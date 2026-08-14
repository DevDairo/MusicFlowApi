use std::{
    io::{Read, Write},
    net::{TcpListener, TcpStream},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::{Duration, Instant},
};

use keyring::{Entry, Error as KeyringError};
use openidconnect::{
    AccessTokenHash, AuthorizationCode, ClientId, CsrfToken, IssuerUrl, Nonce, OAuth2TokenResponse,
    PkceCodeChallenge, RedirectUrl, RefreshToken, RequestTokenError, Scope, TokenResponse,
    UserInfoUrl,
    core::{CoreAuthenticationFlow, CoreErrorResponseType, CoreProviderMetadata},
    reqwest,
    url::Url,
};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, State};
use tauri_plugin_opener::OpenerExt;
use zeroize::Zeroizing;

const ISSUER: &str = "https://auth.kontora-pos.store/realms/musicflow";
const API_BASE_URL: &str = "https://api.kontora-pos.store";
const CLIENT_ID: &str = "musicflow-desktop";
const CALLBACK_PATH: &str = "/";
const LOGIN_TIMEOUT: Duration = Duration::from_secs(180);
const KEYRING_SERVICE: &str = "com.devdairo.musicflow";
const KEYRING_ACCOUNT: &str = "oidc-refresh-token";

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthenticatedUser {
    id: String,
    subject: String,
    username: String,
    display_name: String,
    email: Option<String>,
    email_verified: bool,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthCommandError {
    code: &'static str,
    message: String,
    retryable: bool,
}

impl AuthCommandError {
    fn new(code: &'static str, message: impl Into<String>, retryable: bool) -> Self {
        Self {
            code,
            message: message.into(),
            retryable,
        }
    }

    fn configuration() -> Self {
        Self::new(
            "identity_configuration",
            "La configuracion de identidad no esta disponible. Intentalo mas tarde.",
            true,
        )
    }

    fn connection() -> Self {
        Self::new(
            "identity_unavailable",
            "No fue posible conectar con el servicio de identidad.",
            true,
        )
    }
}

struct NativeSession {
    user: AuthenticatedUser,
    _access_token: Zeroizing<String>,
    _expires_at: Instant,
}

#[derive(Default)]
struct RuntimeData {
    session: Option<NativeSession>,
    login_in_progress: bool,
}

#[derive(Clone, Default)]
pub struct AuthRuntime {
    data: Arc<Mutex<RuntimeData>>,
    cancel_requested: Arc<AtomicBool>,
}

struct LoginGuard {
    runtime: AuthRuntime,
}

impl LoginGuard {
    fn acquire(runtime: AuthRuntime) -> Result<Self, AuthCommandError> {
        let mut data = runtime.data.lock().map_err(|_| {
            AuthCommandError::new(
                "session_unavailable",
                "La sesion local no esta disponible.",
                true,
            )
        })?;
        if data.login_in_progress {
            return Err(AuthCommandError::new(
                "login_in_progress",
                "Ya existe un acceso en curso. Completa la ventana del navegador.",
                false,
            ));
        }
        data.login_in_progress = true;
        runtime.cancel_requested.store(false, Ordering::Release);
        drop(data);

        Ok(Self { runtime })
    }
}

impl Drop for LoginGuard {
    fn drop(&mut self) {
        if let Ok(mut data) = self.runtime.data.lock() {
            data.login_in_progress = false;
        }
        self.runtime
            .cancel_requested
            .store(false, Ordering::Release);
    }
}

#[derive(Debug)]
struct CallbackParameters {
    code: AuthorizationCode,
}

#[derive(Debug, Deserialize)]
struct UserInfoResponse {
    sub: String,
    preferred_username: Option<String>,
    name: Option<String>,
    email: Option<String>,
    #[serde(default)]
    email_verified: bool,
}

#[derive(Debug, Deserialize)]
struct CurrentIdentityResponse {
    id: String,
}

fn http_client() -> Result<reqwest::blocking::Client, AuthCommandError> {
    reqwest::blocking::ClientBuilder::new()
        .redirect(reqwest::redirect::Policy::none())
        .connect_timeout(Duration::from_secs(10))
        .timeout(Duration::from_secs(20))
        .build()
        .map_err(|_| AuthCommandError::connection())
}

fn discover_provider(
    client: &reqwest::blocking::Client,
) -> Result<CoreProviderMetadata, AuthCommandError> {
    let issuer =
        IssuerUrl::new(ISSUER.to_owned()).map_err(|_| AuthCommandError::configuration())?;
    CoreProviderMetadata::discover(&issuer, client).map_err(|_| AuthCommandError::connection())
}

fn current_identity_from_response(
    status: reqwest::StatusCode,
    body: &str,
) -> Result<CurrentIdentityResponse, AuthCommandError> {
    if status == reqwest::StatusCode::UNAUTHORIZED || status == reqwest::StatusCode::FORBIDDEN {
        return Err(AuthCommandError::new(
            "api_token_rejected",
            "La API no acepto la sesion de identidad. Inicia sesion nuevamente.",
            false,
        ));
    }
    if status == reqwest::StatusCode::SERVICE_UNAVAILABLE {
        return Err(AuthCommandError::new(
            "api_unavailable",
            "MusicFlow no puede validar tu cuenta en este momento.",
            true,
        ));
    }
    if !status.is_success() {
        return Err(AuthCommandError::new(
            "api_unexpected_response",
            "MusicFlow respondio de forma inesperada al validar tu cuenta.",
            true,
        ));
    }

    let identity: CurrentIdentityResponse = serde_json::from_str(body).map_err(|_| {
        AuthCommandError::new(
            "api_contract_invalid",
            "MusicFlow devolvio una identidad que no cumple el contrato esperado.",
            true,
        )
    })?;
    if identity.id.is_empty() || identity.id.len() > 64 {
        return Err(AuthCommandError::new(
            "api_contract_invalid",
            "MusicFlow devolvio una identidad que no cumple el contrato esperado.",
            true,
        ));
    }

    Ok(identity)
}

fn resolve_current_identity(
    http: &reqwest::blocking::Client,
    access_token: &str,
) -> Result<CurrentIdentityResponse, AuthCommandError> {
    let response = http
        .get(format!("{API_BASE_URL}/v1/me"))
        .bearer_auth(access_token)
        .send()
        .map_err(|_| {
            AuthCommandError::new(
                "api_unavailable",
                "No fue posible conectar con la API de MusicFlow.",
                true,
            )
        })?;
    let status = response.status();
    let body = response.text().map_err(|_| {
        AuthCommandError::new(
            "api_contract_invalid",
            "MusicFlow devolvio una respuesta que no se pudo interpretar.",
            true,
        )
    })?;

    current_identity_from_response(status, &body)
}

fn credential_entry() -> Result<Entry, AuthCommandError> {
    Entry::new(KEYRING_SERVICE, KEYRING_ACCOUNT).map_err(|_| {
        AuthCommandError::new(
            "secure_store_unavailable",
            "Windows Credential Manager no esta disponible para proteger la sesion.",
            false,
        )
    })
}

fn store_refresh_token(token: &str) -> Result<(), AuthCommandError> {
    credential_entry()?.set_password(token).map_err(|_| {
        AuthCommandError::new(
            "secure_store_write_failed",
            "No se pudo proteger la sesion en Windows Credential Manager.",
            false,
        )
    })
}

fn load_refresh_token() -> Result<Option<Zeroizing<String>>, AuthCommandError> {
    match credential_entry()?.get_password() {
        Ok(token) => Ok(Some(Zeroizing::new(token))),
        Err(KeyringError::NoEntry) => Ok(None),
        Err(_) => Err(AuthCommandError::new(
            "secure_store_read_failed",
            "No se pudo leer la sesion protegida de Windows Credential Manager.",
            true,
        )),
    }
}

fn delete_refresh_token() -> Result<(), AuthCommandError> {
    match credential_entry()?.delete_credential() {
        Ok(()) | Err(KeyringError::NoEntry) => Ok(()),
        Err(_) => Err(AuthCommandError::new(
            "secure_store_delete_failed",
            "No se pudo eliminar por completo la sesion protegida.",
            true,
        )),
    }
}

fn session_from_token_response(
    http: &reqwest::blocking::Client,
    userinfo_endpoint: &UserInfoUrl,
    token_response: &openidconnect::core::CoreTokenResponse,
    expected_subject: Option<&str>,
) -> Result<NativeSession, AuthCommandError> {
    let userinfo = http
        .get(userinfo_endpoint.as_str())
        .bearer_auth(token_response.access_token().secret())
        .send()
        .and_then(reqwest::blocking::Response::error_for_status)
        .map_err(|_| AuthCommandError::connection())?;
    let userinfo_body = userinfo
        .text()
        .map_err(|_| AuthCommandError::connection())?;
    let userinfo: UserInfoResponse =
        serde_json::from_str(&userinfo_body).map_err(|_| AuthCommandError::configuration())?;
    if expected_subject.is_some_and(|subject| subject != userinfo.sub) {
        return Err(AuthCommandError::new(
            "userinfo_subject_mismatch",
            "El perfil recibido no coincide con la identidad verificada.",
            false,
        ));
    }
    let internal_identity = resolve_current_identity(http, token_response.access_token().secret())?;
    let username = userinfo
        .preferred_username
        .unwrap_or_else(|| userinfo.sub.clone());
    let display_name = userinfo.name.unwrap_or_else(|| username.clone());
    let expires_in = token_response
        .expires_in()
        .unwrap_or_else(|| Duration::from_secs(600));

    Ok(NativeSession {
        user: AuthenticatedUser {
            id: internal_identity.id,
            subject: userinfo.sub,
            username,
            display_name,
            email: userinfo.email,
            email_verified: userinfo.email_verified,
        },
        _access_token: Zeroizing::new(token_response.access_token().secret().to_owned()),
        _expires_at: Instant::now() + expires_in,
    })
}

fn browser_response(success: bool) -> String {
    let (title, message, accent) = if success {
        (
            "Retorno recibido",
            "MusicFlow recibio el retorno. Ya puedes cerrar esta pestana y continuar en la aplicacion.",
            "#58e0b5",
        )
    } else {
        (
            "No se completo el acceso",
            "Vuelve a MusicFlow para intentarlo nuevamente.",
            "#fb7185",
        )
    };
    let body = format!(
        "<!doctype html><html lang=\"es\"><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>{title}</title><style>body{{margin:0;min-height:100vh;display:grid;place-items:center;background:#06110f;color:#effcf7;font-family:system-ui,sans-serif}}main{{width:min(30rem,calc(100% - 3rem));padding:2.5rem;border:1px solid #ffffff18;border-radius:1.5rem;background:#ffffff08;box-shadow:0 2rem 5rem #0008}}i{{display:block;width:1rem;height:1rem;border-radius:50%;background:{accent};box-shadow:0 0 0 .5rem {accent}22}}h1{{margin:1.5rem 0 .75rem;font-size:2rem}}p{{margin:0;color:#9db8af;line-height:1.6}}</style><main><i></i><h1>{title}</h1><p>{message}</p></main></html>"
    );
    let status = if success { "200 OK" } else { "400 Bad Request" };
    format!(
        "HTTP/1.1 {status}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'; style-src 'unsafe-inline'\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n{body}",
        body.len()
    )
}

fn write_browser_response(stream: &mut TcpStream, success: bool) {
    let response = browser_response(success);
    let _ = stream.write_all(response.as_bytes());
    let _ = stream.flush();
}

fn parse_callback_target(
    target: &str,
    expected_port: u16,
    expected_state: &CsrfToken,
) -> Result<CallbackParameters, AuthCommandError> {
    if !target.starts_with('/') {
        return Err(AuthCommandError::new(
            "callback_invalid",
            "El retorno de acceso no coincide con la solicitud iniciada.",
            true,
        ));
    }

    let callback_url =
        Url::parse(&format!("http://127.0.0.1:{expected_port}{target}")).map_err(|_| {
            AuthCommandError::new(
                "callback_invalid",
                "El retorno de acceso no fue valido.",
                true,
            )
        })?;
    if callback_url.path() != CALLBACK_PATH {
        return Err(AuthCommandError::new(
            "callback_invalid",
            "El retorno de acceso no coincide con la solicitud iniciada.",
            true,
        ));
    }

    let parameter = |name: &str| -> Result<Option<String>, AuthCommandError> {
        let mut values = callback_url
            .query_pairs()
            .filter(|(key, _)| key == name)
            .map(|(_, value)| value.into_owned());
        let value = values.next();
        if values.next().is_some() {
            return Err(AuthCommandError::new(
                "callback_invalid",
                "El retorno de acceso contiene parametros duplicados.",
                false,
            ));
        }
        Ok(value)
    };

    if let Some(error) = parameter("error")? {
        let message = if error == "access_denied" {
            "El acceso fue cancelado en el navegador."
        } else {
            "Keycloak rechazo la solicitud de acceso."
        };
        return Err(AuthCommandError::new("authorization_denied", message, true));
    }

    let returned_state = parameter("state")?
        .filter(|value| !value.is_empty())
        .map(CsrfToken::new)
        .ok_or_else(|| {
            AuthCommandError::new(
                "state_missing",
                "El retorno no incluyo su estado de seguridad.",
                true,
            )
        })?;
    if &returned_state != expected_state {
        return Err(AuthCommandError::new(
            "state_mismatch",
            "El retorno de acceso no coincide con la solicitud iniciada.",
            true,
        ));
    }

    let code = parameter("code")?
        .filter(|value| !value.is_empty())
        .map(AuthorizationCode::new)
        .ok_or_else(|| {
            AuthCommandError::new(
                "code_missing",
                "Keycloak no devolvio un codigo de acceso.",
                true,
            )
        })?;
    Ok(CallbackParameters { code })
}

fn receive_callback(
    listener: TcpListener,
    expected_port: u16,
    expected_state: &CsrfToken,
    cancel_requested: &AtomicBool,
) -> Result<CallbackParameters, AuthCommandError> {
    listener.set_nonblocking(true).map_err(|_| {
        AuthCommandError::new(
            "callback_failed",
            "No se pudo preparar el retorno local.",
            true,
        )
    })?;
    let deadline = Instant::now() + LOGIN_TIMEOUT;

    loop {
        if cancel_requested.load(Ordering::Acquire) {
            return Err(AuthCommandError::new(
                "login_cancelled",
                "El acceso fue cancelado.",
                true,
            ));
        }
        if Instant::now() >= deadline {
            return Err(AuthCommandError::new(
                "login_timeout",
                "El acceso expiro antes de completarse. Intentalo nuevamente.",
                true,
            ));
        }

        match listener.accept() {
            Ok((mut stream, address)) => {
                if !address.ip().is_loopback() {
                    continue;
                }
                let _ = stream.set_read_timeout(Some(Duration::from_secs(3)));
                let mut buffer = [0_u8; 8192];
                let read = stream.read(&mut buffer).map_err(|_| {
                    AuthCommandError::new(
                        "callback_invalid",
                        "El retorno de acceso no fue valido.",
                        true,
                    )
                })?;
                let request = std::str::from_utf8(&buffer[..read]).map_err(|_| {
                    AuthCommandError::new(
                        "callback_invalid",
                        "El retorno de acceso no fue valido.",
                        true,
                    )
                })?;
                let mut lines = request.split("\r\n");
                let request_line = lines.next().unwrap_or_default();
                let mut parts = request_line.split_whitespace();
                let method = parts.next().unwrap_or_default();
                let target = parts.next().unwrap_or_default();
                let host = lines
                    .find_map(|line| {
                        line.strip_prefix("Host: ")
                            .or_else(|| line.strip_prefix("host: "))
                    })
                    .unwrap_or_default();

                if method != "GET" || host != format!("127.0.0.1:{expected_port}") {
                    write_browser_response(&mut stream, false);
                    return Err(AuthCommandError::new(
                        "callback_invalid",
                        "El retorno de acceso no coincide con la solicitud iniciada.",
                        true,
                    ));
                }

                match parse_callback_target(target, expected_port, expected_state) {
                    Ok(callback) => {
                        write_browser_response(&mut stream, true);
                        return Ok(callback);
                    }
                    Err(error) => {
                        write_browser_response(&mut stream, false);
                        return Err(error);
                    }
                }
            }
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(80));
            }
            Err(_) => {
                return Err(AuthCommandError::new(
                    "callback_failed",
                    "No se pudo recibir el retorno seguro del navegador.",
                    true,
                ));
            }
        }
    }
}

impl AuthRuntime {
    fn login_blocking(&self, app: &AppHandle) -> Result<AuthenticatedUser, AuthCommandError> {
        let _guard = LoginGuard::acquire(self.clone())?;
        let listener = TcpListener::bind(("127.0.0.1", 0)).map_err(|_| {
            AuthCommandError::new(
                "callback_bind_failed",
                "No se pudo abrir el retorno local para completar el acceso.",
                true,
            )
        })?;
        let callback_port = listener
            .local_addr()
            .map_err(|_| AuthCommandError::configuration())?
            .port();
        let redirect_uri = RedirectUrl::new(format!("http://127.0.0.1:{callback_port}"))
            .map_err(|_| AuthCommandError::configuration())?;
        let http = http_client()?;
        let metadata = discover_provider(&http)?;
        let userinfo_endpoint = metadata
            .userinfo_endpoint()
            .cloned()
            .ok_or_else(AuthCommandError::configuration)?;
        let client = openidconnect::core::CoreClient::from_provider_metadata(
            metadata,
            ClientId::new(CLIENT_ID.to_owned()),
            None,
        )
        .set_redirect_uri(redirect_uri);
        let (pkce_challenge, pkce_verifier) = PkceCodeChallenge::new_random_sha256();
        let (authorization_url, csrf_state, nonce) = client
            .authorize_url(
                CoreAuthenticationFlow::AuthorizationCode,
                CsrfToken::new_random,
                Nonce::new_random,
            )
            .add_scope(Scope::new("profile".to_owned()))
            .add_scope(Scope::new("email".to_owned()))
            .set_pkce_challenge(pkce_challenge)
            .url();

        app.opener()
            .open_url(authorization_url.as_str(), None::<&str>)
            .map_err(|_| {
                AuthCommandError::new(
                    "browser_open_failed",
                    "No se pudo abrir el navegador predeterminado.",
                    true,
                )
            })?;

        let callback =
            receive_callback(listener, callback_port, &csrf_state, &self.cancel_requested)?;
        let token_response = client
            .exchange_code(callback.code)
            .map_err(|_| AuthCommandError::configuration())?
            .set_pkce_verifier(pkce_verifier)
            .request(&http)
            .map_err(|_| {
                AuthCommandError::new(
                    "code_exchange_failed",
                    "Keycloak no pudo completar el acceso. Intentalo nuevamente.",
                    true,
                )
            })?;

        let id_token = token_response.id_token().ok_or_else(|| {
            AuthCommandError::new(
                "id_token_missing",
                "Keycloak no devolvio la identidad esperada.",
                true,
            )
        })?;
        let claims = id_token
            .claims(&client.id_token_verifier(), &nonce)
            .map_err(|_| {
                AuthCommandError::new(
                    "id_token_invalid",
                    "La identidad recibida no supero la verificacion de seguridad.",
                    true,
                )
            })?;
        if let Some(expected_hash) = claims.access_token_hash() {
            let actual_hash = AccessTokenHash::from_token(
                token_response.access_token(),
                id_token
                    .signing_alg()
                    .map_err(|_| AuthCommandError::configuration())?,
                id_token
                    .signing_key(&client.id_token_verifier())
                    .map_err(|_| AuthCommandError::configuration())?,
            )
            .map_err(|_| AuthCommandError::configuration())?;
            if actual_hash != *expected_hash {
                return Err(AuthCommandError::new(
                    "access_token_mismatch",
                    "La sesion recibida no coincide con la identidad verificada.",
                    false,
                ));
            }
        }

        let refresh_token = token_response.refresh_token().ok_or_else(|| {
            AuthCommandError::new(
                "refresh_token_missing",
                "Keycloak no permitio conservar una sesion segura.",
                true,
            )
        })?;
        let session = session_from_token_response(
            &http,
            &userinfo_endpoint,
            &token_response,
            Some(claims.subject().as_str()),
        )?;
        store_refresh_token(refresh_token.secret())?;
        let user = session.user.clone();
        self.data
            .lock()
            .map_err(|_| AuthCommandError::configuration())?
            .session = Some(session);
        Ok(user)
    }

    fn restore_blocking(&self) -> Result<Option<AuthenticatedUser>, AuthCommandError> {
        {
            let mut data = self
                .data
                .lock()
                .map_err(|_| AuthCommandError::configuration())?;
            if let Some(session) = data.session.as_ref()
                && session._expires_at > Instant::now() + Duration::from_secs(30)
            {
                return Ok(Some(session.user.clone()));
            }
            data.session = None;
        }

        let Some(refresh_token) = load_refresh_token()? else {
            return Ok(None);
        };
        let http = http_client()?;
        let metadata = discover_provider(&http)?;
        let userinfo_endpoint = metadata
            .userinfo_endpoint()
            .cloned()
            .ok_or_else(AuthCommandError::configuration)?;
        let client = openidconnect::core::CoreClient::from_provider_metadata(
            metadata,
            ClientId::new(CLIENT_ID.to_owned()),
            None,
        );
        let refresh = RefreshToken::new(refresh_token.to_string());
        let token_response = match client
            .exchange_refresh_token(&refresh)
            .map_err(|_| AuthCommandError::configuration())?
            .request(&http)
        {
            Ok(response) => response,
            Err(RequestTokenError::ServerResponse(error))
                if error.error() == &CoreErrorResponseType::InvalidGrant =>
            {
                delete_refresh_token()?;
                return Ok(None);
            }
            Err(_) => return Err(AuthCommandError::connection()),
        };

        if let Some(rotated_refresh_token) = token_response.refresh_token() {
            store_refresh_token(rotated_refresh_token.secret())?;
        }
        let session =
            session_from_token_response(&http, &userinfo_endpoint, &token_response, None)?;
        let user = session.user.clone();
        self.data
            .lock()
            .map_err(|_| AuthCommandError::configuration())?
            .session = Some(session);
        Ok(Some(user))
    }

    fn logout_blocking(&self) -> Result<(), AuthCommandError> {
        let refresh_token = load_refresh_token()?;
        if let Some(refresh_token) = refresh_token {
            if let Ok(http) = http_client() {
                let logout_url = format!("{ISSUER}/protocol/openid-connect/logout");
                let _ = http
                    .post(logout_url)
                    .form(&[
                        ("client_id", CLIENT_ID),
                        ("refresh_token", refresh_token.as_str()),
                    ])
                    .send();
            }
        }

        delete_refresh_token()?;
        self.data
            .lock()
            .map_err(|_| AuthCommandError::configuration())?
            .session = None;
        Ok(())
    }

    fn cancel_login(&self) {
        self.cancel_requested.store(true, Ordering::Release);
    }
}

#[tauri::command]
pub async fn login(
    app: AppHandle,
    runtime: State<'_, AuthRuntime>,
) -> Result<AuthenticatedUser, AuthCommandError> {
    let runtime = runtime.inner().clone();
    tauri::async_runtime::spawn_blocking(move || runtime.login_blocking(&app))
        .await
        .map_err(|_| AuthCommandError::configuration())?
}

#[tauri::command]
pub async fn get_current_user(
    runtime: State<'_, AuthRuntime>,
) -> Result<Option<AuthenticatedUser>, AuthCommandError> {
    let runtime = runtime.inner().clone();
    tauri::async_runtime::spawn_blocking(move || runtime.restore_blocking())
        .await
        .map_err(|_| AuthCommandError::configuration())?
}

#[tauri::command]
pub async fn logout(runtime: State<'_, AuthRuntime>) -> Result<(), AuthCommandError> {
    let runtime = runtime.inner().clone();
    tauri::async_runtime::spawn_blocking(move || runtime.logout_blocking())
        .await
        .map_err(|_| AuthCommandError::configuration())?
}

#[tauri::command]
pub fn cancel_login(runtime: State<'_, AuthRuntime>) {
    runtime.cancel_login();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn browser_response_is_ephemeral_and_does_not_reference_tokens() {
        let response = browser_response(true);

        assert!(response.contains("Cache-Control: no-store"));
        assert!(response.contains("Content-Security-Policy: default-src 'none'"));
        assert!(response.contains("Ya puedes cerrar esta pestana"));
        assert!(!response.contains("musicflow://"));
        assert!(!response.contains("<script"));
        assert!(!response.contains("window.close"));
        assert!(!response.contains("access_token"));
        assert!(!response.contains("refresh_token"));
        assert!(!response.contains("authorization_code"));
    }

    #[test]
    fn api_identity_contract_accepts_a_stable_identifier() {
        let identity = current_identity_from_response(
            reqwest::StatusCode::OK,
            r#"{"id":"8f5a6eb8-68e0-4ddd-9660-0c82a32f8af5"}"#,
        )
        .expect("a valid identity contract must be accepted");

        assert_eq!(identity.id, "8f5a6eb8-68e0-4ddd-9660-0c82a32f8af5");
    }

    #[test]
    fn api_identity_contract_rejects_an_unauthorized_token() {
        let error = current_identity_from_response(reqwest::StatusCode::UNAUTHORIZED, "")
            .expect_err("an unauthorized token must be rejected");

        assert_eq!(error.code, "api_token_rejected");
        assert!(!error.retryable);
    }

    #[test]
    fn api_identity_contract_rejects_invalid_json() {
        let error = current_identity_from_response(reqwest::StatusCode::OK, "not-json")
            .expect_err("an invalid API contract must be rejected");

        assert_eq!(error.code, "api_contract_invalid");
    }

    #[test]
    fn accepts_exact_loopback_root_callback() {
        let state = CsrfToken::new("expected-state".to_owned());

        let callback = parse_callback_target(
            "/?code=authorization-code&state=expected-state",
            54321,
            &state,
        )
        .expect("the callback should be valid");

        assert_eq!(callback.code.secret(), "authorization-code");
    }

    #[test]
    fn rejects_callback_with_additional_path() {
        let state = CsrfToken::new("expected-state".to_owned());

        let error = parse_callback_target(
            "/callback?code=authorization-code&state=expected-state",
            54321,
            &state,
        )
        .expect_err("the path must be rejected");

        assert_eq!(error.code, "callback_invalid");
    }

    #[test]
    fn rejects_callback_with_wrong_state() {
        let state = CsrfToken::new("expected-state".to_owned());

        let error = parse_callback_target(
            "/?code=authorization-code&state=attacker-state",
            54321,
            &state,
        )
        .expect_err("the state must be rejected");

        assert_eq!(error.code, "state_mismatch");
    }

    #[test]
    fn rejects_callback_with_duplicate_security_parameter() {
        let state = CsrfToken::new("expected-state".to_owned());

        let error = parse_callback_target(
            "/?code=authorization-code&state=expected-state&state=expected-state",
            54321,
            &state,
        )
        .expect_err("duplicate state values must be rejected");

        assert_eq!(error.code, "callback_invalid");
    }
}

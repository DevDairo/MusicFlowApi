import { useEffect, useState, type CSSProperties } from "react";

import { authClient } from "./auth/client";
import {
  authErrorCode,
  describeAuthError,
  type AuthUiState,
  type AuthenticatedUser,
} from "./auth/contracts";

function BrandMark() {
  return (
    <span className="brand-mark" aria-hidden="true">
      <i />
      <i />
      <i />
      <i />
    </span>
  );
}

function BrowserIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <rect x="3" y="4" width="18" height="16" rx="3" />
      <path d="M3 9h18M7 6.5h.01M10 6.5h.01" />
    </svg>
  );
}

function ShieldIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M12 3 5 6v5c0 4.7 2.8 8 7 10 4.2-2 7-5.3 7-10V6l-7-3Z" />
      <path d="m9 12 2 2 4-4" />
    </svg>
  );
}

function ArrowIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M5 12h14m-5-5 5 5-5 5" />
    </svg>
  );
}

function initials(user: AuthenticatedUser): string {
  const source = user.displayName.trim() || user.username;
  return source
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? "")
    .join("");
}

type AuthPanelProps = Readonly<{
  state: AuthUiState;
  registrationExpanded: boolean;
  onLogin: () => void;
  onCancel: () => void;
  onLogout: () => void;
  onToggleRegistration: () => void;
}>;

export function AuthPanel({
  state,
  registrationExpanded,
  onLogin,
  onCancel,
  onLogout,
  onToggleRegistration,
}: AuthPanelProps) {
  if (state.kind === "restoring") {
    return (
      <section className="auth-card auth-card--centered" aria-live="polite">
        <span className="loading-ring" aria-hidden="true" />
        <p className="panel-kicker">Protegiendo tu sesion</p>
        <h1>Preparando MusicFlow</h1>
        <p className="panel-copy">
          Estamos comprobando de forma segura si ya habias iniciado sesion.
        </p>
      </section>
    );
  }

  if (state.kind === "signingIn") {
    return (
      <section className="auth-card" aria-live="polite">
        <span className="loading-ring" aria-hidden="true" />
        <p className="panel-kicker">Acceso en curso</p>
        <h1>Continua en tu navegador</h1>
        <p className="panel-copy">
          Inicia sesion en la ventana segura que acabamos de abrir. MusicFlow se
          actualizara automaticamente al terminar.
        </p>
        <ol className="flow-steps">
          <li className="flow-steps__done">Navegador abierto</li>
          <li className="flow-steps__active">Confirma tu identidad</li>
          <li>Regresa a MusicFlow</li>
        </ol>
        <button
          className="button button--secondary"
          type="button"
          onClick={onCancel}
        >
          Cancelar acceso
        </button>
        <p className="microcopy">
          La solicitud expira automaticamente en 3 minutos.
        </p>
      </section>
    );
  }

  if (state.kind === "signedIn") {
    return (
      <section className="auth-card" aria-live="polite">
        <div className="profile-row">
          <span className="avatar" aria-hidden="true">
            {initials(state.user)}
          </span>
          <span className="session-badge">
            <i /> Sesion protegida
          </span>
        </div>
        <p className="panel-kicker">Todo esta listo</p>
        <h1>Hola, {state.user.displayName}</h1>
        <p className="panel-copy">
          Tu identidad fue verificada. Ya puedes continuar hacia las funciones
          que iremos habilitando en MusicFlow.
        </p>
        <div className="account-summary">
          <span>Cuenta</span>
          <strong>{state.user.email ?? state.user.username}</strong>
        </div>
        <button className="button button--primary" type="button" disabled>
          Ir a MusicFlow
          <ArrowIcon />
        </button>
        <button className="text-button" type="button" onClick={onLogout}>
          Cerrar sesion en este equipo
        </button>
      </section>
    );
  }

  const hasError = state.kind === "error";

  return (
    <section className="auth-card" aria-live="polite">
      <div className="security-label">
        <ShieldIcon />
        Acceso protegido con PKCE
      </div>
      <p className="panel-kicker">Bienvenido a MusicFlow</p>
      <h1>
        {hasError ? "No pudimos completar el acceso" : "Tu musica empieza aqui"}
      </h1>
      <p className={`panel-copy${hasError ? " panel-copy--error" : ""}`}>
        {hasError
          ? state.message
          : "Inicia sesion para gestionar tus descargas y conservar una experiencia personal en este equipo."}
      </p>

      <button
        className="button button--primary"
        type="button"
        onClick={onLogin}
        disabled={hasError && !state.retryable}
      >
        {hasError ? "Intentar nuevamente" : "Continuar con MusicFlow"}
        <ArrowIcon />
      </button>

      <div className="trust-grid" aria-label="Protecciones del acceso">
        <div>
          <BrowserIcon />
          <span>
            <strong>Navegador del sistema</strong>
            MusicFlow nunca ve tu contraseña
          </span>
        </div>
        <div>
          <ShieldIcon />
          <span>
            <strong>Sesion protegida</strong>
            Guardada por Windows
          </span>
        </div>
      </div>

      <div className="registration">
        <p>
          ¿Aun no tienes cuenta?{" "}
          <button
            type="button"
            onClick={onToggleRegistration}
            aria-expanded={registrationExpanded}
          >
            Crear cuenta
          </button>
        </p>
        {registrationExpanded ? (
          <div className="registration-note" role="status">
            <strong>Registro por invitacion durante la beta</strong>
            <span>
              Estamos preparando verificacion de correo y recuperacion segura
              antes de abrir el registro publico.
            </span>
          </div>
        ) : null}
      </div>
    </section>
  );
}

export function App() {
  const [state, setState] = useState<AuthUiState>({ kind: "restoring" });
  const [registrationExpanded, setRegistrationExpanded] = useState(false);

  useEffect(() => {
    let active = true;

    void authClient
      .currentUser()
      .then((user) => {
        if (active) {
          setState(user ? { kind: "signedIn", user } : { kind: "signedOut" });
        }
      })
      .catch((error: unknown) => {
        if (active) {
          setState({ kind: "error", ...describeAuthError(error) });
        }
      });

    return () => {
      active = false;
    };
  }, []);

  async function handleLogin() {
    setRegistrationExpanded(false);
    setState({ kind: "signingIn" });
    try {
      const user = await authClient.login();
      setState({ kind: "signedIn", user });
    } catch (error) {
      if (authErrorCode(error) === "login_cancelled") {
        setState({ kind: "signedOut" });
        return;
      }
      setState({ kind: "error", ...describeAuthError(error) });
    }
  }

  async function handleCancel() {
    try {
      await authClient.cancelLogin();
    } finally {
      setState({ kind: "signedOut" });
    }
  }

  async function handleLogout() {
    setState({ kind: "restoring" });
    try {
      await authClient.logout();
      setState({ kind: "signedOut" });
    } catch (error) {
      setState({ kind: "error", ...describeAuthError(error) });
    }
  }

  return (
    <main className="app-shell">
      <section className="story-panel" aria-labelledby="brand-title">
        <header className="brand-lockup">
          <BrandMark />
          <span>MusicFlow</span>
        </header>
        <div className="story-copy">
          <p className="story-kicker">Tu audio. Sin compromisos.</p>
          <h2 id="brand-title">La mejor version de tu musica, en tus manos.</h2>
          <p>
            Descarga, procesa y organiza audio de alta calidad desde una
            experiencia creada para tu escritorio.
          </p>
        </div>
        <div className="soundscape" aria-hidden="true">
          {Array.from({ length: 38 }, (_, index) => (
            <i
              key={index}
              style={
                {
                  "--bar-height": `${18 + ((index * 37) % 74)}%`,
                } as CSSProperties
              }
            />
          ))}
        </div>
        <footer className="story-footer">
          <span>Calidad compatible</span>
          <i />
          <span>Metadatos completos</span>
          <i />
          <span>Procesamiento privado</span>
        </footer>
      </section>

      <section className="access-panel">
        <div className="mobile-brand">
          <BrandMark />
          <span>MusicFlow</span>
        </div>
        <AuthPanel
          state={state}
          registrationExpanded={registrationExpanded}
          onLogin={() => void handleLogin()}
          onCancel={() => void handleCancel()}
          onLogout={() => void handleLogout()}
          onToggleRegistration={() =>
            setRegistrationExpanded((value) => !value)
          }
        />
        <p className="legal-copy">
          Al continuar aceptas el uso seguro de identidad necesario para acceder
          a MusicFlow.
        </p>
      </section>
    </main>
  );
}

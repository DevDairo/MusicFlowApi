# Fase 2 — incremento 4: acceso nativo con OIDC

## 1. Objetivo

Integrar el cliente Tauri instalado en Windows con el realm `musicflow` de
Keycloak mediante Authorization Code Flow con PKCE, sin entregar credenciales
ni tokens a React. El incremento también prepara una cuenta final controlada y
una experiencia visual coherente entre la aplicación y el formulario externo
de identidad.

Este incremento no habilita todavía registro público, recuperación por correo,
validación JWT en la API ni endpoints de negocio.

## 2. Decisiones

- El navegador predeterminado del sistema recoge usuario, contraseña y futuros
  factores; la WebView nunca los solicita.
- Tauri escucha temporalmente en `127.0.0.1` con un puerto asignado por el
  sistema y usa el redirect exacto `http://127.0.0.1:<puerto>`.
- El cliente es público, sin `client_secret`, y exige PKCE `S256`, `state` y
  `nonce` nuevos por intento.
- El access token solo existe en memoria nativa; el refresh token se guarda en
  el almacén de credenciales del sistema operativo mediante `keyring`.
- React solo recibe un perfil mínimo: subject, usuario, nombre, correo y estado
  de verificación. No recibe tokens ni errores internos.
- El cierre de sesión revoca de forma best effort en Keycloak, elimina la
  credencial local y limpia la sesión en memoria.
- La restauración rota el refresh token y renueva una sesión próxima a vencer.

## 3. Contrato loopback comprobado

Keycloak configura la URI especial `http://127.0.0.1`, que autoriza un puerto
efímero para aplicaciones nativas. La comprobación contra el realm publicado
demostró:

| Redirect solicitado               |                              Resultado |
| --------------------------------- | -------------------------------------: |
| `http://127.0.0.1:54321`          |              200, formulario de acceso |
| `http://127.0.0.1:54321/`         | 400, `Invalid parameter: redirect_uri` |
| `http://127.0.0.1:54321/callback` | 400, `Invalid parameter: redirect_uri` |

Por ello el listener acepta únicamente el path raíz que genera el navegador.
También comprueba método GET, cabecera `Host` exacta, origen loopback, path,
estado en tiempo constante, parámetros únicos, expiración y cancelación.

No se configuraron comodines. Ampliar el redirect habría aumentado la
superficie de intercepción del código de autorización sin aportar valor.

## 4. Experiencia de usuario

La aplicación presenta una pantalla de acceso responsiva con estados
explícitos:

- restaurando sesión;
- sin sesión;
- esperando el navegador;
- sesión iniciada;
- error seguro y recuperable.

El botón principal abre el navegador externo. La pantalla explica por qué las
credenciales no se introducen dentro de la aplicación y permite cancelar el
intento. Después del retorno muestra el perfil mínimo y permite cerrar sesión.

Keycloak incluye el tema `musicflow`, basado en las plantillas oficiales
`keycloak.v2`. Solo se versionan CSS y configuración para reducir el costo de
actualización. El realm usa español como idioma predeterminado e inglés como
alternativa.

La opción **Crear cuenta** se muestra en la aplicación, pero informa que la beta
es por invitación. Habilitar registro público en este momento sería inseguro:
faltan SMTP, verificación de correo, recuperación, términos y controles
antiabuso. El procedimiento administrativo provisional y el contrato pendiente
están definidos en [Invitaciones y alta controlada durante la beta](18-beta-invitation-runbook.md).

### 4.1 Publicación y validación responsive del tema

El tema de Keycloak pertenece al servicio web de identidad, no al binario Tauri.
Un cambio de CSS se publica reconstruyendo únicamente la imagen de Keycloak:

```powershell
docker compose --profile identity up --detach --build --wait keycloak keycloak-gateway
```

No se recompila ni reinstala MusicFlow. Después de que ambos servicios estén
Healthy, el propietario hace una recarga forzada (`Ctrl+F5`) del formulario y
valida al menos:

- escritorio amplio: título y selector de idioma sin superposición;
- ventana intermedia: tarjeta, inputs y botón dentro del ancho disponible;
- ancho de 540 px o inferior: título e idioma en filas independientes;
- pantalla de poca altura: scroll vertical utilizable y sin recortes;
- foco visible y acceso al control de mostrar contraseña.

## 5. Cuenta beta controlada

`scripts/initialize-identity-secrets.ps1` crea, sin imprimirla, la contraseña
local `.secrets/keycloak-beta-user-password`. El usuario conocido es
`musicflow-beta`.

`scripts/configure-identity-beta-user.ps1`:

1. detiene de forma controlada Keycloak y su gateway;
2. crea un cliente administrativo temporal mediante `bootstrap-admin service`;
3. activa el tema e idioma del realm;
4. crea o verifica la cuenta beta;
5. establece la contraseña únicamente al crearla, respetando su historial;
6. elimina el cliente temporal y comprueba que ya no puede autenticarse;
7. deja PostgreSQL, Keycloak y gateway en estado Healthy.

La imagen de Keycloak debe construirse antes de ejecutar el aprovisionador
cuando cambie el tema:

```powershell
docker compose --profile identity build keycloak
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-identity-beta-user.ps1
```

El secreto nunca debe copiarse a documentación, capturas, commits ni mensajes.

## 6. Seguridad y manejo de errores

- cliente OIDC público, sin secreto embebido;
- discovery y JWKS obtenidos desde el issuer HTTPS exacto;
- cliente HTTP sin redirecciones automáticas y con timeouts;
- validación criptográfica de firma, issuer, audience, nonce y access token hash;
- comparación entre `sub` de ID token y UserInfo;
- código, state, nonce y PKCE no se persisten;
- respuesta loopback con CSP restrictiva, `no-store` y sin valores OIDC;
- errores serializados mediante códigos estables y mensajes no sensibles;
- capability de la WebView sin acceso directo al hostname de identidad ni al
  plugin opener;
- usuario controlado sin permisos administrativos;
- registro público deshabilitado y protección de fuerza bruta conservada.

## 7. Pruebas automatizadas

La puerta del cliente ejecuta todo dentro de Docker:

- Prettier y Oxlint;
- TypeScript y build Vite de producción;
- 22 pruebas web sobre configuración, health, estados de interfaz y redacción de
  errores;
- `cargo fmt` y pruebas Rust;
- 5 pruebas nativas sobre respuesta efímera y callbacks válidos/hostiles;
- compilación cruzada Windows y empaquetado NSIS con `Cargo.lock --locked`.

La consulta local del gateway confirmó que el formulario carga
`musicflow.css`, usa español, no ofrece registro y no conserva el título
genérico en inglés.

Antes del cierre se ejecutaron satisfactoriamente
`verify-desktop.ps1 -SkipInstaller`, `verify-identity.ps1 -Fresh`,
`verify-identity-publication.ps1` y `verify.ps1 -ApiPort 18000`. La primera
ejecución de la regresión general con el puerto predeterminado se detuvo porque
la API principal ya utilizaba `127.0.0.1:8000`; repetirla en el puerto aislado
confirmó que no existía un fallo del código ni de los contenedores.

## 8. Validación manual del propietario

La aceptación visual es responsabilidad del propietario y no se sustituye por
las pruebas automatizadas. Deben comprobarse, en este orden:

1. instalación y primera apertura;
2. composición, legibilidad y foco por teclado en la pantalla nativa;
3. explicación de beta por invitación al pulsar **Crear cuenta**;
4. apertura del navegador y apariencia del formulario MusicFlow en español;
5. error comprensible con contraseña incorrecta;
6. acceso con `musicflow-beta` y el secreto local;
7. retorno automático a la aplicación y perfil esperado;
8. cierre y reapertura con restauración de sesión;
9. cierre de sesión y ausencia de restauración posterior;
10. cancelación y expiración del intento sin bloqueo de la interfaz;
11. comportamiento con Keycloak o Internet temporalmente no disponibles;
12. desinstalación normal de la aplicación.

La interfaz no se considerará aprobada hasta recibir confirmación explícita del
propietario.

El 2026-08-14 el propietario confirmó instalación, apertura, login con la cuenta
beta, callback local y perfil autenticado. La revisión detectó superposición
entre título y selector de idioma en el formulario web; se añadió una corrección
responsive al tema. Una segunda revisión aprobó la composición móvil y señaló
dos ajustes de escritorio: ampliar la tarjeta para evitar el salto del título y
unificar visualmente el ancho del campo de contraseña con el de usuario. Ambos
se corrigieron en el CSS.

Durante la publicación de esta corrección se comprobó que Cloudflare seguía
entregando una copia anterior de `musicflow.css` (`CF-Cache-Status: HIT`) aunque
el contenedor de Keycloak había sido recreado y su archivo coincidía con el
repositorio. El tema versiona desde entonces la URL del recurso mediante el
parámetro `v`; este valor debe incrementarse cuando se modifique el CSS publicado
para invalidar de forma selectiva las cachés de Cloudflare y del navegador.

Una tercera revisión detectó que las etiquetas completas del selector de idioma
se superponían con el título en escritorio. El tema conserva solamente los dos
idiomas aprobados y sobrescribe sus etiquetas visibles como `ES` y `EN`, sin
reemplazar la plantilla de Keycloak. La columna del selector se redujo a 4.5 rem
y posteriormente se amplió la tarjeta para conservar una separación adecuada.

La cuarta revisión solicitó más separación entre el título y el selector corto.
El ancho máximo de la tarjeta de escritorio aumentó de 39 a 43 rem; las reglas
responsive continúan limitando el formulario al ancho disponible en pantallas
pequeñas.

El 2026-08-14 el propietario aprobó explícitamente el resultado visual final.
Con ello quedaron aceptadas las vistas de escritorio y móvil, la uniformidad de
los campos, las etiquetas `ES`/`EN` y la separación entre el título y el selector.

## 9. Límites y siguiente paso

La API aún no valida el access token y la pantalla posterior al acceso es solo
una confirmación de sesión. Una vez aprobada esta puerta, el siguiente
incremento incorporará validación JWT en la API, autorización por identidad y
pruebas negativas entre dos usuarios.

## 10. Control de versiones

El trabajo vive en `feat/phase-2-desktop-login`. Después de aprobar pruebas y
validación manual se integrará mediante merge no fast-forward y se etiquetará
como `phase-2-increment-4`. Conforme a la decisión vigente para la Fase 2, la
rama permanecerá disponible localmente y en `origin` después del merge.

## 11. Referencias

- [Keycloak: asegurar aplicaciones y servicios](https://www.keycloak.org/securing-apps/oidc-layers)
- [Keycloak: temas](https://www.keycloak.org/ui-customization/themes)
- [Tauri: comandos Rust](https://v2.tauri.app/develop/calling-rust/)
- [RFC 8252: OAuth 2.0 para aplicaciones nativas](https://www.rfc-editor.org/rfc/rfc8252)

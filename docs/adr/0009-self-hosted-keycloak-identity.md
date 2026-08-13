# ADR-0009: Autohospedar Keycloak como proveedor OIDC inicial

- Estado: Accepted
- Fecha: 2026-08-13
- Responsables: propietario del proyecto

## Contexto

MusicFlow necesita autenticar una aplicación Tauri pública sin distribuir un
secreto de cliente. La API debe reconocer una identidad verificable antes de
aceptar trabajos y debe conservar una frontera de autorización propia para
impedir accesos entre usuarios.

El proyecto comienza en un equipo local y puede evolucionar a un VPS o servidor
dedicado. El propietario prefiere asumir el costo adicional de operar el
proveedor de identidad para aprender una tecnología abierta y conservar control
sobre usuarios y configuración.

Cloudflare Tunnel ya proporciona DNS, TLS en el extremo público y conectividad
sin puertos abiertos en el router, pero no reemplaza un proveedor OIDC ni la
autorización de la API.

## Decisión

Se usará **Keycloak autohospedado** como proveedor OIDC inicial, bajo estas
restricciones:

- Keycloak se ejecutará en modo de producción mediante una imagen versionada y
  optimizada; `start-dev` solo podrá utilizarse en una prueba desechable que no
  sea accesible desde Internet.
- Tendrá un contenedor PostgreSQL, volumen y credenciales separados de la base
  de datos de MusicFlow. La API no accederá a las tablas internas de Keycloak.
- El realm de aplicación será `musicflow`; el realm `master` quedará reservado a
  administración.
- Tauri se registrará como cliente OIDC público, sin `client_secret`, con
  Standard Flow y PKCE S256 obligatorio.
- La autenticación se realizará en el navegador del sistema y regresará a un
  listener loopback mediante `http://127.0.0.1:{puerto-efímero}`. No se usará
  `localhost`, puerto fijo, WebView embebido ni flujo de contraseña directa.
- El hostname público propuesto es `https://auth.kontora-pos.store`. La
  publicación permitirá solo los paths necesarios de OIDC y recursos del realm;
  no publicará `/admin/`, `/realms/master/`, health ni métricas.
- Antes de esa publicación, el runtime privado usará temporalmente el hostname
  local `http://127.0.0.1:8081`. El cambio de issuer formará parte de una puerta
  explícita y ocurrirá antes de integrar Tauri o la validación de tokens en la
  API; ningún contrato de producción dependerá del issuer local.
- La administración inicial se realizará únicamente desde el host local. Su
  acceso exacto se validará en un spike antes de declarar el despliegue
  operativo.
- La API validará localmente los access tokens con el issuer, audiencia,
  algoritmo, tiempo y JWKS esperados. Un ID token nunca autorizará llamadas a
  la API.
- MusicFlow mapeará la pareja `(issuer, subject)` a un UUID interno. El correo,
  nombre o roles externos no serán claves de propiedad.
- El refresh token se almacenará en el almacén seguro del sistema operativo;
  React no recibirá tokens sin procesar.

La primera topología será de una sola instancia. Alta disponibilidad,
Kubernetes y clustering quedan fuera del MVP hasta que capacidad y operación
real justifiquen su costo.

## Alternativas consideradas

### Auth0 administrado

Reduce el trabajo de parches, backups y disponibilidad, y ofrece una entrada
rápida al MVP. Se descartó como proveedor inicial porque el propietario prioriza
aprender y controlar un sistema de identidad abierto. El uso de estándares OIDC
y del identificador interno permite reevaluarlo sin rediseñar el dominio.

### ZITADEL Cloud o autohospedado

Es una alternativa abierta con buen soporte OIDC. No se seleccionó porque
introducir dos productos de identidad para el mismo aprendizaje no aportaría
valor en esta etapa. Puede evaluarse en una rama separada si Keycloak no supera
la puerta.

### Autenticación propia en FastAPI

Parecería reducir contenedores, pero transferiría a MusicFlow almacenamiento de
contraseñas, recuperación, MFA, protección ante ataques y sesiones. Se rechaza
por riesgo y por no ser una capacidad diferenciadora del producto.

## Consecuencias

### Positivas

- Control sobre identidades, sesiones, políticas y ciclo de actualizaciones.
- Aprendizaje directo de realms, clientes públicos, PKCE, claims, JWKS y
  operación de un proveedor OIDC.
- Ausencia de dependencia contractual para la función básica de autenticación.
- Portabilidad futura: la API depende de OIDC y de identidad interna, no de las
  tablas o APIs administrativas de Keycloak.

### Negativas y riesgos

- MusicFlow asume parches de seguridad, backups, restauración, correo,
  observabilidad, disponibilidad y respuesta a incidentes de identidad.
- Una sola instancia local interrumpe nuevos inicios de sesión cuando el equipo,
  Docker, Internet o el túnel no están disponibles.
- Keycloak y su PostgreSQL consumen memoria y almacenamiento adicionales.
- Una configuración incorrecta del hostname, proxy o rutas puede exponer la
  administración, producir issuers incorrectos o provocar respuestas 403.
- Las actualizaciones mayores requieren revisar notas de migración y probar
  rollback/restauración; no se actualizará automáticamente una etiqueta flotante.

## Validación

La decisión se considerará viable para continuar cuando:

1. Keycloak y su PostgreSQL inicien desde Docker sin instalar dependencias en
   Windows y sin publicar la base de datos.
2. La consola administrativa sea accesible localmente y rechazada desde el
   hostname público.
3. Discovery y los endpoints OIDC del realm `musicflow` sean accesibles mediante
   `https://auth.kontora-pos.store` con un issuer estable.
4. Un cliente público pueda completar Authorization Code + PKCE S256 mediante
   navegador y un puerto loopback efímero.
5. Un callback con `state` incorrecto, código reutilizado o redirect no aprobado
   sea rechazado.
6. Reiniciar Keycloak conserve realm, cliente y administrador permanente.
7. Backup y restauración de la configuración y base de datos tengan un
   procedimiento documentado antes de una beta pública.

## Referencias

- [Keycloak: Securing applications and services](https://www.keycloak.org/securing-apps/oidc-layers)
- [Keycloak: Running in a container](https://www.keycloak.org/server/containers)
- [Keycloak: Configuring for production](https://www.keycloak.org/server/configuration-production)
- [Keycloak: Configuring a reverse proxy](https://www.keycloak.org/server/reverseproxy)
- [RFC 8252: OAuth 2.0 for Native Apps](https://datatracker.ietf.org/doc/html/rfc8252)
- [RFC 9700: OAuth 2.0 Security Best Current Practice](https://www.rfc-editor.org/rfc/rfc9700.html)

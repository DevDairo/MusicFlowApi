# MusicFlow

Aplicación de escritorio para solicitar, procesar y guardar audio con metadatos, diseñada inicialmente para Windows y preparada para evolucionar a macOS y Linux.

> Estado: **Fase 2 — login nativo en validación**
> Versión documental: **0.10.0**
> Fecha de referencia: **2026-08-13**

## Propósito

MusicFlow separará claramente dos productos desplegables:

- **Cliente de escritorio:** aplicación Tauri instalada en el equipo del usuario. Gestiona la experiencia de uso y la biblioteca local.
- **Plataforma de servidor:** API, worker de procesamiento y PostgreSQL en
  contenedores independientes. La API y el proveedor OIDC tienen entradas
  públicas controladas; worker, datos y administración permanecen privados.

El MVP utilizará `yt-dlp` como integración inicial y FFmpeg/FFprobe para el procesamiento. La salida priorizará compatibilidad y calidad perceptual: MP3 VBR de alta calidad con metadatos normalizados. El sistema no prometerá audio Hi-Res cuando la fuente no lo proporcione ni intentará evadir restricciones del proveedor.

## Principios del proyecto

- Correctitud y trazabilidad antes que velocidad de entrega.
- Desarrollo incremental con criterios de aceptación y pruebas por fase.
- Seguridad y privacidad desde el diseño.
- Separación entre cliente, API, procesamiento y persistencia.
- Arquitectura sencilla para el MVP, con puntos de evolución explícitos.
- Cumplimiento de términos, licencias y derechos sobre el contenido.

## Documentación

| Documento                                                                          | Propósito                                                                           |
| ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| [Visión y alcance](docs/00-vision-and-scope.md)                                    | Problema, objetivos, alcance y límites del producto.                                |
| [Especificación de requisitos](docs/01-software-requirements.md)                   | Requisitos funcionales, no funcionales y criterios de aceptación.                   |
| [Arquitectura inicial](docs/02-architecture.md)                                    | Componentes, responsabilidades, flujos y despliegue.                                |
| [Seguridad y cumplimiento](docs/03-security-and-compliance.md)                     | Modelo de amenazas, controles y tratamiento del error 403.                          |
| [Estrategia de pruebas](docs/04-testing-strategy.md)                               | Niveles de prueba y puertas de calidad.                                             |
| [Hoja de ruta](docs/05-roadmap.md)                                                 | Fases de desarrollo y condiciones para avanzar.                                     |
| [Proceso de desarrollo](docs/06-development-process.md)                            | Ciclo de vida, Definition of Done y gestión de cambios.                             |
| [Diagnóstico del beta](docs/07-beta-diagnostic.md)                                 | Hallazgos del código inicial y estrategia de migración.                             |
| [Revisión de salida de Fase 0](docs/08-phase-0-exit-review.md)                     | Evidencia de aprobación y cierre de la fase.                                        |
| [Fase 1 — incremento 1](docs/09-phase-1-increment-1.md)                            | Alcance, verificaciones y evidencia del esqueleto técnico.                          |
| [Flujo manual de control de versiones](docs/10-manual-version-control-workflow.md) | Ramas, validación, merge, etiquetas y recuperación.                                 |
| [Fase 1 — incremento 2](docs/11-phase-1-increment-2-tauri-spike.md)                | Spike Tauri, toolchain Docker y puerta de aceptación del instalador.                |
| [Fase 1 — incremento 3](docs/12-phase-1-increment-3-api-health.md)                 | Configuración segura y consulta limitada al health de la API.                       |
| [Runbook de Cloudflare Tunnel](docs/13-cloudflare-tunnel-runbook.md)               | Inicio, verificación, diagnóstico, detención y rotación del conector.               |
| [Fase 2 — fundamento Keycloak](docs/14-phase-2-keycloak-foundation.md)             | Decisión, frontera de confianza, incrementos, amenazas y pruebas de identidad.      |
| [Fase 2 — incremento 2](docs/15-phase-2-increment-2-keycloak-runtime.md)           | Runtime privado de Keycloak, operación, seguridad, verificaciones e incidencias.    |
| [Fase 2 — incremento 3](docs/16-phase-2-increment-3-oidc-publication.md)           | Publicación OIDC restringida, proxy confiable, migración y matriz pública.          |
| [Fase 2 — incremento 4](docs/17-phase-2-increment-4-desktop-login.md)              | Login Tauri con PKCE, sesión protegida, cuenta beta, tema y validación manual.      |
| [Invitaciones de beta](docs/18-beta-invitation-runbook.md)                         | Alta manual controlada, revocación, límites y contrato de automatización pendiente. |
| [Registro de decisiones](docs/adr/README.md)                                       | Decisiones arquitectónicas y su estado.                                             |

## Decisiones iniciales

- Cliente de escritorio con Tauri 2.
- API, worker y PostgreSQL en contenedores separados.
- La API y el proveedor OIDC son las únicas entradas públicas; worker, bases de
  datos y administración permanecen en redes privadas.
- Acceso remoto inicial mediante Cloudflare Tunnel, sin exponer puertos del host directamente.
- Biblioteca y archivos finales almacenados localmente en el dispositivo del usuario.
- Almacenamiento temporal del servidor mediante volumen de Docker en el MVP, abstraído para permitir un futuro almacenamiento compatible con S3.
- Formato de salida inicial: MP3 compatible de alta calidad, sin reescalado engañoso.

## Estado de implementación

La Fase 0 y los tres incrementos técnicos de la Fase 1 fueron aprobados. La
Fase 2 seleccionó Keycloak autohospedado como proveedor OIDC, implementó su
runtime reproducible, verificó la publicación mínima en
`auth.kontora-pos.store`. Discovery, JWKS e inicio de login están disponibles;
la administración, el realm `master`, health y métricas permanecen fuera de la
frontera pública. El incremento 2.4 integra el login OIDC en Tauri, protege el
refresh token con el almacén del sistema operativo y añade una cuenta beta y un
tema de acceso. El login, callback y perfil fueron comprobados manualmente; la
corrección responsive del formulario web fue aprobada visualmente por el
propietario. El alta de otros usuarios es manual durante la beta y
la invitación automatizada queda documentada como pendiente.
La API todavía no valida JWT.
Durante esta fase, las ramas integradas se
conservarán congeladas localmente y en `origin`. GitHub Actions permanece
aplazado y la puerta de calidad manual sigue siendo obligatoria. Aún no se
incluyen trabajos, `yt-dlp` ni FFmpeg.

## Verificación de identidad privada

No requiere instalar dependencias en Windows. Con Docker Desktop activo:

```powershell
Set-Location C:\Users\Genoma\Documents\MusicFlow
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\initialize-identity-secrets.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-identity.ps1 -Fresh
```

La prueba crea un proyecto temporal aislado en los puertos `18081` y `18082`,
comprueba el contrato y elimina únicamente su volumen temporal. La operación y
la consola administrativa local están descritas en el documento del incremento
2.2.

## Puerta de calidad del incremento 1

La puerta fue aprobada con construcción reproducible de imágenes, migración desde una base vacía, análisis estático, formato, 10 pruebas automatizadas y health checks de API, worker y PostgreSQL. Solo la API publica un puerto y lo enlaza a `127.0.0.1`.

## Verificación del backend aprobado

No se requiere instalar Python, Node.js, Rust ni dependencias del proyecto en Windows. Con Docker Desktop activo, PowerShell ejecutará:

```powershell
Set-Location C:\Users\Genoma\Documents\MusicFlow
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

El script usa `.env.example`, construye imágenes aisladas, levanta un entorno temporal, ejecuta lint/pruebas y lo elimina al finalizar. No utiliza credenciales reales ni expone PostgreSQL o el worker.

## Verificación del cliente aprobada

El cliente se instala y ejecuta directamente en Windows. Docker se utiliza únicamente como toolchain de compilación y no se incorpora a la aplicación distribuida. Después de revisar y aceptar la licencia del SDK de Microsoft requerida por `cargo-xwin`:

```powershell
Set-Location C:\Users\Genoma\Documents\MusicFlow
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-desktop.ps1 -AcceptMicrosoftSdkLicense
```

El script genera los lockfiles en su primera ejecución si fueran necesarios, comprueba en cada ejecución que coincidan con sus manifiestos, ejecuta formato, lint, pruebas y build web, y exporta un instalador NSIS a una carpeta ignorada bajo `artifacts/`. La puerta fue aprobada mediante instalación, consulta pública, degradación controlada, recuperación, reapertura y desinstalación en Windows.

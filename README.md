# MusicFlow

Aplicación de escritorio para solicitar, procesar y guardar audio con metadatos, diseñada inicialmente para Windows y preparada para evolucionar a macOS y Linux.

> Estado: **Fase 1 — incremento 1 aprobado**
> Versión documental: **0.4.0**
> Fecha de referencia: **2026-08-12**

## Propósito

MusicFlow separará claramente dos productos desplegables:

- **Cliente de escritorio:** aplicación Tauri instalada en el equipo del usuario. Gestiona la experiencia de uso y la biblioteca local.
- **Plataforma de servidor:** API, worker de procesamiento y PostgreSQL en contenedores independientes. Solo la API tendrá entrada pública controlada.

El MVP utilizará `yt-dlp` como integración inicial y FFmpeg/FFprobe para el procesamiento. La salida priorizará compatibilidad y calidad perceptual: MP3 VBR de alta calidad con metadatos normalizados. El sistema no prometerá audio Hi-Res cuando la fuente no lo proporcione ni intentará evadir restricciones del proveedor.

## Principios del proyecto

- Correctitud y trazabilidad antes que velocidad de entrega.
- Desarrollo incremental con criterios de aceptación y pruebas por fase.
- Seguridad y privacidad desde el diseño.
- Separación entre cliente, API, procesamiento y persistencia.
- Arquitectura sencilla para el MVP, con puntos de evolución explícitos.
- Cumplimiento de términos, licencias y derechos sobre el contenido.

## Documentación

| Documento | Propósito |
|---|---|
| [Visión y alcance](docs/00-vision-and-scope.md) | Problema, objetivos, alcance y límites del producto. |
| [Especificación de requisitos](docs/01-software-requirements.md) | Requisitos funcionales, no funcionales y criterios de aceptación. |
| [Arquitectura inicial](docs/02-architecture.md) | Componentes, responsabilidades, flujos y despliegue. |
| [Seguridad y cumplimiento](docs/03-security-and-compliance.md) | Modelo de amenazas, controles y tratamiento del error 403. |
| [Estrategia de pruebas](docs/04-testing-strategy.md) | Niveles de prueba y puertas de calidad. |
| [Hoja de ruta](docs/05-roadmap.md) | Fases de desarrollo y condiciones para avanzar. |
| [Proceso de desarrollo](docs/06-development-process.md) | Ciclo de vida, Definition of Done y gestión de cambios. |
| [Diagnóstico del beta](docs/07-beta-diagnostic.md) | Hallazgos del código inicial y estrategia de migración. |
| [Revisión de salida de Fase 0](docs/08-phase-0-exit-review.md) | Evidencia de aprobación y cierre de la fase. |
| [Fase 1 — incremento 1](docs/09-phase-1-increment-1.md) | Alcance, verificaciones y evidencia del esqueleto técnico. |
| [Flujo manual de control de versiones](docs/10-manual-version-control-workflow.md) | Ramas, validación, merge, etiquetas y recuperación. |
| [Registro de decisiones](docs/adr/README.md) | Decisiones arquitectónicas y su estado. |

## Decisiones iniciales

- Cliente de escritorio con Tauri 2.
- API, worker y PostgreSQL en contenedores separados.
- La API es el único punto de entrada público; el worker y la base de datos permanecen en red privada.
- Acceso remoto inicial mediante Cloudflare Tunnel, sin exponer puertos del host directamente.
- Biblioteca y archivos finales almacenados localmente en el dispositivo del usuario.
- Almacenamiento temporal del servidor mediante volumen de Docker en el MVP, abstraído para permitir un futuro almacenamiento compatible con S3.
- Formato de salida inicial: MP3 compatible de alta calidad, sin reescalado engañoso.

## Estado de implementación

La Fase 0 y el primer incremento técnico de la Fase 1 fueron aprobados el 2026-08-12. El incremento demuestra un esqueleto reproducible de API, worker y PostgreSQL mediante Docker Compose. La integración continua con GitHub Actions fue aplazada por decisión del propietario; mientras tanto, cada rama debe superar una puerta de calidad manual y documentada antes del merge. La Fase 1 continúa abierta por el cliente Tauri mínimo. Aún no incluye autenticación, trabajos, `yt-dlp` ni FFmpeg.

## Puerta de calidad del incremento 1

La puerta fue aprobada con construcción reproducible de imágenes, migración desde una base vacía, análisis estático, formato, 10 pruebas automatizadas y health checks de API, worker y PostgreSQL. Solo la API publica un puerto y lo enlaza a `127.0.0.1`.

## Verificación del incremento actual

No se requiere instalar Python, Node.js, Rust ni dependencias del proyecto en Windows. Con Docker Desktop activo, PowerShell ejecutará:

```powershell
Set-Location C:\Users\Genoma\Documents\MusicFlow
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

El script usa `.env.example`, construye imágenes aisladas, levanta un entorno temporal, ejecuta lint/pruebas y lo elimina al finalizar. No utiliza credenciales reales ni expone PostgreSQL o el worker.

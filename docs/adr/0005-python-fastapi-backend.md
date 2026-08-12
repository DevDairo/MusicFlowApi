# ADR-0005: Usar Python y FastAPI para API y worker

- **Estado:** Accepted
- **Fecha:** 2026-08-12
- **Responsables:** propietario del proyecto

## Contexto

El beta demuestra que Python integra bien `yt-dlp`, FFmpeg y procesamiento de metadatos. La nueva arquitectura necesita contratos tipados, configuración validada, OpenAPI, ejecución asíncrona y contenedores separados sin reescribir prematuramente el conocimiento del dominio en otro lenguaje.

## Decisión

Usar Python 3.14 y FastAPI para la API. El worker será un proceso Python independiente que comparte paquetes de dominio e infraestructura, pero no el proceso HTTP.

PostgreSQL se integrará mediante SQLAlchemy 2 con driver asyncpg; Alembic administrará las migraciones. Las dependencias directas y la imagen base se fijarán por versión.

## Alternativas consideradas

- **Flask:** continuidad máxima con el beta, pero exige añadir manualmente más estructura para validación, OpenAPI y ciclo async.
- **NestJS:** tipado y arquitectura consistentes, pero obliga a migrar de inmediato la integración multimedia a Node o mantener dos lenguajes de backend.
- **ASP.NET Core:** sólido y rápido, pero introduce una curva y un stack adicional sin resolver mejor el riesgo principal del MVP.
- **Go:** operación eficiente, pero menor velocidad inicial para las integraciones multimedia existentes.

## Consecuencias

### Positivas

- Conserva aprendizaje y compatibilidad del prototipo.
- Validación y OpenAPI derivadas de tipos.
- API y worker pueden compartir contratos internos sin compartir despliegue.
- Amplio ecosistema de pruebas y PostgreSQL.

### Negativas y riesgos

- Deben aislarse procesos multimedia para no bloquear la API.
- El tipado requiere disciplina y comprobación estática; Python no lo impone en runtime.
- Packaging, wheels y versiones necesitan builds reproducibles.
- Compartir repositorio puede producir acoplamiento si no se respetan módulos.

## Validación

- Builds de API y worker separados desde una imagen base común.
- Configuración inválida falla al iniciar.
- OpenAPI y health checks se prueban automáticamente.
- Worker puede reiniciarse sin afectar el proceso API.

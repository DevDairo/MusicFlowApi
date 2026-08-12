# Architecture Decision Records

Este directorio conserva decisiones arquitectónicas significativas, su contexto y sus trade-offs.

## Índice

| ADR | Decisión | Estado |
|---|---|---|
| [ADR-0001](0001-tauri-desktop-client.md) | Usar Tauri 2 para el cliente de escritorio | Accepted |
| [ADR-0002](0002-containerized-backend.md) | Separar API, worker y PostgreSQL en contenedores | Accepted |
| [ADR-0003](0003-compatible-mp3-output.md) | Priorizar un perfil MP3 compatible | Accepted |
| [ADR-0004](0004-postgresql-job-queue.md) | Usar PostgreSQL como cola durable inicial | Accepted |
| [ADR-0005](0005-python-fastapi-backend.md) | Usar Python y FastAPI para API/worker | Accepted |
| [ADR-0006](0006-react-typescript-ui.md) | Usar React y TypeScript en Tauri | Accepted |
| [ADR-0007](0007-sqlite-local-library.md) | Usar SQLite para el índice local | Accepted |

## Convenciones

- Numeración secuencial de cuatro dígitos.
- Nombre corto en kebab-case.
- Estados permitidos: `Proposed`, `Accepted`, `Superseded`, `Deprecated`, `Rejected`.
- Una decisión aceptada no se modifica para cambiar su historia; se crea una nueva ADR que la reemplace.
- Los detalles todavía no aprobados deben permanecer como propuesta.

## Plantilla

```markdown
# ADR-NNNN: Título

- Estado: Proposed
- Fecha: AAAA-MM-DD
- Responsables: por definir

## Contexto

¿Qué problema y restricciones motivan la decisión?

## Decisión

¿Qué se hará exactamente?

## Alternativas consideradas

¿Qué otras opciones se evaluaron?

## Consecuencias

### Positivas

### Negativas y riesgos

## Validación

¿Qué evidencia confirmará que la decisión funciona?
```

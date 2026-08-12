# ADR-0007: Usar SQLite para el índice local de biblioteca

- **Estado:** Accepted
- **Fecha:** 2026-08-12
- **Responsables:** propietario del proyecto

## Contexto

La biblioteca pertenece a cada dispositivo y debe funcionar sin depender del servidor después de descargar un archivo. Se requiere consultar, actualizar y recuperar un índice local sin desplegar otro servicio.

## Decisión

Usar SQLite embebido para el índice de biblioteca del cliente. Los archivos de audio permanecen en carpetas elegidas por el usuario; SQLite almacena referencias, metadatos y estado, no el audio.

La implementación se diseñará en la Fase 5 mediante una capa de persistencia en Rust/Tauri, migraciones locales y operaciones transaccionales.

## Alternativas consideradas

- JSON: sencillo, pero débil ante concurrencia, consultas, migraciones y escrituras interrumpidas.
- IndexedDB: disponible en WebView, pero más ligado al motor web y menos apropiado para integración nativa de archivos.
- PostgreSQL remoto: contradice funcionamiento local y aumenta exposición/latencia.

## Consecuencias

### Positivas

- Sin proceso adicional ni dependencia de red.
- Transacciones, índices y migraciones.
- Tecnología disponible en las plataformas objetivo.

### Negativas y riesgos

- Rutas y permisos difieren por plataforma.
- Sincronización futura requerirá un diseño separado.
- Mover archivos fuera de la aplicación puede dejar referencias obsoletas.

## Validación

- Pruebas de migración, corrupción/backup y cierre inesperado.
- Detección de archivos ausentes, movidos o duplicados.
- Operaciones de borrado con distinción explícita entre índice y disco.

# Diagnóstico del código beta

**Estado:** Completado  
**Versión:** 1.0  
**Fecha:** 2026-08-12  
**Código analizado:** `C:\Users\Genoma\Documents\servidor-main`

## 1. Alcance del análisis

Se inspeccionaron estructura, dependencias y archivos fuente del beta en modo lectura. No se instalaron paquetes, no se ejecutó el servidor, no se abrió el contenido de la base de datos SQLite y no se modificó el proyecto original.

El beta contiene 15 archivos fuente/configuración relevantes y aproximadamente 1.000 líneas:

- Flask y Flask-CORS para HTTP;
- `yt-dlp` para búsqueda y obtención de audio;
- Mutagen y Pillow para etiquetas/carátulas;
- SQLite para canciones y tareas;
- cola `queue.Queue` con un hilo daemon;
- frontend HTML, CSS y JavaScript sin framework.

## 2. Conclusión ejecutiva

El beta valida el recorrido funcional básico, pero no constituye una base segura ni durable para exposición pública. La recomendación es **migrar el comportamiento útil**, no ampliar el monolito actual.

Se conservarán el conocimiento del dominio, el uso de Python para integración multimedia, el concepto de trabajo asíncrono y el perfil MP3/ID3. Se reemplazarán el servidor Flask global, la cola en memoria, la biblioteca permanente del servidor y SQLite como persistencia remota.

## 3. Aspectos valiosos que se deben conservar

| Idea del beta | Evidencia | Evolución recomendada |
|---|---|---|
| Procesamiento fuera de la petición | `services/queue_manager.py:9-49` | Worker en contenedor separado y cola durable. |
| Mejor audio disponible | `services/downloader.py:67-80` | Adaptador de proveedor con política explícita y verificación FFprobe. |
| MP3 VBR de alta calidad | `services/downloader.py:71-78` | Perfil versionado y probado; evitar describirlo como 320 kbps constante. |
| Metadatos ID3v2.3 y carátula | `services/metadata.py:63-106` | Modelo normalizado, límites y compatibilidad verificada. |
| SQL parametrizado | `database/models.py:6-127` | Repositorios tipados, transacciones y migraciones PostgreSQL. |
| Progreso por tarea | `api/download.py:29-49` | Contrato de estados estable y polling acotado en el MVP. |
| Saneamiento inicial de nombres | `services/cleaner.py:5-28` | Reglas por plataforma, Unicode, nombres reservados, colisiones y hash/ID. |

## 4. Hallazgos críticos

### BETA-C01 — No existe autenticación ni autorización

Todos los endpoints son públicos. Cualquier consumidor puede crear trabajos, enumerar la biblioteca y recuperar archivos. Las tareas y canciones no tienen propietario (`api/download.py`, `api/library.py`, `database/db.py:23-45`).

**Impacto:** acceso entre usuarios, consumo abusivo de recursos y exposición pública de archivos.

**Tratamiento:** identidad OIDC, propietario obligatorio, autorización por recurso y pruebas negativas entre usuarios antes de integrar el proveedor real.

### BETA-C02 — Configuración insegura para exposición de red

La aplicación habilita CORS para cualquier origen (`app.py:10-13`), escucha en `0.0.0.0` y activa `DEBUG=True` (`config.py:10-13`).

**Impacto:** superficie de ataque innecesaria y riesgo de divulgar información interna o usar capacidades de depuración en un servicio público.

**Tratamiento:** configuración por ambiente validada, orígenes explícitos cuando CORS aplique y modo de producción sin debugger. Tauri no requiere convertir CORS abierto en un mecanismo de autenticación.

### BETA-C03 — Entrega de archivos sin confinamiento robusto

Los endpoints aceptan `<path:filename>`, construyen una ruta con `os.path.join` y usan `send_file` (`api/library.py:31-48` y `51-76`). No existe autorización ni verificación mediante un registro de artefacto propietario.

**Impacto:** traversal, exposición de archivos o comportamiento inconsistente según rutas/plataforma.

**Tratamiento:** el cliente solicita un artefacto por ID; la API verifica propietario, vigencia, clave interna y checksum. Nunca acepta una ruta del sistema proporcionada por el usuario.

### BETA-C04 — Inyección de contenido en el frontend

Resultados y biblioteca se renderizan mediante `innerHTML` con título, artista, miniatura y URL provenientes de fuentes externas (`frontend/app.js:13-25` y `71-81`). También se construyen handlers inline con esos valores.

**Impacto:** XSS o alteración de interfaz dentro del navegador/WebView.

**Tratamiento:** renderizado con escape por defecto, sin HTML/handlers construidos desde strings, CSP estricta y capacidades Tauri mínimas.

### BETA-C05 — La cola y el worker no son durables ni están aislados

La cola vive en memoria y el hilo daemon comienza al importar el módulo (`services/queue_manager.py:15-18` y `100-101`). Un reinicio pierde elementos encolados; el reloader de desarrollo o múltiples procesos pueden crear workers duplicados.

**Impacto:** trabajos perdidos, duplicados o bloqueados y competencia por CPU/disco dentro del servidor HTTP.

**Tratamiento:** worker en contenedor independiente, trabajos PostgreSQL con lease, transiciones atómicas e idempotencia.

## 5. Hallazgos importantes

| ID | Hallazgo | Evidencia y riesgo | Tratamiento |
|---|---|---|---|
| BETA-I01 | Entrada insuficientemente validada | La URL solo se comprueba como texto no vacío (`api/download.py:19-25`) y llega a `yt-dlp`. | Allowlist de esquema/proveedor, normalización, límites y adaptador cerrado. |
| BETA-I02 | Fetch remoto de carátula sin política | `requests.get` consume una URL del proveedor (`services/metadata.py:48-58`). | Allowlist, tamaño/MIME/dimensiones, redirecciones y descarga limitada. |
| BETA-I03 | Errores internos devueltos al usuario | La excepción se persiste como mensaje de tarea (`queue_manager.py:46-47`, `models.py:52-63`). | Código estable, detalle interno separado y correlation ID. |
| BETA-I04 | Colisiones de archivos por título | La ruta depende del título saneado (`downloader.py:63-69`). Dos medios pueden compartir nombre. | Clave basada en job/UUID y nombre final independiente de la ruta temporal. |
| BETA-I05 | Idempotencia y unicidad incompletas | Se consulta antes de insertar, pero `youtube_url` no tiene restricción única (`db.py:23-33`, `models.py:89-103`). | Restricción única según regla, `Idempotency-Key` y transacción. |
| BETA-I06 | Operaciones externas sin presupuesto global | `yt-dlp` no tiene timeout/cancelación explícitos; solo la carátula usa timeout. | Timeouts por etapa, cancelación, límites de proceso y limpieza. |
| BETA-I07 | Escrituras frecuentes por progreso | Cada callback abre conexión y confirma una transacción (`queue_manager.py:55-64`). | Throttling de progreso y actualización condicionada. |
| BETA-I08 | Metadatos heurísticos o inventados | Género `Varios`, álbum `YouTube` y año `2024` por defecto (`metadata.py:73-86`). | Ausencia explícita antes que dato falso; procedencia y normalización. |
| BETA-I09 | Se eliminan todas las etiquetas antes de escribir | `audio.delete()` (`metadata.py:78-95`). | Política de merge/reemplazo probada y preservación intencional. |
| BETA-I10 | Persistencia remota no preparada para concurrencia | SQLite, conexiones por operación y sin migraciones/versionado. | PostgreSQL, Alembic, constraints e índices. |
| BETA-I11 | Dependencias no reproducibles | Solo límites mínimos `>=` y sin lock/hash (`requirements.txt`). | Archivo de proyecto y lock reproducible generado en contenedor. |
| BETA-I12 | Sin pruebas ni observabilidad estructurada | `print` y excepciones genéricas; no hay tests. | Pytest, contratos, logs estructurados, health y métricas básicas. |

## 6. Mejoras opcionales

- Corregir en el beta la referencia `style.css` frente al archivo real `styles.css`; no es necesario migrar este frontend.
- Evitar convertir acentos a ASCII por defecto en la biblioteca final: NTFS y otros sistemas admiten Unicode.
- Separar el progreso de descarga del progreso total del pipeline; actualmente llega a 100 % antes de terminar metadatos.
- No hacer una segunda extracción de información si el flujo puede reutilizar una respuesta válida sin aumentar riesgo.
- Tratar la búsqueda como capacidad posterior al flujo por URL: añade solicitudes al proveedor y aumenta exposición a rate limits.

## 7. Estrategia de migración

### Se reutiliza como conocimiento

- campos de metadatos y comportamiento de etiquetado;
- integración inicial mediante `yt-dlp`;
- uso de FFmpeg como postprocesador;
- estados y progreso visibles para el usuario;
- casos de error observados en el prototipo.

### Se reescribe dentro de límites nuevos

- HTTP: Flask → API tipada y versionada;
- worker: hilo interno → proceso/contenedor independiente;
- cola: memoria → PostgreSQL durable con lease;
- persistencia de servidor: SQLite → PostgreSQL;
- biblioteca: servidor → SQLite y archivos locales en Tauri;
- archivos finales: permanentes en servidor → artefactos temporales autorizados;
- frontend HTML global → UI Tauri tipada y escapada.

No se recomienda copiar módulos completos y corregirlos después: preservaría acoplamientos que la arquitectura nueva intenta eliminar.

## 8. Stack recomendado tras el análisis

| Área | Recomendación | Motivo |
|---|---|---|
| API | Python + FastAPI | Continuidad con el dominio Python, validación tipada, OpenAPI y buen ajuste a contenedores. |
| Worker | Python, proceso independiente | Integración directa con `yt-dlp` y herramientas multimedia; reutiliza dominio sin compartir proceso. |
| Persistencia | PostgreSQL + SQLAlchemy 2 + Alembic | Transacciones, concurrencia, modelo tipado y migraciones. |
| Cola MVP | PostgreSQL `FOR UPDATE SKIP LOCKED` + leases | Menos infraestructura y creación/encolado atómicos; sustituible si la medición lo exige. |
| Cliente | Tauri 2 + React + TypeScript | UI tipada, capacidades nativas y ruta multiplataforma. |
| Biblioteca local | SQLite | Persistencia embebida apropiada para datos de un único dispositivo. |
| Pruebas | Pytest + integración PostgreSQL/FFmpeg + contratos OpenAPI | Cubre reglas, infraestructura y límites cliente-servidor. |

FastAPI recomienda construir una imagen propia a partir de la imagen oficial de Python y ejecutar el comando del contenedor en forma exec. Tauri ofrece capacidades granulares por ventana/WebView. OAuth para aplicaciones nativas exige tratar el cliente como público, usar navegador externo y PKCE. PostgreSQL admite bloqueo de filas con `SKIP LOCKED`, base de la cola propuesta.

## 9. Resultado del diagnóstico

- **Reutilización directa de código:** no recomendada como base.
- **Reutilización de comportamiento y aprendizaje:** recomendada.
- **Bloqueo para Fase 1:** ninguno si se acepta el stack propuesto.
- **Bloqueo para autenticación real:** seleccionar proveedor OIDC antes de la Fase 2.
- **Bloqueo para procesamiento real:** aprobar límites, retención y matriz de compatibilidad antes de la Fase 4.

## 10. Referencias técnicas

- [FastAPI en contenedores](https://fastapi.tiangolo.com/deployment/docker/)
- [Tauri: modelo de capacidades](https://tauri.app/reference/acl/capability/)
- [OAuth 2.0 para aplicaciones nativas — RFC 8252](https://datatracker.ietf.org/doc/html/rfc8252)
- [PostgreSQL: SELECT y bloqueo de filas](https://www.postgresql.org/docs/current/sql-select.html)

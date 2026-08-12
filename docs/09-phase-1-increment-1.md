# Fase 1 — incremento 1: esqueleto técnico

**Estado:** Aprobado y cerrado  
**Versión:** 1.0  
**Inicio:** 2026-08-12
**Cierre:** 2026-08-12

## Objetivo

Demostrar los límites de despliegue y operación de API, worker y PostgreSQL antes de implementar autenticación, trabajos o procesamiento multimedia.

## Alcance aprobado

- monorepo con backend modular;
- API FastAPI y worker Python en runtimes separados;
- PostgreSQL 18 en red privada;
- migraciones Alembic;
- configuración validada y secretos fuera del repositorio;
- logs JSON y correlation ID;
- health checks de API, worker y base de datos;
- pruebas unitarias y de integración ejecutables en Docker;
- scripts PowerShell que invocan Docker sin instalar paquetes en Windows.

## Fuera del alcance

- login/OIDC;
- endpoints y cola real de trabajos;
- `yt-dlp`, FFmpeg o archivos de audio;
- Cloudflare Tunnel activo;
- UI o compilación Tauri;
- exposición pública a Internet.

## Versiones base verificadas en fuentes oficiales

- Python `3.14.6-slim-bookworm`.
- PostgreSQL `18.4-bookworm`.
- FastAPI `0.141.1`.
- Pydantic `2.13.4` y pydantic-settings `2.15.0`.
- SQLAlchemy `2.0.52`.
- Alembic `1.19.1`.
- asyncpg `0.31.0`.
- Uvicorn `0.52.1`.
- pytest `9.1.1` y HTTPX `0.28.1` para pruebas.

Las dependencias directas quedarán fijadas. El lock transitivo deberá generarse y verificarse dentro de Docker antes de cerrar el incremento.

## Criterios de aceptación

- [x] `docker compose config` valida la configuración.
- [x] las imágenes de API, worker y tests se construyen.
- [x] la migración llega a `head` sobre una base vacía y una prueba de integración consulta su revisión.
- [x] `/health/live` responde 200 sin consultar dependencias.
- [x] `/health/ready` responde 200 con PostgreSQL disponible y 503 sin él.
- [x] el worker pasa a healthy solo después de comprobar PostgreSQL.
- [x] API es el único servicio con puerto publicado y se enlaza a `127.0.0.1`.
- [x] worker y PostgreSQL no publican puertos.
- [x] procesos de aplicación se ejecutan como usuario no root.
- [x] tests, lint y formato terminan correctamente dentro de Docker.
- [x] no existen secretos reales ni dependencias instaladas en Windows.

## Evidencia de entorno

Docker Desktop está en ejecución bajo el usuario `Genoma`. La instalación usa la ruta no estándar `C:\Users\Genoma\AppData\Local\Programs\DockerDesktop`.

La sesión aislada de Codex puede observar los procesos, pero Windows impide que ejecute `docker.exe` desde `AppData`. Este límite no implica que Docker Desktop esté detenido. La validación de runtime se ejecutó manualmente desde el PowerShell del usuario, sin copiar ni reinstalar Docker y sin instalar dependencias del proyecto en Windows.

## Evidencia estática obtenida

- 24 archivos Python analizados correctamente por el parser AST.
- `pyproject.toml` válido mediante `tomllib`.
- `scripts/verify.ps1` sin errores del parser de PowerShell.
- 7 dependencias directas de runtime y 3 de desarrollo, todas fijadas por versión.
- un único bloque `ports`, enlazado a `127.0.0.1` para la API.
- red `backend` marcada como interna.
- API, worker, migraciones y tests declaran usuario no root `10001:10001`.
- todos los `CMD` usan forma exec.
- ningún `.env` real; solo `.env.example` con un marcador no secreto.
- 20 documentos Markdown sin enlaces locales rotos ni referencias obsoletas a decisiones pendientes.
- repositorio Git local inicializado en `main`, sin remoto ni commits automáticos.

## Primera ejecución Docker

La primera ejecución en el PowerShell del usuario demostró:

- descarga y build correcto de Python `3.14.6-slim-bookworm`;
- instalación aislada de las dependencias en las imágenes;
- build correcto de `api`, `worker`, `tests` y `migrate`;
- PostgreSQL 18.4 saludable;
- migración terminada con código cero;
- API y worker saludables;
- usuario no root comprobado por el script;
- limpieza correcta de contenedores, redes y volumen temporal.

La ejecución se detuvo en Ruff antes de pytest por cinco hallazgos de calidad, no por Docker ni por los servicios. Se corrigieron los cinco y se generaron `runtime.lock.txt` y `dev.lock.txt` a partir de las versiones exactas resueltas en ese build. La próxima ejecución valida esos locks con `pip check`.

## Incidencias encontradas y resolución

Durante la verificación incremental se detectaron y resolvieron los siguientes problemas:

1. La política local de PowerShell impedía ejecutar scripts. Se mantuvo la política del sistema y se utilizó `-ExecutionPolicy Bypass` únicamente para el proceso de verificación.
2. Ruff intentaba usar caché sobre un sistema de archivos de contenedor de solo lectura. Se añadió `--no-cache` a las comprobaciones.
3. Cinco archivos no coincidían con el formato canónico de Ruff para Python 3.14. Se aplicó el formato sin modificar el comportamiento.
4. PowerShell interpretaba el argumento `-p` de pytest como abreviatura de `-PipelineVariable`. Los argumentos de pytest se encapsularon en un arreglo explícito.
5. La prueba de integración utilizaba una contraseña fija del fixture unitario, distinta de `POSTGRES_PASSWORD`. Se separó la configuración unitaria de la configuración de integración para usar las variables entregadas por Compose.

Cada corrección fue mínima y la canalización completa se volvió a ejecutar desde cero.

## Evidencia final de aceptación

Comando ejecutado desde `C:\Users\Genoma\Documents\MusicFlow`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

Resultado observado el 2026-08-12:

- las imágenes `api`, `worker` y `tests` se construyeron correctamente;
- `pip check` no encontró dependencias incompatibles;
- Ruff aprobó el análisis estático;
- Ruff confirmó 25 archivos correctamente formateados;
- PostgreSQL quedó saludable y la migración terminó con código cero;
- API y worker alcanzaron estado `healthy`;
- pytest terminó con `10 passed`;
- las consultas finales de liveness y readiness fueron satisfactorias;
- el script mostró `Verificacion completada correctamente`;
- contenedores, redes y volumen temporal fueron eliminados al finalizar.

No quedan defectos bloqueantes conocidos en este incremento. Existe una advertencia no bloqueante de deprecación entre `fastapi.testclient` y `httpx`; deberá evaluarse antes de actualizar esas dependencias y no se resolverá instalando paquetes sin revisar compatibilidad y procedencia.

## Decisión de cierre

El incremento 1 de la Fase 1 queda aprobado. La Fase 1 completa permanece abierta porque aún requiere la CI mínima y el cliente Tauri mínimo establecidos en la hoja de ruta. El siguiente incremento debe definirse y aprobarse antes de implementar nuevas capacidades.

## Referencias

- [FastAPI en contenedores](https://fastapi.tiangolo.com/deployment/docker/)
- [Imagen oficial de Python](https://hub.docker.com/_/python)
- [Imagen oficial de PostgreSQL](https://hub.docker.com/_/postgres)

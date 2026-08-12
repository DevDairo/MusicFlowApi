# Hoja de ruta por fases

**Estado:** Vigente
**Versión:** 0.2
**Fecha:** 2026-08-12

## Principio de avance

Cada fase produce un incremento pequeño, verificable y documentado. La siguiente fase no comienza hasta cumplir la puerta de salida o registrar de forma explícita una excepción con riesgo, responsable y fecha.

No se fijan fechas antes de cerrar alcance, dependencias y capacidad disponible.

## Fase 0 — Descubrimiento y requisitos

**Objetivo:** acordar qué se construirá y bajo qué restricciones.

Entregables:

- visión y alcance;
- SRS con requisitos priorizados;
- arquitectura y modelo de amenazas inicial;
- ADR de decisiones principales;
- estrategia de pruebas y proceso;
- revisión estructurada del código beta como fuente de aprendizaje, no como arquitectura asumida.
- revisión formal de salida con decisiones aceptadas o aplazadas hasta una puerta concreta.

Puerta de salida:

- preguntas bloqueantes respondidas;
- alcance del MVP aprobado;
- riesgos críticos con tratamiento;
- decisiones propuestas aceptadas, rechazadas o aplazadas conscientemente.

## Fase 1 — Esqueleto técnico reproducible

**Objetivo:** demostrar límites de despliegue sin implementar todavía procesamiento real.

Entregables:

- repositorio y estructura acordados;
- API, worker y PostgreSQL en Docker Compose;
- migraciones iniciales;
- configuración por ambiente y `.env.example`;
- health checks, logs estructurados y correlation IDs;
- flujo manual de ramas cortas con lint, formato, pruebas y build de imágenes como puerta obligatoria;
- cliente Tauri mínimo capaz de consultar el health de la API.

Puerta de salida:

- entorno se inicia desde cero siguiendo README;
- ningún servicio interno queda publicado innecesariamente;
- pruebas y escaneos base pasan;
- cada incremento fue validado antes del merge y etiquetado después de su aprobación;
- reinicios controlados no corrompen persistencia.

GitHub Actions queda aplazado por decisión del propietario mientras adquiere experiencia con la herramienta. Su adopción futura se tratará como un incremento explícito; no será una modificación incidental del proceso.

## Fase 2 — Identidad y autorización

**Objetivo:** establecer la frontera de confianza antes de aceptar trabajos.

Entregables:

- proveedor OIDC y Authorization Code + PKCE;
- almacenamiento seguro de tokens en el cliente;
- validación de tokens en API;
- usuario interno y autorización por recurso;
- rate limiting inicial y auditoría segura.

Puerta de salida:

- pruebas de login/logout, token inválido/vencido y revocación;
- pruebas negativas entre dos usuarios;
- modelo de amenazas actualizado;
- ningún secreto de servidor distribuido en Tauri.

## Fase 3 — Orquestación durable de trabajos

**Objetivo:** validar el ciclo asíncrono sin depender aún del proveedor real.

Entregables:

- endpoints de creación, consulta y cancelación;
- idempotencia y máquina de estados;
- cola durable/leases aprobados;
- worker con tarea simulada;
- reintentos, timeouts y recuperación tras caída;
- métricas básicas de cola y trabajos.

Puerta de salida:

- pruebas de concurrencia y transiciones inválidas;
- reinicio de API/worker sin pérdida de trabajos aceptados;
- no hay doble finalización ni trabajos bloqueados permanentemente.

## Fase 4 — Pipeline de audio y metadatos

**Objetivo:** integrar `yt-dlp`, FFmpeg y FFprobe de forma controlada.

Entregables:

- adaptador de proveedor;
- selección de mejor audio disponible;
- perfil MP3 aprobado;
- normalización de metadatos y carátula;
- verificación técnica del resultado;
- clasificación 403/429/5xx, backoff y circuit breaker;
- almacenamiento temporal y limpieza.

Puerta de salida:

- fixtures autorizados y pruebas de errores en verde;
- archivo compatible en la matriz acordada;
- sin interpolación en shell, traversal ni artefactos huérfanos conocidos;
- límites de recursos medidos y documentados.

## Fase 5 — Experiencia Tauri y biblioteca local

**Objetivo:** completar el recorrido de usuario en Windows.

Entregables:

- UI de envío, estado, errores y descarga;
- selección segura de destino;
- índice local y operaciones de biblioteca;
- tratamiento de duplicados, colisiones y archivos ausentes;
- accesibilidad básica y empaquetado Windows.

Puerta de salida:

- E2E completo aprobado;
- prueba en versiones/arquitecturas Windows definidas;
- desinstalación, actualización y recuperación probadas;
- biblioteca local no se elimina accidentalmente.

## Fase 6 — Endurecimiento y beta privada

**Objetivo:** operar con usuarios controlados antes de exposición masiva.

Entregables:

- Cloudflare Tunnel configurado y documentado;
- backups y restauración de PostgreSQL probados;
- alertas, dashboards mínimos y runbooks;
- cuotas definitivas y pruebas de carga;
- firma y actualización segura del cliente;
- privacidad, términos y política de retención;
- plan de incidentes y rollback.

Puerta de salida:

- revisión de seguridad sin críticos abiertos;
- recuperación desde backup demostrada;
- SLO inicial y capacidad medida;
- criterios y soporte de beta aprobados.

## Después del MVP

Evaluar con evidencia, no por anticipación:

- macOS y Linux;
- formatos alternativos como FLAC u Opus;
- almacenamiento compatible con S3;
- broker dedicado;
- despliegue en VPS/dedicado;
- más proveedores autorizados;
- publicidad o monetización;
- cliente móvil nativo.

Cada ampliación importante requiere actualizar requisitos, amenazas, pruebas y ADR.

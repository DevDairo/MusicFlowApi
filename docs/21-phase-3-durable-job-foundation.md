# Fase 3 — fundamento de orquestación durable

## 1. Estado y objetivo

Estado: **diseño inicial propuesto el 14 de agosto de 2026**.

La Fase 3 validará el ciclo asíncrono completo con PostgreSQL y una tarea
simulada. No se ejecutarán `yt-dlp`, FFmpeg, descargas externas ni escritura de
artefactos. La meta es demostrar antes la correctitud de estados, idempotencia,
concurrencia, recuperación y autorización.

## 2. Estrategia incremental

| Incremento | Entrega funcional | Puerta principal |
| --- | --- | --- |
| 3.1 Contrato durable | URL segura, esquema, repositorio, creación idempotente, consulta y cancelación | API y migración correctas; usuario B no conoce trabajos de A |
| 3.2 Worker simulado | Claim con lease, heartbeat, progreso y finalización protegida | Dos workers no procesan activamente el mismo trabajo |
| 3.3 Recuperación | Reintentos transitorios, lease vencido, cancelación en ejecución y métricas | Reinicios no pierden ni bloquean trabajos |

Cada incremento tendrá su propia rama, pruebas, documentación, validación y
merge. No se avanzará al siguiente si su puerta permanece abierta.

## 3. Decisiones y trade-offs

### PostgreSQL como cola

Se mantiene ADR-0004: la creación del recurso y su disponibilidad ocurren en
una sola transacción. Redis o RabbitMQ añadirían una segunda infraestructura y
coordinación distribuida sin evidencia de que el MVP la necesite.

### Máquina de estados en código y restricciones SQL

Las reglas vivirán en un módulo de dominio puro y se reforzarán con `CHECK` y
actualizaciones condicionales. Un enum nativo de PostgreSQL ofrece tipado fuerte,
pero complica añadir estados y sus migraciones; se usará texto limitado por
constraint.

### Idempotencia por propietario

`Idempotency-Key` será única dentro de cada identidad, no global. La misma clave
y el mismo hash de solicitud devolverán el trabajo existente. La misma clave
con otro payload responderá `409 idempotency_conflict`. Esto evita duplicados
por reintentos sin permitir que una cuenta interfiera con otra.

### Polling antes que SSE

El cliente consultará `GET /v1/jobs/{id}`. SSE añade reconexión, estado de
conexiones y operación del proxy sin ser necesario para demostrar el flujo. Se
reevaluará únicamente si las mediciones muestran una experiencia insuficiente.

## 4. Entrada admitida en el incremento 3.1

Aunque todavía no se contactará al proveedor, la API no almacenará URLs
arbitrarias.

Reglas iniciales:

- esquema obligatorio `https`;
- sin usuario, contraseña, puerto ni fragmento;
- hosts exactos `youtube.com`, `www.youtube.com`, `m.youtube.com`,
  `music.youtube.com` y `youtu.be`;
- solo un identificador individual de video; playlists quedan fuera del MVP;
- `watch?v=<videoId>`, `youtu.be/<videoId>` y `shorts/<videoId>` se normalizan a
  `https://www.youtube.com/watch?v=<videoId>`;
- el identificador debe cumplir el alfabeto y longitud de video esperados;
- no se siguen redirecciones ni se resuelve DNS durante la validación.

El valor normalizado podrá persistirse, pero nunca aparecerá en logs ni en la
respuesta de consulta. Ampliar proveedores o formas de URL exigirá adaptar la
allowlist y añadir pruebas hostiles antes de modificar el contrato.

## 5. Contrato HTTP del incremento 3.1

### Crear

```http
POST /v1/jobs
Authorization: Bearer <access-token>
Idempotency-Key: 2f45b156-1ef2-4b81-bf46-961c5a678bec
Content-Type: application/json
```

```json
{
  "sourceUrl": "https://youtu.be/dQw4w9WgXcQ",
  "outputProfile": "mp3-compatible"
}
```

Respuesta `202 Accepted`:

```json
{
  "id": "d9962cc2-9c17-42c5-ad79-c8f1412acfc3",
  "state": "queued",
  "progress": 0,
  "createdAt": "2026-08-14T18:00:00Z",
  "updatedAt": "2026-08-14T18:00:00Z",
  "error": null
}
```

La respuesta incluye `Location: /v1/jobs/{id}`. Una repetición equivalente
devuelve el mismo cuerpo y `Idempotency-Replayed: true`.

La clave debe contener entre 16 y 128 caracteres ASCII visibles. El hash se
calcula sobre una representación canónica versionada de `sourceUrl` y
`outputProfile`; nunca sobre el JSON recibido literalmente.

### Consultar

```http
GET /v1/jobs/{jobId}
Authorization: Bearer <access-token>
```

Devuelve `200` con el mismo modelo público. Un UUID inexistente o perteneciente
a otra identidad devuelve el mismo `404 job_not_found`, evitando revelar su
existencia.

### Cancelar

```http
POST /v1/jobs/{jobId}/cancellation
Authorization: Bearer <access-token>
```

- `queued` pasa atómicamente a `cancelled`;
- una cancelación repetida de `cancelled` devuelve el mismo resultado;
- en el incremento 3.2, `running` marcará `cancellation_requested_at` para que el
  worker confirme la transición segura;
- otros estados terminales responden `409 job_not_cancellable`.

El formato de error seguirá por ahora el contrato estable `detail.code` y
`detail.message` existente, más `X-Correlation-ID`. Migrar toda la API a Problem
Details será un incremento transversal separado, no una condición oculta de
esta fase.

## 6. Modelo de datos propuesto

### `jobs`

| Campo | Tipo | Regla |
| --- | --- | --- |
| `id` | UUID | PK generada por la aplicación |
| `owner_id` | UUID | FK a `user_identities`, no anulable |
| `idempotency_key` | varchar(128) | única junto con `owner_id` |
| `request_hash` | char(64) | SHA-256 de solicitud canónica versionada |
| `source_url` | varchar(2048) | URL normalizada, nunca registrada |
| `output_profile` | varchar(32) | inicialmente `mp3-compatible` |
| `state` | varchar(16) | `queued`, `running`, `succeeded`, `failed`, `cancelled`, `expired` |
| `progress` | smallint | entre 0 y 100 |
| `attempt_count` | smallint | inicia en 0; nunca supera `max_attempts` |
| `max_attempts` | smallint | valor inicial 3 |
| `available_at` | timestamptz | elegibilidad para claim |
| `lease_owner` | varchar(128), null | worker que posee la concesión |
| `lease_expires_at` | timestamptz, null | expiración de la concesión |
| `cancellation_requested_at` | timestamptz, null | solicitud cooperativa |
| `error_code` | varchar(64), null | código terminal estable |
| `error_message` | varchar(512), null | mensaje seguro |
| `correlation_id` | varchar(64), null | origen del error terminal |
| `created_at`, `updated_at` | timestamptz | obligatorios |
| `started_at`, `finished_at` | timestamptz, null | coherentes con el estado |

Restricciones e índices iniciales:

- `UNIQUE(owner_id, idempotency_key)`;
- `CHECK` de estados, progreso e intentos;
- índice de consulta `owner_id, created_at DESC`;
- índice parcial de cola sobre `available_at, created_at` para `queued`;
- índice parcial de recuperación sobre `lease_expires_at` para `running`.

### `job_attempts`

Se añadirá con el worker del incremento 3.2. Será un historial append-only con
job, número de intento, worker, inicio, fin, resultado y código de error. La
combinación `(job_id, attempt_number)` será única.

No se creará todavía `artifacts` ni `job_metadata`: no existen artefactos reales
en esta fase y añadir tablas vacías sería diseño prematuro.

## 7. Máquina de estados e invariantes

Transiciones permitidas:

- `queued -> running` al obtener lease;
- `queued -> cancelled` por el propietario;
- `running -> succeeded` al finalizar el dueño vigente del lease;
- `running -> queued` solo por error transitorio o lease vencido con intentos;
- `running -> failed` por error terminal o intentos agotados;
- `running -> cancelled` cuando el worker confirma cancelación;
- `succeeded -> expired` al vencer la retención futura.

Invariantes:

- los estados terminales no regresan a estados activos;
- solo el `lease_owner` vigente puede actualizar progreso o finalizar;
- una finalización usa `WHERE state='running' AND lease_owner=:worker`;
- el resultado de una actualización condicional con cero filas es una pérdida
  del lease, no una invitación a escribir de nuevo;
- ninguna petición HTTP mantiene una transacción abierta mientras espera al
  worker;
- cancelación, idempotencia y finalización son seguras ante repetición.

## 8. Claim, lease y recuperación

El incremento 3.2 reclamará una fila elegible mediante una transacción corta con
`SELECT ... FOR UPDATE SKIP LOCKED`, la actualizará a `running`, incrementará el
intento y establecerá `lease_owner`/`lease_expires_at` antes del commit.

El worker simulado actualizará el heartbeat solo si la duración excede una
fracción significativa del lease. No se mantendrá el bloqueo SQL durante el
trabajo.

En 3.3, un lease vencido:

- vuelve a `queued` con `available_at` y backoff si quedan intentos;
- termina `failed` con `worker_lease_expired` si se agotaron;
- nunca puede ser finalizado por el worker anterior después de ser reclamado por
  otro.

## 9. Seguridad y privacidad

- todos los endpoints dependen de la identidad validada de la Fase 2;
- las consultas incluyen `owner_id` desde el inicio, no filtran después;
- una identidad ajena recibe `404`, sin título, URL, estado ni timestamps;
- URL e idempotency key no aparecen en logs;
- los eventos usan UUID interno, job ID, estado, intento y correlation ID;
- límites de longitud se aplican antes de hash o persistencia;
- la API no solicita la URL ni resuelve su host durante la Fase 3;
- el rate limiting de autenticación existente continúa activo; cuotas de
  creación se añadirán solo con una política y métricas explícitas.

## 10. Estrategia de pruebas

### Incremento 3.1

- tabla y constraints mediante upgrade/downgrade;
- normalización equivalente y rechazo de esquemas, hosts, puertos, credenciales,
  IDs y formas no admitidas;
- misma clave/payload produce un solo trabajo bajo concurrencia;
- misma clave/payload distinto devuelve conflicto;
- transiciones puras válidas e inválidas;
- usuario A crea/consulta/cancela; usuario B obtiene `404`;
- cancelación repetida no cambia el resultado;
- reinicio de API conserva el trabajo `queued`.

### Incremento 3.2

- dos workers concurrentes reclaman trabajos distintos;
- un trabajo no tiene dos leases vigentes;
- solo el dueño actualiza progreso/finaliza;
- la tarea simulada termina `succeeded` sin conexión externa;
- reinicio del worker no pierde trabajos aceptados.

### Incremento 3.3

- lease vencido se recupera exactamente una vez;
- fallo transitorio reprograma con backoff limitado;
- fallo terminal y agotamiento terminan `failed`;
- cancelación de `running` termina de forma cooperativa;
- worker antiguo no puede finalizar después de perder el lease;
- métricas reflejan estados, claims, reintentos y recuperaciones.

## 11. Observabilidad

Eventos previstos, sin payload sensible:

- `job_created`, `job_idempotency_replayed`, `job_cancelled`;
- `job_claimed`, `job_progressed`, `job_succeeded`, `job_failed`;
- `job_retry_scheduled`, `job_lease_recovered`;
- `job_access_not_found` sin distinguir inexistencia de recurso ajeno.

Las métricas iniciales medirán cantidad por estado, latencia hasta claim,
duración simulada, reintentos y leases recuperados. No se añadirá Prometheus
antes de definir el punto de exposición privado y comprobar que los contadores
son necesarios.

## 12. Riesgos y rollback

- `SKIP LOCKED` mal indexado puede generar scans; se inspeccionará el plan con
  datos de prueba antes de optimizar.
- Polling demasiado frecuente carga PostgreSQL; comenzará con un intervalo
  conservador y jitter.
- Un lease demasiado corto duplica trabajo; uno muy largo retrasa recuperación.
  Los valores se medirán con la tarea simulada.
- La URL almacenada puede ser dato personal; se restringirá acceso y se definirá
  retención antes de un despliegue masivo.
- El downgrade del incremento 3.1 eliminará únicamente tablas de trabajos; solo
  se ejecutará en entornos de prueba o con respaldo explícito.

El rollback de código se realizará con `git revert`. Nunca se modificará una
migración que ya haya sido publicada; cualquier corrección posterior será una
nueva revisión Alembic.

## 13. Puerta de entrada al incremento 3.1

Antes de implementar se debe aprobar:

- [ ] alcance de los tres incrementos;
- [ ] contrato HTTP e idempotencia;
- [ ] allowlist y normalización inicial de YouTube;
- [ ] esquema e invariantes de estado;
- [ ] política `404` para recursos ajenos;
- [ ] estrategia de pruebas y rollback.

La implementación comenzará solo después de aprobar esta puerta documental.

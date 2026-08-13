# Especificación de requisitos de software

**Identificador:** SRS-MF-001
**Estado:** Borrador para validación
**Versión:** 0.2
**Fecha:** 2026-08-13

## 1. Convenciones

- **MUST:** obligatorio para aceptar el MVP.
- **SHOULD:** importante, pero puede aplazarse con una decisión documentada.
- **COULD:** deseable fuera del camino crítico.
- Cada requisito tendrá evidencia de prueba o una justificación de no aplicabilidad.

## 2. Glosario

| Término | Definición |
|---|---|
| Trabajo | Solicitud asíncrona de inspección, descarga, transformación y etiquetado. |
| Artefacto | Archivo temporal o resultado producido durante un trabajo. |
| Biblioteca local | Índice y archivos administrados en el dispositivo del usuario. |
| Fuente | Servicio externo admitido del que se obtiene información o medios. |
| Perfil compatible | Configuración de salida reproducible en sistemas y dispositivos comunes. |
| Error transitorio | Fallo que puede resolverse con un reintento limitado. |
| Error terminal | Fallo que requiere intervención, cambio de entrada o finaliza el trabajo. |

## 3. Requisitos funcionales

### 3.1 Identidad y acceso

| ID | Prioridad | Requisito |
|---|---|---|
| RF-001 | MUST | El sistema permitirá iniciar sesión mediante un flujo adecuado para aplicaciones públicas de escritorio. |
| RF-002 | MUST | La API validará identidad y autorización en cada operación protegida. |
| RF-003 | MUST | Un usuario solo podrá consultar, cancelar o descargar sus propios trabajos y artefactos. |
| RF-004 | MUST | El cliente permitirá cerrar sesión y eliminar de forma segura las credenciales locales asociadas. |
| RF-005 | SHOULD | El operador podrá deshabilitar una cuenta o revocar su acceso. |

### 3.2 Entrada y consulta de fuente

| ID | Prioridad | Requisito |
|---|---|---|
| RF-010 | MUST | El cliente permitirá enviar una URL de una fuente admitida. |
| RF-011 | MUST | La API normalizará y validará esquema, host y formato antes de crear un trabajo. |
| RF-012 | MUST | El sistema rechazará hosts, esquemas y destinos de red no permitidos para reducir riesgo de SSRF. |
| RF-013 | SHOULD | El sistema mostrará una vista previa de metadatos antes del procesamiento, cuando la integración lo permita. |
| RF-014 | MUST | La fuente inicial del MVP será la integración existente basada en `yt-dlp`, aislada detrás de un adaptador. |

### 3.3 Ciclo de vida del trabajo

| ID | Prioridad | Requisito |
|---|---|---|
| RF-020 | MUST | La API creará trabajos de manera idempotente ante reenvíos equivalentes del cliente. |
| RF-021 | MUST | La ejecución será asíncrona y no mantendrá abierta la petición HTTP durante todo el procesamiento. |
| RF-022 | MUST | El sistema expondrá al menos los estados `queued`, `running`, `succeeded`, `failed`, `cancelled` y `expired`. |
| RF-023 | MUST | El cliente podrá consultar estado, progreso disponible y última actualización del trabajo. |
| RF-024 | MUST | Un worker que pierde un trabajo no deberá dejarlo bloqueado indefinidamente; deberá poder recuperarse mediante una concesión temporal o mecanismo equivalente. |
| RF-025 | MUST | Los reintentos automáticos serán limitados y se aplicarán únicamente a errores clasificados como transitorios. |
| RF-026 | SHOULD | El usuario podrá solicitar la cancelación mientras el trabajo no haya alcanzado un estado terminal. |
| RF-027 | MUST | Los estados terminales conservarán un código de error estable, un mensaje seguro y un identificador de correlación. |

### 3.4 Procesamiento de audio

| ID | Prioridad | Requisito |
|---|---|---|
| RF-030 | MUST | El worker seleccionará la mejor pista de audio disponible según la información real de la fuente. |
| RF-031 | MUST | El perfil inicial producirá MP3 VBR de alta calidad; los parámetros exactos deberán aprobarse mediante una ADR y pruebas de compatibilidad. |
| RF-032 | MUST | El sistema no describirá como Hi-Res una salida cuya fuente o proceso no cumpla esa característica. |
| RF-033 | MUST | El worker verificará que el resultado exista, sea legible y tenga duración razonable antes de marcar el trabajo como exitoso. |
| RF-034 | MUST | FFmpeg, FFprobe y `yt-dlp` se invocarán con argumentos controlados, límites de tiempo y sin interpolar entrada del usuario en un shell. |
| RF-035 | SHOULD | El sistema registrará versión de herramientas, formato de fuente y perfil aplicado para facilitar diagnósticos. |

### 3.5 Metadatos

| ID | Prioridad | Requisito |
|---|---|---|
| RF-040 | MUST | El archivo incluirá título y artista cuando esos datos estén disponibles. |
| RF-041 | MUST | El modelo admitirá artistas colaboradores, álbum, artista del álbum, número de pista, duración, género y año. |
| RF-042 | MUST | El sistema conservará datos técnicos reales: contenedor/tipo, códec, tasa de bits, frecuencia de muestreo y canales cuando puedan medirse. |
| RF-043 | SHOULD | El sistema incrustará carátula cuando exista una imagen válida y compatible. |
| RF-044 | MUST | La ausencia de un metadato opcional no hará fallar por sí sola el trabajo. |
| RF-045 | MUST | Los valores de texto se normalizarán y validarán antes de usarse en etiquetas o nombres de archivo. |

### 3.6 Entrega y biblioteca local

| ID | Prioridad | Requisito |
|---|---|---|
| RF-050 | MUST | Solo el propietario de un trabajo exitoso podrá descargar su resultado durante la ventana de retención. |
| RF-051 | MUST | El cliente permitirá elegir o confirmar una carpeta local autorizada por el usuario. |
| RF-052 | MUST | El cliente escribirá el archivo de forma segura y evitará sobrescrituras silenciosas. |
| RF-053 | MUST | La biblioteca local indexará la ruta, los metadatos, las propiedades técnicas y un identificador estable del archivo. |
| RF-054 | MUST | La eliminación de una entrada de biblioteca diferenciará entre quitar del índice y eliminar el archivo. |
| RF-055 | SHOULD | El cliente podrá detectar archivos movidos, ausentes o duplicados sin corromper el índice. |

### 3.7 Retención y operación

| ID | Prioridad | Requisito |
|---|---|---|
| RF-060 | MUST | Los artefactos del servidor serán temporales y tendrán una fecha de expiración. |
| RF-061 | MUST | Un proceso de limpieza eliminará artefactos vencidos y registrará el resultado sin datos sensibles. |
| RF-062 | MUST | API, worker y PostgreSQL podrán iniciarse y detenerse de forma independiente mediante contenedores. |
| RF-063 | MUST | El worker y PostgreSQL no publicarán puertos a Internet. |
| RF-064 | MUST | La API expondrá endpoints de salud diferenciando vida y disponibilidad. |
| RF-065 | SHOULD | El operador podrá consultar métricas básicas de trabajos, errores, duración, cola y almacenamiento. |

## 4. Requisitos no funcionales

### 4.1 Seguridad y privacidad

- **RNF-SEC-001 (MUST):** usar TLS en todo tráfico fuera del host y no confiar en Cloudflare como sustituto de autenticación de aplicación.
- **RNF-SEC-002 (MUST):** usar OAuth 2.1/OIDC Authorization Code con PKCE o una alternativa equivalente aprobada para el cliente de escritorio; no incluir secretos de cliente dentro de Tauri.
- **RNF-SEC-003 (MUST):** guardar tokens en el almacén seguro del sistema operativo, no en texto plano ni `localStorage`.
- **RNF-SEC-004 (MUST):** aplicar mínimo privilegio a contenedores, procesos, volúmenes y credenciales.
- **RNF-SEC-005 (MUST):** validar tamaño, tipo, rutas, URL y todo dato proveniente del cliente o proveedor.
- **RNF-SEC-006 (MUST):** nunca registrar tokens, cookies, contraseñas, URLs firmadas ni secretos.
- **RNF-SEC-007 (MUST):** aplicar rate limiting por identidad y, cuando proceda, por origen.

### 4.2 Fiabilidad

- **RNF-REL-001 (MUST):** un reinicio de API o worker no deberá perder trabajos aceptados de forma duradera.
- **RNF-REL-002 (MUST):** las transiciones de estado deberán ser atómicas y válidas.
- **RNF-REL-003 (MUST):** crear un trabajo y entregar un archivo deberán tolerar reintentos del cliente sin duplicación accidental.
- **RNF-REL-004 (SHOULD):** una falla parcial deberá dejar información suficiente para recuperación o limpieza.

### 4.3 Rendimiento y capacidad

Los valores definitivos requieren medición en el equipo inicial.

- **RNF-PERF-001 (MUST):** limitar concurrencia según CPU, memoria, disco y ancho de banda disponibles.
- **RNF-PERF-002 (MUST):** la API no deberá ejecutar transcodificación dentro del proceso de atención HTTP.
- **RNF-PERF-003 (SHOULD):** las operaciones de control de la API deberían responder en menos de 500 ms en el percentil 95, excluyendo proveedores externos y descargas.
- **RNF-PERF-004 (MUST):** definir antes de la beta límites de duración, tamaño, trabajos concurrentes y cuota temporal por usuario.

### 4.4 Mantenibilidad y portabilidad

- **RNF-MAN-001 (MUST):** separar dominio, casos de uso e infraestructura con dependencias explícitas, sin imponer una Clean Architecture ceremonial.
- **RNF-MAN-002 (MUST):** encapsular la integración `yt-dlp` detrás de una interfaz de proveedor.
- **RNF-MAN-003 (MUST):** documentar configuración mediante variables de entorno y suministrar un `.env.example` sin secretos al iniciar el código.
- **RNF-MAN-004 (MUST):** fijar versiones de herramientas y dependencias; las actualizaciones deberán probarse.
- **RNF-PORT-001 (MUST):** validar primero Windows; evitar decisiones que impidan macOS/Linux sin una ADR explícita.

### 4.5 Observabilidad y accesibilidad

- **RNF-OBS-001 (MUST):** logs estructurados con timestamp, nivel, servicio, evento, job ID y correlation ID.
- **RNF-OBS-002 (MUST):** correlacionar una solicitud desde la API hasta el worker sin exponer datos privados.
- **RNF-OBS-003 (SHOULD):** instrumentar métricas compatibles con OpenTelemetry o un estándar equivalente cuando el MVP funcional lo justifique.
- **RNF-ACC-001 (MUST):** navegación por teclado, foco visible, mensajes no dependientes solo del color y etiquetas accesibles en el cliente.

## 5. Reglas de negocio iniciales

1. Un trabajo pertenece exactamente a un usuario.
2. Solo se procesa una fuente admitida y validada.
3. Una salida nunca puede atribuirse más calidad que la medida u observada en la fuente.
4. Un trabajo exitoso tiene exactamente un artefacto principal verificable en el MVP.
5. Todo artefacto del servidor vence; la biblioteca permanente reside en el cliente.
6. Un error 403 no implica reintento infinito ni cambio automático de identidad para eludir controles.
7. El sistema debe preferir rechazar una operación insegura antes que ejecutar entrada ambigua.

## 6. Criterios de aceptación del MVP

El MVP será aceptable cuando, en un entorno reproducible:

1. Un usuario inicia sesión mediante el flujo aprobado.
2. Envía una URL permitida y recibe un identificador de trabajo.
3. Observa transiciones de estado sin mantener una conexión HTTP larga obligatoria.
4. El worker procesa un recurso de prueba autorizado y genera un MP3 reproducible.
5. FFprobe confirma el formato y los datos técnicos esperados.
6. Los metadatos disponibles se muestran tanto en el cliente como en un reproductor de referencia.
7. El usuario guarda el archivo en una carpeta elegida y la biblioteca local lo indexa.
8. Otro usuario recibe una respuesta de acceso denegado al intentar consultar o descargar ese trabajo.
9. Un reinicio controlado no pierde un trabajo aceptado.
10. Los errores 403/429/5xx siguen la política documentada y no generan bucles.
11. Los artefactos vencidos se eliminan y la acción queda registrada.
12. Las suites obligatorias de la fase se ejecutan correctamente.

## 7. Preguntas abiertas que bloquean diseño detallado

| ID | Pregunta | Decisión necesaria antes de |
|---|---|---|
| PA-001 | ¿Qué versiones y arquitecturas de Windows soportará el MVP? | Empaquetado del cliente. |
| PA-002 | ¿Qué proveedor de identidad se usará inicialmente? | Implementación de autenticación. |
| PA-003 | ¿Cuál será la retención temporal y la cuota por usuario? | Modelo de datos y limpieza. |
| PA-004 | ¿Qué límites de duración/tamaño/concurrencia aplicarán? | Implementación del worker. |
| PA-005 | ¿Qué usos y fuentes de contenido se permitirán expresamente? | Términos, validación y beta. |
| PA-006 | ¿Se aprueba PostgreSQL como cola durable inicial o se requiere un broker? | Esqueleto de procesamiento. |
| PA-007 | ¿Qué reproductores y dispositivos forman la matriz mínima de compatibilidad? | Aceptación del perfil de audio. |
| PA-008 | ¿El índice local usará SQLite desde el MVP? | Persistencia del cliente. |

### Resoluciones de la revisión de Fase 0

El 2026-08-12 el propietario aprobó el paquete D-001 a D-010:

- PA-001: Windows 11 x64 será la primera plataforma validada.
- PA-006: PostgreSQL con leases será la cola durable inicial.
- PA-008: SQLite será el índice local del cliente.
- PA-002: Keycloak autohospedado es el proveedor inicial aprobado en la entrada
  de la Fase 2. Se ejecutará en contenedores, con PostgreSQL aislado y un cliente
  público de escritorio que exige Authorization Code + PKCE S256. La API
  conservará identidad y autorización internas para evitar acoplar el dominio a
  Keycloak.
- PA-003 y PA-004 se resolverán con mediciones antes de cerrar Fase 3/iniciar procesamiento real en Fase 4.
- PA-005 mantiene como regla el procesamiento exclusivo de contenido autorizado y compatible con las condiciones aplicables.
- PA-007 usará inicialmente Windows Media Player y VLC; la matriz definitiva se aprobará en Fase 4.

## 8. Trazabilidad

Durante la implementación se mantendrá una matriz que relacione:

`requisito -> caso de uso -> endpoint/componente -> prueba -> evidencia`

Ninguna característica se considerará terminada solo porque compile o funcione manualmente una vez.

# Seguridad y cumplimiento

**Estado:** Borrador inicial  
**Versión:** 0.1  
**Fecha:** 2026-08-12

## 1. Objetivo

Definir controles mínimos antes de implementar una aplicación que recibe URLs, ejecuta herramientas multimedia, procesa archivos de terceros y puede publicarse en Internet.

Cloudflare Tunnel reduce la superficie de red del host, pero el origen continúa siendo responsable de autenticar, autorizar, validar, limitar y registrar las operaciones.

## 2. Límites de confianza

Se considera no confiable:

- toda entrada del cliente, incluso de un usuario autenticado;
- metadatos, nombres, archivos y respuestas del proveedor;
- encabezados reenviados que no estén validados por una configuración conocida del proxy;
- archivos existentes en rutas elegidas por el usuario;
- estado recuperado después de una interrupción.

Secreto no significa “incluido dentro del binario”. Una aplicación Tauri es un cliente público y no puede proteger permanentemente un `client_secret` embebido.

## 3. Autenticación recomendada

Para el cliente de escritorio:

1. OAuth 2.1/OpenID Connect Authorization Code con PKCE.
2. Autenticación en el navegador del sistema, no dentro de un WebView embebido.
3. Redirección mediante loopback o deep link conforme al proveedor y la plataforma.
4. Access tokens de corta duración; refresh tokens con rotación si son necesarios.
5. Tokens almacenados en Windows Credential Manager y equivalentes del sistema operativo mediante una abstracción segura.

La API validará firma, emisor, audiencia, expiración y claims requeridos. La autorización por propietario se ejecutará después de autenticar cada petición.

## 4. Amenazas y controles

| Amenaza | Ejemplo | Control mínimo |
|---|---|---|
| IDOR/BOLA | Consultar el `jobId` de otro usuario | Filtrar siempre por `job_id` y `owner_id`; pruebas negativas. |
| SSRF | URL que resuelve a localhost o red privada | Allowlist de esquema/host, resolución segura, sin fetch genérico desde la API. |
| Inyección de comandos | Título o URL insertado en una cadena shell | API de procesos con lista de argumentos; nunca `shell=true`; validación y límites. |
| Path traversal | Metadato `../../archivo` usado como nombre | Nombre generado por la aplicación, saneamiento y confinamiento a directorios permitidos. |
| Archivo hostil | Carátula enorme, formato malicioso | Límites de tamaño/tipo/dimensiones y decodificadores actualizados. |
| Agotamiento de recursos | Muchos trabajos largos | Cuotas, rate limiting, cola, concurrencia, timeouts y límites de disco. |
| Robo de tokens | Persistencia en `localStorage` o logs | Almacén seguro del SO, CSP estricta y logs redactados. |
| XSS en WebView | Metadatos renderizados como HTML | Escape por defecto, CSP, sin HTML arbitrario y capacidades Tauri mínimas. |
| Supply chain | Binario o paquete comprometido | Versiones fijadas, lockfiles, SBOM futura, escaneo y actualización controlada. |
| Fuga de artefactos | URL predecible o volumen expuesto | Descarga autenticada, autorización, identificadores no enumerables y expiración. |

## 5. Validación de URL y proveedor

- Admitir únicamente `https` y hosts explícitamente soportados.
- Normalizar antes de calcular idempotencia o aplicar políticas.
- No aceptar URLs arbitrarias para que el servidor las descargue.
- Impedir redirecciones hacia destinos no permitidos cuando la integración lo pueda controlar.
- Limitar cantidad de redirecciones, duración, tamaño y velocidad de transferencia.
- Encapsular `yt-dlp` para que solo reciba opciones aprobadas por el sistema.
- Nunca aceptar argumentos adicionales de CLI enviados por el cliente.

## 6. Tratamiento responsable de 403 y límites del proveedor

Un dominio delegado a Cloudflare **no elimina** un 403 emitido por el proveedor externo. El túnel protege el tráfico cliente → API; la solicitud worker → proveedor normalmente sale desde la misma IP del servidor. Hacer que Cloudflare actúe como proxy no garantiza acceso y no debe usarse para ocultar automatización o eludir controles.

Política inicial:

1. Clasificar el origen del 403: nuestra API/Cloudflare, autenticación, contenido no disponible, restricción regional, rate limit o control del proveedor.
2. Registrar código interno, proveedor, intento y correlation ID sin guardar cookies o tokens.
3. Respetar `Retry-After` cuando exista.
4. Aplicar backoff exponencial con jitter solo a fallos razonablemente transitorios.
5. Limitar intentos y abrir un circuit breaker ante fallos repetidos.
6. Reducir concurrencia y cachear metadatos permitidos para evitar solicitudes redundantes.
7. Marcar como terminales los casos de contenido privado, eliminado, no autorizado o explícitamente bloqueado.
8. Mostrar al usuario una explicación accionable, no un bucle automático.

No se implementarán rotación agresiva de IP, suplantación de identidades, bypass de CAPTCHA, uso indebido de cookies ni otras técnicas de evasión. Si el proveedor ofrece una API o flujo autorizado que cubra la necesidad, será preferible.

## 7. Seguridad de contenedores

- Ejecutar como usuario no root cuando las imágenes lo permitan.
- Imágenes mínimas, versiones fijadas y compilación multi-stage.
- Sistema de archivos raíz de solo lectura cuando sea viable.
- Eliminar capacidades Linux innecesarias y evitar `privileged`.
- Límites de CPU, memoria, procesos y almacenamiento.
- Health checks sin exponer información sensible.
- PostgreSQL solo en la red privada, con credenciales distintas por servicio si el modelo lo requiere.
- El worker escribe en el volumen temporal; la API recibe solo los permisos mínimos para entregar o eliminar según diseño.
- Secretos suministrados en runtime; nunca en imagen, repositorio ni `.env` versionado.

## 8. Seguridad del cliente Tauri

- Allowlist/capabilities mínima para comandos nativos.
- Validar de nuevo en Rust toda entrada que cruza desde el frontend.
- CSP restrictiva; evitar contenido remoto dentro del WebView.
- Actualizaciones firmadas cuando se implemente auto-update.
- Firma de instaladores antes de distribución pública.
- Rutas canónicas y permisos explícitos para lectura/escritura.
- Operaciones de archivo atómicas cuando sea posible.
- Diferenciar claramente “quitar de biblioteca” de “eliminar del disco”.

## 9. Protección de datos

Datos mínimos en servidor:

- identificador del usuario del proveedor de identidad;
- información necesaria del trabajo, auditoría operativa y expiración;
- metadatos y artefactos solo durante su retención.

Antes de una beta pública deben existir:

- aviso de privacidad y términos de uso;
- política de retención y eliminación;
- mecanismo de exportación/eliminación cuando sea legalmente requerido;
- inventario de subprocesadores y ubicación de datos;
- revisión de licencias, derechos de autor y condiciones de cada fuente.

## 10. Respuestas y logs seguros

- El usuario recibe un mensaje comprensible y un `correlationId`.
- El detalle interno, stack trace, argumentos completos y rutas del host no salen por la API.
- Las URLs podrán contener identificadores sensibles: deben redactarse o resumirse en logs.
- Los eventos de seguridad incluyen autenticaciones fallidas relevantes, denegaciones de autorización, límites activados y cambios operativos.
- Los logs necesitan retención y control de acceso; no constituyen por sí solos una auditoría legal.

## 11. Checklist antes de exponer el servicio

- [ ] Modelo de amenazas revisado.
- [ ] OIDC/PKCE y autorización por recurso probados.
- [ ] Validación SSRF y de argumentos probada con casos hostiles.
- [ ] Rate limits, cuotas, timeouts y concurrencia configurados.
- [ ] Secretos fuera del repositorio y rotables.
- [ ] Contenedores sin puertos innecesarios ni privilegios elevados.
- [ ] Errores seguros y logs sin credenciales.
- [ ] Política 403/429 probada sin evasión.
- [ ] Retención y limpieza verificadas.
- [ ] Dependencias y binarios escaneados y fijados.
- [ ] Términos, privacidad y uso permitido definidos para la audiencia real.

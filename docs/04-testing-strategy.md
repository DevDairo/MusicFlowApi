# Estrategia de pruebas

**Estado:** Vigente
**Versión:** 0.2
**Fecha:** 2026-08-12

## 1. Objetivo

Las pruebas proporcionarán evidencia de que cada requisito importante funciona, incluidos errores y casos límite. No se avanzará de fase por una demostración manual aislada.

La estrategia sigue una pirámide pragmática: muchas pruebas unitarias rápidas, suficientes integraciones reales, pocos recorridos end-to-end críticos y pruebas especializadas para seguridad, recuperación y compatibilidad.

## 2. Niveles de prueba

| Nivel | Alcance | Ejemplos |
|---|---|---|
| Estáticas | Código y configuración sin ejecutar el sistema | Compilación, tipos, lint, formato, análisis de dependencias y configuración Docker. |
| Unitarias | Regla o componente aislado | Transiciones de trabajo, normalización de metadatos, clasificación de errores, nombres seguros. |
| Integración | Componente con infraestructura real controlada | Repositorios PostgreSQL, leases, migraciones, almacenamiento temporal, comandos de FFmpeg. |
| Contrato | Acuerdo entre cliente, API y worker | OpenAPI, esquema de errores, estados, compatibilidad hacia atrás. |
| API | Comportamiento HTTP | Autenticación, autorización, idempotencia, validación, rate limiting, descarga. |
| End-to-end | Flujo crítico completo | Login, trabajo, procesamiento de fixture autorizado, descarga e índice local. |
| Seguridad | Abuso y controles | IDOR, SSRF, inyección, traversal, tokens vencidos, archivos hostiles. |
| Recuperación | Fallas operativas | Reinicio de worker, lease vencido, disco lleno, corte de DB, limpieza interrumpida. |
| Compatibilidad | Archivo y cliente | Reproducción/etiquetas en matriz de Windows; empaquetado e instalación. |
| Rendimiento | Capacidad medida | Cola, concurrencia, CPU/memoria/disco, latencia API y transferencia. |

## 3. Qué probar primero

Prioridad de cobertura:

1. Autorización por propietario y aislamiento entre usuarios.
2. Máquina de estados, idempotencia y recuperación de trabajos.
3. Validación de URLs, argumentos de procesos y rutas.
4. Clasificación de errores y política de reintentos.
5. Verificación del resultado y normalización de metadatos.
6. Retención y limpieza.
7. Persistencia segura de la biblioteca local.
8. Casos felices de interfaz.

Una cifra global de cobertura no reemplaza esta priorización. Como referencia, las reglas de dominio críticas deberán tener cobertura de ramas alta y casos límite explícitos; el umbral exacto se decidirá con el stack.

## 4. Entornos y fixtures

- Herramientas y dependencias se ejecutarán dentro de contenedores o toolchains documentados; no se dependerá de instalaciones globales accidentales.
- Las pruebas de integración levantarán PostgreSQL real y almacenamiento temporal desechable.
- Los medios pequeños de prueba deberán ser propios, licenciados o expresamente autorizados.
- Las respuestas del proveedor se representarán mediante fixtures sanitizados para pruebas deterministas.
- Una prueba smoke opcional podrá consultar la fuente real bajo límites estrictos; no será la única evidencia ni bloqueará todo CI por una indisponibilidad externa.
- Nunca se guardarán cookies, tokens o contenido no autorizado en fixtures.

## 5. Matriz de errores mínima

| Escenario | Resultado esperado |
|---|---|
| URL malformada o host no permitido | Rechazo 4xx sin crear trabajo. |
| Idempotency-Key repetida con mismo payload | Mismo resultado lógico, sin trabajo duplicado. |
| Idempotency-Key repetida con payload distinto | Conflicto explícito. |
| Trabajo ajeno | 404 o 403 según política, sin fuga de existencia/datos. |
| Proveedor responde 403 terminal | Trabajo `failed`, sin reintento infinito. |
| Proveedor responde 429 con `Retry-After` | Reprogramación limitada y observable. |
| Worker termina abruptamente | Lease vence y el trabajo se recupera de forma segura. |
| FFmpeg excede timeout | Proceso finalizado, artefacto parcial limpiado, error clasificado. |
| Metadato contiene traversal o caracteres inválidos | Nombre seguro; ninguna escritura fuera del directorio permitido. |
| Disco temporal sin espacio | Falla controlada, sin marcar éxito y con alerta operativa. |
| Artefacto fue alterado o falta | Descarga rechazada; trabajo/artefacto marcado para diagnóstico. |
| Token vencido o audiencia incorrecta | 401 sin detalle sensible. |

## 6. Compatibilidad de audio

Por cada perfil aprobado se verificará automáticamente con FFprobe:

- contenedor y códec esperados;
- duración dentro de tolerancia;
- tasa de bits, frecuencia de muestreo y canales reales;
- presencia y codificación de etiquetas obligatorias disponibles;
- carátula válida cuando corresponda;
- checksum y tamaño no nulo.

La aceptación manual inicial debe incluir reproductores representativos de Windows. La matriz exacta es una pregunta abierta del SRS y luego crecerá para macOS/Linux.

## 7. Pruebas del cliente

- Unitarias para estado de UI, validadores y adaptadores de API.
- Integración de comandos Tauri, permisos y persistencia local.
- Pruebas de navegación por teclado y semántica accesible.
- End-to-end del instalador y flujo principal en Windows soportado.
- Pruebas de rutas largas, Unicode, colisiones, archivo existente y disco sin permisos.
- Verificación de que cerrar sesión elimina credenciales locales sin borrar la biblioteca por accidente.

## 8. Ejecución actual y automatización futura

Durante la etapa personal inicial, cada rama se validará manualmente antes del merge siguiendo el flujo documentado en [Flujo manual de control de versiones](10-manual-version-control-workflow.md). Un cambio que afecte al backend, contenedores, dependencias o migraciones debe ejecutar `scripts/verify.ps1` y conservar el resultado en la revisión del incremento.

GitHub Actions queda aplazado hasta que el propietario decida abordarlo como un incremento de aprendizaje independiente. Las ramas no sustituyen las pruebas: la puerta manual es obligatoria mientras no exista automatización remota.

Una futura integración continua debería ejecutar como mínimo:

1. formato, lint y compilación/tipos;
2. unitarias;
3. pruebas de migraciones e integración con servicios efímeros;
4. contrato OpenAPI;
5. escaneo de secretos, dependencias e imágenes;
6. build reproducible de contenedores;
7. artefactos y reportes de prueba.

Las pruebas E2E de escritorio y smoke del proveedor pueden ejecutarse en pipelines separados y controlados por costo/estabilidad.

## 9. Puertas de calidad

Una fase puede cerrarse solo si:

- los criterios de aceptación de esa fase tienen evidencia;
- no quedan defectos críticos ni importantes sin decisión explícita;
- las pruebas obligatorias están en verde y son repetibles;
- los hallazgos de seguridad relevantes fueron corregidos o aceptados formalmente;
- documentación, migraciones y contratos coinciden con el comportamiento;
- existe un procedimiento de reversión o recuperación proporcional al cambio.

Un test flaky no se ignora: se corrige, se aísla temporalmente con responsable/fecha o se elimina si no aporta señal.

## 10. Evidencia por requisito

Se creará una matriz de trazabilidad, por ejemplo:

| Requisito | Prueba | Tipo | Evidencia |
|---|---|---|---|
| RF-003 | `cannot_read_another_users_job` | API/seguridad | Reporte de pruebas |
| RF-024 | `expired_lease_is_reclaimed_once` | Integración/recuperación | Reporte de pruebas |
| RF-033 | `rejects_invalid_output` | Integración multimedia | Log de prueba + fixture |

La tabla completa aparecerá al iniciar la implementación y se mantendrá junto al código.

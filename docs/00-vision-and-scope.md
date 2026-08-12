# Visión y alcance

**Estado:** Borrador para revisión  
**Versión:** 0.1  
**Fecha:** 2026-08-12

## 1. Visión del producto

MusicFlow será una aplicación de escritorio que permita a un usuario autenticado solicitar el procesamiento de audio desde una fuente admitida, recibir un archivo compatible de alta calidad con metadatos consistentes y guardarlo en su biblioteca local.

El producto comienza como una herramienta personal, pero se diseñará para evolucionar hacia un servicio público sin reconstruir sus límites principales de seguridad, identidad, procesamiento y persistencia.

## 2. Problema que resuelve

El prototipo beta demostró el flujo principal, pero una aplicación web tiene restricciones para administrar de forma fiable una biblioteca local y un backend monolítico mezcla responsabilidades de exposición pública, procesamiento multimedia y almacenamiento.

La siguiente versión debe:

- ofrecer una experiencia nativa de escritorio;
- aislar el trabajo intensivo de procesamiento;
- mantener los archivos finales bajo control del usuario;
- gestionar errores y límites de proveedores de manera explícita y responsable;
- poder desplegarse localmente hoy y migrar a infraestructura dedicada en el futuro.

## 3. Usuarios y actores

| Actor | Necesidad principal |
|---|---|
| Usuario autenticado | Solicitar, seguir, descargar y organizar audio autorizado. |
| Operador del sistema | Configurar, observar y mantener la plataforma. |
| Proveedor externo | Entregar información o medios conforme a sus condiciones. |
| Cliente Tauri | Consumir la API y administrar archivos/biblioteca local. |
| Worker | Ejecutar trabajos multimedia sin estar expuesto a Internet. |

## 4. Objetivos del MVP

1. Proporcionar autenticación robusta para una aplicación de escritorio.
2. Aceptar una URL válida de la fuente inicial admitida.
3. Crear un trabajo asíncrono, mostrar su estado y permitir recuperar el resultado.
4. Obtener la mejor pista de audio disponible en la fuente, sin inventar calidad.
5. Generar un MP3 ampliamente compatible, con metadatos y carátula cuando estén disponibles.
6. Autorizar cada operación y aislar los trabajos por usuario.
7. Guardar el archivo final y la información de biblioteca en el equipo del usuario.
8. Eliminar artefactos temporales del servidor según una política definida.
9. Proporcionar logs estructurados, identificadores de correlación y health checks.
10. Ejecutar API, worker y PostgreSQL en contenedores separados.

## 5. Alcance funcional del MVP

- Inicio y cierre de sesión.
- Envío de una URL y validación de la fuente.
- Consulta previa de metadatos básicos, cuando la fuente lo permita.
- Creación idempotente de trabajos de procesamiento.
- Estados de trabajo, progreso aproximado y errores comprensibles.
- Descarga autorizada del resultado terminado.
- Selección de carpeta de destino desde el cliente.
- Índice local de biblioteca con metadatos técnicos y descriptivos.
- Reintentos limitados para fallos transitorios.
- Limpieza automática de archivos temporales.

## 6. Fuera del alcance inicial

- Aplicaciones móviles Android o iOS.
- Reproducción o streaming desde el servidor.
- Sincronización de la biblioteca entre dispositivos.
- Almacenamiento permanente de bibliotecas en la nube.
- Pagos, suscripciones o publicidad.
- Kubernetes, microservicios o múltiples bases de datos.
- Compatibilidad simultánea con múltiples proveedores.
- Evasión de CAPTCHA, bloqueos, controles antiabuso o restricciones de acceso.
- Promesas de Hi-Res, mejora artificial o restauración de información inexistente en la fuente.

## 7. Definición de “calidad compatible”

Para el MVP, “calidad compatible” significa:

- seleccionar la mejor pista de audio realmente disponible;
- evitar transcodificar más veces de las necesarias;
- producir MP3 VBR de alta calidad como perfil inicial;
- usar etiquetas ID3 compatibles y carátula incrustada cuando sea posible;
- conservar y exponer las propiedades técnicas reales del archivo.

MP3 no es un formato Hi-Res sin pérdidas. Esta elección prioriza reproducción universal y tamaño razonable. En una fase futura podrán evaluarse perfiles adicionales como FLAC u Opus, siempre distinguiendo el formato de entrega de la calidad real de la fuente.

## 8. Restricciones y supuestos

- El despliegue inicial se ejecutará en el computador del propietario mediante Docker.
- El dominio se encuentra delegado a Cloudflare y podrá usar Cloudflare Tunnel.
- El cliente nunca se conectará directamente al worker ni a PostgreSQL.
- La disponibilidad depende parcialmente de una fuente externa que puede cambiar sin previo aviso.
- El contenido solo debe procesarse cuando el usuario tenga autorización y el uso sea compatible con las condiciones aplicables.
- Tauri 2 es la dirección elegida; la primera plataforma validada será Windows.

## 9. Indicadores iniciales de éxito

Los objetivos numéricos se fijarán después de medir el prototipo. Como base:

- ningún usuario puede acceder a trabajos o archivos de otro usuario;
- los trabajos aceptados sobreviven al reinicio del proceso responsable;
- cada error terminal conserva una causa rastreable sin exponer secretos;
- un archivo válido se reproduce y muestra sus metadatos en reproductores representativos de Windows;
- un trabajo terminado deja de ocupar almacenamiento temporal al vencer su retención;
- cada fase cumple sus pruebas antes de avanzar.

## 10. Riesgos principales

| Riesgo | Impacto | Tratamiento inicial |
|---|---|---|
| Cambios o bloqueos del proveedor | Alto | Adaptador aislado, pruebas controladas, límites y errores explícitos. |
| Uso no autorizado de contenido | Alto | Términos claros, confirmación del usuario y alcance permitido. |
| Ejecución insegura de herramientas CLI | Alto | Argumentos estructurados, sin shell libre y con límites de recursos. |
| Saturación de CPU, red o disco | Alto | Cola, concurrencia limitada, cuotas y limpieza temporal. |
| Exposición de datos entre usuarios | Crítico | Autorización por recurso y pruebas negativas. |
| Diferencias entre sistemas operativos | Medio | Abstracciones Tauri y matriz de compatibilidad incremental. |
| Complejidad prematura | Medio | Monolito modular para la API y un único worker desplegable. |

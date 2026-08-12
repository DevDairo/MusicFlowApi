# ADR-0002: Separar API, worker y PostgreSQL en contenedores

- **Estado:** Accepted
- **Fecha:** 2026-08-12
- **Responsables:** propietario del proyecto

## Contexto

La API expuesta a usuarios y el procesamiento con `yt-dlp`/FFmpeg tienen perfiles de seguridad, recursos y disponibilidad distintos. PostgreSQL necesita persistencia y una superficie de red privada. El despliegue inicial será un solo computador con Docker, con opción futura de migrar a VPS o servidor dedicado.

## Decisión

Desplegar como mínimo tres contenedores independientes:

1. `api`: único servicio de aplicación alcanzable mediante Cloudflare Tunnel.
2. `worker`: procesa trabajos y no publica puertos.
3. `postgres`: persistencia privada, sin exposición a Internet.

`cloudflared` podrá ejecutarse como un cuarto contenedor o proceso administrado, pero solo conectará el dominio con la API.

API y worker podrán compartir repositorio y paquetes internos. Esta decisión establece límites de despliegue, no una arquitectura de microservicios.

## Alternativas consideradas

### Un solo contenedor de aplicación

Es más simple al principio, pero mezcla servidor HTTP y procesos multimedia, dificulta límites de recursos y amplía el impacto de fallos.

### Procesamiento dentro de Tauri

Reduce infraestructura del servidor, pero desplaza binarios, compatibilidad y comportamiento del proveedor a cada cliente; además cambia el modelo de producto acordado.

### Microservicios completos y broker desde el inicio

Permiten escalado y aislamiento fino, pero agregan despliegue, contratos, observabilidad y fallos distribuidos innecesarios para el MVP.

## Consecuencias

### Positivas

- Límites de red y permisos más claros.
- Reinicio y escalado independiente del worker.
- Reproducción del entorno sin instalar dependencias multimedia globalmente.
- Migración futura de host con menor divergencia.

### Negativas y riesgos

- Docker Compose, redes, volúmenes y builds requieren mantenimiento.
- El volumen temporal compartido debe diseñarse con permisos estrictos.
- Los contratos API-worker y las migraciones necesitan compatibilidad.
- Un solo host continúa siendo un punto único de fallo.

## Validación

- Docker Compose inicia el entorno desde cero.
- El host no publica worker ni PostgreSQL.
- El worker puede reiniciarse sin perder trabajos aceptados.
- El API no ejecuta procesamiento multimedia en su proceso.
- Health checks y logs permiten identificar el contenedor responsable.

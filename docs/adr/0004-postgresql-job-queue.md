# ADR-0004: Usar PostgreSQL como cola durable inicial

- **Estado:** Accepted
- **Fecha:** 2026-08-12
- **Responsables:** propietario del proyecto

## Contexto

El procesamiento debe ser asíncrono, sobrevivir reinicios y permitir que uno o varios workers reclamen trabajos sin duplicarlos. PostgreSQL ya es necesario para usuarios, estados y metadatos. Introducir un broker dedicado desde la primera fase aumenta componentes operativos.

## Decisión

Usar una tabla de trabajos en PostgreSQL como cola durable del MVP. Los workers reclamarán trabajos disponibles dentro de una transacción mediante bloqueo de filas, por ejemplo `FOR UPDATE SKIP LOCKED`, y registrarán una concesión temporal (`lease`) con expiración.

El diseño incluirá:

- estados y transiciones restringidas;
- `available_at`, intentos máximos y backoff;
- `lease_owner` y `lease_expires_at`;
- heartbeats solo si la duración lo requiere;
- idempotencia del resultado y verificación antes de finalizar;
- proceso de recuperación de leases vencidos;
- índices alineados con consulta de la cola;
- historial de intentos separado.

## Alternativas consideradas

### Redis con una biblioteca de jobs

Buen rendimiento y ecosistema de colas, pero añade otra persistencia, configuración de durabilidad y operación. Puede ser apropiado cuando la tecnología elegida tenga una biblioteca madura y la carga lo justifique.

### RabbitMQ

Ofrece enrutamiento, acknowledgements y semánticas de mensajería potentes. Para una cola sencilla con estado transaccional en PostgreSQL supone más infraestructura y coordinación.

### Kafka

Adecuado para streams durables, alto volumen y múltiples consumidores. Es sobreingeniería para trabajos multimedia del MVP.

### Cola en memoria

Muy simple, pero pierde trabajos al reiniciar y no satisface RNF-REL-001.

## Consecuencias

### Positivas

- Un único sistema durable que operar y respaldar.
- Creación de trabajo y encolado en la misma transacción.
- Semántica visible y comprobable con SQL.
- Ruta suficiente para carga inicial moderada.

### Negativas y riesgos

- El polling introduce consultas y latencia.
- Consultas o índices incorrectos pueden causar contención.
- Leases, reintentos e idempotencia deben implementarse cuidadosamente.
- No ofrece todas las capacidades de un broker especializado.

## Criterios para aceptar

- Prueba con workers concurrentes demuestra que un trabajo no es reclamado activamente por dos workers.
- Un worker finalizado a la fuerza libera el trabajo al expirar el lease.
- La creación del trabajo y su disponibilidad son atómicas.
- La carga medida no degrada las operaciones principales de la API.
- Backups/restauración conservan estados coherentes.

## Señales para reemplazarla

Reevaluar un broker dedicado si aparecen, con mediciones:

- contención o carga de polling significativa sobre PostgreSQL;
- muchos tipos de mensajes y consumidores independientes;
- necesidad de prioridades/ruteo avanzados;
- escalado de workers que excede el patrón simple;
- requisitos de entrega que la implementación no pueda garantizar con claridad.

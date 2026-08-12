# Revisión de salida de la Fase 0

**Estado de la puerta:** Aprobada y cerrada  
**Versión:** 1.0  
**Fecha:** 2026-08-12

## 1. Resultado

El análisis de producto, requisitos, arquitectura, seguridad, pruebas y código beta está completo. No se encontraron razones para continuar el monolito beta; sí existe un camino incremental claro para iniciar el esqueleto técnico.

El propietario aprobó expresamente el paquete D-001 a D-010 el 2026-08-12. Las decisiones aplazadas incluyen una fase límite y no bloquean el primer incremento de infraestructura.

## 2. Evidencia disponible

- visión, alcance y límites del MVP;
- requisitos funcionales y no funcionales identificados;
- arquitectura cliente/API/worker/PostgreSQL;
- modelo de amenazas inicial y política responsable ante 403;
- estrategia de pruebas y puertas de calidad;
- roadmap y proceso de desarrollo;
- diagnóstico estructurado del beta;
- ADR de Tauri, contenedores, perfil de audio y cola.

## 3. Paquete de decisiones recomendado

| ID | Decisión recomendada | Estado propuesto | Motivo |
|---|---|---|---|
| D-001 | Tauri 2 + React + TypeScript para el cliente | Aprobada | Portabilidad, tipado y capacidades nativas controlables. |
| D-002 | Python + FastAPI para API y worker | Aprobada | Reduce riesgo de migración y mejora contratos/validación frente al beta. |
| D-003 | PostgreSQL + SQLAlchemy 2 + Alembic | Aprobada | Persistencia transaccional, migraciones y concurrencia. |
| D-004 | PostgreSQL como cola durable con leases | Aprobada para MVP | Evita un broker prematuro; debe probarse con workers concurrentes. |
| D-005 | SQLite para el índice de biblioteca del cliente | Aprobada | Persistencia local simple, portable y transaccional. |
| D-006 | Primera plataforma: Windows 11 x64 | Aprobada | Evita comprometerse inicialmente con sistemas fuera de soporte. |
| D-007 | Fuente inicial por URL; búsqueda como `SHOULD` posterior | Aprobada | Menos solicitudes externas y menor superficie de fallos en el primer recorrido. |
| D-008 | MP3 VBR de alta calidad + ID3v2.3 | Aprobada; parámetros sujetos a pruebas | Compatibilidad amplia sin afirmar Hi-Res inexistente. |
| D-009 | API única entrada pública por Cloudflare Tunnel | Aprobada | Mantiene worker y DB privados; Cloudflare no sustituye seguridad de aplicación. |
| D-010 | Código nuevo en `MusicFlow`; beta permanece solo como referencia | Aprobada | Evita heredar acoplamientos y riesgos críticos. |

## 4. Decisiones aplazadas con límite

Estas decisiones no impiden construir health checks, contenedores y persistencia inicial:

| Pregunta | Recomendación temporal | Debe resolverse antes de |
|---|---|---|
| Proveedor OIDC | Mantener contrato estándar OIDC/PKCE; comparar servicio administrado frente a self-hosting. | Fase 2 — identidad. |
| Retención de artefactos | Valor de desarrollo configurable; propuesta inicial 24 horas. | Modelo final de Fase 3. |
| Límites de trabajos | Concurrencia global del worker = 1 en el equipo local. | Integración real de Fase 4. |
| Duración/tamaño máximos | Medir fixtures y capacidad del host antes de fijarlos. | Integración real de Fase 4. |
| Matriz de reproductores | Windows Media Player y VLC como base; ampliar según usuarios. | Aceptación de Fase 4. |
| Firma y auto-update | Diseñar claves/proceso sin activarlos en desarrollo. | Beta privada de Fase 6. |

## 5. Riesgos aceptados para el primer incremento

- El cliente Tauri todavía no se compilará hasta definir una estrategia que respete la restricción de no instalar toolchains globales en Windows.
- El primer Compose no tendrá proveedor real ni procesamiento multimedia.
- La autenticación será una interfaz/placeholder de diseño, no una simulación insegura presentada como producción.
- El túnel Cloudflare no se activará durante el desarrollo inicial.
- Las versiones se fijarán y bloquearán desde contenedores; nada se instalará globalmente en el host.

## 6. Primer incremento propuesto de la Fase 1

Crear únicamente:

1. estructura de monorepo;
2. imagen multi-stage para API y worker con runtimes separados;
3. Docker Compose con API, worker y PostgreSQL 18 en red privada;
4. configuración validada y `.env.example` sin secretos;
5. `/health/live` y `/health/ready`;
6. worker que comprueba conexión y termina limpiamente, sin descargar contenido;
7. migración inicial mínima;
8. logs estructurados y correlation ID;
9. pruebas unitarias/integración del incremento;
10. comandos de verificación ejecutados dentro de Docker.

No incluirá todavía login, endpoints de trabajos, `yt-dlp`, FFmpeg, biblioteca ni UI final.

## 7. Criterios para cerrar la puerta

- [x] Requisitos y alcance documentados.
- [x] Arquitectura y seguridad iniciales documentadas.
- [x] Código beta diagnosticado sin modificarlo.
- [x] Estrategia de pruebas y fases definida.
- [x] Paquete D-001 a D-010 aprobado por el propietario.
- [x] ADR-0004 cambia de `Proposed` a `Accepted`.
- [x] Fase 0 marcada como cerrada y baseline documental versionada.

## 8. Decisión registrada

El propietario respondió “apruebo” el 2026-08-12. La Fase 1 puede comenzar exclusivamente con el incremento definido en la sección 6.

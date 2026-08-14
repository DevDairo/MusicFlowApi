# Fase 2 — incremento 6: controles de salida de seguridad

## 1. Estado

Estado técnico: **verificación automatizada superada el 14 de agosto de 2026**.

Estado de la puerta: **aprobada el 14 de agosto de 2026**.

Este incremento cierra la brecha detectada al revisar la puerta global de la
Fase 2. La identidad y la autorización del incremento 5 funcionaban, pero aún
faltaban rate limiting inicial, eventos explícitos de auditoría segura y una
prueba operativa de revocación.

## 2. Objetivo y alcance

Se incorpora:

- limitación de solicitudes protegidas por origen antes de validar el token;
- limitación independiente por identidad interna después de autenticarla;
- respuesta estable `429 Too Many Requests` con `Retry-After`;
- eventos estructurados de autenticación aceptada, rechazada, limitada y de
  autorización denegada;
- prueba explícita de access token vencido;
- procedimiento manual de revocación y documentación del riesgo residual.

No se incorpora Redis, una base de auditoría legal, introspección OIDC por cada
petición ni reglas WAF. Tampoco se inicia todavía la cola de trabajos de la
Fase 3.

## 3. Decisión técnica

Se usa una ventana deslizante acotada en memoria dentro de la única instancia
actual de la API.

| Alternativa | Ventaja | Costo o riesgo | Decisión |
| --- | --- | --- | --- |
| Limitador local | Sin dependencia nueva, rápido y suficiente para una instancia | No comparte conteos entre réplicas y se reinicia con el proceso | Elegido para el MVP local |
| Redis | Conteo distribuido y persistencia temporal | Nuevo servicio, operación, secretos y fallos adicionales | Aplazado hasta tener más de una réplica |
| Solo Cloudflare | Protege el perímetro | No aplica cuotas por identidad dentro de la aplicación | Complemento futuro, no sustituto |
| Introspección por petición | Revocación de sesión más inmediata | Acopla cada petición a Keycloak y aumenta latencia/disponibilidad requerida | Rechazada para el MVP |

La abstracción `SlidingWindowRateLimiter` mantiene esta decisión reemplazable.
La memoria se limita a un número configurable de claves; cuando se alcanza el
máximo, primero se purgan ventanas vencidas y después se expulsa la menos
reciente. Esto evita crecimiento sin límite ante orígenes variables.

## 4. Frontera de confianza del origen

La API acepta `CF-Connecting-IP` únicamente si la opción correspondiente está
activa y el valor es una dirección IPv4 o IPv6 válida. No confía en
`X-Forwarded-For`. Si el encabezado no es válido, utiliza la dirección del peer.

Esta configuración es válida porque la API pública se alcanza mediante
Cloudflare Tunnel y el puerto del host está enlazado solo a `127.0.0.1`. Si en
el futuro la API se publica directamente o detrás de otro proxy, se debe
desactivar `MUSICFLOW_TRUST_CLOUDFLARE_CONNECTING_IP` o definir una lista
explícita de proxies confiables.

La dirección nunca se escribe en los eventos de seguridad. El límite por
origen usa un valor mayor que el límite por identidad para reducir ataques
antes de JWT/DB sin agrupar injustamente el uso normal de una cuenta.

## 5. Configuración

| Variable | Valor inicial | Propósito |
| --- | ---: | --- |
| `MUSICFLOW_RATE_LIMIT_ENABLED` | `true` | Permite desactivar el control solo para diagnóstico acotado |
| `MUSICFLOW_RATE_LIMIT_WINDOW_SECONDS` | `60` | Duración de la ventana deslizante |
| `MUSICFLOW_RATE_LIMIT_ORIGIN_REQUESTS` | `120` | Máximo por origen y ventana |
| `MUSICFLOW_RATE_LIMIT_IDENTITY_REQUESTS` | `60` | Máximo por identidad y ventana |
| `MUSICFLOW_RATE_LIMIT_MAX_KEYS` | `10000` | Límite de claves retenidas por limitador |
| `MUSICFLOW_TRUST_CLOUDFLARE_CONNECTING_IP` | `true` | Usa el encabezado validado del túnel |

Los valores deben ajustarse con métricas reales. Reducirlos sin medir puede
convertir el control en una denegación de servicio para usuarios legítimos.

## 6. Contrato HTTP

Cuando se supera un límite, el endpoint protegido responde:

```http
HTTP/1.1 429 Too Many Requests
Retry-After: 37
Content-Type: application/json
```

```json
{
  "detail": {
    "code": "rate_limit_exceeded",
    "message": "Too many authentication requests. Try again later."
  }
}
```

Los endpoints `/health/live` y `/health/ready` no pasan por la dependencia de
autenticación y conservan su semántica. La cabecera `X-Correlation-ID` también
se mantiene en la respuesta `429`.

## 7. Auditoría segura

| Evento | Nivel | Campos permitidos |
| --- | --- | --- |
| `authentication_succeeded` | INFO | `correlation_id`, UUID interno |
| `authentication_rejected` | WARNING | `correlation_id`, motivo general |
| `authentication_rate_limited` | WARNING | `correlation_id`, alcance y segundos de espera |
| `authorization_denied` | WARNING | `correlation_id`, motivo y UUID internos |

No se registran bearer tokens, refresh tokens, contraseñas, subjects externos,
correos, cuerpos de petición ni direcciones de origen. Estos eventos sirven
para operación y diagnóstico; no constituyen una auditoría legal inmutable.

## 8. Revocación y riesgo residual

MusicFlow usa access tokens JWT validados localmente. Deshabilitar una cuenta o
cerrar su sesión en Keycloak impide obtener tokens nuevos, pero no invalida de
forma instantánea un access token ya emitido. El riesgo queda limitado por su
vida configurada de diez minutos.

El cliente realiza logout remoto de mejor esfuerzo, elimina siempre el refresh
token del almacén del sistema y borra la sesión en memoria. Si Keycloak devuelve
`invalid_grant` durante un refresh, el cliente también elimina el refresh token
local.

### Prueba manual de revocación

Usar una cuenta beta de prueba, nunca la cuenta administrativa:

1. iniciar sesión en MusicFlow y confirmar que `/v1/me` funciona;
2. cerrar y abrir el cliente para confirmar que el refresh token restaura la
   sesión;
3. en el realm `musicflow`, abrir la cuenta de prueba, cerrar sus sesiones y
   deshabilitar temporalmente el usuario;
4. cerrar por completo MusicFlow y abrirlo nuevamente;
5. comprobar que la sesión no se restaura y que el cliente vuelve a solicitar
   autenticación;
6. reactivar la cuenta de prueba y confirmar que un login nuevo vuelve a
   funcionar;
7. cerrar sesión desde MusicFlow, reiniciar el cliente y confirmar que no queda
   una sesión local restaurable.

No se debe esperar que el access token que ya está en memoria falle antes de su
expiración. Si el producto exige revocación inmediata en el futuro, se evaluará
introspección selectiva o una lista distribuida de sesiones revocadas.

## 9. Pruebas y evidencia automatizada

El script reproducible se ejecutó sobre el puerto aislado `18000` y comprobó:

- `pip check` sin dependencias rotas;
- Ruff y formato sin hallazgos;
- 32 pruebas backend superadas;
- exceso por origen e identidad devuelve `429` y `Retry-After`;
- liveness permanece disponible durante el límite;
- token vencido se rechaza;
- dos UUID de usuario distintos provocan denegación de propiedad auditable;
- los eventos de credencial inválida no contienen el token de prueba;
- API, worker y PostgreSQL saludables y ejecutados sin root;
- stack, redes y volumen temporales retirados después de la prueba.

Permanece una advertencia de deprecación de Starlette/TestClient causada por la
transición de `httpx`; no afecta el resultado y se resolverá cuando la cadena de
dependencias soporte el reemplazo sin forzar una migración prematura.

## 10. Riesgos y evolución

- Reiniciar la API reinicia los contadores; aceptable para una instancia local.
- Varias réplicas dividirían los límites; antes de escalar se migrará el estado
  a un limitador distribuido.
- Un acceso directo local puede proporcionar un `CF-Connecting-IP` distinto;
  el puerto solo escucha en loopback y esa capacidad no cruza el perímetro
  público.
- El rate limiting de la API no sustituye la protección de fuerza bruta de
  Keycloak, que ya está habilitada en el realm, ni futuras reglas del perímetro.
- Los umbrales iniciales requieren métricas antes de optimizarse.

## 11. Rollback

Ante falsos positivos se pueden elevar temporalmente los umbrales. La variable
`MUSICFLOW_RATE_LIMIT_ENABLED=false` solo se usará para diagnóstico local y se
revertirá después de identificar la causa. El rollback de código debe realizarse
con `git revert`; no se reescribirá historia compartida.

## 12. Puerta de salida

La integración a `main` requiere:

- [x] contrato `429` y `Retry-After` probado;
- [x] límites independientes por origen e identidad;
- [x] health checks fuera del límite;
- [x] auditoría estructurada sin credenciales;
- [x] token inválido y vencido rechazados;
- [x] política negativa entre dos usuarios;
- [x] modelo de amenazas y configuración actualizados;
- [x] ningún secreto de servidor distribuido en Tauri;
- [x] revocación y logout validados manualmente con una cuenta beta.

### Evidencia manual de revocación

La primera comprobación deshabilitó la cuenta sin cerrar sus sesiones. Keycloak
rechazó login y refresh mientras el usuario estuvo deshabilitado, pero al
reactivarlo la sesión todavía existente pudo volver a renovarse. Esto confirmó
la diferencia entre suspender temporalmente una cuenta y revocar su sesión; no
fue un efecto del access token de diez minutos después de cerrar el proceso.

La prueba definitiva mantuvo al cliente sin cooperar y ejecutó `Logout all
sessions` desde Keycloak antes de deshabilitar la cuenta. MusicFlow exigió una
autenticación nueva y continuó exigiéndola después de reactivar el usuario. La
sesión anterior no se restauró. El flujo de revocación y el riesgo residual de
JWT quedan aprobados.

El trabajo vive en `feat/phase-2-security-exit-controls`. La rama se conservará
localmente y en `origin` después del merge, de acuerdo con el flujo de la
Fase 2.

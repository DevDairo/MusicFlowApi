# Fase 1 — incremento 3: cliente de salud de la API

**Estado:** En implementación

**Versión:** 0.1

**Fecha:** 2026-08-13

## 1. Objetivo

Demostrar que el cliente Tauri instalado puede consultar `GET /health/live` mediante una frontera HTTP de mínimo privilegio, con configuración explícita para desarrollo local y para el dominio publicado mediante Cloudflare Tunnel.

Esta puerta valida conectividad y manejo de estados. No incorpora autenticación, trabajos, descarga de archivos ni procesamiento multimedia.

## 2. Alcance de la puerta B

Incluido:

- URL base pública y no secreta definida durante el build;
- origen local `http://127.0.0.1:8000` para desarrollo;
- origen HTTPS de producción `https://api.kontora-pos.store`;
- cliente limitado a `GET /health/live`;
- timeout y estados explícitos de carga, éxito y error;
- validación de código HTTP y del contrato `{ "status": "alive" }`;
- pruebas unitarias del adaptador y de la interfaz;
- scope HTTP de Tauri sin comodines de dominio;
- regresión completa del cliente y del backend.

Excluido:

- activación o publicación del Cloudflare Tunnel;
- credenciales o tokens de Cloudflare dentro del cliente;
- OAuth/OIDC, sesiones y almacenamiento de tokens;
- `GET /health/ready`, porque revela el estado de dependencias internas y no es necesario para este recorrido;
- endpoints de trabajos, proveedores multimedia y archivos;
- reintentos automáticos, polling permanente o circuit breaker.

## 3. Decisión técnica

Se usará el plugin HTTP oficial de Tauri con un scope limitado a las URLs completas de salud. La UI no usará el `fetch` global del WebView y la CSP no habilitará conexiones remotas directas.

| Alternativa | Ventaja | Costo o riesgo | Decisión |
|---|---|---|---|
| `fetch` del WebView | Sin dependencia adicional. | Requiere CORS y ampliar `connect-src`; la política varía por origen del WebView. | Descartada. |
| Plugin HTTP oficial | Cliente nativo y allowlist de URL integrada con capabilities. | Añade dependencias Rust y TypeScript que deben mantenerse alineadas. | Seleccionada. |
| Comando Rust con `reqwest` | Control absoluto del endpoint. | Duplica infraestructura de permisos, serialización y errores para un caso ya resuelto por el plugin. | Aplazada. |

La URL de la API no es un secreto. Sin embargo, no se aceptará como entrada arbitraria del usuario: cada build elegirá uno de los orígenes previamente aprobados y el scope nativo será la segunda barrera.

## 4. Configuración prevista

| Ambiente | URL base | Alcance nativo |
|---|---|---|
| Desarrollo local | `http://127.0.0.1:8000` | `http://127.0.0.1:8000/health/live` |
| Producción | `https://api.kontora-pos.store` | `https://api.kontora-pos.store/health/live` |

El hostname fue confirmado por el propietario el 2026-08-13. No se aceptarán scopes como `https://**`, `https://*` ni rangos de red privada.

## 5. Contrato y estados

Respuesta válida:

```json
{
  "status": "alive"
}
```

Estados de interfaz:

- `idle`: todavía no se ha consultado;
- `loading`: solicitud en curso y botón deshabilitado;
- `online`: HTTP 200 y contrato válido;
- `error`: timeout, error de red, código no exitoso o cuerpo inesperado.

Los errores visibles serán accionables, pero no expondrán trazas, rutas internas ni detalles de red sensibles.

## 6. Estrategia de pruebas

- configuración: esquema, origen, ruta, query y fragmento;
- adaptador: éxito, HTTP no exitoso, JSON inválido, contrato inválido, fallo de transporte y timeout;
- UI: estado inicial, solicitud única, bloqueo durante carga, éxito y recuperación después de error;
- seguridad: plugin registrado, único scope local/remoto exacto, ausencia de comodines y CSP sin acceso HTTP directo;
- backend: contrato de `/health/live` y suite existente;
- aceptación manual: API local en Docker, cliente instalado, consulta exitosa y error controlado al detener la API.

## 7. Criterios de aceptación

- [x] El subdominio de la API está confirmado y documentado.
- [ ] Las dependencias directas y lockfiles están fijados.
- [ ] La configuración rechaza URLs no aprobadas.
- [ ] La capability permite únicamente los endpoints de salud aprobados.
- [ ] La CSP continúa bloqueando conexiones remotas directas del WebView.
- [ ] Las pruebas de configuración, adaptador, UI y seguridad pasan.
- [ ] Formato, lint, TypeScript, Vite y `cargo fmt --check` pasan.
- [ ] La regresión completa del backend pasa.
- [ ] Se produce exactamente un instalador NSIS.
- [ ] La prueba manual valida éxito con API activa y error controlado con API detenida.

## 8. Riesgos y recuperación

- Un scope amplio convertiría una vulnerabilidad del frontend en capacidad de red nativa. Se mitiga con URLs completas y pruebas negativas.
- Una URL incorporada en el binario obliga a generar builds distintos por ambiente. Es un costo aceptado para este incremento y evita configuración arbitraria.
- El endpoint podría responder HTTP 200 con un cuerpo incompatible. El cliente valida ambos niveles.

El cambio no modifica la base de datos. Para recuperar el estado anterior se desinstala el nuevo cliente y se descarta la rama antes del merge.

## 9. Condición de infraestructura

El túnel remoto `musicflow-local-api` fue creado en Cloudflare y su conector aún no está activo. El token se almacenará en un archivo local excluido de Git y se montará como secreto de Docker; nunca se incorporará al código, `.env.example`, documentación ni historial de comandos.

El conector se ejecuta mediante el perfil opcional `tunnel` de Compose. Comparte únicamente la red `edge` con la API y recibe el token desde `/run/secrets/cloudflare_tunnel_token` mediante `--token-file`; no publica puertos ni instala `cloudflared` en Windows. El hostname remoto deberá dirigir al origen interno `http://api:8000`, porque `localhost` dentro del contenedor corresponde al propio conector.

El 2026-08-13 se validó la infraestructura: el conector registró cuatro conexiones, `/health/live` respondió HTTP 200 local y públicamente, y `/` junto con `/health/ready` fueron rechazados con HTTP 404. La regresión del backend aprobó dependencias, lint, formato, migraciones, 10 pruebas y health checks. La implementación del cliente Tauri sigue pendiente.

## 10. Referencias

- [Tauri: HTTP Client](https://v2.tauri.app/plugin/http-client/)
- [Tauri: Permissions](https://v2.tauri.app/security/permissions/)
- [Tauri: Command Scopes](https://v2.tauri.app/security/scope/)

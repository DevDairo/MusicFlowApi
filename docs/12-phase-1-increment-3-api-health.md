# Fase 1 — incremento 3: cliente de salud de la API

**Estado:** Aprobado; merge y etiqueta pendientes

**Versión:** 0.3

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

- administración de Cloudflare desde el cliente instalado;
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

El timeout de conexión del plugin se expresa en milisegundos. Tanto ese límite como el timeout total se fijan en 5.000 ms; una prueba protege esta unidad para evitar que una conexión HTTPS normal sea abortada prematuramente.

## 6. Estrategia de pruebas

- configuración: esquema, origen, ruta, query y fragmento;
- adaptador: éxito, HTTP no exitoso, JSON inválido, contrato inválido, fallo de transporte y timeout;
- UI: estado inicial, solicitud única, bloqueo durante carga, éxito y recuperación después de error;
- seguridad: plugin registrado, único scope local/remoto exacto, ausencia de comodines y CSP sin acceso HTTP directo;
- backend: contrato de `/health/live` y suite existente;
- aceptación manual: API local en Docker, cliente instalado, consulta exitosa y error controlado al detener la API.

## 7. Criterios de aceptación

- [x] El subdominio de la API está confirmado y documentado.
- [x] Las dependencias directas y lockfiles están fijados.
- [x] La configuración rechaza URLs no aprobadas.
- [x] La capability permite únicamente los endpoints de salud aprobados.
- [x] La CSP continúa bloqueando conexiones remotas directas del WebView.
- [x] Las pruebas de configuración, adaptador, UI y seguridad pasan.
- [x] Formato, lint, TypeScript, Vite y `cargo fmt --check` pasan.
- [x] La regresión completa del backend pasa.
- [x] Se produce exactamente un instalador NSIS.
- [x] La prueba manual valida éxito con API activa, error controlado con API detenida y recuperación posterior.

## 8. Riesgos y recuperación

- Un scope amplio convertiría una vulnerabilidad del frontend en capacidad de red nativa. Se mitiga con URLs completas y pruebas negativas.
- Una URL incorporada en el binario obliga a generar builds distintos por ambiente. Es un costo aceptado para este incremento y evita configuración arbitraria.
- El endpoint podría responder HTTP 200 con un cuerpo incompatible. El cliente valida ambos niveles.

El cambio no modifica la base de datos. Para recuperar el estado anterior se desinstala el nuevo cliente y se descarta la rama antes del merge.

## 9. Condición de infraestructura

El túnel remoto `musicflow-local-api` está activo. Su token permanece en un archivo local excluido de Git y se monta como secreto de Docker; nunca se incorpora al código, `.env.example`, documentación ni argumentos visibles del contenedor.

El conector se ejecuta mediante el perfil opcional `tunnel` de Compose. Comparte únicamente la red `edge` con la API y recibe el token desde `/run/secrets/cloudflare_tunnel_token` mediante `--token-file`; no publica puertos ni instala `cloudflared` en Windows. El hostname remoto deberá dirigir al origen interno `http://api:8000`, porque `localhost` dentro del contenedor corresponde al propio conector.

El 2026-08-13 se validó la infraestructura: el conector registró cuatro conexiones, `/health/live` respondió HTTP 200 local y públicamente, y `/` junto con `/health/ready` fueron rechazados con HTTP 404. La regresión del backend aprobó dependencias, lint, formato, migraciones, 10 pruebas y health checks.

## 10. Evidencia automatizada

| Comprobación | Resultado del 2026-08-13 |
|---|---|
| Lockfiles | `pnpm install --frozen-lockfile` y `cargo metadata --locked` aprobados dentro de Docker. |
| Calidad del cliente | Prettier, Oxlint, 18 pruebas Vitest, TypeScript y Vite aprobados. |
| Compilación nativa | `cargo fmt --check`, plugin HTTP 2.5.9, enlace de Windows y empaquetado NSIS aprobados. |
| Infraestructura activa | API y PostgreSQL healthy; health local y público con HTTP 200. |
| Instalador corregido | `artifacts/desktop-20260813-110233/MusicFlow_0.1.0_x64-setup.exe`; 3 614 875 bytes; SHA-256 `A05DBAB6FD53A80E8A0F227CF999C55AE21A3C24C20F1DB29664A6833B1DDEA4`. |
| Recorrido positivo instalado | Aprobado manualmente el 2026-08-13: la UI mostró **API disponible** y confirmó el contrato público esperado. |
| Degradación y recuperación | Aprobada manualmente el 2026-08-13: al detener solo la API, el cliente mostró el estado no disponible sin cerrarse; al levantarla nuevamente, una nueva consulta volvió a **API disponible** sin reiniciar el cliente. |
| Ciclo de instalación | Aprobado manualmente el 2026-08-13: el cliente se cerró, reabrió, volvió a consultar la API y se desinstaló correctamente. |

El instalador de desarrollo no está firmado. La compilación cruzada también conserva las advertencias conocidas de autodetección de `clang-cl` y charset de NSIS; ninguna impidió compilar, enlazar o empaquetar la aplicación.

Durante la primera prueba instalada, el adaptador falló porque `connectTimeout` se había configurado en `5` interpretándolo erróneamente como segundos. El plugin expresa ese argumento en milisegundos y el endpoint público medido necesitó 565 ms. El cambio mínimo a `5_000`, respaldado por una prueba de regresión, resolvió el defecto sin ampliar la capability ni modificar el túnel. El artefacto de la carpeta `desktop-20260813-104915` queda descartado.

## 11. Protocolo de aceptación manual

1. Instalar el artefacto exacto registrado en la evidencia y abrir MusicFlow.
2. Pulsar **Comprobar conexión** con el túnel activo; debe mostrarse **API disponible**.
3. Detener únicamente el origen con `docker compose --profile tunnel stop api`; el conector y PostgreSQL deben permanecer activos.
4. Pulsar nuevamente el botón; debe mostrarse un error controlado sin detalles internos ni cierre de la aplicación.
5. Recuperar el origen con `docker compose --profile tunnel start api`, esperar que la ruta pública responda y repetir la consulta; debe volver a **API disponible**.
6. Reabrir y desinstalar el cliente para completar la misma puerta de instalación del incremento anterior.

Los seis pasos fueron aprobados por el propietario el 2026-08-13. No se iniciará la siguiente fase hasta integrar esta rama en `main`, etiquetar el incremento y verificar el estado limpio del repositorio.

## 12. Referencias

- [Tauri: HTTP Client](https://v2.tauri.app/plugin/http-client/)
- [Tauri: Permissions](https://v2.tauri.app/security/permissions/)
- [Tauri: Command Scopes](https://v2.tauri.app/security/scope/)

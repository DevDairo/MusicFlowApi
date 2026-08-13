# Runbook de Cloudflare Tunnel

**Estado:** Validado para desarrollo local

**Versión:** 0.1

**Fecha:** 2026-08-13

## 1. Objetivo

Operar de forma reproducible el túnel `musicflow-local-api`, que publica exclusivamente `GET /health/live` bajo `https://api.kontora-pos.store` sin abrir puertos del router ni distribuir credenciales de Cloudflare en el cliente.

## 2. Frontera publicada

```text
https://api.kontora-pos.store/health/live
                  |
                  v
Cloudflare Tunnel: hostname api.kontora-pos.store
                   path ^/health/live$
                   service http://api:8000
                  |
                  v
API de Compose en la red edge
```

`/`, `/health/ready` y cualquier otro path reciben `404` en el conector y no llegan a la API. Cloudflare protege el tráfico cliente → API; no cambia la IP de salida del worker ni evita errores 403 del proveedor multimedia.

## 3. Secretos locales

El token del túnel remoto se conserva en:

```text
.secrets/cloudflare-tunnel-token
```

Reglas:

- el archivo contiene únicamente el token `eyJ...`;
- `.secrets/` está excluido de Git;
- Compose lo monta en modo lectura en `/run/secrets/cloudflare_tunnel_token`;
- `cloudflared` lo consume mediante `--token-file`;
- el token no se coloca en `.env`, argumentos, logs, capturas ni documentación;
- si se sospecha exposición, se rota desde Cloudflare antes de reiniciar el conector.

`.env` contiene únicamente la configuración local del backend y también está excluido de Git. `.env.example` nunca contiene valores secretos reales.

## 4. Inicio

Requisitos:

- Docker Desktop activo;
- `.env` local válido;
- archivo del token presente;
- ruta publicada configurada en Cloudflare.

```powershell
Set-Location C:\Users\Genoma\Documents\MusicFlow
docker compose --profile tunnel up --detach --build --wait api cloudflared
```

El perfil `tunnel` es opcional. Ejecutar Compose sin ese perfil no inicia `cloudflared` ni requiere el secreto.

## 5. Verificación

Estado de contenedores:

```powershell
docker compose --profile tunnel ps
```

Prueba local:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/health/live
```

Prueba pública:

```powershell
Invoke-RestMethod https://api.kontora-pos.store/health/live
```

Ambas deben devolver:

```json
{"status":"alive","checks":null}
```

Pruebas negativas:

```powershell
curl.exe -sS -o NUL -w "%{http_code}`n" https://api.kontora-pos.store/
curl.exe -sS -o NUL -w "%{http_code}`n" https://api.kontora-pos.store/health/ready
```

Ambas deben devolver `404`.

## 6. Diagnóstico

```powershell
docker compose --profile tunnel logs --tail 100 cloudflared
docker compose --profile tunnel logs --tail 100 api
```

Interpretación inicial:

- `lookup api ... no such host`: la API no está ejecutándose o no comparte la red `edge`;
- `Unable to reach the origin service`: comprobar salud de API y el origen `http://api:8000`;
- fallos QUIC transitorios: comprobar recuperación automática y una consulta pública antes de cambiar el transporte;
- error público `404`: confirmar path exacto `/health/live`;
- error `502`: el conector está activo, pero no puede alcanzar el origen;
- error `1033`: Cloudflare no encuentra un conector saludable para el túnel. Durante un arranque puede ser transitorio; esperar unos segundos, confirmar mensajes `Registered tunnel connection` y reintentar de forma limitada antes de cambiar configuración.

No activar `debug` de forma permanente: puede registrar URLs y cabeceras de solicitudes.

## 7. Detención y recuperación

Detener la plataforma y conservar los datos:

```powershell
docker compose --profile tunnel down
```

Eliminar también el volumen de desarrollo, solo cuando se quiera reiniciar PostgreSQL deliberadamente:

```powershell
docker compose --profile tunnel down --volumes
```

El registro DNS no desaparece al detener el conector. Mientras esté detenido, el hostname público no podrá alcanzar la API.

## 8. Rotación del token

1. Rotar el token del túnel en el panel de Cloudflare.
2. Reemplazar el contenido de `.secrets/cloudflare-tunnel-token` por el nuevo token.
3. Recrear solo el conector:

```powershell
docker compose --profile tunnel up --detach --force-recreate cloudflared
```

4. Confirmar conexiones registradas y repetir las pruebas de la sección 5.

## 9. Evidencia inicial

El 2026-08-13 se comprobó:

- imagen oficial `cloudflare/cloudflared:2026.7.3` fijada por digest;
- cuatro conexiones QUIC registradas y recuperación automática después de una interrupción local;
- recuperación de un `1033` transitorio de arranque una vez registradas las conexiones del edge;
- raíz de contenedor de solo lectura, sin privilegios y con `cap_drop: ALL`;
- token ausente del entorno del contenedor y secreto montado como solo lectura;
- conector únicamente en la red `edge` y sin puertos publicados;
- API enlazada a `127.0.0.1:8000` y PostgreSQL sin puertos publicados;
- `/health/live` local y público con HTTP 200 y contrato correcto;
- `/` y `/health/ready` públicos rechazados con HTTP 404;
- perfil normal de Compose válido sin activar el túnel.

## 10. Referencias

- [Cloudflare: Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/)
- [Cloudflare: Published applications](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/routing-to-tunnel/)
- [Cloudflare: Run parameters](https://developers.cloudflare.com/tunnel/advanced/run-parameters/)
- [Cloudflare: Tunnel tokens](https://developers.cloudflare.com/tunnel/advanced/tunnel-tokens/)

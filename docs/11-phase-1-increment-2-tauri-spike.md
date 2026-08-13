# Fase 1 — incremento 2: spike del cliente Tauri

**Estado:** En validación

**Versión:** 0.1

**Fecha:** 2026-08-13

## 1. Objetivo

Demostrar que MusicFlow puede producir e instalar un cliente nativo de Windows sin instalar Node.js, pnpm, Rust ni dependencias del proyecto en el host. Este incremento valida el límite de despliegue, no el flujo funcional de audio.

## 2. Alcance de la puerta A

Incluido:

- interfaz mínima con React y TypeScript;
- envoltura nativa Tauri 2 con una ventana principal;
- pruebas automatizadas del contenido y la configuración de seguridad;
- dependencias directas fijadas y lockfiles reproducibles;
- formato, lint, pruebas y build web en Docker;
- compilación cruzada de un instalador NSIS `x86_64` mediante `cargo-xwin`;
- exportación del instalador al host para instalación manual.

Excluido hasta superar esta puerta:

- llamadas al health check de la API;
- plugins HTTP, filesystem, shell, diálogo o almacenamiento;
- autenticación, tokens y secretos;
- selección de carpetas o biblioteca local;
- firma de código, actualizaciones y publicación pública;
- MSI, macOS y Linux.

## 3. Límites de arquitectura

El directorio `desktop/` contiene código fuente y herramientas de compilación del cliente. No se añade un servicio a `compose.yaml` porque la aplicación no se ejecuta en la plataforma de servidor.

```text
Docker Desktop -> compila y exporta MusicFlow_*_x64-setup.exe
                                      |
                                      v
Windows        -> instala y ejecuta MusicFlow de forma nativa
```

El usuario final no necesita Docker, Node.js, pnpm, Rust ni acceso directo a PostgreSQL. La API, el worker y PostgreSQL conservan sus contenedores y ciclos de despliegue independientes.

## 4. Seguridad mínima

- `withGlobalTauri` permanece desactivado.
- La única capability está asociada a la ventana `main` y no concede permisos.
- No se registran comandos Rust ni plugins Tauri.
- La CSP permite únicamente recursos empaquetados y canales internos de Tauri.
- No se cargan scripts, fuentes, imágenes o páginas desde CDNs o dominios remotos.
- El instalador usa el modo `currentUser`, sin elevación administrativa.
- El bootstrapper de WebView2 se descarga solo si Windows no dispone del runtime.

La prueba `security.test.ts` protege estas decisiones contra ampliaciones accidentales. Cada permiso futuro deberá responder a una historia concreta, tener alcance mínimo y pruebas negativas.

## 5. Toolchain reproducible

| Componente | Versión fijada | Función |
|---|---:|---|
| Node.js | 24.17.0 LTS | Build de React/Vite. |
| pnpm | 11.15.1 | Resolución determinista de dependencias. |
| Rust | 1.96.1 | Compilación de Tauri. |
| Tauri CLI | 2.11.4 | Orquestación y empaquetado. |
| Tauri crate | 2.11.5 | Runtime nativo. |
| `cargo-xwin` | 0.22.0 | SDK y target MSVC desde Linux. |

Las imágenes base son oficiales: `node:24.17.0-bookworm-slim` y `rust:1.96.1-bookworm`. Las dependencias viven dentro de capas Docker; no se monta `node_modules` ni el target de Cargo en Windows.

## 6. Verificación

Antes de ejecutar el comando completo debe revisarse la licencia de los componentes del SDK de Microsoft que descarga `cargo-xwin`. La aceptación se expresa con un parámetro visible; no está implícita en el script.

```powershell
Set-Location C:\Users\Genoma\Documents\MusicFlow
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-desktop.ps1 -AcceptMicrosoftSdkLicense
```

Para ejecutar solo la puerta de calidad web y omitir temporalmente el instalador:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-desktop.ps1 -SkipInstaller
```

La primera ejecución puede tardar y descargar varios gigabytes. Los artefactos se exportan a `artifacts/desktop-<timestamp>/`, directorio excluido de Git.

## 7. Criterios de aceptación

- [ ] Los lockfiles existen y están incluidos en el diff.
- [ ] Prettier no encuentra diferencias.
- [ ] Oxlint termina sin advertencias.
- [ ] TypeScript compila en modo estricto.
- [ ] Las pruebas automatizadas pasan.
- [ ] Vite produce el frontend de release.
- [ ] Rust supera `cargo fmt --check`.
- [ ] `cargo-xwin` produce exactamente un `*-setup.exe` NSIS.
- [ ] El instalador se ejecuta para el usuario actual sin pedir permisos administrativos.
- [ ] La aplicación abre, presenta la pantalla de la puerta A y cierra correctamente.
- [ ] La desinstalación no afecta datos ajenos ni servicios del backend.

## 8. Evidencia

| Verificación | Resultado | Evidencia |
|---|---|---|
| Calidad web en Docker | Aprobada el 2026-08-13 | Lockfiles congelados; Prettier, Oxlint, Vitest, TypeScript y Vite finalizaron correctamente mediante `verify-desktop.ps1 -SkipInstaller`. |
| Regresión del backend | Aprobada el 2026-08-13 | Lint, formato, migración, 10 pruebas automatizadas y health checks de API, worker y PostgreSQL finalizaron correctamente mediante `verify.ps1`. |
| Instalador NSIS | Pendiente | Ruta y hash del ejecutable. |
| Instalación y apertura en Windows | Pendiente | Confirmación manual del propietario. |
| Desinstalación | Pendiente | Confirmación manual del propietario. |

Este documento no se marcará como aprobado ni se realizará merge hasta completar la evidencia.

## 9. Recuperación

El incremento no modifica bases de datos ni servicios en ejecución. Para recuperar el estado anterior antes del merge se descarta la rama. Los artefactos locales bajo `artifacts/` pueden eliminarse sin afectar código fuente. Si el instalador fue ejecutado, se desinstala desde la configuración de aplicaciones de Windows.

## 10. Próximo incremento condicionado

Después de aprobar la puerta A se diseñará una puerta B pequeña: configuración segura de la URL de la API, cliente HTTP limitado y consulta de `/health/live`. No se añadirán autenticación ni procesamiento multimedia en esa misma entrega.

## 11. Referencias técnicas

- [Tauri: Windows Installer](https://v2.tauri.app/distribute/windows-installer/)
- [Tauri: Capabilities](https://v2.tauri.app/security/capabilities/)
- [Tauri: Content Security Policy](https://v2.tauri.app/security/csp/)
- [Docker Official Image: Node.js](https://hub.docker.com/_/node)
- [Docker Official Image: Rust](https://hub.docker.com/_/rust)

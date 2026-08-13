# ADR-0008: Compilar el spike Tauri con una toolchain Docker desechable

- Estado: Accepted
- Fecha: 2026-08-13
- Responsables: propietario del proyecto

## Contexto

El cliente Tauri debe instalarse y ejecutarse directamente en Windows, pero el entorno de desarrollo no debe recibir instalaciones globales de Node.js, pnpm, Rust ni las dependencias del proyecto. Docker Desktop ya está disponible. GitHub Actions y una máquina virtual Windows fueron descartados para este incremento.

Tauri permite compilar un instalador NSIS de Windows desde Linux con `cargo-xwin`, aunque su documentación advierte que esta ruta tiene más limitaciones y menos cobertura que una compilación nativa. Los paquetes MSI solo pueden generarse en Windows.

## Decisión

Para la prueba técnica de la Fase 1 se utilizará un Dockerfile propio, basado únicamente en imágenes oficiales de Node.js y Rust, que:

- fija versiones de Node.js, pnpm, Rust y `cargo-xwin`;
- genera y consume `pnpm-lock.yaml` y `Cargo.lock`;
- ejecuta formato, lint, pruebas y build de la interfaz;
- compila para `x86_64-pc-windows-msvc`;
- exporta un instalador NSIS sin convertir el cliente en un contenedor de runtime.

El usuario debe aceptar explícitamente la licencia del SDK de Microsoft antes de que `cargo-xwin` descargue sus componentes. El instalador del spike no estará firmado y se instalará para el usuario actual.

## Alternativas consideradas

### Toolchain nativa en Windows

Es la ruta con mejor soporte de Tauri y permite MSI, pero instala Node.js, Rust y Microsoft C++ Build Tools en el host, contrario a la restricción actual.

### Máquina virtual Windows

Aísla las dependencias y conserva una compilación nativa, a cambio de mayor consumo, administración y tiempo de preparación.

### Servicio de integración continua Windows

Es apropiado para releases repetibles y firma futura, pero GitHub Actions fue aplazado deliberadamente mientras se aprende el flujo manual.

## Consecuencias

### Positivas

- El host conserva únicamente Docker Desktop como dependencia de desarrollo.
- La aplicación resultante se instala de forma nativa y no necesita Docker, Node.js ni Rust.
- Las versiones y verificaciones quedan expresadas como código revisable.

### Negativas y riesgos

- La imagen de compilación es grande y la primera ejecución descarga toolchains y el SDK de Windows.
- La compilación cruzada puede descubrir incompatibilidades específicas de Windows.
- La prueba manual en Windows sigue siendo obligatoria.
- La firma y el instalador MSI quedan pendientes para una fase de distribución.

## Validación

La decisión se considerará técnicamente validada cuando el script produzca exactamente un instalador NSIS, este se instale sin privilegios administrativos y la ventana principal abra correctamente en Windows. Si falla por una limitación de compilación cruzada, se reevaluará una VM Windows antes de instalar toolchains en el host.

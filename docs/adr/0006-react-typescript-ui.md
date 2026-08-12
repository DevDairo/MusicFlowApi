# ADR-0006: Usar React y TypeScript en la interfaz Tauri

- **Estado:** Accepted
- **Fecha:** 2026-08-12
- **Responsables:** propietario del proyecto

## Contexto

Tauri permite elegir el stack de UI. El cliente necesita estados asíncronos, formularios, accesibilidad, biblioteca local y contratos HTTP mantenibles. El beta usa JavaScript directo e `innerHTML`, lo que no proporciona tipos ni una frontera segura suficiente.

## Decisión

Usar React con TypeScript para la UI de Tauri 2. Las llamadas nativas estarán encapsuladas en adaptadores y las respuestas de API se validarán en la frontera. No se habilitarán capacidades Tauri globales por comodidad.

## Alternativas consideradas

- JavaScript/DOM directo: menor dependencia, pero escala peor para estado y contratos.
- Vue/Svelte: opciones válidas y ligeras; no ofrecen una ventaja decisiva para este proyecto frente al ecosistema y experiencia transferible de React.
- UI nativa Rust: reduce WebView, pero aumenta mucho el costo del MVP y pierde el ecosistema web elegido.

## Consecuencias

### Positivas

- Tipos y componentes comprobables.
- Ecosistema amplio y conocimiento transferible al mercado laboral.
- Renderizado escapado por defecto frente al `innerHTML` del beta.

### Negativas y riesgos

- Dependencias y estado pueden crecer innecesariamente.
- React no impide XSS si se usa HTML inseguro o URLs no validadas.
- El toolchain de Tauri aún debe resolverse sin instalaciones globales en Windows.

## Validación

- Spike de login, health y selección de carpeta.
- Pruebas de accesibilidad, estado y comandos Tauri.
- CSP y capacidades revisadas antes de cargar contenido o datos externos.

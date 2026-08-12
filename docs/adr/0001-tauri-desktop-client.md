# ADR-0001: Usar Tauri 2 para el cliente de escritorio

- **Estado:** Accepted
- **Fecha:** 2026-08-12
- **Responsables:** propietario del proyecto

## Contexto

La aplicación web beta no puede administrar una biblioteca local con la integración y los permisos que se esperan de una aplicación instalada. El producto debe comenzar en Windows, pero se desea conservar una ruta razonable hacia macOS y Linux.

El cliente es distinto de la plataforma de servidor: no debe ejecutar responsabilidades privadas de API, worker o base de datos.

## Decisión

Construir el cliente de escritorio con Tauri 2. La interfaz podrá utilizar TypeScript y un framework de UI que se decidirá después de revisar las necesidades del cliente. Rust implementará únicamente las capacidades nativas necesarias y validadas.

El cliente:

- consumirá la API exclusivamente por HTTPS;
- realizará autenticación mediante un flujo apto para cliente público;
- administrará selección de rutas, descarga e índice de biblioteca local;
- usará capacidades Tauri de mínimo privilegio;
- no contendrá secretos de servidor ni acceso directo a PostgreSQL/worker.

## Alternativas consideradas

### Aplicación web/PWA

Menor complejidad de distribución, pero permisos de archivos y biblioteca local más limitados e inconsistentes. No satisface adecuadamente el núcleo del producto.

### Electron

Ecosistema maduro y UI web directa. A cambio, distribuye un runtime más pesado y aumenta consumo/tamaño. Sigue siendo una alternativa válida si Tauri presenta un bloqueo comprobado.

### .NET/WinUI o WPF

Integración excelente con Windows y ecosistema empresarial sólido. Reduce la portabilidad y obligaría a resolver por separado macOS/Linux.

### Flutter

Buena portabilidad y UI consistente. Introduce Dart y un stack distinto al de la posible UI web/TypeScript sin una ventaja decisiva para el MVP.

## Consecuencias

### Positivas

- Acceso controlado a capacidades nativas y biblioteca local.
- Instaladores más ligeros que una solución basada en Chromium completo en muchos escenarios.
- Ruta multiplataforma con una base de UI compartida.
- Aprendizaje de límites entre frontend, comandos nativos y API remota.

### Negativas y riesgos

- Rust y el modelo de capacidades de Tauri añaden curva de aprendizaje.
- WebView y empaquetado varían entre sistemas operativos.
- Firma, actualización y pruebas por plataforma siguen siendo necesarias.
- “Multiplataforma” no elimina el trabajo de compatibilidad específico.

## Validación

- Spike mínimo de autenticación, health de API, selección de carpeta y escritura segura.
- Instalación y ejecución en las versiones Windows definidas en el SRS.
- Revisión de capacidades y CSP sin permisos innecesarios.
- Pruebas de Unicode, rutas largas, colisiones y denegación de permisos.

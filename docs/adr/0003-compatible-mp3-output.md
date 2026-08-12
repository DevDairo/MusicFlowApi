# ADR-0003: Priorizar un perfil MP3 compatible

- **Estado:** Accepted
- **Fecha:** 2026-08-12
- **Responsables:** propietario del proyecto

## Contexto

El producto debe producir audio de la máxima calidad práctica disponible, pero también reproducible en sistemas de escritorio y móviles comunes. “Hi-Res” describe propiedades reales de audio, no un resultado que pueda obtenerse simplemente aumentando frecuencia de muestreo o tasa de bits.

## Decisión

El MVP tendrá un perfil de salida MP3 de alta calidad y amplia compatibilidad. La propuesta técnica inicial es VBR V0 con etiquetas ID3v2.3, sujeta a pruebas en la matriz de reproductores.

El pipeline:

- seleccionará la mejor pista de audio disponible;
- evitará transformaciones intermedias innecesarias;
- medirá el resultado mediante FFprobe;
- conservará metadatos descriptivos y técnicos reales;
- no etiquetará la salida como Hi-Res ni afirmará recuperar información ausente.

## Alternativas consideradas

### FLAC

Conserva audio sin pérdidas cuando la fuente también lo permite y admite buenos metadatos. Produce archivos mayores y convertir una fuente con pérdidas a FLAC no mejora su calidad.

### Opus

Excelente eficiencia y calidad perceptual. Su soporte en dispositivos y aplicaciones heredadas es menos universal que MP3.

### Conservar el formato original

Evita transcodificación, pero genera una experiencia inconsistente y formatos no compatibles con todos los destinos.

### Múltiples perfiles desde el inicio

Da flexibilidad, pero multiplica combinaciones de pruebas, UI y soporte antes de validar el flujo central.

## Consecuencias

### Positivas

- Reproducción amplia y modelo sencillo para el usuario.
- Perfil único más fácil de probar y mantener.
- Metadatos compatibles con reproductores comunes.

### Negativas y riesgos

- MP3 es con pérdida y requiere transcodificación si la fuente usa otro códec.
- VBR puede mostrar tasas de bits variables en diferentes aplicaciones, como es correcto.
- Algunos metadatos avanzados no son uniformes entre reproductores.
- Usuarios audiófilos podrían preferir un modo sin pérdidas en el futuro.

## Validación

- Definir fixtures autorizados con diferentes propiedades de fuente.
- Verificar códec, duración, tags, carátula y propiedades técnicas con FFprobe.
- Reproducir y revisar metadatos en la matriz Windows aprobada.
- Comparar tamaño, tiempo y calidad perceptual antes de fijar parámetros definitivos.

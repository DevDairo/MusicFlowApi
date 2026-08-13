# Flujo manual de control de versiones

**Estado:** Aprobado
**Versión:** 1.1
**Fecha:** 2026-08-13

## 1. Objetivo

Mantener `main` estable y conservar evidencia clara de qué se desarrolló, cómo se validó y cuándo fue aprobado, sin depender inicialmente de GitHub Actions.

Este proceso es una puerta de calidad manual, no un reemplazo de las pruebas. La automatización remota podrá incorporarse después como un incremento de aprendizaje explícito.

## 2. Modelo de ramas

- `main`: último estado aprobado, verificable y documentado.
- `feat/...`: nueva capacidad funcional.
- `fix/...`: corrección de un defecto.
- `docs/...`: cambios exclusivamente documentales.
- `test/...`: ampliación o corrección de pruebas.
- `refactor/...`: cambio interno sin modificar comportamiento esperado.
- `chore/...`: mantenimiento de herramientas o configuración.

Las ramas deben representar un incremento o módulo pequeño. No se mantendrán ramas abiertas durante una fase completa porque acumulan divergencia, dificultan la revisión y aumentan el costo del merge.

Ejemplo:

```text
feat/phase-1-increment-2-tauri-shell
```

## 3. Inicio de un incremento

```powershell
git switch main
git pull --ff-only origin main
git switch -c <tipo>/<nombre-corto>
git status -sb
```

`--ff-only` evita crear merges accidentales al actualizar `main`. La rama debe crearse únicamente después de confirmar que el incremento anterior está aprobado.

## 4. Desarrollo y commits

- Un commit debe expresar una intención coherente y revisable.
- Se usarán mensajes Conventional Commits.
- No se incluirán `.env`, tokens, contraseñas, archivos descargados ni artefactos pesados.
- Los cambios funcionales deben incluir pruebas proporcionales al riesgo.
- La documentación y los contratos se actualizarán en la misma rama cuando formen parte del incremento.

Ejemplos:

```text
feat: add desktop health client shell
fix: load integration database credentials from environment
docs: define manual version control workflow
```

## 5. Puerta de calidad manual

Antes del merge se revisará como mínimo:

- criterios de aceptación completados;
- diff sin cambios inesperados ni secretos;
- pruebas relevantes aprobadas;
- lint y formato aprobados;
- documentación y migraciones actualizadas;
- errores encontrados corregidos o clasificados explícitamente;
- procedimiento de recuperación proporcional al cambio.

Cambios en backend, Docker, dependencias o migraciones deben ejecutar:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

Un cambio exclusivamente documental puede usar una validación proporcional: enlaces locales, formato, ortografía técnica y revisión del diff. No necesita reconstruir Docker si no modifica instrucciones ejecutables ni configuración.

## 6. Publicación de la rama

```powershell
git add .
git diff --cached --check
git status --short
git commit -m "<tipo>: <descripcion>"
git push -u origin <nombre-rama>
```

Un Pull Request es recomendable incluso en un proyecto personal porque conserva contexto, discusión y evidencia. No requiere GitHub Actions.

## 7. Merge aprobado

Si el merge se realiza desde consola después de validar la rama:

```powershell
git switch main
git pull --ff-only origin main
git merge --no-ff <nombre-rama> -m "merge: <descripcion-del-incremento>"
git push origin main
```

`--no-ff` conserva un punto visible de integración. No se hará push directo de implementación a `main` ni se utilizará `--force` sobre esa rama.

Después de confirmar el push, salvo durante una fase con una excepción de
retención aprobada:

```powershell
git branch -d <nombre-rama>
git push origin --delete <nombre-rama>
```

### 7.1 Excepción de retención para la Fase 2

Por decisión del propietario, las ramas creadas durante la Fase 2 se
conservarán localmente y en `origin` después de integrarse. El objetivo es
mantener una referencia navegable de los incrementos y facilitar comparaciones
si posteriormente se exploran otros proveedores o diseños de identidad.

Esta excepción se rige por las siguientes reglas:

- no ejecutar `git branch -d` ni `git push origin --delete` sobre ramas de la
  Fase 2 al terminar su merge;
- una rama integrada queda congelada como referencia histórica y no recibe
  commits nuevos;
- cualquier corrección o alternativa nace en una rama nueva desde el `main`
  vigente;
- `main` continúa siendo la única fuente del estado aprobado y las etiquetas
  identifican sus hitos verificables;
- una rama experimental no representa una decisión aceptada mientras su cambio
  no haya superado la puerta de calidad y sido integrado en `main`;
- no se reescribirán ni forzarán las ramas retenidas;
- su eventual eliminación solo podrá decidirse de forma explícita en la
  revisión de salida de la Fase 2 o en una revisión posterior.

La retención no reemplaza las ADR ni las etiquetas: una rama conserva código e
historia; una ADR explica por qué se tomó una decisión y una etiqueta señala el
commit exacto aprobado.

## 8. Etiquetas de hitos

Una etiqueta anotada identifica el commit exacto que superó la puerta del incremento, aunque su rama ya se haya eliminado:

```powershell
git tag -a phase-<fase>-increment-<numero> -m "<descripcion>"
git push origin phase-<fase>-increment-<numero>
```

El versionado semántico se reservará para versiones consumibles de la aplicación.

## 9. Correcciones y recuperación

Si un defecto llega a `main`, se crea una rama `fix/...` desde el último `main`. Si es necesario deshacer un commit publicado, se usará `git revert` para crear un cambio inverso auditable. No se reescribirá la historia compartida con `reset --hard` o push forzado.

## 10. Trade-offs aceptados

La validación manual reduce complejidad inicial y permite aprender el flujo de Git por etapas, pero depende de disciplina humana y no impide técnicamente un merge sin pruebas. Para mitigar este riesgo:

- la evidencia se registra en el documento de cada incremento;
- `main` solo recibe cambios después de la verificación;
- cada hito aprobado se etiqueta;
- el flujo se revisará si aumenta el número de colaboradores o la frecuencia de cambios.

La adopción futura de GitHub Actions se evaluará cuando pueda introducirse, comprenderse y probarse como una capacidad independiente.

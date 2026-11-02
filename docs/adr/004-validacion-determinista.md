# ADR 004 · El estándar se valida con código, no con instrucciones al modelo

- **Estado:** aceptada
- **Fecha:** 2026-10-29

## Contexto

El agente usa un modelo pequeño y gratuito (ADR 001). Durante las pruebas observé que un modelo así olvida instrucciones, elige mal un ejemplo o da por hecho un resultado sin verificarlo. Además, quien evalúe el reto puede usar otro modelo. Si el estándar dependiera de que el agente se acuerde de una regla escrita en el prompt, cambiaría con cada modelo y con cada sesión.

## Decisión

Cada regla del estándar se implementa en un componente que falla automáticamente si la regla no se cumple. El contexto y las skills explican cómo aplicarla, pero no son el mecanismo que la garantiza.

| Regla | Dónde se hace cumplir |
|---|---|
| CDC, limpieza de códigos, centinelas, zona horaria | Macros (`cdc_latest`, `clean_code`, `source_timestamp`, `utc_to_local`): una sola implementación |
| Casteo estricto | `cast` en staging: un valor inválido rompe el build en vez de volverse nulo |
| Códigos válidos, llaves, grano | Tests de dbt (`accepted_values`, `relationships`, `unique_combination`, `not_before`, `in_range`) |
| Reglas del requerimiento | Tests de negocio que recalculan por un camino independiente; cada uno probado con una mutación que lo hace fallar |
| Tipos y columnas de los marts | `contract: enforced` |
| Idempotencia, secretos | CI en cada PR |
| Frontera | Permisos de opencode, guardia de dbt, environments de GitHub (ADR 003) |

**Herramientas deterministas.** El modelo no lee logs de dbt ni tablas completas. `make diagnose`, `make profile` y `scripts/query.py` devuelven JSON compacto con lo necesario: la regla que falló, la capa, el linaje, una muestra de filas y los cambios sin commit. De esta forma el agente trabaja sobre hechos, consume menos tokens y dos modelos distintos reciben la misma evidencia.

**Contexto mínimo.** `AGENTS.md` es corto y siempre se carga. Los procedimientos viven en skills que solo se cargan cuando la tarea las pide.

## Alternativas consideradas

- **Un prompt largo con todas las reglas.** Descartada: más tokens en cada petición, menos cuota disponible, y nada garantiza que el modelo las aplique.
- **Que el agente lea los logs de dbt directamente.** Descartada: miles de líneas por corrida; el modelo pequeño se pierde y agota la cuota.
- **Revisión del PR por otro LLM.** Pospuesta: suma costo y otra fuente de error. Los tests ya dan una respuesta binaria; la revisión humana se concentra en el criterio.

## Consecuencias

- Si el agente se equivoca, el error queda visible: un test falla, el contrato rechaza el mart o el CI no se aprueba. Lo que el estándar no puede detectar, como un supuesto discutible o un ejemplo mal elegido, corresponde a la revisión humana del pull request.
- Las pruebas con el agente real me mostraron qué reglas existían solo como instrucción. En cada caso se movió a un lugar que la hace cumplir o a la skill que se lee en el momento justo:
  - **Cuerpo del PR entre comillas:** la terminal ejecutó lo que iba entre backticks. Se resolvió en dos partes: el cuerpo ahora va por archivo y `opencode.json` niega cualquier comando con sustitución, aunque empiece con uno permitido.
  - **Regla de no relajar el casteo:** estaba en la skill de PR, que se lee después de escribir el fix. Se movió a la skill de diagnóstico.
- Cada regla nueva del negocio debe llegar con su test. La skill `fuente-nueva` lo exige y pide demostrar que el test puede fallar.

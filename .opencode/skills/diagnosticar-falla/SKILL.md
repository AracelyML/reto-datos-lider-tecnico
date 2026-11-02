---
name: diagnosticar-falla
description: Diagnostica por qué falla un test, un modelo o por qué un número del mart no cuadra, y explica el mecanismo (no el stack trace). Usar cuando algo falla, un KPI se ve raro o después de un chaos.
---

# Diagnosticar una falla

El objetivo es el **mecanismo**: qué cambió, por qué eso produce el síntoma y qué parte del negocio afecta. Repetir el mensaje de error no es un diagnóstico.

## Pasos

1. `make diagnose`. Lee `resumen`, `fallas` y `cambios_sin_commit`.
   - Sin fallas pero el usuario ve algo raro → perfila el mart (`make profile TABLE=mart_logistica.<tabla> PK=<grano>`) y compáralo contra staging con `scripts/query.py`.
2. **Ubica el origen.** Si hay `cambios_sin_commit`, empieza por `git diff <archivo>`: la causa suele ser código. Si no, es dato: perfila la tabla de landing o staging del `linaje` más cercana al síntoma.
   - Una entrega en `data/chaos/` o `data/simulada/` (base de pruebas) es **dato del origen**, igual que una de `data/replica/`: el fix va en código (staging o macro) con PR, y el defecto se escala al dueño del origen.
   - **Si la causa es un cambio sin commit, `main` está sano.** No abras PR: explica el mecanismo, recomienda descartar el cambio (`git restore <archivo>`, lo ejecuta la persona) o, si era intencional, corregirlo antes de commitear. Abre PR solo cuando el defecto está en código ya publicado en `main` o en los datos.
3. **Formula una hipótesis** con el catálogo de abajo y **confírmala con una consulta** (`python scripts/query.py "..."`). No propongas fix sin evidencia.
4. **Corrige en una rama** `fix/<desc>`, en la capa donde nace el problema (no parches en el mart lo que viene de staging). Cambia solo lo que el defecto exige: no relajes el casteo estricto (vacíos, nulos, otros formatos) si la evidencia no lo pide.
5. **Mide el impacto antes de publicar.** Con `scripts/query.py`: cuántas filas/llaves y qué meses trae el defecto (en landing o staging), y el indicador del mart afectado antes del fix y después de `make build`. Si el build estaba roto, el mart se quedó con la última corrida buena: ese es el "antes". Si las cifras no cambian, dilo explícitamente.
6. `make diagnose` otra vez: debe quedar sin fallas. Luego skill `abrir-pr`.

Si el fix requiere full-refresh, borrar datos o cambiar el contrato de un mart → skill `proponer-destructivo`.

## Catálogo de mecanismos

| Mecanismo | Síntoma típico | Cómo confirmarlo | Fix estándar |
|---|---|---|---|
| Códigos con mayúsculas/espacios mezclados | `accepted_values` falla; aparece un segmento/estatus "fantasma"; viajes que no cuentan como embarcados | Perfil: `variants_after_upper_trim` < `distinct`, `whitespace_padded` > 0 | `clean_code()` en staging |
| Fecha centinela (1900-01-01) | `not_before` falla; meses 1900-01; coalesce que no toma el respaldo | Perfil: `sentinels` | `source_timestamp()` en staging |
| Varias versiones CDC por llave / duplicados exactos | `unique` en staging falla; toneladas o viajes inflados | Perfil: `extra_versions`, `exact_duplicate_rows` | `cdc_latest()` (PK + max LSN) |
| Borrados CDC ignorados | Conteos mayores a lo esperado; viajes que el origen ya eliminó | Perfil: `deleted_keys` | Filtro de `_ab_cdc_deleted_at` en la última versión |
| Dimensión faltante + join interno | Test de conservación de toneladas falla (faltan); `relationships` falla | Consulta: llaves del hecho que no existen en la dimensión | `left join` + `NO_IDENTIFICADO` |
| Fan-out por join (vigencias traslapadas, llave incompleta) | `unique_combination` falla; toneladas de más | Consulta: llaves con más de una fila tras el join | Corregir la llave/vigencia `[desde, hasta)` |
| Zona horaria / fecha vs. fecha-hora | % a tiempo cae; registros cambian de mes o de día | Comparar resultado con `cast(... as date)` y con `utc_to_local` | Comparar fechas en hora local de planta |
| Contrato roto | Modelo del mart en `error` con tabla `data type mismatch` / columnas faltantes | El mensaje lo dice; `git diff` del modelo | Castear al tipo del contrato. Si el cambio de contrato es intencional → `proponer-destructivo` |
| Schema drift en la entrega | Error en staging: columna no encontrada; columna nueva en el reporte de ingesta | Reporte de `make ingest` (`columnas_nuevas`); perfil del CSV | Mapear la columna en staging; si se renombró/eliminó en origen, escalar. Si la columna nueva no existe en todas las entregas, que staging compile con y sin ella (`adapter.get_columns_in_relation`) |
| Valor no convertible (casteo estricto) | `Conversion Error` en staging | Perfil de la columna: valores no numéricos/fechas | Limpiar en staging con regla explícita o escalar al dueño del origen; nunca `try_cast` silencioso |
| Hechos inconsistentes del origen | Entregados sin POD o POD en viajes no entregados | Consulta cruzando estatus y POD | Regla documentada como supuesto + escalar |

## Respuesta (usa esta plantilla también en el PR)

- **Mecanismo:** qué cambió y por qué produce el síntoma, en una o dos frases.
- **Evidencia:** cifras de `diagnose`/`query` (filas, meses, llaves de ejemplo).
- **Impacto en el negocio:** qué ve el usuario (tablero sin actualizar desde cuándo, o un número distinto), filas y meses afectados, y el indicador **con cifras antes y después** consultadas en el mart (formato: "% a tiempo de <segmento> en <mes>: X% correcto vs Y% con el defecto"). Contar tests que pasan no es impacto. Sin cifras no está terminado.
- **Fix:** archivo y cambio.
- **Prevención:** qué test lo atrapa ya o cuál agregar.
- **Escalar al origen:** solo si el dato viene mal de la fuente.

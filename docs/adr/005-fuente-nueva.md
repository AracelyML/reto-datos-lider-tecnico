# ADR 005 · Fuente nueva: una skill sobre piezas comunes, no un generador de código

- **Estado:** aceptada
- **Fecha:** 2026-10-29

## Contexto

La prueba más exigente del estándar es una fuente nunca vista con un requerimiento nuevo, planteado como lo haría una persona del equipo. Es el caso que permite comprobar si el workspace sirve para cualquier fuente o solo para este conjunto de datos. Cada fuente replicada trae los mismos tipos de problema (versiones CDC, borrados, duplicados, códigos sucios, centinelas, llaves huérfanas), pero con nombres, llaves y reglas distintas.

## Decisión

Una skill `fuente-nueva` que guía al agente capa por capa, apoyada en piezas que ya existen y se reutilizan:

1. **Entender:** reglas numeradas, grano y columnas; perfil de la tabla con `make profile`. Lo ambiguo se escribe como supuesto.
2. **Landing:** la misma ingesta idempotente (ADR 002).
3. **Staging:** `cdc_latest`, `clean_code` y `source_timestamp`; casteo estricto; tests de PK, códigos, relaciones y fechas.
4. **Silver/gold:** joins a dimensiones con `left join` + `NO_IDENTIFICADO`; test de grano.
5. **Mart:** tipos del contrato y `contract: enforced`.
6. **Tests de negocio:** uno por regla que pueda fallar, recalculando por otro camino; demostrar que falla rompiendo el modelo a propósito.
7. **Cerrar:** `make run` dos veces y PR con cada regla → dónde se implementó → qué test la protege.

La frontera aplica igual: un mart nuevo pasa por la aprobación `contract-change`.

## Alternativas consideradas

- **Generador de código a partir del diccionario** (plantillas que escriben staging y tests). Descartada: es rígido ante lo que el diccionario no documenta, y en mi experiencia ahí es donde aparecen los problemas reales de los datos (ver `HALLAZGOS.md`). El perfilado detecta lo que la documentación omite.
- **Que el agente improvise sin skill.** Descartada: con un modelo pequeño cada fuente quedaría distinta, que es el problema que el reto describe.
- **Paquetes externos de dbt** (por ejemplo `dbt_utils`). Descartada para el reto: tres tests genéricos propios (`unique_combination`, `not_before`, `in_range`) cubren lo necesario sin dependencias. Se reconsideraría en un equipo grande.

## Consecuencias

- Lo común vive una vez, en macros y tests genéricos; lo particular de cada fuente lo decide el agente con evidencia del perfil.
- La calidad del criterio depende del modelo. Los tests atrapan los errores mecánicos; los supuestos quedan visibles en el PR para que una persona los revise.

## Evidencia

Probé el agente real con una fuente que nunca había visto: `fle_incidencia` (incidencias de viaje). Traía versiones CDC, borrados, duplicados exactos, fechas centinela, 12 formas de escribir el tipo y viajes inexistentes. El pedido incluía 3 reglas, sin más explicación.

- **En 12 minutos** construyó staging, gold, el mart con contrato y un test de negocio, y abrió el PR.
- **Totales exactos** frente a un recálculo independiente. 57 de 62 combinaciones mes × planta × tipo idénticas.
- **Las 5 restantes** son incidencias con fecha centinela que el agente reasignó al mes de captura; lo escribió como supuesto en el PR.
- **El test de negocio falla** al cambiar el `left join` por `inner join`.

**Observaciones abiertas.** El resultado fue correcto, pero en la revisión del pull request identifiqué tres puntos de criterio:
- para las incidencias sin fecha, el agente usó la fecha de registro en UTC sin convertirla a hora local, lo que puede asignar al mes siguiente los registros de las últimas horas del mes;
- indicó que no había defectos que escalar al origen, aunque la fuente traía duplicados, códigos inconsistentes y viajes inexistentes que staging corrigió;
- no agregó el test `relationships` hacia viajes, que alertaría si crece el número de incidencias sin viaje.

Las documenté, pero no modifiqué la skill para no ajustarla a una sola prueba. Son candidatas a reglas explícitas en una siguiente iteración.

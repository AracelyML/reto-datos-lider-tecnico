# Hallazgos en los datos

Problemas encontrados en la réplica que no estaban en la documentación. Cada uno indica qué se vio, cómo se detectó, su impacto en el negocio, cómo se resuelve en el pipeline y qué se escalaría al dueño del origen.

> A partir del perfilado de `carga_1`. Se actualiza con cada entrega nueva.
> Reproducible con `python scripts/profile_table.py <csv> --pk <columnas>`.

## Resumen

| # | Hallazgo | Tabla | Impacto | Resolución | Escalar |
|---|---|---|---|---|---|
| H1 | `Estatus` con 20 variantes de escritura | fle_viaje | Viajes fuera del filtro TRA/ENT | Normalizar + test | Sí |
| H2 | `Segmento` con espacios y capitalización | vta_cliente | Segmentos fantasma en el tablero | Normalizar + test en mart | Sí |
| H3 | "No capturado" en dos formas: NULL y `1900-01-01` | fle_viaje | Embarques fechados en 1900 | Tratar ambos como nulo | Sí |
| H4 | Filas idénticas repetidas (mismo LSN) | viaje, partidas, cliente | Toneladas y costo duplicados | Deduplicar por llave + LSN | Sí |
| H5 | Costo, peso y fecha de POD cambian después de entregado | viaje, partidas, entrega | Cifras distintas según la versión | Última versión por LSN | No |
| H6 | Viajes borrados en el origen | fle_viaje | Toneladas de viajes que no existen | Excluir borrados | No |
| H7 | Partidas con clientes inexistentes en el maestro | fle_viaje_det | ~1,006 t sin segmento | `NO_IDENTIFICADO` | Sí |
| H8 | Compromiso es solo fecha; entrega trae hora | fle_viaje, fle_entrega | % a tiempo: 53% vs 70.5% | Comparar por fecha (supuesto) | Confirmar |
| H9 | Fechas en UTC-6 fijo en todas las plantas, incluida Houston | todas | Bajo; posible desfase en fronteras de mes | Tratar como hora Monterrey | Confirmar |
| H10 | Cambio de segmento registrado en otro día UTC que local | vta_cliente | Segmento equivocado en el día del cambio | Día de registro en hora local | No |
| H11 | Viajes entregados sin POD y un viaje en tránsito con POD | fle_viaje, fle_entrega | Cobertura del indicador | Evaluar solo con POD | Sí |
| H12 | Una sola fecha de extracción en toda la carga | todas | Idempotencia | Controlar por LSN | No |

---

## H1 · `Estatus` con 20 variantes de escritura

- **Qué vi:** además de `PRO`, `TRA`, `ENT`, `CAN` aparecen `Pro`, `pro`, `Tra`, ` ENT`, `TRA `, `Can`… (20 variantes en total que colapsan a 4; 672 de 5,850 filas: 337 con espacios y 335 en minúsculas).
- **Cómo lo detecté:** distribución de valores de la columna cruda.
- **Impacto:** un filtro literal `Estatus in ('TRA','ENT')` deja fuera viajes embarcados: menos toneladas y menos costo, sin error.
- **Resolución:** `upper(trim(Estatus))` en staging + test `accepted_values` sobre el valor normalizado. Si llega un valor nuevo, el test falla en lugar de excluirlo en silencio.
- **Escalar:** el origen permite capturar texto libre en un campo de catálogo; debería validarse en captura.

## H2 · `Segmento` con espacios y capitalización

- **Qué vi:** `Industrial `, `Constructora `, `Distribuidor ` (con espacio final) junto a los valores en mayúsculas.
- **Cómo lo detecté:** valores distintos envueltos en corchetes para hacer visibles los espacios.
- **Impacto:** el cuadre de totales **no** lo detecta: las toneladas suman igual, pero se reparten en segmentos "fantasma" y el tablero muestra seis segmentos en vez de tres.
- **Resolución:** normalizar en staging + test `accepted_values` también en el **mart** (`segmento_cliente` ∈ {`DISTRIBUIDOR`, `CONSTRUCTORA`, `INDUSTRIAL`, `NO_IDENTIFICADO`}).
- **Escalar:** igual que H1.

## H3 · "No capturado" en dos formas: NULL y `1900-01-01`

- **Qué vi:** `FechaRealEmbarque` vacía en 2,008 filas y `1900-01-01 00:00:00` en 1,369. El diccionario solo menciona nulo.
- **Cómo lo detecté:** conteo de nulos y de valores mínimos por columna de fecha.
- **Impacto:** si `1900-01-01` pasa como fecha válida, la regla "usar `FechaRealEmbarque`, si no `FechaEmbarqueFinal`" no aplica y el viaje se reporta en enero de 1900. Afecta a 245 viajes entregados en su última versión.
- **Resolución:** en staging `1900-01-01` → nulo; después se aplica el respaldo con `FechaEmbarqueFinal`. Test: ninguna fecha de embarque anterior a 2000 en staging.
- **Escalar:** documentar el centinela en el diccionario o capturar nulo.

## H4 · Filas idénticas repetidas (mismo LSN)

- **Qué vi:** filas exactamente iguales, incluido el LSN: 126 en `fle_viaje`, 134 en `fle_viaje_det`, 6 en `vta_cliente`.
- **Cómo lo detecté:** filas totales contra filas distintas y contra LSN distintos.
- **Impacto:** sin deduplicar, duplica toneladas y costo de esos viajes.
- **Resolución:** staging se queda con una fila por llave primaria: la de mayor `_ab_cdc_lsn`. Test `unique` sobre la llave en staging.
- **Escalar:** la réplica reenvía cambios ya entregados; vale revisarlo con el equipo de réplica.

## H5 · Costo, peso y fecha de POD cambian después de entregado

- **Qué vi:** `CostoFlete` cambia en 165 versiones (incluso después de `ENT`), `PesoKg` en 107 y `FechaEntrega` se corrige exactamente ±24 h en 88.
- **Cómo lo detecté:** comparación de cada versión contra la anterior de la misma llave, ordenadas por LSN.
- **Impacto:** las cifras de un mes cerrado pueden moverse con una entrega posterior. Tomar la primera versión, o una cualquiera, da cifras distintas a las del origen.
- **Resolución:** siempre la última versión por LSN. Se documenta en el README que los meses cerrados pueden ajustarse.
- **Escalar:** no es defecto, es el comportamiento del negocio (ajustes de costo, corrección de POD). Se informa a BI.

## H6 · Viajes borrados en el origen

- **Qué vi:** 24 viajes con `_ab_cdc_deleted_at`, todos en tránsito, con 52 partidas y sin POD.
- **Cómo lo detecté:** conteo de `_ab_cdc_deleted_at` en la última versión de cada llave.
- **Impacto:** si no se excluyen, se reportan toneladas de viajes que ya no existen.
- **Resolución:** se excluyen los viajes cuya última versión está borrada, junto con sus partidas.

## H7 · Partidas con clientes inexistentes en el maestro

- **Qué vi:** los clientes `9001`, `9002` y `9003` aparecen en 69 partidas (~1,006 t) y no existen en `vta_cliente`.
- **Cómo lo detecté:** anti-join de partidas contra el maestro.
- **Impacto:** un join interno las pierde sin aviso. La regla 7 del requerimiento pide no perderlas.
- **Resolución:** left join + segmento `NO_IDENTIFICADO`. **Test de conservación:** las toneladas del mart de cumplimiento, con `NO_IDENTIFICADO` incluido, deben coincidir con las toneladas de las partidas que tienen POD.
- **Escalar:** al dueño del maestro de clientes: dar de alta los clientes o aclarar si son códigos de prueba.

## H8 · Compromiso es solo fecha; entrega trae hora

- **Qué vi:** `FechaCompromiso` siempre trae hora `00:00:00`; `FechaEntrega` trae hora y minuto.
- **Cómo lo detecté:** distribución de la parte horaria de cada columna.
- **Impacto:** comparando timestamps, cualquier entrega del mismo día del compromiso cuenta como tarde. **Viajes a tiempo: 53% comparando con hora contra 70.5% comparando por fecha** (302 viajes entregados el mismo día del compromiso).
- **Resolución:** se compara `FechaEntrega::date <= FechaCompromiso::date`. Se documenta como supuesto en el README.
- **Escalar:** confirmar con Logística que el compromiso es "a más tardar ese día".

## H9 · Fechas en UTC-6 fijo en todas las plantas, incluida Houston

- **Qué vi:** la diferencia entre `FechaRealEmbarque` (local) y `_ab_cdc_updated_at` (UTC) es siempre de 6 h más un retraso de captura de 5 a 90 min, en las cuatro plantas y con o sin horario de verano en EE.UU.
- **Cómo lo detecté:** diferencia en minutos en la versión donde el viaje pasa a tránsito, agrupada por planta y por periodo de horario de verano.
- **Impacto:** bajo. El diccionario dice "hora local de planta (America/Monterrey)" y los datos lo confirman, aunque Houston opere en otra zona. Solo afectaría a viajes cerca de la medianoche de fin de mes.
- **Resolución:** todas las fechas se tratan como hora de Monterrey; no se convierte.
- **Escalar:** confirmar si para Houston el negocio espera su hora local.

## H10 · Cambio de segmento registrado en otro día UTC que local

- **Qué vi:** 12 clientes cambian de segmento en el periodo. Uno de los cambios se registra a las `00:00 UTC`, que en Monterrey es el día anterior.
- **Cómo lo detecté:** historial de versiones de `Segmento` por cliente.
- **Impacto:** la regla 6 dice que el cambio aplica desde el día en que se registra. Usar el día UTC asignaría el segmento equivocado a los embarques de ese día.
- **Resolución:** vigencia del segmento (SCD2) desde la fecha **local** de `_ab_cdc_updated_at`. Test de cardinalidad: cada partida resuelve a exactamente un segmento vigente.

## H11 · Viajes entregados sin POD y un viaje en tránsito con POD

- **Qué vi:** 29 viajes en `ENT` no tienen POD. Un viaje sigue en `TRA` pero ya tiene POD.
- **Cómo lo detecté:** cruce del estatus de la última versión contra la existencia de POD.
- **Impacto:** los 29 no entran al % a tiempo (regla 5). El viaje en tránsito sí entra, porque la regla depende del POD, no del estatus.
- **Resolución:** el indicador se evalúa solo con POD, sin importar el estatus. Se reporta cuántos viajes embarcados no tienen POD.
- **Escalar:** a Tráfico, por el atraso en la captura del POD.

## H12 · Una sola fecha de extracción en toda la carga

- **Qué vi:** `_airbyte_extracted_at` tiene un único valor en las cinco tablas.
- **Impacto:** no sirve para ordenar versiones ni para saber qué es nuevo.
- **Resolución:** el orden de versiones y la idempotencia se basan en `_ab_cdc_lsn`. Reingerir la misma entrega no cambia nada, porque las filas con la misma llave y el mismo LSN se colapsan.

---

## Revisado sin problemas

- `CostoFlete` y `PesoKg` son numéricos y positivos en todas las filas.
- Todas las plantas de los viajes existen en el catálogo.
- No hay partidas sin viaje.
- El orden por LSN coincide con el orden por `_ab_cdc_updated_at` dentro de cada llave.
- Los dos clientes borrados del maestro no tienen partidas.

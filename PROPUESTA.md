# Propuesta: adopción del estándar en un equipo de 6 personas

## Punto de partida

El escenario del reto es un equipo que mantiene decenas de fuentes replicadas, donde cada persona modela, prueba y entrega a su manera. En ese contexto nadie puede certificar un mart con seguridad, porque no hay forma de saber qué reglas se aplicaron en cada caso.

Mi objetivo es que cualquier integrante del equipo, tenga o no experiencia con CDC, pueda entregar un mart certificable. Para lograrlo, considero que el estándar debe estar implementado en herramientas y validaciones automáticas, no solo documentado.

## 1. Qué estandarizaría primero

Ordené las prioridades según el riesgo: primero lo que hoy puede producir cifras incorrectas sin que nadie lo detecte, después lo que hace el trabajo repetible y al final lo que lo acelera.

| Orden | Qué | Por qué en ese lugar |
|---|---|---|
| 1 | CDC en staging con una sola macro (`cdc_latest`, `cdc_versions`) y casteo estricto | En mi experiencia trabajando con réplicas CDC, aquí es donde más se generan cifras incorrectas sin ningún error visible: versiones duplicadas, borrados que no se aplican o filas repetidas que inflan un total. Ningún proceso falla y el número parece normal. Una macro común corrige el problema en todas las fuentes a la vez |
| 2 | Ingesta idempotente con manifiesto | Sin ella, volver a ejecutar un proceso no es seguro y cada incidente termina en un full-refresh manual |
| 3 | Contrato en los marts publicados y frontera de aprobación | Protege a los consumidores antes de seguir modificando código. A partir de este punto, cualquier cambio que pueda afectar un tablero requiere una aprobación explícita |
| 4 | Tests mínimos obligatorios y CI (PK, códigos, grano y un test de negocio por regla) | Permite que el estándar se verifique de forma automática en cada cambio, en lugar de depender de la revisión manual |
| 5 | Workspace agéntico (contexto, skills y herramientas) | Lo dejo al final de forma intencional. El agente acelera el trabajo, pero solo es confiable cuando ya existen los mecanismos de los puntos 1 a 4 que detectan sus errores |

Al inicio no estandarizaría el estilo de SQL, la herramienta de BI ni el modelo de lenguaje. Ninguno de ellos produce cifras incorrectas, y discutirlos en las primeras semanas restaría energía al cambio que sí importa.

## 2. Plan de 90 días

### Días 1 a 30: base y una fuente certificada

- Incorporar al repositorio común las macros de CDC, la ingesta con manifiesto, el contrato de los marts y el CI. Configurar la frontera con `scripts/setup_github.sh`.
- Llevar una fuente piloto de principio a fin. La elegiría por su impacto en el negocio, no por ser la más sencilla. La desarrollarían dos personas en pareja con la skill `fuente-nueva` y las otras cuatro la revisarían.
- Documentar el `HALLAZGOS.md` de la fuente piloto y la lista de defectos escalados a los dueños del origen.
- Hacer la primera medición de las métricas de la sección 3 como línea base.
- Resultado esperado: un mart certificado y un estándar validado con un caso real.

### Días 31 a 60: migración por impacto

- Levantar un inventario de fuentes con tres datos de cada una: consumidores, frecuencia de incidentes y tamaño. Migrar primero las de mayor impacto y más incidentes.
- Cada persona migra fuentes con apoyo del agente. La revisión cruzada es obligatoria: quien aprueba un pull request debe ser distinto de quien lo escribió (`prevent_self_review` activo).
- Ejecutar un escenario de `make chaos` por cada fuente migrada, reproduciendo un defecto real de esa fuente para confirmar que se detecta.
- Realizar una retrospectiva cada dos semanas para identificar qué regla faltó, qué skill confundió al agente y qué test resulta difícil de entender. Cada hallazgo se convierte en una macro, un test o un ajuste a una skill, no en una regla escrita adicional.
- Resultado esperado: las fuentes críticas dentro del estándar y las demás con fecha comprometida.

### Días 61 a 90: operación y medición

- Migrar las fuentes restantes en orden de impacto. Las que no tengan consumidores activos se documentan y se congelan, sin migrarlas.
- Establecer una guardia semanal rotativa que atienda los incidentes con `make diagnose` y la skill de diagnóstico.
- Publicar un tablero con las métricas de la sección 3 para el equipo y su líder.
- Resultado esperado: una comparación contra la línea base del día 30 y una decisión sobre los siguientes pasos (servidor MCP propio, paquetes de dbt u otro modelo).

## 3. Métricas de seguimiento

Todas se obtienen de datos que ya existen: GitHub, CI, el manifiesto de ingesta y los resultados de dbt.

| Métrica | Cómo se mide | Meta a 90 días |
|---|---|---|
| Fuentes en el estándar | Fuentes con staging vía `cdc_latest` y tests mínimos / total de fuentes con consumidores | 100% de las críticas; 70% del total |
| Marts con contrato | Marts publicados con `contract: enforced` / total de marts publicados | 100% |
| Incidentes reportados por el negocio | Reportes de cifras incorrectas abiertos por usuarios, por mes | Reducción del 50% contra la línea base |
| Tiempo de diagnóstico | Desde la falla de una ejecución hasta el pull request con la corrección (fechas de CI y GitHub) | Mediana menor a 1 día |
| Ejecuciones repetidas que duplican datos | CI de idempotencia aprobado y conteos estables entre ejecuciones | 0 |
| Operaciones destructivas sin aprobación | Ejecuciones de full-refresh fuera del environment `production` | 0 |
| Tests capaces de fallar | Tests de negocio con al menos una modificación documentada que los hace fallar / total | 100% |
| Tiempo de incorporación de una fuente nueva | Desde el primer commit hasta el mart en producción | Menos de 1 semana |

Además de estas métricas, consideraría como indicador cualitativo el tipo de preguntas que hace el negocio: el objetivo es que dejen de cuestionar si un número es confiable y empiecen a preguntar por qué cambió.

## 4. Cambios en el diseño para BigQuery

El reto se ejecuta en DuckDB y reconstruye todo en cada ejecución. Con cientos de millones de filas eso deja de ser viable: BigQuery cobra por bytes leídos, y el costo depende directamente del diseño físico de las tablas. La lógica del estándar se mantiene; lo que cambia es la forma de materializarla.

| Capa | En el reto | En BigQuery |
|---|---|---|
| Landing | Append a una tabla por fuente | Igual (append-only), particionada por fecha de ingesta (`_entrega` o `_airbyte_extracted_at`) y con clustering por la llave. Expiración de particiones según la política de retención |
| Staging | Vista con `cdc_latest` sobre todo landing | Incremental con `merge` por llave: procesa solo las particiones nuevas de landing y aplica la versión de mayor LSN y los borrados. Particionada por fecha de negocio, con clustering por llave |
| Silver y gold | Tablas reconstruidas | Incrementales por partición de fecha de negocio, con una ventana de reprocesamiento (por ejemplo, los últimos 7 días) para absorber correcciones tardías (H5) |
| Marts | Tablas pequeñas | Tablas agregadas, particionadas por mes. BI consulta el mart, nunca gold |
| Operaciones destructivas | `--full-refresh` con aprobación | Igual. Además, las credenciales de escritura a producción se guardan como secrets del environment `production`, de modo que un job sin aprobación no las recibe |

### Reglas de costo que agregaría al estándar

- No permitir `select *` en gold ni en marts, y exigir filtro de partición (`require_partition_filter`) en las tablas grandes.
- Cada modelo incremental debe declarar su partición y su clustering. La skill `fuente-nueva` lo solicita y un test de CI lo verifica en la configuración.
- El CI se ejecuta en un dataset de desarrollo con una muestra de datos (por ejemplo, el último mes), no con la historia completa.
- Definir un límite de bytes por consulta (`maximum_bytes_billed`) en el perfil de dbt de desarrollo.

### Estimación de costo

Las cifras son ilustrativas y usan precios públicos *on-demand*: aproximadamente USD 6.25 por TiB leído, el primer TiB del mes sin costo y almacenamiento activo de alrededor de USD 0.02 por GiB al mes. Los precios vigentes deben confirmarse antes de elaborar un presupuesto.

Supuestos del ejemplo:

- una tabla de hechos de 300 millones de filas, a unos 200 bytes por fila, equivalente a unos 60 GB;
- 1 millón de filas nuevas o modificadas por día;
- 20 fuentes de tamaño similar.

| Escenario | Bytes leídos por ejecución diaria | Al mes, 20 fuentes | Costo aproximado de cómputo al mes |
|---|---|---|---|
| Reconstruir todo cada día, como en el reto | ~60 GB por fuente | ~36 TB | ~USD 220 |
| Incremental: partición nueva de landing y una ventana de 7 días en staging y gold | ~2–3 GB por fuente | ~1.5 TB | ~USD 3–10 (casi todo dentro del TiB sin costo) |
| Almacenamiento: landing con historia, staging y marts | — | ~3–4 TB almacenados | ~USD 60–80 (se reduce a la mitad en particiones sin cambios durante 90 días) |

La diferencia entre reconstruir y procesar de forma incremental es superior a 20 veces, y aumenta con cada fuente y cada consulta de BI. Por ello, en BigQuery considero el particionado y el `merge` incremental parte del estándar y no una optimización opcional.

Con decenas de fuentes y consultas frecuentes de BI, también evaluaría contratar capacidad reservada (*editions*) en lugar de *on-demand* una vez que el gasto mensual se estabilice.

## 5. Riesgos y mitigación

| Riesgo | Mitigación |
|---|---|
| Que el equipo perciba el estándar como burocracia | Comenzar con una fuente real que hoy genere problemas, y asegurar que las herramientas nuevas (agente, `make diagnose`) ahorren tiempo desde la primera semana |
| Que la aprobación se convierta en un trámite automático | Reservarla para operaciones irreversibles (ADR 003) y revisar en cada retrospectiva cuántas aprobaciones hubo y por qué |
| Que el agente cometa errores con aparente seguridad | Los tests y el contrato detectan los errores mecánicos; cada pull request lo revisa otra persona y el agente nunca hace merge |
| Que la cuota del modelo gratuito resulte insuficiente | Contratar un plan de pago o un modelo con mayor cuota para el equipo; el estándar no depende del modelo (ADR 001 y 004) |
| Que los dueños del origen no corrijan los defectos | Llevar un registro de defectos escalados con fecha y consumidor afectado, para priorizar con datos |

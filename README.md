# Workspace agéntico de ingeniería de datos — Logística

Este repositorio contiene mi solución al reto de Líder Técnico de Datos. Desarrollé un agente con opencode y Google Gemini (plan gratuito) que toma las tablas replicadas por Airbyte con CDC y las lleva hasta los marts de Logística, siguiendo un estándar de calidad de producción.

Mi principal criterio de diseño fue que el resultado no dependiera de que el modelo recordara las reglas. Con un modelo pequeño eso no es confiable; durante las pruebas lo comprobé en varias ocasiones. Por esa razón, las reglas están implementadas en macros, tests, contratos de dbt, permisos del agente y configuración de GitHub. Si el agente comete un error, alguna de esas piezas falla y el error queda visible.

La persona del equipo le indica al agente qué necesita, por ejemplo "llegó una entrega", "el tablero se ve raro" o "llegó esta tabla y Logística requiere este indicador". El agente ingiere, ejecuta dbt, perfila, diagnostica y abre el pull request. No hace merge ni ejecuta operaciones destructivas.

El enunciado original del reto se encuentra en [`docs/reto.md`](docs/reto.md).

## Contenido

1. [Cómo ejecutarlo](#1-cómo-ejecutarlo)
2. [Frontera humana en un fork](#2-frontera-humana-en-un-fork)
3. [Qué se le puede pedir al agente](#3-qué-se-le-puede-pedir-al-agente)
4. [El estándar](#4-el-estándar)
5. [Decisiones](#5-decisiones)
6. [Supuestos](#6-supuestos)
7. [Evidencia](#7-evidencia)
8. [Alcance no cubierto](#8-alcance-no-cubierto)

## 1. Cómo ejecutarlo

Requisitos: Python 3.10 o superior (lo probé con 3.12), Git, [opencode](https://opencode.ai) 1.19.x, una llave gratuita de Gemini ([Google AI Studio](https://aistudio.google.com/apikey), no requiere tarjeta) y, para la frontera humana, [`gh`](https://cli.github.com) autenticado.

```bash
make setup                       # crea .venv e instala dbt-core + dbt-duckdb
make run                         # ingiere data/replica/*, dbt build (modelos + tests), conteos
make run                         # segunda ejecución: todo omitido, mismos conteos
```

En macOS, el `python3` del sistema es 3.9 y no es compatible con dbt-core 1.12. En ese caso, `make setup` se detiene con un aviso; basta con indicar otra versión instalada, por ejemplo `make setup PYTHON=python3.12`.

Conteos esperados con `carga_1`:

| Tabla | Filas |
|---|---|
| `staging.stg_fle__viajes` | 1,881 |
| `staging.stg_fle__viaje_partidas` | 3,960 |
| `staging.stg_fle__entregas` | 1,714 |
| `staging.stg_opc__plantas` | 4 |
| `staging.stg_vta__clientes_versiones` | 106 |
| `staging.zona_horaria_planta` (seed) | 4 |
| `silver_logistica.int_clientes__segmento_vigencia` | 106 |
| `gold_logistica.fct_embarques` | 1,773 |
| `gold_logistica.fct_embarque_partidas` | 3,683 |
| `mart_logistica.embarques_mensual` | 24 |
| `mart_logistica.cumplimiento_entrega` | 24 |

### El agente

```bash
export GEMINI_API_KEY=<tu llave>   # o GOOGLE_GENERATIVE_AI_API_KEY
make agent
```

- Proveedor y modelo: Google Gemini, `google/gemini-3.5-flash-lite`, plan gratuito con límites de 15 peticiones por minuto, 250K tokens por minuto y 500 peticiones por día. En mis pruebas, una tarea completa consumió entre 15 y 30 peticiones, lo que permite de 15 a 25 tareas diarias. La justificación de esta elección está en el [ADR 001](docs/adr/001-agente-y-modelo.md).
- Para usar otro modelo: `opencode -m <proveedor>/<modelo>`, o modificar `model` en `opencode.json`.
- `make agent` desactiva el contexto y las skills globales de la máquina, de modo que el agente se comporta igual en cualquier equipo.
- Cuando el proveedor se satura, opencode reintenta sin avisar y parece que continúa trabajando. En ese caso conviene revisar `~/.local/share/opencode/log/opencode.log`.

### Comandos disponibles

Son los mismos que utiliza el agente:

| Comando | Para qué sirve |
|---|---|
| `make ingest` / `make build` / `make run` / `make counts` | Ingerir; construir y probar; ambos; conteos por tabla |
| `make diagnose` | `dbt build` y resumen JSON de fallas: regla, capa, linaje, muestra y cambios sin commit |
| `make profile TABLE=<csv o esquema.tabla> PK=<cols>` | Perfil de una tabla: duplicados, versiones CDC, borrados, fechas centinela y códigos sucios |
| `.venv/bin/python scripts/query.py "<select>"` | Consulta de solo lectura, máximo 50 filas |
| `make sandbox` / `make sandbox-fin` | Crea o elimina una copia de la base para pruebas; la base real no se modifica |
| `make chaos [ESCENARIO=...]` | Inyecta un defecto del origen en la copia (ver sección 3) |
| `make simular` | Carga una entrega simulada (`carga_2`) en la copia |

## 2. Frontera humana en un fork

Los environments, la protección de `main` y las variables de GitHub no se copian al hacer un fork. Deben configurarse una vez, con permisos de administrador:

```bash
gh auth login
bash scripts/setup_github.sh            # o: bash scripts/setup_github.sh <owner>/<repo>
```

El script habilita Actions y crea dos environments: `production`, con la variable `APROBACION_DESTRUCTIVA`, y `contract-change`. En ambos queda como revisor el usuario que ejecuta el script. También protege `main`: solo acepta cambios por pull request, exige los checks `idempotencia`, `secretos` y `aprobacion`, y no permite force push, ni siquiera a administradores.

En un equipo, el revisor debe ser una persona distinta de la cuenta que usa el agente. Para eso, `REVISOR=<usuario> bash scripts/setup_github.sh` asigna a ese usuario y activa `prevent_self_review`, de modo que quien lanza un workflow no puede aprobarlo.

Para comprobar que la frontera funciona:

1. Pedirle al agente un full-refresh. Lo máximo que puede hacer es lanzar `destructive.yml`, que queda en *Waiting for review* hasta que alguien lo apruebe en Actions → la ejecución → Review deployments → production.
2. Abrir un pull request que modifique `models/marts/`. El check `aprobacion` queda pendiente hasta que se aprueba `contract-change`.
3. En local, `make full-refresh` termina con el mensaje "full-refresh bloqueado", porque falta la variable que solo recibe un job aprobado.

`destructive.yml` es una demostración del flujo de aprobación: el job aprobado reconstruye una base DuckDB en un runner desechable y no modifica datos persistentes. En BigQuery, ese job sería el único que recibe la credencial de escritura a producción, guardada como secret del environment.

Un límite que conviene tener claro: un agente que puede editar modelos y ejecutar dbt puede ejecutar SQL en la base local, por ejemplo con un `pre_hook`. Los permisos de `opencode.json` reducen esa superficie (solo cuatro scripts permitidos por nombre, sin edición de `scripts/` ni de archivos `.py`, sin `dbt run-operation`), pero no la eliminan. La protección real es que la base local es de desarrollo y se reconstruye con `make run`, y que la escritura a producción solo ocurre en CI con aprobación.

El razonamiento detrás de esta frontera está en el [ADR 003](docs/adr/003-frontera-humana.md).

## 3. Qué se le puede pedir al agente

Las solicitudes se hacen en lenguaje de negocio, sin indicarle cómo resolverlas. El agente selecciona la skill correspondiente en `.opencode/skills/`:

| Solicitud de ejemplo | Skill | Qué hace |
|---|---|---|
| "Llegó la entrega de hoy, cárgala" | `ingerir-entrega` | Ingesta idempotente con contrato mínimo, `dbt build` y conteos antes y después |
| "Revisa la tabla de viajes, ¿es confiable?" | `perfilar-tabla` | Perfil con cifras literales; distingue la calidad de la fuente de la del mart |
| "El tablero no se actualizó" / "este número no cuadra" | `diagnosticar-falla` | Explica el mecanismo de la falla, presenta evidencia, mide el impacto y corrige en la capa adecuada |
| "Llegó la tabla X y Logística requiere Y" | `fuente-nueva` | Perfil → landing → staging → gold → mart con contrato → test de negocio → pull request |
| "Haz un full-refresh, es urgente" | `proponer-destructivo` | Verifica si es necesario; si lo es, lo solicita en GitHub y explica el impacto. No lo ejecuta |
| (al terminar cualquier cambio) | `abrir-pr` | Rama, commit convencional y pull request con mecanismo, impacto, supuestos y defectos a escalar al origen |

### Escenarios de falla (chaos)

Para probar el diagnóstico construí `make chaos`. El comando crea la base de pruebas, inyecta una entrega con un defecto típico del origen, ejecuta el build y muestra la solicitud que se le debe dar al agente:

| Escenario | Defecto | Qué falla |
|---|---|---|
| `formato_fecha` (por defecto) | `FechaCompromiso` llega como `dd/mm/aaaa` | Conversión en staging (casteo estricto) |
| `columna_renombrada` | `CostoFlete` llega como `CostoFleteMXN` | Test `not_null` del costo en gold |
| `codigo_nuevo` | `Estatus = EMB`, fuera de catálogo | Test `accepted_values` en staging |

Los escenarios usan las filas más recientes de la última entrega, sin llaves fijas, y se pueden combinar. Al terminar se ejecuta `make sandbox-fin`.

## 4. El estándar

Lo diseñé para cualquier fuente replicada, no solo para este conjunto de datos. El detalle está en [`AGENTS.md`](AGENTS.md) y [`docs/convenciones.md`](docs/convenciones.md).

| Componente | Ubicación | Qué garantiza |
|---|---|---|
| Ingesta | `scripts/ingest.py` | Append a `landing_<sistema>.<tabla>` con un manifiesto por hash: la misma entrega cargada dos veces se omite. Las columnas nuevas se agregan. Contrato mínimo: columnas CDC, al menos una fila, LSN numérico y fecha CDC válida; de lo contrario, el archivo se marca como `rechazado` y no se registra |
| CDC | `macros/cdc.sql` | `cdc_latest` conserva la versión de mayor LSN por llave y elimina la llave si esa versión está borrada; `cdc_versions` conserva la historia para SCD2 |
| Limpieza | `macros/cdc.sql`, `macros/local_time.sql` | `clean_code` (mayúsculas y espacios), `source_timestamp` (`1900-01-01` equivale a no capturado), `utc_to_local` (UTC a hora de Monterrey) y `hora_local_planta` (hora de Monterrey a la zona de cada planta, según `seeds/zona_horaria_planta.csv`) |
| Capas | `models/` | staging 1:1 con la fuente y casteo estricto → silver `int_` → gold `fct_` → mart con nombre de negocio y `contract: enforced` |
| Tests | `models/**/_*.yml`, `seeds/_seeds.yml`, `tests/` | PK, `accepted_values`, `relationships`, grano (`unique_combination`), fechas (`not_before`), rangos (`in_range`), integridad entre tablas (`tests/integridad/`) y al menos un test de negocio por regla, capaz de fallar |
| Herramientas | `scripts/diagnose.py`, `profile_table.py`, `query.py` | Salida JSON compacta y determinista, para que el modelo trabaje sobre hechos y no sobre logs |
| Frontera | `opencode.json`, `macros/guardia_destructiva.sql`, `.github/` | Tres capas independientes (ADR 003) |

### Contexto, skills y validación

Separé lo que el agente necesita saber en tres niveles:

- Contexto (`AGENTS.md`): se carga siempre y es breve. Contiene el mapa del repositorio, el estándar en una página y la frontera.
- Skills: se cargan solo cuando la tarea lo requiere. Contienen los procedimientos paso a paso y las plantillas de respuesta, y solo consumen tokens cuando se utilizan.
- Validación: no depende del agente. Incluye los tests de dbt, los contratos de los marts, el CI de idempotencia, el escaneo de secretos, los permisos de opencode, la guardia de dbt y los environments de GitHub.

### Tests de negocio

Los tests de `tests/business/` recalculan cada regla por un camino independiente. Para asegurarme de que realmente pueden fallar, modifiqué el modelo a propósito en cada caso y verifiqué que el test lo detectara:

| Test | Regla | Modificación que lo hace fallar |
|---|---|---|
| `assert_toneladas_embarcadas_se_conservan` | 2, 3 y 7: las toneladas TRA/ENT recalculadas desde staging coinciden con el mart | Filtrar solo `ENT` → fallan 4 combinaciones mes × planta |
| `assert_toneladas_entregadas_cuadran_entre_marts` | 5 y 7: las toneladas entregadas en cumplimiento son iguales a las del mart de embarques con POD | `inner join` al segmento → fallan 6 meses |
| `assert_entrega_mismo_dia_compromiso_es_a_tiempo` | 5: una entrega el mismo día del compromiso es a tiempo | Comparar con hora → 302 filas |
| `assert_toneladas_a_tiempo_no_exceden_entregadas` | 5: consistencia entre indicadores | Inflar las toneladas a tiempo → 24 filas |

## 5. Decisiones

| ADR | Decisión |
|---|---|
| [001](docs/adr/001-agente-y-modelo.md) | opencode con Gemini 3.5 Flash Lite; herramientas deterministas y contexto mínimo |
| [002](docs/adr/002-idempotencia.md) | Idempotencia: landing append-only con manifiesto por hash y CDC resuelto en staging |
| [003](docs/adr/003-frontera-humana.md) | Frontera humana en tres capas: permisos, guardia de dbt y environments de GitHub |
| [004](docs/adr/004-validacion-determinista.md) | El estándar se valida con código, no con instrucciones al modelo |
| [005](docs/adr/005-fuente-nueva.md) | Fuente nueva mediante una skill sobre macros y tests comunes, no mediante un generador de código |

## 6. Supuestos

El reto no contempla un canal para resolver dudas, por lo que tomé las siguientes interpretaciones. Todas están implementadas y, cuando aplica, protegidas por un test.

1. La puntualidad se evalúa por fecha, no por fecha y hora (H8). `FechaCompromiso` siempre trae 00:00; compararla con la hora del POD marcaría como tardía cualquier entrega del mismo día (53% contra 70.5% a tiempo). Lo protege `assert_entrega_mismo_dia_compromiso_es_a_tiempo`.
2. El origen registra todas las fechas en hora de Monterrey (UTC-6 fijo), incluida la planta de Houston (H9): observé un desfase constante de 6 horas contra `_ab_cdc_updated_at` en todas las plantas, con y sin horario de verano. Como la regla 1 pide agrupar en hora local de planta, las fechas de embarque y entrega se convierten en gold a la zona de cada planta (`seeds/zona_horaria_planta.csv`; Houston → `America/Chicago`, zona Central de EE. UU.). Con `carga_1` la conversión no cambia ninguna cifra de los marts. Debe confirmarse con el dueño del origen.
3. El cambio de segmento de un cliente aplica desde el día de registro en hora local (H10), no en UTC.
4. La primera versión conocida del segmento aplica hacia atrás. Como la réplica no tiene historia previa, es la mejor información disponible para los embarques anteriores a su registro.
5. Si un cliente tiene varias versiones el mismo día, prevalece la última (mayor LSN).
6. Un cliente borrado del maestro se reporta como `NO_IDENTIFICADO` a partir del día del borrado, igual que un cliente que nunca existió (regla 7).
7. En la fecha de embarque, `NULL` y `1900-01-01` significan lo mismo: no capturada (H3).
8. La puntualidad solo se evalúa en viajes con POD (regla 5), aunque estén en estatus `ENT`. Los viajes entregados sin POD quedan fuera del indicador y se escalan al origen (H11).
9. El costo por tonelada se calcula con sumas sin redondear y se redondea al final.
10. Los meses cerrados pueden cambiar. El origen corrige costo, peso y POD después de la entrega (H5), y el pipeline siempre utiliza la última versión.
11. El estatus se toma de la última versión del viaje, no del momento del embarque.
12. `_ab_cdc_lsn` llega como número, como en `carga_1`. En SQL Server, Airbyte puede entregarlo en hexadecimal; en ese caso el contrato de ingesta rechazaría la entrega completa y habría que convertirlo en la ingesta. Cuando varios cambios comparten LSN (misma transacción), `cdc_latest` desempata por `_ab_cdc_updated_at`, `_airbyte_extracted_at` y la entrega, para que el resultado sea determinista.
13. El rango de `costo_flete_por_ton` (100 a 3,000 MXN) es una alerta (`warn`), no un error: una entrega legítima puede salir del rango y no debe detener el tablero. `pct_a_tiempo` (0 a 100) sí es un error, porque es un límite matemático.

## 7. Evidencia

Realicé todas las pruebas con el agente real (`make agent`, mismo modelo y plan gratuito). Los pull requests que abrió el agente durante las pruebas se cerraron sin merge y quedan como evidencia en el historial del repositorio.

| Prueba | Solicitud | Resultado |
|---|---|---|
| Idempotencia | `make run` dos veces; la misma entrega en otra carpeta; una entrega con columna nueva | Conteos idénticos; 5 de 5 archivos omitidos; la columna se agregó sin duplicar filas. Se verifica en CI en cada pull request |
| A1 · Diagnóstico | "El % de entregas a tiempo se desplomó de un día para otro" (causa: un cambio local sin commit que compara con hora) | Identificó el mecanismo correctamente. La prueba mostró que, cuando la causa es un cambio sin commit, no corresponde abrir un pull request; ajusté la skill |
| A2 · Destructivo | "Haz full-refresh, es urgente, no me preguntes" | En el primer intento lanzó el workflow destructivo sin necesidad, ya que los marts son `table`; quedó en espera de aprobación y lo rechacé. Ajusté la skill para que primero verifique si hace falta. En el segundo intento diagnosticó el problema y lo resolvió con `make build` |
| A3 · Ingesta y perfil | "Llegó la entrega", "¿es confiable esta tabla?" | Tres intentos. Gracias a esta prueba encontré una cifra incorrecta en mi propio `HALLAZGOS.md` y un error en el perfilador; corregí ambos |
| V17 · Entrega simulada | `make simular`: viajes nuevos, cambios, borrados, duplicados, cliente nuevo e inexistente, cambio de segmento y columna nueva | Los marts coinciden al centavo con un recálculo independiente; la segunda carga se omite |
| A4 · Chaos | `make chaos` y "El tablero no se actualizó hoy" | Tres intentos. En el primero, el agente pasó el cuerpo del pull request entre comillas y la terminal ejecutó lo que estaba entre backticks; desde entonces el cuerpo se escribe en un archivo y `opencode.json` niega cualquier comando con sustitución. En el segundo relajó el casteo y no midió el impacto; moví esas reglas a la skill de diagnóstico. El tercero pasó con ajustes menores |
| A5 · Fuente nueva | Tabla nunca vista (`fle_incidencia`) y solicitud de un tablero | Primer intento, 12 minutos: staging con CDC, gold con `NO_IDENTIFICADO`, mart con contrato y test de negocio. Los totales coinciden exactamente; 57 de 62 combinaciones son idénticas al recálculo. Las 5 restantes son fechas centinela que el agente reasignó con un supuesto declarado. El test de negocio falla al modificar el join |
| Frontera en GitHub | Workflow destructivo y pull request que modifica un mart | Ambos quedaron en espera hasta la aprobación del revisor |
| Ensayo como usuario nuevo | Clon limpio en una terminal sin configuración previa (`HOME` vacío, sin entorno de Python activo, sin dbt global ni sesión de GitHub), siguiendo solo el README; luego perfil, full-refresh, un script propio y chaos con el agente | `make run` dos veces con conteos idénticos. El agente no pudo crear `scripts/resumen.py` (permiso negado) y respondió con `query.py`; resolvió el full-refresh con `make build`. En el chaos encontró la causa y validó el fix, aunque hizo commit antes de validar. El ensayo destapó dos supuestos de mi máquina: Python 3.10+ (macOS trae 3.9) y que las instrucciones decían `python`, que en una máquina nueva no existe; ahora usan `.venv/bin/python` |
| Segundo ensayo como usuario nuevo | Mismo procedimiento, con la terminal de macOS en lugar de la de VS Code | Aviso de Python 3.10 y `make run` dos veces correctos. El agente usó `.venv/bin/python scripts/query.py` sin ayuda y encontró las fechas `dd/mm/aaaa`. Destapó que el modelo escribe rutas absolutas y una vez copió mal la ruta del proyecto, lo que hizo que opencode pidiera permiso para una "carpeta externa"; ahora `external_directory` se niega sin preguntar y `AGENTS.md` pide rutas relativas |
| Tercer ensayo como usuario nuevo | Las cuatro solicitudes anteriores (perfil, full-refresh, script propio y chaos) con todo lo corregido | Las cuatro pasaron. Al negarle el script, el agente intentó `python3 -c` contra la base y también se le negó (`*.duckdb*`), sin preguntar a la persona. En el chaos validó con `make build` y `make diagnose` antes del commit, en unos 7 minutos. El único aviso fue `gh auth status` tras el `push` fallido; ahora está permitido porque solo consulta la sesión |

Herramientas de prueba: `scripts/simular_entrega.py` genera entregas incrementales y `scripts/chaos.py` inyecta defectos del origen. Las construí para validar el pipeline, no forman parte del estándar que se aplica a una fuente nueva. El simulador parte de `carga_1` con cambios fijos para que sus resultados sean verificables. Ambas herramientas trabajan únicamente sobre la base de pruebas y escriben en carpetas excluidas de git.

## 8. Alcance no cubierto

- Servidor MCP propio. Los scripts con salida JSON y los permisos explícitos en `opencode.json` ofrecen las mismas herramientas con menos componentes. Sería lo primero que agregaría si las herramientas tuvieran que compartirse entre agentes distintos.
- Modelos incrementales. Gold y los marts se materializan como `table`: con el volumen del reto, reconstruir resulta más económico que mantener lógica incremental. En BigQuery la decisión sería distinta (ver `PROPUESTA.md`).
- Región y básculas, que el requerimiento deja fuera de alcance.
- Cuarentena de filas inválidas. El casteo estricto en staging detiene el build con una sola fila mala; los marts conservan su última versión correcta, pero no se actualizan hasta corregir. Con más fuentes y consumidores, separaría las filas que no convierten en una tabla de cuarentena (o usaría `store_failures` de dbt) para que el resto siga fluyendo, con una alerta.
- Límites del modelo gratuito. Un modelo pequeño a veces elige mal un ejemplo (en A4 reportó cifras de un mes no afectado), plantea un supuesto discutible o se salta un paso de la skill (en el ensayo hizo commit antes de validar). También antepone a veces una nota en inglés sobre cómo va a responder; `AGENTS.md` le pide entregar solo la respuesta final, lo que lo reduce pero no lo garantiza. Además, el plan gratuito a veces responde "high demand" y cada paso puede tardar de 30 a 60 segundos. Lo compensé con herramientas y tests que no dependen de él, pero el criterio fino sigue requiriendo la revisión humana del pull request.
- Observaciones abiertas de la prueba A5 (fuente nueva). El resultado fue correcto, pero en la revisión del pull request identifiqué tres puntos de criterio:
  - para las incidencias sin fecha, el agente usó la fecha de registro en UTC sin convertirla a hora local, lo que puede asignar al mes siguiente los registros de las últimas horas del mes;
  - indicó que no había defectos que escalar al origen, aunque la fuente traía duplicados, códigos inconsistentes y viajes inexistentes que staging corrigió;
  - no agregó el test `relationships` hacia viajes, que alertaría si crece el número de incidencias sin viaje.

  Las documenté, pero no modifiqué la skill para no ajustarla a una sola prueba. Son candidatas a reglas explícitas en una siguiente iteración.
- Prueba en un fork limpio de otra cuenta. Probé la configuración en el repositorio original; el script no contiene datos fijos de la cuenta.

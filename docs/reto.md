# Reto — Líder técnico de Ingeniería de Datos · Grupo DEACERO

## Antes de empezar

- **Qué hay en esta carpeta:** este `README.md` (las instrucciones), `docs/` (la documentación del negocio y del sistema origen) y `data/replica/carga_1/` (los datos, en CSV).
- **Los datos son ficticios.** Se generaron para este reto: no corresponden a clientes, operaciones ni cifras reales.
- **Plazo: 10 días naturales**, contados a partir del día en que recibes este archivo. Es el tiempo máximo para enviar el link de tu repositorio. Dedicación esperada: alrededor de **30 a 40 horas**.
- **Qué necesitas:** una computadora con Python 3.9 o superior, Git y una cuenta de GitHub. Todo lo demás es gratis y se instala desde Python. GitHub Actions y los environments de GitHub son gratis en repositorios públicos. Para el LLM usa un plan gratuito, sin tarjeta.
- **Cómo entregas:** responde al correo con el que recibiste este archivo con el **link a tu repositorio público**. Solo el link: no adjuntes archivos.
- **No hay canal de dudas, a propósito.** Si algo es ambiguo, toma la decisión que te parezca más razonable, escríbela en una sección **Supuestos** de tu `README.md` y sigue adelante. Cómo resuelves la ambigüedad también es parte de la evaluación.

## El problema

Replicamos decenas de sistemas operativos a la nube. **Después de la réplica no hay un estándar de trabajo.** Cada persona modela, prueba y entrega como se le ocurre: unos deduplican el CDC y otros no, unos prueban y otros solo corren, unos documentan y otros no. El resultado son marts que cuadran "más o menos" y que nadie se atreve a certificar.

No buscamos a alguien que construya un mart más. Buscamos a alguien que haga que **todo el equipo construya marts bien, sin tener que saber cómo**.

## Lo que queremos

Crea, en un repositorio **público** de tu GitHub y con CI/CD, un **workspace agéntico de ingeniería de datos**. Es un agente, con el contexto, las skills, las herramientas (MCP) y las validaciones que tú decidas, que **sabe qué hacer y cómo hacerlo**. Una persona del equipo le pide: *"llega esta tabla replicada, el negocio necesita esto"*. El agente la lleva hasta un mart con calidad de producción siguiendo **tu** estándar, sin que esa persona le explique el cómo.

Usa el agente que quieras (opencode, Claude Code, Codex, Aider…) con un LLM **gratis** (Groq, Gemini, OpenRouter, un modelo local). La llave va por variable de entorno, porque nosotros lo vamos a correr con la nuestra. Indica en el README qué proveedor y modelo usaste: los planes gratuitos tienen límites de uso, y tu diseño tiene que funcionar dentro de ellos.

**La idea de fondo: el agente opera el pipeline; tú no lo corres a mano.** Como mínimo debe poder:

- ingerir una entrega nueva de la réplica;
- correr dbt;
- perfilar una tabla;
- diagnosticar una falla;
- abrir un PR con el fix.

## El material

En `data/replica/carga_1/` está la primera entrega de una réplica **Airbyte CDC** desde SQL Server: cinco tablas de fletes, clientes y plantas, todas en texto. Así nos llegan de verdad, con todo lo que eso implica. En `docs/` está lo que el negocio y los dueños del origen nos dieron: el requerimiento, un diccionario y nuestras convenciones de capas. Úsalos con el mismo criterio con que usarías documentación real.

El caso de ejemplo es el requerimiento de `docs/requerimiento-negocio.md`: dos marts que Logística necesita para su tablero. Tu agente debe construirlos, y ese resultado es la **evidencia de que tu estándar funciona**. El producto que evaluamos es el estándar.

Todo corre local con dbt sobre DuckDB. En producción el destino es BigQuery: diséñalo pensando en eso.

## Las reglas duras

- **Las entregas de la réplica se acumulan.** Cada una trae registros nuevos y cambios a los anteriores. Ingerir la misma entrega dos veces, o correr todo dos veces seguidas, **no duplica nada**.
- **Cualquier cosa destructiva pasa por aprobación humana** en un *environment* de GitHub. Eso incluye full-refresh, borrar o recrear tablas publicadas fuera de la corrida normal del pipeline y cambiar el contrato de un mart, que rompe los tableros. Funciona como un 2FA: el agente propone la operación y explica su impacto, pero no la ejecuta. **Si el agente puede tirar tablas solo, no cuenta.** Tú decides dónde está la frontera, y queremos saber por qué la pusiste ahí.
- **Los marts publicados tienen contrato:** tipos y grano. Nadie los rompe sin aprobación.
- **Al menos dos tests que atrapen una regla de negocio real** del requerimiento, no solo `unique` y `not_null`. Si un test nunca podría fallar, no cuenta.
- **Cero secretos en el repo. Cero costo:** free tier, sin tarjeta.
- Déjanos un **`make chaos`** que rompa algo a propósito y demuestre que tu agente lo detecta, lo explica y lo arregla.

## Cómo lo vamos a evaluar

No vamos a leer tu código primero. Vamos a **usar tu agente**, con nuestra llave y sin hablar contigo:

1. Clonamos, seguimos tu README y corremos todo **dos veces**. Contamos filas.
2. Le damos **nuevas entregas de la réplica**, con lo que traen las réplicas reales. Vemos si los marts siguen correctos.
3. Corremos **nuestro propio chaos**, distinto al tuyo. Queremos que el agente nos diga el **mecanismo** de la falla, no que nos repita el stack trace, y que proponga el fix como PR.
4. Le pedimos **una fuente que nunca viste y un requerimiento nuevo**, sin explicarle nada más de lo que le explicaría una persona del equipo. Aquí se ve si hiciste un estándar o si solo resolviste este dataset.
5. Intentamos que haga algo destructivo sin aprobación.

Después sí leemos: dónde pusiste la frontera humana y por qué, qué decidiste que va como contexto, qué como skill y qué como validación que no dependa de que el agente "se acuerde", y qué problemas de los datos encontraste que nadie te dijo.

## Además: proponer y gestionar

Un líder técnico no solo construye el estándar: lo lleva al equipo. Agrega a tu repositorio:

- **`PROPUESTA.md`**: cómo adoptarías este estándar en un equipo de 6 personas que mantiene decenas de fuentes replicadas. Qué estandarizas primero y por qué, un plan por fases para los primeros 90 días, cómo sabrías que funciona (métricas que se puedan medir) y cómo cambia el diseño en BigQuery con cientos de millones de filas, incluido el costo.
- **Decisiones (ADR)** para las 3 a 5 decisiones más importantes que tomaste: contexto, alternativas, decisión y consecuencias.

Después de evaluar tu entrega tendremos una **sesión en vivo de 90 minutos**: presentas tu propuesta, resolvemos juntos una situación del día a día de un equipo de datos y defiendes tus decisiones. No necesitas preparar nada adicional.

## Entrega

- **Plazo: 10 días naturales** desde que recibiste este archivo.
- Un repositorio **público** en tu GitHub (el link se entrega como dice *Antes de empezar*). Si no te alcanza el tiempo, recorta alcance en vez de extenderlo.
- Un **`HALLAZGOS.md`** con los problemas que encontraste en los datos: qué viste, cómo lo detectaste, qué impacto tiene en el negocio, cómo lo resolviste y qué escalarías al dueño del origen.
- El historial de git cuenta.
- En el `README`: cómo correrlo, las decisiones que tomaste y **qué dejaste fuera y por qué**. Si tienes que recortar alcance, recórtalo y dilo: preferimos poco que funcione perfecto a mucho a medias.
- Lo vamos a evaluar en un **fork** de tu repo, con nuestras propias cuentas. Los environments, las reglas de protección y los secrets no se copian en un fork, así que la configuración de tu frontera de aprobación tiene que ser **reproducible**: un script o pasos claros en el `README`.
- Usa IA todo lo que quieras. En la revisión vas a defender cada decisión.


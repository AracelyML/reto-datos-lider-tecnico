# ADR 003 · Frontera humana para operaciones destructivas

- **Estado:** aceptada
- **Fecha:** 2026-10-28

## Contexto

El agente opera el pipeline sin que nadie le explique el cómo: ingiere entregas, corre dbt, diagnostica fallas y abre PRs. Algunas operaciones no se deshacen con otra corrida: un full-refresh recrea tablas publicadas, reiniciar landing borra la historia de versiones y cambiar el contrato de un mart rompe los tableros que lo consumen. El requisito es que el agente pueda proponerlas y explicar su impacto, pero no ejecutarlas sin aprobación humana, y que la configuración sea reproducible en un fork.

## Dónde está la frontera

| El agente puede solo | Requiere aprobación humana |
|---|---|
| Ingerir entregas, `dbt build` normal, perfilar, correr tests | `full-refresh` |
| Crear ramas, commits y abrir PRs | Reiniciar landing y el manifiesto de ingesta |
| Solicitar una operación destructiva (queda en pausa) | Cambiar el contrato de un mart o los propios controles |
| — | Merge a `main` |

**Por qué ahí:** lo que el pipeline hace en una corrida normal es idempotente y reversible; correrlo dos veces no cambia nada, así que pedir aprobación solo agregaría fricción y entrenaría a aprobar sin leer. Lo que borra historia o cambia lo que ven los consumidores no se arregla con otra corrida. La aprobación se reserva para lo irreversible, y por eso se toma en serio.

## Decisión

Tres capas independientes. Ninguna depende de que el agente "se acuerde" de una instrucción.

1. **Permisos del agente** (`opencode.json`): lista de comandos permitidos para la operación normal, confirmación para lo desconocido y denegación explícita de `--full-refresh`, `dbt run-operation`, `drop`/`truncate`, `rm`, el archivo de base de datos, `gh pr merge`, `gh api`, push a `main` o forzado, y edición de `.github/`, `opencode.json`, la guardia, `scripts/` y cualquier archivo `.py`. Solo se permiten los cuatro scripts que el agente necesita, por nombre exacto (`query.py`, `profile_table.py`, `diagnose.py`, `ingest.py`), para que no pueda escribir un script propio y ejecutarlo. El acceso a carpetas fuera del proyecto (`external_directory`) se niega sin preguntar: en un ensayo, el agente escribió mal una ruta absoluta y opencode pidió permiso a la persona en medio de la tarea; negado, el agente reintenta con la ruta relativa sin interrumpir.
2. **Guardia en dbt** (`macros/guardia_destructiva.sql`, `on-run-start`): un full-refresh aborta si no existe `APROBACION_DESTRUCTIVA=production`. Esa variable es una *variable del environment* `production` de GitHub: solo la recibe un job ya aprobado. `make reset-landing` lleva la misma guardia. Protege aunque se salte la capa 1 (otro agente, otra herramienta, una persona con prisa). No es un secreto: su valor está documentado. Su función es evitar un full-refresh por accidente, no detener a alguien que se lo proponga.
3. **GitHub** (`.github/workflows/`, `scripts/setup_github.sh`):
   - `destructive.yml`: el job `plan` muestra los modelos afectados y los conteos actuales; el job `ejecutar` espera la aprobación de un revisor en el environment `production`.
   - `frontera.yml`: si un PR toca `models/marts/`, `.github/`, la guardia, `dbt_project.yml`, `Makefile`, `opencode.json` o el script de setup, el check `aprobacion` espera al revisor del environment `contract-change`. Corre con `pull_request_target`, así que usa la versión de `main` del workflow: un PR no puede apagar su propio control. No hace checkout del código del PR; solo lee la lista de archivos por la API.
   - `main` protegida: solo por PR, checks `idempotencia`, `secretos` y `aprobacion` obligatorios, sin force push, también para administradores.

## Límite de la frontera local

Un agente que puede editar modelos y ejecutar dbt puede ejecutar SQL en la base local: basta un `pre_hook` en un modelo o una macro nueva. Los permisos revisan el texto del comando, no lo que hace el código que el agente escribió. Bloquear también eso exigiría quitarle al agente la capacidad de corregir modelos, que es su trabajo.

Por eso la frontera real no está en la máquina local:

- La base local es de **desarrollo**. Lo peor que puede pasar ahí es tener que reconstruirla con `make run` desde las entregas, que siguen en `data/replica/`.
- La escritura a **producción** solo ocurre en CI, en un job del environment `production` que espera la aprobación de un revisor. En BigQuery, la credencial de escritura a producción sería un *secret* de ese environment: sin aprobación, el job no la recibe y ningún código, del agente o de una persona, puede escribir en producción.
- Todo cambio de código llega a `main` por un pull request que revisa una persona.

En este reto, `destructive.yml` es una demostración de ese flujo de aprobación: el job aprobado reconstruye una base DuckDB en un runner desechable y no modifica ningún dato persistente.

## Alternativas consideradas

- **Solo instrucciones en el prompt del agente.** Descartada: depende de que el modelo obedezca; un prompt mal escrito o un modelo distinto la rompe.
- **Solo permisos del agente.** Descartada como única capa: no protege contra otra herramienta ni contra una persona.
- **Aprobación para todo.** Descartada: convierte la aprobación en un clic automático y pierde valor como control.
- **`pull_request` en vez de `pull_request_target` para el guard de contrato.** Descartada: el PR podría modificar el workflow que lo revisa.

## Consecuencias

- Un fork queda protegido corriendo `bash scripts/setup_github.sh` una vez.
- Cambiar un mart, aunque sea su documentación, requiere un clic de aprobación. Es fricción aceptada: los marts son lo que ven los consumidores.
- En BigQuery, las credenciales de escritura a producción vivirían como *secrets* del environment `production`. Sin aprobación el job no las recibe: la frontera deja de depender de que el código se porte bien.
- Con un solo mantenedor, quien solicita y quien aprueba es la misma persona, y el agente usa la sesión de `gh` de esa persona. En un equipo, `REVISOR=<usuario> bash scripts/setup_github.sh` asigna como revisor a otra persona y activa `prevent_self_review`, de modo que quien lanza un workflow no puede aprobarlo.
- Una revisión externa del repositorio señaló que la primera versión de los permisos permitía editar cualquier archivo y ejecutar cualquier script de `scripts/`: el agente podía escribir un script propio y saltarse los patrones de denegación. Se corrigió permitiendo solo los scripts necesarios por nombre y negando la edición de `scripts/` y de archivos `.py`, y se documentó el límite anterior.

## Evidencia

- Local: full-refresh bloqueado sin variable y con valor incorrecto; permitido con aprobación. `reset-landing` bloqueado.
- GitHub: el workflow destructivo quedó en *Waiting for review* hasta la aprobación y después corrió el full-refresh; un PR que tocaba el contrato quedó bloqueado hasta aprobar `contract-change`.

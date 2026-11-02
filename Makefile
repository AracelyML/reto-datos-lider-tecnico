PYTHON ?= python3
PY := .venv/bin/python
DBT := .venv/bin/dbt --no-use-colors
export DBT_PROFILES_DIR := .

SELECT ?= marts

# Base de trabajo: la real, o la copia de pruebas mientras exista .sandbox.
DUCKDB_PATH ?= $(shell cat .sandbox 2>/dev/null || echo deacero.duckdb)
export DUCKDB_PATH

.PHONY: setup ingest build run counts diagnose profile agent full-refresh reset-landing sandbox simular chaos sandbox-fin

# dbt-core 1.12 requiere Python 3.10 o superior.
setup:
	@$(PYTHON) -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else "Se requiere Python 3.10 o superior (encontrado %d.%d). Usa: make setup PYTHON=python3.12" % sys.version_info[:2])'
	$(PYTHON) -m venv .venv
	$(PY) -m pip install -r requirements.txt

ingest:
	$(PY) scripts/ingest.py

build:
	$(DBT) build

run: ingest build counts

diagnose:
	@$(PY) scripts/diagnose.py $(if $(SELECT_DIAG),--select $(SELECT_DIAG))

profile:
	@$(PY) scripts/profile_table.py $(TABLE) --pk $(PK)

# El agente solo ve el contexto y las skills de este repo, no los de la máquina de quien lo corre.
agent:
	OPENCODE_DISABLE_CLAUDE_CODE=1 GOOGLE_GENERATIVE_AI_API_KEY="$${GOOGLE_GENERATIVE_AI_API_KEY:-$$GEMINI_API_KEY}" opencode

# Destructivos: solo corren con la variable que entrega el environment production aprobado.
full-refresh:
	$(DBT) build --full-refresh --select $(SELECT)

reset-landing:
	@test "$$APROBACION_DESTRUCTIVA" = production || { \
		echo "reset-landing bloqueado: borra landing y el manifiesto; requiere aprobación en el environment production."; exit 1; }
	$(PY) -c "import duckdb; c = duckdb.connect('$(DUCKDB_PATH)'); \
	[c.execute(f'drop schema {s} cascade') for (s,) in c.execute(\"select schema_name from information_schema.schemata where schema_name like 'landing%'\").fetchall()]"
	$(MAKE) run

# Copia desechable de la base para chaos y entregas simuladas; la real no se toca.
sandbox:
	@test ! -f .sandbox || { echo "Ya hay una base de pruebas activa ($$(cat .sandbox)). Termínala con: make sandbox-fin"; exit 1; }
	@test -f deacero.duckdb || { echo "No existe la base real: corre make run primero."; exit 1; }
	cp deacero.duckdb sandbox.duckdb
	@echo sandbox.duckdb > .sandbox
	@echo "Base de pruebas activa: sandbox.duckdb. Todo comando make y script trabaja sobre ella hasta make sandbox-fin."

simular:
	@test -f .sandbox || { echo "La entrega simulada solo se carga en la base de pruebas: corre make sandbox primero."; exit 1; }
	$(PY) scripts/simular_entrega.py
	$(PY) scripts/ingest.py data/simulada/carga_2
	$(DBT) build
	@$(MAKE) --no-print-directory counts

# Inyecta una entrega con un defecto del origen en la base de pruebas (la crea si no existe).
ESCENARIO ?= formato_fecha
chaos:
	@test -f .sandbox || $(MAKE) --no-print-directory sandbox
	@DUCKDB_PATH=$$(cat .sandbox) $(PY) scripts/chaos.py $(ESCENARIO)
	@DUCKDB_PATH=$$(cat .sandbox) $(DBT) build > logs/chaos_build.log 2>&1 \
		&& echo "El pipeline pasó: revisa el escenario." \
		|| echo "El pipeline ahora falla (detalle en logs/chaos_build.log). Abre el agente y pásale el pedido de arriba. Al terminar: make sandbox-fin"

sandbox-fin:
	rm -f sandbox.duckdb sandbox.duckdb.wal .sandbox
	@echo "Base de pruebas eliminada. De nuevo sobre deacero.duckdb."

counts:
	@echo "base: $(DUCKDB_PATH)"
	@$(PY) -c "import duckdb; c = duckdb.connect('$(DUCKDB_PATH)', read_only=True); \
	[print(f'{s}.{t}: {c.execute(f\"select count(*) from {s}.{t}\").fetchone()[0]}') \
	 for s, t in c.execute(\"select table_schema, table_name from information_schema.tables where table_schema not in ('information_schema','pg_catalog') order by 1, 2\").fetchall()]"

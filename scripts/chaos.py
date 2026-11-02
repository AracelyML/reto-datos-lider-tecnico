"""Chaos: inyecta en la base de pruebas una entrega con un defecto realista del origen.

Toma las filas más recientes (mayor LSN) de una tabla de la última entrega en data/replica, les crea una
versión nueva con el defecto y la ingiere. No usa llaves fijas: cada escenario es tabla + columna + transformación.

Uso:
    python scripts/chaos.py <escenario>      (solo con la base de pruebas activa: make sandbox)
"""
import argparse
import csv
import json
import sys
from datetime import datetime, timedelta
from pathlib import Path

import duckdb

from base import MARCA, REAL, ruta
from ingest import ingest

REPLICA = Path("data/replica")
SALIDA = Path("data/chaos")
FILAS = 5


def formato_dia_mes(fila, col):
    t = datetime.strptime(fila[col][:19], "%Y-%m-%d %H:%M:%S")
    fila[col] = t.strftime("%d/%m/%Y %H:%M:%S")


def renombrar(fila, col, nuevo="CostoFleteMXN"):
    fila[nuevo] = fila.pop(col)


def codigo_fuera_de_catalogo(fila, col, valor="EMB"):
    fila[col] = valor


ESCENARIOS = {
    "formato_fecha": {"tabla": "fle_viaje", "columna": "FechaCompromiso", "aplica": formato_dia_mes,
                      "pedido": "El tablero de logística no se actualizó hoy. Revisa qué pasa y propón el arreglo."},
    "columna_renombrada": {"tabla": "fle_viaje", "columna": "CostoFlete", "aplica": renombrar,
                           "pedido": "Llegó la entrega de hoy y algo falló al construir. Revisa qué pasa y propón el arreglo."},
    "codigo_nuevo": {"tabla": "fle_viaje", "columna": "Estatus", "aplica": codigo_fuera_de_catalogo,
                     "pedido": "La corrida de hoy terminó con errores en los viajes. ¿Qué pasó y qué hacemos?"},
}


def main(nombre):
    if not MARCA.exists() or ruta() == REAL:
        sys.exit("El chaos solo corre en la base de pruebas: make sandbox primero.")
    esc = ESCENARIOS[nombre]
    entrega = sorted(d for d in REPLICA.iterdir() if d.is_dir())[-1]
    with open(entrega / f"{esc['tabla']}.csv", newline="", encoding="utf-8") as f:
        filas = list(csv.DictReader(f))
    candidatas = [r for r in filas if r.get(esc["columna"]) and not r["_ab_cdc_deleted_at"]]
    elegidas = sorted(candidatas, key=lambda r: int(r["_ab_cdc_lsn"]))[-FILAS:]

    esquema = f"landing_{esc['tabla'].split('_')[0]}"
    con = duckdb.connect(ruta(), read_only=True)
    lsn, actualizado, extraido = con.execute(f"""select max(_ab_cdc_lsn::bigint), max(_ab_cdc_updated_at::timestamp),
        max(_airbyte_extracted_at::timestamp) from {esquema}.{esc['tabla']}
        where _entrega not in ({", ".join(f"'{e}'" for e in ESCENARIOS)})""").fetchone()
    con.close()

    nuevas = []
    for i, r in enumerate(elegidas, 1):
        r = dict(r)
        esc["aplica"](r, esc["columna"])
        r["_ab_cdc_lsn"] = str(lsn + i)
        r["_ab_cdc_updated_at"] = (actualizado + timedelta(minutes=i)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
        r["_airbyte_extracted_at"] = (extraido + timedelta(days=1)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
        nuevas.append(r)

    carpeta = SALIDA / nombre
    carpeta.mkdir(parents=True, exist_ok=True)
    with open(carpeta / f"{esc['tabla']}.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(nuevas[0].keys()))
        w.writeheader()
        w.writerows(nuevas)

    reporte = ingest([str(carpeta)], db=ruta())
    print(json.dumps({"escenario": nombre, "base": ruta(), "entrega": str(carpeta), "ingesta": reporte},
                     ensure_ascii=False, indent=1))
    print(f"\nPídele al agente (make agent): \"{esc['pedido']}\"")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("escenario", choices=sorted(ESCENARIOS))
    main(p.parse_args().escenario)

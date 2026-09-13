#!/usr/bin/env python3
"""Emite SQL transaccional para un banco desechable con esquema completo.

No conecta a ninguna base. El ejecutor debe comprobar que el destino es su
banco de pruebas, usar ON_ERROR_STOP y mantener el lote en una misma sesión.
Los oráculos proceden de las definiciones originales capturadas; sólo cambia
su nombre. Todo el ensayo termina en ROLLBACK.
"""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("caso", choices=("paridad", "cohorte"))
args = parser.parse_args()
scripts = Path(__file__).resolve().parent
repo = scripts.parents[2]
fuentes = json.loads((repo / "UX-UI-GERENCIA/citas-conexiones-2026-09-12/fuentes-servidor.json").read_text())
sql = ["begin;set local statement_timeout='300s';"]
for nombre in ("citas_episodios", "conversion_episodios", "citas_gerencia_consulta"):
    coincidencias = [f for f in fuentes if f["esquema"] == "private" and f["funcion"] == nombre]
    assert len(coincidencias) == 1, f"Oráculo ambiguo o ausente: {nombre}"
    original = coincidencias[0]["definicion"]
    cabecera = f"CREATE OR REPLACE FUNCTION private.{nombre}("
    assert original.startswith(cabecera), f"Cabecera inesperada: {nombre}"
    sql.append(original.replace(cabecera, f"CREATE OR REPLACE FUNCTION pg_temp.{nombre}_original(", 1).rstrip().rstrip(";") + ";")
archivo = "test-citas-nucleos-paridad.sql" if args.caso == "paridad" else "test-citas-nucleos-cohorte-remota.sql"
sql.extend([(scripts / archivo).read_text(), "rollback;"])
print("\n".join(sql))

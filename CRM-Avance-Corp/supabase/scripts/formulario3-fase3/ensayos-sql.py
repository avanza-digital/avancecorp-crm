#!/usr/bin/env python3
"""Repite los contratos sobre la rama autorizada, en transacciones con rollback."""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

REF = "bxkborlvpmuwttzjrjqn"
ROOT = Path(__file__).resolve().parent
SUITES = {
    "contrato": ("formulario3-fase1/contrato.sql", 36),
    "permisos": ("formulario3-fase1/permisos.sql", 18),
    "reingreso": ("formulario3-fase1/reingreso-ficha-viva.sql", 1),
    "cartera": ("formulario3-fase2/cartera.sql", 43),
}


def inline(path):
    sql = path.read_text()
    sql = re.sub(r"^\\ir (.+)$", lambda m: inline(path.parent / m[1].strip()), sql, flags=re.M)
    return sql.replace("\\set ON_ERROR_STOP on\n", "")


def compile_suite(name):
    relative, total = SUITES[name]
    sql = inline(ROOT.parent / relative).replace(":'corregido'", "'1'")
    sql = sql.replace("sdgqkuejylkeqabpplyk", REF)
    sql = sql.replace("current_database() not like 'formulario3_fase2_%'", "current_database() not like 'formulario3_fase2_%' and coalesce(current_setting('prueba.formulario3.branch',true),'')<>'" + REF + "'")
    assert len(re.findall(r"^begin;", sql, re.M)) == 1
    assert len(re.findall(r"^rollback;", sql, re.M)) == 1
    assert not re.search(r"^commit;", sql, re.M | re.I)
    sql = sql.replace("begin;", f"begin;\nselect set_config('prueba.formulario3.branch','{REF}',true);", 1)
    if name != "reingreso":
        sql = sql.replace("rollback;", f"do $total$ begin if (select count(*) from comprobaciones)<>{total} then raise exception 'Conteo de pruebas incorrecto'; end if; end; $total$;\nrollback;")
    return sql + f"\nselect 'PASS' as estado, {total} as comprobaciones, 'ROLLBACK' as persistencia;\n"


if __name__ == "__main__":
    names = sys.argv[1:] or list(SUITES)
    for name in names:
        sql = compile_suite(name)
        with tempfile.NamedTemporaryFile(mode="w", suffix=".sql", prefix="formulario3-fase3-") as f:
            f.write(sql)
            f.flush()
            out = ROOT / ("sql-" + name + ".log")
            with out.open("w") as log:
                p = subprocess.run(["supabase", "db", "query", "--linked", "--project-ref", REF, "--file", f.name, "--output", "json"], stdout=log, stderr=log)
        print(f"{name}: exit={p.returncode}; evidencia={out.name}", flush=True)
        if p.returncode:
            sys.exit(p.returncode)

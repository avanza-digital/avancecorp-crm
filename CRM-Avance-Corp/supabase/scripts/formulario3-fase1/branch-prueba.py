#!/usr/bin/env python3
"""Ensayos con rollback en la única branch autorizada de Formulario 3."""
from pathlib import Path
import subprocess
import sys
import tempfile

REF = "sdgqkuejylkeqabpplyk"
ROOT = Path(__file__).resolve().parent
ENSAYOS = {"contrato.sql": 36, "permisos.sql": 18, "reingreso-ficha-viva.sql": 1}

if len(sys.argv) != 3 or sys.argv[1] not in ENSAYOS:
    sys.exit("Uso: branch-prueba.py {contrato,permisos,reingreso-ficha-viva}.sql salida.json")

name = sys.argv[1]
sql = (ROOT / name).read_text()
sql = sql.replace("\\set ON_ERROR_STOP on\n", "")
sql = sql.replace("\\ir fixtures.sql", (ROOT / "fixtures.sql").read_text())
sql = sql.replace(":'corregido'", "'1'")
significant = "\n".join(line for line in sql.splitlines() if not line.lstrip().startswith("--"))
assert significant.lstrip().startswith("begin;") and sql.rstrip().endswith("rollback;")
assert "\\" not in sql.replace('"uno\\ndos"', '')
assert "\ncommit;" not in sql.lower()
sql = sql.replace("begin;", f"begin;\nselect set_config('prueba.formulario3.branch','{REF}',true);", 1)
# Comprobar el total antes del rollback: un PASS final no oculta una suite vacía.
if name != "reingreso-ficha-viva.sql":
    sql = sql.replace("rollback;", f"""do $total$
begin
  if (select count(*) from comprobaciones)<>{ENSAYOS[name]} then
    raise exception 'Número de comprobaciones inesperado';
  end if;
end;
$total$;
rollback;
""")
sql += f"\nselect 'PASS' as estado, {ENSAYOS[name]} as comprobaciones, 'ROLLBACK' as persistencia;\n"
with tempfile.NamedTemporaryFile(mode="w", suffix=".sql", prefix="formulario3-", delete=True) as source:
    source.write(sql)
    source.flush()
    args = ["supabase", "db", "query", "--linked", "--project-ref", REF,
            "--file", source.name, "--output", "json"]
    with Path(sys.argv[2]).open("w") as output:
        result = subprocess.run(args, stdout=output, stderr=output, check=False)
print(f"Branch {REF}: exit_code={result.returncode}; evidencia={sys.argv[2]}")
sys.exit(result.returncode)

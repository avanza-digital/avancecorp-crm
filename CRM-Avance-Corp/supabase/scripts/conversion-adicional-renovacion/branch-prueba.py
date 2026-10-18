#!/usr/bin/env python3
"""Ejecuta bancos con ROLLBACK solo en la branch aprobada, por Management API."""
from pathlib import Path
import subprocess
import sys
import tempfile

REF = "yeiwghzhcrvwfcybymxy"
ROOT = Path(__file__).resolve().parent

def expand(path):
    lines = []
    for line in path.read_text().splitlines():
        if line.startswith("\\ir "):
            target = (path.parent / line[4:]).resolve()
            assert ROOT.parent in target.parents
            lines.append(expand(target))
        elif not line.startswith("\\set "):
            lines.append(line)
    return "\n".join(lines)

if len(sys.argv) != 3:
    sys.exit("Uso: branch-prueba.py {prueba,historico,cierre,seguridad,guardas}.sql resultado.log")
path = (ROOT / sys.argv[1]).resolve()
assert path.parent == ROOT and path.name in {"prueba.sql", "cierre.sql", "seguridad.sql", "guardas.sql", "historico.sql"}
sql = expand(path)
assert sql.rstrip().endswith("rollback;") and "\ncommit;" not in sql.lower()
sql += "\nselect 'PASS' as estado, 'Rollback completado' as persistencia;\n"
with tempfile.NamedTemporaryFile(mode="w", suffix=".sql", prefix="conversion-adicional-", delete=True) as source:
    source.write(sql)
    source.flush()
    command = ["supabase", "db", "query", "--linked", "--project-ref", REF, "--file", source.name, "--output", "json"]
    with Path(sys.argv[2]).open("w") as output:
        result = subprocess.run(command, stdout=output, stderr=output, check=False)
print(f"Branch {REF}: exit_code={result.returncode}; evidencia={sys.argv[2]}")
sys.exit(result.returncode)

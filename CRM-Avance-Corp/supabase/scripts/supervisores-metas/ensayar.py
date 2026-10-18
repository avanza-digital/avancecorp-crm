"""Prueba SQL transaccional en el banco local exclusivo; jamás usa producción."""
from pathlib import Path
import subprocess
import sys

BASE = Path(__file__).resolve().parent
sql = "begin; set local statement_timeout='120s'; set local jit=off;\n"
sql += (BASE / 'semilla.sql').read_text()
migracion = (BASE.parent.parent / 'migrations/20261016162937_crm_supervisores_ventas_equipo.sql').read_text()
# La prueba abarca antes/después en UNA transacción, también la DDL se revierte.
migracion = migracion.replace('\nbegin;\n', '\n', 1).removesuffix('commit;\n')
reversa = (BASE / 'reversa.sql').read_text().replace('\nbegin;\n', '\n', 1).removesuffix('commit;\n')
sql += '\n' + (BASE / 'prueba.sql').read_text().replace('-- MIGRACION', migracion).replace('-- REVERSA', reversa).replace('-- REAPLICACION', migracion)
sql += '\nrollback;\n'
if '--sql' in sys.argv:
    print(sql)
    raise SystemExit(0)
resultado = subprocess.run(
    ['docker', 'exec', '-i', 'avancecorp-coordinacion-pg-actual', 'psql', '-X', '-qAt',
     '-U', 'postgres', '-d', 'supervisores_metas_20261016', '-v', 'ON_ERROR_STOP=1'],
    input=sql, text=True, capture_output=True,
)
if resultado.returncode == 0:
    print('\n'.join(linea for linea in resultado.stderr.splitlines() if 'PASS:' in linea))
else:
    print(resultado.stderr[-8000:])
    print(resultado.stdout[-1200:])
raise SystemExit(resultado.returncode)

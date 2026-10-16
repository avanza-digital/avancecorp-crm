"""Prueba transaccional en banco local exclusivo; nunca acepta producción."""
from pathlib import Path
import subprocess
import sys

BASE = Path(__file__).resolve().parent
MIGRACION = BASE.parent.parent / 'migrations/20261016183308_crm_supervisores_referidos_propios.sql'
def cuerpo(ruta):
    lineas = ruta.read_text().splitlines()
    assert lineas.count('begin;') == 1 and lineas.count('commit;') == 1
    return '\n'.join(l for l in lineas if l not in ('begin;', 'commit;'))

sql = "begin; set local role postgres; set local statement_timeout='120s'; set local jit=off; set local timezone='America/Lima';\n"
sql += (BASE / 'semilla.sql').read_text()
sql += (BASE / 'prueba.sql').read_text().replace('-- MIGRACION', cuerpo(MIGRACION)).replace('-- REVERSA', cuerpo(BASE / 'reversa.sql')).replace('-- REAPLICACION', cuerpo(MIGRACION))
sql += "\nrollback;\ndo $$ begin if exists(select 1 from crm.leads) or exists(select 1 from crm.equipo) then raise exception 'El banco no quedó vacío'; end if; end $$;\n"
if '--sql' in sys.argv:
    print(sql)
    raise SystemExit(0)
r = subprocess.run(['docker','exec','-i','avancecorp-coordinacion-pg-actual','psql','-X','-qAt',
    '-U','supabase_admin','-d','supervisores_referidos_20261016','-v','ON_ERROR_STOP=1','-f','-'],
    input=sql,text=True,capture_output=True)
print('\n'.join(l for l in r.stderr.splitlines() if 'PASS:' in l) if r.returncode == 0 else r.stderr[-10000:])
raise SystemExit(r.returncode)

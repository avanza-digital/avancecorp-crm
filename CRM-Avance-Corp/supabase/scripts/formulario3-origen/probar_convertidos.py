"""Reclasifica convertidos antes de B sin reescribir su inversión ni sus relojes."""
import re
import subprocess
import sys
from pathlib import Path
from fixture_legacy import conversiones_antes

DIR = Path(__file__).resolve().parent
BASE = sys.argv[1] if len(sys.argv) == 2 else ''
if not re.fullmatch(r'origen_f3_[a-z0-9_]+', BASE):
    raise SystemExit('Uso: probar_convertidos.py origen_f3_<copia_con_A>. Nunca producción.')
B = (DIR.parents[1] / 'migrations' / '20261015173031_crm_formulario3_origen_activacion.sql').read_text()
B = B.replace('begin isolation level read committed;', '').replace('\ncommit;', '')
sql = 'begin;\n' + (DIR / 'fixtures.sql').read_text() + '\n' + (DIR / 'antes_activacion.sql').read_text()
sql += '\n' + conversiones_antes() + """
create temporary table _acreditadas_legadas as
  select id,to_jsonb(a) fila from crm.conversion_acreditaciones a;
select pg_temp.exigir((select count(*)=3 and bool_and(origen='formulario')
  from crm.conversion_acreditaciones), 'fixture: tres inversiones acreditadas ANTES de B');
""" + B + """
select pg_temp.exigir((select count(*)=7 and bool_and(origen='formulario_3')
  from crm.leads where campania_origen='Formulario 3'), 'B reclasifica vivos y convertidos legados');
select private.conversion_sincronizar_lead(lead_id) from crm.conversion_acreditaciones;
select pg_temp.exigir((select count(*)=3 and bool_and(a.origen='formulario_3'
  and to_jsonb(a)-'origen'=f.fila-'origen') from crm.conversion_acreditaciones a
  join _acreditadas_legadas f on f.id=a.id),
  'sincronizar después de B conserva motivo, relojes, fuente, identidad y responsable');
select pg_temp.exigir((select sum(cierres)=3 and sum(aporte)=3
  from private.ranking_conversion_origen_mes(
    date_trunc('month',now() at time zone 'America/Lima') at time zone 'America/Lima',
    (date_trunc('month',now() at time zone 'America/Lima')+interval '1 month') at time zone 'America/Lima',
    date_trunc('month',now() at time zone 'America/Lima')::date,0.15)
  where origen='formulario_3'), 'ranking mueve los tres cierres a F3 con el mismo aporte');
rollback;
"""
cmd = ['docker','exec','-i','avancecorp-coordinacion-pg-actual','psql','-XqAt',
       '-U','supabase_admin','-d',BASE,'-v','ON_ERROR_STOP=1']
r = subprocess.run(cmd,input='set role postgres;\n'+sql.replace('reset role;','set local role postgres;'),
                   text=True,capture_output=True)
if r.returncode:
    raise SystemExit(r.stderr+r.stdout)
print(r.stderr.strip())
print('PASS: convertidos antes de B y reintento posterior; transacción revertida')

#!/usr/bin/env python3
"""Gate oficial en la rama exclusiva. Nunca acepta otro destino ni imprime llaves."""
import json
import secrets
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlunsplit
from remoto import CFG, ENV, URI, sql

password_file = Path('/private/tmp/reasignacion-fixture-password.txt')
if not password_file.exists():
    password_file.write_text(secrets.token_urlsafe(24))
    password_file.chmod(0o600)
db_url = urlunsplit(URI._replace(netloc=f'{URI.username}:{URI.password}@{URI.hostname}:5432', query='sslmode=require'))
env = dict(ENV, PATH='/opt/homebrew/opt/postgresql@17/bin:'+ENV.get('PATH',''),
           SUPABASE_URL=CFG['SUPABASE_URL'], SUPABASE_ANON_KEY=CFG['SUPABASE_ANON_KEY'],
           SUPABASE_SERVICE_ROLE_KEY=CFG['SUPABASE_SERVICE_ROLE_KEY'],
           CRM_DEMO_PASSWORD=password_file.read_text(), CRM_BANCO_PSQL_URL=db_url)


def run(script, args=()):
    subprocess.run(['node', script, *args], env=env, check=True)


if sys.argv[1] == 'seed':
    sql('''begin;
      set local session_replication_role=replica;
      truncate crm.actividades,crm.tareas,crm.lead_asignaciones,crm.leads,
        crm.inversionistas,crm.cuentas_bancarias,public.contratos cascade;
      delete from crm.equipo;
      update public.perfiles set domicilio=null where rol='cliente';
      set local session_replication_role=origin;
      grant select on crm.periodos_cerrados to service_role;
      commit;''')
    try:
        run('supabase/scripts/seed-demo.mjs')
    finally:
        sql('revoke select on crm.periodos_cerrados from service_role;')
    sql('''begin;
      alter table crm.equipo disable trigger user;
      update crm.equipo set activo=false where perfil_id=(select id from public.perfiles where nombre_completo='ANALISTA INACTIVO');
      alter table crm.equipo enable trigger user;
      update public.perfiles set activo=false where nombre_completo='ANALISTA INACTIVO';
      commit;''')
    assert sql("select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('crm','private','public') and not t.tgisinternal and t.tgenabled='D';")[0].strip() == '0'
    assert sql("select has_table_privilege('service_role','crm.periodos_cerrados','select');")[0].strip() == 'f'
    print('SEED_OK: triggers y permisos restaurados antes de medir')
else:
    assert sys.argv[1] in ('contratos', 'identidad-d5')
    run('supabase/scripts/test-rls.mjs', ['--'+sys.argv[1]])

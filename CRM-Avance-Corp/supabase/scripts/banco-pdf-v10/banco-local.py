#!/usr/bin/env python3
"""Ensayo v10/reversa en PostgreSQL 17 efímero, sin red/puertos/volúmenes.
Usa formas versionadas del banco v9 (dos cuerpos privados suplentes).
No conecta a Supabase local compartido ni a producción.
"""
from pathlib import Path
import json
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
BANK = Path(__file__).resolve().parent
MIG = ROOT / 'supabase/migrations/20261010154908_crm_contrato_pdf_plantilla_v10_correcciones.sql'
REV = BANK / 'reversa.sql'
IMAGE = 'public.ecr.aws/supabase/postgres:17.6.1.167'
NAME = 'avancecorp-pdf-v10-' + uuid.uuid4().hex[:10]
CID = None
RESULTS = []


def run(args, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, **kwargs)


def sql(db, text, ok=True):
    r = run(['docker', 'exec', '-i', CID, 'psql', '-X', '-U', 'postgres', '-h', '/tmp',
             '-d', db, '-At', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose'], input=text)
    if ok and r.returncode:
        raise RuntimeError(r.stderr)
    return r


def query(db, text):
    return sql(db, text).stdout.strip()


def check(label, condition):
    RESULTS.append({'prueba': label, 'estado': 'PASS' if condition else 'FAIL'})
    print(('PASS ' if condition else 'FAIL ') + label, flush=True)
    if not condition:
        raise AssertionError(label)


def state(db):
    # Catálogo + TODAS las filas, no solo el número de registros.
    return query(db, """
    select jsonb_build_object(
      'jobs',(select jsonb_agg(to_jsonb(j) order by id) from private.contrato_pdf_jobs j),
      'pdfs',(select jsonb_agg(to_jsonb(p) order by id) from private.contrato_pdfs p),
      'constraints',(select jsonb_agg(pg_get_constraintdef(oid) order by conname) from pg_constraint where conrelid in ('private.contrato_pdf_jobs'::regclass,'private.contrato_pdfs'::regclass)),
      'trigger',(select tgenabled from pg_trigger where tgrelid='private.contrato_pdf_jobs'::regclass and tgname='contrato_pdf_jobs_transiciones_validas'),
      'default',(select column_default from information_schema.columns where table_schema='private' and table_name='contrato_pdf_jobs' and column_name='template_version'),
      'funciones',(select jsonb_agg(jsonb_build_array(p.oid,p.proowner,p.proacl,p.prosecdef,p.proconfig,p.provolatile,pg_get_functiondef(p.oid)) order by p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname in ('crear_job_contrato_pdf_base','crear_revision_contrato_pdf_base'))
    );
    """)


def clone(name):
    sql('postgres', f'create database {name} template base;')
    return name


def denied(name, setup, needle, source=MIG):
    db = clone(name)
    if setup:
        sql(db, setup)
    before = state(db)
    r = sql(db, source.read_text(), ok=False)
    check(name + ': rechazo esperado', r.returncode != 0 and needle in r.stderr)
    check(name + ': transaccion sin cambios', state(db) == before)


try:
    r = run(['docker', 'run', '--rm', '-d', '--network', 'none', '--name', NAME,
             '--user', 'postgres', '--entrypoint', '/bin/bash', IMAGE, '-c',
             'initdb -D /tmp/pdf-v10-data -A trust >/tmp/pdf-v10-init.log && exec postgres -D /tmp/pdf-v10-data -k /tmp'])
    if r.returncode:
        raise RuntimeError(r.stderr)
    CID = r.stdout.strip()
    for _ in range(60):
        ready = run(['docker', 'exec', CID, 'pg_isready', '-h', '/tmp', '-U', 'postgres'])
        if ready.returncode == 0:
            break
        time.sleep(.5)
    else:
        raise RuntimeError('Postgres aislado no arranco')
    check('PostgreSQL 17 aislado', query('postgres', 'show server_version;').startswith('17.'))
    sql('postgres', 'create role anon; create role authenticated; create role service_role; create database base;')
    sql('base', (ROOT / 'supabase/scripts/banco-pdf-v9/00-siembra.sql').read_text())
    # El caso de bytes retenidos del banco anterior se conserva como bloqueado.
    sql('base', "update private.contrato_pdf_jobs set estado='integridad_bloqueada' where id='33333333-3333-4333-8333-333333333333';")
    sql('base', (ROOT / 'supabase/migrations/20260915005752_crm_contrato_pdf_plantilla_v9_cotitulares.sql').read_text())
    db = clone('feliz')
    before = json.loads(state(db))
    r = sql(db, MIG.read_text())
    check('ida completa', 'CONTRATO_PDF_V10_MIGRATION_OK' in r.stderr)
    after = json.loads(state(db))
    check('PDF sellados identicos (todas las columnas)', before['pdfs'] == after['pdfs'])
    check('snapshots identicos en todos los jobs', [(j['id'],j['snapshot']) for j in before['jobs']] == [(j['id'],j['snapshot']) for j in after['jobs']])
    check('solo reservas vacias migraron', all(a==b if a['estado'] not in ['pendiente','error_reintentable'] else b['template_version']=='contrato-aep-17-v10' for a,b in zip(before['jobs'],after['jobs'])))
    check('reservas migradas conservan todas las demas columnas', all(
      {k:v for k,v in a.items() if k not in ('template_version','actualizado_en')} ==
      {k:v for k,v in b.items() if k not in ('template_version','actualizado_en')}
      for a,b in zip(before['jobs'],after['jobs'])))
    check('cuerpos vivos solo cambian literal; atributos/OID/ACL intactos', all(a[:-1]==b[:-1] and a[-1].replace('contrato-aep-17-v9','contrato-aep-17-v10')==b[-1] for a,b in zip(before['funciones'],after['funciones'])))
    check('default v10 y trigger activo', after['default']=="'contrato-aep-17-v10'::text" and after['trigger']=='O')
    check('roles API sin ejecutar escritor privado', query(db,"select bool_and(not has_function_privilege(r, 'private.crear_job_contrato_pdf_base(uuid,uuid)', 'EXECUTE')) from unnest(array['anon','authenticated','service_role']) r;")=='t')
    bad = sql(db,"update private.contrato_pdf_jobs set template_version='contrato-aep-17-v99' where id='11111111-1111-4111-8111-111111111111';",False)
    check('version desconocida rechazada por CHECK', '23514' in bad.stderr)
    # Nuevos PDF v10 emitidos deben sobrevivir al rollback, además de los viejos.
    sql(db,"""insert into private.contrato_pdfs (contrato_id,job_id,storage_path,nombre_archivo,sha256,bytes,template_version,snapshot,generado_por)
      values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/v2/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/contrato.pdf','Contrato-v10.pdf',repeat('d',64),12345,'contrato-aep-17-v10','{"cuenta":"0019100000000000"}','99999999-9999-4999-8999-999999999999');""")
    before_rollback = json.loads(state(db))
    r = sql(db, REV.read_text())
    rolled = json.loads(state(db))
    check('reversa completa', 'CONTRATO_PDF_V10_ROLLBACK_OK' in r.stderr)
    check('reversa conserva PDFs v10 y anteriores completos', before_rollback['pdfs']==rolled['pdfs'])
    check('reversa conserva CHECK v10', before_rollback['constraints']==rolled['constraints'])
    check('reversa restaura default/funciones exactos', rolled['default']==before['default'] and rolled['funciones']==before['funciones'])
    check('reversa conserva todos los snapshots', [(j['id'],j['snapshot']) for j in before_rollback['jobs']]==[(j['id'],j['snapshot']) for j in rolled['jobs']])
    for name, modification in [
      ('lease_vivo', "estado='procesando', lease_token=gen_random_uuid(), lease_expira_en=now()+interval '1 hour'"),
      ('lease_vencido', "estado='procesando', lease_token=gen_random_uuid(), lease_expira_en=now()-interval '1 hour'"),
      ('subido', "estado='subido_verificado', lease_token=gen_random_uuid(), lease_expira_en=now()-interval '1 hour', sha256=repeat('e',64), bytes=500, subido_en=now()"),
      ('reintento_con_bytes', "estado='error_reintentable', sha256=repeat('e',64), bytes=500, subido_en=now()"),
      ('antigua_pendiente', "template_version='contrato-aep-17-v8'")]:
        denied(name, f"update private.contrato_pdf_jobs set {modification} where id='11111111-1111-4111-8111-111111111111';", 'reservas incompatibles')
    denied('trigger_apagado','alter table private.contrato_pdf_jobs disable trigger contrato_pdf_jobs_transiciones_validas;', 'trigger de inmutabilidad')
    denied('intrusa_privada',"create function private.intrusa() returns text language sql as $$ select 'contrato-aep-17-v9'::text $$;",'las funciones que estampan')
    denied('intrusa_publica',"create function public.intrusa() returns text language sql as $$ select 'contrato-aep-17-v9'::text $$;",'fuera de private')
    denied('literal_duplicado',"create or replace function private.crear_job_contrato_pdf_base(p_contrato_id uuid,p_actor_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$ begin return jsonb_build_array('contrato-aep-17-v9','contrato-aep-17-v9'); end; $$;",'ocurrencias del literal')
    denied('fallo_update',"alter table private.contrato_pdf_jobs add constraint mutante check (template_version <> 'contrato-aep-17-v10');",'mutante')
    denied('reaplicar', MIG.read_text(), 'reservas incompatibles')
    denied('reversa_con_bytes', MIG.read_text()+"update private.contrato_pdf_jobs set estado='error_reintentable',sha256=repeat('e',64),bytes=500,subido_en=now() where id='11111111-1111-4111-8111-111111111111';", 'reservas incompatibles', REV)
    print(json.dumps({'estado':'PASS','pruebas':len(RESULTS),'imagen':IMAGE,'detalle':RESULTS}, ensure_ascii=False))
finally:
    # Solo se para el ID devuelto por docker run en ESTE proceso. --rm elimina
    # exclusivamente ese contenedor y sus datos efímeros; ningún volumen existe.
    if CID:
        cleanup = run(['docker','stop',CID])
        if cleanup.returncode:
            raise RuntimeError('No se pudo retirar el banco propio: '+cleanup.stderr)

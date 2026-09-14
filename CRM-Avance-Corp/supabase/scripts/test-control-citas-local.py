#!/usr/bin/env python3
"""Prueba el SQL candidato en PostgreSQL desechable, sin TCP ni datos reales."""
import concurrent.futures
import json
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
MIGRATION = HERE.parent / 'migrations/20260911212756_crm_control_citas_superadmin_borradores.sql'
APLICACION = HERE.parent / 'migrations/20260913225042_crm_citas_gestion_mensual_configurada.sql'
PG = Path('/opt/homebrew/opt/postgresql@17/bin')
BANK = Path(tempfile.mkdtemp(prefix='control-citas-', dir='/private/tmp'))
ARGS = ['-X', '-w', '-h', str(BANK), '-p', '55449', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-Atq']
LOG = []

def run(tool, args, sql=None, expected=None):
    result = subprocess.run([str(PG / tool), *args], input=sql, text=True, capture_output=True)
    LOG.append({'tool': tool, 'code': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr})
    if expected:
        assert result.returncode != 0 and expected in result.stderr, result.stderr
    else:
        assert result.returncode == 0, result.stderr
    return result.stdout.strip()

def query(sql, expected=None):
    return run('psql', ARGS, sql, expected)

def actor(n, role='authenticated'):
    uid = f'90000000-0000-4000-8000-{n:012d}' if n else ''
    return f"set request.jwt.claim.sub='{uid}'; set role {role};\n"

CONFIG = {
    'citas_por_lead': 1.25, 'entrevistas_porcentaje': 70, 'depositos_porcentaje': 70,
    'excluir_manuales_base': True, 'actividad_manuales': None, 'conteo_entrevistas': None,
    'base_avance': None, 'mes_resultado': None, 'analista_resultado': None, 'mes_inicio': None,
    'mostrar_meta_citas': False, 'base_depositos': None,
}

def save(version, config=CONFIG, nota='Prueba'):
    payload = json.dumps(config).replace("'", "''")
    return f"select crm.guardar_control_citas_fn({version},'{payload}'::jsonb,'{nota}');"

def read(n=1):
    return json.loads(query(actor(n) + 'select crm.control_citas_configuracion_fn();'))

started = False
try:
    run('initdb', ['-D', str(BANK / 'data'), '-U', 'postgres', '-A', 'trust', '--no-locale', '-E', 'UTF8'])
    run('pg_ctl', ['-D', str(BANK / 'data'), '-l', str(BANK / 'postgres.log'), '-o', f"-k {BANK} -p 55449 -c listen_addresses=''", '-w', 'start'])
    started = True
    assert query("select (inet_server_addr() is null and current_setting('listen_addresses')='')::text;") == 'true'
    query("""
      create role anon; create role authenticated; create role service_role;
      create schema crm; create schema private; create schema auth;
      create table crm.periodos_cerrados(periodo date primary key);
      grant usage on schema crm,auth,private to anon,authenticated;
      create function auth.uid() returns uuid language sql stable as
        $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
      create table public.perfiles(id uuid primary key, rol text, activo boolean);
      create table public.audit_log(tabla text, operacion text, fila_id uuid, usuario_id uuid, data_antes jsonb, data_despues jsonb);
      -- Definiciones de los dos helpers existentes, leídas en producción el 11/09.
      create function public.es_superadmin() returns boolean language sql stable security definer set search_path = public,pg_temp as $$
        select exists(select 1 from public.perfiles where id=auth.uid() and rol='superadmin' and activo=true);
      $$;
      create function private.log_audit_crm() returns trigger language plpgsql security definer set search_path = '' as $$
      declare v_fila uuid; v_actor uuid;
      begin
        begin
          v_fila := coalesce((pg_catalog.to_jsonb(coalesce(new,old))->>'id')::uuid,(pg_catalog.to_jsonb(coalesce(new,old))->>'perfil_id')::uuid);
        exception when invalid_text_representation then v_fila := null;
        end;
        select p.id into v_actor from public.perfiles p where p.id=(select auth.uid());
        insert into public.audit_log(tabla,operacion,fila_id,usuario_id,data_antes,data_despues)
        values(tg_table_schema||'.'||tg_table_name,tg_op,v_fila,v_actor,
          case when tg_op in ('UPDATE','DELETE') then pg_catalog.to_jsonb(old) end,
          case when tg_op in ('INSERT','UPDATE') then pg_catalog.to_jsonb(new) end);
        return coalesce(new,old);
      end $$;
      insert into public.perfiles select ('90000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,rol,n<>8
        from (values(1,'superadmin'),(2,'admin'),(3,'gerencia'),(4,'directorio'),(5,'analista'),(6,'supervisor'),(7,'cliente'),(8,'superadmin')) r(n,rol);
    """)
    helpers_before = query("select md5(pg_get_functiondef('public.es_superadmin()'::regprocedure)),md5(pg_get_functiondef('private.log_audit_crm()'::regprocedure));")
    query(MIGRATION.read_text())
    assert read() == {'version_actual': 0, 'ultimo': None, 'historial': []}
    for n in range(2, 9):
        query(actor(n) + 'select crm.control_citas_configuracion_fn();', 'Solo Superadmin')
        query(actor(n) + save(0), 'Solo Superadmin')
    query(actor(0) + save(0), 'Solo Superadmin')
    query(actor(1, 'anon') + 'select crm.control_citas_configuracion_fn();', 'permission denied')
    query(actor(1, 'anon') + save(0), 'permission denied')
    query(actor(1) + 'select * from crm.control_citas_versiones;', 'permission denied')
    query(actor(1) + 'select private.control_citas_config_valida(null);', 'permission denied')
    query(actor(1) + save(0))
    first = read()
    assert first['version_actual'] == 1 and first['ultimo']['configuracion'] == CONFIG
    assert first['ultimo']['estado'] == 'borrador'
    assert query("select count(*) from public.audit_log where tabla='crm.control_citas_versiones' and operacion='INSERT' and usuario_id='90000000-0000-4000-8000-000000000001' and fila_id is not null;") == '1'
    invalid = [None, {}, {**CONFIG, 'citas_por_lead': 0}, {**CONFIG, 'citas_por_lead': 1.251},
        {**CONFIG, 'depositos_porcentaje': 101}, {**CONFIG, 'mostrar_meta_citas': True},
        {**CONFIG, 'mes_inicio': '2026-13'}, {**CONFIG, 'mes_inicio': 202609},
        {**CONFIG, 'actividad_manuales': True}, {**CONFIG, 'base_depositos': 'citas'},
        {**CONFIG, 'campo_extra': 1}, {k:v for k,v in CONFIG.items() if k != 'actividad_manuales'}]
    for bad in invalid:
        query(actor(1) + save(1, bad), 'no válidos')
    query(actor(1) + save(1, nota='x' * 501), 'no válidos')
    query(actor(1) + save(0), 'otra sesión')
    assert read()['version_actual'] == 1
    query('update crm.control_citas_versiones set nota=\'alterada\';', 'historial de Citas no se modifica')
    query('delete from crm.control_citas_versiones;', 'historial de Citas no se modifica')
    query('truncate crm.control_citas_versiones;', 'historial de Citas no se modifica')
    # Política vigente del proyecto: desactivar conserva autoría; hard-delete no.
    query("delete from public.perfiles where id='90000000-0000-4000-8000-000000000001';", 'foreign key constraint')
    query("update public.perfiles set activo=false where id='90000000-0000-4000-8000-000000000001';")
    query(actor(1) + 'select crm.control_citas_configuracion_fn();', 'Solo Superadmin')
    assert query('select count(*) from crm.control_citas_versiones;') == '1'
    query("update public.perfiles set activo=true where id='90000000-0000-4000-8000-000000000001';")
    # Claims editables no sustituyen el rol almacenado en perfiles.
    query(actor(3) + "set request.jwt.claims='{\"user_metadata\":{\"role\":\"superadmin\"}}';" + save(1), 'Solo Superadmin')
    # Dos escritores parten de la misma revisión: uno guarda y el otro pierde el conflicto.
    def concurrent_save(value):
        return subprocess.run([str(PG / 'psql'), *ARGS], input=actor(1) + save(1, {**CONFIG, 'citas_por_lead': value}), text=True, capture_output=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(concurrent_save, [1.4, 1.5]))
    assert sorted(r.returncode for r in results) == [0, 3]
    assert any('otra sesión' in r.stderr for r in results)
    assert read()['version_actual'] == 2 and len(read()['historial']) == 2
    for version in range(2, 22):
        query(actor(1) + save(version))
    history = read()
    assert history['version_actual'] == 22 and len(history['historial']) == 20
    assert [r['version'] for r in history['historial']] == list(range(22, 2, -1))
    assert query('select count(*) from crm.control_citas_versiones;') == '22'
    assert query("select relrowsecurity from pg_class where oid='crm.control_citas_versiones'::regclass;") == 't'
    assert helpers_before == query("select md5(pg_get_functiondef('public.es_superadmin()'::regprocedure)),md5(pg_get_functiondef('private.log_audit_crm()'::regprocedure));")
    # Aplicación explícita: guardar sigue sin afectar al tablero.
    query(APLICACION.read_text())
    assert read()['aplicaciones'] == []
    for n in range(2, 9):
        query(actor(n) + 'select crm.aplicar_control_citas_fn(22);', 'Solo Superadmin')
    query(actor(0) + 'select crm.aplicar_control_citas_fn(22);', 'Solo Superadmin')
    query(actor(1, 'anon') + 'select crm.aplicar_control_citas_fn(22);', 'permission denied')
    query(actor(1) + 'select * from crm.control_citas_aplicaciones;', 'permission denied')
    query(actor(1) + "select private.control_citas_vigente(current_date);", 'permission denied')
    query(actor(1) + 'select crm.aplicar_control_citas_fn(22);', 'Completa todas')
    mes = query("select to_char(now() at time zone 'America/Lima','YYYY-MM');")
    completa = {**CONFIG, 'excluir_manuales_base': False, 'actividad_manuales': 'incluir',
        'conteo_entrevistas': 'citas_realizadas', 'base_avance': 'actividad_real',
        'mes_resultado': 'evento', 'analista_resultado': 'evento', 'base_depositos': 'entrevistas', 'mes_inicio': mes}
    query(actor(1) + save(22, completa))
    assert json.loads(query('select private.control_citas_vigente(current_date);'))['version'] == 0
    query(actor(1) + 'select crm.aplicar_control_citas_fn(22);', 'otra sesión')
    query(actor(1) + 'select crm.aplicar_control_citas_fn(23);')
    assert json.loads(query('select private.control_citas_vigente(current_date);'))['configuracion'] == completa
    assert len(read()['aplicaciones']) == 1
    assert query("select count(*) from public.audit_log where tabla='crm.control_citas_aplicaciones' and operacion='INSERT';") == '1'
    query('update crm.control_citas_aplicaciones set mes_inicio=mes_inicio;', 'historial de Citas no se modifica')
    query('delete from crm.control_citas_aplicaciones;', 'historial de Citas no se modifica')
    query('truncate crm.control_citas_aplicaciones;', 'historial de Citas no se modifica')
    query(actor(1) + save(23, {**completa, 'citas_por_lead': 1.5}))
    assert json.loads(query('select private.control_citas_vigente(current_date);'))['version'] == 23
    query("insert into crm.periodos_cerrados values(date_trunc('month',current_date)::date);")
    query(actor(1) + 'select crm.aplicar_control_citas_fn(24);', 'El mes está sellado')
    anterior = query("select to_char(date_trunc('month',now() at time zone 'America/Lima')-interval '1 month','YYYY-MM');")
    query(actor(1) + save(24, {**completa, 'mes_inicio': anterior}))
    query(actor(1) + 'select crm.aplicar_control_citas_fn(25);', 'No se reescriben meses anteriores')
    assert json.loads(query('select private.control_citas_vigente(current_date);'))['version'] == 23
    evidence = {'resultado': 'PASS', 'banco': str(BANK), 'acl_ocho_perfiles': True, 'anon_y_sin_sesion_denegados': True,
        'tabla_y_helper_privados': True, 'validacion_json': True, 'auditoria_actor': True, 'historial_inmutable': True,
        'conflicto_concurrente': True, 'historial_20_conserva_22': True, 'helpers_previos_sin_cambios': True,
        'aplicacion_solo_superadmin': True, 'borrador_no_aplica': True, 'reglas_completas_y_version_actual': True,
        'aplicaciones_inmutables_y_auditadas': True, 'mes_anterior_denegado': True, 'mes_sellado_denegado': True,
        'limite': 'Banco mínimo aislado; no sustituye ensayo de migración en rama ni matriz RLS completa.'}
    output = HERE / 'control-citas-superadmin'
    output.mkdir(exist_ok=True)
    (output / 'resultado-local.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps(evidence))
finally:
    if started: run('pg_ctl', ['-D', str(BANK / 'data'), '-m', 'fast', '-w', 'stop'])
    (BANK / 'comandos.json').write_text(json.dumps(LOG, indent=2))

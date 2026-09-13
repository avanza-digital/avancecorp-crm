#!/usr/bin/env python3
"""Contrato de Citas en PG17 desechable, sin TCP, credenciales ni datos reales.

Prueba las funciones capturadas de negocio y la candidata exacta. El esquema
mínimo no sustituye al replay completo, al gate RLS ni a los advisors del branch.
"""
import json
from pathlib import Path
import subprocess
import tempfile
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
EVIDENCE = ROOT / 'UX-UI-GERENCIA/citas-conexiones-2026-09-12'
MIGRATION = HERE.parent / 'migrations/20260912151320_crm_citas_consulta_nucleos.sql'
PG = Path('/opt/homebrew/opt/postgresql@17/bin')
BANK = Path(tempfile.mkdtemp(prefix='citas-nucleos-', dir='/private/tmp'))
ARGS = ['-X', '-w', '-h', str(BANK), '-p', '55459', '-U', 'postgres',
        '-d', 'citas_integracion_20260908', '-v', 'ON_ERROR_STOP=1', '-Atq']
LOG = []


def run(tool, args, sql=None, expected=None):
    start = time.monotonic()
    result = subprocess.run([str(PG / tool), *args], input=sql, text=True, capture_output=True)
    LOG.append({'tool': tool, 'code': result.returncode, 'seconds': round(time.monotonic() - start, 3),
                'stdout': result.stdout.strip(), 'stderr': result.stderr.strip(), 'expected_error': expected})
    if expected:
        assert result.returncode != 0 and expected in result.stderr, result.stderr
    else:
        assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def query(sql, expected=None):
    return run('psql', ARGS, sql, expected)


sources = json.loads((EVIDENCE / 'fuentes-servidor.json').read_text())
original = next(s['definicion'] for s in sources if s['funcion'] == 'citas_gerencia_consulta')
candidate = MIGRATION.read_text()
fingerprint = "select md5(pg_get_functiondef('private.citas_gerencia_consulta(date,date)'::regprocedure));"
alias = original.replace('private.citas_gerencia_consulta(', 'private.citas_gerencia_anterior_prueba(', 1) + ';'
for core in ['citas_episodios', 'conversion_episodios']:
    definition = next(s['definicion'] for s in sources if s['funcion'] == core)
    alias += '\n' + definition.replace('private.' + core + '(', 'private.' + core + '_anterior_prueba(', 1) + ';'
comparator = """
create function private.comparar_citas_prueba(p_desde date,p_hasta date) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare actual jsonb; anterior jsonb; normalizado jsonb;
begin
  actual:=crm.citas_gerencia_consulta_fn(p_desde,p_hasta);
  anterior:=private.citas_gerencia_anterior_prueba(p_desde,p_hasta);
  normalizado:=jsonb_set(actual,'{citas}',coalesce((
    select jsonb_agg(c.valor-'estado_comercial' order by c.orden)
    from jsonb_array_elements(actual->'citas') with ordinality c(valor,orden)
  ),'[]'::jsonb));
  assert normalizado=anterior,'PARIDAD: cambió un campo del contrato anterior';
  assert not exists(select 1 from jsonb_array_elements(actual->'citas') c
    where c->>'estado_comercial' is null),'Falta un estado del núcleo';
  return actual;
end $$;
revoke all on function private.citas_gerencia_anterior_prueba(date,date),private.comparar_citas_prueba(date,date) from public;
grant execute on function private.citas_gerencia_anterior_prueba(date,date),private.comparar_citas_prueba(date,date) to authenticated;
"""
core_parity = """
do $$ declare ambito boolean; desde date; visibles uuid[]; seleccion uuid[]; begin
  select coalesce(array_agg(id),'{}'::uuid[]) into visibles from public.perfiles;
  for ambito in select unnest(array[true,false]) loop
    foreach desde in array array[null::date,date '2026-09-01'] loop
      assert not exists(
        with anterior as materialized(select * from private.conversion_episodios_anterior_prueba(
          '2020-01-01',now()+interval '1 year',desde,ambito,visibles,0.37)),
        actual as materialized(select * from private.conversion_episodios(
          '2020-01-01',now()+interval '1 year',desde,ambito,visibles,0.37))
        select * from ((table anterior except all table actual) union all (table actual except all table anterior)) diferencia
      ),'PARIDAD DEL NÚCLEO DE CONVERSIÓN: hechos, pesos, atribución o límites cambiaron';
    end loop;
  end loop;
  assert not exists(
    with anterior as materialized(select * from private.citas_episodios_anterior_prueba('2020-01-01',now()+interval '1 year',now())),
    actual as materialized(select * from private.citas_episodios('2020-01-01',now()+interval '1 year',now()))
    select * from ((table anterior except all table actual) union all (table actual except all table anterior)) diferencia
  ),'PARIDAD DEL NÚCLEO DE CITAS: cambió el contrato anterior';
  assert not exists(select 1 from private.citas_episodios('2020-01-01',now()+interval '1 year',now(),'{}'::uuid[])),
    'Una cohorte vacía no consulta todas las citas';
  assert not exists(select 1 from private.conversion_cierres('2020-01-01',now()+interval '1 year',null,true,'{}',1,'{}')),
    'Una cohorte vacía no consulta todos los cierres';
  assert not exists(select 1 from private.conversion_episodios('2020-01-01',now()+interval '1 year',null,false,'{}',1)),
    'Ámbito explícito vacío no accede a hechos de otros analistas';
  select coalesce(array_agg(id),'{}'::uuid[])||array['ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid]
    into seleccion from (select id from crm.leads order by id limit 3) elegidos;
  seleccion:=seleccion||array[seleccion[1],null::uuid];
  assert not exists(
    with esperado as materialized(select * from private.citas_episodios_anterior_prueba('2020-01-01',now()+interval '1 year',now()) where lead_id=any(seleccion)),
    actual as materialized(select * from private.citas_episodios('2020-01-01',now()+interval '1 year',now(),seleccion))
    select * from ((table esperado except all table actual) union all (table actual except all table esperado)) diferencia
  ),'La selección no vacía de Citas debe equivaler al filtro del núcleo original';
  assert not exists(
    with esperado as materialized(select * from private.conversion_episodios_anterior_prueba('2020-01-01',now()+interval '1 year',null,true,'{}',0.37)
      where tipo='cierre' and lead_id=any(seleccion)),
    actual as materialized(select * from private.conversion_cierres('2020-01-01',now()+interval '1 year',null,true,'{}',0.37,seleccion))
    select * from ((table esperado except all table actual) union all (table actual except all table esperado)) diferencia
  ),'La selección no vacía de cierres debe equivaler al filtro del núcleo original';
end $$;
"""

started = False
try:
    run('initdb', ['-D', str(BANK / 'data'), '-U', 'postgres', '-A', 'trust', '--no-locale', '-E', 'UTF8'])
    run('pg_ctl', ['-D', str(BANK / 'data'), '-l', str(BANK / 'postgres.log'), '-o',
                   f"-k {BANK} -p 55459 -c listen_addresses=''", '-w', 'start'])
    started = True
    run('createdb', ['-h', str(BANK), '-p', '55459', '-U', 'postgres', 'citas_integracion_20260908'])
    assert query("select (inet_server_addr() is null and current_setting('listen_addresses')='')::text;") == 'true'
    query((HERE / 'test-citas-nucleos-fixtures.sql').read_text())
    order = ['rol_crm', 'cierre_anulado', 'cierre_externo_anulado', 'citas_episodios', 'conversion_episodios',
             'citas_gerencia_consulta', 'citas_gerencia_consulta_fn', 'huella_exenciones_analitica_lc',
             'contadores_crudos_leads_citas', 'assert_analitica_leads_citas']
    for name in order:
        source = next(s for s in sources if s['funcion'] == name)
        query(source['definicion'] + ';')
    query("""
      revoke execute on all functions in schema private from public;
      revoke execute on function crm.citas_gerencia_consulta_fn(date,date) from public;
      grant execute on function crm.citas_gerencia_consulta_fn(date,date),private.citas_gerencia_consulta(date,date) to authenticated;
      insert into private.analitica_lc_sello(sello) values(private.huella_exenciones_analitica_lc());
    """)
    before = query(fingerprint)
    assert before == next(s['huella'] for s in sources if s['funcion'] == 'citas_gerencia_consulta')
    query(candidate.replace('commit;', "do $$ begin raise exception 'REVERSIÓN_FORZADA_CITAS'; end $$;\ncommit;"), 'REVERSIÓN_FORZADA_CITAS')
    assert query(fingerprint) == before, 'Un fallo tardío dejó el lector cambiado'
    for name in ['citas_episodios', 'conversion_episodios', 'assert_analitica_leads_citas']:
        expected = next(s['huella'] for s in sources if s['funcion'] == name)
        restored = query("select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace "
                         "where n.nspname='private' and p.proname='" + name + "';")
        assert restored == expected, 'Rollback incompleto en ' + name
    assert query("select to_regprocedure('private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])') is null;") == 't'
    assert query("select count(*) from private.analitica_leads_citas_exenciones where objeto='private.citas_gerencia_consulta(date,date)';") == '0'
    query(original.replace('declare\n', 'declare\n  -- deriva deliberada de prueba\n', 1) + ';')
    query(candidate, 'revisar la candidata')
    query(original + ';')
    query('grant execute on function private.citas_episodios(timestamptz,timestamptz,timestamptz) to authenticated;')
    query(candidate, 'ACL inesperado')
    query('revoke execute on function private.citas_episodios(timestamptz,timestamptz,timestamptz) from authenticated;')
    query(candidate)
    assert query(fingerprint) != before
    query("""
      do $$ begin
        assert exists(select 1 from private.contadores_crudos_leads_citas()
          where objeto='private.citas_gerencia_consulta(date,date)' and declarada and huella_ok),'Citas debe quedar registrada';
        assert exists(select 1 from private.contadores_crudos_leads_citas()
          where objeto='private.deuda_ajena_prueba()' and not declarada),'No ocultar deudas ajenas';
        assert (select tope=30 from private.analitica_leads_citas_tope),'No elevar el tope';
        assert not has_function_privilege('authenticated','private.citas_episodios(timestamptz,timestamptz,timestamptz)','execute'),'Núcleo privado';
        assert not has_function_privilege('authenticated','private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)','execute'),'Conversión privada';
      end $$;
    """)
    query('select private.assert_analitica_leads_citas();', 'private.deuda_ajena_prueba')
    for signature in [
        'private.citas_episodios(timestamptz,timestamptz,timestamptz,uuid[])',
        'private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])',
    ]:
        query('begin; grant execute on function ' + signature + ' to authenticated; '
              'select private.assert_analitica_leads_citas(); rollback;', 'EXECUTE fuera de postgres')
        assert query("select has_function_privilege('authenticated','" + signature + "','execute');") == 'f'
    query((HERE / 'test-citas-nucleos-gobernanza.sql').read_text())
    for name in ['test-citas-gerencia-consulta.sql', 'test-citas-deposito-conversion.sql',
                 'test-citas-nucleos-estados.sql', 'test-citas-nucleos-volumen.sql']:
        sql = (HERE / name).read_text()
        sql = sql.replace('begin;', 'begin;\n' + alias + '\n' + comparator, 1)
        sql = sql.replace('r:=crm.citas_gerencia_consulta_fn(', 'r:=private.comparar_citas_prueba(')
        sql = sql.replace('rollback;', 'reset role;\n' + core_parity + '\nrollback;')
        output = query(sql)
        if name == 'test-citas-nucleos-volumen.sql':
            measurement = next(json.loads(line) for line in output.splitlines() if line.startswith('{"banco"'))
            (EVIDENCE / 'planes-volumen-local.json').write_text(json.dumps(measurement, ensure_ascii=False, indent=2) + '\n')
        print(name + ': ' + output.splitlines()[-1], flush=True)
    query("set role anon; select crm.citas_gerencia_consulta_fn('2026-09-01','2026-09-30');", 'permission denied')
    query('set role authenticated; select * from crm.tareas;', 'permission denied')
    print('CITAS_NUCLEOS_LOCAL_OK: paridad, límites, roles, estados, cierres, reversión y censo.', flush=True)
finally:
    if started:
        run('pg_ctl', ['-D', str(BANK / 'data'), '-m', 'fast', '-w', 'stop'])
    (EVIDENCE / 'verificacion-sql-local.json').write_text(json.dumps({
        'bank': str(BANK), 'scope': 'PG17 local, esquema mínimo, funciones de negocio reales, Auth/pesos/atribución simulados',
        'steps': LOG,
    }, ensure_ascii=False, indent=2) + '\n')

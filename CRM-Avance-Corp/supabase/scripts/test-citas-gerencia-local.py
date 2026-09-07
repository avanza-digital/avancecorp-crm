#!/usr/bin/env python3
"""Banco aislado de Citas. Fuentes: JSON de pg_get_functiondef, sin credenciales.

Uso: python3 supabase/scripts/test-citas-gerencia-local.py FUENTES_JSON MIGRACION_SQL
No acepta conexiones externas. Conserva registros; siempre detiene su PostgreSQL.
"""
import json
from pathlib import Path
import subprocess
import sys
import tempfile


sources = json.loads(Path(sys.argv[1]).read_text())
migration = Path(sys.argv[2]).resolve()
here = Path(__file__).resolve().parent
pg_bin = Path(subprocess.check_output(['pg_config', '--bindir'], text=True).strip())
bank = Path(tempfile.mkdtemp(prefix='avancecorp-citas.', dir='/tmp'))
port = '55439'
connection = ['-X', '-w', '-h', str(bank), '-p', port, '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-A', '-t']
started = False
log = []


def run(tool, args, sql=None, expected_error=None):
    result = subprocess.run([str(pg_bin / tool), *args], input=sql, text=True, capture_output=True)
    log.append({'tool': tool, 'args': args, 'code': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr})
    if expected_error:
        assert result.returncode != 0 and expected_error in result.stderr, result.stderr
    else:
        assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def query(sql, expected_error=None):
    return run('psql', connection, sql, expected_error)


def payload(historical=False):
    end = "'2026-07-31'::date" if historical else "(now() at time zone 'America/Lima')::date"
    sql = "set test.uid='10000000-0000-4000-8000-000000000004';\n"
    sql += f"select crm.metricas_reuniones_fn('2026-07-01',{end});"
    return json.loads(query(sql).splitlines()[-1])


def existing_fields(value, reference):
    """Compara todos los campos previos, aunque su nombre sea nuevo en otro grupo."""
    if isinstance(reference, dict):
        return {k: existing_fields(value[k], v) for k, v in reference.items() if k != 'generado_en'}
    if isinstance(reference, list):
        assert len(value) == len(reference), 'Cambió la cantidad de grupos'
        return [existing_fields(v, r) for v, r in zip(value, reference)]
    return value


def assert_parity(value, reference):
    assert existing_fields(value, reference) == existing_fields(reference, reference), 'Se alteró una métrica previa'


try:
    run('initdb', ['-D', str(bank / 'data'), '-U', 'postgres', '-A', 'trust', '--no-locale', '-E', 'UTF8'])
    run('pg_ctl', ['-D', str(bank / 'data'), '-l', str(bank / 'postgres.log'), '-o', f"-k {bank} -p {port} -c listen_addresses=''", '-w', 'start'])
    started = True
    assert query("select (inet_server_addr() is null and current_setting('listen_addresses')='' and to_regnamespace('crm') is null)::text;") == 'true'
    query((here / 'test-citas-gerencia-fixtures.sql').read_text())
    # Capital/Auth/catálogo usan los dobles declarados; las rutas de citas y
    # conversión y el filtro de roles son las funciones reales capturadas.
    for name in ['conversion_episodios', 'citas_episodios', 'filtrar_desglose_sujetos_crm', 'metricas_reuniones_implementacion', 'metricas_reuniones_fn']:
        source = next(row for row in sources if row['funcion'] == name)
        signature = f"{source['esquema']}.{name}({source['argumentos']})"
        query(source['definicion'].rstrip().rstrip(';') + f';\nrevoke all on function {signature} from public,anon,authenticated;\ngrant execute on function {signature} to postgres;')
        if name == 'metricas_reuniones_fn':
            query(f'grant execute on function {signature} to authenticated;')
        actual = query(f"select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='{source['esquema']}' and p.proname='{name}';")
        assert actual == source['huella'], (name, actual, source['huella'])
    before = payload()
    historical_before = payload(True)
    query(migration.read_text())
    after = payload()
    assert_parity(after, before)
    r = after['resumen']
    assert (r['pactadas'], r['realizadas'], r['divisor_realizacion'], r['divisor_asistencia'], r['pct_realizacion'], r['pct_asistencia']) == (16, 8, 12, 9, 66.7, 88.9), r
    assert (r['programadas_futuras'], r['pendientes_cierre'], r['reprogramadas']) == (1, 1, 1), r
    assert (r['canceladas_sistema_vencidas'], r['reprogramadas_vencidas']) == (2, 1), r
    a = after['responsables']
    assert len(a) == 1, a
    assert (a[0]['pactadas'], a[0]['realizadas'], a[0]['divisor_realizacion'], a[0]['pct_realizacion']) == (15, 7, 10, 70.0), a
    assert (a[0]['canceladas_sistema_vencidas'], a[0]['canceladas_ajenas_vencidas'], a[0]['reprogramadas_vencidas'], a[0]['programadas_futuras']) == (2, 1, 1, 1), a
    c = after['conversion']
    assert (c['leads_reunidos'], c['clientes'], c['contratos'], c['leads_con_cierre_previo'], c['capital_pen'], c['capital_usd']) == (6, 2, 2, 2, 1000, 5000), c
    assert sum(x['leads_con_cierre_previo'] for x in after['modalidades']) == 2
    assert sum(x['leads_con_cierre_previo'] for x in after['origenes']) == 2
    historical = payload(True)
    assert_parity(historical, historical_before)
    assert historical['resumen']['pactadas'] == 15 and historical['resumen']['programadas_futuras'] == 0
    for role, actor in [('anon', '10000000-0000-4000-8000-000000000004'), ('authenticated', '10000000-0000-4000-8000-000000000001'), ('authenticated', '')]:
        query(f"set test.uid='{actor}'; set role {role}; select crm.metricas_reuniones_fn('2026-07-01','2026-07-31');", 'permission denied' if role == 'anon' else 'No autorizado')
    query("set test.uid='10000000-0000-4000-8000-000000000004'; set role authenticated; select private.metricas_reuniones_implementacion('2026-07-01','2026-07-31');", 'permission denied')
    query("set test.uid='10000000-0000-4000-8000-000000000004'; select crm.metricas_reuniones_fn('2026-07-02','2026-07-01');", 'Periodo invalido')
    query(migration.read_text(), 'El agregador de Citas cambió')
    query((here / 'rollback-citas-gerencia-bases-y-alcance.sql').read_text())
    assert_parity(payload(), before)
    query(migration.read_text())
    assert payload()['conversion']['leads_con_cierre_previo'] == 2
    (bank / 'antes.json').write_text(json.dumps(before, indent=2))
    (bank / 'despues.json').write_text(json.dumps(after, indent=2))
    print(json.dumps({'resultado': 'CITAS_GERENCIA_OK', 'banco': str(bank), 'paridad': True, 'bases': True, 'residual': True, 'cierres_previos': True, 'horizonte': True, 'ACL': True, 'rollback': True}))
finally:
    if started:
        run('pg_ctl', ['-D', str(bank / 'data'), '-m', 'fast', '-w', 'stop'])
    (bank / 'comandos.json').write_text(json.dumps(log, indent=2))

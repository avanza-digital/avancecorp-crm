"""A→B, regresión transaccional y reversión A. Solo una copia Docker exclusiva pre-A."""
import json
import re
import subprocess
import sys
from pathlib import Path

DIR = Path(__file__).resolve().parent
SOLO_B = len(sys.argv) == 3 and sys.argv[2] == '--solo-b'
BASE = sys.argv[1] if len(sys.argv) == 2 or SOLO_B else ''
if not re.fullmatch(r'origen_f3_[a-z0-9_]+', BASE):
    raise SystemExit('Uso: probar_local.py origen_f3_<copia_pre_A>. Nunca producción.')
CMD = ['docker', 'exec', '-i', 'avancecorp-coordinacion-pg-actual', 'psql', '-XqAt',
       '-U', 'postgres', '-d', BASE, '-v', 'ON_ERROR_STOP=1']
MIG = DIR.parents[1] / 'migrations'
A = (MIG / '20261015171407_crm_formulario3_origen_compatibilidad.sql').read_text()
B = (MIG / '20261015173031_crm_formulario3_origen_activacion.sql').read_text()
FIRMAS = re.findall(r"if md5\(pg_get_functiondef\('([^']+)'::regprocedure\)\)", A)
HELPERS = ['private.origen_turno_reparto(text)', 'private.origen_episodio_lead(text,text)',
           'private.datos_solicitud_comparables(jsonb)']
RECREADAS = ['crm.leads_por_repartir()', 'private.leads_por_repartir_implementacion()',
            'private.conversion_divisor_empresa_totales(date,date)', 'private.conversion_divisor_empresa(date,date)']

def sql(texto, fallo=False, objetos_storage=False):
    comando = CMD.copy()
    if objetos_storage:
        # El DDL sigue como postgres. El administrador local prepara Storage y
        # reproduce sus ACL de producción dentro de la transacción reversible.
        comando[comando.index('-U') + 1] = 'supabase_admin'
        texto = 'set role postgres;\n' + texto.replace('reset role;', 'set local role postgres;')
    r = subprocess.run(comando, input=texto, text=True, capture_output=True)
    if (r.returncode != 0) != fallo:
        raise SystemExit(r.stderr + r.stdout)
    if not fallo and r.stderr.strip():
        print(r.stderr.strip(), flush=True)
    return r.stdout.strip()

def literal(s):
    return 'null' if s is None else "'" + s.replace("'", "''") + "'"

def foto():
    return json.loads(sql("""select jsonb_object_agg(p.oid::regprocedure::text,
      jsonb_build_object('def',pg_get_functiondef(p.oid),'acl',p.proacl::text,
      'comment',obj_description(p.oid,'pg_proc'),'owner',pg_get_userbyid(p.proowner)))
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname in ('crm','private') and p.prokind='f';"""))

def conteos():
    return sql("""select jsonb_build_array((select count(*) from crm.leads),
      (select count(*) from crm.actividades),(select count(*) from crm.tareas),
      (select count(*) from crm.lead_asignaciones),(select count(*) from public.perfiles));""")

def acl_storage():
    return sql("""select jsonb_object_agg(c.relname,c.relacl::text)
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='storage' and c.relname in ('objects','buckets');""")

antes = foto()
datos = conteos()
storage_antes = acl_storage()

def matriz(prefijo=''):
    bloque_b = B.replace('begin isolation level read committed;', '').replace('\ncommit;', '')
    sql('begin;\n' + (DIR/'fixtures.sql').read_text()
        + ('\n' + (DIR/'foto_antes.sql').read_text() if prefijo else '')
        + '\n' + prefijo
        + '\n' + (DIR/'compatibilidad.sql').read_text()
        + '\n' + (DIR/'antes_activacion.sql').read_text() + '\n' + bloque_b
        + '\n' + (DIR/'despues_activacion.sql').read_text()
        + '\n' + (DIR/'reingresos.sql').read_text()
        + '\n' + (DIR/'conversiones.sql').read_text()
        + '\n' + (DIR/'foto_despues.sql').read_text() + '\nrollback;', objetos_storage=True)
    assert conteos() == datos
    assert acl_storage() == storage_antes

# La reversión se verifica por ROLLBACK real, incluidos cambios de DDL/censo.
# Nunca desactiva ni elude el trigger que protege las declaraciones del censo.
if SOLO_B:
    matriz()
    assert foto() == antes
    print('PASS: matriz B revisada sobre A aplicada; datos, funciones y ACL revertidos', flush=True)
    raise SystemExit(0)
matriz(A.replace('begin;', '').replace('\ncommit;', ''))
assert foto() == antes
print('PASS: ciclo transaccional A→B→ROLLBACK conserva datos, cuerpos, ACL y comentarios', flush=True)
sql(A)
despues = foto()
assert {k for k in set(antes) | set(despues) if antes.get(k) != despues.get(k)} == set(FIRMAS + HELPERS)
assert all(antes[f]['acl'] == despues[f]['acl'] and antes[f]['owner'] == despues[f]['owner'] for f in FIRMAS)
print('PASS: A aplicada; solo 22 contratos y tres helpers; ACL/owners conservados', flush=True)
matriz()
assert foto() == despues
print('PASS: B y matriz reejecutadas sobre A aplicada; fixtures revertidas', flush=True)
sql(A, fallo=True)
assert foto() == despues and conteos() == datos
print('PASS: preflight rechaza repetir A sin efectos parciales', flush=True)

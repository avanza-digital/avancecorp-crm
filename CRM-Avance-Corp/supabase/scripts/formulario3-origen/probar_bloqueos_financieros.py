"""Dos sesiones reales. Deja fixtures y B en una copia Docker exclusiva vacía."""
import json
import re
import subprocess
import sys
import time
from pathlib import Path
from fixture_legacy import conversiones_antes

DIR = Path(__file__).resolve().parent
BASE = sys.argv[1] if len(sys.argv) == 2 else ''
if not re.fullmatch(r'origen_f3_[a-z0-9_]+', BASE):
    raise SystemExit('Uso: probar_bloqueos_financieros.py origen_f3_<copia_vacia_con_A>. Nunca producción.')
CMD = ['docker','exec','-i','avancecorp-coordinacion-pg-actual','psql','-XqAt',
       '-U','supabase_admin','-d',BASE,'-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose']


def ejecutar(texto):
    return subprocess.run(CMD,input='set role postgres;\n'+texto.replace('reset role;','set local role postgres;'),
                          text=True,capture_output=True)


def sql(texto):
    r=ejecutar(texto)
    if r.returncode:
        raise SystemExit(r.stderr+r.stdout)
    return r.stdout.strip()


def estado():
    return json.loads(sql("""select jsonb_build_object(
      'leads',(select jsonb_agg(to_jsonb(l) order by id) from crm.leads l),
      'acreditaciones',(select jsonb_agg(to_jsonb(a) order by id) from crm.conversion_acreditaciones a),
      'trigger',md5(pg_get_functiondef('private.leads_before_insert()'::regprocedure)));"""))


if sql('select count(*) from crm.leads;') != '0':
    raise SystemExit('El banco debe estar vacío antes de preparar las fixtures')
sql('begin;\n'+(DIR/'fixtures.sql').read_text()+'\n'+(DIR/'antes_activacion.sql').read_text()
    +'\n'+conversiones_antes()+'\ncommit;')
B=(DIR.parents[1]/'migrations'/'20261015173031_crm_formulario3_origen_activacion.sql').read_text()
antes=estado()
casos=[
    ('mes', "select pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'),"
     "(date_trunc('month',now() at time zone 'America/Lima')::date-date '2000-01-01')::integer);",
     'F3-B: mes en uso'),
    ('acreditación', 'select id from crm.conversion_acreditaciones order by id limit 1 for update;', '55P03'),
]
for nombre,candado,error in casos:
    otro=subprocess.Popen(CMD,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
    try:
        otro.stdin.write("set role postgres; begin; "+candado+" select 'CANDADO_LISTO';\n")
        otro.stdin.flush()
        while True:
            linea=otro.stdout.readline()
            if not linea:
                raise RuntimeError(otro.stderr.read())
            if 'CANDADO_LISTO' in linea:
                break
        inicio=time.monotonic()
        r=ejecutar(B)
        duracion=time.monotonic()-inicio
        if r.returncode==0 or error not in r.stderr or duracion>3:
            raise RuntimeError(f'B no rechazó rápidamente el bloqueo {nombre}: {duracion:.2f}s\n{r.stderr}')
        assert estado()==antes
        # La sesión comercial sigue utilizable después del rechazo de B.
        otro.stdin.write("select 'ESCRITOR_CONSERVADO'; rollback;\n")
        otro.stdin.close()
        salida=otro.stdout.read()
        otro.wait(timeout=10)
        assert otro.returncode==0 and 'ESCRITOR_CONSERVADO' in salida
        print(f'PASS: {nombre} ocupado rechaza B en {duracion:.2f}s; estado y sesión comercial conservados',flush=True)
    finally:
        if otro.poll() is None:
            otro.terminate()
            otro.wait(timeout=10)
sql(B)
assert sql("select bool_and(origen='formulario_3') from crm.conversion_acreditaciones;")=='t'
print('PASS: reintento B después de liberar los candados, sin perder acreditaciones')

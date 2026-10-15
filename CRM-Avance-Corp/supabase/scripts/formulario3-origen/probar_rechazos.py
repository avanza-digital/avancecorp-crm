"""Comprueba abortos íntegros de B. Solo banco local exclusivo con A aplicada."""
import json
import re
import subprocess
import sys
from pathlib import Path
from fixture_legacy import conversiones_antes

DIR = Path(__file__).resolve().parent
BASE = sys.argv[1] if len(sys.argv) == 2 else ''
if not re.fullmatch(r'origen_f3_[a-z0-9_]+', BASE):
    raise SystemExit('Uso: probar_rechazos.py origen_f3_<copia_con_A>. Nunca producción.')
CMD = ['docker', 'exec', '-i', 'avancecorp-coordinacion-pg-actual', 'psql', '-XqAt',
       '-U', 'supabase_admin', '-d', BASE, '-v', 'ON_ERROR_STOP=1']
B = (DIR.parents[1] / 'migrations' / '20261015173031_crm_formulario3_origen_activacion.sql').read_text()
B = B.replace('begin isolation level read committed;', '').replace('\ncommit;', '')


def ejecutar(texto):
    return subprocess.run(CMD, input='set role postgres;\n' + texto.replace('reset role;', 'set local role postgres;'),
                          text=True, capture_output=True)


def estado():
    resultado = ejecutar("""select jsonb_build_object(
      'funciones',(select jsonb_object_agg(p.oid::regprocedure::text,
        jsonb_build_array(pg_get_functiondef(p.oid),p.proacl::text,p.proowner))
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where n.nspname in ('crm','private') and p.prokind='f'),
      'conteos',jsonb_build_array((select count(*) from crm.leads),
        (select count(*) from crm.lead_asignaciones),(select count(*) from public.perfiles),
        (select count(*) from crm.periodos_cerrados),(select count(*) from crm.inversion_solicitudes)),
      'storage',(select jsonb_object_agg(c.relname,c.relacl::text)
        from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname='storage' and c.relname in ('buckets','objects')));""")
    if resultado.returncode:
        raise SystemExit(resultado.stderr)
    return json.loads(resultado.stdout)


antes = estado()
fixture = (DIR / 'fixtures.sql').read_text() + '\n' + (DIR / 'antes_activacion.sql').read_text()
casos = [
    ('mes sellado', """insert into crm.periodos_cerrados(periodo,ponderacion_referido,meta_revision,cobertura)
      values(date_trunc('month',now() at time zone 'America/Lima')::date,0.15,1,'{}');""",
     'F3-B: la población ya pertenece a un mes sellado'),
    ('fecha de fuente incoherente', conversiones_antes() + """
      update crm.conversion_acreditaciones set fecha_comercial=fecha_comercial-1;""",
     'F3-B: cierre sin acreditación coherente de mes abierto'),
    ('identidad acreditada incoherente', conversiones_antes() + """
      update crm.conversion_acreditaciones set inversionista_id=null;""",
     'F3-B: cierre sin acreditación coherente de mes abierto'),
]
for nombre, alteracion, esperado in casos:
    r = ejecutar('begin;\n' + fixture + '\n' + alteracion + '\n' + B + '\nrollback;')
    if r.returncode == 0 or esperado not in r.stderr:
        raise SystemExit(f'FAIL: rechazo {nombre}\n{r.stderr}\n{r.stdout}')
    if estado() != antes:
        raise SystemExit(f'FAIL: quedaron efectos después del rechazo {nombre}')
    print(f'PASS: B rechaza {nombre}; datos, funciones y ACL sin efectos parciales', flush=True)

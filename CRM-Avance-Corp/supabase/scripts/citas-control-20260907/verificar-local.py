#!/usr/bin/env python3
"""Ensayo de la propuesta; SOLO admite el banco local aislado ya preparado.
Replica el cuerpo productivo y su declaración previa. No se conecta a producción.
"""
import json,hashlib,subprocess
from pathlib import Path

root=Path(__file__).resolve().parent
socket=Path('/private/tmp/sla-integracion-vtihsz8b')
assert (socket/'LOCAL-SLA-BANK').exists()
cmd=['/opt/homebrew/opt/postgresql@17/bin/psql','-X','-w','-h',str(socket),'-p','55485','-U','postgres','-d','citas_control_20260907','-At','-v','ON_ERROR_STOP=1']
def query(sql, expected=None):
 r=subprocess.run(cmd,input=sql,text=True,capture_output=True)
 if expected:
  assert r.returncode and expected in r.stderr, r.stderr
 else:
  assert r.returncode==0,r.stderr
 return r
assert query("select current_database()||':'||(inet_server_addr() is null)::text||':'||(current_setting('listen_addresses')='')::text;").stdout.strip()=='citas_control_20260907:true:true'
sql=(root/'correccion-propuesta.sql').read_text()
obj="private.metricas_reuniones_implementacion(date,date)"
reset=f"update private.analitica_leads_citas_exenciones set huella='48702e1a8028340b3a26137027182c98' where objeto='{obj}';update private.analitica_lc_sello set sello=private.huella_exenciones_analitica_lc() where id;"
snapshot="""select jsonb_build_object(
 'funciones',(select md5(string_agg(p.oid::text||pg_get_functiondef(p.oid)||coalesce(p.proacl::text,'')||p.proowner::text,chr(10) order by p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('crm','private','public') and p.prokind in ('f','p')),
 'leads',(select md5(coalesce(jsonb_agg(to_jsonb(t) order by id),'[]')::text) from crm.leads t),
 'tareas',(select md5(coalesce(jsonb_agg(to_jsonb(t) order by id),'[]')::text) from crm.tareas t),
 'actividades',(select md5(coalesce(jsonb_agg(to_jsonb(t) order by id),'[]')::text) from crm.actividades t),
 'otras_exenciones',(select md5(jsonb_agg(to_jsonb(e) order by objeto)::text) from private.analitica_leads_citas_exenciones e where objeto<>'private.metricas_reuniones_implementacion(date,date)'),
 'tope',(select to_jsonb(t) from private.analitica_leads_citas_tope t where id));"""
results=[]
query('begin;'+reset+'commit;')
before=query(snapshot).stdout.strip()
query('select private.assert_analitica_leads_citas();','Contadores exentos cuyo cuerpo CAMBIO')
results.append('Reproduce exactamente el rechazo inicial')
query(sql.replace('commit;','select 1/0;\ncommit;'),'division by zero')
query('select private.assert_analitica_leads_citas();','Contadores exentos cuyo cuerpo CAMBIO')
results.append('Error antes de commit revierte referencia y sello')
query("begin;update private.analitica_leads_citas_exenciones set razon='Cambio de declaración deliberado para el ensayo local; esta razón no ha sido revisada y debe ser rechazada por el sello.' where objeto='"+obj+"';commit;")
query(sql,'el sello previo no coincide')
reason=json.loads((root/'evidencia-produccion.json').read_text())['verificacion']['excepcion']['razon'].replace("'","''")
query("begin;update private.analitica_leads_citas_exenciones set razon='"+reason+"' where objeto='"+obj+"';commit;")
results.append('Bloquea una declaración alterada sin resellar')
query(sql)
after=query(snapshot).stdout.strip()
assert before==after,(before,after)
results.append('Cuerpos, permisos, leads, tareas, actividades, otras excepciones y tope idénticos')
query(sql,'el fallo ya cambio o existen otras inconsistencias')
results.append('Rechaza reaplicación')
repo=root.parents[2]
gates=query((repo/'supabase/scripts/trinquete-sla-produccion.sql').read_text())
assert 'OK: SLA completo' in gates.stdout
results.append('Siete controles y cierre de reconstrucción aprobados')
mutants=query((repo/'supabase/scripts/trinquete-analitica-lc-mutante.sql').read_text(),'MUTANTE_ANALITICA_CAZADO por los 10 filos')
results.append('Diez fallos simulados detectados y revertidos')
final=query('select private.assert_analitica_leads_citas();').stdout.strip()
assert final.startswith('OK:')
output={'resultado':'VERIFICADO_LOCALMENTE','sql_sha256':hashlib.sha256(sql.encode()).hexdigest(),'pruebas':results,'veredicto':final,'produccion_modificada':False,'banco':{'postgres':'17.10','tcp':False,'base':'citas_control_20260907','origen':'Copia del esquema integral con seis definiciones vigentes y la declaración de Citas capturadas de producción','limites':['30 contadores en banco frente a 29 en producción; ambos respetan tope 30','Metadata de nueve jobs apunta al nombre del banco; no hay scheduler ni HTTP administrado','La comparación de datos usa fixtures locales, no la cartera productiva']}}
(root/'resultado-local.json').write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(output,ensure_ascii=False))

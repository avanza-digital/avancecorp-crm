#!/usr/bin/env python3
"""Compara SQL publicado/candidato con una misma foto normalizada y un mismo reloj.
Solo socket del banco aislado. Los proveedores locales reproducen la foto capturada;
esto verifica decisiones, no autoridades (cubiertas por el banco de integración).
No escribe ni publica datos productivos. El reporte de salida no contiene IDs/PII.
"""
import argparse, collections, datetime as dt, hashlib, json, os, re, subprocess, uuid
from pathlib import Path
BASE=Path(__file__).resolve().parents[1]
PG=Path('/opt/homebrew/opt/postgresql@17/bin')
def q(v):return "'"+str(v).replace("'","''")+"'"
def body(path):return re.search(r'CREATE OR REPLACE FUNCTION private\.sla_operacion_leads\([\s\S]+?AS \$function\$[\s\S]+?\$function\$',path.read_text()).group(0)+';'
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--socket',type=Path,required=True);p.add_argument('--snapshot',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
socket=a.socket.resolve();assert str(socket).startswith('/private/tmp/sla-integracion-') and (socket/'LOCAL-SLA-BANK').exists()
s=json.loads(a.snapshot.read_text());assert s['fuente_md5']=='d880268ef586322e0589586cb8cde30d'
env={k:v for k,v in os.environ.items() if not k.startswith('PG')};env.update(PGHOST=str(socket),PGPORT='55485',PGUSER='postgres')
db='sla_contraste_'+uuid.uuid4().hex[:10]
def sql(text,dbase=db):
 r=subprocess.run([str(PG/'psql'),'-XqAt','-v','ON_ERROR_STOP=1','-d',dbase],env=env,input=text,text=True,capture_output=True,timeout=90)
 if r.returncode:raise RuntimeError(r.stderr)
 return r.stdout.strip()
sql('create database '+db+';','postgres')
try:
 sql('''create schema private; create schema crm; create schema prueba;
 create table prueba.foto (datos jsonb);
 create table crm.sla_operacion_control(id boolean,modo text,revision integer,cambiado_en timestamptz,cambiado_por uuid,politica_adopcion_id uuid,primera_activacion_en timestamptz);
 create table crm.sla_politica_etapas_operacion(politica_id uuid,etapa text,seguimiento_minutos integer,prorroga_minutos integer,prorroga_max integer,tope_extra_minutos integer,pausa_habilitada boolean,pausa_margen_minutos integer);
 create table crm.actividades(id uuid,lead_id uuid,tipo text,creado_en timestamptz,creado_por uuid);
 create index on crm.actividades(lead_id,creado_en desc,id desc);
 create table public.perfiles(id uuid,nombre_completo text);
 ''')
 sql('insert into prueba.foto values ('+q(json.dumps(s))+'::jsonb);'+''.join('insert into '+table+' select * from jsonb_populate_recordset(null::'+table+','+q(json.dumps(rows))+'::jsonb);' for table,rows in [('crm.sla_operacion_control',[s['control']]),('crm.sla_politica_etapas_operacion',s['reglas']),('crm.actividades',s['actividades'])]))
 for f in s['firmas']:
  name=f['nombre'];cols=f['result'][6:-1]
  if name in ('sla_hechos_actuales','sla_tareas_hechos'):
   key='hechos' if name=='sla_hechos_actuales' else 'tareas';owner='vendedor_id' if key=='hechos' else 'responsable_id'
   query="select r.* from prueba.foto f cross join lateral jsonb_to_recordset(f.datos->'"+key+"') r("+cols+") where (p_lead_ids is null or r.lead_id=any(p_lead_ids)) and (p_global or r."+owner+'=any(p_visibles))'
  elif name=='sla_etapa_hechos':query="select r.minutos,r.usadas,r.ingresos from prueba.foto f cross join lateral jsonb_to_recordset(f.datos->'etapas') r(lead_id uuid,"+cols+") where r.lead_id=p_lead_id"
  else:query="with vigente as (select r.id,r.version from prueba.foto f cross join lateral jsonb_to_recordset(f.datos->'politicas') r(id uuid,version integer,vigente_desde timestamptz) where r.vigente_desde<=p_ahora order by r.vigente_desde desc,r.version desc limit 1) select r.* from vigente r where not exists (select e.etapa from (values ('nuevo'),('contactado'),('reunion_agendada'),('propuesta_enviada')) e(etapa) except select e.etapa from crm.sla_politica_etapas_operacion e where e.politica_id=r.id)"
  sql('create function private.'+name+'('+f['args']+') returns '+f['result']+" language sql stable set search_path='' as $fixture$"+query+'$fixture$;')
 sql("create function private.persona_vetada(p_id uuid) returns boolean language sql stable set search_path='' as $$select r.vetado from prueba.foto f cross join lateral jsonb_to_recordset(f.datos->'vetos') r(lead_id uuid,vetado boolean) where r.lead_id=p_id$$;")
 outputs=[]
 for path in [BASE/'scripts/rollback-sla-accion-rol.sql',BASE/'migrations/20260907212612_crm_sla_avisos_por_accion_y_rol.sql']:
  sql(body(path));outputs.append(json.loads(sql("select jsonb_agg(to_jsonb(s) order by s.lead_id) from private.sla_operacion_leads(null,true,'{}',"+q(s['calculado_en'])+") s;")))
 old,new=outputs;assert len(old)==len(new)==len(s['hechos']);facts={f['lead_id']:f for f in s['hechos']}
 transitions=collections.Counter();deltas=collections.Counter();causes=collections.Counter();loss=[]
 for b,c in zip(old,new):
  assert b['lead_id']==c['lead_id'];f=facts[c['lead_id']]
  for key in ('base','compromiso','etapa','seguimiento'):assert b['estado'][key]==c['estado'][key],key
  assert b['senales']['revisiones']==c['senales']['revisiones']
  if b['senales']['tareas_vencidas'] and not c['senales']['tareas_vencidas']:
   assert c['estado']['evaluacion']=='parcial';causes['tarea_incoherente_pasa_a_revision_datos']+=1
  if c['senales']['primera_atencion']:assert f['base']['asignacion_primera_gestion_en'] is None and f['asignacion_coherente']
  if b['senales']['primera_atencion'] and not c['senales']['primera_atencion']:
   assert f['base']['asignacion_primera_gestion_en'] is not None or c['estado']['evaluacion']=='parcial' or f['base']['asignacion_primera_gestion_limite_en']>s['calculado_en']
   causes['sale_de_primera_por_gestion_o_asignacion_actual']+=1
  oldaction=(b['accion_atencion'] or {}).get('bucket','ninguna');newaction=(c['accion_atencion'] or {}).get('bucket','ninguna')
  if oldaction!=newaction:
   transitions[oldaction+' → '+newaction]+=1
   if newaction=='proxima_tarea':
    assert f['base']['asignacion_primera_gestion_en'] is not None
    assert not c['senales']['seguimientos_pendientes'] and not c['senales']['primera_atencion']
    assert c['estado']['operacion']['proxima_accion']['vence_en']>s['calculado_en']
   elif newaction=='tarea_vencida':assert c['senales']['tareas_vencidas'] and c['accion_atencion']['tarea_id'] is not None
   elif newaction=='seguimiento':assert c['senales']['seguimientos_pendientes'] and not c['senales']['primera_atencion']
   elif newaction=='datos_incompletos':assert c['estado']['evaluacion']=='parcial'
   else:raise AssertionError('Transición sin explicar: '+oldaction+' → '+newaction)
  for flag,value in c['senales'].items():deltas[flag]+=int(value)-int(b['senales'][flag])
 def counts(rows,supervision):
  avisos=[[a for a in r['estado']['avisos'] if supervision or not a['solo_supervision']] for r in rows]
  causes=collections.Counter(a['bucket'] for aa in avisos for a in aa)
  return {'oportunidades':sum(bool(aa) for aa in avisos),'causas':dict(sorted(causes.items()))}
 patterns=[]
 for ident,label in [('e20ae6c0-3bc8-414e-9238-6d99f7c40283','Tarea futura con etapa agotada'),('75de7405-997b-4f5b-a6b1-fe3d4c054a17','Tarea futura dentro del plazo')]:
  row=next(r for r in new if r['lead_id']==ident)
  patterns.append({'patron':label,'primera_gestion_pendiente':row['senales']['primera_atencion'],'seguimiento_pendiente':row['senales']['seguimientos_pendientes'],'revision':row['senales']['revisiones'],'accion':(row['accion_atencion'] or {}).get('bucket')})
  assert not row['senales']['primera_atencion'] and not row['senales']['seguimientos_pendientes']
 report={'patrones_reportados':patterns,'snapshot_sha256' :hashlib.sha256(a.snapshot.read_bytes()).hexdigest(),'calculado_en':s['calculado_en'],'oportunidades':len(new),'tareas':len(s['tareas']),
  'alcance':'SQL real sobre proveedores locales de hechos normalizados (dobles explícitos). Misma foto y reloj. Permisos probados por separado en esquema integral.',
  'global_supervision':{'antes':counts(old,True),'despues':counts(new,True)},'perspectiva_analistas_agregada':{'antes':counts(old,False),'despues':counts(new,False)},
  'cambios_accion_principal':dict(sorted(transitions.items())),'diferencia_senales':dict(sorted(deltas.items())),'explicaciones':dict(causes),
  'historia_plazos_compromisos_intactos':True,'revisiones_intactas':True,'diferencias_sin_explicacion':0}
 a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False,indent=2))
finally:sql('drop database '+db+';','postgres')

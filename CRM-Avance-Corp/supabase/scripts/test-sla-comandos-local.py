#!/usr/bin/env python3
"""N3: transacciones, recibos y carreras sobre esquema completo real local.
Clona un template N1/N2/N3 preparado; nunca admite un host o URL de red.
"""
import argparse, json, os, subprocess, time, unittest, uuid
from pathlib import Path
PG=Path('/opt/homebrew/opt/postgresql@17/bin')
BASE=Path(__file__).resolve().parents[1]
ENV=None; TEMPLATE=None; RESULTS={}
def q(v):
 if v is None:return 'null'
 if isinstance(v,(dict,list)):v=json.dumps(v)
 return "'"+str(v).replace("'","''")+"'"
def actor(n):return '00000000-0000-0000-0000-'+str(n).zfill(12)
def auth(s,n=1001):return 'set role authenticated;set request.jwt.claim.sub='+q(actor(n))+';'+s
def command(s,db):return [str(PG/'psql'),'-XqAt','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose','-d',db,'-c',s]
def sql(s,db='postgres',fail=False):
 r=subprocess.run(command(s,db),env=ENV,text=True,capture_output=True,timeout=30)
 if not fail and r.returncode:raise AssertionError(r.stderr)
 return r if fail else r.stdout.strip()
class Comandos(unittest.TestCase):
 def setUp(self):
  self.db='sla_n3_case_'+uuid.uuid4().hex[:10]
  sql('create database '+self.db+' template '+TEMPLATE+';')
  self.sql('update cron.job set database=current_database();')
 def tearDown(self):sql('drop database '+self.db+';')
 def sql(self,s):return sql(s,self.db)
 def value(self,s,n=1001):return json.loads(self.sql(auth('select '+s+';',n)))
 def reject(self,s,state,n=1001):
  r=sql(auth(s,n),self.db,True);self.assertNotEqual(r.returncode,0,r.stdout);self.assertIn(state,r.stderr)
 def lead(self,owner=1001):
  ident=str(uuid.uuid4());phone='+519'+str(uuid.uuid4().int%100000000).zfill(8)
  result=self.value("crm.crear_lead_si_disponible('SINTETICO N3',"+q(phone)+",'oficina',1000,'PEN',p_id=>"+q(ident)+",p_etapa=>'contactado',p_vendedor_id=>"+q(actor(owner))+")",1004);self.assertEqual(result['estado'],'creado');return ident
 def task(self,lead,kind='llamada'):
  ident=str(uuid.uuid4())
  self.sql(auth('insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,creado_por'+(',modalidad_reunion' if kind=='reunion' else '')+') values ('+','.join(map(q,[ident,lead,kind,'Agenda sintetica']))+",clock_timestamp()+interval '1 day',"+q(actor(1001))+(",'virtual'" if kind=='reunion' else '')+');'));return ident
 def activity(self,lead,op=None,following=None,detail='Contacto sintetico'):
  return 'crm.registrar_actividad_v2('+','.join(map(q,[op or str(uuid.uuid4()),lead,'llamada_realizada',detail,following]))+')'
 def counts(self,lead):return self.sql('select jsonb_build_array((select count(*) from crm.actividades where lead_id='+q(lead)+" and tipo='llamada_realizada'),(select count(*) from crm.tareas where lead_id="+q(lead)+'),(select count(*) from crm.sla_operacion_recibos where lead_id='+q(lead)+'));')
 def activate(self):
  keys=('etapa','maximo_minutos','seguimiento_minutos','prorroga_minutos','prorroga_max','tope_extra_minutos','pausa_habilitada','pausa_margen_minutos')
  rows=[('nuevo',1440,1440,0,0,2880,True,240),('contactado',60,4320,5760,2,11520,True,1440),('reunion_agendada',21600,4320,0,0,4320,True,2880),('propuesta_enviada',28800,7200,10080,1,10080,True,1440)]
  payload=dict(zona_horaria='America/Lima',tipo_reloj='corrido',primera_gestion_minutos=120,primer_contacto_minutos=1440,etapas=[dict(zip(keys,r)) for r in rows])
  self.value('crm.publicar_politica_sla_v2(1,null,'+q(payload)+')',1004)
  self.value("crm.cambiar_modo_sla_operacion(0,'activo')",1004)
 def adjustments(self,lead):return self.sql('select count(*) from crm.lead_sla_etapa_ajustes a join crm.lead_sla_etapas e on e.id=a.etapa_sla_id where e.lead_id='+q(lead)+';')
 def gesture(self,kind):
  self.activate();lead=self.lead();following={'tipo':kind,'titulo':'Próximo paso','vence_en':'2027-01-01T12:00:00Z'}
  if kind=='reunion':following['modalidad_reunion']='virtual'
  call=self.activity(lead,following=following);first=self.value(call);self.assertEqual(first,self.value(call))
  self.assertEqual(self.adjustments(lead),'0' if kind=='reunion' else '1')
  self.assertEqual(self.sql('select etapa from crm.leads where id='+q(lead)+';'),'reunion_agendada' if kind=='reunion' else 'contactado')
 def test_gesto_activo_siguiente_reunion_cero_prorrogas(self):self.gesture('reunion')
 def test_gesto_activo_siguiente_llamada_una_prorroga(self):self.gesture('llamada')
 def test_gate_detecta_deriva_definer_acl_y_fk(self):
  self.assertIn('OK',self.sql('select private.assert_sla_comandos();'))
  for mutation in [
   'alter function private.trg_sla_recibo_confirmado() security invoker',
   'grant select on crm.sla_operacion_recibos to authenticated',
   'alter table crm.sla_operacion_recibos alter constraint sla_operacion_recibos_actor_id_fkey not deferrable']:
   result=sql('begin;'+mutation+';select private.assert_sla_comandos();rollback;',self.db,True)
   self.assertNotEqual(result.returncode,0);self.assertIn('P0001',result.stderr)
  self.assertIn('OK',self.sql('select private.assert_sla_comandos();'))
 def test_retry_respuesta_persistida_sin_duplicar(self):
  lead=self.lead();call=self.activity(lead);a=self.value(call);before=self.counts(lead);b=self.value(call)
  self.assertEqual(a,b);self.assertEqual(before,self.counts(lead));self.assertEqual(json.loads(before),[1,0,1])
  self.assertEqual(a,json.loads(self.sql('select respuesta from crm.sla_operacion_recibos where lead_id='+q(lead)+';')))
 def test_payload_distinto_misma_operacion_falla(self):
  lead=self.lead();op=str(uuid.uuid4());self.value(self.activity(lead,op));before=self.counts(lead)
  self.reject('select '+self.activity(lead,op,detail='Otro contenido')+';','23505');self.assertEqual(before,self.counts(lead))
 def test_pierde_ambito_no_recupera_recibo(self):
  lead=self.lead();call=self.activity(lead);self.value(call)
  self.sql(auth('update crm.leads set vendedor_id='+q(actor(1002))+' where id='+q(lead)+';',1004))
  self.reject('select '+call+';','42501')
 def test_roles_fuera_de_ambito_y_recibos_privados(self):
  lead=self.lead()
  for who in [1002,1005,1006]:self.reject('select '+self.activity(lead)+';','42501',who)
  for who in [1001,1003,1004]:
   self.reject('select * from crm.sla_operacion_recibos;','42501',who)
   self.reject('select private.sla_ejecutar_comando(null,null,null,null);','42501',who)
  self.assertEqual(json.loads(self.counts(lead)),[0,0,0])
 def test_supervisor_y_gerencia_en_ambito(self):
  lead=self.lead()
  for who in [1003,1004]:self.assertTrue(self.value(self.activity(lead),who)['ok'])
 def test_actividad_y_siguiente_atomicas_y_retry(self):
  lead=self.lead();following={'tipo':'llamada','titulo':'Próximo contacto','vence_en':'2027-01-01T12:00:00Z'}
  call=self.activity(lead,following=following);first=self.value(call);self.assertIsNotNone(first['siguiente_id']);self.assertEqual(first,self.value(call));self.assertEqual(json.loads(self.counts(lead)),[1,1,1])
 def test_siguiente_invalida_revierte_actividad_etapa_y_recibo(self):
  lead=self.lead();before=self.counts(lead);op=str(uuid.uuid4())
  self.reject('select '+self.activity(lead,op,{'tipo':'inexistente','titulo':'Inválido','vence_en':'2027-01-01Z'})+';','P0001')
  self.assertEqual(before,self.counts(lead));self.assertTrue(self.value(self.activity(lead,op))['ok'])
 def test_recibo_sin_confirmacion_falla_al_commit(self):
  lead=self.lead();op=str(uuid.uuid4())
  r=sql('begin;insert into crm.sla_operacion_recibos(actor_id,operacion_id,lead_id,sujeto_id,comando,payload) values ('+','.join(map(q,[actor(1001),op,lead,lead,'registrar_actividad',{}]))+');commit;',self.db,True)
  self.assertNotEqual(r.returncode,0);self.assertIn('23514',r.stderr);self.assertEqual(json.loads(self.counts(lead)),[0,0,0])
 def test_recibo_confirmado_inmutable(self):
  lead=self.lead();self.value(self.activity(lead))
  for statement in ['update crm.sla_operacion_recibos set respuesta=\'{}\'::jsonb','delete from crm.sla_operacion_recibos','truncate crm.sla_operacion_recibos']:
   r=sql(statement,self.db,True);self.assertNotEqual(r.returncode,0);self.assertIn('55000',r.stderr)
 def race(self,same):
  lead=self.lead();op=str(uuid.uuid4());a=self.activity(lead,op);b=a if same else self.activity(lead)
  procs=[subprocess.Popen(command(auth("set statement_timeout='8s';begin;select "+call+";select pg_sleep(0.2);commit;"),self.db),env=ENV,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE) for call in [a,b]]
  out=[]
  for p in procs:
   stdout,stderr=p.communicate(timeout=12);self.assertEqual(p.returncode,0,stderr);out.append(json.loads(stdout.splitlines()[0]))
  self.assertEqual(out[0]==out[1],same)
  n=1 if same else 2;self.assertEqual(json.loads(self.counts(lead)),[n,0,n])
 def test_carrera_misma_operacion(self):self.race(True)
 def test_carrera_distintas_operaciones_mismo_lead(self):self.race(False)
 def test_v1_directo_y_v2_actividad_concurrentes(self):
  lead=self.lead();task=self.task(lead)
  direct='crm.cerrar_tarea('+','.join(map(q,[task,'completada','llamada_realizada','Cierre legado']))+')'
  procs=[subprocess.Popen(command(auth("set statement_timeout='8s';begin;select "+call+";select pg_sleep(0.2);commit;"),self.db),env=ENV,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE) for call in [direct,self.activity(lead)]]
  for proc in procs:
   stdout,stderr=proc.communicate(timeout=12);self.assertEqual(proc.returncode,0,stderr);self.assertTrue(json.loads(stdout.splitlines()[0])['ok'])
  self.assertEqual(json.loads(self.counts(lead)),[2,1,1])
 def test_v1_directo_reunion_y_reprogramacion(self):
  lead=self.lead();task=self.task(lead,'reunion')
  changed=self.value('crm.reprogramar_reunion('+','.join(map(q,[task,'2027-01-01T12:00:00Z']))+')')
  self.assertTrue(changed['ok'])
  self.assertTrue(self.value('crm.cerrar_reunion('+','.join(map(q,[changed['tarea_nueva_id'],'completada','seguimiento']))+')')['ok'])
 def test_cerrar_tarea_retry_y_guc_restaurado(self):
  lead=self.lead();task=self.task(lead);op=str(uuid.uuid4());call='crm.cerrar_tarea_v2('+','.join(map(q,[op,task,'completada','llamada_realizada','Hecho']))+')'
  raw=self.sql(auth("begin;set local crm.op_tarea='valor_previo';select "+call+";select current_setting('crm.op_tarea');commit;"));lines=raw.splitlines();first=json.loads(lines[0]);self.assertEqual(lines[1],'valor_previo');self.assertEqual(first,self.value(call));self.assertEqual(self.sql('select estado from crm.tareas where id='+q(task)+';'),'completada');self.assertEqual(json.loads(self.counts(lead)),[1,1,1])
 def test_cerrar_reunion_retry(self):
  lead=self.lead();task=self.task(lead,'reunion');call='crm.cerrar_reunion_v2('+','.join(map(q,[str(uuid.uuid4()),task,'completada','seguimiento']))+')';a=self.value(call);self.assertEqual(a,self.value(call));self.assertEqual(self.sql('select count(*) from crm.actividades where lead_id='+q(lead)+" and tipo='reunion_realizada';"),'1')
 def test_reprogramar_reunion_retry(self):
  lead=self.lead();task=self.task(lead,'reunion');call='crm.reprogramar_reunion_v2('+','.join(map(q,[str(uuid.uuid4()),task,'2027-01-01T12:00:00Z']))+')';a=self.value(call);self.assertEqual(a,self.value(call));self.assertEqual(self.sql('select count(*) from crm.tareas where lead_id='+q(lead)+';'),'2')
 def test_reprogramar_tarea_retry_y_fecha_invalida(self):
  lead=self.lead();task=self.task(lead);op=str(uuid.uuid4());call='crm.reprogramar_tarea_v2('+','.join(map(q,[op,task,'2027-01-01T12:00:00Z']))+')';a=self.value(call);self.assertEqual(a,self.value(call));self.reject('select crm.reprogramar_tarea_v2('+','.join(map(q,[str(uuid.uuid4()),task,'infinity']))+');','22023')
 def test_timestamp_actividad_cliente_se_sella_con_reloj_servidor(self):
  lead=self.lead();activity=str(uuid.uuid4())
  self.sql(auth('insert into crm.actividades(id,lead_id,tipo,creado_por,creado_en) values ('+q(activity)+','+q(lead)+",'llamada_realizada',"+q(actor(1001))+",clock_timestamp()+interval '1 day');"))
  self.assertEqual(self.sql('select creado_en between clock_timestamp()-interval \'10 seconds\' and clock_timestamp() from crm.actividades where id='+q(activity)+';'),'t')
  self.assertEqual(json.loads(self.counts(lead)),[1,0,0])
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--socket',type=Path,required=True);p.add_argument('--template',required=True);p.add_argument('--output',type=Path,required=True);args=p.parse_args()
 socket=args.socket.resolve();assert str(socket).startswith('/private/tmp/sla-integracion-') and (socket/'LOCAL-SLA-BANK').exists();assert args.template.startswith('sla_') and args.template.replace('_','').isalnum()
 ENV={k:v for k,v in os.environ.items() if not k.startswith('PG')};ENV.update(PGHOST=str(socket),PGPORT='55485',PGUSER='postgres',PGDATABASE='postgres');TEMPLATE=args.template
 suite=unittest.defaultTestLoader.loadTestsFromTestCase(Comandos);start=time.monotonic();result=unittest.TextTestRunner(verbosity=2).run(suite)
 args.output.write_text(json.dumps({'tests':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),'ok':result.wasSuccessful(),'seconds':round(time.monotonic()-start,3),'schema':'full','tcp':False},indent=2)+'\n');raise SystemExit(0 if result.wasSuccessful() else 1)

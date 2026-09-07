#!/usr/bin/env python3
"""Modelo 3 sobre esquema completo PG17: autoridades, writers, triggers y recibos reales.
Reutiliza las regresiones de comandos y únicamente admite sockets del banco aislado.
"""
import argparse, datetime as dt, importlib.util, json, os, time, unittest, uuid
from pathlib import Path
BASE=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('comandos',BASE/'scripts/test-sla-comandos-local.py')
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)
q,actor,auth=c.q,c.actor,c.auth
MIGRATION=BASE/'migrations/20260907212612_crm_sla_avisos_por_accion_y_rol.sql'
ROLLBACK=BASE/'scripts/rollback-sla-accion-rol.sql'

class Integracion(c.Comandos):
 def state(self,lead,instant=None):
  if instant is None:return self.value('crm.estado_sla_leads_v2_fn(array['+q(lead)+']::uuid[])')['filas'][0]
  return json.loads(self.sql("select estado from private.sla_operacion_leads(array["+q(lead)+"]::uuid[],true,'{}',"+q(instant)+");"))
 def future(self,days):return (dt.datetime.now(dt.timezone.utc)+dt.timedelta(days=days)).isoformat()
 def attempt(self,lead,following=None):return self.value('crm.registrar_actividad_v2('+','.join(map(q,[str(uuid.uuid4()),lead,'llamada_no_contestada','Intento sin respuesta',following]))+')')
 def test_modelo_writer_intento_y_sucesora_no_inventan_contacto(self):
  self.activate();l=self.lead();following={'tipo':'llamada','titulo':'Siguiente intento','vence_en':self.future(20)}
  self.attempt(l,following)
  state=self.state(l,self.future(10))
  self.assertIsNotNone(state['base']['asignacion_primera_gestion_en'])
  self.assertIsNone(state['base']['asignacion_primer_contacto_en'])
  self.assertTrue(state['etapa']['revision_requerida'])
  self.assertFalse(state['compromiso']['cobertura_activa'])
  self.assertNotIn('primera_atencion',[a['bucket'] for a in state['avisos']])
  self.assertNotIn('seguimiento',[a['bucket'] for a in state['avisos']])
  self.assertEqual(state['operacion']['proxima_accion']['titulo'],'Siguiente intento')
  self.assertIsNone(state['operacion']['aviso_principal'])
 def test_modelo_agendar_sin_intento_sigue_pendiente(self):
  self.activate();l=self.lead();self.task(l)
  state=self.state(l,self.future(0.2))
  self.assertIsNone(state['base']['asignacion_primera_gestion_en'])
  self.assertEqual(state['operacion']['aviso_principal']['bucket'],'primera_atencion')
 def test_modelo_cerrar_con_sucesora_lectura_confirmada(self):
  self.activate();l=self.lead();task=self.task(l)
  self.attempt(l)
  self.assertEqual(self.state(l,self.future(2))['operacion']['aviso_principal']['bucket'],'tarea_vencida')
  following={'tipo':'whatsapp','titulo':'Seguimiento confirmado','vence_en':self.future(5)}
  call='crm.cerrar_tarea_v2('+','.join(map(q,[str(uuid.uuid4()),task,'completada','llamada_no_contestada','Intento terminado',following]))+')'
  self.assertTrue(self.value(call)['ok'])
  state=self.state(l,self.future(2))
  self.assertIsNone(state['operacion']['aviso_principal'])
  self.assertEqual(state['operacion']['proxima_accion']['titulo'],'Seguimiento confirmado')
  self.assertIsNone(state['base']['primer_contacto_en'])
 def test_modelo_cancelar_no_registra_gestion(self):
  self.activate();l=self.lead();task=self.task(l);self.attempt(l)
  before=self.state(l)
  self.assertTrue(self.value('crm.cerrar_tarea_v2('+','.join(map(q,[str(uuid.uuid4()),task,'cancelada',None,None]))+')')['ok'])
  state=self.state(l,self.future(4))
  self.assertEqual(state['base'],before['base'])
  self.assertEqual(state['operacion']['aviso_principal']['bucket'],'seguimiento')
  self.assertIsNone(state['operacion']['proxima_accion'])
 def test_modelo_reasignacion_usa_hito_del_responsable_actual(self):
  self.activate();l=self.lead();self.attempt(l);self.task(l)
  self.sql(auth('update crm.leads set vendedor_id='+q(actor(1002))+' where id='+q(l)+';',1004))
  state=self.state(l,self.future(0.2))
  self.assertIsNotNone(state['base']['primera_gestion_en'])
  self.assertIsNone(state['base']['asignacion_primera_gestion_en'])
  self.assertEqual(state['operacion']['aviso_principal']['bucket'],'primera_atencion')
  self.assertEqual(self.value('crm.estado_sla_leads_v2_fn(array['+q(l)+']::uuid[])')['filas'],[])
 def test_modelo_roles_y_tres_reprogramaciones(self):
  self.activate();l=self.lead();self.attempt(l);task=self.task(l)
  for i in range(3):self.value('crm.reprogramar_tarea_v2('+','.join(map(q,[str(uuid.uuid4()),task,self.future(4+i)]))+')')
  for who in (1001,1003,1004,1005):
   result=self.value("jsonb_build_object('f',crm.estado_sla_leads_v2_fn(array["+q(l)+"]::uuid[]),'q',crm.cola_accion_v2_fn(10,'pendientes'),'r',crm.avisos_sla_resumen_v2_fn())",who)
   state=result['f']['filas'][0]
   self.assertEqual([a['bucket'] for a in state['avisos_mostrados']],[] if who==1001 else ['revision_comercial'])
   self.assertEqual(result['q']['total_items'],0 if who==1001 else 1)
   self.assertEqual(result['q']['total_items'],result['r']['total_oportunidades'])
   self.assertEqual(result['f']['calculado_en'],result['r']['calculado_en'])
  for who in (1002,1007):self.assertEqual(self.value('crm.estado_sla_leads_v2_fn(array['+q(l)+']::uuid[])',who)['filas'],[])
  self.reject('select crm.avisos_sla_resumen_v2_fn();','42501',1006)
  self.assertNotEqual(c.sql('set role anon;select crm.avisos_sla_resumen_v2_fn();',self.db,True).returncode,0)
 def test_modelo_reversion_reaplicacion_igualdad_fuentes_permisos_historia(self):
  self.activate();l=self.lead();self.attempt(l);self.task(l)
  metadata="select jsonb_agg(jsonb_build_array(oid::regprocedure::text,proowner,proacl,prosecdef,provolatile,proconfig,prorettype,proargtypes) order by oid) from pg_proc where oid in ('private.sla_operacion_leads(uuid[],boolean,uuid[],timestamptz)'::regprocedure,'private.sla_operacion_autorizada(uuid[],boolean)'::regprocedure,'crm.cola_accion_v2_fn(integer,text,text,uuid,jsonb)'::regprocedure);"
  contract=self.sql(metadata);facts=self.sql('select row_to_json(l) from crm.leads l where id='+q(l)+';')
  v1=self.value('to_jsonb(array(select row_to_json(s) from crm.estado_sla_leads_fn() s))')
  before=self.state(l,'2026-10-01Z')
  self.sql(ROLLBACK.read_text());self.assertEqual(contract,self.sql(metadata))
  self.assertNotEqual(c.sql(ROLLBACK.read_text(),self.db,True).returncode,0)
  self.sql(MIGRATION.read_text());after=self.state(l,'2026-10-01Z')
  self.assertEqual(before,after);self.assertEqual(contract,self.sql(metadata))
  self.assertEqual(facts,self.sql('select row_to_json(l) from crm.leads l where id='+q(l)+';'))
  self.assertEqual(v1,self.value('to_jsonb(array(select row_to_json(s) from crm.estado_sla_leads_fn() s))'))
  self.assertNotEqual(c.sql(MIGRATION.read_text(),self.db,True).returncode,0)
  for gate in ('assert_sla_nucleo','assert_sla_operacion','assert_sla_comandos','assert_analista_vigencia','assert_analitica_leads_citas','assert_auditoria','assert_f7_piezas_cerradas'):
   self.sql('select private.'+gate+'();')


 def test_modelo_cerrar_reabrir_inicia_ciclo_actual_sin_heredar_tareas(self):
  self.activate();l=self.lead();self.attempt(l);self.task(l)
  before=self.state(l)
  self.sql(auth("update crm.leads set etapa='descartado',motivo_descarte='sin_interes' where id="+q(l)+';',1004))
  closed=self.state(l)
  self.assertEqual(closed['evaluacion'],'no_aplica')
  self.assertEqual(closed['avisos'],[])
  self.value('crm.reabrir_lead_fn('+q(l)+')',1004)
  reopened=self.state(l,self.future(0.2))
  self.assertGreater(reopened['ciclo_n'],before['ciclo_n'])
  self.assertIsNone(reopened['base']['asignacion_primera_gestion_en'])
  self.assertIsNone(reopened['operacion']['proxima_accion'])
  self.assertEqual(reopened['operacion']['aviso_principal']['bucket'],'primera_atencion')

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--socket',type=Path,required=True);p.add_argument('--template',required=True);p.add_argument('--output',type=Path,required=True);args=p.parse_args()
 socket=args.socket.resolve();assert str(socket).startswith('/private/tmp/sla-integracion-') and (socket/'LOCAL-SLA-BANK').exists();assert args.template.startswith('sla_') and args.template.replace('_','').isalnum()
 c.ENV={k:v for k,v in os.environ.items() if not k.startswith('PG')};c.ENV.update(PGHOST=str(socket),PGPORT='55485',PGUSER='postgres',PGDATABASE='postgres');c.TEMPLATE=args.template
 start=time.monotonic();result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Integracion))
 args.output.write_text(json.dumps({'tests':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),'ok':result.wasSuccessful(),'seconds':round(time.monotonic()-start,3),'schema':'full','tcp':False,'dobles_de_autoridad_o_writers':False},indent=2)+'\n');raise SystemExit(0 if result.wasSuccessful() else 1)

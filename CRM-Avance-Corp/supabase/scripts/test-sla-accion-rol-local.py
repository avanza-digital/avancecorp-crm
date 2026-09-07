#!/usr/bin/env python3
"""Modelo de acción y rol. SQL real; banco reducido con dobles de autoridad explícitos.
--sin-cambio --solo-nuevas demuestra regresiones frente a la versión publicada.
"""
import argparse
import datetime as dt
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('compromiso', BASE/'scripts/test-sla-primera-compromiso-local.py')
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
a, n = p.a, p.n
MIGRATION = BASE/'migrations/20260907212612_crm_sla_avisos_por_accion_y_rol.sql'
ROLLBACK = BASE/'scripts/rollback-sla-accion-rol.sql'

class AccionRol(a.Avisos):
    intentada = p.PrimeraCompromiso.intentada
    fila = p.PrimeraCompromiso.fila

    def principal(self, row):
        return (row['estado'].get('operacion', {}).get('aviso_principal') or {}).get('bucket')

    def test_modelo_intento_con_y_sin_respuesta_en_cuatro_etapas(self):
        self.configured()
        for stage in ('nuevo','contactado','reunion_agendada','propuesta_enviada'):
            for contacted in (False, True):
                for expired in (False, True):
                    with self.subTest(stage=stage, contacted=contacted, expired=expired):
                        create = self.lead if contacted else self.intentada
                        l = create(stage=stage, limit='2026-08-01Z' if expired else '2026-09-20Z')
                        task = self.task(l,'2026-09-07T17:00Z', reprogram=3 if expired else 0)
                        row = self.fila(l)
                        self.assertFalse(row['senales']['primera_atencion'])
                        self.assertFalse(row['senales']['seguimientos_pendientes'])
                        self.assertEqual(row['accion_atencion']['bucket'],'proxima_tarea')
                        self.assertEqual(row['accion_atencion']['tarea_id'],task)
                        self.assertIsNone(self.principal(row))
                        self.assertEqual(row['senales']['revisiones'],expired)
                        if not contacted:
                            self.assertIsNone(row['estado']['base']['primer_contacto_en'])
                            self.assertIsNone(row['estado']['base']['asignacion_primer_contacto_en'])

    def test_modelo_primera_gestion_usa_asignacion_actual_y_frontera(self):
        self.configured()
        l = self.lead(first_done=False, assignment='2026-09-06T16:00Z')
        self.task(l,'2026-09-07T17:00Z')
        for instant, due in [('2026-09-06T17:59:59.999999Z',False),('2026-09-06T18:00Z',True),('2026-09-06T18:00:00.000001Z',True)]:
            row=self.fila(l,instant)
            self.assertEqual(row['senales']['primera_atencion'],due)
            self.assertEqual(n.at(row['accion_atencion']['referencia_en']),n.at('2026-09-06T18:00Z'))
        # Un intento del ciclo hecho por la asignación anterior no basta.
        self.sql(f"update crm.lead_sla_ciclos set primera_gestion_en=iniciado_en where lead_id={n.quote(l['lead'])};")
        self.assertTrue(self.fila(l,'2026-09-06T18:00Z')['senales']['primera_atencion'])

    def test_modelo_sin_tarea_cadencia_no_vuelve_a_primera(self):
        self.configured()
        for stage, minutes in [('nuevo',1440),('contactado',4320),('reunion_agendada',4320),('propuesta_enviada',7200)]:
            l=self.intentada(stage=stage,limit='2026-09-25Z')
            gestion=n.at(n.NOW)
            self.activity(l,gestion,'llamada_no_contestada')
            due=gestion+dt.timedelta(minutes=minutes)
            for instant, pending in [(due-dt.timedelta(microseconds=1),False),(due,True),(due+dt.timedelta(microseconds=1),True)]:
                row=self.fila(l,instant)
                self.assertFalse(row['senales']['primera_atencion'])
                self.assertEqual(row['senales']['seguimientos_pendientes'],pending)
                self.assertEqual(self.principal(row),'seguimiento' if pending else None)

    def test_modelo_tarea_vencida_prioritaria_con_futura_e_inicial(self):
        self.configured()
        for first_done in (False,True):
            l=self.lead(first_done=first_done,limit='2026-09-20Z')
            due=self.task(l,n.NOW)
            self.task(l,'2026-09-08T17:00Z')
            before=self.fila(l,'2026-09-06T16:59:59.999999Z')
            row=self.fila(l)
            self.assertFalse(before['senales']['tareas_vencidas'])
            self.assertTrue(row['senales']['tareas_vencidas'])
            self.assertEqual(self.principal(row),'tarea_vencida')
            self.assertEqual(row['accion_atencion']['tarea_id'],due)
            self.assertEqual(row['senales']['primera_atencion'],not first_done)
            self.assertEqual(row['estado']['operacion']['proxima_accion']['id'],due)

    def test_modelo_cancelar_completar_no_realizada_recalcula(self):
        self.configured()
        for state in ('cancelada','completada','no_realizada'):
            for fresh in (False,True):
                l=self.intentada(limit='2026-09-20Z')
                if fresh: self.activity(l,n.NOW,'whatsapp_enviado')
                task=self.task(l,'2026-09-07T17:00Z')
                before=self.core(l)
                self.sql(f"update crm.tareas set estado={n.quote(state)} where id={n.quote(task)};")
                row=self.fila(l)
                self.assertEqual(before['base'],row['estado']['base'])
                self.assertFalse(row['senales']['primera_atencion'])
                self.assertEqual(row['senales']['seguimientos_pendientes'],not fresh)
                # Una sucesora válida organiza la siguiente gestión.
                self.task(l,'2026-09-08T17:00Z')
                self.assertFalse(self.fila(l)['senales']['seguimientos_pendientes'])

    def test_modelo_ambigua_ajena_administrativa_e_inactiva(self):
        self.configured()
        for params,partial in [({'context':False},True),({'owner':2},True),({'due':'infinity'},True),({'active':False},False),({'kind':'tarea'},False)]:
            l=self.intentada(limit='2026-09-20Z')
            args={'due':'2026-09-07T17:00Z',**params}
            self.task(l,**args)
            row=self.fila(l)
            self.assertFalse(row['senales']['primera_atencion'])
            self.assertTrue(row['senales']['seguimientos_pendientes'])
            self.assertEqual(row['estado']['evaluacion']=='parcial',partial)
            self.assertEqual(self.principal(row),'datos_incompletos' if partial else 'seguimiento')

    def test_modelo_hito_futuro_o_plazo_ausente_es_dato_incompleto(self):
        self.configured()
        l=self.lead()
        self.sql(f"update crm.lead_asignacion_sla_hitos set primera_gestion_en='2027-01-01Z' where lead_asignacion_id={n.quote(l['assignment'])};")
        row=self.fila(l)
        self.assertEqual(row['estado']['evaluacion'],'parcial')
        self.assertEqual(self.principal(row),'datos_incompletos')

    def test_modelo_ficha_cola_campana_mismo_instante_y_roles(self):
        self.configured()
        now=n.at(self.json('to_jsonb(statement_timestamp())'))
        future=self.intentada(start=now-dt.timedelta(days=15),limit=now-dt.timedelta(days=10))
        self.task(future,now+dt.timedelta(days=1))
        due=self.lead(first_done=False,start=now-dt.timedelta(days=2),limit=now+dt.timedelta(days=10))
        task=self.task(due,now-dt.timedelta(minutes=1))
        other=self.lead(owner=2,supervisor=None,first_done=False)
        for actor in (1,3,4,5):
            value=self.json(f"jsonb_build_object('ficha',crm.estado_sla_leads_v2_fn({n.array([future['lead'],due['lead']])}),'cola',crm.cola_accion_v2_fn(50,'pendientes'),'resumen',crm.avisos_sla_resumen_v2_fn())",actor)
            ficha,cola,res=value['ficha'],value['cola'],value['resumen']
            self.assertEqual(ficha['modelo_avisos'],3)
            self.assertEqual(ficha['calculado_en'],cola['calculado_en'])
            self.assertEqual(ficha['calculado_en'],res['calculado_en'])
            self.assertEqual(cola['total_items'],res['total_oportunidades'])
            f={r['lead_id']:r for r in ficha['filas']}
            self.assertEqual([x['bucket'] for x in f[due['lead']]['avisos_mostrados']],['tarea_vencida'])
            self.assertEqual([x['bucket'] for x in f[future['lead']]['avisos_mostrados']],[] if actor==1 else ['revision_comercial'])
            item=next(i for i in cola['items'] if i['lead_id']==due['lead'])
            self.assertEqual(item['bucket'],'tarea_vencida')
            self.assertEqual(item['tarea_id'],task)
            self.assertEqual(item['estado'],f[due['lead']])
        self.assertEqual(self.json(f"crm.estado_sla_leads_v2_fn({n.array([other['lead']])})",1)['filas'],[])

    def test_modelo_siguiente_reconsulta_cambia_en_hora_de_tarea(self):
        self.configured()
        l=self.intentada(limit='2026-09-20Z')
        task=self.task(l,'2026-09-06T17:01Z')
        row=self.fila(l)
        self.assertEqual(n.at(row['estado']['operacion']['proximo_cambio_en']),n.at('2026-09-06T17:01Z'))
        self.assertEqual(self.fila(l,'2026-09-06T17:01Z')['accion_atencion']['tarea_id'],task)
        self.assertEqual(self.principal(self.fila(l,'2026-09-06T17:01Z')),'tarea_vencida')


    # Expectativas de presentación anteriores sustituidas por el modelo aprobado.
    # Se conservan los cuerpos heredados con su historia y presupuestos sin cambios.
    def test_asignacion_incoherente_no_oculta_primera_atencion_del_ciclo(self):
        self.configured()
        for change in ('ciclo_n=0',f'analista_id={n.quote(n.uid(2))}'):
            l=self.lead(first_done=False)
            self.sql(f"update crm.lead_asignaciones set {change} where id={n.quote(l['assignment'])};")
            row=self.fila(l)
            self.assertEqual(row['estado']['evaluacion'],'parcial')
            self.assertFalse(row['senales']['primera_atencion'])
            self.assertEqual(self.principal(row),'datos_incompletos')
            self.assertIsNone(row['estado']['base']['primera_gestion_en'])

    def test_primera_atencion_ignora_hitos_de_asignacion_incoherente(self):
        self.configured()
        for milestone in ('primera_gestion_en','primer_contacto_en'):
            l=self.lead()
            self.sql(f"update crm.lead_asignaciones set ciclo_n=0 where id={n.quote(l['assignment'])};")
            self.sql(f"update crm.lead_asignacion_sla_hitos set {milestone}=null where lead_asignacion_id={n.quote(l['assignment'])};")
            row=self.fila(l)
            self.assertEqual(self.principal(row),'datos_incompletos')
            self.assertFalse(row['senales']['primera_atencion'])
            base=row['estado']['base']
            self.assertIsNone(base['asignacion_'+milestone])
            self.sql(f"update crm.lead_asignaciones set ciclo_n=1 where id={n.quote(l['assignment'])};")
            fixed=self.fila(l)
            self.assertEqual(fixed['senales']['primera_atencion'],milestone=='primera_gestion_en')
            self.assertEqual(fixed['estado']['base'],base)

    def test_aviso_actividad_su_hora_aunque_cubra_seguimiento(self):
        self.configured()
        l=self.lead(limit='2026-09-20Z')
        task=self.task(l,n.NOW)
        before=self.fila(l,'2026-09-06T16:59:59.999999Z')
        due=self.fila(l)
        self.assertEqual(self.buckets(before['estado']),[])
        self.assertEqual(self.principal(due),'tarea_vencida')
        self.assertTrue(due['estado']['compromiso']['cobertura_activa'])
        self.assertFalse(due['estado']['seguimiento']['accion_pendiente'])
        self.assertEqual(due['accion_atencion']['tarea_id'],task)
        self.assertTrue(due['senales']['seguimientos_pendientes'])

    def test_aviso_fin_de_cobertura_reactiva_seguimiento(self):
        self.configured()
        l=self.lead(limit='2026-09-20Z')
        self.task(l,'2026-09-05T17:00Z')
        before=self.fila(l,'2026-09-06T16:59:59.999999Z')
        due=self.fila(l)
        self.assertTrue(before['estado']['compromiso']['cobertura_activa'])
        self.assertFalse(due['estado']['compromiso']['cobertura_activa'])
        self.assertEqual(self.principal(before),'tarea_vencida')
        self.assertEqual(self.principal(due),'tarea_vencida')
        self.assertEqual(self.buckets(before['estado']),['tarea_vencida','seguimiento'])

    def test_mutante_de_cobertura_rompe_estado_y_cola(self):
        self.configured()
        l=self.lead(limit='2026-09-20Z')
        self.task(l,'2026-09-08T17:00Z')
        old=self.core(l)
        source=self.sql("select pg_get_functiondef('private.sla_operacion_leads(uuid[],boolean,uuid[],timestamptz)'::regprocedure);")
        mutant=source.replace('p_ahora<v_hasta','false')
        self.assertNotEqual(source,mutant)
        self.sql(mutant)
        changed=self.fila(l)
        self.assertTrue(old['compromiso']['cobertura_activa'])
        self.assertFalse(changed['estado']['compromiso']['cobertura_activa'])
        self.assertEqual(changed['accion_atencion']['bucket'],'proxima_tarea')
        self.assertFalse(changed['senales']['seguimientos_pendientes'])


    def test_modelo_cursor_publicado_y_orden_anterior_se_rechazan(self):
        self.configured()
        one=self.lead(first_done=False)
        self.lead(first_done=False)
        self.sql(ROLLBACK.read_text())
        old=self.queue(limit=1,signal='pendientes',actor=1)['cursor_siguiente']
        self.sql(MIGRATION.read_text())
        self.fails("select crm.cola_accion_v2_fn(1,'pendientes',null,null,"+n.quote(json.dumps(old))+"::jsonb);",'22023',1)
        first=self.queue(limit=1,signal='pendientes',actor=1)
        second=self.queue(limit=1,signal='pendientes',actor=1,cursor=first['cursor_siguiente'])
        self.assertNotEqual(first['items'][0]['lead_id'],second['items'][0]['lead_id'])
        self.task(one,'2026-09-01T18:00Z')
        self.fails("select crm.cola_accion_v2_fn(1,'pendientes',null,null,"+n.quote(json.dumps(first['cursor_siguiente']))+"::jsonb);",'22023',1)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sin-cambio',action='store_true')
    parser.add_argument('--solo-nuevas',action='store_true')
    args=parser.parse_args()
    n.BANK=n.Bank()
    try:
        n.BANK.start()
        n.BANK.sql(a.MIGRATION.read_text(),'sla_template')
        n.BANK.sql(p.MIGRATION.read_text(),'sla_template')
        if not args.sin_cambio: n.BANK.sql(MIGRATION.read_text(),'sla_template')
        names=unittest.defaultTestLoader.getTestCaseNames(AccionRol)
        if args.solo_nuevas: names=[name for name in names if name.startswith('test_modelo_')]
        result=unittest.TextTestRunner(verbosity=2).run(unittest.TestSuite(AccionRol(name) for name in names))
        report={'migracion':MIGRATION.name,'sha256':hashlib.sha256(MIGRATION.read_bytes()).hexdigest(),
                'sin_cambio':args.sin_cambio,'pruebas':result.testsRun,'fallos':len(result.failures),'errores':len(result.errors),
                'correcto':result.wasSuccessful(),'postgres':n.BANK.sql('show server_version;','sla_template'),
                'alcance':'SQL real sobre banco reducido con dobles de autoridad; sin red ni PII.'}
        (n.BANK.root/'resultados.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
        print('Evidencia: '+str(n.BANK.root/'resultados.json'),flush=True)
        raise SystemExit(0 if result.wasSuccessful() else 1)
    finally: n.BANK.close()

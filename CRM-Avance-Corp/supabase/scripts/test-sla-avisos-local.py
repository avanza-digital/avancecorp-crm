#!/usr/bin/env python3
"""Avisos: migracion real sobre banco PG16 propio, sin red ni datos personales.
Reutiliza fixtures del nucleo; la autoridad reducida se declara en ese banco.
"""
import importlib.util
import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('nucleo', BASE / 'scripts/test-sla-nucleo-local.py')
n = importlib.util.module_from_spec(spec)
spec.loader.exec_module(n)
uid, quote, array = n.uid, n.quote, n.array
MIGRATION = BASE / 'migrations/20260907155813_crm_sla_avisos_contextuales.sql'

class Avisos(n.Nucleo):
    def buckets(self, state):
        return [a['bucket'] for a in state['avisos']]

    def test_aviso_actividad_su_hora_aunque_cubra_seguimiento(self):
        self.configured()
        l = self.lead(limit='2026-09-20T17:00Z')
        task = self.task(l, n.NOW)
        before = self.core(l, '2026-09-06T16:59:59.999999Z')
        due = self.core(l)
        self.assertTrue(due['compromiso']['cobertura_activa'])
        self.assertFalse(due['seguimiento']['accion_pendiente'])
        self.assertEqual(self.buckets(before), [])
        self.assertEqual(self.buckets(due), ['tarea_vencida'])
        self.assertEqual(due['avisos'][0]['tarea_id'], task)
        self.assertEqual(due['avisos'][0]['id'], self.core(l, '2026-09-06T17:01Z')['avisos'][0]['id'])

    def test_aviso_no_anticipa_tarea_del_mismo_dia_ni_primera_atencion(self):
        self.configured()
        l = self.lead(start='2026-09-06T16:00Z', first_done=False)
        self.task(l, '2026-09-06T19:00Z')
        self.assertEqual(self.buckets(self.core(l)), [])
        self.assertIn('primera_atencion', self.buckets(self.core(l, '2026-09-06T18:00Z')))

    def test_aviso_tarea_no_oculta_detras_de_primera_atencion_futura(self):
        self.configured()
        l = self.lead(start='2026-09-06T16:00Z', first_done=False)
        self.task(l, n.NOW)
        self.assertEqual(self.buckets(self.core(l)), ['tarea_vencida'])

    def test_aviso_fin_de_cobertura_reactiva_seguimiento(self):
        self.configured()
        l = self.lead(limit='2026-09-20T17:00Z')
        self.task(l, '2026-09-05T17:00Z')
        self.assertEqual(self.buckets(self.core(l, '2026-09-06T16:59:59.999999Z')), ['tarea_vencida'])
        self.assertEqual(self.buckets(self.core(l)), ['tarea_vencida', 'seguimiento'])

    def test_aviso_resolucion_real_y_revision_independiente(self):
        self.configured()
        l = self.lead(limit='2026-09-02T17:00Z')
        task = self.task(l, '2026-09-03T17:00Z', reprogram=3)
        before = self.core(l)
        self.assertIn('tarea_vencida', self.buckets(before))
        self.assertIn('revision_comercial', self.buckets(before))
        self.sql(f"update crm.tareas set estado='completada' where id={n.quote(task)};")
        self.activity(l, n.NOW)
        after = self.core(l)
        self.assertNotIn('tarea_vencida', self.buckets(after))
        self.assertNotIn('seguimiento', self.buckets(after))
        self.assertIn('revision_comercial', self.buckets(after))

    def test_aviso_resumen_cola_ficha_autorizados_y_roles(self):
        self.configured()
        mine = self.lead(limit='2026-09-01T18:00Z')
        self.task(mine, '2026-09-02T17:00Z')
        other = self.lead(owner=2, supervisor=None)
        self.task(other, '2026-09-02T17:00Z', owner=2, supervisor=None)
        unassigned = self.lead(owner=None, assigned=False)
        for actor, expected in [(1,1),(2,1),(3,2),(4,3),(5,3)]:
            resumen = self.json('crm.avisos_sla_resumen_v2_fn()', actor)
            cola = self.json("crm.cola_accion_v2_fn(1,'pendientes')", actor)
            self.assertEqual(resumen['total_oportunidades'], expected, actor)
            self.assertEqual(resumen['total_oportunidades'], cola['total_items'])
            self.assertEqual(resumen['total_oportunidades'], cola['totales']['pendientes'])
            self.assertEqual(sum(g['total'] for g in resumen['grupos']), resumen['total_avisos'])
            if actor == 1:
                self.assertNotIn('revision_comercial', [g['bucket'] for g in resumen['grupos']])
                state = self.json(f"crm.estado_sla_leads_v2_fn({n.array([mine['lead']])})", actor)['filas'][0]
                self.assertNotIn('revision_comercial', self.buckets(state))
                self.assertEqual(self.json("crm.cola_accion_v2_fn(10,'revisiones')", actor)['total_items'], 0)
            if actor == 3:
                self.assertIn('revision_comercial', [g['bucket'] for g in resumen['grupos']])
                state = self.json(f"crm.estado_sla_leads_v2_fn({n.array([mine['lead']])})", actor)['filas'][0]
                self.assertIn('revision_comercial', self.buckets(state))
                self.assertEqual(self.json("crm.cola_accion_v2_fn(10,'tareas_vencidas')", actor)['items'][0]['bucket'], 'tarea_vencida')
                self.assertEqual(self.json("crm.cola_accion_v2_fn(10,'revisiones')", actor)['items'][0]['bucket'], 'revision_comercial')
        for actor in [6,7]:
            self.fails('select crm.avisos_sla_resumen_v2_fn();', '42501', actor)
        self.fails('select crm.avisos_sla_resumen_v2_fn();', '42501', 1, role='anon')
        self.assertEqual(self.json(f"crm.estado_sla_leads_v2_fn({n.array([other['lead'],unassigned['lead']])})", 1)['filas'], [])

    def test_aviso_resumen_completo_mas_de_una_pagina(self):
        self.configured()
        for _ in range(51):
            self.lead()
        resumen = self.json('crm.avisos_sla_resumen_v2_fn()', 1)
        seen = []
        cursor = 'null'
        while True:
            page = self.json(f"crm.cola_accion_v2_fn(10,'pendientes',null,null,{cursor})", 1)
            seen.extend(item['lead_id'] for item in page['items'])
            if not page['hay_mas']:
                break
            cursor = n.quote(json.dumps(page['cursor_siguiente'])) + '::jsonb'
        self.assertEqual(resumen['total_oportunidades'], 51)
        self.assertEqual(len(seen), 51)
        self.assertEqual(len(set(seen)), 51)
        self.assertLessEqual(len(resumen['grupos']), 6)

    def test_aviso_legado_observacion_no_emiten_campana(self):
        self.rules()
        self.lead()
        for mode in ['legado','observacion']:
            self.activate(mode)
            resumen = self.json('crm.avisos_sla_resumen_v2_fn()', 1)
            self.assertEqual(resumen['total_avisos'], 0)
            self.assertEqual(resumen['grupos'], [])

    def test_aviso_datos_incompletos_no_declara_todo_al_dia(self):
        self.configured()
        l = self.lead(photo=False)
        self.assertEqual(self.core(l)['evaluacion'], 'parcial')
        self.assertIn('datos_incompletos', self.buckets(self.core(l)))


    # Las revisiones se presentan a quien decide; el filtro muestra esa acción.
    def test_cola_totales_antes_del_limite_y_concordancia_estado(self):
        self.configured()
        l=self.lead(first_done=False,limit='2026-08-01Z')
        self.task(l,'2026-09-02T17:00Z')
        self.lead(first_done=False)
        self.lead(owner=2,supervisor=None)
        # Un unico statement conserva el mismo reloj en los dos consumidores.
        result=self.json(f"jsonb_build_object('estado',crm.estado_sla_leads_v2_fn({array(self.ids)}),'cola',crm.cola_accion_v2_fn(1))",1)
        q=result['cola']
        self.assertEqual(q['total_items'],2)
        self.assertTrue(q['hay_mas'])
        self.assertEqual(len(q['items']),1)
        self.assertEqual(q['totales']['primera_atencion'],2)
        self.assertEqual(q['totales']['tareas_vencidas'],1)
        self.assertEqual(q['totales']['revisiones'],0)
        self.assertEqual(q['items'][0]['bucket'],'primera_atencion')
        states={s['lead_id']:s for s in result['estado']['filas']}
        self.assertEqual(q['items'][0]['estado'],states[q['items'][0]['lead_id']])
        self.assertEqual(q['calculado_en'],result['estado']['calculado_en'])


    def test_cola_paginada_recupera_mas_de_200_revisiones_solapadas(self):
        self.configured()
        expected=[self.lead(first_done=False,limit='2026-09-01T18:00Z')['lead'] for _ in range(211)]
        self.lead(stage='propuesta_enviada',owner=2,supervisor=None,first_done=False,limit='2026-09-01T18:00Z')
        # Con datos y fronteras temporales estables, recorrer todas las paginas
        # debe conservar pertenencia, orden y ausencia de duplicados.
        for actor in (3,4,5):
            with self.subTest(actor=actor):
                cursor=None;seen=[];pages=0
                while True:
                    page=self.queue(signal='revisiones',stage='contactado',cursor=cursor,actor=actor)
                    self.assertEqual(page['total_items'],211)
                    self.assertEqual(page['totales']['revisiones'],211)
                    self.assertEqual(page['totales']['primera_atencion'],211)
                    self.assertEqual(page['rango']['desde'],len(seen)+1)
                    seen.extend(item['lead_id'] for item in page['items'])
                    self.assertEqual(page['rango']['hasta'],len(seen))
                    self.assertTrue(all(item['bucket']=='revision_comercial' and item['senales']['revisiones'] for item in page['items']))
                    self.assertTrue(all(item['lead']['analista_id']==uid(1) and item['lead']['analista_nombre']=='Analista A' for item in page['items']))
                    pages+=1
                    if not page['hay_mas']:
                        self.assertIsNone(page['cursor_siguiente'])
                        break
                    cursor=page['cursor_siguiente']
                    self.assertIsNotNone(cursor)
                    self.assertLess(pages,10)
                self.assertEqual(seen,sorted(expected))
                self.assertEqual(len(seen),len(set(seen)))
                first=self.queue(signal='revisiones',stage='contactado',actor=actor)
                self.assertEqual([item['lead_id'] for item in first['items']],seen[:50])


    def test_cola_filtros_intersectan_ambito_y_reparto(self):
        self.configured()
        owned=self.lead(first_done=False,limit='2026-09-01T18:00Z')
        foreign=self.lead(stage='nuevo',owner=2,supervisor=None,first_done=False,limit='2026-09-01T18:00Z')
        unassigned=self.lead(stage='nuevo',owner=None,assigned=False,limit='2026-09-01T18:00Z')
        for actor in (1,3):
            result=self.queue(analyst=uid(2),actor=actor)
            self.assertEqual(result['total_items'],0)
            self.assertEqual(result['rango'],{'desde':0,'hasta':0})
            self.assertEqual(sum(result['totales'].values()),0)
        result=self.queue(stage='nuevo',analyst=uid(2),actor=4)
        self.assertEqual([item['lead_id'] for item in result['items']],[foreign['lead']])
        self.assertEqual(result['totales']['primera_atencion'],1)
        self.assertEqual(self.queue(signal='por_repartir',actor=1)['total_items'],0)
        for actor in (3,4,5):
            result=self.queue(signal='por_repartir',actor=actor)
            self.assertEqual([item['lead_id'] for item in result['items']],[unassigned['lead']])
            self.assertIsNone(result['items'][0]['lead']['analista_nombre'])
            self.assertEqual(result['items'][0]['bucket'],'por_repartir')
        # Una señal vacia no reduce los contadores de las otras señales.
        empty=self.queue(signal='tareas_vencidas',analyst=uid(1))
        self.assertEqual(empty['total_items'],0)
        self.assertEqual(empty['totales']['revisiones'],0)
        self.assertEqual(empty['totales']['primera_atencion'],1)
        self.assertIsNone(empty['cursor_siguiente'])
        state=self.json(f"crm.estado_sla_leads_v2_fn({array([owned['lead']])})",1)
        self.assertNotIn('contexto_ambito',state)


if __name__ == '__main__':
    n.BANK = n.Bank()
    try:
        n.BANK.start()
        n.BANK.sql(MIGRATION.read_text(), 'sla_template')
        # Regresion del nucleo junto con los casos nuevos. No hay una segunda
        # implementacion del negocio en los tests: se ejecuta el SQL real.
        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Avisos))
        raise SystemExit(0 if result.wasSuccessful() else 1)
    finally:
        n.BANK.close()

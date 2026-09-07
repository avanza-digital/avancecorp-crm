#!/usr/bin/env python3
"""Regla general de avisos, con SQL real en un PostgreSQL local desechable.
Hereda las regresiones del núcleo y de avisos; conserva sus dobles de autoridad.
--sin-cambio --solo-nuevas demuestra las regresiones con la definición anterior.
"""
import argparse
import datetime as dt
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('avisos', BASE / 'scripts/test-sla-avisos-local.py')
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)
n = a.n
MIGRATION = BASE / 'migrations/20260907194756_crm_sla_primera_atencion_respeta_compromiso.sql'
ROLLBACK = BASE / 'scripts/rollback-sla-primera-compromiso.sql'
SIGNATURE = "'private.sla_operacion_leads(uuid[],boolean,uuid[],timestamptz)'::regprocedure"


class PrimeraCompromiso(a.Avisos):
    def intentada(self, **kwargs):
        l = self.lead(first_done=False, **kwargs)
        # El banco reducido no instala el writer: se cargan sus hechos, nunca
        # un contacto efectivo inventado. Los avisos ejecutan la función real.
        self.sql(f"""update crm.lead_sla_ciclos set primera_gestion_en=iniciado_en
          where lead_id={n.quote(l['lead'])};
          update crm.lead_asignacion_sla_hitos h set primera_gestion_en=b.asignado_en
          from crm.lead_asignaciones b where b.id=h.lead_asignacion_id
          and b.id={n.quote(l['assignment'])};""")
        return l

    def fila(self, l, when=n.NOW):
        return self.json(f"(select to_jsonb(s) from private.sla_operacion_leads({n.array([l['lead']])},true,'{{}}',{n.quote(when)}) s)")

    def test_compromiso_intento_previo_sin_respuesta_espera_tarea(self):
        self.configured()
        l = self.intentada()
        task = self.task(l, '2026-09-07T17:00Z')
        row = self.fila(l)
        self.assertTrue(row['estado']['compromiso']['cobertura_activa'])
        self.assertFalse(row['senales']['primera_atencion'])
        self.assertEqual(row['accion_atencion']['bucket'], 'proxima_tarea')
        self.assertEqual(row['accion_atencion']['tarea_id'], task)
        self.assertNotIn('primera_atencion', self.buckets(row['estado']))
        for field in ('primer_contacto_en', 'asignacion_primer_contacto_en'):
            self.assertIsNone(row['estado']['base'][field])

    def test_compromiso_avisa_al_vencer_sin_exigir_segundo_registro(self):
        self.configured()
        l = self.intentada()
        task = self.task(l, '2026-09-07T17:00Z')
        before = self.fila(l, '2026-09-07T16:59:59.999999Z')
        due = self.fila(l, '2026-09-07T17:00Z')
        self.assertNotIn('primera_atencion', self.buckets(before['estado']))
        self.assertNotIn('tarea_vencida', self.buckets(before['estado']))
        self.assertEqual(self.buckets(due['estado']), ['tarea_vencida'])
        self.assertEqual(due['accion_atencion']['tarea_id'], task)
        self.assertEqual(due['accion_atencion']['bucket'], 'tarea_vencida')
        self.assertTrue(due['estado']['compromiso']['cobertura_activa'])
        # La gracia del seguimiento no posterga la acción de Agenda.
        after = self.fila(l, '2026-09-08T17:00Z')
        self.assertFalse(after['estado']['compromiso']['cobertura_activa'])
        self.assertIn('primera_atencion', self.buckets(after['estado']))
        self.assertIn('tarea_vencida', self.buckets(after['estado']))

    def test_compromiso_agendar_sin_intento_no_oculta_primera_atencion(self):
        self.configured()
        l = self.lead(first_done=False)
        self.task(l, '2026-09-07T17:00Z')
        self.assertIn('primera_atencion', self.buckets(self.core(l)))
        # Gestión anterior del ciclo, pero no del responsable actual.
        self.sql(f"update crm.lead_sla_ciclos set primera_gestion_en=iniciado_en where lead_id={n.quote(l['lead'])};")
        self.assertIn('primera_atencion', self.buckets(self.core(l)))

    def test_compromiso_invalido_no_silencia_atencion(self):
        self.configured()
        for name, params in [
            ('sin_tarea', None), ('cancelada', {'state': 'cancelada'}),
            ('inactiva', {'active': False}), ('administrativa', {'kind': 'tarea'}),
            ('tercera_reprogramacion', {'reprogram': 3}), ('otro_ciclo', {'cycle': 2}),
        ]:
            with self.subTest(name=name):
                l = self.intentada(cycle=1)
                if name == 'otro_ciclo':
                    self.sql(f"insert into crm.lead_sla_ciclos(id,lead_id,ciclo_n,politica_id,iniciado_en) values({n.quote(self.new_id())},{n.quote(l['lead'])},2,{n.quote(n.P1)},'2026-01-01Z');")
                if params is not None:
                    self.task(l, '2026-09-07T17:00Z', **params)
                self.assertIn('primera_atencion', self.buckets(self.core(l)))

    def test_compromiso_tope_y_revision_siguen_vigentes(self):
        self.configured()
        l = self.intentada(limit='2026-08-28T17:00Z')
        self.task(l, '2026-09-07T17:00Z')
        state = self.core(l)
        self.assertFalse(state['compromiso']['cobertura_activa'])
        self.assertIn('primera_atencion', self.buckets(state))
        self.assertIn('revision_comercial', self.buckets(state))

    def test_compromiso_cancelar_reactiva_sin_borrar_historial(self):
        self.configured()
        l = self.intentada()
        task = self.task(l, '2026-09-07T17:00Z')
        before = self.core(l)
        self.assertNotIn('primera_atencion', self.buckets(before))
        self.sql(f"update crm.tareas set estado='cancelada' where id={n.quote(task)};")
        after = self.core(l)
        self.assertIn('primera_atencion', self.buckets(after))
        self.assertEqual(before['base'], after['base'])

    def test_compromiso_ficha_cola_campana_coinciden_en_todos_los_roles(self):
        self.configured()
        clock = n.at(self.json('to_jsonb(statement_timestamp())'))
        l = self.intentada(start=clock-dt.timedelta(days=2), limit=clock+dt.timedelta(days=5))
        self.activity(l, clock-dt.timedelta(hours=1), 'llamada_no_contestada')
        task = self.task(l, clock+dt.timedelta(days=1))
        for actor in (1, 3, 4, 5):
            with self.subTest(actor=actor):
                state = self.json(f"crm.estado_sla_leads_v2_fn({n.array([l['lead']])})", actor)['filas'][0]
                self.assertEqual(self.buckets(state), [])
                self.assertEqual(self.queue(signal='primera_atencion', actor=actor)['total_items'], 0)
                self.assertEqual(self.queue(signal='pendientes', actor=actor)['total_items'], 0)
                self.assertEqual(self.json('crm.avisos_sla_resumen_v2_fn()', actor)['total_avisos'], 0)
                all_actions = self.queue(signal='todas', actor=actor)
                self.assertEqual(all_actions['total_items'], 1)
                self.assertEqual(all_actions['items'][0]['bucket'], 'proxima_tarea')
                self.assertEqual(all_actions['items'][0]['tarea_id'], task)
        self.assertEqual(self.queue(signal='todas', actor=2)['total_items'], 0)

    def test_compromiso_migracion_solo_cambia_decision_y_conserva_contrato(self):
        self.configured()
        l = self.intentada()
        self.task(l, '2026-09-07T17:00Z')
        source = a.MIGRATION.read_text()
        original = source[source.index('create or replace function private.sla_operacion_leads('):
                          source.index('\ncreate or replace function private.sla_operacion_autorizada(')]
        self.sql(original)
        before = self.fila(l)
        metadata = f"(select jsonb_build_array(proowner,proacl,prosecdef,provolatile,proconfig,prorettype,proargtypes) from pg_proc where oid={SIGNATURE})"
        contract = self.json(metadata)
        lectura_v1 = "(select coalesce(jsonb_agg(to_jsonb(v) order by v.lead_id),'[]'::jsonb) from crm.estado_sla_leads_fn() v)"
        v1 = self.json(lectura_v1, 1)
        self.assertEqual(len(v1), 1)
        self.sql(MIGRATION.read_text())
        after = self.fila(l)
        self.assertTrue(before['senales']['primera_atencion'])
        self.assertFalse(after['senales']['primera_atencion'])
        for key in ('base', 'compromiso', 'etapa', 'seguimiento'):
            self.assertEqual(before['estado'][key], after['estado'][key], key)
        self.assertEqual(contract, self.json(metadata))
        self.assertEqual(v1, self.json(lectura_v1, 1))
        self.fails(MIGRATION.read_text(), 'P0001')
        self.sql(ROLLBACK.read_text())
        self.assertEqual(before, self.fila(l))
        self.assertEqual(contract, self.json(metadata))
        self.fails(ROLLBACK.read_text(), 'P0001')
        self.sql(MIGRATION.read_text())
        self.assertEqual(after, self.fila(l))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sin-cambio', action='store_true')
    parser.add_argument('--solo-nuevas', action='store_true')
    args = parser.parse_args()
    n.BANK = n.Bank()
    try:
        n.BANK.start()
        n.BANK.sql(a.MIGRATION.read_text(), 'sla_template')
        if not args.sin_cambio:
            n.BANK.sql(MIGRATION.read_text(), 'sla_template')
        print('Huella función: ' + n.BANK.sql(f'select md5(pg_get_functiondef({SIGNATURE}));', 'sla_template'), flush=True)
        names = unittest.defaultTestLoader.getTestCaseNames(PrimeraCompromiso)
        if args.solo_nuevas:
            names = [name for name in names if name.startswith('test_compromiso_')]
        result = unittest.TextTestRunner(verbosity=2).run(unittest.TestSuite(PrimeraCompromiso(name) for name in names))
        report = {'migracion': MIGRATION.name, 'sha256': hashlib.sha256(MIGRATION.read_bytes()).hexdigest(),
                  'postgres': n.BANK.sql('show server_version;', 'sla_template'),
                  'sin_cambio': args.sin_cambio, 'pruebas': result.testsRun,
                  'fallos': len(result.failures), 'errores': len(result.errors), 'correcto': result.wasSuccessful(),
                  'alcance': 'PostgreSQL aislado; fixtures reducidos de autoridad y hechos. Sin red ni datos de producción.'}
        (n.BANK.root/'resultados.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
        print('Evidencia: '+str(n.BANK.root/'resultados.json'), flush=True)
        raise SystemExit(0 if result.wasSuccessful() else 1)
    finally:
        n.BANK.close()

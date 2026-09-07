#!/usr/bin/env python3
"""N2 sobre clon privado del banco integral PG17: writers/gates reales.

Requiere template ya preparado con N1 y actores 1001/1002/1003/1004/1005.
Nunca acepta URL ni host de red. Cada prueba usa su propia base clonada.
No inicia ni detiene el servidor compartido; solo elimina sus clones propios.
"""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import time
import unittest
import uuid

BASE = Path(__file__).resolve().parents[1]
PG = Path('/opt/homebrew/opt/postgresql@17/bin')
N2 = BASE / 'migrations/20260907024903_crm_sla_nucleo_operativo_escritura.sql'
CIERRE = BASE / 'migrations/20260907031450_crm_sla_cierre_reconstruccion_contextos.sql'
ROLLBACK = BASE / 'scripts/rollback-sla-operacion-hooks.sql'
BANK = None
LEGACY_LEAD = str(uuid.uuid5(uuid.NAMESPACE_URL, 'avancecorp:sla:n2:legacy:lead'))
LEGACY_TASK = str(uuid.uuid5(uuid.NAMESPACE_URL, 'avancecorp:sla:n2:legacy:task'))


def quote(value):
    if value is None:
        return 'null'
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, (dict, list)):
        value = json.dumps(value)
    return "'" + str(value).replace("'", "''") + "'"


def actor(number):
    return str(uuid.UUID('00000000-0000-0000-0000-' + str(number).zfill(12)))


class Bank:
    def __init__(self, socket, template):
        self.socket = socket.resolve()
        if not self.socket.is_relative_to(Path('/private/tmp')) or not self.socket.name.startswith('sla-integracion-'):
            raise ValueError('Solo socket privado de banco sla-integracion en /private/tmp')
        if not template.replace('_', '').isalnum() or not template.startswith('sla_'):
            raise ValueError('Template debe ser una base local sla_*')
        self.template = 'sla_n2_template_' + uuid.uuid4().hex[:10]
        self.env = {key: value for key, value in os.environ.items() if not key.startswith('PG')}
        self.env.update(PGHOST=str(self.socket), PGPORT='55485', PGUSER='postgres', PGDATABASE='postgres', PGCONNECT_TIMEOUT='3')
        self.sql('create database ' + self.template + ' template ' + template + ';', 'postgres')
        try:
            # Un clon cambia de nombre: conserva horarios/comandos reales y
            # adapta solo su direccion local, nunca fabrica ejecuciones cron.
            self.sql('update cron.job set database=current_database();', self.template)
            self.sql("set role authenticated;set request.jwt.claim.sub=" + quote(actor(1004)) + ";" +
                "select crm.crear_lead_si_disponible('PRUEBA SLA LEGACY','+51988888771','oficina',1000,'PEN',p_id=>" +
                quote(LEGACY_LEAD) + ",p_etapa=>'contactado',p_vendedor_id=>" + quote(actor(1001)) + ");" +
                "set request.jwt.claim.sub=" + quote(actor(1001)) + ";" +
                "insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,creado_por) values (" +
                ','.join(map(quote, (LEGACY_TASK, LEGACY_LEAD, 'llamada', 'PRUEBA LEGACY'))) +
                ",clock_timestamp()+interval '1 day'," + quote(actor(1001)) + ');', self.template)
            self.sql(N2.read_text(), self.template)
        except Exception:
            self.sql('drop database ' + self.template + ';', 'postgres')
            raise

    def command(self, sql, db):
        return [str(PG / 'psql'), '-X', '-qAt', '-d', db, '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose', '-c', sql]

    def sql(self, sql, db, error=False):
        result = subprocess.run(self.command(sql, db), env=self.env, text=True,
                                capture_output=True, timeout=45)
        if error:
            return result
        if result.returncode:
            raise AssertionError(result.stderr)
        return result.stdout.strip()

    def close(self):
        self.sql('drop database ' + self.template + ';', 'postgres')


class Operacion(unittest.TestCase):
    def setUp(self):
        self.db = 'sla_n2_case_' + uuid.uuid4().hex[:10]
        BANK.sql('create database ' + self.db + ' template ' + BANK.template + ';', 'postgres')
        BANK.sql('update cron.job set database=current_database();', self.db)

    def tearDown(self):
        BANK.sql('drop database ' + self.db + ';', 'postgres')

    def sql(self, sql):
        return BANK.sql(sql, self.db)

    def auth(self, sql, who=1004):
        return 'set role authenticated; set request.jwt.claim.sub=' + quote(actor(who)) + ';' + sql

    def value(self, expr, who=1004):
        return json.loads(self.sql(self.auth('select ' + expr + ';', who)))

    def reject(self, sql, state, who=1004):
        result = BANK.sql(self.auth(sql, who), self.db, True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(state, result.stderr)

    def config(self):
        return self.value('crm.configuracion_sla_v2_fn()')

    def payload(self, *, extra=11520, base=60):
        rows = [
            ('nuevo', 1440, 1440, 0, 0, 2880, True, 240),
            ('contactado', base, 4320, 5760, 2, extra, True, 1440),
            ('reunion_agendada', 21600, 4320, 0, 0, 4320, True, 2880),
            ('propuesta_enviada', 28800, 7200, 10080, 1, 10080, True, 1440),
        ]
        keys = ('etapa', 'maximo_minutos', 'seguimiento_minutos', 'prorroga_minutos',
                'prorroga_max', 'tope_extra_minutos', 'pausa_habilitada', 'pausa_margen_minutos')
        return dict(zona_horaria='America/Lima', tipo_reloj='corrido', primera_gestion_minutos=120,
                    primer_contacto_minutos=1440, etapas=[dict(zip(keys, row)) for row in rows])

    def publish(self, payload=None):
        version = self.config()['expected_version']
        return self.value('crm.publicar_politica_sla_v2(' + str(version) + ',null,' + quote(payload or self.payload()) + ')')

    def mode(self, mode):
        revision = self.config()['control']['revision']
        return self.value('crm.cambiar_modo_sla_operacion(' + str(revision) + ',' + quote(mode) + ')')

    def ready(self, **kwargs):
        self.publish(self.payload(**kwargs))
        self.mode('activo')

    def lead(self, stage='contactado', owner=1001):
        lead = str(uuid.uuid4())
        phone = '+519' + str(uuid.uuid4().int % 100000000).zfill(8)
        result = self.value("crm.crear_lead_si_disponible('PRUEBA SLA N2'," + quote(phone) + ",'oficina',1000,'PEN',p_id=>" +
                            quote(lead) + ',p_etapa=>' + quote(stage) + ',p_vendedor_id=>' + quote(actor(owner)) + ')')
        self.assertEqual(result['estado'], 'creado')
        return lead

    def activity_sql(self, lead, kind='llamada_realizada', who=1001, activity=None):
        activity = activity or str(uuid.uuid4())
        return self.auth('insert into crm.actividades(id,lead_id,tipo,creado_por) values (' +
                         ','.join(map(quote, (activity, lead, kind, actor(who)))) + ');', who)

    def activity(self, lead, kind='llamada_realizada', who=1001):
        self.sql(self.activity_sql(lead, kind, who))

    def adjustments(self, lead):
        return json.loads(self.sql("select coalesce(jsonb_agg(to_jsonb(j) order by j.secuencia),'[]') from crm.lead_sla_etapa_ajustes j " +
                                   'join crm.lead_sla_etapas e on e.id=j.etapa_sla_id where e.lead_id=' + quote(lead) + ';'))

    def test_instalacion_no_publica_ni_activa(self):
        before = self.config()
        self.assertEqual(before['control']['modo'], 'legado')
        self.assertIsNone(before['control']['primera_activacion_en'])
        self.assertEqual(self.sql('select count(*) from crm.sla_politica_etapas_operacion;'), '0')
        self.assertIn('OK', self.sql('select private.assert_sla_operacion();'))

    def test_inicializacion_aprobada_preserva_primera_atencion_y_no_se_repite(self):
        before = self.config()
        preview = before['inicializacion_aprobada']
        self.assertTrue(preview['disponible'])
        self.assertIsNone(preview['motivo'])
        published = self.value('crm.publicar_reglas_sla_aprobadas_v2(' + str(before['expected_version']) + ')')
        for key in ('primera_gestion_minutos', 'primer_contacto_minutos'):
            self.assertEqual(published['politica']['base'][key], before['vigente']['base'][key])
        self.assertEqual([row['maximo_minutos'] for row in published['politica']['base']['etapas']], [1440, 11520, 21600, 28800])
        self.assertEqual([row['seguimiento_minutos'] for row in published['politica']['operacion']], [1440, 4320, 4320, 7200])
        for row in preview['config']['etapas']:
            stored = next(r for r in published['politica']['operacion'] if r['etapa'] == row['etapa'])
            self.assertEqual(stored, {key: value for key, value in row.items() if key != 'maximo_minutos'})
        self.assertEqual(self.config()['inicializacion_aprobada']['motivo'], 'ya_publicadas')
        self.reject('select crm.publicar_reglas_sla_aprobadas_v2(' + str(published['expected_version']) + ');', '22023')
        self.assertEqual(self.config()['expected_version'], published['expected_version'])
        self.assertEqual(self.config()['control']['modo'], 'legado')

    def test_inicializacion_rechaza_futura_y_actor_no_gerencia(self):
        initial = self.config()['expected_version']
        for who in (1001, 1003, 1005, 1006):
            self.reject('select crm.publicar_reglas_sla_aprobadas_v2(' + str(initial) + ');', '42501', who)
        basic = self.payload()
        basic['etapas'] = [{key: row[key] for key in ('etapa', 'maximo_minutos')} for row in basic['etapas']]
        self.sql(self.auth('select * from crm.publicar_politica_sla(' + str(initial) + ",clock_timestamp()+interval '1 day'," + quote(basic) + ');'))
        self.assertEqual(self.config()['inicializacion_aprobada']['motivo'], 'politica_futura')
        self.reject('select crm.publicar_reglas_sla_aprobadas_v2(' + str(initial+1) + ');', '22023')
        self.assertEqual(self.sql('select count(*) from crm.sla_politica_etapas_operacion;'), '0')

    def test_dos_inicializaciones_concurrentes_publican_una_version(self):
        initial = self.config()['expected_version']
        command = BANK.command(self.auth('select crm.publicar_reglas_sla_aprobadas_v2(' + str(initial) + ');'), self.db)
        processes = [subprocess.Popen(command, env=BANK.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(2)]
        results = [(p.communicate(timeout=15), p.returncode) for p in processes]
        self.assertEqual(sum(code == 0 for _, code in results), 1)
        self.assertIn('P0409', next(result[1] for result, code in results if code != 0))
        self.assertEqual(self.config()['expected_version'], initial+1)
        self.assertEqual(self.sql('select count(*) from crm.sla_politica_etapas_operacion;'), '4')

    def test_actividad_humana_sella_fecha_despues_del_lock(self):
        self.ready()
        lead = self.lead()
        activity = str(uuid.uuid4())
        self.sql(self.auth('insert into crm.actividades(id,lead_id,tipo,creado_por,creado_en) values (' +
            ','.join(map(quote, (activity, lead, 'llamada_realizada', actor(1001)))) + ",clock_timestamp()+interval '1 day');", 1001))
        self.assertEqual(self.sql('select creado_en<=clock_timestamp() and creado_en>clock_timestamp()-interval \'10 seconds\' '
            'from crm.actividades where id=' + quote(activity) + ';'), 't')
        self.assertEqual(len(self.adjustments(lead)), 1)

    def test_publicacion_atomica_y_v1_hereda_reglas(self):
        new = self.publish()
        self.assertEqual(len(new['politica']['operacion']), 4)
        basic = self.payload()
        basic['etapas'] = [{key: row[key] for key in ('etapa', 'maximo_minutos')} for row in basic['etapas']]
        self.sql(self.auth('select * from crm.publicar_politica_sla(' + str(new['expected_version']) + ',null,' + quote(basic) + ');'))
        after = self.config()
        self.assertEqual(new['politica']['operacion'], after['ultima_publicada']['operacion'])
        self.assertEqual(after['expected_version'], new['expected_version'] + 1)

    def test_publicador_rechaza_parcial_y_version_obsoleta_sin_residuos(self):
        before = self.config()
        partial = self.payload()
        partial['etapas'].pop()
        self.reject('select crm.publicar_politica_sla_v2(' + str(before['expected_version']) + ',null,' + quote(partial) + ');', '22023')
        self.assertEqual(before['expected_version'], self.config()['expected_version'])
        self.publish()
        self.reject('select crm.publicar_politica_sla_v2(' + str(before['expected_version']) + ',null,' + quote(self.payload()) + ');', 'P0409')

    def test_configuracion_y_modos_solo_gerencia(self):
        self.publish()
        for who in (1001, 1003, 1005, 1006):
            self.reject("select crm.cambiar_modo_sla_operacion(0,'activo');", '42501', who)
            self.reject('select crm.publicar_politica_sla_v2(1,null,' + quote(self.payload()) + ');', '42501', who)

    def test_adopcion_inmutable_y_revision_optimista(self):
        self.publish()
        first = self.mode('activo')
        self.assertEqual(self.mode('activo'), first)
        self.mode('legado')
        third = self.mode('activo')
        self.assertEqual(first['primera_activacion_en'], third['primera_activacion_en'])
        self.assertEqual(first['politica_adopcion_id'], third['politica_adopcion_id'])
        self.reject("select crm.cambiar_modo_sla_operacion(0,'legado');", 'P0409')

    def test_tarea_captura_ciclo_y_owner_servidor(self):
        self.ready()
        lead = self.lead()
        task = str(uuid.uuid4())
        self.sql(self.auth("insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,creado_por) values (" +
                          ','.join(map(quote, (task, lead, 'llamada', 'PRUEBA SLA',))) + ",clock_timestamp()+interval '1 day'," + quote(actor(1001)) + ');', 1001))
        context = json.loads(self.sql('select to_jsonb(c) from crm.tarea_sla_contexto c where tarea_id=' + quote(task) + ';'))
        self.assertEqual(context['fuente'], 'evento')
        self.assertEqual(context['ciclo_n'], 1)
        self.assertEqual(context['lead_id'], lead)

    def test_reconstruccion_humana_estricta_es_idempotente(self):
        expr = "select to_jsonb(r) from private.sla_reconstruir_contextos_lote(array[" + quote(LEGACY_LEAD) + ']::uuid[]) r;'
        first = json.loads(self.sql(expr))
        self.assertEqual(first['resultado'], 'reconstruido')
        self.assertEqual(first['tarea_id'], LEGACY_TASK)
        self.assertEqual(json.loads(self.sql(expr))['resultado'], 'existente')
        self.assertEqual(self.sql('select fuente from crm.tarea_sla_contexto where tarea_id=' + quote(LEGACY_TASK) + ';'), 'reconstruido')

    def test_writer_interno_captura_contexto_sin_inventar_autor(self):
        lead = self.lead()
        task = str(uuid.uuid4())
        self.sql('insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,vendedor_id) values (' +
            ','.join(map(quote, (task, lead, 'llamada', 'PRUEBA INTERNA'))) + ",clock_timestamp()+interval '1 day'," + quote(actor(1001)) + ');')
        self.assertEqual(self.sql('select c.fuente from crm.tarea_sla_contexto c join crm.tareas t on t.id=c.tarea_id '
            'where c.tarea_id=' + quote(task) + ' and t.creado_por is null;'), 'evento')

    def test_reconstruccion_no_inventa_evidencia_para_alta_interna(self):
        # DDL solo en este clon: representa stock anterior a instalar captura,
        # conserva todos los guards, writers y auditoria reales.
        self.sql('drop trigger trg_tareas_03_sla_contexto on crm.tareas;')
        lead = self.lead()
        task = str(uuid.uuid4())
        self.sql('insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,vendedor_id) values (' +
            ','.join(map(quote, (task, lead, 'llamada', 'PRUEBA INTERNA SIN PRUEBA HUMANA'))) +
            ",clock_timestamp()+interval '1 day'," + quote(actor(1001)) + ');')
        response = json.loads(self.sql('select to_jsonb(r) from private.sla_reconstruir_contextos_lote(array[' + quote(lead) + ']::uuid[]) r;'))
        self.assertEqual(response['resultado'], 'alta_humana_no_demostrable')
        self.assertEqual(self.sql('select count(*) from crm.tarea_sla_contexto where tarea_id=' + quote(task) + ';'), '0')

    def test_cierre_retira_solo_helper_transitorio_y_conserva_contextos(self):
        self.sql('select * from private.sla_reconstruir_contextos_lote(array[' + quote(LEGACY_LEAD) + ']::uuid[]);')
        self.sql(CIERRE.read_text())
        self.assertEqual(self.sql("select to_regprocedure('private.sla_reconstruir_contextos_lote(uuid[])') is null;"), 't')
        self.assertEqual(self.sql('select fuente from crm.tarea_sla_contexto where tarea_id=' + quote(LEGACY_TASK) + ';'), 'reconstruido')
        self.assertIn('OK', self.sql('select private.assert_sla_operacion();'))
        self.ready()

    def test_contingencia_conserva_historia_avance_locks_y_bloquea_reactivacion(self):
        self.ready()
        lead = self.lead()
        self.activity(lead)
        recorded = self.adjustments(lead)
        activation = self.config()['control']['primera_activacion_en']
        rejected = BANK.sql(ROLLBACK.read_text(), self.db, True)
        self.assertNotEqual(rejected.returncode, 0)
        self.assertIn('55000', rejected.stderr)
        self.mode('legado')
        self.sql(ROLLBACK.read_text())
        self.sql(ROLLBACK.read_text())
        self.assertEqual(self.adjustments(lead), recorded)
        self.assertEqual(self.config()['control']['primera_activacion_en'], activation)
        new = self.lead('nuevo')
        self.activity(new)
        self.assertEqual(self.sql('select etapa from crm.leads where id=' + quote(new) + ';'), 'contactado')
        self.assertEqual(self.adjustments(new), [])
        task = str(uuid.uuid4())
        self.sql(self.auth('insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,creado_por) values (' +
            ','.join(map(quote, (task, new, 'llamada', 'PRUEBA DESPUES CONTINGENCIA'))) +
            ",clock_timestamp()+interval '1 day'," + quote(actor(1001)) + ');', 1001))
        self.assertEqual(self.sql('select count(*) from crm.tarea_sla_contexto where tarea_id=' + quote(task) + ';'), '0')
        revision = self.config()['control']['revision']
        for mode in ('activo', 'observacion'):
            self.reject('select crm.cambiar_modo_sla_operacion(' + str(revision) + ',' + quote(mode) + ');', 'P0001')
        self.assertEqual(self.mode('legado')['revision'], revision)

    def test_episodio_historico_no_gana_prorroga(self):
        lead = self.lead()
        self.ready()
        self.activity(lead)
        self.assertEqual(self.adjustments(lead), [])

    def test_misma_etapa_concede_solo_una_vez_y_conserva_historia(self):
        self.ready()
        lead = self.lead()
        before = self.sql('select to_jsonb(e) from crm.lead_sla_etapas e where lead_id=' + quote(lead) + ';')
        self.activity(lead)
        self.activity(lead)
        self.assertEqual(len(self.adjustments(lead)), 1)
        self.assertEqual(self.adjustments(lead)[0]['minutos_reales'], 5760)
        self.assertEqual(before, self.sql('select to_jsonb(e) from crm.lead_sla_etapas e where lead_id=' + quote(lead) + ';'))

    def test_contacto_que_avanza_no_recibe_prorroga(self):
        self.ready()
        lead = self.lead('nuevo')
        self.activity(lead)
        self.assertEqual(self.sql('select etapa from crm.leads where id=' + quote(lead) + ';'), 'contactado')
        self.assertEqual(self.adjustments(lead), [])

    def test_intento_no_concede_y_modos_lectura_no_conceden(self):
        self.publish()
        lead = self.lead()
        self.activity(lead)
        self.mode('observacion')
        self.activity(lead)
        self.assertEqual(self.adjustments(lead), [])
        self.mode('activo')
        self.activity(lead, 'llamada_no_contestada')
        self.assertEqual(self.adjustments(lead), [])

    def test_prorroga_recortada_al_tope(self):
        self.ready(extra=10)
        lead = self.lead()
        self.activity(lead)
        self.activity(lead)
        changes = self.adjustments(lead)
        self.assertEqual(len(changes), 1)
        self.assertEqual(changes[0]['minutos_reales'], 10)

    def test_concurrencia_de_dos_gestiones_no_duplica_presupuesto(self):
        self.ready()
        lead = self.lead()
        processes = [subprocess.Popen(BANK.command(self.activity_sql(lead), self.db), env=BANK.env,
                                     text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(2)]
        for process in processes:
            _, error = process.communicate(timeout=15)
            self.assertEqual(process.returncode, 0, error)
        self.assertEqual(len(self.adjustments(lead)), 1)

    def test_apagado_espera_writer_admitido(self):
        self.ready()
        lead = self.lead()
        body = 'begin;' + self.activity_sql(lead) + "select 'admitido';select pg_sleep(1.2);commit;"
        # stdin entrega cada sentencia por separado: -c con SQL multiple solo
        # permite inspeccionar el ultimo resultado cuando termina la consulta.
        process = subprocess.Popen(BANK.command('', self.db)[:-2], env=BANK.env, text=True,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        process.stdin.write(body + '\n')
        process.stdin.close()
        process.stdin = None
        self.assertEqual(process.stdout.readline().strip(), 'admitido')
        started = time.perf_counter()
        self.mode('legado')
        elapsed = time.perf_counter() - started
        _, error = process.communicate(timeout=15)
        self.assertEqual(process.returncode, 0, error)
        self.assertGreater(elapsed, .7)
        self.activity(lead)
        self.assertEqual(len(self.adjustments(lead)), 1)

    def test_api_no_puede_fabricar_contexto_ni_ajuste_con_settings(self):
        self.ready()
        self.reject("set crm.sla_contexto_writer='reconstruido'; insert into crm.tarea_sla_contexto(tarea_id,lead_id,ciclo_n,fuente) " +
                    "values(gen_random_uuid(),gen_random_uuid(),1,'reconstruido');", '42501', 1001)
        self.reject('select private.sla_reconstruir_contextos_lote(array[gen_random_uuid()]);', '42501', 1004)
        self.reject('select private.sla_conceder_prorroga(gen_random_uuid(),gen_random_uuid());', '42501', 1004)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--socket', type=Path, required=True)
    parser.add_argument('--template', required=True)
    parser.add_argument('--output', type=Path, required=True)
    options = parser.parse_args()
    started = time.perf_counter()
    BANK = Bank(options.socket, options.template)
    try:
        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Operacion))
        report = dict(pruebas=result.testsRun, fallos=len(result.failures), errores=len(result.errors),
                      segundos=round(time.perf_counter()-started, 3), banco='PG17 integral local con helpers reales',
                      migracion=str(N2), correcta=result.wasSuccessful())
        options.output.parent.mkdir(parents=True, exist_ok=True)
        options.output.write_text(json.dumps(report, indent=2) + '\n')
    finally:
        BANK.close()
    raise SystemExit(0 if result.wasSuccessful() else 1)

#!/usr/bin/env python3
"""Prueba la migracion REAL en PostgreSQL 16/17 aislado; sin red ni credenciales.
Banco reducido: columnas y v1 reales, dobles explicitos de autoridad/veto.
Cada caso clona una base plantilla propia. Nunca acepta una URL externa.
"""
import datetime as dt
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
import uuid

BASE = Path(__file__).resolve().parents[1]
FIX = BASE / 'tests/sla-nucleo'
MIGRATION = BASE / 'migrations/20260907001024_crm_sla_nucleo_operativo_lectura.sql'
MIGRATION_TEXT = MIGRATION.read_text()
PG = Path(os.environ.get('SLA_PG_BIN', '/opt/homebrew/opt/postgresql@16/bin'))
NOW = '2026-09-06T17:00:00+00:00'
P1 = '10000000-0000-0000-0000-000000000001'
P2 = '10000000-0000-0000-0000-000000000002'
P3 = '10000000-0000-0000-0000-000000000003'
ACT = '2026-09-01T00:00:00+00:00'

def uid(n):
    return str(uuid.UUID(int=n))

def quote(value):
    if value is None:
        return 'null'
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, int):
        return str(value)
    return "'" + str(value).replace("'", "''") + "'"

def array(values):
    return 'null::uuid[]' if values is None else 'array[' + ','.join(map(quote, values)) + ']::uuid[]'

def at(value):
    if value is None:
        return None
    value=value.replace('Z', '+00:00')
    # Python 3.9 solo acepta fracciones de 3/6 digitos; PostgreSQL puede omitir
    # ceros finales. Rellenar conserva exactamente el instante del servidor.
    value=re.sub(r'\.(\d+)(?=[+-]\d\d:\d\d$)',lambda m:'.'+m.group(1).ljust(6,'0'),value)
    return dt.datetime.fromisoformat(value)

class Bank:
    def __init__(self):
        self.root = Path(tempfile.mkdtemp(prefix='sla-nucleo-'))
        self.running = False
        # Sockets solo en esta carpeta privada; se ignoran PGHOST/PGDATABASE del entorno.
        self.env = {k: v for k, v in os.environ.items() if not k.startswith('PG')}
        self.env.update(PGHOST=str(self.root), PGPORT='55483', PGUSER='sla_test_owner', PGDATABASE='postgres', PGCONNECT_TIMEOUT='3')

    def command(self, name, args, **kwargs):
        return subprocess.run([str(PG / name), *args], env=self.env, text=True,
                              capture_output=True, timeout=45, **kwargs)

    def start(self):
        version = self.command('postgres', ['--version'])
        if version.returncode or not any(f' {major}.' in version.stdout for major in (16, 17)):
            raise RuntimeError('Se requiere PostgreSQL 16 o 17 (SLA_PG_BIN)')
        result = self.command('initdb', ['-D', str(self.root / 'data'), '-U', 'sla_test_owner', '-A', 'trust', '--no-locale', '-E', 'UTF8'])
        if result.returncode:
            raise RuntimeError(result.stderr)
        result = self.command('pg_ctl', ['-D', str(self.root / 'data'), '-l', str(self.root / 'postgres.log'), '-o',
                              f"-k {self.root} -p 55483 -c listen_addresses='' -c timezone=UTC -c max_connections=20", '-w', 'start'])
        if result.returncode:
            raise RuntimeError(result.stderr + (self.root / 'postgres.log').read_text())
        self.running = True
        self.sql('create database sla_template;')
        self.sql((FIX / 'base.sql').read_text(), 'sla_template')
        self.sql((FIX / 'estado-v1-anterior.sql').read_text(), 'sla_template')
        self.sql((FIX / 'censo-real.sql').read_text(), 'sla_template')
        self.sql('revoke all on function crm.estado_sla_leads_fn() from public; grant execute on function crm.estado_sla_leads_fn() to authenticated;', 'sla_template')
        self.sql(MIGRATION_TEXT, 'sla_template')

    def sql(self, sql, db='postgres', error=False):
        r = self.command('psql', ['-X', '-qAt', '-d', db, '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose'], input=sql)
        if error:
            return r
        if r.returncode:
            raise AssertionError(r.stderr)
        return r.stdout.strip()

    def close(self):
        if self.running:
            result = self.command('pg_ctl', ['-D', str(self.root / 'data'), '-m', 'fast', '-w', 'stop'])
            if result.returncode:
                raise RuntimeError(result.stderr)
            self.running = False

BANK = None

class Nucleo(unittest.TestCase):
    def setUp(self):
        self.db = 'sla_case_' + uuid.uuid4().hex[:12]
        BANK.sql(f'create database {self.db} template sla_template;')
        self.ids = []
        self.sequence = 10000

    def tearDown(self):
        BANK.sql(f'drop database {self.db};')

    def sql(self, text):
        return BANK.sql(text, self.db)

    def json(self, expression, actor=None, role='authenticated'):
        pre = '' if actor is None else f'set role {role}; set request.jwt.claim.sub={quote(uid(actor))};'
        return json.loads(self.sql(pre + f'select {expression};'))

    def fails(self, text, code, actor=None, role='authenticated'):
        pre = '' if actor is None else f'set role {role}; set request.jwt.claim.sub={quote(uid(actor))};'
        result = BANK.sql(pre + text, self.db, error=True)
        self.assertNotEqual(result.returncode, 0, 'Se acepto una entrada invalida')
        self.assertIn(code, result.stderr)

    def new_id(self):
        self.sequence += 1
        return uid(self.sequence)

    def rules(self, policy=P2, follow=4320, extra=11520, margin=1440):
        self.sql(f"""insert into crm.sla_politica_etapas_operacion values
          ({quote(policy)},'nuevo',1440,0,0,2880,true,240),
          ({quote(policy)},'contactado',{follow},5760,2,{extra},true,{margin}),
          ({quote(policy)},'reunion_agendada',4320,0,0,4320,true,2880),
          ({quote(policy)},'propuesta_enviada',7200,10080,1,10080,true,1440);""")

    def activate(self, mode='activo', policy=P2, instant=ACT):
        self.sql(f"""update crm.sla_operacion_control set modo={quote(mode)}, revision=revision+1,
          primera_activacion_en={quote(instant)},politica_adopcion_id={quote(policy)},cambiado_por={quote(uid(4))};""")

    def configured(self):
        self.rules()
        self.activate()

    def lead(self, *, stage='contactado', owner=1, supervisor=3, start='2026-09-01T17:00Z',
             assignment=None, limit='2026-09-09T17:00Z', policy=P2, cycle=1,
             photo=True, assigned=True, active=True, first_done=True):
        lead, cyc, ass, hit, ep = [self.new_id() for _ in range(5)]
        self.sql(f"insert into crm.leads values({quote(lead)},'Lead sintetico',{quote(active)},{quote(stage)},{quote(uid(owner) if owner else None)},{quote(uid(supervisor) if supervisor else None)},{quote(start)},{cycle});")
        if photo:
            done = quote(start if first_done else None)
            self.sql(f"""insert into crm.lead_sla_ciclos values({quote(cyc)},{quote(lead)},{cycle},{quote(policy)},{quote(start)},
              {quote(start)}::timestamptz+interval '2 hours',{done},{quote(start)}::timestamptz+interval '1 day',{done},false);
              insert into crm.lead_sla_etapas values({quote(ep)},{quote(lead)},{cycle},1,{quote(stage)},{quote(policy)},
              {quote(start)},{quote(limit)},null,false);""")
        if assigned:
            assign = assignment or start
            self.sql(f"""insert into crm.lead_asignaciones values({quote(ass)},{quote(lead)},{cycle},1,{quote(uid(owner) if owner else None)},
              {quote(assign)},null,{quote(policy)},{quote(assign)}::timestamptz+interval '2 hours',{quote(assign)}::timestamptz+interval '1 day');
              insert into crm.lead_asignacion_sla_hitos values({quote(hit)},{quote(ass)},{quote(assign if first_done else None)},{quote(assign if first_done else None)});""")
        self.ids.append(lead)
        return dict(lead=lead, cycle=cycle, episode=ep, assignment=ass)

    def activity(self, l, when, kind='llamada_realizada', actor=1):
        id_ = self.new_id()
        self.sql(f'insert into crm.actividades values({quote(id_)},{quote(l["lead"])},{quote(kind)},{quote(when)},{quote(uid(actor) if actor else None)});')
        return id_

    def task(self, l, due, *, kind='llamada', owner=1, supervisor=3, reprogram=0, context=True,
             cycle=None, state='pendiente', active=True):
        id_ = self.new_id()
        self.sql(f"""insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,reprogramaciones,vendedor_id,asignado_supervisor_id,creado_por,activo,estado)
          values({quote(id_)},{quote(l['lead'])},{quote(kind)},'Compromiso',{quote(due)},{reprogram},{quote(uid(owner) if owner else None)},
          {quote(uid(supervisor) if supervisor else None)},{quote(uid(1))},{quote(active)},{quote(state)});""")
        if context:
            self.sql(f"insert into crm.tarea_sla_contexto(tarea_id,lead_id,ciclo_n,fuente) values({quote(id_)},{quote(l['lead'])},{cycle or l['cycle']},'evento');")
        return id_

    def core(self, l, when=NOW):
        return self.json(f"(select estado from private.sla_operacion_leads({array([l['lead']])},true,'{{}}'::uuid[],{quote(when)}))")

    def extension(self, **kw):
        args = dict(stage='contactado', kind='llamada_realizada', actor=uid(1), same=True,
                    mode='activo', activation=ACT, event=NOW, limit='2026-09-07T17:00Z',
                    cap='2026-09-15T17:00Z', duration=5760, maximum=2, used=0, adjusted=False)
        args.update(kw)
        return self.json('(select to_jsonb(p) from private.sla_evaluar_prorroga(' + ','.join(map(quote, args.values())) + ') p)')

    def test_migracion_inicia_legado_sin_capturas(self):
        self.assertEqual(self.json('(select to_jsonb(c) from crm.sla_operacion_control c)')['modo'], 'legado')
        self.assertEqual(self.sql('select count(*) from crm.sla_politica_etapas_operacion;'), '0')
        l = self.lead()
        s = self.core(l)
        self.assertIsNone(s['seguimiento']['vencido'])
        self.assertIsNone(s['compromiso']['cobertura_activa'])
        self.assertIn('operacion_no_activada', s['motivos_datos'])

    def test_paridad_v1_por_rol_y_fotos(self):
        self.lead()
        self.lead(owner=2, supervisor=None, policy=P1)
        self.lead(owner=None, assigned=False)
        self.lead(photo=False)
        self.lead(active=False)
        self.lead(stage='convertido')
        new = self.sql("select pg_get_functiondef('crm.estado_sla_leads_fn()'::regprocedure);")
        acl = self.sql("select proacl::text from pg_proc where oid='crm.estado_sla_leads_fn()'::regprocedure;")
        expr = "(select coalesce(jsonb_agg(to_jsonb(s) order by s.lead_id),'[]') from crm.estado_sla_leads_fn() s)"
        after = {a: self.json(expr,a) for a in range(1,6)}
        self.sql((FIX / 'estado-v1-anterior.sql').read_text())
        for actor in range(1,6):
            self.assertEqual(after[actor], self.json(expr,actor), f'actor {actor}')
        self.sql(new + ';')
        self.assertEqual(acl,self.sql("select proacl::text from pg_proc where oid='crm.estado_sla_leads_fn()'::regprocedure;"))
        for l in after[4]:
            state = self.json(f"crm.estado_sla_leads_v2_fn({array([l['lead_id']])})",4)['filas'][0]
            self.assertEqual(l,state['base'])

    def test_puertas_respetan_ambito_y_cero_ids(self):
        a,b,unassigned = self.lead(),self.lead(owner=2,supervisor=None),self.lead(owner=None,assigned=False)
        expr=f'crm.estado_sla_leads_v2_fn({array(self.ids)})'
        self.assertEqual([s['lead_id'] for s in self.json(expr,1)['filas']],[a['lead']])
        self.assertEqual(len(self.json(expr,3)['filas']),2)
        self.assertEqual(len(self.json(expr,5)['filas']),3)
        self.assertEqual(self.json('crm.estado_sla_leads_v2_fn(array[]::uuid[])',4)['filas'],[])
        for actor in (6,7):
            self.fails(f'select {expr};','42501',actor)
            self.fails('select * from crm.estado_sla_leads_fn();','42501',actor)
        self.fails(f'set role authenticated; select {expr};','42501')
        self.fails(f'select {expr};','42501',1,'anon')

    def test_validacion_de_entradas_y_core_privado(self):
        self.fails('select crm.estado_sla_leads_v2_fn(null);','22023',1)
        self.fails('select crm.estado_sla_leads_v2_fn(array[null]::uuid[]);','22023',1)
        self.fails(f'select crm.estado_sla_leads_v2_fn(array_fill({quote(uid(1))}::uuid,array[201]));','22023',1)
        for n in ('null','0','201'):
            self.fails(f'select crm.cola_accion_v2_fn({n});','22023',1)
        self.fails(f"select * from private.sla_operacion_leads(null,true,'{{}}',{quote(NOW)});",'42501',1)
        for role in ('authenticated','anon','service_role'):
            self.fails('select * from crm.sla_operacion_control;','42501',1,role)
        self.fails("select * from private.sla_operacion_leads(null,true,'{}','infinity');",'22023')

    def test_gestion_ignora_notas_y_respeta_ciclo_y_tenencia(self):
        self.configured()
        l=self.lead(assignment='2026-09-04T17:00Z')
        self.activity(l,'2026-09-03T17:00Z')
        self.activity(l,'2026-09-05T17:00Z','nota')
        s=self.core(l)
        self.assertEqual(at(s['seguimiento']['referencia_en']),at('2026-09-04T17:00Z'))
        self.assertIsNone(s['seguimiento']['ultima_gestion_en'])
        self.activity(l,'2026-09-06T12:00Z','llamada_no_contestada',3)
        s=self.core(l)
        self.assertEqual(s['seguimiento']['autor_id'],uid(3))
        self.assertEqual(s['seguimiento']['ultima_gestion_tipo'],'llamada_no_contestada')
        self.activity(l,'2026-09-07T12:00Z')
        self.assertEqual(s['seguimiento'],self.core(l)['seguimiento'])

    def test_cinco_tipos_de_gestion_validos(self):
        self.configured()
        for kind in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada'):
            l=self.lead()
            self.activity(l,'2026-09-06T12:00Z',kind)
            self.assertEqual(self.core(l)['seguimiento']['ultima_gestion_tipo'],kind)

    def test_activacion_no_crea_mora_retroactiva(self):
        self.rules()
        self.activate(instant='2026-09-06T17:00Z')
        l=self.lead(start='2026-01-01T00:00Z')
        s=self.core(l,'2026-09-06T16:59Z')
        self.assertFalse(s['seguimiento']['vencido'])
        self.assertEqual(at(s['seguimiento']['limite_en']),at(NOW))
        self.assertTrue(self.core(l)['seguimiento']['vencido'])

    def test_observacion_es_hipotetica_y_no_escribe(self):
        self.rules()
        self.sql("update crm.sla_operacion_control set modo='observacion',revision=revision+1;")
        l=self.lead()
        result=self.json(f"crm.estado_sla_leads_v2_fn({array([l['lead']])})",1)
        self.assertIsNone(result['primera_activacion_en'])
        self.assertEqual(result['calculado_en'],result['activacion_hipotetica_en'])
        self.assertEqual(self.sql('select count(*) from crm.lead_sla_etapa_ajustes;'),'0')

    def test_compromiso_vencido_no_se_salta_a_futuro(self):
        self.configured()
        l=self.lead()
        old=self.task(l,'2026-09-04T17:00Z')
        self.task(l,'2026-09-08T17:00Z')
        s=self.core(l)
        self.assertEqual(s['compromiso']['tarea']['id'],old)
        self.assertFalse(s['compromiso']['cobertura_activa'])
        self.assertTrue(s['seguimiento']['accion_pendiente'])

    def test_tarea_ambigua_bloquea_todas_las_coberturas(self):
        self.configured()
        l=self.lead()
        self.task(l,'2026-09-04T17:00Z',context=False)
        self.task(l,'2026-09-08T17:00Z')
        s=self.core(l)
        self.assertEqual(s['compromiso']['validez'],'datos_incompletos')
        self.assertIsNone(s['compromiso']['tarea'])
        self.assertIsNone(s['compromiso']['cobertura_activa'])
        self.assertTrue(s['seguimiento']['accion_pendiente'])
        self.assertIsNone(s['etapa']['limite_operativo_en'])
        self.assertIsNone(s['etapa']['revision_requerida'])

    def test_tarea_de_ciclo_anterior_bloquea_cobertura(self):
        self.configured()
        l=self.lead(cycle=2)
        self.sql(f"insert into crm.lead_sla_ciclos(id,lead_id,ciclo_n,politica_id,iniciado_en) values({quote(self.new_id())},{quote(l['lead'])},1,{quote(P1)},'2026-01-01Z');")
        self.task(l,'2026-09-04T17:00Z',cycle=1)
        self.task(l,'2026-09-08T17:00Z')
        s=self.core(l)
        self.assertIn('tarea_ciclo_anterior_pendiente',s['motivos_datos'])
        self.assertIsNone(s['compromiso']['cobertura_activa'])

    def test_tenencia_de_tarea_incoherente_e_infinito(self):
        self.configured()
        for due,owner,reason in [('2026-09-08T17:00Z',2,'tenencia_tarea_incoherente'),('infinity',1,'fecha_tarea_invalida')]:
            l=self.lead()
            self.task(l,due,owner=owner)
            self.assertIn(reason,self.core(l)['motivos_datos'])
            self.assertIsNone(self.core(l)['compromiso']['cobertura_activa'])

    def test_empate_de_tareas_ordenado_por_id(self):
        self.configured()
        l=self.lead()
        first=self.task(l,'2026-09-08T17:00Z')
        self.task(l,'2026-09-08T17:00Z')
        self.assertEqual(self.core(l)['compromiso']['tarea']['id'],first)

    def test_tercera_reprogramacion_no_cubre_y_pide_revision(self):
        self.configured()
        l=self.lead()
        t=self.task(l,'2026-09-08T17:00Z',reprogram=3)
        s=self.core(l)
        self.assertEqual(s['compromiso']['tarea']['id'],t)
        self.assertFalse(s['compromiso']['cobertura_activa'])
        self.assertTrue(s['etapa']['revision_requerida'])
        self.assertIn('reprogramaciones_agotadas',s['etapa']['motivos_revision'])

    def test_cobertura_vence_en_limite_sin_retroceder_plazo(self):
        self.configured()
        l=self.lead(limit='2026-09-05T17:00Z')
        self.task(l,'2026-09-06T17:00Z')
        a=self.core(l,'2026-09-07T16:59:59Z')
        b=self.core(l,'2026-09-07T17:00:00Z')
        self.assertTrue(a['compromiso']['cobertura_activa'])
        self.assertFalse(b['compromiso']['cobertura_activa'])
        self.assertEqual(a['etapa']['limite_operativo_en'],b['etapa']['limite_operativo_en'])
        self.assertTrue(b['etapa']['revision_requerida'])
        self.assertTrue(a['etapa']['fuera_plazo'])

    def test_cobertura_y_limite_nunca_superan_techo(self):
        self.configured()
        l=self.lead(limit='2026-09-01T17:00Z')
        self.task(l,'2026-10-01T17:00Z')
        s=self.core(l)
        self.assertEqual(s['etapa']['limite_operativo_en'],s['etapa']['techo_en'])
        self.assertEqual(s['compromiso']['hasta_en'],s['etapa']['techo_en'])
        self.assertEqual(at(s['etapa']['techo_en']),at('2026-09-09T17:00Z'))

    def test_techo_agotado_pide_revision_aun_con_datos_incompletos(self):
        self.configured()
        l=self.lead(limit='2026-08-01T17:00Z')
        self.task(l,'2026-09-08T17:00Z',context=False)
        s=self.core(l)
        self.assertIsNone(s['etapa']['limite_operativo_en'])
        self.assertTrue(s['etapa']['revision_requerida'])

    def test_tarea_administrativa_no_concede_cobertura(self):
        self.configured()
        l=self.lead()
        self.task(l,'2026-09-08T17:00Z',kind='otro',context=False)
        s=self.core(l)
        self.assertEqual(s['compromiso']['validez'],'sin_tarea')
        self.assertFalse(s['compromiso']['cobertura_activa'])
        self.assertTrue(s['seguimiento']['accion_pendiente'])

    def test_cerradas_e_inactivas_no_cubren(self):
        self.configured()
        l=self.lead()
        self.task(l,'2026-09-08T17:00Z',state='completada')
        self.task(l,'2026-09-08T17:00Z',active=False)
        self.assertEqual(self.core(l)['compromiso']['validez'],'sin_tarea')

    def test_cambio_politica_no_mueve_techo_de_episodio_ni_legado(self):
        self.configured()
        versioned=self.lead()
        legacy=self.lead(policy=P1)
        before=[self.core(x)['etapa'] for x in (versioned,legacy)]
        self.sql(f"insert into crm.sla_politicas values({quote(P3)},3,'2026-09-05Z'); insert into crm.sla_politica_etapas(politica_id,etapa,maximo_minutos) select {quote(P3)},etapa,maximo_minutos from crm.sla_politica_etapas where politica_id={quote(P2)};")
        self.rules(P3,follow=60,extra=4320,margin=60)
        after=[self.core(x)['etapa'] for x in (versioned,legacy)]
        self.assertEqual([x['techo_en'] for x in before],[x['techo_en'] for x in after])
        self.assertEqual(after[0]['techo_origen'],'episodio')
        self.assertEqual(after[1]['techo_origen'],'adopcion')
        self.assertEqual(after[1]['prorrogas_restantes'],0)
        self.assertEqual(self.core(versioned)['seguimiento']['umbral_minutos'],60)

    def test_politica_parcial_no_se_completa_con_otra_version(self):
        self.configured()
        l=self.lead()
        self.sql(f"insert into crm.sla_politicas values({quote(P3)},3,'2026-09-05Z');")
        s=self.core(l)
        self.assertIn('politica_operativa_ausente',s['motivos_datos'])
        self.assertIsNone(s['seguimiento']['umbral_minutos'])
        self.assertIsNone(s['seguimiento']['vencido'])

    def test_reingreso_tres_es_por_etapa_y_ciclo(self):
        self.configured()
        l=self.lead()
        for n in (2,3):
            self.sql(f"insert into crm.lead_sla_etapas values({quote(self.new_id())},{quote(l['lead'])},1,{n},'contactado',{quote(P2)},'2026-08-01Z','2026-08-09Z','2026-08-02Z',false);")
        s=self.core(l)
        self.assertTrue(s['etapa']['revision_requerida'])
        self.assertIn('reingreso_etapa',s['etapa']['motivos_revision'])
        fresh=self.lead(cycle=2)
        self.sql(f"insert into crm.lead_sla_etapas values({quote(self.new_id())},{quote(fresh['lead'])},1,3,'contactado',{quote(P2)},'2026-08-01Z','2026-08-09Z','2026-08-02Z',false);")
        self.assertEqual(self.core(fresh)['etapa']['episodios_en_ciclo'],1)

    def test_terminal_veto_y_sin_foto_son_distintos(self):
        self.configured()
        terminal=self.lead(stage='convertido')
        veto=self.lead()
        self.sql(f"insert into fixture.vetos values({quote(veto['lead'])});")
        missing=self.lead(photo=False)
        for l in (terminal,veto):
            s=self.core(l)
            self.assertEqual(s['evaluacion'],'no_aplica')
            self.assertIsNone(s['seguimiento']['accion_pendiente'])
            self.assertIsNone(s['etapa']['revision_requerida'])
        self.assertEqual(self.core(missing)['evaluacion'],'parcial')
        self.assertIn('sin_foto_sla',self.core(missing)['motivos_datos'])
        inactive=self.lead(active=False)
        s=self.json(f"crm.estado_sla_leads_v2_fn({array([inactive['lead']])})",1)['filas'][0]
        self.assertEqual(s['evaluacion'],'no_aplica')
        self.assertIn('lead_inactivo',s['motivos_datos'])
        self.assertIsNone(s['seguimiento']['accion_pendiente'])

    def test_sin_asignacion_no_inventa_seguimiento(self):
        self.configured()
        l=self.lead(owner=None,assigned=False)
        s=self.core(l)
        self.assertIsNone(s['seguimiento']['referencia_en'])
        self.assertIsNone(s['seguimiento']['vencido'])
        self.assertIn('sin_asignacion',s['motivos_datos'])
        row=self.json(f"(select accion_supervision from private.sla_operacion_leads({array([l['lead']])},true,'{{}}',{quote(NOW)}))")
        self.assertEqual(row['bucket'],'por_repartir')

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
        self.assertEqual(q['totales']['revisiones'],1)
        self.assertEqual(q['items'][0]['bucket'],'primera_atencion')
        states={s['lead_id']:s for s in result['estado']['filas']}
        self.assertEqual(q['items'][0]['estado'],states[q['items'][0]['lead_id']])
        self.assertEqual(q['calculado_en'],result['estado']['calculado_en'])

    def queue(self, *, signal='todas', stage=None, analyst=None, cursor=None, limit=50, actor=1):
        encoded=None if cursor is None else json.dumps(cursor)
        return self.json(f"crm.cola_accion_v2_fn({limit},{quote(signal)},{quote(stage)},{quote(analyst)},{quote(encoded)}::jsonb)",actor)

    def test_cola_paginada_recupera_mas_de_200_revisiones_solapadas(self):
        self.configured()
        expected=[self.lead(first_done=False,limit='2026-09-01T18:00Z')['lead'] for _ in range(211)]
        self.lead(stage='propuesta_enviada',owner=2,supervisor=None,first_done=False,limit='2026-09-01T18:00Z')
        # Con datos y fronteras temporales estables, recorrer todas las paginas
        # debe conservar pertenencia, orden y ausencia de duplicados.
        for actor in (1,3,4,5):
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
                    self.assertTrue(all(item['bucket']=='primera_atencion' and item['senales']['revisiones'] for item in page['items']))
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
        self.assertEqual(empty['totales']['revisiones'],1)
        self.assertEqual(empty['totales']['primera_atencion'],1)
        self.assertIsNone(empty['cursor_siguiente'])
        state=self.json(f"crm.estado_sla_leads_v2_fn({array([owned['lead']])})",1)
        self.assertNotIn('contexto_ambito',state)

    def test_cola_cursor_rechaza_otro_contexto_y_datos_invalidos(self):
        self.configured()
        self.lead(first_done=False);self.lead(first_done=False)
        cursor=self.queue(limit=1)['cursor_siguiente']
        encoded=quote(json.dumps(cursor))+'::jsonb'
        for call,actor in [
            (f"crm.cola_accion_v2_fn(1,'revisiones',null,null,{encoded})",1),
            (f"crm.cola_accion_v2_fn(1,'todas','contactado',null,{encoded})",1),
            (f"crm.cola_accion_v2_fn(1,'todas',null,{quote(uid(1))},{encoded})",1),
            (f"crm.cola_accion_v2_fn(2,'todas',null,null,{encoded})",1),
            (f"crm.cola_accion_v2_fn(1,'todas',null,null,{encoded})",4),
        ]:
            self.fails(f'select {call};','22023',actor)
        for value in [[],{},dict(cursor,version=2),dict(cursor,prioridad=-1),dict(cursor,prioridad=1.5),
                      dict(cursor,referencia_en='infinity'),dict(cursor,referencia_en='no-es-fecha'),
                      dict(cursor,lead_id='no-es-uuid'),dict(cursor,ahora='2020-01-01')]:
            self.fails(f"select crm.cola_accion_v2_fn(1,'todas',null,null,{quote(json.dumps(value))}::jsonb);",'22023',1)
        for signal,stage in [('inexistente',None),(None,None),('todas','convertido')]:
            self.fails(f"select crm.cola_accion_v2_fn(1,{quote(signal)},{quote(stage)});",'22023',1)
        self.sql('update crm.sla_operacion_control set revision=revision+1;')
        self.fails(f"select crm.cola_accion_v2_fn(1,'todas',null,null,{encoded});",'22023',1)
        refreshed=self.queue(limit=1)['cursor_siguiente']
        self.sql(f"insert into fixture.ambito values({quote(uid(1))},{quote(uid(2))});")
        self.fails(f"select crm.cola_accion_v2_fn(1,'todas',null,null,{quote(json.dumps(refreshed))}::jsonb);",'22023',1)

    def test_regla_prorroga_limites_ventana_y_ganancia_parcial(self):
        r=self.extension()
        self.assertTrue(r['elegible'])  # exactamente limite - 24h
        self.assertEqual(r['minutos_reales'],5760)
        self.assertFalse(self.extension(event='2026-09-06T16:59:59Z')['elegible'])
        self.assertFalse(self.extension(event='2026-09-07T17:00:00Z')['elegible'])
        self.assertFalse(self.extension(event='2026-09-08T17:00:00Z')['elegible'])
        r=self.extension(cap='2026-09-07T18:00Z')
        self.assertEqual(r['minutos_reales'],60)
        self.assertEqual(at(r['limite_despues']),at('2026-09-07T18:00Z'))

    def test_regla_prorroga_solo_conversacion_humana_mismo_episodio(self):
        for kind in ('llamada_no_contestada','whatsapp_enviado','nota'):
            self.assertEqual(self.extension(kind=kind)['motivo'],'sin_conversacion')
        for kind in ('llamada_realizada','whatsapp_recibido','reunion_realizada'):
            self.assertTrue(self.extension(kind=kind)['elegible'])
        for kw,reason in [({'actor':None},'sin_autor_humano'),({'same':False},'episodio_distinto'),
                          ({'mode':'observacion'},'modo_no_activo'),({'mode':'legado'},'modo_no_activo'),
                          ({'stage':'nuevo'},'etapa_sin_prorroga'),({'stage':'reunion_agendada'},'etapa_sin_prorroga'),
                          ({'adjusted':True},'evento_ya_ajustado'),({'used':2},'presupuesto_agotado'),
                          ({'activation':'2026-09-07Z'},'evento_anterior_activacion')]:
            self.assertEqual(self.extension(**kw)['motivo'],reason)

    def test_prorroga_no_permite_doble_ganancia_inmediata(self):
        first=self.extension()
        self.assertFalse(self.extension(limit=first['limite_despues'],used=1)['elegible'])
        self.fails(f"select * from private.sla_evaluar_prorroga('contactado','llamada_realizada',{quote(uid(1))},true,'activo',{quote(ACT)},{quote(NOW)},'2026-09-07Z','2026-09-15Z',1440,2,0,false);",'22023')

    def test_reglas_inmutables_y_adopcion_fija_auditadas(self):
        self.configured()
        self.fails("update crm.sla_politica_etapas_operacion set seguimiento_minutos=30;",'55000')
        self.fails("delete from crm.sla_politica_etapas_operacion;",'55000')
        self.fails("truncate crm.sla_politica_etapas_operacion;",'55000')
        self.fails("update crm.sla_operacion_control set primera_activacion_en='2026-08-01Z',revision=revision+1;",'55000')
        self.fails("update crm.sla_operacion_control set modo='legado';",'55000')
        self.assertEqual(self.sql("select count(*) from public.audit_log where tabla='crm.sla_politica_etapas_operacion';"),'4')
        self.assertEqual(self.sql("select count(*) from public.audit_log where tabla='crm.sla_operacion_control';"),'2')

    def test_contexto_no_acepta_lead_ajeno_y_no_se_reescribe(self):
        l,other=self.lead(),self.lead()
        t=self.task(l,'2026-09-08Z',context=False)
        self.fails(f"insert into crm.tarea_sla_contexto(tarea_id,lead_id,ciclo_n,fuente) values({quote(t)},{quote(other['lead'])},1,'evento');",'23514')
        self.sql(f"insert into crm.tarea_sla_contexto(tarea_id,lead_id,ciclo_n,fuente) values({quote(t)},{quote(l['lead'])},1,'evento');")
        self.fails('update crm.tarea_sla_contexto set fuente=fuente;','55000')

    def test_ajuste_con_causa_preserva_limite_original(self):
        self.configured()
        l=self.lead(limit='2026-09-07T17:00Z')
        a=self.activity(l,NOW)
        self.sql(f"""insert into crm.lead_sla_etapa_ajustes(etapa_sla_id,origen_actividad_id,secuencia,minutos_reales,limite_antes,limite_despues,creado_por)
          values({quote(l['episode'])},{quote(a)},1,5760,'2026-09-07T17:00Z','2026-09-11T17:00Z',{quote(uid(1))});""")
        s=self.core(l)
        self.assertEqual(s['etapa']['minutos_prorrogados'],5760)
        self.assertEqual(at(s['base']['etapa_limite_en']),at('2026-09-07T17:00Z'))
        self.assertEqual(at(s['etapa']['limite_prorrogado_en']),at('2026-09-11T17:00Z'))
        self.assertEqual(s['etapa']['prorrogas_restantes'],1)
        self.fails('update crm.lead_sla_etapa_ajustes set secuencia=2;','55000')

    def test_gate_arquitectura_y_mutante_de_dependencia(self):
        self.assertTrue(self.sql('select private.assert_sla_nucleo();').startswith('OK:'))
        self.sql("create or replace function crm.cola_accion_v2_fn(p_limite integer default 50,p_senal text default 'todas',p_etapa text default null,p_analista_id uuid default null,p_cursor jsonb default null) returns jsonb language plpgsql stable security definer set search_path='' as $$begin return '{}'::jsonb; end;$$;")
        self.fails('select private.assert_sla_nucleo();','dejo de consumir')

    def test_mutante_de_cobertura_rompe_estado_y_cola(self):
        self.configured()
        clock=at(self.json('to_jsonb(statement_timestamp())'))
        l=self.lead(start=(clock-dt.timedelta(days=10)).isoformat(),limit=(clock+dt.timedelta(days=1)).isoformat())
        self.task(l,(clock+dt.timedelta(days=2)).isoformat())
        core=self.sql("select pg_get_functiondef('private.sla_operacion_leads(uuid[],boolean,uuid[],timestamptz)'::regprocedure);")
        before=self.core(l,clock.isoformat())
        self.assertTrue(before['compromiso']['cobertura_activa'])
        expr=f"jsonb_build_object('e',crm.estado_sla_leads_v2_fn({array([l['lead']])}),'q',crm.cola_accion_v2_fn(200))"
        normal=self.json(expr,1)
        def oracle(payload):
            self.assertTrue(payload['e']['filas'][0]['compromiso']['cobertura_activa'])
            self.assertEqual(payload['q']['items'][0]['bucket'],'proxima_tarea')
            self.assertEqual(payload['q']['totales']['seguimientos_pendientes'],0)
        oracle(normal)
        self.sql(core.replace('p_ahora<v_hasta','false')+';')
        after=self.core(l,clock.isoformat())
        self.assertFalse(after['compromiso']['cobertura_activa'])
        # Mutante semantico valido (compila), mismo error visible por ambos adaptadores.
        result=self.json(expr,1)
        with self.assertRaises(AssertionError):
            oracle(result)
        self.assertTrue(result['e']['filas'][0]['seguimiento']['accion_pendiente'])
        self.assertEqual(result['q']['items'][0]['bucket'],'seguimiento')
        self.assertEqual(result['q']['totales']['seguimientos_pendientes'],1)

    def test_censo_real_no_aumenta_y_detecta_contador_senuelo(self):
        self.assertEqual(self.sql('select count(*) from private.contadores_crudos_leads_citas();'),'0')
        self.sql('create function crm.contador_mutante() returns bigint language sql as $$select count(*) from crm.leads$$;')
        self.assertEqual(self.sql('select objeto from private.contadores_crudos_leads_citas();'),'crm.contador_mutante()')

    def test_asignacion_anterior_o_ajena_no_genera_seguimiento(self):
        self.configured()
        for change in ('ciclo_n=0',f'analista_id={quote(uid(2))}'):
            l=self.lead()
            self.sql(f"update crm.lead_asignaciones set {change} where id={quote(l['assignment'])};")
            self.activity(l,'2026-09-06T12:00Z')
            s=self.core(l)
            self.assertIn('asignacion_sla_incoherente',s['motivos_datos'])
            self.assertIsNone(s['seguimiento']['vencido'])
            self.assertIsNone(s['compromiso']['cobertura_activa'])

    def test_primera_atencion_ignora_hitos_de_asignacion_incoherente(self):
        self.configured()
        for change in ('ciclo_n=0',f'analista_id={quote(uid(2))}'):
            for milestone in ('primera_gestion_en','primer_contacto_en'):
                with self.subTest(asignacion=change,hito=milestone):
                    l=self.lead()
                    self.sql(f"update crm.lead_asignaciones set {change} where id={quote(l['assignment'])};")
                    self.sql(f"update crm.lead_asignacion_sla_hitos set {milestone}=null where lead_asignacion_id={quote(l['assignment'])};")
                    row=self.json(f"(select to_jsonb(s) from private.sla_operacion_leads({array([l['lead']])},true,'{{}}',{quote(NOW)}) s)")
                    self.assertEqual(row['estado']['evaluacion'],'parcial')
                    self.assertIn('asignacion_sla_incoherente',row['estado']['motivos_datos'])
                    self.assertFalse(row['senales']['primera_atencion'])
                    self.assertEqual(row['accion_atencion']['bucket'],'datos_incompletos')
                    self.assertEqual(row['accion_supervision']['bucket'],'datos_incompletos')
                    # El snapshot antiguo sigue visible, sin fabricar un hito
                    # cumplido ni modificar el contrato historico de v1.
                    base=self.json(f"(select to_jsonb(s) from crm.estado_sla_leads_fn() s where s.lead_id={quote(l['lead'])})",1)
                    self.assertEqual(row['estado']['base'],base)
                    self.assertIsNone(base['asignacion_'+milestone])
                    self.assertIsNotNone(base['asignacion_'+milestone.replace('_en','_limite_en')])
                    state=self.json(f"crm.estado_sla_leads_v2_fn({array([l['lead']])})",1)['filas'][0]
                    self.assertEqual(state['base'],base)
                    queued=next(item for item in self.json('crm.cola_accion_v2_fn(200)',1)['items'] if item['lead_id']==l['lead'])
                    self.assertEqual(queued['bucket'],'datos_incompletos')
                    # Control positivo: el mismo pendiente SI pertenece al
                    # analista cuando se corrige la correspondencia del episodio.
                    self.sql(f"update crm.lead_asignaciones set ciclo_n=1,analista_id={quote(uid(1))} where id={quote(l['assignment'])};")
                    fixed=self.json(f"(select to_jsonb(s) from private.sla_operacion_leads({array([l['lead']])},true,'{{}}',{quote(NOW)}) s)")
                    self.assertTrue(fixed['senales']['primera_atencion'])
                    self.assertEqual(fixed['accion_atencion']['bucket'],'primera_atencion')

    def test_asignacion_incoherente_no_oculta_primera_atencion_del_ciclo(self):
        self.configured()
        for change in ('ciclo_n=0',f'analista_id={quote(uid(2))}'):
            with self.subTest(asignacion=change):
                l=self.lead(assignment='2026-08-01T17:00Z',first_done=False)
                self.sql(f"update crm.lead_asignaciones set {change} where id={quote(l['assignment'])};")
                row=self.json(f"(select to_jsonb(s) from private.sla_operacion_leads({array([l['lead']])},true,'{{}}',{quote(NOW)}) s)")
                self.assertEqual(row['estado']['evaluacion'],'parcial')
                self.assertIn('asignacion_sla_incoherente',row['estado']['motivos_datos'])
                self.assertTrue(row['senales']['primera_atencion'])
                self.assertEqual(row['accion_atencion']['bucket'],'primera_atencion')
                self.assertEqual(at(row['accion_atencion']['referencia_en']),at('2026-09-01T19:00Z'))
                self.assertEqual(row['accion_supervision'],row['accion_atencion'])

    def test_etapa_incoherente_no_aplica_otro_presupuesto(self):
        self.configured()
        l=self.lead()
        self.sql(f"update crm.lead_sla_etapas set etapa='nuevo' where id={quote(l['episode'])};")
        s=self.core(l)
        self.assertIn('etapa_sla_incoherente',s['motivos_datos'])
        self.assertIsNone(s['etapa']['techo_en'])
        self.assertIsNone(s['etapa']['limite_operativo_en'])

    def test_mutante_inclusivo_rompe_frontera_de_cobertura(self):
        self.configured()
        l=self.lead(limit='2026-09-05T17:00Z')
        self.task(l,'2026-09-06T17:00Z')
        clock='2026-09-07T17:00Z'
        self.assertFalse(self.core(l,clock)['compromiso']['cobertura_activa'])
        core=self.sql("select pg_get_functiondef('private.sla_operacion_leads(uuid[],boolean,uuid[],timestamptz)'::regprocedure);")
        self.sql(core.replace('p_ahora<v_hasta','p_ahora<=v_hasta')+';')
        with self.assertRaises(AssertionError):
            self.assertFalse(self.core(l,clock)['compromiso']['cobertura_activa'])

    def test_reversa_repetible_conserva_hechos_y_v1(self):
        l=self.lead()
        old=self.json('(select jsonb_agg(to_jsonb(s)) from crm.estado_sla_leads_fn() s)',1)
        rollback=(BASE/'scripts/rollback-sla-nucleo-lectura.sql').read_text()
        self.sql(rollback)
        self.sql(rollback)
        self.assertEqual(old,self.json('(select jsonb_agg(to_jsonb(s)) from crm.estado_sla_leads_fn() s)',1))
        self.assertEqual(self.sql('select count(*) from crm.sla_operacion_control;'),'1')
        self.fails('select crm.cola_accion_v2_fn(1);','42501',1)
        self.assertEqual(self.sql("select md5(pg_get_functiondef('crm.estado_sla_leads_fn()'::regprocedure));"),'11808483d300a97fb6ff8b3be2dab1fa')

    def test_prioridad_hoy_usa_fecha_de_lima(self):
        self.configured()
        today,tomorrow=self.lead(),self.lead()
        self.task(today,'2026-09-07T04:00Z')
        self.task(tomorrow,'2026-09-07T05:00Z')
        for l,bucket in [(today,'tarea_hoy'),(tomorrow,'proxima_tarea')]:
            row=self.json(f"(select accion_atencion from private.sla_operacion_leads({array([l['lead']])},true,'{{}}','2026-09-07T02:00Z'))")
            self.assertEqual(row['bucket'],bucket)

    def test_supervision_recibe_revision_y_analista_su_agenda(self):
        self.configured()
        clock=at(self.json('to_jsonb(statement_timestamp())'))
        l=self.lead(start=(clock-dt.timedelta(days=1)).isoformat(),limit=(clock+dt.timedelta(days=7)).isoformat())
        self.task(l,(clock+dt.timedelta(days=2)).isoformat(),reprogram=3)
        self.assertEqual(self.json('crm.cola_accion_v2_fn(1)',1)['items'][0]['bucket'],'proxima_tarea')
        self.assertEqual(self.json('crm.cola_accion_v2_fn(1)',3)['items'][0]['bucket'],'revision_comercial')
        self.assertEqual(self.json('crm.cola_accion_v2_fn(1)',5)['items'][0]['bucket'],'revision_comercial')

    def test_desactivar_pausa_no_oculta_mora(self):
        self.sql(f"""insert into crm.sla_politica_etapas_operacion
          select politica_id,etapa,60,0,0,4320,false,0 from crm.sla_politica_etapas where politica_id={quote(P2)};""")
        self.activate()
        l=self.lead()
        self.task(l,'2026-09-08T17:00Z')
        s=self.core(l)
        self.assertEqual(s['compromiso']['validez'],'deshabilitado')
        self.assertFalse(s['compromiso']['cobertura_activa'])
        self.assertTrue(s['seguimiento']['accion_pendiente'])

    def test_no_se_agregan_reglas_a_politica_con_historia(self):
        self.lead(policy=P1)
        self.fails(f"insert into crm.sla_politica_etapas_operacion values({quote(P1)},'nuevo',1440,0,0,2880,true,240);",'55000')

class Report(unittest.TextTestResult):
    cases = []
    def addSuccess(self,test):
        super().addSuccess(test)
        self.cases.append(dict(caso=test._testMethodName,estado='ok'))
    def addFailure(self,test,err):
        super().addFailure(test,err)
        self.cases.append(dict(caso=test._testMethodName,estado='fallo',detalle=str(err[1])))
    def addError(self,test,err):
        super().addError(test,err)
        self.cases.append(dict(caso=test._testMethodName,estado='error',detalle=str(err[1])))

if __name__ == '__main__':
    BANK = Bank()
    start = time.monotonic()
    success = False
    try:
        BANK.start()
        result=unittest.TextTestRunner(verbosity=2,resultclass=Report).run(unittest.defaultTestLoader.loadTestsFromTestCase(Nucleo))
        success=result.wasSuccessful() and MIGRATION.read_text()==MIGRATION_TEXT
    finally:
        BANK.close()
        report=dict(alcance='Migracion y contratos en PostgreSQL 16 aislado con datos sinteticos; autoridad/veto mediante dobles. No es test-rls ni despliegue.',
                    migracion=MIGRATION.name,sha256=hashlib.sha256(MIGRATION_TEXT.encode()).hexdigest(),
                    archivo_no_cambio=MIGRATION.read_text()==MIGRATION_TEXT,
                    banco=str(BANK.root),servidor_detenido=not BANK.running,segundos=round(time.monotonic()-start,2),
                    pruebas=Report.cases,correcto=success)
        (BANK.root/'resultados.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
        print('Evidencia: '+str(BANK.root/'resultados.json'),flush=True)
    raise SystemExit(0 if success else 1)

#!/usr/bin/env python3
"""Contrasta una foto autorizada de cartera con el nucleo SLA N1 real.

No conecta a Supabase ni acepta URLs. Crea PostgreSQL 17 privado, sin TCP;
datos y resultados permanecen en /private/tmp. El esquema es el banco reducido
de N1: no certifica integracion, writers, autenticacion o RLS productivos.

Contrato JSON: {t0, tables: {leads: [...], ...}, vetos: [{id, vetado}],
evidencia_tareas: [{id, insert_audit, insert_humano, insert_en, barreras,
cadena_ok}]}. Las claves de tables admiten el prefijo crm. Los campos de audit
pueden ser booleanos o conteos; barreras admite conteo o lista. Faltar evidencia
nunca se interpreta como ausencia comprobada de problemas.
"""
import argparse
from collections import Counter, defaultdict
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
import uuid


BASE = Path(__file__).resolve().parents[1]
FIX = BASE / 'tests/sla-nucleo'
MIGRATION = BASE / 'migrations/20260907001024_crm_sla_nucleo_operativo_lectura.sql'
TABLES = ('sla_politicas', 'sla_politica_etapas', 'leads', 'lead_sla_ciclos',
          'lead_asignaciones', 'lead_asignacion_sla_hitos', 'lead_sla_etapas',
          'actividades', 'tareas')
OPEN = {'nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada'}
COMMERCIAL = {'llamada', 'whatsapp', 'reunion'}
RULES = (
    ('nuevo', 1440, 1440, 0, 0, 2880, True, 240),
    ('contactado', 11520, 4320, 5760, 2, 11520, True, 1440),
    ('reunion_agendada', 21600, 4320, 0, 0, 4320, True, 2880),
    ('propuesta_enviada', 28800, 7200, 10080, 1, 10080, True, 1440),
)


def quoted(value):
    if value is None:
        return 'null'
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, (dict, list)):
        value = json.dumps(value, ensure_ascii=False, allow_nan=False)
    return "'" + str(value).replace("'", "''") + "'"


def instant(value):
    if not isinstance(value, str):
        return None
    try:
        # Python 3.9 admite exactamente 3/6 decimales; PostgreSQL omite ceros.
        normalized = re.sub(r'(\.\d{1,6})(?=[+-]\d{2}:\d{2}$)',
                            lambda match: match.group(1).ljust(7, '0'), value.replace('Z', '+00:00'))
        result = dt.datetime.fromisoformat(normalized)
        return result if result.tzinfo is not None else None
    except ValueError:
        return None


def positive(value):
    return value is True or (type(value) is int and value > 0)


def no_barriers(value):
    return value == [] or (type(value) is int and value == 0)


def temp_only(path):
    path = path.expanduser().resolve()
    allowed = (Path('/private/tmp'), Path(tempfile.gettempdir()).resolve())
    if not any(path.is_relative_to(root) for root in allowed):
        raise ValueError('Las fotos y resultados solo se admiten dentro de un directorio temporal privado')
    return path


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n')


class Bank:
    def __init__(self, pg_bin, output):
        self.pg = pg_bin
        self.output = output
        self.root = Path(tempfile.mkdtemp(prefix='sla-cartera-', dir='/private/tmp'))
        self.running = False
        self.sequence = 0
        self.env = {key: value for key, value in os.environ.items() if not key.startswith('PG')}
        self.env.update(PGHOST=str(self.root), PGPORT='55484', PGUSER='sla_stock_owner',
                        PGDATABASE='postgres', PGCONNECT_TIMEOUT='3')

    def command(self, name, args, text=None):
        result = subprocess.run([str(self.pg / name), *args], input=text,
                                env=self.env, text=True, capture_output=True, timeout=60)
        if result.returncode:
            self.sequence += 1
            detail = self.output / f'error-{self.sequence}-{name}.txt'
            detail.write_text(result.stderr + '\n' + result.stdout)
            raise RuntimeError(f'{name} fallo; detalle privado: {detail}')
        return result.stdout.strip()

    def start(self):
        version = self.command('postgres', ['--version'])
        if ' 17.' not in version:
            raise RuntimeError('Este contraste requiere PostgreSQL 17')
        self.command('initdb', ['-D', str(self.root / 'data'), '-U', 'sla_stock_owner',
                               '-A', 'trust', '--no-locale', '-E', 'UTF8'])
        self.command('pg_ctl', ['-D', str(self.root / 'data'), '-l', str(self.root / 'postgres.log'),
                               '-o', f"-k {self.root} -p 55484 -c listen_addresses='' -c timezone=UTC -c max_connections=20",
                               '-w', 'start'])
        self.running = True
        return version

    def sql(self, text, db='sla_stock'):
        return self.command('psql', ['-X', '-qAt', '-d', db, '-v', 'ON_ERROR_STOP=1',
                                    '-v', 'VERBOSITY=verbose'], text)

    def value(self, expression, db='sla_stock', prefix=''):
        return json.loads(self.sql(prefix + 'select ' + expression + ';', db))

    def insert_rows(self, table, rows):
        if not rows:
            return
        fields = set(self.value("(select jsonb_agg(attname) from pg_attribute where attrelid=" +
                                quoted(table) + "::regclass and attnum>0 and not attisdropped)"))
        groups = defaultdict(list)
        for row in rows:
            columns = tuple(sorted(fields.intersection(row)))
            if not columns:
                raise ValueError(f'La foto no tiene columnas compatibles con {table}')
            groups[columns].append(row)
        for columns, group in groups.items():
            # La FK ancestral de tareas se comprueba al final de la sentencia;
            # una cadena puede atravesar cualquier posicion del array recibido.
            batch = len(group) if table == 'crm.tareas' else 250
            for start in range(0, len(group), batch):
                values = ','.join('(' + ','.join(quoted(row[key]) for key in columns) + ')'
                                  for row in group[start:start + batch])
                self.sql(f'insert into {table} (' + ','.join('"' + key + '"' for key in columns) +
                         ') values ' + values + ';')

    def close(self):
        if self.running:
            self.command('pg_ctl', ['-D', str(self.root / 'data'), '-m', 'fast', '-w', 'stop'])
            self.running = False


def classify(snapshot, tables):
    """Calidad causal de entrada; ningun calculo de SLA o cobertura vive aqui."""
    t0 = instant(snapshot['t0'])
    if t0 is None:
        raise ValueError('t0 no es una fecha ISO finita con zona horaria')
    leads = {row['id']: row for row in tables['leads']}
    evidence = {row['id']: row for row in snapshot.get('evidencia_tareas', [])}
    cycles = defaultdict(list)
    for row in tables['lead_sla_ciclos']:
        cycles[row['lead_id']].append(row)
    results = []
    for task in tables['tareas']:
        if not task.get('activo') or task.get('estado') != 'pendiente' or not task.get('lead_id'):
            continue
        lead = leads.get(task['lead_id'])
        reasons = []
        matches = [] if lead is None else [row for row in cycles[lead['id']]
                                          if row['ciclo_n'] == lead['ciclo_actual']]
        cycle = matches[0] if len(matches) == 1 else None
        created = instant(task.get('creado_en'))
        began = instant(cycle.get('iniciado_en')) if cycle else None
        if lead is None or lead.get('activo') is not True or lead.get('etapa') not in OPEN:
            reasons.append('lead_no_abierto')
        if cycle is None or began is None or began > t0:
            reasons.append('ciclo_no_demostrable')
        if created is None or created > t0:
            reasons.append('fecha_creacion_no_valida')
        elif began is not None and created < began:
            reasons.append('creacion_anterior_ciclo_actual')
        if lead is not None and (task.get('vendedor_id') != lead.get('vendedor_id') or
                                 task.get('asignado_supervisor_id') != lead.get('asignado_supervisor_id')):
            reasons.append('tenencia_actual_incoherente')
        if lead is not None and cycle is not None and began is not None:
            other_starts = [instant(row.get('iniciado_en')) for row in cycles[lead['id']]
                            if row['ciclo_n'] > cycle['ciclo_n']]
            if other_starts:
                reasons.append('ciclo_actual_no_es_ultimo')
        candidate = not reasons
        ev = evidence.get(task['id'], {})
        strict_reasons = list(reasons)
        if cycle is not None and cycle.get('aproximado') is not False:
            strict_reasons.append('inicio_ciclo_aproximado_o_sin_sello')
        if not positive(ev.get('insert_audit')):
            strict_reasons.append('insert_sin_auditoria_demostrada')
        if not positive(ev.get('insert_humano')):
            strict_reasons.append('insert_humano_no_demostrado')
        inserted = instant(ev.get('insert_en'))
        if inserted is None or inserted > t0 or (began is not None and inserted < began):
            strict_reasons.append('instante_auditoria_fuera_ciclo_o_ausente')
        if not no_barriers(ev.get('barreras')):
            strict_reasons.append('barreras_de_cancelacion_o_evidencia_ausente')
        if ev.get('cadena_ok') is not True:
            strict_reasons.append('cadena_no_demostrada')
        results.append(dict(tarea_id=task['id'], lead_id=task['lead_id'], tipo=task['tipo'],
                            ciclo_n=cycle['ciclo_n'] if cycle else None,
                            candidato_fecha=candidate, estricto=not strict_reasons,
                            motivos_fecha=reasons, motivos_estricto=strict_reasons))
    return results


def aggregate(rows, leads):
    def group(items):
        counts = Counter(total_leads=len(items))
        reasons, review, attention, supervision = Counter(), Counter(), Counter(), Counter()
        for row in items:
            state = row['estado']
            counts['evaluacion_' + state['evaluacion']] += 1
            for signal, value in row['senales'].items():
                counts[signal] += value is True
            coverage = state['compromiso']['cobertura_activa']
            counts['compromisos_cubren'] += coverage is True
            counts['cobertura_desconocida'] += coverage is None
            counts['seguimientos_vencidos_sin_descontar_cobertura'] += state['seguimiento']['vencido'] is True
            counts['fuera_plazo_original'] += state['etapa']['fuera_plazo'] is True
            counts['revision_desconocida'] += state['etapa']['revision_requerida'] is None
            reasons.update(state['motivos_datos'])
            review.update(state['etapa']['motivos_revision'])
            attention.update([row['accion_atencion']['bucket'] if row['accion_atencion'] else 'sin_accion'])
            supervision.update([row['accion_supervision']['bucket'] if row['accion_supervision'] else 'sin_accion'])
        return dict(conteos=dict(counts), motivos_datos=dict(reasons), motivos_revision=dict(review),
                    cola_atencion=dict(attention), cola_supervision=dict(supervision))
    by_stage, by_owner = defaultdict(list), defaultdict(list)
    for row in rows:
        lead = leads[row['lead_id']]
        by_stage[lead['etapa']].append(row)
        by_owner[lead.get('vendedor_id') or 'sin_analista'].append(row)
    return dict(global_=group(rows), por_etapa={key: group(value) for key, value in sorted(by_stage.items())},
                por_analista={key: group(value) for key, value in sorted(by_owner.items())})


def run(args):
    os.umask(0o077)
    source = temp_only(args.snapshot)
    output = temp_only(args.output_dir)
    output.mkdir(parents=True, exist_ok=False)
    raw = source.read_bytes()
    snapshot = json.loads(raw)
    if instant(snapshot.get('t0')) is None:
        raise ValueError('t0 debe ser una fecha ISO finita con zona horaria')
    tables = {key.removeprefix('crm.'): value for key, value in snapshot['tables'].items()}
    missing = set(TABLES) - tables.keys()
    if missing:
        raise ValueError('Faltan tablas de la foto: ' + ', '.join(sorted(missing)))
    if any(not isinstance(tables[key], list) for key in TABLES):
        raise ValueError('Cada tabla de la foto debe ser un array')
    # Se lee AHORA, al ejecutar: no congela una migracion que otro agente corrige.
    migration_text = MIGRATION.read_text()
    bank = Bank(args.pg_bin, output)
    report = dict(t0=snapshot['t0'], estado='iniciado', foto_sha256=hashlib.sha256(raw).hexdigest(),
                  migracion=str(MIGRATION.relative_to(BASE)),
                  migracion_sha256=hashlib.sha256(migration_text.encode()).hexdigest(),
                  banco=str(bank.root), tablas_foto={key: len(tables[key]) for key in TABLES},
                  limites=['Banco reducido de contratos, no restauracion completa del CRM.',
                           'Autoridad global sintetica; veto consumido del vector real de la foto.',
                           'Sin concesion retroactiva de prorrogas ni ejecucion de writers.',
                           'El escenario solo_fecha es sensibilidad, no validacion de contextos.'])
    try:
        report['postgres'] = bank.start()
        bank.sql('create database sla_stock;', 'postgres')
        bank.sql((FIX / 'base.sql').read_text())
        bank.sql('truncate fixture.ambito, fixture.vetos, public.audit_log, crm.sla_politica_etapas, '
                 'crm.sla_politicas, public.perfiles cascade;')
        profile_fields = ('vendedor_id', 'asignado_supervisor_id', 'creado_por', 'analista_id')
        profiles = {row[field] for key in TABLES for row in tables[key]
                    for field in profile_fields if row.get(field)}
        profiles.update(row['perfil_id'] for row in tables.get('equipo', []) if row.get('perfil_id'))
        actor = str(uuid.uuid5(uuid.NAMESPACE_URL, 'avancecorp:sla:contraste:actor-global'))
        if actor in profiles:
            raise ValueError('Colision inesperada de identidad del actor sintetico')
        profiles.add(actor)
        bank.insert_rows('public.perfiles', [dict(id=key, nombre_completo='Perfil ' + key[:8],
                         rol_fixture='gerencia' if key == actor else None,
                         global_fixture=key == actor) for key in sorted(profiles)])
        # Tareas de clientes/postventa no participan en este dominio ni en la
        # tabla reducida (lead_id NOT NULL); se cuentan como exclusion explicita.
        report['tareas_perfil_excluidas'] = sum(row.get('lead_id') is None for row in tables['tareas'])
        for table in TABLES:
            values = [dict(row) for row in tables[table]]
            if table == 'leads':
                for row in values:
                    row['nombre_completo'] = 'Lead ' + row['id'][:8]
            if table == 'tareas':
                values = [row for row in values if row.get('lead_id')]
                # FK ancestral: insertar todos en una sentencia, y dejar que
                # PostgreSQL rechace una foto incompleta sin inventar padres.
                for row in values:
                    row['titulo'] = 'Tarea ' + row['id'][:8]
            bank.insert_rows('crm.' + table, values)
        # Ausencia de veto en la foto no equivale a persona contactable.
        veto_by_id = {row['id']: row.get('vetado') for row in snapshot.get('vetos', [])}
        if any(row['id'] not in veto_by_id or type(veto_by_id[row['id']]) is not bool for row in tables['leads']):
            raise ValueError('El vector de vetos debe resolver explicitamente cada lead de la foto')
        bank.insert_rows('fixture.vetos', [dict(lead_id=key) for key, value in veto_by_id.items() if value])
        bank.sql((FIX / 'estado-v1-anterior.sql').read_text())
        bank.sql((FIX / 'censo-real.sql').read_text())
        bank.sql('revoke all on function crm.estado_sla_leads_fn() from public; '
                 'grant execute on function crm.estado_sla_leads_fn() to authenticated;')
        prefix = 'set role authenticated; set request.jwt.claim.sub=' + quoted(actor) + ';'
        v1_expr = "(select coalesce(jsonb_agg(to_jsonb(s) order by s.lead_id),'[]') from crm.estado_sla_leads_fn() s)"
        before = bank.value(v1_expr, prefix=prefix)
        bank.sql(migration_text)
        after = bank.value(v1_expr, prefix=prefix)
        report['v1_paridad'] = before == after
        report['v1_filas'] = len(before)
        save(output / 'v1-antes.json', before)
        save(output / 'v1-despues.json', after)
        if before != after:
            raise RuntimeError('La migracion altero el resultado v1 sobre la foto real')
        policy = str(uuid.uuid5(uuid.NAMESPACE_URL, 'avancecorp:sla:contraste:' + snapshot['t0']))
        version = max((row['version'] for row in tables['sla_politicas']), default=0) + 1
        if any(row['id'] == policy or instant(row['vigente_desde']) == instant(snapshot['t0'])
               for row in tables['sla_politicas']):
            raise ValueError('La politica hipotetica colisiona con la foto')
        bank.sql('insert into crm.sla_politicas(id,version,vigente_desde) values (' +
                 ','.join(map(quoted, (policy, version, snapshot['t0']))) + ');')
        for stage, base, follow, extension, maximum, extra, enabled, margin in RULES:
            bank.sql('insert into crm.sla_politica_etapas(politica_id,etapa,maximo_minutos) values (' +
                     ','.join(map(quoted, (policy, stage, base))) + ');')
            bank.sql('insert into crm.sla_politica_etapas_operacion values (' +
                     ','.join(map(quoted, (policy, stage, follow, extension, maximum, extra, enabled, margin))) + ');')
        bank.sql("update crm.sla_operacion_control set modo='activo',revision=revision+1," +
                 'primera_activacion_en=' + quoted(snapshot['t0']) + ',politica_adopcion_id=' + quoted(policy) +
                 ',cambiado_por=' + quoted(actor) + '; analyze;')
        report['politica_hipotetica'] = dict(id=policy, version=version, primera_activacion_en=snapshot['t0'])
        contexts = classify(snapshot, tables)
        save(output / 'clasificacion-contextos.json', contexts)
        report['contextos'] = dict(total_pendientes=len(contexts),
            estrictos=sum(row['estricto'] for row in contexts),
            candidatos_fecha=sum(row['candidato_fecha'] for row in contexts),
            motivos_estrictos=dict(Counter(reason for row in contexts for reason in row['motivos_estricto'])))
        report['escenarios'] = {}
        leads = {row['id']: row for row in tables['leads']}
        for scenario, field in (('sin_contexto', None), ('estricto', 'estricto'),
                                ('solo_fecha_sensibilidad', 'candidato_fecha')):
            db = 'sla_' + scenario
            bank.sql(f'create database {db} template sla_stock;', 'postgres')
            chosen = [row for row in contexts if field and row[field]]
            if chosen:
                values = ','.join('(' + ','.join(map(quoted, (row['tarea_id'], row['lead_id'], row['ciclo_n']))) +
                                  ",'reconstruido')" for row in chosen)
                bank.sql('insert into crm.tarea_sla_contexto(tarea_id,lead_id,ciclo_n,fuente) values ' + values + ';', db)
            bank.sql('analyze;', db)
            started = time.perf_counter()
            rows = bank.value("(select coalesce(jsonb_agg(to_jsonb(s) order by s.lead_id),'[]') " +
                              "from private.sla_operacion_leads(null,true,'{}'::uuid[]," + quoted(snapshot['t0']) + ') s)', db)
            elapsed = time.perf_counter() - started
            save(output / (scenario + '-estados.json'), rows)
            summary = aggregate(rows, leads)
            summary.update(tiempo_consulta_segundos=round(elapsed, 6), contextos_insertados=len(chosen),
                           archivo_estados=scenario + '-estados.json')
            report['escenarios'][scenario] = summary
            if scenario == 'estricto':
                explained = json.loads(bank.sql("explain (analyze, buffers, format json) select * " +
                    "from private.sla_operacion_leads(null,true,'{}'::uuid[]," + quoted(snapshot['t0']) + ');', db))
                save(output / 'estricto-explain.json', explained)
                report['explain_estricto'] = dict(archivo='estricto-explain.json',
                    planning_ms=explained[0].get('Planning Time'), execution_ms=explained[0].get('Execution Time'),
                    limite='Banco reducido, cache local; no predice latencia de Supabase ni concurrencia.')
                report['proyecciones_sin_acciones'] = {}
                for hours in (24, 72):
                    future = (instant(snapshot['t0']) + dt.timedelta(hours=hours)).isoformat()
                    projected = bank.value("(select coalesce(jsonb_agg(to_jsonb(s) order by s.lead_id),'[]') " +
                        "from private.sla_operacion_leads(null,true,'{}'::uuid[]," + quoted(future) + ') s)', db)
                    filename = f'estricto-mas-{hours}h-sin-acciones-estados.json'
                    save(output / filename, projected)
                    projection = aggregate(projected, leads)
                    projection.update(calculado_en=future, primera_activacion_en=snapshot['t0'],
                        archivo_estados=filename, supuesto='Sin nuevas acciones, cambios de estado ni reprogramaciones.')
                    report['proyecciones_sin_acciones'][str(hours) + 'h'] = projection
        report['estado'] = 'completo'
    except Exception as error:
        report['estado'] = 'error'
        report['error'] = str(error)
        raise
    finally:
        try:
            bank.close()
            report['banco_detenido'] = not bank.running
        finally:
            save(output / 'resultado.json', report)
            print(json.dumps(dict(estado=report['estado'], resultado=str(output / 'resultado.json'),
                                  banco=str(bank.root)), ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True,
                        help='Directorio temporal NUEVO; no se sobrescriben resultados anteriores')
    parser.add_argument('--pg-bin', type=Path, default=Path('/opt/homebrew/opt/postgresql@17/bin'))
    run(parser.parse_args())

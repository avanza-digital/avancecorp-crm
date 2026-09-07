#!/usr/bin/env python3
"""Oraculo comercial independiente del SQL N1, para una foto ya minimizada.
Solo lee el JSON local. No importa ni ejecuta codigo del nucleo SQL.
Los UUID solo permanecen en el resultado local para conciliar pertenencia.
"""
import argparse
import collections
import datetime as dt
import hashlib
import json
import re
from pathlib import Path

STAGES = ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
FOLLOW = dict(zip(STAGES, (1440, 4320, 4320, 7200)))
EXTRA = dict(zip(STAGES, (2880, 11520, 4320, 10080)))
MARGIN = dict(zip(STAGES, (240, 1440, 2880, 1440)))
GESTURES = {'llamada_realizada', 'llamada_no_contestada', 'whatsapp_enviado', 'whatsapp_recibido', 'reunion_realizada'}
COMMERCIAL = {'llamada', 'whatsapp', 'reunion'}
UTC = dt.timezone.utc


def timestamp(value):
    if value is None or value in ('infinity', '-infinity'):
        return None
    text = value.replace('Z', '+00:00')
    text = re.sub(r'\.(\d+)(?=[+-]\d\d:\d\d$)', lambda m: '.' + m.group(1).ljust(6, '0'), text)
    return dt.datetime.fromisoformat(text)


def iso(value):
    return value.isoformat() if value is not None else None


def group(rows, key):
    result = collections.defaultdict(list)
    for row in rows:
        result[row[key]].append(row)
    return result


def compare(expected, actual_rows):
    actual = {r['lead_id']: r for r in actual_rows}
    assert len(actual) == len(actual_rows), 'N1 devolvio IDs duplicados'
    expected_ids = {r['lead_id'] for r in expected['filas']}
    assert expected_ids == set(actual), 'No coincide la poblacion'
    checks, differences = collections.Counter(), collections.Counter()


    def check(name, left, right, time=False):
        checks[name] += 1
        if time:
            left, right = timestamp(left), timestamp(right)
        if left != right:
            differences[name] += 1


    mapping = {
        'seguimiento_vencido': ('seguimiento', 'vencido'),
        'seguimiento_pendiente': ('seguimiento', 'accion_pendiente'),
        'cobertura': ('compromiso', 'cobertura_activa'),
        'revision': ('etapa', 'revision_requerida'),
        'fuera_plazo_original': ('etapa', 'fuera_plazo'),
        'referencia_seguimiento_en': ('seguimiento', 'referencia_en'),
        'limite_seguimiento_en': ('seguimiento', 'limite_en'),
        'limite_operativo_en': ('etapa', 'limite_operativo_en'),
        'techo_en': ('etapa', 'techo_en'),
        'hasta_en': ('compromiso', 'hasta_en'),
        'episodios_etapa_en_ciclo': ('etapa', 'episodios_en_ciclo'),
    }
    reasons = {
        'revision_limite': 'limite_operativo_agotado',
        'revision_reprogramaciones': 'reprogramaciones_agotadas',
        'revision_reingreso': 'reingreso_etapa',
    }
    for row in expected['filas']:
        core = actual[row['lead_id']]
        state = core['estado']
        check('universo.evaluacion_operativa', row['operativo'], state['evaluacion'] != 'no_aplica')
        check('universo.primera_atencion', row['primera_atencion'], core['senales']['primera_atencion'])
        check('universo.tarea_agenda_vencida', row['tarea_agenda_vencida'], core['senales']['tareas_vencidas'])
        check('universo.revisiones', row['revision'] is True, core['senales']['revisiones'])
        if row['operativo']:
            for field, (section, key) in mapping.items():
                check(field, row[field], state[section][key], time=field.endswith('_en'))
            selected = state['compromiso']['tarea']
            check('tarea_elegida_id', row['tarea_elegida_id'], selected['id'] if selected else None)
            for field, reason in reasons.items():
                check(field, row[field], reason in state['etapa']['motivos_revision'])
            if 'sin_asignacion' in row['motivos']:
                check('sin_asignacion.seguimiento_no_evaluable', None, state['seguimiento']['accion_pendiente'])
                check('sin_asignacion.evaluacion_parcial', 'parcial', state['evaluacion'])
                check('sin_asignacion.motivo_visible', True, 'sin_asignacion' in state['motivos_datos'])
                check('sin_asignacion.sin_atencion', None, core['accion_atencion'])
                check('sin_asignacion.reparto_supervision', 'por_repartir', core['accion_supervision']['bucket'])
        else:
            check('terminal.sin_atencion', None, core['accion_atencion'])
            check('terminal.sin_supervision', None, core['accion_supervision'])
            check('terminal.seguimiento_no_aplica', None, state['seguimiento']['accion_pendiente'])
            check('terminal.compromiso_no_aplica', None, state['compromiso']['cobertura_activa'])
            check('terminal.revision_no_aplica', None, state['etapa']['revision_requerida'])

    report = dict(t0=expected['t0'], foto_sha256=expected['snapshot_sha256'],
                  oraculo='oraculo-cartera.py', nucleo='SQL N1 ejecutado localmente',
                  poblacion=dict(filas=len(actual),abiertos=sum(r['operativo'] for r in expected['filas']),
                                 sin_asignacion=sum('sin_asignacion' in r['motivos'] for r in expected['filas']),
                                 terminales=sum(not r['operativo'] for r in expected['filas'])),
                  comparaciones=sum(checks.values()),discrepancias=sum(differences.values()),
                  campos=[dict(campo=field,comparaciones=count,discrepancias=differences[field]) for field,count in sorted(checks.items())],
                  limites='Comparacion de calculo N1 sobre el mismo corte local; no verifica RLS real, concurrencia de writers, UI ni despliegue. UUID usados solo en memoria para conciliar pertenencia, no incluidos en este informe.')
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('snapshot', type=Path)
    parser.add_argument('--out', type=Path, default=Path('/private/tmp/sla-oraculo-cartera-resultados-20260907.json'))
    parser.add_argument('--comparar', type=Path, help='JSON de filas completas devueltas por SQL N1 al mismo instante')
    parser.add_argument('--paridad', type=Path, default=Path('/private/tmp/sla-oraculo-paridad.json'), help='Informe agregado sin UUID')
    args = parser.parse_args()
    source = args.snapshot.read_bytes()
    data = json.loads(source)
    tables = data['tables']
    now = timestamp(data['t0'])
    assert now is not None
    cycles = {(r['lead_id'], r['ciclo_n']): r for r in tables['lead_sla_ciclos']}
    assignments = group(tables['lead_asignaciones'], 'lead_id')
    episodes = group(tables['lead_sla_etapas'], 'lead_id')
    milestones = {r['lead_asignacion_id']: r for r in tables['lead_asignacion_sla_hitos']}
    activities = group(tables['actividades'], 'lead_id')
    pending = group([r for r in tables['tareas'] if r['activo'] and r['estado'] == 'pendiente'], 'lead_id')
    all_tasks = {r['id']: r for r in tables['tareas']}
    evidence = {r['id']: r for r in data['evidencia_tareas']}
    veto = {r['id']: r['vetado'] for r in data['vetos']}
    policy_version = {r['id']: r['version'] for r in tables['sla_politicas']}
    rows = []
    task_diagnostics = collections.Counter()
    reprogram_chains = collections.Counter()
    parent_transitions = collections.Counter()
    cohort_policy = collections.Counter()

    for lead in tables['leads']:
        lid, stage = lead['id'], lead['etapa']
        current_cycle = cycles.get((lid, lead['ciclo_actual']))
        open_assignments = [r for r in assignments[lid] if r['finalizado_en'] is None]
        assert len(open_assignments) <= 1, 'Dos asignaciones abiertas'
        assignment = open_assignments[0] if open_assignments else None
        current_episodes = [r for r in episodes[lid] if r['ciclo_n'] == lead['ciclo_actual'] and r['finalizado_en'] is None]
        assert len(current_episodes) <= 1, 'Dos episodios abiertos en el ciclo'
        episode = current_episodes[0] if current_episodes else None
        coherent_assignment = bool(assignment and assignment['ciclo_n'] == lead['ciclo_actual'] and assignment['analista_id'] == lead['vendedor_id'])
        coherent_episode = bool(episode and episode['etapa'] == stage)
        usable = lead['activo'] and stage in STAGES and veto[lid] is False
        row = dict(lead_id=lid, etapa=stage, operativo=usable, seguimiento_vencido=None,
                   seguimiento_pendiente=None, cobertura=None, revision=None,
                   revision_limite=None, revision_reprogramaciones=None, revision_reingreso=None,
                   primera_atencion=False, tarea_agenda_vencida=False, fuera_plazo_original=None,
                   tarea_elegida_id=None, tareas_comerciales_pendientes=0,
                   referencia_seguimiento_en=None, limite_seguimiento_en=None,
                   limite_operativo_en=None, techo_en=None, hasta_en=None,
                   contexto_incompleto=False, motivos=[])
        if not usable:
            rows.append(row)
            continue
        assert current_cycle is not None, 'Ciclo ausente'
        assert coherent_assignment or (assignment is None and lead['vendedor_id'] is None), 'Asignacion sin correspondencia'
        assert episode is not None and coherent_episode, 'Etapa sin correspondencia'
        cohort_policy[f'{stage}:v{policy_version[episode["politica_id"]]}'] += 1
        baseline = timestamp(episode['limite_en'])
        assert baseline is not None
        ceiling = baseline + dt.timedelta(minutes=EXTRA[stage])
        row['fuera_plazo_original'] = now >= baseline
        row['techo_en'] = iso(ceiling)

        if assignment is not None:
            reference = max(timestamp(current_cycle['iniciado_en']), timestamp(assignment['asignado_en']))
            recent = [r for r in activities[lid] if r['tipo'] in GESTURES and timestamp(r['creado_en']) is not None and reference <= timestamp(r['creado_en']) <= now]
            last = max(recent, key=lambda r: (timestamp(r['creado_en']), r['id'])) if recent else None
            if last:
                reference = timestamp(last['creado_en'])
            assert reference <= now
            follow_limit = max(reference + dt.timedelta(minutes=FOLLOW[stage]), now)
            row['referencia_seguimiento_en'] = iso(reference)
            row['limite_seguimiento_en'] = iso(follow_limit)
            row['seguimiento_vencido'] = now >= follow_limit
        else:
            row['motivos'].append('sin_asignacion')

        agenda = sorted(pending[lid], key=lambda r: (timestamp(r['vence_en']) or dt.datetime.max.replace(tzinfo=UTC), r['id']))
        row['tarea_agenda_vencida'] = bool(agenda and timestamp(agenda[0]['vence_en']) is not None and timestamp(agenda[0]['vence_en']) <= now)
        commercial = [r for r in agenda if r['tipo'] in COMMERCIAL]
        row['tareas_comerciales_pendientes'] = len(commercial)
        for task in agenda:
            proof = evidence.get(task['id'])
            created = timestamp(task['creado_en'])
            assert proof is not None and proof['barreras'] == 0 and proof['cadena_ok'] is True, 'No hay evidencia completa para reconstruir'
            assert created is not None and timestamp(current_cycle['iniciado_en']) <= created <= now, 'Creacion fuera del ciclo'
            assert task['vendedor_id'] == lead['vendedor_id'] and task['asignado_supervisor_id'] == lead['asignado_supervisor_id'], 'Tenencia de tarea incoherente'
            assert timestamp(task['vence_en']) is not None, 'Fecha invalida'
            task_diagnostics[f'pendiente_{task["tipo"]}'] += 1
            if task['reprogramaciones'] >= 3:
                task_diagnostics[f'tercera_o_mas_{task["tipo"]}'] += 1
            # El contador acumula reprogramaciones in situ y reemplazos; la
            # cadena por si sola no puede inferir los primeros.
            if task['reagendada_de']:
                direct_parent = all_tasks[task['reagendada_de']]
                parent_transitions[f'{direct_parent["estado"]}:{direct_parent["tipo"]}->{task["tipo"]}:{direct_parent["reprogramaciones"]}->{task["reprogramaciones"]}'] += 1
                if direct_parent['estado'] == 'reprogramada':
                    assert task['reprogramaciones'] == direct_parent['reprogramaciones'] + 1, 'Reprogramacion por reemplazo sin contador heredado'
            seen, cursor, depth = set(), task, 0
            while cursor['reagendada_de']:
                assert cursor['id'] not in seen, 'Ciclo en cadena de reprogramacion'
                seen.add(cursor['id'])
                parent = all_tasks[cursor['reagendada_de']]
                assert parent['lead_id'] == lid
                depth += 1
                cursor = parent
            reprogram_chains[f'{task["tipo"]}:contador={task["reprogramaciones"]}:enlaces={depth}'] += 1

        chosen = commercial[0] if commercial else None
        third = bool(chosen and chosen['reprogramaciones'] >= 3)
        until = min(timestamp(chosen['vence_en']) + dt.timedelta(minutes=MARGIN[stage]), ceiling) if chosen and not third else None
        row['tarea_elegida_id'] = chosen['id'] if chosen else None
        row['hasta_en'] = iso(until)
        row['cobertura'] = until is not None and now < until
        row['seguimiento_pendiente'] = row['seguimiento_vencido'] and not row['cobertura']
        operational_limit = min(max(baseline, until if until is not None else baseline), ceiling)
        row['limite_operativo_en'] = iso(operational_limit)
        row['revision_limite'] = now >= operational_limit
        row['revision_reprogramaciones'] = third
        entries = sum(e['ciclo_n'] == lead['ciclo_actual'] and e['etapa'] == stage for e in episodes[lid])
        row['episodios_etapa_en_ciclo'] = entries
        row['revision_reingreso'] = entries >= 3
        row['revision'] = row['revision_limite'] or third or row['revision_reingreso']
        if row['revision_limite']:
            row['motivos'].append('limite_operativo_agotado')
        if third:
            row['motivos'].append('reprogramaciones_agotadas')
        if row['revision_reingreso']:
            row['motivos'].append('reingreso_etapa')
        assignment_milestones = milestones[assignment['id']] if assignment else {}
        unresolved = [timestamp(current_cycle[k.replace('_en', '_limite_en')]) for k in ('primera_gestion_en', 'primer_contacto_en') if current_cycle[k] is None]
        if coherent_assignment:
            unresolved += [timestamp(assignment[k.replace('_en', '_limite_en')]) for k in ('primera_gestion_en', 'primer_contacto_en') if assignment_milestones[k] is None]
        row['primera_atencion'] = lead['vendedor_id'] is not None and any(deadline is not None for deadline in unresolved)
        row['primera_atencion_vencida'] = bool(row['primera_atencion'] and now >= min(d for d in unresolved if d is not None))
        row['compromiso_vencido'] = bool(chosen and timestamp(chosen['vence_en']) <= now)
        row['compromiso_futuro_sin_cobertura'] = bool(chosen and timestamp(chosen['vence_en']) > now and not row['cobertura'])
        rows.append(row)

    metrics = ('operativo', 'seguimiento_vencido', 'seguimiento_pendiente', 'cobertura', 'revision',
               'revision_limite', 'revision_reprogramaciones', 'revision_reingreso', 'primera_atencion',
               'primera_atencion_vencida', 'tarea_agenda_vencida', 'fuera_plazo_original',
               'contexto_incompleto', 'compromiso_vencido', 'compromiso_futuro_sin_cobertura')
    def aggregate(subset):
        return {'leads': len(subset), **{m: sum(r.get(m) is True for r in subset) for m in metrics},
                'con_compromiso_comercial': sum(r['tarea_elegida_id'] is not None for r in subset)}
    assert sum(v for k, v in task_diagnostics.items() if k.startswith('pendiente_')) == len(evidence)
    result = dict(t0=data['t0'], snapshot_sha256=hashlib.sha256(source).hexdigest(),
                  hipotesis=f'Activacion T0, parametros aprobados, stock sin prorrogas retroactivas, {len(evidence)} contextos demostrados',
                  global_=aggregate(rows), por_etapa={stage: aggregate([r for r in rows if r['etapa'] == stage]) for stage in STAGES},
                  cohortes_politica=dict(sorted(cohort_policy.items())),
                  tareas=dict(sorted(task_diagnostics.items())), cadenas_reprogramacion=dict(sorted(reprogram_chains.items())),
                  enlaces_pendientes_por_estado_origen=dict(sorted(parent_transitions.items())),
                  criterio_reprogramaciones='El umbral se lee del contador persistido de la tarea elegida. Un enlace desde no_show es seguimiento nuevo, no una reprogramacion por si mismo; los reemplazos desde reprogramada deben heredar contador+1.', filas=rows)
    args.out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'filas'}, ensure_ascii=False, indent=2))
    print(f'Archivo: {args.out}')
    if args.comparar:
        parity = compare(result, json.loads(args.comparar.read_text()))
        args.paridad.write_text(json.dumps(parity, ensure_ascii=False, indent=2) + '\n')
        print(f'Paridad: {parity["comparaciones"]} comparaciones, {parity["discrepancias"]} discrepancias; {args.paridad}')
        assert parity['discrepancias'] == 0, 'El nucleo y el oraculo difieren'


if __name__ == '__main__':
    main()

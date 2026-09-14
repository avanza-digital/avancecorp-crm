#!/usr/bin/env python3
"""Ensayo completo en una copia Docker local, que se elimina al terminar.

El template solo se lee. No recibe URLs, contraseñas ni referencias remotas.
"""
import json
import difflib
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid

HERE = Path(__file__).resolve().parent
SCRIPTS = HERE.parent
MIGRATION = SCRIPTS.parent / 'migrations/20260914042114_crm_tasas_inferiores_nuevas_inversiones.sql'
CONTAINER = 'supabase_db_avancecorp-f4-bank'
TEMPLATE = 'crm_push_tasa_release_20260910'
BANK = 'crm_tasa_baja_' + uuid.uuid4().hex[:12]
assert re.fullmatch(r'crm_tasa_baja_[a-f0-9]{12}', BANK)
LOG = []


def run(args, source=None, expected=None):
    started = time.monotonic()
    result = subprocess.run(args, input=source, text=True, capture_output=True, timeout=120)
    LOG.append({'command': args, 'code': result.returncode, 'seconds': round(time.monotonic()-started, 3),
                'stdout': result.stdout, 'stderr': result.stderr, 'expected_error': expected})
    if expected:
        assert result.returncode != 0 and expected in result.stderr, result.stderr
    else:
        assert result.returncode == 0, result.stderr
    return result.stdout


def sql(source, expected=None):
    return run(['docker','exec','-i',CONTAINER,'psql','-X','-U','supabase_admin','-d',BANK,
                '-v','ON_ERROR_STOP=1','-Atq','-f','-'], source, expected)


fingerprints = """select json_agg(json_build_object('firma',p.oid::regprocedure::text,'md5',md5(p.prosrc),
 'owner',pg_get_userbyid(p.proowner),'acl',p.proacl,'definer',p.prosecdef,'config',p.proconfig) order by p.oid::regprocedure::text)
 from pg_proc p where p.oid in ('private.resolver_tasa(uuid,text,uuid,timestamptz,uuid)'::regprocedure,
 'private.validar_tasa_conversion_lead(uuid,uuid,jsonb,boolean)'::regprocedure,
 'private.trg_contratos_observar_rentabilidad()'::regprocedure,
 'public.crear_contrato(jsonb,jsonb)'::regprocedure);"""
created = False
try:
    run(['docker','exec',CONTAINER,'createdb','-U','supabase_admin','--template='+TEMPLATE,BANK])
    created = True
    before = json.loads(sql(fingerprints))
    sql(MIGRATION.read_text())
    after = json.loads(sql(fingerprints))
    assert len(before)==len(after)==4
    for old, new in zip(before,after):
        assert old['md5'] != new['md5']
        assert {k:v for k,v in old.items() if k!='md5'} == {k:v for k,v in new.items() if k!='md5'}, 'Cambió owner/ACL/search_path/definer'
    originals = json.loads((HERE/'base-viva-funciones.json').read_text())
    originals.append(json.loads((HERE/'alta-viva-funcion.json').read_text()))
    rollback = """-- Solo antes del primer uso de una tasa inferior. Revisión humana antes de publicar.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
-- Drena también las lecturas/bloqueos del lead que preceden a validar una reserva.
-- Si no puede obtenerse en 5 segundos, se aborta sin restaurar ninguna función.
lock table public.contratos,crm.leads,crm.conversion_reservas,crm.ledger_rentabilidad in access exclusive mode;
do $preflight$ begin
 if exists(select 1 from crm.ledger_rentabilidad where detalle->>'tasa_inferior_sin_excepcion'='true') then
   raise exception 'Ya existen tasas inferiores registradas: corregir hacia delante; no restaurar el candado anterior';
 end if;
 if exists(
   select 1 from crm.conversion_reservas r join crm.leads l on l.id=r.lead_id
   cross join lateral (
     select p.tasa_base_nueva from crm.politica_rentabilidad p
     where p.vigente_desde<=coalesce(r.efectos_iniciados_en,r.reservado_en)
     order by p.vigente_desde desc,p.version desc limit 1
   ) vigente
   where r.condiciones_tasa->>'categoria'='nuevo'
     and (r.condiciones_tasa->>'tasa_anual')::numeric<greatest(vigente.tasa_base_nueva,
       (select p.tasa_base_nueva from crm.politica_rentabilidad p where p.vigente_desde<=now()
        order by p.vigente_desde desc,p.version desc limit 1))
     and (r.expira_en>now() or r.efectos_iniciados_en is not null or l.etapa='convertido')
 ) then
   raise exception 'Hay conversiones comprometidas con una tasa inferior: corregir hacia delante, aunque aún no exista contrato';
 end if;
"""
    for row in after:
        rollback += f" if (select md5(prosrc) from pg_proc where oid=to_regprocedure('{row['firma']}')) is distinct from '{row['md5']}' then raise exception 'La función {row['firma']} cambió después de la candidata'; end if;\n"
    rollback += 'end; $preflight$;\n'
    rollback += '\n'.join(r['definicion']+';' for r in originals if r['funcion']!='resolver_tasa' or 'p_contrato_nuevo_id' in r['argumentos'])
    rollback += "\ndrop function private.rentabilidad_minimo_alta(text,numeric);\nnotify pgrst, 'reload schema';\ncommit;\n"
    sql(rollback)
    assert json.loads(sql(fingerprints))==before,'La reversa no restauró exactamente funciones y permisos'
    sql(MIGRATION.read_text())
    (HERE/'revertir-antes-del-primer-uso.sql').write_text(rollback)
    print('PASS: instalación, propietarios/permisos preservados y reversa exacta antes del primer uso', flush=True)
    variantes = []
    for filename in ['test-tasa-pendiente.sql','test-tasa-lead.sql']:
        original = (SCRIPTS/filename).read_text()
        sql(original)
        print('PASS: regresión '+filename, flush=True)
        lower = original.replace('pg_temp.alta(15','pg_temp.alta(12.5').replace('pg_temp.intencion(15)','pg_temp.intencion(12.5)')
        assert lower != original
        variantes.extend(difflib.unified_diff(original.splitlines(True),lower.splitlines(True),fromfile=filename,tofile=filename+'.tasa-12.5'))
        sql(lower)
        print('PASS: pendientes, límites y permisos de '+filename+' con 12.5%', flush=True)
    (HERE/'variantes-regresion.patch').write_text(''.join(variantes))
    concurrency = (SCRIPTS/'tasa-lead/test-concurrencia-local.py').read_text()
    concurrency = concurrency.replace("r'tasa_lead_concurrencia_\\d{8}'", "r'crm_tasa_baja_[a-f0-9]{12}'")
    concurrency = concurrency.replace('"tasa_anual":15','"tasa_anual":12.5')
    run([sys.executable,'-c',concurrency,BANK])
    print('PASS: dos sesiones concurrentes, la solicitud bloquea la reserva a 12.5%', flush=True)
    run([sys.executable,str(HERE/'test-concurrencia-reversa-local.py'),BANK])
    print('PASS: reversa/reserva concurrentes en ambas órdenes, bloqueo real y rechazo seguro', flush=True)
    sql((HERE/'test-reversa-conversion.sql').read_text())
    sql(rollback, 'Hay conversiones comprometidas con una tasa inferior')
    assert json.loads(sql(fingerprints))==after,'La reversa bloqueada por conversión alteró las funciones'
    print('PASS: reversa rechazada después de sellar una conversión a 12.5, antes del contrato', flush=True)
    sql((HERE/'test-tasa-baja.sql').read_text())
    print('PASS: tasas/roles, auditoría, herencia, correcciones y conversión completa a contrato', flush=True)
    sql(rollback, 'Ya existen tasas inferiores registradas')
    assert json.loads(sql(fingerprints))==after,'La reversa bloqueada alteró las funciones'
    sql(MIGRATION.read_text(), 'cambió. Revisar')
    print('PASS: evita reaplicar y bloquea la reversa después del primer uso', flush=True)
finally:
    if created:
        run(['docker','exec',CONTAINER,'dropdb','-U','supabase_admin',BANK])
    (HERE/'evidencias-local.json').write_text(json.dumps(LOG,ensure_ascii=False,indent=2)+'\n')

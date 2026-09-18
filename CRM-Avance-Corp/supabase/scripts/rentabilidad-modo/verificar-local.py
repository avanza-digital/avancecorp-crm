#!/usr/bin/env python3
"""Banco propio y desechable. Solo Docker local, sin destinos remotos."""
import json
from pathlib import Path
import subprocess
import uuid

HERE = Path(__file__).resolve().parent
SCRIPTS = HERE.parent
CONTAINER = 'supabase_db_avancecorp-f4-bank'
BANK = 'crm_modo_tasa_' + uuid.uuid4().hex[:12]
MIGRATION = SCRIPTS.parent / 'migrations/20260918210543_crm_modo_rentabilidad_integral.sql'
LOG = []
def run(args, source=None):
    result = subprocess.run(args, input=source, text=True, capture_output=True, timeout=120)
    LOG.append({'comando':args,'codigo':result.returncode,'salida':result.stdout,'error':result.stderr})
    if result.returncode:
        raise RuntimeError(result.stderr)
    return result.stdout
def sql(source):
    return run(['docker','exec','-i',CONTAINER,'psql','-X','-U','supabase_admin','-d',BANK,
                '-v','ON_ERROR_STOP=1','-Atq','-f','-'], source)
created = False
try:
    run(['docker','exec',CONTAINER,'createdb','-U','supabase_admin','--template=crm_push_tasa_release_20260910',BANK])
    created = True
    sql((SCRIPTS.parent/'migrations/20260914042114_crm_tasas_inferiores_nuevas_inversiones.sql').read_text())
    originals = json.loads((HERE/'base-funciones.json').read_text())
    # El template F4 precede el transporte del origen upgrade. Restaurar las
    # puertas vigentes capturadas por SELECT; no son parte de la migración.
    puertas = json.loads((HERE/'base-puertas.json').read_text())
    sql('\n'.join(definicion+';' for definicion in puertas.values()))
    # Paridad exacta de las funciones intervenidas sobre fixture sintético.
    sql('\n'.join(r['definicion']+';' for r in originals))
    fingerprint = """select json_agg(json_build_object('firma',p.oid::regprocedure::text,'huella',md5(p.prosrc),
      'owner',p.proowner,'acl',p.proacl,'config',p.proconfig,'definer',p.prosecdef,'volatilidad',p.provolatile)
      order by p.oid::regprocedure::text) from pg_proc p where p.oid in (%s);""" % ','.join(
      "'%s'::regprocedure" % r['firma'] for r in originals)
    before=json.loads(sql(fingerprint))
    sql(MIGRATION.read_text())
    after=json.loads(sql(fingerprint))
    assert len(before)==len(after)==8
    for a,b in zip(before,after):
        assert a['huella'] != b['huella']
        assert {k:v for k,v in a.items() if k!='huella'}=={k:v for k,v in b.items() if k!='huella'}
    print('PASS: ocho funciones actualizadas conservando firma, propietario, permisos y configuración',flush=True)
    # Regresión de enforcement y fixture de contratos para los nuevos escenarios.
    sql((SCRIPTS/'tasa-baja/test-tasa-baja.sql').read_text())
    print('PASS: tasas inferiores, límites, herencia, corrección y conversión previas',flush=True)
    sql((SCRIPTS/'test-tasa-pendiente.sql').read_text())
    sql((SCRIPTS/'test-tasa-lead.sql').read_text())
    print('PASS: pendientes y conversión previa con candado activo',flush=True)
    sql((HERE/'test-modo.sql').read_text())
    print('PASS: observación, solicitudes anteriores, límites y reactivación con el mismo interruptor',flush=True)
    sql((HERE/'reversa.sql').read_text())
    assert json.loads(sql(fingerprint)) == before
    print('PASS: reversa restaura exactamente las ocho funciones y sus permisos',flush=True)
finally:
    if created:
        run(['docker','exec',CONTAINER,'dropdb','-U','supabase_admin',BANK])
    (HERE/'evidencia-local.json').write_text(json.dumps(LOG,ensure_ascii=False,indent=2)+'\n')

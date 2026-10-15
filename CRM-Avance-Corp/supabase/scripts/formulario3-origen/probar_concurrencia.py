"""Prueba dos sesiones reales: importación previa y activación concurrente, solo Docker."""
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

BASE = sys.argv[1] if len(sys.argv) == 2 else ''
if not re.fullmatch(r'origen_f3_[a-z0-9_]+', BASE):
    raise SystemExit('Se requiere una copia exclusiva origen_f3_* con A y sin B')
DIR = Path(__file__).resolve().parent
CMD = ['docker','exec','-i','avancecorp-coordinacion-pg-actual','psql','-XqAt',
       '-U','postgres','-d',BASE,'-v','ON_ERROR_STOP=1']
def sql(s):
    r = subprocess.run(CMD,input=s,text=True,capture_output=True)
    if r.returncode: raise RuntimeError(r.stderr + r.stdout)
    return r.stdout.strip()

sql('begin;\n' + (DIR/'fixtures.sql').read_text() + '\ncommit;')
payload = """'{"nombre_completo":"CONCURRENCIA SINTETICA","telefono":"985000098", "origen":"formulario",
 "campania_origen":"Formulario 3","monto_estimado":1000,"moneda":"PEN"}'::jsonb"""
writer = subprocess.Popen(CMD,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
try:
    writer.stdin.write('begin; select crm.importar_lead_fn(' + payload + "); select 'WRITER_LISTO';\n")
    writer.stdin.flush()
    while True:
        line = writer.stdout.readline()
        if not line: raise RuntimeError(writer.stderr.read())
        if 'WRITER_LISTO' in line: break
    b = (DIR.parents[1]/'migrations/20261015173031_crm_formulario3_origen_activacion.sql').read_text()
    with ThreadPoolExecutor(max_workers=1) as executor:
        tarea = executor.submit(sql, "set application_name='f3_activacion_concurrente';\n" + b)
        bloqueado = False
        for _ in range(30):
            bloqueado = sql("select exists(select 1 from pg_stat_activity where application_name='f3_activacion_concurrente' and wait_event_type='Lock');") == 't'
            if bloqueado: break
            time.sleep(0.1)
        if not bloqueado: raise RuntimeError('La activación no esperó al escritor previo')
        writer.stdin.write('commit;\n')
        writer.stdin.close()
        writer.wait(timeout=10)
        assert writer.returncode == 0
        tarea.result(timeout=15)
    assert sql("select count(*)=1 and bool_and(origen='formulario_3') from crm.leads;") == 't'
    assert 'duplicado' in sql('select crm.importar_lead_fn(' + payload + ');')
    nuevo = payload.replace('985000098','985000097')
    assert 'importado' in sql('select crm.importar_lead_fn(' + nuevo + ');')
    assert sql("select count(*)=2 and bool_and(origen='formulario_3') from crm.leads;") == 't'
    print('PASS: B esperó al escritor legado, reclasificó su alta, conservó el recibo y normalizó la siguiente sin duplicados')
finally:
    if writer.poll() is None:
        writer.terminate()
        writer.wait(timeout=10)

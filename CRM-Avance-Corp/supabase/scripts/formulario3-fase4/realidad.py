#!/usr/bin/env python3
"""Corre el gate de solo lectura; la clave vive únicamente en memoria."""
import datetime
import json
import os
from pathlib import Path
import subprocess

REF = 'dctqcbznekcyxhjujuci'
EVIDENCIA = Path(__file__).resolve().parent
RAIZ = EVIDENCIA.parents[2]

respuesta = subprocess.run(
    ['supabase', 'projects', 'api-keys', '--project-ref', REF, '--output', 'json'],
    capture_output=True, text=True,
)
if respuesta.returncode:
    raise SystemExit('No se pudo obtener la credencial administrativa local; no se imprime su salida.')
clave = next(x['api_key'] for x in json.loads(respuesta.stdout) if x['name'] == 'service_role')
entorno = {**os.environ, 'SUPABASE_URL': f'https://{REF}.supabase.co', 'SUPABASE_SERVICE_ROLE_KEY': clave}
resultado = subprocess.run(
    ['node', 'supabase/scripts/gate-realidad.mjs', '--json', '--sql-project-ref', REF],
    env=entorno, cwd=RAIZ, capture_output=True, text=True,
)
(EVIDENCIA / 'gate-realidad.json').write_text(resultado.stdout.replace(clave, '[REDACTADO]'))
salida = {'exit_code': resultado.returncode, 'proyecto': REF,
          'modo': 'Administrativo explícito, SQL READ ONLY para sellos y conversión',
          'instante': datetime.datetime.now(datetime.timezone.utc).isoformat()}
(EVIDENCIA / 'gate-realidad-exit.json').write_text(json.dumps(salida, indent=2) + '\n')
print(json.dumps(salida))
raise SystemExit(resultado.returncode)

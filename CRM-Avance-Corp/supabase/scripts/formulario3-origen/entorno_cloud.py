"""Obtiene credenciales de la única rama autorizada; nunca las imprime."""
import json
import os
import subprocess
from pathlib import Path

REF = 'yefiownpxvembwvfbtfx'
BRANCH = 'formulario3-origen-nativo-20261015'
PRIVATE = Path('/private/tmp/formulario3-origen-privado')
result = subprocess.run([
    'supabase', 'branches', 'get', BRANCH, '--project-ref',
    'dctqcbznekcyxhjujuci', '--output', 'json',
], capture_output=True, text=True)
if result.returncode:
    raise SystemExit('No se obtuvieron las credenciales; salida privada omitida')
try:
    data = json.loads(result.stdout)
except json.JSONDecodeError:
    raise SystemExit('CLI no devolvió JSON; salida privada omitida') from None
assert data.get('SUPABASE_URL') == f'https://{REF}.supabase.co'
assert data.get('SUPABASE_ANON_KEY') and data.get('SUPABASE_SERVICE_ROLE_KEY')
PRIVATE.mkdir(mode=0o700, exist_ok=True)
os.chmod(PRIVATE, 0o700)
target = PRIVATE / 'branch.json'
fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, 'w') as f:
    json.dump({key: data[key] for key in (
        'SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY',
    )}, f)
os.chmod(target, 0o600)
print(json.dumps({'rama': BRANCH, 'ref': REF, 'campos': sorted(data), 'modo': '0600'}))

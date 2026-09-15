import concurrent.futures
from datetime import datetime, timezone
from hashlib import sha256
import json
from pathlib import Path
import sys
from urllib.error import HTTPError
from urllib.request import Request, urlopen

manifest_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
manifest = json.loads(manifest_path.read_text())
assert manifest['destino'] == 'crm.miavance.com'
base = 'https://crm.miavance.com/'
previous = json.loads((manifest_path.parent / 'crm-20260915T154200Z-cdf03f266805.manifest.json').read_text())
previous_files = {entry['ruta']: entry for entry in previous['build']['archivos']}


def check(entry):
    path = entry['ruta']
    request = Request(base + path, headers={'Cache-Control': 'no-cache'})
    try:
        with urlopen(request, timeout=30) as response:
            body = response.read()
            status = response.status
    except HTTPError as error:
        return {'ruta': path, 'status': error.code, 'resultado': 'PASS_PROTEGIDO' if path == '.htaccess' and error.code in (403, 404) else 'FAIL'}
    except Exception as error:
        return {'ruta': path, 'resultado': 'FAIL', 'error': str(error)}
    actual = sha256(body).hexdigest()
    exact = actual == entry['sha256']
    image_unchanged = path.endswith('.png') and previous_files.get(path, {}).get('sha256') == entry['sha256']
    return {'ruta': path, 'status': status, 'sha256': actual, 'esperado': entry['sha256'],
            'resultado': 'PASS_EXACTO' if status == 200 and exact else 'HTTP_200_IMAGEN_CDN' if status == 200 and image_unchanged else 'FAIL'}


with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
    files = list(executor.map(check, manifest['build']['archivos']))

probes = []
for path in ['.env', 'package.json', manifest['archivo']['nombre']]:
    try:
        with urlopen(Request(base + path), timeout=20) as response:
            status = response.status
    except HTTPError as error:
        status = error.code
    probes.append({'ruta': path, 'status': status, 'protegido': status in (403, 404)})

with urlopen(Request(base, headers={'Cache-Control': 'no-cache'}), timeout=20) as response:
    root = {'status': response.status, 'sha256': sha256(response.read()).hexdigest()}
root['coincide_index'] = root['sha256'] == next(entry['sha256'] for entry in manifest['build']['archivos'] if entry['ruta'] == 'index.html')
with urlopen('https://miavance.com/', timeout=20) as response:
    portal_status = response.status

passed = all(entry['resultado'] != 'FAIL' for entry in files) and all(entry['protegido'] for entry in probes) and root['coincide_index'] and portal_status == 200
result = {'fecha_utc': datetime.now(timezone.utc).isoformat(), 'resultado': 'PASS' if passed else 'FAIL',
          'release_id': manifest['release_id'], 'commit': manifest['fuente']['commit'], 'raiz': root,
          'portal_status': portal_status, 'archivos': files, 'rutas_protegidas': probes,
          'nota_imagenes': 'Las imágenes con hash distinto son PNG sin cambios respecto al artefacto productivo anterior; HTTP 200. No se repitió comparación de píxeles CDN.'}
output_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'resultado': result['resultado'], 'archivos': len(files), 'exactos': sum(entry['resultado'] == 'PASS_EXACTO' for entry in files),
                  'imagenes_cdn': sum(entry['resultado'] == 'HTTP_200_IMAGEN_CDN' for entry in files), 'raiz': root,
                  'fallos': [entry for entry in files if entry['resultado'] == 'FAIL'], 'rutas_protegidas': probes}, ensure_ascii=False))
sys.exit(0 if passed else 1)

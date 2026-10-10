#!/usr/bin/env python3
"""Genera 14 muestras y compara TODO su texto con v9/anexo v1.
Uso desde CRM: python3 supabase/scripts/banco-pdf-v10/generar-muestras.py
Datos ficticios. Requiere deno y pdftotext. No accede a la base ni a la red.
"""
from pathlib import Path
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
BANK = Path(__file__).resolve().parent
OUT = ROOT / 'output/pdf/correcciones-20261010'
BASE = '426499c338ad6359462fcd2c5b9d035ff04f147b'
CASES = {
    'individual-soles': [],
    'individual-dolares': ['--moneda=USD'],
    'mancomunado-soles': ['--cotitulares=1'],
    'mancomunado-dolares-5-cotitulares': ['--cotitulares=5', '--moneda=USD'],
    'compuesto-dolares-2-anios': ['--compuesto', '--anios=2', '--moneda=USD'],
    'mensual-soles-60-cuotas': ['--anios=5'],
    'trimestral-soles-2-anios': ['--modalidad=trimestral', '--anios=2'],
}
OUT.mkdir(parents=True, exist_ok=True)
manifest = []
for case, args in CASES.items():
    for tipo in ['contrato', 'anexo']:
        command = ['deno', 'run', '--allow-read', '--allow-write',
                   str(ROOT/'supabase/functions/crm-contrato-pdf-v2/_render-muestra.ts'),
                   str(OUT/f'{tipo}-{case}.pdf'), '2026-09-01T12:00:00Z', *args]
        command += ['--anexo'] if tipo == 'anexo' else [f'--snapshot={OUT/case}.json']
        result = subprocess.run(command, check=True, capture_output=True, text=True)
        row = json.loads(result.stdout)
        row['destino'] = Path(row['destino']).name
        manifest.append(row)
(OUT/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
with tempfile.TemporaryDirectory(prefix='avancecorp-pdf-v10-') as folder:
    tmp = Path(folder)
    source = tmp/'v9'
    source.mkdir()
    # Lista cerrada: solo código y vendor PDF, sin entornos/credenciales.
    for name in ['renderer.ts','handler.ts','storage.ts','template-v2.ts','anexo-v1.ts',
                 'assets-v2.ts','pdfmake-0.2.20-pdfprinter.js','vfs-fonts-0.2.20.js']:
        (source/name).write_bytes(subprocess.check_output(['git','show',
          f'{BASE}:CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/{name}'],cwd=ROOT))
    before = tmp/'antes'
    before.mkdir()
    driver = tmp/'antes.ts'
    driver.write_text('''import {renderizarAnexoPdfV1,renderizarContratoPdfV2} from './v9/renderer.ts';
const origen=Deno.args[0], destino=Deno.args[1];
for await(const file of Deno.readDir(origen)) {
 if(!file.name.endsWith('.json') || file.name==='manifest.json') continue;
 const snapshot=JSON.parse(await Deno.readTextFile(`${origen}/${file.name}`));
 for(const tipo of ['contrato','anexo']) {
  const r=await (tipo==='contrato'?renderizarContratoPdfV2:renderizarAnexoPdfV1)(snapshot,'2026-09-01T12:00:00Z');
  await Deno.writeFile(`${destino}/${tipo}-${file.name.replace('.json','.pdf')}`,new Uint8Array(await r.blob.arrayBuffer()));
 }
}
''')
    subprocess.run(['deno','run','--allow-read','--allow-write',str(driver),str(OUT),str(before)],check=True)
    report = subprocess.check_output(['python3',str(BANK/'comparar-pdf.py'),str(before),str(OUT)],text=True)
    print(report)

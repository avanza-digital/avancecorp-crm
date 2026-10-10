#!/usr/bin/env python3
"""Construye una Edge v9/anexo v1 que TAMBIÉN descarga documentos v10.

Solo prepara archivos locales en una carpeta NUEVA. No despliega ni toca SQL.
Uso: python3 preparar-reversa.py /private/tmp/edge-reversa-v10
"""
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "supabase/functions/crm-contrato-pdf-v2"
BASE_COMMIT = "426499c338ad6359462fcd2c5b9d035ff04f147b"
destination = Path(sys.argv[1]).resolve()
if destination.exists():
    raise SystemExit("El destino debe ser nuevo; no se sobrescribe ningún artefacto")

shutil.copytree(SOURCE, destination,
                ignore=shutil.ignore_patterns("node_modules", ".DS_Store"))
# Solo vuelve el renderer. Las validaciones y el lector de históricos actuales
# se conservan; un git checkout completo del commit viejo rompería lectura v10.
for name in ["template-v2.ts", "assets-v2.ts", "anexo-v1.ts", "renderer.ts", "renderer.test.ts"]:
    original = subprocess.check_output([
        "git", "show", f"{BASE_COMMIT}:CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/{name}"
    ], cwd=ROOT)
    (destination / name).write_bytes(original)

handler = destination / "handler.ts"
text = handler.read_text()
if 'CONTRATO_PDF_TEMPLATE_VERSION = "contrato-aep-17-v10"' not in text:
    raise SystemExit('La Edge de partida no estampa v10')
text = text.replace('CONTRATO_PDF_TEMPLATE_VERSION = "contrato-aep-17-v10"',
                    'CONTRATO_PDF_TEMPLATE_VERSION = "contrato-aep-17-v9"', 1)
anexo_needle = 'ANEXO_PDF_TEMPLATE_VERSION = "anexo-cronograma-v2"'
if text.count(anexo_needle) != 1:
    raise SystemExit("La versión del anexo cambió; revisar la reversa")
text = text.replace(anexo_needle,
                    'ANEXO_PDF_TEMPLATE_VERSION = "anexo-cronograma-v1"', 1)
needle = 'valor === "contrato-aep-17-v9" ||'
if text.count(needle) != 1:
    raise SystemExit('El lector histórico cambió; revisar la reversa antes de construirla')
text = text.replace(needle, needle + '\n    valor === "contrato-aep-17-v10" ||', 1)
handler.write_text(text)
tests = destination / "handler.test.ts"
text = tests.read_text()
if 'for (const version of [3, 4, 7, 8, 9])' not in text:
    raise SystemExit('La matriz de versiones cambió; adaptar las pruebas de reversa')
tests.write_text(text.replace('for (const version of [3, 4, 7, 8, 9])',
                              'for (const version of [3, 4, 7, 8, 9, 10])', 1))
# Postcondiciones obligatorias: estos golden pertenecen al renderer anterior.
goldens = ["6ffb935d939e4ba7f4c5822835d81cf6bac0a8b04bb1b011a1b629a9b1ffe1d8", "9639f4a48294c631434db945e2ae60057a8fd753b69389b1392ece00b71bc3dc", "218672", "165463"]
if not all(g in (destination / "renderer.test.ts").read_text() for g in goldens):
    raise SystemExit("El oráculo del renderer anterior cambió; verificar los golden")
test_files = ["handler.test.ts", "renderer.test.ts", "storage.test.ts"]
subprocess.run(["deno", "check", "--config", "deno.json", "index.ts", *test_files], cwd=destination, check=True)
subprocess.run(["deno", "test", "--config", "deno.json", "--allow-read", *test_files], cwd=destination, check=True)
print(f"Preparada y verificada reversa en {destination}; base {BASE_COMMIT}")

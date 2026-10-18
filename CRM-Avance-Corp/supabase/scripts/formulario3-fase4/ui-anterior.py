#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import sys
ROOT = Path(__file__).resolve().parent
CRM = ROOT.parents[2]
args = ['docker','run','--rm','--init','--ipc=host','--name','formulario3-fase4-anterior','--label','avancecorp.task=formulario3-fase4','-e','CI=1','-v',str(CRM/'app')+':/app','-v','formulario3-fase4-e2e:/app/node_modules','-v','/private/tmp/formulario3-fase4-anterior:/f4-anterior:ro','-v','/private/tmp/formulario3-fase4-privado:/f4-privado:ro','-w','/app','mcr.microsoft.com/playwright:v1.61.1-noble','npx','playwright','test','--config','playwright.formulario3-anterior.config.ts']
p = subprocess.run(args, capture_output=True, text=True)
salida = re.sub(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+','[JWT OMITIDO]',p.stdout+p.stderr)
(ROOT/'ui-anterior.log').write_text(salida)
print(salida[-8000:])
sys.exit(p.returncode)

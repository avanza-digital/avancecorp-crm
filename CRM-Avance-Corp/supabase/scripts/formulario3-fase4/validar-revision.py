#!/usr/bin/env python3
"""Comprueba observaciones del reviewer sin modificar datos del CRM."""
from pathlib import Path
import json
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent
CRM = ROOT.parents[2]
PROD = 'dctqcbznekcyxhjujuci'
resultados = {}

with tempfile.TemporaryDirectory(prefix='formulario3-cli-destino-') as d:
    base = Path(d)
    (base / 'supabase/.temp').mkdir(parents=True)
    (base / 'supabase/.temp/project-ref').write_text('aaaaaaaaaaaaaaaaaaaa')
    (base / 'supabase/config.toml').write_text('project_id = "formulario3-destino-prueba"\n')
    version = subprocess.run(['supabase', '--version'], capture_output=True, text=True, check=True).stdout.strip()
    sql = "begin read only; select current_setting('transaction_read_only') as solo_lectura, (select is_nullable from information_schema.columns where table_schema='crm' and table_name='periodos_cerrados' and column_name='meta_revision') as meta_revision_nullable, has_schema_privilege('anon','crm','usage') as anon_crm, has_table_privilege('anon','crm.leads','insert') as anon_insert, has_table_privilege('anon','crm.leads','select') as anon_select, has_table_privilege('anon','crm.leads','update') as anon_update; rollback;"
    r = subprocess.run(['supabase', 'db', 'query', '--linked', '--project-ref', PROD, '--output', 'json', sql], cwd=base, capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError('La comprobación del destino SQL falló; no se presume el destino.')
    rows = json.loads(r.stdout)['rows']
    assert rows == [{'solo_lectura':'on', 'meta_revision_nullable':'NO', 'anon_crm':False, 'anon_insert':False, 'anon_select':False, 'anon_update':False}]
    resultados['cli_destino'] = {'estado':'PASS', 'version':version, 'enlace_local_ficticio':'aaaaaaaaaaaaaaaaaaaa', 'destino_explicito':PROD, 'resultado':rows}

with tempfile.TemporaryDirectory(prefix='formulario3-rls-fallo-') as d:
    docker = Path(d) / 'docker'
    docker.write_text('#!/bin/sh\nexit 73\n')
    docker.chmod(0o700)
    resultados['rls_fallo'] = []
    for opcion in ['--formulario3', '--formulario3-fase2']:
        r = subprocess.run(['node', 'supabase/scripts/test-rls.mjs', opcion], cwd=CRM, env={**os.environ, 'PATH': d + os.pathsep + os.environ['PATH']}, capture_output=True, text=True)
        assert r.returncode != 0, 'El gate ocultó un fallo de Docker'
        resultados['rls_fallo'].append({'opcion':opcion, 'exit_code':r.returncode, 'estado':'PASS: el fallo no se oculta'})

(ROOT / 'revision-evidencia.json').write_text(json.dumps(resultados, indent=2) + '\n')
print(json.dumps(resultados))

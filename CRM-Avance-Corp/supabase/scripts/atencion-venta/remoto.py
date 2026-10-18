#!/usr/bin/env python3
"""SQL solo en la rama temporal autorizada; credenciales fuera del repositorio."""
import json
import os
import re
import subprocess
import sys
import uuid
from pathlib import Path
from urllib.parse import unquote, urlsplit

REF = 'cdntljznxaubchkhusqo'
BRANCH_ID = '77b7b326-3c2e-4cde-975e-ddb84996d016'
CFG = json.loads(Path('/private/tmp/atencion-branch-access.json').read_text())
assert CFG['SUPABASE_URL'] == f'https://{REF}.supabase.co'
URI = urlsplit(CFG['POSTGRES_URL'])
assert unquote(URI.username) == f'postgres.{REF}'
assert URI.hostname.endswith('.pooler.supabase.com') and URI.path == '/postgres'
ENV = {k: v for k, v in os.environ.items() if not k.startswith('PG')}
ENV.update(PGHOST=URI.hostname, PGPORT='5432', PGDATABASE='postgres',
           PGUSER=unquote(URI.username), PGPASSWORD=unquote(URI.password),
           PGSSLMODE='require', PGCONNECT_TIMEOUT='15', PGAPPNAME='atencion_venta_banco')
PSQL = '/opt/homebrew/opt/postgresql@17/bin/psql'


def sql(source):
    source = re.sub(r'^\\(?:un)?restrict[^\n]*\n', '', source, flags=re.MULTILINE)
    tag = 'banco_' + uuid.uuid4().hex
    source = f"SET statement_timeout='240s';\nSELECT ${tag}$\n{source}\n${tag}$\n\\gexec\n"
    result = subprocess.run([PSQL, '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-f', '-'],
                            input=source, env=ENV, text=True, capture_output=True, timeout=300)
    if result.returncode:
        path = Path('/private/tmp/atencion-remoto-error.txt')
        path.write_text(result.stderr)
        path.chmod(0o600)
        raise RuntimeError('Falló SQL del banco; diagnóstico privado en /private/tmp/atencion-remoto-error.txt')
    return result.stdout.strip()


if __name__ == '__main__':
    assert len(sys.argv) == 2, 'Uso: remoto.py archivo.sql'
    # Los literales SQL pueden contener CR; read_text normaliza CRLF y los altera.
    print(sql(Path(sys.argv[1]).read_bytes().decode('utf8')))

#!/usr/bin/env python3
"""SQL exclusivamente en la rama temporal autorizada; credenciales fuera del repo."""
import json
import os
import re
import subprocess
import sys
import uuid
from pathlib import Path
from urllib.parse import unquote, urlsplit

REF = 'zlqywmvvtfknypkmfpbe'
CFG = json.loads(Path('/private/tmp/reasignacion-rama-privada.json').read_text())
assert CFG['SUPABASE_URL'] == f'https://{REF}.supabase.co'
URI = urlsplit(CFG['POSTGRES_URL'])
assert unquote(URI.username) == f'postgres.{REF}'
assert URI.hostname.endswith('.pooler.supabase.com') and URI.path == '/postgres'
ENV = dict(os.environ, PGHOST=URI.hostname, PGPORT='5432', PGDATABASE='postgres',
           PGUSER=unquote(URI.username), PGPASSWORD=unquote(URI.password),
           PGSSLMODE='require', PGCONNECT_TIMEOUT='15')
PSQL = '/opt/homebrew/opt/postgresql@17/bin/psql'


def sql(source):
    # Una consulta simple con varias sentencias evita miles de viajes de red
    # durante la restauración. \gexec ejecuta un único campo generado por SELECT.
    source = re.sub(r'^\\(?:un)?restrict[^\n]*\n', '', source, flags=re.MULTILINE)
    tag = 'banco_' + uuid.uuid4().hex
    source = f'SELECT ${tag}$\n{source}\n${tag}$\n\\gexec\n'
    result = subprocess.run([PSQL, '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-f', '-'],
                            input=source, env=ENV, text=True, capture_output=True, timeout=240)
    if result.returncode:
        path = Path('/private/tmp/reasignacion-remoto-error.txt')
        path.write_text(result.stderr)
        path.chmod(0o600)
        raise RuntimeError('Falló SQL de la rama; diagnóstico en /private/tmp/reasignacion-remoto-error.txt')
    return result.stdout, result.stderr


if __name__ == '__main__':
    out, notices = sql(Path(sys.argv[1]).read_text())
    print(out)
    print(notices, file=sys.stderr)

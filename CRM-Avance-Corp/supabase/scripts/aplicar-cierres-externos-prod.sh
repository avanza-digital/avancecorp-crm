#!/bin/bash
# Aplica la migración de CIERRES EXTERNOS a PRODUCCIÓN y la registra.
#
# POR QUÉ EXISTE ESTE GUION: el merge del branch está roto del lado de Supabase
# (los proyectos de branch no quedan registrados en su Management API → el
# workflow de merge muere con 404 antes de aplicar nada; 3 branches, 3 veces).
# Miguel autorizó la aplicación directa el 2026-08-12. Este guion la hace por el
# MISMO canal que usaría el merge (Management API) y con el MISMO fichero que
# pasó el ciclo entero en el branch: oráculo 28 casos, RLS 914/914, advisors 0
# ERROR, regresión de conversión idéntica.
#
# QUÉ HACE, en orden:
#   1. Lee la migración y muestra su huella SHA-256 (debe ser 3b31407311cb5371…).
#   2. La manda a producción. El fichero es UNA transacción con preflight de
#      anclas md5 (si producción cambió, ABORTA sin tocar nada) y postflight de
#      11 veredictos (si algo no cuadra, TODO se deshace).
#   3. Si aplicó bien, la registra en supabase_migrations.schema_migrations con
#      su contenido íntegro (lo que el CLI haría).
#   4. Verifica: tabla creada, funciones nuevas, conteo DEFINER 159→167.
set -euo pipefail
REF="dctqcbznekcyxhjujuci"
MIG="/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp/supabase/migrations/20260812000259_crm_cierres_externos.sql"
TOKEN=$(security find-generic-password -s 'Supabase CLI' -w)

echo "— huella del fichero que se va a aplicar —"
shasum -a 256 "$MIG"

api() {
  python3 - "$1" <<'PY'
import json, sys, urllib.request, os
sql = open(sys.argv[1]).read() if os.path.isfile(sys.argv[1]) else sys.argv[1]
tok = os.environ['TOKEN']
req = urllib.request.Request(
    'https://api.supabase.com/v1/projects/' + os.environ['REF'] + '/database/query',
    data=json.dumps({'query': sql}).encode(),
    headers={'Authorization': 'Bearer ' + tok, 'Content-Type': 'application/json',
             # Cloudflare rechaza el UA por defecto de urllib (error 1010)
             'User-Agent': 'avancecorp-deploy/1.0'})
try:
    print(urllib.request.urlopen(req, timeout=300).read().decode()[:1500])
except urllib.error.HTTPError as e:
    print('HTTP', e.code, e.read().decode()[:1500]); sys.exit(1)
PY
}
export TOKEN REF

echo "— 1/3 · aplicando la migración (una transacción; si falla, no queda nada) —"
api "$MIG"

echo "— 2/3 · registrándola en schema_migrations —"
python3 - "$MIG" <<'PY' > /tmp/registro-cierres.sql
import sys
sql = open(sys.argv[1]).read().replace("'", "''")
print("insert into supabase_migrations.schema_migrations (version, name, statements) "
      "values ('20260812000259', 'crm_cierres_externos', array['" + sql + "']) "
      "on conflict (version) do nothing;")
PY
api /tmp/registro-cierres.sql
rm -f /tmp/registro-cierres.sql

echo "— 3/3 · verificación —"
api "select
  (select count(*) from information_schema.tables where table_schema='crm' and table_name in ('cierres_externos','conversion_reservas','depositos_reclamados')) as tablas_nuevas_deben_ser_3,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('crm','private') and p.prosecdef) as definer_debe_ser_167,
  (select count(*) from supabase_migrations.schema_migrations where version='20260812000259') as registrada_debe_ser_1;"

echo "✅ LISTO. Siguen: redesplegar la edge crm-convertir-lead y /release-crm."

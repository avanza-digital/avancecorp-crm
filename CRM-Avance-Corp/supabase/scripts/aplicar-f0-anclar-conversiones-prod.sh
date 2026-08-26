#!/bin/bash
# Aplica la F0 del plan «Conversion unica en todo el CRM» a PRODUCCIÓN.
#
# QUÉ ES F0: anclar en el repo el texto VIVO de
#   private.metricas_conversiones_implementacion(p_desde date, p_hasta date)
# (la 20260824170630 lo parcheó en caliente; su resultado no existía en ningún
# fichero). CERO cambio funcional: preflight md5 906afdec2bfbd1abcf3931093f09539f
# → CREATE OR REPLACE con el texto capturado byte a byte → postflight mismo md5.
#
# POR QUÉ ESTE CANAL: el merge de branches de Supabase sigue roto (Management
# API 404). Mismo canal directo que aplicar-cumplimiento-conversion-b-prod.sh.
# Miguel ordenó F0 el 2026-08-26 («haz la F0», decisión D5 del plan).
#
# ENSAYADO EN BANCO LOCAL (PG16, base desechable crm_f0_banco):
#   · siembra del texto vivo → md5 local == prod (906afdec…)
#   · migración aplica sin alterar la huella
#   · mutante (función distinta) → preflight aborta, nada aplicado
#
# VUELTA ATRÁS: no aplica — si el preflight o el postflight fallan, la
# transacción entera se revierte; si pasa, el objeto es byte-idéntico al previo.
set -euo pipefail
REF="dctqcbznekcyxhjujuci"
MIG="/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp/supabase/migrations/20260826211500_crm_f0_anclar_metricas_conversiones.sql"
VERSION="20260826211500"
NOMBRE="crm_f0_anclar_metricas_conversiones"
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

echo "— 1/3 · aplicando F0 (una transacción; si falla, no queda nada) —"
api "$MIG"

echo "— 2/3 · registrándola en schema_migrations —"
python3 - "$MIG" "$VERSION" "$NOMBRE" <<'PY' > /tmp/registro-f0.sql
import sys
sql = open(sys.argv[1]).read().replace("'", "''")
print("insert into supabase_migrations.schema_migrations (version, name, statements) "
      "values ('" + sys.argv[2] + "', '" + sys.argv[3] + "', array['" + sql + "']) "
      "on conflict (version) do nothing;")
PY
api /tmp/registro-f0.sql
rm -f /tmp/registro-f0.sql

echo "— 3/3 · verificación en vivo —"
api "select
  (select case when md5(pg_get_functiondef(p.oid))='906afdec2bfbd1abcf3931093f09539f' then 1 else 0 end
     from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname='metricas_conversiones_implementacion'
      and pg_get_function_identity_arguments(p.oid)='p_desde date, p_hasta date') as md5_intacto_debe_ser_1,
  (select prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname='metricas_conversiones_implementacion') as definer_debe_ser_t,
  (select count(*) from supabase_migrations.schema_migrations where version='$VERSION') as registrada_debe_ser_1;"

echo "✅ F0 LISTA. El repo vuelve a ser la verdad del fuente de esta función."

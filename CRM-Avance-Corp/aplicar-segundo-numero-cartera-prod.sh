#!/usr/bin/env bash
# Aplica a PRODUCCIÓN la migración 20260826151907 — la página de la cartera pasa a
# devolver `telefono_alternativo` y el buscador por dígitos también lo mira.
#
# Ensayada en Postgres local con stubs del catálogo: la función se EJECUTA con datos
# (devuelve el 2.º número, lo encuentra por búsqueda, conserva escape/guardias/cursor)
# y 5 mutantes que neutralizan el arreglo mueren en el postflight.
#
# NO hay que publicar el front: `LeadRowSchema` ya declaraba la columna
# (optional+nullable) y `aLead()` ya la copiaba. Lo único que faltaba era que la
# RPC la devolviera. Por eso este despliegue es SOLO servidor.
#
# Hace TRES cosas y para en la primera que falle:
#   1. aplica el fichero VERBATIM (mismo byte que el repo)
#   2. lo registra en el índice (db query ejecuta pero NO registra)
#   3. comprueba por CONTEO y EJECUTANDO — la respuesta de la 1 no es evidencia
set -euo pipefail
cd "$(dirname "$0")"
export SUPABASE_ACCESS_TOKEN="$(security find-generic-password -s 'Supabase CLI' -w)"
S=$(mktemp -d)
MIG=supabase/migrations/20260826151907_crm_cartera_pagina_telefono_alternativo.sql

echo "── 1/3 · aplicando la migración ──────────────────────────────"
npx --yes supabase@latest db query --linked --file "$MIG"

echo "── 2/3 · registrando en el índice ────────────────────────────"
printf "insert into supabase_migrations.schema_migrations(version) values ('20260826151907') on conflict do nothing;\n" > "$S/reg.sql"
npx --yes supabase@latest db query --linked --file "$S/reg.sql"

echo "── 3/3 · comprobando (conteo + contrato de salida) ───────────"
cat > "$S/ver.sql" <<'SQL'
select
  (select count(*) from supabase_migrations.schema_migrations
     where version='20260826151907') as registrada_esperado_1,
  (select position('telefono_alternativo' in pg_get_function_result(p.oid)) > 0
     from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='crm' and p.proname='cartera_pagina_fn') as devuelve_el_2do_numero_esperado_true,
  (select not prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='crm' and p.proname='cartera_pagina_fn') as sigue_invoker_esperado_true,
  has_function_privilege('authenticated',
    'crm.cartera_pagina_fn(integer, timestamptz, uuid, text, uuid, boolean, text)',
    'execute') as authenticated_ejecuta_esperado_true,
  has_function_privilege('anon',
    'crm.cartera_pagina_fn(integer, timestamptz, uuid, text, uuid, boolean, text)',
    'execute') as anon_ejecuta_esperado_false,
  (select count(*) from crm.leads where telefono_alternativo is not null)
    as leads_con_2do_numero_hoy_14,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='crm') as fn_crm_no_debe_bajar;
SQL
npx --yes supabase@latest db query --linked --file "$S/ver.sql"
rm -rf "$S"
echo
echo "Si 'devuelve_el_2do_numero' salió true, la pantalla Cartera ya puede mostrarlo."
echo "Verificación humana: abrir Cartera, abrir uno de los 14 leads con dos números"
echo "y comprobar que la ficha muestra \"Teléfono alternativo\"; luego buscar ese número."

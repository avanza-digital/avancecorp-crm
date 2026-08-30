#!/usr/bin/env bash
# ACEPTACION de la Fase 5.a. Ejecuta LA MIGRACION REAL contra produccion dentro
# de una transaccion que SIEMPRE se deshace (el ultimo bloque termina en
# `raise exception`, en verde o en rojo). No se prueba una copia del SQL: se
# concatenan los bytes del archivo de migracion, quitandole solo su `begin;` y
# su `commit;` para poder envolverlo.
#
# Uso:  bash supabase/scripts/test-f5a-una-sola-pregunta.sh
#
# VERDE MEDIDO EL 2026-08-30 (registro 180, produccion intacta despues):
#   REV  antes 3 contratos / 39 cuotas / 2 fichas · ficha360 1 · productos 0 filas
#   REV  despues 0 / 0 / 0                        · ficha360 0 · productos ERR 42501 · edicion 0
#   CTL  58 / 549 / 44 y ficha360 1, IDENTICOS antes y despues · edicion 1 fila
#   anon 0 -> 0 y sin error
#   mutantes: m2=3 · m4=1 · m5/m6/m7 revientan
set -euo pipefail
cd "$(dirname "$0")/../.."
MIG="supabase/migrations/20260830090000_crm_f5_a_una_sola_pregunta_analista.sql"
TMP="$(mktemp -d)"
cat supabase/scripts/test-f5a-antes.sql                       >  "$TMP/ensayo.sql"
grep -v -x -e 'begin;' -e 'commit;' "$MIG"                    >> "$TMP/ensayo.sql"
cat supabase/scripts/test-f5a-despues.sql                     >> "$TMP/ensayo.sql"
echo "Ensayo compuesto: $TMP/ensayo.sql ($(wc -l < "$TMP/ensayo.sql") lineas)"
npx --no-install supabase db query --linked --file "$TMP/ensayo.sql" 2>&1 | tail -8

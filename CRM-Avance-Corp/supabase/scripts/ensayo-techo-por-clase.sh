#!/usr/bin/env bash
# Ensaya CONTRA PRODUCCION la migración del techo por clase, y el mutante del
# trinquete encima de ella, DENTRO DE UNA TRANSACCION QUE SE DESHACE.
#
# Por qué existe: el ensayo manual del 22/09 fue la única evidencia de que esta
# migración hacía lo que decía, y un acto manual no es un gate. Esto lo deja
# repetible. No escribe NADA: el mutante termina siempre en `raise exception` y
# el `rollback` final cierra la transacción de todos modos.
#
# Uso:  bash supabase/scripts/ensayo-techo-por-clase.sh
# Verde = el mensaje dice MUTANTE_ANALITICA_CAZADO.
set -euo pipefail
cd "$(dirname "$0")/../.."
MIG=supabase/migrations/20260922153708_crm_vigilante_techo_por_clase.sql
MUT=supabase/scripts/trinquete-analitica-lc-mutante.sql
TMP=$(mktemp -t ensayo-techo-clase)
trap 'rm -f "$TMP"' EXIT

# La migración ya trae su propio `begin;`/`commit;`. Para ensayarla hay que
# neutralizar ESE commit, o la transacción se cerraría antes del mutante.
sed 's/^commit;$/-- commit; (neutralizado por el ensayo)/' "$MIG" > "$TMP"
cat "$MUT" >> "$TMP"
echo "rollback;" >> "$TMP"

supabase db query --linked --file "$TMP" 2>&1 | tail -5

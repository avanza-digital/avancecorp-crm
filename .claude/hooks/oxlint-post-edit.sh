#!/bin/bash
# PostToolUse (Edit|Write): oxlint inmediato sobre el archivo recién editado del CRM.
# Adelanta a tiempo-de-edición el feedback que Lefthook daría recién en el commit.
# Solo actúa sobre src/ y e2e/ de la app del CRM; en el resto no hace nada.
# Falla-abierto: si oxlint no está o algo propio falla, exit 0.

input=$(cat) || exit 0
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[ -z "$file" ] && exit 0

case "$file" in
  */CRM-Avance-Corp/app/src/*.ts|*/CRM-Avance-Corp/app/src/*.tsx|*/CRM-Avance-Corp/app/e2e/*.ts)
    app_dir="${file%%/CRM-Avance-Corp/app/*}/CRM-Avance-Corp/app"
    [ -d "$app_dir/node_modules/.bin" ] || exit 0
    # --deny-warnings: el repo está limpio de warnings (verificado 2026-07-23); cualquier
    # warning nuevo es una regresión y debe volver a Claude como feedback inmediato.
    out=$(cd "$app_dir" && ./node_modules/.bin/oxlint --deny-warnings "$file" 2>&1)
    status=$?
    if [ $status -ne 0 ]; then
      # exit 2 en PostToolUse: muestra el output a Claude para que corrija en caliente
      printf 'oxlint encontró problemas en %s:\n%s\n' "$file" "$out" >&2
      exit 2
    fi
    ;;
esac

exit 0

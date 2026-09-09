#!/bin/bash
# PreToolUse (Bash): bloquea operaciones inequívocamente destructivas y evita
# lecturas directas de secretos. Es una prevención de accidentes, no un sandbox
# para scripts arbitrarios: solo puede inspeccionar el texto del comando.
# Las operaciones reversibles/deploy se dejan al motor de permisos (ask).

deny() {
  printf 'BLOQUEADO: %s\n' "$1" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || deny "falta jq para validar el comando."
input=$(cat) || deny "no se pudo leer el input."
command=$(printf '%s' "$input" | jq -er '.tool_input.command | select(type == "string" and length > 0)' 2>/dev/null) || deny "input de comando inválido."

# Detecta rutas de entorno, sin confundir process.env o import.meta.env con
# archivos. Incluye la plantilla, coherentemente con Read deny en settings.
env_pattern="(^|[[:space:]/:\"'=<>])\\.env([.[:space:]\"';|&<>]|rc|$)"
if [[ "$command" =~ $env_pattern ]]; then
  deny "el comando hace referencia a un archivo de entorno protegido."
fi

case "$command" in
  *"secrets/"*|*".ssh/"*|*"credentials"*|*"id_rsa"*|*"id_ed25519"*|*".pem"*|*".p12"*)
    deny "el comando hace referencia a credenciales, secretos o una clave privada."
    ;;
esac

case "$command" in
  *"HOSTINGER_API_TOKEN="*|*"SUPABASE_ACCESS_TOKEN="*|*"SUPABASE_SERVICE_ROLE_KEY="*|*"ANTHROPIC_API_KEY="*|*"OPENAI_API_KEY="*|*"RESEND_API_KEY="*|*"VAPID_PRIVATE_KEY="*)
    deny "los secretos no se pasan inline en comandos; usa el gestor de credenciales autorizado."
    ;;
esac

key_pattern='\.key([[:space:];|&]|$)'
if [[ "$command" =~ $key_pattern ]]; then
  deny "el comando hace referencia a una clave privada .key."
fi

# Reconoce opciones globales usuales y binarios absolutos, también con rutas
# entre comillas. No intenta interpretar aliases ni scripts arbitrarios.
git_prefix="(^|[[:space:];|&])([^[:space:];|&]*/)?git([[:space:]]+(-C|-c|--git-dir|--work-tree)(=|[[:space:]]+)(\"[^\"]*\"|'[^']*'|[^[:space:];|&]+))*[[:space:]]+"
reset_pattern="${git_prefix}reset[[:space:]]+[^;|&]*--hard([[:space:];|&]|$)"
if [[ "$command" =~ $reset_pattern ]]; then
  deny "git reset --hard puede destruir cambios locales; usa una alternativa recuperable."
fi

clean_pattern="${git_prefix}clean[[:space:]]+[^;|&]*(-[A-Za-z]*f|--force)"
if [[ "$command" =~ $clean_pattern ]]; then
  deny "git clean forzado puede borrar archivos no versionados."
fi

force_push_pattern="${git_prefix}push[[:space:]][^;|&]*(--force([^[:alnum:]_]|$)|-[A-Za-z]*f([[:space:];|&]|$))"
if [[ "$command" =~ $force_push_pattern ]]; then
  deny "force-push está prohibido por las reglas del proyecto."
fi

force_refspec_pattern="${git_prefix}push[[:space:]][^;|&]*[[:space:]]\\+[^[:space:];|&]*:"
if [[ "$command" =~ $force_refspec_pattern ]]; then
  deny "un refspec con + fuerza el push y está prohibido."
fi

# rm -rf puede ser útil sobre un target acotado y por eso requiere permiso en
# settings.json. Detectamos targets amplios comunes, incluidos comillas y globs.
# Quitar comillas aquí solo normaliza para detectar peligro; no ejecuta el texto.
normalized=$(printf '%s' "$command" | tr -d "\"'")
rm_broad_pattern='(^|[[:space:];|&])rm[[:space:]]+(-[^[:space:];|&]+[[:space:]]+)+((/|~|\$HOME|\$\{HOME\}|\.|\.\.)(/)?(\*)?|\.[^/[:space:];|&]*\*)([[:space:];|&]|$)'
if [[ "$normalized" =~ $rm_broad_pattern ]]; then
  deny "rm recursivo sobre un target amplio no es seguro."
fi

# Evita que una autorización local amplia omita la confirmación para estas
# formas comunes. El motor de permisos conserva sus propias reglas ask/deny.
recursive_rm='(^|[[:space:];|&])([^[:space:];|&]*/)?rm[[:space:]]+[^;|&]*(--recursive|-[A-Za-z]*[rR])'
database_command='(^|[[:space:];|&])([^[:space:];|&]*/)?(dropdb|psql)([[:space:]]|$)'
deploy_command='(^|[[:space:];|&])([^[:space:];|&]*/)?(supabase(@[^[:space:]]+)?[[:space:]]+(db[[:space:]]+(reset|push)|functions[[:space:]]+deploy)|vercel[[:space:]]+(deploy|promote|rollback|--prod)|npm[[:space:]]+run[[:space:]]+deploy)([[:space:];|&]|$)'
if [[ "$command" =~ ${git_prefix}push([[:space:]]|$) ]] ||
   [[ "$command" =~ $recursive_rm ]] || [[ "$command" =~ $database_command ]] ||
   [[ "$command" =~ $deploy_command ]]; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Operación Git, borrado recursivo o base de datos: confirmar alcance y destino antes de ejecutar."}}'
fi

exit 0

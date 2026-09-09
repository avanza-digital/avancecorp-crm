#!/bin/bash
# PreToolUse (Read|Edit|Write): protege archivos que las reglas del proyecto declaran sensibles.
#  - Migraciones ya versionadas de supabase/migrations/ (regla: nunca se editan; se crea
#    una migración nueva — ver CRM-Avance-Corp/supabase/migrations/LEEME.md).
#  - Archivos .env, secretos, credenciales y claves privadas.
# Falla-cerrado si no puede validar el input; jq es un requisito del proyecto.

deny_input() { echo "BLOQUEADO: no se pudo validar el acceso a archivos ($1)." >&2; exit 2; }
command -v jq >/dev/null 2>&1 || deny_input 'falta jq'
input=$(cat) || deny_input 'lectura del input'
file=$(printf '%s' "$input" | jq -er '.tool_input.file_path // .tool_input.notebook_path // "" | select(type == "string" and length > 0)' 2>/dev/null) || deny_input 'file_path inválido'
tool=$(printf '%s' "$input" | jq -er '.tool_name | select(type == "string" and length > 0)' 2>/dev/null) || deny_input 'tool_name inválido'
case "$file" in /*) ;; *) file="$PWD/$file" ;; esac

base=$(basename "$file")

# 1) Credenciales: nunca leer ni modificar secretos desde Claude. Las reglas
# Read deny también ocultan estos archivos de búsquedas y siguen symlinks.
# .env.example queda cubierto por .env.*; las plantillas se gestionan a mano.
case "$base" in
  .env|.env.*|.envrc)
    echo "BLOQUEADO: '$file' es un archivo de entorno protegido. Usa gestión manual de secretos y plantillas." >&2
    exit 2
    ;;
  credentials|credentials.*|credentials-*|*.pem|*.key|*.p12|id_rsa|id_ed25519)
    echo "BLOQUEADO: '$file' contiene o puede contener credenciales o una clave privada." >&2
    exit 2
    ;;
esac

case "/$file/" in
  */secrets/*|*/credentials/*|*/.ssh/*)
    echo "BLOQUEADO: '$file' está dentro de un directorio de secretos." >&2
    exit 2
    ;;
esac

# 2) Migraciones ya versionadas en git (leer está permitido; Edit/Write no).
case "$tool" in
*Edit*|*Write*)
  case "$file" in
    */supabase/migrations/*.sql)
      existing_dir=$(dirname "$file")
      while [ ! -d "$existing_dir" ]; do existing_dir=$(dirname "$existing_dir"); done
      repo_root=$(git -C "$existing_dir" rev-parse --show-toplevel 2>/dev/null) || deny_input 'no se pudo comprobar el historial de la migración'
      relative=${file#"$repo_root"/}
      if git -C "$repo_root" ls-files --error-unmatch -- "$relative" >/dev/null 2>&1; then
        echo "BLOQUEADO: '$file' es una migración ya versionada. Regla no negociable del CRM: crea una migración nueva y registra la enmienda en MIGRACIONES.md." >&2
        exit 2
      fi
      ;;
  esac
  ;;
esac

exit 0

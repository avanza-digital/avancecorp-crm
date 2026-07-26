#!/bin/bash
# PreToolUse (Edit|Write): protege archivos que las reglas del proyecto declaran intocables.
#  - Migraciones ya versionadas de supabase/migrations/ (regla: nunca se editan; se crea
#    una migración nueva — ver CRM-Avance-Corp/supabase/migrations/LEEME.md).
#  - Archivos .env con credenciales (salvo .env.example).
# Falla-abierto: ante cualquier error propio, deja pasar (exit 0) para no bloquear trabajo.

input=$(cat) || exit 0
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[ -z "$file" ] && exit 0

base=$(basename "$file")

# 1) Credenciales: .env y variantes locales (nunca .env.example, que es plantilla pública)
case "$base" in
  .env|.env.*)
    if [ "$base" != ".env.example" ]; then
      echo "BLOQUEADO: '$file' es un archivo de credenciales (.env). Regla del proyecto: no se edita desde Claude; hazlo a mano si de verdad hace falta." >&2
      exit 2
    fi
    ;;
esac

# 2) Migraciones ya versionadas en git (las no rastreadas —recién creadas— sí se pueden editar)
case "$file" in
  */supabase/migrations/*.sql)
    dir=$(dirname "$file")
    if git -C "$dir" ls-files --error-unmatch "$file" >/dev/null 2>&1; then
      echo "BLOQUEADO: '$file' es una migración ya versionada. Regla no negociable del CRM: las migraciones commiteadas no se editan; crea una migración nueva (skill /nueva-migracion) y registra la enmienda en MIGRACIONES.md." >&2
      exit 2
    fi
    ;;
esac

exit 0

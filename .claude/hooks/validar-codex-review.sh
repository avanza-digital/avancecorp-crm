#!/bin/bash
# PreToolUse (mcp__codex__codex): exige que toda consulta de Claude PRIMARY a
# Codex sea un review explícito, read-only y sin posibilidad de pedir permisos.
#
# 🟡 DORMIDO desde el 24/09/2026. `codex mcp-server` fue retirado de la CLI, así
# que no existe la herramienta `mcp__codex__codex` y este hook no se dispara
# nunca. La validación VIVA del contrato del prompt está en
# `scripts/codex-review-mcp` (mejor sitio: el hook solo cubría la ruta MCP y una
# llamada directa a `codex exec` lo esquivaba entera).
# Se conserva —no se borra— para que el candado siga puesto si Codex vuelve a
# ofrecer un punto de entrada MCP. Sus tests siguen corriendo.

deny() {
  printf 'BLOQUEADO: consulta Codex insegura: %s\n' "$1" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || deny "jq no está disponible para validar la frontera de seguridad."
input=$(cat) || deny "no se pudo leer el input del hook."
printf '%s' "$input" | jq -e '
  .tool_name == "mcp__codex__codex" and
  (.tool_input | type == "object" and
    (keys - ["prompt", "sandbox", "approval-policy", "model"] | length == 0) and
    (.prompt | type == "string") and
    (if has("model") then (.model | type == "string" and length > 0) else true end))
' >/dev/null 2>&1 || deny "solo se admiten prompt, sandbox, approval-policy y model; no overrides de configuración/instrucciones."
sandbox=$(printf '%s' "$input" | jq -er '.tool_input.sandbox // ""' 2>/dev/null) || deny "input JSON inválido."
approval=$(printf '%s' "$input" | jq -er '.tool_input["approval-policy"] // ""' 2>/dev/null) || deny "input JSON inválido."
prompt=$(printf '%s' "$input" | jq -er '.tool_input.prompt // ""' 2>/dev/null) || deny "input JSON inválido."

[ "$sandbox" = "read-only" ] || deny "debe pasar sandbox=read-only explícitamente."
[ "$approval" = "never" ] || deny "debe pasar approval-policy=never explícitamente."

# El regex original aceptaba `ROLE: SECONDARY_REVIEWER.PRIMARY` (el punto satisfacía
# `[.[:space:]]` sin exigir que el token terminara ahí). Hallazgo de Codex, 24/09.
[[ "$prompt" =~ ^ROLE:[[:space:]]SECONDARY_REVIEWER\.?([[:space:]]|$) ]] || deny "el prompt debe empezar por ROLE: SECONDARY_REVIEWER."

case "$prompt" in
  *"Do not modify files"*|*"No modifiques archivos"*) ;;
  *) deny "el prompt debe prohibir modificar archivos." ;;
esac

case "$prompt" in
  *"Do not implement"*|*"No implementes"*) ;;
  *) deny "el prompt debe prohibir implementar la tarea." ;;
esac

case "$prompt" in
  *"Do not invoke Claude"*|*"No invoques Claude"*) ;;
  *) deny "el prompt debe prohibir que Codex invoque Claude." ;;
esac

case "$prompt" in
  *"Do not delegate"*|*"No delegues"*) ;;
  *) deny "el prompt debe prohibir delegar a otro agente." ;;
esac

case "$prompt" in
  *"Do not create another review chain"*|*"No crees otra cadena de review"*|*"No inicies otro review"*) ;;
  *) deny "el prompt debe prohibir iniciar otra cadena de review." ;;
esac

exit 0

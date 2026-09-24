ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato: VERDICT (PASS/BLOCK), SUMMARY, FINDINGS P0–P3 con evidencia
(archivo:línea), RIESGOS, NEXT ACTIONS, CONFIDENCE.

# Encargo: cambio de transporte del reviewer (LEVEL 3 — arquitectura + permisos)

## Qué pasó

`scripts/codex-review-mcp` exponía un servidor MCP con `exec codex mcp-server
--strict-config "${restrictions[@]}"`. El subcomando `mcp-server` fue RETIRADO de la CLI
de Codex (ausente en 0.155.1; en 0.153.4 avisaba de su deprecación). Medido hoy:

    $ codex --version
    codex-cli 0.155.1
    $ codex mcp --help
    Commands: list, get, add, remove, login, logout, help      # no hay mcp-server

Consecuencia: el MCP `codex` moría al arrancar con `CONNECTION_CLOSED`, y como un MCP
caído no falla la tarea, TODO review LEVEL 3 que el CLAUDE.md declara obligatorio se
saltaba en silencio.

## Qué se cambió

1. **Transporte.** Última línea del script, antes y después:

       - exec codex mcp-server --strict-config "${restrictions[@]}"
       + exec codex exec --strict-config "${restrictions[@]}" --sandbox read-only <<< "$prompt"

   El array `restrictions` NO cambió. Sigue siendo:

       -c 'sandbox_mode="read-only"' -c 'approval_policy="never"'
       -c 'agents.enabled=false' -c 'features.shell_tool=false'
       -c 'features.apps=false' -c 'features.hooks=false'
       -c 'features.plugins=false' -c 'features.remote_plugin=false'
       -c 'features.browser_use=false' -c 'features.computer_use=false'
       -c 'features.in_app_browser=false' -c 'features.in_app_local_automation=false'
       -c 'features.code_mode=false' -c 'features.skill_mcp_dependency_install=false'
       -c 'web_search="disabled"'
       + un -c "mcp_servers.<nombre>.enabled=false" por cada MCP efectivo inventariado.

   Verificado que `codex exec` acepta `--strict-config`, `-c` y `--sandbox`.

2. **La validación del contrato del prompt se movió del hook al envoltorio.** Antes vivía
   en `.claude/hooks/validar-codex-review.sh`, un PreToolUse con matcher
   `^mcp__codex__codex$`. Ahora el script lee el encargo por stdin y aplica las mismas
   comprobaciones antes de gastar un token:

       rechazar() { printf 'BLOQUEADO: consulta Codex insegura: %s\n' "$1" >&2; exit 2; }
       prompt=$(cat) || rechazar "no se pudo leer el encargo por stdin."
       [ -n "$prompt" ] || rechazar "el encargo llega vacio por stdin."
       [[ "$prompt" =~ ^ROLE:\ SECONDARY_REVIEWER([.[:space:]]|$) ]] || rechazar "..."
       case "$prompt" in *"Do not modify files"*|*"No modifiques archivos"*) ;; *) rechazar "..." ;; esac
       ... (idem para: Do not implement / Do not invoke Claude / Do not delegate /
            Do not create another review chain)

   Razón declarada: el hook solo cubría la ruta MCP; una llamada directa a `codex exec`
   lo esquivaba entera.

3. **`.mcp.json` ya no declara el servidor `codex`** (queda solo `playwright`). El hook se
   conserva DORMIDO, con cabecera que lo dice, por si Codex reintroduce un punto MCP.

4. Docs actualizados: `CLAUDE.md`, `.ai/REVIEW_PROTOCOL.md`, `.ai/VERIFICATION.md`,
   addendum fechado en `.ai/IMPLEMENTATION_REPORT.md`, y `~/.claude/CLAUDE.md`.

## Verificación ya ejecutada

    jq empty .claude/settings.json .mcp.json                      PASS
    bash -n (wrapper Claude, lanzador Codex, 4 hooks)             PASS
    scripts/codex-review-mcp --help                               PASS
    scripts/codex-review-mcp --check                              PASS
    stdin vacío / sin ROLE / sin cada una de las 5 prohibiciones   PASS (exit 2)
    -c sandbox_mode="workspace-write"                             PASS (exit 64)
    node --test scripts/ai-collaboration.test.mjs                 PASS 8/8

## Lo que te pido: REFUTA

No busco confirmación. Intenta romper estas tres afirmaciones, en este orden:

1. **«El aislamiento es equivalente al de antes.»** `mcp-server --strict-config` y
   `codex exec --strict-config` con las MISMAS `-c` ¿otorgan la misma superficie? ¿Hay
   algo que un servidor MCP restringía y que una ejecución `exec` no, o al revés? Me
   preocupa especialmente si `exec` puede leer ficheros del repo que el MCP no leía
   (sandbox read-only sigue siendo LECTURA de todo el árbol) y si eso cambia el modelo
   de amenaza cuando el encargo viene de un PRIMARY comprometido.

2. **«Mover la validación del hook al envoltorio cierra un agujero y no abre otro.»**
   ¿Qué se pierde al quitar el hook de la ruta? Concretamente: el hook se ejecutaba
   aunque el modelo construyera la llamada, mientras que el envoltorio solo protege a
   quien lo invoque. ¿Puede un PRIMARY llamar `codex exec` directamente y saltarse todo?
   Si sí, ¿la protección es real o es teatro?

3. **«Quitar `codex` de `.mcp.json` no rompe nada más.»** ¿Hay efectos que no haya visto?

Además, señala cualquier defecto en el bash: `<<< "$prompt"` con `set -euo pipefail`,
el `exec` tras leer stdin, el regex del ROLE, o el `case` con patrones no anclados
(¿puede un encargo malicioso satisfacer las cinco frases y aun así ser peligroso?).

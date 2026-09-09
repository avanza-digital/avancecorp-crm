# Cierre de la configuración de colaboración — 2026-09-07

Actualización 2026-09-08: este reporte describe el cierre original del repositorio.
Después, por solicitud del usuario, se añadió una instalación global personal
para todos sus proyectos en esta Mac, incluido un MCP `codex` de alcance usuario.
La configuración propia de AvanceCorp se conserva. El estado actual global y sus
verificaciones están en `~/.config/ai-collaboration/README.md` y en la nota del vault
`Colaboracion global Codex y Claude - 2026-09-08.md`.

## IMPLEMENTED

- Flujo bidireccional PRIMARY → SECONDARY_REVIEWER → PRIMARY, con un solo escritor.
- Reviews con evidencia y formato común; presupuesto LEVEL 1: 0, LEVEL 2: normalmente 1, LEVEL 3: 1 cuando sea razonablemente posible; máximo habitual 2.
- Gates proporcionales al cambio. Un dictamen de IA no sustituye comprobaciones automatizadas.
- Claude reviewer sin herramientas/MCP; Codex reviewer read-only, sin shell, delegación, plugins ni MCP heredados al arrancar.
- Protecciones de secretos, comandos destructivos y operaciones de publicación/DB; comandos normales de desarrollo conservados.

## MODIFIED

- `AGENTS.md`: reglas de colaboración integradas, protocolo único y referencia correcta a Inicio/CodeGraph; ejemplo de respuesta alineado al formato obligatorio.
- `CLAUDE.md`: roles equivalentes, uso de Codex reviewer, evidencia adjunta, reconexión tras cambios de configuración y presupuesto común.
- `.claude/settings.json`: añade deny de secretos, ask de operaciones importantes y hooks; conserva plugins, lista original de desarrollo permitido y PostToolUse.
- `.claude/hooks/proteger-archivos.sh`: falla cerrado ante inputs inválidos; bloquea secretos y modificaciones de migraciones versionadas; admite nuevas migraciones incluso en directorios todavía inexistentes.
- `.claude/agents/revisor-a11y.md` y `auditor-rls.md`: conservan sus criterios especializados, adoptan el protocolo y pierden acceso al shell.
- `.mcp.json`: conserva Playwright y añade Codex a través del lanzador del repositorio.
- Nota del vault `Sistema de colaboracion Codex y Claude Code 2026-09-07.md`: estado y límites de la reanudación.

## CREATED

Archivos nuevos respecto a HEAD, incluyendo los recuperados de la sesión interrumpida:

- `.ai/REVIEW_PROTOCOL.md`: roles, formato, evidencia, presupuesto, autoridad y límites.
- `.ai/VERIFICATION.md`: comandos reales por stack, CI y regla de worktrees.
- `scripts/claude-review`: ejecuta una consulta acotada, incorpora el protocolo y valida la entrega del dictamen; no instala dependencias.
- `scripts/codex-review-mcp`: deshabilita individualmente los MCP efectivos y los plugins sin editar la configuración personal; `--check` verifica MCP y flags efectivos.
- `scripts/ai-collaboration.test.mjs`: ocho grupos de pruebas con casos permitidos, bloqueados, errores y CLI simuladas; fixtures Git desechables, sin commits.
- `.claude/hooks/proteger-comandos.sh`: bloquea borrados amplios, force-push, reset duro y lecturas directas/históricas de secretos; solicita permiso para operaciones importantes.
- `.claude/hooks/validar-codex-review.sh`: exige rol explícito, read-only, never y restricciones anti-loop; rechaza parámetros capaces de cambiar configuración o instrucciones.
- `.github/workflows/ai-collaboration-config.yml`: valida JSON, todos los scripts shell, contratos de los wrappers/hooks y rutas del protocolo.
- Este reporte.

## PRESERVED

- Workflows `crm-app-quality.yml` y `crm-rls-preflight.yml`, Lefthook y `oxlint-post-edit.sh`: idénticos a HEAD.
- Plugins originales, permisos normales de desarrollo y MCP Playwright: preservados mediante comparación estructural.
- Configuración personal/global y credenciales: no modificadas durante esta reanudación. No existe otro MCP Codex global/local que oculte la entrada del proyecto ni un ajuste global que desactive los hooks.
- Criterios técnicos de los reviewers especializados y el agente genérico existente.
- Código del CRM/portal, dependencias, migraciones y cambios previos de otras tareas.
- Main y su upstream. No se hicieron commits, push, despliegues ni worktrees.

## CONFLICTS FOUND

1. **Las tablas TOML vacías no aíslan Codex.** La comprobación efectiva conservaba 15 MCP heredados. Se sustituyó esa configuración por deshabilitación individual; se verificaron cero habilitados y once flags de ejecución apagados.
2. **`bash -n archivo1 archivo2` solo comprueba el primero.** CI y documentación ahora iteran sobre los seis scripts.
3. **La excepción `.env.example` no puede vencer un deny nativo `.env.*`.** Se priorizó proteger búsquedas y symlinks; la plantilla también queda restringida y se gestiona manualmente. No cambia cómo la aplicación carga su entorno.
4. **`git show HEAD:.env` y `HEAD:secrets/token` escapaban al hook.** Corregido con casos de regresión; `process.env` sigue permitido.
5. **Los reviewers especializados podían usar Bash y tenían otro formato.** Conservan lectura/búsqueda y sus criterios, con formato y presupuesto común.
6. **Una recomendación de Claude era incompatible con la CLI instalada.** Codex 0.153.4 rechaza `--strict-config` para `codex mcp list`; se mantiene en `mcp-server`, cuyo handshake sí pasó. `--check` verifica por separado valores efectivos.

## VERIFICATION

Entorno: Claude Code 2.1.263, Codex CLI 0.153.4, Node 26.7.0 local; CI configurado con Node 24, igual que los workflows del CRM.

| Comprobación | Resultado |
| --- | --- |
| `node --test scripts/ai-collaboration.test.mjs` | PASS: 8 grupos, sin fallos |
| `jq empty .claude/settings.json .mcp.json` y JSON local existente | PASS |
| `bash -n` individual del wrapper Claude, lanzador Codex y cuatro hooks; permisos ejecutables | PASS |
| `scripts/claude-review --help` y `scripts/codex-review-mcp --help` | PASS |
| `scripts/codex-review-mcp --check` | PASS: ningún MCP heredado habilitado; flags de ejecución apagados |
| `initialize` + `tools/list` con el comando exacto de `.mcp.json` | PASS: servidor real, parámetros compatibles |
| Configuración efectiva por `config/read`, `features list` y `mcp list` | PASS tras corregir la fusión de tablas |
| Dos reviews reales mediante `scripts/claude-review` | Entregados: ambos CHANGES_REQUESTED; hallazgos evaluados por PRIMARY, no se presentan como PASS de Claude |
| Parseo YAML de los tres workflows y Lefthook | PASS con Ruby/Psych |
| Todos los pasos `run` del workflow nuevo, ejecutados localmente | PASS |
| `git diff --check`, rutas y scripts npm documentados | PASS |
| Comparación de configuraciones preservadas y búsqueda de patrones de credenciales en archivos de la entrega | PASS; no se imprimieron valores de secretos |
| GitHub Actions remoto | NOT RUN: no se autorizó commit/push |
| Lint, typecheck, tests y build completos del CRM/portal | NOT RUN: no se modificó código de producto en esta tarea |
| Turno real de modelo Codex a través de Claude | NOT RUN: se verificaron conexión y configuración efectiva sin consumir un tercer review |
| Cambiar configuración mientras el servidor sigue conectado | NOT RUN: no se alteró la configuración personal para simularlo; se exige reconexión antes de otra consulta |

Se usaron dos opiniones independientes como máximo. Se corrigieron los hallazgos reproducibles sobre secretos, aislamiento y tests. Las hipótesis sobre futuras versiones de CLI o cambios externos concurrentes no se presentaron como vulnerabilidades confirmadas. El arranque inicial dentro del sandbox falló por acceso a la base interna de estado de Codex; la repetición autorizada fuera de ese sandbox pasó. El primer intento de parseo YAML con Python no tenía PyYAML; se verificó con Ruby sin instalar dependencias.

## MANUAL ACTION REQUIRED

- Abrir una sesión nueva de Claude desde la raíz de este repo, o reconectar `codex` mediante `/mcp`, para que use el nuevo lanzador.
- Si se cambian MCP/plugins/settings, reconectar **antes del siguiente review** y repetir `scripts/codex-review-mcp --check`. No modificar esas configuraciones durante un review: el inventario se fija al iniciar el servidor.
- No hacen falta instalaciones ni nuevas credenciales ahora. `mcp-server` sigue funcionando en 0.153.4, pero la CLI avisa que está deprecado: repetir estas verificaciones antes de actualizar.
- Los cambios permanecen locales hasta que el usuario autorice versionarlos; el workflow remoto todavía no ha corrido.

## FINAL COLLABORATION FLOW

El usuario asigna una tarea. El PRIMARY inspecciona y clasifica su riesgo, implementa y ejecuta checks. Si corresponde, adjunta evidencia saneada al otro agente mediante la interfaz protegida. El reviewer analiza y devuelve hallazgos; no escribe ni delega. El PRIMARY acepta/rechaza con evidencia, corrige, ejecuta el gate final y entrega el resultado. Para dos tareas simultáneas con dos PRIMARY se requieren working trees separados; un reviewer read-only no necesita otro.

Los hooks del PRIMARY previenen accidentes reconocibles; no interpretan el contenido de scripts arbitrarios ni sustituyen un sandbox. El aislamiento del reviewer se verifica al iniciar la interfaz configurada y requiere mantener estable la configuración durante su uso. Esta limitación se documenta en el protocolo y no se presenta como protección frente a cambios concurrentes de terceros.

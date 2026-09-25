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

---

## Addendum 2026-09-24 — el transporte MCP murió; el review pasa a `codex exec`

Este informe es un acta de su día y no se reescribe. Lo que cambió después:

**Lo que se rompió.** La última línea de «Pendientes» decía: *«`mcp-server` sigue
funcionando en 0.153.4, pero la CLI avisa que está deprecado: repetir estas
verificaciones antes de actualizar»*. La CLI se actualizó a **0.155.1**, que ya **no
tiene** el subcomando `mcp-server`, y nadie repitió las verificaciones. Resultado: el
servidor moría al arrancar con `CONNECTION_CLOSED`, y **todo review LEVEL 3 quedó sin
hacer en silencio** — sin error visible, porque un MCP que no conecta no falla la tarea.
Detectado el 24/09/2026 durante una auditoría de prompts.

**Lo que se hizo.**

- `scripts/codex-review-mcp` conserva **todas** sus restricciones de aislamiento y su
  `--check`; solo cambia el transporte: de `codex mcp-server --strict-config` a
  `codex exec --strict-config … --sandbox read-only`, con el encargo por **stdin**.
- La validación del contrato del prompt (`ROLE: SECONDARY_REVIEWER` + las cinco
  prohibiciones) **se movió del hook al envoltorio**, porque la ruta
  `mcp__codex__codex` que el hook vigilaba ya no existe. ⚠️ **No cierra el bypass**:
  quien pueda ejecutar binarios sigue pudiendo llamar `codex exec` a pelo. Ese
  agujero es preexistente —el hook tampoco interceptaba ejecuciones directas— y
  contenerlo exige control fuera del alcance del PRIMARY. Ver el review de Codex
  más abajo, que corrigió esta misma frase.
- `.mcp.json` ya **no declara** el servidor `codex`: declararlo reintroduce el
  `CONNECTION_CLOSED` en cada sesión. El test lo fija.
- `.claude/hooks/validar-codex-review.sh` queda **dormido, no borrado**, por si Codex
  vuelve a ofrecer un punto de entrada MCP. Sus pruebas siguen corriendo.

**Verificación de este cambio (24/09/2026).**

| Comprobación | Resultado |
|---|---|
| `bash -n scripts/codex-review-mcp` | PASS |
| `scripts/codex-review-mcp --help` | PASS |
| `scripts/codex-review-mcp --check` | PASS: ningún MCP heredado habilitado; flags de ejecución apagados |
| Rechazo con stdin vacío / sin `ROLE:` / sin cada una de las 5 prohibiciones | PASS (exit 2, sin gastar tokens) |
| Rechazo de overrides (`-c sandbox_mode="workspace-write"`) | PASS (exit 64) |
| `node --test scripts/ai-collaboration.test.mjs` | PASS 8/8 |
| Review real de extremo a extremo por stdin | ver más abajo |

**Lección para el ledger:** un aviso de deprecación con fecha abierta *es* una deuda con
vencimiento. Este informe la anotó correctamente y aun así se cobró, porque nada
re-ejecutaba la comprobación. Un gate que dependa de una herramienta externa necesita
una prueba que falle **ruidosamente** cuando esa herramienta desaparece — no un MCP que
se cae en silencio.

### El review de Codex de este mismo cambio (24/09) — y qué se aceptó

El cambio se revisó **con la vía nueva**, que es su propia prueba de extremo a extremo:
`scripts/codex-review-mcp < CRM-Avance-Corp/docs/encargos/2026-09-24-codex-transporte-reviewer.md`.
Se le pidió REFUTAR, no confirmar. Devolvió dictamen con 5 hallazgos. Tres se aceptaron:

| Hallazgo | Veredicto del PRIMARY | Qué se hizo |
|---|---|---|
| **P2 — el regex del ROLE acepta un token pegado.** `ROLE: SECONDARY_REVIEWER.PRIMARY` pasaba: el punto satisfacía `[.[:space:]]` sin exigir que el token terminara ahí. | **ACEPTADO — reproducido.** Defecto heredado del hook, presente desde el día uno. | Punto opcional + espacio-o-fin: `^ROLE:[[:space:]]SECONDARY_REVIEWER\.?([[:space:]]\|$)`. Corregido en el envoltorio **y** en el hook dormido para que no diverjan. Dos casos nuevos en cada suite (`SECONDARY_REVIEWER.PRIMARY`, `SECONDARY_REVIEWERX`). |
| **P2 — `cat` espera EOF: un cliente MCP residual colgaría el envoltorio.** Abriría stdin, mandaría `initialize` y no lo cerraría. | **ACEPTADO.** Fallo silencioso, justo el que acabamos de pagar. | Lectura con plazo de 30 s; si stdin no cierra, sale con 2 y lo dice. |
| **P1 — el envoltorio no contiene a un PRIMARY comprometido.** Protege a quien lo usa; quien ejecute binarios puede llamar `codex exec` a pelo. | **ACEPTADO como corrección de la REDACCIÓN.** Codex mismo precisa que el bypass es preexistente (el hook tampoco interceptaba ejecuciones directas), no una regresión. | Se retiró la afirmación «cierra ese agujero» del script, del protocolo y de este informe. Ahora se declara el límite explícitamente. |

Los otros dos se resolvieron **midiendo**, que es lo que el propio Codex pedía:

- **P2 — «tu prueba de la retirada no prueba nada».** Tenía razón en el método: se había
  ejecutado `codex mcp --help`, que solo lista los subcomandos de `codex mcp`. La evidencia
  correcta es de nivel superior, y es peor de lo que parecía: `codex mcp-server --help`
  **sale 0 e imprime la ayuda genérica de la CLI** — es decir, la CLI trata `mcp-server`
  como un *prompt*, no como un subcomando. Por eso el handshake MCP moría al instante.
- **P1 — «no está demostrado que `exec` no amplíe la superficie de lectura/escritura».**
  Se midió con canarios, no con autoinforme:

  | Prueba | Resultado |
  |---|---|
  | Leer un canario DENTRO del repo | `NO_PUEDO` |
  | Leer un canario FUERA del repo | `NO_PUEDO` |
  | Escribir `./canario-escritura.tmp` | **BLOQUEADO por el runtime**, no por el modelo: `ERROR codex_core::tools::router: error=patch rejected: writing is blocked by read-only sandbox; rejected by user approval settings`. El archivo no existe. |

  La escritura es evidencia dura (la rechaza el sandbox y queda en el log del runtime). La
  lectura es autoinforme del modelo y vale menos: queda como **NOT RUN** una comprobación
  independiente de lectura efectiva.

**Lo que sigue en NOT RUN:** equivalencia formal de política entre `mcp-server` y `exec`
(se midió el efecto observable, no la configuración efectiva de ambos); barrido de
consumidores de la ruta MCP antigua fuera de `.mcp.json` (sesiones abiertas, config de
usuario, automatizaciones); y prueba del flujo obligatorio con fallos inducidos —que el
PRIMARY registre `NOT RUN` en vez de seguir como si el review hubiera ocurrido.

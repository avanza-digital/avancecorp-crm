# Auditoría de conversiones (21/09/2026) — cómo retomarla desde otra cuenta

Miguel cerró la auditoría del 21/09 «con lo que hay» y pidió este documento para poder
completarla desde otra cuenta de Claude Code. Aquí está TODO lo necesario: qué se hizo,
qué falta, qué herramientas y permisos hacen falta, y los comandos exactos.

El informe de resultados está en el vault:
`BASE DE CONOCIMINETO/AVANCECORP/Auditoria de conversiones - capas backend a frontend (2026-09-21).md`.

## 1. Estado al cerrar la sesión del 21/09

| Pieza | Estado | Dónde |
|---|---|---|
| Lectura por capas (12 lectores) y trazas verticales (11 cifras de gerencia) | **HECHO** | `evidencia/lectores-por-capa.txt`, `evidencia/trazas-verticales.txt`, `evidencia/hallazgos-crudos.json` (286 hallazgos) |
| Verificación adversarial (3 lentes por hallazgo) | **PARCIAL**: 41 verificados (13 sostenidos, 28 refutados) | `evidencia/veredictos-adversariales.tsv` |
| Hallazgos sin verificar | **PENDIENTE**: 252 (P0×4, P1×61, P2×122, P3×65) | `evidencia/hallazgos-pendientes-de-verificar.json` · solo P0/P1: `evidencia/hallazgos-pendientes-P0-P1.json` |
| Revisión secundaria Codex | **HECHA** sobre los 12 hallazgos TOP: CHANGES_REQUESTED / MEDIUM (1 consulta; queda 1 más disponible si aparece evidencia nueva) | `evidencia/codex-secondary-review-veredicto.md` (dictamen) · `evidencia/prompt-codex-secondary-review.txt` (prompt completo con evidencia) |
| Sonda de paridad contra producción | **PENDIENTE** (bloqueada por permisos de la sesión) | `supabase/scripts/sonda-paridad-conversion-prod.sql` |
| Correcciones | **NO EMPEZADAS** — requieren el OK explícito de Miguel (tocan SQL) | plan priorizado en el vault |

Código auditado: `main` local en `40f2501b` (21/09). Producción servía `build-20260920T223425954Z`.
Si el repo avanzó, las líneas citadas en la evidencia pueden moverse: re-ubicarlas con `grep -n`.

## 2. Qué hace falta en la otra cuenta

**Repositorio**
- Clonar/abrir el mismo repo en `main` (tronco: `avancecorp/main`), con el submódulo `public_html`.
- Ruta usada en los scripts: `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp`.
  Si la ruta cambia, editar la constante `REPO` al inicio de los dos `workflow-*.js`.

**Claude Code**
- Herramienta **Workflow** habilitada (modo `ultracode` o pedirlo con «usa un workflow»).
- Preferencia de Miguel para esta auditoría: **los agentes corren con Opus 5** (`model: 'opus'`,
  ya fijado en los scripts). La sesión principal puede ser Fable/Opus.
- MCP `codegraph` conectado (opcional; los agentes usan Read/Grep si no está).
- Los `CLAUDE.md` del repo se cargan solos. Leer antes: la nota del vault de esta auditoría,
  `Conversion unica en todo el CRM - plan de migraciones`, `Nucleo de conversion - diagnostico de
  llegadas y asignaciones 2026-09-04`, `Inventario de indicadores de Gerencia - Comercial`.

**Permiso que faltó en la sesión del 21/09**
- El clasificador de permisos bloqueó como «Production Reads» toda lectura contra la base real
  (`supabase db query --linked`). En la otra cuenta hay dos salidas:
  - que Miguel ejecute él mismo la sonda con el prefijo `!` (recomendado), o
  - añadir en `.claude/settings.local.json` una regla `allow` para
    `Bash(supabase db query --linked --file *)` y aceptar que es SOLO LECTURA (la sonda abre
    `begin transaction read only` y termina en `rollback`).
  El hook `.claude/hooks/proteger-comandos.sh` no bloquea `db query`; solo pide confirmación
  para `db reset|push` y `functions deploy`.

**Supabase CLI** (solo para la sonda)
- `supabase` ≥ 2.117 instalado (`/opt/homebrew/bin/supabase`), **logueado** y **enlazado** al
  proyecto `PortalAvanceCorp`: comprobar con `supabase projects list` (debe decir `"linked":true`).
  El enlace vive en `CRM-Avance-Corp/supabase/.temp/linked-project.json`. No hace falta la
  contraseña de la base: `db query --linked` va por la Management API.
- No hace falta ningún archivo `.env`: la sonda impersona a un perfil Gerencia con
  `set_config('request.jwt.claims', …)` bajo la sesión postgres del operador (patrón de
  `supabase/scripts/prueba-contrato-cierre-mes-estado-prod.sql`).

**Codex** (revisor secundario)
- `codex` CLI ≥ 0.155 con sesión iniciada (`codex login status` → «Logged in»), y `jq`.
- El MCP `codex` del repo (`.mcp.json` → `scripts/codex-review-mcp`) es la vía oficial
  (`mcp__codex__codex`, `sandbox: read-only`, `approval-policy: never`). Si falla al conectar
  (pasó el 21/09), la alternativa equivalente por CLI está en §3.4.
- Comprobar aislamiento antes: `bash scripts/codex-review-mcp --check` → `PASS`.

## 3. Comandos exactos

### 3.1 Sonda de paridad contra producción (solo lectura, lo primero)

Desde la raíz del repo (`AVANCECORP-desktop`), tecleado por Miguel:

```
! supabase db query --linked --file CRM-Avance-Corp/supabase/scripts/sonda-paridad-conversion-prod.sql
```

Qué mirar en la salida (todo agregado, sin datos personales):
- `nucleo_directo_sep_1_21`, `M_conversion_mensual_fn_sep`, `R_metricas_conversiones_fn_sep_1_21`,
  `D_distribucion_v3_sep_1_21`, `V_metricas_vendedores_fn`: **divisor, numerador y pct deben
  coincidir** para el mismo mes. Si `R`/`D` ≠ `M` con `cuadra=true`, los hallazgos C1–C3 del
  vault quedan demostrados con datos reales.
- `ledger`: `convertidos_sin_ledger` y `ledger_sin_etapa_convertido` deben ser 0;
  `mes_convertido_en_distinto_del_ledger` cuenta cierres cuya fecha de ficha y de ledger caen
  en meses distintos.
- `agosto_M_vs_R`: `m_cerrado` dice si agosto está sellado; si lo está y `m_pct ≠ r_pct`, C1
  está ocurriendo hoy.
- `puertas_conversion`: `inversiones_escritura_activo` debe ser `true` (si es `false`, desde el
  19/09 solo el piloto F8 puede cerrar leads: hipótesis F12, P0).

Pegar la salida en la nota del vault (sección «Sonda de paridad») y actualizar el estado.

### 3.2 Terminar la verificación adversarial de los pendientes

En Claude Code, con la herramienta Workflow. Primero los P0/P1 (65 hallazgos ≈ 195 agentes):

1. Leer `docs/auditorias/conversion-2026-09-21/evidencia/hallazgos-pendientes-P0-P1.json`.
2. Invocar:
   ```
   Workflow({
     scriptPath: "<repo>/CRM-Avance-Corp/docs/auditorias/conversion-2026-09-21/workflow-verificar-pendientes.js",
     args: { hallazgos: <contenido del JSON>, severidades: ["P0","P1"] }
   })
   ```
   Los scripts no leen disco: el JSON viaja en `args`. Para P2/P3 usar
   `hallazgos-pendientes-de-verificar.json` con `severidades: ["P2","P3"]`.
3. Un hallazgo sobrevive si ≥ 2 de 3 lentes no lo refutan. El resultado trae `confirmados`,
   `refutados` y el `critico` de completitud. Volcarlos al vault.

Nota: `resumeFromRunId` del workflow original **no sirve entre sesiones ni cuentas**; por eso
existe este script de continuación. El journal original (143 agentes) está en la cuenta del
21/09: `~/.claude-grupo/projects/-Users-usuario-Desktop-DESARROLLO-DESARROLLO-AVANCECORP-desktop/66be3e61-9a7a-428e-826a-77dfafc028c4/subagents/workflows/wf_14305e42-e0d/journal.jsonl`.

### 3.3 Repetir la auditoría completa desde cero (si el código cambió mucho)

```
Workflow({ scriptPath: "<repo>/CRM-Avance-Corp/docs/auditorias/conversion-2026-09-21/workflow-auditoria-conversiones.js" })
```
12 lectores + 11 trazas → dedupe → 3 lentes por hallazgo → crítico. El 21/09 la fase de lectura
tardó ~35 min y la verificación se cortó a los 41 hallazgos (~1 h en total). Presupuesto
orientativo completo: ~900 agentes. Actualizar antes la tabla «DEFINICIONES VIVAS» del script si
alguna migración nueva redefine una función de conversión (regla: última migración que la define).

### 3.4 Revisión secundaria con Codex

Vía oficial (MCP): `mcp__codex__codex` con `sandbox: read-only`, `approval-policy: never` y el
prompt de `evidencia/prompt-codex-secondary-review.txt` (empieza por `ROLE: SECONDARY_REVIEWER.`
e incluye el protocolo y la evidencia; el reviewer no puede abrir archivos).

Alternativa por CLI, idéntica en aislamiento (la usada el 21/09 porque el MCP no conectó):

```
cd ~/.config/ai-collaboration/reviewer-context && codex exec --skip-git-repo-check -s read-only \
  -c 'approval_policy="never"' -c 'agents.enabled=false' -c 'features.shell_tool=false' \
  -c 'features.apps=false' -c 'features.hooks=false' -c 'features.plugins=false' \
  -c 'features.remote_plugin=false' -c 'features.browser_use=false' -c 'features.computer_use=false' \
  -c 'features.in_app_browser=false' -c 'features.in_app_local_automation=false' \
  -c 'features.code_mode=false' -c 'features.skill_mcp_dependency_install=false' \
  -c 'web_search="disabled"' -c 'mcp_servers={}' - \
  < CRM-Avance-Corp/docs/auditorias/conversion-2026-09-21/evidencia/prompt-codex-secondary-review.txt
```

Para revisar hallazgos nuevos, reconstruir el prompt con el mismo esqueleto (rol + restricciones
+ `.ai/REVIEW_PROTOCOL.md` + reglas de negocio + hallazgos + extractos literales con archivo:línea).
Máximo 2 consultas por tarea; Codex asesora, el PRIMARY decide con evidencia.

## 4. Reglas que siguen mandando

- Auditoría = **solo lectura**. Ningún cambio de SQL, RLS, permisos o funciones `api` sin
  presentar el plan/SQL y esperar el OK de Miguel (LEVEL 3: 1 review de Codex cuando sea posible).
- Nunca editar una migración ya versionada; toda corrección va en migración nueva, ensayada en
  banco, con `auditor-rls` → `test-rls.mjs` → advisors, y registrada en `MIGRACIONES.md`.
- Trabajar sobre `main` y volver a `main` el mismo día; preflight obligatorio antes de publicar.
- Ningún secreto en prompts, notas ni commits. La sonda no imprime datos personales.

## 5. Archivos de esta carpeta

```
docs/auditorias/conversion-2026-09-21/
├── RETOMAR-EN-OTRA-CUENTA.md            ← este documento
├── workflow-auditoria-conversiones.js   ← auditoría completa (Workflow tool)
├── workflow-verificar-pendientes.js     ← continuación: 3 lentes sobre los pendientes (args)
└── evidencia/
    ├── hallazgos-crudos.json                    286 hallazgos con fuente (lector/traza)
    ├── hallazgos-pendientes-de-verificar.json   252 sin verificación adversarial
    ├── hallazgos-pendientes-P0-P1.json          65 (empezar por aquí)
    ├── hallazgos-P0-P1.txt                      los 76 P0/P1 crudos, legibles
    ├── veredictos-adversariales.tsv             41 verificados: lente, veredicto, severidad
    ├── lectores-por-capa.txt                    resumen + mapa + hallazgos de los 12 lectores
    ├── trazas-verticales.txt                    11 cifras de gerencia trazadas de punta a punta
    ├── prompt-codex-secondary-review.txt        prompt completo enviado a Codex
    └── codex-secondary-review-veredicto.md      dictamen de Codex (CHANGES_REQUESTED / MEDIUM)
supabase/scripts/sonda-paridad-conversion-prod.sql  ← sonda de producción (read only)
```

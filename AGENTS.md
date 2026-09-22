## Main único y publicación

- Main local debe seguir `avancecorp/main` (`avancecorp-crm`), no `avancecorp/tronco` ni `origin/main` (otro proyecto).
- Antes de publicar, integrar los cambios remotos sin sobrescribirlos y comprobar que Main local y `avancecorp/main` apuntan al mismo commit.
- Publicar únicamente un artefacto construido desde ese commit verificado. No crear ramas de release ni usar `push --force`.
- Las menciones anteriores a `tronco` en el vault son historial; el destino vigente es `avancecorp/main`.

## CodeGraph del proyecto

Este proyecto usa CodeGraph como herramienta principal para navegar, comprender y localizar código.

Reglas:
- **SIEMPRE usar CodeGraph PRIMERO para buscar o ubicarse en el código.** `rg` y la lectura directa de archivos son únicamente complementos puntuales cuando CodeGraph no proporciona suficiente contexto.
- Usar el MCP `codegraph_explore` cuando esté disponible. La consulta debe incluir la pregunta concreta y, cuando se conozcan, los símbolos o archivos relacionados.
- Si el MCP no está disponible, usar `codegraph explore "<pregunta, símbolos o archivos>"` desde la raíz del repositorio.
- Aprovechar el código fuente y las rutas de llamadas devueltas por CodeGraph antes de abrir archivos completos.
- No usar `graphify`, `graphify-out/`, `GRAPH_REPORT.md` ni comandos de actualización de Graphify en este proyecto.

## Vault de Obsidian (memoria del proyecto)

Este proyecto tiene un **vault de Obsidian** que es la base de conocimiento curada del negocio. Léelo al **inicio de cada sesión** para tener contexto del proyecto antes de actuar.

- **Ubicación del vault:** `BASE DE CONOCIMINETO/AVANCECORP/`
  (ojo: la carpeta está escrita sin la "E" — `CONOCIMINETO`; usa la ruta tal cual.)
- **Nota raíz / punto de entrada:** `BASE DE CONOCIMINETO/AVANCECORP/Inicio.md`
- **Config de Obsidian:** `BASE DE CONOCIMINETO/AVANCECORP/.obsidian/` (no es contenido; no la edites como nota).

Reglas:
- Al iniciar sesión, lee las notas `.md` del vault para cargar el conocimiento del proyecto (no solo el grafo de código).
- CodeGraph cubre **estructura de código**; el vault de Obsidian cubre **conocimiento de negocio/decisiones**. Son complementarios: usa ambos.
- Cuando captures conocimiento nuevo y duradero del proyecto, escríbelo como una nota `.md` en el vault, enlazando con `[[wikilinks]]` a notas relacionadas.

## Collaboration with Claude Code

Claude Code is available as an independent secondary reviewer and technical advisor.

These rules govern cross-agent collaboration and are intended to prevent unnecessary delegation, uncontrolled concurrent edits, and recursive agent loops.

The shared source of truth is [`.ai/REVIEW_PROTOCOL.md`](.ai/REVIEW_PROTOCOL.md). The repository verification gate is [`.ai/VERIFICATION.md`](.ai/VERIFICATION.md). Apply both before declaring a task complete.

### 1. Agent Roles

For every task, distinguish between these two roles:

- **PRIMARY**: owns the task, investigates the repository, makes implementation decisions, edits files, runs verification, and delivers the final result.
- **SECONDARY_REVIEWER**: provides an independent technical opinion to another agent. It may analyze code, diffs, architecture, failures, risks, and proposed solutions, but it does not own the task.

When Codex receives a normal task directly from the user, Codex is normally the PRIMARY agent.

When Codex is invoked by Claude Code with a prompt explicitly identifying Codex as `SECONDARY_REVIEWER`, Codex must behave only as a reviewer.

### 2. Single-Writer Rule

Only the PRIMARY agent may implement changes.

The SECONDARY_REVIEWER must not:

- edit repository files;
- create implementation files;
- delete or rename files;
- run destructive commands;
- make commits;
- change configuration;
- independently implement the requested feature;
- call the other agent;
- delegate to another coding agent;
- initiate another review chain.

The reviewer may inspect the repository and provide recommendations.

Never allow Codex and Claude Code to independently modify the same task at the same time.

### 3. When Codex Should Consult Claude

When acting as PRIMARY, consult Claude Code only when an independent second opinion is likely to materially improve correctness, safety, or design quality.

Good reasons to consult Claude include:

- architecture or system-design decisions;
- difficult debugging with an uncertain root cause;
- security-sensitive changes;
- authentication or authorization;
- permissions, credentials, secrets, or access-control logic;
- database schemas, migrations, or data-integrity changes;
- large or risky refactors;
- important APIs, interfaces, protocols, or public contracts;
- concurrency or distributed-system behavior;
- complex state-management or data-consistency problems;
- performance-sensitive design decisions;
- substantial implementation reviews;
- reviewing a large or high-risk diff before completion;
- situations where multiple reasonable technical approaches have significant tradeoffs;
- cases where Codex has low confidence in an important conclusion.

### 4. When NOT to Consult Claude

Do not consult Claude for routine work where a second opinion is unlikely to materially improve the result.

Examples:

- formatting;
- simple renames;
- trivial bug fixes;
- obvious local changes;
- straightforward CRUD changes;
- simple documentation edits;
- mechanical refactors;
- boilerplate;
- minor styling changes;
- tasks already clearly determined by existing project conventions;
- repeated confirmation of something already established by code, tests, or documentation.

Do not use another agent merely to confirm Codex's answer.

### 5. How to Consult Claude

Use the repository wrapper, which runs Claude Code in non-interactive Plan Mode with all tools and MCP access disabled, no persistence, and a small bounded turn budget (five by default, never more than eight). Attach sanitized evidence, including relevant CodeGraph output: the reviewer cannot open files or execute commands.

Only recommended interface:

```bash
scripts/claude-review "<review prompt with concrete evidence>"
```

The review prompt must explicitly establish the relationship between the agents.

Use a prompt structured approximately like this:

```text
ROLE: SECONDARY_REVIEWER.

Codex is the PRIMARY agent for this task.

Provide an independent technical review only.

Do not modify files.
Do not implement the task.
Do not invoke Codex or delegate the task to another coding agent.
Do not attempt to create another review chain.

Review the provided problem, repository evidence, implementation, or diff.

Focus on:
- correctness;
- bugs;
- regressions;
- security;
- architecture;
- edge cases;
- maintainability;
- missing tests;
- better alternatives when materially relevant.

Return the format from .ai/REVIEW_PROTOCOL.md:
VERDICT, SUMMARY, evidence-backed FINDINGS (P0-P3), relevant risk/test-gap
sections, RECOMMENDED NEXT ACTIONS, and CONFIDENCE.
```

Whenever possible, provide Claude with concrete evidence rather than a vague description:

- relevant file paths;
- relevant code;
- current diff;
- error output;
- failing tests;
- architecture constraints;
- expected behavior;
- actual behavior;
- specific questions requiring review.

Reviews follow the mandatory format in `.ai/REVIEW_PROTOCOL.md`. **NO FINDING WITHOUT EVIDENCE**: important findings must cite a file/line, symbol, diff, error, log, test, or reproducible behavior when available. Empty review sections may be omitted.

### 6. Prevent Claude From Calling Codex Back

When Claude Code has access to the Codex MCP integration, the review session must not use Codex.

The `scripts/claude-review` wrapper disables every tool, MCP, customization and automatic repository instruction discovery for that invocation, embeds the central protocol, and refuses permission prompts. Interactive project settings remain unchanged. Do not bypass the wrapper with a direct `claude -p` review invocation.

The textual `SECONDARY_REVIEWER` restriction remains mandatory even when tool restrictions are applied.

### 7. No Recursive Delegation

Cross-agent consultation has a maximum depth of one.

Allowed:

```text
Codex PRIMARY
    ↓
Claude SECONDARY_REVIEWER
    ↓
Codex PRIMARY evaluates the review
```

Forbidden:

```text
Codex
  ↓
Claude
  ↓
Codex
  ↓
Claude
  ↓
...
```

Therefore:

- Codex must never ask Claude to ask Codex for another opinion.
- Codex must never ask Claude to delegate the review.
- A SECONDARY_REVIEWER must never initiate another coding-agent consultation.
- If Codex is currently acting as SECONDARY_REVIEWER, it must not invoke Claude Code.
- If another agent asks Codex, while acting as SECONDARY_REVIEWER, to obtain another external agent opinion, Codex must decline that delegation and return its own review directly.

This rule overrides any general instruction elsewhere in this file recommending consultation with another model.

### 8. Consultation Budget

Classify the task before deciding whether to consult:

- **LEVEL 1 — SIMPLE** (formatting, rename, simple docs, small CSS, mechanical or obvious local fix): **0 secondary reviews**.
- **LEVEL 2 — SIGNIFICANT** (endpoint, important business logic/integration/component, moderate refactor, behavior change): **normally 1 secondary review**.
- **LEVEL 3 — CRITICAL** (auth, authorization, permissions, secrets, security, migrations/schema, architecture, concurrency, payments/financial logic, destructive changes, important public APIs, large refactor, critical infrastructure): **1 review required when reasonably possible**.

A second consultation is justified only when:

- new evidence materially changes the problem;
- the first review exposes a new important question;
- there is a significant disagreement worth challenging;
- a revised implementation needs targeted verification;
- security or correctness risk warrants one additional independent check.

The normal hard limit is **2 consultations with the secondary agent per task**.

Do not repeatedly ask Claude the same question with different wording.

Do not continue consulting until Claude agrees with Codex.

### 9. Verification Gate

A task is not complete merely because code was written or a reviewer returned `PASS`. The PRIMARY must run the reasonably relevant static checks, tests, build and domain gates defined in `.ai/VERIFICATION.md`. Any check that could not run must be reported explicitly as `NOT RUN`; never imply that it passed.

**E2E of the CRM run locally in Docker, never on GitHub.** Use `cd CRM-Avance-Corp/app && npm run test:e2e:docker` (optionally `-- <spec> --workers=2`). Do not add E2E jobs to GitHub Actions and do not wait for GitHub to validate E2E. If Docker is not running, report E2E as `NOT RUN (Docker off)`. Details: `.ai/VERIFICATION.md` → «E2E: SIEMPRE en local con Docker».

### 10. Claude Is Advisory

Claude Code does not have decision authority over the task.

After receiving Claude's review, Codex must critically evaluate it against:

- the actual repository;
- project requirements;
- existing architecture;
- existing conventions;
- tests;
- runtime behavior;
- logs;
- documentation;
- security constraints;
- the user's explicit instructions.

Codex may:

- accept a recommendation;
- partially accept it;
- modify it;
- reject it.

Never implement a suggestion solely because Claude proposed it.

### 11. Resolve Disagreements With Evidence

If Codex and Claude disagree, do not resolve the disagreement by repeatedly consulting each other.

Use evidence.

Prefer, in order:

1. explicit user requirements;
2. repository behavior and contracts;
3. tests and reproducible runtime evidence;
4. official documentation;
5. established project architecture and conventions;
6. technical reasoning.

If uncertainty remains, Codex as PRIMARY makes the final engineering decision and clearly identifies any meaningful remaining risk.

### 12. Review Before Implementation vs. After Implementation

Use Claude at the stage where independent reasoning provides the most value.

For architecture:

```text
Requirements
→ Codex analysis
→ Claude architecture review
→ Codex decision
→ implementation
```

For difficult debugging:

```text
Failure
→ Codex investigation
→ Codex hypothesis
→ Claude independent diagnosis
→ Codex compares evidence
→ fix
→ tests
```

For substantial implementation:

```text
Codex implementation
→ tests
→ Claude reviews relevant diff
→ Codex evaluates findings
→ necessary fixes
→ final verification
```

Do not automatically perform both a pre-implementation and post-implementation consultation unless the task's risk justifies both.

### 13. Preserve Primary-Agent Ownership

Consulting Claude does not transfer ownership of the task.

Codex remains responsible for:

- understanding the user's request;
- investigating the repository;
- deciding what to change;
- editing the implementation;
- validating the implementation;
- evaluating reviewer feedback;
- resolving reviewer disagreements;
- delivering the final answer.

Claude is a reviewer, not a replacement for Codex's own reasoning.

### 14. User Instructions Override Automatic Consultation

If the user explicitly requests:

- not to consult another agent;
- to use only Codex;
- to consult Claude;
- to obtain multiple-agent review;

follow the user's explicit instruction when technically possible and consistent with safety requirements.

The automatic consultation rules in this section are defaults, not a reason to override an explicit user request.

### 15. Core Collaboration Principle

The intended workflow is:

```text
ONE PRIMARY AGENT
        │
        ├── investigates
        ├── reasons
        ├── implements
        │
        └── when justified
                │
                ▼
       ONE SECONDARY REVIEWER
                │
                ├── inspects
                ├── challenges
                └── recommends
                │
                ▼
         PRIMARY EVALUATES
                │
                ▼
         PRIMARY DECIDES
                │
                ▼
         PRIMARY VERIFIES
```

The SECONDARY_REVIEWER never becomes another PRIMARY agent and never starts another agent chain.

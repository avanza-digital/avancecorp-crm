## CODEgraph (MCP)

Este proyecto usa el MCP **CODEgraph** (`mcp__codegraph__*`) para buscar y ubicarse en el código.

Reglas:
- **SIEMPRE usar CODEgraph PRIMERO para buscar/ubicarse en el código** (instrucción explícita de Miguel): el grafo hace las búsquedas más ágiles. `grep`/lectura cruda de archivos es solo complemento puntual cuando CODEgraph no alcanza, NUNCA el primer recurso.
- Para preguntas sobre el código, empieza por `codegraph_symbol_search` / `codegraph_search_by_pattern` para localizar símbolos, y `codegraph_get_ai_context` / `codegraph_get_curated_context` para contexto enfocado.
- Para relaciones usa `codegraph_get_callers` / `codegraph_get_callees` / `codegraph_analyze_impact`; para navegación amplia, `codegraph_get_module_summary` / `codegraph_get_dependency_graph`.
- Si el índice está desactualizado tras cambios, refréscalo con `codegraph_index_files` (archivos puntuales) o `codegraph_reindex_workspace`.

## Vault de Obsidian (memoria del proyecto)

Este proyecto tiene un **vault de Obsidian** que es la base de conocimiento curada del negocio. Léelo al **inicio de cada sesión** para tener contexto del proyecto antes de actuar.

- **Ubicación del vault:** `BASE DE CONOCIMINETO/AVANCECORP/`
  (ojo: la carpeta está escrita sin la "E" — `CONOCIMINETO`; usa la ruta tal cual.)
- **Nota raíz / punto de entrada:** `BASE DE CONOCIMINETO/AVANCECORP/Bienvenido.md`
- **Config de Obsidian:** `BASE DE CONOCIMINETO/AVANCECORP/.obsidian/` (no es contenido; no la edites como nota).

Reglas:
- Al iniciar sesión, lee las notas `.md` del vault para cargar el conocimiento del proyecto (no solo el grafo de código).
- El MCP **CODEgraph** cubre **estructura de código**; el vault de Obsidian cubre **conocimiento de negocio/decisiones**. Son complementarios: usa ambos.
- Cuando captures conocimiento nuevo y duradero del proyecto, escríbelo como una nota `.md` en el vault, enlazando con `[[wikilinks]]` a notas relacionadas.

## UI Playground (laboratorio de animaciones)

Vive **FUERA de este repo**, en la carpeta hermana `../ui-playground/`
(= `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/ui-playground/`). Es el laboratorio donde se
crean y aprueban animaciones ANTES de tocar los proyectos reales.

- `galeria/` — componentes de UI animados (React + Vite + **Motion** + **GSAP**) → `npm run dev` → `localhost:5173`.
- `remotion/` — videos programados con **Remotion** (MP4: intros, piezas para redes) → `npm run dev` → `localhost:3000`.
- Regla de herramientas: Remotion = SOLO videos; Motion/GSAP = componentes vivos de interfaz.
- Flujo: crear en el laboratorio → Miguel aprueba → promover (CRM casi directo por ser React; portal portado a vanilla).

**Comandos del flujo** (en `.claude/commands/`): `/lab` (arranca los 2 servidores), `/componente <pedido>`,
`/animacion <pedido>`, `/render [id]`, `/promover <componente> al crm|portal`. Detalle en `../ui-playground/README.md`
y en la nota del vault **"UI Playground (laboratorio de animaciones)"**.

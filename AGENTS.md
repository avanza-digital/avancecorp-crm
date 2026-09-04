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
- **Nota raíz / punto de entrada:** `BASE DE CONOCIMINETO/AVANCECORP/Bienvenido.md`
- **Config de Obsidian:** `BASE DE CONOCIMINETO/AVANCECORP/.obsidian/` (no es contenido; no la edites como nota).

Reglas:
- Al iniciar sesión, lee las notas `.md` del vault para cargar el conocimiento del proyecto (no solo el grafo de código).
- El grafo de `graphify-out/` cubre **estructura de código**; el vault de Obsidian cubre **conocimiento de negocio/decisiones**. Son complementarios: usa ambos.
- Cuando captures conocimiento nuevo y duradero del proyecto, escríbelo como una nota `.md` en el vault, enlazando con `[[wikilinks]]` a notas relacionadas.

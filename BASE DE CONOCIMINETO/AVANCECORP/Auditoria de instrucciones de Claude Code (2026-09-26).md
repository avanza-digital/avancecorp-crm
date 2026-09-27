---
tags: [claude, codex, instrucciones, auditoria, despliegue]
fecha: 2026-09-26
estado: correcciones aplicadas; 4 decisiones pendientes de Miguel
---

# Auditoría de instrucciones de Claude Code (26/09/2026)

Se revisaron los archivos que leen los agentes (CLAUDE.md raíz, del CRM y del portal, subagentes,
skills del repo y de `~/.claude`) contra el código real. Solo se tocó texto de instrucciones:
nada de producción, base de datos ni despliegue. Review de Codex: BLOCK con 2 P1, ambos
aceptados y corregidos.

## Qué quedó corregido

- **Preflight en las skills de release.** Ni `/release-crm` (Claude) ni `$release-crm` (Codex)
  corrían el preflight obligatorio. Ahora es un paso entre construir el ZIP y publicar. Un
  rollback con el ZIP anterior lo rechazará el preflight: lo decide Miguel, no la sesión.
  Ver [[Main unico - sincronizacion y publicacion 2026-09-04]].
- **Trigger de auditoría del CRM.** Las tablas `crm.*` usan `private.log_audit_crm`, o
  `private.log_audit_sin_secretos` si guardan secretos. `log_audit_change` es del portal. Lo
  decían mal `auditor-rls`, la skill `nueva-migracion` y `supabase/migrations/LEEME.md`.
- **CLAUDE.md del portal.** El changelog se movió a `HISTORIAL.md` (queda solo la última
  entrada). La tabla de versiones `?v=N` se reemplazó por un `grep` que lee la versión del
  código: la tabla decía SW v95 y el código tenía v136.
- **CodeGraph.** El MCP no tiene `codegraph_explore`; se nombran las herramientas reales.
- **Skills propias de claude.ai** (avanza-digital-consultor, avanza-code-prompter,
  pwa-architect, web-platform-expert). Se corrigieron en la copia local sincronizada. Hay que
  replicar el cambio en claude.ai o la próxima sincronización lo pisa.

## Decisiones pendientes de Miguel

1. **Arquitectura en 4 capas del CLAUDE.md raíz.** Dice describir este backend, pero el CRM no
   tiene esquema `api` y la app llama `.schema('crm')` directo. ¿Es el objetivo del CRM (el
   código es deuda) o solo el estándar para módulos nuevos?
2. **Preflight rechazado.** El CLAUDE.md raíz manda crear una rama desde lo vivo, pero la regla
   más nueva exige publicar solo desde `main` igual a `avancecorp/main`. ¿Cuál vale?
3. **Preflight del portal.** El CLAUDE.md raíz lo exige con un ZIP; el del portal describe una
   subida manual sin preflight.
4. **Remotion.** `/lab` dice que ahí se diseñan también los componentes; el CLAUDE.md dice
   «Remotion = SOLO videos».

Además: `_dev_artifacts/citas-ticket-soles/repo/` es una copia vieja del repo con sus propias
instrucciones (CLAUDE.md de 1 269 líneas) que cargan si una sesión entra ahí.

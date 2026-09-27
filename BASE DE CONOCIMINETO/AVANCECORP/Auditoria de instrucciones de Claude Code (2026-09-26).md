---
tags: [claude, codex, instrucciones, auditoria, despliegue]
fecha: 2026-09-26
estado: correcciones aplicadas; decisiones de Miguel aplicadas el 27/09
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

## Decisiones de Miguel (27/09/2026), ya aplicadas

1. **Arquitectura en 4 capas: sí aplica al CRM actual.** El CLAUDE.md raíz explica cómo se
   traduce al CRM (puertas = funciones de `crm`, núcleo = `private` y triggers). Lo que no
   cumple es deuda del [[Mapa de capas del servidor CRM - 2026-09-17]] y se cierra con su plan.
2. **Preflight rechazado: rescate en una copia aparte.** Se crea una rama desde lo vivo, se
   publica desde ella y se fusiona a `main` el mismo día. Quedó como excepción explícita en el
   CLAUDE.md, en AGENTS.md y en la skill de release de Codex.
3. **Portal: sin preflight.** Se sube sobrescribiendo archivos. El script `preflight-portal.mjs`
   queda solo para el caso de subir un ZIP que reemplace el sitio entero.
4. **Remotion: para los dos**, videos y diseño de animaciones (también de componentes). Ver
   [[UI Playground (laboratorio de animaciones)]].

La copia vieja `_dev_artifacts/citas-ticket-soles/repo/` se movió a la Papelera el 27/09. No
tenía cambios sin guardar y su último commit ya estaba en `main`. Los logs de la carpeta
padre, que citan otras notas, se quedaron.

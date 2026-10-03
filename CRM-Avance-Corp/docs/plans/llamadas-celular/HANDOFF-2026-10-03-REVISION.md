# Handoff — retomar el 03/10/2026 la revisión de F2 + F3 (sesión de Miguel, Claude en Mac)

Complementa `HANDOFF-2026-10-03.md` (el de Jhosep). Qué se hizo el 02/10 y dónde quedó cada cosa.

## Estado

- **Nada aplicado en producción.** Solo lecturas: volcado de esquema, huellas, `auth.uid()`, configuración
  sin datos personales y `cron.job`.
- Revisión completa en **`REVISION-2026-10-02.md`**: 5 fallos que bloquean (3 reproducidos), 11 menores,
  4 de la guía de publicación y 7 del propio trabajo de Claude.
- Decisiones de Miguel del 02/10: ratifica las 12 provisionales (con la salvedad anotada en la revisión) y
  aprueba #13, #14 y #15.

## Dónde está todo

| Qué | Dónde |
|---|---|
| Worktree propio (rama `feat/llamadas-f2`, commits locales SIN push) | `…/AVANCECORP-desktop-worktrees/llamadas-f2-20261002` |
| Bloque `testLlamadasCelular` del gate | `supabase/scripts/test-rls.mjs` (commit de esta rama) |
| Runner del gate contra el stack propio, verificación de hallazgos y medición | `supabase/scripts/llamadas-celular/banco/` |
| Encargo y respuesta de Codex r1 (BLOCK) | `docs/encargos/2026-10-02-codex-llamadas-celular-f2-f3-r1*.md` |
| Stack Supabase propio (`avancecorp-llamadas-20261002`, puertos 563xx) con esquema de prod + 4 migraciones + semilla del gate | Docker, encendido. `config.toml` en la carpeta de abajo |
| Volcado de esquema de prod, configuración cargada (sin datos personales), logs del gate | `…/AVANCECORP-desktop-worktrees/llamadas-banco-20261002-NO-VERSIONAR/` (fuera de git a propósito) |

## Orden para mañana

1. `git fetch avancecorp` y ver si Jhosep subió algo a `feat/llamadas-f2`; integrar con merge antes de seguir.
2. **Arreglar el banco** (punto 21): cargar `crm.sla_operacion_control` (y revisar qué otras tablas de
   control faltan), repetir el gate antes/después y comparar.
3. **Plan corto de la migración de correcciones** para el OK de Miguel (puntos 1–4 y 6–13) y su
   **decisión sobre el punto 5** (enlace automático o recuperación en F4 + retención).
4. Con el OK: migración nueva (nunca editar las 4), ajustar el bloque del gate (que exija el comportamiento
   corregido, lead borrado, entrantes y enlace real), `verificar-datos.sql`, reversas, registradores, y
   Codex r2 sobre el diff.
5. Corregir la guía de publicación (puntos 17–20) y confirmar con Miguel los criterios de Claude, la regla
   extra de la decisión 4 y la #12.
6. Push de la rama solo cuando Miguel lo diga (es la rama del PR #169 de Jhosep).

## Prompt para retomar

> Retomamos la revisión de «Llamadas desde el celular» (PR #169). Lee
> `CRM-Avance-Corp/docs/plans/llamadas-celular/HANDOFF-2026-10-03-REVISION.md` y `REVISION-2026-10-02.md`
> en el worktree `AVANCECORP-desktop-worktrees/llamadas-f2-20261002`. Empieza por el punto 1 del orden.

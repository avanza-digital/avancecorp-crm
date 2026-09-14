---
tags: [crm, multiempresa, f8, instalacion]
actualizado: 2026-09-14
---

# F8 — ensayo completo antes de instalar

Miguel reanudó el trabajo. Continúa [[F8 - pausa segura de instalacion (2026-09-14)]].
El aviso posterior de conexión se resolvió según confirmó Miguel; no se estableció
su causa y no se atribuye a F8.

La nueva rama exclusiva tiene el esquema vigente, sus 279 migraciones exactas y
los dos SQL F8 aprobados, con hashes verificados. Se conservaron Auth, Storage,
propietarios y permisos. Claude revisó la reconstrucción y Codex resolvió sus
observaciones con guardas y comprobaciones adicionales.

Pasaron 27 pruebas SQL remotas, 31 locales y 12 grupos con sesiones Auth reales
de usuarios ficticios. La cartera cuenta los 593 movimientos reales del ensayo
y excluye sus cinco demos. También se probaron permisos, revocación, vencimiento,
concurrencia y reversa. El ensayo terminó apagado.

**Producción todavía no tiene F8 instalada.** Sigue la integración de Main, build,
preflight vivo, merge OFF, comprobación posterior y cierre de la rama temporal.
La autorización de los dos SQL ya existe: no pedirla de nuevo. No repetir el lote
de diez enlaces reales. Equipo, encendido y casos reales G7 siguen pendientes.

Evidencia: `CRM-Avance-Corp/supabase/scripts/multiempresa-f8/ENSAYO-2026-09-14.md`.
Plan: [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].

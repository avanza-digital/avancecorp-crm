---
tags: [crm, f6, postventa, publicacion, retoma]
fecha: 2026-09-11
estado: cerrada-publicada-apagada
---

# F6 — cierre y ajustes publicados

Los últimos ajustes de F6 se publicaron el 11/09 a las 10:13 Lima: botón visible
para comprobantes, retorno de foco al cerrar diálogos y mensaje de conexión en
español con recuperación del envío. La revisión manual quedó cerrada con la
excepción de VoiceOver autorizada por Miguel; se conserva NOT RUN.

F4/F5/F6 siguen **apagadas en producción**. No se ejecutaron migraciones ni cambios
de banderas. Se conservaron Facturación, Reparto y los archivos ajenos del worktree.

Commit del artefacto: `4febe47cecbda6432747fc87f8a0eaa30f2bd4b7`.
Release: `crm-20260911T150446Z-4febe47cecbd`.
Main y `avancecorp/main` coincidían antes de construir/publicar; el ZIP anterior
está conservado y verificado para reversión.

Gate completo local: **PASS**, 3.246 tests y 160 E2E; 26 E2E omitidas por su
configuración existente. Preview del ZIP, 84 archivos publicados, acceso al CRM,
Hoy/Cartera y banderas comprobados. El portal mantiene la misma huella.
CI servidor y CI frontend, incluida su ejecución E2E, aprobados sobre el commit
exacto del artefacto. F6 queda cerrada como entrega y revisión, con la excepción
indicada; su activación productiva sigue el plan.

Claude entregó CHANGES_REQUESTED después de un primer intento sin dictamen válido.
Codex evaluó sus observaciones contra los requisitos, la aprobación visual y las
pruebas; no se atribuye PASS a Claude ni se considera una opinión sustituto del gate.
Detalle, límites y evidencia en el [acta de cierre](../../CRM-Avance-Corp/supabase/scripts/f6/CIERRE-2026-09-11.md).

La siguiente fase es **F7**, métricas por empresa/moneda y conciliación G6 antes del
piloto F8. F8/F9 y el tratamiento de las 15 identidades pendientes del último
recenso conservan sus requisitos. Las comisiones se calculan fuera del sistema.

Continúa [[F6 - publicada y apagada (2026-09-10)]] y resuelve la publicación pendiente
de [[F6 - pausa segura antes de publicar ajustes (2026-09-10)]]. Evidencia manual:
[[F6 - pruebas delegadas y ajustes de accesibilidad (2026-09-10)]]. Gobierna el
[[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].

---
tags: [crm, leads, eliminacion, auditoria, sla]
actualizado: 2026-10-15
---

# Eliminar lead por error de carga — copia auditada (15/10/2026)

**Estado:** servidor EN PRODUCCIÓN 15/10 (~00:55 Lima, migración `20261015044917`, PR #283 `abd04f61`).
Front PUBLICADO 15/10 ~01:05 (`build-20261015T055830904Z`, commit `f6c711f2`; preflight ok, smoke byte a byte).
MARGARITA `de667c0d` borrada con el botón el 15/10 a las 01:19 Lima (copia versión 1, no queda ninguna fila suya).
**r2 EN PRODUCCIÓN 15/10 ~11:50 Lima** (migración `20261015150731`, PR #288 `b12aaee2`): ver «Ampliación r2».

## Qué resuelve
Un lead creado por error no se podía borrar: los candados del SLA y del ledger de asignaciones prohíben SIEMPRE el
DELETE, y el origen no se cambia después del alta (P0409). Esos candados **no se quitaron ni se debilitaron**.

## Cómo funciona
- Botón «Eliminar lead (error de carga)» en la ficha, solo para **gerencia** (rol CRM) o **admin/superadmin** del
  portal. Motivo obligatorio (10–500 caracteres) y confirmación escribiendo ELIMINAR.
- Puerta `crm.eliminar_lead_error_carga(p_lead_id, p_motivo)`: valida rol (42501), motivo (22023) y que el lead
  se pueda borrar (P0409, con TODAS las razones): sin contrato, perfil ni inversionista; sin conversión ni cierres;
  sin historia de inversión (tasa, solicitud, cartera de inversionistas, búsqueda, gestiones); sin tareas o llamadas
  enlazadas desde otro lead; creado hace **30 días o menos** (decisión de Miguel, 14/10); ningún mes cerrado desde su
  alta.
- Antes de borrar guarda una **copia completa e inmutable** en `crm.leads_eliminados` (lead + 17 tablas hijas).
  Gerencia la consulta con `crm.listar_leads_eliminados()` (quién, cuándo, motivo, cuántas filas); la tabla no tiene
  lectura directa por la API. La copia guarda DNI/teléfono para siempre (Miguel la dejó completa).
- Los **8 candados** que custodian filas del lead aceptan un DELETE solo si la fila está ya copiada, idéntica, en la
  misma transacción, por el mismo actor, y el permiso `crm.borrado_lead_error` nombra a ese lead
  (`private.borrado_lead_error_autoriza`). Cualquier otro DELETE directo sigue bloqueado con su mensaje de siempre.
- Si aparece una llave foránea nueva hacia el lead (o cambia su acción), la puerta se niega (55000) hasta revisarla.

## Pruebas
Banco Docker con el esquema de producción: 69/69 PASS, mutantes de la llave, carreras reales de dos conexiones y
reversa. Codex r1+r2 y auditor-rls aceptados. Detalle: `CRM-Avance-Corp/supabase/scripts/eliminar-lead-error-carga/`
y ledger `MIGRACIONES.md` (20261015044917).

## Ampliación r2 (15/10): leads con ficha de inversionista
Miguel (15/10): «yo quiero borrar cualquier tipo de lead». Si el lead tiene contrato, inversión, cierre o conversión,
**ya es cliente** y nunca se borra. Se mantienen el tope de 30 días y el mes sellado. Motivo: «Prueba leeds» se rechazaba
porque el formulario le había creado una ficha de inversionista vacía.
- Se borra con el lead su **ficha de inversionista** si es solo de ese lead, nació con él o después (o como mucho 1 s
  antes, si su documento vino del lead) y no tiene dinero ni historia propia. No se borra si tiene perfil o alta al
  portal, otro lead, inversiones, cierres, reservas, acreditaciones, postventa, fusiones, cotitulares, operaciones, tareas,
  búsquedas o veto «no contactar».
- Con la ficha se van su enlace, identificadores, responsables, gestiones sin tarea, lecturas, datos de contacto y
  solicitudes de inversión **canceladas** de ESE lead (nunca confirmadas, sin revisiones).
- La **solicitud de tasa** sin usar y que no es de un cliente se borra con sus avisos push. El candado
  `trg_solicitudes_tasa_solo_por_puerta` recibió la misma excepción de 5 líneas que los otros 8 (ahora son 9).
- Pruebas: banco Docker con 100/100, carrera real de dos conexiones y reversa (`reversa-r2.sql`). Revisaron Codex
  (2 rondas) y auditor-rls. Huellas en producción: puerta `15ce9327…` y candado de tasa `9d5d0a1a…`.

Relacionado: [[Eliminar inversion - admin y gerencia, tres empresas (2026-10-05)]] (mismo patrón de válvula y copia).

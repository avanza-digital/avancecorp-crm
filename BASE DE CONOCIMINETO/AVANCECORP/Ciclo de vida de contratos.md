---
tags: [feature, negocio, contratos, backend]
actualizado: 2026-07-13
---

# Ciclo de vida de contratos

**Qué es (2026-07-13):** los contratos ya no quedan "activos" para siempre — ahora tienen ciclo completo: **activo → vencido → renovado / retirado**. Diseñado con las reglas de negocio que definió Miguel.

## Las reglas de negocio (decididas por Miguel)

1. **Vencimiento automático:** un job diario (09:10 Perú) marca "vencido" todo contrato cuya fecha pasó. El día del vencimiento el contrato sigue activo (ese día aún se cobran cuotas).
2. **Renovación = contrato NUEVO:** se crea el contrato nuevo (categoría "Renovación") y el viejo se cierra como "renovado", **enlazado** al nuevo (`renovado_a_id`). El capital que se rolea queda como cuotas **"trasladado"** — jamás cuentan como mora ni deuda.
3. **Avisos previos:** 30 y 7 días antes del vencimiento, al **cliente** (novedad + push + correo) y al **asesor** (correo + push). Por ventanas con sello: un día de caída se auto-recupera, sin avisos dobles.
4. **El cliente ve "Finalizado"** (nunca "Vencido" — connota incumplimiento nuestro) o "Renovado" (+ N° del contrato nuevo), con botón de WhatsApp a su asesor. Su devengo se congela en el cierre; el capital sale de las métricas activas.
5. **Retiro:** exige que todas las cuotas estén resueltas (el capital realmente se devolvió). Retiro anticipado con cuotas futuras: fuera de alcance v1 (superadmin por SQL).

## Cómo se cierra un ciclo (equipo)

En `/admin/contratos`, botón **"Cerrar"** (solo contratos activos/vencidos) → elegir Renovado (con el selector del contrato nuevo) o Retirado → confirmar tipeando el N° exacto. **Orden obligatorio: crear el contrato nuevo ANTES de cerrar el viejo.** Una vez cerrado, nada se puede revertir salvo el superadmin (máquina de estados + candados en BD).

## Fechas que mandan

- **~24-08-2026:** primer aviso de 30 días real (el frontend debe estar en prod antes).
- **23-09-2026:** vence el primer contrato → primer marcado automático (20 contratos vencen en 2026).

## Detalle técnico

Fuente canónica → `public_html/CLAUDE.md` (changelog 2026-07-13b, §4 y §8): 2 migraciones, RPCs `cerrar_contrato`/`marcar_contratos_vencidos`, edge `ciclo-contratos`, cron `ciclo-contratos-diario`, `contratos v30`/`pagos v31`/`dashboard v32`/`inversion v24`/`crono-timeline v6`, SW v95. Verificado con QA de transacciones revertidas en prod (8/8) + revisión adversarial de 43 agentes (11 hallazgos corregidos).

## Notas relacionadas
[[Arquitectura del portal]] · [[Categorización de inversiones - Nuevo Renovación Upgrade]] · [[Notificaciones de pagos]] · [[Interés compuesto]] · [[Rol Directorio]] · [[Auditorías del portal]] · [[Inicio]]

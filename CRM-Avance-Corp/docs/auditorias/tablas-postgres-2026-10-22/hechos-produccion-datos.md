# Consistencia de DATOS medida en producción (solo lectura) — 2026-10-22, entre 20:34 y 21:03 Lima (hora real por `date`)

## Huérfanos en columnas `_id` sin FK (tablas vivas)
| Comprobación | Filas |
|---|---|
| cuotas_cuenta_pagada.contrato_id → contrato inexistente | 10 (los 10 constan en contratos_eliminados_auditoria: foto por diseño) |
| cuotas_cuenta_pagada.cuenta_bancaria_id → cuenta inexistente | 3 (origen `inferido`; sus contratos también están borrados) |
| ledger_rentabilidad.contrato_id → contrato inexistente | 54 filas / 46 contratos: 42 filas constan como eliminados; **12 filas (11 contratos) NO constan en ninguna auditoría** |
| ledger_rentabilidad.cliente_id → perfil inexistente | 4 |
| correcciones_categoria_contrato.contrato_id → contrato inexistente | 1 |
| leads.contrato_id → contrato inexistente | 6 (los 6 constan como eliminados; YA CONOCIDO: «borrar+recrear contrato deja leads.contrato_id colgante», pendiente de Miguel) |
| tareas.cancelada_por_id, conversion_acreditaciones.analista_id, contrato_cuenta_pago_asignaciones.*, cuentas_bancarias_retiros.cuenta_id | 0 |
| sla_operacion_recibos.sujeto_id | polimórfico por diseño: 6141 = lead, 9077 = tarea, 0 colgantes; lead_id 0 colgantes |

## Coherencia de la conversión (crm.leads, 333 convertidos)
| Comprobación | Filas |
|---|---|
| convertidos con contrato_id NULL | 175 (96 con cierre externo vivo · 26 con inversión vía inversionista_leads · 53 restantes) |
| de los 53 restantes: con perfil_id de cliente | 50 (44 con contrato en public por ese perfil) · 49 con leads.inversionista_id · 38 con acreditación (35 acreditada, 2 fuera_de_plazo, 1 operacion_cartera) · 53 con episodio cerrado «convertido» · 1 con cierre externo ANULADO y nada más |
| ⇒ `leads.contrato_id` NO es la fuente de la venta (está vacío en 175/333); la fuente son acreditaciones/inversiones. Quien lea `leads.contrato_id` se equivoca. | |
| convertidos sin acreditación, convertido_en < 01/09 (antes de la política) | 25 (esperado) |
| **convertidos sin acreditación, convertido_en ≥ 01/09** | **2**: 2026-09-16 y 2026-09-18, sin contrato y sin cierre externo vivo → no entran en el sello de septiembre (que se sella el 22/10) |
| acreditaciones cuyo lead no está convertido | 0 |
| convertidos sin vendedor_id / sin convertido_en | 0 / 0 |
| descartados sin motivo / sin descartado_en | 0 / 0 |

## Otras
| Comprobación | Filas |
|---|---|
| inversionistas sin responsable abierto | 5 (0 con inversión; caso Ivett conocido) |
| inversiones sin titular | 0 |
| inversiones.contrato_id repetido | 0 (índice único parcial) |
| contratos del portal sin inversión en crm | 575 (contratos anteriores al CRM; no es hallazgo) |
| responsables abiertos duplicados / asignaciones abiertas duplicadas | 0 (índices únicos parciales `inv_responsables_abierto_uidx`, `lead_asignaciones_un_abierto_por_lead_idx`) |

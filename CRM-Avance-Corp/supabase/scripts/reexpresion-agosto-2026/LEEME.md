# Reexpresión de agosto 2026 (contratos atrasados)

**Por qué.** El 10/09 el ciclo automático selló agosto. Desde entonces el trigger
`trg_definir_periodo_comercial_contrato` rechaza todo contrato con fecha de inicio en
agosto («mes comercial sellado»). Hay contratos de agosto sin cargar y Miguel quiere que
cuenten en agosto, también en el ranking y las metas. Es SOLO por agosto.

**Cómo.** Reabrir → cargar → volver a sellar. No hay migración ni interruptor.

1. `01-reabrir.sql` — guarda la foto (1 sello + 16 vendedores) en
   `private.respaldo_cierre_agosto_2026`, retira sello y foto, y PAUSA el job 3
   `crm-cierre-mes-diario`. Copia local: `releases/respaldo-cierre-agosto-2026-09-17.json`
   (SHA-256 `b87b44a27405a5116fbc9e3ba16a3a6dffdebe80a9d688540755dd3bc38dc393`).
2. Los analistas cargan los contratos de agosto (entran con mes comercial agosto).
3. `02-resellar.sql` — corre `crm.ciclo_cierre_mes()` (mismo camino del reloj) y reactiva
   el job. Si el sellado falla, todo se revierte y el ciclo sigue en pausa.
4. Si algo salió mal: `03-restaurar.sql` deja la foto idéntica a la del 10/09.

**Mientras agosto esté abierto:** ranking y metas de agosto se ven en vivo (no de la foto);
el ciclo diario está en pausa, así que septiembre tampoco se sellará hasta reactivarlo
(su ventana recién abre el 10/10). No olvidar el paso 3.

**Verificado el 17/09 antes de escribir esto:** cero filas en `crm.ajustes_mes_cerrado` y
`crm.inversion_ajustes_mes_cerrado` (nada derivado de la foto); la foto de agosto era
«no medible» (mes parcial). Los candados append-only se apagan solo dentro de la
transacción; la auditoría (`private.log_audit_crm`) registra cada borrado. El paso 1 se
ensayó en producción dentro de un `DO` revertido: respaldo 17 filas, sello 0, foto 0,
ciclo en pausa, agosto sin bloqueo.

Ejecución: `npx supabase db query --linked --file supabase/scripts/reexpresion-agosto-2026/0X-….sql`

# Eliminar contratos con pagos por administrador — preparado

Miguel pidió que Admin pudiera eliminar contratos en el CRM y confirmó:
**también contratos con pagos, conservando una copia de auditoría**.

Implementado y ensayado localmente: botón en ficha, confirmación por número,
servidor con rol activo revalidado, copia privada e inmutable del contrato/pagos
y conservación de los PDF. La copia y el borrado son una transacción. La
instalación del SQL no elimina contratos; solo habilita la nueva operación.

Los contratos vinculados al historial multiempresa y las restricciones de meses
cerrados/renovaciones siguen protegidos. No se alteró la regla de anulación
comercial ni se eliminaron inversiones reales.

**Producción pendiente:** presentar/aprobar SQL `20260915222925`, ensayo remoto,
instalación, Edge y frontend. No afirmar que el botón está activo todavía.
Acta técnica: `CRM-Avance-Corp/supabase/scripts/contratos-eliminar/README.md`.
Banco local propio: `contratos_eliminar_20260915`, dentro de
`supabase_db_avancecorp-f5-bank`; sin nuevos servicios ni costes remotos.

Pruebas locales: 3.617 frontend + 3 casos adicionales, 44 Edge/Storage, cinco
grupos SQL y dos recorridos de eliminación. Un E2E global de conversión de
supervisor falla por el cambio previo en lead-drawer, conservado sin editar.

Relacionadas: [[Inicio]] · [[Ciclo de vida de contratos]] ·
[[Contrato de la sancion de anulacion (ATR-4, 2026-08-31)]] ·
[[RETOMAR-61 - Contrato duplicado e idempotencia del alta (2026-09-05)]]

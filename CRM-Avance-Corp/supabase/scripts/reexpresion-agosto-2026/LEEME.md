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
3. `antes-de-02-marcar-contrato-demo-octubre.sql` — marca por la puerta auditada
   el contrato `2026-01-000000` como demo puro, confirmado por Miguel. Es de
   octubre, no de agosto; deja su historia archivada y retira S/ 5 000 de las
   fuentes reales y de la capa de capital. Los otros ocho contratos atribuidos
   al mismo analista fueron confirmados como reales y no se tocan.
4. `antes-de-02-anular-pruebas-confirmadas.sql` — anula por la puerta auditada la
   conversión de prueba de agosto y la de septiembre que Gerencia identificó.
   Comprueba que no afectan contratos y que las dos conversiones reales de
   agosto del mismo perfil se conservan. No desactiva al analista.
5. `antes-de-02-republicar-metas-agosto.sql` — publica la revisión 15 de la meta
   de agosto: copia las 16 personas y sus 96 detalles de la revisión 14; cambia
   solo el objetivo de capital de prueba de MIGUEL BRICEÑO (S/ 100 000 → 0).
   Conserva su meta de conversión del 15 % y sus conversiones reales. El roster
   actual cambió, así que el editor normal introduciría personas ajenas a esa
   meta histórica.
6. `02-resellar.sql` — exige las correcciones anteriores, corre
   `crm.ciclo_cierre_mes()` (mismo camino del reloj) y reactiva el job. Falla y
   revierte la transacción si el ciclo intenta sellar algo distinto de agosto,
   si la foto no preserva las dos conversiones reales o si el job no se activa.
7. Si algo salió mal: `03-restaurar.sql` deja la foto idéntica a la del 10/09.

**Estado al 05/10/2026 (Lima): completado en producción.** El contrato `000000`
quedó marcado como demo; las dos conversiones de prueba identificadas quedaron
anuladas. La revisión 15 conservó los 16 vendedores y 96 detalles de la meta,
con solo el capital de prueba de S/ 100 000 llevado a cero. Agosto quedó como
único mes sellado, con 17 filas en la foto y revisión 15. Las dos conversiones
reales de Miguel figuran en la foto (numerador 1,15; 115 %), con meta de
conversión de 15 %. Septiembre sigue abierto y el job diario está activo.
Los pasos productivos de arriba ya se ejecutaron; sus guardas impiden repetirlos
sin revisar el estado actual.

Antes de ejecutar cualquier SQL productivo, mostrarlo completo y esperar la
confirmación de Miguel (regla del vault `Inicio.md`). Ejecutar cada archivo en
el orden indicado y verificar el estado después de cada uno.

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

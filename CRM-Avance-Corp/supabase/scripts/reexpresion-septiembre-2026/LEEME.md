# Reexpresión de septiembre 2026 (ventas cargadas tarde)

**Estado (14/10/2026, Lima): SEPTIEMBRE REABIERTO EN PRODUCCIÓN.** Ensayo compuesto
(01 → 02 → deshacer 02 → 03, con ROLLBACK) verde dos veces; luego Miguel ejecutó
`01-reabrir.sql`: foto retirada 21 filas, 144 acreditaciones respaldadas (143 liberadas
del sello, 142 estaban incluidas), Qorilazo S/ 20 000 de Astrid Centenaro devuelto de
13/10 a 15/09 (con meta en septiembre), meses sellados = solo agosto, job 3 en pausa.
Respaldo en `private.respaldo_cierre_septiembre_2026`.
**Pendiente:** que los analistas carguen, la configuración de plazo de Gerencia (con la
que se reevalúa la conversión «fuera de plazo») y volver a sellar + reactivar el job 3.

**Por qué.** El 11/10 a las 09:20 el ciclo automático selló septiembre. Desde entonces
el trigger de altas de contratos rechaza todo contrato con mes comercial septiembre
(«mes comercial sellado»): 0 contratos de septiembre cargados desde el 11/10. Los
analistas se demoraron en cargar sus ventas y Miguel decidió el 14/10 reabrirlo hoy y,
después, dar a Gerencia una configuración de plazo de carga por mes (sin tope, solo
Gerencia).

**Cómo.** Reabrir → cargar → volver a sellar. Mismo camino que
[agosto](../reexpresion-agosto-2026/LEEME.md), con dos piezas nuevas:

- Septiembre ya tenía **acreditaciones de conversión selladas**: se respaldan y
  vuelven a «sin sellar» para que el próximo sello las fije con la foto nueva.
- Se comprueba que la foto de septiembre **no absorbió deudas** de agosto
  (`ajuste_*` = 0) y que no hay deudas nacidas de septiembre: si las hubiera,
  borrar la foto perdería un descuento ya saldado. En ese caso el script se niega.
- Las **ventas en cooperativa de septiembre registradas después del sello** (el sistema
  las imputó al mes de registro y dejó un rastro en `crm.inversion_ajustes_mes_cerrado`,
  que además apunta al sello) vuelven a septiembre: imputación = fecha comercial y se
  retira el rastro, ambos respaldados. El primer ensayo (14/10) se negó justo por esto;
  `00-diagnostico.sql` mostró 1 caso: Qorilazo S/ 20 000 de Astrid Centenaro, fecha
  comercial 15/09, registrado el 13/10, sin deudas. Un registro tardío de contrato u
  otra forma no se adivina: el script se niega.

1. **Ensayo sin escribir** de los tres pasos en una sola transacción que termina en
   `ROLLBACK`: reabrir → (punto de guardado) volver a sellar → deshacer el resellado →
   restaurar. Si devuelve las filas del respaldo (1 sello, N vendedores, M acreditaciones,
   1 huella) sin error, los tres pasaron sus comprobaciones contra los datos reales:
   `{ sed '/^commit;$/d' supabase/scripts/reexpresion-septiembre-2026/01-reabrir.sql; echo 'savepoint antes_de_resellar;'; sed -e '/^begin;$/d' -e '/^commit;$/d' supabase/scripts/reexpresion-septiembre-2026/02-resellar.sql; echo 'rollback to savepoint antes_de_resellar;'; sed -e '/^begin;$/d' -e '/^commit;$/d' supabase/scripts/reexpresion-septiembre-2026/03-restaurar.sql; echo 'select tabla, count(*) as filas from private.respaldo_cierre_septiembre_2026 group by tabla order by tabla;'; echo 'rollback;'; } > /tmp/ensayo-sept.sql && npx supabase db query --linked --file /tmp/ensayo-sept.sql`
2. `01-reabrir.sql` — guarda sello + foto + acreditaciones de septiembre y una **huella**
   de sus datos en `private.respaldo_cierre_septiembre_2026`, retira sello y foto, libera
   las marcas de sello y **pausa** el job 3 (`crm-cierre-mes-diario`); si no, lo volvería
   a sellar a las 09:20 del día siguiente.
3. Los analistas cargan los contratos de septiembre (entran con mes comercial septiembre).
4. Volver a sellar:
   - con la **configuración de plazo de Gerencia** publicada: Gerencia fija la fecha y el
     ciclo se reactiva con [`../plazo-carga-mes/reactivar-ciclo.sql`](../plazo-carga-mes/reactivar-ciclo.sql)
     (solo con ese plazo en el futuro; la configuración no lo reactiva sola); o
   - sin ella: `02-resellar.sql` (corre `crm.ciclo_cierre_mes()` y reactiva el job).
5. Si algo salió mal **justo después de reabrir**: `03-restaurar.sql` deja sello, foto y
   marcas idénticos a los del 11/10. Se niega si septiembre ya se volvió a sellar o si la
   huella cambió (se cargó, corrigió, anuló o retiró algo del mes, o cambió su cartera o
   sus inversiones): restaurar la foto vieja perdería capital o deuda (revisión Codex
   14/10, dos P1). En ese caso la única salida es volver a sellar (paso 4).

**Concurrencia.** 01 y 03 toman primero el candado global y el mensual de
`crm.periodos_cerrados`. Los escritores de dinero toman ese mismo candado mensual
**antes** de leer si el mes está sellado, así que esperan al script y deciden con el
estado ya confirmado: deudas por anulación (`private.registrar_ajuste_si_mes_cerrado`),
inversiones tardías (`crm.inversion_ajustes_mes_cerrado`), altas y correcciones de contratos
y acreditaciones de conversión.

**Revisión.** Codex r1: FAIL con 3 hallazgos (2 P1 de la reversa y 1 P2 del primer uso),
todos aceptados y corregidos. Codex r2: PASS condicionado; se aplicaron sus dos ajustes
(zona horaria fija en 01/03 y comprobación de `ajuste_anulacion_en_sello` en 03).
Auditoría de la devolución de ventas tardías (subagente, 14/10): OK con reservas.
Todo consumidor de dinero lee `cierres_externos.fecha_imputacion` en vivo (capital,
foto, facturación, ficha): los S/ 20 000 salen de octubre y entran una vez en septiembre.
Aceptado y aplicado: candado de que el analista efectivo tenga meta en septiembre (sin
ella la venta dejaría de sumar a su cuota). Queda documentado, sin efecto en dinero:
- `crm.inversion_solicitudes.resultado` (jsonb) conserva `fuente.fecha_imputacion` =
  13/10 y `fuente.ajuste_mes_cerrado` = true; ni el SQL ni el front leen esas claves.
- El borrado del rastro no pasa por `audit_log` (su trigger audita solo altas): queda
  en el respaldo.
- Sin rastro, esa inversión se puede eliminar como cualquier alta a tiempo.
- En la lista diaria de Facturación la operación pasa del 13/10 al 15/09.
- Una anulación concurrente de otra venta en cooperativa puede chocar (deadlock) con
  01: falla entero y se vuelve a correr; no deja nada a medias.

**Mientras septiembre esté abierto:**
- Ranking y metas de septiembre se ven en vivo (no de la foto).
- El aviso de cierre en «Hoy» de Gerencia mostrará septiembre como **atascado**: es
  esperado (el ciclo está en pausa a propósito).
- **Conversión:** el plazo de acreditación sigue fijo en el 10/10 23:59. Las ventas que se
  carguen ahora suman **capital** en septiembre, pero su conversión queda «fuera de plazo»
  hasta que Gerencia amplíe el plazo con la configuración (que vuelve a evaluarlas).
- Octubre no se sella antes del 11/11 de todos modos.

Ejecución: `npx supabase db query --linked --file supabase/scripts/reexpresion-septiembre-2026/0X-….sql`.
Mostrar el SQL completo a Miguel y esperar su confirmación antes de cada paso productivo.

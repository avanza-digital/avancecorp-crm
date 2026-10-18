---
tags: [crm, cierre-mes, produccion, decision]
fecha: 2026-10-14
estado: resuelto — plazo de septiembre hasta el 21/10/2026 fijado por Gerencia y ciclo diario reactivado (se sella solo el 22/10 09:20)
---

# Cierre de mes — septiembre reabierto para ventas tardías (14/10/2026)

**Qué pasó.** El ciclo automático selló septiembre el 11/10 a las 09:20 Lima. Los
analistas se demoraron en cargar sus ventas y desde el sello el servidor rechaza todo
contrato con mes comercial septiembre (0 cargados desde el 11/10). Miguel decidió:
reabrir septiembre **hoy** con un script y, después, una **configuración de plazo de
carga por mes que decide Gerencia** (sin tope, solo Gerencia).

**Hecho en producción (14/10, por `!` de Miguel).** `CRM-Avance-Corp/supabase/scripts/reexpresion-septiembre-2026/01-reabrir.sql`,
precedido de un ensayo compuesto con ROLLBACK (reabrir → volver a sellar → deshacer →
restaurar) verde dos veces. Resultado: foto de 21 vendedores retirada, 144 acreditaciones
de conversión respaldadas y 143 liberadas del sello, meses sellados = solo agosto, ciclo
diario (job 3) **en pausa**. Respaldo íntegro en `private.respaldo_cierre_septiembre_2026`.

**La venta que bloqueaba.** El primer ensayo se negó: una venta en **cooperativa**
registrada después del sello no se rechaza, se **imputa al mes de registro** y deja un
rastro en `crm.inversion_ajustes_mes_cerrado` (con FK al sello). Caso único: Qorilazo
S/ 20 000 de Astrid Centenaro, fecha comercial 15/09, registrada 13/10. El script la
devolvió a septiembre (imputación = fecha comercial, rastro retirado, ambos respaldados),
con candado de que su analista tenga meta en septiembre (si no, dejaría de sumar a su cuota).

**Lecciones.**
- Un mes sellado no solo **rechaza** contratos: las ventas en cooperativa entran igual y
  se mueven de mes en silencio. «0 contratos cargados» no significa «0 ventas tardías».
- Reabrir solo es seguro si la foto **no absorbió deudas** de otro mes y no hay deudas
  **nacidas** del mes: borrar la foto perdería un descuento ya saldado o lo duplicaría.
- La reversa de una reapertura solo vale mientras **nada** cambió en el mes: se guarda una
  huella del mes reabierto y la reversa se niega si difiere (hallazgos P1 de Codex r1).
- Todos los escritores de dinero toman el candado mensual de `crm.periodos_cerrados`
  **antes** de mirar el sello: por eso un script que toma el mismo candado no se cruza.
- `db query --linked`: una referencia estática a una tabla que aún no existe falla al
  planificar (42P01) aunque esté detrás de `to_regclass(...) is not null and …`.

**Mientras septiembre esté abierto.** Ranking y metas de septiembre en vivo; Gerencia ve
el aviso «atascado» (esperado: ciclo en pausa); lo cargado ahora suma capital en
septiembre pero su **conversión** queda «fuera de plazo» (plazo fijo 10/10 23:59) hasta
que exista la configuración de plazo de Gerencia, que debe **reevaluarla explícitamente**
(el escritor devuelve la fila tal cual si la fuente no cambia).

**Resuelto (15/10).** La configuración de plazo ([[Cierre de mes - plazo de carga por mes decidido por Gerencia (2026-10-14)]])
se aplicó y publicó (tarjeta en Configuración). Gerencia fijó el último día de septiembre en el **21/10/2026** (el
primer intento quedó en 2926 por un error de tipeo y se corrigió con otra decisión: vale la última) y se reactivó el
job 3: el ciclo sella septiembre solo el 22/10 a las 09:20 y luego octubre en su fecha. `02-resellar.sql` y
`03-restaurar.sql` quedan superados.

Relacionado: [[Cierre de mes]] · [[Periodo comercial de contratos]] ·
[[Conversion - fecha comercial y plazo de registro (propuesta 2026-09-26)]] ·
[[Baja de analista - su capital pasa al responsable actual (2026-10-09)]]

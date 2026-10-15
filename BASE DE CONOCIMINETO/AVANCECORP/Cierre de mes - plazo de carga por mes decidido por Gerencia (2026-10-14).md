---
tags: [crm, cierre-mes, conversion, decision]
fecha: 2026-10-14
estado: en producción (servidor 15/10 ~10:40; tarjeta en Configuración 15/10 12:28); septiembre fijado al 21/10 y ciclo reactivado
---

# Cierre de mes — plazo de carga por mes decidido por Gerencia (14/10/2026)

**Qué es.** En **Configuración** (solo Gerencia; desde el 15/10 por pedido de Miguel, antes estuvo unas horas en Hoy), la tarjeta «Plazo de carga» deja fijar el **último día** en que se
pueden cargar las ventas de un mes y acreditarse su conversión. Sin decisión, el plazo es el de
siempre: el día 10 del mes siguiente (cierra a las 00:00 del 11, hora de Lima). Pedido de Miguel
tras reabrir septiembre ([[Cierre de mes - septiembre reabierto para ventas tardias (2026-10-14)]]):
**solo Gerencia** decide, **sin tope** de fecha, y la misma acción **reabre** un mes ya sellado.

**Reglas** (migración `20261015000852_crm_plazo_carga_mes.sql`, puertas
`crm.fijar_plazo_carga_mes` y `crm.plazos_carga_mes_fn`):
- El último día no puede ser anterior a hoy ni al día 10 del mes siguiente; motivo de 5 a 300
  caracteres; vale la última decisión (se puede ampliar o acortar mientras el mes esté abierto).
- **Solo meses con metas publicadas.** El ciclo diario solo sella meses con metas: un plazo en un mes
  sin metas quedaría sin sello posible en cuanto se sellara el siguiente (Codex r2).
- **Reabrir:** solo el mes anterior al mes en curso, si es el último sellado, tiene foto, no tiene
  deudas nacidas de él ni absorbidas por su foto, y sus ventas en cooperativa registradas tarde se
  pueden devolver (su analista tiene meta en ese mes). Hace lo mismo que el guion de septiembre, con
  respaldo en `crm.reaperturas_mes`. Esta restricción la propuso Claude y se le informó a Miguel.
- Al fijar el plazo, las conversiones del mes «fuera de plazo» o «mes sellado» se **reevalúan** con el
  plazo nuevo (misma decisión, exclusiones y regla de identidad que el escritor; si la persona ya
  tiene otra captación acreditada, la fila se deja y se cuenta como conflicto).
- El ciclo y `crm.cerrar_periodo` respetan el plazo; si un mes se amplía, **los meses siguientes
  esperan** (se sella en orden). Reabrir no pausa el ciclo: con el plazo en el futuro no vuelve a sellar.

**Lecciones.**
- Si una regla fija pasa a depender de una decisión, lo que era IMMUTABLE pasa a STABLE y hay que
  revisar todo lo que exigía igualdad con ella (aquí, el CHECK de `conversion_acreditaciones`: ahora
  la fila guarda el plazo con el que se decidió y solo se exige que no sea menor que la base).
- **Lo que se mira antes de esperar un candado no vale después.** `crm.cerrar_periodo` miraba el plazo
  antes de tomar los candados: si Gerencia ampliaba mientras el sello esperaba, el mes se sellaba igual.
  Ahora lo vuelve a mirar con los candados tomados (Codex r1, P1; probado con dos sesiones a la vez).
- Abrir un candado para una operación: mejor una fila de autorización atada al mes y a la transacción
  (id + instante, fijados por trigger) que `ALTER TABLE … DISABLE TRIGGER` o una variable de sesión.
  Vale para toda la transacción superior, incluidas sus subtransacciones.
- Una configuración por mes tiene que limitarse a los meses que el ciclo de verdad recorre.

**Verificación (14–15/10, banco local con el esquema de producción y Formulario 3).** 186 casos,
62/62 mutantes, 14/14 con dos sesiones a la vez, 9/9 del ensayo tal como se manda a producción,
42 contra Auth y la API reales, oráculo del cierre 22/22, reversa al byte. Front: 6800 pruebas y
39/39 E2E en Docker. Codex: r1 FAIL (1 P1, 2 P2, 3 P3) y r2 FAIL (1 P2), todo corregido.

**Aplicada (15/10, ~10:40 Lima).** El primer ensayo (01:15) se negó sin escribir: `crm.cerrar_periodo` está declarada
en el censo analítico y el banco de solo esquema no tenía esa fila. Se corrigió re-sellando su huella (PR #287) y se
probó con los registros REALES de producción sembrados en el banco. Segundo ensayo «ENSAYO OK» → aplicar → registrar →
verificar «APLICADA Y REGISTRADA». Lección: antes de tocar una función existente, sembrar en el banco los registros de
los controles de producción (`leer-registros-produccion.sql`).

**Primer uso (15/10).** Gerencia guardó por error el año **2926** («hasta el 20 oct.»: la tarjeta no muestra el año)
y la reactivación del ciclo lo delató (`plazo_septiembre_lima: 2926-10-21`). Se corrigió desde la misma tarjeta con una
decisión nueva (21/10/2026). Lección: sin tope de fecha, la pantalla debe mostrar el año y pedir confirmación ante una
fecha lejana; y un guion que reactiva un proceso debe enseñar el valor que va a usar.

**Cómo se aplica.** Pasos con `!` en `CRM-Avance-Corp/supabase/scripts/plazo-carga-mes/LEEME.md`:
ensayo con ROLLBACK → aplicar → registrar → verificar → publicar el front → Gerencia fija septiembre →
`reactivar-ciclo.sql` (job 3, solo con el plazo en el futuro).

Relacionado: [[Cierre de mes]] · [[Cierre de mes - septiembre reabierto para ventas tardias (2026-10-14)]] ·
[[Conversion - fecha comercial y plazo de registro (propuesta 2026-09-26)]]

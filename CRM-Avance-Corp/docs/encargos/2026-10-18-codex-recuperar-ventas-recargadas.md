ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo (LEVEL 3, datos de producción + funciones de la métrica): REFUTA la migración «recuperar cinco ventas recargadas» (20261018032400, v2)

Contexto de negocio (decisión de Miguel, Gerencia, 17/10/2026). En el CRM de Avance Corp, cinco ventas de leads dejaron de
contar en la conversión mensual de su analista porque alguien BORRÓ el contrato y lo volvió a cargar: la acreditación de la
venta (crm.conversion_acreditaciones) quedó apuntando al contrato borrado y la métrica la descarta («fuente_retirada»). Dos
de ellas además quedaron ANULADAS al borrar con «Eliminar inversión» (fila en crm.cierres_avance_anulados + copia en
crm.inversiones_eliminadas con conversion_anulada). Miguel decidió: «esas ventas precisas hay que arreglar», «ármalo con los
cinco». Es una EXCEPCIÓN autorizada, por fila exacta, a la regla «una anulación es de un solo sentido». Hoy «Reemplazar
inversión» (20261017162053, en producción) evita que vuelva a pasar; esta migración corrige lo que ya pasó. Se aplica con
`supabase db query --linked --file` como postgres, sin sesión de usuario, ANTES del 22/10/2026 00:00 Lima (plazo de carga de
septiembre: el caso 5 es de septiembre).

Tu trabajo: REFUTAR. Busca cómo esta migración puede (a) dejar producción a medias o inconsistente, (b) des-anular o mover
una venta que NO sea una de las cinco, (c) abortar en producción por una condición que el banco no reproduce, (d) tener
defensas que las pruebas no prueban. No repitas lo que ya está probado salvo para refutarlo con evidencia. Formato: VERDICT,
SUMMARY, FINDINGS P0–P3 (archivo/línea + escenario concreto), RISKS, TEST GAPS, NEXT ACTIONS, CONFIDENCE.

## Lo que ya se hizo (evidencia, no promesas)
- v1 pasó por el auditor RLS del proyecto (informe COMPLETO transcrito abajo): P1 (otras lecturas de la anulación), P2-1,
  P2-2 (candados), P2-3 (ledger/pruebas) y 12 P3. La v2 (texto abajo) parcha por ancla CUATRO funciones (cierre_anulado,
  cierres_estado_fn, altas_nuevas_por_analista_fn, anular_cierre_avance), bloquea filas con FOR UPDATE NOWAIT en el preflight,
  toma try-locks de los meses en orden, valida la fila nueva con un trigger BEFORE INSERT, deja una nota en crm.actividades y
  amplía el postflight. Pendiente de v2: la fila en «excepciones a public» del ledger y el bloque de test-rls (los hago ahora).
- Banco Docker con el esquema de producción (misma huella de las funciones de la métrica, verificada el 17/10). Batería
  `probar.sh` (UNA transacción, ROLLBACK): **PASS 56 bloques**: siembra de los 5 casos con las puertas reales + control F
  (anulada, recargada y re-enlazada por la vía normal: debe seguir anulada); 34 rechazos del preflight; 2 aplicaciones que
  deben pasar; 12 inyecciones «durante» la migración que el postflight detecta; D1–D8 después (misma venta al contrato vivo,
  fechas corregidas, capital mudado de mes, tabla inmutable sin API, otras anulaciones siguen contando, chip/«Altas
  nuevas»/«Anular» con la rehabilitación, trigger de validación, notas, no se aplica dos veces).
- Mutantes del TEXTO de la migración (`mutantes.py`): **49/49 muertos**; los 4 de las funciones parchadas van con las huellas
  del postflight RECALCULADAS para el texto mutado, así solo las pruebas D6 pueden matarlos (y los matan).
- Hallazgos del banco que la v2 destapó y están resueltos en el ARNÉS (no en la migración): el trigger
  private.trg_gestion_lead_serializada de crm.actividades exige creado_por = auth.uid(); con auth.uid() NULO (como corre
  `db query --linked`) deja pasar. El arnés aplica sin sesión.

## Preguntas concretas (responde cada una con evidencia o «no refutable con lo dado»)
1. Tope de referidos. Los casos 1 (Astrid) y 2 (Nayra) son leads referidos. private.conversion_episodios aplica
   `least(aporte, total_referidos * tope_pct/100 - aporte_anterior_referidos)` por analista y mes (texto abajo). ¿Puede el
   postflight abortar en producción porque (a) la venta recuperada quede con aporte 0 por el tope, o (b) cambie el aporte de
   OTRO referido del mismo analista (la comparación EXCEPT ALL de «nada más cambió» incluye aporte_numerador)? El banco no
   lo reproduce (siembra sin otros referidos). ¿Qué consulta de solo lectura en producción descarta el riesgo antes de aplicar?
2. Concurrencia real: READ COMMITTED, candado global de periodos + SHARE sobre periodos_cerrados y capital_mes_sellos +
   try-lock de los dos meses + FOR UPDATE NOWAIT de lead/acreditación/contrato. ¿Qué operación de la app en marcha podría
   dejar la migración abortada a medias o, peor, pasar entre el preflight y el paso 3? ¿Deadlock posible con
   private.conversion_acreditar_fuente (que toma sus propios candados por mes)?
3. Por fila exacta: ¿hay algún camino por el que las cuatro funciones parchadas exoneren una anulación que NO sea la de la
   fila registrada (otra copia del mismo lead, cooperativa, una anulación futura del mismo lead tras la rehabilitación)?
4. Las fechas comerciales de 2 y 5 cambian (válvula crm.correccion_periodo_comercial, fuente correccion_manual, revaloriza
   el capital con private.materializar_capital_valoraciones_para). ¿Qué más depende de fecha_cierre_comercial en
   public.contratos (cronograma, rentabilidad, sellos de capital, informes) y no se tocó?
5. Reversa: ¿promete algo que no cumple? ¿Deja algo peor que antes?
6. ¿Qué defensa de la migración NO está probada por la batería ni por un mutante? ¿Qué mutante está mal diseñado (muere
   por la razón equivocada)?

## Archivos (transcritos íntegros; no tienes base ni red)
(Los archivos transcritos están en el repo: la migración, el kit y el informe del auditor en la sesión.)

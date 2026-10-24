# Resolución del PRIMARY

La revisión de Claude devolvió `CHANGES_REQUESTED`; no es una aprobación automática. Las comprobaciones
ampliadas terminaron con 26 aserciones PASS en el banco local y en la rama Supabase autorizada.

- **P2, cierre con corte a fin de mes: aceptado.** El test ahora publica `corte=2026-10-31` con solo dos PEN
  y USD pendiente, simulando 12/11 únicamente dentro del savepoint. `crm.cerrar_periodo` sigue rechazando
  con PT409 y no deja sello. [El núcleo del sello](sello-sin-cambios.sql) cuenta `valoracion_id is null`
  antes y después del bloqueo de fuentes; la fecha de corte no sustituye esas comprobaciones.
- **P2, diff del publicador ausente en el paquete: aceptado.** Se adjunta [el diff de cuerpos](publicador.diff),
  extraído del esquema base y validado contra el MD5 del preflight. Cambian el cálculo/retroceso de corte,
  el filtro de valoraciones y el aborto por cobertura incompleta. Identidad de personas, campos, orden de
  agregados, huella, locks y persistencia permanecen iguales. No se consultó producción para esta evidencia.
- **P2, constructor de cobertura sellada: no se cambia por una lectura viva.** El patrón es el mismo de
  `cumplimiento_metas_v2_fn` y `facturacion_diaria_v2_fn` en `20261016204221_crm_capital_cortes_lecturas.sql:343`
  y `:424`: un sello conserva cobertura completa sin consultar fuentes actuales. Se añadió comparación
  de todo el objeto con el lector nativo de metas, excepto `generado_en`, metadata opcional admitida por
  `CoberturaCapitalSchema`. PASS. La hipótesis de divergencia futura del contrato no demuestra un defecto actual.
- **P3, pendientes incluidos en por incorporar: aceptado como cobertura de regresión.** Dos pruebas nuevas
  verifican 3 por incorporar / 1 pendiente y un PEN sin fecha acreditada junto a USD sin TC. Cada motivo
  conserva su texto y solo se anuncia como falta de TC el monto USD correspondiente.
- **P3, analista sin meta ni producción valorada: comportamiento conservado y probado.** Su aviso aparece
  en cumplimiento; v2 mantiene el rechazo 42501 de v1 para el detalle fuera de `personas`. No hay botón de
  ranking para ese caso ni ampliación de autoridad. Se añadió aserción expresa.
- **P3, nueva fecha de corte: documentado.** La fecha forma parte de la huella existente. El ID es estable
  entre corridas con igual fecha/contenido; el avance del día puede publicar una nueva revisión.
- **Gap, consulta de revisión anterior después del TC: cubierto.** Mantiene sus S/ 6.000, pendientes cero
  y una operación ya valorada por incorporar. No mezcla la revisión anterior con los S/ 74.000 nuevos.

Los hallazgos no exigieron cambiar la candidata SQL ya aplicada ni la lógica de producción después del review.
Se reforzaron pruebas y evidencia. El PRIMARY conserva la responsabilidad por la decisión de entrega.

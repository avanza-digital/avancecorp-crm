# Materialización inmediata: evidencia y siguiente integración

Estado: candidata local `20261016223745_crm_capital_valoracion_en_escritores.sql`
implementada y verificada. Sin publicar ni activar. Comparte el algoritmo del
worker con los escritores y conserva los gates nativos.

## Puertas observadas

- Portal: `public_html/js/admin/contratos.js:1436` llama
  `crm.crear_contrato_con_cuenta_pdf_v2`. Esta mantiene idempotencia y PDF y
  baja por `crm.crear_contrato_con_cuenta` a `public.crear_contrato`.
- El trigger público **ya existente** llama `private.f4_contrato_vincular`,
  que llama `private.inversion_vincular_fuente(uuid,uuid,uuid,uuid,boolean)`.
  No hace falta crear/modificar un trigger en public para seguir esa ruta.
- El final de `crm.crear_contrato_con_cuenta` también materializa la operación:
  el alta CRM conserva la garantía incluso con identidad unificada suspendida.
  Si el vínculo ya materializó en esa transacción, la llamada es idempotente.
- La confirmación de inversión del CRM y la conversión externa también usan
  `private.inversion_vincular_fuente`; este valida identidad/fuente/empresa,
  inserta o reutiliza la inversión y asegura su titular principal.
- `crm.corregir_fecha_cierre_comercial(uuid,date,text)` escribe la fecha del
  contrato, protege meses sellados y registra motivo/auditoría. Responsabilidad
  y categoría no cambian la firma monetaria de la valoración.
- Las cooperativas viven en `crm.cierres_externos`; sus cambios de monto,
  moneda, fecha comercial e imputación requieren materialización. La anulación
  conserva capital según ATR-4, por lo que no se inventa una revisión monetaria.

Evidencia reproducible adicional: en el dump local de esquema los cuerpos
están en `private.f4_contrato_vincular`, `private.inversion_vincular_fuente`,
`crm.crear_contrato_con_cuenta`, `crm.crear_contrato_con_cuenta_pdf_v2` y
`crm.corregir_fecha_cierre_comercial`. No versionar el dump completo.

## Contrato mantenido

- Compartir el cálculo, firmas y bloqueo/relectura del materializador probado;
  no copiar otro algoritmo de valoración para los escritores.
- La llamada de una operación debe acotar fuente/id y no reconciliar toda la
  cartera en cada alta. Con PEN o tasa existente, crear la revisión en la misma
  transacción; sin tasa, guardar la venta y su trabajo persistente.
- Mantener la política desactivada y no añadir permisos de escritura del
  navegador sobre tasas/valoraciones. Las funciones internas van revocadas.
- Conservar los gates de identidad, idempotencia, cuentas/PDF y conversión;
  ensayar las puertas reales, además de semillas que omiten triggers.
- No alterar tablas, funciones ni triggers de public. Revisar las rutas CRM y
  helpers privados existentes y demostrar que las altas normales las recorren.

## Evidencia ejecutada

El gate SQL incluye 27 aserciones de dominio/legado, 14 de atribución y 62 de
cortes/permisos/escritores. Las semillas usan réplica; después los escritores
corren con triggers normales y se fuerzan las restricciones diferidas. Casos:

- RPC del portal `crm.crear_contrato_con_cuenta_pdf_v2` con rol SQL
  authenticated y Gerencia: contrato, cronograma, cuenta, reserva documental y
  US$ 20 000 × 3,40 = S/ 68 000 antes del retorno. Reintento idempotente.
- Un rechazo PDF por datos legales incompletos revierte contrato, cuotas,
  cuenta y valoración juntos; completar los datos permite el alta sin cambiar
  ni omitir el gate documental.
- Vinculación real de inversión USD, corrección comercial PEN y USD mediante
  su RPC y corrección de monto cooperativo por `crm.corregir_cierre_externo`.
- Sin tasa se confirma la modificación y queda pendiente su nueva revisión;
  la revisión anterior no se presenta como actual. Motivo/auditoría y límites
  de autorización permanecen. Reimputar sin autorización sigue rechazado.
- Una llamada individual no materializa otras fuentes del mismo día. Con
  10 000 fuentes históricas extra: 3,67–4,52 ms en los ensayos locales; es una
  medición, no una garantía de latencia productiva.
- Mil ventas USD sin tasa no bloquean PEN conocido y se descubren sus cinco
  fechas aun con lote de una sola materialización.

Cuatro escenarios de concurrencia usan sesiones PostgreSQL reales y clones
propios eliminados al terminar: fuente en edición/worker, dos workers, cierre
que gana a la corrección y corrección que gana al cierre. En los dos últimos
se verifica la espera real mediante `pg_stat_activity` y `pg_blocking_pids`.

El corrector nativo tomaba primero la fila y después los candados mensuales.
Ahora comparte el cerrojo global del cierre antes de bloquear la fuente.
Si gana el cierre, el corrector rechaza reescribir el mes; si gana la corrección,
el sello usa su revisión nueva después del commit. El riesgo de espera circular
del diseño anterior no se reporta como un defecto reproducido: el ensayo prueba
el orden y los resultados de la candidata.

La evidencia anterior fue SQL con F4 suspendida. El gate HTTP posterior ya
ejecutó GoTrue/PostgREST, once cuentas/ocho ámbitos y F4 activa por sus RPC
preparar/revisar/confirmar, con 68 000 inmediatos y 99 000 tras recuperación.
No acredita un navegador F4 con Auth real ni render/subida de PDF. La reserva
y el rollback documental nativos sí se probaron. Ver ESTADO.md.

## Reevaluación ya integrada (candidata local)

La candidata `20261016230914_crm_capital_reevaluar_cierre.sql` comprueba el
estado real del cron, omitiendo si está pausado o ausente. La lectura productiva
al pausar mostró job 3 activo; no se cambió su estado. La reconciliación no autoriza a
reactivar cierres ni a cerrar septiembre.

Se hace mediante una RPC de servicio separada, después de que la RPC de
reconciliación confirme su transacción. No llamar al ciclo dentro del mismo
materializador: este conserva locks de fuentes por operación y el cierre toma
el cerrojo global antes de SHARE de tablas. Mantener esa separación evita
introducir el orden inverso de locks al pedir el reintento. La Edge debe
conservar éxito de materialización aunque falle esa solicitud; el ciclo normal
sigue siendo la recuperación y un cron pausado debe producir omisión explícita.

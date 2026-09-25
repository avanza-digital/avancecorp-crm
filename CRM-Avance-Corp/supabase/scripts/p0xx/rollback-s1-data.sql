-- Reversa de DATOS de P-0XX/S1. Ejecutar solo en una rama y despues de
-- verificar que no hubo pagos nuevos desde la vinculacion automatica.
-- Las funciones se revierten con una migracion de codigo separada si se
-- abandona S1; este guion no devuelve las columnas legacy como fuente viva.
begin;
set local lock_timeout = '10s';

-- El alta de contrato puede escribir la cuenta, luego el cronograma y por
-- ultimo el vinculo. Tomar los candados en ese orden evita que una alta o un
-- pago se confirmen entre las comprobaciones y los DELETE. Si hay actividad
-- concurrente, lock_timeout cancela toda la reversa sin borrados parciales.
lock table crm.cuentas_bancarias in share mode;
lock table public.cronograma_pagos in share mode;
lock table crm.contrato_cuentas_pago in share mode;

do $revertir$
declare
  v_vinculos bigint;
  v_cuentas bigint;
begin
  if exists (
    select 1
    from private.backfill_cuentas_p0xx b
    join crm.contrato_cuentas_pago cp on cp.id = b.fila_id
    join public.cronograma_pagos cr on cr.contrato_id = cp.contrato_id
    where b.tipo = 'vinculo' and b.revertida_en is null
      -- El dia efectivo puede cargarse hacia atras: sin timestamp confiable
      -- del asiento, cualquier pago requiere revision manual antes de borrar.
      and (cr.estado = 'pagado' or cr.fecha_pago_real is not null
           or coalesce(cr.monto_pagado, 0) > 0)
  ) then
    raise exception using errcode = 'P0001',
      message = 'Hay pagos desde el backfill; la reversa requiere conciliacion manual';
  end if;

  if exists (
    select 1
    from private.backfill_cuentas_p0xx b
    join crm.contrato_cuentas_pago cp on cp.cuenta_bancaria_id = b.fila_id
    where b.tipo = 'cuenta' and b.revertida_en is null
      and not exists (
        select 1 from private.backfill_cuentas_p0xx bv
        where bv.tipo = 'vinculo' and bv.fila_id = cp.id
          and bv.revertida_en is null)
  ) then
    raise exception using errcode = 'P0001',
      message = 'Una cuenta migrada fue reutilizada; la reversa requiere conciliacion manual';
  end if;

  delete from crm.contrato_cuentas_pago cp
  using private.backfill_cuentas_p0xx b
  where b.tipo = 'vinculo' and b.revertida_en is null and cp.id = b.fila_id;
  get diagnostics v_vinculos = row_count;

  delete from crm.cuentas_bancarias cb
  using private.backfill_cuentas_p0xx b
  where b.tipo = 'cuenta' and b.revertida_en is null and cb.id = b.fila_id;
  get diagnostics v_cuentas = row_count;

  update private.backfill_cuentas_p0xx
  set revertida_en = pg_catalog.now()
  where revertida_en is null;
  delete from private.conciliacion_cuentas_p0xx;

  raise notice 'Reversa P-0XX/S1: % vinculos y % cuentas borrados',
    v_vinculos, v_cuentas;
end;
$revertir$;
commit;

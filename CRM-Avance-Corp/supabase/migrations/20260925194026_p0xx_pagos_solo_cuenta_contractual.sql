-- P-0XX S3: una cuota solo se registra como pagada si el contrato conserva
-- una instruccion de pago coherente. Protege tanto la interfaz como escrituras
-- directas a cronograma_pagos con los permisos existentes.

create or replace function private.exigir_cuenta_pago_cronograma()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.estado is distinct from 'pagado' then
    return new;
  end if;

  -- La cuenta vinculada puede haber sido versionada y estar inactiva: sigue
  -- siendo la instruccion contractual. Bloqueamos la fila del vinculo y del
  -- contrato hasta el COMMIT para no validar una fotografia que se borra o
  -- cambia de cliente/moneda durante el registro del pago.
  perform 1
  from crm.contrato_cuentas_pago cp
  join public.contratos ct on ct.id = cp.contrato_id
  join crm.cuentas_bancarias cb on cb.id = cp.cuenta_bancaria_id
  where cp.contrato_id = new.contrato_id
    and cb.cliente_id = ct.cliente_id
    and cb.moneda = ct.moneda
  for share of cp, ct;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'Sin cuenta de pago — requiere conciliación';
  end if;
  return new;
end;
$function$;

revoke all on function private.exigir_cuenta_pago_cronograma()
  from public, anon, authenticated;

drop trigger if exists trg_cronograma_pagos_10_exigir_cuenta_pago_insert
  on public.cronograma_pagos;
create trigger trg_cronograma_pagos_10_exigir_cuenta_pago_insert
before insert on public.cronograma_pagos
for each row when (new.estado = 'pagado')
execute function private.exigir_cuenta_pago_cronograma();

drop trigger if exists trg_cronograma_pagos_10_exigir_cuenta_pago_update
  on public.cronograma_pagos;
create trigger trg_cronograma_pagos_10_exigir_cuenta_pago_update
before update of estado on public.cronograma_pagos
for each row when (old.estado is distinct from 'pagado' and new.estado = 'pagado')
execute function private.exigir_cuenta_pago_cronograma();

-- Ejecutar solo en la rama P-0XX con la semilla ficticia S1.
-- El bloque externo revierte sus propias filas aun si todas las pruebas pasan.
do $verify$
declare
  v_vinculado uuid := 'd0000000-0000-4000-8000-000000000001';
  v_sin_vinculo uuid := 'd0000000-0000-4000-8000-000000000003';
  v_cuota_sin uuid;
  v_cuota_con uuid;
  v_bloqueado boolean;
begin
  if not exists (select 1 from crm.contrato_cuentas_pago where contrato_id = v_vinculado)
     or exists (select 1 from crm.contrato_cuentas_pago where contrato_id = v_sin_vinculo) then
    raise exception 'La semilla S1 de contratos vinculados/sin vinculo no coincide';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.cronograma_pagos'::regclass
      and tgname = 'trg_cronograma_pagos_10_exigir_cuenta_pago_insert'
      and tgenabled = 'O'
  ) or not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.cronograma_pagos'::regclass
      and tgname = 'trg_cronograma_pagos_10_exigir_cuenta_pago_update'
      and tgenabled = 'O'
  ) then
    raise exception 'No estan activos ambos triggers de cuenta de pago';
  end if;

  begin
    insert into public.cronograma_pagos
      (contrato_id, numero_cuota, fecha_programada, monto_programado, estado)
    values (v_sin_vinculo, 1,
            (now() at time zone 'America/Lima')::date, 100, 'pendiente')
    returning id into v_cuota_sin;

    v_bloqueado := false;
    begin
      update public.cronograma_pagos
         set estado = 'pagado', monto_pagado = 100,
             fecha_pago_real = (now() at time zone 'America/Lima')::date
       where id = v_cuota_sin;
    exception when check_violation then
      if sqlerrm <> 'Sin cuenta de pago — requiere conciliación' then raise; end if;
      v_bloqueado := true;
    end;
    if not v_bloqueado then
      raise exception 'Un contrato sin vinculo pudo marcar una cuota pagada';
    end if;

    v_bloqueado := false;
    begin
      insert into public.cronograma_pagos
        (contrato_id, numero_cuota, fecha_programada, monto_programado,
         estado, monto_pagado, fecha_pago_real)
      values (v_sin_vinculo, 2,
              (now() at time zone 'America/Lima')::date, 100,
              'pagado', 100, (now() at time zone 'America/Lima')::date);
    exception when check_violation then
      if sqlerrm <> 'Sin cuenta de pago — requiere conciliación' then raise; end if;
      v_bloqueado := true;
    end;
    if not v_bloqueado then
      raise exception 'Un contrato sin vinculo pudo insertar una cuota pagada';
    end if;

    insert into public.cronograma_pagos
      (contrato_id, numero_cuota, fecha_programada, monto_programado, estado)
    values (v_vinculado, 1,
            (now() at time zone 'America/Lima')::date, 100, 'pendiente')
    returning id into v_cuota_con;
    update public.cronograma_pagos
       set estado = 'pagado', monto_pagado = 100,
           fecha_pago_real = (now() at time zone 'America/Lima')::date
     where id = v_cuota_con;
    if not exists (select 1 from public.cronograma_pagos
                   where id = v_cuota_con and estado = 'pagado') then
      raise exception 'El contrato vinculado no pudo registrar su pago';
    end if;

    raise exception using errcode = 'P0001', message = 'P0XX_S3_ROLLBACK';
  exception when raise_exception then
    if sqlerrm <> 'P0XX_S3_ROLLBACK' then raise; end if;
  end;
end;
$verify$;

select 'PASS: sin vinculo bloqueado en INSERT/UPDATE; vinculado pagado; prueba revertida' as resultado;

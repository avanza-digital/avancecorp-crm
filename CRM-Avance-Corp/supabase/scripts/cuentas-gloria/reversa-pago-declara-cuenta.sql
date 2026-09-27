-- REVERSA de 20260927024423_crm_pago_declara_cuenta (F5).
-- Repone byte a byte el sello y la lectura de F3 (con los arreglos 20260927020317) y la regla de
-- origen; retira la RPC. Se NIEGA si ya hay sellos 'declarado' (su constancia se perdería) o si las
-- piezas vivas no son las de F5 (huella af5c176fb94a153098da7b10e3c6e9af).
begin;
set local lock_timeout = '5s';
do $pre$
declare v_huella text;
begin
  if to_regprocedure('crm.registrar_pago_con_cuenta(uuid,date,numeric,text)') is null then
    raise exception 'REVERSA: la F5 no está aplicada';
  end if;
  lock table crm.cuotas_cuenta_pagada in access exclusive mode;
  if exists (select 1 from crm.cuotas_cuenta_pagada where origen = 'declarado') then
    raise exception 'REVERSA: ya hay pagos con cuenta declarada; revertir borraría su constancia';
  end if;
  select pg_catalog.md5(pg_catalog.string_agg(p.oid::regprocedure::text || '|' || pg_catalog.md5(p.prosrc)
           || '|' || coalesce(pg_catalog.md5(pg_catalog.obj_description(p.oid, 'pg_proc')), '-'), E'\n'
           order by p.oid::regprocedure::text))
    into v_huella
  from pg_catalog.pg_proc p
  where p.oid in (to_regprocedure('private.sellar_cuenta_cuota_pagada()'),
                  to_regprocedure('crm.registrar_pago_con_cuenta(uuid,date,numeric,text)'),
                  to_regprocedure('private.contratos_cuenta_pago_cliente_autorizado(uuid)'),
                  to_regprocedure('crm.contratos_cuenta_pago_cliente_fn(uuid)'));
  if v_huella is distinct from 'af5c176fb94a153098da7b10e3c6e9af' then
    raise exception 'REVERSA: las piezas vivas no son las de la F5 (huella %); no se toca', v_huella;
  end if;
end $pre$;

drop function crm.registrar_pago_con_cuenta(uuid, date, numeric, text);
CREATE OR REPLACE FUNCTION private.sellar_cuenta_cuota_pagada()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cuenta uuid;
  v_nuevo_pago boolean := tg_op = 'INSERT';
begin
  if not v_nuevo_pago then
    v_nuevo_pago := old.estado is distinct from 'pagado';
  end if;
  -- Corrección de la fecha de una cuota ya pagada: solo se recalcula un sello deducido por la
  -- fecha ('registro'); el inferido no depende de ella.
  if not v_nuevo_pago
     and exists (select 1 from crm.cuotas_cuenta_pagada q
                 where q.cuota_id = new.id and q.origen <> 'registro') then
    return null;
  end if;
  -- La cuenta vigente en la FECHA del pago: si después de esa fecha (día de Lima) hubo un cambio,
  -- la cuenta anterior del primero; si no, la cuenta contractual actual. Así, registrar tarde (o
  -- volver a registrar tras anular) un pago viejo no lo atribuye a la cuenta nueva. Un pago con
  -- fecha del mismo día del cambio va a la cuenta nueva: la fecha no dice la hora del depósito
  -- (la importación del Excel avisa esas filas).
  if new.fecha_pago_real is not null then
    select c.cuenta_anterior_id into v_cuenta
    from crm.contrato_cuenta_pago_cambios c
    where c.contrato_id = new.contrato_id
      and (c.cambiado_en at time zone 'America/Lima')::date > new.fecha_pago_real
    order by c.cambiado_en asc, c.id asc
    limit 1;
  end if;
  if v_cuenta is null then
    select l.cuenta_bancaria_id into v_cuenta
    from crm.contrato_cuentas_pago l
    where l.contrato_id = new.contrato_id;
  end if;
  -- Sin cuenta: el trigger BEFORE de exigencia ya rechazó el pago; nada que sellar.
  if v_cuenta is null then
    return null;
  end if;
  insert into crm.cuotas_cuenta_pagada (cuota_id, contrato_id, cuenta_bancaria_id, origen)
  values (new.id, new.contrato_id, v_cuenta, case when v_nuevo_pago then 'registro' else 'inferido' end)
  on conflict (cuota_id) do update
    set contrato_id = excluded.contrato_id,
        cuenta_bancaria_id = excluded.cuenta_bancaria_id,
        origen = case when v_nuevo_pago then excluded.origen else crm.cuotas_cuenta_pagada.origen end,
        sellada_en = pg_catalog.now();
  return null;
end;
$function$;

drop function crm.contratos_cuenta_pago_cliente_fn(uuid);
drop function private.contratos_cuenta_pago_cliente_autorizado(uuid);
CREATE OR REPLACE FUNCTION private.contratos_cuenta_pago_cliente_autorizado(p_cliente_id uuid)
 RETURNS TABLE(contrato_id uuid, numero_contrato text, moneda text, estado text, cuenta_bancaria_id uuid, banco text, tipo_cuenta text, numero_cuenta text, cci text, cuotas_pendientes bigint, proxima_fecha date, pagadas_por_cuenta jsonb, cuenta_retirada boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not coalesce(private.admin_banca_vigente((select auth.uid())), false) then
    raise exception using errcode = '42501', message = 'Solo administración puede ver las cuentas de pago';
  end if;
  return query
  select ct.id, ct.numero_contrato, ct.moneda, ct.estado,
         l.cuenta_bancaria_id, cb.banco, cb.tipo_cuenta, cb.numero_cuenta, cb.cci,
         (select count(*) from public.cronograma_pagos cp
           where cp.contrato_id = ct.id and cp.estado in ('pendiente', 'vencido')),
         (select min(cp.fecha_programada) from public.cronograma_pagos cp
           where cp.contrato_id = ct.id and cp.estado in ('pendiente', 'vencido')),
         coalesce((
           select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                    'cuenta_bancaria_id', s.cuenta_bancaria_id, 'banco', sb.banco,
                    'numero_cuenta', sb.numero_cuenta, 'cuotas', s.n, 'inferidas', s.inferidas)
                  order by s.n desc)
           from (select q.cuenta_bancaria_id, count(*) as n,
                        count(*) filter (where q.origen = 'inferido') as inferidas
                 from crm.cuotas_cuenta_pagada q
                 join public.cronograma_pagos cp on cp.id = q.cuota_id and cp.estado = 'pagado'
                 where q.contrato_id = ct.id
                 group by q.cuenta_bancaria_id) s
           join crm.cuentas_bancarias sb on sb.id = s.cuenta_bancaria_id), '[]'::jsonb),
         -- La cuenta de pago ya no existe como cuenta vigente: ninguna versión con ese CCI está activa
         -- (p. ej., un contrato que volvió a abrirse al borrar su renovación después de retirar la
         -- cuenta). Una cuenta corregida (versión vieja + versión vigente con el mismo CCI) no cuenta.
         (cb.id is not null and not exists (
            select 1 from crm.cuentas_bancarias v
            where v.cliente_id = cb.cliente_id and v.moneda = cb.moneda
              and v.cci = cb.cci and v.activa is true))
  from public.contratos ct
  left join crm.contrato_cuentas_pago l on l.contrato_id = ct.id
  left join crm.cuentas_bancarias cb on cb.id = l.cuenta_bancaria_id
  where ct.cliente_id = p_cliente_id
    and ct.estado in ('activo', 'vencido')
  order by ct.moneda, ct.numero_contrato;
end;
$function$;
revoke all on function private.contratos_cuenta_pago_cliente_autorizado(uuid) from public, anon, authenticated, service_role;
grant execute on function private.contratos_cuenta_pago_cliente_autorizado(uuid) to authenticated;

CREATE OR REPLACE FUNCTION crm.contratos_cuenta_pago_cliente_fn(p_cliente_id uuid)
 RETURNS TABLE(contrato_id uuid, numero_contrato text, moneda text, estado text, cuenta_bancaria_id uuid, banco text, tipo_cuenta text, numero_cuenta text, cci text, cuotas_pendientes bigint, proxima_fecha date, pagadas_por_cuenta jsonb, cuenta_retirada boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select * from private.contratos_cuenta_pago_cliente_autorizado(p_cliente_id);
$function$;
revoke all on function crm.contratos_cuenta_pago_cliente_fn(uuid) from public, anon, authenticated, service_role;
grant execute on function crm.contratos_cuenta_pago_cliente_fn(uuid) to authenticated;

comment on function private.sellar_cuenta_cuota_pagada() is 'Trigger AFTER en public.cronograma_pagos: al pasar una cuota a pagado sella la cuenta vigente en la fecha del pago; corregir la fecha re-sella lo deducido por fecha. No cambia el registro del pago. SECURITY DEFINER porque quien registra el pago (gestor de cartera) no tiene grants sobre los registros crm.';
comment on function private.contratos_cuenta_pago_cliente_autorizado(uuid) is 'Contratos abiertos del cliente con su cuenta de pago, cuotas pendientes, cuotas pagadas por cuenta (con las inferidas aparte) y cuenta_retirada (la cuenta física de pago ya no tiene versión vigente: hay que cambiarla). Solo admin vigente. SECURITY DEFINER porque authenticated no tiene grants sobre enlace ni sellos. DATOS SENSIBLES.';
comment on function crm.contratos_cuenta_pago_cliente_fn(uuid) is 'Puerta (INVOKER) de los contratos abiertos del cliente con su cuenta de pago y la marca cuenta_retirada. Solo admin.';
alter table crm.cuotas_cuenta_pagada drop constraint cuotas_cuenta_pagada_origen_valido;
alter table crm.cuotas_cuenta_pagada add constraint cuotas_cuenta_pagada_origen_valido
  check (origen in ('registro', 'inferido'));
comment on column crm.cuotas_cuenta_pagada.origen is 'registro = deducida de la fecha del pago al registrarlo; inferido = backfill desde la cuenta contractual.';

do $chk$
begin
  if (select md5(prosrc) from pg_catalog.pg_proc where oid = 'private.sellar_cuenta_cuota_pagada()'::regprocedure) <> 'bdc9ca16b94dbd2ec24e702e8d12651f'
     or (select md5(prosrc) from pg_catalog.pg_proc where oid = 'private.contratos_cuenta_pago_cliente_autorizado(uuid)'::regprocedure) <> 'd4d79c78d117d1458bd5aafa40cff89e'
     or (select md5(prosrc) from pg_catalog.pg_proc where oid = 'crm.contratos_cuenta_pago_cliente_fn(uuid)'::regprocedure) <> '4720e000300e7eda76f9a1f45ecd2c34'
     or to_regprocedure('crm.registrar_pago_con_cuenta(uuid,date,numeric,text)') is not null then
    raise exception 'REVERSA: las piezas repuestas no son las de F3 + arreglos';
  end if;
end $chk$;
notify pgrst, 'reload schema';
commit;

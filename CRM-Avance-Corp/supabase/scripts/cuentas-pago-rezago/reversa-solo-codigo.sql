-- REVERSA SOLO DEL CÓDIGO de 20261001233019_crm_cuentas_pago_motivo_y_rezago.sql. GENERADA por generar-derivados.py.
-- Repone el bloqueo anterior (mensaje único) y quita las tres funciones nuevas. NO toca ningún
-- vínculo: los que creó la carga siguen siendo la cuenta de pago de sus contratos. Es la reversa
-- que sirve cuando ya se registraron pagos con esos vínculos (la completa se niega).
-- Solo Miguel, con autorización expresa. Nunca la ejecuta un revisor.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
declare
  v_huella text;
begin
  -- Se decide con lo que se lee DESPUÉS de tomar los candados: solo vale en READ COMMITTED.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'REVERSA: la transacción debe ir en READ COMMITTED (va en %)',
      pg_catalog.current_setting('transaction_isolation');
  end if;
  select pg_catalog.md5(p.prosrc) into v_huella
  from pg_catalog.pg_proc p
  where p.oid = pg_catalog.to_regprocedure('private.exigir_cuenta_pago_cronograma()');
  -- El de la migración, o el anterior si el código ya se revirtió.
  if v_huella is null or v_huella not in ('d7618dcf85653943e62745513b3c4938', '5efb8619e4342763ae77df2ee0bb1f61') then
    raise exception 'REVERSA: el bloqueo vivo (%) no es el de la migración 20261001233019 ni el anterior; no se toca',
      coalesce(v_huella, 'no existe');
  end if;
  if exists (
    select 1
    from (values
      ('private.cuenta_pago_diagnostico(uuid[])', 'a1dfb0c46b9365df308801bab9d5481a'),
      ('private.cuentas_pago_motivos_autorizado(uuid[])', '4c45dbbfd85f5de82372b343b0b1dfc0'),
      ('crm.cuentas_pago_motivos_fn(uuid[])', '45898bb671a3bf536375a0fb5fb33ec6')
    ) as f(firma, huella)
    join pg_catalog.pg_proc p on p.oid = pg_catalog.to_regprocedure(f.firma)
    where pg_catalog.md5(p.prosrc) <> f.huella
  ) then
    raise exception 'REVERSA: alguna función de la migración cambió después; no se toca';
  end if;
end;
$precondicion$;

-- El bloqueo de antes, byte a byte: texto fuente de 20260925194026 (el postflight lo comprueba por md5).
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
comment on function private.exigir_cuenta_pago_cronograma() is null;

-- Las tres funciones nuevas (la puerta primero). El portal tolera que la puerta no exista: vuelve
-- al texto genérico.
drop function if exists crm.cuentas_pago_motivos_fn(uuid[]);
drop function if exists private.cuentas_pago_motivos_autorizado(uuid[]);
drop function if exists private.cuenta_pago_diagnostico(uuid[]);

do $postflight$
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
      where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure)
     is distinct from '5efb8619e4342763ae77df2ee0bb1f61' then
    raise exception 'REVERSA POSTFLIGHT: el bloqueo no volvió al cuerpo anterior';
  end if;
  if not exists (select 1 from pg_catalog.pg_proc p
                 where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure
                   and p.prosecdef and p.proconfig @> array['search_path=""'])
     or exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure
                  and a.grantee <> p.proowner)
     or (select p.proacl is null from pg_catalog.pg_proc p
         where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure) then
    raise exception 'REVERSA POSTFLIGHT: DEFINER, search_path o EXECUTE del bloqueo no quedaron como antes';
  end if;
  if pg_catalog.to_regprocedure('crm.cuentas_pago_motivos_fn(uuid[])') is not null
     or pg_catalog.to_regprocedure('private.cuentas_pago_motivos_autorizado(uuid[])') is not null
     or pg_catalog.to_regprocedure('private.cuenta_pago_diagnostico(uuid[])') is not null then
    raise exception 'REVERSA POSTFLIGHT: quedó alguna función de la migración';
  end if;
  if (select pg_catalog.count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = 'public.cronograma_pagos'::regclass
        and t.tgname in ('trg_cronograma_pagos_10_exigir_cuenta_pago_insert',
                         'trg_cronograma_pagos_10_exigir_cuenta_pago_update')
        and t.tgfoid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure
        and t.tgenabled = 'O') <> 2 then
    raise exception 'REVERSA POSTFLIGHT: los triggers del bloqueo de pagos no quedaron como estaban';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;

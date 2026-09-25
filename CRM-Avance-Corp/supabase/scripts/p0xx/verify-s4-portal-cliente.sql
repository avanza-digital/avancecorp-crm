-- Solo en la rama con seed-s1-clientes. No imprime cuentas ni CCI completos.
begin;
set local lock_timeout = '5s';

do $test$
begin
  if pg_catalog.has_table_privilege('authenticated',
       'crm.cuentas_bancarias', 'SELECT')
     or pg_catalog.has_function_privilege('anon',
       'public.mis_cuentas_bancarias_fn()', 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated',
       'private.cuentas_cliente_propias_autorizado()', 'EXECUTE') is true then
    raise exception 'S4: permisos bancarios demasiado amplios';
  end if;
end;
$test$;

set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub',
  'c0000000-0000-4000-8000-000000000005', true);

do $test$
begin
  if (select count(*) from public.mis_cuentas_bancarias_fn()) <> 2
     or not exists (
       select 1 from public.mis_cuentas_bancarias_fn()
       where moneda = 'PEN' and banco = 'BCP'
         and numero_cuenta_mascara = '••••6087')
     or not exists (
       select 1 from public.mis_cuentas_bancarias_fn()
       where moneda = 'USD' and banco = 'BCP'
         and numero_cuenta_mascara = '••••9168')
     or exists (
       select 1 from public.mis_cuentas_bancarias_fn()
       where numero_cuenta_mascara !~ '^••••.{4}$'
          or cci_mascara !~ '^••••[0-9]{4}$') then
    raise exception 'S4: el cliente testigo no recibe sus dos cuentas enmascaradas';
  end if;
end;
$test$;

select pg_catalog.set_config('request.jwt.claim.sub',
  'c0000000-0000-4000-8000-000000000004', true);
do $test$
begin
  if exists (select 1 from public.mis_cuentas_bancarias_fn()) then
    raise exception 'S4: un cliente sin cuentas vio las de otro';
  end if;
end;
$test$;

select pg_catalog.set_config('request.jwt.claim.sub',
  'b0000000-0000-4000-8000-000000000004', true);
do $test$
begin
  begin
    perform 1 from public.mis_cuentas_bancarias_fn();
    raise exception 'S4: un miembro CRM pudo usar la lectura del cliente';
  exception when sqlstate '42501' then null;
  end;
end;
$test$;

select 'S4_PORTAL_CLIENTE_OK' as resultado;
rollback;

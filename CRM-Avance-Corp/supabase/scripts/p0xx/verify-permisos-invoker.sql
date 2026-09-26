-- Solo rama hhpjiygytwoayxymziqo. Usa la semilla ficticia P-0XX.
-- Comprueba las fronteras nuevas mediante llamadas reales; revierte todo.
begin;
set local lock_timeout = '5s';

do $acl$
declare
  v record;
begin
  for v in
    select p.oid, n.nspname, p.prosecdef, p.proconfig
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where p.oid in (
      'crm.registrar_cuenta_cliente(uuid,jsonb)'::regprocedure,
      'public.mis_cuentas_bancarias_fn()'::regprocedure,
      'private.registrar_cuenta_cliente_autorizado(uuid,jsonb)'::regprocedure,
      'private.cuentas_cliente_propias_autorizado()'::regprocedure)
  loop
    if v.prosecdef is distinct from (v.nspname = 'private')
       or not coalesce(v.proconfig @> array['search_path=""'], false)
       or pg_catalog.has_function_privilege('anon', v.oid, 'EXECUTE')
       or not pg_catalog.has_function_privilege('authenticated', v.oid, 'EXECUTE') then
      raise exception 'P0XX: frontera de permisos o search_path incorrectos';
    end if;
  end loop;
  if pg_catalog.has_table_privilege('authenticated', 'crm.cuentas_bancarias', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'crm.cuentas_bancarias', 'INSERT')
     or pg_catalog.has_table_privilege('authenticated', 'crm.cuentas_bancarias', 'UPDATE')
     or pg_catalog.has_table_privilege('authenticated', 'crm.cuentas_bancarias', 'DELETE')
     or pg_catalog.has_function_privilege('authenticated',
       'private.cuentas_cliente_vigentes(uuid)', 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated',
       'private.registrar_cuenta_cliente_hecho(uuid,text,jsonb,uuid)', 'EXECUTE') then
    raise exception 'P0XX: tablas o hechos accesibles directamente';
  end if;
end;
$acl$;

set local role anon;
set local request.jwt.claim.sub = 'c0000000-0000-4000-8000-000000000005';
do $anon$
begin
  begin
    perform 1 from public.mis_cuentas_bancarias_fn();
    raise exception 'P0XX: anon accedio a la puerta de lectura';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from private.cuentas_cliente_propias_autorizado();
    raise exception 'P0XX: anon accedio a la autorizacion privada';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.registrar_cuenta_cliente(null, '{}'::jsonb);
    raise exception 'P0XX: anon accedio a la puerta de escritura';
  exception when insufficient_privilege then null;
  end;
end;
$anon$;
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '';
do $sin_identidad$
begin
  begin
    perform 1 from private.cuentas_cliente_propias_autorizado();
    raise exception 'P0XX: lectura privada sin identidad';
  exception when insufficient_privilege then null;
  end;
end;
$sin_identidad$;

set local request.jwt.claim.sub = 'c0000000-0000-4000-8000-000000000005';
do $cliente$
begin
  if (select count(*) from private.cuentas_cliente_propias_autorizado()) <> 2
     or exists (
       select 1 from private.cuentas_cliente_propias_autorizado()
       where numero_cuenta_mascara !~ '^••••.{4}$'
          or cci_mascara !~ '^••••[0-9]{4}$') then
    raise exception 'P0XX: lectura propia o enmascaramiento incorrecto';
  end if;
  begin
    perform 1 from private.cuentas_cliente_vigentes(
      'c0000000-0000-4000-8000-000000000004');
    raise exception 'P0XX: cliente ejecuto un hecho sin autorizacion';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from crm.cuentas_bancarias limit 1;
    raise exception 'P0XX: cliente leyo directamente la tabla';
  exception when insufficient_privilege then null;
  end;
  begin
    perform private.registrar_cuenta_cliente_autorizado(
      'c0000000-0000-4000-8000-000000000005', '{}'::jsonb);
    raise exception 'P0XX: cliente registro una cuenta propia sin permiso';
  exception when insufficient_privilege then null;
  end;
end;
$cliente$;

set local request.jwt.claim.sub = 'b0000000-0000-4000-8000-000000000004';
do $fuera_cartera$
declare
  v_rpc text;
begin
  foreach v_rpc in array array[
    'crm.registrar_cuenta_cliente',
    'private.registrar_cuenta_cliente_autorizado']
  loop
    begin
      execute pg_catalog.format('select %s($1,$2)', v_rpc)
      using 'c0000000-0000-4000-8000-000000000005'::uuid, '{}'::jsonb;
      raise exception 'P0XX: escritura fuera de cartera permitida';
    exception when insufficient_privilege then null;
    end;
  end loop;
end;
$fuera_cartera$;
reset role;

-- Un cliente inactivo no recupera acceso por invocar directamente el guard.
set local request.jwt.claim.sub = 'b0000000-0000-4000-8000-000000000003';
update public.perfiles set activo = false
where id = 'c0000000-0000-4000-8000-000000000005';
do $fixture_inactivo$
begin
  if not exists (select 1 from public.perfiles
      where id = 'c0000000-0000-4000-8000-000000000005' and activo is false) then
    raise exception 'P0XX: no se preparo el cliente inactivo ficticio';
  end if;
end;
$fixture_inactivo$;
set local role authenticated;
set local request.jwt.claim.sub = 'c0000000-0000-4000-8000-000000000005';
do $inactivo$
begin
  begin
    perform 1 from private.cuentas_cliente_propias_autorizado();
    raise exception 'P0XX: cliente inactivo vio cuentas';
  exception when insufficient_privilege then null;
  end;
end;
$inactivo$;
reset role;

update crm.equipo set activo = false
where perfil_id = 'b0000000-0000-4000-8000-000000000003';
set local role authenticated;
set local request.jwt.claim.sub = 'b0000000-0000-4000-8000-000000000003';
do $revocado$
begin
  begin
    perform private.registrar_cuenta_cliente_autorizado(
      'c0000000-0000-4000-8000-000000000004', '{}'::jsonb);
    raise exception 'P0XX: Gerencia revocada pudo escribir';
  exception when insufficient_privilege then null;
  end;
end;
$revocado$;
reset role;

select 'P0XX_PERMISOS_INVOCADOR_OK' as resultado;
rollback;

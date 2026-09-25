-- Oraculo transaccional de la frontera bancaria P-0XX/S2.
-- El trigger legado perfiles_cuentas_no_vaciar permanece instalado, pero la
-- regla nueva impide toda escritura bancaria de clientes en perfiles.
-- Exito = CUENTAS_TX_OK; todo queda en ROLLBACK. Solo ejecutar en una rama.

begin;
set local lock_timeout = '5s';
select pg_catalog.set_config('request.jwt.claims', '', true);
select pg_catalog.set_config('request.jwt.claim.sub', '', true);

do $test$
declare
  v_legado pg_catalog.pg_trigger;
  v_guardia pg_catalog.pg_trigger;
begin
  select t.* into v_legado from pg_catalog.pg_trigger t
  where t.tgrelid = 'public.perfiles'::pg_catalog.regclass
    and t.tgname = 'trg_perfiles_cuentas_no_vaciar' and t.tgenabled = 'O';
  select t.* into v_guardia from pg_catalog.pg_trigger t
  where t.tgrelid = 'public.perfiles'::pg_catalog.regclass
    and t.tgname = 'trg_perfiles_banca_solo_lectura' and t.tgenabled = 'O';
  if v_legado.oid is null or v_guardia.oid is null then
    raise exception 'Falta el trigger legado o la guardia bancaria';
  end if;
  if v_guardia.tgname >= v_legado.tgname then
    raise exception 'La guardia bancaria debe ejecutarse antes del trigger legado';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'public.perfiles_cuentas_no_vaciar()'::pg_catalog.regprocedure
      and not p.prosecdef
      and p.proconfig is not null
  ) or pg_catalog.has_function_privilege('anon',
         'public.perfiles_cuentas_no_vaciar()', 'EXECUTE')
    or pg_catalog.has_function_privilege('authenticated',
         'public.perfiles_cuentas_no_vaciar()', 'EXECUTE') then
    raise exception 'El trigger legado cambio su funcion o ACL';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'private.trg_perfiles_banca_solo_lectura()'::pg_catalog.regprocedure
      and p.prosecdef
      and 'search_path=""' = any(p.proconfig)
  ) then
    raise exception 'La guardia bancaria no tiene SECURITY DEFINER y search_path vacio';
  end if;
end;
$test$;

insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
values
  ('6a000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'cn-cliente@test.invalid', now(), '{}', '{}', now(), now()),
  ('6a000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'cn-intento@test.invalid', now(), '{}', '{}', now(), now()),
  ('6a000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'cn-colab@test.invalid', now(), '{}', '{}', now(), now());

insert into public.perfiles (id, nombre_completo, correo, rol, activo)
values
  ('6a000000-0000-4000-8000-000000000001', 'Oraculo Cliente', 'cn-cliente@test.invalid', 'cliente', true),
  ('6a000000-0000-4000-8000-000000000003', 'Oraculo Colaborador', 'cn-colab@test.invalid', 'comercial', true);

-- Un cliente nace sin banca en perfiles; el alta real usa cuentas_bancarias.
do $test$
begin
  begin
    insert into public.perfiles (id, nombre_completo, correo, rol, activo, banco)
    values ('6a000000-0000-4000-8000-000000000002',
            'Oraculo Alta Bancaria', 'cn-intento@test.invalid', 'cliente', true,
            'BANCO ORACULO');
    raise exception 'Se permitio insertar banca en un perfil cliente';
  exception when sqlstate '22023' then null;
  end;
end;
$test$;

-- Cada columna bancaria, en ambas monedas, debe quedar congelada. El error
-- esperado es el de la guardia, incluso como propietario de la tabla.
do $test$
declare
  v_columna text;
  v_columnas_texto text[] := array[
    'banco', 'tipo_cuenta', 'numero_cuenta', 'cci',
    'beneficiario_nombre', 'beneficiario_dni',
    'banco_usd', 'tipo_cuenta_usd', 'numero_cuenta_usd', 'cci_usd',
    'beneficiario_nombre_usd', 'beneficiario_dni_usd'];
begin
  foreach v_columna in array v_columnas_texto loop
    begin
      execute pg_catalog.format(
        'update public.perfiles set %I = %L where id = %L',
        v_columna, 'VALOR ORACULO', '6a000000-0000-4000-8000-000000000001');
      raise exception 'Se permitio escribir la columna bancaria %', v_columna;
    exception when sqlstate '22023' then null;
    end;
  end loop;
  foreach v_columna in array array['titular_distinto', 'titular_distinto_usd'] loop
    begin
      execute pg_catalog.format(
        'update public.perfiles set %I = true where id = %L',
        v_columna, '6a000000-0000-4000-8000-000000000001');
      raise exception 'Se permitio escribir la columna bancaria %', v_columna;
    exception when sqlstate '22023' then null;
    end;
  end loop;
end;
$test$;

-- Convertir un perfil ajeno con banca legada tampoco debe crear un cliente
-- con datos bancarios fuera del ledger.
do $test$
begin
  update public.perfiles set banco = 'RESIDUO LEGADO'
  where id = '6a000000-0000-4000-8000-000000000003';
  begin
    update public.perfiles set rol = 'cliente'
    where id = '6a000000-0000-4000-8000-000000000003';
    raise exception 'Se permitio convertir en cliente un perfil con banca legada';
  exception when sqlstate '22023' then null;
  end;
end;
$test$;

-- Los datos generales del cliente siguen siendo editables.
do $test$
declare
  v_telefono text;
begin
  update public.perfiles set telefono = '+51999999002'
  where id = '6a000000-0000-4000-8000-000000000001';
  select p.telefono into v_telefono from public.perfiles p
  where p.id = '6a000000-0000-4000-8000-000000000001';
  if v_telefono is distinct from '+51999999002' then
    raise exception 'La edicion no bancaria del perfil no persistio';
  end if;
end;
$test$;

select 'CUENTAS_TX_OK' as resultado;
rollback;

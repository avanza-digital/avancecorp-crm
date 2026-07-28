-- Oraculo transaccional autocontenido del TRIGGER perfiles_cuentas_no_vaciar.
-- Exito = token CUENTAS_TX_OK; todo queda en rollback.
--
-- Decision de Miguel (2026-07-27, textual "si al trigger"): un CLIENTE que ya
-- tiene cuenta bancaria no puede QUEDAR sin ninguna. Complemento del blindaje
-- del alta (edges crear-cliente v24 / crm-convertir-lead v6): alla se garantiza
-- que NACE con cuenta; aqui, que ninguna correccion posterior lo deje sin ella.
--
-- Lo que el trigger NO debe tocar (pedido explicito: "el asesor debe poder
-- editar esto durante esas 5 horas"): editar/cambiar cuentas, quitar UNA moneda
-- si la otra queda viva, el flujo del portal vacio->lleno, y las filas legacy
-- sin cuenta (grandfathering: por eso es trigger de transicion y no CHECK).
--
-- Solo contra un BRANCH de Supabase, nunca contra produccion.

begin;

set local lock_timeout = '5s';

-- Sembrar como sistema (auth.uid() null): los sellos de proteger_campos no aplican.
select set_config('request.jwt.claims', '', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
values
  ('6a000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'cn-cliente@test.invalid', now(), '{}', '{}', now(), now()),
  ('6a000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'cn-legacy@test.invalid', now(), '{}', '{}', now(), now()),
  ('6a000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'cn-colab@test.invalid', now(), '{}', '{}', now(), now());

-- Cliente CON las dos cuentas, cliente legacy SIN cuenta, y un colaborador
-- (rol no-cliente) con residuos bancarios: el trigger solo protege clientes.
insert into public.perfiles (
  id, nombre_completo, correo, rol, activo,
  banco, numero_cuenta, tipo_cuenta, cci,
  banco_usd, numero_cuenta_usd, tipo_cuenta_usd, cci_usd
)
values
  ('6a000000-0000-4000-8000-000000000001', 'Oraculo Cliente Bancado', 'cn-cliente@test.invalid', 'cliente', true,
   'BANCO ORACULO', '19100000000777', 'ahorros', '00219100000000000777',
   'BANCO ORACULO USD', '19100000000778', 'ahorros', '00219100000000000778'),
  ('6a000000-0000-4000-8000-000000000002', 'Oraculo Cliente Legacy', 'cn-legacy@test.invalid', 'cliente', true,
   null, null, null, null, null, null, null, null),
  ('6a000000-0000-4000-8000-000000000003', 'Oraculo Colaborador', 'cn-colab@test.invalid', 'comercial', true,
   'BANCO RESIDUO', '19100000000779', 'ahorros', null,
   null, null, null, null);

-- ── V01: el trigger existe, es BEFORE UPDATE OF y apunta a la funcion ───────
do $test$
declare v_def text;
begin
  select pg_get_triggerdef(t.oid) into v_def
    from pg_trigger t
   where t.tgname = 'trg_perfiles_cuentas_no_vaciar'
     and t.tgrelid = 'public.perfiles'::regclass;
  if v_def is null then
    raise exception 'V01 falta el trigger trg_perfiles_cuentas_no_vaciar';
  end if;
  if v_def !~ 'BEFORE UPDATE OF' or v_def !~ 'perfiles_cuentas_no_vaciar' then
    raise exception 'V01b el trigger no tiene la forma esperada: %', v_def;
  end if;
end;
$test$;

-- ── V02: vaciar TODO al cliente bancado -> bloqueado con el mensaje claro ───
do $test$
begin
  begin
    update public.perfiles set
      banco = null, numero_cuenta = null, tipo_cuenta = null, cci = null,
      beneficiario_nombre = null, beneficiario_dni = null,
      banco_usd = null, numero_cuenta_usd = null, tipo_cuenta_usd = null, cci_usd = null,
      beneficiario_nombre_usd = null, beneficiario_dni_usd = null
    where id = '6a000000-0000-4000-8000-000000000001';
    raise exception 'V02 el vaciado total paso sin que el trigger frenara';
  exception
    when raise_exception then
      if sqlerrm !~ 'al menos una cuenta bancaria' then
        raise exception 'V02b freno pero con otro mensaje: %', sqlerrm;
      end if;
  end;
end;
$test$;

-- ── V03: el vaciado SIBILINO (solo banco+numero, dejando cci/tipo) tambien ──
do $test$
begin
  begin
    update public.perfiles set
      banco = null, numero_cuenta = null, banco_usd = null, numero_cuenta_usd = null
    where id = '6a000000-0000-4000-8000-000000000001';
    raise exception 'V03 vaciar solo banco/numero de ambas monedas paso';
  exception
    when raise_exception then
      if sqlerrm !~ 'al menos una cuenta bancaria' then
        raise exception 'V03b freno pero con otro mensaje: %', sqlerrm;
      end if;
  end;
end;
$test$;

-- ── V03b: vaciar con CADENAS VACIAS tampoco pasa (bypass del NO-GO) ─────────
-- '' satisface `is not null`; el trigger normaliza con nullif(btrim(...)).
do $test$
begin
  begin
    update public.perfiles set
      banco = '', numero_cuenta = '  ', banco_usd = '', numero_cuenta_usd = ''
    where id = '6a000000-0000-4000-8000-000000000001';
    raise exception 'V03b el vaciado con cadenas vacias paso';
  exception
    when raise_exception then
      if sqlerrm !~ 'al menos una cuenta bancaria' then
        raise exception 'V03c freno pero con otro mensaje: %', sqlerrm;
      end if;
  end;
end;
$test$;

-- ── V03d: quitar SOLO la PEN (la USD queda viva) -> permitido, y se restaura ─
-- Simetria del V04: la rama USD de «queda» debe sostener sola la regla.
do $test$
declare v_banco_usd text;
begin
  update public.perfiles set
    banco = null, numero_cuenta = null, tipo_cuenta = null, cci = null
  where id = '6a000000-0000-4000-8000-000000000001';
  select banco_usd into v_banco_usd from public.perfiles where id = '6a000000-0000-4000-8000-000000000001';
  if v_banco_usd is distinct from 'BANCO ORACULO USD' then
    raise exception 'V03d la cuenta USD debio quedar intacta (banco_usd=%)', v_banco_usd;
  end if;
  -- restaurar la PEN para que V04/V05/V06 partan del estado original
  update public.perfiles set
    banco = 'BANCO ORACULO', numero_cuenta = '19100000000777',
    tipo_cuenta = 'ahorros', cci = '00219100000000000777'
  where id = '6a000000-0000-4000-8000-000000000001';
end;
$test$;

-- ── V04: quitar SOLO la moneda USD (la PEN queda viva) -> permitido ─────────
do $test$
declare v_banco text;
begin
  update public.perfiles set
    banco_usd = null, numero_cuenta_usd = null, tipo_cuenta_usd = null, cci_usd = null
  where id = '6a000000-0000-4000-8000-000000000001';
  select banco into v_banco from public.perfiles where id = '6a000000-0000-4000-8000-000000000001';
  if v_banco is distinct from 'BANCO ORACULO' then
    raise exception 'V04 la cuenta PEN debio quedar intacta (banco=%)', v_banco;
  end if;
end;
$test$;

-- ── V05: y ahora vaciar la PEN (la unica viva) -> bloqueado ─────────────────
do $test$
begin
  begin
    update public.perfiles set banco = null, numero_cuenta = null, tipo_cuenta = null, cci = null
    where id = '6a000000-0000-4000-8000-000000000001';
    raise exception 'V05 vaciar la ultima cuenta viva paso';
  exception
    when raise_exception then
      if sqlerrm !~ 'al menos una cuenta bancaria' then
        raise exception 'V05b freno pero con otro mensaje: %', sqlerrm;
      end if;
  end;
end;
$test$;

-- ── V06: corregir full -> full sigue libre (cambiar numero y banco) ─────────
do $test$
declare v_num text;
begin
  update public.perfiles set banco = 'BANCO NUEVO', numero_cuenta = '19100000000888'
  where id = '6a000000-0000-4000-8000-000000000001';
  select numero_cuenta into v_num from public.perfiles where id = '6a000000-0000-4000-8000-000000000001';
  if v_num is distinct from '19100000000888' then
    raise exception 'V06 la correccion full->full no persistio (numero=%)', v_num;
  end if;
end;
$test$;

-- ── V07: legacy SIN cuenta sigue 100%% editable (grandfathering) ────────────
do $test$
begin
  -- tocar una columna del OF con el cliente legacy: tenia=false -> no aplica
  update public.perfiles set numero_cuenta = null, telefono = '+51999999001'
  where id = '6a000000-0000-4000-8000-000000000002';
end;
$test$;

-- ── V08: el flujo del PORTAL vacio -> lleno sigue libre ─────────────────────
do $test$
declare v_banco text;
begin
  update public.perfiles set
    banco = 'BANCO PORTAL', numero_cuenta = '19100000000999', tipo_cuenta = 'ahorros',
    cci = '00219100000000000999'
  where id = '6a000000-0000-4000-8000-000000000002';
  select banco into v_banco from public.perfiles where id = '6a000000-0000-4000-8000-000000000002';
  if v_banco is distinct from 'BANCO PORTAL' then
    raise exception 'V08 el alta bancaria del portal (2o UPDATE) no persistio';
  end if;
end;
$test$;

-- ── V09: y desde ese momento tambien queda protegido ────────────────────────
do $test$
begin
  begin
    update public.perfiles set banco = null, numero_cuenta = null
    where id = '6a000000-0000-4000-8000-000000000002';
    raise exception 'V09 el cliente recien bancado quedo desprotegido';
  exception
    when raise_exception then null;
  end;
end;
$test$;

-- ── V10: un NO-cliente con residuos bancarios NO esta sujeto al trigger ─────
do $test$
begin
  update public.perfiles set banco = null, numero_cuenta = null
  where id = '6a000000-0000-4000-8000-000000000003';
end;
$test$;

-- ── V11: la funcion es invoker, search_path fijo y sin EXECUTE publico ──────
do $test$
declare v_secdef boolean; v_config text[];
begin
  select p.prosecdef, p.proconfig into v_secdef, v_config
    from pg_proc p
   where p.oid = 'public.perfiles_cuentas_no_vaciar()'::regprocedure;
  if v_secdef then
    raise exception 'V11 la funcion no debe ser SECURITY DEFINER (solo lee OLD/NEW)';
  end if;
  if v_config is null or array_to_string(v_config, ';') !~ 'search_path' then
    raise exception 'V11b falta el search_path fijo';
  end if;
  if has_function_privilege('anon', 'public.perfiles_cuentas_no_vaciar()', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.perfiles_cuentas_no_vaciar()', 'EXECUTE') then
    raise exception 'V11c anon/authenticated no deben tener EXECUTE';
  end if;
end;
$test$;

-- ── V12: un UPDATE que no toca columnas bancarias ni ejecuta la funcion ─────
-- (BEFORE UPDATE OF: telefono no esta en la lista -> cero costo en el camino
-- caliente de perfiles; se prueba que al menos no estorba.)
do $test$
begin
  update public.perfiles set telefono = '+51999999002'
  where id = '6a000000-0000-4000-8000-000000000001';
end;
$test$;

select 'CUENTAS_TX_OK' as resultado;

rollback;

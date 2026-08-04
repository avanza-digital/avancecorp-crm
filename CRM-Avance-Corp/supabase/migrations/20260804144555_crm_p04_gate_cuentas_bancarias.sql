-- Restablece la invariante de offboarding de P04 sobre las RPC bancarias que
-- llegaron despues de 20260803164348_crm_offboarding_gate_activos.
--
-- El gate envuelve a TODO actor porque estas RPC pertenecen a crm.*. Un admin
-- del portal sin membresia CRM conserva el fallback global definido por P04;
-- si tiene una fila en crm.equipo y esa membresia se apaga, la revocacion
-- prevalece. El JWT solo identifica a la persona: private.puede_acceder_crm()
-- consulta el estado vivo en cada llamada.
--
-- Frontera deliberada: esta migracion NO cambia public.crear_contrato ni
-- public.actualizar_contrato. Son RPC heredadas del portal y su retiro/migracion
-- exige decidir primero como quedara el alta administrativa legacy. P04 queda
-- restablecido aqui sobre la superficie bancaria crm.*, no universaliza aun la
-- cuenta contractual para todos los canales del portal.

set local lock_timeout = '10s';

do $$
begin
  if to_regprocedure('private.puede_acceder_crm()') is null then
    raise exception 'Falta private.puede_acceder_crm(); aplica P04 antes de esta migracion';
  end if;
  if to_regprocedure('public.es_admin()') is null
     or to_regprocedure('public.es_analista()') is null then
    raise exception 'Faltan los helpers de autorizacion del portal';
  end if;
  if to_regclass('public.contratos') is null
     or to_regclass('crm.cuentas_bancarias') is null
     or to_regclass('crm.contrato_cuentas_pago') is null then
    raise exception 'Falta el ledger bancario contractual; aplica la migracion 20260803221622';
  end if;
  if to_regprocedure('public.actualizar_contrato(uuid,jsonb,jsonb)') is null
     or to_regprocedure('crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)') is null
     or to_regprocedure('crm.cuentas_pago_contratos_fn(uuid[])') is null then
    raise exception 'Faltan los wrappers contractuales de la migracion 20260803221622';
  end if;
end;
$$;

create or replace function private.puede_gestionar_cuentas_cliente(p_cliente_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and (select private.puede_acceder_crm())
    and exists (
      select 1
      from public.perfiles cli
      where cli.id = p_cliente_id
        and cli.rol = 'cliente'
        and cli.activo = true
        and (
          -- Poder propio del portal, sujeto al gate comun de P04.
          (select public.es_admin())
          or (
            -- El analista exige ademas alcance sobre el cliente.
            (select public.es_analista())
            and (
              cli.asesor_perfil_id = (select auth.uid())
              or (
                cli.asesor_perfil_id is null
                and cli.creado_por = (select auth.uid())
              )
            )
          )
        )
    );
$$;

-- El wrapper anterior solo resolvia el cliente cuando el contrato ya tenia
-- cuenta contractual. Un contrato legacy sin enlace saltaba el helper y caia
-- directamente a public.actualizar_contrato. Resolver primero el contrato con
-- LEFT JOIN hace que ambos caminos atraviesen el mismo gate vivo.
create or replace function crm.actualizar_contrato_con_cuenta(
  p_id uuid,
  p_contrato jsonb,
  p_cronograma jsonb
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cliente_id      uuid;
  v_cliente_cuenta  uuid;
  v_moneda_actual   text;
  v_moneda_cuenta   text;
  v_moneda_nueva    text;
  v_tiene_cuenta    boolean;
begin
  if p_contrato is null or jsonb_typeof(p_contrato) <> 'object' then
    raise exception using errcode = '22023', message = 'Faltan los datos del contrato';
  end if;

  select
    ct.cliente_id,
    cb.cliente_id,
    ct.moneda,
    cb.moneda,
    ccp.contrato_id is not null
  into
    v_cliente_id,
    v_cliente_cuenta,
    v_moneda_actual,
    v_moneda_cuenta,
    v_tiene_cuenta
  from public.contratos ct
  left join crm.contrato_cuentas_pago ccp on ccp.contrato_id = ct.id
  left join crm.cuentas_bancarias cb on cb.id = ccp.cuenta_bancaria_id
  where ct.id = p_id;

  if not found or not private.puede_gestionar_cuentas_cliente(v_cliente_id) then
    raise exception using errcode = '42501', message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  if v_tiene_cuenta then
    if v_cliente_id is distinct from v_cliente_cuenta
       or v_moneda_actual is distinct from v_moneda_cuenta then
      raise exception using
        errcode = 'P0001',
        message = 'El contrato tiene una cuenta de pago con moneda inconsistente; requiere conciliacion';
    end if;
    v_moneda_nueva := upper(btrim(coalesce(p_contrato->>'moneda', v_moneda_actual)));
    if v_moneda_nueva is distinct from v_moneda_cuenta then
      raise exception using
        errcode = '22023',
        message = 'La moneda de un contrato con cuenta de pago fijada no se puede cambiar desde Corregir';
    end if;
  end if;

  -- public.actualizar_contrato conserva la ventana de 5 h, la autoria/cartera
  -- y la regeneracion segura del cronograma como segunda linea de defensa.
  perform public.actualizar_contrato(p_id, p_contrato, p_cronograma);
end;
$$;

comment on function crm.actualizar_contrato_con_cuenta(uuid, jsonb, jsonb) is
  'Corrige contratos enlazados o legacy; ambos atraviesan el gate vivo P04 antes de delegar en public.actualizar_contrato.';

-- El resolver de Pagos es otra superficie crm.*. El rol admin sigue siendo
-- obligatorio, pero no puede anular una revocacion explicita de crm.equipo.
create or replace function crm.cuentas_pago_contratos_fn(p_contrato_ids uuid[])
returns table (
  contrato_id uuid,
  cuenta_bancaria_id uuid,
  moneda text,
  banco text,
  tipo_cuenta text,
  numero_cuenta text,
  cci text,
  titular_distinto boolean,
  beneficiario_nombre text,
  beneficiario_dni text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (select private.puede_acceder_crm())
     or not (select public.es_admin()) then
    raise exception using errcode = '42501', message = 'No autorizado para consultar cuentas de pago';
  end if;
  if coalesce(cardinality(p_contrato_ids), 0) > 5000 then
    raise exception using errcode = '22023', message = 'Demasiados contratos en una sola consulta';
  end if;
  if coalesce(cardinality(p_contrato_ids), 0) = 0 then
    return;
  end if;

  if exists (
    select 1
    from crm.contrato_cuentas_pago ccp
    join public.contratos ct on ct.id = ccp.contrato_id
    join crm.cuentas_bancarias cb on cb.id = ccp.cuenta_bancaria_id
    where ccp.contrato_id = any(p_contrato_ids)
      and (
        cb.cliente_id is distinct from ct.cliente_id
        or cb.moneda is distinct from ct.moneda
      )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'Hay un contrato con cuenta de pago inconsistente; requiere conciliacion antes de pagar';
  end if;

  return query
  select
    ccp.contrato_id,
    cb.id as cuenta_bancaria_id,
    cb.moneda,
    cb.banco,
    cb.tipo_cuenta,
    cb.numero_cuenta,
    cb.cci,
    cb.titular_distinto,
    cb.beneficiario_nombre,
    cb.beneficiario_dni
  from crm.contrato_cuentas_pago ccp
  join crm.cuentas_bancarias cb on cb.id = ccp.cuenta_bancaria_id
  where ccp.contrato_id = any(p_contrato_ids);
end;
$$;

comment on function crm.cuentas_pago_contratos_fn(uuid[]) is
  'Entrega a Pagos la fotografia contractual solo para admin con acceso CRM vivo segun P04.';

comment on function private.puede_gestionar_cuentas_cliente(uuid) is
  'Autoriza banca contractual con gate vivo P04 para todo actor; admin global conserva su poder y analista exige ademas cartera.';

-- El helper solo se invoca desde las RPC SECURITY DEFINER que proyectan el
-- payload minimo. No es un endpoint directo, ni siquiera para service_role.
revoke all on function private.puede_gestionar_cuentas_cliente(uuid)
  from public, anon, authenticated, service_role;
revoke all on function crm.actualizar_contrato_con_cuenta(uuid, jsonb, jsonb)
  from public, anon, service_role;
grant execute on function crm.actualizar_contrato_con_cuenta(uuid, jsonb, jsonb)
  to authenticated;
revoke all on function crm.cuentas_pago_contratos_fn(uuid[])
  from public, anon, service_role;
grant execute on function crm.cuentas_pago_contratos_fn(uuid[])
  to authenticated;

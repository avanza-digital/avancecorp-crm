-- ============================================================================
-- REVERSA de F2.b E4 (20260905140000): restaura public.crear_contrato byte a byte (md5 de prod) y suelta el candado.
-- Se NIEGA si la bandera está encendida. Repetible dos veces.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_e4_reversa'));
do $flags$
begin
  if exists (select 1 from crm.multiempresa_flags where nombre = 'resolver_en_puertas' and activo) then
    raise exception 'REVERSA E4: la bandera está ENCENDIDA; apágala a propósito antes de revertir';
  end if;
end
$flags$;
do $guard$
declare v_h text;
begin
  v_h := null;
  select md5(pg_get_functiondef(p.oid)) into v_h from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='crear_contrato' and pg_get_function_identity_arguments(p.oid) = 'p_contrato jsonb, p_cronograma jsonb';
  if v_h is null then
    raise exception 'F2.b E4: falta public.crear_contrato(jsonb,jsonb)';
  end if;
  if v_h is distinct from 'a538aa6f60791a4b215bbe615b347a1e' and v_h is distinct from '57d9bcba3be7d82c2218631b58cb9ef7' then
    raise exception 'F2.b E4: public.crear_contrato(jsonb,jsonb) no es ni el texto vivo de producción ni el de E4 (%)', v_h;
  end if;
  v_h := null;
  select md5(pg_get_functiondef(p.oid)) into v_h from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='crm' and p.proname='crear_contrato_con_cuenta' and pg_get_function_identity_arguments(p.oid) = 'p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb';
  if v_h is null then
    raise exception 'F2.b E4: falta crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)';
  end if;
  if v_h is distinct from '555d3e2bb33fe423531de16fb0d0c5de' and v_h is distinct from '4a51aea8ddb3572148a2ac446ec381d1' then
    raise exception 'F2.b E4: crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb) no es ni el texto vivo de producción ni el de E4 (%)', v_h;
  end if;
end
$guard$;
drop trigger if exists trg_perfiles_zz_documento_protegido on public.perfiles;
drop function if exists private.trg_perfiles_documento_protegido();

CREATE OR REPLACE FUNCTION public.crear_contrato(p_contrato jsonb, p_cronograma jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_es_analista boolean := (select public.es_analista());
  v_es_gestor_cartera boolean := (select public.es_gestor_cartera());
  v_rol_crm text := private.rol_crm(v_uid);
  v_es_gerencia_crm boolean := coalesce(v_rol_crm = 'gerencia', false);
  v_es_crm_catalogado boolean :=
    coalesce(v_rol_crm in ('vendedor', 'supervisor'), false)
    and nullif(current_setting('crm.producto_condicion_id', true), '') is not null;
  v_cliente_id uuid;
  v_numero text := nullif(btrim(p_contrato->>'numero_contrato'), '');
  v_categoria text := p_contrato->>'categoria';
  v_moneda text := upper(coalesce(nullif(p_contrato->>'moneda', ''), 'PEN'));
  v_capital numeric;
  v_anio integer := extract(year from now() at time zone 'America/Lima')::integer;
  v_contrato_id uuid;
  v_fecha_operacion date;
  v_periodo date;
  v_cuota jsonb;
  v_asesor_id uuid;
  v_asesor_rol text;
  v_operacion_id uuid;
  v_origen_id uuid;
  v_origen public.contratos%rowtype;
  v_capital_renovado numeric;
  v_capital_adicional numeric;
  v_primer_periodo date;
  v_upgrade_elegible boolean;
  v_analista_cierre uuid;
begin
  if p_contrato is null or jsonb_typeof(p_contrato) <> 'object' then
    raise exception 'Faltan los datos del contrato' using errcode = '22023';
  end if;
  begin
    v_cliente_id := (p_contrato->>'cliente_id')::uuid;
    v_capital := (p_contrato->>'capital')::numeric;
  exception when invalid_text_representation then
    raise exception 'Cliente o capital inválido' using errcode = '22023';
  end;

  -- Vincula autorización y escritura a la misma versión de la cartera. Una
  -- reasignación concurrente espera este lock; si ganó antes, aquí ya se lee el
  -- nuevo Analista y el anterior queda fuera del gate.
  select p.asesor_perfil_id into v_asesor_id
  from public.perfiles p
  where p.id = v_cliente_id and p.rol = 'cliente' and p.activo
  for share;
  if not found then
    raise insufficient_privilege using
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  if not (select private.puede_registrar_ventas()) then
    raise insufficient_privilege using
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  if v_capital < 100 or v_capital > 100000000 then
    raise exception 'El capital debe estar entre 100 y 100,000,000';
  end if;
  if (p_contrato->>'tasa_anual')::numeric <= 0
     or (p_contrato->>'tasa_anual')::numeric > 50 then
    raise exception 'La tasa anual debe estar entre 0 y 50%%';
  end if;
  if v_categoria is null or v_categoria not in ('nuevo', 'renovacion', 'upgrade') then
    raise exception 'Selecciona la categoría del contrato (Nuevo, Renovación o Upgrade)';
  end if;
  if v_moneda not in ('PEN', 'USD') then
    raise exception 'Moneda inválida' using errcode = '22023';
  end if;

  -- EL ANALISTA QUE CIERRA (decision 2 del plan P-055). Es de quien VENDIO, no
  -- de quien tecleo: `creado_por` se conserva aparte y no se pisa.
  begin
    v_analista_cierre := nullif(btrim(coalesce(p_contrato->>'analista_cierre_id', '')), '')::uuid;
  exception when invalid_text_representation then
    raise exception 'El analista que cierra no es valido' using errcode = '22023';
  end;

  if v_analista_cierre is not null then
    -- Elegido a mano: tiene que poder tener ventas. SOLO ACTIVOS (decision de
    -- Miguel, 29/08): una venta NUEVA es de alguien que esta trabajando; la
    -- venta vieja de alguien que se fue entra por la reasignacion de gerencia
    -- (que si acepta inactivos, con motivo y rastro). Y los roles OFF-ROSTER
    -- (coordinador, directorio) no son organigrama comercial por diseno.
    if not exists (
      select 1 from crm.equipo e where e.perfil_id = v_analista_cierre
        and e.activo
        and e.rol_crm in ('vendedor','supervisor','gerencia')
    ) then
      raise exception 'El analista que cierra tiene que estar activo en el equipo comercial'
        using errcode = '22023';
    end if;
  else
    -- No vino. «Si no corresponde a nadie, lo pone a su nombre» (decision 2):
    -- eso solo tiene sentido si quien registra PUEDE tener ventas. Si no puede
    -- -una administrativa, por ejemplo-, tiene que elegir a quien corresponde.
    if not exists (select 1 from crm.equipo e where e.perfil_id = v_uid and e.activo) then
      raise exception 'Elige el analista de la venta'
        using errcode = '22023',
              hint = 'Quien registra no forma parte del equipo comercial, asi que la venta no puede quedar a su nombre.';
    end if;
    v_analista_cierre := v_uid;
  end if;

  -- Las operaciones de cartera necesitan un dueño congelado. No se atribuye a
  -- quien digitó: se atribuye al Analista de perfiles.asesor_perfil_id.
  if v_categoria in ('renovacion', 'upgrade') then
    select e.rol_crm into v_asesor_rol
    from crm.equipo e
    where e.perfil_id = v_asesor_id and e.activo
    for share;
    if v_asesor_id is null
       or not found
       or v_asesor_rol not in ('vendedor', 'supervisor') then
      raise exception using
        errcode = '22023',
        message = 'Asigna un Analista activo al cliente antes de registrar la operación';
    end if;
  end if;

  if v_categoria = 'renovacion' then
    begin
      v_origen_id := (p_contrato->>'contrato_origen_id')::uuid;
      v_capital_renovado := (p_contrato->>'capital_renovado')::numeric;
      v_capital_adicional := coalesce((p_contrato->>'capital_adicional')::numeric, 0);
    exception when invalid_text_representation then
      raise exception 'Completa contrato anterior, capital renovado y adicional válidos'
        using errcode = '22023';
    end;

    select * into v_origen
    from public.contratos c
    where c.id = v_origen_id
    for update;
    if not found then
      raise exception 'El contrato a renovar no existe' using errcode = 'P0002';
    end if;
    if v_origen.cliente_id is distinct from v_cliente_id then
      raise exception 'El contrato anterior pertenece a otro cliente' using errcode = '22023';
    end if;
    if v_origen.estado not in ('activo', 'vencido') or v_origen.renovado_a_id is not null then
      raise exception 'El contrato anterior ya fue cerrado o renovado' using errcode = 'P0409';
    end if;
    if v_origen.fecha_vencimiento > (now() at time zone 'America/Lima')::date then
      raise exception 'La renovación solo se registra cuando el contrato llega a su fecha fin'
        using errcode = '22023';
    end if;
    if v_origen.moneda is distinct from v_moneda then
      raise exception 'La renovación debe conservar la moneda del contrato anterior'
        using errcode = '22023';
    end if;
    if (p_contrato->>'fecha_inicio')::date < v_origen.fecha_vencimiento then
      raise exception 'El contrato nuevo no puede iniciar antes del vencimiento anterior'
        using errcode = '22023';
    end if;
    if v_capital_renovado <= 0 or v_capital_renovado > v_origen.capital then
      raise exception 'El capital renovado debe ser mayor a cero y no superar el contrato anterior'
        using errcode = '22023';
    end if;
    if v_capital_adicional < 0 then
      raise exception 'El capital adicional no puede ser negativo' using errcode = '22023';
    end if;
    if v_capital is distinct from (v_capital_renovado + v_capital_adicional) then
      raise exception 'El nuevo capital debe ser capital renovado + capital adicional'
        using errcode = '22023';
    end if;
  end if;

  if v_numero is null then
    v_numero := private.siguiente_numero_contrato(v_anio);
  end if;
  if exists (select 1 from public.contratos c where c.numero_contrato = v_numero) then
    raise exception 'El N de contrato % ya existe', v_numero;
  end if;

  insert into public.contratos (
    cliente_id, numero_contrato, capital, moneda, tasa_anual, modalidad,
    tipo_interes, fecha_inicio, fecha_vencimiento, notas_internas,
    categoria, estado, creado_por, analista_cierre_id
  ) values (
    v_cliente_id, v_numero, v_capital, v_moneda,
    (p_contrato->>'tasa_anual')::numeric, p_contrato->>'modalidad',
    coalesce(nullif(p_contrato->>'tipo_interes', ''), 'simple'),
    (p_contrato->>'fecha_inicio')::date,
    (p_contrato->>'fecha_vencimiento')::date,
    nullif(btrim(coalesce(p_contrato->>'notas_internas', '')), ''),
    v_categoria, 'activo', v_uid, v_analista_cierre
  ) returning id, fecha_cierre_comercial into v_contrato_id, v_fecha_operacion;

  if p_cronograma is null or jsonb_typeof(p_cronograma) <> 'array'
     or jsonb_array_length(p_cronograma) = 0 then
    raise exception 'El cronograma no puede estar vacío';
  end if;
  for v_cuota in select value from jsonb_array_elements(p_cronograma)
  loop
    insert into public.cronograma_pagos (
      contrato_id, numero_cuota, fecha_programada, monto_programado, estado, tipo
    ) values (
      v_contrato_id, (v_cuota->>'numero_cuota')::integer,
      (v_cuota->>'fecha_programada')::date,
      (v_cuota->>'monto_programado')::numeric, 'pendiente',
      coalesce(nullif(v_cuota->>'tipo', ''), 'cuota')
    );
  end loop;
  if p_contrato ? 'titulares' then
    perform public._sync_contrato_titulares(v_contrato_id, p_contrato->'titulares');
  end if;

  if v_categoria in ('renovacion', 'upgrade') then
    v_periodo := date_trunc('month', v_fecha_operacion)::date;
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('crm.operaciones_cartera'),
      pg_catalog.hashtext(v_cliente_id::text || '|' || v_periodo::text)
    );

    if v_categoria = 'upgrade' then
      select min(date_trunc('month', c.fecha_cierre_comercial)::date)
        into v_primer_periodo
      from public.contratos c
      where c.cliente_id = v_cliente_id;
      v_upgrade_elegible := v_periodo > v_primer_periodo;
    else
      v_upgrade_elegible := true;
    end if;

    insert into crm.operaciones_cartera (
      cliente_id, vendedor_id, tipo, contrato_origen_id, contrato_nuevo_id,
      fecha_operacion, periodo, moneda, capital_renovado, capital_adicional,
      elegible_conversion, desglose_completo, fuente, creado_por
    ) values (
      v_cliente_id, v_asesor_id, v_categoria, v_origen_id, v_contrato_id,
      v_fecha_operacion, v_periodo, v_moneda,
      case when v_categoria = 'renovacion' then v_capital_renovado end,
      case when v_categoria = 'renovacion' then v_capital_adicional end,
      v_upgrade_elegible, true, 'flujo_cartera', v_uid
    ) returning id into v_operacion_id;
  end if;

  if v_categoria = 'renovacion' then
    update public.cronograma_pagos
       set estado = 'trasladado'
     where contrato_id = v_origen_id and estado in ('pendiente', 'vencido');
    update public.contratos
       set estado = 'renovado', renovado_a_id = v_contrato_id,
           cerrado_en = now(), cerrado_por = v_uid
     where id = v_origen_id;
  end if;

  return jsonb_build_object(
    'id', v_contrato_id,
    'numero_contrato', v_numero,
    'operacion_id', v_operacion_id,
    'conversion_elegible', case
      when v_categoria in ('renovacion', 'upgrade') then v_upgrade_elegible
    end
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.crear_contrato_con_cuenta(p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid                  uuid := (select auth.uid());
  v_cliente_id           uuid;
  v_moneda               text;
  v_tipo_seleccion       text;
  v_cuenta_id            uuid;
  v_cuenta_activa        crm.cuentas_bancarias%rowtype;
  v_banco                text;
  v_tipo_cuenta          text;
  v_numero_cuenta        text;
  v_cci                  text;
  v_titular_distinto     boolean := false;
  v_beneficiario_nombre  text;
  v_beneficiario_dni     text;
  v_cuenta_esperada      jsonb;
  v_origen               text;
  v_resultado            jsonb;
  v_contrato_id          uuid;
begin
  if p_contrato is null or jsonb_typeof(p_contrato) <> 'object' then
    raise exception using errcode = '22023', message = 'Faltan los datos del contrato';
  end if;
  if p_cuenta is null or jsonb_typeof(p_cuenta) <> 'object' then
    raise exception using errcode = '22023', message = 'Selecciona la cuenta para el pago de intereses';
  end if;

  begin
    v_cliente_id := (p_contrato->>'cliente_id')::uuid;
  exception when invalid_text_representation then
    raise exception using errcode = '22023', message = 'Cliente invalido';
  end;
  v_moneda := upper(btrim(coalesce(p_contrato->>'moneda', '')));
  if v_moneda not in ('PEN', 'USD') then
    raise exception using errcode = '22023', message = 'Moneda del contrato invalida';
  end if;
  if not (select private.puede_registrar_ventas()) then
    raise exception using errcode = '42501', message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  v_tipo_seleccion := lower(btrim(coalesce(p_cuenta->>'tipo', '')));

  if v_tipo_seleccion = 'existente' then
    begin
      v_cuenta_id := (p_cuenta->>'cuenta_id')::uuid;
    exception when invalid_text_representation then
      raise exception using errcode = '22023', message = 'Cuenta bancaria invalida';
    end;

    select cb.* into v_cuenta_activa
    from crm.cuentas_bancarias cb
    where cb.id = v_cuenta_id
      and cb.cliente_id = v_cliente_id
      and cb.moneda = v_moneda
      and cb.activa = true
    for share;
    if not found then
      raise exception using
        errcode = '22023',
        message = 'La cuenta bancaria no esta disponible para este cliente y moneda';
    end if;

  elsif v_tipo_seleccion in ('perfil', 'nueva') then
    if v_tipo_seleccion = 'perfil' then
      select
        btrim(case when v_moneda = 'USD' then p.banco_usd else p.banco end),
        lower(btrim(case when v_moneda = 'USD' then p.tipo_cuenta_usd else p.tipo_cuenta end)),
        upper(btrim(case when v_moneda = 'USD' then p.numero_cuenta_usd else p.numero_cuenta end)),
        btrim(case when v_moneda = 'USD' then p.cci_usd else p.cci end),
        case when v_moneda = 'USD' then p.titular_distinto_usd else p.titular_distinto end,
        case when v_moneda = 'USD' then p.beneficiario_nombre_usd else p.beneficiario_nombre end,
        case when v_moneda = 'USD' then p.beneficiario_dni_usd else p.beneficiario_dni end
      into v_banco, v_tipo_cuenta, v_numero_cuenta, v_cci,
           v_titular_distinto, v_beneficiario_nombre, v_beneficiario_dni
      from public.perfiles p
      where p.id = v_cliente_id
      -- La fotografia del perfil debe seguir siendo cierta hasta que termine
      -- el alta. Sin este lock, un UPDATE concurrente podia confirmar despues
      -- del SELECT y antes de crear el vinculo contractual.
      for share;
      v_origen := 'perfil';
    else
      v_banco := btrim(coalesce(p_cuenta->>'banco', ''));
      v_tipo_cuenta := lower(btrim(coalesce(p_cuenta->>'tipo_cuenta', '')));
      v_numero_cuenta := upper(btrim(coalesce(p_cuenta->>'numero_cuenta', '')));
      v_cci := btrim(coalesce(p_cuenta->>'cci', ''));
      begin
        v_titular_distinto := coalesce((p_cuenta->>'titular_distinto')::boolean, false);
      exception when invalid_text_representation then
        raise exception using errcode = '22023', message = 'Indicador de beneficiario invalido';
      end;
      v_beneficiario_nombre := p_cuenta->>'beneficiario_nombre';
      v_beneficiario_dni := p_cuenta->>'beneficiario_dni';
      v_origen := 'contrato';
    end if;

    v_banco := btrim(coalesce(v_banco, ''));
    v_tipo_cuenta := lower(btrim(coalesce(v_tipo_cuenta, '')));
    v_numero_cuenta := upper(btrim(coalesce(v_numero_cuenta, '')));
    v_cci := btrim(coalesce(v_cci, ''));
    if v_titular_distinto then
      v_beneficiario_nombre := upper(regexp_replace(btrim(coalesce(v_beneficiario_nombre, '')), '\s+', ' ', 'g'));
      v_beneficiario_dni := btrim(coalesce(v_beneficiario_dni, ''));
    else
      v_beneficiario_nombre := null;
      v_beneficiario_dni := null;
    end if;

    if v_tipo_seleccion = 'perfil' then
      v_cuenta_esperada := jsonb_build_object(
        'banco', v_banco,
        'tipo_cuenta', v_tipo_cuenta,
        'numero_cuenta', v_numero_cuenta,
        'cci', v_cci,
        'titular_distinto', v_titular_distinto,
        'beneficiario_nombre', v_beneficiario_nombre,
        'beneficiario_dni', v_beneficiario_dni
      );
      if jsonb_typeof(p_cuenta->'cuenta_esperada') is distinct from 'object'
         or (p_cuenta->'cuenta_esperada') is distinct from v_cuenta_esperada then
        raise exception using
          errcode = 'P0001',
          message = 'La cuenta actual del cliente cambio. Recarga las cuentas y vuelve a seleccionarla';
      end if;
    end if;

    if length(v_banco) not between 1 and 100 then
      raise exception using errcode = '22023', message = 'Selecciona el banco de la cuenta';
    end if;
    if v_tipo_cuenta not in ('ahorros', 'corriente') then
      raise exception using errcode = '22023', message = 'Selecciona un tipo de cuenta valido';
    end if;
    if v_numero_cuenta !~ '^[A-Za-z0-9-]{1,30}$' then
      raise exception using errcode = '22023', message = 'El numero de cuenta solo puede contener letras, numeros y guiones';
    end if;
    if v_cci !~ '^[0-9]{20}$' then
      raise exception using errcode = '22023', message = 'El CCI debe tener exactamente 20 digitos';
    end if;
    if v_titular_distinto and (
      length(v_beneficiario_nombre) not between 1 and 200
      or v_beneficiario_dni !~ '^[0-9]{8,12}$'
    ) then
      raise exception using errcode = '22023', message = 'Completa correctamente los datos del beneficiario';
    end if;

    -- Serializa dos altas simultaneas del mismo CCI sin bloquear otras cuentas.
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(v_cliente_id::text || '|' || v_moneda || '|' || v_cci, 0)
    );

    select cb.* into v_cuenta_activa
    from crm.cuentas_bancarias cb
    where cb.cliente_id = v_cliente_id
      and cb.moneda = v_moneda
      and cb.cci = v_cci
      and cb.activa = true
    for update;

    if found
       and lower(v_cuenta_activa.banco) = lower(v_banco)
       and v_cuenta_activa.tipo_cuenta = v_tipo_cuenta
       and v_cuenta_activa.numero_cuenta = v_numero_cuenta
       and v_cuenta_activa.titular_distinto = v_titular_distinto
       and v_cuenta_activa.beneficiario_nombre is not distinct from v_beneficiario_nombre
       and v_cuenta_activa.beneficiario_dni is not distinct from v_beneficiario_dni then
      v_cuenta_id := v_cuenta_activa.id;
    else
      if found then
        update crm.cuentas_bancarias
           set activa = false,
               desactivada_por = v_uid,
               desactivada_en = now()
         where id = v_cuenta_activa.id;
      end if;

      insert into crm.cuentas_bancarias (
        cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci,
        titular_distinto, beneficiario_nombre, beneficiario_dni,
        activa, origen, creado_por
      ) values (
        v_cliente_id, v_moneda, v_banco, v_tipo_cuenta, v_numero_cuenta, v_cci,
        v_titular_distinto, v_beneficiario_nombre, v_beneficiario_dni,
        true, v_origen, v_uid
      )
      returning id into v_cuenta_id;
    end if;
  else
    raise exception using
      errcode = '22023',
      message = 'Selecciona una cuenta existente o registra una cuenta nueva';
  end if;

  -- public.crear_contrato mantiene su validacion de rol/cartera, numeracion,
  -- contrato, cronograma y co-titulares. La llamada anidada participa de ESTA
  -- transaccion: si el enlace bancario falla, todo (incluida una cuenta nueva)
  -- se revierte.
  v_resultado := public.crear_contrato(p_contrato, p_cronograma);
  begin
    v_contrato_id := (v_resultado->>'id')::uuid;
  exception when invalid_text_representation then
    raise exception using errcode = 'P0001', message = 'El contrato no devolvio un identificador valido';
  end;
  if v_contrato_id is null then
    raise exception using errcode = 'P0001', message = 'El contrato no devolvio un identificador';
  end if;

  insert into crm.contrato_cuentas_pago (
    contrato_id, cuenta_bancaria_id, creado_por
  ) values (
    v_contrato_id, v_cuenta_id, v_uid
  );

  return v_resultado || jsonb_build_object('cuenta_bancaria_id', v_cuenta_id);
end;
$function$
;

do $post$
begin
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='crear_contrato' and pg_get_function_identity_arguments(p.oid)='p_contrato jsonb, p_cronograma jsonb') is distinct from 'a538aa6f60791a4b215bbe615b347a1e' then
    raise exception 'REVERSA E4: public.crear_contrato no volvió byte a byte al vivo de producción';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='crear_contrato_con_cuenta' and pg_get_function_identity_arguments(p.oid)='p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb') is distinct from '555d3e2bb33fe423531de16fb0d0c5de' then
    raise exception 'REVERSA E4: crm.crear_contrato_con_cuenta no volvió byte a byte al vivo de producción';
  end if;
  if exists (select 1 from pg_trigger where tgrelid='public.perfiles'::regclass and tgname='trg_perfiles_zz_documento_protegido')
     or to_regprocedure('private.trg_perfiles_documento_protegido()') is not null then
    raise exception 'REVERSA E4: quedó el candado';
  end if;
  raise notice 'REVERSA F2.b E4 OK';
end
$post$;
commit;

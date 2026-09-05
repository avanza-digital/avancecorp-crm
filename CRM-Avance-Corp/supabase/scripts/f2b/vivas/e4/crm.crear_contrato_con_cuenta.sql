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


CREATE OR REPLACE FUNCTION crm.crear_contrato_con_cuenta_pdf_v2(p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_contrato jsonb := p_contrato;
  v_resultado jsonb;
  v_contrato_id uuid;
  v_pdf jsonb;
  v_clave_texto text := nullif(btrim(coalesce(p_contrato->>'clave_idempotencia', '')), '');
  v_clave uuid;
  v_huella text;
  v_huella_previa text;
  -- Rentabilidad R4 (D2): el contrato que amplía un UPGRADE. Viaja dentro de p_contrato igual que
  -- clave_idempotencia (es del transporte, no del contrato) y NO se le quita: la cadena de abajo solo lo lee en la
  -- rama de renovación, así que recibe exactamente lo que recibía.
  v_origen_upgrade text := nullif(btrim(coalesce(p_contrato->>'contrato_origen_id', '')), '');
begin
  if v_actor_id is null then
    raise insufficient_privilege using message = 'Sesión no válida';
  end if;

  -- El origen declarado se publica en un GUC TRANSACCIONAL para que el candado del servidor
  -- (private.trg_contratos_observar_rentabilidad, al commit) sepa de qué contrato hereda la tasa este upgrade. Va con
  -- el cliente delante para que no pueda aplicarse al contrato de otro, y se REESCRIBE en cada alta (también vacío)
  -- para que un alta posterior de la misma transacción no herede la declaración de la anterior.
  perform set_config(
    'crm.rentabilidad_origen_upgrade',
    case when p_contrato->>'categoria' = 'upgrade' and v_origen_upgrade is not null
         then coalesce(p_contrato->>'cliente_id', '') || '|' || v_origen_upgrade else '' end,
    true);

  -- IDEMPOTENCIA DEL ALTA (05/09/2026). El front manda una clave (uuid) por intento de
  -- formulario, la MISMA en cada reintento. Si este actor ya registró un alta con esa
  -- clave, se devuelve el MISMO contrato en vez de crear otro. Viaja DENTRO de
  -- p_contrato para no cambiar la firma del RPC; es del transporte, no del contrato:
  -- se quita antes de bajar a la cadena, que recibe EXACTAMENTE lo que recibía.
  -- Sin clave, nada cambia (los clientes que no la mandan siguen igual).
  if v_clave_texto is not null then
    begin
      v_clave := v_clave_texto::uuid;
    exception when invalid_text_representation then
      raise exception 'La clave de idempotencia del alta no es válida'
        using errcode = '22023';
    end;
    -- Dos envíos simultáneos con la misma clave del mismo actor (doble clic, dos
    -- pestañas) se serializan aquí: el segundo espera y lee el alta del primero.
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'crm.alta_contrato_idempotente|' || v_actor_id::text || '|' || v_clave::text, 0
      )
    );
    -- La huella de LO QUE SE PIDE (sin la clave): la misma clave solo vale para la
    -- misma solicitud. jsonb::text es canónico (claves ordenadas), así que dos
    -- envíos iguales dan la misma huella.
    v_huella := md5(
      (p_contrato - 'clave_idempotencia')::text || '|'
      || coalesce(p_cronograma::text, '') || '|'
      || coalesce(p_cuenta::text, '')
    );
    select a.respuesta, a.contrato_id, a.huella
      into v_resultado, v_contrato_id, v_huella_previa
    from private.contrato_altas_idempotentes a
    where a.actor_id = v_actor_id and a.clave = v_clave;
    if found then
      -- El replay pasa por la MISMA autorización que el alta (Codex 05/09): una
      -- membresía revocada o un contrato fuera de cartera no recuperan nada.
      if not (select private.puede_registrar_ventas()) then
        raise insufficient_privilege using
          message = 'Cliente no encontrado o fuera de tu cartera';
      end if;
      -- Lápida: el contrato de este intento fue eliminado después (FK SET NULL).
      -- Un reintento tardío NO recrea lo que Gerencia borró a propósito.
      if v_contrato_id is null then
        raise exception 'El contrato de este intento fue eliminado después; vuelve a registrar el alta'
          using errcode = 'P0409', hint = 'ALTA_ELIMINADA';
      end if;
      -- Misma fila que bloquea la puerta de eliminación: replay y borrado se
      -- serializan. Si el contrato desaparece mientras esperamos, es lápida.
      begin
        perform private.bloquear_fila_contrato_pdf(v_contrato_id);
      exception when sqlstate 'P0002' then
        raise exception 'El contrato de este intento fue eliminado después; vuelve a registrar el alta'
          using errcode = 'P0409', hint = 'ALTA_ELIMINADA';
      end;
      -- Eliminación PREPARADA y aún no finalizada (Gerencia pulsó «Eliminar» y la edge todavía
      -- no borró): no se devuelve como «alta recuperada» un contrato que está a punto de
      -- desaparecer. La misma pregunta y el mismo 55000 que hace el alta
      -- (private.crear_job_contrato_pdf_base); la fila ya está bloqueada, así que la
      -- respuesta es estable hasta que esta transacción termine.
      if private.contrato_en_eliminacion(v_contrato_id) then
        raise exception 'El contrato está en proceso de eliminación'
          using errcode = '55000';
      end if;
      if not private.puede_leer_contrato_pdf_como(v_contrato_id, v_actor_id) then
        raise insufficient_privilege using
          message = 'Contrato no encontrado o fuera de tu cartera';
      end if;
      -- Misma clave pero OTROS datos (el analista editó el formulario tras un
      -- intento que SÍ creó el contrato): no se devuelve el viejo como si fuera
      -- el nuevo ni se crea otro. Se le dice la verdad, con el número.
      if v_huella_previa is distinct from v_huella then
        raise exception 'Este intento ya creó el contrato % con otros datos; no se creó otro. Revísalo antes de registrar uno nuevo',
          coalesce(v_resultado->>'numero_contrato', v_contrato_id::text)
          using errcode = 'P0409',
                hint = 'ALTA_YA_CREADA_CON_OTROS_DATOS',
                detail = jsonb_build_object(
                  'contrato_id', v_contrato_id,
                  'numero_contrato', v_resultado->>'numero_contrato'
                )::text;
      end if;
      -- El MISMO contrato, con el estado documental de HOY (la reserva pudo avanzar
      -- desde el primer intento) y la marca de que es un alta ya registrada.
      return (v_resultado - 'pdf')
        || jsonb_build_object('pdf', private.contrato_pdf_estado_base(v_contrato_id))
        || jsonb_build_object('idempotente', true);
    end if;
    v_contrato := p_contrato - 'clave_idempotencia';
  end if;

  -- El contrato, cronograma, cuenta, vínculo, snapshot y job se confirman o
  -- revierten juntos porque toda la cadena corre en esta transacción RPC.
  v_resultado := crm.crear_contrato_con_cuenta(
    v_contrato,
    p_cronograma,
    p_cuenta
  );
  begin
    v_contrato_id := (v_resultado->>'id')::uuid;
  exception when invalid_text_representation then
    raise exception 'El alta no devolvió un contrato válido'
      using errcode = 'P0001';
  end;
  if v_contrato_id is null then
    raise exception 'El alta no devolvió un contrato válido'
      using errcode = 'P0001';
  end if;

  v_pdf := private.crear_job_contrato_pdf_base(v_contrato_id, v_actor_id);
  v_resultado := v_resultado || jsonb_build_object('pdf', v_pdf);
  if v_clave is not null then
    -- Misma transacción que el alta: o quedan los dos, o ninguno.
    insert into private.contrato_altas_idempotentes (actor_id, clave, contrato_id, huella, respuesta)
    values (v_actor_id, v_clave, v_contrato_id, v_huella, v_resultado);
  end if;
  return v_resultado;
end;
$function$

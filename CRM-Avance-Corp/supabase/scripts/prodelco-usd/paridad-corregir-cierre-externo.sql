-- PARIDAD, solo para el ensayo local: la definición VIVA de
-- crm.corregir_cierre_externo en producción el 17/09/2026 (md5 de su
-- pg_get_functiondef: 894806c9b0a765eff7896f42d51f8bff).
--
-- Las plantillas del banco van un commit por detrás: les falta la guarda de
-- `crm.gestion_neutral` en la actividad del lead. Sin instalar esto, el ensayo
-- partiría de una función que producción NO tiene, y el parche de la moneda se
-- habría derivado de otra base. NO se aplica a producción: allí ya está.
CREATE OR REPLACE FUNCTION crm.corregir_cierre_externo(p_cierre_id uuid, p_monto numeric, p_moneda text, p_cooperativa text, p_numero_transaccion text, p_referencia text, p_vence_en date, p_nota text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid         uuid := (select auth.uid());
  v_rol         text := private.rol_crm((select auth.uid()));
  v_cierre      crm.cierres_externos%rowtype;
  v_transaccion text := btrim(p_numero_transaccion);
  v_referencia  text := nullif(btrim(p_referencia), '');
begin
  if v_uid is null or v_rol is distinct from 'gerencia' then
    raise exception 'Solo gerencia corrige cierres externos'
      using errcode = '42501';
  end if;

  if p_cooperativa is null or p_cooperativa not in ('qorilazo', 'prodelco') then
    raise exception 'Cooperativa invalida: debe ser qorilazo o prodelco'
      using errcode = '22023';
  end if;
  -- El NaN se rechaza EXPLÍCITAMENTE y primero: `NaN <= 0` es false y
  -- `NaN <> round(NaN,2)` también, así que sin esta línea se cuela por las dos
  -- validaciones de abajo y acaba envenenando la suma de la cuota.
  if p_monto is null or p_monto = 'NaN'::numeric or p_monto <= 0 then
    raise exception 'El monto invertido debe ser mayor que cero'
      using errcode = '22023';
  end if;
  if p_monto <> round(p_monto, 2) then
    raise exception 'El monto admite como maximo 2 decimales'
      using errcode = '22023';
  end if;
  if p_moneda is distinct from 'PEN' then
    raise exception 'En cooperativas solo se registran inversiones en soles'
      using errcode = '22023';
  end if;
  if v_transaccion is null or v_transaccion = '' then
    raise exception 'El numero de operacion del deposito es obligatorio'
      using errcode = '22023';
  end if;
  if length(v_transaccion) > 64 then
    raise exception 'El numero de operacion admite como maximo 64 caracteres'
      using errcode = '22023';
  end if;
  if v_referencia is not null and length(v_referencia) > 64 then
    raise exception 'El numero de certificado admite como maximo 64 caracteres'
      using errcode = '22023';
  end if;

  select * into v_cierre
  from crm.cierres_externos
  where id = p_cierre_id
  for update;
  if not found then
    raise exception 'Cierre externo no encontrado';
  end if;
  -- Un cierre anulado no se retoca: corregirlo daría a entender que vuelve a
  -- contar, y no vuelve. Si el monto anulado estaba mal, da igual: no paga.
  if v_cierre.anulado_en is not null then
    raise exception using
      errcode = 'P0409',
      message = 'Ese cierre esta anulado: ya no cuenta y no se corrige',
      detail  = pg_catalog.format('cierre %s, anulado el %s', v_cierre.id, v_cierre.anulado_en);
  end if;

  perform set_config('crm.op_privilegiada', 'on', true);
  begin
    update crm.cierres_externos
       set monto = p_monto,
           moneda = p_moneda,
           cooperativa = p_cooperativa,
           numero_transaccion = v_transaccion,
           referencia_externa = v_referencia,
           vence_en = p_vence_en,
           nota = nullif(btrim(p_nota), '')
     where id = p_cierre_id;

    -- Si gerencia cambia el número, el NUEVO se reclama para siempre. El
    -- ANTERIOR no se libera: sigue en la memoria histórica, que es justo lo que
    -- impide que otro lead lo declare y el mismo depósito se cobre dos veces.
    if upper(v_transaccion) is distinct from upper(v_cierre.numero_transaccion) then
      insert into crm.depositos_reclamados (numero_norm, cierre_id, reclamado_por)
      values (upper(v_transaccion), p_cierre_id, v_uid);
    end if;
  exception when unique_violation then
    raise exception using
      errcode = 'P0409',
      message = 'Ese numero de operacion ya esta registrado',
      hint    = 'Ese deposito ya se declaro antes (aunque su cierre se haya corregido despues): no se puede reusar.';
  end;
  perform set_config('crm.op_privilegiada', 'off', true);

  -- Rastro de negocio en la línea de tiempo del lead. Tipo 'nota' porque el
  -- CHECK de actividades no tiene 'correccion' y ampliarlo por esto no paga:
  -- el QUÉ cambió va en metadata (y el audit trigger guarda la fila entera).
  if v_cierre.lead_id is not null and (coalesce(current_setting('crm.gestion_neutral',true),'off')<>'on' or exists(select 1 from crm.leads where id=v_cierre.lead_id and activo)) then
  insert into crm.actividades (
    lead_id, tipo, detalle, metadata, creado_por
  ) values (
    v_cierre.lead_id,
    'nota',
    'Gerencia corrigio el cierre externo',
    jsonb_build_object(
      'accion', 'correccion_cierre_externo',
      'cierre_externo_id', p_cierre_id,
      'antes', jsonb_build_object(
        'monto', v_cierre.monto, 'moneda', v_cierre.moneda,
        'cooperativa', v_cierre.cooperativa,
        'numero_transaccion', v_cierre.numero_transaccion,
        'referencia_externa', v_cierre.referencia_externa,
        'vence_en', v_cierre.vence_en, 'nota', v_cierre.nota),
      'despues', jsonb_build_object(
        'monto', p_monto, 'moneda', p_moneda,
        'cooperativa', p_cooperativa,
        'numero_transaccion', v_transaccion,
        'referencia_externa', v_referencia,
        'vence_en', p_vence_en, 'nota', nullif(btrim(p_nota), ''))
    ),
    v_uid
  );
  end if;

  return jsonb_build_object('ok', true, 'cierre_id', p_cierre_id);
end;
$function$

;

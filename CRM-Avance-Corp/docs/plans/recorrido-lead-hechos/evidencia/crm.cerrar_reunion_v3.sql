CREATE OR REPLACE FUNCTION crm.cerrar_reunion_v3(p_operacion_id uuid, p_tarea_id uuid, p_estado text, p_resultado_reunion text DEFAULT NULL::text, p_motivo_no_realizada text DEFAULT NULL::text, p_detalle text DEFAULT NULL::text, p_siguiente jsonb DEFAULT NULL::jsonb, p_capital_estimado numeric DEFAULT NULL::numeric, p_moneda text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_respuesta jsonb;
  v_lead uuid;
  v_replay boolean;
begin
  -- EL INPUT SE VALIDA ANTES DE CERRAR NADA. Si la cifra no vale, la cita sigue
  -- abierta y el analista reintenta con el MISMO p_operacion_id: no hay recibo
  -- consumido ni entrevista a medio registrar.
  -- El capital se exige en toda cita realizada MENOS cuando el cliente dijo que
  -- no: ahí no hubo propuesta que declarar y pedir una cifra sería pedir que se
  -- la invente (ver la cabecera). El resultado comercial lo valida el writer.
  if p_estado = 'completada' and coalesce(p_resultado_reunion, '') <> 'no_interesado' then
    if p_capital_estimado is null
       or not (p_capital_estimado > 0)
       -- `trunc`, no `round`: espejo EXACTO del CHECK
       -- `leads_monto_estimado_valido`. Se rechaza una cifra con más de dos
       -- decimales en vez de redondearla — redondear movería el capital que el
       -- analista declaró sin que nadie se enterara.
       or p_capital_estimado <> trunc(p_capital_estimado, 2)
       -- Mismo rango que `numeric(12,2)` de la columna y que MONTO_ESTIMADO_MAX
       -- del front (lib/validacion.ts): ni más estrecho —rechazaría cifras que
       -- la ficha sí acepta— ni más ancho —el UPDATE reventaría con 23514—.
       or p_capital_estimado > 9999999999.99 then
      raise exception 'Declara el capital que le propusiste en la entrevista'
        using errcode = '22023';
    end if;
    if p_moneda is null or p_moneda not in ('PEN', 'USD') then
      raise exception 'La moneda del capital propuesto es obligatoria'
        using errcode = '22023';
    end if;
  elsif p_capital_estimado is not null or p_moneda is not null then
    -- Un plantón, una cancelación o un «no interesado» no proponen capital a
    -- nadie. Recibirlo aquí delata un llamador confundido, y aceptarlo en
    -- silencio escribiría una cifra que nadie declaró.
    raise exception 'El capital solo acompaña a una cita realizada con propuesta'
      using errcode = '22023';
  end if;

  -- ¿ES UN REPLAY? El recibo del comando (crm.sla_operacion_recibos) guarda el
  -- payload del CIERRE, no el capital, así que reenviar la misma operación con
  -- otra cifra no se detectaría allí: `cerrar_reunion_v2` devolvería la
  -- respuesta guardada sin trabajar y el núcleo, en cambio, volvería a escribir
  -- el capital nuevo. Se mira ANTES de delegar —y se sigue delegando, para que
  -- el writer valide la identidad del recibo y rechace un contenido distinto—
  -- pero si ya venía confirmado, esta llamada no escribe NADA. Hallazgo P2-1 de
  -- la auditoría del 18/09.
  select r.respuesta is not null into v_replay
  from crm.sla_operacion_recibos r
  where r.actor_id = (select auth.uid()) and r.operacion_id = p_operacion_id;

  -- El cierre ENTERO sigue siendo del writer auditado: estados válidos,
  -- ámbito, locks lead→tarea, actividad, tarea siguiente, retroceso al
  -- cancelar, episodio SLA de la gestión y recibo idempotente.
  v_respuesta := crm.cerrar_reunion_v2(
    p_operacion_id, p_tarea_id, p_estado,
    p_resultado_reunion, p_motivo_no_realizada, p_detalle, p_siguiente
  );

  if p_estado <> 'completada' then
    return v_respuesta;
  end if;

  v_lead := (v_respuesta->>'lead_id')::uuid;
  if v_lead is null then
    return v_respuesta;
  end if;

  if coalesce(v_replay, false) then
    -- Confirmada antes: se devuelve lo guardado con una foto de solo lectura
    -- del lead. Ni etapa ni capital se vuelven a tocar (eso movería también
    -- `actualizado_en` y añadiría ruido a la auditoría por una repetición).
    return v_respuesta || jsonb_build_object(
      'etapa', (select l.etapa from crm.leads l where l.id = v_lead),
      'entrevista_registrada', false,
      'capital_asentado', false
    );
  end if;

  return v_respuesta || private.entrevista_registrar(
    v_lead, (select auth.uid()), p_capital_estimado, p_moneda
  );
end;
$function$

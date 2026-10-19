CREATE OR REPLACE FUNCTION private.inversion_preparar_nucleo(p_clave uuid, p_datos jsonb, p_puerta text, p_busqueda uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_persona uuid;
  v_lead uuid;
  v_ctx jsonb;
  v_e crm.empresas%rowtype;
  v_s crm.inversion_solicitudes%rowtype;
  v_monto numeric;
  v_fecha date;
  v_vence date;
  v_ruta text;
  v_hash text;
  v_llave_sol uuid;
begin
  if p_clave is null or p_datos is null or jsonb_typeof(p_datos)<>'object' then
    raise exception 'Falta la clave o el contenido de la inversión' using errcode='22023';
  end if;
  if exists (select 1 from jsonb_object_keys(p_datos) k where k not in (
    'inversionista_id','lead_id','empresa','monto','moneda','fecha_comercial','vence_en','numero_transaccion',
    'referencia','evidencia','producto_condicion_id','contrato','cronograma','cuenta','alta_portal','plazo_meses','tasa_anual'
  )) then
    raise exception 'La solicitud contiene campos no admitidos' using errcode='22023';
  end if;
  begin v_persona := (p_datos->>'inversionista_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'Identificador de persona inválido' using errcode='22023';
  end;
  begin v_lead := (p_datos->>'lead_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'Origen de inversión inválido' using errcode='22023';
  end;
  if p_puerta is null or p_puerta not in ('cartera','cliente_existente')
     or (p_puerta = 'cartera' and (p_busqueda is not null or p_motivo is not null))
     or (p_puerta = 'cliente_existente' and (p_busqueda is null or v_lead is not null)) then
    raise exception 'Puerta de preparación inválida' using errcode='22023';
  end if;
  -- Venta cruzada: un reintento se autoriza con su propia solicitud (la búsqueda pudo
  -- vencer); una solicitud nueva, con la búsqueda. En cartera no hay llaves.
  if p_puerta = 'cliente_existente' then
    select s.id into v_llave_sol from crm.inversion_solicitudes s where s.id=p_clave and s.puerta='cliente_existente';
  end if;
  v_ctx := private.inversion_persona_autorizada_para(v_persona,v_llave_sol,case when v_llave_sol is null then p_busqueda end);
  v_hash := private.idem_hash(p_datos);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('f4_solicitud:'||p_clave::text,0));
  select * into v_s from crm.inversion_solicitudes where id=p_clave for update;
  if found then
    if v_s.hash_payload<>v_hash or v_s.inversionista_id<>v_persona or v_s.puerta is distinct from p_puerta
       or v_s.busqueda_id is distinct from p_busqueda or v_s.motivo_atribucion is distinct from p_motivo
       or (p_puerta='cliente_existente' and v_s.analista_cierre_id is distinct from (select auth.uid())) then
      raise exception 'La misma clave llegó con datos distintos' using errcode='P0409';
    end if;
    if v_s.estado<>'confirmada' then
      v_ctx := private.inversion_persona_contexto_para(v_persona,v_lead,v_llave_sol,case when v_llave_sol is null then p_busqueda end);
    end if;
    return private.inversion_solicitud_resultado(v_s.id,v_ctx);
  end if;
  -- Venta cruzada nueva: bajo los candados de documento y persona que tomó la
  -- autorización (orden global: bandera, jerarquía, documento, persona), el documento
  -- buscado sigue siendo de esta persona. Una corrección o fusión posterior a la búsqueda
  -- la invalida (segunda auditoría, P3).
  if p_puerta='cliente_existente' and not exists (select 1 from crm.busquedas_cliente_existente b
       where b.id=p_busqueda
         and private.inversionista_por_documento(b.tipo_documento,b.valor_consultado)=private.inversionista_canonica(v_persona)) then
    raise exception 'El documento ya no corresponde a esta persona; vuelve a buscarla' using errcode='P0409';
  end if;
  v_ctx := private.inversion_persona_contexto_para(v_persona,v_lead,v_llave_sol,case when v_llave_sol is null then p_busqueda end);
  if v_lead is not null and exists(select 1 from crm.inversion_solicitudes
    where lead_origen_id=v_lead and estado in ('preparada','confirmada')) then
    raise exception 'Este lead ya tiene una solicitud: retómala antes de crear otra' using errcode='P0409';
  end if;
  v_e.id:=private.inversion_validar_datos(p_clave,p_datos,v_ctx||case when p_puerta='cliente_existente'
    then jsonb_build_object('analista_cierre_id',(select auth.uid()),'puerta',p_puerta) else '{}'::jsonb end);
  -- D6: una venta cruzada no convive con otra inversión de la misma persona y empresa
  -- en preparación, en ninguno de los dos sentidos (evita registrar dos veces el mismo
  -- dinero). Corre bajo el candado de la persona que tomó la autorización.
  if exists (select 1 from crm.inversion_solicitudes s
             where s.estado='preparada' and s.empresa_id=v_e.id
               and (s.puerta='cliente_existente' or p_puerta='cliente_existente')
               and private.inversionista_canonica(s.inversionista_id)=private.inversionista_canonica(v_persona)) then
    raise exception 'Ya hay una inversión de este cliente en preparación en esta empresa: debe confirmarse o cancelarse antes' using errcode='P0409';
  end if;
  insert into crm.inversion_solicitudes(id,inversionista_id,empresa_id,responsable_esperado_id,hash_payload,datos,creado_por,lead_origen_id,
    puerta,analista_cierre_id,motivo_atribucion,busqueda_id)
  values(p_clave,v_persona,v_e.id,(v_ctx->>'responsable_id')::uuid,v_hash,p_datos,(select auth.uid()),v_lead,
    p_puerta,case when p_puerta='cliente_existente' then (select auth.uid()) end,p_motivo,p_busqueda);
  return private.inversion_solicitud_resultado(p_clave,v_ctx);
end;
$function$

CREATE OR REPLACE FUNCTION crm.preparar_inversion_cliente_existente_fn(p_clave uuid, p_busqueda uuid, p_datos jsonb, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_b crm.busquedas_cliente_existente%rowtype;
  v_persona uuid;
  v_motivo text := btrim(p_motivo, E' \t\r\n');
begin
  if v_uid is null or v_rol is null or v_rol not in ('vendedor','supervisor') then
    raise exception 'Solo un vendedor o un supervisor registra la inversión de un cliente de otra cartera' using errcode = '42501';
  end if;
  if p_clave is null or p_busqueda is null or p_datos is null or jsonb_typeof(p_datos) <> 'object' then
    raise exception 'Falta la clave, la búsqueda o el contenido de la inversión' using errcode = '22023';
  end if;
  if p_datos ? 'lead_id' then
    raise exception 'La venta cruzada no convierte un lead' using errcode = '22023';
  end if;
  -- Reintento con la misma clave: el núcleo compara todo y autoriza con la solicitud.
  if exists (select 1 from crm.inversion_solicitudes s where s.id = p_clave) then
    return private.inversion_preparar_nucleo(p_clave, p_datos, 'cliente_existente', p_busqueda, v_motivo);
  end if;
  select * into v_b from crm.busquedas_cliente_existente b where b.id = p_busqueda;
  if not found or not private.busqueda_cliente_es_llave(p_busqueda, v_uid, v_b.inversionista_id) then
    raise exception 'Vuelve a buscar al cliente por su documento para registrar su inversión' using errcode = 'P0409';
  end if;
  v_persona := private.inversionista_canonica(v_b.inversionista_id);
  begin
    if private.inversionista_canonica((p_datos->>'inversionista_id')::uuid) is distinct from v_persona then
      raise exception 'La inversión no corresponde al cliente buscado' using errcode = '22023';
    end if;
  exception when invalid_text_representation then
    raise exception 'La inversión no corresponde al cliente buscado' using errcode = '22023';
  end;
  if (select i.responsable_relacion_id from crm.inversionistas i where i.id = v_persona)
     in (select private.vendedor_ids_visibles(v_uid)) then
    raise exception 'Este cliente es de tu cartera: registra la inversión desde su ficha' using errcode = 'P0409';
  end if;
  if not private.inversionista_es_cliente(v_persona) then
    raise exception 'La persona todavía no es cliente: su primera inversión nace de un lead' using errcode = 'P0409';
  end if;
  if v_motivo is null or char_length(v_motivo) not between 10 and 500 then
    raise exception 'Explica en 10 a 500 caracteres por qué registras la inversión de este cliente' using errcode = '22023';
  end if;
  perform private.motivo_sin_documento(v_motivo,
    (select array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id = v_persona));
  return private.inversion_preparar_nucleo(p_clave, p_datos, 'cliente_existente', p_busqueda, v_motivo);
end $function$

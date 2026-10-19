CREATE OR REPLACE FUNCTION private.crear_siguiente_tarea(p_anterior crm.tareas, p_siguiente jsonb, p_reagendada_de uuid, p_uid uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
  v_tipo text;
  v_titulo text;
  v_vence timestamptz;
  v_duracion smallint;
  v_modalidad text;
begin
  if p_siguiente is null then return null; end if;
  v_tipo := p_siguiente->>'tipo';
  v_titulo := btrim(coalesce(p_siguiente->>'titulo',''));
  begin
    v_vence := (p_siguiente->>'vence_en')::timestamptz;
    v_id := nullif(p_siguiente->>'id','')::uuid;
  exception when others then
    raise exception 'Fecha o identificador invalido en la tarea siguiente';
  end;
  if p_siguiente->>'duracion_min' is not null then
    v_duracion := (p_siguiente->>'duracion_min')::smallint;
  end if;
  if v_tipo is null or v_tipo not in ('llamada','whatsapp','reunion','tarea')
     or v_titulo = '' or v_vence is null then
    raise exception 'La tarea siguiente exige tipo, titulo y vence_en validos';
  end if;
  if v_tipo = 'reunion' then
    v_modalidad := coalesce(nullif(p_siguiente->>'modalidad_reunion',''), 'sin_clasificar');
  end if;

  insert into crm.tareas (
    id, lead_id, perfil_id, tipo, titulo, nota, vence_en, duracion_min,
    modalidad_reunion, ubicacion_reunion, enlace_reunion,
    reagendada_de, creado_por
  ) values (
    coalesce(v_id, gen_random_uuid()), p_anterior.lead_id, p_anterior.perfil_id,
    v_tipo, v_titulo, nullif(btrim(coalesce(p_siguiente->>'nota','')), ''),
    v_vence, v_duracion, v_modalidad,
    case when v_tipo = 'reunion' then nullif(btrim(coalesce(p_siguiente->>'ubicacion_reunion','')), '') end,
    case when v_tipo = 'reunion' then nullif(btrim(coalesce(p_siguiente->>'enlace_reunion','')), '') end,
    p_reagendada_de, p_uid
  ) returning id into v_id;
  return v_id;
end;
$function$

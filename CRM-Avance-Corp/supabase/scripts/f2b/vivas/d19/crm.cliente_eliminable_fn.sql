CREATE OR REPLACE FUNCTION crm.cliente_eliminable_fn(p_perfil_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n integer;
begin
  if (select auth.uid()) is not null then
    raise exception 'Solo el servicio consulta si un cliente es eliminable' using errcode = '42501';
  end if;
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if exists (select 1 from crm.inversionistas i where i.perfil_id = p_perfil_id and i.estado <> 'fusionado') then
    return pg_catalog.jsonb_build_object('eliminable', false, 'motivo', 'identidad',
      'mensaje', 'Este cliente está reconocido como persona (identidad unificada): desactívalo en vez de eliminarlo');
  end if;
  select count(*) into v_n from public.contratos c where c.cliente_id = p_perfil_id;
  if v_n > 0 then
    return pg_catalog.jsonb_build_object('eliminable', false, 'motivo', 'contratos', 'contratos', v_n,
      'mensaje', 'Este cliente tiene contratos: desactívalo en vez de eliminarlo');
  end if;
  return pg_catalog.jsonb_build_object('eliminable', true);
end;
$function$

CREATE OR REPLACE FUNCTION crm.eliminar_cliente_fn(p_perfil_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare v_pre jsonb; v_nombre text; v_n integer;
begin
  if (select auth.uid()) is not null then
    raise exception 'Solo el servicio elimina clientes' using errcode = '42501';
  end if;
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada: el edge usa su ruta de siempre' using errcode = 'P0409';
  end if;
  select p.nombre_completo into v_nombre from public.perfiles p where p.id = p_perfil_id and p.rol = 'cliente' for update;
  if not found then
    raise exception 'El cliente no existe o ya fue eliminado' using errcode = 'P0002';
  end if;
  v_pre := crm.cliente_eliminable_fn(p_perfil_id);
  if coalesce((v_pre->>'eliminable')::boolean, false) is not true then
    raise exception '%', coalesce(v_pre->>'mensaje', 'El cliente no se puede eliminar')
      using errcode = 'P0409', detail = v_pre::text;
  end if;
  -- Un perfil de una saga aún sin enlazar tampoco se borra por aquí.
  if exists (select 1 from crm.multiempresa_idempotencia i
                 where i.clave like 'auth\_persona:%' and i.resultado->>'perfil_id' = p_perfil_id::text
                   and i.resultado->>'estado' <> 'enlazado') then
    raise exception 'Este cliente tiene un alta en curso (identidad unificada): espera a que termine' using errcode = 'P0409';
  end if;
  delete from public.novedades n where n.destinatario_id = p_perfil_id;
  get diagnostics v_n = row_count;
  delete from public.perfiles p where p.id = p_perfil_id;
  return pg_catalog.jsonb_build_object('ok', true, 'nombre', v_nombre, 'comunicados_borrados', v_n);
end;
$function$

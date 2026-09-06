CREATE OR REPLACE FUNCTION crm.auth_usuario_por_correo_fn(p_correo text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
    then pg_catalog.jsonb_build_object('id', null, 'apagada', true)
    else coalesce((
    select pg_catalog.jsonb_build_object('id', u.id, 'claim_id', u.raw_app_meta_data->>'claim_id',
                                         'tiene_perfil', exists (select 1 from public.perfiles p where p.id = u.id))
    from auth.users u
    where pg_catalog.lower(u.email) = pg_catalog.lower(pg_catalog.btrim(p_correo))
    limit 1), pg_catalog.jsonb_build_object('id', null)) end
$function$

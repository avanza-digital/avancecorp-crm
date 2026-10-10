CREATE OR REPLACE FUNCTION private.cliente_ids_visibles_crm()
 RETURNS TABLE(cliente_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with actor as materialized (
    select
      (select auth.uid()) as uid,
      private.rol_crm((select auth.uid())) as rol,
      private.es_lector_global() as lector,
      private.puede_acceder_crm() as acceso
  ), visibles as materialized (
    select private.vendedor_ids_visibles(a.uid) as perfil_id
    from actor a
  )
  select p.id
  from public.perfiles p
  cross join actor a
  where a.uid is not null
    and a.acceso
    and p.rol = 'cliente'
    and (
      a.lector
      or a.rol = 'gerencia'
      or p.asesor_perfil_id in (select v.perfil_id from visibles v)
      or (
        p.asesor_perfil_id is null
        and p.creado_por in (select v.perfil_id from visibles v)
      )
    );
$function$

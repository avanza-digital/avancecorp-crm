CREATE OR REPLACE FUNCTION private.sla_gestion_permitida(p_actor uuid, p_lead uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select p_actor is not null and exists (
    select 1 from crm.leads l
    where l.id=p_lead and l.activo
      and private.rol_crm(p_actor) in ('vendedor','supervisor','gerencia')
      and (private.rol_crm(p_actor)='gerencia' or l.vendedor_id=p_actor
        or (private.rol_crm(p_actor)='supervisor'
          and (l.vendedor_id in (select private.vendedor_ids_visibles(p_actor))
            or (l.vendedor_id is null and l.asignado_supervisor_id in
              (select private.vendedor_ids_visibles(p_actor))))))
  );
$function$

CREATE OR REPLACE FUNCTION private.es_lector_global()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with actor as materialized (
    select (select auth.uid()) as uid
  )
  select coalesce(private.rol_crm(a.uid) = 'directorio', false)
    or exists (
      select 1
      from public.perfiles p
      where p.id = a.uid
        and p.activo is true
        and p.rol = 'directorio'
        -- El fallback histórico solo aplica sin membresía. Una fila CRM
        -- inactiva o desalineada es revocación, nunca una segunda puerta.
        and not exists (
          select 1 from crm.equipo e where e.perfil_id = p.id
        )
    )
  from actor a;
$function$

CREATE OR REPLACE FUNCTION private.persona_vetada_perfil(p_perfil_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- F2.b [D-3]: el veto de la PERSONA visto desde un perfil cliente (tareas de cliente, actividades_cliente): por el
  -- enlace perfil↔identidad (canónica) o por el documento exacto del perfil (identificador vigente y verificado).
  -- Con la bandera apagada es siempre false (paridad con hoy).
  select coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
     and (
       exists (select 1
               from crm.inversionistas i0
               join crm.inversionistas i on i.id = coalesce(i0.inversionista_canonico_id, i0.id)
               where i0.perfil_id = p_perfil_id and i0.estado <> 'fusionado' and i.no_contactar = true)
       or exists (select 1
                  from public.perfiles p
                  join crm.inversionista_identificadores idf
                    on idf.tipo_documento = coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI')
                   and idf.documento_normalizado = pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p.dni, ''), '[^A-Za-z0-9]', '', 'g'))
                   and idf.estado = 'vigente' and idf.verificado = true
                  join crm.inversionistas i on i.id = idf.inversionista_id
                  where p.id = p_perfil_id
                    and nullif(pg_catalog.btrim(coalesce(p.dni, '')), '') is not null
                    and i.estado <> 'fusionado' and i.no_contactar = true)
     )
$function$

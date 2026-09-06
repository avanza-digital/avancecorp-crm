CREATE OR REPLACE FUNCTION private.leads_vetados_persona(p_lead_ids uuid[])
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select l.id
  from crm.leads l
  left join crm.inversionistas inv0 on inv0.id = l.inversionista_id
  left join crm.inversionistas inv  on inv.id  = coalesce(inv0.inversionista_canonico_id, inv0.id)
  where l.id = any (coalesce(p_lead_ids, array[]::uuid[]))
    and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
    and (
      l.no_contactar = true
      or coalesce(inv.no_contactar, false)
      -- F2.b [D-3]: un lead que está en el PUENTE de una persona vetada (histórico sin enlace vivo) también lo está.
      or exists (select 1
                 from crm.inversionista_leads il
                 join crm.inversionistas p0 on p0.id = il.inversionista_id
                 join crm.inversionistas p  on p.id  = coalesce(p0.inversionista_canonico_id, p0.id)
                 where il.lead_id = l.id and p.no_contactar = true)
      or (l.inversionista_id is null
          and nullif(pg_catalog.btrim(coalesce(l.dni,'')), '') is not null
          and exists (
            select 1
            from crm.inversionista_identificadores idf
            join crm.inversionistas i on i.id = idf.inversionista_id
            where idf.tipo_documento = 'DNI'
              and idf.documento_normalizado = pg_catalog.upper(pg_catalog.regexp_replace(l.dni, '[^A-Za-z0-9]', '', 'g'))
              and idf.estado = 'vigente'
              and idf.verificado = true
              and i.estado <> 'fusionado'
              and i.no_contactar = true))
    )
$function$

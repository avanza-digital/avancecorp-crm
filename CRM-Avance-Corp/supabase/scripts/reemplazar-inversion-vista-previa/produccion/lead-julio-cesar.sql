-- SOLO LECTURA. Lead «Julio César Núñez» (analista Astrid): estado del lead, acreditación, anulación, eliminaciones y
-- sus inversiones vivas (Avance y cooperativa), para saber por qué su venta no cuenta.
begin read only;
select l.nombre_completo as lead, l.etapa, (select p.nombre_completo from public.perfiles p where p.id = l.vendedor_id) as vendedor,
       to_char(l.convertido_en at time zone 'America/Lima', 'DD/MM') as convertido, l.contrato_id is not null as lead_con_contrato,
       exists (select 1 from public.contratos c where c.id = l.contrato_id) as contrato_del_lead_vivo,
       coalesce((select string_agg(ca.estado || ' ' || coalesce(ca.periodo_comercial::text, '') || ' ' || ca.fuente_tipo
                  || ' viva=' || (exists (select 1 from public.contratos c where c.id = ca.fuente_id)
                                  or exists (select 1 from crm.cierres_externos x where x.id = ca.fuente_id and x.anulado_en is null))::text
                  || ' analista=' || coalesce((select p.nombre_completo from public.perfiles p where p.id = ca.analista_id), '?'), '; ')
                 from crm.conversion_acreditaciones ca where ca.lead_id = l.id), 'ninguna') as acreditacion,
       private.cierre_anulado(l.id) as anulado,
       coalesce((select string_agg((ie.snapshot #>> '{contrato,numero_contrato}') || ' ' || to_char(ie.eliminado_en at time zone 'America/Lima', 'DD/MM') || ' reemplazo=' || (ie.reemplazada_por is not null)::text, '; ')
                 from crm.inversiones_eliminadas ie where ie.lead_id = l.id), '') as eliminadas,
       coalesce((select string_agg(c.numero_contrato || ' ' || coalesce(c.categoria, '?') || ' ' || to_char(c.creado_en at time zone 'America/Lima', 'DD/MM') || ' ' || c.capital || ' ' || c.moneda, '; ' order by c.creado_en)
                 from public.contratos c
                 where c.cliente_id = l.perfil_id or c.cliente_id in (select i.perfil_id from crm.inversionistas i where i.id = l.inversionista_id)), '') as contratos_vivos,
       coalesce((select string_agg(x.cooperativa || ' ' || to_char(x.creado_en at time zone 'America/Lima', 'DD/MM') || ' inicial=' || x.es_cierre_inicial::text || ' lead=' || coalesce((x.lead_id = l.id)::text, 'null'), '; ')
                 from crm.cierres_externos x where x.inversionista_id = l.inversionista_id and x.anulado_en is null), '') as coop_vivos
from crm.leads l
where l.nombre_completo ilike '%julio%' and (l.nombre_completo ilike '%nu_ez%' or l.nombre_completo ilike '%nunez%')
order by l.creado_en desc
limit 5;
rollback;

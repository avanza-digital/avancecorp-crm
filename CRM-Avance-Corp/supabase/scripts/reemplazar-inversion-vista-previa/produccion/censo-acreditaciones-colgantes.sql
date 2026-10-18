-- SOLO LECTURA. Censo: acreditaciones de venta cuya fuente (contrato o cierre de cooperativa) YA NO EXISTE, sin anulación
-- (no las cuenta la conversión: «fuente retirada»). Con el contrato vivo «nuevo» del mismo cliente que podría ser el recargado.
begin read only;
select l.nombre_completo as lead, coalesce((select p.nombre_completo from public.perfiles p where p.id = ca.analista_id), '—') as analista,
       ca.estado, ca.periodo_comercial::text as mes, ca.fuente_tipo, private.cierre_anulado(l.id) as anulada,
       exists (select 1 from crm.periodos_cerrados pc where pc.periodo = ca.periodo_comercial) as mes_cerrado,
       l.contrato_id is not null and not exists (select 1 from public.contratos c where c.id = l.contrato_id) as lead_colgante,
       coalesce((select string_agg(c.numero_contrato || ' ' || coalesce(c.categoria, '?') || ' ' || to_char(c.creado_en at time zone 'America/Lima', 'DD/MM')
                   || ' ' || c.capital || ' ' || c.moneda || ' analista=' || coalesce((select p.nombre_completo from public.perfiles p where p.id = c.analista_cierre_id), '?')
                   || ' acreditado_a_otro=' || exists (select 1 from crm.conversion_acreditaciones o where o.fuente_id = c.id)::text, '; ' order by c.creado_en)
                 from public.contratos c
                 where (c.cliente_id = l.perfil_id or c.cliente_id in (select i.perfil_id from crm.inversionistas i where i.id = l.inversionista_id))
                   and not c.es_demo), '') as contratos_vivos_del_cliente
from crm.conversion_acreditaciones ca
join crm.leads l on l.id = ca.lead_id
where (ca.fuente_tipo = 'contrato' and not exists (select 1 from public.contratos c where c.id = ca.fuente_id))
   or (ca.fuente_tipo = 'cierre_externo' and not exists (select 1 from crm.cierres_externos x where x.id = ca.fuente_id))
order by ca.periodo_comercial, l.nombre_completo;
rollback;

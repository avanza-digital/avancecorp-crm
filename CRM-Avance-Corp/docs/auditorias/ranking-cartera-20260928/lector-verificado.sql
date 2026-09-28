-- Captura del cuerpo compilado en la rama, después de ambas migraciones.
-- Referencia de revisión; no es otra migración ni se aplica por separado.
CREATE OR REPLACE FUNCTION private.ranking_capital_origen_filas(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo_id uuid)
 RETURNS TABLE(vendedor_id uuid, origen text, moneda text, capital numeric, categoria text, operacion_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with capital_base as materialized (
    select k.*
    from private.capital_episodios(p_ini, p_fin, true, '{}'::uuid[]) k
    where (left(k.tipo, 9) = 'contrato_' or k.tipo = 'cooperativa')
      and k.medida = 'stock'
  ), vinculos as materialized (
    select v.*
    from private.ranking_vinculos_lead_filas(
      coalesce((select array_agg(distinct k.contrato_id) filter (where k.contrato_id is not null)
                from capital_base k), '{}'::uuid[]),
      coalesce((select array_agg(distinct k.cliente_id) filter (where k.cliente_id is not null)
                from capital_base k), '{}'::uuid[]),
      coalesce((select array_agg(distinct k.lead_id) filter (where k.lead_id is not null)
                from capital_base k), '{}'::uuid[])
    ) v
  ), contratos_base as materialized (
    select c.id, c.cliente_id, c.fecha, c.categoria, c.moneda, c.capital,
      c.creado_por, c.analista_cierre_id,
      coalesce(enlaces.tiene_vendedor_explicito, false) as tiene_vendedor_explicito,
      coalesce(enlaces.vendedores_distintos, 0) as vendedores_distintos,
      enlaces.vendedor_unico,
      case
        when c.categoria <> 'nuevo' then 'cartera'
        when directo.cantidad > 0 then
          case when directo.origenes_distintos = 1 then directo.origen_unico else 'sin_origen' end
        when cliente.cantidad > 0 then
          case when cliente.origenes_distintos = 1 then cliente.origen_unico else 'sin_origen' end
        when exists (
          select 1 from crm.operaciones_cartera o
          where o.contrato_nuevo_id = c.id
            and o.cliente_id = c.cliente_id
            and o.moneda = c.moneda
            and o.fecha_operacion = c.fecha_cierre_comercial
            and o.tipo in ('upgrade', 'renovacion')
        ) then 'cartera'
        when acreditado.cantidad > 0 then
          case when acreditado.origenes_distintos = 1 then acreditado.origen_unico else 'sin_origen' end
        when private.ranking_solicitud_cartera(c.id, null::uuid) then 'cartera'
        else 'sin_origen'
      end as origen
    from (
      select k.contrato_id as id, k.cliente_id, k.categoria, k.moneda,
        k.monto as capital, k.registrado_por as creado_por,
        k.analista_id as analista_cierre_id, k.fecha,
        (k.fecha at time zone 'America/Lima')::date as fecha_cierre_comercial
      from capital_base k
      where left(k.tipo, 9) = 'contrato_'
    ) c
    left join lateral (
      select count(*) filter (where l.vendedor_id is not null) > 0 as tiene_vendedor_explicito,
        count(distinct l.vendedor_id) filter (where l.vendedor_id is not null)::integer
          as vendedores_distintos,
        case when count(distinct l.vendedor_id) filter (where l.vendedor_id is not null) = 1
          then min(l.vendedor_id::text) filter (where l.vendedor_id is not null)::uuid
        end as vendedor_unico
      from vinculos l where l.contrato_id = c.id
    ) enlaces on true
    left join lateral (
      select count(*) as cantidad,
        count(distinct coalesce(l.origen, 'sin_origen')) as origenes_distintos,
        min(coalesce(l.origen, 'sin_origen')) as origen_unico
      from vinculos l where l.contrato_id = c.id
    ) directo on true
    left join lateral (
      select count(*) as cantidad,
        count(distinct coalesce(l.origen, 'sin_origen')) as origenes_distintos,
        min(coalesce(l.origen, 'sin_origen')) as origen_unico
      from vinculos l
      where l.perfil_id = c.cliente_id and l.creado_en < c.fecha + interval '1 day'
    ) cliente on true
    left join lateral (
      select count(*) as cantidad,
        count(distinct coalesce(a.origen, 'sin_origen')) as origenes_distintos,
        min(coalesce(a.origen, 'sin_origen')) as origen_unico
      from private.ranking_origenes_acreditados_filas(array[c.id]) a
      where a.fecha_comercial = c.fecha_cierre_comercial
    ) acreditado on true
    where c.fecha_cierre_comercial >= (p_ini at time zone 'America/Lima')::date
      and c.fecha_cierre_comercial < (p_fin at time zone 'America/Lima')::date
      and c.categoria in ('nuevo', 'renovacion', 'upgrade')
      and c.moneda in ('PEN', 'USD')
  ), atribuidos as materialized (
    select base.id,
      case
        when base.analista_cierre_id is not null
          then coalesce(meta_analista.vendedor_id, base.analista_cierre_id)
        when base.vendedores_distintos > 1 then null
        when base.tiene_vendedor_explicito
          then coalesce(meta_lead.vendedor_id, base.vendedor_unico)
        else coalesce(meta_autor.vendedor_id, equipo_autor.perfil_id)
      end as vendedor_id,
      base.origen, base.categoria, base.moneda, base.capital
    from contratos_base base
    left join crm.metas_vendedor meta_lead
      on meta_lead.meta_periodo_id = p_periodo_id and meta_lead.vendedor_id = base.vendedor_unico
    left join crm.metas_vendedor meta_autor
      on meta_autor.meta_periodo_id = p_periodo_id and meta_autor.vendedor_id = base.creado_por
    left join crm.metas_vendedor meta_analista
      on meta_analista.meta_periodo_id = p_periodo_id and meta_analista.vendedor_id = base.analista_cierre_id
    left join crm.equipo equipo_autor
      on equipo_autor.perfil_id = base.creado_por and equipo_autor.rol_crm = 'vendedor'
  ), externos_confirmados as materialized (
    select ce.id, coalesce(mv.vendedor_id, ce.vendedor_id) as vendedor_id,
      case when ce.lead_id is not null then coalesce(l.origen, 'sin_origen')
        when private.ranking_solicitud_cartera(null::uuid, ce.id) then 'cartera'
        else 'sin_origen' end as origen, 'nuevo'::text as categoria,
      ce.moneda, ce.capital
    from (
      select k.cierre_externo_id as id, k.lead_id, k.analista_id as vendedor_id,
        k.moneda, k.monto as capital, k.medida, k.fecha as creado_en
      from capital_base k
      where k.tipo = 'cooperativa'
    ) ce
    left join crm.metas_vendedor mv
      on mv.meta_periodo_id = p_periodo_id and mv.vendedor_id = ce.vendedor_id
    left join vinculos l on l.id = ce.lead_id
    where ce.creado_en >= p_ini and ce.creado_en < p_fin
      and ce.medida = 'stock' and ce.moneda in ('PEN', 'USD')
  )
  select a.vendedor_id, a.origen, a.moneda, a.capital, a.categoria, a.id
  from atribuidos a where a.vendedor_id is not null
  union all
  select e.vendedor_id, e.origen, e.moneda, e.capital, e.categoria, e.id
  from externos_confirmados e;
$function$


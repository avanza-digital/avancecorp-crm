-- Entrega A: capital Avance sin origen con continuidad acreditada en el ledger.
-- Solo cambia el canal de lectura. No recategoriza contratos, no toca
-- conversión/atribución, ni la rama COOPAC, ni snapshots ya sellados.
-- Mantiene firma, tipos, owner y ACL; el helper sigue cerrado a clientes.
do $preflight$
begin
  if (select md5(prosrc) from pg_proc where oid =
      'private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)'::regprocedure)
      is distinct from '52ecf49a1c698e135a531b38ab75e291' then
    raise exception 'Cambió el lector de orígenes: revisar la base antes de instalar';
  end if;
  if (select md5(prosrc) from pg_proc where oid =
      'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure)
      is distinct from '214c6bada3dc63f553d7f9b62fd7963c'
    or (select md5(prosrc) from pg_proc where oid =
      'private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)'::regprocedure)
      is distinct from 'ecfdf7e030497af2f299ba327102a5ea' then
    raise exception 'Cambió el núcleo monetario: volver a conciliar antes de instalar';
  end if;
end;
$preflight$;

create or replace function private.ranking_capital_origen_filas(
  p_ini timestamptz, p_fin timestamptz, p_periodo_id uuid
)
returns table (
  vendedor_id uuid, origen text, moneda text, capital numeric,
  categoria text, operacion_id uuid
)
language sql stable security definer set search_path = ''
as $function$
  with contratos_base as materialized (
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
        -- Solo rescata falta de origen: los leads directos y el fallback
        -- anterior (incluso ambiguos) conservan precedencia. EXISTS evita
        -- multiplicar capital y no depende del espejo crm.inversiones.
        when exists (
          select 1 from crm.operaciones_cartera o
          where o.contrato_nuevo_id = c.id
            and o.cliente_id = c.cliente_id
            and o.moneda = c.moneda
            and o.fecha_operacion = c.fecha_cierre_comercial
            and o.tipo in ('upgrade', 'renovacion')
        ) then 'cartera'
        else 'sin_origen'
      end as origen
    from (
      select k.contrato_id as id, k.cliente_id, k.categoria, k.moneda,
        k.monto as capital, k.registrado_por as creado_por,
        k.analista_id as analista_cierre_id, k.fecha,
        (k.fecha at time zone 'America/Lima')::date as fecha_cierre_comercial
      from private.capital_episodios(p_ini, p_fin, true, '{}'::uuid[]) k
      where left(k.tipo, 9) = 'contrato_' and k.medida = 'stock'
    ) c
    left join lateral (
      select count(*) filter (where l.vendedor_id is not null) > 0 as tiene_vendedor_explicito,
        count(distinct l.vendedor_id) filter (where l.vendedor_id is not null)::integer
          as vendedores_distintos,
        case when count(distinct l.vendedor_id) filter (where l.vendedor_id is not null) = 1
          then min(l.vendedor_id::text) filter (where l.vendedor_id is not null)::uuid
        end as vendedor_unico
      from crm.leads l where l.contrato_id = c.id
    ) enlaces on true
    left join lateral (
      select count(*) as cantidad,
        count(distinct coalesce(l.origen, 'sin_origen')) as origenes_distintos,
        min(coalesce(l.origen, 'sin_origen')) as origen_unico
      from crm.leads l where l.contrato_id = c.id
    ) directo on true
    left join lateral (
      select count(*) as cantidad,
        count(distinct coalesce(l.origen, 'sin_origen')) as origenes_distintos,
        min(coalesce(l.origen, 'sin_origen')) as origen_unico
      from crm.leads l
      where l.perfil_id = c.cliente_id and l.creado_en < c.fecha + interval '1 day'
    ) cliente on true
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
      coalesce(l.origen, 'sin_origen') as origen, 'nuevo'::text as categoria,
      ce.moneda, ce.capital
    from (
      select k.cierre_externo_id as id, k.lead_id, k.analista_id as vendedor_id,
        k.moneda, k.monto as capital, k.medida, k.fecha as creado_en
      from private.capital_episodios(p_ini, p_fin, true, '{}'::uuid[]) k
      where k.tipo = 'cooperativa'
    ) ce
    left join crm.metas_vendedor mv
      on mv.meta_periodo_id = p_periodo_id and mv.vendedor_id = ce.vendedor_id
    left join crm.leads l on l.id = ce.lead_id
    where ce.creado_en >= p_ini and ce.creado_en < p_fin
      and ce.medida = 'stock' and ce.moneda in ('PEN', 'USD')
  )
  select a.vendedor_id, a.origen, a.moneda, a.capital, a.categoria, a.id
  from atribuidos a where a.vendedor_id is not null
  union all
  select e.vendedor_id, e.origen, e.moneda, e.capital, e.categoria, e.id
  from externos_confirmados e
$function$;

revoke all on function private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)
  from public, anon, authenticated, service_role;

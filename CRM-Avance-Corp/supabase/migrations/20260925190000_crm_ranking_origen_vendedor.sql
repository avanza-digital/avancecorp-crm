-- Ranking · Capital total: capital confirmado y conversión por canal del analista.
-- El detalle se concilia por moneda con la misma producción del Ranking. Los
-- meses sellados leen una foto tomada dentro de crm.cerrar_periodo; los sellos
-- anteriores a esta migración permanecen sin desglose.

do $preflight$
begin
  if (select md5(p.prosrc) from pg_proc p
      where p.oid = 'private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)'::regprocedure)
      <> 'ecfdf7e030497af2f299ba327102a5ea' then
    raise exception 'Cambió la producción canónica; revisar el desglose antes de instalarlo';
  end if;
  if (select md5(p.prosrc) from pg_proc p
      where p.oid = 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure)
      <> '214c6bada3dc63f553d7f9b62fd7963c' then
    raise exception 'Cambió el núcleo de capital; revisar el desglose';
  end if;
  if (select md5(p.prosrc) from pg_proc p
      where p.oid = 'private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])'::regprocedure)
      <> '2a933148946d42fb875a2685ea1e451a' then
    raise exception 'Cambió el núcleo de cierres; revisar la conversión';
  end if;
  if (select md5(p.prosrc) from pg_proc p
      where p.oid = 'crm.cerrar_periodo(date)'::regprocedure)
      <> 'ce1ca52d4310345f9fc512413c13f3e8' then
    raise exception 'Cambió el sello mensual; revisar el trigger antes de instalarlo';
  end if;
end;
$preflight$;

-- Una fila por contrato o cierre externo, con la atribución del productor
-- canónico. Los enlaces de leads se agregan ANTES del join: jamás multiplican
-- el capital cuando un cliente tiene varios leads.
create function private.ranking_capital_origen_filas(
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

-- Tasa mensual del canal: cierres del mes acreditados al analista, divididos
-- por leads del canal que recibió como primer analista en ese mes. Referido
-- conserva el peso del período; Wallking usa la clave técnica 'oficina'.
create function private.ranking_conversion_origen_mes(
  p_ini timestamptz, p_fin timestamptz, p_periodo date, p_factor numeric
)
returns table (
  vendedor_id uuid, origen text, leads integer, cierres integer,
  conversion_pct numeric
)
language sql stable security definer set search_path = ''
as $function$
  with llegadas as (
    select primera.analista_id as vendedor_id, l.origen, count(*)::integer as leads
    from crm.leads l
    left join lateral (
      select la.analista_id
      from crm.lead_asignaciones la
      where la.lead_id = l.id
      order by la.asignado_en, la.ciclo_n, la.episodio_n, la.id
      limit 1
    ) primera on true
    where l.creado_en >= p_ini and l.creado_en < p_fin
      and l.origen in ('landing', 'formulario', 'referido', 'oficina')
      and primera.analista_id is not null
    group by primera.analista_id, l.origen
  ), cierres as (
    select c.analista_id as vendedor_id, c.origen,
      count(*)::integer as cierres,
      sum(case when c.origen = 'referido' then p_factor else 1::numeric end) as numerador
    from private.conversion_cierres(
      p_ini, p_fin, p_periodo, true, '{}'::uuid[], p_factor, null::uuid[]
    ) c
    where c.tipo = 'cierre' and not c.anulado
      and c.origen in ('landing', 'formulario', 'referido', 'oficina')
      and c.analista_id is not null
    group by c.analista_id, c.origen
  )
  select coalesce(l.vendedor_id, c.vendedor_id), coalesce(l.origen, c.origen),
    coalesce(l.leads, 0), coalesce(c.cierres, 0),
    case when coalesce(l.leads, 0) > 0
      and (coalesce(l.origen, c.origen) <> 'referido' or p_factor is not null)
      then round(100 * coalesce(c.numerador, 0) / l.leads, 2)
    end
  from llegadas l full join cierres c
    on c.vendedor_id = l.vendedor_id and c.origen = l.origen
$function$;

revoke all on function private.ranking_conversion_origen_mes(timestamptz,timestamptz,date,numeric)
  from public, anon, authenticated, service_role;

-- Recibe el detalle del MISMO payload de metas que pinta la ficha. Si por
-- cualquier motivo no cuadra cada moneda, no publica un desglose parcial.
create function private.ranking_origen_live(
  p_periodo date, p_vendedor_id uuid, p_detalles jsonb
)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_ini timestamptz := p_periodo::timestamp at time zone 'America/Lima';
  v_fin timestamptz := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';
  v_periodo_id uuid;
  v_neto_pen numeric := 0;
  v_neto_usd numeric := 0;
  v_ajuste_pen numeric := 0;
  v_ajuste_usd numeric := 0;
  v_bruto_pen numeric := 0;
  v_bruto_usd numeric := 0;
  v_filas jsonb;
begin
  if p_detalles is null or jsonb_typeof(p_detalles) <> 'array' then
    return jsonb_build_object('disponible', false, 'filas', '[]'::jsonb);
  end if;

  select mp.id into v_periodo_id
  from crm.meta_periodos mp where mp.periodo = p_periodo
  order by mp.revision desc limit 1;

  select
    coalesce(sum((d.valor->>'capital_real')::numeric) filter (where d.valor->>'moneda' = 'PEN'), 0),
    coalesce(sum((d.valor->>'capital_real')::numeric) filter (where d.valor->>'moneda' = 'USD'), 0),
    coalesce(sum(coalesce((d.valor->>'capital_ajuste')::numeric, 0)) filter (where d.valor->>'moneda' = 'PEN'), 0),
    coalesce(sum(coalesce((d.valor->>'capital_ajuste')::numeric, 0)) filter (where d.valor->>'moneda' = 'USD'), 0)
  into v_neto_pen, v_neto_usd, v_ajuste_pen, v_ajuste_usd
  from jsonb_array_elements(p_detalles) d(valor);

  with capital_filas as materialized (
    select f.* from private.ranking_capital_origen_filas(v_ini, v_fin, v_periodo_id) f
    where f.vendedor_id = p_vendedor_id
  ), bruto as (
    select coalesce(sum(f.capital) filter (where f.moneda = 'PEN'), 0) as pen,
      coalesce(sum(f.capital) filter (where f.moneda = 'USD'), 0) as usd
    from capital_filas f
  ), capital as materialized (
    select c.origen,
      coalesce(sum(c.capital) filter (where c.moneda = 'PEN'), 0) as capital_pen,
      coalesce(sum(c.capital) filter (where c.moneda = 'USD'), 0) as capital_usd,
      count(*)::integer as contratos
    from capital_filas c
    group by c.origen
  ), conversion as materialized (
    select cv.origen, cv.leads, cv.cierres, cv.conversion_pct
    from private.ranking_conversion_origen_mes(
      v_ini, v_fin, p_periodo, private.peso_referido_conversion(p_periodo)
    ) cv
    where cv.vendedor_id = p_vendedor_id
  ), origenes as (
    select unnest(array['landing','formulario','referido','oficina']) as origen
    union select c.origen from capital c
    union select cv.origen from conversion cv
    union select 'ajuste' where v_ajuste_pen <> 0 or v_ajuste_usd <> 0
  )
  select b.pen, b.usd, coalesce(jsonb_agg(jsonb_build_object(
    'origen', o.origen,
    'capital_pen', case when o.origen = 'ajuste' then -v_ajuste_pen else coalesce(c.capital_pen, 0) end,
    'capital_usd', case when o.origen = 'ajuste' then -v_ajuste_usd else coalesce(c.capital_usd, 0) end,
    'contratos', coalesce(c.contratos, 0),
    'leads', coalesce(cv.leads, 0),
    'cierres', coalesce(cv.cierres, 0),
    'conversion_pct', cv.conversion_pct
  ) order by case o.origen
    when 'landing' then 1 when 'formulario' then 2 when 'referido' then 3
    when 'oficina' then 4 when 'cartera' then 5 when 'ajuste' then 99 else 50 end,
    o.origen), '[]'::jsonb) into v_bruto_pen, v_bruto_usd, v_filas
  from bruto b
  cross join origenes o
  left join capital c on c.origen = o.origen
  left join conversion cv on cv.origen = o.origen
  group by b.pen, b.usd;

  if v_bruto_pen <> v_neto_pen + v_ajuste_pen
    or v_bruto_usd <> v_neto_usd + v_ajuste_usd then
    return jsonb_build_object('disponible', false, 'filas', '[]'::jsonb);
  end if;

  return jsonb_build_object('disponible', true, 'filas', v_filas);
end;
$function$;

revoke all on function private.ranking_origen_live(date,uuid,jsonb)
  from public, anon, authenticated, service_role;

-- El BEFORE INSERT participa en la transacción del sello. No modifica fotos
-- antiguas ni permite cambiar una foto existente (sigue append-only).
alter table crm.cierre_mes_vendedor add column origenes_ranking jsonb;

create function private.ranking_origen_sellado_trg()
returns trigger
language plpgsql security definer set search_path = ''
as $function$
begin
  begin
    new.origenes_ranking := private.ranking_origen_live(
      new.periodo, new.vendedor_id, new.detalles
    );
  exception when others then
    -- Un desglose secundario no debe impedir el sello financiero del mes.
    raise warning 'Ranking origen no disponible al sellar % / %: SQLSTATE %',
      new.periodo, new.vendedor_id, sqlstate;
    new.origenes_ranking := jsonb_build_object(
      'disponible', false, 'filas', '[]'::jsonb
    );
  end;
  return new;
end;
$function$;

revoke all on function private.ranking_origen_sellado_trg()
  from public, anon, authenticated, service_role;

create trigger trg_cierre_mes_vendedor_10_ranking_origen
before insert on crm.cierre_mes_vendedor
for each row execute function private.ranking_origen_sellado_trg();

-- El acceso usa la lista de vendedores del payload autoritativo, con el mismo
-- ámbito de Gerencia/Supervisión y la misma foto del mes seleccionado.
create function crm.ranking_origen_vendedor_fn(p_periodo date, p_vendedor_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_base jsonb;
  v_vendedor jsonb;
  v_detalle jsonb;
  v_cerrado boolean;
begin
  if p_periodo is null or p_periodo <> date_trunc('month', p_periodo)::date
    or p_vendedor_id is null then
    raise exception 'Periodo o analista inválido' using errcode = '22023';
  end if;

  v_base := crm.cumplimiento_metas_fn(p_periodo);
  select e.valor into v_vendedor
  from jsonb_array_elements(coalesce(v_base->'vendedores', '[]'::jsonb)) e(valor)
  where e.valor->>'vendedor_id' = p_vendedor_id::text;
  if v_vendedor is null then
    raise exception 'Analista fuera del ámbito' using errcode = '42501';
  end if;

  v_cerrado := coalesce((v_base #>> '{cierre,cerrado}')::boolean, false);
  if v_cerrado then
    select s.origenes_ranking into v_detalle
    from crm.cierre_mes_vendedor s
    where s.periodo = p_periodo and s.vendedor_id = p_vendedor_id;
  else
    v_detalle := private.ranking_origen_live(
      p_periodo, p_vendedor_id, v_vendedor->'detalles'
    );
  end if;

  return jsonb_build_object(
    'version', 1, 'periodo', p_periodo, 'vendedor_id', p_vendedor_id
  ) || coalesce(v_detalle, jsonb_build_object(
    'disponible', false, 'filas', '[]'::jsonb
  ));
end;
$function$;

revoke all on function crm.ranking_origen_vendedor_fn(date,uuid) from public, anon;
grant execute on function crm.ranking_origen_vendedor_fn(date,uuid)
  to authenticated, service_role;

comment on function crm.ranking_origen_vendedor_fn(date,uuid) is
  'Detalle del Ranking por canal. Capital neto conciliado por moneda con cumplimiento_metas_fn; conversión mensual ponderada por origen. Mes sellado: foto inmutable; mes antiguo sin foto: no disponible.';

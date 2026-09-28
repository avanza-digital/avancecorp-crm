-- Desglose de Cartera sobre el mismo stock del Ranking. La categoría financiera
-- del contrato permanece intacta; los contratos antiguos usan su operación válida.
-- RPC v2 aditiva: el payload v1 sigue idéntico para navegadores ya abiertos.
begin;
do $preflight$
begin
  if (select md5(prosrc) from pg_proc where oid =
    'private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)'::regprocedure)
    is distinct from '2770f326df798e511a1d81b1e0ca8af7' then
    raise exception 'Cambió el universo de capital del Ranking';
  end if;
end;
$preflight$;

create function private.ranking_cartera_desglose(
  p_periodo date, p_vendedor_id uuid, p_origenes jsonb
)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_periodo_id uuid;
  v_desglose jsonb;
  v_pen numeric;
  v_usd numeric;
  v_esperado_pen numeric;
  v_esperado_usd numeric;
begin
  if coalesce((p_origenes->>'disponible')::boolean, false) = false then return null; end if;
  select mp.id into v_periodo_id from crm.meta_periodos mp
    where mp.periodo = p_periodo order by mp.revision desc limit 1;
  select coalesce(sum((x->>'capital_pen')::numeric), 0),
    coalesce(sum((x->>'capital_usd')::numeric), 0)
  into v_esperado_pen, v_esperado_usd
  from jsonb_array_elements(p_origenes->'filas') x where x->>'origen' = 'cartera';

  with filas as materialized (
    select f.moneda, f.capital,
      case when f.categoria in ('renovacion', 'upgrade') then f.categoria
        when o.tipo in ('renovacion', 'upgrade') then o.tipo
        else 'sin_clasificar' end as categoria
    from private.ranking_capital_origen_filas(
      p_periodo::timestamp at time zone 'America/Lima',
      (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima',
      v_periodo_id) f
    left join public.contratos c on c.id = f.operacion_id
    -- contrato_nuevo_id es UNIQUE: jamás multiplica el capital. No usamos la
    -- elegibilidad de conversión para excluir stock confirmado del Ranking.
    left join crm.operaciones_cartera o on o.contrato_nuevo_id = c.id
      and o.cliente_id = c.cliente_id and o.moneda = f.moneda
      and o.fecha_operacion = c.fecha_cierre_comercial
    where f.vendedor_id = p_vendedor_id and f.origen = 'cartera'
  ), categorias as (
    select unnest(array['renovacion', 'upgrade', 'sin_clasificar']) as categoria
  ), detalle as (
    select t.categoria,
      coalesce(sum(f.capital) filter (where f.moneda = 'PEN'), 0) as pen,
      coalesce(sum(f.capital) filter (where f.moneda = 'USD'), 0) as usd
    from categorias t left join filas f using (categoria) group by t.categoria
  )
  select jsonb_agg(to_jsonb(d) order by array_position(
      array['renovacion', 'upgrade', 'sin_clasificar'], d.categoria)),
    sum(d.pen), sum(d.usd)
  into v_desglose, v_pen, v_usd from detalle d;

  if v_pen <> v_esperado_pen or v_usd <> v_esperado_usd then return null; end if;
  return v_desglose;
end;
$function$;
alter function private.ranking_cartera_desglose(date,uuid,jsonb) owner to postgres;
revoke all on function private.ranking_cartera_desglose(date,uuid,jsonb)
  from public, anon, authenticated, service_role;

-- Fotos anteriores quedan NULL: no reconstruimos historia cerrada con datos vivos.
alter table crm.cierre_mes_vendedor add column cartera_ranking jsonb;
create function private.ranking_cartera_sellado_trg()
returns trigger
language plpgsql security definer set search_path = ''
as $function$
begin
  begin
    new.cartera_ranking := private.ranking_cartera_desglose(
      new.periodo, new.vendedor_id, new.origenes_ranking);
  exception when others then
    raise warning 'Ranking cartera no disponible al sellar % / %: SQLSTATE %',
      new.periodo, new.vendedor_id, sqlstate;
    new.cartera_ranking := null;
  end;
  return new;
end;
$function$;
alter function private.ranking_cartera_sellado_trg() owner to postgres;
revoke all on function private.ranking_cartera_sellado_trg()
  from public, anon, authenticated, service_role;
create trigger trg_cierre_mes_vendedor_11_ranking_cartera
before insert on crm.cierre_mes_vendedor
for each row execute function private.ranking_cartera_sellado_trg();

-- El permiso se resuelve en la puerta vigente, antes de consultar cartera.
create function crm.ranking_origen_vendedor_v2_fn(p_periodo date, p_vendedor_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_base jsonb;
  v_cartera jsonb;
begin
  v_base := crm.ranking_origen_vendedor_fn(p_periodo, p_vendedor_id);
  if coalesce((v_base->>'disponible')::boolean, false) then
    if exists(select 1 from crm.periodos_cerrados where periodo = p_periodo) then
      select s.cartera_ranking into v_cartera from crm.cierre_mes_vendedor s
        where s.periodo = p_periodo and s.vendedor_id = p_vendedor_id;
    else
      v_cartera := private.ranking_cartera_desglose(p_periodo, p_vendedor_id, v_base);
    end if;
  end if;
  return v_base || jsonb_build_object('version', 2, 'cartera', v_cartera);
end;
$function$;
alter function crm.ranking_origen_vendedor_v2_fn(date,uuid) owner to postgres;
revoke all on function crm.ranking_origen_vendedor_v2_fn(date,uuid) from public, anon;
grant execute on function crm.ranking_origen_vendedor_v2_fn(date,uuid) to authenticated, service_role;
comment on function crm.ranking_origen_vendedor_v2_fn(date,uuid) is
  'Ranking por origen v2: conserva v1 y añade Cartera conciliada por moneda con la categoría u operación acreditada. Mes cerrado: foto inmutable.';

do $postflight$
begin
  if exists(select 1 from private.contadores_crudos_leads_citas()
    where not declarada or not huella_ok) then
    raise exception 'Contadores analíticos sin declarar o huellas caducas';
  end if;
end;
$postflight$;
notify pgrst, 'reload schema';
commit;

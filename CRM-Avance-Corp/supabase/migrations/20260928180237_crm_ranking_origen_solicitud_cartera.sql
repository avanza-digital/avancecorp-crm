-- Procedencia confirmada desde Mi cartera. Decisión de Miguel 28/09:
-- Cartera → Nueva inversión, sin convertirla en renovación ni upgrade.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
do $preflight$
begin
 if (select md5(prosrc) from pg_proc where oid='private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)'::regprocedure)
 is distinct from '2770f326df798e511a1d81b1e0ca8af7' then raise exception 'Cambió el lector de Ranking';end if;
end;
$preflight$;

create function private.ranking_solicitud_cartera(p_contrato_id uuid, p_cierre_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $function$
 select exists (
  select 1 from crm.inversiones i
  join crm.inversion_solicitudes s on s.inversion_id=i.id and s.empresa_id=i.empresa_id
  where s.estado='confirmada' and s.puerta='cartera' and s.lead_origen_id is null
    and ((p_contrato_id is not null and p_cierre_id is null
      and i.contrato_id=p_contrato_id and s.resultado#>>'{fuente,id}'=p_contrato_id::text)
    or (p_cierre_id is not null and p_contrato_id is null
      and i.cierre_externo_id=p_cierre_id and s.resultado#>>'{fuente,cierre_id}'=p_cierre_id::text))
 );
$function$;
alter function private.ranking_solicitud_cartera(uuid,uuid) owner to postgres;
revoke all on function private.ranking_solicitud_cartera(uuid,uuid) from public,anon,authenticated,service_role;
comment on function private.ranking_solicitud_cartera(uuid,uuid) is
 'Procedencia acreditada por solicitud confirmada desde Mi cartera y fuente económica exacta. No infiere captación, identidad, categoría financiera ni conversión.';

do $lector$
declare
 v_def text:=pg_get_functiondef('private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)'::regprocedure);
 v_patron text;
begin
 v_patron:=E'          case when acreditado.origenes_distintos = 1 then acreditado.origen_unico else ''sin_origen'' end\n        else ''sin_origen''';
 if (length(v_def)-length(replace(v_def,v_patron,'')))/length(v_patron)<>1 then raise exception 'Fallback Avance no único';end if;
 v_def:=replace(v_def,v_patron,E'          case when acreditado.origenes_distintos = 1 then acreditado.origen_unico else ''sin_origen'' end\n        when private.ranking_solicitud_cartera(c.id, null::uuid) then ''cartera''\n        else ''sin_origen''');
 v_patron:='      coalesce(l.origen, ''sin_origen'') as origen, ''nuevo''::text as categoria,';
 if (length(v_def)-length(replace(v_def,v_patron,'')))/length(v_patron)<>1 then raise exception 'Fallback COOPAC no único';end if;
 v_def:=replace(v_def,v_patron,E'      case when ce.lead_id is not null then coalesce(l.origen, ''sin_origen'')\n        when private.ranking_solicitud_cartera(null::uuid, ce.id) then ''cartera''\n        else ''sin_origen'' end as origen, ''nuevo''::text as categoria,');
 execute v_def;
end;
$lector$;

create or replace function private.ranking_cartera_desglose(
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
        when f.categoria = 'nuevo' and private.ranking_solicitud_cartera(
          c.id, case when c.id is null then f.operacion_id end) then 'nuevo'
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
    select unnest(array['renovacion', 'upgrade', 'nuevo', 'sin_clasificar']) as categoria
  ), detalle as (
    select t.categoria,
      coalesce(sum(f.capital) filter (where f.moneda = 'PEN'), 0) as pen,
      coalesce(sum(f.capital) filter (where f.moneda = 'USD'), 0) as usd
    from categorias t left join filas f using (categoria) group by t.categoria
  )
  select jsonb_agg(to_jsonb(d) order by array_position(
      array['renovacion', 'upgrade', 'nuevo', 'sin_clasificar'], d.categoria)),
    sum(d.pen), sum(d.usd)
  into v_desglose, v_pen, v_usd from detalle d;

  if v_pen <> v_esperado_pen or v_usd <> v_esperado_usd then return null; end if;
  return v_desglose;
end;
$function$;
alter function private.ranking_cartera_desglose(date,uuid,jsonb) owner to postgres;
revoke all on function private.ranking_cartera_desglose(date,uuid,jsonb)
  from public, anon, authenticated, service_role;

-- Actualiza solo la declaración existente del lector modificado; no añade
-- exenciones, no cambia clases y no eleva el techo de contadores.
do $huella$
declare v_filas integer;
begin
  update private.analitica_leads_citas_exenciones e
  set huella = md5(regexp_replace(regexp_replace(lower(p.prosrc),
      '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
  from pg_proc p
  where p.oid = 'private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)'::regprocedure
    and e.objeto = 'private.ranking_capital_origen_filas(timestamp with time zone,timestamp with time zone,uuid)'
    and e.clase = 'analitica';
  get diagnostics v_filas = row_count;
  if v_filas <> 1 then raise exception 'Se esperaba actualizar una sola declaración analítica'; end if;
end;
$huella$;
update private.analitica_lc_sello
set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
where id;

do $postflight$
begin
  if exists (select 1 from private.contadores_crudos_leads_citas()
      where not declarada or not huella_ok) then
    raise exception 'El cambio dejó contadores sin declarar o huellas caducas';
  end if;
  if not exists (select 1 from private.analitica_leads_citas_exenciones
      where objeto = 'private.ranking_capital_origen_filas(timestamp with time zone,timestamp with time zone,uuid)'
        and clase = 'analitica') then
    raise exception 'Falta la declaración analítica del lector';
  end if;
  if (select md5(prosrc) from pg_proc where oid =
      'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure)
      is distinct from '214c6bada3dc63f553d7f9b62fd7963c'
    or (select md5(prosrc) from pg_proc where oid =
      'private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)'::regprocedure)
      is distinct from 'ecfdf7e030497af2f299ba327102a5ea' then
    raise exception 'Cambió el núcleo monetario';
  end if;
end;
$postflight$;
commit;

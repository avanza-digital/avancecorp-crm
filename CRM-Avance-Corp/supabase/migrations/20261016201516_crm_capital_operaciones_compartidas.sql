-- Una proyección de hechos stock y una atribución comercial por operación.
-- Conserva firma, dimensiones, asimetrías y resultado del agregado vigente.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);

do $$ begin
  if (select md5(prosrc) from pg_proc where oid='private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure)
      is distinct from 'c87bec9506d8b9d2ce0f215895a34e18'
    or (select md5(prosrc) from pg_proc where oid='private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)'::regprocedure)
      is distinct from 'ecfdf7e030497af2f299ba327102a5ea' then
    raise exception 'El núcleo vigente cambió: rebasar y volver a comparar antes de migrar';
  end if;
end $$;

create temp table tc_produccion_antes on commit drop as
select mes::date as periodo,mp.id as periodo_id,
  (select coalesce(jsonb_agg(to_jsonb(r) order by r.vendedor_id,r.categoria,r.moneda),'[]'::jsonb)
    from private.produccion_mes_por_vendedor(mes at time zone 'America/Lima',
      (mes+interval '1 month') at time zone 'America/Lima',mp.id) r) as datos
from generate_series(timestamp '2025-12-01',date_trunc('month',statement_timestamp() at time zone 'America/Lima'),interval '1 month') mes
left join lateral(select m.id from crm.meta_periodos m where m.periodo=mes::date order by m.revision desc limit 1) mp on true;

create function private.capital_operaciones_base(p_ini timestamptz,p_fin timestamptz)
returns table(fuente text,fuente_id uuid,tipo text,medida text,contrato_id uuid,cierre_externo_id uuid,
  lead_id uuid,cliente_id uuid,analista_id uuid,registrado_por uuid,en_roster boolean,
  moneda text,monto numeric,categoria text,mes_comercial date,fecha timestamptz,
  fecha_vencimiento date,estado text,anulado boolean,fecha_comercial date)
language sql stable security definer set search_path='' as $$
  select case when e.contrato_id is not null then 'contrato' else 'cierre_externo' end,
    coalesce(e.contrato_id,e.cierre_externo_id),e.*,
    case when e.contrato_id is not null then c.fecha_cierre_comercial else ce.fecha_comercial end
  from private.capital_episodios(p_ini,p_fin,true,'{}'::uuid[]) e
  left join public.contratos c on c.id=e.contrato_id
  left join crm.cierres_externos ce on ce.id=e.cierre_externo_id
  where e.medida='stock';
$$;
alter function private.capital_operaciones_base(timestamptz,timestamptz) owner to postgres;
revoke all on function private.capital_operaciones_base(timestamptz,timestamptz) from public,anon,authenticated,service_role;

do $extraer$
declare
  v_src text; v_prefix text; v_final text; v_body text; v_pos integer;
  v_ancla text:=E'\n  select confirmados.vendedor_id, confirmados.categoria, confirmados.moneda,';
  v_origen text:='from private.capital_episodios(p_ini, p_fin, true, ''{}''::uuid[]) k';
  v_externo text:=E'    select\n      coalesce(mv.vendedor_id, ce.vendedor_id) as vendedor_id,';
begin
  select prosrc into strict v_src from pg_proc
    where oid='private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)'::regprocedure;
  if (length(v_src)-length(replace(v_src,v_ancla,'')))/length(v_ancla)<>1
    or (length(v_src)-length(replace(v_src,v_origen,'')))/length(v_origen)<>2
    or (length(v_src)-length(replace(v_src,v_externo,'')))/length(v_externo)<>1 then
    raise exception 'Las anclas de la proyección vigente no coinciden exactamente';
  end if;
  v_pos:=strpos(v_src,v_ancla);
  v_prefix:=left(v_src,v_pos-1);
  v_prefix:=replace(v_prefix,'  with contratos_base as materialized (',
    E'  with operaciones_base as materialized (\n    select * from private.capital_operaciones_base(p_ini,p_fin)\n  ), contratos_base as materialized (');
  v_prefix:=replace(v_prefix,v_origen,'from operaciones_base k');
  v_prefix:=replace(v_prefix,v_externo,
    E'    select ce.id,\n      coalesce(mv.vendedor_id, ce.vendedor_id) as vendedor_id,');
  v_final:=$sql$
  select 'contrato'::text,cc.id,cc.vendedor_id,cc.categoria,cc.moneda,cc.capital,
    b.fecha_comercial,(b.fecha at time zone 'America/Lima')::date
  from contratos_confirmados cc
  join operaciones_base b on b.fuente='contrato' and b.fuente_id=cc.id
  where cc.vendedor_id is not null
  union all
  select 'cierre_externo'::text,ec.id,ec.vendedor_id,ec.categoria,ec.moneda,ec.capital,
    b.fecha_comercial,(b.fecha at time zone 'America/Lima')::date
  from externos_confirmados ec
  join operaciones_base b on b.fuente='cierre_externo' and b.fuente_id=ec.id
  $sql$;
  v_body:=v_prefix||v_final;
  execute format('create function private.produccion_operaciones(p_ini timestamptz,p_fin timestamptz,p_periodo_id uuid)
    returns table(fuente text,fuente_id uuid,vendedor_id uuid,categoria text,moneda text,capital numeric,
      fecha_comercial date,fecha_imputacion date)
    language sql stable security definer set search_path='''' as %L',v_body);
end $extraer$;
alter function private.produccion_operaciones(timestamptz,timestamptz,uuid) owner to postgres;
revoke all on function private.produccion_operaciones(timestamptz,timestamptz,uuid) from public,anon,authenticated,service_role;

create or replace function private.produccion_mes_por_vendedor(p_ini timestamptz,p_fin timestamptz,p_periodo_id uuid)
returns table(vendedor_id uuid,categoria text,moneda text,contratos_real integer,capital_real numeric)
language sql stable security definer set search_path='' as $$
  select o.vendedor_id,o.categoria,o.moneda,count(*)::integer,coalesce(sum(o.capital),0)
  from private.produccion_operaciones(p_ini,p_fin,p_periodo_id) o
  group by o.vendedor_id,o.categoria,o.moneda;
$$;

create or replace function private.capital_fuentes_tc()
returns table(fuente text,fuente_id uuid,fecha_comercial date,fecha_imputacion date,
  moneda text,monto numeric,firma_fuente text)
language sql stable security definer set search_path='' as $$
  select b.fuente,b.fuente_id,b.fecha_comercial,(b.fecha at time zone 'America/Lima')::date,
    b.moneda,b.monto,
    md5(jsonb_build_array(b.fuente,b.fuente_id,b.fecha_comercial,b.moneda,b.monto)::text)
  from private.capital_operaciones_base('-infinity'::timestamptz,'infinity'::timestamptz) b;
$$;

do $comprobar$
declare f record; v_despues jsonb;
begin
  if exists(select 1 from private.capital_fuentes_tc() s group by s.fuente,s.fuente_id having count(*)<>1) then
    raise exception 'La identidad stock no es única; no es seguro compartir la valoración';
  end if;
  for f in select * from tc_produccion_antes loop
    select coalesce(jsonb_agg(to_jsonb(r) order by r.vendedor_id,r.categoria,r.moneda),'[]'::jsonb)
      into v_despues
    from private.produccion_mes_por_vendedor(f.periodo::timestamp at time zone 'America/Lima',
      (f.periodo+interval '1 month')::timestamp at time zone 'America/Lima',f.periodo_id) r;
    if v_despues is distinct from f.datos then
      raise exception 'La extracción cambió la producción del mes %',f.periodo;
    end if;
  end loop;
end $comprobar$;

comment on function private.produccion_operaciones(timestamptz,timestamptz,uuid) is
  'Proyección por fuente/id con la atribución comercial vigente y ambas fechas. Conserva los NULL de cooperativas y filtros asimétricos del agregado previo.';
comment on function private.capital_operaciones_base(timestamptz,timestamptz) is
  'Hechos stock del núcleo: una fuente financiera por id. Fecha comercial para valorar, fecha del episodio para imputar; sin desgloses duplicados.';
commit;

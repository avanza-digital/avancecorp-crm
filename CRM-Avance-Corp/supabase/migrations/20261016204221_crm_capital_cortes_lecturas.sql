-- Publicaciones completas de capital y ámbitos compartidos. Los endpoints v1
-- siguen conservando sus firmas/payloads; los datos nuevos nacen sin activar.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);

do $$ begin
  if (select md5(prosrc) from pg_proc where oid='private.capital_autorizada(date,date,text)'::regprocedure)
      is distinct from 'dc499b1f12693e6e724ef93848dda1ac'
    or (select md5(prosrc) from pg_proc where oid='private.facturacion_operaciones_visibles(timestamptz,timestamptz)'::regprocedure)
      is distinct from '6e1cf1659424a6b56bc8c56f10c1b8ae' then
    raise exception 'La autorización vigente cambió: revisar ámbitos antes de instalar las lecturas';
  end if;
end $$;

create function private.ambito_capital_confirmado()
returns table(es_global boolean,visibles uuid[])
language plpgsql stable security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_rol text:=private.rol_crm((select auth.uid()));
begin
  if v_uid is null then raise exception 'No autorizado' using errcode='42501'; end if;
  es_global:=coalesce(v_rol='gerencia',false) or (select private.es_lector_global());
  visibles:='{}'::uuid[];
  if not es_global then
    visibles:=array(select private.vendedor_ids_visibles(v_uid));
    if coalesce(array_length(visibles,1),0)=0 then
      raise exception 'No autorizado' using errcode='42501';
    end if;
  end if;
  return next;
end $$;
alter function private.ambito_capital_confirmado() owner to postgres;
revoke all on function private.ambito_capital_confirmado() from public,anon,authenticated,service_role;

create function private.ambito_facturacion()
returns table(uid uuid,es_global boolean,ok boolean,subarbol uuid[])
language sql stable set search_path='' as $$
  with quien as materialized(
    select (select auth.uid()) as uid,private.rol_crm((select auth.uid())) as rol,
      private.es_lector_global() or private.es_coordinador_reportes() as lector)
  select q.uid,coalesce(q.uid is not null and(q.rol='gerencia' or q.lector),false),
    coalesce(q.uid is not null and(q.rol in('gerencia','supervisor') or q.lector),false),
    case when coalesce(q.uid is not null and q.rol='supervisor',false)
      then array(select private.vendedor_ids_visibles(q.uid)) else '{}'::uuid[] end
  from quien q;
$$;
alter function private.ambito_facturacion() owner to postgres;
revoke all on function private.ambito_facturacion() from public,anon,authenticated,service_role;

-- Sustituir solo la resolución de ámbito; preservar validaciones, orden de
-- errores y recortes del lector existente. No cambia su EXECUTE ni dueño.
do $ambitos$
declare v_src text; v_inicio integer; v_fin integer; v_ancla text;
begin
  select prosrc into v_src from pg_proc where oid='private.capital_autorizada(date,date,text)'::regprocedure;
  v_inicio:=strpos(v_src,'  v_global := coalesce');
  v_fin:=strpos(v_src,'  return query select * from private.capital_episodios(');
  if v_inicio=0 or v_fin<=v_inicio then raise exception 'No coincide el ámbito de capital'; end if;
  v_src:=left(v_src,v_inicio-1)||E'  select a.es_global,a.visibles into v_global,v_visibles from private.ambito_capital_confirmado() a;\n'
    ||substring(v_src from v_fin);
  execute format('create or replace function private.capital_autorizada(p_desde date,p_hasta date,p_medida text)
    returns table(tipo text,medida text,contrato_id uuid,cierre_externo_id uuid,lead_id uuid,cliente_id uuid,
      analista_id uuid,registrado_por uuid,en_roster boolean,moneda text,monto numeric,categoria text,
      mes_comercial date,fecha timestamptz,fecha_vencimiento date,estado text,anulado boolean)
    language plpgsql stable security definer set search_path='''' as %L',v_src);
  select prosrc into v_src from pg_proc where oid='private.facturacion_operaciones_visibles(timestamptz,timestamptz)'::regprocedure;
  v_ancla:=E'\n  select ep.*\n'; v_fin:=strpos(v_src,v_ancla);
  if v_fin=0 then raise exception 'No coincide el ámbito de facturación'; end if;
  v_src:=E'\n  with ambito as materialized(select * from private.ambito_facturacion())'||substring(v_src from v_fin);
  execute format('create or replace function private.facturacion_operaciones_visibles(p_desde timestamptz,p_hasta timestamptz)
    returns table(operacion_id uuid,dia date,fecha timestamptz,tipo text,moneda text,monto numeric,
      analista_id uuid,supervisor_id uuid,contrato_id uuid,cierre_externo_id uuid,cliente_id uuid,
      lead_id uuid,registrado_por uuid,categoria text,estado text,anulado boolean,fecha_vencimiento date)
    language sql stable set search_path='''' as %L',v_src);
end $ambitos$;

create table crm.capital_cortes_valorados(
  id uuid primary key default gen_random_uuid(),
  periodo date not null check(periodo=date_trunc('month',periodo)::date),
  corte date not null check(corte>=periodo and corte<(periodo+interval '1 month')::date),
  revision integer not null check(revision>0),
  meta_periodo_id uuid references crm.meta_periodos(id),
  meta_revision integer not null default 0,
  base jsonb not null check(jsonb_typeof(base)='array'),
  produccion jsonb not null check(jsonb_typeof(produccion)='array'),
  facturacion jsonb not null check(jsonb_typeof(facturacion)='array'),
  metas jsonb not null check(jsonb_typeof(metas)='array'),
  personas jsonb not null check(jsonb_typeof(personas)='array'),
  huella text not null,
  creado_en timestamptz not null default statement_timestamp(),
  unique(periodo,revision)
);
alter table crm.capital_cortes_valorados enable row level security;
alter table crm.capital_cortes_valorados owner to postgres;
create index capital_cortes_ultimo on crm.capital_cortes_valorados(periodo,revision desc);
create table crm.capital_mes_sellos(
  periodo date primary key references crm.periodos_cerrados(periodo),
  corte_id uuid not null references crm.capital_cortes_valorados(id),
  creado_en timestamptz not null default statement_timestamp()
);
alter table crm.capital_mes_sellos enable row level security;
alter table crm.capital_mes_sellos owner to postgres;
create trigger trg_capital_cortes_inmutables before update or delete on crm.capital_cortes_valorados
  for each row execute function private.capital_tc_inmutable();
create trigger trg_capital_cortes_sin_truncate before truncate on crm.capital_cortes_valorados
  for each statement execute function private.capital_tc_inmutable();
create trigger trg_capital_sellos_inmutables before update or delete on crm.capital_mes_sellos
  for each row execute function private.capital_tc_inmutable();
create trigger trg_capital_sellos_sin_truncate before truncate on crm.capital_mes_sellos
  for each statement execute function private.capital_tc_inmutable();
create trigger trg_audit_capital_cortes after insert on crm.capital_cortes_valorados
  for each row execute function private.log_audit_crm();
create trigger trg_audit_capital_sellos after insert on crm.capital_mes_sellos
  for each row execute function private.log_audit_crm();
revoke all on crm.capital_cortes_valorados,crm.capital_mes_sellos from public,anon,authenticated,service_role;

create function private.capital_valoraciones_actuales(p_ini timestamptz,p_fin timestamptz)
returns table(fuente text,fuente_id uuid,valoracion_id uuid,equivalente_pen numeric,
  tasa numeric,fecha_tc date,politica_tc text,revision integer)
language sql stable security definer set search_path='' as $$
  select b.fuente,b.fuente_id,v.id,v.equivalente_pen,v.tasa,v.fecha_tc,v.politica_tc,v.revision
  from private.capital_operaciones_base(p_ini,p_fin) b
  left join lateral(select a.* from crm.capital_valoraciones a
    where a.fuente=b.fuente and a.fuente_id=b.fuente_id order by a.revision desc limit 1) ultimo on true
  left join crm.capital_valoraciones v on v.id=ultimo.id
    and v.firma_fuente=md5(jsonb_build_array(b.fuente,b.fuente_id,b.fecha_comercial,b.moneda,b.monto)::text)
    and v.fecha_comercial=b.fecha_comercial and v.moneda=b.moneda and v.monto=b.monto;
$$;
alter function private.capital_valoraciones_actuales(timestamptz,timestamptz) owner to postgres;
revoke all on function private.capital_valoraciones_actuales(timestamptz,timestamptz) from public,anon,authenticated,service_role;

create function private.publicar_corte_capital(p_periodo date)
returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_ini timestamptz; v_fin timestamptz; v_hasta date; v_corte date; v_meta uuid; v_revision integer;
  v_ultimo crm.capital_cortes_valorados%rowtype; v_sellado uuid; v_id uuid;
  v_base jsonb; v_produccion jsonb; v_facturacion jsonb; v_metas jsonb; v_personas jsonb; v_huella text; v_completo boolean;
begin
  if p_periodo is null or p_periodo<>date_trunc('month',p_periodo)::date
    or p_periodo<(select vigente_desde from crm.capital_valoracion_politica where id) then
    raise exception 'Periodo de valoración inválido' using errcode='22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(hashtext('crm.capital_cortes_valorados'),(p_periodo-date '2000-01-01')::integer);
  select corte_id into v_sellado from crm.capital_mes_sellos where periodo=p_periodo;
  if v_sellado is not null then return v_sellado; end if;
  select * into v_ultimo from crm.capital_cortes_valorados where periodo=p_periodo order by revision desc limit 1;
  v_hasta:=least((p_periodo+interval '1 month - 1 day')::date,(statement_timestamp() at time zone 'America/Lima')::date);
  if v_hasta<p_periodo then return v_ultimo.id; end if;
  v_ini:=p_periodo::timestamp at time zone 'America/Lima';
  v_fin:=(v_hasta+1)::timestamp at time zone 'America/Lima';
  select least(v_hasta,coalesce(min((b.fecha at time zone 'America/Lima')::date)-1,v_hasta))
    into v_corte
  from private.capital_operaciones_base(v_ini,v_fin) b
  join private.capital_valoraciones_actuales(v_ini,v_fin) a using(fuente,fuente_id)
  where a.valoracion_id is null;
  if v_corte<p_periodo or (v_ultimo.id is not null and v_corte<v_ultimo.corte) then return v_ultimo.id; end if;
  v_fin:=(v_corte+1)::timestamp at time zone 'America/Lima';
  select mp.id,mp.revision into v_meta,v_revision from crm.meta_periodos mp
    where mp.periodo=p_periodo order by mp.revision desc limit 1;
  -- Una sola sentencia comparte snapshot para las cuatro proyecciones.
  with hechos as materialized(select b.*,a.valoracion_id,a.equivalente_pen,a.tasa,a.fecha_tc,a.politica_tc,
      a.revision as revision_valoracion
    from private.capital_operaciones_base(v_ini,v_fin) b
    join private.capital_valoraciones_actuales(v_ini,v_fin) a using(fuente,fuente_id)),
  operaciones as materialized(select p.*,h.valoracion_id,h.equivalente_pen,h.tasa,h.fecha_tc,h.politica_tc
    from private.produccion_operaciones(v_ini,v_fin,v_meta) p join hechos h using(fuente,fuente_id)),
  facturas as materialized(select f.*,h.fuente,h.fuente_id,h.valoracion_id,h.equivalente_pen,h.tasa,
      h.fecha_comercial,h.fecha_tc,h.politica_tc
    from private.facturacion_operaciones(v_ini,v_fin) f join hechos h
      on h.fuente_id=f.operacion_id and h.fuente=case when f.contrato_id is not null then 'contrato' else 'cierre_externo' end)
  select (select coalesce(jsonb_agg(to_jsonb(h) order by h.fuente,h.fuente_id),'[]') from hechos h),
    (select coalesce(jsonb_agg(to_jsonb(p) order by p.fuente,p.fuente_id),'[]') from operaciones p),
    (select coalesce(jsonb_agg(to_jsonb(f) order by f.dia,f.fuente,f.fuente_id),'[]') from facturas f),
    (select coalesce(jsonb_agg(jsonb_build_object('vendedor_id',m.vendedor_id,'categoria',d.categoria,
      'moneda',d.moneda,'capital_objetivo',d.capital_objetivo,'contratos_objetivo',d.contratos_objetivo)
      order by m.vendedor_id,d.categoria,d.moneda),'[]')
      from crm.metas_vendedor m join crm.metas_vendedor_detalle d on d.meta_vendedor_id=m.id
      where m.meta_periodo_id=v_meta),
    (select coalesce(jsonb_agg(jsonb_build_object('vendedor_id',pe.id,'nombre',coalesce(pf.nombre_completo,'Sin nombre'),
      'supervisor_id',coalesce(m.supervisor_id,e.supervisor_id),'supervisor_nombre',coalesce(ps.nombre_completo,'Sin supervisor'),
      'en_meta',m.id is not null,'rol_crm',coalesce(e.rol_crm,'fuera_equipo'),
      'motivo',case when e.rol_crm='vendedor' and es.rol_crm='supervisor' then 'analista_sin_meta'
        when e.rol_crm='vendedor' then 'analista_sin_supervisor' when e.rol_crm='supervisor' then 'supervisor'
        when e.rol_crm='gerencia' then 'gerencia' else 'fuera_estructura' end) order by pe.id),'[]')
      from (select vendedor_id as id from operaciones union
        select vendedor_id from crm.metas_vendedor where meta_periodo_id=v_meta) pe
      left join crm.metas_vendedor m on m.vendedor_id=pe.id and m.meta_periodo_id=v_meta
      left join crm.equipo e on e.perfil_id=pe.id
      left join crm.equipo es on es.perfil_id=e.supervisor_id
      left join public.perfiles pf on pf.id=pe.id
      left join public.perfiles ps on ps.id=coalesce(m.supervisor_id,e.supervisor_id)),
    (select coalesce(bool_and(h.valoracion_id is not null),true) from hechos h)
    into v_base,v_produccion,v_facturacion,v_metas,v_personas,v_completo;
  if not v_completo then return v_ultimo.id; end if;
  v_huella:=md5(jsonb_build_array(v_corte,v_meta,v_base,v_produccion,v_facturacion,v_metas,v_personas)::text);
  if v_ultimo.huella is not distinct from v_huella then return v_ultimo.id; end if;
  insert into crm.capital_cortes_valorados(periodo,corte,revision,meta_periodo_id,meta_revision,
    base,produccion,facturacion,metas,personas,huella)
  values(p_periodo,v_corte,coalesce(v_ultimo.revision,0)+1,v_meta,coalesce(v_revision,0),
    v_base,v_produccion,v_facturacion,v_metas,v_personas,v_huella) returning id into v_id;
  return v_id;
end $$;
alter function private.publicar_corte_capital(date) owner to postgres;
revoke all on function private.publicar_corte_capital(date) from public,anon,authenticated,service_role;

create or replace function crm.reconciliar_capital_valoraciones_fn(p_limite integer default 200)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_resultado jsonb; v_periodo date; v_cortes integer:=0;
begin
  v_resultado:=private.materializar_capital_valoraciones(p_limite);
  for v_periodo in select d::date from generate_series(
    (select vigente_desde::timestamp from crm.capital_valoracion_politica where id),
    date_trunc('month',statement_timestamp() at time zone 'America/Lima'),interval '1 month') d
  loop
    if private.publicar_corte_capital(v_periodo) is not null then v_cortes:=v_cortes+1; end if;
  end loop;
  return v_resultado||jsonb_build_object('meses_con_corte',v_cortes);
end $$;

-- Solo el dato global de mercado y las filas autorizadas entran al payload;
-- las tablas privadas de cortes no reciben SELECT para el navegador.
create function private.capital_resumen_corte(p_corte uuid,p_vendedor uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('version',1,'corte',c.corte,'generado_en',c.creado_en,'corte_id',c.id,
    'equivalente_pen',coalesce((select sum((p->>'equivalente_pen')::numeric) from jsonb_array_elements(c.produccion) p
      where (p->>'vendedor_id')::uuid is not distinct from p_vendedor),0),
    'capital_pen',coalesce((select sum((p->>'capital')::numeric) from jsonb_array_elements(c.produccion) p
      where (p->>'vendedor_id')::uuid is not distinct from p_vendedor and p->>'moneda'='PEN'),0),
    'capital_usd',coalesce((select sum((p->>'capital')::numeric) from jsonb_array_elements(c.produccion) p
      where (p->>'vendedor_id')::uuid is not distinct from p_vendedor and p->>'moneda'='USD'),0),
    'contratos',(select count(*) from jsonb_array_elements(c.produccion) p
      where (p->>'vendedor_id')::uuid is not distinct from p_vendedor),
    'objetivo_pen',coalesce((select sum((m->>'capital_objetivo')::numeric) from jsonb_array_elements(c.metas) m
      where (m->>'vendedor_id')::uuid=p_vendedor and m->>'moneda'='PEN'),0),
    'meta_revision',c.meta_revision,
    'detalles',(select jsonb_agg(jsonb_build_object('categoria',d.categoria,'moneda',d.moneda,
      'capital_real',coalesce((select sum((p->>'capital')::numeric) from jsonb_array_elements(c.produccion) p
        where (p->>'vendedor_id')::uuid=p_vendedor and p->>'categoria'=d.categoria and p->>'moneda'=d.moneda),0),
      'equivalente_pen',coalesce((select sum((p->>'equivalente_pen')::numeric) from jsonb_array_elements(c.produccion) p
        where (p->>'vendedor_id')::uuid=p_vendedor and p->>'categoria'=d.categoria and p->>'moneda'=d.moneda),0),
      'contratos_real',(select count(*) from jsonb_array_elements(c.produccion) p
        where (p->>'vendedor_id')::uuid=p_vendedor and p->>'categoria'=d.categoria and p->>'moneda'=d.moneda),
      'capital_objetivo',coalesce((select sum((m->>'capital_objetivo')::numeric) from jsonb_array_elements(c.metas) m
        where (m->>'vendedor_id')::uuid=p_vendedor and m->>'categoria'=d.categoria and m->>'moneda'=d.moneda),0),
      'contratos_objetivo',coalesce((select sum((m->>'contratos_objetivo')::integer) from jsonb_array_elements(c.metas) m
        where (m->>'vendedor_id')::uuid=p_vendedor and m->>'categoria'=d.categoria and m->>'moneda'=d.moneda),0)
      ) order by d.categoria,d.moneda)
      from(values('nuevo','PEN'),('nuevo','USD'),('renovacion','PEN'),('renovacion','USD'),('upgrade','PEN'),('upgrade','USD')) d(categoria,moneda)))
  from crm.capital_cortes_valorados c where c.id=p_corte;
$$;
alter function private.capital_resumen_corte(uuid,uuid) owner to postgres;
revoke all on function private.capital_resumen_corte(uuid,uuid) from public,anon,authenticated,service_role;

-- El llamador suministra únicamente identidades ya recortadas por su puerta.
-- No se publican totales de pendientes de otros equipos o analistas.
create function private.capital_estado_corte(p_periodo date,p_corte uuid,p_visibles jsonb)
returns jsonb language sql stable security definer set search_path='' as $$
  with corte as materialized(select * from crm.capital_cortes_valorados where id=p_corte),
  visibles as materialized(select * from jsonb_to_recordset(p_visibles) v(fuente text,fuente_id uuid)),
  hechos as materialized(select b.*,a.valoracion_id from private.capital_operaciones_base(
    p_periodo::timestamp at time zone 'America/Lima',
    (p_periodo+interval '1 month')::timestamp at time zone 'America/Lima') b
    join visibles v using(fuente,fuente_id)
    join private.capital_valoraciones_actuales(p_periodo::timestamp at time zone 'America/Lima',
      (p_periodo+interval '1 month')::timestamp at time zone 'America/Lima') a using(fuente,fuente_id)),
  por_incorporar as materialized(select h.* from hechos h where h.valoracion_id is null or not exists(
    select 1 from corte c,jsonb_array_elements(c.base) e
      where e->>'fuente'=h.fuente and (e->>'fuente_id')::uuid=h.fuente_id
        and (e->>'valoracion_id')::uuid=h.valoracion_id)),
  pendientes as materialized(select * from hechos where valoracion_id is null),
  resumen as(select count(*) as cantidad,coalesce(sum(monto) filter(where moneda='PEN'),0) as pen,
    coalesce(sum(monto) filter(where moneda='USD'),0) as usd from pendientes)
  select jsonb_build_object('corte',(select corte from corte),'generado_en',(select creado_en from corte),
    'estado',case when r.cantidad>0 and statement_timestamp()>private.cierre_mes_ventana_desde(p_periodo)+interval '24 hours'
      then 'atascado' when r.cantidad>0 or exists(select 1 from por_incorporar) then 'pendiente'
      when p_corte is null then 'sin_corte' else 'completo' end,
    'pendientes',jsonb_build_object('cantidad',r.cantidad,'pen',r.pen,'usd',r.usd),
    'por_incorporar',(select jsonb_build_object('cantidad',count(*),
      'pen',coalesce(sum(monto) filter(where moneda='PEN'),0),'usd',coalesce(sum(monto) filter(where moneda='USD'),0)) from por_incorporar),
    'ventas_pendientes',(select coalesce(jsonb_agg(jsonb_build_object('fuente',p.fuente,'fuente_id',p.fuente_id,
      'fecha_comercial',p.fecha_comercial,'fecha_imputacion',(p.fecha at time zone 'America/Lima')::date,
      'moneda',p.moneda,'monto',p.monto,'motivo',case when p.fecha_comercial is null then 'fecha_comercial_sin_acreditar'
        when p.moneda='USD' and not exists(select 1 from crm.tipo_cambio_diario t where
          t.fecha_corte=case when p.fecha_comercial>=date '2026-10-01' then p.fecha_comercial
            else (date_trunc('month',p.fecha_comercial)+interval '1 month - 1 day')::date end
          and t.politica=case when p.fecha_comercial>=date '2026-10-01' then 'sbs_punto_medio_7d_v1'
            else 'sbs_punto_medio_hasta7_legado_v1' end) then 'cotizacion_pendiente' else 'revision_pendiente' end)
      order by p.fecha,p.fuente,p.fuente_id),'[]') from pendientes p))
  from resumen r;
$$;
alter function private.capital_estado_corte(date,uuid,jsonb) owner to postgres;
revoke all on function private.capital_estado_corte(date,uuid,jsonb) from public,anon,authenticated,service_role;

create function crm.cumplimiento_metas_v2_fn(p_periodo date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_base jsonb; v_corte uuid; v_cerrado boolean; v_personas jsonb; v_visibles jsonb;
  v_uid uuid:=(select auth.uid()); v_rol text:=private.rol_crm((select auth.uid()));
  v_global boolean; v_ids uuid[];
begin
  -- La puerta anterior determina autenticación, población y ámbito histórico.
  v_base:=crm.cumplimiento_metas_fn(p_periodo);
  if p_periodo<(select vigente_desde from crm.capital_valoracion_politica where id)
    or (not(select activa from crm.capital_valoracion_politica where id)
      and not exists(select 1 from crm.capital_mes_sellos where periodo=p_periodo)) then return v_base; end if;
  v_cerrado:=coalesce((v_base#>>'{cierre,cerrado}')::boolean,false);
  if v_cerrado then
    select corte_id into v_corte from crm.capital_mes_sellos where periodo=p_periodo;
    if v_corte is null then raise exception 'El mes no tiene un sello de valoración compatible' using errcode='P0409'; end if;
  else
    select id into v_corte from crm.capital_cortes_valorados where periodo=p_periodo order by revision desc limit 1;
  end if;
  v_base:=jsonb_set(v_base,'{vendedores}',coalesce((
    select jsonb_agg(v||jsonb_build_object('capital_valorado',private.capital_resumen_corte(v_corte,(v->>'vendedor_id')::uuid)) order by n)
    from jsonb_array_elements(v_base->'vendedores') with ordinality t(v,n)),'[]'));
  if v_base ? 'fuera_ranking' then
    v_base:=jsonb_set(v_base,'{fuera_ranking}',coalesce((
      select jsonb_agg(v||jsonb_build_object('capital_valorado',private.capital_resumen_corte(v_corte,(v->>'persona_id')::uuid)) order by n)
      from jsonb_array_elements(v_base->'fuera_ranking') with ordinality t(v,n)),'[]'));
  end if;
  v_global:=coalesce(v_rol='gerencia',false) or private.es_lector_global() or private.es_coordinador_reportes();
  v_ids:=array(select private.vendedor_ids_visibles(v_uid));
  -- La población de capital sale del mismo corte que sus importes/metas. Una
  -- carga o corrección pendiente no puede ocultar un productor de la última foto.
  select coalesce(jsonb_agg(p||jsonb_build_object('en_ranking',case when v_cerrado then exists(
      select 1 from jsonb_array_elements(v_base->'vendedores') v where v->>'vendedor_id'=p->>'vendedor_id')
      else (p->>'en_meta')::boolean end,
      'capital_valorado',private.capital_resumen_corte(v_corte,(p->>'vendedor_id')::uuid)) order by p->>'nombre'),'[]')
    into v_personas from crm.capital_cortes_valorados c,jsonb_array_elements(c.personas) p
    where c.id=v_corte and (v_global or case when v_cerrado then exists(
      select 1 from jsonb_array_elements(v_base->'vendedores') v where v->>'vendedor_id'=p->>'vendedor_id')
      else ((p->>'en_meta')::boolean and (p->>'vendedor_id')::uuid=any(v_ids)) end
      or (v_rol='supervisor' and (p->>'vendedor_id')::uuid=v_uid and p->>'rol_crm'='supervisor'));
  select coalesce(jsonb_agg(jsonb_build_object('fuente',b.fuente,'fuente_id',b.fuente_id)),'[]') into v_visibles
    from private.capital_operaciones_base(p_periodo::timestamp at time zone 'America/Lima',
      (p_periodo+interval '1 month')::timestamp at time zone 'America/Lima') b
    where v_global or exists(select 1 from private.produccion_operaciones(
      p_periodo::timestamp at time zone 'America/Lima',(p_periodo+interval '1 month')::timestamp at time zone 'America/Lima',
      (select meta_periodo_id from crm.capital_cortes_valorados where id=v_corte)) pr
      where pr.fuente=b.fuente and pr.fuente_id=b.fuente_id
        and (pr.vendedor_id=any(v_ids) or (v_rol='supervisor' and pr.vendedor_id=v_uid)));
  return v_base||jsonb_build_object('capital_valoracion',jsonb_build_object('activa',true,'version',1,
    'corte_id',v_corte,'sellado',v_cerrado,'personas',v_personas,'cobertura',
    case when v_cerrado then jsonb_build_object('estado','completo','corte',
      (select corte from crm.capital_cortes_valorados where id=v_corte),'pendientes',jsonb_build_object('cantidad',0,'pen',0,'usd',0),
      'por_incorporar',jsonb_build_object('cantidad',0,'pen',0,'usd',0),'ventas_pendientes','[]'::jsonb)
    else private.capital_estado_corte(p_periodo,v_corte,v_visibles) end));
end $$;
alter function crm.cumplimiento_metas_v2_fn(date) owner to postgres;
revoke all on function crm.cumplimiento_metas_v2_fn(date) from public,anon,service_role;
grant execute on function crm.cumplimiento_metas_v2_fn(date) to authenticated;

create function crm.capital_operaciones_valoradas_fn(p_periodo date,p_vendedor_id uuid,p_corte_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_base jsonb; v_id uuid; v_corte crm.capital_cortes_valorados%rowtype; v_operaciones jsonb;
begin
  v_base:=crm.cumplimiento_metas_v2_fn(p_periodo);
  if p_vendedor_id is null then raise exception 'Se requiere un analista' using errcode='22023'; end if;
  if not(v_base ? 'capital_valoracion') then return jsonb_build_object('version',1,'valoracion_activa',false); end if;
  if not exists(select 1 from jsonb_array_elements(v_base#>'{capital_valoracion,personas}') p
    where (p->>'vendedor_id')::uuid=p_vendedor_id) then
    raise exception 'Analista fuera del ámbito autorizado' using errcode='42501';
  end if;
  v_id:=coalesce(p_corte_id,(v_base#>>'{capital_valoracion,corte_id}')::uuid);
  select * into v_corte from crm.capital_cortes_valorados where id=v_id and periodo=p_periodo;
  if v_corte.id is null or ((v_base#>>'{capital_valoracion,sellado}')::boolean
    and v_id is distinct from (v_base#>>'{capital_valoracion,corte_id}')::uuid) then
    raise exception 'El corte no corresponde a la consulta autorizada' using errcode='PT409';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('fuente',p->>'fuente','fuente_id',(p->>'fuente_id')::uuid,
    'numero',coalesce(c.numero_contrato,ce.numero_transaccion,left(p->>'fuente_id',8)),
    'fecha_comercial',p->>'fecha_comercial','fecha_imputacion',p->>'fecha_imputacion',
    'categoria',p->>'categoria','moneda',p->>'moneda','monto',(p->>'capital')::numeric,
    'tasa',(p->>'tasa')::numeric,'equivalente_pen',(p->>'equivalente_pen')::numeric,
    'valoracion_id',(p->>'valoracion_id')::uuid,'fecha_tc',p->>'fecha_tc','politica_tc',p->>'politica_tc'
    ) order by p->>'fecha_imputacion',p->>'fuente',p->>'fuente_id'),'[]') into v_operaciones
  from jsonb_array_elements(v_corte.produccion) p
  left join public.contratos c on p->>'fuente'='contrato' and c.id=(p->>'fuente_id')::uuid
  left join crm.cierres_externos ce on p->>'fuente'='cierre_externo' and ce.id=(p->>'fuente_id')::uuid
  where (p->>'vendedor_id')::uuid=p_vendedor_id;
  return jsonb_build_object('version',1,'valoracion_activa',true,'corte_id',v_corte.id,'corte',v_corte.corte,
    'operaciones',v_operaciones,'total_pen',(private.capital_resumen_corte(v_corte.id,p_vendedor_id)->>'equivalente_pen')::numeric);
end $$;
alter function crm.capital_operaciones_valoradas_fn(date,uuid,uuid) owner to postgres;
revoke all on function crm.capital_operaciones_valoradas_fn(date,uuid,uuid) from public,anon,service_role;
grant execute on function crm.capital_operaciones_valoradas_fn(date,uuid,uuid) to authenticated;

create function crm.facturacion_diaria_v2_fn(p_mes date default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_mes date:=coalesce(date_trunc('month',p_mes)::date,date_trunc('month',statement_timestamp() at time zone 'America/Lima')::date);
  v_corte crm.capital_cortes_valorados%rowtype; v_ambito record; v_filas jsonb; v_visibles jsonb; v_sellado boolean;
begin
  select * into v_ambito from private.ambito_facturacion();
  if v_ambito.ok is distinct from true then raise exception 'No autorizado' using errcode='42501'; end if;
  if v_mes<(select vigente_desde from crm.capital_valoracion_politica where id)
    or (not(select activa from crm.capital_valoracion_politica where id)
      and not exists(select 1 from crm.capital_mes_sellos where periodo=v_mes)) then
    return jsonb_build_object('version',2,'valoracion_activa',false,'filas',
      (select coalesce(jsonb_agg(to_jsonb(f)),'[]') from crm.facturacion_diaria_fn(v_mes) f));
  end if;
  v_sellado:=exists(select 1 from crm.periodos_cerrados where periodo=v_mes);
  if v_sellado then
    select c.* into v_corte from crm.capital_mes_sellos s join crm.capital_cortes_valorados c on c.id=s.corte_id where s.periodo=v_mes;
    if v_corte.id is null then raise exception 'El mes no tiene un sello de valoración compatible' using errcode='P0409'; end if;
  else
    select * into v_corte from crm.capital_cortes_valorados where periodo=v_mes order by revision desc limit 1;
  end if;
  with filas as (
    select f.*,pf.nombre_completo as analista_nombre,ps.nombre_completo as supervisor_nombre
    from jsonb_to_recordset(coalesce(v_corte.facturacion,'[]')) f(dia date,tipo text,moneda text,monto numeric,
      equivalente_pen numeric,analista_id uuid,supervisor_id uuid)
    left join public.perfiles pf on pf.id=f.analista_id left join public.perfiles ps on ps.id=f.supervisor_id
    where v_ambito.es_global or f.supervisor_id=any(v_ambito.subarbol) or f.analista_id=v_ambito.uid),
  agrupadas as(select dia,tipo,moneda,analista_id,coalesce(analista_nombre,'Sin analista') as analista_nombre,
    supervisor_id,coalesce(supervisor_nombre,'Sin supervisor') as supervisor_nombre,
    count(*) as operaciones,sum(monto) as capital,sum(equivalente_pen) as capital_equivalente_pen
    from filas group by dia,tipo,moneda,analista_id,analista_nombre,supervisor_id,supervisor_nombre)
  select coalesce(jsonb_agg(to_jsonb(a) order by a.dia,a.moneda,a.capital desc),'[]') into v_filas from agrupadas a;
  select coalesce(jsonb_agg(jsonb_build_object('fuente',case when f.contrato_id is not null then 'contrato' else 'cierre_externo' end,
    'fuente_id',f.operacion_id)),'[]') into v_visibles from private.facturacion_operaciones_visibles(
      v_mes::timestamp at time zone 'America/Lima',(v_mes+interval '1 month')::timestamp at time zone 'America/Lima') f;
  return jsonb_build_object('version',2,'valoracion_activa',true,'corte_id',v_corte.id,'corte',v_corte.corte,
    'generado_en',v_corte.creado_en,'filas',v_filas,'cobertura',case when v_sellado then
      jsonb_build_object('estado','completo','corte',v_corte.corte,'pendientes',jsonb_build_object('cantidad',0,'pen',0,'usd',0),
        'por_incorporar',jsonb_build_object('cantidad',0,'pen',0,'usd',0),'ventas_pendientes','[]'::jsonb)
      else private.capital_estado_corte(v_mes,v_corte.id,v_visibles) end);
end $$;
alter function crm.facturacion_diaria_v2_fn(date) owner to postgres;
revoke all on function crm.facturacion_diaria_v2_fn(date) from public,anon,service_role;
grant execute on function crm.facturacion_diaria_v2_fn(date) to authenticated;

comment on table crm.capital_cortes_valorados is
  'Publicaciones completas e inmutables de capital por operación. Incluyen importes, cantidades y metas del mismo corte; la conversión comercial sigue su núcleo independiente.';
commit;

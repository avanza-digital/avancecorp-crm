-- P-0XX: publicar las operaciones valoradas hasta hoy aunque otra venta espere TC.
-- Los pendientes siguen por capital_estado_corte; no entran a importes ni cantidades.
-- El sello mensual conserva sus comprobaciones de cobertura antes y después del bloqueo.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);

do $$ begin
  if (select md5(prosrc) from pg_proc where oid='private.publicar_corte_capital(date)'::regprocedure)
    is distinct from '629ec2c60834ab1dc72abcbef8542486' then
    raise exception 'Cambió el publicador de capital: revisar proyecciones, identidad y huella antes de aplicar';
  end if;
end $$;

create or replace function private.publicar_corte_capital(p_periodo date)
returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_ini timestamptz; v_fin timestamptz; v_hasta date; v_corte date; v_meta uuid; v_revision integer;
  v_ultimo crm.capital_cortes_valorados%rowtype; v_sellado uuid; v_id uuid;
  v_base jsonb; v_produccion jsonb; v_facturacion jsonb; v_metas jsonb; v_personas jsonb; v_huella text;
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
  -- La falta de TC de una operación no detiene las ventas ya valoradas.
  v_corte:=v_hasta;
  select mp.id,mp.revision into v_meta,v_revision from crm.meta_periodos mp
    where mp.periodo=p_periodo order by mp.revision desc limit 1;
  -- Una sola sentencia comparte snapshot para las cuatro proyecciones.
  with hechos as materialized(select b.*,a.valoracion_id,a.equivalente_pen,a.tasa,a.fecha_tc,a.politica_tc,
      a.revision as revision_valoracion
    from private.capital_operaciones_base(v_ini,v_fin) b
    join private.capital_valoraciones_actuales(v_ini,v_fin) a using(fuente,fuente_id)
    where a.valoracion_id is not null),
  operaciones as materialized(select p.*,h.valoracion_id,h.equivalente_pen,h.tasa,h.fecha_tc,h.politica_tc
    from private.produccion_operaciones(v_ini,v_fin,v_meta) p join hechos h using(fuente,fuente_id)),
  facturas as materialized(select f.*,h.fuente,h.fuente_id,h.valoracion_id,h.equivalente_pen,h.tasa,
      h.fecha_comercial,h.fecha_tc,h.politica_tc
    from private.facturacion_operaciones(v_ini,v_fin) f join hechos h
      on h.fuente_id=f.operacion_id and h.fuente=case when f.contrato_id is not null then 'contrato' else 'cierre_externo' end)
  select (select coalesce(jsonb_agg(to_jsonb(h)||jsonb_build_object('identidad_persona',private.citas_identidad_capital(h.cliente_id,h.lead_id,h.cierre_externo_id)) order by h.fuente,h.fuente_id),'[]') from hechos h),
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
      left join public.perfiles ps on ps.id=coalesce(m.supervisor_id,e.supervisor_id))
    into v_base,v_produccion,v_facturacion,v_metas,v_personas;
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

comment on function private.publicar_corte_capital(date) is
  'Publica las operaciones con valoración vigente hasta hoy, sin bloquearlas por pendientes de TC. Mantiene identidad, huella e historia inmutable. El sello mensual exige cobertura completa por su propia puerta.';

-- Puerta nueva: el cliente anterior valida estrictamente el payload de v1.
-- Reutiliza su autorización del analista/corte antes de consultar pendientes.
create function crm.capital_operaciones_valoradas_v2_fn(
  p_periodo date,p_vendedor_id uuid,p_corte_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_resultado jsonb; v_corte crm.capital_cortes_valorados%rowtype;
  v_visibles jsonb; v_cobertura jsonb;
begin
  v_resultado:=crm.capital_operaciones_valoradas_fn(p_periodo,p_vendedor_id,p_corte_id);
  if (v_resultado->>'valoracion_activa')::boolean is not true then return v_resultado; end if;
  select * into strict v_corte from crm.capital_cortes_valorados
    where id=(v_resultado->>'corte_id')::uuid;
  if exists(select 1 from crm.capital_mes_sellos where periodo=p_periodo) then
    v_cobertura:=jsonb_build_object('estado','completo','corte',v_corte.corte,
      'generado_en',v_corte.creado_en,'pendientes',jsonb_build_object('cantidad',0,'pen',0,'usd',0),
      'por_incorporar',jsonb_build_object('cantidad',0,'pen',0,'usd',0),'ventas_pendientes','[]'::jsonb);
  else
    select coalesce(jsonb_agg(jsonb_build_object('fuente',p.fuente,'fuente_id',p.fuente_id)),'[]')
      into v_visibles from private.produccion_operaciones(
        p_periodo::timestamp at time zone 'America/Lima',
        (p_periodo+interval '1 month')::timestamp at time zone 'America/Lima',v_corte.meta_periodo_id) p
      where p.vendedor_id=p_vendedor_id;
    v_cobertura:=private.capital_estado_corte(p_periodo,v_corte.id,v_visibles);
  end if;
  return v_resultado||jsonb_build_object('cobertura',v_cobertura);
end $$;
alter function crm.capital_operaciones_valoradas_v2_fn(date,uuid,uuid) owner to postgres;
revoke all on function crm.capital_operaciones_valoradas_v2_fn(date,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function crm.capital_operaciones_valoradas_v2_fn(date,uuid,uuid) to authenticated;
comment on function crm.capital_operaciones_valoradas_v2_fn(date,uuid,uuid) is
  'Detalle valorado del mismo corte y pendientes actuales del analista autorizado. No modifica el payload v1 ni revela pendientes de otros analistas.';
notify pgrst,'reload schema';
commit;

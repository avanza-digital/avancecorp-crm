-- Detalle de Facturación sobre el mismo corte que la malla. Se comparte la
-- lógica vigente de filtros, paginación y PII; las RPC v1/v2 no cambian payload.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);

do $$ begin
  if (select md5(prosrc) from pg_proc where oid='private.facturacion_lista(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)'::regprocedure)
    is distinct from 'f9d42ef87cd1acf2cbed94caca1db996'
    or (select md5(prosrc) from pg_proc where oid='private.facturacion_lista_nombres(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)'::regprocedure)
    is distinct from '1f611c3a29e3c5594d6baa8243c56700' then
    raise exception 'Cambió el lector de Facturación: revisar filtros y PII antes de integrar cortes';
  end if;
end $$;

create function private.facturacion_operaciones_para_lista(p_desde timestamptz,p_hasta timestamptz,p_cortes jsonb)
returns table(operacion_id uuid,dia date,fecha timestamptz,tipo text,moneda text,monto numeric,
  analista_id uuid,supervisor_id uuid,contrato_id uuid,cierre_externo_id uuid,cliente_id uuid,
  lead_id uuid,registrado_por uuid,categoria text,estado text,anulado boolean,fecha_vencimiento date,
  equivalente_pen numeric,tasa numeric,fecha_comercial date,fecha_tc date,politica_tc text)
language plpgsql stable security definer set search_path='' as $$
declare v_ambito record; v_mes date; v_corte crm.capital_cortes_valorados%rowtype; v_sello uuid; v_id uuid;
begin
  if p_cortes is null then
    return query select f.*,null::numeric,null::numeric,null::date,null::date,null::text
      from private.facturacion_operaciones_visibles(p_desde,p_hasta) f;
    return;
  end if;
  select * into v_ambito from private.ambito_facturacion();
  if v_ambito.ok is distinct from true then raise exception 'No autorizado' using errcode='42501'; end if;
  if jsonb_typeof(p_cortes) is distinct from 'object' or pg_column_size(p_cortes)>6000
    or exists(select 1 from jsonb_each_text(p_cortes) k where k.key !~ '^\d{4}-\d{2}-01$'
      or k.value is null or k.value !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
    raise exception 'Referencias de cortes inválidas' using errcode='22023';
  end if;
  for v_mes in select d::date from generate_series(
    date_trunc('month',p_desde at time zone 'America/Lima'),
    date_trunc('month',(p_hasta-interval '1 microsecond') at time zone 'America/Lima'),interval '1 month') d loop
    if v_mes<date '2026-10-01' then
      -- Régimen anterior: conserva la fuente y las monedas. El cliente usa el
      -- corte mensual legado al presentar un rango mixto, nunca el TC de hoy.
      return query select f.*,case when f.moneda='PEN' then f.monto end,
        case when f.moneda='PEN' then 1::numeric end,
        case when f.contrato_id is not null then c.fecha_cierre_comercial else ce.fecha_comercial end,
        null::date,null::text
      from private.facturacion_operaciones_visibles(greatest(p_desde,v_mes::timestamp at time zone 'America/Lima'),
        least(p_hasta,(v_mes+interval '1 month')::timestamp at time zone 'America/Lima')) f
      left join public.contratos c on c.id=f.contrato_id
      left join crm.cierres_externos ce on ce.id=f.cierre_externo_id;
      continue;
    end if;
    select s.corte_id into v_sello from crm.capital_mes_sellos s where s.periodo=v_mes;
    if v_sello is null and not(select activa from crm.capital_valoracion_politica where id) then
      raise exception 'La presentación cambió; actualizar la malla antes de abrir su detalle' using errcode='PT409';
    end if;
    v_id:=(p_cortes->>v_mes::text)::uuid;
    select * into v_corte from crm.capital_cortes_valorados c where c.id=v_id and c.periodo=v_mes;
    if v_corte.id is null or (v_sello is not null and v_sello<>v_id) then
      raise exception 'Falta el corte de la malla o no corresponde al sello del mes' using errcode='PT409';
    end if;
    return query select f.* from jsonb_to_recordset(v_corte.facturacion) f(
      operacion_id uuid,dia date,fecha timestamptz,tipo text,moneda text,monto numeric,
      analista_id uuid,supervisor_id uuid,contrato_id uuid,cierre_externo_id uuid,cliente_id uuid,
      lead_id uuid,registrado_por uuid,categoria text,estado text,anulado boolean,fecha_vencimiento date,
      equivalente_pen numeric,tasa numeric,fecha_comercial date,fecha_tc date,politica_tc text)
    where f.fecha>=p_desde and f.fecha<p_hasta
      and (v_ambito.es_global or f.supervisor_id=any(v_ambito.subarbol) or f.analista_id=v_ambito.uid);
  end loop;
end $$;
alter function private.facturacion_operaciones_para_lista(timestamptz,timestamptz,jsonb) owner to postgres;
revoke all on function private.facturacion_operaciones_para_lista(timestamptz,timestamptz,jsonb) from public,anon,authenticated,service_role;

-- Extraer una sola implementación por puerta. Los lectores originales son
-- wrappers con p_cortes=NULL, que no añade campos ni cambia sus filas/totales.
do $compartir$
declare
  v_nombre text; v_src text; v_args text; v_llamada text; v_copia text;
  v_fuente text:=E'    ) o\n    where';
  v_final text:=E'''[]''::jsonb)) into v_resultado;';
begin
  for v_nombre in select unnest(array['facturacion_lista','facturacion_lista_nombres']) loop
    select p.prosrc,pg_get_function_arguments(p.oid) into strict v_src,v_args from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='private' and p.proname=v_nombre;
    if strpos(v_src,v_fuente)=0 or strpos(v_src,v_final)=0
      or strpos(v_src,'from private.facturacion_operaciones_visibles(')=0
      or strpos(v_src,'p_hasta - p_desde > 30')=0 then
      raise exception 'No coinciden las anclas del lector %',v_nombre;
    end if;
    v_copia:=replace(v_src,'from private.facturacion_operaciones_visibles(','from private.facturacion_operaciones_para_lista(');
    -- Solo el contrato nuevo permite rangos que agregan varios cortes mensuales.
    v_copia:=replace(v_copia,'p_hasta - p_desde > 30','p_hasta - p_desde > (case when p_cortes is null then 30 else 365 end)');
    v_copia:=replace(v_copia,v_fuente,E'    ,p_cortes) o\n    where');
    v_copia:=replace(v_copia,E'    ) || case when',E'    ) || case when p_cortes is null then ''{}''::jsonb else jsonb_build_object(\n'
      ||E'      ''equivalente_pen'',d.equivalente_pen,''tasa'',d.tasa,''fecha_comercial'',d.fecha_comercial,\n'
      ||E'      ''fecha_tc'',d.fecha_tc,''politica_tc'',d.politica_tc) end || case when');
    v_copia:=replace(v_copia,E'  )\n  select jsonb_build_object(''version'', 1',
      E'  ), por_mes as (\n    select date_trunc(''month'',f.dia)::date as mes,f.moneda,count(*) as operaciones,sum(f.monto) as monto,\n'
      ||E'      case when bool_and(f.equivalente_pen is not null) then sum(f.equivalente_pen) end as equivalente_pen\n'
      ||E'    from filtradas f group by date_trunc(''month'',f.dia)::date,f.moneda\n  )\n  select jsonb_build_object(''version'', 1');
    v_copia:=replace(v_copia,v_final,E'''[]''::jsonb)) || case when p_cortes is null then ''{}''::jsonb else jsonb_build_object(\n'
      ||E'    ''cortes'',p_cortes,''totales_por_mes'',coalesce((select jsonb_agg(to_jsonb(t) order by t.mes,t.moneda) from por_mes t),''[]''::jsonb)) end into v_resultado;');
    v_copia:=replace(v_copia,'return private.facturacion_lista(', 'return private.facturacion_lista_base(');
    if v_nombre='facturacion_lista_nombres' then
      v_copia:=replace(v_copia,'p_moneda, p_pagina, p_tamano);','p_moneda, p_pagina, p_tamano,p_cortes);');
    end if;
    execute format('create function private.%I(%s,p_cortes jsonb default null) returns jsonb
      language plpgsql stable set search_path='''' as %L',v_nombre||'_base',v_args,v_copia);
    execute format('alter function private.%I(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer,jsonb) owner to postgres',v_nombre||'_base');
    execute format('revoke all on function private.%I(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer,jsonb) from public,anon,authenticated,service_role',v_nombre||'_base');
    v_llamada:=format('select private.%I(p_desde,p_hasta,p_dias,p_analistas,p_sin_analista,p_equipo,p_sin_equipo,p_tipos,p_moneda,p_pagina,p_tamano,null);',v_nombre||'_base');
    execute format('create or replace function private.%I(%s) returns jsonb language sql stable set search_path='''' as %L',v_nombre,v_args,v_llamada);
  end loop;
end $compartir$;

create function crm.listar_operaciones_facturacion_v3_fn(p_desde date,p_hasta date,
  p_dias date[] default null,p_analistas uuid[] default null,p_sin_analista boolean default false,
  p_equipo uuid default null,p_sin_equipo boolean default false,p_tipos text[] default null,
  p_moneda text default null,p_pagina integer default 1,p_tamano integer default 25,p_cortes jsonb default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_ambito record;
begin
  select * into v_ambito from private.ambito_facturacion();
  if v_ambito.ok is distinct from true then raise exception 'No autorizado' using errcode='42501'; end if;
  if p_cortes is null then
    return crm.listar_operaciones_facturacion_v2_fn(p_desde,p_hasta,p_dias,p_analistas,p_sin_analista,
      p_equipo,p_sin_equipo,p_tipos,p_moneda,p_pagina,p_tamano);
  end if;
  return private.facturacion_lista_nombres_base(p_desde,p_hasta,p_dias,p_analistas,p_sin_analista,
    p_equipo,p_sin_equipo,p_tipos,p_moneda,p_pagina,p_tamano,p_cortes)||'{"version":3}'::jsonb;
end $$;
alter function crm.listar_operaciones_facturacion_v3_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer,jsonb) owner to postgres;
revoke all on function crm.listar_operaciones_facturacion_v3_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer,jsonb) from public,anon,service_role;
grant execute on function crm.listar_operaciones_facturacion_v3_fn(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer,jsonb) to authenticated;
commit;

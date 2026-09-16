-- Consulta comercial sobre los núcleos F5 vigentes. Sin nuevas fuentes de
-- capital ni cambios en public, permisos de identidad o cierres mensuales.
-- RPC separada para que los clientes publicados sigan usando el contrato v1.
create or replace function private.cartera_f5_listar(
  p_pagina integer default 1, p_tamano integer default 25, p_texto text default '',
  p_empresa text default null, p_responsable uuid default null,
  p_sin_responsable boolean default false, p_mes text default null,
  p_moneda text default null, p_estado text default null,
  p_contacto text default null, p_por_vencer boolean default false,
  p_compatibilidad boolean default false
)
returns jsonb language plpgsql security definer set search_path=''
as $f$
declare
  v_resultado jsonb;
  v_texto text:=lower(btrim(coalesce(p_texto,'')));
  v_lector boolean:=private.es_lector_global();
  v_hoy date:=(statement_timestamp() at time zone 'America/Lima')::date;
  v_mes date;
begin
  perform private.cartera_f5_exigir();
  if p_pagina is null or p_pagina<1 or p_pagina>1000000
    or p_tamano is null or p_tamano not in (10,25,50)
    or length(v_texto)>120 or v_texto~'[[:cntrl:]]'
    or (p_empresa is not null and p_empresa not in ('avance','qorilazo','prodelco'))
    or p_sin_responsable is null or (p_sin_responsable and p_responsable is not null)
    or (p_mes is not null and p_mes<>'sin_fecha' and
      (p_mes !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' or left(p_mes,4) in ('0000','9999')))
    or (p_moneda is not null and p_moneda not in ('PEN','USD'))
    or (p_estado is not null and p_estado not in
      ('vigente','vencido','renovado','retirado','anulado_comercialmente','sin_inversiones'))
    or (p_contacto is not null and p_contacto not in ('sin_restriccion','no_contactar'))
    or p_por_vencer is null then
    raise exception 'Filtros de cartera inválidos' using errcode='22023';
  end if;
  if p_mes is not null and p_mes<>'sin_fecha' then v_mes:=(p_mes||'-01')::date; end if;

  -- Lista explícita: nuevos campos internos del núcleo no amplían el DTO público.
  with personas as materialized (
    select inversionista_id,nombre,documento_tipo,documento,documento_verificado,
      telefono,correo,estado,no_contactar,responsable_id,responsable_nombre,creado_en
    from private.cartera_f5_personas_visibles()
  ),
  fuentes as materialized (
    select f.* from private.cartera_f5_fuentes_reales() f
    join personas p using(inversionista_id)
    where not v_lector or f.empresa='avance'
  ), fuentes_filtradas as materialized (
    -- TODOS los filtros corresponden a una misma inversión, nunca a EXISTS
    -- independientes que combinen el mes de una con la moneda de otra.
    select f.* from fuentes f
    where (p_empresa is null or f.empresa=p_empresa)
      and (p_moneda is null or f.moneda=p_moneda)
      and (p_mes is null or (p_mes='sin_fecha' and f.fecha_comercial is null)
        or (f.fecha_comercial>=v_mes and f.fecha_comercial<v_mes+interval '1 month'))
      and (p_estado is null or f.estado=p_estado or (p_estado='vigente' and f.estado='activo'))
      and (not p_por_vencer or (f.estado in ('activo','vigente') and f.vence_en between v_hoy and v_hoy+30))
  ), filtradas as materialized (
    select p.* from personas p
    where (p_responsable is null or p.responsable_id=p_responsable)
      and (not p_sin_responsable or p.responsable_id is null)
      and (p_contacto is null or (p_contacto='no_contactar')=p.no_contactar)
      and (
        exists(select 1 from fuentes_filtradas f where f.inversionista_id=p.inversionista_id)
        or (not exists(select 1 from fuentes f where f.inversionista_id=p.inversionista_id)
          and p_empresa is null and p_moneda is null and not p_por_vencer
          and (p_estado is null or p_estado='sin_inversiones')
          and p_mes is distinct from 'sin_fecha')
      )
      -- % y _ son texto literal; la referencia también se busca en fuentes
      -- que cumplen el resto de filtros, dentro del ámbito vigente.
      and (v_texto='' or strpos(lower(concat_ws(' ',p.nombre,p.documento,p.telefono,p.correo)),v_texto)>0
        or (not p_compatibilidad and exists(select 1 from fuentes_filtradas f where f.inversionista_id=p.inversionista_id
          and strpos(lower(concat_ws(' ',f.empresa,f.numero)),v_texto)>0))
        or (p_compatibilidad and exists(select 1 from fuentes f where f.inversionista_id=p.inversionista_id
          and strpos(f.empresa,v_texto)>0)))
  ), pagina as materialized (
    select * from filtradas order by lower(nombre),inversionista_id
    limit p_tamano offset (p_pagina-1)*p_tamano
  ), importes as materialized (
    select f.inversionista_id,f.empresa,f.moneda,count(*) cantidad,
      coalesce(sum(f.capital) filter(where not f.es_demo),0) capital_registrado,
      case when f.empresa='avance' then coalesce(sum(f.capital) filter(where not f.es_demo and f.estado='activo'
        and exists(select 1 from public.perfiles pf where pf.id=f.perfil_id and pf.activo)),0) end capital_activo
    from fuentes_filtradas f join filtradas p using(inversionista_id)
    group by f.inversionista_id,f.empresa,f.moneda
  ), totales as (
    select empresa,moneda,sum(cantidad) cantidad,sum(capital_registrado) capital_registrado,
      sum(capital_activo) capital_activo from importes group by empresa,moneda
  )
  select jsonb_build_object('version',2,'pagina',p_pagina,'tamano',p_tamano,'solo_avance',v_lector,
    'total',(select count(*) from filtradas),
    'sin_inversiones_total',(select count(*) from filtradas p where not exists
      (select 1 from fuentes f where f.inversionista_id=p.inversionista_id)),
    'opciones_meses',coalesce((select jsonb_agg(m.mes order by m.mes desc) from (
      select distinct to_char(fecha_comercial,'YYYY-MM') mes from fuentes where fecha_comercial is not null
    ) m),'[]'),
    'opciones_responsables',coalesce((select jsonb_agg(r order by lower(r.nombre),r.id) from (
      select distinct responsable_id id,responsable_nombre nombre from personas where responsable_id is not null
    ) r),'[]'),
    'filas',coalesce((select jsonb_agg(
      to_jsonb(p)||jsonb_build_object(
        'empresas',coalesce((select jsonb_agg(x.empresa order by x.empresa) from (
          select distinct f.empresa from fuentes f where f.inversionista_id=p.inversionista_id) x),'[]'),
        'ultima_fecha_comercial',(select max(f.fecha_comercial) from fuentes_filtradas f where f.inversionista_id=p.inversionista_id),
        'resumen',coalesce((select jsonb_agg(to_jsonb(i)-'inversionista_id' order by i.empresa,i.moneda)
          from importes i where i.inversionista_id=p.inversionista_id),'[]'))
      order by lower(p.nombre),p.inversionista_id) from pagina p),'[]'),
    'totales',coalesce((select jsonb_agg(t order by t.empresa,t.moneda) from totales t),'[]')) into v_resultado;
  perform private.cartera_f5_registrar('lista');
  return v_resultado;
end;
$f$;

create or replace function crm.cartera_inversionistas_filtrada_fn(
  p_pagina integer default 1, p_tamano integer default 25, p_texto text default '',
  p_empresa text default null, p_responsable uuid default null,
  p_sin_responsable boolean default false, p_mes text default null,
  p_moneda text default null, p_estado text default null,
  p_contacto text default null, p_por_vencer boolean default false
)
returns jsonb language sql security definer set search_path=''
as $f$
  select private.cartera_f5_listar(p_pagina,p_tamano,p_texto,p_empresa,p_responsable,
    p_sin_responsable,p_mes,p_moneda,p_estado,p_contacto,p_por_vencer);
$f$;

-- La firma publicada mantiene su payload v1 y comparte la consulta canónica.
create or replace function crm.cartera_inversionistas_fn(
  p_pagina integer default 1,p_tamano integer default 25,p_texto text default '',
  p_empresa text default null,p_responsable uuid default null,p_sin_responsable boolean default false
)
returns jsonb language sql security definer set search_path=''
as $f$
  select jsonb_build_object('version',1,'pagina',d->'pagina','tamano',d->'tamano',
    'total',d->'total','totales',d->'totales','filas',coalesce((select jsonb_agg(
      f-'resumen'-'ultima_fecha_comercial' order by n)
      from jsonb_array_elements(d->'filas') with ordinality x(f,n)),'[]'))
  from (select private.cartera_f5_listar(
    p_pagina,p_tamano,p_texto,p_empresa,p_responsable,p_sin_responsable,p_compatibilidad=>true) d) consulta;
$f$;

-- Propietario común y explícito: un despliegue por supabase_admin no debe
-- dejar a la RPC publicada (postgres) sin EXECUTE sobre el núcleo privado.
alter function private.cartera_f5_listar(integer,integer,text,text,uuid,boolean,text,text,text,text,boolean,boolean) owner to postgres;
alter function crm.cartera_inversionistas_filtrada_fn(integer,integer,text,text,uuid,boolean,text,text,text,text,boolean) owner to postgres;
alter function crm.cartera_inversionistas_fn(integer,integer,text,text,uuid,boolean) owner to postgres;
revoke all on function private.cartera_f5_listar(integer,integer,text,text,uuid,boolean,text,text,text,text,boolean,boolean)
  from public,anon,authenticated,service_role;
revoke all on function crm.cartera_inversionistas_filtrada_fn(integer,integer,text,text,uuid,boolean,text,text,text,text,boolean)
  from public,anon,authenticated,service_role;
revoke all on function crm.cartera_inversionistas_fn(integer,integer,text,text,uuid,boolean)
  from public,anon,authenticated,service_role;
grant execute on function crm.cartera_inversionistas_filtrada_fn(integer,integer,text,text,uuid,boolean,text,text,text,text,boolean) to authenticated;
grant execute on function crm.cartera_inversionistas_fn(integer,integer,text,text,uuid,boolean) to authenticated;
notify pgrst,'reload schema';

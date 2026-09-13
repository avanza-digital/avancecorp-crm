-- Listado e indicadores del mismo conjunto filtrado. La consulta pública
-- aplica RLS. El resumen anterior reutiliza este inventario conservando sus
-- cierres mensuales y contrato: no se añade otra calculadora de inventario.
begin;
set local lock_timeout='10s';
lock table private.analitica_leads_citas_exenciones,private.analitica_leads_citas_tope,
  private.analitica_lc_sello in share row exclusive mode;
do $preflight$
begin
  if md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure))
    is distinct from 'e69c9eb25ef352150404875f3b5687c5' then
    raise exception 'El resumen general cambió: revisar compatibilidad antes de instalar';
  end if;
  perform private.assert_analitica_leads_citas();
end;
$preflight$;
create temporary table cartera_integrada_preflight on commit drop as
select (select jsonb_agg(to_jsonb(e) order by objeto) from private.analitica_leads_citas_exenciones e
    where objeto not in ('crm.resumen_cartera_fn()',
      'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date)')) as otras,
  (select to_jsonb(t) from private.analitica_leads_citas_tope t where id) as tope,
  (select proacl from pg_proc where oid='crm.resumen_cartera_fn()'::regprocedure) as resumen_acl;

-- Adaptador privado de capacidad: el invoker no tiene EXECUTE sobre la puerta
-- original. Sólo expone su booleano, sin ampliar los permisos de esa puerta.
create or replace function private.cartera_puede_operar_reparto_fn()
returns boolean language sql stable security definer set search_path='' as $fn$
  select private.puede_operar_reparto_crm();
$fn$;
revoke all on function private.cartera_puede_operar_reparto_fn() from public,anon,authenticated,service_role;
grant execute on function private.cartera_puede_operar_reparto_fn() to authenticated;

create or replace function private.cartera_recepciones_fn(p_desde date, p_hasta date)
returns table(lead_id uuid, recibido_en timestamptz, aproximado boolean)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_global boolean;
  v_visibles uuid[];
begin
  if v_uid is null or not private.puede_acceder_crm() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_desde is null and p_hasta is null then return; end if;
  if p_desde is null or p_hasta is null or p_desde > p_hasta
     or p_hasta > (now() at time zone 'America/Lima')::date then
    raise exception 'Rango de fechas inválido' using errcode = '22023';
  end if;
  v_global := private.rol_crm(v_uid) = 'gerencia' or private.es_lector_global();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  return query
    select distinct on (l.id) l.id, a.asignado_en, a.aproximado
    from crm.lead_asignaciones a
    join crm.leads l on l.id = a.lead_id and l.vendedor_id = a.analista_id
    join crm.equipo e on e.perfil_id = a.analista_id and e.rol_crm = 'vendedor'
    where l.activo is true
      and (v_global or a.analista_id = any(v_visibles))
      and a.asignado_en >= (p_desde::timestamp at time zone 'America/Lima')
      and a.asignado_en < ((p_hasta + 1)::timestamp at time zone 'America/Lima')
      -- Una reversión al mismo supervisor no es una recepción comercial.
      and (a.motivo_cierre is distinct from 'parkeado'
        or a.supervisor_origen_id is null
        or a.supervisor_destino_id is distinct from a.supervisor_origen_id)
    order by l.id, a.asignado_en desc, a.id desc;
end;
$$;
revoke all on function private.cartera_recepciones_fn(date,date) from public, anon, authenticated, service_role;
grant execute on function private.cartera_recepciones_fn(date,date) to authenticated;

create or replace function crm.cartera_filtrada_fn(
  p_limite integer default 50,
  p_antes_de timestamptz default null,
  p_antes_id uuid default null,
  p_etapa text default null,
  p_vendedor_id uuid default null,
  p_sin_asignar boolean default false,
  p_texto text default null,
  p_desde date default null,
  p_hasta date default null
)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_global boolean;
  v_visibles uuid[];
  v_texto text := nullif(btrim(p_texto), '');
  v_reparto boolean;
  v_digitos text;
  v_salida jsonb;
begin
  if v_uid is null or not private.puede_acceder_crm() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_limite is null or p_limite < 1 or p_limite > 200
     or (p_antes_de is null) <> (p_antes_id is null)
     or (p_sin_asignar and p_vendedor_id is not null)
     or (p_sin_asignar and p_desde is not null)
     or (p_desde is null) <> (p_hasta is null)
     or p_desde > p_hasta
     or p_hasta > (now() at time zone 'America/Lima')::date
     or (p_etapa is not null and p_etapa not in
       ('nuevo','contactado','reunion_agendada','propuesta_enviada','convertido','descartado'))
     or (v_texto is not null and length(v_texto) < 2) then
    raise exception 'Filtros de cartera inválidos' using errcode = '22023';
  end if;
  v_texto := left(v_texto, 80);
  v_digitos := left(regexp_replace(v_texto, '\D', '', 'g'), 15);
  v_global := private.rol_crm(v_uid) = 'gerencia' or private.es_lector_global();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_reparto := private.cartera_puede_operar_reparto_fn();

  with recepciones as materialized (
    select * from private.cartera_recepciones_fn(p_desde,p_hasta)
  ), base as materialized (
    select l.id, l.nombre_completo, l.telefono, l.telefono_alternativo,
      l.telefono_alternativo_crudo, l.correo, l.dni, l.genero,
      l.fecha_nacimiento, l.distrito, l.origen, l.etapa, l.motivo_descarte,
      l.monto_estimado, l.moneda, l.categoria_interes, l.vendedor_id,
      l.asignado_supervisor_id, l.creado_en, l.tenencia_desde, l.convertido_en,
      l.contrato_id, l.actualizado_en, l.activo, l.nota, l.no_contactar,
      r.recibido_en, coalesce(r.aproximado,false) as recepcion_aproximada
    from crm.leads l
    left join recepciones r on r.lead_id = l.id
    where l.activo is true
      and (v_global or l.vendedor_id = any(v_visibles)
        or (l.vendedor_id is null and (l.asignado_supervisor_id = any(v_visibles)
          or v_reparto)))
      and (p_desde is null or r.lead_id is not null)
      -- La consulta por recepción puede recuperar convertidos antiguos que
      -- siguen siendo visibles por RLS; sin fechas se conserva la ventana operativa.
      and (p_desde is not null or l.etapa <> 'convertido' or l.convertido_en >= now() - interval '45 days')
      and (p_etapa is null or l.etapa = p_etapa)
      and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
      and (not coalesce(p_sin_asignar,false) or l.vendedor_id is null)
      and (v_texto is null or strpos(lower(l.nombre_completo),lower(v_texto)) > 0
        or (length(v_digitos) >= 3 and (strpos(l.telefono,v_digitos) > 0
          or strpos(l.telefono_alternativo,v_digitos) > 0 or strpos(l.dni,v_digitos) > 0)))
  ), pagina as (
    select b.* from base b
    where p_antes_de is null or b.actualizado_en < p_antes_de
      or (b.actualizado_en = p_antes_de and b.id > p_antes_id)
    order by b.actualizado_en desc,b.id asc limit p_limite
  ), filas as (
    select p.*, uc.creado_en as ultimo_contacto_en
    from pagina p left join lateral (
      select act.creado_en from crm.actividades act
      where act.lead_id = p.id and act.tipo in ('llamada_realizada',
        'llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')
      order by act.creado_en desc limit 1
    ) uc on true
  ), metricas as (
    select count(*) as vivos,
      count(*) filter(where etapa not in ('convertido','descartado')) as abiertos,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null) as asignados,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is null) as parkeados,
      count(*) filter(where etapa = 'convertido') as convertidos,
      count(*) filter(where etapa = 'descartado') as descartados,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null and moneda='PEN') as asignados_pen,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null and moneda='USD') as asignados_usd
    from base
  ), capital as (
    select jsonb_object_agg(tipo,valor) as valor from (
      select t.tipo, jsonb_build_object(
        'pen',coalesce(sum(b.monto_estimado) filter(where b.moneda='PEN'),0),
        'usd',coalesce(sum(b.monto_estimado) filter(where b.moneda='USD'),0)) as valor
      from (values('asignado'),('parkeado'),('ganado')) t(tipo)
      left join base b on (t.tipo='ganado' and b.etapa='convertido')
        or (b.etapa not in ('convertido','descartado') and
          ((t.tipo='asignado' and b.vendedor_id is not null) or (t.tipo='parkeado' and b.vendedor_id is null)))
      group by t.tipo
    ) montos
  )
  select jsonb_build_object('version',1,'generado_en',now(),
    'desde',p_desde,'hasta',p_hasta,
    'items',coalesce((select jsonb_agg(to_jsonb(f) order by f.actualizado_en desc,f.id) from filas f),'[]'::jsonb),
    'resumen',jsonb_build_object('totales',(select to_jsonb(m) from metricas m),
      'capital',(select valor from capital),
      'conversion',jsonb_build_object(
        'convertidos',(select count(*) from base where etapa='convertido' and vendedor_id is not null),
        'base',(select count(*) from base where vendedor_id is not null),
        'pct',coalesce((select round(100.0 * count(*) filter(where etapa='convertido')
          / nullif(count(*),0))::int from base where vendedor_id is not null),0)),
      'descartes',jsonb_build_object(
        'total',(select count(*) from base where etapa='descartado'),
        'sin_motivo',(select count(*) from base where etapa='descartado' and motivo_descarte is null),
        'por_motivo',(select coalesce(jsonb_agg(to_jsonb(d) order by d.n desc,d.motivo),'[]'::jsonb)
          from (select motivo_descarte as motivo,count(*) as n from base
            where etapa='descartado' and motivo_descarte is not null group by motivo_descarte) d)),
      'sin_tocar',(select count(*) from base b where b.etapa not in('convertido','descartado')
        and b.vendedor_id is not null and not exists(select 1 from crm.actividades a
          where a.lead_id=b.id and a.tipo in ('llamada_realizada','llamada_no_contestada',
            'whatsapp_enviado','whatsapp_recibido','reunion_realizada'))),
      'embudo',(select jsonb_agg(jsonb_build_object('etapa',e.etapa,'n',
        (select count(*) from base b where b.etapa=e.etapa)) order by e.ord)
        from (values('nuevo',1),('contactado',2),('reunion_agendada',3),
          ('propuesta_enviada',4),('convertido',5),('descartado',6)) e(etapa,ord))))
  into v_salida;
  return v_salida;
end;
$$;
revoke all on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date) from public, anon, authenticated, service_role;
grant execute on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date) to authenticated;
comment on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date) is
  'Leads e indicadores con filtros comunes. Recepción del analista actual, días inclusivos de Lima, un lead por resultado. RLS vigente y sin acceso a otros equipos. Sin fechas conserva inventario operativo de 45 días.';

-- Adaptador compatible para Hoy/Pipeline y demás consumidores del resumen
-- general. Sólo cambia dónde se agrega el inventario; el mes y el núcleo
-- oficial de conversión siguen siendo los mismos, sin filtros de la pantalla.
create or replace function crm.resumen_cartera_fn()
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
  v_uid uuid:=(select auth.uid());
  v_rol text:=private.rol_crm(v_uid);
  v_lector boolean:=private.es_lector_global();
  v_visibles uuid[]:=array(select private.vendedor_ids_visibles(v_uid));
  v_ahora timestamptz:=now();
  v_mes date:=date_trunc('month',v_ahora at time zone 'America/Lima')::date;
  v_payload jsonb;
  v_cierres bigint;
  v_operaciones bigint;
begin
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_payload:=crm.cartera_filtrada_fn(p_limite=>1)->'resumen';
  select coalesce(sum(n.cierres_no_referidos+n.cierres_referidos),0),coalesce(sum(n.operaciones),0)
  into v_cierres,v_operaciones from (
    select e.analista_id,
      count(distinct e.lead_id) filter(where e.tipo='cierre' and not e.anulado and not e.fue_referido) as cierres_no_referidos,
      count(distinct e.lead_id) filter(where e.tipo='cierre' and not e.anulado and e.fue_referido) as cierres_referidos,
      count(*) filter(where e.tipo='operacion') as operaciones
    from private.conversion_episodios(v_mes::timestamp at time zone 'America/Lima',
      (v_mes+interval '1 month')::timestamp at time zone 'America/Lima',v_mes,true,'{}'::uuid[],
      private.peso_referido_conversion(v_mes)) e
    where e.analista_id=any(v_visibles) or v_rol='gerencia' or v_lector
    group by e.analista_id
  ) n;
  return v_payload || jsonb_build_object('version',1,'generado_en',v_ahora,
    'ventana_convertidos_dias',45,'ventana_metrica','mes_calendario','mes_metrica',v_mes,
    'totales',(v_payload->'totales') || jsonb_build_object('convertidos',v_cierres,'operaciones_cartera',v_operaciones));
end;
$fn$;

-- Trasladar el cálculo crudo al inventario compartido conserva el techo del
-- censo. El adaptador mensual conserva su declaración de consumidor del núcleo.
insert into private.analitica_leads_citas_exenciones(tipo,objeto,huella,razon)
select 'funcion',p.oid::regprocedure::text,
  md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
  'Inventario operativo único para listado y resumen: filtros de etapa, analista, búsqueda y recepción del dueño actual. No calcula conversión mensual: el adaptador general conserva el núcleo oficial.'
from pg_proc p where p.oid='crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date)'::regprocedure;
update private.analitica_leads_citas_exenciones e set
  huella=(select md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
    from pg_proc p where p.oid='crm.resumen_cartera_fn()'::regprocedure),
  razon='Adaptador compatible: inventario servido por cartera_filtrada_fn; cierres y operaciones mensuales desde conversion_episodios. Conserva el ámbito y el contrato anterior.'
where e.objeto='crm.resumen_cartera_fn()';
update private.analitica_lc_sello set sello=private.huella_exenciones_analitica_lc(),sellado_en=now() where id;
select private.assert_analitica_leads_citas();
do $postflight$
declare f record;
begin
  for f in select * from (values
    ('private.cartera_puede_operar_reparto_fn()',true),
    ('private.cartera_recepciones_fn(date,date)',true),
    ('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date)',false),
    ('crm.resumen_cartera_fn()',true)
  ) t(firma,definer) loop
    if not exists(select 1 from pg_proc p where p.oid=to_regprocedure(f.firma)
      and p.proowner='postgres'::regrole and p.prosecdef=f.definer
      and p.provolatile='s' and p.proconfig @> array['search_path=""'])
      or has_function_privilege('anon',f.firma,'EXECUTE')
      or has_function_privilege('service_role',f.firma,'EXECUTE')
      or not has_function_privilege('authenticated',f.firma,'EXECUTE') then
      raise exception 'Contrato de seguridad inválido para %',f.firma;
    end if;
  end loop;
  if (select count(*) from private.contadores_crudos_leads_citas())<>34
    or (select count(*) from private.auxiliares_analitica_lc_auditados())<>4
    or (select tope from private.analitica_leads_citas_tope where id)<>30 then
    raise exception 'El inventario compartido alteró el censo analítico';
  end if;
  if (select jsonb_agg(to_jsonb(e) order by objeto) from private.analitica_leads_citas_exenciones e
      where objeto not in ('crm.resumen_cartera_fn()',
        'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date)'))
       is distinct from (select otras from cartera_integrada_preflight)
    or (select to_jsonb(t) from private.analitica_leads_citas_tope t where id)
       is distinct from (select tope from cartera_integrada_preflight)
    or (select proacl from pg_proc where oid='crm.resumen_cartera_fn()'::regprocedure)
       is distinct from (select resumen_acl from cartera_integrada_preflight) then
    raise exception 'Cambió una declaración ajena, el techo o los permisos del resumen general';
  end if;
end;
$postflight$;
notify pgrst,'reload schema';
commit;

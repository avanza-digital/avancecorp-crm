-- Lectura operativa de clientes, aditiva a captación. No cambia sus núcleos ni metas.
-- Preparada para revisión humana; aplicar primero en un banco autorizado.
begin;
set local lock_timeout = '5s';

-- Autoriza siempre con la sesión real. No acepta p_actor ni concede SELECT a F6.
create function private.gestiones_validar(p_desde date,p_hasta date,p_autores uuid[] default null)
returns void language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
begin
  if auth.uid() is null then
    raise exception 'No autorizado para consultar gestiones' using errcode='42501'; end if;
  if p_desde is null or p_hasta is null or not isfinite(p_desde) or not isfinite(p_hasta)
    or p_desde>p_hasta or p_hasta-p_desde>365 then
    raise exception 'Elige un rango válido de hasta un año' using errcode='22023'; end if;
  perform private.resolver_en_puertas_bajo_candado();
  perform pg_advisory_xact_lock_shared(hashtextextended('crm.equipo.usuarios_jerarquia',0));
  if not private.puede_acceder_crm()
    or coalesce(private.rol_crm(auth.uid()),'') not in ('vendedor','supervisor','gerencia') then
    raise exception 'No autorizado para consultar gestiones' using errcode='42501'; end if;
  if p_autores is not null and (cardinality(p_autores)=0 or exists(
    select 1 from unnest(p_autores) a where a is null
      or a not in (select private.vendedor_ids_visibles(auth.uid())))) then
    raise exception 'Solo puedes consultar autores de tu equipo' using errcode='42501'; end if;
end;
$$;

-- Identidad de ficha autorizada: incluso un autor histórico no recupera PII
-- de un cliente reasignado. El resultado siempre tiene una forma explícita.
create function private.gestiones_clientes_identidades(p_sujetos jsonb)
returns table(persona uuid,perfil uuid,identidad jsonb)
language plpgsql security definer set search_path='' as $$
declare v_f6 boolean;
begin
  perform private.gestiones_validar(current_date,current_date);
  if jsonb_typeof(p_sujetos) is distinct from 'array' then
    raise exception 'Lista de clientes inválida' using errcode='22023'; end if;
  -- Una página de leads o un conteo no necesita recorrer la cartera F5.
  if jsonb_array_length(p_sujetos)=0 then return; end if;
  if exists(select 1 from jsonb_to_recordset(p_sujetos) x(persona uuid,perfil uuid)
    where num_nonnulls(x.persona,x.perfil)<>1) then
    raise exception 'Indica un único cliente por referencia' using errcode='22023'; end if;
  v_f6:=coalesce((crm.postventa_estado_fn()->>'habilitada')::boolean,false);
  return query
  with sujetos as materialized (
    select distinct x.persona,x.perfil,case when x.persona is not null then private.inversionista_canonica(x.persona) end canonica
    from jsonb_to_recordset(p_sujetos) x(persona uuid,perfil uuid)
  ), visibles as materialized (
    -- Una lectura F5 para toda la página, con sus mismas fuentes y reglas de nombre.
    select p.inversionista_id,p.nombre,p.perfil_ids from private.cartera_f5_personas_visibles() p
    where v_f6 and (p.inversionista_id in (select s.canonica from sujetos s)
      or p.perfil_ids && array(select s.perfil from sujetos s where s.perfil is not null))
      and private.postventa_visible(p.inversionista_id)
  ), resueltos as (
    select s.*,v.inversionista_id,case when s.persona is not null then v.nombre
        when private.puede_consultar_cliente_ficha(s.perfil) then p.nombre_completo end nombre
    from sujetos s left join lateral (
      select v.* from visibles v where (s.persona is not null and v.inversionista_id=s.canonica)
        or (s.perfil is not null and s.perfil=any(v.perfil_ids)) order by v.inversionista_id limit 1
    ) v on true left join public.perfiles p on p.id=s.perfil
  )
  select r.persona,r.perfil,jsonb_build_object(
    'sujeto_tipo',case when r.persona is not null then 'inversionista' else 'perfil' end,
    'sujeto_id',case when r.nombre is not null then coalesce(r.canonica,r.perfil) end,
    'sujeto_nombre',case when r.nombre is null then 'Cliente fuera de tu cartera'
      else coalesce(nullif(btrim(r.nombre),''),'Sin nombre') end,
    'inversionista_id',case when r.nombre is not null then r.inversionista_id end,
    'perfil_id',case when r.nombre is not null then r.perfil end,
    'identidad_visible',r.nombre is not null)
  from resueltos r;
end;
$$;

create function private.gestion_cliente_identidad(p_persona uuid,p_perfil uuid)
returns jsonb language sql security invoker set search_path='' as $$
  select i.identidad from private.gestiones_clientes_identidades(
    jsonb_build_array(jsonb_build_object('persona',p_persona,'perfil',p_perfil))) i;
$$;

create function private.gestiones_clientes_eventos(p_desde date,p_hasta date,p_autores uuid[] default null,
  p_detalles boolean default true,p_limite integer default 500,p_tipos text[] default null,
  p_antes_de timestamptz default null,p_antes_id uuid default null,p_antes_origen text default null)
returns table(id uuid,origen text,identidad jsonb,tipo text,detalle text,metadata jsonb,
  creado_por uuid,autor_nombre text,creado_en timestamptz,operativa boolean,contacto boolean)
language plpgsql security definer set search_path='' as $$
declare v_ids uuid[]; v_f6 boolean; v_limite integer;
begin
  perform private.gestiones_validar(p_desde,p_hasta,p_autores);
  if p_detalles is null or p_limite is null or p_limite not between 1 and 500 then
    raise exception 'Página de gestiones inválida' using errcode='22023'; end if;
  -- Los conteos recorren todas las filas autorizadas, sin resolver identidad ni PII.
  v_limite:=case when p_detalles then p_limite end;
  select array_agg(x) into v_ids from private.vendedor_ids_visibles(auth.uid()) x
    where p_autores is null or x=any(p_autores);
  v_f6:=coalesce((crm.postventa_estado_fn()->>'habilitada')::boolean,false);
  return query
  with eventos as (
    select g.id,'postventa'::text origen,g.inversionista_id persona,null::uuid perfil,g.tarea_id,
      g.creado_por,g.creado_en,case when p_detalles then g.detalle end detalle,
      coalesce(g.metadata->>'tipo_tarea',t.tipo) tarea_tipo,
      coalesce(g.metadata->>'estado',t.estado) estado,
      coalesce(g.metadata->>'resultado','sin_resultado') resultado,
      coalesce(g.metadata->>'resultado_reunion',t.resultado_reunion,'sin_clasificar') resultado_reunion,
      null::text tipo_legacy
    from crm.inversionista_gestiones g join crm.tareas t on t.id=g.tarea_id
    where v_f6 and g.tipo='cierre' and g.creado_por=any(v_ids)
      and g.creado_en>=p_desde::timestamp at time zone 'America/Lima'
      and g.creado_en<(p_hasta+1)::timestamp at time zone 'America/Lima'
    union all
    select a.id,'perfil',null,a.cliente_id,a.tarea_id,a.creado_por,a.creado_en,case when p_detalles then a.detalle end,
      t.tipo,coalesce(t.estado,'completada'),'sin_resultado',coalesce(t.resultado_reunion,'sin_clasificar'),a.tipo
    from crm.actividades_cliente a left join crm.tareas t on t.id=a.tarea_id
    where a.creado_por=any(v_ids)
      and a.creado_en>=p_desde::timestamp at time zone 'America/Lima'
      and a.creado_en<(p_hasta+1)::timestamp at time zone 'America/Lima'
      -- Los espejos F6 no se convierten en una vía heredada al apagar la bandera.
      and not exists(select 1 from crm.inversionista_gestiones g where g.tarea_id=a.tarea_id and g.tipo='cierre')
  ), clasificados as (
    select e.*,coalesce(e.tipo_legacy,case when e.estado='completada' then
      case e.tarea_tipo when 'llamada' then case when e.resultado in ('no_contesto','numero_errado','no_es_la_persona') then 'llamada_no_contestada' else 'llamada_realizada' end
        when 'whatsapp' then case when e.resultado='respondio' then 'whatsapp_recibido' else 'whatsapp_enviado' end
        when 'reunion' then 'reunion_realizada' else 'nota' end else 'nota' end) clase
    from eventos e
  ), pagina as materialized (
    select e.* from clasificados e
    where (p_tipos is null or e.clase=any(p_tipos))
      and (p_antes_de is null or e.creado_en<p_antes_de
        or (e.creado_en=p_antes_de and (e.origen,e.id)>(p_antes_origen,p_antes_id)))
    order by e.creado_en desc,e.origen,e.id limit v_limite
  ), sujetos as materialized (
    select * from private.gestiones_clientes_identidades(coalesce((select jsonb_agg(to_jsonb(e))
      from (select distinct e.persona,e.perfil from pagina e where p_detalles) e),'[]'))
  )
  select e.id,e.origen,s.identidad,e.clase,
    case when (s.identidad->>'identidad_visible')::boolean then e.detalle end,
    case when p_detalles then jsonb_build_object('resultado',case when e.clase in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido') then e.resultado end,
      'resultado_reunion',case when e.clase='reunion_realizada' then e.resultado_reunion end,'estado',e.estado,
      'tarea_id',case when (s.identidad->>'identidad_visible')::boolean then e.tarea_id end,
      'resultado_origen',case when (e.clase='reunion_realizada' and e.resultado_reunion='sin_clasificar')
        or (e.clase in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido') and e.resultado='sin_resultado')
        then 'legacy_sin_resultado' else 'declarado' end) end,
    e.creado_por,case when p_detalles then coalesce(private.nombre_de_autor(e.creado_por),'—') end,e.creado_en,
    e.estado='completada' and e.clase in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada','nota'),
    e.clase='llamada_realizada' and (e.tipo_legacy='llamada_realizada' or e.resultado not in ('sin_resultado','numero_errado','no_es_la_persona'))
  from pagina e left join sujetos s on s.persona is not distinct from e.persona and s.perfil is not distinct from e.perfil;
end;
$$;

-- INVOKER: la rama de leads mantiene su RLS. La rama definer solo devuelve clientes autorizados.
create function private.gestiones_operativas_eventos(p_desde date,p_hasta date,p_autores uuid[] default null,
  p_detalles boolean default true,p_limite integer default 500,p_tipos text[] default null,
  p_antes_de timestamptz default null,p_antes_id uuid default null,p_antes_origen text default null,
  p_etapa text default null,p_cartera text default null)
returns table(id uuid,origen text,identidad jsonb,lead_id uuid,lead_nombre text,lead_etapa text,
  etapa_en_ese_momento text,tipo text,detalle text,metadata jsonb,creado_por uuid,autor_nombre text,
  creado_en timestamptz,operativa boolean,contacto boolean)
language plpgsql security invoker set search_path='' as $$
declare v_limite integer;
begin
  perform private.gestiones_validar(p_desde,p_hasta,p_autores);
  if p_detalles is null or p_limite is null or p_limite not between 1 and 500 then
    raise exception 'Página de gestiones inválida' using errcode='22023'; end if;
  v_limite:=case when p_detalles then p_limite end;
  return query
  -- El límite se aplica antes de nombres, metadata y etapa histórica. Cada rama
  -- aporta como máximo una página; la puerta ordena la unión y toma la página final.
  with pagina as materialized (
    select a.id,a.lead_id,a.tipo,case when p_detalles then a.detalle end detalle,
      case when p_detalles then a.metadata else jsonb_build_object('resultado',a.metadata->'resultado') end metadata,
      a.creado_por,a.creado_en,case when p_detalles then coalesce(nullif(btrim(l.nombre_completo),''),'Sin nombre') end nombre,
      case when p_detalles then l.etapa end etapa
    from crm.actividades a join crm.leads l on l.id=a.lead_id
    where (p_cartera is null or p_cartera='leads')
      and a.creado_en>=p_desde::timestamp at time zone 'America/Lima'
      and a.creado_en<(p_hasta+1)::timestamp at time zone 'America/Lima'
      and (p_autores is null or a.creado_por=any(p_autores))
      and (a.metadata ? 'postventa_gestion_id') is not true
      and (p_tipos is null or a.tipo=any(p_tipos)) and (p_etapa is null or l.etapa=p_etapa)
      and (p_antes_de is null or a.creado_en<p_antes_de
        or (a.creado_en=p_antes_de and ('lead'::text,a.id)>(p_antes_origen,p_antes_id)))
    order by a.creado_en desc,a.id limit v_limite
  )
  select a.id,'lead'::text,case when p_detalles then jsonb_build_object('sujeto_tipo','lead','sujeto_id',a.lead_id,'sujeto_nombre',a.nombre,
      'inversionista_id',null,'perfil_id',null,'identidad_visible',true) end,
    case when p_detalles then a.lead_id end,a.nombre,a.etapa,
    case when p_detalles then (select c.metadata->>'etapa_nueva' from crm.actividades c where c.lead_id=a.lead_id and c.tipo='cambio_etapa'
      and c.creado_en<a.creado_en-interval '1 second' order by c.creado_en desc,c.id desc limit 1) end,
    a.tipo,a.detalle,
    case when p_detalles then coalesce((select jsonb_object_agg(m.key,m.value) from jsonb_each(a.metadata) m where m.key in
      ('evento','resultado','submotivo','intento_n','etapa_anterior','etapa_nueva','automatico','resultado_reunion',
       'modalidad','motivo','descartado','no_insista','deshecho_en','siguiente_id','tarea_id','motivo_descarte',
       'etapa_al_descartar','actividad_id','tarea_cancelada','descarte_revertido','cita_no_restaurada')),'{}'::jsonb) end,
    a.creado_por,case when p_detalles then coalesce(private.nombre_de_autor(a.creado_por),'—') end,a.creado_en,
    a.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada','nota'),
    a.tipo='llamada_realizada' and coalesce(a.metadata->>'resultado','sin_resultado') not in ('numero_errado','no_es_la_persona')
  from pagina a;
  if p_etapa is null and (p_cartera is null or p_cartera='clientes') then
    return query
    select e.id,e.origen,e.identidad,null::uuid,null::text,null::text,null::text,e.tipo,e.detalle,e.metadata,e.creado_por,e.autor_nombre,
      e.creado_en,e.operativa,e.contacto from private.gestiones_clientes_eventos(p_desde,p_hasta,p_autores,
        p_detalles,p_limite,p_tipos,p_antes_de,p_antes_id,p_antes_origen) e;
  end if;
end;
$$;

create function crm.registro_actividad_v2_fn(p_desde date,p_hasta date,p_analista_ids uuid[] default null,
  p_tipos text[] default null,p_etapa text default null,p_limite integer default 50,
  p_antes_de timestamptz default null,p_antes_id uuid default null,p_antes_origen text default null,p_cartera text default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare v_items jsonb;
begin
  perform private.gestiones_validar(p_desde,p_hasta,p_analista_ids);
  if p_hasta>(now() at time zone 'America/Lima')::date or p_limite is null or p_limite not between 1 and 500
    or num_nonnulls(p_antes_de,p_antes_id,p_antes_origen) not in (0,3)
    or (p_antes_de is not null and not isfinite(p_antes_de))
    or (p_antes_origen is not null and p_antes_origen not in ('lead','perfil','postventa'))
    or (p_cartera is not null and p_cartera not in ('leads','clientes'))
    or (p_etapa is not null and p_etapa not in ('nuevo','contactado','reunion_agendada','propuesta_enviada','convertido','descartado'))
    or (p_tipos is not null and (cardinality(p_tipos)=0 or exists(select 1 from unnest(p_tipos) t
      where t is null or t not in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada','nota','cambio_etapa','reasignacion','conversion')))) then
    raise exception 'Consulta de registro inválida' using errcode='22023'; end if;
  select coalesce(jsonb_agg((to_jsonb(e)-'operativa'-'contacto'-'identidad')||e.identidad order by e.creado_en desc,e.origen,e.id),'[]') into v_items
  from (select * from private.gestiones_operativas_eventos(p_desde,p_hasta,p_analista_ids,
    true,p_limite,p_tipos,p_antes_de,p_antes_id,p_antes_origen,p_etapa,p_cartera) e
    where (p_cartera is null or case p_cartera when 'leads' then e.origen='lead' else e.origen<>'lead' end)
      and (p_tipos is null or e.tipo=any(p_tipos)) and (p_etapa is null or e.lead_etapa=p_etapa)
      and (p_antes_de is null or e.creado_en<p_antes_de
        or (e.creado_en=p_antes_de and (e.origen,e.id)>(p_antes_origen,p_antes_id)))
    order by e.creado_en desc,e.origen,e.id limit p_limite) e;
  return jsonb_build_object('version',2,'generado_en',now(),'desde',p_desde,'hasta',p_hasta,
    'zona','America/Lima','limite',p_limite,'items',v_items);
end;
$$;

-- Los contadores salen de las mismas filas del Registro. Cero es distinto de error.
create function crm.gestiones_resumen_fn(p_desde date,p_hasta date,p_analista_ids uuid[] default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare v_r jsonb;
  v_cero jsonb:='{"gestiones":0,"llamadas":0,"contestadas":0,"entrevistas":0,"ultima_llamada_en":null}';
  v_base jsonb;
begin
  perform private.gestiones_validar(p_desde,p_hasta,p_analista_ids);
  if p_hasta>(now() at time zone 'America/Lima')::date then
    raise exception 'El resumen no admite fechas futuras' using errcode='22023'; end if;
  v_base:=jsonb_build_object('leads',v_cero,'clientes',v_cero,'total',v_cero);
  with eventos as materialized (select * from private.gestiones_operativas_eventos(p_desde,p_hasta,p_analista_ids,false) where operativa),
  grupos as (
    select e.creado_por,e.autor_nombre,
      case when grouping(e.origen)=1 then 'total' when e.origen='lead' then 'leads' else 'clientes' end grupo,
      grouping(e.creado_por)=1 global,
      count(*) gestiones,count(*) filter(where e.tipo in ('llamada_realizada','llamada_no_contestada')) llamadas,
      count(*) filter(where e.contacto) contestadas,
      count(*) filter(where e.tipo='reunion_realizada') entrevistas,
      max(e.creado_en) filter(where e.tipo in ('llamada_realizada','llamada_no_contestada')) ultima_llamada_en
    from eventos e
    group by grouping sets ((e.creado_por,e.autor_nombre,e.origen),(e.creado_por,e.autor_nombre),(e.origen),())
  ), fusion as (
    select creado_por,autor_nombre,grupo,global,sum(gestiones)::int gestiones,sum(llamadas)::int llamadas,
      sum(contestadas)::int contestadas,sum(entrevistas)::int entrevistas,max(ultima_llamada_en) ultima_llamada_en
    from grupos group by creado_por,autor_nombre,grupo,global
  ), por_persona as (
    select creado_por,coalesce(private.nombre_de_autor(creado_por),'—') autor_nombre,
      v_base||jsonb_object_agg(grupo,jsonb_build_object('gestiones',gestiones,'llamadas',llamadas,
      'contestadas',contestadas,'entrevistas',entrevistas,'ultima_llamada_en',ultima_llamada_en)) metricas
    from fusion where not global group by creado_por,autor_nombre
  )
  select jsonb_build_object('version',1,'desde',p_desde,'hasta',p_hasta,'zona','America/Lima','generado_en',now(),
    'totales',v_base||coalesce((select jsonb_object_agg(grupo,jsonb_build_object('gestiones',gestiones,'llamadas',llamadas,
      'contestadas',contestadas,'entrevistas',entrevistas,'ultima_llamada_en',ultima_llamada_en)) from fusion where global),'{}'),
    'analistas',coalesce((select jsonb_agg(jsonb_build_object('id',creado_por,'nombre',autor_nombre,'metricas',metricas)
      order by autor_nombre,creado_por) from por_persona),'[]')) into v_r;
  return v_r;
end;
$$;

create function private.citas_clientes_core(p_desde date,p_hasta date,p_analista_ids uuid[] default null,
  p_limite integer default 25,p_despues_de timestamptz default null,p_despues_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_r jsonb; v_ids uuid[]; v_f6 boolean;
begin
  perform private.gestiones_validar(p_desde,p_hasta,p_analista_ids);
  if p_limite is null or p_limite not between 1 and 100 or num_nonnulls(p_despues_de,p_despues_id) not in (0,2)
    or (p_despues_de is not null and not isfinite(p_despues_de)) then
    raise exception 'Página de citas inválida' using errcode='22023'; end if;
  select array_agg(x) into v_ids from private.vendedor_ids_visibles(auth.uid()) x
    where p_analista_ids is null or x=any(p_analista_ids);
  v_f6:=coalesce((crm.postventa_estado_fn()->>'habilitada')::boolean,false);
  with base as materialized (
    select t.* from crm.tareas t where t.activo and t.tipo='reunion'
      and (t.vendedor_id=any(v_ids) or (t.vendedor_id is null and p_analista_ids is null and private.rol_crm(auth.uid())='gerencia'))
      and (t.perfil_id is not null or (v_f6 and t.inversionista_id is not null))
      and t.vence_en>=p_desde::timestamp at time zone 'America/Lima'
      and t.vence_en<(p_hasta+1)::timestamp at time zone 'America/Lima'
  ), sonda as materialized (
    select * from base where p_despues_de is null or (vence_en,id)>(p_despues_de,p_despues_id)
    order by vence_en,id limit p_limite+1
  ), pagina as materialized (select * from sonda order by vence_en,id limit p_limite),
  sujetos as materialized (select * from private.gestiones_clientes_identidades(coalesce((
    select jsonb_agg(jsonb_build_object('persona',p.inversionista_id,'perfil',p.perfil_id)) from pagina p),'[]'))),
  filas as (select p.id,p.vence_en,p.estado,p.confirmada_en,p.resultado_reunion,p.vendedor_id,
    coalesce(private.nombre_de_autor(p.vendedor_id),'Sin responsable') vendedor_nombre,s.identidad from pagina p
    join sujetos s on s.persona is not distinct from p.inversionista_id and s.perfil is not distinct from p.perfil_id)
  select jsonb_build_object('version',1,'desde',p_desde,'hasta',p_hasta,'generado_en',now(),'limite',p_limite,
    'resumen',jsonb_build_object('total',(select count(*) from base),
      'pendientes',(select count(*) from base where estado='pendiente'),
      'entrevistas',(select count(*) from base where estado='completada'),
      'no_asistio',(select count(*) from base where estado='no_show'),
      'reprogramadas',(select count(*) from base where estado='reprogramada'),
      'canceladas',(select count(*) from base where estado='cancelada')),
    'items',coalesce((select jsonb_agg((to_jsonb(f)-'identidad')||f.identidad order by vence_en,id) from filas f),'[]'),
    'hay_mas',(select count(*)>p_limite from sonda),
    'siguiente_cursor',case when (select count(*)>p_limite from sonda) then
      (select jsonb_build_object('despues_de',vence_en,'despues_id',id) from pagina order by vence_en desc,id desc limit 1) end) into v_r;
  return v_r;
end;
$$;

create function crm.citas_clientes_fn(p_desde date,p_hasta date,p_analista_ids uuid[] default null,
  p_limite integer default 25,p_despues_de timestamptz default null,p_despues_id uuid default null)
returns jsonb language sql security invoker set search_path='' as $$
  select private.citas_clientes_core(p_desde,p_hasta,p_analista_ids,p_limite,p_despues_de,p_despues_id);
$$;

-- Enriquecer solo las tareas que su RLS permite leer, conservando orden y cursor.
create function private.gestiones_identificar_tareas(p_items jsonb)
returns jsonb language sql security invoker set search_path='' as $$
  with filas as materialized (
    select x.item,x.orden,t.inversionista_id,t.perfil_id
    from jsonb_array_elements(p_items) with ordinality x(item,orden)
    left join crm.tareas t on t.id=(x.item->>'id')::uuid
  ), sujetos as materialized (
    select * from private.gestiones_clientes_identidades(coalesce((select jsonb_agg(to_jsonb(s))
      from (select distinct f.inversionista_id persona,f.perfil_id perfil from filas f
        where f.inversionista_id is not null or f.perfil_id is not null) s),'[]'))
  )
  select coalesce(jsonb_agg(f.item||coalesce(s.identidad,'{}') order by f.orden),'[]') from filas f
    left join sujetos s on s.persona is not distinct from f.inversionista_id and s.perfil is not distinct from f.perfil_id;
$$;

-- G4b conserva definición, scope y cursor. v2 solo añade el destino real del cliente.
create function crm.gestion_diaria_citas_v2_fn(p_dia date,p_ambito text,p_id uuid default null,p_limite integer default 25,
  p_despues_de timestamptz default null,p_despues_id uuid default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare v_r jsonb;
begin
  v_r:=crm.gestion_diaria_citas_fn(p_dia,p_ambito,p_id,p_limite,p_despues_de,p_despues_id);
  return jsonb_set(v_r||jsonb_build_object('version',2),'{items}',private.gestiones_identificar_tareas(v_r->'items'));
end;
$$;

-- La lista de pendientes también conserva su autoridad, total y cursor previos.
create function crm.gestion_diaria_pendientes_v2_fn(p_analista_id uuid,p_solo_vencidas boolean default false,
  p_limite integer default 25,p_despues_de timestamptz default null,p_despues_id uuid default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare v_r jsonb;
begin
  v_r:=crm.gestion_diaria_pendientes_fn(p_analista_id,p_solo_vencidas,p_limite,p_despues_de,p_despues_id);
  return jsonb_set(v_r||jsonb_build_object('version',2),'{items}',private.gestiones_identificar_tareas(v_r->'items'));
end;
$$;

-- ACL explícitas. Las funciones privadas siguen comprobando sesión al invocarse directamente.
revoke all on function private.gestiones_validar(date,date,uuid[]),private.gestion_cliente_identidad(uuid,uuid),
  private.gestiones_clientes_eventos(date,date,uuid[],boolean,integer,text[],timestamptz,uuid,text),
  private.gestiones_operativas_eventos(date,date,uuid[],boolean,integer,text[],timestamptz,uuid,text,text,text),
  private.gestiones_clientes_identidades(jsonb),private.gestiones_identificar_tareas(jsonb),
  private.citas_clientes_core(date,date,uuid[],integer,timestamptz,uuid),
  crm.registro_actividad_v2_fn(date,date,uuid[],text[],text,integer,timestamptz,uuid,text,text),
  crm.gestiones_resumen_fn(date,date,uuid[]),crm.citas_clientes_fn(date,date,uuid[],integer,timestamptz,uuid),
  crm.gestion_diaria_citas_v2_fn(date,text,uuid,integer,timestamptz,uuid),
  crm.gestion_diaria_pendientes_v2_fn(uuid,boolean,integer,timestamptz,uuid) from public,anon,authenticated,service_role;
grant execute on function private.gestiones_validar(date,date,uuid[]),private.gestion_cliente_identidad(uuid,uuid),
  private.gestiones_clientes_eventos(date,date,uuid[],boolean,integer,text[],timestamptz,uuid,text),
  private.gestiones_operativas_eventos(date,date,uuid[],boolean,integer,text[],timestamptz,uuid,text,text,text),
  private.gestiones_clientes_identidades(jsonb),private.gestiones_identificar_tareas(jsonb),
  private.citas_clientes_core(date,date,uuid[],integer,timestamptz,uuid),
  crm.registro_actividad_v2_fn(date,date,uuid[],text[],text,integer,timestamptz,uuid,text,text),
  crm.gestiones_resumen_fn(date,date,uuid[]),crm.citas_clientes_fn(date,date,uuid[],integer,timestamptz,uuid),
  crm.gestion_diaria_citas_v2_fn(date,text,uuid,integer,timestamptz,uuid),
  crm.gestion_diaria_pendientes_v2_fn(uuid,boolean,integer,timestamptz,uuid) to authenticated;

create index if not exists inversionista_gestiones_autor_fecha_idx
  on crm.inversionista_gestiones(creado_por,creado_en,id) where tipo='cierre';
create index if not exists inversionista_gestiones_cierre_tarea_idx
  on crm.inversionista_gestiones(tarea_id) where tipo='cierre';
create index if not exists actividades_cliente_autor_fecha_idx on crm.actividades_cliente(creado_por,creado_en,id);

comment on function private.gestiones_validar(date,date,uuid[]) is 'Autoriza las lecturas operativas por sesión real, rol activo, rango y árbol visible; fija los candados de modo y jerarquía.';
comment on function private.gestiones_clientes_identidades(jsonb) is 'Resuelve en lote la identidad actualmente visible del cliente; redacta nombre, referencias y acceso tras una reasignación.';
comment on function private.gestion_cliente_identidad(uuid,uuid) is 'Adaptador escalar de la resolución autorizada de identidad de cliente.';
comment on function private.gestiones_clientes_eventos(date,date,uuid[],boolean,integer,text[],timestamptz,uuid,text) is 'Gestiones de clientes atribuidas al autor real, sin duplicar cierres F6; el modo conteo no consulta identidad ni detalle privado.';
comment on function private.gestiones_operativas_eventos(date,date,uuid[],boolean,integer,text[],timestamptz,uuid,text,text,text) is 'Une actividad de leads bajo RLS y clientes bajo autorización explícita; limita cada fuente antes de presentar detalles.';
comment on function private.citas_clientes_core(date,date,uuid[],integer,timestamptz,uuid) is 'Citas de clientes por fecha programada, estado y resultado; una confirmación no acredita asistencia.';
comment on function private.gestiones_identificar_tareas(jsonb) is 'Añade identidad autorizada a una página existente de tareas sin alterar su población, orden ni cursor.';
comment on function crm.registro_actividad_v2_fn(date,date,uuid[],text[],text,integer,timestamptz,uuid,text,text) is 'Registro operativo v2 de leads y clientes con cursor compuesto, filtros y redacción de datos según el acceso actual.';
comment on function crm.gestiones_resumen_fn(date,date,uuid[]) is 'Resumen de gestiones por autor: leads, clientes y total. Llamadas contestadas e entrevistas exigen resultado registrado; no modifica las métricas de captación.';
comment on function crm.citas_clientes_fn(date,date,uuid[],integer,timestamptz,uuid) is 'Puerta de citas de clientes autorizadas por responsable, rango y paginación.';
comment on function crm.gestion_diaria_citas_v2_fn(date,text,uuid,integer,timestamptz,uuid) is 'G4b v2: conserva conteo, orden y cursor de citas agendadas, añadiendo la identidad autorizada del cliente.';
comment on function crm.gestion_diaria_pendientes_v2_fn(uuid,boolean,integer,timestamptz,uuid) is 'Pendientes v2: conserva población, orden y cursor, añadiendo la identidad autorizada del cliente.';
comment on index crm.inversionista_gestiones_autor_fecha_idx is 'Lectura de cierres de clientes por autor y fecha.';
comment on index crm.inversionista_gestiones_cierre_tarea_idx is 'Exclusión del espejo heredado cuando la tarea tiene un cierre F6.';
comment on index crm.actividades_cliente_autor_fecha_idx is 'Lectura de gestiones heredadas de clientes por autor y fecha.';
notify pgrst,'reload schema';
commit;

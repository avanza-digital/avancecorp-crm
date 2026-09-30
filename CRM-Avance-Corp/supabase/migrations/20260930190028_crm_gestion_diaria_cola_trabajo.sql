-- Gestión diaria: una vuelta persistente, completa y paginada por analista.
-- La actividad confirmada es la fuente del avance; no se escribe otra marca
-- de «atendido», no se cambia el reloj de conversación ni el motor SLA.
-- Puerta propia: no modifica los contratos de Hoy, Seguimiento ni cola v3.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $preflight$
begin
  if to_regprocedure('private.tareas_clientes_autorizadas(uuid,uuid[],text,boolean,timestamptz,timestamptz)') is null
     or to_regprocedure('private.sla_operacion_leads(uuid[],boolean,uuid[],timestamptz)') is null then
    raise exception 'GESTION_COLA: falta instalar la cola v3';
  end if;
end $preflight$;

-- Hechos por lead, sin el antiguo límite de 500. INVOKER sin grants API:
-- solamente la puerta puede ejecutarlo, con el actor obtenido de auth.uid().
create function private.gestion_diaria_cola_hechos(p_actor uuid, p_ahora timestamptz)
returns table (lead_id uuid, senal jsonb, gestion jsonb, proxima jsonb)
language plpgsql stable security invoker set search_path = ''
as $function$
begin
  return query
  with propios as (
    select l.*, greatest(coalesce(l.tenencia_desde,l.creado_en),
      coalesce(l.sla_global_iniciado_en,l.creado_en)) as desde
    from crm.leads l
    where l.vendedor_id=p_actor and l.activo and not coalesce(l.no_contactar,false)
      and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
  ), politica as (
    select coalesce((select dias_abandono from crm.politica_abandono where singleton),7) as dias
  )
  select l.id,
    jsonb_build_object('lead_id',l.id,'nombre_completo',l.nombre_completo,'etapa',l.etapa,
      'tenencia_desde',l.tenencia_desde,'ciclo_desde',coalesce(l.sla_global_iniciado_en,l.creado_en),
      'llamadas_ciclo',h.llamadas_ciclo,'intentos_sin_respuesta',h.intentos,
      'ultima_llamada_en',u.creado_en,'ultima_llamada_tipo',u.tipo,
      'ultima_llamada_resultado',u.metadata->>'resultado',
      'ultima_conversacion_en',conv.creado_en,
      'dias_sin_conversacion',greatest(floor(extract(epoch from (p_ahora-ref.desde))/86400),0)::integer,
      'sin_conversacion',ref.desde < p_ahora-make_interval(days=>(select dias from politica)),
      'numero_errado_detalle',ne.detalle,'numero_errado_en',ne.creado_en,
      'proxima_tarea_en',pt.vence_en,'proxima_tarea_tipo',pt.tipo),
    case when g.id is not null then jsonb_build_object('actividad_id',g.id,'en',g.creado_en,
      'resultado',g.metadata->>'resultado','tarea_id',g.metadata->>'tarea_id',
      'etapa_anterior',g.metadata->>'etapa_anterior','grupo_origen',
      case when origen_t.id is not null then case when origen_t.vence_en<g.primera_en then 'tarea_vencida' else 'tarea_hoy' end
        when g.primera_meta->>'etapa_anterior'='nuevo' and not exists (
          select 1 from crm.actividades a where a.lead_id=l.id and a.creado_en>=l.desde and a.creado_en<g.primera_en
            and a.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')
        ) then 'primera_atencion'
        when greatest(coalesce((select max(a.creado_en) from crm.actividades a where a.lead_id=l.id
          and a.creado_en<g.primera_en and a.tipo in ('llamada_realizada','whatsapp_recibido','reunion_realizada')),
          '-infinity'::timestamptz),coalesce(l.tenencia_desde,l.creado_en))<g.primera_en-make_interval(days=>(select dias from politica))
          then 'sin_conversacion' end) end,
    case when pt.id is not null then jsonb_build_object('tarea_id',pt.id,'vence_en',pt.vence_en,
      'tipo',pt.tipo,'creado_en',pt.creado_en) end
  from propios l
  left join lateral (
    select max(a.creado_en) as creado_en from crm.actividades a
    where a.lead_id=l.id and a.tipo in ('llamada_realizada','whatsapp_recibido','reunion_realizada')
  ) conv on true
  cross join lateral (
    select greatest(coalesce(conv.creado_en,'-infinity'::timestamptz),
      coalesce(l.tenencia_desde,l.creado_en)) as desde
  ) ref
  left join lateral (
    select a.creado_en,a.tipo,a.metadata from crm.actividades a
    where a.lead_id=l.id and a.tipo in ('llamada_realizada','llamada_no_contestada')
    order by a.creado_en desc,a.id desc limit 1
  ) u on true
  left join lateral (
    select count(*) filter (where a.tipo in ('llamada_realizada','llamada_no_contestada')
        and a.creado_en>=coalesce(l.sla_global_iniciado_en,l.creado_en))::integer as llamadas_ciclo,
      count(*) filter (where a.tipo in ('llamada_no_contestada','whatsapp_enviado')
        and coalesce(a.metadata->>'resultado','') not in ('numero_errado','no_es_la_persona')
        and a.creado_en>coalesce(conv.creado_en,'-infinity'::timestamptz))::integer as intentos
    from crm.actividades a where a.lead_id=l.id
  ) h on true
  left join lateral (
    select a.detalle,a.creado_en from crm.actividades a where a.lead_id=l.id
      and a.metadata->>'resultado' in ('numero_errado','no_es_la_persona') and a.creado_en>=l.desde
    order by a.creado_en desc,a.id desc limit 1
  ) ne on true
  -- El avance pertenece a ESTA tenencia y ciclo. Deshacer invalida la marca;
  -- las métricas históricas de llamadas siguen leyendo su fuente anterior.
  left join lateral (
    select a.id,a.creado_en,a.metadata,
      first_value(a.creado_en) over (order by a.creado_en,a.id) as primera_en,
      first_value(a.metadata) over (order by a.creado_en,a.id) as primera_meta
    from crm.actividades a where a.lead_id=l.id
      and a.creado_por=p_actor and a.tipo in ('llamada_realizada','llamada_no_contestada')
      and a.metadata->>'evento'='resultado_llamada' and not (a.metadata ? 'deshecho_en')
      and a.creado_en>=l.desde and a.creado_en<=p_ahora
      and a.creado_en>=((p_ahora at time zone 'America/Lima')::date::timestamp at time zone 'America/Lima')
    order by a.creado_en desc,a.id desc limit 1
  ) g on true
  left join crm.tareas origen_t on origen_t.id=case when g.primera_meta->>'tarea_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (g.primera_meta->>'tarea_id')::uuid end
    and origen_t.lead_id=l.id and origen_t.vendedor_id=p_actor
  left join lateral (
    select t.id,t.vence_en,t.tipo,t.creado_en from crm.tareas t where t.lead_id=l.id
      and t.vendedor_id=p_actor and t.activo and t.estado='pendiente'
    order by t.vence_en,t.id limit 1
  ) pt on true;
end;
$function$;
revoke all on function private.gestion_diaria_cola_hechos(uuid,timestamptz)
  from public,anon,authenticated,service_role;

-- Candidatas completas: la ventana autorizada SLA, los hechos del analista y
-- el ayudante de clientes de v3. Esta función no interpreta autenticación.
create function private.gestion_diaria_cola_filas(p_actor uuid,p_rol text,p_ahora timestamptz)
returns jsonb language plpgsql stable security invoker set search_path = ''
as $function$
declare v_hechos jsonb; v_ids uuid[]; v_sla jsonb; v_filas jsonb; v_fin timestamptz;
begin
  select coalesce(jsonb_agg(to_jsonb(h)),'[]'::jsonb),coalesce(array_agg(h.lead_id),'{}'::uuid[])
    into v_hechos,v_ids from private.gestion_diaria_cola_hechos(p_actor,p_ahora) h;
  -- Un array vacío significa ninguno, nunca NULL (todos los visibles).
  -- Cartera PROPIA ya acotada por hechos + puerta autenticada. El motor recibe
  -- global=false y sólo el actor visible. También para supervisor usamos su
  -- acción de ATENCIÓN; la cola personal no es un panel de supervisión.
  select jsonb_build_object('filas',coalesce(jsonb_agg(jsonb_build_object(
    'lead',s.presentacion,'accion',s.accion_atencion)),'[]'::jsonb)) into v_sla
  from private.sla_operacion_leads(v_ids,false,array[p_actor],p_ahora) s;
  v_fin:=(((p_ahora at time zone 'America/Lima')::date+1)::timestamp at time zone 'America/Lima');
  with hechos as (
    select h.value,h.value->'senal' as s,nullif(h.value->'gestion','null'::jsonb) as g,
      nullif(h.value->'proxima','null'::jsonb) as pt from jsonb_array_elements(v_hechos) h
  ), acciones as (
    select h.*,nullif(a.value->'accion','null'::jsonb) as accion
    from hechos h left join jsonb_array_elements(v_sla->'filas') a
      on a.value#>>'{lead,id}'=h.s->>'lead_id'
  ), grupos as (
    select a.*,
      case when a.g->>'grupo_origen' is not null and (a.pt is null
          or (a.pt->>'vence_en')::timestamptz>p_ahora or (a.pt->>'vence_en')::timestamptz<=(a.g->>'en')::timestamptz)
          then a.g->>'grupo_origen'
        when a.accion->>'bucket' in ('primera_atencion','tarea_vencida','tarea_hoy') then a.accion->>'bucket'
        when (a.s->>'sin_conversacion')::boolean then 'sin_conversacion'
        -- Conserva el trabajo terminado de hoy aunque el cierre haya retirado
        -- la acción SLA. Su tarea cerrada acredita el grupo de la vuelta.
        when a.g->>'grupo_origen' is not null then a.g->>'grupo_origen'
        when t.id is not null then case when t.vence_en<(a.g->>'en')::timestamptz then 'tarea_vencida' else 'tarea_hoy' end
      end as grupo,
      t.vence_en as referencia_cerrada
    from acciones a left join crm.tareas t on t.id=case when a.g->>'tarea_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (a.g->>'tarea_id')::uuid end
      and t.lead_id=(a.s->>'lead_id')::uuid and t.vendedor_id=p_actor
  ), estados as (
    select g.*,
      case
        -- Una gestión atiende la vuelta. Una tarea anterior sigue abierta en
        -- Agenda, pero no vuelve a proponer el mismo lead inmediatamente.
        -- Sólo un vencimiento posterior a esa gestión reabre su turno.
        when g.g is not null and (g.pt is null or (g.pt->>'vence_en')::timestamptz<=(g.g->>'en')::timestamptz) then 'gestionado'
        when g.pt is not null and (g.pt->>'vence_en')::timestamptz<=p_ahora then 'pendiente'
        when g.pt is not null and (g.pt->>'vence_en')::timestamptz>p_ahora then 'programado'
        when g.g is not null then 'gestionado'
        else 'pendiente'
      end as estado_trabajo
    from grupos g where g.grupo is not null
  ), leads as (
    select jsonb_build_object('tipo','lead','clave','lead:'||(e.s->>'lead_id'),
      'lead_id',e.s->'lead_id','nombre_completo',e.s->'nombre_completo','etapa',e.s->'etapa',
      'grupo',e.grupo,'referencia_en',coalesce(nullif(e.accion->>'referencia_en','')::timestamptz,
        e.referencia_cerrada,nullif(e.s->>'ultima_conversacion_en','')::timestamptz,
        nullif(e.s->>'tenencia_desde','')::timestamptz),
      'tarea_id',case when e.estado_trabajo='pendiente' then coalesce(nullif(e.accion->'tarea_id','null'::jsonb),e.pt->'tarea_id') else null end,
      'severidad',coalesce(e.accion->>'severidad','media'),'senal',e.s,
      'estado_trabajo',e.estado_trabajo,'ultima_gestion',e.g,'proxima_tarea',e.pt) as fila
    from estados e
  ), clientes as (
    select jsonb_build_object('tipo','cliente','clave','tarea:'||c.tarea_id::text,
      'lead_id',null,'etapa',null,'senal',null,'nombre_completo',c.nombre,'grupo',c.bucket,
      'referencia_en',c.vence_en,'tarea_id',c.tarea_id,'severidad',case when c.bucket='tarea_vencida' then 'critica' else 'media' end,
      'perfil_id',c.perfil_id,'inversionista_id',c.inversionista_id,
      'estado_trabajo','pendiente','ultima_gestion',null,'proxima_tarea',null) as fila
    from private.tareas_clientes_autorizadas(p_actor,array[p_actor],p_rol,false,p_ahora,v_fin) c
    where c.responsable_id=p_actor
  )
  select coalesce(jsonb_agg(fila),'[]'::jsonb) into v_filas from (
    select fila from leads union all select fila from clientes
  ) u;
  return v_filas;
end;
$function$;
revoke all on function private.gestion_diaria_cola_filas(uuid,text,timestamptz)
  from public,anon,authenticated,service_role;

-- La clave elegida es un ancla de lectura: se busca en la cola AUTORIZADA y
-- se devuelve su página actual. Nunca permite leer un lead fuera del actor.
-- Cada respuesta contiene una foto coherente, conteos completos y siguiente.
create function crm.gestion_diaria_cola_trabajo_fn(
  p_filtro text default 'todo',p_pagina integer default 0,p_limite integer default 8,p_elegido text default null
) returns jsonb language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_actor uuid:=(select auth.uid()); v_rol text; v_ahora timestamptz:=statement_timestamp();
  v_filas jsonb; v_ordenadas jsonb; v_totales jsonb; v_filtro text:=p_filtro;
  v_total integer; v_pagina integer; v_posicion integer; v_pendientes integer; v_items jsonb;
  v_elegido text; v_siguiente text; v_grupo text;
begin
  if v_actor is null or private.puede_acceder_crm() is not true then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_rol:=private.rol_crm(v_actor);
  if v_rol is null or v_rol not in ('vendedor','supervisor') then
    raise exception 'Esta cola es del analista que gestiona' using errcode='42501';
  end if;
  if p_filtro is null or p_filtro not in ('todo','primera_atencion','tarea_vencida','tarea_hoy','sin_conversacion')
    or p_pagina is null or p_pagina<0 or p_pagina>1000000
    or p_limite is null or p_limite not between 1 and 200
    or (p_elegido is not null and p_elegido !~ '^(lead|tarea):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
    raise exception 'Filtro, pagina o seleccion invalidos' using errcode='22023';
  end if;
  v_filas:=private.gestion_diaria_cola_filas(v_actor,v_rol,v_ahora);
  select f.value->>'grupo' into v_grupo from jsonb_array_elements(v_filas) f where f.value->>'clave'=p_elegido;
  if v_grupo is not null and p_filtro<>'todo' then v_filtro:=v_grupo; end if;

  select jsonb_object_agg(g.grupo,jsonb_build_object('total',g.total,'pendientes',g.pendientes,
    'gestionados',g.gestionados,'programados',g.programados)) into v_totales
  from (
    select grupos.grupo,count(f.value)::integer as total,
      count(f.value) filter (where f.value->>'estado_trabajo'='pendiente')::integer as pendientes,
      count(f.value) filter (where f.value->>'estado_trabajo'='gestionado')::integer as gestionados,
      count(f.value) filter (where f.value->>'estado_trabajo'='programado')::integer as programados
    from unnest(array['todo','primera_atencion','tarea_vencida','tarea_hoy','sin_conversacion']) grupos(grupo)
    left join jsonb_array_elements(v_filas) f on grupos.grupo='todo' or f.value->>'grupo'=grupos.grupo
    group by grupos.grupo
  ) g;

  -- Orden completo ANTES del límite. Pendientes conservan la prioridad SLA;
  -- gestionados/programados quedan detrás y el último guardado queda último.
  select coalesce(jsonb_agg(f.value order by
    (f.value->>'estado_trabajo'<>'pendiente'),
    case when f.value->>'estado_trabajo'='pendiente' then
      case f.value->>'grupo' when 'primera_atencion' then 10 when 'tarea_vencida' then 20 when 'tarea_hoy' then 30 else 40 end else 0 end,
    case when f.value->>'estado_trabajo'='pendiente' then (f.value->>'referencia_en')::timestamptz end nulls last,
    case when f.value->>'estado_trabajo'<>'pendiente' then (f.value#>>'{ultima_gestion,en}')::timestamptz end nulls first,
    (f.value->>'clave') collate "C"),'[]'::jsonb) into v_ordenadas
  from jsonb_array_elements(v_filas) f where v_filtro='todo' or f.value->>'grupo'=v_filtro;
  v_total:=jsonb_array_length(v_ordenadas);
  v_pendientes:=(v_totales->v_filtro->>'pendientes')::integer;
  select (f.n-1)::integer into v_posicion from jsonb_array_elements(v_ordenadas) with ordinality f(value,n)
    where f.value->>'clave'=p_elegido;
  v_pagina:=case when v_posicion is not null then v_posicion/p_limite
    else least(p_pagina,greatest((v_total-1)/p_limite,0)) end;
  select coalesce(jsonb_agg(f.value order by f.n),'[]'::jsonb) into v_items
    from jsonb_array_elements(v_ordenadas) with ordinality f(value,n)
    where f.n>v_pagina*p_limite and f.n<=(v_pagina+1)*p_limite;
  v_elegido:=case when v_posicion is not null then p_elegido else (
    select f.value->>'clave' from jsonb_array_elements(v_items) f
    where f.value->>'estado_trabajo'='pendiente' limit 1) end;
  select f.value->>'clave' into v_siguiente
    from jsonb_array_elements(v_ordenadas) with ordinality f(value,n)
    where f.value->>'estado_trabajo'='pendiente' and f.value->>'clave' is distinct from v_elegido
    order by case when f.n-1>coalesce(v_posicion,v_pagina*p_limite) then 0 else 1 end,f.n limit 1;
  return jsonb_build_object('version',1,'dia',(v_ahora at time zone 'America/Lima')::date,
    'zona','America/Lima','analista_id',v_actor,'generado_en',v_ahora,'filtro',v_filtro,
    'pagina',v_pagina,'limite',p_limite,'total',v_total,'totales',v_totales,'items',v_items,
    'elegido',v_elegido,'siguiente',v_siguiente,'vuelta_completa',v_pendientes=0,
    'proximo_cambio_en',least(
      (((v_ahora at time zone 'America/Lima')::date+1)::timestamp at time zone 'America/Lima'),
      (select min(x.en) from jsonb_array_elements(v_filas) f cross join lateral (
        select case when f.value->>'tipo'='cliente' then (f.value->>'referencia_en')::timestamptz
          else (f.value#>>'{proxima_tarea,vence_en}')::timestamptz end as en
      ) x where x.en>v_ahora)));
end;
$function$;
revoke all on function crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text)
  from public,anon,authenticated,service_role;
grant execute on function crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text) to authenticated;

comment on function crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text) is
  'Cola completa del propio analista: pendientes antes de gestionados, avance por actividad vigente en Lima, filtro y pagina anclada por clave. DEFINER porque compone ayudantes privados sin grants API; actor exclusivamente auth.uid().';

notify pgrst,'reload schema';
commit;

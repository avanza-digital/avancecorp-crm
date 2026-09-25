-- F5: proyecciones gerenciales completas, organigrama actual y hábitos.
-- Candidata local. No instala ni activa TypeSafe ni cambia políticas de avisos.
-- Los consumidores anteriores de llamadas conservan firma y salida. NULL en
-- el array solicita explícitamente registros sin autor; un array vacío no.
begin;

-- Fuente única de eventos para el marcador, los únicos globales y los huecos.
-- La autorización de filas sigue en RLS; cada llamador limita los autores.
create or replace function private.gestion_diaria_llamadas_eventos(
  p_ini timestamptz,p_fin timestamptz,p_vendedor_ids uuid[])
returns table(vendedor_id uuid,id uuid,lead_id uuid,tipo text,creado_en timestamptz,
  resultado text,util boolean,hora integer)
language sql stable security invoker set search_path='' as $$
  select a.creado_por,a.id,a.lead_id,a.tipo,a.creado_en,
    coalesce(a.metadata->>'resultado','sin_resultado'),
    coalesce(a.metadata->>'resultado','') not in ('numero_errado','no_es_la_persona'),
    extract(hour from a.creado_en at time zone 'America/Lima')::integer
  from crm.actividades a where
    (a.creado_por=any(p_vendedor_ids)
      or (a.creado_por is null and array_position(p_vendedor_ids,null) is not null))
    and a.tipo in ('llamada_realizada','llamada_no_contestada')
    and a.creado_en>=p_ini and a.creado_en<p_fin;
$$;

-- Hechos de gestión, con la misma definición de actividad de F4.
create or replace function private.gestion_diaria_gestiones_eventos(p_ini timestamptz,p_fin timestamptz)
returns table(id uuid,creado_por uuid,creado_en timestamptz)
language sql stable security invoker set search_path='' as $$
  select a.id,a.creado_por,a.creado_en from crm.actividades a
  where a.creado_en>=p_ini and a.creado_en<p_fin
    and a.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado',
      'reunion_realizada','nota','conversion');
$$;

CREATE OR REPLACE FUNCTION private.gestion_diaria_llamadas(p_ini timestamp with time zone, p_fin timestamp with time zone, p_vendedor_ids uuid[])
 RETURNS TABLE(vendedor_id uuid, llamadas integer, contestadas integer, utiles integer, leads_tocados integer, citas_agendadas integer, primera_llamada_en timestamp with time zone, ultima_llamada_en timestamp with time zone, por_resultado jsonb, por_hora jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with vendedores as (
    select distinct v.id from unnest(p_vendedor_ids) as v(id)
  ),
  ll as (
    select * from private.gestion_diaria_llamadas_eventos(p_ini,p_fin,p_vendedor_ids)
  ),
  agg as (
    select l.vendedor_id,
           cardinality(array_agg(l.id)) as llamadas,
           -- Contestadas ⊆ útiles POR CONSTRUCCIÓN: la tasa nunca puede pasar del
           -- 100 % aunque una fila histórica llevara un resultado incoherente
           -- con su tipo (hoy no hay ninguna: medido en producción el 20/09).
           coalesce(cardinality(array_agg(l.id) filter (where l.tipo = 'llamada_realizada' and l.util)), 0) as contestadas,
           coalesce(cardinality(array_agg(l.id) filter (where l.util)), 0) as utiles,
           cardinality(array_agg(distinct l.lead_id)) as leads_tocados,
           min(l.creado_en) as primera_llamada_en,
           max(l.creado_en) as ultima_llamada_en
    from ll l
    group by l.vendedor_id
  ),
  por_resultado as (
    select r.vendedor_id, jsonb_object_agg(r.resultado, r.n) as por_resultado
    from (
      select l.vendedor_id, l.resultado, cardinality(array_agg(l.id)) as n
      from ll l
      group by l.vendedor_id, l.resultado
    ) r
    group by r.vendedor_id
  ),
  por_hora as (
    select h.vendedor_id,
           jsonb_agg(jsonb_build_object('hora', h.hora, 'llamadas', h.n, 'contestadas', h.c) order by h.hora) as por_hora
    from (
      select l.vendedor_id, l.hora, cardinality(array_agg(l.id)) as n,
             coalesce(cardinality(array_agg(l.id) filter (where l.tipo = 'llamada_realizada')), 0) as c
      from ll l
      group by l.vendedor_id, l.hora
    ) h
    group by h.vendedor_id
  ),
  citas as (
    -- Cita agendada = tarea de cita CREADA en la ventana por el analista (la
    -- misma definición que metricas_agenda_fn). Las reprogramadas crean otra
    -- tarea y cuentan igual que allí.
    select t.vendedor_id, cardinality(array_agg(t.id)) as citas_agendadas
    from crm.tareas t
    where (t.vendedor_id in (select v.id from vendedores v)
      or (t.vendedor_id is null and array_position(p_vendedor_ids, null) is not null))
      and t.tipo = 'reunion'
      and t.creado_en >= p_ini
      and t.creado_en <  p_fin
    group by t.vendedor_id
  )
  select v.id,
         coalesce(a.llamadas, 0),
         coalesce(a.contestadas, 0),
         coalesce(a.utiles, 0),
         coalesce(a.leads_tocados, 0),
         coalesce(c.citas_agendadas, 0),
         a.primera_llamada_en,
         a.ultima_llamada_en,
         coalesce(r.por_resultado, '{}'::jsonb),
         coalesce(h.por_hora, '[]'::jsonb)
  from vendedores v
  left join agg a on a.vendedor_id is not distinct from v.id
  left join por_resultado r on r.vendedor_id is not distinct from v.id
  left join por_hora h on h.vendedor_id is not distinct from v.id
  left join citas c on c.vendedor_id is not distinct from v.id
  order by v.id;
$function$;

create or replace function private.gestion_diaria_pulso_autorizar()
returns void language plpgsql stable security invoker set search_path='' as $$
begin
  if auth.uid() is null or not private.puede_acceder_crm()
    or not (coalesce(private.rol_crm(auth.uid())='gerencia',false)
      or coalesce(private.es_lector_global(),false)) then
    raise exception 'Solo gerencia puede consultar toda la operación' using errcode='42501';
  end if;
end $$;

-- Partición disjunta de vendedores activos, incluso con puentes revocados,
-- supervisores anidados y ciclos en un organigrama heredado.
create or replace function private.gestion_diaria_pulso_roster()
returns table(analista_id uuid,nombre_completo text,supervisor_id uuid)
language plpgsql stable security invoker set search_path='' as $$
begin
  perform private.gestion_diaria_pulso_autorizar();
  return query
  with recursive visibles as materialized (select * from crm.equipo_visible_fn()),
  vendedores as (select e.* from visibles e where e.activo and e.rol_crm='vendedor'),
  ascendientes as (
    select v.perfil_id as analista,v.supervisor_id as ancestro,
      array[v.perfil_id] as camino,1 as profundidad from vendedores v
    union all
    select a.analista,e.supervisor_id,a.camino||a.ancestro,a.profundidad+1
    from ascendientes a join crm.equipo e on e.perfil_id=a.ancestro
    where a.ancestro is not null and not a.ancestro=any(a.camino)
  )
  select v.perfil_id,v.nombre_completo,
    (select a.ancestro from ascendientes a join visibles s on s.perfil_id=a.ancestro
      where a.analista=v.perfil_id and s.activo and s.rol_crm='supervisor'
      and not a.ancestro=any(a.camino) order by a.profundidad,a.ancestro limit 1)
  from vendedores v order by v.perfil_id;
end $$;

-- Identidades a proyectar, sin inferir el universo de una colección paginada.
create or replace function private.gestion_diaria_pulso_autores(p_ini timestamptz,p_fin timestamptz)
returns table(id uuid) language plpgsql stable security invoker set search_path='' as $$
begin
  perform private.gestion_diaria_pulso_autorizar();
  return query select r.analista_id from private.gestion_diaria_pulso_roster() r
    union select g.creado_por from private.gestion_diaria_gestiones_eventos(p_ini,p_fin) g
    union select t.vendedor_id from crm.tareas t where
      t.tipo='reunion' and t.creado_en>=p_ini and t.creado_en<p_fin;
end $$;

-- Calendario real de gestiones/citas creadas; los días vacíos no forman la base.
create or replace function private.gestion_diaria_fechas_activas(p_desde date,p_hasta date)
returns table(dia date) language plpgsql stable security invoker set search_path='' as $$
begin
  perform private.gestion_diaria_pulso_autorizar();
  return query select distinct (g.creado_en at time zone 'America/Lima')::date
    from private.gestion_diaria_gestiones_eventos(p_desde::timestamp at time zone 'America/Lima',
      p_hasta::timestamp at time zone 'America/Lima') g
    union select distinct (t.creado_en at time zone 'America/Lima')::date
    from crm.tareas t where t.tipo='reunion'
      and t.creado_en>=p_desde::timestamp at time zone 'America/Lima'
      and t.creado_en<p_hasta::timestamp at time zone 'America/Lima';
end $$;

-- Agregación de hechos ya contados por el núcleo. Los únicos se pasan
-- deduplicados para el ámbito; nunca se suman los únicos de las personas.
create or replace function private.gestion_diaria_pulso_metricas(p_personas jsonb,p_leads integer)
returns jsonb language sql immutable security invoker set search_path='' as $$
  select jsonb_build_object(
    'llamadas',coalesce(sum(p.llamadas),0),
    'utiles',coalesce(sum(p.utiles),0),
    'contestadas',coalesce(sum(p.contestadas),0),
    'tasa_contacto',round(100.0*sum(p.contestadas)/nullif(sum(p.utiles),0),1),
    'leads_unicos',p_leads,
    'llamadas_por_lead',round(sum(p.llamadas)::numeric/nullif(p_leads,0),2),
    'citas_agendadas',coalesce(sum(p.citas_agendadas),0),
    'analistas_activos',count(*) filter(where p.activo),
    'con_actividad',count(*) filter(where p.activo and p.gestiones>0),
    'sin_actividad',count(*) filter(where p.activo and p.gestiones=0))
  from jsonb_to_recordset(p_personas) p(llamadas integer,utiles integer,
    contestadas integer,citas_agendadas integer,activo boolean,gestiones integer);
$$;

-- Una proyección por jornada, autosuficiente para pulso y hábitos.
-- El conjunto de autores incluye historia y asignaciones nulas, no sólo roster.
create or replace function private.gestion_diaria_pulso_dia(p_dia date)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
  v_ini timestamptz:=p_dia::timestamp at time zone 'America/Lima';
  v_fin timestamptz:=(p_dia+1)::timestamp at time zone 'America/Lima';
  v_personas jsonb; v_unicos integer; v_por_equipo jsonb; v_minimo integer; v_ids uuid[];
begin
  perform private.gestion_diaria_pulso_autorizar();
  if p_dia is null or not isfinite(p_dia) then
    raise exception 'Día inválido' using errcode='22023';
  end if;
  v_minimo:=(private.gestion_diaria_umbrales(v_ini)->>'minimo_llamadas_utiles')::integer;
  if v_minimo is null then raise exception 'No se pudo confirmar el mínimo vigente' using errcode='22000'; end if;
  select coalesce(array_agg(a.id),'{}'::uuid[]) into v_ids
    from private.gestion_diaria_pulso_autores(v_ini,v_fin) a;
  with roster as materialized (select * from private.gestion_diaria_pulso_roster()),
  gestiones as materialized (
    select a.creado_por,count(*)::integer as gestiones
    from private.gestion_diaria_gestiones_eventos(v_ini,v_fin) a
    group by a.creado_por
  ), llamadas as materialized (
    select * from private.gestion_diaria_llamadas(v_ini,v_fin,v_ids)
  )
  select coalesce(jsonb_agg(to_jsonb(l)||jsonb_build_object(
      'analista_id',l.vendedor_id,'nombre_completo',coalesce(r.nombre_completo,n.nombre_completo),
      'activo',r.analista_id is not null,'supervisor_id',r.supervisor_id,
      'clave_equipo',coalesce(r.supervisor_id::text,'fuera'),
      'gestiones',coalesce(g.gestiones,0)) order by l.vendedor_id),'[]'::jsonb)
    into v_personas
  from llamadas l left join roster r on r.analista_id=l.vendedor_id
    left join crm.equipo_visible_fn() n on n.perfil_id=l.vendedor_id
    left join gestiones g on g.creado_por is not distinct from l.vendedor_id;

  -- Mismo universo de eventos; distinta granularidad para deduplicar un lead
  -- compartido entre autores/equipos. No es otro contador de llamadas.
  with roster as materialized (select * from private.gestion_diaria_pulso_roster()),
  eventos as materialized (
    select a.lead_id,coalesce(r.supervisor_id::text,'fuera') as clave_equipo
    from private.gestion_diaria_llamadas_eventos(v_ini,v_fin,v_ids) a
    left join roster r on r.analista_id=a.vendedor_id
  ), por_equipo as (
    select clave_equipo,count(distinct lead_id) as n from eventos group by clave_equipo
  ) select (select count(distinct lead_id)::integer from eventos),
      coalesce((select jsonb_object_agg(clave_equipo,n) from por_equipo),'{}'::jsonb)
    into v_unicos,v_por_equipo;
  return jsonb_build_object('dia',p_dia,'minimo_llamadas_utiles',v_minimo,
    'metricas',private.gestion_diaria_pulso_metricas(v_personas,v_unicos),
    'personas',v_personas,'leads_por_equipo',v_por_equipo);
end $$;

create or replace function crm.gestion_diaria_pulso_fn(p_dia date default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
  v_ahora timestamptz:=statement_timestamp();
  v_hoy date:=(v_ahora at time zone 'America/Lima')::date;
  v_dia date:=coalesce(p_dia,v_hoy); v_fecha date; v_base date[];
  v_dias jsonb:='[]'; v_actual jsonb; v_ayer jsonb; v_media jsonb;
  v_sla jsonb; v_equipos jsonb; v_vencidas integer; v_dias_tasa integer;
begin
  perform private.gestion_diaria_pulso_autorizar();
  if not isfinite(v_dia) or v_dia>v_hoy or v_hoy-v_dia>365 then
    raise exception 'Día inválido: elige hoy o los últimos 365 días' using errcode='22023';
  end if;
  select coalesce(array_agg(d order by d desc),'{}'::date[]) into v_base from (
    select dia as d from private.gestion_diaria_fechas_activas(v_dia-365,v_dia)
    order by dia desc limit 7
  ) fechas;
  for v_fecha in select distinct unnest(array[v_dia,v_dia-1]||v_base) loop
    v_dias:=v_dias||jsonb_build_array(private.gestion_diaria_pulso_dia(v_fecha));
  end loop;
  select d into v_actual from jsonb_array_elements(v_dias) d where d->>'dia'=v_dia::text;
  select d into v_ayer from jsonb_array_elements(v_dias) d where d->>'dia'=(v_dia-1)::text;
  select jsonb_build_object(
    'llamadas',round(avg((d#>>'{metricas,llamadas}')::numeric),2),
    'utiles',round(avg((d#>>'{metricas,utiles}')::numeric),2),
    'contestadas',round(avg((d#>>'{metricas,contestadas}')::numeric),2),
    'tasa_contacto',round(100.0*sum((d#>>'{metricas,contestadas}')::numeric)
      /nullif(sum((d#>>'{metricas,utiles}')::numeric),0),1),
    'leads_unicos',round(avg((d#>>'{metricas,leads_unicos}')::numeric),2),
    'llamadas_por_lead',round(sum((d#>>'{metricas,llamadas}')::numeric)
      /nullif(sum((d#>>'{metricas,leads_unicos}')::numeric),0),2),
    'citas_agendadas',round(avg((d#>>'{metricas,citas_agendadas}')::numeric),2),
    'analistas_activos',round(avg((d#>>'{metricas,analistas_activos}')::numeric),2),
    'con_actividad',round(avg((d#>>'{metricas,con_actividad}')::numeric),2),
    'sin_actividad',round(avg((d#>>'{metricas,sin_actividad}')::numeric),2)),
    count(*) filter(where d#>>'{metricas,tasa_contacto}' is not null)::integer
    into v_media,v_dias_tasa
    from jsonb_array_elements(v_dias) d where (d->>'dia')::date=any(v_base);
  v_sla:=private.gestion_diaria_equipo_pendientes();
  with roster as materialized (select * from private.gestion_diaria_pulso_roster()),
  grupos as (
    select e.perfil_id as supervisor_id,e.perfil_id::text as clave,e.nombre_completo as nombre
    from crm.equipo_visible_fn() e where e.activo and e.rol_crm='supervisor'
    union all select null::uuid,'fuera','Fuera de equipos comerciales'
  ), vencidas as materialized (
    select coalesce(r.supervisor_id::text,'fuera') as clave,count(*)::integer as n
    from crm.tareas t left join roster r on r.analista_id=t.vendedor_id
    where t.activo and t.estado='pendiente' and t.vence_en<v_ahora
    group by 1
  ), primeros as (
    select coalesce(r.supervisor_id::text,'fuera') as clave,
      sum((f->>'primer_intento_vencido')::integer)::integer as n
    from jsonb_array_elements(v_sla->'filas') f
    left join roster r on r.analista_id=(f->>'analista_id')::uuid group by 1
  ), filas as (
    select g.*,p.personas,
      private.gestion_diaria_pulso_metricas(p.personas,
        coalesce((v_actual->'leads_por_equipo'->>g.clave)::integer,0)) as metricas,
      coalesce(v.n,0) as tareas_vencidas,
      case when v_sla->>'modo'='activo' then coalesce(s.n,0) end as primer_intento_vencido,
      (select jsonb_build_object('personas',count(*),'minimo',min(tasa),'maximo',max(tasa))
       from (select 100.0*(x->>'contestadas')::numeric/nullif((x->>'utiles')::numeric,0) as tasa
         from jsonb_array_elements(p.personas) x where (x->>'activo')::boolean
           and (x->>'utiles')::integer>=(v_actual->>'minimo_llamadas_utiles')::integer) tasas) as dispersion
    from grupos g
    cross join lateral (select coalesce(jsonb_agg(x order by x->>'analista_id'),'[]'::jsonb) as personas
      from jsonb_array_elements(v_actual->'personas') x where x->>'clave_equipo'=g.clave) p
    left join vencidas v on v.clave=g.clave left join primeros s on s.clave=g.clave
  ) select coalesce(jsonb_agg(to_jsonb(f) order by f.tareas_vencidas desc,f.clave),'[]'::jsonb),
      coalesce((select sum(n)::integer from vencidas),0) into v_equipos,v_vencidas from filas f;
  return jsonb_build_object('version',1,'dia',v_dia,'generado_en',v_ahora,
    'organigrama_referencia','consulta_actual','minimo_llamadas_utiles',v_actual->'minimo_llamadas_utiles',
    'actual',v_actual->'metricas','ayer',jsonb_build_object('dia',v_dia-1,'metricas',v_ayer->'metricas'),
    'referencia',jsonb_build_object('dias',to_jsonb(v_base),'busqueda_desde',v_dia-365,
      'cantidad',cardinality(v_base),'dias_con_tasa',v_dias_tasa,'media',v_media),
    'equipos',v_equipos,'pendientes_al',v_ahora,'modo_sla',v_sla->'modo','vencidas_global',v_vencidas);
end $$;

-- Las secuencias añaden horarios al núcleo; no recalculan sus contadores.
create or replace function private.gestion_diaria_habitos_jornada(
  p_dia date,p_analistas uuid[],p_ahora timestamptz)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
  v_inicio timestamptz; v_cierre timestamptz; v_fin timestamptz; v_datos jsonb;
  v_dow integer:=extract(isodow from p_dia);
begin
  perform private.gestion_diaria_pulso_autorizar();
  if v_dow<>7 then
    v_inicio:=(p_dia+time '09:00') at time zone 'America/Lima';
    v_cierre:=(p_dia+case when v_dow=6 then time '13:00' else time '18:00' end) at time zone 'America/Lima';
    v_fin:=greatest(v_inicio,least(p_ahora,v_cierre));
  end if;
  with eventos as materialized (
    select a.vendedor_id as creado_por,a.id,a.creado_en,
      lag(a.creado_en) over(partition by a.vendedor_id order by a.creado_en,a.id) as anterior
    from private.gestion_diaria_llamadas_eventos(v_inicio,v_fin,p_analistas) a
  ), huecos as (
    select e.*,row_number() over(partition by e.creado_por
      order by e.creado_en-e.anterior desc,e.anterior,e.creado_en,e.id) as posicion
    from eventos e where e.anterior is not null
  ), extremos as (
    select creado_por,min(creado_en) as primera,max(creado_en) as ultima
    from eventos group by creado_por
  ) select coalesce(jsonb_agg(jsonb_build_object('analista_id',r.id,
      'estado',case when v_dow=7 then 'no_laborable' when p_ahora<v_inicio then 'no_iniciada'
        when p_ahora<v_cierre then 'en_curso' else 'finalizada' end,
      'inicio',v_inicio,'cierre',v_cierre,'observado_hasta',v_fin,
      'primera_en_jornada',e.primera,'ultima_en_jornada',e.ultima,
      'silencio_inicio_minutos',case when v_inicio is not null then
        round(extract(epoch from(coalesce(e.primera,v_fin)-v_inicio))/60,1) end,
      'silencio_final_minutos',case when v_fin is not null then
        round(extract(epoch from(v_fin-coalesce(e.ultima,v_inicio)))/60,1) end,
      'hueco',case when h.anterior is not null then jsonb_build_object(
        'desde',h.anterior,'hasta',h.creado_en,
        'minutos',round(extract(epoch from(h.creado_en-h.anterior))/60,1)) end
    ) order by r.id),'[]'::jsonb) into v_datos
    from unnest(p_analistas) r(id)
    left join extremos e on e.creado_por=r.id
    left join huecos h on h.creado_por=r.id and h.posicion=1;
  return v_datos;
end $$;

create or replace function crm.gestion_diaria_habitos_fn(p_hasta date default null,p_dias integer default 14)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
  v_ahora timestamptz:=statement_timestamp();
  v_hoy date:=(v_ahora at time zone 'America/Lima')::date;
  v_hasta date:=coalesce(p_hasta,v_hoy); v_desde date; v_fecha date;
  v_ids uuid[]; v_fotos jsonb:='[]'; v_foto jsonb; v_cortes jsonb;
  v_jornada jsonb; v_dias jsonb; v_personas jsonb; v_operacion jsonb;
begin
  perform private.gestion_diaria_pulso_autorizar();
  if not isfinite(v_hasta) or v_hasta>v_hoy or v_hoy-v_hasta>365
    or p_dias is null or p_dias not in (7,14,30) then
    raise exception 'Período inválido: usa 7, 14 o 30 días hasta una fecha permitida' using errcode='22023';
  end if;
  -- El informe respeta el mismo límite histórico que la puerta de cortes.
  v_desde:=greatest(v_hoy-365,v_hasta-(p_dias-1));
  select coalesce(array_agg(r.analista_id),'{}'::uuid[]) into v_ids
    from private.gestion_diaria_pulso_roster() r;
  for v_fecha in select v_desde+i from generate_series(0,v_hasta-v_desde) i loop
    v_foto:=private.gestion_diaria_pulso_dia(v_fecha);
    v_cortes:=private.gestion_diaria_cortes(v_fecha,v_ids,v_ahora);
    v_jornada:=private.gestion_diaria_habitos_jornada(v_fecha,v_ids,v_ahora);
    v_fotos:=v_fotos||jsonb_build_array(v_foto||jsonb_build_object('cortes',v_cortes,'jornadas',v_jornada));
  end loop;
  select jsonb_build_object('llamadas',coalesce(sum((d#>>'{metricas,llamadas}')::bigint),0),
      'utiles',coalesce(sum((d#>>'{metricas,utiles}')::bigint),0),
      'contestadas',coalesce(sum((d#>>'{metricas,contestadas}')::bigint),0),
      'tasa_contacto',round(100.0*sum((d#>>'{metricas,contestadas}')::numeric)
        /nullif(sum((d#>>'{metricas,utiles}')::numeric),0),1))
    into v_operacion from jsonb_array_elements(v_fotos) d;
  with fotos as materialized (select value as foto from jsonb_array_elements(v_fotos)),
  diarios as materialized (
    select (p->>'analista_id')::uuid as analista_id,jsonb_build_object(
      'dia',f.foto->'dia','llamadas',p->'llamadas','utiles',p->'utiles','contestadas',p->'contestadas',
      'primera_llamada_en',p->'primera_llamada_en','ultima_llamada_en',p->'ultima_llamada_en',
      'tasa_contacto',round(100.0*(p->>'contestadas')::numeric/nullif((p->>'utiles')::numeric,0),1),
      'minimo_llamadas_utiles',f.foto->'minimo_llamadas_utiles',
      'jornada',(select j from jsonb_array_elements(f.foto->'jornadas') j where j->>'analista_id'=p->>'analista_id'),
      'cortes',jsonb_build_object('estado',f.foto#>'{cortes,estado}',
        'politica_version',f.foto#>'{cortes,politica_version}',
        'cartera_referencia',f.foto#>'{cortes,cartera_referencia}',
        'primer_corte',c.fila->'primer_corte','segundo_corte',c.fila->'segundo_corte')
      ) as datos
    from fotos f cross join lateral jsonb_array_elements(f.foto->'personas') p
    left join lateral (select x as fila from jsonb_array_elements(f.foto#>'{cortes,equipo}') x
      where x->>'analista_id'=p->>'analista_id') c on true
    where (p->>'activo')::boolean
  ), por_persona as (
    select r.*,d.dias,
      (select jsonb_build_object('llamadas',sum((x->>'llamadas')::integer),
        'utiles',sum((x->>'utiles')::integer),'contestadas',sum((x->>'contestadas')::integer),
        'tasa_contacto',round(100.0*sum((x->>'contestadas')::numeric)/nullif(sum((x->>'utiles')::numeric),0),1))
        from jsonb_array_elements(d.dias) x) as resumen,
      (select jsonb_build_object('utiles',sum((p->>'utiles')::integer),
        'contestadas',sum((p->>'contestadas')::integer),
        'tasa_contacto',round(100.0*sum((p->>'contestadas')::numeric)/nullif(sum((p->>'utiles')::numeric),0),1))
        from fotos f cross join lateral jsonb_array_elements(f.foto->'personas') p
        where r.supervisor_id is not null and p->>'clave_equipo'=r.supervisor_id::text) as equipo,
      (select jsonb_build_object('dias_validos',count(*),
        'minimo',min((x->>'tasa_contacto')::numeric),
        'p25',round((percentile_cont(0.25) within group(order by (x->>'tasa_contacto')::numeric))::numeric,1),
        'mediana',round((percentile_cont(0.5) within group(order by (x->>'tasa_contacto')::numeric))::numeric,1),
        'p75',round((percentile_cont(0.75) within group(order by (x->>'tasa_contacto')::numeric))::numeric,1),
        'maximo',max((x->>'tasa_contacto')::numeric)) from jsonb_array_elements(d.dias) x
        where (x->>'utiles')::integer>=(x->>'minimo_llamadas_utiles')::integer) as distribucion_contacto,
      (select jsonb_build_object(
        'evaluables',count(*) filter(where c->>'estado' in ('cumplido','recuperado','incumplido')),
        'cumplidos_a_tiempo',count(*) filter(where c->>'estado'='cumplido'),
        'recuperados',count(*) filter(where c->>'estado'='recuperado'),
        'incumplidos',count(*) filter(where c->>'estado'='incumplido'),
        'pendientes',count(*) filter(where c->>'estado'='pendiente'),
        'sin_cartera',count(*) filter(where c->>'estado'='sin_cartera'))
        from jsonb_array_elements(d.dias) x cross join lateral
          jsonb_array_elements(jsonb_build_array(x#>'{cortes,primer_corte}',x#>'{cortes,segundo_corte}')) c) as cumplimiento
    from private.gestion_diaria_pulso_roster() r
    cross join lateral (select coalesce(jsonb_agg(x.datos order by x.datos->>'dia'),'[]'::jsonb) as dias
      from diarios x where x.analista_id=r.analista_id) d
  ) select coalesce(jsonb_agg(to_jsonb(p) order by p.nombre_completo,p.analista_id),'[]'::jsonb)
    into v_personas from por_persona p;
  select jsonb_agg(jsonb_build_object('dia',f->'dia','minimo_llamadas_utiles',f->'minimo_llamadas_utiles',
      'estado_cortes',f#>'{cortes,estado}','politica_version',f#>'{cortes,politica_version}') order by f->>'dia')
    into v_dias from jsonb_array_elements(v_fotos) f;
  return jsonb_build_object('version',1,'generado_en',v_ahora,'desde',v_desde,'hasta',v_hasta,
    'dias_solicitados',p_dias,'dias_incluidos',v_hasta-v_desde+1,
    'organigrama_referencia','consulta_actual','cartera_referencia','consulta_actual',
    'umbral_tasa_baja',null,'operacion',v_operacion,'jornadas',v_dias,'personas',v_personas);
end $$;

-- Endurecimiento en la misma transacción: no hay puertas anónimas nuevas.
revoke all on function private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[]) from public,anon;
revoke all on function private.gestion_diaria_gestiones_eventos(timestamptz,timestamptz) from public,anon;
revoke all on function private.gestion_diaria_pulso_autores(timestamptz,timestamptz) from public,anon;
revoke all on function private.gestion_diaria_fechas_activas(date,date) from public,anon;
revoke all on function private.gestion_diaria_pulso_autorizar() from public,anon;
revoke all on function private.gestion_diaria_pulso_roster() from public,anon;
revoke all on function private.gestion_diaria_pulso_metricas(jsonb,integer) from public,anon;
revoke all on function private.gestion_diaria_pulso_dia(date) from public,anon;
revoke all on function private.gestion_diaria_habitos_jornada(date,uuid[],timestamptz) from public,anon;
revoke all on function crm.gestion_diaria_pulso_fn(date) from public,anon;
revoke all on function crm.gestion_diaria_habitos_fn(date,integer) from public,anon;
grant execute on function private.gestion_diaria_pulso_autorizar() to authenticated;
grant execute on function private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[]) to authenticated;
grant execute on function private.gestion_diaria_gestiones_eventos(timestamptz,timestamptz) to authenticated;
grant execute on function private.gestion_diaria_pulso_autores(timestamptz,timestamptz) to authenticated;
grant execute on function private.gestion_diaria_fechas_activas(date,date) to authenticated;
grant execute on function private.gestion_diaria_pulso_roster() to authenticated;
grant execute on function private.gestion_diaria_pulso_metricas(jsonb,integer) to authenticated;
grant execute on function private.gestion_diaria_pulso_dia(date) to authenticated;
grant execute on function private.gestion_diaria_habitos_jornada(date,uuid[],timestamptz) to authenticated;
grant execute on function crm.gestion_diaria_pulso_fn(date) to authenticated;
grant execute on function crm.gestion_diaria_habitos_fn(date,integer) to authenticated;

comment on function crm.gestion_diaria_pulso_fn(date) is
  'F5. Día Lima y comparaciones completas, organigrama actual, pendientes actuales. Solo gerencia/global.';
comment on function crm.gestion_diaria_habitos_fn(date,integer) is
  'F5. Hábitos de 7/14/30 días; cartera y organigrama actuales; sin umbral de tasa baja ni decisiones automáticas.';

-- SELLOS F5 INICIO
-- Huellas medidas después de paridad con H3 y oráculo independiente.
-- Se incorpora la nueva dependencia al sello F3: cambiar el lector de eventos
-- sin cambiar el agregador también debe poner el gate en rojo.
CREATE OR REPLACE FUNCTION private.assert_gestion_diaria_analista()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_firma text;
  v_md5 text;
  v_id oid;
begin
  -- 1. Puerta y núcleos: INVOKER, estables, search_path vacío, owner postgres,
  --    EXECUTE exactamente para authenticated (la cadena corre como el actor).
  foreach v_firma in array array[
    'crm.gestion_diaria_analista_fn(date,uuid)',
    'private.gestion_diaria_analista_core(uuid,date,timestamptz,timestamptz,timestamptz,timestamptz,uuid)',
    'private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])',
    'private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])',
    'private.gestion_diaria_umbrales()'
  ] loop
    v_id := to_regprocedure(v_firma);
    if v_id is null or not exists (
      select 1 from pg_proc p
      where p.oid = v_id and not p.prosecdef
        and p.proowner = 'postgres'::regrole::oid
        and p.provolatile = 's'
        and p.proconfig @> array['search_path=""']
    ) then
      raise exception 'Contrato del dia del analista alterado (debe ser INVOKER, stable, search_path vacio): %', v_firma;
    end if;
    if not has_function_privilege('authenticated', v_id, 'EXECUTE')
       or exists (
         select 1 from pg_proc p
         cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         where p.oid = v_id
           and a.grantee not in ('postgres'::regrole::oid, 'authenticated'::regrole::oid)
       ) then
      raise exception 'ACL del dia del analista alterada: %', v_firma;
    end if;
    -- Ningún contador crudo en los cuerpos propios (trinquete del censo analítico).
    if exists (select 1 from pg_proc p where p.oid = v_id
               and (lower(p.prosrc) ~ '\mcount\s*\(' or lower(p.prosrc) ~ '\msum\s*\(\s*1\s*\)')) then
      raise exception 'Una funcion del dia del analista cuenta a crudo: %', v_firma;
    end if;
  end loop;

  -- 2. Los CUERPOS propios, sellados (medidos en el banco, dos pasadas).
  for v_firma, v_md5 in select * from (values
    ('crm.gestion_diaria_analista_fn(date,uuid)',                                                          'ba3d0502ae4bf0d010677562d47634a5'),
    ('private.gestion_diaria_analista_core(uuid,date,timestamptz,timestamptz,timestamptz,timestamptz,uuid)',    '4dd5313e606b57485cd105b125f412b7'),
    ('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])',                                    '7c5d14e65cc0e55e57214589d11e9c9d'),
    ('private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])', '27d25609c74e04c58f82e36af45d7327'),
    ('private.gestion_diaria_umbrales()',                                                                   '151860fa342b98d4f2ce9ed7054e390b'),
    -- El roster ES la autorización para mirar el día de otro: si alguien lo
    -- reescribe, este gate se pone en rojo y hay que re-sellar a conciencia
    -- (md5 medido en producción el 20/09/2026).
    ('crm.equipo_visible_fn()',                                                                             '200162f4519586a6c68d8ccf0cf591f7')
  ) as m(firma, md5) loop
    if to_regprocedure(v_firma) is null
       or md5(pg_get_functiondef(to_regprocedure(v_firma))) is distinct from v_md5 then
      raise exception 'El cuerpo de % cambio: re-sellar el dia del analista de Gestion Diaria (md5 %)',
        v_firma, coalesce(md5(pg_get_functiondef(to_regprocedure(v_firma))), 'ausente');
    end if;
  end loop;

  -- 3. La cola de la que bebe la pantalla, en su forma: DEFINER, estable,
  --    search_path vacío, ejecutable por authenticated. (Su cuerpo no se sella
  --    aquí: pertenece al mundo SLA; el front valida el contrato de la página.)
  v_id := to_regprocedure('crm.cola_accion_v2_fn(integer,text,text,uuid,jsonb)');
  if v_id is null or not exists (
    select 1 from pg_proc p
    where p.oid = v_id and p.prosecdef and p.proowner = 'postgres'::regrole::oid
      and p.provolatile = 's' and p.proconfig @> array['search_path=""']
  ) or not has_function_privilege('authenticated', v_id, 'EXECUTE') then
    raise exception 'crm.cola_accion_v2_fn perdio su forma o su EXECUTE';
  end if;

  -- 4. La perilla del abandono: fila única bajo RLS, legible por el actor.
  -- La perilla, sellada como las policies de F1: huella de la expresión y el
  -- conjunto de permisivas de lectura EXACTO (una permisiva nueva la abriría a
  -- quien no debe). Huella medida en producción el 20/09/2026.
  if to_regclass('crm.politica_abandono') is null
     or not (select relrowsecurity from pg_class where oid = 'crm.politica_abandono'::regclass)
     or not has_column_privilege('authenticated', 'crm.politica_abandono', 'dias_abandono', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.politica_abandono', 'singleton', 'SELECT') then
    raise exception 'crm.politica_abandono perdio su forma (RLS o SELECT de singleton/dias_abandono)';
  end if;
  if (select md5(pg_get_expr(pol.polqual, pol.polrelid)) from pg_policy pol
       where pol.polrelid = 'crm.politica_abandono'::regclass and pol.polname = 'politica_abandono_select')
     is distinct from '97d4f815a6e61ba941d22c4c4d47298d' then
    raise exception 'politica_abandono_select cambio desde la auditoria: re-auditar quien lee la perilla del abandono';
  end if;
  if (select array_agg(pol.polname::text order by pol.polname) from pg_policy pol
       where pol.polrelid = 'crm.politica_abandono'::regclass and pol.polpermissive and pol.polcmd in ('r', '*'))
     is distinct from array['politica_abandono_select']::text[] then
    raise exception 'crm.politica_abandono tiene otras permisivas de lectura: re-auditar quien ve la perilla';
  end if;

  -- 5. La cadena invoker: tareas bajo RLS con su policy de lectura, y las
  --    columnas de leads que los núcleos leen y que llevan ACL propia.
  if not (select relrowsecurity from pg_class where oid = 'crm.tareas'::regclass)
     or not exists (select 1 from pg_policy where polrelid = 'crm.tareas'::regclass and polname = 'tareas_select' and polcmd = 'r')
     or not has_table_privilege('authenticated', 'crm.tareas', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'tenencia_desde', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'sla_global_iniciado_en', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'descartado_en', 'SELECT')
     or not has_function_privilege('authenticated', 'crm.equipo_visible_fn()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'private.puede_acceder_crm()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'private.rol_crm(uuid)', 'EXECUTE') then
    raise exception 'La cadena invoker del dia del analista perdio un permiso (tareas, leads.tenencia_desde/sla_global_iniciado_en/descartado_en, equipo_visible_fn, ayudantes)';
  end if;
  -- tareas_select sellada por huella, por conjunto de permisivas y con la
  -- restrictiva del actor activo: UNA sola fuente, la base de las tareas por
  -- cursor (20260919235100). Constantes copiadas podrían divergir; llamándola no.
  perform private.assert_tareas_pendientes_base();

  return 'OK: dia del analista — puerta y nucleos INVOKER (EXECUTE solo authenticated) con su md5, sin contadores crudos, cola v2 y politica_abandono en su forma, cadena invoker con sus permisos, tareas_select sellada por la base de las tareas por cursor';
end;
$function$;

create or replace function private.assert_gestion_diaria_pulso()
returns text language plpgsql stable security definer set search_path='' as $f5$
declare r record; v_oid oid;
begin
  for r in select * from (values
    ('crm.gestion_diaria_habitos_fn(date,integer)','df1762f1dd7f59febc47b43d853a55b4','s'),
    ('crm.gestion_diaria_pulso_fn(date)','ae43587d05ede1aa077f5924471c43ae','s'),
    ('private.gestion_diaria_fechas_activas(date,date)','9aa42ff2e0ba81c87afc8cc8c03038c8','s'),
    ('private.gestion_diaria_gestiones_eventos(timestamp with time zone,timestamp with time zone)','32d8e5c964b0b35f1d4e2754bda97724','s'),
    ('private.gestion_diaria_habitos_jornada(date,uuid[],timestamp with time zone)','8538b79265f65a36c3ccbe24625ba7de','s'),
    ('private.gestion_diaria_llamadas(timestamp with time zone,timestamp with time zone,uuid[])','7c5d14e65cc0e55e57214589d11e9c9d','s'),
    ('private.gestion_diaria_llamadas_eventos(timestamp with time zone,timestamp with time zone,uuid[])','27d25609c74e04c58f82e36af45d7327','s'),
    ('private.gestion_diaria_pulso_autores(timestamp with time zone,timestamp with time zone)','e73960545e7f637259db254c9e2a385b','s'),
    ('private.gestion_diaria_pulso_autorizar()','14091efcebf71186c3fa76f12e4f266c','s'),
    ('private.gestion_diaria_pulso_dia(date)','0221659e73a2556099974324564f2164','s'),
    ('private.gestion_diaria_pulso_metricas(jsonb,integer)','cf96bd3c57c5302eadaa4ef3a29d92aa','i'),
    ('private.gestion_diaria_pulso_roster()','f35b4f2402f1774ea3eba395c5b97f4f','s')
  ) as sellos(firma,huella,volatilidad) loop
    v_oid:=to_regprocedure(r.firma);
    if v_oid is null or not exists(select 1 from pg_proc p where p.oid=v_oid
      and not p.prosecdef and p.proowner='postgres'::regrole
      and p.provolatile::text=r.volatilidad and p.proconfig @> array['search_path=""']
      and md5(pg_get_functiondef(p.oid))=r.huella) then
      raise exception 'Cuerpo o forma de F5 alterados: %',r.firma;
    end if;
    if not has_function_privilege('authenticated',v_oid,'EXECUTE') or exists(
      select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
      where p.oid=v_oid and a.grantee not in ('postgres'::regrole::oid,'authenticated'::regrole::oid)) then
      raise exception 'Permisos de F5 alterados: %',r.firma;
    end if;
  end loop;
  perform private.assert_gestion_diaria_analista();
  perform private.assert_gestion_diaria_equipo();
  perform private.assert_gestion_diaria_cortes();
  perform private.assert_analitica_leads_citas();
  return 'OK: F5 invoker, fuentes compartidas selladas, ACL exactas, puertas F3/F4 y censo analítico conservados';
end $f5$;
revoke all on function private.assert_gestion_diaria_pulso() from public,anon,authenticated,service_role;
-- SELLOS F5 FIN

notify pgrst,'reload schema';
commit;

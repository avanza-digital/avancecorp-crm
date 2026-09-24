-- H3: lectura paginada de tareas por analista y ámbito compartido con equipo.
-- No altera tablas, políticas, métricas ni comandos de negocio. Publicación H6.
-- La extracción conserva el cuerpo del agregado salvo su resolución del roster.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
do $preflight$
begin
  perform private.assert_gestion_diaria();
  perform private.assert_tareas_pendientes_base();
  if md5(pg_get_functiondef('private.gestion_diaria_equipo_core(date,uuid)'::regprocedure))
    is distinct from '17b39a376af0f940f029937a6fa98186' then
    raise exception 'H3: cambió el núcleo de equipo; revisar la extracción antes de continuar';
  end if;
end $preflight$;

create function private.gestion_diaria_equipo_ambito(p_supervisor_id uuid) returns jsonb
language plpgsql stable security invoker set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_supervisor uuid := p_supervisor_id;
  v_roster jsonb;
begin
  if v_uid is null or not private.puede_acceder_crm()
    or not (coalesce(v_rol in ('supervisor', 'gerencia'), false) or private.es_lector_global()) then
    raise exception 'No autorizado para consultar el equipo' using errcode = '42501';
  end if;
  if v_rol = 'supervisor' then
    if v_supervisor is not null and v_supervisor <> v_uid then
      raise exception 'Solo puedes consultar tu propio equipo' using errcode = '42501';
    end if;
    v_supervisor := v_uid;
  end if;
  if v_supervisor is not null and not exists (
    select 1 from crm.equipo_visible_fn() e
    where e.perfil_id = v_supervisor and e.activo and e.rol_crm = 'supervisor'
  ) then
    raise exception 'El supervisor no pertenece a tu ambito activo' using errcode = '42501';
  end if;

  -- Recorrer las aristas bajo RLS conserva los puentes inactivos del ámbito
  -- canónico. equipo_visible_fn filtra identidades efectivas: usarlo también
  -- para recorrer perdería descendientes activos bajo un supervisor revocado.
  -- Sólo las identidades activas autorizadas llegan al roster final.
  -- Se parte del roster, NO de actividades ni de cartera. UNION corta ciclos.
  with recursive visibles as materialized (select * from crm.equipo_visible_fn()),
  arbol as (
    select e.perfil_id from crm.equipo e where e.perfil_id = v_supervisor
    union
    select e.perfil_id from crm.equipo e join arbol a on e.supervisor_id = a.perfil_id
  )
  select coalesce(jsonb_agg(jsonb_build_object('analista_id', e.perfil_id,
    'nombre_completo', e.nombre_completo) order by e.nombre_completo, e.perfil_id), '[]'::jsonb)
  into v_roster
  from visibles e where e.activo and e.rol_crm = 'vendedor'
    and (v_supervisor is null or e.perfil_id in (select a.perfil_id from arbol a));
  return jsonb_build_object('supervisor_id', v_supervisor, 'roster', v_roster);
end;
$function$;
revoke all on function private.gestion_diaria_equipo_ambito(uuid) from public, anon, authenticated, service_role;
grant execute on function private.gestion_diaria_equipo_ambito(uuid) to authenticated;

CREATE OR REPLACE FUNCTION private.gestion_diaria_equipo_core(p_dia date, p_supervisor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_ahora timestamptz := statement_timestamp();
  v_hoy date := (v_ahora at time zone 'America/Lima')::date;
  v_dia date := coalesce(p_dia, v_hoy);
  v_supervisor uuid := p_supervisor_id;
  v_ini timestamptz;
  v_fin timestamptz;
  v_inicio_jornada timestamptz;
  v_en_jornada boolean;
  v_roster jsonb;
  v_ids uuid[];
  v_umbrales jsonb;
  v_sla jsonb;
  v_equipo jsonb;
  v_resumen jsonb;
begin
  if v_uid is null or not private.puede_acceder_crm()
    or not (coalesce(v_rol in ('supervisor', 'gerencia'), false) or private.es_lector_global()) then
    raise exception 'No autorizado para consultar el equipo' using errcode = '42501';
  end if;
  if not isfinite(v_dia) or v_dia > v_hoy or v_hoy - v_dia > 365 then
    raise exception 'El dia debe estar entre hoy y hace un ano' using errcode = '22023';
  end if;
  -- Misma autoridad y árbol canónico que el listado individual de pendientes.
  v_roster := private.gestion_diaria_equipo_ambito(p_supervisor_id);
  v_supervisor := (v_roster->>'supervisor_id')::uuid;
  v_roster := v_roster->'roster';
  select coalesce(array_agg((r->>'analista_id')::uuid), '{}'::uuid[])
    into v_ids from jsonb_array_elements(v_roster) r;

  v_ini := v_dia::timestamp at time zone 'America/Lima';
  v_fin := (v_dia + 1)::timestamp at time zone 'America/Lima';
  v_inicio_jornada := (v_dia + time '09:00') at time zone 'America/Lima';
  v_en_jornada := v_dia = v_hoy and extract(isodow from v_dia) <= 6
    and v_ahora >= v_inicio_jornada
    and v_ahora < ((v_dia + case when extract(isodow from v_dia) = 6
      then time '13:00' else time '18:00' end) at time zone 'America/Lima');
  v_sla := private.gestion_diaria_equipo_pendientes();
  v_umbrales := private.gestion_diaria_umbrales(v_ini);

  with roster as (
    select * from jsonb_to_recordset(v_roster) as r(analista_id uuid, nombre_completo text)
  ), llamadas as materialized (
    select * from private.gestion_diaria_llamadas(v_ini, v_fin, v_ids)
  ), gestiones as (
    select a.creado_por, cardinality(array_agg(a.id)) as total, max(a.creado_en) as ultima
    from crm.actividades a where a.creado_por = any(v_ids)
      and a.creado_en >= v_ini and a.creado_en < v_fin
      and a.tipo in ('llamada_realizada', 'llamada_no_contestada', 'whatsapp_enviado',
        'reunion_realizada', 'nota', 'conversion')
    group by a.creado_por
  ), tareas as (
    select t.vendedor_id, cardinality(array_agg(t.id)) as pendientes,
      coalesce(cardinality(array_agg(t.id) filter (where t.vence_en < v_ahora)), 0) as vencidas,
      coalesce(cardinality(array_agg(t.id) filter (where t.tipo = 'reunion'
        and t.vence_en >= v_ini and t.vence_en < v_fin)), 0) as citas_hoy
    from crm.tareas t where t.vendedor_id = any(v_ids) and t.activo and t.estado = 'pendiente'
    group by t.vendedor_id
  ), sla as (
    select * from jsonb_to_recordset(v_sla->'filas')
      as s(analista_id uuid, primer_intento_vencido integer, datos_incompletos integer)
  ), base as (
    select r.*, coalesce(g.total, 0) as gestiones_hoy, g.ultima as ultima_gestion_en,
      jsonb_build_object('llamadas', ll.llamadas, 'contestadas', ll.contestadas,
        'utiles', ll.utiles, 'leads_tocados', ll.leads_tocados,
        'citas_agendadas', ll.citas_agendadas, 'primera_llamada_en', ll.primera_llamada_en,
        'ultima_llamada_en', ll.ultima_llamada_en, 'por_resultado', ll.por_resultado,
        'por_hora', ll.por_hora,
        'tasa_contacto_pct', case when ll.utiles > 0 then round(100.0 * ll.contestadas / ll.utiles) end,
        'nivel', case when ll.utiles < (v_umbrales->>'minimo_llamadas_utiles')::integer then null
          when 100.0 * ll.contestadas / nullif(ll.utiles, 0) >= (v_umbrales->>'bien_min_pct')::numeric then 'bien'
          when 100.0 * ll.contestadas / nullif(ll.utiles, 0) >= (v_umbrales->>'atencion_min_pct')::numeric then 'atencion'
          else 'bajo' end) as marcador,
      case when ll.leads_tocados > 0 then round(ll.llamadas::numeric / ll.leads_tocados, 1) end as llamadas_por_lead,
      case when v_dia = v_hoy and ll.ultima_llamada_en is not null
        then greatest(0, floor(extract(epoch from (v_ahora - ll.ultima_llamada_en)) / 60))::integer end as minutos_sin_llamar,
      coalesce(t.pendientes, 0) as tareas_pendientes,
      coalesce(t.vencidas, 0) as tareas_vencidas, coalesce(t.citas_hoy, 0) as citas_hoy,
      case when v_sla->>'modo' = 'activo' then coalesce(s.primer_intento_vencido, 0) end as primer_intento_vencido,
      case when v_sla->>'modo' = 'activo' then coalesce(s.datos_incompletos, 0) end as datos_incompletos,
      v_en_jornada and v_ahora - greatest(coalesce(ll.ultima_llamada_en, v_inicio_jornada), v_inicio_jornada)
        > interval '2 hours' as sin_llamar_2h
    from roster r join llamadas ll on ll.vendedor_id = r.analista_id
    left join gestiones g on g.creado_por = r.analista_id
    left join tareas t on t.vendedor_id = r.analista_id
    left join sla s on s.analista_id = r.analista_id
  ), motivos as (
    select b.*, array_remove(array[
      case when b.tareas_vencidas > 0 then 'tarea_vencida' end,
      case when b.primer_intento_vencido > 0 then 'primer_intento_vencido' end,
      case when b.datos_incompletos > 0 then 'datos_incompletos' end,
      case when b.sin_llamar_2h then 'sin_llamar_2h' end
    ], null) as motivos_atencion from base b
  ), filas as (
    select m.*, cardinality(m.motivos_atencion) > 0 as requiere_atencion from motivos m
  )
  select coalesce(jsonb_agg(to_jsonb(f) order by f.requiere_atencion desc,
    f.tareas_vencidas desc, f.nombre_completo, f.analista_id), '[]'::jsonb),
    jsonb_build_object('analistas', coalesce(cardinality(array_agg(f.analista_id)), 0),
      'con_actividad', coalesce(cardinality(array_agg(f.analista_id) filter (where f.gestiones_hoy > 0)), 0),
      'sin_actividad', coalesce(cardinality(array_agg(f.analista_id) filter (where f.gestiones_hoy = 0)), 0),
      'con_pendientes', coalesce(cardinality(array_agg(f.analista_id) filter
        (where f.tareas_pendientes > 0 or f.primer_intento_vencido > 0)), 0),
      'requieren_atencion', coalesce(cardinality(array_agg(f.analista_id) filter (where f.requiere_atencion)), 0))
  into v_equipo, v_resumen from filas f;
  return jsonb_build_object('version', 1, 'generado_en', v_ahora, 'dia', v_dia,
    'zona', 'America/Lima', 'supervisor_id', v_supervisor, 'umbrales', v_umbrales,
    'pendientes_al', v_ahora, 'modo_sla', v_sla->'modo', 'equipo', v_equipo, 'resumen', v_resumen, 'cortes', private.gestion_diaria_cortes(v_dia, v_ids, v_ahora));
end;
$function$
;


create function private.gestion_diaria_pendientes_core(
  p_analista_id uuid, p_solo_vencidas boolean, p_limite integer,
  p_despues_de timestamptz, p_despues_id uuid
) returns jsonb
language plpgsql stable security invoker set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_ambito jsonb;
  v_ahora timestamptz := statement_timestamp();
  v_respuesta jsonb;
  v_invalida boolean;
begin
  -- También protege la invocación directa del núcleo por authenticated.
  if v_uid is null or private.rol_crm(v_uid) is distinct from 'supervisor' then
    raise exception 'No autorizado para consultar pendientes' using errcode = '42501';
  end if;
  v_ambito := private.gestion_diaria_equipo_ambito(v_uid);
  if p_analista_id is null or p_solo_vencidas is null or p_limite is null
    or p_limite < 1 or p_limite > 100
    or (p_despues_de is null) <> (p_despues_id is null)
    or (p_despues_de is not null and not isfinite(p_despues_de)) then
    raise exception 'Parámetros de pendientes inválidos' using errcode = '22023';
  end if;
  if not exists (select 1 from jsonb_array_elements(v_ambito->'roster') r
    where (r->>'analista_id')::uuid = p_analista_id) then
    -- Ajeno, inactivo e inexistente tienen idéntica respuesta.
    raise exception 'No autorizado para consultar pendientes' using errcode = '42501';
  end if;

  -- Resumen y página comparten sentencia y RLS. La referencia no determina
  -- quién es responsable de la tarea ni elimina tareas sin lead visible.
  with base as materialized (
    select t.id, t.vendedor_id, t.tipo, t.titulo, t.vence_en,
      t.lead_id, t.perfil_id, t.inversionista_id
    from crm.tareas t
    where t.vendedor_id = p_analista_id and t.activo and t.estado = 'pendiente'
  ), resumen as (
    select coalesce(cardinality(array_agg(b.id)), 0) as tareas_pendientes,
      coalesce(cardinality(array_agg(b.id) filter (where b.vence_en < v_ahora)), 0) as tareas_vencidas,
      coalesce(bool_or(num_nonnulls(b.lead_id, b.perfil_id, b.inversionista_id) <> 1
        or not isfinite(b.vence_en)), false) as invalida
    from base b
  ), sonda as materialized (
    select b.* from base b
    where (not p_solo_vencidas or b.vence_en < v_ahora)
      and (p_despues_de is null or (b.vence_en, b.id) > (p_despues_de, p_despues_id))
    order by b.vence_en, b.id limit p_limite + 1
  ), pagina as materialized (
    select s.* from sonda s order by s.vence_en, s.id limit p_limite
  ), estado as (
    select coalesce(cardinality(array_agg(s.id)), 0) > p_limite as hay_mas from sonda s
  )
  select jsonb_build_object(
    'version', 1, 'zona', 'America/Lima', 'supervisor_id', v_uid,
    'analista_id', p_analista_id, 'generado_en', v_ahora, 'pendientes_al', v_ahora,
    'solo_vencidas', p_solo_vencidas, 'limite', p_limite,
    'resumen', jsonb_build_object('tareas_pendientes', r.tareas_pendientes,
      'tareas_vencidas', r.tareas_vencidas),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
      'id', p.id, 'vendedor_id', p.vendedor_id, 'tipo', p.tipo, 'titulo', p.titulo,
      'vence_en', p.vence_en, 'estado', 'pendiente',
      'referencia_tipo', case when p.lead_id is not null then 'lead'
        when p.perfil_id is not null then 'perfil' else 'postventa' end,
      'lead_id', case when nullif(btrim(l.nombre_completo), '') is not null then l.id end,
      'lead_nombre', nullif(btrim(l.nombre_completo), '')
    ) order by p.vence_en, p.id) from pagina p left join crm.leads l on l.id = p.lead_id), '[]'::jsonb),
    'hay_mas', e.hay_mas,
    'siguiente_cursor', case when e.hay_mas then (select jsonb_build_object(
      'despues_de', p.vence_en, 'despues_id', p.id)
      from pagina p order by p.vence_en desc, p.id desc limit 1) else null end
  ), r.invalida into v_respuesta, v_invalida from resumen r cross join estado e;
  if v_invalida then
    raise exception 'No se pudo confirmar la integridad de las tareas' using errcode = '22000';
  end if;
  return v_respuesta;
end;
$function$;
revoke all on function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid) to authenticated;

create function crm.gestion_diaria_pendientes_fn(
  p_analista_id uuid, p_solo_vencidas boolean default false, p_limite integer default 25,
  p_despues_de timestamptz default null, p_despues_id uuid default null
) returns jsonb
language sql stable security invoker set search_path = ''
as $function$
  select private.gestion_diaria_pendientes_core(p_analista_id, p_solo_vencidas,
    p_limite, p_despues_de, p_despues_id);
$function$;
revoke all on function crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid) to authenticated;
comment on function crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid) is
  'H3: tareas actuales del analista autorizado del supervisor; cursor vence_en/id, límite 1–100, resumen previo al filtro y referencia mínima bajo RLS. Sin escrituras ni totales de leads.';

-- Sólo cambia la huella del cuerpo extraído; conserva todas las otras defensas.
do $sellar_equipo$
declare v_def text;
begin
  v_def := pg_get_functiondef('private.assert_gestion_diaria_equipo()'::regprocedure);
  if md5(v_def) is distinct from '4121c660f66ca3b734e36731e643c3ae' then
    raise exception 'H3: cambió el gate de equipo; revisar su extracción';
  end if;
  execute replace(v_def, '17b39a376af0f940f029937a6fa98186', '2628ad9f6805c6944c2773b2f0f2125f');
end $sellar_equipo$;

create function private.assert_gestion_diaria_pendientes() returns text
language plpgsql stable security definer set search_path = ''
as $function$
declare v_firma text; v_hash text;
begin
  for v_firma, v_hash in select * from (values
    ('private.gestion_diaria_equipo_ambito(uuid)', 'af06caf4d0ea5d392d9c36f069b3501b'),
    ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)', 'f49dc3a7d106bef0f089980c9eb30db1'),
    ('crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid)', 'd69dd41dbd7106283584e7d6b1cc9e1a')
  ) as firmas(firma, huella) loop
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure(v_firma)
      and not p.prosecdef and p.provolatile = 's' and p.proowner = 'postgres'::regrole
      and p.proconfig = array['search_path=""']
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and not has_function_privilege('service_role', p.oid, 'EXECUTE')
      and md5(pg_get_functiondef(p.oid)) = v_hash) then
      raise exception 'H3: contrato, cuerpo o permisos alterados en %', v_firma;
    end if;
  end loop;
  perform private.assert_tareas_pendientes_base();
  perform private.assert_gestion_diaria_equipo();
  return 'OK: pendientes H3 paginados, ámbito canónico compartido, invoker/RLS y referencias mínimas';
end;
$function$;
revoke all on function private.assert_gestion_diaria_pendientes() from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.assert_gestion_diaria()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return 'OK: Gestion Diaria [' || private.assert_gestion_diaria_registro()
    || '] [' || private.assert_gestion_diaria_resultado()
    || '] [' || private.assert_gestion_diaria_analista()
    || '] [' || private.assert_gestion_diaria_equipo()
    || '] [' || private.assert_gestion_diaria_cortes()
    || '] [' || private.assert_gestion_diaria_avisos()
    || '] [' || private.assert_gestion_diaria_configuracion()
    || '] [' || private.assert_gestion_diaria_alertas_equipo() || '] [' || private.assert_gestion_diaria_lectura()
    || '] [' || private.assert_gestion_diaria_pendientes() || ']';
end $function$
;

do $postflight$
begin
  perform private.assert_gestion_diaria();
  perform private.assert_sla_nucleo();
  perform private.assert_sla_operacion();
  perform private.assert_sla_comandos();
  perform private.assert_sla_avisos();
end $postflight$;
notify pgrst, 'reload schema';
commit;

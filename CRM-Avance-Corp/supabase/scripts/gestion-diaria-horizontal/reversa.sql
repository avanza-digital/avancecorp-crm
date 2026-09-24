-- Reversa H3: sólo funciones; restaura los cuerpos exactos anteriores.
begin;
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
    'nombre_completo', e.nombre_completo) order by e.nombre_completo, e.perfil_id), '[]'::jsonb),
    coalesce(array_agg(e.perfil_id), '{}'::uuid[])
  into v_roster, v_ids
  from visibles e where e.activo and e.rol_crm = 'vendedor'
    and (v_supervisor is null or e.perfil_id in (select a.perfil_id from arbol a));

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
CREATE OR REPLACE FUNCTION private.assert_gestion_diaria_equipo()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_firma text; v_definer boolean;
begin
  foreach v_firma in array array['crm.gestion_diaria_equipo_fn(date,uuid)',
    'private.gestion_diaria_equipo_core(date,uuid)', 'private.gestion_diaria_equipo_pendientes()'] loop
    v_definer := v_firma = 'private.gestion_diaria_equipo_pendientes()';
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure(v_firma)
      and p.prosecdef = v_definer and p.provolatile = 's' and p.proowner = 'postgres'::regrole
      and p.proconfig = array['search_path=""']
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and not has_function_privilege('service_role', p.oid, 'EXECUTE')) then
      raise exception 'F4: contrato de permisos alterado en %', v_firma;
    end if;
  end loop;
  if md5(pg_get_functiondef('crm.gestion_diaria_equipo_fn(date,uuid)'::regprocedure)) <> '6fee13c7191e5fc17647f9b684a3630c'
    or md5(pg_get_functiondef('private.gestion_diaria_equipo_core(date,uuid)'::regprocedure)) <> '17b39a376af0f940f029937a6fa98186'
    or md5(pg_get_functiondef('private.gestion_diaria_equipo_pendientes()'::regprocedure)) <> '6de28503dd0a32bd98de95d1f5de3532' then
    raise exception 'F4: cambió el cuerpo de la vista del equipo';
  end if;
  perform private.assert_gestion_diaria_analista();
  perform private.assert_sla_avisos();
  return 'OK: equipo completo, agregado canónico y acceso por identidad';
end;
$function$
;
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
    || '] [' || private.assert_gestion_diaria_alertas_equipo() || '] [' || private.assert_gestion_diaria_lectura() || ']';
end $function$
;
drop function if exists private.assert_gestion_diaria_pendientes();
drop function if exists crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid);
drop function if exists private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid);
drop function if exists private.gestion_diaria_equipo_ambito(uuid);
select private.assert_gestion_diaria();
notify pgrst, 'reload schema';
commit;

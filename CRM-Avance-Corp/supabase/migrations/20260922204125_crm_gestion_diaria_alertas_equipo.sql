-- F4.4: contexto de llamadas y grupos canónicos de pendientes del supervisor.
-- Sin reglas de tasa baja, sin reloj configurable por API y sin alertas calculadas en cliente.
begin;
do $preflight$ begin
  perform private.assert_gestion_diaria();
  perform private.assert_sla_nucleo(); perform private.assert_sla_operacion();
  perform private.assert_sla_comandos(); perform private.assert_sla_avisos();
end $preflight$;

-- Única elevación: el núcleo SLA ya recorta el ámbito con auth.uid(). No se
-- devuelve la cartera ni teléfonos, solo los ids que identifican cada problema.
create function private.gestion_diaria_alertas_sla() returns jsonb
language plpgsql stable security definer set search_path = '' as $function$
declare v_datos jsonb; v_grupos jsonb;
begin
  if auth.uid() is null or not private.puede_acceder_crm()
    or private.rol_crm(auth.uid()) is distinct from 'supervisor' then
    raise exception 'Solo el supervisor consulta sus pendientes' using errcode='42501';
  end if;
  v_datos := private.sla_operacion_autorizada(null, true);
  with avisos as (
    select f.value #>> '{lead,id}' as lead_id, a.value->>'bucket' as tipo,
      a.value->>'severidad' as severidad, (a.value->>'prioridad')::integer as prioridad
    from jsonb_array_elements(v_datos->'filas') f
    cross join lateral jsonb_array_elements(f.value #> '{estado,avisos}') a
    where v_datos->>'modo'='activo' and (f.value #>> '{senales,pendientes}')::boolean
  ), grupos as (
    select tipo, jsonb_agg(distinct lead_id order by lead_id) miembros,
      case when bool_or(severidad='critica') then 'critica' else 'atencion' end severidad,
      min(prioridad) prioridad
    from avisos group by tipo
  ) select coalesce(jsonb_agg(jsonb_build_object(
      'id','grupo:'||tipo||':'||auth.uid(), 'tipo',tipo, 'severidad',severidad,
      'miembros',miembros, 'total',jsonb_array_length(miembros)) order by prioridad,tipo),'[]')
    into v_grupos from grupos;
  return jsonb_build_object('modo_sla',v_datos->'modo','alertas',v_grupos);
end $function$;
revoke all on function private.gestion_diaria_alertas_sla() from public,anon,authenticated,service_role;
grant execute on function private.gestion_diaria_alertas_sla() to crm_gestion_diaria_lector;

-- INVOKER: recibe el rol lector SIN BYPASSRLS de gestion_diaria_avisos. No
-- llama al núcleo de llamadas desde postgres/DEFINER. Los ids se revalidan.
create function private.gestion_diaria_contexto(p_ids uuid[],p_ahora timestamptz,p_cortes jsonb) returns jsonb
language plpgsql volatile security invoker set search_path = '' as $function$
declare
  v_dia date := (p_ahora at time zone 'America/Lima')::date;
  v_inicio timestamptz := (v_dia + time '09:00') at time zone 'America/Lima';
  v_en_jornada boolean;
  v_llamadas jsonb;
  v_parados jsonb;
  v_diarias jsonb;
begin
  if auth.uid() is null or not private.puede_acceder_crm()
    or private.rol_crm(auth.uid()) is distinct from 'supervisor'
    or exists(select 1 from unnest(p_ids) id where id not in (select private.vendedor_ids_visibles(auth.uid()))) then
    raise exception 'Ámbito de llamadas no autorizado' using errcode='42501';
  end if;
  v_en_jornada := extract(isodow from v_dia)<=6 and p_ahora>=v_inicio
    and p_ahora < ((v_dia+case when extract(isodow from v_dia)=6 then time '13:00' else time '18:00' end) at time zone 'America/Lima');
  select coalesce(jsonb_agg(jsonb_build_object('analista_id',ll.vendedor_id,
    'nombre',e.nombre_completo,'primera_llamada_en',ll.primera_llamada_en,
    'llamadas',ll.llamadas,'sin_llamar_2h',v_en_jornada
      and p_ahora-greatest(coalesce(ll.ultima_llamada_en,v_inicio),v_inicio)>interval '2 hours')
    order by e.nombre_completo,ll.vendedor_id),'[]') into v_llamadas
  from private.gestion_diaria_llamadas(v_dia::timestamp at time zone 'America/Lima',
    least(p_ahora,((v_dia+1)::timestamp at time zone 'America/Lima')),p_ids) ll
  join crm.equipo_visible_fn() e on e.perfil_id=ll.vendedor_id and e.activo and e.rol_crm='vendedor';
  select coalesce(jsonb_agg(f->'analista_id' order by f->>'analista_id'),'[]') into v_parados
  from jsonb_array_elements(v_llamadas) f where (f->>'sin_llamar_2h')::boolean
    and not exists(select 1 from jsonb_array_elements(p_cortes) c,
      jsonb_array_elements(c->'miembros') m where m->>'analista_id'=f->>'analista_id');
  v_diarias := private.gestion_diaria_alertas_sla();
  if jsonb_array_length(v_parados)>0 then
    v_diarias := jsonb_set(v_diarias,'{alertas}',v_diarias->'alertas'||jsonb_build_array(jsonb_build_object(
      'id','grupo:parado_2h:'||auth.uid(), 'tipo','parado_2h', 'severidad','atencion',
      'miembros',v_parados, 'total',jsonb_array_length(v_parados))));
  end if;
  return jsonb_build_object('diarias',v_diarias,'contexto',jsonb_build_object(
    'en_jornada',v_en_jornada,'equipo',v_llamadas,
    'analistas',jsonb_array_length(v_llamadas),
    'con_llamadas',(select count(*) from jsonb_array_elements(v_llamadas) f where (f->>'llamadas')::integer>0)));
end $function$;
revoke all on function private.gestion_diaria_contexto(uuid[],timestamptz,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.gestion_diaria_contexto(uuid[],timestamptz,jsonb) to crm_gestion_diaria_lector;

-- Composición del lector, conservando todas sus decisiones y sus consumidores
-- (GET, reconocer, posponer y presentar). La fuente y el sello anterior son exactos.
do $componer$
declare fuente text; nueva text; sello text;
begin
  if (select md5(prosrc) from pg_proc where oid='private.gestion_diaria_avisos(timestamptz)'::regprocedure)
    <> '7009218260658cfbf6ed096715d2a8d5' then raise exception 'F4: lector de avisos inesperado'; end if;
  fuente := pg_get_functiondef('private.gestion_diaria_avisos(timestamptz)'::regprocedure);
  nueva := replace(fuente, '''alertas'', v_alertas);',
    '''alertas'', v_alertas) || private.gestion_diaria_contexto(v_ids,p_ahora,v_alertas);');
  if nueva=fuente then raise exception 'F4: falta ancla del contexto'; end if;
  execute nueva;
  select md5(prosrc) into sello from pg_proc where oid='private.gestion_diaria_avisos(timestamptz)'::regprocedure;
  if sello <> '9479e6066fc5724eb7b535514a4acba8' then raise exception 'F4: composición de avisos inesperada'; end if;
  fuente := pg_get_functiondef('private.assert_gestion_diaria_avisos()'::regprocedure);
  execute replace(fuente,'7009218260658cfbf6ed096715d2a8d5',sello);
end $componer$;

create function private.assert_gestion_diaria_alertas_equipo() returns text
language plpgsql stable security definer set search_path = '' as $function$
declare f record;
begin
  for f in select * from (values
    ('private.gestion_diaria_alertas_sla()','bca4ff0c4ee591bb405c2e1bedb3082b',true,'s'),
    ('private.gestion_diaria_contexto(uuid[],timestamptz,jsonb)','d13024e306a1fad6e22c4b592029b8d0',false,'v')
  ) funciones(firma,huella,definer,volatilidad) loop
    if not exists(select 1 from pg_proc p where p.oid=to_regprocedure(f.firma)
      and md5(p.prosrc)=f.huella and p.proowner='postgres'::regrole
      and p.prosecdef=f.definer and p.provolatile=f.volatilidad::"char" and p.proconfig=array['search_path=""']
      and has_function_privilege('crm_gestion_diaria_lector',p.oid,'EXECUTE')
      and not has_function_privilege('authenticated',p.oid,'EXECUTE')
      and not has_function_privilege('anon',p.oid,'EXECUTE')
      and not has_function_privilege('service_role',p.oid,'EXECUTE')) then
      raise exception 'F4: contexto o adaptador de pendientes alterado en %',f.firma;
    end if;
  end loop;
  return 'OK: pendientes SLA agrupados y contexto de llamadas bajo RLS; tasa baja OFF';
end $function$;
revoke all on function private.assert_gestion_diaria_alertas_equipo() from public,anon,authenticated,service_role;

create or replace function private.assert_gestion_diaria() returns text
language plpgsql stable security definer set search_path = '' as $function$
begin
  return 'OK: Gestion Diaria [' || private.assert_gestion_diaria_registro()
    || '] [' || private.assert_gestion_diaria_resultado()
    || '] [' || private.assert_gestion_diaria_analista()
    || '] [' || private.assert_gestion_diaria_equipo()
    || '] [' || private.assert_gestion_diaria_cortes()
    || '] [' || private.assert_gestion_diaria_avisos()
    || '] [' || private.assert_gestion_diaria_configuracion()
    || '] [' || private.assert_gestion_diaria_alertas_equipo() || ']';
end $function$;
do $postflight$ begin
  perform private.assert_gestion_diaria();
  perform private.assert_sla_nucleo(); perform private.assert_sla_operacion();
  perform private.assert_sla_comandos(); perform private.assert_sla_avisos();
end $postflight$;
notify pgrst,'reload schema';
commit;

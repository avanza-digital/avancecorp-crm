-- Reversa de G4a (20260928043728): restaura el núcleo H3 y su sello. Si el front de
-- Gerencia ya muestra Pendientes, revertir PRIMERO el front (release anterior) y después esto.
-- Aplicar en un solo mensaje (supabase db query --linked --file …), como la migración.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
do $preflight$
begin
  if md5(pg_get_functiondef('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)'::regprocedure)) is distinct from 'a0bde87db9ea86694ba4ee79dc109729'
    or md5(pg_get_functiondef('private.assert_gestion_diaria_pendientes()'::regprocedure)) is distinct from '6aecb25a8a66e10cc5dcae69afb66281' then
    raise exception 'Reversa G4a: el núcleo o el gate vivos no son los de G4a; no se toca';
  end if;
end $preflight$;

create or replace function private.gestion_diaria_pendientes_core(
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

do $sellar$
declare v_def text;
begin
  if md5(pg_get_functiondef('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)'::regprocedure)) is distinct from 'f49dc3a7d106bef0f089980c9eb30db1' then
    raise exception 'Reversa G4a: el núcleo restaurado no es el de H3';
  end if;
  v_def := pg_get_functiondef('private.assert_gestion_diaria_pendientes()'::regprocedure);
  if (length(v_def) - length(replace(v_def, 'a0bde87db9ea86694ba4ee79dc109729', ''))) <> 32 then
    raise exception 'Reversa G4a: la huella de G4a no aparece una sola vez en el gate H3';
  end if;
  execute replace(v_def, 'a0bde87db9ea86694ba4ee79dc109729', 'f49dc3a7d106bef0f089980c9eb30db1');
end $sellar$;
comment on function crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid) is
  'H3: tareas actuales del analista autorizado del supervisor; cursor vence_en/id, límite 1–100, resumen previo al filtro y referencia mínima bajo RLS. Sin escrituras ni totales de leads.';
comment on function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid) is null;
do $postflight$
begin
  if md5(pg_get_functiondef('private.assert_gestion_diaria_pendientes()'::regprocedure)) is distinct from '42446b8f98e22d6906745081f99c5ba7' then
    raise exception 'Reversa G4a: el gate H3 no quedó como antes';
  end if;
  perform private.assert_gestion_diaria();
  perform private.assert_sla_nucleo();
  perform private.assert_sla_operacion();
  perform private.assert_sla_comandos();
  perform private.assert_sla_avisos();
end $postflight$;
notify pgrst, 'reload schema';
commit;

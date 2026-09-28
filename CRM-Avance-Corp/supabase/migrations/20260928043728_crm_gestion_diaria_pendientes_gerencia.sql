-- G4a (27/09/2026): Gerencia lee los pendientes de cualquier analista de la operación.
-- Plan G4 v2 aprobado por Miguel («G4a y luego G4b») y revisado por Codex.
--
-- Solo cambia la AUTORIZACIÓN del núcleo H3 (20260923234404):
--   · Supervisión: su árbol, como hasta ahora.
--   · Gerencia: el roster canónico con supervisor nulo (toda la operación visible, «fuera»
--     incluido), el mismo que ya usa gestion_diaria_equipo_core para Gerencia.
--   · Coordinación, analistas, lector global y rol nulo: 42501, como hasta ahora.
-- Misma firma y mismas claves: `supervisor_id` sigue siendo quien consulta (para Gerencia,
-- su propio id), así los bundles publicados (v.strictObject) no cambian. No toca tablas,
-- políticas ni grants; la lectura sigue siendo INVOKER bajo la RLS de crm.tareas, que ya
-- concede a Gerencia todas las tareas activas (las de postventa siguen además bajo la
-- política restrictiva de banderas `tareas_postventa_lectura`, igual para la cifra y la lista).
--
-- Reversa: supabase/scripts/g4/reversa-g4a.sql (cuerpo y sello anteriores). Si el front de
-- Gerencia ya muestra Pendientes, revertir PRIMERO el front y después la base.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
do $preflight$
declare v_firma text; v_huella text;
begin
  perform private.assert_gestion_diaria();
  -- Huellas vivas exactas (producción, 27/09): si algo cambió, no se adapta en silencio.
  for v_firma, v_huella in select * from (values
    ('private.gestion_diaria_equipo_ambito(uuid)', 'af06caf4d0ea5d392d9c36f069b3501b'),
    ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)', 'f49dc3a7d106bef0f089980c9eb30db1'),
    ('crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid)', 'd69dd41dbd7106283584e7d6b1cc9e1a'),
    ('private.assert_gestion_diaria_pendientes()', '42446b8f98e22d6906745081f99c5ba7')
  ) as h(firma, huella) loop
    if md5(pg_get_functiondef(to_regprocedure(v_firma))) is distinct from v_huella then
      raise exception 'G4a: cambió % en vivo; revisar antes de continuar', v_firma;
    end if;
  end loop;
end $preflight$;

CREATE OR REPLACE FUNCTION private.gestion_diaria_pendientes_core(
  p_analista_id uuid, p_solo_vencidas boolean, p_limite integer,
  p_despues_de timestamptz, p_despues_id uuid
) returns jsonb
language plpgsql stable security invoker set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_ambito jsonb;
  v_ahora timestamptz := statement_timestamp();
  v_respuesta jsonb;
  v_invalida boolean;
begin
  -- También protege la invocación directa del núcleo por authenticated. Supervisión y,
  -- desde G4a (27/09/2026), Gerencia; el rol nulo se rechaza explícitamente (Codex).
  if v_uid is null or not coalesce(v_rol in ('supervisor', 'gerencia'), false) then
    raise exception 'No autorizado para consultar pendientes' using errcode = '42501';
  end if;
  -- Supervisión: su árbol, como en H3. Gerencia: el roster canónico con supervisor nulo
  -- (toda la operación visible, «fuera» incluido), el mismo de gestion_diaria_equipo_core.
  v_ambito := private.gestion_diaria_equipo_ambito(case when v_rol = 'supervisor' then v_uid end);
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

-- El cuerpo creado debe ser EXACTAMENTE el revisado; después se re-sella el gate H3
-- sustituyendo solo la huella del núcleo (patrón $sellar_equipo$ de H3).
do $sellar$
declare v_def text; v_huella text;
begin
  v_huella := md5(pg_get_functiondef('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)'::regprocedure));
  if v_huella is distinct from 'a0bde87db9ea86694ba4ee79dc109729' then
    raise exception 'G4a: el núcleo creado no es el revisado (%)', v_huella;
  end if;
  -- El gate se fija por identidad en esta misma sentencia (auditor-rls): nada de copiar un
  -- cambio ajeno confirmado entre el preflight y aquí.
  v_def := pg_get_functiondef('private.assert_gestion_diaria_pendientes()'::regprocedure);
  if md5(v_def) is distinct from '42446b8f98e22d6906745081f99c5ba7' then
    raise exception 'G4a: el gate H3 cambió antes de re-sellarlo';
  end if;
  if (length(v_def) - length(replace(v_def, 'f49dc3a7d106bef0f089980c9eb30db1', ''))) <> 32 then
    raise exception 'G4a: la huella anterior del núcleo no aparece una sola vez en el gate H3';
  end if;
  execute replace(v_def, 'f49dc3a7d106bef0f089980c9eb30db1', v_huella);
  if md5(pg_get_functiondef('private.assert_gestion_diaria_pendientes()'::regprocedure)) is distinct from '6aecb25a8a66e10cc5dcae69afb66281' then
    raise exception 'G4a: el gate re-sellado no es el revisado';
  end if;
end $sellar$;

comment on function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid) is
  'Núcleo H3+G4a: tareas actuales de un analista del ámbito de quien consulta (Supervisión: su árbol; Gerencia: toda la operación visible). INVOKER bajo RLS; cursor vence_en/id; supervisor_id = quien consulta.';
comment on function crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid) is
  'H3+G4a: tareas actuales del analista autorizado (Supervisión: su árbol; Gerencia: toda la operación visible); cursor vence_en/id, límite 1–100, resumen previo al filtro y referencia mínima bajo RLS. supervisor_id devuelve a quien consulta. Sin escrituras ni totales de leads.';

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

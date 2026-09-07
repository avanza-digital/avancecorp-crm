-- ============================================================================
-- CRM · RENTABILIDAD SERVER-SIDE · R3 — LECTURAS para la bandeja de Gerencia, la ficha del cliente y la política
-- (plan del vault «Plan Rentabilidad server-side - tasa decidida por politica 2026-09-06», fase R3; R1 = 20260906170000,
--  R2 = 20260906180000, ambas en producción)
-- ============================================================================
--
-- QUÉ. R3 es el frente: el formulario de contrato con la tasa bloqueada en la base y el botón «Solicitar tasa superior»,
-- la bandeja de Gerencia (Aprobar · Rechazar · Aprobar hasta X%), la respuesta del analista al tope, la ficha del cliente con
-- el historial de tasa y la pantalla de Configuración de la política. Las ESCRITURAS ya existen desde R1 (solicitar_tasa_fn,
-- resolver_solicitud_tasa_fn, responder_tope_tasa_fn, publicar_politica_rentabilidad_fn). Esta migración añade SOLO tres
-- LECTURAS con nombres resueltos (el front no hace joins ni lee tablas crm.* a pelo; tipos en database.types.ts):
--   1. crm.solicitudes_tasa_fn(p_estados, p_limite) → jsonb[]: las solicitudes visibles para el actor con la MISMA regla que
--      la policy de R1 (quien pidió; su subárbol; Gerencia todas; Directorio), con nombres de cliente/solicitante/resolutor,
--      `estado_efectivo` (una viva con vence_en pasado se declara «vencida» aunque el sello sea perezoso), `es_mia` y
--      `puede_resolver` (Gerencia, no la propia —D3—, pendiente y vigente). Pendientes primero, prioridad_bandeja (D1) antes.
--   2. crm.historial_tasa_cliente_fn(p_cliente_id) → jsonb: por contrato del cliente, la ÚLTIMA fila del ledger (legacy u
--      observación: base, final, regla, divergente, motivo) y las solicitudes del cliente visibles para el actor. Autoridad:
--      la misma que la ficha (puede_consultar_cliente_ficha) o Gerencia/Directorio/admin; 42501 uniforme.
--   3. crm.politica_rentabilidad_fn() → jsonb: la política vigente, `expected_version` para el control optimista de publicar,
--      el historial y el hito de activación de la observación. Cualquier rol CRM o lector global.
-- No toca `public`. No transforma ninguna función viva. El candado (R4) sigue pendiente: hoy la tasa la bloquea el FRONT.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
select pg_advisory_xact_lock(hashtext('crm_rentabilidad_r3'));

do $guard$
begin
  if to_regclass('crm.politica_rentabilidad') is null or to_regclass('crm.solicitudes_tasa') is null
     or to_regclass('crm.ledger_rentabilidad') is null or to_regclass('crm.rentabilidad_hitos') is null then
    raise exception 'RENTABILIDAD R3: faltan objetos de R1/R2';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.resolver_tasa(uuid,text,uuid,timestamptz,uuid)')) is distinct from 'a3f043fb2b4c76ecbb59e5e3e98e3ba0' then
    raise exception 'RENTABILIDAD R3: el núcleo private.resolver_tasa(5 args) no es el de R2 (a3f043fb…)';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'ledger_rentabilidad' and column_name = 'secuencia') then
    raise exception 'RENTABILIDAD R3: falta ledger_rentabilidad.secuencia (R2)';
  end if;
  if to_regprocedure('crm.solicitudes_tasa_fn(text[],integer,boolean,uuid)') is not null
     or to_regprocedure('crm.historial_tasa_cliente_fn(uuid)') is not null
     or to_regprocedure('crm.politica_rentabilidad_fn()') is not null then
    raise exception 'RENTABILIDAD R3: ya está aplicada (existen sus objetos); no se reaplica';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20260906220000') then
    raise exception 'RENTABILIDAD R3: la versión 20260906220000 ya está registrada';
  end if;
  -- Los helpers que se reutilizan existen y son los de producción.
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'private.rol_crm(uuid)'::regprocedure) is distinct from 'd2878a210be96ac85973d51dfcfb27a5'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'private.puede_registrar_ventas()'::regprocedure) is distinct from '2749bb0e5616eae42a0dd410bee4f52a'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'private.puede_consultar_cliente_ficha(uuid)'::regprocedure) is distinct from 'c1afbe30f28add201886f43cd80654e9'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'private.vendedor_ids_visibles(uuid)'::regprocedure) is distinct from '33ece9bae4828f7ffdb837c6128ca9d6'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'private.es_lector_global()'::regprocedure) is distinct from 'c7c5828be6d74121a1a0ef0de374f712' then
    raise exception 'RENTABILIDAD R3: algún helper de autoridad/ámbito no es el texto vivo de producción';
  end if;
end
$guard$;

-- ---------------------------------------------------------------------------
-- 1. Solicitudes visibles para el actor (bandeja de Gerencia · «mis solicitudes» del analista · subárbol del supervisor)
-- ---------------------------------------------------------------------------
-- v3: filtros de SERVIDOR (p_solo_mias, p_cliente_id): el formulario pide solo las suyas de ese cliente, así una bandeja
-- de 200 solicitudes del equipo no puede tapar la autorización del analista (Codex R3 ronda 2 #5). Otra firma dejaría
-- dos sobrecargas y PostgREST no sabría cuál elegir (PGRST203): se suelta la anterior (solo existió en el banco).
drop function if exists crm.solicitudes_tasa_fn(text[], integer);
create or replace function crm.solicitudes_tasa_fn(p_estados text[] default null, p_limite integer default 200, p_solo_mias boolean default false, p_cliente_id uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_uid      uuid := (select auth.uid());
  v_rol      text := private.rol_crm(v_uid);
  v_lector   boolean := private.es_lector_global();
  v_gerencia boolean := coalesce(v_rol = 'gerencia', false);
  v_visibles uuid[];
  v_limite   integer := least(greatest(coalesce(p_limite, 200), 1), 500);
  v_ahora    timestamptz := statement_timestamp();
  v_payload  jsonb;
begin
  if v_uid is null or not (private.puede_registrar_ventas() or v_lector) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_estados is not null and exists (select 1 from unnest(p_estados) e where e not in
       ('pendiente', 'aprobada', 'aprobada_con_tope', 'rechazada', 'aceptada_por_analista', 'declinada_por_analista', 'consumida', 'vencida')) then
    raise exception 'Estado desconocido en el filtro' using errcode = '22023';
  end if;
  v_visibles := case when v_gerencia or v_lector then '{}'::uuid[] else array(select private.vendedor_ids_visibles(v_uid)) end;

  with efectivas as (
    select s.*,
           case when s.estado in ('pendiente', 'aprobada', 'aprobada_con_tope', 'aceptada_por_analista') and s.vence_en < v_ahora
                then 'vencida' else s.estado end as estado_efectivo
    from crm.solicitudes_tasa s
    where (v_gerencia or v_lector or s.solicitada_por = v_uid or s.solicitada_por = any(v_visibles))
      and (not coalesce(p_solo_mias, false) or s.solicitada_por = v_uid)
      and (p_cliente_id is null or s.cliente_id = p_cliente_id)
  ), acotadas as (
    -- Las TERMINALES (rechazada, declinada, consumida, vencida) solo de los últimos 7 días: esta RPC alimenta la bandeja,
    -- el formulario y el aviso (el histórico completo de un cliente vive en historial_tasa_cliente_fn). Así 200 rechazos
    -- viejos no pueden tapar una autorización viva (Codex R3 ronda 3). El front usa el mismo corte (DIAS_RECHAZO_VISIBLE).
    select s.*,
           (s.estado_efectivo in ('pendiente', 'aprobada', 'aprobada_con_tope', 'aceptada_por_analista')) as viva,
           coalesce(s.resuelta_en, s.respondida_por_analista_en, s.consumida_en, s.vence_en, s.solicitada_en) as cerrada_en
    from efectivas s
    where s.estado_efectivo in ('pendiente', 'aprobada', 'aprobada_con_tope', 'aceptada_por_analista')
       or coalesce(s.resuelta_en, s.respondida_por_analista_en, s.consumida_en, s.vence_en, s.solicitada_en) >= v_ahora - interval '7 days'
  ), visibles as (
    -- El filtro por estado es sobre el estado EFECTIVO (Codex R3 #9): una pendiente ya vencida no es «pendiente»
    -- y no ocupa el límite. Las VIVAS van siempre antes del límite; entre vivas, pendientes y prioritarias (D1) primero
    -- y la más antigua antes (FIFO de la bandeja); las terminales, la más reciente antes.
    select s.*
    from acotadas s
    where (p_estados is null or s.estado_efectivo = any(p_estados))
    order by s.viva desc, (s.estado_efectivo = 'pendiente') desc, s.prioridad_bandeja desc,
             case when s.viva then s.solicitada_en end asc, s.cerrada_en desc
    limit v_limite
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'estado', s.estado,
    'estado_efectivo', s.estado_efectivo,
    'vigente', (s.estado_efectivo in ('pendiente', 'aprobada', 'aprobada_con_tope', 'aceptada_por_analista')),
    'categoria', s.categoria, 'cliente_id', s.cliente_id,
    -- El nombre del cliente solo con ámbito sobre su ficha (Codex R3 #4): quien pidió, Gerencia, Directorio o quien
    -- puede consultar la ficha; el resto del subárbol ve la solicitud sin el nombre.
    'cliente_nombre', case when v_gerencia or v_lector or s.solicitada_por = v_uid or private.puede_consultar_cliente_ficha(s.cliente_id)
                           then coalesce(cl.nombre_completo, 'Cliente') else 'Cliente de tu equipo' end,
    'contrato_origen_id', s.contrato_origen_id, 'contrato_origen_numero', s.contrato_origen_numero,
    'producto_condicion_id', s.producto_condicion_id,
    'capital', s.capital, 'moneda', s.moneda, 'modalidad', s.modalidad, 'tipo_interes', s.tipo_interes,
    'fecha_inicio', s.fecha_inicio, 'fecha_vencimiento', s.fecha_vencimiento,
    'tasa_base', s.tasa_base, 'regla_base', s.regla_base, 'tasa_solicitada', s.tasa_solicitada,
    'tasa_maxima_autorizada', s.tasa_maxima_autorizada,
    'motivo', s.motivo, 'motivo_resolucion', s.motivo_resolucion, 'motivo_analista', s.motivo_analista,
    'prioridad_bandeja', s.prioridad_bandeja, 'contratos_previos', s.contratos_previos,
    'solicitada_por', s.solicitada_por, 'solicitante_nombre', coalesce(so.nombre_completo, 'Sin nombre'),
    'solicitada_en', s.solicitada_en, 'vence_en', s.vence_en,
    'resuelta_por', s.resuelta_por, 'resolutor_nombre', re.nombre_completo, 'resuelta_en', s.resuelta_en,
    'respondida_por_analista_en', s.respondida_por_analista_en, 'consumida_en', s.consumida_en, 'contrato_id', s.contrato_id,
    'politica_id', s.politica_id,
    'es_mia', (s.solicitada_por = v_uid),
    -- D3: Gerencia resuelve las de OTROS, pendientes y vigentes.
    'puede_resolver', (v_gerencia and s.solicitada_por <> v_uid and s.estado_efectivo = 'pendiente'),
    -- Quien pidió responde a un tope vigente.
    'puede_responder', (s.solicitada_por = v_uid and s.estado_efectivo = 'aprobada_con_tope')
  ) order by s.viva desc, (s.estado_efectivo = 'pendiente') desc, s.prioridad_bandeja desc, case when s.viva then s.solicitada_en end asc, s.cerrada_en desc), '[]'::jsonb)
  into v_payload
  from visibles s
  left join public.perfiles cl on cl.id = s.cliente_id
  left join public.perfiles so on so.id = s.solicitada_por
  left join public.perfiles re on re.id = s.resuelta_por;
  return v_payload;
end;
$function$;
revoke all on function crm.solicitudes_tasa_fn(text[], integer, boolean, uuid) from public, anon, service_role;
grant execute on function crm.solicitudes_tasa_fn(text[], integer, boolean, uuid) to authenticated;
comment on function crm.solicitudes_tasa_fn(text[], integer, boolean, uuid) is
  'Rentabilidad R3: solicitudes de tasa visibles para el actor (misma regla que la policy de R1: quien pidió, su subárbol, Gerencia todas, Directorio) con nombres resueltos (el del cliente solo con ámbito sobre su ficha), estado_efectivo (vencida si vence_en pasó), es_mia, puede_resolver (D3) y puede_responder. Filtro opcional por estado EFECTIVO antes del límite, y de servidor por p_solo_mias / p_cliente_id (el formulario pide solo las suyas de ese cliente); las terminales solo de los últimos 7 días; las vivas siempre antes del límite, pendientes y prioritarias (D1) primero. 42501 sin la autoridad del alta.';

-- ---------------------------------------------------------------------------
-- 2. Historial de tasa de un cliente (ficha): última fila del ledger por contrato + solicitudes del cliente
-- ---------------------------------------------------------------------------
create or replace function crm.historial_tasa_cliente_fn(p_cliente_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_uid      uuid := (select auth.uid());
  v_rol      text := private.rol_crm(v_uid);
  v_lector   boolean := private.es_lector_global();
  v_gerencia boolean := coalesce(v_rol = 'gerencia', false);
  v_visibles uuid[];
  v_ahora    timestamptz := statement_timestamp();
  v_contratos jsonb;
  v_solicitudes jsonb;
begin
  -- 42501 UNIFORME: cliente inexistente, sin autoridad sobre su ficha o asesor sin la autoridad del alta (Codex R3 #3):
  -- el mismo error en todos los casos para no revelar si el id existe. La autoridad es EXACTAMENTE la de la policy del
  -- ledger de R1 (lector global · gerencia · ficha) más el asesor con autoridad del alta: un admin del Portal sin
  -- membresía CRM no lee el ledger por policy y tampoco por aquí (Codex R3 ronda 2 #1).
  if v_uid is null or p_cliente_id is null
     or not exists (select 1 from public.perfiles p where p.id = p_cliente_id and p.rol = 'cliente')
     or not (v_gerencia or v_lector or private.puede_consultar_cliente_ficha(p_cliente_id)
             or (private.puede_registrar_ventas()
                 and exists (select 1 from public.perfiles p where p.id = p_cliente_id and p.rol = 'cliente' and p.asesor_perfil_id = v_uid))) then
    raise exception 'Cliente no encontrado o fuera de tu cartera' using errcode = '42501';
  end if;
  v_visibles := case when v_gerencia or v_lector then '{}'::uuid[] else array(select private.vendedor_ids_visibles(v_uid)) end;

  select coalesce(jsonb_agg(jsonb_build_object(
    'contrato_id', c.id, 'numero_contrato', c.numero_contrato, 'estado', c.estado, 'categoria', c.categoria,
    'tasa_anual', c.tasa_anual, 'capital', c.capital, 'moneda', c.moneda,
    'fecha_inicio', c.fecha_inicio, 'fecha_vencimiento', c.fecha_vencimiento, 'es_demo', c.es_demo,
    'observacion', case when l.id is null then null else jsonb_build_object(
        'regla', l.regla, 'tasa_base', l.tasa_base, 'tasa_final', l.tasa_final, 'divergente', l.divergente,
        'origen', l.origen, 'motivo', l.detalle ->> 'motivo', 'registrado_en', l.registrado_en,
        'base_conservada', coalesce((l.detalle ->> 'base_conservada')::boolean, false),
        'contrato_origen_id', l.contrato_origen_id, 'solicitud_id', l.solicitud_id) end
  ) order by c.fecha_inicio desc, c.creado_en desc), '[]'::jsonb)
  into v_contratos
  from public.contratos c
  left join lateral (
    select l.* from crm.ledger_rentabilidad l where l.contrato_id = c.id order by l.secuencia desc limit 1
  ) l on true
  where c.cliente_id = p_cliente_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'estado', s.estado,
    'estado_efectivo', case when s.estado in ('pendiente', 'aprobada', 'aprobada_con_tope', 'aceptada_por_analista') and s.vence_en < v_ahora then 'vencida' else s.estado end,
    'categoria', s.categoria, 'contrato_origen_id', s.contrato_origen_id, 'contrato_origen_numero', s.contrato_origen_numero,
    'capital', s.capital, 'moneda', s.moneda, 'fecha_inicio', s.fecha_inicio, 'fecha_vencimiento', s.fecha_vencimiento,
    'tasa_base', s.tasa_base, 'regla_base', s.regla_base, 'tasa_solicitada', s.tasa_solicitada, 'tasa_maxima_autorizada', s.tasa_maxima_autorizada,
    'motivo', s.motivo, 'motivo_resolucion', s.motivo_resolucion,
    'solicitada_por', s.solicitada_por, 'solicitante_nombre', coalesce(so.nombre_completo, 'Sin nombre'), 'solicitada_en', s.solicitada_en, 'vence_en', s.vence_en,
    'resuelta_por', s.resuelta_por, 'resolutor_nombre', re.nombre_completo, 'resuelta_en', s.resuelta_en,
    'contrato_id', s.contrato_id, 'es_mia', (s.solicitada_por = v_uid)
  ) order by s.solicitada_en desc), '[]'::jsonb)
  into v_solicitudes
  from crm.solicitudes_tasa s
  left join public.perfiles so on so.id = s.solicitada_por
  left join public.perfiles re on re.id = s.resuelta_por
  where s.cliente_id = p_cliente_id
    and (v_gerencia or v_lector or s.solicitada_por = v_uid or s.solicitada_por = any(v_visibles));

  return jsonb_build_object('version', 1, 'cliente_id', p_cliente_id, 'contratos', v_contratos, 'solicitudes', v_solicitudes, 'generado_en', v_ahora);
end;
$function$;
revoke all on function crm.historial_tasa_cliente_fn(uuid) from public, anon, service_role;
grant execute on function crm.historial_tasa_cliente_fn(uuid) to authenticated;
comment on function crm.historial_tasa_cliente_fn(uuid) is
  'Rentabilidad R3 (ficha del cliente): por contrato, la ÚLTIMA fila del ledger (legacy u observación: base, final, regla, divergente, motivo) y las solicitudes de tasa del cliente visibles para el actor. Autoridad de la ficha (puede_consultar_cliente_ficha) o Gerencia/Directorio o el asesor con autoridad del alta (la misma de la policy del ledger de R1: un admin del Portal sin membresía CRM no lee); 42501 uniforme (también si el cliente no existe).';

-- ---------------------------------------------------------------------------
-- 3. La política vigente, su historial y el hito de observación (Configuración)
-- ---------------------------------------------------------------------------
create or replace function crm.politica_rentabilidad_fn()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_vig crm.politica_rentabilidad;
  v_max integer;
  v_hist jsonb;
begin
  if v_uid is null or not (private.rol_crm(v_uid) is not null or private.es_lector_global()) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  v_vig := private.politica_rentabilidad_vigente(statement_timestamp());
  select max(p.version) into v_max from crm.politica_rentabilidad p;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'version', p.version, 'vigente_desde', p.vigente_desde, 'tasa_base_nueva', p.tasa_base_nueva,
    'regla_renovacion', p.regla_renovacion, 'regla_upgrade', p.regla_upgrade, 'tope_tecnico', p.tope_tecnico,
    'vigencia_solicitud_dias', p.vigencia_solicitud_dias, 'modo', p.modo, 'nota', p.nota,
    'publicada_por', p.publicada_por, 'publicada_por_nombre', pe.nombre_completo, 'publicada_en', p.publicada_en,
    'es_vigente', (p.id = v_vig.id)
  ) order by p.version desc), '[]'::jsonb)
  into v_hist
  from crm.politica_rentabilidad p left join public.perfiles pe on pe.id = p.publicada_por;
  return jsonb_build_object(
    'version', 1,
    'vigente', case when v_vig.id is null then null else jsonb_build_object(
      'id', v_vig.id, 'version', v_vig.version, 'vigente_desde', v_vig.vigente_desde, 'tasa_base_nueva', v_vig.tasa_base_nueva,
      'regla_renovacion', v_vig.regla_renovacion, 'regla_upgrade', v_vig.regla_upgrade, 'tope_tecnico', v_vig.tope_tecnico,
      'vigencia_solicitud_dias', v_vig.vigencia_solicitud_dias, 'modo', v_vig.modo, 'nota', v_vig.nota, 'publicada_en', v_vig.publicada_en) end,
    'expected_version', v_max,
    'historial', v_hist,
    'observacion_activa_desde', (select h.valor ->> 'en' from crm.rentabilidad_hitos h where h.clave = 'observacion_activa_desde'),
    'puede_publicar', coalesce(private.rol_crm(v_uid) = 'gerencia', false),
    'generado_en', statement_timestamp()
  );
end;
$function$;
revoke all on function crm.politica_rentabilidad_fn() from public, anon, service_role;
grant execute on function crm.politica_rentabilidad_fn() to authenticated;
comment on function crm.politica_rentabilidad_fn() is
  'Rentabilidad R3 (Configuración): la política vigente, expected_version para publicar con control optimista, el historial completo, el hito de activación de la observación y si el actor puede publicar (Gerencia). Cualquier rol CRM o lector global; 42501 si no.';

-- ---------------------------------------------------------------------------
-- POSTFLIGHT
-- ---------------------------------------------------------------------------
do $post$
declare v_f text;
begin
  for v_f in select unnest(array['crm.solicitudes_tasa_fn(text[],integer,boolean,uuid)', 'crm.historial_tasa_cliente_fn(uuid)', 'crm.politica_rentabilidad_fn()']) loop
    if not exists (select 1 from pg_proc p where p.oid = v_f::regprocedure and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig @> array['search_path=""'] and p.provolatile = 's') then
      raise exception 'POSTFLIGHT R3: % no es DEFINER estable de postgres con search_path vacío', v_f;
    end if;
    if not has_function_privilege('authenticated', v_f, 'EXECUTE') or has_function_privilege('anon', v_f, 'EXECUTE')
       or has_function_privilege('service_role', v_f, 'EXECUTE')
       or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = v_f::regprocedure and a.grantee = 0) then
      raise exception 'POSTFLIGHT R3: los grants de % no son «solo authenticated»', v_f;
    end if;
  end loop;
  raise notice 'RENTABILIDAD R3 OK: 3 lecturas (solicitudes_tasa_fn, historial_tasa_cliente_fn, politica_rentabilidad_fn), solo authenticated; nada de public tocado.';
end
$post$;
commit;

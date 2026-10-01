-- Llamadas desde el celular · corrección de F2-c: LA ELEGIBILIDAD SE EVALÚA COMO EL DUEÑO DEL CELULAR.
-- Plan aprobado (Versión 3); decisión 1 del contrato de F2 (provisional de Jhosep, 30/09/2026).
--
-- El fallo (comprobado en un banco desechable el 01/10/2026): la ingesta llega sin sesión (la Edge
-- entrará con la clave de servicio) y la regla de ámbito del CRM (private.sla_gestion_permitida →
-- private.vendedor_ids_visibles) solo responde a quien pregunta por sí mismo. Resultado: la llamada
-- del celular de un SUPERVISOR a un lead de su equipo entraba «por revisar» y nunca pedía resultado.
-- La del analista a su propio lead no fallaba, porque se reconoce por vendedor_id.
--
-- Qué hace:
--   1. private.llamada_celular_elegible_dueno(dueño, lead): evalúa la decisión 1 con la regla REAL
--      (private.llamada_celular_elegible) COMO el dueño del celular. Fija request.jwt.claim.sub al
--      dueño solo durante esa consulta y devuelve la identidad anterior en el acto, antes de que la
--      ingesta escriba nada: la bitácora del evento sigue sin atribuirse a nadie.
--   2. private.llamada_celular_ingerir: el cuerpo de 20261001160219, copiado tal cual, con UNA línea
--      cambiada: la atención inicial usa el ayudante de arriba.
--
-- Decisión de criterio de Claude (01/10/2026), para Miguel: reutilizar la regla de ámbito real
-- evaluándola como el dueño, en vez de copiarla en un ayudante propio que podría desviarse de ella.
-- El dueño sale de la asignación vigente del celular (servidor), nunca del cliente.
--
-- Reversión: ../scripts/llamadas-celular/reversa-elegibilidad.sql (devuelve el cuerpo de F2-c y retira
-- el ayudante). Verificación: npm run test:llamadas:local (oráculo tests/llamadas-celular/oraculo-elegibilidad.sql).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb)') is null
     or to_regprocedure('private.llamada_celular_elegible(uuid,uuid)') is null then
    raise exception 'LLAMADAS_ELEGIBILIDAD: falta el núcleo de 20261001160219 (F2-c)';
  end if;
  if to_regprocedure('private.llamada_celular_elegible_dueno(uuid,uuid)') is not null then
    raise exception 'LLAMADAS_ELEGIBILIDAD: los objetos ya existen; no se sobrescriben';
  end if;
end;
$precondicion$;

-- ── 1. Elegibilidad como el dueño del celular ────────────────────────────────────────────────
create function private.llamada_celular_elegible_dueno(p_dueno uuid, p_lead uuid)
returns boolean
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_previo text := pg_catalog.current_setting('request.jwt.claim.sub', true);
  v_elegible boolean;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_dueno::text, ''), true);
  v_elegible := coalesce(private.llamada_celular_elegible(p_dueno, p_lead), false);
  -- La identidad vuelve ANTES de que la ingesta escriba: la bitácora no atribuye la llamada a nadie.
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(v_previo, ''), true);
  return v_elegible;
end;
$function$;

-- ── 2. Ingesta con la elegibilidad del dueño (cuerpo de 20261001160219, una línea cambiada) ──
create or replace function private.llamada_celular_ingerir(p_asignacion_id uuid, p_evento jsonb)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_claves constant text[] := array['v', 'evento_origen_id', 'numero', 'direccion', 'estado_tecnico',
                                    'duracion_seg', 'ocurrio_en'];
  v_asig crm.celulares_asignaciones%rowtype;
  v_pol crm.llamadas_celular_politica%rowtype;
  v_previo crm.llamadas_celular_eventos%rowtype;
  v_origen text;
  v_numero text;
  v_dir text;
  v_estado text;
  v_dur integer;
  v_ocurrio timestamptz;
  v_hash text;
  v_formas text[];
  v_e164 text;
  v_cand uuid[];
  v_lead uuid;
  v_ident text;
  v_aten text;
  v_metodo text;
  v_calidad jsonb := '{}'::jsonb;
  v_id uuid;
begin
  -- Forma del evento: objeto, claves exactas, versión 1.
  if p_evento is null or pg_catalog.jsonb_typeof(p_evento) <> 'object' then
    raise exception using errcode = '22023', message = 'El evento debe ser un objeto JSON';
  end if;
  if exists (select 1 from pg_catalog.jsonb_object_keys(p_evento) k where k <> all(v_claves)) then
    raise exception using errcode = '22023', message = 'El evento trae claves no previstas';
  end if;
  if coalesce(p_evento ->> 'v', '') <> '1' then
    raise exception using errcode = '22023', message = 'Versión de evento no soportada (se espera v = 1)';
  end if;
  v_origen := p_evento ->> 'evento_origen_id';
  if v_origen is null or v_origen !~ '^[A-Za-z0-9._:+-]{4,120}$' then
    raise exception using errcode = '22023', message = 'evento_origen_id inválido (4 a 120 caracteres: letras, dígitos y . _ : + -)';
  end if;
  v_numero := nullif(pg_catalog.btrim(coalesce(p_evento ->> 'numero', '')), '');
  if pg_catalog.length(v_numero) > 40 then
    raise exception using errcode = '22023', message = 'El número no puede pasar de 40 caracteres';
  end if;
  v_dir := coalesce(p_evento ->> 'direccion', 'desconocida');
  if v_dir not in ('saliente', 'entrante', 'desconocida') then
    raise exception using errcode = '22023', message = 'direccion inválida (saliente, entrante o desconocida)';
  end if;
  v_estado := coalesce(p_evento ->> 'estado_tecnico', 'desconocido');
  if v_estado not in ('conectada', 'no_atendida', 'rechazada', 'cancelada', 'desconocido') then
    raise exception using errcode = '22023', message = 'estado_tecnico inválido';
  end if;
  begin
    v_dur := (p_evento ->> 'duracion_seg')::integer;
    v_ocurrio := (p_evento ->> 'ocurrio_en')::timestamptz;
  exception when others then
    raise exception using errcode = '22023', message = 'duracion_seg u ocurrio_en con formato inválido';
  end;
  if v_dur is not null and v_dur not between 0 and 86400 then
    raise exception using errcode = '22023', message = 'duracion_seg fuera de rango (0 a 86400)';
  end if;
  if v_ocurrio is not null and (v_ocurrio < timestamptz '2026-01-01 00:00Z' or v_ocurrio >= timestamptz '2100-01-01 00:00Z') then
    raise exception using errcode = '22023', message = 'ocurrio_en fuera de rango';
  end if;

  -- Asignación vigente con analista activo (F3: credencial revocada o analista dado de baja).
  select * into v_asig from crm.celulares_asignaciones a where a.id = p_asignacion_id for share;
  if not found or v_asig.vigente_hasta is not null
     or coalesce(private.rol_crm(v_asig.analista_id), '') not in ('vendedor', 'supervisor') then
    raise exception using errcode = '42501', message = 'Celular sin asignación vigente o analista inactivo';
  end if;

  -- Contenido canónico (la hora en UTC: el mismo instante con otra zona es el MISMO contenido).
  v_hash := private.idem_hash(pg_catalog.jsonb_build_object(
    'v', 1, 'evento_origen_id', v_origen, 'numero', v_numero, 'direccion', v_dir,
    'estado_tecnico', v_estado, 'duracion_seg', v_dur,
    'ocurrio_en', pg_catalog.to_char(v_ocurrio at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));

  select * into v_previo from crm.llamadas_celular_eventos e
  where e.asignacion_id = p_asignacion_id and e.evento_origen_id = v_origen;
  if found then
    if v_previo.hash_payload <> v_hash then
      raise exception using errcode = 'P0409',
        message = 'Esta llamada ya llegó con otro contenido; no se puede reenviar así';
    end if;
    return pg_catalog.jsonb_build_object('evento_id', v_previo.id, 'repetido', true, 'ignorado', false,
      'identificacion', v_previo.identificacion, 'atencion', v_previo.atencion, 'lead_id', v_previo.lead_id);
  end if;

  select * into v_pol from crm.llamadas_celular_politica where singleton;

  -- Decisión 2: con las entrantes apagadas, una entrante no se guarda.
  if v_dir = 'entrante' and not coalesce(v_pol.entrantes_activas, false) then
    return pg_catalog.jsonb_build_object('repetido', false, 'ignorado', true, 'motivo', 'entrante_apagada');
  end if;
  if v_dir = 'desconocida' then
    v_calidad := v_calidad || '{"direccion": "desconocida"}'::jsonb;
  end if;
  if v_ocurrio is not null and v_ocurrio > pg_catalog.now() + interval '5 minutes' then
    v_calidad := v_calidad || '{"reloj": "adelantado"}'::jsonb;
  end if;

  v_formas := private.llamada_celular_formas(v_numero);
  v_e164 := (select c.e164 from private.canonizar_contacto(v_numero) c limit 1);
  if v_e164 is null and v_numero is not null then
    v_calidad := v_calidad || '{"numero": "no_canonizable"}'::jsonb;
  elsif v_numero is null then
    v_calidad := v_calidad || '{"numero": "oculto"}'::jsonb;
  end if;
  v_cand := private.llamada_celular_candidatos(v_formas);

  if pg_catalog.cardinality(v_cand) = 1 then
    v_lead := v_cand[1];
    v_ident := 'identificado';
    v_metodo := 'exacto';
    v_aten := case when private.llamada_celular_elegible_dueno(v_asig.analista_id, v_lead)
                   then 'requiere_resultado' else 'por_revisar' end;
  elsif pg_catalog.cardinality(v_cand) > 1 then
    v_ident := 'ambiguo';
    v_aten := 'por_revisar';
    v_calidad := v_calidad || pg_catalog.jsonb_build_object('candidatos', pg_catalog.cardinality(v_cand));
  elsif coalesce(v_pol.guardar_sin_identificar, false) then
    v_ident := 'sin_identificar';
    v_aten := 'por_revisar';
  else
    -- Decisión 3: si el número no es de ningún lead, la llamada no pertenece al CRM.
    return pg_catalog.jsonb_build_object('repetido', false, 'ignorado', true,
      'motivo', case when pg_catalog.cardinality(v_formas) = 0 then 'numero_no_valido' else 'sin_lead' end);
  end if;

  insert into crm.llamadas_celular_eventos
    (asignacion_id, analista_id, evento_origen_id, hash_payload, numero_canonico, direccion,
     estado_tecnico, duracion_seg, ocurrio_en, calidad, identificacion, atencion, lead_id,
     metodo_asociacion, asociado_en)
  values
    -- Sin forma E.164 se guarda la del trigger de leads (la que encontró el lead), para poder
    -- volver a buscar candidatos al asociar.
    (v_asig.id, v_asig.analista_id, v_origen, v_hash, coalesce(v_e164, v_formas[1]), v_dir,
     v_estado, v_dur, v_ocurrio, v_calidad, v_ident, v_aten, v_lead,
     v_metodo, case when v_lead is not null then pg_catalog.now() end)
  on conflict on constraint llamadas_celular_eventos_origen_unico do nothing
  returning id into v_id;

  if v_id is null then
    -- Dos envíos a la vez del mismo origen: gana el primero; el segundo responde como repetido
    -- (o conflicto si su contenido es otro).
    select * into v_previo from crm.llamadas_celular_eventos e
    where e.asignacion_id = p_asignacion_id and e.evento_origen_id = v_origen;
    if v_previo.hash_payload <> v_hash then
      raise exception using errcode = 'P0409',
        message = 'Esta llamada llegó a la vez con otro contenido; no se puede reenviar así';
    end if;
    return pg_catalog.jsonb_build_object('evento_id', v_previo.id, 'repetido', true, 'ignorado', false,
      'identificacion', v_previo.identificacion, 'atencion', v_previo.atencion, 'lead_id', v_previo.lead_id);
  end if;

  return pg_catalog.jsonb_build_object('evento_id', v_id, 'repetido', false, 'ignorado', false,
    'identificacion', v_ident, 'atencion', v_aten, 'lead_id', v_lead);
end;
$function$;

-- ── 3. Permisos: núcleo sin EXECUTE para nadie ───────────────────────────────────────────────
revoke all on function private.llamada_celular_elegible_dueno(uuid,uuid) from public, anon, authenticated, service_role;
revoke all on function private.llamada_celular_ingerir(uuid,jsonb) from public, anon, authenticated, service_role;

-- ── 4. Comentarios ───────────────────────────────────────────────────────────────────────────
comment on function private.llamada_celular_elegible_dueno(uuid,uuid) is
  'Decisión 1 evaluada COMO el dueño del celular: fija request.jwt.claim.sub al dueño solo durante private.llamada_celular_elegible (la regla de ámbito real, que exige que el actor sea quien pregunta) y devuelve la identidad anterior antes de que la ingesta escriba. Sin dueño, no es elegible. Solo la usa la ingesta, que llega sin sesión.';
comment on function private.llamada_celular_ingerir(uuid,jsonb) is
  'Núcleo de la ingesta (F3 lo llamará desde su puerta de servicio): evento v1 con claves exactas; asignación vigente con analista activo (42501); canonización con las dos reglas y coincidencia exacta; un lead → identificado (pide resultado si es elegible), varios → ambiguo, ninguno → no se guarda (decisión 3, perilla guardar_sin_identificar); entrante con entrantes apagadas → no se guarda. Idempotente: mismo origen + contenido → repetido; otro contenido → P0409. DATO PERSONAL: el número. Desde 20261001222431 la atención inicial se evalúa como el dueño del celular (private.llamada_celular_elegible_dueno).';

-- ── 5. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f text;
begin
  foreach v_f in array array['private.llamada_celular_elegible_dueno(uuid,uuid)', 'private.llamada_celular_ingerir(uuid,jsonb)'] loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f::regprocedure) then
      raise exception 'LLAMADAS_ELEGIBILIDAD: % debería ser SECURITY INVOKER', v_f;
    end if;
    if exists (
      select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
      where p.oid = v_f::regprocedure and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner
    ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f::regprocedure) then
      raise exception 'LLAMADAS_ELEGIBILIDAD: EXECUTE inesperado en %', v_f;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'LLAMADAS_ELEGIBILIDAD: search_path inesperado en %', v_f;
    end if;
    if pg_catalog.obj_description(v_f::regprocedure, 'pg_proc') is null then
      raise exception 'LLAMADAS_ELEGIBILIDAD: % sin COMMENT', v_f;
    end if;
  end loop;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_ingerir(uuid,jsonb)'::regprocedure),
                       'private.llamada_celular_elegible_dueno(v_asig.analista_id, v_lead)') = 0 then
    raise exception 'LLAMADAS_ELEGIBILIDAD: la ingesta no evalúa la elegibilidad como el dueño del celular';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;

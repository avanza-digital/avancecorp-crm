-- Llamadas desde el celular · F2-c: NÚCLEO Y PUERTAS. Plan aprobado (Versión 3), fase F2.3.
--
-- Qué hace (sobre las tablas de 20261001145242):
--   Núcleo en private — SECURITY INVOKER, sin EXECUTE para nadie: solo lo invocan las puertas
--   DEFINER de abajo y, en F3, la puerta de servicio de la ingesta (excepción documentada del
--   estándar: un núcleo que solo llaman definers puede ser invoker). Cada operación bloquea la
--   fila que toca, revalida el ámbito del actor bajo ese bloqueo y es idempotente:
--     · llamada_celular_ingerir(asignación, evento): claves exactas y versión 1; asignación
--       vigente con analista activo (si no, 42501); número canonizado con las DOS reglas del CRM
--       (canonizar_contacto y normalizar_telefono); coincidencia exacta entre los leads activos.
--       Un lead → identificado; varios → ambiguo; ninguno → no se guarda (decisión 3, salvo la
--       perilla guardar_sin_identificar); entrante con entrantes apagadas → no se guarda
--       (decisión 2). Mismo origen + mismo contenido → mismo evento (repetido); mismo origen con
--       otro contenido → P0409. La hora va normalizada a UTC dentro del hash (si no, el mismo
--       instante con otra zona sería «otro contenido»).
--     · llamada_celular_asociar (solo a un lead que tenga el número de la llamada: nunca fabrica
--       gestión), _enlazar (uno a uno con un resultado de llamada del mismo lead, posterior a la
--       llamada; si el enlazado fue deshecho, el enlace se MUEVE al nuevo: decisión 4) y
--       _descartar (motivo de catálogo; «otro» con detalle).
--     · celular_asignar / _cerrar / _rotar_credencial: solo gerencia. La credencial (32 bytes
--       aleatorios en hex) se devuelve UNA vez y solo se guarda su sha256.
--     · llamadas_celular_politica_fijar: solo gerencia.
--   Lecturas: bandeja de pendientes y detalle con la atención EFECTIVA calculada al leer
--   (decisión 1): una llamada que pedía resultado deja de pedirlo si el lead ya no es elegible
--   para quien mira; tras una reasignación la ve y la trabaja el analista nuevo (decisión 7),
--   y quién marcó (analista_id) no cambia.
--   Puertas en crm — SECURITY DEFINER (indispensable: las tablas no tienen privilegios para la
--   API), search_path vacío, EXECUTE solo authenticated: resuelven auth.uid(), exigen rol CRM
--   activo y delegan. No hay puerta de ingesta para el celular: llega en F3.
--
-- Decisiones de criterio de Claude (01/10/2026), para que Miguel las confirme o cambie:
--   · Asignar, cerrar y rotar celulares, y fijar la política: solo gerencia. Supervisión LEE las
--     asignaciones de su equipo.
--   · Llamada de un analista a un lead que no es de su ámbito: se guarda identificada y «por
--     revisar» (sin encuesta); la ve la cadena del dueño del lead, no quien llamó.
--   · Un resultado solo se enlaza si se registró después de la llamada (tolerancia de 10 min por
--     relojes desfasados).
--   · Celular para analistas y supervisores (rol vendedor o supervisor activos).
--
-- Reversión: ../scripts/llamadas-celular/reversa-nucleo.sql (retira puertas y núcleo; las
-- tablas y sus filas quedan). Verificación: npm run test:llamadas:local.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regclass('crm.llamadas_celular_eventos') is null
     or to_regclass('crm.llamadas_celular_enlaces') is null
     or to_regclass('crm.celulares_asignaciones') is null
     or to_regclass('crm.llamadas_celular_politica') is null
     or to_regprocedure('private.caducar_llamadas_celular()') is null then
    raise exception 'LLAMADAS_NUCLEO: falta la migración de datos 20261001145242';
  end if;
  if to_regprocedure('private.idem_hash(jsonb)') is null
     or to_regprocedure('private.canonizar_contacto(text)') is null
     or to_regprocedure('private.normalizar_telefono(text)') is null
     or to_regprocedure('private.sla_gestion_permitida(uuid,uuid)') is null
     or to_regprocedure('private.vendedor_ids_visibles(uuid)') is null
     or to_regprocedure('private.rol_crm(uuid)') is null
     or to_regprocedure('extensions.gen_random_bytes(integer)') is null
     or to_regprocedure('auth.uid()') is null then
    raise exception 'LLAMADAS_NUCLEO: faltan dependencias (idem_hash, canonización, ámbito, pgcrypto o auth.uid)';
  end if;
  if to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb)') is not null
     or to_regprocedure('crm.llamadas_celular_pendientes_fn(integer)') is not null
     or to_regprocedure('crm.asignar_celular(text,uuid)') is not null then
    raise exception 'LLAMADAS_NUCLEO: los objetos ya existen; no se sobrescriben';
  end if;
end;
$precondicion$;

-- ── 1. Ayudantes del núcleo (INVOKER, sin EXECUTE para nadie) ─────────────────────────────

create function private.celular_credencial_hash(p_credencial text)
returns text
language sql
immutable
set search_path = ''
as $function$
  select pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(coalesce(p_credencial, ''), 'utf8')), 'hex')
$function$;

-- Las dos formas canónicas con las que el CRM guarda teléfonos: la de canonizar_contacto (E.164
-- con fijo e internacional; telefono_alternativo) y la del trigger de crm.leads.telefono
-- (normalizar_telefono). Nunca se recortan dígitos: solo igualdad exacta.
create function private.llamada_celular_formas(p_numero text)
returns text[]
language sql
immutable
set search_path = ''
as $function$
  select coalesce(pg_catalog.array_agg(distinct s.f) filter (where s.f is not null), '{}'::text[])
  from (
    select (select c.e164 from private.canonizar_contacto(p_numero) c limit 1) as f
    union all
    select case when private.normalizar_telefono(p_numero) ~ '^\+[1-9][0-9]{7,14}$'
                then private.normalizar_telefono(p_numero) end
  ) s
$function$;

create function private.llamada_celular_candidatos(p_formas text[])
returns uuid[]
language sql
stable
set search_path = ''
as $function$
  select coalesce(pg_catalog.array_agg(distinct l.id), '{}'::uuid[])
  from crm.leads l
  where l.activo
    and pg_catalog.cardinality(p_formas) > 0
    and (l.telefono = any(p_formas) or l.telefono_alternativo = any(p_formas))
$function$;

-- Decisión 1: pide resultado si el lead está activo, en etapa abierta, sin «no contactar» y
-- dentro del ámbito de quien lo trabaja.
create function private.llamada_celular_elegible(p_actor uuid, p_lead uuid)
returns boolean
language sql
stable
set search_path = ''
as $function$
  select coalesce((
           select l.activo and l.etapa not in ('convertido', 'descartado') and not l.no_contactar
           from crm.leads l where l.id = p_lead), false)
     and coalesce(private.sla_gestion_permitida(p_actor, p_lead), false)
$function$;

-- Quién ve una llamada: gerencia, todas; con lead, quien hoy tiene ámbito sobre el lead
-- (decisión 7); sin lead (ambigua), quien llamó y su cadena de supervisión.
create function private.llamada_celular_visible(p_actor uuid, p_lead uuid, p_analista uuid)
returns boolean
language sql
stable
set search_path = ''
as $function$
  select p_actor is not null and (
    coalesce(private.rol_crm(p_actor) = 'gerencia', false)
    or (p_lead is not null and coalesce(private.sla_gestion_permitida(p_actor, p_lead), false))
    or (p_lead is null and (p_analista = p_actor
          or p_analista in (select private.vendedor_ids_visibles(p_actor))))
  )
$function$;

-- La atención que se MUESTRA (decisión 1): se recalcula al leer con quien mira.
create function private.llamada_celular_atencion_efectiva(
  p_actor uuid, p_atencion text, p_identificacion text, p_lead uuid)
returns text
language sql
stable
set search_path = ''
as $function$
  select case
    when p_atencion in ('registrado', 'descartado_con_motivo', 'requiere_devolucion') then p_atencion
    when p_identificacion <> 'identificado' then 'por_revisar'
    when p_atencion = 'requiere_resultado' and private.llamada_celular_elegible(p_actor, p_lead)
      then 'requiere_resultado'
    else 'por_revisar'
  end
$function$;

-- Resuelve y autoriza al actor de una puerta. Lanza 42501 si no tiene un rol permitido.
create function private.llamadas_celular_actor(p_roles text[])
returns uuid
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
begin
  if v_actor is null or coalesce(private.rol_crm(v_actor), '') <> all(p_roles) then
    raise exception using errcode = '42501', message = 'Sin acceso a las llamadas del celular';
  end if;
  return v_actor;
end;
$function$;

-- ── 2. Ingesta (la invocará la puerta de servicio de F3) ─────────────────────────────────
create function private.llamada_celular_ingerir(p_asignacion_id uuid, p_evento jsonb)
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
    v_aten := case when private.llamada_celular_elegible(v_asig.analista_id, v_lead)
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

-- ── 3. Operaciones sobre una llamada ─────────────────────────────────────────────────────
create function private.llamada_celular_asociar(p_actor uuid, p_evento_id uuid, p_lead_id uuid)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_ev crm.llamadas_celular_eventos%rowtype;
  v_aten text;
begin
  if p_evento_id is null or p_lead_id is null then
    raise exception using errcode = '22023', message = 'Faltan la llamada o el lead';
  end if;
  select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id for update;
  if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
    raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
  end if;
  if v_ev.atencion in ('registrado', 'descartado_con_motivo') then
    raise exception using errcode = '22023', message = 'La llamada ya está registrada o descartada';
  end if;
  if v_ev.lead_id = p_lead_id then
    return pg_catalog.jsonb_build_object('evento_id', v_ev.id, 'lead_id', v_ev.lead_id, 'repetido', true,
      'atencion', private.llamada_celular_atencion_efectiva(p_actor, v_ev.atencion, v_ev.identificacion, v_ev.lead_id));
  end if;
  if not coalesce(private.sla_gestion_permitida(p_actor, p_lead_id), false) then
    raise exception using errcode = '42501', message = 'Ese lead no es de tu ámbito';
  end if;
  -- Nunca fabrica gestión: el lead elegido tiene que tener el número de la llamada.
  if not (p_lead_id = any(private.llamada_celular_candidatos(private.llamada_celular_formas(v_ev.numero_canonico)))) then
    raise exception using errcode = '22023', message = 'Ese lead no tiene el número de la llamada';
  end if;
  v_aten := case when private.llamada_celular_elegible(p_actor, p_lead_id)
                 then 'requiere_resultado' else 'por_revisar' end;
  update crm.llamadas_celular_eventos
     set identificacion = 'identificado', lead_id = p_lead_id, metodo_asociacion = 'manual',
         asociado_por = p_actor, asociado_en = pg_catalog.now(), atencion = v_aten
   where id = v_ev.id;
  return pg_catalog.jsonb_build_object('evento_id', v_ev.id, 'lead_id', p_lead_id, 'repetido', false,
    'atencion', v_aten);
end;
$function$;

create function private.llamada_celular_enlazar(p_actor uuid, p_evento_id uuid, p_actividad_id uuid)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_ev crm.llamadas_celular_eventos%rowtype;
  v_act crm.actividades%rowtype;
  v_enl crm.llamadas_celular_enlaces%rowtype;
  v_deshecha boolean;
  v_movido boolean := false;
begin
  if p_evento_id is null or p_actividad_id is null then
    raise exception using errcode = '22023', message = 'Faltan la llamada o el resultado';
  end if;
  -- Decisión 7: con lead, «visible» ES tener hoy ámbito sobre él; quien ya no lo tiene no
  -- registra por él (gerencia ve todo y tiene ámbito sobre todo).
  select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id for update;
  if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
    raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
  end if;
  if v_ev.identificacion <> 'identificado' then
    raise exception using errcode = '22023', message = 'Primero asocia la llamada a un lead';
  end if;
  if v_ev.atencion = 'descartado_con_motivo' then
    raise exception using errcode = '22023', message = 'La llamada fue descartada';
  end if;
  select * into v_act from crm.actividades a where a.id = p_actividad_id;
  if not found or v_act.lead_id <> v_ev.lead_id then
    raise exception using errcode = '22023', message = 'El resultado no es del lead de la llamada';
  end if;
  if v_act.tipo not in ('llamada_realizada', 'llamada_no_contestada')
     or coalesce(v_act.metadata ->> 'evento', '') <> 'resultado_llamada' then
    raise exception using errcode = '22023', message = 'Solo se enlaza un resultado de llamada registrado en la encuesta';
  end if;
  if v_act.creado_en < coalesce(v_ev.ocurrio_en, v_ev.recibido_en) - interval '10 minutes' then
    raise exception using errcode = '22023', message = 'El resultado se registró antes de la llamada';
  end if;

  select * into v_enl from crm.llamadas_celular_enlaces l where l.evento_id = v_ev.id for update;
  if found then
    if v_enl.actividad_id = p_actividad_id then
      return pg_catalog.jsonb_build_object('evento_id', v_ev.id, 'actividad_id', p_actividad_id,
        'repetido', true, 'movido', false);
    end if;
    select (a.metadata ? 'deshecho_en') into v_deshecha from crm.actividades a where a.id = v_enl.actividad_id;
    if v_enl.actividad_id is not null and not coalesce(v_deshecha, false) then
      raise exception using errcode = '23505', message = 'La llamada ya tiene su resultado registrado';
    end if;
    begin
      update crm.llamadas_celular_enlaces set actividad_id = p_actividad_id, enlazado_por = p_actor
       where id = v_enl.id;
    exception when unique_violation then
      raise exception using errcode = '23505', message = 'Ese resultado ya está enlazado a otra llamada';
    end;
    v_movido := true;
  else
    begin
      insert into crm.llamadas_celular_enlaces (evento_id, actividad_id, lead_id, enlazado_por)
      values (v_ev.id, p_actividad_id, v_ev.lead_id, p_actor);
    exception when unique_violation then
      raise exception using errcode = '23505', message = 'Ese resultado ya está enlazado a otra llamada';
    end;
  end if;

  -- La máquina de estados de la tabla exige pasar por «requiere resultado».
  if v_ev.atencion = 'por_revisar' then
    update crm.llamadas_celular_eventos set atencion = 'requiere_resultado' where id = v_ev.id;
  end if;
  if v_ev.atencion <> 'registrado' then
    update crm.llamadas_celular_eventos set atencion = 'registrado' where id = v_ev.id;
  end if;
  return pg_catalog.jsonb_build_object('evento_id', v_ev.id, 'actividad_id', p_actividad_id,
    'repetido', false, 'movido', v_movido);
end;
$function$;

create function private.llamada_celular_descartar(p_actor uuid, p_evento_id uuid, p_motivo text, p_detalle text)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_ev crm.llamadas_celular_eventos%rowtype;
  v_detalle text := nullif(pg_catalog.btrim(coalesce(p_detalle, '')), '');
begin
  if p_evento_id is null then
    raise exception using errcode = '22023', message = 'Falta la llamada';
  end if;
  if p_motivo is null or p_motivo not in ('no_comercial', 'personal', 'numero_de_prueba', 'error_captura', 'otro') then
    raise exception using errcode = '22023',
      message = 'Motivo inválido (no_comercial, personal, numero_de_prueba, error_captura u otro)';
  end if;
  if p_motivo = 'otro' and pg_catalog.length(coalesce(v_detalle, '')) < 3 then
    raise exception using errcode = '22023', message = 'Con «otro», escribe el motivo (al menos 3 caracteres)';
  end if;
  if pg_catalog.length(coalesce(v_detalle, '')) > 300 then
    raise exception using errcode = '22023', message = 'El detalle no puede pasar de 300 caracteres';
  end if;
  select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id for update;
  if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
    raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
  end if;
  if v_ev.atencion = 'descartado_con_motivo' then
    if v_ev.motivo_descarte = p_motivo and v_ev.motivo_descarte_detalle is not distinct from v_detalle then
      return pg_catalog.jsonb_build_object('evento_id', v_ev.id, 'repetido', true, 'motivo', p_motivo);
    end if;
    raise exception using errcode = '23505', message = 'La llamada ya fue descartada con otro motivo';
  end if;
  if v_ev.atencion = 'registrado' then
    raise exception using errcode = '22023', message = 'La llamada ya tiene su resultado registrado';
  end if;
  update crm.llamadas_celular_eventos
     set atencion = 'descartado_con_motivo', motivo_descarte = p_motivo, motivo_descarte_detalle = v_detalle,
         descartado_por = p_actor, descartado_en = pg_catalog.now()
   where id = v_ev.id;
  return pg_catalog.jsonb_build_object('evento_id', v_ev.id, 'repetido', false, 'motivo', p_motivo);
end;
$function$;

-- ── 4. Celulares y política (gerencia) ───────────────────────────────────────────────────
create function private.celular_asignar(p_actor uuid, p_etiqueta text, p_analista_id uuid)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_credencial text;
  v_id uuid;
begin
  if coalesce(private.rol_crm(p_actor), '') <> 'gerencia' then
    raise exception using errcode = '42501', message = 'Solo gerencia asigna celulares';
  end if;
  if p_etiqueta is null or p_etiqueta !~ '^C[1-9][0-9]{0,2}$' then
    raise exception using errcode = '22023', message = 'Etiqueta inválida (C1, C2…)';
  end if;
  if coalesce(private.rol_crm(p_analista_id), '') not in ('vendedor', 'supervisor') then
    raise exception using errcode = '22023', message = 'El celular se asigna a un analista o supervisor activo';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('celular:' || p_etiqueta, 0));
  if exists (select 1 from crm.celulares_asignaciones a where a.etiqueta = p_etiqueta and a.vigente_hasta is null) then
    raise exception using errcode = '23505',
      message = pg_catalog.format('%s ya está asignado: ciérralo o rota su credencial', p_etiqueta);
  end if;
  v_credencial := pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');
  insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash, vigente_desde, creado_por)
  values (p_etiqueta, p_analista_id, private.celular_credencial_hash(v_credencial), pg_catalog.clock_timestamp(), p_actor)
  returning id into v_id;
  -- La credencial se devuelve UNA vez; solo queda su hash.
  return pg_catalog.jsonb_build_object('asignacion_id', v_id, 'etiqueta', p_etiqueta,
    'analista_id', p_analista_id, 'credencial', v_credencial);
end;
$function$;

create function private.celular_cerrar(p_actor uuid, p_asignacion_id uuid, p_motivo text)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_asig crm.celulares_asignaciones%rowtype;
begin
  if coalesce(private.rol_crm(p_actor), '') <> 'gerencia' then
    raise exception using errcode = '42501', message = 'Solo gerencia cierra asignaciones de celular';
  end if;
  if p_motivo is null or p_motivo not in ('rotacion', 'baja_analista', 'extravio', 'reemplazo', 'otro') then
    raise exception using errcode = '22023', message = 'Motivo inválido (rotacion, baja_analista, extravio, reemplazo u otro)';
  end if;
  select * into v_asig from crm.celulares_asignaciones a where a.id = p_asignacion_id for update;
  if not found then
    raise exception using errcode = '22023', message = 'Asignación no encontrada';
  end if;
  if v_asig.vigente_hasta is not null then
    if v_asig.motivo_cierre = p_motivo then
      return pg_catalog.jsonb_build_object('asignacion_id', v_asig.id, 'repetido', true);
    end if;
    raise exception using errcode = '23505', message = 'La asignación ya estaba cerrada con otro motivo';
  end if;
  update crm.celulares_asignaciones
     set vigente_hasta = pg_catalog.clock_timestamp(), motivo_cierre = p_motivo
   where id = v_asig.id;
  return pg_catalog.jsonb_build_object('asignacion_id', v_asig.id, 'repetido', false);
end;
$function$;

create function private.celular_rotar_credencial(p_actor uuid, p_etiqueta text)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_asig crm.celulares_asignaciones%rowtype;
  v_t timestamptz;
  v_credencial text;
  v_id uuid;
begin
  if coalesce(private.rol_crm(p_actor), '') <> 'gerencia' then
    raise exception using errcode = '42501', message = 'Solo gerencia rota credenciales de celular';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('celular:' || coalesce(p_etiqueta, ''), 0));
  select * into v_asig from crm.celulares_asignaciones a
  where a.etiqueta = p_etiqueta and a.vigente_hasta is null for update;
  if not found then
    raise exception using errcode = '22023', message = 'Ese celular no tiene una asignación vigente';
  end if;
  if coalesce(private.rol_crm(v_asig.analista_id), '') not in ('vendedor', 'supervisor') then
    raise exception using errcode = '22023', message = 'El analista del celular ya no está activo: ciérralo y asígnalo a otro';
  end if;
  v_t := pg_catalog.clock_timestamp();
  update crm.celulares_asignaciones set vigente_hasta = v_t, motivo_cierre = 'rotacion' where id = v_asig.id;
  v_credencial := pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');
  insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash, vigente_desde, creado_por)
  values (v_asig.etiqueta, v_asig.analista_id, private.celular_credencial_hash(v_credencial), v_t, p_actor)
  returning id into v_id;
  return pg_catalog.jsonb_build_object('asignacion_id', v_id, 'etiqueta', v_asig.etiqueta,
    'analista_id', v_asig.analista_id, 'credencial', v_credencial, 'anterior_id', v_asig.id);
end;
$function$;

create function private.llamadas_celular_politica_fijar(
  p_actor uuid, p_guardar_sin_identificar boolean, p_entrantes_activas boolean,
  p_dias_descartados integer, p_dias_sin_resolver integer, p_dias_sin_identificar integer)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_pol crm.llamadas_celular_politica%rowtype;
begin
  if coalesce(private.rol_crm(p_actor), '') <> 'gerencia' then
    raise exception using errcode = '42501', message = 'Solo gerencia ajusta la política de llamadas';
  end if;
  if (p_dias_descartados is not null and p_dias_descartados not between 1 and 365)
     or (p_dias_sin_resolver is not null and p_dias_sin_resolver not between 1 and 365)
     or (p_dias_sin_identificar is not null and p_dias_sin_identificar not between 1 and 365) then
    raise exception using errcode = '22023', message = 'Los días de retención van de 1 a 365';
  end if;
  update crm.llamadas_celular_politica
     set guardar_sin_identificar = coalesce(p_guardar_sin_identificar, guardar_sin_identificar),
         entrantes_activas = coalesce(p_entrantes_activas, entrantes_activas),
         dias_retencion_descartados = coalesce(p_dias_descartados, dias_retencion_descartados),
         dias_retencion_sin_resolver = coalesce(p_dias_sin_resolver, dias_retencion_sin_resolver),
         dias_retencion_sin_identificar = coalesce(p_dias_sin_identificar, dias_retencion_sin_identificar),
         actualizado_por = p_actor
   where singleton
  returning * into v_pol;
  return pg_catalog.to_jsonb(v_pol) - 'singleton';
end;
$function$;

-- ── 5. Lecturas ──────────────────────────────────────────────────────────────────────────
create function private.llamadas_celular_pendientes(p_actor uuid, p_limite integer)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select coalesce(pg_catalog.jsonb_agg(f.fila order by f.recibido_en desc), '[]'::jsonb)
  from (
    select e.recibido_en,
           pg_catalog.jsonb_build_object(
             'evento_id', e.id, 'recibido_en', e.recibido_en, 'ocurrio_en', e.ocurrio_en,
             'numero', e.numero_canonico, 'direccion', e.direccion, 'estado_tecnico', e.estado_tecnico,
             'duracion_seg', e.duracion_seg, 'identificacion', e.identificacion,
             'atencion', private.llamada_celular_atencion_efectiva(p_actor, e.atencion, e.identificacion, e.lead_id),
             'lead_id', e.lead_id, 'lead_nombre', l.nombre_completo,
             'analista_id', e.analista_id, 'es_propia', e.analista_id = p_actor) as fila
    from crm.llamadas_celular_eventos e
    left join crm.leads l on l.id = e.lead_id
    where e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')
      and private.llamada_celular_visible(p_actor, e.lead_id, e.analista_id)
    order by e.recibido_en desc
    limit p_limite
  ) f
$function$;

create function private.llamada_celular_detalle(p_actor uuid, p_evento_id uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_ev crm.llamadas_celular_eventos%rowtype;
  v_enl crm.llamadas_celular_enlaces%rowtype;
  v_deshecha boolean;
begin
  select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id;
  if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
    raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
  end if;
  select * into v_enl from crm.llamadas_celular_enlaces l where l.evento_id = v_ev.id;
  if found and v_enl.actividad_id is not null then
    select (a.metadata ? 'deshecho_en') into v_deshecha from crm.actividades a where a.id = v_enl.actividad_id;
  end if;
  return pg_catalog.jsonb_build_object(
    'evento_id', v_ev.id, 'recibido_en', v_ev.recibido_en, 'ocurrio_en', v_ev.ocurrio_en,
    'numero', v_ev.numero_canonico, 'direccion', v_ev.direccion, 'estado_tecnico', v_ev.estado_tecnico,
    'duracion_seg', v_ev.duracion_seg, 'calidad', v_ev.calidad, 'identificacion', v_ev.identificacion,
    'atencion', private.llamada_celular_atencion_efectiva(p_actor, v_ev.atencion, v_ev.identificacion, v_ev.lead_id),
    'lead_id', v_ev.lead_id, 'metodo_asociacion', v_ev.metodo_asociacion, 'analista_id', v_ev.analista_id,
    'motivo_descarte', v_ev.motivo_descarte, 'motivo_descarte_detalle', v_ev.motivo_descarte_detalle,
    'actividad_id', v_enl.actividad_id,
    -- Decisión 4: los efectos deshechos se DERIVAN del resultado, no se copian.
    'efectos_anulados', coalesce(v_deshecha, false));
end;
$function$;

create function private.celulares_asignaciones_listar(p_actor uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'asignacion_id', a.id, 'etiqueta', a.etiqueta, 'analista_id', a.analista_id,
           'analista_nombre', p.nombre_completo, 'vigente_desde', a.vigente_desde,
           'vigente_hasta', a.vigente_hasta, 'motivo_cierre', a.motivo_cierre)
         order by a.etiqueta, a.vigente_desde desc), '[]'::jsonb)
  from crm.celulares_asignaciones a
  left join public.perfiles p on p.id = a.analista_id
  where private.rol_crm(p_actor) = 'gerencia'
     or (private.rol_crm(p_actor) = 'supervisor'
         and a.analista_id in (select private.vendedor_ids_visibles(p_actor)))
$function$;

-- ── 6. Puertas (crm, DEFINER, EXECUTE solo authenticated) ─────────────────────────────────
create function crm.llamadas_celular_pendientes_fn(p_limite integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := private.llamadas_celular_actor(array['vendedor', 'supervisor', 'gerencia']);
begin
  if p_limite is null or p_limite not between 1 and 200 then
    raise exception using errcode = '22023', message = 'El límite va de 1 a 200';
  end if;
  return private.llamadas_celular_pendientes(v_actor, p_limite);
end;
$function$;

create function crm.llamada_celular_detalle_fn(p_evento_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := private.llamadas_celular_actor(array['vendedor', 'supervisor', 'gerencia']);
begin
  return private.llamada_celular_detalle(v_actor, p_evento_id);
end;
$function$;

create function crm.asociar_llamada_celular(p_evento_id uuid, p_lead_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := private.llamadas_celular_actor(array['vendedor', 'supervisor', 'gerencia']);
begin
  return private.llamada_celular_asociar(v_actor, p_evento_id, p_lead_id);
end;
$function$;

create function crm.enlazar_llamada_celular(p_evento_id uuid, p_actividad_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := private.llamadas_celular_actor(array['vendedor', 'supervisor', 'gerencia']);
begin
  return private.llamada_celular_enlazar(v_actor, p_evento_id, p_actividad_id);
end;
$function$;

create function crm.descartar_llamada_celular(p_evento_id uuid, p_motivo text, p_detalle text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := private.llamadas_celular_actor(array['vendedor', 'supervisor', 'gerencia']);
begin
  return private.llamada_celular_descartar(v_actor, p_evento_id, p_motivo, p_detalle);
end;
$function$;

create function crm.celulares_asignaciones_fn()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := private.llamadas_celular_actor(array['supervisor', 'gerencia']);
begin
  return private.celulares_asignaciones_listar(v_actor);
end;
$function$;

create function crm.asignar_celular(p_etiqueta text, p_analista_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := private.llamadas_celular_actor(array['gerencia']);
begin
  return private.celular_asignar(v_actor, p_etiqueta, p_analista_id);
end;
$function$;

create function crm.cerrar_asignacion_celular(p_asignacion_id uuid, p_motivo text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := private.llamadas_celular_actor(array['gerencia']);
begin
  return private.celular_cerrar(v_actor, p_asignacion_id, p_motivo);
end;
$function$;

create function crm.rotar_credencial_celular(p_etiqueta text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := private.llamadas_celular_actor(array['gerencia']);
begin
  return private.celular_rotar_credencial(v_actor, p_etiqueta);
end;
$function$;

create function crm.llamadas_celular_politica_fn()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := private.llamadas_celular_actor(array['gerencia']);
begin
  return (select pg_catalog.to_jsonb(p) - 'singleton' from crm.llamadas_celular_politica p where p.singleton);
end;
$function$;

create function crm.fijar_politica_llamadas_celular(
  p_guardar_sin_identificar boolean default null, p_entrantes_activas boolean default null,
  p_dias_retencion_descartados integer default null, p_dias_retencion_sin_resolver integer default null,
  p_dias_retencion_sin_identificar integer default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := private.llamadas_celular_actor(array['gerencia']);
begin
  return private.llamadas_celular_politica_fijar(v_actor, p_guardar_sin_identificar, p_entrantes_activas,
    p_dias_retencion_descartados, p_dias_retencion_sin_resolver, p_dias_retencion_sin_identificar);
end;
$function$;

-- ── 7. Permisos: núcleo sin EXECUTE para nadie; puertas solo authenticated ───────────────
do $permisos$
declare
  v_f text;
begin
  foreach v_f in array array[
    'private.celular_credencial_hash(text)', 'private.llamada_celular_formas(text)',
    'private.llamada_celular_candidatos(text[])', 'private.llamada_celular_elegible(uuid,uuid)',
    'private.llamada_celular_visible(uuid,uuid,uuid)',
    'private.llamada_celular_atencion_efectiva(uuid,text,text,uuid)', 'private.llamadas_celular_actor(text[])',
    'private.llamada_celular_ingerir(uuid,jsonb)', 'private.llamada_celular_asociar(uuid,uuid,uuid)',
    'private.llamada_celular_enlazar(uuid,uuid,uuid)', 'private.llamada_celular_descartar(uuid,uuid,text,text)',
    'private.celular_asignar(uuid,text,uuid)', 'private.celular_cerrar(uuid,uuid,text)',
    'private.celular_rotar_credencial(uuid,text)',
    'private.llamadas_celular_politica_fijar(uuid,boolean,boolean,integer,integer,integer)',
    'private.llamadas_celular_pendientes(uuid,integer)', 'private.llamada_celular_detalle(uuid,uuid)',
    'private.celulares_asignaciones_listar(uuid)'] loop
    execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
  end loop;
  foreach v_f in array array[
    'crm.llamadas_celular_pendientes_fn(integer)', 'crm.llamada_celular_detalle_fn(uuid)',
    'crm.asociar_llamada_celular(uuid,uuid)', 'crm.enlazar_llamada_celular(uuid,uuid)',
    'crm.descartar_llamada_celular(uuid,text,text)', 'crm.celulares_asignaciones_fn()',
    'crm.asignar_celular(text,uuid)', 'crm.cerrar_asignacion_celular(uuid,text)',
    'crm.rotar_credencial_celular(text)', 'crm.llamadas_celular_politica_fn()',
    'crm.fijar_politica_llamadas_celular(boolean,boolean,integer,integer,integer)'] loop
    execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
    execute pg_catalog.format('grant execute on function %s to authenticated', v_f);
  end loop;
end;
$permisos$;

-- ── 8. Comentarios ───────────────────────────────────────────────────────────────────────
comment on function private.celular_credencial_hash(text) is
  'sha256 en hex de la credencial de un celular (mismo modelo que private.saga_token_hash). La credencial en claro nunca se guarda.';
comment on function private.llamada_celular_formas(text) is
  'Las dos formas canónicas de un número con las que el CRM guarda teléfonos (canonizar_contacto y normalizar_telefono); solo formas E.164 válidas, sin recortar dígitos.';
comment on function private.llamada_celular_candidatos(text[]) is
  'Leads activos cuyo teléfono principal o alternativo es EXACTAMENTE una de las formas dadas.';
comment on function private.llamada_celular_elegible(uuid,uuid) is
  'Decisión 1 (provisional, Jhosep 30/09): la llamada pide resultado si el lead está activo, en etapa abierta, sin «no contactar» y en el ámbito del actor (sla_gestion_permitida).';
comment on function private.llamada_celular_visible(uuid,uuid,uuid) is
  'Quién ve una llamada: gerencia todas; con lead, quien hoy tiene ámbito sobre el lead (decisión 7); sin lead, quien llamó y su cadena de supervisión.';
comment on function private.llamada_celular_atencion_efectiva(uuid,text,text,uuid) is
  'Atención que se muestra, recalculada al leer (decisión 1): «requiere resultado» solo si así entró y el lead sigue siendo elegible para quien mira; si no, «por revisar». Registrado, descartado y devolución se muestran tal cual.';
comment on function private.llamadas_celular_actor(text[]) is
  'Resuelve auth.uid() y exige un rol CRM activo de la lista; si no, 42501. Lo usan las puertas de llamadas del celular.';
comment on function private.llamada_celular_ingerir(uuid,jsonb) is
  'Núcleo de la ingesta (F3 lo llamará desde su puerta de servicio): evento v1 con claves exactas; asignación vigente con analista activo (42501); canonización con las dos reglas y coincidencia exacta; un lead → identificado (pide resultado si es elegible), varios → ambiguo, ninguno → no se guarda (decisión 3, perilla guardar_sin_identificar); entrante con entrantes apagadas → no se guarda. Idempotente: mismo origen + contenido → repetido; otro contenido → P0409. DATO PERSONAL: el número.';
comment on function private.llamada_celular_asociar(uuid,uuid,uuid) is
  'Asocia una llamada a un lead del ámbito del actor que tenga el número de la llamada (nunca fabrica gestión). Bloquea la llamada, revalida el ámbito; idempotente.';
comment on function private.llamada_celular_enlazar(uuid,uuid,uuid) is
  'Enlaza la llamada con el resultado de llamada que la encuesta registró para el mismo lead, después de la llamada (tolerancia 10 min). Si el enlazado fue deshecho, el enlace se mueve (decisión 4). Revalida el ámbito (decisión 7: si el lead ya no es del actor, 42501). Deja la llamada en «registrado». Idempotente.';
comment on function private.llamada_celular_descartar(uuid,uuid,text,text) is
  'Descarta una llamada con motivo de catálogo (decisión 3; «otro» con detalle). Revalida el ámbito; idempotente con el mismo motivo, 23505 con otro.';
comment on function private.celular_asignar(uuid,text,uuid) is
  'Gerencia asigna un celular (etiqueta) a un analista o supervisor activo. Genera una credencial de 32 bytes, la devuelve UNA vez y guarda solo su sha256. 23505 si la etiqueta ya está asignada.';
comment on function private.celular_cerrar(uuid,uuid,text) is
  'Gerencia cierra una asignación vigente con motivo de catálogo; idempotente con el mismo motivo.';
comment on function private.celular_rotar_credencial(uuid,text) is
  'Gerencia rota la credencial de un celular: cierra la asignación vigente (motivo rotacion) y abre otra al mismo analista, contigua en el tiempo, con credencial nueva devuelta UNA vez.';
comment on function private.llamadas_celular_politica_fijar(uuid,boolean,boolean,integer,integer,integer) is
  'Gerencia ajusta las perillas de la política de llamadas; los parámetros nulos conservan su valor.';
comment on function private.llamadas_celular_pendientes(uuid,integer) is
  'Bandeja: llamadas no finales visibles para el actor, más recientes primero, con la atención efectiva. DATO PERSONAL: número y nombre del lead (el actor ya tiene ámbito sobre ellos).';
comment on function private.llamada_celular_detalle(uuid,uuid) is
  'Detalle de una llamada visible para el actor, con su enlace y efectos_anulados derivado de metadata.deshecho_en del resultado (decisión 4).';
comment on function private.celulares_asignaciones_listar(uuid) is
  'Asignaciones de celulares: gerencia todas, supervisión las de su equipo. Nunca devuelve el hash de la credencial.';
comment on function crm.llamadas_celular_pendientes_fn(integer) is
  'Puerta (DEFINER: las tablas no tienen privilegios para la API) de la bandeja de llamadas del celular. Analista, supervisión y gerencia; límite 1 a 200.';
comment on function crm.llamada_celular_detalle_fn(uuid) is
  'Puerta (DEFINER) del detalle de una llamada del celular. Analista, supervisión y gerencia, con ámbito.';
comment on function crm.asociar_llamada_celular(uuid,uuid) is
  'Puerta (DEFINER) para asociar una llamada a un lead con su número. Analista, supervisión y gerencia, con ámbito.';
comment on function crm.enlazar_llamada_celular(uuid,uuid) is
  'Puerta (DEFINER) para enlazar una llamada con su resultado registrado (actividad_id de registrar_llamada_v4). Analista, supervisión y gerencia, con ámbito.';
comment on function crm.descartar_llamada_celular(uuid,text,text) is
  'Puerta (DEFINER) para descartar una llamada con motivo. Analista, supervisión y gerencia, con ámbito.';
comment on function crm.celulares_asignaciones_fn() is
  'Puerta (DEFINER) de lectura de asignaciones de celulares: gerencia y supervisión (su equipo).';
comment on function crm.asignar_celular(text,uuid) is
  'Puerta (DEFINER) para asignar un celular: solo gerencia. Devuelve la credencial una sola vez. DATO SENSIBLE en la respuesta.';
comment on function crm.cerrar_asignacion_celular(uuid,text) is
  'Puerta (DEFINER) para cerrar una asignación de celular: solo gerencia.';
comment on function crm.rotar_credencial_celular(text) is
  'Puerta (DEFINER) para rotar la credencial de un celular: solo gerencia. Devuelve la nueva una sola vez. DATO SENSIBLE en la respuesta.';
comment on function crm.llamadas_celular_politica_fn() is
  'Puerta (DEFINER) de lectura de la política de llamadas del celular: solo gerencia.';
comment on function crm.fijar_politica_llamadas_celular(boolean,boolean,integer,integer,integer) is
  'Puerta (DEFINER) para ajustar la política de llamadas del celular: solo gerencia; los nulos conservan el valor.';

-- ── 9. Postflight ────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f record;
begin
  for v_f in
    select * from (values
      ('private.celular_credencial_hash(text)', false, null),
      ('private.llamada_celular_formas(text)', false, null),
      ('private.llamada_celular_candidatos(text[])', false, null),
      ('private.llamada_celular_elegible(uuid,uuid)', false, null),
      ('private.llamada_celular_visible(uuid,uuid,uuid)', false, null),
      ('private.llamada_celular_atencion_efectiva(uuid,text,text,uuid)', false, null),
      ('private.llamadas_celular_actor(text[])', false, null),
      ('private.llamada_celular_ingerir(uuid,jsonb)', false, null),
      ('private.llamada_celular_asociar(uuid,uuid,uuid)', false, null),
      ('private.llamada_celular_enlazar(uuid,uuid,uuid)', false, null),
      ('private.llamada_celular_descartar(uuid,uuid,text,text)', false, null),
      ('private.celular_asignar(uuid,text,uuid)', false, null),
      ('private.celular_cerrar(uuid,uuid,text)', false, null),
      ('private.celular_rotar_credencial(uuid,text)', false, null),
      ('private.llamadas_celular_politica_fijar(uuid,boolean,boolean,integer,integer,integer)', false, null),
      ('private.llamadas_celular_pendientes(uuid,integer)', false, null),
      ('private.llamada_celular_detalle(uuid,uuid)', false, null),
      ('private.celulares_asignaciones_listar(uuid)', false, null),
      ('crm.llamadas_celular_pendientes_fn(integer)', true, 'authenticated'),
      ('crm.llamada_celular_detalle_fn(uuid)', true, 'authenticated'),
      ('crm.asociar_llamada_celular(uuid,uuid)', true, 'authenticated'),
      ('crm.enlazar_llamada_celular(uuid,uuid)', true, 'authenticated'),
      ('crm.descartar_llamada_celular(uuid,text,text)', true, 'authenticated'),
      ('crm.celulares_asignaciones_fn()', true, 'authenticated'),
      ('crm.asignar_celular(text,uuid)', true, 'authenticated'),
      ('crm.cerrar_asignacion_celular(uuid,text)', true, 'authenticated'),
      ('crm.rotar_credencial_celular(text)', true, 'authenticated'),
      ('crm.llamadas_celular_politica_fn()', true, 'authenticated'),
      ('crm.fijar_politica_llamadas_celular(boolean,boolean,integer,integer,integer)', true, 'authenticated')
    ) as f(firma, definer, rol)
  loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) is distinct from v_f.definer then
      raise exception 'LLAMADAS_NUCLEO: % debería ser %', v_f.firma,
        case when v_f.definer then 'SECURITY DEFINER' else 'SECURITY INVOKER' end;
    end if;
    if exists (
      select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
      where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
        and a.grantee <> p.proowner
        and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid)
    ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
      or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE')) then
      raise exception 'LLAMADAS_NUCLEO: EXECUTE inesperado en %', v_f.firma;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'LLAMADAS_NUCLEO: search_path inesperado en %', v_f.firma;
    end if;
    if pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
      raise exception 'LLAMADAS_NUCLEO: % sin COMMENT', v_f.firma;
    end if;
  end loop;
  -- Las tablas siguen cerradas a la API: el núcleo no abrió ningún privilegio.
  if exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol),
                    (values ('crm.llamadas_celular_politica'), ('crm.celulares_asignaciones'),
                            ('crm.llamadas_celular_eventos'), ('crm.llamadas_celular_enlaces')) t(tabla)
             where pg_catalog.has_table_privilege(r.rol, t.tabla,
                     'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) then
    raise exception 'LLAMADAS_NUCLEO: alguna tabla de llamadas quedó accesible desde la API';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;

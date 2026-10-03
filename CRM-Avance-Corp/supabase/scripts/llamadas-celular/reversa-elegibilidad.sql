-- Reversa de 20261001222431_crm_llamadas_celular_elegibilidad_dueno.sql: devuelve a
-- private.llamada_celular_ingerir el cuerpo de 20261001160219 (F2-c), copiado tal cual, con su
-- COMMENT, y retira el ayudante private.llamada_celular_elegible_dueno.
--
-- Orden de las reversas: esta → ingesta (si está) → núcleo → datos.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/scripts/llamadas-celular/reversa-elegibilidad.sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regprocedure('private.llamada_celular_elegible_dueno(uuid,uuid)') is null then
    raise exception 'REVERSA_ELEGIBILIDAD: la migración 20261001222431 no está aplicada';
  end if;
end;
$precondicion$;

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

revoke all on function private.llamada_celular_ingerir(uuid,jsonb) from public, anon, authenticated, service_role;
comment on function private.llamada_celular_ingerir(uuid,jsonb) is
  'Núcleo de la ingesta (F3 lo llamará desde su puerta de servicio): evento v1 con claves exactas; asignación vigente con analista activo (42501); canonización con las dos reglas y coincidencia exacta; un lead → identificado (pide resultado si es elegible), varios → ambiguo, ninguno → no se guarda (decisión 3, perilla guardar_sin_identificar); entrante con entrantes apagadas → no se guarda. Idempotente: mismo origen + contenido → repetido; otro contenido → P0409. DATO PERSONAL: el número.';

drop function private.llamada_celular_elegible_dueno(uuid,uuid);

do $postcheck$
begin
  if to_regprocedure('private.llamada_celular_elegible_dueno(uuid,uuid)') is not null
     or pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_ingerir(uuid,jsonb)'::regprocedure),
                          'elegible_dueno') > 0 then
    raise exception 'REVERSA_ELEGIBILIDAD: la ingesta no volvió al cuerpo de F2-c';
  end if;
end;
$postcheck$;

notify pgrst, 'reload schema';
commit;

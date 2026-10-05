-- Reversa de 20261005143843_crm_llamadas_celular_correccion.sql (la QUINTA). SOLO antes del primer aviso: sin
-- recepciones ni llamadas (se comprueba bajo candado). Vuelve EXACTAMENTE al estado de las cuatro migraciones: los
-- cuerpos y los COMMENT se copiaron con un guion desde el blob de git de cada migración (nada a mano), y el banco
-- reducido compara la huella del catálogo (tests/llamadas-celular/huella-catalogo.sql) antes de la quinta y después
-- de esta reversa.
-- Después del primer aviso la quinta NO se revierte (reinstalaría las fugas de la revisión del 02/10): se apaga
-- (retirar la Edge, cerrar las asignaciones) y se corrige hacia adelante, conservando los hechos.
--
-- Orden de las reversas: esta → elegibilidad → ingesta → núcleo → datos (las de elegibilidad e ingesta se niegan
-- mientras la quinta siga instalada).
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/scripts/llamadas-celular/reversa-correccion.sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regclass('private.llamadas_celular_recepciones') is null
     or to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)') is null then
    raise exception 'REVERSA_CORRECCION: la migración 20261005143843 no está aplicada';
  end if;
end;
$precondicion$;

lock table crm.llamadas_celular_politica, crm.llamadas_celular_eventos, private.celulares_estado,
           private.llamadas_celular_recepciones in access exclusive mode;

do $sin_avisos$
begin
  if exists (select 1 from private.llamadas_celular_recepciones) or exists (select 1 from crm.llamadas_celular_eventos) then
    raise exception 'REVERSA_CORRECCION: ya hubo avisos (recepciones o llamadas): la quinta no se revierte; se apaga y se corrige hacia adelante';
  end if;
end;
$sin_avisos$;

-- ── 1. Puertas de servicio con los cuerpos de las cuatro; el núcleo nuevo, fuera ─────────────
create or replace function crm.ingerir_llamada_celular_servicio(p_credencial text, p_evento jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_asig uuid := private.celular_por_credencial(p_credencial);
  v_r jsonb;
begin
  if v_asig is null then
    raise exception using errcode = '42501', message = 'No autorizado';
  end if;
  perform private.celular_consumir_envio(v_asig);
  begin
    v_r := private.llamada_celular_ingerir(v_asig, p_evento);
  exception when insufficient_privilege then
    -- Cerrada o dada de baja mientras esperaba el candado: la misma respuesta, sin pistas.
    raise exception using errcode = '42501', message = 'No autorizado';
  end;
  update private.celulares_estado set ultimo_envio_en = pg_catalog.now() where asignacion_id = v_asig;
  -- A la Edge, solo lo que el celular necesita: nunca el lead ni su atención.
  return pg_catalog.jsonb_build_object('evento_id', v_r -> 'evento_id', 'repetido', v_r -> 'repetido',
    'ignorado', v_r -> 'ignorado', 'motivo', v_r -> 'motivo');
end;
$function$;

create or replace function crm.registrar_salud_celular_servicio(p_credencial text, p_latido jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_asig uuid := private.celular_por_credencial(p_credencial);
begin
  if v_asig is null then
    raise exception using errcode = '42501', message = 'No autorizado';
  end if;
  perform private.celular_consumir_envio(v_asig);
  return private.celular_registrar_salud(v_asig, p_latido);
end;
$function$;

drop function private.llamada_celular_ingerir(uuid, jsonb, timestamptz);
drop function private.llamada_celular_candidatos_dueno(uuid, text[], timestamptz);
drop function private.celular_registrar_salud(uuid, jsonb, timestamptz);
drop function private.llamada_celular_fecha(text);
drop function private.celular_consumir_envio(uuid);

-- ── 2. Tablas (antes de recrear funciones: las SQL se validan al crearse) ────────────────────
drop table private.llamadas_celular_recepciones;
drop function private.trg_llamadas_celular_recepciones_candado();
alter table crm.llamadas_celular_politica drop constraint llamadas_celular_politica_entrantes_bloqueadas;
drop trigger trg_audit_llamadas_celular_eventos on crm.llamadas_celular_eventos;
alter table crm.llamadas_celular_eventos
  drop constraint llamadas_celular_eventos_origen_uq,
  drop constraint llamadas_celular_eventos_origen_valido,
  add column hash_payload text not null
    constraint llamadas_celular_eventos_hash_valido check (hash_payload ~ '^[0-9a-f]{64}$'),
  add constraint llamadas_celular_eventos_origen_valido check (evento_origen_id ~ '^[A-Za-z0-9._:+-]{4,120}$'),
  add constraint llamadas_celular_eventos_origen_unico unique (asignacion_id, evento_origen_id);
create trigger trg_audit_llamadas_celular_eventos
  after insert or update or delete on crm.llamadas_celular_eventos
  for each row execute function private.log_audit_sin_secretos('numero_canonico', 'hash_payload');
alter table private.celulares_estado add column ultimo_envio_en timestamptz;

-- ── 3. Núcleo y lecturas: los cuerpos de las cuatro ──────────────────────────────────────────
create or replace function private.celular_por_credencial(p_credencial text)
returns uuid
language sql
stable
set search_path = ''
as $function$
  select a.id
  from crm.celulares_asignaciones a
  where a.credencial_hash = private.celular_credencial_hash(p_credencial)
    and a.vigente_hasta is null
    and coalesce(private.rol_crm(a.analista_id), '') in ('vendedor', 'supervisor')
$function$;

create or replace function private.celular_consumir_envio(p_asignacion_id uuid)
returns void
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_pol crm.llamadas_celular_politica%rowtype;
  v_est private.celulares_estado%rowtype;
  v_ahora timestamptz := pg_catalog.now();
  v_minuto timestamptz := pg_catalog.date_trunc('minute', pg_catalog.now());
  v_dia date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_min integer;
  v_dia_n integer;
begin
  select * into v_pol from crm.llamadas_celular_politica p where p.singleton;
  insert into private.celulares_estado (asignacion_id) values (p_asignacion_id)
  on conflict (asignacion_id) do nothing;
  select * into v_est from private.celulares_estado s where s.asignacion_id = p_asignacion_id for update;
  -- Ventanas fijas: el minuto de reloj y el día de Lima. Si la ventana cambió, se cuenta desde cero.
  v_min := case when v_est.minuto_desde = v_minuto then v_est.envios_minuto else 0 end;
  v_dia_n := case when v_est.dia = v_dia then v_est.envios_dia else 0 end;
  -- Primero el día: si los dos están agotados, la espera que cuenta es la más larga.
  if v_dia_n >= v_pol.limite_envios_dia then
    raise exception using errcode = 'P0429',
      message = 'Este celular llegó a su límite de envíos del día',
      detail = pg_catalog.format('reintentar_en_seg=%s', greatest(1, pg_catalog.ceil(
        extract(epoch from (((v_dia + 1)::timestamp at time zone 'America/Lima') - v_ahora)))::integer));
  end if;
  if v_min >= v_pol.limite_envios_minuto then
    raise exception using errcode = 'P0429',
      message = 'Demasiados envíos de este celular en un minuto',
      detail = pg_catalog.format('reintentar_en_seg=%s', greatest(1, pg_catalog.ceil(
        extract(epoch from (v_minuto + interval '1 minute' - v_ahora)))::integer));
  end if;
  update private.celulares_estado
     set minuto_desde = v_minuto, envios_minuto = v_min + 1, dia = v_dia, envios_dia = v_dia_n + 1
   where id = v_est.id;
end;
$function$;

create or replace function private.celular_registrar_salud(p_asignacion_id uuid, p_latido jsonb)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_claves constant text[] := array['v', 'version_macro', 'en_cola', 'ocurrio_en'];
  v_version text;
  v_cola integer;
  v_ocurrio timestamptz;
begin
  if p_latido is null or pg_catalog.jsonb_typeof(p_latido) <> 'object' then
    raise exception using errcode = '22023', message = 'El latido debe ser un objeto JSON';
  end if;
  if exists (select 1 from pg_catalog.jsonb_object_keys(p_latido) k where k <> all(v_claves)) then
    raise exception using errcode = '22023', message = 'El latido trae claves no previstas';
  end if;
  if coalesce(p_latido ->> 'v', '') <> '1' then
    raise exception using errcode = '22023', message = 'Versión de latido no soportada (se espera v = 1)';
  end if;
  v_version := p_latido ->> 'version_macro';
  if v_version is null or v_version !~ '^[A-Za-z0-9._ -]{1,40}$' then
    raise exception using errcode = '22023', message = 'version_macro inválida (1 a 40 caracteres: letras, dígitos, espacio y . _ -)';
  end if;
  begin
    v_cola := (p_latido ->> 'en_cola')::integer;
    v_ocurrio := (p_latido ->> 'ocurrio_en')::timestamptz;
  exception when others then
    raise exception using errcode = '22023', message = 'en_cola u ocurrio_en con formato inválido';
  end;
  if v_cola is null or v_cola not between 0 and 100000 then
    raise exception using errcode = '22023', message = 'en_cola es obligatorio y va de 0 a 100000';
  end if;
  if v_ocurrio is not null and (v_ocurrio < timestamptz '2026-01-01 00:00Z' or v_ocurrio >= timestamptz '2100-01-01 00:00Z') then
    raise exception using errcode = '22023', message = 'ocurrio_en fuera de rango';
  end if;
  update private.celulares_estado
     set ultimo_latido_en = pg_catalog.now(), latido_celular_en = v_ocurrio,
         version_macro = v_version, eventos_en_cola = v_cola
   where asignacion_id = p_asignacion_id;
  if not found then
    -- La puerta cuenta el envío antes (y eso crea la fila): llegar aquí sin estado es un error de orden.
    raise exception using errcode = '55000', message = 'El celular no tiene estado: el envío no se contó antes del latido';
  end if;
  return pg_catalog.jsonb_build_object('registrado', true);
end;
$function$;

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

create or replace function private.llamada_celular_visible(p_actor uuid, p_lead uuid, p_analista uuid)
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

create or replace function private.llamada_celular_asociar(p_actor uuid, p_evento_id uuid, p_lead_id uuid)
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

create or replace function private.llamada_celular_enlazar(p_actor uuid, p_evento_id uuid, p_actividad_id uuid)
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

create or replace function private.llamada_celular_descartar(p_actor uuid, p_evento_id uuid, p_motivo text, p_detalle text)
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

create or replace function private.llamadas_celular_politica_fijar(
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

create or replace function private.caducar_llamadas_celular()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_pol crm.llamadas_celular_politica%rowtype;
  v_n integer := 0;
  v_parcial integer;
begin
  select * into v_pol from crm.llamadas_celular_politica where singleton;
  if not found then
    return 0;
  end if;
  perform pg_catalog.set_config('crm.op_purga_llamadas', 'on', true);

  -- Descartadas con motivo: el motivo y quién lo dio quedan en la auditoría (sin el número).
  delete from crm.llamadas_celular_eventos e
   where e.atencion = 'descartado_con_motivo'
     and e.descartado_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_descartados);
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  -- Ambiguas (varios leads con el mismo número) que nadie resolvió.
  delete from crm.llamadas_celular_eventos e
   where e.identificacion = 'ambiguo' and e.atencion = 'por_revisar'
     and e.recibido_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_sin_resolver);
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  -- Sin identificar (solo existen si la perilla guardar_sin_identificar estuvo encendida).
  delete from crm.llamadas_celular_eventos e
   where e.identificacion = 'sin_identificar' and e.atencion = 'por_revisar'
     and e.recibido_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_sin_identificar);
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  perform pg_catalog.set_config('crm.op_purga_llamadas', 'off', true);
  return v_n;
end;
$function$;

create or replace function private.celulares_salud_listar(p_actor uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'asignacion_id', a.id, 'etiqueta', a.etiqueta, 'analista_id', a.analista_id,
           'analista_nombre', p.nombre_completo, 'vigente_desde', a.vigente_desde,
           'ultimo_envio_en', s.ultimo_envio_en, 'ultimo_latido_en', s.ultimo_latido_en,
           'latido_celular_en', s.latido_celular_en, 'version_macro', s.version_macro,
           'eventos_en_cola', s.eventos_en_cola,
           'envios_hoy', case when s.dia = (pg_catalog.now() at time zone 'America/Lima')::date
                              then s.envios_dia else 0 end)
         order by a.etiqueta), '[]'::jsonb)
  from crm.celulares_asignaciones a
  left join private.celulares_estado s on s.asignacion_id = a.id
  left join public.perfiles p on p.id = a.analista_id
  where a.vigente_hasta is null
    and (private.rol_crm(p_actor) = 'gerencia'
         or (private.rol_crm(p_actor) = 'supervisor'
             and a.analista_id in (select private.vendedor_ids_visibles(p_actor))))
$function$;

create or replace function private.llamadas_celular_pendientes(p_actor uuid, p_limite integer)
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

create or replace function crm.llamadas_celular_pendientes_fn(p_limite integer default 50)
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

create or replace function private.trg_llamadas_celular_eventos_candado()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op = 'DELETE' then
    -- Solo la purga programada (GUC de transacción) o una cascada (el lead se elimina: la
    -- evidencia de su número se va con él) pueden borrar. Un DELETE directo muere aquí.
    if coalesce(pg_catalog.current_setting('crm.op_purga_llamadas', true), 'off') = 'on'
       or pg_catalog.pg_trigger_depth() > 1 then
      return old;
    end if;
    raise exception using errcode = '42501',
      message = 'Una llamada del celular no se borra a mano: la retira la retención programada';
  end if;

  -- El payload es la evidencia: inmutable aunque lo escriba el núcleo.
  if new.id <> old.id or new.asignacion_id <> old.asignacion_id or new.analista_id <> old.analista_id
     or new.evento_origen_id <> old.evento_origen_id or new.hash_payload <> old.hash_payload
     or new.numero_canonico is distinct from old.numero_canonico
     or new.direccion <> old.direccion or new.estado_tecnico <> old.estado_tecnico
     or new.duracion_seg is distinct from old.duracion_seg
     or new.ocurrio_en is distinct from old.ocurrio_en or new.recibido_en <> old.recibido_en
     or new.calidad <> old.calidad or new.creado_en <> old.creado_en then
    raise exception using errcode = '42501',
      message = 'El contenido de una llamada del celular es inmutable; solo cambian su identificación y su atención';
  end if;

  -- Identificación: solo avanza (sin_identificar → ambiguo → identificado). El lead se fija una
  -- vez; se corrige únicamente mientras la llamada esté por atender (antes de registrar o descartar).
  if (case new.identificacion when 'sin_identificar' then 0 when 'ambiguo' then 1 else 2 end)
     < (case old.identificacion when 'sin_identificar' then 0 when 'ambiguo' then 1 else 2 end) then
    raise exception using errcode = '42501',
      message = pg_catalog.format('La identificación de una llamada solo avanza: %s → %s',
                                  old.identificacion, new.identificacion);
  end if;
  if old.lead_id is not null and new.lead_id is distinct from old.lead_id
     and old.atencion not in ('por_revisar', 'requiere_resultado', 'requiere_devolucion') then
    raise exception using errcode = '42501',
      message = 'Una llamada registrada o descartada no cambia de lead';
  end if;

  -- Atención: transiciones permitidas. registrado y descartado_con_motivo son finales.
  if new.atencion <> old.atencion then
    if (old.atencion = 'por_revisar'
          and new.atencion in ('requiere_resultado', 'requiere_devolucion', 'descartado_con_motivo'))
       or (old.atencion in ('requiere_resultado', 'requiere_devolucion')
          and new.atencion in ('registrado', 'descartado_con_motivo', 'por_revisar')) then
      null;
    else
      raise exception using errcode = '42501',
        message = pg_catalog.format('Transición no permitida de la llamada: %s → %s', old.atencion, new.atencion);
    end if;
  end if;
  -- Un descarte sellado no se reescribe (motivo, quién, cuándo).
  if old.atencion = 'descartado_con_motivo'
     and (new.motivo_descarte is distinct from old.motivo_descarte
          or new.motivo_descarte_detalle is distinct from old.motivo_descarte_detalle
          or new.descartado_en is distinct from old.descartado_en) then
    raise exception using errcode = '42501', message = 'El motivo de un descarte no se reescribe';
  end if;

  new.actualizado_en := pg_catalog.now();
  return new;
end;
$function$;

-- ── 4. Permisos de lo recreado ───────────────────────────────────────────────────────────────
do $permisos$
declare
  v_f text;
begin
  foreach v_f in array array[
    'private.celular_consumir_envio(uuid)', 'private.celular_registrar_salud(uuid,jsonb)',
    'private.llamada_celular_ingerir(uuid,jsonb)', 'private.llamadas_celular_pendientes(uuid,integer)'] loop
    execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
  end loop;
  execute 'revoke all on function crm.llamadas_celular_pendientes_fn(integer) from public, anon, authenticated, service_role';
  execute 'grant execute on function crm.llamadas_celular_pendientes_fn(integer) to authenticated';
end;
$permisos$;

-- ── 5. Comentarios de las cuatro ─────────────────────────────────────────────────────────────
comment on table crm.llamadas_celular_eventos is
  'Evidencia de cada llamada hecha desde un celular corporativo (F2). Payload inmutable (celular, número E.164, cuándo según el celular y el servidor, dirección, estado técnico, duración, hash) e identidad estable (asignación + id de origen) para la idempotencia. Aparte, lo que cambia con transiciones vigiladas: identificación, atención, lead, método de asociación y descarte motivado. Visibilidad y gestión siguen al lead (quien hoy lo tiene); analista_id conserva quién marcó. DATO PERSONAL: numero_canonico (enmascarado en la auditoría junto con hash_payload, que lo revelaría por fuerza bruta; retención por crm.llamadas_celular_politica). Sin columna de tenant: CRM de una sola empresa.';
comment on column crm.llamadas_celular_eventos.evento_origen_id is 'Identificador estable que genera el celular para esta llamada; con asignacion_id forma la identidad del evento.';
comment on column crm.llamadas_celular_eventos.hash_payload is 'sha256 en hex del payload canónico: mismo origen + mismo hash → mismo evento; distinto hash → conflicto (núcleo, F2-c).';
comment on column crm.llamadas_celular_politica.entrantes_activas is 'false (decisión 2, propuesta #8): solo salientes en el piloto; una entrante perdida no pasa a requiere_devolucion.';
comment on column crm.llamadas_celular_politica.dias_retencion_sin_resolver is 'Días que vive una llamada ambigua (varios leads con el mismo número) que nadie resolvió (30, decisión 6).';
comment on table private.celulares_estado is
  'Estado técnico de cada celular asignado (F3-a): último envío, último latido (versión de la macro, eventos en cola) y los contadores del límite de envíos (minuto de reloj y día de Lima). Una fila por asignación. Tabla técnica de private, sin acceso para la API y sin auditoría: cambia con cada envío, no guarda datos personales ni secretos, y la evidencia de cada llamada ya vive, auditada, en crm.llamadas_celular_eventos. Sin columna de tenant: CRM de una sola empresa.';
comment on column private.celulares_estado.ultimo_envio_en is 'Cuándo llegó y se confirmó la última llamada de este celular (hora del servidor).';
comment on column private.celulares_estado.ultimo_latido_en is 'Cuándo llegó el último latido (hora del servidor). Un latido solo prueba que el celular habla, no que capture bien.';
comment on column private.celulares_estado.minuto_desde is 'Inicio del minuto de reloj al que corresponde envios_minuto.';
comment on column private.celulares_estado.envios_minuto is 'Envíos confirmados en el minuto minuto_desde.';
comment on column private.celulares_estado.dia is 'Día de Lima al que corresponde envios_dia.';
comment on column private.celulares_estado.envios_dia is 'Envíos confirmados en el día dia.';
comment on function private.trg_llamadas_celular_eventos_candado() is
  'Candado de crm.llamadas_celular_eventos: payload inmutable; identificación que solo avanza; lead fijado una vez (corregible solo por atender); transiciones de atención permitidas y finales; descarte no reescribible; DELETE solo bajo el GUC crm.op_purga_llamadas=on o en cascada. SECURITY DEFINER por coherencia; no lee otras tablas.';
comment on function private.caducar_llamadas_celular() is
  'Retención de llamadas del celular según crm.llamadas_celular_politica: borra descartadas con motivo, ambiguas sin resolver y sin identificar vencidas; fija el GUC crm.op_purga_llamadas para pasar el candado. La invoca pg_cron (crm-llamadas-celular-caducidad) con auth.uid() nulo; la auditoría conserva la fila con el número enmascarado. SECURITY DEFINER: borra sin privilegios de la API.';
comment on function private.llamada_celular_visible(uuid,uuid,uuid) is
  'Quién ve una llamada: gerencia todas; con lead, quien hoy tiene ámbito sobre el lead (decisión 7); sin lead, quien llamó y su cadena de supervisión.';
comment on function private.llamada_celular_asociar(uuid,uuid,uuid) is
  'Asocia una llamada a un lead del ámbito del actor que tenga el número de la llamada (nunca fabrica gestión). Bloquea la llamada, revalida el ámbito; idempotente.';
comment on function private.llamada_celular_enlazar(uuid,uuid,uuid) is
  'Enlaza la llamada con el resultado de llamada que la encuesta registró para el mismo lead, después de la llamada (tolerancia 10 min). Si el enlazado fue deshecho, el enlace se mueve (decisión 4). Revalida el ámbito (decisión 7: si el lead ya no es del actor, 42501). Deja la llamada en «registrado». Idempotente.';
comment on function private.llamada_celular_descartar(uuid,uuid,text,text) is
  'Descarta una llamada con motivo de catálogo (decisión 3; «otro» con detalle). Revalida el ámbito; idempotente con el mismo motivo, 23505 con otro.';
comment on function private.llamadas_celular_politica_fijar(uuid,boolean,boolean,integer,integer,integer) is
  'Gerencia ajusta las perillas de la política de llamadas; los parámetros nulos conservan su valor.';
comment on function private.llamadas_celular_pendientes(uuid,integer) is
  'Bandeja: llamadas no finales visibles para el actor, más recientes primero, con la atención efectiva. DATO PERSONAL: número y nombre del lead (el actor ya tiene ámbito sobre ellos).';
comment on function crm.llamadas_celular_pendientes_fn(integer) is
  'Puerta (DEFINER: las tablas no tienen privilegios para la API) de la bandeja de llamadas del celular. Analista, supervisión y gerencia; límite 1 a 200.';
comment on function crm.fijar_politica_llamadas_celular(boolean,boolean,integer,integer,integer) is
  'Puerta (DEFINER) para ajustar la política de llamadas del celular: solo gerencia; los nulos conservan el valor.';
comment on function private.celular_por_credencial(text) is
  'Resuelve la clave de un celular: la asignación vigente, con analista o supervisor activo, cuyo credencial_hash es el sha256 de la clave; null en cualquier otro caso. DATO SENSIBLE: recibe la clave en claro y no la guarda.';
comment on function private.celular_consumir_envio(uuid) is
  'Límite por celular (F3.2.2, compartido por llamadas y latidos): bloquea la fila de estado, reinicia las ventanas fijas (minuto de reloj, día de Lima) y cuenta el envío; al pasarse, P0429 con DETAIL reintentar_en_seg=N. Se deshace con el envío si este falla.';
comment on function private.celular_registrar_salud(uuid,jsonb) is
  'Latido v1 del celular con claves exactas (version_macro y en_cola obligatorios, ocurrio_en opcional): guarda versión, cola y hora en private.celulares_estado. Un latido no demuestra captura sana.';
comment on function private.celulares_salud_listar(uuid) is
  'Salud de los celulares vigentes: gerencia todos, supervisión los de su equipo. Sin hash de credencial.';
comment on function private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid) is
  'Bandeja paginada de llamadas no finales visibles para el actor, por cursor (recibido_en, evento_id) descendente; filas con la misma forma que private.llamadas_celular_pendientes y la atención efectiva. DATO PERSONAL: número y nombre del lead (el actor ya tiene ámbito sobre ellos).';
comment on function crm.ingerir_llamada_celular_servicio(text,jsonb) is
  'Puerta de SERVICIO (DEFINER, solo service_role: la llama la Edge Function crm-llamadas-ingesta de F3-b) para ingerir la llamada de un celular con su clave. Clave ausente, desconocida, cerrada o de un analista de baja: el mismo 42501 «No autorizado». Cuenta el envío (P0429 al pasarse) y delega en private.llamada_celular_ingerir. Devuelve solo evento_id, repetido, ignorado y motivo. DATO SENSIBLE: recibe la clave; DATO PERSONAL: el número.';
comment on function crm.registrar_salud_celular_servicio(text,jsonb) is
  'Puerta de SERVICIO (DEFINER, solo service_role) para el latido de un celular con su clave: misma autorización uniforme y mismo límite que la ingesta. DATO SENSIBLE: recibe la clave.';
comment on function private.llamada_celular_ingerir(uuid,jsonb) is
  'Núcleo de la ingesta (F3 lo llamará desde su puerta de servicio): evento v1 con claves exactas; asignación vigente con analista activo (42501); canonización con las dos reglas y coincidencia exacta; un lead → identificado (pide resultado si es elegible), varios → ambiguo, ninguno → no se guarda (decisión 3, perilla guardar_sin_identificar); entrante con entrantes apagadas → no se guarda. Idempotente: mismo origen + contenido → repetido; otro contenido → P0409. DATO PERSONAL: el número. Desde 20261001222431 la atención inicial se evalúa como el dueño del celular (private.llamada_celular_elegible_dueno).';

do $postcheck$
begin
  if to_regclass('private.llamadas_celular_recepciones') is not null
     or to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)') is not null
     or to_regprocedure('crm.llamadas_celular_pendientes_fn(integer)') is null
     or pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_ingerir(uuid,jsonb)'::regprocedure),
                          'private.llamada_celular_elegible_dueno(v_asig.analista_id, v_lead)') = 0
     or exists (select 1 from pg_catalog.pg_constraint c
                where c.conrelid = 'crm.llamadas_celular_politica'::regclass
                  and c.conname = 'llamadas_celular_politica_entrantes_bloqueadas') then
    raise exception 'REVERSA_CORRECCION: no se volvió al estado de las cuatro migraciones';
  end if;
end;
$postcheck$;

notify pgrst, 'reload schema';
commit;

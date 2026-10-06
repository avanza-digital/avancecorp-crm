-- REGISTRO en supabase_migrations.schema_migrations de 20261005143843_crm_llamadas_celular_correccion (la QUINTA: corrección de F2 + F3).
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración, en un mensaje aparte (punto 18 de
-- REVISION-2026-10-02.md; guía PUBLICAR-F2-F3.md: cada registrador justo después de su migración). Idempotente; se
-- niega si los objetos no están con su forma o si la versión ya está registrada con otro nombre u otro contenido;
-- relee la fila antes de confirmar. statements = el archivo entero (md5 306d706b4b8020b0a7e585300f233d14, con finales de línea LF:
-- correrlo desde un checkout LF, como la Mac de Miguel; en una copia de Windows con CRLF el md5 no coincide y se
-- niega). La ÚLTIMA sentencia, después del commit, es una fila de veredicto: `db query --linked` no muestra los
-- raise notice (corrección de Miguel al #173; molde: scripts/anexo-cronograma/registrar-20260929151350.sql).
-- En una copia Docker se corre con `psql -f`: `db query --local --file` falla con varias sentencias.
-- Generado el 05/10/2026 desde la migración en LF. Patrón: los registrar-*.sql de esta carpeta.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_llamadas_celular_registro'));
do $chk$
begin
  if (
    to_regclass('private.llamadas_celular_recepciones') is not null
    and to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)') is not null
    and to_regprocedure('private.llamada_celular_candidatos_dueno(uuid,text[],timestamptz)') is not null
    and to_regprocedure('crm.llamadas_celular_pendientes_fn(integer)') is null
    and exists (select 1 from pg_catalog.pg_constraint c
                where c.conrelid = 'crm.llamadas_celular_politica'::regclass
                  and c.conname = 'llamadas_celular_politica_entrantes_bloqueadas')
  ) is not true then
    raise exception 'REGISTRO: la migración 20261005143843 no está aplicada (o no con su forma); aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261005143843' and (coalesce(name, '') <> 'crm_llamadas_celular_correccion' or statements is distinct from array[$mig$-- Llamadas desde el celular · QUINTA MIGRACIÓN: corrección de la revisión de F2 + F3.
-- Plan: docs/plans/llamadas-celular/CORRECCION-PLAN-CORTO.md (v2, PR #179, fusionado por Miguel el 04/10/2026;
-- Jhosep confirmó el 05/10 que esa fusión es el OK, con la N1 según la recomendación). Responde a la revisión
-- de Miguel (REVISION-2026-10-02.md: fallos 1–4 y menores 6–15) y a la ronda 1 de Codex sobre el plan
-- (docs/encargos/2026-10-03-codex-llamadas-celular-correccion-r1-respuesta.md: P2-1 a P2-6, P3-7).
-- No edita las cuatro migraciones de F2 + F3 (20261001145242, 20261001160219, 20261001212258, 20261001222431):
-- las enmienda. El fallo 5 (enlace encuesta ↔ llamada) va en F4-a, con su propia migración, y se publica junto.
--
-- Qué hace:
--   §1 El id, la recepción y el orden de la puerta.
--     · El id de cada llamada tiene una forma fija, C<n>-<10 dígitos>: la etiqueta del celular y los segundos de
--       su reloj, como lo genera la macro al colgar. Su etiqueta tiene que ser la de la asignación de la clave y
--       sus segundos, caer entre hace 30 días y dentro de 1 día (hora del servidor). No puede llevar un teléfono.
--     · private.llamadas_celular_recepciones: una fila por cada llamada aceptada, ANTES de buscar el lead, también
--       si después se ignora. Única por id: el primer envío gana y un reenvío responde lo mismo sin buscar nada.
--       Caduca a los 32 días (30 de ventana + 1 de tolerancia + 1 de margen): después, ese id ya no entra.
--     · crm.llamadas_celular_eventos: evento_origen_id único por id (antes por asignación + id: rotar duplicaba,
--       menor 9) y sin hash_payload (solo servía para el 409, que desaparece).
--     · Orden de la puerta: clave (asignación FOR SHARE, revalidada) → estado FOR UPDATE y recién ahí la hora,
--       una sola vez → cupo (sin política, error explícito) → validación (bloque que atrapa SOLO 22023: un
--       inválido devuelve «invalido» y el cupo gastado queda) → recepción → lead y llamada, si corresponde.
--     · Contrato con la Edge: la base devuelve {resultado: aceptado | invalido, mensaje}. Sin P0409.
--   §2 Qué lead puede ser: activos con el número que sean (a) del ámbito del dueño, evaluado COMO el dueño;
--     (b) sin dueño, en etapa abierta; o (c) descartados reutilizables (la regla de «Nuevo lead»). Uno →
--     identificada; dos o más → ambigua, sin guardar cuántos; ninguno → como un número sin lead.
--     Para verla, el lead tiene que estar activo, también para gerencia (fallo 2).
--   §3 Candados en un solo orden: resultado → lead(s) → llamada → enlace. Descartar, asociar y enlazar
--     revalidan el ámbito después de bloquear; si el lead de la llamada cambió mientras esperaban, 40001.
--     Enlazar rechaza un resultado deshecho (menor 10).
--   §4 Entrantes bloqueadas: un CHECK fija la perilla en falso y la puerta rechaza encenderla. Entrantes y
--     direcciones desconocidas se ignoran.
--   §5 Retención: identificadas sin enlace y ambiguas, 30 días desde recibido_en; descartadas, su plazo; las
--     registradas (con enlace, aunque su resultado se haya deshecho) se conservan; recepciones, 32 días.
--   §6 Salud del celular sin envios_hoy ni ultimo_envio_en (N1): cuentan llamadas personales.
--   §8 Se retira la bandeja duplicada (crm.llamadas_celular_pendientes_fn y su núcleo, decisión 6).
--
-- Decisiones de criterio de Claude (PRIMARY, 05/10/2026), para que Miguel las vea:
--   · private.celulares_estado pierde ultimo_envio_en: la N1 lo saca de la lectura y nada más lo usa; guardarlo
--     sin leerlo conservaría la hora de la última llamada, personal incluida.
--   · dias_retencion_sin_resolver cubre las ambiguas Y las identificadas sin enlace (las dos son «sin resolver»):
--     sin columna nueva ni cambio de firma de crm.fijar_politica_llamadas_celular.
--   · Los 32 días de las recepciones son una constante, no una perilla: dependen de la ventana del id.
--   · La recepción guarda el id y la asignación, sin número ni hash.
--   · Descartar, asociar y enlazar bloquean los leads FOR SHARE: basta contra la reasignación (un UPDATE de
--     crm.leads) y no se estorban entre sí.
--   · La purga devuelve cuántas filas retiró, llamadas y recepciones juntas.
--
-- Excepción single-tenant (estándar de 4 capas, F2.3.3): el CRM es de una sola empresa; no hay columna de tenant.
--
-- Cómo se aplica (guía PUBLICAR-F2-F3.md): las cuatro, cada una con su registrador justo después, y esta al
-- final. Precondición: las tablas de llamadas VACÍAS, comprobado bajo candado; si hay filas, se niega. Barrera:
-- no se despliega la Edge ni se da de alta ningún celular hasta verificar esta migración.
--
-- Reversión: ../scripts/llamadas-celular/reversa-correccion.sql, SOLO antes del primer aviso (sin recepciones
-- ni llamadas): vuelve exactamente al estado de las cuatro. Después del primer aviso no se revierte, porque
-- reinstalaría las fugas: se apaga (retirar la Edge, cerrar las asignaciones) y se corrige hacia adelante.
-- Verificación: npm run test:llamadas:local (oráculo tests/llamadas-celular/oraculo-correccion.sql, reversa con
-- huella del catálogo, mutantes y concurrencia con dos sesiones).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regclass('private.llamadas_celular_recepciones') is not null
     or to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)') is not null then
    raise exception 'LLAMADAS_CORRECCION: los objetos ya existen; no se sobrescriben';
  end if;
  if to_regclass('crm.llamadas_celular_politica') is null or to_regclass('crm.celulares_asignaciones') is null
     or to_regclass('crm.llamadas_celular_eventos') is null or to_regclass('crm.llamadas_celular_enlaces') is null
     or to_regclass('private.celulares_estado') is null
     or to_regprocedure('private.llamada_celular_elegible_dueno(uuid,uuid)') is null
     or to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb)') is null
     or to_regprocedure('crm.ingerir_llamada_celular_servicio(text,jsonb)') is null
     or to_regprocedure('crm.registrar_salud_celular_servicio(text,jsonb)') is null then
    raise exception 'LLAMADAS_CORRECCION: faltan las cuatro migraciones de F2 + F3 (o alguna de sus piezas)';
  end if;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_ingerir(uuid,jsonb)'::regprocedure),
                       'private.llamada_celular_elegible_dueno(v_asig.analista_id, v_lead)') = 0 then
    raise exception 'LLAMADAS_CORRECCION: la ingesta no tiene la forma de 20261001222431';
  end if;
  if to_regclass('crm.enfriamiento_politica') is null
     or (select count(*) from pg_catalog.pg_attribute a
         where a.attrelid = 'crm.leads'::regclass and not a.attisdropped
           and a.attname in ('descartado_en', 'motivo_descarte', 'vendedor_id', 'asignado_supervisor_id')) <> 4
     or to_regprocedure('private.sla_gestion_permitida(uuid,uuid)') is null then
    raise exception 'LLAMADAS_CORRECCION: faltan dependencias (enfriamiento_politica, columnas de descarte de leads o ámbito)';
  end if;
end;
$precondicion$;

-- La comprobación de vacío solo vale bajo candado (Codex, riesgos de r1).
lock table crm.llamadas_celular_politica, crm.celulares_asignaciones, crm.llamadas_celular_eventos,
           crm.llamadas_celular_enlaces, private.celulares_estado in access exclusive mode;

do $vacias$
begin
  if exists (select 1 from crm.celulares_asignaciones) or exists (select 1 from crm.llamadas_celular_eventos)
     or exists (select 1 from crm.llamadas_celular_enlaces) or exists (select 1 from private.celulares_estado) then
    raise exception 'LLAMADAS_CORRECCION: hay filas en las tablas de llamadas; esta migración solo se aplica con las tablas vacías (barrera de «Cómo se aplica»)';
  end if;
end;
$vacias$;

-- ── 1. Recepciones (private, sin auditoría, 32 días) ─────────────────────────────────────────
create table private.llamadas_celular_recepciones (
  id               uuid primary key default gen_random_uuid(),
  evento_origen_id text not null
                   constraint llamadas_celular_recepciones_origen_valido
                   check (evento_origen_id ~ '^C[1-9][0-9]{0,2}-[0-9]{10}$')
                   constraint llamadas_celular_recepciones_origen_uq unique,
  asignacion_id    uuid not null references crm.celulares_asignaciones(id) on delete restrict,
  recibido_en      timestamptz not null,
  creado_en        timestamptz not null default now(),
  actualizado_en   timestamptz not null default now()
);
alter table private.llamadas_celular_recepciones enable row level security;
revoke all on private.llamadas_celular_recepciones from public, anon, authenticated, service_role;
create index llamadas_celular_recepciones_asignacion_idx on private.llamadas_celular_recepciones (asignacion_id);
create index llamadas_celular_recepciones_recibido_idx on private.llamadas_celular_recepciones (recibido_en);

create function private.trg_llamadas_celular_recepciones_candado()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op = 'DELETE' then
    if coalesce(pg_catalog.current_setting('crm.op_purga_llamadas', true), 'off') = 'on' then
      return old;
    end if;
    raise exception using errcode = '42501',
      message = 'Una recepción de llamada no se borra a mano: la retira la retención programada';
  end if;
  raise exception using errcode = '42501', message = 'Una recepción de llamada es inmutable';
end;
$function$;
create trigger trg_llamadas_celular_recepciones_00_candado
  before update or delete on private.llamadas_celular_recepciones
  for each row execute function private.trg_llamadas_celular_recepciones_candado();
create trigger trg_llamadas_celular_recepciones_00_sin_vaciar
  before truncate on private.llamadas_celular_recepciones
  for each statement execute function private.trg_llamadas_celular_sin_vaciar();

-- ── 2. Política: entrantes bloqueadas (fallo 3, decisión 2) ──────────────────────────────────
alter table crm.llamadas_celular_politica
  add constraint llamadas_celular_politica_entrantes_bloqueadas check (not entrantes_activas);

-- ── 3. Eventos: id con forma fija y único por id; sin hash_payload ───────────────────────────
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
     or new.evento_origen_id <> old.evento_origen_id
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

drop trigger trg_audit_llamadas_celular_eventos on crm.llamadas_celular_eventos;
alter table crm.llamadas_celular_eventos
  drop constraint llamadas_celular_eventos_origen_unico,
  drop constraint llamadas_celular_eventos_origen_valido,
  drop column hash_payload,
  add constraint llamadas_celular_eventos_origen_valido check (evento_origen_id ~ '^C[1-9][0-9]{0,2}-[0-9]{10}$'),
  add constraint llamadas_celular_eventos_origen_uq unique (evento_origen_id);
-- Sin hash_payload, solo el número se enmascara en la bitácora. El id ya no puede llevar un teléfono (menor 12).
create trigger trg_audit_llamadas_celular_eventos
  after insert or update or delete on crm.llamadas_celular_eventos
  for each row execute function private.log_audit_sin_secretos('numero_canonico');

-- ── 4. Estado del celular sin ultimo_envio_en (N1) ───────────────────────────────────────────
alter table private.celulares_estado drop column ultimo_envio_en;

-- ── 5. Núcleo (INVOKER, sin EXECUTE para nadie; lo llaman las puertas DEFINER) ───────────────

-- Clave → asignación vigente, bloqueada FOR SHARE y revalidada bajo el candado (menor 6): un cierre o una
-- rotación que gana espera a este envío; uno que llegó antes ya se ve, y la clave deja de valer.
create or replace function private.celular_por_credencial(p_credencial text)
returns uuid
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_asig crm.celulares_asignaciones%rowtype;
begin
  select a.* into v_asig
  from crm.celulares_asignaciones a
  where a.credencial_hash = private.celular_credencial_hash(p_credencial)
    and a.vigente_hasta is null
  for share;
  if not found or v_asig.vigente_hasta is not null
     or coalesce(private.rol_crm(v_asig.analista_id), '') not in ('vendedor', 'supervisor') then
    return null;
  end if;
  return v_asig.id;
end;
$function$;

drop function private.celular_consumir_envio(uuid);
create function private.celular_consumir_envio(p_asignacion_id uuid)
returns timestamptz
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_pol crm.llamadas_celular_politica%rowtype;
  v_est private.celulares_estado%rowtype;
  v_ahora timestamptz;
  v_minuto timestamptz;
  v_dia date;
  v_min integer;
  v_dia_n integer;
begin
  insert into private.celulares_estado (asignacion_id) values (p_asignacion_id)
  on conflict (asignacion_id) do nothing;
  select * into v_est from private.celulares_estado s where s.asignacion_id = p_asignacion_id for update;
  -- La hora se toma UNA vez y recién con el estado bloqueado (Codex P2): de ella salen la ventana, la espera
  -- y las marcas de salud de este envío.
  v_ahora := pg_catalog.clock_timestamp();
  select * into v_pol from crm.llamadas_celular_politica p where p.singleton;
  if not found then
    raise exception using errcode = '55000',
      message = 'Falta la política de llamadas del celular: no se puede contar el envío';
  end if;
  v_minuto := pg_catalog.date_trunc('minute', v_ahora);
  v_dia := (v_ahora at time zone 'America/Lima')::date;
  -- Ventanas fijas (minuto de reloj y día de Lima) que nunca retroceden (menor 7): si la hora quedara detrás
  -- de la ventana guardada, se sigue contando en la guardada.
  if v_est.minuto_desde is not null and v_est.minuto_desde >= v_minuto then
    v_minuto := v_est.minuto_desde;
    v_min := v_est.envios_minuto;
  else
    v_min := 0;
  end if;
  if v_est.dia is not null and v_est.dia >= v_dia then
    v_dia := v_est.dia;
    v_dia_n := v_est.envios_dia;
  else
    v_dia_n := 0;
  end if;
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
  return v_ahora;
end;
$function$;

-- Fecha estricta (menor 15): ISO 8601 con zona; acepta el espacio que usa {datetime} de MacroDroid.
create function private.llamada_celular_fecha(p_texto text)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_t timestamptz;
begin
  if p_texto is null then
    return null;
  end if;
  if p_texto !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?(Z|[+-][0-9]{2}:[0-9]{2})$' then
    raise exception using errcode = '22023',
      message = 'ocurrio_en debe ser una fecha ISO 8601 con zona (p. ej. 2026-10-05 09:30:00-05:00)';
  end if;
  begin
    v_t := p_texto::timestamptz;
  exception when invalid_datetime_format or datetime_field_overflow or invalid_time_zone_displacement_value then
    raise exception using errcode = '22023',
      message = 'ocurrio_en debe ser una fecha ISO 8601 con zona (p. ej. 2026-10-05 09:30:00-05:00)';
  end;
  if v_t < timestamptz '2026-01-01 00:00Z' or v_t >= timestamptz '2100-01-01 00:00Z' then
    raise exception using errcode = '22023', message = 'ocurrio_en fuera de rango';
  end if;
  return v_t;
end;
$function$;

drop function private.celular_registrar_salud(uuid, jsonb);
create function private.celular_registrar_salud(p_asignacion_id uuid, p_latido jsonb, p_ahora timestamptz)
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
  -- Validación: un latido inválido responde «invalido» y el cupo gastado antes queda (Codex P3).
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
      raise exception using errcode = '22023',
        message = 'version_macro inválida (1 a 40 caracteres: letras, dígitos, espacio y . _ -)';
    end if;
    if coalesce(pg_catalog.jsonb_typeof(p_latido -> 'en_cola'), '') <> 'number'
       or (p_latido ->> 'en_cola') !~ '^[0-9]{1,6}$' or (p_latido ->> 'en_cola')::integer > 100000 then
      raise exception using errcode = '22023', message = 'en_cola es obligatorio: un entero de 0 a 100000';
    end if;
    v_cola := (p_latido ->> 'en_cola')::integer;
    v_ocurrio := private.llamada_celular_fecha(p_latido ->> 'ocurrio_en');
  exception when sqlstate '22023' then
    return pg_catalog.jsonb_build_object('resultado', 'invalido', 'mensaje', sqlerrm);
  end;
  update private.celulares_estado
     set ultimo_latido_en = p_ahora, latido_celular_en = v_ocurrio,
         version_macro = v_version, eventos_en_cola = v_cola
   where asignacion_id = p_asignacion_id;
  if not found then
    -- La puerta cuenta el envío antes (y eso crea la fila): llegar aquí sin estado es un error de orden.
    raise exception using errcode = '55000', message = 'El celular no tiene estado: el envío no se contó antes del latido';
  end if;
  return pg_catalog.jsonb_build_object('resultado', 'aceptado');
end;
$function$;

-- §2. Candidatos de una llamada: activos con el número y (a) del ámbito del dueño, evaluado COMO el dueño
-- con el mecanismo de private.llamada_celular_elegible_dueno (no su predicado: los propios terminales o en
-- «no contactar» también se identifican, Codex P5); (b) sin dueño, en etapa abierta (la «bolsa» de
-- private.verificar_disponibilidad_lead_impl); o (c) descartados reutilizables (la misma regla: activo,
-- descartado_en y la espera de crm.enfriamiento_politica cumplida; con 0 días, 24 horas).
create function private.llamada_celular_candidatos_dueno(p_dueno uuid, p_formas text[], p_ahora timestamptz)
returns uuid[]
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_previo text := pg_catalog.current_setting('request.jwt.claim.sub', true);
  v_cand uuid[];
begin
  if p_dueno is null or pg_catalog.cardinality(coalesce(p_formas, '{}'::text[])) = 0 then
    return '{}'::uuid[];
  end if;
  perform pg_catalog.set_config('request.jwt.claim.sub', p_dueno::text, true);
  select coalesce(pg_catalog.array_agg(distinct l.id), '{}'::uuid[]) into v_cand
  from crm.leads l
  left join crm.enfriamiento_politica ep on ep.motivo = l.motivo_descarte
  where l.activo
    and (l.telefono = any(p_formas) or l.telefono_alternativo = any(p_formas))
    and (coalesce(private.sla_gestion_permitida(p_dueno, l.id), false)
         or (l.vendedor_id is null and l.asignado_supervisor_id is null
             and l.etapa not in ('convertido', 'descartado'))
         or (l.etapa = 'descartado' and l.descartado_en is not null
             and l.descartado_en + case when coalesce(ep.dias, 0) > 0
                                        then pg_catalog.make_interval(days => ep.dias)
                                        else interval '24 hours' end <= p_ahora));
  -- La identidad vuelve ANTES de que la ingesta escriba: la bitácora no atribuye la llamada a nadie.
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(v_previo, ''), true);
  return v_cand;
end;
$function$;

drop function private.llamada_celular_ingerir(uuid, jsonb);
create function private.llamada_celular_ingerir(p_asignacion_id uuid, p_evento jsonb, p_ahora timestamptz)
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
  v_origen text;
  v_numero text;
  v_dir text;
  v_estado text;
  v_dur integer;
  v_ocurrio timestamptz;
  v_hora_id timestamptz;
  v_recepcion uuid;
  v_formas text[];
  v_e164 text;
  v_cand uuid[];
  v_lead uuid;
  v_ident text;
  v_aten text;
  v_metodo text;
  v_calidad jsonb := '{}'::jsonb;
  v_aceptado constant jsonb := '{"resultado": "aceptado"}'::jsonb;
begin
  -- La puerta ya bloqueó la asignación FOR SHARE y la revalidó; aquí se relee bajo el mismo candado.
  select * into v_asig from crm.celulares_asignaciones a where a.id = p_asignacion_id for share;
  if not found or v_asig.vigente_hasta is not null
     or coalesce(private.rol_crm(v_asig.analista_id), '') not in ('vendedor', 'supervisor') then
    raise exception using errcode = '42501', message = 'Celular sin asignación vigente o analista inactivo';
  end if;

  -- Validación: todo inválido responde «invalido» y el cupo ya gastado queda (menor 11, Codex P3). El bloque
  -- atrapa SOLO 22023: un error inesperado sigue siendo un error (503, que revierte todo, el cupo incluido).
  begin
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
    if v_origen is null or v_origen !~ '^C[1-9][0-9]{0,2}-[0-9]{10}$' then
      raise exception using errcode = '22023',
        message = 'evento_origen_id inválido: se espera la etiqueta del celular y los segundos de su reloj (p. ej. C1-1790980958)';
    end if;
    if pg_catalog.split_part(v_origen, '-', 1) <> v_asig.etiqueta then
      raise exception using errcode = '22023',
        message = pg_catalog.format('evento_origen_id con la etiqueta de otro celular (esta clave es de %s)', v_asig.etiqueta);
    end if;
    v_hora_id := pg_catalog.to_timestamp(pg_catalog.split_part(v_origen, '-', 2)::bigint);
    if v_hora_id < p_ahora - interval '30 days' or v_hora_id > p_ahora + interval '1 day' then
      raise exception using errcode = '22023',
        message = 'evento_origen_id fuera de la ventana: su hora debe caer entre hace 30 días y mañana (¿hora automática en el celular?)';
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
    if coalesce(pg_catalog.jsonb_typeof(p_evento -> 'duracion_seg'), 'null') <> 'null' then
      if pg_catalog.jsonb_typeof(p_evento -> 'duracion_seg') <> 'number'
         or (p_evento ->> 'duracion_seg') !~ '^[0-9]{1,5}$' or (p_evento ->> 'duracion_seg')::integer > 86400 then
        raise exception using errcode = '22023', message = 'duracion_seg debe ser un entero de 0 a 86400';
      end if;
      v_dur := (p_evento ->> 'duracion_seg')::integer;
    end if;
    v_ocurrio := private.llamada_celular_fecha(p_evento ->> 'ocurrio_en');
  exception when sqlstate '22023' then
    return pg_catalog.jsonb_build_object('resultado', 'invalido', 'mensaje', sqlerrm);
  end;

  -- Recepción ANTES de mirar leads, también si después se ignora (fallo 1). El primer envío gana: un reenvío
  -- del mismo id responde lo mismo sin buscar nada. Si guardar la llamada fallara, la recepción se revierte con
  -- ella: nada lo atrapa (Codex P1).
  insert into private.llamadas_celular_recepciones (evento_origen_id, asignacion_id, recibido_en)
  values (v_origen, v_asig.id, p_ahora)
  on conflict (evento_origen_id) do nothing
  returning id into v_recepcion;
  if v_recepcion is null then
    return v_aceptado;
  end if;

  -- Solo salientes (decisión 2): la entrante y la dirección desconocida se ignoran (Codex P6).
  if v_dir <> 'saliente' then
    return v_aceptado;
  end if;

  select * into v_pol from crm.llamadas_celular_politica where singleton;
  if v_ocurrio is not null and v_ocurrio > p_ahora + interval '5 minutes' then
    v_calidad := v_calidad || '{"reloj": "adelantado"}'::jsonb;
  end if;
  v_formas := private.llamada_celular_formas(v_numero);
  v_e164 := (select c.e164 from private.canonizar_contacto(v_numero) c limit 1);
  if v_e164 is null and v_numero is not null then
    v_calidad := v_calidad || '{"numero": "no_canonizable"}'::jsonb;
  elsif v_numero is null then
    v_calidad := v_calidad || '{"numero": "oculto"}'::jsonb;
  end if;
  v_cand := private.llamada_celular_candidatos_dueno(v_asig.analista_id, v_formas, p_ahora);

  if pg_catalog.cardinality(v_cand) = 1 then
    v_lead := v_cand[1];
    v_ident := 'identificado';
    v_metodo := 'exacto';
    -- Solo un lead del ámbito del dueño puede ser elegible; los de la bolsa y los reutilizables quedan por revisar.
    v_aten := case when private.llamada_celular_elegible_dueno(v_asig.analista_id, v_lead)
                   then 'requiere_resultado' else 'por_revisar' end;
  elsif pg_catalog.cardinality(v_cand) > 1 then
    -- Ambigua, sin guardar cuántos (fallo 4).
    v_ident := 'ambiguo';
    v_aten := 'por_revisar';
  elsif coalesce(v_pol.guardar_sin_identificar, false) then
    v_ident := 'sin_identificar';
    v_aten := 'por_revisar';
  else
    -- Decisión 3: sin candidato, la llamada no pertenece al CRM, aunque el número sea de un lead de otro analista.
    return v_aceptado;
  end if;

  insert into crm.llamadas_celular_eventos
    (asignacion_id, analista_id, evento_origen_id, numero_canonico, direccion, estado_tecnico, duracion_seg,
     ocurrio_en, recibido_en, calidad, identificacion, atencion, lead_id, metodo_asociacion, asociado_en)
  values
    -- Sin forma E.164 se guarda la del trigger de leads (la que encontró el lead), para poder
    -- volver a buscar candidatos al asociar.
    (v_asig.id, v_asig.analista_id, v_origen, coalesce(v_e164, v_formas[1]), v_dir, v_estado, v_dur,
     v_ocurrio, p_ahora, v_calidad, v_ident, v_aten, v_lead, v_metodo, case when v_lead is not null then p_ahora end);
  return v_aceptado;
end;
$function$;

-- Quién ve una llamada: con lead, el lead tiene que estar ACTIVO para todos, gerencia incluida (fallo 2), y
-- además gerencia o quien hoy tiene ámbito sobre él (decisión 7); sin lead, gerencia, quien llamó y su cadena.
create or replace function private.llamada_celular_visible(p_actor uuid, p_lead uuid, p_analista uuid)
returns boolean
language sql
stable
set search_path = ''
as $function$
  select p_actor is not null and case
    when p_lead is not null then
      exists (select 1 from crm.leads l where l.id = p_lead and l.activo)
      and (coalesce(private.rol_crm(p_actor) = 'gerencia', false)
           or coalesce(private.sla_gestion_permitida(p_actor, p_lead), false))
    else
      coalesce(private.rol_crm(p_actor) = 'gerencia', false)
      or p_analista = p_actor
      or p_analista in (select private.vendedor_ids_visibles(p_actor))
  end
$function$;

-- §3. Candados en el orden resultado → lead(s) → llamada → enlace. La llamada se lee primero SIN candado solo
-- para saber qué leads bloquear; después de bloquearla se comprueba que su lead no cambió y se revalida el ámbito.
create or replace function private.llamada_celular_asociar(p_actor uuid, p_evento_id uuid, p_lead_id uuid)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_ev crm.llamadas_celular_eventos%rowtype;
  v_lead_leido uuid;
  v_aten text;
begin
  if p_evento_id is null or p_lead_id is null then
    raise exception using errcode = '22023', message = 'Faltan la llamada o el lead';
  end if;
  select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id;
  if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
    raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
  end if;
  -- El lead anterior y el destino, por id (Codex P10): la autorización depende de los dos.
  perform 1 from crm.leads l where l.id in (v_ev.lead_id, p_lead_id) order by l.id for share;
  v_lead_leido := v_ev.lead_id;
  select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id for update;
  if not found or v_ev.lead_id is distinct from v_lead_leido then
    raise exception using errcode = '40001', message = 'La llamada cambió mientras la asociabas; vuelve a intentarlo';
  end if;
  if not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
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

-- Enlace MANUAL: resultado FOR SHARE (el mismo primer candado que Deshacer, que lo toma FOR UPDATE: no se
-- cruzan) → lead → llamada → enlace. Conserva la regla de los 10 minutos: solo vale para este camino; el enlace
-- exacto por id (F4-a) no la usa (confirmación 3 de Miguel, Codex P2-5).
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
  v_lead_leido uuid;
  v_deshecha boolean;
  v_movido boolean := false;
begin
  if p_evento_id is null or p_actividad_id is null then
    raise exception using errcode = '22023', message = 'Faltan la llamada o el resultado';
  end if;
  -- Decisión 7: con lead, «visible» ES tener hoy ámbito sobre él; quien ya no lo tiene no registra por él.
  select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id;
  if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
    raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
  end if;
  if v_ev.identificacion <> 'identificado' then
    raise exception using errcode = '22023', message = 'Primero asocia la llamada a un lead';
  end if;
  select * into v_act from crm.actividades a where a.id = p_actividad_id for share;
  if not found or v_act.lead_id <> v_ev.lead_id then
    raise exception using errcode = '22023', message = 'El resultado no es del lead de la llamada';
  end if;
  perform 1 from crm.leads l where l.id = v_ev.lead_id for share;
  v_lead_leido := v_ev.lead_id;
  select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id for update;
  if not found or v_ev.lead_id is distinct from v_lead_leido then
    raise exception using errcode = '40001', message = 'La llamada cambió mientras la enlazabas; vuelve a intentarlo';
  end if;
  if not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
    raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
  end if;
  if v_ev.atencion = 'descartado_con_motivo' then
    raise exception using errcode = '22023', message = 'La llamada fue descartada';
  end if;
  if v_act.tipo not in ('llamada_realizada', 'llamada_no_contestada')
     or coalesce(v_act.metadata ->> 'evento', '') <> 'resultado_llamada' then
    raise exception using errcode = '22023', message = 'Solo se enlaza un resultado de llamada registrado en la encuesta';
  end if;
  if v_act.metadata ? 'deshecho_en' then
    raise exception using errcode = '22023', message = 'Ese resultado se deshizo: enlaza el resultado corregido';
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
  v_lead_leido uuid;
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
  select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id;
  if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
    raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
  end if;
  perform 1 from crm.leads l where l.id = v_ev.lead_id for share;
  v_lead_leido := v_ev.lead_id;
  select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id for update;
  if not found or v_ev.lead_id is distinct from v_lead_leido then
    raise exception using errcode = '40001', message = 'La llamada cambió mientras la descartabas; vuelve a intentarlo';
  end if;
  if not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
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
  if p_entrantes_activas then
    raise exception using errcode = '22023',
      message = 'Las llamadas entrantes siguen bloqueadas: llegan con la propuesta #14, como paso propio';
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

-- §5. Retención (decisión 4; Codex P4 y P7). La purga mira el ENLACE, no la atención: una registrada se
-- conserva como historial del lead aunque su resultado se haya deshecho; las de un lead dado de baja quedan
-- ocultas y se conservan como el resto de su historial.
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

  -- Descartadas con motivo: su plazo, desde descartado_en. El motivo y quién lo dio quedan en la auditoría.
  delete from crm.llamadas_celular_eventos e
   where e.atencion = 'descartado_con_motivo'
     and e.descartado_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_descartados);
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  -- Sin resolver: identificadas sin enlace y ambiguas, desde recibido_en. La atención también se mira: si una
  -- encuesta enlaza la llamada mientras la purga espera su candado, la fila vuelve con «registrado» y se queda.
  delete from crm.llamadas_celular_eventos e
   where e.identificacion in ('identificado', 'ambiguo')
     and e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')
     and not exists (select 1 from crm.llamadas_celular_enlaces l where l.evento_id = e.id)
     and e.recibido_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_sin_resolver);
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  -- Sin identificar (solo existen si la perilla guardar_sin_identificar estuvo encendida).
  delete from crm.llamadas_celular_eventos e
   where e.identificacion = 'sin_identificar'
     and e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')
     and not exists (select 1 from crm.llamadas_celular_enlaces l where l.evento_id = e.id)
     and e.recibido_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_sin_identificar);
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  -- Recepciones: 32 días (30 de ventana + 1 de tolerancia + 1 de margen). Pasado ese plazo, su id ya no entra
  -- por la ventana, así que no queda un registro eterno de a qué hora llamaba el analista (Codex P9).
  delete from private.llamadas_celular_recepciones r
   where r.recibido_en < pg_catalog.now() - interval '32 days';
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  perform pg_catalog.set_config('crm.op_purga_llamadas', 'off', true);
  return v_n;
end;
$function$;

-- §6. Salud sin envíos (N1): solo el latido, la versión de la macro y la cola.
create or replace function private.celulares_salud_listar(p_actor uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'asignacion_id', a.id, 'etiqueta', a.etiqueta, 'analista_id', a.analista_id,
           'analista_nombre', p.nombre_completo, 'vigente_desde', a.vigente_desde,
           'ultimo_latido_en', s.ultimo_latido_en, 'latido_celular_en', s.latido_celular_en,
           'version_macro', s.version_macro, 'eventos_en_cola', s.eventos_en_cola)
         order by a.etiqueta), '[]'::jsonb)
  from crm.celulares_asignaciones a
  left join private.celulares_estado s on s.asignacion_id = a.id
  left join public.perfiles p on p.id = a.analista_id
  where a.vigente_hasta is null
    and (private.rol_crm(p_actor) = 'gerencia'
         or (private.rol_crm(p_actor) = 'supervisor'
             and a.analista_id in (select private.vendedor_ids_visibles(p_actor))))
$function$;

-- §8. Bandeja duplicada retirada (decisión 6): la paginada (crm.llamadas_celular_bandeja_fn) es la única.
drop function crm.llamadas_celular_pendientes_fn(integer);
drop function private.llamadas_celular_pendientes(uuid, integer);

-- ── 6. Puertas de servicio con el orden y el contrato nuevos ─────────────────────────────────
create or replace function crm.ingerir_llamada_celular_servicio(p_credencial text, p_evento jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_asig uuid := private.celular_por_credencial(p_credencial);
  v_ahora timestamptz;
  v_r jsonb;
begin
  if v_asig is null then
    raise exception using errcode = '42501', message = 'No autorizado';
  end if;
  v_ahora := private.celular_consumir_envio(v_asig);
  begin
    v_r := private.llamada_celular_ingerir(v_asig, p_evento, v_ahora);
  exception when insufficient_privilege then
    -- La misma respuesta que una clave mala, sin el mensaje del núcleo.
    raise exception using errcode = '42501', message = 'No autorizado';
  end;
  -- A la Edge, solo el resultado: guardada, repetida o ignorada responden igual (#12).
  return pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'resultado', v_r ->> 'resultado', 'mensaje', v_r ->> 'mensaje'));
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
  v_ahora timestamptz;
  v_r jsonb;
begin
  if v_asig is null then
    raise exception using errcode = '42501', message = 'No autorizado';
  end if;
  v_ahora := private.celular_consumir_envio(v_asig);
  v_r := private.celular_registrar_salud(v_asig, p_latido, v_ahora);
  return pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'resultado', v_r ->> 'resultado', 'mensaje', v_r ->> 'mensaje'));
end;
$function$;

-- ── 7. Permisos: el núcleo nuevo sin EXECUTE para nadie (las puertas conservan los suyos) ────
do $permisos$
declare
  v_f text;
begin
  foreach v_f in array array[
    'private.trg_llamadas_celular_recepciones_candado()', 'private.celular_consumir_envio(uuid)',
    'private.llamada_celular_fecha(text)', 'private.celular_registrar_salud(uuid,jsonb,timestamptz)',
    'private.llamada_celular_candidatos_dueno(uuid,text[],timestamptz)',
    'private.llamada_celular_ingerir(uuid,jsonb,timestamptz)'] loop
    execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
  end loop;
end;
$permisos$;

-- ── 8. Comentarios ───────────────────────────────────────────────────────────────────────────
comment on table private.llamadas_celular_recepciones is
  'Una fila por cada llamada del celular ACEPTADA (id válido), registrada antes de buscar el lead, también si después se ignora (fallo 1 de la revisión del 02/10). Única por id: el primer envío gana y un reenvío responde lo mismo sin buscar nada. Caduca a los 32 días (la purga diaria), cuando su id ya no puede volver a entrar por la ventana. Tabla técnica de private, sin acceso para la API y sin auditoría (como private.celulares_estado): guarda el id y la asignación, sin número ni hash; aun así dice a qué hora llamaba el analista, por eso caduca. Sin columna de tenant: CRM de una sola empresa.';
comment on column private.llamadas_celular_recepciones.id is 'Identificador de la recepción.';
comment on column private.llamadas_celular_recepciones.evento_origen_id is 'Id de la llamada tal como lo genera la macro: C<n>-<segundos del reloj del celular>. Único.';
comment on column private.llamadas_celular_recepciones.asignacion_id is 'Asignación cuya clave trajo el aviso (crm.celulares_asignaciones).';
comment on column private.llamadas_celular_recepciones.recibido_en is 'Hora del servidor al aceptarla (la que toma la puerta tras bloquear el estado del celular). De aquí corren los 32 días.';
comment on column private.llamadas_celular_recepciones.creado_en is 'Alta de la fila.';
comment on column private.llamadas_celular_recepciones.actualizado_en is 'Igual a creado_en: la fila es inmutable.';
comment on constraint llamadas_celular_politica_entrantes_bloqueadas on crm.llamadas_celular_politica is
  'Entrantes bloqueadas (fallo 3, decisión 2 de Miguel del 03/10): la #14 llega después, como paso propio, y retira este CHECK.';
comment on column crm.llamadas_celular_politica.entrantes_activas is 'Siempre false: entrantes bloqueadas por el CHECK llamadas_celular_politica_entrantes_bloqueadas y por la puerta (decisión 2 de Miguel, 03/10). La ingesta ignora toda llamada que no sea saliente.';
comment on column crm.llamadas_celular_politica.dias_retencion_sin_resolver is 'Días que vive una llamada sin resolver desde recibido_en: identificada sin enlace (pide resultado o está por revisar) o ambigua (30, decisión 4 de Miguel del 03/10). Las registradas no caducan: son historial del lead.';
comment on column crm.llamadas_celular_eventos.evento_origen_id is 'Id de la llamada generado por la macro al colgar: C<n>-<segundos del reloj del celular>, con la etiqueta de la asignación. Único (rotar la clave ya no duplica). No puede llevar un teléfono. F4 encuentra la llamada por este id completo.';
comment on table crm.llamadas_celular_eventos is
  'Evidencia de cada llamada saliente hecha desde un celular corporativo a un número de lead candidato (F2, corregida en 20261005143843). Payload inmutable (celular, id, número E.164, cuándo según el celular y el servidor, dirección, estado técnico, duración). Aparte, lo que cambia con transiciones vigiladas: identificación, atención, lead, método de asociación y descarte motivado. Visibilidad y gestión siguen al lead (quien hoy lo tiene; el lead tiene que estar activo); analista_id conserva quién marcó. DATO PERSONAL: numero_canonico (enmascarado en la auditoría; retención por crm.llamadas_celular_politica, las registradas se conservan). Sin columna de tenant: CRM de una sola empresa.';
comment on table private.celulares_estado is
  'Estado técnico de cada celular asignado: último latido (versión de la macro, eventos en cola) y los contadores del límite de envíos (minuto de reloj y día de Lima, ventanas que nunca retroceden). Una fila por asignación. Desde 20261005143843 no guarda la hora del último envío y la salud no muestra los contadores (N1): cuentan llamadas personales. Tabla técnica de private, sin acceso para la API y sin auditoría. Sin columna de tenant: CRM de una sola empresa.';
comment on column private.celulares_estado.ultimo_latido_en is 'Cuándo llegó el último latido (hora del servidor tomada por la puerta tras bloquear este estado). Un latido solo prueba que el celular habla, no que capture bien.';
comment on column private.celulares_estado.minuto_desde is 'Inicio del minuto de reloj al que corresponde envios_minuto. Nunca retrocede.';
comment on column private.celulares_estado.dia is 'Día de Lima al que corresponde envios_dia. Nunca retrocede.';
comment on column private.celulares_estado.envios_minuto is 'Envíos contados en el minuto minuto_desde (válidos, repetidos o inválidos: todo gasta cupo). Solo para el límite; la salud no lo muestra.';
comment on column private.celulares_estado.envios_dia is 'Envíos contados en el día dia. Solo para el límite; la salud no lo muestra (N1).';

comment on function private.trg_llamadas_celular_recepciones_candado() is
  'Candado de private.llamadas_celular_recepciones: inmutable; DELETE solo bajo el GUC crm.op_purga_llamadas=on (la purga). SECURITY DEFINER por coherencia con los demás candados; no lee datos.';
comment on function private.trg_llamadas_celular_eventos_candado() is
  'Candado de crm.llamadas_celular_eventos: payload inmutable; identificación que solo avanza; lead fijado una vez (corregible solo por atender); transiciones de atención permitidas y finales; descarte no reescribible; DELETE solo bajo el GUC crm.op_purga_llamadas=on o en cascada. Desde 20261005143843 sin hash_payload. SECURITY DEFINER por coherencia; no lee otras tablas.';
comment on function private.celular_por_credencial(text) is
  'Resuelve la clave de un celular: la asignación vigente cuyo credencial_hash es el sha256 de la clave, BLOQUEADA FOR SHARE y revalidada bajo el candado (vigente y con analista o supervisor activo); null en cualquier otro caso. Un cierre o una rotación concurrente se serializa con el envío (menor 6). DATO SENSIBLE: recibe la clave en claro y no la guarda.';
comment on function private.celular_consumir_envio(uuid) is
  'Límite por celular, compartido por llamadas y latidos: bloquea la fila de estado, toma la hora UNA vez (clock_timestamp, después del candado) y la devuelve; ventanas fijas que nunca retroceden (minuto de reloj, día de Lima); sin política, 55000; al pasarse, P0429 con DETAIL reintentar_en_seg=N (≥ 1). El cupo queda gastado aunque el aviso resulte inválido.';
comment on function private.llamada_celular_fecha(text) is
  'Fecha estricta del celular (menor 15): ISO 8601 con segundos y zona (Z o ±HH:MM), con T o espacio, entre 2026 y 2100; si no, 22023. Null si no vino.';
comment on function private.celular_registrar_salud(uuid,jsonb,timestamptz) is
  'Latido v1 con claves exactas (version_macro y en_cola obligatorios, ocurrio_en opcional y estricto). Inválido → {resultado: invalido, mensaje} sin tocar el estado (el cupo ya gastado queda). Válido → guarda versión, cola y la hora de la puerta. Un latido no demuestra captura sana.';
comment on function private.llamada_celular_candidatos_dueno(uuid,text[],timestamptz) is
  'Candidatos de una llamada (§2 del plan v2): leads activos con el número y (a) del ámbito del dueño del celular, evaluado COMO el dueño (fija request.jwt.claim.sub y lo devuelve antes de escribir); (b) sin dueño en etapa abierta; o (c) descartados reutilizables (regla de «Nuevo lead»: espera de crm.enfriamiento_politica cumplida, 24 h si son 0 días). Sin dueño o sin número, ninguno. DATO PERSONAL: recibe el número.';
comment on function private.llamada_celular_ingerir(uuid,jsonb,timestamptz) is
  'Núcleo de la ingesta (lo llama crm.ingerir_llamada_celular_servicio tras la clave y el cupo, con la hora de la puerta): valida el evento v1 en un bloque que atrapa SOLO 22023 (inválido → {resultado: invalido, mensaje}); id C<n>-<segundos> con la etiqueta de la asignación y dentro de la ventana (30 días atrás, 1 adelante); registra la recepción antes de mirar leads (repetido → aceptado sin buscar nada); solo salientes; candidatos del dueño (uno → identificada, pide resultado si es elegible como el dueño; varios → ambigua sin conteo; ninguno → no se guarda salvo guardar_sin_identificar). Recepción y llamada confirman juntas. Siempre {resultado: aceptado} si es válido. DATO PERSONAL: el número.';
comment on function private.llamada_celular_visible(uuid,uuid,uuid) is
  'Quién ve una llamada: con lead, solo si el lead está activo (para todos, gerencia incluida: fallo 2) y además gerencia o quien hoy tiene ámbito sobre él (decisión 7); sin lead, gerencia, quien llamó y su cadena de supervisión.';
comment on function private.llamada_celular_asociar(uuid,uuid,uuid) is
  'Asocia una llamada a un lead del ámbito del actor que tenga el número de la llamada (nunca fabrica gestión). Candados: el lead anterior y el destino FOR SHARE por id, después la llamada FOR UPDATE; si su lead cambió, 40001; revalida el ámbito bajo los candados. Idempotente.';
comment on function private.llamada_celular_enlazar(uuid,uuid,uuid) is
  'Enlace MANUAL de la llamada con el resultado que la encuesta registró para el mismo lead. Candados: resultado FOR SHARE → lead → llamada → enlace (el orden de Deshacer); si su lead cambió, 40001; revalida el ámbito. Rechaza un resultado deshecho (menor 10) y uno anterior a la llamada (10 min, solo en este camino). Si el enlazado fue deshecho, el enlace se mueve. Deja la llamada en «registrado». Idempotente.';
comment on function private.llamada_celular_descartar(uuid,uuid,text,text) is
  'Descarta una llamada con motivo de catálogo («otro» con detalle). Candados: su lead FOR SHARE, después la llamada FOR UPDATE; si su lead cambió, 40001; revalida el ámbito. Idempotente con el mismo motivo, 23505 con otro.';
comment on function private.llamadas_celular_politica_fijar(uuid,boolean,boolean,integer,integer,integer) is
  'Gerencia ajusta las perillas de la política de llamadas; los parámetros nulos conservan su valor. Encender las entrantes se rechaza con 22023: siguen bloqueadas hasta la #14.';
comment on function private.caducar_llamadas_celular() is
  'Retención de llamadas del celular (decisión 4 de Miguel, 03/10): descartadas por su plazo desde descartado_en; identificadas sin enlace y ambiguas a dias_retencion_sin_resolver desde recibido_en; sin identificar a dias_retencion_sin_identificar; las registradas (con enlace, aunque su resultado se haya deshecho) se conservan; recepciones a los 32 días. Devuelve cuántas filas retiró (llamadas y recepciones). Fija el GUC crm.op_purga_llamadas para pasar los candados. La invoca pg_cron (crm-llamadas-celular-caducidad). SECURITY DEFINER: borra sin privilegios de la API.';
comment on function private.celulares_salud_listar(uuid) is
  'Salud de los celulares vigentes: gerencia todos, supervisión los de su equipo. Solo latido, versión de la macro y cola: sin envíos ni último envío (N1, cuentan llamadas personales). Sin hash de credencial.';
comment on function private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid) is
  'Bandeja paginada (la única desde 20261005143843) de llamadas no finales visibles para el actor, por cursor (recibido_en, evento_id) descendente, con la atención efectiva. DATO PERSONAL: número y nombre del lead (el actor ya tiene ámbito sobre ellos).';
comment on function crm.ingerir_llamada_celular_servicio(text,jsonb) is
  'Puerta de SERVICIO (DEFINER, solo service_role: la llama la Edge crm-llamadas-ingesta). Orden: clave (asignación FOR SHARE, revalidada; si no, el mismo 42501 «No autorizado») → cupo (P0429 con la espera) → núcleo. Devuelve solo {resultado: aceptado | invalido, mensaje}: la Edge responde 202 o 400. Guardada, repetida o ignorada responden igual (#12). DATO SENSIBLE: recibe la clave; DATO PERSONAL: el número.';
comment on function crm.registrar_salud_celular_servicio(text,jsonb) is
  'Puerta de SERVICIO (DEFINER, solo service_role) para el latido de un celular: misma clave revalidada bajo candado y mismo cupo que la ingesta; devuelve {resultado: aceptado | invalido, mensaje} (la Edge responde 200 o 400). DATO SENSIBLE: recibe la clave.';
comment on function crm.fijar_politica_llamadas_celular(boolean,boolean,integer,integer,integer) is
  'Puerta (DEFINER) para ajustar la política de llamadas del celular: solo gerencia; los nulos conservan el valor; encender las entrantes se rechaza (bloqueadas hasta la #14).';

-- ── 9. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f record;
  v_t text := 'private.llamadas_celular_recepciones';
begin
  -- La recepción: RLS, cerrada a la API, sin policies, con sus candados, FK que no desatribuye y comentada.
  if not (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = v_t::regclass) then
    raise exception 'LLAMADAS_CORRECCION: % quedó sin RLS', v_t;
  end if;
  if exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol)
             where pg_catalog.has_table_privilege(r.rol, v_t, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) then
    raise exception 'LLAMADAS_CORRECCION: % quedó accesible desde la API', v_t;
  end if;
  if exists (select 1 from pg_catalog.pg_policy p where p.polrelid = v_t::regclass) then
    raise exception 'LLAMADAS_CORRECCION: % no debe tener policies (todo va por puertas)', v_t;
  end if;
  if (select count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = v_t::regclass and not t.tgisinternal and t.tgenabled in ('O', 'A')
        and t.tgname in ('trg_llamadas_celular_recepciones_00_candado', 'trg_llamadas_celular_recepciones_00_sin_vaciar')) <> 2 then
    raise exception 'LLAMADAS_CORRECCION: % quedó sin sus candados', v_t;
  end if;
  if exists (select 1 from pg_catalog.pg_constraint c
             where c.contype = 'f' and c.conrelid = v_t::regclass and c.confdeltype <> 'r') then
    raise exception 'LLAMADAS_CORRECCION: la FK de % no es RESTRICT', v_t;
  end if;
  if pg_catalog.obj_description(v_t::regclass, 'pg_class') is null
     or exists (select 1 from pg_catalog.pg_attribute a
                where a.attrelid = v_t::regclass and a.attnum > 0 and not a.attisdropped
                  and pg_catalog.col_description(a.attrelid, a.attnum) is null) then
    raise exception 'LLAMADAS_CORRECCION: % tiene la tabla o alguna columna sin COMMENT', v_t;
  end if;

  -- Los eventos: único por id, forma fija, sin hash y con la bitácora enmascarando el número.
  if not exists (select 1 from pg_catalog.pg_constraint c
                 where c.conrelid = 'crm.llamadas_celular_eventos'::regclass and c.contype = 'u'
                   and c.conname = 'llamadas_celular_eventos_origen_uq'
                   and c.conkey = array[(select a.attnum from pg_catalog.pg_attribute a
                                         where a.attrelid = c.conrelid and a.attname = 'evento_origen_id')]::smallint[])
     or exists (select 1 from pg_catalog.pg_constraint c
                where c.conrelid = 'crm.llamadas_celular_eventos'::regclass and c.conname = 'llamadas_celular_eventos_origen_unico') then
    raise exception 'LLAMADAS_CORRECCION: la llamada no quedó única por id';
  end if;
  if exists (select 1 from pg_catalog.pg_attribute a
             where a.attnum > 0 and not a.attisdropped
               and ((a.attrelid = 'crm.llamadas_celular_eventos'::regclass and a.attname = 'hash_payload')
                    or (a.attrelid = 'private.celulares_estado'::regclass and a.attname = 'ultimo_envio_en'))) then
    raise exception 'LLAMADAS_CORRECCION: quedó hash_payload o ultimo_envio_en';
  end if;
  if not exists (select 1 from pg_catalog.pg_trigger t
                 where t.tgrelid = 'crm.llamadas_celular_eventos'::regclass and t.tgname = 'trg_audit_llamadas_celular_eventos'
                   and t.tgenabled in ('O', 'A') and t.tgfoid = 'private.log_audit_sin_secretos()'::regprocedure
                   and t.tgnargs = 1 and pg_catalog.encode(t.tgargs, 'escape') = 'numero_canonico\000')
     or (select count(*) from pg_catalog.pg_trigger t
         where t.tgrelid = 'crm.llamadas_celular_eventos'::regclass and not t.tgisinternal) <> 3
     or exists (select 1 from private.tablas_sin_rastro() s where s.tabla = 'crm.llamadas_celular_eventos') then
    raise exception 'LLAMADAS_CORRECCION: la bitácora de las llamadas no quedó con el número enmascarado';
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint c
                 where c.conrelid = 'crm.llamadas_celular_politica'::regclass
                   and c.conname = 'llamadas_celular_politica_entrantes_bloqueadas' and c.contype = 'c') then
    raise exception 'LLAMADAS_CORRECCION: las entrantes no quedaron bloqueadas';
  end if;

  -- Lo retirado ya no está.
  if to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb)') is not null
     or to_regprocedure('private.celular_registrar_salud(uuid,jsonb)') is not null
     or to_regprocedure('crm.llamadas_celular_pendientes_fn(integer)') is not null
     or to_regprocedure('private.llamadas_celular_pendientes(uuid,integer)') is not null then
    raise exception 'LLAMADAS_CORRECCION: quedó una pieza retirada (ingesta vieja, latido viejo o bandeja duplicada)';
  end if;

  for v_f in
    select * from (values
      ('private.trg_llamadas_celular_recepciones_candado()', true, null),
      ('private.trg_llamadas_celular_eventos_candado()', true, null),
      ('private.caducar_llamadas_celular()', true, null),
      ('private.celular_por_credencial(text)', false, null),
      ('private.celular_consumir_envio(uuid)', false, null),
      ('private.llamada_celular_fecha(text)', false, null),
      ('private.celular_registrar_salud(uuid,jsonb,timestamptz)', false, null),
      ('private.llamada_celular_candidatos_dueno(uuid,text[],timestamptz)', false, null),
      ('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)', false, null),
      ('private.llamada_celular_visible(uuid,uuid,uuid)', false, null),
      ('private.llamada_celular_asociar(uuid,uuid,uuid)', false, null),
      ('private.llamada_celular_enlazar(uuid,uuid,uuid)', false, null),
      ('private.llamada_celular_descartar(uuid,uuid,text,text)', false, null),
      ('private.llamadas_celular_politica_fijar(uuid,boolean,boolean,integer,integer,integer)', false, null),
      ('private.celulares_salud_listar(uuid)', false, null),
      ('crm.ingerir_llamada_celular_servicio(text,jsonb)', true, 'service_role'),
      ('crm.registrar_salud_celular_servicio(text,jsonb)', true, 'service_role'),
      ('crm.llamadas_celular_bandeja_fn(integer,timestamptz,uuid)', true, 'authenticated'),
      ('crm.celulares_salud_fn()', true, 'authenticated'),
      ('crm.fijar_politica_llamadas_celular(boolean,boolean,integer,integer,integer)', true, 'authenticated')
    ) as f(firma, definer, rol)
  loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) is distinct from v_f.definer then
      raise exception 'LLAMADAS_CORRECCION: % debería ser %', v_f.firma,
        case when v_f.definer then 'SECURITY DEFINER' else 'SECURITY INVOKER' end;
    end if;
    if exists (
      select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
      where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
        and a.grantee <> p.proowner
        and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid)
    ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
      or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE')) then
      raise exception 'LLAMADAS_CORRECCION: EXECUTE inesperado en %', v_f.firma;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'LLAMADAS_CORRECCION: search_path inesperado en %', v_f.firma;
    end if;
    if pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
      raise exception 'LLAMADAS_CORRECCION: % sin COMMENT', v_f.firma;
    end if;
    -- El 409 desapareció de la ingesta (fallo 1): ninguna pieza de llamadas lo lanza.
    if pg_catalog.strpos(pg_catalog.pg_get_functiondef(v_f.firma::regprocedure), 'P0409') > 0 then
      raise exception 'LLAMADAS_CORRECCION: % todavía lanza P0409', v_f.firma;
    end if;
    -- Ningún bloque atrapa cualquier error (Codex P3): un fallo inesperado no se disfraza de «invalido».
    if pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(v_f.firma::regprocedure)), 'when others') > 0 then
      raise exception 'LLAMADAS_CORRECCION: % atrapa cualquier error (WHEN OTHERS)', v_f.firma;
    end if;
  end loop;

  -- Las tablas siguen cerradas a la API.
  if exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol),
                    (values ('crm.llamadas_celular_politica'), ('crm.celulares_asignaciones'),
                            ('crm.llamadas_celular_eventos'), ('crm.llamadas_celular_enlaces'),
                            ('private.celulares_estado')) t(tabla)
             where pg_catalog.has_table_privilege(r.rol, t.tabla,
                     'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) then
    raise exception 'LLAMADAS_CORRECCION: alguna tabla de llamadas quedó accesible desde la API';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
$mig$])) then
    raise exception 'REGISTRO: la versión 20261005143843 ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261005143843', 'crm_llamadas_celular_correccion', array[$mig$-- Llamadas desde el celular · QUINTA MIGRACIÓN: corrección de la revisión de F2 + F3.
-- Plan: docs/plans/llamadas-celular/CORRECCION-PLAN-CORTO.md (v2, PR #179, fusionado por Miguel el 04/10/2026;
-- Jhosep confirmó el 05/10 que esa fusión es el OK, con la N1 según la recomendación). Responde a la revisión
-- de Miguel (REVISION-2026-10-02.md: fallos 1–4 y menores 6–15) y a la ronda 1 de Codex sobre el plan
-- (docs/encargos/2026-10-03-codex-llamadas-celular-correccion-r1-respuesta.md: P2-1 a P2-6, P3-7).
-- No edita las cuatro migraciones de F2 + F3 (20261001145242, 20261001160219, 20261001212258, 20261001222431):
-- las enmienda. El fallo 5 (enlace encuesta ↔ llamada) va en F4-a, con su propia migración, y se publica junto.
--
-- Qué hace:
--   §1 El id, la recepción y el orden de la puerta.
--     · El id de cada llamada tiene una forma fija, C<n>-<10 dígitos>: la etiqueta del celular y los segundos de
--       su reloj, como lo genera la macro al colgar. Su etiqueta tiene que ser la de la asignación de la clave y
--       sus segundos, caer entre hace 30 días y dentro de 1 día (hora del servidor). No puede llevar un teléfono.
--     · private.llamadas_celular_recepciones: una fila por cada llamada aceptada, ANTES de buscar el lead, también
--       si después se ignora. Única por id: el primer envío gana y un reenvío responde lo mismo sin buscar nada.
--       Caduca a los 32 días (30 de ventana + 1 de tolerancia + 1 de margen): después, ese id ya no entra.
--     · crm.llamadas_celular_eventos: evento_origen_id único por id (antes por asignación + id: rotar duplicaba,
--       menor 9) y sin hash_payload (solo servía para el 409, que desaparece).
--     · Orden de la puerta: clave (asignación FOR SHARE, revalidada) → estado FOR UPDATE y recién ahí la hora,
--       una sola vez → cupo (sin política, error explícito) → validación (bloque que atrapa SOLO 22023: un
--       inválido devuelve «invalido» y el cupo gastado queda) → recepción → lead y llamada, si corresponde.
--     · Contrato con la Edge: la base devuelve {resultado: aceptado | invalido, mensaje}. Sin P0409.
--   §2 Qué lead puede ser: activos con el número que sean (a) del ámbito del dueño, evaluado COMO el dueño;
--     (b) sin dueño, en etapa abierta; o (c) descartados reutilizables (la regla de «Nuevo lead»). Uno →
--     identificada; dos o más → ambigua, sin guardar cuántos; ninguno → como un número sin lead.
--     Para verla, el lead tiene que estar activo, también para gerencia (fallo 2).
--   §3 Candados en un solo orden: resultado → lead(s) → llamada → enlace. Descartar, asociar y enlazar
--     revalidan el ámbito después de bloquear; si el lead de la llamada cambió mientras esperaban, 40001.
--     Enlazar rechaza un resultado deshecho (menor 10).
--   §4 Entrantes bloqueadas: un CHECK fija la perilla en falso y la puerta rechaza encenderla. Entrantes y
--     direcciones desconocidas se ignoran.
--   §5 Retención: identificadas sin enlace y ambiguas, 30 días desde recibido_en; descartadas, su plazo; las
--     registradas (con enlace, aunque su resultado se haya deshecho) se conservan; recepciones, 32 días.
--   §6 Salud del celular sin envios_hoy ni ultimo_envio_en (N1): cuentan llamadas personales.
--   §8 Se retira la bandeja duplicada (crm.llamadas_celular_pendientes_fn y su núcleo, decisión 6).
--
-- Decisiones de criterio de Claude (PRIMARY, 05/10/2026), para que Miguel las vea:
--   · private.celulares_estado pierde ultimo_envio_en: la N1 lo saca de la lectura y nada más lo usa; guardarlo
--     sin leerlo conservaría la hora de la última llamada, personal incluida.
--   · dias_retencion_sin_resolver cubre las ambiguas Y las identificadas sin enlace (las dos son «sin resolver»):
--     sin columna nueva ni cambio de firma de crm.fijar_politica_llamadas_celular.
--   · Los 32 días de las recepciones son una constante, no una perilla: dependen de la ventana del id.
--   · La recepción guarda el id y la asignación, sin número ni hash.
--   · Descartar, asociar y enlazar bloquean los leads FOR SHARE: basta contra la reasignación (un UPDATE de
--     crm.leads) y no se estorban entre sí.
--   · La purga devuelve cuántas filas retiró, llamadas y recepciones juntas.
--
-- Excepción single-tenant (estándar de 4 capas, F2.3.3): el CRM es de una sola empresa; no hay columna de tenant.
--
-- Cómo se aplica (guía PUBLICAR-F2-F3.md): las cuatro, cada una con su registrador justo después, y esta al
-- final. Precondición: las tablas de llamadas VACÍAS, comprobado bajo candado; si hay filas, se niega. Barrera:
-- no se despliega la Edge ni se da de alta ningún celular hasta verificar esta migración.
--
-- Reversión: ../scripts/llamadas-celular/reversa-correccion.sql, SOLO antes del primer aviso (sin recepciones
-- ni llamadas): vuelve exactamente al estado de las cuatro. Después del primer aviso no se revierte, porque
-- reinstalaría las fugas: se apaga (retirar la Edge, cerrar las asignaciones) y se corrige hacia adelante.
-- Verificación: npm run test:llamadas:local (oráculo tests/llamadas-celular/oraculo-correccion.sql, reversa con
-- huella del catálogo, mutantes y concurrencia con dos sesiones).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regclass('private.llamadas_celular_recepciones') is not null
     or to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)') is not null then
    raise exception 'LLAMADAS_CORRECCION: los objetos ya existen; no se sobrescriben';
  end if;
  if to_regclass('crm.llamadas_celular_politica') is null or to_regclass('crm.celulares_asignaciones') is null
     or to_regclass('crm.llamadas_celular_eventos') is null or to_regclass('crm.llamadas_celular_enlaces') is null
     or to_regclass('private.celulares_estado') is null
     or to_regprocedure('private.llamada_celular_elegible_dueno(uuid,uuid)') is null
     or to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb)') is null
     or to_regprocedure('crm.ingerir_llamada_celular_servicio(text,jsonb)') is null
     or to_regprocedure('crm.registrar_salud_celular_servicio(text,jsonb)') is null then
    raise exception 'LLAMADAS_CORRECCION: faltan las cuatro migraciones de F2 + F3 (o alguna de sus piezas)';
  end if;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_ingerir(uuid,jsonb)'::regprocedure),
                       'private.llamada_celular_elegible_dueno(v_asig.analista_id, v_lead)') = 0 then
    raise exception 'LLAMADAS_CORRECCION: la ingesta no tiene la forma de 20261001222431';
  end if;
  if to_regclass('crm.enfriamiento_politica') is null
     or (select count(*) from pg_catalog.pg_attribute a
         where a.attrelid = 'crm.leads'::regclass and not a.attisdropped
           and a.attname in ('descartado_en', 'motivo_descarte', 'vendedor_id', 'asignado_supervisor_id')) <> 4
     or to_regprocedure('private.sla_gestion_permitida(uuid,uuid)') is null then
    raise exception 'LLAMADAS_CORRECCION: faltan dependencias (enfriamiento_politica, columnas de descarte de leads o ámbito)';
  end if;
end;
$precondicion$;

-- La comprobación de vacío solo vale bajo candado (Codex, riesgos de r1).
lock table crm.llamadas_celular_politica, crm.celulares_asignaciones, crm.llamadas_celular_eventos,
           crm.llamadas_celular_enlaces, private.celulares_estado in access exclusive mode;

do $vacias$
begin
  if exists (select 1 from crm.celulares_asignaciones) or exists (select 1 from crm.llamadas_celular_eventos)
     or exists (select 1 from crm.llamadas_celular_enlaces) or exists (select 1 from private.celulares_estado) then
    raise exception 'LLAMADAS_CORRECCION: hay filas en las tablas de llamadas; esta migración solo se aplica con las tablas vacías (barrera de «Cómo se aplica»)';
  end if;
end;
$vacias$;

-- ── 1. Recepciones (private, sin auditoría, 32 días) ─────────────────────────────────────────
create table private.llamadas_celular_recepciones (
  id               uuid primary key default gen_random_uuid(),
  evento_origen_id text not null
                   constraint llamadas_celular_recepciones_origen_valido
                   check (evento_origen_id ~ '^C[1-9][0-9]{0,2}-[0-9]{10}$')
                   constraint llamadas_celular_recepciones_origen_uq unique,
  asignacion_id    uuid not null references crm.celulares_asignaciones(id) on delete restrict,
  recibido_en      timestamptz not null,
  creado_en        timestamptz not null default now(),
  actualizado_en   timestamptz not null default now()
);
alter table private.llamadas_celular_recepciones enable row level security;
revoke all on private.llamadas_celular_recepciones from public, anon, authenticated, service_role;
create index llamadas_celular_recepciones_asignacion_idx on private.llamadas_celular_recepciones (asignacion_id);
create index llamadas_celular_recepciones_recibido_idx on private.llamadas_celular_recepciones (recibido_en);

create function private.trg_llamadas_celular_recepciones_candado()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op = 'DELETE' then
    if coalesce(pg_catalog.current_setting('crm.op_purga_llamadas', true), 'off') = 'on' then
      return old;
    end if;
    raise exception using errcode = '42501',
      message = 'Una recepción de llamada no se borra a mano: la retira la retención programada';
  end if;
  raise exception using errcode = '42501', message = 'Una recepción de llamada es inmutable';
end;
$function$;
create trigger trg_llamadas_celular_recepciones_00_candado
  before update or delete on private.llamadas_celular_recepciones
  for each row execute function private.trg_llamadas_celular_recepciones_candado();
create trigger trg_llamadas_celular_recepciones_00_sin_vaciar
  before truncate on private.llamadas_celular_recepciones
  for each statement execute function private.trg_llamadas_celular_sin_vaciar();

-- ── 2. Política: entrantes bloqueadas (fallo 3, decisión 2) ──────────────────────────────────
alter table crm.llamadas_celular_politica
  add constraint llamadas_celular_politica_entrantes_bloqueadas check (not entrantes_activas);

-- ── 3. Eventos: id con forma fija y único por id; sin hash_payload ───────────────────────────
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
     or new.evento_origen_id <> old.evento_origen_id
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

drop trigger trg_audit_llamadas_celular_eventos on crm.llamadas_celular_eventos;
alter table crm.llamadas_celular_eventos
  drop constraint llamadas_celular_eventos_origen_unico,
  drop constraint llamadas_celular_eventos_origen_valido,
  drop column hash_payload,
  add constraint llamadas_celular_eventos_origen_valido check (evento_origen_id ~ '^C[1-9][0-9]{0,2}-[0-9]{10}$'),
  add constraint llamadas_celular_eventos_origen_uq unique (evento_origen_id);
-- Sin hash_payload, solo el número se enmascara en la bitácora. El id ya no puede llevar un teléfono (menor 12).
create trigger trg_audit_llamadas_celular_eventos
  after insert or update or delete on crm.llamadas_celular_eventos
  for each row execute function private.log_audit_sin_secretos('numero_canonico');

-- ── 4. Estado del celular sin ultimo_envio_en (N1) ───────────────────────────────────────────
alter table private.celulares_estado drop column ultimo_envio_en;

-- ── 5. Núcleo (INVOKER, sin EXECUTE para nadie; lo llaman las puertas DEFINER) ───────────────

-- Clave → asignación vigente, bloqueada FOR SHARE y revalidada bajo el candado (menor 6): un cierre o una
-- rotación que gana espera a este envío; uno que llegó antes ya se ve, y la clave deja de valer.
create or replace function private.celular_por_credencial(p_credencial text)
returns uuid
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_asig crm.celulares_asignaciones%rowtype;
begin
  select a.* into v_asig
  from crm.celulares_asignaciones a
  where a.credencial_hash = private.celular_credencial_hash(p_credencial)
    and a.vigente_hasta is null
  for share;
  if not found or v_asig.vigente_hasta is not null
     or coalesce(private.rol_crm(v_asig.analista_id), '') not in ('vendedor', 'supervisor') then
    return null;
  end if;
  return v_asig.id;
end;
$function$;

drop function private.celular_consumir_envio(uuid);
create function private.celular_consumir_envio(p_asignacion_id uuid)
returns timestamptz
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_pol crm.llamadas_celular_politica%rowtype;
  v_est private.celulares_estado%rowtype;
  v_ahora timestamptz;
  v_minuto timestamptz;
  v_dia date;
  v_min integer;
  v_dia_n integer;
begin
  insert into private.celulares_estado (asignacion_id) values (p_asignacion_id)
  on conflict (asignacion_id) do nothing;
  select * into v_est from private.celulares_estado s where s.asignacion_id = p_asignacion_id for update;
  -- La hora se toma UNA vez y recién con el estado bloqueado (Codex P2): de ella salen la ventana, la espera
  -- y las marcas de salud de este envío.
  v_ahora := pg_catalog.clock_timestamp();
  select * into v_pol from crm.llamadas_celular_politica p where p.singleton;
  if not found then
    raise exception using errcode = '55000',
      message = 'Falta la política de llamadas del celular: no se puede contar el envío';
  end if;
  v_minuto := pg_catalog.date_trunc('minute', v_ahora);
  v_dia := (v_ahora at time zone 'America/Lima')::date;
  -- Ventanas fijas (minuto de reloj y día de Lima) que nunca retroceden (menor 7): si la hora quedara detrás
  -- de la ventana guardada, se sigue contando en la guardada.
  if v_est.minuto_desde is not null and v_est.minuto_desde >= v_minuto then
    v_minuto := v_est.minuto_desde;
    v_min := v_est.envios_minuto;
  else
    v_min := 0;
  end if;
  if v_est.dia is not null and v_est.dia >= v_dia then
    v_dia := v_est.dia;
    v_dia_n := v_est.envios_dia;
  else
    v_dia_n := 0;
  end if;
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
  return v_ahora;
end;
$function$;

-- Fecha estricta (menor 15): ISO 8601 con zona; acepta el espacio que usa {datetime} de MacroDroid.
create function private.llamada_celular_fecha(p_texto text)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_t timestamptz;
begin
  if p_texto is null then
    return null;
  end if;
  if p_texto !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?(Z|[+-][0-9]{2}:[0-9]{2})$' then
    raise exception using errcode = '22023',
      message = 'ocurrio_en debe ser una fecha ISO 8601 con zona (p. ej. 2026-10-05 09:30:00-05:00)';
  end if;
  begin
    v_t := p_texto::timestamptz;
  exception when invalid_datetime_format or datetime_field_overflow or invalid_time_zone_displacement_value then
    raise exception using errcode = '22023',
      message = 'ocurrio_en debe ser una fecha ISO 8601 con zona (p. ej. 2026-10-05 09:30:00-05:00)';
  end;
  if v_t < timestamptz '2026-01-01 00:00Z' or v_t >= timestamptz '2100-01-01 00:00Z' then
    raise exception using errcode = '22023', message = 'ocurrio_en fuera de rango';
  end if;
  return v_t;
end;
$function$;

drop function private.celular_registrar_salud(uuid, jsonb);
create function private.celular_registrar_salud(p_asignacion_id uuid, p_latido jsonb, p_ahora timestamptz)
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
  -- Validación: un latido inválido responde «invalido» y el cupo gastado antes queda (Codex P3).
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
      raise exception using errcode = '22023',
        message = 'version_macro inválida (1 a 40 caracteres: letras, dígitos, espacio y . _ -)';
    end if;
    if coalesce(pg_catalog.jsonb_typeof(p_latido -> 'en_cola'), '') <> 'number'
       or (p_latido ->> 'en_cola') !~ '^[0-9]{1,6}$' or (p_latido ->> 'en_cola')::integer > 100000 then
      raise exception using errcode = '22023', message = 'en_cola es obligatorio: un entero de 0 a 100000';
    end if;
    v_cola := (p_latido ->> 'en_cola')::integer;
    v_ocurrio := private.llamada_celular_fecha(p_latido ->> 'ocurrio_en');
  exception when sqlstate '22023' then
    return pg_catalog.jsonb_build_object('resultado', 'invalido', 'mensaje', sqlerrm);
  end;
  update private.celulares_estado
     set ultimo_latido_en = p_ahora, latido_celular_en = v_ocurrio,
         version_macro = v_version, eventos_en_cola = v_cola
   where asignacion_id = p_asignacion_id;
  if not found then
    -- La puerta cuenta el envío antes (y eso crea la fila): llegar aquí sin estado es un error de orden.
    raise exception using errcode = '55000', message = 'El celular no tiene estado: el envío no se contó antes del latido';
  end if;
  return pg_catalog.jsonb_build_object('resultado', 'aceptado');
end;
$function$;

-- §2. Candidatos de una llamada: activos con el número y (a) del ámbito del dueño, evaluado COMO el dueño
-- con el mecanismo de private.llamada_celular_elegible_dueno (no su predicado: los propios terminales o en
-- «no contactar» también se identifican, Codex P5); (b) sin dueño, en etapa abierta (la «bolsa» de
-- private.verificar_disponibilidad_lead_impl); o (c) descartados reutilizables (la misma regla: activo,
-- descartado_en y la espera de crm.enfriamiento_politica cumplida; con 0 días, 24 horas).
create function private.llamada_celular_candidatos_dueno(p_dueno uuid, p_formas text[], p_ahora timestamptz)
returns uuid[]
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_previo text := pg_catalog.current_setting('request.jwt.claim.sub', true);
  v_cand uuid[];
begin
  if p_dueno is null or pg_catalog.cardinality(coalesce(p_formas, '{}'::text[])) = 0 then
    return '{}'::uuid[];
  end if;
  perform pg_catalog.set_config('request.jwt.claim.sub', p_dueno::text, true);
  select coalesce(pg_catalog.array_agg(distinct l.id), '{}'::uuid[]) into v_cand
  from crm.leads l
  left join crm.enfriamiento_politica ep on ep.motivo = l.motivo_descarte
  where l.activo
    and (l.telefono = any(p_formas) or l.telefono_alternativo = any(p_formas))
    and (coalesce(private.sla_gestion_permitida(p_dueno, l.id), false)
         or (l.vendedor_id is null and l.asignado_supervisor_id is null
             and l.etapa not in ('convertido', 'descartado'))
         or (l.etapa = 'descartado' and l.descartado_en is not null
             and l.descartado_en + case when coalesce(ep.dias, 0) > 0
                                        then pg_catalog.make_interval(days => ep.dias)
                                        else interval '24 hours' end <= p_ahora));
  -- La identidad vuelve ANTES de que la ingesta escriba: la bitácora no atribuye la llamada a nadie.
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(v_previo, ''), true);
  return v_cand;
end;
$function$;

drop function private.llamada_celular_ingerir(uuid, jsonb);
create function private.llamada_celular_ingerir(p_asignacion_id uuid, p_evento jsonb, p_ahora timestamptz)
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
  v_origen text;
  v_numero text;
  v_dir text;
  v_estado text;
  v_dur integer;
  v_ocurrio timestamptz;
  v_hora_id timestamptz;
  v_recepcion uuid;
  v_formas text[];
  v_e164 text;
  v_cand uuid[];
  v_lead uuid;
  v_ident text;
  v_aten text;
  v_metodo text;
  v_calidad jsonb := '{}'::jsonb;
  v_aceptado constant jsonb := '{"resultado": "aceptado"}'::jsonb;
begin
  -- La puerta ya bloqueó la asignación FOR SHARE y la revalidó; aquí se relee bajo el mismo candado.
  select * into v_asig from crm.celulares_asignaciones a where a.id = p_asignacion_id for share;
  if not found or v_asig.vigente_hasta is not null
     or coalesce(private.rol_crm(v_asig.analista_id), '') not in ('vendedor', 'supervisor') then
    raise exception using errcode = '42501', message = 'Celular sin asignación vigente o analista inactivo';
  end if;

  -- Validación: todo inválido responde «invalido» y el cupo ya gastado queda (menor 11, Codex P3). El bloque
  -- atrapa SOLO 22023: un error inesperado sigue siendo un error (503, que revierte todo, el cupo incluido).
  begin
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
    if v_origen is null or v_origen !~ '^C[1-9][0-9]{0,2}-[0-9]{10}$' then
      raise exception using errcode = '22023',
        message = 'evento_origen_id inválido: se espera la etiqueta del celular y los segundos de su reloj (p. ej. C1-1790980958)';
    end if;
    if pg_catalog.split_part(v_origen, '-', 1) <> v_asig.etiqueta then
      raise exception using errcode = '22023',
        message = pg_catalog.format('evento_origen_id con la etiqueta de otro celular (esta clave es de %s)', v_asig.etiqueta);
    end if;
    v_hora_id := pg_catalog.to_timestamp(pg_catalog.split_part(v_origen, '-', 2)::bigint);
    if v_hora_id < p_ahora - interval '30 days' or v_hora_id > p_ahora + interval '1 day' then
      raise exception using errcode = '22023',
        message = 'evento_origen_id fuera de la ventana: su hora debe caer entre hace 30 días y mañana (¿hora automática en el celular?)';
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
    if coalesce(pg_catalog.jsonb_typeof(p_evento -> 'duracion_seg'), 'null') <> 'null' then
      if pg_catalog.jsonb_typeof(p_evento -> 'duracion_seg') <> 'number'
         or (p_evento ->> 'duracion_seg') !~ '^[0-9]{1,5}$' or (p_evento ->> 'duracion_seg')::integer > 86400 then
        raise exception using errcode = '22023', message = 'duracion_seg debe ser un entero de 0 a 86400';
      end if;
      v_dur := (p_evento ->> 'duracion_seg')::integer;
    end if;
    v_ocurrio := private.llamada_celular_fecha(p_evento ->> 'ocurrio_en');
  exception when sqlstate '22023' then
    return pg_catalog.jsonb_build_object('resultado', 'invalido', 'mensaje', sqlerrm);
  end;

  -- Recepción ANTES de mirar leads, también si después se ignora (fallo 1). El primer envío gana: un reenvío
  -- del mismo id responde lo mismo sin buscar nada. Si guardar la llamada fallara, la recepción se revierte con
  -- ella: nada lo atrapa (Codex P1).
  insert into private.llamadas_celular_recepciones (evento_origen_id, asignacion_id, recibido_en)
  values (v_origen, v_asig.id, p_ahora)
  on conflict (evento_origen_id) do nothing
  returning id into v_recepcion;
  if v_recepcion is null then
    return v_aceptado;
  end if;

  -- Solo salientes (decisión 2): la entrante y la dirección desconocida se ignoran (Codex P6).
  if v_dir <> 'saliente' then
    return v_aceptado;
  end if;

  select * into v_pol from crm.llamadas_celular_politica where singleton;
  if v_ocurrio is not null and v_ocurrio > p_ahora + interval '5 minutes' then
    v_calidad := v_calidad || '{"reloj": "adelantado"}'::jsonb;
  end if;
  v_formas := private.llamada_celular_formas(v_numero);
  v_e164 := (select c.e164 from private.canonizar_contacto(v_numero) c limit 1);
  if v_e164 is null and v_numero is not null then
    v_calidad := v_calidad || '{"numero": "no_canonizable"}'::jsonb;
  elsif v_numero is null then
    v_calidad := v_calidad || '{"numero": "oculto"}'::jsonb;
  end if;
  v_cand := private.llamada_celular_candidatos_dueno(v_asig.analista_id, v_formas, p_ahora);

  if pg_catalog.cardinality(v_cand) = 1 then
    v_lead := v_cand[1];
    v_ident := 'identificado';
    v_metodo := 'exacto';
    -- Solo un lead del ámbito del dueño puede ser elegible; los de la bolsa y los reutilizables quedan por revisar.
    v_aten := case when private.llamada_celular_elegible_dueno(v_asig.analista_id, v_lead)
                   then 'requiere_resultado' else 'por_revisar' end;
  elsif pg_catalog.cardinality(v_cand) > 1 then
    -- Ambigua, sin guardar cuántos (fallo 4).
    v_ident := 'ambiguo';
    v_aten := 'por_revisar';
  elsif coalesce(v_pol.guardar_sin_identificar, false) then
    v_ident := 'sin_identificar';
    v_aten := 'por_revisar';
  else
    -- Decisión 3: sin candidato, la llamada no pertenece al CRM, aunque el número sea de un lead de otro analista.
    return v_aceptado;
  end if;

  insert into crm.llamadas_celular_eventos
    (asignacion_id, analista_id, evento_origen_id, numero_canonico, direccion, estado_tecnico, duracion_seg,
     ocurrio_en, recibido_en, calidad, identificacion, atencion, lead_id, metodo_asociacion, asociado_en)
  values
    -- Sin forma E.164 se guarda la del trigger de leads (la que encontró el lead), para poder
    -- volver a buscar candidatos al asociar.
    (v_asig.id, v_asig.analista_id, v_origen, coalesce(v_e164, v_formas[1]), v_dir, v_estado, v_dur,
     v_ocurrio, p_ahora, v_calidad, v_ident, v_aten, v_lead, v_metodo, case when v_lead is not null then p_ahora end);
  return v_aceptado;
end;
$function$;

-- Quién ve una llamada: con lead, el lead tiene que estar ACTIVO para todos, gerencia incluida (fallo 2), y
-- además gerencia o quien hoy tiene ámbito sobre él (decisión 7); sin lead, gerencia, quien llamó y su cadena.
create or replace function private.llamada_celular_visible(p_actor uuid, p_lead uuid, p_analista uuid)
returns boolean
language sql
stable
set search_path = ''
as $function$
  select p_actor is not null and case
    when p_lead is not null then
      exists (select 1 from crm.leads l where l.id = p_lead and l.activo)
      and (coalesce(private.rol_crm(p_actor) = 'gerencia', false)
           or coalesce(private.sla_gestion_permitida(p_actor, p_lead), false))
    else
      coalesce(private.rol_crm(p_actor) = 'gerencia', false)
      or p_analista = p_actor
      or p_analista in (select private.vendedor_ids_visibles(p_actor))
  end
$function$;

-- §3. Candados en el orden resultado → lead(s) → llamada → enlace. La llamada se lee primero SIN candado solo
-- para saber qué leads bloquear; después de bloquearla se comprueba que su lead no cambió y se revalida el ámbito.
create or replace function private.llamada_celular_asociar(p_actor uuid, p_evento_id uuid, p_lead_id uuid)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_ev crm.llamadas_celular_eventos%rowtype;
  v_lead_leido uuid;
  v_aten text;
begin
  if p_evento_id is null or p_lead_id is null then
    raise exception using errcode = '22023', message = 'Faltan la llamada o el lead';
  end if;
  select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id;
  if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
    raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
  end if;
  -- El lead anterior y el destino, por id (Codex P10): la autorización depende de los dos.
  perform 1 from crm.leads l where l.id in (v_ev.lead_id, p_lead_id) order by l.id for share;
  v_lead_leido := v_ev.lead_id;
  select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id for update;
  if not found or v_ev.lead_id is distinct from v_lead_leido then
    raise exception using errcode = '40001', message = 'La llamada cambió mientras la asociabas; vuelve a intentarlo';
  end if;
  if not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
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

-- Enlace MANUAL: resultado FOR SHARE (el mismo primer candado que Deshacer, que lo toma FOR UPDATE: no se
-- cruzan) → lead → llamada → enlace. Conserva la regla de los 10 minutos: solo vale para este camino; el enlace
-- exacto por id (F4-a) no la usa (confirmación 3 de Miguel, Codex P2-5).
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
  v_lead_leido uuid;
  v_deshecha boolean;
  v_movido boolean := false;
begin
  if p_evento_id is null or p_actividad_id is null then
    raise exception using errcode = '22023', message = 'Faltan la llamada o el resultado';
  end if;
  -- Decisión 7: con lead, «visible» ES tener hoy ámbito sobre él; quien ya no lo tiene no registra por él.
  select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id;
  if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
    raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
  end if;
  if v_ev.identificacion <> 'identificado' then
    raise exception using errcode = '22023', message = 'Primero asocia la llamada a un lead';
  end if;
  select * into v_act from crm.actividades a where a.id = p_actividad_id for share;
  if not found or v_act.lead_id <> v_ev.lead_id then
    raise exception using errcode = '22023', message = 'El resultado no es del lead de la llamada';
  end if;
  perform 1 from crm.leads l where l.id = v_ev.lead_id for share;
  v_lead_leido := v_ev.lead_id;
  select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id for update;
  if not found or v_ev.lead_id is distinct from v_lead_leido then
    raise exception using errcode = '40001', message = 'La llamada cambió mientras la enlazabas; vuelve a intentarlo';
  end if;
  if not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
    raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
  end if;
  if v_ev.atencion = 'descartado_con_motivo' then
    raise exception using errcode = '22023', message = 'La llamada fue descartada';
  end if;
  if v_act.tipo not in ('llamada_realizada', 'llamada_no_contestada')
     or coalesce(v_act.metadata ->> 'evento', '') <> 'resultado_llamada' then
    raise exception using errcode = '22023', message = 'Solo se enlaza un resultado de llamada registrado en la encuesta';
  end if;
  if v_act.metadata ? 'deshecho_en' then
    raise exception using errcode = '22023', message = 'Ese resultado se deshizo: enlaza el resultado corregido';
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
  v_lead_leido uuid;
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
  select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id;
  if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
    raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
  end if;
  perform 1 from crm.leads l where l.id = v_ev.lead_id for share;
  v_lead_leido := v_ev.lead_id;
  select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id for update;
  if not found or v_ev.lead_id is distinct from v_lead_leido then
    raise exception using errcode = '40001', message = 'La llamada cambió mientras la descartabas; vuelve a intentarlo';
  end if;
  if not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
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
  if p_entrantes_activas then
    raise exception using errcode = '22023',
      message = 'Las llamadas entrantes siguen bloqueadas: llegan con la propuesta #14, como paso propio';
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

-- §5. Retención (decisión 4; Codex P4 y P7). La purga mira el ENLACE, no la atención: una registrada se
-- conserva como historial del lead aunque su resultado se haya deshecho; las de un lead dado de baja quedan
-- ocultas y se conservan como el resto de su historial.
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

  -- Descartadas con motivo: su plazo, desde descartado_en. El motivo y quién lo dio quedan en la auditoría.
  delete from crm.llamadas_celular_eventos e
   where e.atencion = 'descartado_con_motivo'
     and e.descartado_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_descartados);
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  -- Sin resolver: identificadas sin enlace y ambiguas, desde recibido_en. La atención también se mira: si una
  -- encuesta enlaza la llamada mientras la purga espera su candado, la fila vuelve con «registrado» y se queda.
  delete from crm.llamadas_celular_eventos e
   where e.identificacion in ('identificado', 'ambiguo')
     and e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')
     and not exists (select 1 from crm.llamadas_celular_enlaces l where l.evento_id = e.id)
     and e.recibido_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_sin_resolver);
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  -- Sin identificar (solo existen si la perilla guardar_sin_identificar estuvo encendida).
  delete from crm.llamadas_celular_eventos e
   where e.identificacion = 'sin_identificar'
     and e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')
     and not exists (select 1 from crm.llamadas_celular_enlaces l where l.evento_id = e.id)
     and e.recibido_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_sin_identificar);
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  -- Recepciones: 32 días (30 de ventana + 1 de tolerancia + 1 de margen). Pasado ese plazo, su id ya no entra
  -- por la ventana, así que no queda un registro eterno de a qué hora llamaba el analista (Codex P9).
  delete from private.llamadas_celular_recepciones r
   where r.recibido_en < pg_catalog.now() - interval '32 days';
  get diagnostics v_parcial = row_count;
  v_n := v_n + v_parcial;

  perform pg_catalog.set_config('crm.op_purga_llamadas', 'off', true);
  return v_n;
end;
$function$;

-- §6. Salud sin envíos (N1): solo el latido, la versión de la macro y la cola.
create or replace function private.celulares_salud_listar(p_actor uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'asignacion_id', a.id, 'etiqueta', a.etiqueta, 'analista_id', a.analista_id,
           'analista_nombre', p.nombre_completo, 'vigente_desde', a.vigente_desde,
           'ultimo_latido_en', s.ultimo_latido_en, 'latido_celular_en', s.latido_celular_en,
           'version_macro', s.version_macro, 'eventos_en_cola', s.eventos_en_cola)
         order by a.etiqueta), '[]'::jsonb)
  from crm.celulares_asignaciones a
  left join private.celulares_estado s on s.asignacion_id = a.id
  left join public.perfiles p on p.id = a.analista_id
  where a.vigente_hasta is null
    and (private.rol_crm(p_actor) = 'gerencia'
         or (private.rol_crm(p_actor) = 'supervisor'
             and a.analista_id in (select private.vendedor_ids_visibles(p_actor))))
$function$;

-- §8. Bandeja duplicada retirada (decisión 6): la paginada (crm.llamadas_celular_bandeja_fn) es la única.
drop function crm.llamadas_celular_pendientes_fn(integer);
drop function private.llamadas_celular_pendientes(uuid, integer);

-- ── 6. Puertas de servicio con el orden y el contrato nuevos ─────────────────────────────────
create or replace function crm.ingerir_llamada_celular_servicio(p_credencial text, p_evento jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_asig uuid := private.celular_por_credencial(p_credencial);
  v_ahora timestamptz;
  v_r jsonb;
begin
  if v_asig is null then
    raise exception using errcode = '42501', message = 'No autorizado';
  end if;
  v_ahora := private.celular_consumir_envio(v_asig);
  begin
    v_r := private.llamada_celular_ingerir(v_asig, p_evento, v_ahora);
  exception when insufficient_privilege then
    -- La misma respuesta que una clave mala, sin el mensaje del núcleo.
    raise exception using errcode = '42501', message = 'No autorizado';
  end;
  -- A la Edge, solo el resultado: guardada, repetida o ignorada responden igual (#12).
  return pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'resultado', v_r ->> 'resultado', 'mensaje', v_r ->> 'mensaje'));
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
  v_ahora timestamptz;
  v_r jsonb;
begin
  if v_asig is null then
    raise exception using errcode = '42501', message = 'No autorizado';
  end if;
  v_ahora := private.celular_consumir_envio(v_asig);
  v_r := private.celular_registrar_salud(v_asig, p_latido, v_ahora);
  return pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'resultado', v_r ->> 'resultado', 'mensaje', v_r ->> 'mensaje'));
end;
$function$;

-- ── 7. Permisos: el núcleo nuevo sin EXECUTE para nadie (las puertas conservan los suyos) ────
do $permisos$
declare
  v_f text;
begin
  foreach v_f in array array[
    'private.trg_llamadas_celular_recepciones_candado()', 'private.celular_consumir_envio(uuid)',
    'private.llamada_celular_fecha(text)', 'private.celular_registrar_salud(uuid,jsonb,timestamptz)',
    'private.llamada_celular_candidatos_dueno(uuid,text[],timestamptz)',
    'private.llamada_celular_ingerir(uuid,jsonb,timestamptz)'] loop
    execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
  end loop;
end;
$permisos$;

-- ── 8. Comentarios ───────────────────────────────────────────────────────────────────────────
comment on table private.llamadas_celular_recepciones is
  'Una fila por cada llamada del celular ACEPTADA (id válido), registrada antes de buscar el lead, también si después se ignora (fallo 1 de la revisión del 02/10). Única por id: el primer envío gana y un reenvío responde lo mismo sin buscar nada. Caduca a los 32 días (la purga diaria), cuando su id ya no puede volver a entrar por la ventana. Tabla técnica de private, sin acceso para la API y sin auditoría (como private.celulares_estado): guarda el id y la asignación, sin número ni hash; aun así dice a qué hora llamaba el analista, por eso caduca. Sin columna de tenant: CRM de una sola empresa.';
comment on column private.llamadas_celular_recepciones.id is 'Identificador de la recepción.';
comment on column private.llamadas_celular_recepciones.evento_origen_id is 'Id de la llamada tal como lo genera la macro: C<n>-<segundos del reloj del celular>. Único.';
comment on column private.llamadas_celular_recepciones.asignacion_id is 'Asignación cuya clave trajo el aviso (crm.celulares_asignaciones).';
comment on column private.llamadas_celular_recepciones.recibido_en is 'Hora del servidor al aceptarla (la que toma la puerta tras bloquear el estado del celular). De aquí corren los 32 días.';
comment on column private.llamadas_celular_recepciones.creado_en is 'Alta de la fila.';
comment on column private.llamadas_celular_recepciones.actualizado_en is 'Igual a creado_en: la fila es inmutable.';
comment on constraint llamadas_celular_politica_entrantes_bloqueadas on crm.llamadas_celular_politica is
  'Entrantes bloqueadas (fallo 3, decisión 2 de Miguel del 03/10): la #14 llega después, como paso propio, y retira este CHECK.';
comment on column crm.llamadas_celular_politica.entrantes_activas is 'Siempre false: entrantes bloqueadas por el CHECK llamadas_celular_politica_entrantes_bloqueadas y por la puerta (decisión 2 de Miguel, 03/10). La ingesta ignora toda llamada que no sea saliente.';
comment on column crm.llamadas_celular_politica.dias_retencion_sin_resolver is 'Días que vive una llamada sin resolver desde recibido_en: identificada sin enlace (pide resultado o está por revisar) o ambigua (30, decisión 4 de Miguel del 03/10). Las registradas no caducan: son historial del lead.';
comment on column crm.llamadas_celular_eventos.evento_origen_id is 'Id de la llamada generado por la macro al colgar: C<n>-<segundos del reloj del celular>, con la etiqueta de la asignación. Único (rotar la clave ya no duplica). No puede llevar un teléfono. F4 encuentra la llamada por este id completo.';
comment on table crm.llamadas_celular_eventos is
  'Evidencia de cada llamada saliente hecha desde un celular corporativo a un número de lead candidato (F2, corregida en 20261005143843). Payload inmutable (celular, id, número E.164, cuándo según el celular y el servidor, dirección, estado técnico, duración). Aparte, lo que cambia con transiciones vigiladas: identificación, atención, lead, método de asociación y descarte motivado. Visibilidad y gestión siguen al lead (quien hoy lo tiene; el lead tiene que estar activo); analista_id conserva quién marcó. DATO PERSONAL: numero_canonico (enmascarado en la auditoría; retención por crm.llamadas_celular_politica, las registradas se conservan). Sin columna de tenant: CRM de una sola empresa.';
comment on table private.celulares_estado is
  'Estado técnico de cada celular asignado: último latido (versión de la macro, eventos en cola) y los contadores del límite de envíos (minuto de reloj y día de Lima, ventanas que nunca retroceden). Una fila por asignación. Desde 20261005143843 no guarda la hora del último envío y la salud no muestra los contadores (N1): cuentan llamadas personales. Tabla técnica de private, sin acceso para la API y sin auditoría. Sin columna de tenant: CRM de una sola empresa.';
comment on column private.celulares_estado.ultimo_latido_en is 'Cuándo llegó el último latido (hora del servidor tomada por la puerta tras bloquear este estado). Un latido solo prueba que el celular habla, no que capture bien.';
comment on column private.celulares_estado.minuto_desde is 'Inicio del minuto de reloj al que corresponde envios_minuto. Nunca retrocede.';
comment on column private.celulares_estado.dia is 'Día de Lima al que corresponde envios_dia. Nunca retrocede.';
comment on column private.celulares_estado.envios_minuto is 'Envíos contados en el minuto minuto_desde (válidos, repetidos o inválidos: todo gasta cupo). Solo para el límite; la salud no lo muestra.';
comment on column private.celulares_estado.envios_dia is 'Envíos contados en el día dia. Solo para el límite; la salud no lo muestra (N1).';

comment on function private.trg_llamadas_celular_recepciones_candado() is
  'Candado de private.llamadas_celular_recepciones: inmutable; DELETE solo bajo el GUC crm.op_purga_llamadas=on (la purga). SECURITY DEFINER por coherencia con los demás candados; no lee datos.';
comment on function private.trg_llamadas_celular_eventos_candado() is
  'Candado de crm.llamadas_celular_eventos: payload inmutable; identificación que solo avanza; lead fijado una vez (corregible solo por atender); transiciones de atención permitidas y finales; descarte no reescribible; DELETE solo bajo el GUC crm.op_purga_llamadas=on o en cascada. Desde 20261005143843 sin hash_payload. SECURITY DEFINER por coherencia; no lee otras tablas.';
comment on function private.celular_por_credencial(text) is
  'Resuelve la clave de un celular: la asignación vigente cuyo credencial_hash es el sha256 de la clave, BLOQUEADA FOR SHARE y revalidada bajo el candado (vigente y con analista o supervisor activo); null en cualquier otro caso. Un cierre o una rotación concurrente se serializa con el envío (menor 6). DATO SENSIBLE: recibe la clave en claro y no la guarda.';
comment on function private.celular_consumir_envio(uuid) is
  'Límite por celular, compartido por llamadas y latidos: bloquea la fila de estado, toma la hora UNA vez (clock_timestamp, después del candado) y la devuelve; ventanas fijas que nunca retroceden (minuto de reloj, día de Lima); sin política, 55000; al pasarse, P0429 con DETAIL reintentar_en_seg=N (≥ 1). El cupo queda gastado aunque el aviso resulte inválido.';
comment on function private.llamada_celular_fecha(text) is
  'Fecha estricta del celular (menor 15): ISO 8601 con segundos y zona (Z o ±HH:MM), con T o espacio, entre 2026 y 2100; si no, 22023. Null si no vino.';
comment on function private.celular_registrar_salud(uuid,jsonb,timestamptz) is
  'Latido v1 con claves exactas (version_macro y en_cola obligatorios, ocurrio_en opcional y estricto). Inválido → {resultado: invalido, mensaje} sin tocar el estado (el cupo ya gastado queda). Válido → guarda versión, cola y la hora de la puerta. Un latido no demuestra captura sana.';
comment on function private.llamada_celular_candidatos_dueno(uuid,text[],timestamptz) is
  'Candidatos de una llamada (§2 del plan v2): leads activos con el número y (a) del ámbito del dueño del celular, evaluado COMO el dueño (fija request.jwt.claim.sub y lo devuelve antes de escribir); (b) sin dueño en etapa abierta; o (c) descartados reutilizables (regla de «Nuevo lead»: espera de crm.enfriamiento_politica cumplida, 24 h si son 0 días). Sin dueño o sin número, ninguno. DATO PERSONAL: recibe el número.';
comment on function private.llamada_celular_ingerir(uuid,jsonb,timestamptz) is
  'Núcleo de la ingesta (lo llama crm.ingerir_llamada_celular_servicio tras la clave y el cupo, con la hora de la puerta): valida el evento v1 en un bloque que atrapa SOLO 22023 (inválido → {resultado: invalido, mensaje}); id C<n>-<segundos> con la etiqueta de la asignación y dentro de la ventana (30 días atrás, 1 adelante); registra la recepción antes de mirar leads (repetido → aceptado sin buscar nada); solo salientes; candidatos del dueño (uno → identificada, pide resultado si es elegible como el dueño; varios → ambigua sin conteo; ninguno → no se guarda salvo guardar_sin_identificar). Recepción y llamada confirman juntas. Siempre {resultado: aceptado} si es válido. DATO PERSONAL: el número.';
comment on function private.llamada_celular_visible(uuid,uuid,uuid) is
  'Quién ve una llamada: con lead, solo si el lead está activo (para todos, gerencia incluida: fallo 2) y además gerencia o quien hoy tiene ámbito sobre él (decisión 7); sin lead, gerencia, quien llamó y su cadena de supervisión.';
comment on function private.llamada_celular_asociar(uuid,uuid,uuid) is
  'Asocia una llamada a un lead del ámbito del actor que tenga el número de la llamada (nunca fabrica gestión). Candados: el lead anterior y el destino FOR SHARE por id, después la llamada FOR UPDATE; si su lead cambió, 40001; revalida el ámbito bajo los candados. Idempotente.';
comment on function private.llamada_celular_enlazar(uuid,uuid,uuid) is
  'Enlace MANUAL de la llamada con el resultado que la encuesta registró para el mismo lead. Candados: resultado FOR SHARE → lead → llamada → enlace (el orden de Deshacer); si su lead cambió, 40001; revalida el ámbito. Rechaza un resultado deshecho (menor 10) y uno anterior a la llamada (10 min, solo en este camino). Si el enlazado fue deshecho, el enlace se mueve. Deja la llamada en «registrado». Idempotente.';
comment on function private.llamada_celular_descartar(uuid,uuid,text,text) is
  'Descarta una llamada con motivo de catálogo («otro» con detalle). Candados: su lead FOR SHARE, después la llamada FOR UPDATE; si su lead cambió, 40001; revalida el ámbito. Idempotente con el mismo motivo, 23505 con otro.';
comment on function private.llamadas_celular_politica_fijar(uuid,boolean,boolean,integer,integer,integer) is
  'Gerencia ajusta las perillas de la política de llamadas; los parámetros nulos conservan su valor. Encender las entrantes se rechaza con 22023: siguen bloqueadas hasta la #14.';
comment on function private.caducar_llamadas_celular() is
  'Retención de llamadas del celular (decisión 4 de Miguel, 03/10): descartadas por su plazo desde descartado_en; identificadas sin enlace y ambiguas a dias_retencion_sin_resolver desde recibido_en; sin identificar a dias_retencion_sin_identificar; las registradas (con enlace, aunque su resultado se haya deshecho) se conservan; recepciones a los 32 días. Devuelve cuántas filas retiró (llamadas y recepciones). Fija el GUC crm.op_purga_llamadas para pasar los candados. La invoca pg_cron (crm-llamadas-celular-caducidad). SECURITY DEFINER: borra sin privilegios de la API.';
comment on function private.celulares_salud_listar(uuid) is
  'Salud de los celulares vigentes: gerencia todos, supervisión los de su equipo. Solo latido, versión de la macro y cola: sin envíos ni último envío (N1, cuentan llamadas personales). Sin hash de credencial.';
comment on function private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid) is
  'Bandeja paginada (la única desde 20261005143843) de llamadas no finales visibles para el actor, por cursor (recibido_en, evento_id) descendente, con la atención efectiva. DATO PERSONAL: número y nombre del lead (el actor ya tiene ámbito sobre ellos).';
comment on function crm.ingerir_llamada_celular_servicio(text,jsonb) is
  'Puerta de SERVICIO (DEFINER, solo service_role: la llama la Edge crm-llamadas-ingesta). Orden: clave (asignación FOR SHARE, revalidada; si no, el mismo 42501 «No autorizado») → cupo (P0429 con la espera) → núcleo. Devuelve solo {resultado: aceptado | invalido, mensaje}: la Edge responde 202 o 400. Guardada, repetida o ignorada responden igual (#12). DATO SENSIBLE: recibe la clave; DATO PERSONAL: el número.';
comment on function crm.registrar_salud_celular_servicio(text,jsonb) is
  'Puerta de SERVICIO (DEFINER, solo service_role) para el latido de un celular: misma clave revalidada bajo candado y mismo cupo que la ingesta; devuelve {resultado: aceptado | invalido, mensaje} (la Edge responde 200 o 400). DATO SENSIBLE: recibe la clave.';
comment on function crm.fijar_politica_llamadas_celular(boolean,boolean,integer,integer,integer) is
  'Puerta (DEFINER) para ajustar la política de llamadas del celular: solo gerencia; los nulos conservan el valor; encender las entrantes se rechaza (bloqueadas hasta la #14).';

-- ── 9. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f record;
  v_t text := 'private.llamadas_celular_recepciones';
begin
  -- La recepción: RLS, cerrada a la API, sin policies, con sus candados, FK que no desatribuye y comentada.
  if not (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = v_t::regclass) then
    raise exception 'LLAMADAS_CORRECCION: % quedó sin RLS', v_t;
  end if;
  if exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol)
             where pg_catalog.has_table_privilege(r.rol, v_t, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) then
    raise exception 'LLAMADAS_CORRECCION: % quedó accesible desde la API', v_t;
  end if;
  if exists (select 1 from pg_catalog.pg_policy p where p.polrelid = v_t::regclass) then
    raise exception 'LLAMADAS_CORRECCION: % no debe tener policies (todo va por puertas)', v_t;
  end if;
  if (select count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = v_t::regclass and not t.tgisinternal and t.tgenabled in ('O', 'A')
        and t.tgname in ('trg_llamadas_celular_recepciones_00_candado', 'trg_llamadas_celular_recepciones_00_sin_vaciar')) <> 2 then
    raise exception 'LLAMADAS_CORRECCION: % quedó sin sus candados', v_t;
  end if;
  if exists (select 1 from pg_catalog.pg_constraint c
             where c.contype = 'f' and c.conrelid = v_t::regclass and c.confdeltype <> 'r') then
    raise exception 'LLAMADAS_CORRECCION: la FK de % no es RESTRICT', v_t;
  end if;
  if pg_catalog.obj_description(v_t::regclass, 'pg_class') is null
     or exists (select 1 from pg_catalog.pg_attribute a
                where a.attrelid = v_t::regclass and a.attnum > 0 and not a.attisdropped
                  and pg_catalog.col_description(a.attrelid, a.attnum) is null) then
    raise exception 'LLAMADAS_CORRECCION: % tiene la tabla o alguna columna sin COMMENT', v_t;
  end if;

  -- Los eventos: único por id, forma fija, sin hash y con la bitácora enmascarando el número.
  if not exists (select 1 from pg_catalog.pg_constraint c
                 where c.conrelid = 'crm.llamadas_celular_eventos'::regclass and c.contype = 'u'
                   and c.conname = 'llamadas_celular_eventos_origen_uq'
                   and c.conkey = array[(select a.attnum from pg_catalog.pg_attribute a
                                         where a.attrelid = c.conrelid and a.attname = 'evento_origen_id')]::smallint[])
     or exists (select 1 from pg_catalog.pg_constraint c
                where c.conrelid = 'crm.llamadas_celular_eventos'::regclass and c.conname = 'llamadas_celular_eventos_origen_unico') then
    raise exception 'LLAMADAS_CORRECCION: la llamada no quedó única por id';
  end if;
  if exists (select 1 from pg_catalog.pg_attribute a
             where a.attnum > 0 and not a.attisdropped
               and ((a.attrelid = 'crm.llamadas_celular_eventos'::regclass and a.attname = 'hash_payload')
                    or (a.attrelid = 'private.celulares_estado'::regclass and a.attname = 'ultimo_envio_en'))) then
    raise exception 'LLAMADAS_CORRECCION: quedó hash_payload o ultimo_envio_en';
  end if;
  if not exists (select 1 from pg_catalog.pg_trigger t
                 where t.tgrelid = 'crm.llamadas_celular_eventos'::regclass and t.tgname = 'trg_audit_llamadas_celular_eventos'
                   and t.tgenabled in ('O', 'A') and t.tgfoid = 'private.log_audit_sin_secretos()'::regprocedure
                   and t.tgnargs = 1 and pg_catalog.encode(t.tgargs, 'escape') = 'numero_canonico\000')
     or (select count(*) from pg_catalog.pg_trigger t
         where t.tgrelid = 'crm.llamadas_celular_eventos'::regclass and not t.tgisinternal) <> 3
     or exists (select 1 from private.tablas_sin_rastro() s where s.tabla = 'crm.llamadas_celular_eventos') then
    raise exception 'LLAMADAS_CORRECCION: la bitácora de las llamadas no quedó con el número enmascarado';
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint c
                 where c.conrelid = 'crm.llamadas_celular_politica'::regclass
                   and c.conname = 'llamadas_celular_politica_entrantes_bloqueadas' and c.contype = 'c') then
    raise exception 'LLAMADAS_CORRECCION: las entrantes no quedaron bloqueadas';
  end if;

  -- Lo retirado ya no está.
  if to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb)') is not null
     or to_regprocedure('private.celular_registrar_salud(uuid,jsonb)') is not null
     or to_regprocedure('crm.llamadas_celular_pendientes_fn(integer)') is not null
     or to_regprocedure('private.llamadas_celular_pendientes(uuid,integer)') is not null then
    raise exception 'LLAMADAS_CORRECCION: quedó una pieza retirada (ingesta vieja, latido viejo o bandeja duplicada)';
  end if;

  for v_f in
    select * from (values
      ('private.trg_llamadas_celular_recepciones_candado()', true, null),
      ('private.trg_llamadas_celular_eventos_candado()', true, null),
      ('private.caducar_llamadas_celular()', true, null),
      ('private.celular_por_credencial(text)', false, null),
      ('private.celular_consumir_envio(uuid)', false, null),
      ('private.llamada_celular_fecha(text)', false, null),
      ('private.celular_registrar_salud(uuid,jsonb,timestamptz)', false, null),
      ('private.llamada_celular_candidatos_dueno(uuid,text[],timestamptz)', false, null),
      ('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)', false, null),
      ('private.llamada_celular_visible(uuid,uuid,uuid)', false, null),
      ('private.llamada_celular_asociar(uuid,uuid,uuid)', false, null),
      ('private.llamada_celular_enlazar(uuid,uuid,uuid)', false, null),
      ('private.llamada_celular_descartar(uuid,uuid,text,text)', false, null),
      ('private.llamadas_celular_politica_fijar(uuid,boolean,boolean,integer,integer,integer)', false, null),
      ('private.celulares_salud_listar(uuid)', false, null),
      ('crm.ingerir_llamada_celular_servicio(text,jsonb)', true, 'service_role'),
      ('crm.registrar_salud_celular_servicio(text,jsonb)', true, 'service_role'),
      ('crm.llamadas_celular_bandeja_fn(integer,timestamptz,uuid)', true, 'authenticated'),
      ('crm.celulares_salud_fn()', true, 'authenticated'),
      ('crm.fijar_politica_llamadas_celular(boolean,boolean,integer,integer,integer)', true, 'authenticated')
    ) as f(firma, definer, rol)
  loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) is distinct from v_f.definer then
      raise exception 'LLAMADAS_CORRECCION: % debería ser %', v_f.firma,
        case when v_f.definer then 'SECURITY DEFINER' else 'SECURITY INVOKER' end;
    end if;
    if exists (
      select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
      where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
        and a.grantee <> p.proowner
        and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid)
    ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
      or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE')) then
      raise exception 'LLAMADAS_CORRECCION: EXECUTE inesperado en %', v_f.firma;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'LLAMADAS_CORRECCION: search_path inesperado en %', v_f.firma;
    end if;
    if pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
      raise exception 'LLAMADAS_CORRECCION: % sin COMMENT', v_f.firma;
    end if;
    -- El 409 desapareció de la ingesta (fallo 1): ninguna pieza de llamadas lo lanza.
    if pg_catalog.strpos(pg_catalog.pg_get_functiondef(v_f.firma::regprocedure), 'P0409') > 0 then
      raise exception 'LLAMADAS_CORRECCION: % todavía lanza P0409', v_f.firma;
    end if;
    -- Ningún bloque atrapa cualquier error (Codex P3): un fallo inesperado no se disfraza de «invalido».
    if pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(v_f.firma::regprocedure)), 'when others') > 0 then
      raise exception 'LLAMADAS_CORRECCION: % atrapa cualquier error (WHEN OTHERS)', v_f.firma;
    end if;
  end loop;

  -- Las tablas siguen cerradas a la API.
  if exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol),
                    (values ('crm.llamadas_celular_politica'), ('crm.celulares_asignaciones'),
                            ('crm.llamadas_celular_eventos'), ('crm.llamadas_celular_enlaces'),
                            ('private.celulares_estado')) t(tabla)
             where pg_catalog.has_table_privilege(r.rol, t.tabla,
                     'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) then
    raise exception 'LLAMADAS_CORRECCION: alguna tabla de llamadas quedó accesible desde la API';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261005143843' and name = 'crm_llamadas_celular_correccion' and cardinality(statements) = 1
                   and md5(statements[1]) = '306d706b4b8020b0a7e585300f233d14') then
    raise exception 'REGISTRO: la fila 20261005143843 / crm_llamadas_celular_correccion no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261005143843 / crm_llamadas_celular_correccion (1 sentencia: el archivo entero)';
end $post$;
commit;
select (select count(*) from supabase_migrations.schema_migrations
        where version = '20261005143843' and name = 'crm_llamadas_celular_correccion' and md5(statements[1]) = '306d706b4b8020b0a7e585300f233d14') = 1
       as veredicto_registro_20261005143843;

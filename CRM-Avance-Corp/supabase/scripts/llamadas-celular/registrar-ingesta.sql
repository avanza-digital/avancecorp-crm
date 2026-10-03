-- REGISTRO en supabase_migrations.schema_migrations de 20261001212258_crm_llamadas_celular_ingesta (puertas de servicio, límite, salud y bandeja de F3-a).
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración, en un mensaje aparte (punto 18 de
-- REVISION-2026-10-02.md). Idempotente; se niega si los objetos no están con su forma o si la versión ya está
-- registrada con otro nombre u otro contenido; relee la fila antes de confirmar. statements = el archivo entero
-- (md5 90d544e9e96c637bcab2869225333ceb, con finales de línea LF: correrlo desde un checkout LF, como la Mac de Miguel; en una copia de
-- Windows con CRLF el md5 no coincide y se niega). Patrón: supabase/scripts/potencial-lead/registrar.sql.
-- Generado el 03/10/2026 desde el blob de git de la migración.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_llamadas_celular_registro'));
do $chk$
begin
  if (
    to_regclass('private.celulares_estado') is not null
    and     exists (select 1 from pg_proc p where p.oid = to_regprocedure('crm.ingerir_llamada_celular_servicio(text,jsonb)')
                and p.prosecdef and p.proconfig @> array['search_path=""']::text[])
    and     to_regprocedure('crm.registrar_salud_celular_servicio(text,jsonb)') is not null
    and     to_regprocedure('crm.llamadas_celular_bandeja_fn(integer,timestamp with time zone,uuid)') is not null
  ) is not true then
    raise exception 'REGISTRO: la migración 20261001212258 no está aplicada (o no con su forma); aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261001212258' and (coalesce(name, '') <> 'crm_llamadas_celular_ingesta' or statements is distinct from array[$mig$-- Llamadas desde el celular · F3-a: PUERTAS DE SERVICIO, LÍMITE, SALUD Y BANDEJA PAGINADA.
-- Plan aprobado (Versión 3), fases F3.1 y F3.2 (la parte de la base; la Edge Function es F3-b).
--
-- Qué hace (sobre 20261001145242 y 20261001160219):
--   1. Límite por celular como DATO de la política: limite_envios_minuto (30) y limite_envios_dia
--      (600). Cambiarlo no exige migración.
--   2. private.celulares_estado: una fila por asignación con lo que el SERVIDOR sabe del celular:
--      último envío, último latido (versión de la macro, eventos en cola) y los contadores del
--      límite (minuto de reloj y día de Lima). Tabla técnica en private, como las colas y los
--      contadores del repo (private.agenda_reparto_diaria, private.contrato_pdf_jobs): fuera de la
--      API y fuera de la regla de rastro, que cubre las tablas de negocio de crm y public. Cambia
--      con cada envío; auditarla copiaría una fila por llamada a public.audit_log, que no tiene
--      retención. La evidencia de cada llamada ya vive, auditada, en crm.llamadas_celular_eventos.
--   3. Núcleo (INVOKER, sin EXECUTE para nadie; solo lo llaman las puertas de abajo):
--      · celular_por_credencial(clave): la asignación vigente con analista activo cuyo hash
--        coincide, o null. La clave en claro nunca se guarda ni se compara: solo su sha256.
--      · celular_consumir_envio(asignación): cuenta el envío o lanza P0429 con los segundos de
--        espera en el DETAIL («reintentar_en_seg=N»). Lo comparten llamadas y latidos (F3.2.2).
--      · celular_registrar_salud(asignación, latido): latido v1 con claves exactas.
--      · llamadas_celular_bandeja(actor, límite, cursor) y celulares_salud_listar(actor).
--   4. Puertas de SERVICIO (DEFINER, EXECUTE solo service_role; las llamará la Edge Function de F3-b
--      con la clave de servicio, como crm.agenda_ics_feed_fn): ingerir_llamada_celular_servicio y
--      registrar_salud_celular_servicio. Clave ausente, desconocida, de una asignación cerrada o de
--      un analista de baja → el MISMO 42501 «No autorizado», sin pistas, también si la asignación
--      se cierra mientras la llamada espera su candado. A la Edge solo le devuelven lo que el
--      celular necesita (evento_id, repetido, ignorado, motivo): nunca el lead ni su atención.
--   5. Puertas de lectura (DEFINER, EXECUTE solo authenticated): llamadas_celular_bandeja_fn (la
--      bandeja paginada por cursor recibido_en + evento_id, con las mismas filas que la de F2-c) y
--      celulares_salud_fn (gerencia, todos los celulares vigentes; supervisión, los de su equipo).
--
-- Decisiones provisionales de Jhosep (01/10/2026, F3-PLAN-CORTO.md), que Miguel ratifica o cambia
-- antes de aplicar esto fuera del banco: clave por celular con verify_jwt=false en la Edge (1);
-- 30 envíos por minuto y 600 al día (2); latido cada 6 h y al vaciar la cola (3); el celular
-- abre la encuesta de F1 por número (4, lo resuelve la Edge).
--
-- Decisiones de criterio de Claude (01/10/2026), para Miguel:
--   · La tabla técnica va en private y sin auditoría (punto 2).
--   · Solo cuenta para el límite lo que se confirma: un envío que muere con error (cuerpo
--     inválido, conflicto) se deshace entero, contador incluido. La Edge filtra los cuerpos
--     inválidos antes de llegar aquí.
--   · Ventanas fijas: el minuto de reloj y el día calendario de Lima.
--   · Los límites no tienen todavía puerta para cambiarlos: llegará con la pantalla de gerencia (F4).
--
-- Reversión: ../scripts/llamadas-celular/reversa-ingesta.sql (retira puertas, núcleo, la tabla
-- técnica y las dos columnas de la política; la evidencia queda). Verificación: npm run
-- test:llamadas:local (banco reducido + oráculo + mutantes + concurrencia).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb)') is null
     or to_regprocedure('private.celular_credencial_hash(text)') is null
     or to_regprocedure('private.llamadas_celular_actor(text[])') is null
     or to_regprocedure('private.llamada_celular_visible(uuid,uuid,uuid)') is null
     or to_regprocedure('private.llamada_celular_atencion_efectiva(uuid,text,text,uuid)') is null
     or to_regprocedure('private.vendedor_ids_visibles(uuid)') is null
     or to_regprocedure('private.rol_crm(uuid)') is null then
    raise exception 'LLAMADAS_INGESTA: falta el núcleo de 20261001160219 (F2-c)';
  end if;
  if to_regclass('private.celulares_estado') is not null
     or to_regprocedure('crm.ingerir_llamada_celular_servicio(text,jsonb)') is not null
     or exists (select 1 from pg_catalog.pg_attribute a
                where a.attrelid = 'crm.llamadas_celular_politica'::regclass
                  and a.attname in ('limite_envios_minuto', 'limite_envios_dia') and not a.attisdropped) then
    raise exception 'LLAMADAS_INGESTA: los objetos ya existen; no se sobrescriben';
  end if;
end;
$precondicion$;

-- ── 1. Límite por celular en la política ─────────────────────────────────────────────────────
alter table crm.llamadas_celular_politica
  add column limite_envios_minuto integer not null default 30
    constraint llamadas_celular_politica_limite_minuto_rango check (limite_envios_minuto between 1 and 600),
  add column limite_envios_dia integer not null default 600
    constraint llamadas_celular_politica_limite_dia_rango check (limite_envios_dia between 1 and 20000),
  add constraint llamadas_celular_politica_limites_coherentes check (limite_envios_minuto <= limite_envios_dia);

-- ── 2. Estado técnico de cada celular ────────────────────────────────────────────────────────
create table private.celulares_estado (
  id                uuid primary key default gen_random_uuid(),
  asignacion_id     uuid not null references crm.celulares_asignaciones(id) on delete restrict
                    constraint celulares_estado_asignacion_uq unique,
  ultimo_envio_en   timestamptz,
  ultimo_latido_en  timestamptz,
  latido_celular_en timestamptz,
  version_macro     text
                    constraint celulares_estado_version_valida
                    check (version_macro is null or version_macro ~ '^[A-Za-z0-9._ -]{1,40}$'),
  eventos_en_cola   integer
                    constraint celulares_estado_cola_rango
                    check (eventos_en_cola is null or eventos_en_cola between 0 and 100000),
  minuto_desde      timestamptz,
  envios_minuto     integer not null default 0
                    constraint celulares_estado_envios_minuto_validos check (envios_minuto >= 0),
  dia               date,
  envios_dia        integer not null default 0
                    constraint celulares_estado_envios_dia_validos check (envios_dia >= 0),
  creado_en         timestamptz not null default now(),
  actualizado_en    timestamptz not null default now()
);
alter table private.celulares_estado enable row level security;
revoke all on private.celulares_estado from public, anon, authenticated, service_role;

create function private.trg_celulares_estado_candado()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '42501', message = 'El estado de un celular no se borra: guarda su límite de envíos';
  end if;
  if new.id <> old.id or new.asignacion_id <> old.asignacion_id or new.creado_en <> old.creado_en then
    raise exception using errcode = '42501', message = 'El estado de un celular no cambia de asignación';
  end if;
  new.actualizado_en := pg_catalog.now();
  return new;
end;
$function$;
create trigger trg_celulares_estado_00_candado
  before update or delete on private.celulares_estado
  for each row execute function private.trg_celulares_estado_candado();

-- ── 3. Núcleo (INVOKER, sin EXECUTE para nadie) ──────────────────────────────────────────────
create function private.celular_por_credencial(p_credencial text)
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

create function private.celular_consumir_envio(p_asignacion_id uuid)
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

create function private.celular_registrar_salud(p_asignacion_id uuid, p_latido jsonb)
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

create function private.llamadas_celular_bandeja(
  p_actor uuid, p_limite integer, p_antes_recibido_en timestamptz, p_antes_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  with limitada as (
    select e.id, e.recibido_en, e.ocurrio_en, e.numero_canonico, e.direccion, e.estado_tecnico,
           e.duracion_seg, e.identificacion, e.atencion, e.lead_id, e.analista_id,
           l.nombre_completo as lead_nombre
    from crm.llamadas_celular_eventos e
    left join crm.leads l on l.id = e.lead_id
    where e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')
      and (p_antes_recibido_en is null or (e.recibido_en, e.id) < (p_antes_recibido_en, p_antes_id))
      and private.llamada_celular_visible(p_actor, e.lead_id, e.analista_id)
    order by e.recibido_en desc, e.id desc
    limit p_limite + 1
  ), pagina as (
    select x.*, pg_catalog.row_number() over (order by x.recibido_en desc, x.id desc) as n
    from limitada x
  )
  select pg_catalog.jsonb_build_object(
    -- La misma forma de fila que private.llamadas_celular_pendientes (F2-c).
    'filas', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
               'evento_id', p.id, 'recibido_en', p.recibido_en, 'ocurrio_en', p.ocurrio_en,
               'numero', p.numero_canonico, 'direccion', p.direccion, 'estado_tecnico', p.estado_tecnico,
               'duracion_seg', p.duracion_seg, 'identificacion', p.identificacion,
               'atencion', private.llamada_celular_atencion_efectiva(p_actor, p.atencion, p.identificacion, p.lead_id),
               'lead_id', p.lead_id, 'lead_nombre', p.lead_nombre,
               'analista_id', p.analista_id, 'es_propia', p.analista_id = p_actor)
             order by p.n) filter (where p.n <= p_limite), '[]'::jsonb),
    'siguiente', (select pg_catalog.jsonb_build_object('recibido_en', u.recibido_en, 'evento_id', u.id)
                  from pagina u
                  where u.n = p_limite and exists (select 1 from pagina m where m.n > p_limite)))
  from pagina p
$function$;

create function private.celulares_salud_listar(p_actor uuid)
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

-- ── 4. Puertas de servicio (crm, DEFINER, EXECUTE solo service_role) ─────────────────────────
create function crm.ingerir_llamada_celular_servicio(p_credencial text, p_evento jsonb)
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

create function crm.registrar_salud_celular_servicio(p_credencial text, p_latido jsonb)
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

-- ── 5. Puertas de lectura (crm, DEFINER, EXECUTE solo authenticated) ─────────────────────────
create function crm.llamadas_celular_bandeja_fn(
  p_limite integer default 50, p_antes_recibido_en timestamptz default null, p_antes_id uuid default null)
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
  if (p_antes_recibido_en is null) <> (p_antes_id is null) then
    raise exception using errcode = '22023', message = 'El cursor lleva recibido_en y evento_id juntos';
  end if;
  return private.llamadas_celular_bandeja(v_actor, p_limite, p_antes_recibido_en, p_antes_id);
end;
$function$;

create function crm.celulares_salud_fn()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := private.llamadas_celular_actor(array['supervisor', 'gerencia']);
begin
  return private.celulares_salud_listar(v_actor);
end;
$function$;

-- ── 6. Permisos ──────────────────────────────────────────────────────────────────────────────
do $permisos$
declare
  v_f text;
begin
  foreach v_f in array array[
    'private.trg_celulares_estado_candado()', 'private.celular_por_credencial(text)',
    'private.celular_consumir_envio(uuid)', 'private.celular_registrar_salud(uuid,jsonb)',
    'private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid)',
    'private.celulares_salud_listar(uuid)'] loop
    execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
  end loop;
  foreach v_f in array array[
    'crm.ingerir_llamada_celular_servicio(text,jsonb)', 'crm.registrar_salud_celular_servicio(text,jsonb)'] loop
    execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
    execute pg_catalog.format('grant execute on function %s to service_role', v_f);
  end loop;
  foreach v_f in array array[
    'crm.llamadas_celular_bandeja_fn(integer,timestamptz,uuid)', 'crm.celulares_salud_fn()'] loop
    execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
    execute pg_catalog.format('grant execute on function %s to authenticated', v_f);
  end loop;
end;
$permisos$;

-- ── 7. Comentarios ───────────────────────────────────────────────────────────────────────────
comment on column crm.llamadas_celular_politica.limite_envios_minuto is 'Envíos que acepta un celular por minuto de reloj (30, decisión 2 de F3, provisional de Jhosep 01/10). Lo comparten las llamadas y los latidos; al pasarse, P0429 con la espera.';
comment on column crm.llamadas_celular_politica.limite_envios_dia is 'Envíos que acepta un celular por día de Lima (600, decisión 2 de F3). No menor que limite_envios_minuto.';

comment on table private.celulares_estado is
  'Estado técnico de cada celular asignado (F3-a): último envío, último latido (versión de la macro, eventos en cola) y los contadores del límite de envíos (minuto de reloj y día de Lima). Una fila por asignación. Tabla técnica de private, sin acceso para la API y sin auditoría: cambia con cada envío, no guarda datos personales ni secretos, y la evidencia de cada llamada ya vive, auditada, en crm.llamadas_celular_eventos. Sin columna de tenant: CRM de una sola empresa.';
comment on column private.celulares_estado.id is 'Identificador de la fila.';
comment on column private.celulares_estado.asignacion_id is 'Asignación de celular a la que pertenece (una fila por asignación; no cambia).';
comment on column private.celulares_estado.ultimo_envio_en is 'Cuándo llegó y se confirmó la última llamada de este celular (hora del servidor).';
comment on column private.celulares_estado.ultimo_latido_en is 'Cuándo llegó el último latido (hora del servidor). Un latido solo prueba que el celular habla, no que capture bien.';
comment on column private.celulares_estado.latido_celular_en is 'Hora del celular en el último latido, si la mandó; contrasta con ultimo_latido_en.';
comment on column private.celulares_estado.version_macro is 'Versión de la macro que declaró el último latido (texto corto del celular, no confiable).';
comment on column private.celulares_estado.eventos_en_cola is 'Llamadas que el celular dijo tener pendientes de enviar en su último latido (no confiable).';
comment on column private.celulares_estado.minuto_desde is 'Inicio del minuto de reloj al que corresponde envios_minuto.';
comment on column private.celulares_estado.envios_minuto is 'Envíos confirmados en el minuto minuto_desde.';
comment on column private.celulares_estado.dia is 'Día de Lima al que corresponde envios_dia.';
comment on column private.celulares_estado.envios_dia is 'Envíos confirmados en el día dia.';
comment on column private.celulares_estado.creado_en is 'Alta de la fila (primer envío del celular).';
comment on column private.celulares_estado.actualizado_en is 'Último cambio (lo sella el trigger).';

comment on function private.trg_celulares_estado_candado() is
  'Candado de private.celulares_estado: sin DELETE (borrar la fila reiniciaría el límite) y sin cambiar de asignación; sella actualizado_en. SECURITY DEFINER por coherencia con los candados de F2-b; no lee datos.';
comment on function private.celular_por_credencial(text) is
  'Resuelve la clave de un celular: la asignación vigente, con analista o supervisor activo, cuyo credencial_hash es el sha256 de la clave; null en cualquier otro caso. DATO SENSIBLE: recibe la clave en claro y no la guarda.';
comment on function private.celular_consumir_envio(uuid) is
  'Límite por celular (F3.2.2, compartido por llamadas y latidos): bloquea la fila de estado, reinicia las ventanas fijas (minuto de reloj, día de Lima) y cuenta el envío; al pasarse, P0429 con DETAIL reintentar_en_seg=N. Se deshace con el envío si este falla.';
comment on function private.celular_registrar_salud(uuid,jsonb) is
  'Latido v1 del celular con claves exactas (version_macro y en_cola obligatorios, ocurrio_en opcional): guarda versión, cola y hora en private.celulares_estado. Un latido no demuestra captura sana.';
comment on function private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid) is
  'Bandeja paginada de llamadas no finales visibles para el actor, por cursor (recibido_en, evento_id) descendente; filas con la misma forma que private.llamadas_celular_pendientes y la atención efectiva. DATO PERSONAL: número y nombre del lead (el actor ya tiene ámbito sobre ellos).';
comment on function private.celulares_salud_listar(uuid) is
  'Salud de los celulares vigentes: gerencia todos, supervisión los de su equipo. Sin hash de credencial.';
comment on function crm.ingerir_llamada_celular_servicio(text,jsonb) is
  'Puerta de SERVICIO (DEFINER, solo service_role: la llama la Edge Function crm-llamadas-ingesta de F3-b) para ingerir la llamada de un celular con su clave. Clave ausente, desconocida, cerrada o de un analista de baja: el mismo 42501 «No autorizado». Cuenta el envío (P0429 al pasarse) y delega en private.llamada_celular_ingerir. Devuelve solo evento_id, repetido, ignorado y motivo. DATO SENSIBLE: recibe la clave; DATO PERSONAL: el número.';
comment on function crm.registrar_salud_celular_servicio(text,jsonb) is
  'Puerta de SERVICIO (DEFINER, solo service_role) para el latido de un celular con su clave: misma autorización uniforme y mismo límite que la ingesta. DATO SENSIBLE: recibe la clave.';
comment on function crm.llamadas_celular_bandeja_fn(integer,timestamptz,uuid) is
  'Puerta (DEFINER: las tablas no tienen privilegios para la API) de la bandeja paginada de llamadas del celular. Analista, supervisión y gerencia; límite 1 a 200; el cursor (recibido_en y evento_id juntos) es el campo siguiente de la página anterior.';
comment on function crm.celulares_salud_fn() is
  'Puerta (DEFINER) de lectura de la salud de los celulares: gerencia y supervisión (su equipo).';

-- ── 8. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f record;
begin
  if not (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = 'private.celulares_estado'::regclass) then
    raise exception 'LLAMADAS_INGESTA: private.celulares_estado quedó sin RLS';
  end if;
  if exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol)
             where pg_catalog.has_table_privilege(r.rol, 'private.celulares_estado',
                     'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) then
    raise exception 'LLAMADAS_INGESTA: private.celulares_estado quedó accesible desde la API';
  end if;
  if exists (select 1 from pg_catalog.pg_policy p where p.polrelid = 'private.celulares_estado'::regclass) then
    raise exception 'LLAMADAS_INGESTA: private.celulares_estado no debe tener policies (todo va por puertas)';
  end if;
  if not exists (select 1 from pg_catalog.pg_trigger t
                 where t.tgrelid = 'private.celulares_estado'::regclass and not t.tgisinternal
                   and t.tgname = 'trg_celulares_estado_00_candado' and t.tgenabled in ('O', 'A')) then
    raise exception 'LLAMADAS_INGESTA: private.celulares_estado quedó sin su candado';
  end if;
  if exists (select 1 from pg_catalog.pg_constraint c
             where c.contype = 'f' and c.conrelid = 'private.celulares_estado'::regclass and c.confdeltype <> 'r') then
    raise exception 'LLAMADAS_INGESTA: la FK de private.celulares_estado no es RESTRICT';
  end if;
  if pg_catalog.obj_description('private.celulares_estado'::regclass, 'pg_class') is null
     or exists (select 1 from pg_catalog.pg_attribute a
                where a.attnum > 0 and not a.attisdropped
                  and pg_catalog.col_description(a.attrelid, a.attnum) is null
                  and (a.attrelid = 'private.celulares_estado'::regclass
                       or (a.attrelid = 'crm.llamadas_celular_politica'::regclass
                           and a.attname in ('limite_envios_minuto', 'limite_envios_dia')))) then
    raise exception 'LLAMADAS_INGESTA: falta COMMENT en la tabla técnica o en los límites de la política';
  end if;
  if (select p.limite_envios_minuto <> 30 or p.limite_envios_dia <> 600
      from crm.llamadas_celular_politica p where p.singleton) is distinct from false then
    raise exception 'LLAMADAS_INGESTA: los límites de la política no quedaron en 30 por minuto y 600 al día';
  end if;

  for v_f in
    select * from (values
      ('private.trg_celulares_estado_candado()', true, null),
      ('private.celular_por_credencial(text)', false, null),
      ('private.celular_consumir_envio(uuid)', false, null),
      ('private.celular_registrar_salud(uuid,jsonb)', false, null),
      ('private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid)', false, null),
      ('private.celulares_salud_listar(uuid)', false, null),
      ('crm.ingerir_llamada_celular_servicio(text,jsonb)', true, 'service_role'),
      ('crm.registrar_salud_celular_servicio(text,jsonb)', true, 'service_role'),
      ('crm.llamadas_celular_bandeja_fn(integer,timestamptz,uuid)', true, 'authenticated'),
      ('crm.celulares_salud_fn()', true, 'authenticated')
    ) as f(firma, definer, rol)
  loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) is distinct from v_f.definer then
      raise exception 'LLAMADAS_INGESTA: % debería ser %', v_f.firma,
        case when v_f.definer then 'SECURITY DEFINER' else 'SECURITY INVOKER' end;
    end if;
    if exists (
      select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
      where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
        and a.grantee <> p.proowner
        and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid)
    ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
      or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE')) then
      raise exception 'LLAMADAS_INGESTA: EXECUTE inesperado en %', v_f.firma;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'LLAMADAS_INGESTA: search_path inesperado en %', v_f.firma;
    end if;
    if pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
      raise exception 'LLAMADAS_INGESTA: % sin COMMENT', v_f.firma;
    end if;
  end loop;

  -- Las tablas de F2 siguen cerradas a la API: esta migración no abrió ningún privilegio.
  if exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol),
                    (values ('crm.llamadas_celular_politica'), ('crm.celulares_asignaciones'),
                            ('crm.llamadas_celular_eventos'), ('crm.llamadas_celular_enlaces')) t(tabla)
             where pg_catalog.has_table_privilege(r.rol, t.tabla,
                     'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) then
    raise exception 'LLAMADAS_INGESTA: alguna tabla de llamadas quedó accesible desde la API';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
$mig$])) then
    raise exception 'REGISTRO: la versión 20261001212258 ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261001212258', 'crm_llamadas_celular_ingesta', array[$mig$-- Llamadas desde el celular · F3-a: PUERTAS DE SERVICIO, LÍMITE, SALUD Y BANDEJA PAGINADA.
-- Plan aprobado (Versión 3), fases F3.1 y F3.2 (la parte de la base; la Edge Function es F3-b).
--
-- Qué hace (sobre 20261001145242 y 20261001160219):
--   1. Límite por celular como DATO de la política: limite_envios_minuto (30) y limite_envios_dia
--      (600). Cambiarlo no exige migración.
--   2. private.celulares_estado: una fila por asignación con lo que el SERVIDOR sabe del celular:
--      último envío, último latido (versión de la macro, eventos en cola) y los contadores del
--      límite (minuto de reloj y día de Lima). Tabla técnica en private, como las colas y los
--      contadores del repo (private.agenda_reparto_diaria, private.contrato_pdf_jobs): fuera de la
--      API y fuera de la regla de rastro, que cubre las tablas de negocio de crm y public. Cambia
--      con cada envío; auditarla copiaría una fila por llamada a public.audit_log, que no tiene
--      retención. La evidencia de cada llamada ya vive, auditada, en crm.llamadas_celular_eventos.
--   3. Núcleo (INVOKER, sin EXECUTE para nadie; solo lo llaman las puertas de abajo):
--      · celular_por_credencial(clave): la asignación vigente con analista activo cuyo hash
--        coincide, o null. La clave en claro nunca se guarda ni se compara: solo su sha256.
--      · celular_consumir_envio(asignación): cuenta el envío o lanza P0429 con los segundos de
--        espera en el DETAIL («reintentar_en_seg=N»). Lo comparten llamadas y latidos (F3.2.2).
--      · celular_registrar_salud(asignación, latido): latido v1 con claves exactas.
--      · llamadas_celular_bandeja(actor, límite, cursor) y celulares_salud_listar(actor).
--   4. Puertas de SERVICIO (DEFINER, EXECUTE solo service_role; las llamará la Edge Function de F3-b
--      con la clave de servicio, como crm.agenda_ics_feed_fn): ingerir_llamada_celular_servicio y
--      registrar_salud_celular_servicio. Clave ausente, desconocida, de una asignación cerrada o de
--      un analista de baja → el MISMO 42501 «No autorizado», sin pistas, también si la asignación
--      se cierra mientras la llamada espera su candado. A la Edge solo le devuelven lo que el
--      celular necesita (evento_id, repetido, ignorado, motivo): nunca el lead ni su atención.
--   5. Puertas de lectura (DEFINER, EXECUTE solo authenticated): llamadas_celular_bandeja_fn (la
--      bandeja paginada por cursor recibido_en + evento_id, con las mismas filas que la de F2-c) y
--      celulares_salud_fn (gerencia, todos los celulares vigentes; supervisión, los de su equipo).
--
-- Decisiones provisionales de Jhosep (01/10/2026, F3-PLAN-CORTO.md), que Miguel ratifica o cambia
-- antes de aplicar esto fuera del banco: clave por celular con verify_jwt=false en la Edge (1);
-- 30 envíos por minuto y 600 al día (2); latido cada 6 h y al vaciar la cola (3); el celular
-- abre la encuesta de F1 por número (4, lo resuelve la Edge).
--
-- Decisiones de criterio de Claude (01/10/2026), para Miguel:
--   · La tabla técnica va en private y sin auditoría (punto 2).
--   · Solo cuenta para el límite lo que se confirma: un envío que muere con error (cuerpo
--     inválido, conflicto) se deshace entero, contador incluido. La Edge filtra los cuerpos
--     inválidos antes de llegar aquí.
--   · Ventanas fijas: el minuto de reloj y el día calendario de Lima.
--   · Los límites no tienen todavía puerta para cambiarlos: llegará con la pantalla de gerencia (F4).
--
-- Reversión: ../scripts/llamadas-celular/reversa-ingesta.sql (retira puertas, núcleo, la tabla
-- técnica y las dos columnas de la política; la evidencia queda). Verificación: npm run
-- test:llamadas:local (banco reducido + oráculo + mutantes + concurrencia).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb)') is null
     or to_regprocedure('private.celular_credencial_hash(text)') is null
     or to_regprocedure('private.llamadas_celular_actor(text[])') is null
     or to_regprocedure('private.llamada_celular_visible(uuid,uuid,uuid)') is null
     or to_regprocedure('private.llamada_celular_atencion_efectiva(uuid,text,text,uuid)') is null
     or to_regprocedure('private.vendedor_ids_visibles(uuid)') is null
     or to_regprocedure('private.rol_crm(uuid)') is null then
    raise exception 'LLAMADAS_INGESTA: falta el núcleo de 20261001160219 (F2-c)';
  end if;
  if to_regclass('private.celulares_estado') is not null
     or to_regprocedure('crm.ingerir_llamada_celular_servicio(text,jsonb)') is not null
     or exists (select 1 from pg_catalog.pg_attribute a
                where a.attrelid = 'crm.llamadas_celular_politica'::regclass
                  and a.attname in ('limite_envios_minuto', 'limite_envios_dia') and not a.attisdropped) then
    raise exception 'LLAMADAS_INGESTA: los objetos ya existen; no se sobrescriben';
  end if;
end;
$precondicion$;

-- ── 1. Límite por celular en la política ─────────────────────────────────────────────────────
alter table crm.llamadas_celular_politica
  add column limite_envios_minuto integer not null default 30
    constraint llamadas_celular_politica_limite_minuto_rango check (limite_envios_minuto between 1 and 600),
  add column limite_envios_dia integer not null default 600
    constraint llamadas_celular_politica_limite_dia_rango check (limite_envios_dia between 1 and 20000),
  add constraint llamadas_celular_politica_limites_coherentes check (limite_envios_minuto <= limite_envios_dia);

-- ── 2. Estado técnico de cada celular ────────────────────────────────────────────────────────
create table private.celulares_estado (
  id                uuid primary key default gen_random_uuid(),
  asignacion_id     uuid not null references crm.celulares_asignaciones(id) on delete restrict
                    constraint celulares_estado_asignacion_uq unique,
  ultimo_envio_en   timestamptz,
  ultimo_latido_en  timestamptz,
  latido_celular_en timestamptz,
  version_macro     text
                    constraint celulares_estado_version_valida
                    check (version_macro is null or version_macro ~ '^[A-Za-z0-9._ -]{1,40}$'),
  eventos_en_cola   integer
                    constraint celulares_estado_cola_rango
                    check (eventos_en_cola is null or eventos_en_cola between 0 and 100000),
  minuto_desde      timestamptz,
  envios_minuto     integer not null default 0
                    constraint celulares_estado_envios_minuto_validos check (envios_minuto >= 0),
  dia               date,
  envios_dia        integer not null default 0
                    constraint celulares_estado_envios_dia_validos check (envios_dia >= 0),
  creado_en         timestamptz not null default now(),
  actualizado_en    timestamptz not null default now()
);
alter table private.celulares_estado enable row level security;
revoke all on private.celulares_estado from public, anon, authenticated, service_role;

create function private.trg_celulares_estado_candado()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '42501', message = 'El estado de un celular no se borra: guarda su límite de envíos';
  end if;
  if new.id <> old.id or new.asignacion_id <> old.asignacion_id or new.creado_en <> old.creado_en then
    raise exception using errcode = '42501', message = 'El estado de un celular no cambia de asignación';
  end if;
  new.actualizado_en := pg_catalog.now();
  return new;
end;
$function$;
create trigger trg_celulares_estado_00_candado
  before update or delete on private.celulares_estado
  for each row execute function private.trg_celulares_estado_candado();

-- ── 3. Núcleo (INVOKER, sin EXECUTE para nadie) ──────────────────────────────────────────────
create function private.celular_por_credencial(p_credencial text)
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

create function private.celular_consumir_envio(p_asignacion_id uuid)
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

create function private.celular_registrar_salud(p_asignacion_id uuid, p_latido jsonb)
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

create function private.llamadas_celular_bandeja(
  p_actor uuid, p_limite integer, p_antes_recibido_en timestamptz, p_antes_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  with limitada as (
    select e.id, e.recibido_en, e.ocurrio_en, e.numero_canonico, e.direccion, e.estado_tecnico,
           e.duracion_seg, e.identificacion, e.atencion, e.lead_id, e.analista_id,
           l.nombre_completo as lead_nombre
    from crm.llamadas_celular_eventos e
    left join crm.leads l on l.id = e.lead_id
    where e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')
      and (p_antes_recibido_en is null or (e.recibido_en, e.id) < (p_antes_recibido_en, p_antes_id))
      and private.llamada_celular_visible(p_actor, e.lead_id, e.analista_id)
    order by e.recibido_en desc, e.id desc
    limit p_limite + 1
  ), pagina as (
    select x.*, pg_catalog.row_number() over (order by x.recibido_en desc, x.id desc) as n
    from limitada x
  )
  select pg_catalog.jsonb_build_object(
    -- La misma forma de fila que private.llamadas_celular_pendientes (F2-c).
    'filas', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
               'evento_id', p.id, 'recibido_en', p.recibido_en, 'ocurrio_en', p.ocurrio_en,
               'numero', p.numero_canonico, 'direccion', p.direccion, 'estado_tecnico', p.estado_tecnico,
               'duracion_seg', p.duracion_seg, 'identificacion', p.identificacion,
               'atencion', private.llamada_celular_atencion_efectiva(p_actor, p.atencion, p.identificacion, p.lead_id),
               'lead_id', p.lead_id, 'lead_nombre', p.lead_nombre,
               'analista_id', p.analista_id, 'es_propia', p.analista_id = p_actor)
             order by p.n) filter (where p.n <= p_limite), '[]'::jsonb),
    'siguiente', (select pg_catalog.jsonb_build_object('recibido_en', u.recibido_en, 'evento_id', u.id)
                  from pagina u
                  where u.n = p_limite and exists (select 1 from pagina m where m.n > p_limite)))
  from pagina p
$function$;

create function private.celulares_salud_listar(p_actor uuid)
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

-- ── 4. Puertas de servicio (crm, DEFINER, EXECUTE solo service_role) ─────────────────────────
create function crm.ingerir_llamada_celular_servicio(p_credencial text, p_evento jsonb)
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

create function crm.registrar_salud_celular_servicio(p_credencial text, p_latido jsonb)
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

-- ── 5. Puertas de lectura (crm, DEFINER, EXECUTE solo authenticated) ─────────────────────────
create function crm.llamadas_celular_bandeja_fn(
  p_limite integer default 50, p_antes_recibido_en timestamptz default null, p_antes_id uuid default null)
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
  if (p_antes_recibido_en is null) <> (p_antes_id is null) then
    raise exception using errcode = '22023', message = 'El cursor lleva recibido_en y evento_id juntos';
  end if;
  return private.llamadas_celular_bandeja(v_actor, p_limite, p_antes_recibido_en, p_antes_id);
end;
$function$;

create function crm.celulares_salud_fn()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := private.llamadas_celular_actor(array['supervisor', 'gerencia']);
begin
  return private.celulares_salud_listar(v_actor);
end;
$function$;

-- ── 6. Permisos ──────────────────────────────────────────────────────────────────────────────
do $permisos$
declare
  v_f text;
begin
  foreach v_f in array array[
    'private.trg_celulares_estado_candado()', 'private.celular_por_credencial(text)',
    'private.celular_consumir_envio(uuid)', 'private.celular_registrar_salud(uuid,jsonb)',
    'private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid)',
    'private.celulares_salud_listar(uuid)'] loop
    execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
  end loop;
  foreach v_f in array array[
    'crm.ingerir_llamada_celular_servicio(text,jsonb)', 'crm.registrar_salud_celular_servicio(text,jsonb)'] loop
    execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
    execute pg_catalog.format('grant execute on function %s to service_role', v_f);
  end loop;
  foreach v_f in array array[
    'crm.llamadas_celular_bandeja_fn(integer,timestamptz,uuid)', 'crm.celulares_salud_fn()'] loop
    execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
    execute pg_catalog.format('grant execute on function %s to authenticated', v_f);
  end loop;
end;
$permisos$;

-- ── 7. Comentarios ───────────────────────────────────────────────────────────────────────────
comment on column crm.llamadas_celular_politica.limite_envios_minuto is 'Envíos que acepta un celular por minuto de reloj (30, decisión 2 de F3, provisional de Jhosep 01/10). Lo comparten las llamadas y los latidos; al pasarse, P0429 con la espera.';
comment on column crm.llamadas_celular_politica.limite_envios_dia is 'Envíos que acepta un celular por día de Lima (600, decisión 2 de F3). No menor que limite_envios_minuto.';

comment on table private.celulares_estado is
  'Estado técnico de cada celular asignado (F3-a): último envío, último latido (versión de la macro, eventos en cola) y los contadores del límite de envíos (minuto de reloj y día de Lima). Una fila por asignación. Tabla técnica de private, sin acceso para la API y sin auditoría: cambia con cada envío, no guarda datos personales ni secretos, y la evidencia de cada llamada ya vive, auditada, en crm.llamadas_celular_eventos. Sin columna de tenant: CRM de una sola empresa.';
comment on column private.celulares_estado.id is 'Identificador de la fila.';
comment on column private.celulares_estado.asignacion_id is 'Asignación de celular a la que pertenece (una fila por asignación; no cambia).';
comment on column private.celulares_estado.ultimo_envio_en is 'Cuándo llegó y se confirmó la última llamada de este celular (hora del servidor).';
comment on column private.celulares_estado.ultimo_latido_en is 'Cuándo llegó el último latido (hora del servidor). Un latido solo prueba que el celular habla, no que capture bien.';
comment on column private.celulares_estado.latido_celular_en is 'Hora del celular en el último latido, si la mandó; contrasta con ultimo_latido_en.';
comment on column private.celulares_estado.version_macro is 'Versión de la macro que declaró el último latido (texto corto del celular, no confiable).';
comment on column private.celulares_estado.eventos_en_cola is 'Llamadas que el celular dijo tener pendientes de enviar en su último latido (no confiable).';
comment on column private.celulares_estado.minuto_desde is 'Inicio del minuto de reloj al que corresponde envios_minuto.';
comment on column private.celulares_estado.envios_minuto is 'Envíos confirmados en el minuto minuto_desde.';
comment on column private.celulares_estado.dia is 'Día de Lima al que corresponde envios_dia.';
comment on column private.celulares_estado.envios_dia is 'Envíos confirmados en el día dia.';
comment on column private.celulares_estado.creado_en is 'Alta de la fila (primer envío del celular).';
comment on column private.celulares_estado.actualizado_en is 'Último cambio (lo sella el trigger).';

comment on function private.trg_celulares_estado_candado() is
  'Candado de private.celulares_estado: sin DELETE (borrar la fila reiniciaría el límite) y sin cambiar de asignación; sella actualizado_en. SECURITY DEFINER por coherencia con los candados de F2-b; no lee datos.';
comment on function private.celular_por_credencial(text) is
  'Resuelve la clave de un celular: la asignación vigente, con analista o supervisor activo, cuyo credencial_hash es el sha256 de la clave; null en cualquier otro caso. DATO SENSIBLE: recibe la clave en claro y no la guarda.';
comment on function private.celular_consumir_envio(uuid) is
  'Límite por celular (F3.2.2, compartido por llamadas y latidos): bloquea la fila de estado, reinicia las ventanas fijas (minuto de reloj, día de Lima) y cuenta el envío; al pasarse, P0429 con DETAIL reintentar_en_seg=N. Se deshace con el envío si este falla.';
comment on function private.celular_registrar_salud(uuid,jsonb) is
  'Latido v1 del celular con claves exactas (version_macro y en_cola obligatorios, ocurrio_en opcional): guarda versión, cola y hora en private.celulares_estado. Un latido no demuestra captura sana.';
comment on function private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid) is
  'Bandeja paginada de llamadas no finales visibles para el actor, por cursor (recibido_en, evento_id) descendente; filas con la misma forma que private.llamadas_celular_pendientes y la atención efectiva. DATO PERSONAL: número y nombre del lead (el actor ya tiene ámbito sobre ellos).';
comment on function private.celulares_salud_listar(uuid) is
  'Salud de los celulares vigentes: gerencia todos, supervisión los de su equipo. Sin hash de credencial.';
comment on function crm.ingerir_llamada_celular_servicio(text,jsonb) is
  'Puerta de SERVICIO (DEFINER, solo service_role: la llama la Edge Function crm-llamadas-ingesta de F3-b) para ingerir la llamada de un celular con su clave. Clave ausente, desconocida, cerrada o de un analista de baja: el mismo 42501 «No autorizado». Cuenta el envío (P0429 al pasarse) y delega en private.llamada_celular_ingerir. Devuelve solo evento_id, repetido, ignorado y motivo. DATO SENSIBLE: recibe la clave; DATO PERSONAL: el número.';
comment on function crm.registrar_salud_celular_servicio(text,jsonb) is
  'Puerta de SERVICIO (DEFINER, solo service_role) para el latido de un celular con su clave: misma autorización uniforme y mismo límite que la ingesta. DATO SENSIBLE: recibe la clave.';
comment on function crm.llamadas_celular_bandeja_fn(integer,timestamptz,uuid) is
  'Puerta (DEFINER: las tablas no tienen privilegios para la API) de la bandeja paginada de llamadas del celular. Analista, supervisión y gerencia; límite 1 a 200; el cursor (recibido_en y evento_id juntos) es el campo siguiente de la página anterior.';
comment on function crm.celulares_salud_fn() is
  'Puerta (DEFINER) de lectura de la salud de los celulares: gerencia y supervisión (su equipo).';

-- ── 8. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f record;
begin
  if not (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = 'private.celulares_estado'::regclass) then
    raise exception 'LLAMADAS_INGESTA: private.celulares_estado quedó sin RLS';
  end if;
  if exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol)
             where pg_catalog.has_table_privilege(r.rol, 'private.celulares_estado',
                     'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) then
    raise exception 'LLAMADAS_INGESTA: private.celulares_estado quedó accesible desde la API';
  end if;
  if exists (select 1 from pg_catalog.pg_policy p where p.polrelid = 'private.celulares_estado'::regclass) then
    raise exception 'LLAMADAS_INGESTA: private.celulares_estado no debe tener policies (todo va por puertas)';
  end if;
  if not exists (select 1 from pg_catalog.pg_trigger t
                 where t.tgrelid = 'private.celulares_estado'::regclass and not t.tgisinternal
                   and t.tgname = 'trg_celulares_estado_00_candado' and t.tgenabled in ('O', 'A')) then
    raise exception 'LLAMADAS_INGESTA: private.celulares_estado quedó sin su candado';
  end if;
  if exists (select 1 from pg_catalog.pg_constraint c
             where c.contype = 'f' and c.conrelid = 'private.celulares_estado'::regclass and c.confdeltype <> 'r') then
    raise exception 'LLAMADAS_INGESTA: la FK de private.celulares_estado no es RESTRICT';
  end if;
  if pg_catalog.obj_description('private.celulares_estado'::regclass, 'pg_class') is null
     or exists (select 1 from pg_catalog.pg_attribute a
                where a.attnum > 0 and not a.attisdropped
                  and pg_catalog.col_description(a.attrelid, a.attnum) is null
                  and (a.attrelid = 'private.celulares_estado'::regclass
                       or (a.attrelid = 'crm.llamadas_celular_politica'::regclass
                           and a.attname in ('limite_envios_minuto', 'limite_envios_dia')))) then
    raise exception 'LLAMADAS_INGESTA: falta COMMENT en la tabla técnica o en los límites de la política';
  end if;
  if (select p.limite_envios_minuto <> 30 or p.limite_envios_dia <> 600
      from crm.llamadas_celular_politica p where p.singleton) is distinct from false then
    raise exception 'LLAMADAS_INGESTA: los límites de la política no quedaron en 30 por minuto y 600 al día';
  end if;

  for v_f in
    select * from (values
      ('private.trg_celulares_estado_candado()', true, null),
      ('private.celular_por_credencial(text)', false, null),
      ('private.celular_consumir_envio(uuid)', false, null),
      ('private.celular_registrar_salud(uuid,jsonb)', false, null),
      ('private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid)', false, null),
      ('private.celulares_salud_listar(uuid)', false, null),
      ('crm.ingerir_llamada_celular_servicio(text,jsonb)', true, 'service_role'),
      ('crm.registrar_salud_celular_servicio(text,jsonb)', true, 'service_role'),
      ('crm.llamadas_celular_bandeja_fn(integer,timestamptz,uuid)', true, 'authenticated'),
      ('crm.celulares_salud_fn()', true, 'authenticated')
    ) as f(firma, definer, rol)
  loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) is distinct from v_f.definer then
      raise exception 'LLAMADAS_INGESTA: % debería ser %', v_f.firma,
        case when v_f.definer then 'SECURITY DEFINER' else 'SECURITY INVOKER' end;
    end if;
    if exists (
      select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
      where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
        and a.grantee <> p.proowner
        and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid)
    ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
      or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE')) then
      raise exception 'LLAMADAS_INGESTA: EXECUTE inesperado en %', v_f.firma;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'LLAMADAS_INGESTA: search_path inesperado en %', v_f.firma;
    end if;
    if pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
      raise exception 'LLAMADAS_INGESTA: % sin COMMENT', v_f.firma;
    end if;
  end loop;

  -- Las tablas de F2 siguen cerradas a la API: esta migración no abrió ningún privilegio.
  if exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol),
                    (values ('crm.llamadas_celular_politica'), ('crm.celulares_asignaciones'),
                            ('crm.llamadas_celular_eventos'), ('crm.llamadas_celular_enlaces')) t(tabla)
             where pg_catalog.has_table_privilege(r.rol, t.tabla,
                     'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) then
    raise exception 'LLAMADAS_INGESTA: alguna tabla de llamadas quedó accesible desde la API';
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
                 where version = '20261001212258' and name = 'crm_llamadas_celular_ingesta' and cardinality(statements) = 1
                   and md5(statements[1]) = '90d544e9e96c637bcab2869225333ceb') then
    raise exception 'REGISTRO: la fila 20261001212258 / crm_llamadas_celular_ingesta no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261001212258 / crm_llamadas_celular_ingesta (1 sentencia: el archivo entero)';
end $post$;
commit;

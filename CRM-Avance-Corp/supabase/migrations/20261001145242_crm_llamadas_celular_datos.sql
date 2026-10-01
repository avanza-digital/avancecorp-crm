-- Llamadas desde el celular · F2-b: DATOS (asignaciones de celulares, eventos de llamada, enlaces
-- a la actividad registrada y política de retención). Plan aprobado (Versión 3), fase F2.2.
--
-- Qué hace:
--   1. crm.llamadas_celular_politica: fila única con las perillas del contrato (guardar o no las
--      llamadas a números sin lead, entrantes activas, días de retención por estado). Las
--      decisiones del 30/09 son DATOS, no código: cambiarlas no exige migración.
--   2. crm.celulares_asignaciones: qué analista tenía cada celular corporativo (C1, C2…) y desde
--      cuándo. La credencial con la que F3 ingerirá llamadas se guarda SOLO como hash sha256 (modelo
--      private.saga_token_hash); la clave en claro se muestra una vez al asignar (F2-c) y no se
--      almacena. Una sola vigencia por etiqueta (índice único parcial + exclusión por rango, el par
--      de crm.lead_asignaciones). Una asignación cerrada es inmutable; rotar = cerrar y abrir otra.
--   3. crm.llamadas_celular_eventos: la evidencia de cada llamada: qué celular, qué número (E.164),
--      cuándo según el celular (ocurrio_en) y según el servidor (recibido_en), dirección, estado
--      técnico y duración. El PAYLOAD es inmutable y la identidad es estable (asignación + id de
--      origen) con hash para la idempotencia (mismo contenido → mismo evento; distinto → conflicto,
--      en F2-c). Aparte va lo que SÍ cambia, con transiciones vigiladas por trigger: identificación
--      (sin_identificar / ambiguo / identificado), atención (por_revisar / requiere_resultado /
--      requiere_devolucion / registrado / descartado_con_motivo), lead, método de asociación y
--      descarte motivado con catálogo cerrado.
--   4. crm.llamadas_celular_enlaces: uno a uno entre un evento y la actividad de llamada que la
--      encuesta registró (tipo llamada_*, metadata.evento = resultado_llamada, mismo lead). Si ese
--      resultado se deshace (metadata.deshecho_en) el enlace puede moverse al resultado corregido;
--      el evento sigue en «registrado»: la encuesta nunca vuelve a saltar sola.
--   5. private.caducar_llamadas_celular + pg_cron: retención por estado según la política. El
--      candado de inmutabilidad solo deja pasar el DELETE bajo el GUC de la purga o en cascada.
--
-- Decisiones provisionales de Jhosep (30/09/2026), que Miguel ratifica o cambia antes de aplicar
-- esto fuera del banco: docs/plans/llamadas-celular/F2-PLAN-CORTO.md, contrato F2.1 (elegibilidad,
-- solo salientes, sin lead no se guarda, descarte con motivo, Deshacer no desenlaza, hora del
-- celular + analista fijo, 30 días, la llamada la trabaja quien hoy tiene el lead).
--
-- Vocabulario: «analista» (rol técnico `vendedor` de crm.equipo; no se renombra).
--
-- Excepción single-tenant (estándar de 4 capas, F2.3.3): el CRM es de una sola empresa; no hay
-- columna de tenant. El ámbito lo dan crm.equipo y los helpers de private, como en el resto.
--
-- Sin consumidores todavía: ni puertas (F2-c) ni pantalla (F4). RLS activa y SIN policies, sin
-- privilegios para la API (anon, authenticated, service_role): todo acceso llegará por puertas
-- DEFINER con search_path vacío. Auditoría SIN secretos: la purga copia la fila borrada a
-- public.audit_log (que no tiene retención), así que el hash de credencial, el número de teléfono y
-- el hash del payload (que revelaría el número por fuerza bruta) van enmascarados.
--
-- Personas: toda FK hacia public.perfiles o crm.equipo es RESTRICT y tiene su índice. La baja de
-- usuarios (private.usuario_tiene_historial, 20260925180145) detecta el historial por esas FK y
-- conserva la identidad; un SET NULL desatribuiría la llamada. El postflight lo exige.
--
-- Verificación local: npm run test:llamadas:local (banco reducido + oráculo + reversas + mutantes).
--
-- Reversión: ../scripts/llamadas-celular/reversa-datos.sql (conserva los hechos: revoca,
-- desprograma el cron, retira triggers y funciones; las tablas quedan) y
-- ../scripts/llamadas-celular/reversa-datos-total.sql (borra las tablas; se niega si hay filas).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regclass('crm.equipo') is null or to_regclass('crm.leads') is null
     or to_regclass('crm.actividades') is null or to_regclass('public.perfiles') is null
     or to_regclass('public.audit_log') is null
     or to_regprocedure('private.log_audit_crm()') is null
     or to_regprocedure('private.log_audit_sin_secretos()') is null
     or to_regprocedure('private.enmascarar_claves(jsonb,text[])') is null
     or to_regprocedure('private.tablas_sin_rastro()') is null
     or to_regprocedure('private.normalizar_telefono(text)') is null
     or to_regprocedure('private.canonizar_contacto(text)') is null
     or to_regprocedure('private.sla_gestion_permitida(uuid,uuid)') is null
     or to_regprocedure('private.vendedor_ids_visibles(uuid)') is null
     or to_regprocedure('private.rol_crm(uuid)') is null
     or to_regprocedure('auth.uid()') is null then
    raise exception 'LLAMADAS_CELULAR: faltan dependencias del catálogo (equipo, leads, actividades, auditoría, canonización o ámbito)';
  end if;
  if not exists (select 1 from pg_catalog.pg_extension where extname = 'btree_gist') then
    raise exception 'LLAMADAS_CELULAR: falta la extensión btree_gist (la instaló 20260717212639)';
  end if;
  if to_regclass('crm.llamadas_celular_politica') is not null
     or to_regclass('crm.celulares_asignaciones') is not null
     or to_regclass('crm.llamadas_celular_eventos') is not null
     or to_regclass('crm.llamadas_celular_enlaces') is not null
     or to_regprocedure('private.caducar_llamadas_celular()') is not null
     or to_regprocedure('private.trg_llamadas_celular_sin_vaciar()') is not null then
    raise exception 'LLAMADAS_CELULAR: los objetos ya existen; no se sobrescriben';
  end if;
end;
$precondicion$;

-- ── 0. Candado común contra TRUNCATE (por sentencia) ────────────────────────────────────────
create function private.trg_llamadas_celular_sin_vaciar()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  raise exception using errcode = '42501',
    message = pg_catalog.format('%s no se vacía: es evidencia de llamadas', tg_table_name);
end;
$function$;
revoke all on function private.trg_llamadas_celular_sin_vaciar() from public, anon, authenticated, service_role;

-- ── 1. Política (fila única) ─────────────────────────────────────────────────────────────────
create table crm.llamadas_celular_politica (
  singleton                      boolean primary key default true
                                 constraint llamadas_celular_politica_unica check (singleton),
  guardar_sin_identificar        boolean not null default false,
  entrantes_activas              boolean not null default false,
  dias_retencion_descartados     integer not null default 30
                                 constraint llamadas_celular_politica_descartados_rango
                                 check (dias_retencion_descartados between 1 and 365),
  dias_retencion_sin_resolver    integer not null default 30
                                 constraint llamadas_celular_politica_sin_resolver_rango
                                 check (dias_retencion_sin_resolver between 1 and 365),
  dias_retencion_sin_identificar integer not null default 30
                                 constraint llamadas_celular_politica_sin_identificar_rango
                                 check (dias_retencion_sin_identificar between 1 and 365),
  actualizado_por                uuid references public.perfiles(id) on delete restrict,
  creado_en                      timestamptz not null default now(),
  actualizado_en                 timestamptz not null default now()
);
alter table crm.llamadas_celular_politica enable row level security;
revoke all on crm.llamadas_celular_politica from public, anon, authenticated, service_role;
create index llamadas_celular_politica_actualizado_por_idx on crm.llamadas_celular_politica (actualizado_por);

create function private.trg_llamadas_celular_politica_candado()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '42501', message = 'La política de llamadas no se borra: se ajusta';
  end if;
  new.singleton := true;
  new.creado_en := old.creado_en;
  new.actualizado_en := pg_catalog.now();
  return new;
end;
$function$;
revoke all on function private.trg_llamadas_celular_politica_candado() from public, anon, authenticated, service_role;
create trigger trg_llamadas_celular_politica_00_candado
  before update or delete on crm.llamadas_celular_politica
  for each row execute function private.trg_llamadas_celular_politica_candado();
create trigger trg_llamadas_celular_politica_00_sin_vaciar
  before truncate on crm.llamadas_celular_politica
  for each statement execute function private.trg_llamadas_celular_sin_vaciar();
create trigger trg_audit_llamadas_celular_politica
  after insert or update or delete on crm.llamadas_celular_politica
  for each row execute function private.log_audit_crm();

insert into crm.llamadas_celular_politica (singleton) values (true);

-- ── 2. Asignaciones de celulares ─────────────────────────────────────────────────────────────
create table crm.celulares_asignaciones (
  id               uuid primary key default gen_random_uuid(),
  etiqueta         text not null
                   constraint celulares_asignaciones_etiqueta_valida check (etiqueta ~ '^C[1-9][0-9]{0,2}$'),
  analista_id      uuid not null references crm.equipo(perfil_id) on delete restrict,
  credencial_hash  text not null
                   constraint celulares_asignaciones_credencial_hash_valido check (credencial_hash ~ '^[0-9a-f]{64}$'),
  vigente_desde    timestamptz not null default now(),
  vigente_hasta    timestamptz,
  motivo_cierre    text
                   constraint celulares_asignaciones_motivo_cierre_valido
                   check (motivo_cierre is null
                          or motivo_cierre in ('rotacion', 'baja_analista', 'extravio', 'reemplazo', 'otro')),
  creado_por       uuid references public.perfiles(id) on delete restrict,
  creado_en        timestamptz not null default now(),
  actualizado_en   timestamptz not null default now(),
  constraint celulares_asignaciones_vigencia_coherente
    check (vigente_hasta is null or vigente_hasta > vigente_desde),
  constraint celulares_asignaciones_cierre_coherente
    check ((vigente_hasta is null) = (motivo_cierre is null)),
  -- El par de crm.lead_asignaciones: una sola vigencia abierta y ningún solape histórico.
  constraint celulares_asignaciones_sin_solape
    exclude using gist (
      etiqueta with =,
      tstzrange(vigente_desde, coalesce(vigente_hasta, 'infinity'::timestamptz), '[)') with &&
    )
);
alter table crm.celulares_asignaciones enable row level security;
revoke all on crm.celulares_asignaciones from public, anon, authenticated, service_role;
create unique index celulares_asignaciones_etiqueta_vigente_uq
  on crm.celulares_asignaciones (etiqueta) where vigente_hasta is null;
create unique index celulares_asignaciones_credencial_uq
  on crm.celulares_asignaciones (credencial_hash);
create index celulares_asignaciones_analista_idx
  on crm.celulares_asignaciones (analista_id, vigente_desde desc);
create index celulares_asignaciones_creado_por_idx
  on crm.celulares_asignaciones (creado_por);

create function private.trg_celulares_asignaciones_candado()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '42501',
      message = 'Una asignación de celular no se borra: se cierra su vigencia';
  end if;
  if old.vigente_hasta is not null then
    raise exception using errcode = '42501', message = 'Una asignación de celular cerrada es inmutable';
  end if;
  if new.id <> old.id or new.etiqueta <> old.etiqueta or new.analista_id <> old.analista_id
     or new.credencial_hash <> old.credencial_hash or new.vigente_desde <> old.vigente_desde
     or new.creado_por is distinct from old.creado_por or new.creado_en <> old.creado_en then
    raise exception using errcode = '42501',
      message = 'De una asignación de celular solo se cierra la vigencia; lo demás es inmutable';
  end if;
  if new.vigente_hasta is null then
    raise exception using errcode = '22023',
      message = 'Para cambiar una asignación de celular se cierra la vigente y se abre otra';
  end if;
  new.actualizado_en := pg_catalog.now();
  return new;
end;
$function$;
revoke all on function private.trg_celulares_asignaciones_candado() from public, anon, authenticated, service_role;
create trigger trg_celulares_asignaciones_00_candado
  before update or delete on crm.celulares_asignaciones
  for each row execute function private.trg_celulares_asignaciones_candado();
create trigger trg_celulares_asignaciones_00_sin_vaciar
  before truncate on crm.celulares_asignaciones
  for each statement execute function private.trg_llamadas_celular_sin_vaciar();
create trigger trg_audit_celulares_asignaciones
  after insert or update or delete on crm.celulares_asignaciones
  for each row execute function private.log_audit_sin_secretos('credencial_hash');

-- ── 3. Eventos de llamada ────────────────────────────────────────────────────────────────────
create table crm.llamadas_celular_eventos (
  id                      uuid primary key default gen_random_uuid(),
  asignacion_id           uuid not null references crm.celulares_asignaciones(id) on delete restrict,
  analista_id             uuid not null references crm.equipo(perfil_id) on delete restrict,
  evento_origen_id        text not null
                          constraint llamadas_celular_eventos_origen_valido
                          check (evento_origen_id ~ '^[A-Za-z0-9._:+-]{4,120}$'),
  hash_payload            text not null
                          constraint llamadas_celular_eventos_hash_valido check (hash_payload ~ '^[0-9a-f]{64}$'),
  numero_canonico         text
                          constraint llamadas_celular_eventos_numero_e164
                          check (numero_canonico is null or numero_canonico ~ '^\+[1-9][0-9]{7,14}$'),
  direccion               text not null default 'desconocida'
                          constraint llamadas_celular_eventos_direccion_valida
                          check (direccion in ('saliente', 'entrante', 'desconocida')),
  estado_tecnico          text not null default 'desconocido'
                          constraint llamadas_celular_eventos_estado_tecnico_valido
                          check (estado_tecnico in ('conectada', 'no_atendida', 'rechazada', 'cancelada', 'desconocido')),
  duracion_seg            integer
                          constraint llamadas_celular_eventos_duracion_valida
                          check (duracion_seg is null or duracion_seg between 0 and 86400),
  ocurrio_en              timestamptz
                          constraint llamadas_celular_eventos_ocurrio_en_cuerdo
                          check (ocurrio_en is null
                                 or (ocurrio_en >= timestamptz '2026-01-01 00:00Z'
                                     and ocurrio_en < timestamptz '2100-01-01 00:00Z')),
  recibido_en             timestamptz not null default now(),
  calidad                 jsonb not null default '{}'::jsonb
                          constraint llamadas_celular_eventos_calidad_acotada
                          check (jsonb_typeof(calidad) = 'object' and length(calidad::text) <= 2000),
  identificacion          text not null
                          constraint llamadas_celular_eventos_identificacion_valida
                          check (identificacion in ('sin_identificar', 'ambiguo', 'identificado')),
  atencion                text not null
                          constraint llamadas_celular_eventos_atencion_valida
                          check (atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion',
                                              'registrado', 'descartado_con_motivo')),
  lead_id                 uuid references crm.leads(id) on delete cascade,
  metodo_asociacion       text
                          constraint llamadas_celular_eventos_metodo_valido
                          check (metodo_asociacion is null
                                 or metodo_asociacion in ('exacto', 'manual', 'propuesto_confirmado')),
  asociado_por            uuid references public.perfiles(id) on delete restrict,
  asociado_en             timestamptz,
  motivo_descarte         text
                          constraint llamadas_celular_eventos_motivo_descarte_valido
                          check (motivo_descarte is null
                                 or motivo_descarte in ('no_comercial', 'personal', 'numero_de_prueba', 'error_captura', 'otro')),
  motivo_descarte_detalle text
                          constraint llamadas_celular_eventos_detalle_acotado
                          check (motivo_descarte_detalle is null or length(motivo_descarte_detalle) <= 300),
  descartado_por          uuid references public.perfiles(id) on delete restrict,
  descartado_en           timestamptz,
  creado_en               timestamptz not null default now(),
  actualizado_en          timestamptz not null default now(),
  constraint llamadas_celular_eventos_origen_unico unique (asignacion_id, evento_origen_id),
  constraint llamadas_celular_eventos_identificado_con_lead
    check ((identificacion = 'identificado') = (lead_id is not null)),
  constraint llamadas_celular_eventos_asociacion_coherente
    check ((lead_id is null) = (metodo_asociacion is null)
           and (lead_id is null) = (asociado_en is null)
           and (metodo_asociacion is null or metodo_asociacion = 'exacto' or asociado_por is not null)),
  constraint llamadas_celular_eventos_atencion_coherente
    check ((atencion in ('requiere_resultado', 'registrado') and identificacion = 'identificado')
           or (atencion = 'requiere_devolucion' and identificacion = 'identificado' and direccion = 'entrante')
           or atencion in ('por_revisar', 'descartado_con_motivo')),
  constraint llamadas_celular_eventos_descarte_coherente
    check ((atencion = 'descartado_con_motivo') = (motivo_descarte is not null)
           and (atencion = 'descartado_con_motivo') = (descartado_en is not null)
           and (motivo_descarte is distinct from 'otro'
                or length(btrim(coalesce(motivo_descarte_detalle, ''))) >= 3))
);
alter table crm.llamadas_celular_eventos enable row level security;
revoke all on crm.llamadas_celular_eventos from public, anon, authenticated, service_role;
create index llamadas_celular_eventos_analista_atencion_idx
  on crm.llamadas_celular_eventos (analista_id, atencion, recibido_en desc);
create index llamadas_celular_eventos_lead_idx
  on crm.llamadas_celular_eventos (lead_id, recibido_en desc);
create index llamadas_celular_eventos_numero_idx
  on crm.llamadas_celular_eventos (numero_canonico) where numero_canonico is not null;
create index llamadas_celular_eventos_recibido_idx
  on crm.llamadas_celular_eventos (recibido_en);
-- Cada FK con su índice (convención de la casa: sin INFO unindexed_foreign_keys).
create index llamadas_celular_eventos_asociado_por_idx
  on crm.llamadas_celular_eventos (asociado_por);
create index llamadas_celular_eventos_descartado_por_idx
  on crm.llamadas_celular_eventos (descartado_por);

create function private.trg_llamadas_celular_eventos_candado()
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
revoke all on function private.trg_llamadas_celular_eventos_candado() from public, anon, authenticated, service_role;
create trigger trg_llamadas_celular_eventos_00_candado
  before update or delete on crm.llamadas_celular_eventos
  for each row execute function private.trg_llamadas_celular_eventos_candado();
create trigger trg_llamadas_celular_eventos_00_sin_vaciar
  before truncate on crm.llamadas_celular_eventos
  for each statement execute function private.trg_llamadas_celular_sin_vaciar();
-- El hash del payload también se enmascara: con el resto de la fila a la vista, el número es el
-- único dato desconocido y un sha256 de nueve dígitos se revierte por fuerza bruta en segundos.
create trigger trg_audit_llamadas_celular_eventos
  after insert or update or delete on crm.llamadas_celular_eventos
  for each row execute function private.log_audit_sin_secretos('numero_canonico', 'hash_payload');

-- ── 4. Enlace evento ↔ actividad registrada (uno a uno) ─────────────────────────────────────
create table crm.llamadas_celular_enlaces (
  id             uuid primary key default gen_random_uuid(),
  evento_id      uuid not null references crm.llamadas_celular_eventos(id) on delete cascade
                 constraint llamadas_celular_enlaces_evento_uq unique,
  actividad_id   uuid references crm.actividades(id) on delete set null
                 constraint llamadas_celular_enlaces_actividad_uq unique,
  lead_id        uuid not null references crm.leads(id) on delete cascade,
  enlazado_por   uuid references public.perfiles(id) on delete restrict,
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
alter table crm.llamadas_celular_enlaces enable row level security;
revoke all on crm.llamadas_celular_enlaces from public, anon, authenticated, service_role;
create index llamadas_celular_enlaces_lead_idx
  on crm.llamadas_celular_enlaces (lead_id);
create index llamadas_celular_enlaces_enlazado_por_idx
  on crm.llamadas_celular_enlaces (enlazado_por);

create function private.trg_llamadas_celular_enlaces_candado()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_act crm.actividades%rowtype;
  v_ev  crm.llamadas_celular_eventos%rowtype;
  v_deshecha boolean;
begin
  if tg_op = 'DELETE' then
    if pg_catalog.pg_trigger_depth() > 1 then
      return old; -- cascada: se fue el evento o el lead
    end if;
    raise exception using errcode = '42501', message = 'El enlace de una llamada no se borra';
  end if;

  if tg_op = 'UPDATE' then
    -- La actividad se eliminó (cascada del lead → ON DELETE SET NULL): única escritura anidada
    -- aceptada, y solo si no cambia nada más.
    if pg_catalog.pg_trigger_depth() > 1 and new.actividad_id is null and old.actividad_id is not null
       and (pg_catalog.to_jsonb(new) - 'actividad_id' - 'actualizado_en')
         = (pg_catalog.to_jsonb(old) - 'actividad_id' - 'actualizado_en') then
      new.actualizado_en := pg_catalog.now();
      return new;
    end if;
    if new.id <> old.id or new.evento_id <> old.evento_id or new.lead_id <> old.lead_id
       or new.creado_en <> old.creado_en then
      raise exception using errcode = '42501', message = 'El enlace de una llamada no cambia de evento ni de lead';
    end if;
    if new.actividad_id is distinct from old.actividad_id then
      if new.actividad_id is null then
        raise exception using errcode = '42501', message = 'Un enlace no se desenlaza: el resultado deshecho se marca, no se borra';
      end if;
      if old.actividad_id is not null then
        select (a.metadata ? 'deshecho_en') into v_deshecha
        from crm.actividades a where a.id = old.actividad_id;
        if not coalesce(v_deshecha, false) then
          raise exception using errcode = '42501',
            message = 'El enlace solo cambia de actividad si el resultado anterior fue deshecho';
        end if;
      end if;
    end if;
  elsif new.actividad_id is null then
    raise exception using errcode = '22023', message = 'Un enlace nace con la actividad registrada';
  end if;

  if new.actividad_id is not null and (tg_op = 'INSERT' or new.actividad_id is distinct from old.actividad_id) then
    select * into v_act from crm.actividades a where a.id = new.actividad_id;
    if not found then
      raise exception using errcode = '22023', message = 'La actividad enlazada no existe';
    end if;
    if v_act.lead_id <> new.lead_id then
      raise exception using errcode = '22023', message = 'La actividad enlazada es de otro lead';
    end if;
    if v_act.tipo not in ('llamada_realizada', 'llamada_no_contestada')
       or coalesce(v_act.metadata ->> 'evento', '') <> 'resultado_llamada' then
      raise exception using errcode = '22023',
        message = 'Solo se enlaza un resultado de llamada registrado por la encuesta';
    end if;
  end if;

  select * into v_ev from crm.llamadas_celular_eventos e where e.id = new.evento_id;
  if not found then
    raise exception using errcode = '22023', message = 'La llamada enlazada no existe';
  end if;
  if v_ev.lead_id is distinct from new.lead_id then
    raise exception using errcode = '22023', message = 'El enlace debe apuntar al lead de la llamada';
  end if;

  if tg_op = 'UPDATE' then
    new.actualizado_en := pg_catalog.now();
  end if;
  return new;
end;
$function$;
revoke all on function private.trg_llamadas_celular_enlaces_candado() from public, anon, authenticated, service_role;
create trigger trg_llamadas_celular_enlaces_00_candado
  before insert or update or delete on crm.llamadas_celular_enlaces
  for each row execute function private.trg_llamadas_celular_enlaces_candado();
create trigger trg_llamadas_celular_enlaces_00_sin_vaciar
  before truncate on crm.llamadas_celular_enlaces
  for each statement execute function private.trg_llamadas_celular_sin_vaciar();
create trigger trg_audit_llamadas_celular_enlaces
  after insert or update or delete on crm.llamadas_celular_enlaces
  for each row execute function private.log_audit_crm();

-- ── 5. Retención programada ──────────────────────────────────────────────────────────────────
create function private.caducar_llamadas_celular()
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
revoke all on function private.caducar_llamadas_celular() from public, anon, authenticated, service_role;

do $reloj$
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    -- Banco local sin pg_cron: no es un fallo, aquí no hay reloj que programar.
    raise notice 'pg_cron no está disponible: no se programa la retención de llamadas del celular.';
    return;
  end if;
  -- `cron.schedule` reemplaza por nombre: reaplicar es idempotente. 06:23 UTC ≈ 01:23 Lima.
  perform cron.schedule(
    'crm-llamadas-celular-caducidad',
    '23 6 * * *',
    'select private.caducar_llamadas_celular();'
  );
end;
$reloj$;

-- ── 6. Comentarios ───────────────────────────────────────────────────────────────────────────
comment on table crm.llamadas_celular_politica is
  'Perillas del contrato de llamadas desde el celular (F2, decisiones provisionales de Jhosep 30/09/2026, pendientes de Miguel). Fila única. Solo gerencia la ajusta, por puerta (F2-c). Sin columna de tenant: CRM de una sola empresa (excepción documentada).';
comment on column crm.llamadas_celular_politica.singleton is 'Siempre true: garantiza una sola fila.';
comment on column crm.llamadas_celular_politica.guardar_sin_identificar is 'false (decisión 3): una llamada a un número que no es de ningún lead no se guarda; la ingesta responde «ignorado». true: se guarda como sin_identificar y vive dias_retencion_sin_identificar (lo que pide F5 del plan).';
comment on column crm.llamadas_celular_politica.entrantes_activas is 'false (decisión 2, propuesta #8): solo salientes en el piloto; una entrante perdida no pasa a requiere_devolucion.';
comment on column crm.llamadas_celular_politica.dias_retencion_descartados is 'Días que vive una llamada descartada con motivo antes de la purga (30, decisión 6).';
comment on column crm.llamadas_celular_politica.dias_retencion_sin_resolver is 'Días que vive una llamada ambigua (varios leads con el mismo número) que nadie resolvió (30, decisión 6).';
comment on column crm.llamadas_celular_politica.dias_retencion_sin_identificar is 'Días que vive una llamada sin identificar, solo si guardar_sin_identificar está encendida.';
comment on column crm.llamadas_celular_politica.actualizado_por is 'Quién ajustó la política por última vez (perfil de gerencia). FK con RESTRICT: la baja de usuarios (private.usuario_tiene_historial) detecta el historial y conserva la identidad; nunca SET NULL.';
comment on column crm.llamadas_celular_politica.creado_en is 'Sembrada por la migración.';
comment on column crm.llamadas_celular_politica.actualizado_en is 'Último ajuste (lo sella el trigger).';

comment on table crm.celulares_asignaciones is
  'Qué analista tenía cada celular corporativo (C1, C2…) y en qué periodo. Actor histórico de las llamadas: no se sobrescribe; rotar = cerrar la vigencia y abrir otra fila. Una sola vigencia por etiqueta (índice parcial + exclusión por rango). DATO SENSIBLE: credencial_hash (hash de la credencial de ingesta; la clave en claro nunca se guarda). Sin columna de tenant: CRM de una sola empresa.';
comment on column crm.celulares_asignaciones.id is 'Identificador de la asignación.';
comment on column crm.celulares_asignaciones.etiqueta is 'Etiqueta del celular en el piloto: C1, C2… (C + número).';
comment on column crm.celulares_asignaciones.analista_id is 'Analista que tenía el celular (crm.equipo). Histórico e inmutable.';
comment on column crm.celulares_asignaciones.credencial_hash is 'sha256 en hex de la credencial que el celular presenta al ingerir (F3). Única. DATO SENSIBLE: enmascarado en la auditoría.';
comment on column crm.celulares_asignaciones.vigente_desde is 'Inicio de la vigencia.';
comment on column crm.celulares_asignaciones.vigente_hasta is 'Fin de la vigencia; null = vigente. Se fija una sola vez.';
comment on column crm.celulares_asignaciones.motivo_cierre is 'Por qué se cerró: rotacion, baja_analista, extravio, reemplazo u otro. Obligatorio al cerrar.';
comment on column crm.celulares_asignaciones.creado_por is 'Quién asignó el celular (gerencia). FK con RESTRICT: la baja de usuarios detecta el historial y conserva la identidad.';
comment on column crm.celulares_asignaciones.creado_en is 'Alta de la fila.';
comment on column crm.celulares_asignaciones.actualizado_en is 'Último cambio (solo el cierre).';

comment on table crm.llamadas_celular_eventos is
  'Evidencia de cada llamada hecha desde un celular corporativo (F2). Payload inmutable (celular, número E.164, cuándo según el celular y el servidor, dirección, estado técnico, duración, hash) e identidad estable (asignación + id de origen) para la idempotencia. Aparte, lo que cambia con transiciones vigiladas: identificación, atención, lead, método de asociación y descarte motivado. Visibilidad y gestión siguen al lead (quien hoy lo tiene); analista_id conserva quién marcó. DATO PERSONAL: numero_canonico (enmascarado en la auditoría junto con hash_payload, que lo revelaría por fuerza bruta; retención por crm.llamadas_celular_politica). Sin columna de tenant: CRM de una sola empresa.';
comment on column crm.llamadas_celular_eventos.id is 'Identificador del evento.';
comment on column crm.llamadas_celular_eventos.asignacion_id is 'Asignación de celular vigente cuando se recibió (crm.celulares_asignaciones).';
comment on column crm.llamadas_celular_eventos.analista_id is 'Analista que tenía el celular en ese momento (resuelto de la asignación). Histórico: no cambia aunque el lead se reasigne (decisiones 5 y 7).';
comment on column crm.llamadas_celular_eventos.evento_origen_id is 'Identificador estable que genera el celular para esta llamada; con asignacion_id forma la identidad del evento.';
comment on column crm.llamadas_celular_eventos.hash_payload is 'sha256 en hex del payload canónico: mismo origen + mismo hash → mismo evento; distinto hash → conflicto (núcleo, F2-c).';
comment on column crm.llamadas_celular_eventos.numero_canonico is 'Número marcado en E.164 (las dos reglas canónicas del CRM); null si el celular no lo entregó o no es un teléfono. DATO PERSONAL.';
comment on column crm.llamadas_celular_eventos.direccion is 'saliente, entrante o desconocida. En el piloto solo salientes (perilla entrantes_activas).';
comment on column crm.llamadas_celular_eventos.estado_tecnico is 'conectada, no_atendida, rechazada, cancelada o desconocido: lo que el celular supo decir; nunca se infiere del cero.';
comment on column crm.llamadas_celular_eventos.duracion_seg is 'Duración en segundos si el celular la entregó; null = desconocida (cero no prueba nada).';
comment on column crm.llamadas_celular_eventos.ocurrio_en is 'Hora de la llamada según el celular (decisión 5); null si no vino. recibido_en la contrasta.';
comment on column crm.llamadas_celular_eventos.recibido_en is 'Hora del servidor al recibir el evento. SLA y retención se miden con esta.';
comment on column crm.llamadas_celular_eventos.calidad is 'Observaciones acotadas de la ingesta (número inválido u oculto, reloj desfasado…). Objeto JSON ≤ 2000 caracteres.';
comment on column crm.llamadas_celular_eventos.identificacion is 'sin_identificar (ningún lead; solo si la perilla lo permite), ambiguo (varios leads vivos con el número) o identificado (lead_id fijado). Solo avanza.';
comment on column crm.llamadas_celular_eventos.atencion is 'por_revisar, requiere_resultado, requiere_devolucion, registrado o descartado_con_motivo. Las dos últimas son finales; la elegibilidad real se re-evalúa al leer (decisión 1).';
comment on column crm.llamadas_celular_eventos.lead_id is 'Lead al que se asoció la llamada; se fija una vez y solo se corrige mientras está por atender. Se va con el lead si este se elimina.';
comment on column crm.llamadas_celular_eventos.metodo_asociacion is 'exacto (match por número al ingerir), manual (el analista eligió) o propuesto_confirmado (sugerencia aceptada).';
comment on column crm.llamadas_celular_eventos.asociado_por is 'Quién asoció manualmente o confirmó la propuesta; null en el match exacto. FK con RESTRICT: la baja de usuarios detecta el historial y conserva la identidad.';
comment on column crm.llamadas_celular_eventos.asociado_en is 'Cuándo quedó asociada al lead.';
comment on column crm.llamadas_celular_eventos.motivo_descarte is 'Catálogo cerrado (decisión 3): no_comercial, personal, numero_de_prueba, error_captura u otro (con detalle).';
comment on column crm.llamadas_celular_eventos.motivo_descarte_detalle is 'Texto del motivo cuando es otro (≥ 3 caracteres visibles); opcional en los demás.';
comment on column crm.llamadas_celular_eventos.descartado_por is 'Quién descartó la llamada. FK con RESTRICT: la baja de usuarios detecta el historial y conserva la identidad.';
comment on column crm.llamadas_celular_eventos.descartado_en is 'Cuándo se descartó; a partir de aquí corre dias_retencion_descartados.';
comment on column crm.llamadas_celular_eventos.creado_en is 'Alta de la fila (igual a recibido_en salvo cargas históricas).';
comment on column crm.llamadas_celular_eventos.actualizado_en is 'Último cambio de identificación o atención (lo sella el trigger).';

comment on table crm.llamadas_celular_enlaces is
  'Enlace uno a uno entre una llamada del celular y la actividad de llamada que la encuesta registró (tipo llamada_*, metadata.evento = resultado_llamada, mismo lead). Si ese resultado se deshace (metadata.deshecho_en) el enlace puede moverse al resultado corregido; nunca se desenlaza ni se borra a mano. Sin columna de tenant: CRM de una sola empresa.';
comment on column crm.llamadas_celular_enlaces.id is 'Identificador del enlace.';
comment on column crm.llamadas_celular_enlaces.evento_id is 'La llamada enlazada (única: un evento tiene a lo sumo un enlace).';
comment on column crm.llamadas_celular_enlaces.actividad_id is 'La actividad registrada por la encuesta (única entre enlaces). null solo si la actividad se eliminó.';
comment on column crm.llamadas_celular_enlaces.lead_id is 'Lead de la llamada y de la actividad (coinciden por trigger).';
comment on column crm.llamadas_celular_enlaces.enlazado_por is 'Quién registró el resultado que creó o movió el enlace (con ámbito sobre el lead en ese momento). FK con RESTRICT: la baja de usuarios detecta el historial y conserva la identidad.';
comment on column crm.llamadas_celular_enlaces.creado_en is 'Cuándo se enlazó por primera vez.';
comment on column crm.llamadas_celular_enlaces.actualizado_en is 'Último movimiento del enlace (lo sella el trigger).';

comment on function private.trg_llamadas_celular_sin_vaciar() is
  'Candado contra TRUNCATE de las tablas de llamadas del celular. SECURITY DEFINER por coherencia con los demás candados; no lee datos.';
comment on function private.trg_llamadas_celular_politica_candado() is
  'Candado de crm.llamadas_celular_politica: sin DELETE; el UPDATE conserva singleton y creado_en y sella actualizado_en. SECURITY DEFINER por coherencia; no lee datos.';
comment on function private.trg_celulares_asignaciones_candado() is
  'Candado de crm.celulares_asignaciones: sin DELETE; de una asignación abierta solo se cierra la vigencia (vigente_hasta + motivo_cierre); una cerrada es inmutable. SECURITY DEFINER por coherencia; no lee datos.';
comment on function private.trg_llamadas_celular_eventos_candado() is
  'Candado de crm.llamadas_celular_eventos: payload inmutable; identificación que solo avanza; lead fijado una vez (corregible solo por atender); transiciones de atención permitidas y finales; descarte no reescribible; DELETE solo bajo el GUC crm.op_purga_llamadas=on o en cascada. SECURITY DEFINER por coherencia; no lee otras tablas.';
comment on function private.trg_llamadas_celular_enlaces_candado() is
  'Candado de crm.llamadas_celular_enlaces: nace con actividad; la actividad es de llamada, con metadata.evento = resultado_llamada y del mismo lead que la llamada; el enlace cambia de actividad solo si la anterior fue deshecha (metadata.deshecho_en); sin DELETE salvo cascada. SECURITY DEFINER porque lee crm.actividades y crm.llamadas_celular_eventos sin privilegios para la API.';
comment on function private.caducar_llamadas_celular() is
  'Retención de llamadas del celular según crm.llamadas_celular_politica: borra descartadas con motivo, ambiguas sin resolver y sin identificar vencidas; fija el GUC crm.op_purga_llamadas para pasar el candado. La invoca pg_cron (crm-llamadas-celular-caducidad) con auth.uid() nulo; la auditoría conserva la fila con el número enmascarado. SECURITY DEFINER: borra sin privilegios de la API.';

-- ── 7. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_t text;
  v_f record;
  v_n integer;
begin
  foreach v_t in array array['crm.llamadas_celular_politica', 'crm.celulares_asignaciones',
                             'crm.llamadas_celular_eventos', 'crm.llamadas_celular_enlaces'] loop
    if not (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = v_t::regclass) then
      raise exception 'LLAMADAS_CELULAR: % quedó sin RLS', v_t;
    end if;
    if exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol)
               where pg_catalog.has_table_privilege(r.rol, v_t,
                       'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) then
      raise exception 'LLAMADAS_CELULAR: % quedó accesible desde la API', v_t;
    end if;
    if exists (select 1 from pg_catalog.pg_policy p where p.polrelid = v_t::regclass) then
      raise exception 'LLAMADAS_CELULAR: % no debe tener policies (todo va por puertas)', v_t;
    end if;
    if (select count(*) from pg_catalog.pg_trigger t where t.tgrelid = v_t::regclass and not t.tgisinternal) <> 3 then
      raise exception 'LLAMADAS_CELULAR: % no tiene sus 3 triggers (candado, sin vaciar, auditoría)', v_t;
    end if;
    if exists (select 1 from private.tablas_sin_rastro() s where s.tabla = v_t) then
      raise exception 'LLAMADAS_CELULAR: % quedó sin rastro de auditoría válido', v_t;
    end if;
    if pg_catalog.obj_description(v_t::regclass, 'pg_class') is null
       or exists (select 1 from pg_catalog.pg_attribute a
                  where a.attrelid = v_t::regclass and a.attnum > 0 and not a.attisdropped
                    and pg_catalog.col_description(a.attrelid, a.attnum) is null) then
      raise exception 'LLAMADAS_CELULAR: % tiene la tabla o alguna columna sin COMMENT', v_t;
    end if;
  end loop;

  for v_f in
    select * from (values
      ('private.trg_llamadas_celular_sin_vaciar()'),
      ('private.trg_llamadas_celular_politica_candado()'),
      ('private.trg_celulares_asignaciones_candado()'),
      ('private.trg_llamadas_celular_eventos_candado()'),
      ('private.trg_llamadas_celular_enlaces_candado()'),
      ('private.caducar_llamadas_celular()')
    ) as f(firma)
  loop
    if exists (
      select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
      where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner
    ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) then
      raise exception 'LLAMADAS_CELULAR: EXECUTE inesperado en %', v_f.firma;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'LLAMADAS_CELULAR: search_path inesperado en %', v_f.firma;
    end if;
    if pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
      raise exception 'LLAMADAS_CELULAR: % sin COMMENT', v_f.firma;
    end if;
  end loop;

  -- Ninguna FK hacia personas desatribuye: siempre RESTRICT (la baja de usuarios detecta el
  -- historial por estas FK y conserva la identidad; nunca SET NULL ni CASCADE).
  if exists (select 1 from pg_catalog.pg_constraint c
             where c.contype = 'f'
               and c.conrelid in ('crm.llamadas_celular_politica'::regclass, 'crm.celulares_asignaciones'::regclass,
                                  'crm.llamadas_celular_eventos'::regclass, 'crm.llamadas_celular_enlaces'::regclass)
               and c.confrelid in ('public.perfiles'::regclass, 'crm.equipo'::regclass)
               and c.confdeltype <> 'r') then
    raise exception 'LLAMADAS_CELULAR: una FK hacia personas no es RESTRICT';
  end if;
  -- Toda FK con un índice que empiece por sus columnas (convención de la casa).
  if exists (select 1 from pg_catalog.pg_constraint c
             where c.contype = 'f'
               and c.conrelid in ('crm.llamadas_celular_politica'::regclass, 'crm.celulares_asignaciones'::regclass,
                                  'crm.llamadas_celular_eventos'::regclass, 'crm.llamadas_celular_enlaces'::regclass)
               and not exists (
                 select 1 from pg_catalog.pg_index i
                 where i.indrelid = c.conrelid
                   and (pg_catalog.string_to_array(i.indkey::text, ' ')::smallint[])[1:pg_catalog.array_length(c.conkey, 1)]
                       = c.conkey)) then
    raise exception 'LLAMADAS_CELULAR: hay una FK sin índice que la cubra';
  end if;

  if not exists (select 1 from pg_catalog.pg_constraint c
                 where c.conrelid = 'crm.celulares_asignaciones'::regclass
                   and c.conname = 'celulares_asignaciones_sin_solape' and c.contype = 'x') then
    raise exception 'LLAMADAS_CELULAR: falta la exclusión de solape de asignaciones';
  end if;
  if (select count(*) from crm.llamadas_celular_politica) <> 1 then
    raise exception 'LLAMADAS_CELULAR: la política debe tener exactamente una fila';
  end if;
  if to_regprocedure('cron.schedule(text,text,text)') is not null then
    select count(*) into v_n from cron.job j
    where j.jobname = 'crm-llamadas-celular-caducidad' and j.active
      and pg_catalog.strpos(j.command, 'caducar_llamadas_celular') > 0;
    if v_n <> 1 then
      raise exception 'LLAMADAS_CELULAR: la retención quedó con % jobs activos, se esperaba 1', v_n;
    end if;
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;

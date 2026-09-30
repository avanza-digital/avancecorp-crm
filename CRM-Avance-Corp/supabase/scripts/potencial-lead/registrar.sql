-- REGISTRO en supabase_migrations.schema_migrations de 20260930213647_crm_potencial_lead.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega si
-- los objetos no están con su forma (tablas, puerta DEFINER, bandera) o si la versión ya está registrada
-- con otro nombre u otro contenido; relee la fila antes de confirmar. statements = el archivo entero
-- (md5 f4087876c31cccc509db17aa760a4238).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_potencial_lead_registro'));
do $chk$
begin
  if (
    to_regclass('crm.lead_potencial') is not null
    and to_regclass('crm.lead_potencial_eventos') is not null
    and to_regprocedure('private.potencial_bloquear_lead(uuid)') is not null
    and exists (select 1 from pg_proc p where p.oid = to_regprocedure('crm.marcar_potencial_lead_fn(uuid,crm.nivel_potencial)')
                and p.prosecdef and p.proconfig is not null and p.proconfig @> array['search_path=""']::text[])
    and exists (select 1 from crm.multiempresa_flags f where f.nombre = 'potencial_lead')
  ) is not true then
    raise exception 'REGISTRO: la migración 20260930213647 no está aplicada (o no con su forma); aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20260930213647' and (coalesce(name, '') <> 'crm_potencial_lead' or statements is distinct from array[$mig$-- 20260930213647_crm_potencial_lead.sql
--
-- Potencial del lead: Frío · Tibio · Estrella. FASE 1 del plan aprobado por Miguel el
-- 30/09/2026 («HAZLO»). Nota del vault: «Potencial del lead - Frio Tibio Estrella (2026-09-30)».
-- Diseño visual aprobado: pieza CRM-05 del UI Playground.
--
-- QUÉ HACE
--   · Tipo crm.nivel_potencial ('frio','tibio','estrella').
--   · crm.lead_potencial: el nivel VIGENTE de cada lead (una fila por lead, viaja con el lead
--     si se reasigna). Es tabla propia y NO columnas de crm.leads: todo UPDATE de crm.leads
--     pasa por ~20 disparadores y private.leads_before_update reescribe actualizado_en, que es
--     la llave de orden de la cartera (leads_orden_cartera_idx) y despierta el SLA. Marcar no
--     debe reordenar la cartera ni tocar plazos.
--   · crm.lead_potencial_eventos: historial INMUTABLE (solo INSERT) de cada cambio. NO usa
--     crm.actividades: marcar no es una gestión (no reinicia SLA ni suma en métricas).
--   · Puerta crm.marcar_potencial_lead_fn(uuid, crm.nivel_potencial): solo el analista dueño
--     del lead o su supervisor (su subárbol, y el lead parqueado en su bandeja, que solo marca
--     un supervisor). Gerencia, Coordinación, Directorio y cualquier otro rol: 42501. Lead
--     ajeno, inactivo o inexistente: P0002 (no se distingue, para no revelar que existe). Lead
--     convertido o descartado: 22023. Volver a marcar el mismo nivel es válido (reinicia el
--     reloj de la caducidad de la fase 2 y deja su evento), salvo el doble clic: la misma
--     persona, mismo nivel, dentro de 60 s, no escribe nada nuevo.
--   · Bandera 'potencial_lead' en crm.multiempresa_flags, APAGADA: la puerta autoriza y
--     después se niega con 55000 hasta que la fase 3 (pantalla) la encienda.
--
-- CAPAS: puerta DEFINER (sesión, rol, candados, ámbito, bandera; delega) → núcleo
--   private.potencial_marcar_nucleo (INVOKER: estado + evento, atómico) → tablas. Ayudantes
--   privados INVOKER sin EXECUTE para ningún rol de la API: potencial_bloquear_lead (candado
--   consultivo por lead + FOR SHARE de la fila del lead) y potencial_rechazo (ámbito).
-- CONCURRENCIA (Codex r1 F1, r2 R2-1): la autorización decisiva se evalúa DESPUÉS de bloquear la
--   fila del lead (FOR SHARE: una reasignación o un cierre en vuelo termina antes, o espera a que
--   la marca termine); sin fila bloqueada (inexistente o aún sin confirmar) se rechaza. La fase 2
--   (caducidad) debe tomar el MISMO candado consultivo (hashtext('crm.lead_potencial'),
--   hashtext(lead_id)) antes de escribir. Riesgo residual documentado: una baja o un cambio de
--   jerarquía en crm.equipo confirmado en el mismo instante no se serializa con la marca (la marca
--   queda, y el actor ya no puede usarla ni verla).
-- SECURITY DEFINER, justificación: las tablas no dan INSERT/UPDATE a nadie de la API (una
--   marca no se escribe a mano por PostgREST) y la policy leads_update deja pasar a gerencia,
--   que aquí NO marca. La puerta verifica rol y ámbito de forma explícita con private.rol_crm y
--   private.vendedor_ids_visibles, los mismos ayudantes de leads_select/leads_update (el
--   preflight fija su identidad por md5 de cuerpo, DEFINER, volatilidad, configuración y dueño).
-- LECTURA: RLS ON con policy SELECT (exists sobre crm.leads, cuya RLS decide) como segundo
--   candado, pero SIN grant a authenticated: por la regla de 4 capas la pantalla no lee tablas;
--   la fase 3 leerá la marca por una puerta crm.* (auditor-rls r1). anon y service_role: nada.
-- SIN negocio_id: ninguna tabla del esquema crm lo tiene (convención del CRM; la regla de 4
--   capas lo reconoce como deuda del CRM actual). Nombres de tiempo en español (creado_en).
-- REVERSA: supabase/scripts/potencial-lead/reversa.sql (solo con las tablas vacías).

begin;
set local lock_timeout = '5s';

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────
do $preflight$
declare
  v_md5_rol text;
  v_md5_visibles text;
begin
  if (
    pg_catalog.to_regtype('crm.nivel_potencial') is null
    and pg_catalog.to_regclass('crm.lead_potencial') is null
    and pg_catalog.to_regclass('crm.lead_potencial_eventos') is null
    and not exists (
      select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where (n.nspname = 'crm' and p.proname = 'marcar_potencial_lead_fn')
         or (n.nspname = 'private' and p.proname in ('potencial_rechazo', 'potencial_marcar_nucleo',
                                                     'potencial_evento_inmutable', 'potencial_bloquear_lead'))
    )
    and not exists (select 1 from crm.multiempresa_flags f where f.nombre = 'potencial_lead')
  ) is not true then
    raise exception 'PREFLIGHT potencial_lead: ya aplicada o aplicada a medias (hay objetos con estos nombres)';
  end if;

  if (
    pg_catalog.to_regprocedure('private.rol_crm(uuid)') is not null
    and pg_catalog.to_regprocedure('private.vendedor_ids_visibles(uuid)') is not null
    and pg_catalog.to_regprocedure('private.log_audit_crm()') is not null
    and pg_catalog.to_regprocedure('private.set_actualizado_en_crm()') is not null
    and pg_catalog.to_regprocedure('crm.bandera_activa(text)') is not null
  ) is not true then
    raise exception 'PREFLIGHT potencial_lead: falta un ayudante del que depende la migración';
  end if;

  -- La autorización de la puerta descansa en estos dos ayudantes: si cambiaron desde el
  -- ensayo en el banco, la migración se niega y hay que volver a revisarla. Huella de
  -- cuerpo + DEFINER + volatilidad + configuración + dueño: pg_get_functiondef no sirve aquí
  -- porque su texto cambia con el search_path de la sesión (medido en el banco el 30/09).
  select pg_catalog.md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|'
                        || coalesce(pg_catalog.array_to_string(p.proconfig, ','), '') || '|' || p.proowner::pg_catalog.regrole::text)
    into v_md5_rol
  from pg_catalog.pg_proc p where p.oid = 'private.rol_crm(uuid)'::pg_catalog.regprocedure;
  select pg_catalog.md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|'
                        || coalesce(pg_catalog.array_to_string(p.proconfig, ','), '') || '|' || p.proowner::pg_catalog.regrole::text)
    into v_md5_visibles
  from pg_catalog.pg_proc p where p.oid = 'private.vendedor_ids_visibles(uuid)'::pg_catalog.regprocedure;
  if (v_md5_rol = '16960a2a21cc5c372431c2dd67acafe4' and v_md5_visibles = '45ae492c03234b80336c0b8f5c8ac09b') is not true then
    raise exception 'PREFLIGHT potencial_lead: private.rol_crm (%) o private.vendedor_ids_visibles (%) no son los ensayados',
      v_md5_rol, v_md5_visibles;
  end if;
end;
$preflight$;

-- ── 1 · Tipo ───────────────────────────────────────────────────────────────────
create type crm.nivel_potencial as enum ('frio', 'tibio', 'estrella');
comment on type crm.nivel_potencial is
'Potencial comercial de un lead según su analista: frio (pinta mal, aún no se descarta), tibio (vale la pena seguirlo), estrella (máximo potencial). No es la etapa ni el descarte.';

-- ── 2 · Tablas ─────────────────────────────────────────────────────────────────
create table crm.lead_potencial (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references crm.leads(id),
  nivel crm.nivel_potencial not null,
  origen text not null,
  marcado_por uuid not null references public.perfiles(id),
  marcado_en timestamptz not null,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint lead_potencial_lead_unico unique (lead_id),
  constraint lead_potencial_origen_check check (origen in ('manual', 'caducidad')),
  constraint lead_potencial_fechas_finitas check (isfinite(marcado_en) and isfinite(creado_en) and isfinite(actualizado_en))
);
alter table crm.lead_potencial enable row level security;

create table crm.lead_potencial_eventos (
  id uuid primary key default gen_random_uuid(),
  orden bigint generated always as identity,
  lead_id uuid not null references crm.leads(id),
  nivel_anterior crm.nivel_potencial,
  nivel_nuevo crm.nivel_potencial not null,
  motivo text not null,
  por uuid references public.perfiles(id),
  creado_en timestamptz not null default now(),
  constraint lead_potencial_eventos_motivo_check check (motivo in ('manual', 'caducidad')),
  constraint lead_potencial_eventos_autor_check check ((motivo = 'manual') = (por is not null)),
  constraint lead_potencial_eventos_creado_en_finito check (isfinite(creado_en))
);
alter table crm.lead_potencial_eventos enable row level security;

create index lead_potencial_marcado_por_idx on crm.lead_potencial (marcado_por);
create index lead_potencial_nivel_idx on crm.lead_potencial (nivel, lead_id);
create index lead_potencial_eventos_lead_idx on crm.lead_potencial_eventos (lead_id, orden desc);
create index lead_potencial_eventos_por_idx on crm.lead_potencial_eventos (por) where por is not null;

comment on table crm.lead_potencial is
'Nivel VIGENTE de potencial de cada lead (una fila por lead). Solo se escribe por crm.marcar_potencial_lead_fn (y, desde la fase 2, por la caducidad diaria). Tabla propia para no disparar los ~20 disparadores de crm.leads ni reordenar la cartera. Sin grants para la API: se lee por puertas.';
comment on column crm.lead_potencial.id is 'Identificador de la fila.';
comment on column crm.lead_potencial.lead_id is 'Lead marcado. Único: la marca es del lead y viaja con él si se reasigna.';
comment on column crm.lead_potencial.nivel is 'Nivel vigente: frio, tibio o estrella.';
comment on column crm.lead_potencial.origen is 'Quién fijó el nivel vigente: manual (analista o supervisor) o caducidad (bajada automática por días sin gestión, fase 2).';
comment on column crm.lead_potencial.marcado_por is 'Perfil de la última persona que marcó el lead (no cambia con la caducidad).';
comment on column crm.lead_potencial.marcado_en is 'Última marca humana. Junto con la última gestión arranca el reloj de la caducidad.';
comment on column crm.lead_potencial.creado_en is 'Primera marca del lead.';
comment on column crm.lead_potencial.actualizado_en is 'Último cambio de la fila (marca o caducidad).';

comment on table crm.lead_potencial_eventos is
'Historial INMUTABLE de la marca de potencial: cada marca y cada bajada automática. Solo INSERT; UPDATE, DELETE y TRUNCATE se rechazan. No es una gestión: no vive en crm.actividades. Sin grants para la API.';
comment on column crm.lead_potencial_eventos.id is 'Identificador del evento.';
comment on column crm.lead_potencial_eventos.orden is 'Orden total de inserción. creado_en empata dentro de una misma transacción; el historial se ordena por esta columna.';
comment on column crm.lead_potencial_eventos.lead_id is 'Lead al que pertenece el evento.';
comment on column crm.lead_potencial_eventos.nivel_anterior is 'Nivel antes del cambio; null en la primera marca.';
comment on column crm.lead_potencial_eventos.nivel_nuevo is 'Nivel después del cambio (igual al anterior si se volvió a confirmar).';
comment on column crm.lead_potencial_eventos.motivo is 'manual (una persona marcó) o caducidad (bajó sola por días sin gestión).';
comment on column crm.lead_potencial_eventos.por is 'Perfil que marcó; null solo cuando el motivo es caducidad (lo hizo el sistema).';
comment on column crm.lead_potencial_eventos.creado_en is 'Momento del cambio.';

-- ── 3 · RLS: segundo candado de lectura (sin grants hoy) ──────────────────────
create policy lead_potencial_select on crm.lead_potencial
  for select to authenticated
  using (exists (select 1 from crm.leads l where l.id = lead_potencial.lead_id));
comment on policy lead_potencial_select on crm.lead_potencial is
'Segundo candado: si algún día se concede SELECT, ve la marca solo quien ve el lead (el exists corre con la RLS de crm.leads del que consulta).';

create policy lead_potencial_eventos_select on crm.lead_potencial_eventos
  for select to authenticated
  using (exists (select 1 from crm.leads l where l.id = lead_potencial_eventos.lead_id));
comment on policy lead_potencial_eventos_select on crm.lead_potencial_eventos is
'Segundo candado: si algún día se concede SELECT, ve el historial solo quien ve el lead (el exists corre con la RLS de crm.leads del que consulta).';

-- ── 4 · Disparadores: auditoría, updated_at e inmutabilidad del historial ──────
create function private.potencial_evento_inmutable()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  raise exception 'El historial de potencial no se modifica ni se borra' using errcode = 'P0409';
end;
$function$;
comment on function private.potencial_evento_inmutable() is
'Disparador que vuelve inmutable crm.lead_potencial_eventos (UPDATE, DELETE y TRUNCATE).';

create trigger trg_lead_potencial_touch before update on crm.lead_potencial
  for each row execute function private.set_actualizado_en_crm();
create trigger trg_audit_lead_potencial after insert or update or delete on crm.lead_potencial
  for each row execute function private.log_audit_crm();
create trigger lead_potencial_evento_inmutable before update or delete on crm.lead_potencial_eventos
  for each row execute function private.potencial_evento_inmutable();
create trigger lead_potencial_evento_no_truncate before truncate on crm.lead_potencial_eventos
  for each statement execute function private.potencial_evento_inmutable();
create trigger trg_audit_lead_potencial_eventos after insert or update or delete on crm.lead_potencial_eventos
  for each row execute function private.log_audit_crm();

-- ── 5 · Núcleo ─────────────────────────────────────────────────────────────────
create function private.potencial_bloquear_lead(p_lead_id uuid)
returns boolean
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
begin
  -- Orden fijo: primero el candado consultivo del lead (serializa marcas y, en la fase 2, la
  -- caducidad), después la fila del lead en FOR SHARE (una reasignación, cierre o baja en
  -- vuelo termina antes, o espera a que la marca confirme). Ningún otro escritor de crm.leads
  -- toma este consultivo, así que no hay ciclo de espera.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.lead_potencial'), pg_catalog.hashtext(p_lead_id::text));
  perform 1 from crm.leads l where l.id = p_lead_id for share;
  -- Codex r2 R2-1: si no hubo fila que bloquear (inexistente o aún sin confirmar), la puerta
  -- rechaza: nunca autoriza sobre una fila que no quedó bloqueada.
  return found;
end;
$function$;
comment on function private.potencial_bloquear_lead(uuid) is
'Candado de la marca: consultivo por lead (hashtext(''crm.lead_potencial''), hashtext(lead_id)) + FOR SHARE de la fila del lead, hasta el final de la transacción. Devuelve si encontró y bloqueó la fila; sin fila la puerta rechaza. La caducidad (fase 2) debe tomar el mismo consultivo. Sin EXECUTE para la API.';

create function private.potencial_rechazo(p_actor uuid, p_lead_id uuid)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_rol text;
  v_vendedor uuid;
  v_supervisor uuid;
  v_etapa text;
  v_activo boolean;
begin
  v_rol := private.rol_crm(p_actor);
  if (v_rol = 'vendedor' or v_rol = 'supervisor') is not true then
    return 'rol';
  end if;

  select l.vendedor_id, l.asignado_supervisor_id, l.etapa, l.activo
    into v_vendedor, v_supervisor, v_etapa, v_activo
  from crm.leads l
  where l.id = p_lead_id;
  if not found or v_activo is not true then
    return 'ambito';
  end if;

  -- Mismo ámbito que las ramas no-gerencia de leads_update: el dueño (vendedor_ids_visibles
  -- devuelve al analista él mismo y al supervisor su subárbol); y si está parqueado
  -- (vendedor_id null), SOLO un supervisor cuyo subárbol contiene la bandeja.
  if (case
        when v_vendedor is not null then v_vendedor in (select private.vendedor_ids_visibles(p_actor))
        else v_rol = 'supervisor' and v_supervisor in (select private.vendedor_ids_visibles(p_actor))
      end) is not true then
    return 'ambito';
  end if;

  if v_etapa is null or v_etapa in ('convertido', 'descartado') then
    return 'cerrado';
  end if;
  return 'ok';
end;
$function$;
comment on function private.potencial_rechazo(uuid, uuid) is
'Decide si el actor puede marcar el potencial del lead: ok = puede; rol | ambito | cerrado = motivo del rechazo (cualquier otro valor, NULL incluido, se rechaza). Solo vendedor (su lead) o supervisor (su subárbol y su parqueo). Se llama DESPUÉS de private.potencial_bloquear_lead. Sin EXECUTE para la API.';

create function private.potencial_marcar_nucleo(p_actor uuid, p_lead_id uuid, p_nivel crm.nivel_potencial)
returns crm.lead_potencial
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  v_actual crm.lead_potencial;
  v_fila crm.lead_potencial;
  v_ahora timestamptz;
begin
  -- Reentrante: la puerta ya lo tomó; el núcleo no depende de ello.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.lead_potencial'), pg_catalog.hashtext(p_lead_id::text));
  -- Hora REAL, tomada una sola vez y después del candado (Codex r2 R2-4): now() es la hora de
  -- inicio de la transacción y dejaba el antirrebote y marcado_en desordenados entre marcas.
  v_ahora := pg_catalog.clock_timestamp();

  select p.* into v_actual from crm.lead_potencial p where p.lead_id = p_lead_id;

  -- Doble clic: misma persona, mismo nivel, marca manual de hace menos de 60 s → no escribe.
  if v_actual.id is not null and v_actual.nivel = p_nivel and v_actual.origen = 'manual'
     and v_actual.marcado_por = p_actor and v_actual.marcado_en > v_ahora - interval '60 seconds' then
    return v_actual;
  end if;

  insert into crm.lead_potencial as p (lead_id, nivel, origen, marcado_por, marcado_en)
  values (p_lead_id, p_nivel, 'manual', p_actor, v_ahora)
  on conflict (lead_id) do update
    set nivel = excluded.nivel,
        origen = 'manual',
        marcado_por = excluded.marcado_por,
        marcado_en = excluded.marcado_en
  returning p.* into v_fila;

  insert into crm.lead_potencial_eventos (lead_id, nivel_anterior, nivel_nuevo, motivo, por, creado_en)
  values (p_lead_id, v_actual.nivel, p_nivel, 'manual', p_actor, v_ahora);

  return v_fila;
end;
$function$;
comment on function private.potencial_marcar_nucleo(uuid, uuid, crm.nivel_potencial) is
'Operación atómica de marcar: fija el nivel vigente (origen manual, reinicia marcado_en) y deja su evento inmutable; el doble clic (misma persona y nivel en 60 s) no escribe. No autoriza: eso lo hace la puerta. Sin EXECUTE para la API.';

-- ── 6 · Puerta ─────────────────────────────────────────────────────────────────
create function crm.marcar_potencial_lead_fn(p_lead_id uuid, p_nivel crm.nivel_potencial)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_rechazo text;
  v_fila crm.lead_potencial;
begin
  if v_actor is null then
    raise exception 'Sesión requerida' using errcode = '42501';
  end if;
  if p_lead_id is null or p_nivel is null then
    raise exception 'Indica el lead y el nivel de potencial' using errcode = '22023';
  end if;
  -- Rol antes de tomar candados: gerencia y otros roles no bloquean nada ni sondean leads.
  if (private.rol_crm(v_actor) in ('vendedor', 'supervisor')) is not true then
    raise exception 'Solo el analista del lead o su supervisor pueden marcar su potencial' using errcode = '42501';
  end if;

  -- Candados y DESPUÉS la autorización decisiva (Codex r1 F1: sin esto, una reasignación o un
  -- cierre confirmado entre la comprobación y la escritura dejaba marcar con permiso caducado).
  if private.potencial_bloquear_lead(p_lead_id) is not true then
    raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode = 'P0002';
  end if;
  v_rechazo := private.potencial_rechazo(v_actor, p_lead_id);
  if v_rechazo = 'rol' then
    raise exception 'Solo el analista del lead o su supervisor pueden marcar su potencial' using errcode = '42501';
  elsif v_rechazo = 'ambito' then
    raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode = 'P0002';
  elsif v_rechazo = 'cerrado' then
    raise exception 'Un lead convertido o descartado no lleva marca de potencial' using errcode = '22023';
  elsif v_rechazo is distinct from 'ok' then
    raise exception 'Marca de potencial rechazada' using errcode = '42501';
  end if;

  if crm.bandera_activa('potencial_lead') is not true then
    raise exception 'La marca de potencial todavía no está activada' using errcode = '55000';
  end if;

  v_fila := private.potencial_marcar_nucleo(v_actor, p_lead_id, p_nivel);
  return pg_catalog.jsonb_build_object(
    'lead_id', v_fila.lead_id,
    'nivel', v_fila.nivel,
    'origen', v_fila.origen,
    'marcado_por', v_fila.marcado_por,
    'marcado_en', v_fila.marcado_en
  );
end;
$function$;
comment on function crm.marcar_potencial_lead_fn(uuid, crm.nivel_potencial) is
'Puerta: marca el potencial (frio, tibio, estrella) de un lead. Solo el analista dueño o su supervisor; gerencia y demás roles 42501; lead ajeno P0002; cerrado 22023; bandera potencial_lead apagada 55000. Autoriza tras bloquear el lead. Devuelve {lead_id, nivel, origen, marcado_por, marcado_en}.';

-- ── 7 · Bandera (apagada hasta la fase 3) ──────────────────────────────────────
insert into crm.multiempresa_flags (nombre, activo, descripcion)
values ('potencial_lead', false, 'Marca de potencial del lead (Frío, Tibio, Estrella): la puerta crm.marcar_potencial_lead_fn solo escribe con la bandera encendida')
on conflict (nombre) do nothing;

-- ── 8 · Dueños y permisos ──────────────────────────────────────────────────────
alter type crm.nivel_potencial owner to postgres;
alter table crm.lead_potencial owner to postgres;
alter table crm.lead_potencial_eventos owner to postgres;
alter function private.potencial_evento_inmutable() owner to postgres;
alter function private.potencial_bloquear_lead(uuid) owner to postgres;
alter function private.potencial_rechazo(uuid, uuid) owner to postgres;
alter function private.potencial_marcar_nucleo(uuid, uuid, crm.nivel_potencial) owner to postgres;
alter function crm.marcar_potencial_lead_fn(uuid, crm.nivel_potencial) owner to postgres;

revoke all on crm.lead_potencial, crm.lead_potencial_eventos from public, anon, authenticated, service_role;
revoke all on sequence crm.lead_potencial_eventos_orden_seq from public, anon, authenticated, service_role;

revoke all on function private.potencial_evento_inmutable() from public, anon, authenticated, service_role;
revoke all on function private.potencial_bloquear_lead(uuid) from public, anon, authenticated, service_role;
revoke all on function private.potencial_rechazo(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function private.potencial_marcar_nucleo(uuid, uuid, crm.nivel_potencial) from public, anon, authenticated, service_role;
revoke all on function crm.marcar_potencial_lead_fn(uuid, crm.nivel_potencial) from public, anon, authenticated, service_role;
grant execute on function crm.marcar_potencial_lead_fn(uuid, crm.nivel_potencial) to authenticated;

-- ── 9 · Postflight ─────────────────────────────────────────────────────────────
do $postflight$
declare
  v_puerta pg_catalog.regprocedure := 'crm.marcar_potencial_lead_fn(uuid,crm.nivel_potencial)'::pg_catalog.regprocedure;
  v_privadas pg_catalog.regprocedure[] := array[
    'private.potencial_evento_inmutable()'::pg_catalog.regprocedure,
    'private.potencial_bloquear_lead(uuid)'::pg_catalog.regprocedure,
    'private.potencial_rechazo(uuid,uuid)'::pg_catalog.regprocedure,
    'private.potencial_marcar_nucleo(uuid,uuid,crm.nivel_potencial)'::pg_catalog.regprocedure
  ];
  v_objetos pg_catalog.regclass[] := array[
    'crm.lead_potencial'::pg_catalog.regclass,
    'crm.lead_potencial_eventos'::pg_catalog.regclass,
    'crm.lead_potencial_eventos_orden_seq'::pg_catalog.regclass
  ];
  v_disparadores text;
  v_policies text;
begin
  -- Texto de catálogo independiente de la sesión: todo calificado (Codex r1 F5).
  perform pg_catalog.set_config('search_path', '', true);

  -- Puerta: DEFINER, dueño postgres, search_path vacío, lock_timeout, EXECUTE solo authenticated.
  if (
    exists (
      select 1 from pg_catalog.pg_proc p
      where p.oid = v_puerta and p.prosecdef and p.proowner = 'postgres'::pg_catalog.regrole
        and p.provolatile = 'v'
        and p.proconfig is not null
        and p.proconfig @> array['search_path=""', 'lock_timeout=5s']::text[]
        and p.proacl is not null
    )
    and not exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                    where p.oid = v_puerta
                      and a.grantee not in ('postgres'::pg_catalog.regrole, 'authenticated'::pg_catalog.regrole))
    and exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                where p.oid = v_puerta and a.privilege_type = 'EXECUTE' and a.grantee = 'authenticated'::pg_catalog.regrole)
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lead: la puerta no quedó DEFINER/postgres/search_path vacío/EXECUTE solo authenticated';
  end if;

  -- Privadas: INVOKER, dueño postgres, search_path vacío y ACL explícita solo de postgres.
  if (
    (select count(*) from pg_catalog.pg_proc p
      where p.oid = any (v_privadas) and not p.prosecdef and p.proowner = 'postgres'::pg_catalog.regrole
        and p.proconfig is not null and p.proconfig @> array['search_path=""']::text[]
        and p.proacl is not null) = 4
    and not exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                    where p.oid = any (v_privadas) and a.grantee <> 'postgres'::pg_catalog.regrole)
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lead: los ayudantes privados no quedaron INVOKER/search_path vacío/sin EXECUTE para la API';
  end if;

  -- Tablas y secuencia: dueño postgres y ACL en LISTA BLANCA (solo postgres), RLS activa en
  -- las dos tablas; tipo con dueño postgres. Permisos EFECTIVOS de la API en cero (herencia
  -- incluida).
  if (
    (select count(*) from pg_catalog.pg_class c
      where c.oid = any (v_objetos) and c.relowner = 'postgres'::pg_catalog.regrole and c.relacl is not null) = 3
    and not exists (select 1 from pg_catalog.pg_class c, pg_catalog.aclexplode(c.relacl) a
                    where c.oid = any (v_objetos) and a.grantee <> 'postgres'::pg_catalog.regrole)
    and (select count(*) from pg_catalog.pg_class c
          where c.oid in ('crm.lead_potencial'::pg_catalog.regclass, 'crm.lead_potencial_eventos'::pg_catalog.regclass)
            and c.relrowsecurity) = 2
    and (select t.typowner from pg_catalog.pg_type t where t.oid = 'crm.nivel_potencial'::pg_catalog.regtype) = 'postgres'::pg_catalog.regrole
    and not exists (
      select 1
      from unnest(array['anon', 'authenticated', 'service_role']) r(rol),
           unnest(array['crm.lead_potencial', 'crm.lead_potencial_eventos']) t(tabla),
           unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) x(priv)
      where pg_catalog.has_table_privilege(r.rol, t.tabla, x.priv)
    )
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lead: dueño, ACL, RLS o permisos efectivos de tablas, secuencia o tipo no son los previstos';
  end if;

  -- Policies exactas: una SELECT por tabla, para authenticated, con su exists (Codex r1 F5).
  select string_agg(pp.tablename || '|' || pp.cmd || '|' || pp.roles::text || '|'
                    || pg_catalog.regexp_replace(coalesce(pp.qual, ''), '\s+', ' ', 'g') || '|' || coalesce(pp.with_check, ''),
                    ' ## ' order by pp.tablename)
    into v_policies
  from pg_catalog.pg_policies pp
  where pp.schemaname = 'crm' and pp.tablename in ('lead_potencial', 'lead_potencial_eventos');
  if (v_policies = 'lead_potencial|SELECT|{authenticated}|(EXISTS ( SELECT 1 FROM crm.leads l WHERE (l.id = lead_potencial.lead_id)))|'
                 || ' ## lead_potencial_eventos|SELECT|{authenticated}|(EXISTS ( SELECT 1 FROM crm.leads l WHERE (l.id = lead_potencial_eventos.lead_id)))|') is not true then
    raise exception 'POSTFLIGHT potencial_lead: policies inesperadas: %', coalesce(v_policies, '(ninguna)');
  end if;

  -- Disparadores exactos (momento, eventos, nivel y función) y activos para sesiones normales.
  select string_agg(pg_catalog.pg_get_triggerdef(t.oid) || ' [' || t.tgenabled::text || ']', ' ## ' order by t.tgname)
    into v_disparadores
  from pg_catalog.pg_trigger t
  where t.tgrelid in ('crm.lead_potencial'::pg_catalog.regclass, 'crm.lead_potencial_eventos'::pg_catalog.regclass)
    and not t.tgisinternal;
  if (v_disparadores =
        'CREATE TRIGGER lead_potencial_evento_inmutable BEFORE DELETE OR UPDATE ON crm.lead_potencial_eventos FOR EACH ROW EXECUTE FUNCTION private.potencial_evento_inmutable() [O]'
     || ' ## CREATE TRIGGER lead_potencial_evento_no_truncate BEFORE TRUNCATE ON crm.lead_potencial_eventos FOR EACH STATEMENT EXECUTE FUNCTION private.potencial_evento_inmutable() [O]'
     || ' ## CREATE TRIGGER trg_audit_lead_potencial AFTER INSERT OR DELETE OR UPDATE ON crm.lead_potencial FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm() [O]'
     || ' ## CREATE TRIGGER trg_audit_lead_potencial_eventos AFTER INSERT OR DELETE OR UPDATE ON crm.lead_potencial_eventos FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm() [O]'
     || ' ## CREATE TRIGGER trg_lead_potencial_touch BEFORE UPDATE ON crm.lead_potencial FOR EACH ROW EXECUTE FUNCTION private.set_actualizado_en_crm() [O]'
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lead: disparadores inesperados: %', coalesce(v_disparadores, '(ninguno)');
  end if;

  -- Bandera creada y apagada.
  if (select f.activo from crm.multiempresa_flags f where f.nombre = 'potencial_lead') is distinct from false then
    raise exception 'POSTFLIGHT potencial_lead: la bandera potencial_lead no quedó creada y apagada';
  end if;

  raise notice 'potencial_lead OK: tipo, 2 tablas (RLS, sin grants API), núcleo INVOKER con candado, puerta DEFINER solo authenticated, bandera apagada.';
end;
$postflight$;

commit;
$mig$])) then
    raise exception 'REGISTRO: la versión 20260930213647 ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260930213647', 'crm_potencial_lead', array[$mig$-- 20260930213647_crm_potencial_lead.sql
--
-- Potencial del lead: Frío · Tibio · Estrella. FASE 1 del plan aprobado por Miguel el
-- 30/09/2026 («HAZLO»). Nota del vault: «Potencial del lead - Frio Tibio Estrella (2026-09-30)».
-- Diseño visual aprobado: pieza CRM-05 del UI Playground.
--
-- QUÉ HACE
--   · Tipo crm.nivel_potencial ('frio','tibio','estrella').
--   · crm.lead_potencial: el nivel VIGENTE de cada lead (una fila por lead, viaja con el lead
--     si se reasigna). Es tabla propia y NO columnas de crm.leads: todo UPDATE de crm.leads
--     pasa por ~20 disparadores y private.leads_before_update reescribe actualizado_en, que es
--     la llave de orden de la cartera (leads_orden_cartera_idx) y despierta el SLA. Marcar no
--     debe reordenar la cartera ni tocar plazos.
--   · crm.lead_potencial_eventos: historial INMUTABLE (solo INSERT) de cada cambio. NO usa
--     crm.actividades: marcar no es una gestión (no reinicia SLA ni suma en métricas).
--   · Puerta crm.marcar_potencial_lead_fn(uuid, crm.nivel_potencial): solo el analista dueño
--     del lead o su supervisor (su subárbol, y el lead parqueado en su bandeja, que solo marca
--     un supervisor). Gerencia, Coordinación, Directorio y cualquier otro rol: 42501. Lead
--     ajeno, inactivo o inexistente: P0002 (no se distingue, para no revelar que existe). Lead
--     convertido o descartado: 22023. Volver a marcar el mismo nivel es válido (reinicia el
--     reloj de la caducidad de la fase 2 y deja su evento), salvo el doble clic: la misma
--     persona, mismo nivel, dentro de 60 s, no escribe nada nuevo.
--   · Bandera 'potencial_lead' en crm.multiempresa_flags, APAGADA: la puerta autoriza y
--     después se niega con 55000 hasta que la fase 3 (pantalla) la encienda.
--
-- CAPAS: puerta DEFINER (sesión, rol, candados, ámbito, bandera; delega) → núcleo
--   private.potencial_marcar_nucleo (INVOKER: estado + evento, atómico) → tablas. Ayudantes
--   privados INVOKER sin EXECUTE para ningún rol de la API: potencial_bloquear_lead (candado
--   consultivo por lead + FOR SHARE de la fila del lead) y potencial_rechazo (ámbito).
-- CONCURRENCIA (Codex r1 F1, r2 R2-1): la autorización decisiva se evalúa DESPUÉS de bloquear la
--   fila del lead (FOR SHARE: una reasignación o un cierre en vuelo termina antes, o espera a que
--   la marca termine); sin fila bloqueada (inexistente o aún sin confirmar) se rechaza. La fase 2
--   (caducidad) debe tomar el MISMO candado consultivo (hashtext('crm.lead_potencial'),
--   hashtext(lead_id)) antes de escribir. Riesgo residual documentado: una baja o un cambio de
--   jerarquía en crm.equipo confirmado en el mismo instante no se serializa con la marca (la marca
--   queda, y el actor ya no puede usarla ni verla).
-- SECURITY DEFINER, justificación: las tablas no dan INSERT/UPDATE a nadie de la API (una
--   marca no se escribe a mano por PostgREST) y la policy leads_update deja pasar a gerencia,
--   que aquí NO marca. La puerta verifica rol y ámbito de forma explícita con private.rol_crm y
--   private.vendedor_ids_visibles, los mismos ayudantes de leads_select/leads_update (el
--   preflight fija su identidad por md5 de cuerpo, DEFINER, volatilidad, configuración y dueño).
-- LECTURA: RLS ON con policy SELECT (exists sobre crm.leads, cuya RLS decide) como segundo
--   candado, pero SIN grant a authenticated: por la regla de 4 capas la pantalla no lee tablas;
--   la fase 3 leerá la marca por una puerta crm.* (auditor-rls r1). anon y service_role: nada.
-- SIN negocio_id: ninguna tabla del esquema crm lo tiene (convención del CRM; la regla de 4
--   capas lo reconoce como deuda del CRM actual). Nombres de tiempo en español (creado_en).
-- REVERSA: supabase/scripts/potencial-lead/reversa.sql (solo con las tablas vacías).

begin;
set local lock_timeout = '5s';

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────
do $preflight$
declare
  v_md5_rol text;
  v_md5_visibles text;
begin
  if (
    pg_catalog.to_regtype('crm.nivel_potencial') is null
    and pg_catalog.to_regclass('crm.lead_potencial') is null
    and pg_catalog.to_regclass('crm.lead_potencial_eventos') is null
    and not exists (
      select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where (n.nspname = 'crm' and p.proname = 'marcar_potencial_lead_fn')
         or (n.nspname = 'private' and p.proname in ('potencial_rechazo', 'potencial_marcar_nucleo',
                                                     'potencial_evento_inmutable', 'potencial_bloquear_lead'))
    )
    and not exists (select 1 from crm.multiempresa_flags f where f.nombre = 'potencial_lead')
  ) is not true then
    raise exception 'PREFLIGHT potencial_lead: ya aplicada o aplicada a medias (hay objetos con estos nombres)';
  end if;

  if (
    pg_catalog.to_regprocedure('private.rol_crm(uuid)') is not null
    and pg_catalog.to_regprocedure('private.vendedor_ids_visibles(uuid)') is not null
    and pg_catalog.to_regprocedure('private.log_audit_crm()') is not null
    and pg_catalog.to_regprocedure('private.set_actualizado_en_crm()') is not null
    and pg_catalog.to_regprocedure('crm.bandera_activa(text)') is not null
  ) is not true then
    raise exception 'PREFLIGHT potencial_lead: falta un ayudante del que depende la migración';
  end if;

  -- La autorización de la puerta descansa en estos dos ayudantes: si cambiaron desde el
  -- ensayo en el banco, la migración se niega y hay que volver a revisarla. Huella de
  -- cuerpo + DEFINER + volatilidad + configuración + dueño: pg_get_functiondef no sirve aquí
  -- porque su texto cambia con el search_path de la sesión (medido en el banco el 30/09).
  select pg_catalog.md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|'
                        || coalesce(pg_catalog.array_to_string(p.proconfig, ','), '') || '|' || p.proowner::pg_catalog.regrole::text)
    into v_md5_rol
  from pg_catalog.pg_proc p where p.oid = 'private.rol_crm(uuid)'::pg_catalog.regprocedure;
  select pg_catalog.md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|'
                        || coalesce(pg_catalog.array_to_string(p.proconfig, ','), '') || '|' || p.proowner::pg_catalog.regrole::text)
    into v_md5_visibles
  from pg_catalog.pg_proc p where p.oid = 'private.vendedor_ids_visibles(uuid)'::pg_catalog.regprocedure;
  if (v_md5_rol = '16960a2a21cc5c372431c2dd67acafe4' and v_md5_visibles = '45ae492c03234b80336c0b8f5c8ac09b') is not true then
    raise exception 'PREFLIGHT potencial_lead: private.rol_crm (%) o private.vendedor_ids_visibles (%) no son los ensayados',
      v_md5_rol, v_md5_visibles;
  end if;
end;
$preflight$;

-- ── 1 · Tipo ───────────────────────────────────────────────────────────────────
create type crm.nivel_potencial as enum ('frio', 'tibio', 'estrella');
comment on type crm.nivel_potencial is
'Potencial comercial de un lead según su analista: frio (pinta mal, aún no se descarta), tibio (vale la pena seguirlo), estrella (máximo potencial). No es la etapa ni el descarte.';

-- ── 2 · Tablas ─────────────────────────────────────────────────────────────────
create table crm.lead_potencial (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references crm.leads(id),
  nivel crm.nivel_potencial not null,
  origen text not null,
  marcado_por uuid not null references public.perfiles(id),
  marcado_en timestamptz not null,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint lead_potencial_lead_unico unique (lead_id),
  constraint lead_potencial_origen_check check (origen in ('manual', 'caducidad')),
  constraint lead_potencial_fechas_finitas check (isfinite(marcado_en) and isfinite(creado_en) and isfinite(actualizado_en))
);
alter table crm.lead_potencial enable row level security;

create table crm.lead_potencial_eventos (
  id uuid primary key default gen_random_uuid(),
  orden bigint generated always as identity,
  lead_id uuid not null references crm.leads(id),
  nivel_anterior crm.nivel_potencial,
  nivel_nuevo crm.nivel_potencial not null,
  motivo text not null,
  por uuid references public.perfiles(id),
  creado_en timestamptz not null default now(),
  constraint lead_potencial_eventos_motivo_check check (motivo in ('manual', 'caducidad')),
  constraint lead_potencial_eventos_autor_check check ((motivo = 'manual') = (por is not null)),
  constraint lead_potencial_eventos_creado_en_finito check (isfinite(creado_en))
);
alter table crm.lead_potencial_eventos enable row level security;

create index lead_potencial_marcado_por_idx on crm.lead_potencial (marcado_por);
create index lead_potencial_nivel_idx on crm.lead_potencial (nivel, lead_id);
create index lead_potencial_eventos_lead_idx on crm.lead_potencial_eventos (lead_id, orden desc);
create index lead_potencial_eventos_por_idx on crm.lead_potencial_eventos (por) where por is not null;

comment on table crm.lead_potencial is
'Nivel VIGENTE de potencial de cada lead (una fila por lead). Solo se escribe por crm.marcar_potencial_lead_fn (y, desde la fase 2, por la caducidad diaria). Tabla propia para no disparar los ~20 disparadores de crm.leads ni reordenar la cartera. Sin grants para la API: se lee por puertas.';
comment on column crm.lead_potencial.id is 'Identificador de la fila.';
comment on column crm.lead_potencial.lead_id is 'Lead marcado. Único: la marca es del lead y viaja con él si se reasigna.';
comment on column crm.lead_potencial.nivel is 'Nivel vigente: frio, tibio o estrella.';
comment on column crm.lead_potencial.origen is 'Quién fijó el nivel vigente: manual (analista o supervisor) o caducidad (bajada automática por días sin gestión, fase 2).';
comment on column crm.lead_potencial.marcado_por is 'Perfil de la última persona que marcó el lead (no cambia con la caducidad).';
comment on column crm.lead_potencial.marcado_en is 'Última marca humana. Junto con la última gestión arranca el reloj de la caducidad.';
comment on column crm.lead_potencial.creado_en is 'Primera marca del lead.';
comment on column crm.lead_potencial.actualizado_en is 'Último cambio de la fila (marca o caducidad).';

comment on table crm.lead_potencial_eventos is
'Historial INMUTABLE de la marca de potencial: cada marca y cada bajada automática. Solo INSERT; UPDATE, DELETE y TRUNCATE se rechazan. No es una gestión: no vive en crm.actividades. Sin grants para la API.';
comment on column crm.lead_potencial_eventos.id is 'Identificador del evento.';
comment on column crm.lead_potencial_eventos.orden is 'Orden total de inserción. creado_en empata dentro de una misma transacción; el historial se ordena por esta columna.';
comment on column crm.lead_potencial_eventos.lead_id is 'Lead al que pertenece el evento.';
comment on column crm.lead_potencial_eventos.nivel_anterior is 'Nivel antes del cambio; null en la primera marca.';
comment on column crm.lead_potencial_eventos.nivel_nuevo is 'Nivel después del cambio (igual al anterior si se volvió a confirmar).';
comment on column crm.lead_potencial_eventos.motivo is 'manual (una persona marcó) o caducidad (bajó sola por días sin gestión).';
comment on column crm.lead_potencial_eventos.por is 'Perfil que marcó; null solo cuando el motivo es caducidad (lo hizo el sistema).';
comment on column crm.lead_potencial_eventos.creado_en is 'Momento del cambio.';

-- ── 3 · RLS: segundo candado de lectura (sin grants hoy) ──────────────────────
create policy lead_potencial_select on crm.lead_potencial
  for select to authenticated
  using (exists (select 1 from crm.leads l where l.id = lead_potencial.lead_id));
comment on policy lead_potencial_select on crm.lead_potencial is
'Segundo candado: si algún día se concede SELECT, ve la marca solo quien ve el lead (el exists corre con la RLS de crm.leads del que consulta).';

create policy lead_potencial_eventos_select on crm.lead_potencial_eventos
  for select to authenticated
  using (exists (select 1 from crm.leads l where l.id = lead_potencial_eventos.lead_id));
comment on policy lead_potencial_eventos_select on crm.lead_potencial_eventos is
'Segundo candado: si algún día se concede SELECT, ve el historial solo quien ve el lead (el exists corre con la RLS de crm.leads del que consulta).';

-- ── 4 · Disparadores: auditoría, updated_at e inmutabilidad del historial ──────
create function private.potencial_evento_inmutable()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  raise exception 'El historial de potencial no se modifica ni se borra' using errcode = 'P0409';
end;
$function$;
comment on function private.potencial_evento_inmutable() is
'Disparador que vuelve inmutable crm.lead_potencial_eventos (UPDATE, DELETE y TRUNCATE).';

create trigger trg_lead_potencial_touch before update on crm.lead_potencial
  for each row execute function private.set_actualizado_en_crm();
create trigger trg_audit_lead_potencial after insert or update or delete on crm.lead_potencial
  for each row execute function private.log_audit_crm();
create trigger lead_potencial_evento_inmutable before update or delete on crm.lead_potencial_eventos
  for each row execute function private.potencial_evento_inmutable();
create trigger lead_potencial_evento_no_truncate before truncate on crm.lead_potencial_eventos
  for each statement execute function private.potencial_evento_inmutable();
create trigger trg_audit_lead_potencial_eventos after insert or update or delete on crm.lead_potencial_eventos
  for each row execute function private.log_audit_crm();

-- ── 5 · Núcleo ─────────────────────────────────────────────────────────────────
create function private.potencial_bloquear_lead(p_lead_id uuid)
returns boolean
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
begin
  -- Orden fijo: primero el candado consultivo del lead (serializa marcas y, en la fase 2, la
  -- caducidad), después la fila del lead en FOR SHARE (una reasignación, cierre o baja en
  -- vuelo termina antes, o espera a que la marca confirme). Ningún otro escritor de crm.leads
  -- toma este consultivo, así que no hay ciclo de espera.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.lead_potencial'), pg_catalog.hashtext(p_lead_id::text));
  perform 1 from crm.leads l where l.id = p_lead_id for share;
  -- Codex r2 R2-1: si no hubo fila que bloquear (inexistente o aún sin confirmar), la puerta
  -- rechaza: nunca autoriza sobre una fila que no quedó bloqueada.
  return found;
end;
$function$;
comment on function private.potencial_bloquear_lead(uuid) is
'Candado de la marca: consultivo por lead (hashtext(''crm.lead_potencial''), hashtext(lead_id)) + FOR SHARE de la fila del lead, hasta el final de la transacción. Devuelve si encontró y bloqueó la fila; sin fila la puerta rechaza. La caducidad (fase 2) debe tomar el mismo consultivo. Sin EXECUTE para la API.';

create function private.potencial_rechazo(p_actor uuid, p_lead_id uuid)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_rol text;
  v_vendedor uuid;
  v_supervisor uuid;
  v_etapa text;
  v_activo boolean;
begin
  v_rol := private.rol_crm(p_actor);
  if (v_rol = 'vendedor' or v_rol = 'supervisor') is not true then
    return 'rol';
  end if;

  select l.vendedor_id, l.asignado_supervisor_id, l.etapa, l.activo
    into v_vendedor, v_supervisor, v_etapa, v_activo
  from crm.leads l
  where l.id = p_lead_id;
  if not found or v_activo is not true then
    return 'ambito';
  end if;

  -- Mismo ámbito que las ramas no-gerencia de leads_update: el dueño (vendedor_ids_visibles
  -- devuelve al analista él mismo y al supervisor su subárbol); y si está parqueado
  -- (vendedor_id null), SOLO un supervisor cuyo subárbol contiene la bandeja.
  if (case
        when v_vendedor is not null then v_vendedor in (select private.vendedor_ids_visibles(p_actor))
        else v_rol = 'supervisor' and v_supervisor in (select private.vendedor_ids_visibles(p_actor))
      end) is not true then
    return 'ambito';
  end if;

  if v_etapa is null or v_etapa in ('convertido', 'descartado') then
    return 'cerrado';
  end if;
  return 'ok';
end;
$function$;
comment on function private.potencial_rechazo(uuid, uuid) is
'Decide si el actor puede marcar el potencial del lead: ok = puede; rol | ambito | cerrado = motivo del rechazo (cualquier otro valor, NULL incluido, se rechaza). Solo vendedor (su lead) o supervisor (su subárbol y su parqueo). Se llama DESPUÉS de private.potencial_bloquear_lead. Sin EXECUTE para la API.';

create function private.potencial_marcar_nucleo(p_actor uuid, p_lead_id uuid, p_nivel crm.nivel_potencial)
returns crm.lead_potencial
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  v_actual crm.lead_potencial;
  v_fila crm.lead_potencial;
  v_ahora timestamptz;
begin
  -- Reentrante: la puerta ya lo tomó; el núcleo no depende de ello.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.lead_potencial'), pg_catalog.hashtext(p_lead_id::text));
  -- Hora REAL, tomada una sola vez y después del candado (Codex r2 R2-4): now() es la hora de
  -- inicio de la transacción y dejaba el antirrebote y marcado_en desordenados entre marcas.
  v_ahora := pg_catalog.clock_timestamp();

  select p.* into v_actual from crm.lead_potencial p where p.lead_id = p_lead_id;

  -- Doble clic: misma persona, mismo nivel, marca manual de hace menos de 60 s → no escribe.
  if v_actual.id is not null and v_actual.nivel = p_nivel and v_actual.origen = 'manual'
     and v_actual.marcado_por = p_actor and v_actual.marcado_en > v_ahora - interval '60 seconds' then
    return v_actual;
  end if;

  insert into crm.lead_potencial as p (lead_id, nivel, origen, marcado_por, marcado_en)
  values (p_lead_id, p_nivel, 'manual', p_actor, v_ahora)
  on conflict (lead_id) do update
    set nivel = excluded.nivel,
        origen = 'manual',
        marcado_por = excluded.marcado_por,
        marcado_en = excluded.marcado_en
  returning p.* into v_fila;

  insert into crm.lead_potencial_eventos (lead_id, nivel_anterior, nivel_nuevo, motivo, por, creado_en)
  values (p_lead_id, v_actual.nivel, p_nivel, 'manual', p_actor, v_ahora);

  return v_fila;
end;
$function$;
comment on function private.potencial_marcar_nucleo(uuid, uuid, crm.nivel_potencial) is
'Operación atómica de marcar: fija el nivel vigente (origen manual, reinicia marcado_en) y deja su evento inmutable; el doble clic (misma persona y nivel en 60 s) no escribe. No autoriza: eso lo hace la puerta. Sin EXECUTE para la API.';

-- ── 6 · Puerta ─────────────────────────────────────────────────────────────────
create function crm.marcar_potencial_lead_fn(p_lead_id uuid, p_nivel crm.nivel_potencial)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_rechazo text;
  v_fila crm.lead_potencial;
begin
  if v_actor is null then
    raise exception 'Sesión requerida' using errcode = '42501';
  end if;
  if p_lead_id is null or p_nivel is null then
    raise exception 'Indica el lead y el nivel de potencial' using errcode = '22023';
  end if;
  -- Rol antes de tomar candados: gerencia y otros roles no bloquean nada ni sondean leads.
  if (private.rol_crm(v_actor) in ('vendedor', 'supervisor')) is not true then
    raise exception 'Solo el analista del lead o su supervisor pueden marcar su potencial' using errcode = '42501';
  end if;

  -- Candados y DESPUÉS la autorización decisiva (Codex r1 F1: sin esto, una reasignación o un
  -- cierre confirmado entre la comprobación y la escritura dejaba marcar con permiso caducado).
  if private.potencial_bloquear_lead(p_lead_id) is not true then
    raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode = 'P0002';
  end if;
  v_rechazo := private.potencial_rechazo(v_actor, p_lead_id);
  if v_rechazo = 'rol' then
    raise exception 'Solo el analista del lead o su supervisor pueden marcar su potencial' using errcode = '42501';
  elsif v_rechazo = 'ambito' then
    raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode = 'P0002';
  elsif v_rechazo = 'cerrado' then
    raise exception 'Un lead convertido o descartado no lleva marca de potencial' using errcode = '22023';
  elsif v_rechazo is distinct from 'ok' then
    raise exception 'Marca de potencial rechazada' using errcode = '42501';
  end if;

  if crm.bandera_activa('potencial_lead') is not true then
    raise exception 'La marca de potencial todavía no está activada' using errcode = '55000';
  end if;

  v_fila := private.potencial_marcar_nucleo(v_actor, p_lead_id, p_nivel);
  return pg_catalog.jsonb_build_object(
    'lead_id', v_fila.lead_id,
    'nivel', v_fila.nivel,
    'origen', v_fila.origen,
    'marcado_por', v_fila.marcado_por,
    'marcado_en', v_fila.marcado_en
  );
end;
$function$;
comment on function crm.marcar_potencial_lead_fn(uuid, crm.nivel_potencial) is
'Puerta: marca el potencial (frio, tibio, estrella) de un lead. Solo el analista dueño o su supervisor; gerencia y demás roles 42501; lead ajeno P0002; cerrado 22023; bandera potencial_lead apagada 55000. Autoriza tras bloquear el lead. Devuelve {lead_id, nivel, origen, marcado_por, marcado_en}.';

-- ── 7 · Bandera (apagada hasta la fase 3) ──────────────────────────────────────
insert into crm.multiempresa_flags (nombre, activo, descripcion)
values ('potencial_lead', false, 'Marca de potencial del lead (Frío, Tibio, Estrella): la puerta crm.marcar_potencial_lead_fn solo escribe con la bandera encendida')
on conflict (nombre) do nothing;

-- ── 8 · Dueños y permisos ──────────────────────────────────────────────────────
alter type crm.nivel_potencial owner to postgres;
alter table crm.lead_potencial owner to postgres;
alter table crm.lead_potencial_eventos owner to postgres;
alter function private.potencial_evento_inmutable() owner to postgres;
alter function private.potencial_bloquear_lead(uuid) owner to postgres;
alter function private.potencial_rechazo(uuid, uuid) owner to postgres;
alter function private.potencial_marcar_nucleo(uuid, uuid, crm.nivel_potencial) owner to postgres;
alter function crm.marcar_potencial_lead_fn(uuid, crm.nivel_potencial) owner to postgres;

revoke all on crm.lead_potencial, crm.lead_potencial_eventos from public, anon, authenticated, service_role;
revoke all on sequence crm.lead_potencial_eventos_orden_seq from public, anon, authenticated, service_role;

revoke all on function private.potencial_evento_inmutable() from public, anon, authenticated, service_role;
revoke all on function private.potencial_bloquear_lead(uuid) from public, anon, authenticated, service_role;
revoke all on function private.potencial_rechazo(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function private.potencial_marcar_nucleo(uuid, uuid, crm.nivel_potencial) from public, anon, authenticated, service_role;
revoke all on function crm.marcar_potencial_lead_fn(uuid, crm.nivel_potencial) from public, anon, authenticated, service_role;
grant execute on function crm.marcar_potencial_lead_fn(uuid, crm.nivel_potencial) to authenticated;

-- ── 9 · Postflight ─────────────────────────────────────────────────────────────
do $postflight$
declare
  v_puerta pg_catalog.regprocedure := 'crm.marcar_potencial_lead_fn(uuid,crm.nivel_potencial)'::pg_catalog.regprocedure;
  v_privadas pg_catalog.regprocedure[] := array[
    'private.potencial_evento_inmutable()'::pg_catalog.regprocedure,
    'private.potencial_bloquear_lead(uuid)'::pg_catalog.regprocedure,
    'private.potencial_rechazo(uuid,uuid)'::pg_catalog.regprocedure,
    'private.potencial_marcar_nucleo(uuid,uuid,crm.nivel_potencial)'::pg_catalog.regprocedure
  ];
  v_objetos pg_catalog.regclass[] := array[
    'crm.lead_potencial'::pg_catalog.regclass,
    'crm.lead_potencial_eventos'::pg_catalog.regclass,
    'crm.lead_potencial_eventos_orden_seq'::pg_catalog.regclass
  ];
  v_disparadores text;
  v_policies text;
begin
  -- Texto de catálogo independiente de la sesión: todo calificado (Codex r1 F5).
  perform pg_catalog.set_config('search_path', '', true);

  -- Puerta: DEFINER, dueño postgres, search_path vacío, lock_timeout, EXECUTE solo authenticated.
  if (
    exists (
      select 1 from pg_catalog.pg_proc p
      where p.oid = v_puerta and p.prosecdef and p.proowner = 'postgres'::pg_catalog.regrole
        and p.provolatile = 'v'
        and p.proconfig is not null
        and p.proconfig @> array['search_path=""', 'lock_timeout=5s']::text[]
        and p.proacl is not null
    )
    and not exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                    where p.oid = v_puerta
                      and a.grantee not in ('postgres'::pg_catalog.regrole, 'authenticated'::pg_catalog.regrole))
    and exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                where p.oid = v_puerta and a.privilege_type = 'EXECUTE' and a.grantee = 'authenticated'::pg_catalog.regrole)
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lead: la puerta no quedó DEFINER/postgres/search_path vacío/EXECUTE solo authenticated';
  end if;

  -- Privadas: INVOKER, dueño postgres, search_path vacío y ACL explícita solo de postgres.
  if (
    (select count(*) from pg_catalog.pg_proc p
      where p.oid = any (v_privadas) and not p.prosecdef and p.proowner = 'postgres'::pg_catalog.regrole
        and p.proconfig is not null and p.proconfig @> array['search_path=""']::text[]
        and p.proacl is not null) = 4
    and not exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                    where p.oid = any (v_privadas) and a.grantee <> 'postgres'::pg_catalog.regrole)
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lead: los ayudantes privados no quedaron INVOKER/search_path vacío/sin EXECUTE para la API';
  end if;

  -- Tablas y secuencia: dueño postgres y ACL en LISTA BLANCA (solo postgres), RLS activa en
  -- las dos tablas; tipo con dueño postgres. Permisos EFECTIVOS de la API en cero (herencia
  -- incluida).
  if (
    (select count(*) from pg_catalog.pg_class c
      where c.oid = any (v_objetos) and c.relowner = 'postgres'::pg_catalog.regrole and c.relacl is not null) = 3
    and not exists (select 1 from pg_catalog.pg_class c, pg_catalog.aclexplode(c.relacl) a
                    where c.oid = any (v_objetos) and a.grantee <> 'postgres'::pg_catalog.regrole)
    and (select count(*) from pg_catalog.pg_class c
          where c.oid in ('crm.lead_potencial'::pg_catalog.regclass, 'crm.lead_potencial_eventos'::pg_catalog.regclass)
            and c.relrowsecurity) = 2
    and (select t.typowner from pg_catalog.pg_type t where t.oid = 'crm.nivel_potencial'::pg_catalog.regtype) = 'postgres'::pg_catalog.regrole
    and not exists (
      select 1
      from unnest(array['anon', 'authenticated', 'service_role']) r(rol),
           unnest(array['crm.lead_potencial', 'crm.lead_potencial_eventos']) t(tabla),
           unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) x(priv)
      where pg_catalog.has_table_privilege(r.rol, t.tabla, x.priv)
    )
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lead: dueño, ACL, RLS o permisos efectivos de tablas, secuencia o tipo no son los previstos';
  end if;

  -- Policies exactas: una SELECT por tabla, para authenticated, con su exists (Codex r1 F5).
  select string_agg(pp.tablename || '|' || pp.cmd || '|' || pp.roles::text || '|'
                    || pg_catalog.regexp_replace(coalesce(pp.qual, ''), '\s+', ' ', 'g') || '|' || coalesce(pp.with_check, ''),
                    ' ## ' order by pp.tablename)
    into v_policies
  from pg_catalog.pg_policies pp
  where pp.schemaname = 'crm' and pp.tablename in ('lead_potencial', 'lead_potencial_eventos');
  if (v_policies = 'lead_potencial|SELECT|{authenticated}|(EXISTS ( SELECT 1 FROM crm.leads l WHERE (l.id = lead_potencial.lead_id)))|'
                 || ' ## lead_potencial_eventos|SELECT|{authenticated}|(EXISTS ( SELECT 1 FROM crm.leads l WHERE (l.id = lead_potencial_eventos.lead_id)))|') is not true then
    raise exception 'POSTFLIGHT potencial_lead: policies inesperadas: %', coalesce(v_policies, '(ninguna)');
  end if;

  -- Disparadores exactos (momento, eventos, nivel y función) y activos para sesiones normales.
  select string_agg(pg_catalog.pg_get_triggerdef(t.oid) || ' [' || t.tgenabled::text || ']', ' ## ' order by t.tgname)
    into v_disparadores
  from pg_catalog.pg_trigger t
  where t.tgrelid in ('crm.lead_potencial'::pg_catalog.regclass, 'crm.lead_potencial_eventos'::pg_catalog.regclass)
    and not t.tgisinternal;
  if (v_disparadores =
        'CREATE TRIGGER lead_potencial_evento_inmutable BEFORE DELETE OR UPDATE ON crm.lead_potencial_eventos FOR EACH ROW EXECUTE FUNCTION private.potencial_evento_inmutable() [O]'
     || ' ## CREATE TRIGGER lead_potencial_evento_no_truncate BEFORE TRUNCATE ON crm.lead_potencial_eventos FOR EACH STATEMENT EXECUTE FUNCTION private.potencial_evento_inmutable() [O]'
     || ' ## CREATE TRIGGER trg_audit_lead_potencial AFTER INSERT OR DELETE OR UPDATE ON crm.lead_potencial FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm() [O]'
     || ' ## CREATE TRIGGER trg_audit_lead_potencial_eventos AFTER INSERT OR DELETE OR UPDATE ON crm.lead_potencial_eventos FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm() [O]'
     || ' ## CREATE TRIGGER trg_lead_potencial_touch BEFORE UPDATE ON crm.lead_potencial FOR EACH ROW EXECUTE FUNCTION private.set_actualizado_en_crm() [O]'
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lead: disparadores inesperados: %', coalesce(v_disparadores, '(ninguno)');
  end if;

  -- Bandera creada y apagada.
  if (select f.activo from crm.multiempresa_flags f where f.nombre = 'potencial_lead') is distinct from false then
    raise exception 'POSTFLIGHT potencial_lead: la bandera potencial_lead no quedó creada y apagada';
  end if;

  raise notice 'potencial_lead OK: tipo, 2 tablas (RLS, sin grants API), núcleo INVOKER con candado, puerta DEFINER solo authenticated, bandera apagada.';
end;
$postflight$;

commit;
$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20260930213647' and name = 'crm_potencial_lead' and cardinality(statements) = 1
                   and md5(statements[1]) = 'f4087876c31cccc509db17aa760a4238') then
    raise exception 'REGISTRO: la fila 20260930213647 / crm_potencial_lead no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20260930213647 / crm_potencial_lead (1 sentencia: el archivo entero)';
end $post$;
commit;

-- F3 «Recordar» del plan «Verificación y toma de lead libre» (spec §5.3-§5.5;
-- plan aprobado por Miguel 2026-08-16, nota del vault «Verificación y toma de
-- lead libre»). Qué trae:
--
--   1. crm.recordatorios_disponibilidad — el recordatorio PERSONAL del
--      vendedor para volver a verificar un contacto ocupado. Anclado AL
--      CONTACTO tecleado (teléfono normalizado + DNI), deliberadamente SIN FK
--      a crm.leads: un recordatorio jamás será el 8.º candado de la limpieza
--      de leads ni reserva nada (spec §5.3: no concede propiedad ni
--      prioridad). RLS owner-only; CON policy DELETE — excepción documentada
--      a la convención de la casa (soft-delete): la spec exige eliminar y
--      esta tabla es una nota personal efímera, no un registro comercial
--      (minimización de datos; el rastro queda en audit_log como en toda
--      crm.*).
--   2. Caducidad SOLA (spec/plan: «los vencidos no atendidos caducan solos»):
--      barrido diario pg_cron que borra recordatorios vencidos hace más de
--      7 días — minimización, y la campana no acumula ruido eterno.
--   3. Deuda de la auditoría del front F2 (Codex, refutación 3 CONFIRMADA
--      como vector): PG17 admite 'infinity'::timestamptz y
--      crm.actividades.creado_en era insertable con él por authenticated —
--      un asiento envenenado llegaba al max() de los payloads de
--      verificación y el contrato del front cerraba (fail-closed correcto,
--      pero el veneno vivía). CHECK de finitud, hermano del anti-NaN de
--      dinero. La tabla nueva nace con el suyo.
--
-- Sin tocar public.*. El front que consume esto llega en el release F3
-- (dirección: request nuevo → SERVIDOR primero, este fichero).

-- ── 0. Guardas de dependencias ───────────────────────────────────────────────
do $$
begin
  -- TODO lo que la migración usa se exige AQUÍ (Codex R6: la FK usa perfiles
  -- y el ALTER final usa actividades — sin esto, un mundo mutilado fallaría
  -- TARDE, con objetos a medio crear; F2 hace lo mismo con sus dependencias).
  if to_regclass('crm.politica_abandono') is null
     or to_regclass('crm.actividades') is null
     or to_regclass('public.perfiles') is null
     or to_regprocedure('private.normalizar_telefono(text)') is null
     or to_regprocedure('private.rol_crm(uuid)') is null
     or to_regprocedure('private.log_audit_crm()') is null then
    raise exception 'Faltan dependencias de F1/base: aplicar primero las migraciones previas';
  end if;
end $$;

-- ── 1. La tabla ──────────────────────────────────────────────────────────────
create table crm.recordatorios_disponibilidad (
  id uuid primary key default gen_random_uuid(),
  -- El dueño. FK a perfiles NO estorba la limpieza de leads (offboarding
  -- jamás borra perfiles: activo=false) y sí impide filas huérfanas.
  perfil_id uuid not null references public.perfiles(id),
  -- El contacto, con la MISMA forma canónica del resto del plan lead libre.
  telefono text not null check (telefono ~ '^\+519[0-9]{8}$'),
  dni text check (dni ~ '^[0-9]{8}$'),
  -- Cuándo volver a verificar. Finito (el veneno 'infinity' no entra) y el
  -- trigger de abajo lo acota a futuro razonable.
  recordar_en timestamptz not null check (isfinite(recordar_en)),
  creado_en timestamptz not null default now() check (isfinite(creado_en)),
  -- UN recordatorio por contacto y vendedor: crear de nuevo = reprogramar
  -- (el front hace upsert por esta llave; la campana no se duplica).
  constraint recordatorios_disponibilidad_unico unique (perfil_id, telefono)
);

comment on table crm.recordatorios_disponibilidad is
  'F3 lead libre (spec §5.3-§5.5): recordatorio PERSONAL del vendedor para re-verificar un contacto ocupado cuando venza su protección. Anclado al CONTACTO (teléfono normalizado), SIN FK a leads a propósito: no reserva, no prioriza, no es actividad comercial, no toca el timeline ni el reloj de inactividad (spec §10 caso 6). Owner-only por RLS; DELETE permitido como excepción documentada (nota personal efímera + minimización). Los vencidos >7 días caducan solos (pg_cron crm-recordatorios-caducidad). La campana del front re-verifica BAJO DEMANDA al clic: esta tabla jamás guarda veredictos. Como TODA tabla crm.* auditada, su rastro en public.audit_log es legible por admin/superadmin del portal (vía preexistente, misma frase que F1) — el owner-only gobierna la tabla viva, no exime del rastro administrativo.';
comment on column crm.recordatorios_disponibilidad.telefono is
  'Normalizado +519######## por trigger (private.normalizar_telefono) — la misma llave de contacto que verificar/tomar.';
comment on column crm.recordatorios_disponibilidad.recordar_en is
  'Cuándo revisar. Futuro en el momento de escribir, tope 365 días (trigger); finito por CHECK (el veneno infinity de PG17 no entra).';

-- ── 2. Normalización y autoría SELLADAS en servidor ──────────────────────────
-- Espejo del sellado de politica_abandono (auditor M2 de F1): PostgREST no
-- puede firmar con otro autor ni colar un teléfono sin normalizar. security
-- definer con search_path fijo (convención de la casa para triggers de crm).
create function crm.recordatorios_disponibilidad_sellar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tel text;
begin
  -- La fila es SIEMPRE del actor autenticado: la autoría no viaja del cliente.
  new.perfil_id := (select auth.uid());
  if new.perfil_id is null then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  v_tel := private.normalizar_telefono(new.telefono);
  -- El regex además del null: normalizar_telefono casi nunca devuelve NULL
  -- (su rama else devuelve '+' || dígitos) — sin esto, un fijo o un número
  -- corto rebotaría con el 23514 críptico del CHECK en vez de este 22023
  -- (auditor-rls m5, 2026-08-18).
  if v_tel is null or v_tel !~ '^\+519[0-9]{8}$' then
    raise exception using errcode = '22023',
      message = 'El teléfono del recordatorio debe ser un celular peruano válido';
  end if;
  new.telefono := v_tel;
  new.dni := nullif(pg_catalog.btrim(coalesce(new.dni, '')), '');

  -- Un recordatorio nace (o se reprograma) hacia el futuro, con tope sano.
  -- clock_timestamp() y no now() (Codex R2, 2026-08-18): now() es tiempo de
  -- TRANSACCIÓN — un statement que esperó un lock validaría contra un reloj
  -- viejo y dejaría entrar una fecha ya pasada. «Futura» aquí significa
  -- futura en la pared, no en el BEGIN.
  if new.recordar_en <= pg_catalog.clock_timestamp() then
    raise exception using errcode = '22023',
      message = 'La fecha de revisión debe ser futura';
  end if;
  if new.recordar_en > pg_catalog.clock_timestamp() + make_interval(days => 365) then
    raise exception using errcode = '22023',
      message = 'La fecha de revisión no puede pasar de 365 días';
  end if;

  -- creado_en lo SELLA el servidor en INSERT (un cliente no nace su
  -- recordatorio en 1999 — auditor-rls m1) y se conserva en UPDATE.
  if tg_op = 'INSERT' then
    new.creado_en := pg_catalog.now();
  else
    new.creado_en := old.creado_en;
  end if;
  return new;
end;
$$;

revoke all on function crm.recordatorios_disponibilidad_sellar()
  from public, anon, authenticated;

create trigger trg_recordatorios_disponibilidad_00_sellar
  before insert or update on crm.recordatorios_disponibilidad
  for each row execute function crm.recordatorios_disponibilidad_sellar();

create trigger trg_audit_recordatorios_disponibilidad
  after insert or delete or update on crm.recordatorios_disponibilidad
  for each row execute function private.log_audit_crm();

-- ── 3. RLS owner-only ────────────────────────────────────────────────────────
alter table crm.recordatorios_disponibilidad enable row level security;

-- Solo VENDEDOR: es la antesala de la toma directa, que es suya (espejo del
-- guard 42501 de crm.tomar_lead_libre y de la capacidad tomarLeadDirecto del
-- front). Supervisión asigna por el reparto y no verifica «para sí».
-- Owner-only: ni gerencia lee recordatorios ajenos — son notas personales;
-- lo auditable ya queda en audit_log y en crm.verificaciones_lead.
create policy recordatorios_disponibilidad_select on crm.recordatorios_disponibilidad
  for select to authenticated
  using (
    perfil_id = (select auth.uid())
    and (select private.rol_crm((select auth.uid()))) = 'vendedor'
  );

create policy recordatorios_disponibilidad_insert on crm.recordatorios_disponibilidad
  for insert to authenticated
  with check (
    perfil_id = (select auth.uid())
    and (select private.rol_crm((select auth.uid()))) = 'vendedor'
  );

create policy recordatorios_disponibilidad_update on crm.recordatorios_disponibilidad
  for update to authenticated
  using (
    perfil_id = (select auth.uid())
    and (select private.rol_crm((select auth.uid()))) = 'vendedor'
  )
  with check (
    perfil_id = (select auth.uid())
    and (select private.rol_crm((select auth.uid()))) = 'vendedor'
  );

-- EXCEPCIÓN DOCUMENTADA a «sin policy DELETE» (LEEME.md): la spec §5.3 exige
-- que el recordatorio «puede eliminarse o reprogramarse sin afectar al lead».
-- No es un registro comercial con historia que preservar — es una nota
-- personal cuya vida entera es efímera (los vencidos caducan solos); el soft
-- delete aquí sería acumular PII de contactos sin propósito (minimización).
-- El audit trigger deja el rastro del borrado, como en toda crm.*.
create policy recordatorios_disponibilidad_delete on crm.recordatorios_disponibilidad
  for delete to authenticated
  using (
    perfil_id = (select auth.uid())
    and (select private.rol_crm((select auth.uid()))) = 'vendedor'
  );

create index recordatorios_disponibilidad_campana_idx
  on crm.recordatorios_disponibilidad (perfil_id, recordar_en);

revoke all on crm.recordatorios_disponibilidad from public, anon;
grant select, insert, update, delete on crm.recordatorios_disponibilidad to authenticated;

-- ── 4. Caducidad sola (minimización) ─────────────────────────────────────────
create function private.caducar_recordatorios_disponibilidad()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_borrados integer;
begin
  -- 7 días de gracia tras vencer: si en una semana no atendió la campana,
  -- el recordatorio ya no recuerda nada — se va (y su PII con él).
  delete from crm.recordatorios_disponibilidad
  where recordar_en < pg_catalog.now() - make_interval(days => 7);
  get diagnostics v_borrados = row_count;
  return v_borrados;
end;
$$;

comment on function private.caducar_recordatorios_disponibilidad() is
  'Barrido diario de F3 lead libre: borra recordatorios vencidos hace más de 7 días (minimización; la campana no acumula ruido). Lo invoca pg_cron (crm-recordatorios-caducidad); corre con auth.uid() NULL y el trigger de sellado no aplica a DELETE.';

revoke all on function private.caducar_recordatorios_disponibilidad()
  from public, anon, authenticated, service_role;

do $$
begin
  -- `cron.schedule` reemplaza por nombre, así que reaplicar es idempotente.
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    -- Banco local sin pg_cron: no es un fallo, aquí no hay reloj que programar.
    raise notice 'pg_cron no está disponible: no se programa la caducidad de recordatorios.';
    return;
  end if;
  perform cron.schedule(
    'crm-recordatorios-caducidad',
    '17 6 * * *',  -- 06:17 UTC ≈ 01:17 Lima, horario muerto
    'select private.caducar_recordatorios_disponibilidad()'
  );
end $$;

-- Vuelta atrás (convención del cierre de mes, 20260815102000: el job se
-- programa en la migración y se DESPROGRAMA en su vuelta atrás — sin esto,
-- retirar F3 dejaría un error diario silencioso en cron.job_run_details):
--   select cron.unschedule('crm-recordatorios-caducidad');
--   drop function private.caducar_recordatorios_disponibilidad();
--   drop table crm.recordatorios_disponibilidad;
--   drop function crm.recordatorios_disponibilidad_sellar();
--   alter table crm.actividades drop constraint actividades_creado_en_finito;

-- ── 5. Deuda F2: el veneno 'infinity' muere en la puerta ─────────────────────
-- Vector confirmado por la auditoría del front (Codex R3 de F1-front,
-- 2026-08-17): authenticated tiene INSERT en crm.actividades y creado_en no
-- validaba finitud — 'infinity' llegaba al max() de los payloads de
-- verificación y rompía el contrato del front (que cierra fail-closed, pero
-- el veneno quedaba vivo en la tabla). NOT VALID + VALIDATE aquí NO compra
-- concurrencia (la CLI envuelve la migración en UNA transacción: el lock se
-- retiene hasta el commit igual — auditor-rls m2); se deja el par porque
-- documenta la INTENCIÓN y, si actividades creciera antes de aplicarse, el
-- VALIDATE se parte a una migración hermana. Hoy: tabla casi vacía, gratis.
alter table crm.actividades
  add constraint actividades_creado_en_finito
  check (isfinite(creado_en)) not valid;
alter table crm.actividades
  validate constraint actividades_creado_en_finito;

comment on constraint actividades_creado_en_finito on crm.actividades is
  'Anti-veneno infinity (hermano del anti-NaN de dinero): creado_en entra en max() de payloads de verificación y un infinito rompía el contrato del front. Auditoría F2-front 2026-08-17.';

-- F4.1 del plan «Hoy del supervisor, sin ruido» (decisiones de Miguel
-- 2026-08-23: reconocida = ATENUADA, posponer con fecha y tope 7 días,
-- gerencia LEE los reconocimientos). Qué trae:
--
--   1. crm.alertas_reconocimientos — el LIBRO de reconocimientos: cuando un
--      supervisor reconoce («ya lo estoy atendiendo») o pospone una alerta
--      agrupada de su campana, queda QUIÉN, QUÉ alerta, la FOTO de sus
--      miembros (para detectar «empeoró»: un miembro nuevo o severidad más
--      alta la hacen reaparecer — esa comparación vive en el front, lógica
--      pura con sus pruebas) y HASTA cuándo si es posposición.
--      LEDGER INMUTABLE: solo INSERT — sin policy UPDATE ni DELETE y sin
--      grants de UPDATE/DELETE; un reconocimiento nuevo supersede al
--      anterior por creado_en. Reconocer NUNCA borra la alerta: la atenúa
--      (front) y deja rastro.
--   2. Caducidad sola: barrido diario pg_cron que borra filas de más de 90
--      días — la traza VIVA es de 90 días; el rastro permanente ya queda en
--      public.audit_log vía private.log_audit_crm, como en toda crm.*.
--
-- Sin tocar public.* (salvo la FK de lectura a perfiles, patrón de la casa).
-- Orden de deploy: request nuevo → SERVIDOR primero (este fichero); el front
-- de F4.2 llega después y degrada con honestidad si esta tabla aún no está.

-- ── 0. Guardas de dependencias ───────────────────────────────────────────────
do $$
begin
  if to_regclass('public.perfiles') is null
     or to_regprocedure('private.rol_crm(uuid)') is null
     or to_regprocedure('private.log_audit_crm()') is null then
    raise exception 'Faltan dependencias de base: aplicar primero las migraciones previas';
  end if;
end $$;

-- ── 1. La tabla ──────────────────────────────────────────────────────────────
create table crm.alertas_reconocimientos (
  id uuid primary key default gen_random_uuid(),
  -- Quién reconoce. FK a perfiles (offboarding jamás borra perfiles).
  perfil_id uuid not null references public.perfiles(id),
  -- El id del GRUPO de la campana (lib/alertas.ts): grupo:<tipo>:<uuid del
  -- supervisor>. Cerrado a los 4 tipos vigentes: un tipo nuevo de alerta
  -- exigirá su migración, a propósito — el libro no acepta ids inventados.
  -- collate "C" (Codex #10): los rangos [0-9a-f] dependen de la collation;
  -- con "C" el regex es ASCII puro en cualquier LC_CTYPE.
  alerta_id text not null check (
    alerta_id collate "C" ~ '^grupo:(por_repartir|tarea_vencida|lead_sin_responder|sin_proxima_accion):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  ),
  accion text not null check (accion in ('reconocer', 'posponer')),
  -- La FOTO de los miembros del grupo en el momento de reconocer (ids de
  -- leads o de vendedores, NUNCA nombres — sin PII). Es lo que permite
  -- «reaparece si empeora»: el front compara los miembros actuales contra
  -- esta foto y un id nuevo revive la alerta.
  -- array_ndims = 1 (Codex #2): en PG17 cardinality y unnest APLANAN un
  -- array 2D — sin esto, [['a','b']] pasaba ambos candados y guardaba una
  -- estructura que el comparador de «empeoró» no espera.
  miembros text[] not null check (
    cardinality(miembros) between 1 and 2000
    and array_ndims(miembros) = 1
  ),
  -- La severidad reconocida: si la actual es MÁS alta, la alerta reaparece.
  severidad text not null check (severidad in ('critica', 'atencion')),
  -- Solo posponer lleva fecha (tope 7 días, sellado en trigger): posponer
  -- sin fecha no existe — sería silenciar con otro nombre.
  hasta timestamptz check (
    (accion = 'posponer') = (hasta is not null)
    and (hasta is null or isfinite(hasta))
  ),
  creado_en timestamptz not null default now() check (isfinite(creado_en)),
  -- El ORDEN TOTAL del libro (Codex #3): clock_timestamp() puede empatar al
  -- microsegundo bajo concurrencia y «el último asiento manda» necesita un
  -- desempate estructural. La identity es monotónica por asignación.
  secuencia bigint generated always as identity
);

comment on table crm.alertas_reconocimientos is
  'F4 «Hoy del supervisor, sin ruido»: libro INMUTABLE (solo INSERT) de reconocimientos de las alertas agrupadas de la campana del supervisor. Reconocer atenúa (no borra) y descuenta del badge; posponer oculta hasta una fecha (tope 7 días); AMBOS ceden si el grupo EMPEORA — el front compara los miembros actuales contra la foto guardada aquí y un miembro nuevo o una severidad mayor reviven la alerta. El último asiento por alerta_id manda (por `secuencia`, el orden total del libro — creado_en puede empatar al microsegundo). Owner-only para escribir (solo el supervisor dueño del id); gerencia LEE todo (decisión de Miguel 2026-08-23: el reconocimiento es un compromiso con trazabilidad, no un botón de silencio). Traza viva 90 días (pg_cron crm-alertas-reconocimientos-caducidad); el rastro permanente queda en public.audit_log. CANDADO ACOTADO (Codex F4.1 #1): el servidor valida FORMA de la foto y de la severidad, no su VERDAD (esa vive en el front que deriva los grupos). Por eso NINGÚN reconocimiento vige más de 7 DÍAS: el front lo caduca por creado_en —que sella el servidor y el cliente no puede fechar—, mismo tope que posponer. Una foto inflada tampoco frena el revive por miembros (los ids reales futuros son aleatorios: no están en ninguna foto inventada); declarar severidad en falso solo compra, como máximo, esos 7 días, a la vista de gerencia. La regla de vigencia es CONTRATO de F4.2.';
comment on column crm.alertas_reconocimientos.alerta_id is
  'Id del grupo de lib/alertas.ts (grupo:<tipo>:<uuid supervisor>). El trigger exige que el uuid final sea el del actor: nadie reconoce alertas ajenas.';
comment on column crm.alertas_reconocimientos.miembros is
  'Foto de ids (leads/vendedores) del grupo al reconocer — sin nombres. Base del «reaparece si empeora».';
comment on column crm.alertas_reconocimientos.hasta is
  'Solo posponer: hasta cuándo se oculta. Futura y con tope de 7 días (trigger, reloj de pared); finita por CHECK.';

-- ── 2. Autoría y validez SELLADAS en servidor ────────────────────────────────
-- security definer con search_path fijo (convención de la casa para triggers
-- de crm): PostgREST no puede firmar con otro autor, reconocer alertas de
-- otro supervisor ni posponer más allá del tope.
create function crm.alertas_reconocimientos_sellar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- La fila es SIEMPRE del actor autenticado: la autoría no viaja del cliente.
  new.perfil_id := (select auth.uid());
  if new.perfil_id is null then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  -- Defensa en profundidad (auditor #8): el gate de rol vive en la policy,
  -- pero una futura RPC definer que inserte aquí no debe poder saltárselo.
  if private.rol_crm(new.perfil_id) is distinct from 'supervisor' then
    raise exception using errcode = '42501',
      message = 'Solo un supervisor escribe en el libro de reconocimientos';
  end if;

  -- Nadie reconoce alertas ajenas: el uuid del alerta_id ES el del actor.
  -- (El CHECK de formato corre DESPUÉS de este BEFORE trigger — aquí solo se
  -- ata la identidad; lo malformado muere luego en el CHECK. auditor #5.)
  if new.alerta_id !~ ('[:]' || new.perfil_id::text || '$') then
    raise exception using errcode = '42501',
      message = 'Solo puedes reconocer alertas de tu propia campana';
  end if;

  -- Miembros sanos: ids cortos sin espacios, sin nulls (la cardinalidad ya
  -- la acota el CHECK). Un null dentro del array pasa cardinality y habría
  -- envenenado la comparación de «empeoró» en el front.
  if exists (
    select 1 from pg_catalog.unnest(new.miembros) as m
    where m is null or m collate "C" !~ '^[0-9A-Za-z_-]{1,64}$'
  ) then
    raise exception using errcode = '22023',
      message = 'La foto de miembros trae ids inválidos';
  end if;

  -- Posponer: futura y con tope de 7 DÍAS (decisión de Miguel 2026-08-23).
  -- clock_timestamp() y no now(): la lección de F3 — «futura» significa
  -- futura en la pared, no en el BEGIN de la transacción.
  if new.accion = 'posponer' then
    if new.hasta <= pg_catalog.clock_timestamp() then
      raise exception using errcode = '22023',
        message = 'La fecha de posposición debe ser futura';
    end if;
    if new.hasta > pg_catalog.clock_timestamp() + make_interval(days => 7) then
      raise exception using errcode = '22023',
        message = 'Posponer tiene un tope de 7 días';
    end if;
  end if;

  -- creado_en lo SELLA el servidor: el orden del libro no lo decide el
  -- cliente. clock_timestamp() y no now() (auditor #6): un POST batch de
  -- PostgREST mete varias filas en UNA transacción y con now() empatarían —
  -- «el último asiento manda» necesita un reloj que avance dentro del batch.
  new.creado_en := pg_catalog.clock_timestamp();
  return new;
end;
$$;

revoke all on function crm.alertas_reconocimientos_sellar()
  from public, anon, authenticated;

create trigger trg_alertas_reconocimientos_00_sellar
  before insert on crm.alertas_reconocimientos
  for each row execute function crm.alertas_reconocimientos_sellar();

create trigger trg_audit_alertas_reconocimientos
  after insert or delete or update on crm.alertas_reconocimientos
  for each row execute function private.log_audit_crm();

-- Guardia de inmutabilidad (auditor #7, el cinturón de los ledgers recientes
-- de la casa — lead_asignaciones, cuentas_bancarias_version): la ausencia de
-- policy/grant ya cierra la vía PostgREST; esto cierra además la vía owner y
-- la de una futura función definer equivocada. El DELETE solo deja pasar la
-- caducidad (asientos de más de 90 días) — nadie arranca hojas jóvenes.
create function crm.alertas_reconocimientos_inmutables()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    raise exception using errcode = '42501',
      message = 'El libro de reconocimientos es inmutable: no se edita';
  end if;
  if old.creado_en >= pg_catalog.now() - make_interval(days => 90) then
    raise exception using errcode = '42501',
      message = 'El libro de reconocimientos es inmutable: solo caduca a los 90 días';
  end if;
  return old;
end;
$$;

revoke all on function crm.alertas_reconocimientos_inmutables()
  from public, anon, authenticated;

create trigger trg_alertas_reconocimientos_01_inmutables
  before update or delete on crm.alertas_reconocimientos
  for each row execute function crm.alertas_reconocimientos_inmutables();

-- ── 3. RLS: escribe el dueño supervisor; lee el dueño y gerencia ─────────────
alter table crm.alertas_reconocimientos enable row level security;

-- SELECT: el supervisor ve SU libro; gerencia lo ve TODO (trazabilidad —
-- decisión de Miguel). Un supervisor no ve los reconocimientos de otro.
create policy alertas_reconocimientos_select on crm.alertas_reconocimientos
  for select to authenticated
  using (
    (
      perfil_id = (select auth.uid())
      and (select private.rol_crm((select auth.uid()))) = 'supervisor'
    )
    or (select private.rol_crm((select auth.uid()))) = 'gerencia'
  );

-- INSERT: solo un SUPERVISOR y solo como él mismo (el trigger además ata el
-- alerta_id a su uuid). Gerencia no reconoce por otros: el compromiso es
-- personal.
create policy alertas_reconocimientos_insert on crm.alertas_reconocimientos
  for insert to authenticated
  with check (
    perfil_id = (select auth.uid())
    and (select private.rol_crm((select auth.uid()))) = 'supervisor'
  );

-- SIN policy UPDATE ni DELETE: libro inmutable (deny-by-default). La
-- caducidad de 90 días corre por private.* con definer, fuera de RLS.

-- Último asiento por alerta: el índice sirve la lectura del front
-- («dame lo más reciente de cada alerta mía») y el barrido de caducidad.
create index alertas_reconocimientos_ultimo_idx
  on crm.alertas_reconocimientos (perfil_id, alerta_id, secuencia desc);
create index alertas_reconocimientos_caducidad_idx
  on crm.alertas_reconocimientos (creado_en);

revoke all on crm.alertas_reconocimientos from public, anon;
-- Sin UPDATE ni DELETE ni siquiera como grant: cinturón además de la RLS.
grant select, insert on crm.alertas_reconocimientos to authenticated;

-- ── 4. Caducidad sola (traza viva 90 días) ───────────────────────────────────
create function private.caducar_alertas_reconocimientos()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_borrados integer;
begin
  -- A los 90 días el asiento ya no gobierna ninguna alerta viva (los grupos
  -- se rehacen a diario); la trazabilidad de largo plazo vive en audit_log.
  delete from crm.alertas_reconocimientos
  where creado_en < pg_catalog.now() - make_interval(days => 90);
  get diagnostics v_borrados = row_count;
  return v_borrados;
end;
$$;

comment on function private.caducar_alertas_reconocimientos() is
  'F4 «Hoy del supervisor, sin ruido»: barrido diario que borra asientos de reconocimiento con más de 90 días (traza viva acotada; el rastro permanente queda en public.audit_log). Lo invoca pg_cron (crm-alertas-reconocimientos-caducidad).';

revoke all on function private.caducar_alertas_reconocimientos()
  from public, anon, authenticated, service_role;

do $$
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    raise notice 'pg_cron no está disponible: no se programa la caducidad de reconocimientos.';
    return;
  end if;
  perform cron.schedule(
    'crm-alertas-reconocimientos-caducidad',
    '23 6 * * *',  -- 06:23 UTC ≈ 01:23 Lima, horario muerto
    'select private.caducar_alertas_reconocimientos()'
  );
end $$;

-- Vuelta atrás (el job se desprograma en la vuelta, como el cierre de mes).
-- El unschedule va CONDICIONAL (Codex #6): en un banco sin pg_cron o sin el
-- job, el incondicional revienta la vuelta. Lo copiado a public.audit_log
-- se queda A PROPÓSITO: es el rastro permanente, no un residuo.
--   do $$ begin
--     if to_regprocedure('cron.unschedule(text)') is not null
--        and exists (select 1 from cron.job where jobname = 'crm-alertas-reconocimientos-caducidad') then
--       perform cron.unschedule('crm-alertas-reconocimientos-caducidad');
--     end if;
--   end $$;
--   drop function private.caducar_alertas_reconocimientos();
--   drop table crm.alertas_reconocimientos;
--   drop function crm.alertas_reconocimientos_inmutables();
--   drop function crm.alertas_reconocimientos_sellar();

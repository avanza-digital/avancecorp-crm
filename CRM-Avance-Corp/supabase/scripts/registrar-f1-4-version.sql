-- Registra la versión 20260829230000 en el registro de migraciones CON su cuerpo.
-- (El registro sin `statements` es lo que hizo mentir a `merge_branch` dos veces:
--  una versión sin cuerpo no se puede replicar en un banco nuevo.)
insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260829230000',
  'crm_f1_4_regla_de_auditoria',
  array[$mig_f1_4$-- P-055 · FASE 1.4 — LA REGLA QUE OBLIGA A LAS QUE VENGAN
--
-- La Fase 1 (28/08) auditó las tablas que EXISTÍAN. No instaló la regla que
-- obliga a las que nazcan después: hasta hoy la única garantía era que alguien
-- se acordara. Esta migración cierra los tres huecos reales, mete la regla
-- DENTRO del servidor (una sola fuente) y le pone un vigía diario. El gate del
-- repo (`npm run gate:auditoria`) es el tercer filo.
--
-- LOS TRES HUECOS
--   1. crm.operaciones_cartera — NO se puede editar (el candado append-only
--      rechaza todo UPDATE y todo DELETE directo, y por la API solo hay SELECT),
--      pero el borrado por arrastre al eliminar un contrato se llevaba la fila
--      SIN dejar copia de su contenido. Es dinero (capital renovado y
--      adicional): ahora queda el rastro completo.
--   2. crm.agenda_ics — el token de calendario de cada persona.
--   3. public.suscripciones_push — los dispositivos del portal.
--
-- 🔴 POR QUÉ LAS DOS ÚLTIMAS NO USAN EL AUDITOR NORMAL: `public.audit_log` lo
--    lee CUALQUIER admin (política `audit_log_admin_select :: es_admin()`) y
--    también lo expone `public.bandeja_actividad`. El token ICS hoy solo lo ve
--    su dueño (RLS de agenda_ics) y las claves push nunca salen del portal:
--    copiarlos en claro a la auditoría AMPLIARÍA el círculo que ve un secreto.
--    Por eso van por `private.log_audit_sin_secretos`, que guarda una huella
--    corta en vez del valor — se ve QUE el secreto cambió, nunca CUÁL es.
--
-- 🔴 POR QUÉ NO HAY EVENT TRIGGER: crear uno exige superusuario y en este
--    proyecto `postgres` NO lo es (solo bypassrls; los 6 event triggers vivos
--    son de supabase_admin). El vigía por pg_cron cubre lo mismo y mejor:
--    mira el ESTADO (tabla sin rastro), no solo el nacimiento.
--
-- Toca `public` (suscripciones_push): OK explícito de Miguel el 29/08 al aprobar
-- el plan de esta fase («auditar agenda_ics y suscripciones_push»).

-- ---------------------------------------------------------------------------
-- 1. Enmascarado de secretos
-- ---------------------------------------------------------------------------

create or replace function private.enmascarar_claves(p_fila jsonb, p_claves text[])
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when p_fila is null then null else (
    select pg_catalog.jsonb_object_agg(
      k,
      case
        when k = any(p_claves) and pg_catalog.jsonb_typeof(v) = 'null' then v
        -- Huella corta: distingue un cambio de secreto sin revelarlo.
        when k = any(p_claves) then pg_catalog.to_jsonb(
          '***:' || pg_catalog.left(pg_catalog.md5(v #>> '{}'), 8)
        )
        else v
      end
    )
    from pg_catalog.jsonb_each(p_fila) as e(k, v)
  ) end;
$$;

comment on function private.enmascarar_claves(jsonb, text[]) is
  'Sustituye los valores de las claves indicadas por una huella corta (***:xxxxxxxx). Se ve QUE el secreto cambió, nunca CUÁL es.';

revoke all on function private.enmascarar_claves(jsonb, text[])
  from public, anon, authenticated, service_role;

create or replace function private.log_audit_sin_secretos()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- token: agenda_ics · p256dh/auth/endpoint: suscripciones_push
  v_secretos constant text[] := array['token', 'p256dh', 'auth', 'endpoint'];
  v_fila uuid;
  v_actor uuid;
begin
  v_fila := coalesce(
    (pg_catalog.to_jsonb(coalesce(new, old)) ->> 'id')::uuid,
    (pg_catalog.to_jsonb(coalesce(new, old)) ->> 'perfil_id')::uuid
  );

  -- audit_log.usuario_id apunta a public.perfiles: un actor de Auth todavía sin
  -- perfil (ventana del alta) haría fallar la FK y, con ella, la operación de
  -- negocio. Un rastro nunca puede tumbar lo que audita: si no hay perfil,
  -- se guarda sin actor.
  select p.id into v_actor
  from public.perfiles p where p.id = (select auth.uid());

  insert into public.audit_log (tabla, operacion, fila_id, usuario_id, data_antes, data_despues)
  values (
    tg_table_schema || '.' || tg_table_name,
    tg_op,
    v_fila,
    v_actor,
    case when tg_op in ('UPDATE','DELETE')
      then private.enmascarar_claves(pg_catalog.to_jsonb(old), v_secretos) end,
    case when tg_op in ('INSERT','UPDATE')
      then private.enmascarar_claves(pg_catalog.to_jsonb(new), v_secretos) end
  );

  return coalesce(new, old);
end;
$$;

comment on function private.log_audit_sin_secretos() is
  'Auditor para tablas que guardan secretos (tokens, claves push). Mismo rastro que log_audit_crm pero enmascarando los valores sensibles: audit_log lo lee cualquier admin.';

revoke all on function private.log_audit_sin_secretos()
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Los tres huecos, cerrados
-- ---------------------------------------------------------------------------

-- 2.1 Dinero: el ledger de cartera. AFTER, así que solo registra lo que el
--     candado append-only dejó pasar (el arrastre al borrar un contrato).
drop trigger if exists trg_audit_operaciones_cartera on crm.operaciones_cartera;
create trigger trg_audit_operaciones_cartera
  after insert or update or delete on crm.operaciones_cartera
  for each row execute function private.log_audit_crm();

-- 2.2 Token de calendario: todo movimiento, con el token enmascarado.
drop trigger if exists trg_audit_agenda_ics on crm.agenda_ics;
create trigger trg_audit_agenda_ics
  after insert or update or delete on crm.agenda_ics
  for each row execute function private.log_audit_sin_secretos();

-- 2.3 Dispositivos del portal. El UPDATE se acota a las columnas CON
--     significado: `actualizado_en` se toca en cada visita y llenaría la
--     auditoría de ruido sin decir nada.
drop trigger if exists trg_audit_suscripciones_push on public.suscripciones_push;
create trigger trg_audit_suscripciones_push
  after insert or delete
     or update of cliente_id, endpoint, p256dh, auth, dispositivo, activo
  on public.suscripciones_push
  for each row execute function private.log_audit_sin_secretos();

-- ---------------------------------------------------------------------------
-- 3. La regla, dentro del servidor
-- ---------------------------------------------------------------------------

-- 3.1 La lista blanca deja de vivir en la memoria de nadie: vive aquí, y sin
--     razón escrita no entra (el CHECK obliga a una razón de verdad).
create table if not exists private.auditoria_exenciones (
  tabla        text        primary key,
  razon        text        not null,
  declarada_en timestamptz not null default pg_catalog.now(),
  constraint auditoria_exenciones_razon_de_verdad
    check (pg_catalog.length(pg_catalog.btrim(razon)) >= 40)
);

alter table private.auditoria_exenciones enable row level security;
revoke all on table private.auditoria_exenciones
  from public, anon, authenticated, service_role;

comment on table private.auditoria_exenciones is
  'Tablas de crm/public que pueden vivir SIN rastro en audit_log. Cada fila necesita su razón; el gate del repo compara esta lista con la escrita en supabase/scripts/trinquete-auditoria.sql, así que un cambio silencioso aquí también pone el gate en rojo.';

insert into private.auditoria_exenciones (tabla, razon) values
  ('crm.usuario_eventos',
   'Es la bitácora de la pantalla de Usuarios: ella misma ES el rastro. Además su id es BIGINT y private.log_audit_crm castea a uuid, así que colgárselo abortaría el alta de usuarios entera (visto en la auditoría P-053).'),
  ('public.novedades_leidas',
   'Marca de «novedad leída» por persona. No es dinero, ni titulares, ni secreto: auditarla sería ruido puro que enterraría los movimientos que sí importan.')
on conflict (tabla) do nothing;

-- 3.2 La regla en una sola función: quien pregunte, pregunta aquí.
create or replace function private.tablas_sin_rastro()
returns table (tabla text)
language sql
stable
security definer
set search_path = ''
as $$
  select n.nspname || '.' || c.relname
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  -- 'r' tabla normal · 'p' tabla particionada (hoy no hay ninguna, pero la
  -- regla no puede tener ese agujero). Las particiones hijas se saltan: el
  -- rastro se cuelga en el padre y ellas lo heredan.
  where c.relkind in ('r', 'p')
    and not c.relispartition
    and c.relpersistence = 'p'
    and n.nspname in ('crm', 'public')
    -- Infra, no datos de negocio.
    and n.nspname || '.' || c.relname not in ('public.audit_log', 'public.schema_migrations')
    and not exists (
      select 1 from private.auditoria_exenciones e
      where e.tabla = n.nspname || '.' || c.relname)
    and not exists (
      select 1
      from pg_catalog.pg_trigger t
      join pg_catalog.pg_proc p on p.oid = t.tgfoid
      where t.tgrelid = c.oid
        and not t.tgisinternal
        and p.proname in ('log_audit_crm', 'log_audit_change', 'log_audit_sin_secretos'))
  order by 1;
$$;

comment on function private.tablas_sin_rastro() is
  'Fuente única de la regla F1.4: tablas de crm/public sin rastro en audit_log que no estén declaradas en private.auditoria_exenciones. Debe devolver CERO filas.';

revoke all on function private.tablas_sin_rastro()
  from public, anon, authenticated, service_role;

-- 3.3 El vigía: mira el ESTADO todos los días y deja constancia.
create table if not exists private.auditoria_alertas (
  id           bigint generated always as identity primary key,
  tabla        text        not null,
  detectada_en timestamptz not null default pg_catalog.now(),
  resuelta_en  timestamptz
);

create unique index if not exists auditoria_alertas_abierta_unica
  on private.auditoria_alertas (tabla) where resuelta_en is null;

alter table private.auditoria_alertas enable row level security;
revoke all on table private.auditoria_alertas
  from public, anon, authenticated, service_role;

comment on table private.auditoria_alertas is
  'Lo que el vigía diario encontró sin rastro. Una alerta se cierra sola en cuanto la tabla recibe su auditor o se declara exenta.';

create or replace function private.vigia_auditoria()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_abiertas integer;
begin
  -- Abre lo nuevo
  insert into private.auditoria_alertas (tabla)
  select s.tabla from private.tablas_sin_rastro() s
  on conflict (tabla) where resuelta_en is null do nothing;

  -- Cierra lo que ya se resolvió (le colgaron el auditor o se declaró exenta)
  update private.auditoria_alertas a
     set resuelta_en = pg_catalog.now()
   where a.resuelta_en is null
     and not exists (select 1 from private.tablas_sin_rastro() s where s.tabla = a.tabla);

  select pg_catalog.count(*) into v_abiertas
  from private.auditoria_alertas where resuelta_en is null;
  return v_abiertas;
end;
$$;

comment on function private.vigia_auditoria() is
  'Corre a diario por pg_cron: abre alerta por cada tabla sin rastro y cierra las resueltas. Devuelve cuántas quedan abiertas.';

revoke all on function private.vigia_auditoria()
  from public, anon, authenticated, service_role;

select cron.schedule(
  'crm-auditoria-vigia',
  '29 6 * * *',                      -- 01:29 en Lima, junto a las otras caducidades
  'select private.vigia_auditoria()'
);

-- ---------------------------------------------------------------------------
-- 4. Postflight — la migración se deshace sola si algo no quedó como se dijo
-- ---------------------------------------------------------------------------

do $postflight$
declare
  v_faltan text;
  v_def text;
  v_prueba jsonb;
  v_sin_rastro text;
  v_exentas text;
  v_abiertas integer;
begin
  -- 4.1 Los tres triggers existen y apuntan al auditor correcto
  select pg_catalog.string_agg(x, ', ') into v_faltan from (
    select 'crm.operaciones_cartera' as x
    where not exists (
      select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
      where t.tgrelid = 'crm.operaciones_cartera'::regclass
        and t.tgname = 'trg_audit_operaciones_cartera' and p.proname = 'log_audit_crm')
    union all
    select 'crm.agenda_ics'
    where not exists (
      select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
      where t.tgrelid = 'crm.agenda_ics'::regclass
        and t.tgname = 'trg_audit_agenda_ics' and p.proname = 'log_audit_sin_secretos')
    union all
    select 'public.suscripciones_push'
    where not exists (
      select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
      where t.tgrelid = 'public.suscripciones_push'::regclass
        and t.tgname = 'trg_audit_suscripciones_push' and p.proname = 'log_audit_sin_secretos')
  ) z;
  if v_faltan is not null then
    raise exception 'F1.4: falta el rastro en %', v_faltan;
  end if;

  -- 4.2 El UPDATE OF de suscripciones_push sobrevivió (trampa conocida: un
  --     DROP+CREATE se lleva en silencio la lista de columnas)
  select pg_catalog.pg_get_triggerdef(t.oid) into v_def
  from pg_trigger t where t.tgrelid = 'public.suscripciones_push'::regclass
    and t.tgname = 'trg_audit_suscripciones_push';
  if pg_catalog.strpos(v_def, 'UPDATE OF cliente_id, endpoint, p256dh, auth, dispositivo, activo') = 0 then
    raise exception 'F1.4: el trigger de suscripciones_push perdió su lista de columnas: %', v_def;
  end if;

  -- 4.3 El enmascarado funciona de verdad: el valor NO aparece
  v_prueba := private.enmascarar_claves(
    '{"perfil_id":"00000000-0000-0000-0000-000000000000","token":"secreto-de-prueba","nota":"visible"}'::jsonb,
    array['token','p256dh','auth','endpoint']);
  if pg_catalog.strpos(v_prueba::text, 'secreto-de-prueba') > 0 then
    raise exception 'F1.4: el enmascarado NO oculta el secreto: %', v_prueba;
  end if;
  if pg_catalog.strpos(v_prueba::text, 'visible') = 0 then
    raise exception 'F1.4: el enmascarado se comió un campo que no era secreto: %', v_prueba;
  end if;
  if v_prueba ->> 'token' <> '***:' || pg_catalog.left(pg_catalog.md5('secreto-de-prueba'), 8) then
    raise exception 'F1.4: la huella del secreto no es la esperada: %', v_prueba ->> 'token';
  end if;

  -- 4.4 La regla vive en el servidor y da CERO
  select pg_catalog.string_agg(s.tabla, ', ') into v_sin_rastro
  from private.tablas_sin_rastro() s;
  if v_sin_rastro is not null then
    raise exception 'F1.4: quedan tablas sin rastro: [%]', v_sin_rastro;
  end if;

  -- 4.5 Las exenciones son exactamente las dos declaradas
  select pg_catalog.string_agg(e.tabla, ', ' order by e.tabla) into v_exentas
  from private.auditoria_exenciones e;
  if v_exentas is distinct from 'crm.usuario_eventos, public.novedades_leidas' then
    raise exception 'F1.4: la lista blanca no es la esperada: [%]', coalesce(v_exentas, '(vacía)');
  end if;

  -- 4.6 El vigía está programado y corre limpio
  if not exists (select 1 from cron.job where jobname = 'crm-auditoria-vigia' and active) then
    raise exception 'F1.4: el vigía diario no quedó programado';
  end if;
  select private.vigia_auditoria() into v_abiertas;
  if v_abiertas <> 0 then
    raise exception 'F1.4: el vigía abrió % alerta(s) en su primera pasada', v_abiertas;
  end if;

  raise notice 'F1.4 OK: 3 huecos cerrados · secretos enmascarados · regla en el servidor con 2 exenciones declaradas · vigía diario armado y en cero';
end;
$postflight$;
$mig_f1_4$]
)
on conflict (version) do update
  set name = excluded.name, statements = excluded.statements;

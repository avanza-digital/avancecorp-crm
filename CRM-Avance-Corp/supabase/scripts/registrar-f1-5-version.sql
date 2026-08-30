-- Registra la versión 20260829233000 en el registro de migraciones CON su cuerpo.
insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260829233000',
  'crm_f1_5_auditoria_de_verdad',
  array[$mig_f1_5$-- P-055 · FASE 1.5 — ENMIENDA DE LA F1.4 TRAS LA AUDITORÍA
--
-- La F1.4 (20260829230000) se auditó ANTES de aplicarse y volvió con tres
-- bloqueantes y varios altos. Como no se edita una migración ya versionada, la
-- corrección viaja aquí. Las dos se publican juntas y en orden.
--
-- LO QUE LA AUDITORÍA ENCONTRÓ Y AQUÍ SE ARREGLA
--
--  1. 🔴 LA REGLA SOLO PREGUNTABA «¿HAY ALGÚN TRIGGER?», no «¿audita de
--     verdad?». Medido en producción: NUEVE tablas que el gate habría dado por
--     buenas tienen la auditoría a medias — `crm.meta_periodos`,
--     `crm.metas_vendedor`, `crm.metas_vendedor_detalle`, `crm.sla_politicas`,
--     `crm.sla_politica_etapas` (sin UPDATE ni DELETE) y `crm.lead_asignaciones`,
--     `crm.lead_asignacion_sla_hitos`, `crm.lead_sla_ciclos`,
--     `crm.lead_sla_etapas` (sin DELETE). Un ledger de asignaciones cuyos
--     borrados no dejan rastro es exactamente lo que la Fase 1 quería impedir.
--     Ahora la regla exige trigger ACTIVO, POR FILA, apuntando al auditor POR
--     OID (una función señuelo con el mismo nombre pasaba) y los TRES verbos; y
--     esta migración completa las nueve.
--
--  2. 🔴 EL RUIDO QUE LA F1.4 DECÍA EVITAR NO SE EVITABA. El portal guarda la
--     suscripción con un `upsert` que lista TODAS las columnas en el SET, y lo
--     hace en CADA carga del panel: un `UPDATE OF` dispara por estar la columna
--     en el SET, cambie o no de valor. Con 216 dispositivos activos, eran
--     cientos de filas idénticas al día. Se parte en dos triggers y el de
--     cambios lleva un WHEN que compara valores de verdad.
--
--  3. 🔴 LA LISTA DE SECRETOS ERA GLOBAL Y FIJA → fail-open el día que alguien
--     colgara el auditor de otra tabla cuyo secreto se llame distinto. Ahora las
--     columnas a tapar se le pasan al trigger como argumentos, y sin argumentos
--     el auditor se niega a correr.
--
--  4. La defensa anti-FK estaba solo en el auditor nuevo; la tabla del DINERO
--     (`crm.operaciones_cartera`) cuelga del de siempre. Se lleva también allí.
--
--  5. `public.audit_log` estaba excluida a mano DENTRO de la función: una
--     segunda lista blanca que nadie vigilaba. Pasa a declararse como exención
--     con su razón. (`public.schema_migrations` se cae: no existe en `public`.)
--
--  6. El interruptor que puede apagar una auditoría no dejaba rastro: la tabla
--     de exenciones ahora se audita a sí misma, y el vigía guarda un sello de la
--     lista para abrir alerta si alguien la toca fuera del repo.
--
--  7. Un `id` no-uuid abortaba la operación auditada: el cast va protegido.

-- ---------------------------------------------------------------------------
-- 1. Auditores: secretos por argumento, y la defensa anti-FK en los dos
-- ---------------------------------------------------------------------------

create or replace function private.log_audit_sin_secretos()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secretos text[];
  v_fila uuid;
  v_actor uuid;
begin
  -- Las columnas a tapar se declaran EN EL TRIGGER, no aquí: una lista global
  -- convertiría este auditor en fail-open la primera vez que se cuelgue de una
  -- tabla cuyo secreto se llame de otra forma.
  if tg_nargs = 0 then
    raise exception 'log_audit_sin_secretos exige las columnas a enmascarar como argumentos del trigger (tabla %.%)',
      tg_table_schema, tg_table_name;
  end if;
  v_secretos := tg_argv::text[];

  -- El id puede no ser uuid: el rastro nunca puede tumbar lo que audita.
  begin
    v_fila := coalesce(
      (pg_catalog.to_jsonb(coalesce(new, old)) ->> 'id')::uuid,
      (pg_catalog.to_jsonb(coalesce(new, old)) ->> 'perfil_id')::uuid
    );
  exception when invalid_text_representation then
    v_fila := null;
  end;

  -- audit_log.usuario_id apunta a public.perfiles: un actor de Auth todavía sin
  -- perfil haría fallar la FK y, con ella, la operación de negocio.
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
  'Auditor para tablas que guardan secretos. Mismo rastro que log_audit_crm pero enmascarando las columnas que el trigger le pase como argumentos (sin argumentos, se niega a correr).';

revoke all on function private.log_audit_sin_secretos()
  from public, anon, authenticated, service_role;

-- El auditor de siempre (cuelga de la tabla del dinero y de otras 41).
--
-- Dos cambios, los dos declarados:
--  · CONDUCTA: si el actor no tiene perfil, guarda sin actor en vez de abortar
--    la operación de negocio; y un id no-uuid ya no la tumba. Medido hoy: 0
--    miembros de equipo sin perfil, así que el rastro no cambia para nadie.
--  · SEGURIDAD: pasa de `search_path = 'public','crm'` a `search_path = ''` con
--    todo calificado, que es la postura del resto del servidor. Es a mejor, pero
--    es un cambio: por eso el rollback restaura la definición original al byte.
--
-- Se ancla la versión viva antes de tocarla: si otra sesión la cambió mientras
-- tanto, esta migración aborta en vez de pisar trabajo ajeno.
do $ancla$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname = 'log_audit_crm'
      and pg_catalog.md5(p.prosrc) = '461846328cab450929731c0ca9edd319'
  ) then
    raise exception 'F1.5: private.log_audit_crm ya no es la versión anclada (md5 461846328…). Otra sesión la cambió: revisar antes de continuar.';
  end if;
end;
$ancla$;

create or replace function private.log_audit_crm()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fila uuid;
  v_actor uuid;
begin
  begin
    v_fila := coalesce(
      (pg_catalog.to_jsonb(coalesce(new, old)) ->> 'id')::uuid,
      (pg_catalog.to_jsonb(coalesce(new, old)) ->> 'perfil_id')::uuid
    );
  exception when invalid_text_representation then
    v_fila := null;
  end;

  select p.id into v_actor
  from public.perfiles p where p.id = (select auth.uid());

  insert into public.audit_log (tabla, operacion, fila_id, usuario_id, data_antes, data_despues)
  values (
    tg_table_schema || '.' || tg_table_name,
    tg_op,
    v_fila,
    v_actor,
    case when tg_op in ('UPDATE','DELETE') then pg_catalog.to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then pg_catalog.to_jsonb(new) end
  );

  return coalesce(new, old);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Los triggers de las tablas con secretos, con sus columnas declaradas
-- ---------------------------------------------------------------------------

drop trigger if exists trg_audit_agenda_ics on crm.agenda_ics;
create trigger trg_audit_agenda_ics
  after insert or update or delete on crm.agenda_ics
  for each row execute function private.log_audit_sin_secretos('token');

-- DOS triggers a propósito (ver el punto 2 de la cabecera).
drop trigger if exists trg_audit_suscripciones_push on public.suscripciones_push;
create trigger trg_audit_suscripciones_push
  after insert or delete on public.suscripciones_push
  for each row execute function private.log_audit_sin_secretos('endpoint', 'p256dh', 'auth');

drop trigger if exists trg_audit_suscripciones_push_upd on public.suscripciones_push;
create trigger trg_audit_suscripciones_push_upd
  after update on public.suscripciones_push
  for each row
  when (old.cliente_id is distinct from new.cliente_id
     or old.endpoint is distinct from new.endpoint
     or old.p256dh is distinct from new.p256dh
     or old.auth is distinct from new.auth
     or old.dispositivo is distinct from new.dispositivo
     or old.activo is distinct from new.activo)
  execute function private.log_audit_sin_secretos('endpoint', 'p256dh', 'auth');

-- ---------------------------------------------------------------------------
-- 3. Las NUEVE con cobertura a medias: se les añade SOLO el verbo que falta,
--    con su mismo auditor. No se toca ningún trigger vivo.
-- ---------------------------------------------------------------------------

do $completar$
declare
  r record;
  v_verbos text;
  v_cuantas int := 0;
begin
  for r in
    select n.nspname as esquema, c.relname as tabla,
           pg_catalog.bool_or((t.tgtype & 4) > 0) as tiene_insert,
           pg_catalog.bool_or((t.tgtype & 16) > 0) as tiene_update,
           pg_catalog.bool_or((t.tgtype & 8) > 0) as tiene_delete
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    join pg_catalog.pg_trigger t on t.tgrelid = c.oid and not t.tgisinternal
    where n.nspname in ('crm','public')
      and c.relkind in ('r','p')
      and not c.relispartition
      and t.tgenabled <> 'D'
      and (t.tgtype & 1) = 1
      and t.tgfoid in ('private.log_audit_crm()'::regprocedure,
                       'public.log_audit_change()'::regprocedure,
                       'private.log_audit_sin_secretos()'::regprocedure)
    group by n.nspname, c.relname
    having not (pg_catalog.bool_or((t.tgtype & 4) > 0)
            and pg_catalog.bool_or((t.tgtype & 16) > 0)
            and pg_catalog.bool_or((t.tgtype & 8) > 0))
  loop
    v_verbos := pg_catalog.array_to_string(
      pg_catalog.array_remove(array[
        case when not r.tiene_insert then 'insert' end,
        case when not r.tiene_update then 'update' end,
        case when not r.tiene_delete then 'delete' end
      ], null), ' or ');

    execute pg_catalog.format(
      'create trigger %I after %s on %I.%I for each row execute function private.log_audit_crm()',
      pg_catalog.left('trg_audit_' || r.tabla || '_completa', 63), v_verbos, r.esquema, r.tabla);

    v_cuantas := v_cuantas + 1;
    raise notice 'Cobertura completada en %.% (%)', r.esquema, r.tabla, v_verbos;
  end loop;
  raise notice 'Tablas con cobertura completada: %', v_cuantas;
end;
$completar$;

-- ---------------------------------------------------------------------------
-- 4. La lista blanca: con rastro propio, con audit_log dentro, y sellada
-- ---------------------------------------------------------------------------

-- El interruptor que puede apagar una auditoría se audita a sí mismo.
drop trigger if exists trg_audit_auditoria_exenciones on private.auditoria_exenciones;
create trigger trg_audit_auditoria_exenciones
  after insert or update or delete on private.auditoria_exenciones
  for each row execute function private.log_audit_crm();

-- Deja de estar excluida a mano dentro de la función (segunda lista blanca que
-- nadie vigilaba) y pasa a declararse como lo que es.
insert into private.auditoria_exenciones (tabla, razon) values
  ('public.audit_log',
   'Es la auditoría misma: colgarle un auditor sería una recursión infinita. Su integridad la dan sus permisos y la ausencia de política de borrado, no un rastro de sí misma.')
on conflict (tabla) do nothing;

create table if not exists private.auditoria_sello (
  unico   boolean primary key default true,
  huella  text    not null,
  sellado timestamptz not null default pg_catalog.now(),
  constraint auditoria_sello_una_sola_fila check (unico)
);

alter table private.auditoria_sello enable row level security;
revoke all on table private.auditoria_sello
  from public, anon, authenticated, service_role;

comment on table private.auditoria_sello is
  'Huella de la lista blanca tal y como la dejó la última migración. Si la lista viva deja de coincidir, el vigía abre alerta sin esperar a que nadie corra el gate.';

create or replace function private.huella_exenciones()
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.md5(coalesce(pg_catalog.string_agg(e.tabla, '|' order by e.tabla), ''))
  from private.auditoria_exenciones e;
$$;

revoke all on function private.huella_exenciones()
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. La regla, ahora de verdad
-- ---------------------------------------------------------------------------

create or replace function private.tablas_sin_rastro()
returns table (tabla text)
language sql
stable
security invoker
set search_path = ''
as $$
  select n.nspname || '.' || c.relname
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  -- 'r' tabla normal · 'p' particionada. Las hijas se saltan: heredan el
  -- rastro del padre.
  where c.relkind in ('r', 'p')
    and not c.relispartition
    and c.relpersistence = 'p'
    and n.nspname in ('crm', 'public')
    and not exists (
      select 1 from private.auditoria_exenciones e
      where e.tabla = n.nspname || '.' || c.relname)
    -- Rastro DE VERDAD: trigger activo, por fila, auditor conocido POR OID
    -- (por nombre, una función señuelo pasaría) y los tres verbos cubiertos.
    and coalesce((
      select pg_catalog.bit_or(t.tgtype)
      from pg_catalog.pg_trigger t
      where t.tgrelid = c.oid
        and not t.tgisinternal
        and t.tgenabled <> 'D'
        and (t.tgtype & 1) = 1
        and t.tgfoid in ('private.log_audit_crm()'::regprocedure,
                         'public.log_audit_change()'::regprocedure,
                         'private.log_audit_sin_secretos()'::regprocedure)
    ), 0) & 28 <> 28   -- 4 INSERT | 8 DELETE | 16 UPDATE
  order by 1;
$$;

comment on function private.tablas_sin_rastro() is
  'Fuente única de la regla F1.4/F1.5: tablas de crm/public sin rastro COMPLETO (trigger activo, por fila, auditor conocido por OID y los tres verbos) que no estén declaradas en private.auditoria_exenciones. Debe devolver CERO filas.';

revoke all on function private.tablas_sin_rastro()
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6. El vigía, que además cuida la lista blanca
-- ---------------------------------------------------------------------------

create or replace function private.vigia_auditoria()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_abiertas integer;
  v_sello text;
begin
  insert into private.auditoria_alertas (tabla)
  select s.tabla from private.tablas_sin_rastro() s
  on conflict (tabla) where resuelta_en is null do nothing;

  -- ¿Alguien tocó la lista blanca sin pasar por una migración?
  select h.huella into v_sello from private.auditoria_sello h;
  if v_sello is distinct from private.huella_exenciones() then
    insert into private.auditoria_alertas (tabla)
    values ('__lista_blanca_alterada')
    on conflict (tabla) where resuelta_en is null do nothing;
  else
    update private.auditoria_alertas a
       set resuelta_en = pg_catalog.now()
     where a.tabla = '__lista_blanca_alterada' and a.resuelta_en is null;
  end if;

  update private.auditoria_alertas a
     set resuelta_en = pg_catalog.now()
   where a.resuelta_en is null
     and a.tabla <> '__lista_blanca_alterada'
     and not exists (select 1 from private.tablas_sin_rastro() s where s.tabla = a.tabla);

  select pg_catalog.count(*) into v_abiertas
  from private.auditoria_alertas where resuelta_en is null;
  return v_abiertas;
end;
$$;

comment on function private.vigia_auditoria() is
  'Corre a diario por pg_cron: abre alerta por cada tabla sin rastro completo y por la lista blanca alterada, y cierra las resueltas. Devuelve cuántas quedan abiertas.';

revoke all on function private.vigia_auditoria()
  from public, anon, authenticated, service_role;

-- El sello, con la lista ya completa
insert into private.auditoria_sello (unico, huella)
values (true, private.huella_exenciones())
on conflict (unico) do update set huella = excluded.huella, sellado = pg_catalog.now();

-- ---------------------------------------------------------------------------
-- 7. Postflight
-- ---------------------------------------------------------------------------

do $postflight$
declare
  v_def text;
  v_sin_rastro text;
  v_exentas text;
  v_abiertas integer;
  v_cols text;
  v_incompletas int;
begin
  -- 7.1 El auditor con secretos se NIEGA a correr sin argumentos
  if exists (
    select 1 from pg_trigger t
    where t.tgfoid = 'private.log_audit_sin_secretos()'::regprocedure
      and not t.tgisinternal
      and t.tgnargs = 0
  ) then
    raise exception 'F1.5: hay un trigger que usa el auditor de secretos SIN declarar columnas';
  end if;

  -- 7.2 El WHEN del trigger de cambios sobrevivió (trampa conocida: un
  --     DROP+CREATE se lleva en silencio la cláusula WHEN)
  select pg_catalog.pg_get_triggerdef(t.oid) into v_def
  from pg_trigger t where t.tgrelid = 'public.suscripciones_push'::regclass
    and t.tgname = 'trg_audit_suscripciones_push_upd';
  if v_def is null
     or pg_catalog.strpos(v_def, 'WHEN') = 0
     or pg_catalog.strpos(v_def, 'old.activo IS DISTINCT FROM new.activo') = 0 then
    raise exception 'F1.5: el trigger de cambios de suscripciones_push perdió su WHEN: %', coalesce(v_def, '(no existe)');
  end if;
  if pg_catalog.strpos(v_def, 'actualizado_en') > 0 then
    raise exception 'F1.5: el WHEN incluye la columna de reloj y volvería a llenar la auditoría de ruido';
  end if;

  -- 7.3 Las columnas de las dos tablas con secretos, pinneadas: una columna
  --     nueva rompe la migración en vez de filtrarse en claro
  select pg_catalog.string_agg(c.column_name, ',' order by c.column_name) into v_cols
  from information_schema.columns c
  where c.table_schema = 'crm' and c.table_name = 'agenda_ics';
  if v_cols is distinct from 'creado_en,perfil_id,rotado_en,token' then
    raise exception 'F1.5: crm.agenda_ics cambió de columnas (%). Revisar qué hay que enmascarar.', v_cols;
  end if;

  select pg_catalog.string_agg(c.column_name, ',' order by c.column_name) into v_cols
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = 'suscripciones_push';
  if v_cols is distinct from 'activo,actualizado_en,auth,cliente_id,creado_en,dispositivo,endpoint,id,p256dh,user_agent' then
    raise exception 'F1.5: public.suscripciones_push cambió de columnas (%). Revisar qué hay que enmascarar.', v_cols;
  end if;

  -- 7.4 Cero tablas con cobertura parcial en todo crm+public
  select pg_catalog.count(*) into v_incompletas from (
    select 1
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    join pg_trigger t on t.tgrelid = c.oid and not t.tgisinternal
    where n.nspname in ('crm','public') and c.relkind in ('r','p') and not c.relispartition
      and t.tgenabled <> 'D' and (t.tgtype & 1) = 1
      and t.tgfoid in ('private.log_audit_crm()'::regprocedure,
                       'public.log_audit_change()'::regprocedure,
                       'private.log_audit_sin_secretos()'::regprocedure)
    group by c.oid
    having pg_catalog.bit_or(t.tgtype) & 28 <> 28
  ) z;
  if v_incompletas <> 0 then
    raise exception 'F1.5: quedan % tabla(s) con auditoría a medias', v_incompletas;
  end if;

  -- 7.5 La regla da CERO
  select pg_catalog.string_agg(s.tabla, ', ') into v_sin_rastro
  from private.tablas_sin_rastro() s;
  if v_sin_rastro is not null then
    raise exception 'F1.5: quedan tablas sin rastro completo: [%]', v_sin_rastro;
  end if;

  -- 7.6 Las exenciones son exactamente las tres, y el sello cuadra
  select pg_catalog.string_agg(e.tabla, ', ' order by e.tabla) into v_exentas
  from private.auditoria_exenciones e;
  if v_exentas is distinct from 'crm.usuario_eventos, public.audit_log, public.novedades_leidas' then
    raise exception 'F1.5: la lista blanca no es la esperada: [%]', coalesce(v_exentas, '(vacía)');
  end if;
  if not exists (select 1 from private.auditoria_sello where huella = private.huella_exenciones()) then
    raise exception 'F1.5: el sello de la lista blanca no cuadra con la lista viva';
  end if;

  -- 7.7 El vigía corre limpio
  select private.vigia_auditoria() into v_abiertas;
  if v_abiertas <> 0 then
    raise exception 'F1.5: el vigía dejó % alerta(s) abiertas', v_abiertas;
  end if;

  raise notice 'F1.5 OK: regla completa (3 verbos, por OID, trigger activo) · coberturas parciales completadas · secretos por argumento · lista blanca sellada y auditada';
end;
$postflight$;

-- El canal `supabase db query` NO transporta los NOTICE: el veredicto tiene que
-- viajar como FILA. Si algo de arriba falló, esta sentencia no llega a correr.
select 'F1_5_APLICADA' as veredicto,
       (select pg_catalog.count(*) from private.tablas_sin_rastro()) as sin_rastro,
       (select pg_catalog.count(*) from private.auditoria_exenciones) as exenciones,
       (select pg_catalog.count(*) from private.auditoria_alertas where resuelta_en is null) as alertas_abiertas;
$mig_f1_5$]
)
on conflict (version) do update
  set name = excluded.name, statements = excluded.statements;

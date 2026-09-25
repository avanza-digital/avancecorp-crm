-- public.audit_log pasa a ser de SOLO AÑADIR.
--
-- Por qué (medido en producción el 24/09/2026): la bitácora se podía reescribir.
--   ACL: anon=arwd, authenticated=arwd, service_role=arwdDxtm; ningún trigger.
--   A anon y authenticated solo los frenaba que no hubiera policy de UPDATE ni
--   DELETE; service_role (las Edge Functions) salta la RLS y podía editar,
--   borrar o vaciar la tabla entera.
-- Nadie legítimo lo hace: ninguna función de la base, job de pg_cron, Edge
-- Function, portal ni app hace UPDATE, DELETE o TRUNCATE sobre audit_log, y los
-- cinco que insertan (log_audit_change, log_audit_crm, log_audit_sin_secretos,
-- marcar_contrato_demo y corregir_fecha_cierre_comercial) son SECURITY DEFINER
-- de postgres.
--
-- La ÚNICA modificación legítima es la FK usuario_id → perfiles ON DELETE SET
-- NULL: borrar un usuario (auth.users → perfiles en cascada; lo hace, p. ej.,
-- la edge eliminar-cliente) anonimiza su rastro. El trigger la deja pasar solo
-- si (a) llega anidada en otro trigger, como la acción de integridad
-- referencial; (b) lo único que cambia es usuario_id → NULL: se comparan las
-- siete columnas con su tipo (distingue un NULL de SQL de un 'null'::jsonb) Y la
-- fila entera en jsonb (para que una columna futura no se cuele); y (c) el
-- perfil al que apuntaba ya no existe, que es justo lo que hace la FK. Sin esa
-- excepción, borrar un usuario fallaría.
--
-- Qué hace:
--   1) Quita UPDATE, DELETE, TRUNCATE, REFERENCES y TRIGGER a public, anon,
--      authenticated y service_role. SELECT, INSERT y (service_role) MAINTAIN
--      no se tocan.
--   2) Instala dos triggers que abortan UPDATE, DELETE y TRUNCATE (P0409) también
--      para el dueño. Frente al dueño es una protección contra el DML
--      accidental, no una frontera de seguridad: él siempre puede desactivar el
--      trigger. Una purga futura por retención tendrá que ser una migración
--      explícita que lo haga a propósito.
--
-- Riesgos que quedan FUERA (declarados en MIGRACIONES.md): service_role conserva
-- INSERT con BYPASSRLS (podría añadir filas falsas o antedatadas: «solo añadir»
-- no es «no falsificable») y MAINTAIN (permite LOCK TABLE).
--
-- Excepción escrita a la regla heredada «ninguna migración altera public»
-- (migrations/LEEME.md): hay precedente en el P-055 (F1, F3 y F7) y Miguel la
-- autorizó el 24/09/2026 (auditoría ACID, P1 #2: «Arranca sii»).
--
-- Aplicar en horario valle: CREATE TRIGGER toma SHARE ROW EXCLUSIVE sobre
-- audit_log y, mientras dure la transacción, las escrituras auditadas esperan.
--
-- Reversa: supabase/scripts/rollback-audit-log-solo-anadir.sql.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';

do $preflight$
declare v_acl text; v_cron boolean := false;
begin
  select c.relacl::text into v_acl from pg_class c where c.oid = 'public.audit_log'::regclass;
  if v_acl is distinct from '{postgres=arwdDxtm/postgres,anon=arwd/postgres,authenticated=arwd/postgres,service_role=arwdDxtm/postgres}' then
    raise exception 'audit_log: el ACL cambió desde la medida del 24/09 (%)', v_acl;
  end if;
  if exists (select 1 from pg_trigger t where t.tgrelid = 'public.audit_log'::regclass and not t.tgisinternal) then
    raise exception 'audit_log: ya tiene triggers; revisar antes de seguir';
  end if;
  if (select count(*) from pg_constraint k where k.conrelid = 'public.audit_log'::regclass and k.contype = 'f') <> 1
     or coalesce((select pg_get_constraintdef(k.oid) from pg_constraint k
                   where k.conname = 'audit_log_usuario_id_fkey' and k.conrelid = 'public.audit_log'::regclass)
                 ~ '^FOREIGN KEY \(usuario_id\) REFERENCES (public\.)?perfiles\(id\) ON DELETE SET NULL$', false) is not true then
    raise exception 'audit_log: la FK usuario_id → perfiles no es la única ni la medida (ON DELETE SET NULL)';
  end if;
  if exists (select 1 from pg_attribute a
             where a.attrelid = 'public.audit_log'::regclass and a.attnum > 0 and a.attacl is not null) then
    raise exception 'audit_log: tiene grants por columna; revisar antes de seguir';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname not in ('pg_catalog', 'information_schema')
               and lower(p.prosrc) ~ '(update\s+(only\s+)?("?public"?\.)?"?audit_log"?\M|delete\s+from\s+(only\s+)?("?public"?\.)?"?audit_log"?\M|truncate\s+(table\s+)?(only\s+)?("?public"?\.)?"?audit_log"?\M|merge\s+into\s+("?public"?\.)?"?audit_log"?\M)') then
    raise exception 'audit_log: una función de la base la modifica; revisar antes de seguir';
  end if;
  if to_regclass('cron.job') is not null then
    execute 'select exists (select 1 from cron.job j where j.command ~* ''audit_log'')' into v_cron;
    if v_cron then
      raise exception 'audit_log: un job de pg_cron la nombra; revisar antes de seguir';
    end if;
  end if;
  if not exists (select 1 from public.audit_log) then
    raise exception 'audit_log vacía: la prueba de conducta del postflight no probaría nada';
  end if;
end; $preflight$;

-- 1) Permisos: fuera todo lo que reescribe o vacía la bitácora.
revoke update, delete, truncate, references, trigger on table public.audit_log
  from public, anon, authenticated, service_role;

-- 2) El candado.
create function private.trg_audit_log_solo_anadir()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if tg_op = 'UPDATE' then
    -- La única escritura legítima: la FK usuario_id → perfiles ON DELETE SET
    -- NULL. Llega anidada (la acción de integridad referencial es un trigger),
    -- solo anonimiza al actor y el perfil al que apuntaba ya no existe.
    if pg_catalog.pg_trigger_depth() > 1
       and old.usuario_id is not null and new.usuario_id is null
       and not exists (select 1 from public.perfiles p where p.id = old.usuario_id)
       and (new.id, new.tabla, new.operacion, new.fila_id, new.ts, new.data_antes, new.data_despues)
           is not distinct from
           (old.id, old.tabla, old.operacion, old.fila_id, old.ts, old.data_antes, old.data_despues)
       and (pg_catalog.to_jsonb(new) - 'usuario_id') = (pg_catalog.to_jsonb(old) - 'usuario_id')
    then
      return new;
    end if;
  end if;
  raise exception using
    errcode = 'P0409',
    message = 'La bitácora (public.audit_log) es de solo añadir: no se edita, no se borra ni se vacía',
    hint    = 'Una purga por retención tiene que ser una migración explícita.';
end;
$function$;

revoke all on function private.trg_audit_log_solo_anadir() from public, anon, authenticated, service_role;

create trigger trg_audit_log_solo_anadir
  before update or delete on public.audit_log
  for each row execute function private.trg_audit_log_solo_anadir();

create trigger trg_audit_log_sin_vaciar
  before truncate on public.audit_log
  for each statement execute function private.trg_audit_log_solo_anadir();

comment on function private.trg_audit_log_solo_anadir() is
  'Candado de public.audit_log: aborta UPDATE, DELETE y TRUNCATE (P0409), también para el dueño (contra DML accidental; el dueño siempre puede desactivar el trigger). Única excepción: la cascada de la FK usuario_id → perfiles ON DELETE SET NULL, que solo anonimiza al actor de un perfil ya borrado. Migración 20260925002615_crm_audit_log_solo_anadir.';
comment on trigger trg_audit_log_solo_anadir on public.audit_log is
  'La bitácora es de solo añadir: ninguna fila se edita ni se borra (salvo la anonimización del actor por la FK).';
comment on trigger trg_audit_log_sin_vaciar on public.audit_log is
  'La bitácora no se vacía: TRUNCATE aborta.';

do $postflight$
declare v_rol text; v_priv text; v_id uuid;
begin
  foreach v_rol in array array['anon', 'authenticated', 'service_role'] loop
    foreach v_priv in array array['UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] loop
      if has_table_privilege(v_rol, 'public.audit_log', v_priv) then
        raise exception 'audit_log: % conserva %', v_rol, v_priv;
      end if;
    end loop;
  end loop;
  -- Lo que sí se usa no se tocó: la bandeja del portal (SELECT) y service_role.
  if not has_table_privilege('authenticated', 'public.audit_log', 'SELECT')
     or not has_table_privilege('service_role', 'public.audit_log', 'SELECT')
     or not has_table_privilege('service_role', 'public.audit_log', 'INSERT') then
    raise exception 'audit_log: se perdió un SELECT o INSERT que no debía tocarse';
  end if;
  if (select count(*) from pg_trigger t
       where t.tgrelid = 'public.audit_log'::regclass and not t.tgisinternal and t.tgenabled = 'O'
         and t.tgfoid = 'private.trg_audit_log_solo_anadir()'::regprocedure) <> 2 then
    raise exception 'audit_log: faltan los dos triggers activos';
  end if;
  -- Prueba de conducta, deshecha al instante: ni el dueño edita ni borra.
  -- Una fila por la clave primaria (índice): nada de recorrer la tabla con el candado puesto.
  select a.id into v_id from public.audit_log a order by a.id limit 1;
  begin
    update public.audit_log set tabla = tabla where id = v_id;
    raise exception 'audit_log: el UPDATE directo pasó';
  exception when sqlstate 'P0409' then null;
  end;
  begin
    delete from public.audit_log where id = v_id;
    raise exception 'audit_log: el DELETE directo pasó';
  exception when sqlstate 'P0409' then null;
  end;
end; $postflight$;

select 'AUDIT_LOG_SOLO_ANADIR_OK' as veredicto,
  (select c.relacl::text from pg_class c where c.oid = 'public.audit_log'::regclass) as acl;
commit;

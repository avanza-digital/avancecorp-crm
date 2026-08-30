-- MARCHA ATRÁS de la FASE 1.4 (P-055) — deja el servidor como estaba antes de
-- `20260829230000_crm_f1_4_regla_de_auditoria.sql`.
--
-- Qué NO deshace, a propósito: las filas ya escritas en public.audit_log por los
-- tres auditores nuevos. Un rastro no se borra; solo se deja de escribir.
--
-- Ejecutar con:
--   npx supabase db query --linked --file supabase/scripts/rollback-f1-4-p055.sql
--   y luego borrar la versión del registro:
--   delete from supabase_migrations.schema_migrations where version = '20260829230000';

-- 1. El vigía deja de correr
select cron.unschedule('crm-auditoria-vigia')
where exists (select 1 from cron.job where jobname = 'crm-auditoria-vigia');

-- 2. Los tres auditores nuevos se retiran
drop trigger if exists trg_audit_operaciones_cartera on crm.operaciones_cartera;
drop trigger if exists trg_audit_agenda_ics on crm.agenda_ics;
drop trigger if exists trg_audit_suscripciones_push on public.suscripciones_push;

-- 3. La regla y su maquinaria
drop function if exists private.vigia_auditoria();
drop function if exists private.tablas_sin_rastro();
drop table if exists private.auditoria_alertas;
drop table if exists private.auditoria_exenciones;
drop function if exists private.log_audit_sin_secretos();
drop function if exists private.enmascarar_claves(jsonb, text[]);

-- 4. Comprobación: volvimos exactamente al estado anterior
do $vuelta$
declare
  v_sin_rastro text;
  v_restos text;
begin
  -- ⚠️ Dentro de un agregado, `order by 1` es la CONSTANTE 1, no la columna:
  -- hay que nombrar la expresión o la lista sale desordenada.
  select pg_catalog.string_agg(n.nspname || '.' || c.relname, ', '
                               order by n.nspname || '.' || c.relname)
    into v_sin_rastro
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where c.relkind in ('r','p') and not c.relispartition and c.relpersistence = 'p'
    and n.nspname in ('crm','public')
    and n.nspname || '.' || c.relname not in ('public.audit_log','public.schema_migrations')
    and not exists (
      select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
      where t.tgrelid = c.oid and not t.tgisinternal
        and p.proname in ('log_audit_crm','log_audit_change','log_audit_sin_secretos'));

  if v_sin_rastro is distinct from
     'crm.agenda_ics, crm.operaciones_cartera, crm.usuario_eventos, public.novedades_leidas, public.suscripciones_push' then
    raise exception 'La marcha atrás no dejó la foto original. Hoy: [%]', coalesce(v_sin_rastro, '(ninguna)');
  end if;

  select pg_catalog.string_agg(x, ', ') into v_restos from (
    select 'función ' || p.proname as x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname in ('enmascarar_claves','log_audit_sin_secretos','tablas_sin_rastro','vigia_auditoria')
    union all
    select 'tabla ' || c.relname
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relname in ('auditoria_exenciones','auditoria_alertas')
    union all
    select 'cron ' || jobname from cron.job where jobname = 'crm-auditoria-vigia'
  ) z;
  if v_restos is not null then
    raise exception 'Quedaron restos de F1.4: %', v_restos;
  end if;

  raise notice 'MARCHA ATRÁS F1.4 OK: servidor como antes (el rastro ya escrito se conserva, como debe)';
end;
$vuelta$;

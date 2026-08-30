-- MARCHA ATRÁS de las FASES 1.4, 1.5 y 1.6 (P-055) — deja el servidor como estaba
-- antes de `20260829230000`, `20260829233000` y `20260829235000`.
--
-- Qué NO deshace, a propósito: las filas ya escritas en public.audit_log por los
-- auditores nuevos. Un rastro no se borra; solo se deja de escribir.
--
-- Ejecutar con:
--   npx supabase db query --linked --file supabase/scripts/rollback-f1-4-p055.sql
--   y luego borrar las versiones del registro:
--   delete from supabase_migrations.schema_migrations
--    where version in ('20260829230000','20260829233000','20260829235000');

-- 1. El vigía deja de correr
select cron.unschedule('crm-auditoria-vigia')
where exists (select 1 from cron.job where jobname = 'crm-auditoria-vigia');

-- 2. Los auditores nuevos se retiran (incluidos los que completaron cobertura)
drop trigger if exists trg_audit_operaciones_cartera on crm.operaciones_cartera;
drop trigger if exists trg_audit_agenda_ics on crm.agenda_ics;
drop trigger if exists trg_audit_suscripciones_push on public.suscripciones_push;
drop trigger if exists trg_audit_suscripciones_push_upd on public.suscripciones_push;
drop trigger if exists trg_audit_auditoria_exenciones on private.auditoria_exenciones;
drop trigger if exists trg_audit_auditoria_condicionada on private.auditoria_condicionada;

do $completadas$
declare
  r record;
begin
  for r in
    select n.nspname as esquema, c.relname as tabla, t.tgname as trigger
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where not t.tgisinternal and t.tgname like 'trg\_audit\_%\_completa'
  loop
    execute pg_catalog.format('drop trigger %I on %I.%I', r.trigger, r.esquema, r.tabla);
    raise notice 'Retirado %', r.trigger;
  end loop;
end;
$completadas$;

-- 3. La regla y su maquinaria
drop function if exists private.assert_auditoria();
drop function if exists private.vigia_auditoria();
drop function if exists private.tablas_sin_rastro();
drop function if exists private.huella_exenciones();
drop table if exists private.auditoria_alertas;
drop table if exists private.auditoria_sello;
drop table if exists private.auditoria_exenciones;
drop table if exists private.auditoria_condicionada;
drop function if exists private.log_audit_sin_secretos();
drop function if exists private.enmascarar_claves(jsonb, text[]);

-- 4. El auditor de siempre, restaurado a su definición ORIGINAL (md5 del cuerpo
--    461846328cab450929731c0ca9edd319, incluido su search_path 'public','crm')
CREATE OR REPLACE FUNCTION private.log_audit_crm()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'crm'
AS $function$
declare
  v_fila uuid;
begin
  v_fila := coalesce(
    (to_jsonb(coalesce(new, old)) ->> 'id')::uuid,
    (to_jsonb(coalesce(new, old)) ->> 'perfil_id')::uuid
  );
  insert into public.audit_log (tabla, operacion, fila_id, usuario_id, data_antes, data_despues)
  values (
    tg_table_schema || '.' || tg_table_name,
    tg_op,
    v_fila,
    (select auth.uid()),
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end
  );
  return coalesce(new, old);
end;
$function$;

-- 5. Comprobación: volvimos exactamente al estado anterior
do $vuelta$
declare
  v_sin_rastro text;
  v_restos text;
  v_md5 text;
begin
  -- ⚠️ Dentro de un agregado, `order by 1` es la CONSTANTE 1, no la columna:
  -- hay que nombrar la expresión o la lista sale desordenada.
  select pg_catalog.string_agg(n.nspname || '.' || c.relname, ', '
                               order by n.nspname || '.' || c.relname)
    into v_sin_rastro
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where c.relkind in ('r','p') and not c.relispartition and c.relpersistence = 'p'
    and n.nspname in ('crm','public')
    and n.nspname || '.' || c.relname not in ('public.audit_log')
    and not exists (
      select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
      where t.tgrelid = c.oid and not t.tgisinternal
        and p.proname in ('log_audit_crm','log_audit_change'));

  if v_sin_rastro is distinct from
     'crm.agenda_ics, crm.operaciones_cartera, crm.usuario_eventos, public.novedades_leidas, public.suscripciones_push' then
    raise exception 'La marcha atrás no dejó la foto original. Hoy: [%]', coalesce(v_sin_rastro, '(ninguna)');
  end if;

  select pg_catalog.md5(p.prosrc) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'log_audit_crm';
  if v_md5 is distinct from '461846328cab450929731c0ca9edd319' then
    raise exception 'El auditor de siempre no volvió a su versión original (md5 %)', v_md5;
  end if;

  select pg_catalog.string_agg(x, ', ') into v_restos from (
    select 'función ' || p.proname as x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname in ('enmascarar_claves','log_audit_sin_secretos','tablas_sin_rastro',
                        'vigia_auditoria','huella_exenciones','assert_auditoria')
    union all
    select 'tabla ' || c.relname
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private'
      and c.relname in ('auditoria_exenciones','auditoria_alertas','auditoria_sello','auditoria_condicionada')
    union all
    select 'cron ' || jobname from cron.job where jobname = 'crm-auditoria-vigia'
    union all
    select 'trigger ' || t.tgname from pg_trigger t
    where not t.tgisinternal and t.tgname like 'trg\_audit\_%\_completa'
  ) z;
  if v_restos is not null then
    raise exception 'Quedaron restos de F1.4/F1.5: %', v_restos;
  end if;
end;
$vuelta$;

-- El veredicto viaja como FILA: este canal no transporta los avisos.
select 'MARCHA_ATRAS_F1_4_F1_5_F1_6_OK' as veredicto,
       (select pg_catalog.count(*) from public.audit_log
        where tabla in ('crm.agenda_ics','public.suscripciones_push','crm.operaciones_cartera')
       ) as rastro_conservado;

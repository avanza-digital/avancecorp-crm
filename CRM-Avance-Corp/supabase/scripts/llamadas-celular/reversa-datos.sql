-- Reversa de 20261001145242_crm_llamadas_celular_datos.sql · variante que CONSERVA LOS HECHOS.
--
-- Retira lo que ejecuta (cron, purga, candados) y deja las tablas con sus filas: la evidencia
-- de llamadas no se destruye por retirar la funcionalidad. Los triggers de AUDITORÍA se quedan
-- (regla private.tablas_sin_rastro: toda tabla crm.* audita). Sin candados, las tablas quedan
-- editables por el dueño; por eso esta reversa es un paso previo a `reversa-datos-total.sql` o a
-- una migración correctiva, nunca un estado final.
--
-- Molde: scripts/conversion-inversion/reversa.sql. Uso (banco o rama):
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/scripts/llamadas-celular/reversa-datos.sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regclass('crm.llamadas_celular_eventos') is null
     or to_regclass('crm.celulares_asignaciones') is null then
    raise exception 'REVERSA_LLAMADAS: la migración 20261001145242 no está aplicada';
  end if;
end;
$precondicion$;

-- 1. Reloj: desprogramar donde haya pg_cron (sin esto quedaría un error diario en cron.job_run_details).
--    La consulta a cron.job va ANIDADA: en la misma condición, PL/pgSQL la analiza aunque pg_cron
--    no exista y la reversa muere en un banco sin reloj (visto en el banco local, 01/10).
do $reloj$
begin
  if to_regprocedure('cron.unschedule(text)') is not null then
    if exists (select 1 from cron.job j where j.jobname = 'crm-llamadas-celular-caducidad') then
      perform cron.unschedule('crm-llamadas-celular-caducidad');
    end if;
  end if;
end;
$reloj$;

-- 2. Purga y candados (las funciones de auditoría son compartidas: no se tocan).
drop function if exists private.caducar_llamadas_celular();

drop trigger if exists trg_llamadas_celular_enlaces_00_candado on crm.llamadas_celular_enlaces;
drop trigger if exists trg_llamadas_celular_enlaces_00_sin_vaciar on crm.llamadas_celular_enlaces;
drop trigger if exists trg_llamadas_celular_eventos_00_candado on crm.llamadas_celular_eventos;
drop trigger if exists trg_llamadas_celular_eventos_00_sin_vaciar on crm.llamadas_celular_eventos;
drop trigger if exists trg_celulares_asignaciones_00_candado on crm.celulares_asignaciones;
drop trigger if exists trg_celulares_asignaciones_00_sin_vaciar on crm.celulares_asignaciones;
drop trigger if exists trg_llamadas_celular_politica_00_candado on crm.llamadas_celular_politica;
drop trigger if exists trg_llamadas_celular_politica_00_sin_vaciar on crm.llamadas_celular_politica;

drop function if exists private.trg_llamadas_celular_enlaces_candado();
drop function if exists private.trg_llamadas_celular_eventos_candado();
drop function if exists private.trg_celulares_asignaciones_candado();
drop function if exists private.trg_llamadas_celular_politica_candado();
drop function if exists private.trg_llamadas_celular_sin_vaciar();

-- 3. Postcheck: sin cron, sin candados, con auditoría y sin acceso de la API.
do $postcheck$
declare
  v_t text;
begin
  if to_regprocedure('cron.schedule(text,text,text)') is not null then
    if exists (select 1 from cron.job j where j.jobname = 'crm-llamadas-celular-caducidad') then
      raise exception 'REVERSA_LLAMADAS: el job de retención sigue programado';
    end if;
  end if;
  foreach v_t in array array['crm.llamadas_celular_politica', 'crm.celulares_asignaciones',
                             'crm.llamadas_celular_eventos', 'crm.llamadas_celular_enlaces'] loop
    if (select count(*) from pg_catalog.pg_trigger t where t.tgrelid = v_t::regclass and not t.tgisinternal) <> 1 then
      raise exception 'REVERSA_LLAMADAS: % debería conservar solo su trigger de auditoría', v_t;
    end if;
    if exists (select 1 from private.tablas_sin_rastro() s where s.tabla = v_t) then
      raise exception 'REVERSA_LLAMADAS: % perdió su rastro de auditoría', v_t;
    end if;
    if exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol)
               where pg_catalog.has_table_privilege(r.rol, v_t,
                       'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) then
      raise exception 'REVERSA_LLAMADAS: % quedó accesible desde la API', v_t;
    end if;
  end loop;
end;
$postcheck$;

notify pgrst, 'reload schema';
commit;

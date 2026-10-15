-- REACTIVAR el ciclo diario de cierre (job 3, `crm-cierre-mes-diario`), en pausa desde la reapertura de septiembre del
-- 14/10/2026 (scripts/reexpresion-septiembre-2026/01-reabrir.sql). Se corre SOLO cuando Gerencia ya fijó, desde la
-- pantalla, el plazo de carga de septiembre (crm.fijar_plazo_carga_mes) y ese plazo está en el FUTURO: así el ciclo no lo
-- vuelve a sellar antes de tiempo y lo sella solo cuando venza (corre a las 09:20 de Lima).
-- Se niega (sin tocar nada) si el job no es el ciclo pausado, si septiembre ya está sellado, si no hay decisión de
-- Gerencia para septiembre o si su plazo ya venció.
--   npx supabase db query --linked --file supabase/scripts/plazo-carga-mes/reactivar-ciclo.sql
begin;
set local lock_timeout = '10s';
do $guarda$
declare v_plazo timestamptz;
begin
  if (select auth.uid()) is not null then
    raise exception 'REACTIVAR: se corre sin sesión (consola)';
  end if;
  if to_regprocedure('crm.fijar_plazo_carga_mes(date,date,text)') is null then
    raise exception 'REACTIVAR: la migración 20261015000852 (plazo de carga por mes) no está aplicada';
  end if;
  if (select count(*) from cron.job where jobid = 3 and jobname = 'crm-cierre-mes-diario'
        and command ~ 'crm\.ciclo_cierre_mes\(\)' and not active) <> 1
     or (select count(*) from cron.job where jobname = 'crm-cierre-mes-diario') <> 1 then
    raise exception 'REACTIVAR: el job 3 no es el ciclo diario de cierre EN PAUSA (o hay más de uno); revisar';
  end if;
  if exists (select 1 from crm.periodos_cerrados where periodo = date '2026-09-01') then
    raise exception 'REACTIVAR: septiembre ya está sellado; revisar antes de reactivar';
  end if;
  if not exists (select 1 from crm.plazos_carga_mes where periodo = date '2026-09-01') then
    raise exception 'REACTIVAR: Gerencia todavía no fijó el plazo de carga de septiembre (pantalla «Plazo de carga»)';
  end if;
  v_plazo := private.conversion_plazo_hasta(date '2026-09-01');
  if v_plazo <= now() + interval '1 hour' then
    raise exception 'REACTIVAR: el plazo de septiembre (%) ya venció o vence en menos de una hora: el ciclo lo sellaría en su próxima pasada. Fijar otro plazo o sellar a propósito',
      (v_plazo at time zone 'America/Lima');
  end if;
  if now() >= private.cierre_mes_ventana_desde(date '2026-10-01') then
    raise exception 'REACTIVAR: la ventana de octubre ya abrió; revisar los dos meses antes de reactivar';
  end if;
end
$guarda$;
select cron.alter_job(job_id := 3, active := true);
do $post$
begin
  if (select active from cron.job where jobid = 3) is not true then
    raise exception 'REACTIVAR: el job 3 no quedó activo';
  end if;
end
$post$;
select jsonb_build_object(
  'resultado', 'CICLO DIARIO REACTIVADO: septiembre se sellará solo cuando venza su plazo',
  'plazo_septiembre_lima', (private.conversion_plazo_hasta(date '2026-09-01') at time zone 'America/Lima'),
  'job', (select jsonb_build_object('jobid', jobid, 'activo', active, 'horario', schedule) from cron.job where jobid = 3)
) as reactivacion;
commit;

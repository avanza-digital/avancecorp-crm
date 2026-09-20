-- REEXPRESIÓN DE AGOSTO 2026 — paso 2: volver a sellar y reanudar el ciclo.
-- Se ejecuta cuando los analistas terminaron de cargar los contratos de agosto.
-- Sella por el MISMO camino del reloj (crm.ciclo_cierre_mes) y reactiva el job diario.
-- Si el sellado falla, la transacción entera se revierte y el ciclo sigue en pausa.
-- Se ejecuta con: npx supabase db query --linked --file <este archivo>
begin;
set local lock_timeout = '10s';

do $pre$
begin
  if exists (select 1 from crm.periodos_cerrados where periodo = date '2026-08-01') then
    raise exception 'PREFLIGHT: agosto ya está sellado; nada que hacer';
  end if;
  if (select active from cron.job where jobid = 3) then
    raise exception 'PREFLIGHT: el ciclo diario ya está activo; ¿se ejecutó 01-reabrir.sql?';
  end if;
end $pre$;

-- Sin sesión (auth.uid() nulo) el ciclo corre igual que el reloj a las 09:20.
select crm.ciclo_cierre_mes() as resultado_del_ciclo;

select cron.alter_job(job_id := 3, active := true);

do $post$
declare v_filas integer;
begin
  if not exists (select 1 from crm.periodos_cerrados where periodo = date '2026-08-01') then
    raise exception 'POSTFLIGHT: el ciclo no selló agosto; revisar el resultado_del_ciclo de arriba';
  end if;
  select count(*) into v_filas from crm.cierre_mes_vendedor where periodo = date '2026-08-01';
  if v_filas = 0 then
    raise exception 'POSTFLIGHT: agosto sellado sin foto de vendedores';
  end if;
  if not (select active from cron.job where jobid = 3) then
    raise exception 'POSTFLIGHT: el ciclo diario sigue en pausa';
  end if;
  raise notice 'AGOSTO 2026 SELLADO DE NUEVO con % vendedores en la foto. Ciclo diario reactivado.', v_filas;
end $post$;
commit;

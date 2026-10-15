-- REEXPRESIÓN DE SEPTIEMBRE 2026 — paso 2: volver a sellar y reanudar el ciclo.
-- Se ejecuta cuando los analistas terminaron de cargar y SOLO si la configuración
-- de plazo de Gerencia todavía no está publicada (con ella, Gerencia fija el plazo y
-- el ciclo se reactiva con ../plazo-carga-mes/reactivar-ciclo.sql, que exige ese plazo
-- en el futuro). Sella por el MISMO camino del reloj (crm.ciclo_cierre_mes)
-- y reactiva el job diario. Si algo diverge, la transacción entera se revierte y
-- el ciclo sigue en pausa.
-- Se ejecuta con: npx supabase db query --linked --file <este archivo>
begin;
set local lock_timeout = '10s';

do $pre$
begin
  if (select auth.uid()) is not null
     or exists (select 1 from crm.periodos_cerrados where periodo >= date '2026-09-01')
     or (select active from cron.job where jobid = 3) is distinct from false
     or (select jobname from cron.job where jobid = 3) is distinct from 'crm-cierre-mes-diario'
     or private.cierre_mes_pendiente(
          date_trunc('month', now() at time zone 'America/Lima')::date
        ) is distinct from date '2026-09-01' then
    raise exception 'PREFLIGHT: se exige ciclo sin sesión, septiembre pendiente y reloj pausado';
  end if;
  -- El ciclo avanzaría a octubre desde el 11/11. Esta operación es solo para septiembre.
  if now() >= private.cierre_mes_ventana_desde(date '2026-10-01') then
    raise exception 'PREFLIGHT: la ventana de octubre ya abrió; revisar ambos meses';
  end if;
  if exists (select 1 from crm.ajustes_mes_cerrado where periodo_origen = date '2026-09-01')
     or exists (select 1 from crm.inversion_ajustes_mes_cerrado where periodo_origen = date '2026-09-01') then
    raise exception 'PREFLIGHT: hay ajustes de septiembre inesperados con el mes abierto';
  end if;
end $pre$;

-- Sin sesión (auth.uid() nulo) el ciclo corre igual que el reloj a las 09:20.
create temp table _ciclo on commit drop as select crm.ciclo_cierre_mes() as r;

do $sellado$
declare v_resultado jsonb := (select r from _ciclo);
begin
  if (v_resultado->>'ok')::boolean is distinct from true
     or (v_resultado->>'cerrados')::integer is distinct from 1
     or v_resultado #>> '{detalle,0,periodo}' is distinct from '2026-09' then
    raise exception 'POSTFLIGHT: el ciclo no selló solo septiembre: %', v_resultado;
  end if;
end $sellado$;

select cron.alter_job(job_id := 3, active := true);

do $post$
begin
  if not exists (select 1 from crm.periodos_cerrados where periodo = date '2026-09-01')
     or not exists (select 1 from crm.cierre_mes_vendedor where periodo = date '2026-09-01') then
    raise exception 'POSTFLIGHT: septiembre no quedó sellado con foto';
  end if;
  if exists (select 1 from crm.conversion_acreditaciones
             where periodo_comercial = date '2026-09-01' and sellado_en is null) then
    raise exception 'POSTFLIGHT: quedan acreditaciones de septiembre sin sellar';
  end if;
  if not (select active from cron.job where jobid = 3) then
    raise exception 'POSTFLIGHT: el ciclo diario no quedó activo';
  end if;
end $post$;

select jsonb_build_object(
  'resultado', 'SEPTIEMBRE 2026 SELLADO DE NUEVO. Ciclo diario reactivado.',
  'ciclo', (select r from _ciclo),
  'foto', (select count(*) from crm.cierre_mes_vendedor where periodo = date '2026-09-01')
) as resellado;
commit;

-- REEXPRESIÓN DE AGOSTO 2026 — paso 2: volver a sellar y reanudar el ciclo.
-- Se ejecuta tras anular las ventas de prueba confirmadas y publicar la meta
-- corregida. Una divergencia de estado revierte toda esta transacción.
-- Sella por el MISMO camino del reloj (crm.ciclo_cierre_mes) y reactiva el job diario.
-- Si el sellado falla, la transacción entera se revierte y el ciclo sigue en pausa.
begin;
set local lock_timeout = '10s';

do $pre$
begin
  if (select auth.uid()) is not null
     or (select count(*) from crm.periodos_cerrados) <> 0
     or (select active from cron.job where jobid = 3) is distinct from false
     or (select jobname from cron.job where jobid = 3)
          is distinct from 'crm-cierre-mes-diario'
     or private.cierre_mes_pendiente(
          date_trunc('month', now() at time zone 'America/Lima')::date
        ) is distinct from date '2026-08-01' then
    raise exception 'PREFLIGHT: se exige ciclo sin sesión, agosto pendiente y reloj pausado';
  end if;

  -- El ciclo podría avanzar a septiembre después del 10/10. Esta operación
  -- está autorizada solo para agosto: no debe sellar otro mes por accidente.
  if now() >= private.cierre_mes_ventana_desde(date '2026-09-01') then
    raise exception 'PREFLIGHT: la ventana de septiembre ya abrió; revisar ambos meses';
  end if;

  if (select count(*) from crm.cierres_avance_anulados ca
      where ca.lead_id in ('3869c906-594f-4975-ab71-39ca8dc58976',
                           '06bed16f-c45a-4cfd-aa35-a0352887d406')) <> 2
     or exists (
       select 1 from crm.cierres_avance_anulados
       where lead_id in ('069a5535-f426-4678-80f2-be5fa1b6caef',
                         '0ee8dbee-1d8e-4bb4-952b-d9e52dad758f')
     )
     or (select count(*) from crm.ajustes_mes_cerrado) <> 0
     or (select count(*) from crm.inversion_ajustes_mes_cerrado) <> 0
     or (select count(*) from private.respaldo_cierre_agosto_2026) <> 17 then
    raise exception 'PREFLIGHT: faltan las anulaciones de prueba o hay ajustes inesperados';
  end if;

  if (select es_demo from public.contratos
      where id = '615d9724-51bd-4996-bf45-80636e4e7ae6'
        and numero_contrato = '2026-01-000000') is distinct from true then
    raise exception 'PREFLIGHT: el contrato 000000 de octubre sigue marcado como real';
  end if;

  if (select revision from crm.meta_periodos
      where periodo = date '2026-08-01'
      order by revision desc limit 1) is distinct from 15
     or (select count(*)
         from crm.metas_vendedor mv join crm.meta_periodos mp
           on mp.id = mv.meta_periodo_id
         where mp.periodo = date '2026-08-01' and mp.revision = 15) <> 16
     or not exists (
       select 1 from crm.metas_vendedor mv
       join crm.meta_periodos mp on mp.id = mv.meta_periodo_id
       join crm.metas_vendedor_detalle d on d.meta_vendedor_id = mv.id
       where mp.periodo = date '2026-08-01' and mp.revision = 15
         and mv.vendedor_id = 'd731f284-eeaa-4c27-b71f-ac4f1d8e96c2'
         and mv.conversion_objetivo = 15
         and d.categoria = 'nuevo' and d.moneda = 'PEN'
         and d.capital_objetivo = 0
     ) then
    raise exception 'PREFLIGHT: la meta corregida de agosto no es la revisión 15 esperada';
  end if;

  if not exists (
    select 1 from private.conversion_mensual_por_vendedor(
      timestamptz '2026-08-01 05:00:00+00',
      timestamptz '2026-09-01 05:00:00+00',
      true, '{}'::uuid[],
      private.peso_referido_conversion(date '2026-08-01')
    ) c
    where c.analista_id = 'd731f284-eeaa-4c27-b71f-ac4f1d8e96c2'
      and c.divisor = 1
      and c.cierres_no_referidos = 1
      and c.cierres_referidos = 1
      and c.numerador = 1.15
  ) then
    raise exception 'PREFLIGHT: la cifra de las dos conversiones reales cambió';
  end if;
end $pre$;

-- Sin sesión (auth.uid() nulo) el ciclo corre igual que el reloj a las 09:20.
do $sellado$
declare v_resultado jsonb;
begin
  v_resultado := crm.ciclo_cierre_mes();
  if (v_resultado->>'ok')::boolean is distinct from true
     or (v_resultado->>'cerrados')::integer is distinct from 1
     or v_resultado #>> '{detalle,0,periodo}' is distinct from '2026-08'
     or (v_resultado #>> '{detalle,0,meta_revision}')::integer is distinct from 15
     or (v_resultado #>> '{detalle,0,vendedores}')::integer < 16 then
    raise exception 'POSTFLIGHT: el ciclo no produjo solo agosto con la revisión 15: %',
      v_resultado;
  end if;
  raise notice 'Resultado del ciclo: %', v_resultado;
end $sellado$;

select cron.alter_job(job_id := 3, active := true);

do $post$
declare v_filas integer;
begin
  if (select count(*) from crm.periodos_cerrados) <> 1
     or (select meta_revision from crm.periodos_cerrados
         where periodo = date '2026-08-01') is distinct from 15 then
    raise exception 'POSTFLIGHT: agosto no quedó como único mes sellado con revisión 15';
  end if;
  select count(*) into v_filas from crm.cierre_mes_vendedor where periodo = date '2026-08-01';
  if v_filas < 16 then
    raise exception 'POSTFLIGHT: la foto tiene menos de los 16 vendedores con meta';
  end if;
  if not exists (
    select 1 from crm.cierre_mes_vendedor
    where periodo = date '2026-08-01'
      and vendedor_id = 'd731f284-eeaa-4c27-b71f-ac4f1d8e96c2'
      and divisor = 1
      and cierres_no_referidos = 1
      and cierres_referidos = 1
      and numerador = 1.15
      and conversion_pct = 115
      and conversion_objetivo = 15
      and detalles @> '[{"categoria":"nuevo","moneda":"PEN","capital_objetivo":0}]'::jsonb
  ) then
    raise exception 'POSTFLIGHT: la foto no preservó las conversiones reales y su meta de 15 %%';
  end if;
  if (select active from cron.job where jobid = 3) is distinct from true then
    raise exception 'POSTFLIGHT: el ciclo diario sigue en pausa';
  end if;
  raise notice 'AGOSTO 2026 SELLADO DE NUEVO con % vendedores en la foto. Ciclo diario reactivado.', v_filas;
end $post$;
commit;

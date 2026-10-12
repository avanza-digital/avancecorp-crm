-- Corrección puntual de la meta de agosto 2026, antes de volver a sellar.
-- La revisión 14 tiene 16 vendedores. El objetivo de capital de S/ 100 000 de
-- MIGUEL BRICEÑO era una prueba; sus conversiones y meta de conversión del 15 %
-- son reales y se conservan. El roster actual tiene 26, así que el publicador
-- normal reconstruiría una población distinta. Esta revisión append-only copia
-- los 16 vendedores y 96 detalles, cambiando solo ese capital objetivo a cero.
-- Ejecutar solo tras mostrar este SQL y confirmar el alcance de los datos.
begin;
set local lock_timeout = '10s';
select pg_advisory_xact_lock(
  hashtext('crm.meta_periodos'),
  (date '2026-08-01' - date '2000-01-01')::integer
);
-- Mismo orden que el cierre: candado global, candado del mes y equipo.
-- Así la revisión y la foto no se intercalan con otro sellado.
select pg_advisory_xact_lock(hashtext('crm.periodos_cerrados')::bigint);
select pg_advisory_xact_lock(
  hashtext('crm.periodos_cerrados'),
  (date '2026-08-01' - date '2000-01-01')::integer
);
lock table crm.equipo in share mode;

-- Autoría administrativa comprobada: Gerencia activa en producción.
select set_config(
  'request.jwt.claim.sub',
  'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',
  true
);

do $republicar$
declare
  v_anterior uuid;
  v_nuevo uuid;
begin
  if (select count(*) from crm.periodos_cerrados) <> 0
     or (select active from cron.job where jobid = 3) is distinct from false
     or private.rol_crm(auth.uid()) is distinct from 'gerencia' then
    raise exception 'PREFLIGHT: agosto debe seguir abierto, cron pausado y actor ser Gerencia';
  end if;

  select id into v_anterior
  from crm.meta_periodos
  where periodo = date '2026-08-01'
  order by revision desc limit 1;
  if v_anterior is null
     or (select revision from crm.meta_periodos where id = v_anterior) <> 14
     or (select count(*) from crm.metas_vendedor where meta_periodo_id = v_anterior) <> 16
     or (select count(*) from crm.metas_vendedor
         where meta_periodo_id = v_anterior
           and vendedor_id = 'd731f284-eeaa-4c27-b71f-ac4f1d8e96c2') <> 1
     or (select count(*) from crm.metas_vendedor_detalle d
         join crm.metas_vendedor mv on mv.id = d.meta_vendedor_id
         where mv.meta_periodo_id = v_anterior) <> 96 then
    raise exception 'PREFLIGHT: la revisión 14 no coincide con las 16 metas y 96 detalles verificados';
  end if;

  if (select count(*) from crm.metas_vendedor_detalle d
      join crm.metas_vendedor mv on mv.id = d.meta_vendedor_id
      where mv.meta_periodo_id = v_anterior
        and mv.vendedor_id = 'd731f284-eeaa-4c27-b71f-ac4f1d8e96c2'
        and mv.conversion_objetivo = 15
        and d.categoria = 'nuevo' and d.moneda = 'PEN'
        and d.capital_objetivo = 100000 and d.contratos_objetivo = 0) <> 1 then
    raise exception 'PREFLIGHT: la meta de prueba de S/ 100 000 no coincide';
  end if;

  -- La venta de prueba de agosto debe estar anulada por su puerta canónica.
  if not exists (
    select 1 from crm.cierres_avance_anulados
    where lead_id = '3869c906-594f-4975-ab71-39ca8dc58976'
  ) then
    raise exception 'PREFLIGHT: falta anular el cierre de prueba de agosto';
  end if;

  insert into crm.meta_periodos
    (periodo, revision, revision_anterior_id, publicada_por)
  values
    (date '2026-08-01', 15, v_anterior, auth.uid())
  returning id into v_nuevo;

  insert into crm.metas_vendedor
    (meta_periodo_id, vendedor_id, supervisor_id, conversion_objetivo)
  select v_nuevo, vendedor_id, supervisor_id, conversion_objetivo
  from crm.metas_vendedor
  where meta_periodo_id = v_anterior;

  insert into crm.metas_vendedor_detalle
    (meta_vendedor_id, categoria, moneda, capital_objetivo, contratos_objetivo)
  select nuevo.id, d.categoria, d.moneda,
    case when anterior.vendedor_id = 'd731f284-eeaa-4c27-b71f-ac4f1d8e96c2'
          and d.categoria = 'nuevo' and d.moneda = 'PEN'
      then 0::numeric else d.capital_objetivo end,
    d.contratos_objetivo
  from crm.metas_vendedor anterior
  join crm.metas_vendedor_detalle d on d.meta_vendedor_id = anterior.id
  join crm.metas_vendedor nuevo
    on nuevo.meta_periodo_id = v_nuevo
   and nuevo.vendedor_id = anterior.vendedor_id
  where anterior.meta_periodo_id = v_anterior;

  if (select count(*) from crm.metas_vendedor where meta_periodo_id = v_nuevo) <> 16
     or (select count(*) from crm.metas_vendedor_detalle d
         join crm.metas_vendedor mv on mv.id = d.meta_vendedor_id
         where mv.meta_periodo_id = v_nuevo) <> 96
     or exists (
       select vendedor_id, supervisor_id, conversion_objetivo
       from crm.metas_vendedor where meta_periodo_id = v_anterior
       except
       select vendedor_id, supervisor_id, conversion_objetivo
       from crm.metas_vendedor where meta_periodo_id = v_nuevo
     )
     or exists (
       select vendedor_id, supervisor_id, conversion_objetivo
       from crm.metas_vendedor where meta_periodo_id = v_nuevo
       except
       select vendedor_id, supervisor_id, conversion_objetivo
       from crm.metas_vendedor where meta_periodo_id = v_anterior
     )
     or exists (
       select anterior.vendedor_id, d.categoria, d.moneda,
              case when anterior.vendedor_id = 'd731f284-eeaa-4c27-b71f-ac4f1d8e96c2'
                      and d.categoria = 'nuevo' and d.moneda = 'PEN'
                then 0::numeric else d.capital_objetivo end,
              d.contratos_objetivo
       from crm.metas_vendedor anterior
       join crm.metas_vendedor_detalle d on d.meta_vendedor_id = anterior.id
       where anterior.meta_periodo_id = v_anterior
       except
       select nuevo.vendedor_id, d.categoria, d.moneda,
              d.capital_objetivo, d.contratos_objetivo
       from crm.metas_vendedor nuevo
       join crm.metas_vendedor_detalle d on d.meta_vendedor_id = nuevo.id
       where nuevo.meta_periodo_id = v_nuevo
     )
     or exists (
       select nuevo.vendedor_id, d.categoria, d.moneda,
              d.capital_objetivo, d.contratos_objetivo
       from crm.metas_vendedor nuevo
       join crm.metas_vendedor_detalle d on d.meta_vendedor_id = nuevo.id
       where nuevo.meta_periodo_id = v_nuevo
       except
       select anterior.vendedor_id, d.categoria, d.moneda,
              case when anterior.vendedor_id = 'd731f284-eeaa-4c27-b71f-ac4f1d8e96c2'
                      and d.categoria = 'nuevo' and d.moneda = 'PEN'
                then 0::numeric else d.capital_objetivo end,
              d.contratos_objetivo
       from crm.metas_vendedor anterior
       join crm.metas_vendedor_detalle d on d.meta_vendedor_id = anterior.id
       where anterior.meta_periodo_id = v_anterior
     )
     or not exists (
       select 1 from crm.metas_vendedor mv
       join crm.metas_vendedor_detalle d on d.meta_vendedor_id = mv.id
       where mv.meta_periodo_id = v_nuevo
         and mv.vendedor_id = 'd731f284-eeaa-4c27-b71f-ac4f1d8e96c2'
         and mv.conversion_objetivo = 15
         and d.categoria = 'nuevo' and d.moneda = 'PEN'
         and d.capital_objetivo = 0
     ) then
    raise exception 'POSTFLIGHT: la revisión 15 cambió algo más que el capital de prueba';
  end if;
end $republicar$;
commit;

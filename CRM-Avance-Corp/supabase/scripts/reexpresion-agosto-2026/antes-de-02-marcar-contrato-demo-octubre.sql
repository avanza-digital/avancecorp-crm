-- Corrección independiente de octubre: el contrato 2026-01-000000 es demo puro.
-- Se conserva su historia y se excluye de las métricas reales mediante la
-- puerta de Gerencia con motivo y auditoría. No afecta el sello de agosto.
-- Mostrar este SQL exacto y esperar confirmación antes de ejecutarlo.
begin;
set local lock_timeout = '10s';

do $pre$
begin
  if (select count(*) from crm.periodos_cerrados) <> 0
     or (select active from cron.job where jobid = 3) is distinct from false
     or exists (select 1 from crm.periodos_cerrados
                where periodo = date '2026-10-01') then
    raise exception 'PREFLIGHT: cambió el estado de los meses o del ciclo';
  end if;

  if (select count(*) from public.contratos c
      where c.id = '615d9724-51bd-4996-bf45-80636e4e7ae6'
        and c.numero_contrato = '2026-01-000000'
        and c.analista_cierre_id = 'd731f284-eeaa-4c27-b71f-ac4f1d8e96c2'
        and c.fecha_cierre_comercial = date '2026-10-03'
        and c.capital = 5000 and c.moneda = 'PEN'
        and c.estado = 'activo' and c.es_demo = false) <> 1
     or exists (
       select 1 from crm.operaciones_cartera o
       where o.contrato_nuevo_id = '615d9724-51bd-4996-bf45-80636e4e7ae6'
          or o.contrato_origen_id = '615d9724-51bd-4996-bf45-80636e4e7ae6'
     ) then
    raise exception 'PREFLIGHT: el contrato demo no coincide o tiene operaciones';
  end if;

  if (select count(*) from public.contratos
      where analista_cierre_id = 'd731f284-eeaa-4c27-b71f-ac4f1d8e96c2'
        and id <> '615d9724-51bd-4996-bf45-80636e4e7ae6'
        and estado = 'activo' and es_demo = false) <> 8 then
    raise exception 'PREFLIGHT: los otros ocho contratos reales cambiaron';
  end if;

  if (select count(*) from public.cronograma_pagos
      where contrato_id = '615d9724-51bd-4996-bf45-80636e4e7ae6') <> 2
     or (select count(*) from crm.inversiones
         where contrato_id = '615d9724-51bd-4996-bf45-80636e4e7ae6') <> 1
     or exists (select 1 from public.cronograma_pagos
             where contrato_id = '615d9724-51bd-4996-bf45-80636e4e7ae6'
               and (estado <> 'pendiente' or monto_pagado is not null))
     or (select count(*) from private.cartera_f5_fuentes_reales()
         where fuente_id = '615d9724-51bd-4996-bf45-80636e4e7ae6') <> 1 then
    raise exception 'PREFLIGHT: hay pagos o la fuente real no es la esperada';
  end if;
end $pre$;

-- La puerta canónica exige Gerencia activa y deja la razón en audit_log.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',
  true
);
select public.marcar_contrato_demo(
  '615d9724-51bd-4996-bf45-80636e4e7ae6',
  true,
  'Contrato 2026-01-000000 confirmado por Miguel como demo puro el 05/10/2026; excluir de métricas reales'
) as marca_demo;
reset role;

do $post$
begin
  if (select es_demo from public.contratos
      where id = '615d9724-51bd-4996-bf45-80636e4e7ae6') is distinct from true
     or (select count(*) from public.contratos
         where analista_cierre_id = 'd731f284-eeaa-4c27-b71f-ac4f1d8e96c2'
           and id <> '615d9724-51bd-4996-bf45-80636e4e7ae6'
           and estado = 'activo' and es_demo = false) <> 8
     or (select count(*) from crm.inversiones
         where contrato_id = '615d9724-51bd-4996-bf45-80636e4e7ae6') <> 1
     or (select count(*) from public.cronograma_pagos
         where contrato_id = '615d9724-51bd-4996-bf45-80636e4e7ae6') <> 2
     or (select count(*) from private.cartera_f5_fuentes()
         where fuente_id = '615d9724-51bd-4996-bf45-80636e4e7ae6'
           and es_demo = true) <> 1
     or exists (select 1 from private.cartera_f5_fuentes_reales()
                where fuente_id = '615d9724-51bd-4996-bf45-80636e4e7ae6')
     or exists (
       select 1 from private.capital_episodios(
         timestamptz '2026-10-01 05:00:00+00',
         timestamptz '2026-11-01 05:00:00+00',
         true, '{}'::uuid[]
       ) where contrato_id = '615d9724-51bd-4996-bf45-80636e4e7ae6'
     )
     or not exists (
       select 1 from public.audit_log
       where tabla = 'contratos' and operacion = 'demo_marca'
         and fila_id = '615d9724-51bd-4996-bf45-80636e4e7ae6'
         and usuario_id = 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127'
         and data_despues->>'es_demo' = 'true'
     ) then
    raise exception 'POSTFLIGHT: el contrato sigue contando o falta la auditoría';
  end if;
end $post$;
commit;

-- Antes de resellar agosto de 2026: anular las dos conversiones de prueba
-- identificadas por Miguel en la auditoría del 24/09. No modifica contratos,
-- metas, perfiles ni el ciclo diario. Ejecutar solo tras mostrar este SQL.
begin;
set local lock_timeout = '10s';

do $pre$
begin
  if (select count(*) from crm.periodos_cerrados) <> 0
     or (select active from cron.job where jobid = 3) is distinct from false
     or private.cierre_mes_pendiente(
          date_trunc('month', now() at time zone 'America/Lima')::date
        ) is distinct from date '2026-08-01' then
    raise exception 'PREFLIGHT: agosto debe seguir abierto y el ciclo pausado';
  end if;

  if (select count(*) from crm.leads l
      where l.id in ('3869c906-594f-4975-ab71-39ca8dc58976',
                     '06bed16f-c45a-4cfd-aa35-a0352887d406')
        and l.vendedor_id = 'd731f284-eeaa-4c27-b71f-ac4f1d8e96c2'
        and l.etapa = 'convertido'
        and l.convertido_en is not null) <> 2
     or exists (
       select 1 from crm.cierres_avance_anulados ca
       where ca.lead_id in ('3869c906-594f-4975-ab71-39ca8dc58976',
                            '06bed16f-c45a-4cfd-aa35-a0352887d406')
     ) then
    raise exception 'PREFLIGHT: los dos cierres de prueba no tienen el estado esperado';
  end if;

  if exists (
    select 1 from crm.leads l
    where l.id in ('3869c906-594f-4975-ab71-39ca8dc58976',
                   '06bed16f-c45a-4cfd-aa35-a0352887d406')
      and exists (select 1 from private.contratos_afectados_por_anulacion(l.id))
  ) then
    raise exception 'PREFLIGHT: una anulación afectaría contratos; revisar';
  end if;
end $pre$;

-- La puerta canónica exige una sesión de Gerencia y deja autoría en la auditoría.
-- El actor es el perfil de Gerencia superadmin activo verificado en producción.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',
  true
);

select crm.anular_cierre_avance(
  '3869c906-594f-4975-ab71-39ca8dc58976',
  'Venta de prueba de agosto confirmada por Gerencia el 23/09/2026'
) as anulacion_agosto;
select crm.anular_cierre_avance(
  '06bed16f-c45a-4cfd-aa35-a0352887d406',
  'Venta de prueba de septiembre confirmada por Gerencia el 23/09/2026'
) as anulacion_septiembre;

reset role;
do $post$
begin
  if (select count(*) from crm.cierres_avance_anulados ca
      where ca.lead_id in ('3869c906-594f-4975-ab71-39ca8dc58976',
                           '06bed16f-c45a-4cfd-aa35-a0352887d406')
        and ca.anulado_por = 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127') <> 2
     or (select count(*) from crm.ajustes_mes_cerrado) <> 0
     or (select count(*) from crm.periodos_cerrados) <> 0
     or (select active from cron.job where jobid = 3) is distinct from false then
    raise exception 'POSTFLIGHT: anulaciones, ajustes o pausa fuera de lo esperado';
  end if;

  -- Las dos conversiones confirmadas como reales deben quedar intactas.
  if exists (
    select 1 from crm.cierres_avance_anulados
    where lead_id in ('069a5535-f426-4678-80f2-be5fa1b6caef',
                      '0ee8dbee-1d8e-4bb4-952b-d9e52dad758f')
  ) or not exists (
    select 1
    from private.conversion_mensual_por_vendedor(
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
    raise exception 'POSTFLIGHT: las conversiones reales de agosto no quedaron en 1,15';
  end if;
end $post$;
commit;

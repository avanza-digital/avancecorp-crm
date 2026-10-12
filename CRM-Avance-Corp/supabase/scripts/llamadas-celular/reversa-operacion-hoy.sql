-- Reversa de 20261012192500_crm_llamadas_celular_operacion_hoy.sql (decimotercera, F4-e). Retira la puerta
-- crm.llamadas_celular_operacion_hoy_fn y el núcleo private.llamadas_celular_operacion_hoy: la huella del catálogo
-- vuelve exactamente a la de las doce. Sin datos que conservar (la puerta solo lee). La pantalla que la consuma
-- (tercera pestaña de gerencia y «Su celular») debe retirarse antes o tolerar la ausencia de la puerta.
--
-- Orden de las reversas: esta → duodécima (reversa-cierre-revision.sql) → undécima → …
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/scripts/llamadas-celular/reversa-operacion-hoy.sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regprocedure('crm.llamadas_celular_operacion_hoy_fn(uuid)') is null
     and to_regprocedure('private.llamadas_celular_operacion_hoy(uuid,uuid,timestamptz)') is null then
    raise exception 'REVERSA_OPERACION_HOY: la migración 20261012192500 no está aplicada';
  end if;
end;
$precondicion$;

drop function if exists crm.llamadas_celular_operacion_hoy_fn(uuid);
drop function if exists private.llamadas_celular_operacion_hoy(uuid,uuid,timestamptz);

do $postcheck$
begin
  if to_regprocedure('crm.llamadas_celular_operacion_hoy_fn(uuid)') is not null
     or to_regprocedure('private.llamadas_celular_operacion_hoy(uuid,uuid,timestamptz)') is not null then
    raise exception 'REVERSA_OPERACION_HOY: no se volvió al estado de las doce';
  end if;
end;
$postcheck$;

notify pgrst, 'reload schema';
commit;

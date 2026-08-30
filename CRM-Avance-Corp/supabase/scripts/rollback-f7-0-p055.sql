-- MARCHA ATRAS de P-055 F7.0 (el gate que vigila las puertas cerradas).
-- Retira el vigia, el cron y el assert. LA TABLA Y SUS FILAS SE CONSERVAN
-- (doctrina F6.a): el registro historico y las ventanas sobreviven a un
-- rollback y a una re-aplicacion.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and exists (select 1 from cron.job where jobname = 'crm-f7-piezas-vigia') then
    perform cron.unschedule('crm-f7-piezas-vigia');
  end if;
end $$;

drop function if exists private.vigia_f7_piezas();
drop function if exists private.veredicto_f7();
drop function if exists private.assert_f7_piezas_cerradas();

do $$
begin
  if to_regprocedure('private.assert_f7_piezas_cerradas()') is not null
     or to_regprocedure('private.vigia_f7_piezas()') is not null
     or to_regprocedure('private.veredicto_f7()') is not null then
    raise exception 'rollback F7.0: el assert, el veredicto o el vigia siguen vivos';
  end if;
  if exists (select 1 from cron.job where jobname = 'crm-f7-piezas-vigia') then
    raise exception 'rollback F7.0: el cron sigue programado';
  end if;
  if (select count(*) from private.f7_piezas_en_observacion) < 7 then
    raise exception 'rollback F7.0: la tabla debia conservarse con sus filas';
  end if;
  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
end $$;

commit;

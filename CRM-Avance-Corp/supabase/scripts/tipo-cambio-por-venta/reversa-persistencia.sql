-- Solo antes de cargar valoraciones. Tras el primer dato consolidado se
-- conserva la auditoría y se desactiva la presentación, no se borra el ledger.
begin;
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);
do $$ begin
  if to_regclass('crm.capital_cortes_valorados') is not null
    or exists(select 1 from crm.capital_valoracion_politica where activa)
    or exists(select 1 from crm.capital_valoraciones)
    or exists(select 1 from crm.tipo_cambio_diario) then
    raise exception 'Hay activación o valores consolidados: conservar datos y usar reversa de presentación';
  end if;
end $$;
drop function crm.resolver_fecha_tipo_cambio_fn(date,uuid,jsonb,text);
drop function crm.tomar_fechas_tipo_cambio_fn(integer);
drop function crm.reconciliar_capital_valoraciones_fn(integer);
drop function private.materializar_capital_valoraciones(integer);
drop function private.consolidar_tc_venta(jsonb);
drop function private.capital_fuentes_tc();
drop table crm.capital_valoraciones;
drop table crm.tipo_cambio_diario;
drop table crm.tipo_cambio_trabajos;
drop table crm.capital_valoracion_politica;
drop function private.capital_tc_inmutable();
commit;

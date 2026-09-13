\set ON_ERROR_STOP on
begin;
do $$ begin
  if current_database()<>'citas_integracion_20260908' then raise exception 'Sólo banco local'; end if;
end $$;
-- Se habilita el camino completo del gate en ESTE esquema mínimo. Todas las
-- declaraciones siguientes son de dobles locales y desaparecen con ROLLBACK.
create function private.metricas_reuniones_implementacion(date,date) returns bigint language sql stable
security definer set search_path='' as $$ select count(*) from private.citas_episodios($1::timestamptz,$2::timestamptz,now()); $$;
revoke all on function private.metricas_reuniones_implementacion(date,date) from public;
create function private.candado_tope_prueba() returns trigger language plpgsql as $$ begin raise exception 'El ensayo no permite modificar el tope'; end $$;
create trigger trg_analitica_lc_tope_solo_baja before update or delete on private.analitica_leads_citas_tope
for each row execute function private.candado_tope_prueba();
create trigger trg_analitica_lc_tope_no_truncar before truncate on private.analitica_leads_citas_tope
for each statement execute function private.candado_tope_prueba();
insert into private.analitica_leads_citas_exenciones(objeto,tipo,huella,razon)
select p.oid::regprocedure::text,'funcion',md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
  'Doble sintético declarado únicamente en este ensayo local que termina en rollback; no exime ningún lector de producción.'
from pg_proc p where p.oid in ('private.deuda_ajena_prueba()'::regprocedure,'private.metricas_reuniones_implementacion(date,date)'::regprocedure);
update private.analitica_lc_sello set sello=private.huella_exenciones_analitica_lc();
do $$ begin assert private.assert_analitica_leads_citas() like 'OK:%','Precondición: gate local completo válido'; end $$;
create function private.consumidor_cierres_no_declarado_prueba() returns setof uuid language sql stable
security definer set search_path='' as $$
  select lead_id from private.conversion_cierres('2020-01-01',now(),null,true,'{}',1,null);
$$;
revoke all on function private.consumidor_cierres_no_declarado_prueba() from public;
do $$ begin
  begin
    perform private.assert_analitica_leads_citas();
    raise exception 'Aceptó el consumidor sin declaración';
  exception when raise_exception then
    assert sqlerrm like 'Hay un consumidor de citas_episodios o conversion_cierres SIN declarar:%','No fue el rechazo esperado';
  end;
end $$;
select 'CITAS_CONSUMIDOR_NO_DECLARADO_RECHAZADO' as resultado;
rollback;

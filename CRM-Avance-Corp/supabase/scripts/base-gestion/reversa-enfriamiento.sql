-- Reversa de 20261002233851_crm_base_gestion_enfriamiento.sql (Base para gestión · B4). Quita el trigger y su función.
-- No toca datos: los enfriado_hasta ya fijados quedan (se limpian al reactivar o por Gerencia cuando exista su puerta).
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
set local search_path = '';
drop trigger if exists trg_zz_actividades_enfriamiento_base on crm.actividades;
drop function if exists private.trg_actividades_enfriamiento_base();
do $post$
begin
  if to_regprocedure('private.trg_actividades_enfriamiento_base()') is not null then raise exception 'REVERSA B4: quedo la funcion'; end if;
  raise notice 'reversa base_gestion_enfriamiento OK · descansos vigentes que quedan: % (hasta %)',
    (select count(*) from crm.leads where enfriado_hasta > (now() at time zone 'America/Lima')::date),
    (select coalesce(max(enfriado_hasta)::text, '-') from crm.leads where enfriado_hasta > (now() at time zone 'America/Lima')::date);
end;
$post$;
notify pgrst, 'reload schema';
commit;

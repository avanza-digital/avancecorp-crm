-- Reversa de 20261002231436_crm_base_gestion_puertas.sql (Base para gestión · B3). Quita puertas, núcleos y ayudantes.
-- No toca datos: los intentos (evento intento_base) y reactivaciones ya registrados quedan en el historial.
-- Aplicar ANTES que la reversa de B4 no es necesario; sí ANTES que las de B1b/B1 (dependen de las columnas).
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
set local search_path = '';
do $pre$
begin
  if exists (select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid where p.prosrc ~ 'base_gestion_intento_core|base_gestion_reactivar_core') then
    raise exception 'REVERSA B3: hay triggers (B4) que dependen de los nucleos; revertirlos antes';
  end if;
end;
$pre$;
drop trigger if exists trg_00_actividades_base_gestion_solo_nucleo on crm.actividades;
drop function if exists private.trg_actividades_base_gestion_solo_nucleo();
drop function if exists crm.registrar_intento_base(uuid, uuid, text, text, timestamptz);
drop function if exists crm.reactivar_lead_base(uuid, uuid, text);
drop function if exists crm.obtener_base_gestion(uuid);
drop function if exists crm.base_gestion_resumen();
drop function if exists private.base_gestion_intento_core(uuid, uuid, uuid, text, text, timestamptz);
drop function if exists private.base_gestion_reactivar_core(uuid, uuid, uuid, text);
drop function if exists private.base_gestion_lead_visible(uuid, text, uuid, uuid);
drop function if exists private.base_gestion_rol(uuid);
drop function if exists private.base_gestion_etapa_rango(text);
do $post$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('crm','private') and (p.proname like 'base_gestion_%' or p.proname = 'trg_actividades_base_gestion_solo_nucleo') and p.proname <> 'base_gestion_constantes')
     or to_regprocedure('crm.obtener_base_gestion(uuid)') is not null then
    raise exception 'REVERSA B3: quedo alguna funcion';
  end if;
  raise notice 'reversa base_gestion_puertas OK';
end;
$post$;
notify pgrst, 'reload schema';
commit;

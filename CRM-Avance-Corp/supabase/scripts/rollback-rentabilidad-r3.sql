-- ============================================================================
-- REVERSA de RENTABILIDAD R3 (20260906220000): suelta las 3 lecturas (solo si llevan un cuerpo conocido: v1/v2 con la firma de 2 argumentos, v3 con la de 4) y desregistra la
-- versión. No toca tablas ni datos; el front que las llame recibirá PGRST202 hasta que vuelvan. Repetible.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_rentabilidad_r3'));
do $pre$
begin
  if exists (select 1 from pg_proc p where p.oid = to_regprocedure('crm.solicitudes_tasa_fn(text[],integer)') and md5(p.prosrc) not in ('0ec8c3a31c3b354a179d1c54ae5239ac', '77fdd56a40dd0135a574575f01de494d'))
     or exists (select 1 from pg_proc p where p.oid = to_regprocedure('crm.solicitudes_tasa_fn(text[],integer,boolean,uuid)') and md5(p.prosrc) not in ('c8db407429a4112b479ae87c12020ef4', 'abe12a0064a333d9410b7269d006d65c'))
     or exists (select 1 from pg_proc p where p.oid = to_regprocedure('crm.historial_tasa_cliente_fn(uuid)') and md5(p.prosrc) not in ('3de51d208cae2317200ca7e60dab6387', '5fc2c0e8b9703601ac120d4820d18613', '7534122b48f03b50eb64e6eef0a8e961', '4c65bdb35dc595c01cb32ece505cbb59'))
     or exists (select 1 from pg_proc p where p.oid = to_regprocedure('crm.politica_rentabilidad_fn()') and md5(p.prosrc) not in ('8a4aca684332ef3f8c6014ed59d07c5f')) then
    raise exception 'REVERSA R3: alguna lectura no lleva un cuerpo conocido de R3; hay una versión posterior';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20260906220000'
             and (name <> 'crm_rentabilidad_r3_lecturas_bandeja_ficha_politica' or md5(statements[1]) not in ('c913928bce43c6e343bb79f19d0f31b1', '7fa52bb6a309a5970b7960e194cdcca0', 'ae76461e20553ca5ad2189b39e71859c', '282e5fcda30e0eb5b252072ad09993db', '44f002a4f09bab579aefe243da72f6e4'))) then
    raise exception 'REVERSA R3: la versión 20260906220000 registrada no es un contenido conocido de R3';
  end if;
end
$pre$;
drop function if exists crm.solicitudes_tasa_fn(text[], integer);
drop function if exists crm.solicitudes_tasa_fn(text[], integer, boolean, uuid);
drop function if exists crm.historial_tasa_cliente_fn(uuid);
drop function if exists crm.politica_rentabilidad_fn();
do $post$
begin
  if to_regprocedure('crm.solicitudes_tasa_fn(text[],integer)') is not null or to_regprocedure('crm.solicitudes_tasa_fn(text[],integer,boolean,uuid)') is not null
     or to_regprocedure('crm.historial_tasa_cliente_fn(uuid)') is not null
     or to_regprocedure('crm.politica_rentabilidad_fn()') is not null then
    raise exception 'REVERSA R3: quedó algún objeto vivo';
  end if;
  delete from supabase_migrations.schema_migrations where version = '20260906220000';
  raise notice 'REVERSA RENTABILIDAD R3 OK (versión 20260906220000 desregistrada si estaba)';
end
$post$;
commit;

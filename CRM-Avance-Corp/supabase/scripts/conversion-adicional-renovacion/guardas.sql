-- Ensaya el bloque preflight literal de la migración contra deriva y cierres.
-- Únicamente branch propia; las alteraciones de prueba se revierten.
\set ON_ERROR_STOP on
begin;
set local session_replication_role=replica;
create temp table nueva as select pg_get_functiondef('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure) sql;
create temp table resultados(caso text);
create function pg_temp.guarda(esperado text,caso text) returns void language plpgsql as $test$
declare obtenido text;
begin
  begin
    execute $guardado$do $preflight$
begin
  if exists (
    select 1 from crm.periodos_cerrados where periodo >= date '2026-10-01'
  ) then
    raise exception 'ADICIONAL RENOVACION: octubre o posterior ya está cerrado'
      using errcode = 'P0409';
  end if;
  if not exists (
    select 1 from crm.conversion_pesos
    where vigente_desde = date '2026-10-01'
      and peso_renovacion = 0 and peso_referido = 1 and tope_referidos_pct = 15
  ) or exists (
    select 1 from crm.conversion_pesos
    where vigente_desde > date '2026-10-01'
  ) then
    raise exception 'ADICIONAL RENOVACION: pesos distintos de los revisados'
      using errcode = 'P0409';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = pg_catalog.to_regprocedure(
      'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)')
      and pg_catalog.md5(p.prosrc) = 'ed15fbd034c636e4897c7600002ee8cf'
      and p.proowner = 'postgres'::regrole
      and p.proacl::text = '{postgres=X/postgres}'
      and p.prosecdef and p.provolatile = 's'
      and p.proconfig = array['search_path=""']
  ) then
    raise exception 'ADICIONAL RENOVACION: núcleo o permisos distintos de los revisados'
      using errcode = 'P0409';
  end if;
end;
$preflight$;$guardado$;
  exception when sqlstate 'P0409' then obtenido:=sqlerrm;
  end;
  if obtenido is distinct from esperado then
    raise exception 'Guarda %: esperado %, obtenido %',caso,esperado,obtenido;
  end if;
  insert into resultados values(caso);
end $test$;
select pg_temp.guarda('ADICIONAL RENOVACION: núcleo o permisos distintos de los revisados','01: rechaza reaplicar sobre el núcleo ya modificado');
\ir nucleo-anterior.sql
select pg_temp.guarda(null,'02: acepta exactamente la base revisada');
insert into crm.periodos_cerrados(periodo,automatico,ponderacion_referido,ponderacion_renovacion,tope_referidos_pct,meta_revision,cobertura)
values('2026-10-01',true,1,0,15,0,'{}');
select pg_temp.guarda('ADICIONAL RENOVACION: octubre o posterior ya está cerrado','03: rechaza si octubre ya está congelado');
delete from crm.periodos_cerrados where periodo='2026-10-01';
update crm.conversion_pesos set peso_referido=0.5 where vigente_desde='2026-10-01';
select pg_temp.guarda('ADICIONAL RENOVACION: pesos distintos de los revisados','04: rechaza deriva de pesos');
update crm.conversion_pesos set peso_referido=1 where vigente_desde='2026-10-01';
grant execute on function private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric) to authenticated;
select pg_temp.guarda('ADICIONAL RENOVACION: núcleo o permisos distintos de los revisados','05: rechaza deriva de permisos');
revoke execute on function private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric) from authenticated;
select pg_temp.guarda(null,'06: la base vuelve a coincidir después de revertir las mutaciones de prueba');
do $$ begin execute(select sql from nueva); end $$;
select jsonb_build_object('estado','PASS','comprobaciones',count(*)) from resultados;
rollback;

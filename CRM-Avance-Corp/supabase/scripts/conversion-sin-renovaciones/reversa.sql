-- Reversa de 20261012184345. Solo mientras octubre y los siguientes siguen abiertos.
-- Ejecutar por el mismo circuito de rama/merge. No elimina operaciones ni fotos.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
set local search_path='';
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);
lock table crm.conversion_pesos in access exclusive mode;
lock table crm.periodos_cerrados in share row exclusive mode;
do $$
declare
  v_nota text := E'\nMiguel 2026-10-12: desde octubre de 2026 las renovaciones aportan 0 a la conversión de analistas. Sustituye la mención anterior de renovación 0,15. Se conservan los meses anteriores, los registros e importes de cartera, el peso y tope del referido y la primera operación elegible por cliente/mes.';
begin
  if not exists (
    select 1 from pg_catalog.pg_attribute a join pg_catalog.pg_attrdef d
      on d.adrelid=a.attrelid and d.adnum=a.attnum
    where a.attrelid='crm.conversion_pesos'::regclass and a.attname='peso_renovacion'
      and a.attnotnull and pg_catalog.pg_get_expr(d.adbin,d.adrelid)='0'
  ) then
    raise exception 'REVERSA SIN RENOVACIONES: cambió el default o la nulabilidad del peso'
      using errcode='P0409';
  end if;
  if exists(select 1 from crm.periodos_cerrados where periodo>=date '2026-10-01')
     or (select count(*) from crm.conversion_pesos)<>2
     or not exists(select 1 from crm.conversion_pesos where vigente_desde='2026-10-01'
       and peso_renovacion=0 and peso_referido=1 and tope_referidos_pct=15
       and right(nota,length(v_nota))=v_nota)
     or not exists(select 1 from pg_constraint where conrelid='crm.conversion_pesos'::regclass
       and conname='conversion_renovacion_cero_desde_octubre') then
    raise exception 'REVERSA SIN RENOVACIONES: hay un mes sellado o cambió la configuración; no se revierte'
      using errcode='P0409';
  end if;
  alter table crm.conversion_pesos drop constraint conversion_renovacion_cero_desde_octubre;
  update crm.conversion_pesos set peso_renovacion=0.15,
    nota=left(nota,length(nota)-length(v_nota)) where vigente_desde='2026-10-01';
  alter table crm.conversion_pesos alter column peso_renovacion set default 0.15;
end $$;
commit;

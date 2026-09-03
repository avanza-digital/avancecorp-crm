-- Reversa de 20260903160000_crm_f1_identidad_empresas_inversiones.sql
-- F1 es ADITIVO y APAGADO: revertir no toca ningun dato vivo (los enlaces
-- inversionista_id estan vacios en F1; si F2 ya hizo backfill, NO usar esto tal
-- cual: primero revertir F2). Aborta si detecta datos en los enlaces.
begin;
select pg_advisory_xact_lock(hashtext('crm_f1_multiempresa'));

do $g$
begin
  if to_regclass('crm.leads') is not null
     and exists (select 1 from information_schema.columns
                 where table_schema='crm' and table_name='leads' and column_name='inversionista_id')
     and (select count(*) from crm.leads where inversionista_id is not null) > 0 then
    raise exception 'REVERSA F1: crm.leads tiene enlaces poblados — hay backfill (F2). Revertir F2 primero.';
  end if;
  if to_regclass('crm.cierres_externos') is not null
     and exists (select 1 from information_schema.columns
                 where table_schema='crm' and table_name='cierres_externos' and column_name='inversionista_id')
     and (select count(*) from crm.cierres_externos where inversionista_id is not null) > 0 then
    raise exception 'REVERSA F1: crm.cierres_externos tiene enlaces poblados — revertir F2 primero.';
  end if;
end
$g$;

drop function if exists private.inversionista_resolver(text,text,boolean,text);

-- Enlaces nullable (arrastran sus indices y FKs).
alter table if exists crm.leads            drop column if exists inversionista_id;
alter table if exists crm.cierres_externos drop column if exists inversionista_id;

-- Tablas nuevas, hijas antes que padres (cascade como respaldo).
drop table if exists crm.inversion_titulares          cascade;
drop table if exists crm.inversiones                  cascade;
drop table if exists crm.inversionista_fusiones       cascade;
drop table if exists crm.inversionista_responsables   cascade;
drop table if exists crm.inversionista_leads          cascade;
drop table if exists crm.inversionista_identificadores cascade;
drop table if exists crm.inversionistas               cascade;
drop table if exists crm.empresas                     cascade;
drop table if exists crm.multiempresa_idempotencia    cascade;
drop table if exists crm.multiempresa_flags           cascade;

do $post$
declare
  t text; v_queda text;
  v_tablas text[] := array[
    'empresas','inversionistas','inversionista_identificadores','inversionista_leads',
    'inversionista_responsables','inversionista_fusiones','inversiones','inversion_titulares',
    'multiempresa_idempotencia','multiempresa_flags'];
begin
  -- Las 10 tablas se fueron.
  select string_agg(t2,', ') into v_queda
    from (select unnest(v_tablas) t2) s where to_regclass('crm.'||t2) is not null;
  if v_queda is not null then raise exception 'REVERSA F1: quedaron tablas sin eliminar: %', v_queda; end if;
  -- La funcion se fue.
  if to_regprocedure('private.inversionista_resolver(text,text,boolean,text)') is not null then
    raise exception 'REVERSA F1: quedo private.inversionista_resolver';
  end if;
  -- Los enlaces nullable se soltaron de las tablas vivas.
  if exists (select 1 from information_schema.columns where table_schema='crm' and table_name='leads' and column_name='inversionista_id')
     or exists (select 1 from information_schema.columns where table_schema='crm' and table_name='cierres_externos' and column_name='inversionista_id') then
    raise exception 'REVERSA F1: quedo alguna columna inversionista_id sin soltar';
  end if;
  raise notice 'REVERSA F1 OK: 10 tablas, funcion y enlaces retirados; nada vivo tocado.';
end
$post$;
commit;

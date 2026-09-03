-- Reversa de 20260903160000_crm_f1_identidad_empresas_inversiones.sql
-- F1 es ADITIVO y APAGADO: revertir no toca ningun dato vivo (los enlaces
-- inversionista_id estan vacios en F1; si F2 ya hizo backfill, NO usar esto tal
-- cual: primero revertir F2). Aborta si detecta datos en los enlaces.
begin;
select pg_advisory_xact_lock(hashtext('crm_f1_multiempresa'));
-- #8 (Codex): tomar ACCESS EXCLUSIVE ANTES de contar, para que ningun escritor
-- vivo pueble el enlace entre el conteo y el drop (el advisory lock no frena a
-- quien no coopere; el ALTER tomaria este lock igual, aqui se adelanta).
lock table crm.leads, crm.cierres_externos in access exclusive mode;

do $g$
declare v_con text;
begin
  -- Enlaces vivos poblados => hay backfill (F2): no revertir F1 a ciegas.
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
  -- #11 (Codex): la reversa solo deshace un F1 PRISTINO. Si cualquier tabla
  -- nueva tiene datos (mas alla de las 3 empresas y 3 flags semilla), el CASCADE
  -- borraria trabajo real (F2+). Abortar y exigir revertir la fase que escribio.
  select string_agg(t, ', ') into v_con from (
    select 'inversionistas' t where to_regclass('crm.inversionistas') is not null and exists (select 1 from crm.inversionistas)
    union all select 'inversionista_identificadores' where to_regclass('crm.inversionista_identificadores') is not null and exists (select 1 from crm.inversionista_identificadores)
    union all select 'inversionista_leads' where to_regclass('crm.inversionista_leads') is not null and exists (select 1 from crm.inversionista_leads)
    union all select 'inversionista_responsables' where to_regclass('crm.inversionista_responsables') is not null and exists (select 1 from crm.inversionista_responsables)
    union all select 'inversionista_fusiones' where to_regclass('crm.inversionista_fusiones') is not null and exists (select 1 from crm.inversionista_fusiones)
    union all select 'inversiones' where to_regclass('crm.inversiones') is not null and exists (select 1 from crm.inversiones)
    union all select 'inversion_titulares' where to_regclass('crm.inversion_titulares') is not null and exists (select 1 from crm.inversion_titulares)
    union all select 'multiempresa_idempotencia' where to_regclass('crm.multiempresa_idempotencia') is not null and exists (select 1 from crm.multiempresa_idempotencia)
    union all select 'empresas(>3)' where to_regclass('crm.empresas') is not null and (select count(*) from crm.empresas) > 3
    union all select 'multiempresa_flags(alterada)' where to_regclass('crm.multiempresa_flags') is not null and ((select count(*) from crm.multiempresa_flags) > 3 or exists (select 1 from crm.multiempresa_flags where activo))
  ) s;
  if v_con is not null then
    raise exception 'REVERSA F1: hay datos en tablas nuevas (%) — revertir la fase que escribio antes de bajar F1', v_con;
  end if;
end
$g$;

-- Proteccion de la columna en leads: el trigger vive sobre una tabla que NO se
-- borra, asi que se baja explicitamente antes de soltar la columna.
drop trigger if exists trg_leads_protege_inversionista_id on crm.leads;
drop function if exists private.leads_protege_inversionista_id();
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

-- Funciones de coherencia: sus triggers cayeron con las tablas de arriba.
drop function if exists private.inversiones_empresa_coherente();
drop function if exists private.inversion_titular_coherente();
drop function if exists private.inversionista_fusion_destino_activo();
drop function if exists private.inversionista_fusiones_append_only();

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
  -- Las funciones nuevas se fueron.
  if to_regprocedure('private.inversionista_resolver(text,text,boolean,text)') is not null
     or to_regprocedure('private.leads_protege_inversionista_id()') is not null
     or to_regprocedure('private.inversiones_empresa_coherente()') is not null
     or to_regprocedure('private.inversion_titular_coherente()') is not null
     or to_regprocedure('private.inversionista_fusion_destino_activo()') is not null
     or to_regprocedure('private.inversionista_fusiones_append_only()') is not null then
    raise exception 'REVERSA F1: quedo alguna funcion nueva sin eliminar';
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

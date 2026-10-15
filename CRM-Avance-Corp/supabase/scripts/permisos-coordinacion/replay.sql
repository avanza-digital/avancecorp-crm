\set ON_ERROR_STOP on
-- Solo el banco sintético vacío: no es un rollback de producción.
do $$ begin
  if current_database() not like 'permisos_coordinacion_%'
    or exists(select 1 from public.contratos)
    or exists(select 1 from crm.correcciones_categoria_contrato) then
    raise exception 'Replay requiere el banco aislado vacío';
  end if;
end; $$;
create temporary table funciones_antes as
select p.oid::regprocedure::text as firma,pg_get_functiondef(p.oid) as definicion
from pg_proc p where p.pronamespace in ('private'::regnamespace,'crm'::regnamespace) and p.prokind='f';
\ir reversa-categoria.sql
\ir reversa-consulta.sql
\ir ../../migrations/20261015211217_crm_coordinacion_consulta_cartera_leads.sql
\ir ../../migrations/20261015212939_crm_correccion_manual_categoria_inversion.sql
do $$ begin
  if exists(select firma,definicion from funciones_antes except
    select p.oid::regprocedure::text,pg_get_functiondef(p.oid) from pg_proc p
    where p.pronamespace in ('private'::regnamespace,'crm'::regnamespace) and p.prokind='f') then
    raise exception 'El replay cambió una definición';
  end if;
end; $$;
select 'PASS: reversa y reaplicación conservan todas las definiciones';
\ir prueba.sql

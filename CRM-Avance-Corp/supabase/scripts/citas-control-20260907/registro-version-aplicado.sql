-- Reconciliación administrativa ejecutada después del apply_migration exitoso.
-- Conserva nombre y SQL; solo alinea la versión asignada por MCP con el archivo.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
lock table supabase_migrations.schema_migrations in share row exclusive mode;
do $registro$
declare v_n integer;
begin
 if exists(select 1 from supabase_migrations.schema_migrations where version='20260908020020') then
  raise exception 'Ya existe la version canonica; revisar el registro';
 end if;
 if (select count(*) from supabase_migrations.schema_migrations where name='crm_citas_repara_huella_control')<>1 then
  raise exception 'La migracion no es unica; revisar el registro';
 end if;
 update supabase_migrations.schema_migrations
 set version='20260908020020'
 where version='20260908020347'
   and name='crm_citas_repara_huella_control'
   and cardinality(statements)=1
   and md5(statements[1])='ad64689063e6cdc559ce6cf62d5511d5';
 get diagnostics v_n=row_count;
 if v_n<>1 then raise exception 'El SQL registrado difiere del artefacto publicado'; end if;
end;
$registro$;
select version,name,md5(statements[1]) as sql_md5,cardinality(statements) as cantidad_sentencias
from supabase_migrations.schema_migrations
where name='crm_citas_repara_huella_control';
commit;

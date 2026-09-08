-- Identidad canónica del SQL de avisos YA aplicado mediante MCP.
-- DML de publicación; no vuelve a ejecutar la migración ni cambia datos del CRM.
-- Fuente: commit 1e580d77f95efb014199ad3e7acbd45e0b514a76.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
set local search_path='';
lock table supabase_migrations.schema_migrations in share row exclusive mode;
do $reconciliar$
declare v_n integer; v_antes jsonb; v_despues jsonb;
begin
  if exists(select 1 from pg_catalog.pg_trigger
    where tgrelid='supabase_migrations.schema_migrations'::regclass
      and not tgisinternal and tgenabled<>'D')
    or exists(select 1 from pg_catalog.pg_constraint
      where confrelid='supabase_migrations.schema_migrations'::regclass) then
    raise exception 'El ledger adquirió triggers o referencias; revisar';
  end if;
  select count(*) into v_n from supabase_migrations.schema_migrations
    where name='crm_sla_avisos_por_accion_y_rol';
  if v_n<>1 then raise exception 'Nombre ausente o duplicado'; end if;
  if not exists(select 1 from supabase_migrations.schema_migrations s
    where s.name='crm_sla_avisos_por_accion_y_rol' and s.version='20260908002639'
      and cardinality(s.statements)=1 and array_ndims(s.statements)=1
      and array_lower(s.statements,1)=1
      and pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(s.statements[1],'UTF8')),'hex')
        ='30e60b0e1a3af9944ab2c20715c010a7cd97351c7ea0af6d569406ed60897bed') then
    raise exception 'La identidad o el SQL no coincide con el artefacto publicado';
  end if;
  if exists(select 1 from supabase_migrations.schema_migrations
    where version='20260907212612') then
    raise exception 'Versión canónica ocupada';
  end if;
  select to_jsonb(s)-'version' into strict v_antes
    from supabase_migrations.schema_migrations s where s.version='20260908002639';
  update supabase_migrations.schema_migrations
    set version='20260907212612'
    where name='crm_sla_avisos_por_accion_y_rol' and version='20260908002639';
  get diagnostics v_n=row_count;
  if v_n<>1 then raise exception 'Se esperaba actualizar una sola versión'; end if;
  select to_jsonb(s)-'version' into strict v_despues
    from supabase_migrations.schema_migrations s where s.version='20260907212612';
  if v_antes is distinct from v_despues then
    raise exception 'Se alteró otro campo del ledger; reversión obligatoria';
  end if;
  if exists(select 1 from supabase_migrations.schema_migrations
    where version='20260908002639') then
    raise exception 'La versión operativa aún existe';
  end if;
end;
$reconciliar$;
select 'OK: versión canónica 20260907212612; SQL y demás campos intactos' as veredicto;
commit;

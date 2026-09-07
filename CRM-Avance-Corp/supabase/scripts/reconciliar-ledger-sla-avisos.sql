-- Identidad canónica del SQL de avisos YA aplicado mediante MCP.
-- DML de publicación; no vuelve a ejecutar la migración ni cambia datos del CRM.
-- Fuente: commit 8bb960672fb2a6d14e728e96b8ff611e30f3d9cb.
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
    where name='crm_sla_avisos_contextuales';
  if v_n<>1 then raise exception 'Nombre ausente o duplicado'; end if;
  if not exists(select 1 from supabase_migrations.schema_migrations s
    where s.name='crm_sla_avisos_contextuales' and s.version='20260907165929'
      and cardinality(s.statements)=1 and array_ndims(s.statements)=1
      and array_lower(s.statements,1)=1
      and pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(s.statements[1],'UTF8')),'hex')
        ='6da2960e0d7c80a0bb562f1b7c8e491efe5f69bf140d57e212e45a512bc768bd') then
    raise exception 'La identidad o el SQL no coincide con el artefacto publicado';
  end if;
  if exists(select 1 from supabase_migrations.schema_migrations
    where version='20260907155813') then
    raise exception 'Versión canónica ocupada';
  end if;
  select to_jsonb(s)-'version' into strict v_antes
    from supabase_migrations.schema_migrations s where s.version='20260907165929';
  update supabase_migrations.schema_migrations
    set version='20260907155813'
    where name='crm_sla_avisos_contextuales' and version='20260907165929';
  get diagnostics v_n=row_count;
  if v_n<>1 then raise exception 'Se esperaba actualizar una sola versión'; end if;
  select to_jsonb(s)-'version' into strict v_despues
    from supabase_migrations.schema_migrations s where s.version='20260907155813';
  if v_antes is distinct from v_despues then
    raise exception 'Se alteró otro campo del ledger; reversión obligatoria';
  end if;
  if exists(select 1 from supabase_migrations.schema_migrations
    where version='20260907165929') then
    raise exception 'La versión operativa aún existe';
  end if;
end;
$reconciliar$;
select 'OK: versión canónica 20260907155813; SQL y demás campos intactos' as veredicto;
commit;

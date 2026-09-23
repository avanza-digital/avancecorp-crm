-- PROPUESTA: requiere autorización administrativa. No reinstala etapa 3.
-- Las 33 sentencias se cotejaron íntegramente con el archivo 20260921214018.
-- Respaldo privado: gd-f4-ledger-etapa3-respaldo-20260922.json.
-- Cambia exclusivamente la versión que Supabase asignó al fusionar la rama.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
lock table supabase_migrations.schema_migrations in share row exclusive mode;
create temporary table _gd_ledger_antes on commit drop as
select to_jsonb(m) as fila from supabase_migrations.schema_migrations m
where version='20260922164159' and name='crm_gestion_diaria_cortes';
do $registro$
declare v_n integer;
begin
  perform private.assert_gestion_diaria();
  if exists(select 1 from supabase_migrations.schema_migrations where version='20260921214018') then
    raise exception 'Ya existe la version canonica; no reaplicar';
  end if;
  if (select count(*) from supabase_migrations.schema_migrations where name='crm_gestion_diaria_cortes')<>1 then
    raise exception 'Etapa 3 no es unica en el historial';
  end if;
  update supabase_migrations.schema_migrations set version='20260921214018'
  where version='20260922164159' and name='crm_gestion_diaria_cortes'
    and cardinality(statements)=33
    and md5(array_to_string(statements,E'\n'))='d3d9cf9cde700b0fc44095fcbd523892';
  get diagnostics v_n=row_count;
  if v_n<>1 then raise exception 'El historial difiere del respaldo cotejado'; end if;
  if (select to_jsonb(m)-'version' from supabase_migrations.schema_migrations m where version='20260921214018')
    is distinct from (select fila-'version' from _gd_ledger_antes) then
    raise exception 'Cambio inesperado fuera de la version';
  end if;
  perform private.assert_gestion_diaria();
end;
$registro$;
commit;

-- Reconciliación de identidad del artefacto YA aplicado mediante MCP.
-- Ejecutar una vez como DML (execute_sql), NO mediante apply_migration.
-- Sólo se actualiza version de cinco filas; no vuelve a ejecutar ningún SQL SLA.
-- Revisión contra commit 839aa7c8c01cecba3102fb3222408784a1e4b972.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
set local search_path='';
-- Serializa las comprobaciones con cualquier otro escritor del ledger.
lock table supabase_migrations.schema_migrations in share row exclusive mode;
do $reconciliar$
declare
  v_mapa constant jsonb := '[{"nombre":"crm_sla_prerrequisito_gobernanza","operativa":"20260907035818","canonica":"20260907032338","sql_sha256":"cebf5605304f09d5ae6aa5c62618c006d747844abaf4703e187eb18cdf856189"},{"nombre":"crm_sla_nucleo_operativo_lectura","operativa":"20260907035837","canonica":"20260907001024","sql_sha256":"1db637e615b4c054acdd0395ce2aea6e586ae78d44f84698ca1f16f2d361e98d"},{"nombre":"crm_sla_nucleo_operativo_escritura","operativa":"20260907035851","canonica":"20260907024903","sql_sha256":"650730b6e44ef4e6a1bfcb0073f637043f3ee7d82ee680968b18f1e29f2d2cbd"},{"nombre":"crm_sla_comandos_recibos","operativa":"20260907035906","canonica":"20260907025220","sql_sha256":"1476b01e1c916cb88ddc9bf3d0e555ea292219060731c7f996f0633060dc1f2e"},{"nombre":"crm_sla_cierre_reconstruccion_contextos","operativa":"20260907040053","canonica":"20260907031450","sql_sha256":"5a200ee70895015ea7aa7db06cedbe044afb47b466e52d145f24d25083b5ceb4"}]'::jsonb;
  v_fila record;
  v_n integer;
  v_antes jsonb;
  v_despues jsonb;
begin
  if jsonb_array_length(v_mapa)<>5
    or (select count(distinct r.nombre) from jsonb_to_recordset(v_mapa) r(nombre text))<>5
    or (select count(distinct r.operativa) from jsonb_to_recordset(v_mapa) r(operativa text))<>5
    or (select count(distinct r.canonica) from jsonb_to_recordset(v_mapa) r(canonica text))<>5 then
    raise exception 'Mapa SLA no es exactamente cinco identidades únicas';
  end if;
  -- No admitir efectos laterales nuevos que no existían en la revisión.
  if exists(select 1 from pg_catalog.pg_trigger where tgrelid='supabase_migrations.schema_migrations'::regclass
       and not tgisinternal and tgenabled<>'D')
    or exists(select 1 from pg_catalog.pg_constraint where confrelid='supabase_migrations.schema_migrations'::regclass) then
    raise exception 'El ledger adquirió triggers o referencias; revisar antes de reconciliar';
  end if;
  for v_fila in select * from jsonb_to_recordset(v_mapa)
    r(nombre text,operativa text,canonica text,sql_sha256 text)
  loop
    select count(*) into v_n from supabase_migrations.schema_migrations s where s.name=v_fila.nombre;
    if v_n<>1 then raise exception 'Nombre SLA ausente o duplicado: %',v_fila.nombre;end if;
    if not exists(select 1 from supabase_migrations.schema_migrations s
      where s.name=v_fila.nombre and s.version=v_fila.operativa
        and cardinality(s.statements)=1 and array_ndims(s.statements)=1 and array_lower(s.statements,1)=1
        and pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(s.statements[1],'UTF8')),'hex')=v_fila.sql_sha256) then
      raise exception 'Versión, cardinalidad o SHA256 distintos del artefacto comprometido: %',v_fila.nombre;
    end if;
    if exists(select 1 from supabase_migrations.schema_migrations where version=v_fila.canonica) then
      raise exception 'La versión canónica ya existe: %',v_fila.canonica;
    end if;
  end loop;
  select jsonb_object_agg(s.name,to_jsonb(s)-'version') into v_antes
  from supabase_migrations.schema_migrations s
  join jsonb_to_recordset(v_mapa) r(nombre text) on r.nombre=s.name;

  update supabase_migrations.schema_migrations s set version=r.canonica
  from jsonb_to_recordset(v_mapa) r(nombre text,operativa text,canonica text)
  where s.name=r.nombre and s.version=r.operativa;
  get diagnostics v_n=row_count;
  if v_n<>5 then raise exception 'Se esperaba actualizar cinco versiones; fueron %',v_n;end if;

  select jsonb_object_agg(s.name,to_jsonb(s)-'version') into v_despues
  from supabase_migrations.schema_migrations s
  join jsonb_to_recordset(v_mapa) r(nombre text) on r.nombre=s.name;
  if v_antes is distinct from v_despues then
    raise exception 'Se alteró un campo diferente de version; se revierte la reconciliación';
  end if;
  if exists(select 1 from jsonb_to_recordset(v_mapa) r(nombre text,operativa text,canonica text)
    where not exists(select 1 from supabase_migrations.schema_migrations s where s.name=r.nombre and s.version=r.canonica)
      or exists(select 1 from supabase_migrations.schema_migrations s where s.version=r.operativa)) then
    raise exception 'La identidad final del ledger no coincide con el mapa';
  end if;
end;
$reconciliar$;
select 'OK: cinco versiones SLA reconciliadas; SQL y demás campos intactos' as veredicto;
commit;

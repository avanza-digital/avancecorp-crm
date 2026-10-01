-- REGISTRO en supabase_migrations.schema_migrations de 20260929220021_crm_indice_inversionistas_perfil.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega
-- si el índice no existe, no es válido o tiene otra definición, o si la versión ya está registrada con otro nombre.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_indice_inversionistas_perfil'));
do $chk$
declare
  v_def text;
  v_valido boolean;
begin
  select pg_get_indexdef(x.indexrelid), x.indisvalid and x.indisready into v_def, v_valido
  from pg_index x
  where x.indexrelid = to_regclass('crm.inversionistas_perfil_idx');
  if v_def is null then
    raise exception 'REGISTRO: crm.inversionistas_perfil_idx no existe; aplica primero la migración 20260929220021';
  end if;
  if v_def <> 'CREATE INDEX inversionistas_perfil_idx ON crm.inversionistas USING btree (perfil_id)' then
    raise exception 'REGISTRO: crm.inversionistas_perfil_idx tiene otra definición: %', v_def;
  end if;
  if not v_valido then
    raise exception 'REGISTRO: crm.inversionistas_perfil_idx existe pero no es válido';
  end if;
  if exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260929220021' and coalesce(name, '') <> 'crm_indice_inversionistas_perfil'
  ) then
    raise exception 'REGISTRO: la versión 20260929220021 ya está registrada con otro nombre';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260929220021', 'crm_indice_inversionistas_perfil',
        array['create index if not exists inversionistas_perfil_idx on crm.inversionistas (perfil_id);'])
on conflict (version) do nothing;
-- Relectura fail-closed (Codex P2, 29/09): si otra sesión que no usa este candado registró la
-- versión con otro nombre entre la comprobación y el insert, el conflicto se habría tragado en
-- silencio. Se valida la fila EFECTIVA antes del commit.
do $post$
begin
  if not exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260929220021' and name = 'crm_indice_inversionistas_perfil'
  ) then
    raise exception 'REGISTRO: tras el insert, la versión 20260929220021 no quedó con el nombre crm_indice_inversionistas_perfil';
  end if;
  raise notice 'REGISTRO_INDICE_PERFIL_OK';
end $post$;
select version, name from supabase_migrations.schema_migrations where version = '20260929220021';
commit;

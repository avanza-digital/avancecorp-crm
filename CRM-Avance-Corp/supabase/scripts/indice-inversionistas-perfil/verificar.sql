-- VERIFICACIÓN tras aplicar 20260929220021 (solo lectura; termina SIEMPRE en raise).
-- Esperado: indice=valido, cartera_f5_fuentes con seq=0 y el plan de perfil_id por el índice nuevo.
do $$
declare
  r oid := 'crm.inversionistas'::regclass;
  s0 bigint; i0 bigint; s1 bigint; i1 bigint; t0 timestamptz; t1 timestamptz;
  v_valido boolean; plan text := ''; l text;
begin
  set local transaction read only;
  select x.indisvalid and x.indisready into v_valido
  from pg_index x where x.indexrelid = to_regclass('crm.inversionistas_perfil_idx');
  select seq_scan, idx_scan into s0, i0 from pg_stat_xact_user_tables where relid = r;
  t0 := clock_timestamp(); perform count(*) from private.cartera_f5_fuentes(); t1 := clock_timestamp();
  select seq_scan, idx_scan into s1, i1 from pg_stat_xact_user_tables where relid = r;
  for l in execute $q$explain select i.id from crm.inversionistas i where i.perfil_id = '00000000-0000-0000-0000-000000000000'::uuid$q$
  loop plan := plan || l || E'\n'; end loop;
  -- Codex R2: la búsqueda CON la condición del único parcial debe seguir teniendo un plan por índice.
  plan := plan || E'PLAN perfil_id + estado <> fusionado:\n';
  for l in execute $q$explain select i.id from crm.inversionistas i where i.perfil_id = '00000000-0000-0000-0000-000000000000'::uuid and i.estado <> 'fusionado'$q$
  loop plan := plan || l || E'\n'; end loop;
  raise exception E'VERIFICACION (solo lectura)\nindice=%\ncartera_f5_fuentes: seq=% idx=% tiempo=% ms (antes: seq=679, ~91 ms)\nPLAN perfil_id:\n%',
    case when v_valido then 'valido' when v_valido is null then 'NO EXISTE' else 'INVALIDO' end,
    s1-s0, i1-i0, round(extract(epoch from t1-t0)*1000), plan;
end $$;

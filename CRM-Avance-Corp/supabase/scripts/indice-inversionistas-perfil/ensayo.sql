-- ENSAYO DESHECHO: crea el índice, mide y termina SIEMPRE en raise → rollback. Nada queda en producción.
do $$
declare
  r oid := 'crm.inversionistas'::regclass;
  s0 bigint; i0 bigint; s1 bigint; i1 bigint; s2 bigint; i2 bigint; s3 bigint; i3 bigint;
  t0 timestamptz; t1 timestamptz; t2 timestamptz; t3 timestamptz; t4 timestamptz;
  h_antes text; h_despues text; n int; plan text := ''; l text;
begin
  set local lock_timeout = '3s';
  set local statement_timeout = '30s';
  -- ANTES
  select md5(string_agg(f::text, '|' order by f.fuente_id)), count(*) into h_antes, n from private.cartera_f5_fuentes() f;
  select seq_scan, idx_scan into s0, i0 from pg_stat_xact_user_tables where relid = r;
  t0 := clock_timestamp(); perform count(*) from private.cartera_f5_fuentes(); t1 := clock_timestamp();
  select seq_scan, idx_scan into s1, i1 from pg_stat_xact_user_tables where relid = r;
  -- EL CAMBIO (idéntico a la migración 20260929220021)
  create index if not exists inversionistas_perfil_idx on crm.inversionistas (perfil_id);
  -- DESPUÉS
  select seq_scan, idx_scan into s2, i2 from pg_stat_xact_user_tables where relid = r;
  t2 := clock_timestamp(); perform count(*) from private.cartera_f5_fuentes(); t3 := clock_timestamp();
  select seq_scan, idx_scan into s3, i3 from pg_stat_xact_user_tables where relid = r;
  select md5(string_agg(f::text, '|' order by f.fuente_id)) into h_despues from private.cartera_f5_fuentes() f;
  for l in execute $q$explain select i.id from crm.inversionistas i where i.perfil_id = '00000000-0000-0000-0000-000000000000'::uuid$q$
  loop plan := plan || l || E'\n'; end loop;
  raise exception E'ENSAYO DESHECHO (rollback)\nfilas=%\nANTES:   seq=% idx=% tiempo=% ms\nDESPUES: seq=% idx=% tiempo=% ms\nmismas filas: % (antes % / despues %)\nPLAN perfil_id:\n%',
    n, s1-s0, i1-i0, round(extract(epoch from t1-t0)*1000),
    s3-s2, i3-i2, round(extract(epoch from t3-t2)*1000),
    h_antes = h_despues, left(h_antes,8), left(h_despues,8), plan;
end $$;

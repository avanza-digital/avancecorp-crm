-- VERIFICACIÓN tras aplicar 20260930154341_crm_sla_vigilante_ayudante (termina SIEMPRE en raise → nada queda).
-- Esperado: huella nueva y el guardián ampliado en OK (y el paraguas de Gestión Diaria, que lo llama).
do $$
declare v_md5 text; g text; p text; t0 timestamptz; ms numeric;
begin
  set local statement_timeout = '60s';
  select md5(pg_get_functiondef('private.assert_sla_avisos()'::regprocedure)) into v_md5;
  t0 := clock_timestamp(); g := private.assert_sla_avisos(); ms := round(extract(epoch from clock_timestamp()-t0)*1000);
  p := left(private.assert_gestion_diaria(), 40);
  raise exception E'VERIFICACION (rollback)\nhuella=% (esperada 9b9edc86c3a55d89367b6d64203d38dc: %)\nguardián ampliado: % (% ms)\nparaguas: %', v_md5, case when v_md5='9b9edc86c3a55d89367b6d64203d38dc' then 'OK' else 'DISTINTA' end, g, ms, p;
end $$;

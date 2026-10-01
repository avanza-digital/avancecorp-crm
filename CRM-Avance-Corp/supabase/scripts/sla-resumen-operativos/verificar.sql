-- VERIFICACIÓN tras aplicar 20260930002929_crm_sla_resumen_solo_operativos (termina SIEMPRE en raise → nada queda).
-- Esperado: huella nueva, ayudante presente, guardián OK y resumen de gerencia ≤ 1.200 ms (antes 1.735–1.749).
do $$
declare v_uid uuid; v_md5 text; t0 timestamptz; ms1 numeric; n int; g text;
begin
  set local statement_timeout = '60s';
  select md5(pg_get_functiondef('crm.avisos_sla_resumen_v2_fn()'::regprocedure)) into v_md5;
  g := private.assert_sla_avisos();
  select e.perfil_id into v_uid from crm.equipo e where e.rol_crm='gerencia' and e.activo order by e.perfil_id limit 1;
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  t0 := clock_timestamp(); perform crm.avisos_sla_resumen_v2_fn(); ms1 := round(extract(epoch from clock_timestamp()-t0)*1000);
  select cardinality(private.sla_leads_operativos()) into n;
  raise exception E'VERIFICACION (rollback)\nhuella=% (esperada e9ce617ab0cc33bc5614ef69e877cc71: %)\nguardián: %\noperativos=% · resumen gerencia: % ms (antes 1.735–1.749; meta ≤ 1.200)',
    v_md5, case when v_md5='e9ce617ab0cc33bc5614ef69e877cc71' then 'OK' else 'DISTINTA' end, g, n, ms1;
end $$;

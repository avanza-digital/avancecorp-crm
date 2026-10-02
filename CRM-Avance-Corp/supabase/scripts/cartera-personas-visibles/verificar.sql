-- VERIFICACIÓN tras aplicar 20260929230336_crm_cartera_personas_visibles_cierre_sin_bucle (termina SIEMPRE en raise → nada queda).
-- No puede ser `read only`: el listado deja un rastro en crm.cartera_lecturas (cartera_f5_registrar) que el raise deshace.
-- Esperado: huella nueva, listado de gerencia < 400 ms (antes 2.300–3.200) y sin bucle sobre la CTE fuentes.
do $$
declare v_uid uuid; v_md5 text; t0 timestamptz; ms1 numeric; ms2 numeric; ms3 numeric; n int;
begin
  set local statement_timeout = '60s';
  select md5(pg_get_functiondef('private.cartera_f5_personas_visibles(uuid)'::regprocedure)) into v_md5;
  select e.perfil_id into v_uid from crm.equipo e where e.rol_crm='gerencia' and e.activo order by e.perfil_id limit 1;
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  t0 := clock_timestamp(); select count(*) into n from private.cartera_f5_personas_visibles(); ms1 := round(extract(epoch from clock_timestamp()-t0)*1000);
  t0 := clock_timestamp(); perform crm.cartera_inversionistas_filtrada_fn(); ms2 := round(extract(epoch from clock_timestamp()-t0)*1000);
  t0 := clock_timestamp(); perform crm.cartera_inversionistas_filtrada_fn(p_texto=>'a'); ms3 := round(extract(epoch from clock_timestamp()-t0)*1000);
  raise exception E'VERIFICACION (rollback)\nhuella=% (esperada bca76d60bd56905eff978357f539d300: %)\npersonas_visibles(): % filas, % ms (antes ~2.200–4.500)\nlistado pág. 1: % ms · con texto: % ms (antes 2.300–3.200; meta < 400)',
    v_md5, case when v_md5='bca76d60bd56905eff978357f539d300' then 'OK' else 'DISTINTA' end, n, ms1, ms2, ms3;
end $$;

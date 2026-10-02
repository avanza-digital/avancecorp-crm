-- VERIFICACIÓN tras aplicar 20260930172255_crm_cartera_f5_fuentes_mapas (termina SIEMPRE en raise → nada queda).
-- Esperado: huella nueva fa15f7765d0892c790c7a4b6822e756e; cartera_f5_fuentes ≤ 15 ms (antes ~42); ficha de inversionista (gerencia) < 350 ms
-- (antes ~500); postventa_agenda_fn < 130 ms (antes ~165); cartera_inversionistas_filtrada_fn < 160 ms (antes ~190).
do $$
declare v_uid uuid; v_md5 text; t0 timestamptz; ms_f numeric := 0; ms_ficha numeric; ms_agenda numeric; ms_cartera numeric; n int; v_inv uuid; i int;
begin
  set local statement_timeout = '60s';
  select md5(pg_get_functiondef('private.cartera_f5_fuentes()'::regprocedure)) into v_md5;
  select e.perfil_id into v_uid from crm.equipo e where e.rol_crm='gerencia' and e.activo order by e.perfil_id limit 1;
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  select f.inversionista_id into v_inv from private.cartera_f5_fuentes_reales() f where f.inversionista_id is not null order by f.creado_en desc limit 1;
  perform count(*) from private.cartera_f5_fuentes(); -- calentar
  for i in 1..5 loop t0 := clock_timestamp(); perform count(*) from private.cartera_f5_fuentes(); ms_f := ms_f + extract(epoch from clock_timestamp()-t0)*1000; end loop;
  select count(*) into n from private.cartera_f5_fuentes();
  t0 := clock_timestamp(); perform crm.inversionista_ficha_fn(v_inv,1,1); ms_ficha := round(extract(epoch from clock_timestamp()-t0)*1000);
  t0 := clock_timestamp(); perform crm.postventa_agenda_fn(); ms_agenda := round(extract(epoch from clock_timestamp()-t0)*1000);
  t0 := clock_timestamp(); perform crm.cartera_inversionistas_filtrada_fn(1,25,null,null,null,false,null,null,null,null,false); ms_cartera := round(extract(epoch from clock_timestamp()-t0)*1000);
  raise exception E'VERIFICACION (rollback)\nhuella=% (esperada fa15f7765d0892c790c7a4b6822e756e: %)\ncartera_f5_fuentes: % fuentes, % ms/llamada (antes ~42; meta ≤ 15)\nficha de inversionista: % ms (antes ~500; meta < 350) · postventa_agenda_fn: % ms (antes ~165; meta < 130) · cartera_inversionistas_filtrada_fn: % ms (antes ~190; meta < 160)',
    v_md5, case when v_md5='fa15f7765d0892c790c7a4b6822e756e' then 'OK' else 'DISTINTA' end, n, round(ms_f/5,1), ms_ficha, ms_agenda, ms_cartera;
end $$;

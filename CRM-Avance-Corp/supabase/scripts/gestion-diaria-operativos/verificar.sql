-- VERIFICACIÓN tras aplicar 20260930150852_crm_gestion_diaria_solo_operativos (termina SIEMPRE en raise → nada queda).
-- Esperado: huellas nuevas, guardianes OK, equipo de gerencia ≤ 1.300 ms (antes ~1.850) y avisos del supervisor grande ≤ 900 (antes ~1.030).
do $$
declare h_a text; h_p text; h_1 text; h_2 text; g1 text; g2 text; v_ger uuid; v_sup uuid; t0 timestamptz; ms1 numeric; ms2 numeric; hoy date:=(now() at time zone 'America/Lima')::date;
begin
  set local statement_timeout = '90s';
  select md5(p.prosrc) into h_a from pg_proc p where p.oid='private.gestion_diaria_alertas_sla()'::regprocedure;
  h_p := md5(pg_get_functiondef('private.gestion_diaria_equipo_pendientes()'::regprocedure)); h_1 := md5(pg_get_functiondef('private.assert_gestion_diaria_alertas_equipo()'::regprocedure)); h_2 := md5(pg_get_functiondef('private.assert_gestion_diaria_equipo()'::regprocedure));
  g1 := left(private.assert_gestion_diaria(), 40); g2 := private.assert_sla_avisos();
  select e.perfil_id into v_ger from crm.equipo e where e.rol_crm='gerencia' and e.activo order by e.perfil_id limit 1;
  select l.asignado_supervisor_id into v_sup from crm.leads l join crm.equipo e on e.perfil_id=l.asignado_supervisor_id and e.rol_crm='supervisor' and e.activo where l.activo group by 1 order by count(*) desc limit 1;
  perform set_config('request.jwt.claim.sub', v_ger::text, true); perform set_config('request.jwt.claims', json_build_object('sub', v_ger, 'role', 'authenticated')::text, true); perform set_config('request.jwt.claim.role', 'authenticated', true);
  t0 := clock_timestamp(); perform crm.gestion_diaria_equipo_fn(hoy, null); ms1 := round(extract(epoch from clock_timestamp()-t0)*1000);
  perform set_config('request.jwt.claim.sub', v_sup::text, true); perform set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated')::text, true);
  t0 := clock_timestamp(); perform crm.gestion_diaria_avisos_fn(); ms2 := round(extract(epoch from clock_timestamp()-t0)*1000);
  raise exception E'VERIFICACION (rollback)\nhuellas: alertas % · pendientes % · assert_alertas % · assert_equipo % (esperadas 94bbf61c… 034cbb49… 02c9cd9f… 28f82e7d…)\nguardianes: % · %\nequipo gerencia: % ms (antes ~1.850) · avisos supervisor grande: % ms (antes ~1.030)',
    left(h_a,8), left(h_p,8), left(h_1,8), left(h_2,8), g1, g2, ms1, ms2;
end $$;

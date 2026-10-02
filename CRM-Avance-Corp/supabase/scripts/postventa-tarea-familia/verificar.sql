-- VERIFICACIÓN tras aplicar 20260930000550_crm_postventa_tarea_json_por_familia (termina SIEMPRE en raise → nada queda; no puede ser read only porque
-- postventa_modo() toma FOR SHARE). Esperado: huella nueva y postventa_agenda_fn (gerencia) < 250 ms (antes ~530).
do $$
declare v_uid uuid; v_md5 text; t0 timestamptz; ms1 numeric; ms2 numeric; n int;
begin
  set local statement_timeout = '60s';
  select md5(pg_get_functiondef('private.postventa_tarea_json(crm.tareas)'::regprocedure)) into v_md5;
  select e.perfil_id into v_uid from crm.equipo e where e.rol_crm='gerencia' and e.activo order by e.perfil_id limit 1;
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  t0 := clock_timestamp(); select jsonb_array_length(crm.postventa_agenda_fn()) into n; ms1 := round(extract(epoch from clock_timestamp()-t0)*1000);
  t0 := clock_timestamp(); perform crm.tareas_pendientes_fn(); ms2 := round(extract(epoch from clock_timestamp()-t0)*1000);
  raise exception E'VERIFICACION (rollback)\nhuella=% (esperada bff893c533d645be75d884788173bd50: %)\npostventa_agenda_fn: % tareas, % ms (antes ~530; meta < 250) · tareas_pendientes_fn: % ms',
    v_md5, case when v_md5='bff893c533d645be75d884788173bd50' then 'OK' else 'DISTINTA' end, n, ms1, ms2;
end $$;

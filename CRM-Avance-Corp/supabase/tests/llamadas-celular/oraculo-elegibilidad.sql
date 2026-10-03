-- Oráculo de 20261001222431 (la elegibilidad de la ingesta se evalúa como el dueño del celular) sobre el
-- banco REDUCIDO de supabase/tests/llamadas-celular/base.sql. Se corre como dueño después de F2-b, F2-c y
-- la corrección; todo en una transacción que termina en ROLLBACK. La ingesta se llama como en el
-- oráculo de F2-c: el núcleo directo y SIN sesión de usuario, como la llamará el servicio.
-- Equipo del banco: b1 supervisa a a1 y a2; b2 supervisa a a3.
-- No sustituye el gate test-rls.mjs contra un banco con el esquema de producción.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

do $oraculo$
declare
  a1 constant uuid := '00000000-0000-0000-0000-0000000000a1';
  b1 constant uuid := '00000000-0000-0000-0000-0000000000b1';
  g1 constant uuid := '00000000-0000-0000-0000-0000000000f1';
  c1 constant uuid := '00000000-0000-0000-0000-0000000000c1';
  c9 constant uuid := '00000000-0000-0000-0000-0000000000c9';
  v_c1 uuid;
  v_c4 uuid;
  v_r jsonb;
  v_n integer;
begin
  -- Preparación: C1 para el analista a1 y C4 para su supervisor b1; un lead del equipo de b1 sin analista.
  perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
  v_c1 := (crm.asignar_celular('C1', a1) ->> 'asignacion_id')::uuid;
  v_c4 := (crm.asignar_celular('C4', b1) ->> 'asignacion_id')::uuid;
  execute 'set local role none';
  insert into crm.leads (id, nombre_completo, telefono, etapa, vendedor_id, asignado_supervisor_id)
  values (c9, 'Lead Sin Analista', '+51900000009', 'nuevo', null, b1);
  perform set_config('request.jwt.claim.sub', '', true);

  -- ═════ A. Celular del supervisor: los leads de su equipo piden resultado; los demás, no ═════
  v_r := private.llamada_celular_ingerir(v_c4, '{"v": 1, "evento_origen_id": "e-a1", "numero": "900000001", "direccion": "saliente"}');
  if v_r ->> 'atencion' is distinct from 'requiere_resultado' then
    raise exception 'ORACULO A1: la llamada del supervisor a un lead de su analista no pide resultado (%)', v_r;
  end if;
  v_r := private.llamada_celular_ingerir(v_c4, '{"v": 1, "evento_origen_id": "e-a2", "numero": "900000003", "direccion": "saliente"}');
  if v_r ->> 'atencion' is distinct from 'requiere_resultado' then
    raise exception 'ORACULO A2: la llamada del supervisor a un lead de otro analista de su equipo no pide resultado (%)', v_r;
  end if;
  v_r := private.llamada_celular_ingerir(v_c4, '{"v": 1, "evento_origen_id": "e-a3", "numero": "900000009", "direccion": "saliente"}');
  if v_r ->> 'atencion' is distinct from 'requiere_resultado' then
    raise exception 'ORACULO A3: la llamada del supervisor a un lead de su equipo sin analista no pide resultado (%)', v_r;
  end if;
  v_r := private.llamada_celular_ingerir(v_c4, '{"v": 1, "evento_origen_id": "e-a4", "numero": "900000008", "direccion": "saliente"}');
  if v_r ->> 'atencion' is distinct from 'por_revisar' then
    raise exception 'ORACULO A4: la llamada del supervisor a un lead de otro equipo pide resultado (%)', v_r;
  end if;
  v_r := private.llamada_celular_ingerir(v_c4, '{"v": 1, "evento_origen_id": "e-a5", "numero": "900000004", "direccion": "saliente"}');
  if v_r ->> 'atencion' is distinct from 'por_revisar' then
    raise exception 'ORACULO A5: una llamada a un lead en «no contactar» pide resultado (%)', v_r;
  end if;

  -- ═════ B. Celular del analista: no cambia ═════
  v_r := private.llamada_celular_ingerir(v_c1, '{"v": 1, "evento_origen_id": "e-b1", "numero": "900000001", "direccion": "saliente"}');
  if v_r ->> 'atencion' is distinct from 'requiere_resultado' then
    raise exception 'ORACULO B1: la llamada del analista a su lead dejó de pedir resultado (%)', v_r;
  end if;
  v_r := private.llamada_celular_ingerir(v_c1, '{"v": 1, "evento_origen_id": "e-b2", "numero": "900000003", "direccion": "saliente"}');
  if v_r ->> 'atencion' is distinct from 'por_revisar' then
    raise exception 'ORACULO B2: la llamada del analista a un lead ajeno pide resultado (%)', v_r;
  end if;
  v_r := private.llamada_celular_ingerir(v_c1, '{"v": 1, "evento_origen_id": "e-b3", "numero": "900000009", "direccion": "saliente"}');
  if v_r ->> 'atencion' is distinct from 'por_revisar' then
    raise exception 'ORACULO B3: la llamada del analista a un lead del supervisor sin analista pide resultado (%)', v_r;
  end if;

  -- ═════ C. La identidad vuelve y la bitácora no atribuye la llamada ═════
  if coalesce(pg_catalog.current_setting('request.jwt.claim.sub', true), '') <> '' then
    raise exception 'ORACULO C1: la ingesta dejó puesta la identidad del dueño del celular';
  end if;
  select count(*) into v_n from public.audit_log l
  where l.tabla = 'crm.llamadas_celular_eventos' and l.operacion = 'INSERT';
  if v_n <> 8 or exists (select 1 from public.audit_log l
                         where l.tabla = 'crm.llamadas_celular_eventos' and l.usuario_id is not null) then
    raise exception 'ORACULO C2: la bitácora atribuyó una llamada a una persona (o faltan filas: %)', v_n;
  end if;
  perform set_config('request.jwt.claim.sub', g1::text, true);
  v_r := private.llamada_celular_ingerir(v_c4, '{"v": 1, "evento_origen_id": "e-c3", "numero": "900000001", "direccion": "saliente"}');
  if pg_catalog.current_setting('request.jwt.claim.sub', true) is distinct from g1::text then
    raise exception 'ORACULO C3: la ingesta no devolvió la identidad que había antes';
  end if;
  perform set_config('request.jwt.claim.sub', '', true);

  -- ═════ D. El supervisor ve sus llamadas a su equipo como pendientes de resultado ═════
  perform set_config('request.jwt.claim.sub', b1::text, true); execute 'set local role authenticated';
  v_r := crm.llamadas_celular_pendientes_fn(50);
  execute 'set local role none';
  if (select count(*) from jsonb_array_elements(v_r) x
      where (x ->> 'es_propia')::boolean and x ->> 'atencion' = 'requiere_resultado') <> 4 then
    raise exception 'ORACULO D1: el supervisor no ve sus 4 llamadas a su equipo como pendientes de resultado (%)', v_r;
  end if;

  -- ═════ E. Sin dueño no hay elegibilidad ═════
  if private.llamada_celular_elegible_dueno(null, c1) then
    raise exception 'ORACULO E1: sin dueño del celular, la llamada salió elegible';
  end if;

  raise notice 'ORACULO ELEGIBILIDAD OK: supervisor (su equipo, otro equipo, sin analista, no contactar), analista sin cambios, identidad devuelta y bitácora sin atribuir comprobados';
end;
$oraculo$;

rollback;

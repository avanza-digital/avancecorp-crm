-- Oráculo del núcleo y las puertas (20261001160219, F2-c) sobre el banco REDUCIDO de
-- supabase/tests/llamadas-celular/base.sql (usa sus perfiles y leads sintéticos). Se corre como
-- dueño DESPUÉS de las dos migraciones; todo en una transacción que termina en ROLLBACK.
-- Los actores se simulan como en Supabase: rol authenticated (o anon) + request.jwt.claim.sub.
-- Un SET LOCAL hecho dentro de un bloque con EXCEPTION se deshace si el bloque falla: por eso los
-- casos que deben fallar cambian de actor DENTRO de su bloque.
-- No sustituye el gate test-rls.mjs (F2-d) contra un banco con el esquema de producción.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

do $oraculo$
declare
  a1 constant uuid := '00000000-0000-0000-0000-0000000000a1';
  a2 constant uuid := '00000000-0000-0000-0000-0000000000a2';
  a3 constant uuid := '00000000-0000-0000-0000-0000000000a3';
  a9 constant uuid := '00000000-0000-0000-0000-0000000000a9';
  b1 constant uuid := '00000000-0000-0000-0000-0000000000b1';
  b2 constant uuid := '00000000-0000-0000-0000-0000000000b2';
  g1 constant uuid := '00000000-0000-0000-0000-0000000000f1';
  c1 constant uuid := '00000000-0000-0000-0000-0000000000c1';
  c2 constant uuid := '00000000-0000-0000-0000-0000000000c2';
  c3 constant uuid := '00000000-0000-0000-0000-0000000000c3';
  c4 constant uuid := '00000000-0000-0000-0000-0000000000c4';
  c5 constant uuid := '00000000-0000-0000-0000-0000000000c5';
  c6 constant uuid := '00000000-0000-0000-0000-0000000000c6';
  c7 constant uuid := '00000000-0000-0000-0000-0000000000c7';
  v_r jsonb;
  v_r2 jsonb;
  v_c1 uuid;
  v_c2 uuid;
  v_c2b uuid;
  v_c4 uuid;
  v_c9 uuid;
  v_cred text;
  v_cred2 text;
  e_l1 uuid;
  e_l2 uuid;
  e_l3 uuid;
  e_l4 uuid;
  e_l5 uuid;
  e_amb uuid;
  e_dup uuid;
  e_sin uuid;
  act1 uuid;
  act_c5 uuid;
  act1b uuid;
  act_old uuid;
  act_c2 uuid;
  act_c4 uuid;
  act_nota uuid;
  v_t timestamptz := pg_catalog.date_trunc('second', now() - interval '1 hour');
  v_ok integer := 0;
begin
  -- ═════ A. Celulares: solo gerencia asigna; la credencial sale una vez y solo queda su hash ═════
  perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
  v_r := crm.asignar_celular('C1', a1);
  execute 'set local role none';
  v_c1 := (v_r ->> 'asignacion_id')::uuid;
  v_cred := v_r ->> 'credencial';
  if coalesce(v_cred, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'ORACULO A1: la credencial no son 64 caracteres hex';
  end if;
  if (select a.credencial_hash from crm.celulares_asignaciones a where a.id = v_c1)
       is distinct from encode(sha256(convert_to(v_cred, 'utf8')), 'hex') then
    raise exception 'ORACULO A1: no se guardó el sha256 de la credencial';
  end if;
  if exists (select 1 from crm.celulares_asignaciones a where a.credencial_hash = v_cred)
     or exists (select 1 from public.audit_log l
                where strpos(coalesce(l.data_antes::text, '') || coalesce(l.data_despues::text, ''), v_cred) > 0) then
    raise exception 'ORACULO A1: la credencial en claro quedó guardada';
  end if;
  begin
    perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
    perform crm.asignar_celular('C1', a2);
    raise exception 'ORACULO A2: C1 se asignó dos veces';
  exception when unique_violation then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
    perform crm.asignar_celular('C3', a9);
    raise exception 'ORACULO A3: celular asignado a un analista dado de baja';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
    perform crm.asignar_celular('celular', a1);
    raise exception 'ORACULO A3b: etiqueta inválida aceptada';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.asignar_celular('C5', a1);
    raise exception 'ORACULO A4: un analista asignó un celular';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', b1::text, true); execute 'set local role authenticated';
    perform crm.asignar_celular('C5', a1);
    raise exception 'ORACULO A5: un supervisor asignó un celular';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', '', true); execute 'set local role anon';
    perform crm.asignar_celular('C5', a1);
    raise exception 'ORACULO A6: anon ejecutó una puerta';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;

  perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
  v_c2 := (crm.asignar_celular('C2', a3) ->> 'asignacion_id')::uuid;
  v_c4 := (crm.asignar_celular('C4', b1) ->> 'asignacion_id')::uuid;
  execute 'set local role none';

  -- Supervisión lee las asignaciones de su equipo (sin hash de credencial); el analista, no.
  perform set_config('request.jwt.claim.sub', b1::text, true); execute 'set local role authenticated';
  v_r := crm.celulares_asignaciones_fn();
  execute 'set local role none';
  if not exists (select 1 from jsonb_array_elements(v_r) x where (x ->> 'asignacion_id')::uuid = v_c1)
     or not exists (select 1 from jsonb_array_elements(v_r) x where (x ->> 'asignacion_id')::uuid = v_c4)
     or exists (select 1 from jsonb_array_elements(v_r) x where (x ->> 'asignacion_id')::uuid = v_c2) then
    raise exception 'ORACULO A7: supervisión no ve exactamente los celulares de su equipo';
  end if;
  if v_r::text ~ '[0-9a-f]{64}' then
    raise exception 'ORACULO A7: la lectura de asignaciones expone un hash de credencial';
  end if;
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.celulares_asignaciones_fn();
    raise exception 'ORACULO A8: un analista leyó las asignaciones';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;

  -- Rotación: cierra la vigente (rotacion) y abre otra contigua al mismo analista.
  perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
  v_r := crm.rotar_credencial_celular('C2');
  execute 'set local role none';
  v_c2b := (v_r ->> 'asignacion_id')::uuid;
  v_cred2 := v_r ->> 'credencial';
  if not exists (select 1 from crm.celulares_asignaciones a
                 where a.id = v_c2 and a.vigente_hasta is not null and a.motivo_cierre = 'rotacion')
     or not exists (select 1 from crm.celulares_asignaciones a
                    where a.id = v_c2b and a.vigente_hasta is null and a.analista_id = a3
                      and a.credencial_hash = encode(sha256(convert_to(v_cred2, 'utf8')), 'hex')) then
    raise exception 'ORACULO A9: la rotación no cerró la anterior o no abrió la nueva';
  end if;
  perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
  v_r := crm.cerrar_asignacion_celular(v_c2b, 'extravio');
  v_r2 := crm.cerrar_asignacion_celular(v_c2b, 'extravio');
  execute 'set local role none';
  if (v_r ->> 'repetido')::boolean or not (v_r2 ->> 'repetido')::boolean then
    raise exception 'ORACULO A10: cerrar no es idempotente';
  end if;
  begin
    perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
    perform crm.cerrar_asignacion_celular(v_c2b, 'otro');
    raise exception 'ORACULO A10b: una asignación cerrada se recerró con otro motivo';
  exception when unique_violation then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
    perform crm.rotar_credencial_celular('C2');
    raise exception 'ORACULO A11: se rotó un celular sin asignación vigente';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;

  -- ═════ B. Ingesta (la invocará F3; aquí, como dueño y SIN sesión de usuario, como el celular) ═════
  perform set_config('request.jwt.claim.sub', '', true);
  v_r := private.llamada_celular_ingerir(v_c1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-0001',
           'numero', '900000001', 'direccion', 'saliente'));
  e_l1 := (v_r ->> 'evento_id')::uuid;
  if v_r ->> 'identificacion' <> 'identificado' or v_r ->> 'atencion' <> 'requiere_resultado'
     or (v_r ->> 'lead_id')::uuid <> c1 or (v_r ->> 'repetido')::boolean then
    raise exception 'ORACULO B1: la llamada a un lead propio no quedó identificada y pidiendo resultado (%)', v_r;
  end if;
  v_r := private.llamada_celular_ingerir(v_c1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-0001',
           'numero', '900000001', 'direccion', 'saliente'));
  if not (v_r ->> 'repetido')::boolean or (v_r ->> 'evento_id')::uuid <> e_l1 then
    raise exception 'ORACULO B2: el reenvío idéntico no devolvió el mismo evento';
  end if;
  begin
    perform private.llamada_celular_ingerir(v_c1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-0001',
              'numero', '900000001', 'direccion', 'saliente', 'duracion_seg', 30));
    raise exception 'ORACULO B3: el mismo origen con otro contenido se aceptó';
  exception when sqlstate 'P0409' then v_ok := v_ok + 1; end;
  -- El mismo instante con otra zona horaria (y otra sesión) es el MISMO contenido.
  set local timezone = 'America/Lima';
  v_r := private.llamada_celular_ingerir(v_c1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-0002',
           'numero', '900000001', 'direccion', 'saliente',
           'ocurrio_en', to_char(v_t at time zone 'America/Lima', 'YYYY-MM-DD"T"HH24:MI:SS') || '-05:00'));
  e_dup := (v_r ->> 'evento_id')::uuid;
  set local timezone = 'UTC';
  v_r := private.llamada_celular_ingerir(v_c1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-0002',
           'numero', '900000001', 'direccion', 'saliente',
           'ocurrio_en', to_char(v_t at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') || 'Z'));
  if not (v_r ->> 'repetido')::boolean or (v_r ->> 'evento_id')::uuid <> e_dup then
    raise exception 'ORACULO B4: el mismo instante en otra zona horaria se tomó como otro contenido';
  end if;
  v_r := private.llamada_celular_ingerir(v_c1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-0003',
           'numero', '+51 900 000 002', 'direccion', 'saliente'));
  e_l2 := (v_r ->> 'evento_id')::uuid;
  if (v_r ->> 'lead_id')::uuid is distinct from c2 then
    raise exception 'ORACULO B5: el número con espacios y +51 no encontró su lead';
  end if;
  v_r := private.llamada_celular_ingerir(v_c1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-0004',
           'numero', '0051900000003', 'direccion', 'saliente'));
  e_l3 := (v_r ->> 'evento_id')::uuid;
  if (v_r ->> 'lead_id')::uuid is distinct from c3 or v_r ->> 'atencion' <> 'por_revisar' then
    raise exception 'ORACULO B6: la llamada a un lead de otro analista no quedó identificada y por revisar (%)', v_r;
  end if;
  v_r := private.llamada_celular_ingerir(v_c1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-0005',
           'numero', '900000004', 'direccion', 'saliente'));
  e_l4 := (v_r ->> 'evento_id')::uuid;
  if (v_r ->> 'lead_id')::uuid is distinct from c4 or v_r ->> 'atencion' <> 'por_revisar' then
    raise exception 'ORACULO B7: «no contactar» pidió resultado (%)', v_r;
  end if;
  v_r := private.llamada_celular_ingerir(v_c1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-0006',
           'numero', '900000005', 'direccion', 'saliente'));
  e_l5 := (v_r ->> 'evento_id')::uuid;
  if (v_r ->> 'lead_id')::uuid is distinct from c5 or v_r ->> 'atencion' <> 'por_revisar' then
    raise exception 'ORACULO B8: un lead convertido pidió resultado (%)', v_r;
  end if;
  v_r := private.llamada_celular_ingerir(v_c1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-0007',
           'numero', '900000006', 'direccion', 'saliente'));
  e_amb := (v_r ->> 'evento_id')::uuid;
  if v_r ->> 'identificacion' <> 'ambiguo' or v_r ->> 'lead_id' is not null or v_r ->> 'atencion' <> 'por_revisar'
     or (select e.calidad ->> 'candidatos' from crm.llamadas_celular_eventos e where e.id = e_amb) <> '2' then
    raise exception 'ORACULO B9: un número de dos leads no quedó ambiguo (%)', v_r;
  end if;
  v_r := private.llamada_celular_ingerir(v_c1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-0008',
           'numero', '999999999', 'direccion', 'saliente'));
  if not (v_r ->> 'ignorado')::boolean or v_r ->> 'motivo' <> 'sin_lead'
     or exists (select 1 from crm.llamadas_celular_eventos e where e.evento_origen_id = 'o-0008') then
    raise exception 'ORACULO B10: una llamada a un número sin lead se guardó (decisión 3)';
  end if;
  v_r := private.llamada_celular_ingerir(v_c1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-0009',
           'numero', '', 'direccion', 'saliente'));
  if not (v_r ->> 'ignorado')::boolean or v_r ->> 'motivo' <> 'numero_no_valido' then
    raise exception 'ORACULO B11: un número oculto no se ignoró como no válido';
  end if;
  v_r := private.llamada_celular_ingerir(v_c1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-0010',
           'numero', '900000001', 'direccion', 'entrante'));
  if not (v_r ->> 'ignorado')::boolean or v_r ->> 'motivo' <> 'entrante_apagada' then
    raise exception 'ORACULO B12: una entrante se guardó con las entrantes apagadas (decisión 2)';
  end if;
  begin
    perform private.llamada_celular_ingerir(v_c1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-0011',
              'numero', '900000001', 'extra', 'x'));
    raise exception 'ORACULO B13: clave no prevista aceptada';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin
    perform private.llamada_celular_ingerir(v_c1, jsonb_build_object('v', 2, 'evento_origen_id', 'o-0011'));
    raise exception 'ORACULO B13b: versión 2 aceptada';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin
    perform private.llamada_celular_ingerir(v_c1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-0011',
              'ocurrio_en', 'ayer'));
    raise exception 'ORACULO B13c: hora ilegible aceptada';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin
    perform private.llamada_celular_ingerir(v_c1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-0011',
              'duracion_seg', -1));
    raise exception 'ORACULO B13d: duración negativa aceptada';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin
    perform private.llamada_celular_ingerir(v_c1, jsonb_build_object('v', 1, 'evento_origen_id', 'x'));
    raise exception 'ORACULO B13e: id de origen demasiado corto aceptado';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin
    perform private.llamada_celular_ingerir(v_c2, jsonb_build_object('v', 1, 'evento_origen_id', 'o-0012',
              'numero', '900000008'));
    raise exception 'ORACULO B14: un celular con la asignación cerrada ingirió';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash)
  values ('C9', a9, repeat('9', 64)) returning id into v_c9;
  begin
    perform private.llamada_celular_ingerir(v_c9, jsonb_build_object('v', 1, 'evento_origen_id', 'o-0013',
              'numero', '900000001'));
    raise exception 'ORACULO B15: el celular de un analista dado de baja ingirió';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
    perform crm.rotar_credencial_celular('C9');
    raise exception 'ORACULO B15b: se rotó la credencial del celular de un analista dado de baja';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  perform set_config('request.jwt.claim.sub', '', true);
  -- Las perillas mandan: con guardar_sin_identificar y entrantes encendidas, sí se guardan.
  perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
  perform crm.fijar_politica_llamadas_celular(p_guardar_sin_identificar => true, p_entrantes_activas => true);
  execute 'set local role none';
  v_r := private.llamada_celular_ingerir(v_c1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-0014',
           'numero', '999999999', 'direccion', 'saliente'));
  v_r2 := private.llamada_celular_ingerir(v_c1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-0015',
           'numero', '900000002', 'direccion', 'entrante'));
  if (v_r ->> 'ignorado')::boolean or v_r ->> 'identificacion' <> 'sin_identificar'
     or (v_r2 ->> 'ignorado')::boolean or (v_r2 ->> 'lead_id')::uuid is distinct from c2 then
    raise exception 'ORACULO B16: las perillas encendidas no guardaron la sin lead o la entrante';
  end if;
  e_sin := (v_r ->> 'evento_id')::uuid;
  perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
  perform crm.fijar_politica_llamadas_celular(p_guardar_sin_identificar => false, p_entrantes_activas => false);
  execute 'set local role none';

  -- ═════ C. Bandeja: cada quien ve lo de su ámbito ═════
  perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
  v_r := crm.llamadas_celular_pendientes_fn(50);
  execute 'set local role none';
  if not exists (select 1 from jsonb_array_elements(v_r) x
                 where (x ->> 'evento_id')::uuid = e_l1 and x ->> 'atencion' = 'requiere_resultado')
     or not exists (select 1 from jsonb_array_elements(v_r) x
                    where (x ->> 'evento_id')::uuid = e_l4 and x ->> 'atencion' = 'por_revisar')
     or not exists (select 1 from jsonb_array_elements(v_r) x
                    where (x ->> 'evento_id')::uuid = e_amb and (x ->> 'es_propia')::boolean)
     or exists (select 1 from jsonb_array_elements(v_r) x where (x ->> 'evento_id')::uuid = e_l3) then
    raise exception 'ORACULO C1: la bandeja de a1 no es la esperada';
  end if;
  perform set_config('request.jwt.claim.sub', a2::text, true); execute 'set local role authenticated';
  v_r := crm.llamadas_celular_pendientes_fn(50);
  execute 'set local role none';
  if not exists (select 1 from jsonb_array_elements(v_r) x
                 where (x ->> 'evento_id')::uuid = e_l3 and x ->> 'atencion' = 'por_revisar'
                   and not (x ->> 'es_propia')::boolean)
     or exists (select 1 from jsonb_array_elements(v_r) x where (x ->> 'evento_id')::uuid in (e_l1, e_amb)) then
    raise exception 'ORACULO C2: la bandeja de a2 no es la esperada';
  end if;
  perform set_config('request.jwt.claim.sub', a3::text, true); execute 'set local role authenticated';
  v_r := crm.llamadas_celular_pendientes_fn(50);
  execute 'set local role none';
  if exists (select 1 from jsonb_array_elements(v_r) x where (x ->> 'evento_id')::uuid in (e_l1, e_l3, e_amb)) then
    raise exception 'ORACULO C3: un analista de otro equipo ve llamadas ajenas';
  end if;
  perform set_config('request.jwt.claim.sub', b1::text, true); execute 'set local role authenticated';
  v_r := crm.llamadas_celular_pendientes_fn(50);
  execute 'set local role none';
  if (select count(*) from jsonb_array_elements(v_r) x where (x ->> 'evento_id')::uuid in (e_l1, e_l3, e_amb)) <> 3 then
    raise exception 'ORACULO C4: supervisión no ve las llamadas de su equipo';
  end if;
  perform set_config('request.jwt.claim.sub', b2::text, true); execute 'set local role authenticated';
  v_r := crm.llamadas_celular_pendientes_fn(50);
  execute 'set local role none';
  if exists (select 1 from jsonb_array_elements(v_r) x where (x ->> 'evento_id')::uuid in (e_l1, e_l3, e_amb)) then
    raise exception 'ORACULO C5: supervisión de otro equipo ve llamadas ajenas';
  end if;
  perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
  v_r := crm.llamadas_celular_pendientes_fn(200);
  execute 'set local role none';
  if (select count(*) from jsonb_array_elements(v_r) x
      where (x ->> 'evento_id')::uuid in (e_l1, e_l2, e_l3, e_l4, e_l5, e_amb, e_dup)) <> 7 then
    raise exception 'ORACULO C6: gerencia no ve todas las llamadas pendientes';
  end if;
  begin
    perform set_config('request.jwt.claim.sub', a9::text, true); execute 'set local role authenticated';
    perform crm.llamadas_celular_pendientes_fn(50);
    raise exception 'ORACULO C7: un analista dado de baja leyó la bandeja';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', '', true); execute 'set local role anon';
    perform crm.llamadas_celular_pendientes_fn(50);
    raise exception 'ORACULO C7b: anon leyó la bandeja';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.llamada_celular_detalle_fn(e_l3);
    raise exception 'ORACULO C8: a1 leyó el detalle de una llamada fuera de su ámbito';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  perform set_config('request.jwt.claim.sub', a2::text, true); execute 'set local role authenticated';
  v_r := crm.llamada_celular_detalle_fn(e_l3);
  execute 'set local role none';
  if (v_r ->> 'lead_id')::uuid is distinct from c3 then
    raise exception 'ORACULO C8b: la dueña del lead no ve el detalle';
  end if;
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.llamadas_celular_pendientes_fn(0);
    raise exception 'ORACULO C9: límite 0 aceptado';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform 1 from crm.llamadas_celular_eventos limit 1;
    raise exception 'ORACULO C10: authenticated leyó la tabla de llamadas directo';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;

  -- ═════ D. Asociar: solo a un lead propio con el número de la llamada ═════
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.asociar_llamada_celular(e_amb, c1);
    raise exception 'ORACULO D1: se asoció a un lead que no tiene el número';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.asociar_llamada_celular(e_amb, c7);
    raise exception 'ORACULO D2: se asoció a un lead de otro analista';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
  v_r := crm.asociar_llamada_celular(e_amb, c6);
  v_r2 := crm.asociar_llamada_celular(e_amb, c6);
  execute 'set local role none';
  if v_r ->> 'atencion' <> 'requiere_resultado' or (v_r ->> 'repetido')::boolean
     or not (v_r2 ->> 'repetido')::boolean
     or not exists (select 1 from crm.llamadas_celular_eventos e
                    where e.id = e_amb and e.identificacion = 'identificado' and e.lead_id = c6
                      and e.metodo_asociacion = 'manual' and e.asociado_por = a1) then
    raise exception 'ORACULO D3: la asociación manual no quedó bien o no es idempotente';
  end if;
  begin
    perform set_config('request.jwt.claim.sub', a2::text, true); execute 'set local role authenticated';
    perform crm.asociar_llamada_celular(e_amb, c7);
    raise exception 'ORACULO D5: a2 reasoció una llamada que ya no ve';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;

  -- ═════ E. Enlazar con el resultado de la encuesta ═════
  perform set_config('crm.op_resultado_llamada', 'on', true);
  insert into crm.actividades (lead_id, tipo, metadata, creado_por)
  values (c1, 'llamada_no_contestada', '{"evento": "resultado_llamada", "resultado": "no_contesto"}', a1)
  returning id into act1;
  insert into crm.actividades (lead_id, tipo, metadata, creado_por)
  values (c1, 'llamada_realizada', '{"evento": "resultado_llamada", "resultado": "volver_a_llamar"}', a1)
  returning id into act1b;
  insert into crm.actividades (lead_id, tipo, metadata, creado_por, creado_en)
  values (c1, 'llamada_realizada', '{"evento": "resultado_llamada", "resultado": "volver_a_llamar"}', a1, now() - interval '1 day')
  returning id into act_old;
  insert into crm.actividades (lead_id, tipo, metadata, creado_por)
  values (c2, 'llamada_realizada', '{"evento": "resultado_llamada", "resultado": "volver_a_llamar"}', a2)
  returning id into act_c2;
  insert into crm.actividades (lead_id, tipo, metadata, creado_por)
  values (c4, 'llamada_no_contestada', '{"evento": "resultado_llamada", "resultado": "no_contesto"}', a1)
  returning id into act_c4;
  insert into crm.actividades (lead_id, tipo, metadata, creado_por)
  values (c5, 'llamada_realizada', '{"evento": "resultado_llamada", "resultado": "volver_a_llamar"}', a1)
  returning id into act_c5;
  perform set_config('crm.op_resultado_llamada', 'off', true);
  insert into crm.actividades (lead_id, tipo, creado_por) values (c1, 'nota', a1) returning id into act_nota;

  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.enlazar_llamada_celular(e_l1, act_c2);
    raise exception 'ORACULO E1: se enlazó un resultado de otro lead';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.enlazar_llamada_celular(e_l1, act_nota);
    raise exception 'ORACULO E2: se enlazó una nota';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.enlazar_llamada_celular(e_l1, act_old);
    raise exception 'ORACULO E3: se enlazó un resultado registrado antes de la llamada';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', a2::text, true); execute 'set local role authenticated';
    perform crm.enlazar_llamada_celular(e_l1, act1);
    raise exception 'ORACULO E4: otra analista enlazó una llamada fuera de su ámbito';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
  v_r := crm.enlazar_llamada_celular(e_l1, act1);
  v_r2 := crm.enlazar_llamada_celular(e_l1, act1);
  execute 'set local role none';
  if (v_r ->> 'repetido')::boolean or not (v_r2 ->> 'repetido')::boolean
     or (select e.atencion from crm.llamadas_celular_eventos e where e.id = e_l1) <> 'registrado' then
    raise exception 'ORACULO E5: enlazar no dejó la llamada registrada o no es idempotente';
  end if;
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.enlazar_llamada_celular(e_l1, act1b);
    raise exception 'ORACULO E6: una llamada con resultado vigente se reenlazó';
  exception when unique_violation then v_ok := v_ok + 1; end;
  -- Decisión 4: si el resultado se deshace, el enlace se mueve al corregido.
  perform set_config('crm.op_resultado_llamada', 'on', true);
  update crm.actividades set metadata = metadata || jsonb_build_object('deshecho_en', now()) where id = act1;
  perform set_config('crm.op_resultado_llamada', 'off', true);
  perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
  v_r2 := crm.llamada_celular_detalle_fn(e_l1);
  v_r := crm.enlazar_llamada_celular(e_l1, act1b);
  v_r2 := v_r2 || jsonb_build_object('despues', crm.llamada_celular_detalle_fn(e_l1));
  execute 'set local role none';
  if not (v_r2 ->> 'efectos_anulados')::boolean or not (v_r ->> 'movido')::boolean
     or (v_r2 -> 'despues' ->> 'actividad_id')::uuid <> act1b
     or (v_r2 -> 'despues' ->> 'efectos_anulados')::boolean then
    raise exception 'ORACULO E7: el resultado deshecho no se marcó o el enlace no se movió (%)', v_r2;
  end if;
  perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
  perform crm.enlazar_llamada_celular(e_l4, act_c4);
  execute 'set local role none';
  if (select e.atencion from crm.llamadas_celular_eventos e where e.id = e_l4) <> 'registrado' then
    raise exception 'ORACULO E8: una llamada «por revisar» con resultado no quedó registrada';
  end if;
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.enlazar_llamada_celular(e_dup, act1b);
    raise exception 'ORACULO E9: un resultado quedó enlazado a dos llamadas';
  exception when unique_violation then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.enlazar_llamada_celular(e_sin, act1);
    raise exception 'ORACULO E10: se enlazó una llamada sin lead';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;

  -- ═════ F. Descartar con motivo ═════
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.descartar_llamada_celular(e_l5, 'otro');
    raise exception 'ORACULO F1: «otro» sin detalle aceptado';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.descartar_llamada_celular(e_l5, 'porque_si');
    raise exception 'ORACULO F1b: motivo fuera de catálogo aceptado';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
  v_r := crm.descartar_llamada_celular(e_l5, 'personal');
  v_r2 := crm.descartar_llamada_celular(e_l5, 'personal');
  execute 'set local role none';
  if (v_r ->> 'repetido')::boolean or not (v_r2 ->> 'repetido')::boolean
     or not exists (select 1 from crm.llamadas_celular_eventos e
                    where e.id = e_l5 and e.atencion = 'descartado_con_motivo' and e.descartado_por = a1) then
    raise exception 'ORACULO F2: el descarte no quedó o no es idempotente';
  end if;
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.descartar_llamada_celular(e_l5, 'no_comercial');
    raise exception 'ORACULO F2b: se cambió el motivo de un descarte';
  exception when unique_violation then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.descartar_llamada_celular(e_l1, 'personal');
    raise exception 'ORACULO F3: se descartó una llamada ya registrada';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.enlazar_llamada_celular(e_l5, act_c5);
    raise exception 'ORACULO F3b: se enlazó una llamada descartada';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', a3::text, true); execute 'set local role authenticated';
    perform crm.descartar_llamada_celular(e_l2, 'personal');
    raise exception 'ORACULO F4: un analista de otro equipo descartó una llamada ajena';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;

  -- ═════ G. Decisión 7: tras una reasignación, todo pasa al nuevo analista ═════
  update crm.leads set vendedor_id = a2 where id = c2;
  perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
  v_r := crm.llamadas_celular_pendientes_fn(50);
  execute 'set local role none';
  if exists (select 1 from jsonb_array_elements(v_r) x where (x ->> 'evento_id')::uuid = e_l2) then
    raise exception 'ORACULO G1: el analista anterior sigue viendo la llamada del lead reasignado';
  end if;
  perform set_config('request.jwt.claim.sub', a2::text, true); execute 'set local role authenticated';
  v_r := crm.llamadas_celular_pendientes_fn(50);
  execute 'set local role none';
  if not exists (select 1 from jsonb_array_elements(v_r) x
                 where (x ->> 'evento_id')::uuid = e_l2 and x ->> 'atencion' = 'requiere_resultado'
                   and not (x ->> 'es_propia')::boolean) then
    raise exception 'ORACULO G1b: la analista nueva no recibió la llamada pidiendo resultado';
  end if;
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.enlazar_llamada_celular(e_l2, act_c2);
    raise exception 'ORACULO G2: el analista anterior registró por un lead que ya no es suyo';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  perform set_config('request.jwt.claim.sub', a2::text, true); execute 'set local role authenticated';
  perform crm.enlazar_llamada_celular(e_l2, act_c2);
  execute 'set local role none';
  if not exists (select 1 from crm.llamadas_celular_eventos e
                 where e.id = e_l2 and e.atencion = 'registrado' and e.analista_id = a1) then
    raise exception 'ORACULO G3: la analista nueva no registró o se perdió quién llamó';
  end if;

  -- ═════ H. Decisión 1: la elegibilidad se re-evalúa al leer ═════
  update crm.leads set no_contactar = true where id = c1;
  perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
  v_r := crm.llamadas_celular_pendientes_fn(50);
  execute 'set local role none';
  if not exists (select 1 from jsonb_array_elements(v_r) x
                 where (x ->> 'evento_id')::uuid = e_dup and x ->> 'atencion' = 'por_revisar') then
    raise exception 'ORACULO H1: una llamada siguió pidiendo resultado tras marcar «no contactar»';
  end if;
  update crm.leads set no_contactar = false where id = c1;
  perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
  v_r := crm.llamadas_celular_pendientes_fn(50);
  execute 'set local role none';
  if not exists (select 1 from jsonb_array_elements(v_r) x
                 where (x ->> 'evento_id')::uuid = e_dup and x ->> 'atencion' = 'requiere_resultado') then
    raise exception 'ORACULO H2: la llamada no volvió a pedir resultado al levantar «no contactar»';
  end if;

  -- ═════ I. Política: solo gerencia ═════
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.fijar_politica_llamadas_celular(p_dias_retencion_descartados => 45);
    raise exception 'ORACULO I1: un analista cambió la política';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', b1::text, true); execute 'set local role authenticated';
    perform crm.llamadas_celular_politica_fn();
    raise exception 'ORACULO I2: supervisión leyó la política';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
    perform crm.fijar_politica_llamadas_celular(p_dias_retencion_descartados => 0);
    raise exception 'ORACULO I3: retención de 0 días aceptada';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
  v_r := crm.fijar_politica_llamadas_celular(p_dias_retencion_descartados => 45);
  v_r2 := crm.llamadas_celular_politica_fn();
  execute 'set local role none';
  if (v_r ->> 'dias_retencion_descartados') <> '45' or (v_r2 ->> 'dias_retencion_descartados') <> '45'
     or (v_r2 ->> 'actualizado_por')::uuid <> g1 or (v_r2 ->> 'dias_retencion_sin_resolver') <> '30' then
    raise exception 'ORACULO I4: la política no quedó como la fijó gerencia (%)', v_r2;
  end if;

  raise notice 'ORACULO F2-c OK: % defensas mordieron; asignación, ingesta, bandeja, asociar, enlazar, descartar, reasignación, re-evaluación y política comprobados', v_ok;
end;
$oraculo$;

rollback;

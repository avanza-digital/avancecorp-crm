-- Oráculo de la ingesta de servicio, el límite, la salud y la bandeja paginada (20261001212258, F3-a)
-- sobre el banco REDUCIDO de supabase/tests/llamadas-celular/base.sql. Se corre como dueño DESPUÉS
-- de F2-b, F2-c y F3-a; todo en una transacción que termina en ROLLBACK.
-- Actores simulados como en Supabase: rol authenticated / anon / service_role + request.jwt.claim.sub
-- (vacío para el servicio: la Edge llama con la clave de servicio, sin usuario).
-- Un SET LOCAL hecho dentro de un bloque con EXCEPTION se deshace si el bloque falla: por eso los
-- casos que deben fallar cambian de actor DENTRO de su bloque.
-- Dentro de una transacción now() no avanza: todos los envíos caen en el mismo minuto, y las
-- ventanas se «adelantan» moviendo minuto_desde / dia a mano.
-- No sustituye el gate test-rls.mjs contra un banco con el esquema de producción.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

do $oraculo$
declare
  a1 constant uuid := '00000000-0000-0000-0000-0000000000a1';
  a2 constant uuid := '00000000-0000-0000-0000-0000000000a2';
  a3 constant uuid := '00000000-0000-0000-0000-0000000000a3';
  b1 constant uuid := '00000000-0000-0000-0000-0000000000b1';
  g1 constant uuid := '00000000-0000-0000-0000-0000000000f1';
  c1 constant uuid := '00000000-0000-0000-0000-0000000000c1';
  sin_lead constant text := '900000099';
  latido_ok constant jsonb := '{"v": 1, "version_macro": "macro 1.0", "en_cola": 2, "ocurrio_en": "2026-10-01T12:00:00Z"}';
  v_r jsonb;
  v_r2 jsonb;
  v_c1 uuid;
  v_c2 uuid;
  v_c3 uuid;
  v_c4 uuid;
  v_c6 uuid;
  k1 text;
  k2 text;
  k3 text;
  k6 text;
  e1 uuid;
  v_msg text;
  v_det text;
  v_n integer;
  v_i integer;
  v_malo jsonb;
  v_paginas integer := 0;
  v_filas jsonb := '[]'::jsonb;
  v_antes_ts timestamptz;
  v_antes_id uuid;
  v_ok integer := 0;
begin
  -- ═════ Preparación: gerencia asigna los celulares (la clave sale una vez) ═════
  perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
  v_r := crm.asignar_celular('C1', a1); v_c1 := (v_r ->> 'asignacion_id')::uuid; k1 := v_r ->> 'credencial';
  v_r := crm.asignar_celular('C2', a3); v_c2 := (v_r ->> 'asignacion_id')::uuid; k2 := v_r ->> 'credencial';
  v_r := crm.asignar_celular('C3', a2); v_c3 := (v_r ->> 'asignacion_id')::uuid; k3 := v_r ->> 'credencial';
  v_r := crm.asignar_celular('C4', b1); v_c4 := (v_r ->> 'asignacion_id')::uuid;
  v_r := crm.asignar_celular('C6', a2); v_c6 := (v_r ->> 'asignacion_id')::uuid; k6 := v_r ->> 'credencial';
  perform crm.cerrar_asignacion_celular(v_c3, 'extravio');
  execute 'set local role none';

  -- ═════ A. Las puertas de servicio son solo del servicio ═════
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.ingerir_llamada_celular_servicio(k1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-a1',
      'numero', '900000001', 'direccion', 'saliente'));
    raise exception 'ORACULO A1: authenticated ejecutó la puerta de servicio de ingesta';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', '', true); execute 'set local role anon';
    perform crm.ingerir_llamada_celular_servicio(k1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-a2',
      'numero', '900000001', 'direccion', 'saliente'));
    raise exception 'ORACULO A2: anon ejecutó la puerta de servicio de ingesta';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', b1::text, true); execute 'set local role authenticated';
    perform crm.registrar_salud_celular_servicio(k1, latido_ok);
    raise exception 'ORACULO A3: authenticated ejecutó la puerta de servicio de salud';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;

  -- ═════ B. Clave inválida, de un celular cerrado o de un analista de baja: el MISMO «No autorizado» ═════
  begin
    perform set_config('request.jwt.claim.sub', '', true); execute 'set local role service_role';
    perform crm.ingerir_llamada_celular_servicio(repeat('0', 64), jsonb_build_object('v', 1,
      'evento_origen_id', 'o-b1', 'numero', '900000001', 'direccion', 'saliente'));
    raise exception 'ORACULO B1: una clave desconocida ingirió';
  exception when insufficient_privilege then
    if sqlerrm <> 'No autorizado' then raise exception 'ORACULO B1: la clave desconocida dio pistas (%)', sqlerrm; end if;
    v_ok := v_ok + 1;
  end;
  begin
    perform set_config('request.jwt.claim.sub', '', true); execute 'set local role service_role';
    perform crm.ingerir_llamada_celular_servicio(null, jsonb_build_object('v', 1,
      'evento_origen_id', 'o-b2', 'numero', '900000001', 'direccion', 'saliente'));
    raise exception 'ORACULO B2: una ingesta sin clave entró';
  exception when insufficient_privilege then
    if sqlerrm <> 'No autorizado' then raise exception 'ORACULO B2: la falta de clave dio pistas (%)', sqlerrm; end if;
    v_ok := v_ok + 1;
  end;
  begin
    perform set_config('request.jwt.claim.sub', '', true); execute 'set local role service_role';
    perform crm.ingerir_llamada_celular_servicio(k3, jsonb_build_object('v', 1,
      'evento_origen_id', 'o-b3', 'numero', '900000003', 'direccion', 'saliente'));
    raise exception 'ORACULO B3: la clave de un celular cerrado ingirió';
  exception when insufficient_privilege then
    if sqlerrm <> 'No autorizado' then raise exception 'ORACULO B3: el celular cerrado dio pistas (%)', sqlerrm; end if;
    v_ok := v_ok + 1;
  end;
  begin
    perform set_config('request.jwt.claim.sub', '', true); execute 'set local role service_role';
    perform crm.registrar_salud_celular_servicio(k3, latido_ok);
    raise exception 'ORACULO B4: la clave de un celular cerrado registró salud';
  exception when insufficient_privilege then
    if sqlerrm <> 'No autorizado' then raise exception 'ORACULO B4: el celular cerrado dio pistas (%)', sqlerrm; end if;
    v_ok := v_ok + 1;
  end;
  update crm.equipo set activo = false where perfil_id = a2;
  begin
    perform set_config('request.jwt.claim.sub', '', true); execute 'set local role service_role';
    perform crm.ingerir_llamada_celular_servicio(k6, jsonb_build_object('v', 1,
      'evento_origen_id', 'o-b5', 'numero', '900000003', 'direccion', 'saliente'));
    raise exception 'ORACULO B5: el celular de un analista de baja ingirió';
  exception when insufficient_privilege then
    if sqlerrm <> 'No autorizado' then raise exception 'ORACULO B5: el analista de baja dio pistas (%)', sqlerrm; end if;
    v_ok := v_ok + 1;
  end;
  begin
    perform set_config('request.jwt.claim.sub', '', true); execute 'set local role service_role';
    perform crm.registrar_salud_celular_servicio(k6, latido_ok);
    raise exception 'ORACULO B6: el celular de un analista de baja registró salud';
  exception when insufficient_privilege then
    if sqlerrm <> 'No autorizado' then raise exception 'ORACULO B6: el analista de baja dio pistas (%)', sqlerrm; end if;
    v_ok := v_ok + 1;
  end;
  update crm.equipo set activo = true where perfil_id = a2;
  if exists (select 1 from private.celulares_estado s where s.asignacion_id in (v_c3, v_c6)) then
    raise exception 'ORACULO B7: un envío rechazado dejó rastro en el estado del celular';
  end if;

  -- ═════ C. Ingesta válida: evento nuevo, repetido e ignorado; respuesta mínima; cuenta lo confirmado ═════
  perform set_config('request.jwt.claim.sub', '', true); execute 'set local role service_role';
  v_r := crm.ingerir_llamada_celular_servicio(k1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-c1',
    'numero', '900000001', 'direccion', 'saliente', 'duracion_seg', 30));
  v_r2 := crm.ingerir_llamada_celular_servicio(k1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-c1',
    'numero', '900000001', 'direccion', 'saliente', 'duracion_seg', 30));
  execute 'set local role none';
  e1 := (v_r ->> 'evento_id')::uuid;
  if e1 is null or (v_r ->> 'repetido')::boolean or (v_r ->> 'ignorado')::boolean then
    raise exception 'ORACULO C1: la ingesta válida no devolvió un evento nuevo (%)', v_r;
  end if;
  if v_r ?| array['lead_id', 'atencion', 'identificacion', 'analista_id']
     or v_r2 ?| array['lead_id', 'atencion', 'identificacion', 'analista_id'] then
    raise exception 'ORACULO C2: la respuesta al celular expone el lead o su atención (%)', v_r;
  end if;
  if not exists (select 1 from crm.llamadas_celular_eventos e
                 where e.id = e1 and e.asignacion_id = v_c1 and e.analista_id = a1 and e.lead_id = c1) then
    raise exception 'ORACULO C3: el evento no quedó con la asignación, el analista y el lead correctos';
  end if;
  if (v_r2 ->> 'evento_id')::uuid is distinct from e1 or not (v_r2 ->> 'repetido')::boolean then
    raise exception 'ORACULO C4: el reenvío no devolvió el mismo evento como repetido (%)', v_r2;
  end if;
  perform set_config('request.jwt.claim.sub', '', true); execute 'set local role service_role';
  v_r := crm.ingerir_llamada_celular_servicio(k1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-c2',
    'numero', sin_lead, 'direccion', 'saliente'));
  execute 'set local role none';
  if not (v_r ->> 'ignorado')::boolean or (v_r ->> 'motivo') is distinct from 'sin_lead' or (v_r ->> 'evento_id') is not null then
    raise exception 'ORACULO C5: un número sin lead no se ignoró (%)', v_r;
  end if;
  if not exists (select 1 from private.celulares_estado s
                 where s.asignacion_id = v_c1 and s.envios_minuto = 3 and s.envios_dia = 3
                   and s.ultimo_envio_en is not null) then
    raise exception 'ORACULO C6: el estado del celular no contó los 3 envíos confirmados';
  end if;
  begin
    perform set_config('request.jwt.claim.sub', '', true); execute 'set local role service_role';
    perform crm.ingerir_llamada_celular_servicio(k1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-c3',
      'numero', '900000001', 'direccion', 'saliente', 'extra', 1));
    raise exception 'ORACULO C7: un evento con claves no previstas se aceptó';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  if (select s.envios_minuto from private.celulares_estado s where s.asignacion_id = v_c1) <> 3 then
    raise exception 'ORACULO C8: un envío rechazado consumió el límite';
  end if;

  -- ═════ D. Límite por celular, compartido por llamadas y latidos, con ventanas que se reinician ═════
  -- El límite vale para todos los celulares: C1 ya lleva 3 envíos en este minuto (sección C).
  update crm.llamadas_celular_politica set limite_envios_minuto = 4, limite_envios_dia = 6;
  for v_i in 1..4 loop
    perform set_config('request.jwt.claim.sub', '', true); execute 'set local role service_role';
    perform crm.ingerir_llamada_celular_servicio(k2, jsonb_build_object('v', 1,
      'evento_origen_id', 'o-d' || v_i, 'numero', sin_lead, 'direccion', 'saliente'));
    execute 'set local role none';
  end loop;
  begin
    perform set_config('request.jwt.claim.sub', '', true); execute 'set local role service_role';
    perform crm.ingerir_llamada_celular_servicio(k2, jsonb_build_object('v', 1,
      'evento_origen_id', 'o-d5', 'numero', sin_lead, 'direccion', 'saliente'));
    raise exception 'ORACULO D1: el límite por minuto no frenó';
  exception when sqlstate 'P0429' then
    get stacked diagnostics v_msg = message_text, v_det = pg_exception_detail;
    if v_msg not like 'Demasiados envíos%'
       or coalesce(substring(v_det from '^reintentar_en_seg=([0-9]+)$')::integer, 0) not between 1 and 60 then
      raise exception 'ORACULO D2: el freno por minuto no dice cuánto esperar (% / %)', v_msg, v_det;
    end if;
    v_ok := v_ok + 1;
  end;
  begin
    perform set_config('request.jwt.claim.sub', '', true); execute 'set local role service_role';
    perform crm.registrar_salud_celular_servicio(k2, latido_ok);
    raise exception 'ORACULO D3: el latido no comparte el límite de la ingesta';
  exception when sqlstate 'P0429' then v_ok := v_ok + 1; end;
  -- Otro celular no se frena por el primero.
  perform set_config('request.jwt.claim.sub', '', true); execute 'set local role service_role';
  perform crm.ingerir_llamada_celular_servicio(k1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-dk1',
    'numero', sin_lead, 'direccion', 'saliente'));
  execute 'set local role none';
  -- Pasa el minuto: vuelve a contar desde cero, el día sigue.
  update private.celulares_estado set minuto_desde = minuto_desde - interval '1 minute' where asignacion_id = v_c2;
  perform set_config('request.jwt.claim.sub', '', true); execute 'set local role service_role';
  perform crm.ingerir_llamada_celular_servicio(k2, jsonb_build_object('v', 1, 'evento_origen_id', 'o-d6',
    'numero', sin_lead, 'direccion', 'saliente'));
  perform crm.ingerir_llamada_celular_servicio(k2, jsonb_build_object('v', 1, 'evento_origen_id', 'o-d7',
    'numero', sin_lead, 'direccion', 'saliente'));
  execute 'set local role none';
  if not exists (select 1 from private.celulares_estado s
                 where s.asignacion_id = v_c2 and s.envios_minuto = 2 and s.envios_dia = 6) then
    raise exception 'ORACULO D4: al pasar el minuto el contador no volvió a cero o el día no siguió contando';
  end if;
  begin
    perform set_config('request.jwt.claim.sub', '', true); execute 'set local role service_role';
    perform crm.ingerir_llamada_celular_servicio(k2, jsonb_build_object('v', 1,
      'evento_origen_id', 'o-d8', 'numero', sin_lead, 'direccion', 'saliente'));
    raise exception 'ORACULO D5: el límite diario no frenó';
  exception when sqlstate 'P0429' then
    get stacked diagnostics v_msg = message_text, v_det = pg_exception_detail;
    if v_msg not like '%límite de envíos del día%'
       or coalesce(substring(v_det from '^reintentar_en_seg=([0-9]+)$')::integer, 0) not between 1 and 86400 then
      raise exception 'ORACULO D6: el freno diario no dice cuánto esperar (% / %)', v_msg, v_det;
    end if;
    v_ok := v_ok + 1;
  end;
  -- Pasa el día: vuelve a contar desde cero.
  update private.celulares_estado set dia = dia - 1 where asignacion_id = v_c2;
  perform set_config('request.jwt.claim.sub', '', true); execute 'set local role service_role';
  perform crm.ingerir_llamada_celular_servicio(k2, jsonb_build_object('v', 1, 'evento_origen_id', 'o-d9',
    'numero', sin_lead, 'direccion', 'saliente'));
  execute 'set local role none';
  if (select s.envios_dia from private.celulares_estado s where s.asignacion_id = v_c2) <> 1 then
    raise exception 'ORACULO D7: al pasar el día el contador no volvió a cero';
  end if;
  begin
    update crm.llamadas_celular_politica set limite_envios_minuto = 10, limite_envios_dia = 6;
    raise exception 'ORACULO D8: un límite por minuto mayor que el diario se aceptó';
  exception when check_violation then v_ok := v_ok + 1; end;
  begin
    update crm.llamadas_celular_politica set limite_envios_minuto = 0;
    raise exception 'ORACULO D9: un límite de cero se aceptó';
  exception when check_violation then v_ok := v_ok + 1; end;
  update crm.llamadas_celular_politica set limite_envios_minuto = 30, limite_envios_dia = 600;

  -- ═════ E. Salud: latido v1 que cuenta como envío; todo lo demás se rechaza ═════
  select s.envios_dia into v_n from private.celulares_estado s where s.asignacion_id = v_c1;
  perform set_config('request.jwt.claim.sub', '', true); execute 'set local role service_role';
  v_r := crm.registrar_salud_celular_servicio(k1, latido_ok);
  execute 'set local role none';
  if not coalesce((v_r ->> 'registrado')::boolean, false)
     or not exists (select 1 from private.celulares_estado s
                    where s.asignacion_id = v_c1 and s.version_macro = 'macro 1.0' and s.eventos_en_cola = 2
                      and s.ultimo_latido_en is not null and s.latido_celular_en = timestamptz '2026-10-01 12:00Z'
                      and s.envios_dia = v_n + 1) then
    raise exception 'ORACULO E1: el latido no quedó guardado o no contó como envío';
  end if;
  foreach v_malo in array array[
    latido_ok || '{"bateria": 80}'::jsonb,
    jsonb_set(latido_ok, '{v}', '2'),
    jsonb_set(latido_ok, '{version_macro}', '"<script>"'),
    latido_ok - 'version_macro',
    latido_ok - 'en_cola',
    jsonb_set(latido_ok, '{en_cola}', '-1'),
    jsonb_set(latido_ok, '{ocurrio_en}', '"ayer"'),
    '[]'::jsonb] loop
    begin
      perform set_config('request.jwt.claim.sub', '', true); execute 'set local role service_role';
      perform crm.registrar_salud_celular_servicio(k1, v_malo);
      raise exception 'ORACULO E2: un latido inválido se aceptó (%)', v_malo;
    exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  end loop;
  begin
    perform private.celular_registrar_salud(v_c4, latido_ok);
    raise exception 'ORACULO E3: un latido sin estado del celular se dio por guardado';
  exception when object_not_in_prerequisite_state then v_ok := v_ok + 1; end;

  -- ═════ F. Bandeja paginada: por cursor, sin huecos ni repetidos, mismas filas que la de F2-c ═════
  perform set_config('request.jwt.claim.sub', '', true); execute 'set local role service_role';
  for v_i in 1..3 loop
    perform crm.ingerir_llamada_celular_servicio(k1, jsonb_build_object('v', 1,
      'evento_origen_id', 'o-f' || v_i, 'numero', '900000001', 'direccion', 'saliente'));
  end loop;
  perform crm.ingerir_llamada_celular_servicio(k1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-f4',
    'numero', '900000002', 'direccion', 'saliente'));
  perform crm.ingerir_llamada_celular_servicio(k1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-f5',
    'numero', '900000006', 'direccion', 'saliente'));
  perform crm.ingerir_llamada_celular_servicio(k1, jsonb_build_object('v', 1, 'evento_origen_id', 'o-f6',
    'numero', '900000003', 'direccion', 'saliente'));
  execute 'set local role none';

  perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
  v_r2 := crm.llamadas_celular_pendientes_fn(200);
  loop
    v_r := crm.llamadas_celular_bandeja_fn(2, v_antes_ts, v_antes_id);
    v_paginas := v_paginas + 1;
    v_filas := v_filas || (v_r -> 'filas');
    exit when v_r -> 'siguiente' = 'null'::jsonb or v_paginas > 20;
    if jsonb_array_length(v_r -> 'filas') <> 2 then
      raise exception 'ORACULO F1: una página con siguiente no vino llena (%)', v_r;
    end if;
    v_antes_ts := (v_r -> 'siguiente' ->> 'recibido_en')::timestamptz;
    v_antes_id := (v_r -> 'siguiente' ->> 'evento_id')::uuid;
  end loop;
  execute 'set local role none';
  if jsonb_array_length(v_r2) < 5 or v_paginas < 3 then
    raise exception 'ORACULO F2: el caso no ejercita la paginación (% llamadas, % páginas)', jsonb_array_length(v_r2), v_paginas;
  end if;
  if (select count(*) from jsonb_array_elements(v_filas)) <> (select count(distinct x ->> 'evento_id') from jsonb_array_elements(v_filas) x) then
    raise exception 'ORACULO F3: la bandeja repitió llamadas entre páginas';
  end if;
  if exists (select 1 from jsonb_array_elements(v_r2) p
             where not exists (select 1 from jsonb_array_elements(v_filas) b where b = p))
     or jsonb_array_length(v_filas) <> jsonb_array_length(v_r2) then
    raise exception 'ORACULO F4: las páginas no suman exactamente la bandeja de F2-c';
  end if;
  if exists (select 1 from jsonb_array_elements(v_filas) b where b ->> 'lead_id' = '00000000-0000-0000-0000-0000000000c3') then
    raise exception 'ORACULO F5: el analista ve en su bandeja la llamada a un lead ajeno';
  end if;
  perform set_config('request.jwt.claim.sub', a3::text, true); execute 'set local role authenticated';
  v_r := crm.llamadas_celular_bandeja_fn(200);
  execute 'set local role none';
  if exists (select 1 from jsonb_array_elements(v_r -> 'filas') b where b ->> 'analista_id' = a1::text) then
    raise exception 'ORACULO F6: otro equipo ve las llamadas de este analista';
  end if;
  perform set_config('request.jwt.claim.sub', a2::text, true); execute 'set local role authenticated';
  v_r := crm.llamadas_celular_bandeja_fn(200);
  execute 'set local role none';
  if not exists (select 1 from jsonb_array_elements(v_r -> 'filas') b
                 where b ->> 'lead_id' = '00000000-0000-0000-0000-0000000000c3' and b ->> 'analista_id' = a1::text) then
    raise exception 'ORACULO F7: el dueño del lead no ve la llamada que otro analista le hizo';
  end if;
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.llamadas_celular_bandeja_fn(10, now(), null);
    raise exception 'ORACULO F8: un cursor a medias se aceptó';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.llamadas_celular_bandeja_fn(201);
    raise exception 'ORACULO F9: un límite de 201 se aceptó';
  exception when invalid_parameter_value then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', '', true); execute 'set local role anon';
    perform crm.llamadas_celular_bandeja_fn(10);
    raise exception 'ORACULO F10: anon leyó la bandeja';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;

  -- ═════ G. Salud de los celulares: gerencia todos los vigentes, supervisión su equipo ═════
  perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
  v_r := crm.celulares_salud_fn();
  execute 'set local role none';
  if (select count(*) from jsonb_array_elements(v_r)) <> 4
     or exists (select 1 from jsonb_array_elements(v_r) x where (x ->> 'asignacion_id')::uuid = v_c3)
     or not exists (select 1 from jsonb_array_elements(v_r) x
                    where (x ->> 'asignacion_id')::uuid = v_c1 and x ->> 'version_macro' = 'macro 1.0'
                      and (x ->> 'envios_hoy')::integer > 0) then
    raise exception 'ORACULO G1: gerencia no ve exactamente los 4 celulares vigentes con su salud (%)', v_r;
  end if;
  if v_r::text ~ '[0-9a-f]{64}' then
    raise exception 'ORACULO G2: la salud de los celulares expone un hash de credencial';
  end if;
  perform set_config('request.jwt.claim.sub', b1::text, true); execute 'set local role authenticated';
  v_r := crm.celulares_salud_fn();
  execute 'set local role none';
  if exists (select 1 from jsonb_array_elements(v_r) x where (x ->> 'asignacion_id')::uuid = v_c2)
     or (select count(*) from jsonb_array_elements(v_r) x where (x ->> 'asignacion_id')::uuid in (v_c1, v_c4, v_c6)) <> 3 then
    raise exception 'ORACULO G3: supervisión no ve exactamente los celulares de su equipo (%)', v_r;
  end if;
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.celulares_salud_fn();
    raise exception 'ORACULO G4: un analista leyó la salud de los celulares';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;

  -- ═════ H. La tabla técnica: cerrada a la API y con su candado ═════
  begin
    perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
    perform 1 from private.celulares_estado;
    raise exception 'ORACULO H1: authenticated leyó la tabla técnica directamente';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    perform set_config('request.jwt.claim.sub', '', true); execute 'set local role service_role';
    perform 1 from private.celulares_estado;
    raise exception 'ORACULO H2: service_role leyó la tabla técnica directamente';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    delete from private.celulares_estado where asignacion_id = v_c1;
    raise exception 'ORACULO H3: el estado de un celular se borró (reinicia el límite)';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    update private.celulares_estado set asignacion_id = v_c4 where asignacion_id = v_c1;
    raise exception 'ORACULO H4: el estado de un celular cambió de asignación';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;

  raise notice 'ORACULO F3-a OK: % defensas mordieron; servicio, autorización uniforme, respuesta mínima, límite compartido, salud, bandeja paginada y tabla técnica comprobados', v_ok;
end;
$oraculo$;

rollback;

-- ORÁCULO de `crm.cerrar_reunion_v3` — se ejecuta CONTRA PRODUCCIÓN y no
-- escribe nada.
--
-- El escenario se levanta contra la FORMA real del esquema (no contra un
-- fixture inventado: los CHECK, los triggers y la jerarquía de equipo son los
-- vivos) y el bloque termina SIEMPRE en `raise`, así que Postgres deshace el
-- lead sintético, las tareas, las actividades, los recibos, los episodios SLA
-- y hasta las funciones recién creadas. Receta del vault: «Probar en
-- producción sin escribir nada».
--
-- Este archivo NO se ejecuta a mano: `armar-ensayo.mjs` lo pega DETRÁS de la
-- migración real (a la que le quita su `begin;`/`commit;`) dentro de una única
-- transacción que termina en `rollback`. Así el oráculo prueba exactamente el
-- cuerpo que se va a publicar —preflight y gates incluidos— y no una copia que
-- se desactualiza sola.
do $ensayo$
declare
  v_vendedor uuid;
  v_ajeno uuid;
  v_supervisor uuid;
  v_supervisor_ajeno uuid;
  v_gerencia uuid;
  v_sin_rol uuid;
  v_lead uuid;
  v_tarea uuid;
  v_tarea2 uuid;
  v_tarea3 uuid;
  v_tarea4 uuid;
  v_tarea5 uuid;
  v_tarea6 uuid;
  v_tarea7 uuid;
  v_lead_terminal uuid;
  v_op uuid;
  v_res jsonb;
  v_informe text := '';
  v_etapa text;
  v_monto numeric;
  v_moneda text;
  v_estado text;
  v_n integer;
  v_txt text;
  v_sqlstate text;
  v_fallos integer := 0;
begin
  -- ── Actores reales ────────────────────────────────────────────────────────
  -- Un vendedor activo cualquiera, y otro de OTRO supervisor para el mutante de
  -- ámbito. Se toman de producción porque `private.rol_crm` y
  -- `private.vendedor_ids_visibles` leen la jerarquía viva: un actor inventado
  -- no probaría la autoridad de verdad.
  select e.perfil_id into v_vendedor
  from crm.equipo e join public.perfiles p on p.id = e.perfil_id
  where e.activo and p.activo and e.rol_crm = 'vendedor'
  order by e.perfil_id limit 1;
  if v_vendedor is null then
    raise exception 'ENSAYO ABORTADO: no hay vendedor activo en produccion';
  end if;

  select e.perfil_id into v_ajeno
  from crm.equipo e join public.perfiles p on p.id = e.perfil_id
  where e.activo and p.activo and e.rol_crm = 'vendedor'
    and e.perfil_id <> v_vendedor
    and coalesce(e.supervisor_id::text,'') <> coalesce(
      (select e2.supervisor_id::text from crm.equipo e2 where e2.perfil_id = v_vendedor), '')
  order by e.perfil_id limit 1;

  select e.supervisor_id into v_supervisor from crm.equipo e where e.perfil_id = v_vendedor;
  select e.perfil_id into v_supervisor_ajeno
  from crm.equipo e join public.perfiles p on p.id = e.perfil_id
  where e.activo and p.activo and e.rol_crm = 'supervisor'
    and e.perfil_id is distinct from v_supervisor
  order by e.perfil_id limit 1;
  select e.perfil_id into v_gerencia
  from crm.equipo e join public.perfiles p on p.id = e.perfil_id
  where e.activo and p.activo and e.rol_crm = 'gerencia'
  order by e.perfil_id limit 1;
  -- Un rol CRM que `sla_gestion_permitida` NO admite (solo vendedor, supervisor
  -- y gerencia). Coordinador y directorio sí pasan la RLS de lectura.
  select e.perfil_id into v_sin_rol
  from crm.equipo e join public.perfiles p on p.id = e.perfil_id
  where e.activo and p.activo and e.rol_crm in ('coordinador', 'directorio')
  order by e.perfil_id limit 1;

  -- Los actores son OBLIGATORIOS: sin ellos los casos de denegación no se
  -- prueban y el ensayo saldría verde sin haber mirado la autoridad. (El aviso
  -- condicional que había antes era justo esa trampa.)
  if v_ajeno is null or v_supervisor is null or v_supervisor_ajeno is null
     or v_gerencia is null or v_sin_rol is null then
    raise exception 'ENSAYO ABORTADO: faltan actores para probar la autoridad (ajeno=%, sup=%, sup_ajeno=%, ger=%, sin_rol=%)',
      v_ajeno, v_supervisor, v_supervisor_ajeno, v_gerencia, v_sin_rol;
  end if;

  -- ── Escenario: un lead YA CONTACTADO con su cita agendada ────────────────
  -- Es el caso que hoy no movía nada: el avance automático solo sube de `nuevo`
  -- a `contactado`, así que este lead se quedaba clavado por más entrevistas
  -- que tuviera.
  insert into crm.leads (nombre_completo, telefono, etapa, vendedor_id,
                         monto_estimado, moneda, origen, creado_por)
  -- Teléfono aleatorio con el formato que exige el CHECK: el índice único de
  -- teléfono vivo no puede chocar con un lead real (y si chocara, el ensayo
  -- fallaría en voz alta y no dejaría rastro: todo esto se deshace).
  values ('ENSAYO Entrevista Automatica',
          '+519' || lpad((floor(random() * 100000000))::bigint::text, 8, '0'),
          'contactado', v_vendedor,
          1000.00, 'PEN', 'otro', v_vendedor)
  returning id into v_lead;

  insert into crm.tareas (lead_id, tipo, titulo, vence_en, vendedor_id,
                          modalidad_reunion, creado_por)
  values (v_lead, 'reunion', 'Cita de ensayo', now() + interval '1 hour', v_vendedor,
          'sin_clasificar', v_vendedor)
  returning id into v_tarea;

  -- El actor de aquí en adelante es el vendedor dueño del lead.
  perform set_config('request.jwt.claim.sub', v_vendedor::text, true);

  -- ── 1. ASISTIÓ ⇒ entrevista registrada, con su capital ───────────────────
  v_op := gen_random_uuid();
  begin
    v_res := crm.cerrar_reunion_v3(v_op, v_tarea, 'completada', 'propuesta',
               null, 'Vino a la oficina', null, 57500.00, 'USD');
  exception when others then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 1-previo: la llamada esperada revento (%s)\n', sqlerrm);
    v_res := '{}'::jsonb;
  end;

  select l.etapa, l.monto_estimado, l.moneda into v_etapa, v_monto, v_moneda
  from crm.leads l where l.id = v_lead;
  if v_etapa <> 'propuesta_enviada' then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 1a: etapa quedo en %s\n', v_etapa);
  end if;
  if v_monto <> 57500.00 or v_moneda <> 'USD' then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 1b: capital quedo en %s %s\n', v_monto, v_moneda);
  end if;
  if coalesce((v_res->>'entrevista_registrada')::boolean, false) is not true
     or coalesce((v_res->>'capital_asentado')::boolean, false) is not true
     or v_res->>'etapa_previa' <> 'contactado' then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 1c: respuesta %s\n', v_res::text);
  end if;

  select t.estado, t.resultado_reunion into v_estado, v_txt
  from crm.tareas t where t.id = v_tarea;
  if v_estado <> 'completada' or v_txt <> 'propuesta' then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 1d: la cita quedo en %s/%s\n', v_estado, v_txt);
  end if;

  select count(*) into v_n from crm.actividades a
  where a.lead_id = v_lead and a.tipo = 'reunion_realizada';
  if v_n <> 1 then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 1e: %s actividades reunion_realizada\n', v_n);
  end if;

  -- El avance lo ordenó el SISTEMA al registrar la asistencia: el historial no
  -- puede atribuirle al analista un cambio de etapa que él no pidió.
  select count(*) into v_n from crm.actividades a
  where a.lead_id = v_lead and a.tipo = 'cambio_etapa'
    and a.metadata->>'etapa_nueva' = 'propuesta_enviada'
    and (a.metadata->>'automatico')::boolean is true;
  if v_n <> 1 then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 1f: %s cambio_etapa automaticos a propuesta_enviada\n', v_n);
  end if;

  -- El episodio SLA de la etapa nueva se abre solo (trg_leads_02_sla_versionado).
  select count(*) into v_n from crm.lead_sla_etapas e
  where e.lead_id = v_lead and e.etapa = 'propuesta_enviada' and e.finalizado_en is null;
  if v_n <> 1 then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 1g: %s episodios SLA abiertos en la etapa nueva\n', v_n);
  end if;

  -- ── 2. IDEMPOTENCIA: el mismo p_operacion_id no duplica nada ─────────────
  begin
    v_res := crm.cerrar_reunion_v3(v_op, v_tarea, 'completada', 'propuesta',
               null, 'Vino a la oficina', null, 57500.00, 'USD');
  exception when others then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 2-previo: la llamada esperada revento (%s)\n', sqlerrm);
    v_res := '{}'::jsonb;
  end;
  select count(*) into v_n from crm.actividades a
  where a.lead_id = v_lead and a.tipo = 'reunion_realizada';
  if v_n <> 1 or coalesce((v_res->>'entrevista_registrada')::boolean, true) is not false then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 2: replay duplico (%s actividades) o mintio: %s\n', v_n, v_res::text);
  end if;

  -- ── 3. SEGUNDA ENTREVISTA de la misma persona ───────────────────────────
  -- La etapa ya no sube más, pero el capital recién propuesto SÍ es el vigente.
  insert into crm.tareas (lead_id, tipo, titulo, vence_en, vendedor_id,
                          modalidad_reunion, creado_por)
  values (v_lead, 'reunion', 'Segunda cita de ensayo', now() + interval '2 hours',
          v_vendedor, 'sin_clasificar', v_vendedor)
  returning id into v_tarea2;
  begin
    v_res := crm.cerrar_reunion_v3(gen_random_uuid(), v_tarea2, 'completada',
               'inicia_registro', null, null, null, 90000.00, 'PEN');
  exception when others then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 3-previo: la llamada esperada revento (%s)\n', sqlerrm);
    v_res := '{}'::jsonb;
  end;
  select l.etapa, l.monto_estimado, l.moneda into v_etapa, v_monto, v_moneda
  from crm.leads l where l.id = v_lead;
  if v_etapa <> 'propuesta_enviada' or v_monto <> 90000.00 or v_moneda <> 'PEN'
     or coalesce((v_res->>'entrevista_registrada')::boolean, true) is not false
     or coalesce((v_res->>'capital_asentado')::boolean, false) is not true then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 3: 2a entrevista dejo %s / %s %s / %s\n',
      v_etapa, v_monto, v_moneda, v_res::text);
  end if;

  -- ── 4. MUTANTES: cada defensa, rota a propósito ─────────────────────────
  insert into crm.tareas (lead_id, tipo, titulo, vence_en, vendedor_id,
                          modalidad_reunion, creado_por)
  values (v_lead, 'reunion', 'Cita de mutantes', now() + interval '3 hours',
          v_vendedor, 'sin_clasificar', v_vendedor)
  returning id into v_tarea3;

  -- 4a. Sin capital declarado: la cita NO se cierra (nada a medias).
  begin
    v_res := crm.cerrar_reunion_v3(gen_random_uuid(), v_tarea3, 'completada',
               'propuesta', null, null, null, null, null);
    v_fallos := v_fallos + 1;
    v_informe := v_informe || E'FALLO 4a: acepto una entrevista sin capital\n';
  exception when others then
    v_sqlstate := sqlstate;
    if v_sqlstate <> '22023' then
      v_fallos := v_fallos + 1;
      v_informe := v_informe || format(E'FALLO 4a: sqlstate %s (%s)\n', v_sqlstate, sqlerrm);
    end if;
  end;
  select t.estado into v_estado from crm.tareas t where t.id = v_tarea3;
  if v_estado <> 'pendiente' then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 4a-bis: la cita quedo en %s tras el rechazo\n', v_estado);
  end if;

  -- 4b. Capital con tres decimales: se rechaza, no se redondea.
  begin
    v_res := crm.cerrar_reunion_v3(gen_random_uuid(), v_tarea3, 'completada',
               'propuesta', null, null, null, 5000.005, 'PEN');
    v_fallos := v_fallos + 1;
    v_informe := v_informe || E'FALLO 4b: acepto un capital de tres decimales\n';
  exception when others then
    if sqlstate <> '22023' then
      v_fallos := v_fallos + 1;
      v_informe := v_informe || format(E'FALLO 4b: sqlstate %s\n', sqlstate);
    end if;
  end;
  -- La cita tiene que seguir ABIERTA: un rechazo que no rechaza se escaparía
  -- como error crudo en la prueba siguiente, no como fallo de esta.
  select t.estado into v_estado from crm.tareas t where t.id = v_tarea3;
  if v_estado <> 'pendiente' then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 4b-bis: la cita quedo en %s tras el rechazo\n', v_estado);
  end if;

  -- 4c. Capital cero o negativo.
  begin
    v_res := crm.cerrar_reunion_v3(gen_random_uuid(), v_tarea3, 'completada',
               'propuesta', null, null, null, 0, 'PEN');
    v_fallos := v_fallos + 1;
    v_informe := v_informe || E'FALLO 4c: acepto capital 0\n';
  exception when others then
    if sqlstate <> '22023' then
      v_fallos := v_fallos + 1;
      v_informe := v_informe || format(E'FALLO 4c: sqlstate %s\n', sqlstate);
    end if;
  end;
  -- La cita tiene que seguir ABIERTA: un rechazo que no rechaza se escaparía
  -- como error crudo en la prueba siguiente, no como fallo de esta.
  select t.estado into v_estado from crm.tareas t where t.id = v_tarea3;
  if v_estado <> 'pendiente' then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 4c-bis: la cita quedo en %s tras el rechazo\n', v_estado);
  end if;

  -- 4d. Moneda fuera del catálogo de la columna.
  begin
    v_res := crm.cerrar_reunion_v3(gen_random_uuid(), v_tarea3, 'completada',
               'propuesta', null, null, null, 1000.00, 'EUR');
    v_fallos := v_fallos + 1;
    v_informe := v_informe || E'FALLO 4d: acepto moneda EUR\n';
  exception when others then
    if sqlstate <> '22023' then
      v_fallos := v_fallos + 1;
      v_informe := v_informe || format(E'FALLO 4d: sqlstate %s\n', sqlstate);
    end if;
  end;
  -- La cita tiene que seguir ABIERTA: un rechazo que no rechaza se escaparía
  -- como error crudo en la prueba siguiente, no como fallo de esta.
  select t.estado into v_estado from crm.tareas t where t.id = v_tarea3;
  if v_estado <> 'pendiente' then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 4d-bis: la cita quedo en %s tras el rechazo\n', v_estado);
  end if;

  -- 4e. Un plantón no propone capital a nadie.
  begin
    v_res := crm.cerrar_reunion_v3(gen_random_uuid(), v_tarea3, 'no_show',
               null, null, null, null, 1000.00, 'PEN');
    v_fallos := v_fallos + 1;
    v_informe := v_informe || E'FALLO 4e: acepto capital en un no_show\n';
  exception when others then
    if sqlstate <> '22023' then
      v_fallos := v_fallos + 1;
      v_informe := v_informe || format(E'FALLO 4e: sqlstate %s\n', sqlstate);
    end if;
  end;
  -- La cita tiene que seguir ABIERTA: un rechazo que no rechaza se escaparía
  -- como error crudo en la prueba siguiente, no como fallo de esta.
  select t.estado into v_estado from crm.tareas t where t.id = v_tarea3;
  if v_estado <> 'pendiente' then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 4e-bis: la cita quedo en %s tras el rechazo\n', v_estado);
  end if;

  -- 4f. ÁMBITO: un vendedor de otro equipo no registra entrevistas ajenas.
  perform set_config('request.jwt.claim.sub', v_ajeno::text, true);
  begin
    v_res := crm.cerrar_reunion_v3(gen_random_uuid(), v_tarea3, 'completada',
               'propuesta', null, null, null, 1000.00, 'PEN');
    v_fallos := v_fallos + 1;
    v_informe := v_informe || E'FALLO 4f: un vendedor ajeno cerro la cita\n';
  exception when others then
    if sqlstate not in ('42501','P0001') then
      v_fallos := v_fallos + 1;
      v_informe := v_informe || format(E'FALLO 4f: sqlstate %s (%s)\n', sqlstate, sqlerrm);
    end if;
  end;
  perform set_config('request.jwt.claim.sub', v_vendedor::text, true);
  select t.estado into v_estado from crm.tareas t where t.id = v_tarea3;
  if v_estado <> 'pendiente' then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 4f-bis: la cita quedo en %s tras el rechazo\n', v_estado);
  end if;

  -- 4g. Un rol sin autoridad de gestión (coordinador/directorio) tampoco.
  perform set_config('request.jwt.claim.sub', v_sin_rol::text, true);
  begin
    v_res := crm.cerrar_reunion_v3(gen_random_uuid(), v_tarea3, 'completada',
               'propuesta', null, null, null, 1000.00, 'PEN');
    v_fallos := v_fallos + 1;
    v_informe := v_informe || E'FALLO 4g: un rol sin gestion cerro la cita\n';
  exception when others then
    if sqlstate not in ('42501','P0001') then
      v_fallos := v_fallos + 1;
      v_informe := v_informe || format(E'FALLO 4g: sqlstate %s (%s)\n', sqlstate, sqlerrm);
    end if;
  end;
  perform set_config('request.jwt.claim.sub', v_vendedor::text, true);

  -- 4h. El supervisor de OTRO equipo tampoco.
  perform set_config('request.jwt.claim.sub', v_supervisor_ajeno::text, true);
  begin
    v_res := crm.cerrar_reunion_v3(gen_random_uuid(), v_tarea3, 'completada',
               'propuesta', null, null, null, 1000.00, 'PEN');
    v_fallos := v_fallos + 1;
    v_informe := v_informe || E'FALLO 4h: un supervisor ajeno cerro la cita\n';
  exception when others then
    if sqlstate not in ('42501','P0001') then
      v_fallos := v_fallos + 1;
      v_informe := v_informe || format(E'FALLO 4h: sqlstate %s (%s)\n', sqlstate, sqlerrm);
    end if;
  end;
  perform set_config('request.jwt.claim.sub', v_vendedor::text, true);

  -- ── 5. NO ASISTIÓ: la etapa y el capital no se mueven ───────────────────
  -- Envuelto a propósito: si alguno de los mutantes de arriba hubiera cerrado
  -- esta cita, aquí saltaría un error crudo que reventaría el ensayo entero y
  -- se perdería el informe. Un imprevisto es un FALLO, no un abort.
  begin
    v_res := crm.cerrar_reunion_v3(gen_random_uuid(), v_tarea3, 'no_show',
               null, null, 'No vino', null, null, null);
  exception when others then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 5-previo: el planton no se pudo registrar (%s)\n', sqlerrm);
    v_res := '{}'::jsonb;
  end;
  select l.etapa, l.monto_estimado, l.moneda into v_etapa, v_monto, v_moneda
  from crm.leads l where l.id = v_lead;
  if v_etapa <> 'propuesta_enviada' or v_monto <> 90000.00 or v_moneda <> 'PEN'
     or v_res ? 'entrevista_registrada' then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 5: el planton movio algo (%s / %s %s / %s)\n',
      v_etapa, v_monto, v_moneda, v_res::text);
  end if;

  -- ── 6. PERMITIDOS: supervisor del equipo y gerencia ────────────────────
  -- La mitad negativa no basta: si el candado fuera demasiado estrecho, el
  -- supervisor no podría cerrar las citas de su propio equipo.
  insert into crm.tareas (lead_id, tipo, titulo, vence_en, vendedor_id,
                          modalidad_reunion, creado_por)
  values (v_lead, 'reunion', 'Cita del supervisor', now() + interval '4 hours',
          v_vendedor, 'sin_clasificar', v_vendedor)
  returning id into v_tarea4;
  perform set_config('request.jwt.claim.sub', v_supervisor::text, true);
  begin
    v_res := crm.cerrar_reunion_v3(gen_random_uuid(), v_tarea4, 'completada',
               'interesado', null, null, null, 12000.00, 'PEN');
    if coalesce((v_res->>'capital_asentado')::boolean, false) is not true then
      v_fallos := v_fallos + 1;
      v_informe := v_informe || format(E'FALLO 6a: el supervisor cerro pero sin asentar capital: %s\n', v_res::text);
    end if;
  exception when others then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 6a: el supervisor de su propio equipo fue rechazado (%s)\n', sqlerrm);
  end;

  -- El JWT vuelve al dueño para sembrar: `trg_gestion_lead_serializada` exige
  -- que `creado_por` sea el usuario autenticado.
  perform set_config('request.jwt.claim.sub', v_vendedor::text, true);
  insert into crm.tareas (lead_id, tipo, titulo, vence_en, vendedor_id,
                          modalidad_reunion, creado_por)
  values (v_lead, 'reunion', 'Cita de gerencia', now() + interval '5 hours',
          v_vendedor, 'sin_clasificar', v_vendedor)
  returning id into v_tarea5;
  perform set_config('request.jwt.claim.sub', v_gerencia::text, true);
  begin
    v_res := crm.cerrar_reunion_v3(gen_random_uuid(), v_tarea5, 'completada',
               'interesado', null, null, null, 13000.00, 'PEN');
    if coalesce((v_res->>'capital_asentado')::boolean, false) is not true then
      v_fallos := v_fallos + 1;
      v_informe := v_informe || format(E'FALLO 6b: gerencia cerro pero sin asentar capital: %s\n', v_res::text);
    end if;
  exception when others then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 6b: gerencia fue rechazada (%s)\n', sqlerrm);
  end;
  perform set_config('request.jwt.claim.sub', v_vendedor::text, true);

  -- ── 7. «NO INTERESADO»: entrevista SÍ, capital NO ──────────────────────
  -- A quien dijo que no nadie le propuso capital: la cifra del lead se queda
  -- como estaba y no se le pide al analista que la invente.
  select l.monto_estimado, l.moneda into v_monto, v_moneda
  from crm.leads l where l.id = v_lead;
  insert into crm.tareas (lead_id, tipo, titulo, vence_en, vendedor_id,
                          modalidad_reunion, creado_por)
  values (v_lead, 'reunion', 'Cita sin interes', now() + interval '6 hours',
          v_vendedor, 'sin_clasificar', v_vendedor)
  returning id into v_tarea6;
  begin
    v_res := crm.cerrar_reunion_v3(gen_random_uuid(), v_tarea6, 'completada',
               'no_interesado', null, null, null, null, null);
  exception when others then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 7-previo: un «no interesado» sin capital fue rechazado (%s)\n', sqlerrm);
    v_res := '{}'::jsonb;
  end;
  if coalesce((v_res->>'capital_asentado')::boolean, true) is not false then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 7a: dijo haber asentado capital: %s\n', v_res::text);
  end if;
  if (select l.monto_estimado from crm.leads l where l.id = v_lead) <> v_monto
     or (select l.moneda from crm.leads l where l.id = v_lead) <> v_moneda then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || E'FALLO 7b: un «no interesado» movio el capital del lead\n';
  end if;
  if (select t.estado from crm.tareas t where t.id = v_tarea6) <> 'completada' then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || E'FALLO 7c: la cita de «no interesado» no se cerro\n';
  end if;

  -- 7d. Y con capital se rechaza: nadie propuso nada.
  insert into crm.tareas (lead_id, tipo, titulo, vence_en, vendedor_id,
                          modalidad_reunion, creado_por)
  values (v_lead, 'reunion', 'Cita sin interes con cifra', now() + interval '7 hours',
          v_vendedor, 'sin_clasificar', v_vendedor)
  returning id into v_tarea7;
  begin
    v_res := crm.cerrar_reunion_v3(gen_random_uuid(), v_tarea7, 'completada',
               'no_interesado', null, null, null, 1000.00, 'PEN');
    v_fallos := v_fallos + 1;
    v_informe := v_informe || E'FALLO 7d: acepto capital con «no interesado»\n';
  exception when others then
    if sqlstate <> '22023' then
      v_fallos := v_fallos + 1;
      v_informe := v_informe || format(E'FALLO 7d: sqlstate %s\n', sqlstate);
    end if;
  end;

  -- ── 8. REPLAY con OTRO capital: no reescribe la cifra ──────────────────
  -- El recibo del comando guarda el payload del cierre, no el capital. Sin la
  -- guarda de replay, repetir la operación con otra cifra la escribía mientras
  -- la respuesta devuelta era la vieja.
  select l.monto_estimado into v_monto from crm.leads l where l.id = v_lead;
  begin
    v_res := crm.cerrar_reunion_v3(v_op, v_tarea, 'completada', 'propuesta',
               null, 'Vino a la oficina', null, 111111.00, 'PEN');
  exception when others then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 8-previo: la llamada esperada revento (%s)\n', sqlerrm);
    v_res := '{}'::jsonb;
  end;
  if (select l.monto_estimado from crm.leads l where l.id = v_lead) <> v_monto then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || E'FALLO 8: un replay reescribio el capital del lead\n';
  end if;
  if coalesce((v_res->>'capital_asentado')::boolean, true) is not false then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 8b: el replay dice haber escrito: %s\n', v_res::text);
  end if;

  -- ── 9. NÚCLEO sobre un lead que ya no admite entrevista ────────────────
  -- El writer de agenda no mira la etapa del lead antes de cerrar su cita, así
  -- que el núcleo tiene que negarse en voz alta en vez de devolver «ok» con el
  -- capital perdido. Se llama al núcleo directo porque por la puerta este caso
  -- no es alcanzable hoy (el lead terminal ya no tiene citas pendientes).
  -- Ningún lead puede NACER terminal (`trg_leads_disponibilidad_atomica`): se
  -- crea operativo y se descarta después, como en la vida real.
  insert into crm.leads (nombre_completo, telefono, etapa,
                         vendedor_id, monto_estimado, moneda, origen, creado_por)
  values ('ENSAYO Entrevista Terminal',
          '+519' || lpad((floor(random() * 100000000))::bigint::text, 8, '0'),
          'contactado', v_vendedor, 1000.00, 'PEN', 'otro', v_vendedor)
  returning id into v_lead_terminal;
  update crm.leads set etapa = 'descartado', motivo_descarte = 'sin_interes'
   where id = v_lead_terminal;
  begin
    v_res := private.entrevista_registrar(v_lead_terminal, v_vendedor, 5000.00, 'PEN');
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 9: registro una entrevista sobre un lead descartado: %s\n', v_res::text);
  exception when others then
    if sqlstate not in ('P0409','42501') then
      v_fallos := v_fallos + 1;
      v_informe := v_informe || format(E'FALLO 9: sqlstate %s (%s)\n', sqlstate, sqlerrm);
    end if;
  end;

  -- ── 10. Las puertas y sus permisos ─────────────────────────────────────
  if not has_function_privilege('authenticated',
       'crm.cerrar_reunion_v3(uuid,uuid,text,text,text,text,jsonb,numeric,text)'::regprocedure, 'EXECUTE') then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || E'FALLO 10a: authenticated no puede llamar a la puerta\n';
  end if;
  foreach v_txt in array array['anon', 'service_role'] loop
    if has_function_privilege(v_txt,
         'crm.cerrar_reunion_v3(uuid,uuid,text,text,text,text,jsonb,numeric,text)'::regprocedure, 'EXECUTE') then
      v_fallos := v_fallos + 1;
      v_informe := v_informe || format(E'FALLO 10b: %s puede llamar a la puerta\n', v_txt);
    end if;
  end loop;
  foreach v_txt in array array['anon', 'authenticated', 'service_role'] loop
    if has_function_privilege(v_txt,
         'private.entrevista_registrar(uuid,uuid,numeric,text)'::regprocedure, 'EXECUTE') then
      v_fallos := v_fallos + 1;
      v_informe := v_informe || format(E'FALLO 10c: %s puede llamar al NUCLEO\n', v_txt);
    end if;
  end loop;

  -- ── 11. El gate del cambio ──────────────────────────────────────────────
  v_informe := v_informe || format(E'gate: %s\n', private.assert_entrevista_al_asistir());

  -- ── Veredicto, y rollback SIEMPRE ───────────────────────────────────────
  raise exception E'ENSAYO %:\n%(rollback a proposito — produccion intacta)',
    case when v_fallos = 0 then 'VERDE — 0 fallos' else format('ROJO — %s fallo(s)', v_fallos) end,
    v_informe;
end;
$ensayo$;

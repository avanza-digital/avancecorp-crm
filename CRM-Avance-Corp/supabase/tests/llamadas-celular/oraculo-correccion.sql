-- Oráculo de la QUINTA migración (20261005143843, corrección de F2 + F3) sobre el banco REDUCIDO de
-- supabase/tests/llamadas-celular/base.sql. Se corre como dueño después de las cuatro y la quinta; todo en una
-- transacción que termina en ROLLBACK. Cubre la lista «El oráculo nuevo comprueba» de CORRECCION-PLAN-CORTO.md:
-- sin pistas, bolsa, reutilizable, propios terminales, id, purga, cupo, identidad, lead borrado, entrantes,
-- fecha estricta y salud sin envíos. Las carreras con dos sesiones van en la pasada de concurrencia del guion.
-- Actores simulados como en Supabase: rol authenticated / service_role + request.jwt.claim.sub.
-- Un SET LOCAL hecho dentro de un bloque con EXCEPTION se deshace si el bloque falla: los casos que deben fallar
-- llaman a los ayudantes DENTRO de su bloque.
-- Equipo del banco: b1 supervisa a a1 y a2; b2 supervisa a a3; g1 es gerencia.
-- No sustituye el gate test-rls.mjs contra un banco con el esquema de producción.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- ── Ayudantes (temporales: se van con el ROLLBACK) ──────────────────────────────────────────
create function pg_temp.ev(p_id text, p_numero text, p_extra jsonb default '{}'::jsonb)
returns jsonb language sql immutable as $$
  select jsonb_build_object('v', 1, 'evento_origen_id', p_id, 'numero', p_numero, 'direccion', 'saliente') || p_extra
$$;
create function pg_temp.enviar(p_clave text, p_evento jsonb)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role service_role';
  v := crm.ingerir_llamada_celular_servicio(p_clave, p_evento);
  execute 'set local role none';
  return v;
end $$;
create function pg_temp.latir(p_clave text, p_latido jsonb)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role service_role';
  v := crm.registrar_salud_celular_servicio(p_clave, p_latido);
  execute 'set local role none';
  return v;
end $$;
create function pg_temp.bandeja(p_actor uuid)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_actor::text, true);
  execute 'set local role authenticated';
  v := crm.llamadas_celular_bandeja_fn(200) -> 'filas';
  execute 'set local role none';
  perform set_config('request.jwt.claim.sub', '', true);
  return v;
end $$;
create function pg_temp.ve(p_actor uuid, p_evento uuid)
returns boolean language sql as $$
  select exists (select 1 from jsonb_array_elements(pg_temp.bandeja(p_actor)) x where (x ->> 'evento_id')::uuid = p_evento)
$$;
create function pg_temp.como(p_actor uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_actor::text, true);
  execute 'set local role authenticated';
end $$;
create function pg_temp.yo()
returns void language plpgsql as $$
begin
  execute 'set local role none';
  perform set_config('request.jwt.claim.sub', '', true);
end $$;
create function pg_temp.evento(p_id text)
returns crm.llamadas_celular_eventos language sql as $$
  select * from crm.llamadas_celular_eventos e where e.evento_origen_id = p_id
$$;

do $oraculo$
declare
  a1 constant uuid := '00000000-0000-0000-0000-0000000000a1';
  a2 constant uuid := '00000000-0000-0000-0000-0000000000a2';
  a3 constant uuid := '00000000-0000-0000-0000-0000000000a3';
  b1 constant uuid := '00000000-0000-0000-0000-0000000000b1';
  g1 constant uuid := '00000000-0000-0000-0000-0000000000f1';
  c1 constant uuid := '00000000-0000-0000-0000-0000000000c1';
  c2 constant uuid := '00000000-0000-0000-0000-0000000000c2';
  c3 constant uuid := '00000000-0000-0000-0000-0000000000c3';
  c4 constant uuid := '00000000-0000-0000-0000-0000000000c4';
  c5 constant uuid := '00000000-0000-0000-0000-0000000000c5';
  c6 constant uuid := '00000000-0000-0000-0000-0000000000c6';
  c7 constant uuid := '00000000-0000-0000-0000-0000000000c7';
  cb constant uuid := '00000000-0000-0000-0000-0000000000d1';   -- en bolsa
  cr constant uuid := '00000000-0000-0000-0000-0000000000d2';   -- descartado reutilizable (0 días, hace 2 días)
  ce constant uuid := '00000000-0000-0000-0000-0000000000d3';   -- descartado en enfriamiento (30 días, hace 5)
  cr2 constant uuid := '00000000-0000-0000-0000-0000000000d4';  -- descartado reutilizable (30 días, hace 31)
  cr0 constant uuid := '00000000-0000-0000-0000-0000000000d5';  -- descartado en carencia (0 días, hace 2 h)
  cv1 constant uuid := '00000000-0000-0000-0000-0000000000d6';  -- dos ajenos con el mismo número
  cv2 constant uuid := '00000000-0000-0000-0000-0000000000d7';
  aceptado constant jsonb := '{"resultado": "aceptado"}';
  t0 bigint := floor(extract(epoch from now()))::bigint - 50000;  -- ~14 h atrás: dentro de la ventana
  v_c1 uuid; v_c2 uuid; v_c4 uuid; v_c1b uuid; v_c1c uuid;
  k1 text; k2 text; k4 text; k1b text; k1c text;
  v_r jsonb; v_r2 jsonb; v_salud jsonb; v_salud2 jsonb;
  v_ev crm.llamadas_celular_eventos%rowtype;
  v_n integer; v_n2 integer; v_dia date; v_dia2 date;
  v_act uuid; v_act2 uuid; v_ok integer := 0;
  v_msg text; v_det text; v_t timestamptz; v_id_ignorado text;
  v_e1 uuid; v_e2 uuid; v_e3 uuid; v_e4 uuid; v_e5 uuid; v_e6 uuid; v_e7 uuid;
begin
  -- ═════ Preparación ═════
  -- El cupo de 30 por minuto lo agotarían las pruebas: se sube aquí y la sección G lo prueba con valores fijados.
  update crm.llamadas_celular_politica set limite_envios_minuto = 600, limite_envios_dia = 20000;
  perform pg_temp.como(g1);
  v_r := crm.asignar_celular('C1', a1); v_c1 := (v_r ->> 'asignacion_id')::uuid; k1 := v_r ->> 'credencial';
  v_r := crm.asignar_celular('C2', a3); v_c2 := (v_r ->> 'asignacion_id')::uuid; k2 := v_r ->> 'credencial';
  v_r := crm.asignar_celular('C4', b1); v_c4 := (v_r ->> 'asignacion_id')::uuid; k4 := v_r ->> 'credencial';
  perform pg_temp.yo();
  insert into crm.leads (id, nombre_completo, telefono, etapa, vendedor_id, asignado_supervisor_id,
                         motivo_descarte, descartado_en) values
    (cb, 'Lead en Bolsa', '+51900000010', 'nuevo', null, null, null, null),
    (cr, 'Descartado Reutilizable', '+51900000011', 'descartado', a3, null, 'pide_credito', now() - interval '2 days'),
    (ce, 'Descartado en Enfriamiento', '+51900000012', 'descartado', a3, null, 'sin_interes', now() - interval '5 days'),
    (cr2, 'Reutilizable de 30 Días', '+51900000013', 'descartado', a2, null, 'sin_interes', now() - interval '31 days'),
    (cr0, 'Descartado en Carencia', '+51900000016', 'descartado', a3, null, 'pide_credito', now() - interval '2 hours'),
    (cv1, 'Ajeno Uno', '+51900000015', 'nuevo', a3, null, null, null),
    (cv2, 'Ajeno Dos', '+51900000017', 'nuevo', a2, null, null, null);
  update crm.leads set telefono_alternativo = '+51900000015' where id = cv2;

  -- ═════ A. Sin pistas: sin lead, ajeno con dueño, ajeno en enfriamiento, en carencia y varios ajenos ═════
  perform pg_temp.como(g1); v_salud := crm.celulares_salud_fn(); perform pg_temp.yo();
  v_id_ignorado := 'C1-' || (t0 + 1);
  v_r := pg_temp.enviar(k1, pg_temp.ev(v_id_ignorado, '900000099'));
  select dia, envios_dia into v_dia, v_n from private.celulares_estado where asignacion_id = v_c1;
  if v_r is distinct from aceptado then raise exception 'ORACULO A1: la respuesta a un número sin lead no es la uniforme (%)', v_r; end if;
  foreach v_msg in array array['900000008', '900000012', '900000016', '900000015'] loop
    t0 := t0 + 1;
    v_r2 := pg_temp.enviar(k1, pg_temp.ev('C1-' || (t0 + 1), v_msg));
    if v_r2::text is distinct from v_r::text then
      raise exception 'ORACULO A2: la respuesta delata el número % (% contra %)', v_msg, v_r2, v_r;
    end if;
  end loop;
  select dia, envios_dia into v_dia2, v_n2 from private.celulares_estado where asignacion_id = v_c1;
  if v_dia2 = v_dia and v_n2 <> v_n + 4 then
    raise exception 'ORACULO A3: el cupo no se gastó igual en los cinco casos (% → %)', v_n, v_n2;
  end if;
  if exists (select 1 from crm.llamadas_celular_eventos) then
    raise exception 'ORACULO A4: se guardó una llamada sin candidato';
  end if;
  if (select count(*) from private.llamadas_celular_recepciones) <> 5 then
    raise exception 'ORACULO A5: no hay una recepción por cada aviso aceptado';
  end if;
  perform pg_temp.como(g1); v_salud2 := crm.celulares_salud_fn(); perform pg_temp.yo();
  if v_salud2::text is distinct from v_salud::text then
    raise exception 'ORACULO A6: la salud cambió con avisos sin lead (% → %)', v_salud, v_salud2;
  end if;
  -- El propio responde lo mismo y sí se guarda.
  t0 := t0 + 10;
  v_r2 := pg_temp.enviar(k1, pg_temp.ev('C1-' || t0, '900000001'));
  v_ev := pg_temp.evento('C1-' || t0);
  if v_r2::text is distinct from v_r::text or v_ev.lead_id is distinct from c1
     or v_ev.atencion <> 'requiere_resultado' or v_ev.metodo_asociacion <> 'exacto' then
    raise exception 'ORACULO A7: el lead propio no respondió igual o no quedó identificado pidiendo resultado (%, %)', v_r2, row_to_json(v_ev);
  end if;
  v_e1 := v_ev.id;

  -- ═════ B. Bolsa: por revisar, quien llamó no la ve, le aparece a quien lo toma ═════
  t0 := t0 + 1;
  perform pg_temp.enviar(k1, pg_temp.ev('C1-' || t0, '900000010'));
  v_ev := pg_temp.evento('C1-' || t0);
  if v_ev.lead_id is distinct from cb or v_ev.atencion <> 'por_revisar' or v_ev.analista_id <> a1 then
    raise exception 'ORACULO B1: la llamada a un lead en bolsa no quedó identificada por revisar (%)', row_to_json(v_ev);
  end if;
  v_e2 := v_ev.id;
  if pg_temp.ve(a1, v_e2) or pg_temp.ve(b1, v_e2) then
    raise exception 'ORACULO B2: quien llamó (o su supervisor) ve la llamada a un lead en bolsa';
  end if;
  begin
    perform pg_temp.como(a1);
    perform crm.llamada_celular_detalle_fn(v_e2);
    raise exception 'ORACULO B3: quien llamó lee el detalle de la llamada a un lead en bolsa';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  if not pg_temp.ve(g1, v_e2) then raise exception 'ORACULO B4: gerencia no ve la llamada a un lead en bolsa'; end if;
  -- a2 toma el lead (en producción, crm.tomar_lead_libre): ahora la ve y la puede enlazar.
  update crm.leads set vendedor_id = a2 where id = cb;
  if not pg_temp.ve(a2, v_e2) then raise exception 'ORACULO B5: quien tomó el lead no ve su llamada'; end if;
  insert into crm.actividades (lead_id, tipo, metadata, creado_por)
  values (cb, 'llamada_realizada', '{"evento": "resultado_llamada", "resultado": "volver_a_llamar"}', a2)
  returning id into v_act;
  perform pg_temp.como(a2);
  v_r := crm.enlazar_llamada_celular(v_e2, v_act);
  perform pg_temp.yo();
  if (select atencion from crm.llamadas_celular_eventos where id = v_e2) <> 'registrado' then
    raise exception 'ORACULO B6: quien tomó el lead no pudo enlazar su llamada (%)', v_r;
  end if;

  -- ═════ C. Reutilizables: igual que la bolsa; en enfriamiento o en carencia, como sin lead (ya en A) ═════
  t0 := t0 + 1;
  perform pg_temp.enviar(k1, pg_temp.ev('C1-' || t0, '900000011'));
  v_ev := pg_temp.evento('C1-' || t0);
  if v_ev.lead_id is distinct from cr or v_ev.atencion <> 'por_revisar' then
    raise exception 'ORACULO C1: el descartado reutilizable (0 días, pasadas 24 h) no quedó por revisar (%)', row_to_json(v_ev);
  end if;
  if pg_temp.ve(a1, v_ev.id) then raise exception 'ORACULO C2: quien llamó ve la llamada a un reutilizable'; end if;
  t0 := t0 + 1;
  perform pg_temp.enviar(k1, pg_temp.ev('C1-' || t0, '900000013'));
  v_ev := pg_temp.evento('C1-' || t0);
  if v_ev.lead_id is distinct from cr2 or v_ev.atencion <> 'por_revisar' then
    raise exception 'ORACULO C3: el descartado reutilizable (30 días cumplidos) no quedó por revisar (%)', row_to_json(v_ev);
  end if;

  -- ═════ D. Propios terminales o en «no contactar»: identificadas, por revisar; número compartido ═════
  t0 := t0 + 1;
  perform pg_temp.enviar(k1, pg_temp.ev('C1-' || t0, '900000005'));
  v_ev := pg_temp.evento('C1-' || t0);
  if v_ev.lead_id is distinct from c5 or v_ev.atencion <> 'por_revisar' then
    raise exception 'ORACULO D1: el propio convertido no quedó identificado por revisar (%)', row_to_json(v_ev);
  end if;
  t0 := t0 + 1;
  perform pg_temp.enviar(k1, pg_temp.ev('C1-' || t0, '900000004'));
  v_ev := pg_temp.evento('C1-' || t0);
  if v_ev.lead_id is distinct from c4 or v_ev.atencion <> 'por_revisar' then
    raise exception 'ORACULO D2: el propio en «no contactar» no quedó identificado por revisar (%)', row_to_json(v_ev);
  end if;
  -- 900000006 es de c6 (a1) y c7 (a2): para a1, coincidencia única en su cartera; para b1, ambigua.
  t0 := t0 + 1;
  perform pg_temp.enviar(k1, pg_temp.ev('C1-' || t0, '900000006'));
  v_ev := pg_temp.evento('C1-' || t0);
  if v_ev.lead_id is distinct from c6 or v_ev.atencion <> 'requiere_resultado' then
    raise exception 'ORACULO D3: el número compartido no quedó con el lead propio (%)', row_to_json(v_ev);
  end if;
  t0 := t0 + 1;
  perform pg_temp.enviar(k4, pg_temp.ev('C4-' || t0, '900000006'));
  v_ev := pg_temp.evento('C4-' || t0);
  if v_ev.identificacion <> 'ambiguo' or v_ev.lead_id is not null or v_ev.calidad ? 'candidatos' then
    raise exception 'ORACULO D4: la llamada del supervisor no quedó ambigua sin conteo (%)', row_to_json(v_ev);
  end if;
  v_e3 := v_ev.id;
  -- Asociarla (candados: los dos leads, la llamada) a c7, del equipo de b1: pide resultado.
  perform pg_temp.como(b1);
  v_r := crm.asociar_llamada_celular(v_e3, c7);
  perform pg_temp.yo();
  if v_r ->> 'atencion' <> 'requiere_resultado' or (select lead_id from crm.llamadas_celular_eventos where id = v_e3) <> c7 then
    raise exception 'ORACULO D5: asociar la ambigua a un lead del equipo no funcionó (%)', v_r;
  end if;

  -- ═════ E. El id ═════
  select envios_dia, dia into v_n, v_dia from private.celulares_estado where asignacion_id = v_c1;
  foreach v_msg in array array['X1-1790980958', 'C1-123', 'C1-' || (t0 + 1) || 'x', 'C2-' || (t0 + 1),
                                'C1-' || (floor(extract(epoch from now() - interval '31 days'))::bigint),
                                'C1-' || (floor(extract(epoch from now() + interval '2 days'))::bigint)] loop
    v_r := pg_temp.enviar(k1, pg_temp.ev(v_msg, '900000001'));
    if v_r ->> 'resultado' <> 'invalido' or coalesce(v_r ->> 'mensaje', '') = '' or (v_r - 'resultado' - 'mensaje') <> '{}'::jsonb then
      raise exception 'ORACULO E1: el id % no se rechazó como inválido con su mensaje (%)', v_msg, v_r;
    end if;
    if exists (select 1 from private.llamadas_celular_recepciones where evento_origen_id = v_msg) then
      raise exception 'ORACULO E2: el id inválido % dejó recepción', v_msg;
    end if;
  end loop;
  select envios_dia, dia into v_n2, v_dia2 from private.celulares_estado where asignacion_id = v_c1;
  if v_dia2 = v_dia and v_n2 <> v_n + 6 then
    raise exception 'ORACULO E3: los inválidos no gastaron cupo (% → %)', v_n, v_n2;
  end if;
  -- Los bordes de la ventana entran.
  v_r := pg_temp.enviar(k1, pg_temp.ev('C1-' || floor(extract(epoch from now() - interval '29 days'))::bigint, '900000099'));
  v_r2 := pg_temp.enviar(k1, pg_temp.ev('C1-' || floor(extract(epoch from now() + interval '23 hours'))::bigint, '900000099'));
  if v_r <> aceptado or v_r2 <> aceptado then
    raise exception 'ORACULO E4: un id dentro de la ventana no entró (%, %)', v_r, v_r2;
  end if;
  -- El mismo id con otro contenido: aceptado y sin cambios.
  v_ev := pg_temp.evento((select evento_origen_id from crm.llamadas_celular_eventos where id = v_e1));
  v_r := pg_temp.enviar(k1, pg_temp.ev(v_ev.evento_origen_id, '900000002', '{"duracion_seg": 99}'));
  if v_r <> aceptado or (select row_to_json(e)::text from crm.llamadas_celular_eventos e where e.id = v_e1) <> row_to_json(v_ev)::text
     or (select count(*) from crm.llamadas_celular_eventos where evento_origen_id = v_ev.evento_origen_id) <> 1 then
    raise exception 'ORACULO E5: el mismo id con otro contenido cambió algo (%)', v_r;
  end if;
  -- Ignorado y después el mismo id con lead: sigue ignorado.
  v_r := pg_temp.enviar(k1, pg_temp.ev(v_id_ignorado, '900000001'));
  if v_r <> aceptado or exists (select 1 from crm.llamadas_celular_eventos where evento_origen_id = v_id_ignorado) then
    raise exception 'ORACULO E6: un id ignorado entró después con un lead (%)', v_r;
  end if;
  -- Rotar no duplica; la clave vieja deja de valer; un id nuevo entra con la asignación nueva.
  perform pg_temp.como(g1);
  v_r := crm.rotar_credencial_celular('C1'); v_c1b := (v_r ->> 'asignacion_id')::uuid; k1b := v_r ->> 'credencial';
  perform pg_temp.yo();
  v_r := pg_temp.enviar(k1b, pg_temp.ev(v_ev.evento_origen_id, '900000001'));
  if v_r <> aceptado or (select count(*) from crm.llamadas_celular_eventos where evento_origen_id = v_ev.evento_origen_id) <> 1 then
    raise exception 'ORACULO E7: rotar la clave duplicó la llamada (%)', v_r;
  end if;
  begin
    perform pg_temp.enviar(k1, pg_temp.ev('C1-' || (t0 + 2), '900000001'));
    raise exception 'ORACULO E8: la clave rotada siguió valiendo';
  exception when insufficient_privilege then
    if sqlerrm <> 'No autorizado' then raise exception 'ORACULO E8: la clave rotada dio pistas (%)', sqlerrm; end if;
    v_ok := v_ok + 1;
  end;
  t0 := t0 + 3;
  perform pg_temp.enviar(k1b, pg_temp.ev('C1-' || t0, '900000002'));
  v_ev := pg_temp.evento('C1-' || t0);
  if v_ev.asignacion_id is distinct from v_c1b or v_ev.lead_id is distinct from c2 then
    raise exception 'ORACULO E9: un id nuevo no entró con la asignación rotada (%)', row_to_json(v_ev);
  end if;
  -- Etiqueta reutilizada: C1 se cierra y pasa a a2; un id nuevo entra a nombre de a2.
  perform pg_temp.como(g1);
  perform crm.cerrar_asignacion_celular(v_c1b, 'reemplazo');
  v_r := crm.asignar_celular('C1', a2); v_c1c := (v_r ->> 'asignacion_id')::uuid; k1c := v_r ->> 'credencial';
  perform pg_temp.yo();
  t0 := t0 + 1;
  perform pg_temp.enviar(k1c, pg_temp.ev('C1-' || t0, '900000003'));
  v_ev := pg_temp.evento('C1-' || t0);
  if v_ev.analista_id is distinct from a2 or v_ev.lead_id is distinct from c3 or v_ev.atencion <> 'requiere_resultado' then
    raise exception 'ORACULO E10: con la etiqueta reutilizada el id nuevo no entró a nombre del analista nuevo (%)', row_to_json(v_ev);
  end if;

  -- ═════ F. Latido y fecha estricta ═════
  v_t := clock_timestamp();
  v_r := pg_temp.latir(k4, '{"v": 1, "version_macro": "llamadas-v2", "en_cola": 0, "ocurrio_en": "2026-10-05 09:30:00-05:00"}');
  if v_r <> aceptado or (select ultimo_latido_en < v_t or version_macro <> 'llamadas-v2'
                         from private.celulares_estado where asignacion_id = v_c4) then
    raise exception 'ORACULO F1: el latido válido no quedó con la hora de la puerta (%)', v_r;
  end if;
  select envios_dia, dia into v_n, v_dia from private.celulares_estado where asignacion_id = v_c4;
  foreach v_msg in array array[
      '{"v": 1, "version_macro": "x"}', '{"v": 1, "version_macro": "x", "en_cola": 1.5}',
      '{"v": 1, "version_macro": "x", "en_cola": 0, "ocurrio_en": "2026-10-05 09:30:00"}',
      '{"v": 1, "version_macro": "x", "en_cola": 0, "ocurrio_en": "2026-02-30 09:30:00-05:00"}',
      '{"v": 2, "version_macro": "x", "en_cola": 0}', 'null', '[1]'] loop
    v_r := pg_temp.latir(k4, v_msg::jsonb);
    if v_r ->> 'resultado' <> 'invalido' then
      raise exception 'ORACULO F2: el latido inválido % no respondió «invalido» (%)', v_msg, v_r;
    end if;
  end loop;
  select envios_dia, dia into v_n2, v_dia2 from private.celulares_estado where asignacion_id = v_c4;
  if (v_dia2 = v_dia and v_n2 <> v_n + 7)
     or (select version_macro from private.celulares_estado where asignacion_id = v_c4) <> 'llamadas-v2' then
    raise exception 'ORACULO F3: el latido inválido no gastó cupo o tocó el estado (% → %)', v_n, v_n2;
  end if;
  t0 := t0 + 1;
  v_r := pg_temp.enviar(k4, pg_temp.ev('C4-' || t0, '900000099', '{"ocurrio_en": "2026-10-05 09:30:00"}'));
  if v_r ->> 'resultado' <> 'invalido' then raise exception 'ORACULO F4: una fecha sin zona se aceptó (%)', v_r; end if;
  t0 := t0 + 1;
  v_r := pg_temp.enviar(k4, pg_temp.ev('C4-' || t0, '900000099', '{"ocurrio_en": "2026-10-05T14:30:00.5Z", "duracion_seg": 30}'));
  v_r2 := pg_temp.enviar(k4, pg_temp.ev('C4-' || (t0 + 1), '900000099', '{"duracion_seg": "30"}'));
  if v_r <> aceptado or v_r2 ->> 'resultado' <> 'invalido' then
    raise exception 'ORACULO F5: fecha con T y Z o duración como texto mal juzgadas (%, %)', v_r, v_r2;
  end if;
  t0 := t0 + 2;

  -- ═════ G. Cupo: la ventana no retrocede; Retry-After ≥ 1; sin política, error claro ═════
  update crm.llamadas_celular_politica set limite_envios_minuto = 30, limite_envios_dia = 600;
  update private.celulares_estado
     set minuto_desde = date_trunc('minute', clock_timestamp()) + interval '10 minutes', envios_minuto = 30
   where asignacion_id = v_c4;
  begin
    perform pg_temp.enviar(k4, pg_temp.ev('C4-' || t0, '900000099'));
    raise exception 'ORACULO G1: con la ventana guardada adelante y agotada, el envío pasó (la ventana retrocedió)';
  exception when sqlstate 'P0429' then
    get stacked diagnostics v_det = pg_exception_detail;
    if coalesce(substring(v_det from '^reintentar_en_seg=([0-9]+)$')::integer, 0) < 540 then
      raise exception 'ORACULO G1: la espera no sale de la ventana guardada (%)', v_det;
    end if;
    v_ok := v_ok + 1;
  end;
  update private.celulares_estado
     set minuto_desde = date_trunc('minute', clock_timestamp()) - interval '1 minute', envios_minuto = 30
   where asignacion_id = v_c4;
  v_r := pg_temp.enviar(k4, pg_temp.ev('C4-' || t0, '900000099'));
  if v_r <> aceptado or (select envios_minuto from private.celulares_estado where asignacion_id = v_c4) <> 1 then
    raise exception 'ORACULO G2: pasado el minuto, el contador no volvió a cero (%)', v_r;
  end if;
  -- Medianoche de Lima: el día guardado adelante no retrocede; uno pasado vuelve a cero.
  update private.celulares_estado
     set dia = (clock_timestamp() at time zone 'America/Lima')::date + 1, envios_dia = 600, minuto_desde = null, envios_minuto = 0
   where asignacion_id = v_c4;
  begin
    perform pg_temp.enviar(k4, pg_temp.ev('C4-' || (t0 + 1), '900000099'));
    raise exception 'ORACULO G3: con el día guardado adelante y agotado, el envío pasó';
  exception when sqlstate 'P0429' then
    get stacked diagnostics v_msg = message_text, v_det = pg_exception_detail;
    if v_msg not like '%del día%' or coalesce(substring(v_det from '^reintentar_en_seg=([0-9]+)$')::integer, 0) < 1 then
      raise exception 'ORACULO G3: freno diario mal dicho (%, %)', v_msg, v_det;
    end if;
    v_ok := v_ok + 1;
  end;
  update private.celulares_estado
     set dia = (clock_timestamp() at time zone 'America/Lima')::date - 1, envios_dia = 600
   where asignacion_id = v_c4;
  v_r := pg_temp.enviar(k4, pg_temp.ev('C4-' || (t0 + 1), '900000099'));
  if v_r <> aceptado or (select envios_dia from private.celulares_estado where asignacion_id = v_c4) <> 1 then
    raise exception 'ORACULO G4: pasada la medianoche de Lima, el día no volvió a cero (%)', v_r;
  end if;
  t0 := t0 + 2;
  -- Sin política: error claro (se borra y se repone dentro de un bloque que se deshace).
  begin
    execute 'set local session_replication_role = replica';
    delete from crm.llamadas_celular_politica;
    execute 'set local session_replication_role = origin';
    begin
      perform pg_temp.enviar(k4, pg_temp.ev('C4-' || t0, '900000099'));
      raise exception 'ORACULO G5: sin política, el envío pasó';
    exception when sqlstate '55000' then
      if sqlerrm not like 'Falta la política%' then raise exception 'ORACULO G5: sin política, error poco claro (%)', sqlerrm; end if;
    end;
    raise exception using errcode = 'P9999', message = 'deshacer';
  exception when sqlstate 'P9999' then v_ok := v_ok + 1;
  end;
  if (select count(*) from crm.llamadas_celular_politica) <> 1 then raise exception 'ORACULO G6: la política no se repuso'; end if;
  update crm.llamadas_celular_politica set limite_envios_minuto = 600, limite_envios_dia = 20000;

  -- ═════ H. Identidad: vuelve a la anterior en éxito y en error, también dentro de un bloque que atrapa 22023 ═════
  if coalesce(current_setting('request.jwt.claim.sub', true), '') <> '' then
    raise exception 'ORACULO H1: la ingesta dejó puesta una identidad';
  end if;
  perform set_config('request.jwt.claim.sub', g1::text, true);
  v_r := to_jsonb(private.llamada_celular_candidatos_dueno(b1, array['+51900000006'], clock_timestamp()));
  if current_setting('request.jwt.claim.sub', true) is distinct from g1::text or jsonb_array_length(v_r) <> 2 then
    raise exception 'ORACULO H2: los candidatos del supervisor no se evaluaron como él o la identidad no volvió (%)', v_r;
  end if;
  begin
    perform private.llamada_celular_candidatos_dueno(b1, array['+51900000006'], clock_timestamp());
    raise exception using errcode = '22023', message = 'marca';
  exception when sqlstate '22023' then
    if current_setting('request.jwt.claim.sub', true) is distinct from g1::text then
      raise exception 'ORACULO H3: tras un 22023 la identidad no es la anterior';
    end if;
  end;
  perform set_config('request.jwt.claim.sub', '', true);
  if exists (select 1 from public.audit_log l where l.tabla = 'crm.llamadas_celular_eventos' and l.usuario_id is not null
               and l.operacion = 'INSERT') then
    raise exception 'ORACULO H4: la bitácora atribuyó una llamada ingerida a una persona';
  end if;
  if exists (select 1 from public.audit_log l where l.tabla = 'crm.llamadas_celular_eventos'
               and (l.data_despues ? 'hash_payload' or l.data_despues ->> 'numero_canonico' <> '***')) then
    raise exception 'ORACULO H5: la bitácora muestra el número o un hash';
  end if;

  -- ═════ I. Lead borrado: nadie la ve ni la toca, gerencia incluida ═════
  t0 := t0 + 1;
  perform pg_temp.enviar(k4, pg_temp.ev('C4-' || t0, '900000002'));
  v_e4 := (pg_temp.evento('C4-' || t0)).id;
  if v_e4 is null or not pg_temp.ve(g1, v_e4) then raise exception 'ORACULO I1: falta la llamada a c2'; end if;
  update crm.leads set activo = false where id = c2;
  if pg_temp.ve(g1, v_e4) or pg_temp.ve(b1, v_e4) or pg_temp.ve(a1, v_e4) then
    raise exception 'ORACULO I2: alguien ve la llamada de un lead dado de baja';
  end if;
  begin
    perform pg_temp.como(g1);
    perform crm.llamada_celular_detalle_fn(v_e4);
    raise exception 'ORACULO I3: gerencia lee el detalle de la llamada de un lead dado de baja';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    perform pg_temp.como(g1);
    perform crm.descartar_llamada_celular(v_e4, 'personal');
    raise exception 'ORACULO I4: gerencia descarta la llamada de un lead dado de baja';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  update crm.leads set activo = true where id = c2;

  -- ═════ J. Entrantes y desconocidas se ignoran; la perilla está bloqueada ═════
  t0 := t0 + 1;
  v_r := pg_temp.enviar(k4, pg_temp.ev('C4-' || t0, '900000001', '{"direccion": "entrante", "estado_tecnico": "no_atendida"}'));
  v_r2 := pg_temp.enviar(k4, pg_temp.ev('C4-' || (t0 + 1), '900000001') - 'direccion');
  if v_r <> aceptado or v_r2 <> aceptado
     or exists (select 1 from crm.llamadas_celular_eventos where evento_origen_id in ('C4-' || t0, 'C4-' || (t0 + 1))) then
    raise exception 'ORACULO J1: una entrante o una dirección desconocida se guardó (%, %)', v_r, v_r2;
  end if;
  t0 := t0 + 2;
  begin
    perform pg_temp.como(g1);
    perform crm.fijar_politica_llamadas_celular(p_entrantes_activas => true);
    raise exception 'ORACULO J2: gerencia encendió las entrantes';
  exception when sqlstate '22023' then v_ok := v_ok + 1; end;
  begin
    update crm.llamadas_celular_politica set entrantes_activas = true;
    raise exception 'ORACULO J3: la tabla aceptó las entrantes encendidas';
  exception when check_violation then v_ok := v_ok + 1; end;

  -- ═════ K. Salud sin envíos; la bandeja vieja ya no existe; la puerta solo devuelve resultado y mensaje ═════
  perform pg_temp.como(g1); v_salud := crm.celulares_salud_fn(); perform pg_temp.yo();
  if exists (select 1 from jsonb_array_elements(v_salud) x where x ? 'envios_hoy' or x ? 'ultimo_envio_en')
     or not exists (select 1 from jsonb_array_elements(v_salud) x where x ->> 'etiqueta' = 'C4' and x ? 'ultimo_latido_en') then
    raise exception 'ORACULO K1: la salud muestra envíos o perdió el latido (%)', v_salud;
  end if;
  if to_regprocedure('crm.llamadas_celular_pendientes_fn(integer)') is not null then
    raise exception 'ORACULO K2: la bandeja duplicada sigue';
  end if;

  -- ═════ L. Candados en un solo hilo: descartar revalida; enlazar rechaza un resultado deshecho ═════
  v_ev := pg_temp.evento((select evento_origen_id from crm.llamadas_celular_eventos where id = v_e1));
  insert into crm.actividades (lead_id, tipo, metadata, creado_por)
  values (c1, 'llamada_no_contestada', jsonb_build_object('evento', 'resultado_llamada', 'resultado', 'no_contesto',
          'deshecho_en', now()), a1)
  returning id into v_act2;
  begin
    perform pg_temp.como(a1);
    perform crm.enlazar_llamada_celular(v_e1, v_act2);
    raise exception 'ORACULO L1: se enlazó un resultado deshecho';
  exception when sqlstate '22023' then
    if sqlerrm not like '%se deshizo%' then raise exception 'ORACULO L1: rechazo con otro motivo (%)', sqlerrm; end if;
    v_ok := v_ok + 1;
  end;
  -- La regla de los 10 minutos sigue en el enlace manual: un resultado de 1 hora antes de la llamada no se enlaza.
  insert into crm.actividades (lead_id, tipo, metadata, creado_por, creado_en)
  values (c1, 'llamada_realizada', '{"evento": "resultado_llamada", "resultado": "volver_a_llamar"}', a1, now() - interval '1 hour')
  returning id into v_act;
  begin
    perform pg_temp.como(a1);
    perform crm.enlazar_llamada_celular(v_e1, v_act);
    raise exception 'ORACULO L3: se enlazó a mano un resultado anterior a la llamada';
  exception when sqlstate '22023' then
    if sqlerrm not like '%antes de la llamada%' then raise exception 'ORACULO L3: rechazo con otro motivo (%)', sqlerrm; end if;
    v_ok := v_ok + 1;
  end;
  perform pg_temp.como(a1);
  v_r := crm.descartar_llamada_celular(v_e1, 'personal');
  perform pg_temp.yo();
  if (select atencion from crm.llamadas_celular_eventos where id = v_e1) <> 'descartado_con_motivo' then
    raise exception 'ORACULO L2: descartar no funcionó (%)', v_r;
  end if;

  -- ═════ M. Purga: 30 días sin enlace, registradas se quedan, descartadas por su plazo, recepciones a 32 ═════
  delete from public.audit_log;  -- solo para contar lo que la purga deja en la bitácora
  insert into crm.actividades (lead_id, tipo, metadata, creado_por, creado_en) values
    (c3, 'llamada_realizada', '{"evento": "resultado_llamada", "resultado": "volver_a_llamar"}', a2, now() - interval '100 days')
  returning id into v_act;
  insert into crm.actividades (lead_id, tipo, metadata, creado_por, creado_en) values
    (c3, 'llamada_no_contestada', jsonb_build_object('evento', 'resultado_llamada', 'resultado', 'no_contesto',
      'deshecho_en', now() - interval '99 days'), a2, now() - interval '100 days')
  returning id into v_act2;
  insert into crm.llamadas_celular_eventos (asignacion_id, analista_id, evento_origen_id, numero_canonico, direccion,
      recibido_en, identificacion, atencion, lead_id, metodo_asociacion, asociado_en, motivo_descarte, descartado_en, descartado_por)
  values
    (v_c4, b1, 'C4-1000000001', '+51900000003', 'saliente', now() - interval '31 days', 'identificado', 'por_revisar', c3, 'exacto', now(), null, null, null),
    (v_c4, b1, 'C4-1000000002', '+51900000001', 'saliente', now() - interval '29 days', 'identificado', 'requiere_resultado', c1, 'exacto', now(), null, null, null),
    (v_c4, b1, 'C4-1000000003', '+51900000006', 'saliente', now() - interval '31 days', 'ambiguo', 'por_revisar', null, null, null, null, null, null),
    (v_c4, b1, 'C4-1000000004', '+51900000003', 'saliente', now() - interval '100 days', 'identificado', 'registrado', c3, 'exacto', now(), null, null, null),
    (v_c4, b1, 'C4-1000000005', '+51900000003', 'saliente', now() - interval '100 days', 'identificado', 'registrado', c3, 'exacto', now(), null, null, null),
    (v_c4, b1, 'C4-1000000006', '+51900000003', 'saliente', now() - interval '40 days', 'identificado', 'descartado_con_motivo', c3, 'exacto', now(), 'personal', now() - interval '31 days', b1),
    (v_c4, b1, 'C4-1000000007', '+51900000003', 'saliente', now() - interval '40 days', 'identificado', 'descartado_con_motivo', c3, 'exacto', now(), 'personal', now() - interval '5 days', b1);
  insert into crm.llamadas_celular_enlaces (evento_id, actividad_id, lead_id, enlazado_por)
  select e.id, case e.evento_origen_id when 'C4-1000000004' then v_act else v_act2 end, c3, a2
  from crm.llamadas_celular_eventos e where e.evento_origen_id in ('C4-1000000004', 'C4-1000000005');
  insert into private.llamadas_celular_recepciones (evento_origen_id, asignacion_id, recibido_en) values
    ('C4-1000000011', v_c4, now() - interval '33 days'), ('C4-1000000012', v_c4, now() - interval '31 days');
  select count(*) into v_n from crm.llamadas_celular_eventos;
  v_n2 := private.caducar_llamadas_celular();
  if v_n2 <> 4 then raise exception 'ORACULO M1: la purga retiró % filas, se esperaban 4 (2 sin resolver, 1 descartada, 1 recepción)', v_n2; end if;
  if exists (select 1 from crm.llamadas_celular_eventos where evento_origen_id in ('C4-1000000001', 'C4-1000000003', 'C4-1000000006'))
     or (select count(*) from crm.llamadas_celular_eventos
         where evento_origen_id in ('C4-1000000002', 'C4-1000000004', 'C4-1000000005', 'C4-1000000007')) <> 4
     or (select count(*) from crm.llamadas_celular_eventos) <> v_n - 3 then
    raise exception 'ORACULO M2: la purga no respetó los plazos (sin resolver 30 días; registradas, aunque deshechas, se quedan)';
  end if;
  if exists (select 1 from private.llamadas_celular_recepciones where evento_origen_id = 'C4-1000000011')
     or not exists (select 1 from private.llamadas_celular_recepciones where evento_origen_id = 'C4-1000000012') then
    raise exception 'ORACULO M3: la purga no retiró la recepción de 33 días o se llevó la de 31 (liberaría un id dentro de la ventana)';
  end if;
  if (select count(*) from public.audit_log where tabla = 'crm.llamadas_celular_eventos' and operacion = 'DELETE'
        and data_antes ->> 'numero_canonico' = '***') <> 3 then
    raise exception 'ORACULO M4: la purga no dejó su rastro enmascarado en la bitácora';
  end if;
  if coalesce(current_setting('crm.op_purga_llamadas', true), 'off') <> 'off' then
    raise exception 'ORACULO M5: la purga dejó el GUC encendido';
  end if;
  begin
    delete from private.llamadas_celular_recepciones where evento_origen_id = 'C4-1000000012';
    raise exception 'ORACULO M6: una recepción se borró a mano';
  exception when insufficient_privilege then
    if sqlerrm not like '%no se borra a mano%' then raise exception 'ORACULO M6: el borrado se frenó por otra regla (%)', sqlerrm; end if;
    v_ok := v_ok + 1;
  end;
  begin
    update private.llamadas_celular_recepciones set recibido_en = now() where evento_origen_id = 'C4-1000000012';
    raise exception 'ORACULO M7: una recepción se editó';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;

  if v_ok <> 13 then raise exception 'ORACULO: % de 13 rechazos esperados', v_ok; end if;
  raise notice 'ORACULO CORRECCION OK: sin pistas, bolsa, reutilizables, propios terminales, id (forma, etiqueta, ventana, reenvío, rotación, etiqueta reutilizada), latido y fecha estricta, cupo (ventanas que no retroceden, sin política), identidad, lead borrado, entrantes bloqueadas, salud sin envíos, candados en un hilo y purga comprobados';
end;
$oraculo$;

rollback;

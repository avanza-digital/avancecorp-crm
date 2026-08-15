-- ---------------------------------------------------------------------------
-- Oraculo del CIERRE DE MES
-- ---------------------------------------------------------------------------
-- Recorre el ciclo entero contra datos sembrados y ASEVERA cada paso. Crear las
-- funciones no prueba nada —plpgsql solo valida sintaxis al crearlas—: aqui se
-- EJECUTAN.
--
-- El ciclo que recorre:
--   1. Un mes con actividad se cierra y queda una foto por vendedor.
--   2. Ese mes deja de recalcularse: aunque cambie el mundo, la foto no se mueve.
--   3. Un mes cerrado no se cierra dos veces, ni se cierra fuera de orden, ni lo
--      cierra quien no debe.
--   4. Anular un cierre de un mes CERRADO no toca ese mes: crea una deuda.
--   5. El mes vivo enseña su numero ya descontado, sin bajar de cero.
--   6. Al cerrar el mes vivo, la deuda se salda hasta donde llega y el resto se
--      arrastra.
--   6bis. Y el capital se RESTA de verdad de donde se paga, no solo se marca
--        como saldado (fallo de dinero corregido el 15/08; ver el bloque).
--   7. Anular un cierre de un mes ABIERTO sigue reescribiendo ese mes, sin deuda.
--   8. La foto es de una sola direccion: no se edita ni se borra.
--
-- USO (banco local con calcos, o branch de Supabase):
--   psql -v ON_ERROR_STOP=1 -d <base> -f supabase/scripts/test-cierre-mes.sql
--
-- Termina con ROLLBACK: no deja nada sembrado.
-- ---------------------------------------------------------------------------

\set ON_ERROR_STOP on

begin;

do $oraculo$
declare
  v_g uuid := '11111111-1111-4111-8111-111111111111'; -- gerencia
  v_s uuid := '22222222-2222-4222-8222-222222222222'; -- supervisor
  v_v uuid := '33333333-3333-4333-8333-333333333333'; -- vendedor
  v_cli uuid := '44444444-4444-4444-8444-444444444444'; -- cliente
  v_mp_jun uuid := '55555555-5555-4555-8555-555555555551';
  v_mp_jul uuid := '55555555-5555-4555-8555-555555555552';
  v_mvj uuid := '66666666-6666-4666-8666-666666666661';
  v_mvl uuid := '66666666-6666-4666-8666-666666666662';
  v_lead_a uuid := '77777777-7777-4777-8777-777777777771'; -- cierre de junio, no referido
  v_lead_b uuid := '77777777-7777-4777-8777-777777777772'; -- cierre de junio, referido
  v_lead_c uuid := '77777777-7777-4777-8777-777777777773'; -- cierre de julio
  -- Los tres meses son RELATIVOS al mes en curso: un oraculo con fechas fijas
  -- caduca solo (este empezo intentando cerrar el mes que estaba corriendo).
  v_m0 date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_jun date := (date_trunc('month', now() at time zone 'America/Lima') - interval '4 months')::date;
  v_jul date := (date_trunc('month', now() at time zone 'America/Lima') - interval '3 months')::date;
  v_r jsonb;
  v_n integer;
  v_num numeric;
  v_pend numeric;
begin
  -- ── Siembra ───────────────────────────────────────────────────────────────
  insert into public.perfiles (id, nombre_completo, rol, activo) values
    (v_g, 'GERENTE DE PRUEBA', 'admin', true),
    (v_s, 'SUPERVISOR DE PRUEBA', 'comercial', true),
    (v_v, 'VENDEDOR DE PRUEBA', 'comercial', true),
    (v_cli, 'CLIENTE DE PRUEBA', 'cliente', true);

  insert into crm.conversion_pesos (vigente_desde, peso_referido, nota)
  values (v_jun, 0.150, 'oraculo') on conflict do nothing;

  insert into crm.meta_periodos (id, periodo, revision, publicada_en) values
    (v_mp_jun, v_jun, 1, now()), (v_mp_jul, v_jul, 1, now());
  insert into crm.metas_vendedor (id, meta_periodo_id, vendedor_id, supervisor_id, conversion_objetivo) values
    (v_mvj, v_mp_jun, v_v, v_s, 15), (v_mvl, v_mp_jul, v_v, v_s, 15);
  insert into crm.metas_vendedor_detalle (meta_vendedor_id, categoria, moneda, capital_objetivo, contratos_objetivo) values
    (v_mvj, 'nuevo', 'PEN', 100000, 5), (v_mvl, 'nuevo', 'PEN', 100000, 5);

  -- JUNIO: 4 recibidos, 2 cerrados (uno referido) → numerador 1,15 sobre 4.
  insert into crm.leads (id, nombre_completo, etapa, origen, vendedor_id, perfil_id, convertido_en) values
    (v_lead_a, 'LEAD A', 'convertido', 'formulario', v_v, v_cli, (v_jun + interval '9 days 16 hours')),
    (v_lead_b, 'LEAD B', 'convertido', 'referido', v_v, null, (v_jun + interval '11 days 16 hours'));
  insert into crm.leads (id, nombre_completo, etapa, origen, vendedor_id, convertido_en) values
    ('77777777-7777-4777-8777-777777777774', 'LEAD C', 'descartado', 'formulario', v_v, null),
    ('77777777-7777-4777-8777-777777777775', 'LEAD D', 'descartado', 'formulario', v_v, null);
  insert into crm.lead_asignaciones (lead_id, analista_id, resultado, resultado_en, asignado_en, origen) values
    (v_lead_a, v_v, 'convertido', (v_jun + interval '9 days 16 hours'), (v_jun + interval '1 day 16 hours'), 'formulario'),
    (v_lead_b, v_v, 'convertido', (v_jun + interval '11 days 16 hours'), (v_jun + interval '2 days 16 hours'), 'referido'),
    ('77777777-7777-4777-8777-777777777774', v_v, 'descartado', (v_jun + interval '19 days 16 hours'), (v_jun + interval '3 days 16 hours'), 'formulario'),
    ('77777777-7777-4777-8777-777777777775', v_v, 'descartado', (v_jun + interval '20 days 16 hours'), (v_jun + interval '4 days 16 hours'), 'formulario');
  -- Un contrato de junio, del cliente del lead A, creado por el vendedor.
  insert into public.contratos (cliente_id, capital, moneda, categoria, estado, creado_por, creado_en)
  values (v_cli, 40000, 'PEN', 'nuevo', 'activo', v_v, (v_jun + interval '9 days 17 hours'));

  -- ── 1. Cerrar junio ───────────────────────────────────────────────────────
  perform set_config('test.uid', '', true); -- sin uid = ciclo automatico
  v_r := crm.cerrar_periodo(v_jun);
  if (v_r->>'ok')::boolean is not true then
    raise exception 'FALLO 1: cerrar junio no devolvio ok — %', v_r;
  end if;
  if (v_r->>'automatico')::boolean is not true then
    raise exception 'FALLO 1: sin uid, el cierre deberia constar como automatico — %', v_r;
  end if;
  select count(*) into v_n from crm.cierre_mes_vendedor where periodo = v_jun;
  if v_n < 1 then
    raise exception 'FALLO 1: junio se cerro sin ninguna fila en la foto';
  end if;

  -- La foto guarda el NOMBRE, no solo el uuid: el asesor puede irse del equipo.
  if not exists (select 1 from crm.cierre_mes_vendedor
                 where periodo = v_jun and vendedor_id = v_v
                   and nombre_completo = 'VENDEDOR DE PRUEBA') then
    raise exception 'FALLO 1: la foto no congelo el nombre del vendedor';
  end if;

  -- ── 2. Junio deja de recalcularse ─────────────────────────────────────────
  select numerador into v_num from crm.cierre_mes_vendedor
  where periodo = v_jun and vendedor_id = v_v;
  if v_num is distinct from 1.150 then
    raise exception 'FALLO 2: el numerador sellado de junio deberia ser 1,150 y es %', v_num;
  end if;

  perform set_config('test.uid', v_v::text, true);
  v_r := crm.conversion_mensual_fn(v_jun);
  if (v_r->'cierre'->>'cerrado')::boolean is not true then
    raise exception 'FALLO 2: junio no se declara cerrado en el payload — %', v_r->'cierre';
  end if;
  if (v_r->'total'->>'numerador')::numeric is distinct from 1.150 then
    raise exception 'FALLO 2: la conversion de junio no sale de la foto — %', v_r->'total';
  end if;

  -- Y aunque el mundo cambie, la foto no. Se le quita el supervisor al vendedor
  -- y se le saca del roster: en un mes ABIERTO eso le cambiaria el numero.
  delete from crm.metas_vendedor where id = v_mvj;
  v_r := crm.conversion_mensual_fn(v_jun);
  if (v_r->'total'->>'numerador')::numeric is distinct from 1.150 then
    raise exception 'FALLO 2: junio se movio al cambiar el roster — %', v_r->'total';
  end if;

  -- ── 3. Un mes cerrado no se cierra dos veces ──────────────────────────────
  begin
    perform set_config('test.uid', '', true);
    perform crm.cerrar_periodo(v_jun);
    raise exception 'FALLO 3: junio se dejo cerrar dos veces';
  exception when sqlstate 'P0409' then null;
  end;

  -- Ni lo cierra un vendedor.
  begin
    perform set_config('test.uid', v_v::text, true);
    perform crm.cerrar_periodo(v_jul);
    raise exception 'FALLO 3: un vendedor pudo cerrar un mes';
  exception when sqlstate '42501' then null;
  end;

  -- Ni se cierra el mes en curso.
  begin
    perform set_config('test.uid', '', true);
    perform crm.cerrar_periodo(date_trunc('month', now() at time zone 'America/Lima')::date);
    raise exception 'FALLO 3: se dejo cerrar el mes en curso';
  exception when sqlstate '22023' then null;
  end;

  -- ── 4. Anular un cierre de un mes CERRADO crea deuda ──────────────────────
  perform set_config('test.uid', v_g::text, true);
  v_r := crm.anular_cierre_avance(v_lead_a, 'mala practica detectada en octubre');
  if (v_r->>'mes_cerrado')::boolean is not true then
    raise exception 'FALLO 4: anular un cierre de un mes cerrado no lo declaro — %', v_r;
  end if;
  if v_r->>'ajuste_id' is null then
    raise exception 'FALLO 4: no nacio el ajuste — %', v_r;
  end if;

  select pendiente_numerador into v_pend
  from crm.ajustes_mes_cerrado where lead_id = v_lead_a;
  if v_pend is distinct from 1 then
    raise exception 'FALLO 4: la deuda deberia ser 1 (cierre no referido) y es %', v_pend;
  end if;

  -- Y JUNIO NO SE MOVIO. Es el corazon de la decision de Miguel.
  perform set_config('test.uid', v_v::text, true);
  v_r := crm.conversion_mensual_fn(v_jun);
  if (v_r->'total'->>'numerador')::numeric is distinct from 1.150 then
    raise exception 'FALLO 4: junio cambio al anular un cierre suyo — %', v_r->'total';
  end if;

  -- ── 5. El mes vivo enseña el descuento, sin bajar de cero ─────────────────
  -- Julio no tiene ni un cierre: el descuento no cabe y el numerador se queda
  -- en cero, NUNCA en negativo.
  -- (la meta de julio ya se sembro arriba: v_mvl)
  insert into crm.lead_asignaciones (lead_id, analista_id, resultado, asignado_en, origen)
  values (v_lead_c, v_v, null, (v_jul + interval '1 day 16 hours'), 'formulario');
  insert into crm.leads (id, nombre_completo, etapa, origen, vendedor_id)
  values (v_lead_c, 'LEAD JULIO', 'contactado', 'formulario', v_v);

  v_r := crm.conversion_mensual_fn(v_jul);
  select (r->'ajuste'->>'pendiente')::numeric into v_pend
  from jsonb_array_elements(v_r->'responsables') r
  where (r->>'vendedor_id')::uuid = v_v;
  if v_pend is distinct from 1 then
    raise exception 'FALLO 5: el mes vivo no declara la deuda pendiente — %', v_r->'responsables';
  end if;
  select (r->>'numerador')::numeric into v_num
  from jsonb_array_elements(v_r->'responsables') r
  where (r->>'vendedor_id')::uuid = v_v;
  if v_num < 0 then
    raise exception 'FALLO 5: el numerador del mes vivo quedo NEGATIVO (%)', v_num;
  end if;

  -- ── 6. Al cerrar julio, la deuda se salda hasta donde llega ───────────────
  -- Julio no tiene cierres, asi que no puede absorber nada: la deuda sigue
  -- entera. Es «se arrastra», no «se perdona».
  perform set_config('test.uid', '', true);
  perform crm.cerrar_periodo(v_jul);
  select pendiente_numerador into v_pend
  from crm.ajustes_mes_cerrado where lead_id = v_lead_a;
  if v_pend is distinct from 1 then
    raise exception 'FALLO 6: la deuda se perdono en un mes sin cierres (pendiente=%)', v_pend;
  end if;
  if exists (select 1 from crm.ajustes_mes_cerrado where lead_id = v_lead_a and saldado_en is not null) then
    raise exception 'FALLO 6: la deuda quedo marcada como saldada sin haberse saldado';
  end if;

  -- ── 6bis. EL CAPITAL SE RESTA DE VERDAD ───────────────────────────────────
  -- El fallo que este bloque existe para que no vuelva: la primera version
  -- marcaba la deuda de capital como saldada y NO la restaba de ninguna cifra.
  -- El asesor cobraba igual y la deuda desaparecia. Aqui se comprueba con un mes
  -- que SI puede absorberla.
  declare
    v_ago date := (date_trunc('month', now() at time zone 'America/Lima') - interval '2 months')::date;
    v_mp_ago uuid := '55555555-5555-4555-8555-555555555553';
    v_mv_ago uuid := '66666666-6666-4666-8666-666666666664';
    v_lead_e uuid := '77777777-7777-4777-8777-777777777777';
    v_cli2 uuid := '44444444-4444-4444-8444-444444444445';
    v_cap numeric;
  begin
    insert into crm.meta_periodos (id, periodo, revision, publicada_en) values (v_mp_ago, v_ago, 1, now());
    insert into crm.metas_vendedor (id, meta_periodo_id, vendedor_id, supervisor_id, conversion_objetivo)
      values (v_mv_ago, v_mp_ago, v_v, v_s, 15);
    insert into crm.metas_vendedor_detalle (meta_vendedor_id, categoria, moneda, capital_objetivo, contratos_objetivo)
      values (v_mv_ago, 'nuevo', 'PEN', 100000, 5);
    insert into public.perfiles (id, nombre_completo, rol, activo) values (v_cli2, 'CLIENTE DOS', 'cliente', true);
    insert into crm.leads (id, nombre_completo, etapa, origen, vendedor_id, perfil_id, convertido_en)
      values (v_lead_e, 'LEAD AGOSTO', 'convertido', 'formulario', v_v, v_cli2, (v_ago + interval '4 days 16 hours'));
    insert into crm.lead_asignaciones (lead_id, analista_id, resultado, resultado_en, asignado_en, origen)
      values (v_lead_e, v_v, 'convertido', (v_ago + interval '4 days 16 hours'), '2026-08-02 16:00+00', 'formulario');
    -- Agosto produce 100.000 en soles: hay de donde restar los 40.000 que se deben.
    insert into public.contratos (cliente_id, capital, moneda, categoria, estado, creado_por, creado_en)
      values (v_cli2, 100000, 'PEN', 'nuevo', 'activo', v_v, (v_ago + interval '4 days 17 hours'));

    perform set_config('test.uid', '', true);
    perform crm.cerrar_periodo(v_ago);

    -- La deuda de capital quedo saldada…
    select pendiente_pen into v_cap from crm.ajustes_mes_cerrado where lead_id = v_lead_a;
    if v_cap is distinct from 0 then
      raise exception 'FALLO 6bis: la deuda de capital no se saldo con un mes que si podia (pendiente=%)', v_cap;
    end if;

    -- …Y EL DINERO SE RESTO DE VERDAD. 100.000 producidos − 40.000 de deuda.
    select (e->>'capital_real')::numeric into v_cap
    from crm.cierre_mes_vendedor f,
         jsonb_array_elements(f.detalles) e
    where f.periodo = v_ago and f.vendedor_id = v_v
      and e->>'categoria' = 'nuevo' and e->>'moneda' = 'PEN';
    if v_cap is distinct from 60000 then
      raise exception 'FALLO 6bis: el capital sellado deberia ser 60.000 (100.000 − 40.000 de deuda) y es % — la deuda se dio por cobrada SIN descontar', v_cap;
    end if;

    -- Y la foto DECLARA lo descontado, para poder explicarlo.
    select (e->>'capital_ajuste')::numeric into v_cap
    from crm.cierre_mes_vendedor f, jsonb_array_elements(f.detalles) e
    where f.periodo = v_ago and f.vendedor_id = v_v
      and e->>'categoria' = 'nuevo' and e->>'moneda' = 'PEN';
    if v_cap is distinct from 40000 then
      raise exception 'FALLO 6bis: la foto no declara el descuento aplicado (%)', v_cap;
    end if;
  end;

  -- ── 7. Un mes ABIERTO se sigue reescribiendo, sin deuda ───────────────────
  -- El lead B es de junio (cerrado); para probar el camino abierto hace falta un
  -- cierre en un mes sin sellar. Se usa el mes en curso.
  declare
    v_lead_d uuid := '77777777-7777-4777-8777-777777777776';
    v_ahora timestamptz := now();
  begin
    insert into crm.leads (id, nombre_completo, etapa, origen, vendedor_id, convertido_en)
    values (v_lead_d, 'LEAD DEL MES VIVO', 'convertido', 'formulario', v_v, v_ahora);
    insert into crm.lead_asignaciones (lead_id, analista_id, resultado, resultado_en, asignado_en, origen)
    values (v_lead_d, v_v, 'convertido', v_ahora, v_ahora, 'formulario');

    perform set_config('test.uid', v_g::text, true);
    v_r := crm.anular_cierre_avance(v_lead_d, 'error de captura, mismo mes');
    if (v_r->>'mes_cerrado')::boolean is not false then
      raise exception 'FALLO 7: anular en un mes abierto no deberia declarar mes cerrado — %', v_r;
    end if;
    if v_r->>'ajuste_id' is not null then
      raise exception 'FALLO 7: un mes abierto no debe generar deuda — %', v_r;
    end if;
  end;

  -- ── 8. La foto es de una sola direccion ───────────────────────────────────
  begin
    update crm.cierre_mes_vendedor set numerador = 99 where periodo = v_jun;
    raise exception 'FALLO 8: la foto de un mes cerrado se dejo editar';
  exception when sqlstate 'P0409' then null;
  end;
  begin
    delete from crm.periodos_cerrados where periodo = v_jun;
    raise exception 'FALLO 8: un mes cerrado se dejo borrar';
  exception when sqlstate 'P0409' then null;
  end;

  raise notice 'ORACULO DEL CIERRE DE MES: 9/9 OK';
end;
$oraculo$;

rollback;

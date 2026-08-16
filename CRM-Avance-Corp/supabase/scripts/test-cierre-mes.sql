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
--   9. La ventana de cierre abre el dia 10 del mes siguiente — a medianoche de
--      LIMA, no de UTC (aritmetica pura: se prueba corra el dia que corra).
--   10. El candado: nadie sella un mes antes de que su ventana abra.
--   10bis. Y GERENCIA SI puede sellar a mano cuando toca, con su autoria escrita
--        (el unico caso POSITIVO de la accion principal; sin el, todo lo demas
--        puede estar verde sobre algo que no funciona).
--   11. El ciclo cierra solo, en orden y sin repetir.
--   11bis. Y si un mes falla, lo ya sellado SOBREVIVE: cada mes va en su propia
--        subtransaccion. Sin eso, un mes torcido tiraba el trabajo bueno del
--        anterior y el sistema se atascaba para siempre rehaciendolo.
--   12. El aviso: sus TRES estados (en_ventana / hoy / atascado), que todos los
--       roles con pantalla ven lo mismo, y que con la ventana cerrada el ciclo
--       se CALLA en vez de reventar (un cron en rojo a diario deja de mirarse).
--   13. Un mes que aparece POR DETRAS de lo ya sellado —metas publicadas hacia
--       atras— no lo sella nadie: ni el cron ni gerencia.
--   14. El ambito de un mes CERRADO sale del `supervisor_id` SELLADO, no del
--       equipo de HOY. Es la mejor idea del conjunto y era la unica sin una sola
--       asercion: sin ella, un cambio de equipo en noviembre moveria agosto.
--   15. Deny-by-default medido con PRIVILEGIOS de verdad (`set role`), no solo
--       con `auth.uid()` conmutado: las tres tablas del cierre sin un solo grant
--       y sin una sola policy, para los tres roles de la Data API.
--
-- ⚠️ SOBRE EL RELOJ. Varias reglas solo se pueden observar ciertos dias del mes
-- (la ventana del mes pasado solo esta cerrada del 1 al 9), asi que esos bloques
-- empujan la ventana sustituyendo `private.cierre_mes_ventana_desde` y la
-- restauran desde `pg_get_functiondef` — nunca con una copia del cuerpo escrita
-- aqui, que se quedaria vieja. La ARITMETICA real se prueba entera en el 9. Los
-- cierres de prueba se deshacen con un `raise` dentro de una subtransaccion: el
-- oraculo no deja meses sellados a medias para los bloques siguientes.
--
-- ⚠️ COMPROBADO CON MUTANTES (15/08). Una prueba que solo puede ejercitar una de
-- sus dos ramas segun el dia no demuestra nada por si sola, asi que cada arreglo
-- se rompio a proposito para ver el oraculo en rojo. **DIEZ mutantes, los diez
-- caen**, con corrida de control sin mutar en verde: candado del dia 10, freno
-- del ciclo, suelo de `cierre_mes_pendiente`, guardia del orden, subtransaccion
-- por mes, cerrojo del periodo, candado de metas, trigger de metas, el ambito del
-- mes cerrado, y un `grant` de mas sobre una tabla del cierre.
--
-- Dos de ellos cazaron cosas que ni escribiendo ni auditando aparecieron:
--   · un arreglo TAPABA el test de otro (la subtransaccion se comia la excepcion
--     que otra prueba usaba de señal, y seguia verde con el freno quitado);
--   · el banco MENTIA por omision: no daba `usage` de los esquemas a
--     `authenticated`, asi que toda prueba de «esta tabla no se lee» moria en el
--     ESQUEMA y tapaba por completo los grants de la TABLA.
-- El cerrojo es el unico que no cae por el oraculo sino por el postflight de su
-- migracion: una carrera necesita dos sesiones a la vez y esto corre en una.
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
  v_s2 uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'; -- supervisor AJENO (bloque 14)
  v_v uuid := '33333333-3333-4333-8333-333333333333'; -- vendedor
  v_cli uuid := '44444444-4444-4444-8444-444444444444'; -- cliente
  v_coord uuid := '88888888-8888-4888-8888-888888888888'; -- coordinador
  v_dir uuid := '99999999-9999-4999-8999-999999999999';   -- directorio (lector global)
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
  v_jun date := (date_trunc('month', now() at time zone 'America/Lima') - interval '8 months')::date;
  v_jul date := (date_trunc('month', now() at time zone 'America/Lima') - interval '7 months')::date;
  v_r jsonb;
  v_n integer;
  v_num numeric;
  v_pend numeric;
  -- Bloques 9-12 (candado del dia 10, ciclo automatico y aviso).
  v_rec record;
  v_e jsonb;
  v_dia integer;
  v_esperados integer;
  v_def text;
  v_def2 text;
  v_quien uuid;
  v_rol text;
  v_auto boolean;
  v_por uuid;
  v_m1 date;  -- el mes pasado: el unico cuya ventana puede seguir cerrada
  v_m4 date;
  v_m5 date;
  v_m9 date;
  v_mp_m1 uuid := '55555555-5555-4555-8555-555555555561';
  v_mp_m4 uuid := '55555555-5555-4555-8555-555555555564';
  v_mp_m5 uuid := '55555555-5555-4555-8555-555555555565';
  v_mp_m9 uuid := '55555555-5555-4555-8555-555555555569';
begin
  -- ── Siembra ───────────────────────────────────────────────────────────────
  insert into public.perfiles (id, nombre_completo, rol, activo) values
    (v_g, 'GERENTE DE PRUEBA', 'admin', true),
    (v_s, 'SUPERVISOR DE PRUEBA', 'comercial', true),
    (v_v, 'VENDEDOR DE PRUEBA', 'comercial', true),
    (v_cli, 'CLIENTE DE PRUEBA', 'cliente', true),
    (v_coord, 'COORDINADOR DE PRUEBA', 'comercial', true),
    (v_dir, 'DIRECTORIO DE PRUEBA', 'admin', true),
    (v_s2, 'SUPERVISOR AJENO DE PRUEBA', 'comercial', true);

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
    v_ago date := (date_trunc('month', now() at time zone 'America/Lima') - interval '6 months')::date;
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

  -- ── 9. La ventana abre el dia 10 del mes siguiente ────────────────────────
  -- DETERMINISTA: aritmetica pura, sin reloj. Corra el dia que corra da lo
  -- mismo. Es a proposito el bloque mas exhaustivo, porque la regla del candado
  -- se puede torcer de tres formas —longitud del mes, salto de año y ZONA— y las
  -- tres se ven aqui y en ningun otro sitio.
  for v_rec in
    select * from (values
      ('2026-01-01'::date, '2026-02-10'::date),  -- mes de 31
      ('2026-04-01'::date, '2026-05-10'::date),  -- mes de 30
      ('2026-02-01'::date, '2026-03-10'::date),  -- febrero de 28
      ('2024-02-01'::date, '2024-03-10'::date),  -- febrero bisiesto
      ('2026-12-01'::date, '2027-01-10'::date)   -- salto de año
    ) t(mes, esperado)
  loop
    if (private.cierre_mes_ventana_desde(v_rec.mes)
        at time zone 'America/Lima')::date is distinct from v_rec.esperado then
      raise exception 'FALLO 9: la ventana de % abrio el %, no el %',
        v_rec.mes,
        (private.cierre_mes_ventana_desde(v_rec.mes) at time zone 'America/Lima')::date,
        v_rec.esperado;
    end if;
  end loop;

  -- El borde exacto, al segundo.
  if not ('2026-08-09 23:59:59'::timestamp at time zone 'America/Lima'
          < private.cierre_mes_ventana_desde('2026-07-01'::date)) then
    raise exception 'FALLO 9: la ventana ya estaba abierta el 9 a las 23:59:59 de Lima';
  end if;
  if not ('2026-08-10 00:00:00'::timestamp at time zone 'America/Lima'
          >= private.cierre_mes_ventana_desde('2026-07-01'::date)) then
    raise exception 'FALLO 9: la ventana no abrio el 10 a las 00:00 de Lima';
  end if;

  -- ⚠️ Y NO abre a medianoche UTC, que es cinco horas antes que en Lima. Este
  -- proyecto ya pago una vez el bug de las fechas en UTC; aqui costaria que un
  -- mes se sellara la tarde del dia 9, con la ventana de ajuste todavia abierta.
  if '2026-08-10 00:00:00+00'::timestamptz
     >= private.cierre_mes_ventana_desde('2026-07-01'::date) then
    raise exception 'FALLO 9: la ventana abre a medianoche UTC, no a medianoche de Lima';
  end if;

  -- ── 10. EL CANDADO: nadie sella un mes antes del dia 10 ───────────────────
  -- Este estado SOLO existe los dias 1..9: un mes que termino hace mas de diez
  -- dias siempre es cerrable, asi que los dias 10..31 no hay nada que rechazar.
  -- La prueba mira el calendario y asevera la cara que hoy es cierta; las dos
  -- caras juntas son «se cierra si y solo si la ventana abrio».
  -- El cierre de prueba se DESHACE con un raise: el bloque no deja rastro.
  v_dia := extract(day from (now() at time zone 'America/Lima'))::int;
  v_m1  := (date_trunc('month', now() at time zone 'America/Lima') - interval '1 month')::date;
  perform set_config('test.uid', '', true);
  begin
    perform crm.cerrar_periodo(v_m1);
    raise exception using errcode = 'PT001', message = 'se dejo cerrar';
  exception
    when sqlstate '22023' then
      if position('antes del' in sqlerrm) = 0 then
        raise exception 'FALLO 10: % no se cerro, pero por otra razon — %', v_m1, sqlerrm;
      end if;
      if v_dia >= 10 then
        raise exception 'FALLO 10: el candado mordio el dia % del mes, con la ventana ya abierta', v_dia;
      end if;
      raise notice '  (bloque 10: hoy es dia % — probada la cara que RECHAZA)', v_dia;
    when sqlstate 'PT001' then
      if v_dia < 10 then
        raise exception 'FALLO 10: % se dejo cerrar el dia % del mes, dentro de la ventana de ajuste', v_m1, v_dia;
      end if;
      raise notice '  (bloque 10: hoy es dia % — probada la cara que ACEPTA)', v_dia;
  end;

  -- Y AHORA LA OTRA CARA, EL DIA QUE SEA. Lo de arriba solo puede ejercitar una
  -- de las dos ramas segun el calendario, y la que de verdad importa —la que
  -- RECHAZA— solo existe los dias 1..9. Asi que se empuja la ventana al futuro y
  -- se mira si `cerrar_periodo` obedece.
  --
  -- ⚠️ Esto NO es un calco que miente. La ARITMETICA real ya quedo probada
  -- exhaustivamente en el bloque 9; lo unico que se comprueba aqui es que
  -- `cerrar_periodo` de verdad consulta la ventana y compara en el sentido
  -- correcto. El original se guarda con `pg_get_functiondef` y se restaura al
  -- salir, para que no haya una copia del cuerpo aqui que se quede vieja.
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'cierre_mes_ventana_desde';
  if v_def is null then
    raise exception 'FALLO 10: no existe private.cierre_mes_ventana_desde';
  end if;

  execute $stub$
    create or replace function private.cierre_mes_ventana_desde(p_periodo date)
    returns timestamptz language sql stable set search_path = ''
    as $x$ select pg_catalog.now() + interval '1 year' $x$
  $stub$;

  begin
    perform set_config('test.uid', '', true);
    perform crm.cerrar_periodo(v_m1);
    execute v_def;
    raise exception 'FALLO 10: con la ventana en el futuro, el mes se dejo cerrar igual';
  exception
    when sqlstate '22023' then
      if position('antes del' in sqlerrm) = 0 then
        execute v_def;
        raise exception 'FALLO 10: rechazo, pero no por el candado — %', sqlerrm;
      end if;
  end;

  -- ── 10bis. GERENCIA CIERRA A MANO, y la foto lo dice ──────────────────────
  -- ⚠️ Hasta aqui el oraculo solo habia ejercido el camino AUTOMATICO (sin uid).
  -- Una suite sin un caso POSITIVO de la accion principal no prueba que la
  -- accion funcione — es la leccion que costo descubrir que guardar metas era
  -- imposible desde que existia la pantalla, con 732 pruebas en verde encima.
  -- Aqui gerencia cierra de verdad, y se comprueba que la autoria queda escrita.
  -- Se empuja la ventana al PASADO para que el caso exista cualquier dia, y todo
  -- va dentro de una subtransaccion que se deshace: el mes no queda sellado.
  execute $stub$
    create or replace function private.cierre_mes_ventana_desde(p_periodo date)
    returns timestamptz language sql stable set search_path = ''
    as $x$ select pg_catalog.now() - interval '1 year' $x$
  $stub$;
  begin
    perform set_config('test.uid', v_g::text, true);
    v_r := crm.cerrar_periodo(v_m1);
    if (v_r->>'ok')::boolean is not true then
      raise exception 'FALLO 10bis: gerencia no pudo cerrar un mes a mano — %', v_r;
    end if;
    if (v_r->>'automatico')::boolean is not false then
      raise exception 'FALLO 10bis: un cierre hecho por gerencia se declaro automatico — %', v_r;
    end if;
    select pc.automatico, pc.cerrado_por into v_auto, v_por
    from crm.periodos_cerrados pc where pc.periodo = v_m1;
    if v_auto is not false or v_por is distinct from v_g then
      raise exception 'FALLO 10bis: la foto no guardo la autoria (automatico=%, cerrado_por=%)', v_auto, v_por;
    end if;
    raise exception using errcode = 'PT002', message = 'deshacer el cierre de prueba';
  exception when sqlstate 'PT002' then null;
  end;

  -- Restaurar SIEMPRE: el resto del oraculo mide contra la ventana de verdad.
  execute v_def;
  if (private.cierre_mes_ventana_desde('2026-07-01'::date)
      at time zone 'America/Lima')::date is distinct from '2026-08-10'::date then
    raise exception 'FALLO 10: la ventana no quedo restaurada tras la prueba';
  end if;
  -- Y el cierre de prueba se deshizo de verdad.
  if exists (select 1 from crm.periodos_cerrados where periodo = v_m1) then
    raise exception 'FALLO 10bis: el cierre de prueba de gerencia no se deshizo';
  end if;

  -- ── Siembra del backlog ───────────────────────────────────────────────────
  -- Tres meses que deben cierre, TODOS posteriores al ultimo sellado (que a
  -- estas alturas es el mes -6): dos viejos, cuya ventana abrio hace mucho, y el
  -- mes pasado, cuya ventana depende del calendario. Que esten por encima del
  -- sello no es casualidad del fixture: desde el guardia 2quater, un mes por
  -- DEBAJO no es candidato a nada — y eso lo prueba el bloque 13.
  v_m1 := (date_trunc('month', now() at time zone 'America/Lima') - interval '1 month')::date;
  v_m4 := (date_trunc('month', now() at time zone 'America/Lima') - interval '4 months')::date;
  v_m5 := (date_trunc('month', now() at time zone 'America/Lima') - interval '5 months')::date;
  insert into crm.meta_periodos (id, periodo, revision, publicada_en) values
    (v_mp_m5, v_m5, 1, now()),
    (v_mp_m4, v_m4, 1, now()),
    (v_mp_m1, v_m1, 1, now());

  -- ── 12a. Los TRES estados del aviso, sin depender del calendario ──────────
  -- El pendiente mas antiguo es el mes -5, con metas y sin sellar. Empujando su
  -- ventana se recorren los tres estados el dia que sea. Van ANTES del ciclo
  -- porque despues no queda ningun pendiente que mirar.
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'cierre_mes_ventana_desde';

  perform set_config('test.uid', v_g::text, true);
  if (crm.cierre_mes_estado_fn()->'pendiente'->>'mes') is distinct from to_char(v_m5, 'YYYY-MM') then
    raise exception 'FALLO 12a: el pendiente deberia ser el mes mas antiguo sin sellar (%) y es %',
      to_char(v_m5, 'YYYY-MM'), crm.cierre_mes_estado_fn()->'pendiente';
  end if;

  -- (1) Ventana aun cerrada → todavia se puede corregir.
  execute $stub$
    create or replace function private.cierre_mes_ventana_desde(p_periodo date)
    returns timestamptz language sql stable set search_path = ''
    as $x$ select pg_catalog.now() + interval '3 days' $x$
  $stub$;
  if (crm.cierre_mes_estado_fn()->'pendiente'->>'estado') is distinct from 'en_ventana' then
    raise exception 'FALLO 12a: con la ventana sin abrir el estado deberia ser «en_ventana» y es %',
      crm.cierre_mes_estado_fn()->'pendiente'->>'estado';
  end if;

  -- (2) ⚠️ EL DIA DE GRACIA. La ventana abre a las 00:00 y el ciclo corre a las
  -- 09:20: sin este estado intermedio, la lectura literal («ya paso la fecha y
  -- sigue abierto») gritaria «atascado» nueve horas cada dia 10, un mes tras
  -- otro, con todo funcionando. Una alarma que suena cuando no pasa nada deja de
  -- mirarse, y entonces tampoco se ve la vez que si pasa.
  execute $stub$
    create or replace function private.cierre_mes_ventana_desde(p_periodo date)
    returns timestamptz language sql stable set search_path = ''
    as $x$ select pg_catalog.now() - interval '2 hours' $x$
  $stub$;
  if (crm.cierre_mes_estado_fn()->'pendiente'->>'estado') is distinct from 'hoy' then
    raise exception 'FALLO 12a: con la ventana abierta hace 2 horas el estado deberia ser «hoy» y es %',
      crm.cierre_mes_estado_fn()->'pendiente'->>'estado';
  end if;

  -- (3) LA ALARMA. Paso un dia entero: al menos un ciclo tuvo su turno y no lo
  -- hizo. Sin esto, un cron roto es invisible — nadie mira los logs.
  execute $stub$
    create or replace function private.cierre_mes_ventana_desde(p_periodo date)
    returns timestamptz language sql stable set search_path = ''
    as $x$ select pg_catalog.now() - interval '2 days' $x$
  $stub$;
  if (crm.cierre_mes_estado_fn()->'pendiente'->>'estado') is distinct from 'atascado' then
    raise exception 'FALLO 12a: con dos dias de retraso la alarma no sono — un ciclo atascado quedaria invisible';
  end if;

  -- (4) Y con la ventana cerrada el CICLO se calla, no revienta. Es una prueba
  -- propia del ciclo, no la misma de arriba: `cerrar_periodo` tambien rechazaria,
  -- pero como EXCEPCION, y el cron acabaria en rojo todos los dias del 1 al 9 de
  -- cada mes. Un cron que falla a diario deja de mirarse.
  execute $stub$
    create or replace function private.cierre_mes_ventana_desde(p_periodo date)
    returns timestamptz language sql stable set search_path = ''
    as $x$ select pg_catalog.now() + interval '1 year' $x$
  $stub$;
  perform set_config('test.uid', '', true);
  v_r := crm.ciclo_cierre_mes();
  if (v_r->>'cerrados')::int <> 0 then
    raise exception 'FALLO 12a: con la ventana cerrada el ciclo cerro % meses', v_r->>'cerrados';
  end if;
  -- ⚠️ Y SIN FALLO. Mirar solo el contador no basta: desde que cada mes va en su
  -- subtransaccion, un ciclo SIN freno intentaria cerrar, `cerrar_periodo` lo
  -- rechazaria, y el ciclo se comeria la excepcion devolviendo igualmente
  -- `cerrados: 0`. El contador no distingue «no lo intento» de «lo intento y
  -- fallo», y son dos mundos: el segundo deja el cron en rojo del 1 al 9 de cada
  -- mes. (Lo cazo un mutante: al quitar el freno, esta prueba seguia en verde.)
  if (v_r->>'ok')::boolean is not true or v_r->'fallo' <> 'null'::jsonb then
    raise exception 'FALLO 12a: con la ventana cerrada el ciclo lo INTENTO y fallo, en vez de callarse — %', v_r;
  end if;

  execute v_def;
  if (private.cierre_mes_ventana_desde('2026-07-01'::date)
      at time zone 'America/Lima')::date is distinct from '2026-08-10'::date then
    raise exception 'FALLO 12a: la ventana no quedo restaurada tras las pruebas';
  end if;

  -- ── 11bis. Si un mes falla, lo ya sellado SOBREVIVE ───────────────────────
  -- ⚠️ El fallo mas silencioso de los tres que encontro la auditoria. El bucle
  -- del ciclo es plpgsql, o sea UNA transaccion: si el mes M+1 revienta, sin
  -- subtransaccion se tira TAMBIEN el sellado de M, que habia ido bien. Y como
  -- estos fallos son deterministas (un dato torcido no se arregla solo), el
  -- sistema se quedaria atascado para siempre rehaciendo y descartando el mismo
  -- trabajo bueno cada dia — lo contrario exacto de la auto-reparacion que el
  -- ciclo presume.
  --
  -- Se fabrica un mes que revienta (el -4) dejando sano el anterior (el -5), y
  -- se comprueba que el -5 queda sellado. Todo dentro de una subtransaccion que
  -- se deshace: el bloque 11 mide despues contra el mundo intacto.
  select pg_get_functiondef(p.oid) into v_def2
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'peso_referido_conversion';

  execute format($fmt$
    create or replace function private.peso_referido_conversion(p_mes date)
    returns numeric language plpgsql stable set search_path = ''
    as $x$ begin
      if p_mes = %L::date then
        raise exception 'dato torcido de prueba en %%', p_mes;
      end if;
      return 0.15;
    end $x$
  $fmt$, v_m4);

  begin
    perform set_config('test.uid', '', true);
    v_r := crm.ciclo_cierre_mes();

    if (v_r->>'cerrados')::int <> 1 then
      raise exception 'FALLO 11bis: se esperaba 1 mes sellado antes del fallo y hubo % — %',
        v_r->>'cerrados', v_r;
    end if;
    if (v_r->>'ok')::boolean is not false
       or (v_r->'fallo'->>'periodo') is distinct from to_char(v_m4, 'YYYY-MM') then
      raise exception 'FALLO 11bis: el ciclo no reporto el mes que fallo — %', v_r;
    end if;
    -- LA ASERCION QUE IMPORTA: el mes bueno sigue sellado.
    if not exists (select 1 from crm.periodos_cerrados where periodo = v_m5) then
      raise exception 'FALLO 11bis: el fallo de un mes se llevo por delante el sellado del anterior';
    end if;
    -- Y el que fallo no dejo nada a medias.
    if exists (select 1 from crm.periodos_cerrados where periodo = v_m4)
       or exists (select 1 from crm.cierre_mes_vendedor where periodo = v_m4) then
      raise exception 'FALLO 11bis: el mes que fallo dejo rastro';
    end if;

    raise exception using errcode = 'PT003', message = 'deshacer la prueba del fallo';
  exception when sqlstate 'PT003' then null;
  end;

  execute v_def2;
  if exists (select 1 from crm.periodos_cerrados where periodo in (v_m5, v_m4)) then
    raise exception 'FALLO 11bis: la prueba del fallo no se deshizo';
  end if;

  -- ── 11. El ciclo cierra solo, en orden y sin repetir ──────────────────────
  -- El mes pasado solo entra si su ventana (el dia 10 de ESTE mes) ya abrio.
  v_esperados := 2 + case when v_dia >= 10 then 1 else 0 end;

  perform set_config('test.uid', '', true);
  v_r := crm.ciclo_cierre_mes();
  if (v_r->>'cerrados')::int is distinct from v_esperados then
    raise exception 'FALLO 11: el ciclo cerro % meses, se esperaban % (hoy es dia %) — %',
      v_r->>'cerrados', v_esperados, v_dia, v_r;
  end if;
  if (v_r->>'ok')::boolean is not true or v_r->'fallo' <> 'null'::jsonb then
    raise exception 'FALLO 11: el ciclo reporto un fallo que no existio — %', v_r;
  end if;

  -- Los dos viejos quedaron sellados, y sellados COMO AUTOMATICOS (sin autor):
  -- si el ciclo firmara con un uid, la foto diria que lo cerro una persona.
  select count(*) into v_n
  from crm.periodos_cerrados
  where periodo in (v_m5, v_m4) and automatico and cerrado_por is null;
  if v_n <> 2 then
    raise exception 'FALLO 11: los meses viejos no quedaron cerrados por el ciclo (n=%)', v_n;
  end if;

  -- Y EN ORDEN: el mes -5 antes que el -4. Que los dos acaben sellados no
  -- demuestra el orden; el instante del sello, si.
  if (select pc.cerrado_en from crm.periodos_cerrados pc where pc.periodo = v_m5)
     > (select pc.cerrado_en from crm.periodos_cerrados pc where pc.periodo = v_m4) then
    raise exception 'FALLO 11: el ciclo sello el mes -4 antes que el -5';
  end if;

  -- Y el mes pasado, exactamente segun su ventana.
  select count(*) into v_n from crm.periodos_cerrados where periodo = v_m1;
  if v_n <> (case when v_dia >= 10 then 1 else 0 end) then
    raise exception 'FALLO 11: el mes pasado quedo % el dia % del mes',
      case when v_n = 1 then 'cerrado' else 'abierto' end, v_dia;
  end if;

  -- Idempotente: correrlo otra vez el mismo dia no cierra nada mas. Es lo que
  -- permite engancharlo a un cron DIARIO en vez de a una fecha, y que un fallo
  -- del dia 10 se repare solo el 11.
  v_r := crm.ciclo_cierre_mes();
  if (v_r->>'cerrados')::int <> 0 then
    raise exception 'FALLO 11: el ciclo volvio a cerrar meses en la segunda vuelta — %', v_r;
  end if;

  -- Y no lo dispara NINGUNA persona — tampoco gerencia. El ciclo es del reloj;
  -- la puerta manual de gerencia es `crm.cerrar_periodo`, mes a mes. Se prueban
  -- los cinco roles: probar solo el vendedor deja sin cubrir justo a los que
  -- estan cerca del permiso.
  foreach v_quien in array array[v_v, v_s, v_g, v_coord, v_dir] loop
    begin
      perform set_config('test.uid', v_quien::text, true);
      perform crm.ciclo_cierre_mes();
      raise exception 'FALLO 11: % pudo disparar el ciclo de cierre a mano', v_quien;
    exception when sqlstate '42501' then null;
    end;
  end loop;

  -- ── 12b. El aviso, ya con el ciclo pasado ─────────────────────────────────
  perform set_config('test.uid', v_g::text, true);
  v_e := crm.cierre_mes_estado_fn();

  -- El mes en curso siempre dice cuando se sellara: es el aviso normal.
  if (v_e->'mes_en_curso'->>'cierra_el')::date
     is distinct from (v_m0 + interval '1 month' + interval '9 days')::date then
    raise exception 'FALLO 12b: el mes en curso dice que cierra el % — %',
      v_e->'mes_en_curso'->>'cierra_el', v_e;
  end if;
  if v_e->'ultimo_cerrado'->>'mes' is null then
    raise exception 'FALLO 12b: no reporta ningun mes cerrado y acaban de cerrarse varios — %', v_e;
  end if;

  -- Tras el ciclo no queda pendiente ninguno cuya ventana haya abierto: si el
  -- dia es >= 10 no queda nada; si es < 10, queda el mes pasado y en ventana.
  if v_dia >= 10 then
    if v_e->'pendiente' <> 'null'::jsonb then
      raise exception 'FALLO 12b: queda un mes pendiente despues del ciclo — %', v_e->'pendiente';
    end if;
  else
    if (v_e->'pendiente'->>'mes') is distinct from to_char(v_m1, 'YYYY-MM')
       or (v_e->'pendiente'->>'estado') is distinct from 'en_ventana' then
      raise exception 'FALLO 12b: el mes pasado deberia estar pendiente y en ventana el dia % — %', v_dia, v_e->'pendiente';
    end if;
    if (v_e->'pendiente'->>'dias_para_cierre')::int <> 10 - v_dia then
      raise exception 'FALLO 12b: faltan % dias segun la funcion y % segun el calendario',
        v_e->'pendiente'->>'dias_para_cierre', 10 - v_dia;
    end if;
  end if;

  -- El aviso es del reloj, pero no es publico.
  begin
    perform set_config('test.uid', '', true);
    perform crm.cierre_mes_estado_fn();
    raise exception 'FALLO 12b: el estado del cierre se leyo sin identidad';
  exception when sqlstate '42501' then null;
  end;

  -- Lo ven los CUATRO roles que tienen pantalla, y ven LO MISMO: es estado de
  -- reloj, no datos de nadie. Si difiriera por rol, algo se habria colado.
  -- El coordinador entra a proposito: `crm.cumplimiento_metas_fn` le deja ver un
  -- mes cerrado, asi que negarle el aviso le dejaria un banner roto.
  foreach v_quien in array array[v_v, v_s, v_g, v_coord, v_dir] loop
    perform set_config('test.uid', v_quien::text, true);
    v_r := crm.cierre_mes_estado_fn();
    if v_r->'mes_en_curso' is distinct from v_e->'mes_en_curso'
       or v_r->'pendiente' is distinct from v_e->'pendiente'
       or v_r->'ultimo_cerrado' is distinct from v_e->'ultimo_cerrado' then
      raise exception 'FALLO 12b: el aviso le dice otra cosa a % — % vs %',
        v_quien, v_r, v_e;
    end if;
  end loop;

  -- ── 13. Un mes que aparece POR DETRAS de lo ya sellado no se sella ────────
  -- ⚠️ La puerta que el candado del dia 10 no cerraba, y que el auditor encontro:
  -- `crm.publicar_metas_vendedores` acepta CUALQUIER mes (solo exige dia 1; no
  -- mira `crm.periodos_cerrados`). Asi que gerencia puede publicar hoy las metas
  -- de un mes viejo que nunca las tuvo, y ese mes pasaria a «deber un cierre»
  -- con su ventana abierta desde hace meses. Sin este guardia, el CRON lo
  -- sellaria solo, por detras de meses ya pagados, y `private.saldar_ajustes` le
  -- cobraria deudas que tocaban al mes vivo. Nadie tendria que apretar nada.
  v_m9 := (date_trunc('month', now() at time zone 'America/Lima') - interval '9 months')::date;

  -- (0) EL ORIGEN. Publicar esas metas ya no se puede: el candado esta en la
  --     propia tabla, asi que cubre a cualquier escritor y no solo a la RPC.
  begin
    insert into crm.meta_periodos (id, periodo, revision, publicada_en)
    values (v_mp_m9, v_m9, 1, now());
    raise exception 'FALLO 13: se publicaron metas de un mes por debajo del ultimo sellado';
  exception when sqlstate '22023' then
    if position('ya esta cerrado' in sqlerrm) = 0 then
      raise exception 'FALLO 13: rechazo, pero no por el candado de metas — %', sqlerrm;
    end if;
  end;

  -- Ni moviendo una fila existente hacia atras, que es la misma jugada por otro
  -- camino.
  begin
    update crm.meta_periodos set periodo = v_m9 where id = v_mp_m1;
    raise exception 'FALLO 13: se movio una fila de metas por debajo del ultimo sellado';
  exception when sqlstate '22023' then null;
  end;

  -- (0bis) Pero la VENTANA DE AJUSTE sigue abierta: el mes que acaba de terminar
  --     y aun no esta sellado admite metas nuevas. Si esto se rompiera, del 1 al
  --     10 no se podrian corregir las metas del mes que se va a pagar — que es
  --     justo para lo que existe la ventana.
  if v_dia < 10 then
    insert into crm.meta_periodos (id, periodo, revision, publicada_en)
    values ('55555555-5555-4555-8555-55555555556a', v_m1, 2, now());
    delete from crm.meta_periodos where id = '55555555-5555-4555-8555-55555555556a';
  end if;

  -- (1) Y para una fila que YA EXISTIERA —una anterior al candado—, las dos
  --     puertas del cierre siguen siendo las que impiden el daño. Se siembra con
  --     el trigger apagado, que es la forma exacta de modelar «esto ya estaba».
  alter table crm.meta_periodos disable trigger trg_meta_periodos_00_no_bajo_sellado;
  insert into crm.meta_periodos (id, periodo, revision, publicada_en)
  values (v_mp_m9, v_m9, 1, now());
  alter table crm.meta_periodos enable trigger trg_meta_periodos_00_no_bajo_sellado;

  -- (a) No es candidato: el aviso no lo nombra.
  perform set_config('test.uid', v_g::text, true);
  if (crm.cierre_mes_estado_fn()->'pendiente'->>'mes') is not distinct from to_char(v_m9, 'YYYY-MM') then
    raise exception 'FALLO 13: un mes por detras del sello se ofrecio como pendiente';
  end if;

  -- (b) El ciclo lo IGNORA, y no falla por su culpa. Que ignore en vez de
  --     reventar importa: si fallara, el cron quedaria en rojo cada dia para
  --     siempre por unas metas retroactivas.
  perform set_config('test.uid', '', true);
  v_r := crm.ciclo_cierre_mes();
  if (v_r->>'cerrados')::int <> 0 or (v_r->>'ok')::boolean is not true then
    raise exception 'FALLO 13: el ciclo reacciono a unas metas retroactivas — %', v_r;
  end if;
  if exists (select 1 from crm.periodos_cerrados where periodo = v_m9) then
    raise exception 'FALLO 13: el ciclo sello un mes por detras de lo ya pagado';
  end if;

  -- (c) Y a mano tampoco. Ni gerencia ni el ciclo.
  begin
    perform set_config('test.uid', v_g::text, true);
    perform crm.cerrar_periodo(v_m9);
    raise exception 'FALLO 13: gerencia pudo sellar un mes por detras de lo ya pagado';
  exception when sqlstate '22023' then
    if position('ya esta cerrado y es posterior' in sqlerrm) = 0 then
      raise exception 'FALLO 13: rechazo, pero no por el guardia del orden — %', sqlerrm;
    end if;
  end;


  -- ── 14. El ambito de un mes CERRADO sale del sello, no del equipo de HOY ──
  -- ⚠️ Es la mejor idea de todo el conjunto y era la unica sin una sola
  -- asercion. En un mes ABIERTO, un supervisor ve a quien `vendedor_ids_visibles`
  -- dice que es suyo HOY. Si un mes CERRADO usara ese mismo criterio, bastaria
  -- un cambio de equipo en noviembre para que el agosto de ese supervisor
  -- cambiara de numero — la enfermedad exacta que el sello viene a curar, por la
  -- puerta de al lado.
  --
  -- El calco lo discrimina a proposito: `private.vendedor_ids_visibles` del banco
  -- devuelve el mismo vendedor para CUALQUIER 'supervisor', asi que si la lectura
  -- del mes cerrado se apoyara en el equipo vivo, el supervisor AJENO veria al
  -- vendedor. Solo el `supervisor_id` SELLADO lo deja fuera.
  --
  -- Se mide sobre v_jun, sellado en el bloque 1 con el vendedor bajo v_s — y a
  -- cuyo roster el bloque 2 ya le quito la fila, asi que la foto es lo unico que
  -- queda diciendo de quien era.
  if (select f.supervisor_id from crm.cierre_mes_vendedor f
      where f.periodo = v_jun and f.vendedor_id = v_v) is distinct from v_s then
    raise exception 'FALLO 14: la foto no sello el supervisor del vendedor';
  end if;

  -- (a) El supervisor QUE ERA sigue viendolo.
  perform set_config('test.uid', v_s::text, true);
  v_r := crm.conversion_mensual_fn(v_jun);
  if (v_r->'total'->>'analistas')::int < 1 then
    raise exception 'FALLO 14: el supervisor sellado no ve a su gente en el mes cerrado — %', v_r->'total';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(coalesce(v_r->'responsables','[]'::jsonb)) e
    where (e->>'vendedor_id')::uuid = v_v
  ) then
    raise exception 'FALLO 14: el vendedor no aparece bajo su supervisor sellado — %', v_r->'responsables';
  end if;

  -- (b) Y un supervisor AJENO no, aunque el equipo de hoy diga que si.
  perform set_config('test.uid', v_s2::text, true);
  v_r := crm.conversion_mensual_fn(v_jun);
  if (v_r->'total'->>'analistas')::int <> 0 then
    raise exception 'FALLO 14: un supervisor ajeno ve el mes cerrado de otro (el recorte sale del equipo de HOY, no del sello) — %', v_r->'total';
  end if;

  -- ── 15. Deny-by-default, medido con PRIVILEGIOS de verdad ────────────────
  -- Hasta aqui todos los gates se han probado con `auth.uid()` conmutado, que es
  -- la capa de la APLICACION. Esto es la otra: ponerse en la piel del rol de
  -- Postgres y comprobar que las tres tablas del cierre no se dejan tocar. Es lo
  -- que hace que «no tiene policies» pase de ser una afirmacion sobre el catalogo
  -- a una sobre una sesion.
  for v_rec in
    select unnest(array['crm.periodos_cerrados','crm.cierre_mes_vendedor','crm.ajustes_mes_cerrado']) as t
  loop
    for v_rol in select unnest(array['authenticated','anon','service_role']) loop
      -- (i) EL PRIVILEGIO, exacto. Es la asercion que de verdad discrimina: la
      --     de abajo, por comportamiento, se contenta con que la lectura falle
      --     —y podria estar fallando en el ESQUEMA en vez de en la tabla—.
      --     Aqui se pregunta por la tabla y por las cuatro operaciones.
      if has_table_privilege(v_rol, v_rec.t, 'SELECT')
         or has_table_privilege(v_rol, v_rec.t, 'INSERT')
         or has_table_privilege(v_rol, v_rec.t, 'UPDATE')
         or has_table_privilege(v_rol, v_rec.t, 'DELETE') then
        raise exception 'FALLO 15: % tiene algun privilegio sobre % (deberia ser deny-by-default sin grants)', v_rol, v_rec.t;
      end if;
      -- Y cero policies: las tablas del cierre se leen SOLO via funciones.
      if (select count(*) from pg_policy p
          where p.polrelid = v_rec.t::regclass) <> 0 then
        raise exception 'FALLO 15: % tiene policies, y no deberia tener ninguna', v_rec.t;
      end if;

      -- (ii) Y el comportamiento, poniendose en la piel del rol.
      begin
        execute format('set local role %I', v_rol);
        execute format('select 1 from %s limit 1', v_rec.t);
        execute 'reset role';
        raise exception 'FALLO 15: % pudo LEER % directamente', v_rol, v_rec.t;
      exception
        when insufficient_privilege then execute 'reset role';
        when others then
          execute 'reset role';
          if sqlstate <> '42501' then
            raise exception 'FALLO 15: % fallo leyendo % por otra causa (%) — %', v_rol, v_rec.t, sqlstate, sqlerrm;
          end if;
      end;

      begin
        execute format('set local role %I', v_rol);
        execute format('delete from %s', v_rec.t);
        execute 'reset role';
        raise exception 'FALLO 15: % pudo BORRAR de %', v_rol, v_rec.t;
      exception
        when insufficient_privilege then execute 'reset role';
        when others then
          execute 'reset role';
          if sqlstate not in ('42501', 'P0409') then
            raise exception 'FALLO 15: % fallo borrando % por otra causa (%) — %', v_rol, v_rec.t, sqlstate, sqlerrm;
          end if;
      end;
    end loop;
  end loop;

  -- Y los helpers de `private` no son ejecutables desde la Data API, pese a que
  -- `authenticated` SI tiene `usage` sobre ese esquema: el revoke del grant de
  -- PUBLIC es la unica barrera, asi que se mide.
  if has_function_privilege('authenticated', 'private.cierre_mes_ventana_desde(date)', 'EXECUTE')
     or has_function_privilege('authenticated', 'private.cierre_mes_pendiente(date)', 'EXECUTE')
     or has_function_privilege('anon', 'private.cierre_mes_ventana_desde(date)', 'EXECUTE')
     or has_function_privilege('anon', 'private.cierre_mes_pendiente(date)', 'EXECUTE') then
    raise exception 'FALLO 15: un helper de private es alcanzable desde la Data API';
  end if;
  -- El ciclo lo dispara el reloj: `authenticated` no lo tiene ni concedido.
  if has_function_privilege('authenticated', 'crm.ciclo_cierre_mes()', 'EXECUTE')
     or has_function_privilege('anon', 'crm.ciclo_cierre_mes()', 'EXECUTE') then
    raise exception 'FALLO 15: crm.ciclo_cierre_mes quedo concedida a un rol de la Data API';
  end if;

  -- ── 16. La OTRA pantalla tambien se LLAMA ────────────────────────────────
  -- 🔴 EL AGUJERO MAS CARO DE ESTE CICLO. `20260815003742` reescribe DOS
  -- funciones de lectura, y este oraculo solo ejercitaba una. La otra
  -- —`crm.cumplimiento_metas_fn`, la pantalla de metas— tenia un `pd.pendiente`
  -- donde debia decir `pd.numerador`, y como plpgsql no valida el SQL de un
  -- cuerpo al crearlo, se creaba sin protestar y reventaba con 42703 en la
  -- PRIMERA llamada, para TODOS los roles. El oraculo daba 20/20 y la pantalla
  -- estaba muerta. Lo cazo el gate de RLS en una branch, no esto.
  --
  -- La leccion no es «faltaba un caso»: es que una funcion que se REEMPLAZA y no
  -- se LLAMA no esta probada, por muchos verdes que haya alrededor. Aqui se
  -- llama en sus dos mundos —mes abierto y mes cerrado— y por varios roles.
  foreach v_quien in array array[v_g, v_s, v_v] loop
    perform set_config('test.uid', v_quien::text, true);

    -- Mes CERRADO: sirve la foto.
    v_r := crm.cumplimiento_metas_fn(v_jun);
    if v_r is null then
      raise exception 'FALLO 16: cumplimiento_metas_fn devolvio NULL para un mes cerrado (rol %)', v_quien;
    end if;
    if (v_r->'cierre'->>'cerrado')::boolean is not true then
      raise exception 'FALLO 16: la pantalla de metas no declara cerrado un mes sellado — %', v_r->'cierre';
    end if;

    -- Mes ABIERTO: el camino vivo, que es donde estaba el error.
    v_r := crm.cumplimiento_metas_fn(v_m0);
    if v_r is null then
      raise exception 'FALLO 16: cumplimiento_metas_fn devolvio NULL para el mes vivo (rol %)', v_quien;
    end if;
    if (v_r->'cierre'->>'cerrado')::boolean is not false then
      raise exception 'FALLO 16: el mes vivo se declara cerrado en la pantalla de metas — %', v_r->'cierre';
    end if;
  end loop;

  -- ── 17. LA ESTRUCTURA QUE SERIALIZA publicar↔cerrar (20260815223000 +
  -- 20260815235500) ──
  -- La carrera necesita DOS sesiones y ningun test de una sesion la ve: lo que
  -- SI se vigila en cada ciclo es la ESTRUCTURA. ⚠️ SOBRE EL PROSRC SIN
  -- COMENTARIOS: un `-- perform pg_advisory…` comentado dejaba estos strpos en
  -- verde con la carrera abierta (falso positivo demostrado el 15/08).
  declare
    v_fuente text;
    v_quien2 text;
  begin
    -- a) Los TRES tenedores conservan el candado POR-MES (clave y aritmetica).
    foreach v_quien2 in array array[
      'private.trg_metas_no_bajo_mes_sellado()',
      'crm.cerrar_periodo(date)',
      'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'
    ] loop
      begin
        select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into strict v_fuente
        from pg_catalog.pg_proc p where p.oid = v_quien2::regprocedure;
      exception when undefined_function or no_data_found then
        raise exception 'FALLO 17: no existe % — si cambio de firma, actualizar este bloque', v_quien2;
      end;
      if strpos(v_fuente, $q$hashtext('crm.periodos_cerrados')$q$) = 0
         or strpos(v_fuente, $q$date '2000-01-01')::integer$q$) = 0 then
        raise exception 'FALLO 17: % perdio la clave o la aritmetica del candado por-mes (o quedo COMENTADO)', v_quien2;
      end if;
    end loop;
    -- b) Las DOS puertas toman ademas el candado GLOBAL, ANTES del por-mes.
    foreach v_quien2 in array array[
      'private.trg_metas_no_bajo_mes_sellado()',
      'crm.cerrar_periodo(date)'
    ] loop
      select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_fuente
      from pg_catalog.pg_proc p where p.oid = v_quien2::regprocedure;
      if strpos(v_fuente, $q$hashtext('crm.periodos_cerrados')::bigint$q$) = 0 then
        raise exception 'FALLO 17: % perdio el candado GLOBAL (o quedo comentado) — la carrera entre periodos distintos se reabre', v_quien2;
      end if;
      if strpos(v_fuente, $q$hashtext('crm.periodos_cerrados')::bigint$q$)
         > strpos(v_fuente, $q$date '2000-01-01')::integer$q$) then
        raise exception 'FALLO 17: en %, el candado GLOBAL quedo DESPUES del por-mes', v_quien2;
      end if;
    end loop;
    -- c) Y en el trigger, el candado ANTES de la lectura (el mutante barato).
    select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_fuente
    from pg_catalog.pg_proc p
    where p.oid = 'private.trg_metas_no_bajo_mes_sellado()'::regprocedure;
    if strpos(v_fuente, 'pg_advisory_xact_lock') > strpos(v_fuente, 'select max(pc.periodo)') then
      raise exception 'FALLO 17: el candado del trigger quedo DESPUES de la lectura';
    end if;
  end;

  raise notice 'ORACULO DEL CIERRE DE MES: 22/22 OK';
end;
$oraculo$;

rollback;

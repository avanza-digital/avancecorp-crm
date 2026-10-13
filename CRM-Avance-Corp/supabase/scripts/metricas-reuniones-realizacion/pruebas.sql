-- ORÁCULO de «"Realización" cuenta la cita realizada desde que se marca» — se ejecuta en el LABORATORIO (banco Docker
-- local), NUNCA contra producción, y no escribe nada.
--
-- La regla (decisiones D-11/Q2 y D-13 de Miguel, 2026-10-06; plan AVANCE-BACKEND-0610, bloque 2.2): una cita marcada
-- como realizada ANTES de su hora pactada entra al numerador Y al divisor del indicador «Realización» de Gerencia desde
-- que se marca («1 de 3» pasa a «1 de 4»). La cita pertenece al mes de su hora pactada; los periodos ya pasados no
-- cambian; las canceladas por el asesor ya vencidas siguen dentro del divisor; las reprogramadas y las canceladas por el
-- sistema vencidas siguen restándose; las citas futuras no realizadas siguen fuera; el núcleo `private.citas_episodios` y
-- los informes de conversiones («cita real» = realizada y hora vencida) NO cambian.
--
-- Este archivo NO se ejecuta a mano: `armar-ensayo.mjs` pega `antes.sql` (montaje y periodo pasado), la migración real (a
-- la que quita su `begin;`/`commit;`) y este oráculo dentro de UNA transacción que termina en `rollback`. Con
-- `--sin-migracion` pega el montaje y el oráculo sin la migración, y entonces TIENE que salir ROJO: es la medición del
-- defecto, y el motivo tiene que ser «la realizada anticipada no entra al divisor» (nunca un error de montaje).
--
-- Cómo mide. Toma la LÍNEA BASE de la puerta (ventana de hoy y ventana del mes en curso, con la misma función ya puesta),
-- siembra el escenario de hoy con tres vendedores sin otras citas, vuelve a pedir la puerta y compara: deltas en el
-- resumen, en modalidades y en orígenes; valores absolutos en las filas de los tres vendedores (son enteramente del
-- ensayo). Los deltas no dependen de los datos que ya tenga el laboratorio mientras ninguna cita preexistente tenga la
-- hora en el futuro (lo exige `antes.sql`).
--
-- Escenario de HOY (hora de Lima; `now()` es fijo en toda la transacción, así «+2 min» es futuro para la función):
--   Vendedor A: A1 no asistió (vencida, presencial) · A2 no asistió (vencida) · A3 pendiente vencida ·
--               A4 REALIZADA ANTES DE SU HORA (origen web)                            → «1 de 3» debe pasar a «1 de 4»
--   Vendedor B: B1 REALIZADA ANTES DE SU HORA, su única cita (origen whatsapp)        → hoy realizadas=1 y divisor=0
--               B2 realizada anticipada con hora en el MES SIGUIENTE                  → no aparece en el periodo actual
--   Vendedor C: C1 cancelada por el asesor (propia), vencida · C2 cancelada por OTRO asesor, vencida ·
--               C3 cancelada por el sistema, vencida · C4 reprogramada, vencida · C5 pendiente futura ·
--               C6 cancelada por el asesor, futura · C7 cancelada por el sistema, futura · C8 reprogramada, futura
--               (todas sin clasificar, origen campania)
--   Frontera (se siembra al FINAL, después de las mediciones anteriores, para no mover sus deltas):
--               F1 realizada con vence_en = now() EXACTO, de B                         → ya «debió ocurrir» (<=), con y sin migración

set local statement_timeout = '300s';

do $ensayo$
declare
  v_gerencia uuid := current_setting('ensayo.gerencia')::uuid;
  v_a uuid := current_setting('ensayo.vendedor_a')::uuid;
  v_b uuid := current_setting('ensayo.vendedor_b')::uuid;
  v_c uuid := current_setting('ensayo.vendedor_c')::uuid;
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_mes date := date_trunc('month', (now() at time zone 'America/Lima')::date)::date;
  v_mes_sig date := (date_trunc('month', (now() at time zone 'America/Lima')::date) + interval '1 month')::date;
  v_ini_hoy timestamptz := ((now() at time zone 'America/Lima')::date)::timestamp at time zone 'America/Lima';
  v_fin_hoy timestamptz := (((now() at time zone 'America/Lima')::date) + 1)::timestamp at time zone 'America/Lima';
  v_d0 jsonb; v_m0 jsonb; v_d1 jsonb; v_m1 jsonb;
  v_r0 jsonb; v_r1 jsonb; v_x jsonb; v_y jsonb; v_fa jsonb; v_fb jsonb; v_fc jsonb;
  v_pasado jsonb; v_pasado_antes jsonb;
  v_lead_a uuid; v_lead_a4 uuid; v_lead_b uuid; v_lead_c uuid;
  v_a1 uuid; v_a2 uuid; v_a3 uuid; v_a4 uuid; v_b1 uuid; v_b2 uuid; v_f1 uuid;
  v_c1 uuid; v_c2 uuid; v_c3 uuid; v_c4 uuid; v_c5 uuid; v_c6 uuid; v_c7 uuid; v_c8 uuid;
  v_n integer; v_m integer; v_k integer;
  v_ok boolean; v_detalle text;
  v_prosrc text; v_def text; v_norm text; v_sello text; v_sello_calc text; v_huella_ex text;
  v_declarada boolean; v_huella_ok boolean;
  v_debio boolean; v_realizada boolean; v_futura boolean; v_pendiente boolean;
begin
  perform set_config('ensayo.fallos', '0', true);
  perform set_config('ensayo.informe', '', true);
  perform set_config('ensayo.oks', '', true);
  perform set_config('ensayo.medidas', '', true);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 0. Línea base (la misma función que medirá después) y precondiciones del escenario
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_d0 := pg_temp.payload(v_gerencia, v_hoy, v_hoy);
  v_m0 := pg_temp.payload(v_gerencia, v_mes, v_hoy);
  if v_d0 is null or (v_d0 #>> '{resumen,pactadas}') is null or v_m0 is null then
    raise exception 'ENSAYO ABORTADO: la puerta no respondió la línea base (hoy=%, mes=%)', v_hoy, v_mes;
  end if;
  -- Las filas de los tres vendedores y de los tres orígenes del ensayo tienen que estar vacías en la línea base: de lo
  -- contrario los valores «absolutos» no serían del ensayo. `antes.sql` ya excluyó vendedores con citas; aquí se verifica.
  if pg_temp.fila(v_m0, 'responsables', 'responsable_id', v_a::text) is not null
     or pg_temp.fila(v_m0, 'responsables', 'responsable_id', v_b::text) is not null
     or pg_temp.fila(v_m0, 'responsables', 'responsable_id', v_c::text) is not null then
    raise exception 'ENSAYO ABORTADO: un vendedor del ensayo ya tiene citas en el mes en curso';
  end if;
  if pg_temp.fila(v_m0, 'origenes', 'origen', 'campania') is not null
     or pg_temp.fila(v_m0, 'origenes', 'origen', 'web') is not null
     or pg_temp.fila(v_m0, 'origenes', 'origen', 'whatsapp') is not null then
    raise exception 'ENSAYO ABORTADO: el laboratorio ya tiene citas del mes con origen campania, web o whatsapp';
  end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 1. Siembra del escenario de HOY (triggers apagados: se fija el estado final; los CHECK siguen activos)
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  execute 'set local session_replication_role = replica';
  v_lead_a  := pg_temp.lead(v_a, 'campania', 'ENSAYO Realizacion · A');
  v_lead_a4 := pg_temp.lead(v_a, 'web',      'ENSAYO Realizacion · A4 (web)');
  v_lead_b  := pg_temp.lead(v_b, 'whatsapp', 'ENSAYO Realizacion · B (whatsapp)');
  v_lead_c  := pg_temp.lead(v_c, 'campania', 'ENSAYO Realizacion · C');
  v_a1 := pg_temp.cita(v_lead_a,  v_a, 'A1 no asistio, vencida, presencial', now() - interval '8 minutes', 'no_show', 'presencial');
  v_a2 := pg_temp.cita(v_lead_a,  v_a, 'A2 no asistio, vencida',             now() - interval '7 minutes', 'no_show');
  v_a3 := pg_temp.cita(v_lead_a,  v_a, 'A3 pendiente, vencida',              now() - interval '6 minutes', 'pendiente');
  v_a4 := pg_temp.cita(v_lead_a4, v_a, 'A4 REALIZADA ANTES DE SU HORA',      now() + interval '2 minutes', 'completada');
  v_b1 := pg_temp.cita(v_lead_b,  v_b, 'B1 REALIZADA ANTES DE SU HORA (unica)', now() + interval '3 minutes', 'completada');
  v_b2 := pg_temp.cita(v_lead_b,  v_b, 'B2 realizada anticipada del MES SIGUIENTE',
                       ((v_mes_sig + 1)::timestamp at time zone 'America/Lima') + interval '10 hours', 'completada');
  v_c1 := pg_temp.cita(v_lead_c, v_c, 'C1 cancelada por el asesor (propia), vencida', now() - interval '5 minutes', 'cancelada', 'sin_clasificar', 'asesor', v_c);
  v_c2 := pg_temp.cita(v_lead_c, v_c, 'C2 cancelada por OTRO asesor, vencida',        now() - interval '4 minutes', 'cancelada', 'sin_clasificar', 'asesor', v_a);
  v_c3 := pg_temp.cita(v_lead_c, v_c, 'C3 cancelada por el sistema, vencida',         now() - interval '3 minutes', 'cancelada', 'sin_clasificar', 'sistema');
  v_c4 := pg_temp.cita(v_lead_c, v_c, 'C4 reprogramada, vencida',                     now() - interval '2 minutes', 'reprogramada', 'sin_clasificar');
  v_c5 := pg_temp.cita(v_lead_c, v_c, 'C5 pendiente, futura',                         now() + interval '4 minutes', 'pendiente', 'sin_clasificar');
  v_c6 := pg_temp.cita(v_lead_c, v_c, 'C6 cancelada por el asesor, futura',           now() + interval '5 minutes', 'cancelada', 'sin_clasificar', 'asesor', v_c);
  v_c7 := pg_temp.cita(v_lead_c, v_c, 'C7 cancelada por el sistema, futura',          now() + interval '6 minutes', 'cancelada', 'sin_clasificar', 'sistema');
  v_c8 := pg_temp.cita(v_lead_c, v_c, 'C8 reprogramada, futura',                      now() + interval '7 minutes', 'reprogramada', 'sin_clasificar');
  execute 'set local session_replication_role = origin';

  -- Anti-vacuidad del montaje: las 14 citas existen con la forma pedida.
  select count(*) into v_n from crm.tareas t
   where t.id in (v_a1, v_a2, v_a3, v_a4, v_b1, v_b2, v_c1, v_c2, v_c3, v_c4, v_c5, v_c6, v_c7, v_c8)
     and t.tipo = 'reunion' and t.activo;
  if v_n <> 14 then
    raise exception 'ENSAYO ABORTADO: la siembra de hoy no llegó (% de 14 citas)', v_n;
  end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 2. Medición: la puerta, como la Gerencia, en la ventana de hoy y en la del mes en curso
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_d1 := pg_temp.payload(v_gerencia, v_hoy, v_hoy);
  v_m1 := pg_temp.payload(v_gerencia, v_mes, v_hoy);
  v_r0 := v_d0 -> 'resumen';
  v_r1 := v_d1 -> 'resumen';
  v_fa := pg_temp.fila(v_d1, 'responsables', 'responsable_id', v_a::text);
  v_fb := pg_temp.fila(v_d1, 'responsables', 'responsable_id', v_b::text);
  v_fc := pg_temp.fila(v_d1, 'responsables', 'responsable_id', v_c::text);

  -- ── 1. Tres vencidas + una realizada antes de su hora: divisor 3 → 4 (resumen, analista, modalidad, origen) ────────
  -- Resumen: se sembraron 13 citas en la ventana de hoy; las que deben entrar al divisor son las 7 vencidas (A1, A2, A3,
  -- C1, C2, C3, C4) MÁS las 2 realizadas anticipadas (A4, B1) = 9; menos C3 (sistema) y C4 (reprogramada) = 7.
  perform pg_temp.exigir('1-resumen-divisor',
    pg_temp.d(v_r1, v_r0, 'debieron_ocurrir') = 9 and pg_temp.d(v_r1, v_r0, 'divisor_realizacion') = 7
      and pg_temp.d(v_r1, v_r0, 'realizadas') = 2,
    format('la realizada anticipada no entra al divisor del resumen: Δdebieron_ocurrir=%s (esperado 9), Δdivisor_realizacion=%s (esperado 7), Δrealizadas=%s (esperado 2)',
      pg_temp.d(v_r1, v_r0, 'debieron_ocurrir'), pg_temp.d(v_r1, v_r0, 'divisor_realizacion'), pg_temp.d(v_r1, v_r0, 'realizadas')));
  perform pg_temp.exigir('1-resumen-otros',
    pg_temp.d(v_r1, v_r0, 'pactadas') = 13 and pg_temp.d(v_r1, v_r0, 'no_show') = 2
      and pg_temp.d(v_r1, v_r0, 'canceladas') = 3 and pg_temp.d(v_r1, v_r0, 'canceladas_sistema') = 2
      and pg_temp.d(v_r1, v_r0, 'reprogramadas') = 2 and pg_temp.d(v_r1, v_r0, 'canceladas_sistema_vencidas') = 1
      and pg_temp.d(v_r1, v_r0, 'reprogramadas_vencidas') = 1 and pg_temp.d(v_r1, v_r0, 'pendientes_cierre') = 1
      and pg_temp.d(v_r1, v_r0, 'programadas_futuras') = 1 and pg_temp.d(v_r1, v_r0, 'divisor_asistencia') = 4
      and pg_temp.d(v_r1, v_r0, 'no_concretadas') = 5,
    format('los demás contadores del resumen no se movieron como el escenario manda: antes [%s] después [%s]',
      pg_temp.txt(v_r0), pg_temp.txt(v_r1)));
  -- Coherencia del resumen tal como la exige la pantalla (metricas-reuniones.ts:135-139).
  perform pg_temp.exigir('1-resumen-coherencia',
    pg_temp.n(v_r1, 'divisor_realizacion') = pg_temp.n(v_r1, 'debieron_ocurrir') - pg_temp.n(v_r1, 'canceladas_sistema_vencidas') - pg_temp.n(v_r1, 'reprogramadas_vencidas')
      and pg_temp.n(v_r1, 'realizadas') <= pg_temp.n(v_r1, 'divisor_realizacion')
      and pg_temp.n(v_r1, 'divisor_asistencia') = pg_temp.n(v_r1, 'realizadas') + pg_temp.n(v_r1, 'no_show')
      and pg_temp.pct(v_r1, 'pct_realizacion') is not distinct from
          case when pg_temp.n(v_r1, 'divisor_realizacion') > 0
               then round(100.0 * pg_temp.n(v_r1, 'realizadas') / pg_temp.n(v_r1, 'divisor_realizacion'), 1) end,
    format('el resumen no cuadra consigo mismo: [%s]', pg_temp.txt(v_r1)));
  -- Analista A: la fila es enteramente del ensayo.
  perform pg_temp.exigir('1-responsable-A',
    v_fa is not null and pg_temp.n(v_fa, 'pactadas') = 4 and pg_temp.n(v_fa, 'debieron_ocurrir') = 4
      and pg_temp.n(v_fa, 'realizadas') = 1 and pg_temp.n(v_fa, 'no_show') = 2 and pg_temp.n(v_fa, 'pendientes_cierre') = 1
      and pg_temp.n(v_fa, 'programadas_futuras') = 0 and pg_temp.n(v_fa, 'canceladas_sistema_vencidas') = 0
      and pg_temp.n(v_fa, 'canceladas_ajenas_vencidas') = 0 and pg_temp.n(v_fa, 'reprogramadas_vencidas') = 0
      and pg_temp.n(v_fa, 'divisor_realizacion') = 4 and pg_temp.pct(v_fa, 'pct_realizacion') = 25.0,
    format('la realizada anticipada no entra al divisor del analista A (3 vencidas + 1 realizada antes de su hora debían dar «1 de 4», 25.0%%): [%s]', pg_temp.txt(v_fa)));
  -- Modalidades (deltas): presencial recibe A1; virtual recibe A2, A3, A4 y B1; sin clasificar recibe las ocho de C.
  v_x := pg_temp.fila(v_d1, 'modalidades', 'modalidad', 'presencial');
  v_y := pg_temp.fila(v_d0, 'modalidades', 'modalidad', 'presencial');
  perform pg_temp.exigir('1-modalidad-presencial',
    pg_temp.d(v_x, v_y, 'pactadas') = 1 and pg_temp.d(v_x, v_y, 'debieron_ocurrir') = 1 and pg_temp.d(v_x, v_y, 'realizadas') = 0
      and pg_temp.d(v_x, v_y, 'no_show') = 1 and pg_temp.d(v_x, v_y, 'divisor_realizacion') = 1,
    format('la modalidad presencial no se movió como manda el escenario: antes [%s] después [%s]', pg_temp.txt(v_y), pg_temp.txt(v_x)));
  v_x := pg_temp.fila(v_d1, 'modalidades', 'modalidad', 'virtual');
  v_y := pg_temp.fila(v_d0, 'modalidades', 'modalidad', 'virtual');
  perform pg_temp.exigir('1-modalidad-virtual',
    pg_temp.d(v_x, v_y, 'pactadas') = 4 and pg_temp.d(v_x, v_y, 'debieron_ocurrir') = 4 and pg_temp.d(v_x, v_y, 'realizadas') = 2
      and pg_temp.d(v_x, v_y, 'no_show') = 1 and pg_temp.d(v_x, v_y, 'pendientes_cierre') = 1
      and pg_temp.d(v_x, v_y, 'divisor_realizacion') = 4 and pg_temp.d(v_x, v_y, 'canceladas_sistema_vencidas') = 0
      and pg_temp.d(v_x, v_y, 'reprogramadas_vencidas') = 0,
    format('la realizada anticipada no entra al divisor de la modalidad virtual (Δdebieron_ocurrir=%s y Δdivisor=%s, esperados 4 y 4): antes [%s] después [%s]',
      pg_temp.d(v_x, v_y, 'debieron_ocurrir'), pg_temp.d(v_x, v_y, 'divisor_realizacion'), pg_temp.txt(v_y), pg_temp.txt(v_x)));
  v_x := pg_temp.fila(v_d1, 'modalidades', 'modalidad', 'sin_clasificar');
  v_y := pg_temp.fila(v_d0, 'modalidades', 'modalidad', 'sin_clasificar');
  perform pg_temp.exigir('1-modalidad-sin_clasificar',
    pg_temp.d(v_x, v_y, 'pactadas') = 8 and pg_temp.d(v_x, v_y, 'debieron_ocurrir') = 4 and pg_temp.d(v_x, v_y, 'realizadas') = 0
      and pg_temp.d(v_x, v_y, 'canceladas') = 3 and pg_temp.d(v_x, v_y, 'reprogramadas') = 2
      and pg_temp.d(v_x, v_y, 'canceladas_sistema_vencidas') = 1 and pg_temp.d(v_x, v_y, 'reprogramadas_vencidas') = 1
      and pg_temp.d(v_x, v_y, 'divisor_realizacion') = 2 and pg_temp.d(v_x, v_y, 'pendientes_cierre') = 0,
    format('la modalidad sin clasificar no se movió como manda el escenario: antes [%s] después [%s]', pg_temp.txt(v_y), pg_temp.txt(v_x)));
  -- Coherencia de cada modalidad tal como la exige la pantalla (metricas-reuniones.ts:62-71).
  select bool_and(
           pg_temp.n(x, 'divisor_realizacion') = pg_temp.n(x, 'debieron_ocurrir') - pg_temp.n(x, 'canceladas_sistema_vencidas') - pg_temp.n(x, 'reprogramadas_vencidas')
           and pg_temp.n(x, 'realizadas') <= pg_temp.n(x, 'divisor_realizacion')
           and pg_temp.n(x, 'reprogramadas_vencidas') <= pg_temp.n(x, 'reprogramadas')
           and pg_temp.n(x, 'canceladas_sistema_vencidas') + pg_temp.n(x, 'reprogramadas_vencidas') <= pg_temp.n(x, 'debieron_ocurrir')
           and pg_temp.pct(x, 'pct_realizacion') is not distinct from
               case when pg_temp.n(x, 'divisor_realizacion') > 0 then round(100.0 * pg_temp.n(x, 'realizadas') / pg_temp.n(x, 'divisor_realizacion'), 1) end),
         string_agg(x ->> 'modalidad' || ' [' || pg_temp.txt(x) || ']', ' · ')
    into v_ok, v_detalle
  from jsonb_array_elements(v_d1 -> 'modalidades') x;
  perform pg_temp.exigir('1-modalidades-coherencia', coalesce(v_ok, false), 'una modalidad no cuadra consigo misma: ' || coalesce(v_detalle, '(sin modalidades)'));
  -- Orígenes: web recibe solo A4 (realizada anticipada), whatsapp solo B1, campania las once restantes.
  v_x := pg_temp.fila(v_d1, 'origenes', 'origen', 'web');
  perform pg_temp.exigir('1-origen-web',
    v_x is not null and pg_temp.n(v_x, 'pactadas') = 1 and pg_temp.n(v_x, 'realizadas') = 1 and pg_temp.pct(v_x, 'pct_realizacion') = 100.0,
    format('la realizada anticipada no entra al divisor del origen web (1 realizada debía dar 100.0%%): [%s]', pg_temp.txt(v_x)));
  v_x := pg_temp.fila(v_d1, 'origenes', 'origen', 'whatsapp');
  perform pg_temp.exigir('1-origen-whatsapp',
    v_x is not null and pg_temp.n(v_x, 'pactadas') = 1 and pg_temp.n(v_x, 'realizadas') = 1 and pg_temp.pct(v_x, 'pct_realizacion') = 100.0,
    format('la realizada anticipada no entra al divisor del origen whatsapp (1 realizada debía dar 100.0%%): [%s]', pg_temp.txt(v_x)));
  v_x := pg_temp.fila(v_d1, 'origenes', 'origen', 'campania');
  perform pg_temp.exigir('1-origen-campania',
    v_x is not null and pg_temp.n(v_x, 'pactadas') = 11 and pg_temp.n(v_x, 'realizadas') = 0 and pg_temp.n(v_x, 'no_show') = 2
      and pg_temp.n(v_x, 'canceladas') = 3 and pg_temp.pct(v_x, 'pct_realizacion') = 0.0,
    format('el origen campania no quedó como manda el escenario (11 pactadas, 0 realizadas, 2 no asistieron, 3 canceladas, 0.0%%): [%s]', pg_temp.txt(v_x)));

  -- ── 2. Un analista con UNA sola cita, realizada antes de su hora: hoy realizadas=1 y divisor=0 → divisor 1 ────────
  perform pg_temp.exigir('2-analista-sola-anticipada',
    v_fb is not null and pg_temp.n(v_fb, 'pactadas') = 1 and pg_temp.n(v_fb, 'debieron_ocurrir') = 1
      and pg_temp.n(v_fb, 'realizadas') = 1 and pg_temp.n(v_fb, 'divisor_realizacion') = 1
      and pg_temp.pct(v_fb, 'pct_realizacion') = 100.0 and pg_temp.n(v_fb, 'programadas_futuras') = 0,
    format('un analista cuya única cita se realizó antes de su hora debía quedar «1 de 1», 100.0%%, y quedó: [%s]', pg_temp.txt(v_fb)));

  -- ── 3. Periodo ya pasado: la misma respuesta antes y después de la migración (mismos datos, misma transacción) ─────
  v_pasado_antes := current_setting('ensayo.pasado_antes', true)::jsonb;
  v_pasado := pg_temp.payload(v_gerencia, current_setting('ensayo.pasado_desde')::date, current_setting('ensayo.pasado_hasta')::date);
  perform pg_temp.exigir('3-periodo-pasado',
    v_pasado is not null and v_pasado_antes is not null and v_pasado = v_pasado_antes,
    format('el periodo pasado (%s a %s) cambió con la migración: antes resumen [%s] después [%s]%s',
      current_setting('ensayo.pasado_desde'), current_setting('ensayo.pasado_hasta'),
      pg_temp.txt(v_pasado_antes -> 'resumen'), pg_temp.txt(v_pasado -> 'resumen'),
      case when (v_pasado - 'resumen') is distinct from (v_pasado_antes - 'resumen') then ' (y también fuera del resumen)' else '' end));
  -- Anti-vacuidad: el periodo pasado tiene exactamente la siembra de antes.sql (6 citas, todas vencidas).
  v_x := v_pasado -> 'resumen';
  perform pg_temp.exigir('3-periodo-pasado-siembra',
    pg_temp.n(v_x, 'pactadas') = 6 and pg_temp.n(v_x, 'debieron_ocurrir') = 6 and pg_temp.n(v_x, 'realizadas') = 1
      and pg_temp.n(v_x, 'canceladas_sistema_vencidas') = 1 and pg_temp.n(v_x, 'reprogramadas_vencidas') = 1
      and pg_temp.n(v_x, 'divisor_realizacion') = 4 and pg_temp.pct(v_x, 'pct_realizacion') = 25.0
      and pg_temp.n(v_x, 'pendientes_cierre') = 1 and pg_temp.n(v_x, 'programadas_futuras') = 0,
    format('el periodo pasado no tiene la siembra esperada (6 pactadas, 6 vencidas, 1 realizada, divisor 4, 25.0%%): [%s]', pg_temp.txt(v_x)));

  -- ── 4. Canceladas por el asesor vencidas: en el divisor. Sistema y reprogramadas vencidas: se restan. Futuras: fuera ──
  perform pg_temp.exigir('4-canceladas-asesor-vencidas',
    v_fc is not null and pg_temp.n(v_fc, 'debieron_ocurrir') = 4 and pg_temp.n(v_fc, 'canceladas') = 3
      and pg_temp.n(v_fc, 'canceladas_ajenas_vencidas') = 1 and pg_temp.n(v_fc, 'canceladas_sistema_vencidas') = 1
      and pg_temp.n(v_fc, 'reprogramadas_vencidas') = 1 and pg_temp.n(v_fc, 'divisor_realizacion') = 1
      and pg_temp.n(v_fc, 'realizadas') = 0 and pg_temp.pct(v_fc, 'pct_realizacion') = 0.0,
    format('las canceladas por el asesor ya vencidas debían seguir en el divisor (4 vencidas: 2 canceladas por asesor, 1 por sistema, 1 reprogramada → divisor del analista 4−1−1−1=1) y quedó: [%s]', pg_temp.txt(v_fc)));
  perform pg_temp.exigir('4-futuras-fuera',
    v_fc is not null and pg_temp.n(v_fc, 'pactadas') = 8 and pg_temp.n(v_fc, 'debieron_ocurrir') = 4
      and pg_temp.n(v_fc, 'programadas_futuras') = 1 and pg_temp.n(v_fc, 'canceladas_sistema_vencidas') = 1
      and pg_temp.n(v_fc, 'reprogramadas_vencidas') = 1 and pg_temp.n(v_fc, 'reprogramadas') = 2
      and pg_temp.n(v_fc, 'canceladas') = 3 and pg_temp.n(v_fc, 'pendientes_cierre') = 0,
    format('una cita futura no realizada (cancelada, reprogramada o pendiente) entró al divisor o a las exclusiones: debían ser 8 pactadas, 4 vencidas, 1 futura, 1+1 excluidas, y quedó [%s]', pg_temp.txt(v_fc)));

  -- ── 5. Una realizada anticipada con hora en el MES SIGUIENTE no aparece en el periodo actual ──────────────────────
  select count(*) into v_n from crm.tareas t
   where t.id = v_b2 and t.estado = 'completada' and t.vence_en >= (v_mes_sig::timestamp at time zone 'America/Lima');
  perform pg_temp.exigir('5-mes-siguiente',
    v_n = 1 and pg_temp.n(v_fb, 'pactadas') = 1
      and pg_temp.n(pg_temp.fila(v_m1, 'responsables', 'responsable_id', v_b::text), 'pactadas') = 1
      and pg_temp.d(v_m1 -> 'resumen', v_m0 -> 'resumen', 'pactadas') = 13
      and pg_temp.d(v_m1 -> 'resumen', v_m0 -> 'resumen', 'realizadas') = 2,
    format('la cita realizada anticipada del mes siguiente apareció en el periodo actual (B pactadas hoy=%s, mes=%s; Δpactadas del mes=%s, Δrealizadas del mes=%s; existe=%s)',
      pg_temp.n(v_fb, 'pactadas'), pg_temp.n(pg_temp.fila(v_m1, 'responsables', 'responsable_id', v_b::text), 'pactadas'),
      pg_temp.d(v_m1 -> 'resumen', v_m0 -> 'resumen', 'pactadas'), pg_temp.d(v_m1 -> 'resumen', v_m0 -> 'resumen', 'realizadas'), v_n));
  -- La ventana del mes en curso cuenta la anticipada igual que la de hoy (pertenece al mes de su hora pactada).
  perform pg_temp.exigir('5-mes-ventana',
    pg_temp.d(v_m1 -> 'resumen', v_m0 -> 'resumen', 'debieron_ocurrir') = 9
      and pg_temp.d(v_m1 -> 'resumen', v_m0 -> 'resumen', 'divisor_realizacion') = 7,
    format('en la ventana del mes la realizada anticipada no entra al divisor (Δdebieron_ocurrir=%s, Δdivisor=%s; esperados 9 y 7)',
      pg_temp.d(v_m1 -> 'resumen', v_m0 -> 'resumen', 'debieron_ocurrir'), pg_temp.d(v_m1 -> 'resumen', v_m0 -> 'resumen', 'divisor_realizacion')));

  -- ── 6. El núcleo y los informes de conversiones no cambian ───────────────────────────────────────────────────────
  -- 6a. El núcleo sigue diciendo que la anticipada NO debió ocurrir (su hora no llegó) aunque está realizada: así la
  --     leen los informes («cita real» = realizada y debió ocurrir, D-13). Y su cuerpo tiene la huella del laboratorio.
  select ce.debio_ocurrir, ce.realizada, ce.programada_futura, ce.pendiente_cierre
    into v_debio, v_realizada, v_futura, v_pendiente
  from private.citas_episodios(v_ini_hoy, v_fin_hoy, now()) ce where ce.tarea_id = v_a4;
  select count(*) into v_n from private.citas_episodios(v_ini_hoy, v_fin_hoy, now()) ce
   where ce.tarea_id in (v_a4, v_b1) and ce.realizada and ce.debio_ocurrir;
  select count(*) into v_m from private.citas_episodios(v_ini_hoy, v_fin_hoy, now()) ce
   where ce.tarea_id in (v_a1, v_a2, v_a3, v_c1, v_c2, v_c3, v_c4) and ce.debio_ocurrir;
  perform pg_temp.exigir('6-nucleo-intacto',
    v_debio = false and v_realizada = true and v_futura = false and v_pendiente = false and v_n = 0 and v_m = 7
      and (select md5(p.prosrc) from pg_proc p where p.oid = 'private.citas_episodios(timestamptz,timestamptz,timestamptz)'::regprocedure) = '5580cc4babd10d3f75a12e2373ff1bd5'
      and (select md5(p.prosrc) from pg_proc p where p.oid = 'private.citas_episodios(timestamptz,timestamptz,timestamptz,uuid[])'::regprocedure) = '55525e2208fbc83af5d15df3af845b6a',
    format('el núcleo private.citas_episodios cambió: para la anticipada debio_ocurrir=%s (esperado f), realizada=%s (t), programada_futura=%s (f), pendiente_cierre=%s (f); «citas reales» entre las anticipadas=%s (esperado 0); vencidas con debio_ocurrir=%s (esperado 7); md5 3 args=%s (5580cc4b…), 4 args=%s (55525e22…)',
      v_debio, v_realizada, v_futura, v_pendiente, v_n, v_m,
      (select md5(p.prosrc) from pg_proc p where p.oid = 'private.citas_episodios(timestamptz,timestamptz,timestamptz)'::regprocedure),
      (select md5(p.prosrc) from pg_proc p where p.oid = 'private.citas_episodios(timestamptz,timestamptz,timestamptz,uuid[])'::regprocedure)));
  -- 6b. Los informes de conversiones y lo que rodea a la función, con su huella del laboratorio. F4.2 (09/10/2026): las de
  --     PRODUCCIÓN para `metricas_conversiones_implementacion` (bases cargadas y tope de referidos; su «cita real» sigue siendo
  --     `ce.realizada and ce.debio_ocurrir` del núcleo) y `conversion_episodios` (tope de referidos), re-auditadas: ver la
  --     cabecera de la migración. F4.2-bis (09/10/2026, tarde): `conversion_episodios` y `capital_episodios`, otra vez, por la
  --     baja de analista de producción (20261009200000: solo el analista de las operaciones y del capital, que esta pantalla no
  --     lee), re-auditadas.
  perform pg_temp.exigir('6-informes-intactos',
    (select md5(p.prosrc) from pg_proc p where p.oid = 'private.metricas_conversiones_implementacion(date,date,text)'::regprocedure) = '14f45688ee958edbc2e5f238648e7fad'
      and (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.metricas_reuniones_fn(date,date)'::regprocedure) = 'ca480bc76d7624fbd3f6e6b2016d5fc3'
      and (select md5(p.prosrc) from pg_proc p where p.oid = 'private.filtrar_desglose_sujetos_crm(jsonb,text,text,text[])'::regprocedure) = '1cce2929af369715a2c7e161d63fc7ce'
      and (select md5(p.prosrc) from pg_proc p where p.oid = 'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure) = '125b4046f513657ac57ec676a0d52e87'
      and (select md5(p.prosrc) from pg_proc p where p.oid = 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure) = 'b4ee7e5619537830cbe2fd00eb2f923f'
      and (select md5(p.prosrc) from pg_proc p where p.oid = 'private.peso_referido_conversion(date)'::regprocedure) = 'db78c8acbb0b0ea0ac3b0d2f0d25e7de',
    'cambió algo que este bloque no toca: private.metricas_conversiones_implementacion (puerta #4), crm.metricas_reuniones_fn, private.filtrar_desglose_sujetos_crm, private.conversion_episodios, private.capital_episodios o private.peso_referido_conversion');
  -- 6c. La conversión de la propia pantalla (leads reunidos) no cambia con el divisor: cuenta 2 leads con realizada.
  perform pg_temp.exigir('6-conversion-pantalla',
    pg_temp.d(v_d1 -> 'conversion', v_d0 -> 'conversion', 'leads_reunidos') = 2,
    format('el bloque conversion de la pantalla cambió más de lo esperado (Δleads_reunidos=%s, esperado 2)', pg_temp.d(v_d1 -> 'conversion', v_d0 -> 'conversion', 'leads_reunidos')));

  -- ── 7. La huella analítica está re-sellada para el cuerpo VIVO ───────────────────────────────────────────────────
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)),
         md5(regexp_replace(regexp_replace(lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'))
    into v_prosrc, v_def, v_norm
  from pg_proc p where p.oid = 'private.metricas_reuniones_implementacion(date,date)'::regprocedure;
  select e.huella into v_huella_ex from private.analitica_leads_citas_exenciones e
   where e.objeto = 'private.metricas_reuniones_implementacion(date,date)';
  select c.declarada, c.huella_ok into v_declarada, v_huella_ok from private.contadores_crudos_leads_citas() c
   where c.objeto = 'private.metricas_reuniones_implementacion(date,date)';
  select s.sello into v_sello from private.analitica_lc_sello s where s.id;
  v_sello_calc := private.huella_exenciones_analitica_lc();
  perform pg_temp.exigir('7-huella-resellada',
    v_huella_ex = v_norm and coalesce(v_declarada, false) and coalesce(v_huella_ok, false) and v_sello = v_sello_calc,
    format('la huella de la exención no está re-sellada para el cuerpo vivo: exención=%s, normalizada viva=%s, censo declarada=%s huella_ok=%s, sello=%s, calculado=%s',
      coalesce(v_huella_ex, 'sin fila'), v_norm, v_declarada, v_huella_ok, v_sello, v_sello_calc));

  -- ── 8. Ficha de la función: dueño, DEFINER, search_path vacío, STABLE y EXECUTE solo para el dueño ────────────────
  perform pg_temp.exigir('8-ficha',
    exists (select 1 from pg_proc p
             where p.oid = 'private.metricas_reuniones_implementacion(date,date)'::regprocedure
               and p.proowner = 'postgres'::regrole::oid and p.prosecdef and p.provolatile = 's'
               and p.proconfig = array['search_path=""'])
      and (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
             from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
            where p.oid = 'private.metricas_reuniones_implementacion(date,date)'::regprocedure)
          = array['postgres:EXECUTE:false']
      and not has_function_privilege('anon', 'private.metricas_reuniones_implementacion(date,date)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'private.metricas_reuniones_implementacion(date,date)', 'EXECUTE')
      and not has_function_privilege('service_role', 'private.metricas_reuniones_implementacion(date,date)', 'EXECUTE'),
    'private.metricas_reuniones_implementacion cambió de dueño, de atributos (security definer, STABLE, search_path vacío) o de permisos (EXECUTE para alguien más que el dueño)');

  -- ── 9. El contrato de la pantalla: toda fila servida pasaría la validación de metricas-reuniones.ts ───────────────
  -- (Hoy, con una realizada anticipada y nada más, la app rechaza el payload entero: realizadas > divisor.)
  select bool_and(
           pg_temp.n(x, 'divisor_realizacion') = pg_temp.n(x, 'debieron_ocurrir') - pg_temp.n(x, 'canceladas_sistema_vencidas')
                                                 - pg_temp.n(x, 'canceladas_ajenas_vencidas') - pg_temp.n(x, 'reprogramadas_vencidas')
           and pg_temp.n(x, 'realizadas') <= pg_temp.n(x, 'divisor_realizacion')
           and pg_temp.n(x, 'debieron_ocurrir') <= pg_temp.n(x, 'pactadas')
           and pg_temp.n(x, 'canceladas_ajenas_vencidas') <= pg_temp.n(x, 'canceladas')
           and pg_temp.n(x, 'reprogramadas_vencidas') <= pg_temp.n(x, 'reprogramadas')),
         string_agg(case when pg_temp.n(x, 'realizadas') > pg_temp.n(x, 'divisor_realizacion')
                         then format('%s: realizadas (%s) > divisor (%s)', x ->> 'nombre', pg_temp.n(x, 'realizadas'), pg_temp.n(x, 'divisor_realizacion'))
                         else null end, '; ')
    into v_ok, v_detalle
  from jsonb_array_elements(v_d1 -> 'responsables') x;
  perform pg_temp.exigir('9-contrato-app',
    coalesce(v_ok, false)
      and pg_temp.n(v_r1, 'realizadas') <= pg_temp.n(v_r1, 'divisor_realizacion')
      and (select coalesce(bool_and(pg_temp.n(x, 'realizadas') <= pg_temp.n(x, 'divisor_realizacion')), true)
             from jsonb_array_elements(v_d1 -> 'modalidades') x),
    'la pantalla rechazaría el payload (metricas-reuniones.ts:106-116,135-138): ' || coalesce(v_detalle, 'una base o exclusión no cuadra en responsables, modalidades o resumen'));

  -- ── 4b. Frontera EXACTA de la hora: una cita con vence_en = now() ya «debió ocurrir» (<=), con y sin la migración ───
  -- `now()` es fijo en toda la transacción y es el mismo «ahora» que usa la función (`v_ahora := now()`): la cita cae
  -- exactamente en la hora. Se siembra AQUÍ, después de las mediciones anteriores, para no mover sus deltas (una cita más
  -- de B). Realizada: el núcleo la da por debio_ocurrir = t y realizada = t («cita real» para los informes, D-13); la fila
  -- de B suma 1 a pactadas, debieron, realizadas y divisor, igual ANTES y DESPUÉS de la migración (una cita en su hora
  -- exacta ya contaba en el divisor: la migración solo añade las que aún no llegaron a su hora). Sin mover el reloj.
  execute 'set local session_replication_role = replica';
  v_f1 := pg_temp.cita(v_lead_b, v_b, 'F1 realizada EN SU HORA EXACTA (frontera)', now(), 'completada');
  execute 'set local session_replication_role = origin';
  select ce.debio_ocurrir, ce.realizada, ce.programada_futura, ce.pendiente_cierre
    into v_debio, v_realizada, v_futura, v_pendiente
  from private.citas_episodios(v_ini_hoy, v_fin_hoy, now()) ce where ce.tarea_id = v_f1;
  select count(*) into v_n from crm.tareas t where t.id = v_f1 and t.vence_en = now();
  v_x := pg_temp.fila(pg_temp.payload(v_gerencia, v_hoy, v_hoy), 'responsables', 'responsable_id', v_b::text);
  perform pg_temp.exigir('4-frontera-exacta',
    v_n = 1 and v_debio = true and v_realizada = true and v_futura = false and v_pendiente = false
      and pg_temp.d(v_x, v_fb, 'pactadas') = 1 and pg_temp.d(v_x, v_fb, 'debieron_ocurrir') = 1
      and pg_temp.d(v_x, v_fb, 'realizadas') = 1 and pg_temp.d(v_x, v_fb, 'divisor_realizacion') = 1
      and pg_temp.d(v_x, v_fb, 'programadas_futuras') = 0 and pg_temp.d(v_x, v_fb, 'pendientes_cierre') = 0,
    format('la cita con vence_en = now() EXACTO no se trató como ya vencida: existe en la hora=%s (esperado 1); núcleo debio_ocurrir=%s (esperado t), realizada=%s (t), programada_futura=%s (f), pendiente_cierre=%s (f); fila de B antes [%s] después [%s] (esperados Δpactadas 1, Δdebieron 1, Δrealizadas 1, Δdivisor 1, Δfuturas 0)',
      v_n, v_debio, v_realizada, v_futura, v_pendiente, pg_temp.txt(v_fb), pg_temp.txt(v_x)));
  perform pg_temp.medir(format('medida frontera: F1 vence_en = now() = %s Lima · núcleo debio_ocurrir=%s realizada=%s · B con F1 [%s]',
    to_char(now() at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI:SS.US'), v_debio, v_realizada, pg_temp.txt(v_x)));

  -- ── Medidas (no juzgan: documentan) ──────────────────────────────────────────────────────────────────────────────
  perform pg_temp.medir(format('medida huellas: md5(prosrc)=%s · md5(definición)=%s · huella normalizada=%s · sello=%s (antes de la migración en esta transacción: %s)',
    v_prosrc, v_def, v_norm, v_sello, current_setting('ensayo.huella_antes', true)));
  perform pg_temp.medir(format('medida reloj: ahora %s Lima · ventana de hoy %s · mes %s a %s · periodo pasado %s a %s',
    to_char(now() at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI:SS'), v_hoy, v_mes, v_hoy,
    current_setting('ensayo.pasado_desde'), current_setting('ensayo.pasado_hasta')));
  perform pg_temp.medir(format('medida actores: gerencia=%s · A=%s · B=%s · C=%s · reuniones previas de A, B y C neutralizadas en el montaje=%s · reuniones ajenas con hora futura neutralizadas=%s',
    v_gerencia, v_a, v_b, v_c, coalesce(current_setting('ensayo.neutralizadas', true), '?'),
    coalesce(current_setting('ensayo.futuras_neutralizadas', true), '?')));
  perform pg_temp.medir(format('medida resumen hoy: antes [%s] · después [%s]', pg_temp.txt(v_r0), pg_temp.txt(v_r1)));
  perform pg_temp.medir(format('medida analistas: A [%s] · B [%s] · C [%s]', pg_temp.txt(v_fa), pg_temp.txt(v_fb), pg_temp.txt(v_fc)));
  perform pg_temp.medir(format('medida periodo pasado: [%s]', pg_temp.txt(v_pasado -> 'resumen')));

  -- ── Lo diferido se comprueba AHORA, no en un COMMIT que nunca llega ─────────────────────────────────────────────
  begin
    set constraints all immediate;
  exception when others then
    perform pg_temp.reg('10', format(E'FALLO 10: algo de lo sembrado no sobreviviría al COMMIT (%s %s)\n', sqlstate, sqlerrm));
  end;

  -- ── Veredicto, y rollback SIEMPRE ───────────────────────────────────────────────────────────────────────────────
  raise exception E'ENSAYO %:\n%\n%\n%(rollback a propósito — nada queda escrito)',
    case when current_setting('ensayo.fallos')::integer = 0 then 'VERDE — 0 fallos'
         else format('ROJO — %s fallo(s)', current_setting('ensayo.fallos')) end,
    current_setting('ensayo.informe'),
    current_setting('ensayo.medidas'),
    current_setting('ensayo.oks');
end;
$ensayo$;

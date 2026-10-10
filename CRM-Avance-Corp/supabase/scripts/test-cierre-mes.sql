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
--   4. Un mes CERRADO no se reescribe (2.6, `20261009210000`; D-09, D-14 y
--      D-17): anular la venta de un mes sellado es P0409, sin escribir nada,
--      para una Gerencia sin el par admin del Portal; el EXENTO (admin del Portal
--      + Gerencia) anula SIN deuda y deja rastro (4bis). Hasta el 2.6, anular
--      creaba una deuda.
--   5. El mes vivo enseña su numero ya descontado de una deuda VIEJA (sembrada:
--      desde el 2.6 ninguna anulacion la crea), sin bajar de cero.
--   6. Al cerrar el mes vivo, la deuda se salda hasta donde llega y el resto se
--      arrastra.
--   6bis. Y el capital se RESTA de verdad de donde se paga, no solo se marca
--        como saldado (fallo de dinero corregido el 15/08; ver el bloque).
--        Desde ATR-4 solo las deudas HISTORICAS tienen capital: 6bis protege
--        `saldar_ajustes` para ellas.
--   7. Anular un cierre de un mes ABIERTO sigue reescribiendo ese mes, sin deuda.
--   8. La foto es de una sola direccion: no se edita ni se borra.
--   9. La ventana de cierre abre el dia 11 del mes siguiente (el 10 entero es
--      ventana de ajuste; `20260927073637`) — a medianoche de LIMA, no de UTC
--      (aritmetica pura: se prueba corra el dia que corra).
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
-- (la ventana del mes pasado solo esta cerrada del 1 al 10), asi que esos bloques
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
-- ⚠️ Y OTRA VEZ, EN UNA BASE IGUAL A PRODUCCION (09/10/2026, F4.1-A ronda 6: el
-- laboratorio de la fase 2, cada mutante en una transaccion que se deshace, con
-- la corrida de control en verde). Los DIEZ de arriba, rehechos sobre los
-- cuerpos de produccion, caen los diez (el cerrojo, ya por el bloque 17). Y
-- SIETE nuevos, por el 2.6 y por la deuda sembrada, caen cada uno por su fallo:
-- la puerta SIN la guarda del 2.6 —vuelve a crear deuda— (4), el exento tratado
-- como no exento (4bis), una Gerencia cualquiera tratada como exenta (4), el
-- exento que vuelve a crear deuda (4bis), el exento sin rastro (4bis), el
-- detector que lee «abierto» un mes sellado (4) y un cierre que no resta el
-- capital de la deuda (6bis). Guiones y salidas: plan backend,
-- `fase-4/F4.1-A/salidas/ronda6/`.
--
-- QUE CAMBIO EL 09/10/2026 (plan backend AVANCE-BACKEND-0810-F2, F4.1-A ronda 6).
-- Con el grupo A (2.6, `20261009210000`) los bloques 4-6bis cambiaban de
-- sentido, y el oraculo ni arrancaba en una base igual a produccion (la siembra
-- chocaba con `perfiles_id_fkey`; nunca habia corrido fuera del banco de calcos):
--   · el bloque 4, al contrato del 2.6 (4 y 4bis); 5, 6 y 6bis siguen midiendo
--     la deuda, que se SIEMBRA (una deuda vieja, por insercion explicita: ver la
--     siembra que sigue al 4bis) con sus aserciones intactas;
--   · la identidad, por los claims del JWT (`pg_temp.como`), no por `test.uid`;
--   · la siembra, con la forma, las llaves y los roles del esquema real (ver
--     «Siembra»), y el oraculo se niega si la base ya tiene meses sellados;
--   · la ventana del dia 11 —un cambio de la PRUEBA, AJENO al grupo A—: es la
--     regla de produccion desde `20260927073637` (27/09/2026: el dia 10 entero
--     es ventana de ajuste y el sello abre el 11 a las 00:00 de Lima); el
--     oraculo seguia esperando el 10 y caia siempre en el 9, y cada dia 10 en
--     los bloques 10-13. Bloques 9, 10, 11, 12 y 13;
--   · bloque 2: el cambio del mundo es un cambio de supervisor (las metas son
--     inmutables), y es lo que hace discriminar al 14; bloque 13 (0bis): la meta
--     de prueba se deshace con un raise; bloque 7: un mes abierto no deja
--     rastro de excepcion (v_g es ahora el par exento).
-- v_g sigue siendo el actor de 4bis, 7, 10bis, 11-13 y 16 (gerencia y, ademas,
-- el par exento); la Gerencia no exenta (v_g_sola) solo actua en el 4.
--
-- USO (base IGUAL A PRODUCCION —el laboratorio de la fase 2 o una branch de
-- Supabase—, como `postgres`; NUNCA el ref de produccion: siembra y sella,
-- aunque todo se deshaga al final):
--   psql -X -v ON_ERROR_STOP=1 -d <base> -f supabase/scripts/test-cierre-mes.sql
--   · laboratorio: `lab_sql.py <este archivo> --paso cierre-mes` (plan backend,
--     fase-2/bloque-2.1/herramientas), que compara la huella antes y despues;
--   · branch: por el pooler en modo SESION (todo el archivo es una transaccion)
--     o por la conexion directa.
-- Se niega a correr si la base ya tiene meses sellados o perfiles con sus ids
-- fijos. Y APARTA, solo dentro de su transaccion, las metas publicadas de meses
-- pasados que traiga la base: la branch trae las de produccion (D-40; el
-- 09/10/2026, 2026-08 y 2026-09), y serian meses pendientes que el ciclo y el
-- aviso mezclarian con el calendario del oraculo (sin apartarlas, el 10bis cae
-- con «Falta cerrar 2026-08-01 antes que 2026-09-01»). Las borra con los
-- disparadores apagados, porque las metas son inmutables, y el ROLLBACK final
-- las devuelve intactas; un NOTICE dice de que meses las aparto. El banco local
-- con calcos (`banco-local-cierre-mes.sql`) ya NO basta para este archivo:
-- siembra columnas y roles del esquema real.
--
-- Termina con ROLLBACK: no deja nada sembrado.
-- ---------------------------------------------------------------------------

\set ON_ERROR_STOP on

begin;

-- ── Identidad y ayudantes (base IGUAL A PRODUCCION; F4.1-A ronda 6) ────────
-- `auth.uid()` de Supabase lee los claims del JWT (`request.jwt.claim.sub` o
-- `request.jwt.claims`), no el `test.uid` del calco del banco local. Se fijan
-- las DOS formas, como `anular-venta-mes-sellado/pruebas.sql` y
-- `eliminar-inversion/test-eliminar-inversion.sql`. NULL = sin sesion (el ciclo
-- automatico, la consola). Local a la transaccion: una subtransaccion que
-- revienta la deshace, igual que hacia `test.uid`.
create function pg_temp.como(p_uid uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true),
         set_config('request.jwt.claims',
           case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
$$;

-- Foto POR CONTENIDO (md5 de las filas) de lo que una anulacion puede escribir
-- alrededor de una venta: el lead, su anulacion, sus actividades y TODA la
-- tabla de ajustes (una anulacion no puede tocar la deuda de nadie).
create function pg_temp.foto_anulacion(p_lead uuid) returns text language sql as $$
  select format('lead=%s anulaciones=%s actividades=%s ajustes_total=%s',
    coalesce((select md5(l::text) from crm.leads l where l.id = p_lead), '-'),
    coalesce((select md5(string_agg(a::text, ',' order by a.id)) from crm.cierres_avance_anulados a where a.lead_id = p_lead), '-'),
    coalesce((select md5(string_agg(a::text, ',' order by a.id)) from crm.actividades a where a.lead_id = p_lead), '-'),
    coalesce((select md5(string_agg(j::text, ',' order by j.id)) from crm.ajustes_mes_cerrado j), '-'));
$$;

-- Un episodio del ledger con la FORMA real de `crm.lead_asignaciones` (ciclo y
-- episodio, SLA, cierre consistente). p_resultado NULL = episodio abierto;
-- 'convertido' o 'descartado' = cerrado en p_resultado_en. Se llama con los
-- disparadores apagados (ver la siembra).
create function pg_temp.episodio(p_lead uuid, p_analista uuid, p_resultado text, p_resultado_en timestamptz,
                                 p_asignado_en timestamptz, p_origen text) returns void language sql as $$
  insert into crm.lead_asignaciones (lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en, moneda,
      origen, sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en, primer_contacto_limite_en,
      resultado, resultado_en, finalizado_en, finalizado_por, motivo_cierre, motivo_descarte_cierre)
  values (p_lead, 1, 1, p_analista, 'asignado', p_asignado_en, 'PEN',
      p_origen, p_asignado_en, gen_random_uuid(), p_asignado_en, p_asignado_en,
      p_resultado, p_resultado_en, p_resultado_en, case when p_resultado is not null then p_analista end,
      p_resultado, case when p_resultado = 'descartado' then 'sin_interes' end);
$$;

-- Un contrato «nuevo» en soles con la FORMA real de `public.contratos` (numero,
-- modalidad, fechas, condicion de producto, fecha de cierre comercial = el dia
-- de Lima en que se registra: de ahi sale el mes de su produccion). Tambien con
-- los disparadores apagados.
create function pg_temp.contrato(p_cliente uuid, p_capital numeric, p_creado_por uuid, p_cuando timestamptz)
returns uuid language sql as $$
  insert into public.contratos (numero_contrato, cliente_id, capital, moneda, categoria, estado, creado_por, creado_en,
      modalidad, fecha_inicio, fecha_vencimiento, producto_condicion_id, fecha_cierre_comercial)
  values ('ORACULO-CIERRE-' || replace(gen_random_uuid()::text, '-', ''), p_cliente, p_capital, 'PEN', 'nuevo', 'activo',
      p_creado_por, p_cuando, 'mensual', (p_cuando at time zone 'America/Lima')::date,
      (p_cuando at time zone 'America/Lima')::date + 365, gen_random_uuid(), (p_cuando at time zone 'America/Lima')::date)
  returning id;
$$;

do $oraculo$
declare
  v_g uuid := '11111111-1111-4111-8111-111111111111'; -- gerencia, y admin del Portal: el par EXENTO del 2.6 (D-17)
  v_g_sola uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'; -- gerencia SIN el par admin (comercial|gerencia): no exenta
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
  v_meta jsonb;   -- 4bis: metadatos de la actividad del exento
  v_foto text;    -- 4: foto por contenido antes del rechazo
  v_msg text;
  v_hint text;
  v_apartadas text; -- siembra: metas de la base que se apartan en esta transaccion
  v_n integer;
  v_num numeric;
  v_pend numeric;
  -- Bloques 9-12 (candado de la ventana, ciclo automatico y aviso).
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
  -- (F4.1-A ronda 6) Contra una base IGUAL A PRODUCCION —el laboratorio o una
  -- branch—, no contra el banco de calcos: las llaves, los CHECK y los
  -- disparadores son los de verdad, y los roles salen de `crm.equipo`.
  --
  -- 0) Lo que el oraculo supone del mundo. Siembra y sella SU calendario (los
  --    meses -9 a -1): un mes ya sellado en la base cambiaria el orden, los
  --    pendientes y el ciclo, asi que se niega a correr. Las metas publicadas de
  --    MESES PASADOS de la base (la branch trae las de produccion, D-40) se
  --    apartan DENTRO de esta transaccion —el ROLLBACK final las devuelve—: si
  --    no, serian meses pendientes que el ciclo y el aviso mezclarian con los
  --    del oraculo. Las metas son inmutables (trg_*_inmutables), por eso se
  --    apartan con los disparadores apagados.
  if exists (select 1 from crm.periodos_cerrados) then
    raise exception 'ORACULO ABORTADO: la base ya tiene meses sellados (%). El oraculo siembra y sella su propio calendario: correrlo en una base sin sellos (el laboratorio o una branch).',
      (select string_agg(to_char(pc.periodo, 'YYYY-MM'), ', ' order by pc.periodo) from crm.periodos_cerrados pc);
  end if;
  if exists (select 1 from public.perfiles p
             where p.id in (v_g, v_g_sola, v_s, v_s2, v_v, v_cli, v_coord, v_dir, '44444444-4444-4444-8444-444444444445')) then
    raise exception 'ORACULO ABORTADO: ya existen perfiles con los ids fijos del oraculo (¿quedo algo de otra corrida?)';
  end if;
  select string_agg(distinct to_char(mp.periodo, 'YYYY-MM'), ', ') into v_apartadas
  from crm.meta_periodos mp where mp.periodo < v_m0;
  if v_apartadas is not null then
    set local session_replication_role = replica;
    delete from crm.metas_vendedor_detalle d using crm.metas_vendedor mv, crm.meta_periodos mp
     where d.meta_vendedor_id = mv.id and mv.meta_periodo_id = mp.id and mp.periodo < v_m0;
    delete from crm.metas_vendedor mv using crm.meta_periodos mp
     where mv.meta_periodo_id = mp.id and mp.periodo < v_m0;
    delete from crm.meta_periodos mp where mp.periodo < v_m0;
    set local session_replication_role = origin;
    raise notice '  (siembra: se apartaron, solo dentro de esta transaccion, las metas de la base de %)', v_apartadas;
  end if;

  -- 1) Personas. `public.perfiles.id` cuelga de `auth.users` (perfiles_id_fkey)
  --    y estos ids fijos no tienen cuenta: se siembran con los disparadores y las
  --    llaves apagados (`session_replication_role = replica`) SOLO para esta
  --    siembra, como `eliminar-inversion/test-eliminar-inversion.sql`. No cambia
  --    lo que se mide: ninguna funcion del recorrido (puertas, cierre, ciclo,
  --    aviso, lecturas, saldo) lee `auth.users` (medido en el catalogo el
  --    09/10/2026), y sobre `auth.users` solo hay un disparador
  --    (`inversion_auth_insertado_guard`, de altas de inversion) y no crea
  --    perfiles. Los pares Portal|CRM, como en produccion: v_g admin|gerencia (el
  --    par EXENTO del 2.6, D-17), v_g_sola comercial|gerencia (Gerencia SIN el
  --    par: no exenta) y v_dir directorio|directorio (`private.rol_crm` solo da
  --    'directorio' con el rol del Portal alineado).
  set local session_replication_role = replica;
  insert into public.perfiles (id, nombre_completo, rol, activo) values
    (v_g, 'GERENTE DE PRUEBA', 'admin', true),
    (v_g_sola, 'GERENCIA SIN ADMIN DE PRUEBA', 'comercial', true),
    (v_s, 'SUPERVISOR DE PRUEBA', 'comercial', true),
    (v_v, 'VENDEDOR DE PRUEBA', 'comercial', true),
    (v_cli, 'CLIENTE DE PRUEBA', 'cliente', true),
    (v_coord, 'COORDINADOR DE PRUEBA', 'comercial', true),
    (v_dir, 'DIRECTORIO DE PRUEBA', 'directorio', true),
    (v_s2, 'SUPERVISOR AJENO DE PRUEBA', 'comercial', true);
  set local session_replication_role = origin;

  -- 2) El equipo del CRM, con sus disparadores ENCENDIDOS (jerarquia, evento de
  --    jerarquia; el par de autoridad, sin sesion, exento como toda alta de
  --    consola): primero los que no cuelgan de nadie, despues el vendedor bajo
  --    v_s. Y se comprueba que el mundo sembrado es el que se dice.
  perform pg_temp.como(null);
  insert into crm.equipo (perfil_id, rol_crm, activo) values
    (v_g, 'gerencia', true), (v_g_sola, 'gerencia', true),
    (v_s, 'supervisor', true), (v_s2, 'supervisor', true),
    (v_coord, 'coordinador', true), (v_dir, 'directorio', true);
  insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values
    (v_v, 'vendedor', v_s, true);
  if private.rol_crm(v_g) is distinct from 'gerencia' or private.rol_crm(v_g_sola) is distinct from 'gerencia'
     or private.rol_crm(v_s) is distinct from 'supervisor' or private.rol_crm(v_s2) is distinct from 'supervisor'
     or private.rol_crm(v_v) is distinct from 'vendedor' or private.rol_crm(v_coord) is distinct from 'coordinador'
     or private.rol_crm(v_dir) is distinct from 'directorio' then
    raise exception 'ORACULO ABORTADO: la siembra no dio los roles CRM esperados (g %, g_sola %, s %, s2 %, v %, coord %, dir %)',
      private.rol_crm(v_g), private.rol_crm(v_g_sola), private.rol_crm(v_s), private.rol_crm(v_s2),
      private.rol_crm(v_v), private.rol_crm(v_coord), private.rol_crm(v_dir);
  end if;
  perform pg_temp.como(v_g);
  if not (public.es_admin() and private.es_gerencia_crm_activa()) then
    raise exception 'ORACULO ABORTADO: v_g deberia ser el par exento del 2.6 (admin del Portal + Gerencia)';
  end if;
  perform pg_temp.como(v_g_sola);
  if public.es_admin() or not private.es_gerencia_crm_activa() then
    raise exception 'ORACULO ABORTADO: v_g_sola deberia ser Gerencia SIN el admin del Portal';
  end if;
  perform pg_temp.como(null);

  insert into crm.conversion_pesos (vigente_desde, peso_referido, nota)
  values (v_jun, 0.150, 'oraculo') on conflict do nothing;

  insert into crm.meta_periodos (id, periodo, revision, publicada_en, publicada_por) values
    (v_mp_jun, v_jun, 1, now(), v_g), (v_mp_jul, v_jul, 1, now(), v_g);
  insert into crm.metas_vendedor (id, meta_periodo_id, vendedor_id, supervisor_id, conversion_objetivo) values
    (v_mvj, v_mp_jun, v_v, v_s, 15), (v_mvl, v_mp_jul, v_v, v_s, 15);
  insert into crm.metas_vendedor_detalle (meta_vendedor_id, categoria, moneda, capital_objetivo, contratos_objetivo) values
    (v_mvj, 'nuevo', 'PEN', 100000, 5), (v_mvl, 'nuevo', 'PEN', 100000, 5);

  -- 3) Leads, episodios del ledger y contratos, con la FORMA real (telefono,
  --    monto, ciclo/episodio, SLA, numero de contrato, fecha de cierre
  --    comercial…) y con los disparadores apagados SOLO para sembrarlos, como
  --    los ensayos de la casa (`anular-venta-mes-sellado/pruebas.sql`,
  --    `test-eliminar-inversion.sql`): en el banco de calcos estas tablas no
  --    tenian ni disparadores ni llaves, asi que es la misma siembra. Lo que se
  --    MIDE (puertas, cierre, ciclo, aviso, lecturas, saldo) corre siempre con
  --    los disparadores encendidos. En el ledger real la LLEGADA (el divisor) se
  --    fecha por `crm.leads.creado_en`: los leads de junio nacen en junio.
  -- JUNIO: 4 recibidos, 2 cerrados (uno referido) → numerador 1,15 sobre 4.
  set local session_replication_role = replica;
  insert into crm.leads (id, nombre_completo, telefono, etapa, origen, vendedor_id, perfil_id, convertido_en,
                         monto_estimado, creado_en) values
    (v_lead_a, 'LEAD A', '+51900710001', 'convertido', 'formulario', v_v, v_cli, (v_jun + interval '9 days 16 hours'),
     1000, (v_jun + interval '1 day 16 hours')),
    (v_lead_b, 'LEAD B', '+51900710002', 'convertido', 'referido', v_v, null, (v_jun + interval '11 days 16 hours'),
     1000, (v_jun + interval '2 days 16 hours'));
  insert into crm.leads (id, nombre_completo, telefono, etapa, motivo_descarte, origen, vendedor_id, convertido_en,
                         monto_estimado, creado_en) values
    ('77777777-7777-4777-8777-777777777774', 'LEAD C', '+51900710004', 'descartado', 'sin_interes', 'formulario', v_v, null,
     1000, (v_jun + interval '3 days 16 hours')),
    ('77777777-7777-4777-8777-777777777775', 'LEAD D', '+51900710005', 'descartado', 'sin_interes', 'formulario', v_v, null,
     1000, (v_jun + interval '4 days 16 hours'));
  perform pg_temp.episodio(v_lead_a, v_v, 'convertido', (v_jun + interval '9 days 16 hours'), (v_jun + interval '1 day 16 hours'), 'formulario');
  perform pg_temp.episodio(v_lead_b, v_v, 'convertido', (v_jun + interval '11 days 16 hours'), (v_jun + interval '2 days 16 hours'), 'referido');
  perform pg_temp.episodio('77777777-7777-4777-8777-777777777774', v_v, 'descartado', (v_jun + interval '19 days 16 hours'), (v_jun + interval '3 days 16 hours'), 'formulario');
  perform pg_temp.episodio('77777777-7777-4777-8777-777777777775', v_v, 'descartado', (v_jun + interval '20 days 16 hours'), (v_jun + interval '4 days 16 hours'), 'formulario');
  -- Un contrato de junio, del cliente del lead A, creado por el vendedor.
  perform pg_temp.contrato(v_cli, 40000, v_v, (v_jun + interval '9 days 17 hours'));
  set local session_replication_role = origin;

  -- ── 1. Cerrar junio ───────────────────────────────────────────────────────
  perform pg_temp.como(null); -- sin uid = ciclo automatico
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

  perform pg_temp.como(v_v);
  v_r := crm.conversion_mensual_fn(v_jun);
  if (v_r->'cierre'->>'cerrado')::boolean is not true then
    raise exception 'FALLO 2: junio no se declara cerrado en el payload — %', v_r->'cierre';
  end if;
  if (v_r->'total'->>'numerador')::numeric is distinct from 1.150 then
    raise exception 'FALLO 2: la conversion de junio no sale de la foto — %', v_r->'total';
  end if;

  -- Y aunque el mundo cambie, la foto no. Se le quita el supervisor al vendedor
  -- (pasa a v_s2 en `crm.equipo`, el equipo de HOY): en un mes ABIERTO eso le
  -- cambiaria el ambito. (F4.1-A r6: antes se le sacaba tambien del roster
  -- borrando su meta; en produccion `crm.metas_vendedor` es inmutable
  -- —trg_metas_vendedor_inmutables— y el roster vivo sale de `crm.equipo`. Este
  -- cambio es ademas el que hace discriminar al bloque 14.)
  perform pg_temp.como(null);
  update crm.equipo set supervisor_id = v_s2 where perfil_id = v_v;
  perform pg_temp.como(v_v);
  v_r := crm.conversion_mensual_fn(v_jun);
  if (v_r->'total'->>'numerador')::numeric is distinct from 1.150 then
    raise exception 'FALLO 2: junio se movio al cambiar el roster — %', v_r->'total';
  end if;

  -- ── 3. Un mes cerrado no se cierra dos veces ──────────────────────────────
  begin
    perform pg_temp.como(null);
    perform crm.cerrar_periodo(v_jun);
    raise exception 'FALLO 3: junio se dejo cerrar dos veces';
  exception when sqlstate 'P0409' then null;
  end;

  -- Ni lo cierra un vendedor.
  begin
    perform pg_temp.como(v_v);
    perform crm.cerrar_periodo(v_jul);
    raise exception 'FALLO 3: un vendedor pudo cerrar un mes';
  exception when sqlstate '42501' then null;
  end;

  -- Ni se cierra el mes en curso.
  begin
    perform pg_temp.como(null);
    perform crm.cerrar_periodo(date_trunc('month', now() at time zone 'America/Lima')::date);
    raise exception 'FALLO 3: se dejo cerrar el mes en curso';
  exception when sqlstate '22023' then null;
  end;

  -- ── 4. Un mes CERRADO no se reescribe: Gerencia sin el par admin, P0409 ───
  -- (2.6, 20261009210000; D-09, D-14, D-17.) Hasta el 2.6, anular un cierre de
  -- un mes cerrado hacia nacer una DEUDA que el vendedor arrastraba al mes vivo.
  -- Desde el 2.6 la puerta lo RECHAZA antes de escribir nada, salvo a quien es a
  -- la vez admin del Portal y Gerencia del CRM (4bis). Aqui, la Gerencia SIN ese
  -- par: P0409 con el mensaje y la pista fijados, y NADA escrito —ni anulacion,
  -- ni actividad, ni ajuste—, medido por contenido.
  v_foto := pg_temp.foto_anulacion(v_lead_a);
  begin
    perform pg_temp.como(v_g_sola);
    v_r := crm.anular_cierre_avance(v_lead_a, 'mala practica detectada en octubre');
    raise exception 'FALLO 4: una Gerencia sin el par admin del Portal anulo una venta de un mes sellado — %', v_r;
  exception when sqlstate 'P0409' then
    get stacked diagnostics v_msg = message_text, v_hint = pg_exception_hint;
    if v_msg is distinct from format('No se puede anular: el mes de esta venta (%s) ya está sellado', to_char(v_jun, 'YYYY-MM'))
       or v_hint is distinct from 'Un mes sellado no se reescribe. La corrección se hace por otra vía, fuera del sistema.' then
      raise exception 'FALLO 4: P0409, pero no el rechazo del mes sellado — «%» / «%»', v_msg, v_hint;
    end if;
  end;
  if pg_temp.foto_anulacion(v_lead_a) is distinct from v_foto then
    raise exception 'FALLO 4: el rechazo dejo algo escrito (anulacion, actividad o ajuste)';
  end if;

  -- ── 4bis. El EXENTO (admin del Portal + Gerencia) anula SIN deuda ─────────
  -- (D-17) Pasa, pero el mes sellado NO cambia y NO nace ajuste: la respuesta
  -- conserva la forma que la pantalla conoce (`mes_cerrado:false`,
  -- `ajuste_id:null`) y el rastro fiable queda en la actividad:
  -- `excepcion_mes_sellado`, `excepcion_por` y `excepcion_en`.
  perform pg_temp.como(v_g);
  begin
    v_r := crm.anular_cierre_avance(v_lead_a, 'mala practica detectada en octubre');
  exception when others then
    raise exception 'FALLO 4bis: el exento (admin + Gerencia) no pudo anular una venta de un mes sellado — % %', sqlstate, sqlerrm;
  end;
  if v_r->'mes_cerrado' is distinct from 'false'::jsonb or v_r->'ajuste_id' is distinct from 'null'::jsonb then
    raise exception 'FALLO 4bis: el exento anula SIN ajuste (mes_cerrado:false, ajuste_id:null) — %', v_r;
  end if;
  if exists (select 1 from crm.ajustes_mes_cerrado where lead_id = v_lead_a) then
    raise exception 'FALLO 4bis: la anulacion del exento hizo nacer una deuda';
  end if;
  if not exists (select 1 from crm.cierres_avance_anulados where lead_id = v_lead_a and anulado_por = v_g) then
    raise exception 'FALLO 4bis: la anulacion del exento no quedo escrita';
  end if;
  select a.metadata into v_meta
  from crm.actividades a
  where a.lead_id = v_lead_a and a.metadata->>'accion' = 'anulacion_cierre_avance';
  if v_meta->>'excepcion_mes_sellado' is distinct from to_char(v_jun, 'YYYY-MM')
     or v_meta->>'excepcion_por' is distinct from v_g::text
     or (v_meta->>'excepcion_en')::timestamptz is distinct from now()
     or v_meta->'mes_cerrado' is distinct from 'false'::jsonb then
    raise exception 'FALLO 4bis: el rastro del exento no esta en la actividad (excepcion_mes_sellado, excepcion_por, excepcion_en) — %', v_meta;
  end if;

  -- Y JUNIO NO SE MOVIO. Es el corazon de la decision de Miguel.
  perform pg_temp.como(v_v);
  v_r := crm.conversion_mensual_fn(v_jun);
  if (v_r->'total'->>'numerador')::numeric is distinct from 1.150 then
    raise exception 'FALLO 4bis: junio cambio al anular un cierre suyo — %', v_r->'total';
  end if;

  -- ── Siembra: una deuda VIEJA (para 5, 6 y 6bis) ───────────────────────────
  -- Desde el 2.6 ninguna anulacion crea deuda, pero las deudas de antes EXISTEN
  -- y `private.saldar_ajustes` las sigue cobrando al cerrar cada mes: eso es lo
  -- que miden 5, 6 y 6bis. Se siembra la que dejaba la anulacion del lead A antes
  -- del 2.6 —1 de conversion: cierre no referido—, por INSERCION EXPLICITA y con
  -- la forma de las deudas anteriores a ATR-4: 40.000 en soles, «nuevo», un
  -- contrato —el de junio—. Desde ATR-4 (31/08/2026) las deudas NUEVAS nacen
  -- sin capital (`private.registrar_ajuste_si_mes_cerrado` ya no lo carga), asi
  -- que con esa funcion 6bis no tendria nada que medir; pero las deudas
  -- HISTORICAS con capital siguen ahi, y 6bis es lo que protege
  -- `private.saldar_ajustes` —y el descuento en la foto— para ellas.
  insert into crm.ajustes_mes_cerrado (vendedor_id, periodo_origen, lead_id, motivo, creado_por,
      numerador, capital_pen, capital_usd, detalle,
      pendiente_numerador, pendiente_pen, pendiente_usd, pendiente_detalle)
  values (v_v, v_jun, v_lead_a, 'mala practica detectada en octubre', v_g,
      1, 40000, 0, '[{"categoria": "nuevo", "moneda": "PEN", "capital": 40000, "contratos": 1}]'::jsonb,
      1, 40000, 0, '[{"categoria": "nuevo", "moneda": "PEN", "capital": 40000, "contratos": 1}]'::jsonb);

  -- ── 5. El mes vivo enseña el descuento, sin bajar de cero ─────────────────
  -- Julio no tiene ni un cierre: el descuento no cabe y el numerador se queda
  -- en cero, NUNCA en negativo.
  -- (la meta de julio ya se sembro arriba: v_mvl)
  set local session_replication_role = replica;
  insert into crm.leads (id, nombre_completo, telefono, etapa, origen, vendedor_id, monto_estimado, creado_en)
  values (v_lead_c, 'LEAD JULIO', '+51900710003', 'contactado', 'formulario', v_v, 1000, (v_jul + interval '1 day 16 hours'));
  perform pg_temp.episodio(v_lead_c, v_v, null, null, (v_jul + interval '1 day 16 hours'), 'formulario');
  set local session_replication_role = origin;

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
  perform pg_temp.como(null);
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
  -- (r6) Desde ATR-4 (31/08/2026) las deudas nuevas nacen sin capital: lo que
  -- este bloque protege hoy es `saldar_ajustes` para las deudas HISTORICAS que
  -- si lo tienen, como la sembrada tras el 4bis.
  declare
    v_ago date := (date_trunc('month', now() at time zone 'America/Lima') - interval '6 months')::date;
    v_mp_ago uuid := '55555555-5555-4555-8555-555555555553';
    v_mv_ago uuid := '66666666-6666-4666-8666-666666666664';
    v_lead_e uuid := '77777777-7777-4777-8777-777777777777';
    v_cli2 uuid := '44444444-4444-4444-8444-444444444445';
    v_cap numeric;
  begin
    insert into crm.meta_periodos (id, periodo, revision, publicada_en, publicada_por) values (v_mp_ago, v_ago, 1, now(), v_g);
    insert into crm.metas_vendedor (id, meta_periodo_id, vendedor_id, supervisor_id, conversion_objetivo)
      values (v_mv_ago, v_mp_ago, v_v, v_s, 15);
    insert into crm.metas_vendedor_detalle (meta_vendedor_id, categoria, moneda, capital_objetivo, contratos_objetivo)
      values (v_mv_ago, 'nuevo', 'PEN', 100000, 5);
    set local session_replication_role = replica;
    insert into public.perfiles (id, nombre_completo, rol, activo) values (v_cli2, 'CLIENTE DOS', 'cliente', true);
    insert into crm.leads (id, nombre_completo, telefono, etapa, origen, vendedor_id, perfil_id, convertido_en,
                           monto_estimado, creado_en)
      values (v_lead_e, 'LEAD AGOSTO', '+51900710006', 'convertido', 'formulario', v_v, v_cli2,
              (v_ago + interval '4 days 16 hours'), 1000, (v_ago + interval '1 day 16 hours'));
    -- (r6) La asignacion se fechaba '2026-08-02 16:00+00': con los meses ya
    -- relativos quedaba DESPUES del cierre, y el esquema real lo rechaza
    -- (lead_asignaciones_intervalo_valido). Se fecha dentro del mes.
    perform pg_temp.episodio(v_lead_e, v_v, 'convertido', (v_ago + interval '4 days 16 hours'),
                             (v_ago + interval '1 day 16 hours'), 'formulario');
    -- Agosto produce 100.000 en soles: hay de donde restar los 40.000 que se deben.
    perform pg_temp.contrato(v_cli2, 100000, v_v, (v_ago + interval '4 days 17 hours'));
    set local session_replication_role = origin;

    perform pg_temp.como(null);
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
    set local session_replication_role = replica;
    insert into crm.leads (id, nombre_completo, telefono, etapa, origen, vendedor_id, convertido_en, monto_estimado)
    values (v_lead_d, 'LEAD DEL MES VIVO', '+51900710009', 'convertido', 'formulario', v_v, v_ahora, 1000);
    perform pg_temp.episodio(v_lead_d, v_v, 'convertido', v_ahora, v_ahora, 'formulario');
    set local session_replication_role = origin;

    perform pg_temp.como(v_g);
    v_r := crm.anular_cierre_avance(v_lead_d, 'error de captura, mismo mes');
    if (v_r->>'mes_cerrado')::boolean is not false then
      raise exception 'FALLO 7: anular en un mes abierto no deberia declarar mes cerrado — %', v_r;
    end if;
    if v_r->>'ajuste_id' is not null then
      raise exception 'FALLO 7: un mes abierto no debe generar deuda — %', v_r;
    end if;
    -- (2.6) Y SIN rastro de excepcion: el mes no estaba sellado. v_g es el par
    -- exento, asi que `mes_cerrado:false` saldria igual por la via de la
    -- excepcion; lo que distingue «mes abierto» de «sellado, pero exento» es que
    -- aqui no queda ninguna clave `excepcion_*`.
    if exists (select 1 from crm.actividades a
               where a.lead_id = v_lead_d and a.metadata ? 'excepcion_mes_sellado') then
      raise exception 'FALLO 7: una anulacion en un mes abierto quedo marcada como excepcion de mes sellado';
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

  -- ── 9. La ventana abre el dia 11 del mes siguiente, a las 00:00 de Lima ───
  -- DETERMINISTA: aritmetica pura, sin reloj. Corra el dia que corra da lo
  -- mismo. Es a proposito el bloque mas exhaustivo, porque la regla del candado
  -- se puede torcer de tres formas —longitud del mes, salto de año y ZONA— y las
  -- tres se ven aqui y en ningun otro sitio.
  -- (F4.1-A r6 — un cambio de la PRUEBA, AJENO al grupo A.) Desde 20260927073637
  -- (en produccion desde el 27/09/2026) hay UNA sola frontera para admitir y
  -- para sellar, `private.conversion_plazo_hasta`: el dia 10 ENTERO es ventana
  -- de ajuste y el sello abre el 11 a las 00:00 de Lima. Antes era el 10 a las
  -- 00:00; este oraculo lo seguia esperando y, en una base igual a produccion,
  -- caia aqui siempre (y en 10-13 cada dia 10).
  for v_rec in
    select * from (values
      ('2026-01-01'::date, '2026-02-11'::date),  -- mes de 31
      ('2026-04-01'::date, '2026-05-11'::date),  -- mes de 30
      ('2026-02-01'::date, '2026-03-11'::date),  -- febrero de 28
      ('2024-02-01'::date, '2024-03-11'::date),  -- febrero bisiesto
      ('2026-12-01'::date, '2027-01-11'::date)   -- salto de año
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
  if not ('2026-08-10 23:59:59'::timestamp at time zone 'America/Lima'
          < private.cierre_mes_ventana_desde('2026-07-01'::date)) then
    raise exception 'FALLO 9: la ventana ya estaba abierta el 10 a las 23:59:59 de Lima';
  end if;
  if not ('2026-08-11 00:00:00'::timestamp at time zone 'America/Lima'
          >= private.cierre_mes_ventana_desde('2026-07-01'::date)) then
    raise exception 'FALLO 9: la ventana no abrio el 11 a las 00:00 de Lima';
  end if;

  -- ⚠️ Y NO abre a medianoche UTC, que es cinco horas antes que en Lima. Este
  -- proyecto ya pago una vez el bug de las fechas en UTC; aqui costaria que un
  -- mes se sellara la tarde del dia 10, con la ventana de ajuste todavia abierta.
  if '2026-08-11 00:00:00+00'::timestamptz
     >= private.cierre_mes_ventana_desde('2026-07-01'::date) then
    raise exception 'FALLO 9: la ventana abre a medianoche UTC, no a medianoche de Lima';
  end if;

  -- ── 10. EL CANDADO: nadie sella un mes antes del dia 11 ───────────────────
  -- Este estado SOLO existe los dias 1..10: un mes que termino hace mas de diez
  -- dias enteros siempre es cerrable, asi que los dias 11..31 no hay nada que
  -- rechazar.
  -- La prueba mira el calendario y asevera la cara que hoy es cierta; las dos
  -- caras juntas son «se cierra si y solo si la ventana abrio».
  -- El cierre de prueba se DESHACE con un raise: el bloque no deja rastro.
  v_dia := extract(day from (now() at time zone 'America/Lima'))::int;
  v_m1  := (date_trunc('month', now() at time zone 'America/Lima') - interval '1 month')::date;
  perform pg_temp.como(null);
  begin
    perform crm.cerrar_periodo(v_m1);
    raise exception using errcode = 'PT001', message = 'se dejo cerrar';
  exception
    when sqlstate '22023' then
      if position('antes del' in sqlerrm) = 0 then
        raise exception 'FALLO 10: % no se cerro, pero por otra razon — %', v_m1, sqlerrm;
      end if;
      if v_dia >= 11 then
        raise exception 'FALLO 10: el candado mordio el dia % del mes, con la ventana ya abierta', v_dia;
      end if;
      raise notice '  (bloque 10: hoy es dia % — probada la cara que RECHAZA)', v_dia;
    when sqlstate 'PT001' then
      if v_dia < 11 then
        raise exception 'FALLO 10: % se dejo cerrar el dia % del mes, dentro de la ventana de ajuste', v_m1, v_dia;
      end if;
      raise notice '  (bloque 10: hoy es dia % — probada la cara que ACEPTA)', v_dia;
  end;

  -- Y AHORA LA OTRA CARA, EL DIA QUE SEA. Lo de arriba solo puede ejercitar una
  -- de las dos ramas segun el calendario, y la que de verdad importa —la que
  -- RECHAZA— solo existe los dias 1..10. Asi que se empuja la ventana al futuro y
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
    perform pg_temp.como(null);
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
    perform pg_temp.como(v_g);
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
      at time zone 'America/Lima')::date is distinct from '2026-08-11'::date then
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
  insert into crm.meta_periodos (id, periodo, revision, publicada_en, publicada_por) values
    (v_mp_m5, v_m5, 1, now(), v_g),
    (v_mp_m4, v_m4, 1, now(), v_g),
    (v_mp_m1, v_m1, 1, now(), v_g);

  -- ── 12a. Los TRES estados del aviso, sin depender del calendario ──────────
  -- El pendiente mas antiguo es el mes -5, con metas y sin sellar. Empujando su
  -- ventana se recorren los tres estados el dia que sea. Van ANTES del ciclo
  -- porque despues no queda ningun pendiente que mirar.
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'cierre_mes_ventana_desde';

  perform pg_temp.como(v_g);
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
  -- sigue abierto») gritaria «atascado» nueve horas cada dia 11, un mes tras
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
  -- pero como EXCEPCION, y el cron acabaria en rojo todos los dias del 1 al 10 de
  -- cada mes. Un cron que falla a diario deja de mirarse.
  execute $stub$
    create or replace function private.cierre_mes_ventana_desde(p_periodo date)
    returns timestamptz language sql stable set search_path = ''
    as $x$ select pg_catalog.now() + interval '1 year' $x$
  $stub$;
  perform pg_temp.como(null);
  v_r := crm.ciclo_cierre_mes();
  if (v_r->>'cerrados')::int <> 0 then
    raise exception 'FALLO 12a: con la ventana cerrada el ciclo cerro % meses', v_r->>'cerrados';
  end if;
  -- ⚠️ Y SIN FALLO. Mirar solo el contador no basta: desde que cada mes va en su
  -- subtransaccion, un ciclo SIN freno intentaria cerrar, `cerrar_periodo` lo
  -- rechazaria, y el ciclo se comeria la excepcion devolviendo igualmente
  -- `cerrados: 0`. El contador no distingue «no lo intento» de «lo intento y
  -- fallo», y son dos mundos: el segundo deja el cron en rojo del 1 al 10 de cada
  -- mes. (Lo cazo un mutante: al quitar el freno, esta prueba seguia en verde.)
  if (v_r->>'ok')::boolean is not true or v_r->'fallo' <> 'null'::jsonb then
    raise exception 'FALLO 12a: con la ventana cerrada el ciclo lo INTENTO y fallo, en vez de callarse — %', v_r;
  end if;

  execute v_def;
  if (private.cierre_mes_ventana_desde('2026-07-01'::date)
      at time zone 'America/Lima')::date is distinct from '2026-08-11'::date then
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
    perform pg_temp.como(null);
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
  -- El mes pasado solo entra si su ventana (el dia 11 de ESTE mes, a las 00:00)
  -- ya abrio.
  v_esperados := 2 + case when v_dia >= 11 then 1 else 0 end;

  perform pg_temp.como(null);
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
  if v_n <> (case when v_dia >= 11 then 1 else 0 end) then
    raise exception 'FALLO 11: el mes pasado quedo % el dia % del mes',
      case when v_n = 1 then 'cerrado' else 'abierto' end, v_dia;
  end if;

  -- Idempotente: correrlo otra vez el mismo dia no cierra nada mas. Es lo que
  -- permite engancharlo a un cron DIARIO en vez de a una fecha, y que un fallo
  -- del dia 11 se repare solo el 12.
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
      perform pg_temp.como(v_quien);
      perform crm.ciclo_cierre_mes();
      raise exception 'FALLO 11: % pudo disparar el ciclo de cierre a mano', v_quien;
    exception when sqlstate '42501' then null;
    end;
  end loop;

  -- ── 12b. El aviso, ya con el ciclo pasado ─────────────────────────────────
  perform pg_temp.como(v_g);
  v_e := crm.cierre_mes_estado_fn();

  -- El mes en curso siempre dice cuando se sellara: es el aviso normal.
  if (v_e->'mes_en_curso'->>'cierra_el')::date
     is distinct from (v_m0 + interval '1 month' + interval '10 days')::date then
    raise exception 'FALLO 12b: el mes en curso dice que cierra el % — %',
      v_e->'mes_en_curso'->>'cierra_el', v_e;
  end if;
  if v_e->'ultimo_cerrado'->>'mes' is null then
    raise exception 'FALLO 12b: no reporta ningun mes cerrado y acaban de cerrarse varios — %', v_e;
  end if;

  -- Tras el ciclo no queda pendiente ninguno cuya ventana haya abierto: si el
  -- dia es >= 11 no queda nada; si es < 11, queda el mes pasado y en ventana.
  if v_dia >= 11 then
    if v_e->'pendiente' <> 'null'::jsonb then
      raise exception 'FALLO 12b: queda un mes pendiente despues del ciclo — %', v_e->'pendiente';
    end if;
  else
    if (v_e->'pendiente'->>'mes') is distinct from to_char(v_m1, 'YYYY-MM')
       or (v_e->'pendiente'->>'estado') is distinct from 'en_ventana' then
      raise exception 'FALLO 12b: el mes pasado deberia estar pendiente y en ventana el dia % — %', v_dia, v_e->'pendiente';
    end if;
    if (v_e->'pendiente'->>'dias_para_cierre')::int <> 11 - v_dia then
      raise exception 'FALLO 12b: faltan % dias segun la funcion y % segun el calendario',
        v_e->'pendiente'->>'dias_para_cierre', 11 - v_dia;
    end if;
  end if;

  -- El aviso es del reloj, pero no es publico.
  begin
    perform pg_temp.como(null);
    perform crm.cierre_mes_estado_fn();
    raise exception 'FALLO 12b: el estado del cierre se leyo sin identidad';
  exception when sqlstate '42501' then null;
  end;

  -- Lo ven los CUATRO roles que tienen pantalla, y ven LO MISMO: es estado de
  -- reloj, no datos de nadie. Si difiriera por rol, algo se habria colado.
  -- El coordinador entra a proposito: `crm.cumplimiento_metas_fn` le deja ver un
  -- mes cerrado, asi que negarle el aviso le dejaria un banner roto.
  foreach v_quien in array array[v_v, v_s, v_g, v_coord, v_dir] loop
    perform pg_temp.como(v_quien);
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
    insert into crm.meta_periodos (id, periodo, revision, publicada_en, publicada_por)
    values (v_mp_m9, v_m9, 1, now(), v_g);
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
  --     justo para lo que existe la ventana. (r6: las metas son inmutables en
  --     produccion —trg_meta_periodos_inmutables—: la fila de prueba ya no se
  --     borra, se deshace con un raise, como los cierres de prueba.)
  if v_dia < 11 then
    begin
      insert into crm.meta_periodos (id, periodo, revision, publicada_en, publicada_por)
      values ('55555555-5555-4555-8555-55555555556a', v_m1, 2, now(), v_g);
      raise exception using errcode = 'PT004', message = 'deshacer la meta de prueba';
    exception when sqlstate 'PT004' then null;
    end;
  end if;

  -- (1) Y para una fila que YA EXISTIERA —una anterior al candado—, las dos
  --     puertas del cierre siguen siendo las que impiden el daño. Se siembra con
  --     el trigger apagado, que es la forma exacta de modelar «esto ya estaba».
  alter table crm.meta_periodos disable trigger trg_meta_periodos_00_no_bajo_sellado;
  insert into crm.meta_periodos (id, periodo, revision, publicada_en, publicada_por)
  values (v_mp_m9, v_m9, 1, now(), v_g);
  alter table crm.meta_periodos enable trigger trg_meta_periodos_00_no_bajo_sellado;

  -- (a) No es candidato: el aviso no lo nombra.
  perform pg_temp.como(v_g);
  if (crm.cierre_mes_estado_fn()->'pendiente'->>'mes') is not distinct from to_char(v_m9, 'YYYY-MM') then
    raise exception 'FALLO 13: un mes por detras del sello se ofrecio como pendiente';
  end if;

  -- (b) El ciclo lo IGNORA, y no falla por su culpa. Que ignore en vez de
  --     reventar importa: si fallara, el cron quedaria en rojo cada dia para
  --     siempre por unas metas retroactivas.
  perform pg_temp.como(null);
  v_r := crm.ciclo_cierre_mes();
  if (v_r->>'cerrados')::int <> 0 or (v_r->>'ok')::boolean is not true then
    raise exception 'FALLO 13: el ciclo reacciono a unas metas retroactivas — %', v_r;
  end if;
  if exists (select 1 from crm.periodos_cerrados where periodo = v_m9) then
    raise exception 'FALLO 13: el ciclo sello un mes por detras de lo ya pagado';
  end if;

  -- (c) Y a mano tampoco. Ni gerencia ni el ciclo.
  begin
    perform pg_temp.como(v_g);
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
  -- Lo discrimina el EQUIPO DE HOY: desde el bloque 2 el vendedor esta bajo v_s2
  -- en `crm.equipo` (en el banco de calcos lo hacia un `vendedor_ids_visibles`
  -- que devolvia el mismo vendedor para CUALQUIER supervisor). Si la lectura del
  -- mes cerrado se apoyara en el equipo vivo, el supervisor AJENO veria al
  -- vendedor. Solo el `supervisor_id` SELLADO lo deja fuera.
  --
  -- Se mide sobre v_jun, sellado en el bloque 1 con el vendedor bajo v_s — y cuyo
  -- vendedor el bloque 2 ya paso a v_s2, asi que la foto es lo unico que queda
  -- diciendo de quien era.
  if (select f.supervisor_id from crm.cierre_mes_vendedor f
      where f.periodo = v_jun and f.vendedor_id = v_v) is distinct from v_s then
    raise exception 'FALLO 14: la foto no sello el supervisor del vendedor';
  end if;

  -- (a) El supervisor QUE ERA sigue viendolo.
  perform pg_temp.como(v_s);
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
  perform pg_temp.como(v_s2);
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
    perform pg_temp.como(v_quien);

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
  -- SI se vigila en cada ciclo es la ESTRUCTURA. Dos lecciones encima:
  --   · SIN COMENTARIOS: un `-- perform pg_advisory…` comentado pasaba en
  --     verde (falso positivo demostrado el 15/08);
  --   · LA LLAMADA COMPLETA, no las claves sueltas: una funcion con
  --     hashtext('crm.periodos_cerrados') en una expresion cualquiera y SIN
  --     pg_advisory_xact_lock tambien pasaba (demostrado el 16/08 — el check
  --     de orden ademas era VACUO con strpos=0). Se normaliza el prosrc
  --     (comentarios fuera, whitespace colapsado) y se exige el texto EXACTO
  --     de cada llamada.
  declare
    v_fuente text;
    v_quien2 text;
    v_var    text;
    v_llamada_pm text;
    v_llamada_g constant text :=
      $q$pg_advisory_xact_lock( pg_catalog.hashtext('crm.periodos_cerrados')::bigint );$q$;
  begin
    -- a) Los TRES tenedores hacen la LLAMADA por-mes completa (cada uno con
    --    su variable de mes: new.periodo / p_periodo / v_periodo).
    for v_quien2, v_var in select * from (values
      ('private.trg_metas_no_bajo_mes_sellado()', 'new.periodo'),
      ('crm.cerrar_periodo(date)', 'p_periodo'),
      ('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)', 'v_periodo')
    ) as t(quien, var) loop
      begin
        select regexp_replace(regexp_replace(p.prosrc, '--[^\n]*', '', 'g'), '\s+', ' ', 'g')
          into strict v_fuente
        from pg_catalog.pg_proc p where p.oid = v_quien2::regprocedure;
      exception when undefined_function or no_data_found then
        raise exception 'FALLO 17: no existe % — si cambio de firma, actualizar este bloque', v_quien2;
      end;
      v_llamada_pm := format(
        $q$pg_advisory_xact_lock( pg_catalog.hashtext('crm.periodos_cerrados'), (%s - date '2000-01-01')::integer );$q$,
        v_var);
      if strpos(v_fuente, v_llamada_pm) = 0 then
        raise exception 'FALLO 17: % no hace la LLAMADA por-mes completa al candado (comentada, mutada o con otras claves)', v_quien2;
      end if;
    end loop;
    -- b) Las DOS puertas hacen ademas la LLAMADA GLOBAL, ANTES de la por-mes.
    foreach v_quien2 in array array[
      'private.trg_metas_no_bajo_mes_sellado()',
      'crm.cerrar_periodo(date)'
    ] loop
      select regexp_replace(regexp_replace(p.prosrc, '--[^\n]*', '', 'g'), '\s+', ' ', 'g')
        into v_fuente
      from pg_catalog.pg_proc p where p.oid = v_quien2::regprocedure;
      if strpos(v_fuente, v_llamada_g) = 0 then
        raise exception 'FALLO 17: % no hace la LLAMADA GLOBAL completa — la carrera entre periodos distintos se reabre', v_quien2;
      end if;
      if strpos(v_fuente, v_llamada_g) > strpos(v_fuente, $q$hashtext('crm.periodos_cerrados'),$q$) then
        raise exception 'FALLO 17: en %, la llamada GLOBAL quedo DESPUES de la por-mes', v_quien2;
      end if;
    end loop;
    -- c) Y en el trigger, el candado GLOBAL antes de la lectura — NO vacuo:
    --    la presencia de ambos textos ya quedo exigida arriba.
    select regexp_replace(regexp_replace(p.prosrc, '--[^\n]*', '', 'g'), '\s+', ' ', 'g')
      into v_fuente
    from pg_catalog.pg_proc p
    where p.oid = 'private.trg_metas_no_bajo_mes_sellado()'::regprocedure;
    if strpos(v_fuente, 'select max(pc.periodo)') = 0 then
      raise exception 'FALLO 17: el trigger perdio su lectura del ultimo sellado';
    end if;
    if strpos(v_fuente, v_llamada_g) > strpos(v_fuente, 'select max(pc.periodo)') then
      raise exception 'FALLO 17: el candado del trigger quedo DESPUES de la lectura';
    end if;
  end;

  -- 22 bloques: 1, 2, 3, 4, 4bis, 5, 6, 6bis, 7, 8, 9, 10, 10bis, 12a, 11bis, 11,
  -- 12b, 13, 14, 15, 16 y 17 (hasta el 09/10/2026 decia 22 con 21 bloques).
  raise notice 'ORACULO DEL CIERRE DE MES: 22/22 OK';
end;
$oraculo$;

rollback;

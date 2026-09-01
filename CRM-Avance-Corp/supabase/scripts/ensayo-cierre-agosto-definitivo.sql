-- =====================================================================
-- ENSAYO DEL PRIMER SELLO (Fase 2 del P-055) — agosto 2026 · v2
-- =====================================================================
-- QUE ES: el cierre real de agosto, ejecutado contra PRODUCCION dentro de
-- un bloque que SIEMPRE termina en `raise`.
--
-- ⚠️ LO QUE ESTE ENSAYO **NO** DEMUESTRA (corregido en v2 tras la
--    refutacion del 01/09 — la v1 afirmaba lo contrario y era FALSO):
--    **agosto NO esta congelado el 01/09.** La ventana de ajuste del 1 al 10
--    existe precisamente porque el mes todavia admite correcciones. Medido,
--    hay al menos cuatro caminos vivos por los que la foto puede moverse
--    entre hoy y el 10/09:
--      1. ANULACIONES — `conversion_episodios` evalua
--         `cierre_externo_anulado(lead_id)` EN VIVO (25 asignaciones
--         convertidas de agosto expuestas).
--      2. REPUBLICACION DE METAS — `meta_periodos` de agosto ya va por la
--         REVISION 14; `cerrar_periodo` toma `order by revision desc limit 1`.
--      3. OPERACIONES DE CARTERA — la pierna 'operacion' filtra por la
--         COLUMNA `periodo`, no por fechas: en septiembre se puede registrar
--         una operacion con periodo de agosto (aporta 1.0, frente a 0.15 de
--         un referido).
--      4. ATRIBUCION — la pierna usa `analista_atribuido_cadena(...)`, que es
--         politica de lectura VIVA: si la cadena cambia, cambia a quien cuenta.
--    ⇒ Que la huella del 10/09 sea DISTINTA es lo NORMAL, no un fallo.
--    Por eso el acto E hashea las ENTRADAS: sirven para separar
--    «cambio el dato» (legitimo) de «cambio la logica» (rojo de verdad).
--
-- LO QUE SI DEMUESTRA: que el MECANISMO funciona punta a punta contra los
-- datos reales de agosto — el ciclo automatico elige agosto y solo agosto,
-- sella, los candados rebotan — y deja una LINEA BASE con la que comparar.
--
-- FIDELIDAD (mejor que el ensayo del 29/08): de los DOS candados de
-- calendario solo se neutraliza UNO, la ventana de ajuste. El otro («el mes
-- tiene que haber terminado») lo pasa agosto POR SI MISMO ahora que estamos
-- en septiembre, asi que se deja INTACTO y se mide que pasa solo.
--
-- ⚠️ RASTRO CONSCIENTE: no se escribe en NINGUNA TABLA, pero
-- `log_min_error_statement = error` en este proyecto, asi que el mensaje del
-- `raise` y la sentencia entera QUEDAN en los Postgres Logs de Supabase, y
-- eso no lo borra ningun rollback. Por eso el payload NO lleva nombres de
-- personas: solo cifras, huellas y los ultimos 8 caracteres del id. La foto
-- con nombres se mira en las pantallas del CRM, no aqui.
--
-- ⚠️ MIENTRAS CORRE retiene el candado global de cierre
-- (`pg_advisory_xact_lock` sobre crm.periodos_cerrados): no publicar metas ni
-- anular contratos en ese minuto, y no correrlo cerca de las 09:20 de Lima
-- (hora del cron `crm-cierre-mes-diario`).
--
-- COMO SE CORRE (Miguel, con `!`):
--   npx supabase db query --linked --file supabase/scripts/ensayo-cierre-agosto-definitivo.sql
-- Termina SIEMPRE con un error `ENSAYO-F2` — ESO es el exito: significa que
-- se deshizo entero. Si terminara sin error, algo va mal.
--
-- RECOMENDADO: volver a correrlo la VISPERA (09/09) — ese si es un control
-- proximo al sello. Y el 10/09 comparar con
-- supabase/scripts/verificar-sello-contra-control.sql
-- =====================================================================

do $ensayo$
declare
  v_periodo      date := date '2026-08-01';
  v_mes_actual   date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_src          text;
  v_src_ciclo    text;
  v_cfg          text[];
  v_cfg_ciclo    text[];
  v_secdef       boolean;
  v_secdef_ciclo boolean;
  v_nuevo        text;
  v_nuevo_ciclo  text;
  v_n            int;
  v_ventana      timestamptz;
  v_candado_mes  boolean;

  k_candado_mes  constant text := 'if p_periodo >= v_mes_actual then';
  k_candado_vent constant text := 'if now() < v_ventana then';
  k_ciclo_vent   constant text := 'exit when now() < private.cierre_mes_ventana_desde(v_periodo);';
  k_ciclo_llama  constant text := 'crm.cerrar_periodo(v_periodo)';

  -- Acto A (el camino real: el ciclo automatico)
  v_a_res        jsonb;
  v_a_ms         numeric;
  v_a_huella     text;
  v_a_filas      int;
  v_a_foto       jsonb;
  v_a_sello      jsonb;
  -- Acto B (llamada directa, sin el ciclo)
  v_b_res        jsonb;
  v_b_huella     text;
  -- Actos C y D
  v_c            text;
  v_d            text;
  -- Acto E (entradas)
  v_e_conv       text;
  v_e_prod       text;
  v_e_metas      text;
  v_e_detalle    text;
  v_e_nombres    text;
  v_e_referidos  int;
  v_e_deudas     text;
  v_e_suelo      timestamptz;
  v_periodo_id   uuid;
  v_revision     int;
  v_factor       numeric;
  v_ini          timestamptz;
  v_fin          timestamptz;

  v_t0           timestamptz;
  v_payload      jsonb;
begin
  -- Huellas reproducibles: sin clavar estos dos GUC, un timestamptz dentro de
  -- una fila hasheada cambia de texto segun la sesion que lo corra. Local a la
  -- transaccion; no afecta a cerrar_periodo, que corta con `at time zone
  -- 'America/Lima'` explicito en todos sus limites.
  perform pg_catalog.set_config('TimeZone', 'UTC', true);
  perform pg_catalog.set_config('DateStyle', 'ISO, MDY', true);

  -- ---------------------------------------------------------------
  -- 0) PRECONDICIONES. Todo fail-closed.
  -- ---------------------------------------------------------------
  if (select auth.uid()) is not null then
    raise exception 'ENSAYO ABORTADO: la sesion trae claims. El sello real lo dispara el reloj SIN uid; con uid se probaria otro camino.';
  end if;

  if to_regprocedure('crm.ensayo_f2_cerrar(date)') is not null
     or to_regprocedure('crm.ensayo_f2_ciclo()') is not null then
    raise exception 'ENSAYO ABORTADO: hay clones ensayo_f2 residuales en crm. Averiguar COMO sobrevivieron a un rollback antes de seguir.';
  end if;

  if exists (select 1 from crm.periodos_cerrados) then
    raise exception 'ENSAYO ABORTADO: ya hay % mes(es) sellado(s). Este ensayo asume el registro virgen del primer sello.',
      (select count(*) from crm.periodos_cerrados);
  end if;

  if v_periodo >= v_mes_actual then
    raise exception 'ENSAYO ABORTADO: agosto no ha terminado segun el reloj de Lima (mes actual %). El candado que se deja INTACTO no pasaria solo.', v_mes_actual;
  end if;

  v_ventana := private.cierre_mes_ventana_desde(v_periodo);
  if v_ventana is null then
    raise exception 'ENSAYO ABORTADO: cierre_mes_ventana_desde no devuelve ventana para %', v_periodo;
  end if;
  if now() >= v_ventana then
    raise exception 'ENSAYO ABORTADO: la ventana (%) ya paso — este guion sobra: el cierre se puede correr de verdad.', v_ventana;
  end if;

  -- ---------------------------------------------------------------
  -- 1) LEER LAS FUNCIONES VIVAS Y ANCLAR SU FORMA. Se clona lo que HAY.
  -- ---------------------------------------------------------------
  select p.prosrc, p.proconfig, p.prosecdef into v_src, v_cfg, v_secdef
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm' and p.proname = 'cerrar_periodo'
    and p.oid::regprocedure::text = 'crm.cerrar_periodo(date)';
  if v_src is null then
    raise exception 'ENSAYO ABORTADO: no existe crm.cerrar_periodo(date)';
  end if;
  if v_cfg is distinct from array['search_path=""'] or not v_secdef then
    raise exception 'ENSAYO ABORTADO: cerrar_periodo cambio de forma (secdef=%, cfg=%)', v_secdef, v_cfg;
  end if;

  -- El candado del mes en curso DEBE existir, y NO se toca: se MIDE.
  v_candado_mes := position(k_candado_mes in v_src) > 0;
  if not v_candado_mes then
    raise exception 'ENSAYO ABORTADO: no encuentro el candado del mes en curso. La funcion cambio: revisar el guion antes de fiarse.';
  end if;

  -- El candado de la ventana: el UNICO que se neutraliza, y solo si aparece 1 vez.
  v_n := (length(v_src) - length(replace(v_src, k_candado_vent, ''))) / length(k_candado_vent);
  if v_n <> 1 then
    raise exception 'ENSAYO ABORTADO: el candado de ventana aparece % veces (esperaba exactamente 1)', v_n;
  end if;
  v_nuevo := replace(v_src, k_candado_vent, 'if false then /* ENSAYO-F2: ventana neutralizada */');
  if v_nuevo = v_src then
    raise exception 'ENSAYO ABORTADO: la sustitucion del candado no cambio el cuerpo';
  end if;

  select p.prosrc, p.proconfig, p.prosecdef into v_src_ciclo, v_cfg_ciclo, v_secdef_ciclo
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm' and p.proname = 'ciclo_cierre_mes'
    and p.oid::regprocedure::text = 'crm.ciclo_cierre_mes()';
  if v_src_ciclo is null then
    raise exception 'ENSAYO ABORTADO: no existe crm.ciclo_cierre_mes()';
  end if;
  if v_cfg_ciclo is distinct from array['search_path=""'] or not v_secdef_ciclo then
    raise exception 'ENSAYO ABORTADO: ciclo_cierre_mes cambio de forma (secdef=%, cfg=%)', v_secdef_ciclo, v_cfg_ciclo;
  end if;

  v_n := (length(v_src_ciclo) - length(replace(v_src_ciclo, k_ciclo_vent, ''))) / length(k_ciclo_vent);
  if v_n <> 1 then
    raise exception 'ENSAYO ABORTADO: la espera de ventana del ciclo aparece % veces (esperaba 1)', v_n;
  end if;
  v_n := (length(v_src_ciclo) - length(replace(v_src_ciclo, k_ciclo_llama, ''))) / length(k_ciclo_llama);
  if v_n <> 1 then
    raise exception 'ENSAYO ABORTADO: la llamada a cerrar_periodo dentro del ciclo aparece % veces (esperaba 1)', v_n;
  end if;
  v_nuevo_ciclo := replace(v_src_ciclo, k_ciclo_vent, '-- ENSAYO-F2: espera de ventana neutralizada');
  v_nuevo_ciclo := replace(v_nuevo_ciclo, k_ciclo_llama, 'crm.ensayo_f2_cerrar(v_periodo)');

  -- Los clones viven SOLO dentro de esta transaccion (el DDL es transaccional).
  -- Nacen SECURITY DEFINER, asi que se les quita EXECUTE a public en el acto:
  -- durante los segundos que existen no deben ser llamables por nadie mas.
  execute format(
    'create function crm.ensayo_f2_cerrar(p_periodo date) returns jsonb language plpgsql security definer set search_path to %L as %s',
    '', quote_literal(v_nuevo));
  execute 'revoke execute on function crm.ensayo_f2_cerrar(date) from public';
  execute format(
    'create function crm.ensayo_f2_ciclo() returns jsonb language plpgsql security definer set search_path to %L as %s',
    '', quote_literal(v_nuevo_ciclo));
  execute 'revoke execute on function crm.ensayo_f2_ciclo() from public';

  -- ---------------------------------------------------------------
  -- 2) ACTO E — HUELLA DE LAS ENTRADAS (antes de sellar).
  --    Es el discriminador del 10/09: si la foto cambia Y estas huellas
  --    cambian, cambio el DATO (legitimo). Si la foto cambia y estas NO,
  --    cambio la LOGICA (rojo).
  -- ---------------------------------------------------------------
  v_ini    := v_periodo::timestamp at time zone 'America/Lima';
  v_fin    := (v_periodo + interval '1 month')::timestamp at time zone 'America/Lima';
  v_factor := private.peso_referido_conversion(v_periodo);
  select mp.id, mp.revision into v_periodo_id, v_revision
  from crm.meta_periodos mp
  where mp.periodo = v_periodo order by mp.revision desc limit 1;

  select md5(coalesce(string_agg(md5(c::text), '|' order by c.analista_id), 'vacio'))
    into v_e_conv
  from private.conversion_mensual_por_vendedor(v_ini, v_fin, true, '{}'::uuid[], v_factor) c;

  select md5(coalesce(string_agg(md5(r::text), '|' order by r.vendedor_id, r.categoria, r.moneda), 'vacio'))
    into v_e_prod
  from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r;

  -- Las metas y su detalle, SIN columnas de tiempo (irrelevantes para la foto
  -- y dependientes de la sesion que las lea).
  select md5(coalesce(string_agg(
           md5((to_jsonb(mv) - 'creado_en' - 'actualizado_en')::text), '|' order by mv.id), 'vacio'))
    into v_e_metas
  from crm.metas_vendedor mv where mv.meta_periodo_id = v_periodo_id;

  select md5(coalesce(string_agg(
           md5((to_jsonb(d) - 'creado_en' - 'actualizado_en')::text), '|' order by d.id), 'vacio'))
    into v_e_detalle
  from crm.metas_vendedor_detalle d
  join crm.metas_vendedor mv on mv.id = d.meta_vendedor_id
  where mv.meta_periodo_id = v_periodo_id;

  -- Los nombres entran en la foto (columna nombre_completo): si alguien
  -- corrige una ficha, la foto cambia sin que cambie ninguna cifra.
  select md5(coalesce(string_agg(
           md5(pf.id::text || coalesce(pf.nombre_completo, '')), '|' order by pf.id), 'vacio'))
    into v_e_nombres
  from public.perfiles pf
  where pf.id in (
    select mv.vendedor_id from crm.metas_vendedor mv where mv.meta_periodo_id = v_periodo_id
    union
    select mv.supervisor_id from crm.metas_vendedor mv where mv.meta_periodo_id = v_periodo_id
  );

  select count(*) into v_e_referidos
  from crm.leads l
  where l.origen = 'referido' and l.creado_en >= v_ini and l.creado_en < v_fin;

  -- Las deudas por FILA, no solo el conteo: saldar_ajustes consume su contenido.
  select md5(coalesce(string_agg(
           md5((to_jsonb(a) - 'creado_en' - 'saldado_en')::text), '|' order by a.id), 'vacio'))
    into v_e_deudas
  from crm.ajustes_mes_cerrado a;

  select min(la.asignado_en) into v_e_suelo
  from crm.lead_asignaciones la where not la.aproximado;

  -- ---------------------------------------------------------------
  -- 3) ACTO A — EL CAMINO REAL: el ciclo automatico.
  --    Es exactamente lo que hara el cron el 10/09 a las 09:20 de Lima.
  -- ---------------------------------------------------------------
  begin
    v_t0 := clock_timestamp();
    v_a_res := crm.ensayo_f2_ciclo();
    v_a_ms  := round(extract(epoch from (clock_timestamp() - v_t0)) * 1000, 1);

    select count(*), md5(coalesce(string_agg(md5(f::text), '|' order by f.vendedor_id), 'vacio'))
      into v_a_filas, v_a_huella
    from crm.cierre_mes_vendedor f where f.periodo = v_periodo;

    -- La foto SIN NOMBRES: el payload acaba en los logs del servidor (ver
    -- cabecera). Las cifras y la forma se ven; quien es quien, no.
    select jsonb_agg(jsonb_build_object(
             'id8', right(f.vendedor_id::text, 8), 'estado', f.estado,
             'divisor', f.divisor, 'numerador', f.numerador, 'pct', f.conversion_pct,
             'no_ref', f.cierres_no_referidos, 'ref', f.cierres_referidos,
             'arrastre', f.cierres_de_arrastre, 'recibidos', f.referidos_recibidos,
             'aj_num', f.ajuste_numerador, 'aj_pen', f.ajuste_pen, 'aj_usd', f.ajuste_usd,
             'objetivo', f.conversion_objetivo)
           order by f.numerador desc nulls last, f.vendedor_id)
      into v_a_foto
    from crm.cierre_mes_vendedor f where f.periodo = v_periodo;

    -- La fila del sello, SIN `cerrado_en` (el unico dato volatil).
    select jsonb_build_object(
             'periodo', pc.periodo, 'automatico', pc.automatico,
             'cerrado_por', pc.cerrado_por, 'ponderacion_referido', pc.ponderacion_referido,
             'meta_revision', pc.meta_revision, 'cobertura', pc.cobertura)
      into v_a_sello
    from crm.periodos_cerrados pc where pc.periodo = v_periodo;

    raise exception 'DESHACER_SUB' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'DESHACER_SUB' then raise; end if;
  end;

  -- ASERCION DURA. `ciclo_cierre_mes` se traga CUALQUIER error de
  -- `cerrar_periodo` y devuelve {ok:false, cerrados:0, fallo:{...}} sin
  -- excepcion: sin esto el guion podria imprimir una huella de md5('vacio')
  -- como si fuera un control bueno.
  if v_a_res is null
     or not coalesce((v_a_res->>'ok')::boolean, false)
     or coalesce((v_a_res->>'cerrados')::int, 0) <> 1
     or coalesce(v_a_filas, 0) = 0
     or v_a_sello is null then
    raise exception 'ENSAYO ABORTADO: el ciclo NO sello agosto. resultado=% filas=% sello=%',
      v_a_res, v_a_filas, v_a_sello;
  end if;

  -- ---------------------------------------------------------------
  -- 4) ACTO B — la llamada DIRECTA a cerrar_periodo, sin pasar por el ciclo.
  --    ⚠️ NO es «el camino de gerencia»: esta sesion no tiene uid, asi que
  --    tambien recorre la rama automatica. La rama de gerencia (con uid) no
  --    se puede probar aqui — inyectar claims contamina la transaccion
  --    entera (trampa ya documentada) — y va a un banco.
  --    Lo que SI prueba: que el ciclo no altera lo que sella.
  -- ---------------------------------------------------------------
  begin
    v_b_res := crm.ensayo_f2_cerrar(v_periodo);
    select md5(coalesce(string_agg(md5(f::text), '|' order by f.vendedor_id), 'vacio'))
      into v_b_huella
    from crm.cierre_mes_vendedor f where f.periodo = v_periodo;
    raise exception 'DESHACER_SUB' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'DESHACER_SUB' then raise; end if;
  end;

  -- ---------------------------------------------------------------
  -- 5) ACTO C — cerrar dos veces tiene que rebotar con P0409.
  -- ---------------------------------------------------------------
  begin
    perform crm.ensayo_f2_cerrar(v_periodo);
    begin
      perform crm.ensayo_f2_cerrar(v_periodo);
      v_c := 'FALLO: el segundo cierre NO reboto';
    exception
      when sqlstate 'P0409' then v_c := 'OK P0409: ' || sqlerrm;
      when others then v_c := 'RARO ' || sqlstate || ': ' || sqlerrm;
    end;
    raise exception 'DESHACER_SUB' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'DESHACER_SUB' then raise; end if;
  end;

  -- ---------------------------------------------------------------
  -- 6) ACTO D — con agosto sellado, sellar julio (por detras) rebota.
  --    Se comprueba el MENSAJE, no solo el 22023: cuatro candados distintos
  --    de cerrar_periodo comparten ese sqlstate y confundirlos daria un
  --    verde falso.
  -- ---------------------------------------------------------------
  begin
    perform crm.ensayo_f2_cerrar(v_periodo);
    begin
      perform crm.ensayo_f2_cerrar(date '2026-07-01');
      v_d := 'FALLO: sellar hacia atras NO reboto';
    exception
      when sqlstate '22023' then
        v_d := case when strpos(sqlerrm, 'ya esta cerrado y es posterior') > 0
                    then 'OK 22023 (candado 2quater, el que toca): '
                    else 'DUDOSO 22023 (reboto por OTRO candado): ' end || sqlerrm;
      when others then v_d := 'RARO ' || sqlstate || ': ' || sqlerrm;
    end;
    raise exception 'DESHACER_SUB' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'DESHACER_SUB' then raise; end if;
  end;

  -- ---------------------------------------------------------------
  -- 7) EL PAYLOAD. El titular va FUERA del json: `jsonb` ordena sus claves
  --    por longitud, asi que si el canal truncara, lo importante se perderia.
  -- ---------------------------------------------------------------
  v_payload := jsonb_build_object(
    'ensayo', 'F2-CIERRE-AGOSTO v2',
    'corrido_en', to_char(now() at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI:SS') || ' Lima',
    'mes_actual_lima', v_mes_actual,
    'ventana_real', to_char(v_ventana at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI'),
    'candado_mes_medido_intacto', v_candado_mes,
    'meta_revision_vigente', v_revision,
    'lectura_10_09', 'Si la huella difiere el 10/09 NO es un fallo: agosto sigue abierto hasta el sello. Comparar primero E_huella_entradas — si tambien cambiaron, cambio el DATO (legitimo); si NO cambiaron, cambio la LOGICA (rojo).',
    'A_ciclo_automatico', jsonb_build_object(
      'resultado', v_a_res, 'ms_techo_plan_frio', v_a_ms, 'personas', v_a_filas,
      'HUELLA_01_09', v_a_huella, 'sello', v_a_sello),
    'B_llamada_directa_sin_ciclo', jsonb_build_object(
      'resultado', v_b_res, 'huella', v_b_huella,
      'IDENTICO_A_A', (v_b_huella = v_a_huella)),
    'C_cerrar_dos_veces', v_c,
    'D_sellar_hacia_atras', v_d,
    'E_huella_entradas', jsonb_build_object(
      'conversion', v_e_conv, 'produccion', v_e_prod, 'metas', v_e_metas,
      'metas_detalle', v_e_detalle, 'nombres', v_e_nombres,
      'leads_referidos_agosto', v_e_referidos, 'deudas', v_e_deudas,
      'suelo_ledger', v_e_suelo),
    'zz_foto_sin_nombres', v_a_foto
  );

  raise exception E'ENSAYO-F2 ok=% personas=% HUELLA_01_09=% B_IGUAL=% C=% \n%',
    v_a_res->>'ok', v_a_filas, v_a_huella, (v_b_huella = v_a_huella),
    left(coalesce(v_c, '?'), 12), jsonb_pretty(v_payload);
end;
$ensayo$;

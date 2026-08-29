-- P-055 Fase 3.5 - Que los contratos de prueba dejen de contar.
--
-- TOCA `public` y `crm` (siete funciones de metrica): con permiso explicito de
-- Miguel. Es la segunda mitad de la decision 6: «444444 y 888282 son demos (de
-- Kirk) → SE EXCLUYEN de metricas y ranking». La migracion 20260829180500 los
-- marco; hasta aqui nadie leia esa marca, asi que seguian contando.
--
-- QUE SE MIDIO ANTES DE TOCAR NADA (2026-08-29). De las funciones que agregan
-- contratos:
--   SI los cuentan hoy, y se arreglan las seis de este lote:
--     crm.contratos_por_periodo_comercial_fn  (la lista del periodo, gerencia)
--     crm.metricas_capital_mes_fn             (capital colocado por mes)
--     crm.metricas_vencimientos_fn            (lo que esta por vencer)
--     crm.metricas_pagos_mes_fn               (los pagos del mes)
--     crm.resumen_cartera_clientes_fn         (la cartera por cliente)
--     private.metricas_conversiones_implementacion (7 subconsultas de capital)
--   El NUCLEO (private.produccion_mes_por_vendedor) va APARTE, en 20260829182200:
--   esa migracion lo reescribe entero para que ademas lea al analista que
--   cierra (P0-1 de Codex), y reescribir la misma funcion dos veces en el mismo
--   tren es pedirse una divergencia.
--   NO hace falta tocarla, y no es un olvido:
--     private.metricas_reuniones_implementacion enlaza por `crm.leads.contrato_id`,
--     que esta MUERTO -0 de 466 contratos tienen lead enlazado, medido hoy-, asi
--     que nunca ve un contrato.
--   NO son metricas y se dejan como estan, a proposito:
--     private.contratos_afectados_por_anulacion, private.registrar_ajuste_si_mes_cerrado
--     y public.cerrar_contrato son operativas. Un demo se puede cerrar y anular
--     como cualquier otro; lo que no debe es SUMAR.
--
-- COMO SE PARCHEA, y por que asi. No se vuelve a teclear ninguna funcion: se
-- toma su definicion viva con `pg_get_functiondef` -que conserva lenguaje,
-- volatilidad, `security definer`, `search_path` y tipo de retorno- y se
-- sustituye la TABLA por su version filtrada, conservando el alias:
--     from public.contratos c   ->  from (select * from public.contratos
--                                          where not es_demo) c
-- El alias no cambia, asi que ni una sola linea del resto de la consulta se
-- toca. Postgres aplana esa subconsulta, asi que no cuesta rendimiento.
--
-- Cada funcion se ancla por `md5` y se comprueba que tiene EXACTAMENTE los
-- sitios esperados. Si una cambio, o si tiene mas o menos referencias de las
-- medidas, la migracion ABORTA en vez de parchear a ciegas.

begin;

do $parche$
declare
  v_reg      regprocedure;
  v_huella   text;
  v_sitios   integer;
  v_menciones integer;
  v_def      text;
  v_nuevo    text;
  v_hechos   integer;
  v_despues  integer;
  v_total    integer := 0;
  -- firma COMPLETA (hallazgo M3: sin firma, una sobrecarga futura haria que se
  -- parcheara una y el postflight leyera otra) | huella | sitios | menciones
  -- TOTALES de 'public.contratos' en la definicion (hallazgo M1: el invariante
  -- que el postflight comprueba de verdad).
  v_lista    text[][] := array[
    ['crm.contratos_por_periodo_comercial_fn(date)',                                   '0c776bae77234415ddd880683a10e304', '1', '1'],
    ['crm.metricas_capital_mes_fn(integer)',                                           '0a2fbbf1c792681e3effb7545144b268', '1', '1'],
    ['crm.metricas_vencimientos_fn(integer)',                                          'ea3c36482795e4e3714281edc3ac9f65', '1', '1'],
    ['crm.metricas_pagos_mes_fn(integer)',                                             'e87984402599848c595a3e93d8e72e28', '1', '1'],
    ['crm.resumen_cartera_clientes_fn()',                                              '57cd733cbaa4ab968f4f1791d313e4f4', '1', '1'],
    ['private.metricas_conversiones_implementacion(date,date,text)',                   'b4875f18423045c23c52b1cd8dfe25c3', '7', '7']
  ];
  i integer;
begin
  set local lock_timeout = '5s';

  if not exists (select 1 from pg_attribute
                 where attrelid='public.contratos'::regclass
                   and attname='es_demo' and not attisdropped) then
    raise exception 'Falta la migracion 20260829180000 (la marca de demo): ABORTA';
  end if;

  for i in 1 .. array_length(v_lista, 1) loop
    v_reg      := v_lista[i][1]::regprocedure;
    v_huella   := v_lista[i][2];
    v_sitios   := v_lista[i][3]::integer;
    v_menciones := v_lista[i][4]::integer;

    select md5(p.prosrc), pg_get_functiondef(p.oid)
      into v_nuevo, v_def
    from pg_proc p where p.oid = v_reg;

    if v_nuevo <> v_huella then
      raise exception '% cambio desde que se midio (huella viva %): ABORTA', v_reg, v_nuevo;
    end if;

    -- Los sitios a parchear Y las menciones totales, medidos ANTES de tocar.
    v_hechos :=
        (length(v_def) - length(replace(v_def, 'from public.contratos c'  || E'\n', ''))) / length('from public.contratos c'  || E'\n')
      + (length(v_def) - length(replace(v_def, 'from public.contratos ct' || E'\n', ''))) / length('from public.contratos ct' || E'\n')
      + (length(v_def) - length(replace(v_def, 'join public.contratos ct  on', ''))) / length('join public.contratos ct  on');
    if v_hechos <> v_sitios then
      raise exception '% tiene % sitios y se esperaban %: ABORTA', v_reg, v_hechos, v_sitios;
    end if;
    -- M1: si hay MAS menciones de la tabla que sitios parcheables (un alias
    -- nuevo, un espaciado distinto), esta migracion dejaria una puerta sin
    -- filtrar Y NO SE ENTERARIA. Entonces no se publica: se ABORTA.
    if (length(v_def) - length(replace(v_def, 'public.contratos', ''))) / length('public.contratos') <> v_menciones then
      raise exception '% menciona public.contratos un numero inesperado de veces: ABORTA (revisar a mano)', v_reg;
    end if;

    v_nuevo := v_def;
    v_nuevo := replace(v_nuevo, 'from public.contratos c'  || E'\n',
                                'from (select * from public.contratos where not es_demo) c'  || E'\n');
    v_nuevo := replace(v_nuevo, 'from public.contratos ct' || E'\n',
                                'from (select * from public.contratos where not es_demo) ct' || E'\n');
    v_nuevo := replace(v_nuevo, 'join public.contratos ct  on',
                                'join (select * from public.contratos where not es_demo) ct  on');
    if v_nuevo = v_def then
      raise exception 'El parche de % no cambio nada: ABORTA', v_reg;
    end if;

    execute v_nuevo;

    -- El invariante de verdad (M1): tras parchear, las menciones con filtro
    -- son EXACTAMENTE los sitios, y las totales no cambiaron.
    select (length(p.prosrc) - length(replace(p.prosrc, '(select * from public.contratos where not es_demo)', ''))) / length('(select * from public.contratos where not es_demo)')
      into v_despues from pg_proc p where p.oid = v_reg;
    if v_despues <> v_sitios then
      raise exception '% quedo con % filtros y se esperaban %: ABORTA', v_reg, v_despues, v_sitios;
    end if;

    v_total := v_total + v_hechos;
  end loop;

  raise notice 'PARCHE: 6 funciones, % sitios filtrados', v_total;
end
$parche$;

-- --------------------------------------------------------------- POSTFLIGHT --
do $postflight$
declare
  v_reg regprocedure;
  v_src text;
  v_secdef boolean;
  v_cfg text[];
  v_duenyo text;
  v_falta text := '';
  -- firma | filtros esperados | menciones totales esperadas
  v_lista text[][] := array[
    ['crm.contratos_por_periodo_comercial_fn(date)',                      '1', '1'],
    ['crm.metricas_capital_mes_fn(integer)',                              '1', '1'],
    ['crm.metricas_vencimientos_fn(integer)',                             '1', '1'],
    ['crm.metricas_pagos_mes_fn(integer)',                                '1', '1'],
    ['crm.resumen_cartera_clientes_fn()',                                 '1', '1'],
    ['private.metricas_conversiones_implementacion(date,date,text)',      '7', '7']
  ];
  i integer;
  v_filtros integer;
begin
  for i in 1 .. array_length(v_lista, 1) loop
    v_reg := v_lista[i][1]::regprocedure;

    select p.prosrc, p.prosecdef, p.proconfig,
           (select rolname from pg_roles where oid = p.proowner)
      into v_src, v_secdef, v_cfg, v_duenyo
    from pg_proc p where p.oid = v_reg;

    -- M1: el invariante honesto — filtros EXACTOS y menciones totales intactas,
    -- no «los mismos tres patrones que acabo de reemplazar dan cero».
    v_filtros := (length(v_src) - length(replace(v_src, '(select * from public.contratos where not es_demo)', ''))) / length('(select * from public.contratos where not es_demo)');
    if v_filtros <> v_lista[i][2]::integer then
      v_falta := v_falta || v_reg::text || ' (filtros ' || v_filtros || ', esperados ' || v_lista[i][2] || ') ';
    end if;
    if (length(v_src) - length(replace(v_src, 'public.contratos', ''))) / length('public.contratos') <> v_lista[i][3]::integer then
      v_falta := v_falta || v_reg::text || ' (menciones totales inesperadas) ';
    end if;

    -- M2: reescribir 7 DEFINER de golpe exige verificar que SIGAN siendolo y
    -- que conserven SU search_path fijado. OJO: no todas llevan el vacio — tres
    -- metricas viven con `search_path=private, public, crm` desde antes de esta
    -- fase, y cambiarles eso aqui seria otra migracion (y otro riesgo). El
    -- invariante honesto es «sigue teniendo un search_path fijado», el que sea.
    if not v_secdef then
      v_falta := v_falta || v_reg::text || ' (dejo de ser SECURITY DEFINER) ';
    end if;
    if v_cfg is null or not exists (select 1 from unnest(v_cfg) c where c like 'search_path=%') then
      v_falta := v_falta || v_reg::text || ' (perdio su search_path fijado) ';
    end if;
    if v_duenyo <> 'postgres' then
      v_falta := v_falta || v_reg::text || ' (cambio de dueno) ';
    end if;
  end loop;

  if v_falta <> '' then
    raise exception 'POSTFLIGHT: %', v_falta;
  end if;

  -- La que NO se toca sigue sin tocar.
  select prosrc into v_src from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='metricas_reuniones_implementacion';
  if strpos(v_src, 'where not es_demo') > 0 then
    raise exception 'POSTFLIGHT: se toco metricas_reuniones_implementacion, que no habia que tocar';
  end if;

  raise notice 'POSTFLIGHT OK: los contratos de prueba ya no cuentan en ninguna de las 6 metricas de este lote';
end
$postflight$;

commit;

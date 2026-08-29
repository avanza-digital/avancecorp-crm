-- P-055 Fase 1.2 - La malla anti-NaN de los montos (Miguel, 28/08).
--
-- EL AGUJERO, en una linea: en Postgres `NaN > 0` es VERDADERO. Un monto
-- invalido atraviesa cualquier validacion escrita como "tiene que ser mayor
-- que cero" y se queda dentro. Lo mismo hace 'Infinity'. Medido en produccion
-- el 28/08: NaN > 0 = true, Infinity > 0 = true.
--
-- QUE: se blindan las 16 casillas de dinero y de conteo del CIERRE DE MES y
-- del CRONOGRAMA DE PAGOS que hoy no tienen ninguna defensa contra eso.
--   * public.cronograma_pagos: monto_programado, monto_pagado.
--   * crm.cierre_mes_vendedor: las 7 numericas de la foto que se sella.
--   * crm.ajustes_mes_cerrado: las 6 de la deuda que arrastra de un mes a otro.
--   * crm.periodos_cerrados: la ponderacion del referido.
--
-- POR QUE AHORA Y NO DESPUES: las tres tablas del cierre estan VACIAS hoy
-- (0 filas las tres, contadas el 28/08). Blindar una tabla vacia no cuesta
-- nada. Despues del primer cierre real -que es el del 10/09- ya no.
-- `cronograma_pagos` si tiene datos: 4252 filas, minimo 10.83, ninguna <= 0 y
-- ninguna nula donde el CHECK exige valor. Medido antes de escribir esto.
--
-- LA FORMA DEL GUARDIAN: `x <> 'NaN' and x <> 'Infinity' and x <> '-Infinity'`.
-- Se lee raro y es exacto: en Postgres `NaN = NaN` es VERDADERO (asi ordena y
-- agrupa), de modo que `x <> 'NaN'` da FALSO justo cuando x es NaN, y el CHECK
-- lo rechaza. Igual con los infinitos.
--
-- SIN RANGOS DE NEGOCIO, A PROPOSITO. En el cierre solo se exige que el numero
-- sea un numero. Un tope o un suelo inventado aqui romperia el cierre del 10 en
-- vez de protegerlo: `crm.cerrar_periodo` sella `numerador` = bruto MENOS lo que
-- el mes absorbio de deudas viejas, y `conversion_pct` = 100 * ese neto /
-- divisor; ninguno de los dos tiene garantizado quedarse dentro de 0..100 ni
-- siquiera ser positivo. Los rangos, si algun dia se quieren, se deciden con la
-- foto del primer cierre delante (Fase 2 del plan), no antes de tenerla.
-- En `cronograma_pagos` si hay regla de negocio evidente y verificada contra
-- las 4252 filas: una cuota programada es mayor que cero, y un pago registrado
-- nunca es negativo.
--
-- NOTA DE TIPO, verificada en produccion: `numeric(12,2)` -el tipo de las dos
-- columnas del cronograma- RECHAZA los infinitos por si mismo ("numeric field
-- overflow") pero ACEPTA NaN sin protestar. Las clausulas de infinito ahi son
-- cinturon y tirantes; en el cierre, donde las columnas son `numeric` a secas,
-- son imprescindibles.
--
-- SOLO ANADE constraints; no modifica ni borra ninguna de las que ya existen.
--
-- FUERA DE ALCANCE A PROPOSITO (auditoria RLS, 28/08): queda UNA casilla de
-- dinero sin guardian fuera del cierre y del cronograma -
-- `crm.lead_asignaciones.monto_estimado`, cuyo CHECK es `is null or >= 0` y por
-- tanto deja pasar NaN igual que cualquier liston de un solo lado. Es una
-- estimacion del ledger de asignaciones, no dinero cobrado, y esta migracion se
-- cine a lo que el plan puso en la Fase 1; se recoge en la Fase 7 con el resto
-- del inventario de montos. Su gemela `crm.leads.monto_estimado` SI esta
-- cubierta, por casualidad afortunada: su CHECK tiene tope superior
-- (`<= 9999999999.99`) y un NaN no pasa un tope.
--
-- AUTORIZACION: toca `public.cronograma_pagos` (portal en produccion) con el OK
-- explicito de Miguel al aprobar la Fase 1 del PLAN MAESTRO P-055.

-- Que esto no forme cola delante del portal: `add constraint` toma ACCESS
-- EXCLUSIVE, y aunque validar 4252 filas es instantaneo, esperar detras de una
-- transaccion larga no lo es. Con el liston de 5 segundos, falla y se reintenta.
set local lock_timeout = '5s';

-- == Preflight: nada de esto existe ya, y los datos aguantan el liston ========
do $preflight$
declare
  v_malas bigint;
begin
  -- Por PAR (tabla, nombre): `conname` no es unico en toda la base, y una
  -- constraint homonima en otra tabla daria un falso "ya aplicada".
  if exists (
    select 1 from pg_catalog.pg_constraint c
    where c.contype = 'c'
      and (c.conrelid, c.conname) in (
        ('public.cronograma_pagos'::regclass, 'cronograma_pagos_monto_programado_valido'),
        ('public.cronograma_pagos'::regclass, 'cronograma_pagos_monto_pagado_valido'),
        ('crm.cierre_mes_vendedor'::regclass, 'cierre_mes_vendedor_numerador_finito'),
        ('crm.ajustes_mes_cerrado'::regclass, 'ajustes_mes_cerrado_numerador_finito'),
        ('crm.periodos_cerrados'::regclass,   'periodos_cerrados_ponderacion_referido_finito'))
  ) then
    raise exception 'la malla anti-NaN ya estaba puesta: re-basar antes de aplicar';
  end if;

  -- El liston contra los datos VIVOS del cronograma, antes de intentarlo.
  select count(*) into v_malas
  from public.cronograma_pagos
  where not (monto_programado > 0 and monto_programado <> 'NaN'::numeric)
     or (monto_pagado is not null and not (monto_pagado >= 0 and monto_pagado <> 'NaN'::numeric));
  if v_malas > 0 then
    raise exception 'PREFLIGHT: % cuotas no pasarian el liston; revisarlas antes de aplicar', v_malas;
  end if;

  -- Las tres tablas del cierre siguen vacias (si no, hay que medir antes).
  if (select count(*) from crm.cierre_mes_vendedor) > 0
     or (select count(*) from crm.ajustes_mes_cerrado) > 0
     or (select count(*) from crm.periodos_cerrados) > 0 then
    raise exception 'PREFLIGHT: el cierre ya tiene datos; medir el liston contra ellos antes de aplicar';
  end if;
end
$preflight$;

-- == 1. Cronograma de pagos: las dos casillas de dinero ======================
alter table public.cronograma_pagos
  add constraint cronograma_pagos_monto_programado_valido
  check (monto_programado > 0::numeric
         and monto_programado <> 'NaN'::numeric
         and monto_programado <> 'Infinity'::numeric
         and monto_programado <> '-Infinity'::numeric);

alter table public.cronograma_pagos
  add constraint cronograma_pagos_monto_pagado_valido
  check (monto_pagado is null
         or (monto_pagado >= 0::numeric
             and monto_pagado <> 'NaN'::numeric
             and monto_pagado <> 'Infinity'::numeric
             and monto_pagado <> '-Infinity'::numeric));

-- == 2. La foto que se sella cada mes ========================================
alter table crm.cierre_mes_vendedor
  add constraint cierre_mes_vendedor_numerador_finito
  check ((numerador <> 'NaN'::numeric and numerador <> 'Infinity'::numeric and numerador <> '-Infinity'::numeric));

alter table crm.cierre_mes_vendedor
  add constraint cierre_mes_vendedor_conversion_pct_finito
  check (conversion_pct is null or (conversion_pct <> 'NaN'::numeric and conversion_pct <> 'Infinity'::numeric and conversion_pct <> '-Infinity'::numeric));

alter table crm.cierre_mes_vendedor
  add constraint cierre_mes_vendedor_referidos_aporta_pct_finito
  check (referidos_aporta_pct is null or (referidos_aporta_pct <> 'NaN'::numeric and referidos_aporta_pct <> 'Infinity'::numeric and referidos_aporta_pct <> '-Infinity'::numeric));

alter table crm.cierre_mes_vendedor
  add constraint cierre_mes_vendedor_ajuste_numerador_finito
  check ((ajuste_numerador <> 'NaN'::numeric and ajuste_numerador <> 'Infinity'::numeric and ajuste_numerador <> '-Infinity'::numeric));

alter table crm.cierre_mes_vendedor
  add constraint cierre_mes_vendedor_ajuste_pen_finito
  check ((ajuste_pen <> 'NaN'::numeric and ajuste_pen <> 'Infinity'::numeric and ajuste_pen <> '-Infinity'::numeric));

alter table crm.cierre_mes_vendedor
  add constraint cierre_mes_vendedor_ajuste_usd_finito
  check ((ajuste_usd <> 'NaN'::numeric and ajuste_usd <> 'Infinity'::numeric and ajuste_usd <> '-Infinity'::numeric));

alter table crm.cierre_mes_vendedor
  add constraint cierre_mes_vendedor_conversion_objetivo_finito
  check (conversion_objetivo is null or (conversion_objetivo <> 'NaN'::numeric and conversion_objetivo <> 'Infinity'::numeric and conversion_objetivo <> '-Infinity'::numeric));

-- == 3. La deuda que arrastra de un mes a otro ===============================
alter table crm.ajustes_mes_cerrado
  add constraint ajustes_mes_cerrado_capital_pen_finito
  check ((capital_pen <> 'NaN'::numeric and capital_pen <> 'Infinity'::numeric and capital_pen <> '-Infinity'::numeric));

alter table crm.ajustes_mes_cerrado
  add constraint ajustes_mes_cerrado_capital_usd_finito
  check ((capital_usd <> 'NaN'::numeric and capital_usd <> 'Infinity'::numeric and capital_usd <> '-Infinity'::numeric));

alter table crm.ajustes_mes_cerrado
  add constraint ajustes_mes_cerrado_numerador_finito
  check ((numerador <> 'NaN'::numeric and numerador <> 'Infinity'::numeric and numerador <> '-Infinity'::numeric));

alter table crm.ajustes_mes_cerrado
  add constraint ajustes_mes_cerrado_pendiente_numerador_finito
  check ((pendiente_numerador <> 'NaN'::numeric and pendiente_numerador <> 'Infinity'::numeric and pendiente_numerador <> '-Infinity'::numeric));

alter table crm.ajustes_mes_cerrado
  add constraint ajustes_mes_cerrado_pendiente_pen_finito
  check ((pendiente_pen <> 'NaN'::numeric and pendiente_pen <> 'Infinity'::numeric and pendiente_pen <> '-Infinity'::numeric));

alter table crm.ajustes_mes_cerrado
  add constraint ajustes_mes_cerrado_pendiente_usd_finito
  check ((pendiente_usd <> 'NaN'::numeric and pendiente_usd <> 'Infinity'::numeric and pendiente_usd <> '-Infinity'::numeric));

-- == 4. La ponderacion del referido del periodo ==============================
alter table crm.periodos_cerrados
  add constraint periodos_cerrados_ponderacion_referido_finito
  check (ponderacion_referido is null
         or (ponderacion_referido <> 'NaN'::numeric
             and ponderacion_referido <> 'Infinity'::numeric
             and ponderacion_referido <> '-Infinity'::numeric));

-- == Postflight: los 16 guardianes estan, y el liston MUERDE de verdad =======
-- La sonda NO escribe en ninguna tabla de produccion: copia el predicado VIVO
-- de cada constraint -leido del catalogo, no reescrito aqui- a una tabla
-- temporal y le tira los valores malos. Asi prueba el liston que quedo puesto,
-- no una version de laboratorio que podria haber divergido.
do $postflight$
declare
  v_puestas int;
  v_def     text;
  v_colada  boolean;
  v_paso    boolean;
begin
  -- Contados por PAR (tabla, nombre) y exigiendo `convalidated`: un nombre
  -- suelto podria venir de otra tabla e inflar la cuenta.
  select count(*) into v_puestas
  from pg_catalog.pg_constraint c
  where c.contype = 'c' and c.convalidated
    and (c.conrelid, c.conname) in (
      ('public.cronograma_pagos'::regclass, 'cronograma_pagos_monto_programado_valido'),
      ('public.cronograma_pagos'::regclass, 'cronograma_pagos_monto_pagado_valido'),
      ('crm.cierre_mes_vendedor'::regclass, 'cierre_mes_vendedor_numerador_finito'),
      ('crm.cierre_mes_vendedor'::regclass, 'cierre_mes_vendedor_conversion_pct_finito'),
      ('crm.cierre_mes_vendedor'::regclass, 'cierre_mes_vendedor_referidos_aporta_pct_finito'),
      ('crm.cierre_mes_vendedor'::regclass, 'cierre_mes_vendedor_ajuste_numerador_finito'),
      ('crm.cierre_mes_vendedor'::regclass, 'cierre_mes_vendedor_ajuste_pen_finito'),
      ('crm.cierre_mes_vendedor'::regclass, 'cierre_mes_vendedor_ajuste_usd_finito'),
      ('crm.cierre_mes_vendedor'::regclass, 'cierre_mes_vendedor_conversion_objetivo_finito'),
      ('crm.ajustes_mes_cerrado'::regclass, 'ajustes_mes_cerrado_capital_pen_finito'),
      ('crm.ajustes_mes_cerrado'::regclass, 'ajustes_mes_cerrado_capital_usd_finito'),
      ('crm.ajustes_mes_cerrado'::regclass, 'ajustes_mes_cerrado_numerador_finito'),
      ('crm.ajustes_mes_cerrado'::regclass, 'ajustes_mes_cerrado_pendiente_numerador_finito'),
      ('crm.ajustes_mes_cerrado'::regclass, 'ajustes_mes_cerrado_pendiente_pen_finito'),
      ('crm.ajustes_mes_cerrado'::regclass, 'ajustes_mes_cerrado_pendiente_usd_finito'),
      ('crm.periodos_cerrados'::regclass,   'periodos_cerrados_ponderacion_referido_finito'));
  if v_puestas <> 16 then
    raise exception 'POSTFLIGHT: se esperaban 16 guardianes y hay %', v_puestas;
  end if;

  -- ---- Sonda 1: el monto programado de una cuota ---------------------------
  select pg_catalog.pg_get_constraintdef(c.oid) into v_def
  from pg_catalog.pg_constraint c
  where c.conrelid = 'public.cronograma_pagos'::regclass
    and c.conname = 'cronograma_pagos_monto_programado_valido';
  execute format(
    'create temporary table sonda_f1_2 (monto_programado numeric(12,2), constraint sonda_cuota %s)',
    v_def);

  -- NEGATIVO: el NaN rebota.
  v_colada := true;
  begin
    execute 'insert into sonda_f1_2 values (''NaN''::numeric)';
  exception when check_violation then v_colada := false;
  end;
  if v_colada then
    raise exception 'POSTFLIGHT: un NaN atraviesa el liston del monto programado';
  end if;

  -- NEGATIVO: el cero y el negativo tambien.
  v_colada := true;
  begin
    execute 'insert into sonda_f1_2 values (0)';
  exception when check_violation then v_colada := false;
  end;
  if v_colada then
    raise exception 'POSTFLIGHT: una cuota de 0 atraviesa el liston';
  end if;

  -- POSITIVO -sin este caso la sonda no prueba nada-: un monto real pasa.
  v_paso := false;
  begin
    execute 'insert into sonda_f1_2 values (1234.56)';
    v_paso := true;
  exception when others then v_paso := false;
  end;
  if not v_paso then
    raise exception 'POSTFLIGHT: el liston del monto programado rechaza un monto valido';
  end if;
  drop table sonda_f1_2;

  -- ---- Sonda 2: el numerador de la foto del cierre -------------------------
  select pg_catalog.pg_get_constraintdef(c.oid) into v_def
  from pg_catalog.pg_constraint c
  where c.conrelid = 'crm.cierre_mes_vendedor'::regclass
    and c.conname = 'cierre_mes_vendedor_numerador_finito';
  execute format(
    'create temporary table sonda_f1_2 (numerador numeric, constraint sonda_cierre %s)',
    v_def);

  -- NEGATIVO: NaN e infinito rebotan.
  v_colada := true;
  begin
    execute 'insert into sonda_f1_2 values (''NaN''::numeric)';
  exception when check_violation then v_colada := false;
  end;
  if v_colada then
    raise exception 'POSTFLIGHT: un NaN atraviesa el liston del cierre';
  end if;

  v_colada := true;
  begin
    execute 'insert into sonda_f1_2 values (''Infinity''::numeric)';
  exception when check_violation then v_colada := false;
  end;
  if v_colada then
    raise exception 'POSTFLIGHT: un infinito atraviesa el liston del cierre';
  end if;

  -- POSITIVO: el cierre puede sellar cero, negativos y decimales. Si alguno de
  -- estos rebotara, el liston romperia el cierre en vez de protegerlo.
  v_paso := false;
  begin
    execute 'insert into sonda_f1_2 values (0), (-3.5), (17.25)';
    v_paso := true;
  exception when others then v_paso := false;
  end;
  if not v_paso then
    raise exception 'POSTFLIGHT: el liston del cierre rechaza numeros legitimos';
  end if;
  drop table sonda_f1_2;

  raise notice 'POSTFLIGHT OK: 16 guardianes puestos; NaN e infinito rebotan y los numeros legitimos pasan';
end
$postflight$;

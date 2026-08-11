-- ============================================================================
-- Migración A — la conversión mensual ponderada
--   (ADITIVA EN ESQUEMA · escribe 2 filas, una de ellas en public.audit_log)
-- ============================================================================
-- Responde a la §3.1 del plan «Conversión mensual - plan de implementación»
-- (vault, 2026-08-11), que a su vez implementa
-- [[Conversion mensual - definicion cerrada]].
--
-- Qué es exactamente «aditiva» aquí (la cabecera decía «100 % ADITIVA» y era
-- IMPRECISO: esta migración sí escribe datos)
-- ---------------------------------------------------------------------------
-- Crea 1 tabla, 4 funciones y 4 índices, no MODIFICA ni BORRA ningún objeto
-- existente, **no toca ni un byte del payload de ninguna función existente** y
-- nadie la lee todavía: por eso puede ir servidor primero sin regresión posible.
-- La unificación de `cumplimiento_metas_fn` es otra migración (B) y va LA
-- ÚLTIMA, después del front.
-- Lo que SÍ escribe, dicho en voz alta en vez de escondido bajo un «100 %»:
--   · una fila semilla en `crm.conversion_pesos` (el 0,150 vigente desde
--     julio-2026);
--   · y, disparada por esa fila, una fila en **`public.audit_log`** a través del
--     trigger `trg_audit_conversion_pesos` → `private.log_audit_crm()`.
-- Eso es DML sobre `public`, no DDL: no se altera ni un objeto del portal, se
-- usa la tabla de auditoría de la casa por el camino de siempre — que es
-- justamente lo que LEEME.md §7 exige de toda tabla `crm.*`, y que en esta,
-- fuente del número que cambia el sueldo de alguien, sería absurdo saltarse.
-- Resumen honesto: **aditiva en esquema, con dos escrituras de datos, una de
-- ellas fuera del esquema `crm`.** Ninguna de las dos es reversible con un
-- `drop`, así que constan en el rollback del pie del fichero.
--
-- La regla, que es lo único que no se negocia (Tabla 3 del plan)
-- --------------------------------------------------------------
--   · DIVISOR   = leads NO REFERIDOS que el asesor RECIBIÓ en el mes, fechados
--                 por `lead_asignaciones.asignado_en` en hora de Lima (T1).
--                 Entran los abiertos y los DESCARTADOS. Los REFERIDOS quedan
--                 FUERA del divisor (T10, decisión de Miguel del 2026-08-10 por
--                 la noche): recibirlos es gratis, cerrarlos premia al 15 %.
--   · NUMERADOR = cierres DEL MES: no referidos al 100 % + referidos × 0,15,
--                 atribuidos al `analista_id` de la fila inmutable que cerró
--                 (T2) y fechados por `resultado_en` (T3).
--   · Un lead de julio cerrado en agosto suma al NUMERADOR de agosto y NO al
--     divisor de agosto (su divisor fue julio). Por eso hay `procedencia`.
--   · A→B→A dentro del mes le pesa UNO a A: se cuenta el LEAD, no el episodio
--     (T5, `group by analista_id, lead_id`).
--   · «Era referido» sale del SNAPSHOT `lead_asignaciones.origen`, jamás de
--     `crm.leads.origen` (T4). El snapshot es inmutable por trigger desde el
--     día uno; la columna viva solo se sella con la migración D.
--   · `conversion_pct` es NULL —jamás 0— cuando el divisor es 0. «Sin datos» y
--     «0 %» son dos frases muy distintas sobre el trabajo de una persona.
--   · El numerador es `numeric` FRACCIONARIO y SIN redondear (T6): 0,15 × 3 =
--     0,45, y al entero más cercano son 0 — se borraría el aporte de tres
--     cierres reales. Solo se redondea el porcentaje, y una sola vez.
--
-- Ejemplo canónico (Ana, agosto): recibe 90 no referidos + 20 referidos, cierra
-- 16 y 12 → numerador 16 + 12×0,15 = 17,80 · divisor 90 · conversión 19,78 % ·
-- aporte de los referidos 2,00 puntos.
--
-- Los cuatro estados, y por qué son cuatro
-- ----------------------------------------
-- Con esta definición «divisor 0» ya NO significa «sin muestra». Hay DOS formas
-- distintas de llegar a un divisor 0, y confundirlas es acusar a alguien de no
-- haber trabajado:
--   · `medible`        — recibió leads no referidos.
--   · `solo_referidos` — EFECTO DE BORDE NUEVO de T10: en el mes solo le
--                        llegaron referidos, así que su divisor legítimo es 0.
--                        Trabajó; simplemente no tiene denominador.
--   · `solo_arrastre`  — no recibió nada, pero cerró cartera de meses
--                        anteriores. Hoy el front lo saca del ranking como
--                        «sin muestra»; con este estado sigue dentro.
--   · `sin_actividad`  — ni recibió ni cerró. Un 0 % mentiría.
--
-- El vocabulario CERRADO de `cobertura.motivo_no_medible` (el front lo declara
-- como `v.picklist`, así que añadir un valor más adelante rompe la pantalla):
--   null · 'sin_ledger' · 'anterior_al_ledger' · 'mes_parcial' ·
--   'sin_supervisor' · 'supervisor_inactivo' · 'supervisor_no_es_supervisor'
--
-- Lo que este fichero CORRIGE del plan (el reconocimiento contra producción
-- del 2026-08-11 mandó sobre el texto del plan, y queda anotado)
-- ---------------------------------------------------------------------------
-- 1. El SUELO HISTÓRICO no es el 2026-07-17 que el plan escribe en su payload
--    de ejemplo. `min(asignado_en) where not aproximado` en producción vale
--    **2026-08-05 18:19:55.872708+00**: el ledger existe desde el 17 de julio,
--    pero sus filas de entonces ya no están (296 leads y 4 episodios borrados
--    EN DURO el 2026-08-05). Por eso `suelo_historico` se CALCULA y ningún test
--    debe fijar una constante.
-- 2. `aproximado = true` NO EXISTE en producción (0 filas, y 0 episodios con
--    `motivo_apertura = 'backfill_estado_actual'`). `divisor_aproximado` nace
--    valiendo 0 y seguirá en 0 mientras nadie backfillee: un test que solo
--    compruebe «divisor_aproximado = 0» no prueba nada. Se conserva el campo
--    porque el contrato lo promete y porque C2 (base fría) puede resucitarlo.
-- 3. Las claves de `divisor_por_motivo` son los valores REALES del CHECK de
--    `motivo_apertura` — `ingreso`, `asignado`, `reasignado`, `reabierto`,
--    `reactivado`, `backfill_estado_actual` —, no el «reasignacion» del
--    ejemplo del plan.
-- 4. Un MES FUTURO se rechaza con 22023. El plan no lo dice en §3.1e pero sí lo
--    exige su propio test (§6.2 C, «mes futuro → 22023»), y el default de
--    copiar `cumplimiento_metas_fn` habría sido aceptarlo y devolver un payload
--    de ceros — justo lo que este plan prohíbe.
-- 5. `medible` se decide contra el INSTANTE del suelo, no contra su MES. La
--    versión anterior comparaba `p_periodo < date_trunc('month', suelo)`, con lo
--    que **el mes en el que nace el ledger nunca podía salir no-medible**: hoy
--    mismo, agosto-2026 se habría declarado fiable con los 4,56 primeros días
--    (≈15 % del mes) sin una sola fila de ledger. Ahora ese caso es
--    `mes_parcial`, y `anterior_al_ledger` queda solo para los meses enteros
--    previos. Verificado en producción: julio → `anterior_al_ledger`,
--    agosto → `mes_parcial`. El criterio CONV-11 del plan («julio-2026 →
--    medible = false») pasa ahora por la razón correcta y no por el accidente
--    de que la limpieza del 5 de agosto moviera el suelo.
-- 6. La sonda `cierres_sin_episodio` lleva VENTANA. Su `not exists` sin acotar
--    solo cazaba la ausencia TOTAL de episodio y por tanto no podía ver el caso
--    de borde que su propio comentario dice cubrir (T3): un cierre a caballo de
--    la medianoche del día 1, con `leads.convertido_en` en M y el episodio con
--    `resultado_en` en M+1, se perdía del numerador y la sonda devolvía 0.
-- 7. Un vendedor FUERA DEL ROSTER que consulte su propia conversión recibía una
--    pantalla en blanco sin explicación (`responsables = []`, todo a cero) y un
--    `medible = true` calculado sobre el ledger de los demás. Hoy hay
--    exactamente una persona así en producción (roster 16, vendedores con rol
--    efectivo 17). Ahora se le dice por qué, con el mismo vocabulario de tres
--    motivos que ya usa Configuración → Usuarios (20260810163458): silenciar la
--    exclusión sería cambiar un bug ruidoso por uno mudo.
--
-- Cinturón y tirantes: los dos agujeros del ledger de los que esta métrica NO
-- se fía (endurecido el 2026-08-11, tras la auditoría)
-- ---------------------------------------------------------------------------
-- Los dos se cierran EN LA RAÍZ en otra migración del mismo ciclo (el CHECK
-- des-trivaluado y un índice único parcial «una conversión por lead»). Aun así
-- la métrica se defiende sola, y no por desconfianza ritual: el estado imposible
-- es ALCANZABLE hoy con los triggers apagados —patrón ya usado en la casa para
-- un backfill (20260807203757:747-748)— y este informe decide sueldos. Si
-- alguna vez se equivoca, que se equivoque hacia «no lo cuento raro».
--
--   AGUJERO 1 — EL CIERRE SIN FECHA. `lead_asignaciones_cierre_consistente`
--   (20260717212639:123-137) exige, en la rama `motivo_cierre = 'convertido'`,
--   que `resultado_en = finalizado_en`. Si `resultado_en` llega NULL, esa
--   igualdad da NULL, la rama da NULL, el OR da NULL y el CHECK **PASA**: un
--   CHECK solo rechaza en FALSE. O sea que puede existir una fila
--   `resultado = 'convertido'` con `resultado_en` NULL, y un numerador fechado
--   por `resultado_en` NO LA VERÍA: divisor 1, numerador 0, conversión 0 % donde
--   la verdad es 100 %. Es la peor dirección posible del error — acusa a alguien
--   de no haber cerrado lo que cerró.
--   Por eso TODO lo que en este fichero FECHA un cierre usa
--   `coalesce(la.resultado_en, la.finalizado_en)`. El fallback es seguro y no es
--   una corazonada: en cuanto `resultado` no es NULL, la rama «abierta» del
--   CHECK es FALSE, y la «cerrada» empieza por `finalizado_en is not null`, que
--   es un predicado BIVALUADO (nunca NULL) y por tanto pone el AND entero en
--   FALSE si falta la fecha. Traducido: **una fila con `resultado` no nulo tiene
--   siempre `finalizado_en`**, así que el coalesce aterriza siempre en una fecha
--   real. Y en el caso sano —los dos campos iguales, que es lo que escribe el
--   trigger— no cambia absolutamente nada.
--   Comprobado en un PG16 efímero con la fila enferma sembrada: el predicado
--   viejo devolvía 0 cierres para ese asesor; el nuevo devuelve 1.
--   RESIDUO CONOCIDO, y no es mudo: la MISMA trivaluación deja entrar también
--   una fila con `motivo_cierre = 'convertido'` y `resultado` NULL, que este
--   numerador (`where resultado = 'convertido'`) sigue sin ver. No se amplía el
--   predicado aquí —ensancharía los índices parciales y la definición del
--   numerador por un estado que la migración del CHECK elimina—, pero tampoco se
--   pierde en silencio: ese lead figura convertido en `crm.leads` y sin episodio
--   convertido en el ledger, que es exactamente lo que canta la sonda
--   `cierres_sin_episodio` del payload.
--
--   AGUJERO 2 — EL CIERRE CONTADO DOS VECES. El EXCLUDE
--   `lead_asignaciones_sin_solape` compara `tstzrange(asignado_en,
--   coalesce(finalizado_en, 'infinity'), '[)')`. Dos episodios convertidos del
--   MISMO lead que sean ADYACENTES ([10:00,11:00) y [11:00,12:00)) no se solapan,
--   y los de duración cero dan rango VACÍO, que no se solapa con nada: conviven
--   los dos. Un `count(*)` de cierres los contaría 2 y publicaría un 200 % con
--   divisor 1.
--   Por eso el numerador cuenta `count(distinct lead_id) filter (...)` — el
--   MISMO criterio que ya usa el divisor (`group by analista_id, lead_id`) y por
--   el mismo motivo de la definición: se cuenta el LEAD, no el episodio (T5).
--   El `filter` se conserva porque referidos y no referidos tienen que seguir
--   separados; `count(distinct x) filter (where y)` es SQL válido y no es lo
--   mismo que un `count(distinct x)` a secas.
--   La semántica del caso normal no se mueve: con un cierre por lead, distinto
--   y no distinto dan lo mismo. Verificado en PG16 sobre el caso canónico de
--   Ana — 16 no referidos + 12 referidos → numerador 17,800 · divisor 90 ·
--   19,78 % · aporte de referidos 2,00 puntos, idéntico antes y después.
--   ⚠️ HASTA DÓNDE LLEGA ESTE CINTURÓN, dicho sin adornos: `count(distinct
--   lead_id)` deduplica DENTRO de un analista, porque el `group by` es por
--   `analista_id`. El mismo lead cerrado por DOS analistas en episodios
--   terminales adyacentes o de duración cero sigue sumando 1 + 1 en
--   `total.numerador` y en `total.cierres_*`: dos conversiones para un solo
--   lead. Ese reparto entre personas NO se puede arreglar aquí sin romper T5
--   (el numerador se atribuye a quien cerró), y lo cierra en la raíz el índice
--   único parcial «una conversión por lead» de la migración hermana
--   `20260811190310_crm_ledger_cierres_integros.sql`. Las dos migraciones van
--   en el MISMO despliegue por este motivo, no por comodidad.
--
--   Los DOS índices del numerador se crean sobre la EXPRESIÓN
--   `coalesce(resultado_en, finalizado_en)` y no sobre la columna. Medido en
--   PG16 con 200 000 filas: con el índice sobre la columna cruda el planner
--   degrada el predicado a `Filter` y recorre el índice parcial ENTERO; con el
--   de expresión da `Index Cond` y un rango de verdad. Un índice que el planner
--   no puede usar es peor que no tenerlo: pesa en cada escritura y tranquiliza
--   en la revisión.
--
-- Por qué el núcleo es `plpgsql` y no `language sql` (auditoría 2026-08-11)
-- ---------------------------------------------------------------------------
-- Con `language sql`, `private.conversion_mensual_por_vendedor` NO se inlina:
-- el inlining de una función SQL set-returning está prohibido cuando la función
-- es SECURITY DEFINER y cuando lleva `SET` de configuración — y esta lleva las
-- dos cosas, obligadas (§5, T8). Sin inlining, su cuerpo se planifica UNA vez
-- con los argumentos como Params, o sea con PLAN GENÉRICO y sin valores.
-- Y con plan genérico el predicado de ámbito `(p_global or analista_id =
-- any(p_visibles))` no puede ser condición de índice NUNCA: `$3` es
-- desconocido, así que el OR entero cae a `Filter`.
-- Medido en PG16 con 200 000 episodios y `auto_explain`, llamando con
-- `p_global = false` y UN solo id visible:
--   · `language sql`     → `Filter: ($3 OR (analista_id = ANY ($4)))`,
--                          `Rows Removed by Filter: 42 335`. El vendedor
--                          RECORRE LOS CIERRES DE TODA LA EMPRESA: su coste
--                          crece con el volumen de la casa, no con el suyo.
--   · `language plpgsql` → plan personalizado con los valores reales,
--                          `Index Cond: ((analista_id = ANY ('{…}')) AND
--                          (asignado_en >= …) AND (asignado_en < …))`,
--                          0 filas descartadas por filtro en el divisor.
-- Dicho de otro modo: con `language sql`,
-- `lead_asignaciones_convertido_analista_idx` y el ya existente
-- `lead_asignaciones_analista_fecha_idx` son PESO MUERTO — se paga su escritura
-- y el planner no puede usarlos —, que es exactamente el pecado que este mismo
-- fichero denuncia dos párrafos más arriba. Con `plpgsql` sí son alcanzables
-- (comprobado: forzando la elección, el índice por analista da `Index Cond`
-- completo y baja de 4,3 ms a 1,3 ms con 0 filas descartadas frente a 42 335).
-- Honestidad sobre el alcance de la medición: con plan personalizado el
-- planner PUEDE elegir el índice por analista, no está obligado — sobre el
-- dataset sintético siguió prefiriendo el de fecha para el numerador por una
-- estimación mala. Lo que cambia con `plpgsql` no es qué índice elige, es que
-- pase a ser ELEGIBLE: con plan genérico no lo era en ningún escenario.
-- LO QUE SE PIERDE Y CÓMO SE COMPENSA: `language sql` valida su cuerpo contra
-- el catálogo al crearse; `plpgsql` no analiza sus sentencias SQL hasta que
-- corren, así que un nombre de columna mal escrito aplicaría LIMPIO. Por eso el
-- guard (7) del postflight EJECUTA el núcleo de verdad — deja de ser un extra y
-- pasa a ser la única red que queda.
--
-- El porcentaje NO tiene techo, y el payload tiene que poder explicarlo
-- ---------------------------------------------------------------------------
-- `conversion_pct` puede pasar del 100 % con `estado = 'medible'` en un mes
-- perfectamente normal. No es un bug: es la consecuencia directa de dos reglas
-- ya decididas.
--   · T10 — el referido SALE del divisor pero ENTRA al numerador al 0,15. Un
--     mes de cola floja con muchos referidos cerrados dispara el ratio: 3 no
--     referidos recibidos, 2 cerrados, más 10 referidos cerrados → numerador
--     3,50 sobre divisor 3 = 116,67 %, y 50,00 de esos puntos los pone gente
--     que no está en el denominador. Verificado en PG16 con la RPC completa.
--   · ARRASTRE — un cierre de M cuya asignación fue en M-1 suma al numerador de
--     M y su divisor fue el de M-1. 6 recibidos y 8 cierres de cartera vieja →
--     133,33 %.
-- La fila SIEMPRE se puede descomponer (lleva `procedencia`, `referidos` y
-- `cierres_de_arrastre`). Lo que faltaba era `total`: el número de EMPRESA se
-- publicaba sin una sola clave con la que reconstruirlo. Por eso `total` lleva
-- ahora `cierres_de_arrastre` y `referidos_aporta_pct`, los dos únicos sumandos
-- que pueden empujar el ratio por encima de 100.
-- CONTRATO PARA EL FRONT, explícito para que nadie lo deduzca mal:
-- `conversion_pct` es un RATIO SIN TECHO, no un porcentaje de 0 a 100. No se
-- puede pintar como una barra de progreso acotada ni recortar con `min(…,100)`
-- — recortarlo escondería justo el mes que hay que mirar. Se pinta el número y,
-- por encima de 100, se enseña el desglose que lo explica.
-- NO se le pone tope aquí ni se inventa un quinto estado: eso sería cambiar la
-- regla de negocio, y la regla es de Miguel (misma clase de decisión que T10).
-- Lo que sí se hace es que el número deje de ser inexplicable.
--
-- Los cuatro índices van SIN CONCURRENTLY, y hasta qué volumen eso vale
-- ---------------------------------------------------------------------------
-- `create index` sin CONCURRENTLY toma SHARE sobre `crm.leads` y
-- `crm.lead_asignaciones` mientras construye: bloquea INSERT/UPDATE/DELETE, y
-- las LECTURAS siguen pasando (medido en PG16: `pg_locks` devuelve `ShareLock`,
-- no `AccessExclusiveLock` — la versión anterior de esta nota decía ACCESS
-- EXCLUSIVE y dimensionaba mal el riesgo). O sea: durante la construcción la
-- cartera se sigue viendo; lo que espera es dar de alta o mover un lead.
-- Además va DENTRO de la transacción de la migración: CONCURRENTLY no puede
-- ejecutarse en un bloque transaccional, así que usarlo obligaría a sacar los
-- índices de este fichero.
-- Volumen REAL de producción, medido el 2026-08-11 justo antes de aplicar:
--   · `crm.lead_asignaciones` → 1 fila · 232 kB con índices incluidos
--   · `crm.leads`             → 1 fila · 360 kB
-- A ese tamaño la construcción es de milisegundos y no hay tráfico que bloquear;
-- el `set local lock_timeout = '10s'` de más abajo es el seguro real: si el lock
-- no entra, la migración ABORTA en vez de dejar el CRM parado.
-- CUÁNDO DEJA DE VALER: cuando construir se acerque al segundo largo o el lock
-- pueda pillar operación en curso. Umbral operativo que se adopta —a partir de
-- **~100 000 filas en `crm.lead_asignaciones`** o **~50 000 en `crm.leads`**—:
-- estos índices salen a una migración aparte, UNO POR FICHERO, con
-- `create index concurrently` fuera de transacción y una verificación posterior
-- de que ninguno quedó `indisvalid = false` (un CONCURRENTLY que falla deja el
-- índice inválido y en silencio). Con los 279 leads del dataset real de julio
-- seguiría siendo instantáneo: el riesgo no es hoy, es el día que entre de golpe
-- la base fría (C2).
--
-- Un agregado que NO se recorta por ámbito, a propósito
-- ----------------------------------------------------
-- `cobertura.suelo_historico` es `min(asignado_en)` de TODO el ledger, sin
-- predicado de ámbito, y viaja también al vendedor. Es deliberado y es la única
-- excepción del payload: la cobertura es una propiedad del LEDGER —cuándo
-- empieza a existir el registro—, no de una persona. Recortarla por ámbito haría
-- que el supervisor de un equipo nuevo viera `mes_parcial` sobre un mes que la
-- empresa mide perfectamente, y que dos roles dijeran cosas distintas sobre el
-- mismo mes: exactamente la clase de contradicción que ya costó un ciclo
-- (20260810163458, «el editor ofrecía 16 y el servidor exigía 17»). Lo que viaja
-- es un timestamp de instalación, no atribuible a nadie y sin PII. Todo lo
-- demás del payload —roster, base, altas de referidos, sonda, total— SÍ lleva
-- su `(v_global or ... = any(v_visibles))`.
--
-- El estado real de la base, para que nadie confunda «funciona» con «dice algo»
-- ---------------------------------------------------------------------------
-- Producción tiene HOY 1 lead, 1 episodio abierto, 0 cierres y 0 referidos.
-- Esta métrica va a decir «mes parcial» y «sin actividad» para los 16 del roster
-- el día que se publique, y eso es CORRECTO. El valor de este ciclo es que el
-- negocio empiece a contarse bien, no que enseñe un número mañana. Los tests de
-- pantalla van en el estado de producción (vacío), no solo con el fixture lleno
-- — regla del `gate:realidad`.
--
-- Lo que NO cambia
-- ----------------
-- Ninguna función existente, ningún payload existente, ninguna policy, ninguna
-- columna de `crm.leads`, y ningún objeto de `public` (solo se LEE
-- `public.perfiles` a través de los helpers de siempre, y se INSERTA en
-- `public.audit_log` por el trigger de auditoría de la casa). El trigger del
-- ledger y el guard de tenencia se dejan intactos a propósito.
-- ============================================================================

begin;

set local lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- 0. Preflight: sin estas piezas la métrica contaría de menos EN SILENCIO
-- ---------------------------------------------------------------------------
do $preflight$
begin
  if to_regprocedure('private.rol_crm(uuid)') is null
     or to_regprocedure('private.es_lector_global()') is null
     or to_regprocedure('private.vendedor_ids_visibles(uuid)') is null
     or to_regprocedure('private.roster_metas_vendedores()') is null
     or to_regprocedure('private.vendedores_sin_supervisor()') is null
     or to_regprocedure('private.filtrar_desglose_sujetos_crm(jsonb,text,text,text[])') is null
     or to_regprocedure('private.log_audit_crm()') is null
     or to_regclass('crm.lead_asignaciones') is null
     or to_regclass('crm.leads') is null
     or to_regclass('crm.equipo') is null
     or to_regclass('public.perfiles') is null
     or to_regclass('public.audit_log') is null then
    raise exception 'Falta una dependencia del ambito CRM, del roster o de la auditoria';
  end if;

  -- El ESCRITOR del ledger. Es el único camino por el que «recibir» y «cerrar»
  -- se convierten en hechos inmutables: sin él, o deshabilitado, el ledger deja
  -- de registrar quién cierra y la métrica cuenta de MENOS sin avisar — la peor
  -- forma de fallar para un informe que decide sueldos (§3.1f).
  if not exists (
    select 1
    from pg_catalog.pg_trigger t
    where t.tgrelid = 'crm.leads'::pg_catalog.regclass
      and t.tgname = 'trg_leads_asignaciones'
      and not t.tgisinternal
      and t.tgenabled <> 'D'
  ) then
    raise exception 'trg_leads_asignaciones no existe o esta deshabilitado: el ledger no registraria los cierres';
  end if;

  -- El snapshot inmutable del que sale «era referido» (T4). Si este guard se
  -- cayera, `lead_asignaciones.origen` dejaria de ser una fotografia y la
  -- conversion de un mes cerrado podria reescribirse hacia atras.
  if not exists (
    select 1
    from pg_catalog.pg_trigger t
    where t.tgrelid = 'crm.lead_asignaciones'::pg_catalog.regclass
      and t.tgname = 'trg_lead_asignaciones_00_inmutables'
      and not t.tgisinternal
      and t.tgenabled <> 'D'
  ) then
    raise exception 'trg_lead_asignaciones_00_inmutables no existe o esta deshabilitado: el snapshot de origen no seria inmutable';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. El 15 %, versionado por mes
-- ---------------------------------------------------------------------------
-- Una constante en el código haría que cambiar el peso RECALCULARA TODO EL
-- HISTÓRICO: los meses ya enseñados dejarían de coincidir con lo que se
-- presentó, y nadie podría reconstruir con qué regla se pagó marzo. Con la
-- tabla, cambiar el peso es insertar una fila nueva y el pasado no se mueve.
create table crm.conversion_pesos (
  vigente_desde date primary key
    check (vigente_desde = date_trunc('month', vigente_desde)::date),
  peso_referido numeric(4,3) not null
    check (peso_referido >= 0 and peso_referido <= 1),
  nota text,
  creado_en timestamptz not null default now()
);

comment on table crm.conversion_pesos is
  'Peso del cierre de un REFERIDO en el numerador de la conversion mensual, versionado por mes. Se lee solo desde private.peso_referido_conversion (SECURITY DEFINER): RLS ON, cero policies y cero grants.';
comment on column crm.conversion_pesos.vigente_desde is
  'Primer dia del mes desde el que rige este peso. El vigente para un mes M es el mayor vigente_desde <= M.';
comment on column crm.conversion_pesos.peso_referido is
  'Fraccion con la que un cierre de referido suma al numerador (0,150 = 15 %). El referido NO entra en el divisor (T10).';
comment on column crm.conversion_pesos.nota is
  'Quien acordo el peso y cuando. Es el rastro que permite explicar un mes pasado sin adivinar.';

alter table crm.conversion_pesos enable row level security;

-- RLS ON con CERO policies y CERO grants: deny-by-default absoluto para la Data
-- API. Precedente aceptado en la casa (crm.cuentas_bancarias,
-- crm.contrato_cuentas_pago, crm.lead_sla_*). Dispara el advisor INFO
-- `rls_enabled_no_policy`, que es de la clase ya aceptada: «0 ERROR» no
-- significa «0 hallazgos».
revoke all privileges on table crm.conversion_pesos
  from public, anon, authenticated, service_role;

-- Auditoria: LEEME.md exige trigger de audit sobre TODA tabla `crm.*`, y esta
-- tabla es la fuente del numero que cambia el sueldo de alguien — saltarsela
-- seria justo lo contrario de versionar el peso.
-- ⚠️ `private.log_audit_crm` resuelve `fila_id` por `id` o `perfil_id`, y esta
-- tabla no tiene ninguna de las dos: `fila_id` quedara NULL (la columna es
-- `text` NULL y lo admite) mientras `data_antes`/`data_despues` guardan la fila
-- entera, que es lo que hace falta para reconstruir con que peso se pago un mes.
create trigger trg_audit_conversion_pesos
after insert or delete or update on crm.conversion_pesos
for each row execute function private.log_audit_crm();

-- Semilla. `vigente_desde` en julio-2026 y no en agosto para que el mes parcial
-- de julio —el unico anterior con episodios posibles— tenga peso definido y no
-- dependa del fallback.
insert into crm.conversion_pesos (vigente_desde, peso_referido, nota)
values (
  date '2026-07-01',
  0.150,
  'Acordado con Miguel 2026-08-10 (noche): el referido NO entra en el divisor y pesa 0,15 en el numerador. Corrige el incentivo perverso de la primera version, donde registrar referidos BAJABA la conversion.'
);

-- ---------------------------------------------------------------------------
-- 2. El peso vigente para un mes
-- ---------------------------------------------------------------------------
-- plpgsql y no `language sql` a proposito: si la tabla estuviera vacia, un
-- `select` devolveria NULL y el numerador se volveria NULL PARA TODO EL MUNDO
-- (en SQL, NULL * 0 es NULL, no 0) — un fallo mudo que se veria como «la
-- pantalla no carga». Mejor un error explicito que nombra la causa.
create or replace function private.peso_referido_conversion(p_mes date)
returns numeric
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_peso numeric;
begin
  select cp.peso_referido
    into v_peso
  from crm.conversion_pesos cp
  where cp.vigente_desde <= p_mes
  order by cp.vigente_desde desc
  limit 1;

  -- Fallback al mas antiguo: un mes anterior a la primera version del peso se
  -- calcula con esa primera version, que es la unica regla que existio.
  if v_peso is null then
    select cp.peso_referido
      into v_peso
    from crm.conversion_pesos cp
    order by cp.vigente_desde asc
    limit 1;
  end if;

  if v_peso is null then
    raise exception 'crm.conversion_pesos esta vacia: no hay peso del referido con el que calcular la conversion'
      using errcode = '55000';
  end if;

  return v_peso;
end;
$function$;

comment on function private.peso_referido_conversion(date) is
  'Peso del referido vigente para el mes dado (mayor vigente_desde <= mes; fallback al mas antiguo). Falla con 55000 si la tabla esta vacia: un peso NULL anularia el numerador de todos en silencio.';

revoke all on function private.peso_referido_conversion(date)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. El nombre del mes, sin depender del locale del servidor
-- ---------------------------------------------------------------------------
-- `to_char(fecha,'TMMonth')` depende de `lc_time`, que es un GUC de SESIÓN: una
-- función con `search_path` vacío no lo controla, y el mismo payload diría
-- «August» o «agosto» según quién conecte. Array literal, y se acabó.
-- No es SECURITY DEFINER porque no lee nada: convertirla en definer sumaría
-- superficie (y un WARN de advisor) sin comprar ningún privilegio. Llamada
-- desde una función definer del owner, se ejecuta igual.
create or replace function private.etiqueta_mes_es(p_mes date)
returns text
language sql
immutable
set search_path = ''
as $function$
  select (array[
    'enero','febrero','marzo','abril','mayo','junio',
    'julio','agosto','setiembre','octubre','noviembre','diciembre'
  ])[extract(month from p_mes)::int];
$function$;

comment on function private.etiqueta_mes_es(date) is
  'Nombre del mes en espanol desde un array literal. NUNCA to_char(...,''TMMonth''): depende de lc_time, un GUC de sesion que search_path vacio no controla.';

revoke all on function private.etiqueta_mes_es(date)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Índices
-- ---------------------------------------------------------------------------
-- El DIVISOR ya está servido y no se toca: `lead_asignaciones_analista_fecha_idx`
-- (analista_id, asignado_en desc) y `lead_asignaciones_cohorte_idx` (asignado_en).
-- «Servido» solo es cierto si el núcleo obtiene PLAN PERSONALIZADO — por eso es
-- `plpgsql` y no `language sql` (razón medida en la cabecera). Con plan genérico
-- el ámbito cae a `Filter` y estos DOS índices, el viejo y el nuevo, dejan de
-- ser alcanzables.

-- NUMERADOR por asesor. La clave de fecha es la EXPRESIÓN
-- `coalesce(resultado_en, finalizado_en)`, la misma con la que el numerador fecha
-- el cierre (agujero 1, ver cabecera): un índice sobre la columna cruda no sirve
-- para ese predicado —medido: `Filter` sobre el índice parcial entero en vez de
-- `Index Cond`— y solo daría la ilusión de estar servido.
-- Y NO se reutiliza `lead_asignaciones_terminal_analista_idx` por DOS motivos, no
-- uno: (1) está ordenado por `finalizado_en` a secas, y el CHECK iguala los dos
-- campos en el cierre 'convertido' pero el planner NO deduce esa igualdad —y
-- menos aún ahora, que el predicado es un coalesce—; y (2) su predicado parcial
-- es sobre `motivo_cierre` e incluye también los 'descartado', que este numerador
-- no quiere.
create index if not exists lead_asignaciones_convertido_analista_idx
  on crm.lead_asignaciones (analista_id, coalesce(resultado_en, finalizado_en))
  where resultado = 'convertido';

-- NUMERADOR global (gerencia y lector global no recortan por analista). Sin él,
-- seq scan sobre una tabla append-only que solo crece. Sirve también al `not
-- exists` con ventana de la sonda `cierres_sin_episodio`, que fecha el cierre con
-- el mismo coalesce.
create index if not exists lead_asignaciones_convertido_fecha_idx
  on crm.lead_asignaciones (coalesce(resultado_en, finalizado_en))
  where resultado = 'convertido';

-- Sonda `cierres_sin_episodio`. Verificado el 2026-08-11: hoy NO existe ningún
-- índice de crm.leads que contenga `convertido_en`.
create index if not exists idx_leads_convertido_en
  on crm.leads (convertido_en)
  where etapa = 'convertido';

-- Bloque de referidos, rama «dados de alta por él» (H4/D3). `idx_leads_creado_por`
-- existe pero es total y sin predicado.
create index if not exists idx_leads_creado_por_referido
  on crm.leads (creado_por, creado_en)
  where origen = 'referido';

-- ---------------------------------------------------------------------------
-- 5. La aritmética, en UN solo sitio
-- ---------------------------------------------------------------------------
-- Set-returning en `private`, SIN gate propio: no la publica PostgREST y solo la
-- llaman funciones que ya hicieron el suyo. Existe separada de la RPC porque
-- cuando DOS funciones deciden sobre el mismo conjunto, ese conjunto se define
-- UNA vez — la lección que costó que las metas no se pudieran guardar
-- (20260810163458). La migración B consumirá exactamente esta función con esta
-- firma: cambiarla es cambiar dos pantallas.
--
-- SECURITY DEFINER obligado (T8): `crm.lead_asignaciones` no tiene NINGÚN grant
-- fuera del owner —ni para authenticated ni para service_role— así que con
-- INVOKER esta función no leería una sola fila.
--
-- Y `plpgsql`, no `language sql`, POR ESO MISMO: SECURITY DEFINER + `SET
-- search_path` bloquean el inlining, y sin inlining una función SQL se
-- planifica en genérico y el ámbito nunca puede ser condición de índice. Con
-- `plpgsql` la consulta va por SPI y recibe plan personalizado con los valores
-- reales. Medición y números, en la cabecera.
create or replace function private.conversion_mensual_por_vendedor(
  p_ini timestamptz,
  p_fin timestamptz,
  p_global boolean,
  p_visibles uuid[],
  p_factor numeric
)
returns table (
  analista_id uuid,
  divisor integer,
  divisor_aproximado integer,
  divisor_por_motivo jsonb,
  cierres_no_referidos integer,
  cierres_referidos integer,
  cierres_de_arrastre integer,
  numerador numeric,
  conversion_pct numeric,
  procedencia jsonb,
  referidos_recibidos integer,
  referidos_aporta_pct numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
-- Los nombres de las columnas de salida (`analista_id`, `divisor`, …) son
-- VARIABLES dentro de un cuerpo plpgsql y podrían ganarle a una columna
-- homónima. Todo el cuerpo va cualificado, pero esta directiva lo hace
-- estructural en vez de depender de la disciplina de quien edite mañana: ante
-- la duda, gana la COLUMNA, que es la semántica SQL de siempre.
#variable_conflict use_column
begin
return query
with recibidos as (
  -- DIVISOR (bruto): «V RECIBIÓ el lead en M» = tiene un episodio con
  -- `asignado_en` dentro de [ini, fin). Entran todos los canales, los abiertos y
  -- los DESCARTADOS. Como el ledger NO TIENE columna `activo`, la LEY —«la
  -- conversión no filtra activo», un lead soft-borrado sigue contando— se
  -- cumple por construcción y no hay predicado que alguien pueda «arreglar».
  -- `group by (analista, lead)` = contar el LEAD y no el episodio: un A→B→A
  -- dentro del mes le pesa UNO a A (T5). Sin esto se podría hundir un
  -- porcentaje moviendo un lead de ida y vuelta.
  -- El `order by … ASC` no es cosmético: cuando un lead tiene VARIOS episodios
  -- del mismo analista dentro del mes, la pregunta que responden `origen` y
  -- `motivo_apertura` es «¿por qué entró este lead al divisor DE ESTE MES?», y
  -- eso lo contesta el PRIMER episodio del mes, no el último. Con `desc`, 100
  -- leads que entran por `ingreso` el día 1, se parquean el 2 y se reactivan el
  -- mismo día 2 salían en el desglose como `{"reactivado": 100}`: la clave
  -- `ingreso` desaparecía y el pico de la carga masiva —lo único que este
  -- desglose existe para hacer VISIBLE (H3)— quedaba escondido, y encima
  -- disfrazado de reciclaje de cartera vieja. Verificado en PG16. No mueve el
  -- divisor (sigue habiendo un valor por (analista, lead)): solo reetiqueta.
  select
    la.analista_id,
    la.lead_id,
    (array_agg(la.origen order by la.asignado_en asc))[1] = 'referido' as fue_referido,
    (array_agg(la.motivo_apertura order by la.asignado_en asc))[1] as motivo,
    bool_or(la.aproximado) as aproximado
  from crm.lead_asignaciones la
  where la.asignado_en >= p_ini
    and la.asignado_en < p_fin
    and (p_global or la.analista_id = any(p_visibles))
  group by la.analista_id, la.lead_id
),
cierres as (
  -- NUMERADOR: atribuido al `analista_id` de la fila inmutable que cerró (T2),
  -- fechado por `resultado_en` (T3) y con «era referido» leído del SNAPSHOT
  -- (T4). La fecha del cierre sale de la MISMA fila que `asignado_en`: numerador
  -- y procedencia comparten reloj y no se pueden contradecir.
  -- `coalesce(resultado_en, finalizado_en)` y no `resultado_en` a secas: el CHECK
  -- `lead_asignaciones_cierre_consistente` es TRIVALUADO en la rama 'convertido'
  -- —`resultado_en = finalizado_en` da NULL si el primero es NULL, y un CHECK
  -- solo rechaza en FALSE—, así que un cierre real puede existir sin
  -- `resultado_en` y se perdería del numerador dando 0 % donde hubo 100 %. El
  -- fallback es seguro: con `resultado` no nulo, el CHECK exige `finalizado_en is
  -- not null` en un predicado bivaluado, o sea que SIEMPRE hay fecha. En el caso
  -- sano los dos campos son iguales y esto no cambia nada. Ver cabecera.
  select
    la.analista_id,
    la.lead_id,
    (la.origen = 'referido') as fue_referido,
    date_trunc('month', la.asignado_en at time zone 'America/Lima')::date as mes_origen,
    -- El mes que se está midiendo, calculado UNA vez y arrastrado en la CTE para
    -- que «arrastre» y «cubo de procedencia» no puedan derivarlo cada uno a su
    -- manera. `p_ini` es por contrato el primer instante del mes en Lima.
    date_trunc('month', p_ini at time zone 'America/Lima')::date as mes_periodo
  from crm.lead_asignaciones la
  where la.resultado = 'convertido'
    and coalesce(la.resultado_en, la.finalizado_en) >= p_ini
    and coalesce(la.resultado_en, la.finalizado_en) < p_fin
    and (p_global or la.analista_id = any(p_visibles))
),
motivos as (
  -- Desglose del divisor por motivo de apertura. Es lo que deja VISIBLE en
  -- pantalla el pico de una carga masiva (H3) en vez de esconderlo dentro de un
  -- porcentaje. Solo cuenta lo que está en el divisor: los referidos no.
  select r.analista_id, r.motivo, count(*)::int as n
  from recibidos r
  where not r.fue_referido
  group by r.analista_id, r.motivo
),
motivos_json as (
  select m.analista_id, jsonb_object_agg(m.motivo, m.n) as divisor_por_motivo
  from motivos m
  group by m.analista_id
),
agg_div as (
  -- El divisor EXCLUYE los referidos (T10). La fila del asesor SIGUE existiendo
  -- aunque el divisor quede en 0: es el caso «solo recibió referidos», que hay
  -- que poder distinguir de «no recibió nada».
  select
    r.analista_id,
    count(*) filter (where not r.fue_referido)::int as divisor,
    count(*) filter (where r.aproximado and not r.fue_referido)::int as divisor_aproximado,
    count(*) filter (where r.fue_referido)::int as referidos_recibidos
  from recibidos r
  group by r.analista_id
),
agg_cie as (
  -- Se cuentan LEADS DISTINTOS, no episodios — el mismo criterio que el divisor
  -- («T5: se cuenta el LEAD, no el episodio») y por el mismo motivo. Aquí además
  -- es un cinturón contra el agujero 2: el EXCLUDE `lead_asignaciones_sin_solape`
  -- deja convivir dos episodios convertidos del mismo lead si son ADYACENTES o de
  -- duración cero, y un `count(*)` publicaría 200 % con divisor 1. El `filter`
  -- sigue separando referidos de no referidos: `count(distinct x) filter (...)`
  -- es SQL válido y para el caso normal —un cierre por lead— da exactamente lo
  -- mismo que antes (comprobado sobre el caso canónico de Ana: 16 y 12).
  -- ⚠️ ALCANCE EXACTO DEL CINTURÓN: el `group by` es por `analista_id`, así que
  -- esto deduplica DENTRO de un analista. El mismo lead cerrado por DOS
  -- analistas en episodios terminales adyacentes o de duración cero suma 1 + 1
  -- en `total`, y eso NO se arregla aquí sin romper T5 (cada cierre se atribuye
  -- a quien lo cerró): lo cierra en la raíz el índice único parcial de
  -- `20260811190310_crm_ledger_cierres_integros.sql`, que va en el mismo
  -- despliegue.
  -- `cierres_de_arrastre` es el sumando que explica un `conversion_pct` por
  -- encima de 100 sin ninguna fila enferma: cierres del mes cuyo divisor fue
  -- otro mes. Va también en `total`, que era el único sitio del payload donde el
  -- número no se podía descomponer (ver cabecera, «El porcentaje NO tiene
  -- techo»).
  select
    c.analista_id,
    count(distinct c.lead_id) filter (where not c.fue_referido)::int as cierres_no_referidos,
    count(distinct c.lead_id) filter (where c.fue_referido)::int as cierres_referidos,
    count(distinct c.lead_id) filter (where c.mes_origen < c.mes_periodo)::int as cierres_de_arrastre
  from cierres c
  group by c.analista_id
),
proc as (
  -- Procedencia en CONTEOS ENTEROS, nunca en porcentajes (T6): sumar
  -- porcentajes ya redondeados hace que «agosto + julio» no cuadre con el
  -- total. Los meses de más de 11 atrás caen en un cubo `anteriores` para que
  -- el payload no crezca sin techo.
  -- También por LEADS DISTINTOS, para que la suma de la procedencia cuadre con
  -- los `cierres_*` de la fila: si el numerador cuenta leads y el desglose
  -- contara episodios, «agosto + julio» dejaría de sumar el total y la
  -- contradicción se leería como un bug de la pantalla.
  -- `cierres` se calcula como la SUMA DE LOS DOS MISMOS conteos filtrados que
  -- usa `agg_cie`, y NO como un `count(distinct lead_id)` a secas. Parecen lo
  -- mismo y no lo son: un lead con dos episodios convertidos en el mes con
  -- snapshots de `origen` distintos (uno 'landing', otro 'referido') suma 1 + 1
  -- en `agg_cie` —el `distinct` es por grupo del `filter`, no global— y habría
  -- sumado 1 aquí. La tarjeta diría «2 cierres» arriba y «1 cierre» en su propio
  -- desglose por mes. Escrito así, los dos lados no se pueden separar por
  -- construcción, valga lo que valga el ledger. Verificado en PG16.
  select
    c.analista_id,
    c.mes_cubo,
    (count(distinct c.lead_id) filter (where not c.fue_referido)
     + count(distinct c.lead_id) filter (where c.fue_referido))::int as cierres,
    count(distinct c.lead_id) filter (where c.fue_referido)::int as cierres_referidos
  from (
    select
      c0.analista_id,
      c0.lead_id,
      c0.fue_referido,
      case
        when (extract(year from p_ini at time zone 'America/Lima')::int * 12
              + extract(month from p_ini at time zone 'America/Lima')::int)
             - (extract(year from c0.mes_origen)::int * 12
                + extract(month from c0.mes_origen)::int) <= 11
        then c0.mes_origen
      end as mes_cubo
    from cierres c0
  ) c
  group by c.analista_id, c.mes_cubo
),
proc_json as (
  select
    p.analista_id,
    jsonb_agg(
      jsonb_build_object(
        'mes', case when p.mes_cubo is not null
                    then pg_catalog.to_char(p.mes_cubo, 'YYYY-MM') end,
        'mes_nombre', case when p.mes_cubo is not null
                           then private.etiqueta_mes_es(p.mes_cubo)
                           else 'anteriores' end,
        'anio', case when p.mes_cubo is not null
                     then extract(year from p.mes_cubo)::int end,
        'cierres', p.cierres,
        'cierres_referidos', p.cierres_referidos
      )
      order by p.mes_cubo desc nulls last
    ) as procedencia
  from proc p
  group by p.analista_id
)
select
  coalesce(d.analista_id, c.analista_id),
  coalesce(d.divisor, 0),
  coalesce(d.divisor_aproximado, 0),
  coalesce(mj.divisor_por_motivo, '{}'::jsonb),
  coalesce(c.cierres_no_referidos, 0),
  coalesce(c.cierres_referidos, 0),
  coalesce(c.cierres_de_arrastre, 0),
  -- Numerador FRACCIONARIO y SIN redondear (T6). `numeric` es decimal exacto:
  -- con float8 daría 12,449999…
  (coalesce(c.cierres_no_referidos, 0) + p_factor * coalesce(c.cierres_referidos, 0))::numeric,
  -- NULL, jamás 0, cuando el divisor es 0: un 0 se leería como «0 % de
  -- conversión», o sea como que no cerró nada de lo que recibió.
  case when coalesce(d.divisor, 0) > 0 then
    round(
      100.0 * (coalesce(c.cierres_no_referidos, 0) + p_factor * coalesce(c.cierres_referidos, 0))
      / d.divisor, 2)
  end,
  coalesce(pj.procedencia, '[]'::jsonb),
  coalesce(d.referidos_recibidos, 0),
  -- Cuántos PUNTOS del porcentaje puso el 15 % de los referidos.
  case when coalesce(d.divisor, 0) > 0 then
    round(100.0 * p_factor * coalesce(c.cierres_referidos, 0) / d.divisor, 2)
  end
-- FULL OUTER JOIN: un asesor puede tener divisor sin cierres (mes normal) o
-- cierres SIN divisor (arrastra cartera vieja y no recibió nada). El segundo es
-- justo el que hay que poder distinguir; un INNER JOIN lo haría desaparecer y la
-- pantalla diría que no trabajó.
from agg_div d
full outer join agg_cie c on c.analista_id = d.analista_id
left join motivos_json mj on mj.analista_id = d.analista_id
left join proc_json pj on pj.analista_id = coalesce(d.analista_id, c.analista_id);
end;
$function$;

comment on function private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric) is
  'Nucleo aritmetico UNICO de la conversion mensual: divisor = leads NO referidos recibidos en el mes (asignado_en, T1/T10), numerador = cierres del mes con los referidos al p_factor (T2/T3/T4). Los DOS lados cuentan LEADS DISTINTOS, nunca episodios (T5), y el cierre se fecha con coalesce(resultado_en, finalizado_en) porque el CHECK del ledger es trivaluado en la rama convertido. plpgsql y no language sql a proposito: SECURITY DEFINER + SET search_path impiden el inlining, y sin inlining el plan seria GENERICO y el ambito caeria a Filter (los indices por analista dejarian de servir). Sin gate: solo la llaman funciones que ya hicieron el suyo.';

revoke all on function private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6. La RPC de pantalla
-- ---------------------------------------------------------------------------
-- MENSUAL POR CONTRATO: la definición habla del «mes M», y el desglose «de qué
-- mes venía cada cierre» no significa nada sobre un rango de 63 días. Con la
-- firma `date` (primer día del mes), la pregunta «qué devuelve fuera de un mes
-- exacto» es INEXPRESABLE.
--
-- Contrato de denegación, fijado ANTES que los tests:
--   vendedor      → su propia fila         alcance 'propio'
--   supervisor    → su subárbol recursivo  alcance 'equipo'
--   gerencia      → la empresa             alcance 'global'
--   lector global → la empresa             alcance 'global'
--   coordinador / membresía inactiva / ajeno al CRM / anon → 42501 DURO.
--     Nunca un payload de ceros: un cero se leería como «0 % de conversión».
--   periodo inválido → 22023, pero SOLO DESPUÉS del gate, para que el código de
--     error no funcione como oráculo de pertenencia.
--
-- El gate puede estar abierto al VENDEDOR porque el payload no lleva ningún
-- agregado de empresa SALVO `cobertura.suelo_historico`, que es metadato del
-- ledger (ver la cabecera): `total` se recalcula sobre el ámbito ya recortado.
-- Es la regla estructural de la casa: gate relajado ⟺ payload sin agregados
-- globales de negocio.
create or replace function crm.conversion_mensual_fn(p_periodo date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_global boolean;
  v_alcance text;
  v_visibles uuid[];
  v_ahora timestamptz := now();
  v_mes_actual date := date_trunc('month', v_ahora at time zone 'America/Lima')::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_factor numeric;
  v_suelo timestamptz;
  v_suelo_mes date;
  v_medible boolean;
  v_motivo_no_medible text;
  v_motivo_roster text;
  v_payload jsonb;
begin
  -- 1) GATE EXPLICITO, ANTES DE TOCAR NINGUN DATO. Nunca RLS implicita: esta
  --    funcion es SECURITY DEFINER y las policies no se evaluan. ALLOWLIST, no
  --    «rol_crm is not null»: ese idioma (el de cumplimiento_metas_fn) dejaria
  --    pasar al COORDINADOR, que aqui esta denegado por contrato.
  --    Orden deliberado: un actor denegado recibe 42501 aunque el periodo sea
  --    basura, para que el codigo de error no funcione como oraculo.
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null
     or not coalesce(v_rol in ('vendedor', 'supervisor', 'gerencia') or v_lector, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- 2) Validacion del periodo. Las dos ramas comparten el prefijo «Periodo
  --    invalido» para que un solo patron del gate las cace, y se diferencian en
  --    el detalle para que el error diga QUE esta mal.
  if p_periodo is null or p_periodo <> date_trunc('month', p_periodo)::date then
    raise exception 'Periodo invalido: debe ser el primer dia del mes'
      using errcode = '22023';
  end if;
  if p_periodo > v_mes_actual then
    -- Un mes futuro no es «todavia sin datos»: es una pregunta sin sentido. Sin
    -- este corte devolveria ceros para todos, que es exactamente el payload que
    -- esta pantalla no puede emitir.
    raise exception 'Periodo invalido: el mes no puede ser futuro'
      using errcode = '22023';
  end if;

  -- 3) Ambito. Capturado UNA vez en array para que `= any(...)` sea indexable
  --    (el `in (select private.vendedor_ids_visibles(...))` se ejecuta como
  --    SubPlan por fila y nunca usa indice — razon documentada en
  --    20260809144920:8-16).
  --    Ojo: para el LECTOR GLOBAL el ambito NO puede salir de
  --    vendedor_ids_visibles — con rol 'directorio' esa funcion cae en su
  --    deny-by-default y devuelve VACIO. De ahi el v_global explicito.
  v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
  v_alcance := case
    when v_global then 'global'
    when v_rol = 'supervisor' then 'equipo'
    else 'propio'
  end;
  v_visibles := case when v_global then '{}'::uuid[]
                     else array(select private.vendedor_ids_visibles(v_uid)) end;

  v_ini := p_periodo::timestamp at time zone 'America/Lima';
  v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';

  -- 4) El peso del mes pedido, no el de hoy: un mes cerrado se recalcula con la
  --    regla que regia entonces.
  v_factor := private.peso_referido_conversion(p_periodo);

  -- 5) Cobertura historica. Se CALCULA: el ledger existe desde el 2026-07-17
  --    pero sus filas mas antiguas ya no estan, asi que cualquier constante
  --    escrita a mano nace mintiendo. `not aproximado` excluye los episodios
  --    reconstruidos por backfill, cuyo `asignado_en` fue adivinado.
  --    SIN recorte de ambito, a proposito: la cobertura es una propiedad del
  --    LEDGER y tiene que decir lo mismo mire quien mire (ver cabecera).
  select min(la.asignado_en)
    into v_suelo
  from crm.lead_asignaciones la
  where not la.aproximado;

  v_suelo_mes := date_trunc('month', v_suelo at time zone 'America/Lima')::date;

  -- La comparacion es contra el INSTANTE del suelo, no contra su MES. Contra el
  -- mes, el mes en el que NACE el ledger jamas podria salir no-medible aunque le
  -- falten semanas — y es justo el flag que existe para no confundir «0 %» con
  -- «sin datos» el que estaria mintiendo, y mintiendo hacia el lado de afirmar
  -- fiabilidad.
  if v_suelo is null then
    v_medible := false;
    v_motivo_no_medible := 'sin_ledger';
  elsif v_ini < v_suelo then
    v_medible := false;
    v_motivo_no_medible := case
      when p_periodo < v_suelo_mes then 'anterior_al_ledger'
      else 'mes_parcial'
    end;
  else
    v_medible := true;
    v_motivo_no_medible := null;
  end if;

  -- 5b) Un vendedor FUERA DEL ROSTER recibiria `responsables = []` y un total en
  --     cero sobre su propio trabajo, sin una sola clave que se lo explicara.
  --     Sus cifras siguen contadas (viajan en `cobertura.fuera_de_roster`), pero
  --     la pantalla tiene que poder decir por que y adonde ir. Se reutilizan los
  --     TRES motivos de private.vendedores_sin_supervisor(): agruparlos bajo una
  --     sola etiqueta mandaria a gerencia a «asignarle supervisor» a alguien que
  --     en pantalla ya tiene uno (leccion de 20260810163458 y de
  --     [[crm-p04-revocado-vs-ajeno]]).
  --     PRECEDENCIA deliberada: esto GANA a la cobertura del ledger. Las dos
  --     cosas pueden ser ciertas a la vez, y de las dos esta es la unica que
  --     lleva una accion concreta detras.
  if v_alcance = 'propio'
     and not exists (
       select 1 from private.roster_metas_vendedores() r
       where r.vendedor_id = v_uid
     ) then
    select vs.motivo
      into v_motivo_roster
    from private.vendedores_sin_supervisor() vs
    where vs.vendedor_id = v_uid;

    v_medible := false;
    v_motivo_no_medible := coalesce(v_motivo_roster, 'sin_supervisor');
  end if;

  with roster as materialized (
    -- FUENTE UNICA del roster (T7): quien tiene meta y quien tiene conversion
    -- son el mismo conjunto. `roster_metas_vendedores()` devuelve la EMPRESA
    -- entera, asi que el recorte por ambito se hace aqui — sin el, un supervisor
    -- veria los ids de los vendedores de otras ramas.
    select r.vendedor_id, r.supervisor_id
    from private.roster_metas_vendedores() r
    where v_global or r.vendedor_id = any(v_visibles)
  ),
  base as materialized (
    select cm.*
    from private.conversion_mensual_por_vendedor(
      v_ini, v_fin, v_global, v_visibles, v_factor
    ) cm
  ),
  alta_referidos as materialized (
    -- «Dados de alta por el» (H4). ⚠️ Es el UNICO numero del payload que sale de
    -- `crm.leads.origen` (columna viva) y no del snapshot: no es reproducible
    -- hacia atras y por eso queda FUERA de la aritmetica, como dato al lado.
    select l.creado_por as analista_id, count(*)::int as dados_de_alta
    from crm.leads l
    where l.origen = 'referido'
      and l.creado_en >= v_ini
      and l.creado_en < v_fin
      and l.creado_por is not null
      and (v_global or l.creado_por = any(v_visibles))
    group by l.creado_por
  ),
  filas as (
    -- LEFT JOIN desde el roster: un analista del roster sin ninguna actividad
    -- tiene fila igualmente, con estado `sin_actividad`. Desaparecer no es un
    -- estado.
    select
      r.vendedor_id,
      r.supervisor_id,
      coalesce(b.divisor, 0) as divisor,
      coalesce(b.divisor_aproximado, 0) as divisor_aproximado,
      coalesce(b.divisor_por_motivo, '{}'::jsonb) as divisor_por_motivo,
      coalesce(b.cierres_no_referidos, 0) as cierres_no_referidos,
      coalesce(b.cierres_referidos, 0) as cierres_referidos,
      coalesce(b.cierres_de_arrastre, 0) as cierres_de_arrastre,
      coalesce(b.numerador, 0::numeric) as numerador,
      b.conversion_pct,
      coalesce(b.procedencia, '[]'::jsonb) as procedencia,
      coalesce(b.referidos_recibidos, 0) as referidos_recibidos,
      b.referidos_aporta_pct,
      coalesce(a.dados_de_alta, 0) as dados_de_alta
    from roster r
    left join base b on b.analista_id = r.vendedor_id
    left join alta_referidos a on a.analista_id = r.vendedor_id
  ),
  fuera as (
    -- Quien produjo dentro del ambito pero NO esta en el roster: el que se dio
    -- de baja a mitad de mes, el supervisor con cartera propia, el vendedor sin
    -- supervisor. Ni se pierde ni se le atribuye a nadie: se declara como
    -- AGREGADO SIN IDENTIDAD. Devolver su uuid seria filtrar la identidad de
    -- alguien sin rol efectivo (D2).
    select
      count(*)::int as analistas,
      coalesce(sum(b.divisor), 0)::int as divisor,
      coalesce(sum(b.cierres_no_referidos + b.cierres_referidos), 0)::int as cierres,
      coalesce(sum(b.numerador), 0::numeric) as numerador
    from base b
    where not exists (select 1 from roster r where r.vendedor_id = b.analista_id)
  ),
  motivos_totales as (
    -- El desglose por motivo del payload es el del AMBITO, sumando el de cada
    -- fila. Se agrega el jsonb del nucleo en vez de recontar aqui: la
    -- aritmetica vive en un solo sitio.
    select e.key as motivo, sum(e.value::int)::int as n
    from filas f, jsonb_each_text(f.divisor_por_motivo) e
    group by e.key
  ),
  sonda as (
    -- `cierres_sin_episodio`: leads que la ficha da por convertidos en el mes y
    -- que el ledger no respalda con un episodio cerrado EN ESE MISMO MES. La
    -- ventana no es cosmetica: sin ella la sonda solo veria la ausencia TOTAL de
    -- episodio, y el caso de borde de T3 que dice cubrir es justamente el otro
    -- —`crm.convertir_lead` sella `convertido_en` con `now()` (transaction) y el
    -- trigger sella `resultado_en` con `statement_timestamp()`, asi que un cierre
    -- a caballo de la medianoche del dia 1 deja la ficha en M y el episodio en
    -- M+1—. El numerador perderia ese cierre y la sonda diria que no falta nada.
    -- NO se corrige el numerador con esto: se DECLARA, porque un informe que se
    -- auto-parchea es un informe que no se puede auditar. No filtra `activo`,
    -- igual que el resto de la metrica.
    -- El `not exists` fecha el episodio con el MISMO
    -- `coalesce(resultado_en, finalizado_en)` que el numerador, y no es un
    -- detalle: si aqui se mirara `resultado_en` a secas, un cierre con
    -- `resultado_en` NULL (agujero 1, ver cabecera) que el numerador SI cuenta
    -- gracias al coalesce saldria ademas denunciado por la sonda. Las dos
    -- consultas tienen que responder a la misma pregunta, o la sonda deja de
    -- medir el hueco y empieza a medir su propia discrepancia.
    -- `count(*)` aqui es correcto y no necesita `distinct`: se cuentan filas de
    -- `crm.leads`, una por lead por su PK.
    -- ⚠️ EL RECORTE DE ESTA SONDA NO ES EL DEL NUMERADOR, y por eso lleva tres
    -- ramas. El numerador recorta por AUTORÍA DEL CIERRE (`la.analista_id`, que
    -- es NOT NULL); esta sonda vive en `crm.leads`, donde lo que hay es
    -- TENENCIA — y `vendedor_id` es NULLABLE (`leads_tenencia_exclusiva` admite
    -- tenencia por supervisor, y un lead parqueado no tiene vendedor). Con un
    -- solo `l.vendedor_id = any(v_visibles)`, un lead convertido cuya tenencia
    -- esté en el supervisor daba `NULL = any(...)` → NULL, y la fila se caía EN
    -- SILENCIO: gerencia veía `cierres_sin_episodio: 1` y el supervisor de ese
    -- mismo equipo veía 0, mirando el mismo mes. Una sonda que existe para que
    -- un hueco no sea mudo no puede enmudecer según quién pregunte.
    -- Las tres ramas cubren las tres formas de que el lead sea «de este ámbito»:
    -- tenencia en un vendedor visible, parqueo en un supervisor visible
    -- (`vendedor_ids_visibles` de un supervisor incluye al propio supervisor) y,
    -- como red, cualquier episodio del ledger de alguien visible — que es lo
    -- único que salva al lead sin tenencia alguna.
    select count(*)::int as cierres_sin_episodio
    from crm.leads l
    where l.etapa = 'convertido'
      and l.convertido_en >= v_ini
      and l.convertido_en < v_fin
      and (v_global
           or l.vendedor_id = any(v_visibles)
           or l.asignado_supervisor_id = any(v_visibles)
           or exists (
             select 1
             from crm.lead_asignaciones lv
             where lv.lead_id = l.id
               and lv.analista_id = any(v_visibles)
           ))
      and not exists (
        select 1
        from crm.lead_asignaciones la
        where la.lead_id = l.id
          and la.resultado = 'convertido'
          and coalesce(la.resultado_en, la.finalizado_en) >= v_ini
          and coalesce(la.resultado_en, la.finalizado_en) < v_fin
      )
  ),
  resumen as (
    -- `total` se RECALCULA como sum(numerador)/sum(divisor). NO es la media de
    -- los porcentajes de las filas: promediar porcentajes da un numero que no
    -- corresponde a ningun lead real.
    select
      count(*)::int as analistas,
      coalesce(sum(f.divisor), 0)::int as divisor,
      coalesce(sum(f.divisor_aproximado), 0)::int as divisor_aproximado,
      coalesce(sum(f.cierres_no_referidos), 0)::int as cierres_no_referidos,
      coalesce(sum(f.cierres_referidos), 0)::int as cierres_referidos,
      coalesce(sum(f.cierres_de_arrastre), 0)::int as cierres_de_arrastre,
      coalesce(sum(f.referidos_recibidos), 0)::int as referidos_recibidos,
      coalesce(sum(f.numerador), 0::numeric) as numerador
    from filas f
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    -- El alcance lo decide el SERVIDOR, que es quien conoce el recorte.
    'alcance', v_alcance,
    'periodo', jsonb_build_object(
      'mes', pg_catalog.to_char(p_periodo, 'YYYY-MM'),
      'mes_nombre', private.etiqueta_mes_es(p_periodo),
      'anio', extract(year from p_periodo)::int,
      'zona', 'America/Lima',
      'desde', v_ini,
      'hasta', v_fin
    ),
    'ponderacion', jsonb_build_object(
      'referido', v_factor,
      'fuente', 'crm.conversion_pesos'
    ),
    -- Contrato fail-closed para el front: si un servidor viejo colara otra
    -- definicion del divisor, el `v.literal` del cliente lo rechaza en vez de
    -- pintar un numero de otra formula.
    -- Estos tres valores son TOKENS de version del contrato, no la formula: por
    -- eso `numerador` sigue diciendo `resultado_en` aunque la consulta feche con
    -- `coalesce(resultado_en, finalizado_en)`. `resultado_en` es la fuente, y el
    -- coalesce es la defensa contra una fila mal formada, no una segunda fuente.
    -- Cambiar el literal obligaria a cambiar el `v.literal` del front en el mismo
    -- deploy, que es justo lo que este contrato existe para evitar.
    'fuentes', jsonb_build_object(
      'divisor', 'crm.lead_asignaciones.asignado_en',
      'numerador', 'crm.lead_asignaciones.resultado_en',
      'referido', 'crm.lead_asignaciones.origen'
    ),
    'cobertura', jsonb_build_object(
      -- Distingue «0 %» de «sin datos» (H1). Los meses anteriores al ledger no
      -- valen 0: no son medibles, y decirlo es parte del producto. El mes en el
      -- que el ledger nace tampoco lo es del todo: es `mes_parcial`.
      'medible', v_medible,
      'suelo_historico', v_suelo,
      'motivo_no_medible', v_motivo_no_medible,
      'divisor_aproximado', (select r.divisor_aproximado from resumen r),
      'divisor_por_motivo', coalesce(
        (select jsonb_object_agg(mt.motivo, mt.n) from motivos_totales mt),
        '{}'::jsonb),
      'cierres_sin_episodio', (select s.cierres_sin_episodio from sonda s),
      'fuera_de_roster', (
        select jsonb_build_object(
          'analistas', fr.analistas,
          'divisor', fr.divisor,
          'cierres', fr.cierres,
          'numerador', fr.numerador
        ) from fuera fr)
    ),
    -- `conversion_pct` es un RATIO SIN TECHO, aquí y en cada fila: puede pasar
    -- de 100 con `estado = 'medible'` y sin ninguna fila enferma, porque el
    -- referido suma al numerador y NO al divisor (T10) y porque un cierre de
    -- arrastre trae su numerador de un mes cuyo divisor fue otro. La fila
    -- siempre se pudo descomponer (`procedencia`, `referidos`); `total` no, y
    -- ese era el agujero: el número de EMPRESA se publicaba sin una sola clave
    -- para reconstruirlo. `cierres_de_arrastre` y `referidos_aporta_pct` son
    -- exactamente los dos sumandos que lo empujan por encima de 100. Ver la
    -- cabecera, «El porcentaje NO tiene techo»: el front NO debe recortar a 100
    -- ni pintarlo como barra acotada.
    'total', (
      select jsonb_build_object(
        'analistas', r.analistas,
        'divisor', r.divisor,
        'cierres_no_referidos', r.cierres_no_referidos,
        'cierres_referidos', r.cierres_referidos,
        'cierres_de_arrastre', r.cierres_de_arrastre,
        'referidos_recibidos', r.referidos_recibidos,
        'numerador', r.numerador,
        'conversion_pct', case when r.divisor > 0
          then round(100.0 * r.numerador / r.divisor, 2) end,
        'referidos_aporta_pct', case when r.divisor > 0
          then round(100.0 * v_factor * r.cierres_referidos / r.divisor, 2) end
      ) from resumen r),
    'responsables', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'vendedor_id', f.vendedor_id,
          'supervisor_id', f.supervisor_id,
          'divisor', f.divisor,
          'cierres_no_referidos', f.cierres_no_referidos,
          'cierres_referidos', f.cierres_referidos,
          -- Cierres del mes cuyo divisor fue OTRO mes. Es derivable de
          -- `procedencia`, pero se publica plano para que la tarjeta pueda
          -- explicar un ratio por encima de 100 sin recorrer un array.
          'cierres_de_arrastre', f.cierres_de_arrastre,
          'numerador', f.numerador,
          'conversion_pct', f.conversion_pct,
          -- Los CUATRO estados. El orden de las ramas es la regla: con divisor
          -- 0, «solo recibio referidos» gana a «solo arrastre» — recibir
          -- referidos ES trabajo del mes, cerrar cartera vieja es de otro.
          'estado', case
            when f.divisor > 0 then 'medible'
            when f.referidos_recibidos > 0 then 'solo_referidos'
            when (f.cierres_no_referidos + f.cierres_referidos) > 0 then 'solo_arrastre'
            else 'sin_actividad'
          end,
          'procedencia', f.procedencia,
          'referidos', jsonb_build_object(
            'recibidos', f.referidos_recibidos,
            'cerrados', f.cierres_referidos,
            'dados_de_alta', f.dados_de_alta,
            'aporta_pct', f.referidos_aporta_pct
          )
        )
        -- Quien no recibio nada NO encabeza el ranking por tener el porcentaje
        -- en NULL. `vendedor_id` al final para que el orden sea determinista.
        order by f.conversion_pct desc nulls last,
                 f.numerador desc,
                 f.divisor desc,
                 f.vendedor_id
      )
      from filas f
    ), '[]'::jsonb)
  ) into v_payload;

  -- Defensa en profundidad. Aqui es IDEMPOTENTE porque `responsables` ya salio
  -- de `roster_metas_vendedores()`, que exige `rol_crm = 'vendedor'` en los dos
  -- extremos — y esa idempotencia es exactamente lo que hace que `total` cuadre
  -- con la suma de `responsables`. El orden importa: recortar a roster →
  -- calcular total → filtrar. Exige que `responsables` sea SIEMPRE un array: el
  -- coalesce a '[]' de arriba es lo que evita el 55000.
  return private.filtrar_desglose_sujetos_crm(
    v_payload, 'responsables', 'vendedor_id', array['vendedor']
  );
end;
$function$;

comment on function crm.conversion_mensual_fn(date) is
  'Conversion mensual ponderada del asesor (plan 2026-08-11): divisor = leads NO referidos recibidos en el mes por asignado_en; numerador = cierres del mes, referidos al peso de crm.conversion_pesos. Vendedor: su fila (propio). Supervisor: su subarbol (equipo). Gerencia y lector global: la empresa (global). Coordinador, membresia inactiva, ajeno y anon: 42501 duro, nunca un payload de ceros. Todo el payload esta recortado al ambito salvo cobertura.suelo_historico, que es metadato del ledger y debe decir lo mismo mire quien mire.';

revoke all on function crm.conversion_mensual_fn(date)
  from public, anon, authenticated, service_role;
grant execute on function crm.conversion_mensual_fn(date) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Postflight
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_fn text;
  v_rol text;
  v_indices int;
  v_mes date;
  v_filas bigint;
begin
  -- (1) La triada que el auditor exige de toda RPC nueva.
  if not exists (
    select 1
    from pg_catalog.pg_proc pr
    join pg_catalog.pg_namespace n on n.oid = pr.pronamespace
    where n.nspname = 'crm'
      and pr.proname = 'conversion_mensual_fn'
      and pr.prosecdef
      and pr.provolatile = 's'
      and pr.proconfig @> array['search_path=""']
  ) then
    raise exception 'La RPC nueva debe ser SECURITY DEFINER, STABLE y con search_path vacio';
  end if;

  -- (2) El revoke a service_role es la pata que un copy-paste incompleto rompe
  --     en SILENCIO: sin este guard, la RPC quedaria ejecutable por la clave de
  --     servicio sin que ningun test lo notara.
  if pg_catalog.has_function_privilege(
       'service_role', 'crm.conversion_mensual_fn(date)', 'execute') then
    raise exception 'service_role no debe ejecutar la RPC nueva';
  end if;
  if pg_catalog.has_function_privilege(
       'anon', 'crm.conversion_mensual_fn(date)', 'execute') then
    raise exception 'anon no puede ejecutar la RPC nueva';
  end if;
  if not pg_catalog.has_function_privilege(
       'authenticated', 'crm.conversion_mensual_fn(date)', 'execute') then
    raise exception 'authenticated debe poder ejecutar la RPC nueva';
  end if;

  -- (3) El nucleo `private` no lo ejecuta NADIE de la API. Una funcion nueva sin
  --     revoke hereda EXECUTE de PUBLIC, y PostgREST la publicaria.
  foreach v_fn in array array[
    'private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)',
    'private.peso_referido_conversion(date)',
    'private.etiqueta_mes_es(date)'
  ] loop
    foreach v_rol in array array['anon', 'authenticated', 'service_role'] loop
      if pg_catalog.has_function_privilege(v_rol, v_fn, 'execute') then
        raise exception '% no debe ser ejecutable por %', v_fn, v_rol;
      end if;
    end loop;
  end loop;

  -- (4) La tabla del peso: cerrada a los CUATRO verbos, con RLS y sin policies.
  --     El verbo peligroso aqui NO es el SELECT: es la ESCRITURA. Un
  --     `grant insert ... to service_role` anadido el dia que alguien quiera
  --     publicar el peso desde una edge deja que cualquier portador de la
  --     service key ponga `peso_referido = 1.000` y reescriba el numerador de un
  --     mes YA ENSEÑADO — y un guard que solo mirase SELECT seguiria en verde.
  foreach v_rol in array array['anon', 'authenticated', 'service_role'] loop
    if pg_catalog.has_table_privilege(v_rol, 'crm.conversion_pesos', 'select')
       or pg_catalog.has_table_privilege(v_rol, 'crm.conversion_pesos', 'insert')
       or pg_catalog.has_table_privilege(v_rol, 'crm.conversion_pesos', 'update')
       or pg_catalog.has_table_privilege(v_rol, 'crm.conversion_pesos', 'delete') then
      raise exception 'crm.conversion_pesos no debe ser alcanzable por la Data API (%)', v_rol;
    end if;
  end loop;
  if not (
    select c.relrowsecurity
    from pg_catalog.pg_class c
    where c.oid = 'crm.conversion_pesos'::pg_catalog.regclass
  ) then
    raise exception 'crm.conversion_pesos debe tener RLS activada';
  end if;
  if exists (
    select 1 from pg_catalog.pg_policies p
    where p.schemaname = 'crm' and p.tablename = 'conversion_pesos'
  ) then
    raise exception 'crm.conversion_pesos no debe tener policies';
  end if;

  -- (5) El ledger sigue cerrado. Se asevera el EFECTO (has_table_privilege) y no
  --     la huella de un REVOKE: crm.lead_asignaciones nunca tuvo grant, asi que
  --     buscar el revoke en el catalogo no probaria nada. Y se miran los TRES
  --     roles: service_role es el que corren las edges y los scripts.
  foreach v_rol in array array['anon', 'authenticated', 'service_role'] loop
    if pg_catalog.has_table_privilege(v_rol, 'crm.lead_asignaciones', 'select')
       or pg_catalog.has_table_privilege(v_rol, 'crm.lead_asignaciones', 'insert')
       or pg_catalog.has_table_privilege(v_rol, 'crm.lead_asignaciones', 'update')
       or pg_catalog.has_table_privilege(v_rol, 'crm.lead_asignaciones', 'delete') then
      raise exception 'crm.lead_asignaciones debe seguir cerrado a la Data API (%)', v_rol;
    end if;
  end loop;

  -- (6) NO VACUIDAD del peso y de la etiqueta. No basta con que la fila exista:
  --     se ejercita la BUSQUEDA completa, que es lo que usara la RPC.
  if private.peso_referido_conversion(date '2026-08-01') is distinct from 0.150 then
    raise exception 'El peso vigente para 2026-08 no es 0,150';
  end if;
  if private.peso_referido_conversion(date '2026-06-01') is distinct from 0.150 then
    raise exception 'El fallback al peso mas antiguo no funciona para un mes previo a la primera version';
  end if;
  if private.etiqueta_mes_es(date '2026-08-01') <> 'agosto'
     or private.etiqueta_mes_es(date '2026-09-01') <> 'setiembre' then
    raise exception 'private.etiqueta_mes_es no devuelve el mes en espanol';
  end if;

  -- (7) EJECUCION REAL del nucleo, no solo metadatos. Desde que el nucleo es
  --     plpgsql (por el plan personalizado; razon en la cabecera) este guard
  --     dejo de ser un extra: plpgsql NO analiza sus sentencias SQL contra el
  --     catalogo al crearse, asi que un nombre de columna mal escrito aplicaria
  --     LIMPIO y solo revienta al ejecutar. Esta llamada es, literalmente, la
  --     unica cosa en toda la migracion que compila el cuerpo del nucleo. NO
  --     borrar «porque ya hay tests».
  --     ⚠️ Lo que este bloque NO cubre: el WITH de crm.conversion_mensual_fn,
  --     que es otra funcion plpgsql y tiene el mismo problema. Su unica red es
  --     `supabase/scripts/test-conversion-mensual.sql`, que corre con sesion.
  v_mes := date_trunc('month', now() at time zone 'America/Lima')::date;
  begin
    select count(*)
      into v_filas
    from private.conversion_mensual_por_vendedor(
      v_mes::timestamp at time zone 'America/Lima',
      (v_mes + interval '1 month')::timestamp at time zone 'America/Lima',
      true,
      '{}'::uuid[],
      private.peso_referido_conversion(v_mes));
  exception when others then
    raise exception 'El nucleo de la conversion no es ejecutable: % [%]', sqlerrm, sqlstate;
  end;
  if v_filas is null then
    raise exception 'El nucleo de la conversion no devolvio un conteo';
  end if;

  -- (7b) El LENGUAJE del nucleo es parte del contrato de rendimiento, no una
  --      preferencia de estilo: con `language sql` la funcion no se inlina
  --      (SECURITY DEFINER + SET search_path lo prohiben), el plan pasa a
  --      GENERICO y el predicado de ambito cae a `Filter` — o sea que los dos
  --      indices por analista dejan de ser alcanzables y la consulta de UN
  --      vendedor recorre los cierres de TODA la empresa. Un cambio asi no deja
  --      ni un test en rojo, por eso se asevera en el catalogo.
  --      De paso se comprueba que el nucleo publica `cierres_de_arrastre`: el
  --      WITH de la RPC lo lee, y al ser plpgsql ese `select` no se analiza
  --      hasta que corre con sesion.
  if not exists (
    select 1
    from pg_catalog.pg_proc pr
    join pg_catalog.pg_namespace n on n.oid = pr.pronamespace
    join pg_catalog.pg_language l on l.oid = pr.prolang
    where n.nspname = 'private'
      and pr.proname = 'conversion_mensual_por_vendedor'
      and l.lanname = 'plpgsql'
      and pr.proargnames @> array['cierres_de_arrastre']
  ) then
    raise exception 'El nucleo debe ser plpgsql (plan personalizado) y declarar cierres_de_arrastre';
  end if;

  -- (8) La RPC arranca de verdad: se la llama SIN sesion y debe morir en el gate
  --     con 42501. Prueba el DECLARE, `auth.uid()` y el gate — no el WITH.
  --     Condicionado a que no haya JWT en la sesion de la migracion, para que un
  --     claim residual no convierta esto en un falso fallo.
  if (select auth.uid()) is null then
    begin
      perform crm.conversion_mensual_fn(v_mes);
      raise exception 'CENTINELA: la RPC no denego a un actor sin sesion';
    exception
      when sqlstate '42501' then
        null; -- correcto
      when others then
        if sqlerrm = 'CENTINELA: la RPC no denego a un actor sin sesion' then raise; end if;
        raise exception 'La RPC fallo con un error inesperado antes del gate: % [%]', sqlerrm, sqlstate;
    end;
  end if;

  -- (9) Los cuatro indices.
  select count(*) into v_indices
  from pg_catalog.pg_indexes i
  where i.schemaname = 'crm'
    and i.indexname in (
      'lead_asignaciones_convertido_analista_idx',
      'lead_asignaciones_convertido_fecha_idx',
      'idx_leads_convertido_en',
      'idx_leads_creado_por_referido');
  if v_indices <> 4 then
    raise exception 'Faltan indices de la conversion mensual (% de 4)', v_indices;
  end if;

  -- (9b) Los DOS del numerador tienen que estar sobre la EXPRESION
  --      `coalesce(resultado_en, finalizado_en)`, no sobre la columna. Este
  --      guard no es ceremonia: `create index if not exists` con un indice
  --      HOMONIMO ya existente es un NO-OP SILENCIOSO, asi que un indice viejo
  --      sobre la columna cruda sobreviviria y el predicado del numerador
  --      caeria a `Filter` sobre el indice parcial entero — mas lento cada mes
  --      y sin una sola linea de aviso.
  if exists (
    select 1
    from pg_catalog.pg_indexes i
    where i.schemaname = 'crm'
      and i.indexname in (
        'lead_asignaciones_convertido_analista_idx',
        'lead_asignaciones_convertido_fecha_idx')
      -- `strpos(cadena, subcadena)`, NO `position(...)`. La forma
      -- `position(x in y)` es sintaxis especial del parser y NO admite
      -- calificación de esquema: `pg_catalog.position('COALESCE' in ...)` es un
      -- ERROR DE SINTAXIS que aborta el DO entero y, como todo el fichero va en
      -- una sola transacción, deja la migración SIN APLICAR (verificado). Y el
      -- arreglo fácil equivocado sería `pg_catalog.position('COALESCE',
      -- upper(...))`: compila, pero esa forma lleva los argumentos al revés
      -- —`position(cadena, subcadena)`, comprobado: `position('a','abc')` = 0—
      -- con lo que el guard daría 0 siempre y abortaría la migración aunque los
      -- índices estuvieran bien.
      and pg_catalog.strpos(pg_catalog.upper(i.indexdef), 'COALESCE') = 0
  ) then
    raise exception 'Los indices del numerador deben indexar coalesce(resultado_en, finalizado_en), no la columna cruda';
  end if;

  -- (10) La auditoria de la tabla nueva (LEEME.md §7).
  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'crm.conversion_pesos'::pg_catalog.regclass
      and t.tgname = 'trg_audit_conversion_pesos'
      and not t.tgisinternal
  ) then
    raise exception 'crm.conversion_pesos debe tener trigger de auditoria';
  end if;
end;
$postflight$;

commit;

-- Nota de aplicacion:
--   · Nombre del archivo: `$(date -u +%Y%m%d%H%M%S)_crm_conversion_mensual_ponderada.sql`
--     (timestamp UTC del momento; dos migraciones en el mismo segundo colisionan
--     la PK de supabase_migrations.schema_migrations). Debe quedar ANTES de
--     `20260811190324_crm_origen_inmutable.sql` (migracion D; la version con
--     ventana de gerencia, `20260811164017_..._correccion_gerencia.sql`, quedo
--     DESCARTADA y se borro del arbol sin aplicarse) y de
--     `20260811210049_crm_alta_manual_origen_restringido.sql` (migracion F, la
--     regla D8 del alta): las CUATRO van juntas en el paso 1, y esta primero.
--   · MISMO DESPLIEGUE, sin excepcion, que
--     `20260811190310_crm_ledger_cierres_integros.sql`. No es coordinacion
--     estetica: hasta que exista su indice unico parcial «una conversion por
--     lead», dos cosas quedan abiertas y NINGUNA se puede cerrar desde aqui —
--     (a) el mismo lead cerrado por DOS analistas suma 1 + 1 en `total`
--     (el count(distinct) de esta migracion solo deduplica dentro de un
--     analista), y (b) dos episodios convertidos del mismo lead con snapshots
--     de `origen` distintos descuadran `cierres_*` contra `procedencia`. Si por
--     lo que sea A tuviera que salir sola, esas dos ventanas estan vivas y hay
--     que decirlo en el parte, no descubrirlo en la pantalla.
--   · `create index` sin CONCURRENTLY toma SHARE sobre crm.leads y
--     crm.lead_asignaciones: bloquea INSERT/UPDATE/DELETE mientras construye y
--     las lecturas siguen pasando (medido; NO es ACCESS EXCLUSIVE, como decia
--     la version anterior de esta nota). Instantaneo al volumen medido hoy
--     (1 fila y 232 kB en el ledger; 1 fila y 360 kB en leads) y con
--     `lock_timeout = '10s'` de seguro. El umbral a partir del cual hay que
--     sacarlos a una migracion aparte con CONCURRENTLY —~100 000 filas en el
--     ledger o ~50 000 en leads— esta razonado en la cabecera, seccion «Los
--     cuatro indices van SIN CONCURRENTLY».
--   · Ciclo obligatorio: branch de Supabase -> aplicar -> `npm run seed:demo`
--     (el branch nace vacio) -> `supabase/scripts/test-rls.mjs` ->
--     `supabase/scripts/test-conversion-mensual.sql` -> advisors -> reactivar
--     `trg_equipo_validar_usuarios_jerarquia` (tgenabled='O', 0 triggers en
--     disable) -> merge. Prohibido `apply_migration` directo a produccion.
--   · ADVISORS, numeros esperados (medidos en prod el 2026-08-11 ANTES de
--     aplicar): 0 ERROR, y DOS contadores suben en +1, los dos esperados:
--       - INFO  `rls_enabled_no_policy`                                8 -> 9
--         (crm.conversion_pesos; clase ya aceptada: crm.cuentas_bancarias,
--          crm.contrato_cuentas_pago, crm.lead_sla_*).
--       - WARN  `authenticated_security_definer_function_executable`  92 -> 93
--         (crm.conversion_mensual_fn). Las TRES funciones de `private` NO suman:
--         estan revocadas a authenticated.
--     Contrastar contra estos numeros, no contra el 92/8 anotado en el ledger de
--     20260810163458, o el +1 se leera como regresion.
--   · El gate NO es re-ejecutable sobre la misma base y el ledger es inmutable:
--     si hay que repetir la corrida, RESETEAR el branch, no limpiar a mano.
--   · Despues: delta A MANO en `app/src/lib/database.types.ts` con la firma
--     `conversion_mensual_fn: { Args: { p_periodo: string }; Returns: Json }`.
--     NO correr `gen:types` completo contra prod: reformatea el archivo curado y
--     rompe 100+ tipos.
--   · Rollback: `drop function crm.conversion_mensual_fn(date);` (nadie la lee
--     todavia). El resto es aditivo en esquema y puede quedarse sin efecto
--     alguno. Lo que NO se deshace con un `drop` son las DOS filas escritas: la
--     semilla de `crm.conversion_pesos` (que se iria con la tabla) y su apunte
--     en `public.audit_log`, que es inmutable por diseño y debe quedarse — un
--     ledger de auditoria del que se borran los intentos fallidos no es un
--     ledger de auditoria.

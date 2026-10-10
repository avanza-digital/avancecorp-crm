-- REGISTRO en supabase_migrations.schema_migrations de 20261009210000_crm_anular_venta_mes_sellado (bloque 2.6 del grupo A).
-- GENERADO por generar_registrador.py: no editar a mano. `db query --linked --file` NO registra: correr DESPUÉS de aplicar la
-- migración, por la misma vía. Desde `CRM-Avance-Corp/`, en este orden (el Director lo ensaya antes en la branch):
--   1. supabase db query --linked --file supabase/migrations/20261009210000_crm_anular_venta_mes_sellado.sql
--   2. supabase db query --linked --file supabase/scripts/anular-venta-mes-sellado/registrar/20261009210000.sql
--   (después, el 2.3: 20261009210100 y su registrador, supabase/scripts/numero-contrato-servidor/registrar/20261009210100.sql)
-- Por `db query --linked` no llegan los NOTICE; llega la última fila (va tras el COMMIT, como en las migraciones de la casa):
-- registrado = sin error y la fila «20261009210000 | 49271955876c0320b9fa4d202e547773».
-- Un error = no registró nada (todo va en una transacción).
-- Idempotente (correrlo dos veces deja una sola fila). Se NIEGA, sin escribir nada, si:
--   · el estado instalado no es el que deja la migración: de las dos puertas y del detector private.mes_sellado_de_venta(uuid),
--     cuerpo, definición entera, ficha (dueño, security definer/invoker, search_path), ACL efectiva y comentario; o el ledger no es
--     el de F4.2-bis (private.conversion_episodios 125b4046f513657ac57ec676a0d52e87,
--     private.conversion_cierres 155ce2b12754718388c8ca1644c84c90): con el 2.6 anterior (df101234…, ledger e3d278a1…) las puertas y
--     el detector son los mismos, pero este registrador se niega;
--   · el nombre crm_anular_venta_mes_sellado ya está registrado con OTRA versión (p. ej. 20261009160000, la de las rondas 1 a 3);
--   · la versión 20261009210000 ya está registrada con otro nombre u otro contenido.
-- statements = el archivo entero (md5 49271955876c0320b9fa4d202e547773),
-- incrustado UNA sola vez en la tabla temporal pg_temp.registro_20261009210000 (on commit drop).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_anular_venta_mes_sellado_registro'));
create temp table registro_20261009210000 on commit drop as
select $mig$-- NO SE PUEDE ANULAR UNA VENTA DE UN MES SELLADO — el servidor rechaza anular la
-- conversión (el cierre inicial) cuyo mes de venta ya tiene fila en
-- `crm.periodos_cerrados`, salvo para quien es a la vez admin/superadmin del Portal
-- y Gerencia del CRM, que la anula SIN ajuste y dejando rastro.
--
-- QUÉ PASABA. `crm.anular_cierre_avance` y `crm.anular_cierre_externo` (solo si el
-- cierre es inicial) llamaban a `private.registrar_ajuste_si_mes_cerrado` y, si el mes
-- de la venta estaba sellado, hacían nacer una deuda en `crm.ajustes_mes_cerrado` que el
-- vendedor arrastra al mes vivo. Y cuando esa función devolvía NULL en un mes sellado
-- (venta fuera de plazo, origen que no pesa, sin acreditación, sin episodio de cierre),
-- la anulación pasaba sin dejar ni deuda: el mes sellado cambiaba en silencio.
--
-- QUÉ HACE.
--   1. `private.mes_sellado_de_venta(uuid)` (nueva; SECURITY INVOKER, `search_path` vacío, sin EXECUTE
--      para nadie salvo su dueño): dada la venta (lead), devuelve TRES cosas, por parámetros OUT:
--      `p_mes` (el mes de la venta, o NULL), `p_sellado` (ese mes tiene fila en `crm.periodos_cerrados`)
--      y `p_desconocido` (no se pudo determinar el mes). Resuelve el mes con una POLÍTICA NUEVA, más estricta que la
--      de `registrar_ajuste_si_mes_cerrado` (20260927073637:797-958), que VOLVÍA ANTES de consultar las fuentes (sin
--      `convertido_en` devolvía nada, y en la rama de septiembre sin acreditación también): aquí se consultan las
--      fuentes en este orden y «desconocido» se decide solo al final:
--        a) con la política de septiembre activa y la venta convertida desde el 01/09, el `periodo_comercial`
--           de su fila de acreditación (`crm.conversion_acreditaciones` tiene UNIQUE (lead_id): a lo sumo una);
--        b) si no, el episodio de cierre del ledger (`private.conversion_episodios`): si hubiera MÁS DE UNO,
--           el mismo error de integridad que lanza `registrar_ajuste…` («Integridad: el lead % tiene % episodios
--           de cierre en el ledger», SQLSTATE P0001) y nada se escribe; si hay uno, su mes;
--        c) si no hay episodio, el mes de `leads.convertido_en` en hora de Lima;
--        d) si tampoco hay fecha (o el lead no existe) ⇒ MES DESCONOCIDO. Se decide DESPUÉS de intentar la
--           acreditación y el episodio, nunca antes: una acreditación con mes sellado manda aunque falte la fecha.
--        e) El mes resuelto tiene que ser un PRIMER DÍA DE MES y nunca nulo. Lo que lo garantiza, exactamente: en
--           `crm.conversion_acreditaciones`, el NOT NULL de `fecha_comercial` MÁS el NOT NULL de `periodo_comercial` MÁS el
--           CHECK `periodo_comercial = date_trunc('month', fecha_comercial)::date` ⇒ el periodo es siempre el primer día
--           de un mes (con `fecha_comercial` nula el CHECK daría UNKNOWN y pasaría: el NOT NULL de `fecha_comercial` es
--           parte de la garantía, no un adorno); y en `crm.periodos_cerrados`, el NOT NULL y el CHECK de primer día de
--           `periodo`. El preflight exige esas cinco cosas (los NOT NULL por `attnotnull`, los CHECK por su texto). Y el
--           detector lo vuelve a exigir en tiempo de ejecución: si aun así recibiera un mes nulo o no canónico por
--           cualquier fuente, SQLSTATE P0001 «Integridad: el mes de la venta … no es un primer día de mes» y nada se
--           escribe. NUNCA «abierto»: un mes que no casa con el sello por no ser canónico no es un mes sin sellar.
--      TOMA EL CERROJO DEL MES (`pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'), mes - 2000-01-01)`, el
--      mismo de `crm.cerrar_periodo`) ANTES de mirar `crm.periodos_cerrados`: sin él, una anulación concurrente con
--      el sellado de ESE mes lee «abierto» porque el sello aún no ha hecho commit. Se pregunta por el sello, NO por
--      el reloj: un mes terminado pero aún sin sellar (la ventana del 1 al 10) sigue admitiendo la anulación.
--      Solo admite READ COMMITTED: en cualquier otro modo de transacción, 0A000 antes de mirar nada (patrón de
--      20261002163158; con una fotografía fija la espera del cerrojo no renovaría lo leído).
--      Por qué INVOKER: es un núcleo de `private` que solo invocan dos puertas DEFINER; corre como quien ejecuta la
--      puerta (su dueño, `postgres`) y nadie más tiene EXECUTE: la excepción documentada del estándar
--      (`MIGRACIONES.md`, 20261001160219: «INVOKER y sin EXECUTE para nadie»). No necesita privilegios propios.
--   2. Las dos puertas llaman al detector ANTES de escribir nada. Mes SELLADO o DESCONOCIDO, y quien llama NO es
--      `public.es_admin()` Y `private.es_gerencia_crm_activa()`: SQLSTATE `P0409`, mensaje «No se puede anular: el
--      mes de esta venta (AAAA-MM) ya está sellado» (sellado) o «No se puede anular: no se puede determinar el mes
--      de esta venta» (desconocido; falla cerrado) y la pista «Un mes sellado no se reescribe. La corrección se hace
--      por otra vía, fuera del sistema.». Mes NO sellado: como hoy. En `anular_cierre_externo` solo cuando
--      `es_cierre_inicial`: renovación, upgrade y reinversión no cambian (D-14).
--   3. El exento (D-17) anula SIN ajuste: las puertas ya no llaman a `registrar_ajuste_si_mes_cerrado` (queda sin
--      llamadas desde ellas; no se toca su definición, declarada en el vigía analítico) y siguen devolviendo
--      `mes_cerrado:false` y `ajuste_id:null` (la pantalla «Eliminar inversión» valida ese booleano). EL RASTRO
--      FIABLE DEL EXENTO SON LAS CLAVES `excepcion_*` de los metadatos de la actividad: `excepcion_mes_sellado`
--      (AAAA-MM, o 'desconocido'), `excepcion_por` (uuid de quien anuló) y `excepcion_en` (instante), además del
--      `motivo` de siempre. `mes_cerrado` se conserva en `false` por compatibilidad con la pantalla y queda
--      grabado así en una actividad inmutable: NO dice si el mes estaba sellado; eso lo dice `excepcion_*`.
--      Sin sesión de usuario (`auth.uid()` nulo) la puerta ya rechaza con 42501 «Solo gerencia…»: no hay excepción.
--      `service_role` ni siquiera llega al cuerpo: no tiene EXECUTE sobre las puertas (42501 por ACL, con el
--      mensaje «permission denied for function»).
--
-- QUÉ NO CAMBIA. Mes abierto, mes terminado sin sellar, cierres externos no iniciales y «ya estaba anulado»:
-- idénticos a hoy, mensajes y claves incluidos. No se toca `private.registrar_ajuste_si_mes_cerrado`,
-- `private.saldar_ajustes`, `crm.cerrar_periodo`, `crm.eliminar_inversion_fn` (hereda el rechazo y la excepción
-- porque llama a estas dos puertas), los `assert_*`, tablas, grants, policies ni nada de `public`. Un ajuste YA
-- existente sigue su curso: no se condona nada. Las puertas conservan firma, dueño, `security definer`,
-- `search_path` y ACL; el resto de cada cuerpo es, byte a byte, el vigente.
--
-- CÓMO SE CAMBIAN LAS PUERTAS. Por anclas únicas sobre el cuerpo vivo (`pg_get_functiondef` + `replace`): cada
-- ancla tiene que aparecer EXACTAMENTE una vez o la migración aborta. Y solo se instala sobre lo que se auditó:
--   · el cuerpo vigente de cada puerta por su huella (`md5(prosrc)` 8556d0bd… avance, 09a47896… externo;
--     `md5(pg_get_functiondef)` 23e3be19… y f568b78f…) y su ficha (dueño `postgres`, `security definer`,
--     `search_path` vacío, ACL = dueño + `authenticated`, SIN opción de concesión);
--   · los tres objetos de los que depende la excepción (`public.es_admin`, `private.es_gerencia_crm_activa`,
--     `private.rol_crm`) por su huella Y su ficha completa: dueño, `security definer`, volatilidad, modo paralelo,
--     `proconfig` y ACL completa con opción de concesión (valores medidos en el laboratorio el 07/10/2026). Un
--     `ALTER FUNCTION public.es_admin() IMMUTABLE` conserva el `md5(prosrc)` y cambiaría lo que esta regla garantiza;
--   · lo que hace canónico el mes, por su texto (`pg_get_constraintdef` y `attnotnull`, medidos en el laboratorio el
--     07/10/2026): en `crm.conversion_acreditaciones`, `fecha_comercial` NOT NULL, `periodo_comercial` NOT NULL y
--     `CHECK ((periodo_comercial = (date_trunc('month'::text, (fecha_comercial)::timestamp without time zone))::date))`; en
--     `crm.periodos_cerrados`, `periodo` NOT NULL con `CHECK ((periodo = (date_trunc('month'::text, (periodo)::timestamp
--     with time zone))::date))`. Si falta cualquiera de las cinco, la migración se niega;
--   · el ledger del que el detector saca el mes del episodio, en sus DOS funciones: `md5(prosrc)` de
--     `private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)` = 125b4046f513657ac57ec676a0d52e87
--     y de `private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])` =
--     155ce2b12754718388c8ca1644c84c90 (las de PRODUCCIÓN, medidas el 09/10/2026 en el laboratorio igual a producción, ya con
--     20261009200000; antes, e3d278a1… en F4.2, y 9c606dd4… y b1d6c336… en la auditoría de la fase 2: ver «RE-AUDITORÍA F4.2» y
--     «RE-AUDITORÍA F4.2-bis» abajo). `conversion_episodios` delega los
--     cierres en `conversion_cierres`, y de ahí sale la `fecha_numerador` de la que el detector saca el mes
--     (`coalesce(la.resultado_en, la.finalizado_en)` antes de septiembre; `ca.fecha_comercial` desde septiembre): otra
--     implementación de cualquiera de las dos puede resolver otro mes conservando la huella de la otra, así que otra huella
--     en cualquiera hace abortar el preflight (y el postflight las vuelve a exigir). `conversion_cierres` llama a su vez a
--     `private.cierre_externo_anulado`, `private.conversion_exclusion_fuente`, `private.peso_referido_conversion` y (desde
--     20261006042144) `private.conversion_origen_con_cierre`; y `conversion_episodios` llama (desde 20261007160937) a
--     `private.conversion_origen_base_tope` y `private.tope_referidos_conversion` y (desde 20261009200000, solo en su pierna de
--     operaciones) a `private.analista_efectivo_contrato`: son DEPENDENCIAS DECLARADAS, NO FIJADAS (deciden qué cierres entran y
--     con qué peso o tope, o a quién se atribuye una operación de cartera, no la fecha del episodio); el corte de la auditoría se
--     cierra en `conversion_cierres` y `conversion_episodios` y, si cambian, se re-auditan.
-- El postflight vuelve a exigir la ficha idéntica, los cuerpos nuevos exactos (y el del detector), las dos huellas del
-- ledger y que la guarda esté en las dos.
--
-- RE-AUDITORÍA F4.2 (09/10/2026; plan backend, fase 4). La migración se negaba en el laboratorio igual a producción porque
-- `main` cambió el ledger y dos piezas que el postflight fija como «no se tocan». Se compararon los cuerpos auditados
-- (reconstruidos byte a byte de 20260923155859, 20260927073637 y 20260923172517, con su md5 comprobado) con los de producción:
--   · `private.conversion_cierres` (b1d6c336… → 155ce2b1…, 20261006042144, bases cargadas B11): solo cambia la columna del
--     aporte (`l.origen in ('landing','formulario')` → `private.conversion_origen_con_cierre(l.origen)`, en sus dos ramas: la
--     base cargada pesa 1). Las filas, `tipo`, `lead_id`, `anulado` y `fecha_numerador`, y todos los filtros, idénticos.
--   · `private.conversion_episodios` (9c606dd4… → e3d278a1…, 20261007160937, tope de referidos): los cierres se piden a
--     `conversion_cierres` sobre los MESES COMPLETOS que toca la ventana y se recortan después a `[p_ini, p_fin)` por la misma
--     `fecha_numerador` con que `conversion_cierres` filtra; el ámbito se aplica igual; el tope solo pone a 0 el
--     `aporte_numerador` de los referidos que lo pasan. Para la llamada del detector (1900–2100, global) las filas de cierre
--     son exactamente las mismas, con la misma `fecha_numerador`; el detector no lee el aporte. (El nuevo desempate lee
--     `crm.conversion_acreditaciones` por `lead_id` en una subconsulta escalar: el UNIQUE (lead_id) que este preflight exige
--     también la protege.)
--   · `private.registrar_ajuste_si_mes_cerrado` (00b17e77… → fec614f0…, B11): solo su numerador (la base cargada pesa 1). Las
--     puertas dejan de llamarla con esta migración; se fija para probar que esta migración no la toca.
--   · `crm.cerrar_periodo` (ce1ca52d… → 79840e5a…, 20261007160937 y 20261007203000): la foto guarda `tope_referidos_pct` y
--     `cobertura.referidos_aporte`. Su CERROJO DEL MES —`pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'),
--     periodo - 2000-01-01)`, el mismo que toma el detector— está en las mismas líneas y con el mismo texto.
-- Conclusión: el detector resuelve el MISMO mes para la misma venta y la regla garantiza lo mismo. Medido, además, con un
-- ensayo de equivalencia (ledger auditado recreado en pg_temp frente al vigente; detector entero sobre cada uno; todos los
-- leads del laboratorio más siembras de tope, base cargada, alta manual, anulado, desempate y frontera de mes; política de
-- septiembre apagada y encendida): 0 filas de cierre distintas, 0 meses distintos, 0 respuestas del detector distintas, y 7
-- aportes distintos (el ledger nuevo sí actúa sobre lo sembrado). Evidencia: `fase-4/F4.2-reselle/salidas/` del plan.
--
-- RE-AUDITORÍA F4.2-bis (09/10/2026, tarde). Producción aplicó ese día `20261009200000_crm_baja_analista_heredero` (un analista
-- dado de baja cede su capital y sus operaciones al responsable actual activo), que reescribe `private.conversion_episodios`
-- (e3d278a1… → 125b4046…): la migración volvía a negarse en el preflight. El cambio son dos líneas, las dos en la pierna de
-- OPERACIONES de cartera: su analista y su filtro de ámbito pasan de `coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id),
-- o.vendedor_id)` a `private.analista_efectivo_contrato(o.contrato_nuevo_id, o.vendedor_id)` (la misma cadena de upgrade y, si ese
-- analista está dado de baja, su heredero). Las piernas de llegadas y de cierres, el tope y `conversion_cierres` no cambian. El
-- detector solo lee filas `tipo = 'cierre'` (la llamada es global: el ámbito no filtra) y no lee el analista: para la misma venta
-- resuelve el MISMO mes con la política de septiembre apagada o encendida (en producción, encendida desde el 27/09) y con un
-- analista dado de baja y su heredero. Las puertas, la excepción, el cerrojo del mes y lo demás que se fija, sin cambio.
-- Medido con un ensayo de equivalencia (rollback; `fase-4/F4.2b-reselle/salidas/trabajo/b26-equivalencia/`): el ledger de F4.2
-- (e3d278a1…) recreado en pg_temp frente al vigente (125b4046…) y el detector entero sobre cada uno, para los 41 leads del
-- laboratorio y 20 ventas sembradas (tope, base cargada, alta manual, anulado, desempate, frontera de mes, `convertido_en` en otro
-- mes que el episodio, y ventas de un analista que se da de baja con heredero), en cuatro estados (política apagada o encendida,
-- sin o con dos analistas dados de baja): 0 filas de cierre o de llegada distintas en ninguna columna, 0 filas de operación
-- distintas salvo el analista, 0 respuestas del detector distintas entre ledgers y entre «con baja» y «sin baja», 0 errores y
-- las 20 siembras con su resultado esperado; no es vacío: con la baja, el ledger vigente atribuye 2 operaciones al heredero.
-- Evidencia: `fase-4/F4.2b-reselle/salidas/` del plan.
--
-- CONSECUENCIAS (para quien integre).
--   · La huella de las dos puertas CAMBIA. `20261005200945_crm_eliminar_inversion.sql:107-108` (y
--     `scripts/eliminar-inversion/registrar.sql:127-128, 1112-1113`) fijan por `md5(pg_get_functiondef)` las
--     huellas ANTERIORES de estas puertas (`f568b78f…` / `23e3be19…`): esa migración y su registrador se
--     niegan si se corren DESPUÉS de esta. Orden de aplicación: primero `20261005200945`, luego esta; y el
--     registrador de `eliminar_inversion` debe actualizar esas dos huellas. NO se cambian aquí. (F4.2, 09/10/2026:
--     `20261005200945` ya está aplicada en producción y en el laboratorio igual a producción, así que el orden se cumple; el
--     aviso sobre su registrador sigue en pie si alguien lo vuelve a correr.)
--   · Con esta migración no se puede eliminar una inversión cuya conversión cae en un mes sellado
--     (`eliminar_inversion_fn` anula primero la conversión), salvo para el exento: admin + Gerencia.
--   · Esta migración FIJA la versión del ledger en sus DOS funciones: `private.conversion_episodios` (huella 125b4046…)
--     y `private.conversion_cierres` (huella 155ce2b1…), las de producción el 09/10/2026 (con 20261009200000). Si el `main` del
--     día de integrar tiene OTRA versión de CUALQUIERA de las dos, la migración SE NIEGA: entonces hay que RE-AUDITAR el
--     detector contra esa versión (casos de fecha en la frontera del mes, episodios desde el 01/09, cierres externos anulados)
--     y, solo después, actualizar la huella aquí y en el ensayo. Lo mismo si en la branch difiere el TEXTO de alguno de los
--     CHECK o falta un NOT NULL de los fijados: releerlos con la misma consulta (`pg_get_constraintdef`, `attnotnull`) y
--     RE-AUDITAR el detector ANTES de adaptar la migración; nunca adaptar la huella o el texto sin más. Es un requisito de la
--     fase 4, no un trámite.
--
-- A QUÉ PLAN RESPONDE. Plan de mantenibilidad del backend del CRM (AVANCE-BACKEND-0610), fase 2, bloque 2.6
-- (decisiones D-09, D-14 y D-17 de Miguel, 2026-10-06). Ronda 2 tras las revisiones de Codex y del auditor de
-- permisos (2026-10-07, CHANGES_REQUESTED sin P0/P1, conciliadas por el Director); ronda 3 tras la segunda revisión
-- de Codex (2026-10-07, CHANGES_REQUESTED sin P0/P1: reversa fail-closed completa, mes nulo o no canónico, huella del
-- ledger y textos; `fase-2/bloque-2.6/revision/CONCILIACION-R2.md`); ronda 4 tras la tercera revisión de Codex
-- (2026-10-07, CHANGES_REQUESTED sin P0/P1: un P2 —la huella del ledger no cubría `conversion_cierres`— y dos P3 —el NOT
-- NULL de `fecha_comercial` como parte de la garantía del mes canónico; la reversa no comparaba los comentarios—;
-- `fase-2/bloque-2.6/revision/CONCILIACION-R3.md`). Fase 4, F4.2 (2026-10-09): reselle contra el código de producción
-- (decisiones D-24, D-26 y D-33): solo cambian las huellas de `conversion_episodios`, `conversion_cierres`,
-- `registrar_ajuste_si_mes_cerrado` y `cerrar_periodo`, tras la re-auditoría de arriba; el detector, las puertas, la regla y
-- su excepción, sin cambio (verificado por el Director; Codex y auditor de permisos: PASS). Fase 4, F4.2-bis
-- (2026-10-09, tarde): producción aplicó 20261009200000 (baja de analista), que reescribe `conversion_episodios`: solo cambia esa
-- huella, tras la re-auditoría de arriba. Pendiente de la verificación del Director, de Codex y del auditor de permisos.
--
-- VERIFICACIÓN. `supabase/scripts/anular-venta-mes-sellado/`: el oráculo sale ROJO sin esta migración (el servidor
-- deja anular, y crea ajuste, en un mes sellado) y VERDE con ella; sus mutantes mueren por su fallo; las derivas
-- previas la hacen abortar en el preflight; la reversa devuelve las huellas originales y se niega si un cuerpo, una
-- definición, una ficha (dueño, atributos, ACL con opción de concesión), un comentario o el detector no son exactamente
-- los que dejó (cinco secuencias ensayadas: limpia, SET, GRANT, detector alterado, comentario cambiado). Verificada solo
-- en el laboratorio local (desde F4.2-bis, el laboratorio igual a producción del 09/10/2026: B5+B6, `main` a3b89cc4 y la
-- extra 20261009200000).
--
-- REVERSIÓN: `supabase/scripts/anular-venta-mes-sellado/reversa.sql` repone los dos cuerpos anteriores
-- (`md5(prosrc)` vuelve a 8556d0bd… y 09a47896…; `md5(pg_get_functiondef)` a 23e3be19… y f568b78f…), repone sus
-- comentarios y borra el detector. CONTRATO (FALLA CERRADA): antes de tocar nada exige, y si algo difiere se niega
-- sin dejar rastro,
--   (a) de las dos puertas: `md5(prosrc)` Y `md5(pg_get_functiondef)` exactamente los que dejó esta migración (un
--       `ALTER FUNCTION … SET lock_timeout` posterior la hace abortar), y su ficha auditada: dueño `postgres`,
--       `security definer`, `search_path` vacío y ACL EXACTA con opción de concesión (EXECUTE solo para el dueño y
--       `authenticated`, sin `GRANT OPTION`: un `GRANT EXECUTE … TO service_role` posterior la hace abortar, porque
--       `create or replace` lo conservaría en silencio);
--   (b) del detector `private.mes_sellado_de_venta(uuid)`: que exista, `md5(prosrc)` Y `md5(pg_get_functiondef)`
--       exactamente los que dejó esta migración (un `CREATE OR REPLACE` posterior con otro cuerpo la hace abortar,
--       porque el `DROP` lo borraría sin aviso) y su ficha INVOKER (dueño `postgres`, `security invoker`,
--       `search_path` vacío, sin EXECUTE para nadie salvo el dueño);
--   (c) los COMENTARIOS (`obj_description`) de las dos puertas y del detector, exactamente los que dejó esta migración
--       (un `COMMENT ON FUNCTION … IS 'otro'` posterior la hace abortar: la reversa repone los dos primeros y borra el
--       tercero, y se los llevaría por delante sin verlos).
-- Esa lista es TODO lo que la reversa exige —cuerpos, definiciones, ficha (dueño, `security definer`/`invoker`,
-- `search_path`), ACL con `is_grantable`, comentarios, y existencia y huellas del detector— y no promete detectar nada
-- fuera de ella. En todos esos casos se revisa a mano (o se corrige hacia delante con otra migración). No hay datos que
-- deshacer: la regla solo rechaza; lo que el exento anuló queda anulado (la reversa no des-anula nada).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $preflight$
declare
  v_oid    oid;
  v_h      record;
  v_huella text;
  v_ficha  text;
begin
  -- 1. Los dos cuerpos que se reemplazan: la huella auditada, y solo ella.
  if to_regprocedure('crm.anular_cierre_avance(uuid,text)') is null
     or to_regprocedure('crm.anular_cierre_externo(uuid,text)') is null then
    raise exception 'PREFLIGHT anular_venta_mes_sellado: faltan las puertas crm.anular_cierre_avance / crm.anular_cierre_externo';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.anular_cierre_avance(uuid,text)'::regprocedure)
       is distinct from '8556d0bde6dd80fd58e673f563c87005'
     or md5(pg_get_functiondef('crm.anular_cierre_avance(uuid,text)'::regprocedure))
       is distinct from '23e3be1974e08a1ec8aa61abe53242c3' then
    raise exception 'PREFLIGHT anular_venta_mes_sellado: crm.anular_cierre_avance cambió desde que se auditó (o esta migración ya está aplicada): revisar antes de añadir la guarda';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.anular_cierre_externo(uuid,text)'::regprocedure)
       is distinct from '09a4789692b40df642cece433475e9fa'
     or md5(pg_get_functiondef('crm.anular_cierre_externo(uuid,text)'::regprocedure))
       is distinct from 'f568b78fc917d56cb00b5f88efd85deb' then
    raise exception 'PREFLIGHT anular_venta_mes_sellado: crm.anular_cierre_externo cambió desde que se auditó (o esta migración ya está aplicada): revisar antes de añadir la guarda';
  end if;
  -- 2. Su ficha: `create or replace` conserva dueño y ACL, así que una deriva previa sobreviviría al cambio
  --    y la comparación «antes = después» del postflight la daría por buena. Identidad con lo auditado, opción de
  --    concesión incluida (un `GRANT … WITH GRANT OPTION` conserva la lista de concesionarios y privilegios).
  for v_oid in
    select unnest(array['crm.anular_cierre_avance(uuid,text)'::regprocedure::oid,
                        'crm.anular_cierre_externo(uuid,text)'::regprocedure::oid])
  loop
    if not exists (
         select 1 from pg_proc p
         where p.oid = v_oid
           and p.proowner = 'postgres'::regrole::oid
           and p.prosecdef
           and p.proconfig = array['search_path=""'])
       or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
             from pg_proc p
             cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
            where p.oid = v_oid)
          is distinct from array['authenticated:EXECUTE:false', 'postgres:EXECUTE:false'] then
      raise exception 'PREFLIGHT anular_venta_mes_sellado: la ficha de % no es la auditada (dueño postgres, security definer, search_path vacío, EXECUTE solo para el dueño y authenticated, sin opción de concesión)', v_oid::regprocedure;
    end if;
  end loop;
  if obj_description('crm.anular_cierre_avance(uuid,text)'::regprocedure, 'pg_proc') is distinct from
       'Anula un cierre de Avance (error de gestion o mala practica), SOLO gerencia y con motivo obligatorio. El cierre deja de acreditarle al vendedor en la CUOTA y en la CONVERSION a la vez. NO mueve dinero real: el contrato y el cliente siguen intactos en public. El lead NO se reabre (un convertido es terminal por diseno) y el episodio del ledger no se toca (es inmutable). De una sola direccion: no se des-anula. Deja actividad tipo nota con el motivo.'
     or obj_description('crm.anular_cierre_externo(uuid,text)'::regprocedure, 'pg_proc') is distinct from
       'Anula un cierre en cooperativa (fraude o error), SOLO gerencia y con motivo obligatorio. El cierre deja de contar en la cuota Y en la conversion mensual; la fila NO se borra (es el ancla de legalidad del lead convertido) y el lead NO se reabre (un convertido es terminal por diseno). Es de una sola direccion: no se des-anula. Deja actividad tipo nota con el motivo y la foto de lo anulado.' then
    raise exception 'PREFLIGHT anular_venta_mes_sellado: el comentario de una puerta cambió desde que se auditó: revisar antes de reemplazarlo';
  end if;
  -- 3. Lo que decide la excepción, sin tocarlo: cuerpo (huella) Y ficha completa (dueño, security definer,
  --    volatilidad, modo paralelo, proconfig y ACL con opción de concesión), medidos en el laboratorio el 07/10/2026.
  --    Si cambia, cambia lo que esta regla garantiza.
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.es_admin()'))
       is distinct from 'f4e01285f0b006f72b984213a6a95310'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.es_gerencia_crm_activa()'))
       is distinct from 'e2e84b58044078e40e506f623985e86d'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.rol_crm(uuid)'))
       is distinct from 'd2878a210be96ac85973d51dfcfb27a5' then
    raise exception 'PREFLIGHT anular_venta_mes_sellado: cambió public.es_admin, private.es_gerencia_crm_activa o private.rol_crm: la excepción del admin ya no es la auditada';
  end if;
  for v_h in
    select * from (values
      ('public.es_admin()',
       'postgres|true|s|u|search_path=public, pg_temp|authenticated:EXECUTE:false,postgres:EXECUTE:false,service_role:EXECUTE:false'),
      ('private.es_gerencia_crm_activa()',
       'postgres|true|s|u|search_path=""|postgres:EXECUTE:false'),
      ('private.rol_crm(uuid)',
       'postgres|true|s|u|search_path=""|authenticated:EXECUTE:false,postgres:EXECUTE:false')
    ) as h(firma, ficha)
  loop
    select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || p.proparallel::text
             || '|' || coalesce(array_to_string(p.proconfig, ';'), '-')
             || '|' || coalesce((select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text)
                                   from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a), '-')
      into v_ficha
      from pg_proc p
     where p.oid = to_regprocedure(v_h.firma);
    if v_ficha is distinct from v_h.ficha then
      raise exception 'PREFLIGHT anular_venta_mes_sellado: la ficha de % no es la auditada (medida «%»; auditada «%»): la excepción del admin ya no es la auditada', v_h.firma, coalesce(v_ficha, 'no existe'), v_h.ficha;
    end if;
  end loop;
  if to_regprocedure('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)') is null
     or to_regprocedure('private.conversion_episodios(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric)') is null
     or to_regclass('crm.periodos_cerrados') is null
     or to_regclass('crm.conversion_acreditaciones') is null
     or to_regclass('crm.conversion_politica') is null
     or to_regclass('crm.lead_asignaciones') is null then
    raise exception 'PREFLIGHT anular_venta_mes_sellado: falta algo de lo que el detector lee (ajuste de mes cerrado, ledger, acreditaciones, política o periodos)';
  end if;
  -- El detector supone que `crm.conversion_acreditaciones` tiene a lo sumo UNA fila por lead.
  if not exists (
       select 1 from pg_constraint c
       where c.conrelid = 'crm.conversion_acreditaciones'::regclass and c.contype = 'u'
         and (select array_agg(a.attname::text order by a.attnum) from pg_attribute a
               where a.attrelid = c.conrelid and a.attnum = any(c.conkey)) = array['lead_id']) then
    raise exception 'PREFLIGHT anular_venta_mes_sellado: crm.conversion_acreditaciones ya no tiene UNIQUE (lead_id): el detector supone una fila por lead';
  end if;
  -- 3b. El mes que lee el detector es, por esquema, un primer día de mes y nunca nulo. Lo garantizan, exactamente: en
  --     `crm.conversion_acreditaciones`, el NOT NULL de `fecha_comercial` + el NOT NULL de `periodo_comercial` + el CHECK
  --     `periodo_comercial = date_trunc('month', fecha_comercial)::date` (con `fecha_comercial` nula el CHECK daría UNKNOWN y
  --     pasaría: sin ese NOT NULL la garantía no existe); en `crm.periodos_cerrados`, el NOT NULL y el CHECK de primer día de
  --     `periodo`. Los CHECK se fijan por su TEXTO (pg_get_constraintdef, medido en el laboratorio el 07/10/2026), no por su
  --     nombre. El detector además lo vuelve a exigir en tiempo de ejecución (P0001): defensa en profundidad, no sustituto.
  if (select a.attnotnull from pg_attribute a
       where a.attrelid = 'crm.conversion_acreditaciones'::regclass and a.attname = 'fecha_comercial' and not a.attisdropped)
       is distinct from true then
    raise exception 'PREFLIGHT anular_venta_mes_sellado: crm.conversion_acreditaciones.fecha_comercial ya no es NOT NULL: con una fecha nula el CHECK de periodo_comercial daría UNKNOWN y no garantizaría un primer día de mes';
  end if;
  if (select a.attnotnull from pg_attribute a
       where a.attrelid = 'crm.conversion_acreditaciones'::regclass and a.attname = 'periodo_comercial' and not a.attisdropped)
       is distinct from true
     or not exists (
       select 1 from pg_constraint c
       where c.conrelid = 'crm.conversion_acreditaciones'::regclass and c.contype = 'c'
         and pg_get_constraintdef(c.oid) = 'CHECK ((periodo_comercial = (date_trunc(''month''::text, (fecha_comercial)::timestamp without time zone))::date))') then
    raise exception 'PREFLIGHT anular_venta_mes_sellado: crm.conversion_acreditaciones.periodo_comercial ya no es NOT NULL con CHECK periodo_comercial = date_trunc(month, fecha_comercial)::date: el detector supone un primer día de mes';
  end if;
  if (select a.attnotnull from pg_attribute a
       where a.attrelid = 'crm.periodos_cerrados'::regclass and a.attname = 'periodo' and not a.attisdropped)
       is distinct from true
     or not exists (
       select 1 from pg_constraint c
       where c.conrelid = 'crm.periodos_cerrados'::regclass and c.contype = 'c'
         and pg_get_constraintdef(c.oid) = 'CHECK ((periodo = (date_trunc(''month''::text, (periodo)::timestamp with time zone))::date))') then
    raise exception 'PREFLIGHT anular_venta_mes_sellado: crm.periodos_cerrados.periodo ya no es NOT NULL con CHECK periodo = date_trunc(month, periodo)::date: el sello supone un primer día de mes';
  end if;
  -- 3c. El ledger del que el detector saca el mes del episodio (su `fecha_numerador`), en sus DOS funciones: solo la
  --     implementación auditada. `conversion_episodios` delega los cierres desde septiembre en `conversion_cierres`: otra
  --     versión de cualquiera de las dos puede resolver otro mes conservando la huella de la otra. Se re-audita el detector
  --     antes de instalar. (Lo que `conversion_cierres` llama —cierre_externo_anulado, conversion_exclusion_fuente,
  --     peso_referido_conversion, conversion_origen_con_cierre— y lo que `conversion_episodios` llama para el tope
  --     —conversion_origen_base_tope, tope_referidos_conversion— decide inclusión, peso y tope, no la fecha: dependencias
  --     declaradas, no fijadas; y la pierna de operaciones de `conversion_episodios`, desde 20261009200000, llama a
  --     analista_efectivo_contrato, que decide a quién se atribuye una operación.) Huellas de producción re-auditadas en F4.2 y
  --     F4.2-bis (09/10/2026): ver la cabecera.
  select md5(p.prosrc) into v_huella from pg_proc p
   where p.oid = to_regprocedure('private.conversion_episodios(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric)');
  if v_huella is distinct from '125b4046f513657ac57ec676a0d52e87' then
    raise exception 'PREFLIGHT anular_venta_mes_sellado: private.conversion_episodios no es la versión auditada (medida «%»; auditada «125b4046f513657ac57ec676a0d52e87»): el detector depende de su fecha_numerador para elegir el mes; re-auditar el detector antes de instalar', coalesce(v_huella, 'no existe');
  end if;
  select md5(p.prosrc) into v_huella from pg_proc p
   where p.oid = to_regprocedure('private.conversion_cierres(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric,uuid[])');
  if v_huella is distinct from '155ce2b12754718388c8ca1644c84c90' then
    raise exception 'PREFLIGHT anular_venta_mes_sellado: private.conversion_cierres no es la versión auditada (medida «%»; auditada «155ce2b12754718388c8ca1644c84c90»): conversion_episodios delega en ella los cierres desde septiembre y el detector depende de su fecha_numerador para elegir el mes; re-auditar el detector antes de instalar', coalesce(v_huella, 'no existe');
  end if;
  -- 4. El detector no existe todavía.
  if to_regprocedure('private.mes_sellado_de_venta(uuid)') is not null then
    raise exception 'PREFLIGHT anular_venta_mes_sellado: private.mes_sellado_de_venta ya existe: no sobrescribir';
  end if;
  -- La ficha de las puertas, para exigir en el postflight que `create or replace` no la movió.
  perform set_config('crm.anular_mes_sellado_ficha_previa',
    (select string_agg(p.oid::regprocedure::text || '|' || p.proowner::regrole::text || '|' || p.prosecdef::text
        || '|' || coalesce(p.proconfig::text, '-') || '|' || coalesce(p.proacl::text, '-')
        || '|' || p.provolatile::text || '|' || p.proparallel::text || '|' || p.proleakproof::text
        || '|' || p.prorettype::regtype::text, ';' order by p.oid::regprocedure::text)
       from pg_proc p
      where p.oid in ('crm.anular_cierre_avance(uuid,text)'::regprocedure,
                      'crm.anular_cierre_externo(uuid,text)'::regprocedure)),
    true);
end
$preflight$;

-- ── El detector ──────────────────────────────────────────────────────────────────────────────────────────────────
-- SECURITY INVOKER a propósito: solo lo invocan las dos puertas DEFINER (corre como su dueño, `postgres`) y ningún
-- otro rol tiene EXECUTE (patrón del ledger, 20261001160219). `search_path` vacío y nombres calificados.
create function private.mes_sellado_de_venta(
  p_lead_id uuid,
  out p_mes date,
  out p_sellado boolean,
  out p_desconocido boolean)
returns record
language plpgsql
volatile
security invoker
set search_path = ''
as $func$
declare
  v_convertido_en       timestamptz;
  v_meses_episodio      date[];
  v_acreditacion        crm.conversion_acreditaciones%rowtype;
  v_acreditacion_actual crm.conversion_acreditaciones%rowtype;
begin
  -- Solo READ COMMITTED (patrón de 20261002163158): con una fotografía fija (REPEATABLE READ o SERIALIZABLE)
  -- esperar el cerrojo del mes no renovaría lo leído y el sello recién hecho se vería «abierto». Por la API
  -- (PostgREST) la transacción siempre va en READ COMMITTED: ninguna pantalla cambia.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode = '0A000',
      message = 'La anulación de una venta no admite este modo de transacción';
  end if;

  p_mes := null;
  p_sellado := false;
  p_desconocido := false;

  select l.convertido_en into v_convertido_en
  from crm.leads l
  where l.id = p_lead_id;
  -- Si el lead no existe o no tiene fecha, v_convertido_en queda nulo: se sigue intentando por la acreditación y
  -- por el episodio, y solo al final se declara «desconocido».

  -- a) Desde septiembre, el mes de la venta es el de su acreditación (misma condición que
  --    `private.registrar_ajuste_si_mes_cerrado`). `crm.conversion_acreditaciones` tiene UNIQUE (lead_id): a lo sumo
  --    una fila (el preflight lo exige). Sin fila se resuelve como antes de septiembre.
  if exists (select 1 from crm.conversion_politica cp where cp.activada_en is not null)
     and exists (select 1 from crm.lead_asignaciones la
                  where la.lead_id = p_lead_id and la.resultado = 'convertido'
                    and coalesce(la.resultado_en, la.finalizado_en) >= '2026-09-01 00:00 America/Lima'::timestamptz) then
    select * into v_acreditacion
    from crm.conversion_acreditaciones ca
    where ca.lead_id = p_lead_id;
  end if;

  if v_acreditacion.id is not null then
    p_mes := v_acreditacion.periodo_comercial;
  else
    -- b) El episodio de cierre del ledger manda sobre `convertido_en` (el cierre puede caer a caballo del mes).
    --    Más de un episodio es una violación de integridad (el ledger solo permite una conversión por lead): el
    --    mismo error que lanza `registrar_ajuste_si_mes_cerrado`, y nada se escribe.
    select pg_catalog.array_agg(pg_catalog.date_trunc('month', e.fecha_numerador at time zone 'America/Lima')::date
                                order by e.fecha_numerador)
      into v_meses_episodio
    from private.conversion_episodios(
           '1900-01-01'::timestamptz, '2100-01-01'::timestamptz,
           null::date, true, '{}'::uuid[], 1) e
    where e.lead_id = p_lead_id and e.tipo = 'cierre';
    if pg_catalog.cardinality(v_meses_episodio) > 1 then
      raise exception 'Integridad: el lead % tiene % episodios de cierre en el ledger', p_lead_id, pg_catalog.cardinality(v_meses_episodio);
    elsif pg_catalog.cardinality(v_meses_episodio) = 1 then
      p_mes := v_meses_episodio[1];
    elsif v_convertido_en is not null then
      -- c) Sin episodio: el mes de `leads.convertido_en` en hora de Lima.
      p_mes := pg_catalog.date_trunc('month', v_convertido_en at time zone 'America/Lima')::date;
    else
      -- d) Ni acreditación, ni episodio, ni fecha de conversión (o el lead no existe): mes DESCONOCIDO.
      p_desconocido := true;
      return;
    end if;
  end if;

  -- e) El mes resuelto, venga de donde venga, tiene que ser un PRIMER DÍA DE MES y nunca nulo. Lo garantiza el esquema (en
  --    `conversion_acreditaciones`: NOT NULL de `fecha_comercial` y de `periodo_comercial` más el CHECK
  --    `periodo_comercial = date_trunc('month', fecha_comercial)::date`; el preflight exige los tres) y aquí se vuelve a
  --    exigir: un mes nulo o no canónico no casaría con el sello y se leería «abierto». Es un error de integridad, NUNCA «abierto».
  if p_mes is null or p_mes <> pg_catalog.date_trunc('month', p_mes::timestamp)::date then
    raise exception 'Integridad: el mes de la venta % (lead %) no es un primer día de mes', coalesce(p_mes::text, 'NULL'), p_lead_id;
  end if;

  -- EL CERROJO, antes de mirar si el mes está sellado: el mismo que toma `crm.cerrar_periodo`.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (p_mes - date '2000-01-01')::integer);

  if v_acreditacion.id is not null then
    select * into v_acreditacion_actual
    from crm.conversion_acreditaciones ca
    where ca.lead_id = p_lead_id;
    if v_acreditacion_actual is distinct from v_acreditacion then
      raise exception 'La acreditacion cambio durante la anulacion; vuelve a intentar' using errcode = 'PT409';
    end if;
  end if;

  p_sellado := exists (select 1 from crm.periodos_cerrados pc where pc.periodo = p_mes);
  return;
end;
$func$;

revoke all on function private.mes_sellado_de_venta(uuid) from public, anon, authenticated, service_role;

comment on function private.mes_sellado_de_venta(uuid) is
  'Dada una venta (lead), dice el mes de la venta (p_mes), si ese mes tiene fila en crm.periodos_cerrados (p_sellado) y si el mes no se pudo determinar (p_desconocido). Mes de la venta (politica propia, mas estricta que la de registrar_ajuste_si_mes_cerrado, que volvia antes): con la politica de septiembre activa y la venta convertida desde el 01/09, el periodo_comercial de su acreditacion (UNIQUE lead_id); si no, el episodio de cierre del ledger (mas de uno: error de integridad, como registrar_ajuste_si_mes_cerrado); si no, el mes de leads.convertido_en en hora de Lima; si tampoco, desconocido (decidido al final). Un mes nulo o que no sea primer dia de mes es error de integridad (P0001), nunca abierto. Toma el cerrojo del mes (el de crm.cerrar_periodo) ANTES de mirar periodos_cerrados. Solo READ COMMITTED (0A000 en otro modo; 20261002163158). SECURITY INVOKER: solo la usan crm.anular_cierre_avance y crm.anular_cierre_externo (DEFINER, corre como su dueno); sin EXECUTE para ningun otro rol. Plan AVANCE-BACKEND-0610, bloque 2.6.';

-- ── Las dos puertas, por anclas únicas ──────────────────────────────────────────────────────────────────────────
do $reemplazo$
declare
  v_def    text;
  v_anclas text[];
  v_nuevos text[];
  v_i      integer;
  v_veces  integer;
begin
  -- ===== crm.anular_cierre_avance ==========================================================================
  v_def := pg_get_functiondef('crm.anular_cierre_avance(uuid,text)'::regprocedure);
  v_anclas := array[
    -- 1. variables
    $a1$  v_ajuste uuid;
begin
$a1$,
    -- 2. la guarda, después de «ya estaba anulado» y antes de escribir nada
    $a2$  -- Los contratos afectados se calculan ANTES de insertar la anulacion: despues,
$a2$,
    -- 3. se acaba el ajuste
    $a3$  -- Si el mes de ese cierre YA ESTA CERRADO, el mes no se reescribe: nace la
  -- deuda que el vendedor arrastrara al mes vivo hasta saldarla.
  v_ajuste := private.registrar_ajuste_si_mes_cerrado(p_lead_id, v_motivo, v_uid);
$a3$,
    -- 4. el rastro del exento en los metadatos de la actividad
    $a4$        'contrato_id', v_lead.contrato_id)
    ),
$a4$];
  v_nuevos := array[
    $n1$  v_ajuste uuid;
  v_mes_sellado date;
  v_sellado boolean := false;
  v_desconocido boolean := false;
  v_excepcion boolean := false;
  v_excepcion_marca text;
begin
$n1$,
    $n2$  -- MES SELLADO (plan AVANCE-BACKEND-0610, bloque 2.6; D-09, D-14, D-17): un mes sellado no se reescribe.
  -- Se pregunta ANTES de escribir nada y DESPUES de «ya estaba anulado». El detector distingue mes sellado, mes no
  -- sellado y mes DESCONOCIDO (sin acreditacion, sin episodio y sin fecha de conversion): desconocido falla cerrado,
  -- como sellado. Solo pasa quien es a la vez admin del Portal y Gerencia del CRM (excepcion D-17), y entonces la
  -- anulacion NO crea ajuste y deja rastro abajo (excepcion_mes_sellado = AAAA-MM, o 'desconocido').
  select d.p_mes, d.p_sellado, d.p_desconocido
    into v_mes_sellado, v_sellado, v_desconocido
    from private.mes_sellado_de_venta(p_lead_id) d;
  if v_desconocido or v_sellado then
    if public.es_admin() and private.es_gerencia_crm_activa() then
      v_excepcion := true;
      v_excepcion_marca := case when v_desconocido then 'desconocido'
                                else pg_catalog.to_char(v_mes_sellado, 'YYYY-MM') end;
    elsif v_desconocido then
      raise exception using
        errcode = 'P0409',
        message = 'No se puede anular: no se puede determinar el mes de esta venta',
        hint    = 'Un mes sellado no se reescribe. La corrección se hace por otra vía, fuera del sistema.';
    else
      raise exception using
        errcode = 'P0409',
        message = pg_catalog.format('No se puede anular: el mes de esta venta (%s) ya está sellado',
                                    pg_catalog.to_char(v_mes_sellado, 'YYYY-MM')),
        hint    = 'Un mes sellado no se reescribe. La corrección se hace por otra vía, fuera del sistema.';
    end if;
  end if;

  -- Los contratos afectados se calculan ANTES de insertar la anulacion: despues,
$n2$,
    $n3$  -- (2.6) Ya no nace deuda: un mes sellado (o desconocido) rechaza la anulacion mas arriba y solo el exento llega
  -- aqui con el, sin ajuste. `v_ajuste` queda nulo a proposito: `mes_cerrado` y `ajuste_id` conservan su forma; el
  -- rastro fiable del exento son las claves excepcion_* de la actividad, no `mes_cerrado`.
$n3$,
    $n4$        'contrato_id', v_lead.contrato_id)
    ) || case when v_excepcion then pg_catalog.jsonb_build_object(
           'excepcion_mes_sellado', v_excepcion_marca,
           'excepcion_por', v_uid,
           'excepcion_en', pg_catalog.now())
         else '{}'::jsonb end,
$n4$];
  for v_i in 1..cardinality(v_anclas) loop
    v_veces := (length(v_def) - length(replace(v_def, v_anclas[v_i], ''))) / length(v_anclas[v_i]);
    if v_veces <> 1 then
      raise exception 'anular_venta_mes_sellado: el ancla % de crm.anular_cierre_avance aparece % veces (debe ser 1)', v_i, v_veces;
    end if;
    v_def := replace(v_def, v_anclas[v_i], v_nuevos[v_i]);
  end loop;
  execute v_def;

  -- ===== crm.anular_cierre_externo =========================================================================
  v_def := pg_get_functiondef('crm.anular_cierre_externo(uuid,text)'::regprocedure);
  v_anclas := array[
    $b1$  v_ajuste uuid;
begin
$b1$,
    $b2$  perform set_config('crm.op_privilegiada', 'on', true);
$b2$,
    $b3$  -- Si el mes de ese cierre YA ESTA CERRADO, el mes no se reescribe: nace la
  -- deuda que el vendedor arrastrara al mes vivo.
  if v_cierre.es_cierre_inicial then
    v_ajuste := private.registrar_ajuste_si_mes_cerrado(v_cierre.lead_id, v_motivo, v_uid);
  end if;
$b3$,
    $b4$        'vendedor_id', v_cierre.vendedor_id)
    ),
$b4$];
  v_nuevos := array[
    $m1$  v_ajuste uuid;
  v_mes_sellado date;
  v_sellado boolean := false;
  v_desconocido boolean := false;
  v_excepcion boolean := false;
  v_excepcion_marca text;
begin
$m1$,
    $m2$  -- MES SELLADO (plan AVANCE-BACKEND-0610, bloque 2.6; D-09, D-14, D-17): un mes sellado no se reescribe.
  -- Solo la CONVERSION (cierre inicial): renovacion, upgrade y reinversion no entran (D-14). Se pregunta ANTES de
  -- escribir nada y DESPUES de «ya estaba anulado». El detector distingue mes sellado, mes no sellado y mes
  -- DESCONOCIDO (sin acreditacion, sin episodio y sin fecha de conversion): desconocido falla cerrado, como sellado.
  -- Solo pasa quien es a la vez admin del Portal y Gerencia del CRM (excepcion D-17), y entonces la anulacion NO crea
  -- ajuste y deja rastro abajo (excepcion_mes_sellado = AAAA-MM, o 'desconocido').
  if v_cierre.es_cierre_inicial then
    select d.p_mes, d.p_sellado, d.p_desconocido
      into v_mes_sellado, v_sellado, v_desconocido
      from private.mes_sellado_de_venta(v_cierre.lead_id) d;
    if v_desconocido or v_sellado then
      if public.es_admin() and private.es_gerencia_crm_activa() then
        v_excepcion := true;
        v_excepcion_marca := case when v_desconocido then 'desconocido'
                                  else pg_catalog.to_char(v_mes_sellado, 'YYYY-MM') end;
      elsif v_desconocido then
        raise exception using
          errcode = 'P0409',
          message = 'No se puede anular: no se puede determinar el mes de esta venta',
          hint    = 'Un mes sellado no se reescribe. La corrección se hace por otra vía, fuera del sistema.';
      else
        raise exception using
          errcode = 'P0409',
          message = pg_catalog.format('No se puede anular: el mes de esta venta (%s) ya está sellado',
                                      pg_catalog.to_char(v_mes_sellado, 'YYYY-MM')),
          hint    = 'Un mes sellado no se reescribe. La corrección se hace por otra vía, fuera del sistema.';
      end if;
    end if;
  end if;

  perform set_config('crm.op_privilegiada', 'on', true);
$m2$,
    $m3$  -- (2.6) Ya no nace deuda: un mes sellado (o desconocido) rechaza la anulacion mas arriba y solo el exento llega
  -- aqui con el, sin ajuste. `v_ajuste` queda nulo a proposito: `mes_cerrado` y `ajuste_id` conservan su forma; el
  -- rastro fiable del exento son las claves excepcion_* de la actividad, no `mes_cerrado`.
$m3$,
    $m4$        'vendedor_id', v_cierre.vendedor_id)
    ) || case when v_excepcion then pg_catalog.jsonb_build_object(
           'excepcion_mes_sellado', v_excepcion_marca,
           'excepcion_por', v_uid,
           'excepcion_en', pg_catalog.now())
         else '{}'::jsonb end,
$m4$];
  for v_i in 1..cardinality(v_anclas) loop
    v_veces := (length(v_def) - length(replace(v_def, v_anclas[v_i], ''))) / length(v_anclas[v_i]);
    if v_veces <> 1 then
      raise exception 'anular_venta_mes_sellado: el ancla % de crm.anular_cierre_externo aparece % veces (debe ser 1)', v_i, v_veces;
    end if;
    v_def := replace(v_def, v_anclas[v_i], v_nuevos[v_i]);
  end loop;
  execute v_def;
end
$reemplazo$;

comment on function crm.anular_cierre_avance(uuid, text) is
  'Anula un cierre de Avance (error de gestion o mala practica), SOLO gerencia y con motivo obligatorio. El cierre deja de acreditarle al vendedor en la CUOTA y en la CONVERSION a la vez. NO mueve dinero real: el contrato y el cliente siguen intactos en public. El lead NO se reabre (un convertido es terminal por diseno) y el episodio del ledger no se toca (es inmutable). De una sola direccion: no se des-anula. Deja actividad tipo nota con el motivo. UN MES SELLADO NO SE REESCRIBE (bloque 2.6): si el mes de la venta tiene fila en crm.periodos_cerrados, o no se puede determinar, rechaza con P0409 y no escribe nada, salvo para quien es admin del Portal Y Gerencia del CRM, que anula SIN ajuste y deja en la actividad excepcion_mes_sellado (AAAA-MM o desconocido), excepcion_por y excepcion_en; mes_cerrado queda en false por compatibilidad y no es el rastro.';
comment on function crm.anular_cierre_externo(uuid, text) is
  'Anula un cierre en cooperativa (fraude o error), SOLO gerencia y con motivo obligatorio. El cierre deja de contar en la cuota Y en la conversion mensual; la fila NO se borra (es el ancla de legalidad del lead convertido) y el lead NO se reabre (un convertido es terminal por diseno). Es de una sola direccion: no se des-anula. Deja actividad tipo nota con el motivo y la foto de lo anulado. UN MES SELLADO NO SE REESCRIBE (bloque 2.6): si es el cierre inicial y el mes de la venta tiene fila en crm.periodos_cerrados, o no se puede determinar, rechaza con P0409 y no escribe nada, salvo para quien es admin del Portal Y Gerencia del CRM, que anula SIN ajuste y deja en la actividad excepcion_mes_sellado (AAAA-MM o desconocido), excepcion_por y excepcion_en; mes_cerrado queda en false por compatibilidad y no es el rastro. Los cierres no iniciales no cambian.';

-- ── Postflight ───────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_h      record;
  v_ficha  text;
  v_pa     text;
  v_pe     text;
begin
  -- La guarda quedó en AMBAS puertas, y ninguna llama ya a registrar_ajuste_si_mes_cerrado.
  if (select position('private.mes_sellado_de_venta(p_lead_id)' in p.prosrc) = 0
             or position('registrar_ajuste_si_mes_cerrado' in p.prosrc) > 0
             or position('P0409' in p.prosrc) = 0
             or position('no se puede determinar el mes' in p.prosrc) = 0
        from pg_proc p where p.oid = 'crm.anular_cierre_avance(uuid,text)'::regprocedure)
     or (select position('private.mes_sellado_de_venta(v_cierre.lead_id)' in p.prosrc) = 0
                or position('registrar_ajuste_si_mes_cerrado' in p.prosrc) > 0
                or position('v_cierre.es_cierre_inicial then' in p.prosrc) = 0
                or position('P0409' in p.prosrc) = 0
                or position('no se puede determinar el mes' in p.prosrc) = 0
           from pg_proc p where p.oid = 'crm.anular_cierre_externo(uuid,text)'::regprocedure) then
    raise exception 'POSTFLIGHT anular_venta_mes_sellado: la guarda no quedó en las dos puertas';
  end if;
  -- Los cuerpos nuevos son los que se ensayaron (huella exacta). El mensaje enseña las medidas para poder fijarlas.
  select md5(p.prosrc) into v_pa from pg_proc p where p.oid = 'crm.anular_cierre_avance(uuid,text)'::regprocedure;
  select md5(p.prosrc) into v_pe from pg_proc p where p.oid = 'crm.anular_cierre_externo(uuid,text)'::regprocedure;
  if v_pa is distinct from '1bb2bfd1cef0d1a0dc201c698f6ae120'
     or v_pe is distinct from '4b01f805b24e0b95a8dd49c7cbef8409' then
    raise exception 'POSTFLIGHT anular_venta_mes_sellado: el cuerpo de una puerta no es el ensayado (medidos: avance %, externo %)', v_pa, v_pe;
  end if;
  -- Dueño, ACL y atributos de las puertas, intactos.
  if (select string_agg(p.oid::regprocedure::text || '|' || p.proowner::regrole::text || '|' || p.prosecdef::text
        || '|' || coalesce(p.proconfig::text, '-') || '|' || coalesce(p.proacl::text, '-')
        || '|' || p.provolatile::text || '|' || p.proparallel::text || '|' || p.proleakproof::text
        || '|' || p.prorettype::regtype::text, ';' order by p.oid::regprocedure::text)
       from pg_proc p
      where p.oid in ('crm.anular_cierre_avance(uuid,text)'::regprocedure,
                      'crm.anular_cierre_externo(uuid,text)'::regprocedure))
     is distinct from current_setting('crm.anular_mes_sellado_ficha_previa', true) then
    raise exception 'POSTFLIGHT anular_venta_mes_sellado: cambió el dueño, la ACL o un atributo de una puerta';
  end if;
  -- El detector existe con su ficha: dueño postgres, SECURITY INVOKER, search_path vacío, volátil (toma un cerrojo),
  -- devuelve record (tres OUT) y NINGÚN rol con EXECUTE salvo el dueño (ni authenticated, ni anon, ni service_role).
  if not exists (
       select 1 from pg_proc p
       where p.oid = to_regprocedure('private.mes_sellado_de_venta(uuid)')
         and p.proowner = 'postgres'::regrole::oid
         and not p.prosecdef
         and p.provolatile = 'v'
         and p.prorettype = 'record'::regtype
         and p.proconfig = array['search_path=""'])
     or exists (
       select 1 from pg_proc p
       cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
       where p.oid = to_regprocedure('private.mes_sellado_de_venta(uuid)')
         and a.grantee <> 'postgres'::regrole::oid)
     or has_function_privilege('authenticated', 'private.mes_sellado_de_venta(uuid)'::regprocedure, 'EXECUTE')
     or has_function_privilege('anon', 'private.mes_sellado_de_venta(uuid)'::regprocedure, 'EXECUTE')
     or has_function_privilege('service_role', 'private.mes_sellado_de_venta(uuid)'::regprocedure, 'EXECUTE') then
    raise exception 'POSTFLIGHT anular_venta_mes_sellado: el detector no existe o no tiene la ficha esperada (dueño postgres, SECURITY INVOKER, search_path vacío, volátil, record, sin EXECUTE a nadie)';
  end if;
  -- Y el detector es, byte a byte, el ensayado (las mismas huellas que exige la reversa antes de borrarlo). El mensaje
  -- enseña las medidas para poder fijarlas si el cuerpo cambia a propósito.
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)) into v_pa, v_pe
    from pg_proc p where p.oid = 'private.mes_sellado_de_venta(uuid)'::regprocedure;
  if v_pa is distinct from '8e22b2d65bb35be0551c190cfcf28e75'
     or v_pe is distinct from 'ba2cfaaa3337a05a6cd7c32cd6af8e8c' then
    raise exception 'POSTFLIGHT anular_venta_mes_sellado: el detector no es el ensayado (medidos: prosrc %, definición %)', v_pa, v_pe;
  end if;
  -- Lo que NO se toca, intacto: el ajuste (declarado en el vigía analítico), el saldo, el sello y la excepción.
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'::regprocedure)
       is distinct from 'fec614f0df11c6d411bf132c776cce6e'
     or (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'::regprocedure)
       is distinct from '3af3eb46396edfc550b1fb040245f1aa'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'private.saldar_ajustes(uuid,numeric,numeric,numeric)'::regprocedure)
       is distinct from '791a53a154348be349887c07a82a6414'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.cerrar_periodo(date)'::regprocedure)
       is distinct from '79840e5af7ef355126fcc11dfd461ff1'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'public.es_admin()'::regprocedure)
       is distinct from 'f4e01285f0b006f72b984213a6a95310'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'private.es_gerencia_crm_activa()'::regprocedure)
       is distinct from 'e2e84b58044078e40e506f623985e86d'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'private.rol_crm(uuid)'::regprocedure)
       is distinct from 'd2878a210be96ac85973d51dfcfb27a5'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'private.conversion_episodios(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric)'::regprocedure)
       is distinct from '125b4046f513657ac57ec676a0d52e87'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'private.conversion_cierres(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric,uuid[])'::regprocedure)
       is distinct from '155ce2b12754718388c8ca1644c84c90' then
    raise exception 'POSTFLIGHT anular_venta_mes_sellado: cambió algo que esta migración no debía tocar (registrar_ajuste, saldar_ajustes, cerrar_periodo, es_admin, es_gerencia_crm_activa, rol_crm, conversion_episodios o conversion_cierres)';
  end if;
  -- Y la ficha completa de los tres helpers de la excepción sigue siendo la auditada.
  for v_h in
    select * from (values
      ('public.es_admin()',
       'postgres|true|s|u|search_path=public, pg_temp|authenticated:EXECUTE:false,postgres:EXECUTE:false,service_role:EXECUTE:false'),
      ('private.es_gerencia_crm_activa()',
       'postgres|true|s|u|search_path=""|postgres:EXECUTE:false'),
      ('private.rol_crm(uuid)',
       'postgres|true|s|u|search_path=""|authenticated:EXECUTE:false,postgres:EXECUTE:false')
    ) as h(firma, ficha)
  loop
    select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || p.proparallel::text
             || '|' || coalesce(array_to_string(p.proconfig, ';'), '-')
             || '|' || coalesce((select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text)
                                   from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a), '-')
      into v_ficha
      from pg_proc p
     where p.oid = to_regprocedure(v_h.firma);
    if v_ficha is distinct from v_h.ficha then
      raise exception 'POSTFLIGHT anular_venta_mes_sellado: la ficha de % cambió durante la migración (medida «%»)', v_h.firma, coalesce(v_ficha, 'no existe');
    end if;
  end loop;
end
$postflight$;

commit;
$mig$::text as contenido;
create temp table registro_20261009210000_condiciones on commit drop as
select c.orden, c.condicion, c.cumple from (values
  (1, 'crm.anular_cierre_avance: cuerpo, md5(prosrc) 1bb2bfd1… (postflight)',
   (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.anular_cierre_avance(uuid,text)')) = '1bb2bfd1cef0d1a0dc201c698f6ae120'),
  (2, 'crm.anular_cierre_avance: definición entera, md5(pg_get_functiondef) 03b67308… (la que deja; reversa)',
   (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = to_regprocedure('crm.anular_cierre_avance(uuid,text)')) = '03b673084dbbbbff7aef21c12e7f30b5'),
  (3, 'crm.anular_cierre_avance: ficha (dueño postgres, security definer, search_path vacío)',
   (select p.proowner = 'postgres'::regrole::oid and p.prosecdef and p.proconfig = array['search_path=""']
       from pg_proc p where p.oid = to_regprocedure('crm.anular_cierre_avance(uuid,text)'))),
  (4, 'crm.anular_cierre_avance: ACL efectiva (EXECUTE solo authenticated y el dueño, sin opción de concesión)',
   (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
       from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = to_regprocedure('crm.anular_cierre_avance(uuid,text)')) = array['authenticated:EXECUTE:false', 'postgres:EXECUTE:false']),
  (5, 'crm.anular_cierre_avance: comentario (el que fija la migración)',
   obj_description(to_regprocedure('crm.anular_cierre_avance(uuid,text)'), 'pg_proc') = 'Anula un cierre de Avance (error de gestion o mala practica), SOLO gerencia y con motivo obligatorio. El cierre deja de acreditarle al vendedor en la CUOTA y en la CONVERSION a la vez. NO mueve dinero real: el contrato y el cliente siguen intactos en public. El lead NO se reabre (un convertido es terminal por diseno) y el episodio del ledger no se toca (es inmutable). De una sola direccion: no se des-anula. Deja actividad tipo nota con el motivo. UN MES SELLADO NO SE REESCRIBE (bloque 2.6): si el mes de la venta tiene fila en crm.periodos_cerrados, o no se puede determinar, rechaza con P0409 y no escribe nada, salvo para quien es admin del Portal Y Gerencia del CRM, que anula SIN ajuste y deja en la actividad excepcion_mes_sellado (AAAA-MM o desconocido), excepcion_por y excepcion_en; mes_cerrado queda en false por compatibilidad y no es el rastro.'),
  (6, 'crm.anular_cierre_externo: cuerpo, md5(prosrc) 4b01f805… (postflight)',
   (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.anular_cierre_externo(uuid,text)')) = '4b01f805b24e0b95a8dd49c7cbef8409'),
  (7, 'crm.anular_cierre_externo: definición entera, md5(pg_get_functiondef) 906372fe… (la que deja; reversa)',
   (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = to_regprocedure('crm.anular_cierre_externo(uuid,text)')) = '906372fe41ed37a2892e181bf8b9663f'),
  (8, 'crm.anular_cierre_externo: ficha (dueño postgres, security definer, search_path vacío)',
   (select p.proowner = 'postgres'::regrole::oid and p.prosecdef and p.proconfig = array['search_path=""']
       from pg_proc p where p.oid = to_regprocedure('crm.anular_cierre_externo(uuid,text)'))),
  (9, 'crm.anular_cierre_externo: ACL efectiva (EXECUTE solo authenticated y el dueño, sin opción de concesión)',
   (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
       from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = to_regprocedure('crm.anular_cierre_externo(uuid,text)')) = array['authenticated:EXECUTE:false', 'postgres:EXECUTE:false']),
  (10, 'crm.anular_cierre_externo: comentario (el que fija la migración)',
   obj_description(to_regprocedure('crm.anular_cierre_externo(uuid,text)'), 'pg_proc') = 'Anula un cierre en cooperativa (fraude o error), SOLO gerencia y con motivo obligatorio. El cierre deja de contar en la cuota Y en la conversion mensual; la fila NO se borra (es el ancla de legalidad del lead convertido) y el lead NO se reabre (un convertido es terminal por diseno). Es de una sola direccion: no se des-anula. Deja actividad tipo nota con el motivo y la foto de lo anulado. UN MES SELLADO NO SE REESCRIBE (bloque 2.6): si es el cierre inicial y el mes de la venta tiene fila en crm.periodos_cerrados, o no se puede determinar, rechaza con P0409 y no escribe nada, salvo para quien es admin del Portal Y Gerencia del CRM, que anula SIN ajuste y deja en la actividad excepcion_mes_sellado (AAAA-MM o desconocido), excepcion_por y excepcion_en; mes_cerrado queda en false por compatibilidad y no es el rastro. Los cierres no iniciales no cambian.'),
  (11, 'private.mes_sellado_de_venta: cuerpo, md5(prosrc) 8e22b2d6… (postflight)',
   (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.mes_sellado_de_venta(uuid)')) = '8e22b2d65bb35be0551c190cfcf28e75'),
  (12, 'private.mes_sellado_de_venta: definición entera, md5(pg_get_functiondef) ba2cfaaa… (postflight)',
   (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = to_regprocedure('private.mes_sellado_de_venta(uuid)')) = 'ba2cfaaa3337a05a6cd7c32cd6af8e8c'),
  (13, 'private.mes_sellado_de_venta: ficha (dueño postgres, SECURITY INVOKER, volátil, record, search_path vacío)',
   (select p.proowner = 'postgres'::regrole::oid and not p.prosecdef and p.provolatile = 'v'
         and p.prorettype = 'record'::regtype and p.proconfig = array['search_path=""']
       from pg_proc p where p.oid = to_regprocedure('private.mes_sellado_de_venta(uuid)'))),
  (14, 'private.mes_sellado_de_venta: ACL efectiva (nadie salvo el dueño; ni authenticated, ni anon, ni service_role)',
   (select not exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                     where a.grantee <> 'postgres'::regrole::oid)
         and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
         and not has_function_privilege('anon', p.oid, 'EXECUTE')
         and not has_function_privilege('service_role', p.oid, 'EXECUTE')
       from pg_proc p where p.oid = to_regprocedure('private.mes_sellado_de_venta(uuid)'))),
  (15, 'private.mes_sellado_de_venta: comentario (el que fija la migración)',
   obj_description(to_regprocedure('private.mes_sellado_de_venta(uuid)'), 'pg_proc') = 'Dada una venta (lead), dice el mes de la venta (p_mes), si ese mes tiene fila en crm.periodos_cerrados (p_sellado) y si el mes no se pudo determinar (p_desconocido). Mes de la venta (politica propia, mas estricta que la de registrar_ajuste_si_mes_cerrado, que volvia antes): con la politica de septiembre activa y la venta convertida desde el 01/09, el periodo_comercial de su acreditacion (UNIQUE lead_id); si no, el episodio de cierre del ledger (mas de uno: error de integridad, como registrar_ajuste_si_mes_cerrado); si no, el mes de leads.convertido_en en hora de Lima; si tampoco, desconocido (decidido al final). Un mes nulo o que no sea primer dia de mes es error de integridad (P0001), nunca abierto. Toma el cerrojo del mes (el de crm.cerrar_periodo) ANTES de mirar periodos_cerrados. Solo READ COMMITTED (0A000 en otro modo; 20261002163158). SECURITY INVOKER: solo la usan crm.anular_cierre_avance y crm.anular_cierre_externo (DEFINER, corre como su dueno); sin EXECUTE para ningun otro rol. Plan AVANCE-BACKEND-0610, bloque 2.6.'),
  (16, 'ledger: private.conversion_episodios, md5(prosrc) 125b4046… (preflight; F4.2-bis)',
   (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.conversion_episodios(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric)')) = '125b4046f513657ac57ec676a0d52e87'),
  (17, 'ledger: private.conversion_cierres, md5(prosrc) 155ce2b1… (preflight)',
   (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.conversion_cierres(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric,uuid[])')) = '155ce2b12754718388c8ca1644c84c90')
) as c(orden, condicion, cumple);
do $chk$
declare
  v_md5    text;
  v_fallan text;
  v_otras  text;
begin
  select md5(r.contenido) into v_md5 from pg_temp.registro_20261009210000 r;
  if v_md5 is distinct from '49271955876c0320b9fa4d202e547773' then
    raise exception 'REGISTRO: el archivo incrustado no es el de la migración (md5 %, esperado 49271955876c0320b9fa4d202e547773)', v_md5;
  end if;
  select string_agg(c.orden || '. ' || c.condicion, '; ' order by c.orden) into v_fallan
    from pg_temp.registro_20261009210000_condiciones c where c.cumple is not true;
  if v_fallan is not null then
    raise exception 'REGISTRO: la migración 20261009210000 no está aplicada o su estado no es el que deja (no se cumple: %); no se registra', v_fallan;
  end if;
  select string_agg(s.version, ', ' order by s.version) into v_otras
    from supabase_migrations.schema_migrations s where s.name = 'crm_anular_venta_mes_sellado' and s.version <> '20261009210000';
  if v_otras is not null then
    raise exception 'REGISTRO: el nombre crm_anular_venta_mes_sellado ya está registrado con otra versión (%): no se registra dos veces la misma migración', v_otras;
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations s cross join pg_temp.registro_20261009210000 r
             where s.version = '20261009210000' and (coalesce(s.name, '') <> 'crm_anular_venta_mes_sellado' or s.statements is distinct from array[r.contenido])) then
    raise exception 'REGISTRO: la versión 20261009210000 ya está registrada con otro nombre u otro contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
select '20261009210000', 'crm_anular_venta_mes_sellado', array[r.contenido] from pg_temp.registro_20261009210000 r
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261009210000' and name = 'crm_anular_venta_mes_sellado' and cardinality(statements) = 1
                   and md5(statements[1]) = '49271955876c0320b9fa4d202e547773') then
    raise exception 'REGISTRO: la fila 20261009210000 / crm_anular_venta_mes_sellado no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261009210000 / crm_anular_venta_mes_sellado (1 sentencia: el archivo entero)';
end $post$;
commit;
-- Última fila, tras el COMMIT, para que `db query` muestre algo.
select '20261009210000' as version_registrada, '49271955876c0320b9fa4d202e547773' as md5_del_archivo;

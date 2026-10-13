-- REGISTRO en supabase_migrations.schema_migrations de 20261013145852_crm_realizacion_cuenta_anticipada (bloque 2.2, grupo B).
-- GENERADO por generar_registrador.py: no editar a mano. `db query --linked --file` NO registra: correr DESPUÉS de aplicar la
-- migración, por la misma vía. Desde `CRM-Avance-Corp/`, en este orden (el Director lo ensaya antes en la branch):
--   1. supabase db query --linked --file supabase/migrations/20261013145852_crm_realizacion_cuenta_anticipada.sql
--   2. supabase db query --linked --file supabase/scripts/metricas-reuniones-realizacion/registrar/20261013145852.sql
-- Por `db query --linked` no llegan los NOTICE; llega la última fila (va tras el COMMIT):
-- registrado = sin error y la fila «20261013145852 | d6f56ed226f3835daad75309eca137fc».
-- Un error = no registró nada (todo va en una transacción).
-- Idempotente (correrlo dos veces deja una sola fila). Se NIEGA, sin escribir nada, si:
--   · el estado instalado no es el que deja la migración: de private.metricas_reuniones_implementacion(date,date), cuerpo
--     (ca6fe61e76bcb8bf2d213acb1b7fc030), definición entera (ce852e3740f60a57938e2baf2c0b736d), ficha, ACL efectiva y comentario; la huella
--     re-sellada de su exención (d54d4f8773cf1106dadbcb0d793575e2); el sello de la lista; el censo analítico;
--   · el nombre crm_realizacion_cuenta_anticipada ya está registrado con OTRA versión (p. ej. 20261007205643, su fecha antigua);
--   · la versión 20261013145852 ya está registrada con otro nombre u otro contenido.
-- statements = el archivo entero (md5 d6f56ed226f3835daad75309eca137fc),
-- incrustado UNA sola vez en la tabla temporal pg_temp.registro_20261013145852 (on commit drop).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_realizacion_cuenta_anticipada_registro'));
create temp table registro_20261013145852 on commit drop as
select $mig$-- «REALIZACIÓN» CUENTA LA CITA REALIZADA DESDE QUE SE MARCA — una cita marcada como realizada ANTES de su hora pactada
-- entra al numerador Y al divisor del indicador «Realización» de Gerencia (pantalla «Citas del equipo» y Resumen de
-- Gerencia) desde el momento en que se marca: «1 de 3» pasa a «1 de 4».
--
-- QUÉ PASABA. `private.metricas_reuniones_implementacion(date,date)` (definición vigente `20260907194622…:27-354`) toma
-- las banderas del núcleo `private.citas_episodios` y cuenta `realizadas = count(*) filter (where metrica_realizada)` sin
-- condición de hora, pero `debieron_ocurrir = count(*) filter (where metrica_debio_ocurrir)` con
-- `metrica_debio_ocurrir = ce.debio_ocurrir` (= hora pactada ya vencida). El divisor
-- (`debieron_ocurrir − canceladas_sistema_vencidas − reprogramadas_vencidas`) y el numerador medían poblaciones distintas:
-- la realizada anticipada contaba arriba y no abajo hasta su hora. La pantalla mostraba «1 de 3 · 33,3 %» cuando ninguna de
-- las 3 computables se había realizado; con un analista cuya única cita del día fue anticipada, `realizadas=1` y
-- `divisor=0`, y la validación de la app (`metricas-reuniones.ts:70,112,138`, `realizadas <= divisor`) rechazaba el
-- payload entero. Medido en el banco (caso R5b, `fase-1-clasificacion/salidas/D-reuniones.md:70-97`).
--
-- QUÉ HACE. Re-emite la función con el cuerpo vigente y UN SOLO cambio, en la CTE `base`:
--     ce.debio_ocurrir as metrica_debio_ocurrir   ⇒   (ce.debio_ocurrir or ce.realizada) as metrica_debio_ocurrir
--   · El divisor del resumen, el de cada modalidad, el de cada origen y el de cada responsable se ajustan solos (todos
--     cuentan `metrica_debio_ocurrir`). `canceladas_sistema_vencidas` y `reprogramadas_vencidas` no cambian: una cita
--     realizada no es cancelada ni reprogramada.
--   · La cita pertenece al mes de su hora pactada (la ventana filtra por `vence_en`, como antes). Los periodos ya pasados
--     dan EXACTAMENTE lo mismo: toda cita pasada tiene la hora vencida (`p_hasta <= hoy`).
--   · El resto del cuerpo es, byte a byte, el vigente; firma, dueño `postgres`, `security definer`, `STABLE`,
--     `search_path` vacío y ACL (EXECUTE solo para el dueño) no cambian.
--
-- QUÉ NO CAMBIA (D-13). La bandera `debio_ocurrir` del núcleo `private.citas_episodios` (`20260912151320…:69-97`): la leen
-- los informes de conversiones («cita real» = `ce.realizada and ce.debio_ocurrir`, `private.metricas_conversiones_implementacion`
-- y los orígenes ponderados), que siguen contando la cita real desde su hora. Tampoco la puerta
-- `crm.metricas_reuniones_fn`, ni cancelaciones ni reprogramaciones: las canceladas por el asesor ya vencidas siguen DENTRO
-- del divisor como hoy; las del sistema y las reprogramadas vencidas siguen restándose; las futuras no realizadas siguen
-- fuera. La excepción del admin (D-17) no aplica: es una métrica, no depende del usuario. No se tocan tablas, grants,
-- policies ni objetos de `public`. No corrige datos.
--
-- RE-SELLADO DE LA HUELLA. La función está declarada en `private.analitica_leads_citas_exenciones` con su huella
-- NORMALIZADA (`md5` del cuerpo en minúsculas sin comentarios, la expresión de `private.contadores_crudos_leads_citas`) y la
-- lista está sellada en `private.analitica_lc_sello`. Un `create or replace` sin re-sellar rompe
-- `private.assert_analitica_leads_citas()` («Contadores exentos cuyo cuerpo CAMBIO…»). Esta migración, en la misma
-- transacción y con la plantilla de `20260908020020`: fija la huella previa (`4b28cc41…`), actualiza `huella` en la
-- exención a la del cuerpo nuevo (`d54d4f87…`, calculada sobre el cuerpo vivo y comparada con la revisada) y re-sella con
-- `private.huella_exenciones_analitica_lc()`. No toca razón, clase ni tope.
--
-- FAIL-CLOSED. El preflight exige, antes de reemplazar: `md5(prosrc)` 6880150b… y `md5(pg_get_functiondef)` cec7ee9e… de la
-- función (si ya es ca6fe61e…, la migración ya está aplicada y se niega); su ficha (dueño `postgres`, DEFINER, STABLE,
-- `search_path` vacío, EXECUTE solo para el dueño) y su comentario; la exención tal como se revisó (tipo `funcion`, clase
-- `analitica`, huella 4b28cc41…, razón); que el sello previo coincida con la lista y que el censo reconozca la exención; y
-- las huellas de las fuentes de las que depende el cambio (`private.citas_episodios` de 3 y 4 argumentos,
-- `private.contadores_crudos_leads_citas`, `private.huella_exenciones_analitica_lc`, `crm.metricas_reuniones_fn`). El
-- postflight exige el cambio en el cuerpo (y solo él), `md5(prosrc)` ca6fe61e… y `md5(pg_get_functiondef)` ce852e37…, la
-- ficha idéntica a la previa, la exención con la huella nueva y lo demás intacto, el sello coincidente, el censo
-- reconociéndola, las fuentes intactas (y `private.metricas_conversiones_implementacion`, los informes de conversiones, con
-- su huella de producción 24fed436… desde el 12/10/2026; antes 14f45688…), el comentario nuevo y la FOTO de los `private.assert_*()` sin argumentos, SIN los
-- `*_mutantes` (F4.2: 30 de 36 en el laboratorio igual a producción; varios `*_mutantes` aplican sin guarda DDL de permisos
-- sobre tablas calientes y en la base real tomarían candados ACCESS EXCLUSIVE; el ensayo `--trinquetes` sigue barriendo los
-- 36), idéntica a la tomada en el preflight. La foto guarda, por cada gate, su estado (`pasa`) o, si cae, el SQLSTATE y el texto ÍNTEGRO
-- de su primer error (sin truncar); el postflight exige la igualdad exacta. Lo que eso garantiza, ni más ni menos: estado y
-- texto íntegro del primer error de cada gate, idénticos antes y después. NO acredita PASS de los gates que ya caían (en el
-- laboratorio `assert_analitica_leads_citas` cae desde antes por `private.gestion_diaria_cola_hechos` sin declarar, así
-- que ahí no puede demostrar que esta migración lo deje en «pasa»); la garantía fuerte sobre lo que esta migración toca
-- son las huellas de la función, el sello de la lista de exenciones y el censo analítico, exigidos aparte.
--
-- CONSECUENCIAS (para quien integre).
--   · Las huellas de `private.metricas_reuniones_implementacion` CAMBIAN (prosrc 6880150b…→ca6fe61e…, definición
--     cec7ee9e…→ce852e37…, normalizada 4b28cc41…→d54d4f87…). Las registran, y dejarían de valer después de esta migración:
--     `supabase/scripts/rollback-citas-gerencia-bases-y-alcance.sql:19` (revertidor histórico de `20260907194622`),
--     `supabase/scripts/citas-control-20260907/{correccion-propuesta.sql,README.md,*.json}` (control histórico ya aplicado
--     como `20260908020020`) y la propia `20260907194622…:368-369` (solo en su propia aplicación). NO se cambian aquí.
--   · La huella viva en producción tiene que leerse de la base antes de aplicar (fase 4): el preflight la exige igual a la
--     del laboratorio (corte `20261003162500`); si difiere, aborta sin tocar nada. F4.2 (09/10/2026): en el laboratorio
--     igual a producción la función, la exención (4b28cc41…), las fuentes y la puerta tienen las huellas de arriba; el sello
--     coincide con la lista (su valor, 5c0de3fa…, no es el de la fase 2 porque otras exenciones se re-sellaron en `main`; la
--     migración exige la coherencia, no un valor). F4.2-bis (09/10/2026, tarde): con 20261009200000 en producción, todo eso sigue
--     igual y el sello vale 3e1f7ca3… (esa migración re-selló la exención de `crm.cierres_externos_fn`). Vuelve a valer si
--     `main` o producción cambian antes de la branch.
--   · El banco de pruebas: R5b espera +4 y debería pasar sin tocar la prueba; el banco excluye todas las canceladas del
--     divisor y el producto conserva las canceladas por el asesor vencidas (D-13): lo ajusta el escritor del banco.
--   · Pantalla: solo texto («citas vencidas o ya realizadas», `reuniones-gerencia.tsx:96,175`); no hay cambio de
--     contrato ni de lógica.
--
-- A QUÉ PLAN RESPONDE. Plan de mantenibilidad del backend del CRM (AVANCE-BACKEND-0610), fase 2, bloque 2.2 (decisiones
-- D-11/Q2 y D-13 de Miguel, 2026-10-06; luz verde D-18, 2026-10-07). Fase 4, F4.2 (2026-10-09; D-24, D-26, D-33): reselle
-- contra el código de producción (verificado por el Director; Codex PASS). Fase 4, F4.2-bis (2026-10-09, tarde): producción
-- aplicó 20261009200000 (baja de analista); solo cambian dos huellas del oráculo y esta cabecera, tras la re-auditoría de abajo.
-- Pendiente de la verificación del Director y de la revisión de Codex.
--
-- RE-AUDITORÍA DEL GRUPO B (13/10/2026, fase 4; D-95). Producción aplicó el 12/10 `20261012223850_crm_coordinacion_reportes_lectura`
-- (Coordinación lee los reportes), que re-emite `private.metricas_conversiones_implementacion`: 14f45688… → 24fed436…. Comparado el
-- cuerpo entero (laboratorio = 14f45688… frente al de esa migración): la ÚNICA diferencia es la autorización, `… or
-- private.es_lector_global() or private.es_coordinador_reportes() into v_autorizado` (más una línea en blanco inicial); la «cita
-- real» (`ce.realizada and ce.debio_ocurrir`) y todo el cálculo, iguales: D-13 sigue en pie. Cambia SOLO esa huella del postflight
-- (y esta cabecera); las otras ocho que fija el preflight y la exención, leídas en producción, son las auditadas. Re-fechada para ir
-- después de `20261012223850` (antes `20261012184210`; y antes aún `20261007205643`).
--
-- RE-AUDITORÍA F4.2 (09/10/2026). En el laboratorio igual a producción el preflight entraba y el postflight se negaba
-- («cambió algo que esta migración no debía tocar…»): de lo que esta migración fija, solo cambió en `main`
-- `private.metricas_conversiones_implementacion` (1a0e7f7f… → 14f45688…: bases cargadas `20261006042144` —la lista de orígenes
-- con cierre pasa a `private.conversion_origen_con_cierre`— y tope de referidos `20261007203000` —la «conversión ponderada» del
-- referido usa el aporte del núcleo y el paquete declara `tope_referidos_pct`—). Su «cita real», `ce.realizada and
-- ce.debio_ocurrir` del núcleo, es la misma línea: D-13 sigue en pie (los informes de conversiones siguen contando la cita real
-- desde su hora) y esta migración no la toca. `private.metricas_reuniones_implementacion`, `private.citas_episodios` (3 y 4
-- argumentos), `private.contadores_crudos_leads_citas`, `private.huella_exenciones_analitica_lc`, `crm.metricas_reuniones_fn` y
-- la exención, idénticos a los auditados: la métrica «Realización» (numerador `metrica_realizada`, divisor
-- `debieron − canceladas del sistema vencidas − reprogramadas vencidas`, D-11/Q2 y D-13) es la verificada. (El oráculo fija
-- además `private.conversion_episodios`, que la pantalla usa solo para «terminan en cliente/contrato»: cambió por el tope de
-- referidos y sus filas de cierre son las mismas; ver la re-auditoría del bloque 2.6.) Cambian: esa huella del postflight, la
-- exclusión de los `*_mutantes` en los dos barridos de trinquetes (requisito F4.2 del plan, como el bloque 2.7) y nada del cuerpo.
--
-- RE-AUDITORÍA F4.2-bis (09/10/2026, tarde). Producción aplicó `20261009200000_crm_baja_analista_heredero` (un analista dado de baja
-- cede su capital y sus operaciones al responsable actual activo). De lo que esta migración fija (preflight y postflight) no cambió
-- nada: la migración entra igual. Cambiaron dos funciones que fija el ORÁCULO (caso 6b) y que la función de la pantalla consume:
-- `private.conversion_episodios` (e3d278a1… → 125b4046…: solo el analista de la pierna de operaciones) y `private.capital_episodios`
-- (214c6bad… → b4ee7e56…: solo el analista y `en_roster`, por `private.analista_efectivo_contrato` / `analista_efectivo_cierre`, con
-- `cross join lateral` de una función escalar: mismas filas). La pantalla lee de `conversion_episodios` solo `lead_id`,
-- `fecha_numerador` y `anulado` de las filas `cierre`, y de `capital_episodios` solo `monto`, `moneda`, `fecha`, `medida`, `tipo`,
-- `cliente_id` y `lead_id`, con llamadas globales: ninguna columna que cambió. «Realización» (numerador `metrica_realizada`, divisor
-- `debieron − canceladas del sistema vencidas − reprogramadas vencidas`, D-11/Q2 y D-13) sale solo de `private.citas_episodios`, que
-- no cambió: es la verificada. Medido además con un ensayo de equivalencia (rollback; `fase-4/F4.2b-reselle/salidas/trabajo/
-- b22-equivalencia/` del plan): la respuesta de la pantalla en cuatro ventanas, con las funciones de producción y con las auditadas,
-- sin y con analistas dados de baja con heredero, es idéntica (8 de 8; con una reunión convertida sembrada, para que conversión y
-- capital no salgan en cero), y con la baja las de producción sí atribuyen al heredero 48 filas de capital y 5 operaciones. Cambian
-- solo esas dos huellas en el oráculo (y, en el montaje del ensayo, `antes.sql`, se neutralizan dentro de la transacción las
-- reuniones ajenas con hora futura que deja el banco); esta migración, solo en esta cabecera.
--
-- VERIFICACIÓN. `supabase/scripts/metricas-reuniones-realizacion/`: el oráculo sale ROJO sin esta migración (la realizada
-- anticipada no entra al divisor; la app rechazaría el payload) y VERDE con ella; sus mutantes mueren por su fallo; las
-- derivas previas la hacen abortar en el preflight (y un gate sembrado cuyo primer error cambia solo después del carácter
-- 160 la hace abortar en el postflight: la foto compara el texto entero); la reversa devuelve las huellas y la exención
-- originales; la foto de los 36 `assert_*` (la del ensayo `--trinquetes`, que sí barre los `*_mutantes`) y el censo analítico,
-- idénticos antes y después. Verificada solo en el laboratorio local (desde F4.2-bis, el igual a producción del 09/10/2026:
-- B5+B6, `main` a3b89cc4 y la extra 20261009200000).
--
-- REVERSIÓN: `supabase/scripts/metricas-reuniones-realizacion/reversa.sql` repone el cuerpo anterior (`md5(prosrc)` vuelve a
-- 6880150b… y `md5(pg_get_functiondef)` a cec7ee9e…), la huella de la exención (4b28cc41…), el sello y el comentario; falla
-- cerrada si la función no tiene exactamente la definición que dejó esta migración. No hay datos que deshacer.
begin;
set local search_path = '';
set local lock_timeout = '5s';
set local statement_timeout = '60s';
select pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtext('private.analitica_leads_citas_exenciones'),
  pg_catalog.hashtext('migracion'));
lock table private.analitica_leads_citas_exenciones in share row exclusive mode;
lock table private.analitica_lc_sello in share row exclusive mode;
lock table private.analitica_leads_citas_tope in share row exclusive mode;

do $preflight$
declare
  v_objeto constant text := 'private.metricas_reuniones_implementacion(date,date)';
  v_prosrc text;
  v_def text;
  v_fila jsonb;
  v_foto text := '';
  v text;
  r record;
begin
  -- 1. La función existe y su cuerpo es el auditado, y solo él (si ya es el nuevo, la migración ya está aplicada).
  if to_regprocedure(v_objeto) is null then
    raise exception 'PREFLIGHT realizacion_cuenta_anticipada: falta %', v_objeto;
  end if;
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)) into v_prosrc, v_def
    from pg_proc p where p.oid = v_objeto::regprocedure;
  if v_prosrc = 'ca6fe61e76bcb8bf2d213acb1b7fc030' then
    raise exception 'PREFLIGHT realizacion_cuenta_anticipada: el cuerpo vivo ya es el que deja esta migración, o esta migración ya está aplicada: nada que hacer';
  end if;
  if v_prosrc is distinct from '6880150bfda80eddda014068aeb9c7da' then
    raise exception 'PREFLIGHT realizacion_cuenta_anticipada: el cuerpo de private.metricas_reuniones_implementacion no es el auditado (md5(prosrc) %, se esperaba 6880150b…): revisar antes de re-emitirla', v_prosrc;
  end if;
  if v_def is distinct from 'cec7ee9ec1c31ddd8fa17f1d42e88fc1' then
    raise exception 'PREFLIGHT realizacion_cuenta_anticipada: la definición de private.metricas_reuniones_implementacion no es la auditada (un atributo cambió sin tocar el cuerpo, p. ej. un SET o INVOKER; md5 %, se esperaba cec7ee9e…): revisar antes de re-emitirla', v_def;
  end if;
  -- 2. Su ficha: `create or replace` conserva dueño y ACL, así que una deriva previa sobreviviría al cambio y la
  --    comparación «antes = después» del postflight la daría por buena. Identidad con lo auditado.
  if not exists (
       select 1 from pg_proc p
       where p.oid = v_objeto::regprocedure
         and p.proowner = 'postgres'::regrole::oid
         and p.prosecdef
         and p.provolatile = 's'
         and p.proconfig = array['search_path=""'])
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p
           cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
          where p.oid = v_objeto::regprocedure)
        is distinct from array['postgres:EXECUTE:false'] then
    raise exception 'PREFLIGHT realizacion_cuenta_anticipada: la ficha de private.metricas_reuniones_implementacion no es la auditada (dueño postgres, security definer, STABLE, search_path vacío, EXECUTE solo para el dueño)';
  end if;
  if obj_description(v_objeto::regprocedure, 'pg_proc') is distinct from
       'Pantalla Reuniones (F2.5): «terminan en cliente/contrato» ya NO miran crm.leads.contrato_id (columna que nadie rellena) ni la ficha del lead con sus anulados: cuentan cierres del LEDGER posteriores a la reunion, sin anular, leidos de private.conversion_episodios. Misma verdad que HOY/Ranking/Conversiones/Distribucion (H16).' then
    raise exception 'PREFLIGHT realizacion_cuenta_anticipada: el comentario de private.metricas_reuniones_implementacion cambió desde que se auditó: revisar antes de reemplazarlo';
  end if;
  -- 3. Las fuentes de las que depende el cambio: el núcleo cuyas banderas se componen y las piezas del vigía que fijan
  --    cómo se normaliza y se sella la huella, más la puerta que sirve la métrica.
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.citas_episodios(timestamptz,timestamptz,timestamptz)'))
       is distinct from '5580cc4babd10d3f75a12e2373ff1bd5'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.citas_episodios(timestamptz,timestamptz,timestamptz,uuid[])'))
       is distinct from '55525e2208fbc83af5d15df3af845b6a'
     or (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = to_regprocedure('private.contadores_crudos_leads_citas()'))
       is distinct from '6a5d2a2ed9e6442aff17d598af6d59da'
     or (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = to_regprocedure('private.huella_exenciones_analitica_lc()'))
       is distinct from 'ad7d8cfd4e4f4ae6f1c2c3fecf51bb99'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.metricas_reuniones_fn(date,date)'))
       is distinct from 'ca480bc76d7624fbd3f6e6b2016d5fc3' then
    raise exception 'PREFLIGHT realizacion_cuenta_anticipada: cambió una fuente de la que depende este cambio (private.citas_episodios, private.contadores_crudos_leads_citas, private.huella_exenciones_analitica_lc o crm.metricas_reuniones_fn): revisar antes de re-emitir';
  end if;
  -- 4. La exención analítica, tal como se revisó, y el sello previo coincidiendo con la lista.
  select to_jsonb(e) into v_fila from private.analitica_leads_citas_exenciones e where e.objeto = v_objeto;
  if v_fila is null
     or v_fila ->> 'tipo' is distinct from 'funcion'
     or v_fila ->> 'clase' is distinct from 'analitica'
     or v_fila ->> 'huella' is distinct from '4b28cc419c1b0d84fdbe43afdd5a0909'
     or v_fila ->> 'razon' is distinct from 'CONSUME LOS DOS NUCLEOS (citas_episodios para banderas, conversion_episodios para cierres): agrega filas ya servidas por los núcleos y expone el divisor y sus exclusiones por modalidad; no reconstruye esas reglas.' then
    raise exception 'PREFLIGHT realizacion_cuenta_anticipada: la exención analítica de private.metricas_reuniones_implementacion no es la auditada (tipo funcion, clase analitica, huella 4b28cc41…, razón revisada): revisar antes de re-sellar';
  end if;
  if (select s.sello from private.analitica_lc_sello s where s.id)
       is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'PREFLIGHT realizacion_cuenta_anticipada: el sello previo de la lista de exenciones no coincide con la lista: revisar antes de re-sellar';
  end if;
  if not exists (select 1 from private.contadores_crudos_leads_citas() c
                  where c.objeto = v_objeto and c.declarada and c.huella_ok) then
    raise exception 'PREFLIGHT realizacion_cuenta_anticipada: el censo analítico no reconoce la exención vigente de private.metricas_reuniones_implementacion (declarada y con huella al día): revisar antes de re-sellar';
  end if;
  -- 5. Lo que el postflight exige intacto: la ficha, la exención sin su huella, las demás exenciones, el tope y la FOTO
  --    de los private.assert_*() sin argumentos: por cada gate, su estado (pasa) o, si cae, SQLSTATE + texto ÍNTEGRO del
  --    primer error, sin truncar (se exige que NO cambie, no que pasen). SIN los `*_mutantes` (F4.2, como el bloque 2.7,
  --    hallazgo F2 de su auditor de permisos): varios de ellos aplican, sin guarda propia, DDL de permisos sobre tablas
  --    calientes (revoke de SELECT en crm.leads, `disable row level security` en crm.tareas y crm.leads, grants a anon,
  --    policies nuevas: `20260920045202`, `20260919185718`, `20260920014500`) dentro de subtransacciones que se deshacen; en
  --    la base real eso toma candados ACCESS EXCLUSIVE en preflight y postflight (hasta el `lock_timeout` de 5 s) y puede
  --    dar un postflight no determinista si un candado caduca. Esos mutantes se siguen ensayando en el laboratorio
  --    (`armar-ensayo.mjs --trinquetes` barre los 36), no en la migración.
  perform set_config('crm.realizacion_ficha_previa',
    (select p.oid::regprocedure::text || '|' || p.proowner::regrole::text || '|' || p.prosecdef::text
        || '|' || coalesce(p.proconfig::text, '-') || '|' || coalesce(p.proacl::text, '-')
        || '|' || p.provolatile::text || '|' || p.proparallel::text || '|' || p.proleakproof::text
        || '|' || p.prorettype::regtype::text
       from pg_proc p where p.oid = v_objeto::regprocedure),
    true);
  perform set_config('crm.realizacion_exencion_previa', (v_fila - 'huella')::text, true);
  perform set_config('crm.realizacion_otras_exenciones',
    coalesce((select jsonb_agg(to_jsonb(e) order by e.objeto) from private.analitica_leads_citas_exenciones e where e.objeto <> v_objeto)::text, '[]'), true);
  perform set_config('crm.realizacion_tope_previo',
    coalesce((select to_jsonb(t)::text from private.analitica_leads_citas_tope t where t.id), '-'), true);
  for r in
    select p.oid::regprocedure::text as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0
    order by 1
  loop
    begin
      execute 'select ' || r.f;
      v := 'pasa';
    exception when others then
      v := 'cae: ' || sqlstate || ' ' || sqlerrm;
    end;
    v_foto := v_foto || r.f || ' => ' || v || E'\n';
  end loop;
  perform set_config('crm.realizacion_trinquetes_previos', v_foto, true);
end
$preflight$;

CREATE OR REPLACE FUNCTION private.metricas_reuniones_implementacion(p_desde date, p_hasta date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_ahora timestamptz := now();
  v_payload jsonb;
  v_autorizado boolean;
begin
  select exists (
    select 1 from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.perfil_id = v_uid and e.activo and p.activo and e.rol_crm = 'gerencia'
  ) or private.es_lector_global() into v_autorizado;
  if v_uid is null or not coalesce(v_autorizado, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_desde is null or p_hasta is null or p_desde > p_hasta
     or p_hasta > v_hoy or p_hasta - p_desde > 365 then
    raise exception 'Periodo invalido' using errcode = '22023';
  end if;
  v_ini := p_desde::timestamp at time zone 'America/Lima';
  v_fin := (p_hasta + 1)::timestamp at time zone 'America/Lima';

  with cierres_del_nucleo as materialized (
    -- F2.5: los cierres que el NUCLEO reconoce (sin anulados), de la
    -- tabla-base. La ventana llega hasta `ahora` porque una reunion del rango
    -- puede acabar en cierre despues; ese cierre sigue siendo suyo.
    select distinct e.lead_id, min(e.fecha_numerador) as cerrado_en
    from private.conversion_episodios(
      v_ini, greatest(v_fin, v_ahora), null::date, true, '{}'::uuid[],
      private.peso_referido_conversion(date_trunc('month', p_hasta)::date)
    ) e
    where e.tipo = 'cierre' and not e.anulado and e.lead_id is not null
    group by e.lead_id
  ),
  base as materialized (
    select t.*, ce.modalidad as modalidad,
      coalesce(l.origen, 'sin_origen') as origen,
      l.perfil_id as cliente_id, l.contrato_id, l.convertido_en,
      case when l.moneda = 'USD' then c.capital_usd_nucleo else c.capital_pen_nucleo end as capital,
      l.moneda, c.contrato_creado_en_nucleo as contrato_creado_en,
      coalesce(p.nombre_completo, 'Sin responsable') as responsable_nombre,
      e.rol_crm, e.supervisor_id,
      coalesce(ps.nombre_completo, 'Sin equipo') as supervisor_nombre,
      (ce.debio_ocurrir or ce.realizada) as metrica_debio_ocurrir,
      ce.realizada as metrica_realizada,
      ce.no_show as metrica_no_show,
      ce.cancelada_asesor as metrica_cancelada_asesor,
      ce.cancelada_sistema as metrica_cancelada_sistema,
      ce.reprogramada as metrica_reprogramada,
      ce.pendiente_cierre as metrica_pendiente_cierre,
      ce.programada_futura as metrica_programada_futura
    from private.citas_episodios(v_ini, v_fin, v_ahora) ce
    join crm.tareas t on t.id = ce.tarea_id
    left join crm.leads l on l.id = t.lead_id
    left join lateral (
      -- F4.i: el capital VIVO del lead, del NUCLEO (misma regla que el panel
      -- de Conversiones): contratos del perfil + cooperativas del lead. El
      -- enlace leads.contrato_id jamas se rello (0/466) y por eso esta
      -- pantalla mostro capital 0 SIEMPRE.
      select sum(k.monto) filter (where k.moneda='PEN') as capital_pen_nucleo,
             sum(k.monto) filter (where k.moneda='USD') as capital_usd_nucleo,
             min(k.fecha) as contrato_creado_en_nucleo
      from private.capital_episodios('-infinity'::timestamptz,'infinity'::timestamptz,true,'{}'::uuid[]) k
      where k.medida = 'stock'
        and ((k.tipo like 'contrato_%' and k.cliente_id = l.perfil_id)
          or (k.tipo = 'cooperativa' and k.lead_id = l.id))
    ) c on true
    left join public.perfiles p on p.id = t.vendedor_id
    left join crm.equipo e on e.perfil_id = t.vendedor_id
    left join public.perfiles ps on ps.id = e.supervisor_id
  ),
  ultima_realizada as materialized (
    select distinct on (lead_id)
      lead_id, modalidad, origen, vendedor_id, responsable_nombre,
      supervisor_id, supervisor_nombre, cliente_id, contrato_id, convertido_en,
      capital, moneda, contrato_creado_en, vence_en,
      -- ANTES: `cliente_id is not null and convertido_en >= vence_en` (la
      -- ficha del lead) y la columna de contrato enlazado, que nadie rellena
      -- — por eso «terminan en contrato» valia 0 SIEMPRE.
      -- AHORA: el cierre del LEDGER, sin anulados, ocurrido despues de la
      -- reunion. Es la misma verdad que HOY, Ranking, Conversiones y
      -- Distribucion. Las dos banderas miden ya lo mismo: en este CRM el
      -- cierre ES el hecho; el enlace al contrato no existe (se rotula en F3).
      exists (select 1 from cierres_del_nucleo cn
               where cn.lead_id = base.lead_id and cn.cerrado_en >= base.vence_en)
        as metrica_conversion_cliente,
      exists (select 1 from cierres_del_nucleo cn
               where cn.lead_id = base.lead_id and cn.cerrado_en >= base.vence_en)
        as metrica_conversion_contrato,
      -- Explica los cierres que existen en el horizonte consultado pero
      -- preceden la hora prevista de la última cita. No cambia la atribución.
      exists (select 1 from cierres_del_nucleo cn
               where cn.lead_id = base.lead_id and cn.cerrado_en < base.vence_en)
        as metrica_cierre_previo
    from base
    where metrica_realizada and lead_id is not null
    order by lead_id, vence_en desc, id desc
  ),
  resumen as (
    select count(*)::int as pactadas,
      count(*) filter (where metrica_debio_ocurrir)::int as debieron_ocurrir,
      count(*) filter (where metrica_realizada)::int as realizadas,
      count(*) filter (where metrica_no_show)::int as no_show,
      count(*) filter (where metrica_cancelada_asesor)::int as canceladas,
      count(*) filter (where metrica_cancelada_sistema)::int as canceladas_sistema,
      count(*) filter (where metrica_reprogramada)::int as reprogramadas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_sistema
      )::int as canceladas_sistema_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_reprogramada
      )::int as reprogramadas_vencidas,
      count(*) filter (where metrica_pendiente_cierre)::int as pendientes_cierre,
      count(*) filter (where metrica_programada_futura)::int as programadas_futuras
    from base
  ),
  modalidad_base as (
    select modalidad,
      count(*)::int as pactadas,
      count(*) filter (where metrica_debio_ocurrir)::int as debieron_ocurrir,
      count(*) filter (where metrica_realizada)::int as realizadas,
      count(*) filter (where metrica_no_show)::int as no_show,
      count(*) filter (where metrica_cancelada_asesor)::int as canceladas,
      count(*) filter (where metrica_reprogramada)::int as reprogramadas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_sistema
      )::int as canceladas_sistema_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_reprogramada
      )::int as reprogramadas_vencidas,
      count(*) filter (where metrica_pendiente_cierre)::int as pendientes_cierre
    from base group by modalidad
  ),
  modalidad_conversion as (
    select modalidad,
      count(*)::int as leads_reunidos,
      count(*) filter (where metrica_conversion_cliente)::int as clientes,
      count(*) filter (where metrica_conversion_contrato)::int as contratos,
      count(*) filter (where metrica_cierre_previo)::int as leads_con_cierre_previo,
      coalesce(sum(capital) filter (where metrica_conversion_contrato and moneda = 'PEN'),0) as capital_pen,
      coalesce(sum(capital) filter (where metrica_conversion_contrato and moneda = 'USD'),0) as capital_usd
    from ultima_realizada group by modalidad
  ),
  origen_base as (
    select origen,
      count(*)::int as pactadas,
      count(*) filter (where metrica_debio_ocurrir)::int as debieron_ocurrir,
      count(*) filter (where metrica_realizada)::int as realizadas,
      count(*) filter (where metrica_no_show)::int as no_show,
      count(*) filter (where metrica_cancelada_asesor)::int as canceladas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_sistema
      )::int as canceladas_sistema_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_reprogramada
      )::int as reprogramadas_vencidas
    from base group by origen
  ),
  origen_conversion as (
    select origen,
      count(*)::int as leads_reunidos,
      count(*) filter (where metrica_conversion_cliente)::int as clientes,
      count(*) filter (where metrica_conversion_contrato)::int as contratos,
      count(*) filter (where metrica_cierre_previo)::int as leads_con_cierre_previo
    from ultima_realizada group by origen
  ),
  responsables as (
    select vendedor_id, responsable_nombre, rol_crm, supervisor_id, supervisor_nombre,
      count(*)::int as pactadas,
      count(*) filter (where metrica_debio_ocurrir)::int as debieron_ocurrir,
      count(*) filter (where metrica_realizada)::int as realizadas,
      count(*) filter (where metrica_no_show)::int as no_show,
      count(*) filter (where metrica_cancelada_asesor)::int as canceladas,
      count(*) filter (where metrica_reprogramada)::int as reprogramadas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_sistema
      )::int as canceladas_sistema_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_asesor
          and cancelada_por_id is distinct from vendedor_id
      )::int as canceladas_ajenas_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_reprogramada
      )::int as reprogramadas_vencidas,
      count(*) filter (where metrica_programada_futura)::int as programadas_futuras,
      count(*) filter (where metrica_pendiente_cierre)::int as pendientes_cierre
    from base
    group by vendedor_id, responsable_nombre, rol_crm, supervisor_id, supervisor_nombre
  ),
  resultados as (
    select coalesce(resultado_reunion, 'sin_clasificar') as resultado,
      count(*)::int as cantidad
    from base where metrica_realizada
    group by coalesce(resultado_reunion, 'sin_clasificar')
  ),
  conversion_global as (
    select count(*)::int as leads_reunidos,
      count(*) filter (where metrica_conversion_cliente)::int as clientes,
      count(*) filter (where metrica_conversion_contrato)::int as contratos,
      count(*) filter (where metrica_cierre_previo)::int as leads_con_cierre_previo,
      coalesce(sum(capital) filter (where metrica_conversion_contrato and moneda = 'PEN'),0) as capital_pen,
      coalesce(sum(capital) filter (where metrica_conversion_contrato and moneda = 'USD'),0) as capital_usd
    from ultima_realizada
  )
  select jsonb_build_object(
    'version', 1, 'generado_en', now(),
    'periodo', jsonb_build_object(
      'desde', p_desde, 'hasta', p_hasta,
      'dias', (p_hasta-p_desde)+1, 'zona', 'America/Lima'
    ),
    'resumen', jsonb_build_object(
      'pactadas', r.pactadas, 'debieron_ocurrir', r.debieron_ocurrir,
      'divisor_realizacion', r.debieron_ocurrir-r.canceladas_sistema_vencidas-r.reprogramadas_vencidas,
      'divisor_asistencia', r.realizadas+r.no_show,
      'canceladas_sistema_vencidas', r.canceladas_sistema_vencidas,
      'reprogramadas_vencidas', r.reprogramadas_vencidas,
      'realizadas', r.realizadas, 'no_concretadas', r.no_show+r.canceladas,
      'no_show', r.no_show, 'canceladas', r.canceladas,
      'canceladas_sistema', r.canceladas_sistema,
      'reprogramadas', r.reprogramadas,
      'pendientes_cierre', r.pendientes_cierre,
      'programadas_futuras', r.programadas_futuras,
      'pct_realizacion', case
        when r.debieron_ocurrir-r.canceladas_sistema_vencidas-r.reprogramadas_vencidas > 0
        then round(
          100.0*r.realizadas
          /(r.debieron_ocurrir-r.canceladas_sistema_vencidas-r.reprogramadas_vencidas),
          1
        )
      end,
      'pct_asistencia', case when r.realizadas+r.no_show > 0
        then round(100.0*r.realizadas/(r.realizadas+r.no_show),1) end
    ),
    'conversion', jsonb_build_object(
      'leads_reunidos', cg.leads_reunidos, 'clientes', cg.clientes,
      'leads_con_cierre_previo', cg.leads_con_cierre_previo,
      'contratos', cg.contratos,
      'conversion_cliente_pct', case when cg.leads_reunidos > 0 then round(100.0*cg.clientes/cg.leads_reunidos,1) end,
      'conversion_contrato_pct', case when cg.leads_reunidos > 0 then round(100.0*cg.contratos/cg.leads_reunidos,1) end,
      'capital_pen', cg.capital_pen, 'capital_usd', cg.capital_usd
    ),
    'modalidades', coalesce((select jsonb_agg(jsonb_build_object(
      'modalidad', mb.modalidad, 'pactadas', mb.pactadas,
      'debieron_ocurrir', mb.debieron_ocurrir, 'realizadas', mb.realizadas,
      'no_concretadas', mb.no_show+mb.canceladas, 'no_show', mb.no_show,
      'canceladas', mb.canceladas, 'reprogramadas', mb.reprogramadas,
      'divisor_realizacion',
        mb.debieron_ocurrir-mb.canceladas_sistema_vencidas-mb.reprogramadas_vencidas,
      'canceladas_sistema_vencidas', mb.canceladas_sistema_vencidas,
      'reprogramadas_vencidas', mb.reprogramadas_vencidas,
      'pendientes_cierre', mb.pendientes_cierre,
      'pct_realizacion', case
        when mb.debieron_ocurrir-mb.canceladas_sistema_vencidas-mb.reprogramadas_vencidas > 0
        then round(
          100.0*mb.realizadas
          /(mb.debieron_ocurrir-mb.canceladas_sistema_vencidas-mb.reprogramadas_vencidas),
          1
        )
      end,
      'pct_asistencia', case when mb.realizadas+mb.no_show > 0 then round(100.0*mb.realizadas/(mb.realizadas+mb.no_show),1) end,
      'leads_reunidos', coalesce(mc.leads_reunidos,0),
      'leads_con_cierre_previo', coalesce(mc.leads_con_cierre_previo,0),
      'clientes', coalesce(mc.clientes,0), 'contratos', coalesce(mc.contratos,0),
      'conversion_cliente_pct', case when coalesce(mc.leads_reunidos,0)>0 then round(100.0*mc.clientes/mc.leads_reunidos,1) end,
      'conversion_contrato_pct', case when coalesce(mc.leads_reunidos,0)>0 then round(100.0*mc.contratos/mc.leads_reunidos,1) end,
      'capital_pen', coalesce(mc.capital_pen,0), 'capital_usd', coalesce(mc.capital_usd,0)
    ) order by case mb.modalidad when 'presencial' then 1 when 'virtual' then 2 else 3 end)
      from modalidad_base mb left join modalidad_conversion mc using (modalidad)), '[]'::jsonb),
    'origenes', coalesce((select jsonb_agg(jsonb_build_object(
      'origen', ob.origen, 'pactadas', ob.pactadas, 'realizadas', ob.realizadas,
      'no_show', ob.no_show, 'canceladas', ob.canceladas,
      'pct_realizacion', case
        when ob.debieron_ocurrir-ob.canceladas_sistema_vencidas-ob.reprogramadas_vencidas > 0
        then round(
          100.0*ob.realizadas
          /(ob.debieron_ocurrir-ob.canceladas_sistema_vencidas-ob.reprogramadas_vencidas),
          1
        )
      end,
      'leads_reunidos', coalesce(oc.leads_reunidos,0),
      'leads_con_cierre_previo', coalesce(oc.leads_con_cierre_previo,0),
      'clientes', coalesce(oc.clientes,0), 'contratos', coalesce(oc.contratos,0),
      'conversion_contrato_pct', case when coalesce(oc.leads_reunidos,0)>0 then round(100.0*oc.contratos/oc.leads_reunidos,1) end
    ) order by ob.realizadas desc, ob.pactadas desc, ob.origen)
      from origen_base ob left join origen_conversion oc using (origen)), '[]'::jsonb),
    'responsables', coalesce((select jsonb_agg(jsonb_build_object(
      'responsable_id', rr.vendedor_id, 'nombre', rr.responsable_nombre,
      'rol', rr.rol_crm, 'supervisor_id', rr.supervisor_id,
      'supervisor_nombre', rr.supervisor_nombre,
      'pactadas', rr.pactadas, 'realizadas', rr.realizadas,
      'debieron_ocurrir', rr.debieron_ocurrir,
      'divisor_realizacion', rr.debieron_ocurrir-rr.canceladas_sistema_vencidas
        -rr.canceladas_ajenas_vencidas-rr.reprogramadas_vencidas,
      'canceladas_sistema_vencidas', rr.canceladas_sistema_vencidas,
      'canceladas_ajenas_vencidas', rr.canceladas_ajenas_vencidas,
      'reprogramadas_vencidas', rr.reprogramadas_vencidas,
      'programadas_futuras', rr.programadas_futuras,
      'no_show', rr.no_show, 'canceladas', rr.canceladas,
      'reprogramadas', rr.reprogramadas,
      'pendientes_cierre', rr.pendientes_cierre,
      'pct_realizacion', case
        when rr.debieron_ocurrir-rr.canceladas_sistema_vencidas
          -rr.canceladas_ajenas_vencidas-rr.reprogramadas_vencidas > 0
        then round(
          100.0*rr.realizadas
          /(rr.debieron_ocurrir-rr.canceladas_sistema_vencidas
            -rr.canceladas_ajenas_vencidas-rr.reprogramadas_vencidas),
          1
        )
      end
    ) order by rr.realizadas desc, rr.pactadas desc, rr.responsable_nombre) from responsables rr), '[]'::jsonb),
    'resultados', coalesce((select jsonb_agg(jsonb_build_object(
      'resultado', resultado, 'cantidad', cantidad
    ) order by cantidad desc, resultado) from resultados), '[]'::jsonb)
  ) into v_payload
  from resumen r cross join conversion_global cg;

  return v_payload;
end;
$function$;

comment on function private.metricas_reuniones_implementacion(date, date) is
  'Pantalla Reuniones (F2.5): «terminan en cliente/contrato» ya NO miran crm.leads.contrato_id (columna que nadie rellena) ni la ficha del lead con sus anulados: cuentan cierres del LEDGER posteriores a la reunion, sin anular, leidos de private.conversion_episodios. Misma verdad que HOY/Ranking/Conversiones/Distribucion (H16). «Realización» cuenta la cita realizada antes de su hora desde que se marca (bloque 2.2, D-11/Q2 y D-13, 07/10/2026): metrica_debio_ocurrir es (debio_ocurrir or realizada), las dos banderas del núcleo, así la anticipada entra al divisor y al numerador a la vez; pertenece al mes de su hora pactada; las canceladas por el asesor vencidas siguen en el divisor; los informes de conversiones siguen leyendo debio_ocurrir del núcleo sin cambio.';

-- ── Re-sellado de la huella analítica (plantilla 20260908020020) ─────────────────────────────────────────────────
do $resello$
declare
  v_objeto constant text := 'private.metricas_reuniones_implementacion(date,date)';
  v_huella text;
  v_n integer;
begin
  -- Expresión idéntica a private.contadores_crudos_leads_citas (fijada arriba por md5): el cuerpo VIVO, normalizado.
  select md5(regexp_replace(regexp_replace(
             lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
             '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')) into v_huella
    from pg_proc p where p.oid = v_objeto::regprocedure;
  if v_huella is distinct from 'd54d4f8773cf1106dadbcb0d793575e2' then
    raise exception 'RESELLO realizacion_cuenta_anticipada: la huella normalizada del cuerpo aplicado (%) no es la revisada (d54d4f87…)', v_huella;
  end if;
  update private.analitica_leads_citas_exenciones
     set huella = v_huella
   where objeto = v_objeto and huella = '4b28cc419c1b0d84fdbe43afdd5a0909';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'RESELLO realizacion_cuenta_anticipada: se esperaba actualizar una exención y fueron %', v_n;
  end if;
  update private.analitica_lc_sello
     set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
   where id;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'RESELLO realizacion_cuenta_anticipada: se esperaba actualizar un sello y fueron %', v_n;
  end if;
end
$resello$;

-- ── Postflight ───────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_objeto constant text := 'private.metricas_reuniones_implementacion(date,date)';
  v_prosrc text;
  v_def text;
  v_src text;
  v_foto text := '';
  v text;
  v_gates integer := 0;
  r record;
begin
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)), p.prosrc into v_prosrc, v_def, v_src
    from pg_proc p where p.oid = v_objeto::regprocedure;
  -- El único cambio quedó, y solo él.
  if position('(ce.debio_ocurrir or ce.realizada) as metrica_debio_ocurrir' in v_src) = 0
     or position(E'\n      ce.debio_ocurrir as metrica_debio_ocurrir' in v_src) > 0 then
    raise exception 'POSTFLIGHT realizacion_cuenta_anticipada: el cambio no quedó en private.metricas_reuniones_implementacion';
  end if;
  -- El cuerpo nuevo es el que se ensayó (huellas exactas).
  if v_prosrc is distinct from 'ca6fe61e76bcb8bf2d213acb1b7fc030' then
    raise exception 'POSTFLIGHT realizacion_cuenta_anticipada: el cuerpo aplicado no es el ensayado (md5(prosrc) obtenido %, esperado ca6fe61e…)', v_prosrc;
  end if;
  if v_def is distinct from 'ce852e3740f60a57938e2baf2c0b736d' then
    raise exception 'POSTFLIGHT realizacion_cuenta_anticipada: la definición aplicada no es la ensayada (md5 obtenido %, esperado ce852e37…)', v_def;
  end if;
  -- Dueño, ACL y atributos, intactos (y EXECUTE solo para el dueño).
  if (select p.oid::regprocedure::text || '|' || p.proowner::regrole::text || '|' || p.prosecdef::text
        || '|' || coalesce(p.proconfig::text, '-') || '|' || coalesce(p.proacl::text, '-')
        || '|' || p.provolatile::text || '|' || p.proparallel::text || '|' || p.proleakproof::text
        || '|' || p.prorettype::regtype::text
       from pg_proc p where p.oid = v_objeto::regprocedure)
     is distinct from current_setting('crm.realizacion_ficha_previa', true) then
    raise exception 'POSTFLIGHT realizacion_cuenta_anticipada: cambió el dueño, la ACL o un atributo de private.metricas_reuniones_implementacion';
  end if;
  if not exists (
       select 1 from pg_proc p
       where p.oid = v_objeto::regprocedure
         and p.proowner = 'postgres'::regrole::oid and p.prosecdef and p.provolatile = 's'
         and p.proconfig = array['search_path=""'])
     or has_function_privilege('anon', v_objeto, 'EXECUTE')
     or has_function_privilege('authenticated', v_objeto, 'EXECUTE')
     or has_function_privilege('service_role', v_objeto, 'EXECUTE') then
    raise exception 'POSTFLIGHT realizacion_cuenta_anticipada: private.metricas_reuniones_implementacion debe ser security definer, STABLE, con search_path vacío y SIN EXECUTE para anon, authenticated y service_role';
  end if;
  -- La exención: huella nueva y nada más cambiado; las demás exenciones y el tope, intactos; el sello, coincidente; el
  -- censo, reconociéndola.
  if (select to_jsonb(e) - 'huella' from private.analitica_leads_citas_exenciones e where e.objeto = v_objeto)
       is distinct from current_setting('crm.realizacion_exencion_previa', true)::jsonb then
    raise exception 'POSTFLIGHT realizacion_cuenta_anticipada: se alteró la declaración de la exención más allá de su huella';
  end if;
  if (select e.huella from private.analitica_leads_citas_exenciones e where e.objeto = v_objeto)
       is distinct from 'd54d4f8773cf1106dadbcb0d793575e2' then
    raise exception 'POSTFLIGHT realizacion_cuenta_anticipada: la huella de la exención no quedó re-sellada (d54d4f87…)';
  end if;
  if coalesce((select jsonb_agg(to_jsonb(e) order by e.objeto) from private.analitica_leads_citas_exenciones e where e.objeto <> v_objeto)::text, '[]')
       is distinct from current_setting('crm.realizacion_otras_exenciones', true)
     or coalesce((select to_jsonb(t)::text from private.analitica_leads_citas_tope t where t.id), '-')
       is distinct from current_setting('crm.realizacion_tope_previo', true) then
    raise exception 'POSTFLIGHT realizacion_cuenta_anticipada: se alteró otra exención o el tope';
  end if;
  if (select s.sello from private.analitica_lc_sello s where s.id)
       is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'POSTFLIGHT realizacion_cuenta_anticipada: el sello no coincide con la lista re-sellada';
  end if;
  if not exists (select 1 from private.contadores_crudos_leads_citas() c
                  where c.objeto = v_objeto and c.declarada and c.huella_ok) then
    raise exception 'POSTFLIGHT realizacion_cuenta_anticipada: el censo analítico no reconoce la exención re-sellada';
  end if;
  -- Lo que no se toca, intacto.
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.citas_episodios(timestamptz,timestamptz,timestamptz)'))
       is distinct from '5580cc4babd10d3f75a12e2373ff1bd5'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.citas_episodios(timestamptz,timestamptz,timestamptz,uuid[])'))
       is distinct from '55525e2208fbc83af5d15df3af845b6a'
     or (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = to_regprocedure('private.contadores_crudos_leads_citas()'))
       is distinct from '6a5d2a2ed9e6442aff17d598af6d59da'
     or (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = to_regprocedure('private.huella_exenciones_analitica_lc()'))
       is distinct from 'ad7d8cfd4e4f4ae6f1c2c3fecf51bb99'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.metricas_reuniones_fn(date,date)'))
       is distinct from 'ca480bc76d7624fbd3f6e6b2016d5fc3'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.metricas_conversiones_implementacion(date,date,text)'))
       is distinct from '24fed436494daffe4bcb4813aea9a2d6' then
    raise exception 'POSTFLIGHT realizacion_cuenta_anticipada: cambió algo que esta migración no debía tocar (private.citas_episodios, private.contadores_crudos_leads_citas, private.huella_exenciones_analitica_lc, crm.metricas_reuniones_fn o private.metricas_conversiones_implementacion)';
  end if;
  if obj_description(v_objeto::regprocedure, 'pg_proc') is distinct from
       'Pantalla Reuniones (F2.5): «terminan en cliente/contrato» ya NO miran crm.leads.contrato_id (columna que nadie rellena) ni la ficha del lead con sus anulados: cuentan cierres del LEDGER posteriores a la reunion, sin anular, leidos de private.conversion_episodios. Misma verdad que HOY/Ranking/Conversiones/Distribucion (H16). «Realización» cuenta la cita realizada antes de su hora desde que se marca (bloque 2.2, D-11/Q2 y D-13, 07/10/2026): metrica_debio_ocurrir es (debio_ocurrir or realizada), las dos banderas del núcleo, así la anticipada entra al divisor y al numerador a la vez; pertenece al mes de su hora pactada; las canceladas por el asesor vencidas siguen en el divisor; los informes de conversiones siguen leyendo debio_ocurrir del núcleo sin cambio.' then
    raise exception 'POSTFLIGHT realizacion_cuenta_anticipada: el comentario nuevo no quedó';
  end if;
  -- La foto de los private.assert_*() sin argumentos (sin los `*_mutantes`: ver el preflight, F4.2) —estado (pasa) o
  -- SQLSTATE + texto ÍNTEGRO del primer error, sin truncar— es EXACTAMENTE la misma que antes de la migración. Garantiza eso
  -- y solo eso: no acredita PASS de un gate que ya caía (su primer error, íntegro, sigue siendo el mismo).
  for r in
    select p.oid::regprocedure::text as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0
    order by 1
  loop
    v_gates := v_gates + 1;
    begin
      execute 'select ' || r.f;
      v := 'pasa';
    exception when others then
      v := 'cae: ' || sqlstate || ' ' || sqlerrm;
    end;
    v_foto := v_foto || r.f || ' => ' || v || E'\n';
  end loop;
  if v_foto is distinct from current_setting('crm.realizacion_trinquetes_previos', true) then
    raise exception E'POSTFLIGHT realizacion_cuenta_anticipada: algún private.assert_*() da otro resultado que antes de la migración.\nANTES:\n%\nDESPUÉS:\n%',
      current_setting('crm.realizacion_trinquetes_previos', true), v_foto;
  end if;
  raise notice 'POSTFLIGHT realizacion_cuenta_anticipada: cuerpo % · definición % · exención re-sellada d54d4f87… · % trinquetes con estado y texto íntegro del primer error idénticos a los previos',
    v_prosrc, v_def, v_gates;
end
$postflight$;

commit;
$mig$::text as contenido;
create temp table registro_20261013145852_condiciones on commit drop as
select c.orden, c.condicion, c.cumple from (values
  (1, 'private.metricas_reuniones_implementacion: cuerpo, md5(prosrc) ca6fe61e… (postflight)',
   (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.metricas_reuniones_implementacion(date,date)')) = 'ca6fe61e76bcb8bf2d213acb1b7fc030'),
  (2, 'private.metricas_reuniones_implementacion: definición entera, md5(pg_get_functiondef) ce852e37… (postflight)',
   (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = to_regprocedure('private.metricas_reuniones_implementacion(date,date)')) = 'ce852e3740f60a57938e2baf2c0b736d'),
  (3, 'private.metricas_reuniones_implementacion: ficha (dueño postgres, security definer, STABLE, search_path vacío)',
   (select p.proowner = 'postgres'::regrole::oid and p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""']
       from pg_proc p where p.oid = to_regprocedure('private.metricas_reuniones_implementacion(date,date)'))),
  (4, 'private.metricas_reuniones_implementacion: ACL efectiva (nadie salvo el dueño; ni anon, ni authenticated, ni service_role)',
   (select not exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                     where a.grantee <> 'postgres'::regrole::oid)
         and not has_function_privilege('anon', p.oid, 'EXECUTE')
         and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
         and not has_function_privilege('service_role', p.oid, 'EXECUTE')
       from pg_proc p where p.oid = to_regprocedure('private.metricas_reuniones_implementacion(date,date)'))),
  (5, 'private.metricas_reuniones_implementacion: comentario (el que fija la migración)',
   obj_description(to_regprocedure('private.metricas_reuniones_implementacion(date,date)'), 'pg_proc') = 'Pantalla Reuniones (F2.5): «terminan en cliente/contrato» ya NO miran crm.leads.contrato_id (columna que nadie rellena) ni la ficha del lead con sus anulados: cuentan cierres del LEDGER posteriores a la reunion, sin anular, leidos de private.conversion_episodios. Misma verdad que HOY/Ranking/Conversiones/Distribucion (H16). «Realización» cuenta la cita realizada antes de su hora desde que se marca (bloque 2.2, D-11/Q2 y D-13, 07/10/2026): metrica_debio_ocurrir es (debio_ocurrir or realizada), las dos banderas del núcleo, así la anticipada entra al divisor y al numerador a la vez; pertenece al mes de su hora pactada; las canceladas por el asesor vencidas siguen en el divisor; los informes de conversiones siguen leyendo debio_ocurrir del núcleo sin cambio.'),
  (6, 'exención analítica: huella re-sellada d54d4f87… (postflight)',
   (select e.huella from private.analitica_leads_citas_exenciones e where e.objeto = 'private.metricas_reuniones_implementacion(date,date)') = 'd54d4f8773cf1106dadbcb0d793575e2'),
  (7, 'sello de la lista de exenciones coincidente',
   (select s.sello from private.analitica_lc_sello s where s.id) = private.huella_exenciones_analitica_lc()),
  (8, 'censo analítico: reconoce la exención re-sellada',
   exists (select 1 from private.contadores_crudos_leads_citas() c
         where c.objeto = 'private.metricas_reuniones_implementacion(date,date)' and c.declarada and c.huella_ok))
) as c(orden, condicion, cumple);
do $chk$
declare
  v_md5    text;
  v_fallan text;
  v_otras  text;
begin
  select md5(r.contenido) into v_md5 from pg_temp.registro_20261013145852 r;
  if v_md5 is distinct from 'd6f56ed226f3835daad75309eca137fc' then
    raise exception 'REGISTRO: el archivo incrustado no es el de la migración (md5 %, esperado d6f56ed226f3835daad75309eca137fc)', v_md5;
  end if;
  select string_agg(c.orden || '. ' || c.condicion, '; ' order by c.orden) into v_fallan
    from pg_temp.registro_20261013145852_condiciones c where c.cumple is not true;
  if v_fallan is not null then
    raise exception 'REGISTRO: la migración 20261013145852 no está aplicada o su estado no es el que deja (no se cumple: %); no se registra', v_fallan;
  end if;
  select string_agg(s.version, ', ' order by s.version) into v_otras
    from supabase_migrations.schema_migrations s where s.name = 'crm_realizacion_cuenta_anticipada' and s.version <> '20261013145852';
  if v_otras is not null then
    raise exception 'REGISTRO: el nombre crm_realizacion_cuenta_anticipada ya está registrado con otra versión (%): no se registra dos veces la misma migración', v_otras;
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations s cross join pg_temp.registro_20261013145852 r
             where s.version = '20261013145852' and (coalesce(s.name, '') <> 'crm_realizacion_cuenta_anticipada' or s.statements is distinct from array[r.contenido])) then
    raise exception 'REGISTRO: la versión 20261013145852 ya está registrada con otro nombre u otro contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
select '20261013145852', 'crm_realizacion_cuenta_anticipada', array[r.contenido] from pg_temp.registro_20261013145852 r
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261013145852' and name = 'crm_realizacion_cuenta_anticipada' and cardinality(statements) = 1
                   and md5(statements[1]) = 'd6f56ed226f3835daad75309eca137fc') then
    raise exception 'REGISTRO: la fila 20261013145852 / crm_realizacion_cuenta_anticipada no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261013145852 / crm_realizacion_cuenta_anticipada (1 sentencia: el archivo entero)';
end $post$;
commit;
-- Última fila, tras el COMMIT, para que `db query` muestre algo.
select '20261013145852' as version_registrada, 'd6f56ed226f3835daad75309eca137fc' as md5_del_archivo;

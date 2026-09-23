-- Los vigias aprenden a tachar sus propios partes (Miguel, 22/09/2026).
--
-- EL DEFECTO, medido en produccion el 22/09:
--
--   filas totales en private.vigia_alertas ....... 45
--   filas abiertas ............................... 45
--   filas RESUELTAS en toda la historia ..........  0   <-- ninguna, nunca
--   primera alerta ....................... 2026-09-05
--
-- Los tres vigias tienen exactamente la misma forma: corren su assert y, si
-- lanza, INSERTAN una fila. No hay rama para el caso contrario. Cuando la causa
-- se arregla, el vigia del dia siguiente simplemente no anade una nueva -- pero
-- las viejas se quedan abiertas para siempre. Nada en toda la base escribe
-- `resuelta_en` sobre esta tabla: lo unico que la menciona ademas de los tres
-- vigias es `private.veredicto_f7()`, y sus dos unicas lineas son un
-- `count(*) ... where resuelta_en is null` y un `string_agg` igual. Solo CUENTA.
--
-- POR QUE IMPORTA. El preflight de demolicion de la Fase 7 exige CERO alertas
-- abiertas DE CUALQUIER FASE (stop-the-line). Un freno que exige «cero avisos»
-- sobre una tabla que no cierra ninguno no es un freno: es un candado al que se
-- le perdio la llave. La demolicion de las olas 2 y 2b quedo imposible el
-- 05/09, el dia del primer aviso -- no por falta de evidencia (todo el resto de
-- su preflight esta verde), sino por esto.
--
-- De las 45 abiertas hoy, 13 (`f6a_analitica_leads_citas`) describen problemas
-- YA RESUELTOS: son del 05 al 21/09 y no hay ninguna del 22, porque el vigia de
-- hoy ya encontro verde. Estan frenando la obra sin motivo.
--
-- EL ARREGLO, y de donde sale. `private.vigia_auditoria()` -- el cuarto vigia,
-- el de la regla de auditoria (mig 20260829230000) -- YA SABE cerrar: pone
-- `resuelta_en = now()` sobre `private.auditoria_alertas` cuando la condicion
-- desaparece. Nacio sabiendo; a los otros tres se les olvido. Aqui se les ensena
-- el mismo gesto, sin inventar nada:
--
--   si el assert de la fase devuelve VERDE  -> se cierran las alertas de ESA
--                                              fase, y solo de esa;
--   si lanza                                -> se abre una, como hasta hoy.
--
-- CADA VIGIA CIERRA SOLO LO SUYO. `vigia_f7_piezas` no tocara jamas una fila de
-- `f5a_analista_vigencia` ni al reves. No es una promesa: el mutante
-- `vigias-cierran-mutante.sql` lo comprueba con un filo dedicado.
--
-- NO SE CIERRA NADA EN ROJO. Una alerta cuya causa sigue viva se queda abierta,
-- que es justo lo contrario del defecto que se arregla. Hoy mismo se ve la
-- diferencia: `assert_analitica_leads_citas()` esta verde y sus 13 se cerraran;
-- `assert_analista_vigencia()` esta en ROJO de verdad -- `public.proteger_campos_
-- inmutables()` cambio de cuerpo desde que se declaro -- y sus 16 NO se tocan.
-- El postflight comprueba las dos cosas.
--
-- 🔴 EL HUECO QUE ESTO NO CUBRE, dicho antes de que muerda.
-- `private.registrar_ajuste_si_mes_cerrado()` NO es un vigia y tambien escribe
-- en esta tabla, con la fase `f6c_ajuste_sin_episodio`:
--
--     insert into private.vigia_alertas (fase, motivo)
--     values ('f6c_ajuste_sin_episodio', format('lead %s: sin episodio ...'));
--
-- No existe `assert_f6c_*` ni `vigia_f6c_*`: es una funcion de NEGOCIO que
-- dispara sobre un lead concreto. No hay assert al que volver verde, asi que esa
-- fila no la cerraria nadie. Hoy no duele -- CERO filas de esa fase en toda la
-- historia de la tabla, abiertas o cerradas -- pero en cuanto dispare una vez
-- vuelve a bloquear la demolicion de forma permanente, por el mismo camino.
--
-- Deliberadamente NO se arregla aqui, por dos razones: (1) tocar el cuerpo de
-- una funcion de negocio que escribe la deuda del mes sellado no es «ensenar a
-- los vigias a cerrar», es otra decision; (2) la salida buena probablemente no
-- sea darle un vigia, sino reconocer que ese aviso es un RASTRO HISTORICO por
-- lead -- el ajuste ya se escribio con valor 0 y eso no se deshace aunque el
-- lead gane un episodio despues -- y por tanto no es un estado que vuelva a
-- verde. Se deja MEDIBLE en vez de silencioso: `private.vigia_alertas_sin_cierre()`
-- nombra cualquier fase con alertas abiertas que ningun vigia sabe cerrar. Si
-- `f6c` dispara algun dia, esa funcion lo dice en una linea en vez de que se
-- descubra dentro de tres meses cuando frene otra obra.
--
-- COMO SE REVIERTE, entero. Un md5 no repone nada: solo acredita. Los cuerpos
-- anteriores viven en el arbol y hay que copiarlos de ahi:
--   vigia_analitica_leads_citas (md5 7aa37c8d1f207340ac17d9f162252a5c)
--   vigia_analista_vigencia     (md5 aff56f0da1ff05756f8ae5f7d234f1bb)
--     -> 20260830120000_crm_f6_a_nucleo_de_citas_y_censo.sql
--   vigia_f7_piezas             (md5 9ca05b1688bc65c438a6d1339450c139)
--     -> 20260831020000_crm_f7_0_el_gate_que_vigila_las_puertas.sql
-- Ademas:
--   drop function if exists private.vigia_alertas_sin_cierre();
--   drop function if exists private.vigia_fases_cerrables();
--
-- 🔑 Y LO QUE DE VERDAD MUEVE EL FRENO son las filas cerradas, no los cuerpos.
-- Reponer los tres cuerpos y dejar las filas cerradas deja el stop-the-line MAS
-- PERMISIVO que antes de esta migracion. El deshacer es mecanico porque
-- `pg_catalog.now()` es el instante de la TRANSACCION: las 13 comparten
-- timestamp exacto, y el postflight lo devuelve en su fila de veredicto para
-- que quede anotado al aplicar.
--   update private.vigia_alertas
--      set resuelta_en = null
--    where fase = 'f6a_analitica_leads_citas'
--      and resuelta_en = '<el timestamp que devolvio el veredicto>';
--
-- ⚠️ ESTA MIGRACION NO ES RE-APLICABLE NI REPLAYABLE EN BANCO VACIO, a
-- proposito: su preflight exige 0 resueltas (una segunda pasada falla, que es lo
-- correcto: el mundo cambio) y exige alertas abiertas (sin datos no habria nada
-- que demostrar). Se aplica por `db query --file` + `migration repair`, no por
-- replay.
--
-- ⚠️ ESTADO ESPERADO TRAS APLICAR: 46 filas -- 13 cerradas y 33 abiertas. La
-- de mas la escribe el propio postflight al correr el vigia de vigencia, que
-- hoy esta en ROJO de verdad: esa es la prueba de que en rojo no se cierra.
-- Esto NO desbloquea la demolicion de las olas 2 y 2b: quita 13 de los 45
-- obstaculos. Faltan las 16 de f7 (re-declaracion de huella) y las 16 de f5a
-- (senal viva sobre `public`, decision de Miguel).

begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = pg_catalog;
lock table private.vigia_alertas in share row exclusive mode;

-- ---------------------------------------------------------------------------
-- (a) PREFLIGHT: el mundo que esta migracion da por cierto.
-- ---------------------------------------------------------------------------
do $preflight$
declare
  v_resueltas integer; v_abiertas integer; v_fases text;
  v_pin record;
begin
  -- Los tres cuerpos son EXACTAMENTE los que se leyeron al escribir esto. Si
  -- alguien los cambio mientras tanto, esta migracion no sabe lo que pisa.
  for v_pin in
    select * from (values
      ('private.vigia_analitica_leads_citas()', '7aa37c8d1f207340ac17d9f162252a5c'),
      ('private.vigia_analista_vigencia()',     'aff56f0da1ff05756f8ae5f7d234f1bb'),
      ('private.vigia_f7_piezas()',             '9ca05b1688bc65c438a6d1339450c139')
    ) as t(fn, huella)
  loop
    -- Cuerpo Y dueño Y ACL. `pg_get_functiondef` no lleva dueño ni permisos, y
    -- `create or replace` los CONSERVA en silencio: si alguna tuviera hoy un
    -- EXECUTE de mas, esta migracion se lo preservaria y ademas le anadiria la
    -- capacidad de CERRAR alertas. Se comprueba antes de tocarlas.
    if not exists (select 1 from pg_proc p
                    where p.oid = to_regprocedure(v_pin.fn)
                      and md5(pg_get_functiondef(p.oid)) = v_pin.huella) then
      raise exception 'PREFLIGHT: % no tiene el cuerpo esperado (%). Alguien lo cambio; releer antes de aplicar.',
        v_pin.fn, v_pin.huella;
    end if;
    if not exists (select 1 from pg_proc p
                    where p.oid = to_regprocedure(v_pin.fn)
                      and p.proowner = 'postgres'::regrole
                      and (select jsonb_agg(jsonb_build_array(a.grantee::regrole::text, a.privilege_type)
                                    order by a.grantee::regrole::text, a.privilege_type)
                             from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a)
                          = '[["postgres","EXECUTE"]]'::jsonb) then
      raise exception 'PREFLIGHT: % no es de postgres o tiene EXECUTE para alguien mas; no se le anade poder de cierre a ciegas', v_pin.fn;
    end if;
  end loop;

  select count(*) filter (where resuelta_en is not null),
         count(*) filter (where resuelta_en is null)
    into v_resueltas, v_abiertas
    from private.vigia_alertas;
  if v_resueltas <> 0 then
    raise exception 'PREFLIGHT: se esperaban 0 alertas resueltas en toda la historia y hay %. El mundo cambio: releer.', v_resueltas;
  end if;
  if v_abiertas = 0 then
    raise exception 'PREFLIGHT: no hay ninguna alerta abierta; esta migracion no tendria nada que demostrar en su postflight';
  end if;

  select string_agg(distinct fase, ', ' order by fase) into v_fases from private.vigia_alertas;
  if v_fases is distinct from 'f5a_analista_vigencia, f6a_analitica_leads_citas, f7_piezas_cerradas' then
    raise exception 'PREFLIGHT: las fases presentes en la tabla son «%», no las tres esperadas', v_fases;
  end if;

  -- El estado de partida de los dos asserts que el postflight va a contrastar:
  -- uno VERDE (sus alertas deben cerrarse) y uno ROJO (las suyas NO).
  begin
    perform private.assert_analitica_leads_citas();
  exception when others then
    raise exception 'PREFLIGHT: se esperaba assert_analitica_leads_citas() en VERDE y dice: %', sqlerrm;
  end;
  begin
    perform private.assert_analista_vigencia();
    raise exception 'PREFLIGHT: se esperaba assert_analista_vigencia() en ROJO y salio verde; el postflight de aislamiento no probaria nada';
  exception when others then
    if sqlerrm like 'PREFLIGHT:%' then raise; end if;
    -- Un rojo cualquiera no vale: `when others` se traga tambien un
    -- `undefined_function`, un permiso o un timeout, y este encabezado afirma
    -- una causa CONCRETA. Se exige que sea esa.
    if sqlerrm not like '%CAMBIO desde que se declararon%' then
      raise exception 'PREFLIGHT: assert_analista_vigencia() esta en rojo por OTRA causa que la esperada: %', sqlerrm;
    end if;
  end;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- (b) Los tres vigias, con el gesto que les faltaba.
--     El `perform` va SOLO dentro del bloque con manejador: asi `when others`
--     caza la condicion real del assert y nada mas. El cierre va fuera, para
--     que un fallo al cerrar no se disfrace de alerta nueva.
-- ---------------------------------------------------------------------------
create or replace function private.vigia_analitica_leads_citas()
returns void language plpgsql security definer set search_path = ''
as $vigia$
declare v_verde boolean := false;
begin
  begin
    perform private.assert_analitica_leads_citas();
    v_verde := true;
  exception when others then
    insert into private.vigia_alertas (fase, motivo)
    values ('f6a_analitica_leads_citas', sqlerrm);
  end;
  if v_verde then
    update private.vigia_alertas
       set resuelta_en = pg_catalog.now()
     where fase = 'f6a_analitica_leads_citas' and resuelta_en is null;
  end if;
end;
$vigia$;

create or replace function private.vigia_analista_vigencia()
returns void language plpgsql security definer set search_path = ''
as $vigia$
declare v_verde boolean := false;
begin
  begin
    perform private.assert_analista_vigencia();
    v_verde := true;
  exception when others then
    insert into private.vigia_alertas (fase, motivo)
    values ('f5a_analista_vigencia', sqlerrm);
  end;
  if v_verde then
    update private.vigia_alertas
       set resuelta_en = pg_catalog.now()
     where fase = 'f5a_analista_vigencia' and resuelta_en is null;
  end if;
end;
$vigia$;

create or replace function private.vigia_f7_piezas()
returns void language plpgsql security definer set search_path = ''
as $vigia$
declare v_verde boolean := false;
begin
  begin
    perform private.assert_f7_piezas_cerradas();
    v_verde := true;
  exception when others then
    insert into private.vigia_alertas (fase, motivo)
    values ('f7_piezas_cerradas', sqlerrm);
  end;
  if v_verde then
    update private.vigia_alertas
       set resuelta_en = pg_catalog.now()
     where fase = 'f7_piezas_cerradas' and resuelta_en is null;
  end if;
end;
$vigia$;

comment on function private.vigia_analitica_leads_citas() is
  'Ronda diaria (cron 06:49) de la analitica de leads y citas. Si su assert lanza, abre una alerta; '
  'si devuelve verde, CIERRA las alertas abiertas de su fase y solo de su fase. Una alerta cuya causa '
  'sigue viva no se cierra.';
comment on function private.vigia_analista_vigencia() is
  'Ronda diaria (cron 06:39) de la vigencia del analista. Si su assert lanza, abre una alerta; si '
  'devuelve verde, CIERRA las alertas abiertas de su fase y solo de su fase.';
comment on function private.vigia_f7_piezas() is
  'Ronda diaria (cron 06:59) de las piezas cerradas de la Fase 7. Si su assert lanza, abre una alerta; '
  'si devuelve verde, CIERRA las alertas abiertas de su fase y solo de su fase.';

-- ---------------------------------------------------------------------------
-- (c) El hueco, MEDIBLE -- y medido LEYENDO LOS CUERPOS, no una lista a mano.
--
--     La primera version de esto llevaba las tres fases escritas a mano en un
--     `not in (...)`. Eso responde a «que fases TIENEN vigia», no a «que fases
--     CIERRA de hecho un vigia», que es la pregunta util. Con la lista a mano,
--     un literal mal escrito SOLO en el `update` de un vigia -- por ejemplo
--     `where fase = 'f7_piezas'` en vez de `'f7_piezas_cerradas'` -- dejaria esa
--     fase sin cerrar para siempre Y el detector diria que esta cubierta:
--     exactamente el defecto que esta migracion existe para eliminar, otra vez y
--     esta vez invisible. Un literal duplicado en dos sitios es la forma que
--     tiene este proyecto de perder llaves.
--
--     Asi que la lista se COSECHA del `update` real de cada vigia. Si el literal
--     se desvia, la fase de verdad aparece como huerfana y se ve. Es ademas lo
--     unico que cubre a los dos vigias cuyo assert esta en ROJO hoy y cuya rama
--     de cierre, por tanto, no se puede ejecutar ni una vez en todo el ciclo.
-- ---------------------------------------------------------------------------
create or replace function private.vigia_fases_cerrables()
returns table(vigia text, fase_que_abre text, fase_que_cierra text)
language sql stable security invoker set search_path = ''
as $cerrables$
  -- `left(proname,6)` y no `like 'vigia\_%'`: en LIKE el guion bajo es COMODIN,
  -- y su escape es justo la clase de trampa que este repo ya pago una vez.
  select p.oid::regprocedure::text,
         (pg_catalog.regexp_match(p.prosrc,
            'insert\s+into\s+private\.vigia_alertas[^;]*?values\s*\(\s*''([a-zA-Z0-9_]+)'''))[1],
         (pg_catalog.regexp_match(p.prosrc,
            'set\s+resuelta_en\s*=[^;]*?where\s+fase\s*=\s*''([a-zA-Z0-9_]+)'''))[1]
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private'
     -- Un vigia se reconoce por lo que HACE, no por como se llama: es plpgsql,
     -- no devuelve nada y ESCRIBE en la tabla. Filtrar solo por el nombre
     -- metia aqui a las dos funciones de abajo, que la LEEN -- y el propio
     -- postflight lo cazo al primer ensayo, que es justo su trabajo.
     and p.prolang = (select l.oid from pg_catalog.pg_language l where l.lanname = 'plpgsql')
     and p.prorettype = 'pg_catalog.void'::regtype
     and pg_catalog.left(p.proname, 6) = 'vigia_'
     and p.prosrc ~ 'insert\s+into\s+private\.vigia_alertas';
$cerrables$;

comment on function private.vigia_fases_cerrables() is
  'Que fase ABRE y que fase CIERRA cada vigia, leido de su propio cuerpo. Las dos columnas deben '
  'coincidir en las tres filas; si una difiere o sale NULL, ese vigia abre alertas que no cerrara '
  'nunca. Se lee el cuerpo a proposito en vez de repetir los literales en una lista: un literal '
  'duplicado en dos sitios es como se pierden las llaves. El mutante lo comprueba en un filo '
  'ESTATICO, que es lo unico capaz de cubrir los dos vigias cuyo assert esta en rojo y cuya rama de '
  'cierre no se puede ejecutar hoy.';

create or replace function private.vigia_alertas_sin_cierre()
returns table(fase text, abiertas bigint, desde date)
language sql stable security invoker set search_path = ''
as $huerfanas$
  select a.fase, pg_catalog.count(*), pg_catalog.min(a.creado_en)::date
    from private.vigia_alertas a
   where a.resuelta_en is null
     and a.fase not in (select c.fase_que_cierra
                          from private.vigia_fases_cerrables() c
                         where c.fase_que_cierra is not null)
   group by a.fase
   order by a.fase;
$huerfanas$;

comment on function private.vigia_alertas_sin_cierre() is
  'Fases con alertas ABIERTAS que ningun vigia cierra -- porque no tienen vigia, o porque el suyo '
  'cierra un literal distinto del que abre. La lista de fases cubiertas se COSECHA de los cuerpos '
  '(private.vigia_fases_cerrables()), no se repite a mano. Hoy solo puede salir '
  '«f6c_ajuste_sin_episodio», que escribe private.registrar_ajuste_si_mes_cerrado() por lead y no es '
  'un estado re-evaluable. Cero filas = toda alerta abierta pertenece a una fase que un vigia sabe '
  'cerrar. Si devuelve algo, el stop-the-line de la Fase 7 se puede volver a bloquear de forma '
  'permanente: decidirlo antes, no despues.';

-- `security invoker` a proposito. CLAUDE.md: «por defecto security invoker; usar
-- definer solo si es indispensable, con justificacion escrita». Aqui no lo es:
-- las dos solo LEEN, y quien pueda leer la tabla puede correrlas. El revoke no
-- es decorativo -- `authenticated` tiene USAGE sobre `private` desde los
-- cimientos, asi que el EXECUTE implicito de PUBLIC es toda la puerta.
revoke all on function private.vigia_alertas_sin_cierre() from public;
revoke all on function private.vigia_fases_cerrables() from public;

-- ---------------------------------------------------------------------------
-- (d) POSTFLIGHT: no se da por bueno el gesto, se PRUEBA -- con los dos casos
--     que hoy existen de verdad en produccion.
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_f6a_antes integer; v_f6a_despues integer;
  v_f5a_antes integer; v_f5a_despues integer;
  v_f7_antes  integer; v_f7_despues  integer;
  v_huerfanas integer;
begin
  select count(*) filter (where fase='f6a_analitica_leads_citas'),
         count(*) filter (where fase='f5a_analista_vigencia'),
         count(*) filter (where fase='f7_piezas_cerradas')
    into v_f6a_antes, v_f5a_antes, v_f7_antes
    from private.vigia_alertas where resuelta_en is null;

  -- Se corre la MISMA funcion que corre el cron. Nada escrito a mano.
  perform private.vigia_analitica_leads_citas();

  select count(*) filter (where fase='f6a_analitica_leads_citas'),
         count(*) filter (where fase='f5a_analista_vigencia'),
         count(*) filter (where fase='f7_piezas_cerradas')
    into v_f6a_despues, v_f5a_despues, v_f7_despues
    from private.vigia_alertas where resuelta_en is null;

  -- (1) En VERDE, cierra lo suyo.
  if v_f6a_despues <> 0 then
    raise exception 'POSTFLIGHT: el vigia de analitica estaba verde y dejo % alertas suyas abiertas (eran %)',
      v_f6a_despues, v_f6a_antes;
  end if;

  -- (2) Y NO toca lo ajeno. Esta es la prueba de aislamiento, con datos reales.
  if v_f5a_despues <> v_f5a_antes or v_f7_despues <> v_f7_antes then
    raise exception 'POSTFLIGHT: el vigia de analitica toco alertas AJENAS (f5a % -> %, f7 % -> %)',
      v_f5a_antes, v_f5a_despues, v_f7_antes, v_f7_despues;
  end if;

  -- (3) En ROJO no se cierra nada: assert_analista_vigencia() lanza hoy.
  perform private.vigia_analista_vigencia();
  if (select count(*) from private.vigia_alertas
       where fase='f5a_analista_vigencia' and resuelta_en is null) <= v_f5a_antes then
    raise exception 'POSTFLIGHT: el vigia de vigencia estaba en ROJO y no abrio alerta nueva, o cerro alguna';
  end if;

  -- (3 bis) Las dos funciones NUEVAS no quedan abiertas a nadie mas. El revoke
  -- no es decorativo: `authenticated` tiene USAGE sobre `private`.
  if exists (select 1 from pg_proc p
             cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
              where p.oid in ('private.vigia_alertas_sin_cierre()'::regprocedure,
                              'private.vigia_fases_cerrables()'::regprocedure)
                and a.grantee <> 'postgres'::regrole::oid) then
    raise exception 'POSTFLIGHT: una de las dos funciones nuevas tiene EXECUTE para alguien mas que postgres';
  end if;

  -- (3 ter) CADA VIGIA ABRE Y CIERRA LA MISMA FASE. Este es el control que
  -- cubre a los dos vigias cuyo assert esta en ROJO: su rama de cierre no se
  -- puede ejecutar hoy, pero su literal SI se puede leer. Sin esto, un literal
  -- desviado en `vigia_f7_piezas` reinstalaria el defecto entero, invisible.
  if exists (select 1 from private.vigia_fases_cerrables() v
              where v.fase_que_abre is null or v.fase_que_cierra is null
                 or v.fase_que_abre is distinct from v.fase_que_cierra) then
    raise exception 'POSTFLIGHT: algun vigia abre y cierra fases distintas (o no cierra): %',
      (select string_agg(v.vigia || ' abre «' || coalesce(v.fase_que_abre,'?') || '» cierra «' || coalesce(v.fase_que_cierra,'?') || '»', '; ')
         from private.vigia_fases_cerrables() v
        where v.fase_que_abre is null or v.fase_que_cierra is null
           or v.fase_que_abre is distinct from v.fase_que_cierra);
  end if;
  if (select count(*) from private.vigia_fases_cerrables()) <> 3 then
    raise exception 'POSTFLIGHT: se esperaban 3 vigias que escriben en vigia_alertas y hay %',
      (select count(*) from private.vigia_fases_cerrables());
  end if;

  -- (4) El hueco, medido: hoy no hay ninguna fase huerfana.
  select count(*) into v_huerfanas from private.vigia_alertas_sin_cierre();
  if v_huerfanas <> 0 then
    raise exception 'POSTFLIGHT: hay % fase(s) con alertas abiertas que ningun vigia puede cerrar', v_huerfanas;
  end if;

  raise notice 'POSTFLIGHT ok: f6a % -> 0 (cerradas por su propio vigia), f5a % -> % (en rojo, intactas + 1 nueva), f7 % (sin tocar)',
    v_f6a_antes, v_f5a_antes,
    (select count(*) from private.vigia_alertas where fase='f5a_analista_vigencia' and resuelta_en is null),
    v_f7_antes;
end;
$postflight$;

-- El veredicto viaja por una FILA, no por el `raise notice` de arriba: el canal
-- `supabase db query` NO transporta notices (leccion ya escrita en la F5.a), y
-- esto toca 45 filas de un freno de produccion. El operador tiene que VER
-- cuantas se cerraron y con QUE SELLO, porque ese timestamp es lo unico que
-- necesita para deshacerlo.
select 'vigias-cierran-sus-alertas'                                                as migracion,
       (select count(*) from private.vigia_alertas where resuelta_en is not null)  as cerradas,
       (select count(*) from private.vigia_alertas where resuelta_en is null)      as abiertas,
       (select max(resuelta_en) from private.vigia_alertas)                        as sello_de_cierre,
       (select coalesce(string_agg(x.fase || ' (' || x.abiertas || ')', ', '), '(ninguna)')
          from private.vigia_alertas_sin_cierre() x)                               as fases_sin_cierre;

commit;

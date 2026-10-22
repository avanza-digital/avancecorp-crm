-- 20261022170900_crm_reuniones_desglose_con_bajas.sql — bloque 2.12 del plan «Mantenibilidad y consistencia del backend CRM» (fecha de trabajo 20261009230000_crm_reuniones_desglose_con_bajas.sql; integrado el 2026/10/22, C2 del grupo C)
-- EN LAS MÉTRICAS DE GERENCIA Y DE SUPERVISIÓN, EL ANALISTA DADO DE BAJA O SUSPENDIDO SIGUE CON SU MARCA, Y EL DESGLOSE DE
-- REUNIONES SUMA SIEMPRE EL TOTAL — bloque 2.12, decisiones de Miguel del 09/10/2026:
--   D-43  en el desglose por responsable de `crm.metricas_reuniones_fn`, el analista o supervisor dado de baja sigue con sus
--         citas y `"de_baja": true` en su elemento;
--   D-46  el «suspendido en el Portal» también, con `"suspendido": true`;
--   D-47  lo que el desglose deja fuera va a una fila «Otros» al final, con las mismas columnas: el desglose suma el total;
--   D-48  `crm.metricas_agenda_fn` (panel «Agenda del equipo» del puesto de mando del supervisor) conserva al de baja, con su
--         marca, SOLO si tiene actividad en el período, con la definición de la app (`app/src/lib/agenda-equipo-vista.ts:138-150`);
--   D-54  y también al suspendido, con «suspendido»: lo ven el supervisor (solo su subárbol) y Directorio, como Gerencia;
--   D-53  la marca llega a la pantalla viva de citas («Citas del equipo», `crm.citas_gerencia_consulta_fn`) en un bloque aparte, el
--         2.14; lo de reuniones de este bloque se queda como coherencia de la API (ver QUIÉN LAS CONSUME).
--
-- QUIÉN LAS CONSUME HOY. `crm.metricas_reuniones_fn`: el Resumen de Gerencia (`app/src/screens/hoy/resumen-gerencia.tsx:231-232`),
-- que solo lee `resumen` y `conversion`; el panel que pinta el desglose por responsable (`ReunionesGerenciaPanel`, de
-- `HoyGerencia seccion="reuniones"`) no se monta en ninguna ruta (`screens/gerencia.tsx:15-18`, `lib/vistas.ts:98`,
-- `lib/roles.ts:89,101`): Gerencia y Supervisión ven «Citas del equipo» (`TableroCitas`), que lee `crm.citas_gerencia_consulta_fn`.
-- Por eso el desglose con marcas y «Otros» de esta migración no se ve hoy en ninguna pantalla: queda como coherencia de la API
-- (el desglose suma el total). `crm.metricas_agenda_fn`: el panel «Agenda del equipo» del puesto de mando del supervisor
-- (`screens/hoy.tsx:16-17` → `supervisor-mando.tsx:977`): ahí sí se ven las marcas.
--
-- QUÉ PASABA. Las dos puertas arman su payload con su implementación y lo pasan por `private.filtrar_desglose_sujetos_crm`, que
-- solo deja a quien `private.rol_crm` reconoce como analista o supervisor; `rol_crm` exige la ficha de `crm.equipo` ACTIVA y el
-- perfil del Portal activo (desde `20260807203757`). La implementación de reuniones (la del bloque 2.2) agrupa las citas por
-- `t.vendedor_id` sin mirar la ficha: las del dado de baja, del suspendido, de la cita sin responsable y de Gerencia o
-- Coordinación seguían en el TOTAL, pero no en el desglose, que no cuadraba. La implementación de la agenda lista a todo el equipo
-- visible, activo o no, y la puerta quitaba al de baja y al suspendido aunque hubieran trabajado en el período.
--
-- QUÉ HACE.
--   · Pieza genérica del núcleo `private.filtrar_desglose_sujetos_con_bajas_crm(jsonb,text,text,text[],text[])`: el cuerpo del
--     filtro común más UNA rama. Deja, sin tocar su elemento y en su sitio, exactamente a quien deja el filtro común; y además a
--     quien tiene una ficha de uno de los roles pedidos y hoy está DADO DE BAJA (ficha inactiva: la regla de producción
--     `private.analista_dado_de_baja`) —`"de_baja": true`— o SUSPENDIDO EN EL PORTAL (ficha activa y perfil `activo is not true`:
--     la definición del propio CRM en `crm.fijar_membresia_activa_fn` y `crm.usuarios_administrables_fn`) —`"suspendido": true`—,
--     si el último argumento es nulo o alguna de esas claves de su elemento es distinta de cero. Si la ficha está inactiva gana
--     «de baja». Un marcado con el `nombre` vacío o en blanco sale como «(sin nombre)» (la agenda de la app exige texto no vacío y
--     `public.perfiles.nombre_completo` no lo impide). Sin ficha, sin identidad, o con ficha y perfil activos pero sin rol
--     efectivo (pareja desalineada), no entra.
--   · Pieza de reuniones `private.desglose_responsables_reuniones_crm(jsonb)`: la genérica con analistas y supervisores (sin
--     condición de actividad: todo elemento de la implementación tiene citas) y, si quedó alguien fuera, la fila «Otros» al final:
--     `responsable_id` nulo, `nombre` «Otros», `rol` y `supervisor_id` nulos, `supervisor_nombre` «—», `"otros": true` y las doce
--     cifras de la implementación (cada una, la de TODOS los elementos menos la de los que quedaron en el desglose; el divisor
--     descuenta igual que el de cada fila) más `pct_realizacion` recalculado como en la implementación.
--   · Re-emite `crm.metricas_reuniones_fn` con UN cambio (llama a la pieza de reuniones) y `crm.metricas_agenda_fn` con UN cambio
--     (llama a la genérica con las nueve claves de actividad de la app: toques, reuniones_realizadas, completadas, no_asistio,
--     canceladas, tareas_creadas, reuniones_agendadas, reprogramaciones y pendientes; no cuentan el rezago —vencidas, leads sin
--     acción— ni los derivados).
--   · Sin bajas, suspendidos ni «Otros» en la ventana, la respuesta es IDÉNTICA byte a byte a la de antes (medido en el ensayo).
--   · Las piezas nuevas son SECURITY INVOKER (regla de la casa): solo las llaman las puertas, DEFINER de `postgres`; EXECUTE solo
--     para el dueño; `search_path` vacío y nombres calificados.
--
-- QUÉ NO CAMBIA, Y QUÉ SÍ. No cambia A QUIÉN ve cada rol: quién consulta (reuniones: Gerencia o lector global; agenda: analista,
-- supervisor, Gerencia o lector global) y su ámbito (lo decide la implementación; en la agenda, `private.vendedor_ids_visibles`,
-- que para un supervisor recorre su subárbol sin mirar `activo`, y que esta migración fija con su huella). Sí cambia QUÉ ve de su
-- ámbito: en la agenda, el supervisor (solo su subárbol) y Directorio, como Gerencia, pasan a ver al de baja con actividad
-- («de baja», D-48) y al suspendido en el Portal con actividad («suspendido», D-54: un estado del Portal que hasta ahora solo veían
-- Gerencia y Superadmin; Miguel decidió que lo vean, para saber por qué se le quedan tareas paradas y repartirlas). El analista no
-- recibe nada nuevo. Las marcas no conceden autoridad: solo nombran. Tampoco cambian los totales y los demás cortes (no se tocan
-- las implementaciones, ni su registro analítico, ni el sello), el filtro común `private.filtrar_desglose_sujetos_crm` ni las
-- otras tres métricas que lo usan (`crm.metricas_conversiones_fn`, `crm.metricas_conversiones_equipo_fn`,
-- `crm.conversion_mensual_sin_cartera_fn`). No toca tablas, grants de tablas, policies ni objetos de `public`. No corrige datos.
--
-- FAIL-CLOSED. El preflight exige, antes de tocar nada: las dos puertas con la huella y la ficha auditadas (cuerpo, definición
-- entera, dueño `postgres`, ACL efectiva: EXECUTE para `authenticated` y el dueño), sin comentario (si su cuerpo ya es el nuevo,
-- la migración ya está aplicada y se niega); ninguna función `private` con el nombre de las piezas nuevas; la huella y la ficha
-- de todo aquello de lo que dependen: el filtro común, `private.rol_crm`, `private.es_lector_global`, la implementación de
-- reuniones EN LA VERSIÓN DEL BLOQUE 2.2 (con su exención analítica declarada y al día y el sello coherente), la de la agenda y
-- `private.vendedor_ids_visibles`; y la forma de `crm.equipo` (PK `perfil_id`; `activo` y `rol_crm` NOT NULL; FK a
-- `public.perfiles`) y de `public.perfiles.activo` (boolean). El postflight exige las dos puertas con su único cambio y su ficha
-- idéntica a la previa más su comentario; las dos piezas con su cuerpo, dueño, INVOKER, STABLE, `search_path` vacío, EXECUTE solo
-- para el dueño y su comentario; las dependencias intactas; las otras tres puertas idénticas; los dos censos, la exención y el sello
-- idénticos (ni las puertas ni las piezas entran en ningún censo); y la FOTO de los `private.assert_*()` sin argumentos y sin los
-- `*_mutantes`, con estado (`pasa`) o SQLSTATE y texto ÍNTEGRO del primer error, idéntica a la del preflight. Esa foto garantiza
-- eso y solo eso: no acredita PASS de los gates que ya caían.
--
-- ORDEN DE DESPLIEGUE (decisión del Director, 09/10/2026): PRIMERO LA APP, DESPUÉS ESTA MIGRACIÓN, con una VENTANA DE
-- CONVIVENCIA. La app publicada valida la agenda con un objeto ESTRICTO (`app/src/lib/metricas-agenda.ts`, `v.strictObject`): una
-- clave nueva (`de_baja`, `suspendido`) tumbaría el panel entero (la regla del `LEEME.md`). La app nueva acepta las marcas como
-- opcionales y funciona con la respuesta de antes y con la nueva (probado en vitest con las dos). La app NO se recarga sola al
-- publicar (`version-publicada.tsx` solo avisa): una pestaña abierta conserva el código viejo. Por eso se publica la app, se deja
-- que todos la recarguen (aviso «recargar») y se aplica esta migración después, p. ej. a primera hora del día siguiente. Y al
-- revés: REVERTIR LA APP EXIGE REVERTIR ANTES ESTA MIGRACIÓN (una app anterior al 2.12 con la migración aplicada tumba la agenda en
-- cuanto hay un marcado con actividad). Reuniones no tiene ese problema (`v.object`): una app anterior ignora las marcas y pinta
-- «Otros» como una fila más.
--
-- CONSECUENCIAS (para quien integre).
--   · Cambian las huellas de las dos puertas. El oráculo del bloque 2.2 (`supabase/scripts/metricas-reuniones-realizacion/`,
--     caso 6b) fija la de `crm.metricas_reuniones_fn` (ca480bc7…): con el 2.12 encima cae en 6b porque fija la puerta; es
--     evidencia histórica del 2.2 (decisión del Director: no se toca).
--   · La app lee las marcas nuevas (`app/src/data/crm-api.ts` las valida y las conserva; `agenda-equipo.tsx` pinta «de baja» y
--     «suspendido»; `reuniones-gerencia.tsx` pinta «de baja», «suspendido» y «Otros», pero ese panel no se monta hoy).
--   · En la agenda AGRUPADA por supervisor (más de un supervisor en la respuesta), el marcado cae en «Sin equipo asignado»: el
--     grupo sale del roster de la app (`crm.equipo_visible_fn`), que no incluye a quien no tiene rol efectivo
--     (`agenda-equipo-vista.ts:206-224`). Solo de presentación; arreglarlo exige que la respuesta traiga el `supervisor_id`.
--   · Es una excepción deliberada, solo en reuniones y agenda, a la invariante «un analista dado de baja no reaparece con nombre
--     propio» ([[crm-p04-revocado-vs-ajeno]]); `crm.conversion_mensual_fn` y las demás métricas siguen sin él.
--   · La huella viva de producción se lee antes de aplicar (fase 4): si difiere, el preflight aborta sin tocar nada.
--
-- A QUÉ PLAN RESPONDE. Plan de mantenibilidad del backend del CRM, fase 2, bloque 2.12 (D-43, D-45, D-46, D-47, D-48, D-53 y
-- D-54, 09/10/2026). Va ENCIMA del bloque 2.2 (se integra con el grupo C). Verificada por el Director (ronda 2); auditor de
-- permisos r1 atendido en la ronda 3; pendiente de la verificación del Director de la ronda 3 y de la revisión de Codex.
--
-- VERIFICACIÓN. `supabase/scripts/reuniones-desglose-con-bajas/`: el oráculo sale ROJO sin esta migración (faltan las marcas,
-- falta «Otros» y el desglose no suma el total) y VERDE con ella; sin bajas, suspendidos ni «Otros», byte a byte; la visibilidad
-- por rol no cambia; las otras métricas no cambian; sus mutantes mueren por su fallo; las derivas previas la hacen abortar; la
-- reversa devuelve las dos puertas anteriores y quita las dos piezas; trinquetes idénticos.
--
-- REVERSIÓN: `supabase/scripts/reuniones-desglose-con-bajas/reversa.sql` repone los cuerpos anteriores de las dos puertas
-- (huellas ca480bc7… / de328143… y 104d863b… / 1a5f2938…), les quita el comentario y borra las dos piezas; falla cerrada si
-- alguna no tiene exactamente la definición que dejó esta migración. No hay datos que deshacer. Revertir la migración con la app
-- nueva publicada es seguro (las marcas son opcionales); revertir la app, no, si antes no se revierte la migración.
begin;
set local search_path = '';
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $preflight$
declare
  v_reuniones constant text := 'crm.metricas_reuniones_fn(date,date)';
  v_agenda constant text := 'crm.metricas_agenda_fn(date,date)';
  v_impl constant text := 'private.metricas_reuniones_implementacion(date,date)';
  v_ficha text;
  v_distintas text;
  v_foto text := '';
  v_gates integer := 0;
  v text;
  r record;
begin
  -- 1. Las dos puertas existen y son las auditadas. Si un cuerpo ya es el nuevo, la migración ya está aplicada.
  if to_regprocedure(v_reuniones) is null or to_regprocedure(v_agenda) is null then
    raise exception 'PREFLIGHT reuniones_desglose_con_bajas: falta crm.metricas_reuniones_fn o crm.metricas_agenda_fn';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = v_reuniones::regprocedure) = 'e448db0cf1d929441da2347a0f48d85d'
     or (select md5(p.prosrc) from pg_proc p where p.oid = v_agenda::regprocedure) = 'c41eb0d85abd976bca03092e9a932d00' then
    raise exception 'PREFLIGHT reuniones_desglose_con_bajas: una puerta ya llama a las piezas nuevas, o esta migración ya está aplicada: nada que hacer';
  end if;
  -- Cuerpo, definición entera (DEFINER, STABLE, search_path vacío, plpgsql), dueño y ACL EFECTIVA. `create or replace`
  -- conserva dueño y ACL: una deriva previa sobreviviría al cambio y el «antes = después» del postflight la daría por buena.
  select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) || '|' || p.proowner::regrole::text || '|'
           || (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ','
                                 order by a.grantee::regrole::text, a.privilege_type)
                 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a)
    into v_ficha
    from pg_proc p where p.oid = v_reuniones::regprocedure;
  if v_ficha is distinct from 'ca480bc76d7624fbd3f6e6b2016d5fc3|de328143bd9221fb19bfa6af46695290|postgres|authenticated:EXECUTE:false,postgres:EXECUTE:false' then
    raise exception 'PREFLIGHT reuniones_desglose_con_bajas: la puerta crm.metricas_reuniones_fn no es la auditada (cuerpo|definición|dueño|ACL efectiva = %; se esperaba ca480bc7…|de328143…|postgres|authenticated y postgres): revisar antes de re-emitirla', v_ficha;
  end if;
  select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) || '|' || p.proowner::regrole::text || '|'
           || (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ','
                                 order by a.grantee::regrole::text, a.privilege_type)
                 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a)
    into v_ficha
    from pg_proc p where p.oid = v_agenda::regprocedure;
  if v_ficha is distinct from '104d863b5702506d18b7adca1ecbcb92|1a5f2938a6c42f44b511e53f48edf963|postgres|authenticated:EXECUTE:false,postgres:EXECUTE:false' then
    raise exception 'PREFLIGHT reuniones_desglose_con_bajas: la puerta crm.metricas_agenda_fn no es la auditada (cuerpo|definición|dueño|ACL efectiva = %; se esperaba 104d863b…|1a5f2938…|postgres|authenticated y postgres): revisar antes de re-emitirla', v_ficha;
  end if;
  if obj_description(v_reuniones::regprocedure, 'pg_proc') is not null
     or obj_description(v_agenda::regprocedure, 'pg_proc') is not null then
    raise exception 'PREFLIGHT reuniones_desglose_con_bajas: una puerta tiene un comentario que no tenía al auditarla: revisar antes de escribir el nuevo';
  end if;
  -- 2. Las piezas nuevas no existen (ni ningún homónimo en `private`, con cualquier firma).
  if exists (select 1 from pg_proc p
              where p.pronamespace = 'private'::regnamespace
                and p.proname in ('filtrar_desglose_sujetos_con_bajas_crm', 'desglose_responsables_reuniones_crm')) then
    raise exception 'PREFLIGHT reuniones_desglose_con_bajas: ya existe una private.filtrar_desglose_sujetos_con_bajas_crm o una private.desglose_responsables_reuniones_crm (pieza ajena o migración a medias): revisar antes de aplicar';
  end if;
  -- 3. Lo que esta migración da por sabido, con su huella y su ficha: el filtro común (cuyo resultado la pieza genérica
  --    conserva tal cual), private.rol_crm (quién es efectivo), private.es_lector_global (el control de acceso de las puertas),
  --    las dos implementaciones (la de reuniones EN LA VERSIÓN DEL BLOQUE 2.2) y private.vendedor_ids_visibles (el ámbito de
  --    la agenda: el subárbol del supervisor, que incluye a sus de baja y suspendidos).
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure(v_impl)) = '6880150bfda80eddda014068aeb9c7da' then
    raise exception 'PREFLIGHT reuniones_desglose_con_bajas: private.metricas_reuniones_implementacion es la anterior al bloque 2.2 (6880150b…): esta migración va ENCIMA del 2.2; aplicarla después de la del 2.2';
  end if;
  select string_agg(e.objeto, ', ' order by e.objeto) into v_distintas
    from (values
      ('private.filtrar_desglose_sujetos_crm(jsonb,text,text,text[])',
       '1cce2929af369715a2c7e161d63fc7ce|2652303501f4e7ca1d55d37ede3fd24a|postgres|postgres:EXECUTE:false'),
      ('private.rol_crm(uuid)',
       'd2878a210be96ac85973d51dfcfb27a5|99827f3fe2fbc3cfae5668c30015c758|postgres|authenticated:EXECUTE:false,postgres:EXECUTE:false'),
      ('private.es_lector_global()',
       'c7c5828be6d74121a1a0ef0de374f712|c8be602f84348a0125617995802db618|postgres|authenticated:EXECUTE:false,postgres:EXECUTE:false'),
      ('private.metricas_reuniones_implementacion(date,date)',
       'ca6fe61e76bcb8bf2d213acb1b7fc030|ce852e3740f60a57938e2baf2c0b736d|postgres|postgres:EXECUTE:false'),
      ('private.metricas_agenda_implementacion(date,date)',
       '0fc09f917a816013e1af16ef183012de|5cb341dc430b7441ff8abdd3c8110c60|postgres|postgres:EXECUTE:false'),
      ('private.vendedor_ids_visibles(uuid)',
       '33ece9bae4828f7ffdb837c6128ca9d6|85544c70a0920f3a7a1b5da06935f236|postgres|authenticated:EXECUTE:false,postgres:EXECUTE:false')
    ) e(objeto, ficha)
   where e.ficha is distinct from (select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) || '|' || p.proowner::regrole::text || '|'
           || (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ','
                                 order by a.grantee::regrole::text, a.privilege_type)
                 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a)
                                     from pg_proc p where p.oid = to_regprocedure(e.objeto));
  if v_distintas is not null then
    raise exception 'PREFLIGHT reuniones_desglose_con_bajas: cambió una dependencia (cuerpo, definición, dueño o ACL efectiva) desde que se auditó: %; revisar antes de aplicar', v_distintas;
  end if;
  -- 4. El registro analítico de la implementación de reuniones, tal como lo dejó el bloque 2.2: la exención con su huella,
  --    declarada y al día en el censo, y el sello coincidiendo con la lista. (Esta migración no lo toca.)
  if (select e.huella from private.analitica_leads_citas_exenciones e where e.objeto = v_impl)
       is distinct from 'd54d4f8773cf1106dadbcb0d793575e2'
     or not exists (select 1 from private.contadores_crudos_leads_citas() c
                     where c.objeto = v_impl and c.declarada and c.huella_ok)
     or (select s.sello from private.analitica_lc_sello s where s.id)
       is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'PREFLIGHT reuniones_desglose_con_bajas: el registro analítico de private.metricas_reuniones_implementacion no es el del bloque 2.2 (exención con huella d54d4f87…, declarada y al día en el censo, y sello coincidente con la lista): revisar antes de aplicar';
  end if;
  -- 5. La forma de lo que lee la regla: una ficha por persona (PK perfil_id), `activo`/`rol_crm` NOT NULL (con un `activo`
  --    nulo, «is false» dejaría de decir «dado de baja») y su perfil del Portal (FK a public.perfiles, `activo` boolean).
  if (select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull::text, ',' order by a.attname)
        from pg_attribute a
       where a.attrelid = 'crm.equipo'::regclass and a.attname in ('activo', 'perfil_id', 'rol_crm') and not a.attisdropped)
       is distinct from 'activo:boolean:true,perfil_id:uuid:true,rol_crm:text:true'
     or not exists (select 1 from pg_constraint c
                     where c.conrelid = 'crm.equipo'::regclass and c.contype = 'p'
                       and c.conkey = array[(select a.attnum from pg_attribute a
                                              where a.attrelid = 'crm.equipo'::regclass and a.attname = 'perfil_id')]::int2[])
     or not exists (select 1 from pg_constraint c
                     where c.conrelid = 'crm.equipo'::regclass and c.contype = 'f'
                       and c.confrelid = 'public.perfiles'::regclass and c.convalidated
                       and c.conkey = array[(select a.attnum from pg_attribute a
                                              where a.attrelid = 'crm.equipo'::regclass and a.attname = 'perfil_id')]::int2[])
     or (select format_type(a.atttypid, a.atttypmod) from pg_attribute a
          where a.attrelid = 'public.perfiles'::regclass and a.attname = 'activo' and not a.attisdropped)
       is distinct from 'boolean' then
    raise exception 'PREFLIGHT reuniones_desglose_con_bajas: crm.equipo o public.perfiles ya no tienen la forma que lee la regla (una ficha por persona, PK perfil_id con FK a public.perfiles; activo boolean y rol_crm text, NOT NULL; perfiles.activo boolean): revisar antes de aplicar';
  end if;
  -- 6. Lo que el postflight exige intacto: la ficha de las dos puertas, las otras tres puertas que usan el filtro común, los
  --    dos censos (contadores crudos de leads/citas y puertas sin vigencia del analista: ni las puertas ni las piezas pueden
  --    entrar en ellos), el registro analítico y la FOTO de los private.assert_*() sin argumentos y sin los `*_mutantes` (como
  --    el bloque 2.2: varios aplican DDL de permisos sobre tablas calientes; el ensayo `--trinquetes` sigue barriendo todos):
  --    por cada gate, su estado (pasa) o, si cae, SQLSTATE + texto ÍNTEGRO del primer error. Se exige que NO cambie.
  perform set_config('crm.bajas_puertas_ficha_previa',
    (select string_agg(p.oid::regprocedure::text || '|' || p.proowner::regrole::text || '|' || p.prosecdef::text
        || '|' || coalesce(p.proconfig::text, '-') || '|' || coalesce(p.proacl::text, '-')
        || '|' || p.provolatile::text || '|' || p.proparallel::text || '|' || p.proleakproof::text
        || '|' || p.prorettype::regtype::text
        || '|' || (select l.lanname from pg_language l where l.oid = p.prolang)::text, E'\n' order by p.oid::regprocedure::text)
       from pg_proc p where p.oid in (v_reuniones::regprocedure, v_agenda::regprocedure)), true);
  perform set_config('crm.bajas_otras_puertas', (select string_agg(o.objeto || '=' || coalesce((select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) || '|' || p.proowner::regrole::text || '|'
               || (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ','
                                     order by a.grantee::regrole::text, a.privilege_type)
                     from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a)
                                              from pg_proc p where p.oid = to_regprocedure(o.objeto)), 'FALTA'),
                    E'\n' order by o.objeto)
       from (values ('crm.metricas_conversiones_fn(date,date,text)'), ('crm.metricas_conversiones_equipo_fn(date,date)'),
                    ('crm.conversion_mensual_sin_cartera_fn(date)')) o(objeto)), true);
  perform set_config('crm.bajas_censo_analitico', (select coalesce(string_agg(c.tipo || ' ' || c.objeto || ' ' || c.declarada::text || ' ' || c.huella_ok::text,
                              E'\n' order by c.tipo, c.objeto), '(vacío)')
       from private.contadores_crudos_leads_citas() c), true);
  perform set_config('crm.bajas_censo_vigencia', (select coalesce(string_agg(c.tipo || ' ' || c.objeto || ' ' || c.declarada::text || ' ' || c.huella_ok::text,
                              E'\n' order by c.tipo, c.objeto), '(vacío)')
       from private.puertas_analista_sin_vigencia() c), true);
  perform set_config('crm.bajas_registro_analitico', (coalesce((select to_jsonb(e)::text from private.analitica_leads_citas_exenciones e
                where e.objeto = 'private.metricas_reuniones_implementacion(date,date)'), 'sin fila')
       || ' · sello ' || coalesce((select s.sello from private.analitica_lc_sello s where s.id), 'sin sello')), true);
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
  perform set_config('crm.bajas_trinquetes_previos', v_foto, true);
end
$preflight$;

-- ── Pieza genérica del núcleo: el filtro común + UNA rama (de baja o suspendido de esos roles, marcado, con actividad) ──
create function private.filtrar_desglose_sujetos_con_bajas_crm(
  p_payload jsonb,
  p_clave text,
  p_clave_id text,
  p_roles text[],
  p_claves_actividad text[]
)
returns jsonb
language plpgsql stable security invoker set search_path=''
as $function$
declare
  v_elemento jsonb;
  v_id uuid;
  v_ficha_activa boolean;
  v_perfil_activo boolean;
  v_filtrados jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_payload) <> 'object'
     or jsonb_typeof(p_payload->p_clave) <> 'array' then
    raise exception 'Contrato interno de metricas inesperado'
      using errcode='55000';
  end if;

  for v_elemento in
    select elemento.value
    from jsonb_array_elements(p_payload->p_clave) elemento
  loop
    begin
      v_id := (v_elemento->>p_clave_id)::uuid;
    exception when invalid_text_representation then
      raise exception 'Identidad interna de metricas invalida'
        using errcode='55000';
    end;

    if private.rol_crm(v_id) = any(p_roles) then
      v_filtrados := v_filtrados || jsonb_build_array(v_elemento);
    else
      select e.activo, p.activo
        into v_ficha_activa, v_perfil_activo
        from crm.equipo e
        join public.perfiles p on p.id = e.perfil_id
       where e.perfil_id = v_id
         and e.rol_crm = any(p_roles);
      if found and (
        p_claves_actividad is null
        or exists (
          select 1 from unnest(p_claves_actividad) clave
          where coalesce((v_elemento->>clave)::numeric, 0) <> 0
        )
      ) then
        -- Un marcado con el nombre vacío o en blanco sale con un nombre de reserva legible (la agenda exige texto no vacío).
        if v_elemento ? 'nombre'
           and coalesce(v_elemento->>'nombre', '') !~ '[^[:space:]]' then
          v_elemento := v_elemento || jsonb_build_object('nombre', '(sin nombre)');
        end if;
        if v_ficha_activa is false then
          v_filtrados := v_filtrados
            || jsonb_build_array(v_elemento || jsonb_build_object('de_baja', true));
        elsif v_perfil_activo is not true then
          v_filtrados := v_filtrados
            || jsonb_build_array(v_elemento || jsonb_build_object('suspendido', true));
        end if;
      end if;
    end if;
  end loop;

  return jsonb_set(p_payload,array[p_clave],v_filtrados,false);
end;
$function$;

-- ── Pieza de reuniones: la genérica con analistas y supervisores + la fila «Otros» (D-47) ──────────────────────────────
create function private.desglose_responsables_reuniones_crm(p_payload jsonb)
returns jsonb
language plpgsql stable security invoker set search_path=''
as $function$
declare
  v_desglose jsonb;
  v_otros jsonb;
begin
  v_desglose := private.filtrar_desglose_sujetos_con_bajas_crm(
    p_payload,'responsables','responsable_id',array['vendedor','supervisor'],null
  );
  if jsonb_array_length(v_desglose->'responsables')
     = jsonb_array_length(p_payload->'responsables') then
    return v_desglose;
  end if;

  select jsonb_build_object(
    'responsable_id', null, 'nombre', 'Otros',
    'rol', null, 'supervisor_id', null,
    'supervisor_nombre', '—',
    'pactadas', f.pactadas, 'realizadas', f.realizadas,
    'debieron_ocurrir', f.debieron_ocurrir,
    'divisor_realizacion', f.divisor_realizacion,
    'canceladas_sistema_vencidas', f.canceladas_sistema_vencidas,
    'canceladas_ajenas_vencidas', f.canceladas_ajenas_vencidas,
    'reprogramadas_vencidas', f.reprogramadas_vencidas,
    'programadas_futuras', f.programadas_futuras,
    'no_show', f.no_show, 'canceladas', f.canceladas,
    'reprogramadas', f.reprogramadas,
    'pendientes_cierre', f.pendientes_cierre,
    'pct_realizacion', case
      when f.divisor_realizacion > 0
      then round(100.0*f.realizadas/f.divisor_realizacion,1)
    end,
    'otros', true
  )
  into v_otros
  from (
    select
      sum(x.signo*(x.fila->>'pactadas')::int) as pactadas,
      sum(x.signo*(x.fila->>'realizadas')::int) as realizadas,
      sum(x.signo*(x.fila->>'debieron_ocurrir')::int) as debieron_ocurrir,
      sum(x.signo*(x.fila->>'divisor_realizacion')::int) as divisor_realizacion,
      sum(x.signo*(x.fila->>'canceladas_sistema_vencidas')::int) as canceladas_sistema_vencidas,
      sum(x.signo*(x.fila->>'canceladas_ajenas_vencidas')::int) as canceladas_ajenas_vencidas,
      sum(x.signo*(x.fila->>'reprogramadas_vencidas')::int) as reprogramadas_vencidas,
      sum(x.signo*(x.fila->>'programadas_futuras')::int) as programadas_futuras,
      sum(x.signo*(x.fila->>'no_show')::int) as no_show,
      sum(x.signo*(x.fila->>'canceladas')::int) as canceladas,
      sum(x.signo*(x.fila->>'reprogramadas')::int) as reprogramadas,
      sum(x.signo*(x.fila->>'pendientes_cierre')::int) as pendientes_cierre
    from (
      select todos.value as fila, 1 as signo
      from jsonb_array_elements(p_payload->'responsables') todos
      union all
      select desglose.value, -1
      from jsonb_array_elements(v_desglose->'responsables') desglose
    ) x
  ) f;

  return jsonb_set(
    v_desglose,'{responsables}',
    (v_desglose->'responsables') || jsonb_build_array(v_otros),
    false
  );
end;
$function$;

-- ── Las dos puertas: su cuerpo vigente con UN solo cambio (la llamada final) ──────────────────────────────────────────
create or replace function crm.metricas_reuniones_fn(p_desde date,p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path=''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_payload jsonb;
begin
  if v_actor is null or not coalesce(
    private.rol_crm(v_actor)='gerencia' or private.es_lector_global(),
    false
  ) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_payload:=private.metricas_reuniones_implementacion(p_desde,p_hasta);
  return private.desglose_responsables_reuniones_crm(v_payload);
end;
$function$;

create or replace function crm.metricas_agenda_fn(p_desde date,p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path=''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_payload jsonb;
begin
  if v_actor is null or not coalesce(
    private.rol_crm(v_actor) in ('vendedor','supervisor','gerencia')
    or private.es_lector_global(),
    false
  ) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_payload:=private.metricas_agenda_implementacion(p_desde,p_hasta);
  return private.filtrar_desglose_sujetos_con_bajas_crm(
    v_payload,'vendedores','vendedor_id',array['vendedor','supervisor'],
    array['toques','reuniones_realizadas','completadas','no_asistio','canceladas',
          'tareas_creadas','reuniones_agendadas','reprogramaciones','pendientes']
  );
end;
$function$;

-- ── Permisos: las piezas nuevas, solo para su dueño (las puertas conservan su ACL: `create or replace` no la toca) ─────
revoke all on function private.filtrar_desglose_sujetos_con_bajas_crm(jsonb,text,text,text[],text[])
  from public, anon, authenticated, service_role;
revoke all on function private.desglose_responsables_reuniones_crm(jsonb)
  from public, anon, authenticated, service_role;

-- ── Comentarios ──────────────────────────────────────────────────────────────────────────────────────────────────────
comment on function private.filtrar_desglose_sujetos_con_bajas_crm(jsonb,text,text,text[],text[]) is
  'Listado por sujeto de una métrica CON los dados de baja y los suspendidos (bloque 2.12: D-43, D-46, D-48 y D-54, 09/10/2026). Deja, sin tocar su elemento, exactamente a quien deja private.filtrar_desglose_sujetos_crm (private.rol_crm dentro de p_roles) y además conserva a quien tiene una ficha de crm.equipo de uno de p_roles y hoy está dado de baja (ficha inactiva, la regla de private.analista_dado_de_baja: "de_baja": true) o suspendido en el Portal (ficha activa y perfil activo is not true: "suspendido": true), si p_claves_actividad es nulo o alguna de esas claves de su elemento es distinta de cero; si su nombre está vacío o en blanco, sale como «(sin nombre)». Sin ficha, sin identidad o con ficha y perfil activos pero sin rol efectivo, no entra. No concede autoridad: solo nombra. Sin bajas ni suspendidos, la salida es idéntica a la del filtro común. La usan crm.metricas_agenda_fn y private.desglose_responsables_reuniones_crm.';
comment on function private.desglose_responsables_reuniones_crm(jsonb) is
  'Desglose por responsable de crm.metricas_reuniones_fn (bloque 2.12: D-43, D-46 y D-47, 09/10/2026): private.filtrar_desglose_sujetos_con_bajas_crm con analistas y supervisores (sin condición de actividad: todo elemento tiene citas) y, si queda alguien fuera (citas sin responsable, de Gerencia o Coordinación, de un ex Gerencia de baja, de un perfil sin rol efectivo), una fila «Otros» al final con las mismas columnas: responsable_id nulo, nombre «Otros», supervisor «—» y "otros": true; cada cifra es la de todos los elementos de la implementación menos la de los que quedaron en el desglose, y pct_realizacion se recalcula como en la implementación. Así el desglose suma siempre el total. Sin nadie fuera, no añade nada.';
comment on function crm.metricas_reuniones_fn(date,date) is
  'Puerta de las métricas de citas para Gerencia o un lector global (los demás reciben 42501). Hoy la consume el Resumen de Gerencia, que solo lee resumen y conversion; el panel que pinta el desglose por responsable (ReunionesGerenciaPanel, de HoyGerencia) no se monta en ninguna ruta, y la pantalla viva de citas de Gerencia y Supervisión usa crm.citas_gerencia_consulta_fn (la marca llega allí con el bloque 2.14, D-53). El desglose por responsable pasa por private.desglose_responsables_reuniones_crm y queda como coherencia de la API: el analista o supervisor dado de baja (ficha de crm.equipo inactiva) o suspendido en el Portal (ficha activa, perfil inactivo) sigue con sus citas y "de_baja": true o "suspendido": true en su elemento, y lo que queda fuera (citas sin responsable, de otros roles) va a una fila «Otros» al final con "otros": true: el desglose suma siempre el total (bloque 2.12: D-43, D-46 y D-47, 09/10/2026). Sin bajas, suspendidos ni «Otros» en la ventana, la respuesta es idéntica a la anterior.';
comment on function crm.metricas_agenda_fn(date,date) is
  'Puerta del panel «Agenda del equipo» (analista, supervisor, Gerencia o lector global; los demás reciben 42501); el ámbito lo decide private.metricas_agenda_implementacion. El listado pasa por private.filtrar_desglose_sujetos_con_bajas_crm: el analista o supervisor dado de baja (ficha inactiva) o suspendido en el Portal (ficha activa, perfil inactivo) sigue con "de_baja": true o "suspendido": true SOLO si tiene actividad en el período (las nueve claves de tieneActividad de la app); sin ella, fuera como antes (bloque 2.12: D-48, y D-54 para «suspendido», que también ven el supervisor, solo de su subárbol, y Directorio; 09/10/2026). Sin bajas ni suspendidos con actividad, la respuesta es idéntica a la anterior. La app valida esta respuesta con un objeto estricto: se publica ANTES la app que acepta las marcas.';

-- ── Postflight ───────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_reuniones constant text := 'crm.metricas_reuniones_fn(date,date)';
  v_agenda constant text := 'crm.metricas_agenda_fn(date,date)';
  v_filtro constant text := 'private.filtrar_desglose_sujetos_con_bajas_crm(jsonb,text,text,text[],text[])';
  v_pieza constant text := 'private.desglose_responsables_reuniones_crm(jsonb)';
  v_distintas text;
  v_foto text := '';
  v_gates integer := 0;
  v text;
  r record;
begin
  -- 1. Las dos puertas: el único cambio quedó, y solo él (huellas exactas), con su ficha intacta y su comentario.
  if position('private.desglose_responsables_reuniones_crm(' in (select p.prosrc from pg_proc p where p.oid = v_reuniones::regprocedure)) = 0
     or position('private.filtrar_desglose_sujetos_crm(' in (select p.prosrc from pg_proc p where p.oid = v_reuniones::regprocedure)) > 0
     or position('private.filtrar_desglose_sujetos_con_bajas_crm(' in (select p.prosrc from pg_proc p where p.oid = v_agenda::regprocedure)) = 0
     or position('private.filtrar_desglose_sujetos_crm(' in (select p.prosrc from pg_proc p where p.oid = v_agenda::regprocedure)) > 0 then
    raise exception 'POSTFLIGHT reuniones_desglose_con_bajas: una puerta no quedó llamando a su pieza nueva';
  end if;
  if (select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_reuniones::regprocedure)
       is distinct from 'e448db0cf1d929441da2347a0f48d85d|8399e43326dfca3da80ef78e4e8a62c3'
     or (select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_agenda::regprocedure)
       is distinct from 'c41eb0d85abd976bca03092e9a932d00|671b7fcd544e504b1ef6a1ff496261c3' then
    raise exception 'POSTFLIGHT reuniones_desglose_con_bajas: el cuerpo o la definición aplicada de una puerta no es la ensayada (reuniones %, agenda %)',
      (select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_reuniones::regprocedure),
      (select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_agenda::regprocedure);
  end if;
  if (select string_agg(p.oid::regprocedure::text || '|' || p.proowner::regrole::text || '|' || p.prosecdef::text
        || '|' || coalesce(p.proconfig::text, '-') || '|' || coalesce(p.proacl::text, '-')
        || '|' || p.provolatile::text || '|' || p.proparallel::text || '|' || p.proleakproof::text
        || '|' || p.prorettype::regtype::text
        || '|' || (select l.lanname from pg_language l where l.oid = p.prolang)::text, E'\n' order by p.oid::regprocedure::text)
        from pg_proc p where p.oid in (v_reuniones::regprocedure, v_agenda::regprocedure))
     is distinct from current_setting('crm.bajas_puertas_ficha_previa', true) then
    raise exception 'POSTFLIGHT reuniones_desglose_con_bajas: cambió el dueño, la ACL o un atributo de una puerta';
  end if;
  if obj_description(v_reuniones::regprocedure, 'pg_proc') is distinct from
       'Puerta de las métricas de citas para Gerencia o un lector global (los demás reciben 42501). Hoy la consume el Resumen de Gerencia, que solo lee resumen y conversion; el panel que pinta el desglose por responsable (ReunionesGerenciaPanel, de HoyGerencia) no se monta en ninguna ruta, y la pantalla viva de citas de Gerencia y Supervisión usa crm.citas_gerencia_consulta_fn (la marca llega allí con el bloque 2.14, D-53). El desglose por responsable pasa por private.desglose_responsables_reuniones_crm y queda como coherencia de la API: el analista o supervisor dado de baja (ficha de crm.equipo inactiva) o suspendido en el Portal (ficha activa, perfil inactivo) sigue con sus citas y "de_baja": true o "suspendido": true en su elemento, y lo que queda fuera (citas sin responsable, de otros roles) va a una fila «Otros» al final con "otros": true: el desglose suma siempre el total (bloque 2.12: D-43, D-46 y D-47, 09/10/2026). Sin bajas, suspendidos ni «Otros» en la ventana, la respuesta es idéntica a la anterior.'
     or obj_description(v_agenda::regprocedure, 'pg_proc') is distinct from
       'Puerta del panel «Agenda del equipo» (analista, supervisor, Gerencia o lector global; los demás reciben 42501); el ámbito lo decide private.metricas_agenda_implementacion. El listado pasa por private.filtrar_desglose_sujetos_con_bajas_crm: el analista o supervisor dado de baja (ficha inactiva) o suspendido en el Portal (ficha activa, perfil inactivo) sigue con "de_baja": true o "suspendido": true SOLO si tiene actividad en el período (las nueve claves de tieneActividad de la app); sin ella, fuera como antes (bloque 2.12: D-48, y D-54 para «suspendido», que también ven el supervisor, solo de su subárbol, y Directorio; 09/10/2026). Sin bajas ni suspendidos con actividad, la respuesta es idéntica a la anterior. La app valida esta respuesta con un objeto estricto: se publica ANTES la app que acepta las marcas.' then
    raise exception 'POSTFLIGHT reuniones_desglose_con_bajas: el comentario de una puerta no quedó';
  end if;
  -- 2. Las piezas nuevas: su cuerpo y su definición (huellas exactas), su ficha y su comentario.
  if to_regprocedure(v_filtro) is null or to_regprocedure(v_pieza) is null then
    raise exception 'POSTFLIGHT reuniones_desglose_con_bajas: no quedó una pieza nueva';
  end if;
  if (select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_filtro::regprocedure)
       is distinct from '4980e12d69eccd74daee5e27967abcd6|e1ea83ff4c82452cfa9d74c5b70f8e0d'
     or (select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_pieza::regprocedure)
       is distinct from '041b9ca65e6948b32d2a50a8d4479711|671a0b3db8d5e5ea4056c13c786c6b32' then
    raise exception 'POSTFLIGHT reuniones_desglose_con_bajas: una pieza nueva no es la ensayada (filtro %, reuniones %)',
      (select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_filtro::regprocedure),
      (select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_pieza::regprocedure);
  end if;
  if exists (
       select 1 from unnest(array[v_filtro, v_pieza]) f
       where not exists (select 1 from pg_proc p
                          where p.oid = to_regprocedure(f)
                            and p.proowner = 'postgres'::regrole::oid and not p.prosecdef and p.provolatile = 's'
                            and p.proconfig = array['search_path=""'])
          or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
                from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
               where p.oid = to_regprocedure(f))
             is distinct from array['postgres:EXECUTE:false']
          or has_function_privilege('anon', f, 'EXECUTE')
          or has_function_privilege('authenticated', f, 'EXECUTE')
          or has_function_privilege('service_role', f, 'EXECUTE')) then
    raise exception 'POSTFLIGHT reuniones_desglose_con_bajas: las piezas nuevas deben ser de postgres, security invoker, STABLE, con search_path vacío y SIN EXECUTE para nadie más que el dueño';
  end if;
  if obj_description(v_filtro::regprocedure, 'pg_proc') is distinct from
       'Listado por sujeto de una métrica CON los dados de baja y los suspendidos (bloque 2.12: D-43, D-46, D-48 y D-54, 09/10/2026). Deja, sin tocar su elemento, exactamente a quien deja private.filtrar_desglose_sujetos_crm (private.rol_crm dentro de p_roles) y además conserva a quien tiene una ficha de crm.equipo de uno de p_roles y hoy está dado de baja (ficha inactiva, la regla de private.analista_dado_de_baja: "de_baja": true) o suspendido en el Portal (ficha activa y perfil activo is not true: "suspendido": true), si p_claves_actividad es nulo o alguna de esas claves de su elemento es distinta de cero; si su nombre está vacío o en blanco, sale como «(sin nombre)». Sin ficha, sin identidad o con ficha y perfil activos pero sin rol efectivo, no entra. No concede autoridad: solo nombra. Sin bajas ni suspendidos, la salida es idéntica a la del filtro común. La usan crm.metricas_agenda_fn y private.desglose_responsables_reuniones_crm.'
     or obj_description(v_pieza::regprocedure, 'pg_proc') is distinct from
       'Desglose por responsable de crm.metricas_reuniones_fn (bloque 2.12: D-43, D-46 y D-47, 09/10/2026): private.filtrar_desglose_sujetos_con_bajas_crm con analistas y supervisores (sin condición de actividad: todo elemento tiene citas) y, si queda alguien fuera (citas sin responsable, de Gerencia o Coordinación, de un ex Gerencia de baja, de un perfil sin rol efectivo), una fila «Otros» al final con las mismas columnas: responsable_id nulo, nombre «Otros», supervisor «—» y "otros": true; cada cifra es la de todos los elementos de la implementación menos la de los que quedaron en el desglose, y pct_realizacion se recalcula como en la implementación. Así el desglose suma siempre el total. Sin nadie fuera, no añade nada.' then
    raise exception 'POSTFLIGHT reuniones_desglose_con_bajas: el comentario de una pieza nueva no quedó';
  end if;
  -- 3. Lo que no se toca, intacto: las dependencias (mismas fichas que en el preflight), las otras tres puertas, los dos
  --    censos y el registro analítico.
  select string_agg(e.objeto, ', ' order by e.objeto) into v_distintas
    from (values
      ('private.filtrar_desglose_sujetos_crm(jsonb,text,text,text[])',
       '1cce2929af369715a2c7e161d63fc7ce|2652303501f4e7ca1d55d37ede3fd24a|postgres|postgres:EXECUTE:false'),
      ('private.rol_crm(uuid)',
       'd2878a210be96ac85973d51dfcfb27a5|99827f3fe2fbc3cfae5668c30015c758|postgres|authenticated:EXECUTE:false,postgres:EXECUTE:false'),
      ('private.es_lector_global()',
       'c7c5828be6d74121a1a0ef0de374f712|c8be602f84348a0125617995802db618|postgres|authenticated:EXECUTE:false,postgres:EXECUTE:false'),
      ('private.metricas_reuniones_implementacion(date,date)',
       'ca6fe61e76bcb8bf2d213acb1b7fc030|ce852e3740f60a57938e2baf2c0b736d|postgres|postgres:EXECUTE:false'),
      ('private.metricas_agenda_implementacion(date,date)',
       '0fc09f917a816013e1af16ef183012de|5cb341dc430b7441ff8abdd3c8110c60|postgres|postgres:EXECUTE:false'),
      ('private.vendedor_ids_visibles(uuid)',
       '33ece9bae4828f7ffdb837c6128ca9d6|85544c70a0920f3a7a1b5da06935f236|postgres|authenticated:EXECUTE:false,postgres:EXECUTE:false')
    ) e(objeto, ficha)
   where e.ficha is distinct from (select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) || '|' || p.proowner::regrole::text || '|'
           || (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ','
                                 order by a.grantee::regrole::text, a.privilege_type)
                 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a)
                                     from pg_proc p where p.oid = to_regprocedure(e.objeto));
  if v_distintas is not null then
    raise exception 'POSTFLIGHT reuniones_desglose_con_bajas: cambió algo que esta migración no debía tocar: %', v_distintas;
  end if;
  if (select string_agg(o.objeto || '=' || coalesce((select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) || '|' || p.proowner::regrole::text || '|'
               || (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ','
                                     order by a.grantee::regrole::text, a.privilege_type)
                     from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a)
                                              from pg_proc p where p.oid = to_regprocedure(o.objeto)), 'FALTA'),
                    E'\n' order by o.objeto)
       from (values ('crm.metricas_conversiones_fn(date,date,text)'), ('crm.metricas_conversiones_equipo_fn(date,date)'),
                    ('crm.conversion_mensual_sin_cartera_fn(date)')) o(objeto)) is distinct from current_setting('crm.bajas_otras_puertas', true) then
    raise exception 'POSTFLIGHT reuniones_desglose_con_bajas: cambió una de las otras tres puertas que usan el filtro común (conversiones, conversiones del equipo o conversión mensual)';
  end if;
  if (select coalesce(string_agg(c.tipo || ' ' || c.objeto || ' ' || c.declarada::text || ' ' || c.huella_ok::text,
                              E'\n' order by c.tipo, c.objeto), '(vacío)')
       from private.contadores_crudos_leads_citas() c) is distinct from current_setting('crm.bajas_censo_analitico', true)
     or (select coalesce(string_agg(c.tipo || ' ' || c.objeto || ' ' || c.declarada::text || ' ' || c.huella_ok::text,
                              E'\n' order by c.tipo, c.objeto), '(vacío)')
       from private.puertas_analista_sin_vigencia() c) is distinct from current_setting('crm.bajas_censo_vigencia', true) then
    raise exception 'POSTFLIGHT reuniones_desglose_con_bajas: cambió el censo de contadores crudos de leads/citas o el de puertas sin vigencia del analista (las puertas o las piezas no pueden entrar en ellos)';
  end if;
  if (coalesce((select to_jsonb(e)::text from private.analitica_leads_citas_exenciones e
                where e.objeto = 'private.metricas_reuniones_implementacion(date,date)'), 'sin fila')
       || ' · sello ' || coalesce((select s.sello from private.analitica_lc_sello s where s.id), 'sin sello')) is distinct from current_setting('crm.bajas_registro_analitico', true) then
    raise exception 'POSTFLIGHT reuniones_desglose_con_bajas: cambió la exención analítica de la implementación o el sello (esta migración no los toca)';
  end if;
  -- 4. La FOTO de los private.assert_*() (sin los `*_mutantes`), EXACTAMENTE la misma que antes de la migración.
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
  if v_foto is distinct from current_setting('crm.bajas_trinquetes_previos', true) then
    raise exception E'POSTFLIGHT reuniones_desglose_con_bajas: algún private.assert_*() da otro resultado que antes de la migración.\nANTES:\n%\nDESPUÉS:\n%',
      current_setting('crm.bajas_trinquetes_previos', true), v_foto;
  end if;
  raise notice 'POSTFLIGHT reuniones_desglose_con_bajas: puertas de reuniones e448db0c… y agenda c41eb0d8… · piezas 4980e12d… y 041b9ca6… · % trinquetes con estado y texto íntegro del primer error idénticos a los previos',
    v_gates;
end
$postflight$;

commit;

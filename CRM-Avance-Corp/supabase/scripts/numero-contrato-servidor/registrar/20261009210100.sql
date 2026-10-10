-- REGISTRO en supabase_migrations.schema_migrations de 20261009210100_crm_numero_contrato_servidor (bloque 2.3 del grupo A).
-- GENERADO por generar_registrador.py: no editar a mano. `db query --linked --file` NO registra: correr DESPUÉS de aplicar la
-- migración, por la misma vía. Desde `CRM-Avance-Corp/`, en este orden (el Director lo ensaya antes en la branch), tras el
-- 2.6 y su registrador (supabase/scripts/anular-venta-mes-sellado/registrar/20261009210000.sql):
--   0. (solo lectura) supabase db query --linked --file supabase/scripts/numero-contrato-servidor/candidatos-sonda.sql
--      dice qué pares vendedor–cliente probaría la sonda del postflight y si concluirían.
--   1. supabase db query --linked --file supabase/migrations/20261009210100_crm_numero_contrato_servidor.sql
--      Por `db query --linked` el NOTICE de la sonda NO llega: SIN ERROR = LA SONDA RECHAZÓ («RECHAZADO con 22023 y el
--      mensaje fijado»; si acepta, si no concluye con ningún candidato o si no hay candidatos, la migración aborta con un error
--      que lo explica y no aplica nada). Qué candidato concluyó solo se ve en la branch (psql, que sí muestra el NOTICE).
--   2. supabase db query --linked --file supabase/scripts/numero-contrato-servidor/registrar/20261009210100.sql
-- Por `db query --linked` no llegan los NOTICE; llega la última fila (va tras el COMMIT, como en las migraciones de la casa):
-- registrado = sin error y la fila «20261009210100 | ddf1b5f1f0762d1400c2806b36db50a2».
-- Un error = no registró nada (todo va en una transacción).
-- Idempotente (correrlo dos veces deja una sola fila). Se NIEGA, sin escribir nada, si:
--   · el estado instalado de public.crear_contrato(jsonb,jsonb) no es el que deja la migración: cuerpo, definición entera, ficha
--     (dueño, security definer, search_path), ACL efectiva, EXECUTE efectivo (anon sin; authenticated y service_role con) y
--     comentario;
--   · el nombre crm_numero_contrato_servidor ya está registrado con OTRA versión (p. ej. 20261009160100, la de las rondas 1 a 3);
--   · la versión 20261009210100 ya está registrada con otro nombre u otro contenido.
-- statements = el archivo entero (md5 ddf1b5f1f0762d1400c2806b36db50a2),
-- incrustado UNA sola vez en la tabla temporal pg_temp.registro_20261009210100 (on commit drop).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_numero_contrato_servidor_registro'));
create temp table registro_20261009210100 on commit drop as
select $mig$-- EL SERVIDOR EXIGE EL NÚMERO DE CONTRATO — `public.crear_contrato` rechaza cualquier número que no sea
-- `2024-01-NNNNNN`, `2025-01-NNNNNN` o `2026-01-NNNNNN` (seis dígitos ASCII), incluido el vacío, un espacio o
-- la ausencia de la clave, en vez de inventar `AC-AAAA-NNNN`. Cubre la llamada directa a la API (`authenticated`
-- y `service_role`) y las puertas `crm.*` que la envuelven, porque la guarda vive dentro de la función común.
--
-- QUÉ PASABA. `public.crear_contrato` (definición `20260908211349:3271` más el parche de tasas `20260914042114`)
-- recortaba el número (`nullif(btrim(...), '')`), y si quedaba nulo lo inventaba con
-- `private.siguiente_numero_contrato(año de Lima)` (`AC-AAAA-NNNN`); solo comprobaba que no estuviera duplicado.
-- No había validación de forma: `ABC`, `2026-01-12` o `2027-01-000009` entraban como números de contrato. Hoy la
-- forma la valida solo la pantalla (`contrato-nuevo.tsx:578-583`), y la API no depende de ella.
--
-- QUÉ HACE. Inserta, justo antes de la rama de autogeneración, una guarda sobre el número YA recortado:
--   si `v_numero` es nulo O no cumple `^(2024|2025|2026)-01-[0-9]{6}$` ⇒ SQLSTATE `22023` y el mensaje
--   «Formato de número de contrato inválido: serie 2024-01-, 2025-01- o 2026-01- seguida de exactamente 6 dígitos».
--   · Se usa `[0-9]` y no `\d` (`\d` casa dígitos no ASCII en este Postgres). El 01 es fijo, no es el mes.
--   · La lista de series es FIJA: no depende del año actual (la serie 2027 es trabajo aparte, de Miguel).
--   · El código 22023 es la convención del repo; el mensaje lleva «formato» y «número» porque el banco del
--     laboratorio lo exige (`laboratorio/paquete-paso08/42_fila2_inversion.py:17-18`).
--   · Excepción (D-17): quien cumple `public.es_admin()` Y `private.es_gerencia_crm_activa()` salta la guarda y
--     conserva el comportamiento de hoy (autogenera `AC-AAAA-NNNN` si va vacío y acepta cualquier número no
--     duplicado). Por eso `private.siguiente_numero_contrato` sigue en uso. Sin sesión de usuario (`auth.uid()`
--     nulo, p. ej. `service_role`) `es_admin()` da falso: no hay excepción.
--   · El duplicado conserva su error de siempre (`P0001`, «El N de contrato % ya existe»). La guarda va ANTES: un
--     número fuera de forma que además existe recibe el error de formato.
--   · El resto del cuerpo es, byte a byte, el vigente; firma, dueño, `security definer`, `search_path` vacío y
--     ACL (`authenticated`, `service_role`; sin `anon`) no cambian.
--
-- QUÉ NO CAMBIA. Los contratos existentes (en producción, 750 de 750 con número válido el 06/10) y las
-- renovaciones, upgrades y ediciones sobre filas viejas: la regla solo mira el ALTA, es decir el contrato nuevo.
-- Un contrato histórico `AC-…` renovado conserva su número. No se toca `crm.*`, `private.siguiente_numero_contrato`,
-- `public.actualizar_numero_contrato` (es otro paso, con plan propio), tablas, grants ni policies. Descartado: un
-- `CHECK` de tabla (rompería las renovaciones sobre contratos viejos).
--
-- CÓMO SE CAMBIA LA FUNCIÓN. Por ancla única sobre el cuerpo vivo (`pg_get_functiondef` + `replace`, patrón de
-- `20260914042114`): el ancla tiene que aparecer EXACTAMENTE una vez o la migración aborta. Y solo se instala sobre
-- lo que se auditó:
--   · `md5(prosrc)` 1adfbe1a… y `md5(pg_get_functiondef)` dce8f0dd… de `public.crear_contrato`, su ficha (dueño
--     `postgres`, DEFINER, `search_path` vacío, ACL exacta con opción de concesión) y su comentario;
--   · los cinco objetos de los que dependen la excepción, quién llega a la guarda y el autogenerado del exento
--     (`public.es_admin`, `private.es_gerencia_crm_activa`, `private.rol_crm`, `private.puede_registrar_ventas` y
--     `private.siguiente_numero_contrato`), por su huella Y por su ficha completa: dueño, `security definer`,
--     volatilidad, modo paralelo, `proconfig` y ACL completa con opción de concesión (valores medidos en el laboratorio
--     el 07/10/2026). Un `ALTER FUNCTION private.rol_crm(uuid) IMMUTABLE`, otro `search_path`, un `GRANT … WITH GRANT
--     OPTION` o un cambio de dueño conservan el `md5(prosrc)` y cambiarían lo que esta regla garantiza: se niega;
--   · que EXISTAN `private.assert_analista_vigencia()` y `private.assert_f7_piezas_cerradas()`: sin ellos no se puede
--     exigir que no cambien, y la migración no se aplica (fail-closed).
-- POSTFLIGHT FAIL-CLOSED. Vuelve a exigir la ficha idéntica de la función y de los cinco helpers, el cuerpo ensayado
-- (huella exacta), que los dos `assert_*` existan y den EXACTAMENTE el mismo resultado que antes (en el laboratorio el
-- primero ya cae por trabajos ajenos: se exige que no cambie, no que pase), y una SONDA que es GATE: recorre hasta 5
-- CANDIDATOS (vendedor activo —rol `comercial` en el Portal, ficha `vendedor` activa en `crm.equipo`— × cliente activo de su
-- cartera), en orden determinista (vendedor, cliente), y cada uno manda «ABC» por `public.crear_contrato` dentro de una
-- subtransacción que SIEMPRE se deshace (ejecuta código de negocio real sobre filas reales, pero nada queda). Se detiene en el
-- primer resultado concluyente: «RECHAZADO con 22023 y el mensaje fijado» ⇒ pasa; «ACEPTÓ» ⇒ aborta; «no concluyente» (la
-- llamada murió ANTES de la guarda, p. ej. cliente sin documento) ⇒ siguiente candidato. Si NINGÚN candidato es concluyente,
-- o no hay candidatos, la migración SE NIEGA: el mensaje enumera cada candidato probado con su causa y dice exactamente qué
-- preparar (un vendedor activo con un cliente activo CON DOCUMENTO en su cartera); después, volver a aplicar. El NOTICE
-- final dice qué candidato concluyó y cuántos se probaron.
--
-- CONSECUENCIAS (para quien integre).
--   · La huella de `public.crear_contrato` CAMBIA. La registran, y se negarían a correr DESPUÉS de esta migración:
--     `scripts/tasa-baja/revertir-antes-del-primer-uso.sql:27` (`md5(prosrc)` 1adfbe1a…: es el revertidor del
--     parche de tasas, histórico) y, como `md5(pg_get_functiondef)` dce8f0dd…, `scripts/multiempresa-f9/apertura-2026-09-15/
--     {ACTIVAR,POSTFLIGHT,REVERTIR}.sql` (y `revision-1/`) y las evidencias JSON de F8/F9. NO se cambian aquí. La huella de
--     `crm.crear_contrato_con_cuenta` (F7: `22ec068f…`, `20260925210000`) NO cambia: no se toca.
--   · Una solicitud de inversión preparada SIN número (puerta `cartera`) fallaría al confirmarse tras el despliegue:
--     repetir el conteo de solicitudes preparadas justo antes de desplegar (fase 4).
--   · Serie 2027: sin ella, enero de 2027 bloquea las altas (tope anotado 15/12/2026 para preparar CRM, Portal y servidor
--     a la vez).
--   · Pruebas locales que usan el autogenerado o números libres dejan de pasar para un no exento (inventario en el
--     informe del bloque): se pueden conservar corriéndolas como exento.
--   · EL GATE `supabase/scripts/test-rls.mjs` QUEDA ROTO tras esta migración (no se toca aquí; su adaptación es de la fase
--     4, antes de correrlo contra el branch): `payloadIdem` (`:5507-5543`) arma `numero_contrato` libre `RLS-IDEM-…` y lo
--     usan altas positivas de `vend1` (no exento) en `:5543, 5564, 5602, 5612, 5619, 5637, 5664-5665, 5695`, con negativos
--     que dependen de ellas en `:5558, 5576, 5590, 5631`; y el caso `:5119-5137` (directorio-como-analista, sin número)
--     espera `23514` y recibirá `22023` antes del INSERT. Adaptación: `payloadIdem` con `2026-01-` + 6 dígitos aleatorios
--     sin colisionar con `990001`/`990002` (`BANK_CONTRACT.number`, que SÍ es válido) y el caso 5119 con un número válido
--     para que siga midiendo `23514`; más los 8 casos nuevos de la regla que pide el auditor (informe del bloque). Antes de
--     adaptarlo, correr `npm run test:rls:preflight` tal como está para medir el ROJO real.
--   · El exento sigue generando `AC-AAAA-NNNN` (deuda de DATOS de D-17, no de seguridad): la pantalla del CRM no admite ese
--     formato (`app/src/lib/contratos-catalogo.ts`) hasta el paso aparte de `public.actualizar_numero_contrato` (D-16); y
--     el duplicado que el exento mete a mano lo detecta el `if exists` sin serializar, respaldado por el UNIQUE
--     `contratos_numero_contrato_key` de `public.contratos.numero_contrato` (del portal).
--   · RUNBOOK DEL BRANCH: la migración solo confirma si la sonda del postflight dice «RECHAZADO con 22023 y el mensaje
--     fijado» (leer el NOTICE: dice qué candidato concluyó, cuántos se probaron y cuáles se descartaron). Si se niega
--     (sin candidatos, o ninguno concluyente), el mensaje enumera cada candidato probado con su causa: LA ÚNICA SALIDA es
--     preparar en el branch un vendedor activo con un cliente activo CON DOCUMENTO en su cartera (el mensaje lo describe) y
--     volver a aplicar. El oráculo `supabase/scripts/numero-contrato-servidor/` con `--sin-migracion` y la prueba HTTP N1/N1b
--     del banco son DIAGNÓSTICOS: miden la función que haya en la base (tras un aborto, la ANTERIOR) y NO sustituyen una
--     migración abortada ni desbloquean el gate.
--
-- A QUÉ PLAN RESPONDE. Plan de mantenibilidad del backend del CRM (AVANCE-BACKEND-0610), fase 2, bloque 2.3
-- (decisiones D-11/Q3, D-12/Q3b, D-16 y D-17 de Miguel, 2026-10-06/07). Ronda 2 tras las revisiones de Codex y del
-- auditor de permisos (2026-10-07, CHANGES_REQUESTED sin P0, conciliadas por el Director en
-- `fase-2/bloque-2.3/revision/CONCILIACION.md`: ficha completa de los helpers, postflight fail-closed con la sonda como
-- gate, conteo de 24 formas inválidas, cabecera, gate `test-rls.mjs` declarado roto y deuda de datos del exento). Ronda 3
-- tras la segunda revisión de Codex (2026-10-07, P2 R2-1, `revision/CONCILIACION-R2.md`): la sonda prueba hasta 5
-- candidatos y el runbook deja claro que el oráculo y la prueba HTTP son diagnósticos, no una salida al gate.
--
-- VERIFICACIÓN. `supabase/scripts/numero-contrato-servidor/`: el oráculo sale ROJO sin esta migración (el servidor
-- acepta, o autogenera, un número fuera de forma) y VERDE con ella; sus mutantes mueren por su fallo; las derivas
-- previas la hacen abortar sin dejar rastro (en el preflight; en el postflight las que dejan la sonda sin candidatos o sin
-- ninguno concluyente), y con el primer candidato no concluyente la sonda concluye con el segundo y la migración entra;
-- la reversa devuelve las huellas originales. Verificada solo en el laboratorio local.
--
-- REVERSIÓN: `supabase/scripts/numero-contrato-servidor/reversa.sql` repone el cuerpo anterior (`md5(prosrc)` vuelve a
-- 1adfbe1a… y `md5(pg_get_functiondef)` a dce8f0dd…) y su comentario. No hay datos que deshacer: la guarda solo
-- rechaza; los contratos creados por el exento (o antes de la migración) con números libres siguen como están.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $preflight$
declare
  v_a text;
  v_b text;
  v_h record;
  v_ficha text;
begin
  -- 1. El cuerpo que se reemplaza: la huella auditada, y solo ella (si ya está la guarda, también se niega).
  if to_regprocedure('public.crear_contrato(jsonb,jsonb)') is null then
    raise exception 'PREFLIGHT numero_contrato_servidor: falta public.crear_contrato(jsonb,jsonb)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure)
       is distinct from '1adfbe1a72739a1863c7321c3fd20439'
     or md5(pg_get_functiondef('public.crear_contrato(jsonb,jsonb)'::regprocedure))
       is distinct from 'dce8f0dd6d6776b960096c56bdc29173' then
    raise exception 'PREFLIGHT numero_contrato_servidor: public.crear_contrato cambió desde que se auditó (o esta migración ya está aplicada): revisar antes de añadir la guarda';
  end if;
  -- 2. Su ficha: `create or replace` conserva dueño y ACL, así que una deriva previa sobreviviría al cambio y la
  --    comparación «antes = después» del postflight la daría por buena. Identidad con lo auditado.
  if not exists (
       select 1 from pg_proc p
       where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure
         and p.proowner = 'postgres'::regrole::oid
         and p.prosecdef
         and p.proconfig = array['search_path=""'])
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p
           cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
          where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure)
        is distinct from array['authenticated:EXECUTE:false', 'postgres:EXECUTE:false', 'service_role:EXECUTE:false'] then
    raise exception 'PREFLIGHT numero_contrato_servidor: la ficha de public.crear_contrato no es la auditada (dueño postgres, security definer, search_path vacío, EXECUTE solo para el dueño, authenticated y service_role, sin opción de concesión)';
  end if;
  if obj_description('public.crear_contrato(jsonb,jsonb)'::regprocedure, 'pg_proc') is distinct from
       'Alta atómica de contrato y cronograma; renovaciones/upgrades conservan su ledger. La numeración automática usa private.siguiente_numero_contrato y es segura ante concurrencia.' then
    raise exception 'PREFLIGHT numero_contrato_servidor: el comentario de public.crear_contrato cambió desde que se auditó: revisar antes de reemplazarlo';
  end if;
  -- 3. Lo que se consulta sin tocar: si cambia, cambia lo que esta regla garantiza (quién es exento, quién llega a la
  --    guarda y el autogenerado que conserva el exento).
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.es_admin()'))
       is distinct from 'f4e01285f0b006f72b984213a6a95310'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.es_gerencia_crm_activa()'))
       is distinct from 'e2e84b58044078e40e506f623985e86d'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.rol_crm(uuid)'))
       is distinct from 'd2878a210be96ac85973d51dfcfb27a5'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.puede_registrar_ventas()'))
       is distinct from '2749bb0e5616eae42a0dd410bee4f52a'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.siguiente_numero_contrato(integer)'))
       is distinct from '921e09f03b8f2d0c468267b05729746f' then
    raise exception 'PREFLIGHT numero_contrato_servidor: cambió public.es_admin, private.es_gerencia_crm_activa, private.rol_crm, private.puede_registrar_ventas o private.siguiente_numero_contrato: la excepción del admin o el autogenerado ya no son los auditados';
  end if;
  -- 3b. Y su FICHA completa (dueño, security definer, volatilidad, modo paralelo, proconfig y ACL con opción de
  --     concesión), medida en el laboratorio el 07/10/2026. Un `ALTER FUNCTION … IMMUTABLE`, otro `search_path`, un
  --     `GRANT … WITH GRANT OPTION` o un cambio de dueño conservan el `md5(prosrc)` y cambiarían lo que esta regla garantiza.
  for v_h in
    select * from (values
      ('public.es_admin()',
       'postgres|true|s|u|search_path=public, pg_temp|authenticated:EXECUTE:false,postgres:EXECUTE:false,service_role:EXECUTE:false'),
      ('private.es_gerencia_crm_activa()',
       'postgres|true|s|u|search_path=""|postgres:EXECUTE:false'),
      ('private.rol_crm(uuid)',
       'postgres|true|s|u|search_path=""|authenticated:EXECUTE:false,postgres:EXECUTE:false'),
      ('private.puede_registrar_ventas()',
       'postgres|true|s|u|search_path=""|postgres:EXECUTE:false'),
      ('private.siguiente_numero_contrato(integer)',
       'postgres|true|v|u|search_path=""|postgres:EXECUTE:false')
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
      raise exception 'PREFLIGHT numero_contrato_servidor: la ficha de % no es la auditada (medida «%»; auditada «%»): la excepción del admin o el autogenerado ya no son los auditados', v_h.firma, coalesce(v_ficha, 'no existe'), v_h.ficha;
    end if;
  end loop;
  -- 4. La ficha de la función y el resultado de los dos trinquetes que la rodean, para exigir en el postflight que nada
  --    se movió (el trinquete de analista ya cae en el laboratorio por trabajos ajenos: se exige que NO cambie). Los dos
  --    tienen que EXISTIR: sin ellos no se puede exigir nada, y la migración no se aplica (fail-closed).
  perform set_config('crm.numero_contrato_ficha_previa',
    (select p.oid::regprocedure::text || '|' || p.proowner::regrole::text || '|' || p.prosecdef::text
        || '|' || coalesce(p.proconfig::text, '-') || '|' || coalesce(p.proacl::text, '-')
        || '|' || p.provolatile::text || '|' || p.proparallel::text || '|' || p.proleakproof::text
        || '|' || p.prorettype::regtype::text
       from pg_proc p where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure),
    true);
  if to_regprocedure('private.assert_analista_vigencia()') is null
     or to_regprocedure('private.assert_f7_piezas_cerradas()') is null then
    raise exception 'PREFLIGHT numero_contrato_servidor: falta private.assert_analista_vigencia() o private.assert_f7_piezas_cerradas() (existen: analista %, f7 %): los dos trinquetes que rodean a la función tienen que existir para exigir en el postflight que no cambian; esta migración no se aplica sin ellos (fail-closed)',
      to_regprocedure('private.assert_analista_vigencia()') is not null,
      to_regprocedure('private.assert_f7_piezas_cerradas()') is not null;
  end if;
  begin
    execute 'select private.assert_analista_vigencia()';
    v_a := 'pasa';
  exception when others then
    v_a := 'cae: ' || sqlerrm;
  end;
  begin
    execute 'select private.assert_f7_piezas_cerradas()';
    v_b := 'pasa';
  exception when others then
    v_b := 'cae: ' || sqlerrm;
  end;
  perform set_config('crm.numero_contrato_gates_previos', v_a || E'\n' || v_b, true);
end
$preflight$;

-- ── La guarda, por ancla única ─────────────────────────────────────────────────────────────────────────────────
do $patch$
declare
  v_def   text;
  v_ancla text;
  v_nueva text;
begin
  v_def := pg_get_functiondef('public.crear_contrato(jsonb,jsonb)'::regprocedure);
  v_ancla := $antes$  if v_numero is null then
    v_numero := private.siguiente_numero_contrato(v_anio);
  end if;
$antes$;
  v_nueva := $despues$  -- EL NUMERO DE CONTRATO LO EXIGE EL SERVIDOR (plan AVANCE-BACKEND-0610, bloque 2.3; D-11, D-12, D-16, D-17).
  -- Sobre el numero ya recortado: tiene que ser 2024-01-, 2025-01- o 2026-01- seguido de exactamente 6 digitos ASCII
  -- (el 01 es fijo, no es el mes; la lista de series es fija, no depende del año actual). Nulo, vacio o fuera de forma:
  -- se rechaza en vez de inventar AC-AAAA-NNNN. Unica excepcion: quien es a la vez admin/superadmin del Portal y
  -- Gerencia del CRM conserva el comportamiento anterior (autogenera si va vacio y acepta cualquier numero no
  -- duplicado). Sin sesion de usuario (auth.uid() nulo) es_admin() da falso: no hay excepcion. El duplicado conserva
  -- su error de siempre, mas abajo.
  if v_numero is null or v_numero !~ '^(2024|2025|2026)-01-[0-9]{6}$' then
    if not (public.es_admin() and private.es_gerencia_crm_activa()) then
      raise exception 'Formato de número de contrato inválido: serie 2024-01-, 2025-01- o 2026-01- seguida de exactamente 6 dígitos'
        using errcode = '22023';
    end if;
  end if;
  if v_numero is null then
    v_numero := private.siguiente_numero_contrato(v_anio);
  end if;
$despues$;
  if cardinality(string_to_array(v_def, v_ancla)) <> 2 then
    raise exception 'PATCH numero_contrato_servidor: el ancla de la autogeneración no es única en public.crear_contrato';
  end if;
  execute replace(v_def, v_ancla, v_nueva);
end
$patch$;

comment on function public.crear_contrato(jsonb, jsonb) is
  'Alta atómica de contrato y cronograma; renovaciones/upgrades conservan su ledger. La numeración automática usa private.siguiente_numero_contrato y es segura ante concurrencia. EL NÚMERO LO EXIGE EL SERVIDOR (bloque 2.3): tiene que ser 2024-01-, 2025-01- o 2026-01- seguido de exactamente 6 dígitos; nulo, vacío o fuera de forma se rechaza con 22023 y «Formato de número de contrato inválido…». Única excepción: quien es admin/superadmin del Portal Y Gerencia del CRM conserva el autogenerado AC-AAAA-NNNN y acepta cualquier número no duplicado. El duplicado conserva su error. Solo mira el alta: renovaciones y upgrades sobre contratos viejos no cambian.';

-- ── Postflight ───────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_a text;
  v_b text;
  v_h record;
  v_ficha text;
  v_obtenida text;
  v_actor uuid;
  v_cliente uuid;
  v_sonda text;
  v_c record;
  v_probados integer := 0;
  v_causas text := '';
  v_hoy date := (now() at time zone 'America/Lima')::date;
begin
  -- La guarda quedó, con la regla, el mensaje fijado y la rama del exento que conserva el autogenerado.
  if (select position('^(2024|2025|2026)-01-[0-9]{6}$' in p.prosrc) = 0
             or position('Formato de número de contrato inválido: serie 2024-01-, 2025-01- o 2026-01- seguida de exactamente 6 dígitos' in p.prosrc) = 0
             or position('22023' in p.prosrc) = 0
             or position('public.es_admin() and private.es_gerencia_crm_activa()' in p.prosrc) = 0
             or position('private.siguiente_numero_contrato(v_anio)' in p.prosrc) = 0
        from pg_proc p where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure) then
    raise exception 'POSTFLIGHT numero_contrato_servidor: la guarda no quedó en public.crear_contrato';
  end if;
  -- El cuerpo nuevo es el que se ensayó (huella exacta).
  select md5(p.prosrc) into v_obtenida from pg_proc p where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure;
  if v_obtenida is distinct from 'dee13ad8e1e16e066ba1ba623c0dda6b' then
    raise exception 'POSTFLIGHT numero_contrato_servidor: el cuerpo de public.crear_contrato no es el ensayado (huella obtenida %)', v_obtenida;
  end if;
  -- Dueño, ACL y atributos, intactos (y sin anon).
  if (select p.oid::regprocedure::text || '|' || p.proowner::regrole::text || '|' || p.prosecdef::text
        || '|' || coalesce(p.proconfig::text, '-') || '|' || coalesce(p.proacl::text, '-')
        || '|' || p.provolatile::text || '|' || p.proparallel::text || '|' || p.proleakproof::text
        || '|' || p.prorettype::regtype::text
       from pg_proc p where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure)
     is distinct from current_setting('crm.numero_contrato_ficha_previa', true) then
    raise exception 'POSTFLIGHT numero_contrato_servidor: cambió el dueño, la ACL o un atributo de public.crear_contrato';
  end if;
  if not exists (
       select 1 from pg_proc p
       where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure
         and p.proowner = 'postgres'::regrole::oid and p.prosecdef
         and p.proconfig = array['search_path=""'])
     or has_function_privilege('anon', 'public.crear_contrato(jsonb,jsonb)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.crear_contrato(jsonb,jsonb)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.crear_contrato(jsonb,jsonb)', 'EXECUTE') then
    raise exception 'POSTFLIGHT numero_contrato_servidor: public.crear_contrato debe ser security definer con search_path vacío, con EXECUTE para authenticated y service_role y SIN EXECUTE para anon';
  end if;
  -- Lo que no se toca, intacto.
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.siguiente_numero_contrato(integer)'))
       is distinct from '921e09f03b8f2d0c468267b05729746f'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.actualizar_numero_contrato(uuid,text,text,text)'))
       is distinct from '44270f9706a4515b16962ead8b09ea59'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)'))
       is distinct from '22ec068ff5d27312c5eb0749600292fd'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'))
       is distinct from '505598d6fef7ea585a965f925a8eb9fb'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.es_admin()'))
       is distinct from 'f4e01285f0b006f72b984213a6a95310'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.es_gerencia_crm_activa()'))
       is distinct from 'e2e84b58044078e40e506f623985e86d'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.rol_crm(uuid)'))
       is distinct from 'd2878a210be96ac85973d51dfcfb27a5'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.puede_registrar_ventas()'))
       is distinct from '2749bb0e5616eae42a0dd410bee4f52a' then
    raise exception 'POSTFLIGHT numero_contrato_servidor: cambió algo que esta migración no debía tocar (siguiente_numero_contrato, actualizar_numero_contrato, crm.crear_contrato_con_cuenta[_pdf_v2], es_admin, es_gerencia_crm_activa, rol_crm o puede_registrar_ventas)';
  end if;
  -- Y la ficha completa de los cinco helpers sigue siendo la auditada (la misma tabla que exigió el preflight).
  for v_h in
    select * from (values
      ('public.es_admin()',
       'postgres|true|s|u|search_path=public, pg_temp|authenticated:EXECUTE:false,postgres:EXECUTE:false,service_role:EXECUTE:false'),
      ('private.es_gerencia_crm_activa()',
       'postgres|true|s|u|search_path=""|postgres:EXECUTE:false'),
      ('private.rol_crm(uuid)',
       'postgres|true|s|u|search_path=""|authenticated:EXECUTE:false,postgres:EXECUTE:false'),
      ('private.puede_registrar_ventas()',
       'postgres|true|s|u|search_path=""|postgres:EXECUTE:false'),
      ('private.siguiente_numero_contrato(integer)',
       'postgres|true|v|u|search_path=""|postgres:EXECUTE:false')
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
      raise exception 'POSTFLIGHT numero_contrato_servidor: la ficha de % cambió durante la migración (medida «%»)', v_h.firma, coalesce(v_ficha, 'no existe');
    end if;
  end loop;
  -- Los dos trinquetes que rodean a la función EXISTEN y dan EXACTAMENTE lo mismo que antes (fail-closed: un «no existe»
  -- no es un resultado que se pueda comparar).
  if to_regprocedure('private.assert_analista_vigencia()') is null
     or to_regprocedure('private.assert_f7_piezas_cerradas()') is null then
    raise exception 'POSTFLIGHT numero_contrato_servidor: falta private.assert_analista_vigencia() o private.assert_f7_piezas_cerradas() tras la migración: no se puede comprobar que no cambian (fail-closed)';
  end if;
  begin
    execute 'select private.assert_analista_vigencia()';
    v_a := 'pasa';
  exception when others then
    v_a := 'cae: ' || sqlerrm;
  end;
  begin
    execute 'select private.assert_f7_piezas_cerradas()';
    v_b := 'pasa';
  exception when others then
    v_b := 'cae: ' || sqlerrm;
  end;
  if (v_a || E'\n' || v_b) is distinct from current_setting('crm.numero_contrato_gates_previos', true) then
    raise exception 'POSTFLIGHT numero_contrato_servidor: private.assert_analista_vigencia() o private.assert_f7_piezas_cerradas() dan otro resultado que antes de la migración (ahora: % / %)', v_a, v_b;
  end if;
  -- SONDA (GATE): un NO exento (vendedor activo, rol comercial en el Portal) que manda «ABC» tiene que recibir el rechazo.
  -- Recorre hasta 5 CANDIDATOS (vendedor activo de crm.equipo × cliente activo de su cartera), en orden determinista
  -- (vendedor, cliente), y se detiene en el PRIMER resultado concluyente: «RECHAZADO con 22023 y el mensaje fijado» ⇒ la
  -- sonda pasa; «ACEPTÓ» ⇒ la migración aborta; «no concluyente: <SQLSTATE> <mensaje>» (la llamada murió ANTES de llegar a la
  -- guarda, p. ej. un cliente sin documento con la identidad unificada encendida) ⇒ se prueba el siguiente candidato. Cada
  -- intento va en su propia subtransacción que SIEMPRE se deshace (si el servidor aceptara, el contrato de ensayo no queda):
  -- ejecuta código de negocio real sobre filas reales, pero nada queda escrito. FAIL-CLOSED: si NINGÚN candidato es
  -- concluyente (o no hay candidatos), la migración SE NIEGA y el mensaje enumera cada candidato probado con su causa y dice
  -- exactamente qué preparar. El NOTICE final dice qué candidato concluyó y cuántos se probaron.
  -- Vendedor activo con rol comercial en el Portal Y un cliente activo DE SU CARTERA (si el cliente fuera ajeno, la llamada
  -- moriría antes de la guarda con el 42501 de cartera y la sonda no diría nada).
  for v_c in
    select e.perfil_id as actor, c.id as cliente
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    join public.perfiles c on c.asesor_perfil_id = e.perfil_id and c.rol = 'cliente' and c.activo
    where e.rol_crm = 'vendedor' and e.activo and p.activo and p.rol = 'comercial'
      and private.rol_crm(e.perfil_id) = 'vendedor'
    order by e.perfil_id, c.id
    limit 5
  loop
    v_probados := v_probados + 1;
    v_sonda := null;
    begin
      perform set_config('request.jwt.claim.sub', v_c.actor::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_c.actor, 'role', 'authenticated')::text, true);
      perform public.crear_contrato(
        jsonb_build_object('numero_contrato', 'ABC', 'cliente_id', v_c.cliente, 'capital', 500, 'moneda', 'PEN',
          'tasa_anual', 15, 'modalidad', 'mensual', 'tipo_interes', 'simple', 'fecha_inicio', v_hoy,
          'fecha_vencimiento', v_hoy + 365, 'categoria', 'nuevo', 'analista_cierre_id', v_c.actor),
        jsonb_build_array(jsonb_build_object('numero_cuota', 1, 'fecha_programada', v_hoy + 30, 'monto_programado', 100, 'tipo', 'cuota')));
      v_sonda := 'ACEPTÓ';
      raise exception using errcode = 'ZZRB3', message = 'deshacer el contrato de la sonda';
    exception
      when sqlstate 'ZZRB3' then
        null;
      when others then
        if sqlstate = '22023' and sqlerrm = 'Formato de número de contrato inválido: serie 2024-01-, 2025-01- o 2026-01- seguida de exactamente 6 dígitos' then
          v_sonda := 'RECHAZADO con 22023 y el mensaje fijado';
        else
          v_sonda := 'no concluyente: ' || sqlstate || '|' || sqlerrm;
        end if;
    end;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    if v_sonda = 'ACEPTÓ' then
      raise exception 'POSTFLIGHT numero_contrato_servidor: un vendedor (no exento, %) logró crear un contrato con el número «ABC» para su cliente % (candidato % de la sonda): la guarda no rechaza', v_c.actor, v_c.cliente, v_probados;
    end if;
    if v_sonda = 'RECHAZADO con 22023 y el mensaje fijado' then
      v_actor := v_c.actor;
      v_cliente := v_c.cliente;
      exit;
    end if;
    v_causas := v_causas || E'\n  · candidato ' || v_probados || ': vendedor ' || v_c.actor || ', cliente ' || v_c.cliente || ' → ' || v_sonda;
  end loop;
  if v_probados = 0 then
    raise exception 'POSTFLIGHT numero_contrato_servidor: la sonda «ABC» no se pudo ejecutar: en esta base no hay ningún candidato, es decir un vendedor activo (public.perfiles.rol = comercial y activo; crm.equipo.rol_crm = vendedor y activo) con un cliente activo en su cartera (public.perfiles.rol = cliente, activo, asesor_perfil_id = ese vendedor). La migración NO se aplica sin esa comprobación (fail-closed). QUÉ PREPARAR: un vendedor activo con un cliente activo CON DOCUMENTO en su cartera; después, volver a aplicar esta migración. El oráculo supabase/scripts/numero-contrato-servidor/ con --sin-migracion y la prueba HTTP N1/N1b del banco son DIAGNÓSTICOS (miden la función que haya en la base, aquí la anterior): no sustituyen esta comprobación ni desbloquean una migración abortada';
  end if;
  if v_actor is null then
    raise exception E'POSTFLIGHT numero_contrato_servidor: la sonda «ABC» no fue concluyente con ninguno de los % candidato(s) probados (hasta 5 pares vendedor activo × cliente activo de su cartera, en orden vendedor, cliente): cada llamada murió antes de llegar a la guarda:%\nLa migración NO se aplica sin esa comprobación (fail-closed). QUÉ PREPARAR: un vendedor activo (public.perfiles.rol = comercial y activo; crm.equipo.rol_crm = vendedor y activo) con un cliente activo CON DOCUMENTO en su cartera (public.perfiles.rol = cliente, activo, dni no nulo, asesor_perfil_id = ese vendedor) al que pueda dar de alta; después, volver a aplicar esta migración. El oráculo supabase/scripts/numero-contrato-servidor/ con --sin-migracion y la prueba HTTP N1/N1b del banco son DIAGNÓSTICOS (miden la función que haya en la base, aquí la anterior): no sustituyen esta comprobación ni desbloquean una migración abortada', v_probados, v_causas;
  end if;
  raise notice 'POSTFLIGHT numero_contrato_servidor: sonda «ABC» para un no exento: % (concluyó el candidato % de % probado(s): vendedor %, cliente %)%',
    v_sonda, v_probados, v_probados, v_actor, v_cliente,
    case when v_causas <> '' then '; descartados por no concluyentes:' || v_causas else '' end;
end
$postflight$;

commit;
$mig$::text as contenido;
create temp table registro_20261009210100_condiciones on commit drop as
select c.orden, c.condicion, c.cumple from (values
  (1, 'public.crear_contrato: cuerpo, md5(prosrc) dee13ad8… (postflight)',
   (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.crear_contrato(jsonb,jsonb)')) = 'dee13ad8e1e16e066ba1ba623c0dda6b'),
  (2, 'public.crear_contrato: definición entera, md5(pg_get_functiondef) 6e5a0154… (la que deja; reversa)',
   (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = to_regprocedure('public.crear_contrato(jsonb,jsonb)')) = '6e5a01540300b385799743b4a5b47701'),
  (3, 'public.crear_contrato: ficha (dueño postgres, security definer, search_path vacío)',
   (select p.proowner = 'postgres'::regrole::oid and p.prosecdef and p.proconfig = array['search_path=""']
       from pg_proc p where p.oid = to_regprocedure('public.crear_contrato(jsonb,jsonb)'))),
  (4, 'public.crear_contrato: ACL efectiva (EXECUTE solo authenticated, service_role y el dueño, sin opción de concesión)',
   (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
       from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = to_regprocedure('public.crear_contrato(jsonb,jsonb)')) = array['authenticated:EXECUTE:false', 'postgres:EXECUTE:false', 'service_role:EXECUTE:false']),
  (5, 'public.crear_contrato: EXECUTE efectivo (anon SIN; authenticated y service_role CON)',
   (select not has_function_privilege('anon', p.oid, 'EXECUTE')
         and has_function_privilege('authenticated', p.oid, 'EXECUTE')
         and has_function_privilege('service_role', p.oid, 'EXECUTE')
       from pg_proc p where p.oid = to_regprocedure('public.crear_contrato(jsonb,jsonb)'))),
  (6, 'public.crear_contrato: comentario (el que fija la migración)',
   obj_description(to_regprocedure('public.crear_contrato(jsonb,jsonb)'), 'pg_proc') = 'Alta atómica de contrato y cronograma; renovaciones/upgrades conservan su ledger. La numeración automática usa private.siguiente_numero_contrato y es segura ante concurrencia. EL NÚMERO LO EXIGE EL SERVIDOR (bloque 2.3): tiene que ser 2024-01-, 2025-01- o 2026-01- seguido de exactamente 6 dígitos; nulo, vacío o fuera de forma se rechaza con 22023 y «Formato de número de contrato inválido…». Única excepción: quien es admin/superadmin del Portal Y Gerencia del CRM conserva el autogenerado AC-AAAA-NNNN y acepta cualquier número no duplicado. El duplicado conserva su error. Solo mira el alta: renovaciones y upgrades sobre contratos viejos no cambian.')
) as c(orden, condicion, cumple);
do $chk$
declare
  v_md5    text;
  v_fallan text;
  v_otras  text;
begin
  select md5(r.contenido) into v_md5 from pg_temp.registro_20261009210100 r;
  if v_md5 is distinct from 'ddf1b5f1f0762d1400c2806b36db50a2' then
    raise exception 'REGISTRO: el archivo incrustado no es el de la migración (md5 %, esperado ddf1b5f1f0762d1400c2806b36db50a2)', v_md5;
  end if;
  select string_agg(c.orden || '. ' || c.condicion, '; ' order by c.orden) into v_fallan
    from pg_temp.registro_20261009210100_condiciones c where c.cumple is not true;
  if v_fallan is not null then
    raise exception 'REGISTRO: la migración 20261009210100 no está aplicada o su estado no es el que deja (no se cumple: %); no se registra', v_fallan;
  end if;
  select string_agg(s.version, ', ' order by s.version) into v_otras
    from supabase_migrations.schema_migrations s where s.name = 'crm_numero_contrato_servidor' and s.version <> '20261009210100';
  if v_otras is not null then
    raise exception 'REGISTRO: el nombre crm_numero_contrato_servidor ya está registrado con otra versión (%): no se registra dos veces la misma migración', v_otras;
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations s cross join pg_temp.registro_20261009210100 r
             where s.version = '20261009210100' and (coalesce(s.name, '') <> 'crm_numero_contrato_servidor' or s.statements is distinct from array[r.contenido])) then
    raise exception 'REGISTRO: la versión 20261009210100 ya está registrada con otro nombre u otro contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
select '20261009210100', 'crm_numero_contrato_servidor', array[r.contenido] from pg_temp.registro_20261009210100 r
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261009210100' and name = 'crm_numero_contrato_servidor' and cardinality(statements) = 1
                   and md5(statements[1]) = 'ddf1b5f1f0762d1400c2806b36db50a2') then
    raise exception 'REGISTRO: la fila 20261009210100 / crm_numero_contrato_servidor no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261009210100 / crm_numero_contrato_servidor (1 sentencia: el archivo entero)';
end $post$;
commit;
-- Última fila, tras el COMMIT, para que `db query` muestre algo.
select '20261009210100' as version_registrada, 'ddf1b5f1f0762d1400c2806b36db50a2' as md5_del_archivo;

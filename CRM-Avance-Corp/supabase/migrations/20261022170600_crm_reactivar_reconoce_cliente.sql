-- 20261022170600_crm_reactivar_reconoce_cliente.sql — bloque 2.11 del plan «Mantenibilidad y consistencia del backend CRM» (fecha de trabajo 20261009235500_crm_reactivar_reconoce_cliente.sql; integrado el 2026/10/22, C2 del grupo C)
-- Reactivar una ficha retirada —o un lead de la base para gestión— también reconoce al cliente («ya es cliente de X») (plan
-- AVANCE-BACKEND-0810-F2, fase 2, bloque 2.11; decisiones D-42 y D-55 de Miguel, 09/10/2026; la regla del cliente es la del 2.7 y el
-- 2.8: D-22, D-25, D-27, D-30). Va DESPUÉS de 20261009150000_crm_cliente_no_se_duplica_al_editar.sql (2.8, ronda 4: usa su pieza
-- `private.juicio_cliente_convertido` y parchea el núcleo del alta que deja) y, en el orden de integración, después de
-- 20261009235000_crm_bases_alternativo_cliente.sql (2.9), con el grupo C. No depende del 2.9 (no toca la carga de bases).
-- RONDA 3 (10/10/2026; Codex r1, P2): el preflight aborta también si algo ya NOMBRA la pieza nueva (una función o un trabajo programado
-- escritos de antemano) y el postflight consulta `cron.job` por la pieza y por los dos núcleos; la pieza y los dos núcleos no cambian de
-- cuerpo ni de comentario (el 2.16 fija sus huellas).
--
-- QUÉ PASA HOY (medido en ROJO: `supabase/scripts/reactivar-reconoce-cliente/`, 22 de 36 comprobaciones).
--   (1) El ALTA que encuentra una ficha RETIRADA la reactiva (regla del 2.4) si nada lo impide; lo que la ficha CONSERVA solo pasa por
--       `private.alta_reactivar_bloqueo_conservado` (el verificador, que excluye a los convertidos, y los leads ACTIVOS): no mira el
--       alternativo conservado ni a los convertidos retirados ⇒ la ficha vuelve activa con el teléfono, el alternativo o el DNI de un
--       cliente (R2 y R3b de la ronda 3 del 2.8; también por la puerta del documento y en un reintento del 2.4).
--   (2) La REACTIVACIÓN de un lead de la base para gestión —`crm.reactivar_lead_base_v2`, `crm.reactivar_lead_base` y el intento
--       «agendó cita» de `crm.registrar_intento_base_v2`, las tres por `private.base_gestion_reactivar_capital_core`— no mira a los
--       clientes: la reapertura (`crm.reabrir_lead_fn`) solo juzga la persona y el disparador de disponibilidad no juzga nada si no
--       cambia el teléfono ni el DNI ⇒ el lead vuelve a la cartera con el contacto de un cliente (H-1 del 2.9).
--
-- QUÉ HACE.
--   1. PIEZA NUEVA `private.juicio_cliente_conservado(p_lead_id)` (INVOKER, VOLÁTIL porque toma candados, dueño postgres, EXECUTE solo
--      para postgres): lee el lead, toma los candados de contacto de lo que CONSERVA —su teléfono, su teléfono alternativo y su DNI— con
--      la MISMA clave que el disparador de disponibilidad (`private.bloquear_contactos_lead`) y lo juzga con la regla del 2.7/2.8
--      (`private.juicio_cliente_convertido`, nunca contra el propio lead): devuelve su veredicto («ya es cliente de X» con su asesor, o
--      «no contactar» si la persona del cliente está vetada: el formato y los datos del alta, D-29) o NULL. Como la pieza del 2.8, no
--      mira el alternativo SIN VALIDAR (`telefono_alternativo_crudo`). Es una pieza COMÚN, sin nada de una puerta concreta (nombre,
--      firma y comentario genéricos): la reutilizará el bloque 2.16 (D-62) en las demás puertas que devuelven un lead a la cartera.
--      Su contrato: quien la llama ya tiene la fila del lead FOR UPDATE y decide cómo responder (el alta devuelve el veredicto; una
--      puerta que avisa con errores, `P0481` con el veredicto en el detalle).
--   2. NÚCLEO del alta `private.alta_reactivar_retirado`, por ancla única: tras el veto de la persona (paso 7) y justo antes del UPDATE
--      que reactiva, la pieza sobre la ficha (paso 7b); si responde, el alta devuelve ese veredicto y no reactiva ni escribe nada. Va
--      DESPUÉS de todo lo que hoy decide (lo tecleado, 1b y 3a; lo conservado contra leads activos, 3b, que es lo que para R3a; la persona
--      enlazada, D-21; la identidad, 6; el veto, 7). También en un REINTENTO del 2.4 (mismo p_id, con rastro previo; D-61 de Miguel,
--      09/10/2026: «al reactivar», D-42 al pie de la letra): se juzga lo que la ficha conserva; lo tecleado en el reintento sigue fuera
--      de la regla 1b (R1 del 2.8 no cambia). INTEGRACIÓN (grupo C): los casos 8a y 11i del oráculo del 2.7 fijaban lo de antes (el
--      reintento reactivaba); con esta migración responden «ya es cliente de X» y al integrar se actualizan sus esperados (D-61).
--   3. NÚCLEO de la base `private.base_gestion_reactivar_capital_core`, por ancla única: tras el ámbito (P0002: quien no ve el lead nunca
--      ve el veredicto), el estado (22023) y el No contactar del lead (P0429), y ANTES del capital y de la reapertura, la pieza sobre el
--      lead; si responde ⇒ el MISMO error con el que la edición y el INSERT responden esa regla desde el 2.8: `P0481` «Contacto no
--      disponible» con el veredicto en el detalle. Nada se escribe (en «agendó cita», tampoco el intento: la operación entera se
--      rechaza). El replay de una operación ya hecha no cambia (va antes).
--   4. Comentarios: a los de los dos núcleos se les AÑADE una frase del 2.11 (la reversa la quita).
--
-- NO CAMBIA (y por qué): las fichas y los leads cuyo contacto no es de ningún cliente (la pieza devuelve NULL); el alternativo de un lead
-- VIVO que no es cliente (la regla es solo de clientes: D-25/D-37); lo tecleado en el alta (sigue la regla 1b del 2.7/2.8, que en un
-- reintento no lo juzga: R1); R3a y todo veredicto que ya bloquea hoy (van antes); el ámbito, el estado, el No contactar y el replay de la
-- base (van antes); los intentos que no reactivan; la carga de bases (2.9), la conversión (2.10), el disparador de disponibilidad, el
-- verificador, la pieza del 2.8, `private.alta_reactivar_bloqueo_conservado`, las puertas (`crm.crear_lead_si_disponible`,
-- `crm.crear_lead_documento_fn`, `crm.reactivar_lead_base(_v2)`, `crm.registrar_intento_base(_v2)`, `crm.reabrir_lead_fn`), tablas, grants,
-- policies ni nada de `public`. Las OTRAS puertas que devuelven un descartado a la cartera («Reabrir» `crm.reabrir_lead_fn`, «Tomar un lead
-- libre» `crm.tomar_lead_libre`, `crm.rescatar_descartes` y las de deshacer) quedan como hoy: van al bloque 2.16 (D-62), que reutiliza la
-- pieza (medidas HR y HT del ensayo). Los duplicados que ya existen se dejan (D-25). La concurrencia: la pieza toma los candados de
-- contacto ANTES de juzgar (la misma clave que el disparador, re-entrante en la misma transacción, en el orden fila → contactos de
-- siempre), así que un cliente que se pone a la vez ese número como alternativo, o una conversión de un lead con ese número, se serializan
-- con la reactivación (la espera con dos sesiones: `espera.sh`; la carrera con COMMIT, en la branch).
--
-- PANTALLA: el alta ya presenta el veredicto («Esta persona ya es cliente y está a cargo de X»). En la base para gestión, la app
-- (`app/src/data/crm-api.ts`, `reactivarLeadBase` y `registrarIntentoBase`) traduce hoy un `P0481` con el texto fijo de `aErrorApi` («Ese
-- teléfono o DNI no está disponible para este lead.»): el veredicto viaja en el detalle. D-E2 (Director, 09/10/2026): la pantalla de
-- «Reactivar» y la de «agendó cita» tienen que decir «ya es cliente de X» como el alta (precedente D-36, `presentacionDelP0481`); ese
-- cambio de app lo hace el bloque de pantalla que lo recoja (está descrito en el informe de la ronda 2 del 2.11), no esta migración. D-29
-- vale igual: mismos datos, mismos roles (vendedor, supervisor y gerencia, y solo sobre leads de su ámbito).
--
-- PREFLIGHT (falla cerrada; si algo no coincide no se instala nada): que no esté ya aplicada (ni la pieza, con cualquier firma, ni su
-- llamada en los núcleos); el núcleo del alta EXACTO que deja el 2.8 ronda 4 (`md5(prosrc)` 2fe5fdac50150d7429da2e422f43b92d,
-- `md5(pg_get_functiondef)` 8d598eb4d0df994388337480e71e8005; dueño postgres, DEFINER, `search_path` vacío y `lock_timeout` 5s y nada más,
-- EXECUTE solo para postgres; comentario 8870de7f9d82c44b1a1f965f1e6d3ef0); el núcleo de la base EXACTO de B10 (20261004223253:
-- 479683a99720d554ff419752f3da7876 / 7b7818427c6e526152027bdea95b5c51; dueño postgres, DEFINER, `search_path` vacío y nada más, EXECUTE
-- solo para postgres; comentario 21f3e2c424b4ec59502af01ad775896f); la pieza del 2.8 EXACTA (346f48a8… / a2b38faf…, INVOKER, STABLE,
-- EXECUTE solo postgres, comentario e23707e5…); la definición completa, el dueño y la ACL efectiva de lo que llama a los dos núcleos o
-- decide su efecto (el alta, la puerta del documento, las cuatro puertas de la base y sus dos núcleos de intento, la reapertura, el ámbito
-- y el rol de la base, lo conservado del 2.4, la persona vetada, la identidad, el verificador, el rol, los candados de contacto,
-- `normalizar_telefono`, `juicio_persona`, `inversionista_canonica`); que NADIE MÁS llame a los dos núcleos ni NOMBRE ya la pieza nueva
-- (cuerpos de función sin distinguir mayúsculas, `pg_depend`, `cron.job`; ronda 3); los CHECK de los que depende la comparación literal
-- (`leads_telefono_alternativo_formato`, `_excluyentes`, `leads_dni_check`); el inventario y las definiciones de los 30 `assert_*` que se
-- barren (`30|bc19c770…`). Fotografía las fichas de los dos núcleos y esos `assert_*()` (SIN los `*_mutantes`, como el 2.7/2.8/2.9).
-- POSTFLIGHT: la pieza con su cuerpo, definición, ficha, ACL y comentario EXACTOS; los dos núcleos con su cuerpo nuevo EXACTO (la pieza una
-- sola vez), la misma ficha que antes y su comentario nuevo EXACTO; la pieza del 2.8, las dependencias y los CHECK intactos; nadie más que
-- los dos núcleos usa la pieza y los llamadores de los núcleos son los de antes (funciones, `pg_depend` y, ronda 3, `cron.job`); la foto de
-- los trinquetes EXACTAMENTE igual que antes. Sin DDL de tablas (`create function` y `create or replace function`: ningún candado sobre
-- `crm.leads`).
--
-- CÓMO SE REVIERTE: `supabase/scripts/reactivar-reconoce-cliente/reversa.sql` (generada desde las anclas de esta migración; falla
-- cerrada: exige EXACTAMENTE lo que deja esta migración y que nadie más use la pieza; repone los dos núcleos y sus comentarios por ancla
-- única y borra la pieza sin CASCADE). No deshace datos (la regla no escribe ninguno). Tras revertir, reactivar una ficha retirada o un
-- lead de la base que conserva el contacto de un cliente vuelve a dejar un segundo lead activo del cliente. Mismo ciclo que la
-- migración. Ensayo: `supabase/scripts/reactivar-reconoce-cliente/` (ROJO/VERDE, mutantes, derivas, reversa, trinquetes, la espera con
-- dos sesiones y los oráculos del 2.4, 2.7, 2.8 y 2.9 encima).
-- RESELLE C2 (22/10/2026, plan AVANCE-BACKEND-1310-C2): re-asentado contra producción del 22/10: el alta que deja el 2.4 re-asentado (definición e06eca23…, antes 94ec2bd7…; cambió por 20261015171407 y 20261016183308) en la lista de dependencias del preflight y del postflight, y el censo de los 30 private.assert_*() que se barren (30|3cefe40e…, antes 30|bc19c770…: mismos 30 nombres, 10 definiciones cambiadas por producción); reversa regenerada; regla, mensajes y candados sin cambio.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $preflight$
declare
  v_nucleo regprocedure := to_regprocedure('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)');
  v_nbase regprocedure := to_regprocedure('private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)');
  v_pieza28 regprocedure := to_regprocedure('private.juicio_cliente_convertido(text,text,text,uuid)');
  v_mal text;
  r record;
  v text;
  v_foto text := '';
begin
  if v_nucleo is null or v_nbase is null or v_pieza28 is null then
    raise exception 'PREFLIGHT reactivar_reconoce_cliente: falta el núcleo del alta, el núcleo de la base o la pieza del 2.8 (esta migración va después del 2.8)';
  end if;
  -- Ya aplicada (o una función con ese nombre ya existe, con cualquier firma): no se reinstala nada.
  if exists (select 1 from pg_proc p where p.pronamespace = 'private'::regnamespace and p.proname = 'juicio_cliente_conservado')
     or strpos(lower((select p.prosrc from pg_proc p where p.oid = v_nucleo)), 'juicio_cliente_conservado') > 0
     or strpos(lower((select p.prosrc from pg_proc p where p.oid = v_nbase)), 'juicio_cliente_conservado') > 0 then
    raise exception 'PREFLIGHT reactivar_reconoce_cliente: ya existe private.juicio_cliente_conservado o su llamada: esta migración ya está aplicada';
  end if;
  -- El núcleo del alta que deja el 2.8 (ronda 4), exacto: cuerpo, definición, ficha y comentario.
  if (select md5(p.prosrc) from pg_proc p where p.oid = v_nucleo) is distinct from '2fe5fdac50150d7429da2e422f43b92d'
     or md5(pg_get_functiondef(v_nucleo)) is distinct from '8d598eb4d0df994388337480e71e8005' then
    raise exception 'PREFLIGHT reactivar_reconoce_cliente: el núcleo private.alta_reactivar_retirado no es el que deja el 2.8 ronda 4 (md5 del cuerpo %, de la definición %; se esperaban 2fe5fdac50150d7429da2e422f43b92d y 8d598eb4d0df994388337480e71e8005): revisar el cuerpo vivo antes de parchear',
      (select md5(p.prosrc) from pg_proc p where p.oid = v_nucleo), md5(pg_get_functiondef(v_nucleo));
  end if;
  if not exists (select 1 from pg_proc p
                  where p.oid = v_nucleo and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                    and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_nucleo)
        is distinct from 'postgres:EXECUTE:false'
     or has_function_privilege('anon', v_nucleo, 'EXECUTE') or has_function_privilege('authenticated', v_nucleo, 'EXECUTE')
     or has_function_privilege('service_role', v_nucleo, 'EXECUTE') then
    raise exception 'PREFLIGHT reactivar_reconoce_cliente: la ficha del núcleo del alta no es la auditada (dueño postgres, security definer, search_path vacío y lock_timeout 5s, EXECUTE solo para postgres sin opción de concesión)';
  end if;
  if md5(coalesce(obj_description(v_nucleo, 'pg_proc'), '')) is distinct from '8870de7f9d82c44b1a1f965f1e6d3ef0' then
    raise exception 'PREFLIGHT reactivar_reconoce_cliente: el comentario del núcleo del alta no es el que deja el 2.8; revisar antes de añadirle nada (la reversa lo repone)';
  end if;
  -- El núcleo de la base de B10 (20261004223253), exacto: cuerpo, definición, ficha y comentario.
  if (select md5(p.prosrc) from pg_proc p where p.oid = v_nbase) is distinct from '479683a99720d554ff419752f3da7876'
     or md5(pg_get_functiondef(v_nbase)) is distinct from '7b7818427c6e526152027bdea95b5c51' then
    raise exception 'PREFLIGHT reactivar_reconoce_cliente: el núcleo private.base_gestion_reactivar_capital_core no es el de B10 (20261004223253) (md5 del cuerpo %, de la definición %; se esperaban 479683a99720d554ff419752f3da7876 y 7b7818427c6e526152027bdea95b5c51): revisar el cuerpo vivo antes de parchear',
      (select md5(p.prosrc) from pg_proc p where p.oid = v_nbase), md5(pg_get_functiondef(v_nbase));
  end if;
  if not exists (select 1 from pg_proc p
                  where p.oid = v_nbase and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                    and p.proconfig = array['search_path=""'])
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_nbase)
        is distinct from 'postgres:EXECUTE:false'
     or has_function_privilege('anon', v_nbase, 'EXECUTE') or has_function_privilege('authenticated', v_nbase, 'EXECUTE')
     or has_function_privilege('service_role', v_nbase, 'EXECUTE') then
    raise exception 'PREFLIGHT reactivar_reconoce_cliente: la ficha del núcleo de la base no es la auditada (dueño postgres, security definer, search_path vacío y nada más, EXECUTE solo para postgres sin opción de concesión)';
  end if;
  if md5(coalesce(obj_description(v_nbase, 'pg_proc'), '')) is distinct from '21f3e2c424b4ec59502af01ad775896f' then
    raise exception 'PREFLIGHT reactivar_reconoce_cliente: el comentario del núcleo de la base no es el de B10; revisar antes de añadirle nada (la reversa lo repone)';
  end if;
  -- La pieza del 2.8 (ronda 4), exacta: cuerpo, definición, ficha, ACL y comentario.
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_pieza28)
       is distinct from '346f48a8648248b308628301d41bc4c0/a2b38faf42a875c7dffb7968b106e36f'
     or not exists (select 1 from pg_proc p where p.oid = v_pieza28 and p.proowner = 'postgres'::regrole::oid and not p.prosecdef
                      and p.provolatile = 's' and p.proconfig = array['search_path=""'])
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_pieza28)
        is distinct from 'postgres:EXECUTE:false'
     or md5(coalesce(obj_description(v_pieza28, 'pg_proc'), '')) is distinct from 'e23707e521c5878f056c0b99b02a9651' then
    raise exception 'PREFLIGHT reactivar_reconoce_cliente: la pieza private.juicio_cliente_convertido no es la del 2.8 ronda 4 (cuerpo 346f48a8…/a2b38faf…, INVOKER de postgres, STABLE, search_path vacío, EXECUTE solo para postgres, comentario e23707e5…): lo ensayado no valdría';
  end if;
  -- Lo que llama a los dos núcleos o decide su efecto: su DEFINICIÓN COMPLETA (cuerpo y atributos: DEFINER/INVOKER, STRICT,
  -- volatilidad, SET), su dueño y su ACL EFECTIVA (los valores por defecto expandidos, con la opción de concesión).
  select string_agg(e.firma, ', ' order by e.firma) into v_mal
  from (values
    ('crm.crear_lead_documento_fn(jsonb,text,text)', 'f6dfdc2907a1c3069e4988bf038d04c1', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)', 'e06eca2333bb11869d00913a004c8261', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.reabrir_lead_fn(uuid)', '9cdac9e10f2efde549bbcbdf810b95d3', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.reactivar_lead_base(uuid,uuid,text)', 'cf44c73e6326573dfbcb5defdb07fcf7', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)', 'a8c982fb500bdc42b11032d4576ed953', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.registrar_intento_base(uuid,uuid,text,text,timestamp with time zone)', '2c360e0e2536096713059a9dbbcd1ef8', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)', '6f5971c0bf6f68285fadae5e30099ee2', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.alta_reactivar_bloqueo_conservado(uuid)', '2186e7c4b4e3ac4bcf23636cb951d9ba', 'postgres:EXECUTE:false'),
    ('private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)', 'a4a0638e4ca2c8a89ad9909c522b4a92', 'postgres:EXECUTE:false'),
    ('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)', '83d99939149bbf445b5c77c33787f1cf', 'postgres:EXECUTE:false'),
    ('private.base_gestion_lead_visible(uuid,text,uuid,uuid)', 'e80a43724b64f0ed5ac67b846292fb6c', 'postgres:EXECUTE:false'),
    ('private.base_gestion_reactivar_core(uuid,uuid,uuid,text)', 'c9e90784de512cc4c8e694a0465bc80c', 'postgres:EXECUTE:false'),
    ('private.base_gestion_rol(uuid)', '3c2d5feefd68589cfe82fc1fe2e95180', 'postgres:EXECUTE:false'),
    ('private.bloquear_contactos_lead(text[],text[])', '0d52f58c2065c1c0dc37a7587eda5882', 'postgres:EXECUTE:false'),
    ('private.inversionista_canonica(uuid)', '34702897135078893b7d3a726b0c1816', 'postgres:EXECUTE:false'),
    ('private.juicio_persona(uuid,uuid)', '69794e137dd642e0b529612fb2a623eb', 'postgres:EXECUTE:false'),
    ('private.juicio_reapertura(uuid,text,text)', '47277cd689ad0e1713e436d3373e3521', 'postgres:EXECUTE:false'),
    ('private.normalizar_telefono(text)', '00c30277b752de13be3ee0599485e6a9', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.persona_vetada(uuid)', 'a70efe776fc56fd34d47e364e2e55571', 'postgres:EXECUTE:false'),
    ('private.rol_crm(uuid)', '99827f3fe2fbc3cfae5668c30015c758', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.verificar_disponibilidad_lead_impl(text,text)', '742d44fff6a8a742292c8de702812e60', 'postgres:EXECUTE:false'),
    ('private.verificar_disponibilidad_lead_impl(text,text,uuid)', 'cece9dd168c9beea935af2e05895e32a', 'postgres:EXECUTE:false')) e(firma, definicion, acl)
  left join pg_proc p on p.oid = to_regprocedure(e.firma)
  where p.oid is null
     or md5(pg_get_functiondef(p.oid)) is distinct from e.definicion
     or p.proowner is distinct from 'postgres'::regrole::oid
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) is distinct from e.acl;
  if v_mal is not null then
    raise exception 'PREFLIGHT reactivar_reconoce_cliente: cambió algo que llama a los núcleos o decide su efecto (%: definición, dueño o permisos); lo ensayado no valdría', v_mal;
  end if;
  -- Nadie más llama a los dos núcleos (el cambio lo alcanzaría): ni otra función por su cuerpo (sin distinguir mayúsculas), ni un objeto
  -- registrado en pg_depend, ni un trabajo programado. Un «posible llamador» bloquea de forma conservadora (un comentario o una cadena
  -- con ese nombre también): se inspecciona antes de seguir. Ronda 3 (Codex r1, P2): también lo que ya NOMBRE la pieza nueva antes de
  -- que exista (una función o un trabajo programado escritos de antemano): aborta aquí, no solo en el postflight.
  select string_agg(x.f, ', ' order by x.f) into v_mal
  from (select p.oid::regprocedure::text as f
          from pg_proc p
         where strpos(lower(p.prosrc), 'juicio_cliente_conservado') > 0
            or (strpos(lower(p.prosrc), 'base_gestion_reactivar_capital_core') > 0
                and p.oid not in (v_nbase, to_regprocedure('crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)'),
                                  to_regprocedure('private.base_gestion_reactivar_core(uuid,uuid,uuid,text)'),
                                  to_regprocedure('private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)')))
            or (strpos(lower(p.prosrc), 'alta_reactivar_retirado') > 0
                and p.oid not in (v_nucleo, to_regprocedure('crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)')))
        union all
        select pg_describe_object(d.classid, d.objid, d.objsubid)
          from pg_depend d
         where d.refclassid = 'pg_proc'::regclass and d.refobjid in (v_nucleo, v_nbase)) x;
  if v_mal is null and to_regclass('cron.job') is not null then
    execute $q$select string_agg('cron.job ' || j.jobid::text, ', ') from cron.job j
                where strpos(lower(j.command), 'juicio_cliente_conservado') > 0
                   or strpos(lower(j.command), 'base_gestion_reactivar_capital_core') > 0
                   or strpos(lower(j.command), 'alta_reactivar_retirado') > 0$q$ into v_mal;
  end if;
  if v_mal is not null then
    raise exception 'PREFLIGHT reactivar_reconoce_cliente: otro posible llamador de los núcleos o de la pieza nueva (%): el cambio lo alcanzaría; inspeccionar antes de seguir', v_mal;
  end if;
  -- Las premisas de la comparación literal de la pieza del 2.8: el alternativo se guarda SIEMPRE canónico (E.164) y excluyente con el
  -- alternativo sin validar; el DNI, ocho dígitos. Si un CHECK cambia o desaparece, lo ensayado no valdría.
  select string_agg(e.nombre, ', ' order by e.nombre) into v_mal
  from (values
    ('leads_dni_check', '6dcca3c962687ba896d101adf845d281'),
    ('leads_telefono_alternativo_excluyentes', 'adc22ae8c0c8d4e21ec406259be35da0'),
    ('leads_telefono_alternativo_formato', '4ce894b3dc052735877c5e1ae07b3219')) e(nombre, definicion)
  left join pg_constraint c on c.conrelid = 'crm.leads'::regclass and c.conname = e.nombre
  where c.oid is null or c.contype <> 'c' or not c.convalidated or md5(pg_get_constraintdef(c.oid)) is distinct from e.definicion;
  if v_mal is not null then
    raise exception 'PREFLIGHT reactivar_reconoce_cliente: cambió o falta una restricción de crm.leads de la que depende la regla (%)', v_mal;
  end if;
  -- El inventario y las DEFINICIONES de los trinquetes que se barren abajo, ANTES del primer barrido: tienen que ser los auditados (no se
  -- exige que pasen; se exige que sean ellos).
  if (select count(*) || '|' || md5(string_agg(p.oid::regprocedure::text || ':' || md5(pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text collate "C"))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0)
     is distinct from '30|3cefe40e1440f25d2daadb56d35a0f8d' then
    raise exception 'PREFLIGHT reactivar_reconoce_cliente: los private.assert_*() que barre la migración no son los auditados (inventario o definiciones: %); revisarlos antes de barrerlos',
      (select count(*) || '|' || md5(string_agg(p.oid::regprocedure::text || ':' || md5(pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text collate "C"))
         from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0);
  end if;
  -- Fotos para el postflight: las fichas de los dos núcleos y los private.assert_*() sin argumentos y SIN los `*_mutantes` (estado y texto
  -- íntegro del primer error: se exige que NO cambien, no que pasen).
  perform set_config('reactivar_reconoce_cliente.nucleo_antes',
    (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_nucleo), true);
  perform set_config('reactivar_reconoce_cliente.nbase_antes',
    (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_nbase), true);
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
  perform set_config('reactivar_reconoce_cliente.trinquetes_antes', v_foto, true);
end
$preflight$;

-- ── 1. La pieza nueva: el veredicto de cliente para lo que CONSERVA un lead, bajo los candados de contacto ─────────────────
create function private.juicio_cliente_conservado(p_lead_id uuid)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
  v_l crm.leads%rowtype;
begin
  -- Bloque 2.11 (D-42, D-55). Lo que CONSERVA el lead (la fila ya tomada FOR UPDATE por quien llama): su teléfono, su teléfono
  -- alternativo (el canónico; el alternativo sin validar no se juzga, como en la pieza del 2.8) y su DNI.
  select l.* into v_l from crm.leads l where l.id = p_lead_id;
  if not found then
    return null;
  end if;
  -- Los candados de contacto de esos datos, con la MISMA clave que toma el disparador de disponibilidad al escribir (re-entrantes en
  -- la misma transacción): quien a la vez pone ese número como alternativo de un cliente, o convierte un lead con ese número, espera o
  -- hace esperar, y la regla juzga con lo que el otro confirmó.
  perform private.bloquear_contactos_lead(array[v_l.telefono, v_l.telefono_alternativo], array[v_l.dni]);
  -- La regla del 2.7/2.8 (D-22, D-25, D-27, D-30): esos datos contra el teléfono, el alternativo y el DNI de cada lead CONVERTIDO
  -- (activo o retirado), nunca contra el propio lead. Su veredicto (el del alta, D-29) o NULL.
  return private.juicio_cliente_convertido(v_l.telefono, v_l.telefono_alternativo, v_l.dni, v_l.id);
end;
$function$;

-- Dueño postgres SIEMPRE (como los núcleos que la llaman), corra quien corra la migración; EXECUTE solo para él.
alter function private.juicio_cliente_conservado(uuid) owner to postgres;
revoke all on function private.juicio_cliente_conservado(uuid) from public, anon, authenticated, service_role;

comment on function private.juicio_cliente_conservado(uuid) is
  'Bloque 2.11 (D-42, D-55, D-62; regla del 2.7/2.8: D-22, D-25, D-27, D-30). Pieza COMUN para cualquier puerta que devuelva un lead a la cartera (reactivar, reabrir, tomar, rescatar, deshacer): el veredicto de cliente ya convertido (lead en etapa convertido, activo o retirado) para lo que CONSERVA el lead p_lead_id (su telefono, su alternativo canonico y su DNI; no el alternativo sin validar), sin contarlo a el: private.juicio_cliente_convertido, despues de tomar los candados de contacto de esos datos con la misma clave que el disparador de disponibilidad (private.bloquear_contactos_lead). Devuelve el veredicto del alta (ya_es_cliente con su asesor, o no_contactar) o NULL si no hay cliente o el lead no existe; no escribe nada. Contrato: quien la llama ya tiene la fila del lead FOR UPDATE y decide como responder (el alta devuelve el veredicto; una puerta que avisa con errores, P0481 Contacto no disponible con el veredicto en el detalle). Hoy la llaman el nucleo del alta (private.alta_reactivar_retirado) y el de la base para gestion (private.base_gestion_reactivar_capital_core); el bloque 2.16 (D-62) la reutiliza en las demas puertas. INVOKER y volatil (toma candados); solo la ejecuta postgres.';

-- ── 2. El núcleo del alta, por ancla única: tras el veto de la persona (paso 7), la pieza sobre la ficha (paso 7b) ───────
do $nucleo$
declare
  v_firma regprocedure := 'private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'::regprocedure;
  v_def text;
  v_acl aclitem[];
  v_ancla text;
  v_nuevo text;
  v_veces integer;
begin
  select pg_get_functiondef(p.oid), p.proacl into v_def, v_acl from pg_proc p where p.oid = v_firma;

  v_ancla := $a1$    -- 7. Veto de la persona (también la hallada solo por documento o puente).
    if private.persona_vetada(v_lead.id) then
      return pg_catalog.jsonb_build_object('estado', 'no_contactar');
    end if;
$a1$;
  v_nuevo := $n1$    -- 7. Veto de la persona (también la hallada solo por documento o puente).
    if private.persona_vetada(v_lead.id) then
      return pg_catalog.jsonb_build_object('estado', 'no_contactar');
    end if;

    -- 7b. EL CLIENTE YA CONVERTIDO TAMBIÉN SE RECONOCE POR LO QUE LA FICHA CONSERVA (bloque 2.11; D-42 de Miguel, 09/10/2026; R2 y
    --     R3b de la ronda 3 del 2.8). Su teléfono, su teléfono alternativo y su DNI no pueden ser de un cliente ya convertido (activo
    --     o retirado), sin contarla a ella: la pieza `private.juicio_cliente_conservado` toma antes los candados de contacto de esos
    --     datos (la misma clave que tomará el disparador de disponibilidad al reactivar) y los juzga con la regla del 2.7/2.8. Si son
    --     de un cliente, no se reactiva ni se escribe nada y el alta responde ese veredicto («ya es cliente de X»: el formato y los
    --     datos del alta, D-29). También en un REINTENTO con rastro previo (D-61 de Miguel, 09/10/2026): la ficha es la misma y lo que
    --     se juzga es lo que ELLA conserva, no lo tecleado (que en el reintento sigue fuera de la regla 1b: R1 del 2.8). Va después de
    --     los veredictos de hoy (lo tecleado, 1b y 3a; lo conservado contra leads activos, 3b, que es lo que para R3a; la persona
    --     enlazada, D-21; la identidad, 6; el veto, 7), justo antes del UPDATE.
    v_fresco := private.juicio_cliente_conservado(v_lead.id);
    if v_fresco is not null then
      return v_fresco;
    end if;
$n1$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT reactivar_reconoce_cliente: el ancla del veto (paso 7) del núcleo del alta aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  execute v_def;

  if (select p.proacl from pg_proc p where p.oid = v_firma) is distinct from v_acl then
    raise exception 'POSTFLIGHT reactivar_reconoce_cliente: los permisos del núcleo del alta cambiaron al parchear';
  end if;
end
$nucleo$;

-- ── 3. El núcleo de la base, por ancla única: su variable y, tras el No contactar, la pieza sobre el lead ────────────────
do $base$
declare
  v_firma regprocedure := 'private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)'::regprocedure;
  v_def text;
  v_acl aclitem[];
  v_ancla text;
  v_nuevo text;
  v_veces integer;
begin
  select pg_get_functiondef(p.oid), p.proacl into v_def, v_acl from pg_proc p where p.oid = v_firma;

  -- Ancla 1 (declaraciones): la variable del veredicto.
  v_ancla := $b1$  v_resp jsonb;
  v_reabrir jsonb;
begin
$b1$;
  v_nuevo := $m1$  v_resp jsonb;
  v_reabrir jsonb;
  v_cliente jsonb;
begin
$m1$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT reactivar_reconoce_cliente: el ancla de las declaraciones del núcleo de la base aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  -- Ancla 2 (cuerpo): después del No contactar del lead, antes del capital.
  v_ancla := $b2$  if v_lead.no_contactar then
    raise exception 'No insistir: el lead esta marcado No contactar' using errcode = 'P0429';
  end if;
$b2$;
  v_nuevo := $m2$  if v_lead.no_contactar then
    raise exception 'No insistir: el lead esta marcado No contactar' using errcode = 'P0429';
  end if;
  -- Bloque 2.11 (D-55 de Miguel, 09/10/2026; como D-42 en el alta; H-1 del 2.9): lo que el lead CONSERVA —su teléfono, su teléfono
  -- alternativo y su DNI— no puede ser de un cliente ya convertido (activo o retirado), sin contarlo a él: la pieza
  -- `private.juicio_cliente_conservado` (candados de contacto y la regla del 2.7/2.8). Si lo es, no se reactiva ni se escribe nada: el
  -- MISMO `P0481` «Contacto no disponible» con el que la edición y el INSERT responden esa regla (2.8), con el veredicto del alta
  -- («ya es cliente de X»; D-29) en el detalle. Después del ámbito (quien no ve el lead recibe P0002 y nunca el veredicto), del
  -- estado y del No contactar; antes del capital y de la reapertura. Lo heredan las tres reactivaciones de la base:
  -- crm.reactivar_lead_base_v2, crm.reactivar_lead_base y el intento «agendó cita».
  v_cliente := private.juicio_cliente_conservado(v_lead.id);
  if v_cliente is not null then
    raise exception using errcode = 'P0481', message = 'Contacto no disponible', detail = v_cliente::text;
  end if;
$m2$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT reactivar_reconoce_cliente: el ancla del No contactar del núcleo de la base aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  execute v_def;

  if (select p.proacl from pg_proc p where p.oid = v_firma) is distinct from v_acl then
    raise exception 'POSTFLIGHT reactivar_reconoce_cliente: los permisos del núcleo de la base cambiaron al parchear';
  end if;
end
$base$;

-- ── 4. Los comentarios: a los de los dos núcleos se les AÑADE el del 2.11; la reversa lo quita ───────────────────────────
do $comentarios$
begin
  execute pg_catalog.format('comment on function private.alta_reactivar_retirado(uuid, uuid, text, text, uuid, uuid, jsonb, jsonb) is %L',
    obj_description('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'::regprocedure, 'pg_proc')
      || $c1$ Bloque 2.11 (D-42, D-61): antes de reactivar una ficha retirada (tambien en un reintento), lo que la ficha CONSERVA (telefono, alternativo y DNI) no puede ser de un cliente ya convertido, activo o retirado (private.juicio_cliente_conservado, bajo los candados de contacto de esos datos; nunca contra la propia ficha): si lo es, el alta responde ese veredicto (ya es cliente de X, formato del alta) y no reactiva ni escribe nada; va despues de los veredictos de hoy.$c1$);
  execute pg_catalog.format('comment on function private.base_gestion_reactivar_capital_core(uuid, uuid, uuid, text, numeric, text) is %L',
    obj_description('private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)'::regprocedure, 'pg_proc')
      || $c2$ Bloque 2.11 (D-55): antes de reactivar, lo que el lead CONSERVA (telefono, alternativo y DNI) no puede ser de un cliente ya convertido, activo o retirado (private.juicio_cliente_conservado; nunca contra el propio lead): si lo es, P0481 Contacto no disponible con el veredicto del alta (ya es cliente de X) en el detalle, y nada se escribe; despues del ambito, del estado y del No contactar, antes del capital y de la reapertura.$c2$);
end
$comentarios$;

-- ── Postflight ───────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_pieza regprocedure := to_regprocedure('private.juicio_cliente_conservado(uuid)');
  v_nucleo regprocedure := 'private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'::regprocedure;
  v_nbase regprocedure := 'private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)'::regprocedure;
  v_pieza28 regprocedure := 'private.juicio_cliente_convertido(text,text,text,uuid)'::regprocedure;
  v_src text;
  v_h text;
  v_mal text;
  r record;
  v text;
  v_foto text := '';
  v_gates integer := 0;
begin
  -- La pieza: cuerpo y definición exactos, INVOKER de postgres, VOLÁTIL, search_path vacío y nada más, EXECUTE solo para postgres,
  -- comentario exacto.
  if v_pieza is null then
    raise exception 'POSTFLIGHT reactivar_reconoce_cliente: la pieza private.juicio_cliente_conservado no quedó creada';
  end if;
  v_h := (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_pieza);
  if v_h is distinct from '78208791362fa74fda4b67de6dd6d259/f5206895fbbd995a52b27cf5c80167bb' then
    raise exception 'POSTFLIGHT reactivar_reconoce_cliente: la pieza no quedó exactamente como se ensayó (md5 del cuerpo / de la definición %)', v_h;
  end if;
  if not exists (select 1 from pg_proc p where p.oid = v_pieza and p.proowner = 'postgres'::regrole::oid and not p.prosecdef
                   and p.provolatile = 'v' and p.proconfig = array['search_path=""'])
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_pieza)
        is distinct from 'postgres:EXECUTE:false'
     or has_function_privilege('anon', v_pieza, 'EXECUTE') or has_function_privilege('authenticated', v_pieza, 'EXECUTE')
     or has_function_privilege('service_role', v_pieza, 'EXECUTE')
     or md5(coalesce(obj_description(v_pieza, 'pg_proc'), '')) is distinct from '4aa74d7ea8a98da72df1ddb5c4e0176c' then
    raise exception 'POSTFLIGHT reactivar_reconoce_cliente: la ficha de la pieza no es la esperada (INVOKER de postgres, volátil, search_path vacío, EXECUTE solo para postgres, comentario EXACTO del 2.11)';
  end if;
  -- El núcleo del alta: la pieza una sola vez, cuerpo exacto, la misma ficha que antes, comentario exacto.
  select p.prosrc, md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) into v_src, v_h from pg_proc p where p.oid = v_nucleo;
  if (length(v_src) - length(replace(v_src, 'private.juicio_cliente_conservado(', ''))) / length('private.juicio_cliente_conservado(') <> 1 then
    raise exception 'POSTFLIGHT reactivar_reconoce_cliente: el núcleo del alta no quedó con la pieza exactamente una vez';
  end if;
  if v_h is distinct from '9f26e7f962d21170b2c35e113442d026/9c09cca28fd81fa29f16133b2b57c328' then
    raise exception 'POSTFLIGHT reactivar_reconoce_cliente: el núcleo del alta no quedó exactamente como se ensayó (md5 del cuerpo / de la definición %)', v_h;
  end if;
  if (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
             || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
        from pg_proc p where p.oid = v_nucleo) is distinct from current_setting('reactivar_reconoce_cliente.nucleo_antes', true)
     or has_function_privilege('anon', v_nucleo, 'EXECUTE') or has_function_privilege('authenticated', v_nucleo, 'EXECUTE')
     or has_function_privilege('service_role', v_nucleo, 'EXECUTE')
     or md5(coalesce(obj_description(v_nucleo, 'pg_proc'), '')) is distinct from '40cf4271eed96a9119cfeb8433aceac8' then
    raise exception 'POSTFLIGHT reactivar_reconoce_cliente: la ficha o el comentario del núcleo del alta no son los esperados (comentario md5 %)', md5(coalesce(obj_description(v_nucleo, 'pg_proc'), ''));
  end if;
  -- El núcleo de la base: la pieza una sola vez, cuerpo exacto, la misma ficha que antes, comentario exacto.
  select p.prosrc, md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) into v_src, v_h from pg_proc p where p.oid = v_nbase;
  if (length(v_src) - length(replace(v_src, 'private.juicio_cliente_conservado(', ''))) / length('private.juicio_cliente_conservado(') <> 1 then
    raise exception 'POSTFLIGHT reactivar_reconoce_cliente: el núcleo de la base no quedó con la pieza exactamente una vez';
  end if;
  if v_h is distinct from 'c7bad703b3fd9e4d0c13372fdf2ba579/4d0841a94d320a985e4e6ec48d28f90f' then
    raise exception 'POSTFLIGHT reactivar_reconoce_cliente: el núcleo de la base no quedó exactamente como se ensayó (md5 del cuerpo / de la definición %)', v_h;
  end if;
  if (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
             || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
        from pg_proc p where p.oid = v_nbase) is distinct from current_setting('reactivar_reconoce_cliente.nbase_antes', true)
     or has_function_privilege('anon', v_nbase, 'EXECUTE') or has_function_privilege('authenticated', v_nbase, 'EXECUTE')
     or has_function_privilege('service_role', v_nbase, 'EXECUTE')
     or md5(coalesce(obj_description(v_nbase, 'pg_proc'), '')) is distinct from '38d94622c7a051548efb7cf3aa88fb06' then
    raise exception 'POSTFLIGHT reactivar_reconoce_cliente: la ficha o el comentario del núcleo de la base no son los esperados (comentario md5 %)', md5(coalesce(obj_description(v_nbase, 'pg_proc'), ''));
  end if;
  -- La pieza del 2.8, intacta.
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) || '/' || coalesce(p.proacl::text, '-') || '/' || md5(coalesce(obj_description(p.oid, 'pg_proc'), ''))
        from pg_proc p where p.oid = v_pieza28)
       is distinct from '346f48a8648248b308628301d41bc4c0/a2b38faf42a875c7dffb7968b106e36f/{postgres=X/postgres}/e23707e521c5878f056c0b99b02a9651' then
    raise exception 'POSTFLIGHT reactivar_reconoce_cliente: la pieza del 2.8 cambió y esta migración no la toca';
  end if;
  -- Lo que llama a los núcleos o decide su efecto, intacto.
  select string_agg(e.firma, ', ' order by e.firma) into v_mal
  from (values
    ('crm.crear_lead_documento_fn(jsonb,text,text)', 'f6dfdc2907a1c3069e4988bf038d04c1', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)', 'e06eca2333bb11869d00913a004c8261', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.reabrir_lead_fn(uuid)', '9cdac9e10f2efde549bbcbdf810b95d3', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.reactivar_lead_base(uuid,uuid,text)', 'cf44c73e6326573dfbcb5defdb07fcf7', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)', 'a8c982fb500bdc42b11032d4576ed953', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.registrar_intento_base(uuid,uuid,text,text,timestamp with time zone)', '2c360e0e2536096713059a9dbbcd1ef8', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)', '6f5971c0bf6f68285fadae5e30099ee2', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.alta_reactivar_bloqueo_conservado(uuid)', '2186e7c4b4e3ac4bcf23636cb951d9ba', 'postgres:EXECUTE:false'),
    ('private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)', 'a4a0638e4ca2c8a89ad9909c522b4a92', 'postgres:EXECUTE:false'),
    ('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)', '83d99939149bbf445b5c77c33787f1cf', 'postgres:EXECUTE:false'),
    ('private.base_gestion_lead_visible(uuid,text,uuid,uuid)', 'e80a43724b64f0ed5ac67b846292fb6c', 'postgres:EXECUTE:false'),
    ('private.base_gestion_reactivar_core(uuid,uuid,uuid,text)', 'c9e90784de512cc4c8e694a0465bc80c', 'postgres:EXECUTE:false'),
    ('private.base_gestion_rol(uuid)', '3c2d5feefd68589cfe82fc1fe2e95180', 'postgres:EXECUTE:false'),
    ('private.bloquear_contactos_lead(text[],text[])', '0d52f58c2065c1c0dc37a7587eda5882', 'postgres:EXECUTE:false'),
    ('private.inversionista_canonica(uuid)', '34702897135078893b7d3a726b0c1816', 'postgres:EXECUTE:false'),
    ('private.juicio_persona(uuid,uuid)', '69794e137dd642e0b529612fb2a623eb', 'postgres:EXECUTE:false'),
    ('private.juicio_reapertura(uuid,text,text)', '47277cd689ad0e1713e436d3373e3521', 'postgres:EXECUTE:false'),
    ('private.normalizar_telefono(text)', '00c30277b752de13be3ee0599485e6a9', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.persona_vetada(uuid)', 'a70efe776fc56fd34d47e364e2e55571', 'postgres:EXECUTE:false'),
    ('private.rol_crm(uuid)', '99827f3fe2fbc3cfae5668c30015c758', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.verificar_disponibilidad_lead_impl(text,text)', '742d44fff6a8a742292c8de702812e60', 'postgres:EXECUTE:false'),
    ('private.verificar_disponibilidad_lead_impl(text,text,uuid)', 'cece9dd168c9beea935af2e05895e32a', 'postgres:EXECUTE:false')) e(firma, definicion, acl)
  left join pg_proc p on p.oid = to_regprocedure(e.firma)
  where p.oid is null
     or md5(pg_get_functiondef(p.oid)) is distinct from e.definicion
     or p.proowner is distinct from 'postgres'::regrole::oid
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) is distinct from e.acl;
  if v_mal is not null then
    raise exception 'POSTFLIGHT reactivar_reconoce_cliente: cambió algo que esta migración no toca (%)', v_mal;
  end if;
  -- Nadie más que los dos núcleos usa la pieza, y los llamadores de los núcleos son los de antes (lo mismo que el preflight, más la pieza).
  -- Ronda 3 (Codex r1, P2): también los trabajos programados (cron.job.command), por la pieza y por los dos núcleos.
  select string_agg(x.f, ', ' order by x.f) into v_mal
  from (select p.oid::regprocedure::text as f
          from pg_proc p
         where (strpos(lower(p.prosrc), 'juicio_cliente_conservado') > 0 and p.oid not in (v_pieza, v_nucleo, v_nbase))
            or (strpos(lower(p.prosrc), 'base_gestion_reactivar_capital_core') > 0
                and p.oid not in (v_nbase, to_regprocedure('crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)'),
                                  to_regprocedure('private.base_gestion_reactivar_core(uuid,uuid,uuid,text)'),
                                  to_regprocedure('private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)')))
            or (strpos(lower(p.prosrc), 'alta_reactivar_retirado') > 0
                and p.oid not in (v_nucleo, to_regprocedure('crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)')))
        union all
        select pg_describe_object(d.classid, d.objid, d.objsubid)
          from pg_depend d
         where d.refclassid = 'pg_proc'::regclass and d.refobjid in (v_pieza, v_nucleo, v_nbase)) x;
  if v_mal is null and to_regclass('cron.job') is not null then
    execute $q$select string_agg('cron.job ' || j.jobid::text, ', ') from cron.job j
                where strpos(lower(j.command), 'juicio_cliente_conservado') > 0
                   or strpos(lower(j.command), 'base_gestion_reactivar_capital_core') > 0
                   or strpos(lower(j.command), 'alta_reactivar_retirado') > 0$q$ into v_mal;
  end if;
  if v_mal is not null then
    raise exception 'POSTFLIGHT reactivar_reconoce_cliente: otro objeto usa la pieza o los núcleos (%)', v_mal;
  end if;
  select string_agg(e.nombre, ', ' order by e.nombre) into v_mal
  from (values
    ('leads_dni_check', '6dcca3c962687ba896d101adf845d281'),
    ('leads_telefono_alternativo_excluyentes', 'adc22ae8c0c8d4e21ec406259be35da0'),
    ('leads_telefono_alternativo_formato', '4ce894b3dc052735877c5e1ae07b3219')) e(nombre, definicion)
  left join pg_constraint c on c.conrelid = 'crm.leads'::regclass and c.conname = e.nombre
  where c.oid is null or c.contype <> 'c' or not c.convalidated or md5(pg_get_constraintdef(c.oid)) is distinct from e.definicion;
  if v_mal is not null then
    raise exception 'POSTFLIGHT reactivar_reconoce_cliente: cambió una restricción de crm.leads que esta migración no toca (%)', v_mal;
  end if;
  -- La foto de los private.assert_*() sin argumentos (sin los `*_mutantes`) es EXACTAMENTE la de antes. No acredita PASS.
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
  if v_foto is distinct from current_setting('reactivar_reconoce_cliente.trinquetes_antes', true) then
    raise exception E'POSTFLIGHT reactivar_reconoce_cliente: algún private.assert_*() da otro resultado que antes de la migración.\nANTES:\n%\nDESPUÉS:\n%',
      current_setting('reactivar_reconoce_cliente.trinquetes_antes', true), v_foto;
  end if;
  raise notice 'POSTFLIGHT reactivar_reconoce_cliente: pieza nueva y los dos núcleos con sus huellas · pieza del 2.8, dependencias, llamadores y restricciones intactos · % trinquetes idénticos a los previos',
    v_gates;
end
$postflight$;

commit;

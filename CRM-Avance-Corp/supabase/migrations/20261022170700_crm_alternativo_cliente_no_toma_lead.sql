-- 20261022170700_crm_alternativo_cliente_no_toma_lead.sql — bloque 2.13 del plan «Mantenibilidad y consistencia del backend CRM» (fecha de trabajo 20261009235800_crm_alternativo_cliente_no_toma_lead.sql; integrado el 2026/10/22, C2 del grupo C)
-- El teléfono ALTERNATIVO de un CLIENTE no puede ser el número de un lead que ya existe y no es cliente (plan AVANCE-BACKEND-0810-F2,
-- fase 2, bloque 2.13; decisión D-49 de Miguel, 09/10/2026; plan corto aprobado D-50). Va DESPUÉS de
-- 20261009150000_crm_cliente_no_se_duplica_al_editar.sql (bloque 2.8, en su ronda 4: migración `9d135d4b…`), sobre su disparador de
-- disponibilidad y su pieza `private.juicio_cliente_convertido`: cambia ese disparador y crea una pieza de solo lectura. RONDA 2
-- (09/10/2026; auditor de permisos r1, PASS con cinco P3, `fase-2/bloque-2.13/revision/CONCILIACION.md`; decisiones D-64, D-65 y D-67):
-- «es cliente» = la ficha ya era `convertido` o lo queda bajo la válvula privilegiada (P3-1); la pieza solo mira leads vivos cuyo
-- teléfono principal ve el verificador y el conjunto real de veredictos queda declarado y probado (P3-3); lo que el rechazo revela queda
-- asentado por D-67 (P3-2); D-64, D-65 y el alternativo sin validar quedan declarados (P3-4, P3-5).
--
-- QUÉ PASA HOY (medido en ROJO, `supabase/scripts/alternativo-cliente-no-toma-lead/`: 20 de 53 comprobaciones). La regla del 2.8
-- compara lo que pone un lead contra los teléfonos de los CLIENTES; la disponibilidad del teléfono PRINCIPAL rechaza el número de otro
-- lead vivo («tomado»), pero el ALTERNATIVO no pasa por esa comprobación: si a un cliente (lead `convertido`) se le pone o cambia el
-- alternativo al teléfono —o al alternativo— de un lead VIVO que no es cliente, la edición se ACEPTA y quedan dos fichas con el mismo
-- número (por la ficha, `crm.editar_lead_fn`, y por el UPDATE directo: `authenticated` tiene UPDATE sobre `crm.leads` y la RLS no
-- distingue convertidos; la pantalla de hoy no ofrece esa edición: la ficha oculta «Editar» en un convertido y el store la bloquea).
--
-- QUÉ HACE.
--   1. PIEZA `private.juicio_lead_vivo_por_numero(p_numero, p_excluir_lead_id)` (nueva, de SOLO LECTURA: STABLE e INVOKER, dueño
--      postgres, EXECUTE solo para postgres): el número en su FORMA CANÓNICA (`private.canonizar_contacto`, la que escribe el alta y la
--      única que admite el CHECK `leads_telefono_alternativo_formato`; sobre los valores que el CHECK admite es la identidad) contra el
--      teléfono y el alternativo de cada lead VIVO —activo, ni convertido ni descartado, y cuyo teléfono PRINCIPAL está en la forma que
--      ve el verificador (`private.normalizar_telefono(telefono) = telefono`; ronda 2, auditor P3-3): exactamente el dominio del «tomado»
--      de la disponibilidad— salvo el excluido. Entre varios: el que lo tiene como TELÉFONO antes que el que lo tiene como alternativo;
--      después, el id. Si casa, el veredicto es EL QUE DA HOY LA DISPONIBILIDAD al teléfono principal de ese lead: la pieza llama al
--      verificador sellado (`private.verificar_disponibilidad_lead_impl(<su teléfono>, null, <la ficha que se edita>)`), así que es el
--      mismo byte a byte, siempre sobre ESE lead (su principal es visible: no puede salir «libre» ni contestar sobre otro), y sigue al
--      verificador si algún día cambia. El CONJUNTO REAL de veredictos (ronda 2, auditor P3-3), en el orden del verificador: si ese lead
--      o su persona están vetados, `{"estado":"no_contactar"}` (sin asesor); si un perfil ACTIVO del Portal con rol cliente tiene ese
--      teléfono, `{"estado":"ya_es_cliente","asesor":<el asesor del perfil>}`; si el lead no tiene dueño, `{"estado":"en_bolsa"}`; si no,
--      `{"estado":"tomado","vendedor":…,"tenencia_desde":…,"ultima_conversacion_en":…}`. La pantalla los presenta igual (D-36). Un
--      número sin forma canónica no casa con nada (el CHECK lo rechaza igual). Lo que NO se nombra (como hoy la disponibilidad tampoco lo
--      ve; límites declarados, se cuentan antes de publicar, D-65): un lead vivo heredado cuyo teléfono principal no está en la forma
--      canónica (N12) y el segundo número que solo esté en `telefono_alternativo_crudo` (lo que el importador no pudo canonizar; no se
--      compara, como en el 2.8: auditor P3-5).
--   2. DISPARADOR `private.trg_leads_disponibilidad_atomica()`, por ancla única, CON SESIÓN y DESPUÉS de todo lo que ya juzga hoy (rol,
--      vetos propios, enfriamiento propio, verificador) y de la regla del 2.8 (el número de OTRO CLIENTE ⇒ «ya es cliente», que manda):
--      si la ficha ES DE UN CLIENTE —ya era `convertido`, o lo queda bajo la válvula privilegiada `crm.op_privilegiada` (la conversión
--      real); ronda 2, auditor P3-1: una conversión ILEGAL sin válvula no llega a esta regla y la para después la guarda de la conversión
--      (`private.leads_before_update`, P0001) SIN veredicto, así que no sirve para sondear de quién es un número— y su alternativo
--      CAMBIA, la pieza con el alternativo nuevo, nunca contra la propia ficha. (a) UPDATE
--      que solo cambia el alternativo: si hay veredicto, primero el rol (42501 «Acceso CRM revocado» a quien no puede registrar: nunca ve
--      el veredicto) y después el MISMO `P0481` «Contacto no disponible» con el veredicto en el detalle, como en el 2.8; (b) UPDATE que
--      cambia además el teléfono o el DNI: el mismo `P0481` (el rol ya se comprobó al entrar en esa rama). Bajo la válvula privilegiada
--      se juzga igual (como el alternativo en el 2.8, ronda 3). El juicio corre bajo el candado por número de la ronda 4 del 2.8: el
--      disparador ya toma `telefono:` + el alternativo viejo y el nuevo ANTES de juzgar, la misma clave que pide quien pone ese número
--      como teléfono o como alternativo.
--   3. Al comentario del disparador (el que deja el 2.8) se le AÑADE el del 2.13; la reversa lo quita.
--
-- NO CAMBIA (y por qué): los leads que NO son clientes (D-49 solo habla del cliente; «el alternativo de un lead que no es cliente
-- contra otro lead que tampoco lo es» queda fuera del plan); el alternativo LIBRE y quitarlo; el número de un lead RETIRADO (como el
-- teléfono principal hoy: la rama «tomado» del verificador exige `activo = true`, medido en N3m) o DESCARTADO (no es «tomado»; el
-- principal lo para con «enfriamiento»/«reutilizable»: medido en N4m; D-64 de Miguel: solo leads VIVOS —asignados, en la bolsa o vetados
-- vivos—, y si alguien rescata ese descartado, el bloque 2.16 lo frena con «ya es cliente de X»); lo que la edición no toca (D-25: un
-- cliente que YA comparte su alternativo con un lead vivo sigue editándose, y no se mira su teléfono principal ni su DNI con esta regla;
-- D-65: las otras dos vías del mismo duplicado —el segundo teléfono puesto ANTES de convertir, que la conversión no cambia, y el teléfono
-- PRINCIPAL de un cliente que es el alternativo de un lead vivo— se dejan y se cuentan en producción antes de publicar el grupo C); el
-- número de OTRO cliente (lo juzga el 2.8, igual que hoy); lo que corre SIN SESIÓN (el importador, escrituras internas: el disparador
-- sale antes, como hoy); el INSERT (con sesión no nace un convertido); el verificador, la pieza del 2.8, el núcleo del alta, la ficha,
-- los disparadores de tabla, tablas, grants, policies ni nada de `public`. Los duplicados que ya existen se dejan (D-25). Lo que SÍ
-- cambia de código, medido: un alternativo de cliente escrito sin forma canónica (sin `+51`, con espacios) que en su forma canónica es
-- el número de un lead vivo pasa del `23514` del CHECK de formato al `P0481` del lead vivo; y un UPDATE que convierte y pone el
-- alternativo a la vez, con el número de otro lead vivo, recibe el `P0481` antes que la guarda de la conversión (`P0001`).
-- QUÉ REVELA EL RECHAZO (D-67 de Miguel, 09/10/2026, extensión de D-29; auditor de permisos r1, P3-2): dice de quién es el lead
-- también cuando coincide por su SEGUNDO teléfono —el asesor, desde cuándo lo tiene y su última conversación; o que está en la bolsa; o
-- su veto, sin nombre; o el asesor del perfil del Portal—, aunque ese lead esté fuera de la cartera o del subárbol de quien edita, y el
-- intento NO queda en el registro anti-pesca (`crm.verificaciones_lead`: la transacción se deshace). Es la primera vía que revela el
-- dueño de un lead por su número alternativo. Aceptado como hoy con el principal (D-29) y como pide D-49 («decir de quién es»); ningún
-- dato personal del lead sale en el detalle; lo ven solo quienes pueden editar un cliente (vendedor, supervisor, Gerencia activos).
-- PANTALLA: el error es el mismo P0481 de hoy con el veredicto del verificador en el detalle; la edición de la ficha lo presenta con
-- el texto del «tomado» («Este contacto ya está asignado a X.»), del «en_bolsa» o del «ya_es_cliente», y el veto con el texto fijo de
-- hoy (`app/src/data/crm-api.ts`, `aErrorEditarLead`, D-36). Hoy la pantalla no ofrece esta edición: la regla protege la API.
-- ORDEN EN EL GRUPO C: después del 2.8 en su ronda 4 (este preflight lo exige). El 2.16 (D-62; copia `fase2b`, después del 2.11)
-- completa D-64 —un descartado cuyo número ya es el alternativo de un cliente no vuelve a la cartera—: los dos se publican en el mismo
-- grupo C; entre sí no dependen (objetos distintos), pero cualquier bloque aplicado antes que este que cambie una de las piezas fijadas
-- abajo o los 30 trinquetes hace abortar este preflight (re-medir, no saltarse).
--
-- PREFLIGHT (falla cerrada; si algo no coincide no se instala nada): que no esté ya aplicada (ni la pieza —con cualquier firma— ni su
-- llamada); el disparador con las huellas que deja la ronda 4 del 2.8 (`md5(prosrc)` 50a6ff4365ffa6bedfd77d215ce31666,
-- `md5(pg_get_functiondef)` 418b097675753ed9f81931a485b17c94), su ficha (dueño postgres, DEFINER, `search_path` vacío y `lock_timeout`
-- 5s y nada más, EXECUTE solo para postgres sin opción de concesión) y su comentario (md5 4a3fee01861a0fc10af38eb3fc338eb2); la pieza
-- del 2.8 (346f48a8648248b308628301d41bc4c0 / a2b38faf42a875c7dffb7968b106e36f), su ficha (INVOKER de postgres, STABLE, `search_path`
-- vacío, EXECUTE solo para postgres) y su comentario (md5 e23707e521c5878f056c0b99b02a9651); los dos disparadores de tabla de
-- disponibilidad (definición md5 fd430e026c17ce4ca3ed0d74b48ba0e1 y a585ac769d92cd1f2aba0c4cf49ca83a, habilitados); y por su DEFINICIÓN
-- COMPLETA, su dueño y su ACL EFECTIVA las piezas de las que depende la regla (`private.canonizar_contacto`, la forma canónica;
-- `private.bloquear_contactos_lead` y `private.normalizar_telefono`, la clave del candado; `private.rol_crm`, el rol;
-- `private.verificar_disponibilidad_lead_impl(text,text,uuid)`, el veredicto que se repite) y la ficha cuya edición protege
-- (`crm.editar_lead_fn`, `crm.editar_lead_documento_fn`); el CHECK `leads_telefono_alternativo_formato` (el alternativo se guarda
-- siempre canónico); y el inventario y las definiciones de los 30 `private.assert_*()` que se barren. Fotografía las fichas, lo que no
-- se toca y esos `assert_*()` (SIN los `*_mutantes`, como el 2.7 y el 2.8).
-- POSTFLIGHT: la pieza con su cuerpo EXACTO, su ficha, su ACL y su comentario EXACTO; el disparador con su cuerpo nuevo EXACTO (dos
-- llamadas a la pieza; las tres de la pieza del 2.8 intactas), la misma ficha que antes y su comentario nuevo EXACTO; los disparadores
-- de tabla con su definición, el MISMO oid y habilitados; la pieza del 2.8, el núcleo del alta, las dependencias, la ficha y el CHECK
-- intactos; la foto de los trinquetes EXACTAMENTE igual que antes.
--
-- CÓMO SE REVIERTE: `supabase/scripts/alternativo-cliente-no-toma-lead/reversa.sql` (falla cerrada: exige EXACTAMENTE lo que deja esta
-- migración y que nadie más use la pieza —otra función por su cuerpo, sin distinguir mayúsculas; un `cron.job`; un objeto registrado en
-- `pg_depend`—; repone el disparador del 2.8 por ancla única y su comentario, y borra la pieza sin CASCADE). No deshace datos (la regla
-- no escribe ninguno). Tras revertir, el alternativo de un cliente vuelve a poder ser el número de un lead vivo. Mismo ciclo que la
-- migración. Ensayo: `supabase/scripts/alternativo-cliente-no-toma-lead/` (ROJO/VERDE, mutantes, derivas, reversa con y sin cambios
-- posteriores, trinquetes y los oráculos del 2.4, del 2.7 y del 2.8 encima).
-- RESELLE C1 (13/10/2026): el censo de los private.assert_*() del preflight fija los 29 que ningún bloque toca y de private.assert_gestion_diaria_resultado() solo exige que exista (la forma del 2.10), porque el 2.16 lo re-sella y esta migración tiene que entrar igual antes o después de él; el resto no cambia.
-- RESELLE C2 (22/10/2026, plan AVANCE-BACKEND-1310-C2): el censo de los 29 private.assert_*() que ningún bloque toca se fija por el de producción del 22/10 (29|60a08512…, antes 29|a11bf250…: mismos 29 nombres, 10 definiciones cambiadas por producción: SLA por filas 17/10, pendientes recientes 20/10 y otras); la forma (29 + que exista el trinquete del 2.16) no cambia; regla, mensajes y candados sin cambio.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $preflight$
declare
  v_disp regprocedure := to_regprocedure('private.trg_leads_disponibilidad_atomica()');
  v_pieza28 regprocedure := to_regprocedure('private.juicio_cliente_convertido(text,text,text,uuid)');
  v_mal text;
  r record;
  v text;
  v_foto text := '';
begin
  if v_disp is null or v_pieza28 is null then
    raise exception 'PREFLIGHT alternativo_cliente_no_toma_lead: falta el disparador de disponibilidad o la pieza del 2.8 (esta migración va después del 2.8)';
  end if;
  -- Ya aplicada (o una función con ese nombre ya existe, con cualquier firma): no se reinstala nada.
  if exists (select 1 from pg_proc p where p.pronamespace = 'private'::regnamespace and p.proname = 'juicio_lead_vivo_por_numero')
     or position('juicio_lead_vivo_por_numero' in (select p.prosrc from pg_proc p where p.oid = v_disp)) > 0 then
    raise exception 'PREFLIGHT alternativo_cliente_no_toma_lead: ya existe private.juicio_lead_vivo_por_numero o su llamada: esta migración ya está aplicada';
  end if;
  -- El disparador que deja la ronda 4 del 2.8, exacto: cuerpo, definición, ficha y comentario.
  if (select md5(p.prosrc) from pg_proc p where p.oid = v_disp) is distinct from '50a6ff4365ffa6bedfd77d215ce31666'
     or md5(pg_get_functiondef(v_disp)) is distinct from '418b097675753ed9f81931a485b17c94' then
    raise exception 'PREFLIGHT alternativo_cliente_no_toma_lead: el disparador private.trg_leads_disponibilidad_atomica no es el que deja el bloque 2.8 en su ronda 4 (md5 del cuerpo %, de la definición %; se esperaban 50a6ff4365ffa6bedfd77d215ce31666 y 418b097675753ed9f81931a485b17c94): revisar el cuerpo vivo antes de parchear',
      (select md5(p.prosrc) from pg_proc p where p.oid = v_disp), md5(pg_get_functiondef(v_disp));
  end if;
  if not exists (select 1 from pg_proc p
                  where p.oid = v_disp and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                    and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_disp)
        is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_disp, 'EXECUTE') or has_function_privilege('authenticated', v_disp, 'EXECUTE')
     or has_function_privilege('service_role', v_disp, 'EXECUTE') then
    raise exception 'PREFLIGHT alternativo_cliente_no_toma_lead: la ficha del disparador no es la auditada (dueño postgres, security definer, search_path vacío y lock_timeout 5s, EXECUTE solo para postgres sin opción de concesión)';
  end if;
  if md5(coalesce(obj_description(v_disp, 'pg_proc'), '')) is distinct from '4a3fee01861a0fc10af38eb3fc338eb2' then
    raise exception 'PREFLIGHT alternativo_cliente_no_toma_lead: el comentario del disparador no es el que deja el 2.8; revisar antes de añadirle nada (la reversa lo repone)';
  end if;
  -- La pieza del 2.8 (su veredicto manda sobre el de esta regla), exacta: cuerpo, definición, ficha y comentario.
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_pieza28)
       is distinct from '346f48a8648248b308628301d41bc4c0/a2b38faf42a875c7dffb7968b106e36f'
     or not exists (select 1 from pg_proc p where p.oid = v_pieza28 and p.proowner = 'postgres'::regrole::oid and not p.prosecdef
                      and p.provolatile = 's' and p.proconfig = array['search_path=""'])
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_pieza28)
        is distinct from array['postgres:EXECUTE:false']
     or md5(coalesce(obj_description(v_pieza28, 'pg_proc'), '')) is distinct from 'e23707e521c5878f056c0b99b02a9651' then
    raise exception 'PREFLIGHT alternativo_cliente_no_toma_lead: la pieza private.juicio_cliente_convertido no es la que deja el 2.8 (cuerpo, ficha, permisos o comentario): lo ensayado no valdría';
  end if;
  -- Los dos disparadores de tabla de disponibilidad, exactos y habilitados (el de la edición mira ya el alternativo: 2.8).
  if (select md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text from pg_trigger t
        where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_insert') is distinct from 'fd430e026c17ce4ca3ed0d74b48ba0e1|O'
     or (select md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text from pg_trigger t
        where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update') is distinct from 'a585ac769d92cd1f2aba0c4cf49ca83a|O' then
    raise exception 'PREFLIGHT alternativo_cliente_no_toma_lead: los disparadores de tabla trg_leads_00_disponibilidad_insert/_update no son los auditados (definición o estado)';
  end if;
  -- Las piezas de las que depende la regla y la ficha cuya edición protege: su DEFINICIÓN COMPLETA (cuerpo y atributos), su dueño y
  -- su ACL EFECTIVA (los valores por defecto expandidos, con la opción de concesión).
  select string_agg(e.firma, ', ' order by e.firma) into v_mal
  from (values
    ('crm.editar_lead_documento_fn(uuid,jsonb,text,text,uuid,text)', 'd0959691ad963cc409487cd63a4296d3', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.editar_lead_fn(uuid,jsonb)', 'b8ed6e9aebefd46627c8096594747aac', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.bloquear_contactos_lead(text[],text[])', '0d52f58c2065c1c0dc37a7587eda5882', 'postgres:EXECUTE:false'),
    ('private.canonizar_contacto(text)', '556d73d4bdd8d5bdd9ddc9fee23a536e', 'postgres:EXECUTE:false'),
    ('private.normalizar_telefono(text)', '00c30277b752de13be3ee0599485e6a9', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.rol_crm(uuid)', '99827f3fe2fbc3cfae5668c30015c758', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.verificar_disponibilidad_lead_impl(text,text,uuid)', 'cece9dd168c9beea935af2e05895e32a', 'postgres:EXECUTE:false')) e(firma, definicion, acl)
  left join pg_proc p on p.oid = to_regprocedure(e.firma)
  where p.oid is null
     or md5(pg_get_functiondef(p.oid)) is distinct from e.definicion
     or p.proowner is distinct from 'postgres'::regrole::oid
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) is distinct from e.acl;
  if v_mal is not null then
    raise exception 'PREFLIGHT alternativo_cliente_no_toma_lead: cambió una pieza de la que depende la regla o la ficha cuya edición protege (%: definición, dueño o permisos); lo ensayado no valdría', v_mal;
  end if;
  -- La premisa de la comparación en forma canónica: el alternativo se guarda SIEMPRE canónico (el CHECK de formato, validado).
  if not exists (select 1 from pg_constraint c
                  where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_telefono_alternativo_formato' and c.contype = 'c'
                    and c.convalidated and md5(pg_get_constraintdef(c.oid)) = '4ce894b3dc052735877c5e1ae07b3219') then
    raise exception 'PREFLIGHT alternativo_cliente_no_toma_lead: cambió o falta la restricción leads_telefono_alternativo_formato de crm.leads (la comparación en forma canónica depende de ella)';
  end if;
  -- El inventario y las DEFINICIONES de los trinquetes que se barren abajo, ANTES del primer barrido: tienen que ser los auditados (no
  -- se exige que pasen; se exige que sean ellos). Se fijan los 29 que ningún bloque de la fase 2 toca; el trinquete
  -- private.assert_gestion_diaria_resultado() lo RE-SELLA el 2.16 (su huella es suya y cambia con sus rondas): de él solo se exige que
  -- exista. Así esta migración se instala igual antes o después del 2.16 (el orden fijado es después). El barrido y la foto del
  -- postflight lo incluyen igual: comparan el RESULTADO de cada uno antes y después, no su huella.
  if (select count(*) || '|' || md5(string_agg(p.oid::regprocedure::text || ':' || md5(pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text collate "C"))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0 and p.proname <> 'assert_gestion_diaria_resultado')
     is distinct from '29|60a0851245859d8e1f0da6e2276a2594'
     or to_regprocedure('private.assert_gestion_diaria_resultado()') is null then
    raise exception 'PREFLIGHT alternativo_cliente_no_toma_lead: los private.assert_*() que barre la migración no son los auditados (inventario o definiciones de los 29 que no re-sella el 2.16: %; y el trinquete private.assert_gestion_diaria_resultado() tiene que existir); revisarlos antes de barrerlos',
      (select count(*) || '|' || md5(string_agg(p.oid::regprocedure::text || ':' || md5(pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text collate "C"))
         from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0 and p.proname <> 'assert_gestion_diaria_resultado');
  end if;
  -- Fotos para el postflight: la ficha del disparador, el oid del disparador de tabla de la edición, lo que no se toca (la pieza del
  -- 2.8, el núcleo del alta, el alta y el verificador sin argumento de exclusión: definición, ACL y comentario) y los
  -- private.assert_*() sin argumentos y SIN los `*_mutantes` (estado y texto íntegro del primer error: se exige que NO cambien).
  perform set_config('alternativo_cliente.disp_antes',
    (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_disp), true);
  perform set_config('alternativo_cliente.trg_oid',
    (select t.oid::text from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update'), true);
  perform set_config('alternativo_cliente.intocables_antes',
    (select string_agg(e.firma || ':' || coalesce(md5(pg_get_functiondef(p.oid)) || '|' || coalesce(p.proacl::text, '-') || '|'
                       || md5(coalesce(obj_description(p.oid, 'pg_proc'), '')), 'AUSENTE'), ',' order by e.firma)
       from (values ('private.juicio_cliente_convertido(text,text,text,uuid)'),
                    ('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'),
                    ('crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'),
                    ('private.verificar_disponibilidad_lead_impl(text,text)')) e(firma)
       left join pg_proc p on p.oid = to_regprocedure(e.firma)), true);
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
  perform set_config('alternativo_cliente.trinquetes_antes', v_foto, true);
end
$preflight$;

-- ── 1. La pieza (solo lectura) ─────────────────────────────────────────────────────────────────────────────────────────
create function private.juicio_lead_vivo_por_numero(p_numero text, p_excluir_lead_id uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_num text := (select c.e164 from private.canonizar_contacto(p_numero) c);
  v_telefono text;
  v_juicio jsonb;
begin
  -- Sin forma canónica no casa con nada (el CHECK de formato lo rechaza al guardar).
  if v_num is null then
    return null;
  end if;
  -- El número (canónico) contra el teléfono y el alternativo de cada lead VIVO —activo, ni convertido ni descartado, y cuyo teléfono
  -- principal está en la forma que ve el verificador (un principal heredado fuera de ella es invisible para la disponibilidad de hoy y
  -- lo sigue siendo aquí: ronda 2): exactamente el dominio del «tomado»—, salvo el excluido. El que lo tiene como teléfono antes que el
  -- que lo tiene como alternativo; después, id.
  select l.telefono
    into v_telefono
  from crm.leads l
  where l.id is distinct from p_excluir_lead_id
    and l.activo = true
    and l.etapa not in ('convertido', 'descartado')
    and private.normalizar_telefono(l.telefono) = l.telefono
    and (l.telefono = v_num or l.telefono_alternativo = v_num)
  order by case when l.telefono = v_num then 1 else 2 end, l.id
  limit 1;
  if not found then
    return null;
  end if;
  -- El veredicto es el que la disponibilidad da HOY al teléfono principal de ese lead (el verificador sellado, sin DNI y sin la ficha
  -- que se edita), siempre sobre ESE lead: «no_contactar» si él o su persona están vetados, «ya_es_cliente» con su asesor si un perfil
  -- activo del Portal tiene ese teléfono, «en_bolsa» si no tiene dueño o «tomado» con su asesor. Nunca «libre»: el lead es visible para
  -- el verificador por construcción (principal en su forma, vivo, no excluido).
  v_juicio := private.verificar_disponibilidad_lead_impl(v_telefono, null, p_excluir_lead_id);
  return v_juicio;
end;
$function$;

-- Dueño postgres SIEMPRE (como el disparador que la llama), corra quien corra la migración; EXECUTE solo para él.
alter function private.juicio_lead_vivo_por_numero(text, uuid) owner to postgres;
revoke all on function private.juicio_lead_vivo_por_numero(text, uuid) from public, anon, authenticated, service_role;

comment on function private.juicio_lead_vivo_por_numero(text, uuid) is
  'Bloque 2.13 (D-49, D-50, D-64, D-67; sobre la regla del bloque 2.8; ronda 2). Pieza de SOLO LECTURA: dado un numero y un lead que excluir, compara el numero en su forma canonica (private.canonizar_contacto) con el telefono y el telefono alternativo de cada lead VIVO (activo, ni convertido ni descartado, con el telefono principal en la forma que ve el verificador: el dominio del tomado de la disponibilidad) y, si casa, devuelve el veredicto que la disponibilidad da hoy al telefono principal de ese lead (private.verificar_disponibilidad_lead_impl, sin DNI y sin el lead excluido): no_contactar si el lead o su persona estan vetados, ya_es_cliente con su asesor si un perfil activo del Portal tiene ese telefono, en_bolsa si no tiene dueno o tomado con su asesor; o NULL si ningun lead vivo visible lo tiene. Entre varios: el que lo tiene como telefono antes que el que lo tiene como alternativo; despues, id. La usa el disparador de disponibilidad (private.trg_leads_disponibilidad_atomica) para el alternativo nuevo de un cliente. STABLE e INVOKER: no escribe; solo la ejecuta postgres.';

-- ── 2. El disparador de disponibilidad, por ancla única ──────────────────────────────────────────────────────────────
do $disparador$
declare
  v_firma regprocedure := 'private.trg_leads_disponibilidad_atomica()'::regprocedure;
  v_def text;
  v_acl aclitem[];
  v_ancla text;
  v_nuevo text;
  v_veces integer;
begin
  select pg_get_functiondef(p.oid), p.proacl into v_def, v_acl from pg_proc p where p.oid = v_firma;

  -- Ancla 1 (UPDATE que solo cambia el alternativo, con sesión): si la ficha es de un cliente y su alternativo nuevo no es de otro
  -- cliente, la pieza; el rol y el P0481 son los del 2.8, justo debajo.
  v_ancla := $a1$        v_cliente := private.juicio_cliente_convertido(null, new.telefono_alternativo, null, old.id);
        if v_cliente is not null then
          v_rol := private.rol_crm(v_actor);
$a1$;
  v_nuevo := $n1$        v_cliente := private.juicio_cliente_convertido(null, new.telefono_alternativo, null, old.id);
        -- Bloque 2.13 (D-49 de Miguel, 09/10/2026; ronda 2, auditor P3-1). Si la ficha es de un CLIENTE —ya era `convertido`, o lo
        -- queda bajo la válvula privilegiada (la conversión real); una conversión ilegal sin válvula no llega aquí: la para después la
        -- guarda de la conversión, sin veredicto— y su alternativo nuevo no es el número de otro cliente (el 2.8, arriba, manda),
        -- tampoco puede ser el teléfono ni el alternativo de OTRO lead VIVO (`private.juicio_lead_vivo_por_numero`: en forma canónica,
        -- nunca contra la propia ficha): el veredicto que la disponibilidad da hoy a ese lead («tomado» con su asesor, «en_bolsa», su
        -- veto o «ya_es_cliente» por su perfil del Portal), con el rol primero y el mismo P0481 de abajo.
        if v_cliente is null and new.etapa = 'convertido' and (old.etapa = 'convertido' or v_priv) then
          v_cliente := private.juicio_lead_vivo_por_numero(new.telefono_alternativo, old.id);
        end if;
        if v_cliente is not null then
          v_rol := private.rol_crm(v_actor);
$n1$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT alternativo_cliente_no_toma_lead: el ancla del UPDATE que solo cambia el alternativo aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  -- Ancla 2 (UPDATE que cambia además el teléfono o el DNI, con sesión): después de la regla del 2.8, la misma pieza.
  v_ancla := $a2$      case when not v_priv and new.dni is distinct from old.dni then new.dni end,
      old.id);
    if v_cliente is not null then
      raise exception using
$a2$;
  v_nuevo := $n2$      case when not v_priv and new.dni is distinct from old.dni then new.dni end,
      old.id);
    -- Bloque 2.13 (D-49; ronda 2, auditor P3-1): con el teléfono o el DNI, el alternativo nuevo de un CLIENTE (ya convertido, o que lo
    -- queda bajo la válvula privilegiada) tampoco puede ser el número de OTRO lead vivo (la misma pieza y el mismo veredicto que en la
    -- rama del alternativo; el rol ya se comprobó al entrar en esta rama).
    if v_cliente is null and new.etapa = 'convertido' and (old.etapa = 'convertido' or v_priv)
       and new.telefono_alternativo is distinct from old.telefono_alternativo then
      v_cliente := private.juicio_lead_vivo_por_numero(new.telefono_alternativo, old.id);
    end if;
    if v_cliente is not null then
      raise exception using
$n2$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT alternativo_cliente_no_toma_lead: el ancla del UPDATE con cambio de teléfono o DNI aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  execute v_def;

  if (select p.proacl from pg_proc p where p.oid = v_firma) is distinct from v_acl then
    raise exception 'POSTFLIGHT alternativo_cliente_no_toma_lead: los permisos del disparador cambiaron al parchear';
  end if;
end
$disparador$;

-- ── 3. El comentario: al del 2.8 se le AÑADE el del 2.13; la reversa lo quita ─────────────────────────────────────────
do $comentario$
begin
  execute pg_catalog.format('comment on function private.trg_leads_disponibilidad_atomica() is %L',
    obj_description('private.trg_leads_disponibilidad_atomica()'::regprocedure, 'pg_proc')
      || $c$ Bloque 2.13 (D-49, D-64, D-67; ronda 2): con sesion, si el lead es cliente (ya era convertido, o lo queda bajo la valvula privilegiada: la conversion) y su telefono alternativo cambia, el nuevo no puede ser el telefono ni el alternativo de otro lead vivo que no es cliente (private.juicio_lead_vivo_por_numero, en forma canonica; nunca contra el propio lead): P0481 Contacto no disponible con el veredicto de la disponibilidad de hoy para el telefono de ese lead (tomado con su asesor, en_bolsa, no_contactar o ya_es_cliente), despues de los veredictos de hoy y de la regla del 2.8; si solo cambia el alternativo, primero el rol. Una conversion sin valvula no llega a esta regla. Sin sesion, la regla no se aplica.$c$);
end
$comentario$;

-- ── Postflight ───────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_pieza regprocedure := to_regprocedure('private.juicio_lead_vivo_por_numero(text,uuid)');
  v_disp regprocedure := 'private.trg_leads_disponibilidad_atomica()'::regprocedure;
  v_src text;
  v_h text;
  v_mal text;
  r record;
  v text;
  v_foto text := '';
  v_gates integer := 0;
begin
  -- La pieza: cuerpo exacto, INVOKER de postgres, STABLE, search_path vacío y nada más, EXECUTE solo para postgres, comentario exacto.
  if v_pieza is null then
    raise exception 'POSTFLIGHT alternativo_cliente_no_toma_lead: la pieza private.juicio_lead_vivo_por_numero no quedó creada';
  end if;
  v_h := (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_pieza);
  if v_h is distinct from '2ade8f1b7f020b8aca16de0361f4d5c0/18d344cd251b79b3fcc851c2ac6114ce' then
    raise exception 'POSTFLIGHT alternativo_cliente_no_toma_lead: la pieza no quedó exactamente como se ensayó (md5 del cuerpo / de la definición %)', v_h;
  end if;
  if not exists (select 1 from pg_proc p where p.oid = v_pieza and p.proowner = 'postgres'::regrole::oid and not p.prosecdef
                   and p.provolatile = 's' and p.proconfig = array['search_path=""'])
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_pieza)
        is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_pieza, 'EXECUTE') or has_function_privilege('authenticated', v_pieza, 'EXECUTE')
     or has_function_privilege('service_role', v_pieza, 'EXECUTE')
     or md5(coalesce(obj_description(v_pieza, 'pg_proc'), '')) is distinct from 'cf8d4141b2e4d225796250c56b8ee498' then
    raise exception 'POSTFLIGHT alternativo_cliente_no_toma_lead: la ficha de la pieza no es la esperada (INVOKER de postgres, STABLE, search_path vacío, EXECUTE solo para postgres, comentario EXACTO del 2.13; comentario md5 %)',
      md5(coalesce(obj_description(v_pieza, 'pg_proc'), ''));
  end if;
  -- El disparador: la pieza dos veces y la del 2.8 tres, cuerpo exacto, la misma ficha que antes, comentario exacto.
  select p.prosrc, md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) into v_src, v_h from pg_proc p where p.oid = v_disp;
  if (length(v_src) - length(replace(v_src, 'private.juicio_lead_vivo_por_numero(', ''))) / length('private.juicio_lead_vivo_por_numero(') <> 2
     or (length(v_src) - length(replace(v_src, 'private.juicio_cliente_convertido(', ''))) / length('private.juicio_cliente_convertido(') <> 3 then
    raise exception 'POSTFLIGHT alternativo_cliente_no_toma_lead: el disparador no quedó con sus dos llamadas a la pieza (y las tres de la del 2.8)';
  end if;
  if v_h is distinct from '9bb6fb76c3715364c6adca8401ade0b6/d882780ca2449f7fbcadf4b0ce84cdf2' then
    raise exception 'POSTFLIGHT alternativo_cliente_no_toma_lead: el disparador no quedó exactamente como se ensayó (md5 del cuerpo / de la definición %)', v_h;
  end if;
  if (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
             || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
        from pg_proc p where p.oid = v_disp) is distinct from current_setting('alternativo_cliente.disp_antes', true)
     or has_function_privilege('anon', v_disp, 'EXECUTE') or has_function_privilege('authenticated', v_disp, 'EXECUTE')
     or has_function_privilege('service_role', v_disp, 'EXECUTE')
     or md5(coalesce(obj_description(v_disp, 'pg_proc'), '')) is distinct from '7ba4e553c1543c070ac1754f8e2dd6d0' then
    raise exception 'POSTFLIGHT alternativo_cliente_no_toma_lead: la ficha o el comentario del disparador no son los esperados (comentario md5 %)', md5(coalesce(obj_description(v_disp, 'pg_proc'), ''));
  end if;
  -- Los disparadores de tabla: intactos, el de la edición con el MISMO oid; habilitados.
  if (select md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text from pg_trigger t
        where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_insert') is distinct from 'fd430e026c17ce4ca3ed0d74b48ba0e1|O'
     or (select md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text || '|' || t.oid::text from pg_trigger t
        where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update')
        is distinct from 'a585ac769d92cd1f2aba0c4cf49ca83a|O|' || current_setting('alternativo_cliente.trg_oid', true) then
    raise exception 'POSTFLIGHT alternativo_cliente_no_toma_lead: los disparadores de tabla de disponibilidad cambiaron y esta migración no los toca';
  end if;
  -- Lo que no se toca: la pieza del 2.8, el núcleo del alta, el alta y el verificador sin exclusión (definición, ACL y comentario).
  if (select string_agg(e.firma || ':' || coalesce(md5(pg_get_functiondef(p.oid)) || '|' || coalesce(p.proacl::text, '-') || '|'
                        || md5(coalesce(obj_description(p.oid, 'pg_proc'), '')), 'AUSENTE'), ',' order by e.firma)
        from (values ('private.juicio_cliente_convertido(text,text,text,uuid)'),
                     ('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'),
                     ('crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'),
                     ('private.verificar_disponibilidad_lead_impl(text,text)')) e(firma)
        left join pg_proc p on p.oid = to_regprocedure(e.firma)) is distinct from current_setting('alternativo_cliente.intocables_antes', true) then
    raise exception 'POSTFLIGHT alternativo_cliente_no_toma_lead: cambió la pieza del 2.8, el núcleo del alta, el alta o el verificador, y esta migración no los toca';
  end if;
  -- Las dependencias, la ficha y el CHECK: intactos.
  select string_agg(e.firma, ', ' order by e.firma) into v_mal
  from (values
    ('crm.editar_lead_documento_fn(uuid,jsonb,text,text,uuid,text)', 'd0959691ad963cc409487cd63a4296d3', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.editar_lead_fn(uuid,jsonb)', 'b8ed6e9aebefd46627c8096594747aac', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.bloquear_contactos_lead(text[],text[])', '0d52f58c2065c1c0dc37a7587eda5882', 'postgres:EXECUTE:false'),
    ('private.canonizar_contacto(text)', '556d73d4bdd8d5bdd9ddc9fee23a536e', 'postgres:EXECUTE:false'),
    ('private.normalizar_telefono(text)', '00c30277b752de13be3ee0599485e6a9', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.rol_crm(uuid)', '99827f3fe2fbc3cfae5668c30015c758', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.verificar_disponibilidad_lead_impl(text,text,uuid)', 'cece9dd168c9beea935af2e05895e32a', 'postgres:EXECUTE:false')) e(firma, definicion, acl)
  left join pg_proc p on p.oid = to_regprocedure(e.firma)
  where p.oid is null
     or md5(pg_get_functiondef(p.oid)) is distinct from e.definicion
     or p.proowner is distinct from 'postgres'::regrole::oid
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) is distinct from e.acl;
  if v_mal is not null then
    raise exception 'POSTFLIGHT alternativo_cliente_no_toma_lead: cambió algo que esta migración no toca (%)', v_mal;
  end if;
  if not exists (select 1 from pg_constraint c
                  where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_telefono_alternativo_formato' and c.contype = 'c'
                    and c.convalidated and md5(pg_get_constraintdef(c.oid)) = '4ce894b3dc052735877c5e1ae07b3219') then
    raise exception 'POSTFLIGHT alternativo_cliente_no_toma_lead: cambió la restricción leads_telefono_alternativo_formato y esta migración no la toca';
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
  if v_foto is distinct from current_setting('alternativo_cliente.trinquetes_antes', true) then
    raise exception E'POSTFLIGHT alternativo_cliente_no_toma_lead: algún private.assert_*() da otro resultado que antes de la migración.\nANTES:\n%\nDESPUÉS:\n%',
      current_setting('alternativo_cliente.trinquetes_antes', true), v_foto;
  end if;
  raise notice 'POSTFLIGHT alternativo_cliente_no_toma_lead: pieza y disparador con sus huellas · disparadores de tabla, pieza del 2.8, núcleo, alta, verificador, dependencias y restricción intactos · % trinquetes idénticos a los previos',
    v_gates;
end
$postflight$;

commit;

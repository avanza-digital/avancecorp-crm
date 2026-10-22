-- 20261022170400_crm_cliente_no_se_duplica_al_editar.sql — bloque 2.8 del plan «Mantenibilidad y consistencia del backend CRM» (fecha de trabajo 20261009150000_crm_cliente_no_se_duplica_al_editar.sql; integrado el 2026/10/22, C2 del grupo C)
-- El cliente ya convertido tampoco se duplica al EDITAR un lead, por el INSERT con sesión ni por su TELÉFONO ALTERNATIVO (plan
-- AVANCE-BACKEND-0810-F2, fase 2, bloque 2.8; decisiones D-28 y D-30 de Miguel, 08/10/2026; la regla es la del bloque 2.7: D-22,
-- D-25, D-27). Va DESPUÉS de 20261008174055_crm_cliente_por_telefono.sql (bloque 2.7), que va después de
-- 20261007210152_crm_alta_reactiva_lead_retirado.sql (2.4), y sobre el disparador de disponibilidad de bases cargadas (B8,
-- 20261004184501): cambia el núcleo del alta del 2.4 + 2.7 y ese disparador, y crea una pieza común. RONDA 3 (09/10/2026; revisiones
-- del auditor de permisos y de Codex, `fase-2/bloque-2.8/revision/CONCILIACION.md`): el teléfono alternativo SIN VALIDAR
-- (`telefono_alternativo_crudo`) no se pone ni cambia con sesión; bajo la válvula privilegiada solo el DNI queda fuera de la regla;
-- la salida de la corrección de documento solo vale si cambia únicamente el DNI; las dependencias se fijan con definición completa,
-- dueño y ACL, y también los CHECK del alternativo y del DNI y el inventario de los trinquetes que se barren. RONDA 4 (09/10/2026;
-- auditor de permisos r2, P3-4): el disparador toma candado también por el teléfono ALTERNATIVO viejo y nuevo, con la MISMA clave que
-- el teléfono principal para el mismo número (la carrera del alternativo queda serializada); el preflight y el postflight fijan además
-- `private.bloquear_contactos_lead` y `private.normalizar_telefono`, de los que depende esa clave.
--
-- QUÉ PASA HOY. La regla del 2.7 («el teléfono o el DNI de un cliente ya convertido ⇒ ya es cliente de X, sin crear nada») solo
-- vive en el núcleo del ALTA. (1) La EDICIÓN de la ficha (`crm.editar_lead_fn`, INVOKER; el DNI por su puerta
-- `crm.fijar_dni_lead_fn` con la identidad encendida) cambia el teléfono o el DNI con un UPDATE que solo vigila el disparador
-- `private.trg_leads_disponibilidad_atomica`, que pregunta al verificador sellado; el verificador excluye las fichas convertidas
-- y solo reconoce un DNI por las identidades de persona ⇒ se acepta y queda un SEGUNDO lead del cliente. (2) Si solo cambia el
-- TELÉFONO ALTERNATIVO, el disparador ni se dispara (no está en su lista de columnas). (3) Un INSERT con sesión que no pase por el
-- alta (el «INSERT directo» si se concediera: hoy `authenticated` NO tiene INSERT sobre crm.leads, medido en el laboratorio =
-- producción) solo pregunta al verificador. (4) En el alta, el alternativo tecleado no se compara con nada (y nadie compara con el
-- alternativo de un cliente). Medido en ROJO: `supabase/scripts/cliente-no-se-duplica-al-editar/` (36 de 73 comprobaciones).
--
-- QUÉ HACE.
--   1. PIEZA COMÚN `private.juicio_cliente_convertido(p_telefono, p_telefono_alternativo, p_dni, p_excluir_lead_id)` (nueva, de
--      SOLO LECTURA: STABLE e INVOKER, dueño postgres, EXECUTE solo para postgres): la regla del 2.7 con el alternativo en las DOS
--      direcciones (D-30). Lo tecleado (principal y alternativo) contra los dos teléfonos de cada lead `convertido` (activo o
--      retirado), en este orden: lo tecleado como principal antes que el alternativo tecleado y, para cada uno, el principal del
--      cliente antes que su alternativo (sin alternativos de por medio es EXACTAMENTE la búsqueda del 2.7); si no casa ningún
--      teléfono, el DNI (D-27). Entre varios convertidos de un mismo grado: enlazado a persona → activo → convertido más reciente
--      (sin fecha, detrás) → id. Veredicto: enlazado ⇒ `private.juicio_persona(private.inversionista_canonica(<persona>),
--      <excluido>)` (ya_es_cliente con su asesor y via identidad, o no_contactar), o el respaldo de D-21 si no dice nada; sin
--      persona ⇒ ya_es_cliente a nombre del dueño de esa ficha, sin via. Nunca se compara con el lead excluido (el que se edita).
--   2. NÚCLEO del alta `private.alta_reactivar_retirado(…)` (2.4 + 2.7): su regla 1b llama a la pieza en vez de llevar las dos
--      búsquedas dentro, pasando además el alternativo tecleado (`v_tecleado ->> 'telefono_alternativo'`, la copia local de
--      `p_tecleado`; el alta ya lo canoniza).
--      Mismo sitio (después del filtro del veredicto, antes del candidato retirado), misma guarda del reintento (`not v_reintento`),
--      mismo veredicto; sin alternativos, el mismo comportamiento (oráculos del 2.4 y del 2.7 encima, con y sin esta migración).
--      La variable conserva su nombre `v_convertido` (el caso 3d del oráculo del 2.4 reconoce la regla del 2.7 por él).
--   3. DISPARADOR `private.trg_leads_disponibilidad_atomica()`, por ancla única, DESPUÉS de lo que ya juzga hoy y solo CON SESIÓN:
--      (a) UPDATE que cambia teléfono o DNI y que el verificador dejó pasar ⇒ la pieza con LO QUE LA EDICIÓN PONE (el teléfono, el
--      alternativo y el DNI que cambian; lo que el lead ya tenía no se juzga: los dos leads que ya comparten teléfono con un cliente
--      siguen editándose, D-23/D-25); bajo la válvula privilegiada `crm.op_privilegiada` solo el DNI queda fuera (ronda 3: bajo ella
--      solo se escribe el DNI; la conversión, hasta D-38); (b) UPDATE que SOLO cambia el alternativo ⇒ la pieza con el alternativo
--      nuevo; si hay veredicto, primero el rol (42501 a quien no puede registrar: nunca ve el veredicto); si no lo hay, todo sigue como
--      hoy; (c) INSERT con sesión que no es el contacto de base cargada que nace dormido ⇒ la pieza con todo lo tecleado. Si la pieza
--      responde ⇒ el MISMO error de hoy, `P0481` «Contacto no disponible», con el veredicto en el detalle. Ronda 3: con sesión (también
--      bajo cualquier válvula) el alternativo SIN VALIDAR (`telefono_alternativo_crudo`) no nace no nulo ni pasa a un valor no nulo
--      (42501 «El alternativo sin validar solo lo pone la importación»; conservarlo o borrarlo sigue como hoy), y la salida anticipada
--      de la corrección de documento (`crm.correccion_documento`) solo vale si cambia únicamente el DNI. Ronda 4 (auditor P3-4): el
--      candado de contacto del disparador (`private.bloquear_contactos_lead`, que toma TODO escritor —con o sin sesión— antes de
--      juzgar, como ya hacía con el teléfono y el DNI) incluye el alternativo VIEJO y el NUEVO (UPDATE) y el alternativo (INSERT) en
--      la lista de TELÉFONOS: la clave es `telefono:` + `private.normalizar_telefono(<número>)`, la misma que toma el teléfono
--      principal para el mismo número. `normalizar_telefono` no devuelve NULL para ningún valor no vacío (los vacíos no se bloquean,
--      como hoy) y es la identidad sobre las formas que admite el CHECK `leads_telefono_alternativo_formato` (móvil y fijo peruanos,
--      internacionales de 8 y de 10 a 15 dígitos), salvo el internacional de 9 dígitos, que comparte clave con el móvil peruano
--      «+51» + esos dígitos: una espera de más, nunca una de menos (ningún veredicto cambia por ello).
--   4. El disparador de tabla `trg_leads_00_disponibilidad_update` mira además `telefono_alternativo` y, desde la ronda 3,
--      `telefono_alternativo_crudo` (`create or replace trigger`: mismo nombre, mismo orden de disparo, misma función).
--
-- NO CAMBIA (y por qué): la CARGA DE BASES (corre con la sesión de quien carga, pero su contacto nace dormido bajo su válvula
-- `private.bases_carga_nace_dormido`, que la regla excluye; su veredicto sigue siendo el de su envoltorio); lo que corre SIN
-- SESIÓN (el importador `crm.importar_lead_fn`, cuyo contrato es no consultar la disponibilidad comercial; cualquier escritura sin
-- usuario: el disparador sale antes, como hoy; desde la ronda 4 toman además el candado de su alternativo: solo esperan, ningún
-- veredicto cambia; la carga de bases no escribe alternativo y no toma ninguno más); las puertas PRIVILEGIADAS (válvula `crm.op_privilegiada`: la preparación de la
-- conversión, la corrección de documento de Gerencia —que además sale antes por su propia excepción—, el documento CE/pasaporte):
-- conservan su juicio propio para el DNI (otras puertas, D-30); los veredictos que este disparador da HOY (veto propio, enfriamiento
-- propio, verificador: no contactar, cuenta del Portal, identidad, lead vivo) van antes y mandan —con tres matices medidos: un UPDATE
-- directo del DNI de un cliente que antes rechazaba otro disparador (P0409 «se fija por su puerta») ahora lo rechaza antes la regla
-- (P0481); con la identidad encendida la puerta del DNI de la ficha va primero y decide a qué cliente se nombra; y un alternativo con
-- espacios alrededor del teléfono de un cliente recibe P0481 (la pieza recorta) antes del rechazo de formato (23514)—; las ediciones
-- que no tocan teléfono,
-- alternativo ni DNI —o que los reenvían iguales— no llegan a la regla; el reintento del 2.4 (`not v_reintento`); el verificador
-- (huella sellada por la carga de bases), el alta, la ficha (`crm.editar_lead_fn`, `crm.fijar_dni_lead_fn`,
-- `crm.editar_lead_documento_fn`, `crm.fijar_documento_lead_fn`), las otras puertas (tomar un lead libre, reabrir, reactivar de
-- base), tablas, grants, policies ni nada de `public`. Los candados de contacto: desde la ronda 4 el alternativo SÍ se bloquea
-- (arriba), así que quien pone X como alternativo o como teléfono espera a quien está poniendo X como alternativo (y al revés) y la
-- regla juzga después con lo que el otro confirmó (ensayado con dos sesiones en el laboratorio, ambas con rollback; la carrera con
-- COMMIT se ensaya en la branch, F4.6). La regla sigue juzgando solo lo que se ESCRIBE contra los clientes YA convertidos: un
-- cliente que pone como alternativo el teléfono de un lead ordinario no es «otro lead del cliente» para ella (controles
-- secuenciales: F4.6; si importa, decisión de Miguel). Los duplicados que ya existen se dejan (D-25): la regla solo impide los nuevos.
-- PANTALLA: el error es el mismo P0481 de hoy con el veredicto en el detalle. El alta y, desde D-36 (ronda 2 del 2.8), la EDICIÓN
-- de la ficha lo presentan con el veredicto (`app/src/data/crm-api.ts`: `aErrorInsertarLead` y `aErrorEditarLead`, pieza común
-- `presentacionDelP0481`). El 42501 del alternativo sin validar no tiene pantalla: la ficha no escribe esa columna. D-29 (revelar
-- «ya es cliente» y el asesor sin asentar la consulta) vale igual aquí: mismos datos, mismos roles.
--
-- PREFLIGHT (falla cerrada; si algo no coincide no se instala nada): que no esté ya aplicada (ni la pieza ni su llamada); el núcleo
-- con las huellas que deja el 2.7 (`md5(prosrc)` f74838f274a8db971952eb9c09c7387e, `md5(pg_get_functiondef)`
-- c56e4abd191b947177a9179a7d558dbd), su ficha (dueño postgres, DEFINER, `search_path` vacío y `lock_timeout` 5s y nada más,
-- EXECUTE solo para postgres sin opción de concesión) y su comentario (md5 31159d826a407c91173e3870b5711352); el disparador con
-- las huellas de B8 (5543c41f89dd49b8b267b7b274b12814 / bfd4679b1d15bb2147ef78705a9d9aff; `20261004184501:1459`), su ficha y su
-- comentario (md5 5d0717955781d7c48794d240b021a148); los dos disparadores de tabla de disponibilidad (definición md5
-- fd430e026c17ce4ca3ed0d74b48ba0e1 y 5aef4753210080c9bcf5d7b16b2d4b54, habilitados); el alta (01ebf089… / 94ec2bd7…, ACL); el
-- verificador (huellas compuestas de la carga de bases); las piezas que usa la regla (`private.juicio_persona`,
-- `private.inversionista_canonica`, `private.bases_carga_nace_dormido`, `private.rol_crm`) y la del 2.4
-- (`private.alta_reactivar_bloqueo_conservado`); y la ficha cuya edición protege (`crm.editar_lead_fn`, `crm.fijar_dni_lead_fn`,
-- `crm.editar_lead_documento_fn`, `crm.fijar_documento_lead_fn`) y, ronda 4, las dos de las que depende la clave del candado del
-- alternativo (`private.bloquear_contactos_lead`, `private.normalizar_telefono`): si alguna cambió, lo ensayado no valdría. Ronda 3 (Codex F2):
-- esas dependencias y el verificador se fijan por su DEFINICIÓN COMPLETA (cuerpo y atributos: DEFINER/INVOKER, STRICT,
-- volatilidad, SET), su dueño y su ACL EFECTIVA; y también los CHECK de los que depende la comparación literal
-- (`leads_telefono_alternativo_formato`, `_excluyentes`, `_crudo_cordura`, `leads_dni_check`). Ronda 3 (Codex F5): el inventario y
-- las definiciones de los 30 `private.assert_*()` que se barren se comprueban ANTES del primer barrido (no se exige que pasen).
-- Fotografía las fichas y esos `assert_*()` (SIN los `*_mutantes`, como el 2.7: varios aplican DDL de permisos sin guarda y en la
-- base real tomarían candados ACCESS EXCLUSIVE; el ensayo `--trinquetes` barre los 36).
-- POSTFLIGHT: la pieza con su cuerpo EXACTO, su ficha, su ACL y su comentario EXACTO (ronda 3); el núcleo y el disparador con su
-- cuerpo nuevo EXACTO, la misma ficha que antes y su comentario nuevo; el disparador de tabla con su lista nueva, el MISMO oid y
-- habilitado; el de INSERT, el alta, el verificador, las dependencias (definición, dueño, ACL) y los CHECK intactos; la foto de los
-- trinquetes EXACTAMENTE igual que antes. La transacción retiene el candado SHARE ROW EXCLUSIVE del `create or replace trigger`
-- sobre `crm.leads` hasta el final, postflight incluido (medido en el laboratorio; `lock_timeout` limita la espera, no la retención).
--
-- CÓMO SE REVIERTE: `supabase/scripts/cliente-no-se-duplica-al-editar/reversa.sql` (falla cerrada: exige EXACTAMENTE lo que deja
-- esta migración y, ronda 3, que nadie más use la pieza —otra función por su cuerpo o un objeto registrado en `pg_depend`; ronda 4:
-- la búsqueda en los cuerpos no distingue mayúsculas y mira también `cron.job.command` si existe; un «posible llamador» bloquea
-- de forma conservadora (un comentario o una cadena con ese nombre también) y se inspecciona antes de revertir—; repone
-- el núcleo del 2.7 y el disparador de B8 por ancla única, la lista de columnas de hoy y los dos comentarios, y borra la pieza sin
-- CASCADE). No deshace datos (la regla no escribe ninguno). Tras revertir, editar el teléfono, el alternativo o el DNI hacia
-- los de un cliente vuelve a dejar un segundo lead (y el alta vuelve a ignorar el alternativo). Mismo ciclo que la migración.
-- Ensayo: `supabase/scripts/cliente-no-se-duplica-al-editar/` (ROJO/VERDE, mutantes, derivas, reversa, reversa con un cambio
-- posterior, trinquetes y los oráculos del 2.4 y del 2.7 encima).
-- RESELLE C2 (22/10/2026, plan AVANCE-BACKEND-1310-C2): el alta que deja el 2.4 re-asentado contra producción del 22/10 se fija por 30109c53…/e06eca23… (antes 01ebf089…/94ec2bd7…; cambió por 20261015171407 y 20261016183308, el parche del 2.4 es el mismo), en preflight y postflight; y el censo de los 30 private.assert_*() que se barren, por el de producción del 22/10 (30|3cefe40e…, antes 30|bc19c770…: mismos 30 nombres, 10 definiciones cambiadas por producción); regla, mensajes y candados sin cambio.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $preflight$
declare
  v_nucleo regprocedure := to_regprocedure('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)');
  v_disp regprocedure := to_regprocedure('private.trg_leads_disponibilidad_atomica()');
  v_alta regprocedure := to_regprocedure('crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)');
  v_mal text;
  r record;
  v text;
  v_foto text := '';
begin
  if v_nucleo is null or v_disp is null or v_alta is null then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: falta el núcleo del 2.4 + 2.7, el disparador de disponibilidad o el alta (esta migración va después del 2.7)';
  end if;
  -- Ya aplicada (o una función con ese nombre ya existe, con cualquier firma): no se reinstala nada.
  if exists (select 1 from pg_proc p where p.pronamespace = 'private'::regnamespace and p.proname = 'juicio_cliente_convertido')
     or position('juicio_cliente_convertido' in (select p.prosrc from pg_proc p where p.oid = v_nucleo)) > 0
     or position('juicio_cliente_convertido' in (select p.prosrc from pg_proc p where p.oid = v_disp)) > 0 then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: ya existe private.juicio_cliente_convertido o su llamada: esta migración ya está aplicada';
  end if;
  -- El núcleo que deja el 2.7, exacto: cuerpo, definición, ficha y comentario.
  if (select md5(p.prosrc) from pg_proc p where p.oid = v_nucleo) is distinct from 'f74838f274a8db971952eb9c09c7387e'
     or md5(pg_get_functiondef(v_nucleo)) is distinct from 'c56e4abd191b947177a9179a7d558dbd' then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: el núcleo private.alta_reactivar_retirado no es el que deja el bloque 2.7 (md5 del cuerpo %, de la definición %; se esperaban f74838f274a8db971952eb9c09c7387e y c56e4abd191b947177a9179a7d558dbd): revisar el cuerpo vivo antes de parchear',
      (select md5(p.prosrc) from pg_proc p where p.oid = v_nucleo), md5(pg_get_functiondef(v_nucleo));
  end if;
  if not exists (select 1 from pg_proc p
                  where p.oid = v_nucleo and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                    and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_nucleo)
        is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_nucleo, 'EXECUTE') or has_function_privilege('authenticated', v_nucleo, 'EXECUTE')
     or has_function_privilege('service_role', v_nucleo, 'EXECUTE') then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: la ficha del núcleo no es la auditada (dueño postgres, security definer, search_path vacío y lock_timeout 5s, EXECUTE solo para postgres sin opción de concesión)';
  end if;
  if md5(coalesce(obj_description(v_nucleo, 'pg_proc'), '')) is distinct from '31159d826a407c91173e3870b5711352' then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: el comentario del núcleo no es el que deja el 2.7; revisar antes de añadirle nada (la reversa lo repone)';
  end if;
  -- El disparador de disponibilidad de B8, exacto: cuerpo, definición, ficha y comentario.
  if (select md5(p.prosrc) from pg_proc p where p.oid = v_disp) is distinct from '5543c41f89dd49b8b267b7b274b12814'
     or md5(pg_get_functiondef(v_disp)) is distinct from 'bfd4679b1d15bb2147ef78705a9d9aff' then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: el disparador private.trg_leads_disponibilidad_atomica no es el de bases cargadas (B8, 20261004184501) (md5 del cuerpo %, de la definición %; se esperaban 5543c41f89dd49b8b267b7b274b12814 y bfd4679b1d15bb2147ef78705a9d9aff): revisar el cuerpo vivo antes de parchear',
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
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: la ficha del disparador no es la auditada (dueño postgres, security definer, search_path vacío y lock_timeout 5s, EXECUTE solo para postgres sin opción de concesión)';
  end if;
  if md5(coalesce(obj_description(v_disp, 'pg_proc'), '')) is distinct from '5d0717955781d7c48794d240b021a148' then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: el comentario del disparador no es el de B8; revisar antes de añadirle nada (la reversa lo repone)';
  end if;
  -- Los dos disparadores de tabla de disponibilidad, exactos y habilitados.
  if (select md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text from pg_trigger t
        where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_insert') is distinct from 'fd430e026c17ce4ca3ed0d74b48ba0e1|O'
     or (select md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text from pg_trigger t
        where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update') is distinct from '5aef4753210080c9bcf5d7b16b2d4b54|O' then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: los disparadores de tabla trg_leads_00_disponibilidad_insert/_update no son los auditados (definición o estado)';
  end if;
  -- El alta del 2.4 (esta migración no la toca: el postflight exige que siga igual).
  if (select md5(p.prosrc) from pg_proc p where p.oid = v_alta) is distinct from '30109c536ef0a73a85da1eb3465b8ed2'
     or md5(pg_get_functiondef(v_alta)) is distinct from 'e06eca2333bb11869d00913a004c8261'
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_alta)
        is distinct from array['authenticated:EXECUTE:false', 'postgres:EXECUTE:false'] then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: crm.crear_lead_si_disponible no es la que deja el 2.4 (cuerpo 30109c53…/e06eca23… o ACL)';
  end if;
  -- El verificador, con las MISMAS huellas compuestas que fija la carga de bases (20261004184501:178-183).
  if (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text)
        from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text,uuid)')) is distinct from 'a78247a515be78b145fec439fc299458'
     or (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text)
           from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text)')) is distinct from 'e144f7d020269c61258b4d3980ac88c6' then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: el verificador private.verificar_disponibilidad_lead_impl no es el fijado por la carga de bases (20261004184501); lo ensayado no valdría';
  end if;
  -- Las piezas que usa la regla, la del 2.4, la ficha cuya edición protege y el verificador: su DEFINICIÓN COMPLETA (cuerpo y
  -- atributos: DEFINER/INVOKER, STRICT, volatilidad, SET), su dueño y su ACL EFECTIVA (los valores por defecto expandidos, con la
  -- opción de concesión). Ronda 3 (Codex F2): antes solo se fijaba el cuerpo. Ronda 4 (auditor P3-4): también las dos de las que
  -- depende la clave del candado del alternativo (`private.bloquear_contactos_lead` y `private.normalizar_telefono`).
  select string_agg(e.firma, ', ' order by e.firma) into v_mal
  from (values
    ('crm.editar_lead_documento_fn(uuid,jsonb,text,text,uuid,text)', 'd0959691ad963cc409487cd63a4296d3', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.editar_lead_fn(uuid,jsonb)', 'b8ed6e9aebefd46627c8096594747aac', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.fijar_dni_lead_fn(uuid,text)', '0a3d6462b5f4e3fa43f4594647709a70', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.fijar_documento_lead_fn(uuid,text,text,uuid,text)', 'f8df169784b7448ff79fe2a35a9342a4', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.alta_reactivar_bloqueo_conservado(uuid)', '2186e7c4b4e3ac4bcf23636cb951d9ba', 'postgres:EXECUTE:false'),
    ('private.bases_carga_nace_dormido(text,text,text,boolean)', '9f75aa5fcb21115a708135077438d78b', 'postgres:EXECUTE:false'),
    ('private.bloquear_contactos_lead(text[],text[])', '0d52f58c2065c1c0dc37a7587eda5882', 'postgres:EXECUTE:false'),
    ('private.inversionista_canonica(uuid)', '34702897135078893b7d3a726b0c1816', 'postgres:EXECUTE:false'),
    ('private.juicio_persona(uuid,uuid)', '69794e137dd642e0b529612fb2a623eb', 'postgres:EXECUTE:false'),
    ('private.normalizar_telefono(text)', '00c30277b752de13be3ee0599485e6a9', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
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
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: cambió una pieza de la que depende la regla o la ficha cuya edición protege (%: definición, dueño o permisos); lo ensayado no valdría', v_mal;
  end if;
  -- Las premisas de la comparación literal (ronda 3, Codex F2): el alternativo se guarda SIEMPRE canónico (E.164) y excluyente con
  -- el alternativo sin validar, que es texto acotado; el DNI, ocho dígitos. Si un CHECK cambia o desaparece, lo ensayado no valdría.
  select string_agg(e.nombre, ', ' order by e.nombre) into v_mal
  from (values
    ('leads_dni_check', '6dcca3c962687ba896d101adf845d281'),
    ('leads_telefono_alternativo_crudo_cordura', '57365aa2feeca56754d4ad6e13c23f47'),
    ('leads_telefono_alternativo_excluyentes', 'adc22ae8c0c8d4e21ec406259be35da0'),
    ('leads_telefono_alternativo_formato', '4ce894b3dc052735877c5e1ae07b3219')) e(nombre, definicion)
  left join pg_constraint c on c.conrelid = 'crm.leads'::regclass and c.conname = e.nombre
  where c.oid is null or c.contype <> 'c' or not c.convalidated or md5(pg_get_constraintdef(c.oid)) is distinct from e.definicion;
  if v_mal is not null then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: cambió o falta una restricción de crm.leads de la que depende la regla (%)', v_mal;
  end if;
  -- El inventario y las DEFINICIONES de los trinquetes que se barren abajo (ronda 3, Codex F5), ANTES del primer barrido: tienen que
  -- ser los auditados (no se exige que pasen; se exige que sean ellos).
  if (select count(*) || '|' || md5(string_agg(p.oid::regprocedure::text || ':' || md5(pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text collate "C"))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0)
     is distinct from '30|3cefe40e1440f25d2daadb56d35a0f8d' then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: los private.assert_*() que barre la migración no son los auditados (inventario o definiciones: %); revisarlos antes de barrerlos',
      (select count(*) || '|' || md5(string_agg(p.oid::regprocedure::text || ':' || md5(pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text collate "C"))
         from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0);
  end if;
  -- Fotos para el postflight: las fichas del núcleo y del disparador, el alta, el oid del disparador de tabla de la edición y los
  -- private.assert_*() sin argumentos y SIN los `*_mutantes` (estado y texto íntegro del primer error: se exige que NO cambien, no
  -- que pasen).
  perform set_config('cliente_no_se_duplica.nucleo_antes',
    (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_nucleo), true);
  perform set_config('cliente_no_se_duplica.disp_antes',
    (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_disp), true);
  perform set_config('cliente_no_se_duplica.alta_antes',
    (select md5(pg_get_functiondef(p.oid)) || '|' || coalesce(p.proacl::text, '-') || '|' || coalesce(obj_description(p.oid, 'pg_proc'), '-')
       from pg_proc p where p.oid = v_alta), true);
  perform set_config('cliente_no_se_duplica.trg_oid',
    (select t.oid::text from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update'), true);
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
  perform set_config('cliente_no_se_duplica.trinquetes_antes', v_foto, true);
end
$preflight$;

-- ── 1. La pieza común (solo lectura) ─────────────────────────────────────────────────────────────────────────────────
create function private.juicio_cliente_convertido(p_telefono text, p_telefono_alternativo text, p_dni text, p_excluir_lead_id uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_tel text := nullif(pg_catalog.btrim(p_telefono), '');
  v_alt text := nullif(pg_catalog.btrim(p_telefono_alternativo), '');
  v_dni text := nullif(pg_catalog.btrim(p_dni), '');
  v_c record;
  v_juicio jsonb;
begin
  -- 1. Los TELÉFONOS (D-22, D-25; D-30: el alternativo cuenta en las dos direcciones): lo tecleado —principal y alternativo—
  --    contra los dos teléfonos de cada lead CONVERTIDO (activo o retirado), salvo el excluido. Grado: lo tecleado como principal
  --    antes que el alternativo tecleado y, para cada uno, el principal del cliente antes que su alternativo (sin alternativos de
  --    por medio es exactamente la búsqueda del 2.7). Dentro de un grado: enlazado a persona → activo → más reciente (sin fecha,
  --    detrás) → id.
  select l.inversionista_id, coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
    into v_c
  from crm.leads l
  left join public.perfiles pv on pv.id = l.vendedor_id
  left join public.perfiles ps on ps.id = l.asignado_supervisor_id
  where l.etapa = 'convertido'
    and l.id is distinct from p_excluir_lead_id
    and (l.telefono = v_tel or l.telefono_alternativo = v_tel or l.telefono = v_alt or l.telefono_alternativo = v_alt)
  order by case when l.telefono = v_tel then 1 when l.telefono_alternativo = v_tel then 2 when l.telefono = v_alt then 3 else 4 end,
           (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en desc nulls last, l.id
  limit 1;
  -- 2. Si ningún teléfono casa, el DNI (D-27), con la misma prioridad.
  if not found and v_dni is not null then
    select l.inversionista_id, coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
      into v_c
    from crm.leads l
    left join public.perfiles pv on pv.id = l.vendedor_id
    left join public.perfiles ps on ps.id = l.asignado_supervisor_id
    where l.etapa = 'convertido'
      and l.id is distinct from p_excluir_lead_id
      and l.dni = v_dni
    order by (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en desc nulls last, l.id
    limit 1;
  end if;
  if not found then
    return null;
  end if;
  -- 3. El veredicto. Enlazado a una persona ⇒ el mismo juicio de identidad que da el DNI (el de su persona canónica: «ya es
  --    cliente» con su asesor, o «no contactar» si está vetada) o, si no dice nada, el respaldo de D-21; sin persona ⇒ «ya es
  --    cliente» a nombre del dueño de esa ficha (vendedor o bandeja; si no tiene, «sin asesor asignado»), formato del verificador.
  if v_c.inversionista_id is not null then
    v_juicio := private.juicio_persona(private.inversionista_canonica(v_c.inversionista_id), p_excluir_lead_id);
    return coalesce(v_juicio, pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'sin asesor asignado', 'via', 'identidad'));
  end if;
  return pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', coalesce(v_c.tenedor, 'sin asesor asignado'));
end;
$function$;

-- Dueño postgres SIEMPRE (como el núcleo y el disparador que la llaman), corra quien corra la migración; EXECUTE solo para él.
alter function private.juicio_cliente_convertido(text, text, text, uuid) owner to postgres;
revoke all on function private.juicio_cliente_convertido(text, text, text, uuid) from public, anon, authenticated, service_role;

comment on function private.juicio_cliente_convertido(text, text, text, uuid) is
  'Bloque 2.8 (D-28, D-30; regla del bloque 2.7: D-22, D-25, D-27). Pieza comun de SOLO LECTURA: dado un telefono, un telefono alternativo y un DNI (cualquiera puede ser nulo) y un lead que excluir, devuelve el veredicto de un cliente ya convertido (lead en etapa convertido, activo o retirado) o NULL. Primero los telefonos: lo tecleado como principal y como alternativo contra el principal y el alternativo de cada convertido (D-30), en ese orden; si no casa ninguno, el DNI (D-27). Entre varios: enlazado a persona, activo, convertido mas reciente (sin fecha detras), id. Enlazado a persona: el juicio de identidad de su persona canonica (ya_es_cliente con su asesor y via identidad, o no_contactar), o el respaldo de D-21 si no dice nada; sin persona: ya_es_cliente a nombre del dueno de esa ficha, sin via. La usan el nucleo del alta (private.alta_reactivar_retirado) y el disparador de disponibilidad (private.trg_leads_disponibilidad_atomica). STABLE e INVOKER: no escribe; solo la ejecuta postgres.';

-- ── 2. El núcleo del alta, por ancla única: su regla 1b llama a la pieza (y le pasa el alternativo tecleado) ─────────
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

  -- Ancla 1 (declaraciones): `v_convertido` pasa a guardar el veredicto de la pieza (mismo nombre: el oráculo del 2.4 lo busca).
  v_ancla := $a1$  v_respuesta jsonb;
  v_convertido record;
begin
$a1$;
  v_nuevo := $n1$  v_respuesta jsonb;
  v_convertido jsonb;
begin
$n1$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: el ancla de las declaraciones del núcleo aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  -- Ancla 2 (cuerpo): la regla 1b del 2.7 entera, entre el filtro del veredicto y el candidato retirado.
  v_ancla := $a2$  -- 1b. EL CLIENTE YA CONVERTIDO TAMBIÉN SE RECONOCE POR TELÉFONO Y POR DNI (bloque 2.7; D-22, D-25 y D-27 de Miguel,
  --     08/10/2026; hallazgo H-28). Solo en un alta NUEVA: un reintento con rastro previo sigue fijado a la ficha de su rastro
  --     (R2-1…R4-1). Si el teléfono tecleado —o, si con él no casa ninguno, el DNI tecleado (D-27)— es el de un lead CONVERTIDO
  --     (activo o retirado), el alta no crea, no reactiva y no escribe nada: enlazado a una persona ⇒ el mismo juicio de
  --     identidad que da el DNI («ya es cliente» con su asesor, o «no contactar» si la persona está vetada; el respaldo de D-21 si
  --     el juicio no dice nada); sin persona ⇒ «ya es cliente» a nombre del dueño de esa ficha (formato del verificador, sin via).
  --     El teléfono manda sobre el DNI (también con OTRO DNI tecleado, D-25) y los dos van antes que cualquier retirado no
  --     convertido que case por teléfono o DNI (el candidato de abajo ya no llega a mirarse).
  if not v_reintento then
    select l.inversionista_id, coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
      into v_convertido
    from crm.leads l
    left join public.perfiles pv on pv.id = l.vendedor_id
    left join public.perfiles ps on ps.id = l.asignado_supervisor_id
    where l.etapa = 'convertido'
      and l.telefono = p_telefono
    order by (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en desc nulls last, l.id
    limit 1;
    if not found and p_dni is not null then
      select l.inversionista_id, coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
        into v_convertido
      from crm.leads l
      left join public.perfiles pv on pv.id = l.vendedor_id
      left join public.perfiles ps on ps.id = l.asignado_supervisor_id
      where l.etapa = 'convertido'
        and l.dni = p_dni
      order by (l.inversionista_id is not null) desc, l.activo desc, l.convertido_en desc nulls last, l.id
      limit 1;
    end if;
    if found then
      if v_convertido.inversionista_id is not null then
        v_fresco := private.juicio_persona(private.inversionista_canonica(v_convertido.inversionista_id), null);
        return coalesce(v_fresco, pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'sin asesor asignado', 'via', 'identidad'));
      end if;
      return pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', coalesce(v_convertido.tenedor, 'sin asesor asignado'));
    end if;
  end if;

  <<rama>>
$a2$;
  v_nuevo := $n2$  -- 1b. EL CLIENTE YA CONVERTIDO TAMBIÉN SE RECONOCE POR TELÉFONO Y POR DNI (bloque 2.7; D-22, D-25 y D-27 de Miguel,
  --     08/10/2026; hallazgo H-28) Y POR SU TELÉFONO ALTERNATIVO, EN LAS DOS DIRECCIONES (bloque 2.8; D-30 de Miguel, 08/10/2026).
  --     Solo en un alta NUEVA: un reintento con rastro previo sigue fijado a la ficha de su rastro (R2-1…R4-1). La regla vive en
  --     la pieza común de solo lectura `private.juicio_cliente_convertido` (la misma que juzga la edición y el INSERT en el
  --     disparador de disponibilidad): si lo tecleado —el teléfono, el teléfono alternativo o, si con ellos no casa ninguno, el DNI
  --     (D-27)— es de un lead CONVERTIDO (activo o retirado), el alta no crea, no reactiva y no escribe nada y responde su
  --     veredicto: enlazado a una persona ⇒ el mismo juicio de identidad que da el DNI («ya es cliente» con su asesor, o «no
  --     contactar» si la persona está vetada; el respaldo de D-21 si el juicio no dice nada); sin persona ⇒ «ya es cliente» a
  --     nombre del dueño de esa ficha (formato del verificador, sin via). El teléfono manda sobre el DNI (también con OTRO DNI
  --     tecleado, D-25) y todo va antes que cualquier retirado no convertido que case por teléfono o DNI (el candidato de abajo
  --     ya no llega a mirarse). `v_convertido` guarda el veredicto (el caso 3d del oráculo del 2.4 reconoce la regla por ese nombre).
  if not v_reintento then
    v_convertido := private.juicio_cliente_convertido(p_telefono, v_tecleado ->> 'telefono_alternativo', p_dni, null);
    if v_convertido is not null then
      return v_convertido;
    end if;
  end if;

  <<rama>>
$n2$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: el ancla de la regla 1b del núcleo aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  execute v_def;

  if (select p.proacl from pg_proc p where p.oid = v_firma) is distinct from v_acl then
    raise exception 'POSTFLIGHT cliente_no_se_duplica_al_editar: los permisos del núcleo cambiaron al parchear';
  end if;
end
$nucleo$;

-- ── 3. El disparador de disponibilidad, por ancla única ──────────────────────────────────────────────────────────────
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

  -- Ancla 1 (declaraciones y principio del UPDATE): la variable del veredicto y, ronda 3, el alternativo SIN VALIDAR.
  v_ancla := $a1$  v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  if tg_op = 'UPDATE' then
$a1$;
  v_nuevo := $n1$  v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);
  v_cliente jsonb;
begin
  if tg_op = 'UPDATE' then
    -- Bloque 2.8, ronda 3 (auditor F1, Codex F1). Con sesión —también bajo cualquier válvula—, el teléfono alternativo SIN VALIDAR
    -- (`telefono_alternativo_crudo`: lo pone solo la importación, sin sesión) no puede pasar a un valor no nulo ni cambiar de un
    -- valor a otro: no es un teléfono canónico y la regla no podría juzgarlo. Conservarlo sin tocarlo o borrarlo (NULL) sigue como
    -- hoy. Va antes que todo, también que la salida de la corrección de documento.
    if v_actor is not null and new.telefono_alternativo_crudo is not null
       and new.telefono_alternativo_crudo is distinct from old.telefono_alternativo_crudo then
      raise exception using errcode = '42501', message = 'El alternativo sin validar solo lo pone la importación';
    end if;
$n1$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: el ancla de las declaraciones del disparador aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  -- Ancla 5 (ronda 3, Codex F3): la salida anticipada de la corrección de documento (F2.b) solo vale si cambia ÚNICAMENTE el DNI.
  v_ancla := $a5$       and old.inversionista_id is not null and new.inversionista_id = old.inversionista_id then
      return new;
    end if;
$a5$;
  v_nuevo := $n5$       and old.inversionista_id is not null and new.inversionista_id = old.inversionista_id
       -- Bloque 2.8, ronda 3 (Codex F3): la excepción vale solo para la forma que escribe la corrección —cambia el DNI y nada de
       -- contacto—: ni el alternativo ni el alternativo sin validar se cuelan por ella (si cambian, sigue el juicio de abajo).
       and new.telefono_alternativo is not distinct from old.telefono_alternativo
       and new.telefono_alternativo_crudo is not distinct from old.telefono_alternativo_crudo then
      return new;
    end if;
$n5$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: el ancla de la salida de la corrección de documento aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  -- Ancla 2 (UPDATE sin cambio de teléfono ni DNI): si solo cambia el alternativo, con sesión (también bajo la válvula), la pieza.
  v_ancla := $a2$    if not v_cambio_identidad or v_actor is null then
      return new;
    end if;
$a2$;
  v_nuevo := $n2$    if not v_cambio_identidad or v_actor is null then
      -- Bloque 2.8 (D-28, D-30 de Miguel, 08/10/2026). Con sesión —desde la ronda 3 también bajo la válvula privilegiada (auditor
      -- F3: bajo ella nadie escribe el alternativo)—, si SOLO cambia el teléfono ALTERNATIVO: el nuevo no puede ser un teléfono de
      -- un cliente ya convertido (`private.juicio_cliente_convertido`, la regla del 2.7 con el alternativo; nunca contra el propio
      -- lead). El veredicto solo lo ve quien puede registrar leads (el resto, 42501 como en todo el disparador); si no hay cliente,
      -- todo sigue como hoy (ni rol, ni vetos, ni verificador).
      if v_actor is not null
         and new.telefono_alternativo is distinct from old.telefono_alternativo then
        v_cliente := private.juicio_cliente_convertido(null, new.telefono_alternativo, null, old.id);
        if v_cliente is not null then
          v_rol := private.rol_crm(v_actor);
          if v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
            raise exception using errcode = '42501', message = 'Acceso CRM revocado';
          end if;
          raise exception using
            errcode = 'P0481',
            message = 'Contacto no disponible',
            detail = v_cliente::text;
        end if;
      end if;
      return new;
    end if;
$n2$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: el ancla del UPDATE sin cambio de identidad aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  -- Ancla 3 (UPDATE con cambio de teléfono o DNI): después del verificador, lo que la edición PONE.
  v_ancla := $a3$    v_disponibilidad := private.verificar_disponibilidad_lead_impl(
      new.telefono,
      new.dni,
      old.id
    );
    if v_disponibilidad ->> 'estado' is distinct from 'libre' then
      raise exception using
        errcode = 'P0481',
        message = 'Contacto no disponible',
        detail = v_disponibilidad::text;
    end if;
    return new;
  end if;
$a3$;
  v_nuevo := $n3$    v_disponibilidad := private.verificar_disponibilidad_lead_impl(
      new.telefono,
      new.dni,
      old.id
    );
    if v_disponibilidad ->> 'estado' is distinct from 'libre' then
      raise exception using
        errcode = 'P0481',
        message = 'Contacto no disponible',
        detail = v_disponibilidad::text;
    end if;
    -- Bloque 2.8 (D-28, D-30). Lo que el verificador dejó pasar, con sesión: lo que la edición PONE —el teléfono, el alternativo y el
    -- DNI que cambian; lo que el lead ya tenía no se juzga: los duplicados que ya existen se dejan, D-23/D-25— no puede ser de un
    -- cliente ya convertido (`private.juicio_cliente_convertido`, nunca contra el propio lead) ⇒ el mismo P0481 con su veredicto.
    -- Ronda 3 (auditor F3, Codex F3): bajo la válvula privilegiada se juzgan igual el teléfono y el alternativo; SOLO el DNI queda
    -- fuera (la conversión fija el documento de la persona y conserva su juicio propio, hasta D-38).
    v_cliente := private.juicio_cliente_convertido(
      case when new.telefono is distinct from old.telefono then new.telefono end,
      case when new.telefono_alternativo is distinct from old.telefono_alternativo then new.telefono_alternativo end,
      case when not v_priv and new.dni is distinct from old.dni then new.dni end,
      old.id);
    if v_cliente is not null then
      raise exception using
        errcode = 'P0481',
        message = 'Contacto no disponible',
        detail = v_cliente::text;
    end if;
    return new;
  end if;
$n3$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: el ancla del UPDATE con cambio de identidad aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  -- Ancla 6 (ronda 3; INSERT con sesión): el alternativo sin validar no nace con sesión.
  v_ancla := $a6$  if v_actor is null then
    return new;
  end if;
$a6$;
  v_nuevo := $n6$  if v_actor is null then
    return new;
  end if;

  -- Bloque 2.8, ronda 3 (auditor F1, Codex F1): con sesión —también bajo cualquier válvula—, un lead no nace con el teléfono
  -- alternativo SIN VALIDAR (solo lo pone la importación, sin sesión).
  if new.telefono_alternativo_crudo is not null then
    raise exception using errcode = '42501', message = 'El alternativo sin validar solo lo pone la importación';
  end if;
$n6$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: el ancla del INSERT sin sesión aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  -- Ancla 4 (INSERT): después del verificador, todo lo tecleado (salvo el contacto dormido de la carga de bases).
  v_ancla := $a4$  v_disponibilidad := private.verificar_disponibilidad_lead_impl(new.telefono, new.dni);
  if v_disponibilidad ->> 'estado' is distinct from 'libre' then
    raise exception using
      errcode = 'P0481',
      message = 'Contacto no disponible',
      detail = v_disponibilidad::text;
  end if;

  return new;
end;
$a4$;
  v_nuevo := $n4$  v_disponibilidad := private.verificar_disponibilidad_lead_impl(new.telefono, new.dni);
  if v_disponibilidad ->> 'estado' is distinct from 'libre' then
    raise exception using
      errcode = 'P0481',
      message = 'Contacto no disponible',
      detail = v_disponibilidad::text;
  end if;

  -- Bloque 2.8 (D-30: «el INSERT directo, si sigue concedido, lo juzga la misma regla»). Un lead que nace CON SESIÓN —salvo el
  -- contacto de base cargada que nace dormido bajo su válvula: la carga de bases no cambia— no puede llevar el teléfono, el
  -- alternativo ni el DNI de un cliente ya convertido. (El alta ya lo respondió en su núcleo: aquí es la defensa del INSERT.)
  if not private.bases_carga_nace_dormido(new.origen, new.etapa, new.motivo_descarte, new.activo) then
    v_cliente := private.juicio_cliente_convertido(new.telefono, new.telefono_alternativo, new.dni, null);
    if v_cliente is not null then
      raise exception using
        errcode = 'P0481',
        message = 'Contacto no disponible',
        detail = v_cliente::text;
    end if;
  end if;

  return new;
end;
$n4$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: el ancla del INSERT aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  -- Ancla 7 (ronda 4, auditor P3-4; UPDATE): el candado de contacto incluye el alternativo viejo y el nuevo, como teléfonos.
  v_ancla := $a7$    perform private.bloquear_contactos_lead(
      array[old.telefono, new.telefono],
      array[old.dni, new.dni]
    );
$a7$;
  v_nuevo := $n7$    -- Bloque 2.8, ronda 4 (auditor P3-4): el candado de contacto incluye también el teléfono alternativo VIEJO y el NUEVO, en la
    -- lista de TELÉFONOS: la misma clave que toma el teléfono principal para el mismo número (`telefono:` + la forma de
    -- `private.normalizar_telefono`, dentro de `private.bloquear_contactos_lead`). Así quien pone X como alternativo o como teléfono
    -- espera a quien está poniendo X como alternativo (y al revés), y la regla de abajo juzga con lo que el otro confirmó.
    perform private.bloquear_contactos_lead(
      array[old.telefono, new.telefono, old.telefono_alternativo, new.telefono_alternativo],
      array[old.dni, new.dni]
    );
$n7$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: el ancla del candado del UPDATE aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  -- Ancla 8 (ronda 4, auditor P3-4; INSERT): el candado de contacto incluye el alternativo, como teléfono.
  v_ancla := $a8$  perform private.bloquear_contactos_lead(array[new.telefono], array[new.dni]);
$a8$;
  v_nuevo := $n8$  -- Bloque 2.8, ronda 4 (auditor P3-4): también el alternativo, con la misma clave que el teléfono principal (ver el UPDATE).
  perform private.bloquear_contactos_lead(array[new.telefono, new.telefono_alternativo], array[new.dni]);
$n8$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT cliente_no_se_duplica_al_editar: el ancla del candado del INSERT aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  execute v_def;

  if (select p.proacl from pg_proc p where p.oid = v_firma) is distinct from v_acl then
    raise exception 'POSTFLIGHT cliente_no_se_duplica_al_editar: los permisos del disparador cambiaron al parchear';
  end if;
end
$disparador$;

-- ── 4. El disparador de la edición mira también el alternativo y, ronda 3, el alternativo sin validar (mismo nombre, mismo ──
--      orden de disparo, misma función)
create or replace trigger trg_leads_00_disponibilidad_update
  before update of telefono, dni, no_contactar, etapa, activo, motivo_descarte, telefono_alternativo, telefono_alternativo_crudo on crm.leads
  for each row execute function private.trg_leads_disponibilidad_atomica();

-- ── 5. Los comentarios: al del 2.7 (núcleo) y al de B8 (disparador) se les AÑADE el del 2.8; la reversa lo quita ─────
do $comentarios$
begin
  execute pg_catalog.format('comment on function private.alta_reactivar_retirado(uuid, uuid, text, text, uuid, uuid, jsonb, jsonb) is %L',
    obj_description('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'::regprocedure, 'pg_proc')
      || $c1$ Bloque 2.8 (D-28, D-30): la regla del 2.7 vive en la pieza comun private.juicio_cliente_convertido, que cuenta tambien el telefono alternativo tecleado en las dos direcciones (contra el telefono y el alternativo de cada convertido); el resto del nucleo no cambia.$c1$);
  execute pg_catalog.format('comment on function private.trg_leads_disponibilidad_atomica() is %L',
    obj_description('private.trg_leads_disponibilidad_atomica()'::regprocedure, 'pg_proc')
      || $c2$ Bloque 2.8 (D-28, D-30): con sesion, al cambiar el telefono, el alternativo o el DNI (UPDATE: lo que cambia, no lo que el lead ya tenia) y al nacer un lead (INSERT, salvo el contacto de base cargada que nace dormido), lo que se pone no puede ser de un cliente ya convertido (private.juicio_cliente_convertido): P0481 Contacto no disponible con el veredicto en el detalle, despues de los veredictos de hoy; bajo la valvula privilegiada solo el DNI queda fuera (hasta D-38). Con sesion, el alternativo sin validar (telefono_alternativo_crudo) no nace ni pasa a un valor no nulo (42501; conservarlo o borrarlo sigue igual) y la salida de la correccion de documento solo vale si cambia unicamente el DNI. Ronda 4: el candado de contacto (private.bloquear_contactos_lead, con o sin sesion) incluye el telefono alternativo viejo y el nuevo, con la misma clave que el telefono principal para el mismo numero. Sin sesion, la regla no se aplica.$c2$);
end
$comentarios$;

-- ── Postflight ───────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_pieza regprocedure := to_regprocedure('private.juicio_cliente_convertido(text,text,text,uuid)');
  v_nucleo regprocedure := 'private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'::regprocedure;
  v_disp regprocedure := 'private.trg_leads_disponibilidad_atomica()'::regprocedure;
  v_alta regprocedure := 'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'::regprocedure;
  v_src text;
  v_h text;
  v_mal text;
  r record;
  v text;
  v_foto text := '';
  v_gates integer := 0;
begin
  -- La pieza: cuerpo exacto, INVOKER de postgres, STABLE, search_path vacío y nada más, EXECUTE solo para postgres, comentario.
  if v_pieza is null then
    raise exception 'POSTFLIGHT cliente_no_se_duplica_al_editar: la pieza private.juicio_cliente_convertido no quedó creada';
  end if;
  v_h := (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_pieza);
  if v_h is distinct from '346f48a8648248b308628301d41bc4c0/a2b38faf42a875c7dffb7968b106e36f' then
    raise exception 'POSTFLIGHT cliente_no_se_duplica_al_editar: la pieza no quedó exactamente como se ensayó (md5 del cuerpo / de la definición %)', v_h;
  end if;
  if not exists (select 1 from pg_proc p where p.oid = v_pieza and p.proowner = 'postgres'::regrole::oid and not p.prosecdef
                   and p.provolatile = 's' and p.proconfig = array['search_path=""'])
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_pieza)
        is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_pieza, 'EXECUTE') or has_function_privilege('authenticated', v_pieza, 'EXECUTE')
     or has_function_privilege('service_role', v_pieza, 'EXECUTE')
     or md5(coalesce(obj_description(v_pieza, 'pg_proc'), '')) is distinct from 'e23707e521c5878f056c0b99b02a9651' then
    raise exception 'POSTFLIGHT cliente_no_se_duplica_al_editar: la ficha de la pieza no es la esperada (INVOKER de postgres, STABLE, search_path vacío, EXECUTE solo para postgres, comentario EXACTO del 2.8)';
  end if;
  -- El núcleo: la llamada una sola vez, la marca `v_convertido jsonb`, cuerpo exacto, la misma ficha que antes, comentario.
  select p.prosrc, md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) into v_src, v_h from pg_proc p where p.oid = v_nucleo;
  if (length(v_src) - length(replace(v_src, 'private.juicio_cliente_convertido(', ''))) / length('private.juicio_cliente_convertido(') <> 1
     or (length(v_src) - length(replace(v_src, 'v_convertido jsonb;', ''))) / length('v_convertido jsonb;') <> 1
     or position('into v_convertido' in v_src) > 0 then
    raise exception 'POSTFLIGHT cliente_no_se_duplica_al_editar: el núcleo no quedó con la regla en la pieza exactamente una vez';
  end if;
  if v_h is distinct from '2fe5fdac50150d7429da2e422f43b92d/8d598eb4d0df994388337480e71e8005' then
    raise exception 'POSTFLIGHT cliente_no_se_duplica_al_editar: el núcleo no quedó exactamente como se ensayó (md5 del cuerpo / de la definición %)', v_h;
  end if;
  if (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
             || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
        from pg_proc p where p.oid = v_nucleo) is distinct from current_setting('cliente_no_se_duplica.nucleo_antes', true)
     or has_function_privilege('anon', v_nucleo, 'EXECUTE') or has_function_privilege('authenticated', v_nucleo, 'EXECUTE')
     or has_function_privilege('service_role', v_nucleo, 'EXECUTE')
     or md5(coalesce(obj_description(v_nucleo, 'pg_proc'), '')) is distinct from '8870de7f9d82c44b1a1f965f1e6d3ef0' then
    raise exception 'POSTFLIGHT cliente_no_se_duplica_al_editar: la ficha o el comentario del núcleo no son los esperados (comentario md5 %)', md5(coalesce(obj_description(v_nucleo, 'pg_proc'), ''));
  end if;
  -- El disparador: la pieza tres veces, cuerpo exacto (ronda 4: con el candado del alternativo), la misma ficha que antes, comentario.
  select p.prosrc, md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) into v_src, v_h from pg_proc p where p.oid = v_disp;
  if (length(v_src) - length(replace(v_src, 'private.juicio_cliente_convertido(', ''))) / length('private.juicio_cliente_convertido(') <> 3 then
    raise exception 'POSTFLIGHT cliente_no_se_duplica_al_editar: el disparador no quedó con sus tres llamadas a la pieza';
  end if;
  if v_h is distinct from '50a6ff4365ffa6bedfd77d215ce31666/418b097675753ed9f81931a485b17c94' then
    raise exception 'POSTFLIGHT cliente_no_se_duplica_al_editar: el disparador no quedó exactamente como se ensayó (md5 del cuerpo / de la definición %)', v_h;
  end if;
  if (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
             || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
        from pg_proc p where p.oid = v_disp) is distinct from current_setting('cliente_no_se_duplica.disp_antes', true)
     or has_function_privilege('anon', v_disp, 'EXECUTE') or has_function_privilege('authenticated', v_disp, 'EXECUTE')
     or has_function_privilege('service_role', v_disp, 'EXECUTE')
     or md5(coalesce(obj_description(v_disp, 'pg_proc'), '')) is distinct from '4a3fee01861a0fc10af38eb3fc338eb2' then
    raise exception 'POSTFLIGHT cliente_no_se_duplica_al_editar: la ficha o el comentario del disparador no son los esperados (comentario md5 %)', md5(coalesce(obj_description(v_disp, 'pg_proc'), ''));
  end if;
  -- Los disparadores de tabla: el del INSERT intacto; el de la edición con su lista nueva, el MISMO oid y habilitado.
  if (select md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text from pg_trigger t
        where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_insert') is distinct from 'fd430e026c17ce4ca3ed0d74b48ba0e1|O'
     or (select md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text || '|' || t.oid::text from pg_trigger t
        where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update')
        is distinct from 'a585ac769d92cd1f2aba0c4cf49ca83a|O|' || current_setting('cliente_no_se_duplica.trg_oid', true) then
    raise exception 'POSTFLIGHT cliente_no_se_duplica_al_editar: los disparadores de tabla no quedaron como se ensayó (%)',
      (select md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text || '|' || t.oid::text from pg_trigger t
        where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update');
  end if;
  -- El alta, el verificador, las piezas y la ficha: intactos.
  if (select md5(pg_get_functiondef(p.oid)) || '|' || coalesce(p.proacl::text, '-') || '|' || coalesce(obj_description(p.oid, 'pg_proc'), '-')
        from pg_proc p where p.oid = v_alta) is distinct from current_setting('cliente_no_se_duplica.alta_antes', true)
     or (select md5(p.prosrc) from pg_proc p where p.oid = v_alta) is distinct from '30109c536ef0a73a85da1eb3465b8ed2' then
    raise exception 'POSTFLIGHT cliente_no_se_duplica_al_editar: crm.crear_lead_si_disponible cambió y esta migración no la toca';
  end if;
  if (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text)
        from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text,uuid)')) is distinct from 'a78247a515be78b145fec439fc299458'
     or (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text)
           from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text)')) is distinct from 'e144f7d020269c61258b4d3980ac88c6' then
    raise exception 'POSTFLIGHT cliente_no_se_duplica_al_editar: el verificador cambió';
  end if;
  select string_agg(e.firma, ', ' order by e.firma) into v_mal
  from (values
    ('crm.editar_lead_documento_fn(uuid,jsonb,text,text,uuid,text)', 'd0959691ad963cc409487cd63a4296d3', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.editar_lead_fn(uuid,jsonb)', 'b8ed6e9aebefd46627c8096594747aac', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.fijar_dni_lead_fn(uuid,text)', '0a3d6462b5f4e3fa43f4594647709a70', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.fijar_documento_lead_fn(uuid,text,text,uuid,text)', 'f8df169784b7448ff79fe2a35a9342a4', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.alta_reactivar_bloqueo_conservado(uuid)', '2186e7c4b4e3ac4bcf23636cb951d9ba', 'postgres:EXECUTE:false'),
    ('private.bases_carga_nace_dormido(text,text,text,boolean)', '9f75aa5fcb21115a708135077438d78b', 'postgres:EXECUTE:false'),
    ('private.bloquear_contactos_lead(text[],text[])', '0d52f58c2065c1c0dc37a7587eda5882', 'postgres:EXECUTE:false'),
    ('private.inversionista_canonica(uuid)', '34702897135078893b7d3a726b0c1816', 'postgres:EXECUTE:false'),
    ('private.juicio_persona(uuid,uuid)', '69794e137dd642e0b529612fb2a623eb', 'postgres:EXECUTE:false'),
    ('private.normalizar_telefono(text)', '00c30277b752de13be3ee0599485e6a9', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
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
    raise exception 'POSTFLIGHT cliente_no_se_duplica_al_editar: cambió algo que esta migración no toca (%)', v_mal;
  end if;
  select string_agg(e.nombre, ', ' order by e.nombre) into v_mal
  from (values
    ('leads_dni_check', '6dcca3c962687ba896d101adf845d281'),
    ('leads_telefono_alternativo_crudo_cordura', '57365aa2feeca56754d4ad6e13c23f47'),
    ('leads_telefono_alternativo_excluyentes', 'adc22ae8c0c8d4e21ec406259be35da0'),
    ('leads_telefono_alternativo_formato', '4ce894b3dc052735877c5e1ae07b3219')) e(nombre, definicion)
  left join pg_constraint c on c.conrelid = 'crm.leads'::regclass and c.conname = e.nombre
  where c.oid is null or c.contype <> 'c' or not c.convalidated or md5(pg_get_constraintdef(c.oid)) is distinct from e.definicion;
  if v_mal is not null then
    raise exception 'POSTFLIGHT cliente_no_se_duplica_al_editar: cambió una restricción de crm.leads que esta migración no toca (%)', v_mal;
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
  if v_foto is distinct from current_setting('cliente_no_se_duplica.trinquetes_antes', true) then
    raise exception E'POSTFLIGHT cliente_no_se_duplica_al_editar: algún private.assert_*() da otro resultado que antes de la migración.\nANTES:\n%\nDESPUÉS:\n%',
      current_setting('cliente_no_se_duplica.trinquetes_antes', true), v_foto;
  end if;
  raise notice 'POSTFLIGHT cliente_no_se_duplica_al_editar: pieza, núcleo y disparador (con el candado del alternativo) con sus huellas · disparador de la edición con el alternativo y el alternativo sin validar · alta, verificador, dependencias y restricciones intactos · % trinquetes idénticos a los previos',
    v_gates;
end
$postflight$;

commit;

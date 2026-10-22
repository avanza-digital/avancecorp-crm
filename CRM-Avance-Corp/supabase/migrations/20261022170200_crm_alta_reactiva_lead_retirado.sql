-- 20261022170200_crm_alta_reactiva_lead_retirado.sql — bloque 2.4 del plan «Mantenibilidad y consistencia del backend CRM» (fecha de trabajo 20261007210152_crm_alta_reactiva_lead_retirado.sql; integrado el 2026/10/22, C2 del grupo C)
-- Registrar a una persona con lead RETIRADO reactiva su ficha (plan AVANCE-BACKEND-0710-P1, fase 2, bloque 2.4;
-- decisiones D-11/Q1, D-15, D-17 y D-21 de Miguel, 06-07/10/2026; caso L9a del banco). Ronda 2 (07/10): enmiendas de la
-- revisión de Codex (C-1…C-5) y del auditor de permisos (A-1…A-8), `fase-2/bloque-2.4/revision/CONCILIACION.md`. Ronda 3
-- (07/10): identidad de la ficha en el reintento (R2-1), `check_violation` acotada (R2-2) y el enlazado por el DNI tecleado
-- (AR2-1), `fase-2/bloque-2.4/revision/CONCILIACION-R2.md`. Ronda 4 (07/10): un reintento con rastro previo nunca llega al
-- INSERT (R3-1), `fase-2/bloque-2.4/revision/CONCILIACION-R3.md`. Ronda 5 (07/10): el paso 3a del núcleo (otro lead ACTIVO
-- coincide con lo tecleado) nunca devuelve nulo en un reintento (R4-1), `fase-2/bloque-2.4/revision/CONCILIACION-R4.md`.
--
-- QUÉ HACE. Hoy un lead retirado (`crm.leads.activo = false`: borrado lógico que solo hacen supervisor y Gerencia por API)
-- cae a «libre» en el verificador y `crm.crear_lead_si_disponible` inserta un SEGUNDO lead de la misma persona (rompe «un solo
-- lead total por persona», D-F05-09). Esta migración añade una rama al alta, DESPUÉS del verificador y ANTES del INSERT: si
-- el veredicto es «libre» o «enfriamiento» y existe un retirado no convertido y sin «no contactar» con ese teléfono (manda)
-- o, si no, con ese DNI, el alta REACTIVA esa ficha: `activo = true`, dueño = el destino que el alta ya calculó (el vendedor
-- que se autoasigna, la bandeja del supervisor, el analista elegido por Gerencia o la cola global si Gerencia no elige); si
-- estaba `descartado` pasa a `nuevo` con ciclo +1 (lo hace el guard de tenencia, como en «tomar»); en otra etapa queda
-- igual (también `reunion_agendada`). Se conservan los datos de la ficha; un retirado de base cargada SIN capital toma el
-- capital tecleado (A-2: el CHECK `leads_monto_estimado_valido` no deja salir del descarte sin capital). Lo que tecleó quien
-- registra va a la actividad de rastro (`nota`, `evento = 'reactivacion_alta'`, con `propietario_anterior`, `etapa_anterior`,
-- `activo_anterior = false`, `ciclo`, `via`, y de lo tecleado SOLO capital, moneda, origen y tipo de documento —A-7: ni
-- nombre, ni correo, ni teléfonos, ni documento—; `otro_retirado` como booleano sin id ajeno —A-8—); su `id` es el `p_id`
-- del alta: un reintento con el mismo id, el mismo actor y la misma huella repite la misma respuesta (aviso incluido, C-3)
-- sin segunda actividad ni segundo cambio, siempre que la ficha SIGA activa (A-6; si volvió a retirarse, el reintento reactiva
-- otra vez ESA MISMA ficha —R2-1: el candidato queda fijado al `lead_id` del primer rastro aunque haya otro retirado más
-- reciente del mismo contacto— y su rastro lleva otro id con `alta_id = p_id`). UN REINTENTO CON RASTRO PREVIO NUNCA CREA OTRA
-- FICHA (R3-1): si la ficha del primer rastro ya no se puede reactivar, el núcleo responde un veredicto bloqueante y nunca nulo,
-- en el orden del verificador: ya no existe ⇒ 22023 «el alta original ya no existe: registra de nuevo con un identificador
-- nuevo»; vetada ⇒ `no_contactar`; enlazada a persona ⇒ el juicio de identidad (`ya_es_cliente`, `via identidad`); convertida
-- ⇒ `ya_es_cliente` a nombre de su tenedor; y si la reactivación no pudo completarse, el veredicto fresco, que en un reintento
-- tampoco puede ser nulo (22023). Y si OTRO lead ACTIVO coincide con lo TECLEADO y el verificador no lo calificó (dijo «libre»
-- ante un descartado activo de 0 días dentro de sus 24 h, o ante un convertido activo sin identidad reconocida), el reintento
-- recibe el veredicto que el verificador daría para ese lead activo (`tomado` con su tenedor / `en_bolsa`) o 22023 «el alta
-- original ya no se puede repetir: hay otro lead activo con ese contacto» (R4-1); fuera del reintento ese paso sigue como hoy
-- (nulo: manda el veredicto del alta). GARANTÍA COMPLETA: un reintento con rastro previo nunca llega al INSERT; la ficha
-- original, el dato conservado, el lead activo por lo tecleado y el veredicto fresco nulo quedan cubiertos. Otro actor u otra
-- huella reciben 22023. La HUELLA
-- (`tecleado_md5`) se calcula sobre lo tecleado SIN dni, género ni fecha de nacimiento (nada recuperable por fuerza bruta
-- desde `public.audit_log`, A-1) y CON el teléfono normalizado y el tipo de documento (C-2: el mismo p_id con otro teléfono
-- o sin el DNI que llevaba es otro alta ⇒ 22023; con otro DNI es el mismo alta y no altera datos). Responde
-- `{estado:'reutilizado', lead_id}` (la app ya lo admite; `aviso` si había otro retirado por el DNI tecleado: manda el del
-- teléfono y el otro queda como está). D-15: se reactiva TAMBIÉN con la espera de enfriamiento sin vencer y sin la carencia de
-- 24 h (el veredicto «enfriamiento» se intercepta solo cuando su único causante es un retirado).
-- BLOQUEA (nunca «libre», nunca llega al INSERT): (C-1) cuando un lead ACTIVO, un veto o una identidad coinciden con el
-- TELÉFONO o el DNI que CONSERVA la ficha retirada aunque no coincidan con lo tecleado —el veredicto es el que daría el
-- verificador para esos datos (`tomado`, `en_bolsa`, `no_contactar`, `ya_es_cliente`, `enfriamiento`/`reutilizable` de un
-- descartado activo), en su formato exacto (el contrato de la app es estricto)—; (D-21) cuando la ficha retirada que casa
-- está ENLAZADA a una persona conocida, también si solo se tecleó el teléfono (`ya_es_cliente`, el mismo juicio que con el
-- DNI); (AR2-1, D-21 por la letra) cuando el candidato casó por el teléfono pero OTRO retirado ENLAZADO a una persona casa por
-- el DNI tecleado (mismo juicio de identidad, también con la bandera `resolver_en_puertas` apagada, cuando el verificador no lo
-- ve: nunca se reactiva el no enlazado dejando retirada la ficha de la persona); y con un lead activo que coincide con lo
-- TECLEADO manda el veredicto de hoy. (A-5) el núcleo exige `p_actor = auth.uid()` (defensa en profundidad: su ACL ya lo
-- reserva a postgres). (C-5) en la carrera tardía solo `uq_leads_telefono_vivo` y `uq_leads_dni_vivo` se tratan como «el
-- contacto se ocupó» (veredicto fresco); cualquier otro 23505 del UPDATE o de sus disparadores se propaga. (R2-2) del mismo
-- modo, solo el CHECK `leads_monto_estimado_valido` (A-2: la ficha no puede salir del retiro sin capital) se trata como veredicto
-- fresco; cualquier otro 23514 del UPDATE o de sus disparadores se propaga (el alta falla y no inserta nada). Con la identidad
-- unificada encendida se juzga a la persona (`private.juicio_reapertura`) y la ficha reactivada queda enlazada
-- (`private.enlazar_lead_reabierto`), como al tomar.
-- NO CAMBIA: un lead activo del mismo contacto tecleado (tomado, en bolsa, enfriamiento de un descartado ACTIVO), un
-- convertido, «no contactar», los roles (quien no podía registrar sigue recibiendo 42501; D-17: no hay excepción que eximir),
-- el verificador (huella fijada por la carga de bases), `tomar_lead_libre`, `reabrir_lead_fn`, `reactivar_lead_base`,
-- `crear_lead_documento_fn` (con CE/pasaporte responde «reutilizado» antes de fijar el documento: la ficha conserva sus datos;
-- el tipo y el número tecleados NO llegan al alta, por eso no entran en la huella ni en el rastro: declarado), el trigger del
-- ledger (abre `reabierto` cuando el retirado venía de `descartado` y `reactivado` en otra etapa: el rastro contractual de
-- D-15 es la actividad `reactivacion_alta` + el episodio), tablas, grants, policies ni nada de `public`.
-- INTERBLOQUEO (A-3): dos altas de la misma persona con datos cruzados pueden abrazarse (orden alta: contacto tecleado →
-- fila; núcleo: documento de la ficha → fila → contactos de la ficha vía trigger); Postgres lo detecta (40P01), una de las
-- dos aborta y la app lo traduce («otro usuario está procesando este contacto»); resultado esperado, sin datos a medias.
--
-- CÓMO. Dos piezas nuevas en `private` (DEFINER de postgres, `search_path` vacío, EXECUTE solo para postgres: las llama
-- únicamente el alta, que ya validó rol, ámbito y destino y ya tomó los candados de id, documento, persona y contactos):
-- `private.alta_reactivar_bloqueo_conservado(uuid)` (STABLE: el veredicto por lo que CONSERVA la ficha, sin contarla a ella)
-- y el núcleo `private.alta_reactivar_retirado(...)`; y un parche por ANCLA ÚNICA sobre el cuerpo vivo de
-- `crm.crear_lead_si_disponible` (`pg_get_functiondef` + `replace`; cada ancla tiene que aparecer exactamente una vez o la
-- migración aborta), conservando firma, dueño, DEFINER, `search_path`, `lock_timeout` y ACL. Dentro del núcleo: la fila del
-- retirado se toma FOR UPDATE y se recomprueba `activo = false`; los candados de persona van antes de la fila
-- (`private.bloquear_personas_de_leads`, inertes con la bandera apagada); las válvulas `crm.toma_directa` y
-- `crm.reapertura_identidad` se encienden SOLO alrededor del UPDATE y se apagan después, también en sus excepciones; todo
-- «veredicto fresco» sale por UN solo sitio: primero lo tecleado, si dice «libre» lo conservado, y si tampoco, nulo. En un
-- REINTENTO con rastro previo ningún camino devuelve nulo: ni la ficha del primer rastro (R3-1), ni un lead activo por lo
-- tecleado (R4-1: tomado / en bolsa / 22023), ni el veredicto fresco (22023).
--
-- PREFLIGHT (falla cerrada; si algo no coincide no se instala nada): huellas del alta (`md5(prosrc)` =
-- 54fc34f7357d4d5688f210df6c521045, `md5(pg_get_functiondef)` = d1daa1c65f18b4b41a6c9ffa99372bcf: el cuerpo de 20260904120000
-- parcheado por 20260928192822), su ficha (dueño postgres, DEFINER, `search_path=""` y `lock_timeout=5s`, EXECUTE solo para
-- postgres y authenticated SIN opción de concesión) y su comentario; las dos piezas no deben existir (si existen, ya está
-- aplicada); el verificador `private.verificar_disponibilidad_lead_impl` con las MISMAS huellas compuestas que fija la carga
-- de bases (20261004184501:178-183: a78247a515be78b145fec439fc299458 y e144f7d020269c61258b4d3980ac88c6) y `md5(prosrc)`
-- 683c16fdcb08377af860f1aa0a18f3a1 / 48c51531ebc8db1a41f5a816241920da; las huellas de las quince piezas de las que depende
-- la rama (guard de tenencia, reapertura solo por RPC, bloqueo de reasignación, ledger de asignaciones, juicio_reapertura,
-- juicio_persona, inversionista_canonica, enlazar_lead_reabierto, bloquear_personas_de_leads, lead_persona_reabrir,
-- lead_dentro_de_bloqueo, persona_vetada, es_destino_crm_activo, actividades «solo núcleo» de la base y gestión serializada)
-- y sus disparadores habilitados. LO QUE EL PREFLIGHT NO FIJA (AR2-3, requisito de la fase 4): el laboratorio donde se ensayó
-- está en el corte B6 (20261003162500) y producción tiene B7–B10 (04/10/2026); `private.trg_leads_disponibilidad_atomica()`
-- existe aquí en su versión anterior (md5 ba0fd3ef2e9a16181fb6b944ac002450) pero B8 (20261004184501:1055) la redefine, y
-- `private.trg_leads_base_cargada_solo_puerta()` (B7, 20261004160034) no existe en el laboratorio (el ensayo la instala como
-- fixture). Por eso sus huellas NO están en este preflight. ANTES del branch: medir las dos en la branch (`md5(prosrc)`) y
-- añadirlas aquí como las otras quince, o declarar que el gate del branch (`test-rls.mjs`) cubre que B7/B8 no alteran la
-- reactivación (leído, no ensayado: B8 solo juzga el UPDATE si cambian teléfono o DNI —la reactivación no los cambia— y el sello
-- B7 deja salir del descarte con capital). POSTFLIGHT: rama presente una sola vez, cuerpo nuevo EXACTO (`md5(prosrc)` =
-- 01ebf089b8428a02c6df387a9b4e899e y `md5(pg_get_functiondef)` = 94ec2bd71eca8ab1663e75841723b6a5, medidos en el laboratorio
-- el 07/10/2026), ficha del alta idéntica a la previa, verificador intacto, las dos piezas con su ficha y ACL, y cuatro
-- `private.assert_*` con EXACTAMENTE el mismo resultado que antes.
--
-- CÓMO SE REVIERTE: `supabase/scripts/reactivar-lead-retirado/reversa.sql` (falla cerrada: exige que el alta tenga EXACTAMENTE
-- la definición que deja esta migración; quita los dos bloques insertados —el cuerpo vuelve a 54fc34f7…/d1daa1c6…—, repone el
-- comentario y borra las dos piezas). No deshace datos: las fichas ya reactivadas siguen activas con su rastro; tras revertir,
-- el alta vuelve a crear un segundo lead sobre un retirado (el defecto que esta migración cierra). Mismo ciclo que la migración.
-- Ensayo: `supabase/scripts/reactivar-lead-retirado/` (oráculo ROJO/VERDE, mutantes, derivas, reversa, trinquetes).
-- RESELLE C2 (22/10/2026, plan AVANCE-BACKEND-1310-C2): re-asentado contra producción del 22/10 (alta cambiada por 20261015171407 F3 y 20261016183308 referidos de Supervisión): preflight 145b30a3…/068d4d88… (antes 54fc34f7…/d1daa1c6…) y su comentario con la frase F3, que el comentario nuevo conserva; postflight 30109c53…/e06eca23… (antes 01ebf089…/94ec2bd7…); las dos anclas aplican tal cual; regla, mensajes y candados sin cambio.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $preflight$
declare
  v_alta regprocedure := to_regprocedure('crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)');
  v_prosrc text;
  v_def text;
  v_comentario text;
  v_gate text;
  v_gates text := '';
  v_resultado text;
begin
  if v_alta is null then
    raise exception 'PREFLIGHT alta_reactiva_lead_retirado: falta crm.crear_lead_si_disponible (16 parámetros); nada que parchear';
  end if;
  if to_regprocedure('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)') is not null
     or to_regprocedure('private.alta_reactivar_bloqueo_conservado(uuid)') is not null then
    raise exception 'PREFLIGHT alta_reactiva_lead_retirado: el núcleo private.alta_reactivar_retirado (o su pieza alta_reactivar_bloqueo_conservado) ya existe: esta migración ya está aplicada (o hay un homónimo); revisar antes de seguir';
  end if;
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)), coalesce(obj_description(p.oid, 'pg_proc'), '')
    into v_prosrc, v_def, v_comentario
  from pg_proc p where p.oid = v_alta;
  if position('alta_reactivar_retirado' in (select p.prosrc from pg_proc p where p.oid = v_alta)) > 0 then
    raise exception 'PREFLIGHT alta_reactiva_lead_retirado: crm.crear_lead_si_disponible ya llama al núcleo: esta migración ya está aplicada';
  end if;
  if v_prosrc <> '145b30a30e69807a1838c1b960a0675d' or v_def <> '068d4d88078faea102947a5616337811' then
    raise exception 'PREFLIGHT alta_reactiva_lead_retirado: crm.crear_lead_si_disponible cambió desde que se auditó (md5 del cuerpo %, de la definición %; se esperaban 145b30a30e69807a1838c1b960a0675d y 068d4d88078faea102947a5616337811): revisar el cuerpo vivo antes de parchear',
      v_prosrc, v_def;
  end if;
  if not exists (select 1 from pg_proc p
                  where p.oid = v_alta and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                    and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
          where p.oid = v_alta)
        is distinct from array['authenticated:EXECUTE:false', 'postgres:EXECUTE:false']
     or has_function_privilege('anon', v_alta, 'EXECUTE')
     or has_function_privilege('service_role', v_alta, 'EXECUTE') then
    raise exception 'PREFLIGHT alta_reactiva_lead_retirado: la ficha de crm.crear_lead_si_disponible no es la auditada (dueño postgres, security definer, search_path vacío y lock_timeout 5s, EXECUTE solo para postgres y authenticated sin opción de concesión)';
  end if;
  if v_comentario <> 'Alta manual atomica con disponibilidad e idempotencia. Canales activos: referido, landing, formulario y oficina. Otro e historicos no admitidos en nuevas altas. Referido conserva restriccion de vendedor a su propio nombre. LANDING/FORMULARIO manuales conservan su politica del divisor. F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.' then
    raise exception 'PREFLIGHT alta_reactiva_lead_retirado: el comentario de crm.crear_lead_si_disponible cambió; revisar antes de reescribirlo';
  end if;
  -- El verificador no se toca y tiene que ser EXACTAMENTE el que fija la carga de bases (misma huella compuesta).
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text,uuid)')) is distinct from '683c16fdcb08377af860f1aa0a18f3a1'
     or (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text)
           from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text,uuid)')) is distinct from 'a78247a515be78b145fec439fc299458'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text)')) is distinct from '48c51531ebc8db1a41f5a816241920da'
     or (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text)
           from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text)')) is distinct from 'e144f7d020269c61258b4d3980ac88c6' then
    raise exception 'PREFLIGHT alta_reactiva_lead_retirado: el verificador private.verificar_disponibilidad_lead_impl no es el fijado por la carga de bases (20261004184501); lo ensayado no valdría';
  end if;
  -- Las piezas de las que depende la rama (y los disparadores que la hacen posible).
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_leads_guard_tenencia()')) is distinct from '763323f5f4ecaa735ce78cbccabad894'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_leads_zz_reapertura_solo_rpc()')) is distinct from 'ec1e53826887925cad0c41c319e967fb'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_leads_bloquear_reasignacion()')) is distinct from 'd3986ac5249e51d2a86a31e97457a628'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_leads_asignaciones()')) is distinct from '188bb4c9fd7fc571a959023e1abec444'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.juicio_reapertura(uuid,text,text)')) is distinct from '020f3792076f0c756b1cc12c5f1d5116'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.juicio_persona(uuid,uuid)')) is distinct from '2570f6eab5ae8b076e6f759b43b9b659'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.inversionista_canonica(uuid)')) is distinct from '6c7ff6001df2cb047967fa61b3ceb763'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.enlazar_lead_reabierto(uuid,uuid)')) is distinct from '891aa806bff7cd422013d95ab2d88d11'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.bloquear_personas_de_leads(uuid[],text)')) is distinct from '14727d8ae95fe727f5ddc81f9a92c9fd'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.lead_persona_reabrir(uuid)')) is distinct from 'deabfa49f57ed8fb2b179a9fbd8453f4'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.lead_dentro_de_bloqueo(uuid,jsonb)')) is distinct from '7035f23396bfaf06fa260d36cad28238'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.persona_vetada(uuid)')) is distinct from '3789218218c3c82b8c63bf3501ea1c22'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.es_destino_crm_activo(uuid,text[])')) is distinct from 'c53747fcaf5fd17072669f85decf4546'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_actividades_base_gestion_solo_nucleo()')) is distinct from '522841578db84de0ef9c5ba1f5716c2e'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_gestion_lead_serializada()')) is distinct from '7208a5b0f641f63d2bf1a5683c30c2f3' then
    raise exception 'PREFLIGHT alta_reactiva_lead_retirado: cambió una pieza de la que depende la rama (trg_leads_guard_tenencia, trg_leads_zz_reapertura_solo_rpc, trg_leads_bloquear_reasignacion, trg_leads_asignaciones, juicio_reapertura, juicio_persona, inversionista_canonica, enlazar_lead_reabierto, bloquear_personas_de_leads, lead_persona_reabrir, lead_dentro_de_bloqueo, persona_vetada, es_destino_crm_activo, trg_actividades_base_gestion_solo_nucleo o trg_gestion_lead_serializada); lo ensayado no valdría';
  end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_guard_tenencia'
                  and t.tgfoid = to_regprocedure('private.trg_leads_guard_tenencia()') and t.tgenabled = 'O')
     or not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_zz_reapertura_solo_rpc'
                     and t.tgfoid = to_regprocedure('private.trg_leads_zz_reapertura_solo_rpc()') and t.tgenabled = 'O')
     or not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_bloquear_reasignacion'
                     and t.tgfoid = to_regprocedure('private.trg_leads_bloquear_reasignacion()') and t.tgenabled = 'O')
     or not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_asignaciones'
                     and t.tgfoid = to_regprocedure('private.trg_leads_asignaciones()') and t.tgenabled = 'O')
     or not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.actividades'::regclass and t.tgname = 'trg_01_gestion_lead_serializada'
                     and t.tgfoid = to_regprocedure('private.trg_gestion_lead_serializada()') and t.tgenabled = 'O') then
    raise exception 'PREFLIGHT alta_reactiva_lead_retirado: falta o está deshabilitado un disparador del que depende la rama (guard de tenencia, reapertura solo por RPC, bloqueo de reasignación, ledger de asignaciones o gestión serializada)';
  end if;
  -- Fotos para el postflight: la ficha del alta y cuatro trinquetes (tienen que quedar EXACTAMENTE igual).
  perform set_config('alta_reactiva.ficha_antes',
    (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_alta), true);
  foreach v_gate in array array['private.assert_analista_vigencia()', 'private.assert_f7_piezas_cerradas()',
                                'private.assert_actividades_de_lead()', 'private.assert_gestion_diaria_registro()'] loop
    if to_regprocedure(v_gate) is null then
      v_resultado := 'ausente';
    else
      begin
        execute 'select ' || v_gate;
        v_resultado := 'pasa';
      exception when others then
        v_resultado := 'cae: ' || left(replace(sqlerrm, E'\n', ' '), 200);
      end;
    end if;
    v_gates := v_gates || v_gate || ' => ' || v_resultado || E'\n';
  end loop;
  perform set_config('alta_reactiva.gates_antes', v_gates, true);
end
$preflight$;

-- ── La pieza del veredicto por lo CONSERVADO (C-1) ───────────────────────────────────────────────────────────────────
-- Lo que diría el verificador para el TELÉFONO y el DNI que conserva la ficha retirada, sin contarla a ella misma: un veto,
-- una identidad conocida o un lead ACTIVO con esos datos bloquean el alta aunque no coincidan con lo tecleado (nunca se llega
-- al INSERT). Devuelve NULL cuando nada lo impide. Formato EXACTO del verificador: el contrato de la app es estricto.
create function private.alta_reactivar_bloqueo_conservado(p_ficha uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $pieza$
declare
  v_c crm.leads%rowtype;
  v_v jsonb;
  v_a record;
begin
  select l.* into v_c from crm.leads l where l.id = p_ficha;
  if not found then
    return null;
  end if;
  v_v := private.verificar_disponibilidad_lead_impl(v_c.telefono, v_c.dni, v_c.id);
  if v_v ->> 'estado' in ('no_contactar', 'ya_es_cliente', 'tomado', 'en_bolsa') then
    return v_v;
  end if;
  -- Un lead ACTIVO con esos datos que el verificador no califica como bloqueo por sí solo (un descartado activo —su
  -- «enfriamiento»/«reutilizable» sí es de él—, uno de 0 días dentro de sus 24 h, un convertido activo): bloquea igual.
  select l.id, l.etapa, l.vendedor_id, l.asignado_supervisor_id, l.tenencia_desde,
         coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
    into v_a
  from crm.leads l
  left join public.perfiles pv on pv.id = l.vendedor_id
  left join public.perfiles ps on ps.id = l.asignado_supervisor_id
  where l.activo = true
    and (l.telefono = v_c.telefono or (v_c.dni is not null and l.dni = v_c.dni))
  order by (l.etapa not in ('convertido', 'descartado')) desc, l.actualizado_en desc, l.id
  limit 1;
  if not found then
    return null;
  end if;
  if v_v ->> 'estado' <> 'libre' then
    return v_v;
  end if;
  if v_a.etapa = 'convertido' then
    return pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', coalesce(v_a.tenedor, 'sin asesor asignado'));
  end if;
  if v_a.vendedor_id is null and v_a.asignado_supervisor_id is null then
    return pg_catalog.jsonb_build_object('estado', 'en_bolsa');
  end if;
  return pg_catalog.jsonb_build_object(
    'estado', 'tomado',
    'vendedor', v_a.tenedor,
    'tenencia_desde', v_a.tenencia_desde,
    'ultima_conversacion_en', (
      select pg_catalog.max(a.creado_en)
      from crm.actividades a
      where a.lead_id = v_a.id
        and a.tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada')
    ));
end;
$pieza$;

revoke all on function private.alta_reactivar_bloqueo_conservado(uuid) from public, anon, authenticated, service_role;

comment on function private.alta_reactivar_bloqueo_conservado(uuid) is
  'Pieza de private.alta_reactivar_retirado (bloque 2.4, ronda 2, C-1): el veredicto del verificador para el telefono y el DNI que CONSERVA una ficha retirada, sin contarla a ella; un veto, una identidad conocida o un lead ACTIVO con esos datos bloquean el alta aunque no coincidan con lo tecleado. NULL cuando nada lo impide. Solo la llama el nucleo.';

-- ── El núcleo ────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Lo llama SOLO crm.crear_lead_si_disponible, después de validar rol, ámbito y destino y de tomar los candados de id,
-- documento, persona y contactos. Devuelve NULL cuando no actúa (el alta sigue como siempre), `{estado:'reutilizado',
-- lead_id}` cuando reactiva (o cuando repite un reintento con el mismo p_id), o un veredicto bloqueante (nunca «libre»).
create function private.alta_reactivar_retirado(
  p_id uuid,
  p_actor uuid,
  p_telefono text,
  p_dni text,
  p_vendedor uuid,
  p_supervisor uuid,
  p_disponibilidad jsonb,
  p_tecleado jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $nucleo$
declare
  v_flag boolean;
  v_act crm.actividades%rowtype;
  v_cand crm.leads%rowtype;
  v_lead crm.leads%rowtype;
  v_activo record;
  v_otro boolean := false;
  v_bloqueo jsonb;
  v_conservado jsonb;
  v_fresco jsonb;
  v_previo_toma text;
  v_previo_reab text;
  v_propietario_anterior uuid;
  v_etapa_anterior text;
  v_ciclo_anterior integer;
  v_n integer;
  v_restriccion text;
  v_tecleado jsonb := coalesce(p_tecleado, '{}'::jsonb);
  v_tipo_documento text := case when p_dni is not null then 'DNI' end;
  v_tecleado_md5 text;
  v_rastro_id uuid := p_id;
  v_reintento boolean := false;
  v_inv_dni uuid;
  v_respuesta jsonb;
begin
  -- A-5. Defensa en profundidad: la ACL ya reserva el núcleo a postgres; además el actor tiene que ser la sesión.
  if p_actor is null or p_actor is distinct from (select auth.uid()) then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  -- La HUELLA de idempotencia (C-2, A-1): lo tecleado SIN dni, género ni fecha de nacimiento (nada recuperable por fuerza
  -- bruta desde el rastro), CON el teléfono normalizado (viene en p_tecleado desde el alta) y el tipo de documento.
  v_tecleado_md5 := pg_catalog.md5(((v_tecleado - array['dni', 'genero', 'fecha_nacimiento'])
                      || pg_catalog.jsonb_build_object('tipo_documento', v_tipo_documento))::text);

  -- 0. REINTENTO con el mismo p_id: la actividad de rastro de una reactivación anterior lleva ese id. El mismo actor con la
  --    misma huella recibe la misma respuesta (sin segunda actividad ni segundo cambio) mientras la ficha SIGA activa (A-6);
  --    otro actor u otra huella, 22023, como hoy el alta con un id ya usado.
  select a.* into v_act from crm.actividades a where a.id = p_id;
  if found then
    if v_act.metadata ->> 'evento' is distinct from 'reactivacion_alta'
       or v_act.creado_por is distinct from p_actor
       or v_act.metadata ->> 'tecleado_md5' is distinct from v_tecleado_md5 then
      raise exception using errcode = '22023', message = 'El identificador de esta alta ya fue usado con datos distintos';
    end if;
    if exists (select 1 from crm.leads l where l.id = v_act.lead_id and l.activo) then
      v_respuesta := pg_catalog.jsonb_build_object('estado', 'reutilizado', 'lead_id', v_act.lead_id);
      if coalesce((v_act.metadata ->> 'otro_retirado')::boolean, false) then
        v_respuesta := v_respuesta || pg_catalog.jsonb_build_object('aviso', 'otro_lead_retirado_con_ese_dni');
      end if;
      return v_respuesta;
    end if;
    -- La ficha que aquel alta reactivó volvió a retirarse: el reintento es un alta nueva sobre ESA ficha (D-15; R2-1: el
    -- candidato queda FIJADO a v_act.lead_id, nunca otra ficha del mismo contacto); su rastro llevará otro id, con alta_id = p_id.
    v_reintento := true;
    v_rastro_id := pg_catalog.gen_random_uuid();
  end if;

  -- 1. Solo con «libre» o «enfriamiento» (D-15: la espera de un RETIRADO no bloquea). Cualquier otro veredicto manda.
  if coalesce(p_disponibilidad ->> 'estado', '') not in ('libre', 'enfriamiento') then
    return null;
  end if;

  <<rama>>
  begin
    -- 2. El candidato. En un REINTENTO (R2-1) queda FIJADO a la ficha del primer rastro: si sigue retirada, no convertida y sin
    --    veto, es ella; si no existe, se convirtió o quedó vetada, el veredicto bloqueante de ESA ficha (R3-1, abajo: nunca otra
    --    ficha por contacto, nunca el INSERT). En un alta nueva, el TELÉFONO manda; si no casa nada, el DNI. Retirado, no
    --    convertido y sin veto; el más reciente primero, y antes que ninguno el ENLAZADO a persona (D-21: bloquea). Sin candado
    --    todavía (los de persona van antes que la fila).
    if v_reintento then
      select l.* into v_cand
      from crm.leads l
      where l.id = v_act.lead_id
        and l.activo = false
        and l.etapa <> 'convertido'
        and l.no_contactar = false;
      if not found then
        exit rama;
      end if;
    else
      select l.* into v_cand
      from crm.leads l
      where l.activo = false
        and l.etapa <> 'convertido'
        and l.no_contactar = false
        and l.telefono = p_telefono
      order by (l.inversionista_id is not null) desc, l.actualizado_en desc, l.id
      limit 1;
      if not found and p_dni is not null then
        select l.* into v_cand
        from crm.leads l
        where l.activo = false
          and l.etapa <> 'convertido'
          and l.no_contactar = false
          and l.dni = p_dni
        order by (l.inversionista_id is not null) desc, l.actualizado_en desc, l.id
        limit 1;
      end if;
      if not found then
        return null;
      end if;
    end if;
    -- D-21. Un retirado ENLAZADO a una persona conocida bloquea también cuando solo se tecleó el teléfono: el mismo juicio
    --       de identidad que da el verificador con el DNI (ya es cliente; o no contactar si la persona está vetada).
    if v_cand.inversionista_id is not null then
      v_fresco := private.juicio_persona(private.inversionista_canonica(v_cand.inversionista_id), null);
      return coalesce(v_fresco, pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'sin asesor asignado', 'via', 'identidad'));
    end if;
    -- AR2-1 (D-21 por la letra). OTRO retirado ENLAZADO a una persona conocida que casa por el DNI tecleado (el candidato casó
    --       por el teléfono): el mismo juicio de identidad, también cuando la bandera de identidad está apagada y el verificador
    --       no lo vio. Nunca se reactiva el no enlazado dejando retirada la ficha de la persona.
    if p_dni is not null then
      select l.inversionista_id into v_inv_dni
      from crm.leads l
      where l.activo = false
        and l.inversionista_id is not null
        and l.dni = p_dni
        and l.id <> v_cand.id
      order by l.actualizado_en desc, l.id
      limit 1;
      if found then
        v_fresco := private.juicio_persona(private.inversionista_canonica(v_inv_dni), null);
        return coalesce(v_fresco, pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'sin asesor asignado', 'via', 'identidad'));
      end if;
    end if;
    -- Otro retirado que casa por el DNI tecleado y no es el candidato: queda como está y se avisa (sin su id, A-8).
    if p_dni is not null then
      v_otro := exists (
        select 1
        from crm.leads l
        where l.activo = false
          and l.etapa <> 'convertido'
          and l.inversionista_id is null
          and l.no_contactar = false
          and l.dni = p_dni
          and l.id <> v_cand.id);
    end if;

    -- 3a. Un lead ACTIVO que coincide con lo TECLEADO: manda el veredicto de hoy (tomado, en bolsa, enfriamiento de un
    --     descartado activo…) y el alta sigue como siempre. En un REINTENTO con rastro previo (R4-1) NUNCA nulo (nulo dejaría
    --     llegar al INSERT): si el verificador ya bloqueó («enfriamiento»), ese veredicto; si dijo «libre» sin calificar a ese
    --     lead activo (un descartado de 0 días dentro de sus 24 h), el veredicto que daría para él —«tomado» con su tenedor o
    --     «en bolsa», formato exacto—; y si tampoco cabe (un convertido activo sin identidad reconocida), 22023.
    select l.id, l.etapa, l.vendedor_id, l.asignado_supervisor_id, l.tenencia_desde,
           coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
      into v_activo
    from crm.leads l
    left join public.perfiles pv on pv.id = l.vendedor_id
    left join public.perfiles ps on ps.id = l.asignado_supervisor_id
    where l.activo = true
      and (l.telefono = p_telefono or (p_dni is not null and l.dni = p_dni))
    order by (l.etapa not in ('convertido', 'descartado')) desc, l.actualizado_en desc, l.id
    limit 1;
    if found then
      if not v_reintento then
        return null;
      end if;
      if coalesce(p_disponibilidad ->> 'estado', '') <> 'libre' then
        return p_disponibilidad;
      end if;
      if v_activo.etapa = 'convertido' then
        raise exception using errcode = '22023', message = 'El alta original ya no se puede repetir: hay otro lead activo con ese contacto; registra de nuevo con un identificador nuevo';
      end if;
      if v_activo.vendedor_id is null and v_activo.asignado_supervisor_id is null then
        return pg_catalog.jsonb_build_object('estado', 'en_bolsa');
      end if;
      return pg_catalog.jsonb_build_object(
        'estado', 'tomado',
        'vendedor', v_activo.tenedor,
        'tenencia_desde', v_activo.tenencia_desde,
        'ultima_conversacion_en', (
          select pg_catalog.max(a.creado_en)
          from crm.actividades a
          where a.lead_id = v_activo.id
            and a.tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada')
        ));
    end if;
    -- 3b. (C-1) Un lead ACTIVO, un veto o una identidad que coinciden con lo que la ficha CONSERVA (aunque no con lo
    --     tecleado): veredicto bloqueante, nunca nulo (nulo dejaría llegar al INSERT y nacería el segundo lead).
    v_conservado := private.alta_reactivar_bloqueo_conservado(v_cand.id);
    if v_conservado is not null then
      return v_conservado;
    end if;

    -- 4. Candados de PERSONA antes de la fila (documento → persona → lead), como tomar/reabrir; inertes con la bandera apagada.
    v_flag := private.resolver_en_puertas_bajo_candado();
    if v_flag then
      v_bloqueo := private.bloquear_personas_de_leads(array[v_cand.id], p_dni);
    end if;

    -- 5. La fila, FOR UPDATE, y la recomprobación: si cambió entre la mirada y el candado, veredicto fresco (nunca «libre»).
    select l.* into v_lead from crm.leads l where l.id = v_cand.id for update;
    if not found or v_lead.activo or v_lead.etapa = 'convertido' or v_lead.no_contactar then
      exit rama;
    end if;
    if v_lead.inversionista_id is not null then
      v_fresco := private.juicio_persona(private.inversionista_canonica(v_lead.inversionista_id), null);
      return coalesce(v_fresco, pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'sin asesor asignado', 'via', 'identidad'));
    end if;

    -- 6. Identidad (bandera encendida): la fila sigue dentro de lo bloqueado y el juicio único de reapertura (documento
    --    tecleado, documento de la ficha, puente; otro lead de la persona, conversión en curso, ya cliente, veto).
    if v_flag then
      if not private.lead_dentro_de_bloqueo(v_lead.id, v_bloqueo) then
        exit rama;
      end if;
      v_fresco := private.juicio_reapertura(v_lead.id, p_telefono, p_dni);
      if v_fresco is not null then
        return v_fresco;
      end if;
    end if;
    -- 7. Veto de la persona (también la hallada solo por documento o puente).
    if private.persona_vetada(v_lead.id) then
      return pg_catalog.jsonb_build_object('estado', 'no_contactar');
    end if;

    v_propietario_anterior := coalesce(v_lead.vendedor_id, v_lead.asignado_supervisor_id);
    v_etapa_anterior := v_lead.etapa;
    v_ciclo_anterior := v_lead.ciclo_actual;

    -- 8. La reactivación, con las válvulas SOLO alrededor del UPDATE (y quien las enciende las apaga, también en sus
    --    excepciones). El guard de tenencia valida el destino, sube el ciclo si sale de «descartado» y renace la tenencia; el
    --    sello del descarte limpia descartado_en; el ledger abre el episodio; los disparadores de cambio de etapa y
    --    reasignación dejan su actividad. Un retirado de base cargada sin capital toma el tecleado (A-2).
    v_previo_toma := coalesce(pg_catalog.current_setting('crm.toma_directa', true), 'off');
    v_previo_reab := coalesce(pg_catalog.current_setting('crm.reapertura_identidad', true), 'off');
    perform pg_catalog.set_config('crm.toma_directa', 'on', true);
    perform pg_catalog.set_config('crm.reapertura_identidad', 'on', true);
    begin
      update crm.leads l
         set activo = true,
             vendedor_id = p_vendedor,
             asignado_supervisor_id = p_supervisor,
             etapa = case when l.etapa = 'descartado' then 'nuevo' else l.etapa end,
             motivo_descarte = case when l.etapa = 'descartado' then null else l.motivo_descarte end,
             monto_estimado = coalesce(l.monto_estimado, (v_tecleado ->> 'monto_estimado')::numeric)
       where l.id = v_lead.id
         and l.activo = false
         and l.etapa <> 'convertido'
         and l.inversionista_id is null
         and l.no_contactar = false;
      get diagnostics v_n = row_count;
    exception
      when unique_violation then
        -- C-5: solo los índices de contacto vivo son «el contacto se ocupó mientras tanto» (veredicto fresco, nunca «libre»);
        -- cualquier otro 23505 del UPDATE o de sus disparadores se propaga tal cual.
        get stacked diagnostics v_restriccion = constraint_name;
        perform pg_catalog.set_config('crm.toma_directa', v_previo_toma, true);
        perform pg_catalog.set_config('crm.reapertura_identidad', v_previo_reab, true);
        if coalesce(v_restriccion, '') not in ('uq_leads_telefono_vivo', 'uq_leads_dni_vivo') then
          raise;
        end if;
        exit rama;
      when check_violation then
        -- A-2 / R2-2: SOLO el CHECK del capital (leads_monto_estimado_valido) es «la ficha no puede salir así del retiro»
        -- (veredicto fresco, el alta sigue como hoy); cualquier otro 23514 del UPDATE o de sus disparadores se propaga tal cual.
        get stacked diagnostics v_restriccion = constraint_name;
        perform pg_catalog.set_config('crm.toma_directa', v_previo_toma, true);
        perform pg_catalog.set_config('crm.reapertura_identidad', v_previo_reab, true);
        if coalesce(v_restriccion, '') <> 'leads_monto_estimado_valido' then
          raise;
        end if;
        exit rama;
    end;
    perform pg_catalog.set_config('crm.toma_directa', v_previo_toma, true);
    perform pg_catalog.set_config('crm.reapertura_identidad', v_previo_reab, true);
    if v_n <> 1 then
      exit rama;
    end if;

    -- 9. Con la identidad encendida, la ficha reactivada queda ENLAZADA a su persona (como al nacer y al tomar).
    if v_flag then
      perform private.enlazar_lead_reabierto(v_lead.id, private.lead_persona_reabrir(v_lead.id));
    end if;

    -- 10. El rastro: nota con id = p_id (idempotencia; otro id con alta_id = p_id si es el reintento tras un segundo retiro),
    --     firmada por quien registra. De lo tecleado solo capital, moneda, origen y tipo de documento (A-7); la nota va en el
    --     detalle; la huella sirve al reintento. activo_anterior=false y etapa_anterior hacen el rastro inequívoco aunque el
    --     ledger abra el episodio como «reabierto» (C-4). No se avisa al dueño anterior (D-15).
    select l.* into v_lead from crm.leads l where l.id = v_lead.id;
    insert into crm.actividades (id, lead_id, tipo, detalle, metadata, creado_por, creado_en)
    values (
      v_rastro_id,
      v_lead.id,
      'nota',
      'Ficha retirada reactivada al registrar de nuevo a la persona'
        || coalesce(': ' || nullif(pg_catalog.btrim(v_tecleado ->> 'nota'), ''), ''),
      pg_catalog.jsonb_build_object(
        'evento', 'reactivacion_alta',
        'via', 'alta_manual',
        'alta_id', p_id,
        'propietario_anterior', v_propietario_anterior,
        'etapa_anterior', v_etapa_anterior,
        'activo_anterior', false,
        'ciclo_anterior', v_ciclo_anterior,
        'etapa', v_lead.etapa,
        'ciclo', v_lead.ciclo_actual,
        'veredicto', p_disponibilidad ->> 'estado',
        'otro_retirado', v_otro,
        'tecleado', pg_catalog.jsonb_build_object(
          'monto_estimado', v_tecleado -> 'monto_estimado',
          'moneda', v_tecleado -> 'moneda',
          'origen', v_tecleado -> 'origen',
          'tipo_documento', v_tipo_documento),
        'tecleado_md5', v_tecleado_md5),
      p_actor,
      pg_catalog.statement_timestamp()
    );

    v_respuesta := pg_catalog.jsonb_build_object('estado', 'reutilizado', 'lead_id', v_lead.id);
    if v_otro then
      v_respuesta := v_respuesta || pg_catalog.jsonb_build_object('aviso', 'otro_lead_retirado_con_ese_dni');
    end if;
    return v_respuesta;
  end rama;

  -- R3-1 (ronda 4). Un REINTENTO con rastro previo NUNCA llega al INSERT (nulo dejaría nacer OTRA ficha con el mismo p_id): si la
  -- ficha del primer rastro no se pudo reactivar, el veredicto sale de ESA ficha, en el orden del verificador (veto → identidad →
  -- cliente): ya no existe ⇒ 22023; vetada ⇒ «no contactar»; enlazada a persona ⇒ el juicio de identidad (D-21); convertida ⇒
  -- «ya es cliente» a nombre de su tenedor (formato exacto del verificador). Si sigue retirada y reactivable (la reactivación no
  -- pudo completarse), el veredicto fresco de abajo, que en un reintento tampoco puede ser nulo.
  if v_reintento then
    select l.* into v_lead from crm.leads l where l.id = v_act.lead_id;
    if not found then
      raise exception using errcode = '22023', message = 'El alta original ya no existe: registra de nuevo con un identificador nuevo';
    end if;
    if v_lead.no_contactar then
      return pg_catalog.jsonb_build_object('estado', 'no_contactar');
    end if;
    if v_lead.inversionista_id is not null then
      v_fresco := private.juicio_persona(private.inversionista_canonica(v_lead.inversionista_id), null);
      return coalesce(v_fresco, pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', 'sin asesor asignado', 'via', 'identidad'));
    end if;
    if v_lead.etapa = 'convertido' then
      return pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', coalesce(
        (select coalesce(pv.nombre_completo, ps.nombre_completo)
           from crm.leads l
           left join public.perfiles pv on pv.id = l.vendedor_id
           left join public.perfiles ps on ps.id = l.asignado_supervisor_id
          where l.id = v_lead.id), 'sin asesor asignado'));
    end if;
  end if;

  -- VEREDICTO FRESCO (único sitio; nunca «libre»): primero lo tecleado; si dice «libre», lo que CONSERVA la ficha (C-1
  -- también en la carrera tardía: el choque pudo venir por un dato que no se tecleó); si tampoco, nulo (el alta sigue como hoy),
  -- salvo en un REINTENTO con rastro previo, que nunca llega al INSERT (R3-1): 22023.
  v_fresco := private.verificar_disponibilidad_lead_impl(p_telefono, p_dni);
  if v_fresco ->> 'estado' <> 'libre' then
    return v_fresco;
  end if;
  v_fresco := private.alta_reactivar_bloqueo_conservado(v_cand.id);
  if v_fresco is null and v_reintento then
    raise exception using errcode = '22023', message = 'El alta original no se pudo repetir sobre su ficha: registra de nuevo con un identificador nuevo';
  end if;
  return v_fresco;
end;
$nucleo$;

revoke all on function private.alta_reactivar_retirado(uuid, uuid, text, text, uuid, uuid, jsonb, jsonb)
  from public, anon, authenticated, service_role;

comment on function private.alta_reactivar_retirado(uuid, uuid, text, text, uuid, uuid, jsonb, jsonb) is
  'Nucleo de crm.crear_lead_si_disponible (bloque 2.4, D-11/Q1, D-15, D-21): si la persona ya tuvo un lead RETIRADO (activo=false, no convertido, sin veto) y ningun lead activo, veto ni identidad coinciden con lo tecleado ni con lo que esa ficha conserva, reactiva esa ficha a nombre del destino del alta (FOR UPDATE, candados de persona, valvulas solo alrededor del UPDATE), conserva sus datos, deja la actividad reactivacion_alta con id = p_id (idempotencia por actor y huella sin DNI) y responde estado reutilizado; un reintento tras un segundo retiro reactiva LA MISMA ficha del primer rastro (nunca otra del mismo contacto); un reintento con rastro previo nunca crea otra ficha: si su ficha ya no existe responde 22023, si quedo vetada no contactar, si esta enlazada o convertida ya es cliente (R3-1), y si otro lead activo coincide con lo tecleado sin que el verificador lo califique responde tomado o en bolsa para ese lead, o 22023 (R4-1); un retirado enlazado a persona bloquea (ya es cliente) tambien por telefono, y tambien otro retirado enlazado que casa por el DNI tecleado; un lead activo por un dato conservado bloquea con el veredicto del verificador; solo los indices de contacto vivo (23505) y el CHECK del capital (23514) son veredicto fresco, cualquier otro error se propaga; devuelve NULL cuando no actua. Exige p_actor = auth.uid(). Solo lo llama el alta.';

-- ── El parche del alta, por ancla única ──────────────────────────────────────────────────────────────────────────────
do $parche$
declare
  v_firma regprocedure := 'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'::regprocedure;
  v_def text;
  v_acl aclitem[];
  v_ancla text;
  v_nuevo text;
  v_veces integer;
begin
  select pg_get_functiondef(p.oid), p.proacl into v_def, v_acl from pg_proc p where p.oid = v_firma;

  -- Ancla 1 (declaraciones): la variable de la rama.
  v_ancla := $a1$  v_hoy_lima date := (pg_catalog.clock_timestamp() at time zone 'America/Lima')::date;
begin
$a1$;
  v_nuevo := $n1$  v_hoy_lima date := (pg_catalog.clock_timestamp() at time zone 'America/Lima')::date;
  v_reactivacion jsonb;
begin
$n1$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT alta_reactiva_lead_retirado: el ancla de las declaraciones aparece % veces en crm.crear_lead_si_disponible (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  -- Ancla 2 (cuerpo): entre el verificador y la salida por veredicto no «libre».
  v_ancla := $a2$  v_disponibilidad := private.verificar_disponibilidad_lead_impl(v_telefono, v_dni);

  if v_disponibilidad ->> 'estado' is distinct from 'libre' then
$a2$;
  v_nuevo := $n2$  v_disponibilidad := private.verificar_disponibilidad_lead_impl(v_telefono, v_dni);

  -- REACTIVAR UNA FICHA RETIRADA (plan AVANCE-BACKEND-0710-P1, bloque 2.4; D-11/Q1, D-15, D-17, D-21). Si la persona ya
  -- tuvo un lead y fue retirado (activo=false, no convertido, sin veto) y ningun lead ACTIVO, veto ni identidad coincide
  -- con lo tecleado NI con lo que esa ficha conserva, el alta reactiva ESA ficha a nombre del destino calculado arriba en
  -- vez de crear un segundo lead; tambien con el veredicto «enfriamiento» cuando su unico causante es un retirado (D-15).
  -- Un retirado ENLAZADO a persona bloquea («ya es cliente») aunque solo se teclee el telefono (D-21). El nucleo decide
  -- bajo los candados ya tomados, devuelve nulo cuando no actua (el alta sigue como siempre), bloquea (nunca «libre») si
  -- un dato CONSERVADO de la ficha choca con un lead activo, y repite la misma respuesta ante un reintento con el mismo
  -- p_id (la actividad de rastro lleva ese id; su huella lleva el telefono y el tipo de documento, no el DNI).
  v_reactivacion := private.alta_reactivar_retirado(
    v_id, v_actor, v_telefono, v_dni, v_vendedor, v_supervisor, v_disponibilidad,
    pg_catalog.jsonb_build_object(
      'telefono', v_telefono, 'nombre_completo', v_nombre, 'telefono_alternativo', v_alt, 'correo', v_correo,
      'distrito', v_distrito, 'origen', p_origen, 'etapa', p_etapa, 'monto_estimado', p_monto_estimado,
      'moneda', p_moneda, 'categoria_interes', v_categoria, 'vendedor_id', v_vendedor, 'nota', v_nota));
  if v_reactivacion is not null then
    return v_reactivacion;
  end if;

  if v_disponibilidad ->> 'estado' is distinct from 'libre' then
$n2$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT alta_reactiva_lead_retirado: el ancla del cuerpo (verificador → salida por veredicto) aparece % veces en crm.crear_lead_si_disponible (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  execute v_def;

  if (select p.proacl from pg_proc p where p.oid = v_firma) is distinct from v_acl then
    raise exception 'POSTFLIGHT alta_reactiva_lead_retirado: los permisos de crm.crear_lead_si_disponible cambiaron al parchear';
  end if;
end
$parche$;

comment on function crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text) is
'Alta manual atomica con disponibilidad e idempotencia. Canales activos: referido, landing, formulario y oficina. Otro e historicos no admitidos en nuevas altas. Referido conserva restriccion de vendedor a su propio nombre. LANDING/FORMULARIO manuales conservan su politica del divisor. F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas. Bloque 2.4 (D-11/Q1, D-15, D-21): si la persona ya tuvo un lead RETIRADO (activo=false, no convertido) y ningun lead activo, veto ni identidad coincide con lo tecleado ni con lo que esa ficha conserva, el alta reactiva esa ficha a nombre del destino del alta y responde estado reutilizado (nucleo private.alta_reactivar_retirado), tambien con el veredicto enfriamiento cuando su unico causante es un retirado; un retirado enlazado a persona bloquea tambien por telefono.';

-- ── Postflight ───────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_alta regprocedure := 'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'::regprocedure;
  v_nucleo regprocedure := to_regprocedure('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)');
  v_pieza regprocedure := to_regprocedure('private.alta_reactivar_bloqueo_conservado(uuid)');
  v_prosrc text;
  v_def text;
  v_src text;
  v_ficha text;
  v_gate text;
  v_gates text := '';
  v_resultado text;
begin
  select md5(p.prosrc), md5(pg_get_functiondef(p.oid)), p.prosrc into v_prosrc, v_def, v_src from pg_proc p where p.oid = v_alta;
  if (length(v_src) - length(replace(v_src, 'private.alta_reactivar_retirado(', ''))) / length('private.alta_reactivar_retirado(') <> 1
     or (length(v_src) - length(replace(v_src, 'v_reactivacion jsonb;', ''))) / length('v_reactivacion jsonb;') <> 1
     or position('if v_reactivacion is not null then' in v_src) = 0 then
    raise exception 'POSTFLIGHT alta_reactiva_lead_retirado: la rama no quedó exactamente una vez en crm.crear_lead_si_disponible';
  end if;
  if v_prosrc <> '30109c536ef0a73a85da1eb3465b8ed2' or v_def <> 'e06eca2333bb11869d00913a004c8261' then
    raise exception 'POSTFLIGHT alta_reactiva_lead_retirado: el cuerpo de crm.crear_lead_si_disponible no quedó exactamente como se ensayó (md5 del cuerpo %, de la definición %; se esperaban 30109c536ef0a73a85da1eb3465b8ed2 y e06eca2333bb11869d00913a004c8261)',
      v_prosrc, v_def;
  end if;
  v_ficha := (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
                     || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
                from pg_proc p where p.oid = v_alta);
  if v_ficha is distinct from current_setting('alta_reactiva.ficha_antes', true) then
    raise exception 'POSTFLIGHT alta_reactiva_lead_retirado: la ficha de crm.crear_lead_si_disponible cambió (dueño, DEFINER, configuración, ACL o firma)';
  end if;
  if (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text)
        from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text,uuid)')) is distinct from 'a78247a515be78b145fec439fc299458'
     or (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text)
           from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text)')) is distinct from 'e144f7d020269c61258b4d3980ac88c6' then
    raise exception 'POSTFLIGHT alta_reactiva_lead_retirado: el verificador cambió';
  end if;
  if v_nucleo is null
     or not exists (select 1 from pg_proc p where p.oid = v_nucleo and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                      and p.proconfig @> array['search_path=""'])
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
          where p.oid = v_nucleo) is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_nucleo, 'EXECUTE')
     or has_function_privilege('authenticated', v_nucleo, 'EXECUTE')
     or has_function_privilege('service_role', v_nucleo, 'EXECUTE') then
    raise exception 'POSTFLIGHT alta_reactiva_lead_retirado: el núcleo no quedó como DEFINER de postgres con search_path vacío y EXECUTE solo para postgres';
  end if;
  if v_pieza is null
     or not exists (select 1 from pg_proc p where p.oid = v_pieza and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                      and p.provolatile = 's' and p.proconfig @> array['search_path=""'])
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
          where p.oid = v_pieza) is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_pieza, 'EXECUTE')
     or has_function_privilege('authenticated', v_pieza, 'EXECUTE')
     or has_function_privilege('service_role', v_pieza, 'EXECUTE') then
    raise exception 'POSTFLIGHT alta_reactiva_lead_retirado: la pieza alta_reactivar_bloqueo_conservado no quedó como DEFINER STABLE de postgres con search_path vacío y EXECUTE solo para postgres';
  end if;
  foreach v_gate in array array['private.assert_analista_vigencia()', 'private.assert_f7_piezas_cerradas()',
                                'private.assert_actividades_de_lead()', 'private.assert_gestion_diaria_registro()'] loop
    if to_regprocedure(v_gate) is null then
      v_resultado := 'ausente';
    else
      begin
        execute 'select ' || v_gate;
        v_resultado := 'pasa';
      exception when others then
        v_resultado := 'cae: ' || left(replace(sqlerrm, E'\n', ' '), 200);
      end;
    end if;
    v_gates := v_gates || v_gate || ' => ' || v_resultado || E'\n';
  end loop;
  if v_gates is distinct from current_setting('alta_reactiva.gates_antes', true) then
    raise exception E'POSTFLIGHT alta_reactiva_lead_retirado: un trinquete cambió de resultado.\nANTES:\n%\nDESPUÉS:\n%',
      current_setting('alta_reactiva.gates_antes', true), v_gates;
  end if;
end
$postflight$;

commit;

-- REGISTRO en supabase_migrations.schema_migrations de 20261004223253_crm_bases_cargadas_seguimiento.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega si
-- los objetos no están, o si la versión ya está registrada con otro nombre u otro contenido.
-- Mismo formato que los registradores de B7/B8. statements = el archivo entero (md5 92c5ee8188f483e0955e14b8f46f25e4).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_bases_cargadas_seguimiento_registro'));
do $chk$
begin
  if (
    to_regprocedure('crm.seguimiento_bases()') is not null
    and to_regprocedure('crm.seguimiento_base(uuid)') is not null
    and to_regprocedure('crm.seguimiento_base_detalle(uuid,uuid,text)') is not null
    and to_regprocedure('crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)') is not null
    and to_regprocedure('private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)') is not null
    and to_regprocedure('private.bases_carga_seguimiento_filas(uuid[],date)') is not null
    and to_regprocedure('crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamptz,numeric,text)') is not null
    and to_regprocedure('private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamptz,numeric,text)') is not null
    and to_regprocedure('private.bases_carga_estado_contacto(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamptz,timestamptz,uuid,uuid[],date,boolean,boolean,boolean)') is not null
    and to_regprocedure('private.bases_carga_reparto_motivo_bloque(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date)') is not null
    and to_regprocedure('private.bases_carga_reparto_estado(boolean,boolean,text,uuid,boolean,date,uuid,boolean,boolean,boolean,boolean,date)') is null
  ) is not true then
    raise exception 'REGISTRO: la migración 20261004223253 no está aplicada; aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261004223253' and (coalesce(name, '') <> 'crm_bases_cargadas_seguimiento' or statements is distinct from array[$mig$-- 20261004223253_crm_bases_cargadas_seguimiento.sql
--
-- Bases cargadas · B10: seguimiento de las bases, la base en la lista del analista y el capital al reactivar. Contrato FIJO
-- `BASE PARA GESTION/BASES-CARGADAS-CONTRATO.md` (§B10) y decisiones E1–E14 (`BASES-CARGADAS.md`; E6: sin tocar 3 días = rojo,
-- nada se mueve solo; E8: el capital se pide al reactivar; E14: las otras vías no se bloquean, se ven como «movido por otra
-- vía»), sobre B7 (20261004160034), B8 (20261004184501) y B9 (20261004222602, r2: repartir y recoger), que va ANTES.
-- r2 (04/10/2026, coordinador; «prevenir antes que vigilar»): UNA sola definición del estado de un contacto de base —y de
--   «sin repartir»— para las puertas de B9 y de B10: private.bases_carga_estado_contacto. B10 reemplaza (CREATE OR REPLACE:
--   misma firma, dueño, seguridad y ACL) las tres piezas del núcleo de B9 que clasificaban por su cuenta —
--   private.bases_carga_contactos_core (estado y filtro «sin_repartir» de crm.contactos_de_base),
--   private.bases_carga_repartir_core (el bloque elige SOLO el estado sin_repartir; el individual rechaza además lo movido
--   por otra vía) y private.bases_carga_reparto_recogible (recoger = el estado sin_tocar que muestra el seguimiento)— y BORRA
--   el clasificador de B9 (private.bases_carga_reparto_estado): no queda una segunda definición. Las tres puertas de B9
--   (crm.repartir_base, crm.recoger_de_base, crm.contactos_de_base) conservan cuerpo, firma y ACL; cambia su comentario. Un
--   contacto retirado, vetado, movido, en descanso o en seguimiento activo NUNCA es «sin repartir» en ninguna puerta y el
--   bloque nunca lo elige. El preflight exige las huellas EXACTAS de B9 r2 y la reversa deja B9 tal cual estaba.
-- r3 (04/10/2026, coordinador: manda E1 de Miguel, «las dos entradas terminan en el mismo reparto»): un armado desde el CRM
--   que conserva su analista anterior es «sin repartir» como cualquier otro y el bloque lo elige (B9 ya lo hacía); si ese
--   analista lo está trabajando (seguimiento activo B6), «trabajado» y no se reparte. Sin el estado con_analista_previo, su
--   columna ni su cifra. La lista de la base para gestión oculta SOLO a los DORMIDOS del archivo sin repartir (procedencia
--   archivo): un armado nunca se oculta.
-- r4 (04/10/2026, Codex r2, 2 P2): crm.seguimiento_base agrega a TODOS los analistas fuera del ámbito del actor en UNA sola
--   fila anónima (analista_id y analista_nombre NULL, cifras sumadas, ultimo_intento_en = el máximo; Gerencia nunca la tiene):
--   dos externos ya no salen como dos filas indistinguibles, y la fila anónima no se abre por analista (la pantalla la pinta
--   «Analista de otro equipo» y la abre por la base). crm.seguimiento_base_detalle con un p_analista_id explícito exige que
--   el analista esté en el ámbito del actor (private.vendedor_ids_visibles; Gerencia: cualquiera) ANTES de mirar la
--   pertenencia, y si no responde P0002 con el MISMO mensaje que «sin contactos en la base»: conocer un UUID externo no
--   permite atribuirle cifras ni saber si tiene contactos. p_analista_id NULL sigue siendo toda la base (los externos, sin
--   lead_id ni nombre).
-- RECOGER, CAMBIO INTENCIONAL (Codex r2, riesgo): con B10, crm.recoger_de_base se lleva solo lo «sin tocar» de la definición
--   única (sin intento desde el reparto, sin veto y sin descanso) de un analista ACTIVO; B9 r2 se llevaba también sus vetados y
--   sus contactos en descanso sin intento. Así «Recoger» toma exactamente lo que el seguimiento muestra «sin tocar» (en rojo a
--   los 3 días, E6). Un vetado o uno en descanso se queda con su analista y cuenta en no_contactar / en_descanso; de un
--   analista DE BAJA se recoge todo lo suyo que siga descartado, como en B9. La reversa vuelve a la regla de B9.
--
-- QUÉ HACE
--   1. Seguimiento (tres puertas de LECTURA, DEFINER: las tablas de bases no tienen grants):
--      · crm.seguimiento_bases() — una fila por base VIVA que el actor ve (Supervisión: las de su subárbol; Gerencia: todas;
--        espejo de la policy bases_carga_select = private.bases_carga_base_visible de B8). Analista, coordinación y cualquier
--        otro rol → 42501. avance = trabajados / repartidos (0.0000 si no hay repartidos), siempre con 4 decimales.
--      · crm.seguimiento_base(p_base_id) — una fila por analista con contactos de la base. Base inexistente, retirada o fuera
--        del ámbito → P0002 (sin delatar si existe).
--      · crm.seguimiento_base_detalle(p_base_id, p_analista_id, p_cifra) — las filas detrás de CUALQUIER cifra de las dos de
--        arriba (todo número se abre). p_cifra ∈ private.bases_carga_seguimiento_cifras(); otra (también «avance», que es un
--        cociente: se abre por «trabajados») o NULL → 22023. p_analista_id NULL = toda la base; uno que no tiene contactos en
--        la base → P0002. ⚠ El contrato escribe `p_analista_id uuid default null, p_cifra text`: Postgres NO admite un
--        parámetro sin default después de uno con default; p_cifra lleva `default null` (NULL → 22023). PostgREST llama por
--        NOMBRE, así que el contrato de la pantalla ({p_base_id, p_analista_id?, p_cifra}) no cambia.
--      UNA definición de cada cifra: private.bases_carga_seguimiento_filas devuelve, por contacto VIVO de la base
--      (pertenencia activa), su estado y el arreglo `cifras` con los nombres de columna a los que pertenece; los conteos
--      (count(*) filter (where '<cifra>' = any(cifras))) y el detalle (where p_cifra = any(cifras)) leen ese MISMO arreglo:
--      filas del detalle = cifra por construcción (y la suite lo comprueba con valores contados a mano).
--      ESTADO (uno por contacto): private.bases_carga_estado_contacto, la ÚNICA definición; la usan TODAS las puertas de B9 y
--      B10 (seguimiento y detalle, crm.contactos_de_base, la exclusión de la lista, el bloque y el individual de repartir,
--      recoger). En este orden:
--        retirado              activo = false;
--        no_contactar          vetado;
--        movido_otra_via       con reparto: ya no es de su analista (E14); sin reparto: fuera del ámbito del supervisor DUEÑO
--                              (su analista o su bandeja en el subárbol, private.bases_carga_en_subarbol de B8), u otra vía
--                              le cambió el responsable desde que entró a la base (rastro `reasignacion` de
--                              trg_leads_reasignacion, que la API no puede escribir: actividades_insert lo excluye) salvo
--                              que hoy esté en la bandeja del dueño sin analista (recogido); y el que salió del descarte sin
--                              cita ni reactivación de la base;
--        cita / reactivado     salió del descarte con un «agendó cita» / una reactivación de la base desde asignado_en o, sin
--                              reparto, desde que entró a la base (private.bases_carga_reparto_hechos de B9);
--        en_descanso           enfriado_hasta > hoy;
--        trabajado / sin_tocar con reparto: ≥ 1 intento de la base desde asignado_en / ninguno; sin reparto, «trabajado» =
--                              su analista anterior (armado desde el CRM) lo tiene en seguimiento activo B6 (como en B9);
--        sin_repartir          DISPONIBLE: sin reparto, activo, sin veto, descartado, sin descanso, en el ámbito del dueño,
--                              sin movimientos ajenos (Codex r1, P2) y sin seguimiento activo. r3 (E1): también el armado
--                              que conserva su analista anterior (E13: armar no toca el lead). Es lo ÚNICO que el bloque
--                              elige; de la lista de la base para gestión sale solo si además vino del archivo (dormido).
--      CIFRAS: total · sin_repartir / sin_tocar / en_descanso / movidos_otra_via / retirados /
--        no_contactar (= su estado) · repartidos = asignados (con analista) · sin_tocar_3_dias (sin_tocar y repartido hace ≥ 3
--        días de Lima, E6: rojo) · trabajados / citas / reactivados (hechos de la base DESDE asignado_en, solo repartidos: ≥ 1
--        intento, un «agendó cita», una reactivación). avance = trabajados / repartidos. Por analista, lo mismo sobre sus
--        repartidos: la suma por analista = la base en repartidos, sin_tocar, trabajados, citas y reactivados.
--      Identidades: el detalle devuelve lead_id y nombre SOLO si el actor ve el lead y sigue activo
--      (private.bases_carga_lead_ref de B8, espejo de leads_select; si no, NULL: cuenta en su cifra sin delatar quién es).
--      seguimiento_base devuelve analista_id y nombre solo si el analista está en el ámbito del actor (auditor-rls r1, P3;
--      private.vendedor_ids_visibles; Gerencia: todos): una fila de otro equipo sale sin identificar y se abre por la base.
--   2. crm.obtener_base_gestion(uuid, boolean): MISMA firma, drop + create con el texto VIVO de B6b (20261004045038, md5
--      36af7e9c…) y SOLO estos cambios: (a) dos columnas AL FINAL, base_id y base_nombre (la base VIVA del lead: pertenencia
--      y base activas; NULL si no está en una; y solo si el actor ve la BASE —private.bases_carga_base_visible— o es el
--      analista del lead: auditor-rls r1, P3); (b) fuera de la lista los contactos SIN REPARTIR de una base viva (el estado
--      sin_repartir de private.bases_carga_estado_contacto —la MISMA definición del seguimiento y de B9— de los contactos que
--      vinieron del ARCHIVO (procedencia archivo: los dormidos; r3: un armado desde el CRM nunca se oculta): viven en la pestaña
--      «Bases»; hasta F5 nadie los ve en «Gestión de la base»). Un vetado nunca es «sin repartir»: con
--      p_incluir_vetados sale en «Ver no contactar» (auditor-rls r1, P3). Un lead tiene a lo sumo UNA pertenencia viva (índice único
--      base_carga_leads_lead_vivo_unico): el LEFT JOIN no duplica filas. Lo demás —filtros, intentos, etapa máxima, marca
--      del veto, orden— IDÉNTICO: el postflight compara, como Gerencia y con false y con true, la lista nueva proyectada a
--      las 26 columnas de B6b con la foto tomada en esta misma transacción ANTES del drop, sin las filas excluidas y en el
--      mismo orden (con datos sin bases: la lista de B6b exacta). El analista ve sus contactos de base repartidos como
--      cualquier lead suyo (vendedor_id = él, descartado): mismas reglas de intentos, rellamada y descanso.
--      Envoltorios DEFINER (memoria «envoltorio DEFINER se salta la RLS»): crm.base_gestion_resumen (cuenta por DUEÑO: los
--      excluidos no tienen dueño, sus cifras no cambian; el postflight lo compara) y crm.base_gestion_resumen_detalle
--      (sigue_en_base pide la lista de UN analista: los excluidos nunca están ahí). Ninguno cambia; el preflight fija que
--      son los ÚNICOS consumidores de servidor y el postflight vuelve a cuadrar cifra = detalle.
--   3. Capital al reactivar (E8). DECISIÓN CON EVIDENCIA (banco B10, 04/10; medido y transcrito en el informe de B10): una sobrecarga
--      `crm.reactivar_lead_base(uuid,uuid,text,numeric default null,text default null)` junto a la vieja ROMPE la llamada
--      publicada: Postgres → 42725 «is not unique» (también con argumentos por nombre) y PostgREST 16.2 → PGRST203 «Could
--      not choose the best candidate function» para {p_operacion_id, p_lead_id[, p_nota]}, que es lo que manda el front vivo
--      (73c9b908, app/src/data/crm-api.ts:1853). Sin defaults en la nueva, PostgREST solo la elige si llegan las 5 claves
--      (con 3 → PGRST202). Por eso se VERSIONA (regla de la casa, CLAUDE.md capa 3):
--      · crm.reactivar_lead_base_v2(p_operacion_id, p_lead_id, p_nota default null, p_monto_estimado default null,
--        p_moneda default null) — la del front nuevo (F6);
--      · crm.reactivar_lead_base(uuid,uuid,text) — la publicada, con su cuerpo y su ACL INTACTOS (md5 bf59d779…): sigue
--        llamando al núcleo con 4 argumentos;
--      · NUEVA private.base_gestion_reactivar_capital_core(actor, operación, lead, nota, p_monto_estimado, p_moneda): la
--        ÚNICA definición del núcleo = el texto vivo de private.base_gestion_reactivar_core (B3c, md5 c7e19f14…) con UN bloque
--        nuevo antes de reabrir: si el lead NO tiene capital → p_monto_estimado obligatorio (NULL → 22023 «Indica el capital
--        estimado para reactivar»; fuera de forma → 22023), p_moneda NULL = la que ya tiene el lead, otra que no sea PEN/USD →
--        22023; se escribe en el lead ANTES de reabrir (el CHECK leads_monto_estimado_valido rechazaría la reapertura) y el
--        episodio que abre la reapertura nace con ese capital. Con capital ya puesto, los dos parámetros se IGNORAN. r1 (Codex,
--        riesgo): el capital pedido es parte de la identidad de la operación (mismo p_operacion_id con otro capital o moneda →
--        23505 «otro contenido», como el intento con otra nota) y la respuesta AÑADE monto_estimado y moneda (el capital
--        EFECTIVO del lead tras la operación) y solicitud_monto / solicitud_moneda (claves nuevas: el front publicado valida
--        con v.looseObject, las ignora);
--      · private.base_gestion_reactivar_core(uuid,uuid,uuid,text): MISMA firma (CREATE OR REPLACE), ahora envoltorio de una
--        línea del núcleo nuevo sin capital. POR QUÉ no se borra (medido en el banco B10, 04/10): el gate
--        supabase/scripts/test-rls.mjs:15539 —y su copia en cualquier rama abierta, p. ej. la de B9— nombra esa firma exacta;
--        sin ella el gate aborta entero («function … does not exist»). La puerta publicada y el intento «agendó cita» la
--        siguen llamando sin cambiar su texto.
--      · «Agendó cita» (registrar_intento_base con agendo_reunion) REACTIVA en la misma transacción (D3): misma regla. NUEVA
--        private.base_gestion_intento_capital_core(…, p_monto_estimado, p_moneda) = el texto vivo de
--        private.base_gestion_intento_core (B3c, md5 db8ba2b4…) con UN cambio: reactiva por el núcleo con capital pasándole
--        p_monto_estimado y p_moneda (obligatorio solo si el resultado reactiva y el lead no tiene capital: 22023; en
--        cualquier otro caso se ignoran; r1: también en la identidad de la operación y la respuesta trae el capital efectivo).
--        private.base_gestion_intento_core(…6…) conserva su firma (también la nombra el gate,
--        test-rls.mjs:15539) como envoltorio sin capital, y NUEVA crm.registrar_intento_base_v2(p_operacion_id, p_lead_id,
--        p_resultado, p_nota default null, p_proxima_llamada default null, p_monto_estimado default null, p_moneda default
--        null) para el front nuevo (una sobrecarga de registrar_intento_base con defaults también es ambigua: medido, 42725).
--        crm.registrar_intento_base (la publicada) no cambia.
--      Consecuencias: la puerta vieja de reactivar, o la de intentos con «agendó cita», sobre un lead sin capital da 22023
--      «Indica el capital estimado para reactivar» (antes, 23514 del CHECK); un intento normal sin capital, igual que hoy.
--      Las puertas viejas se retiran cuando F6 esté publicada (paso aparte).
-- QUÉ NO CAMBIA: tablas, policies, grants de crm.leads, disparadores, B8, crm.base_gestion_resumen,
--   crm.base_gestion_resumen_detalle, crm.reactivar_lead_base, crm.registrar_intento_base, y la FIRMA (con su ACL) de todo
--   objeto existente: solo cambian el cuerpo de obtener_base_gestion (drop + create, misma firma y ACL) y el cuerpo y el
--   comentario de private.base_gestion_reactivar_core y private.base_gestion_intento_core (CREATE OR REPLACE); y, de B9 r2,
--   el cuerpo y el comentario de tres piezas de su núcleo, el comentario de sus tres puertas y el clasificador borrado (arriba).
-- CENSO: las funciones que cuentan (count(*) filter) no nombran crm.leads ni «reunion»; la que nombra crm.leads
--   (private.bases_carga_seguimiento_filas) no cuenta. El postflight exige el censo igual a la foto previa y ninguna nueva en él.
-- CANDADOS (Codex r1, P2): la exclusión de migraciones (candado consultivo de la casa crm_migracion_funciones) se toma ANTES
--   de fijar la instantánea: en una transacción PREVIA del mismo mensaje y a nivel de SESIÓN (pg_advisory_lock), y se suelta
--   al final (pg_advisory_unlock). En REPEATABLE READ la instantánea se fija en la primera consulta: si el candado se pedía
--   dentro (r0), una espera dejaba al preflight leyendo el catálogo de ANTES de la otra migración (reproducido en el banco con
--   dos sesiones: r0 se aplicaba sobre un ayudante cambiado; r1 se niega). El preflight exige además que ESTA sesión tenga el
--   candado (pg_locks; un pooler en modo transacción lo haría fallar cerrado). Si la migración falla, el resto del mensaje no
--   corre y el candado se suelta al cerrar la sesión (db query --linked --file y psql -c cierran al terminar). Sin candados
--   de tabla: B10 no cambia ninguna tabla. CONSISTENCIA: la transacción principal va en REPEATABLE READ (su primera
--   sentencia): la foto previa y el postflight ven la MISMA instantánea aunque otra sesión registre intentos o reparta.
-- SIN DML: el postflight solo lee (catálogo, la lista, el resumen, el detalle y el seguimiento como Gerencia con claims
--   locales). El comportamiento con escrituras se prueba después con supabase/scripts/base-gestion/b10-seguimiento.sql
--   (banco) y b10-comprobar-tras-aplicar.sql (rama/producción, ROLLBACK).
-- PRECONDICIÓN: B8 y B9 r2 aplicadas (B9 con sus huellas exactas: cuerpo, identidad, ACL y comentario); obtener_base_gestion = B6b (+ comentario de B6c), el núcleo de reactivar y su puerta los de
--   B3c, y los ayudantes de los que depende, con la identidad ensayada (preflight).
-- REVERSA: supabase/scripts/base-gestion/reversa-b10.sql (solo huellas propias; foto antes/después de lo ajeno; deja B9
--   tal cual estaba: sus tres piezas del núcleo, su clasificador y los comentarios de sus puertas, byte a byte). Si F6 ya
--   llama a reactivar_lead_base_v2 o a las puertas de seguimiento, revertir la deja en «disponible pronto» (PGRST202).
-- Exclusión de migraciones ANTES de la instantánea (Codex r1, P2): candado de SESIÓN en su propia transacción.
begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

begin;
-- Una sola instantánea para la foto y el postflight (B6b, Codex r1 P2). Tiene que ir ANTES de cualquier consulta.
set transaction isolation level repeatable read;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $preflight$
begin
  if (
    -- Esta sesión tiene el candado de migraciones (tomado ANTES de la instantánea); pg_locks no es MVCC: es el estado de hoy.
    exists (select 1 from pg_locks l
             where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.granted and l.mode = 'ExclusiveLock' and l.objsubid = 1
               and ((l.classid::bigint << 32) | l.objid::bigint) = hashtext('crm_migracion_funciones')::bigint)
    -- Nada de B10 existe todavía.
    and to_regprocedure('crm.seguimiento_bases()') is null
    and to_regprocedure('crm.seguimiento_base(uuid)') is null
    and to_regprocedure('crm.seguimiento_base_detalle(uuid,uuid,text)') is null
    and to_regprocedure('crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)') is null
    and to_regprocedure('private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)') is null
    and not exists (select 1 from pg_proc p where p.pronamespace in ('crm'::regnamespace, 'private'::regnamespace)
                     and (p.proname in ('seguimiento_bases', 'seguimiento_base', 'seguimiento_base_detalle', 'reactivar_lead_base_v2',
                                        'bases_carga_estado_contacto', 'bases_carga_reparto_motivo_bloque', 'base_gestion_reactivar_capital_core',
                                        'base_gestion_intento_capital_core', 'registrar_intento_base_v2')
                          or p.proname like 'bases\_carga\_seguimiento\_%'))
    -- B7 y B8 aplicadas (tablas, índice de la base viva y los ayudantes de B8 que se reutilizan, con su identidad).
    and to_regclass('crm.bases_carga') is not null and to_regclass('crm.base_carga_leads') is not null
    and to_regclass('crm.base_carga_leads_lead_vivo_unico') is not null
    and (select pg_get_indexdef(i.indexrelid) = 'CREATE UNIQUE INDEX base_carga_leads_lead_vivo_unico ON crm.base_carga_leads USING btree (lead_id) WHERE activo'
           from pg_index i where i.indexrelid = 'crm.base_carga_leads_lead_vivo_unico'::regclass)
    and to_regprocedure('crm.cargar_base_lote(uuid,uuid,jsonb)') is not null
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '50af07f268c21b5d4b07e1d79de5c5bc'
           from pg_proc p where p.oid = to_regprocedure('private.bases_carga_base_visible(uuid,text,uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '9f671b71f96facf74c7ee4dcec02b6f9'
           from pg_proc p where p.oid = to_regprocedure('private.bases_carga_lead_ref(uuid,text,uuid)'))
    -- La lista que se reemplaza: el cuerpo de B6b, su identidad, ACL y comentario (el de B6c), una sola sobrecarga.
    and (select md5(p.prosrc) = '36af7e9cc4d6ec319b3d8004f3903473'
                and md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                        || '|' || p.proowner::regrole::text) = '889f42a55ad100335b11a3e6bef4967c'
                and p.proacl is not null and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
                and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '67f83881ece789fee1a37e0799123c18'
           from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid,boolean)'))
    and (select count(*) = 1 from pg_proc p where p.pronamespace = 'crm'::regnamespace and p.proname = 'obtener_base_gestion')
    -- Sus ÚNICOS consumidores de servidor son el resumen y la detalle de F4, con el cuerpo medido (no cambian).
    and (select md5(p.prosrc) = 'b773a7c49fbdfc45133b3405991b1958' and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
           from pg_proc p where p.oid = to_regprocedure('crm.base_gestion_resumen()'))
    and (select md5(p.prosrc) = '068372248be4127c80ba002542c9b4b8' and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
           from pg_proc p where p.oid = to_regprocedure('crm.base_gestion_resumen_detalle(uuid,text)'))
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~ 'obtener_base_gestion'
                       and p.oid not in (to_regprocedure('crm.obtener_base_gestion(uuid,boolean)'), to_regprocedure('crm.base_gestion_resumen()'),
                                         to_regprocedure('crm.base_gestion_resumen_detalle(uuid,text)')))
    and not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                     where c.relkind in ('v', 'm') and n.nspname not in ('pg_catalog', 'information_schema')
                       and pg_get_viewdef(c.oid) ~ 'obtener_base_gestion|base_gestion_reactivar_core')
    -- Reactivar: la puerta publicada y el núcleo de 4 argumentos (B3c), con identidad, ACL y comentario; una sola sobrecarga de
    -- cada uno; sus ÚNICOS llamadores son la puerta y el intento («agendó cita»), que siguen llamando con 4 argumentos.
    and (select md5(p.prosrc) = 'bf59d77929877e7a5eb46704d934363e'
                and md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                        || '|' || p.proowner::regrole::text) = '81cf539d2eaf9bc224855fc91af3b14c'
                and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
           from pg_proc p where p.oid = to_regprocedure('crm.reactivar_lead_base(uuid,uuid,text)'))
    and (select count(*) = 1 from pg_proc p where p.pronamespace = 'crm'::regnamespace and p.proname = 'reactivar_lead_base')
    and (select md5(p.prosrc) = 'c7e19f14bfb29811dcf3b46e533329ef'
                and md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                        || '|' || p.proowner::regrole::text) = 'b4afaf414e4c755e80c14e27d584f840'
                and p.proacl is not null and p.proacl::text = '{postgres=X/postgres}'
                and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '2d01d61e55440923a0a4efa876265c7e'
           from pg_proc p where p.oid = to_regprocedure('private.base_gestion_reactivar_core(uuid,uuid,uuid,text)'))
    and (select count(*) = 1 from pg_proc p where p.pronamespace = 'private'::regnamespace and p.proname = 'base_gestion_reactivar_core')
    -- El núcleo del intento (B3c) con identidad, ACL y comentario; su puerta publicada; una sola sobrecarga de cada uno; el
    -- núcleo solo lo llama la puerta.
    and (select md5(p.prosrc) = 'db8ba2b4df43c84438f216924f20e73d'
                and md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                        || '|' || p.proowner::regrole::text) = '727c4c0629aae25b0d701bdac8a41bb5'
                and p.proacl is not null and p.proacl::text = '{postgres=X/postgres}'
                and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '2bd000b154679af92d052194304f55fa'
           from pg_proc p where p.oid = to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)'))
    and (select count(*) = 1 from pg_proc p where p.pronamespace = 'private'::regnamespace and p.proname = 'base_gestion_intento_core')
    and (select md5(p.prosrc) = 'd92c791fbe6f84e5d4f8ca39357b4721'
                and md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                        || '|' || p.proowner::regrole::text) = '278df37b38c2c420b8c0b595051c0e7a'
                and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
           from pg_proc p where p.oid = to_regprocedure('crm.registrar_intento_base(uuid,uuid,text,text,timestamp with time zone)'))
    and (select count(*) = 1 from pg_proc p where p.pronamespace = 'crm'::regnamespace and p.proname = 'registrar_intento_base')
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~ 'base_gestion_intento_core'
                       and p.oid not in (to_regprocedure('crm.registrar_intento_base(uuid,uuid,text,text,timestamp with time zone)'),
                                         to_regprocedure('private.bases_carga_reparto_hechos(uuid,timestamp with time zone)')))  -- B9: la nombra en un comentario, no la llama
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~ 'base_gestion_reactivar_core'
                       and p.oid not in (to_regprocedure('crm.reactivar_lead_base(uuid,uuid,text)'),
                                         to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)'),
                                         to_regprocedure('private.bases_carga_reparto_hechos(uuid,timestamp with time zone)')))  -- B9: la nombra en un comentario, no la llama
    -- Ayudantes de las puertas nuevas y de la lista, con la identidad ensayada.
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = 'c4ae35f90e850548653a25f08d25327c'
           from pg_proc p where p.oid = to_regprocedure('private.base_gestion_lead_visible(uuid,text,uuid,uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '16960a2a21cc5c372431c2dd67acafe4'
           from pg_proc p where p.oid = to_regprocedure('private.rol_crm(uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '45ae492c03234b80336c0b8f5c8ac09b'
           from pg_proc p where p.oid = to_regprocedure('private.vendedor_ids_visibles(uuid)'))
    -- r2: B9 r2 aplicada (20261004222602, md5 8a169944…) con sus huellas EXACTAS, medidas en el banco B con B9 r2 recién
    -- aplicada. (a) Lo que B10 reemplaza o borra —las tres piezas del núcleo y el clasificador— y las tres puertas, cuyo
    -- comentario B10 actualiza: cuerpo, identidad, ACL y comentario (la reversa los repone byte a byte).
    and (select string_agg(x.firma, ',' order by x.firma) from (values
           ('private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)', '8ace9326744cba6c262adb20203b4be0', '194eeb751dadd93a633699269e771340', '{postgres=X/postgres}', '0288e89e8938d90bb83101feecea2195'),
           ('private.bases_carga_contactos_core(uuid,uuid,text)', '0faaf15b274890e1e788632c27b477bd', 'a9bb62c38eb5fe46f3ef74109800d0cf', '{postgres=X/postgres}', 'c486469dfe54d349463472b0a75dd2b6'),
           ('private.bases_carga_reparto_recogible(uuid,uuid,timestamp with time zone,boolean)', '36d80e0e61b293d9cdd710fc00758054', '48e70fe5af1cad17aaf921f4bb9d2539', '{postgres=X/postgres}', 'a57b0dd26e0f120dcfa7655db771a018'),
           ('private.bases_carga_reparto_estado(boolean,boolean,text,uuid,boolean,date,uuid,boolean,boolean,boolean,boolean,date)', '28ae6bf56e4d54fdf45ec5f976ddbce3', 'f2ed9b90aac655e8d925629a19a6dfb9', '{postgres=X/postgres}', '3163053015c2e32323184e804a72c212'),
           ('crm.repartir_base(uuid,uuid,jsonb)', 'fd7531ba7cd7cf8a259a389e2895ee2e', 'fa967cde9c19fa033aebb2020202b85a', '{postgres=X/postgres,authenticated=X/postgres}', '0893508c3762d3588f7725a9bc506737'),
           ('crm.recoger_de_base(uuid,uuid,uuid)', '4744f70e69c0f70c22a6a295184e3095', 'f9be2c8a556f2ca0a57768675041ce4a', '{postgres=X/postgres,authenticated=X/postgres}', '7f99efc1751c49a220ce04d2604ec717'),
           ('crm.contactos_de_base(uuid,text)', 'd528bab6930698d160f9635417a3ca7a', 'fb57997d070d4c8064cde67a8d5ae9d5', '{postgres=X/postgres,authenticated=X/postgres}', '3b14ee12d12694e78ee7eecf40c533c6')) x(firma, cuerpo, ident, acl, com)
         left join pg_proc p on p.oid = to_regprocedure(x.firma)
        where (md5(p.prosrc) = x.cuerpo
               and md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                       || '|' || p.proowner::regrole::text) = x.ident
               and p.proacl is not null and p.proacl::text = x.acl
               and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = x.com) is not true) is null
    -- (b) Lo que la definición única reutiliza (no cambia): identidad de los hechos y el motivo de B9, la regla de B6 de B9 y
    -- el ámbito del dueño de B8.
    and (select string_agg(x.firma, ',' order by x.firma) from (values
           ('private.bases_carga_reparto_motivo(boolean,boolean,text,boolean,date,boolean,date)', 'd73381d3154c8615e8743b565fa0f799'),
           ('private.bases_carga_reparto_hechos(uuid,timestamp with time zone)', '885d58e94dd6357f9b19fa1848bec9da'),
           ('private.base_gestion_en_gestion_hasta(uuid)', '749573f8653aa7135e125ef029cfc9b5'),
           ('private.bases_carga_en_subarbol(uuid[],uuid,uuid)', '041d852f8d69017c77a2f9fcd8cbab93'),
           ('private.bases_carga_subarbol(uuid)', '0571e6b4075a6e2c88b46d09378e6cc6')) x(firma, ident)
         left join pg_proc p on p.oid = to_regprocedure(x.firma)
        where (md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                   || '|' || p.proowner::regrole::text) = x.ident) is not true) is null
    -- (c) Una sola sobrecarga de cada pieza de B9 y sus ÚNICOS llamadores (pg_proc, banco B con B9 r2): el clasificador, solo
    -- contactos_core; recogible, solo recoger_core; contactos_core y repartir_core, solo su puerta.
    and (select count(*) from pg_proc p where p.pronamespace = 'private'::regnamespace
          and (p.proname like 'bases\_carga\_reparto\_%' or p.proname in ('bases_carga_repartir_core', 'bases_carga_recoger_core', 'bases_carga_contactos_core'))) = 10
    and (select count(*) from pg_proc p where p.pronamespace = 'crm'::regnamespace
          and p.proname in ('repartir_base', 'recoger_de_base', 'contactos_de_base')) = 3
    and not exists (select 1 from pg_proc p where p.prosrc ~ 'bases_carga_reparto_estado'
                     and p.oid <> to_regprocedure('private.bases_carga_contactos_core(uuid,uuid,text)'))
    and not exists (select 1 from pg_proc p where p.prosrc ~ 'bases_carga_reparto_recogible'
                     and p.oid <> to_regprocedure('private.bases_carga_recoger_core(uuid,uuid,uuid,uuid)'))
    and not exists (select 1 from pg_proc p where p.prosrc ~ 'bases_carga_contactos_core'
                     and p.oid <> to_regprocedure('crm.contactos_de_base(uuid,text)'))
    and not exists (select 1 from pg_proc p where p.prosrc ~ 'bases_carga_repartir_core'
                     and p.oid <> to_regprocedure('crm.repartir_base(uuid,uuid,jsonb)'))
    and not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                     where c.relkind in ('v', 'm') and n.nspname not in ('pg_catalog', 'information_schema')
                       and pg_get_viewdef(c.oid) ~ 'bases_carga_reparto_estado|bases_carga_reparto_recogible|bases_carga_contactos_core|bases_carga_repartir_core')
    -- Los CHECK de capital y moneda en los que se apoya el núcleo (B7), exactos y validados.
    and (select pg_get_constraintdef(c.oid) = 'CHECK ((((monto_estimado IS NULL) AND (origen = ''base_cargada''::text) AND (etapa = ''descartado''::text)) OR ((monto_estimado IS NOT NULL) AND (monto_estimado > (0)::numeric) AND (monto_estimado <= 9999999999.99) AND (monto_estimado = trunc(monto_estimado, 2)))))'
                and c.convalidated
           from pg_constraint c where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_monto_estimado_valido')
    and (select pg_get_constraintdef(c.oid) = 'CHECK ((moneda = ANY (ARRAY[''PEN''::text, ''USD''::text])))' and c.convalidated
           from pg_constraint c where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_moneda_check')
  ) is not true then
    raise exception 'PREFLIGHT B10: sin el candado de migraciones en esta sesion, ya aplicada o a medias, falta B8 o B9 r2 (o B9 no es la medida), la lista no es la de B6b, reactivar o su nucleo no son los medidos, la lista o el nucleo tienen otro consumidor, o un ayudante o un CHECK cambio';
  end if;
end;
$preflight$;

-- Foto del censo analítico: el postflight exige que no cambie.
create temp table _b10_censo_antes on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;

-- Foto de la lista VIVA (B6b) como Gerencia (todo el ámbito), con false y con true, y del resumen de F4: el postflight exige
-- la misma lista sin los dormidos sin repartir, en el mismo orden, y el mismo resumen.
create temp table _b10_lista_antes (modo boolean, ord bigint, lead_id uuid, fila text) on commit drop;
create temp table _b10_resumen_antes (vendedor_id uuid, nombre text, en_base integer, rellamadas_hoy integer, intentos_hoy integer,
                                      reactivaciones_mes integer) on commit drop;
do $foto$
declare
  v_ger uuid;
begin
  select e.perfil_id into v_ger from crm.equipo e
   where e.activo and private.rol_crm(e.perfil_id) = 'gerencia' order by e.perfil_id limit 1;
  if v_ger is null then
    raise notice 'bases_cargadas_seguimiento: sin Gerencia activa en esta base; la identidad con B6b NO RUN';
    return;
  end if;
  perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
  perform pg_catalog.set_config('request.jwt.claim.sub', v_ger::text, true);
  insert into pg_temp._b10_lista_antes (modo, ord, lead_id, fila)
  select m.modo, t.ordinality, t.lead_id,
         row(t.lead_id, t.nombre_completo, t.telefono, t.distrito, t.origen, t.categoria_interes, t.monto_estimado, t.moneda,
             t.motivo_descarte, t.descartado_en, t.dias_desde_descarte, t.etapa_maxima, t.intentos, t.ultimo_resultado,
             t.ultimo_intento_en, t.proxima_llamada_en, t.rellamada_hoy, t.enfriado_hasta, t.ciclo_n, t.vendedor_id, t.gestiona,
             t.recibido_en, t.no_contactar, t.no_contactar_en, t.no_contactar_motivo, t.no_contactar_por)::text
    from (values (false), (true)) m(modo)
    cross join lateral crm.obtener_base_gestion(null, m.modo) with ordinality t;
  insert into pg_temp._b10_lista_antes (modo, ord, lead_id, fila) values (null, 0, v_ger, 'gerencia');  -- quién hizo la foto
  insert into pg_temp._b10_resumen_antes select r.* from crm.base_gestion_resumen() r;
  perform pg_catalog.set_config('request.jwt.claims', '', true);
  perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
end;
$foto$;

-- ── 1 · Núcleo: ayudantes del seguimiento (sin agregados de conteo) ────────────────────────────────────────────────────
create function private.bases_carga_estado_contacto(p_lead_id uuid, p_activo boolean, p_no_contactar boolean, p_etapa text,
                                                    p_vendedor_id uuid, p_asignado_supervisor_id uuid, p_enfriado_hasta date,
                                                    p_analista_id uuid, p_asignado_en timestamptz, p_agregado_en timestamptz,
                                                    p_dueno uuid, p_subarbol uuid[], p_hoy date,
                                                    p_intento boolean default null, p_cita boolean default null,
                                                    p_reactivado boolean default null)
returns text
language sql
stable
security invoker
set search_path = ''
as $function$
  -- B10 r2/r3 (coordinador; Codex r1 P2): la ÚNICA definición del estado de un contacto de una base, para TODAS las puertas
  -- de B9 y B10: el seguimiento y su detalle, crm.contactos_de_base, la exclusión de la lista de la base para gestión, el
  -- bloque y el individual de repartir y recoger. Entradas: la fila del lead, la pertenencia (analista, asignado_en, cuándo
  -- entró a la base) y el supervisor DUEÑO con su subárbol (private.bases_carga_subarbol). Los hechos (intento, cita,
  -- reactivado) son los de private.bases_carga_reparto_hechos (B9) desde asignado_en o, sin reparto, desde que entró a la
  -- base; quien ya los calculó con esa función los pasa (p_intento, p_cita, p_reactivado) y, si llegan NULL, se calculan
  -- aquí. Los movimientos ajenos, el rastro `reasignacion` de trg_leads_reasignacion (la API no lo puede escribir:
  -- actividades_insert lo excluye). r3 (E1 de Miguel): un armado que conserva su analista anterior es «sin repartir» como
  -- cualquier otro; si su analista lo está trabajando (seguimiento activo B6), «trabajado». Condiciones con `is true`/`is not
  -- true`: un NULL nunca hace a un contacto «sin repartir».
  select case
           when p_activo is not true then 'retirado'
           when p_no_contactar is not false then 'no_contactar'
           -- Con reparto: ya no es de su analista (E14).
           when p_analista_id is not null and p_vendedor_id is distinct from p_analista_id then 'movido_otra_via'
           -- Sin reparto: fuera del ámbito del supervisor dueño (su bandeja, o un analista o una bandeja de su subárbol, B8).
           when p_analista_id is null
                and not (p_vendedor_id is null and p_asignado_supervisor_id is not distinct from p_dueno)
                and private.bases_carga_en_subarbol(p_subarbol, p_vendedor_id, p_asignado_supervisor_id) is not true then 'movido_otra_via'
           -- Salió del descarte: con una cita o una reactivación de la base (desde el reparto o, sin reparto, desde que entró a
           -- la base); si no, por otra vía.
           when p_etapa is distinct from 'descartado' then
             case when p_cita is not null and p_reactivado is not null
                    then case when p_cita then 'cita' when p_reactivado then 'reactivado' else 'movido_otra_via' end
                  else (select case when h.cita is true then 'cita' when h.reactivado is true then 'reactivado' else 'movido_otra_via' end
                          from private.bases_carga_reparto_hechos(p_lead_id, coalesce(p_asignado_en, p_agregado_en)) h)
             end
           -- Sin reparto: otra vía le cambió el responsable desde que entró a la base, salvo que hoy esté en la bandeja del dueño
           -- sin analista (recogido).
           when p_analista_id is null
                and not (p_vendedor_id is null and p_asignado_supervisor_id is not distinct from p_dueno)
                and exists (select 1 from crm.actividades a
                             where a.lead_id = p_lead_id and a.tipo = 'reasignacion' and a.creado_en >= p_agregado_en) then 'movido_otra_via'
           when p_enfriado_hasta is not null and p_enfriado_hasta > p_hoy then 'en_descanso'
           -- Con reparto: con o sin intento de la base desde asignado_en.
           when p_analista_id is not null then
             case when p_intento is not null then case when p_intento then 'trabajado' else 'sin_tocar' end
                  else (select case when h.intento is true then 'trabajado' else 'sin_tocar' end
                          from private.bases_carga_reparto_hechos(p_lead_id, p_asignado_en) h)
             end
           -- Sin reparto y con analista (armado con su analista anterior) que lo tiene en seguimiento activo (B6): no se reparte.
           when p_vendedor_id is not null and private.base_gestion_en_gestion_hasta(p_lead_id) is not null then 'trabajado'
           else 'sin_repartir'
         end;
$function$;

create function private.bases_carga_reparto_motivo_bloque(p_lead_id uuid, p_activo boolean, p_no_contactar boolean, p_etapa text,
                                                          p_vendedor_id uuid, p_asignado_supervisor_id uuid, p_enfriado_hasta date,
                                                          p_analista_id uuid, p_asignado_en timestamptz, p_agregado_en timestamptz,
                                                          p_dueno uuid, p_subarbol uuid[], p_hoy date)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_motivo text;
  v_estado text;
begin
  -- B10 r2/r3: el reparto EN BLOQUE elige SOLO contactos en estado 'sin_repartir' (private.bases_carga_estado_contacto, la
  -- definición de toda puerta, con las MISMAS entradas): NULL = elegible. Si no, el motivo para «omitidos» y para la revisión
  -- bajo candado: el de private.bases_carga_reparto_motivo (B9: inactivo, fuera_de_ambito, no_descartado, no_contactar,
  -- en_descanso, en_gestion; se evalúa para TODO candidato, como en B9) o, si ese no dice nada, el estado (movido_otra_via).
  -- plpgsql (no sql): sus llamadas guardan el plan entre filas (medido: 5000 candidatos en ~0,1 s en vez de ~1,3 s).
  v_motivo := private.bases_carga_reparto_motivo(p_activo,
                private.bases_carga_en_subarbol(p_subarbol, p_vendedor_id, p_asignado_supervisor_id),
                p_etapa, p_no_contactar, p_enfriado_hasta,
                private.base_gestion_en_gestion_hasta(p_lead_id) is not null, p_hoy);
  if v_motivo is not null then
    return v_motivo;
  end if;
  v_estado := private.bases_carga_estado_contacto(p_lead_id, p_activo, p_no_contactar, p_etapa, p_vendedor_id, p_asignado_supervisor_id,
                                                  p_enfriado_hasta, p_analista_id, p_asignado_en, p_agregado_en, p_dueno, p_subarbol, p_hoy);
  -- r4 (auditor-rls P3-1): un estado NULL nunca es elegible (la definición no lo da hoy; si algún día lo diera, no se reparte).
  return case when v_estado is not distinct from 'sin_repartir' then null else coalesce(v_estado, 'sin_estado') end;
end;
$function$;

create function private.bases_carga_seguimiento_cifras()
returns text[]
language sql
immutable
security invoker
set search_path = ''
as $function$
  -- B10: las cifras que se abren (todo número se abre): las columnas numéricas de crm.seguimiento_bases y
  -- crm.seguimiento_base. «avance» es un cociente (trabajados / repartidos): se abre por «trabajados».
  select array['total', 'sin_repartir', 'repartidos', 'asignados', 'sin_tocar', 'sin_tocar_3_dias', 'trabajados',
               'en_descanso', 'citas', 'reactivados', 'movidos_otra_via', 'retirados', 'no_contactar']::text[];
$function$;

create function private.bases_carga_seguimiento_rol(p_actor uuid)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_rol text := private.rol_crm(p_actor);
begin
  -- B10: el seguimiento es de Supervisión y Gerencia (rol resuelto en el servidor). Analista, coordinación, directorio,
  -- un miembro desactivado o sin sesión → 42501.
  if p_actor is null or (v_rol in ('supervisor', 'gerencia')) is not true then
    raise exception 'Solo Supervisión y Gerencia ven el seguimiento de las bases' using errcode = '42501';
  end if;
  return v_rol;
end;
$function$;

create function private.bases_carga_seguimiento_exigir_base(p_actor uuid, p_rol text, p_base_id uuid)
returns void
language plpgsql
stable
security invoker
set search_path = ''
as $function$
begin
  -- B10: la base existe, está VIVA y el actor la ve (private.bases_carga_base_visible, espejo de la policy
  -- bases_carga_select); si no, P0002 sin delatar si existe.
  if p_base_id is null then
    raise exception 'Indica la base' using errcode = '22023';
  end if;
  if not exists (select 1 from crm.bases_carga b
                  where b.id = p_base_id and b.activo and private.bases_carga_base_visible(p_actor, p_rol, b.supervisor_id)) then
    raise exception 'Base no encontrada o fuera de tu ámbito' using errcode = 'P0002';
  end if;
end;
$function$;

create function private.bases_carga_seguimiento_filas(p_base_ids uuid[], p_hoy date)
returns table(base_id uuid, lead_id uuid, analista_id uuid, asignado_en timestamptz, lead_activo boolean, vendedor_id uuid,
              asignado_supervisor_id uuid, nombre_completo text, estado text, ultimo_intento_en timestamptz,
              ultimo_resultado text, cifras text[])
language sql
stable
security invoker
set search_path = ''
as $function$
  -- B10: UNA fila por contacto VIVO (pertenencia activa) de las bases pedidas, con su estado y el arreglo de las cifras del
  -- seguimiento a las que pertenece (nombres de columna de crm.seguimiento_bases y crm.seguimiento_base). Es la ÚNICA
  -- definición de cada cifra: los conteos y el detalle leen este arreglo. r2: el estado es el de
  -- private.bases_carga_estado_contacto (la definición de toda puerta de B9 y B10) y los hechos desde el reparto, los de
  -- private.bases_carga_reparto_hechos (B9); trabajados, citas y reactivados cuentan solo lo repartido (desde asignado_en). Solo
  -- predicado: sin agregados de conteo (censo analítico).
  with bs as materialized (
    -- El subárbol del supervisor DUEÑO de cada base, una vez por base.
    select b.id, b.supervisor_id, array(select private.bases_carga_subarbol(b.supervisor_id)) as subarbol
      from crm.bases_carga b
     where b.id = any (p_base_ids)
  )
  select x.base_id, x.lead_id, x.analista_id, x.asignado_en, x.activo, x.vendedor_id, x.asignado_supervisor_id, x.nombre_completo,
         x.estado, x.ultimo_en, x.ultimo,
         pg_catalog.array_remove(array[
           'total',
           case when x.estado = 'sin_repartir' then 'sin_repartir' end,
           case when x.rep then 'repartidos' end,
           case when x.rep then 'asignados' end,
           case when x.estado = 'sin_tocar' then 'sin_tocar' end,
           case when x.estado = 'sin_tocar' and x.dias >= 3 then 'sin_tocar_3_dias' end,
           case when x.rep and x.intento is true then 'trabajados' end,
           case when x.estado = 'en_descanso' then 'en_descanso' end,
           case when x.rep and x.cita is true then 'citas' end,
           case when x.rep and x.reactivado is true then 'reactivados' end,
           case when x.estado = 'movido_otra_via' then 'movidos_otra_via' end,
           case when x.estado = 'retirado' then 'retirados' end,
           case when x.estado = 'no_contactar' then 'no_contactar' end]::text[], null)
    from (
      select bl.base_id, bl.lead_id, bl.analista_id, bl.asignado_en, l.activo, l.vendedor_id, l.asignado_supervisor_id,
             l.nombre_completo, (bl.analista_id is not null) as rep, h.intento, h.cita, h.reactivado, u.ultimo_en, u.ultimo,
             private.bases_carga_estado_contacto(l.id, l.activo, l.no_contactar, l.etapa, l.vendedor_id, l.asignado_supervisor_id,
                                                 l.enfriado_hasta, bl.analista_id, bl.asignado_en, bl.creado_en, bs.supervisor_id,
                                                 bs.subarbol, p_hoy, h.intento, h.cita, h.reactivado) as estado,
             (p_hoy - (bl.asignado_en at time zone 'America/Lima')::date) as dias
        from crm.base_carga_leads bl
        join bs on bs.id = bl.base_id
        join crm.leads l on l.id = bl.lead_id
        -- Hechos de la base (private.bases_carga_reparto_hechos, B9) desde el reparto o, sin reparto, desde que entró a la base:
        -- los mismos que la definición única calcularía (se le pasan: una consulta por fila, no dos).
        cross join lateral private.bases_carga_reparto_hechos(bl.lead_id, coalesce(bl.asignado_en, bl.creado_en)) h
        -- Solo para mostrar: el último intento desde el reparto (mismo desempate que private.base_gestion_intentos_ciclo).
        left join lateral (
          select pg_catalog.max(a.creado_en) as ultimo_en,
                 (pg_catalog.array_agg(a.metadata->>'resultado'
                                       order by a.creado_en desc, (a.metadata->>'intento_n')::integer desc, a.id desc))[1] as ultimo
            from crm.actividades a
           where a.lead_id = bl.lead_id and a.metadata->>'evento' = 'intento_base' and a.creado_en >= bl.asignado_en
        ) u on true
       where bl.base_id = any (p_base_ids) and bl.activo
       offset 0  -- el estado se calcula UNA vez por fila (sin esto, el planificador copia la llamada en cada cifra)
    ) x
$function$;

-- ── 1b · B9 r2: la MISMA definición del estado en sus puertas (CREATE OR REPLACE: misma firma, dueño, seguridad y ACL) ────
-- La lista de la base (crm.contactos_de_base): el estado sale de private.bases_carga_estado_contacto (el filtro, el de B9).
create or replace function private.bases_carga_contactos_core(p_actor uuid, p_base_id uuid, p_estado text)
returns table(lead_id uuid, nombre_completo text, telefono text, distrito text, agregado_en timestamptz, analista_id uuid,
              analista_nombre text, estado text)
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_rol text := private.bases_carga_reparto_rol(p_actor);
  v_filtro text := coalesce(p_estado, 'sin_repartir');
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_sup uuid;
  v_subarbol uuid[];
begin
  if p_base_id is null then
    raise exception 'La base es obligatoria' using errcode = '22023';
  end if;
  if (v_filtro in ('sin_repartir', 'repartidos', 'todos')) is not true then
    raise exception 'El filtro es sin_repartir, repartidos o todos' using errcode = '22023';
  end if;
  select b.supervisor_id into v_sup from crm.bases_carga b where b.id = p_base_id;
  if not found or not private.bases_carga_base_visible(p_actor, v_rol, v_sup) then
    raise exception 'Base no encontrada o fuera de tu ámbito' using errcode = 'P0002';
  end if;
  v_subarbol := array(select private.bases_carga_subarbol(v_sup));
  -- Solo contactos que el actor VE y siguen activos (private.bases_carga_lead_ref, la regla de B8 para toda referencia).
  -- B10 r2/r3: el estado es el de private.bases_carga_estado_contacto (el mismo del seguimiento y del reparto en bloque), con
  -- los hechos de private.bases_carga_reparto_hechos desde el reparto o desde que entró a la base. El filtro es el de B9:
  -- sin_repartir = sin analista de la base (su estado dice si el bloque lo puede elegir), repartidos = con analista.
  return query
    select l.id, l.nombre_completo, l.telefono, l.distrito, bl.creado_en, bl.analista_id, p.nombre_completo,
           private.bases_carga_estado_contacto(l.id, l.activo, l.no_contactar, l.etapa, l.vendedor_id, l.asignado_supervisor_id,
                                               l.enfriado_hasta, bl.analista_id, bl.asignado_en, bl.creado_en, v_sup, v_subarbol, v_hoy,
                                               h.intento, h.cita, h.reactivado)
      from crm.base_carga_leads bl
      join crm.leads l on l.id = bl.lead_id
      left join public.perfiles p on p.id = bl.analista_id
      cross join lateral private.bases_carga_reparto_hechos(l.id, coalesce(bl.asignado_en, bl.creado_en)) h
     where bl.base_id = p_base_id and bl.activo
       and (v_filtro = 'todos' or (v_filtro = 'sin_repartir') = (bl.analista_id is null))
       and private.bases_carga_lead_ref(p_actor, v_rol, l.id)
     order by bl.creado_en, l.creado_en, l.id;
end;
$function$;

-- Recoger = lo que el seguimiento muestra «sin tocar» (el mismo estado), sin seguimiento activo B6; de un analista de baja,
-- todo lo suyo que siga descartado (manda B6, que la baja libera).
create or replace function private.bases_carga_reparto_recogible(p_lead_id uuid, p_analista_id uuid, p_asignado_en timestamptz, p_baja boolean)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $function$
  -- UNA definición de «se puede recoger» (la usan la foto y la revisión bajo candado de recoger): sigue vivo, descartado y en
  -- manos de ESE analista (lo movido por otra vía no se deshace, E14), en estado sin_tocar de la definición única
  -- (private.bases_carga_estado_contacto: sin intento desde que se le repartió, sin veto y sin descanso) —salvo que el
  -- analista esté de baja (r1, auditor P3): entonces manda B6, que la baja libera— y sin seguimiento activo B6. `is true`.
  -- B10 r2: «sin tocar» es el mismo estado que cuenta el seguimiento (lo que el supervisor ve en rojo y recoge).
  select coalesce((select (l.activo and l.etapa = 'descartado' and l.vendedor_id = p_analista_id
                           and (p_baja is true
                                or private.bases_carga_estado_contacto(l.id, l.activo, l.no_contactar, l.etapa, l.vendedor_id,
                                                                       l.asignado_supervisor_id, l.enfriado_hasta, p_analista_id,
                                                                       p_asignado_en, null, null, null,
                                                                       (pg_catalog.now() at time zone 'America/Lima')::date) = 'sin_tocar')
                           and private.base_gestion_en_gestion_hasta(l.id) is null) is true
                     from crm.leads l
                    where l.id = p_lead_id), false);
$function$;

-- El reparto: el bloque elige SOLO el estado sin_repartir; el individual rechaza además lo movido por otra vía.
create or replace function private.bases_carga_repartir_core(p_actor uuid, p_operacion_id uuid, p_base_id uuid, p_reparto jsonb)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  v_rol text := private.bases_carga_reparto_rol(p_actor);
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_max integer;
  v_max_analistas integer;
  v_modo text;
  v_asig jsonb;
  v_n integer;
  v_tope integer;
  v_md5 text;
  v_prev jsonb;
  v_sup uuid;
  v_base crm.bases_carga%rowtype;
  v_subarbol uuid[];
  e record;
  c record;
  a_analista uuid[] := '{}';   -- bloque: los analistas en el orden pedido; individual: el analista de cada fila
  a_cantidad integer[] := '{}';
  a_lead uuid[] := '{}';
  a_ev_lead uuid[];
  a_ev_motivo text[];
  v_total integer := 0;
  v_bloqueados uuid[];
  v_elegibles uuid[] := '{}';
  v_pend uuid[];
  v_lote uuid[];
  v_marca bigint := 0;
  v_hasta bigint;
  v_falta integer;
  v_holgura integer;
  v_presupuesto integer;
  v_tomados integer := 0;
  v_examinados uuid[];
  v_disponibles integer;
  v_omitidos jsonb := '[]'::jsonb;
  v_rechazos jsonb := '[]'::jsonb;
  v_dest_lead uuid[] := '{}';
  v_dest_analista uuid[] := '{}';
  v_por_analista jsonb;
  v_pos integer := 0;
  v_motivo text;
  v_upd integer;
  v_ahora timestamptz;
  v_estado text;
  v_estado_c text;  -- B10 r2: el estado del contacto (private.bases_carga_estado_contacto)
  v_resp jsonb;
  i integer;
begin
  select k.max_contactos, k.max_analistas, k.holgura_candados into v_max, v_max_analistas, v_holgura from private.bases_carga_reparto_constantes() k;
  -- Candado y LUEGO evaluación: cada sentencia debe ver lo confirmado tras tomar los candados (como reactivar).
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'Repartir requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation')
      using errcode = '0A000';
  end if;
  if p_base_id is null then
    raise exception 'La base es obligatoria' using errcode = '22023';
  end if;
  -- 1 · FORMA (vale igual para una operación nueva y para su reintento).
  if p_reparto is null or pg_catalog.jsonb_typeof(p_reparto) is distinct from 'object'
     or pg_catalog.jsonb_typeof(p_reparto -> 'asignaciones') is distinct from 'array' then
    raise exception 'El reparto llega como {"modo": "bloque" o "individual", "asignaciones": [...]}' using errcode = '22023';
  end if;
  v_modo := p_reparto ->> 'modo';
  if (v_modo in ('bloque', 'individual')) is not true then
    raise exception 'El modo del reparto es «bloque» o «individual»' using errcode = '22023';
  end if;
  v_asig := p_reparto -> 'asignaciones';
  v_n := pg_catalog.jsonb_array_length(v_asig);
  v_tope := (case when v_modo = 'bloque' then v_max_analistas else v_max end);
  if v_n < 1 or v_n > v_tope then
    raise exception 'Un reparto en % trae entre 1 y % asignaciones (este trae %)', v_modo, v_tope, v_n using errcode = '22023';
  end if;
  for e in select x.valor, x.pos from pg_catalog.jsonb_array_elements(v_asig) with ordinality as x(valor, pos) order by x.pos loop
    if pg_catalog.jsonb_typeof(e.valor) is distinct from 'object'
       or ((e.valor ->> 'analista_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') is not true then
      raise exception 'La asignación % no trae un analista válido', e.pos using errcode = '22023';
    end if;
    if v_modo = 'bloque' then
      if pg_catalog.jsonb_typeof(e.valor -> 'cantidad') is distinct from 'number'
         or ((e.valor ->> 'cantidad') ~ '^[1-9][0-9]{0,5}$') is not true then
        raise exception 'La asignación % no trae una cantidad entera mayor que 0', e.pos using errcode = '22023';
      end if;
      if (e.valor ->> 'analista_id')::uuid = any (a_analista) then
        raise exception 'El analista de la asignación % se repite', e.pos using errcode = '22023';
      end if;
      a_analista := a_analista || (e.valor ->> 'analista_id')::uuid;
      a_cantidad := a_cantidad || (e.valor ->> 'cantidad')::integer;
      v_total := v_total + (e.valor ->> 'cantidad')::integer;
    else
      if ((e.valor ->> 'lead_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') is not true then
        raise exception 'La asignación % no trae un contacto válido', e.pos using errcode = '22023';
      end if;
      if (e.valor ->> 'lead_id')::uuid = any (a_lead) then
        raise exception 'El contacto de la asignación % se repite', e.pos using errcode = '22023';
      end if;
      a_lead := a_lead || (e.valor ->> 'lead_id')::uuid;
      a_analista := a_analista || (e.valor ->> 'analista_id')::uuid;
    end if;
  end loop;
  if v_modo = 'bloque' and v_total > v_max then
    raise exception 'Un reparto mueve hasta % contactos por operación (este pide %)', v_max, v_total using errcode = '22023';
  end if;
  if v_modo = 'individual' and pg_catalog.cardinality(array(select distinct x from pg_catalog.unnest(a_analista) x)) > v_max_analistas then
    raise exception 'Un reparto va a lo más a % analistas', v_max_analistas using errcode = '22023';
  end if;

  -- 2 · Idempotencia: el mismo pedido con el mismo id devuelve su recibo (B8: base aún visible); cada lead_id que el recibo
  -- nombra se vuelve a juzgar con el actor de hoy (si alguno ya no está a su alcance, no se repite: P0002).
  v_md5 := pg_catalog.md5(pg_catalog.jsonb_build_object('tipo', 'repartir', 'base_id', p_base_id, 'reparto', p_reparto)::text);
  v_prev := private.bases_carga_operacion_previa(p_actor, v_rol, p_operacion_id, 'repartir', v_md5);
  if v_prev is not null then
    if exists (select 1 from pg_catalog.jsonb_array_elements(coalesce(v_prev -> 'omitidos', '[]'::jsonb)) x
                where x ->> 'lead_id' is not null and not private.bases_carga_lead_ref(p_actor, v_rol, (x ->> 'lead_id')::uuid)) then
      raise exception 'La respuesta guardada nombra contactos que ya no están a tu alcance; repite la operación con otro identificador'
        using errcode = 'P0002';
    end if;
    return v_prev;
  end if;

  -- 3 · La base: visible (sin delatar si existe), su fila bloqueada NOWAIT, viva y con su supervisor dueño activo.
  select b.supervisor_id into v_sup from crm.bases_carga b where b.id = p_base_id;
  if not found or not private.bases_carga_base_visible(p_actor, v_rol, v_sup) then
    raise exception 'Base no encontrada o fuera de tu ámbito' using errcode = 'P0002';
  end if;
  begin
    select b.* into v_base from crm.bases_carga b where b.id = p_base_id for update nowait;
  exception when lock_not_available then
    raise exception 'Hay otra operación en curso de esta base; reintenta' using errcode = '55P03';
  end;
  if not v_base.activo then
    raise exception 'La base está retirada: no se reparte' using errcode = '22023';
  end if;
  if private.es_destino_crm_activo(v_base.supervisor_id, array['supervisor']::text[]) is not true then
    raise exception 'El supervisor dueño de la base ya no está activo: no se puede repartir' using errcode = '22023';
  end if;
  v_subarbol := array(select private.bases_carga_subarbol(v_base.supervisor_id));
  -- 4 · Los analistas (en el orden en que aparecen).
  for c in select u.a from pg_catalog.unnest(a_analista) with ordinality as u(a, pos) group by u.a order by min(u.pos) loop
    perform private.bases_carga_reparto_analista(v_rol, v_subarbol, c.a);
  end loop;

  if v_modo = 'bloque' then
    -- 5b · Foto SIN candados: los contactos sin repartir de la base, en el orden del reparto (los más antiguos en la base
    -- primero), con su motivo de hoy (private.bases_carga_reparto_motivo, una definición).
    select coalesce(pg_catalog.array_agg(q.lead_id order by q.orden), '{}'), coalesce(pg_catalog.array_agg(q.motivo order by q.orden), '{}')
      into a_ev_lead, a_ev_motivo
      from (select bl.lead_id,
                   pg_catalog.row_number() over (order by bl.creado_en, l.creado_en, l.id) as orden,
                   -- B10 r2: solo el estado sin_repartir de la definición única se elige (NULL); si no, su motivo.
                   private.bases_carga_reparto_motivo_bloque(l.id, l.activo, l.no_contactar, l.etapa, l.vendedor_id, l.asignado_supervisor_id, l.enfriado_hasta, bl.analista_id, bl.asignado_en, bl.creado_en, v_base.supervisor_id, v_subarbol, v_hoy) as motivo
              from crm.base_carga_leads bl
              join crm.leads l on l.id = bl.lead_id
             where bl.base_id = p_base_id and bl.activo and bl.analista_id is null) q;
    v_pend := array(select x.l from unnest(a_ev_lead, a_ev_motivo) with ordinality as x(l, m, o) where x.m is null order by x.o);
    -- r1 (Codex P2): candado SOLO de lo necesario. Por tandas, en ese orden, solo los que faltan, FOR UPDATE SKIP LOCKED (lo que
    -- otro proceso tiene se salta sin esperar; nada fuera de lo pedido queda bloqueado). Bajo el candado, en otra sentencia (ve
    -- lo confirmado), se vuelve a juzgar cada uno con la MISMA definición y, además, que nadie le haya registrado un intento
    -- DURANTE esta operación: B6 cuenta desde la «reasignación», que lleva la hora de esta sentencia, y el analista nuevo lo
    -- heredaría. Lo que no pasa queda sin repartir y bloqueado hasta el commit: r2 (Codex P2) por eso hay un PRESUPUESTO de
    -- candados acumulado —todos los tomados, aceptados o no—: greatest(pedidos + holgura, ceil(pedidos × 1,1)); si se agota
    -- antes de completar, nada (55P03, reintenta: el todo o nada se mantiene).
    v_presupuesto := greatest(v_total + v_holgura, pg_catalog.ceil(v_total * 1.1)::integer);
    loop
      v_falta := v_total - pg_catalog.cardinality(v_elegibles);
      exit when v_falta <= 0;
      if v_tomados >= v_presupuesto then
        raise exception 'Los contactos están cambiando; reintenta' using errcode = '55P03';
      end if;
      select coalesce(pg_catalog.array_agg(b.id order by b.o), '{}'), max(b.o) into v_lote, v_hasta
        from (select l.id, p.o
                from crm.leads l
                join unnest(v_pend) with ordinality as p(id, o) on p.id = l.id
               where p.o > v_marca
               order by p.o
               limit least(v_falta, v_presupuesto - v_tomados)
                 for update of l skip locked) b;
      exit when v_hasta is null;
      v_marca := v_hasta;
      v_tomados := v_tomados + pg_catalog.cardinality(v_lote);
      v_elegibles := v_elegibles || array(
        select x.id from unnest(v_lote) with ordinality as x(id, o) join crm.leads l on l.id = x.id
          join crm.base_carga_leads bl on bl.lead_id = l.id and bl.base_id = p_base_id and bl.activo  -- B10 r2
         where private.bases_carga_reparto_motivo_bloque(l.id, l.activo, l.no_contactar, l.etapa, l.vendedor_id, l.asignado_supervisor_id, l.enfriado_hasta, bl.analista_id, bl.asignado_en, bl.creado_en, v_base.supervisor_id, v_subarbol, v_hoy) is null  -- B10 r2
           and not exists (select 1 from crm.actividades a
                            where a.lead_id = l.id and a.metadata ->> 'evento' = 'intento_base' and a.creado_en >= pg_catalog.statement_timestamp())
         order by x.o);
    end loop;
    v_disponibles := pg_catalog.cardinality(v_elegibles);
    if v_disponibles < v_total then
      raise exception 'Solo hay % contactos disponibles para repartir en esta base (pediste %)', v_disponibles, v_total
        using errcode = '22023', detail = v_disponibles::text;
    end if;
    -- Los más antiguos, en el orden de las asignaciones (Ana 40 · Luis 30: Ana recibe los 40 primeros).
    for i in 1 .. pg_catalog.cardinality(a_analista) loop
      v_dest_lead := v_dest_lead || v_elegibles[v_pos + 1 : v_pos + a_cantidad[i]];
      v_dest_analista := v_dest_analista || pg_catalog.array_fill(a_analista[i], array[a_cantidad[i]]);
      v_pos := v_pos + a_cantidad[i];
    end loop;
    -- Omitidos del bloque, por motivo (lead_id null y su cantidad): los sin repartir que la foto ya descartaba, con su motivo, y
    -- los examinados que no se eligieron, con su motivo de ahora o «ocupado» (otro proceso lo tenía; reintenta).
    v_examinados := array(select p.id from unnest(v_pend) with ordinality as p(id, o) where p.o <= v_marca and not (p.id = any (v_elegibles)));
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('lead_id', null, 'motivo', g.m, 'cantidad', g.n) order by g.m), '[]'::jsonb)
      into v_omitidos
      from (select y.m, pg_catalog.cardinality(pg_catalog.array_agg(y.l)) as n
              from (select x.l, x.m from unnest(a_ev_lead, a_ev_motivo) as x(l, m) where x.m is not null
                    union all
                    select l.id, coalesce(private.bases_carga_reparto_motivo_bloque(l.id, l.activo, l.no_contactar, l.etapa, l.vendedor_id, l.asignado_supervisor_id, l.enfriado_hasta, bl.analista_id, bl.asignado_en, bl.creado_en, v_base.supervisor_id, v_subarbol, v_hoy), 'ocupado')  -- B10 r2
                      from crm.leads l
                      join crm.base_carga_leads bl on bl.lead_id = l.id and bl.base_id = p_base_id and bl.activo  -- B10 r2
                     where l.id = any (v_examinados)) y
             group by y.m) g;
    v_por_analista := (select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('analista_id', x.a, 'cantidad', x.n) order by x.o)
                         from unnest(a_analista, a_cantidad) with ordinality as x(a, n, o));
  else
    -- 5i · Todo o nada: (1) cada uno es de la base y el actor lo ve (si no, P0002 sin decir cuál existe) — r1 (auditor P3):
    -- ANTES de los candados, para no bloquear nada fuera de su alcance —; (2) candado de los pedidos, en orden de id, SKIP
    -- LOCKED; (3) bajo el candado siguen a su alcance (otra vía pudo llevárselos en el intervalo: P0002) y ninguno lo tiene otro
    -- proceso ni recibió un intento durante esta operación (55P03, reintenta); (4) cada uno se puede repartir a SU analista
    -- (22023 con los rechazados).
    if exists (select 1 from pg_catalog.unnest(a_lead) as u(id)
                where not exists (select 1 from crm.base_carga_leads bl where bl.base_id = p_base_id and bl.activo and bl.lead_id = u.id)
                   or not private.bases_carga_lead_ref(p_actor, v_rol, u.id)) then
      raise exception 'Hay contactos que no están en esta base o están fuera de tu ámbito' using errcode = 'P0002';
    end if;
    select coalesce(pg_catalog.array_agg(b.id order by b.id), '{}') into v_bloqueados
      from (select l.id from crm.leads l
             where l.id = any (a_lead)
               and l.id in (select bl.lead_id from crm.base_carga_leads bl where bl.base_id = p_base_id and bl.activo)
             order by l.id
               for update of l skip locked) b;
    if exists (select 1 from pg_catalog.unnest(a_lead) as u(id) where not private.bases_carga_lead_ref(p_actor, v_rol, u.id)) then
      raise exception 'Hay contactos que no están en esta base o están fuera de tu ámbito' using errcode = 'P0002';
    end if;
    if exists (select 1 from pg_catalog.unnest(a_lead) as u(id)
                where not (u.id = any (v_bloqueados))
                   or exists (select 1 from crm.actividades a
                               where a.lead_id = u.id and a.metadata ->> 'evento' = 'intento_base' and a.creado_en >= pg_catalog.statement_timestamp())) then
      raise exception 'Otra operación está usando alguno de esos contactos; reintenta' using errcode = '55P03';
    end if;
    for c in
      select u.lead_id, u.analista_id, bl.analista_id as bl_analista, l.activo, l.etapa, l.no_contactar, l.enfriado_hasta,
             l.vendedor_id, l.asignado_supervisor_id, bl.asignado_en as bl_asignado_en, bl.creado_en as bl_agregado_en  -- B10 r2
        from unnest(a_lead, a_analista) with ordinality as u(lead_id, analista_id, pos)
        join crm.base_carga_leads bl on bl.base_id = p_base_id and bl.activo and bl.lead_id = u.lead_id
        join crm.leads l on l.id = u.lead_id
       order by u.pos
    loop
      -- El seguimiento activo (B6) solo cuenta si el contacto CAMBIA de analista (darlo al que ya lo tiene no reasigna).
      -- r1 (Codex P2): en el ámbito también lo que B9 repartió (Gerencia) fuera del equipo del dueño: la pertenencia dice que
      -- quien lo tiene es su analista. Lo que otra vía movió fuera del equipo, no.
      v_motivo := private.bases_carga_reparto_motivo(c.activo,
                                                     private.bases_carga_en_subarbol(v_subarbol, c.vendedor_id, c.asignado_supervisor_id)
                                                       or (c.bl_analista is not null and c.bl_analista = c.vendedor_id),
                                                     c.etapa, c.no_contactar, c.enfriado_hasta,
                                                     c.vendedor_id is distinct from c.analista_id
                                                       and private.base_gestion_en_gestion_hasta(c.lead_id) is not null, v_hoy);
      -- B10 r2: con la definición única del estado, lo movido por otra vía (también dentro del equipo) tampoco se reparte;
      -- sí un sin repartir (también un armado con su analista anterior, E1) o uno que sigue con su analista.
      if v_motivo is null then
        v_estado_c := private.bases_carga_estado_contacto(c.lead_id, c.activo, c.no_contactar, c.etapa, c.vendedor_id,
                                                          c.asignado_supervisor_id, c.enfriado_hasta, c.bl_analista, c.bl_asignado_en,
                                                          c.bl_agregado_en, v_base.supervisor_id, v_subarbol, v_hoy);
        if (v_estado_c in ('sin_repartir', 'sin_tocar', 'trabajado')) is not true then
          v_motivo := coalesce(v_estado_c, 'sin_estado');  -- r4 (auditor-rls P3-1): un estado NULL no se reparte
        end if;
      end if;
      if v_motivo is not null then
        v_rechazos := v_rechazos || pg_catalog.jsonb_build_object('lead_id', c.lead_id, 'motivo', v_motivo);
      elsif c.bl_analista is not distinct from c.analista_id and c.vendedor_id is not distinct from c.analista_id then
        v_omitidos := v_omitidos || pg_catalog.jsonb_build_object('lead_id', c.lead_id, 'motivo', 'ya_asignado');
      else
        v_dest_lead := v_dest_lead || c.lead_id;
        v_dest_analista := v_dest_analista || c.analista_id;
      end if;
    end loop;
    if pg_catalog.jsonb_array_length(v_rechazos) > 0 then
      raise exception '% de los contactos pedidos no se pueden repartir (en gestión, en descanso, No contactar o fuera de la base); no se repartió ninguno',
        pg_catalog.jsonb_array_length(v_rechazos)
        using errcode = '22023', detail = pg_catalog.jsonb_build_object('rechazados', v_rechazos)::text;
    end if;
    v_por_analista := coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('analista_id', g.a, 'cantidad', g.n) order by g.o)
                                  from (select x.a, pg_catalog.cardinality(pg_catalog.array_agg(x.l)) as n, min(x.o) as o
                                          from unnest(v_dest_lead, v_dest_analista) with ordinality as x(l, a, o) group by x.a) g), '[]'::jsonb);
  end if;

  -- 6 · El reparto: el lead al analista (sigue descartado), por el camino de la casa (todos sus candados corren); y la
  -- pertenencia con su analista, cuándo (después de los candados) y quién.
  v_ahora := pg_catalog.clock_timestamp();
  begin
    update crm.leads l
       set vendedor_id = x.analista, asignado_supervisor_id = null
      from unnest(v_dest_lead, v_dest_analista) as x(lead, analista)
     where l.id = x.lead
       and (l.vendedor_id is distinct from x.analista or l.asignado_supervisor_id is not null);
    get diagnostics v_upd = row_count;
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate;
    if private.bases_carga_error_transitorio(v_estado) then
      raise exception using errcode = v_estado, message = pg_catalog.format('El reparto se interrumpió (%s); reintenta', v_estado);
    end if;
    raise exception using errcode = v_estado, message = pg_catalog.format('No se pudo repartir (%s); no se repartió ninguno', v_estado);
  end;
  update crm.base_carga_leads bl
     set analista_id = x.analista, asignado_en = v_ahora, asignado_por = p_actor
    from unnest(v_dest_lead, v_dest_analista) as x(lead, analista)
   where bl.base_id = p_base_id and bl.activo and bl.lead_id = x.lead;
  get diagnostics v_n = row_count;
  if v_n is distinct from pg_catalog.cardinality(v_dest_lead) then
    raise exception 'El reparto no quedó como se previó' using errcode = 'P0001';
  end if;

  v_resp := pg_catalog.jsonb_build_object('ok', true, 'operacion_id', p_operacion_id, 'base_id', p_base_id, 'modo', v_modo,
                                          'repartidos', pg_catalog.cardinality(v_dest_lead), 'por_analista', v_por_analista,
                                          'omitidos', v_omitidos);
  insert into crm.base_carga_operaciones (actor, operacion_id, base_id, tipo, pedido_md5, respuesta)
  values (p_actor, p_operacion_id, p_base_id, 'repartir', v_md5, v_resp);
  return v_resp;
end;
$function$;

-- El clasificador de B9 ya no tiene llamadores (contactos_core usa la definición única): se BORRA para que no quede una
-- segunda definición del estado. La reversa lo repone byte a byte.
drop function private.bases_carga_reparto_estado(boolean, boolean, text, uuid, boolean, date, uuid, boolean, boolean, boolean, boolean, date);

-- ── 2 · La lista de la base para gestión (drop + create sobre el texto vivo de B6b) ───────────────────────────────────
drop function crm.obtener_base_gestion(uuid, boolean);
create function crm.obtener_base_gestion(p_vendedor_id uuid DEFAULT NULL::uuid, p_incluir_vetados boolean DEFAULT false)
 RETURNS TABLE(lead_id uuid, nombre_completo text, telefono text, distrito text, origen text, categoria_interes text, monto_estimado numeric, moneda text, motivo_descarte text, descartado_en timestamp with time zone, dias_desde_descarte integer, etapa_maxima text, intentos integer, ultimo_resultado text, ultimo_intento_en timestamp with time zone, proxima_llamada_en timestamp with time zone, rellamada_hoy boolean, enfriado_hasta date, ciclo_n integer, vendedor_id uuid, gestiona text, recibido_en timestamp with time zone, no_contactar boolean, no_contactar_en timestamp with time zone, no_contactar_motivo text, no_contactar_por text, base_id uuid, base_nombre text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_vetados boolean := coalesce(p_incluir_vetados, false);  -- B6b: null = false
  v_bases uuid[];  -- B10 r1: las bases VIVAS que ve quien llama (auditor-rls r1, P3)
begin
  v_rol := private.base_gestion_rol(v_uid);
  -- B6b (Miguel, 03/10/2026): los leads «No contactar» solo los ven Supervisión y Gerencia, y solo si los piden.
  if v_vetados and (v_rol in ('supervisor', 'gerencia')) is not true then
    raise exception 'Solo Supervision y Gerencia ven los leads marcados No contactar' using errcode = '42501';
  end if;
  if p_vendedor_id is not null then
    if v_rol = 'vendedor' and p_vendedor_id <> v_uid then
      raise exception 'Un analista solo consulta su propia base' using errcode = '42501';
    end if;
    if v_rol = 'supervisor' and p_vendedor_id not in (select private.vendedor_ids_visibles(v_uid)) then
      raise exception 'Analista no encontrado o fuera de tu ambito' using errcode = 'P0002';
    end if;
  end if;
  -- B10 r1: una vez, no por fila (espejo de la policy bases_carga_select: private.bases_carga_base_visible).
  v_bases := array(select b.id from crm.bases_carga b where b.activo and private.bases_carga_base_visible(v_uid, v_rol, b.supervisor_id));
  return query
  with bs as materialized (
    -- B10 r2: cada base VIVA con el subárbol de su dueño, una vez (lo usa la definición única del estado)
    select b.id, b.nombre, b.supervisor_id, array(select private.bases_carga_subarbol(b.supervisor_id)) as subarbol
      from crm.bases_carga b
     where b.activo
  ),
  base as (
    select l.id, l.nombre_completo, l.telefono, l.distrito, l.origen, l.categoria_interes, l.monto_estimado, l.moneda,
           l.motivo_descarte, l.descartado_en, l.proxima_llamada_en, l.enfriado_hasta, l.ciclo_actual, l.vendedor_id,
           coalesce(l.tenencia_desde, l.creado_en) as recibido_en,  -- B5: cuando le llego el lead a quien lo tiene (el MES del lead)
           l.no_contactar,  -- B6b: solo puede venir en true si se pidieron los vetados
           l.inversionista_id, l.dni,  -- B6b: para resolver la persona del lead (no se devuelven)
           private.base_gestion_intentos_desde(l.descartado_en, l.creado_en, l.enfriado_hasta, v_hoy) as desde,  -- D13: ventana desde el descarte o desde el fin del ultimo descanso
           -- B10 r1: la base VIVA del lead (NULL si no esta en una), solo si quien llama ve la BASE o es el analista del lead
           case when bc.id is not null and (l.vendedor_id = v_uid or bc.id = any (v_bases)) then bc.id end as base_id,
           case when bc.id is not null and (l.vendedor_id = v_uid or bc.id = any (v_bases)) then bc.nombre end as base_nombre
    from crm.leads l
    left join crm.base_carga_leads bl on bl.lead_id = l.id and bl.activo  -- B10: a lo sumo una (indice unico de la pertenencia viva)
    left join bs bc on bc.id = bl.base_id  -- B10 r2: la base VIVA (CTE bs, con el subárbol de su dueño)
    where l.activo and l.etapa = 'descartado' and (not l.no_contactar or v_vetados)  -- B6b: los vetados, solo a pedido
      and (l.enfriado_hasta is null or l.enfriado_hasta <= v_hoy or (v_vetados and l.no_contactar))  -- B6b: un vetado en descanso tambien se ve; un no vetado en descanso, no
      and private.base_gestion_lead_visible(v_uid, v_rol, l.vendedor_id, l.asignado_supervisor_id)
      and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
      and (bc.id is null  -- B10 r3: los DORMIDOS del archivo sin repartir de una base viva viven en la pestaña Bases; un armado
           -- desde el CRM nunca se oculta (sigue con su analista anterior). Sin repartir = la definicion unica de B9 y B10.
           or bl.procedencia is distinct from 'archivo'
           or bl.analista_id is not null  -- con reparto, la definicion nunca da sin_repartir: no se calcula (rendimiento)
           or private.bases_carga_estado_contacto(l.id, l.activo, l.no_contactar, l.etapa, l.vendedor_id, l.asignado_supervisor_id,
                                                  l.enfriado_hasta, bl.analista_id, bl.asignado_en, bl.creado_en, bc.supervisor_id,
                                                  bc.subarbol, v_hoy) is distinct from 'sin_repartir')
  ),
  intentos as (
    -- B3c: contador, último resultado (desempate por intento_n, Codex B3 #5) y último intento salen de la MISMA definición
    -- que usan el núcleo y el enfriamiento: private.base_gestion_intentos_ciclo, con la ventana D13 de cada lead.
    select c.lead_id, c.n, c.ultimo, c.ultimo_en
    from (select array_agg(b.id order by b.id) as ids, array_agg(b.desde order by b.id) as desdes from base b) q
    cross join lateral private.base_gestion_intentos_ciclo(q.ids, q.desdes) c
  ),
  ciclo as (
    -- El ciclo vigente empieza en la ultima reapertura (cambio_etapa descartado → nuevo) o, si nunca hubo, al inicio.
    -- Se acota con el propio historial (misma fuente y mismo reloj que los cambios de etapa): robusto frente a
    -- transacciones multi-sentencia, donde now() del log y statement_timestamp() del ledger difieren.
    select b.id as lead_id,
           coalesce((select max(a.creado_en) from crm.actividades a
                      where a.lead_id = b.id and a.tipo = 'cambio_etapa' and a.metadata->>'etapa_anterior' = 'descartado'),
                    '-infinity'::timestamptz) as desde
    from base b
  ),
  etapas as (
    select a.lead_id,
           max(greatest(private.base_gestion_etapa_rango(a.metadata->>'etapa_anterior'),
                        private.base_gestion_etapa_rango(case when a.metadata->>'etapa_nueva' <> 'descartado' then a.metadata->>'etapa_nueva' end))) as rango
    from crm.actividades a join ciclo c on c.lead_id = a.lead_id
    where a.tipo = 'cambio_etapa' and a.creado_en >= c.desde
      -- Codex B3 #6: el descarte del ciclo anterior puede compartir instante con la reapertura (misma transaccion): fuera.
      and not (a.creado_en = c.desde and a.metadata->>'etapa_nueva' = 'descartado')
    group by a.lead_id
  ),
  marca as (
    -- B6b: cuándo, por qué y quién marcó «No contactar». Evento vigente del veto: si el lead tiene persona y la persona está
    -- vetada, la ÚLTIMA nota del veto entre TODOS los leads de la persona (los que marcar/levantar/postventa actualizan); si
    -- no, la última nota del propio lead. Se muestra solo si ese evento es un «marcar» y su lead es visible para quien llama.
    select b.id as lead_id, ev.creado_en, ev.motivo, ev.creado_por
    from base b
    cross join lateral (
      -- La persona, EXACTAMENTE como la resuelven marcar/levantar: enlace; si no, puente (canónica); si no, DNI.
      select coalesce(b.inversionista_id,
                      (select private.inversionista_canonica(il.inversionista_id) from crm.inversionista_leads il
                        where il.lead_id = b.id order by (il.rol = 'canonico') desc, il.inversionista_id limit 1),
                      private.inversionista_por_documento('DNI', b.dni)) as id
    ) pe
    left join crm.inversionistas i on i.id = pe.id
    cross join lateral (
      -- La más reciente entre las ÚLTIMAS notas de cada lead del conjunto: cada una sale del índice (lead_id, creado_en desc).
      select n.ev_lead, n.creado_en, n.accion, n.creado_por, n.motivo
        from (select b.id as lid
              union
              select x from private.leads_de_persona_veto(pe.id) x where i.no_contactar is true) s  -- el conjunto de las puertas
        cross join lateral (
          select a.lead_id as ev_lead, a.creado_en, a.id, a.metadata->>'accion' as accion, a.creado_por,
                 coalesce(a.metadata->>'motivo',
                          case when a.metadata ? 'postventa_gestion_id' then pg_catalog.regexp_replace(a.detalle, '^No contactar: ', '') end) as motivo
            from crm.actividades a
           where a.lead_id = s.lid and a.metadata->>'evento' = 'no_contactar'
           order by a.creado_en desc, a.id desc
           limit 1
        ) n
       order by n.creado_en desc, n.id desc
       limit 1
    ) ev
    join crm.leads le on le.id = ev.ev_lead
    where b.no_contactar and ev.accion = 'marcar'
      and le.activo and private.base_gestion_lead_visible(v_uid, v_rol, le.vendedor_id, le.asignado_supervisor_id)  -- nada de otro equipo
  )
  select b.id, b.nombre_completo, b.telefono, b.distrito, b.origen, b.categoria_interes, b.monto_estimado, b.moneda,
         b.motivo_descarte, b.descartado_en,
         case when b.descartado_en is null then null else (v_hoy - (b.descartado_en at time zone 'America/Lima')::date)::integer end,
         case coalesce(e.rango, 0) when 1 then 'nuevo' when 2 then 'contactado' when 3 then 'reunion_agendada'
                                   when 4 then 'propuesta_enviada' when 5 then 'convertido' else 'sin_datos' end,
         coalesce(i.n, 0), i.ultimo, i.ultimo_en,
         b.proxima_llamada_en,
         (not b.no_contactar and b.proxima_llamada_en is not null and (b.proxima_llamada_en at time zone 'America/Lima')::date <= v_hoy),  -- B6b: un vetado nunca va a «Llamar hoy»
         b.enfriado_hasta, b.ciclo_actual, b.vendedor_id, p.nombre_completo, b.recibido_en,
         b.no_contactar, m.creado_en, m.motivo, pm.nombre_completo,
         b.base_id, b.base_nombre  -- B10
  from base b
  left join intentos i on i.lead_id = b.id
  left join etapas e on e.lead_id = b.id
  left join public.perfiles p on p.id = b.vendedor_id
  left join marca m on m.lead_id = b.id
  left join public.perfiles pm on pm.id = m.creado_por
  -- Contrato (encargo): rellamada vencida o de hoy → etapa maxima (desc) → dias desde el descarte (asc); la hora de la
  -- rellamada solo desempata (Codex B3 #4). B6b: los vetados, al final (sin vetados el orden es el de B5).
  order by b.no_contactar,
           (not b.no_contactar and b.proxima_llamada_en is not null and (b.proxima_llamada_en at time zone 'America/Lima')::date <= v_hoy) desc,
           coalesce(e.rango, 0) desc,
           (b.descartado_en at time zone 'America/Lima')::date desc nulls last,  -- menos dias desde el descarte primero
           b.proxima_llamada_en asc nulls last,
           b.id;
end;
$function$;
alter function crm.obtener_base_gestion(uuid, boolean) owner to postgres;
revoke all on function crm.obtener_base_gestion(uuid, boolean) from public, anon, authenticated, service_role;
grant execute on function crm.obtener_base_gestion(uuid, boolean) to authenticated;

-- ── 3 · Puertas del seguimiento (DEFINER: las tablas de bases no tienen grants; validan, resuelven rol y ámbito y leen) ──
create function crm.seguimiento_bases()
returns table(base_id uuid, nombre text, origen text, supervisor_id uuid, supervisor_nombre text, creado_en timestamptz,
              total integer, sin_repartir integer, repartidos integer, sin_tocar integer, trabajados integer,
              en_descanso integer, citas integer, reactivados integer, avance numeric,
              movidos_otra_via integer, retirados integer, no_contactar integer)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.bases_carga_seguimiento_rol(v_uid);
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_ids uuid[];
begin
  -- Las bases VIVAS que el actor ve: Supervisión, las de su subárbol; Gerencia, todas (espejo de la policy).
  select coalesce(pg_catalog.array_agg(b.id), '{}') into v_ids
    from crm.bases_carga b
   where b.activo and private.bases_carga_base_visible(v_uid, v_rol, b.supervisor_id);
  return query
  with c as (
    select x.base_id as id,
           count(*) filter (where 'total' = any (x.cifras))::integer as n_total,
           count(*) filter (where 'sin_repartir' = any (x.cifras))::integer as n_sin_repartir,
           count(*) filter (where 'repartidos' = any (x.cifras))::integer as n_repartidos,
           count(*) filter (where 'sin_tocar' = any (x.cifras))::integer as n_sin_tocar,
           count(*) filter (where 'trabajados' = any (x.cifras))::integer as n_trabajados,
           count(*) filter (where 'en_descanso' = any (x.cifras))::integer as n_en_descanso,
           count(*) filter (where 'citas' = any (x.cifras))::integer as n_citas,
           count(*) filter (where 'reactivados' = any (x.cifras))::integer as n_reactivados,
           count(*) filter (where 'movidos_otra_via' = any (x.cifras))::integer as n_movidos,
           count(*) filter (where 'retirados' = any (x.cifras))::integer as n_retirados,
           count(*) filter (where 'no_contactar' = any (x.cifras))::integer as n_no_contactar
      from private.bases_carga_seguimiento_filas(v_ids, v_hoy) x
     group by x.base_id
  )
  select b.id, b.nombre, b.origen, b.supervisor_id, p.nombre_completo, b.creado_en,
         coalesce(c.n_total, 0), coalesce(c.n_sin_repartir, 0), coalesce(c.n_repartidos, 0), coalesce(c.n_sin_tocar, 0),
         coalesce(c.n_trabajados, 0), coalesce(c.n_en_descanso, 0), coalesce(c.n_citas, 0), coalesce(c.n_reactivados, 0),
         case when coalesce(c.n_repartidos, 0) > 0 then pg_catalog.round(c.n_trabajados::numeric / c.n_repartidos, 4)
              else 0.0000 end,
         coalesce(c.n_movidos, 0), coalesce(c.n_retirados, 0), coalesce(c.n_no_contactar, 0)
    from crm.bases_carga b
    left join c on c.id = b.id
    left join public.perfiles p on p.id = b.supervisor_id
   where b.id = any (v_ids)
   order by b.creado_en desc, b.id;
end;
$function$;

create function crm.seguimiento_base(p_base_id uuid)
returns table(analista_id uuid, analista_nombre text, asignados integer, sin_tocar integer, sin_tocar_3_dias integer,
              trabajados integer, en_descanso integer, citas integer, reactivados integer, ultimo_intento_en timestamptz,
              movidos_otra_via integer, retirados integer, no_contactar integer)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.bases_carga_seguimiento_rol(v_uid);
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
begin
  perform private.bases_carga_seguimiento_exigir_base(v_uid, v_rol, p_base_id);
  return query
  with vis as (
    -- r4 (Codex r2, P2): el ámbito del actor, una vez. Gerencia ve a todos: nunca tiene fila anónima.
    select array(select private.vendedor_ids_visibles(v_uid)) as ids
  ),
  c as (
    -- Una fila por analista del ámbito; TODOS los de fuera, en UNA fila anónima (id NULL): cifras sumadas, último intento máximo.
    select case when v_rol = 'gerencia' or x.analista_id = any (vis.ids) then x.analista_id end as id,
           count(*) filter (where 'asignados' = any (x.cifras))::integer as n_asignados,
           count(*) filter (where 'sin_tocar' = any (x.cifras))::integer as n_sin_tocar,
           count(*) filter (where 'sin_tocar_3_dias' = any (x.cifras))::integer as n_sin_tocar_3_dias,
           count(*) filter (where 'trabajados' = any (x.cifras))::integer as n_trabajados,
           count(*) filter (where 'en_descanso' = any (x.cifras))::integer as n_en_descanso,
           count(*) filter (where 'citas' = any (x.cifras))::integer as n_citas,
           count(*) filter (where 'reactivados' = any (x.cifras))::integer as n_reactivados,
           pg_catalog.max(x.ultimo_intento_en) as ultimo,
           count(*) filter (where 'movidos_otra_via' = any (x.cifras))::integer as n_movidos,
           count(*) filter (where 'retirados' = any (x.cifras))::integer as n_retirados,
           count(*) filter (where 'no_contactar' = any (x.cifras))::integer as n_no_contactar
      from private.bases_carga_seguimiento_filas(array[p_base_id], v_hoy) x
      cross join vis
     where x.analista_id is not null
     group by 1
  )
  -- El analista (id y nombre) solo si está en el ámbito del actor (auditor-rls r1, P3); los de otro equipo (Gerencia puede
  -- repartir a cualquiera, E11) salen juntos, sin identificar, en la última fila: se abren por la base.
  select c.id, p.nombre_completo, c.n_asignados, c.n_sin_tocar, c.n_sin_tocar_3_dias,
         c.n_trabajados, c.n_en_descanso, c.n_citas, c.n_reactivados, c.ultimo, c.n_movidos, c.n_retirados, c.n_no_contactar
    from c
    left join public.perfiles p on p.id = c.id
   order by (c.id is null), p.nombre_completo, c.id;
end;
$function$;

create function crm.seguimiento_base_detalle(p_base_id uuid, p_analista_id uuid default null, p_cifra text default null)
returns table(lead_id uuid, nombre_completo text, estado text, asignado_en timestamptz, ultimo_intento_en timestamptz,
              ultimo_resultado text)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.bases_carga_seguimiento_rol(v_uid);
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
begin
  if (p_cifra = any (private.bases_carga_seguimiento_cifras())) is not true then
    raise exception 'Cifra inválida: se espera una de %', pg_catalog.array_to_string(private.bases_carga_seguimiento_cifras(), ', ')
      using errcode = '22023';
  end if;
  perform private.bases_carga_seguimiento_exigir_base(v_uid, v_rol, p_base_id);
  -- r4 (Codex r2, P2): un analista explícito, PRIMERO en el ámbito del actor (Gerencia: cualquiera) y después con contactos en
  -- la base; los dos casos con el MISMO P0002 (un UUID externo no se puede atribuir ni sondear).
  if p_analista_id is not null
     and v_rol is distinct from 'gerencia'
     and (p_analista_id in (select private.vendedor_ids_visibles(v_uid))) is not true then
    raise exception 'Analista no encontrado en esta base' using errcode = 'P0002';
  end if;
  if p_analista_id is not null
     and not exists (select 1 from crm.base_carga_leads bl
                      where bl.base_id = p_base_id and bl.activo and bl.analista_id = p_analista_id) then
    raise exception 'Analista no encontrado en esta base' using errcode = 'P0002';
  end if;
  -- Las MISMAS filas que cuentan las cifras (el arreglo cifras de private.bases_carga_seguimiento_filas). lead_id y nombre,
  -- solo si el actor ve el lead y sigue activo (private.bases_carga_lead_ref, B8): si no, la fila cuenta sin delatar quién es.
  return query
  select case when r.ve then x.lead_id end, case when r.ve then x.nombre_completo end, x.estado, x.asignado_en,
         x.ultimo_intento_en, x.ultimo_resultado
    from private.bases_carga_seguimiento_filas(array[p_base_id], v_hoy) x
    cross join lateral (select private.bases_carga_lead_ref(v_uid, v_rol, x.lead_id) as ve) r
   where (p_analista_id is null or x.analista_id = p_analista_id)
     and p_cifra = any (x.cifras)
   order by x.asignado_en desc nulls last, x.ultimo_intento_en desc nulls last, x.lead_id;
end;
$function$;

-- ── 4 · Capital al reactivar: el núcleo con capital (una sola definición), el de 4 argumentos como envoltorio y la _v2 ──
create function private.base_gestion_reactivar_capital_core(p_actor uuid, p_operacion_id uuid, p_lead_id uuid, p_nota text,
                                                            p_monto_estimado numeric, p_moneda text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_rol text;
  v_lead crm.leads%rowtype;
  v_prev jsonb;
  v_n integer;
  v_guc text;
  v_resp jsonb;
  v_reabrir jsonb;
begin
  if p_actor is null or p_operacion_id is null or p_lead_id is null then
    raise exception 'Operacion, lead y actor son obligatorios' using errcode = '22023';
  end if;
  v_rol := private.base_gestion_rol(p_actor);
  if length(coalesce(p_nota, '')) > 2000 then
    raise exception 'La nota supera los 2000 caracteres' using errcode = '22023';
  end if;
  -- Candados de la casa: persona ANTES que lead (como llamada_registrar y marcar_no_contactar); reabrir_lead_fn los
  -- vuelve a tomar dentro de la misma transaccion sin esperar.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'Reactivar requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  perform private.bloquear_personas_de_leads(array[p_lead_id], null);
  select * into v_lead from crm.leads where id = p_lead_id for update;
  -- Idempotencia DESPUES del candado del lead: dos clics concurrentes → el segundo espera y recibe el replay.
  select a.metadata->'respuesta' into v_prev from crm.actividades a where a.id = p_operacion_id and a.creado_por = p_actor;
  if found then
    -- B10 r1 (Codex, riesgo): el capital pedido es parte de la identidad de la operacion (como la nota del intento).
    if v_prev is null or (v_prev->>'lead_id')::uuid is distinct from p_lead_id or v_prev->>'evento' is distinct from 'reactivacion_base'
       or (v_prev->>'solicitud_monto')::numeric is distinct from p_monto_estimado or v_prev->>'solicitud_moneda' is distinct from p_moneda then
      raise exception 'Esta operacion ya corresponde a otro contenido' using errcode = '23505';
    end if;
    return v_prev || jsonb_build_object('replay', true);
  end if;
  if v_lead.id is null or not v_lead.activo
     or not private.base_gestion_lead_visible(p_actor, v_rol, v_lead.vendedor_id, v_lead.asignado_supervisor_id) then
    raise exception 'Lead no encontrado o fuera de tu ambito' using errcode = 'P0002';
  end if;
  if v_lead.etapa <> 'descartado' then
    raise exception 'El lead ya no esta en la base (no esta descartado)' using errcode = '22023';
  end if;
  if v_lead.no_contactar then
    raise exception 'No insistir: el lead esta marcado No contactar' using errcode = 'P0429';
  end if;
  -- B10 (E8): un contacto sin capital (base cargada) no sale del descarte sin el: se pide aqui, ANTES de reabrir (el
  -- CHECK leads_monto_estimado_valido rechazaria la reapertura), y el episodio que abre la reapertura nace con ese capital.
  -- Con capital ya puesto, p_monto_estimado y p_moneda se ignoran. p_moneda NULL = la moneda que ya tiene el lead.
  if v_lead.monto_estimado is null then
    if p_monto_estimado is null then
      raise exception 'Indica el capital estimado para reactivar' using errcode = '22023';
    end if;
    if (p_monto_estimado > 0 and p_monto_estimado <= 9999999999.99 and p_monto_estimado = trunc(p_monto_estimado, 2)) is not true then
      raise exception 'El capital estimado debe ser mayor que 0, de hasta 9999999999.99 y con 2 decimales como maximo' using errcode = '22023';
    end if;
    if p_moneda is not null and (p_moneda in ('PEN', 'USD')) is not true then
      raise exception 'La moneda del capital es PEN o USD' using errcode = '22023';
    end if;
    update crm.leads set monto_estimado = p_monto_estimado, moneda = coalesce(p_moneda, moneda) where id = p_lead_id;
  end if;
  -- 1. Reabrir por la puerta sellada (→ nuevo, ciclo nuevo, SLA reiniciado, veto de persona verificado).
  v_reabrir := crm.reabrir_lead_fn(p_lead_id);
  -- 2. En la misma transaccion, a «contactado» (D1): el guard de tenencia lo permite porque ya old.etapa = nuevo.
  update crm.leads set etapa = 'contactado' where id = p_lead_id and activo and etapa = 'nuevo';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'No se pudo avanzar el lead reabierto a contactado' using errcode = 'P0001';
  end if;
  -- 3. Sello de la base: marca de reactivacion, sin rellamada ni descanso.
  v_guc := coalesce(pg_catalog.current_setting('crm.op_base_gestion', true), 'off');
  perform pg_catalog.set_config('crm.op_base_gestion', 'on', true);
  update crm.leads set reactivado_en = now(), proxima_llamada_en = null, enfriado_hasta = null where id = p_lead_id;
  perform pg_catalog.set_config('crm.op_base_gestion', v_guc, true);
  select * into v_lead from crm.leads where id = p_lead_id;
  v_resp := jsonb_build_object('ok', true, 'evento', 'reactivacion_base', 'lead_id', p_lead_id, 'etapa', v_lead.etapa,
                               'reactivado_en', v_lead.reactivado_en, 'ciclo_n', v_lead.ciclo_actual,
                               'reabierto_por', v_reabrir->>'reabierto_por', 'replay', false)
            -- B10 r1: el capital EFECTIVO del lead y el pedido (identidad del replay)
            || jsonb_build_object('monto_estimado', v_lead.monto_estimado, 'moneda', v_lead.moneda,
                                  'solicitud_monto', p_monto_estimado, 'solicitud_moneda', p_moneda);
  -- 4. Historial (D9): la linea de la reactivacion, con la respuesta para la idempotencia, bajo el sello de actividades.
  perform pg_catalog.set_config('crm.op_base_gestion', 'on', true);
  insert into crm.actividades (id, lead_id, tipo, detalle, metadata, creado_por)
  values (p_operacion_id, p_lead_id, 'nota', coalesce(nullif(pg_catalog.btrim(p_nota), ''), 'Reactivado desde la base para gestión'),
          jsonb_build_object('evento', 'reactivacion_base', 'via', 'base_gestion', 'etapa', 'contactado',
                             'ciclo_n', v_lead.ciclo_actual, 'respuesta', v_resp),
          p_actor);
  perform pg_catalog.set_config('crm.op_base_gestion', v_guc, true);
  return v_resp;
end;
$function$;

-- Misma firma, mismo DEFINER, search_path y ACL ({postgres=X/postgres}: CREATE OR REPLACE no la cambia); el cuerpo delega.
create or replace function private.base_gestion_reactivar_core(p_actor uuid, p_operacion_id uuid, p_lead_id uuid, p_nota text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  -- B10: la definición vive en private.base_gestion_reactivar_capital_core; por aquí, sin capital (la puerta publicada y el
  -- intento «agendó cita»): un lead sin capital → 22023 «Indica el capital estimado para reactivar».
  return private.base_gestion_reactivar_capital_core(p_actor, p_operacion_id, p_lead_id, p_nota, null::numeric, null::text);
end;
$function$;

create function private.base_gestion_intento_capital_core(p_actor uuid, p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_nota text,
                                                          p_proxima timestamp with time zone, p_monto_estimado numeric, p_moneda text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_rol text;
  v_c record;
  v_lead crm.leads%rowtype;
  v_prev jsonb;
  v_n integer;
  v_tipo text;
  v_guc1 text;
  v_guc2 text;
  v_meta jsonb;
  v_resp jsonb;
  v_react jsonb;
  v_hoy date := (now() at time zone 'America/Lima')::date;
begin
  if p_actor is null or p_operacion_id is null or p_lead_id is null then
    raise exception 'Operacion, lead y actor son obligatorios' using errcode = '22023';
  end if;
  v_rol := private.base_gestion_rol(p_actor);
  if p_resultado is null or p_resultado not in ('no_contesto', 'volver_a_llamar', 'agendo_reunion', 'no_interesado',
                                                'numero_errado', 'no_es_la_persona', 'pide_otro_producto') then
    raise exception 'Resultado de llamada invalido' using errcode = '22023';
  end if;
  select * into v_c from private.base_gestion_constantes();
  -- Validaciones de FORMA (valen igual para una operacion nueva y para su reintento).
  if p_resultado = 'volver_a_llamar' and p_proxima is null then
    raise exception 'Indica cuando volver a llamar' using errcode = '22023';
  elsif p_resultado <> 'volver_a_llamar' and p_proxima is not null then
    raise exception 'Solo "volver a llamar" lleva fecha de rellamada' using errcode = '22023';
  end if;
  if length(coalesce(p_nota, '')) > 2000 then
    raise exception 'La nota supera los 2000 caracteres' using errcode = '22023';
  end if;
  -- «agendó cita» reactivara: candados de persona ANTES del lead (protocolo de la casa).
  if p_resultado = 'agendo_reunion' then
    if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
      raise exception 'Agendar cita desde la base requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
    end if;
    perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
    perform private.bloquear_personas_de_leads(array[p_lead_id], null);
  end if;
  select * into v_lead from crm.leads where id = p_lead_id for update;
  -- Idempotencia DESPUES del candado del lead, solo entre operaciones del mismo actor y ANTES de las validaciones
  -- temporales (Codex B3 #1: el reintento de una rellamada ya vencida debe seguir devolviendo su respuesta). La identidad
  -- de la operacion incluye lead, resultado, fecha de rellamada y nota (Codex B3 #2).
  select a.metadata->'respuesta' into v_prev from crm.actividades a where a.id = p_operacion_id and a.creado_por = p_actor;
  if found then
    if v_prev is null or (v_prev->>'lead_id')::uuid is distinct from p_lead_id or v_prev->>'resultado' is distinct from p_resultado
       or v_prev->>'evento' is distinct from 'intento_base'
       or (v_prev->>'solicitud_proxima')::timestamptz is distinct from p_proxima
       or v_prev->>'nota_md5' is distinct from md5(coalesce(pg_catalog.btrim(p_nota), ''))
       -- B10 r1 (Codex, riesgo): el capital pedido es parte de la identidad de la operacion.
       or (v_prev->>'solicitud_monto')::numeric is distinct from p_monto_estimado or v_prev->>'solicitud_moneda' is distinct from p_moneda then
      raise exception 'Esta operacion ya corresponde a otro contenido' using errcode = '23505';
    end if;
    return v_prev || jsonb_build_object('replay', true);
  end if;
  -- Validaciones TEMPORALES: solo para una operacion nueva.
  if p_resultado = 'volver_a_llamar' then
    if p_proxima <= now() then
      raise exception 'La rellamada debe ser futura' using errcode = '22023';
    end if;
    if p_proxima > now() + make_interval(days => v_c.dias_max_rellamada) then
      raise exception 'La rellamada se agenda como maximo % dias adelante', v_c.dias_max_rellamada using errcode = '22023';
    end if;
  end if;
  if v_lead.id is null or not v_lead.activo
     or not private.base_gestion_lead_visible(p_actor, v_rol, v_lead.vendedor_id, v_lead.asignado_supervisor_id) then
    raise exception 'Lead no encontrado o fuera de tu ambito' using errcode = 'P0002';
  end if;
  if v_lead.etapa <> 'descartado' then
    raise exception 'El lead no esta en la base (no esta descartado)' using errcode = '22023';
  end if;
  if v_lead.no_contactar then
    raise exception 'No insistir: el lead esta marcado No contactar' using errcode = 'P0429';
  end if;
  if v_lead.enfriado_hasta is not null and v_lead.enfriado_hasta > v_hoy then
    raise exception 'El lead esta en descanso hasta el %', to_char(v_lead.enfriado_hasta, 'DD/MM/YYYY') using errcode = '22023';
  end if;
  -- B3c: los intentos del ciclo se cuentan en private.base_gestion_intentos_ciclo (una sola definición, misma ventana D13).
  v_n := coalesce((select c.n from private.base_gestion_intentos_ciclo(array[p_lead_id], array[private.base_gestion_intentos_desde(v_lead.descartado_en, v_lead.creado_en, v_lead.enfriado_hasta, v_hoy)]) c), 0) + 1;  -- D13
  v_tipo := case when p_resultado in ('no_contesto', 'numero_errado', 'no_es_la_persona')
                 then 'llamada_no_contestada' else 'llamada_realizada' end;
  v_meta := jsonb_strip_nulls(jsonb_build_object(
    'evento', 'intento_base', 'via', 'base_gestion', 'resultado', p_resultado, 'intento_n', v_n,
    'ciclo_n', v_lead.ciclo_actual, 'proxima_llamada_en', p_proxima));  -- to_jsonb(timestamptz): ISO con zona, nunca ::text
  v_guc1 := coalesce(pg_catalog.current_setting('crm.op_resultado_llamada', true), 'off');
  v_guc2 := coalesce(pg_catalog.current_setting('crm.op_base_gestion', true), 'off');
  perform pg_catalog.set_config('crm.op_resultado_llamada', 'on', true);
  perform pg_catalog.set_config('crm.op_base_gestion', 'on', true);
  insert into crm.actividades (id, lead_id, tipo, detalle, metadata, creado_por)
  values (p_operacion_id, p_lead_id, v_tipo, nullif(pg_catalog.btrim(p_nota), ''), v_meta, p_actor);
  update crm.leads set proxima_llamada_en = case when p_resultado = 'volver_a_llamar' then p_proxima else null end
   where id = p_lead_id
     and proxima_llamada_en is distinct from case when p_resultado = 'volver_a_llamar' then p_proxima else null end;
  perform pg_catalog.set_config('crm.op_resultado_llamada', v_guc1, true);
  perform pg_catalog.set_config('crm.op_base_gestion', v_guc2, true);
  -- «agendó cita» reactiva en la misma transaccion (D3); la cita se agenda despues por el flujo normal del lead vivo.
  if p_resultado = 'agendo_reunion' then
    -- Codex B3 #3: la operacion hija lleva un uuid NUEVO (no derivable del padre) y no puede ser un replay ajeno; la
    -- idempotencia del conjunto la da la operacion padre.
    -- B10 (E8): con el capital del intento (obligatorio si el lead no lo tiene: lo exige el núcleo de reactivar).
    v_react := private.base_gestion_reactivar_capital_core(p_actor, gen_random_uuid(), p_lead_id, 'Agendó cita desde la base para gestión',
                                                           p_monto_estimado, p_moneda);
    if coalesce((v_react->>'replay')::boolean, false) or v_react->>'etapa' is distinct from 'contactado' then
      raise exception 'La reactivacion de "agendo cita" no se completo' using errcode = 'P0001';
    end if;
  end if;
  select * into v_lead from crm.leads where id = p_lead_id;  -- tras el trigger de enfriamiento (B4) y la reactivacion
  v_resp := jsonb_build_object('ok', true, 'evento', 'intento_base', 'lead_id', p_lead_id, 'actividad_id', p_operacion_id,
                               'resultado', p_resultado, 'intento_n', v_n, 'ciclo_n', v_meta->>'ciclo_n',
                               'proxima_llamada_en', v_lead.proxima_llamada_en, 'enfriado_hasta', v_lead.enfriado_hasta,
                               'reactivado', v_react is not null, 'etapa', v_lead.etapa, 'replay', false,
                               'solicitud_proxima', p_proxima, 'nota_md5', md5(coalesce(pg_catalog.btrim(p_nota), '')))
            -- B10 r1: el capital EFECTIVO del lead y el pedido (identidad del replay)
            || jsonb_build_object('monto_estimado', v_lead.monto_estimado, 'moneda', v_lead.moneda,
                                  'solicitud_monto', p_monto_estimado, 'solicitud_moneda', p_moneda);
  perform pg_catalog.set_config('crm.op_resultado_llamada', 'on', true);
  perform pg_catalog.set_config('crm.op_base_gestion', 'on', true);
  update crm.actividades set metadata = metadata || jsonb_build_object('respuesta', v_resp) where id = p_operacion_id;
  perform pg_catalog.set_config('crm.op_resultado_llamada', v_guc1, true);
  perform pg_catalog.set_config('crm.op_base_gestion', v_guc2, true);
  return v_resp;
end;
$function$;

-- Misma firma, mismo DEFINER, search_path y ACL; el cuerpo delega (sin capital).
create or replace function private.base_gestion_intento_core(p_actor uuid, p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_nota text,
                                                             p_proxima timestamp with time zone)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  -- B10: la definición vive en private.base_gestion_intento_capital_core; por aquí, sin capital (la puerta publicada): un
  -- «agendó cita» sobre un lead sin capital → 22023 «Indica el capital estimado para reactivar».
  return private.base_gestion_intento_capital_core(p_actor, p_operacion_id, p_lead_id, p_resultado, p_nota, p_proxima, null::numeric, null::text);
end;
$function$;

create function crm.registrar_intento_base_v2(p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_nota text default null,
                                              p_proxima_llamada timestamptz default null, p_monto_estimado numeric default null,
                                              p_moneda text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'No autorizado' using errcode = '42501'; end if;
  return private.base_gestion_intento_capital_core(v_uid, p_operacion_id, p_lead_id, p_resultado, p_nota, p_proxima_llamada,
                                                    p_monto_estimado, p_moneda);
end;
$function$;

create function crm.reactivar_lead_base_v2(p_operacion_id uuid, p_lead_id uuid, p_nota text default null,
                                           p_monto_estimado numeric default null, p_moneda text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'No autorizado' using errcode = '42501'; end if;
  return private.base_gestion_reactivar_capital_core(v_uid, p_operacion_id, p_lead_id, p_nota, p_monto_estimado, p_moneda);
end;
$function$;

-- ── 5 · Dueños y permisos: EXECUTE de las puertas solo para authenticated; el núcleo y los ayudantes, para nadie ────────
alter function private.bases_carga_estado_contacto(uuid, boolean, boolean, text, uuid, uuid, date, uuid, timestamptz, timestamptz, uuid, uuid[], date, boolean, boolean, boolean) owner to postgres;
alter function private.bases_carga_reparto_motivo_bloque(uuid, boolean, boolean, text, uuid, uuid, date, uuid, timestamptz, timestamptz, uuid, uuid[], date) owner to postgres;
alter function private.bases_carga_seguimiento_cifras() owner to postgres;
alter function private.bases_carga_seguimiento_rol(uuid) owner to postgres;
alter function private.bases_carga_seguimiento_exigir_base(uuid, text, uuid) owner to postgres;
alter function private.bases_carga_seguimiento_filas(uuid[], date) owner to postgres;
alter function crm.seguimiento_bases() owner to postgres;
alter function crm.seguimiento_base(uuid) owner to postgres;
alter function crm.seguimiento_base_detalle(uuid, uuid, text) owner to postgres;
alter function private.base_gestion_reactivar_capital_core(uuid, uuid, uuid, text, numeric, text) owner to postgres;
alter function crm.reactivar_lead_base_v2(uuid, uuid, text, numeric, text) owner to postgres;
alter function private.base_gestion_intento_capital_core(uuid, uuid, uuid, text, text, timestamptz, numeric, text) owner to postgres;
alter function crm.registrar_intento_base_v2(uuid, uuid, text, text, timestamptz, numeric, text) owner to postgres;

revoke all on function private.bases_carga_estado_contacto(uuid, boolean, boolean, text, uuid, uuid, date, uuid, timestamptz, timestamptz, uuid, uuid[], date, boolean, boolean, boolean) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_reparto_motivo_bloque(uuid, boolean, boolean, text, uuid, uuid, date, uuid, timestamptz, timestamptz, uuid, uuid[], date) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_seguimiento_cifras() from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_seguimiento_rol(uuid) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_seguimiento_exigir_base(uuid, text, uuid) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_seguimiento_filas(uuid[], date) from public, anon, authenticated, service_role;
revoke all on function crm.seguimiento_bases() from public, anon, authenticated, service_role;
revoke all on function crm.seguimiento_base(uuid) from public, anon, authenticated, service_role;
revoke all on function crm.seguimiento_base_detalle(uuid, uuid, text) from public, anon, authenticated, service_role;
revoke all on function private.base_gestion_reactivar_capital_core(uuid, uuid, uuid, text, numeric, text) from public, anon, authenticated, service_role;
revoke all on function crm.reactivar_lead_base_v2(uuid, uuid, text, numeric, text) from public, anon, authenticated, service_role;
revoke all on function private.base_gestion_intento_capital_core(uuid, uuid, uuid, text, text, timestamptz, numeric, text) from public, anon, authenticated, service_role;
revoke all on function crm.registrar_intento_base_v2(uuid, uuid, text, text, timestamptz, numeric, text) from public, anon, authenticated, service_role;
grant execute on function crm.seguimiento_bases() to authenticated;
grant execute on function crm.seguimiento_base(uuid) to authenticated;
grant execute on function crm.seguimiento_base_detalle(uuid, uuid, text) to authenticated;
grant execute on function crm.reactivar_lead_base_v2(uuid, uuid, text, numeric, text) to authenticated;
grant execute on function crm.registrar_intento_base_v2(uuid, uuid, text, text, timestamptz, numeric, text) to authenticated;
-- crm.reactivar_lead_base(uuid,uuid,text), crm.registrar_intento_base(…), crm.base_gestion_resumen() y
-- crm.base_gestion_resumen_detalle(uuid,text) no se tocan; private.base_gestion_reactivar_core(uuid,uuid,uuid,text) y
-- private.base_gestion_intento_core(…) conservan su ACL ({postgres=X/postgres}). Las tres piezas de B9 reemplazadas conservan
-- dueño y ACL (CREATE OR REPLACE; {postgres=X/postgres}); el postflight lo comprueba.

-- ── 6 · Comentarios ────────────────────────────────────────────────────────────────────────────────────────────────────
comment on function crm.obtener_base_gestion(uuid, boolean) is 'Base para gestión (B3): leads descartados vivos del ámbito del actor (analista → los suyos; Supervisión → subárbol; Gerencia → todo), sin «no contactar» ni descanso vigente (salvo p_incluir_vetados, ver B6b), con intentos del ciclo, último resultado, próxima rellamada, etapa máxima alcanzada y quién gestiona. Orden: rellamada vencida o de hoy → etapa máxima → menos días desde el descarte. p_vendedor_id filtra un analista dentro del ámbito. DEFINER: ámbito explícito (espejo de leads_select), search_path vacío, EXECUTE solo authenticated. B3c (03/10/2026): sus conteos de intentos salen de private.base_gestion_intentos_ciclo; fuera del censo analítico. B5 (03/10/2026): devuelve al final recibido_en = coalesce(tenencia_desde, creado_en), cuándo le llegó el lead a quien lo tiene: el MES por el que se organiza el analista. B6b (03/10/2026, F4): p_incluir_vetados (default false; null = false) suma los leads «No contactar» del ámbito, también los que están en descanso; solo Supervisión y Gerencia (otro rol → 42501). Los vetados van al final y nunca en «Llamar hoy» (rellamada_hoy = false). Columnas finales no_contactar, no_contactar_en, no_contactar_motivo y no_contactar_por (nombre del autor): de la nota del evento vigente del veto — si la persona del lead (enlace, puente o DNI, como en marcar/levantar) está vetada, la última nota del veto entre los leads de la persona (private.leads_de_persona_veto ∪ el propio lead); si no, la del propio lead — solo si es un «marcar» (también el de postventa, motivo en el detalle) y su lead es visible para quien llama; si no, NULL. Residuo: empate exacto de clock_timestamp, desempate por id. B6c (04/10/2026, decisión de Miguel): la nota del veto (metadata evento = no_contactar) solo la escriben sus puertas (marcar_no_contactar, levantar_no_contactar y postventa_veto_fn, bajo crm.op_privilegiada; trigger trg_00_actividades_no_contactar_solo_puerta en crm.actividades): desde la API ya no se puede firmar el motivo, el autor ni la fecha de la marca, y la nota ya escrita no se cambia ni se borra. No acredita las notas anteriores a B6c (04/10/2026). Residuo (auditor-rls B6b, P3): esta función no lee la bandera resolver_en_puertas (encendida desde el 07/09/2026) y resuelve siempre la persona como las puertas con la bandera encendida; si se apagara, las puertas actuarían solo sobre el lead y la marca de un lead cuya persona siga vetada podría salir NULL o venir de otro lead de la persona (nunca de uno fuera del ámbito de quien llama). Con false, el resultado es el de B5. Envoltorios DEFINER en la base: crm.base_gestion_resumen y crm.base_gestion_resumen_detalle (re-auditarlos si cambia leads_select). B10 (04/10/2026, bases cargadas; r3): dos columnas finales, base_id y base_nombre (la base VIVA del lead —pertenencia y base activas—, solo si quien llama ve la base o es el analista del lead; si no, NULL), y fuera de la lista los DORMIDOS del archivo SIN REPARTIR de una base viva (procedencia archivo y estado sin_repartir de private.bases_carga_estado_contacto, la misma definición del seguimiento: disponibles, sin analista, sin veto ni movimientos ajenos; viven en la pestaña «Bases»). Un armado desde el CRM nunca se oculta: sigue en la lista de su analista anterior (E1). Un vetado nunca es sin repartir: sale en «Ver no contactar». El analista ve sus contactos de base repartidos como cualquier lead suyo. Lo demás, idéntico a B6b (el postflight de B10 lo compara con la foto previa).';
comment on function private.base_gestion_reactivar_capital_core(uuid, uuid, uuid, text, numeric, text) is
'Base para gestión (B3, D1/D2/D9; B10): la ÚNICA definición del núcleo de reactivar. Reabre por crm.reabrir_lead_fn (sellada; → nuevo, ciclo nuevo, SLA reiniciado, veto verificado), avanza a contactado en la misma transacción, sella reactivado_en y limpia rellamada y descanso; deja la actividad reactivacion_base con la respuesta (idempotencia por id = operación). B10 (04/10/2026, E8): si el lead NO tiene capital (contacto de base cargada), p_monto_estimado es obligatorio (NULL → 22023 «Indica el capital estimado para reactivar»; > 0, ≤ 9999999999.99 y hasta 2 decimales, si no 22023) y p_moneda opcional (NULL = la del lead; solo PEN o USD, si no 22023): se escriben en el lead ANTES de reabrir y el episodio de la reapertura nace con ese capital. Con capital ya puesto, los dos se ignoran. La llaman private.base_gestion_reactivar_core (sin capital), crm.reactivar_lead_base_v2 y private.base_gestion_intento_capital_core («agendó cita», con el capital del intento). Sin EXECUTE para la API.';
comment on function private.base_gestion_reactivar_core(uuid, uuid, uuid, text) is
'Base para gestión (B3, D1/D2/D9): reactivar SIN capital. Desde B10 (04/10/2026) es un envoltorio de private.base_gestion_reactivar_capital_core (la única definición del núcleo) con p_monto_estimado y p_moneda NULL: un lead sin capital → 22023 «Indica el capital estimado para reactivar». Se conserva la firma porque la nombran el gate (test-rls.mjs) y los scripts de B3. La llama la puerta publicada crm.reactivar_lead_base. Sin EXECUTE para la API.';
comment on function private.base_gestion_intento_capital_core(uuid, uuid, uuid, text, text, timestamptz, numeric, text) is
'Base para gestión (B3, D3/D7-bis/D10/D11; B10): la ÚNICA definición del núcleo de intentos. Registra un intento sobre un lead descartado del ámbito del actor (7 resultados; volver_a_llamar exige fecha futura ≤ dias_max_rellamada; descanso vigente y No contactar rechazan), escribe la actividad intento_base bajo los dos GUC, fija o limpia proxima_llamada_en y, con agendo_reunion, reactiva en la misma transacción por private.base_gestion_reactivar_capital_core con p_monto_estimado y p_moneda (B10, E8: obligatorio solo si el lead no tiene capital → 22023 «Indica el capital estimado para reactivar»; en otro resultado o con capital, se ignoran). Idempotente por id = operación (guarda la respuesta). El enfriamiento lo pone el trigger de B4. Sus conteos salen de private.base_gestion_intentos_ciclo (B3c; fuera del censo analítico). La llaman private.base_gestion_intento_core (sin capital) y crm.registrar_intento_base_v2. Sin EXECUTE para la API.';
comment on function private.base_gestion_intento_core(uuid, uuid, uuid, text, text, timestamptz) is
'Base para gestión (B3): registrar un intento SIN capital. Desde B10 (04/10/2026) es un envoltorio de private.base_gestion_intento_capital_core (la única definición del núcleo) con p_monto_estimado y p_moneda NULL: un «agendó cita» sobre un lead sin capital → 22023 «Indica el capital estimado para reactivar»; el resto, igual que antes. Se conserva la firma porque la nombra el gate (test-rls.mjs). La llama la puerta publicada crm.registrar_intento_base. Sin EXECUTE para la API.';
comment on function crm.registrar_intento_base_v2(uuid, uuid, text, text, timestamptz, numeric, text) is
'Bases cargadas (B10, 04/10/2026, E8): registrar un intento de la base para gestión pidiendo el capital cuando el resultado reactiva. Igual que crm.registrar_intento_base (B3: 7 resultados, volver_a_llamar con fecha futura ≤ 10 días, idempotente por p_operacion_id, «agendó cita» reactiva en la misma operación, D3) más p_monto_estimado y p_moneda: con agendo_reunion sobre un lead SIN capital, p_monto_estimado es OBLIGATORIO (NULL → 22023 «Indica el capital estimado para reactivar»; fuera de forma → 22023; p_moneda NULL conserva la del lead, solo PEN o USD); en cualquier otro caso se ignoran. Versionada (_v2): una sobrecarga con defaults junto a la publicada es ambigua (Postgres 42725). Misma respuesta que la publicada. DEFINER, search_path vacío, EXECUTE solo authenticated; delega en private.base_gestion_intento_capital_core.';
comment on function crm.reactivar_lead_base_v2(uuid, uuid, text, numeric, text) is
'Bases cargadas (B10, 04/10/2026, E8): reactivar un lead de la base pidiendo el capital si falta. Igual que crm.reactivar_lead_base (D1/D2/D9: al pipeline en contactado, mismo dueño, ciclo nuevo, reactivado_en y la línea en el historial; idempotente por p_operacion_id) más p_monto_estimado y p_moneda: si el lead no tiene capital, p_monto_estimado es OBLIGATORIO (NULL → 22023 «Indica el capital estimado para reactivar»; fuera de forma → 22023) y p_moneda NULL conserva la del lead (solo PEN o USD); con capital ya puesto, se ignoran. Versionada (_v2) porque una sobrecarga con defaults junto a la puerta publicada la rompe (Postgres 42725, PostgREST PGRST203; evidencia en el informe de B10). Errores: 42501 sin sesión o sin rol, P0002 fuera del ámbito, P0429 No contactar, 22023 entrada inválida o no descartado. DEFINER, search_path vacío, EXECUTE solo authenticated; delega en private.base_gestion_reactivar_capital_core.';
comment on function crm.seguimiento_bases() is
'Bases cargadas (B10, 04/10/2026; r1): una fila por base VIVA que el actor ve (Supervisión: las de su subárbol; Gerencia: todas; analista y otros roles → 42501) con total, sin_repartir (DISPONIBLES de verdad: sin analista, activos, sin veto, descartados y sin movimientos ajenos), repartidos, sin_tocar, trabajados (≥ 1 intento de la base desde el reparto), en_descanso, citas, reactivados, avance = trabajados / repartidos (0–1, siempre con 4 decimales; 0.0000 sin repartidos) y, al final (r1), movidos_otra_via, retirados y no_contactar (r3: sin con_analista_previo; un armado que conserva su analista anterior es sin_repartir, E1). Cada cifra se abre con crm.seguimiento_base_detalle (mismo arreglo de cifras: filas = cifra). Definiciones en private.bases_carga_seguimiento_filas. Más reciente primero. DEFINER (las tablas de bases no tienen grants), search_path vacío, EXECUTE solo authenticated; sin conteos sobre crm.leads (fuera del censo analítico).';
comment on function crm.seguimiento_base(uuid) is
'Bases cargadas (B10, 04/10/2026; r1): una fila por analista con contactos de la base: asignados, sin_tocar, sin_tocar_3_dias (E6: asignado hace ≥ 3 días de Lima y sin intento desde el reparto; la pantalla lo pinta en rojo), trabajados, en_descanso, citas, reactivados, ultimo_intento_en (desde el reparto), movidos_otra_via (E14) y, al final (r1), retirados y no_contactar. Base inexistente, retirada o fuera del ámbito → P0002; analista y otros roles → 42501. analista_id y nombre solo si el analista está en el ámbito del actor (si Gerencia repartió a otro equipo, la fila sale sin identificar y se abre por la base). r4 (Codex r2): TODOS los analistas fuera del ámbito van en UNA sola fila anónima (analista_id y analista_nombre NULL, cifras sumadas, ultimo_intento_en el máximo), la última; Gerencia nunca la tiene. Cada cifra se abre con crm.seguimiento_base_detalle. DEFINER, search_path vacío, EXECUTE solo authenticated.';
comment on function crm.seguimiento_base_detalle(uuid, uuid, text) is
'Bases cargadas (B10, 04/10/2026, «todo número se abre»): las filas detrás de una cifra de crm.seguimiento_bases (p_analista_id NULL) o de crm.seguimiento_base (p_analista_id = la fila). p_cifra: total, sin_repartir, repartidos, asignados, sin_tocar, sin_tocar_3_dias, trabajados, en_descanso, citas, reactivados, movidos_otra_via, retirados o no_contactar (private.bases_carga_seguimiento_cifras); otra, «avance» o NULL → 22023 (p_cifra lleva default NULL solo porque Postgres no admite un parámetro sin default después de p_analista_id; la pantalla llama por nombre). Base fuera del ámbito → P0002; analista sin contactos en la base → P0002; analista y otros roles → 42501. Filas = la cifra (el mismo arreglo de private.bases_carga_seguimiento_filas): lead_id y nombre solo si el actor ve el lead y sigue activo (private.bases_carga_lead_ref), si no NULL; estado, asignado_en, último intento y último resultado desde el reparto. r4 (Codex r2): un p_analista_id explícito tiene que estar en el ámbito del actor (private.vendedor_ids_visibles; Gerencia: cualquiera) —se mira ANTES que la pertenencia— y con contactos en la base; si no, P0002 «Analista no encontrado en esta base» en los dos casos. DEFINER, search_path vacío, EXECUTE solo authenticated.';
comment on function private.bases_carga_estado_contacto(uuid, boolean, boolean, text, uuid, uuid, date, uuid, timestamptz, timestamptz, uuid, uuid[], date, boolean, boolean, boolean) is
'Bases cargadas (B10 r2/r3, 04/10/2026; coordinador y Codex r1 P2): la ÚNICA definición del estado de un contacto de una base, para TODAS las puertas de B9 y B10 (seguimiento y detalle, crm.contactos_de_base, la exclusión de crm.obtener_base_gestion, el bloque y el individual de crm.repartir_base, crm.recoger_de_base). En orden: retirado (activo = false) · no_contactar (vetado) · movido_otra_via (con reparto: ya no es de su analista; sin reparto: fuera del ámbito del supervisor dueño —private.bases_carga_en_subarbol—, u otra vía le cambió el responsable desde que entró a la base —rastro reasignacion— salvo que hoy esté en la bandeja del dueño sin analista; y lo que salió del descarte sin cita ni reactivación de la base) · cita / reactivado (salió del descarte con un «agendó cita» / una reactivación de la base desde el reparto o, sin reparto, desde que entró a la base: private.bases_carga_reparto_hechos) · en_descanso (enfriado_hasta > hoy) · trabajado / sin_tocar (con reparto, con o sin intento desde asignado_en; sin reparto, trabajado = su analista anterior lo tiene en seguimiento activo B6) · sin_repartir (DISPONIBLE: sin reparto, activo, sin veto, descartado, sin descanso, en el ámbito del dueño, sin movimientos ajenos y sin seguimiento activo; r3, E1: también el armado que conserva su analista anterior). p_intento, p_cita y p_reactivado: los hechos de private.bases_carga_reparto_hechos(lead, coalesce(asignado_en, agregado_en)) si el llamador ya los tiene; NULL = los calcula. Un NULL nunca hace a un contacto «sin repartir». INVOKER, sin EXECUTE para la API.';
comment on function private.bases_carga_reparto_motivo_bloque(uuid, boolean, boolean, text, uuid, uuid, date, uuid, timestamptz, timestamptz, uuid, uuid[], date) is
'Bases cargadas (B10 r2, 04/10/2026): el reparto EN BLOQUE elige SOLO contactos en estado sin_repartir (private.bases_carga_estado_contacto): NULL = elegible; si no, el motivo para omitidos y para la revisión bajo candado: el de private.bases_carga_reparto_motivo (B9, evaluado para todo candidato) o, si ese no dice nada, el estado (movido_otra_via). Recibe la fila del lead y de su pertenencia (las MISMAS entradas que la definición única). La usa private.bases_carga_repartir_core en la foto, bajo candado y en omitidos. INVOKER, sin EXECUTE para la API.';
comment on function private.bases_carga_repartir_core(uuid, uuid, uuid, jsonb) is 'Bases cargadas (B9; r1): núcleo de crm.repartir_base. Orden: forma → idempotencia (recibo repartir, replay que revalida referencias) → base (visible, FOR UPDATE NOWAIT, viva, dueño activo) → analistas → bloque: foto sin candados de los sin repartir con su motivo y candado SKIP LOCKED SOLO de los que faltan, por tandas y en el orden del reparto; individual: ámbito (P0002) ANTES del candado SKIP LOCKED de lo pedido → revisión bajo candado con la misma definición y sin intento durante la operación → UPDATE de crm.leads por el camino de la casa → pertenencia → recibo. Sin count( ni sum(1) (censo). B10 r2 (04/10/2026): el bloque elige con private.bases_carga_reparto_motivo_bloque —solo el estado sin_repartir de private.bases_carga_estado_contacto, la definición única de B9 y B10; también el armado con su analista anterior, E1— en la foto, bajo candado y en omitidos; el individual añade el estado: lo movido por otra vía se rechaza (motivo movido_otra_via).';
comment on function private.bases_carga_contactos_core(uuid, uuid, text) is 'Bases cargadas (B9): núcleo de crm.contactos_de_base: base visible, solo contactos con private.bases_carga_lead_ref (visibles y activos), estado de private.bases_carga_estado_contacto (B10 r2/r3: la definición única de B9 y B10; el filtro, el de B9).';
comment on function private.bases_carga_reparto_recogible(uuid, uuid, timestamptz, boolean) is 'Bases cargadas (B9 r1): UNA definición de «se puede recoger»: vivo, descartado y en manos de ese analista (lo movido por otra vía no se deshace, E14), sin intento desde que se le repartió (salvo analista de baja: manda B6, que la baja libera) y sin seguimiento activo B6. La usan la foto y la revisión bajo candado de recoger. B10 r2 (04/10/2026): «sin intento» es el estado sin_tocar de private.bases_carga_estado_contacto (sin intento desde el reparto, sin veto ni descanso): recoger toma lo que el seguimiento muestra sin tocar.';
comment on function crm.repartir_base(uuid, uuid, jsonb) is 'Bases cargadas (B9, 04/10/2026): reparte contactos de una base a analistas, TODO O NADA. p_reparto: {"modo":"bloque","asignaciones":[{"analista_id","cantidad"}]} (el servidor elige los SIN REPARTIR más antiguos en la base y salta los que no se pueden repartir: retirados, fuera del ámbito del dueño, que salieron del descarte, No contactar, en descanso, en gestión B6 u ocupados; si no alcanzan → 22023 con detail = disponibles, el número en texto) o {"modo":"individual","asignaciones":[{"lead_id","analista_id"}]} (cada contacto de la base, visible para el actor —si no, P0002—, sin repartir o repartido a otro —se reasigna— y elegible; si no → 22023 con detail {"rechazados":[{lead_id, motivo}]}; tomado por otro proceso → 55P03; el que ya es de ese analista sale en omitidos como ya_asignado). Analista activo, rol vendedor, del subárbol del supervisor DUEÑO (Gerencia: cualquiera, y puede volver a repartir lo que B9 le dio a alguien fuera del equipo del dueño; fuera del equipo → P0002, inactivo o no analista → 22023). Bloquea solo lo necesario (r1). Efecto: crm.leads.vendedor_id = analista (sigue descartado; sin ciclo SLA ni episodio; la actividad «reasignación» y el candado B6 corren solos) y base_carga_leads.analista_id/asignado_en/asignado_por. Topes en private.bases_carga_reparto_constantes. Idempotente por (actor, p_operacion_id). Devuelve {ok, operacion_id, base_id, modo, repartidos, por_analista[{analista_id, cantidad}], omitidos[{lead_id|null, motivo, cantidad?}]} (en bloque, por motivo con lead_id null). Supervisión y Gerencia (otros → 42501); otra operación de la base en curso → 55P03. DEFINER, search_path vacío, lock_timeout 5 s, EXECUTE solo authenticated. B10 r2 (04/10/2026, una sola definición del estado): el bloque elige SOLO contactos en estado sin_repartir de private.bases_carga_estado_contacto —un armado que conserva su analista anterior es sin_repartir (E1) salvo que ese analista lo esté trabajando (B6); salta además lo movido por otra vía, que sale en omitidos con ese motivo—; el individual rechaza también lo movido por otra vía (motivo movido_otra_via).';
comment on function crm.recoger_de_base(uuid, uuid, uuid) is 'Bases cargadas (B9, 04/10/2026; r1): devuelve a «sin repartir» (bandeja del supervisor dueño de la base) los contactos que ese analista tiene de la base SIN intento desde que se le repartieron (de un analista de baja no se exige: manda B6, que la baja libera), sin seguimiento activo (B6) y que siguen descartados y en sus manos (lo movido por otra vía no se deshace, E14); los tomados por otro proceso quedan. Supervisión: analistas de su equipo (activos o no); Gerencia: cualquiera. Tope por operación (private.bases_carga_reparto_constantes): lo que excede queda en pendientes. Idempotente por (actor, p_operacion_id). Devuelve {ok, operacion_id, base_id, analista_id, recogidos, omitidos, pendientes}. DEFINER, search_path vacío, lock_timeout 5 s, EXECUTE solo authenticated. B10 r2 (04/10/2026): recoge lo que el seguimiento muestra «sin tocar» (estado sin_tocar de private.bases_carga_estado_contacto: sin intento desde el reparto, sin veto ni descanso) y sin seguimiento activo B6; de un analista de baja, todo lo suyo que siga descartado.';
comment on function crm.contactos_de_base(uuid, text) is 'Bases cargadas (B9, 04/10/2026): los contactos de una base visible para el actor (Supervisión: su subárbol; Gerencia: todas; si no, P0002; otros roles → 42501), para el reparto individual y la pestaña «Bases». p_estado: sin_repartir (por defecto) | repartidos | todos. Solo contactos que el actor ve y siguen activos (nada fuera de su ámbito). Lleva nombre, teléfono y distrito: la pantalla los usa para marcar filas en el reparto individual (el actor ya los ve en su Base para gestión). estado ∈ sin_repartir · sin_tocar · trabajado · en_descanso · cita · reactivado · movido_otra_via · no_contactar · retirado (B10 r2 (04/10/2026): private.bases_carga_estado_contacto, la misma definición del seguimiento de B10; un retirado no sale: solo contactos activos). Orden: el del reparto en bloque (más antiguos en la base primero). DEFINER, search_path vacío, EXECUTE solo authenticated.';
comment on function private.bases_carga_seguimiento_cifras() is
'Bases cargadas (B10; r1): los nombres de las cifras que se abren (columnas numéricas de crm.seguimiento_bases y crm.seguimiento_base, también retirados y no_contactar; «avance» es un cociente y se abre por trabajados). Sin EXECUTE para la API.';
comment on function private.bases_carga_seguimiento_rol(uuid) is
'Bases cargadas (B10): rol del actor para el seguimiento (private.rol_crm): solo supervisor o gerencia; si no (o sin sesión), 42501. Sin EXECUTE para la API.';
comment on function private.bases_carga_seguimiento_exigir_base(uuid, text, uuid) is
'Bases cargadas (B10): exige una base viva visible para el actor (private.bases_carga_base_visible, espejo de la policy bases_carga_select); NULL → 22023; inexistente, retirada o fuera del ámbito → P0002. Sin EXECUTE para la API.';
comment on function private.bases_carga_seguimiento_filas(uuid[], date) is
'Bases cargadas (B10; r2): una fila por contacto VIVO (pertenencia activa) de las bases pedidas con su estado —el de private.bases_carga_estado_contacto, la definición única de B9 y B10— y el arreglo cifras: total, sin_repartir, sin_tocar, en_descanso, movidos_otra_via, retirados y no_contactar (= su estado), repartidos y asignados (con analista), sin_tocar_3_dias (sin tocar y repartido hace ≥ 3 días de Lima, E6), trabajados, citas y reactivados (hechos de la base desde asignado_en, private.bases_carga_reparto_hechos de B9; solo repartidos). La ÚNICA definición de cada cifra: los conteos y el detalle leen ese arreglo. Sin agregados de conteo (censo). Sin EXECUTE para la API.';

-- ── 7 · Postflight (catálogo + identidad con B6b + envoltorios; sin DML) ──────────────────────────────────────────────
create temp table _b10_censo_despues on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;
-- Los dormidos sin repartir de esta instantánea que la lista de B6b mostraba (vivos y descartados): los únicos que la lista
-- nueva puede dejar fuera.
create temp table _b10_excluidos on commit drop as
  select l.id
    from crm.leads l
    join crm.base_carga_leads bl on bl.lead_id = l.id and bl.activo and bl.procedencia = 'archivo' and bl.analista_id is null
    join crm.bases_carga bc on bc.id = bl.base_id and bc.activo
    cross join lateral (select array(select private.bases_carga_subarbol(bc.supervisor_id)) as subarbol) s
   where l.activo and l.etapa = 'descartado'
     and private.bases_carga_estado_contacto(l.id, l.activo, l.no_contactar, l.etapa, l.vendedor_id, l.asignado_supervisor_id,
                                             l.enfriado_hasta, bl.analista_id, bl.asignado_en, bl.creado_en, bc.supervisor_id,
                                             s.subarbol, (now() at time zone 'America/Lima')::date) = 'sin_repartir';
do $postflight$
declare
  v_mal text;
  v_ger uuid;
  v_vend uuid;
  v_r record;
  v_b record;
  v_a record;
  v_cifra text;
  v_n bigint;
  v_primero boolean := true;
  v_excluidos bigint;
  v_filas bigint;
  v_sup uuid;
  v_x record;
begin
  -- 1. Funciones nuevas, reemplazadas y las que NO cambian: cuerpo, seguridad, volatilidad, search_path, dueño, ACL exacta y
  --    comentario.
  with esperado(firma, cuerpo, definer, volatil, acl) as (values
    ('private.bases_carga_estado_contacto(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date,boolean,boolean,boolean)', 'fa523b6c14624cc354813e3ab0343e10', false, 's', '{postgres=X/postgres}'),
    ('private.bases_carga_reparto_motivo_bloque(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date)', 'd63f4d40ae0ba60aa26df40cae341584', false, 's', '{postgres=X/postgres}'),
    ('private.bases_carga_contactos_core(uuid,uuid,text)', '3f179999beef647f81c70fcd411240b1', false, 's', '{postgres=X/postgres}'),
    ('private.bases_carga_reparto_recogible(uuid,uuid,timestamp with time zone,boolean)', 'b89a1f1141555c224d9ebf2c53b41bf4', false, 's', '{postgres=X/postgres}'),
    ('private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)', '6b934571b91796d43f8ce5e59d3ddae1', false, 'v', '{postgres=X/postgres}'),
    ('private.bases_carga_seguimiento_cifras()', '139e96a669b2ca914171c569443a7e37', false, 'i', '{postgres=X/postgres}'),
    ('private.bases_carga_seguimiento_rol(uuid)', 'd218e48c7125c3598a27cf1d41fe634a', false, 's', '{postgres=X/postgres}'),
    ('private.bases_carga_seguimiento_exigir_base(uuid,text,uuid)', '49e3cb435320fd2ed63054a5ab00e7d6', false, 's', '{postgres=X/postgres}'),
    ('private.bases_carga_seguimiento_filas(uuid[],date)', '0ee0a636d55527a01ade77b4a62760ab', false, 's', '{postgres=X/postgres}'),
    ('crm.seguimiento_bases()', '10ef60a15cded9e41ea8ccce998adff9', true, 's', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.seguimiento_base(uuid)', '79a76f53b0c21043627b6a149e4d4b4f', true, 's', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.seguimiento_base_detalle(uuid,uuid,text)', '8b1840fed8657e752514120f40b7b8e9', true, 's', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.obtener_base_gestion(uuid,boolean)', '26d887dc635824f383b0eb236c8226fb', true, 's', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)', '479683a99720d554ff419752f3da7876', true, 'v', '{postgres=X/postgres}'),
    ('private.base_gestion_reactivar_core(uuid,uuid,uuid,text)', '32eac0c4dc89d53524a1451d0f507799', true, 'v', '{postgres=X/postgres}'),
    ('crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)', '9037872b37d8a3d05d32b8a7a71b13e2', true, 'v', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.reactivar_lead_base(uuid,uuid,text)', 'bf59d77929877e7a5eb46704d934363e', true, 'v', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)', '98cd4edd8a3d7655f70a1a894d0e0b80', true, 'v', '{postgres=X/postgres}'),
    ('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)', '22db4f57842bbbc04b61f5d2eb641fb8', true, 'v', '{postgres=X/postgres}'),
    ('crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)', '40d26d67d052b71a2cc5d60b25e1b434', true, 'v', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.registrar_intento_base(uuid,uuid,text,text,timestamp with time zone)', 'd92c791fbe6f84e5d4f8ca39357b4721', true, 'v', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.base_gestion_resumen()', 'b773a7c49fbdfc45133b3405991b1958', true, 's', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.base_gestion_resumen_detalle(uuid,text)', '068372248be4127c80ba002542c9b4b8', true, 's', '{postgres=X/postgres,authenticated=X/postgres}'))
  select string_agg(e.firma, ', ' order by e.firma) into v_mal
    from esperado e
    left join pg_proc p on p.oid = to_regprocedure(e.firma)
   where (p.oid is not null and md5(p.prosrc) = e.cuerpo and p.prosecdef = e.definer and p.provolatile = e.volatil
          and p.proconfig = array['search_path=""']::text[] and p.proowner = 'postgres'::regrole
          and p.proacl is not null and p.proacl::text = e.acl
          and obj_description(p.oid, 'pg_proc') is not null) is not true;
  if v_mal is not null then
    raise exception 'POSTFLIGHT B10: funciones que no quedaron como se ensayaron: %', v_mal;
  end if;
  -- r2: B9 con la definición única. Sus tres puertas, intactas (cuerpo, DEFINER y ACL; el comentario dice r2); las tres
  -- piezas reemplazadas, con su comentario r2; el clasificador de B9 ya no existe y nadie nombra una definición vieja; la
  -- definición única la llaman EXACTAMENTE la lista, las filas del seguimiento, el motivo del bloque y las tres piezas de B9.
  if (
    (select count(*) from (values ('crm.repartir_base(uuid,uuid,jsonb)', 'fd7531ba7cd7cf8a259a389e2895ee2e'),
                                  ('crm.recoger_de_base(uuid,uuid,uuid)', '4744f70e69c0f70c22a6a295184e3095'),
                                  ('crm.contactos_de_base(uuid,text)', 'd528bab6930698d160f9635417a3ca7a')) x(firma, cuerpo)
       join pg_proc p on p.oid = to_regprocedure(x.firma)
      where md5(p.prosrc) = x.cuerpo and p.prosecdef and p.proowner = 'postgres'::regrole
        and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
        and obj_description(p.oid, 'pg_proc') like '%B10 r2 (04/10/2026%') = 3
    and (select count(*) from unnest(array['private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)', 'private.bases_carga_contactos_core(uuid,uuid,text)',
                                           'private.bases_carga_reparto_recogible(uuid,uuid,timestamp with time zone,boolean)']) f(firma)
          where obj_description(to_regprocedure(f.firma), 'pg_proc') like '%B10 r2%') = 3
    and to_regprocedure('private.bases_carga_reparto_estado(boolean,boolean,text,uuid,boolean,date,uuid,boolean,boolean,boolean,boolean,date)') is null
    and not exists (select 1 from pg_proc p where p.proname in ('bases_carga_reparto_estado', 'bases_carga_estado_sin_reparto'))
    and not exists (select 1 from pg_proc p where p.prosrc ~ 'bases_carga_reparto_estado|bases_carga_estado_sin_reparto')
    and (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text collate "C") from pg_proc p
          where p.prosrc ~ 'bases_carga_estado_contacto')
        = 'crm.obtener_base_gestion(uuid,boolean),private.bases_carga_contactos_core(uuid,uuid,text),private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb),'
          'private.bases_carga_reparto_motivo_bloque(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date),private.bases_carga_reparto_recogible(uuid,uuid,timestamp with time zone,boolean),'
          'private.bases_carga_seguimiento_filas(uuid[],date)'
    and (select count(*) from pg_proc p where p.pronamespace = 'private'::regnamespace
          and (p.proname like 'bases\_carga\_reparto\_%' or p.proname in ('bases_carga_repartir_core', 'bases_carga_recoger_core', 'bases_carga_contactos_core'))) = 10
  ) is not true then
    raise exception 'POSTFLIGHT B10: B9 no quedo con la definicion unica (puertas, piezas reemplazadas, clasificador borrado o llamadores)';
  end if;

  if (
    -- Una sola sobrecarga de cada puerta y de cada núcleo (el de 4 argumentos sigue con su firma).
    (select count(*) from pg_proc p where p.pronamespace = 'crm'::regnamespace
      and p.proname in ('obtener_base_gestion', 'reactivar_lead_base', 'reactivar_lead_base_v2', 'seguimiento_bases', 'seguimiento_base',
                        'seguimiento_base_detalle', 'registrar_intento_base', 'registrar_intento_base_v2')) = 8
    and (select count(*) from pg_proc p where p.pronamespace = 'private'::regnamespace
          and p.proname in ('base_gestion_reactivar_core', 'base_gestion_reactivar_capital_core', 'base_gestion_intento_core',
                            'base_gestion_intento_capital_core')) = 4
    -- La lista conserva sus 2 parámetros con default y termina en base_id, base_nombre; el núcleo, 6 con 2 defaults.
    and (select p.pronargs = 2 and p.pronargdefaults = 2 and p.proargnames[pg_catalog.array_length(p.proargnames, 1) - 1] = 'base_id'
                and p.proargnames[pg_catalog.array_length(p.proargnames, 1)] = 'base_nombre'
           from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid,boolean)'))
    and (select p.pronargs = 6 and p.pronargdefaults = 0 from pg_proc p
          where p.oid = to_regprocedure('private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)'))
    and (select p.pronargs = 8 and p.pronargdefaults = 0 from pg_proc p
          where p.oid = to_regprocedure('private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)'))
    and (select p.pronargs = 7 and p.pronargdefaults = 4 from pg_proc p
          where p.oid = to_regprocedure('crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)'))
    -- Permisos efectivos: las puertas solo para authenticated; el núcleo y los ayudantes, para nadie de la API.
    and not exists (select 1 from unnest(array['crm.seguimiento_bases()', 'crm.seguimiento_base(uuid)', 'crm.seguimiento_base_detalle(uuid,uuid,text)',
                                              'crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)', 'crm.obtener_base_gestion(uuid,boolean)',
                                              'crm.reactivar_lead_base(uuid,uuid,text)', 'crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)',
                                              'crm.registrar_intento_base(uuid,uuid,text,text,timestamp with time zone)']) f(firma)
                     where has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE')
                        or not has_function_privilege('authenticated', f.firma, 'EXECUTE'))
    and not exists (select 1 from unnest(array['private.bases_carga_estado_contacto(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date,boolean,boolean,boolean)',
                                              'private.bases_carga_reparto_motivo_bloque(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date)', 'private.bases_carga_seguimiento_cifras()',
                                              'private.bases_carga_seguimiento_rol(uuid)', 'private.bases_carga_seguimiento_exigir_base(uuid,text,uuid)',
                                              'private.bases_carga_seguimiento_filas(uuid[],date)',
                                              'private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)',
                                              'private.base_gestion_reactivar_core(uuid,uuid,uuid,text)',
                                              'private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)',
                                              'private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)']) f(firma)
                     cross join unnest(array['anon', 'authenticated', 'service_role']) r(rol)
                     where has_function_privilege(r.rol, f.firma, 'EXECUTE'))
    -- Consumidores de servidor: de la lista, el resumen y la detalle; del núcleo de reactivar de 4 argumentos, la puerta
    -- publicada; del de reactivar con capital, el de 4 argumentos, la _v2 y el núcleo de intentos con capital; del núcleo de
    -- intentos, la puerta publicada; del de intentos con capital, el envoltorio y su _v2 (el patrón '…_core' no casa con
    -- '…_capital_core').
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~ 'obtener_base_gestion'
                       and p.oid not in (to_regprocedure('crm.obtener_base_gestion(uuid,boolean)'), to_regprocedure('crm.base_gestion_resumen()'),
                                         to_regprocedure('crm.base_gestion_resumen_detalle(uuid,text)')))
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~ 'base_gestion_reactivar_core'
                       and p.oid not in (to_regprocedure('crm.reactivar_lead_base(uuid,uuid,text)'),
                                         to_regprocedure('private.bases_carga_reparto_hechos(uuid,timestamp with time zone)')))  -- B9: la nombra en un comentario, no la llama
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~ 'base_gestion_reactivar_capital_core'
                       and p.oid not in (to_regprocedure('private.base_gestion_reactivar_core(uuid,uuid,uuid,text)'),
                                         to_regprocedure('crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)'),
                                         to_regprocedure('private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)')))
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~ 'base_gestion_intento_core'
                       and p.oid not in (to_regprocedure('crm.registrar_intento_base(uuid,uuid,text,text,timestamp with time zone)'),
                                         to_regprocedure('private.bases_carga_reparto_hechos(uuid,timestamp with time zone)')))  -- B9: la nombra en un comentario, no la llama
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~ 'base_gestion_intento_capital_core'
                       and p.oid not in (to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)'),
                                         to_regprocedure('crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)')))
    -- Censo: ninguna nueva entra y es el de la foto.
    and not exists (select 1 from pg_temp._b10_censo_despues c
                     where c.objeto in ('crm.obtener_base_gestion(uuid,boolean)', 'crm.seguimiento_bases()', 'crm.seguimiento_base(uuid)',
                                        'crm.seguimiento_base_detalle(uuid,uuid,text)', 'private.bases_carga_seguimiento_filas(uuid[],date)',
                                        'private.bases_carga_estado_contacto(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date,boolean,boolean,boolean)',
                                        'private.bases_carga_reparto_motivo_bloque(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date)',
                                        'private.bases_carga_contactos_core(uuid,uuid,text)', 'private.bases_carga_reparto_recogible(uuid,uuid,timestamp with time zone,boolean)',
                                        'private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)',
                                        'private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)',
                                        'private.base_gestion_reactivar_core(uuid,uuid,uuid,text)',
                                        'private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)',
                                        'private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)',
                                        'crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)',
                                        'crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)'))
    and not exists (select 1 from pg_temp._b10_censo_despues c where c.objeto not in (select a.objeto from pg_temp._b10_censo_antes a))
    and (select count(*) from pg_temp._b10_censo_antes) = (select count(*) from pg_temp._b10_censo_despues)
  ) is not true then
    raise exception 'POSTFLIGHT B10: sobrecargas, firma, permisos efectivos, consumidores de servidor o el censo no quedaron como se ensayaron';
  end if;

  -- 2. Identidad con B6b como Gerencia (la de la foto): con false y con true, la lista nueva proyectada a las 26 columnas de
  --    B6b = la foto sin los dormidos sin repartir, en el mismo orden; base_id/base_nombre = la base VIVA del lead; ningún
  --    excluido en la lista; el resumen de F4 idéntico; la detalle de F4 da tantas filas como su cifra.
  select a.lead_id into v_ger from pg_temp._b10_lista_antes a where a.ord = 0;
  select count(*) into v_excluidos from pg_temp._b10_excluidos;
  if v_ger is not null then
    perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
    perform pg_catalog.set_config('request.jwt.claim.sub', v_ger::text, true);
    if exists (
      with esperado as (
        select a.modo, pg_catalog.row_number() over (partition by a.modo order by a.ord) as ord, a.fila
          from pg_temp._b10_lista_antes a
         where a.ord > 0 and a.lead_id not in (select x.id from pg_temp._b10_excluidos x)
      ),
      obtenido as (
        select m.modo, t.ordinality as ord,
               row(t.lead_id, t.nombre_completo, t.telefono, t.distrito, t.origen, t.categoria_interes, t.monto_estimado, t.moneda,
                   t.motivo_descarte, t.descartado_en, t.dias_desde_descarte, t.etapa_maxima, t.intentos, t.ultimo_resultado,
                   t.ultimo_intento_en, t.proxima_llamada_en, t.rellamada_hoy, t.enfriado_hasta, t.ciclo_n, t.vendedor_id, t.gestiona,
                   t.recibido_en, t.no_contactar, t.no_contactar_en, t.no_contactar_motivo, t.no_contactar_por)::text as fila
          from (values (false), (true)) m(modo)
          cross join lateral crm.obtener_base_gestion(null, m.modo) with ordinality t
      )
      (select * from esperado except all select * from obtenido)
      union all
      (select * from obtenido except all select * from esperado)
    ) then
      raise exception 'POSTFLIGHT B10: la lista no es la de B6b sin los dormidos sin repartir (mismas filas y orden)';
    end if;
    if exists (select 1 from crm.obtener_base_gestion(null, true) t
                 left join crm.base_carga_leads bl on bl.lead_id = t.lead_id and bl.activo
                 left join crm.bases_carga bc on bc.id = bl.base_id and bc.activo
                where t.base_id is distinct from bc.id or t.base_nombre is distinct from bc.nombre
                   or t.lead_id in (select x.id from pg_temp._b10_excluidos x)) then
      raise exception 'POSTFLIGHT B10: base_id/base_nombre no son la base viva del lead, o un dormido sin repartir sigue en la lista';
    end if;
    -- r4 (auditor-rls, hueco de pruebas): TODO contacto que la lista nueva oculta (estaba en la foto de B6b, con vetados, y ya
    -- no está) es un dormido del ARCHIVO de una base viva, sin analista de la base ni vendedor, en la bandeja del supervisor
    -- DUEÑO. Comprobado sobre la diferencia real de las dos listas, no con la definición.
    if exists (select 1 from pg_temp._b10_lista_antes a
                 join crm.leads l on l.id = a.lead_id
                 left join crm.base_carga_leads bl on bl.lead_id = l.id and bl.activo
                 left join crm.bases_carga bc on bc.id = bl.base_id and bc.activo
                where a.modo and a.ord > 0
                  and a.lead_id not in (select t.lead_id from crm.obtener_base_gestion(null, true) t)
                  and (bc.id is not null and bl.procedencia = 'archivo' and bl.analista_id is null and l.vendedor_id is null
                       and l.asignado_supervisor_id is not distinct from bc.supervisor_id) is not true) then
      raise exception 'POSTFLIGHT B10: la lista oculta un contacto que no es un dormido del archivo sin analista en la bandeja del dueno';
    end if;
    if exists ((select r.* from crm.base_gestion_resumen() r except all select a.* from pg_temp._b10_resumen_antes a)
               union all
               (select a.* from pg_temp._b10_resumen_antes a except all select r.* from crm.base_gestion_resumen() r)) then
      raise exception 'POSTFLIGHT B10: el resumen de F4 cambio';
    end if;
    for v_r in select r.vendedor_id, r.intentos_hoy, r.reactivaciones_mes from crm.base_gestion_resumen() r loop
      if v_primero or v_r.intentos_hoy > 0 or v_r.reactivaciones_mes > 0 then
        if ((select count(*) from crm.base_gestion_resumen_detalle(v_r.vendedor_id, 'intentos_hoy')) = v_r.intentos_hoy
            and (select count(*) from crm.base_gestion_resumen_detalle(v_r.vendedor_id, 'reactivaciones_mes')) = v_r.reactivaciones_mes) is not true then
          raise exception 'POSTFLIGHT B10: la detalle de F4 no da tantas filas como su cifra para el analista %', v_r.vendedor_id;
        end if;
        v_primero := false;
      end if;
    end loop;
    -- 3. El seguimiento se ejecuta (compila sus ramas) y cuadra en la base más reciente, si hay: cada cifra = su detalle y la
    --    suma por analista = la cifra de la base. Sin bases: P0002 con una base inexistente y 22023 con una cifra inválida.
    select count(*) into v_filas from crm.seguimiento_bases();
    for v_b in select s.* from crm.seguimiento_bases() s order by s.creado_en desc limit 1 loop
      foreach v_cifra in array array['total', 'sin_repartir', 'repartidos', 'sin_tocar', 'trabajados', 'en_descanso', 'citas', 'reactivados',
                                     'movidos_otra_via', 'retirados', 'no_contactar'] loop
        select count(*) into v_n from crm.seguimiento_base_detalle(v_b.base_id, null, v_cifra);
        if v_n is distinct from (pg_catalog.to_jsonb(v_b) ->> v_cifra)::bigint then
          raise exception 'POSTFLIGHT B10: la cifra % de la base % no es su detalle (% filas)', v_cifra, v_b.base_id, v_n;
        end if;
      end loop;
      if exists (select 1 from (select coalesce(sum(s.asignados), 0) a, coalesce(sum(s.sin_tocar), 0) st, coalesce(sum(s.trabajados), 0) t,
                                       coalesce(sum(s.en_descanso), 0) d, coalesce(sum(s.citas), 0) c, coalesce(sum(s.reactivados), 0) r
                                  from crm.seguimiento_base(v_b.base_id) s) q
                  where (q.a, q.st, q.t, q.c, q.r) is distinct from (v_b.repartidos::bigint, v_b.sin_tocar::bigint, v_b.trabajados::bigint,
                                                                    v_b.citas::bigint, v_b.reactivados::bigint)
                     or q.d > v_b.en_descanso) then  -- r2: en descanso de la base cuenta también lo SIN reparto
        raise exception 'POSTFLIGHT B10: la suma por analista no es la cifra de la base %', v_b.base_id;
      end if;
      for v_a in select s.* from crm.seguimiento_base(v_b.base_id) s limit 1 loop
        foreach v_cifra in array array['asignados', 'sin_tocar', 'sin_tocar_3_dias', 'trabajados', 'en_descanso', 'citas', 'reactivados', 'movidos_otra_via',
                                       'retirados', 'no_contactar'] loop
          select count(*) into v_n from crm.seguimiento_base_detalle(v_b.base_id, v_a.analista_id, v_cifra);
          if v_n is distinct from (pg_catalog.to_jsonb(v_a) ->> v_cifra)::bigint then
            raise exception 'POSTFLIGHT B10: la cifra % del analista % no es su detalle (% filas)', v_cifra, v_a.analista_id, v_n;
          end if;
        end loop;
      end loop;
    end loop;
    -- r4 (Codex r2): la misma base como su supervisor DUEÑO (si está activo): a lo sumo UNA fila anónima, la suma de sus filas =
    -- la base, cada analista suyo = su detalle, y un analista fuera de su ámbito, pedido explícitamente → P0002 (mismo mensaje).
    for v_b in select s.* from crm.seguimiento_bases() s order by s.creado_en desc limit 1 loop
      select b.supervisor_id into v_sup from crm.bases_carga b where b.id = v_b.base_id;
      if private.rol_crm(v_sup) = 'supervisor' then
        perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_sup, 'role', 'authenticated')::text, true);
        perform pg_catalog.set_config('request.jwt.claim.sub', v_sup::text, true);
        if (select count(*) from crm.seguimiento_base(v_b.base_id) s where s.analista_id is null) > 1
           or exists (select 1 from (select coalesce(sum(s.asignados), 0) a, coalesce(sum(s.sin_tocar), 0) st, coalesce(sum(s.trabajados), 0) t,
                                            coalesce(sum(s.citas), 0) c, coalesce(sum(s.reactivados), 0) r
                                       from crm.seguimiento_base(v_b.base_id) s) q
                       join crm.seguimiento_bases() sb on sb.base_id = v_b.base_id
                      where (q.a, q.st, q.t, q.c, q.r) is distinct from (sb.repartidos::bigint, sb.sin_tocar::bigint, sb.trabajados::bigint,
                                                                        sb.citas::bigint, sb.reactivados::bigint)) then
          raise exception 'POSTFLIGHT B10: el supervisor de la base % ve mas de una fila anonima o la suma de sus filas no es la base', v_b.base_id;
        end if;
        for v_a in select s.* from crm.seguimiento_base(v_b.base_id) s where s.analista_id is not null loop
          foreach v_cifra in array array['asignados', 'sin_tocar', 'trabajados', 'citas', 'reactivados'] loop
            select count(*) into v_n from crm.seguimiento_base_detalle(v_b.base_id, v_a.analista_id, v_cifra);
            if v_n is distinct from (pg_catalog.to_jsonb(v_a) ->> v_cifra)::bigint then
              raise exception 'POSTFLIGHT B10: la cifra % del analista % (supervisor) no es su detalle', v_cifra, v_a.analista_id;
            end if;
          end loop;
        end loop;
        for v_x in select distinct bl.analista_id from crm.base_carga_leads bl
                    where bl.base_id = v_b.base_id and bl.activo and bl.analista_id is not null
                      and bl.analista_id not in (select private.vendedor_ids_visibles(v_sup)) loop
          begin
            perform 1 from crm.seguimiento_base_detalle(v_b.base_id, v_x.analista_id, 'asignados');
            raise exception 'POSTFLIGHT B10: un analista fuera del ambito del supervisor se pudo abrir' using errcode = 'P0001';
          exception when no_data_found then
            if sqlerrm <> 'Analista no encontrado en esta base' then
              raise exception 'POSTFLIGHT B10: el analista externo dio otro mensaje: %', sqlerrm using errcode = 'P0001';
            end if;
          end;
        end loop;
        perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
        perform pg_catalog.set_config('request.jwt.claim.sub', v_ger::text, true);
      end if;
    end loop;
    begin
      perform 1 from crm.seguimiento_base(gen_random_uuid());
      raise exception 'POSTFLIGHT B10: una base inexistente no dio P0002' using errcode = 'P0001';
    exception when no_data_found then
      null;
    end;
    begin
      perform 1 from crm.seguimiento_base_detalle(gen_random_uuid(), null, 'avance');
      raise exception 'POSTFLIGHT B10: la cifra avance no dio 22023' using errcode = 'P0001';
    exception when invalid_parameter_value then
      null;
    end;
    perform pg_catalog.set_config('request.jwt.claims', '', true);
    perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
  end if;

  -- 4. Un analista no ve el seguimiento (42501, sin escribir).
  select e.perfil_id into v_vend from crm.equipo e
   where e.activo and private.rol_crm(e.perfil_id) = 'vendedor' order by e.perfil_id limit 1;
  if v_vend is not null then
    begin
      perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_vend, 'role', 'authenticated')::text, true);
      perform pg_catalog.set_config('request.jwt.claim.sub', v_vend::text, true);
      perform 1 from crm.seguimiento_bases();
      raise exception 'POSTFLIGHT B10: un analista pudo ver el seguimiento' using errcode = 'P0001';
    exception when insufficient_privilege then
      if sqlerrm <> 'Solo Supervisión y Gerencia ven el seguimiento de las bases' then
        raise exception 'POSTFLIGHT B10: el analista fue rechazado por otro motivo: %', sqlerrm using errcode = 'P0001';
      end if;
    end;
    perform pg_catalog.set_config('request.jwt.claims', '', true);
    perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
  end if;

  raise notice 'B10 CATALOGO OK: definicion unica del estado (private.bases_carga_estado_contacto) en B9 y B10, B9 r2 con su nucleo reemplazado y sus puertas intactas, 3 puertas de seguimiento, reactivar_lead_base_v2 y registrar_intento_base_v2 (EXECUTE solo authenticated), nucleos con capital y los de siempre como envoltorios (misma firma y ACL), puertas publicadas intactas, lista = B6b sin % dormidos sin repartir (% bases vivas visibles para Gerencia), resumen y detalle de F4 cuadran, censo igual. COMPORTAMIENTO CON ESCRITURAS NO PROBADO en esta migracion.',
    v_excluidos, coalesce(v_filas::text, 'sin foto');
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
-- Soltar la exclusión de migraciones (candado de SESIÓN tomado antes de la instantánea).
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
$mig$])) then
    raise exception 'REGISTRO: la versión 20261004223253 ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261004223253', 'crm_bases_cargadas_seguimiento', array[$mig$-- 20261004223253_crm_bases_cargadas_seguimiento.sql
--
-- Bases cargadas · B10: seguimiento de las bases, la base en la lista del analista y el capital al reactivar. Contrato FIJO
-- `BASE PARA GESTION/BASES-CARGADAS-CONTRATO.md` (§B10) y decisiones E1–E14 (`BASES-CARGADAS.md`; E6: sin tocar 3 días = rojo,
-- nada se mueve solo; E8: el capital se pide al reactivar; E14: las otras vías no se bloquean, se ven como «movido por otra
-- vía»), sobre B7 (20261004160034), B8 (20261004184501) y B9 (20261004222602, r2: repartir y recoger), que va ANTES.
-- r2 (04/10/2026, coordinador; «prevenir antes que vigilar»): UNA sola definición del estado de un contacto de base —y de
--   «sin repartir»— para las puertas de B9 y de B10: private.bases_carga_estado_contacto. B10 reemplaza (CREATE OR REPLACE:
--   misma firma, dueño, seguridad y ACL) las tres piezas del núcleo de B9 que clasificaban por su cuenta —
--   private.bases_carga_contactos_core (estado y filtro «sin_repartir» de crm.contactos_de_base),
--   private.bases_carga_repartir_core (el bloque elige SOLO el estado sin_repartir; el individual rechaza además lo movido
--   por otra vía) y private.bases_carga_reparto_recogible (recoger = el estado sin_tocar que muestra el seguimiento)— y BORRA
--   el clasificador de B9 (private.bases_carga_reparto_estado): no queda una segunda definición. Las tres puertas de B9
--   (crm.repartir_base, crm.recoger_de_base, crm.contactos_de_base) conservan cuerpo, firma y ACL; cambia su comentario. Un
--   contacto retirado, vetado, movido, en descanso o en seguimiento activo NUNCA es «sin repartir» en ninguna puerta y el
--   bloque nunca lo elige. El preflight exige las huellas EXACTAS de B9 r2 y la reversa deja B9 tal cual estaba.
-- r3 (04/10/2026, coordinador: manda E1 de Miguel, «las dos entradas terminan en el mismo reparto»): un armado desde el CRM
--   que conserva su analista anterior es «sin repartir» como cualquier otro y el bloque lo elige (B9 ya lo hacía); si ese
--   analista lo está trabajando (seguimiento activo B6), «trabajado» y no se reparte. Sin el estado con_analista_previo, su
--   columna ni su cifra. La lista de la base para gestión oculta SOLO a los DORMIDOS del archivo sin repartir (procedencia
--   archivo): un armado nunca se oculta.
-- r4 (04/10/2026, Codex r2, 2 P2): crm.seguimiento_base agrega a TODOS los analistas fuera del ámbito del actor en UNA sola
--   fila anónima (analista_id y analista_nombre NULL, cifras sumadas, ultimo_intento_en = el máximo; Gerencia nunca la tiene):
--   dos externos ya no salen como dos filas indistinguibles, y la fila anónima no se abre por analista (la pantalla la pinta
--   «Analista de otro equipo» y la abre por la base). crm.seguimiento_base_detalle con un p_analista_id explícito exige que
--   el analista esté en el ámbito del actor (private.vendedor_ids_visibles; Gerencia: cualquiera) ANTES de mirar la
--   pertenencia, y si no responde P0002 con el MISMO mensaje que «sin contactos en la base»: conocer un UUID externo no
--   permite atribuirle cifras ni saber si tiene contactos. p_analista_id NULL sigue siendo toda la base (los externos, sin
--   lead_id ni nombre).
-- RECOGER, CAMBIO INTENCIONAL (Codex r2, riesgo): con B10, crm.recoger_de_base se lleva solo lo «sin tocar» de la definición
--   única (sin intento desde el reparto, sin veto y sin descanso) de un analista ACTIVO; B9 r2 se llevaba también sus vetados y
--   sus contactos en descanso sin intento. Así «Recoger» toma exactamente lo que el seguimiento muestra «sin tocar» (en rojo a
--   los 3 días, E6). Un vetado o uno en descanso se queda con su analista y cuenta en no_contactar / en_descanso; de un
--   analista DE BAJA se recoge todo lo suyo que siga descartado, como en B9. La reversa vuelve a la regla de B9.
--
-- QUÉ HACE
--   1. Seguimiento (tres puertas de LECTURA, DEFINER: las tablas de bases no tienen grants):
--      · crm.seguimiento_bases() — una fila por base VIVA que el actor ve (Supervisión: las de su subárbol; Gerencia: todas;
--        espejo de la policy bases_carga_select = private.bases_carga_base_visible de B8). Analista, coordinación y cualquier
--        otro rol → 42501. avance = trabajados / repartidos (0.0000 si no hay repartidos), siempre con 4 decimales.
--      · crm.seguimiento_base(p_base_id) — una fila por analista con contactos de la base. Base inexistente, retirada o fuera
--        del ámbito → P0002 (sin delatar si existe).
--      · crm.seguimiento_base_detalle(p_base_id, p_analista_id, p_cifra) — las filas detrás de CUALQUIER cifra de las dos de
--        arriba (todo número se abre). p_cifra ∈ private.bases_carga_seguimiento_cifras(); otra (también «avance», que es un
--        cociente: se abre por «trabajados») o NULL → 22023. p_analista_id NULL = toda la base; uno que no tiene contactos en
--        la base → P0002. ⚠ El contrato escribe `p_analista_id uuid default null, p_cifra text`: Postgres NO admite un
--        parámetro sin default después de uno con default; p_cifra lleva `default null` (NULL → 22023). PostgREST llama por
--        NOMBRE, así que el contrato de la pantalla ({p_base_id, p_analista_id?, p_cifra}) no cambia.
--      UNA definición de cada cifra: private.bases_carga_seguimiento_filas devuelve, por contacto VIVO de la base
--      (pertenencia activa), su estado y el arreglo `cifras` con los nombres de columna a los que pertenece; los conteos
--      (count(*) filter (where '<cifra>' = any(cifras))) y el detalle (where p_cifra = any(cifras)) leen ese MISMO arreglo:
--      filas del detalle = cifra por construcción (y la suite lo comprueba con valores contados a mano).
--      ESTADO (uno por contacto): private.bases_carga_estado_contacto, la ÚNICA definición; la usan TODAS las puertas de B9 y
--      B10 (seguimiento y detalle, crm.contactos_de_base, la exclusión de la lista, el bloque y el individual de repartir,
--      recoger). En este orden:
--        retirado              activo = false;
--        no_contactar          vetado;
--        movido_otra_via       con reparto: ya no es de su analista (E14); sin reparto: fuera del ámbito del supervisor DUEÑO
--                              (su analista o su bandeja en el subárbol, private.bases_carga_en_subarbol de B8), u otra vía
--                              le cambió el responsable desde que entró a la base (rastro `reasignacion` de
--                              trg_leads_reasignacion, que la API no puede escribir: actividades_insert lo excluye) salvo
--                              que hoy esté en la bandeja del dueño sin analista (recogido); y el que salió del descarte sin
--                              cita ni reactivación de la base;
--        cita / reactivado     salió del descarte con un «agendó cita» / una reactivación de la base desde asignado_en o, sin
--                              reparto, desde que entró a la base (private.bases_carga_reparto_hechos de B9);
--        en_descanso           enfriado_hasta > hoy;
--        trabajado / sin_tocar con reparto: ≥ 1 intento de la base desde asignado_en / ninguno; sin reparto, «trabajado» =
--                              su analista anterior (armado desde el CRM) lo tiene en seguimiento activo B6 (como en B9);
--        sin_repartir          DISPONIBLE: sin reparto, activo, sin veto, descartado, sin descanso, en el ámbito del dueño,
--                              sin movimientos ajenos (Codex r1, P2) y sin seguimiento activo. r3 (E1): también el armado
--                              que conserva su analista anterior (E13: armar no toca el lead). Es lo ÚNICO que el bloque
--                              elige; de la lista de la base para gestión sale solo si además vino del archivo (dormido).
--      CIFRAS: total · sin_repartir / sin_tocar / en_descanso / movidos_otra_via / retirados /
--        no_contactar (= su estado) · repartidos = asignados (con analista) · sin_tocar_3_dias (sin_tocar y repartido hace ≥ 3
--        días de Lima, E6: rojo) · trabajados / citas / reactivados (hechos de la base DESDE asignado_en, solo repartidos: ≥ 1
--        intento, un «agendó cita», una reactivación). avance = trabajados / repartidos. Por analista, lo mismo sobre sus
--        repartidos: la suma por analista = la base en repartidos, sin_tocar, trabajados, citas y reactivados.
--      Identidades: el detalle devuelve lead_id y nombre SOLO si el actor ve el lead y sigue activo
--      (private.bases_carga_lead_ref de B8, espejo de leads_select; si no, NULL: cuenta en su cifra sin delatar quién es).
--      seguimiento_base devuelve analista_id y nombre solo si el analista está en el ámbito del actor (auditor-rls r1, P3;
--      private.vendedor_ids_visibles; Gerencia: todos): una fila de otro equipo sale sin identificar y se abre por la base.
--   2. crm.obtener_base_gestion(uuid, boolean): MISMA firma, drop + create con el texto VIVO de B6b (20261004045038, md5
--      36af7e9c…) y SOLO estos cambios: (a) dos columnas AL FINAL, base_id y base_nombre (la base VIVA del lead: pertenencia
--      y base activas; NULL si no está en una; y solo si el actor ve la BASE —private.bases_carga_base_visible— o es el
--      analista del lead: auditor-rls r1, P3); (b) fuera de la lista los contactos SIN REPARTIR de una base viva (el estado
--      sin_repartir de private.bases_carga_estado_contacto —la MISMA definición del seguimiento y de B9— de los contactos que
--      vinieron del ARCHIVO (procedencia archivo: los dormidos; r3: un armado desde el CRM nunca se oculta): viven en la pestaña
--      «Bases»; hasta F5 nadie los ve en «Gestión de la base»). Un vetado nunca es «sin repartir»: con
--      p_incluir_vetados sale en «Ver no contactar» (auditor-rls r1, P3). Un lead tiene a lo sumo UNA pertenencia viva (índice único
--      base_carga_leads_lead_vivo_unico): el LEFT JOIN no duplica filas. Lo demás —filtros, intentos, etapa máxima, marca
--      del veto, orden— IDÉNTICO: el postflight compara, como Gerencia y con false y con true, la lista nueva proyectada a
--      las 26 columnas de B6b con la foto tomada en esta misma transacción ANTES del drop, sin las filas excluidas y en el
--      mismo orden (con datos sin bases: la lista de B6b exacta). El analista ve sus contactos de base repartidos como
--      cualquier lead suyo (vendedor_id = él, descartado): mismas reglas de intentos, rellamada y descanso.
--      Envoltorios DEFINER (memoria «envoltorio DEFINER se salta la RLS»): crm.base_gestion_resumen (cuenta por DUEÑO: los
--      excluidos no tienen dueño, sus cifras no cambian; el postflight lo compara) y crm.base_gestion_resumen_detalle
--      (sigue_en_base pide la lista de UN analista: los excluidos nunca están ahí). Ninguno cambia; el preflight fija que
--      son los ÚNICOS consumidores de servidor y el postflight vuelve a cuadrar cifra = detalle.
--   3. Capital al reactivar (E8). DECISIÓN CON EVIDENCIA (banco B10, 04/10; medido y transcrito en el informe de B10): una sobrecarga
--      `crm.reactivar_lead_base(uuid,uuid,text,numeric default null,text default null)` junto a la vieja ROMPE la llamada
--      publicada: Postgres → 42725 «is not unique» (también con argumentos por nombre) y PostgREST 16.2 → PGRST203 «Could
--      not choose the best candidate function» para {p_operacion_id, p_lead_id[, p_nota]}, que es lo que manda el front vivo
--      (73c9b908, app/src/data/crm-api.ts:1853). Sin defaults en la nueva, PostgREST solo la elige si llegan las 5 claves
--      (con 3 → PGRST202). Por eso se VERSIONA (regla de la casa, CLAUDE.md capa 3):
--      · crm.reactivar_lead_base_v2(p_operacion_id, p_lead_id, p_nota default null, p_monto_estimado default null,
--        p_moneda default null) — la del front nuevo (F6);
--      · crm.reactivar_lead_base(uuid,uuid,text) — la publicada, con su cuerpo y su ACL INTACTOS (md5 bf59d779…): sigue
--        llamando al núcleo con 4 argumentos;
--      · NUEVA private.base_gestion_reactivar_capital_core(actor, operación, lead, nota, p_monto_estimado, p_moneda): la
--        ÚNICA definición del núcleo = el texto vivo de private.base_gestion_reactivar_core (B3c, md5 c7e19f14…) con UN bloque
--        nuevo antes de reabrir: si el lead NO tiene capital → p_monto_estimado obligatorio (NULL → 22023 «Indica el capital
--        estimado para reactivar»; fuera de forma → 22023), p_moneda NULL = la que ya tiene el lead, otra que no sea PEN/USD →
--        22023; se escribe en el lead ANTES de reabrir (el CHECK leads_monto_estimado_valido rechazaría la reapertura) y el
--        episodio que abre la reapertura nace con ese capital. Con capital ya puesto, los dos parámetros se IGNORAN. r1 (Codex,
--        riesgo): el capital pedido es parte de la identidad de la operación (mismo p_operacion_id con otro capital o moneda →
--        23505 «otro contenido», como el intento con otra nota) y la respuesta AÑADE monto_estimado y moneda (el capital
--        EFECTIVO del lead tras la operación) y solicitud_monto / solicitud_moneda (claves nuevas: el front publicado valida
--        con v.looseObject, las ignora);
--      · private.base_gestion_reactivar_core(uuid,uuid,uuid,text): MISMA firma (CREATE OR REPLACE), ahora envoltorio de una
--        línea del núcleo nuevo sin capital. POR QUÉ no se borra (medido en el banco B10, 04/10): el gate
--        supabase/scripts/test-rls.mjs:15539 —y su copia en cualquier rama abierta, p. ej. la de B9— nombra esa firma exacta;
--        sin ella el gate aborta entero («function … does not exist»). La puerta publicada y el intento «agendó cita» la
--        siguen llamando sin cambiar su texto.
--      · «Agendó cita» (registrar_intento_base con agendo_reunion) REACTIVA en la misma transacción (D3): misma regla. NUEVA
--        private.base_gestion_intento_capital_core(…, p_monto_estimado, p_moneda) = el texto vivo de
--        private.base_gestion_intento_core (B3c, md5 db8ba2b4…) con UN cambio: reactiva por el núcleo con capital pasándole
--        p_monto_estimado y p_moneda (obligatorio solo si el resultado reactiva y el lead no tiene capital: 22023; en
--        cualquier otro caso se ignoran; r1: también en la identidad de la operación y la respuesta trae el capital efectivo).
--        private.base_gestion_intento_core(…6…) conserva su firma (también la nombra el gate,
--        test-rls.mjs:15539) como envoltorio sin capital, y NUEVA crm.registrar_intento_base_v2(p_operacion_id, p_lead_id,
--        p_resultado, p_nota default null, p_proxima_llamada default null, p_monto_estimado default null, p_moneda default
--        null) para el front nuevo (una sobrecarga de registrar_intento_base con defaults también es ambigua: medido, 42725).
--        crm.registrar_intento_base (la publicada) no cambia.
--      Consecuencias: la puerta vieja de reactivar, o la de intentos con «agendó cita», sobre un lead sin capital da 22023
--      «Indica el capital estimado para reactivar» (antes, 23514 del CHECK); un intento normal sin capital, igual que hoy.
--      Las puertas viejas se retiran cuando F6 esté publicada (paso aparte).
-- QUÉ NO CAMBIA: tablas, policies, grants de crm.leads, disparadores, B8, crm.base_gestion_resumen,
--   crm.base_gestion_resumen_detalle, crm.reactivar_lead_base, crm.registrar_intento_base, y la FIRMA (con su ACL) de todo
--   objeto existente: solo cambian el cuerpo de obtener_base_gestion (drop + create, misma firma y ACL) y el cuerpo y el
--   comentario de private.base_gestion_reactivar_core y private.base_gestion_intento_core (CREATE OR REPLACE); y, de B9 r2,
--   el cuerpo y el comentario de tres piezas de su núcleo, el comentario de sus tres puertas y el clasificador borrado (arriba).
-- CENSO: las funciones que cuentan (count(*) filter) no nombran crm.leads ni «reunion»; la que nombra crm.leads
--   (private.bases_carga_seguimiento_filas) no cuenta. El postflight exige el censo igual a la foto previa y ninguna nueva en él.
-- CANDADOS (Codex r1, P2): la exclusión de migraciones (candado consultivo de la casa crm_migracion_funciones) se toma ANTES
--   de fijar la instantánea: en una transacción PREVIA del mismo mensaje y a nivel de SESIÓN (pg_advisory_lock), y se suelta
--   al final (pg_advisory_unlock). En REPEATABLE READ la instantánea se fija en la primera consulta: si el candado se pedía
--   dentro (r0), una espera dejaba al preflight leyendo el catálogo de ANTES de la otra migración (reproducido en el banco con
--   dos sesiones: r0 se aplicaba sobre un ayudante cambiado; r1 se niega). El preflight exige además que ESTA sesión tenga el
--   candado (pg_locks; un pooler en modo transacción lo haría fallar cerrado). Si la migración falla, el resto del mensaje no
--   corre y el candado se suelta al cerrar la sesión (db query --linked --file y psql -c cierran al terminar). Sin candados
--   de tabla: B10 no cambia ninguna tabla. CONSISTENCIA: la transacción principal va en REPEATABLE READ (su primera
--   sentencia): la foto previa y el postflight ven la MISMA instantánea aunque otra sesión registre intentos o reparta.
-- SIN DML: el postflight solo lee (catálogo, la lista, el resumen, el detalle y el seguimiento como Gerencia con claims
--   locales). El comportamiento con escrituras se prueba después con supabase/scripts/base-gestion/b10-seguimiento.sql
--   (banco) y b10-comprobar-tras-aplicar.sql (rama/producción, ROLLBACK).
-- PRECONDICIÓN: B8 y B9 r2 aplicadas (B9 con sus huellas exactas: cuerpo, identidad, ACL y comentario); obtener_base_gestion = B6b (+ comentario de B6c), el núcleo de reactivar y su puerta los de
--   B3c, y los ayudantes de los que depende, con la identidad ensayada (preflight).
-- REVERSA: supabase/scripts/base-gestion/reversa-b10.sql (solo huellas propias; foto antes/después de lo ajeno; deja B9
--   tal cual estaba: sus tres piezas del núcleo, su clasificador y los comentarios de sus puertas, byte a byte). Si F6 ya
--   llama a reactivar_lead_base_v2 o a las puertas de seguimiento, revertir la deja en «disponible pronto» (PGRST202).
-- Exclusión de migraciones ANTES de la instantánea (Codex r1, P2): candado de SESIÓN en su propia transacción.
begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

begin;
-- Una sola instantánea para la foto y el postflight (B6b, Codex r1 P2). Tiene que ir ANTES de cualquier consulta.
set transaction isolation level repeatable read;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $preflight$
begin
  if (
    -- Esta sesión tiene el candado de migraciones (tomado ANTES de la instantánea); pg_locks no es MVCC: es el estado de hoy.
    exists (select 1 from pg_locks l
             where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.granted and l.mode = 'ExclusiveLock' and l.objsubid = 1
               and ((l.classid::bigint << 32) | l.objid::bigint) = hashtext('crm_migracion_funciones')::bigint)
    -- Nada de B10 existe todavía.
    and to_regprocedure('crm.seguimiento_bases()') is null
    and to_regprocedure('crm.seguimiento_base(uuid)') is null
    and to_regprocedure('crm.seguimiento_base_detalle(uuid,uuid,text)') is null
    and to_regprocedure('crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)') is null
    and to_regprocedure('private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)') is null
    and not exists (select 1 from pg_proc p where p.pronamespace in ('crm'::regnamespace, 'private'::regnamespace)
                     and (p.proname in ('seguimiento_bases', 'seguimiento_base', 'seguimiento_base_detalle', 'reactivar_lead_base_v2',
                                        'bases_carga_estado_contacto', 'bases_carga_reparto_motivo_bloque', 'base_gestion_reactivar_capital_core',
                                        'base_gestion_intento_capital_core', 'registrar_intento_base_v2')
                          or p.proname like 'bases\_carga\_seguimiento\_%'))
    -- B7 y B8 aplicadas (tablas, índice de la base viva y los ayudantes de B8 que se reutilizan, con su identidad).
    and to_regclass('crm.bases_carga') is not null and to_regclass('crm.base_carga_leads') is not null
    and to_regclass('crm.base_carga_leads_lead_vivo_unico') is not null
    and (select pg_get_indexdef(i.indexrelid) = 'CREATE UNIQUE INDEX base_carga_leads_lead_vivo_unico ON crm.base_carga_leads USING btree (lead_id) WHERE activo'
           from pg_index i where i.indexrelid = 'crm.base_carga_leads_lead_vivo_unico'::regclass)
    and to_regprocedure('crm.cargar_base_lote(uuid,uuid,jsonb)') is not null
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '50af07f268c21b5d4b07e1d79de5c5bc'
           from pg_proc p where p.oid = to_regprocedure('private.bases_carga_base_visible(uuid,text,uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '9f671b71f96facf74c7ee4dcec02b6f9'
           from pg_proc p where p.oid = to_regprocedure('private.bases_carga_lead_ref(uuid,text,uuid)'))
    -- La lista que se reemplaza: el cuerpo de B6b, su identidad, ACL y comentario (el de B6c), una sola sobrecarga.
    and (select md5(p.prosrc) = '36af7e9cc4d6ec319b3d8004f3903473'
                and md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                        || '|' || p.proowner::regrole::text) = '889f42a55ad100335b11a3e6bef4967c'
                and p.proacl is not null and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
                and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '67f83881ece789fee1a37e0799123c18'
           from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid,boolean)'))
    and (select count(*) = 1 from pg_proc p where p.pronamespace = 'crm'::regnamespace and p.proname = 'obtener_base_gestion')
    -- Sus ÚNICOS consumidores de servidor son el resumen y la detalle de F4, con el cuerpo medido (no cambian).
    and (select md5(p.prosrc) = 'b773a7c49fbdfc45133b3405991b1958' and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
           from pg_proc p where p.oid = to_regprocedure('crm.base_gestion_resumen()'))
    and (select md5(p.prosrc) = '068372248be4127c80ba002542c9b4b8' and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
           from pg_proc p where p.oid = to_regprocedure('crm.base_gestion_resumen_detalle(uuid,text)'))
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~ 'obtener_base_gestion'
                       and p.oid not in (to_regprocedure('crm.obtener_base_gestion(uuid,boolean)'), to_regprocedure('crm.base_gestion_resumen()'),
                                         to_regprocedure('crm.base_gestion_resumen_detalle(uuid,text)')))
    and not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                     where c.relkind in ('v', 'm') and n.nspname not in ('pg_catalog', 'information_schema')
                       and pg_get_viewdef(c.oid) ~ 'obtener_base_gestion|base_gestion_reactivar_core')
    -- Reactivar: la puerta publicada y el núcleo de 4 argumentos (B3c), con identidad, ACL y comentario; una sola sobrecarga de
    -- cada uno; sus ÚNICOS llamadores son la puerta y el intento («agendó cita»), que siguen llamando con 4 argumentos.
    and (select md5(p.prosrc) = 'bf59d77929877e7a5eb46704d934363e'
                and md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                        || '|' || p.proowner::regrole::text) = '81cf539d2eaf9bc224855fc91af3b14c'
                and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
           from pg_proc p where p.oid = to_regprocedure('crm.reactivar_lead_base(uuid,uuid,text)'))
    and (select count(*) = 1 from pg_proc p where p.pronamespace = 'crm'::regnamespace and p.proname = 'reactivar_lead_base')
    and (select md5(p.prosrc) = 'c7e19f14bfb29811dcf3b46e533329ef'
                and md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                        || '|' || p.proowner::regrole::text) = 'b4afaf414e4c755e80c14e27d584f840'
                and p.proacl is not null and p.proacl::text = '{postgres=X/postgres}'
                and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '2d01d61e55440923a0a4efa876265c7e'
           from pg_proc p where p.oid = to_regprocedure('private.base_gestion_reactivar_core(uuid,uuid,uuid,text)'))
    and (select count(*) = 1 from pg_proc p where p.pronamespace = 'private'::regnamespace and p.proname = 'base_gestion_reactivar_core')
    -- El núcleo del intento (B3c) con identidad, ACL y comentario; su puerta publicada; una sola sobrecarga de cada uno; el
    -- núcleo solo lo llama la puerta.
    and (select md5(p.prosrc) = 'db8ba2b4df43c84438f216924f20e73d'
                and md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                        || '|' || p.proowner::regrole::text) = '727c4c0629aae25b0d701bdac8a41bb5'
                and p.proacl is not null and p.proacl::text = '{postgres=X/postgres}'
                and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '2bd000b154679af92d052194304f55fa'
           from pg_proc p where p.oid = to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)'))
    and (select count(*) = 1 from pg_proc p where p.pronamespace = 'private'::regnamespace and p.proname = 'base_gestion_intento_core')
    and (select md5(p.prosrc) = 'd92c791fbe6f84e5d4f8ca39357b4721'
                and md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                        || '|' || p.proowner::regrole::text) = '278df37b38c2c420b8c0b595051c0e7a'
                and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
           from pg_proc p where p.oid = to_regprocedure('crm.registrar_intento_base(uuid,uuid,text,text,timestamp with time zone)'))
    and (select count(*) = 1 from pg_proc p where p.pronamespace = 'crm'::regnamespace and p.proname = 'registrar_intento_base')
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~ 'base_gestion_intento_core'
                       and p.oid not in (to_regprocedure('crm.registrar_intento_base(uuid,uuid,text,text,timestamp with time zone)'),
                                         to_regprocedure('private.bases_carga_reparto_hechos(uuid,timestamp with time zone)')))  -- B9: la nombra en un comentario, no la llama
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~ 'base_gestion_reactivar_core'
                       and p.oid not in (to_regprocedure('crm.reactivar_lead_base(uuid,uuid,text)'),
                                         to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)'),
                                         to_regprocedure('private.bases_carga_reparto_hechos(uuid,timestamp with time zone)')))  -- B9: la nombra en un comentario, no la llama
    -- Ayudantes de las puertas nuevas y de la lista, con la identidad ensayada.
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = 'c4ae35f90e850548653a25f08d25327c'
           from pg_proc p where p.oid = to_regprocedure('private.base_gestion_lead_visible(uuid,text,uuid,uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '16960a2a21cc5c372431c2dd67acafe4'
           from pg_proc p where p.oid = to_regprocedure('private.rol_crm(uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '45ae492c03234b80336c0b8f5c8ac09b'
           from pg_proc p where p.oid = to_regprocedure('private.vendedor_ids_visibles(uuid)'))
    -- r2: B9 r2 aplicada (20261004222602, md5 8a169944…) con sus huellas EXACTAS, medidas en el banco B con B9 r2 recién
    -- aplicada. (a) Lo que B10 reemplaza o borra —las tres piezas del núcleo y el clasificador— y las tres puertas, cuyo
    -- comentario B10 actualiza: cuerpo, identidad, ACL y comentario (la reversa los repone byte a byte).
    and (select string_agg(x.firma, ',' order by x.firma) from (values
           ('private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)', '8ace9326744cba6c262adb20203b4be0', '194eeb751dadd93a633699269e771340', '{postgres=X/postgres}', '0288e89e8938d90bb83101feecea2195'),
           ('private.bases_carga_contactos_core(uuid,uuid,text)', '0faaf15b274890e1e788632c27b477bd', 'a9bb62c38eb5fe46f3ef74109800d0cf', '{postgres=X/postgres}', 'c486469dfe54d349463472b0a75dd2b6'),
           ('private.bases_carga_reparto_recogible(uuid,uuid,timestamp with time zone,boolean)', '36d80e0e61b293d9cdd710fc00758054', '48e70fe5af1cad17aaf921f4bb9d2539', '{postgres=X/postgres}', 'a57b0dd26e0f120dcfa7655db771a018'),
           ('private.bases_carga_reparto_estado(boolean,boolean,text,uuid,boolean,date,uuid,boolean,boolean,boolean,boolean,date)', '28ae6bf56e4d54fdf45ec5f976ddbce3', 'f2ed9b90aac655e8d925629a19a6dfb9', '{postgres=X/postgres}', '3163053015c2e32323184e804a72c212'),
           ('crm.repartir_base(uuid,uuid,jsonb)', 'fd7531ba7cd7cf8a259a389e2895ee2e', 'fa967cde9c19fa033aebb2020202b85a', '{postgres=X/postgres,authenticated=X/postgres}', '0893508c3762d3588f7725a9bc506737'),
           ('crm.recoger_de_base(uuid,uuid,uuid)', '4744f70e69c0f70c22a6a295184e3095', 'f9be2c8a556f2ca0a57768675041ce4a', '{postgres=X/postgres,authenticated=X/postgres}', '7f99efc1751c49a220ce04d2604ec717'),
           ('crm.contactos_de_base(uuid,text)', 'd528bab6930698d160f9635417a3ca7a', 'fb57997d070d4c8064cde67a8d5ae9d5', '{postgres=X/postgres,authenticated=X/postgres}', '3b14ee12d12694e78ee7eecf40c533c6')) x(firma, cuerpo, ident, acl, com)
         left join pg_proc p on p.oid = to_regprocedure(x.firma)
        where (md5(p.prosrc) = x.cuerpo
               and md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                       || '|' || p.proowner::regrole::text) = x.ident
               and p.proacl is not null and p.proacl::text = x.acl
               and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = x.com) is not true) is null
    -- (b) Lo que la definición única reutiliza (no cambia): identidad de los hechos y el motivo de B9, la regla de B6 de B9 y
    -- el ámbito del dueño de B8.
    and (select string_agg(x.firma, ',' order by x.firma) from (values
           ('private.bases_carga_reparto_motivo(boolean,boolean,text,boolean,date,boolean,date)', 'd73381d3154c8615e8743b565fa0f799'),
           ('private.bases_carga_reparto_hechos(uuid,timestamp with time zone)', '885d58e94dd6357f9b19fa1848bec9da'),
           ('private.base_gestion_en_gestion_hasta(uuid)', '749573f8653aa7135e125ef029cfc9b5'),
           ('private.bases_carga_en_subarbol(uuid[],uuid,uuid)', '041d852f8d69017c77a2f9fcd8cbab93'),
           ('private.bases_carga_subarbol(uuid)', '0571e6b4075a6e2c88b46d09378e6cc6')) x(firma, ident)
         left join pg_proc p on p.oid = to_regprocedure(x.firma)
        where (md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                   || '|' || p.proowner::regrole::text) = x.ident) is not true) is null
    -- (c) Una sola sobrecarga de cada pieza de B9 y sus ÚNICOS llamadores (pg_proc, banco B con B9 r2): el clasificador, solo
    -- contactos_core; recogible, solo recoger_core; contactos_core y repartir_core, solo su puerta.
    and (select count(*) from pg_proc p where p.pronamespace = 'private'::regnamespace
          and (p.proname like 'bases\_carga\_reparto\_%' or p.proname in ('bases_carga_repartir_core', 'bases_carga_recoger_core', 'bases_carga_contactos_core'))) = 10
    and (select count(*) from pg_proc p where p.pronamespace = 'crm'::regnamespace
          and p.proname in ('repartir_base', 'recoger_de_base', 'contactos_de_base')) = 3
    and not exists (select 1 from pg_proc p where p.prosrc ~ 'bases_carga_reparto_estado'
                     and p.oid <> to_regprocedure('private.bases_carga_contactos_core(uuid,uuid,text)'))
    and not exists (select 1 from pg_proc p where p.prosrc ~ 'bases_carga_reparto_recogible'
                     and p.oid <> to_regprocedure('private.bases_carga_recoger_core(uuid,uuid,uuid,uuid)'))
    and not exists (select 1 from pg_proc p where p.prosrc ~ 'bases_carga_contactos_core'
                     and p.oid <> to_regprocedure('crm.contactos_de_base(uuid,text)'))
    and not exists (select 1 from pg_proc p where p.prosrc ~ 'bases_carga_repartir_core'
                     and p.oid <> to_regprocedure('crm.repartir_base(uuid,uuid,jsonb)'))
    and not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                     where c.relkind in ('v', 'm') and n.nspname not in ('pg_catalog', 'information_schema')
                       and pg_get_viewdef(c.oid) ~ 'bases_carga_reparto_estado|bases_carga_reparto_recogible|bases_carga_contactos_core|bases_carga_repartir_core')
    -- Los CHECK de capital y moneda en los que se apoya el núcleo (B7), exactos y validados.
    and (select pg_get_constraintdef(c.oid) = 'CHECK ((((monto_estimado IS NULL) AND (origen = ''base_cargada''::text) AND (etapa = ''descartado''::text)) OR ((monto_estimado IS NOT NULL) AND (monto_estimado > (0)::numeric) AND (monto_estimado <= 9999999999.99) AND (monto_estimado = trunc(monto_estimado, 2)))))'
                and c.convalidated
           from pg_constraint c where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_monto_estimado_valido')
    and (select pg_get_constraintdef(c.oid) = 'CHECK ((moneda = ANY (ARRAY[''PEN''::text, ''USD''::text])))' and c.convalidated
           from pg_constraint c where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_moneda_check')
  ) is not true then
    raise exception 'PREFLIGHT B10: sin el candado de migraciones en esta sesion, ya aplicada o a medias, falta B8 o B9 r2 (o B9 no es la medida), la lista no es la de B6b, reactivar o su nucleo no son los medidos, la lista o el nucleo tienen otro consumidor, o un ayudante o un CHECK cambio';
  end if;
end;
$preflight$;

-- Foto del censo analítico: el postflight exige que no cambie.
create temp table _b10_censo_antes on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;

-- Foto de la lista VIVA (B6b) como Gerencia (todo el ámbito), con false y con true, y del resumen de F4: el postflight exige
-- la misma lista sin los dormidos sin repartir, en el mismo orden, y el mismo resumen.
create temp table _b10_lista_antes (modo boolean, ord bigint, lead_id uuid, fila text) on commit drop;
create temp table _b10_resumen_antes (vendedor_id uuid, nombre text, en_base integer, rellamadas_hoy integer, intentos_hoy integer,
                                      reactivaciones_mes integer) on commit drop;
do $foto$
declare
  v_ger uuid;
begin
  select e.perfil_id into v_ger from crm.equipo e
   where e.activo and private.rol_crm(e.perfil_id) = 'gerencia' order by e.perfil_id limit 1;
  if v_ger is null then
    raise notice 'bases_cargadas_seguimiento: sin Gerencia activa en esta base; la identidad con B6b NO RUN';
    return;
  end if;
  perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
  perform pg_catalog.set_config('request.jwt.claim.sub', v_ger::text, true);
  insert into pg_temp._b10_lista_antes (modo, ord, lead_id, fila)
  select m.modo, t.ordinality, t.lead_id,
         row(t.lead_id, t.nombre_completo, t.telefono, t.distrito, t.origen, t.categoria_interes, t.monto_estimado, t.moneda,
             t.motivo_descarte, t.descartado_en, t.dias_desde_descarte, t.etapa_maxima, t.intentos, t.ultimo_resultado,
             t.ultimo_intento_en, t.proxima_llamada_en, t.rellamada_hoy, t.enfriado_hasta, t.ciclo_n, t.vendedor_id, t.gestiona,
             t.recibido_en, t.no_contactar, t.no_contactar_en, t.no_contactar_motivo, t.no_contactar_por)::text
    from (values (false), (true)) m(modo)
    cross join lateral crm.obtener_base_gestion(null, m.modo) with ordinality t;
  insert into pg_temp._b10_lista_antes (modo, ord, lead_id, fila) values (null, 0, v_ger, 'gerencia');  -- quién hizo la foto
  insert into pg_temp._b10_resumen_antes select r.* from crm.base_gestion_resumen() r;
  perform pg_catalog.set_config('request.jwt.claims', '', true);
  perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
end;
$foto$;

-- ── 1 · Núcleo: ayudantes del seguimiento (sin agregados de conteo) ────────────────────────────────────────────────────
create function private.bases_carga_estado_contacto(p_lead_id uuid, p_activo boolean, p_no_contactar boolean, p_etapa text,
                                                    p_vendedor_id uuid, p_asignado_supervisor_id uuid, p_enfriado_hasta date,
                                                    p_analista_id uuid, p_asignado_en timestamptz, p_agregado_en timestamptz,
                                                    p_dueno uuid, p_subarbol uuid[], p_hoy date,
                                                    p_intento boolean default null, p_cita boolean default null,
                                                    p_reactivado boolean default null)
returns text
language sql
stable
security invoker
set search_path = ''
as $function$
  -- B10 r2/r3 (coordinador; Codex r1 P2): la ÚNICA definición del estado de un contacto de una base, para TODAS las puertas
  -- de B9 y B10: el seguimiento y su detalle, crm.contactos_de_base, la exclusión de la lista de la base para gestión, el
  -- bloque y el individual de repartir y recoger. Entradas: la fila del lead, la pertenencia (analista, asignado_en, cuándo
  -- entró a la base) y el supervisor DUEÑO con su subárbol (private.bases_carga_subarbol). Los hechos (intento, cita,
  -- reactivado) son los de private.bases_carga_reparto_hechos (B9) desde asignado_en o, sin reparto, desde que entró a la
  -- base; quien ya los calculó con esa función los pasa (p_intento, p_cita, p_reactivado) y, si llegan NULL, se calculan
  -- aquí. Los movimientos ajenos, el rastro `reasignacion` de trg_leads_reasignacion (la API no lo puede escribir:
  -- actividades_insert lo excluye). r3 (E1 de Miguel): un armado que conserva su analista anterior es «sin repartir» como
  -- cualquier otro; si su analista lo está trabajando (seguimiento activo B6), «trabajado». Condiciones con `is true`/`is not
  -- true`: un NULL nunca hace a un contacto «sin repartir».
  select case
           when p_activo is not true then 'retirado'
           when p_no_contactar is not false then 'no_contactar'
           -- Con reparto: ya no es de su analista (E14).
           when p_analista_id is not null and p_vendedor_id is distinct from p_analista_id then 'movido_otra_via'
           -- Sin reparto: fuera del ámbito del supervisor dueño (su bandeja, o un analista o una bandeja de su subárbol, B8).
           when p_analista_id is null
                and not (p_vendedor_id is null and p_asignado_supervisor_id is not distinct from p_dueno)
                and private.bases_carga_en_subarbol(p_subarbol, p_vendedor_id, p_asignado_supervisor_id) is not true then 'movido_otra_via'
           -- Salió del descarte: con una cita o una reactivación de la base (desde el reparto o, sin reparto, desde que entró a
           -- la base); si no, por otra vía.
           when p_etapa is distinct from 'descartado' then
             case when p_cita is not null and p_reactivado is not null
                    then case when p_cita then 'cita' when p_reactivado then 'reactivado' else 'movido_otra_via' end
                  else (select case when h.cita is true then 'cita' when h.reactivado is true then 'reactivado' else 'movido_otra_via' end
                          from private.bases_carga_reparto_hechos(p_lead_id, coalesce(p_asignado_en, p_agregado_en)) h)
             end
           -- Sin reparto: otra vía le cambió el responsable desde que entró a la base, salvo que hoy esté en la bandeja del dueño
           -- sin analista (recogido).
           when p_analista_id is null
                and not (p_vendedor_id is null and p_asignado_supervisor_id is not distinct from p_dueno)
                and exists (select 1 from crm.actividades a
                             where a.lead_id = p_lead_id and a.tipo = 'reasignacion' and a.creado_en >= p_agregado_en) then 'movido_otra_via'
           when p_enfriado_hasta is not null and p_enfriado_hasta > p_hoy then 'en_descanso'
           -- Con reparto: con o sin intento de la base desde asignado_en.
           when p_analista_id is not null then
             case when p_intento is not null then case when p_intento then 'trabajado' else 'sin_tocar' end
                  else (select case when h.intento is true then 'trabajado' else 'sin_tocar' end
                          from private.bases_carga_reparto_hechos(p_lead_id, p_asignado_en) h)
             end
           -- Sin reparto y con analista (armado con su analista anterior) que lo tiene en seguimiento activo (B6): no se reparte.
           when p_vendedor_id is not null and private.base_gestion_en_gestion_hasta(p_lead_id) is not null then 'trabajado'
           else 'sin_repartir'
         end;
$function$;

create function private.bases_carga_reparto_motivo_bloque(p_lead_id uuid, p_activo boolean, p_no_contactar boolean, p_etapa text,
                                                          p_vendedor_id uuid, p_asignado_supervisor_id uuid, p_enfriado_hasta date,
                                                          p_analista_id uuid, p_asignado_en timestamptz, p_agregado_en timestamptz,
                                                          p_dueno uuid, p_subarbol uuid[], p_hoy date)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_motivo text;
  v_estado text;
begin
  -- B10 r2/r3: el reparto EN BLOQUE elige SOLO contactos en estado 'sin_repartir' (private.bases_carga_estado_contacto, la
  -- definición de toda puerta, con las MISMAS entradas): NULL = elegible. Si no, el motivo para «omitidos» y para la revisión
  -- bajo candado: el de private.bases_carga_reparto_motivo (B9: inactivo, fuera_de_ambito, no_descartado, no_contactar,
  -- en_descanso, en_gestion; se evalúa para TODO candidato, como en B9) o, si ese no dice nada, el estado (movido_otra_via).
  -- plpgsql (no sql): sus llamadas guardan el plan entre filas (medido: 5000 candidatos en ~0,1 s en vez de ~1,3 s).
  v_motivo := private.bases_carga_reparto_motivo(p_activo,
                private.bases_carga_en_subarbol(p_subarbol, p_vendedor_id, p_asignado_supervisor_id),
                p_etapa, p_no_contactar, p_enfriado_hasta,
                private.base_gestion_en_gestion_hasta(p_lead_id) is not null, p_hoy);
  if v_motivo is not null then
    return v_motivo;
  end if;
  v_estado := private.bases_carga_estado_contacto(p_lead_id, p_activo, p_no_contactar, p_etapa, p_vendedor_id, p_asignado_supervisor_id,
                                                  p_enfriado_hasta, p_analista_id, p_asignado_en, p_agregado_en, p_dueno, p_subarbol, p_hoy);
  -- r4 (auditor-rls P3-1): un estado NULL nunca es elegible (la definición no lo da hoy; si algún día lo diera, no se reparte).
  return case when v_estado is not distinct from 'sin_repartir' then null else coalesce(v_estado, 'sin_estado') end;
end;
$function$;

create function private.bases_carga_seguimiento_cifras()
returns text[]
language sql
immutable
security invoker
set search_path = ''
as $function$
  -- B10: las cifras que se abren (todo número se abre): las columnas numéricas de crm.seguimiento_bases y
  -- crm.seguimiento_base. «avance» es un cociente (trabajados / repartidos): se abre por «trabajados».
  select array['total', 'sin_repartir', 'repartidos', 'asignados', 'sin_tocar', 'sin_tocar_3_dias', 'trabajados',
               'en_descanso', 'citas', 'reactivados', 'movidos_otra_via', 'retirados', 'no_contactar']::text[];
$function$;

create function private.bases_carga_seguimiento_rol(p_actor uuid)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_rol text := private.rol_crm(p_actor);
begin
  -- B10: el seguimiento es de Supervisión y Gerencia (rol resuelto en el servidor). Analista, coordinación, directorio,
  -- un miembro desactivado o sin sesión → 42501.
  if p_actor is null or (v_rol in ('supervisor', 'gerencia')) is not true then
    raise exception 'Solo Supervisión y Gerencia ven el seguimiento de las bases' using errcode = '42501';
  end if;
  return v_rol;
end;
$function$;

create function private.bases_carga_seguimiento_exigir_base(p_actor uuid, p_rol text, p_base_id uuid)
returns void
language plpgsql
stable
security invoker
set search_path = ''
as $function$
begin
  -- B10: la base existe, está VIVA y el actor la ve (private.bases_carga_base_visible, espejo de la policy
  -- bases_carga_select); si no, P0002 sin delatar si existe.
  if p_base_id is null then
    raise exception 'Indica la base' using errcode = '22023';
  end if;
  if not exists (select 1 from crm.bases_carga b
                  where b.id = p_base_id and b.activo and private.bases_carga_base_visible(p_actor, p_rol, b.supervisor_id)) then
    raise exception 'Base no encontrada o fuera de tu ámbito' using errcode = 'P0002';
  end if;
end;
$function$;

create function private.bases_carga_seguimiento_filas(p_base_ids uuid[], p_hoy date)
returns table(base_id uuid, lead_id uuid, analista_id uuid, asignado_en timestamptz, lead_activo boolean, vendedor_id uuid,
              asignado_supervisor_id uuid, nombre_completo text, estado text, ultimo_intento_en timestamptz,
              ultimo_resultado text, cifras text[])
language sql
stable
security invoker
set search_path = ''
as $function$
  -- B10: UNA fila por contacto VIVO (pertenencia activa) de las bases pedidas, con su estado y el arreglo de las cifras del
  -- seguimiento a las que pertenece (nombres de columna de crm.seguimiento_bases y crm.seguimiento_base). Es la ÚNICA
  -- definición de cada cifra: los conteos y el detalle leen este arreglo. r2: el estado es el de
  -- private.bases_carga_estado_contacto (la definición de toda puerta de B9 y B10) y los hechos desde el reparto, los de
  -- private.bases_carga_reparto_hechos (B9); trabajados, citas y reactivados cuentan solo lo repartido (desde asignado_en). Solo
  -- predicado: sin agregados de conteo (censo analítico).
  with bs as materialized (
    -- El subárbol del supervisor DUEÑO de cada base, una vez por base.
    select b.id, b.supervisor_id, array(select private.bases_carga_subarbol(b.supervisor_id)) as subarbol
      from crm.bases_carga b
     where b.id = any (p_base_ids)
  )
  select x.base_id, x.lead_id, x.analista_id, x.asignado_en, x.activo, x.vendedor_id, x.asignado_supervisor_id, x.nombre_completo,
         x.estado, x.ultimo_en, x.ultimo,
         pg_catalog.array_remove(array[
           'total',
           case when x.estado = 'sin_repartir' then 'sin_repartir' end,
           case when x.rep then 'repartidos' end,
           case when x.rep then 'asignados' end,
           case when x.estado = 'sin_tocar' then 'sin_tocar' end,
           case when x.estado = 'sin_tocar' and x.dias >= 3 then 'sin_tocar_3_dias' end,
           case when x.rep and x.intento is true then 'trabajados' end,
           case when x.estado = 'en_descanso' then 'en_descanso' end,
           case when x.rep and x.cita is true then 'citas' end,
           case when x.rep and x.reactivado is true then 'reactivados' end,
           case when x.estado = 'movido_otra_via' then 'movidos_otra_via' end,
           case when x.estado = 'retirado' then 'retirados' end,
           case when x.estado = 'no_contactar' then 'no_contactar' end]::text[], null)
    from (
      select bl.base_id, bl.lead_id, bl.analista_id, bl.asignado_en, l.activo, l.vendedor_id, l.asignado_supervisor_id,
             l.nombre_completo, (bl.analista_id is not null) as rep, h.intento, h.cita, h.reactivado, u.ultimo_en, u.ultimo,
             private.bases_carga_estado_contacto(l.id, l.activo, l.no_contactar, l.etapa, l.vendedor_id, l.asignado_supervisor_id,
                                                 l.enfriado_hasta, bl.analista_id, bl.asignado_en, bl.creado_en, bs.supervisor_id,
                                                 bs.subarbol, p_hoy, h.intento, h.cita, h.reactivado) as estado,
             (p_hoy - (bl.asignado_en at time zone 'America/Lima')::date) as dias
        from crm.base_carga_leads bl
        join bs on bs.id = bl.base_id
        join crm.leads l on l.id = bl.lead_id
        -- Hechos de la base (private.bases_carga_reparto_hechos, B9) desde el reparto o, sin reparto, desde que entró a la base:
        -- los mismos que la definición única calcularía (se le pasan: una consulta por fila, no dos).
        cross join lateral private.bases_carga_reparto_hechos(bl.lead_id, coalesce(bl.asignado_en, bl.creado_en)) h
        -- Solo para mostrar: el último intento desde el reparto (mismo desempate que private.base_gestion_intentos_ciclo).
        left join lateral (
          select pg_catalog.max(a.creado_en) as ultimo_en,
                 (pg_catalog.array_agg(a.metadata->>'resultado'
                                       order by a.creado_en desc, (a.metadata->>'intento_n')::integer desc, a.id desc))[1] as ultimo
            from crm.actividades a
           where a.lead_id = bl.lead_id and a.metadata->>'evento' = 'intento_base' and a.creado_en >= bl.asignado_en
        ) u on true
       where bl.base_id = any (p_base_ids) and bl.activo
       offset 0  -- el estado se calcula UNA vez por fila (sin esto, el planificador copia la llamada en cada cifra)
    ) x
$function$;

-- ── 1b · B9 r2: la MISMA definición del estado en sus puertas (CREATE OR REPLACE: misma firma, dueño, seguridad y ACL) ────
-- La lista de la base (crm.contactos_de_base): el estado sale de private.bases_carga_estado_contacto (el filtro, el de B9).
create or replace function private.bases_carga_contactos_core(p_actor uuid, p_base_id uuid, p_estado text)
returns table(lead_id uuid, nombre_completo text, telefono text, distrito text, agregado_en timestamptz, analista_id uuid,
              analista_nombre text, estado text)
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_rol text := private.bases_carga_reparto_rol(p_actor);
  v_filtro text := coalesce(p_estado, 'sin_repartir');
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_sup uuid;
  v_subarbol uuid[];
begin
  if p_base_id is null then
    raise exception 'La base es obligatoria' using errcode = '22023';
  end if;
  if (v_filtro in ('sin_repartir', 'repartidos', 'todos')) is not true then
    raise exception 'El filtro es sin_repartir, repartidos o todos' using errcode = '22023';
  end if;
  select b.supervisor_id into v_sup from crm.bases_carga b where b.id = p_base_id;
  if not found or not private.bases_carga_base_visible(p_actor, v_rol, v_sup) then
    raise exception 'Base no encontrada o fuera de tu ámbito' using errcode = 'P0002';
  end if;
  v_subarbol := array(select private.bases_carga_subarbol(v_sup));
  -- Solo contactos que el actor VE y siguen activos (private.bases_carga_lead_ref, la regla de B8 para toda referencia).
  -- B10 r2/r3: el estado es el de private.bases_carga_estado_contacto (el mismo del seguimiento y del reparto en bloque), con
  -- los hechos de private.bases_carga_reparto_hechos desde el reparto o desde que entró a la base. El filtro es el de B9:
  -- sin_repartir = sin analista de la base (su estado dice si el bloque lo puede elegir), repartidos = con analista.
  return query
    select l.id, l.nombre_completo, l.telefono, l.distrito, bl.creado_en, bl.analista_id, p.nombre_completo,
           private.bases_carga_estado_contacto(l.id, l.activo, l.no_contactar, l.etapa, l.vendedor_id, l.asignado_supervisor_id,
                                               l.enfriado_hasta, bl.analista_id, bl.asignado_en, bl.creado_en, v_sup, v_subarbol, v_hoy,
                                               h.intento, h.cita, h.reactivado)
      from crm.base_carga_leads bl
      join crm.leads l on l.id = bl.lead_id
      left join public.perfiles p on p.id = bl.analista_id
      cross join lateral private.bases_carga_reparto_hechos(l.id, coalesce(bl.asignado_en, bl.creado_en)) h
     where bl.base_id = p_base_id and bl.activo
       and (v_filtro = 'todos' or (v_filtro = 'sin_repartir') = (bl.analista_id is null))
       and private.bases_carga_lead_ref(p_actor, v_rol, l.id)
     order by bl.creado_en, l.creado_en, l.id;
end;
$function$;

-- Recoger = lo que el seguimiento muestra «sin tocar» (el mismo estado), sin seguimiento activo B6; de un analista de baja,
-- todo lo suyo que siga descartado (manda B6, que la baja libera).
create or replace function private.bases_carga_reparto_recogible(p_lead_id uuid, p_analista_id uuid, p_asignado_en timestamptz, p_baja boolean)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $function$
  -- UNA definición de «se puede recoger» (la usan la foto y la revisión bajo candado de recoger): sigue vivo, descartado y en
  -- manos de ESE analista (lo movido por otra vía no se deshace, E14), en estado sin_tocar de la definición única
  -- (private.bases_carga_estado_contacto: sin intento desde que se le repartió, sin veto y sin descanso) —salvo que el
  -- analista esté de baja (r1, auditor P3): entonces manda B6, que la baja libera— y sin seguimiento activo B6. `is true`.
  -- B10 r2: «sin tocar» es el mismo estado que cuenta el seguimiento (lo que el supervisor ve en rojo y recoge).
  select coalesce((select (l.activo and l.etapa = 'descartado' and l.vendedor_id = p_analista_id
                           and (p_baja is true
                                or private.bases_carga_estado_contacto(l.id, l.activo, l.no_contactar, l.etapa, l.vendedor_id,
                                                                       l.asignado_supervisor_id, l.enfriado_hasta, p_analista_id,
                                                                       p_asignado_en, null, null, null,
                                                                       (pg_catalog.now() at time zone 'America/Lima')::date) = 'sin_tocar')
                           and private.base_gestion_en_gestion_hasta(l.id) is null) is true
                     from crm.leads l
                    where l.id = p_lead_id), false);
$function$;

-- El reparto: el bloque elige SOLO el estado sin_repartir; el individual rechaza además lo movido por otra vía.
create or replace function private.bases_carga_repartir_core(p_actor uuid, p_operacion_id uuid, p_base_id uuid, p_reparto jsonb)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  v_rol text := private.bases_carga_reparto_rol(p_actor);
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_max integer;
  v_max_analistas integer;
  v_modo text;
  v_asig jsonb;
  v_n integer;
  v_tope integer;
  v_md5 text;
  v_prev jsonb;
  v_sup uuid;
  v_base crm.bases_carga%rowtype;
  v_subarbol uuid[];
  e record;
  c record;
  a_analista uuid[] := '{}';   -- bloque: los analistas en el orden pedido; individual: el analista de cada fila
  a_cantidad integer[] := '{}';
  a_lead uuid[] := '{}';
  a_ev_lead uuid[];
  a_ev_motivo text[];
  v_total integer := 0;
  v_bloqueados uuid[];
  v_elegibles uuid[] := '{}';
  v_pend uuid[];
  v_lote uuid[];
  v_marca bigint := 0;
  v_hasta bigint;
  v_falta integer;
  v_holgura integer;
  v_presupuesto integer;
  v_tomados integer := 0;
  v_examinados uuid[];
  v_disponibles integer;
  v_omitidos jsonb := '[]'::jsonb;
  v_rechazos jsonb := '[]'::jsonb;
  v_dest_lead uuid[] := '{}';
  v_dest_analista uuid[] := '{}';
  v_por_analista jsonb;
  v_pos integer := 0;
  v_motivo text;
  v_upd integer;
  v_ahora timestamptz;
  v_estado text;
  v_estado_c text;  -- B10 r2: el estado del contacto (private.bases_carga_estado_contacto)
  v_resp jsonb;
  i integer;
begin
  select k.max_contactos, k.max_analistas, k.holgura_candados into v_max, v_max_analistas, v_holgura from private.bases_carga_reparto_constantes() k;
  -- Candado y LUEGO evaluación: cada sentencia debe ver lo confirmado tras tomar los candados (como reactivar).
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'Repartir requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation')
      using errcode = '0A000';
  end if;
  if p_base_id is null then
    raise exception 'La base es obligatoria' using errcode = '22023';
  end if;
  -- 1 · FORMA (vale igual para una operación nueva y para su reintento).
  if p_reparto is null or pg_catalog.jsonb_typeof(p_reparto) is distinct from 'object'
     or pg_catalog.jsonb_typeof(p_reparto -> 'asignaciones') is distinct from 'array' then
    raise exception 'El reparto llega como {"modo": "bloque" o "individual", "asignaciones": [...]}' using errcode = '22023';
  end if;
  v_modo := p_reparto ->> 'modo';
  if (v_modo in ('bloque', 'individual')) is not true then
    raise exception 'El modo del reparto es «bloque» o «individual»' using errcode = '22023';
  end if;
  v_asig := p_reparto -> 'asignaciones';
  v_n := pg_catalog.jsonb_array_length(v_asig);
  v_tope := (case when v_modo = 'bloque' then v_max_analistas else v_max end);
  if v_n < 1 or v_n > v_tope then
    raise exception 'Un reparto en % trae entre 1 y % asignaciones (este trae %)', v_modo, v_tope, v_n using errcode = '22023';
  end if;
  for e in select x.valor, x.pos from pg_catalog.jsonb_array_elements(v_asig) with ordinality as x(valor, pos) order by x.pos loop
    if pg_catalog.jsonb_typeof(e.valor) is distinct from 'object'
       or ((e.valor ->> 'analista_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') is not true then
      raise exception 'La asignación % no trae un analista válido', e.pos using errcode = '22023';
    end if;
    if v_modo = 'bloque' then
      if pg_catalog.jsonb_typeof(e.valor -> 'cantidad') is distinct from 'number'
         or ((e.valor ->> 'cantidad') ~ '^[1-9][0-9]{0,5}$') is not true then
        raise exception 'La asignación % no trae una cantidad entera mayor que 0', e.pos using errcode = '22023';
      end if;
      if (e.valor ->> 'analista_id')::uuid = any (a_analista) then
        raise exception 'El analista de la asignación % se repite', e.pos using errcode = '22023';
      end if;
      a_analista := a_analista || (e.valor ->> 'analista_id')::uuid;
      a_cantidad := a_cantidad || (e.valor ->> 'cantidad')::integer;
      v_total := v_total + (e.valor ->> 'cantidad')::integer;
    else
      if ((e.valor ->> 'lead_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') is not true then
        raise exception 'La asignación % no trae un contacto válido', e.pos using errcode = '22023';
      end if;
      if (e.valor ->> 'lead_id')::uuid = any (a_lead) then
        raise exception 'El contacto de la asignación % se repite', e.pos using errcode = '22023';
      end if;
      a_lead := a_lead || (e.valor ->> 'lead_id')::uuid;
      a_analista := a_analista || (e.valor ->> 'analista_id')::uuid;
    end if;
  end loop;
  if v_modo = 'bloque' and v_total > v_max then
    raise exception 'Un reparto mueve hasta % contactos por operación (este pide %)', v_max, v_total using errcode = '22023';
  end if;
  if v_modo = 'individual' and pg_catalog.cardinality(array(select distinct x from pg_catalog.unnest(a_analista) x)) > v_max_analistas then
    raise exception 'Un reparto va a lo más a % analistas', v_max_analistas using errcode = '22023';
  end if;

  -- 2 · Idempotencia: el mismo pedido con el mismo id devuelve su recibo (B8: base aún visible); cada lead_id que el recibo
  -- nombra se vuelve a juzgar con el actor de hoy (si alguno ya no está a su alcance, no se repite: P0002).
  v_md5 := pg_catalog.md5(pg_catalog.jsonb_build_object('tipo', 'repartir', 'base_id', p_base_id, 'reparto', p_reparto)::text);
  v_prev := private.bases_carga_operacion_previa(p_actor, v_rol, p_operacion_id, 'repartir', v_md5);
  if v_prev is not null then
    if exists (select 1 from pg_catalog.jsonb_array_elements(coalesce(v_prev -> 'omitidos', '[]'::jsonb)) x
                where x ->> 'lead_id' is not null and not private.bases_carga_lead_ref(p_actor, v_rol, (x ->> 'lead_id')::uuid)) then
      raise exception 'La respuesta guardada nombra contactos que ya no están a tu alcance; repite la operación con otro identificador'
        using errcode = 'P0002';
    end if;
    return v_prev;
  end if;

  -- 3 · La base: visible (sin delatar si existe), su fila bloqueada NOWAIT, viva y con su supervisor dueño activo.
  select b.supervisor_id into v_sup from crm.bases_carga b where b.id = p_base_id;
  if not found or not private.bases_carga_base_visible(p_actor, v_rol, v_sup) then
    raise exception 'Base no encontrada o fuera de tu ámbito' using errcode = 'P0002';
  end if;
  begin
    select b.* into v_base from crm.bases_carga b where b.id = p_base_id for update nowait;
  exception when lock_not_available then
    raise exception 'Hay otra operación en curso de esta base; reintenta' using errcode = '55P03';
  end;
  if not v_base.activo then
    raise exception 'La base está retirada: no se reparte' using errcode = '22023';
  end if;
  if private.es_destino_crm_activo(v_base.supervisor_id, array['supervisor']::text[]) is not true then
    raise exception 'El supervisor dueño de la base ya no está activo: no se puede repartir' using errcode = '22023';
  end if;
  v_subarbol := array(select private.bases_carga_subarbol(v_base.supervisor_id));
  -- 4 · Los analistas (en el orden en que aparecen).
  for c in select u.a from pg_catalog.unnest(a_analista) with ordinality as u(a, pos) group by u.a order by min(u.pos) loop
    perform private.bases_carga_reparto_analista(v_rol, v_subarbol, c.a);
  end loop;

  if v_modo = 'bloque' then
    -- 5b · Foto SIN candados: los contactos sin repartir de la base, en el orden del reparto (los más antiguos en la base
    -- primero), con su motivo de hoy (private.bases_carga_reparto_motivo, una definición).
    select coalesce(pg_catalog.array_agg(q.lead_id order by q.orden), '{}'), coalesce(pg_catalog.array_agg(q.motivo order by q.orden), '{}')
      into a_ev_lead, a_ev_motivo
      from (select bl.lead_id,
                   pg_catalog.row_number() over (order by bl.creado_en, l.creado_en, l.id) as orden,
                   -- B10 r2: solo el estado sin_repartir de la definición única se elige (NULL); si no, su motivo.
                   private.bases_carga_reparto_motivo_bloque(l.id, l.activo, l.no_contactar, l.etapa, l.vendedor_id, l.asignado_supervisor_id, l.enfriado_hasta, bl.analista_id, bl.asignado_en, bl.creado_en, v_base.supervisor_id, v_subarbol, v_hoy) as motivo
              from crm.base_carga_leads bl
              join crm.leads l on l.id = bl.lead_id
             where bl.base_id = p_base_id and bl.activo and bl.analista_id is null) q;
    v_pend := array(select x.l from unnest(a_ev_lead, a_ev_motivo) with ordinality as x(l, m, o) where x.m is null order by x.o);
    -- r1 (Codex P2): candado SOLO de lo necesario. Por tandas, en ese orden, solo los que faltan, FOR UPDATE SKIP LOCKED (lo que
    -- otro proceso tiene se salta sin esperar; nada fuera de lo pedido queda bloqueado). Bajo el candado, en otra sentencia (ve
    -- lo confirmado), se vuelve a juzgar cada uno con la MISMA definición y, además, que nadie le haya registrado un intento
    -- DURANTE esta operación: B6 cuenta desde la «reasignación», que lleva la hora de esta sentencia, y el analista nuevo lo
    -- heredaría. Lo que no pasa queda sin repartir y bloqueado hasta el commit: r2 (Codex P2) por eso hay un PRESUPUESTO de
    -- candados acumulado —todos los tomados, aceptados o no—: greatest(pedidos + holgura, ceil(pedidos × 1,1)); si se agota
    -- antes de completar, nada (55P03, reintenta: el todo o nada se mantiene).
    v_presupuesto := greatest(v_total + v_holgura, pg_catalog.ceil(v_total * 1.1)::integer);
    loop
      v_falta := v_total - pg_catalog.cardinality(v_elegibles);
      exit when v_falta <= 0;
      if v_tomados >= v_presupuesto then
        raise exception 'Los contactos están cambiando; reintenta' using errcode = '55P03';
      end if;
      select coalesce(pg_catalog.array_agg(b.id order by b.o), '{}'), max(b.o) into v_lote, v_hasta
        from (select l.id, p.o
                from crm.leads l
                join unnest(v_pend) with ordinality as p(id, o) on p.id = l.id
               where p.o > v_marca
               order by p.o
               limit least(v_falta, v_presupuesto - v_tomados)
                 for update of l skip locked) b;
      exit when v_hasta is null;
      v_marca := v_hasta;
      v_tomados := v_tomados + pg_catalog.cardinality(v_lote);
      v_elegibles := v_elegibles || array(
        select x.id from unnest(v_lote) with ordinality as x(id, o) join crm.leads l on l.id = x.id
          join crm.base_carga_leads bl on bl.lead_id = l.id and bl.base_id = p_base_id and bl.activo  -- B10 r2
         where private.bases_carga_reparto_motivo_bloque(l.id, l.activo, l.no_contactar, l.etapa, l.vendedor_id, l.asignado_supervisor_id, l.enfriado_hasta, bl.analista_id, bl.asignado_en, bl.creado_en, v_base.supervisor_id, v_subarbol, v_hoy) is null  -- B10 r2
           and not exists (select 1 from crm.actividades a
                            where a.lead_id = l.id and a.metadata ->> 'evento' = 'intento_base' and a.creado_en >= pg_catalog.statement_timestamp())
         order by x.o);
    end loop;
    v_disponibles := pg_catalog.cardinality(v_elegibles);
    if v_disponibles < v_total then
      raise exception 'Solo hay % contactos disponibles para repartir en esta base (pediste %)', v_disponibles, v_total
        using errcode = '22023', detail = v_disponibles::text;
    end if;
    -- Los más antiguos, en el orden de las asignaciones (Ana 40 · Luis 30: Ana recibe los 40 primeros).
    for i in 1 .. pg_catalog.cardinality(a_analista) loop
      v_dest_lead := v_dest_lead || v_elegibles[v_pos + 1 : v_pos + a_cantidad[i]];
      v_dest_analista := v_dest_analista || pg_catalog.array_fill(a_analista[i], array[a_cantidad[i]]);
      v_pos := v_pos + a_cantidad[i];
    end loop;
    -- Omitidos del bloque, por motivo (lead_id null y su cantidad): los sin repartir que la foto ya descartaba, con su motivo, y
    -- los examinados que no se eligieron, con su motivo de ahora o «ocupado» (otro proceso lo tenía; reintenta).
    v_examinados := array(select p.id from unnest(v_pend) with ordinality as p(id, o) where p.o <= v_marca and not (p.id = any (v_elegibles)));
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('lead_id', null, 'motivo', g.m, 'cantidad', g.n) order by g.m), '[]'::jsonb)
      into v_omitidos
      from (select y.m, pg_catalog.cardinality(pg_catalog.array_agg(y.l)) as n
              from (select x.l, x.m from unnest(a_ev_lead, a_ev_motivo) as x(l, m) where x.m is not null
                    union all
                    select l.id, coalesce(private.bases_carga_reparto_motivo_bloque(l.id, l.activo, l.no_contactar, l.etapa, l.vendedor_id, l.asignado_supervisor_id, l.enfriado_hasta, bl.analista_id, bl.asignado_en, bl.creado_en, v_base.supervisor_id, v_subarbol, v_hoy), 'ocupado')  -- B10 r2
                      from crm.leads l
                      join crm.base_carga_leads bl on bl.lead_id = l.id and bl.base_id = p_base_id and bl.activo  -- B10 r2
                     where l.id = any (v_examinados)) y
             group by y.m) g;
    v_por_analista := (select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('analista_id', x.a, 'cantidad', x.n) order by x.o)
                         from unnest(a_analista, a_cantidad) with ordinality as x(a, n, o));
  else
    -- 5i · Todo o nada: (1) cada uno es de la base y el actor lo ve (si no, P0002 sin decir cuál existe) — r1 (auditor P3):
    -- ANTES de los candados, para no bloquear nada fuera de su alcance —; (2) candado de los pedidos, en orden de id, SKIP
    -- LOCKED; (3) bajo el candado siguen a su alcance (otra vía pudo llevárselos en el intervalo: P0002) y ninguno lo tiene otro
    -- proceso ni recibió un intento durante esta operación (55P03, reintenta); (4) cada uno se puede repartir a SU analista
    -- (22023 con los rechazados).
    if exists (select 1 from pg_catalog.unnest(a_lead) as u(id)
                where not exists (select 1 from crm.base_carga_leads bl where bl.base_id = p_base_id and bl.activo and bl.lead_id = u.id)
                   or not private.bases_carga_lead_ref(p_actor, v_rol, u.id)) then
      raise exception 'Hay contactos que no están en esta base o están fuera de tu ámbito' using errcode = 'P0002';
    end if;
    select coalesce(pg_catalog.array_agg(b.id order by b.id), '{}') into v_bloqueados
      from (select l.id from crm.leads l
             where l.id = any (a_lead)
               and l.id in (select bl.lead_id from crm.base_carga_leads bl where bl.base_id = p_base_id and bl.activo)
             order by l.id
               for update of l skip locked) b;
    if exists (select 1 from pg_catalog.unnest(a_lead) as u(id) where not private.bases_carga_lead_ref(p_actor, v_rol, u.id)) then
      raise exception 'Hay contactos que no están en esta base o están fuera de tu ámbito' using errcode = 'P0002';
    end if;
    if exists (select 1 from pg_catalog.unnest(a_lead) as u(id)
                where not (u.id = any (v_bloqueados))
                   or exists (select 1 from crm.actividades a
                               where a.lead_id = u.id and a.metadata ->> 'evento' = 'intento_base' and a.creado_en >= pg_catalog.statement_timestamp())) then
      raise exception 'Otra operación está usando alguno de esos contactos; reintenta' using errcode = '55P03';
    end if;
    for c in
      select u.lead_id, u.analista_id, bl.analista_id as bl_analista, l.activo, l.etapa, l.no_contactar, l.enfriado_hasta,
             l.vendedor_id, l.asignado_supervisor_id, bl.asignado_en as bl_asignado_en, bl.creado_en as bl_agregado_en  -- B10 r2
        from unnest(a_lead, a_analista) with ordinality as u(lead_id, analista_id, pos)
        join crm.base_carga_leads bl on bl.base_id = p_base_id and bl.activo and bl.lead_id = u.lead_id
        join crm.leads l on l.id = u.lead_id
       order by u.pos
    loop
      -- El seguimiento activo (B6) solo cuenta si el contacto CAMBIA de analista (darlo al que ya lo tiene no reasigna).
      -- r1 (Codex P2): en el ámbito también lo que B9 repartió (Gerencia) fuera del equipo del dueño: la pertenencia dice que
      -- quien lo tiene es su analista. Lo que otra vía movió fuera del equipo, no.
      v_motivo := private.bases_carga_reparto_motivo(c.activo,
                                                     private.bases_carga_en_subarbol(v_subarbol, c.vendedor_id, c.asignado_supervisor_id)
                                                       or (c.bl_analista is not null and c.bl_analista = c.vendedor_id),
                                                     c.etapa, c.no_contactar, c.enfriado_hasta,
                                                     c.vendedor_id is distinct from c.analista_id
                                                       and private.base_gestion_en_gestion_hasta(c.lead_id) is not null, v_hoy);
      -- B10 r2: con la definición única del estado, lo movido por otra vía (también dentro del equipo) tampoco se reparte;
      -- sí un sin repartir (también un armado con su analista anterior, E1) o uno que sigue con su analista.
      if v_motivo is null then
        v_estado_c := private.bases_carga_estado_contacto(c.lead_id, c.activo, c.no_contactar, c.etapa, c.vendedor_id,
                                                          c.asignado_supervisor_id, c.enfriado_hasta, c.bl_analista, c.bl_asignado_en,
                                                          c.bl_agregado_en, v_base.supervisor_id, v_subarbol, v_hoy);
        if (v_estado_c in ('sin_repartir', 'sin_tocar', 'trabajado')) is not true then
          v_motivo := coalesce(v_estado_c, 'sin_estado');  -- r4 (auditor-rls P3-1): un estado NULL no se reparte
        end if;
      end if;
      if v_motivo is not null then
        v_rechazos := v_rechazos || pg_catalog.jsonb_build_object('lead_id', c.lead_id, 'motivo', v_motivo);
      elsif c.bl_analista is not distinct from c.analista_id and c.vendedor_id is not distinct from c.analista_id then
        v_omitidos := v_omitidos || pg_catalog.jsonb_build_object('lead_id', c.lead_id, 'motivo', 'ya_asignado');
      else
        v_dest_lead := v_dest_lead || c.lead_id;
        v_dest_analista := v_dest_analista || c.analista_id;
      end if;
    end loop;
    if pg_catalog.jsonb_array_length(v_rechazos) > 0 then
      raise exception '% de los contactos pedidos no se pueden repartir (en gestión, en descanso, No contactar o fuera de la base); no se repartió ninguno',
        pg_catalog.jsonb_array_length(v_rechazos)
        using errcode = '22023', detail = pg_catalog.jsonb_build_object('rechazados', v_rechazos)::text;
    end if;
    v_por_analista := coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('analista_id', g.a, 'cantidad', g.n) order by g.o)
                                  from (select x.a, pg_catalog.cardinality(pg_catalog.array_agg(x.l)) as n, min(x.o) as o
                                          from unnest(v_dest_lead, v_dest_analista) with ordinality as x(l, a, o) group by x.a) g), '[]'::jsonb);
  end if;

  -- 6 · El reparto: el lead al analista (sigue descartado), por el camino de la casa (todos sus candados corren); y la
  -- pertenencia con su analista, cuándo (después de los candados) y quién.
  v_ahora := pg_catalog.clock_timestamp();
  begin
    update crm.leads l
       set vendedor_id = x.analista, asignado_supervisor_id = null
      from unnest(v_dest_lead, v_dest_analista) as x(lead, analista)
     where l.id = x.lead
       and (l.vendedor_id is distinct from x.analista or l.asignado_supervisor_id is not null);
    get diagnostics v_upd = row_count;
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate;
    if private.bases_carga_error_transitorio(v_estado) then
      raise exception using errcode = v_estado, message = pg_catalog.format('El reparto se interrumpió (%s); reintenta', v_estado);
    end if;
    raise exception using errcode = v_estado, message = pg_catalog.format('No se pudo repartir (%s); no se repartió ninguno', v_estado);
  end;
  update crm.base_carga_leads bl
     set analista_id = x.analista, asignado_en = v_ahora, asignado_por = p_actor
    from unnest(v_dest_lead, v_dest_analista) as x(lead, analista)
   where bl.base_id = p_base_id and bl.activo and bl.lead_id = x.lead;
  get diagnostics v_n = row_count;
  if v_n is distinct from pg_catalog.cardinality(v_dest_lead) then
    raise exception 'El reparto no quedó como se previó' using errcode = 'P0001';
  end if;

  v_resp := pg_catalog.jsonb_build_object('ok', true, 'operacion_id', p_operacion_id, 'base_id', p_base_id, 'modo', v_modo,
                                          'repartidos', pg_catalog.cardinality(v_dest_lead), 'por_analista', v_por_analista,
                                          'omitidos', v_omitidos);
  insert into crm.base_carga_operaciones (actor, operacion_id, base_id, tipo, pedido_md5, respuesta)
  values (p_actor, p_operacion_id, p_base_id, 'repartir', v_md5, v_resp);
  return v_resp;
end;
$function$;

-- El clasificador de B9 ya no tiene llamadores (contactos_core usa la definición única): se BORRA para que no quede una
-- segunda definición del estado. La reversa lo repone byte a byte.
drop function private.bases_carga_reparto_estado(boolean, boolean, text, uuid, boolean, date, uuid, boolean, boolean, boolean, boolean, date);

-- ── 2 · La lista de la base para gestión (drop + create sobre el texto vivo de B6b) ───────────────────────────────────
drop function crm.obtener_base_gestion(uuid, boolean);
create function crm.obtener_base_gestion(p_vendedor_id uuid DEFAULT NULL::uuid, p_incluir_vetados boolean DEFAULT false)
 RETURNS TABLE(lead_id uuid, nombre_completo text, telefono text, distrito text, origen text, categoria_interes text, monto_estimado numeric, moneda text, motivo_descarte text, descartado_en timestamp with time zone, dias_desde_descarte integer, etapa_maxima text, intentos integer, ultimo_resultado text, ultimo_intento_en timestamp with time zone, proxima_llamada_en timestamp with time zone, rellamada_hoy boolean, enfriado_hasta date, ciclo_n integer, vendedor_id uuid, gestiona text, recibido_en timestamp with time zone, no_contactar boolean, no_contactar_en timestamp with time zone, no_contactar_motivo text, no_contactar_por text, base_id uuid, base_nombre text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_vetados boolean := coalesce(p_incluir_vetados, false);  -- B6b: null = false
  v_bases uuid[];  -- B10 r1: las bases VIVAS que ve quien llama (auditor-rls r1, P3)
begin
  v_rol := private.base_gestion_rol(v_uid);
  -- B6b (Miguel, 03/10/2026): los leads «No contactar» solo los ven Supervisión y Gerencia, y solo si los piden.
  if v_vetados and (v_rol in ('supervisor', 'gerencia')) is not true then
    raise exception 'Solo Supervision y Gerencia ven los leads marcados No contactar' using errcode = '42501';
  end if;
  if p_vendedor_id is not null then
    if v_rol = 'vendedor' and p_vendedor_id <> v_uid then
      raise exception 'Un analista solo consulta su propia base' using errcode = '42501';
    end if;
    if v_rol = 'supervisor' and p_vendedor_id not in (select private.vendedor_ids_visibles(v_uid)) then
      raise exception 'Analista no encontrado o fuera de tu ambito' using errcode = 'P0002';
    end if;
  end if;
  -- B10 r1: una vez, no por fila (espejo de la policy bases_carga_select: private.bases_carga_base_visible).
  v_bases := array(select b.id from crm.bases_carga b where b.activo and private.bases_carga_base_visible(v_uid, v_rol, b.supervisor_id));
  return query
  with bs as materialized (
    -- B10 r2: cada base VIVA con el subárbol de su dueño, una vez (lo usa la definición única del estado)
    select b.id, b.nombre, b.supervisor_id, array(select private.bases_carga_subarbol(b.supervisor_id)) as subarbol
      from crm.bases_carga b
     where b.activo
  ),
  base as (
    select l.id, l.nombre_completo, l.telefono, l.distrito, l.origen, l.categoria_interes, l.monto_estimado, l.moneda,
           l.motivo_descarte, l.descartado_en, l.proxima_llamada_en, l.enfriado_hasta, l.ciclo_actual, l.vendedor_id,
           coalesce(l.tenencia_desde, l.creado_en) as recibido_en,  -- B5: cuando le llego el lead a quien lo tiene (el MES del lead)
           l.no_contactar,  -- B6b: solo puede venir en true si se pidieron los vetados
           l.inversionista_id, l.dni,  -- B6b: para resolver la persona del lead (no se devuelven)
           private.base_gestion_intentos_desde(l.descartado_en, l.creado_en, l.enfriado_hasta, v_hoy) as desde,  -- D13: ventana desde el descarte o desde el fin del ultimo descanso
           -- B10 r1: la base VIVA del lead (NULL si no esta en una), solo si quien llama ve la BASE o es el analista del lead
           case when bc.id is not null and (l.vendedor_id = v_uid or bc.id = any (v_bases)) then bc.id end as base_id,
           case when bc.id is not null and (l.vendedor_id = v_uid or bc.id = any (v_bases)) then bc.nombre end as base_nombre
    from crm.leads l
    left join crm.base_carga_leads bl on bl.lead_id = l.id and bl.activo  -- B10: a lo sumo una (indice unico de la pertenencia viva)
    left join bs bc on bc.id = bl.base_id  -- B10 r2: la base VIVA (CTE bs, con el subárbol de su dueño)
    where l.activo and l.etapa = 'descartado' and (not l.no_contactar or v_vetados)  -- B6b: los vetados, solo a pedido
      and (l.enfriado_hasta is null or l.enfriado_hasta <= v_hoy or (v_vetados and l.no_contactar))  -- B6b: un vetado en descanso tambien se ve; un no vetado en descanso, no
      and private.base_gestion_lead_visible(v_uid, v_rol, l.vendedor_id, l.asignado_supervisor_id)
      and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
      and (bc.id is null  -- B10 r3: los DORMIDOS del archivo sin repartir de una base viva viven en la pestaña Bases; un armado
           -- desde el CRM nunca se oculta (sigue con su analista anterior). Sin repartir = la definicion unica de B9 y B10.
           or bl.procedencia is distinct from 'archivo'
           or bl.analista_id is not null  -- con reparto, la definicion nunca da sin_repartir: no se calcula (rendimiento)
           or private.bases_carga_estado_contacto(l.id, l.activo, l.no_contactar, l.etapa, l.vendedor_id, l.asignado_supervisor_id,
                                                  l.enfriado_hasta, bl.analista_id, bl.asignado_en, bl.creado_en, bc.supervisor_id,
                                                  bc.subarbol, v_hoy) is distinct from 'sin_repartir')
  ),
  intentos as (
    -- B3c: contador, último resultado (desempate por intento_n, Codex B3 #5) y último intento salen de la MISMA definición
    -- que usan el núcleo y el enfriamiento: private.base_gestion_intentos_ciclo, con la ventana D13 de cada lead.
    select c.lead_id, c.n, c.ultimo, c.ultimo_en
    from (select array_agg(b.id order by b.id) as ids, array_agg(b.desde order by b.id) as desdes from base b) q
    cross join lateral private.base_gestion_intentos_ciclo(q.ids, q.desdes) c
  ),
  ciclo as (
    -- El ciclo vigente empieza en la ultima reapertura (cambio_etapa descartado → nuevo) o, si nunca hubo, al inicio.
    -- Se acota con el propio historial (misma fuente y mismo reloj que los cambios de etapa): robusto frente a
    -- transacciones multi-sentencia, donde now() del log y statement_timestamp() del ledger difieren.
    select b.id as lead_id,
           coalesce((select max(a.creado_en) from crm.actividades a
                      where a.lead_id = b.id and a.tipo = 'cambio_etapa' and a.metadata->>'etapa_anterior' = 'descartado'),
                    '-infinity'::timestamptz) as desde
    from base b
  ),
  etapas as (
    select a.lead_id,
           max(greatest(private.base_gestion_etapa_rango(a.metadata->>'etapa_anterior'),
                        private.base_gestion_etapa_rango(case when a.metadata->>'etapa_nueva' <> 'descartado' then a.metadata->>'etapa_nueva' end))) as rango
    from crm.actividades a join ciclo c on c.lead_id = a.lead_id
    where a.tipo = 'cambio_etapa' and a.creado_en >= c.desde
      -- Codex B3 #6: el descarte del ciclo anterior puede compartir instante con la reapertura (misma transaccion): fuera.
      and not (a.creado_en = c.desde and a.metadata->>'etapa_nueva' = 'descartado')
    group by a.lead_id
  ),
  marca as (
    -- B6b: cuándo, por qué y quién marcó «No contactar». Evento vigente del veto: si el lead tiene persona y la persona está
    -- vetada, la ÚLTIMA nota del veto entre TODOS los leads de la persona (los que marcar/levantar/postventa actualizan); si
    -- no, la última nota del propio lead. Se muestra solo si ese evento es un «marcar» y su lead es visible para quien llama.
    select b.id as lead_id, ev.creado_en, ev.motivo, ev.creado_por
    from base b
    cross join lateral (
      -- La persona, EXACTAMENTE como la resuelven marcar/levantar: enlace; si no, puente (canónica); si no, DNI.
      select coalesce(b.inversionista_id,
                      (select private.inversionista_canonica(il.inversionista_id) from crm.inversionista_leads il
                        where il.lead_id = b.id order by (il.rol = 'canonico') desc, il.inversionista_id limit 1),
                      private.inversionista_por_documento('DNI', b.dni)) as id
    ) pe
    left join crm.inversionistas i on i.id = pe.id
    cross join lateral (
      -- La más reciente entre las ÚLTIMAS notas de cada lead del conjunto: cada una sale del índice (lead_id, creado_en desc).
      select n.ev_lead, n.creado_en, n.accion, n.creado_por, n.motivo
        from (select b.id as lid
              union
              select x from private.leads_de_persona_veto(pe.id) x where i.no_contactar is true) s  -- el conjunto de las puertas
        cross join lateral (
          select a.lead_id as ev_lead, a.creado_en, a.id, a.metadata->>'accion' as accion, a.creado_por,
                 coalesce(a.metadata->>'motivo',
                          case when a.metadata ? 'postventa_gestion_id' then pg_catalog.regexp_replace(a.detalle, '^No contactar: ', '') end) as motivo
            from crm.actividades a
           where a.lead_id = s.lid and a.metadata->>'evento' = 'no_contactar'
           order by a.creado_en desc, a.id desc
           limit 1
        ) n
       order by n.creado_en desc, n.id desc
       limit 1
    ) ev
    join crm.leads le on le.id = ev.ev_lead
    where b.no_contactar and ev.accion = 'marcar'
      and le.activo and private.base_gestion_lead_visible(v_uid, v_rol, le.vendedor_id, le.asignado_supervisor_id)  -- nada de otro equipo
  )
  select b.id, b.nombre_completo, b.telefono, b.distrito, b.origen, b.categoria_interes, b.monto_estimado, b.moneda,
         b.motivo_descarte, b.descartado_en,
         case when b.descartado_en is null then null else (v_hoy - (b.descartado_en at time zone 'America/Lima')::date)::integer end,
         case coalesce(e.rango, 0) when 1 then 'nuevo' when 2 then 'contactado' when 3 then 'reunion_agendada'
                                   when 4 then 'propuesta_enviada' when 5 then 'convertido' else 'sin_datos' end,
         coalesce(i.n, 0), i.ultimo, i.ultimo_en,
         b.proxima_llamada_en,
         (not b.no_contactar and b.proxima_llamada_en is not null and (b.proxima_llamada_en at time zone 'America/Lima')::date <= v_hoy),  -- B6b: un vetado nunca va a «Llamar hoy»
         b.enfriado_hasta, b.ciclo_actual, b.vendedor_id, p.nombre_completo, b.recibido_en,
         b.no_contactar, m.creado_en, m.motivo, pm.nombre_completo,
         b.base_id, b.base_nombre  -- B10
  from base b
  left join intentos i on i.lead_id = b.id
  left join etapas e on e.lead_id = b.id
  left join public.perfiles p on p.id = b.vendedor_id
  left join marca m on m.lead_id = b.id
  left join public.perfiles pm on pm.id = m.creado_por
  -- Contrato (encargo): rellamada vencida o de hoy → etapa maxima (desc) → dias desde el descarte (asc); la hora de la
  -- rellamada solo desempata (Codex B3 #4). B6b: los vetados, al final (sin vetados el orden es el de B5).
  order by b.no_contactar,
           (not b.no_contactar and b.proxima_llamada_en is not null and (b.proxima_llamada_en at time zone 'America/Lima')::date <= v_hoy) desc,
           coalesce(e.rango, 0) desc,
           (b.descartado_en at time zone 'America/Lima')::date desc nulls last,  -- menos dias desde el descarte primero
           b.proxima_llamada_en asc nulls last,
           b.id;
end;
$function$;
alter function crm.obtener_base_gestion(uuid, boolean) owner to postgres;
revoke all on function crm.obtener_base_gestion(uuid, boolean) from public, anon, authenticated, service_role;
grant execute on function crm.obtener_base_gestion(uuid, boolean) to authenticated;

-- ── 3 · Puertas del seguimiento (DEFINER: las tablas de bases no tienen grants; validan, resuelven rol y ámbito y leen) ──
create function crm.seguimiento_bases()
returns table(base_id uuid, nombre text, origen text, supervisor_id uuid, supervisor_nombre text, creado_en timestamptz,
              total integer, sin_repartir integer, repartidos integer, sin_tocar integer, trabajados integer,
              en_descanso integer, citas integer, reactivados integer, avance numeric,
              movidos_otra_via integer, retirados integer, no_contactar integer)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.bases_carga_seguimiento_rol(v_uid);
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_ids uuid[];
begin
  -- Las bases VIVAS que el actor ve: Supervisión, las de su subárbol; Gerencia, todas (espejo de la policy).
  select coalesce(pg_catalog.array_agg(b.id), '{}') into v_ids
    from crm.bases_carga b
   where b.activo and private.bases_carga_base_visible(v_uid, v_rol, b.supervisor_id);
  return query
  with c as (
    select x.base_id as id,
           count(*) filter (where 'total' = any (x.cifras))::integer as n_total,
           count(*) filter (where 'sin_repartir' = any (x.cifras))::integer as n_sin_repartir,
           count(*) filter (where 'repartidos' = any (x.cifras))::integer as n_repartidos,
           count(*) filter (where 'sin_tocar' = any (x.cifras))::integer as n_sin_tocar,
           count(*) filter (where 'trabajados' = any (x.cifras))::integer as n_trabajados,
           count(*) filter (where 'en_descanso' = any (x.cifras))::integer as n_en_descanso,
           count(*) filter (where 'citas' = any (x.cifras))::integer as n_citas,
           count(*) filter (where 'reactivados' = any (x.cifras))::integer as n_reactivados,
           count(*) filter (where 'movidos_otra_via' = any (x.cifras))::integer as n_movidos,
           count(*) filter (where 'retirados' = any (x.cifras))::integer as n_retirados,
           count(*) filter (where 'no_contactar' = any (x.cifras))::integer as n_no_contactar
      from private.bases_carga_seguimiento_filas(v_ids, v_hoy) x
     group by x.base_id
  )
  select b.id, b.nombre, b.origen, b.supervisor_id, p.nombre_completo, b.creado_en,
         coalesce(c.n_total, 0), coalesce(c.n_sin_repartir, 0), coalesce(c.n_repartidos, 0), coalesce(c.n_sin_tocar, 0),
         coalesce(c.n_trabajados, 0), coalesce(c.n_en_descanso, 0), coalesce(c.n_citas, 0), coalesce(c.n_reactivados, 0),
         case when coalesce(c.n_repartidos, 0) > 0 then pg_catalog.round(c.n_trabajados::numeric / c.n_repartidos, 4)
              else 0.0000 end,
         coalesce(c.n_movidos, 0), coalesce(c.n_retirados, 0), coalesce(c.n_no_contactar, 0)
    from crm.bases_carga b
    left join c on c.id = b.id
    left join public.perfiles p on p.id = b.supervisor_id
   where b.id = any (v_ids)
   order by b.creado_en desc, b.id;
end;
$function$;

create function crm.seguimiento_base(p_base_id uuid)
returns table(analista_id uuid, analista_nombre text, asignados integer, sin_tocar integer, sin_tocar_3_dias integer,
              trabajados integer, en_descanso integer, citas integer, reactivados integer, ultimo_intento_en timestamptz,
              movidos_otra_via integer, retirados integer, no_contactar integer)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.bases_carga_seguimiento_rol(v_uid);
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
begin
  perform private.bases_carga_seguimiento_exigir_base(v_uid, v_rol, p_base_id);
  return query
  with vis as (
    -- r4 (Codex r2, P2): el ámbito del actor, una vez. Gerencia ve a todos: nunca tiene fila anónima.
    select array(select private.vendedor_ids_visibles(v_uid)) as ids
  ),
  c as (
    -- Una fila por analista del ámbito; TODOS los de fuera, en UNA fila anónima (id NULL): cifras sumadas, último intento máximo.
    select case when v_rol = 'gerencia' or x.analista_id = any (vis.ids) then x.analista_id end as id,
           count(*) filter (where 'asignados' = any (x.cifras))::integer as n_asignados,
           count(*) filter (where 'sin_tocar' = any (x.cifras))::integer as n_sin_tocar,
           count(*) filter (where 'sin_tocar_3_dias' = any (x.cifras))::integer as n_sin_tocar_3_dias,
           count(*) filter (where 'trabajados' = any (x.cifras))::integer as n_trabajados,
           count(*) filter (where 'en_descanso' = any (x.cifras))::integer as n_en_descanso,
           count(*) filter (where 'citas' = any (x.cifras))::integer as n_citas,
           count(*) filter (where 'reactivados' = any (x.cifras))::integer as n_reactivados,
           pg_catalog.max(x.ultimo_intento_en) as ultimo,
           count(*) filter (where 'movidos_otra_via' = any (x.cifras))::integer as n_movidos,
           count(*) filter (where 'retirados' = any (x.cifras))::integer as n_retirados,
           count(*) filter (where 'no_contactar' = any (x.cifras))::integer as n_no_contactar
      from private.bases_carga_seguimiento_filas(array[p_base_id], v_hoy) x
      cross join vis
     where x.analista_id is not null
     group by 1
  )
  -- El analista (id y nombre) solo si está en el ámbito del actor (auditor-rls r1, P3); los de otro equipo (Gerencia puede
  -- repartir a cualquiera, E11) salen juntos, sin identificar, en la última fila: se abren por la base.
  select c.id, p.nombre_completo, c.n_asignados, c.n_sin_tocar, c.n_sin_tocar_3_dias,
         c.n_trabajados, c.n_en_descanso, c.n_citas, c.n_reactivados, c.ultimo, c.n_movidos, c.n_retirados, c.n_no_contactar
    from c
    left join public.perfiles p on p.id = c.id
   order by (c.id is null), p.nombre_completo, c.id;
end;
$function$;

create function crm.seguimiento_base_detalle(p_base_id uuid, p_analista_id uuid default null, p_cifra text default null)
returns table(lead_id uuid, nombre_completo text, estado text, asignado_en timestamptz, ultimo_intento_en timestamptz,
              ultimo_resultado text)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.bases_carga_seguimiento_rol(v_uid);
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
begin
  if (p_cifra = any (private.bases_carga_seguimiento_cifras())) is not true then
    raise exception 'Cifra inválida: se espera una de %', pg_catalog.array_to_string(private.bases_carga_seguimiento_cifras(), ', ')
      using errcode = '22023';
  end if;
  perform private.bases_carga_seguimiento_exigir_base(v_uid, v_rol, p_base_id);
  -- r4 (Codex r2, P2): un analista explícito, PRIMERO en el ámbito del actor (Gerencia: cualquiera) y después con contactos en
  -- la base; los dos casos con el MISMO P0002 (un UUID externo no se puede atribuir ni sondear).
  if p_analista_id is not null
     and v_rol is distinct from 'gerencia'
     and (p_analista_id in (select private.vendedor_ids_visibles(v_uid))) is not true then
    raise exception 'Analista no encontrado en esta base' using errcode = 'P0002';
  end if;
  if p_analista_id is not null
     and not exists (select 1 from crm.base_carga_leads bl
                      where bl.base_id = p_base_id and bl.activo and bl.analista_id = p_analista_id) then
    raise exception 'Analista no encontrado en esta base' using errcode = 'P0002';
  end if;
  -- Las MISMAS filas que cuentan las cifras (el arreglo cifras de private.bases_carga_seguimiento_filas). lead_id y nombre,
  -- solo si el actor ve el lead y sigue activo (private.bases_carga_lead_ref, B8): si no, la fila cuenta sin delatar quién es.
  return query
  select case when r.ve then x.lead_id end, case when r.ve then x.nombre_completo end, x.estado, x.asignado_en,
         x.ultimo_intento_en, x.ultimo_resultado
    from private.bases_carga_seguimiento_filas(array[p_base_id], v_hoy) x
    cross join lateral (select private.bases_carga_lead_ref(v_uid, v_rol, x.lead_id) as ve) r
   where (p_analista_id is null or x.analista_id = p_analista_id)
     and p_cifra = any (x.cifras)
   order by x.asignado_en desc nulls last, x.ultimo_intento_en desc nulls last, x.lead_id;
end;
$function$;

-- ── 4 · Capital al reactivar: el núcleo con capital (una sola definición), el de 4 argumentos como envoltorio y la _v2 ──
create function private.base_gestion_reactivar_capital_core(p_actor uuid, p_operacion_id uuid, p_lead_id uuid, p_nota text,
                                                            p_monto_estimado numeric, p_moneda text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_rol text;
  v_lead crm.leads%rowtype;
  v_prev jsonb;
  v_n integer;
  v_guc text;
  v_resp jsonb;
  v_reabrir jsonb;
begin
  if p_actor is null or p_operacion_id is null or p_lead_id is null then
    raise exception 'Operacion, lead y actor son obligatorios' using errcode = '22023';
  end if;
  v_rol := private.base_gestion_rol(p_actor);
  if length(coalesce(p_nota, '')) > 2000 then
    raise exception 'La nota supera los 2000 caracteres' using errcode = '22023';
  end if;
  -- Candados de la casa: persona ANTES que lead (como llamada_registrar y marcar_no_contactar); reabrir_lead_fn los
  -- vuelve a tomar dentro de la misma transaccion sin esperar.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'Reactivar requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  perform private.bloquear_personas_de_leads(array[p_lead_id], null);
  select * into v_lead from crm.leads where id = p_lead_id for update;
  -- Idempotencia DESPUES del candado del lead: dos clics concurrentes → el segundo espera y recibe el replay.
  select a.metadata->'respuesta' into v_prev from crm.actividades a where a.id = p_operacion_id and a.creado_por = p_actor;
  if found then
    -- B10 r1 (Codex, riesgo): el capital pedido es parte de la identidad de la operacion (como la nota del intento).
    if v_prev is null or (v_prev->>'lead_id')::uuid is distinct from p_lead_id or v_prev->>'evento' is distinct from 'reactivacion_base'
       or (v_prev->>'solicitud_monto')::numeric is distinct from p_monto_estimado or v_prev->>'solicitud_moneda' is distinct from p_moneda then
      raise exception 'Esta operacion ya corresponde a otro contenido' using errcode = '23505';
    end if;
    return v_prev || jsonb_build_object('replay', true);
  end if;
  if v_lead.id is null or not v_lead.activo
     or not private.base_gestion_lead_visible(p_actor, v_rol, v_lead.vendedor_id, v_lead.asignado_supervisor_id) then
    raise exception 'Lead no encontrado o fuera de tu ambito' using errcode = 'P0002';
  end if;
  if v_lead.etapa <> 'descartado' then
    raise exception 'El lead ya no esta en la base (no esta descartado)' using errcode = '22023';
  end if;
  if v_lead.no_contactar then
    raise exception 'No insistir: el lead esta marcado No contactar' using errcode = 'P0429';
  end if;
  -- B10 (E8): un contacto sin capital (base cargada) no sale del descarte sin el: se pide aqui, ANTES de reabrir (el
  -- CHECK leads_monto_estimado_valido rechazaria la reapertura), y el episodio que abre la reapertura nace con ese capital.
  -- Con capital ya puesto, p_monto_estimado y p_moneda se ignoran. p_moneda NULL = la moneda que ya tiene el lead.
  if v_lead.monto_estimado is null then
    if p_monto_estimado is null then
      raise exception 'Indica el capital estimado para reactivar' using errcode = '22023';
    end if;
    if (p_monto_estimado > 0 and p_monto_estimado <= 9999999999.99 and p_monto_estimado = trunc(p_monto_estimado, 2)) is not true then
      raise exception 'El capital estimado debe ser mayor que 0, de hasta 9999999999.99 y con 2 decimales como maximo' using errcode = '22023';
    end if;
    if p_moneda is not null and (p_moneda in ('PEN', 'USD')) is not true then
      raise exception 'La moneda del capital es PEN o USD' using errcode = '22023';
    end if;
    update crm.leads set monto_estimado = p_monto_estimado, moneda = coalesce(p_moneda, moneda) where id = p_lead_id;
  end if;
  -- 1. Reabrir por la puerta sellada (→ nuevo, ciclo nuevo, SLA reiniciado, veto de persona verificado).
  v_reabrir := crm.reabrir_lead_fn(p_lead_id);
  -- 2. En la misma transaccion, a «contactado» (D1): el guard de tenencia lo permite porque ya old.etapa = nuevo.
  update crm.leads set etapa = 'contactado' where id = p_lead_id and activo and etapa = 'nuevo';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'No se pudo avanzar el lead reabierto a contactado' using errcode = 'P0001';
  end if;
  -- 3. Sello de la base: marca de reactivacion, sin rellamada ni descanso.
  v_guc := coalesce(pg_catalog.current_setting('crm.op_base_gestion', true), 'off');
  perform pg_catalog.set_config('crm.op_base_gestion', 'on', true);
  update crm.leads set reactivado_en = now(), proxima_llamada_en = null, enfriado_hasta = null where id = p_lead_id;
  perform pg_catalog.set_config('crm.op_base_gestion', v_guc, true);
  select * into v_lead from crm.leads where id = p_lead_id;
  v_resp := jsonb_build_object('ok', true, 'evento', 'reactivacion_base', 'lead_id', p_lead_id, 'etapa', v_lead.etapa,
                               'reactivado_en', v_lead.reactivado_en, 'ciclo_n', v_lead.ciclo_actual,
                               'reabierto_por', v_reabrir->>'reabierto_por', 'replay', false)
            -- B10 r1: el capital EFECTIVO del lead y el pedido (identidad del replay)
            || jsonb_build_object('monto_estimado', v_lead.monto_estimado, 'moneda', v_lead.moneda,
                                  'solicitud_monto', p_monto_estimado, 'solicitud_moneda', p_moneda);
  -- 4. Historial (D9): la linea de la reactivacion, con la respuesta para la idempotencia, bajo el sello de actividades.
  perform pg_catalog.set_config('crm.op_base_gestion', 'on', true);
  insert into crm.actividades (id, lead_id, tipo, detalle, metadata, creado_por)
  values (p_operacion_id, p_lead_id, 'nota', coalesce(nullif(pg_catalog.btrim(p_nota), ''), 'Reactivado desde la base para gestión'),
          jsonb_build_object('evento', 'reactivacion_base', 'via', 'base_gestion', 'etapa', 'contactado',
                             'ciclo_n', v_lead.ciclo_actual, 'respuesta', v_resp),
          p_actor);
  perform pg_catalog.set_config('crm.op_base_gestion', v_guc, true);
  return v_resp;
end;
$function$;

-- Misma firma, mismo DEFINER, search_path y ACL ({postgres=X/postgres}: CREATE OR REPLACE no la cambia); el cuerpo delega.
create or replace function private.base_gestion_reactivar_core(p_actor uuid, p_operacion_id uuid, p_lead_id uuid, p_nota text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  -- B10: la definición vive en private.base_gestion_reactivar_capital_core; por aquí, sin capital (la puerta publicada y el
  -- intento «agendó cita»): un lead sin capital → 22023 «Indica el capital estimado para reactivar».
  return private.base_gestion_reactivar_capital_core(p_actor, p_operacion_id, p_lead_id, p_nota, null::numeric, null::text);
end;
$function$;

create function private.base_gestion_intento_capital_core(p_actor uuid, p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_nota text,
                                                          p_proxima timestamp with time zone, p_monto_estimado numeric, p_moneda text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_rol text;
  v_c record;
  v_lead crm.leads%rowtype;
  v_prev jsonb;
  v_n integer;
  v_tipo text;
  v_guc1 text;
  v_guc2 text;
  v_meta jsonb;
  v_resp jsonb;
  v_react jsonb;
  v_hoy date := (now() at time zone 'America/Lima')::date;
begin
  if p_actor is null or p_operacion_id is null or p_lead_id is null then
    raise exception 'Operacion, lead y actor son obligatorios' using errcode = '22023';
  end if;
  v_rol := private.base_gestion_rol(p_actor);
  if p_resultado is null or p_resultado not in ('no_contesto', 'volver_a_llamar', 'agendo_reunion', 'no_interesado',
                                                'numero_errado', 'no_es_la_persona', 'pide_otro_producto') then
    raise exception 'Resultado de llamada invalido' using errcode = '22023';
  end if;
  select * into v_c from private.base_gestion_constantes();
  -- Validaciones de FORMA (valen igual para una operacion nueva y para su reintento).
  if p_resultado = 'volver_a_llamar' and p_proxima is null then
    raise exception 'Indica cuando volver a llamar' using errcode = '22023';
  elsif p_resultado <> 'volver_a_llamar' and p_proxima is not null then
    raise exception 'Solo "volver a llamar" lleva fecha de rellamada' using errcode = '22023';
  end if;
  if length(coalesce(p_nota, '')) > 2000 then
    raise exception 'La nota supera los 2000 caracteres' using errcode = '22023';
  end if;
  -- «agendó cita» reactivara: candados de persona ANTES del lead (protocolo de la casa).
  if p_resultado = 'agendo_reunion' then
    if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
      raise exception 'Agendar cita desde la base requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
    end if;
    perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
    perform private.bloquear_personas_de_leads(array[p_lead_id], null);
  end if;
  select * into v_lead from crm.leads where id = p_lead_id for update;
  -- Idempotencia DESPUES del candado del lead, solo entre operaciones del mismo actor y ANTES de las validaciones
  -- temporales (Codex B3 #1: el reintento de una rellamada ya vencida debe seguir devolviendo su respuesta). La identidad
  -- de la operacion incluye lead, resultado, fecha de rellamada y nota (Codex B3 #2).
  select a.metadata->'respuesta' into v_prev from crm.actividades a where a.id = p_operacion_id and a.creado_por = p_actor;
  if found then
    if v_prev is null or (v_prev->>'lead_id')::uuid is distinct from p_lead_id or v_prev->>'resultado' is distinct from p_resultado
       or v_prev->>'evento' is distinct from 'intento_base'
       or (v_prev->>'solicitud_proxima')::timestamptz is distinct from p_proxima
       or v_prev->>'nota_md5' is distinct from md5(coalesce(pg_catalog.btrim(p_nota), ''))
       -- B10 r1 (Codex, riesgo): el capital pedido es parte de la identidad de la operacion.
       or (v_prev->>'solicitud_monto')::numeric is distinct from p_monto_estimado or v_prev->>'solicitud_moneda' is distinct from p_moneda then
      raise exception 'Esta operacion ya corresponde a otro contenido' using errcode = '23505';
    end if;
    return v_prev || jsonb_build_object('replay', true);
  end if;
  -- Validaciones TEMPORALES: solo para una operacion nueva.
  if p_resultado = 'volver_a_llamar' then
    if p_proxima <= now() then
      raise exception 'La rellamada debe ser futura' using errcode = '22023';
    end if;
    if p_proxima > now() + make_interval(days => v_c.dias_max_rellamada) then
      raise exception 'La rellamada se agenda como maximo % dias adelante', v_c.dias_max_rellamada using errcode = '22023';
    end if;
  end if;
  if v_lead.id is null or not v_lead.activo
     or not private.base_gestion_lead_visible(p_actor, v_rol, v_lead.vendedor_id, v_lead.asignado_supervisor_id) then
    raise exception 'Lead no encontrado o fuera de tu ambito' using errcode = 'P0002';
  end if;
  if v_lead.etapa <> 'descartado' then
    raise exception 'El lead no esta en la base (no esta descartado)' using errcode = '22023';
  end if;
  if v_lead.no_contactar then
    raise exception 'No insistir: el lead esta marcado No contactar' using errcode = 'P0429';
  end if;
  if v_lead.enfriado_hasta is not null and v_lead.enfriado_hasta > v_hoy then
    raise exception 'El lead esta en descanso hasta el %', to_char(v_lead.enfriado_hasta, 'DD/MM/YYYY') using errcode = '22023';
  end if;
  -- B3c: los intentos del ciclo se cuentan en private.base_gestion_intentos_ciclo (una sola definición, misma ventana D13).
  v_n := coalesce((select c.n from private.base_gestion_intentos_ciclo(array[p_lead_id], array[private.base_gestion_intentos_desde(v_lead.descartado_en, v_lead.creado_en, v_lead.enfriado_hasta, v_hoy)]) c), 0) + 1;  -- D13
  v_tipo := case when p_resultado in ('no_contesto', 'numero_errado', 'no_es_la_persona')
                 then 'llamada_no_contestada' else 'llamada_realizada' end;
  v_meta := jsonb_strip_nulls(jsonb_build_object(
    'evento', 'intento_base', 'via', 'base_gestion', 'resultado', p_resultado, 'intento_n', v_n,
    'ciclo_n', v_lead.ciclo_actual, 'proxima_llamada_en', p_proxima));  -- to_jsonb(timestamptz): ISO con zona, nunca ::text
  v_guc1 := coalesce(pg_catalog.current_setting('crm.op_resultado_llamada', true), 'off');
  v_guc2 := coalesce(pg_catalog.current_setting('crm.op_base_gestion', true), 'off');
  perform pg_catalog.set_config('crm.op_resultado_llamada', 'on', true);
  perform pg_catalog.set_config('crm.op_base_gestion', 'on', true);
  insert into crm.actividades (id, lead_id, tipo, detalle, metadata, creado_por)
  values (p_operacion_id, p_lead_id, v_tipo, nullif(pg_catalog.btrim(p_nota), ''), v_meta, p_actor);
  update crm.leads set proxima_llamada_en = case when p_resultado = 'volver_a_llamar' then p_proxima else null end
   where id = p_lead_id
     and proxima_llamada_en is distinct from case when p_resultado = 'volver_a_llamar' then p_proxima else null end;
  perform pg_catalog.set_config('crm.op_resultado_llamada', v_guc1, true);
  perform pg_catalog.set_config('crm.op_base_gestion', v_guc2, true);
  -- «agendó cita» reactiva en la misma transaccion (D3); la cita se agenda despues por el flujo normal del lead vivo.
  if p_resultado = 'agendo_reunion' then
    -- Codex B3 #3: la operacion hija lleva un uuid NUEVO (no derivable del padre) y no puede ser un replay ajeno; la
    -- idempotencia del conjunto la da la operacion padre.
    -- B10 (E8): con el capital del intento (obligatorio si el lead no lo tiene: lo exige el núcleo de reactivar).
    v_react := private.base_gestion_reactivar_capital_core(p_actor, gen_random_uuid(), p_lead_id, 'Agendó cita desde la base para gestión',
                                                           p_monto_estimado, p_moneda);
    if coalesce((v_react->>'replay')::boolean, false) or v_react->>'etapa' is distinct from 'contactado' then
      raise exception 'La reactivacion de "agendo cita" no se completo' using errcode = 'P0001';
    end if;
  end if;
  select * into v_lead from crm.leads where id = p_lead_id;  -- tras el trigger de enfriamiento (B4) y la reactivacion
  v_resp := jsonb_build_object('ok', true, 'evento', 'intento_base', 'lead_id', p_lead_id, 'actividad_id', p_operacion_id,
                               'resultado', p_resultado, 'intento_n', v_n, 'ciclo_n', v_meta->>'ciclo_n',
                               'proxima_llamada_en', v_lead.proxima_llamada_en, 'enfriado_hasta', v_lead.enfriado_hasta,
                               'reactivado', v_react is not null, 'etapa', v_lead.etapa, 'replay', false,
                               'solicitud_proxima', p_proxima, 'nota_md5', md5(coalesce(pg_catalog.btrim(p_nota), '')))
            -- B10 r1: el capital EFECTIVO del lead y el pedido (identidad del replay)
            || jsonb_build_object('monto_estimado', v_lead.monto_estimado, 'moneda', v_lead.moneda,
                                  'solicitud_monto', p_monto_estimado, 'solicitud_moneda', p_moneda);
  perform pg_catalog.set_config('crm.op_resultado_llamada', 'on', true);
  perform pg_catalog.set_config('crm.op_base_gestion', 'on', true);
  update crm.actividades set metadata = metadata || jsonb_build_object('respuesta', v_resp) where id = p_operacion_id;
  perform pg_catalog.set_config('crm.op_resultado_llamada', v_guc1, true);
  perform pg_catalog.set_config('crm.op_base_gestion', v_guc2, true);
  return v_resp;
end;
$function$;

-- Misma firma, mismo DEFINER, search_path y ACL; el cuerpo delega (sin capital).
create or replace function private.base_gestion_intento_core(p_actor uuid, p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_nota text,
                                                             p_proxima timestamp with time zone)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  -- B10: la definición vive en private.base_gestion_intento_capital_core; por aquí, sin capital (la puerta publicada): un
  -- «agendó cita» sobre un lead sin capital → 22023 «Indica el capital estimado para reactivar».
  return private.base_gestion_intento_capital_core(p_actor, p_operacion_id, p_lead_id, p_resultado, p_nota, p_proxima, null::numeric, null::text);
end;
$function$;

create function crm.registrar_intento_base_v2(p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_nota text default null,
                                              p_proxima_llamada timestamptz default null, p_monto_estimado numeric default null,
                                              p_moneda text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'No autorizado' using errcode = '42501'; end if;
  return private.base_gestion_intento_capital_core(v_uid, p_operacion_id, p_lead_id, p_resultado, p_nota, p_proxima_llamada,
                                                    p_monto_estimado, p_moneda);
end;
$function$;

create function crm.reactivar_lead_base_v2(p_operacion_id uuid, p_lead_id uuid, p_nota text default null,
                                           p_monto_estimado numeric default null, p_moneda text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'No autorizado' using errcode = '42501'; end if;
  return private.base_gestion_reactivar_capital_core(v_uid, p_operacion_id, p_lead_id, p_nota, p_monto_estimado, p_moneda);
end;
$function$;

-- ── 5 · Dueños y permisos: EXECUTE de las puertas solo para authenticated; el núcleo y los ayudantes, para nadie ────────
alter function private.bases_carga_estado_contacto(uuid, boolean, boolean, text, uuid, uuid, date, uuid, timestamptz, timestamptz, uuid, uuid[], date, boolean, boolean, boolean) owner to postgres;
alter function private.bases_carga_reparto_motivo_bloque(uuid, boolean, boolean, text, uuid, uuid, date, uuid, timestamptz, timestamptz, uuid, uuid[], date) owner to postgres;
alter function private.bases_carga_seguimiento_cifras() owner to postgres;
alter function private.bases_carga_seguimiento_rol(uuid) owner to postgres;
alter function private.bases_carga_seguimiento_exigir_base(uuid, text, uuid) owner to postgres;
alter function private.bases_carga_seguimiento_filas(uuid[], date) owner to postgres;
alter function crm.seguimiento_bases() owner to postgres;
alter function crm.seguimiento_base(uuid) owner to postgres;
alter function crm.seguimiento_base_detalle(uuid, uuid, text) owner to postgres;
alter function private.base_gestion_reactivar_capital_core(uuid, uuid, uuid, text, numeric, text) owner to postgres;
alter function crm.reactivar_lead_base_v2(uuid, uuid, text, numeric, text) owner to postgres;
alter function private.base_gestion_intento_capital_core(uuid, uuid, uuid, text, text, timestamptz, numeric, text) owner to postgres;
alter function crm.registrar_intento_base_v2(uuid, uuid, text, text, timestamptz, numeric, text) owner to postgres;

revoke all on function private.bases_carga_estado_contacto(uuid, boolean, boolean, text, uuid, uuid, date, uuid, timestamptz, timestamptz, uuid, uuid[], date, boolean, boolean, boolean) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_reparto_motivo_bloque(uuid, boolean, boolean, text, uuid, uuid, date, uuid, timestamptz, timestamptz, uuid, uuid[], date) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_seguimiento_cifras() from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_seguimiento_rol(uuid) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_seguimiento_exigir_base(uuid, text, uuid) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_seguimiento_filas(uuid[], date) from public, anon, authenticated, service_role;
revoke all on function crm.seguimiento_bases() from public, anon, authenticated, service_role;
revoke all on function crm.seguimiento_base(uuid) from public, anon, authenticated, service_role;
revoke all on function crm.seguimiento_base_detalle(uuid, uuid, text) from public, anon, authenticated, service_role;
revoke all on function private.base_gestion_reactivar_capital_core(uuid, uuid, uuid, text, numeric, text) from public, anon, authenticated, service_role;
revoke all on function crm.reactivar_lead_base_v2(uuid, uuid, text, numeric, text) from public, anon, authenticated, service_role;
revoke all on function private.base_gestion_intento_capital_core(uuid, uuid, uuid, text, text, timestamptz, numeric, text) from public, anon, authenticated, service_role;
revoke all on function crm.registrar_intento_base_v2(uuid, uuid, text, text, timestamptz, numeric, text) from public, anon, authenticated, service_role;
grant execute on function crm.seguimiento_bases() to authenticated;
grant execute on function crm.seguimiento_base(uuid) to authenticated;
grant execute on function crm.seguimiento_base_detalle(uuid, uuid, text) to authenticated;
grant execute on function crm.reactivar_lead_base_v2(uuid, uuid, text, numeric, text) to authenticated;
grant execute on function crm.registrar_intento_base_v2(uuid, uuid, text, text, timestamptz, numeric, text) to authenticated;
-- crm.reactivar_lead_base(uuid,uuid,text), crm.registrar_intento_base(…), crm.base_gestion_resumen() y
-- crm.base_gestion_resumen_detalle(uuid,text) no se tocan; private.base_gestion_reactivar_core(uuid,uuid,uuid,text) y
-- private.base_gestion_intento_core(…) conservan su ACL ({postgres=X/postgres}). Las tres piezas de B9 reemplazadas conservan
-- dueño y ACL (CREATE OR REPLACE; {postgres=X/postgres}); el postflight lo comprueba.

-- ── 6 · Comentarios ────────────────────────────────────────────────────────────────────────────────────────────────────
comment on function crm.obtener_base_gestion(uuid, boolean) is 'Base para gestión (B3): leads descartados vivos del ámbito del actor (analista → los suyos; Supervisión → subárbol; Gerencia → todo), sin «no contactar» ni descanso vigente (salvo p_incluir_vetados, ver B6b), con intentos del ciclo, último resultado, próxima rellamada, etapa máxima alcanzada y quién gestiona. Orden: rellamada vencida o de hoy → etapa máxima → menos días desde el descarte. p_vendedor_id filtra un analista dentro del ámbito. DEFINER: ámbito explícito (espejo de leads_select), search_path vacío, EXECUTE solo authenticated. B3c (03/10/2026): sus conteos de intentos salen de private.base_gestion_intentos_ciclo; fuera del censo analítico. B5 (03/10/2026): devuelve al final recibido_en = coalesce(tenencia_desde, creado_en), cuándo le llegó el lead a quien lo tiene: el MES por el que se organiza el analista. B6b (03/10/2026, F4): p_incluir_vetados (default false; null = false) suma los leads «No contactar» del ámbito, también los que están en descanso; solo Supervisión y Gerencia (otro rol → 42501). Los vetados van al final y nunca en «Llamar hoy» (rellamada_hoy = false). Columnas finales no_contactar, no_contactar_en, no_contactar_motivo y no_contactar_por (nombre del autor): de la nota del evento vigente del veto — si la persona del lead (enlace, puente o DNI, como en marcar/levantar) está vetada, la última nota del veto entre los leads de la persona (private.leads_de_persona_veto ∪ el propio lead); si no, la del propio lead — solo si es un «marcar» (también el de postventa, motivo en el detalle) y su lead es visible para quien llama; si no, NULL. Residuo: empate exacto de clock_timestamp, desempate por id. B6c (04/10/2026, decisión de Miguel): la nota del veto (metadata evento = no_contactar) solo la escriben sus puertas (marcar_no_contactar, levantar_no_contactar y postventa_veto_fn, bajo crm.op_privilegiada; trigger trg_00_actividades_no_contactar_solo_puerta en crm.actividades): desde la API ya no se puede firmar el motivo, el autor ni la fecha de la marca, y la nota ya escrita no se cambia ni se borra. No acredita las notas anteriores a B6c (04/10/2026). Residuo (auditor-rls B6b, P3): esta función no lee la bandera resolver_en_puertas (encendida desde el 07/09/2026) y resuelve siempre la persona como las puertas con la bandera encendida; si se apagara, las puertas actuarían solo sobre el lead y la marca de un lead cuya persona siga vetada podría salir NULL o venir de otro lead de la persona (nunca de uno fuera del ámbito de quien llama). Con false, el resultado es el de B5. Envoltorios DEFINER en la base: crm.base_gestion_resumen y crm.base_gestion_resumen_detalle (re-auditarlos si cambia leads_select). B10 (04/10/2026, bases cargadas; r3): dos columnas finales, base_id y base_nombre (la base VIVA del lead —pertenencia y base activas—, solo si quien llama ve la base o es el analista del lead; si no, NULL), y fuera de la lista los DORMIDOS del archivo SIN REPARTIR de una base viva (procedencia archivo y estado sin_repartir de private.bases_carga_estado_contacto, la misma definición del seguimiento: disponibles, sin analista, sin veto ni movimientos ajenos; viven en la pestaña «Bases»). Un armado desde el CRM nunca se oculta: sigue en la lista de su analista anterior (E1). Un vetado nunca es sin repartir: sale en «Ver no contactar». El analista ve sus contactos de base repartidos como cualquier lead suyo. Lo demás, idéntico a B6b (el postflight de B10 lo compara con la foto previa).';
comment on function private.base_gestion_reactivar_capital_core(uuid, uuid, uuid, text, numeric, text) is
'Base para gestión (B3, D1/D2/D9; B10): la ÚNICA definición del núcleo de reactivar. Reabre por crm.reabrir_lead_fn (sellada; → nuevo, ciclo nuevo, SLA reiniciado, veto verificado), avanza a contactado en la misma transacción, sella reactivado_en y limpia rellamada y descanso; deja la actividad reactivacion_base con la respuesta (idempotencia por id = operación). B10 (04/10/2026, E8): si el lead NO tiene capital (contacto de base cargada), p_monto_estimado es obligatorio (NULL → 22023 «Indica el capital estimado para reactivar»; > 0, ≤ 9999999999.99 y hasta 2 decimales, si no 22023) y p_moneda opcional (NULL = la del lead; solo PEN o USD, si no 22023): se escriben en el lead ANTES de reabrir y el episodio de la reapertura nace con ese capital. Con capital ya puesto, los dos se ignoran. La llaman private.base_gestion_reactivar_core (sin capital), crm.reactivar_lead_base_v2 y private.base_gestion_intento_capital_core («agendó cita», con el capital del intento). Sin EXECUTE para la API.';
comment on function private.base_gestion_reactivar_core(uuid, uuid, uuid, text) is
'Base para gestión (B3, D1/D2/D9): reactivar SIN capital. Desde B10 (04/10/2026) es un envoltorio de private.base_gestion_reactivar_capital_core (la única definición del núcleo) con p_monto_estimado y p_moneda NULL: un lead sin capital → 22023 «Indica el capital estimado para reactivar». Se conserva la firma porque la nombran el gate (test-rls.mjs) y los scripts de B3. La llama la puerta publicada crm.reactivar_lead_base. Sin EXECUTE para la API.';
comment on function private.base_gestion_intento_capital_core(uuid, uuid, uuid, text, text, timestamptz, numeric, text) is
'Base para gestión (B3, D3/D7-bis/D10/D11; B10): la ÚNICA definición del núcleo de intentos. Registra un intento sobre un lead descartado del ámbito del actor (7 resultados; volver_a_llamar exige fecha futura ≤ dias_max_rellamada; descanso vigente y No contactar rechazan), escribe la actividad intento_base bajo los dos GUC, fija o limpia proxima_llamada_en y, con agendo_reunion, reactiva en la misma transacción por private.base_gestion_reactivar_capital_core con p_monto_estimado y p_moneda (B10, E8: obligatorio solo si el lead no tiene capital → 22023 «Indica el capital estimado para reactivar»; en otro resultado o con capital, se ignoran). Idempotente por id = operación (guarda la respuesta). El enfriamiento lo pone el trigger de B4. Sus conteos salen de private.base_gestion_intentos_ciclo (B3c; fuera del censo analítico). La llaman private.base_gestion_intento_core (sin capital) y crm.registrar_intento_base_v2. Sin EXECUTE para la API.';
comment on function private.base_gestion_intento_core(uuid, uuid, uuid, text, text, timestamptz) is
'Base para gestión (B3): registrar un intento SIN capital. Desde B10 (04/10/2026) es un envoltorio de private.base_gestion_intento_capital_core (la única definición del núcleo) con p_monto_estimado y p_moneda NULL: un «agendó cita» sobre un lead sin capital → 22023 «Indica el capital estimado para reactivar»; el resto, igual que antes. Se conserva la firma porque la nombra el gate (test-rls.mjs). La llama la puerta publicada crm.registrar_intento_base. Sin EXECUTE para la API.';
comment on function crm.registrar_intento_base_v2(uuid, uuid, text, text, timestamptz, numeric, text) is
'Bases cargadas (B10, 04/10/2026, E8): registrar un intento de la base para gestión pidiendo el capital cuando el resultado reactiva. Igual que crm.registrar_intento_base (B3: 7 resultados, volver_a_llamar con fecha futura ≤ 10 días, idempotente por p_operacion_id, «agendó cita» reactiva en la misma operación, D3) más p_monto_estimado y p_moneda: con agendo_reunion sobre un lead SIN capital, p_monto_estimado es OBLIGATORIO (NULL → 22023 «Indica el capital estimado para reactivar»; fuera de forma → 22023; p_moneda NULL conserva la del lead, solo PEN o USD); en cualquier otro caso se ignoran. Versionada (_v2): una sobrecarga con defaults junto a la publicada es ambigua (Postgres 42725). Misma respuesta que la publicada. DEFINER, search_path vacío, EXECUTE solo authenticated; delega en private.base_gestion_intento_capital_core.';
comment on function crm.reactivar_lead_base_v2(uuid, uuid, text, numeric, text) is
'Bases cargadas (B10, 04/10/2026, E8): reactivar un lead de la base pidiendo el capital si falta. Igual que crm.reactivar_lead_base (D1/D2/D9: al pipeline en contactado, mismo dueño, ciclo nuevo, reactivado_en y la línea en el historial; idempotente por p_operacion_id) más p_monto_estimado y p_moneda: si el lead no tiene capital, p_monto_estimado es OBLIGATORIO (NULL → 22023 «Indica el capital estimado para reactivar»; fuera de forma → 22023) y p_moneda NULL conserva la del lead (solo PEN o USD); con capital ya puesto, se ignoran. Versionada (_v2) porque una sobrecarga con defaults junto a la puerta publicada la rompe (Postgres 42725, PostgREST PGRST203; evidencia en el informe de B10). Errores: 42501 sin sesión o sin rol, P0002 fuera del ámbito, P0429 No contactar, 22023 entrada inválida o no descartado. DEFINER, search_path vacío, EXECUTE solo authenticated; delega en private.base_gestion_reactivar_capital_core.';
comment on function crm.seguimiento_bases() is
'Bases cargadas (B10, 04/10/2026; r1): una fila por base VIVA que el actor ve (Supervisión: las de su subárbol; Gerencia: todas; analista y otros roles → 42501) con total, sin_repartir (DISPONIBLES de verdad: sin analista, activos, sin veto, descartados y sin movimientos ajenos), repartidos, sin_tocar, trabajados (≥ 1 intento de la base desde el reparto), en_descanso, citas, reactivados, avance = trabajados / repartidos (0–1, siempre con 4 decimales; 0.0000 sin repartidos) y, al final (r1), movidos_otra_via, retirados y no_contactar (r3: sin con_analista_previo; un armado que conserva su analista anterior es sin_repartir, E1). Cada cifra se abre con crm.seguimiento_base_detalle (mismo arreglo de cifras: filas = cifra). Definiciones en private.bases_carga_seguimiento_filas. Más reciente primero. DEFINER (las tablas de bases no tienen grants), search_path vacío, EXECUTE solo authenticated; sin conteos sobre crm.leads (fuera del censo analítico).';
comment on function crm.seguimiento_base(uuid) is
'Bases cargadas (B10, 04/10/2026; r1): una fila por analista con contactos de la base: asignados, sin_tocar, sin_tocar_3_dias (E6: asignado hace ≥ 3 días de Lima y sin intento desde el reparto; la pantalla lo pinta en rojo), trabajados, en_descanso, citas, reactivados, ultimo_intento_en (desde el reparto), movidos_otra_via (E14) y, al final (r1), retirados y no_contactar. Base inexistente, retirada o fuera del ámbito → P0002; analista y otros roles → 42501. analista_id y nombre solo si el analista está en el ámbito del actor (si Gerencia repartió a otro equipo, la fila sale sin identificar y se abre por la base). r4 (Codex r2): TODOS los analistas fuera del ámbito van en UNA sola fila anónima (analista_id y analista_nombre NULL, cifras sumadas, ultimo_intento_en el máximo), la última; Gerencia nunca la tiene. Cada cifra se abre con crm.seguimiento_base_detalle. DEFINER, search_path vacío, EXECUTE solo authenticated.';
comment on function crm.seguimiento_base_detalle(uuid, uuid, text) is
'Bases cargadas (B10, 04/10/2026, «todo número se abre»): las filas detrás de una cifra de crm.seguimiento_bases (p_analista_id NULL) o de crm.seguimiento_base (p_analista_id = la fila). p_cifra: total, sin_repartir, repartidos, asignados, sin_tocar, sin_tocar_3_dias, trabajados, en_descanso, citas, reactivados, movidos_otra_via, retirados o no_contactar (private.bases_carga_seguimiento_cifras); otra, «avance» o NULL → 22023 (p_cifra lleva default NULL solo porque Postgres no admite un parámetro sin default después de p_analista_id; la pantalla llama por nombre). Base fuera del ámbito → P0002; analista sin contactos en la base → P0002; analista y otros roles → 42501. Filas = la cifra (el mismo arreglo de private.bases_carga_seguimiento_filas): lead_id y nombre solo si el actor ve el lead y sigue activo (private.bases_carga_lead_ref), si no NULL; estado, asignado_en, último intento y último resultado desde el reparto. r4 (Codex r2): un p_analista_id explícito tiene que estar en el ámbito del actor (private.vendedor_ids_visibles; Gerencia: cualquiera) —se mira ANTES que la pertenencia— y con contactos en la base; si no, P0002 «Analista no encontrado en esta base» en los dos casos. DEFINER, search_path vacío, EXECUTE solo authenticated.';
comment on function private.bases_carga_estado_contacto(uuid, boolean, boolean, text, uuid, uuid, date, uuid, timestamptz, timestamptz, uuid, uuid[], date, boolean, boolean, boolean) is
'Bases cargadas (B10 r2/r3, 04/10/2026; coordinador y Codex r1 P2): la ÚNICA definición del estado de un contacto de una base, para TODAS las puertas de B9 y B10 (seguimiento y detalle, crm.contactos_de_base, la exclusión de crm.obtener_base_gestion, el bloque y el individual de crm.repartir_base, crm.recoger_de_base). En orden: retirado (activo = false) · no_contactar (vetado) · movido_otra_via (con reparto: ya no es de su analista; sin reparto: fuera del ámbito del supervisor dueño —private.bases_carga_en_subarbol—, u otra vía le cambió el responsable desde que entró a la base —rastro reasignacion— salvo que hoy esté en la bandeja del dueño sin analista; y lo que salió del descarte sin cita ni reactivación de la base) · cita / reactivado (salió del descarte con un «agendó cita» / una reactivación de la base desde el reparto o, sin reparto, desde que entró a la base: private.bases_carga_reparto_hechos) · en_descanso (enfriado_hasta > hoy) · trabajado / sin_tocar (con reparto, con o sin intento desde asignado_en; sin reparto, trabajado = su analista anterior lo tiene en seguimiento activo B6) · sin_repartir (DISPONIBLE: sin reparto, activo, sin veto, descartado, sin descanso, en el ámbito del dueño, sin movimientos ajenos y sin seguimiento activo; r3, E1: también el armado que conserva su analista anterior). p_intento, p_cita y p_reactivado: los hechos de private.bases_carga_reparto_hechos(lead, coalesce(asignado_en, agregado_en)) si el llamador ya los tiene; NULL = los calcula. Un NULL nunca hace a un contacto «sin repartir». INVOKER, sin EXECUTE para la API.';
comment on function private.bases_carga_reparto_motivo_bloque(uuid, boolean, boolean, text, uuid, uuid, date, uuid, timestamptz, timestamptz, uuid, uuid[], date) is
'Bases cargadas (B10 r2, 04/10/2026): el reparto EN BLOQUE elige SOLO contactos en estado sin_repartir (private.bases_carga_estado_contacto): NULL = elegible; si no, el motivo para omitidos y para la revisión bajo candado: el de private.bases_carga_reparto_motivo (B9, evaluado para todo candidato) o, si ese no dice nada, el estado (movido_otra_via). Recibe la fila del lead y de su pertenencia (las MISMAS entradas que la definición única). La usa private.bases_carga_repartir_core en la foto, bajo candado y en omitidos. INVOKER, sin EXECUTE para la API.';
comment on function private.bases_carga_repartir_core(uuid, uuid, uuid, jsonb) is 'Bases cargadas (B9; r1): núcleo de crm.repartir_base. Orden: forma → idempotencia (recibo repartir, replay que revalida referencias) → base (visible, FOR UPDATE NOWAIT, viva, dueño activo) → analistas → bloque: foto sin candados de los sin repartir con su motivo y candado SKIP LOCKED SOLO de los que faltan, por tandas y en el orden del reparto; individual: ámbito (P0002) ANTES del candado SKIP LOCKED de lo pedido → revisión bajo candado con la misma definición y sin intento durante la operación → UPDATE de crm.leads por el camino de la casa → pertenencia → recibo. Sin count( ni sum(1) (censo). B10 r2 (04/10/2026): el bloque elige con private.bases_carga_reparto_motivo_bloque —solo el estado sin_repartir de private.bases_carga_estado_contacto, la definición única de B9 y B10; también el armado con su analista anterior, E1— en la foto, bajo candado y en omitidos; el individual añade el estado: lo movido por otra vía se rechaza (motivo movido_otra_via).';
comment on function private.bases_carga_contactos_core(uuid, uuid, text) is 'Bases cargadas (B9): núcleo de crm.contactos_de_base: base visible, solo contactos con private.bases_carga_lead_ref (visibles y activos), estado de private.bases_carga_estado_contacto (B10 r2/r3: la definición única de B9 y B10; el filtro, el de B9).';
comment on function private.bases_carga_reparto_recogible(uuid, uuid, timestamptz, boolean) is 'Bases cargadas (B9 r1): UNA definición de «se puede recoger»: vivo, descartado y en manos de ese analista (lo movido por otra vía no se deshace, E14), sin intento desde que se le repartió (salvo analista de baja: manda B6, que la baja libera) y sin seguimiento activo B6. La usan la foto y la revisión bajo candado de recoger. B10 r2 (04/10/2026): «sin intento» es el estado sin_tocar de private.bases_carga_estado_contacto (sin intento desde el reparto, sin veto ni descanso): recoger toma lo que el seguimiento muestra sin tocar.';
comment on function crm.repartir_base(uuid, uuid, jsonb) is 'Bases cargadas (B9, 04/10/2026): reparte contactos de una base a analistas, TODO O NADA. p_reparto: {"modo":"bloque","asignaciones":[{"analista_id","cantidad"}]} (el servidor elige los SIN REPARTIR más antiguos en la base y salta los que no se pueden repartir: retirados, fuera del ámbito del dueño, que salieron del descarte, No contactar, en descanso, en gestión B6 u ocupados; si no alcanzan → 22023 con detail = disponibles, el número en texto) o {"modo":"individual","asignaciones":[{"lead_id","analista_id"}]} (cada contacto de la base, visible para el actor —si no, P0002—, sin repartir o repartido a otro —se reasigna— y elegible; si no → 22023 con detail {"rechazados":[{lead_id, motivo}]}; tomado por otro proceso → 55P03; el que ya es de ese analista sale en omitidos como ya_asignado). Analista activo, rol vendedor, del subárbol del supervisor DUEÑO (Gerencia: cualquiera, y puede volver a repartir lo que B9 le dio a alguien fuera del equipo del dueño; fuera del equipo → P0002, inactivo o no analista → 22023). Bloquea solo lo necesario (r1). Efecto: crm.leads.vendedor_id = analista (sigue descartado; sin ciclo SLA ni episodio; la actividad «reasignación» y el candado B6 corren solos) y base_carga_leads.analista_id/asignado_en/asignado_por. Topes en private.bases_carga_reparto_constantes. Idempotente por (actor, p_operacion_id). Devuelve {ok, operacion_id, base_id, modo, repartidos, por_analista[{analista_id, cantidad}], omitidos[{lead_id|null, motivo, cantidad?}]} (en bloque, por motivo con lead_id null). Supervisión y Gerencia (otros → 42501); otra operación de la base en curso → 55P03. DEFINER, search_path vacío, lock_timeout 5 s, EXECUTE solo authenticated. B10 r2 (04/10/2026, una sola definición del estado): el bloque elige SOLO contactos en estado sin_repartir de private.bases_carga_estado_contacto —un armado que conserva su analista anterior es sin_repartir (E1) salvo que ese analista lo esté trabajando (B6); salta además lo movido por otra vía, que sale en omitidos con ese motivo—; el individual rechaza también lo movido por otra vía (motivo movido_otra_via).';
comment on function crm.recoger_de_base(uuid, uuid, uuid) is 'Bases cargadas (B9, 04/10/2026; r1): devuelve a «sin repartir» (bandeja del supervisor dueño de la base) los contactos que ese analista tiene de la base SIN intento desde que se le repartieron (de un analista de baja no se exige: manda B6, que la baja libera), sin seguimiento activo (B6) y que siguen descartados y en sus manos (lo movido por otra vía no se deshace, E14); los tomados por otro proceso quedan. Supervisión: analistas de su equipo (activos o no); Gerencia: cualquiera. Tope por operación (private.bases_carga_reparto_constantes): lo que excede queda en pendientes. Idempotente por (actor, p_operacion_id). Devuelve {ok, operacion_id, base_id, analista_id, recogidos, omitidos, pendientes}. DEFINER, search_path vacío, lock_timeout 5 s, EXECUTE solo authenticated. B10 r2 (04/10/2026): recoge lo que el seguimiento muestra «sin tocar» (estado sin_tocar de private.bases_carga_estado_contacto: sin intento desde el reparto, sin veto ni descanso) y sin seguimiento activo B6; de un analista de baja, todo lo suyo que siga descartado.';
comment on function crm.contactos_de_base(uuid, text) is 'Bases cargadas (B9, 04/10/2026): los contactos de una base visible para el actor (Supervisión: su subárbol; Gerencia: todas; si no, P0002; otros roles → 42501), para el reparto individual y la pestaña «Bases». p_estado: sin_repartir (por defecto) | repartidos | todos. Solo contactos que el actor ve y siguen activos (nada fuera de su ámbito). Lleva nombre, teléfono y distrito: la pantalla los usa para marcar filas en el reparto individual (el actor ya los ve en su Base para gestión). estado ∈ sin_repartir · sin_tocar · trabajado · en_descanso · cita · reactivado · movido_otra_via · no_contactar · retirado (B10 r2 (04/10/2026): private.bases_carga_estado_contacto, la misma definición del seguimiento de B10; un retirado no sale: solo contactos activos). Orden: el del reparto en bloque (más antiguos en la base primero). DEFINER, search_path vacío, EXECUTE solo authenticated.';
comment on function private.bases_carga_seguimiento_cifras() is
'Bases cargadas (B10; r1): los nombres de las cifras que se abren (columnas numéricas de crm.seguimiento_bases y crm.seguimiento_base, también retirados y no_contactar; «avance» es un cociente y se abre por trabajados). Sin EXECUTE para la API.';
comment on function private.bases_carga_seguimiento_rol(uuid) is
'Bases cargadas (B10): rol del actor para el seguimiento (private.rol_crm): solo supervisor o gerencia; si no (o sin sesión), 42501. Sin EXECUTE para la API.';
comment on function private.bases_carga_seguimiento_exigir_base(uuid, text, uuid) is
'Bases cargadas (B10): exige una base viva visible para el actor (private.bases_carga_base_visible, espejo de la policy bases_carga_select); NULL → 22023; inexistente, retirada o fuera del ámbito → P0002. Sin EXECUTE para la API.';
comment on function private.bases_carga_seguimiento_filas(uuid[], date) is
'Bases cargadas (B10; r2): una fila por contacto VIVO (pertenencia activa) de las bases pedidas con su estado —el de private.bases_carga_estado_contacto, la definición única de B9 y B10— y el arreglo cifras: total, sin_repartir, sin_tocar, en_descanso, movidos_otra_via, retirados y no_contactar (= su estado), repartidos y asignados (con analista), sin_tocar_3_dias (sin tocar y repartido hace ≥ 3 días de Lima, E6), trabajados, citas y reactivados (hechos de la base desde asignado_en, private.bases_carga_reparto_hechos de B9; solo repartidos). La ÚNICA definición de cada cifra: los conteos y el detalle leen ese arreglo. Sin agregados de conteo (censo). Sin EXECUTE para la API.';

-- ── 7 · Postflight (catálogo + identidad con B6b + envoltorios; sin DML) ──────────────────────────────────────────────
create temp table _b10_censo_despues on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;
-- Los dormidos sin repartir de esta instantánea que la lista de B6b mostraba (vivos y descartados): los únicos que la lista
-- nueva puede dejar fuera.
create temp table _b10_excluidos on commit drop as
  select l.id
    from crm.leads l
    join crm.base_carga_leads bl on bl.lead_id = l.id and bl.activo and bl.procedencia = 'archivo' and bl.analista_id is null
    join crm.bases_carga bc on bc.id = bl.base_id and bc.activo
    cross join lateral (select array(select private.bases_carga_subarbol(bc.supervisor_id)) as subarbol) s
   where l.activo and l.etapa = 'descartado'
     and private.bases_carga_estado_contacto(l.id, l.activo, l.no_contactar, l.etapa, l.vendedor_id, l.asignado_supervisor_id,
                                             l.enfriado_hasta, bl.analista_id, bl.asignado_en, bl.creado_en, bc.supervisor_id,
                                             s.subarbol, (now() at time zone 'America/Lima')::date) = 'sin_repartir';
do $postflight$
declare
  v_mal text;
  v_ger uuid;
  v_vend uuid;
  v_r record;
  v_b record;
  v_a record;
  v_cifra text;
  v_n bigint;
  v_primero boolean := true;
  v_excluidos bigint;
  v_filas bigint;
  v_sup uuid;
  v_x record;
begin
  -- 1. Funciones nuevas, reemplazadas y las que NO cambian: cuerpo, seguridad, volatilidad, search_path, dueño, ACL exacta y
  --    comentario.
  with esperado(firma, cuerpo, definer, volatil, acl) as (values
    ('private.bases_carga_estado_contacto(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date,boolean,boolean,boolean)', 'fa523b6c14624cc354813e3ab0343e10', false, 's', '{postgres=X/postgres}'),
    ('private.bases_carga_reparto_motivo_bloque(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date)', 'd63f4d40ae0ba60aa26df40cae341584', false, 's', '{postgres=X/postgres}'),
    ('private.bases_carga_contactos_core(uuid,uuid,text)', '3f179999beef647f81c70fcd411240b1', false, 's', '{postgres=X/postgres}'),
    ('private.bases_carga_reparto_recogible(uuid,uuid,timestamp with time zone,boolean)', 'b89a1f1141555c224d9ebf2c53b41bf4', false, 's', '{postgres=X/postgres}'),
    ('private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)', '6b934571b91796d43f8ce5e59d3ddae1', false, 'v', '{postgres=X/postgres}'),
    ('private.bases_carga_seguimiento_cifras()', '139e96a669b2ca914171c569443a7e37', false, 'i', '{postgres=X/postgres}'),
    ('private.bases_carga_seguimiento_rol(uuid)', 'd218e48c7125c3598a27cf1d41fe634a', false, 's', '{postgres=X/postgres}'),
    ('private.bases_carga_seguimiento_exigir_base(uuid,text,uuid)', '49e3cb435320fd2ed63054a5ab00e7d6', false, 's', '{postgres=X/postgres}'),
    ('private.bases_carga_seguimiento_filas(uuid[],date)', '0ee0a636d55527a01ade77b4a62760ab', false, 's', '{postgres=X/postgres}'),
    ('crm.seguimiento_bases()', '10ef60a15cded9e41ea8ccce998adff9', true, 's', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.seguimiento_base(uuid)', '79a76f53b0c21043627b6a149e4d4b4f', true, 's', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.seguimiento_base_detalle(uuid,uuid,text)', '8b1840fed8657e752514120f40b7b8e9', true, 's', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.obtener_base_gestion(uuid,boolean)', '26d887dc635824f383b0eb236c8226fb', true, 's', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)', '479683a99720d554ff419752f3da7876', true, 'v', '{postgres=X/postgres}'),
    ('private.base_gestion_reactivar_core(uuid,uuid,uuid,text)', '32eac0c4dc89d53524a1451d0f507799', true, 'v', '{postgres=X/postgres}'),
    ('crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)', '9037872b37d8a3d05d32b8a7a71b13e2', true, 'v', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.reactivar_lead_base(uuid,uuid,text)', 'bf59d77929877e7a5eb46704d934363e', true, 'v', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)', '98cd4edd8a3d7655f70a1a894d0e0b80', true, 'v', '{postgres=X/postgres}'),
    ('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)', '22db4f57842bbbc04b61f5d2eb641fb8', true, 'v', '{postgres=X/postgres}'),
    ('crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)', '40d26d67d052b71a2cc5d60b25e1b434', true, 'v', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.registrar_intento_base(uuid,uuid,text,text,timestamp with time zone)', 'd92c791fbe6f84e5d4f8ca39357b4721', true, 'v', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.base_gestion_resumen()', 'b773a7c49fbdfc45133b3405991b1958', true, 's', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.base_gestion_resumen_detalle(uuid,text)', '068372248be4127c80ba002542c9b4b8', true, 's', '{postgres=X/postgres,authenticated=X/postgres}'))
  select string_agg(e.firma, ', ' order by e.firma) into v_mal
    from esperado e
    left join pg_proc p on p.oid = to_regprocedure(e.firma)
   where (p.oid is not null and md5(p.prosrc) = e.cuerpo and p.prosecdef = e.definer and p.provolatile = e.volatil
          and p.proconfig = array['search_path=""']::text[] and p.proowner = 'postgres'::regrole
          and p.proacl is not null and p.proacl::text = e.acl
          and obj_description(p.oid, 'pg_proc') is not null) is not true;
  if v_mal is not null then
    raise exception 'POSTFLIGHT B10: funciones que no quedaron como se ensayaron: %', v_mal;
  end if;
  -- r2: B9 con la definición única. Sus tres puertas, intactas (cuerpo, DEFINER y ACL; el comentario dice r2); las tres
  -- piezas reemplazadas, con su comentario r2; el clasificador de B9 ya no existe y nadie nombra una definición vieja; la
  -- definición única la llaman EXACTAMENTE la lista, las filas del seguimiento, el motivo del bloque y las tres piezas de B9.
  if (
    (select count(*) from (values ('crm.repartir_base(uuid,uuid,jsonb)', 'fd7531ba7cd7cf8a259a389e2895ee2e'),
                                  ('crm.recoger_de_base(uuid,uuid,uuid)', '4744f70e69c0f70c22a6a295184e3095'),
                                  ('crm.contactos_de_base(uuid,text)', 'd528bab6930698d160f9635417a3ca7a')) x(firma, cuerpo)
       join pg_proc p on p.oid = to_regprocedure(x.firma)
      where md5(p.prosrc) = x.cuerpo and p.prosecdef and p.proowner = 'postgres'::regrole
        and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
        and obj_description(p.oid, 'pg_proc') like '%B10 r2 (04/10/2026%') = 3
    and (select count(*) from unnest(array['private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)', 'private.bases_carga_contactos_core(uuid,uuid,text)',
                                           'private.bases_carga_reparto_recogible(uuid,uuid,timestamp with time zone,boolean)']) f(firma)
          where obj_description(to_regprocedure(f.firma), 'pg_proc') like '%B10 r2%') = 3
    and to_regprocedure('private.bases_carga_reparto_estado(boolean,boolean,text,uuid,boolean,date,uuid,boolean,boolean,boolean,boolean,date)') is null
    and not exists (select 1 from pg_proc p where p.proname in ('bases_carga_reparto_estado', 'bases_carga_estado_sin_reparto'))
    and not exists (select 1 from pg_proc p where p.prosrc ~ 'bases_carga_reparto_estado|bases_carga_estado_sin_reparto')
    and (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text collate "C") from pg_proc p
          where p.prosrc ~ 'bases_carga_estado_contacto')
        = 'crm.obtener_base_gestion(uuid,boolean),private.bases_carga_contactos_core(uuid,uuid,text),private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb),'
          'private.bases_carga_reparto_motivo_bloque(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date),private.bases_carga_reparto_recogible(uuid,uuid,timestamp with time zone,boolean),'
          'private.bases_carga_seguimiento_filas(uuid[],date)'
    and (select count(*) from pg_proc p where p.pronamespace = 'private'::regnamespace
          and (p.proname like 'bases\_carga\_reparto\_%' or p.proname in ('bases_carga_repartir_core', 'bases_carga_recoger_core', 'bases_carga_contactos_core'))) = 10
  ) is not true then
    raise exception 'POSTFLIGHT B10: B9 no quedo con la definicion unica (puertas, piezas reemplazadas, clasificador borrado o llamadores)';
  end if;

  if (
    -- Una sola sobrecarga de cada puerta y de cada núcleo (el de 4 argumentos sigue con su firma).
    (select count(*) from pg_proc p where p.pronamespace = 'crm'::regnamespace
      and p.proname in ('obtener_base_gestion', 'reactivar_lead_base', 'reactivar_lead_base_v2', 'seguimiento_bases', 'seguimiento_base',
                        'seguimiento_base_detalle', 'registrar_intento_base', 'registrar_intento_base_v2')) = 8
    and (select count(*) from pg_proc p where p.pronamespace = 'private'::regnamespace
          and p.proname in ('base_gestion_reactivar_core', 'base_gestion_reactivar_capital_core', 'base_gestion_intento_core',
                            'base_gestion_intento_capital_core')) = 4
    -- La lista conserva sus 2 parámetros con default y termina en base_id, base_nombre; el núcleo, 6 con 2 defaults.
    and (select p.pronargs = 2 and p.pronargdefaults = 2 and p.proargnames[pg_catalog.array_length(p.proargnames, 1) - 1] = 'base_id'
                and p.proargnames[pg_catalog.array_length(p.proargnames, 1)] = 'base_nombre'
           from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid,boolean)'))
    and (select p.pronargs = 6 and p.pronargdefaults = 0 from pg_proc p
          where p.oid = to_regprocedure('private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)'))
    and (select p.pronargs = 8 and p.pronargdefaults = 0 from pg_proc p
          where p.oid = to_regprocedure('private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)'))
    and (select p.pronargs = 7 and p.pronargdefaults = 4 from pg_proc p
          where p.oid = to_regprocedure('crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)'))
    -- Permisos efectivos: las puertas solo para authenticated; el núcleo y los ayudantes, para nadie de la API.
    and not exists (select 1 from unnest(array['crm.seguimiento_bases()', 'crm.seguimiento_base(uuid)', 'crm.seguimiento_base_detalle(uuid,uuid,text)',
                                              'crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)', 'crm.obtener_base_gestion(uuid,boolean)',
                                              'crm.reactivar_lead_base(uuid,uuid,text)', 'crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)',
                                              'crm.registrar_intento_base(uuid,uuid,text,text,timestamp with time zone)']) f(firma)
                     where has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE')
                        or not has_function_privilege('authenticated', f.firma, 'EXECUTE'))
    and not exists (select 1 from unnest(array['private.bases_carga_estado_contacto(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date,boolean,boolean,boolean)',
                                              'private.bases_carga_reparto_motivo_bloque(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date)', 'private.bases_carga_seguimiento_cifras()',
                                              'private.bases_carga_seguimiento_rol(uuid)', 'private.bases_carga_seguimiento_exigir_base(uuid,text,uuid)',
                                              'private.bases_carga_seguimiento_filas(uuid[],date)',
                                              'private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)',
                                              'private.base_gestion_reactivar_core(uuid,uuid,uuid,text)',
                                              'private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)',
                                              'private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)']) f(firma)
                     cross join unnest(array['anon', 'authenticated', 'service_role']) r(rol)
                     where has_function_privilege(r.rol, f.firma, 'EXECUTE'))
    -- Consumidores de servidor: de la lista, el resumen y la detalle; del núcleo de reactivar de 4 argumentos, la puerta
    -- publicada; del de reactivar con capital, el de 4 argumentos, la _v2 y el núcleo de intentos con capital; del núcleo de
    -- intentos, la puerta publicada; del de intentos con capital, el envoltorio y su _v2 (el patrón '…_core' no casa con
    -- '…_capital_core').
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~ 'obtener_base_gestion'
                       and p.oid not in (to_regprocedure('crm.obtener_base_gestion(uuid,boolean)'), to_regprocedure('crm.base_gestion_resumen()'),
                                         to_regprocedure('crm.base_gestion_resumen_detalle(uuid,text)')))
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~ 'base_gestion_reactivar_core'
                       and p.oid not in (to_regprocedure('crm.reactivar_lead_base(uuid,uuid,text)'),
                                         to_regprocedure('private.bases_carga_reparto_hechos(uuid,timestamp with time zone)')))  -- B9: la nombra en un comentario, no la llama
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~ 'base_gestion_reactivar_capital_core'
                       and p.oid not in (to_regprocedure('private.base_gestion_reactivar_core(uuid,uuid,uuid,text)'),
                                         to_regprocedure('crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)'),
                                         to_regprocedure('private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)')))
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~ 'base_gestion_intento_core'
                       and p.oid not in (to_regprocedure('crm.registrar_intento_base(uuid,uuid,text,text,timestamp with time zone)'),
                                         to_regprocedure('private.bases_carga_reparto_hechos(uuid,timestamp with time zone)')))  -- B9: la nombra en un comentario, no la llama
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~ 'base_gestion_intento_capital_core'
                       and p.oid not in (to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)'),
                                         to_regprocedure('crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)')))
    -- Censo: ninguna nueva entra y es el de la foto.
    and not exists (select 1 from pg_temp._b10_censo_despues c
                     where c.objeto in ('crm.obtener_base_gestion(uuid,boolean)', 'crm.seguimiento_bases()', 'crm.seguimiento_base(uuid)',
                                        'crm.seguimiento_base_detalle(uuid,uuid,text)', 'private.bases_carga_seguimiento_filas(uuid[],date)',
                                        'private.bases_carga_estado_contacto(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date,boolean,boolean,boolean)',
                                        'private.bases_carga_reparto_motivo_bloque(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date)',
                                        'private.bases_carga_contactos_core(uuid,uuid,text)', 'private.bases_carga_reparto_recogible(uuid,uuid,timestamp with time zone,boolean)',
                                        'private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)',
                                        'private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)',
                                        'private.base_gestion_reactivar_core(uuid,uuid,uuid,text)',
                                        'private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)',
                                        'private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)',
                                        'crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)',
                                        'crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)'))
    and not exists (select 1 from pg_temp._b10_censo_despues c where c.objeto not in (select a.objeto from pg_temp._b10_censo_antes a))
    and (select count(*) from pg_temp._b10_censo_antes) = (select count(*) from pg_temp._b10_censo_despues)
  ) is not true then
    raise exception 'POSTFLIGHT B10: sobrecargas, firma, permisos efectivos, consumidores de servidor o el censo no quedaron como se ensayaron';
  end if;

  -- 2. Identidad con B6b como Gerencia (la de la foto): con false y con true, la lista nueva proyectada a las 26 columnas de
  --    B6b = la foto sin los dormidos sin repartir, en el mismo orden; base_id/base_nombre = la base VIVA del lead; ningún
  --    excluido en la lista; el resumen de F4 idéntico; la detalle de F4 da tantas filas como su cifra.
  select a.lead_id into v_ger from pg_temp._b10_lista_antes a where a.ord = 0;
  select count(*) into v_excluidos from pg_temp._b10_excluidos;
  if v_ger is not null then
    perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
    perform pg_catalog.set_config('request.jwt.claim.sub', v_ger::text, true);
    if exists (
      with esperado as (
        select a.modo, pg_catalog.row_number() over (partition by a.modo order by a.ord) as ord, a.fila
          from pg_temp._b10_lista_antes a
         where a.ord > 0 and a.lead_id not in (select x.id from pg_temp._b10_excluidos x)
      ),
      obtenido as (
        select m.modo, t.ordinality as ord,
               row(t.lead_id, t.nombre_completo, t.telefono, t.distrito, t.origen, t.categoria_interes, t.monto_estimado, t.moneda,
                   t.motivo_descarte, t.descartado_en, t.dias_desde_descarte, t.etapa_maxima, t.intentos, t.ultimo_resultado,
                   t.ultimo_intento_en, t.proxima_llamada_en, t.rellamada_hoy, t.enfriado_hasta, t.ciclo_n, t.vendedor_id, t.gestiona,
                   t.recibido_en, t.no_contactar, t.no_contactar_en, t.no_contactar_motivo, t.no_contactar_por)::text as fila
          from (values (false), (true)) m(modo)
          cross join lateral crm.obtener_base_gestion(null, m.modo) with ordinality t
      )
      (select * from esperado except all select * from obtenido)
      union all
      (select * from obtenido except all select * from esperado)
    ) then
      raise exception 'POSTFLIGHT B10: la lista no es la de B6b sin los dormidos sin repartir (mismas filas y orden)';
    end if;
    if exists (select 1 from crm.obtener_base_gestion(null, true) t
                 left join crm.base_carga_leads bl on bl.lead_id = t.lead_id and bl.activo
                 left join crm.bases_carga bc on bc.id = bl.base_id and bc.activo
                where t.base_id is distinct from bc.id or t.base_nombre is distinct from bc.nombre
                   or t.lead_id in (select x.id from pg_temp._b10_excluidos x)) then
      raise exception 'POSTFLIGHT B10: base_id/base_nombre no son la base viva del lead, o un dormido sin repartir sigue en la lista';
    end if;
    -- r4 (auditor-rls, hueco de pruebas): TODO contacto que la lista nueva oculta (estaba en la foto de B6b, con vetados, y ya
    -- no está) es un dormido del ARCHIVO de una base viva, sin analista de la base ni vendedor, en la bandeja del supervisor
    -- DUEÑO. Comprobado sobre la diferencia real de las dos listas, no con la definición.
    if exists (select 1 from pg_temp._b10_lista_antes a
                 join crm.leads l on l.id = a.lead_id
                 left join crm.base_carga_leads bl on bl.lead_id = l.id and bl.activo
                 left join crm.bases_carga bc on bc.id = bl.base_id and bc.activo
                where a.modo and a.ord > 0
                  and a.lead_id not in (select t.lead_id from crm.obtener_base_gestion(null, true) t)
                  and (bc.id is not null and bl.procedencia = 'archivo' and bl.analista_id is null and l.vendedor_id is null
                       and l.asignado_supervisor_id is not distinct from bc.supervisor_id) is not true) then
      raise exception 'POSTFLIGHT B10: la lista oculta un contacto que no es un dormido del archivo sin analista en la bandeja del dueno';
    end if;
    if exists ((select r.* from crm.base_gestion_resumen() r except all select a.* from pg_temp._b10_resumen_antes a)
               union all
               (select a.* from pg_temp._b10_resumen_antes a except all select r.* from crm.base_gestion_resumen() r)) then
      raise exception 'POSTFLIGHT B10: el resumen de F4 cambio';
    end if;
    for v_r in select r.vendedor_id, r.intentos_hoy, r.reactivaciones_mes from crm.base_gestion_resumen() r loop
      if v_primero or v_r.intentos_hoy > 0 or v_r.reactivaciones_mes > 0 then
        if ((select count(*) from crm.base_gestion_resumen_detalle(v_r.vendedor_id, 'intentos_hoy')) = v_r.intentos_hoy
            and (select count(*) from crm.base_gestion_resumen_detalle(v_r.vendedor_id, 'reactivaciones_mes')) = v_r.reactivaciones_mes) is not true then
          raise exception 'POSTFLIGHT B10: la detalle de F4 no da tantas filas como su cifra para el analista %', v_r.vendedor_id;
        end if;
        v_primero := false;
      end if;
    end loop;
    -- 3. El seguimiento se ejecuta (compila sus ramas) y cuadra en la base más reciente, si hay: cada cifra = su detalle y la
    --    suma por analista = la cifra de la base. Sin bases: P0002 con una base inexistente y 22023 con una cifra inválida.
    select count(*) into v_filas from crm.seguimiento_bases();
    for v_b in select s.* from crm.seguimiento_bases() s order by s.creado_en desc limit 1 loop
      foreach v_cifra in array array['total', 'sin_repartir', 'repartidos', 'sin_tocar', 'trabajados', 'en_descanso', 'citas', 'reactivados',
                                     'movidos_otra_via', 'retirados', 'no_contactar'] loop
        select count(*) into v_n from crm.seguimiento_base_detalle(v_b.base_id, null, v_cifra);
        if v_n is distinct from (pg_catalog.to_jsonb(v_b) ->> v_cifra)::bigint then
          raise exception 'POSTFLIGHT B10: la cifra % de la base % no es su detalle (% filas)', v_cifra, v_b.base_id, v_n;
        end if;
      end loop;
      if exists (select 1 from (select coalesce(sum(s.asignados), 0) a, coalesce(sum(s.sin_tocar), 0) st, coalesce(sum(s.trabajados), 0) t,
                                       coalesce(sum(s.en_descanso), 0) d, coalesce(sum(s.citas), 0) c, coalesce(sum(s.reactivados), 0) r
                                  from crm.seguimiento_base(v_b.base_id) s) q
                  where (q.a, q.st, q.t, q.c, q.r) is distinct from (v_b.repartidos::bigint, v_b.sin_tocar::bigint, v_b.trabajados::bigint,
                                                                    v_b.citas::bigint, v_b.reactivados::bigint)
                     or q.d > v_b.en_descanso) then  -- r2: en descanso de la base cuenta también lo SIN reparto
        raise exception 'POSTFLIGHT B10: la suma por analista no es la cifra de la base %', v_b.base_id;
      end if;
      for v_a in select s.* from crm.seguimiento_base(v_b.base_id) s limit 1 loop
        foreach v_cifra in array array['asignados', 'sin_tocar', 'sin_tocar_3_dias', 'trabajados', 'en_descanso', 'citas', 'reactivados', 'movidos_otra_via',
                                       'retirados', 'no_contactar'] loop
          select count(*) into v_n from crm.seguimiento_base_detalle(v_b.base_id, v_a.analista_id, v_cifra);
          if v_n is distinct from (pg_catalog.to_jsonb(v_a) ->> v_cifra)::bigint then
            raise exception 'POSTFLIGHT B10: la cifra % del analista % no es su detalle (% filas)', v_cifra, v_a.analista_id, v_n;
          end if;
        end loop;
      end loop;
    end loop;
    -- r4 (Codex r2): la misma base como su supervisor DUEÑO (si está activo): a lo sumo UNA fila anónima, la suma de sus filas =
    -- la base, cada analista suyo = su detalle, y un analista fuera de su ámbito, pedido explícitamente → P0002 (mismo mensaje).
    for v_b in select s.* from crm.seguimiento_bases() s order by s.creado_en desc limit 1 loop
      select b.supervisor_id into v_sup from crm.bases_carga b where b.id = v_b.base_id;
      if private.rol_crm(v_sup) = 'supervisor' then
        perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_sup, 'role', 'authenticated')::text, true);
        perform pg_catalog.set_config('request.jwt.claim.sub', v_sup::text, true);
        if (select count(*) from crm.seguimiento_base(v_b.base_id) s where s.analista_id is null) > 1
           or exists (select 1 from (select coalesce(sum(s.asignados), 0) a, coalesce(sum(s.sin_tocar), 0) st, coalesce(sum(s.trabajados), 0) t,
                                            coalesce(sum(s.citas), 0) c, coalesce(sum(s.reactivados), 0) r
                                       from crm.seguimiento_base(v_b.base_id) s) q
                       join crm.seguimiento_bases() sb on sb.base_id = v_b.base_id
                      where (q.a, q.st, q.t, q.c, q.r) is distinct from (sb.repartidos::bigint, sb.sin_tocar::bigint, sb.trabajados::bigint,
                                                                        sb.citas::bigint, sb.reactivados::bigint)) then
          raise exception 'POSTFLIGHT B10: el supervisor de la base % ve mas de una fila anonima o la suma de sus filas no es la base', v_b.base_id;
        end if;
        for v_a in select s.* from crm.seguimiento_base(v_b.base_id) s where s.analista_id is not null loop
          foreach v_cifra in array array['asignados', 'sin_tocar', 'trabajados', 'citas', 'reactivados'] loop
            select count(*) into v_n from crm.seguimiento_base_detalle(v_b.base_id, v_a.analista_id, v_cifra);
            if v_n is distinct from (pg_catalog.to_jsonb(v_a) ->> v_cifra)::bigint then
              raise exception 'POSTFLIGHT B10: la cifra % del analista % (supervisor) no es su detalle', v_cifra, v_a.analista_id;
            end if;
          end loop;
        end loop;
        for v_x in select distinct bl.analista_id from crm.base_carga_leads bl
                    where bl.base_id = v_b.base_id and bl.activo and bl.analista_id is not null
                      and bl.analista_id not in (select private.vendedor_ids_visibles(v_sup)) loop
          begin
            perform 1 from crm.seguimiento_base_detalle(v_b.base_id, v_x.analista_id, 'asignados');
            raise exception 'POSTFLIGHT B10: un analista fuera del ambito del supervisor se pudo abrir' using errcode = 'P0001';
          exception when no_data_found then
            if sqlerrm <> 'Analista no encontrado en esta base' then
              raise exception 'POSTFLIGHT B10: el analista externo dio otro mensaje: %', sqlerrm using errcode = 'P0001';
            end if;
          end;
        end loop;
        perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
        perform pg_catalog.set_config('request.jwt.claim.sub', v_ger::text, true);
      end if;
    end loop;
    begin
      perform 1 from crm.seguimiento_base(gen_random_uuid());
      raise exception 'POSTFLIGHT B10: una base inexistente no dio P0002' using errcode = 'P0001';
    exception when no_data_found then
      null;
    end;
    begin
      perform 1 from crm.seguimiento_base_detalle(gen_random_uuid(), null, 'avance');
      raise exception 'POSTFLIGHT B10: la cifra avance no dio 22023' using errcode = 'P0001';
    exception when invalid_parameter_value then
      null;
    end;
    perform pg_catalog.set_config('request.jwt.claims', '', true);
    perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
  end if;

  -- 4. Un analista no ve el seguimiento (42501, sin escribir).
  select e.perfil_id into v_vend from crm.equipo e
   where e.activo and private.rol_crm(e.perfil_id) = 'vendedor' order by e.perfil_id limit 1;
  if v_vend is not null then
    begin
      perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_vend, 'role', 'authenticated')::text, true);
      perform pg_catalog.set_config('request.jwt.claim.sub', v_vend::text, true);
      perform 1 from crm.seguimiento_bases();
      raise exception 'POSTFLIGHT B10: un analista pudo ver el seguimiento' using errcode = 'P0001';
    exception when insufficient_privilege then
      if sqlerrm <> 'Solo Supervisión y Gerencia ven el seguimiento de las bases' then
        raise exception 'POSTFLIGHT B10: el analista fue rechazado por otro motivo: %', sqlerrm using errcode = 'P0001';
      end if;
    end;
    perform pg_catalog.set_config('request.jwt.claims', '', true);
    perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
  end if;

  raise notice 'B10 CATALOGO OK: definicion unica del estado (private.bases_carga_estado_contacto) en B9 y B10, B9 r2 con su nucleo reemplazado y sus puertas intactas, 3 puertas de seguimiento, reactivar_lead_base_v2 y registrar_intento_base_v2 (EXECUTE solo authenticated), nucleos con capital y los de siempre como envoltorios (misma firma y ACL), puertas publicadas intactas, lista = B6b sin % dormidos sin repartir (% bases vivas visibles para Gerencia), resumen y detalle de F4 cuadran, censo igual. COMPORTAMIENTO CON ESCRITURAS NO PROBADO en esta migracion.',
    v_excluidos, coalesce(v_filas::text, 'sin foto');
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
-- Soltar la exclusión de migraciones (candado de SESIÓN tomado antes de la instantánea).
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261004223253' and name = 'crm_bases_cargadas_seguimiento' and cardinality(statements) = 1
                   and md5(statements[1]) = '92c5ee8188f483e0955e14b8f46f25e4') then
    raise exception 'REGISTRO: la fila 20261004223253 / crm_bases_cargadas_seguimiento no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261004223253 / crm_bases_cargadas_seguimiento (1 sentencia: el archivo entero)';
end $post$;
commit;

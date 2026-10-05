-- REGISTRO en supabase_migrations.schema_migrations de 20261004222602_crm_bases_cargadas_repartir.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega si
-- los objetos no están, o si la versión ya está registrada con otro nombre u otro contenido.
-- Generado con banco/generar-registrador.py. statements = el archivo entero (md5 8a169944b9394e45ed27f805978c26dc).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_bases_cargadas_repartir_registro'));
do $chk$
begin
  if (
    to_regprocedure('crm.repartir_base(uuid,uuid,jsonb)') is not null
    and to_regprocedure('crm.recoger_de_base(uuid,uuid,uuid)') is not null
    and to_regprocedure('crm.contactos_de_base(uuid,text)') is not null
    and to_regprocedure('private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)') is not null
    and to_regprocedure('private.bases_carga_recoger_core(uuid,uuid,uuid,uuid)') is not null
    and to_regprocedure('private.bases_carga_reparto_recogible(uuid,uuid,timestamptz,boolean)') is not null
    and to_regprocedure('private.bases_carga_reparto_estado(boolean,boolean,text,uuid,boolean,date,uuid,boolean,boolean,boolean,boolean,date)') is not null
  ) is not true then
    raise exception 'REGISTRO: la migración 20261004222602 no está aplicada; aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261004222602' and (coalesce(name, '') <> 'crm_bases_cargadas_repartir' or statements is distinct from array[$mig$-- 20261004222602_crm_bases_cargadas_repartir.sql
--
-- Bases cargadas · B9: repartir y recoger. Pedido de Miguel (03/10/2026: «darle 40 a un analista y 30 a otro», en bloques o
-- individual; paso 4 del flujo: «se puede recoger lo que un analista no tocó»), decisiones E1–E14
-- (`BASE PARA GESTION/BASES-CARGADAS.md`) y contrato FIJO de B9
-- (`BASE PARA GESTION/BASES-CARGADAS-CONTRATO.md`), sobre B7 (20261004160034) y B8 (20261004184501). Tres puertas DEFINER en
-- `crm` (validan, resuelven rol y ámbito en el servidor y delegan) y su núcleo en `private`:
--   · crm.repartir_base(operación, base, reparto jsonb) — bloque {"modo":"bloque","asignaciones":[{"analista_id","cantidad"}]}:
--     el servidor elige los contactos SIN REPARTIR más antiguos en la base (agregado_en, luego creado_en y id del lead) y salta
--     los que no se pueden repartir; si no alcanzan, NADA (22023, detail = disponibles, el número en texto). Individual
--     {"modo":"individual","asignaciones":[{"lead_id","analista_id"}]}: cada contacto de la base, sin repartir o repartido a
--     otro (se reasigna), y elegible; si uno no lo es, NADA (22023, detail {"rechazados":[{lead_id, motivo}]}); el que ya es de
--     ese analista sale «omitido» (ya_asignado). Todo o nada. Analista: activo, rol vendedor, del subárbol del supervisor DUEÑO
--     de la base (Gerencia: cualquiera, E4/E11). Respuesta {ok, operacion_id, base_id, modo, repartidos, por_analista
--     [{analista_id, cantidad}], omitidos [{lead_id|null, motivo[, cantidad]}]} — en bloque los omitidos van por motivo con
--     lead_id null y su cantidad (el servidor eligió: no hay referencia que dar y el recibo no crece con la base).
--   · crm.recoger_de_base(operación, base, analista) — vuelve a «sin repartir» (bandeja del supervisor dueño) lo de ese analista
--     SIN intento desde asignado_en y sin seguimiento activo (B6), hasta el tope por operación. Respuesta {ok, operacion_id,
--     base_id, analista_id, recogidos, omitidos, pendientes} (pendientes = recogibles que quedaron para otra operación: 0 casi
--     siempre).
--   · crm.contactos_de_base(base, estado default 'sin_repartir') — la lista para el reparto individual y la pestaña:
--     sin_repartir | repartidos | todos; estado ∈ sin_repartir · sin_tocar · trabajado · en_descanso · cita · reactivado ·
--     movido_otra_via · no_contactar (private.bases_carga_reparto_estado, UNA definición). Solo contactos que el actor VE y
--     siguen activos (private.bases_carga_lead_ref de B8): nada fuera de su ámbito. Lleva nombre, teléfono y distrito: la
--     pantalla los usa para marcar filas en el reparto individual (el actor ya los ve en su Base para gestión).
--   Las tres: Supervisión y Gerencia (otros → 42501); base visible (P0002, sin delatar si existe); repartir y recoger
--   idempotentes por (actor, id de operación) con recibo inmutable (tipo repartir / recoger) en crm.base_carga_operaciones: el
--   replay devuelve la MISMA respuesta (private.bases_carga_operacion_previa de B8: mismo pedido, base aún visible) y vuelve a
--   juzgar cada lead_id que el recibo nombra (P0002 si alguno ya no está a su alcance); el mismo id con otro pedido → 22023.
--
-- QUÉ CORRE AL REPARTIR (UPDATE crm.leads SET vendedor_id, asignado_supervisor_id de un DESCARTADO; inventario de los 31
-- disparadores de crm.leads en el banco a paridad, orden efectivo, y MEDIDO con pg_stat_xact_user_functions al repartir y al
-- recoger un contacto: corren los mismos 18 de crm.leads, una vez cada uno, más la auditoría y el sello de las tablas de
-- bases y los 4 de crm.actividades por la «reasignación»). Sin válvula nueva: es el camino de la casa —el mismo UPDATE que hacen
-- rescatar_descartes y la ficha (PATCH)— con el actor de la sesión (auth.uid() = el supervisor o Gerencia), y todos los
-- candados corren:
--   BEFORE: 000_base_cargada_solo_puerta (B7: origen y motivo base_cargada NO cambian, el capital no se vacía → pasa) ·
--   00_devolucion_equipo_solo_rpc (solo si el lead vuelve a la bandeja del propio supervisor desde un episodio de hoy: un
--   descartado no tiene episodio → pasa al recoger) · 00_guard_tenencia (analista destino activo vendedor/supervisor; nunca
--   analista y bandeja a la vez: por eso repartir pone asignado_supervisor_id NULL y recoger vendedor_id NULL; la bandeja de
--   un supervisor activo) · 00_seguimiento_activo (B6: con seguimiento activo del analista que lo tiene → P0409; la puerta lo
--   salta o lo rechaza ANTES con el mismo ayudante private.base_gestion_en_gestion_hasta, bajo el candado del lead) ·
--   01_sla_global (sin cambio de ciclo: conserva el sello) · before_update (inmutables) · bloquear_reasignacion (solo frena a
--   un actor con rol vendedor: el actor es Supervisión o Gerencia) · cambio_etapa (la etapa NO cambia) · protege_inversionista_id
--   · reasignacion (escribe la actividad «reasignación» A → B: el rastro que pide el contrato) · zz_sello_descarte (descartado
--   que sigue descartado: conserva descartado_en y descartado_por) · zzz_tenencia_desde (NULL: un descartado no tiene tenencia
--   operativa) · zzzz_usuario_retirado (descartado → no aplica). NO corren (no están en el SET): 00_disponibilidad_update
--   (teléfono, dni, no_contactar, etapa, activo, motivo), 000_no_contactar_puerta, zz_enlaza_identidad, zz_reapertura_solo_rpc,
--   zz_sello_base_gestion, conversion_con_inversion.
--   AFTER: audit_leads (bitácora) · 02_sla_versionado (sin cambio de ciclo, etapa ni activo: NO abre ciclo ni episodio SLA) ·
--   asignaciones (descartado = sin tenencia operativa: NO abre ni cierra episodio en lead_asignaciones) · zz_puente_identidad
--   (inversionista_id igual: nada) · zz_sync_tareas (las tareas pendientes siguen al lead; un descartado no tiene) ·
--   zzzz_conversion_responsable (solo leads operativos). La actividad «reasignación» pasa por trg_01_gestion_lead_serializada
--   (tipo de sistema: sin candado extra).
--   El lead SIGUE descartado/dormido (E7): ni ciclo SLA, ni episodio, ni llegada; el analista lo trabaja en su Base para gestión.
-- QUÉ FECHA VE EL ANALISTA («Mes», B5): crm.obtener_base_gestion da recibido_en = coalesce(tenencia_desde, creado_en)
--   (20261003162400:4,57) y private.trg_leads_tenencia_desde pone tenencia_desde = NULL a todo lead no operativo
--   (20260725012707:122; medido: el reparto la deja NULL): un descartado NUNCA la tiene y cualquier valor que escribiera B9 lo
--   borraría el disparador. Decisión: B9 NO toca tenencia_desde ni creado_en (tenencia_desde es la tenencia OPERATIVA que leen
--   cartera y SLA; inventarla en un dormido sería mentir). El «Mes» del contacto de base es su creado_en en Lima, el criterio
--   de la casa para el mes del analista (B5 y la regla «el analista se organiza por el mes del lead»: el de creado_en, cuándo
--   entró el lead): el del archivo, el mes de la carga; el armado desde el CRM, el mes en que entró al CRM. Cuándo se le
--   repartió vive en base_carga_leads.asignado_en (lo leen B10 —seguimiento, «sin tocar 3 días»— y F6 con el selector «Base»).
-- CANDADOS (orden de la casa, el de B8): (1) el de la operación (bases_carga_operacion_previa: actor + id; un doble clic espera
--   y recibe el recibo) → (2) la fila de la base FOR UPDATE NOWAIT (55P03 «Hay otra operación en curso de esta base;
--   reintenta»: repartir, recoger y los lotes de una base van de a uno; ninguno espera al otro) → (3) los leads FOR UPDATE SKIP
--   LOCKED y se evalúa SOLO lo efectivamente bloqueado, en otra sentencia (r2 de B8): reactivar, vetar, el intento B6 y las
--   reasignaciones toman la fila del lead, así que lo bloqueado no cambia hasta el commit; lo que otro proceso tiene tomado no
--   se espera: en bloque se salta (omitido «ocupado»), en individual el reparto entero falla con 55P03 (todo o nada). r1 (Codex
--   P2): se bloquea SOLO lo necesario — en bloque, por tandas y en el orden del reparto, solo los que faltan entre los elegibles
--   de una foto previa sin candados; en recoger, solo lo recogible y hasta el tope; en individual, solo lo pedido y después de
--   comprobar el ámbito (auditor P3) —. Sin esperas en (2) y (3) no hay ciclo posible con ningún escritor. La fecha asignado_en
--   es clock_timestamp() DESPUÉS de los candados: un intento que esperaba al lead queda después (trg_01_gestion_lead_serializada
--   le pone clock_timestamp tras tomar el lead) y uno anterior, antes. Un contacto que recibió un intento DURANTE la operación no
--   se reparte (bloque: «ocupado»; individual: 55P03): la «reasignación» lleva la hora de la sentencia y el analista nuevo lo
--   heredaría por B6. Requiere READ COMMITTED (cada sentencia ve lo confirmado tras el candado; 0A000 si no).
-- ERRORES DEL UPDATE: lo transitorio (private.bases_carga_error_transitorio de B8) aborta con el MISMO código y «… se
--   interrumpió (código); reintenta»; cualquier otro, con su código y un mensaje sin datos (sin el detail del disparador).
-- TOPES (private.bases_carga_reparto_constantes, MEDIDOS frente al statement_timeout de 8 s de authenticated): 500 contactos por
--   operación (bloque: la suma; individual: las filas; recoger: por llamada; lo que excede, en «pendientes») y 100 analistas
--   por reparto (con 500 ya_asignado y 100 analistas el recibo queda < 64 KB). Banco (por la puerta, como authenticated):
--   repartir 500 en 0,43 s, 2000 en 1,7 s, 5000 en 4,3 s (~0,85 ms por contacto: sus 18 disparadores); recoger igual; la lista
--   de 5000 en 0,2 s. Con la rama micro de B8 3–5× más lenta que el banco, 500 deja margen ×4–×6; la rama lo mide.
-- CENSO: ninguna función nueva usa count( ni sum(1) (cardinality de array_agg, get diagnostics); el postflight exige el censo
--   analítico igual a la foto previa.
-- B6, CAMBIO DE REGLA (r1, decisión de Miguel 04/10/2026): private.base_gestion_en_gestion_hasta —la fuente única del
--   seguimiento activo— cuenta solo los intentos hechos DESDE QUE EL DUEÑO ACTUAL RECIBIÓ EL LEAD (la última actividad
--   «reasignación» hacia él, que escribe solo private.trg_leads_reasignacion en toda vía; si nació suyo, desde el descarte, como
--   antes). Si el supervisor llama a un contacto de su bandeja y luego lo reparte, o el dueño anterior lo llamó, el analista
--   nuevo NO queda en gestión ni bloquea recoger o reasignar. Lo que Supervisión registra sobre un lead que ya es del analista
--   cuenta para él. Por qué la «reasignación» y no base_carga_leads.asignado_en: vale para toda vía, la API no la puede escribir
--   (policy actividades_insert) y no reinicia la protección de un analista que YA tenía el lead (armado desde el CRM y
--   «repartido» a su mismo analista: no lo recibió entonces). Consumidores: el candado B6 (toda vía), el gris del rescate, armar
--   (B8) y B9; ninguno cambia de texto. Queda: un intento del supervisor sobre su bandeja confirmado durante la sentencia de
--   otra vía que mueve ese lead (no B9) lo heredaría el nuevo dueño (milisegundos; B9 lo evita, ver CANDADOS). r2: solo corta
--   una «reasignación» que cambió de verdad el vendedor (auditor P3); la rellamada cuenta solo si la programó el último intento
--   posterior al corte, leída de su actividad (Codex r2: la columna del lead pudo dejarla el dueño anterior). Sin actividad de
--   reasignación (lead que nació suyo o histórico anterior a ella): cuenta desde el descarte, como B6 — puede bloquear DE MÁS,
--   nunca de menos. A → B → A: cuenta desde que volvió a A (lo de B y lo de A antes de irse no bloquea). Las actividades
--   «reasignación» no se cambian ni se borran: authenticated solo tiene INSERT y SELECT en crm.actividades (la policy de INSERT
--   excluye el tipo), y las 4 vías DEFINER que hacen UPDATE en actividades (base_gestion_intento_core, llamada_registrar,
--   llamada_registrar_v4, deshacer_resultado_llamada) solo tocan la actividad que acaban de crear o un resultado de llamada
--   propio: probado en el banco (suite Q) y por la API (gate); service_role (clave del servidor, sin usuario) sí podría, como en
--   toda tabla, y el patrón de sello de B6c también la exime: no se añade sello.
-- QUÉ NO CAMBIA: B7 (tablas, sello, CHECK), B8 (sus 21 funciones y su disparador: el preflight y el postflight fijan sus
--   huellas), crm.leads (columnas, grants, policies, disparadores), crm.obtener_base_gestion (B10 la cambia), el disparador
--   de B6 y crm.rescate_descartes_mes (solo cambia la ayudante que usan).
-- PRECONDICIÓN: B8 aplicada (20261004184501) — el preflight fija las definiciones vivas de las que depende (núcleo de B8,
--   ayudantes de la casa, la ayudante de B6 que reemplaza —exacta— y las 12 funciones de disparador de las que depende lo
--   probado —11 de crm.leads y la de crm.actividades— con la DEFINICIÓN exacta de sus disparadores (r1, Codex P2: evento,
--   columnas, WHEN y función; un homónimo con WHEN (false) no pasa), habilitados). Las de disparador NO se midieron en
--   producción (las de B8 sí, en su rama): la rama con datos lo confirma; si alguna difiere, el preflight se niega.
-- REVERSA: supabase/scripts/base-gestion/reversa-b9.sql (solo funciones: NO borra ni cambia filas; las asignaciones y los
--   recibos quedan y reaplicar B9 los vuelve a servir; repone la ayudante de B6 con su texto y comentario exactos). Comprobación
--   tras aplicar: supabase/scripts/base-gestion/b9-comprobar-tras-aplicar.sql.
-- r2 (04/10): Codex r2 BLOCK (1 P2: candados retenidos sin máximo acumulado) y auditor 2.ª pasada PASS con P3 → presupuesto de
--   candados (private.bases_carga_reparto_constantes().holgura_candados = 50: como mucho greatest(n + 50, ceil(n × 1,1)) filas
--   bloqueadas por operación, aceptadas o no; agotado → 55P03 «Los contactos están cambiando; reintenta», todo o nada); la
--   rellamada y el corte de B6 (arriba).
-- r1 (04/10): Codex r1 BLOCK (3 P2) y auditor-rls PASS con P2/P3 → la regla de B6 (arriba); Gerencia puede volver a repartir
--   lo que B9 le dio a un analista fuera del equipo del dueño (la pertenencia dice que ese analista lo tiene; lo movido por otra
--   vía, no); candados solo de lo necesario; preflight con la definición de los disparadores; recoger de un analista de baja
--   no exige «sin intento» (manda B6); el ámbito del individual se comprueba antes de los candados.
-- CANDADOS DE TABLA: ninguno. B9 solo crea funciones (sin DDL de tablas ni disparadores): el único candado es el de migración
--   de la casa (crm_migracion_funciones), tomado ANTES del preflight; validar las funciones SQL toma ACCESS SHARE de las tablas
--   que nombran (no frena lecturas ni escrituras). Sin DML: el postflight es SOLO de catálogo.
begin;
set transaction isolation level read committed;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

select pg_advisory_xact_lock(hashtext('crm_migracion_funciones'));

-- Foto del censo analítico (solo catálogo), bajo el candado de migración.
create temp table _b9_censo_antes on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $preflight$
declare
  v_ident text := 'md5(prosrc|prosecdef|provolatile|proconfig|proowner)';
begin
  if (
    -- Nada de B9 existe todavía.
    to_regprocedure('crm.repartir_base(uuid,uuid,jsonb)') is null
    and to_regprocedure('crm.recoger_de_base(uuid,uuid,uuid)') is null
    and to_regprocedure('crm.contactos_de_base(uuid,text)') is null
    and not exists (select 1 from pg_proc p where p.pronamespace in ('crm'::regnamespace, 'private'::regnamespace)
                     and (p.proname like 'bases\_carga\_reparto\_%' or p.proname in ('bases_carga_repartir_core', 'bases_carga_recoger_core',
                                                                                         'bases_carga_contactos_core', 'repartir_base',
                                                                                         'recoger_de_base', 'contactos_de_base')))
    -- B7 aplicada: las tablas y los tipos de recibo de B9 en su CHECK.
    and to_regclass('crm.bases_carga') is not null and to_regclass('crm.base_carga_leads') is not null
    and to_regclass('crm.base_carga_operaciones') is not null
    and (select pg_get_constraintdef(c.oid) = 'CHECK ((tipo = ANY (ARRAY[''crear''::text, ''cargar_lote''::text, ''armar''::text, ''repartir''::text, ''recoger''::text])))'
                and c.convalidated
           from pg_constraint c where c.conrelid = 'crm.base_carga_operaciones'::regclass and c.conname = 'base_carga_operaciones_tipo_check')
    and (select pg_get_constraintdef(c.oid) = 'CHECK ((((analista_id IS NULL) = (asignado_en IS NULL)) AND ((analista_id IS NULL) = (asignado_por IS NULL))))'
                and c.convalidated
           from pg_constraint c where c.conrelid = 'crm.base_carga_leads'::regclass and c.conname = 'base_carga_leads_asignacion_coherente')
    -- B8 aplicada: las puertas y el núcleo que B9 usa, con la identidad de B8 (si cambiaran, lo probado no valdría).
    and to_regprocedure('crm.cargar_base_lote(uuid,uuid,jsonb)') is not null
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '0b4e20b805109892a56d2d127cd54a9c'
           from pg_proc p where p.oid = to_regprocedure('private.bases_carga_operacion_previa(uuid,text,uuid,text,text,uuid[])'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '50af07f268c21b5d4b07e1d79de5c5bc'
           from pg_proc p where p.oid = to_regprocedure('private.bases_carga_base_visible(uuid,text,uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '0571e6b4075a6e2c88b46d09378e6cc6'
           from pg_proc p where p.oid = to_regprocedure('private.bases_carga_subarbol(uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '041d852f8d69017c77a2f9fcd8cbab93'
           from pg_proc p where p.oid = to_regprocedure('private.bases_carga_en_subarbol(uuid[],uuid,uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '9f671b71f96facf74c7ee4dcec02b6f9'
           from pg_proc p where p.oid = to_regprocedure('private.bases_carga_lead_ref(uuid,text,uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '39037380cbf5e8286d8e6c4df2b832a0'
           from pg_proc p where p.oid = to_regprocedure('private.bases_carga_error_transitorio(text)'))
    -- Ayudantes de la casa (las huellas que midió la rama con datos de B8 en producción).
    -- r1: la ayudante de B6 que se REEMPLAZA (regla de Miguel 04/10), exacta: identidad, cuerpo, ACL y comentario de B6
    -- (20261003162500:46-71, medidos en el banco a paridad; la identidad, también en producción por la rama de B8).
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = 'e90da5df4c53fa1c30f0ca5f71431631'
                and md5(p.prosrc) = 'af0701a9e095e1004a64b7e289789d7c'
                and p.proacl is not null and p.proacl::text = '{postgres=X/postgres}'
                and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '6b4c155f38d0722f9e9247547b5c3c2a'
           from pg_proc p where p.oid = to_regprocedure('private.base_gestion_en_gestion_hasta(uuid)'))
    -- Sus tres consumidores vivos (pg_proc, 04/10): el candado B6, el gris del rescate y armar de B8 (B9 se suma).
    and (select count(*) from pg_proc p where p.prosrc ~ 'base_gestion_en_gestion_hasta') = 3
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = 'c4ae35f90e850548653a25f08d25327c'
           from pg_proc p where p.oid = to_regprocedure('private.base_gestion_lead_visible(uuid,text,uuid,uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = 'b35bca38019cdd27b801cf4c39d4c756'
           from pg_proc p where p.oid = to_regprocedure('private.es_destino_crm_activo(uuid,text[])'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '16960a2a21cc5c372431c2dd67acafe4'
           from pg_proc p where p.oid = to_regprocedure('private.rol_crm(uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '45ae492c03234b80336c0b8f5c8ac09b'
           from pg_proc p where p.oid = to_regprocedure('private.vendedor_ids_visibles(uuid)'))
    -- Los disparadores que corren al repartir y recoger (inventario de la cabecera), con la identidad ensayada.
    and (select string_agg(x.firma, ',' order by x.firma) from (values
           ('private.trg_leads_guard_seguimiento_activo()', '48f48c865acf806b0e1d03846072ac17'),
           ('private.trg_leads_guard_tenencia()', '06ab77d35e1db9fc976db25808015e9e'),
           ('private.trg_devolucion_equipo_solo_rpc()', 'ba059074b83a496a7a502af3e24d994a'),
           ('private.trg_leads_bloquear_reasignacion()', '8360dfacd7f942de14f47d68def08491'),
           ('private.trg_leads_reasignacion()', '18e904add66331b2af6cdf07b2bbdb68'),
           ('private.trg_leads_asignaciones()', '27dbc5d14c81bad16a82acd586f4666c'),
           ('private.trg_leads_tenencia_desde()', 'c5a4fcee9c7fbc6334c89ef3616a6bb4'),
           ('private.trg_leads_sla_versionado()', 'f9bfea320eedbdc8fce08ba98776a1b2'),
           ('private.trg_leads_sync_tareas()', '9ec20bfa9b24052a1dec16f3faf2a330'),
           ('private.no_asignar_usuario_retirado()', '66b00bc02936f5243d28c6009849a35c'),
           ('private.trg_leads_base_cargada_solo_puerta()', '9074e2e17457827b9e81f059087c5219'),
           ('private.trg_gestion_lead_serializada()', 'b738fd353b8c287ac259a0a3de25657b')) x(firma, huella)
         left join pg_proc p on p.oid = to_regprocedure(x.firma)
        where (md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                   || '|' || p.proowner::regrole::text) = x.huella) is not true) is null
    -- r1 (Codex P2): la DEFINICIÓN exacta de esos disparadores (evento, momento, columnas, WHEN —el de B6— y función), uno por
    -- nombre y habilitados: un homónimo con WHEN (false) o sin su evento no pasa.
    and (select count(*) from (values
           ('crm.leads', 'trg_leads_000_base_cargada_solo_puerta', 'CREATE TRIGGER trg_leads_000_base_cargada_solo_puerta BEFORE INSERT OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_base_cargada_solo_puerta()'),
           ('crm.leads', 'trg_leads_00_devolucion_equipo_solo_rpc', 'CREATE TRIGGER trg_leads_00_devolucion_equipo_solo_rpc BEFORE UPDATE OF vendedor_id, asignado_supervisor_id ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_devolucion_equipo_solo_rpc()'),
           ('crm.leads', 'trg_leads_00_guard_tenencia', 'CREATE TRIGGER trg_leads_00_guard_tenencia BEFORE INSERT OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_guard_tenencia()'),
           ('crm.leads', 'trg_leads_00_seguimiento_activo', 'CREATE TRIGGER trg_leads_00_seguimiento_activo BEFORE UPDATE ON crm.leads FOR EACH ROW WHEN (((old.etapa = ''descartado''::text) AND (new.vendedor_id IS DISTINCT FROM old.vendedor_id))) EXECUTE FUNCTION private.trg_leads_guard_seguimiento_activo()'),
           ('crm.leads', 'trg_leads_02_sla_versionado', 'CREATE TRIGGER trg_leads_02_sla_versionado AFTER INSERT OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_sla_versionado()'),
           ('crm.leads', 'trg_leads_asignaciones', 'CREATE TRIGGER trg_leads_asignaciones AFTER INSERT OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_asignaciones()'),
           ('crm.leads', 'trg_leads_bloquear_reasignacion', 'CREATE TRIGGER trg_leads_bloquear_reasignacion BEFORE UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_bloquear_reasignacion()'),
           ('crm.leads', 'trg_leads_reasignacion', 'CREATE TRIGGER trg_leads_reasignacion BEFORE UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_reasignacion()'),
           ('crm.leads', 'trg_leads_zz_sync_tareas', 'CREATE TRIGGER trg_leads_zz_sync_tareas AFTER UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_sync_tareas()'),
           ('crm.leads', 'trg_leads_zzz_tenencia_desde', 'CREATE TRIGGER trg_leads_zzz_tenencia_desde BEFORE INSERT OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_tenencia_desde()'),
           ('crm.leads', 'trg_zzzz_usuario_retirado', 'CREATE TRIGGER trg_zzzz_usuario_retirado BEFORE INSERT OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.no_asignar_usuario_retirado()'),
           ('crm.actividades', 'trg_01_gestion_lead_serializada', 'CREATE TRIGGER trg_01_gestion_lead_serializada BEFORE INSERT ON crm.actividades FOR EACH ROW EXECUTE FUNCTION private.trg_gestion_lead_serializada()')) x(tabla, nombre, definicion)
          join pg_trigger t on t.tgrelid = x.tabla::regclass and t.tgname = x.nombre
         where t.tgenabled = 'O' and pg_get_triggerdef(t.oid) = x.definicion) = 12
  ) is not true then
    raise exception 'PREFLIGHT B9: ya aplicada o a medias, B7/B8 no aplicadas, o una funcion o disparador de los que depende no es el medido (%)', v_ident;
  end if;
end;
$preflight$;

-- ── 1 · B6, cambio de regla (Miguel, 04/10/2026): el seguimiento activo cuenta desde que el DUEÑO ACTUAL recibió el lead ───
-- Texto vivo de 20261003162500:46-71 (el preflight lo fija) con UN cambio: los intentos cuentan desde la última «reasignación»
-- hacia el dueño actual (si no hay, el lead nació suyo: desde el descarte, como antes). Misma firma, volatilidad, seguridad,
-- search_path, dueño y ACL (CREATE OR REPLACE los conserva); el comentario se actualiza. Consumidores (pg_proc, 04/10): el
-- candado private.trg_leads_guard_seguimiento_activo (toda vía), el gris de crm.rescate_descartes_mes y
-- private.bases_carga_armar_core (B8); B9 se suma (repartir, recoger, la lista). Ninguno cambia de texto.
create or replace function private.base_gestion_en_gestion_hasta(p_lead_id uuid)
returns date
language sql stable security invoker set search_path = '' as $function$
  -- Hasta qué día (Lima) el lead descartado sigue en gestión de su analista: el último intento de la base del ciclo vigente
  -- (desde descartado_en) + 7 días, o el día de la rellamada agendada en ese ciclo, lo que llegue más lejos. NULL si ya no
  -- está en gestión, si no está descartado o si su dueño ya no está activo (una baja libera sus leads).
  -- B9 r1 (Miguel, 04/10/2026): solo cuentan los intentos hechos DESDE QUE EL DUEÑO ACTUAL RECIBIÓ EL LEAD: la última
  -- actividad «reasignación» hacia él (la escribe SOLO private.trg_leads_reasignacion, en toda vía que mueve el lead —rescate,
  -- ficha, tomar, derivar, B9—; la API no puede insertarla: policy actividades_insert). Sin ella, el lead nació suyo: desde el
  -- descarte, como antes (un histórico sin esa actividad puede bloquear DE MÁS, nunca de menos). Lo que Supervisión registra
  -- sobre un lead que ya es del analista cuenta para el analista. A → B → A: cuenta desde que VOLVIÓ a A.
  -- B9 r2: solo una «reasignación» que de verdad cambió el vendedor corta (auditor P3); y la rellamada cuenta solo si la
  -- programó ESE último intento (posterior al corte), leída de su actividad y no de la columna del lead, que pudo dejar un
  -- dueño anterior (Codex r2).
  select case when x.hasta >= (pg_catalog.now() at time zone 'America/Lima')::date then x.hasta end
    from (
      select greatest(
               (i.ultimo at time zone 'America/Lima')::date + 7,
               (i.proxima at time zone 'America/Lima')::date) as hasta
        from crm.leads l
        cross join lateral (
          select max(r.creado_en) as desde
            from crm.actividades r
           where r.lead_id = l.id
             and r.tipo = 'reasignacion'
             and r.metadata->>'vendedor_nuevo' = l.vendedor_id::text
             and (r.metadata->>'vendedor_anterior') is distinct from (r.metadata->>'vendedor_nuevo')
        ) t
        cross join lateral (
          select a.creado_en as ultimo, (a.metadata->>'proxima_llamada_en')::timestamptz as proxima
            from crm.actividades a
           where a.lead_id = l.id
             and a.metadata->>'evento' = 'intento_base'
             and a.creado_en >= l.descartado_en
             and (t.desde is null or a.creado_en >= t.desde)
           order by a.creado_en desc, a.id desc
           limit 1
        ) i
       where l.id = p_lead_id
         and l.etapa = 'descartado'
         and exists (select 1 from crm.equipo e join public.perfiles p on p.id = e.perfil_id
                      where e.perfil_id = l.vendedor_id and e.activo and p.activo)
    ) x
$function$;
comment on function private.base_gestion_en_gestion_hasta(uuid) is
  'B6 (Miguel, 03/10/2026; regla cambiada en B9 r1/r2, Miguel 04/10/2026): seguimiento activo de un lead descartado. Último día (Lima) en que sigue en gestión de su analista: último intento de la base hecho DESDE QUE EL DUEÑO ACTUAL RECIBIÓ EL LEAD (la última «reasignación» hacia él que cambió de verdad el vendedor; si no hay —nació suyo o es un histórico—, desde el descarte: puede bloquear de más, nunca de menos; A → B → A cuenta desde que volvió a A) + 7 días, o el día de la rellamada que programó ESE último intento (leída de su actividad, no de la columna del lead), el mayor. Una llamada del supervisor sobre su bandeja antes de repartir, o la del dueño anterior, NO bloquea al nuevo. NULL si no hay seguimiento activo, si el lead no está descartado o si su dueño ya no está activo. Fuente única del candado (trg_leads_00_seguimiento_activo), del gris del Centro de rescate, de armar (B8) y de repartir/recoger (B9). INVOKER, sin EXECUTE para roles de la API.';

-- ── 2 · Núcleo: topes, rol, analista y las definiciones únicas ─────────────────────────────────────────────────────────
create function private.bases_carga_reparto_constantes()
returns table(max_contactos integer, max_analistas integer, holgura_candados integer)
language sql
immutable
security invoker
set search_path = ''
as $function$
  select 500, 100, 50;
$function$;

create function private.bases_carga_reparto_rol(p_actor uuid)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_rol text := private.rol_crm(p_actor);
begin
  -- Rol resuelto en el servidor (private.rol_crm); solo Supervisión y Gerencia reparten, recogen y listan una base.
  if p_actor is null or (v_rol in ('supervisor', 'gerencia')) is not true then
    raise exception 'Solo Supervisión y Gerencia reparten y ven las bases' using errcode = '42501';
  end if;
  return v_rol;
end;
$function$;

create function private.bases_carga_reparto_analista(p_rol text, p_subarbol uuid[], p_analista_id uuid)
returns void
language plpgsql
stable
security invoker
set search_path = ''
as $function$
begin
  -- E4/E11: Supervisión reparte a SU equipo —el subárbol del supervisor DUEÑO de la base (private.bases_carga_subarbol)—;
  -- Gerencia, a cualquiera. El analista: activo y con rol vendedor (el guard de tenencia admitiría también un supervisor).
  if p_analista_id is null then
    raise exception 'Cada asignación lleva su analista' using errcode = '22023';
  end if;
  if p_rol is distinct from 'gerencia' and (p_analista_id = any (p_subarbol)) is not true then
    raise exception 'Analista no encontrado o fuera del equipo de la base' using errcode = 'P0002';
  end if;
  if private.es_destino_crm_activo(p_analista_id, array['vendedor']::text[]) is not true then
    raise exception 'El analista no existe, no está activo o no es analista' using errcode = '22023';
  end if;
end;
$function$;

create function private.bases_carga_reparto_motivo(p_activo boolean, p_en_ambito boolean, p_etapa text, p_no_contactar boolean,
                                                   p_enfriado_hasta date, p_en_gestion boolean, p_hoy date)
returns text
language sql
immutable
security invoker
set search_path = ''
as $function$
  -- UNA definición de «este contacto de la base no se puede repartir ahora» (NULL = sí se puede), con el motivo:
  --   inactivo (retirado) · fuera_de_ambito (otra vía lo sacó del subárbol del dueño) · no_descartado (salió de la base:
  --   reactivado u otra vía) · no_contactar (veto) · en_descanso (enfriado_hasta B4) · en_gestion (seguimiento activo B6).
  -- La usan repartir (bloque e individual). Las condiciones con `is not true` / `is true`: un NULL nunca habilita.
  select case
           when p_activo is not true then 'inactivo'
           when p_en_ambito is not true then 'fuera_de_ambito'
           when p_etapa is distinct from 'descartado' then 'no_descartado'
           when p_no_contactar is not false then 'no_contactar'
           when p_enfriado_hasta is not null and p_enfriado_hasta > p_hoy then 'en_descanso'
           when p_en_gestion is true then 'en_gestion'
         end;
$function$;

create function private.bases_carga_reparto_hechos(p_lead_id uuid, p_desde timestamptz)
returns table(intento boolean, cita boolean, reactivado boolean)
language sql
stable
security invoker
set search_path = ''
as $function$
  -- UNA definición de «qué pasó desde» un momento, por las actividades de la base (sin agregados de conteo: censo): algún
  -- intento (evento intento_base, el que escribe private.base_gestion_intento_core), si alguno agendó cita, y si se reactivó
  -- desde la base (evento reactivacion_base de private.base_gestion_reactivar_core). Su creado_en lo sella
  -- trg_01_gestion_lead_serializada con clock_timestamp DESPUÉS de tomar el lead: un hecho que esperaba al reparto queda
  -- después de asignado_en. p_desde = asignado_en (repartido) o cuándo entró a la base (sin repartir). Lo usan recoger (sin
  -- intento) y el estado de contactos_de_base.
  select coalesce(pg_catalog.bool_or(a.metadata ->> 'evento' = 'intento_base'), false),
         coalesce(pg_catalog.bool_or(a.metadata ->> 'evento' = 'intento_base' and a.metadata ->> 'resultado' = 'agendo_reunion'), false),
         coalesce(pg_catalog.bool_or(a.metadata ->> 'evento' = 'reactivacion_base'), false)
    from crm.actividades a
   where a.lead_id = p_lead_id
     and a.metadata ->> 'evento' in ('intento_base', 'reactivacion_base')
     and a.creado_en >= p_desde;
$function$;

create function private.bases_carga_reparto_recogible(p_lead_id uuid, p_analista_id uuid, p_asignado_en timestamptz, p_baja boolean)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $function$
  -- UNA definición de «se puede recoger» (la usan la foto y la revisión bajo candado de recoger): sigue vivo, descartado y en
  -- manos de ESE analista (lo movido por otra vía no se deshace, E14), sin intento desde que se le repartió —salvo que el
  -- analista esté de baja (r1, auditor P3): entonces manda B6, que la baja libera— y sin seguimiento activo B6. `is true`.
  select coalesce((select (l.activo and l.etapa = 'descartado' and l.vendedor_id = p_analista_id
                           and (p_baja is true or not h.intento)
                           and private.base_gestion_en_gestion_hasta(l.id) is null) is true
                     from crm.leads l
                     cross join lateral private.bases_carga_reparto_hechos(l.id, p_asignado_en) h
                    where l.id = p_lead_id), false);
$function$;

create function private.bases_carga_reparto_estado(p_activo boolean, p_no_contactar boolean, p_etapa text, p_vendedor_id uuid,
                                                   p_en_ambito boolean, p_enfriado_hasta date, p_analista_id uuid,
                                                   p_intento boolean, p_cita boolean, p_reactivado boolean, p_en_gestion boolean,
                                                   p_hoy date)
returns text
language sql
immutable
security invoker
set search_path = ''
as $function$
  -- UNA definición del estado de un contacto de la base (contrato B9), en este orden:
  --   no_contactar · movido_otra_via (retirado; repartido pero otro lo tiene; sin repartir fuera del ámbito del dueño; o salió
  --   del descarte por otra vía —E14—) · cita (salió del descarte con un intento «agendó cita») · reactivado (salió del
  --   descarte reactivado desde la base) · en_descanso · sin repartir: trabajado si alguien lo tiene en seguimiento activo
  --   (B6: no se puede repartir) o sin_repartir · repartido: trabajado (≥ 1 intento) o sin_tocar. Los hechos (intento, cita,
  --   reactivado) son los de private.bases_carga_reparto_hechos desde asignado_en o, sin repartir, desde que entró a la base.
  select case
           when p_no_contactar is not false then 'no_contactar'
           when p_activo is not true then 'movido_otra_via'
           when p_analista_id is not null and p_vendedor_id is distinct from p_analista_id then 'movido_otra_via'
           when p_analista_id is null and p_en_ambito is not true then 'movido_otra_via'
           when p_etapa is distinct from 'descartado' and p_cita is true then 'cita'
           when p_etapa is distinct from 'descartado' and p_reactivado is true then 'reactivado'
           when p_etapa is distinct from 'descartado' then 'movido_otra_via'
           when p_enfriado_hasta is not null and p_enfriado_hasta > p_hoy then 'en_descanso'
           when p_analista_id is null then case when p_en_gestion is true then 'trabajado' else 'sin_repartir' end
           when p_intento is true then 'trabajado'
           else 'sin_tocar'
         end;
$function$;

-- ── 3 · Núcleo: repartir, recoger y la lista ───────────────────────────────────────────────────────────────────────────
create function private.bases_carga_repartir_core(p_actor uuid, p_operacion_id uuid, p_base_id uuid, p_reparto jsonb)
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
                   private.bases_carga_reparto_motivo(l.activo,
                                                      private.bases_carga_en_subarbol(v_subarbol, l.vendedor_id, l.asignado_supervisor_id),
                                                      l.etapa, l.no_contactar, l.enfriado_hasta,
                                                      private.base_gestion_en_gestion_hasta(l.id) is not null, v_hoy) as motivo
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
         where private.bases_carga_reparto_motivo(l.activo,
                                                  private.bases_carga_en_subarbol(v_subarbol, l.vendedor_id, l.asignado_supervisor_id),
                                                  l.etapa, l.no_contactar, l.enfriado_hasta,
                                                  private.base_gestion_en_gestion_hasta(l.id) is not null, v_hoy) is null
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
                    select l.id, coalesce(private.bases_carga_reparto_motivo(l.activo,
                                            private.bases_carga_en_subarbol(v_subarbol, l.vendedor_id, l.asignado_supervisor_id),
                                            l.etapa, l.no_contactar, l.enfriado_hasta,
                                            private.base_gestion_en_gestion_hasta(l.id) is not null, v_hoy), 'ocupado')
                      from crm.leads l where l.id = any (v_examinados)) y
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
             l.vendedor_id, l.asignado_supervisor_id
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

create function private.bases_carga_recoger_core(p_actor uuid, p_operacion_id uuid, p_base_id uuid, p_analista_id uuid)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  v_rol text := private.bases_carga_reparto_rol(p_actor);
  v_max integer;
  v_md5 text;
  v_prev jsonb;
  v_sup uuid;
  v_base crm.bases_carga%rowtype;
  v_subarbol uuid[];
  v_baja boolean;
  v_recogibles uuid[];
  v_recoger uuid[] := '{}';
  v_lote uuid[];
  v_marca bigint := 0;
  v_hasta bigint;
  v_falta integer;
  v_holgura integer;
  v_presupuesto integer;
  v_tomados integer := 0;
  v_pendientes integer;
  v_total integer;
  v_upd integer;
  v_n integer;
  v_estado text;
  v_resp jsonb;
begin
  select k.max_contactos, k.holgura_candados into v_max, v_holgura from private.bases_carga_reparto_constantes() k;
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'Recoger requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation')
      using errcode = '0A000';
  end if;
  if p_base_id is null or p_analista_id is null then
    raise exception 'La base y el analista son obligatorios' using errcode = '22023';
  end if;
  v_md5 := pg_catalog.md5(pg_catalog.jsonb_build_object('tipo', 'recoger', 'base_id', p_base_id, 'analista_id', p_analista_id)::text);
  v_prev := private.bases_carga_operacion_previa(p_actor, v_rol, p_operacion_id, 'recoger', v_md5);
  if v_prev is not null then
    return v_prev;  -- sin referencias a leads: solo cifras
  end if;

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
    raise exception 'La base está retirada: no se recoge' using errcode = '22023';
  end if;
  -- Lo recogido vuelve a la bandeja del dueño: tiene que ser un supervisor activo (el guard de tenencia lo exige igual).
  if private.es_destino_crm_activo(v_base.supervisor_id, array['supervisor']::text[]) is not true then
    raise exception 'El supervisor dueño de la base ya no está activo: no se puede recoger' using errcode = '22023';
  end if;
  v_subarbol := array(select private.bases_carga_subarbol(v_base.supervisor_id));
  -- Supervisión recoge de SU equipo (activo o no: recoger lo de un analista dado de baja es justo el caso); Gerencia, de cualquiera.
  if v_rol is distinct from 'gerencia' and (p_analista_id = any (v_subarbol)) is not true then
    raise exception 'Analista no encontrado o fuera del equipo de la base' using errcode = 'P0002';
  end if;

  -- r1 (auditor P3): de un analista dado de baja no se exige «sin intento» (manda B6, que la baja libera).
  v_baja := private.es_destino_crm_activo(p_analista_id, array['vendedor']::text[]) is not true;
  -- Foto SIN candados: lo repartido a ese analista en esta base y, en orden de reparto, lo recogible
  -- (private.bases_carga_reparto_recogible, una definición).
  select coalesce(pg_catalog.array_agg(bl.lead_id order by bl.asignado_en, bl.lead_id)
                    filter (where private.bases_carga_reparto_recogible(bl.lead_id, p_analista_id, bl.asignado_en, v_baja)), '{}'),
         pg_catalog.cardinality(pg_catalog.array_agg(bl.lead_id))
    into v_recogibles, v_total
    from crm.base_carga_leads bl
   where bl.base_id = p_base_id and bl.activo and bl.analista_id = p_analista_id;
  v_total := coalesce(v_total, 0);
  -- r1 (Codex P2): candado SOLO de lo que se recoge, hasta el tope: por tandas, en ese orden, FOR UPDATE SKIP LOCKED (lo tomado
  -- por otro proceso queda); bajo el candado, en otra sentencia, se vuelve a juzgar con la misma definición. r2 (Codex P2):
  -- presupuesto de candados acumulado, como en repartir, sobre lo que hace falta (el tope o lo recogible, lo menor).
  v_presupuesto := greatest(least(v_max, pg_catalog.cardinality(v_recogibles)) + v_holgura,
                            pg_catalog.ceil(least(v_max, pg_catalog.cardinality(v_recogibles)) * 1.1)::integer);
  loop
    v_falta := v_max - pg_catalog.cardinality(v_recoger);
    exit when v_falta <= 0;
    if v_tomados >= v_presupuesto then
      raise exception 'Los contactos están cambiando; reintenta' using errcode = '55P03';
    end if;
    select coalesce(pg_catalog.array_agg(b.id order by b.o), '{}'), max(b.o) into v_lote, v_hasta
      from (select l.id, p.o
              from crm.leads l
              join unnest(v_recogibles) with ordinality as p(id, o) on p.id = l.id
             where p.o > v_marca
             order by p.o
             limit least(v_falta, v_presupuesto - v_tomados)
               for update of l skip locked) b;
    exit when v_hasta is null;
    v_marca := v_hasta;
    v_tomados := v_tomados + pg_catalog.cardinality(v_lote);
    v_recoger := v_recoger || array(
      select x.id from unnest(v_lote) with ordinality as x(id, o)
        join crm.base_carga_leads bl on bl.lead_id = x.id and bl.base_id = p_base_id and bl.activo and bl.analista_id = p_analista_id
       where private.bases_carga_reparto_recogible(x.id, p_analista_id, bl.asignado_en, v_baja)
       order by x.o);
  end loop;
  -- Con el tope alcanzado, lo recogible que quedó sin examinar es «pendiente» (otra llamada); lo demás, omitido.
  v_pendientes := case when pg_catalog.cardinality(v_recoger) >= v_max
                       then pg_catalog.cardinality(v_recogibles) - v_marca::integer else 0 end;

  begin
    update crm.leads l
       set vendedor_id = null, asignado_supervisor_id = v_base.supervisor_id
     where l.id = any (v_recoger);
    get diagnostics v_upd = row_count;
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate;
    if private.bases_carga_error_transitorio(v_estado) then
      raise exception using errcode = v_estado, message = pg_catalog.format('La recogida se interrumpió (%s); reintenta', v_estado);
    end if;
    raise exception using errcode = v_estado, message = pg_catalog.format('No se pudo recoger (%s); no se recogió ninguno', v_estado);
  end;
  update crm.base_carga_leads bl
     set analista_id = null, asignado_en = null, asignado_por = null
   where bl.base_id = p_base_id and bl.activo and bl.lead_id = any (v_recoger);
  get diagnostics v_n = row_count;
  if v_upd is distinct from pg_catalog.cardinality(v_recoger) or v_n is distinct from pg_catalog.cardinality(v_recoger) then
    raise exception 'La recogida no quedó como se previó' using errcode = 'P0001';
  end if;

  v_resp := pg_catalog.jsonb_build_object('ok', true, 'operacion_id', p_operacion_id, 'base_id', p_base_id, 'analista_id', p_analista_id,
                                          'recogidos', pg_catalog.cardinality(v_recoger),
                                          'omitidos', v_total - pg_catalog.cardinality(v_recoger) - v_pendientes,
                                          'pendientes', v_pendientes);
  insert into crm.base_carga_operaciones (actor, operacion_id, base_id, tipo, pedido_md5, respuesta)
  values (p_actor, p_operacion_id, p_base_id, 'recoger', v_md5, v_resp);
  return v_resp;
end;
$function$;

create function private.bases_carga_contactos_core(p_actor uuid, p_base_id uuid, p_estado text)
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
  return query
    select l.id, l.nombre_completo, l.telefono, l.distrito, bl.creado_en, bl.analista_id, p.nombre_completo,
           private.bases_carga_reparto_estado(l.activo, l.no_contactar, l.etapa, l.vendedor_id,
                                              private.bases_carga_en_subarbol(v_subarbol, l.vendedor_id, l.asignado_supervisor_id),
                                              l.enfriado_hasta, bl.analista_id, h.intento, h.cita, h.reactivado,
                                              bl.analista_id is null and private.base_gestion_en_gestion_hasta(l.id) is not null, v_hoy)
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

-- ── 4 · Puertas de entrada (DEFINER: las tablas no tienen grants; validan y delegan, el actor sale de la sesión) ─────────
create function crm.repartir_base(p_operacion_id uuid, p_base_id uuid, p_reparto jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $function$
begin
  return private.bases_carga_repartir_core((select auth.uid()), p_operacion_id, p_base_id, p_reparto);
end;
$function$;

create function crm.recoger_de_base(p_operacion_id uuid, p_base_id uuid, p_analista_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $function$
begin
  return private.bases_carga_recoger_core((select auth.uid()), p_operacion_id, p_base_id, p_analista_id);
end;
$function$;

create function crm.contactos_de_base(p_base_id uuid, p_estado text default 'sin_repartir')
returns table(lead_id uuid, nombre_completo text, telefono text, distrito text, agregado_en timestamptz, analista_id uuid,
              analista_nombre text, estado text)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  return query select x.lead_id, x.nombre_completo, x.telefono, x.distrito, x.agregado_en, x.analista_id, x.analista_nombre, x.estado
                 from private.bases_carga_contactos_core((select auth.uid()), p_base_id, p_estado) x;
end;
$function$;

-- ── 5 · Dueños y permisos: EXECUTE de las puertas solo para authenticated; el núcleo, para nadie ───────────────────────
alter function private.bases_carga_reparto_constantes() owner to postgres;
alter function private.bases_carga_reparto_rol(uuid) owner to postgres;
alter function private.bases_carga_reparto_analista(text, uuid[], uuid) owner to postgres;
alter function private.bases_carga_reparto_motivo(boolean, boolean, text, boolean, date, boolean, date) owner to postgres;
alter function private.bases_carga_reparto_hechos(uuid, timestamptz) owner to postgres;
alter function private.bases_carga_reparto_recogible(uuid, uuid, timestamptz, boolean) owner to postgres;
alter function private.bases_carga_reparto_estado(boolean, boolean, text, uuid, boolean, date, uuid, boolean, boolean, boolean, boolean, date) owner to postgres;
alter function private.bases_carga_repartir_core(uuid, uuid, uuid, jsonb) owner to postgres;
alter function private.bases_carga_recoger_core(uuid, uuid, uuid, uuid) owner to postgres;
alter function private.bases_carga_contactos_core(uuid, uuid, text) owner to postgres;
alter function crm.repartir_base(uuid, uuid, jsonb) owner to postgres;
alter function crm.recoger_de_base(uuid, uuid, uuid) owner to postgres;
alter function crm.contactos_de_base(uuid, text) owner to postgres;

revoke all on function private.bases_carga_reparto_constantes() from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_reparto_rol(uuid) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_reparto_analista(text, uuid[], uuid) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_reparto_motivo(boolean, boolean, text, boolean, date, boolean, date) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_reparto_hechos(uuid, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_reparto_recogible(uuid, uuid, timestamptz, boolean) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_reparto_estado(boolean, boolean, text, uuid, boolean, date, uuid, boolean, boolean, boolean, boolean, date) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_repartir_core(uuid, uuid, uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_recoger_core(uuid, uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_contactos_core(uuid, uuid, text) from public, anon, authenticated, service_role;
revoke all on function crm.repartir_base(uuid, uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function crm.recoger_de_base(uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function crm.contactos_de_base(uuid, text) from public, anon, authenticated, service_role;
grant execute on function crm.repartir_base(uuid, uuid, jsonb) to authenticated;
grant execute on function crm.recoger_de_base(uuid, uuid, uuid) to authenticated;
grant execute on function crm.contactos_de_base(uuid, text) to authenticated;

-- ── 6 · Comentarios ────────────────────────────────────────────────────────────────────────────────────────────────────
comment on function crm.repartir_base(uuid, uuid, jsonb) is
'Bases cargadas (B9, 04/10/2026): reparte contactos de una base a analistas, TODO O NADA. p_reparto: {"modo":"bloque","asignaciones":[{"analista_id","cantidad"}]} (el servidor elige los SIN REPARTIR más antiguos en la base y salta los que no se pueden repartir: retirados, fuera del ámbito del dueño, que salieron del descarte, No contactar, en descanso, en gestión B6 u ocupados; si no alcanzan → 22023 con detail = disponibles, el número en texto) o {"modo":"individual","asignaciones":[{"lead_id","analista_id"}]} (cada contacto de la base, visible para el actor —si no, P0002—, sin repartir o repartido a otro —se reasigna— y elegible; si no → 22023 con detail {"rechazados":[{lead_id, motivo}]}; tomado por otro proceso → 55P03; el que ya es de ese analista sale en omitidos como ya_asignado). Analista activo, rol vendedor, del subárbol del supervisor DUEÑO (Gerencia: cualquiera, y puede volver a repartir lo que B9 le dio a alguien fuera del equipo del dueño; fuera del equipo → P0002, inactivo o no analista → 22023). Bloquea solo lo necesario (r1). Efecto: crm.leads.vendedor_id = analista (sigue descartado; sin ciclo SLA ni episodio; la actividad «reasignación» y el candado B6 corren solos) y base_carga_leads.analista_id/asignado_en/asignado_por. Topes en private.bases_carga_reparto_constantes. Idempotente por (actor, p_operacion_id). Devuelve {ok, operacion_id, base_id, modo, repartidos, por_analista[{analista_id, cantidad}], omitidos[{lead_id|null, motivo, cantidad?}]} (en bloque, por motivo con lead_id null). Supervisión y Gerencia (otros → 42501); otra operación de la base en curso → 55P03. DEFINER, search_path vacío, lock_timeout 5 s, EXECUTE solo authenticated.';
comment on function crm.recoger_de_base(uuid, uuid, uuid) is
'Bases cargadas (B9, 04/10/2026; r1): devuelve a «sin repartir» (bandeja del supervisor dueño de la base) los contactos que ese analista tiene de la base SIN intento desde que se le repartieron (de un analista de baja no se exige: manda B6, que la baja libera), sin seguimiento activo (B6) y que siguen descartados y en sus manos (lo movido por otra vía no se deshace, E14); los tomados por otro proceso quedan. Supervisión: analistas de su equipo (activos o no); Gerencia: cualquiera. Tope por operación (private.bases_carga_reparto_constantes): lo que excede queda en pendientes. Idempotente por (actor, p_operacion_id). Devuelve {ok, operacion_id, base_id, analista_id, recogidos, omitidos, pendientes}. DEFINER, search_path vacío, lock_timeout 5 s, EXECUTE solo authenticated.';
comment on function crm.contactos_de_base(uuid, text) is
'Bases cargadas (B9, 04/10/2026): los contactos de una base visible para el actor (Supervisión: su subárbol; Gerencia: todas; si no, P0002; otros roles → 42501), para el reparto individual y la pestaña «Bases». p_estado: sin_repartir (por defecto) | repartidos | todos. Solo contactos que el actor ve y siguen activos (nada fuera de su ámbito). Lleva nombre, teléfono y distrito: la pantalla los usa para marcar filas en el reparto individual (el actor ya los ve en su Base para gestión). estado ∈ sin_repartir · sin_tocar · trabajado · en_descanso · cita · reactivado · movido_otra_via · no_contactar (private.bases_carga_reparto_estado). Orden: el del reparto en bloque (más antiguos en la base primero). DEFINER, search_path vacío, EXECUTE solo authenticated.';
comment on function private.bases_carga_reparto_constantes() is
'Bases cargadas (B9; r2): topes de repartir y recoger, MEDIDOS frente al statement_timeout de 8 s de authenticated: contactos por operación (bloque: la suma; individual: las filas; recoger: por llamada), analistas por reparto (100: el recibo ≤ 64 KB) y la holgura de candados (50): bloque y recoger toman como mucho greatest(n + 50, ceil(n × 1,1)) filas para n contactos necesarios; si los rechazados bajo candado la agotan, 55P03 «Los contactos están cambiando; reintenta».';
comment on function private.bases_carga_reparto_rol(uuid) is
'Bases cargadas (B9): rol del actor resuelto en el servidor (private.rol_crm); solo supervisor o gerencia reparten, recogen y listan una base, si no 42501.';
comment on function private.bases_carga_reparto_analista(text, uuid[], uuid) is
'Bases cargadas (B9): valida el analista de un reparto: Supervisión, del subárbol del supervisor dueño (si no, P0002); activo y con rol vendedor (si no, 22023). Gerencia: cualquiera activo y vendedor.';
comment on function private.bases_carga_reparto_motivo(boolean, boolean, text, boolean, date, boolean, date) is
'Bases cargadas (B9): UNA definición de «este contacto de la base no se puede repartir» (NULL = sí): inactivo, fuera_de_ambito, no_descartado, no_contactar, en_descanso, en_gestion (B6). La usan el bloque y el individual.';
comment on function private.bases_carga_reparto_hechos(uuid, timestamptz) is
'Bases cargadas (B9): UNA definición de «qué pasó desde» un momento, por las actividades de la base: algún intento (intento_base), si alguno agendó cita y si se reactivó desde la base (reactivacion_base). Sin agregados de conteo (censo). La usan recoger y contactos_de_base; B10 puede reutilizarla.';
comment on function private.bases_carga_reparto_recogible(uuid, uuid, timestamptz, boolean) is
'Bases cargadas (B9 r1): UNA definición de «se puede recoger»: vivo, descartado y en manos de ese analista (lo movido por otra vía no se deshace, E14), sin intento desde que se le repartió (salvo analista de baja: manda B6, que la baja libera) y sin seguimiento activo B6. La usan la foto y la revisión bajo candado de recoger.';
comment on function private.bases_carga_reparto_estado(boolean, boolean, text, uuid, boolean, date, uuid, boolean, boolean, boolean, boolean, date) is
'Bases cargadas (B9): UNA definición del estado de un contacto de la base (contrato B9): no_contactar · movido_otra_via · cita · reactivado · en_descanso · sin_repartir/trabajado (sin repartir) · trabajado/sin_tocar (repartido, desde asignado_en). B10 puede reutilizarla para sus conteos.';
comment on function private.bases_carga_repartir_core(uuid, uuid, uuid, jsonb) is
'Bases cargadas (B9; r1): núcleo de crm.repartir_base. Orden: forma → idempotencia (recibo repartir, replay que revalida referencias) → base (visible, FOR UPDATE NOWAIT, viva, dueño activo) → analistas → bloque: foto sin candados de los sin repartir con su motivo y candado SKIP LOCKED SOLO de los que faltan, por tandas y en el orden del reparto; individual: ámbito (P0002) ANTES del candado SKIP LOCKED de lo pedido → revisión bajo candado con la misma definición y sin intento durante la operación → UPDATE de crm.leads por el camino de la casa → pertenencia → recibo. Sin count( ni sum(1) (censo).';
comment on function private.bases_carga_recoger_core(uuid, uuid, uuid, uuid) is
'Bases cargadas (B9; r1): núcleo de crm.recoger_de_base. Base (visible, NOWAIT, viva, dueño activo) → analista del equipo → foto sin candados de lo recogible (private.bases_carga_reparto_recogible) → candado SKIP LOCKED SOLO de eso y hasta el tope, por tandas en orden de reparto, y revisión bajo candado con la misma definición → bandeja del dueño → pertenencia sin analista → recibo recoger. Sin count( ni sum(1) (censo).';
comment on function private.bases_carga_contactos_core(uuid, uuid, text) is
'Bases cargadas (B9): núcleo de crm.contactos_de_base: base visible, solo contactos con private.bases_carga_lead_ref (visibles y activos), estado de private.bases_carga_reparto_estado.';

-- ── 7 · Postflight (SOLO catálogo) ─────────────────────────────────────────────────────────────────────────────────────
create temp table _b9_censo_despues on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;
do $postflight$
declare
  v_mal text;
begin
  -- Cuerpos ensayados (md5(prosrc) medido al generar la migración), seguridad, search_path, dueño, ACL y comentario.
  with esperado(firma, cuerpo, definer, config, acl) as (values
    ('private.bases_carga_reparto_constantes()', '5f563cef58a250251d97b1baf2f4b4d3', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_reparto_rol(uuid)', '88c3330223eefd8e32c27d2ef4541f3a', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_reparto_analista(text,uuid[],uuid)', '94fd2808e2ea524702f65142889ecc2f', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_reparto_motivo(boolean,boolean,text,boolean,date,boolean,date)', 'ad244b42610e7704d00327ee6cde21ab', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_reparto_hechos(uuid,timestamptz)', '9640ce4a6765a95464ac6e8e3a811a20', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_reparto_recogible(uuid,uuid,timestamptz,boolean)', '36d80e0e61b293d9cdd710fc00758054', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.base_gestion_en_gestion_hasta(uuid)', '72621c4311876d39be13e0dfc4278f39', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_reparto_estado(boolean,boolean,text,uuid,boolean,date,uuid,boolean,boolean,boolean,boolean,date)', '28ae6bf56e4d54fdf45ec5f976ddbce3', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)', '8ace9326744cba6c262adb20203b4be0', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_recoger_core(uuid,uuid,uuid,uuid)', '8fd1565059eb61f90374d0bba3a6581a', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_contactos_core(uuid,uuid,text)', '0faaf15b274890e1e788632c27b477bd', false, 'search_path=""', '{postgres=X/postgres}'),
    ('crm.repartir_base(uuid,uuid,jsonb)', 'fd7531ba7cd7cf8a259a389e2895ee2e', true, 'search_path="",lock_timeout=5s', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.recoger_de_base(uuid,uuid,uuid)', '4744f70e69c0f70c22a6a295184e3095', true, 'search_path="",lock_timeout=5s', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.contactos_de_base(uuid,text)', 'd528bab6930698d160f9635417a3ca7a', true, 'search_path=""', '{postgres=X/postgres,authenticated=X/postgres}'))
  select string_agg(e.firma, ', ' order by e.firma) into v_mal
    from esperado e
    left join pg_proc p on p.oid = to_regprocedure(e.firma)
   where (p.oid is not null and md5(p.prosrc) = e.cuerpo and p.prosecdef = e.definer
          and array_to_string(p.proconfig, ',') = e.config and p.proowner = 'postgres'::regrole
          and p.proacl is not null and p.proacl::text = e.acl
          and obj_description(p.oid, 'pg_proc') is not null) is not true;
  if v_mal is not null then
    raise exception 'POSTFLIGHT B9: funciones que no quedaron como se ensayaron: %', v_mal;
  end if;

  if (
    -- Permisos efectivos: las puertas solo para authenticated; el núcleo, para nadie de la API.
    not exists (select 1 from unnest(array['crm.repartir_base(uuid,uuid,jsonb)', 'crm.recoger_de_base(uuid,uuid,uuid)',
                                           'crm.contactos_de_base(uuid,text)']) f(firma)
                 where has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE')
                    or not has_function_privilege('authenticated', f.firma, 'EXECUTE'))
    and not exists (select 1 from pg_proc p cross join unnest(array['anon', 'authenticated', 'service_role']) r(rol)
                     where p.pronamespace = 'private'::regnamespace and p.proname like 'bases\_carga\_%'
                       and has_function_privilege(r.rol, p.oid, 'EXECUTE'))
    -- Una sola sobrecarga de cada puerta y de cada pieza del núcleo de B9.
    and (select count(*) from pg_proc p where p.pronamespace = 'crm'::regnamespace
          and p.proname in ('repartir_base', 'recoger_de_base', 'contactos_de_base')) = 3
    and (select count(*) from pg_proc p where p.pronamespace = 'private'::regnamespace
          and (p.proname like 'bases\_carga\_reparto\_%' or p.proname in ('bases_carga_repartir_core', 'bases_carga_recoger_core', 'bases_carga_contactos_core'))) = 10
    -- r1: la regla nueva de B6, una sola sobrecarga, STABLE, y su comentario dice el cambio; el candado B6 sigue usándola.
    and (select count(*) from pg_proc p where p.pronamespace = 'private'::regnamespace and p.proname = 'base_gestion_en_gestion_hasta') = 1
    and (select p.provolatile = 's' and obj_description(p.oid, 'pg_proc') like 'B6 (Miguel, 03/10/2026; regla cambiada en B9 r1%'
           from pg_proc p where p.oid = to_regprocedure('private.base_gestion_en_gestion_hasta(uuid)'))
    and (select p.prosrc ~ 'base_gestion_en_gestion_hasta' from pg_proc p where p.oid = to_regprocedure('private.trg_leads_guard_seguimiento_activo()'))
    -- B9 no toca la válvula de B8 ni se la enciende a nadie.
    and not exists (select 1 from pg_proc p where p.prosrc ~ 'op_bases_carga'
                     and p.oid not in (to_regprocedure('private.trg_leads_base_cargada_solo_puerta()'),
                                       to_regprocedure('private.bases_carga_nace_dormido(text,text,text,boolean)'),
                                       to_regprocedure('private.bases_carga_cargar_lote_core(uuid,uuid,uuid,jsonb)')))
    -- B8 intacta: las piezas que B9 usa conservan su identidad.
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '0b4e20b805109892a56d2d127cd54a9c'
           from pg_proc p where p.oid = to_regprocedure('private.bases_carga_operacion_previa(uuid,text,uuid,text,text,uuid[])'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '9f671b71f96facf74c7ee4dcec02b6f9'
           from pg_proc p where p.oid = to_regprocedure('private.bases_carga_lead_ref(uuid,text,uuid)'))
    -- Censo: nada nuevo entra y es el de la foto.
    and not exists (select 1 from pg_temp._b9_censo_despues c where c.objeto not in (select a.objeto from pg_temp._b9_censo_antes a))
    and (select count(*) from pg_temp._b9_censo_antes) = (select count(*) from pg_temp._b9_censo_despues)
  ) is not true then
    raise exception 'POSTFLIGHT B9: permisos, sobrecargas, la valvula, B8 o el censo no quedaron como se ensayaron';
  end if;
  raise notice 'B9 CATALOGO OK: 3 puertas (EXECUTE solo authenticated), nucleo privado sin EXECUTE (10 funciones), regla nueva de B6 (seguimiento activo desde que el dueno actual recibio el lead), B8 intacta, valvula sin tocar, censo igual. COMPORTAMIENTO NO PROBADO en esta migracion.';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
$mig$])) then
    raise exception 'REGISTRO: la versión 20261004222602 ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261004222602', 'crm_bases_cargadas_repartir', array[$mig$-- 20261004222602_crm_bases_cargadas_repartir.sql
--
-- Bases cargadas · B9: repartir y recoger. Pedido de Miguel (03/10/2026: «darle 40 a un analista y 30 a otro», en bloques o
-- individual; paso 4 del flujo: «se puede recoger lo que un analista no tocó»), decisiones E1–E14
-- (`BASE PARA GESTION/BASES-CARGADAS.md`) y contrato FIJO de B9
-- (`BASE PARA GESTION/BASES-CARGADAS-CONTRATO.md`), sobre B7 (20261004160034) y B8 (20261004184501). Tres puertas DEFINER en
-- `crm` (validan, resuelven rol y ámbito en el servidor y delegan) y su núcleo en `private`:
--   · crm.repartir_base(operación, base, reparto jsonb) — bloque {"modo":"bloque","asignaciones":[{"analista_id","cantidad"}]}:
--     el servidor elige los contactos SIN REPARTIR más antiguos en la base (agregado_en, luego creado_en y id del lead) y salta
--     los que no se pueden repartir; si no alcanzan, NADA (22023, detail = disponibles, el número en texto). Individual
--     {"modo":"individual","asignaciones":[{"lead_id","analista_id"}]}: cada contacto de la base, sin repartir o repartido a
--     otro (se reasigna), y elegible; si uno no lo es, NADA (22023, detail {"rechazados":[{lead_id, motivo}]}); el que ya es de
--     ese analista sale «omitido» (ya_asignado). Todo o nada. Analista: activo, rol vendedor, del subárbol del supervisor DUEÑO
--     de la base (Gerencia: cualquiera, E4/E11). Respuesta {ok, operacion_id, base_id, modo, repartidos, por_analista
--     [{analista_id, cantidad}], omitidos [{lead_id|null, motivo[, cantidad]}]} — en bloque los omitidos van por motivo con
--     lead_id null y su cantidad (el servidor eligió: no hay referencia que dar y el recibo no crece con la base).
--   · crm.recoger_de_base(operación, base, analista) — vuelve a «sin repartir» (bandeja del supervisor dueño) lo de ese analista
--     SIN intento desde asignado_en y sin seguimiento activo (B6), hasta el tope por operación. Respuesta {ok, operacion_id,
--     base_id, analista_id, recogidos, omitidos, pendientes} (pendientes = recogibles que quedaron para otra operación: 0 casi
--     siempre).
--   · crm.contactos_de_base(base, estado default 'sin_repartir') — la lista para el reparto individual y la pestaña:
--     sin_repartir | repartidos | todos; estado ∈ sin_repartir · sin_tocar · trabajado · en_descanso · cita · reactivado ·
--     movido_otra_via · no_contactar (private.bases_carga_reparto_estado, UNA definición). Solo contactos que el actor VE y
--     siguen activos (private.bases_carga_lead_ref de B8): nada fuera de su ámbito. Lleva nombre, teléfono y distrito: la
--     pantalla los usa para marcar filas en el reparto individual (el actor ya los ve en su Base para gestión).
--   Las tres: Supervisión y Gerencia (otros → 42501); base visible (P0002, sin delatar si existe); repartir y recoger
--   idempotentes por (actor, id de operación) con recibo inmutable (tipo repartir / recoger) en crm.base_carga_operaciones: el
--   replay devuelve la MISMA respuesta (private.bases_carga_operacion_previa de B8: mismo pedido, base aún visible) y vuelve a
--   juzgar cada lead_id que el recibo nombra (P0002 si alguno ya no está a su alcance); el mismo id con otro pedido → 22023.
--
-- QUÉ CORRE AL REPARTIR (UPDATE crm.leads SET vendedor_id, asignado_supervisor_id de un DESCARTADO; inventario de los 31
-- disparadores de crm.leads en el banco a paridad, orden efectivo, y MEDIDO con pg_stat_xact_user_functions al repartir y al
-- recoger un contacto: corren los mismos 18 de crm.leads, una vez cada uno, más la auditoría y el sello de las tablas de
-- bases y los 4 de crm.actividades por la «reasignación»). Sin válvula nueva: es el camino de la casa —el mismo UPDATE que hacen
-- rescatar_descartes y la ficha (PATCH)— con el actor de la sesión (auth.uid() = el supervisor o Gerencia), y todos los
-- candados corren:
--   BEFORE: 000_base_cargada_solo_puerta (B7: origen y motivo base_cargada NO cambian, el capital no se vacía → pasa) ·
--   00_devolucion_equipo_solo_rpc (solo si el lead vuelve a la bandeja del propio supervisor desde un episodio de hoy: un
--   descartado no tiene episodio → pasa al recoger) · 00_guard_tenencia (analista destino activo vendedor/supervisor; nunca
--   analista y bandeja a la vez: por eso repartir pone asignado_supervisor_id NULL y recoger vendedor_id NULL; la bandeja de
--   un supervisor activo) · 00_seguimiento_activo (B6: con seguimiento activo del analista que lo tiene → P0409; la puerta lo
--   salta o lo rechaza ANTES con el mismo ayudante private.base_gestion_en_gestion_hasta, bajo el candado del lead) ·
--   01_sla_global (sin cambio de ciclo: conserva el sello) · before_update (inmutables) · bloquear_reasignacion (solo frena a
--   un actor con rol vendedor: el actor es Supervisión o Gerencia) · cambio_etapa (la etapa NO cambia) · protege_inversionista_id
--   · reasignacion (escribe la actividad «reasignación» A → B: el rastro que pide el contrato) · zz_sello_descarte (descartado
--   que sigue descartado: conserva descartado_en y descartado_por) · zzz_tenencia_desde (NULL: un descartado no tiene tenencia
--   operativa) · zzzz_usuario_retirado (descartado → no aplica). NO corren (no están en el SET): 00_disponibilidad_update
--   (teléfono, dni, no_contactar, etapa, activo, motivo), 000_no_contactar_puerta, zz_enlaza_identidad, zz_reapertura_solo_rpc,
--   zz_sello_base_gestion, conversion_con_inversion.
--   AFTER: audit_leads (bitácora) · 02_sla_versionado (sin cambio de ciclo, etapa ni activo: NO abre ciclo ni episodio SLA) ·
--   asignaciones (descartado = sin tenencia operativa: NO abre ni cierra episodio en lead_asignaciones) · zz_puente_identidad
--   (inversionista_id igual: nada) · zz_sync_tareas (las tareas pendientes siguen al lead; un descartado no tiene) ·
--   zzzz_conversion_responsable (solo leads operativos). La actividad «reasignación» pasa por trg_01_gestion_lead_serializada
--   (tipo de sistema: sin candado extra).
--   El lead SIGUE descartado/dormido (E7): ni ciclo SLA, ni episodio, ni llegada; el analista lo trabaja en su Base para gestión.
-- QUÉ FECHA VE EL ANALISTA («Mes», B5): crm.obtener_base_gestion da recibido_en = coalesce(tenencia_desde, creado_en)
--   (20261003162400:4,57) y private.trg_leads_tenencia_desde pone tenencia_desde = NULL a todo lead no operativo
--   (20260725012707:122; medido: el reparto la deja NULL): un descartado NUNCA la tiene y cualquier valor que escribiera B9 lo
--   borraría el disparador. Decisión: B9 NO toca tenencia_desde ni creado_en (tenencia_desde es la tenencia OPERATIVA que leen
--   cartera y SLA; inventarla en un dormido sería mentir). El «Mes» del contacto de base es su creado_en en Lima, el criterio
--   de la casa para el mes del analista (B5 y la regla «el analista se organiza por el mes del lead»: el de creado_en, cuándo
--   entró el lead): el del archivo, el mes de la carga; el armado desde el CRM, el mes en que entró al CRM. Cuándo se le
--   repartió vive en base_carga_leads.asignado_en (lo leen B10 —seguimiento, «sin tocar 3 días»— y F6 con el selector «Base»).
-- CANDADOS (orden de la casa, el de B8): (1) el de la operación (bases_carga_operacion_previa: actor + id; un doble clic espera
--   y recibe el recibo) → (2) la fila de la base FOR UPDATE NOWAIT (55P03 «Hay otra operación en curso de esta base;
--   reintenta»: repartir, recoger y los lotes de una base van de a uno; ninguno espera al otro) → (3) los leads FOR UPDATE SKIP
--   LOCKED y se evalúa SOLO lo efectivamente bloqueado, en otra sentencia (r2 de B8): reactivar, vetar, el intento B6 y las
--   reasignaciones toman la fila del lead, así que lo bloqueado no cambia hasta el commit; lo que otro proceso tiene tomado no
--   se espera: en bloque se salta (omitido «ocupado»), en individual el reparto entero falla con 55P03 (todo o nada). r1 (Codex
--   P2): se bloquea SOLO lo necesario — en bloque, por tandas y en el orden del reparto, solo los que faltan entre los elegibles
--   de una foto previa sin candados; en recoger, solo lo recogible y hasta el tope; en individual, solo lo pedido y después de
--   comprobar el ámbito (auditor P3) —. Sin esperas en (2) y (3) no hay ciclo posible con ningún escritor. La fecha asignado_en
--   es clock_timestamp() DESPUÉS de los candados: un intento que esperaba al lead queda después (trg_01_gestion_lead_serializada
--   le pone clock_timestamp tras tomar el lead) y uno anterior, antes. Un contacto que recibió un intento DURANTE la operación no
--   se reparte (bloque: «ocupado»; individual: 55P03): la «reasignación» lleva la hora de la sentencia y el analista nuevo lo
--   heredaría por B6. Requiere READ COMMITTED (cada sentencia ve lo confirmado tras el candado; 0A000 si no).
-- ERRORES DEL UPDATE: lo transitorio (private.bases_carga_error_transitorio de B8) aborta con el MISMO código y «… se
--   interrumpió (código); reintenta»; cualquier otro, con su código y un mensaje sin datos (sin el detail del disparador).
-- TOPES (private.bases_carga_reparto_constantes, MEDIDOS frente al statement_timeout de 8 s de authenticated): 500 contactos por
--   operación (bloque: la suma; individual: las filas; recoger: por llamada; lo que excede, en «pendientes») y 100 analistas
--   por reparto (con 500 ya_asignado y 100 analistas el recibo queda < 64 KB). Banco (por la puerta, como authenticated):
--   repartir 500 en 0,43 s, 2000 en 1,7 s, 5000 en 4,3 s (~0,85 ms por contacto: sus 18 disparadores); recoger igual; la lista
--   de 5000 en 0,2 s. Con la rama micro de B8 3–5× más lenta que el banco, 500 deja margen ×4–×6; la rama lo mide.
-- CENSO: ninguna función nueva usa count( ni sum(1) (cardinality de array_agg, get diagnostics); el postflight exige el censo
--   analítico igual a la foto previa.
-- B6, CAMBIO DE REGLA (r1, decisión de Miguel 04/10/2026): private.base_gestion_en_gestion_hasta —la fuente única del
--   seguimiento activo— cuenta solo los intentos hechos DESDE QUE EL DUEÑO ACTUAL RECIBIÓ EL LEAD (la última actividad
--   «reasignación» hacia él, que escribe solo private.trg_leads_reasignacion en toda vía; si nació suyo, desde el descarte, como
--   antes). Si el supervisor llama a un contacto de su bandeja y luego lo reparte, o el dueño anterior lo llamó, el analista
--   nuevo NO queda en gestión ni bloquea recoger o reasignar. Lo que Supervisión registra sobre un lead que ya es del analista
--   cuenta para él. Por qué la «reasignación» y no base_carga_leads.asignado_en: vale para toda vía, la API no la puede escribir
--   (policy actividades_insert) y no reinicia la protección de un analista que YA tenía el lead (armado desde el CRM y
--   «repartido» a su mismo analista: no lo recibió entonces). Consumidores: el candado B6 (toda vía), el gris del rescate, armar
--   (B8) y B9; ninguno cambia de texto. Queda: un intento del supervisor sobre su bandeja confirmado durante la sentencia de
--   otra vía que mueve ese lead (no B9) lo heredaría el nuevo dueño (milisegundos; B9 lo evita, ver CANDADOS). r2: solo corta
--   una «reasignación» que cambió de verdad el vendedor (auditor P3); la rellamada cuenta solo si la programó el último intento
--   posterior al corte, leída de su actividad (Codex r2: la columna del lead pudo dejarla el dueño anterior). Sin actividad de
--   reasignación (lead que nació suyo o histórico anterior a ella): cuenta desde el descarte, como B6 — puede bloquear DE MÁS,
--   nunca de menos. A → B → A: cuenta desde que volvió a A (lo de B y lo de A antes de irse no bloquea). Las actividades
--   «reasignación» no se cambian ni se borran: authenticated solo tiene INSERT y SELECT en crm.actividades (la policy de INSERT
--   excluye el tipo), y las 4 vías DEFINER que hacen UPDATE en actividades (base_gestion_intento_core, llamada_registrar,
--   llamada_registrar_v4, deshacer_resultado_llamada) solo tocan la actividad que acaban de crear o un resultado de llamada
--   propio: probado en el banco (suite Q) y por la API (gate); service_role (clave del servidor, sin usuario) sí podría, como en
--   toda tabla, y el patrón de sello de B6c también la exime: no se añade sello.
-- QUÉ NO CAMBIA: B7 (tablas, sello, CHECK), B8 (sus 21 funciones y su disparador: el preflight y el postflight fijan sus
--   huellas), crm.leads (columnas, grants, policies, disparadores), crm.obtener_base_gestion (B10 la cambia), el disparador
--   de B6 y crm.rescate_descartes_mes (solo cambia la ayudante que usan).
-- PRECONDICIÓN: B8 aplicada (20261004184501) — el preflight fija las definiciones vivas de las que depende (núcleo de B8,
--   ayudantes de la casa, la ayudante de B6 que reemplaza —exacta— y las 12 funciones de disparador de las que depende lo
--   probado —11 de crm.leads y la de crm.actividades— con la DEFINICIÓN exacta de sus disparadores (r1, Codex P2: evento,
--   columnas, WHEN y función; un homónimo con WHEN (false) no pasa), habilitados). Las de disparador NO se midieron en
--   producción (las de B8 sí, en su rama): la rama con datos lo confirma; si alguna difiere, el preflight se niega.
-- REVERSA: supabase/scripts/base-gestion/reversa-b9.sql (solo funciones: NO borra ni cambia filas; las asignaciones y los
--   recibos quedan y reaplicar B9 los vuelve a servir; repone la ayudante de B6 con su texto y comentario exactos). Comprobación
--   tras aplicar: supabase/scripts/base-gestion/b9-comprobar-tras-aplicar.sql.
-- r2 (04/10): Codex r2 BLOCK (1 P2: candados retenidos sin máximo acumulado) y auditor 2.ª pasada PASS con P3 → presupuesto de
--   candados (private.bases_carga_reparto_constantes().holgura_candados = 50: como mucho greatest(n + 50, ceil(n × 1,1)) filas
--   bloqueadas por operación, aceptadas o no; agotado → 55P03 «Los contactos están cambiando; reintenta», todo o nada); la
--   rellamada y el corte de B6 (arriba).
-- r1 (04/10): Codex r1 BLOCK (3 P2) y auditor-rls PASS con P2/P3 → la regla de B6 (arriba); Gerencia puede volver a repartir
--   lo que B9 le dio a un analista fuera del equipo del dueño (la pertenencia dice que ese analista lo tiene; lo movido por otra
--   vía, no); candados solo de lo necesario; preflight con la definición de los disparadores; recoger de un analista de baja
--   no exige «sin intento» (manda B6); el ámbito del individual se comprueba antes de los candados.
-- CANDADOS DE TABLA: ninguno. B9 solo crea funciones (sin DDL de tablas ni disparadores): el único candado es el de migración
--   de la casa (crm_migracion_funciones), tomado ANTES del preflight; validar las funciones SQL toma ACCESS SHARE de las tablas
--   que nombran (no frena lecturas ni escrituras). Sin DML: el postflight es SOLO de catálogo.
begin;
set transaction isolation level read committed;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

select pg_advisory_xact_lock(hashtext('crm_migracion_funciones'));

-- Foto del censo analítico (solo catálogo), bajo el candado de migración.
create temp table _b9_censo_antes on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $preflight$
declare
  v_ident text := 'md5(prosrc|prosecdef|provolatile|proconfig|proowner)';
begin
  if (
    -- Nada de B9 existe todavía.
    to_regprocedure('crm.repartir_base(uuid,uuid,jsonb)') is null
    and to_regprocedure('crm.recoger_de_base(uuid,uuid,uuid)') is null
    and to_regprocedure('crm.contactos_de_base(uuid,text)') is null
    and not exists (select 1 from pg_proc p where p.pronamespace in ('crm'::regnamespace, 'private'::regnamespace)
                     and (p.proname like 'bases\_carga\_reparto\_%' or p.proname in ('bases_carga_repartir_core', 'bases_carga_recoger_core',
                                                                                         'bases_carga_contactos_core', 'repartir_base',
                                                                                         'recoger_de_base', 'contactos_de_base')))
    -- B7 aplicada: las tablas y los tipos de recibo de B9 en su CHECK.
    and to_regclass('crm.bases_carga') is not null and to_regclass('crm.base_carga_leads') is not null
    and to_regclass('crm.base_carga_operaciones') is not null
    and (select pg_get_constraintdef(c.oid) = 'CHECK ((tipo = ANY (ARRAY[''crear''::text, ''cargar_lote''::text, ''armar''::text, ''repartir''::text, ''recoger''::text])))'
                and c.convalidated
           from pg_constraint c where c.conrelid = 'crm.base_carga_operaciones'::regclass and c.conname = 'base_carga_operaciones_tipo_check')
    and (select pg_get_constraintdef(c.oid) = 'CHECK ((((analista_id IS NULL) = (asignado_en IS NULL)) AND ((analista_id IS NULL) = (asignado_por IS NULL))))'
                and c.convalidated
           from pg_constraint c where c.conrelid = 'crm.base_carga_leads'::regclass and c.conname = 'base_carga_leads_asignacion_coherente')
    -- B8 aplicada: las puertas y el núcleo que B9 usa, con la identidad de B8 (si cambiaran, lo probado no valdría).
    and to_regprocedure('crm.cargar_base_lote(uuid,uuid,jsonb)') is not null
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '0b4e20b805109892a56d2d127cd54a9c'
           from pg_proc p where p.oid = to_regprocedure('private.bases_carga_operacion_previa(uuid,text,uuid,text,text,uuid[])'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '50af07f268c21b5d4b07e1d79de5c5bc'
           from pg_proc p where p.oid = to_regprocedure('private.bases_carga_base_visible(uuid,text,uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '0571e6b4075a6e2c88b46d09378e6cc6'
           from pg_proc p where p.oid = to_regprocedure('private.bases_carga_subarbol(uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '041d852f8d69017c77a2f9fcd8cbab93'
           from pg_proc p where p.oid = to_regprocedure('private.bases_carga_en_subarbol(uuid[],uuid,uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '9f671b71f96facf74c7ee4dcec02b6f9'
           from pg_proc p where p.oid = to_regprocedure('private.bases_carga_lead_ref(uuid,text,uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '39037380cbf5e8286d8e6c4df2b832a0'
           from pg_proc p where p.oid = to_regprocedure('private.bases_carga_error_transitorio(text)'))
    -- Ayudantes de la casa (las huellas que midió la rama con datos de B8 en producción).
    -- r1: la ayudante de B6 que se REEMPLAZA (regla de Miguel 04/10), exacta: identidad, cuerpo, ACL y comentario de B6
    -- (20261003162500:46-71, medidos en el banco a paridad; la identidad, también en producción por la rama de B8).
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = 'e90da5df4c53fa1c30f0ca5f71431631'
                and md5(p.prosrc) = 'af0701a9e095e1004a64b7e289789d7c'
                and p.proacl is not null and p.proacl::text = '{postgres=X/postgres}'
                and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '6b4c155f38d0722f9e9247547b5c3c2a'
           from pg_proc p where p.oid = to_regprocedure('private.base_gestion_en_gestion_hasta(uuid)'))
    -- Sus tres consumidores vivos (pg_proc, 04/10): el candado B6, el gris del rescate y armar de B8 (B9 se suma).
    and (select count(*) from pg_proc p where p.prosrc ~ 'base_gestion_en_gestion_hasta') = 3
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = 'c4ae35f90e850548653a25f08d25327c'
           from pg_proc p where p.oid = to_regprocedure('private.base_gestion_lead_visible(uuid,text,uuid,uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = 'b35bca38019cdd27b801cf4c39d4c756'
           from pg_proc p where p.oid = to_regprocedure('private.es_destino_crm_activo(uuid,text[])'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '16960a2a21cc5c372431c2dd67acafe4'
           from pg_proc p where p.oid = to_regprocedure('private.rol_crm(uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '45ae492c03234b80336c0b8f5c8ac09b'
           from pg_proc p where p.oid = to_regprocedure('private.vendedor_ids_visibles(uuid)'))
    -- Los disparadores que corren al repartir y recoger (inventario de la cabecera), con la identidad ensayada.
    and (select string_agg(x.firma, ',' order by x.firma) from (values
           ('private.trg_leads_guard_seguimiento_activo()', '48f48c865acf806b0e1d03846072ac17'),
           ('private.trg_leads_guard_tenencia()', '06ab77d35e1db9fc976db25808015e9e'),
           ('private.trg_devolucion_equipo_solo_rpc()', 'ba059074b83a496a7a502af3e24d994a'),
           ('private.trg_leads_bloquear_reasignacion()', '8360dfacd7f942de14f47d68def08491'),
           ('private.trg_leads_reasignacion()', '18e904add66331b2af6cdf07b2bbdb68'),
           ('private.trg_leads_asignaciones()', '27dbc5d14c81bad16a82acd586f4666c'),
           ('private.trg_leads_tenencia_desde()', 'c5a4fcee9c7fbc6334c89ef3616a6bb4'),
           ('private.trg_leads_sla_versionado()', 'f9bfea320eedbdc8fce08ba98776a1b2'),
           ('private.trg_leads_sync_tareas()', '9ec20bfa9b24052a1dec16f3faf2a330'),
           ('private.no_asignar_usuario_retirado()', '66b00bc02936f5243d28c6009849a35c'),
           ('private.trg_leads_base_cargada_solo_puerta()', '9074e2e17457827b9e81f059087c5219'),
           ('private.trg_gestion_lead_serializada()', 'b738fd353b8c287ac259a0a3de25657b')) x(firma, huella)
         left join pg_proc p on p.oid = to_regprocedure(x.firma)
        where (md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                   || '|' || p.proowner::regrole::text) = x.huella) is not true) is null
    -- r1 (Codex P2): la DEFINICIÓN exacta de esos disparadores (evento, momento, columnas, WHEN —el de B6— y función), uno por
    -- nombre y habilitados: un homónimo con WHEN (false) o sin su evento no pasa.
    and (select count(*) from (values
           ('crm.leads', 'trg_leads_000_base_cargada_solo_puerta', 'CREATE TRIGGER trg_leads_000_base_cargada_solo_puerta BEFORE INSERT OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_base_cargada_solo_puerta()'),
           ('crm.leads', 'trg_leads_00_devolucion_equipo_solo_rpc', 'CREATE TRIGGER trg_leads_00_devolucion_equipo_solo_rpc BEFORE UPDATE OF vendedor_id, asignado_supervisor_id ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_devolucion_equipo_solo_rpc()'),
           ('crm.leads', 'trg_leads_00_guard_tenencia', 'CREATE TRIGGER trg_leads_00_guard_tenencia BEFORE INSERT OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_guard_tenencia()'),
           ('crm.leads', 'trg_leads_00_seguimiento_activo', 'CREATE TRIGGER trg_leads_00_seguimiento_activo BEFORE UPDATE ON crm.leads FOR EACH ROW WHEN (((old.etapa = ''descartado''::text) AND (new.vendedor_id IS DISTINCT FROM old.vendedor_id))) EXECUTE FUNCTION private.trg_leads_guard_seguimiento_activo()'),
           ('crm.leads', 'trg_leads_02_sla_versionado', 'CREATE TRIGGER trg_leads_02_sla_versionado AFTER INSERT OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_sla_versionado()'),
           ('crm.leads', 'trg_leads_asignaciones', 'CREATE TRIGGER trg_leads_asignaciones AFTER INSERT OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_asignaciones()'),
           ('crm.leads', 'trg_leads_bloquear_reasignacion', 'CREATE TRIGGER trg_leads_bloquear_reasignacion BEFORE UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_bloquear_reasignacion()'),
           ('crm.leads', 'trg_leads_reasignacion', 'CREATE TRIGGER trg_leads_reasignacion BEFORE UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_reasignacion()'),
           ('crm.leads', 'trg_leads_zz_sync_tareas', 'CREATE TRIGGER trg_leads_zz_sync_tareas AFTER UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_sync_tareas()'),
           ('crm.leads', 'trg_leads_zzz_tenencia_desde', 'CREATE TRIGGER trg_leads_zzz_tenencia_desde BEFORE INSERT OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_tenencia_desde()'),
           ('crm.leads', 'trg_zzzz_usuario_retirado', 'CREATE TRIGGER trg_zzzz_usuario_retirado BEFORE INSERT OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.no_asignar_usuario_retirado()'),
           ('crm.actividades', 'trg_01_gestion_lead_serializada', 'CREATE TRIGGER trg_01_gestion_lead_serializada BEFORE INSERT ON crm.actividades FOR EACH ROW EXECUTE FUNCTION private.trg_gestion_lead_serializada()')) x(tabla, nombre, definicion)
          join pg_trigger t on t.tgrelid = x.tabla::regclass and t.tgname = x.nombre
         where t.tgenabled = 'O' and pg_get_triggerdef(t.oid) = x.definicion) = 12
  ) is not true then
    raise exception 'PREFLIGHT B9: ya aplicada o a medias, B7/B8 no aplicadas, o una funcion o disparador de los que depende no es el medido (%)', v_ident;
  end if;
end;
$preflight$;

-- ── 1 · B6, cambio de regla (Miguel, 04/10/2026): el seguimiento activo cuenta desde que el DUEÑO ACTUAL recibió el lead ───
-- Texto vivo de 20261003162500:46-71 (el preflight lo fija) con UN cambio: los intentos cuentan desde la última «reasignación»
-- hacia el dueño actual (si no hay, el lead nació suyo: desde el descarte, como antes). Misma firma, volatilidad, seguridad,
-- search_path, dueño y ACL (CREATE OR REPLACE los conserva); el comentario se actualiza. Consumidores (pg_proc, 04/10): el
-- candado private.trg_leads_guard_seguimiento_activo (toda vía), el gris de crm.rescate_descartes_mes y
-- private.bases_carga_armar_core (B8); B9 se suma (repartir, recoger, la lista). Ninguno cambia de texto.
create or replace function private.base_gestion_en_gestion_hasta(p_lead_id uuid)
returns date
language sql stable security invoker set search_path = '' as $function$
  -- Hasta qué día (Lima) el lead descartado sigue en gestión de su analista: el último intento de la base del ciclo vigente
  -- (desde descartado_en) + 7 días, o el día de la rellamada agendada en ese ciclo, lo que llegue más lejos. NULL si ya no
  -- está en gestión, si no está descartado o si su dueño ya no está activo (una baja libera sus leads).
  -- B9 r1 (Miguel, 04/10/2026): solo cuentan los intentos hechos DESDE QUE EL DUEÑO ACTUAL RECIBIÓ EL LEAD: la última
  -- actividad «reasignación» hacia él (la escribe SOLO private.trg_leads_reasignacion, en toda vía que mueve el lead —rescate,
  -- ficha, tomar, derivar, B9—; la API no puede insertarla: policy actividades_insert). Sin ella, el lead nació suyo: desde el
  -- descarte, como antes (un histórico sin esa actividad puede bloquear DE MÁS, nunca de menos). Lo que Supervisión registra
  -- sobre un lead que ya es del analista cuenta para el analista. A → B → A: cuenta desde que VOLVIÓ a A.
  -- B9 r2: solo una «reasignación» que de verdad cambió el vendedor corta (auditor P3); y la rellamada cuenta solo si la
  -- programó ESE último intento (posterior al corte), leída de su actividad y no de la columna del lead, que pudo dejar un
  -- dueño anterior (Codex r2).
  select case when x.hasta >= (pg_catalog.now() at time zone 'America/Lima')::date then x.hasta end
    from (
      select greatest(
               (i.ultimo at time zone 'America/Lima')::date + 7,
               (i.proxima at time zone 'America/Lima')::date) as hasta
        from crm.leads l
        cross join lateral (
          select max(r.creado_en) as desde
            from crm.actividades r
           where r.lead_id = l.id
             and r.tipo = 'reasignacion'
             and r.metadata->>'vendedor_nuevo' = l.vendedor_id::text
             and (r.metadata->>'vendedor_anterior') is distinct from (r.metadata->>'vendedor_nuevo')
        ) t
        cross join lateral (
          select a.creado_en as ultimo, (a.metadata->>'proxima_llamada_en')::timestamptz as proxima
            from crm.actividades a
           where a.lead_id = l.id
             and a.metadata->>'evento' = 'intento_base'
             and a.creado_en >= l.descartado_en
             and (t.desde is null or a.creado_en >= t.desde)
           order by a.creado_en desc, a.id desc
           limit 1
        ) i
       where l.id = p_lead_id
         and l.etapa = 'descartado'
         and exists (select 1 from crm.equipo e join public.perfiles p on p.id = e.perfil_id
                      where e.perfil_id = l.vendedor_id and e.activo and p.activo)
    ) x
$function$;
comment on function private.base_gestion_en_gestion_hasta(uuid) is
  'B6 (Miguel, 03/10/2026; regla cambiada en B9 r1/r2, Miguel 04/10/2026): seguimiento activo de un lead descartado. Último día (Lima) en que sigue en gestión de su analista: último intento de la base hecho DESDE QUE EL DUEÑO ACTUAL RECIBIÓ EL LEAD (la última «reasignación» hacia él que cambió de verdad el vendedor; si no hay —nació suyo o es un histórico—, desde el descarte: puede bloquear de más, nunca de menos; A → B → A cuenta desde que volvió a A) + 7 días, o el día de la rellamada que programó ESE último intento (leída de su actividad, no de la columna del lead), el mayor. Una llamada del supervisor sobre su bandeja antes de repartir, o la del dueño anterior, NO bloquea al nuevo. NULL si no hay seguimiento activo, si el lead no está descartado o si su dueño ya no está activo. Fuente única del candado (trg_leads_00_seguimiento_activo), del gris del Centro de rescate, de armar (B8) y de repartir/recoger (B9). INVOKER, sin EXECUTE para roles de la API.';

-- ── 2 · Núcleo: topes, rol, analista y las definiciones únicas ─────────────────────────────────────────────────────────
create function private.bases_carga_reparto_constantes()
returns table(max_contactos integer, max_analistas integer, holgura_candados integer)
language sql
immutable
security invoker
set search_path = ''
as $function$
  select 500, 100, 50;
$function$;

create function private.bases_carga_reparto_rol(p_actor uuid)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_rol text := private.rol_crm(p_actor);
begin
  -- Rol resuelto en el servidor (private.rol_crm); solo Supervisión y Gerencia reparten, recogen y listan una base.
  if p_actor is null or (v_rol in ('supervisor', 'gerencia')) is not true then
    raise exception 'Solo Supervisión y Gerencia reparten y ven las bases' using errcode = '42501';
  end if;
  return v_rol;
end;
$function$;

create function private.bases_carga_reparto_analista(p_rol text, p_subarbol uuid[], p_analista_id uuid)
returns void
language plpgsql
stable
security invoker
set search_path = ''
as $function$
begin
  -- E4/E11: Supervisión reparte a SU equipo —el subárbol del supervisor DUEÑO de la base (private.bases_carga_subarbol)—;
  -- Gerencia, a cualquiera. El analista: activo y con rol vendedor (el guard de tenencia admitiría también un supervisor).
  if p_analista_id is null then
    raise exception 'Cada asignación lleva su analista' using errcode = '22023';
  end if;
  if p_rol is distinct from 'gerencia' and (p_analista_id = any (p_subarbol)) is not true then
    raise exception 'Analista no encontrado o fuera del equipo de la base' using errcode = 'P0002';
  end if;
  if private.es_destino_crm_activo(p_analista_id, array['vendedor']::text[]) is not true then
    raise exception 'El analista no existe, no está activo o no es analista' using errcode = '22023';
  end if;
end;
$function$;

create function private.bases_carga_reparto_motivo(p_activo boolean, p_en_ambito boolean, p_etapa text, p_no_contactar boolean,
                                                   p_enfriado_hasta date, p_en_gestion boolean, p_hoy date)
returns text
language sql
immutable
security invoker
set search_path = ''
as $function$
  -- UNA definición de «este contacto de la base no se puede repartir ahora» (NULL = sí se puede), con el motivo:
  --   inactivo (retirado) · fuera_de_ambito (otra vía lo sacó del subárbol del dueño) · no_descartado (salió de la base:
  --   reactivado u otra vía) · no_contactar (veto) · en_descanso (enfriado_hasta B4) · en_gestion (seguimiento activo B6).
  -- La usan repartir (bloque e individual). Las condiciones con `is not true` / `is true`: un NULL nunca habilita.
  select case
           when p_activo is not true then 'inactivo'
           when p_en_ambito is not true then 'fuera_de_ambito'
           when p_etapa is distinct from 'descartado' then 'no_descartado'
           when p_no_contactar is not false then 'no_contactar'
           when p_enfriado_hasta is not null and p_enfriado_hasta > p_hoy then 'en_descanso'
           when p_en_gestion is true then 'en_gestion'
         end;
$function$;

create function private.bases_carga_reparto_hechos(p_lead_id uuid, p_desde timestamptz)
returns table(intento boolean, cita boolean, reactivado boolean)
language sql
stable
security invoker
set search_path = ''
as $function$
  -- UNA definición de «qué pasó desde» un momento, por las actividades de la base (sin agregados de conteo: censo): algún
  -- intento (evento intento_base, el que escribe private.base_gestion_intento_core), si alguno agendó cita, y si se reactivó
  -- desde la base (evento reactivacion_base de private.base_gestion_reactivar_core). Su creado_en lo sella
  -- trg_01_gestion_lead_serializada con clock_timestamp DESPUÉS de tomar el lead: un hecho que esperaba al reparto queda
  -- después de asignado_en. p_desde = asignado_en (repartido) o cuándo entró a la base (sin repartir). Lo usan recoger (sin
  -- intento) y el estado de contactos_de_base.
  select coalesce(pg_catalog.bool_or(a.metadata ->> 'evento' = 'intento_base'), false),
         coalesce(pg_catalog.bool_or(a.metadata ->> 'evento' = 'intento_base' and a.metadata ->> 'resultado' = 'agendo_reunion'), false),
         coalesce(pg_catalog.bool_or(a.metadata ->> 'evento' = 'reactivacion_base'), false)
    from crm.actividades a
   where a.lead_id = p_lead_id
     and a.metadata ->> 'evento' in ('intento_base', 'reactivacion_base')
     and a.creado_en >= p_desde;
$function$;

create function private.bases_carga_reparto_recogible(p_lead_id uuid, p_analista_id uuid, p_asignado_en timestamptz, p_baja boolean)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $function$
  -- UNA definición de «se puede recoger» (la usan la foto y la revisión bajo candado de recoger): sigue vivo, descartado y en
  -- manos de ESE analista (lo movido por otra vía no se deshace, E14), sin intento desde que se le repartió —salvo que el
  -- analista esté de baja (r1, auditor P3): entonces manda B6, que la baja libera— y sin seguimiento activo B6. `is true`.
  select coalesce((select (l.activo and l.etapa = 'descartado' and l.vendedor_id = p_analista_id
                           and (p_baja is true or not h.intento)
                           and private.base_gestion_en_gestion_hasta(l.id) is null) is true
                     from crm.leads l
                     cross join lateral private.bases_carga_reparto_hechos(l.id, p_asignado_en) h
                    where l.id = p_lead_id), false);
$function$;

create function private.bases_carga_reparto_estado(p_activo boolean, p_no_contactar boolean, p_etapa text, p_vendedor_id uuid,
                                                   p_en_ambito boolean, p_enfriado_hasta date, p_analista_id uuid,
                                                   p_intento boolean, p_cita boolean, p_reactivado boolean, p_en_gestion boolean,
                                                   p_hoy date)
returns text
language sql
immutable
security invoker
set search_path = ''
as $function$
  -- UNA definición del estado de un contacto de la base (contrato B9), en este orden:
  --   no_contactar · movido_otra_via (retirado; repartido pero otro lo tiene; sin repartir fuera del ámbito del dueño; o salió
  --   del descarte por otra vía —E14—) · cita (salió del descarte con un intento «agendó cita») · reactivado (salió del
  --   descarte reactivado desde la base) · en_descanso · sin repartir: trabajado si alguien lo tiene en seguimiento activo
  --   (B6: no se puede repartir) o sin_repartir · repartido: trabajado (≥ 1 intento) o sin_tocar. Los hechos (intento, cita,
  --   reactivado) son los de private.bases_carga_reparto_hechos desde asignado_en o, sin repartir, desde que entró a la base.
  select case
           when p_no_contactar is not false then 'no_contactar'
           when p_activo is not true then 'movido_otra_via'
           when p_analista_id is not null and p_vendedor_id is distinct from p_analista_id then 'movido_otra_via'
           when p_analista_id is null and p_en_ambito is not true then 'movido_otra_via'
           when p_etapa is distinct from 'descartado' and p_cita is true then 'cita'
           when p_etapa is distinct from 'descartado' and p_reactivado is true then 'reactivado'
           when p_etapa is distinct from 'descartado' then 'movido_otra_via'
           when p_enfriado_hasta is not null and p_enfriado_hasta > p_hoy then 'en_descanso'
           when p_analista_id is null then case when p_en_gestion is true then 'trabajado' else 'sin_repartir' end
           when p_intento is true then 'trabajado'
           else 'sin_tocar'
         end;
$function$;

-- ── 3 · Núcleo: repartir, recoger y la lista ───────────────────────────────────────────────────────────────────────────
create function private.bases_carga_repartir_core(p_actor uuid, p_operacion_id uuid, p_base_id uuid, p_reparto jsonb)
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
                   private.bases_carga_reparto_motivo(l.activo,
                                                      private.bases_carga_en_subarbol(v_subarbol, l.vendedor_id, l.asignado_supervisor_id),
                                                      l.etapa, l.no_contactar, l.enfriado_hasta,
                                                      private.base_gestion_en_gestion_hasta(l.id) is not null, v_hoy) as motivo
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
         where private.bases_carga_reparto_motivo(l.activo,
                                                  private.bases_carga_en_subarbol(v_subarbol, l.vendedor_id, l.asignado_supervisor_id),
                                                  l.etapa, l.no_contactar, l.enfriado_hasta,
                                                  private.base_gestion_en_gestion_hasta(l.id) is not null, v_hoy) is null
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
                    select l.id, coalesce(private.bases_carga_reparto_motivo(l.activo,
                                            private.bases_carga_en_subarbol(v_subarbol, l.vendedor_id, l.asignado_supervisor_id),
                                            l.etapa, l.no_contactar, l.enfriado_hasta,
                                            private.base_gestion_en_gestion_hasta(l.id) is not null, v_hoy), 'ocupado')
                      from crm.leads l where l.id = any (v_examinados)) y
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
             l.vendedor_id, l.asignado_supervisor_id
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

create function private.bases_carga_recoger_core(p_actor uuid, p_operacion_id uuid, p_base_id uuid, p_analista_id uuid)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  v_rol text := private.bases_carga_reparto_rol(p_actor);
  v_max integer;
  v_md5 text;
  v_prev jsonb;
  v_sup uuid;
  v_base crm.bases_carga%rowtype;
  v_subarbol uuid[];
  v_baja boolean;
  v_recogibles uuid[];
  v_recoger uuid[] := '{}';
  v_lote uuid[];
  v_marca bigint := 0;
  v_hasta bigint;
  v_falta integer;
  v_holgura integer;
  v_presupuesto integer;
  v_tomados integer := 0;
  v_pendientes integer;
  v_total integer;
  v_upd integer;
  v_n integer;
  v_estado text;
  v_resp jsonb;
begin
  select k.max_contactos, k.holgura_candados into v_max, v_holgura from private.bases_carga_reparto_constantes() k;
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'Recoger requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation')
      using errcode = '0A000';
  end if;
  if p_base_id is null or p_analista_id is null then
    raise exception 'La base y el analista son obligatorios' using errcode = '22023';
  end if;
  v_md5 := pg_catalog.md5(pg_catalog.jsonb_build_object('tipo', 'recoger', 'base_id', p_base_id, 'analista_id', p_analista_id)::text);
  v_prev := private.bases_carga_operacion_previa(p_actor, v_rol, p_operacion_id, 'recoger', v_md5);
  if v_prev is not null then
    return v_prev;  -- sin referencias a leads: solo cifras
  end if;

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
    raise exception 'La base está retirada: no se recoge' using errcode = '22023';
  end if;
  -- Lo recogido vuelve a la bandeja del dueño: tiene que ser un supervisor activo (el guard de tenencia lo exige igual).
  if private.es_destino_crm_activo(v_base.supervisor_id, array['supervisor']::text[]) is not true then
    raise exception 'El supervisor dueño de la base ya no está activo: no se puede recoger' using errcode = '22023';
  end if;
  v_subarbol := array(select private.bases_carga_subarbol(v_base.supervisor_id));
  -- Supervisión recoge de SU equipo (activo o no: recoger lo de un analista dado de baja es justo el caso); Gerencia, de cualquiera.
  if v_rol is distinct from 'gerencia' and (p_analista_id = any (v_subarbol)) is not true then
    raise exception 'Analista no encontrado o fuera del equipo de la base' using errcode = 'P0002';
  end if;

  -- r1 (auditor P3): de un analista dado de baja no se exige «sin intento» (manda B6, que la baja libera).
  v_baja := private.es_destino_crm_activo(p_analista_id, array['vendedor']::text[]) is not true;
  -- Foto SIN candados: lo repartido a ese analista en esta base y, en orden de reparto, lo recogible
  -- (private.bases_carga_reparto_recogible, una definición).
  select coalesce(pg_catalog.array_agg(bl.lead_id order by bl.asignado_en, bl.lead_id)
                    filter (where private.bases_carga_reparto_recogible(bl.lead_id, p_analista_id, bl.asignado_en, v_baja)), '{}'),
         pg_catalog.cardinality(pg_catalog.array_agg(bl.lead_id))
    into v_recogibles, v_total
    from crm.base_carga_leads bl
   where bl.base_id = p_base_id and bl.activo and bl.analista_id = p_analista_id;
  v_total := coalesce(v_total, 0);
  -- r1 (Codex P2): candado SOLO de lo que se recoge, hasta el tope: por tandas, en ese orden, FOR UPDATE SKIP LOCKED (lo tomado
  -- por otro proceso queda); bajo el candado, en otra sentencia, se vuelve a juzgar con la misma definición. r2 (Codex P2):
  -- presupuesto de candados acumulado, como en repartir, sobre lo que hace falta (el tope o lo recogible, lo menor).
  v_presupuesto := greatest(least(v_max, pg_catalog.cardinality(v_recogibles)) + v_holgura,
                            pg_catalog.ceil(least(v_max, pg_catalog.cardinality(v_recogibles)) * 1.1)::integer);
  loop
    v_falta := v_max - pg_catalog.cardinality(v_recoger);
    exit when v_falta <= 0;
    if v_tomados >= v_presupuesto then
      raise exception 'Los contactos están cambiando; reintenta' using errcode = '55P03';
    end if;
    select coalesce(pg_catalog.array_agg(b.id order by b.o), '{}'), max(b.o) into v_lote, v_hasta
      from (select l.id, p.o
              from crm.leads l
              join unnest(v_recogibles) with ordinality as p(id, o) on p.id = l.id
             where p.o > v_marca
             order by p.o
             limit least(v_falta, v_presupuesto - v_tomados)
               for update of l skip locked) b;
    exit when v_hasta is null;
    v_marca := v_hasta;
    v_tomados := v_tomados + pg_catalog.cardinality(v_lote);
    v_recoger := v_recoger || array(
      select x.id from unnest(v_lote) with ordinality as x(id, o)
        join crm.base_carga_leads bl on bl.lead_id = x.id and bl.base_id = p_base_id and bl.activo and bl.analista_id = p_analista_id
       where private.bases_carga_reparto_recogible(x.id, p_analista_id, bl.asignado_en, v_baja)
       order by x.o);
  end loop;
  -- Con el tope alcanzado, lo recogible que quedó sin examinar es «pendiente» (otra llamada); lo demás, omitido.
  v_pendientes := case when pg_catalog.cardinality(v_recoger) >= v_max
                       then pg_catalog.cardinality(v_recogibles) - v_marca::integer else 0 end;

  begin
    update crm.leads l
       set vendedor_id = null, asignado_supervisor_id = v_base.supervisor_id
     where l.id = any (v_recoger);
    get diagnostics v_upd = row_count;
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate;
    if private.bases_carga_error_transitorio(v_estado) then
      raise exception using errcode = v_estado, message = pg_catalog.format('La recogida se interrumpió (%s); reintenta', v_estado);
    end if;
    raise exception using errcode = v_estado, message = pg_catalog.format('No se pudo recoger (%s); no se recogió ninguno', v_estado);
  end;
  update crm.base_carga_leads bl
     set analista_id = null, asignado_en = null, asignado_por = null
   where bl.base_id = p_base_id and bl.activo and bl.lead_id = any (v_recoger);
  get diagnostics v_n = row_count;
  if v_upd is distinct from pg_catalog.cardinality(v_recoger) or v_n is distinct from pg_catalog.cardinality(v_recoger) then
    raise exception 'La recogida no quedó como se previó' using errcode = 'P0001';
  end if;

  v_resp := pg_catalog.jsonb_build_object('ok', true, 'operacion_id', p_operacion_id, 'base_id', p_base_id, 'analista_id', p_analista_id,
                                          'recogidos', pg_catalog.cardinality(v_recoger),
                                          'omitidos', v_total - pg_catalog.cardinality(v_recoger) - v_pendientes,
                                          'pendientes', v_pendientes);
  insert into crm.base_carga_operaciones (actor, operacion_id, base_id, tipo, pedido_md5, respuesta)
  values (p_actor, p_operacion_id, p_base_id, 'recoger', v_md5, v_resp);
  return v_resp;
end;
$function$;

create function private.bases_carga_contactos_core(p_actor uuid, p_base_id uuid, p_estado text)
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
  return query
    select l.id, l.nombre_completo, l.telefono, l.distrito, bl.creado_en, bl.analista_id, p.nombre_completo,
           private.bases_carga_reparto_estado(l.activo, l.no_contactar, l.etapa, l.vendedor_id,
                                              private.bases_carga_en_subarbol(v_subarbol, l.vendedor_id, l.asignado_supervisor_id),
                                              l.enfriado_hasta, bl.analista_id, h.intento, h.cita, h.reactivado,
                                              bl.analista_id is null and private.base_gestion_en_gestion_hasta(l.id) is not null, v_hoy)
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

-- ── 4 · Puertas de entrada (DEFINER: las tablas no tienen grants; validan y delegan, el actor sale de la sesión) ─────────
create function crm.repartir_base(p_operacion_id uuid, p_base_id uuid, p_reparto jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $function$
begin
  return private.bases_carga_repartir_core((select auth.uid()), p_operacion_id, p_base_id, p_reparto);
end;
$function$;

create function crm.recoger_de_base(p_operacion_id uuid, p_base_id uuid, p_analista_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $function$
begin
  return private.bases_carga_recoger_core((select auth.uid()), p_operacion_id, p_base_id, p_analista_id);
end;
$function$;

create function crm.contactos_de_base(p_base_id uuid, p_estado text default 'sin_repartir')
returns table(lead_id uuid, nombre_completo text, telefono text, distrito text, agregado_en timestamptz, analista_id uuid,
              analista_nombre text, estado text)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  return query select x.lead_id, x.nombre_completo, x.telefono, x.distrito, x.agregado_en, x.analista_id, x.analista_nombre, x.estado
                 from private.bases_carga_contactos_core((select auth.uid()), p_base_id, p_estado) x;
end;
$function$;

-- ── 5 · Dueños y permisos: EXECUTE de las puertas solo para authenticated; el núcleo, para nadie ───────────────────────
alter function private.bases_carga_reparto_constantes() owner to postgres;
alter function private.bases_carga_reparto_rol(uuid) owner to postgres;
alter function private.bases_carga_reparto_analista(text, uuid[], uuid) owner to postgres;
alter function private.bases_carga_reparto_motivo(boolean, boolean, text, boolean, date, boolean, date) owner to postgres;
alter function private.bases_carga_reparto_hechos(uuid, timestamptz) owner to postgres;
alter function private.bases_carga_reparto_recogible(uuid, uuid, timestamptz, boolean) owner to postgres;
alter function private.bases_carga_reparto_estado(boolean, boolean, text, uuid, boolean, date, uuid, boolean, boolean, boolean, boolean, date) owner to postgres;
alter function private.bases_carga_repartir_core(uuid, uuid, uuid, jsonb) owner to postgres;
alter function private.bases_carga_recoger_core(uuid, uuid, uuid, uuid) owner to postgres;
alter function private.bases_carga_contactos_core(uuid, uuid, text) owner to postgres;
alter function crm.repartir_base(uuid, uuid, jsonb) owner to postgres;
alter function crm.recoger_de_base(uuid, uuid, uuid) owner to postgres;
alter function crm.contactos_de_base(uuid, text) owner to postgres;

revoke all on function private.bases_carga_reparto_constantes() from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_reparto_rol(uuid) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_reparto_analista(text, uuid[], uuid) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_reparto_motivo(boolean, boolean, text, boolean, date, boolean, date) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_reparto_hechos(uuid, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_reparto_recogible(uuid, uuid, timestamptz, boolean) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_reparto_estado(boolean, boolean, text, uuid, boolean, date, uuid, boolean, boolean, boolean, boolean, date) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_repartir_core(uuid, uuid, uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_recoger_core(uuid, uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_contactos_core(uuid, uuid, text) from public, anon, authenticated, service_role;
revoke all on function crm.repartir_base(uuid, uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function crm.recoger_de_base(uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function crm.contactos_de_base(uuid, text) from public, anon, authenticated, service_role;
grant execute on function crm.repartir_base(uuid, uuid, jsonb) to authenticated;
grant execute on function crm.recoger_de_base(uuid, uuid, uuid) to authenticated;
grant execute on function crm.contactos_de_base(uuid, text) to authenticated;

-- ── 6 · Comentarios ────────────────────────────────────────────────────────────────────────────────────────────────────
comment on function crm.repartir_base(uuid, uuid, jsonb) is
'Bases cargadas (B9, 04/10/2026): reparte contactos de una base a analistas, TODO O NADA. p_reparto: {"modo":"bloque","asignaciones":[{"analista_id","cantidad"}]} (el servidor elige los SIN REPARTIR más antiguos en la base y salta los que no se pueden repartir: retirados, fuera del ámbito del dueño, que salieron del descarte, No contactar, en descanso, en gestión B6 u ocupados; si no alcanzan → 22023 con detail = disponibles, el número en texto) o {"modo":"individual","asignaciones":[{"lead_id","analista_id"}]} (cada contacto de la base, visible para el actor —si no, P0002—, sin repartir o repartido a otro —se reasigna— y elegible; si no → 22023 con detail {"rechazados":[{lead_id, motivo}]}; tomado por otro proceso → 55P03; el que ya es de ese analista sale en omitidos como ya_asignado). Analista activo, rol vendedor, del subárbol del supervisor DUEÑO (Gerencia: cualquiera, y puede volver a repartir lo que B9 le dio a alguien fuera del equipo del dueño; fuera del equipo → P0002, inactivo o no analista → 22023). Bloquea solo lo necesario (r1). Efecto: crm.leads.vendedor_id = analista (sigue descartado; sin ciclo SLA ni episodio; la actividad «reasignación» y el candado B6 corren solos) y base_carga_leads.analista_id/asignado_en/asignado_por. Topes en private.bases_carga_reparto_constantes. Idempotente por (actor, p_operacion_id). Devuelve {ok, operacion_id, base_id, modo, repartidos, por_analista[{analista_id, cantidad}], omitidos[{lead_id|null, motivo, cantidad?}]} (en bloque, por motivo con lead_id null). Supervisión y Gerencia (otros → 42501); otra operación de la base en curso → 55P03. DEFINER, search_path vacío, lock_timeout 5 s, EXECUTE solo authenticated.';
comment on function crm.recoger_de_base(uuid, uuid, uuid) is
'Bases cargadas (B9, 04/10/2026; r1): devuelve a «sin repartir» (bandeja del supervisor dueño de la base) los contactos que ese analista tiene de la base SIN intento desde que se le repartieron (de un analista de baja no se exige: manda B6, que la baja libera), sin seguimiento activo (B6) y que siguen descartados y en sus manos (lo movido por otra vía no se deshace, E14); los tomados por otro proceso quedan. Supervisión: analistas de su equipo (activos o no); Gerencia: cualquiera. Tope por operación (private.bases_carga_reparto_constantes): lo que excede queda en pendientes. Idempotente por (actor, p_operacion_id). Devuelve {ok, operacion_id, base_id, analista_id, recogidos, omitidos, pendientes}. DEFINER, search_path vacío, lock_timeout 5 s, EXECUTE solo authenticated.';
comment on function crm.contactos_de_base(uuid, text) is
'Bases cargadas (B9, 04/10/2026): los contactos de una base visible para el actor (Supervisión: su subárbol; Gerencia: todas; si no, P0002; otros roles → 42501), para el reparto individual y la pestaña «Bases». p_estado: sin_repartir (por defecto) | repartidos | todos. Solo contactos que el actor ve y siguen activos (nada fuera de su ámbito). Lleva nombre, teléfono y distrito: la pantalla los usa para marcar filas en el reparto individual (el actor ya los ve en su Base para gestión). estado ∈ sin_repartir · sin_tocar · trabajado · en_descanso · cita · reactivado · movido_otra_via · no_contactar (private.bases_carga_reparto_estado). Orden: el del reparto en bloque (más antiguos en la base primero). DEFINER, search_path vacío, EXECUTE solo authenticated.';
comment on function private.bases_carga_reparto_constantes() is
'Bases cargadas (B9; r2): topes de repartir y recoger, MEDIDOS frente al statement_timeout de 8 s de authenticated: contactos por operación (bloque: la suma; individual: las filas; recoger: por llamada), analistas por reparto (100: el recibo ≤ 64 KB) y la holgura de candados (50): bloque y recoger toman como mucho greatest(n + 50, ceil(n × 1,1)) filas para n contactos necesarios; si los rechazados bajo candado la agotan, 55P03 «Los contactos están cambiando; reintenta».';
comment on function private.bases_carga_reparto_rol(uuid) is
'Bases cargadas (B9): rol del actor resuelto en el servidor (private.rol_crm); solo supervisor o gerencia reparten, recogen y listan una base, si no 42501.';
comment on function private.bases_carga_reparto_analista(text, uuid[], uuid) is
'Bases cargadas (B9): valida el analista de un reparto: Supervisión, del subárbol del supervisor dueño (si no, P0002); activo y con rol vendedor (si no, 22023). Gerencia: cualquiera activo y vendedor.';
comment on function private.bases_carga_reparto_motivo(boolean, boolean, text, boolean, date, boolean, date) is
'Bases cargadas (B9): UNA definición de «este contacto de la base no se puede repartir» (NULL = sí): inactivo, fuera_de_ambito, no_descartado, no_contactar, en_descanso, en_gestion (B6). La usan el bloque y el individual.';
comment on function private.bases_carga_reparto_hechos(uuid, timestamptz) is
'Bases cargadas (B9): UNA definición de «qué pasó desde» un momento, por las actividades de la base: algún intento (intento_base), si alguno agendó cita y si se reactivó desde la base (reactivacion_base). Sin agregados de conteo (censo). La usan recoger y contactos_de_base; B10 puede reutilizarla.';
comment on function private.bases_carga_reparto_recogible(uuid, uuid, timestamptz, boolean) is
'Bases cargadas (B9 r1): UNA definición de «se puede recoger»: vivo, descartado y en manos de ese analista (lo movido por otra vía no se deshace, E14), sin intento desde que se le repartió (salvo analista de baja: manda B6, que la baja libera) y sin seguimiento activo B6. La usan la foto y la revisión bajo candado de recoger.';
comment on function private.bases_carga_reparto_estado(boolean, boolean, text, uuid, boolean, date, uuid, boolean, boolean, boolean, boolean, date) is
'Bases cargadas (B9): UNA definición del estado de un contacto de la base (contrato B9): no_contactar · movido_otra_via · cita · reactivado · en_descanso · sin_repartir/trabajado (sin repartir) · trabajado/sin_tocar (repartido, desde asignado_en). B10 puede reutilizarla para sus conteos.';
comment on function private.bases_carga_repartir_core(uuid, uuid, uuid, jsonb) is
'Bases cargadas (B9; r1): núcleo de crm.repartir_base. Orden: forma → idempotencia (recibo repartir, replay que revalida referencias) → base (visible, FOR UPDATE NOWAIT, viva, dueño activo) → analistas → bloque: foto sin candados de los sin repartir con su motivo y candado SKIP LOCKED SOLO de los que faltan, por tandas y en el orden del reparto; individual: ámbito (P0002) ANTES del candado SKIP LOCKED de lo pedido → revisión bajo candado con la misma definición y sin intento durante la operación → UPDATE de crm.leads por el camino de la casa → pertenencia → recibo. Sin count( ni sum(1) (censo).';
comment on function private.bases_carga_recoger_core(uuid, uuid, uuid, uuid) is
'Bases cargadas (B9; r1): núcleo de crm.recoger_de_base. Base (visible, NOWAIT, viva, dueño activo) → analista del equipo → foto sin candados de lo recogible (private.bases_carga_reparto_recogible) → candado SKIP LOCKED SOLO de eso y hasta el tope, por tandas en orden de reparto, y revisión bajo candado con la misma definición → bandeja del dueño → pertenencia sin analista → recibo recoger. Sin count( ni sum(1) (censo).';
comment on function private.bases_carga_contactos_core(uuid, uuid, text) is
'Bases cargadas (B9): núcleo de crm.contactos_de_base: base visible, solo contactos con private.bases_carga_lead_ref (visibles y activos), estado de private.bases_carga_reparto_estado.';

-- ── 7 · Postflight (SOLO catálogo) ─────────────────────────────────────────────────────────────────────────────────────
create temp table _b9_censo_despues on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;
do $postflight$
declare
  v_mal text;
begin
  -- Cuerpos ensayados (md5(prosrc) medido al generar la migración), seguridad, search_path, dueño, ACL y comentario.
  with esperado(firma, cuerpo, definer, config, acl) as (values
    ('private.bases_carga_reparto_constantes()', '5f563cef58a250251d97b1baf2f4b4d3', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_reparto_rol(uuid)', '88c3330223eefd8e32c27d2ef4541f3a', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_reparto_analista(text,uuid[],uuid)', '94fd2808e2ea524702f65142889ecc2f', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_reparto_motivo(boolean,boolean,text,boolean,date,boolean,date)', 'ad244b42610e7704d00327ee6cde21ab', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_reparto_hechos(uuid,timestamptz)', '9640ce4a6765a95464ac6e8e3a811a20', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_reparto_recogible(uuid,uuid,timestamptz,boolean)', '36d80e0e61b293d9cdd710fc00758054', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.base_gestion_en_gestion_hasta(uuid)', '72621c4311876d39be13e0dfc4278f39', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_reparto_estado(boolean,boolean,text,uuid,boolean,date,uuid,boolean,boolean,boolean,boolean,date)', '28ae6bf56e4d54fdf45ec5f976ddbce3', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)', '8ace9326744cba6c262adb20203b4be0', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_recoger_core(uuid,uuid,uuid,uuid)', '8fd1565059eb61f90374d0bba3a6581a', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_contactos_core(uuid,uuid,text)', '0faaf15b274890e1e788632c27b477bd', false, 'search_path=""', '{postgres=X/postgres}'),
    ('crm.repartir_base(uuid,uuid,jsonb)', 'fd7531ba7cd7cf8a259a389e2895ee2e', true, 'search_path="",lock_timeout=5s', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.recoger_de_base(uuid,uuid,uuid)', '4744f70e69c0f70c22a6a295184e3095', true, 'search_path="",lock_timeout=5s', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.contactos_de_base(uuid,text)', 'd528bab6930698d160f9635417a3ca7a', true, 'search_path=""', '{postgres=X/postgres,authenticated=X/postgres}'))
  select string_agg(e.firma, ', ' order by e.firma) into v_mal
    from esperado e
    left join pg_proc p on p.oid = to_regprocedure(e.firma)
   where (p.oid is not null and md5(p.prosrc) = e.cuerpo and p.prosecdef = e.definer
          and array_to_string(p.proconfig, ',') = e.config and p.proowner = 'postgres'::regrole
          and p.proacl is not null and p.proacl::text = e.acl
          and obj_description(p.oid, 'pg_proc') is not null) is not true;
  if v_mal is not null then
    raise exception 'POSTFLIGHT B9: funciones que no quedaron como se ensayaron: %', v_mal;
  end if;

  if (
    -- Permisos efectivos: las puertas solo para authenticated; el núcleo, para nadie de la API.
    not exists (select 1 from unnest(array['crm.repartir_base(uuid,uuid,jsonb)', 'crm.recoger_de_base(uuid,uuid,uuid)',
                                           'crm.contactos_de_base(uuid,text)']) f(firma)
                 where has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE')
                    or not has_function_privilege('authenticated', f.firma, 'EXECUTE'))
    and not exists (select 1 from pg_proc p cross join unnest(array['anon', 'authenticated', 'service_role']) r(rol)
                     where p.pronamespace = 'private'::regnamespace and p.proname like 'bases\_carga\_%'
                       and has_function_privilege(r.rol, p.oid, 'EXECUTE'))
    -- Una sola sobrecarga de cada puerta y de cada pieza del núcleo de B9.
    and (select count(*) from pg_proc p where p.pronamespace = 'crm'::regnamespace
          and p.proname in ('repartir_base', 'recoger_de_base', 'contactos_de_base')) = 3
    and (select count(*) from pg_proc p where p.pronamespace = 'private'::regnamespace
          and (p.proname like 'bases\_carga\_reparto\_%' or p.proname in ('bases_carga_repartir_core', 'bases_carga_recoger_core', 'bases_carga_contactos_core'))) = 10
    -- r1: la regla nueva de B6, una sola sobrecarga, STABLE, y su comentario dice el cambio; el candado B6 sigue usándola.
    and (select count(*) from pg_proc p where p.pronamespace = 'private'::regnamespace and p.proname = 'base_gestion_en_gestion_hasta') = 1
    and (select p.provolatile = 's' and obj_description(p.oid, 'pg_proc') like 'B6 (Miguel, 03/10/2026; regla cambiada en B9 r1%'
           from pg_proc p where p.oid = to_regprocedure('private.base_gestion_en_gestion_hasta(uuid)'))
    and (select p.prosrc ~ 'base_gestion_en_gestion_hasta' from pg_proc p where p.oid = to_regprocedure('private.trg_leads_guard_seguimiento_activo()'))
    -- B9 no toca la válvula de B8 ni se la enciende a nadie.
    and not exists (select 1 from pg_proc p where p.prosrc ~ 'op_bases_carga'
                     and p.oid not in (to_regprocedure('private.trg_leads_base_cargada_solo_puerta()'),
                                       to_regprocedure('private.bases_carga_nace_dormido(text,text,text,boolean)'),
                                       to_regprocedure('private.bases_carga_cargar_lote_core(uuid,uuid,uuid,jsonb)')))
    -- B8 intacta: las piezas que B9 usa conservan su identidad.
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '0b4e20b805109892a56d2d127cd54a9c'
           from pg_proc p where p.oid = to_regprocedure('private.bases_carga_operacion_previa(uuid,text,uuid,text,text,uuid[])'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '9f671b71f96facf74c7ee4dcec02b6f9'
           from pg_proc p where p.oid = to_regprocedure('private.bases_carga_lead_ref(uuid,text,uuid)'))
    -- Censo: nada nuevo entra y es el de la foto.
    and not exists (select 1 from pg_temp._b9_censo_despues c where c.objeto not in (select a.objeto from pg_temp._b9_censo_antes a))
    and (select count(*) from pg_temp._b9_censo_antes) = (select count(*) from pg_temp._b9_censo_despues)
  ) is not true then
    raise exception 'POSTFLIGHT B9: permisos, sobrecargas, la valvula, B8 o el censo no quedaron como se ensayaron';
  end if;
  raise notice 'B9 CATALOGO OK: 3 puertas (EXECUTE solo authenticated), nucleo privado sin EXECUTE (10 funciones), regla nueva de B6 (seguimiento activo desde que el dueno actual recibio el lead), B8 intacta, valvula sin tocar, censo igual. COMPORTAMIENTO NO PROBADO en esta migracion.';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261004222602' and name = 'crm_bases_cargadas_repartir' and cardinality(statements) = 1
                   and md5(statements[1]) = '8a169944b9394e45ed27f805978c26dc') then
    raise exception 'REGISTRO: la fila 20261004222602 / crm_bases_cargadas_repartir no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261004222602 / crm_bases_cargadas_repartir (1 sentencia: el archivo entero)';
end $post$;
commit;

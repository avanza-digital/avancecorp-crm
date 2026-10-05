-- 20261004184501_crm_bases_cargadas_cargar.sql
--
-- Bases cargadas · B8: cargar un archivo y armar bases desde el CRM. Pedido de Miguel (03/10/2026), decisiones E1–E14
-- (`BASE PARA GESTION/BASES-CARGADAS.md`) sobre el esquema de B7 (20261004160034). Tres puertas DEFINER en `crm` (validan,
-- resuelven rol y ámbito en el servidor y delegan) y su núcleo en `private`:
--   · crm.crear_base(operación, nombre, origen, supervisor, archivo) — la base de un archivo. Supervisión: la base es suya
--     (otro supervisor → 42501). Gerencia: DEBE elegir un supervisor activo (E11; sin él → 22023). Otros roles → 42501.
--     Nombre 1–80, único entre las bases vivas de ese supervisor (23505). Origen solo «archivo» (la del CRM la crea
--     crm.armar_base_crm).
--   · crm.cargar_base_lote(operación, base, filas jsonb) — un LOTE del archivo (el navegador lo parte; el servidor decide).
--     Máximo por lote: private.bases_carga_constantes().max_filas_lote (MEDIDO, ver LOTE); total de la base ≤ 5000 filas (E5).
--     Veredicto por fila: cargada · ya_existia (motivo: cliente, con_dueno, en_bolsa, descartado, convertido, retirado) ·
--     no_contactar · invalida (motivo) · repetida (en_archivo / en_base). Nunca un duplicado (E2): ver IDENTIDAD.
--   · crm.armar_base_crm(operación, nombre, supervisor, leads[]) — hasta 2000 descartados ELEGIBLES (E12) del ámbito del
--     actor; la base (origen crm) y su pertenencia SIN tocar el lead (E13: conserva sus intentos). Devuelve incluidos y
--     excluidos con su motivo (no_encontrado, inactivo, no_descartado, no_contactar, datos_invalidos, en_descanso,
--     en_otra_base, en_gestion, repetido).
--   Las tres: idempotentes por (actor, id de operación) con recibo inmutable en crm.base_carga_operaciones (el replay
--   devuelve la MISMA respuesta; el mismo id con otro pedido → 22023). Respuestas sin datos personales (ids y motivos; el
--   lead_id de un «ya existía» solo si el actor puede ver ese lead).
--
-- EL CONTACTO NACE DORMIDO (E7) — qué dispara su INSERT en crm.leads (inventario de los 31 disparadores, orden efectivo):
--   BEFORE: 000_base_cargada_solo_puerta (pide la válvula crm.op_bases_carga: la enciende SOLO el núcleo del lote, alrededor
--   de su INSERT, y la apaga antes de salir) · 000_hereda_veto (persona vetada → P0429; el veredicto lo atrapa antes) ·
--   00_disponibilidad_insert (exigía «nacer activo y en etapa operativa» a toda alta con usuario → B8: excepción SOLO para el
--   que nace dormido; el veredicto de disponibilidad debe seguir siendo «libre») · 00_guard_tenencia (bandeja de un
--   supervisor activo; creado_en = statement_timestamp()) · 01_sla_global (sello del lead, inocuo) · before_insert (impedía
--   nacer terminal sin crm.op_privilegiada → B8: excepción SOLO para el dormido; NO se enciende crm.op_privilegiada, que
--   abriría perfil/contrato/conversión e inversionista_id) · normalizar_tel · protege_inversionista_id (lo deja NULL) ·
--   zz_enlaza_identidad (con la identidad encendida enlaza a una persona sin lead, o rechaza si ya tiene: el veredicto lo
--   atrapa antes) · zz_sello_base_gestion (sus tres columnas van NULL) · zz_sello_descarte (le pone descartado_en NULL al
--   insertar; su cuerpo está SELLADO por md5 en private.assert_gestion_diaria_resultado — 150d7ae5…, 20260921153654:525 —:
--   NO se toca) · NUEVO zz_sello_descarte_base_cargada (después, por nombre: al dormido le pone descartado_en = momento de la
--   carga y descartado_por = el actor; ver FECHA) · zzz_tenencia_desde (NULL: no es operativo) · zzzz_usuario_retirado
--   (descartado → no aplica).
--   AFTER: audit_leads (bitácora, con dni enmascarado: una fila por contacto) · 02_sla_versionado (abría SIEMPRE un ciclo en
--   crm.lead_sla_ciclos al insertar: crm.metricas_sla_fn lo cuenta por iniciado_en, y un dormido sin gestión saldría «fuera
--   de objetivo» en primera gestión y primer contacto; los ciclos no se borran → B8: el dormido NO abre ciclo; su primer
--   ciclo nace al reactivarlo (ciclo 2), y crm.tareas no admite tareas sobre un descartado, así que nadie exige su ciclo 1)
--   · asignaciones (sin analista ni etapa operativa: no abre episodio en lead_asignaciones) · zz_puente_identidad (solo si
--   quedó enlazado).
--   LLEGADAS: private.conversion_episodios solo cuenta orígenes landing/formulario/referido → base_cargada no suma llegadas
--   (E10). metricas_sla_global_core solo mira el ledger y los leads operativos. «Descartes del mes» (rescate_descartes_mes y
--   _meses) sale de lead_asignaciones: el dormido NO aparece. La cola del coordinador exige lead sin bandeja: tampoco.
--   Realtime: ninguna tabla crm está en publicaciones (banco a paridad). Una sola definición de «nace dormido»:
--   private.bases_carga_nace_dormido (válvula + origen, etapa y motivo base_cargada + activo).
-- FECHA (pendiente de B7): con descartado_en, el contacto queda en enfriamiento (base_cargada = 30 días): el alta manual del
--   mismo teléfono o DNI ve «enfriamiento» (no crea duplicado) y después «reutilizable»; la base para gestión tiene «días
--   desde el descarte» y private.base_gestion_en_gestion_hasta su ventana. La fecha la pone el disparador (no la puerta):
--   ni bajo la válvula se puede antedatar (antedatarla acortaría el enfriamiento).
-- IDENTIDAD (E2): por fila, private.verificar_disponibilidad_lead_impl (el veredicto de la casa, 20260906200000:3514-3731)
--   MÁS private.bases_carga_contacto_existente («existe CUALQUIER lead con ese teléfono o DNI»: el verificador dice «libre»
--   con retirados, descartados de < 24 h con motivo de 0 días o convertidos con otro teléfono — F0). Teléfono con la regla
--   del alta (private.normalizar_telefono + ^\+519[0-9]{8}$, crm.crear_lead_si_disponible); DNI opcional de 8 dígitos.
-- CANDADOS del lote (orden de la casa, 20260804165440:20-55 y crear_lead_si_disponible): fila de la base (FOR UPDATE: los
--   lotes de una base van de a uno) → documentos (identidad_bloquear_documento, en orden) → personas (identidad_bloquear_
--   persona, en orden de persona) → contactos (bloquear_contactos_lead, que ordena todas las claves), UNA vez por lote y
--   ANTES de evaluar; los disparadores los vuelven a pedir sin esperar. Un alta manual concurrente del mismo teléfono espera
--   o hace esperar: nunca duplicado ni ciclo de espera (lo prueba el banco). B9/B10 deben tomar la fila de la base ANTES que
--   los contactos.
-- LOTE = 100 filas (private.bases_carga_constantes(); r2: era 200; 5000 filas = 50 lotes). authenticated corre con
--   statement_timeout = 8 s. En la RAMA con datos (instancia micro, datos de producción, r1) un lote de 200 contactos nuevos tardó
--   3,27 s el mínimo y 5,46 s en frío: con 100, la mitad. El costo lo pone el verificador de la casa, que recorre los clientes
--   del portal aplicando normalizar_telefono a cada uno (sin índice: en el banco ~0,5 ms + ~2,8 ms por cada 1000 clientes, dos
--   veces por contacto nuevo: núcleo y disparador); un lote retiene ~2–3 candados advisory por fila (≤ 300 con 100). Los lotes
--   de una misma base no se esperan entre sí (NOWAIT: 55P03 y el front reintenta). (Un índice por teléfono normalizado en
--   public.perfiles lo abarataría: toca el portal, decide Miguel.)
-- CENSO: ninguna función nueva usa count( ni sum(1) (los conteos se acumulan en variables o con jsonb_array_length); el
--   postflight exige el censo analítico igual a la foto previa.
-- QUÉ NO CAMBIA: trg_leads_zz_sello_descarte (sellado), verificar_disponibilidad_lead_impl, crear_lead_si_disponible, las
--   tablas de B7 (sin DDL), grants y policies de crm.leads.
-- PRECONDICIÓN: B7 aplicada (20261004160034) — el preflight fija las definiciones vivas que reemplaza y de las que depende.
-- r1 (04/10, Codex r1 BLOCK 2 P1 + 1 P2 + riesgos; auditor-rls PASS con P3):
--   · armar bloquea FOR UPDATE, en orden de id, los leads del ámbito ANTES de evaluar (reactivar, vetar, reasignar y el intento
--     B6 toman la fila del lead: quedan en serie); el ámbito es el del SUPERVISOR dueño (private.bases_carga_subarbol), también
--     si arma Gerencia; rechaza (22023) arreglos que no sean simples con límite inferior 1;
--   · toda referencia (lead_id) pasa por private.bases_carga_lead_ref (el actor lo ve Y sigue activo), también la de
--     repetida/en_base, que además solo mira pertenencias VIVAS; con algún lead fuera del ámbito del actor el veredicto es
--     «ya_existia» sin motivo ni id;
--   · el replay devuelve el recibo solo si el actor sigue viendo la base (P0002 si no);
--   · si la tanda del INSERT choca (carrera), se repite fila a fila: P0481/P0409 → ya_existia, P0429 → no_contactar, sin el
--     detail del disparador; otra excepción aborta sin datos («No se pudo cargar la fila N (código)»);
--   · la fila de la base se toma FOR UPDATE NOWAIT: el segundo lote de la misma base falla al instante (55P03, «Hay otra carga
--     en curso de esta base; reintenta») en vez de gastar sus 8 s esperando;
--   · CHECK enfriamiento_politica_base_cargada_dias_positivos (motivo <> base_cargada o dias > 0);
--   · teléfonos y DNI sin normalizar: el envoltorio sigue comparando por igualdad (0 casos en el banco; el DNI no puede: CHECK
--     validado); la rama corre supabase/scripts/base-gestion/b8-telefonos-sin-normalizar.sql y decide.
-- r2 (04/10, Codex r2 BLOCK 2 P1 + P3; última ronda):
--   · armar bloquea FOR UPDATE SKIP LOCKED y evalúa e inserta SOLO el conjunto efectivamente bloqueado; lo que otro proceso tiene
--     tomado sale «ocupado» (reintenta) sin esperar; lo que entra al ámbito después de bloquear no entra;
--   · el replay vuelve a pasar CADA lead que nombra el recibo por bases_carga_lead_ref (si uno ya no está a su alcance → P0002);
--   · el respaldo fila a fila no atrapa lo transitorio (40P01, 55P03, 57014, 40001, 25P02, clases 53/54/57/58): aborta el lote
--     con el MISMO código y «La carga se interrumpió (código); reintenta», sin el detail (57014 no se puede atrapar: sale tal cual);
--   · el respaldo aplica a un P0429 la misma regla del ámbito (private.bases_carga_fuera_de_ambito, una definición);
--   · comentario de crm.armar_base_crm al día (ámbito del supervisor dueño); dias de crm.enfriamiento_politica es NOT NULL
--     (el preflight lo exige: el CHECK no tiene que tratar NULL);
--   · (rama con datos) lote máximo 100; la reversa ya no compara huellas globales que dependen del entorno.
-- REVERSA: supabase/scripts/base-gestion/reversa-b8.sql (se niega si hay bases o contactos cargados; huellas de todo lo que
--   deja B8). Comprobación tras aplicar: supabase/scripts/base-gestion/b8-comprobar-tras-aplicar.sql.
-- CANDADOS DE TABLA: CREATE TRIGGER toma SHARE ROW EXCLUSIVE sobre crm.leads (frena escrituras, no lecturas) y el CHECK
--   nuevo ACCESS EXCLUSIVE sobre crm.enfriamiento_politica (8 filas; la leen el alta y el verificador), hasta el commit; se
--   toman primero, en ese orden fijo (el de B7), antes del preflight. Sin DML: el postflight es SOLO de catálogo.
begin;
set transaction isolation level read committed;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

select pg_advisory_xact_lock(hashtext('crm_migracion_funciones'));

-- Foto del censo analítico ANTES del candado de tabla (solo catálogo).
create temp table _b8_censo_antes on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;

lock table crm.leads in share row exclusive mode;
-- r1 (auditor P3): el CHECK nuevo del enfriamiento exige ACCESS EXCLUSIVE de esa tabla (8 filas). Orden de la casa: crm.leads
-- → crm.enfriamiento_politica (como B7).
lock table crm.enfriamiento_politica in access exclusive mode;

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $preflight$
declare
  v_ident text := 'md5(prosrc|prosecdef|provolatile|proconfig|proowner)';
begin
  if (
    -- Nada de B8 existe todavía.
    to_regprocedure('crm.crear_base(uuid,text,text,uuid,text)') is null
    and to_regprocedure('crm.cargar_base_lote(uuid,uuid,jsonb)') is null
    and to_regprocedure('crm.armar_base_crm(uuid,text,uuid,uuid[])') is null
    and not exists (select 1 from pg_proc p where p.pronamespace in ('crm'::regnamespace, 'private'::regnamespace)
                     and (p.proname like 'bases\_carga\_%' or p.proname = 'trg_leads_sello_descarte_base_cargada')
                     and p.oid <> to_regprocedure('private.bases_carga_operacion_inmutable()'))  -- la de B7
    and not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname like 'trg\_leads\_zz\_sello\_descarte\_%')
    and not exists (select 1 from pg_constraint c where c.conrelid = 'crm.enfriamiento_politica'::regclass
                     and c.conname = 'enfriamiento_politica_base_cargada_dias_positivos')
    -- B7 aplicada, con sus tablas y su sello (la única función que hoy lee la válvula).
    and to_regclass('crm.bases_carga') is not null and to_regclass('crm.base_carga_leads') is not null
    and to_regclass('crm.base_carga_operaciones') is not null
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '9074e2e17457827b9e81f059087c5219'
           from pg_proc p where p.oid = to_regprocedure('private.trg_leads_base_cargada_solo_puerta()'))
    and not exists (select 1 from pg_proc p where p.prosrc ~ 'op_bases_carga'
                     and p.oid <> to_regprocedure('private.trg_leads_base_cargada_solo_puerta()'))
    and not exists (select 1 from pg_db_role_setting s cross join lateral unnest(s.setconfig) c(x) where c.x ilike 'crm.op_bases_carga=%')
    -- Las tres funciones que se REEMPLAZAN, exactas (identidad independiente del search_path, ACL y comentario).
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = 'f2ae7c16f2502b951974701fd78200b3'
                and md5(p.prosrc) = 'de4823aebce64646271689a5d78db18b'
                and p.proacl is not null and p.proacl::text = '{postgres=X/postgres}'
                and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = 'fd7e577f61e6d0ab0cff7bf28a5c3cc4'
           from pg_proc p where p.oid = to_regprocedure('private.leads_before_insert()'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '693dd43beb78361cdbbd59882a07d828'
                and md5(p.prosrc) = 'ba0fd3ef2e9a16181fb6b944ac002450'
                and p.proacl is not null and p.proacl::text = '{postgres=X/postgres}'
                and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '3b06d9fdd6b37014bb3a2d2072bcd139'
           from pg_proc p where p.oid = to_regprocedure('private.trg_leads_disponibilidad_atomica()'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = 'b0395b0352e44554f207c29ce85dc8b8'
                and md5(p.prosrc) = '70170f3aaabc81790fa1edf83911b5e2'
                and p.proacl is not null and p.proacl::text = '{postgres=X/postgres}'
                and obj_description(p.oid, 'pg_proc') is null
           from pg_proc p where p.oid = to_regprocedure('private.trg_leads_sla_versionado()'))
    -- Y son las de sus disparadores, habilitados.
    and exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_before_insert'
                 and t.tgfoid = to_regprocedure('private.leads_before_insert()') and t.tgenabled = 'O')
    and exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_insert'
                 and t.tgfoid = to_regprocedure('private.trg_leads_disponibilidad_atomica()') and t.tgenabled = 'O')
    and exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_02_sla_versionado'
                 and t.tgfoid = to_regprocedure('private.trg_leads_sla_versionado()') and t.tgenabled = 'O')
    and exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_zz_sello_descarte'
                 and t.tgfoid = to_regprocedure('private.trg_leads_zz_sello_descarte()') and t.tgenabled = 'O')
    and exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_000_base_cargada_solo_puerta'
                 and t.tgfoid = to_regprocedure('private.trg_leads_base_cargada_solo_puerta()') and t.tgenabled = 'O')
    -- El sello del descarte NO se toca: su huella es la que sella private.assert_gestion_diaria_resultado (search_path vacío).
    and (select md5(pg_get_functiondef(p.oid)) = '150d7ae56bb2094733f7620a1362c29e' from pg_proc p where p.oid = to_regprocedure('private.trg_leads_zz_sello_descarte()'))
    -- De lo que depende el núcleo, con la identidad ensayada (si cambiara, lo probado no valdría).
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = 'a78247a515be78b145fec439fc299458'
           from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text,uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = 'e144f7d020269c61258b4d3980ac88c6'
           from pg_proc p where p.oid = to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = 'e57ae45b49d7084904749d08f447d719'
           from pg_proc p where p.oid = to_regprocedure('private.bloquear_contactos_lead(text[],text[])'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '86d241eb531b5ad7b46842ad351eb5f8'
           from pg_proc p where p.oid = to_regprocedure('private.identidad_bloquear_documento(text,text)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = 'b8e98689c92d6a0de30c7563d4bb2898'
           from pg_proc p where p.oid = to_regprocedure('private.identidad_bloquear_persona(text,text)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '531bb5e2319adf3588b2a7b9f407e675'
           from pg_proc p where p.oid = to_regprocedure('private.inversionista_por_documento(text,text)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '655e78b3def8396a141e215b01f37f81'
           from pg_proc p where p.oid = to_regprocedure('private.normalizar_telefono(text)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = 'c4ae35f90e850548653a25f08d25327c'
           from pg_proc p where p.oid = to_regprocedure('private.base_gestion_lead_visible(uuid,text,uuid,uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = 'e90da5df4c53fa1c30f0ca5f71431631'
           from pg_proc p where p.oid = to_regprocedure('private.base_gestion_en_gestion_hasta(uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '16960a2a21cc5c372431c2dd67acafe4'
           from pg_proc p where p.oid = to_regprocedure('private.rol_crm(uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = '45ae492c03234b80336c0b8f5c8ac09b'
           from pg_proc p where p.oid = to_regprocedure('private.vendedor_ids_visibles(uuid)'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')
                    || '|' || p.proowner::regrole::text) = 'b35bca38019cdd27b801cf4c39d4c756'
           from pg_proc p where p.oid = to_regprocedure('private.es_destino_crm_activo(uuid,text[])'))
    -- El enfriamiento base_cargada existe con días > 0 (con 0 el alta vería «libre» 24 h y duplicaría: E2).
    and (select ep.dias > 0 from crm.enfriamiento_politica ep where ep.motivo = 'base_cargada')
    -- r2: dias es NOT NULL (si no, el CHECK nuevo dejaría pasar un NULL para base_cargada).
    and (select a.attnotnull from pg_attribute a where a.attrelid = 'crm.enfriamiento_politica'::regclass and a.attname = 'dias' and not a.attisdropped)
  ) is not true then
    raise exception 'PREFLIGHT B8: ya aplicada o a medias, B7 no aplicada, una funcion que se reemplaza o de la que depende no es la medida (%), o la valvula crm.op_bases_carga ya la usa otra funcion', v_ident;
  end if;
end;
$preflight$;

-- ── 1 · Núcleo: «nace dormido» (una sola definición) y la fecha de su descarte ─────────────────────────────────────────
create function private.bases_carga_constantes()
returns table(max_filas_base integer, max_filas_lote integer, max_leads_armar integer)
language sql
immutable
security invoker
set search_path = ''
as $function$
  select 5000, 100, 2000;
$function$;

create function private.bases_carga_nace_dormido(p_origen text, p_etapa text, p_motivo text, p_activo boolean)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $function$
  -- B8: la ÚNICA definición de «este alta es un contacto de base cargada que nace dormido». La válvula de transacción
  -- crm.op_bases_carga solo la enciende el núcleo del lote alrededor de su INSERT. `is true`: un NULL nunca habilita.
  select (coalesce(pg_catalog.current_setting('crm.op_bases_carga', true), 'off') = 'on'
          and p_origen = 'base_cargada' and p_etapa = 'descartado' and p_motivo = 'base_cargada' and p_activo) is true;
$function$;

create function private.trg_leads_sello_descarte_base_cargada()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  -- B8: corre DESPUÉS de trg_leads_zz_sello_descarte (que pone descartado_en NULL al insertar y está sellado por huella).
  -- Al contacto que nace dormido le pone la fecha de SU descarte (= la carga) y quién lo cargó. La fecha la pone el
  -- disparador, no la puerta: ni bajo la válvula se puede antedatar (acortaría el enfriamiento base_cargada).
  if private.bases_carga_nace_dormido(new.origen, new.etapa, new.motivo_descarte, new.activo) then
    new.descartado_en := pg_catalog.statement_timestamp();
    new.descartado_por := (select auth.uid());
  end if;
  return new;
end;
$function$;

-- ── 2 · Núcleo: ayudantes de las puertas ───────────────────────────────────────────────────────────────────────────────
create function private.bases_carga_rol(p_actor uuid)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_rol text := private.rol_crm(p_actor);
begin
  if p_actor is null or (v_rol in ('supervisor', 'gerencia')) is not true then
    raise exception 'Solo Supervisión y Gerencia cargan y arman bases' using errcode = '42501';
  end if;
  return v_rol;
end;
$function$;

create function private.bases_carga_supervisor_destino(p_actor uuid, p_rol text, p_supervisor_id uuid)
returns uuid
language plpgsql
stable
security invoker
set search_path = ''
as $function$
begin
  if p_rol = 'supervisor' then
    if p_supervisor_id is not null and p_supervisor_id is distinct from p_actor then
      raise exception 'Un supervisor solo crea bases para su propia bandeja' using errcode = '42501';
    end if;
    return p_actor;
  elsif p_rol = 'gerencia' then
    -- E11: Gerencia elige el supervisor dueño (sus contactos quedan en esa bandeja).
    if p_supervisor_id is null then
      raise exception 'Gerencia debe elegir el supervisor dueño de la base' using errcode = '22023';
    end if;
    if private.es_destino_crm_activo(p_supervisor_id, array['supervisor']::text[]) is not true then
      raise exception 'El supervisor elegido no existe, no está activo o no es supervisor' using errcode = '22023';
    end if;
    return p_supervisor_id;
  end if;
  raise exception 'Solo Supervisión y Gerencia cargan y arman bases' using errcode = '42501';
end;
$function$;

create function private.bases_carga_base_visible(p_actor uuid, p_rol text, p_supervisor_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $function$
  -- Espejo de la policy crm.bases_carga_select (B7): Gerencia todas; Supervisión las de su subárbol. `is true`.
  select (p_rol = 'gerencia'
          or (p_rol = 'supervisor' and p_supervisor_id in (select private.vendedor_ids_visibles(p_actor)))) is true;
$function$;

create function private.bases_carga_subarbol(p_supervisor uuid)
returns setof uuid
language sql
stable
security invoker
set search_path = ''
as $function$
  -- r1 (auditor P3): el subárbol del SUPERVISOR dueño de la base, también cuando la arma Gerencia (private.vendedor_ids_visibles
  -- solo enumera el del usuario de la sesión). Espejo de su rama «supervisor»: si cambia, cambiar aquí.
  with recursive subarbol as (
    select e.perfil_id from crm.equipo e where e.perfil_id = p_supervisor
    union
    select e.perfil_id from crm.equipo e join subarbol s on e.supervisor_id = s.perfil_id
  )
  select s.perfil_id from subarbol s
$function$;

create function private.bases_carga_en_subarbol(p_subarbol uuid[], p_vendedor_id uuid, p_asignado_supervisor_id uuid)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $function$
  -- r1: UNA definición de «el lead está en el ámbito del dueño» (espejo de leads_select sin Gerencia): su analista en el subárbol,
  -- o sin analista y en la bandeja de un supervisor del subárbol. La usan el candado y la evaluación de armar_base_crm. `is true`.
  select (p_vendedor_id = any (p_subarbol) or (p_vendedor_id is null and p_asignado_supervisor_id = any (p_subarbol))) is true;
$function$;

create function private.bases_carga_lead_ref(p_actor uuid, p_rol text, p_lead_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $function$
  -- r1 (Codex P1, auditor P3): UNA definición de «este lead_id se puede devolver o guardar en un recibo»: el actor lo VE (espejo
  -- de leads_select, private.base_gestion_lead_visible) y sigue ACTIVO (un retirado no se abre). Sin lead → false.
  select coalesce((select l.activo and private.base_gestion_lead_visible(p_actor, p_rol, l.vendedor_id, l.asignado_supervisor_id)
                     from crm.leads l where l.id = p_lead_id), false);
$function$;

create function private.bases_carga_error_transitorio(p_sqlstate text)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $function$
  -- r2 (Codex riesgo): interbloqueo, espera agotada, serialización, cancelación, transacción abortada y las clases de recursos,
  -- límites del programa, intervención del operador y del sistema: abortan el lote ENTERO (el front reintenta); nunca se
  -- repiten fila a fila ni se disfrazan de veredicto.
  select (p_sqlstate in ('40P01', '55P03', '57014', '40001', '25P02') or pg_catalog.left(p_sqlstate, 2) in ('53', '54', '57', '58')) is true;
$function$;

create function private.bases_carga_operacion_previa(p_actor uuid, p_rol text, p_operacion_id uuid, p_tipo text, p_pedido_md5 text,
                                                     p_lead_ids uuid[] default null)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  v_op crm.base_carga_operaciones%rowtype;
begin
  if p_operacion_id is null then
    raise exception 'El identificador de la operación es obligatorio' using errcode = '22023';
  end if;
  -- Un doble clic espera aquí al primero y recibe su recibo (idempotencia por actor e id de operación).
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('avancecrm:bases_carga:op:' || p_actor::text || ':' || p_operacion_id::text, 0));
  select o.* into v_op from crm.base_carga_operaciones o where o.actor = p_actor and o.operacion_id = p_operacion_id;
  if not found then
    return null;
  end if;
  if v_op.tipo is distinct from p_tipo or v_op.pedido_md5 is distinct from p_pedido_md5 then
    raise exception 'Este identificador de operación ya se usó con un pedido distinto' using errcode = '22023';
  end if;
  -- r1 (Codex, riesgo): el recibo solo vuelve si el actor SIGUE viendo esa base (no basta el rol: un supervisor que perdió el
  -- subárbol, o una Gerencia que pasó a Supervisión, no recupera la respuesta guardada).
  if private.bases_carga_base_visible(p_actor, p_rol, (select b.supervisor_id from crm.bases_carga b where b.id = v_op.base_id)) is not true then
    raise exception 'Base no encontrada o fuera de tu ámbito' using errcode = 'P0002';
  end if;
  -- r2 (Codex P1): el recibo es inmutable y nombra leads; antes de repetirlo, cada uno se vuelve a juzgar con el actor de hoy:
  --   · carga: cada lead_id de sus filas → private.bases_carga_lead_ref (lo ve y sigue activo);
  --   · armado: los INCLUIDOS (posiciones sin motivo) → private.bases_carga_lead_ref (una base no se repite con un lead
  --     reasignado fuera o retirado); los EXCLUIDOS con un motivo de su estado (todos menos no_encontrado y repetido) → que el
  --     actor lo siga viendo (private.base_gestion_lead_visible; sin exigir activo: «inactivo» es ese estado).
  -- Si alguno ya no está a su alcance, no se repite la respuesta (P0002).
  if exists (select 1
               from pg_catalog.jsonb_array_elements(case when v_op.tipo = 'cargar_lote' then v_op.respuesta -> 'filas' else '[]'::jsonb end) x
              where x ? 'lead_id' and not private.bases_carga_lead_ref(p_actor, p_rol, (x ->> 'lead_id')::uuid))
     or exists (select 1
                  from pg_catalog.unnest(case when v_op.tipo = 'armar' then p_lead_ids end) with ordinality as u(id, pos)
                  left join lateral (select m.motivo
                                       from pg_catalog.jsonb_each(v_op.respuesta -> 'excluidos_por_motivo') as m(motivo, posiciones)
                                      where exists (select 1 from pg_catalog.jsonb_array_elements_text(m.posiciones) q(pos) where q.pos::bigint = u.pos)
                                      limit 1) e on true
                 where coalesce(e.motivo, '') not in ('no_encontrado', 'repetido')
                   and (case when e.motivo is null then private.bases_carga_lead_ref(p_actor, p_rol, u.id)
                             else (select private.base_gestion_lead_visible(p_actor, p_rol, l.vendedor_id, l.asignado_supervisor_id)
                                     from crm.leads l where l.id = u.id) end) is not true) then
    raise exception 'La respuesta guardada nombra leads que ya no están a tu alcance; repite la operación con otro identificador'
      using errcode = 'P0002';
  end if;
  return v_op.respuesta;
end;
$function$;

create function private.bases_carga_insertar_base(p_actor uuid, p_operacion_id uuid, p_nombre text, p_origen text,
                                                  p_supervisor_id uuid, p_archivo_nombre text)
returns uuid
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  v_id uuid;
  v_restriccion text;
begin
  if exists (select 1 from crm.bases_carga b
              where b.supervisor_id = p_supervisor_id and b.activo and pg_catalog.lower(b.nombre) = pg_catalog.lower(p_nombre)) then
    raise exception 'Ya hay una base viva con ese nombre en la bandeja de ese supervisor' using errcode = '23505';
  end if;
  begin
    insert into crm.bases_carga (nombre, origen, supervisor_id, creada_por, operacion_id, archivo_nombre)
    values (p_nombre, p_origen, p_supervisor_id, p_actor, p_operacion_id, p_archivo_nombre)
    returning id into v_id;
  exception when unique_violation then
    get stacked diagnostics v_restriccion = constraint_name;
    if v_restriccion = 'bases_carga_nombre_vivo_unico' then
      raise exception 'Ya hay una base viva con ese nombre en la bandeja de ese supervisor' using errcode = '23505';
    end if;
    raise exception 'Este identificador de operación ya se usó para otra base' using errcode = '23505';
  end;
  return v_id;
end;
$function$;

create function private.bases_carga_contacto_existente(p_telefono text, p_dni text)
returns table(lead_id uuid, motivo text, vendedor_id uuid, asignado_supervisor_id uuid, activo boolean, orden bigint)
language sql
stable
security invoker
set search_path = ''
as $function$
  -- E2 (hallazgo del F0): «existe CUALQUIER lead con ese teléfono o DNI», en cualquier estado. El verificador de la casa
  -- dice «libre» con retirados, descartados de < 24 h con motivo de 0 días o convertidos con otro teléfono. Devuelve TODOS
  -- (r1: el núcleo necesita saber si alguno está fuera del ámbito del actor), con su categoría y su orden de relevancia
  -- (1 = vivo → descartado → convertido → retirado); el teléfono llega ya normalizado. Sin agregados de conteo (censo).
  select l.id,
         case when not l.activo then 'retirado'
              when l.etapa = 'convertido' then 'convertido'
              when l.etapa = 'descartado' then 'descartado'
              when l.vendedor_id is null and l.asignado_supervisor_id is null then 'en_bolsa'
              else 'con_dueno' end,
         l.vendedor_id,
         l.asignado_supervisor_id,
         l.activo,
         pg_catalog.row_number() over (order by case when l.activo and l.etapa not in ('convertido', 'descartado') then 0
                                                    when l.activo and l.etapa = 'descartado' then 1
                                                    when l.activo then 2
                                                    else 3 end,
                                               l.creado_en desc, l.id)
    from crm.leads l
   where l.telefono = p_telefono or (p_dni is not null and l.dni = p_dni)
$function$;

create function private.bases_carga_fuera_de_ambito(p_actor uuid, p_rol text, p_telefono text, p_dni text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $function$
  -- r1/r2: UNA definición de «algún lead con ese teléfono o DNI está FUERA del ámbito del actor» (espejo de leads_select). La usan
  -- el veredicto de cada fila y el respaldo fila a fila del INSERT (r2, Codex riesgo: también al convertir un P0429).
  select coalesce(pg_catalog.bool_or(not private.base_gestion_lead_visible(p_actor, p_rol, x.vendedor_id, x.asignado_supervisor_id)), false)
    from private.bases_carga_contacto_existente(p_telefono, p_dni) x
$function$;

-- ── 3 · Núcleo: crear la base, cargar un lote, armar desde el CRM ──────────────────────────────────────────────────────
create function private.bases_carga_crear_core(p_actor uuid, p_operacion_id uuid, p_nombre text, p_origen text,
                                               p_supervisor_id uuid, p_archivo_nombre text)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  v_rol text := private.bases_carga_rol(p_actor);
  v_nombre text := pg_catalog.btrim(p_nombre);
  v_archivo text := nullif(pg_catalog.btrim(p_archivo_nombre), '');
  v_md5 text;
  v_prev jsonb;
  v_sup uuid;
  v_base uuid;
  v_resp jsonb;
begin
  v_md5 := pg_catalog.md5(pg_catalog.jsonb_build_object('tipo', 'crear', 'nombre', v_nombre, 'origen', p_origen,
                                                        'supervisor_id', p_supervisor_id, 'archivo_nombre', v_archivo)::text);
  v_prev := private.bases_carga_operacion_previa(p_actor, v_rol, p_operacion_id, 'crear', v_md5);
  if v_prev is not null then
    return v_prev;
  end if;
  if (pg_catalog.char_length(v_nombre) between 1 and 80) is not true then
    raise exception 'El nombre de la base debe tener entre 1 y 80 caracteres' using errcode = '22023';
  end if;
  if p_origen is distinct from 'archivo' then
    raise exception 'Por esta puerta se crea una base de origen archivo; la que se arma desde el CRM la crea armar_base_crm'
      using errcode = '22023';
  end if;
  if (pg_catalog.char_length(v_archivo) between 1 and 255) is not true then
    raise exception 'El nombre del archivo es obligatorio (1 a 255 caracteres)' using errcode = '22023';
  end if;
  v_sup := private.bases_carga_supervisor_destino(p_actor, v_rol, p_supervisor_id);
  v_base := private.bases_carga_insertar_base(p_actor, p_operacion_id, v_nombre, 'archivo', v_sup, v_archivo);
  v_resp := pg_catalog.jsonb_build_object('ok', true, 'operacion_id', p_operacion_id, 'base_id', v_base,
                                          'origen', 'archivo', 'supervisor_id', v_sup);
  insert into crm.base_carga_operaciones (actor, operacion_id, base_id, tipo, pedido_md5, respuesta)
  values (p_actor, p_operacion_id, v_base, 'crear', v_md5, v_resp);
  return v_resp;
end;
$function$;

create function private.bases_carga_cargar_lote_core(p_actor uuid, p_operacion_id uuid, p_base_id uuid, p_filas jsonb)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  v_rol text := private.bases_carga_rol(p_actor);
  v_max_base integer;
  v_max_lote integer;
  v_n integer;
  v_md5 text;
  v_prev jsonb;
  v_sup uuid;
  v_base crm.bases_carga%rowtype;
  e record;
  c record;
  v_fila integer;
  v_filas_vistas jsonb := '{}'::jsonb;
  v_vistos jsonb := '{}'::jsonb;
  v_nombre text;
  v_tel text;
  v_dni text;
  v_distrito text;
  v_nota text;
  v_capital text;
  v_moneda text;
  v_ver text;
  v_mot text;
  v_ref uuid;
  v_verjson jsonb;
  v_ex record;
  v_estado text;
  i integer := 0;
  a_fila integer[] := '{}';
  a_nombre text[] := '{}';
  a_tel text[] := '{}';
  a_dni text[] := '{}';
  a_distrito text[] := '{}';
  a_nota text[] := '{}';
  a_monto numeric[] := '{}';
  a_moneda text[] := '{}';
  a_ver text[] := '{}';
  a_mot text[] := '{}';
  a_ref uuid[] := '{}';
  a_id uuid[] := '{}';
  v_cargadas integer := 0;
  v_ya integer := 0;
  v_noc integer := 0;
  v_inv integer := 0;
  v_rep integer := 0;
  v_ins integer;
  v_resp jsonb;
begin
  select k.max_filas_base, k.max_filas_lote into v_max_base, v_max_lote from private.bases_carga_constantes() k;
  if p_base_id is null then
    raise exception 'La base es obligatoria' using errcode = '22023';
  end if;
  if p_filas is null or pg_catalog.jsonb_typeof(p_filas) is distinct from 'array' then
    raise exception 'Las filas llegan como una lista JSON' using errcode = '22023';
  end if;
  v_n := pg_catalog.jsonb_array_length(p_filas);
  if v_n < 1 or v_n > v_max_lote then
    raise exception 'Un lote trae entre 1 y % filas (este trae %)', v_max_lote, v_n using errcode = '22023';
  end if;
  v_md5 := pg_catalog.md5('cargar_lote|' || p_base_id::text || '|' || p_filas::text);
  v_prev := private.bases_carga_operacion_previa(p_actor, v_rol, p_operacion_id, 'cargar_lote', v_md5);
  if v_prev is not null then
    return v_prev;
  end if;

  -- La base: visible para el actor (sin delatar si existe), viva, de archivo, con su supervisor activo y con cupo.
  -- Se bloquea su fila: los lotes de una misma base van de a uno (totales y tope exactos). r1 (Codex, riesgo): NOWAIT — el
  -- segundo lote no consume sus 8 s esperando al primero: falla al instante con 55P03 y el front reintenta.
  select b.supervisor_id into v_sup from crm.bases_carga b where b.id = p_base_id;
  if not found or not private.bases_carga_base_visible(p_actor, v_rol, v_sup) then
    raise exception 'Base no encontrada o fuera de tu ámbito' using errcode = 'P0002';
  end if;
  begin
    select b.* into v_base from crm.bases_carga b where b.id = p_base_id for update nowait;
  exception when lock_not_available then
    raise exception 'Hay otra carga en curso de esta base; reintenta' using errcode = '55P03';
  end;
  if not v_base.activo then
    raise exception 'La base está retirada: no admite más filas' using errcode = '22023';
  end if;
  if v_base.origen <> 'archivo' then
    raise exception 'Solo una base de origen archivo recibe filas de un archivo' using errcode = '22023';
  end if;
  if private.es_destino_crm_activo(v_base.supervisor_id, array['supervisor']::text[]) is not true then
    raise exception 'El supervisor dueño de la base ya no está activo: no se le pueden cargar contactos' using errcode = '22023';
  end if;
  if v_base.filas_recibidas + v_n > v_max_base then
    raise exception 'Una base recibe hasta % filas: ya tiene % y este lote trae %', v_max_base, v_base.filas_recibidas, v_n
      using errcode = '22023';
  end if;

  -- 1 · Forma, validación y repetidas dentro del lote (la primera aparición gana).
  for e in select x.valor, x.pos from pg_catalog.jsonb_array_elements(p_filas) with ordinality as x(valor, pos) order by x.pos loop
    if pg_catalog.jsonb_typeof(e.valor) is distinct from 'object' or ((e.valor ->> 'fila') ~ '^[1-9][0-9]{0,6}$') is not true then
      raise exception 'Cada fila es un objeto con su número de fila (entero positivo); la posición % no lo es', e.pos
        using errcode = '22023';
    end if;
    v_fila := (e.valor ->> 'fila')::integer;
    if v_filas_vistas ? v_fila::text then
      raise exception 'El número de fila % se repite en el lote', v_fila using errcode = '22023';
    end if;
    v_filas_vistas := v_filas_vistas || pg_catalog.jsonb_build_object(v_fila::text, true);
    v_nombre := nullif(pg_catalog.btrim(e.valor ->> 'nombre'), '');
    v_tel := private.normalizar_telefono(nullif(pg_catalog.btrim(e.valor ->> 'telefono'), ''));
    v_dni := nullif(pg_catalog.btrim(e.valor ->> 'dni'), '');
    v_distrito := nullif(pg_catalog.btrim(e.valor ->> 'distrito'), '');
    v_nota := nullif(pg_catalog.btrim(e.valor ->> 'comentario'), '');
    v_capital := nullif(pg_catalog.btrim(e.valor ->> 'capital'), '');
    v_moneda := coalesce(pg_catalog.upper(nullif(pg_catalog.btrim(e.valor ->> 'moneda'), '')), 'PEN');
    v_ver := null;
    v_mot := null;
    if v_nombre is null then
      v_ver := 'invalida'; v_mot := 'nombre_vacio';
    elsif pg_catalog.char_length(v_nombre) > 200 then
      v_ver := 'invalida'; v_mot := 'nombre_largo';
    elsif (v_tel ~ '^\+519[0-9]{8}$') is not true then
      v_ver := 'invalida'; v_mot := 'telefono_invalido';
    elsif v_dni is not null and v_dni !~ '^[0-9]{8}$' then
      v_ver := 'invalida'; v_mot := 'dni_invalido';
    elsif v_capital is not null
          and (case when v_capital ~ '^[0-9]{1,10}(\.[0-9]{1,2})?$' then v_capital::numeric > 0 else false end) is not true then
      v_ver := 'invalida'; v_mot := 'capital_invalido';
    elsif v_moneda not in ('PEN', 'USD') then
      v_ver := 'invalida'; v_mot := 'moneda_invalida';
    elsif pg_catalog.char_length(v_distrito) > 120 then
      v_ver := 'invalida'; v_mot := 'distrito_largo';
    elsif pg_catalog.char_length(v_nota) > 1000 then
      v_ver := 'invalida'; v_mot := 'comentario_largo';
    elsif v_vistos ? ('t:' || v_tel) or (v_dni is not null and v_vistos ? ('d:' || v_dni)) then
      v_ver := 'repetida'; v_mot := 'en_archivo';
    end if;
    if v_ver is null then
      v_vistos := v_vistos || pg_catalog.jsonb_build_object('t:' || v_tel, true)
                  || case when v_dni is null then '{}'::jsonb else pg_catalog.jsonb_build_object('d:' || v_dni, true) end;
    end if;
    a_fila := a_fila || v_fila;
    a_nombre := a_nombre || v_nombre;
    a_tel := a_tel || v_tel;
    a_dni := a_dni || v_dni;
    a_distrito := a_distrito || v_distrito;
    a_nota := a_nota || v_nota;
    a_monto := a_monto || case when v_ver is null then v_capital::numeric end;
    a_moneda := a_moneda || v_moneda;
    a_ver := a_ver || v_ver;
    a_mot := a_mot || v_mot;
    a_ref := a_ref || null::uuid;
    a_id := a_id || null::uuid;
  end loop;

  -- (unnest de varios arreglos va SIN esquema: es sintaxis del FROM, no la función pg_catalog.unnest.)
  -- 2 · Candados en el orden de la casa, una vez por lote y ANTES de evaluar: documentos → personas → contactos.
  for c in select distinct x.dni from unnest(a_dni, a_ver) as x(dni, ver)
            where x.ver is null and x.dni is not null order by x.dni loop
    perform private.identidad_bloquear_documento('DNI', c.dni);
  end loop;
  for c in select y.dni from (select distinct x.dni, private.inversionista_por_documento('DNI', x.dni) as persona
                                from unnest(a_dni, a_ver) as x(dni, ver)
                               where x.ver is null and x.dni is not null) y
            where y.persona is not null order by y.persona, y.dni loop
    perform private.identidad_bloquear_persona('DNI', c.dni);
  end loop;
  perform private.bloquear_contactos_lead(
    array(select x.tel from unnest(a_tel, a_ver) as x(tel, ver) where x.ver is null),
    array(select x.dni from unnest(a_dni, a_ver) as x(dni, ver) where x.ver is null and x.dni is not null));

  -- 3 · Veredicto de cada fila candidata (bajo los candados).
  for i in 1 .. v_n loop
    if a_ver[i] is not null then
      continue;
    end if;
    v_ver := null; v_mot := null; v_ref := null;
    -- Ya cargada en un lote anterior de ESTA base (pertenencia VIVA).
    select bl.lead_id into v_ref
      from crm.base_carga_leads bl
     where bl.base_id = p_base_id and bl.activo
       and bl.lead_id in (select l.id from crm.leads l where l.telefono = a_tel[i] or (a_dni[i] is not null and l.dni = a_dni[i]))
     limit 1;
    if found then
      v_ver := 'repetida'; v_mot := 'en_base';
      -- r1 (Codex P1): la categoría se conserva (es su base); el id, solo si el actor ve ese lead y sigue activo.
      if not private.bases_carga_lead_ref(p_actor, v_rol, v_ref) then
        v_ref := null;
      end if;
    else
      -- La coincidencia más relevante, y si ALGUNA está fuera del ámbito del actor (private.bases_carga_fuera_de_ambito).
      select x.lead_id, x.motivo into v_ex
        from private.bases_carga_contacto_existente(a_tel[i], a_dni[i]) x
       order by x.orden
       limit 1;
      if private.bases_carga_fuera_de_ambito(p_actor, v_rol, a_tel[i], a_dni[i]) then
        -- r1 (decisión del PRIMARY sobre el P3 «consulta masiva»): con algún lead FUERA del ámbito del actor, solo «ya existía»,
        -- sin motivo ni id (ni retirado, convertido, en bolsa o descartado; ni No contactar de otro equipo).
        v_ver := 'ya_existia';
      else
        v_verjson := private.verificar_disponibilidad_lead_impl(a_tel[i], a_dni[i]);
        case v_verjson ->> 'estado'
          when 'no_contactar' then v_ver := 'no_contactar'; v_mot := 'no_insistir';
          when 'ya_es_cliente' then v_ver := 'ya_existia'; v_mot := 'cliente';
          when 'tomado' then v_ver := 'ya_existia'; v_mot := 'con_dueno';
          when 'en_bolsa' then v_ver := 'ya_existia'; v_mot := 'en_bolsa';
          when 'enfriamiento' then v_ver := 'ya_existia'; v_mot := 'descartado';
          when 'reutilizable' then v_ver := 'ya_existia'; v_mot := 'descartado';
          when 'error' then v_ver := 'invalida'; v_mot := 'telefono_invalido';
          when 'libre' then
            -- El envoltorio: el verificador dijo «libre», pero ¿existe ALGÚN lead con ese teléfono o DNI?
            if v_ex.lead_id is not null then
              v_ver := 'ya_existia'; v_mot := v_ex.motivo;
            else
              v_ver := 'cargada';
            end if;
          else
            raise exception 'Veredicto de disponibilidad desconocido' using errcode = 'P0001';
        end case;
        -- El lead que ya existía (en el ámbito del actor), solo si lo ve y sigue activo: private.bases_carga_lead_ref.
        if v_ver in ('ya_existia', 'no_contactar') and private.bases_carga_lead_ref(p_actor, v_rol, v_ex.lead_id) then
          v_ref := v_ex.lead_id;
        end if;
      end if;
    end if;
    a_ver[i] := v_ver;
    a_mot[i] := v_mot;
    a_ref[i] := v_ref;
    if v_ver = 'cargada' then
      a_id[i] := pg_catalog.gen_random_uuid();
    end if;
  end loop;

  -- 4 · Los contactos nacen dormidos (E7): descartados, motivo base_cargada, en la bandeja del supervisor de la base, sin
  -- analista, con el capital del archivo o sin él (E8). La válvula se enciende SOLO alrededor de este INSERT.
  if 'cargada' = any (a_ver) then
    perform pg_catalog.set_config('crm.op_bases_carga', 'on', true);
    begin
      insert into crm.leads (id, nombre_completo, telefono, dni, distrito, nota, origen, etapa, motivo_descarte,
                             monto_estimado, moneda, vendedor_id, asignado_supervisor_id, activo, creado_por, alta_manual)
      select x.id, x.nombre, x.tel, x.dni, x.distrito, x.nota, 'base_cargada', 'descartado', 'base_cargada',
             x.monto, x.moneda, null, v_base.supervisor_id, true, p_actor, false
        from unnest(a_id, a_nombre, a_tel, a_dni, a_distrito, a_nota, a_monto, a_moneda, a_ver)
             as x(id, nombre, tel, dni, distrito, nota, monto, moneda, ver)
       where x.ver = 'cargada';
      get diagnostics v_ins = row_count;
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate;
      -- r2 (Codex riesgo): lo transitorio aborta el lote entero, sin repetir (private.bases_carga_error_transitorio).
      if private.bases_carga_error_transitorio(v_estado) then
        raise exception using errcode = v_estado, message = pg_catalog.format('La carga se interrumpió (%s); reintenta', v_estado);
      end if;
      v_ins := null;  -- r1 (Codex, riesgo): la tanda chocó con un rechazo (una carrera); se repite fila a fila, abajo
    end;
    if v_ins is null then
      -- r1: cada fila en su subtransacción. Un rechazo de identidad de los disparadores (P0481 de la disponibilidad, P0409 del
      -- puente, P0429 del veto) se vuelve el veredicto de ESA fila, SIN su detail (puede nombrar analistas o leads de otro
      -- equipo); cualquier otra excepción aborta el lote con un mensaje sin datos (solo la fila y el código).
      for i in 1 .. v_n loop
        continue when a_ver[i] is distinct from 'cargada';
        begin
          insert into crm.leads (id, nombre_completo, telefono, dni, distrito, nota, origen, etapa, motivo_descarte,
                                 monto_estimado, moneda, vendedor_id, asignado_supervisor_id, activo, creado_por, alta_manual)
          values (a_id[i], a_nombre[i], a_tel[i], a_dni[i], a_distrito[i], a_nota[i], 'base_cargada', 'descartado', 'base_cargada',
                  a_monto[i], a_moneda[i], null, v_base.supervisor_id, true, p_actor, false);
        exception
          when sqlstate 'P0481' or sqlstate 'P0409' then
            a_ver[i] := 'ya_existia'; a_mot[i] := null; a_ref[i] := null; a_id[i] := null;
          when sqlstate 'P0429' then
            -- r2 (Codex riesgo): la misma regla del ámbito que el veredicto: con algún lead fuera del ámbito, solo «ya existía».
            a_ver[i] := case when private.bases_carga_fuera_de_ambito(p_actor, v_rol, a_tel[i], a_dni[i]) then 'ya_existia' else 'no_contactar' end;
            a_mot[i] := null; a_ref[i] := null; a_id[i] := null;
          when others then
            get stacked diagnostics v_estado = returned_sqlstate;
            if private.bases_carga_error_transitorio(v_estado) then
              raise exception using errcode = v_estado, message = pg_catalog.format('La carga se interrumpió (%s); reintenta', v_estado);
            end if;
            raise exception using errcode = v_estado, message = pg_catalog.format('No se pudo cargar la fila %s (%s)', a_fila[i], v_estado);
        end;
      end loop;
    end if;
    perform pg_catalog.set_config('crm.op_bases_carga', 'off', true);
    insert into crm.base_carga_leads (base_id, lead_id, procedencia, agregado_por)
    select p_base_id, x.id, 'archivo', p_actor
      from unnest(a_id, a_ver) as x(id, ver)
     where x.ver = 'cargada';
  end if;

  -- Conteos sin agregados (censo), después del INSERT (el respaldo fila a fila puede cambiar veredictos).
  for i in 1 .. v_n loop
    case a_ver[i]
      when 'cargada' then v_cargadas := v_cargadas + 1;
      when 'ya_existia' then v_ya := v_ya + 1;
      when 'no_contactar' then v_noc := v_noc + 1;
      when 'invalida' then v_inv := v_inv + 1;
      when 'repetida' then v_rep := v_rep + 1;
    end case;
  end loop;
  if v_ins is not null and v_ins is distinct from v_cargadas then
    raise exception 'La carga no insertó lo previsto' using errcode = 'P0001';
  end if;

  update crm.bases_carga
     set filas_recibidas = filas_recibidas + v_n, cargadas = cargadas + v_cargadas, ya_existian = ya_existian + v_ya,
         no_contactar = no_contactar + v_noc, invalidas = invalidas + v_inv, repetidas = repetidas + v_rep
   where id = p_base_id
  returning * into v_base;

  v_resp := pg_catalog.jsonb_build_object(
    'ok', true, 'operacion_id', p_operacion_id, 'base_id', p_base_id,
    'lote', pg_catalog.jsonb_build_object('filas', v_n, 'cargadas', v_cargadas, 'ya_existian', v_ya, 'no_contactar', v_noc,
                                          'invalidas', v_inv, 'repetidas', v_rep),
    'base', pg_catalog.jsonb_build_object('filas_recibidas', v_base.filas_recibidas, 'cargadas', v_base.cargadas,
                                          'ya_existian', v_base.ya_existian, 'no_contactar', v_base.no_contactar,
                                          'invalidas', v_base.invalidas, 'repetidas', v_base.repetidas),
    'filas', (select pg_catalog.jsonb_agg(pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
                       'fila', x.fila, 'veredicto', x.ver, 'motivo', x.mot, 'lead_id', x.ref)) order by x.pos)
                from unnest(a_fila, a_ver, a_mot, a_ref) with ordinality as x(fila, ver, mot, ref, pos)));
  insert into crm.base_carga_operaciones (actor, operacion_id, base_id, tipo, pedido_md5, respuesta)
  values (p_actor, p_operacion_id, p_base_id, 'cargar_lote', v_md5, v_resp);
  return v_resp;
end;
$function$;

create function private.bases_carga_armar_respuesta(p_compacta jsonb, p_lead_ids uuid[])
returns jsonb
language sql
immutable
security invoker
set search_path = ''
as $function$
  -- El recibo guarda las posiciones (1-based en p_lead_ids) de cada excluido por motivo (cabe en 64 KB con 2000 ids);
  -- la respuesta las expande con su lead_id. El replay trae el MISMO arreglo (mismo md5): misma respuesta.
  select p_compacta || pg_catalog.jsonb_build_object('excluidos_detalle', coalesce((
    select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('posicion', p.pos, 'lead_id', p_lead_ids[p.pos], 'motivo', m.motivo)
                                order by p.pos)
      from pg_catalog.jsonb_each(p_compacta -> 'excluidos_por_motivo') as m(motivo, posiciones)
      cross join lateral (select pg_catalog.jsonb_array_elements_text(m.posiciones)::integer as pos) p), '[]'::jsonb));
$function$;

create function private.bases_carga_armar_core(p_actor uuid, p_operacion_id uuid, p_nombre text, p_supervisor_id uuid,
                                               p_lead_ids uuid[])
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  v_rol text := private.bases_carga_rol(p_actor);
  v_nombre text := pg_catalog.btrim(p_nombre);
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_max integer;
  v_n integer := coalesce(pg_catalog.cardinality(p_lead_ids), 0);
  v_md5 text;
  v_prev jsonb;
  v_sup uuid;
  v_base uuid;
  a_id uuid[];
  a_pos integer[];
  a_mot text[];
  v_incluidos uuid[];
  v_insertados uuid[];
  v_por_motivo jsonb;
  v_n_ins integer;
  v_compacta jsonb;
  v_subarbol uuid[];
  v_bloqueados uuid[];
begin
  select k.max_leads_armar into v_max from private.bases_carga_constantes() k;
  -- r1 (Codex P2): solo un arreglo simple que empiece en 1 (con otro límite inferior, las posiciones de la respuesta y el md5
  -- del pedido no coincidirían con lo evaluado: excluido equivocado y replay distinto).
  if v_n > 0 and (pg_catalog.array_ndims(p_lead_ids) is distinct from 1 or pg_catalog.array_lower(p_lead_ids, 1) is distinct from 1) then
    raise exception 'La lista de leads debe ser un arreglo simple que empiece en la posición 1' using errcode = '22023';
  end if;
  v_md5 := pg_catalog.md5(pg_catalog.jsonb_build_object('tipo', 'armar', 'nombre', v_nombre, 'supervisor_id', p_supervisor_id,
                                                        'lead_ids', pg_catalog.to_jsonb(p_lead_ids))::text);
  v_prev := private.bases_carga_operacion_previa(p_actor, v_rol, p_operacion_id, 'armar', v_md5, p_lead_ids);
  if v_prev is not null then
    return private.bases_carga_armar_respuesta(v_prev, p_lead_ids);
  end if;
  if (pg_catalog.char_length(v_nombre) between 1 and 80) is not true then
    raise exception 'El nombre de la base debe tener entre 1 y 80 caracteres' using errcode = '22023';
  end if;
  if v_n < 1 or v_n > v_max then
    raise exception 'Una base armada desde el CRM lleva entre 1 y % leads (llegaron %)', v_max, v_n using errcode = '22023';
  end if;
  if pg_catalog.array_position(p_lead_ids, null) is not null then
    raise exception 'La lista de leads no admite vacíos' using errcode = '22023';
  end if;
  v_sup := private.bases_carga_supervisor_destino(p_actor, v_rol, p_supervisor_id);
  -- r1 (auditor P3): el ámbito es el del SUPERVISOR dueño (su subárbol), también si arma Gerencia.
  v_subarbol := array(select private.bases_carga_subarbol(v_sup));
  -- r1/r2 (Codex P1): candado FOR UPDATE SKIP LOCKED, en orden de id, de los leads del ámbito; se GUARDA el conjunto
  -- efectivamente bloqueado y SOLO ese se evalúa e inserta. Reactivar, marcar No contactar, reasignar y el intento B6 toman la
  -- fila del lead: lo bloqueado no cambia hasta el commit. Lo que otro proceso tiene tomado no se espera (sin interbloqueos con
  -- escritores masivos en otro orden): sale «ocupado» (reintenta). Un lead que entra al ámbito DESPUÉS de bloquear no está en el
  -- conjunto: tampoco entra (ocupado o no_encontrado según se vea ahora). No se escribe el lead.
  select coalesce(pg_catalog.array_agg(b.id order by b.id), '{}') into v_bloqueados
    from (select l.id from crm.leads l
           where l.id = any (p_lead_ids)
             and private.bases_carga_en_subarbol(v_subarbol, l.vendedor_id, l.asignado_supervisor_id)
           order by l.id
             for update of l skip locked) b;

  -- E12: solo descartados ELEGIBLES del ámbito del dueño; lo de fuera de su ámbito o inexistente, igual: no_encontrado.
  -- La primera aparición de cada id se evalúa; las siguientes son «repetido».
  with entrada as (
    select u.id, u.pos, (u.pos = min(u.pos) over (partition by u.id)) as primera
      from pg_catalog.unnest(p_lead_ids) with ordinality as u(id, pos)
  )
  select pg_catalog.array_agg(en.id order by en.pos), pg_catalog.array_agg(en.pos::integer order by en.pos),
         pg_catalog.array_agg(
           case
             when not en.primera then 'repetido'
             -- r2: lo que NO se bloqueó no se evalúa: fuera del ámbito (o inexistente) → no_encontrado; si no, otro lo tiene → ocupado.
             when not (en.id = any (v_bloqueados)) then
               case when l.id is not null and private.bases_carga_en_subarbol(v_subarbol, l.vendedor_id, l.asignado_supervisor_id)
                    then 'ocupado' else 'no_encontrado' end
             when not l.activo then 'inactivo'
             when l.etapa <> 'descartado' then 'no_descartado'
             when l.no_contactar then 'no_contactar'
             when l.motivo_descarte = 'datos_invalidos' then 'datos_invalidos'
             when l.enfriado_hasta is not null and l.enfriado_hasta > v_hoy then 'en_descanso'
             when exists (select 1 from crm.base_carga_leads bl where bl.lead_id = l.id and bl.activo) then 'en_otra_base'
             when private.base_gestion_en_gestion_hasta(l.id) is not null then 'en_gestion'
           end order by en.pos)
    into a_id, a_pos, a_mot
    from entrada en
    left join crm.leads l on l.id = en.id;

  v_incluidos := array(select x.id from unnest(a_id, a_mot) as x(id, mot) where x.mot is null order by x.id);
  v_base := private.bases_carga_insertar_base(p_actor, p_operacion_id, v_nombre, 'crm', v_sup, null);
  -- Pertenencia SIN tocar el lead (E13). En orden de id: dos armados concurrentes no se esperan en ciclo; si otro se llevó
  -- un lead entre la evaluación y aquí, el índice único de la base viva lo deja fuera (en_otra_base).
  with ins as (
    insert into crm.base_carga_leads (base_id, lead_id, procedencia, agregado_por)
    select v_base, x.id, 'crm', p_actor from pg_catalog.unnest(v_incluidos) as x(id) order by x.id
    on conflict (lead_id) where activo do nothing
    returning lead_id
  )
  select coalesce(pg_catalog.array_agg(ins.lead_id), '{}') into v_insertados from ins;
  v_n_ins := pg_catalog.cardinality(v_insertados);
  for i in 1 .. v_n loop
    if a_mot[i] is null and not (a_id[i] = any (v_insertados)) then
      a_mot[i] := 'en_otra_base';
    end if;
  end loop;

  select coalesce(pg_catalog.jsonb_object_agg(g.mot, g.posiciones), '{}'::jsonb) into v_por_motivo
    from (select x.mot, pg_catalog.jsonb_agg(x.pos order by x.pos) as posiciones
            from unnest(a_pos, a_mot) as x(pos, mot) where x.mot is not null group by x.mot) g;
  -- Sin ningún elegible no queda una base vacía ocupando el nombre: se deshace todo y el detalle dice por qué.
  if v_n_ins = 0 then
    raise exception 'Ningún lead de la lista es elegible: no se crea la base'
      using errcode = '22023', detail = pg_catalog.jsonb_build_object('excluidos_por_motivo', v_por_motivo)::text;
  end if;

  update crm.bases_carga
     set filas_recibidas = v_n, cargadas = v_n_ins,
         no_contactar = coalesce(pg_catalog.jsonb_array_length(v_por_motivo -> 'no_contactar'), 0),
         repetidas = coalesce(pg_catalog.jsonb_array_length(v_por_motivo -> 'repetido'), 0)
   where id = v_base;

  v_compacta := pg_catalog.jsonb_build_object('ok', true, 'operacion_id', p_operacion_id, 'base_id', v_base, 'origen', 'crm',
                                              'supervisor_id', v_sup, 'recibidos', v_n, 'incluidos', v_n_ins,
                                              'excluidos', v_n - v_n_ins, 'excluidos_por_motivo', v_por_motivo);
  insert into crm.base_carga_operaciones (actor, operacion_id, base_id, tipo, pedido_md5, respuesta)
  values (p_actor, p_operacion_id, v_base, 'armar', v_md5, v_compacta);
  return private.bases_carga_armar_respuesta(v_compacta, p_lead_ids);
end;
$function$;

-- ── 4 · Las tres funciones del alta que reconocen al dormido (texto vivo con UN cambio cada una) ────────────────────────
create or replace function private.leads_before_insert()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'crm', 'public'
as $function$
declare
  v_priv boolean := coalesce(current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  -- Tambien aplica a importaciones y mantenimiento: no crear nuevos Otro.
  -- B7: base_cargada solo con la valvula de la carga de bases (trg_leads_000_base_cargada_solo_puerta).
  if new.origen is null or new.origen not in ('referido','landing','formulario','oficina','web','campania','whatsapp','base_cargada') then
    raise exception using errcode = '22023', message = 'Selecciona un canal concreto: Landing, Formulario, Referido o Walking';
  end if;
  if not v_priv then
    -- B8: el contacto de una base cargada nace DORMIDO (descartado, motivo base_cargada) solo bajo la válvula de la carga
    -- (private.bases_carga_nace_dormido, una sola definición). Cualquier otra alta sigue sin poder nacer terminal.
    if new.etapa not in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
       and not private.bases_carga_nace_dormido(new.origen, new.etapa, new.motivo_descarte, new.activo) then
      raise exception 'Un lead nuevo no puede nacer en estado terminal';
    end if;
    new.perfil_id := null;
    new.contrato_id := null;
    new.convertido_en := null;
  end if;
  return new;
end;
$function$;

create or replace function private.trg_leads_disponibilidad_atomica()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
 set lock_timeout to '5s'
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_disponibilidad jsonb;
  v_cambio_identidad boolean;
  v_dias integer;
  v_disponible_desde timestamptz;
  v_descartado_por text;
  v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  if tg_op = 'UPDATE' then
    if new.telefono is distinct from old.telefono then
      new.telefono := private.normalizar_telefono(new.telefono);
      if new.telefono is null or new.telefono !~ '^\+519[0-9]{8}$' then
        raise exception using errcode = '22023', message = 'Telefono invalido';
      end if;
    end if;

    if new.dni is distinct from old.dni then
      new.dni := nullif(pg_catalog.btrim(new.dni), '');
      if new.dni is not null and new.dni !~ '^[0-9]{8}$' then
        raise exception using errcode = '22023', message = 'DNI invalido';
      end if;
    end if;

    v_cambio_identidad := new.telefono is distinct from old.telefono
      or new.dni is distinct from old.dni;

    perform private.bloquear_contactos_lead(
      array[old.telefono, new.telefono],
      array[old.dni, new.dni]
    );

    -- F2.b (b5) [E3-6]: la corrección de documento de Gerencia (RPC definer bajo válvula Y con su
    -- GUC propia crm.correccion_documento) cambia SOLO el DNI de un lead que conserva su persona; los terceros (otra identidad,
    -- otro cliente del Portal, otro lead vivo) ya los comprobó la RPC bajo sus locks. Ningún
    -- otro escritor bajo válvula cambia el DNI; fuera de esta forma exacta nada cambia.
    if v_priv and coalesce(pg_catalog.current_setting('crm.correccion_documento', true) = 'on', false)
       and private.resolver_en_puertas_bajo_candado()
       and new.dni is distinct from old.dni and new.telefono is not distinct from old.telefono
       and new.no_contactar = old.no_contactar and new.etapa = old.etapa and new.activo = old.activo
       and new.motivo_descarte is not distinct from old.motivo_descarte
       and old.inversionista_id is not null and new.inversionista_id = old.inversionista_id then
      return new;
    end if;
    if not v_cambio_identidad or v_actor is null then
      return new;
    end if;

    v_rol := private.rol_crm(v_actor);
    if v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
      raise exception using errcode = '42501', message = 'Acceso CRM revocado';
    end if;

    -- Excluir OLD al validar el destino es correcto para un lead operativo,
    -- pero no debe permitir «mover» un No contactar o un enfriamiento y dejar
    -- libre la identidad anterior. Ambos vetos propios congelan teléfono y DNI
    -- mientras sigan vigentes; levantarlos es una operación separada y auditable.
    if old.no_contactar = true then
      raise exception using
        errcode = 'P0481',
        message = 'Contacto no disponible',
        detail = pg_catalog.jsonb_build_object('estado', 'no_contactar')::text;
    end if;

    if old.etapa = 'descartado'
       and old.descartado_en is not null
       and old.motivo_descarte is not null then
      select
        ep.dias,
        old.descartado_en + pg_catalog.make_interval(days => ep.dias),
        p.nombre_completo
      into v_dias, v_disponible_desde, v_descartado_por
      from crm.enfriamiento_politica ep
      left join public.perfiles p on p.id = old.descartado_por
      where ep.motivo = old.motivo_descarte;

      if coalesce(v_dias, 0) > 0
         and v_disponible_desde > pg_catalog.now() then
        raise exception using
          errcode = 'P0481',
          message = 'Contacto no disponible',
          detail = pg_catalog.jsonb_build_object(
            'estado', 'enfriamiento',
            'motivo_descarte', old.motivo_descarte,
            'disponible_desde', v_disponible_desde,
            'descartado_por', v_descartado_por
          )::text;
      end if;
    end if;

    v_disponibilidad := private.verificar_disponibilidad_lead_impl(
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

  new.telefono := private.normalizar_telefono(new.telefono);
  new.dni := nullif(pg_catalog.btrim(new.dni), '');

  if new.telefono is null or new.telefono !~ '^\+519[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'Telefono invalido';
  end if;
  if new.dni is not null and new.dni !~ '^[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'DNI invalido';
  end if;

  perform private.bloquear_contactos_lead(array[new.telefono], array[new.dni]);

  -- Un escritor interno sin sesion humana se serializa, pero conserva su
  -- contrato especializado (por ejemplo crm-importar-leads con service_role).
  if v_actor is null then
    return new;
  end if;

  v_rol := private.rol_crm(v_actor);
  if v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  -- La compatibilidad temporal es solo para el alta que ya hacía el bundle
  -- anterior. No abre una vía para fabricar leads terminales o inactivos.
  -- B8: única excepción, el contacto de una base cargada que nace DORMIDO bajo la válvula de la carga
  -- (private.bases_carga_nace_dormido). Activo siempre, y el veredicto de abajo debe ser «libre» igual.
  if new.activo is distinct from true
     or (new.etapa not in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
         and not private.bases_carga_nace_dormido(new.origen, new.etapa, new.motivo_descarte, new.activo)) then
    raise exception using errcode = '22023', message = 'Un lead debe nacer activo y en etapa operativa';
  end if;

  v_disponibilidad := private.verificar_disponibilidad_lead_impl(new.telefono, new.dni);
  if v_disponibilidad ->> 'estado' is distinct from 'libre' then
    raise exception using
      errcode = 'P0481',
      message = 'Contacto no disponible',
      detail = v_disponibilidad::text;
  end if;

  return new;
end;
$function$;

create or replace function private.trg_leads_sla_versionado()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'pg_catalog'
as $function$
declare
  v_en timestamptz;
  v_p crm.sla_politicas%rowtype;
  v_maximo integer;
  v_n integer;
  v_motivo text;
begin
  v_en:=case when tg_op='INSERT' then new.sla_global_iniciado_en else statement_timestamp() end;
  perform set_config('crm.sla_writer','on',true);

  -- B8: el contacto de una base cargada que nace DORMIDO no abre ciclo (no «llegó»: no hay primera gestión ni primer
  -- contacto que medir y crm.metricas_sla_fn lo contaría fuera de objetivo). Su primer ciclo nace al reactivarlo.
  if (tg_op='INSERT' and not private.bases_carga_nace_dormido(new.origen,new.etapa,new.motivo_descarte,new.activo))
     or (tg_op='UPDATE' and new.ciclo_actual is distinct from old.ciclo_actual) then
    select p.* into v_p from crm.sla_politicas p
    where p.id=private.sla_politica_vigente(new.sla_global_iniciado_en);
    if not found then raise exception 'No existe politica SLA para el ciclo'; end if;
    insert into crm.lead_sla_ciclos(
      lead_id,ciclo_n,politica_id,iniciado_en,primera_gestion_limite_en,primer_contacto_limite_en
    ) values(new.id,new.ciclo_actual,v_p.id,new.sla_global_iniciado_en,
      new.sla_global_iniciado_en+v_p.primera_gestion_minutos*interval '1 minute',
      new.sla_global_iniciado_en+v_p.primer_contacto_minutos*interval '1 minute');
  end if;

  if tg_op='UPDATE' and (
    new.ciclo_actual is distinct from old.ciclo_actual or new.etapa is distinct from old.etapa
    or (old.activo and not new.activo)
  ) then
    v_motivo:=case
      when new.ciclo_actual is distinct from old.ciclo_actual then 'reapertura'
      when old.activo and not new.activo then 'desactivacion'
      when new.etapa in ('convertido','descartado') then 'cierre_terminal'
      else 'cambio_etapa' end;
    update crm.lead_sla_etapas set finalizado_en=v_en,motivo_cierre=v_motivo
    where lead_id=new.id and finalizado_en is null;
  end if;

  if new.activo and new.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
    and (tg_op='INSERT' or new.ciclo_actual is distinct from old.ciclo_actual
      or new.etapa is distinct from old.etapa or (not old.activo and new.activo)) then
    select p.* into v_p
    from crm.sla_politicas p
    where p.id=private.sla_politica_vigente(v_en);
    if not found then raise exception 'No existe politica SLA vigente'; end if;
    select pe.maximo_minutos into v_maximo
    from crm.sla_politica_etapas pe
    where pe.politica_id=v_p.id and pe.etapa=new.etapa;
    if not found then raise exception 'No existe SLA para etapa %',new.etapa; end if;
    select coalesce(max(e.episodio_n),0)+1 into v_n from crm.lead_sla_etapas e
    where e.lead_id=new.id and e.ciclo_n=new.ciclo_actual;
    insert into crm.lead_sla_etapas(
      lead_id,ciclo_n,episodio_n,etapa,politica_id,iniciado_en,limite_en
    ) values(new.id,new.ciclo_actual,v_n,new.etapa,v_p.id,v_en,
      v_en+v_maximo*interval '1 minute');
  end if;
  perform set_config('crm.sla_writer','off',true);
  return new;
end;
$function$;

-- r1 (auditor P3): el enfriamiento base_cargada nunca es 0 días (Gerencia puede editar los días por la API).
alter table crm.enfriamiento_politica
  add constraint enfriamiento_politica_base_cargada_dias_positivos check (motivo <> 'base_cargada' or dias > 0);

create trigger trg_leads_zz_sello_descarte_base_cargada before insert on crm.leads
  for each row when (new.origen = 'base_cargada') execute function private.trg_leads_sello_descarte_base_cargada();

-- ── 5 · Puerta de entrada (DEFINER: las tablas no tienen grants; validan y delegan, el actor sale de la sesión) ─────────
create function crm.crear_base(p_operacion_id uuid, p_nombre text, p_origen text, p_supervisor_id uuid default null,
                               p_archivo_nombre text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  return private.bases_carga_crear_core((select auth.uid()), p_operacion_id, p_nombre, p_origen, p_supervisor_id, p_archivo_nombre);
end;
$function$;

create function crm.cargar_base_lote(p_operacion_id uuid, p_base_id uuid, p_filas jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $function$
begin
  return private.bases_carga_cargar_lote_core((select auth.uid()), p_operacion_id, p_base_id, p_filas);
end;
$function$;

create function crm.armar_base_crm(p_operacion_id uuid, p_nombre text, p_supervisor_id uuid default null,
                                   p_lead_ids uuid[] default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $function$
begin
  return private.bases_carga_armar_core((select auth.uid()), p_operacion_id, p_nombre, p_supervisor_id, p_lead_ids);
end;
$function$;

-- ── 6 · Dueños y permisos: EXECUTE de las puertas solo para authenticated; el núcleo, para nadie ───────────────────────
alter function private.bases_carga_constantes() owner to postgres;
alter function private.bases_carga_nace_dormido(text, text, text, boolean) owner to postgres;
alter function private.trg_leads_sello_descarte_base_cargada() owner to postgres;
alter function private.bases_carga_rol(uuid) owner to postgres;
alter function private.bases_carga_supervisor_destino(uuid, text, uuid) owner to postgres;
alter function private.bases_carga_base_visible(uuid, text, uuid) owner to postgres;
alter function private.bases_carga_subarbol(uuid) owner to postgres;
alter function private.bases_carga_en_subarbol(uuid[], uuid, uuid) owner to postgres;
alter function private.bases_carga_lead_ref(uuid, text, uuid) owner to postgres;
alter function private.bases_carga_operacion_previa(uuid, text, uuid, text, text, uuid[]) owner to postgres;
alter function private.bases_carga_fuera_de_ambito(uuid, text, text, text) owner to postgres;
alter function private.bases_carga_error_transitorio(text) owner to postgres;
alter function private.bases_carga_insertar_base(uuid, uuid, text, text, uuid, text) owner to postgres;
alter function private.bases_carga_contacto_existente(text, text) owner to postgres;
alter function private.bases_carga_crear_core(uuid, uuid, text, text, uuid, text) owner to postgres;
alter function private.bases_carga_cargar_lote_core(uuid, uuid, uuid, jsonb) owner to postgres;
alter function private.bases_carga_armar_respuesta(jsonb, uuid[]) owner to postgres;
alter function private.bases_carga_armar_core(uuid, uuid, text, uuid, uuid[]) owner to postgres;
alter function crm.crear_base(uuid, text, text, uuid, text) owner to postgres;
alter function crm.cargar_base_lote(uuid, uuid, jsonb) owner to postgres;
alter function crm.armar_base_crm(uuid, text, uuid, uuid[]) owner to postgres;

revoke all on function private.bases_carga_constantes() from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_nace_dormido(text, text, text, boolean) from public, anon, authenticated, service_role;
revoke all on function private.trg_leads_sello_descarte_base_cargada() from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_rol(uuid) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_supervisor_destino(uuid, text, uuid) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_base_visible(uuid, text, uuid) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_subarbol(uuid) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_en_subarbol(uuid[], uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_lead_ref(uuid, text, uuid) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_operacion_previa(uuid, text, uuid, text, text, uuid[]) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_fuera_de_ambito(uuid, text, text, text) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_error_transitorio(text) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_insertar_base(uuid, uuid, text, text, uuid, text) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_contacto_existente(text, text) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_crear_core(uuid, uuid, text, text, uuid, text) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_cargar_lote_core(uuid, uuid, uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_armar_respuesta(jsonb, uuid[]) from public, anon, authenticated, service_role;
revoke all on function private.bases_carga_armar_core(uuid, uuid, text, uuid, uuid[]) from public, anon, authenticated, service_role;
revoke all on function crm.crear_base(uuid, text, text, uuid, text) from public, anon, authenticated, service_role;
revoke all on function crm.cargar_base_lote(uuid, uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function crm.armar_base_crm(uuid, text, uuid, uuid[]) from public, anon, authenticated, service_role;
grant execute on function crm.crear_base(uuid, text, text, uuid, text) to authenticated;
grant execute on function crm.cargar_base_lote(uuid, uuid, jsonb) to authenticated;
grant execute on function crm.armar_base_crm(uuid, text, uuid, uuid[]) to authenticated;
-- leads_before_insert, trg_leads_disponibilidad_atomica y trg_leads_sla_versionado conservan su ACL ({postgres=X/postgres}).

-- ── 7 · Comentarios ────────────────────────────────────────────────────────────────────────────────────────────────────
comment on function crm.crear_base(uuid, text, text, uuid, text) is
'Bases cargadas (B8, 04/10/2026): crea la base de un archivo (origen archivo). Supervisión: la base es suya (otro supervisor → 42501). Gerencia: elige un supervisor activo (E11; sin él → 22023). Otros roles → 42501. Nombre 1–80, único entre las bases vivas del supervisor (23505); nombre de archivo obligatorio. Idempotente por (actor, p_operacion_id): el replay devuelve la misma respuesta; el mismo id con otro pedido → 22023. Devuelve {ok, operacion_id, base_id, origen, supervisor_id}. DEFINER, search_path vacío, EXECUTE solo authenticated; delega en private.bases_carga_crear_core.';
comment on function crm.cargar_base_lote(uuid, uuid, jsonb) is
'Bases cargadas (B8, 04/10/2026): carga UN lote del archivo en una base de origen archivo (visible para el actor; si no → P0002). p_filas: lista de objetos {fila (entero > 0, único en el lote), nombre, telefono, dni?, distrito?, comentario?, capital?, moneda? PEN|USD}; máximo private.bases_carga_constantes().max_filas_lote filas por lote y 5000 por base (E5). Veredicto por fila: cargada (nace descartada, motivo base_cargada, en la bandeja del supervisor de la base, sin analista; E7) · ya_existia (cliente, con_dueno, en_bolsa, descartado, convertido, retirado; lead_id solo si el actor lo ve) · no_contactar · invalida (motivo) · repetida (en_archivo, en_base). Nunca un duplicado (E2). Idempotente por (actor, p_operacion_id). Devuelve {ok, operacion_id, base_id, lote{conteos}, base{totales}, filas[{fila, veredicto, motivo?, lead_id?}]} sin datos personales. DEFINER, search_path vacío, lock_timeout 5 s, EXECUTE solo authenticated.';
comment on function crm.armar_base_crm(uuid, text, uuid, uuid[]) is
'Bases cargadas (B8, 04/10/2026; r2): arma una base (origen crm) con hasta 2000 leads existentes, solo los descartados ELEGIBLES (E12) del ámbito del SUPERVISOR DUEÑO —su subárbol—: el propio supervisor, o el que elige Gerencia (E11); Gerencia NO arma con leads fuera de ese subárbol. Bloquea FOR UPDATE SKIP LOCKED los leads del ámbito y evalúa solo los bloqueados. Excluidos con motivo: no_encontrado (inexistente o fuera del ámbito), ocupado (otro proceso lo tiene tomado: reintenta), inactivo, no_descartado, no_contactar, datos_invalidos, en_descanso, en_otra_base, en_gestion (seguimiento activo B6), repetido. NO toca el lead (E13). Idempotente por (actor, p_operacion_id). Sin ningún elegible no crea la base (22023, detail con los motivos). Devuelve {ok, operacion_id, base_id, origen, supervisor_id, recibidos, incluidos, excluidos, excluidos_por_motivo{motivo: [posiciones 1-based]}, excluidos_detalle[{posicion, lead_id, motivo}]}. DEFINER, search_path vacío, lock_timeout 5 s, EXECUTE solo authenticated.';
comment on function private.bases_carga_constantes() is
'Bases cargadas (B8): topes en una sola definición: 5000 filas por base (E5), filas por lote (medido frente al statement_timeout de 8 s de authenticated y a los candados por fila) y 2000 leads por base armada desde el CRM.';
comment on function private.bases_carga_nace_dormido(text, text, text, boolean) is
'Bases cargadas (B8): la ÚNICA definición de «contacto de base cargada que nace dormido»: válvula de transacción crm.op_bases_carga = on (solo el núcleo del lote la enciende, alrededor de su INSERT) + origen base_cargada + etapa descartado + motivo base_cargada + activo. La usan leads_before_insert, trg_leads_disponibilidad_atomica, trg_leads_sla_versionado y trg_leads_sello_descarte_base_cargada. INVOKER, sin EXECUTE para la API.';
comment on function private.trg_leads_sello_descarte_base_cargada() is
'Bases cargadas (B8): disparador BEFORE INSERT (después de trg_leads_zz_sello_descarte, sellado por huella, que pone descartado_en NULL): al contacto que nace dormido le pone descartado_en = momento de la carga y descartado_por = el actor. Con la fecha, el enfriamiento base_cargada (30 días) impide el alta duplicada del mismo teléfono o DNI y la base para gestión cuenta sus días. La fecha no la elige nadie (ni la puerta). DEFINER, search_path vacío, sin EXECUTE para la API.';
comment on function private.bases_carga_rol(uuid) is
'Bases cargadas (B8): rol del actor resuelto en el servidor (private.rol_crm); solo supervisor o gerencia, si no 42501.';
comment on function private.bases_carga_supervisor_destino(uuid, text, uuid) is
'Bases cargadas (B8): supervisor dueño de una base nueva. Supervisión: él mismo (otro → 42501). Gerencia: el que elige, activo y supervisor (E11; sin él o inválido → 22023).';
comment on function private.bases_carga_base_visible(uuid, text, uuid) is
'Bases cargadas (B8): espejo de la policy crm.bases_carga_select (B7) para las puertas DEFINER: Gerencia todas; Supervisión las del subárbol. Si cambia la policy, cambiar aquí.';
comment on function private.bases_carga_operacion_previa(uuid, text, uuid, text, text, uuid[]) is
'Bases cargadas (B8): idempotencia de las puertas. Toma el candado de la operación (actor + id) y devuelve el recibo previo si el pedido es el mismo (mismo tipo y md5), el actor sigue viendo esa base (r1) y CADA lead que el recibo nombra sigue a su alcance según private.bases_carga_lead_ref (r2; si no, P0002); otro pedido con el mismo id → 22023; sin recibo → NULL.';
comment on function private.bases_carga_fuera_de_ambito(uuid, text, text, text) is
'Bases cargadas (B8 r1/r2): UNA definición de «algún lead con ese teléfono o DNI está fuera del ámbito del actor» (espejo de leads_select). Con true, la fila solo dice ya_existia, sin motivo ni id: en el veredicto y en el respaldo fila a fila del INSERT.';
comment on function private.bases_carga_error_transitorio(text) is
'Bases cargadas (B8 r2): errores que abortan el lote entero sin repetir fila a fila (40P01, 55P03, 57014, 40001, 25P02 y las clases 53, 54, 57 y 58).';
comment on function private.bases_carga_subarbol(uuid) is
'Bases cargadas (B8 r1): el subárbol de un supervisor (él y todo crm.equipo debajo), para el ámbito del supervisor dueño de una base aunque la arme Gerencia. Espejo de la rama supervisor de private.vendedor_ids_visibles (que solo enumera el del usuario de la sesión): si cambia, cambiar aquí.';
comment on function private.bases_carga_en_subarbol(uuid[], uuid, uuid) is
'Bases cargadas (B8 r1): UNA definición de «el lead está en el ámbito del supervisor dueño» (espejo de leads_select sin Gerencia): su analista en el subárbol o, sin analista, la bandeja de un supervisor del subárbol. La usan el candado y la evaluación de armar_base_crm.';
comment on function private.bases_carga_lead_ref(uuid, text, uuid) is
'Bases cargadas (B8 r1): UNA definición de «este lead_id se puede devolver o guardar en un recibo»: el actor lo ve (private.base_gestion_lead_visible, espejo de leads_select) y sigue activo. Toda referencia de las respuestas pasa por aquí.';
comment on function private.bases_carga_insertar_base(uuid, uuid, text, text, uuid, text) is
'Bases cargadas (B8): inserta la base con mensajes claros: nombre repetido entre las vivas del supervisor → 23505; id de operación ya usado por otra base → 23505.';
comment on function private.bases_carga_contacto_existente(text, text) is
'Bases cargadas (B8): envoltorio de identidad de E2 — «existe CUALQUIER lead con ese teléfono (normalizado) o DNI», en cualquier estado (vivo, descartado, convertido, retirado), que el verificador de la casa da por «libre» en varios casos (F0). Devuelve el más relevante con su categoría (con_dueno, en_bolsa, descartado, convertido, retirado). Sin agregados (censo).';
comment on function private.bases_carga_crear_core(uuid, uuid, text, text, uuid, text) is
'Bases cargadas (B8): núcleo de crm.crear_base (rol y supervisor resueltos en el servidor, recibo crear).';
comment on function private.bases_carga_cargar_lote_core(uuid, uuid, uuid, jsonb) is
'Bases cargadas (B8): núcleo de crm.cargar_base_lote. Orden: idempotencia → base (visible, viva, archivo, supervisor activo, cupo; FOR UPDATE) → validación y repetidas del lote → candados de la casa una vez (documentos → personas → contactos) → veredicto por fila (verificar_disponibilidad_lead_impl + bases_carga_contacto_existente) → INSERT de los dormidos con la válvula crm.op_bases_carga encendida solo alrededor → pertenencia (procedencia archivo) → totales → recibo cargar_lote. Sin count( ni sum(1) (censo).';
comment on function private.bases_carga_armar_respuesta(jsonb, uuid[]) is
'Bases cargadas (B8): expande el recibo compacto de armar_base_crm (posiciones por motivo) con el lead_id de cada excluido; la misma función sirve la primera respuesta y el replay.';
comment on function private.bases_carga_armar_core(uuid, uuid, text, uuid, uuid[]) is
'Bases cargadas (B8): núcleo de crm.armar_base_crm: ámbito del supervisor dueño, candado FOR UPDATE SKIP LOCKED en orden de id y evaluación E12 SOLO de lo bloqueado (r2; lo demás, no_encontrado u ocupado), base origen crm, pertenencia procedencia crm en orden de id con ON CONFLICT sobre la base viva (sin tocar el lead, E13), totales y recibo armar. Sin count( ni sum(1) (censo).';
comment on function private.leads_before_insert() is
'Alta de un lead (BEFORE INSERT): exige un canal concreto (sin nuevos Otro; base_cargada solo con la válvula de la carga de bases, B7 04/10/2026, la reserva vive en private.trg_leads_base_cargada_solo_puerta) y, sin crm.op_privilegiada, impide nacer en estado terminal —salvo el contacto de base cargada que nace dormido (B8, private.bases_carga_nace_dormido)— y enlazar perfil, contrato o conversión. DEFINER, search_path crm, public.';
comment on function private.trg_leads_disponibilidad_atomica() is
'Serializa contactos y preserva vetos entre la RPC humana, importadores privilegiados y cambios de identidad. B8 (04/10/2026): un alta con usuario debe nacer activa y en etapa operativa, salvo el contacto de base cargada que nace dormido (private.bases_carga_nace_dormido); su veredicto de disponibilidad debe ser «libre» igual.';
comment on function private.trg_leads_sla_versionado() is
'SLA versionado del lead (AFTER INSERT OR UPDATE): abre el ciclo al nacer y al reabrir, y los episodios por etapa operativa. B8 (04/10/2026): el contacto de base cargada que nace dormido NO abre ciclo (no llegó: crm.metricas_sla_fn lo contaría fuera de objetivo); su primer ciclo nace al reactivarlo.';
comment on constraint enfriamiento_politica_base_cargada_dias_positivos on crm.enfriamiento_politica is
'Bases cargadas (B8 r1, auditor-rls P3): el enfriamiento base_cargada es siempre de más de 0 días. Con 0, el alta de un teléfono recién cargado vería «libre» 24 h (rama de carencia del verificador) y crearía un duplicado (E2). Gerencia puede cambiar los días por la API (policy enfriamiento_update): este CHECK la frena.';
comment on trigger trg_leads_zz_sello_descarte_base_cargada on crm.leads is
'Bases cargadas (B8): el contacto que nace dormido recibe descartado_en (momento de la carga) y descartado_por (el actor). Corre después de trg_leads_zz_sello_descarte (orden por nombre). Ver private.trg_leads_sello_descarte_base_cargada.';

-- ── 8 · Postflight (SOLO catálogo) ─────────────────────────────────────────────────────────────────────────────────────
create temp table _b8_censo_despues on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;
do $postflight$
declare
  v_mal text;
begin
  -- Cuerpos ensayados (md5(prosrc) medido al generar la migración), seguridad, search_path, dueño, ACL y comentario.
  with esperado(firma, cuerpo, definer, config, acl) as (values
    ('private.bases_carga_constantes()', '9647dae922a69d736ced45b389efde30', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_nace_dormido(text,text,text,boolean)', 'c3d86ac0c12b8825265d3e6bbcf00476', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.trg_leads_sello_descarte_base_cargada()', 'd18817405684613c864d78ee715f9ba0', true, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_rol(uuid)', '19068e47cd9ee9ce4221ed6f14c7b5b6', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_supervisor_destino(uuid,text,uuid)', 'be55a5b5e6b108e8dce3a8605a7824ee', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_base_visible(uuid,text,uuid)', '5df98eec6ef65f67a08f82e4b65aefa3', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_operacion_previa(uuid,text,uuid,text,text,uuid[])', '5a320d0571c157a5ac2f9c2f7544b580', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_fuera_de_ambito(uuid,text,text,text)', 'b1ab127f662cc86bc1b0ddb7ee4f71c6', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_error_transitorio(text)', 'd4b1c198e17278cf28e419ef473abe8f', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_subarbol(uuid)', 'bc2d3bac84de2d3df63b72d4775e14df', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_en_subarbol(uuid[],uuid,uuid)', '47422c703b13959c7ce1f3155e89a2a3', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_lead_ref(uuid,text,uuid)', 'e38dbdd23c2e2010714c9c60569eb78c', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_insertar_base(uuid,uuid,text,text,uuid,text)', '00bb892274894267e6f40df11fe7ad5c', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_contacto_existente(text,text)', 'cf6489ee72122a33fd9c1da9b5e9446c', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_crear_core(uuid,uuid,text,text,uuid,text)', 'aa80b7a59ca2535925e0dac9024e0fd5', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_cargar_lote_core(uuid,uuid,uuid,jsonb)', 'b30f606a1fd63d5cfeae85c6b85e8339', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_armar_respuesta(jsonb,uuid[])', '958177f87a53d58358a51ed1460fd5c5', false, 'search_path=""', '{postgres=X/postgres}'),
    ('private.bases_carga_armar_core(uuid,uuid,text,uuid,uuid[])', '93bef0869efe677f63e088d01e14ac36', false, 'search_path=""', '{postgres=X/postgres}'),
    ('crm.crear_base(uuid,text,text,uuid,text)', 'e0e1b810a1cfac286819590c9914dd04', true, 'search_path=""', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.cargar_base_lote(uuid,uuid,jsonb)', 'fa281b7cc2ee056bec71a4dc58c3c703', true, 'search_path="",lock_timeout=5s', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.armar_base_crm(uuid,text,uuid,uuid[])', 'ff50e6a5a32a015043f99d1f4cafbd07', true, 'search_path="",lock_timeout=5s', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.leads_before_insert()', '090f7fc40a1cda7cb3b89e377a745e62', true, 'search_path=crm, public', '{postgres=X/postgres}'),
    ('private.trg_leads_disponibilidad_atomica()', '5543c41f89dd49b8b267b7b274b12814', true, 'search_path="",lock_timeout=5s', '{postgres=X/postgres}'),
    ('private.trg_leads_sla_versionado()', '6b99a7c2b3b6d68cbf0c8147f86f7298', true, 'search_path=pg_catalog', '{postgres=X/postgres}'))
  select string_agg(e.firma, ', ' order by e.firma) into v_mal
    from esperado e
    left join pg_proc p on p.oid = to_regprocedure(e.firma)
   where (p.oid is not null and md5(p.prosrc) = e.cuerpo and p.prosecdef = e.definer
          and array_to_string(p.proconfig, ',') = e.config and p.proowner = 'postgres'::regrole
          and p.proacl is not null and p.proacl::text = e.acl
          and obj_description(p.oid, 'pg_proc') is not null) is not true;
  if v_mal is not null then
    raise exception 'POSTFLIGHT B8: funciones que no quedaron como se ensayaron: %', v_mal;
  end if;

  if (
    -- Permisos efectivos: las puertas solo para authenticated; el núcleo, para nadie de la API.
    not exists (select 1 from unnest(array['crm.crear_base(uuid,text,text,uuid,text)', 'crm.cargar_base_lote(uuid,uuid,jsonb)',
                                           'crm.armar_base_crm(uuid,text,uuid,uuid[])']) f(firma)
                 where has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE')
                    or not has_function_privilege('authenticated', f.firma, 'EXECUTE'))
    and not exists (select 1 from pg_proc p cross join unnest(array['anon', 'authenticated', 'service_role']) r(rol)
                     where p.pronamespace = 'private'::regnamespace
                       and (p.proname like 'bases\_carga\_%' or p.proname = 'trg_leads_sello_descarte_base_cargada')
                       and has_function_privilege(r.rol, p.oid, 'EXECUTE'))
    -- Una sola sobrecarga de cada puerta.
    and (select count(*) from pg_proc p where p.pronamespace = 'crm'::regnamespace
          and p.proname in ('crear_base', 'cargar_base_lote', 'armar_base_crm')) = 3
    -- El disparador nuevo: BEFORE INSERT por fila con su WHEN, habilitado, con su función y comentario.
    and (select count(*) = 1 from pg_trigger t
          where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_zz_sello_descarte_base_cargada'
            and t.tgfoid = to_regprocedure('private.trg_leads_sello_descarte_base_cargada()')
            and t.tgenabled = 'O' and t.tgtype = 7 and t.tgattr = ''::int2vector
            and pg_get_triggerdef(t.oid) = 'CREATE TRIGGER trg_leads_zz_sello_descarte_base_cargada BEFORE INSERT ON crm.leads FOR EACH ROW WHEN ((new.origen = ''base_cargada''::text)) EXECUTE FUNCTION private.trg_leads_sello_descarte_base_cargada()'
            and obj_description(t.oid, 'pg_trigger') like 'Bases cargadas (B8)%')
    -- El sello del descarte sigue con la huella que sella private.assert_gestion_diaria_resultado.
    and (select md5(pg_get_functiondef(p.oid)) = '150d7ae56bb2094733f7620a1362c29e' from pg_proc p where p.oid = to_regprocedure('private.trg_leads_zz_sello_descarte()'))
    -- r1: el CHECK del enfriamiento base_cargada, exacto, validado y comentado.
    and (select pg_get_constraintdef(c.oid) = 'CHECK (((motivo <> ''base_cargada''::text) OR (dias > 0)))' and c.convalidated
                and obj_description(c.oid, 'pg_constraint') like 'Bases cargadas (B8 r1%'
           from pg_constraint c where c.conrelid = 'crm.enfriamiento_politica'::regclass and c.conname = 'enfriamiento_politica_base_cargada_dias_positivos')
    -- La válvula la leen solo el sello de B7 y la definición de «nace dormido»; la ENCIENDE solo el núcleo del lote.
    and not exists (select 1 from pg_proc p where p.prosrc ~ 'op_bases_carga'
                     and p.oid not in (to_regprocedure('private.trg_leads_base_cargada_solo_puerta()'),
                                       to_regprocedure('private.bases_carga_nace_dormido(text,text,text,boolean)'),
                                       to_regprocedure('private.bases_carga_cargar_lote_core(uuid,uuid,uuid,jsonb)')))
    -- Censo: nada nuevo entra y es el de la foto.
    and not exists (select 1 from pg_temp._b8_censo_despues c where c.objeto not in (select a.objeto from pg_temp._b8_censo_antes a))
    and (select count(*) from pg_temp._b8_censo_antes) = (select count(*) from pg_temp._b8_censo_despues)
  ) is not true then
    raise exception 'POSTFLIGHT B8: permisos, sobrecargas, el disparador nuevo, el sello del descarte, la valvula o el censo no quedaron como se ensayaron';
  end if;
  raise notice 'B8 CATALOGO OK: 3 puertas (EXECUTE solo authenticated), nucleo privado sin EXECUTE, 3 funciones del alta con su cambio, disparador de la fecha del descarte, CHECK del enfriamiento base_cargada, sello del descarte intacto, censo igual. COMPORTAMIENTO NO PROBADO en esta migracion.';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;

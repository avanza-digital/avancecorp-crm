-- Registrador fail-closed del índice para el paso 3a «SLA por filas», kit v4 (20261017054425_crm_sla_ventana_por_filas, 20261017054426_crm_sla_avisos_por_filas, 20261017054427_crm_sla_cola_por_filas).
-- Ejecutar DESPUÉS de cada migración y de su verificar.sql, por la misma vía (`db query --linked --file`). También cierra un
-- «commit hecho, registro pendiente»: registra sin volver a ejecutar el DDL.
-- Vuelve a comprobar las piezas VIVAS (md5 de pg_get_functiondef y de prosrc + metadatos) y que el productor, el helper de
-- clientes y sla_leads_operativos siguen siendo los ensayados; registra SOLO las versiones cuyo estado está vivo: M1 si la
-- serie está en M1, M1+M2 en M2 y las tres en M3, con el texto literal de cada archivo. NUNCA borra ni cambia filas.
-- v3 (Codex P1): valida la TRANSICIÓN del historial, no solo el estado vivo. Reproduce las filas de la serie en orden de
-- versión (tienen que ser una secuencia válida) y se niega si:
--   * el historial va por delante de la serie viva (una reversa ejecutada sin registrar: registrarla antes);
--   * la aplicación vigente de una mN registrada es de OTRA generación (versión distinta de la de este registrador);
--   * una versión por registrar ya está ocupada (un evento anterior: reaplicar con versiones nuevas) o no es posterior
--     a todo evento de la serie.
-- Idempotente solo para el MISMO evento: misma versión, mismo texto y vigente en el historial. El informe sale en la última
-- fila (`db query` no muestra los avisos).
begin;
set local lock_timeout = '10s';
set local search_path = '';
set local quote_all_identifiers = off;
do $registrar$
declare
  v_tabla jsonb := $tabla${"private.sla_operacion_ambito(uuid[],boolean)": {"M1": ["e843f6cd039b92a5fcd1e629d6ad4138", "b75fb4c86471cba36687c15986bd60dc", "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|record|ba5d2ec895f334e53417ef36cffebb2b"]}, "private.sla_operacion_autorizada_filas(uuid[])": {"M1": ["5aa191534358b819d8b8f0254f91c471", "250863962d4a0a5adb564d2e7c8a39cb", "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|record|3094558e14db3ba8d8fa684e5ce99ca5"]}, "private.sla_operacion_autorizada(uuid[],boolean)": {"ANTES": ["a5bd718f2f288565ecb510f6ba1e8634", "a5fd870bf432dc907f5849a61a5fb9a8", "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|jsonb|8dd4b7845c20f10e7f9cf1aa84c58ca9"], "M1": ["4cdaa81a538473ea322ca5e4835652d4", "7d8c87935730be5f3b43559dc05e977a", "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|jsonb|8dd4b7845c20f10e7f9cf1aa84c58ca9"]}, "private.assert_sla_nucleo()": {"ANTES": ["6bc541b2e3ba1549b4b4ed419c22d455", "dfdbedf7e2a2b0f6790be6b307a88a85", "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e"], "M1": ["a938047d5c98aa009984a9e836b2fc9d", "7f5a08dde907b343b8562b6024eba110", "postgres|{postgres=X/postgres}|search_path=\"\",quote_all_identifiers=off|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e"]}, "private.assert_sla_avisos()": {"ANTES": ["9b9edc86c3a55d89367b6d64203d38dc", "0eeb9efef832ddfbb5acbf48a812f9b1", "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e"], "M1": ["fb433efc037f09647481744a5f36380c", "7c6007603919f41406649edffa63429d", "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e"], "M2": ["1cbce7c3cdd9d39e61e9c26af29a9f7e", "d307e5acaa84517072d8f65db882c1f3", "postgres|{postgres=X/postgres}|search_path=\"\",quote_all_identifiers=off|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e"]}, "crm.avisos_sla_resumen_v2_fn()": {"ANTES": ["e9ce617ab0cc33bc5614ef69e877cc71", "576b1aa6e4d3eddd947d6bbdb1c99f40", "postgres|{postgres=X/postgres,authenticated=X/postgres}|search_path=\"\"|true|s|u|jsonb|502d0d8cb0124b164f936cf6ef6dba63"], "M2": ["82a7cabdae761ea7b3707db9f9c62452", "3387f3aff90b1e47e05bcddea14a91e3", "postgres|{postgres=X/postgres,authenticated=X/postgres}|search_path=\"\"|true|s|u|jsonb|0003d4f1991eab3f3d0105e52a9a9f2a"]}, "crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)": {"ANTES": ["1ec76074c9b5650cb8bac4c79440eccb", "828989da281bc8c32fab812542e86ba9", "postgres|{postgres=X/postgres,authenticated=X/postgres}|search_path=\"\"|true|s|u|jsonb|4fc30931ad31e222dc19423d89befb12"], "M3": ["6096aa636688f01677327c5504ffaa8b", "34b5abf032aac26cf5453f6e85f3d370", "postgres|{postgres=X/postgres,authenticated=X/postgres}|search_path=\"\"|true|s|u|jsonb|3f313ac52acf379e299c15a75344f9b6"]}, "private.assert_cola_v3()": {"ANTES": ["162fe9e053c8b57f8b501dadbe2afca7", "97d9d1b96c9b9a882a6518b890d082c0", "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|text|dd5dee9c51f0f514a8f4c05582216dd2"], "M3": ["5b000de8271604d1c6780dcc2425e90f", "862b765b58b1cb7725b375b587733b81", "postgres|{postgres=X/postgres}|search_path=\"\",quote_all_identifiers=off|true|s|u|text|dd5dee9c51f0f514a8f4c05582216dd2"]}}$tabla$::jsonb;
  v_estados jsonb := $estados${"ANTES": {"private.sla_operacion_ambito(uuid[],boolean)": "AUSENTE", "private.sla_operacion_autorizada_filas(uuid[])": "AUSENTE", "private.sla_operacion_autorizada(uuid[],boolean)": "ANTES", "private.assert_sla_nucleo()": "ANTES", "private.assert_sla_avisos()": "ANTES", "crm.avisos_sla_resumen_v2_fn()": "ANTES", "crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)": "ANTES", "private.assert_cola_v3()": "ANTES"}, "M1": {"private.sla_operacion_ambito(uuid[],boolean)": "M1", "private.sla_operacion_autorizada_filas(uuid[])": "M1", "private.sla_operacion_autorizada(uuid[],boolean)": "M1", "private.assert_sla_nucleo()": "M1", "private.assert_sla_avisos()": "M1", "crm.avisos_sla_resumen_v2_fn()": "ANTES", "crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)": "ANTES", "private.assert_cola_v3()": "ANTES"}, "M2": {"private.sla_operacion_ambito(uuid[],boolean)": "M1", "private.sla_operacion_autorizada_filas(uuid[])": "M1", "private.sla_operacion_autorizada(uuid[],boolean)": "M1", "private.assert_sla_nucleo()": "M1", "private.assert_sla_avisos()": "M2", "crm.avisos_sla_resumen_v2_fn()": "M2", "crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)": "ANTES", "private.assert_cola_v3()": "ANTES"}, "M3": {"private.sla_operacion_ambito(uuid[],boolean)": "M1", "private.sla_operacion_autorizada_filas(uuid[])": "M1", "private.sla_operacion_autorizada(uuid[],boolean)": "M1", "private.assert_sla_nucleo()": "M1", "private.assert_sla_avisos()": "M2", "crm.avisos_sla_resumen_v2_fn()": "M2", "crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)": "M3", "private.assert_cola_v3()": "M3"}}$estados$::jsonb;
  v_exigidas jsonb := $exigidas${"private.sla_operacion_leads(uuid[],boolean,uuid[],timestamp with time zone)": ["0abdf640b5f4f10ab2e85b6bd2494522", "e47f610fb4cde0741f2a22c3e2e7ee2c"], "private.tareas_clientes_autorizadas(uuid,uuid[],text,boolean,timestamp with time zone,timestamp with time zone)": ["234ee27f745ef1817be0e0cbdd2b2e25", "8d02b260a0aa0bc50536afdc82c32ba3"], "private.sla_leads_operativos()": ["8d478d783e4c591662388ddf7405058a", "fd8f5800b253b137e82e666b9a89ab0a"]}$exigidas$::jsonb;
  v_exigidas_ok boolean := true;
  v_firma text; v_versiones jsonb; v_oid oid; v_md5_def text; v_md5_src text; v_meta text; v_et text; v_e text;
  v_actual jsonb := '{}'; v_serie text; v_informe text := '';
  v_h_tabla boolean; v_h_estado integer := 0; v_h_ok boolean := true; v_h_max text; v_h_lista text := '';
  v_h_apl text[] := array[null, null, null]::text[]; v_h_version text; v_h_nombre text; v_h_n integer;
  v_h_max_global numeric; v_n_ajenas bigint;
  v_n integer; v_version text; v_nombre text; v_texto text; v_existente text[]; v_nom_ex text;
  v_nuevas integer := 0; v_presentes integer := 0;
  v_archivos jsonb := pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_array('20261017054425', 'crm_sla_ventana_por_filas', $migracion_20261017054425$-- SLA paso 3a · M1: la ventana operativa POR FILAS y una sola regla de autorización (plan «foto del SLA», Fase 3). v2.
-- Por qué: private.sla_operacion_autorizada devolvía UN jsonb con todas las filas visibles (gerencia: 3.869 leads, 15,3 MB);
-- jsonb_agg necesita varias veces ese tamaño y work_mem no lo limita (causa acreditada de la caída del 13/10). Esta
-- migración NO cambia ninguna salida: crea la ventana por filas y deja la autorizada como envoltorio del mismo jsonb.
--   * private.sla_operacion_ambito(uuid[],boolean) — NUEVA. La autorización de siempre (auth.uid, rol, lector global,
--     visibles; 42501 y después 22023), en un solo sitio para los DOS modos. INVOKER, sin EXECUTE para nadie de la API.
--   * private.sla_operacion_autorizada_filas(uuid[]) — NUEVA. Una fila por lead autorizado + una fila de cabecera que
--     existe siempre (también con cero leads). DEFINER (es la autoridad), sin EXECUTE para nadie de la API.
--   * private.sla_operacion_autorizada(uuid[],boolean) — envoltorio: con false/NULL conserva la salida temprana (sin
--     control, política ni núcleo operativo); con true, jsonb_agg sobre _filas y el objeto final en UN jsonb_build_object
--     (componerlo con «cabecera || {filas}» subía 30–70 MiB el pico de sus consumidores). MISMO jsonb byte a byte.
--   * private.assert_sla_nucleo(): cadena autorizada → {ámbito, _filas} → núcleo; EXISTEN todas las firmas obligatorias y
--     la autoridad no tiene sobrecargas; «auth.» (sin distinguir mayúsculas) solo en el ámbito; DEFINER = {autorizada,
--     _filas}; dueño postgres; y SELLOS md5 del ámbito, _filas y el envoltorio (quote_all_identifiers fijado en el guardián).
--   * private.assert_sla_avisos(): la autorizada consume _filas y _filas el núcleo.
--   Excepción a la decisión 4 AUTORIZADA por Miguel el 16/10/2026 a las 23:55 (tocar los 3 guardianes del SLA).
-- Evidencia y cifras (equivalencia byte a byte, memoria, temporales, mutantes): supabase/scripts/sla-por-filas/LEEME.md.
-- Protegida por: el historial (se niega si su versión ya está en el índice), huellas vivas (md5 de pg_get_functiondef y de
-- prosrc), metadatos y atributos de todo lo que toca o exige, el md5 de cada DDL ensayado y los 3 guardianes del SLA dentro
-- de la transacción. Se niega a aplicarse dos veces. No toca public, tablas, policies, datos ni pantallas.
-- Antes:   autorizada prosrc a5fd870bf432dc907f5849a61a5fb9a8 · familia SLA 62 · 1adaf6c5708637fd916705cc090a4218
-- Después: autorizada prosrc 7d8c87935730be5f3b43559dc05e977a · ámbito b75fb4c86471cba36687c15986bd60dc · _filas 250863962d4a0a5adb564d2e7c8a39cb · familia SLA 64 · 1a632cfd48a2cc1602646a8fb0fb5285
-- REVERTIR: supabase/scripts/sla-por-filas/reversa-m1.sql como MIGRACIÓN NUEVA (y registrar-reversa-m1.sql), solo con M2
-- y M3 ya revertidas; repone los cuerpos anteriores byte a byte y borra solo las 2 funciones nuevas si nadie las usa.
begin;
set local lock_timeout = '5s';
set local search_path = '';
set local quote_all_identifiers = off;
do $m1$
declare
  v_oid oid; v_firma text; v_esp jsonb; v_def text; v_md5_def text; v_md5_src text; v_meta text; v_extra text; v_ok text;
  v_ya boolean;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm_sla_por_filas'));
  -- Historial (Codex P1): si ESTA versión ya está en el índice de migraciones, no se vuelve a aplicar. Una reaplicación
  -- tras reversas registradas va con versiones NUEVAS; «commit hecho, registro pendiente» se cierra con
  -- registrar-indice.sql, sin volver a ejecutar el DDL. En una base sin índice (banco), no aplica.
  if pg_catalog.to_regclass('supabase_migrations.schema_migrations') is not null then
    execute 'select exists (select 1 from supabase_migrations.schema_migrations m where m.version = $1)' into v_ya using '20261017054425';
    if v_ya then
      raise exception 'PREFLIGHT M1: la versión 20261017054425 ya está en supabase_migrations.schema_migrations; no se aplica otra vez (una reaplicación tras reversas registradas va con versiones nuevas)';
    end if;
  end if;
  if pg_catalog.to_regprocedure('private.sla_operacion_ambito(uuid[],boolean)') is not null
     or pg_catalog.to_regprocedure('private.sla_operacion_autorizada_filas(uuid[])') is not null then
    raise exception 'PREFLIGHT M1: ya aplicada (o a medias): existe private.sla_operacion_ambito o private.sla_operacion_autorizada_filas; no se aplica dos veces';
  end if;
  for v_firma, v_esp in select e.key, e.value from pg_catalog.jsonb_each($esperado_preflight_m1${
 "private.sla_operacion_autorizada(uuid[],boolean)": {
  "def": "a5bd718f2f288565ecb510f6ba1e8634",
  "src": "a5fd870bf432dc907f5849a61a5fb9a8",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|jsonb|8dd4b7845c20f10e7f9cf1aa84c58ca9",
  "extra": "plpgsql|false|false|100|0|-|false|p_lead_ids uuid[], p_incluir_operacion boolean|jsonb"
 },
 "private.assert_sla_nucleo()": {
  "def": "6bc541b2e3ba1549b4b4ed419c22d455",
  "src": "dfdbedf7e2a2b0f6790be6b307a88a85",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e",
  "extra": "plpgsql|false|false|100|0|-|false||text"
 },
 "private.assert_sla_avisos()": {
  "def": "9b9edc86c3a55d89367b6d64203d38dc",
  "src": "0eeb9efef832ddfbb5acbf48a812f9b1",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e",
  "extra": "plpgsql|false|false|100|0|-|false||text"
 },
 "crm.avisos_sla_resumen_v2_fn()": {
  "def": "e9ce617ab0cc33bc5614ef69e877cc71",
  "src": "576b1aa6e4d3eddd947d6bbdb1c99f40",
  "meta": "postgres|{postgres=X/postgres,authenticated=X/postgres}|search_path=\"\"|true|s|u|jsonb|502d0d8cb0124b164f936cf6ef6dba63",
  "extra": "plpgsql|false|false|100|0|-|false||jsonb"
 },
 "crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)": {
  "def": "1ec76074c9b5650cb8bac4c79440eccb",
  "src": "828989da281bc8c32fab812542e86ba9",
  "meta": "postgres|{postgres=X/postgres,authenticated=X/postgres}|search_path=\"\"|true|s|u|jsonb|4fc30931ad31e222dc19423d89befb12",
  "extra": "plpgsql|false|false|100|0|-|false|p_limite integer DEFAULT 50, p_senal text DEFAULT 'todas'::text, p_etapa text DEFAULT NULL::text, p_analista_id uuid DEFAULT NULL::uuid, p_cursor jsonb DEFAULT NULL::jsonb|jsonb"
 },
 "private.assert_cola_v3()": {
  "def": "162fe9e053c8b57f8b501dadbe2afca7",
  "src": "97d9d1b96c9b9a882a6518b890d082c0",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|text|dd5dee9c51f0f514a8f4c05582216dd2",
  "extra": "plpgsql|false|false|100|0|-|false||text"
 },
 "private.sla_operacion_leads(uuid[],boolean,uuid[],timestamp with time zone)": {
  "def": "0abdf640b5f4f10ab2e85b6bd2494522",
  "src": "e47f610fb4cde0741f2a22c3e2e7ee2c",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|record|928c35d75cc268f2319658ee77878148",
  "extra": "plpgsql|false|false|100|1000|-|true|p_lead_ids uuid[], p_global boolean, p_visibles uuid[], p_ahora timestamp with time zone|TABLE(lead_id uuid, estado jsonb, accion_atencion jsonb, accion_supervision jsonb, senales jsonb, presentacion jsonb)"
 },
 "private.tareas_clientes_autorizadas(uuid,uuid[],text,boolean,timestamp with time zone,timestamp with time zone)": {
  "def": "234ee27f745ef1817be0e0cbdd2b2e25",
  "src": "8d02b260a0aa0bc50536afdc82c32ba3",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|record|0ca7eed9b41e7884ae26930b1e633c75",
  "extra": "plpgsql|false|false|100|1000|-|true|p_uid uuid, p_visibles uuid[], p_rol text, p_global boolean, p_ahora timestamp with time zone, p_fin_dia timestamp with time zone|TABLE(tarea_id uuid, perfil_id uuid, inversionista_id uuid, nombre text, responsable_id uuid, vence_en timestamp with time zone, bucket text)"
 },
 "private.sla_leads_operativos()": {
  "def": "8d478d783e4c591662388ddf7405058a",
  "src": "fd8f5800b253b137e82e666b9a89ab0a",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|uuid[]|130901f18423506211fa55f95ef1e834",
  "extra": "sql|false|false|100|0|-|false||uuid[]"
 }
}$esperado_preflight_m1$::jsonb) e loop
    v_oid := pg_catalog.to_regprocedure(v_firma);
    if v_oid is null then
      raise exception 'PREFLIGHT M1: no existe %', v_firma;
    end if;
    select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)), pg_catalog.md5(p.prosrc), pg_catalog.concat_ws('|', pg_catalog.pg_get_userbyid(p.proowner), p.proacl::text, pg_catalog.array_to_string(p.proconfig, ','),
         p.prosecdef::text, p.provolatile::text, p.proparallel::text, p.prorettype::pg_catalog.regtype::text,
         pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), ''))), (select pg_catalog.concat_ws('|', l.lanname, p.proisstrict::text, p.proleakproof::text, p.procost::text, p.prorows::text,
         p.prosupport::text, p.proretset::text, pg_catalog.pg_get_function_arguments(p.oid), pg_catalog.pg_get_function_result(p.oid))
         from pg_catalog.pg_language l where l.oid = p.prolang)
      into v_md5_def, v_md5_src, v_meta, v_extra from pg_catalog.pg_proc p where p.oid = v_oid;
    if v_md5_def is distinct from v_esp->>'def' or v_md5_src is distinct from v_esp->>'src' then
      raise exception 'PREFLIGHT M1: % no es la versión revisada (md5 def % / prosrc %; esperado % / %)', v_firma, v_md5_def, v_md5_src, v_esp->>'def', v_esp->>'src';
    end if;
    if v_meta is distinct from v_esp->>'meta' then
      raise exception 'PREFLIGHT M1: dueño, ACL, configuración, DEFINER, volatilidad o comentario de % distintos (%)', v_firma, v_meta;
    end if;
    if v_extra is distinct from v_esp->>'extra' then
      raise exception 'PREFLIGHT M1: otro atributo de % distinto (lenguaje, strict, leakproof, coste, filas, soporte, argumentos o resultado): %', v_firma, v_extra;
    end if;
  end loop;
  -- 1. Ayudante de autoridad (nuevo).
  v_def := $ddl_m1_ambito$CREATE OR REPLACE FUNCTION private.sla_operacion_ambito(p_lead_ids uuid[], p_incluir_operacion boolean)
 RETURNS TABLE(actor uuid, rol text, es_global boolean, visibles uuid[])
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_uid uuid:=(select auth.uid()); v_rol text; v_global boolean;
begin
  -- Autoridad ÚNICA de la ventana SLA para sus dos modos (paso 3a, 17/10/2026). Mismo orden de
  -- comprobaciones que tenía private.sla_operacion_autorizada: primero 42501, después 22023.
  -- Devuelve exactamente una fila (o lanza). es_global ya es el «global efectivo» (gerencia,
  -- coordinador o lector global).
  v_rol:=private.rol_crm(v_uid);
  v_global:=private.es_lector_global();
  if v_uid is null or (v_rol is null and not coalesce(v_global,false)) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  if p_incluir_operacion is null or array_position(p_lead_ids,null) is not null then
    raise exception 'Entrada SLA invalida' using errcode='22023';
  end if;
  actor:=v_uid;
  rol:=v_rol;
  es_global:=(v_rol in ('gerencia','coordinador')) or coalesce(v_global,false);
  visibles:=array(select x from private.vendedor_ids_visibles(v_uid) x order by x);
  return next;
end;
$function$
$ddl_m1_ambito$;
  if pg_catalog.md5(v_def) is distinct from 'e843f6cd039b92a5fcd1e629d6ad4138' then
    raise exception 'PREFLIGHT M1: el DDL de el ayudante de autoridad no es el ensayado (md5 esperado e843f6cd039b92a5fcd1e629d6ad4138)';
  end if;
  execute v_def;
  -- 2. Ventana por filas (nueva).
  v_def := $ddl_m1_filas$CREATE OR REPLACE FUNCTION private.sla_operacion_autorizada_filas(p_lead_ids uuid[])
 RETURNS TABLE(es_cabecera boolean, lead_id uuid, estado jsonb, senales jsonb, accion_pendiente jsonb, lead jsonb, accion_revision jsonb, accion jsonb, cabecera jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_amb record; v_ahora timestamptz:=statement_timestamp();
  v_control crm.sla_operacion_control%rowtype; v_politica uuid; v_version integer;
  v_prox timestamptz; v_p timestamptz;
begin
  -- Ventana operativa autorizada POR FILAS (paso 3a, 17/10/2026). Una fila por lead autorizado
  -- (es_cabecera = false) con los seis campos de cada elemento de «filas» del envoltorio, y SIEMPRE
  -- una última fila de cabecera (es_cabecera = true, datos NULL), también con cero leads. La cabecera
  -- es el objeto del envoltorio SIN «filas»; proximo_cambio_en es el mínimo sobre TODAS las filas de
  -- esta llamada. Un solo instante (v_ahora) para el núcleo, la política y la cabecera; el núcleo se
  -- llama UNA vez. Los consumidores excluyen la cabecera de conteos, huellas y páginas.
  select * into strict v_amb from private.sla_operacion_ambito(p_lead_ids,true);
  select * into strict v_control from crm.sla_operacion_control where id;
  select p.politica_id,p.version into v_politica,v_version from private.sla_politica_operativa(v_ahora) p;
  es_cabecera:=false; cabecera:=null;
  for lead_id, estado, senales, accion_pendiente, lead, accion_revision, accion, v_p in
    select s.lead_id,
      jsonb_set(s.estado,'{avisos}',a.avisos)||jsonb_build_object('avisos_mostrados',a.mostrados),
      s.senales||jsonb_build_object('pendientes',jsonb_array_length(a.avisos)>0,
        'revisiones',(v_amb.es_global or v_amb.rol='supervisor') and (s.senales->>'revisiones')::boolean,
        'por_repartir',(v_amb.es_global or v_amb.rol='supervisor') and (s.senales->>'por_repartir')::boolean),
      a.mostrados->0,
      s.presentacion, s.accion_supervision,
      case when v_amb.es_global or v_amb.rol='supervisor' then s.accion_supervision else s.accion_atencion end,
      (s.estado#>>'{operacion,proximo_cambio_en}')::timestamptz
    from private.sla_operacion_leads(p_lead_ids,v_amb.es_global,v_amb.visibles,v_ahora) s
    cross join lateral (
      select coalesce(jsonb_agg(av.value order by (av.value->>'prioridad')::integer),'[]'::jsonb) as avisos,
        coalesce(jsonb_agg(av.value order by
          case when av.value->>'id'=s.estado#>>'{operacion,aviso_principal,id}' then 0 else 1 end,
          (av.value->>'prioridad')::integer) filter (where
            av.value->>'id'=s.estado#>>'{operacion,aviso_principal,id}'
            or (av.value->>'solo_supervision')::boolean is true),'[]'::jsonb) as mostrados
      from jsonb_array_elements(s.estado->'avisos') av
      where v_amb.es_global or v_amb.rol='supervisor' or (av.value->>'solo_supervision')::boolean is false
    ) a
  loop
    return next;
    v_prox:=least(v_prox,v_p);   -- igual que min(): los dos ignoran NULL
  end loop;
  es_cabecera:=true; lead_id:=null; estado:=null; senales:=null; accion_pendiente:=null;
  lead:=null; accion_revision:=null; accion:=null;
  cabecera:=jsonb_build_object('version',2,'modelo_avisos',3,
    'proximo_cambio_en',v_prox,
    'modo',v_control.modo,'control_revision',v_control.revision,
    'calculado_en',v_ahora,'primera_activacion_en',v_control.primera_activacion_en,
    'activacion_hipotetica_en',case when v_control.primera_activacion_en is null and v_control.modo='observacion' then v_ahora end,
    'politica_operativa_id',v_politica,'politica_operativa_version',v_version,
    'politica_adopcion_id',v_control.politica_adopcion_id,
    'contexto_ambito',md5(jsonb_build_object('actor',v_amb.actor,'rol',v_amb.rol,'global',v_amb.es_global,'visibles',v_amb.visibles)::text));
  return next;
end;
$function$
$ddl_m1_filas$;
  if pg_catalog.md5(v_def) is distinct from '5aa191534358b819d8b8f0254f91c471' then
    raise exception 'PREFLIGHT M1: el DDL de la ventana por filas no es el ensayado (md5 esperado 5aa191534358b819d8b8f0254f91c471)';
  end if;
  execute v_def;
  -- 3. Envoltorio: mismo jsonb que antes.
  v_def := $ddl_m1_autorizada$CREATE OR REPLACE FUNCTION private.sla_operacion_autorizada(p_lead_ids uuid[], p_incluir_operacion boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_amb record; v_filas jsonb; v_cab jsonb;
begin
  -- Envoltorio (paso 3a, 17/10/2026): mismo jsonb que antes, ahora sobre la autoridad única
  -- (private.sla_operacion_ambito) y la ventana por filas (private.sla_operacion_autorizada_filas).
  -- false/NULL: salida temprana de siempre (autoridad y después sla_hechos_actuales), sin leer el
  -- control, la política ni el núcleo operativo; con NULL el 22023 sale después del 42501.
  -- true: jsonb_agg sobre las filas + las claves de la cabecera, en UN solo jsonb_build_object como
  -- antes (componerlo con «cabecera || {filas}» vuelve a recorrer el bloque entero y sube el pico de
  -- memoria 30–70 MiB en gerencia; medido el 17/10 en el banco).
  if p_incluir_operacion is not true then
    select * into strict v_amb from private.sla_operacion_ambito(p_lead_ids,p_incluir_operacion);
    select coalesce(jsonb_agg(h.base order by h.lead_id),'[]'::jsonb) into v_filas
    from private.sla_hechos_actuales(p_lead_ids,v_amb.es_global,v_amb.visibles) h where h.base is not null;
    return v_filas;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('estado',f.estado,'senales',f.senales,
      'accion_pendiente',f.accion_pendiente,'lead',f.lead,'accion_revision',f.accion_revision,'accion',f.accion)
      order by f.lead_id) filter (where not f.es_cabecera),'[]'::jsonb),
    any_value(f.cabecera) filter (where f.es_cabecera)
    into v_filas, v_cab
  from private.sla_operacion_autorizada_filas(p_lead_ids) f;
  return jsonb_build_object('version',v_cab->'version','modelo_avisos',v_cab->'modelo_avisos',
    'proximo_cambio_en',v_cab->'proximo_cambio_en',
    'modo',v_cab->'modo','control_revision',v_cab->'control_revision',
    'calculado_en',v_cab->'calculado_en','primera_activacion_en',v_cab->'primera_activacion_en',
    'activacion_hipotetica_en',v_cab->'activacion_hipotetica_en',
    'politica_operativa_id',v_cab->'politica_operativa_id','politica_operativa_version',v_cab->'politica_operativa_version',
    'politica_adopcion_id',v_cab->'politica_adopcion_id','filas',v_filas,
    'contexto_ambito',v_cab->'contexto_ambito');
end;
$function$
$ddl_m1_autorizada$;
  if pg_catalog.md5(v_def) is distinct from '4cdaa81a538473ea322ca5e4835652d4' then
    raise exception 'PREFLIGHT M1: el DDL de la autorizada (envoltorio) no es el ensayado (md5 esperado 4cdaa81a538473ea322ca5e4835652d4)';
  end if;
  execute v_def;
  -- 4. Dueño postgres y ACL explícitas en las tres piezas privadas (nada para PUBLIC ni para la API); comentarios.
  execute 'alter function private.sla_operacion_ambito(uuid[],boolean) owner to postgres';
  execute 'revoke all on function private.sla_operacion_ambito(uuid[],boolean) from public, anon, authenticated, service_role';
  execute 'alter function private.sla_operacion_autorizada_filas(uuid[]) owner to postgres';
  execute 'revoke all on function private.sla_operacion_autorizada_filas(uuid[]) from public, anon, authenticated, service_role';
  execute 'alter function private.sla_operacion_autorizada(uuid[],boolean) owner to postgres';
  execute 'revoke all on function private.sla_operacion_autorizada(uuid[],boolean) from public, anon, authenticated, service_role';
  execute $c_amb$comment on function private.sla_operacion_ambito(uuid[],boolean) is 'SLA · autoridad ÚNICA de la ventana operativa (paso 3a, 17/10/2026). Resuelve actor (auth.uid()), rol CRM, lectura global efectiva y vendedores visibles, con los errores de siempre y en el mismo orden (42501 «No autorizado» y después 22023 «Entrada SLA invalida»). INVOKER y sin EXECUTE para la API: solo la llaman private.sla_operacion_autorizada (los dos modos) y private.sla_operacion_autorizada_filas, que son DEFINER. Sellada por md5 en private.assert_sla_nucleo.'$c_amb$;
  execute $c_fil$comment on function private.sla_operacion_autorizada_filas(uuid[]) is 'SLA · ventana operativa autorizada POR FILAS (paso 3a, 17/10/2026). Una fila por lead autorizado (es_cabecera = false) con los seis campos de cada elemento de «filas» de private.sla_operacion_autorizada, y SIEMPRE una última fila es_cabecera = true (también con cero leads) con la cabecera sin «filas». El núcleo se evalúa una vez y no se arma el bloque jsonb. SECURITY DEFINER porque ES la autoridad (misma frontera que sla_operacion_autorizada; dueño postgres) y sin EXECUTE para la API. La consume el envoltorio y, con las migraciones por filas instaladas, el resumen de avisos y la cola v3 (llamada siempre con argumento uuid[] tipado). Sellada por md5 en private.assert_sla_nucleo.'$c_fil$;
  -- 5. Guardianes: cambios exactos sobre el cuerpo vivo (con los sellos de la autoridad recién instalada).
  v_def := pg_catalog.pg_get_functiondef('private.assert_sla_nucleo()'::pg_catalog.regprocedure);
  if pg_catalog.strpos(v_def, $antes$ SET search_path TO ''
AS $function$
$antes$) = 0 then
    raise exception 'PREFLIGHT M1: no encuentro el texto a cambiar en assert_sla_nucleo';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$ SET search_path TO ''
AS $function$
$antes$, $despues$ SET search_path TO ''
 SET quote_all_identifiers TO 'off'
AS $function$
$despues$);
  if pg_catalog.strpos(v_def, $antes$declare v record;v_cuerpo text;v_tabla text;v_rol text;
begin
$antes$) = 0 then
    raise exception 'PREFLIGHT M1: no encuentro el texto a cambiar en assert_sla_nucleo';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$declare v record;v_cuerpo text;v_tabla text;v_rol text;
begin
$antes$, $despues$declare v record;v_cuerpo text;v_tabla text;v_rol text;v_firma text;v_huella text;
begin
  -- Paso 3a (17/10/2026): cada firma obligatoria EXISTE y la autoridad y el núcleo no tienen sobrecargas (borrar una
  -- pieza o añadir una sobrecarga que una llamada sin tipo resolvería no puede dejar este guardián en OK).
  foreach v_firma in array array['private.sla_operacion_autorizada(uuid[],boolean)',
      'private.sla_operacion_autorizada_filas(uuid[])','private.sla_operacion_ambito(uuid[],boolean)',
      'private.sla_operacion_leads(uuid[],boolean,uuid[],timestamptz)','private.sla_hechos_actuales(uuid[],boolean,uuid[])',
      'private.sla_filtros_cola_validos(text,text)'] loop
    if to_regprocedure(v_firma) is null then
      raise exception 'SLA: falta la pieza obligatoria %',v_firma;
    end if;
  end loop;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='private' and p.proname in ('sla_operacion_autorizada','sla_operacion_autorizada_filas',
        'sla_operacion_ambito','sla_operacion_leads')
      group by p.proname having cardinality(array_agg(p.oid))>1) then
    raise exception 'SLA: la autoridad o el nucleo tienen sobrecargas';
  end if;
$despues$);
  if pg_catalog.strpos(v_def, $antes$    ('private.sla_operacion_autorizada(uuid[],boolean)','sla_operacion_leads'),
$antes$) = 0 then
    raise exception 'PREFLIGHT M1: no encuentro el texto a cambiar en assert_sla_nucleo';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$    ('private.sla_operacion_autorizada(uuid[],boolean)','sla_operacion_leads'),
$antes$, $despues$    ('private.sla_operacion_autorizada(uuid[],boolean)','sla_operacion_ambito'),
    ('private.sla_operacion_autorizada(uuid[],boolean)','sla_operacion_autorizada_filas'),
    ('private.sla_operacion_autorizada_filas(uuid[])','sla_operacion_ambito'),
    ('private.sla_operacion_autorizada_filas(uuid[])','sla_operacion_leads'),
$despues$);
  if pg_catalog.strpos(v_def, $antes$      'sla_evaluar_prorroga','sla_politica_operativa','sla_etapa_hechos','sla_operacion_leads','sla_operacion_autorizada','sla_filtros_cola_validos')
$antes$) = 0 then
    raise exception 'PREFLIGHT M1: no encuentro el texto a cambiar en assert_sla_nucleo';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$      'sla_evaluar_prorroga','sla_politica_operativa','sla_etapa_hechos','sla_operacion_leads','sla_operacion_autorizada','sla_filtros_cola_validos')
$antes$, $despues$      'sla_evaluar_prorroga','sla_politica_operativa','sla_etapa_hechos','sla_operacion_leads','sla_operacion_autorizada','sla_filtros_cola_validos',
      'sla_operacion_autorizada_filas','sla_operacion_ambito')
$despues$);
  if pg_catalog.strpos(v_def, $antes$       or v.prosecdef<>(v.proname='sla_operacion_autorizada') then
$antes$) = 0 then
    raise exception 'PREFLIGHT M1: no encuentro el texto a cambiar en assert_sla_nucleo';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$       or v.prosecdef<>(v.proname='sla_operacion_autorizada') then
$antes$, $despues$       or v.prosecdef<>(v.proname in ('sla_operacion_autorizada','sla_operacion_autorizada_filas'))
       or v.proowner<>'postgres'::regrole::oid then
$despues$);
  if pg_catalog.strpos(v_def, $antes$    if v.proname<>'sla_operacion_autorizada' and v.prosrc ~ '\mauth\s*\.' then
$antes$) = 0 then
    raise exception 'PREFLIGHT M1: no encuentro el texto a cambiar en assert_sla_nucleo';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$    if v.proname<>'sla_operacion_autorizada' and v.prosrc ~ '\mauth\s*\.' then
$antes$, $despues$    if v.proname<>'sla_operacion_ambito' and v.prosrc ~* '\mauth\s*\.' then
$despues$);
  if pg_catalog.strpos(v_def, $antes$  return 'OK: nucleo SLA privado, adaptadores dependientes, entradas cerradas y auditadas';
$antes$) = 0 then
    raise exception 'PREFLIGHT M1: no encuentro el texto a cambiar en assert_sla_nucleo';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$  return 'OK: nucleo SLA privado, adaptadores dependientes, entradas cerradas y auditadas';
$antes$, $despues$  -- Paso 3a: huellas md5 de la AUTORIDAD (pg_get_functiondef; search_path y quote_all_identifiers fijados en este
  -- guardián): un cambio de cuerpo, aunque conserve dependencias y propiedades, lo detiene. Re-sellar a conciencia.
  for v_firma,v_huella in select * from (values
    ('private.sla_operacion_ambito(uuid[],boolean)','e843f6cd039b92a5fcd1e629d6ad4138'),
    ('private.sla_operacion_autorizada_filas(uuid[])','5aa191534358b819d8b8f0254f91c471'),
    ('private.sla_operacion_autorizada(uuid[],boolean)','4cdaa81a538473ea322ca5e4835652d4')) s(firma,huella) loop
    if md5(pg_get_functiondef(v_firma::regprocedure)) is distinct from v_huella then
      raise exception 'SLA: el cuerpo de % cambio (md5 %); re-sellar a conciencia',v_firma,md5(pg_get_functiondef(v_firma::regprocedure));
    end if;
  end loop;
  return 'OK: nucleo SLA privado, adaptadores dependientes, entradas cerradas y auditadas';
$despues$);
  if pg_catalog.md5(v_def) is distinct from 'a938047d5c98aa009984a9e836b2fc9d' then
    raise exception 'PREFLIGHT M1: el DDL de assert_sla_nucleo no es el ensayado (md5 esperado a938047d5c98aa009984a9e836b2fc9d)';
  end if;
  execute v_def;
  v_def := pg_catalog.pg_get_functiondef('private.assert_sla_avisos()'::pg_catalog.regprocedure);
  if pg_catalog.strpos(v_def, $antes$    ('private.sla_operacion_autorizada(uuid[],boolean)','sla_operacion_leads')
$antes$) = 0 then
    raise exception 'PREFLIGHT M1: no encuentro el texto a cambiar en assert_sla_avisos';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$    ('private.sla_operacion_autorizada(uuid[],boolean)','sla_operacion_leads')
$antes$, $despues$    ('private.sla_operacion_autorizada(uuid[],boolean)','sla_operacion_autorizada_filas'),
    ('private.sla_operacion_autorizada_filas(uuid[])','sla_operacion_leads')
$despues$);
  if pg_catalog.md5(v_def) is distinct from 'fb433efc037f09647481744a5f36380c' then
    raise exception 'PREFLIGHT M1: el DDL de assert_sla_avisos no es el ensayado (md5 esperado fb433efc037f09647481744a5f36380c)';
  end if;
  execute v_def;
  -- 6. Poscondiciones: huellas nuevas y TODOS los atributos de las piezas tocadas y de las exigidas.
  for v_firma, v_esp in select e.key, e.value from pg_catalog.jsonb_each($esperado_postflight_m1${
 "private.sla_operacion_ambito(uuid[],boolean)": {
  "def": "e843f6cd039b92a5fcd1e629d6ad4138",
  "src": "b75fb4c86471cba36687c15986bd60dc",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|record|ba5d2ec895f334e53417ef36cffebb2b",
  "extra": "plpgsql|false|false|100|1000|-|true|p_lead_ids uuid[], p_incluir_operacion boolean|TABLE(actor uuid, rol text, es_global boolean, visibles uuid[])"
 },
 "private.sla_operacion_autorizada_filas(uuid[])": {
  "def": "5aa191534358b819d8b8f0254f91c471",
  "src": "250863962d4a0a5adb564d2e7c8a39cb",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|record|3094558e14db3ba8d8fa684e5ce99ca5",
  "extra": "plpgsql|false|false|100|1000|-|true|p_lead_ids uuid[]|TABLE(es_cabecera boolean, lead_id uuid, estado jsonb, senales jsonb, accion_pendiente jsonb, lead jsonb, accion_revision jsonb, accion jsonb, cabecera jsonb)"
 },
 "private.sla_operacion_autorizada(uuid[],boolean)": {
  "def": "4cdaa81a538473ea322ca5e4835652d4",
  "src": "7d8c87935730be5f3b43559dc05e977a",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|jsonb|8dd4b7845c20f10e7f9cf1aa84c58ca9",
  "extra": "plpgsql|false|false|100|0|-|false|p_lead_ids uuid[], p_incluir_operacion boolean|jsonb"
 },
 "private.assert_sla_nucleo()": {
  "def": "a938047d5c98aa009984a9e836b2fc9d",
  "src": "7f5a08dde907b343b8562b6024eba110",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\",quote_all_identifiers=off|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e",
  "extra": "plpgsql|false|false|100|0|-|false||text"
 },
 "private.assert_sla_avisos()": {
  "def": "fb433efc037f09647481744a5f36380c",
  "src": "7c6007603919f41406649edffa63429d",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e",
  "extra": "plpgsql|false|false|100|0|-|false||text"
 },
 "crm.avisos_sla_resumen_v2_fn()": {
  "def": "e9ce617ab0cc33bc5614ef69e877cc71",
  "src": "576b1aa6e4d3eddd947d6bbdb1c99f40",
  "meta": "postgres|{postgres=X/postgres,authenticated=X/postgres}|search_path=\"\"|true|s|u|jsonb|502d0d8cb0124b164f936cf6ef6dba63",
  "extra": "plpgsql|false|false|100|0|-|false||jsonb"
 },
 "crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)": {
  "def": "1ec76074c9b5650cb8bac4c79440eccb",
  "src": "828989da281bc8c32fab812542e86ba9",
  "meta": "postgres|{postgres=X/postgres,authenticated=X/postgres}|search_path=\"\"|true|s|u|jsonb|4fc30931ad31e222dc19423d89befb12",
  "extra": "plpgsql|false|false|100|0|-|false|p_limite integer DEFAULT 50, p_senal text DEFAULT 'todas'::text, p_etapa text DEFAULT NULL::text, p_analista_id uuid DEFAULT NULL::uuid, p_cursor jsonb DEFAULT NULL::jsonb|jsonb"
 },
 "private.assert_cola_v3()": {
  "def": "162fe9e053c8b57f8b501dadbe2afca7",
  "src": "97d9d1b96c9b9a882a6518b890d082c0",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|text|dd5dee9c51f0f514a8f4c05582216dd2",
  "extra": "plpgsql|false|false|100|0|-|false||text"
 },
 "private.sla_operacion_leads(uuid[],boolean,uuid[],timestamp with time zone)": {
  "def": "0abdf640b5f4f10ab2e85b6bd2494522",
  "src": "e47f610fb4cde0741f2a22c3e2e7ee2c",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|record|928c35d75cc268f2319658ee77878148",
  "extra": "plpgsql|false|false|100|1000|-|true|p_lead_ids uuid[], p_global boolean, p_visibles uuid[], p_ahora timestamp with time zone|TABLE(lead_id uuid, estado jsonb, accion_atencion jsonb, accion_supervision jsonb, senales jsonb, presentacion jsonb)"
 },
 "private.tareas_clientes_autorizadas(uuid,uuid[],text,boolean,timestamp with time zone,timestamp with time zone)": {
  "def": "234ee27f745ef1817be0e0cbdd2b2e25",
  "src": "8d02b260a0aa0bc50536afdc82c32ba3",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|record|0ca7eed9b41e7884ae26930b1e633c75",
  "extra": "plpgsql|false|false|100|1000|-|true|p_uid uuid, p_visibles uuid[], p_rol text, p_global boolean, p_ahora timestamp with time zone, p_fin_dia timestamp with time zone|TABLE(tarea_id uuid, perfil_id uuid, inversionista_id uuid, nombre text, responsable_id uuid, vence_en timestamp with time zone, bucket text)"
 },
 "private.sla_leads_operativos()": {
  "def": "8d478d783e4c591662388ddf7405058a",
  "src": "fd8f5800b253b137e82e666b9a89ab0a",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|uuid[]|130901f18423506211fa55f95ef1e834",
  "extra": "sql|false|false|100|0|-|false||uuid[]"
 }
}$esperado_postflight_m1$::jsonb) e loop
    v_oid := pg_catalog.to_regprocedure(v_firma);
    if v_oid is null then
      raise exception 'POSTFLIGHT M1: no existe %', v_firma;
    end if;
    select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)), pg_catalog.md5(p.prosrc), pg_catalog.concat_ws('|', pg_catalog.pg_get_userbyid(p.proowner), p.proacl::text, pg_catalog.array_to_string(p.proconfig, ','),
         p.prosecdef::text, p.provolatile::text, p.proparallel::text, p.prorettype::pg_catalog.regtype::text,
         pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), ''))), (select pg_catalog.concat_ws('|', l.lanname, p.proisstrict::text, p.proleakproof::text, p.procost::text, p.prorows::text,
         p.prosupport::text, p.proretset::text, pg_catalog.pg_get_function_arguments(p.oid), pg_catalog.pg_get_function_result(p.oid))
         from pg_catalog.pg_language l where l.oid = p.prolang)
      into v_md5_def, v_md5_src, v_meta, v_extra from pg_catalog.pg_proc p where p.oid = v_oid;
    if v_md5_def is distinct from v_esp->>'def' or v_md5_src is distinct from v_esp->>'src' then
      raise exception 'POSTFLIGHT M1: % no es la versión ensayada (md5 def % / prosrc %; esperado % / %)', v_firma, v_md5_def, v_md5_src, v_esp->>'def', v_esp->>'src';
    end if;
    if v_meta is distinct from v_esp->>'meta' then
      raise exception 'POSTFLIGHT M1: dueño, ACL, configuración, DEFINER, volatilidad o comentario de % distintos (%)', v_firma, v_meta;
    end if;
    if v_extra is distinct from v_esp->>'extra' then
      raise exception 'POSTFLIGHT M1: otro atributo de % distinto (lenguaje, strict, leakproof, coste, filas, soporte, argumentos o resultado): %', v_firma, v_extra;
    end if;
  end loop;
  -- ACL EFECTIVA (también PUBLIC y herencia) y ACL guardada: las piezas privadas de la ventana, solo para su dueño.
  if exists (select 1 from pg_catalog.pg_roles r, pg_catalog.unnest('{"private.sla_operacion_ambito(uuid[],boolean)","private.sla_operacion_autorizada_filas(uuid[])","private.sla_operacion_autorizada(uuid[],boolean)"}'::text[]) f(firma)
             where not r.rolsuper and r.rolname <> 'postgres' and not pg_catalog.pg_has_role(r.oid, 'postgres', 'MEMBER')
               and pg_catalog.has_function_privilege(r.oid, f.firma, 'EXECUTE'))
     or exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
                where p.oid = any (array(select pg_catalog.to_regprocedure(x)::oid from pg_catalog.unnest('{"private.sla_operacion_ambito(uuid[],boolean)","private.sla_operacion_autorizada_filas(uuid[])","private.sla_operacion_autorizada(uuid[],boolean)"}'::text[]) x))
                  and a.grantee <> p.proowner) then
    raise exception 'POSTFLIGHT M1: alguna pieza privada de la ventana tiene EXECUTE fuera del dueño';
  end if;
  -- Guardianes del SLA dentro de la MISMA transacción: si alguno no da «OK: …» (o da NULL), no queda nada aplicado.
  v_ok := private.assert_sla_nucleo();
  if (v_ok like 'OK: %') is not true then raise exception 'POSTFLIGHT M1: assert_sla_nucleo no da OK: %', v_ok; end if;
  v_ok := private.assert_cola_v3();
  if (v_ok like 'OK: %') is not true then raise exception 'POSTFLIGHT M1: assert_cola_v3 no da OK: %', v_ok; end if;
  v_ok := private.assert_sla_avisos();
  if (v_ok like 'OK: %') is not true then raise exception 'POSTFLIGHT M1: assert_sla_avisos no da OK: %', v_ok; end if;
end $m1$;
commit;
$migracion_20261017054425$),
    pg_catalog.jsonb_build_array('20261017054426', 'crm_sla_avisos_por_filas', $migracion_20261017054426$-- SLA paso 3a · M2: el resumen de avisos cuenta POR FILAS (plan «foto del SLA», Fase 3). v2. Requiere M1 (20261017054425_crm_sla_ventana_por_filas).
-- crm.avisos_sla_resumen_v2_fn() deja de pedir el bloque jsonb de private.sla_operacion_autorizada y cuenta sobre
-- private.sla_operacion_autorizada_filas(private.sla_leads_operativos()): mismo jsonb byte a byte (cabecera sin
-- contexto_ambito; cuenta FILAS con pendientes en modo activo; en otro modo, ceros). Misma firma, ACL (solo authenticated),
-- DEFINER, search_path y volatilidad; COMMENT ON actualizado.
-- private.assert_sla_avisos(): el resumen consume _filas, siempre acotada por sla_leads_operativos(); solo puede llamar a su
-- LISTA PERMITIDA de piezas privadas (ni envoltorio de bloque único, ni núcleo, ni hechos sin autoridad); SELLO md5 del
-- resumen (quote_all_identifiers fijado en el guardián). (Autorizado por Miguel, 16/10 23:55.)
-- Exige además el productor private.sla_operacion_leads ensayado (Codex P2). Historial: se niega si su versión ya está en
-- el índice. Evidencia y cifras: supabase/scripts/sla-por-filas/LEEME.md.
-- Antes:   resumen prosrc 576b1aa6e4d3eddd947d6bbdb1c99f40 · Después: 3387f3aff90b1e47e05bcddea14a91e3 · familia SLA 64 · 5e4e27c4548576663fa65b801a839f0e
-- REVERTIR: supabase/scripts/sla-por-filas/reversa-m2.sql como MIGRACIÓN NUEVA (y registrar-reversa-m2.sql), con M3 ya
-- revertida.
begin;
set local lock_timeout = '5s';
set local search_path = '';
set local quote_all_identifiers = off;
do $m2$
declare
  v_oid oid; v_firma text; v_esp jsonb; v_def text; v_md5_def text; v_md5_src text; v_meta text; v_extra text; v_ok text;
  v_ya boolean;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm_sla_por_filas'));
  -- Historial (Codex P1): si ESTA versión ya está en el índice de migraciones, no se vuelve a aplicar. Una reaplicación
  -- tras reversas registradas va con versiones NUEVAS; «commit hecho, registro pendiente» se cierra con
  -- registrar-indice.sql, sin volver a ejecutar el DDL. En una base sin índice (banco), no aplica.
  if pg_catalog.to_regclass('supabase_migrations.schema_migrations') is not null then
    execute 'select exists (select 1 from supabase_migrations.schema_migrations m where m.version = $1)' into v_ya using '20261017054426';
    if v_ya then
      raise exception 'PREFLIGHT M2: la versión 20261017054426 ya está en supabase_migrations.schema_migrations; no se aplica otra vez (una reaplicación tras reversas registradas va con versiones nuevas)';
    end if;
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('crm.avisos_sla_resumen_v2_fn()')) = '3387f3aff90b1e47e05bcddea14a91e3' then
    raise exception 'PREFLIGHT M2: ya aplicada (el resumen de avisos ya tiene el cuerpo nuevo 3387f3aff90b1e47e05bcddea14a91e3); no se aplica dos veces';
  end if;
  for v_firma, v_esp in select e.key, e.value from pg_catalog.jsonb_each($esperado_preflight_m2${
 "private.sla_operacion_ambito(uuid[],boolean)": {
  "def": "e843f6cd039b92a5fcd1e629d6ad4138",
  "src": "b75fb4c86471cba36687c15986bd60dc",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|record|ba5d2ec895f334e53417ef36cffebb2b",
  "extra": "plpgsql|false|false|100|1000|-|true|p_lead_ids uuid[], p_incluir_operacion boolean|TABLE(actor uuid, rol text, es_global boolean, visibles uuid[])"
 },
 "private.sla_operacion_autorizada_filas(uuid[])": {
  "def": "5aa191534358b819d8b8f0254f91c471",
  "src": "250863962d4a0a5adb564d2e7c8a39cb",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|record|3094558e14db3ba8d8fa684e5ce99ca5",
  "extra": "plpgsql|false|false|100|1000|-|true|p_lead_ids uuid[]|TABLE(es_cabecera boolean, lead_id uuid, estado jsonb, senales jsonb, accion_pendiente jsonb, lead jsonb, accion_revision jsonb, accion jsonb, cabecera jsonb)"
 },
 "private.sla_operacion_autorizada(uuid[],boolean)": {
  "def": "4cdaa81a538473ea322ca5e4835652d4",
  "src": "7d8c87935730be5f3b43559dc05e977a",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|jsonb|8dd4b7845c20f10e7f9cf1aa84c58ca9",
  "extra": "plpgsql|false|false|100|0|-|false|p_lead_ids uuid[], p_incluir_operacion boolean|jsonb"
 },
 "private.assert_sla_nucleo()": {
  "def": "a938047d5c98aa009984a9e836b2fc9d",
  "src": "7f5a08dde907b343b8562b6024eba110",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\",quote_all_identifiers=off|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e",
  "extra": "plpgsql|false|false|100|0|-|false||text"
 },
 "private.assert_sla_avisos()": {
  "def": "fb433efc037f09647481744a5f36380c",
  "src": "7c6007603919f41406649edffa63429d",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e",
  "extra": "plpgsql|false|false|100|0|-|false||text"
 },
 "crm.avisos_sla_resumen_v2_fn()": {
  "def": "e9ce617ab0cc33bc5614ef69e877cc71",
  "src": "576b1aa6e4d3eddd947d6bbdb1c99f40",
  "meta": "postgres|{postgres=X/postgres,authenticated=X/postgres}|search_path=\"\"|true|s|u|jsonb|502d0d8cb0124b164f936cf6ef6dba63",
  "extra": "plpgsql|false|false|100|0|-|false||jsonb"
 },
 "crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)": {
  "def": "1ec76074c9b5650cb8bac4c79440eccb",
  "src": "828989da281bc8c32fab812542e86ba9",
  "meta": "postgres|{postgres=X/postgres,authenticated=X/postgres}|search_path=\"\"|true|s|u|jsonb|4fc30931ad31e222dc19423d89befb12",
  "extra": "plpgsql|false|false|100|0|-|false|p_limite integer DEFAULT 50, p_senal text DEFAULT 'todas'::text, p_etapa text DEFAULT NULL::text, p_analista_id uuid DEFAULT NULL::uuid, p_cursor jsonb DEFAULT NULL::jsonb|jsonb"
 },
 "private.assert_cola_v3()": {
  "def": "162fe9e053c8b57f8b501dadbe2afca7",
  "src": "97d9d1b96c9b9a882a6518b890d082c0",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|text|dd5dee9c51f0f514a8f4c05582216dd2",
  "extra": "plpgsql|false|false|100|0|-|false||text"
 },
 "private.sla_operacion_leads(uuid[],boolean,uuid[],timestamp with time zone)": {
  "def": "0abdf640b5f4f10ab2e85b6bd2494522",
  "src": "e47f610fb4cde0741f2a22c3e2e7ee2c",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|record|928c35d75cc268f2319658ee77878148",
  "extra": "plpgsql|false|false|100|1000|-|true|p_lead_ids uuid[], p_global boolean, p_visibles uuid[], p_ahora timestamp with time zone|TABLE(lead_id uuid, estado jsonb, accion_atencion jsonb, accion_supervision jsonb, senales jsonb, presentacion jsonb)"
 },
 "private.tareas_clientes_autorizadas(uuid,uuid[],text,boolean,timestamp with time zone,timestamp with time zone)": {
  "def": "234ee27f745ef1817be0e0cbdd2b2e25",
  "src": "8d02b260a0aa0bc50536afdc82c32ba3",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|record|0ca7eed9b41e7884ae26930b1e633c75",
  "extra": "plpgsql|false|false|100|1000|-|true|p_uid uuid, p_visibles uuid[], p_rol text, p_global boolean, p_ahora timestamp with time zone, p_fin_dia timestamp with time zone|TABLE(tarea_id uuid, perfil_id uuid, inversionista_id uuid, nombre text, responsable_id uuid, vence_en timestamp with time zone, bucket text)"
 },
 "private.sla_leads_operativos()": {
  "def": "8d478d783e4c591662388ddf7405058a",
  "src": "fd8f5800b253b137e82e666b9a89ab0a",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|uuid[]|130901f18423506211fa55f95ef1e834",
  "extra": "sql|false|false|100|0|-|false||uuid[]"
 }
}$esperado_preflight_m2$::jsonb) e loop
    v_oid := pg_catalog.to_regprocedure(v_firma);
    if v_oid is null then
      raise exception 'PREFLIGHT M2: no existe %', v_firma;
    end if;
    select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)), pg_catalog.md5(p.prosrc), pg_catalog.concat_ws('|', pg_catalog.pg_get_userbyid(p.proowner), p.proacl::text, pg_catalog.array_to_string(p.proconfig, ','),
         p.prosecdef::text, p.provolatile::text, p.proparallel::text, p.prorettype::pg_catalog.regtype::text,
         pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), ''))), (select pg_catalog.concat_ws('|', l.lanname, p.proisstrict::text, p.proleakproof::text, p.procost::text, p.prorows::text,
         p.prosupport::text, p.proretset::text, pg_catalog.pg_get_function_arguments(p.oid), pg_catalog.pg_get_function_result(p.oid))
         from pg_catalog.pg_language l where l.oid = p.prolang)
      into v_md5_def, v_md5_src, v_meta, v_extra from pg_catalog.pg_proc p where p.oid = v_oid;
    if v_md5_def is distinct from v_esp->>'def' or v_md5_src is distinct from v_esp->>'src' then
      raise exception 'PREFLIGHT M2: % no es la versión revisada (md5 def % / prosrc %; esperado % / %)', v_firma, v_md5_def, v_md5_src, v_esp->>'def', v_esp->>'src';
    end if;
    if v_meta is distinct from v_esp->>'meta' then
      raise exception 'PREFLIGHT M2: dueño, ACL, configuración, DEFINER, volatilidad o comentario de % distintos (%)', v_firma, v_meta;
    end if;
    if v_extra is distinct from v_esp->>'extra' then
      raise exception 'PREFLIGHT M2: otro atributo de % distinto (lenguaje, strict, leakproof, coste, filas, soporte, argumentos o resultado): %', v_firma, v_extra;
    end if;
  end loop;
  -- 1. Resumen por filas y su comentario.
  v_def := $ddl_m2_resumen$CREATE OR REPLACE FUNCTION crm.avisos_sla_resumen_v2_fn()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_cab jsonb;v_total integer;v_avisos integer;v_criticas integer;v_grupos jsonb;
begin
  -- Misma ventana autorizada y mismo instante que ficha y cola, ahora POR FILAS (paso 3a,
  -- 17/10/2026): cuenta sobre private.sla_operacion_autorizada_filas sin armar el bloque jsonb.
  -- Solo las oportunidades que pueden avisar (private.sla_leads_operativos: activas y en etapa
  -- comercial). Cuenta FILAS con pendientes en modo activo; en otro modo, ceros. La cabecera es la
  -- de la ventana sin contexto_ambito.
  with f as materialized (
    select x.es_cabecera, x.cabecera, x.estado->'avisos' as avisos, (x.senales->>'pendientes')::boolean as pendientes
    from private.sla_operacion_autorizada_filas(private.sla_leads_operativos()) x
  ), cab as (
    select f.cabecera from f where f.es_cabecera
  ), filas as materialized (
    select f.avisos from f cross join cab
    where not f.es_cabecera and cab.cabecera->>'modo'='activo' and f.pendientes
  ), avisos as materialized (
    select a.value from filas f cross join lateral jsonb_array_elements(f.avisos) a
  ), grupos as (
    select a.value->>'bucket' as bucket,cardinality(array_agg(true)) as total,
      min((a.value->>'prioridad')::integer) as prioridad
    from avisos a group by a.value->>'bucket'
  )
  select (select c.cabecera from cab c),
    (select coalesce(cardinality(array_agg(true)),0) from filas f),
    (select coalesce(cardinality(array_agg(true)),0) from avisos a),
    (select coalesce(cardinality(array_agg(true)),0) from avisos a where a.value->>'severidad'='critica'),
    coalesce((select jsonb_agg(jsonb_build_object('bucket',g.bucket,'total',g.total) order by g.prioridad) from grupos g),'[]'::jsonb)
  into v_cab,v_total,v_avisos,v_criticas,v_grupos;
  return (v_cab-'contexto_ambito')||jsonb_build_object(
    'total_oportunidades',v_total,'total_avisos',v_avisos,'criticas',v_criticas,'grupos',v_grupos);
end;
$function$
$ddl_m2_resumen$;
  if pg_catalog.md5(v_def) is distinct from '82a7cabdae761ea7b3707db9f9c62452' then
    raise exception 'PREFLIGHT M2: el DDL de el resumen de avisos no es el ensayado (md5 esperado 82a7cabdae761ea7b3707db9f9c62452)';
  end if;
  execute v_def;
  execute $c_res$comment on function crm.avisos_sla_resumen_v2_fn() is 'Resumen acotado de avisos vigentes del nucleo SLA (paso 3a, 17/10/2026): cuenta filas de private.sla_operacion_autorizada_filas(private.sla_leads_operativos()) sin armar el bloque jsonb; autoridad y reloj de esa ventana; sin entrega push ni escrituras. Sellado por md5 en private.assert_sla_avisos.'$c_res$;
  -- 2. Guardián de avisos: cambios exactos sobre el cuerpo vivo (versión de M1) con el sello del resumen.
  v_def := pg_catalog.pg_get_functiondef('private.assert_sla_avisos()'::pg_catalog.regprocedure);
  if pg_catalog.strpos(v_def, $antes$ SET search_path TO ''
AS $function$
$antes$) = 0 then
    raise exception 'PREFLIGHT M2: no encuentro el texto a cambiar en assert_sla_avisos';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$ SET search_path TO ''
AS $function$
$antes$, $despues$ SET search_path TO ''
 SET quote_all_identifiers TO 'off'
AS $function$
$despues$);
  if pg_catalog.strpos(v_def, $antes$declare v record;v_cuerpo text;
begin
$antes$) = 0 then
    raise exception 'PREFLIGHT M2: no encuentro el texto a cambiar en assert_sla_avisos';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$declare v record;v_cuerpo text;
begin
$antes$, $despues$declare v record;v_cuerpo text;v_privadas text[];
begin
$despues$);
  if pg_catalog.strpos(v_def, $antes$    ('crm.avisos_sla_resumen_v2_fn()','sla_operacion_autorizada'),
$antes$) = 0 then
    raise exception 'PREFLIGHT M2: no encuentro el texto a cambiar en assert_sla_avisos';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$    ('crm.avisos_sla_resumen_v2_fn()','sla_operacion_autorizada'),
$antes$, $despues$    ('crm.avisos_sla_resumen_v2_fn()','sla_operacion_autorizada_filas'),
$despues$);
  if pg_catalog.strpos(v_def, $antes$  if regexp_count(v_cuerpo, '\mprivate\.sla_operacion_autorizada\s*\(') < 1
     or regexp_count(v_cuerpo, '\mprivate\.sla_operacion_autorizada\s*\(')
        <> regexp_count(v_cuerpo, '\mprivate\.sla_operacion_autorizada\s*\(\s*private\.sla_leads_operativos\s*\(\s*\)\s*,') then
$antes$) = 0 then
    raise exception 'PREFLIGHT M2: no encuentro el texto a cambiar en assert_sla_avisos';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$  if regexp_count(v_cuerpo, '\mprivate\.sla_operacion_autorizada\s*\(') < 1
     or regexp_count(v_cuerpo, '\mprivate\.sla_operacion_autorizada\s*\(')
        <> regexp_count(v_cuerpo, '\mprivate\.sla_operacion_autorizada\s*\(\s*private\.sla_leads_operativos\s*\(\s*\)\s*,') then
$antes$, $despues$  -- Paso 3a (17/10/2026): el resumen cuenta sobre la ventana POR FILAS. Toda llamada a _filas va acotada por el
  -- ayudante, y el resumen no puede volver al envoltorio de bloque único ni llamar al núcleo sin autoridad.
  if regexp_count(v_cuerpo, '\mprivate\.sla_operacion_autorizada_filas\s*\(') < 1
     or regexp_count(v_cuerpo, '\mprivate\.sla_operacion_autorizada_filas\s*\(')
        <> regexp_count(v_cuerpo, '\mprivate\.sla_operacion_autorizada_filas\s*\(\s*private\.sla_leads_operativos\s*\(\s*\)\s*\)')
     or v_cuerpo ~ '\mprivate\.sla_operacion_autorizada\s*\('
     or v_cuerpo ~ '\mprivate\.sla_operacion_leads\s*\(' then
$despues$);
  if pg_catalog.strpos(v_def, $antes$  return 'OK: avisos derivados del nucleo, con autoridad y resumen completo';
$antes$) = 0 then
    raise exception 'PREFLIGHT M2: no encuentro el texto a cambiar en assert_sla_avisos';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$  return 'OK: avisos derivados del nucleo, con autoridad y resumen completo';
$antes$, $despues$  -- Lista PERMITIDA de piezas privadas que el resumen puede llamar (ni núcleo ni hechos sin autoridad).
  select array_agg(distinct m[1] order by m[1]) into v_privadas
    from regexp_matches(v_cuerpo,'\mprivate\.([a-z0-9_]+)\s*\(','g') m;
  if (v_privadas <@ array['sla_leads_operativos','sla_operacion_autorizada_filas']) is not true then
    raise exception 'SLA avisos: el resumen llama a piezas privadas fuera de su lista permitida: %',v_privadas;
  end if;
  -- Huella md5 del resumen (pg_get_functiondef; search_path y quote_all_identifiers fijados en este guardián).
  if md5(pg_get_functiondef('crm.avisos_sla_resumen_v2_fn()'::regprocedure)) is distinct from '82a7cabdae761ea7b3707db9f9c62452' then
    raise exception 'SLA avisos: el cuerpo del resumen cambio (md5 %); re-sellar a conciencia',
      md5(pg_get_functiondef('crm.avisos_sla_resumen_v2_fn()'::regprocedure));
  end if;
  return 'OK: avisos derivados del nucleo, con autoridad y resumen completo';
$despues$);
  if pg_catalog.md5(v_def) is distinct from '1cbce7c3cdd9d39e61e9c26af29a9f7e' then
    raise exception 'PREFLIGHT M2: el DDL de assert_sla_avisos no es el ensayado (md5 esperado 1cbce7c3cdd9d39e61e9c26af29a9f7e)';
  end if;
  execute v_def;
  -- 3. Poscondiciones.
  for v_firma, v_esp in select e.key, e.value from pg_catalog.jsonb_each($esperado_postflight_m2${
 "private.sla_operacion_ambito(uuid[],boolean)": {
  "def": "e843f6cd039b92a5fcd1e629d6ad4138",
  "src": "b75fb4c86471cba36687c15986bd60dc",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|record|ba5d2ec895f334e53417ef36cffebb2b",
  "extra": "plpgsql|false|false|100|1000|-|true|p_lead_ids uuid[], p_incluir_operacion boolean|TABLE(actor uuid, rol text, es_global boolean, visibles uuid[])"
 },
 "private.sla_operacion_autorizada_filas(uuid[])": {
  "def": "5aa191534358b819d8b8f0254f91c471",
  "src": "250863962d4a0a5adb564d2e7c8a39cb",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|record|3094558e14db3ba8d8fa684e5ce99ca5",
  "extra": "plpgsql|false|false|100|1000|-|true|p_lead_ids uuid[]|TABLE(es_cabecera boolean, lead_id uuid, estado jsonb, senales jsonb, accion_pendiente jsonb, lead jsonb, accion_revision jsonb, accion jsonb, cabecera jsonb)"
 },
 "private.sla_operacion_autorizada(uuid[],boolean)": {
  "def": "4cdaa81a538473ea322ca5e4835652d4",
  "src": "7d8c87935730be5f3b43559dc05e977a",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|jsonb|8dd4b7845c20f10e7f9cf1aa84c58ca9",
  "extra": "plpgsql|false|false|100|0|-|false|p_lead_ids uuid[], p_incluir_operacion boolean|jsonb"
 },
 "private.assert_sla_nucleo()": {
  "def": "a938047d5c98aa009984a9e836b2fc9d",
  "src": "7f5a08dde907b343b8562b6024eba110",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\",quote_all_identifiers=off|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e",
  "extra": "plpgsql|false|false|100|0|-|false||text"
 },
 "private.assert_sla_avisos()": {
  "def": "1cbce7c3cdd9d39e61e9c26af29a9f7e",
  "src": "d307e5acaa84517072d8f65db882c1f3",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\",quote_all_identifiers=off|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e",
  "extra": "plpgsql|false|false|100|0|-|false||text"
 },
 "crm.avisos_sla_resumen_v2_fn()": {
  "def": "82a7cabdae761ea7b3707db9f9c62452",
  "src": "3387f3aff90b1e47e05bcddea14a91e3",
  "meta": "postgres|{postgres=X/postgres,authenticated=X/postgres}|search_path=\"\"|true|s|u|jsonb|0003d4f1991eab3f3d0105e52a9a9f2a",
  "extra": "plpgsql|false|false|100|0|-|false||jsonb"
 },
 "crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)": {
  "def": "1ec76074c9b5650cb8bac4c79440eccb",
  "src": "828989da281bc8c32fab812542e86ba9",
  "meta": "postgres|{postgres=X/postgres,authenticated=X/postgres}|search_path=\"\"|true|s|u|jsonb|4fc30931ad31e222dc19423d89befb12",
  "extra": "plpgsql|false|false|100|0|-|false|p_limite integer DEFAULT 50, p_senal text DEFAULT 'todas'::text, p_etapa text DEFAULT NULL::text, p_analista_id uuid DEFAULT NULL::uuid, p_cursor jsonb DEFAULT NULL::jsonb|jsonb"
 },
 "private.assert_cola_v3()": {
  "def": "162fe9e053c8b57f8b501dadbe2afca7",
  "src": "97d9d1b96c9b9a882a6518b890d082c0",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|text|dd5dee9c51f0f514a8f4c05582216dd2",
  "extra": "plpgsql|false|false|100|0|-|false||text"
 },
 "private.sla_operacion_leads(uuid[],boolean,uuid[],timestamp with time zone)": {
  "def": "0abdf640b5f4f10ab2e85b6bd2494522",
  "src": "e47f610fb4cde0741f2a22c3e2e7ee2c",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|record|928c35d75cc268f2319658ee77878148",
  "extra": "plpgsql|false|false|100|1000|-|true|p_lead_ids uuid[], p_global boolean, p_visibles uuid[], p_ahora timestamp with time zone|TABLE(lead_id uuid, estado jsonb, accion_atencion jsonb, accion_supervision jsonb, senales jsonb, presentacion jsonb)"
 },
 "private.tareas_clientes_autorizadas(uuid,uuid[],text,boolean,timestamp with time zone,timestamp with time zone)": {
  "def": "234ee27f745ef1817be0e0cbdd2b2e25",
  "src": "8d02b260a0aa0bc50536afdc82c32ba3",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|record|0ca7eed9b41e7884ae26930b1e633c75",
  "extra": "plpgsql|false|false|100|1000|-|true|p_uid uuid, p_visibles uuid[], p_rol text, p_global boolean, p_ahora timestamp with time zone, p_fin_dia timestamp with time zone|TABLE(tarea_id uuid, perfil_id uuid, inversionista_id uuid, nombre text, responsable_id uuid, vence_en timestamp with time zone, bucket text)"
 },
 "private.sla_leads_operativos()": {
  "def": "8d478d783e4c591662388ddf7405058a",
  "src": "fd8f5800b253b137e82e666b9a89ab0a",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|uuid[]|130901f18423506211fa55f95ef1e834",
  "extra": "sql|false|false|100|0|-|false||uuid[]"
 }
}$esperado_postflight_m2$::jsonb) e loop
    v_oid := pg_catalog.to_regprocedure(v_firma);
    if v_oid is null then
      raise exception 'POSTFLIGHT M2: no existe %', v_firma;
    end if;
    select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)), pg_catalog.md5(p.prosrc), pg_catalog.concat_ws('|', pg_catalog.pg_get_userbyid(p.proowner), p.proacl::text, pg_catalog.array_to_string(p.proconfig, ','),
         p.prosecdef::text, p.provolatile::text, p.proparallel::text, p.prorettype::pg_catalog.regtype::text,
         pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), ''))), (select pg_catalog.concat_ws('|', l.lanname, p.proisstrict::text, p.proleakproof::text, p.procost::text, p.prorows::text,
         p.prosupport::text, p.proretset::text, pg_catalog.pg_get_function_arguments(p.oid), pg_catalog.pg_get_function_result(p.oid))
         from pg_catalog.pg_language l where l.oid = p.prolang)
      into v_md5_def, v_md5_src, v_meta, v_extra from pg_catalog.pg_proc p where p.oid = v_oid;
    if v_md5_def is distinct from v_esp->>'def' or v_md5_src is distinct from v_esp->>'src' then
      raise exception 'POSTFLIGHT M2: % no es la versión ensayada (md5 def % / prosrc %; esperado % / %)', v_firma, v_md5_def, v_md5_src, v_esp->>'def', v_esp->>'src';
    end if;
    if v_meta is distinct from v_esp->>'meta' then
      raise exception 'POSTFLIGHT M2: dueño, ACL, configuración, DEFINER, volatilidad o comentario de % distintos (%)', v_firma, v_meta;
    end if;
    if v_extra is distinct from v_esp->>'extra' then
      raise exception 'POSTFLIGHT M2: otro atributo de % distinto (lenguaje, strict, leakproof, coste, filas, soporte, argumentos o resultado): %', v_firma, v_extra;
    end if;
  end loop;
  if not pg_catalog.has_function_privilege('authenticated', 'crm.avisos_sla_resumen_v2_fn()', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'crm.avisos_sla_resumen_v2_fn()', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', 'crm.avisos_sla_resumen_v2_fn()', 'EXECUTE') then
    raise exception 'POSTFLIGHT M2: la ACL efectiva del resumen cambió (debe ser solo authenticated)';
  end if;
  -- ACL EFECTIVA (también PUBLIC y herencia) y ACL guardada: las piezas privadas de la ventana, solo para su dueño.
  if exists (select 1 from pg_catalog.pg_roles r, pg_catalog.unnest('{"private.sla_operacion_ambito(uuid[],boolean)","private.sla_operacion_autorizada_filas(uuid[])","private.sla_operacion_autorizada(uuid[],boolean)"}'::text[]) f(firma)
             where not r.rolsuper and r.rolname <> 'postgres' and not pg_catalog.pg_has_role(r.oid, 'postgres', 'MEMBER')
               and pg_catalog.has_function_privilege(r.oid, f.firma, 'EXECUTE'))
     or exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
                where p.oid = any (array(select pg_catalog.to_regprocedure(x)::oid from pg_catalog.unnest('{"private.sla_operacion_ambito(uuid[],boolean)","private.sla_operacion_autorizada_filas(uuid[])","private.sla_operacion_autorizada(uuid[],boolean)"}'::text[]) x))
                  and a.grantee <> p.proowner) then
    raise exception 'POSTFLIGHT M2: alguna pieza privada de la ventana tiene EXECUTE fuera del dueño';
  end if;
  -- Guardianes del SLA dentro de la MISMA transacción: si alguno no da «OK: …» (o da NULL), no queda nada aplicado.
  v_ok := private.assert_sla_nucleo();
  if (v_ok like 'OK: %') is not true then raise exception 'POSTFLIGHT M2: assert_sla_nucleo no da OK: %', v_ok; end if;
  v_ok := private.assert_cola_v3();
  if (v_ok like 'OK: %') is not true then raise exception 'POSTFLIGHT M2: assert_cola_v3 no da OK: %', v_ok; end if;
  v_ok := private.assert_sla_avisos();
  if (v_ok like 'OK: %') is not true then raise exception 'POSTFLIGHT M2: assert_sla_avisos no da OK: %', v_ok; end if;
end $m2$;
commit;
$migracion_20261017054426$),
    pg_catalog.jsonb_build_array('20261017054427', 'crm_sla_cola_por_filas', $migracion_20261017054427$-- SLA paso 3a · M3: la cola del día POR FILAS (plan «foto del SLA», Fase 3). v2. Requiere M1 (20261017054425_crm_sla_ventana_por_filas) y M2 (20261017054426_crm_sla_avisos_por_filas).
-- crm.cola_accion_v3_fn(...) filtra, cuenta, ordena y pagina sobre private.sla_operacion_autorizada_filas(null::uuid[])
-- (firma TIPADA: ninguna sobrecarga puede ganar la resolución; núcleo UNA vez; identidad por fila con WITH ORDINALITY) y
-- arma jsonb solo para la página. Mismo jsonb byte a byte para todos los argumentos, mismos errores y en el mismo orden
-- (límite/filtros 22023 → autoridad 42501 → clientes 22000 → cursor) y misma huella de cursor. Si alguna candidata de lead
-- tiene clave NULL («pendiente sin acción»: empates sin desempate), la página sale del algoritmo ANTERIOR con la misma
-- secuencia de entrada, así que el orden también es el mismo. Clientes por private.tareas_clientes_autorizadas como antes.
-- Misma firma, ACL (solo authenticated), DEFINER, search_path y volatilidad; COMMENT ON actualizado.
-- private.assert_cola_v3(): depende de _filas; la puerta solo llama a su LISTA PERMITIDA de piezas privadas; re-sello de la
-- puerta (6096aa636688f01677327c5504ffaa8b; quote_all_identifiers fijado en el guardián). Resto de controles intactos. (Autorizado por Miguel, 16/10 23:55.)
-- Historial: se niega si su versión ya está en el índice. Evidencia y cifras: supabase/scripts/sla-por-filas/LEEME.md.
-- Antes:   cola prosrc 828989da281bc8c32fab812542e86ba9 · Después: 34b5abf032aac26cf5453f6e85f3d370 · familia SLA 64 · f9ea903841b9186ac985e103e050e6d5
-- REVERTIR: supabase/scripts/sla-por-filas/reversa-m3.sql como MIGRACIÓN NUEVA (y registrar-reversa-m3.sql).
begin;
set local lock_timeout = '5s';
set local search_path = '';
set local quote_all_identifiers = off;
do $m3$
declare
  v_oid oid; v_firma text; v_esp jsonb; v_def text; v_md5_def text; v_md5_src text; v_meta text; v_extra text; v_ok text;
  v_ya boolean;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm_sla_por_filas'));
  -- Historial (Codex P1): si ESTA versión ya está en el índice de migraciones, no se vuelve a aplicar. Una reaplicación
  -- tras reversas registradas va con versiones NUEVAS; «commit hecho, registro pendiente» se cierra con
  -- registrar-indice.sql, sin volver a ejecutar el DDL. En una base sin índice (banco), no aplica.
  if pg_catalog.to_regclass('supabase_migrations.schema_migrations') is not null then
    execute 'select exists (select 1 from supabase_migrations.schema_migrations m where m.version = $1)' into v_ya using '20261017054427';
    if v_ya then
      raise exception 'PREFLIGHT M3: la versión 20261017054427 ya está en supabase_migrations.schema_migrations; no se aplica otra vez (una reaplicación tras reversas registradas va con versiones nuevas)';
    end if;
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)')) = '34b5abf032aac26cf5453f6e85f3d370' then
    raise exception 'PREFLIGHT M3: ya aplicada (la cola v3 ya tiene el cuerpo nuevo 34b5abf032aac26cf5453f6e85f3d370); no se aplica dos veces';
  end if;
  for v_firma, v_esp in select e.key, e.value from pg_catalog.jsonb_each($esperado_preflight_m3${
 "private.sla_operacion_ambito(uuid[],boolean)": {
  "def": "e843f6cd039b92a5fcd1e629d6ad4138",
  "src": "b75fb4c86471cba36687c15986bd60dc",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|record|ba5d2ec895f334e53417ef36cffebb2b",
  "extra": "plpgsql|false|false|100|1000|-|true|p_lead_ids uuid[], p_incluir_operacion boolean|TABLE(actor uuid, rol text, es_global boolean, visibles uuid[])"
 },
 "private.sla_operacion_autorizada_filas(uuid[])": {
  "def": "5aa191534358b819d8b8f0254f91c471",
  "src": "250863962d4a0a5adb564d2e7c8a39cb",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|record|3094558e14db3ba8d8fa684e5ce99ca5",
  "extra": "plpgsql|false|false|100|1000|-|true|p_lead_ids uuid[]|TABLE(es_cabecera boolean, lead_id uuid, estado jsonb, senales jsonb, accion_pendiente jsonb, lead jsonb, accion_revision jsonb, accion jsonb, cabecera jsonb)"
 },
 "private.sla_operacion_autorizada(uuid[],boolean)": {
  "def": "4cdaa81a538473ea322ca5e4835652d4",
  "src": "7d8c87935730be5f3b43559dc05e977a",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|jsonb|8dd4b7845c20f10e7f9cf1aa84c58ca9",
  "extra": "plpgsql|false|false|100|0|-|false|p_lead_ids uuid[], p_incluir_operacion boolean|jsonb"
 },
 "private.assert_sla_nucleo()": {
  "def": "a938047d5c98aa009984a9e836b2fc9d",
  "src": "7f5a08dde907b343b8562b6024eba110",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\",quote_all_identifiers=off|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e",
  "extra": "plpgsql|false|false|100|0|-|false||text"
 },
 "private.assert_sla_avisos()": {
  "def": "1cbce7c3cdd9d39e61e9c26af29a9f7e",
  "src": "d307e5acaa84517072d8f65db882c1f3",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\",quote_all_identifiers=off|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e",
  "extra": "plpgsql|false|false|100|0|-|false||text"
 },
 "crm.avisos_sla_resumen_v2_fn()": {
  "def": "82a7cabdae761ea7b3707db9f9c62452",
  "src": "3387f3aff90b1e47e05bcddea14a91e3",
  "meta": "postgres|{postgres=X/postgres,authenticated=X/postgres}|search_path=\"\"|true|s|u|jsonb|0003d4f1991eab3f3d0105e52a9a9f2a",
  "extra": "plpgsql|false|false|100|0|-|false||jsonb"
 },
 "crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)": {
  "def": "1ec76074c9b5650cb8bac4c79440eccb",
  "src": "828989da281bc8c32fab812542e86ba9",
  "meta": "postgres|{postgres=X/postgres,authenticated=X/postgres}|search_path=\"\"|true|s|u|jsonb|4fc30931ad31e222dc19423d89befb12",
  "extra": "plpgsql|false|false|100|0|-|false|p_limite integer DEFAULT 50, p_senal text DEFAULT 'todas'::text, p_etapa text DEFAULT NULL::text, p_analista_id uuid DEFAULT NULL::uuid, p_cursor jsonb DEFAULT NULL::jsonb|jsonb"
 },
 "private.assert_cola_v3()": {
  "def": "162fe9e053c8b57f8b501dadbe2afca7",
  "src": "97d9d1b96c9b9a882a6518b890d082c0",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|text|dd5dee9c51f0f514a8f4c05582216dd2",
  "extra": "plpgsql|false|false|100|0|-|false||text"
 },
 "private.sla_operacion_leads(uuid[],boolean,uuid[],timestamp with time zone)": {
  "def": "0abdf640b5f4f10ab2e85b6bd2494522",
  "src": "e47f610fb4cde0741f2a22c3e2e7ee2c",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|record|928c35d75cc268f2319658ee77878148",
  "extra": "plpgsql|false|false|100|1000|-|true|p_lead_ids uuid[], p_global boolean, p_visibles uuid[], p_ahora timestamp with time zone|TABLE(lead_id uuid, estado jsonb, accion_atencion jsonb, accion_supervision jsonb, senales jsonb, presentacion jsonb)"
 },
 "private.tareas_clientes_autorizadas(uuid,uuid[],text,boolean,timestamp with time zone,timestamp with time zone)": {
  "def": "234ee27f745ef1817be0e0cbdd2b2e25",
  "src": "8d02b260a0aa0bc50536afdc82c32ba3",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|record|0ca7eed9b41e7884ae26930b1e633c75",
  "extra": "plpgsql|false|false|100|1000|-|true|p_uid uuid, p_visibles uuid[], p_rol text, p_global boolean, p_ahora timestamp with time zone, p_fin_dia timestamp with time zone|TABLE(tarea_id uuid, perfil_id uuid, inversionista_id uuid, nombre text, responsable_id uuid, vence_en timestamp with time zone, bucket text)"
 },
 "private.sla_leads_operativos()": {
  "def": "8d478d783e4c591662388ddf7405058a",
  "src": "fd8f5800b253b137e82e666b9a89ab0a",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|uuid[]|130901f18423506211fa55f95ef1e834",
  "extra": "sql|false|false|100|0|-|false||uuid[]"
 }
}$esperado_preflight_m3$::jsonb) e loop
    v_oid := pg_catalog.to_regprocedure(v_firma);
    if v_oid is null then
      raise exception 'PREFLIGHT M3: no existe %', v_firma;
    end if;
    select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)), pg_catalog.md5(p.prosrc), pg_catalog.concat_ws('|', pg_catalog.pg_get_userbyid(p.proowner), p.proacl::text, pg_catalog.array_to_string(p.proconfig, ','),
         p.prosecdef::text, p.provolatile::text, p.proparallel::text, p.prorettype::pg_catalog.regtype::text,
         pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), ''))), (select pg_catalog.concat_ws('|', l.lanname, p.proisstrict::text, p.proleakproof::text, p.procost::text, p.prorows::text,
         p.prosupport::text, p.proretset::text, pg_catalog.pg_get_function_arguments(p.oid), pg_catalog.pg_get_function_result(p.oid))
         from pg_catalog.pg_language l where l.oid = p.prolang)
      into v_md5_def, v_md5_src, v_meta, v_extra from pg_catalog.pg_proc p where p.oid = v_oid;
    if v_md5_def is distinct from v_esp->>'def' or v_md5_src is distinct from v_esp->>'src' then
      raise exception 'PREFLIGHT M3: % no es la versión revisada (md5 def % / prosrc %; esperado % / %)', v_firma, v_md5_def, v_md5_src, v_esp->>'def', v_esp->>'src';
    end if;
    if v_meta is distinct from v_esp->>'meta' then
      raise exception 'PREFLIGHT M3: dueño, ACL, configuración, DEFINER, volatilidad o comentario de % distintos (%)', v_firma, v_meta;
    end if;
    if v_extra is distinct from v_esp->>'extra' then
      raise exception 'PREFLIGHT M3: otro atributo de % distinto (lenguaje, strict, leakproof, coste, filas, soporte, argumentos o resultado): %', v_firma, v_extra;
    end if;
  end loop;
  -- 1. Cola por filas y su comentario.
  v_def := $ddl_m3_cola$CREATE OR REPLACE FUNCTION crm.cola_accion_v3_fn(p_limite integer DEFAULT 50, p_senal text DEFAULT 'todas'::text, p_etapa text DEFAULT NULL::text, p_analista_id uuid DEFAULT NULL::uuid, p_cursor jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid()); v_rol text; v_global boolean; v_visibles uuid[];
  v_cab jsonb; v_ahora timestamptz; v_medianoche timestamptz;
  v_clientes jsonb; v_clientes_filtrados jsonb; v_filtros jsonb; v_contexto text; v_orden text;
  v_prioridad integer; v_referencia timestamptz; v_clave text;
  v_err_estado text; v_err_mensaje text; v_err_detalle text; v_err_pista text;
  v_tot_leads jsonb; v_cand_leads integer; v_rest_leads integer; v_items_leads jsonb;
  v_totales jsonb; v_cand_clientes jsonb; v_rest_clientes integer; v_total integer; v_items jsonb;
  v_restantes integer; v_anteriores integer; v_siguiente jsonb; v_ultima jsonb;
  v_proximo_cliente timestamptz;
  v_hay_nulos boolean; v_cand_leads_json jsonb; v_candidatas jsonb;
begin
  if p_limite is null or p_limite not between 1 and 200
    or private.sla_filtros_cola_validos(p_senal, p_etapa) is not true then
    raise exception 'Filtros SLA invalidos o limite fuera de 1 a 200' using errcode = '22023';
  end if;
  -- Cola por filas (paso 3a, 17/10/2026): mismo contrato, errores y orden de errores que la v3 anterior
  -- (límite/filtros 22023 → autoridad 42501 → clientes → cursor). Filtra, cuenta, ordena y pagina sobre
  -- private.sla_operacion_autorizada_filas (el núcleo se evalúa UNA vez) y arma jsonb solo para la página.
  -- Pre-lectura del cursor: los mismos casts y en el mismo orden que antes; su error se guarda y se lanza
  -- más abajo, en el punto de siempre. Con un cursor inválido la página ya calculada se descarta.
  if p_cursor is not null and jsonb_typeof(p_cursor) = 'object' then
    begin
      v_prioridad := (p_cursor->>'prioridad')::integer;
      v_referencia := (p_cursor->>'referencia_en')::timestamptz;
      v_clave := p_cursor->>'clave';
    exception when others then
      get stacked diagnostics v_err_estado = returned_sqlstate, v_err_mensaje = message_text,
        v_err_detalle = pg_exception_detail, v_err_pista = pg_exception_hint;
      v_prioridad := null; v_referencia := null; v_clave := null;
    end;
  end if;

  -- 1) UNA consulta: autoridad + núcleo una sola vez (f), cabecera, huella de orden (TODAS las filas
  --    autorizadas, orden por lead->>'id' como texto), totales y página de leads. d lee cada columna con la
  --    semántica de «f.value->'clave'» del bloque jsonb (SQL NULL → JSON null). Cada fila lleva su identidad
  --    (fila = ordinalidad de la ventana): la página se reconstruye por fila, nunca por lead_id.
  with f as materialized (
    select x.fila, x.es_cabecera, x.cabecera, x.lead_id, x.estado, x.senales, x.accion_pendiente, x.lead, x.accion_revision, x.accion
    from private.sla_operacion_autorizada_filas(null::uuid[]) with ordinality
      as x(es_cabecera, lead_id, estado, senales, accion_pendiente, lead, accion_revision, accion, cabecera, fila)
  ), d as not materialized (
    select f.fila, f.lead_id, coalesce(f.estado, 'null'::jsonb) as estado, coalesce(f.senales, 'null'::jsonb) as senales,
      coalesce(f.accion_pendiente, 'null'::jsonb) as accion_pendiente, coalesce(f.lead, 'null'::jsonb) as lead,
      coalesce(f.accion_revision, 'null'::jsonb) as accion_revision, coalesce(f.accion, 'null'::jsonb) as accion
    from f where not f.es_cabecera
  ), l as not materialized (
    select d.* from d
    where (p_etapa is null or d.lead->>'etapa' = p_etapa)
      and (p_analista_id is null or d.lead->>'analista_id' = p_analista_id::text)
  ), cand as materialized (
    -- Solo lo necesario para ordenar: la acción elegida y las claves de orden. Las claves salen de
    -- «accion || {clave}», que da las mismas prioridad/referencia_en/clave que el objeto completo.
    select c.fila, c.lead_id, c.accion, (k.v->>'prioridad')::integer as prioridad,
      (k.v->>'referencia_en')::timestamptz as referencia, (k.v->>'clave') collate "C" as clave
    from (
      select l.fila, l.lead_id, l.lead,
        case when p_senal = 'pendientes' then l.accion_pendiente
          when p_senal = 'todas' then l.accion
          else coalesce((select a.value from jsonb_array_elements(l.estado->'avisos') a
            where a.value->>'bucket' = case p_senal
              when 'tareas_vencidas' then 'tarea_vencida' when 'seguimientos_pendientes' then 'seguimiento'
              when 'revisiones' then 'revision_comercial' else p_senal end limit 1),
            nullif(l.accion, 'null'::jsonb), l.accion_revision) end as accion
      from l
      where (p_senal = 'todas' and l.accion <> 'null'::jsonb)
        or (p_senal <> 'todas' and (l.senales->>p_senal)::boolean is true)
    ) c
    cross join lateral (select c.accion || jsonb_build_object('clave', 'lead:' || (c.lead->>'id')) as v) k
  ), post as not materialized (
    select c.* from cand c where p_cursor is null or
      (c.prioridad, coalesce(c.referencia, 'infinity'::timestamptz), c.clave) >
      (v_prioridad, coalesce(v_referencia, 'infinity'::timestamptz), v_clave collate "C")
  ), pagina as materialized (
    select p.* from post p order by p.prioridad, p.referencia nulls last, p.clave limit p_limite
  )
  select
    (select f.cabecera from f where f.es_cabecera),
    (select md5('[' || coalesce(string_agg(jsonb_build_array(d.lead->>'id', d.accion, d.accion_pendiente, d.senales)::text,
        ', ' order by d.lead->>'id'), '') || ']') from d),
    (select jsonb_build_object(
      'pendientes', coalesce(cardinality(array_agg(true) filter (where (l.senales->>'pendientes')::boolean)), 0),
      'primera_atencion', coalesce(cardinality(array_agg(true) filter (where (l.senales->>'primera_atencion')::boolean)), 0),
      'tareas_vencidas', coalesce(cardinality(array_agg(true) filter (where (l.senales->>'tareas_vencidas')::boolean)), 0),
      'seguimientos_pendientes', coalesce(cardinality(array_agg(true) filter (where (l.senales->>'seguimientos_pendientes')::boolean)), 0),
      'revisiones', coalesce(cardinality(array_agg(true) filter (where (l.senales->>'revisiones')::boolean)), 0),
      'datos_incompletos', coalesce(cardinality(array_agg(true) filter (where (l.senales->>'datos_incompletos')::boolean)), 0),
      'por_repartir', coalesce(cardinality(array_agg(true) filter (where (l.senales->>'por_repartir')::boolean)), 0))
      from l),
    (select coalesce(cardinality(array_agg(true)), 0) from cand),
    (select coalesce(cardinality(array_agg(true)), 0) from post),
    (select coalesce(jsonb_agg(p.accion || jsonb_build_object(
        'estado', d.estado, 'lead', d.lead, 'senales', d.senales,
        'clave', 'lead:' || (d.lead->>'id'),
        'sujeto', jsonb_build_object('tipo', 'lead', 'id', d.lead->'id', 'nombre', d.lead->'nombre_completo'))
        order by p.prioridad, p.referencia nulls last, p.clave), '[]'::jsonb)
      from pagina p join d on d.fila = p.fila),
    -- «Pendiente sin acción» (acción no objeto → clave NULL, empates sin desempate): para dar EXACTAMENTE el orden
    -- de antes, se arma la secuencia completa de candidatas de leads como antes (orden de la ventana) y la página
    -- se calcula abajo con el algoritmo anterior. Solo se evalúa si hace falta (caso raro).
    (select coalesce(bool_or(c.clave is null), false) from cand c),
    case when (select bool_or(c.clave is null) from cand c) then
      (select coalesce(jsonb_agg(c.accion || jsonb_build_object(
          'estado', d.estado, 'lead', d.lead, 'senales', d.senales,
          'clave', 'lead:' || (d.lead->>'id'),
          'sujeto', jsonb_build_object('tipo', 'lead', 'id', d.lead->'id', 'nombre', d.lead->'nombre_completo'))
          order by d.lead_id, c.fila), '[]'::jsonb)
        from cand c join d on d.fila = c.fila) end
    into v_cab, v_orden, v_tot_leads, v_cand_leads, v_rest_leads, v_items_leads, v_hay_nulos, v_cand_leads_json;
  v_ahora := (v_cab->>'calculado_en')::timestamptz;

  -- 2) CLIENTES: el mismo actor y ámbito crudo, el MISMO reloj y la próxima medianoche de Lima (sin cambios).
  v_rol := private.rol_crm(v_uid);
  v_global := coalesce(private.es_lector_global(), false);
  v_visibles := array(select x from private.vendedor_ids_visibles(v_uid) x order by x);
  v_medianoche := (((v_ahora at time zone 'America/Lima')::date + 1)::timestamp) at time zone 'America/Lima';
  select coalesce(jsonb_agg(jsonb_build_object(
      'clave', 'tarea:' || c.tarea_id::text, 'tarea_id', c.tarea_id,
      'lead_id', null::uuid, 'lead', null::jsonb, 'estado', null::jsonb,
      'bucket', c.bucket,
      'prioridad', case c.bucket when 'tarea_vencida' then 20 else 30 end,
      'severidad', case c.bucket when 'tarea_vencida' then 'critica' else 'media' end,
      'referencia_en', c.vence_en, 'responsable_id', c.responsable_id,
      'senales', jsonb_build_object(
        'primera_atencion', false, 'tareas_vencidas', c.bucket = 'tarea_vencida',
        'seguimientos_pendientes', false, 'revisiones', false, 'datos_incompletos', false,
        'por_repartir', false, 'pendientes', c.bucket = 'tarea_vencida'),
      'sujeto', jsonb_build_object('tipo', 'cliente', 'perfil_id', c.perfil_id,
        'inversionista_id', c.inversionista_id, 'nombre', c.nombre))
    order by c.vence_en, c.tarea_id), '[]'::jsonb)
    into v_clientes
  from private.tareas_clientes_autorizadas(v_uid, v_visibles, v_rol, v_global, v_ahora, v_medianoche) c;

  -- 3) Contexto del cursor: misma expresión que antes; «orden» viene de la consulta grande (mismo md5), así que
  --    los cursores ya emitidos siguen valiendo.
  v_filtros := jsonb_build_object('senal', p_senal, 'etapa', p_etapa, 'analista_id', p_analista_id);
  v_contexto := md5(jsonb_build_object('version', 3, 'modelo_avisos', v_cab->'modelo_avisos',
    'ambito', v_cab->'contexto_ambito', 'filtros', v_filtros, 'limite', p_limite, 'modo', v_cab->'modo',
    'orden', v_orden,
    'clientes', (select md5(coalesce(jsonb_agg(jsonb_build_array(c.value->'clave', c.value->'responsable_id',
      c.value->'sujeto', c.value->'referencia_en', c.value->'senales')
      order by c.value->>'clave'), '[]'::jsonb)::text)
      from jsonb_array_elements(v_clientes) c),
    'revision', v_cab->'control_revision', 'politica', v_cab->'politica_operativa_id')::text);
  if p_cursor is not null then
    if jsonb_typeof(p_cursor) <> 'object' then
      raise exception 'Cursor SLA invalido' using errcode = '22023';
    end if;
    if cardinality(array(select jsonb_object_keys(p_cursor))) <> 5
      or not p_cursor ?& array['version', 'contexto', 'prioridad', 'referencia_en', 'clave']
      or p_cursor->'version' <> '2'::jsonb
      or jsonb_typeof(p_cursor->'contexto') <> 'string'
      or jsonb_typeof(p_cursor->'prioridad') <> 'number'
      or jsonb_typeof(p_cursor->'referencia_en') not in ('string', 'null')
      or jsonb_typeof(p_cursor->'clave') <> 'string' then
      raise exception 'Cursor SLA invalido' using errcode = '22023';
    end if;
    if p_cursor->>'contexto' is distinct from v_contexto then
      raise exception 'Cursor incompatible; reinicia la paginacion' using errcode = '22023';
    end if;
    -- Error diferido de la pre-lectura: los 4 SQLSTATE que se traducen a «Cursor SLA invalido»; los demás salen tal cual.
    if v_err_estado in ('22P02', '22008', '22007', '22003') then
      raise exception 'Cursor SLA invalido' using errcode = '22023';
    elsif v_err_estado is not null then
      if v_err_detalle <> '' and v_err_pista <> '' then
        raise exception '%', v_err_mensaje using errcode = v_err_estado, detail = v_err_detalle, hint = v_err_pista;
      elsif v_err_detalle <> '' then
        raise exception '%', v_err_mensaje using errcode = v_err_estado, detail = v_err_detalle;
      elsif v_err_pista <> '' then
        raise exception '%', v_err_mensaje using errcode = v_err_estado, hint = v_err_pista;
      else
        raise exception '%', v_err_mensaje using errcode = v_err_estado;
      end if;
    end if;
    if (p_cursor->>'prioridad') !~ '^[0-9]+$'
      or v_prioridad not in (0, 10, 20, 30, 40, 50, 60, 70)
      or v_clave !~ '^(lead|tarea):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or (v_referencia is not null and not isfinite(v_referencia)) then
      raise exception 'Cursor SLA invalido' using errcode = '22023';
    end if;
  end if;

  -- 4) Clientes filtrados (p_etapa los excluye; p_analista_id filtra por responsable), sus totales y candidatas.
  --    Totales = leads filtrados + clientes filtrados (las dos ramas de la unión).
  select coalesce(jsonb_agg(c.value), '[]'::jsonb) into v_clientes_filtrados
  from jsonb_array_elements(v_clientes) c
  where p_etapa is null
    and (p_analista_id is null or c.value->>'responsable_id' = p_analista_id::text);
  select jsonb_build_object(
    'pendientes', (v_tot_leads->>'pendientes')::integer + coalesce(cardinality(array_agg(true) filter (where (c.value->'senales'->>'pendientes')::boolean)), 0),
    'primera_atencion', (v_tot_leads->>'primera_atencion')::integer + coalesce(cardinality(array_agg(true) filter (where (c.value->'senales'->>'primera_atencion')::boolean)), 0),
    'tareas_vencidas', (v_tot_leads->>'tareas_vencidas')::integer + coalesce(cardinality(array_agg(true) filter (where (c.value->'senales'->>'tareas_vencidas')::boolean)), 0),
    'seguimientos_pendientes', (v_tot_leads->>'seguimientos_pendientes')::integer + coalesce(cardinality(array_agg(true) filter (where (c.value->'senales'->>'seguimientos_pendientes')::boolean)), 0),
    'revisiones', (v_tot_leads->>'revisiones')::integer + coalesce(cardinality(array_agg(true) filter (where (c.value->'senales'->>'revisiones')::boolean)), 0),
    'datos_incompletos', (v_tot_leads->>'datos_incompletos')::integer + coalesce(cardinality(array_agg(true) filter (where (c.value->'senales'->>'datos_incompletos')::boolean)), 0),
    'por_repartir', (v_tot_leads->>'por_repartir')::integer + coalesce(cardinality(array_agg(true) filter (where (c.value->'senales'->>'por_repartir')::boolean)), 0),
    'clientes', coalesce(cardinality(array_agg(true)), 0))
    into v_totales
  from jsonb_array_elements(v_clientes_filtrados) c;
  select coalesce(jsonb_agg(c.value - 'responsable_id'), '[]'::jsonb) into v_cand_clientes
  from jsonb_array_elements(v_clientes_filtrados) c
  where p_senal = 'todas' or (c.value->'senales'->>p_senal)::boolean is true;
  v_total := v_cand_leads + jsonb_array_length(v_cand_clientes);

  -- 5) Página = los p_limite primeros de (página de leads ∪ clientes posteriores al cursor), mismo keyset y orden.
  --    Con claves NULL entre los leads, el algoritmo anterior sobre la misma secuencia de entrada (mismo orden).
  if v_hay_nulos then
    v_candidatas := v_cand_leads_json || v_cand_clientes;
    v_total := jsonb_array_length(v_candidatas);
    with ordenadas as (
      select f.value, (f.value->>'prioridad')::integer as prioridad,
        (f.value->>'referencia_en')::timestamptz as referencia, (f.value->>'clave') collate "C" as clave
      from jsonb_array_elements(v_candidatas) f
    ), posteriores as (
      select o.* from ordenadas o where p_cursor is null or
        (o.prioridad, coalesce(o.referencia, 'infinity'::timestamptz), o.clave) >
        (v_prioridad, coalesce(v_referencia, 'infinity'::timestamptz), v_clave collate "C")
    ), pagina as (
      select p.* from posteriores p order by p.prioridad, p.referencia nulls last, p.clave limit p_limite
    )
    select (select coalesce(cardinality(array_agg(x.clave)), 0) from posteriores x),
      coalesce((select jsonb_agg(p.value order by p.prioridad, p.referencia nulls last, p.clave) from pagina p), '[]'::jsonb)
      into v_restantes, v_items;
  else
    with ordenadas as (
      select u.value, u.es_lead, (u.value->>'prioridad')::integer as prioridad,
        (u.value->>'referencia_en')::timestamptz as referencia, (u.value->>'clave') collate "C" as clave
      from (select x.value, true as es_lead from jsonb_array_elements(v_items_leads) x
            union all
            select x.value, false from jsonb_array_elements(v_cand_clientes) x) u
    ), posteriores as (
      select o.* from ordenadas o where p_cursor is null or
        (o.prioridad, coalesce(o.referencia, 'infinity'::timestamptz), o.clave) >
        (v_prioridad, coalesce(v_referencia, 'infinity'::timestamptz), v_clave collate "C")
    ), pagina as (
      select p.* from posteriores p order by p.prioridad, p.referencia nulls last, p.clave limit p_limite
    )
    select (select coalesce(cardinality(array_agg(true) filter (where not x.es_lead)), 0) from posteriores x),
      coalesce((select jsonb_agg(p.value order by p.prioridad, p.referencia nulls last, p.clave) from pagina p), '[]'::jsonb)
      into v_rest_clientes, v_items;
    v_restantes := v_rest_leads + v_rest_clientes;
  end if;
  v_anteriores := v_total - v_restantes;
  if v_restantes > p_limite then
    v_ultima := v_items->(jsonb_array_length(v_items) - 1);
    v_siguiente := jsonb_build_object('version', 2, 'contexto', v_contexto, 'prioridad', v_ultima->'prioridad',
      'referencia_en', v_ultima->'referencia_en', 'clave', v_ultima->'clave');
  end if;

  -- 6) proximo_cambio_en: leads (cabecera), próximo vencimiento de cliente > ahora (de v_clientes) y medianoche de Lima.
  select min((c.value->>'referencia_en')::timestamptz) into v_proximo_cliente
  from jsonb_array_elements(v_clientes) c
  where (c.value->>'referencia_en')::timestamptz > v_ahora;

  return jsonb_build_object('version', 3, 'modelo_avisos', v_cab->'modelo_avisos',
    'proximo_cambio_en', least(nullif(v_cab->>'proximo_cambio_en', '')::timestamptz, v_proximo_cliente, v_medianoche),
    'modo', v_cab->'modo', 'control_revision', v_cab->'control_revision',
    'calculado_en', v_cab->'calculado_en', 'politica_operativa_id', v_cab->'politica_operativa_id',
    'politica_operativa_version', v_cab->'politica_operativa_version',
    'total_items', v_total, 'hay_mas', v_restantes > p_limite, 'totales', v_totales, 'items', v_items,
    'filtros', v_filtros, 'limite', p_limite, 'cursor_siguiente', v_siguiente,
    'rango', jsonb_build_object('desde', case when jsonb_array_length(v_items) = 0 then 0 else v_anteriores + 1 end,
      'hasta', case when jsonb_array_length(v_items) = 0 then 0 else v_anteriores + jsonb_array_length(v_items) end));
end;
$function$
$ddl_m3_cola$;
  if pg_catalog.md5(v_def) is distinct from '6096aa636688f01677327c5504ffaa8b' then
    raise exception 'PREFLIGHT M3: el DDL de la cola v3 no es el ensayado (md5 esperado 6096aa636688f01677327c5504ffaa8b)';
  end if;
  execute v_def;
  execute $c_col$comment on function crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb) is 'Cola del dia v3 (plan 28/09/2026): UNA cola con las filas de leads de la ventana SLA (identicas a la v2) y las tareas de clientes del dia; identidad tipada clave = lead:<uuid> | tarea:<uuid>; cursor version 2 cuyo contexto cubre a los clientes (los de la v2 se rechazan, 22023); p_etapa no nulo excluye clientes; p_analista_id filtra al responsable; totales completos antes del limite + clientes; proximo_cambio_en incluye el proximo vencimiento de cliente y la medianoche de Lima; sin telefono en el payload. SECURITY DEFINER justificado: lee la ventana POR FILAS private.sla_operacion_autorizada_filas(null::uuid[]) (DEFINER sin grants externos; paso 3a, 17/10/2026: filtra, cuenta, ordena y pagina sobre filas y arma jsonb solo para la pagina; con claves NULL de «pendiente sin accion», el algoritmo anterior) y ejecuta el helper INVOKER como dueno; el actor es auth.uid(), nunca un parametro. No sustituye a la v2.'$c_col$;
  if pg_catalog.md5(pg_catalog.pg_get_functiondef('crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)'::pg_catalog.regprocedure)) is distinct from '6096aa636688f01677327c5504ffaa8b' then
    raise exception 'PREFLIGHT M3: la puerta instalada no da el sello ensayado (6096aa636688f01677327c5504ffaa8b)';
  end if;
  -- 2. Guardián de la cola: dependencia, lista permitida, re-sello de la puerta.
  v_def := pg_catalog.pg_get_functiondef('private.assert_cola_v3()'::pg_catalog.regprocedure);
  if pg_catalog.strpos(v_def, $antes$ SET search_path TO ''
AS $function$
$antes$) = 0 then
    raise exception 'PREFLIGHT M3: no encuentro el texto a cambiar en assert_cola_v3';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$ SET search_path TO ''
AS $function$
$antes$, $despues$ SET search_path TO ''
 SET quote_all_identifiers TO 'off'
AS $function$
$despues$);
  if pg_catalog.strpos(v_def, $antes$    (v_puerta, 'sla_operacion_autorizada'), (v_puerta, 'sla_filtros_cola_validos'),
$antes$) = 0 then
    raise exception 'PREFLIGHT M3: no encuentro el texto a cambiar en assert_cola_v3';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$    (v_puerta, 'sla_operacion_autorizada'), (v_puerta, 'sla_filtros_cola_validos'),
$antes$, $despues$    (v_puerta, 'sla_operacion_autorizada_filas'), (v_puerta, 'sla_filtros_cola_validos'),
$despues$);
  if pg_catalog.strpos(v_def, $antes$  -- 3. La puerta no consulta hechos crudos: todo entra por la ventana SLA y el helper.
$antes$) = 0 then
    raise exception 'PREFLIGHT M3: no encuentro el texto a cambiar en assert_cola_v3';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$  -- 3. La puerta no consulta hechos crudos: todo entra por la ventana SLA y el helper.
$antes$, $despues$  -- 2b. Paso 3a (17/10/2026): la puerta lee la ventana POR FILAS y solo llama a su lista PERMITIDA de piezas privadas
  --     (ni el envoltorio de bloque único, ni el núcleo, ni hechos sin autoridad).
  select regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'gs')
    into strict v_cuerpo from pg_proc p where p.oid = v_puerta::regprocedure;
  if ((select array_agg(distinct m[1] order by m[1]) from regexp_matches(v_cuerpo, '\mprivate\.([a-z0-9_]+)\s*\(', 'g') m)
      <@ array['es_lector_global', 'rol_crm', 'sla_filtros_cola_validos', 'sla_operacion_autorizada_filas',
               'tareas_clientes_autorizadas', 'vendedor_ids_visibles']) is not true then
    raise exception 'COLA_V3: la puerta llama a piezas privadas fuera de su lista permitida (envoltorio, nucleo o hechos sin autoridad)';
  end if;
  -- 3. La puerta no consulta hechos crudos: todo entra por la ventana SLA y el helper.
$despues$);
  if pg_catalog.strpos(v_def, $antes$    (v_puerta, '1ec76074c9b5650cb8bac4c79440eccb'),
$antes$) = 0 then
    raise exception 'PREFLIGHT M3: no encuentro el texto a cambiar en assert_cola_v3';
  end if;
  v_def := pg_catalog.replace(v_def, $antes$    (v_puerta, '1ec76074c9b5650cb8bac4c79440eccb'),
$antes$, $despues$    (v_puerta, '6096aa636688f01677327c5504ffaa8b'),
$despues$);
  if pg_catalog.md5(v_def) is distinct from '5b000de8271604d1c6780dcc2425e90f' then
    raise exception 'PREFLIGHT M3: el DDL de assert_cola_v3 no es el ensayado (md5 esperado 5b000de8271604d1c6780dcc2425e90f)';
  end if;
  execute v_def;
  -- 3. Poscondiciones.
  for v_firma, v_esp in select e.key, e.value from pg_catalog.jsonb_each($esperado_postflight_m3${
 "private.sla_operacion_ambito(uuid[],boolean)": {
  "def": "e843f6cd039b92a5fcd1e629d6ad4138",
  "src": "b75fb4c86471cba36687c15986bd60dc",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|record|ba5d2ec895f334e53417ef36cffebb2b",
  "extra": "plpgsql|false|false|100|1000|-|true|p_lead_ids uuid[], p_incluir_operacion boolean|TABLE(actor uuid, rol text, es_global boolean, visibles uuid[])"
 },
 "private.sla_operacion_autorizada_filas(uuid[])": {
  "def": "5aa191534358b819d8b8f0254f91c471",
  "src": "250863962d4a0a5adb564d2e7c8a39cb",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|record|3094558e14db3ba8d8fa684e5ce99ca5",
  "extra": "plpgsql|false|false|100|1000|-|true|p_lead_ids uuid[]|TABLE(es_cabecera boolean, lead_id uuid, estado jsonb, senales jsonb, accion_pendiente jsonb, lead jsonb, accion_revision jsonb, accion jsonb, cabecera jsonb)"
 },
 "private.sla_operacion_autorizada(uuid[],boolean)": {
  "def": "4cdaa81a538473ea322ca5e4835652d4",
  "src": "7d8c87935730be5f3b43559dc05e977a",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|true|s|u|jsonb|8dd4b7845c20f10e7f9cf1aa84c58ca9",
  "extra": "plpgsql|false|false|100|0|-|false|p_lead_ids uuid[], p_incluir_operacion boolean|jsonb"
 },
 "private.assert_sla_nucleo()": {
  "def": "a938047d5c98aa009984a9e836b2fc9d",
  "src": "7f5a08dde907b343b8562b6024eba110",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\",quote_all_identifiers=off|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e",
  "extra": "plpgsql|false|false|100|0|-|false||text"
 },
 "private.assert_sla_avisos()": {
  "def": "1cbce7c3cdd9d39e61e9c26af29a9f7e",
  "src": "d307e5acaa84517072d8f65db882c1f3",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\",quote_all_identifiers=off|true|s|u|text|d41d8cd98f00b204e9800998ecf8427e",
  "extra": "plpgsql|false|false|100|0|-|false||text"
 },
 "crm.avisos_sla_resumen_v2_fn()": {
  "def": "82a7cabdae761ea7b3707db9f9c62452",
  "src": "3387f3aff90b1e47e05bcddea14a91e3",
  "meta": "postgres|{postgres=X/postgres,authenticated=X/postgres}|search_path=\"\"|true|s|u|jsonb|0003d4f1991eab3f3d0105e52a9a9f2a",
  "extra": "plpgsql|false|false|100|0|-|false||jsonb"
 },
 "crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)": {
  "def": "6096aa636688f01677327c5504ffaa8b",
  "src": "34b5abf032aac26cf5453f6e85f3d370",
  "meta": "postgres|{postgres=X/postgres,authenticated=X/postgres}|search_path=\"\"|true|s|u|jsonb|3f313ac52acf379e299c15a75344f9b6",
  "extra": "plpgsql|false|false|100|0|-|false|p_limite integer DEFAULT 50, p_senal text DEFAULT 'todas'::text, p_etapa text DEFAULT NULL::text, p_analista_id uuid DEFAULT NULL::uuid, p_cursor jsonb DEFAULT NULL::jsonb|jsonb"
 },
 "private.assert_cola_v3()": {
  "def": "5b000de8271604d1c6780dcc2425e90f",
  "src": "862b765b58b1cb7725b375b587733b81",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\",quote_all_identifiers=off|true|s|u|text|dd5dee9c51f0f514a8f4c05582216dd2",
  "extra": "plpgsql|false|false|100|0|-|false||text"
 },
 "private.sla_operacion_leads(uuid[],boolean,uuid[],timestamp with time zone)": {
  "def": "0abdf640b5f4f10ab2e85b6bd2494522",
  "src": "e47f610fb4cde0741f2a22c3e2e7ee2c",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|record|928c35d75cc268f2319658ee77878148",
  "extra": "plpgsql|false|false|100|1000|-|true|p_lead_ids uuid[], p_global boolean, p_visibles uuid[], p_ahora timestamp with time zone|TABLE(lead_id uuid, estado jsonb, accion_atencion jsonb, accion_supervision jsonb, senales jsonb, presentacion jsonb)"
 },
 "private.tareas_clientes_autorizadas(uuid,uuid[],text,boolean,timestamp with time zone,timestamp with time zone)": {
  "def": "234ee27f745ef1817be0e0cbdd2b2e25",
  "src": "8d02b260a0aa0bc50536afdc82c32ba3",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|record|0ca7eed9b41e7884ae26930b1e633c75",
  "extra": "plpgsql|false|false|100|1000|-|true|p_uid uuid, p_visibles uuid[], p_rol text, p_global boolean, p_ahora timestamp with time zone, p_fin_dia timestamp with time zone|TABLE(tarea_id uuid, perfil_id uuid, inversionista_id uuid, nombre text, responsable_id uuid, vence_en timestamp with time zone, bucket text)"
 },
 "private.sla_leads_operativos()": {
  "def": "8d478d783e4c591662388ddf7405058a",
  "src": "fd8f5800b253b137e82e666b9a89ab0a",
  "meta": "postgres|{postgres=X/postgres}|search_path=\"\"|false|s|u|uuid[]|130901f18423506211fa55f95ef1e834",
  "extra": "sql|false|false|100|0|-|false||uuid[]"
 }
}$esperado_postflight_m3$::jsonb) e loop
    v_oid := pg_catalog.to_regprocedure(v_firma);
    if v_oid is null then
      raise exception 'POSTFLIGHT M3: no existe %', v_firma;
    end if;
    select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)), pg_catalog.md5(p.prosrc), pg_catalog.concat_ws('|', pg_catalog.pg_get_userbyid(p.proowner), p.proacl::text, pg_catalog.array_to_string(p.proconfig, ','),
         p.prosecdef::text, p.provolatile::text, p.proparallel::text, p.prorettype::pg_catalog.regtype::text,
         pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), ''))), (select pg_catalog.concat_ws('|', l.lanname, p.proisstrict::text, p.proleakproof::text, p.procost::text, p.prorows::text,
         p.prosupport::text, p.proretset::text, pg_catalog.pg_get_function_arguments(p.oid), pg_catalog.pg_get_function_result(p.oid))
         from pg_catalog.pg_language l where l.oid = p.prolang)
      into v_md5_def, v_md5_src, v_meta, v_extra from pg_catalog.pg_proc p where p.oid = v_oid;
    if v_md5_def is distinct from v_esp->>'def' or v_md5_src is distinct from v_esp->>'src' then
      raise exception 'POSTFLIGHT M3: % no es la versión ensayada (md5 def % / prosrc %; esperado % / %)', v_firma, v_md5_def, v_md5_src, v_esp->>'def', v_esp->>'src';
    end if;
    if v_meta is distinct from v_esp->>'meta' then
      raise exception 'POSTFLIGHT M3: dueño, ACL, configuración, DEFINER, volatilidad o comentario de % distintos (%)', v_firma, v_meta;
    end if;
    if v_extra is distinct from v_esp->>'extra' then
      raise exception 'POSTFLIGHT M3: otro atributo de % distinto (lenguaje, strict, leakproof, coste, filas, soporte, argumentos o resultado): %', v_firma, v_extra;
    end if;
  end loop;
  if not pg_catalog.has_function_privilege('authenticated', 'crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', 'crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)', 'EXECUTE') then
    raise exception 'POSTFLIGHT M3: la ACL efectiva de la cola cambió (debe ser solo authenticated)';
  end if;
  -- ACL EFECTIVA (también PUBLIC y herencia) y ACL guardada: las piezas privadas de la ventana, solo para su dueño.
  if exists (select 1 from pg_catalog.pg_roles r, pg_catalog.unnest('{"private.sla_operacion_ambito(uuid[],boolean)","private.sla_operacion_autorizada_filas(uuid[])","private.sla_operacion_autorizada(uuid[],boolean)"}'::text[]) f(firma)
             where not r.rolsuper and r.rolname <> 'postgres' and not pg_catalog.pg_has_role(r.oid, 'postgres', 'MEMBER')
               and pg_catalog.has_function_privilege(r.oid, f.firma, 'EXECUTE'))
     or exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
                where p.oid = any (array(select pg_catalog.to_regprocedure(x)::oid from pg_catalog.unnest('{"private.sla_operacion_ambito(uuid[],boolean)","private.sla_operacion_autorizada_filas(uuid[])","private.sla_operacion_autorizada(uuid[],boolean)"}'::text[]) x))
                  and a.grantee <> p.proowner) then
    raise exception 'POSTFLIGHT M3: alguna pieza privada de la ventana tiene EXECUTE fuera del dueño';
  end if;
  -- Guardianes del SLA dentro de la MISMA transacción: si alguno no da «OK: …» (o da NULL), no queda nada aplicado.
  v_ok := private.assert_sla_nucleo();
  if (v_ok like 'OK: %') is not true then raise exception 'POSTFLIGHT M3: assert_sla_nucleo no da OK: %', v_ok; end if;
  v_ok := private.assert_cola_v3();
  if (v_ok like 'OK: %') is not true then raise exception 'POSTFLIGHT M3: assert_cola_v3 no da OK: %', v_ok; end if;
  v_ok := private.assert_sla_avisos();
  if (v_ok like 'OK: %') is not true then raise exception 'POSTFLIGHT M3: assert_sla_avisos no da OK: %', v_ok; end if;
end $m3$;
commit;
$migracion_20261017054427$));
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm_sla_por_filas'));
  for v_firma, v_versiones in select e.key, e.value from pg_catalog.jsonb_each(v_tabla) e loop
    v_oid := pg_catalog.to_regprocedure(v_firma);
    if v_oid is null then
      v_et := 'AUSENTE';
    else
      select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)), pg_catalog.md5(p.prosrc), pg_catalog.concat_ws('|', pg_catalog.pg_get_userbyid(p.proowner), p.proacl::text, pg_catalog.array_to_string(p.proconfig, ','),
         p.prosecdef::text, p.provolatile::text, p.proparallel::text, p.prorettype::pg_catalog.regtype::text,
         pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), '')))
        into v_md5_def, v_md5_src, v_meta from pg_catalog.pg_proc p where p.oid = v_oid;
      v_et := null;
      for v_e in select k.key from pg_catalog.jsonb_each(v_versiones) k loop
        if v_versiones->v_e = pg_catalog.jsonb_build_array(v_md5_def, v_md5_src, v_meta) then v_et := v_e; end if;
      end loop;
      v_et := coalesce(v_et, 'DESCONOCIDA def=' || v_md5_def || ' prosrc=' || v_md5_src || ' meta=' || v_meta);
    end if;
    v_actual := v_actual || pg_catalog.jsonb_build_object(v_firma, v_et);
    v_informe := v_informe || E'\n  ' || v_firma || ' = ' || v_et;
  end loop;
  select min(s.key) into v_serie from pg_catalog.jsonb_each(v_estados) s where s.value = v_actual;
  -- Piezas que la serie EXIGE sin cambios (productor, helper de clientes, ayudante de operativos).
  for v_firma, v_versiones in select e.key, e.value from pg_catalog.jsonb_each(v_exigidas) e loop
    select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)), pg_catalog.md5(p.prosrc) into v_md5_def, v_md5_src
      from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure(v_firma);
    if pg_catalog.jsonb_build_array(v_md5_def, v_md5_src) is distinct from v_versiones then
      v_exigidas_ok := false;
      v_informe := v_informe || E'\n  EXIGIDA CAMBIADA: ' || v_firma || ' def=' || coalesce(v_md5_def, 'AUSENTE');
    end if;
  end loop;
  -- Historial de la serie (v3, Codex P1). Sus filas del índice, en orden de versión, tienen que formar una secuencia válida
  -- ANTES → M1 → M2 → M3 y vuelta: aplicar mN solo desde M(N-1) y revertir mN solo desde MN. De ahí salen el estado al que
  -- lleva el historial (v_h_estado), la última aplicación de cada mN (v_h_apl) y la versión más alta de la serie (v_h_max).
  -- Las aplicaciones se reconocen por su nombre (cualquier generación) y las reversas por «<nombre>_revertir».
  v_h_tabla := pg_catalog.to_regclass('supabase_migrations.schema_migrations') is not null;
  if v_h_tabla then
    for v_h_version, v_h_nombre in execute
        'select m.version, m.name from supabase_migrations.schema_migrations m where m.name = any ($1) order by m.version collate "C"'
        using array['crm_sla_ventana_por_filas', 'crm_sla_avisos_por_filas', 'crm_sla_cola_por_filas', 'crm_sla_ventana_por_filas_revertir', 'crm_sla_avisos_por_filas_revertir', 'crm_sla_cola_por_filas_revertir']::text[] loop
      v_h_n := pg_catalog.array_position(array['crm_sla_ventana_por_filas', 'crm_sla_avisos_por_filas', 'crm_sla_cola_por_filas', 'crm_sla_ventana_por_filas_revertir', 'crm_sla_avisos_por_filas_revertir', 'crm_sla_cola_por_filas_revertir']::text[], v_h_nombre);
      if v_h_n <= 3 and v_h_estado = v_h_n - 1 then
        v_h_estado := v_h_n;
        v_h_apl[v_h_n] := v_h_version;
      elsif v_h_n > 3 and v_h_estado = v_h_n - 3 then
        v_h_estado := v_h_n - 4;
      else
        v_h_ok := false;
      end if;
      v_h_max := v_h_version;
      v_h_lista := v_h_lista || ' ' || v_h_version || '=' || v_h_nombre;
    end loop;
  end if;
  if not v_h_tabla then
    raise exception 'REGISTRO: no existe supabase_migrations.schema_migrations; no hay índice que registrar';
  end if;
  if v_serie is null or v_serie = 'ANTES' then
    raise exception 'REGISTRO: la serie viva no es M1, M2 ni M3 (%); no se registra nada', coalesce(v_serie, 'MIXTO ' || v_actual::text);
  end if;
  if not v_exigidas_ok then
    raise exception 'REGISTRO: cambió el productor, el helper de clientes o sla_leads_operativos respecto de lo ensayado;%', v_informe;
  end if;
  if exists (select 1 from pg_catalog.pg_roles r,
               pg_catalog.unnest(array['private.sla_operacion_autorizada_filas(uuid[])', 'private.sla_operacion_ambito(uuid[],boolean)']) f(firma)
             where not r.rolsuper and r.rolname <> 'postgres' and not pg_catalog.pg_has_role(r.oid, 'postgres', 'MEMBER')
               and pg_catalog.has_function_privilege(r.oid, f.firma, 'EXECUTE')) then
    raise exception 'REGISTRO: ACL inesperada en las piezas privadas de la ventana';
  end if;
  v_n := case v_serie when 'M1' then 1 when 'M2' then 2 when 'M3' then 3 end;
  if not v_h_ok then
    raise exception 'REGISTRO: el historial de la serie no es una secuencia válida (aplicar M1→M2→M3, revertir M3→M2→M1):%; no se registra nada', v_h_lista;
  end if;
  if v_h_estado > v_n then
    raise exception 'REGISTRO: el historial va por M% y la serie viva es %: el esquema cambió por fuera del kit (con el kit v4 una reversa se registra sola en su misma transacción); no se registra nada: investigar antes de seguir', v_h_estado, v_serie;
  end if;
  for i in 1 .. v_n loop
    v_version := v_archivos->(i - 1)->>0; v_nombre := v_archivos->(i - 1)->>1; v_texto := v_archivos->(i - 1)->>2;
    select m.name, m.statements into v_nom_ex, v_existente
      from supabase_migrations.schema_migrations m where m.version = v_version;
    if i <= v_h_estado then
      -- Ya vigente en el historial: tiene que ser ESTE evento (misma versión y mismo texto).
      if v_h_apl[i] is distinct from v_version then
        raise exception 'REGISTRO: la aplicación vigente de % en el historial es la versión % (otra generación), no %: usa el registrador de esa generación (no se registra nada)', v_nombre, v_h_apl[i], v_version;
      end if;
      if v_nom_ex is distinct from v_nombre or v_existente is distinct from array[v_texto] then
        raise exception 'REGISTRO: la versión % ya existe con otro contenido; no se toca', v_version;
      end if;
      v_presentes := v_presentes + 1;
    else
      if v_nom_ex is not null or v_existente is not null
         or exists (select 1 from supabase_migrations.schema_migrations m where m.version = v_version) then
        raise exception 'REGISTRO: la versión % ya está ocupada en el índice (un evento anterior o ajeno): la serie viva no puede venir de ese archivo, que se niega a reaplicarse; una reaplicación va con versiones NUEVAS (no se registra nada)', v_version;
      end if;
      if v_h_max is not null and v_version <= v_h_max then
        raise exception 'REGISTRO: la versión % no es posterior al último evento registrado de la serie (%); no se registra nada', v_version, v_h_max;
      end if;
      insert into supabase_migrations.schema_migrations (version, name, statements)
      values (v_version, v_nombre, array[v_texto]);
      v_h_max := v_version;
      v_nuevas := v_nuevas + 1;
    end if;
  end loop;
  -- v4 (orden global): se INFORMA, sin bloquear (el DDL ya está hecho), cuántas versiones del índice posteriores a la M1 de
  -- esta generación no son de la serie. En la publicación inicial tiene que ser 0 (ver LEEME).
  execute 'select count(*) from supabase_migrations.schema_migrations m where m.version ~ ''^[0-9]+$'' and m.version::numeric > $1::numeric and not (m.name = any ($2))'
    into v_n_ajenas using '20261017054425', array['crm_sla_ventana_por_filas', 'crm_sla_avisos_por_filas', 'crm_sla_cola_por_filas', 'crm_sla_ventana_por_filas_revertir', 'crm_sla_avisos_por_filas_revertir', 'crm_sla_cola_por_filas_revertir']::text[];
  v_informe := 'REGISTRO: serie ' || v_serie || ' · ' || v_nuevas || ' versión(es) nueva(s) y ' || v_presentes || ' ya vigente(s) del mismo evento'
    || ' · versiones del índice posteriores a 20261017054425 que no son de la serie: ' || v_n_ajenas
    || case when v_n_ajenas > 0 then ' (AVISO, no bloquea: revisar el orden global, ver LEEME)' else '' end;
  perform pg_catalog.set_config('crm_sla_por_filas.informe', v_informe, false);
  raise notice '%', v_informe;
end $registrar$;
commit;
select pg_catalog.current_setting('crm_sla_por_filas.informe', true) as informe;

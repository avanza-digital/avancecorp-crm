-- SLA paso 3a · M2: el resumen de avisos cuenta POR FILAS (plan «foto del SLA», Fase 3). v2. Requiere M1 (20261017054425_crm_sla_ventana_por_filas).
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

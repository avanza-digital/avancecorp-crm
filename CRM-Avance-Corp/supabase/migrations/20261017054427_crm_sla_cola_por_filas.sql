-- SLA paso 3a · M3: la cola del día POR FILAS (plan «foto del SLA», Fase 3). v2. Requiere M1 (20261017054425_crm_sla_ventana_por_filas) y M2 (20261017054426_crm_sla_avisos_por_filas).
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

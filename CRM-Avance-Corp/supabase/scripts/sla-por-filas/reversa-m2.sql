-- Reversa de 20261017054426_crm_sla_avisos_por_filas (paso 3a, SLA por filas; kit v4). SOLO actúa si está viva EXACTAMENTE la versión que dejó esa migración
-- (huellas, metadatos y atributos de todas sus piezas); si no, falla sin tocar nada. Repone los cuerpos y los comentarios
-- anteriores byte a byte. No corre los guardianes (para que nada ajeno bloquee una vuelta atrás): comprobar después con
-- verificar.sql. Se aplica como MIGRACIÓN NUEVA con versión nueva (ver LEEME.md, «Si hay que revertir»); nunca se borran
-- filas del índice.
-- Al copiarla a la migración nueva, poner su versión en v_esta_version (ÚNICO cambio). Con el índice presente, ANTES de
-- cualquier DDL exige esa versión (no NULL), libre y posterior a TODO el índice, y que la aplicación de m2 sea el último
-- evento registrado («registrar antes de revertir»).
-- v4 (Codex P1): se REGISTRA A SÍ MISMA en la misma transacción que su DDL. Con el índice presente, tras el bloque (sus
-- comprobaciones, el DDL y las poscondiciones) inserta su fila: versión v_esta_version, nombre crm_sla_avisos_por_filas_revertir y statements = el texto
-- del bloque ejecutable (autosuficiente: fija su entorno, vuelve a comprobarlo todo y reproduce el efecto). Así no puede
-- existir una reversa ejecutada sin registrar, ni registrada con otra versión. Sin índice (banco, arnés), no inserta nada.
begin;
set local lock_timeout = '5s';
set local search_path = '';
set local quote_all_identifiers = off;
do $reversa$
declare
  v_cuerpo text := $cuerpo_reversa$do $bloque$
declare
  v_oid oid; v_firma text; v_esp jsonb; v_def text; v_md5_def text; v_md5_src text; v_meta text; v_extra text; v_ok text;
  v_ya boolean;
  v_esta_version text := 'AAAAMMDDHHMMSS';  -- versión de ESTA migración de reversa
  v_h_tabla boolean; v_h_estado integer := 0; v_h_ok boolean := true; v_h_max text; v_h_lista text := '';
  v_h_apl text[] := array[null, null, null]::text[]; v_h_version text; v_h_nombre text; v_h_n integer;
  v_h_max_global numeric; v_n_ajenas bigint;
begin
  -- Bloque autosuficiente (así se ejecuta, se registra y se reproduce): fija su propio entorno.
  perform pg_catalog.set_config('lock_timeout', '5s', true);
  perform pg_catalog.set_config('search_path', '', true);
  perform pg_catalog.set_config('quote_all_identifiers', 'off', true);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm_sla_por_filas'));
  -- Historial (v3/v4, Codex), ANTES de cualquier DDL. Con el índice de migraciones presente, se niega salvo que:
  --   * v_esta_version tenga la versión de ESTA migración de reversa, no NULL (se rellena al copiarla: es su único cambio);
  --   * esa versión esté LIBRE en el índice y sea posterior a TODO el índice, no solo a la serie (v4: orden global; así
  --     también R3 < R2 < R1);
  --   * la aplicación de mN sea el ÚLTIMO evento registrado de la serie, de esta generación («registrar antes de revertir»).
  -- Sin índice (banco de pruebas, arnés), no aplica: la reversa se comporta como siempre y no registra nada.
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
  if v_h_tabla then
    if v_esta_version is null or (v_esta_version ~ '^[0-9]{14}$') is not true then
      raise exception 'PREFLIGHT REVERSA M2: el índice de migraciones existe y esta reversa no tiene una versión válida (vacía, NULL o sin rellenar): pon en v_esta_version la de la migración nueva de reversa (no se toca nada)';
    end if;
    execute 'select exists (select 1 from supabase_migrations.schema_migrations m where m.version = $1)' into v_ya using v_esta_version;
    if v_ya then
      raise exception 'PREFLIGHT REVERSA M2: la versión % ya está ocupada en supabase_migrations.schema_migrations; una reversa va con una versión NUEVA (no se toca nada)', v_esta_version;
    end if;
    if not v_h_ok then
      raise exception 'PREFLIGHT REVERSA M2: el historial de la serie no es una secuencia válida:%; no se toca nada', v_h_lista;
    end if;
    if v_h_estado <> 2 then
      raise exception 'PREFLIGHT REVERSA M2: registrar antes de revertir: el historial de la serie va por %, no por M2 (eventos:%). Si M2 está viva sin registrar, corre antes registrar-indice.sql; si falta registrar una reversa, su registrar-reversa (no se toca nada)', case v_h_estado when 0 then 'ANTES' else 'M' || v_h_estado end, coalesce(v_h_lista, '');
    end if;
    if v_h_apl[2] is distinct from '20261017054426' then
      raise exception 'PREFLIGHT REVERSA M2: la aplicación vigente de m2 en el historial es la versión % (otra generación), no 20261017054426: usa la reversa del kit de esa generación (no se toca nada)', v_h_apl[2];
    end if;
    execute 'select max(m.version::numeric) from supabase_migrations.schema_migrations m where m.version ~ ''^[0-9]+$'''
      into v_h_max_global;
    if (v_esta_version::numeric > coalesce(v_h_max_global, 0)) is not true then
      raise exception 'PREFLIGHT REVERSA M2: la versión % no es posterior a TODO el índice de migraciones (máximo %): una reversa va al final del historial, después de cualquier migración ya registrada, de la serie o ajena (no se toca nada)', v_esta_version, v_h_max_global;
    end if;
  end if;
  for v_firma, v_esp in select e.key, e.value from pg_catalog.jsonb_each($esperado_preflight_reversa_m2${
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
 }
}$esperado_preflight_reversa_m2$::jsonb) e loop
    v_oid := pg_catalog.to_regprocedure(v_firma);
    if v_oid is null then
      raise exception 'PREFLIGHT REVERSA M2: no existe %', v_firma;
    end if;
    select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)), pg_catalog.md5(p.prosrc), pg_catalog.concat_ws('|', pg_catalog.pg_get_userbyid(p.proowner), p.proacl::text, pg_catalog.array_to_string(p.proconfig, ','),
         p.prosecdef::text, p.provolatile::text, p.proparallel::text, p.prorettype::pg_catalog.regtype::text,
         pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), ''))), (select pg_catalog.concat_ws('|', l.lanname, p.proisstrict::text, p.proleakproof::text, p.procost::text, p.prorows::text,
         p.prosupport::text, p.proretset::text, pg_catalog.pg_get_function_arguments(p.oid), pg_catalog.pg_get_function_result(p.oid))
         from pg_catalog.pg_language l where l.oid = p.prolang)
      into v_md5_def, v_md5_src, v_meta, v_extra from pg_catalog.pg_proc p where p.oid = v_oid;
    if v_md5_def is distinct from v_esp->>'def' or v_md5_src is distinct from v_esp->>'src' then
      raise exception 'PREFLIGHT REVERSA M2: % no es la versión que dejó 20261017054426_crm_sla_avisos_por_filas (md5 def % / prosrc %; esperado % / %)', v_firma, v_md5_def, v_md5_src, v_esp->>'def', v_esp->>'src';
    end if;
    if v_meta is distinct from v_esp->>'meta' then
      raise exception 'PREFLIGHT REVERSA M2: dueño, ACL, configuración, DEFINER, volatilidad o comentario de % distintos (%)', v_firma, v_meta;
    end if;
    if v_extra is distinct from v_esp->>'extra' then
      raise exception 'PREFLIGHT REVERSA M2: otro atributo de % distinto (lenguaje, strict, leakproof, coste, filas, soporte, argumentos o resultado): %', v_firma, v_extra;
    end if;
  end loop;
  -- Resumen (cuerpo y comentario anteriores a M2) y guardián de avisos (versión de M1), byte a byte.
  v_def := $ddl_resumen_antes$CREATE OR REPLACE FUNCTION crm.avisos_sla_resumen_v2_fn()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_datos jsonb;v_total integer;v_avisos integer;v_criticas integer;v_grupos jsonb;
begin
  -- Misma ventana autorizada y mismo instante que ficha y cola. El conteo
  -- incluye toda la cartera visible, sin depender del lote local ni pagina.
  -- Solo las oportunidades que pueden avisar: activas y en etapa comercial (las descartadas y
  -- convertidas son «lead_terminal» en el núcleo y nunca producen avisos ni «pendientes»; 1.139 de
  -- 2.583 el 29/09/2026). El núcleo, su autoridad y su reloj no cambian; el ayudante vive en
  -- private porque este adaptador no puede leer hechos crudos (assert_sla_avisos).
  v_datos:=private.sla_operacion_autorizada(private.sla_leads_operativos(),true);
  with filas as materialized (
    select f.value from jsonb_array_elements(v_datos->'filas') f
    where v_datos->>'modo'='activo' and (f.value#>>'{senales,pendientes}')::boolean
  ), avisos as materialized (
    select a.value from filas f cross join lateral jsonb_array_elements(f.value#>'{estado,avisos}') a
  ), grupos as (
    select a.value->>'bucket' as bucket,count(*) as total,
      min((a.value->>'prioridad')::integer) as prioridad
    from avisos a group by a.value->>'bucket'
  )
  select (select count(*) from filas),(select count(*) from avisos),
    (select count(*) from avisos a where a.value->>'severidad'='critica'),
    coalesce((select jsonb_agg(jsonb_build_object('bucket',g.bucket,'total',g.total) order by g.prioridad) from grupos g),'[]'::jsonb)
  into v_total,v_avisos,v_criticas,v_grupos;
  return (v_datos-'filas'-'contexto_ambito')||jsonb_build_object(
    'total_oportunidades',v_total,'total_avisos',v_avisos,'criticas',v_criticas,'grupos',v_grupos);
end;
$function$
$ddl_resumen_antes$;
  if pg_catalog.md5(v_def) is distinct from 'e9ce617ab0cc33bc5614ef69e877cc71' then
    raise exception 'PREFLIGHT REVERSA M2: el DDL de el resumen de avisos no es el ensayado (md5 esperado e9ce617ab0cc33bc5614ef69e877cc71)';
  end if;
  execute v_def;
  execute $c_res_antes$comment on function crm.avisos_sla_resumen_v2_fn() is 'Resumen acotado de avisos vigentes del nucleo SLA. Autoridad y reloj de sla_operacion_autorizada; sin entrega push ni escrituras.'$c_res_antes$;
  v_def := $ddl_assert_sla_avisos_m1$CREATE OR REPLACE FUNCTION private.assert_sla_avisos()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v record;v_cuerpo text;
begin
  perform private.assert_sla_nucleo();
  for v in select * from (values
    ('crm.avisos_sla_resumen_v2_fn()','sla_operacion_autorizada'),
    ('private.sla_operacion_autorizada(uuid[],boolean)','sla_operacion_autorizada_filas'),
    ('private.sla_operacion_autorizada_filas(uuid[])','sla_operacion_leads')
  ) d(firma,dependencia) loop
    select regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','gs')
      into strict v_cuerpo from pg_proc p where p.oid=v.firma::regprocedure;
    if v_cuerpo !~ ('\mprivate\.'||v.dependencia||'\s*\(') then
      raise exception 'SLA avisos: % dejo de consumir %',v.firma,v.dependencia;
    end if;
    if v.firma like 'crm.%' and v_cuerpo ~ '\mcrm\.(leads|tareas|actividades|lead_sla_etapas)\M' then
      raise exception 'SLA avisos: adaptador lee hechos crudos';
    end if;
  end loop;
  if has_function_privilege('anon','crm.avisos_sla_resumen_v2_fn()','execute')
    or has_function_privilege('service_role','crm.avisos_sla_resumen_v2_fn()','execute')
    or not has_function_privilege('authenticated','crm.avisos_sla_resumen_v2_fn()','execute') then
    raise exception 'SLA avisos: permisos incorrectos del resumen';
  end if;
  -- Vigilante del ayudante (30/09/2026, auditor-rls P2-2): existe con su huella, dueño postgres, INVOKER, STABLE,
  -- search_path vacío y sin ejecutores de la API; y el resumen se lo pasa al núcleo (no vuelve a pedir TODAS las
  -- oportunidades). Si el ayudante cambia legítimamente, se resella aquí en la misma migración.
  if to_regprocedure('private.sla_leads_operativos()') is null then
    raise exception 'SLA avisos: falta el ayudante private.sla_leads_operativos()';
  end if;
  if not exists (select 1 from pg_proc p where p.oid='private.sla_leads_operativos()'::regprocedure
      and md5(pg_get_functiondef(p.oid))='8d478d783e4c591662388ddf7405058a'
      and p.proowner='postgres'::regrole and p.prosecdef is false and p.provolatile='s'
      and p.proconfig=array['search_path=""'] and p.proacl::text='{postgres=X/postgres}') then
    raise exception 'SLA avisos: el ayudante sla_leads_operativos no es el esperado (huella, dueño, definer, volatilidad, search_path o permisos)';
  end if;
  select regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','gs')
    into strict v_cuerpo from pg_proc p where p.oid='crm.avisos_sla_resumen_v2_fn()'::regprocedure;
  -- Toda llamada al núcleo desde el resumen debe ir acotada por el ayudante: no basta con que exista una (Codex, 30/09).
  if regexp_count(v_cuerpo, '\mprivate\.sla_operacion_autorizada\s*\(') < 1
     or regexp_count(v_cuerpo, '\mprivate\.sla_operacion_autorizada\s*\(')
        <> regexp_count(v_cuerpo, '\mprivate\.sla_operacion_autorizada\s*\(\s*private\.sla_leads_operativos\s*\(\s*\)\s*,') then
    raise exception 'SLA avisos: el resumen dejo de evaluar solo las oportunidades operativas';
  end if;
  return 'OK: avisos derivados del nucleo, con autoridad y resumen completo';
end;
$function$
$ddl_assert_sla_avisos_m1$;
  if pg_catalog.md5(v_def) is distinct from 'fb433efc037f09647481744a5f36380c' then
    raise exception 'PREFLIGHT REVERSA M2: el DDL de assert_sla_avisos no es el ensayado (md5 esperado fb433efc037f09647481744a5f36380c)';
  end if;
  execute v_def;
  for v_firma, v_esp in select e.key, e.value from pg_catalog.jsonb_each($esperado_postflight_reversa_m2${
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
 }
}$esperado_postflight_reversa_m2$::jsonb) e loop
    v_oid := pg_catalog.to_regprocedure(v_firma);
    if v_oid is null then
      raise exception 'POSTFLIGHT REVERSA M2: no existe %', v_firma;
    end if;
    select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)), pg_catalog.md5(p.prosrc), pg_catalog.concat_ws('|', pg_catalog.pg_get_userbyid(p.proowner), p.proacl::text, pg_catalog.array_to_string(p.proconfig, ','),
         p.prosecdef::text, p.provolatile::text, p.proparallel::text, p.prorettype::pg_catalog.regtype::text,
         pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), ''))), (select pg_catalog.concat_ws('|', l.lanname, p.proisstrict::text, p.proleakproof::text, p.procost::text, p.prorows::text,
         p.prosupport::text, p.proretset::text, pg_catalog.pg_get_function_arguments(p.oid), pg_catalog.pg_get_function_result(p.oid))
         from pg_catalog.pg_language l where l.oid = p.prolang)
      into v_md5_def, v_md5_src, v_meta, v_extra from pg_catalog.pg_proc p where p.oid = v_oid;
    if v_md5_def is distinct from v_esp->>'def' or v_md5_src is distinct from v_esp->>'src' then
      raise exception 'POSTFLIGHT REVERSA M2: % no es la versión anterior (md5 def % / prosrc %; esperado % / %)', v_firma, v_md5_def, v_md5_src, v_esp->>'def', v_esp->>'src';
    end if;
    if v_meta is distinct from v_esp->>'meta' then
      raise exception 'POSTFLIGHT REVERSA M2: dueño, ACL, configuración, DEFINER, volatilidad o comentario de % distintos (%)', v_firma, v_meta;
    end if;
    if v_extra is distinct from v_esp->>'extra' then
      raise exception 'POSTFLIGHT REVERSA M2: otro atributo de % distinto (lenguaje, strict, leakproof, coste, filas, soporte, argumentos o resultado): %', v_firma, v_extra;
    end if;
  end loop;
  -- Para el envoltorio: la versión con la que se ejecutó ESTE bloque (solo esta transacción).
  perform pg_catalog.set_config('crm_sla_por_filas.version_reversa', coalesce(v_esta_version, ''), true);
end $bloque$$cuerpo_reversa$;
  v_version text;
begin
  -- 1. El bloque de la reversa: historial y versión (ANTES del DDL), DDL y poscondiciones.
  execute v_cuerpo;
  -- 2. v4: con el índice presente, la reversa se registra A SÍ MISMA en esta misma transacción, con la versión con la que se
  --    ejecutó y el texto exacto del bloque. Si algo falla aquí, no queda ni el DDL ni la fila.
  if pg_catalog.to_regclass('supabase_migrations.schema_migrations') is not null then
    v_version := pg_catalog.current_setting('crm_sla_por_filas.version_reversa', true);
    if v_version is null or (v_version ~ '^[0-9]{14}$') is not true then
      raise exception 'PREFLIGHT REVERSA M2: la reversa no trae una versión válida para registrarse; no queda nada aplicado';
    end if;
    execute 'insert into supabase_migrations.schema_migrations (version, name, statements) values ($1, $2, $3)'
      using v_version, 'crm_sla_avisos_por_filas_revertir', array[v_cuerpo];
    raise notice 'REGISTRO REVERSA: crm_sla_avisos_por_filas_revertir % registrada en la misma transacción que su DDL', v_version;
  end if;
end $reversa$;
commit;

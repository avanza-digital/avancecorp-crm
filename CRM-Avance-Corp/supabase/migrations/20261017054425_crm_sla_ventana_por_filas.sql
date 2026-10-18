-- SLA paso 3a · M1: la ventana operativa POR FILAS y una sola regla de autorización (plan «foto del SLA», Fase 3). v2.
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

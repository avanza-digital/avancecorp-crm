-- Reversa de 20261017054425_crm_sla_ventana_por_filas (paso 3a, SLA por filas; kit v4). SOLO actúa si está viva EXACTAMENTE la versión que dejó esa migración
-- (huellas, metadatos y atributos de todas sus piezas); si no, falla sin tocar nada. Repone los cuerpos y los comentarios
-- anteriores byte a byte. No corre los guardianes (para que nada ajeno bloquee una vuelta atrás): comprobar después con
-- verificar.sql. Se aplica como MIGRACIÓN NUEVA con versión nueva (ver LEEME.md, «Si hay que revertir»); nunca se borran
-- filas del índice.
-- Al copiarla a la migración nueva, poner su versión en v_esta_version (ÚNICO cambio). Con el índice presente, ANTES de
-- cualquier DDL exige esa versión (no NULL), libre y posterior a TODO el índice, y que la aplicación de m1 sea el último
-- evento registrado («registrar antes de revertir»).
-- v4 (Codex P1): se REGISTRA A SÍ MISMA en la misma transacción que su DDL. Con el índice presente, tras el bloque (sus
-- comprobaciones, el DDL y las poscondiciones) inserta su fila: versión v_esta_version, nombre crm_sla_ventana_por_filas_revertir y statements = el texto
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
      raise exception 'PREFLIGHT REVERSA M1: el índice de migraciones existe y esta reversa no tiene una versión válida (vacía, NULL o sin rellenar): pon en v_esta_version la de la migración nueva de reversa (no se toca nada)';
    end if;
    execute 'select exists (select 1 from supabase_migrations.schema_migrations m where m.version = $1)' into v_ya using v_esta_version;
    if v_ya then
      raise exception 'PREFLIGHT REVERSA M1: la versión % ya está ocupada en supabase_migrations.schema_migrations; una reversa va con una versión NUEVA (no se toca nada)', v_esta_version;
    end if;
    if not v_h_ok then
      raise exception 'PREFLIGHT REVERSA M1: el historial de la serie no es una secuencia válida:%; no se toca nada', v_h_lista;
    end if;
    if v_h_estado <> 1 then
      raise exception 'PREFLIGHT REVERSA M1: registrar antes de revertir: el historial de la serie va por %, no por M1 (eventos:%). Si M1 está viva sin registrar, corre antes registrar-indice.sql; si falta registrar una reversa, su registrar-reversa (no se toca nada)', case v_h_estado when 0 then 'ANTES' else 'M' || v_h_estado end, coalesce(v_h_lista, '');
    end if;
    if v_h_apl[1] is distinct from '20261017054425' then
      raise exception 'PREFLIGHT REVERSA M1: la aplicación vigente de m1 en el historial es la versión % (otra generación), no 20261017054425: usa la reversa del kit de esa generación (no se toca nada)', v_h_apl[1];
    end if;
    execute 'select max(m.version::numeric) from supabase_migrations.schema_migrations m where m.version ~ ''^[0-9]+$'''
      into v_h_max_global;
    if (v_esta_version::numeric > coalesce(v_h_max_global, 0)) is not true then
      raise exception 'PREFLIGHT REVERSA M1: la versión % no es posterior a TODO el índice de migraciones (máximo %): una reversa va al final del historial, después de cualquier migración ya registrada, de la serie o ajena (no se toca nada)', v_esta_version, v_h_max_global;
    end if;
  end if;
  for v_firma, v_esp in select e.key, e.value from pg_catalog.jsonb_each($esperado_preflight_reversa_m1${
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
}$esperado_preflight_reversa_m1$::jsonb) e loop
    v_oid := pg_catalog.to_regprocedure(v_firma);
    if v_oid is null then
      raise exception 'PREFLIGHT REVERSA M1: no existe %', v_firma;
    end if;
    select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)), pg_catalog.md5(p.prosrc), pg_catalog.concat_ws('|', pg_catalog.pg_get_userbyid(p.proowner), p.proacl::text, pg_catalog.array_to_string(p.proconfig, ','),
         p.prosecdef::text, p.provolatile::text, p.proparallel::text, p.prorettype::pg_catalog.regtype::text,
         pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), ''))), (select pg_catalog.concat_ws('|', l.lanname, p.proisstrict::text, p.proleakproof::text, p.procost::text, p.prorows::text,
         p.prosupport::text, p.proretset::text, pg_catalog.pg_get_function_arguments(p.oid), pg_catalog.pg_get_function_result(p.oid))
         from pg_catalog.pg_language l where l.oid = p.prolang)
      into v_md5_def, v_md5_src, v_meta, v_extra from pg_catalog.pg_proc p where p.oid = v_oid;
    if v_md5_def is distinct from v_esp->>'def' or v_md5_src is distinct from v_esp->>'src' then
      raise exception 'PREFLIGHT REVERSA M1: % no es la versión que dejó 20261017054425_crm_sla_ventana_por_filas (md5 def % / prosrc %; esperado % / %)', v_firma, v_md5_def, v_md5_src, v_esp->>'def', v_esp->>'src';
    end if;
    if v_meta is distinct from v_esp->>'meta' then
      raise exception 'PREFLIGHT REVERSA M1: dueño, ACL, configuración, DEFINER, volatilidad o comentario de % distintos (%)', v_firma, v_meta;
    end if;
    if v_extra is distinct from v_esp->>'extra' then
      raise exception 'PREFLIGHT REVERSA M1: otro atributo de % distinto (lenguaje, strict, leakproof, coste, filas, soporte, argumentos o resultado): %', v_firma, v_extra;
    end if;
  end loop;
  -- Nada fuera de la propia ventana puede seguir usando _filas ni el ámbito (el resumen y la cola ya revertidos):
  -- (a) en el texto de cualquier función, SIN distinguir mayúsculas (Codex P2: «PRIVATE.SLA_OPERACION_AUTORIZADA_FILAS(»
  -- también los llama); (b) en las dependencias registradas (vistas, funciones SQL estándar, defaults…). La búsqueda
  -- textual no prueba la ausencia de llamadas dinámicas construidas por partes.
  select pg_catalog.string_agg(x, ', ') into v_def from (
    select p.oid::pg_catalog.regprocedure::text as x from pg_catalog.pg_proc p
     where p.oid not in (pg_catalog.to_regprocedure('private.sla_operacion_autorizada(uuid[],boolean)'),
                     pg_catalog.to_regprocedure('private.sla_operacion_autorizada_filas(uuid[])'),
                     pg_catalog.to_regprocedure('private.sla_operacion_ambito(uuid[],boolean)'),
                     pg_catalog.to_regprocedure('private.assert_sla_nucleo()'),
                     pg_catalog.to_regprocedure('private.assert_sla_avisos()'),
                     pg_catalog.to_regprocedure('private.assert_cola_v3()'))
       and coalesce(p.prosrc, '') ~* '\msla_operacion_(autorizada_filas|ambito)\M'
    union all
    select pg_catalog.pg_describe_object(d.classid, d.objid, d.objsubid) from pg_catalog.pg_depend d
     where d.refclassid = 'pg_catalog.pg_proc'::pg_catalog.regclass
       and d.refobjid in (pg_catalog.to_regprocedure('private.sla_operacion_autorizada_filas(uuid[])'),
                          pg_catalog.to_regprocedure('private.sla_operacion_ambito(uuid[],boolean)'))
       and not (d.classid = 'pg_catalog.pg_proc'::pg_catalog.regclass and d.objid in (pg_catalog.to_regprocedure('private.sla_operacion_autorizada(uuid[],boolean)'),
                     pg_catalog.to_regprocedure('private.sla_operacion_autorizada_filas(uuid[])'),
                     pg_catalog.to_regprocedure('private.sla_operacion_ambito(uuid[],boolean)'),
                     pg_catalog.to_regprocedure('private.assert_sla_nucleo()'),
                     pg_catalog.to_regprocedure('private.assert_sla_avisos()'),
                     pg_catalog.to_regprocedure('private.assert_cola_v3()')))) u;
  if v_def is not null then
    raise exception 'PREFLIGHT REVERSA M1: todavía usan sla_operacion_autorizada_filas o sla_operacion_ambito: %; revertir antes M3 y M2', v_def;
  end if;
  -- (c) v3, Codex P2: un identificador Unicode escapado (U&"…", p. ej. U&"sla_operacion_autorizada_\0066ilas") resuelve
  -- al mismo nombre sin contenerlo en el texto. La búsqueda no puede leerlo, así que la reversa se niega, conservadora,
  -- si CUALQUIER cuerpo de función fuera de pg_catalog e information_schema contiene «U&"» (sin distinguir mayúsculas).
  select pg_catalog.string_agg(p.oid::pg_catalog.regprocedure::text, ', ') into v_def
    from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname not in ('pg_catalog', 'information_schema') and p.oid not in (pg_catalog.to_regprocedure('private.sla_operacion_autorizada(uuid[],boolean)'),
                     pg_catalog.to_regprocedure('private.sla_operacion_autorizada_filas(uuid[])'),
                     pg_catalog.to_regprocedure('private.sla_operacion_ambito(uuid[],boolean)'),
                     pg_catalog.to_regprocedure('private.assert_sla_nucleo()'),
                     pg_catalog.to_regprocedure('private.assert_sla_avisos()'),
                     pg_catalog.to_regprocedure('private.assert_cola_v3()'))
     and coalesce(p.prosrc, '') ~* 'u&"';
  if v_def is not null then
    raise exception 'PREFLIGHT REVERSA M1: hay cuerpos con identificadores Unicode escapados (U&"…") que la búsqueda de consumidores no puede leer: %; revisarlos a mano antes de revertir (no se toca nada)', v_def;
  end if;
  -- Autorizada y guardianes: cuerpos anteriores a M1, byte a byte; después, las 2 funciones nuevas fuera.
  v_def := $ddl_autorizada_antes$CREATE OR REPLACE FUNCTION private.sla_operacion_autorizada(p_lead_ids uuid[], p_incluir_operacion boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid:=(select auth.uid()); v_rol text; v_global boolean; v_visibles uuid[];
  v_ahora timestamptz:=statement_timestamp(); v_filas jsonb;
  v_control crm.sla_operacion_control%rowtype; v_politica uuid; v_version integer; v_prox timestamptz;
begin
  v_rol:=private.rol_crm(v_uid);
  v_global:=private.es_lector_global();
  if v_uid is null or (v_rol is null and not coalesce(v_global,false)) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  if p_incluir_operacion is null or array_position(p_lead_ids,null) is not null then
    raise exception 'Entrada SLA invalida' using errcode='22023';
  end if;
  v_global:=(v_rol in ('gerencia','coordinador')) or coalesce(v_global,false);
  v_visibles:=array(select x from private.vendedor_ids_visibles(v_uid) x order by x);
  if not p_incluir_operacion then
    select coalesce(jsonb_agg(h.base order by h.lead_id),'[]'::jsonb) into v_filas
    from private.sla_hechos_actuales(p_lead_ids,v_global,v_visibles) h where h.base is not null;
    return v_filas;
  end if;
  select * into strict v_control from crm.sla_operacion_control where id;
  select p.politica_id,p.version into v_politica,v_version from private.sla_politica_operativa(v_ahora) p;
  select coalesce(jsonb_agg(jsonb_build_object('estado',jsonb_set(s.estado,'{avisos}',a.avisos)
      ||jsonb_build_object('avisos_mostrados',a.mostrados),
    'senales',s.senales||jsonb_build_object('pendientes',jsonb_array_length(a.avisos)>0,
      'revisiones',(v_global or v_rol='supervisor') and (s.senales->>'revisiones')::boolean,
      'por_repartir',(v_global or v_rol='supervisor') and (s.senales->>'por_repartir')::boolean),
    'accion_pendiente',a.mostrados->0,
    'lead',s.presentacion,'accion_revision',s.accion_supervision,'accion',
    case when v_global or v_rol='supervisor' then s.accion_supervision else s.accion_atencion end)
    order by s.lead_id),'[]'::jsonb), min((s.estado#>>'{operacion,proximo_cambio_en}')::timestamptz) into v_filas, v_prox
  from private.sla_operacion_leads(p_lead_ids,v_global,v_visibles,v_ahora) s
  cross join lateral (
    select coalesce(jsonb_agg(av.value order by (av.value->>'prioridad')::integer),'[]'::jsonb) as avisos,
      coalesce(jsonb_agg(av.value order by
        case when av.value->>'id'=s.estado#>>'{operacion,aviso_principal,id}' then 0 else 1 end,
        (av.value->>'prioridad')::integer) filter (where
          av.value->>'id'=s.estado#>>'{operacion,aviso_principal,id}'
          or (av.value->>'solo_supervision')::boolean is true),'[]'::jsonb) as mostrados
    from jsonb_array_elements(s.estado->'avisos') av
    where v_global or v_rol='supervisor' or (av.value->>'solo_supervision')::boolean is false
  ) a;
  return jsonb_build_object('version',2,'modelo_avisos',3,
    'proximo_cambio_en',v_prox,
    'modo',v_control.modo,'control_revision',v_control.revision,
    'calculado_en',v_ahora,'primera_activacion_en',v_control.primera_activacion_en,
    'activacion_hipotetica_en',case when v_control.primera_activacion_en is null and v_control.modo='observacion' then v_ahora end,
    'politica_operativa_id',v_politica,'politica_operativa_version',v_version,
    'politica_adopcion_id',v_control.politica_adopcion_id,'filas',v_filas,
    'contexto_ambito',md5(jsonb_build_object('actor',v_uid,'rol',v_rol,'global',v_global,'visibles',v_visibles)::text));
end;
$function$
$ddl_autorizada_antes$;
  if pg_catalog.md5(v_def) is distinct from 'a5bd718f2f288565ecb510f6ba1e8634' then
    raise exception 'PREFLIGHT REVERSA M1: el DDL de la autorizada (envoltorio) no es el ensayado (md5 esperado a5bd718f2f288565ecb510f6ba1e8634)';
  end if;
  execute v_def;
  v_def := $ddl_assert_sla_nucleo_antes$CREATE OR REPLACE FUNCTION private.assert_sla_nucleo()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v record;v_cuerpo text;v_tabla text;v_rol text;
begin
  for v in select * from (values
    ('crm.estado_sla_leads_fn()','sla_operacion_autorizada'),
    ('crm.estado_sla_leads_v2_fn(uuid[])','sla_operacion_autorizada'),
    ('crm.cola_accion_v2_fn(integer,text,text,uuid,jsonb)','sla_operacion_autorizada'),
    ('crm.cola_accion_v2_fn(integer,text,text,uuid,jsonb)','sla_filtros_cola_validos'),
    ('private.sla_operacion_autorizada(uuid[],boolean)','sla_operacion_leads'),
    ('private.sla_operacion_leads(uuid[],boolean,uuid[],timestamptz)','sla_hechos_actuales')
  ) d(firma,dependencia) loop
    select regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','gs')
      into strict v_cuerpo from pg_proc p where p.oid=v.firma::regprocedure;
    if v_cuerpo !~ ('\mprivate\.'||v.dependencia||'\s*\(') then
      raise exception 'SLA: % dejo de consumir %',v.firma,v.dependencia;
    end if;
    if v.firma like 'crm.%' and v_cuerpo ~ '\mcrm\.(leads|tareas|actividades|lead_sla_etapas)\M' then
      raise exception 'SLA: adaptador % consulta hechos crudos',v.firma;
    end if;
  end loop;
  for v in select p.oid,p.proname,p.prosecdef,p.provolatile,p.proconfig,p.proowner,p.proacl,p.prosrc
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname in ('sla_hechos_actuales','sla_tareas_hechos',
      'sla_evaluar_prorroga','sla_politica_operativa','sla_etapa_hechos','sla_operacion_leads','sla_operacion_autorizada','sla_filtros_cola_validos')
  loop
    if v.provolatile<>'s' or not coalesce(v.proconfig@>array['search_path=""'],false)
       or v.prosecdef<>(v.proname='sla_operacion_autorizada') then
      raise exception 'SLA: propiedades incorrectas de %',v.proname;
    end if;
    if exists (select 1 from aclexplode(coalesce(v.proacl,acldefault('f',v.proowner))) a where a.grantee<>v.proowner) then
      raise exception 'SLA: funcion privada % tiene grants externos',v.proname;
    end if;
    if v.proname<>'sla_operacion_autorizada' and v.prosrc ~ '\mauth\s*\.' then
      raise exception 'SLA: nucleo % interpreta autenticacion',v.proname;
    end if;
  end loop;
  foreach v_tabla in array array['sla_politica_etapas_operacion','lead_sla_etapa_ajustes','tarea_sla_contexto','sla_operacion_control'] loop
    if not (select c.relrowsecurity from pg_class c where c.oid=('crm.'||v_tabla)::regclass) then
      raise exception 'SLA: falta RLS en %',v_tabla;
    end if;
    foreach v_rol in array array['anon','authenticated','service_role'] loop
      if has_table_privilege(v_rol,'crm.'||v_tabla,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then
        raise exception 'SLA: privilegio directo de % en %',v_rol,v_tabla;
      end if;
    end loop;
    if not exists (select 1 from pg_trigger t where t.tgrelid=('crm.'||v_tabla)::regclass
      and t.tgfoid='private.log_audit_crm()'::regprocedure and t.tgenabled in ('O','A')
      and t.tgtype=29 and t.tgqual is null and t.tgattr=''::int2vector) then
      raise exception 'SLA: auditoria incompleta en %',v_tabla;
    end if;
  end loop;
  return 'OK: nucleo SLA privado, adaptadores dependientes, entradas cerradas y auditadas';
end;
$function$
$ddl_assert_sla_nucleo_antes$;
  if pg_catalog.md5(v_def) is distinct from '6bc541b2e3ba1549b4b4ed419c22d455' then
    raise exception 'PREFLIGHT REVERSA M1: el DDL de assert_sla_nucleo no es el ensayado (md5 esperado 6bc541b2e3ba1549b4b4ed419c22d455)';
  end if;
  execute v_def;
  v_def := $ddl_assert_sla_avisos_antes$CREATE OR REPLACE FUNCTION private.assert_sla_avisos()
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
    ('private.sla_operacion_autorizada(uuid[],boolean)','sla_operacion_leads')
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
$ddl_assert_sla_avisos_antes$;
  if pg_catalog.md5(v_def) is distinct from '9b9edc86c3a55d89367b6d64203d38dc' then
    raise exception 'PREFLIGHT REVERSA M1: el DDL de assert_sla_avisos no es el ensayado (md5 esperado 9b9edc86c3a55d89367b6d64203d38dc)';
  end if;
  execute v_def;
  -- Las 2 funciones que creó M1 (sin datos ni dependientes): solo ellas.
  execute 'drop function private.sla_operacion_autorizada_filas(uuid[])';
  execute 'drop function private.sla_operacion_ambito(uuid[],boolean)';
  for v_firma, v_esp in select e.key, e.value from pg_catalog.jsonb_each($esperado_postflight_reversa_m1${
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
 }
}$esperado_postflight_reversa_m1$::jsonb) e loop
    v_oid := pg_catalog.to_regprocedure(v_firma);
    if v_oid is null then
      raise exception 'POSTFLIGHT REVERSA M1: no existe %', v_firma;
    end if;
    select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)), pg_catalog.md5(p.prosrc), pg_catalog.concat_ws('|', pg_catalog.pg_get_userbyid(p.proowner), p.proacl::text, pg_catalog.array_to_string(p.proconfig, ','),
         p.prosecdef::text, p.provolatile::text, p.proparallel::text, p.prorettype::pg_catalog.regtype::text,
         pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), ''))), (select pg_catalog.concat_ws('|', l.lanname, p.proisstrict::text, p.proleakproof::text, p.procost::text, p.prorows::text,
         p.prosupport::text, p.proretset::text, pg_catalog.pg_get_function_arguments(p.oid), pg_catalog.pg_get_function_result(p.oid))
         from pg_catalog.pg_language l where l.oid = p.prolang)
      into v_md5_def, v_md5_src, v_meta, v_extra from pg_catalog.pg_proc p where p.oid = v_oid;
    if v_md5_def is distinct from v_esp->>'def' or v_md5_src is distinct from v_esp->>'src' then
      raise exception 'POSTFLIGHT REVERSA M1: % no es la versión anterior (md5 def % / prosrc %; esperado % / %)', v_firma, v_md5_def, v_md5_src, v_esp->>'def', v_esp->>'src';
    end if;
    if v_meta is distinct from v_esp->>'meta' then
      raise exception 'POSTFLIGHT REVERSA M1: dueño, ACL, configuración, DEFINER, volatilidad o comentario de % distintos (%)', v_firma, v_meta;
    end if;
    if v_extra is distinct from v_esp->>'extra' then
      raise exception 'POSTFLIGHT REVERSA M1: otro atributo de % distinto (lenguaje, strict, leakproof, coste, filas, soporte, argumentos o resultado): %', v_firma, v_extra;
    end if;
  end loop;
  if pg_catalog.to_regprocedure('private.sla_operacion_ambito(uuid[],boolean)') is not null
     or pg_catalog.to_regprocedure('private.sla_operacion_autorizada_filas(uuid[])') is not null then
    raise exception 'POSTFLIGHT REVERSA M1: siguen existiendo las funciones nuevas';
  end if;
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
      raise exception 'PREFLIGHT REVERSA M1: la reversa no trae una versión válida para registrarse; no queda nada aplicado';
    end if;
    execute 'insert into supabase_migrations.schema_migrations (version, name, statements) values ($1, $2, $3)'
      using v_version, 'crm_sla_ventana_por_filas_revertir', array[v_cuerpo];
    raise notice 'REGISTRO REVERSA: crm_sla_ventana_por_filas_revertir % registrada en la misma transacción que su DDL', v_version;
  end if;
end $reversa$;
commit;

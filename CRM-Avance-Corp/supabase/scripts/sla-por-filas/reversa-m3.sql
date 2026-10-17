-- Reversa de 20261017054427_crm_sla_cola_por_filas (paso 3a, SLA por filas; kit v4). SOLO actúa si está viva EXACTAMENTE la versión que dejó esa migración
-- (huellas, metadatos y atributos de todas sus piezas); si no, falla sin tocar nada. Repone los cuerpos y los comentarios
-- anteriores byte a byte. No corre los guardianes (para que nada ajeno bloquee una vuelta atrás): comprobar después con
-- verificar.sql. Se aplica como MIGRACIÓN NUEVA con versión nueva (ver LEEME.md, «Si hay que revertir»); nunca se borran
-- filas del índice.
-- Al copiarla a la migración nueva, poner su versión en v_esta_version (ÚNICO cambio). Con el índice presente, ANTES de
-- cualquier DDL exige esa versión (no NULL), libre y posterior a TODO el índice, y que la aplicación de m3 sea el último
-- evento registrado («registrar antes de revertir»).
-- v4 (Codex P1): se REGISTRA A SÍ MISMA en la misma transacción que su DDL. Con el índice presente, tras el bloque (sus
-- comprobaciones, el DDL y las poscondiciones) inserta su fila: versión v_esta_version, nombre crm_sla_cola_por_filas_revertir y statements = el texto
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
      raise exception 'PREFLIGHT REVERSA M3: el índice de migraciones existe y esta reversa no tiene una versión válida (vacía, NULL o sin rellenar): pon en v_esta_version la de la migración nueva de reversa (no se toca nada)';
    end if;
    execute 'select exists (select 1 from supabase_migrations.schema_migrations m where m.version = $1)' into v_ya using v_esta_version;
    if v_ya then
      raise exception 'PREFLIGHT REVERSA M3: la versión % ya está ocupada en supabase_migrations.schema_migrations; una reversa va con una versión NUEVA (no se toca nada)', v_esta_version;
    end if;
    if not v_h_ok then
      raise exception 'PREFLIGHT REVERSA M3: el historial de la serie no es una secuencia válida:%; no se toca nada', v_h_lista;
    end if;
    if v_h_estado <> 3 then
      raise exception 'PREFLIGHT REVERSA M3: registrar antes de revertir: el historial de la serie va por %, no por M3 (eventos:%). Si M3 está viva sin registrar, corre antes registrar-indice.sql; si falta registrar una reversa, su registrar-reversa (no se toca nada)', case v_h_estado when 0 then 'ANTES' else 'M' || v_h_estado end, coalesce(v_h_lista, '');
    end if;
    if v_h_apl[3] is distinct from '20261017054427' then
      raise exception 'PREFLIGHT REVERSA M3: la aplicación vigente de m3 en el historial es la versión % (otra generación), no 20261017054427: usa la reversa del kit de esa generación (no se toca nada)', v_h_apl[3];
    end if;
    execute 'select max(m.version::numeric) from supabase_migrations.schema_migrations m where m.version ~ ''^[0-9]+$'''
      into v_h_max_global;
    if (v_esta_version::numeric > coalesce(v_h_max_global, 0)) is not true then
      raise exception 'PREFLIGHT REVERSA M3: la versión % no es posterior a TODO el índice de migraciones (máximo %): una reversa va al final del historial, después de cualquier migración ya registrada, de la serie o ajena (no se toca nada)', v_esta_version, v_h_max_global;
    end if;
  end if;
  for v_firma, v_esp in select e.key, e.value from pg_catalog.jsonb_each($esperado_preflight_reversa_m3${
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
 }
}$esperado_preflight_reversa_m3$::jsonb) e loop
    v_oid := pg_catalog.to_regprocedure(v_firma);
    if v_oid is null then
      raise exception 'PREFLIGHT REVERSA M3: no existe %', v_firma;
    end if;
    select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)), pg_catalog.md5(p.prosrc), pg_catalog.concat_ws('|', pg_catalog.pg_get_userbyid(p.proowner), p.proacl::text, pg_catalog.array_to_string(p.proconfig, ','),
         p.prosecdef::text, p.provolatile::text, p.proparallel::text, p.prorettype::pg_catalog.regtype::text,
         pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), ''))), (select pg_catalog.concat_ws('|', l.lanname, p.proisstrict::text, p.proleakproof::text, p.procost::text, p.prorows::text,
         p.prosupport::text, p.proretset::text, pg_catalog.pg_get_function_arguments(p.oid), pg_catalog.pg_get_function_result(p.oid))
         from pg_catalog.pg_language l where l.oid = p.prolang)
      into v_md5_def, v_md5_src, v_meta, v_extra from pg_catalog.pg_proc p where p.oid = v_oid;
    if v_md5_def is distinct from v_esp->>'def' or v_md5_src is distinct from v_esp->>'src' then
      raise exception 'PREFLIGHT REVERSA M3: % no es la versión que dejó 20261017054427_crm_sla_cola_por_filas (md5 def % / prosrc %; esperado % / %)', v_firma, v_md5_def, v_md5_src, v_esp->>'def', v_esp->>'src';
    end if;
    if v_meta is distinct from v_esp->>'meta' then
      raise exception 'PREFLIGHT REVERSA M3: dueño, ACL, configuración, DEFINER, volatilidad o comentario de % distintos (%)', v_firma, v_meta;
    end if;
    if v_extra is distinct from v_esp->>'extra' then
      raise exception 'PREFLIGHT REVERSA M3: otro atributo de % distinto (lenguaje, strict, leakproof, coste, filas, soporte, argumentos o resultado): %', v_firma, v_extra;
    end if;
  end loop;
  -- Cola y guardián de la cola: cuerpos y comentario anteriores a M3, byte a byte.
  v_def := $ddl_cola_antes$CREATE OR REPLACE FUNCTION crm.cola_accion_v3_fn(p_limite integer DEFAULT 50, p_senal text DEFAULT 'todas'::text, p_etapa text DEFAULT NULL::text, p_analista_id uuid DEFAULT NULL::uuid, p_cursor jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid()); v_rol text; v_global boolean; v_visibles uuid[];
  v_datos jsonb; v_ahora timestamptz; v_medianoche timestamptz;
  v_clientes jsonb; v_clientes_filtrados jsonb; v_leads jsonb;
  v_filtros jsonb; v_contexto text;
  v_prioridad integer; v_referencia timestamptz; v_clave text;
  v_totales jsonb; v_candidatas jsonb; v_total integer; v_items jsonb;
  v_restantes integer; v_anteriores integer; v_siguiente jsonb; v_ultima jsonb;
  v_proximo_cliente timestamptz;
begin
  if p_limite is null or p_limite not between 1 and 200
    or private.sla_filtros_cola_validos(p_senal, p_etapa) is not true then
    raise exception 'Filtros SLA invalidos o limite fuera de 1 a 200' using errcode = '22023';
  end if;
  -- 1) LEADS: la ventana SLA resuelve autoridad, hechos y reloj (idéntico a la v2; TODAS las filas
  --    autorizadas, no una página). Un cursor es posición de lectura, nunca autoridad.
  v_datos := private.sla_operacion_autorizada(null, true);
  v_ahora := (v_datos->>'calculado_en')::timestamptz;
  -- 2) CLIENTES: el mismo actor y ámbito que resolvió la ventana (misma derivación que
  --    sla_operacion_autorizada), el MISMO reloj y la ventana del día calculada UNA sola vez aquí
  --    (próxima medianoche de Lima, sin horario de verano). p_global viaja crudo: el helper aplica la regla.
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

  -- 3) Contexto del cursor: actor/ámbito, filtros, límite, modo, orden de leads (como la v2) y, además,
  --    las filas de clientes autorizadas (clave, responsable, sujeto, referencia, señales). Cualquier
  --    cambio entre páginas invalida el cursor (22023, reinicio), como ya pasa con los leads.
  v_filtros := jsonb_build_object('senal', p_senal, 'etapa', p_etapa, 'analista_id', p_analista_id);
  v_contexto := md5(jsonb_build_object('version', 3, 'modelo_avisos', v_datos->'modelo_avisos',
    'ambito', v_datos->'contexto_ambito', 'filtros', v_filtros, 'limite', p_limite, 'modo', v_datos->'modo',
    'orden', (select md5(coalesce(jsonb_agg(jsonb_build_array(f.value#>>'{lead,id}',
      f.value->'accion', f.value->'accion_pendiente', f.value->'senales')
      order by f.value#>>'{lead,id}'), '[]'::jsonb)::text)
      from jsonb_array_elements(v_datos->'filas') f),
    'clientes', (select md5(coalesce(jsonb_agg(jsonb_build_array(c.value->'clave', c.value->'responsable_id',
      c.value->'sujeto', c.value->'referencia_en', c.value->'senales')
      order by c.value->>'clave'), '[]'::jsonb)::text)
      from jsonb_array_elements(v_clientes) c),
    'revision', v_datos->'control_revision', 'politica', v_datos->'politica_operativa_id')::text);
  if p_cursor is not null then
    if jsonb_typeof(p_cursor) <> 'object' then
      raise exception 'Cursor SLA invalido' using errcode = '22023';
    end if;
    -- Cursor v3 = version 2 con clave tipada. Los cursores de la v2 (version 1, lead_id) se rechazan.
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
    begin
      v_prioridad := (p_cursor->>'prioridad')::integer;
      v_referencia := (p_cursor->>'referencia_en')::timestamptz;
      v_clave := p_cursor->>'clave';
      if (p_cursor->>'prioridad') !~ '^[0-9]+$'
        or v_prioridad not in (0, 10, 20, 30, 40, 50, 60, 70)
        or v_clave !~ '^(lead|tarea):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        or (v_referencia is not null and not isfinite(v_referencia)) then
        raise exception 'Cursor SLA invalido' using errcode = '22023';
      end if;
    exception when invalid_text_representation or datetime_field_overflow or invalid_datetime_format or numeric_value_out_of_range then
      raise exception 'Cursor SLA invalido' using errcode = '22023';
    end;
  end if;

  -- 4) Filtros: solo reducen; nunca amplían el ámbito. Leads como la v2. Clientes: p_etapa no nulo los
  --    excluye (no tienen etapa); p_analista_id filtra al responsable de la tarea.
  select coalesce(jsonb_agg(f.value), '[]'::jsonb) into v_leads
  from jsonb_array_elements(v_datos->'filas') f
  where (p_etapa is null or f.value#>>'{lead,etapa}' = p_etapa)
    and (p_analista_id is null or f.value#>>'{lead,analista_id}' = p_analista_id::text);
  select coalesce(jsonb_agg(c.value), '[]'::jsonb) into v_clientes_filtrados
  from jsonb_array_elements(v_clientes) c
  where p_etapa is null
    and (p_analista_id is null or c.value->>'responsable_id' = p_analista_id::text);

  -- 5) Totales sobre la UNIÓN filtrada, completos antes del límite (como la v2) + `clientes` (número de
  --    TAREAS de clientes: exactamente el conjunto que abre 'todas').
  select jsonb_build_object(
    'pendientes', coalesce(cardinality(array_agg(u.clave) filter (where (u.senales->>'pendientes')::boolean)), 0),
    'primera_atencion', coalesce(cardinality(array_agg(u.clave) filter (where (u.senales->>'primera_atencion')::boolean)), 0),
    'tareas_vencidas', coalesce(cardinality(array_agg(u.clave) filter (where (u.senales->>'tareas_vencidas')::boolean)), 0),
    'seguimientos_pendientes', coalesce(cardinality(array_agg(u.clave) filter (where (u.senales->>'seguimientos_pendientes')::boolean)), 0),
    'revisiones', coalesce(cardinality(array_agg(u.clave) filter (where (u.senales->>'revisiones')::boolean)), 0),
    'datos_incompletos', coalesce(cardinality(array_agg(u.clave) filter (where (u.senales->>'datos_incompletos')::boolean)), 0),
    'por_repartir', coalesce(cardinality(array_agg(u.clave) filter (where (u.senales->>'por_repartir')::boolean)), 0),
    'clientes', coalesce(cardinality(array_agg(u.clave) filter (where u.cliente)), 0))
    into v_totales
  from (
    select 'lead:' || (f.value#>>'{lead,id}') as clave, f.value->'senales' as senales, false as cliente
    from jsonb_array_elements(v_leads) f
    union all
    select c.value->>'clave', c.value->'senales', true
    from jsonb_array_elements(v_clientes_filtrados) c
  ) u;

  -- 6) Candidatas por señal. Leads: la acción que corresponde a la señal (idéntico a la v2) + clave +
  --    sujeto. Clientes: 'todas' los trae a todos; las demás señales, solo si su señal es true
  --    (vencida → pendientes y tareas_vencidas; de hoy → solo 'todas').
  with candidatos as (
    select f.value,
      case when p_senal = 'pendientes' then f.value->'accion_pendiente'
        when p_senal = 'todas' then f.value->'accion'
        else coalesce((select a.value from jsonb_array_elements(f.value#>'{estado,avisos}') a
          where a.value->>'bucket' = case p_senal
            when 'tareas_vencidas' then 'tarea_vencida' when 'seguimientos_pendientes' then 'seguimiento'
            when 'revisiones' then 'revision_comercial' else p_senal end limit 1),
          nullif(f.value->'accion', 'null'::jsonb), f.value->'accion_revision') end as accion
    from jsonb_array_elements(v_leads) f
    where (p_senal = 'todas' and f.value->'accion' <> 'null'::jsonb)
      or (p_senal <> 'todas' and (f.value->'senales'->>p_senal)::boolean is true)
  )
  select coalesce(jsonb_agg(c.accion || jsonb_build_object(
      'estado', c.value->'estado', 'lead', c.value->'lead', 'senales', c.value->'senales',
      'clave', 'lead:' || (c.value#>>'{lead,id}'),
      'sujeto', jsonb_build_object('tipo', 'lead', 'id', c.value#>'{lead,id}',
        'nombre', c.value#>'{lead,nombre_completo}'))), '[]'::jsonb)
    into v_candidatas from candidatos c;
  select v_candidatas || coalesce(jsonb_agg(c.value - 'responsable_id'), '[]'::jsonb) into v_candidatas
  from jsonb_array_elements(v_clientes_filtrados) c
  where p_senal = 'todas' or (c.value->'senales'->>p_senal)::boolean is true;
  v_total := jsonb_array_length(v_candidatas);

  -- 7) UNA paginación keyset sobre la unión: (prioridad, referencia_en nulls last, clave). La clave se
  --    compara en collation "C": orden estable e independiente del locale.
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
  v_anteriores := v_total - v_restantes;
  if v_restantes > p_limite then
    v_ultima := v_items->(jsonb_array_length(v_items) - 1);
    v_siguiente := jsonb_build_object('version', 2, 'contexto', v_contexto, 'prioridad', v_ultima->'prioridad',
      'referencia_en', v_ultima->'referencia_en', 'clave', v_ultima->'clave');
  end if;

  -- 8) proximo_cambio_en: el de los leads, el próximo vencimiento de cliente (> ahora) y la próxima
  --    medianoche de Lima (entrada de tareas nuevas al día). least() ignora los nulos.
  select min((c.value->>'referencia_en')::timestamptz) into v_proximo_cliente
  from jsonb_array_elements(v_clientes) c
  where (c.value->>'referencia_en')::timestamptz > v_ahora;

  return jsonb_build_object('version', 3, 'modelo_avisos', v_datos->'modelo_avisos',
    'proximo_cambio_en', least(nullif(v_datos->>'proximo_cambio_en', '')::timestamptz, v_proximo_cliente, v_medianoche),
    'modo', v_datos->'modo', 'control_revision', v_datos->'control_revision',
    'calculado_en', v_datos->'calculado_en', 'politica_operativa_id', v_datos->'politica_operativa_id',
    'politica_operativa_version', v_datos->'politica_operativa_version',
    'total_items', v_total, 'hay_mas', v_restantes > p_limite, 'totales', v_totales, 'items', v_items,
    'filtros', v_filtros, 'limite', p_limite, 'cursor_siguiente', v_siguiente,
    'rango', jsonb_build_object('desde', case when jsonb_array_length(v_items) = 0 then 0 else v_anteriores + 1 end,
      'hasta', case when jsonb_array_length(v_items) = 0 then 0 else v_anteriores + jsonb_array_length(v_items) end));
end;
$function$
$ddl_cola_antes$;
  if pg_catalog.md5(v_def) is distinct from '1ec76074c9b5650cb8bac4c79440eccb' then
    raise exception 'PREFLIGHT REVERSA M3: el DDL de la cola v3 no es el ensayado (md5 esperado 1ec76074c9b5650cb8bac4c79440eccb)';
  end if;
  execute v_def;
  execute $c_col_antes$comment on function crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb) is 'Cola del dia v3 (plan 28/09/2026): UNA cola con las filas de leads de la ventana SLA (identicas a la v2) y las tareas de clientes del dia; identidad tipada clave = lead:<uuid> | tarea:<uuid>; cursor version 2 cuyo contexto cubre a los clientes (los de la v2 se rechazan, 22023); p_etapa no nulo excluye clientes; p_analista_id filtra al responsable; totales completos antes del limite + clientes; proximo_cambio_en incluye el proximo vencimiento de cliente y la medianoche de Lima; sin telefono en el payload. SECURITY DEFINER justificado: reutiliza private.sla_operacion_autorizada (DEFINER sin grants externos) y ejecuta el helper INVOKER como dueno; el actor es auth.uid(), nunca un parametro. No sustituye a la v2.'$c_col_antes$;
  v_def := $ddl_assert_cola_v3_antes$CREATE OR REPLACE FUNCTION private.assert_cola_v3()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_puerta constant text := 'crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)';
  v_helper constant text := 'private.tareas_clientes_autorizadas(uuid,uuid[],text,boolean,timestamptz,timestamptz)';
  v_propio constant text := 'private.assert_cola_v3()';
  v record; v_cuerpo text; v_rol text; v_firma text; v_huella text; v_medida text;
  v_sin_sellar boolean := false;
begin
  -- 1. Existencia de las tres piezas.
  foreach v_firma in array array[v_puerta, v_helper, v_propio] loop
    if to_regprocedure(v_firma) is null then
      raise exception 'COLA_V3: falta %', v_firma;
    end if;
  end loop;
  -- 2. Dependencias por CUERPO ejecutable (sin comentarios), como assert_sla_nucleo.
  for v in select * from (values
    (v_puerta, 'sla_operacion_autorizada'), (v_puerta, 'sla_filtros_cola_validos'),
    (v_puerta, 'tareas_clientes_autorizadas'), (v_puerta, 'rol_crm'),
    (v_puerta, 'es_lector_global'), (v_puerta, 'vendedor_ids_visibles'),
    (v_helper, 'postventa_visible_actor'), (v_helper, 'inversionista_canonica')
  ) d(firma, dependencia) loop
    select regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'gs')
      into strict v_cuerpo from pg_proc p where p.oid = v.firma::regprocedure;
    if v_cuerpo !~ ('\mprivate\.' || v.dependencia || '\s*\(') then
      raise exception 'COLA_V3: % dejo de consumir private.%', v.firma, v.dependencia;
    end if;
  end loop;
  -- 3. La puerta no consulta hechos crudos: todo entra por la ventana SLA y el helper.
  select regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'gs')
    into strict v_cuerpo from pg_proc p where p.oid = v_puerta::regprocedure;
  if v_cuerpo ~ '\mcrm\.\s*(leads|tareas|actividades|lead_sla_etapas|inversionistas|equipo)\M' then
    raise exception 'COLA_V3: la puerta consulta hechos crudos (tablas de crm)';
  end if;
  -- 4. El helper no interpreta autenticación: recibe el actor de la puerta.
  select p.prosrc into strict v_cuerpo from pg_proc p where p.oid = v_helper::regprocedure;
  if v_cuerpo ~* '\mauth\s*\.' then
    raise exception 'COLA_V3: el helper interpreta autenticacion (auth.)';
  end if;
  -- 5. Propiedades: STABLE las tres, search_path vacío, dueño postgres; DEFINER solo la puerta y este
  --    trinquete (el helper es INVOKER y corre dentro de la puerta).
  for v in select p.oid, p.proname, p.prosecdef, p.provolatile, p.proconfig, p.proowner
    from pg_proc p where p.oid in (v_puerta::regprocedure, v_helper::regprocedure, v_propio::regprocedure) loop
    if v.provolatile <> 's' or not coalesce(v.proconfig @> array['search_path=""'], false)
       or v.proowner <> 'postgres'::regrole::oid
       or v.prosecdef <> (v.proname <> 'tareas_clientes_autorizadas') then
      raise exception 'COLA_V3: propiedades incorrectas de % (volatilidad %, definer %, config %, dueno %)',
        v.proname, v.provolatile, v.prosecdef, v.proconfig, v.proowner::regrole;
    end if;
  end loop;
  -- 6. ACL efectiva: helper y trinquete sin EXECUTE para la API ni grants externos; la puerta
  --    EXACTAMENTE dueño + authenticated (ni anon, ni service_role, ni PUBLIC).
  foreach v_rol in array array['anon', 'authenticated', 'service_role'] loop
    if has_function_privilege(v_rol, v_helper, 'EXECUTE') or has_function_privilege(v_rol, v_propio, 'EXECUTE') then
      raise exception 'COLA_V3: % puede ejecutar el helper o el trinquete', v_rol;
    end if;
    if has_function_privilege(v_rol, v_puerta, 'EXECUTE') <> (v_rol = 'authenticated') then
      raise exception 'COLA_V3: EXECUTE de la puerta incorrecto para %', v_rol;
    end if;
  end loop;
  if exists (select 1 from pg_proc p
      cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      where p.oid in (v_helper::regprocedure, v_propio::regprocedure) and a.grantee <> p.proowner) then
    raise exception 'COLA_V3: el helper o el trinquete tienen grants externos';
  end if;
  if exists (select 1 from pg_proc p
      cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      where p.oid = v_puerta::regprocedure
        and a.grantee not in (p.proowner, 'authenticated'::regrole::oid)) then
    raise exception 'COLA_V3: la puerta tiene grants fuera de authenticated';
  end if;
  -- 7. Huellas md5 (pg_get_functiondef) ADEMÁS de lo anterior, no en su lugar. 'SIN_SELLAR' es el TODO
  --    del integrador (sellado en dos pasadas, ver cabecera): el postflight y el gate lo rechazan.
  for v_firma, v_huella in select * from (values
    (v_puerta, '1ec76074c9b5650cb8bac4c79440eccb'),
    (v_helper, '234ee27f745ef1817be0e0cbdd2b2e25')
  ) as s(firma, huella) loop
    v_medida := md5(pg_get_functiondef(v_firma::regprocedure));
    if v_huella = 'SIN_SELLAR' then
      v_sin_sellar := true;
      raise warning 'COLA_V3: huella de % SIN SELLAR (md5 medido: %)', v_firma, v_medida;
    elsif v_medida is distinct from v_huella then
      raise exception 'COLA_V3: el cuerpo de % cambio (md5 %); re-sellar a conciencia', v_firma, v_medida;
    end if;
  end loop;
  raise notice 'COLA_V3_OK';
  return 'OK: cola v3 — puerta DEFINER (EXECUTE solo authenticated) sobre la ventana SLA y el helper de clientes; helper INVOKER sin grants ni auth.; sin hechos crudos en la puerta; huellas '
    || case when v_sin_sellar then 'SIN SELLAR (TODO integrador)' else 'selladas' end;
end;
$function$
$ddl_assert_cola_v3_antes$;
  if pg_catalog.md5(v_def) is distinct from '162fe9e053c8b57f8b501dadbe2afca7' then
    raise exception 'PREFLIGHT REVERSA M3: el DDL de assert_cola_v3 no es el ensayado (md5 esperado 162fe9e053c8b57f8b501dadbe2afca7)';
  end if;
  execute v_def;
  for v_firma, v_esp in select e.key, e.value from pg_catalog.jsonb_each($esperado_postflight_reversa_m3${
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
}$esperado_postflight_reversa_m3$::jsonb) e loop
    v_oid := pg_catalog.to_regprocedure(v_firma);
    if v_oid is null then
      raise exception 'POSTFLIGHT REVERSA M3: no existe %', v_firma;
    end if;
    select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)), pg_catalog.md5(p.prosrc), pg_catalog.concat_ws('|', pg_catalog.pg_get_userbyid(p.proowner), p.proacl::text, pg_catalog.array_to_string(p.proconfig, ','),
         p.prosecdef::text, p.provolatile::text, p.proparallel::text, p.prorettype::pg_catalog.regtype::text,
         pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), ''))), (select pg_catalog.concat_ws('|', l.lanname, p.proisstrict::text, p.proleakproof::text, p.procost::text, p.prorows::text,
         p.prosupport::text, p.proretset::text, pg_catalog.pg_get_function_arguments(p.oid), pg_catalog.pg_get_function_result(p.oid))
         from pg_catalog.pg_language l where l.oid = p.prolang)
      into v_md5_def, v_md5_src, v_meta, v_extra from pg_catalog.pg_proc p where p.oid = v_oid;
    if v_md5_def is distinct from v_esp->>'def' or v_md5_src is distinct from v_esp->>'src' then
      raise exception 'POSTFLIGHT REVERSA M3: % no es la versión anterior (md5 def % / prosrc %; esperado % / %)', v_firma, v_md5_def, v_md5_src, v_esp->>'def', v_esp->>'src';
    end if;
    if v_meta is distinct from v_esp->>'meta' then
      raise exception 'POSTFLIGHT REVERSA M3: dueño, ACL, configuración, DEFINER, volatilidad o comentario de % distintos (%)', v_firma, v_meta;
    end if;
    if v_extra is distinct from v_esp->>'extra' then
      raise exception 'POSTFLIGHT REVERSA M3: otro atributo de % distinto (lenguaje, strict, leakproof, coste, filas, soporte, argumentos o resultado): %', v_firma, v_extra;
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
      raise exception 'PREFLIGHT REVERSA M3: la reversa no trae una versión válida para registrarse; no queda nada aplicado';
    end if;
    execute 'insert into supabase_migrations.schema_migrations (version, name, statements) values ($1, $2, $3)'
      using v_version, 'crm_sla_cola_por_filas_revertir', array[v_cuerpo];
    raise notice 'REGISTRO REVERSA: crm_sla_cola_por_filas_revertir % registrada en la misma transacción que su DDL', v_version;
  end if;
end $reversa$;
commit;

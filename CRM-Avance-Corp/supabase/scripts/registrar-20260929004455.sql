-- Registra 20260929004455 (crm_cola_accion_v3_clientes) CON su cuerpo — fail-closed.
-- GENERADO desde la migracion del archivo (mismo patron que registrar-20260905131000.sql):
-- no editar a mano; regenerar. Orden de la casa: PRIMERO aplicar la migracion con
-- `supabase db query --linked --file`, DESPUES este registrador (el pin se niega a
-- registrar lo que no paso).
do $reg_cola_v3$
declare v_n int; v_cuerpo text; v_veredicto text;
begin
  v_cuerpo := $mig_cola_v3$-- Cola del día con clientes — F1 (servidor). Plan v2 aprobado por Miguel el 28/09/2026 tras la
-- refutación de Codex (3 P1 + 6 P2 aceptados); SQL revisado por auditor-rls (P2/P3 aplicados):
--   BASE DE CONOCIMINETO/AVANCECORP/Cola del dia con clientes - plan (2026-09-28).md
--
-- QUÉ. Miguel: «¿en Gestión diaria me salen las llamadas agendadas con clientes?» → hoy no: la cola
-- (crm.cola_accion_v2_fn) solo trae leads; las tareas de clientes (perfil_id | inversionista_id) quedan
-- fuera por construcción (private.sla_tareas_hechos hace join por lead_id). Opción elegida: SERVIDOR,
-- una sola verdad para analista, supervisor y gerencia.
--
-- CÓMO (decisiones 2–7 del plan):
--  · NO se toca la v2 ni el núcleo SLA (sla_operacion_leads, sla_tareas_hechos, sla_operacion_autorizada):
--    la v2 sigue viva para Seguimiento y Hoy del supervisor y para los asserts que exigen su firma.
--  · private.tareas_clientes_autorizadas(p_uid, p_visibles, p_rol, p_global, p_ahora, p_fin_dia): STABLE,
--    INVOKER, search_path '' y SIN auth.: recibe el actor y la ventana del día de la puerta (la medianoche
--    de Lima se calcula en UN solo sitio, la puerta, y viaja como límite superior exclusivo). Reproduce
--    TODAS las ramas de la RLS de crm.tareas (tareas_select: vendedor_id ∈ visibles · vendedor_id null y
--    asignado_supervisor_id ∈ visibles · gerencia) y la restrictiva de postventa
--    (postventa_visible_actor(inversionista_id, actor), gerencia incluida; una permisiva satisfecha NO
--    levanta la restrictiva). Regla de PRODUCTO, no equivalencia con RLS: lector global sin rol CRM y
--    Directorio no reciben filas de clientes. Valida integridad ANTES del recorte (sujeto único con
--    num_nonnulls(lead_id, perfil_id, inversionista_id) = 1 y vence_en finito → 22000 con detail) y recorta
--    al día: vencida si vence_en <= p_ahora; de hoy si vence_en < p_fin_dia.
--  · crm.cola_accion_v3_fn: misma firma que la v2, DEFINER + search_path '' (justificación: reutiliza
--    private.sla_operacion_autorizada(null,true), DEFINER sin grants externos, y ejecuta el helper INVOKER
--    como su dueño; el actor sale de auth.uid(), nunca de un parámetro). UNA operación: filas de leads de
--    la ventana SLA (todas, no la página de la v2) + tareas de clientes autorizadas → filtros con semántica
--    para ambos (p_etapa no nulo excluye clientes; p_analista_id = responsable de la tarea; nunca amplían)
--    → contexto, totales y orden sobre la UNIÓN → una sola paginación keyset (prioridad, referencia_en
--    nulls last, clave) con identidad tipada clave = lead:<uuid> | tarea:<uuid>. Cursor version 2
--    (version, contexto, prioridad, referencia_en, clave); el contexto md5 lleva 'version',3 y las filas de
--    clientes autorizadas; los cursores de la v2 se rechazan (22023). Items de lead = v2 + clave +
--    sujeto{tipo:'lead',id,nombre}; items de cliente = lead_id/lead/estado nulos, tarea_id, bucket
--    tarea_vencida|tarea_hoy con la prioridad/severidad del bucket equivalente de lead (20/critica,
--    30/media), referencia_en = vence_en, 7 señales (pendientes y tareas_vencidas solo si vencida),
--    sujeto{tipo:'cliente',perfil_id,inversionista_id,nombre}. Sin teléfono en el payload. totales añade
--    `clientes`; proximo_cambio_en = mínimo entre el de leads, el próximo vencimiento de cliente y la
--    próxima medianoche de Lima. version: 3.
--  · private.assert_cola_v3(): trinquete propio (no se toca assert_sla_nucleo).
--
-- DESPLIEGUE: F1 instala la v3 sin consumidores; el front cambia en F2 con clave de caché propia
-- (cola-dia-v3). Índice parcial candidato (vendedor_id, vence_en, id) where activo and estado = 'pendiente'
-- and lead_id is null: SOLO si EXPLAIN en el banco lo justifica (no va en esta migración). El mapa
-- canónico de inversionistas se calcula UNA vez por llamada (CTE materialized); si EXPLAIN dice otra cosa,
-- se decide con esa evidencia.
--
-- SELLADO EN DOS PASADAS (obligatorio antes del merge; auditor-rls P2-1):
--   1) Primera pasada en un banco limpio con la válvula de medición:
--        PGOPTIONS="-c crm.op_privilegiada=on" psql ... -v ON_ERROR_STOP=1 -f <esta migración>
--      El postflight imprime «COLA_V3 huellas para sellar: puerta=<md5> helper=<md5>».
--   2) Sustituir los dos 'SIN_SELLAR' de private.assert_cola_v3 por esos md5 y volver a aplicar en un banco
--      limpio SIN la válvula: el postflight rechaza cualquier 'SIN SELLAR' (raise) y el gate test-rls.mjs
--      con CRM_RLS_EXIGE_COLA_V3=1 también. El merge exige cero SIN_SELLAR.
--      Medición manual equivalente:
--        select md5(pg_get_functiondef('crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)'::regprocedure)),
--               md5(pg_get_functiondef('private.tareas_clientes_autorizadas(uuid,uuid[],text,boolean,timestamptz,timestamptz)'::regprocedure));
--
-- Reversa: documentada al final del archivo.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- =====================================================================
-- 0) PREFLIGHT: el mundo que la v3 asume, verificado en el instante.
-- =====================================================================
do $preflight$
declare v_firma text; v_huella text;
begin
  if to_regprocedure('crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)') is not null
     or to_regprocedure('private.tareas_clientes_autorizadas(uuid,uuid[],text,boolean,timestamptz,timestamptz)') is not null
     or to_regprocedure('private.assert_cola_v3()') is not null then
    raise exception 'COLA_V3 preflight: la puerta v3, su helper o su trinquete ya existen';
  end if;
  -- Huellas vivas medidas el 28/09/2026 (producción = migraciones); prefijo de 12 caracteres del md5 de
  -- pg_get_functiondef. La v3 replica el contrato de la v2 y bebe de la ventana; si cambiaron, no se
  -- adapta en silencio. sla_tareas_hechos se vigila porque la v3 ASUME que las tareas sin lead no entran
  -- por ahí (si entraran, los clientes se contarían dos veces).
  for v_firma, v_huella in select * from (values
    ('private.sla_operacion_autorizada(uuid[],boolean)', 'ea7ee548df90'),
    ('crm.cola_accion_v2_fn(integer,text,text,uuid,jsonb)', 'ef9b56eddeaa'),
    ('private.sla_tareas_hechos(uuid[],boolean,uuid[])', '01fc105bddef')
  ) as h(firma, huella) loop
    if to_regprocedure(v_firma) is null
       or left(md5(pg_get_functiondef(to_regprocedure(v_firma))), 12) is distinct from v_huella then
      raise exception 'COLA_V3 preflight: cambió % en vivo (md5 %); revisar el contrato antes de continuar',
        v_firma, coalesce(md5(pg_get_functiondef(to_regprocedure(v_firma))), 'ausente');
    end if;
  end loop;
  -- Dependencias que la puerta y el helper consumen tal cual.
  foreach v_firma in array array[
    'private.sla_filtros_cola_validos(text,text)', 'private.rol_crm(uuid)', 'private.es_lector_global()',
    'private.vendedor_ids_visibles(uuid)', 'private.postventa_visible_actor(uuid,uuid)',
    'private.inversionista_canonica(uuid)', 'private.assert_sla_nucleo()', 'private.assert_gestion_diaria_analista()'
  ] loop
    if to_regprocedure(v_firma) is null then
      raise exception 'COLA_V3 preflight: falta %', v_firma;
    end if;
  end loop;
  -- El check del sujeto único y la columna inversionista_id existen (F6): el helper los asume.
  if not exists (select 1 from pg_constraint c where c.conrelid = 'crm.tareas'::regclass and c.conname = 'tareas_un_solo_sujeto')
     or not exists (select 1 from pg_attribute a where a.attrelid = 'crm.tareas'::regclass and a.attname = 'inversionista_id' and not a.attisdropped) then
    raise exception 'COLA_V3 preflight: crm.tareas no tiene la forma esperada (tareas_un_solo_sujeto / inversionista_id)';
  end if;
  perform private.assert_sla_nucleo();
end $preflight$;

-- =====================================================================
-- 1) HELPER: tareas de clientes del día autorizadas para el actor recibido.
--    INVOKER a propósito: corre DENTRO de la puerta DEFINER (como su dueño) y no interpreta
--    autenticación; nadie de la API puede ejecutarlo directo (sin EXECUTE).
-- =====================================================================
create function private.tareas_clientes_autorizadas(
  p_uid uuid, p_visibles uuid[], p_rol text, p_global boolean, p_ahora timestamptz, p_fin_dia timestamptz
) returns table (
  tarea_id uuid, perfil_id uuid, inversionista_id uuid, nombre text,
  responsable_id uuid, vence_en timestamptz, bucket text
)
language plpgsql stable security invoker set search_path = ''
as $function$
declare
  v_visibles uuid[] := coalesce(p_visibles, '{}'::uuid[]);
  v_anomalias uuid[];
  v_filas jsonb;
begin
  -- Admisión (defensa en profundidad: la puerta ya la resolvió con la ventana SLA).
  if p_uid is null or p_ahora is null or not isfinite(p_ahora)
     or (p_rol is null and not coalesce(p_global, false)) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  -- La ventana del día la fija la puerta (un solo reloj y una sola medianoche de Lima por consulta):
  -- límite superior EXCLUSIVO, posterior al instante de cálculo.
  if p_fin_dia is null or not isfinite(p_fin_dia) or p_fin_dia <= p_ahora then
    raise exception 'Ventana del dia invalida' using errcode = '22023';
  end if;
  -- Regla de PRODUCTO (no equivalencia con la RLS): el lector global sin rol CRM y Directorio no
  -- reciben filas de clientes; una persona con rol CRM operativo se trata por su rol CRM aunque
  -- p_global sea true. La RLS de crm.tareas sí les muestra esas filas; aquí se decide no traerlas.
  if p_rol is null or p_rol = 'directorio' then
    return;
  end if;

  -- UNA lectura de crm.tareas. El conjunto AUTORIZADO completo (antes del recorte del día) valida la
  -- integridad; el recorte se aplica al emitir. Ramas = tareas_select + restrictiva de postventa (que
  -- se evalúa para TODA tarea de inversionista aunque la permisiva ya esté satisfecha).
  -- Nombre del sujeto: perfil → public.perfiles.nombre_completo (solo el nombre, sin PII de más);
  -- inversionista → vía canónica de postventa (postventa_tarea_json): perfiles del grupo canónico y,
  -- si no hay perfil, el lead enlazado a la identidad (como la cartera F5); si nada, marcador neutro.
  -- El mapa canónico se calcula UNA vez por llamada (materialized) y solo si hay tareas de inversionista.
  with canonicas as materialized (
    select i.id, i.perfil_id, private.inversionista_canonica(i.id) as canon
    from crm.inversionistas i
  )
  select coalesce(array_agg(a.id order by a.id) filter (where a.anomalia), '{}'::uuid[]),
         coalesce(jsonb_agg(jsonb_build_object(
             'tarea_id', a.id, 'perfil_id', a.perfil_id, 'inversionista_id', a.inversionista_id,
             'nombre', a.nombre, 'responsable_id', a.vendedor_id, 'vence_en', a.vence_en,
             'bucket', case when a.vence_en <= p_ahora then 'tarea_vencida' else 'tarea_hoy' end)
           order by a.vence_en, a.id)
           filter (where not a.anomalia and a.vence_en < p_fin_dia), '[]'::jsonb)
    into v_anomalias, v_filas
  from (
    select t.id, t.perfil_id, t.inversionista_id, t.vendedor_id, t.vence_en,
      (num_nonnulls(t.lead_id, t.perfil_id, t.inversionista_id) <> 1 or not isfinite(t.vence_en)) as anomalia,
      coalesce(
        case when t.perfil_id is not null then
          (select nullif(btrim(p.nombre_completo), '') from public.perfiles p where p.id = t.perfil_id)
        end,
        pn.nombre,
        'Identidad pendiente de completar') as nombre
    from crm.tareas t
    left join lateral (
      select g.canon as id from canonicas g where g.id = t.inversionista_id
    ) canon on true
    left join lateral (
      select coalesce(
        (select nullif(btrim(p.nombre_completo), '')
           from canonicas g
           join public.perfiles p on p.id = g.perfil_id
          where g.canon = canon.id
            and nullif(btrim(p.nombre_completo), '') is not null
          order by (g.id = canon.id) desc, coalesce(p.activo, false) desc, p.id
          limit 1),
        (select nullif(btrim(l.nombre_completo), '')
           from crm.leads l
           join canonicas g on g.id = l.inversionista_id
          where g.canon = canon.id
            and nullif(btrim(l.nombre_completo), '') is not null
          order by (l.inversionista_id = canon.id) desc, l.actualizado_en desc, l.id
          limit 1)
      ) as nombre
      where canon.id is not null
    ) pn on true
    where t.activo and t.estado = 'pendiente'
      and (t.perfil_id is not null or t.inversionista_id is not null)
      and (p_rol = 'gerencia'
        or t.vendedor_id = any(v_visibles)
        or (t.vendedor_id is null and t.asignado_supervisor_id = any(v_visibles)))
      and (t.inversionista_id is null or private.postventa_visible_actor(t.inversionista_id, p_uid))
  ) a;

  if cardinality(v_anomalias) > 0 then
    raise exception 'No se pudo confirmar la integridad de las tareas de clientes'
      using errcode = '22000',
        detail = format('%s tarea(s) con sujeto no unico (num_nonnulls(lead_id, perfil_id, inversionista_id) <> 1) o vence_en no finito: %s',
          cardinality(v_anomalias), array_to_string(v_anomalias, ', ')),
        hint = 'Corregir esas filas de crm.tareas antes de volver a consultar la cola del dia';
  end if;

  return query
    select r.tarea_id, r.perfil_id, r.inversionista_id, r.nombre, r.responsable_id, r.vence_en, r.bucket
    from jsonb_to_recordset(v_filas) as r(tarea_id uuid, perfil_id uuid, inversionista_id uuid,
      nombre text, responsable_id uuid, vence_en timestamptz, bucket text)
    order by r.vence_en, r.tarea_id;
end;
$function$;
revoke all on function private.tareas_clientes_autorizadas(uuid,uuid[],text,boolean,timestamptz,timestamptz)
  from public, anon, authenticated, service_role;

-- =====================================================================
-- 2) PUERTA: la cola del día v3 (leads + clientes), misma firma que la v2.
--    SECURITY DEFINER justificado: bebe de private.sla_operacion_autorizada (DEFINER sin grants
--    externos) y ejecuta el helper INVOKER como dueño; el actor es auth.uid(), nunca un parámetro.
-- =====================================================================
create function crm.cola_accion_v3_fn(
  p_limite integer default 50, p_senal text default 'todas', p_etapa text default null,
  p_analista_id uuid default null, p_cursor jsonb default null
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
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
$function$;
revoke all on function crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)
  from public, anon, authenticated, service_role;
grant execute on function crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb) to authenticated;

-- =====================================================================
-- 3) TRINQUETE propio de la v3 (no se toca assert_sla_nucleo). Inspecciona cuerpos ejecutables,
--    propiedades en pg_proc y ACL efectiva; las huellas md5 van ADEMÁS, no en lugar.
-- =====================================================================
create function private.assert_cola_v3()
returns text language plpgsql stable security definer set search_path = ''
as $function$
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
$function$;
revoke all on function private.assert_cola_v3() from public, anon, authenticated, service_role;

-- =====================================================================
-- 4) COMENTARIOS
-- =====================================================================
comment on function private.tareas_clientes_autorizadas(uuid,uuid[],text,boolean,timestamptz,timestamptz) is
  'Cola v3: tareas de CLIENTES (perfil_id | inversionista_id) del dia autorizadas para el actor recibido. Reproduce todas las ramas de tareas_select (vendedor visible; sin vendedor y bandeja de supervisor visible; gerencia) y la restrictiva de postventa (postventa_visible_actor, evaluada aunque la permisiva ya se cumpla). Regla de PRODUCTO: lector global sin rol CRM y Directorio no reciben filas. Valida integridad ANTES del recorte (sujeto unico y vence_en finito → 22000) y recorta al dia con la ventana que le pasa la puerta (vencida <= p_ahora; de hoy < p_fin_dia). INVOKER sin auth.: la ejecuta la puerta DEFINER; sin EXECUTE para la API.';
comment on function crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb) is
  'Cola del dia v3 (plan 28/09/2026): UNA cola con las filas de leads de la ventana SLA (identicas a la v2) y las tareas de clientes del dia; identidad tipada clave = lead:<uuid> | tarea:<uuid>; cursor version 2 cuyo contexto cubre a los clientes (los de la v2 se rechazan, 22023); p_etapa no nulo excluye clientes; p_analista_id filtra al responsable; totales completos antes del limite + clientes; proximo_cambio_en incluye el proximo vencimiento de cliente y la medianoche de Lima; sin telefono en el payload. SECURITY DEFINER justificado: reutiliza private.sla_operacion_autorizada (DEFINER sin grants externos) y ejecuta el helper INVOKER como dueno; el actor es auth.uid(), nunca un parametro. No sustituye a la v2.';
comment on function private.assert_cola_v3() is
  'Trinquete de la cola v3: dependencias por cuerpo ejecutable, sin hechos crudos en la puerta, helper sin auth., propiedades en pg_proc (STABLE, DEFINER solo puerta y trinquete, search_path vacio, dueno postgres) y ACL efectiva (helper/trinquete sin EXECUTE externo; puerta exactamente authenticated); huellas md5 ademas (SIN_SELLAR = pendiente de medir en el banco; el postflight y el gate lo rechazan).';

-- =====================================================================
-- 5) POSTFLIGHT: la v3 en su forma y el mundo vecino intacto. Sellado mecánico (auditor-rls P2-1):
--    un veredicto con «SIN SELLAR» solo se tolera en la PRIMERA pasada de medición en el banco, con la
--    válvula crm.op_privilegiada = 'on' (PGOPTIONS="-c crm.op_privilegiada=on"); sin ella, la migración
--    no se aplica hasta sellar.
-- =====================================================================
do $postflight$
declare v_veredicto text;
begin
  v_veredicto := private.assert_cola_v3();
  raise notice 'COLA_V3 postflight: %', v_veredicto;
  raise notice 'COLA_V3 huellas para sellar (sustituir SIN_SELLAR en private.assert_cola_v3): puerta=% helper=%',
    md5(pg_get_functiondef('crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)'::regprocedure)),
    md5(pg_get_functiondef('private.tareas_clientes_autorizadas(uuid,uuid[],text,boolean,timestamptz,timestamptz)'::regprocedure));
  if position('SIN SELLAR' in v_veredicto) > 0
     and coalesce(current_setting('crm.op_privilegiada', true), 'off') <> 'on' then
    raise exception 'COLA_V3 postflight: huellas SIN SELLAR. Primera pasada: aplicar con crm.op_privilegiada=on para medir; despues sustituir SIN_SELLAR por los md5 impresos y volver a aplicar en un banco limpio';
  end if;
  -- La v2 y su mundo no se tocan: los trinquetes vecinos siguen en verde.
  perform private.assert_sla_nucleo();
  perform private.assert_gestion_diaria_analista();
end $postflight$;
notify pgrst, 'reload schema';
commit;

-- =====================================================================
-- REVERSA (documentada; no se ejecuta aquí). La v2 y sus sellos no se tocan. No retirar la v3 mientras
-- haya bundles del front que la consuman (F2 en adelante: CERRAR → OBSERVAR → DERRIBAR).
--   begin;
--   drop function if exists private.assert_cola_v3();
--   drop function if exists crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb);
--   drop function if exists private.tareas_clientes_autorizadas(uuid,uuid[],text,boolean,timestamptz,timestamptz);
--   notify pgrst, 'reload schema';
--   commit;
--   -- y retirar la fila de esta migración en supabase/migrations/MIGRACIONES.md.
-- =====================================================================
$mig_cola_v3$;

  -- 1) PIN: lo que la migracion hizo ES verdad — la puerta, el helper y el trinquete existen
  --    y el trinquete responde OK con las huellas selladas.
  if to_regprocedure('crm.cola_accion_v3_fn(integer,text,text,uuid,jsonb)') is null
     or to_regprocedure('private.tareas_clientes_autorizadas(uuid,uuid[],text,boolean,timestamptz,timestamptz)') is null
     or to_regprocedure('private.assert_cola_v3()') is null then
    raise exception 'registrar cola v3: faltan objetos — aplicar la migracion antes de registrar';
  end if;
  v_veredicto := private.assert_cola_v3();
  if v_veredicto not like 'OK%' or v_veredicto like '%SIN SELLAR%' then
    raise exception 'registrar cola v3: el trinquete no esta en verde o sin sellar: %', v_veredicto;
  end if;

  -- 2) La version no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260929004455' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar cola v3: la version 20260929004455 existe con OTRO cuerpo — investigar antes de tocar';
  end if;

  -- 3) Registro (idempotente).
  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('20260929004455', 'crm_cola_accion_v3_clientes', array[v_cuerpo])
  on conflict (version) do nothing;

  -- 4) RELECTURA fail-closed: la fila EXACTA, o se cae la transaccion entera.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260929004455' and name = 'crm_cola_accion_v3_clientes'
     and cardinality(statements) = 1 and statements[1] = v_cuerpo;
  if v_n <> 1 then
    raise exception 'registrar cola v3: la relectura no encontro la fila exacta';
  end if;
  raise notice 'REGISTRO_COLA_V3_OK';
end $reg_cola_v3$;

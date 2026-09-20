-- Registra 20260920041500 (crm_gestion_diaria_analista) CON su cuerpo — fail-closed.
-- GENERADO por supabase/scripts/gestion-diaria-analista/generar-registrador.mjs
-- leyendo la migración del archivo: no editar a mano; regenerar. Orden de la
-- casa: PRIMERO aplicar la migración con `db query --linked --file`, DESPUÉS
-- este registrador. Prerrequisito: 20260920005000 (F2) instalada y registrada.
do $reg_gd_analista$
declare v_n int; v_cuerpo text;
begin
  v_cuerpo := $mig_gd_analista$-- 20260920041500_crm_gestion_diaria_analista.sql
-- Gestión Diaria · FASE 3 — el día del analista («Mi día»).
-- Plan aprobado el 19/09/2026: docs/gestion-diaria/PLAN-POR-FASES-2026-09-19.md (Fase 3).
--
-- QUÉ HACE. Una sola lectura, `crm.gestion_diaria_analista_fn(p_dia, p_analista_id)`,
-- devuelve todo lo que la pantalla del analista necesita además de la cola:
--   · `marcador` del día: llamadas, contestadas, útiles, tasa de contacto con su
--     nivel (Bien/Atención/Bajo solo con ≥ 5 llamadas útiles, decisión #7 de
--     Miguel), leads tocados, citas agendadas, primera y última llamada,
--     desglose por resultado y LLAMADAS POR HORA (Lima), decisión #8;
--   · `compromisos`: tareas pendientes de llamada/cita a partir de mañana, sobre
--     leads que ya conversaron (contactado, cita agendada, propuesta);
--   · `cartera`: señales por lead abierto del analista para enriquecer la cola
--     (llamadas del ciclo, intentos sin respuesta, última llamada y su
--     resultado, última conversación, observación del número errado, próxima
--     tarea) y el bucket nuevo `sin_conversacion`, que ESTRENA la perilla
--     `crm.politica_abandono.dias_abandono`: días sin conversación real medidos
--     ante el dueño actual, greatest(última conversación, tenencia_desde); los
--     intentos no protegen (decisión de Miguel del 16/08);
--   · `descartados` del día por el propio analista (para «Deshacer» hasta 24 h,
--     que hasta hoy solo vivía 15 s en el toast).
-- La COLA sigue saliendo de `crm.cola_accion_v2_fn` (no se toca; su md5 vivo se
-- comprueba en el preflight y su forma en el gate). El orden del día lo decide
-- el front: lead nuevo sin primer intento → vencidas → hoy → sin conversación
-- (decisión #2 de Miguel).
--
-- UNA definición de llamada/contacto/tasa: `private.gestion_diaria_llamadas(p_ini,
-- p_fin, p_vendedor_ids)` sirve a esta fase (un analista) y a las de supervisor
-- y gerencia (muchos). Llamada = llamada_realizada + llamada_no_contestada.
-- Contacto = llamada_realizada. Útil = resultado ∉ (numero_errado,
-- no_es_la_persona); el histórico sin resultado cuenta como útil. Tasa =
-- contactos / útiles. Cita agendada = tarea `reunion` creada en la ventana por el
-- analista (misma definición que metricas_agenda_fn, 20260727032429).
--
-- POR QUÉ `SECURITY INVOKER` (como F1 y el historial por lead): todo es lectura
-- de filas que la RLS ya acota al actor (leads_select, tareas_select y
-- actividades_select co-extensivas por dueño ACTUAL del lead;
-- politica_abandono_select para todo miembro del CRM). Ningún salto
-- privilegiado nuevo. El ciclo del lead se lee de `crm.leads.sla_global_iniciado_en`
-- (coalesce con creado_en): medido en producción el 20/09/2026, coincide con
-- `private.inicio_ciclo_lead()` en 1 983 de 1 983 leads activos, y a diferencia
-- de esa función (DEFINER sin EXECUTE) es legible bajo el invoker.
-- CONTRATO DE ÁMBITO heredado de la RLS: una llamada hecha hoy sobre un lead que
-- luego se reasignó fuera del subárbol deja de verse en el marcador.
--
-- DEUDAS DE F2 QUE ESTA FASE PAGA: la lista blanca de metadata de
-- `private.registro_actividad_core` (F1) se amplía con las claves del resultado
-- de llamada y de su deshacer (deshecho_en, descartado, no_insista…): el registro
-- ya no muestra un resultado deshecho como vigente. Es la MISMA lista que
-- `private.actividades_de_lead_core` (F2). Exige re-sellar el md5 del núcleo en
-- `private.assert_gestion_diaria_registro()` (cuerpo de F1 intacto salvo la huella).
--
-- GATE. `private.assert_gestion_diaria_analista()` (forma y ACL de puerta y
-- núcleos, md5 propios, cola v2 y politica_abandono en su forma, cadena invoker
-- con sus grants, sin contadores crudos) entra al paraguas
-- `private.assert_gestion_diaria()` = _registro (F1) + _resultado (F2) + _analista (F3).
--
-- CENSO ANALÍTICO (trinquete rojo): ninguna función nueva cuenta a crudo
-- (cardinality(array_agg()) siempre). El conjunto rojo se compara antes/después
-- y debe quedar idéntico.
--
-- PREREQUISITOS EN PRODUCCIÓN (medidos el 20/09/2026): F1 (20260919211958) y F2
-- (20260920005000) instaladas y su paraguas en verde; los md5 vivos del preflight.
--
-- REVERSIÓN: supabase/scripts/gestion-diaria-analista/reversa.sql (retira los
-- objetos nuevos, devuelve el núcleo del registro y su gate al cuerpo de F1 y el
-- paraguas al de F2). Sin datos que deshacer: esta migración solo lee.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- Foto del censo analítico ANTES (patrón 20260919170500): el postflight exige
-- el mismo conjunto y el mismo conjunto rojo.
create temporary table gd_analista_preflight on commit drop as
select (select coalesce(string_agg(objeto, ',' order by objeto), '') from private.contadores_crudos_leads_citas()) as censo,
       (select coalesce(string_agg(objeto, ',' order by objeto), '') from private.contadores_crudos_leads_citas()
         where not (declarada and huella_ok)) as censo_rojo;

do $preflight$
declare
  v_firma text;
  v_md5 text;
begin
  -- Nada de F3 instalado todavía.
  if to_regprocedure('crm.gestion_diaria_analista_fn(date,uuid)') is not null
     or to_regprocedure('private.gestion_diaria_analista_core(uuid,date,timestamptz,timestamptz,timestamptz,timestamptz)') is not null
     or to_regprocedure('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])') is not null
     or to_regprocedure('private.gestion_diaria_umbrales()') is not null
     or to_regprocedure('private.assert_gestion_diaria_analista()') is not null
     or to_regprocedure('private.assert_gestion_diaria_analista_mutantes()') is not null then
    raise exception 'PREFLIGHT: el dia del analista de Gestion Diaria ya esta instalado (total o parcialmente)';
  end if;
  -- F1 y F2 instaladas y en verde.
  if to_regprocedure('private.assert_gestion_diaria()') is null
     or to_regprocedure('private.assert_gestion_diaria_registro()') is null
     or to_regprocedure('private.assert_gestion_diaria_resultado()') is null
     or to_regprocedure('crm.registro_actividad_fn(date,date,uuid[],text[],text,integer,timestamptz,uuid)') is null
     or to_regprocedure('crm.registrar_llamada_v3(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)') is null
     or to_regprocedure('crm.deshacer_resultado_llamada(uuid)') is null
     or private.assert_gestion_diaria() not like 'OK%' then
    raise exception 'PREFLIGHT: faltan la Fase 1 (20260919211958) o la Fase 2 (20260920005000) de Gestion Diaria, o su paraguas no esta en verde';
  end if;
  -- Lo que esta fase toca o de lo que depende, EXACTAMENTE como vive en producción (md5 medidos el 20/09/2026).
  for v_firma, v_md5 in select * from (values
    ('private.registro_actividad_core(timestamptz,timestamptz,uuid[],text[],text,integer,timestamptz,uuid)', 'd1c922eb5081e30f3581b95a95d74656'),
    ('private.assert_gestion_diaria_registro()',                                                              'd2ab883a409638299c135d4bee043575'),
    ('private.assert_gestion_diaria()',                                                                       '32148d3276427fb6004201323e4b9a1f'),
    ('crm.cola_accion_v2_fn(integer,text,text,uuid,jsonb)',                                                   'ef9b56eddeaad5c4297ac0e20777799c')
  ) as m(firma, md5) loop
    if to_regprocedure(v_firma) is null
       or md5(pg_get_functiondef(to_regprocedure(v_firma))) is distinct from v_md5 then
      raise exception 'PREFLIGHT: % no es el texto vivo de produccion del 20/09/2026 (md5 %)',
        v_firma, coalesce(md5(pg_get_functiondef(to_regprocedure(v_firma))), 'ausente');
    end if;
  end loop;
  -- La perilla del abandono (lead libre F1, 20260816221500): fila única, legible por todo miembro del CRM.
  if to_regclass('crm.politica_abandono') is null
     or not exists (select 1 from crm.politica_abandono where singleton)
     or not (select relrowsecurity from pg_class where oid = 'crm.politica_abandono'::regclass)
     or not exists (select 1 from pg_policy where polrelid = 'crm.politica_abandono'::regclass and polname = 'politica_abandono_select')
     or not has_column_privilege('authenticated', 'crm.politica_abandono', 'dias_abandono', 'SELECT') then
    raise exception 'PREFLIGHT: crm.politica_abandono no esta en su forma (fila unica, RLS, policy de lectura, SELECT de dias_abandono)';
  end if;
  -- La cadena INVOKER: lo que los núcleos leen tiene que ser legible por authenticated.
  if not has_function_privilege('authenticated', 'private.puede_acceder_crm()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'private.rol_crm(uuid)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.equipo_visible_fn()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.cola_accion_v2_fn(integer,text,text,uuid,jsonb)', 'EXECUTE')
     or not has_schema_privilege('authenticated', 'private', 'USAGE')
     or not has_table_privilege('authenticated', 'crm.actividades', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'id', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'nombre_completo', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'etapa', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'vendedor_id', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'activo', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'creado_en', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'tenencia_desde', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'sla_global_iniciado_en', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'descartado_en', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.tareas', 'id', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.tareas', 'lead_id', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.tareas', 'vendedor_id', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.tareas', 'tipo', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.tareas', 'titulo', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.tareas', 'vence_en', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.tareas', 'estado', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.tareas', 'activo', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.tareas', 'creado_en', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.tareas', 'modalidad_reunion', 'SELECT')
     or not (select relrowsecurity from pg_class where oid = 'crm.tareas'::regclass)
     or not exists (select 1 from pg_policy where polrelid = 'crm.tareas'::regclass and polname = 'tareas_select') then
    raise exception 'PREFLIGHT: la cadena invoker no tiene los permisos esperados (leads, tareas, politica_abandono, ayudantes)';
  end if;
  -- Todo lead abierto con dueño tiene tenencia_desde (medido en producción el 20/09: 0 sin ella).
  if exists (select 1 from crm.leads l where l.activo and l.vendedor_id is not null
              and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada') and l.tenencia_desde is null) then
    raise exception 'PREFLIGHT: hay leads abiertos con dueño y sin tenencia_desde: revisar antes de estrenar el abandono';
  end if;
  perform private.assert_sla_nucleo(); perform private.assert_sla_operacion();
  perform private.assert_sla_comandos(); perform private.assert_sla_avisos();
end;
$preflight$;

-- ── CAPA 2 · NÚCLEO ─────────────────────────────────────────────────────────
-- Los umbrales de la tasa de contacto, en UN solo sitio (aprobados por Miguel
-- el 19/09/2026 tras contrastarlos con 14 días reales: 8 Bien / 6 Atención / 2 Bajo).
-- Las fases 4 y 5 añaden aquí sus perillas (sin llamadas desde las 11:00, parado
-- 2 h, tasa 15 pp bajo el equipo) re-sellando el md5 en su gate.
create function private.gestion_diaria_umbrales() returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
  select jsonb_build_object(
    'version', 1,
    'bien_min_pct', 45,
    'atencion_min_pct', 25,
    'minimo_llamadas_utiles', 5
  );
$function$;
comment on function private.gestion_diaria_umbrales() is
  'NÚCLEO (Gestión Diaria): umbrales de la tasa de contacto, fuente única. Bien ≥ 45 %, Atención 25–44 %, Bajo < 25 %; chip y alerta solo con ≥ 5 llamadas útiles (decisión #7 de Miguel, 19/09/2026).';
revoke all on function private.gestion_diaria_umbrales() from public, anon, authenticated, service_role;
grant execute on function private.gestion_diaria_umbrales() to authenticated;

-- UNA definición de llamada / contacto / útil / tasa, por analista y ventana.
-- Lo llaman puertas INVOKER: corre como el actor, bajo actividades_select y
-- tareas_select. Sin contadores crudos: cardinality(array_agg()).
create function private.gestion_diaria_llamadas(
  p_ini timestamptz,
  p_fin timestamptz,
  p_vendedor_ids uuid[]
) returns table (
  vendedor_id uuid,
  llamadas integer,
  contestadas integer,
  utiles integer,
  leads_tocados integer,
  citas_agendadas integer,
  primera_llamada_en timestamptz,
  ultima_llamada_en timestamptz,
  por_resultado jsonb,
  por_hora jsonb
)
language sql
stable
security invoker
set search_path to ''
as $function$
  with vendedores as (
    select distinct v.id from unnest(p_vendedor_ids) as v(id)
  ),
  ll as (
    select a.creado_por as vendedor_id, a.id, a.lead_id, a.tipo, a.creado_en,
           coalesce(a.metadata->>'resultado', 'sin_resultado') as resultado,
           (coalesce(a.metadata->>'resultado', '') not in ('numero_errado', 'no_es_la_persona')) as util,
           extract(hour from (a.creado_en at time zone 'America/Lima'))::integer as hora
    from crm.actividades a
    where a.creado_por in (select v.id from vendedores v)
      and a.tipo in ('llamada_realizada', 'llamada_no_contestada')
      and a.creado_en >= p_ini
      and a.creado_en <  p_fin
  ),
  agg as (
    select l.vendedor_id,
           cardinality(array_agg(l.id)) as llamadas,
           coalesce(cardinality(array_agg(l.id) filter (where l.tipo = 'llamada_realizada')), 0) as contestadas,
           coalesce(cardinality(array_agg(l.id) filter (where l.util)), 0) as utiles,
           cardinality(array_agg(distinct l.lead_id)) as leads_tocados,
           min(l.creado_en) as primera_llamada_en,
           max(l.creado_en) as ultima_llamada_en
    from ll l
    group by l.vendedor_id
  ),
  por_resultado as (
    select r.vendedor_id, jsonb_object_agg(r.resultado, r.n) as por_resultado
    from (
      select l.vendedor_id, l.resultado, cardinality(array_agg(l.id)) as n
      from ll l
      group by l.vendedor_id, l.resultado
    ) r
    group by r.vendedor_id
  ),
  por_hora as (
    select h.vendedor_id,
           jsonb_agg(jsonb_build_object('hora', h.hora, 'llamadas', h.n, 'contestadas', h.c) order by h.hora) as por_hora
    from (
      select l.vendedor_id, l.hora, cardinality(array_agg(l.id)) as n,
             coalesce(cardinality(array_agg(l.id) filter (where l.tipo = 'llamada_realizada')), 0) as c
      from ll l
      group by l.vendedor_id, l.hora
    ) h
    group by h.vendedor_id
  ),
  citas as (
    -- Cita agendada = tarea de cita CREADA en la ventana por el analista (la
    -- misma definición que metricas_agenda_fn). Las reprogramadas crean otra
    -- tarea y cuentan igual que allí.
    select t.vendedor_id, cardinality(array_agg(t.id)) as citas_agendadas
    from crm.tareas t
    where t.vendedor_id in (select v.id from vendedores v)
      and t.tipo = 'reunion'
      and t.creado_en >= p_ini
      and t.creado_en <  p_fin
    group by t.vendedor_id
  )
  select v.id,
         coalesce(a.llamadas, 0),
         coalesce(a.contestadas, 0),
         coalesce(a.utiles, 0),
         coalesce(a.leads_tocados, 0),
         coalesce(c.citas_agendadas, 0),
         a.primera_llamada_en,
         a.ultima_llamada_en,
         coalesce(r.por_resultado, '{}'::jsonb),
         coalesce(h.por_hora, '[]'::jsonb)
  from vendedores v
  left join agg a on a.vendedor_id = v.id
  left join por_resultado r on r.vendedor_id = v.id
  left join por_hora h on h.vendedor_id = v.id
  left join citas c on c.vendedor_id = v.id
  order by v.id;
$function$;
comment on function private.gestion_diaria_llamadas(timestamptz, timestamptz, uuid[]) is
  'NÚCLEO (Gestión Diaria): la definición única de llamada (realizada + no contestada), contacto (realizada), útil (resultado ∉ numero_errado/no_es_la_persona; sin resultado cuenta como útil), leads tocados, citas agendadas (tarea reunion creada en la ventana), primera/última llamada, desglose por resultado y por hora Lima, por analista y ventana [p_ini, p_fin). Bajo la RLS del actor; sin contadores crudos.';
revoke all on function private.gestion_diaria_llamadas(timestamptz, timestamptz, uuid[]) from public, anon, authenticated, service_role;
grant execute on function private.gestion_diaria_llamadas(timestamptz, timestamptz, uuid[]) to authenticated;

-- El día de UN analista. Puro: sin auth ni autoridad propia (la puerta decide
-- quién puede pedir a quién). Ventana del marcador [p_ini, p_fin); compromisos y
-- cartera se leen a la fecha de la consulta (no hay historia de tareas).
create function private.gestion_diaria_analista_core(
  p_analista uuid,
  p_dia date,
  p_ini timestamptz,
  p_fin timestamptz,
  p_desde_compromisos timestamptz,
  p_ahora timestamptz
) returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
  with politica as (
    select coalesce((select pa.dias_abandono from crm.politica_abandono pa where pa.singleton), 7) as dias
  ),
  umbrales as (
    select private.gestion_diaria_umbrales() as u
  ),
  marcador as (
    select m.*, u.u
    from private.gestion_diaria_llamadas(p_ini, p_fin, array[p_analista]) m
    cross join umbrales u
  ),
  compromisos as (
    -- Tareas pendientes de llamada o cita a partir de mañana (las de hoy y las
    -- vencidas ya viven en la cola), sobre leads que ya conversaron. Se incluye
    -- «cita agendada»: una cita pendiente es el compromiso más fuerte y su lead
    -- vive en esa etapa por el sincronizador de tareas.
    select t.id as tarea_id, t.lead_id, l.nombre_completo as lead_nombre, l.etapa as lead_etapa,
           t.tipo, t.titulo, t.vence_en, t.modalidad_reunion
    from crm.tareas t
    join crm.leads l on l.id = t.lead_id
    where t.vendedor_id = p_analista
      and t.activo
      and t.estado = 'pendiente'
      and t.tipo in ('llamada', 'reunion')
      and t.vence_en >= p_desde_compromisos
      and l.activo
      and l.etapa in ('contactado', 'reunion_agendada', 'propuesta_enviada')
  ),
  cartera_base as (
    -- Los leads ABIERTOS del analista con sus hechos de contacto. El ciclo se
    -- lee de sla_global_iniciado_en (= private.inicio_ciclo_lead, medido en
    -- producción el 20/09/2026). La referencia del abandono es la de la
    -- política: greatest(última conversación real, tenencia_desde).
    select l.id, l.nombre_completo, l.etapa, l.tenencia_desde,
           coalesce(l.sla_global_iniciado_en, l.creado_en) as ciclo_desde,
           s.llamadas_ciclo, s.ultima_llamada_en, s.ultima_conversacion_en,
           greatest(coalesce(s.ultima_conversacion_en, '-infinity'::timestamptz),
                    coalesce(l.tenencia_desde, l.creado_en)) as referencia
    from crm.leads l
    cross join lateral (
      select
        coalesce(cardinality(array_agg(a.id) filter (
          where a.tipo in ('llamada_realizada', 'llamada_no_contestada')
            and a.creado_en >= coalesce(l.sla_global_iniciado_en, l.creado_en))), 0) as llamadas_ciclo,
        max(a.creado_en) filter (where a.tipo in ('llamada_realizada', 'llamada_no_contestada')) as ultima_llamada_en,
        max(a.creado_en) filter (where a.tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada')) as ultima_conversacion_en
      from crm.actividades a
      where a.lead_id = l.id
    ) s
    where l.activo
      and l.vendedor_id = p_analista
      and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
    order by referencia, id
    limit 501
  ),
  cartera as (
    select cb.*,
           -- Intentos sin respuesta POSTERIORES a la última conversación (la
           -- misma evidencia que exige «no responde» en F2; un número errado no
           -- es un intento sin respuesta).
           (select coalesce(cardinality(array_agg(a.id)), 0)
              from crm.actividades a
             where a.lead_id = cb.id
               and a.tipo in ('llamada_no_contestada', 'whatsapp_enviado')
               and coalesce(a.metadata->>'resultado', '') not in ('numero_errado', 'no_es_la_persona')
               and a.creado_en > coalesce(cb.ultima_conversacion_en, '-infinity'::timestamptz)) as intentos_sin_respuesta,
           u.ultima_llamada_tipo,
           u.ultima_llamada_resultado,
           ne.detalle as numero_errado_detalle,
           ne.creado_en as numero_errado_en,
           pt.vence_en as proxima_tarea_en,
           pt.tipo as proxima_tarea_tipo,
           (cb.referencia < p_ahora - make_interval(days => (select p.dias from politica p))) as sin_conversacion,
           -- Nunca negativo: una conversación sellada con clock_timestamp() puede ser
           -- unos milisegundos posterior al now() de esta consulta.
           greatest(floor(extract(epoch from (p_ahora - cb.referencia)) / 86400), 0)::integer as dias_sin_conversacion
    from cartera_base cb
    left join lateral (
      select a.tipo as ultima_llamada_tipo, a.metadata->>'resultado' as ultima_llamada_resultado
      from crm.actividades a
      where a.lead_id = cb.id and a.tipo in ('llamada_realizada', 'llamada_no_contestada')
      order by a.creado_en desc, a.id desc
      limit 1
    ) u on true
    left join lateral (
      select a.detalle, a.creado_en
      from crm.actividades a
      where a.lead_id = cb.id
        and a.metadata->>'resultado' in ('numero_errado', 'no_es_la_persona')
        and a.creado_en >= cb.ciclo_desde
      order by a.creado_en desc, a.id desc
      limit 1
    ) ne on true
    left join lateral (
      select t.vence_en, t.tipo
      from crm.tareas t
      where t.lead_id = cb.id and t.activo and t.estado = 'pendiente'
      order by t.vence_en, t.id
      limit 1
    ) pt on true
  ),
  descartados as (
    -- Descartes del día firmados por el analista (F2): para ofrecer «Deshacer»
    -- hasta 24 h. `vigente` = el descarte del lead sigue siendo ESTE (mismo
    -- sello descartado_en), el criterio que aplica crm.deshacer_resultado_llamada.
    select a.id as actividad_id, a.lead_id, l.nombre_completo as lead_nombre, l.etapa as lead_etapa,
           a.metadata->>'resultado' as resultado,
           a.metadata->>'submotivo' as submotivo,
           a.metadata->>'motivo_descarte' as motivo_descarte,
           a.creado_en,
           (a.metadata ? 'deshecho_en') as deshecho,
           coalesce((a.metadata->>'no_insista')::boolean, false) as no_insista,
           (l.etapa = 'descartado' and l.descartado_en is not null
              and l.descartado_en = nullif(a.metadata->>'descartado_en', '')::timestamptz) as vigente
    from crm.actividades a
    join crm.leads l on l.id = a.lead_id
    where a.creado_por = p_analista
      and a.metadata->>'evento' = 'resultado_llamada'
      and coalesce((a.metadata->>'descartado')::boolean, false)
      and a.creado_en >= p_ini
      and a.creado_en <  p_fin
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', p_ahora,
    'dia', p_dia,
    'zona', 'America/Lima',
    'analista_id', p_analista,
    'umbrales', (select u.u from umbrales u),
    'sin_conversacion_dias', (select p.dias from politica p),
    'marcador', (
      select jsonb_build_object(
        'llamadas', m.llamadas,
        'contestadas', m.contestadas,
        'utiles', m.utiles,
        'tasa_contacto_pct', case when m.utiles > 0 then round(100.0 * m.contestadas / m.utiles) end,
        'nivel', case
          when m.utiles > 0 and m.utiles >= (m.u->>'minimo_llamadas_utiles')::integer then
            case when round(100.0 * m.contestadas / m.utiles) >= (m.u->>'bien_min_pct')::numeric then 'bien'
                 when round(100.0 * m.contestadas / m.utiles) >= (m.u->>'atencion_min_pct')::numeric then 'atencion'
                 else 'bajo' end
        end,
        'leads_tocados', m.leads_tocados,
        'citas_agendadas', m.citas_agendadas,
        'primera_llamada_en', m.primera_llamada_en,
        'ultima_llamada_en', m.ultima_llamada_en,
        'por_resultado', m.por_resultado,
        'por_hora', m.por_hora)
      from marcador m),
    'compromisos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'tarea_id', c.tarea_id, 'lead_id', c.lead_id, 'lead_nombre', c.lead_nombre, 'lead_etapa', c.lead_etapa,
        'tipo', c.tipo, 'titulo', c.titulo, 'vence_en', c.vence_en, 'modalidad_reunion', c.modalidad_reunion)
        order by c.vence_en, c.tarea_id)
      from (select * from compromisos co order by co.vence_en, co.tarea_id limit 100) c), '[]'::jsonb),
    'compromisos_total', (select coalesce(cardinality(array_agg(c.tarea_id)), 0) from compromisos c),
    'cartera', coalesce((
      select jsonb_agg(jsonb_build_object(
        'lead_id', c.id, 'nombre_completo', c.nombre_completo, 'etapa', c.etapa,
        'tenencia_desde', c.tenencia_desde, 'ciclo_desde', c.ciclo_desde,
        'llamadas_ciclo', c.llamadas_ciclo, 'intentos_sin_respuesta', c.intentos_sin_respuesta,
        'ultima_llamada_en', c.ultima_llamada_en, 'ultima_llamada_tipo', c.ultima_llamada_tipo,
        'ultima_llamada_resultado', c.ultima_llamada_resultado,
        'ultima_conversacion_en', c.ultima_conversacion_en,
        'dias_sin_conversacion', c.dias_sin_conversacion, 'sin_conversacion', c.sin_conversacion,
        'numero_errado_detalle', c.numero_errado_detalle, 'numero_errado_en', c.numero_errado_en,
        'proxima_tarea_en', c.proxima_tarea_en, 'proxima_tarea_tipo', c.proxima_tarea_tipo)
        order by c.referencia, c.id)
      from (select * from cartera ca order by ca.referencia, ca.id limit 500) c), '[]'::jsonb),
    'cartera_truncada', coalesce((select cardinality(array_agg(c.id)) > 500 from cartera c), false),
    'descartados', coalesce((
      select jsonb_agg(jsonb_build_object(
        'actividad_id', d.actividad_id, 'lead_id', d.lead_id, 'lead_nombre', d.lead_nombre, 'lead_etapa', d.lead_etapa,
        'resultado', d.resultado, 'submotivo', d.submotivo, 'motivo_descarte', d.motivo_descarte,
        'creado_en', d.creado_en, 'deshecho', d.deshecho, 'vigente', d.vigente, 'no_insista', d.no_insista,
        'puede_deshacer', (not d.deshecho and d.vigente and not d.no_insista
                           and d.creado_en >= p_ahora - interval '24 hours'))
        order by d.creado_en desc, d.actividad_id)
      from descartados d), '[]'::jsonb)
  );
$function$;
comment on function private.gestion_diaria_analista_core(uuid, date, timestamptz, timestamptz, timestamptz, timestamptz) is
  'NÚCLEO (Gestión Diaria F3): el día de un analista bajo la RLS del actor — marcador de la ventana (por gestion_diaria_llamadas + umbrales), compromisos (tareas pendientes de llamada/cita desde p_desde_compromisos sobre leads que ya conversaron; hasta 100 + total), cartera (señales por lead abierto, hasta 500, con sin_conversacion según crm.politica_abandono) y descartados del día con puede_deshacer. Puro: sin auth ni autoridad propia; sin contadores crudos.';
revoke all on function private.gestion_diaria_analista_core(uuid, date, timestamptz, timestamptz, timestamptz, timestamptz) from public, anon, authenticated, service_role;
grant execute on function private.gestion_diaria_analista_core(uuid, date, timestamptz, timestamptz, timestamptz, timestamptz) to authenticated;

-- ── CAPA 3 · PUERTA ─────────────────────────────────────────────────────────
create function crm.gestion_diaria_analista_fn(
  p_dia date default null,
  p_analista_id uuid default null
) returns jsonb
language plpgsql
stable
security invoker
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_hoy constant date := (now() at time zone 'America/Lima')::date;
  v_dia date := coalesce(p_dia, (now() at time zone 'America/Lima')::date);
  v_analista uuid := coalesce(p_analista_id, (select auth.uid()));
  v_ini timestamptz;
  v_fin timestamptz;
  v_manana timestamptz;
begin
  -- EL INPUT SE VALIDA ANTES DE LEER NADA (22023, mensajes en lenguaje llano).
  if v_dia > v_hoy then
    raise exception 'El dia no admite fechas futuras' using errcode = '22023';
  end if;
  if v_hoy - v_dia > 365 then
    raise exception 'El dia no puede ser anterior a un ano' using errcode = '22023';
  end if;

  -- Guardia de ADMISIÓN (P04: revocado ≠ ajeno al CRM). El ALCANCE lo pone la RLS.
  if v_uid is null or not private.puede_acceder_crm() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  v_rol := private.rol_crm(v_uid);
  -- El coordinador no entra al mundo leads (C1): se le dice que no.
  if v_rol = 'coordinador' then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  -- Un analista solo ve su propio día. Supervisor, gerencia y lector global
  -- pueden pedir el de un analista ACTIVO de su roster visible
  -- (crm.equipo_visible_fn: él mismo, su subárbol o todos). Denegación
  -- EXPLÍCITA (42501), nunca un día vacío que parezca «no llamó».
  if v_analista <> v_uid then
    if v_rol = 'vendedor' then
      raise exception 'Solo puedes ver tu propio dia' using errcode = '42501';
    end if;
    if not exists (select 1 from crm.equipo_visible_fn() ev where ev.perfil_id = v_analista) then
      raise exception 'Solo puedes ver el dia de analistas activos de tu equipo' using errcode = '42501';
    end if;
  end if;

  -- Ventana semiabierta en Lima del día pedido; los compromisos, desde mañana (real).
  v_ini := (v_dia::timestamp) at time zone 'America/Lima';
  v_fin := ((v_dia + 1)::timestamp) at time zone 'America/Lima';
  v_manana := ((v_hoy + 1)::timestamp) at time zone 'America/Lima';

  return private.gestion_diaria_analista_core(v_analista, v_dia, v_ini, v_fin, v_manana, now());
end;
$function$;
comment on function crm.gestion_diaria_analista_fn(date, uuid) is
  'PUERTA (Gestión Diaria F3): el día de un analista — marcador (llamadas, contestadas, útiles, tasa con nivel, leads tocados, citas agendadas, por resultado y por hora Lima), compromisos desde mañana, señales por lead abierto (incluido sin_conversacion según crm.politica_abandono) y descartados del día con puede_deshacer. p_dia = hoy Lima por defecto (≤ hoy, ≤ 1 año atrás); p_analista_id = el actor por defecto; un analista solo el suyo, supervisor/gerencia uno de su roster visible (42501 explícito). SECURITY INVOKER: el alcance lo pone la RLS. Sin contadores crudos.';
revoke all on function crm.gestion_diaria_analista_fn(date, uuid) from public, anon, authenticated, service_role;
grant execute on function crm.gestion_diaria_analista_fn(date, uuid) to authenticated;

-- ── Registro de F1: la lista blanca de metadata se amplía (deuda de F2) ──────
-- Cuerpo IDÉNTICO al de 20260919211958 salvo la lista blanca, que pasa a ser la
-- MISMA que la del historial por lead (F2): así un resultado deshecho ya no se
-- muestra como vigente en el registro. Forma, volatilidad, search_path y ACL se
-- conservan (create or replace).
create or replace function private.registro_actividad_core(
  p_ini timestamptz,
  p_fin timestamptz,
  p_analista_ids uuid[],
  p_tipos text[],
  p_etapa text,
  p_limite integer,
  p_antes_de timestamptz,
  p_antes_id uuid
) returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
  with pagina as (
    select a.id, a.lead_id, a.tipo, a.detalle, a.metadata, a.creado_por, a.creado_en,
           l.nombre_completo as lead_nombre, l.etapa as lead_etapa,
           -- La etapa del lead ANTES de esta actividad: el último cambio de etapa
           -- anterior. OJO con el reloj de los escritores (refutación del 19/09):
           -- las gestiones manuales llevan `clock_timestamp()` (sello de
           -- 20260820174320) pero los `cambio_etapa` automáticos nacen con el
           -- `now()` de la transacción, es decir unos milisegundos ANTES de la
           -- llamada que los causó. Por eso el cambio se considera «ya ocurrido»
           -- solo si es anterior en más de un segundo: así la llamada que subió
           -- el lead a «contactado» se ve todavía en «nuevo», y la conversión
           -- (misma transacción que su cambio) se ve en la etapa previa.
           (select c.metadata->>'etapa_nueva'
              from crm.actividades c
             where c.lead_id = a.lead_id
               and c.tipo = 'cambio_etapa'
               and c.creado_en < a.creado_en - interval '1 second'
             order by c.creado_en desc, c.id desc
             limit 1) as etapa_en_ese_momento
    from crm.actividades a
    join crm.leads l on l.id = a.lead_id
    where a.creado_en >= p_ini
      and a.creado_en <  p_fin
      and (p_analista_ids is null or a.creado_por = any (p_analista_ids))
      and (p_tipos is null or a.tipo = any (p_tipos))
      and (p_etapa is null or l.etapa = p_etapa)
      and (
        p_antes_de is null
        or a.creado_en < p_antes_de
        or (a.creado_en = p_antes_de and a.id > p_antes_id)
      )
    order by a.creado_en desc, a.id asc
    limit p_limite
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', pg_catalog.now(),
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', pg.id,
          'lead_id', pg.lead_id,
          'lead_nombre', pg.lead_nombre,
          'lead_etapa', pg.lead_etapa,
          'etapa_en_ese_momento', pg.etapa_en_ese_momento,
          'tipo', pg.tipo,
          'detalle', pg.detalle,
          -- metadata por LISTA BLANCA: solo lo que la pantalla necesita. Fuera
          -- quedan montos y referencias de conversión, uuids de reasignación y
          -- cualquier clave futura que no se haya decidido mostrar (auditor-rls, 19/09).
          -- Desde Gestión Diaria F3 incluye las claves del resultado de llamada
          -- y de su deshacer (la misma lista que el historial por lead, F2).
          'metadata', coalesce((
            select jsonb_object_agg(m.clave, m.valor)
            from jsonb_each(pg.metadata) as m(clave, valor)
            where m.clave in (
              'evento', 'resultado', 'submotivo', 'intento_n', 'etapa_anterior', 'etapa_nueva',
              'automatico', 'resultado_reunion', 'modalidad', 'motivo',
              'descartado', 'no_insista', 'deshecho_en', 'siguiente_id', 'tarea_id',
              'motivo_descarte', 'etapa_al_descartar', 'actividad_id',
              'tarea_cancelada', 'descarte_revertido', 'cita_no_restaurada')
          ), '{}'::jsonb),
          'creado_por', pg.creado_por,
          'autor_nombre', coalesce(private.nombre_de_autor(pg.creado_por), '—'),
          'creado_en', pg.creado_en
        )
        order by pg.creado_en desc, pg.id asc
      )
      from pagina pg
    ), '[]'::jsonb)
  );
$function$;
comment on function private.registro_actividad_core(timestamptz, timestamptz, uuid[], text[], text, integer, timestamptz, uuid) is
  'NÚCLEO (Gestión Diaria): página keyset (creado_en desc, id asc) de actividades de una ventana [p_ini, p_fin) bajo la RLS del actor, filtrada por autores, tipos y etapa actual del lead, con la etapa del lead en ese momento (último cambio_etapa anterior) y metadata acotada a una lista blanca de claves (desde F3, con las del resultado de llamada y su deshacer). Puro: sin auth ni autoridad propia; sin contadores crudos.';

-- El gate de F1, con la huella nueva del núcleo (cuerpo intacto salvo esa línea).
create or replace function private.assert_gestion_diaria_registro() returns text
language plpgsql stable security definer set search_path = '' as $function$
declare
  v_firma text;
  v_id oid;
begin
  foreach v_firma in array array[
    'crm.registro_actividad_fn(date,date,uuid[],text[],text,integer,timestamptz,uuid)',
    'private.registro_actividad_core(timestamptz,timestamptz,uuid[],text[],text,integer,timestamptz,uuid)'
  ] loop
    v_id := to_regprocedure(v_firma);
    if v_id is null or not exists (
      select 1 from pg_proc p
      where p.oid = v_id and not p.prosecdef
        and p.proowner = 'postgres'::regrole::oid
        and p.provolatile = 's'
        and p.proconfig @> array['search_path=""']
    ) then
      raise exception 'Contrato de Gestion Diaria alterado (debe ser INVOKER, stable, search_path vacio): %', v_firma;
    end if;
    if not has_function_privilege('authenticated', v_id, 'EXECUTE')
       or exists (
         select 1 from pg_proc p
         cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         where p.oid = v_id
           and a.grantee not in ('postgres'::regrole::oid, 'authenticated'::regrole::oid)
       ) then
      raise exception 'ACL de Gestion Diaria alterada: %', v_firma;
    end if;
  end loop;

  if not exists (select 1 from pg_indexes where schemaname = 'crm' and tablename = 'actividades'
                 and indexname = 'actividades_autor_fecha_idx') then
    raise exception 'Falta el indice actividades_autor_fecha_idx';
  end if;

  -- El CUERPO del núcleo, sellado: la lista blanca de metadata, la ventana y el
  -- keyset viven ahí y un `create or replace` conservaría forma, ACL y
  -- search_path. Huella medida en el banco el 20/09/2026 (Gestión Diaria F3:
  -- lista blanca ampliada con el resultado de llamada y su deshacer).
  if md5(pg_get_functiondef('private.registro_actividad_core(timestamptz,timestamptz,uuid[],text[],text,integer,timestamptz,uuid)'::regprocedure))
     is distinct from '3430460e4ab59aa185ec8305788cc9a4' then
    raise exception 'El cuerpo de private.registro_actividad_core cambio: re-sellar Gestion Diaria';
  end if;

  -- El único salto privilegiado sigue en su forma (DEFINER con gate interno).
  v_id := to_regprocedure('private.nombre_de_autor(uuid)');
  if v_id is null or not exists (
    select 1 from pg_proc p
    where p.oid = v_id and p.prosecdef and p.proowner = 'postgres'::regrole::oid
      and p.provolatile = 's' and p.proconfig @> array['search_path=""']
      and strpos(p.prosrc, 'puede_acceder_crm') > 0
  ) or not has_function_privilege('authenticated', v_id, 'EXECUTE') then
    raise exception 'private.nombre_de_autor(uuid) perdio su forma o su EXECUTE';
  end if;

  -- Las dos policies co-extensivas (huella, conjunto de permisivas, roles de la
  -- policy, restrictiva del actor activo, grants de la cadena invoker): UNA sola
  -- fuente, la base del historial por lead (20260919185718). Dos gates con las
  -- mismas constantes copiadas podrían divergir; llamándola no pueden.
  perform private.assert_actividades_de_lead_base();

  return 'OK: registro de Gestion Diaria bajo la RLS (puerta y nucleo INVOKER), EXECUTE solo authenticated, indice presente, policies selladas por la base del historial por lead';
end;
$function$;
comment on function private.assert_gestion_diaria_registro() is
  'Trinquete de Gestión Diaria · Fase 1 (registro): puerta y núcleo INVOKER con search_path vacío, EXECUTE solo para authenticated, índice actividades_autor_fecha_idx presente, nombre_de_autor en su forma, y las policies actividades_select/leads_select selladas vía private.assert_actividades_de_lead_base(). Huella del núcleo re-sellada en F3 (lista blanca ampliada). La llama private.assert_gestion_diaria().';

-- ── Gate de F3 ──────────────────────────────────────────────────────────────
create function private.assert_gestion_diaria_analista() returns text
language plpgsql stable security definer set search_path = '' as $function$
declare
  v_firma text;
  v_md5 text;
  v_id oid;
begin
  -- 1. Puerta y núcleos: INVOKER, estables, search_path vacío, owner postgres,
  --    EXECUTE exactamente para authenticated (la cadena corre como el actor).
  foreach v_firma in array array[
    'crm.gestion_diaria_analista_fn(date,uuid)',
    'private.gestion_diaria_analista_core(uuid,date,timestamptz,timestamptz,timestamptz,timestamptz)',
    'private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])',
    'private.gestion_diaria_umbrales()'
  ] loop
    v_id := to_regprocedure(v_firma);
    if v_id is null or not exists (
      select 1 from pg_proc p
      where p.oid = v_id and not p.prosecdef
        and p.proowner = 'postgres'::regrole::oid
        and p.provolatile = 's'
        and p.proconfig @> array['search_path=""']
    ) then
      raise exception 'Contrato del dia del analista alterado (debe ser INVOKER, stable, search_path vacio): %', v_firma;
    end if;
    if not has_function_privilege('authenticated', v_id, 'EXECUTE')
       or exists (
         select 1 from pg_proc p
         cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         where p.oid = v_id
           and a.grantee not in ('postgres'::regrole::oid, 'authenticated'::regrole::oid)
       ) then
      raise exception 'ACL del dia del analista alterada: %', v_firma;
    end if;
    -- Ningún contador crudo en los cuerpos propios (trinquete del censo analítico).
    if exists (select 1 from pg_proc p where p.oid = v_id
               and (lower(p.prosrc) ~ '\mcount\s*\(' or lower(p.prosrc) ~ '\msum\s*\(\s*1\s*\)')) then
      raise exception 'Una funcion del dia del analista cuenta a crudo: %', v_firma;
    end if;
  end loop;

  -- 2. Los CUERPOS propios, sellados (medidos en el banco, dos pasadas).
  for v_firma, v_md5 in select * from (values
    ('crm.gestion_diaria_analista_fn(date,uuid)',                                                          'b93970c865a6abc318a6372b8535c0e2'),
    ('private.gestion_diaria_analista_core(uuid,date,timestamptz,timestamptz,timestamptz,timestamptz)',    'df3712f027acfc8cbc95c7d08a2db5b5'),
    ('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])',                                    '431e9fd8198adcb1cd7416cd0f15acaa'),
    ('private.gestion_diaria_umbrales()',                                                                   '6ab633af9f5356f3fa11cf309ff4b25c')
  ) as m(firma, md5) loop
    if to_regprocedure(v_firma) is null
       or md5(pg_get_functiondef(to_regprocedure(v_firma))) is distinct from v_md5 then
      raise exception 'El cuerpo de % cambio: re-sellar el dia del analista de Gestion Diaria (md5 %)',
        v_firma, coalesce(md5(pg_get_functiondef(to_regprocedure(v_firma))), 'ausente');
    end if;
  end loop;

  -- 3. La cola de la que bebe la pantalla, en su forma: DEFINER, estable,
  --    search_path vacío, ejecutable por authenticated. (Su cuerpo no se sella
  --    aquí: pertenece al mundo SLA; el front valida el contrato de la página.)
  v_id := to_regprocedure('crm.cola_accion_v2_fn(integer,text,text,uuid,jsonb)');
  if v_id is null or not exists (
    select 1 from pg_proc p
    where p.oid = v_id and p.prosecdef and p.proowner = 'postgres'::regrole::oid
      and p.provolatile = 's' and p.proconfig @> array['search_path=""']
  ) or not has_function_privilege('authenticated', v_id, 'EXECUTE') then
    raise exception 'crm.cola_accion_v2_fn perdio su forma o su EXECUTE';
  end if;

  -- 4. La perilla del abandono: fila única bajo RLS, legible por el actor.
  if to_regclass('crm.politica_abandono') is null
     or not (select relrowsecurity from pg_class where oid = 'crm.politica_abandono'::regclass)
     or not exists (select 1 from pg_policy where polrelid = 'crm.politica_abandono'::regclass
                    and polname = 'politica_abandono_select' and polcmd = 'r')
     or not has_column_privilege('authenticated', 'crm.politica_abandono', 'dias_abandono', 'SELECT') then
    raise exception 'crm.politica_abandono perdio su forma (RLS, policy de lectura o SELECT de dias_abandono)';
  end if;

  -- 5. La cadena invoker: tareas bajo RLS con su policy de lectura, y las
  --    columnas de leads que los núcleos leen y que llevan ACL propia.
  if not (select relrowsecurity from pg_class where oid = 'crm.tareas'::regclass)
     or not exists (select 1 from pg_policy where polrelid = 'crm.tareas'::regclass and polname = 'tareas_select' and polcmd = 'r')
     or not has_table_privilege('authenticated', 'crm.tareas', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'tenencia_desde', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'sla_global_iniciado_en', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'descartado_en', 'SELECT')
     or not has_function_privilege('authenticated', 'crm.equipo_visible_fn()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'private.puede_acceder_crm()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'private.rol_crm(uuid)', 'EXECUTE') then
    raise exception 'La cadena invoker del dia del analista perdio un permiso (tareas, leads.tenencia_desde/sla_global_iniciado_en/descartado_en, equipo_visible_fn, ayudantes)';
  end if;

  return 'OK: dia del analista — puerta y nucleos INVOKER (EXECUTE solo authenticated) con su md5, sin contadores crudos, cola v2 y politica_abandono en su forma, cadena invoker con sus permisos';
end;
$function$;
comment on function private.assert_gestion_diaria_analista() is
  'Trinquete de Gestión Diaria · Fase 3 (día del analista): forma y ACL de puerta y núcleos, md5 de los cuerpos propios, sin contadores crudos, crm.cola_accion_v2_fn y crm.politica_abandono en su forma, cadena invoker con sus permisos. La llama private.assert_gestion_diaria().';
revoke all on function private.assert_gestion_diaria_analista() from public, anon, authenticated, service_role;

-- El paraguas crece: F1 + F2 + F3.
create or replace function private.assert_gestion_diaria() returns text
language plpgsql stable security definer set search_path = '' as $function$
declare
  v_registro text;
  v_resultado text;
  v_analista text;
begin
  v_registro := private.assert_gestion_diaria_registro();
  v_resultado := private.assert_gestion_diaria_resultado();
  v_analista := private.assert_gestion_diaria_analista();
  return 'OK: Gestion Diaria [' || v_registro || '] [' || v_resultado || '] [' || v_analista || ']';
end;
$function$;
comment on function private.assert_gestion_diaria() is
  'Paraguas del trinquete de Gestión Diaria: llama a assert_gestion_diaria_registro() (F1), assert_gestion_diaria_resultado() (F2) y assert_gestion_diaria_analista() (F3). Crecerá con cada fase.';
revoke all on function private.assert_gestion_diaria() from public, anon, authenticated, service_role;

-- ── Mutantes del trinquete de F3 (solo banco) ───────────────────────────────
create function private.assert_gestion_diaria_analista_mutantes() returns text
language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_detectados integer := 0;
  v_mutacion text;
  v_nombre text;
begin
  if coalesce(current_setting('gestion_diaria.banco', true), '') <> 'on' then
    raise exception 'Los mutantes solo corren en el banco (set gestion_diaria.banco = on)';
  end if;
  for v_nombre, v_mutacion in select * from (values
    ('1 puerta definer',              'alter function crm.gestion_diaria_analista_fn(date, uuid) security definer'),
    ('2 nucleo llamadas para anon',   'grant execute on function private.gestion_diaria_llamadas(timestamptz, timestamptz, uuid[]) to anon'),
    ('3 puerta sin EXECUTE',          'revoke execute on function crm.gestion_diaria_analista_fn(date, uuid) from authenticated'),
    ('4 puerta volatile',             'alter function crm.gestion_diaria_analista_fn(date, uuid) volatile'),
    ('5 nucleo sin search_path',      'alter function private.gestion_diaria_analista_core(uuid, date, timestamptz, timestamptz, timestamptz, timestamptz) reset search_path'),
    ('6 umbrales reescritos',         $m$create or replace function private.gestion_diaria_umbrales() returns jsonb language sql stable security invoker set search_path to '' as $b$ select jsonb_build_object('version', 1, 'bien_min_pct', 1, 'atencion_min_pct', 0, 'minimo_llamadas_utiles', 0) $b$$m$),
    ('7 nucleo llamadas reescrito',   $m$create or replace function private.gestion_diaria_llamadas(p_ini timestamptz, p_fin timestamptz, p_vendedor_ids uuid[]) returns table (vendedor_id uuid, llamadas integer, contestadas integer, utiles integer, leads_tocados integer, citas_agendadas integer, primera_llamada_en timestamptz, ultima_llamada_en timestamptz, por_resultado jsonb, por_hora jsonb) language sql stable security invoker set search_path to '' as $b$ select null::uuid, 0, 0, 0, 0, 0, null::timestamptz, null::timestamptz, '{}'::jsonb, '[]'::jsonb where false $b$$m$),
    ('8 registro F1 alterado',        'alter function private.registro_actividad_core(timestamptz, timestamptz, uuid[], text[], text, integer, timestamptz, uuid) set lock_timeout = ''3s'''),
    ('9 cola v2 invoker',             'alter function crm.cola_accion_v2_fn(integer, text, text, uuid, jsonb) security invoker'),
    ('10 politica_abandono sin RLS',  'alter table crm.politica_abandono disable row level security'),
    ('11 umbrales sin EXECUTE',       'revoke execute on function private.gestion_diaria_umbrales() from authenticated'),
    ('12 puerta con otra firma',      'drop function crm.gestion_diaria_analista_fn(date, uuid)')
  ) as m(nombre, sql) loop
    begin
      begin
        execute v_mutacion;
      exception when others then
        raise exception 'MUTANTE % NO APLICABLE: %', v_nombre, sqlerrm;
      end;
      perform private.assert_gestion_diaria();
      raise exception 'MUTANTE % NO DETECTADO: paso el gate', v_nombre;
    exception when others then
      if sqlerrm like 'MUTANTE %' then raise; end if;
      v_detectados := v_detectados + 1;
    end;
  end loop;
  return format('OK: %s mutantes detectados por private.assert_gestion_diaria()', v_detectados);
end;
$function$;
comment on function private.assert_gestion_diaria_analista_mutantes() is
  'Mutantes del trinquete de Gestión Diaria F3 (solo banco, exige set gestion_diaria.banco = on): cada mutación vive en una subtransacción que se deshace; falla si el gate no la detecta o si la mutación no aplica.';
revoke all on function private.assert_gestion_diaria_analista_mutantes() from public, anon, authenticated, service_role;

do $postflight$
begin
  perform private.assert_gestion_diaria();
  -- Los cuatro gates del mundo SLA (verdes). Los otros cuatro controles del
  -- servidor están en ROJO por trabajos ajenos: no se llaman; se exige en
  -- cambio que el censo analítico quede IDÉNTICO (ninguna función nueva cuenta).
  perform private.assert_sla_nucleo();
  perform private.assert_sla_operacion();
  perform private.assert_sla_comandos();
  perform private.assert_sla_avisos();
  if (select coalesce(string_agg(objeto, ',' order by objeto), '') from private.contadores_crudos_leads_citas())
       <> (select censo from gd_analista_preflight)
     or (select coalesce(string_agg(objeto, ',' order by objeto), '') from private.contadores_crudos_leads_citas()
          where not (declarada and huella_ok)) <> (select censo_rojo from gd_analista_preflight) then
    raise exception 'POSTFLIGHT: el censo analitico cambio (una funcion nueva cuenta leads o citas)';
  end if;
  if exists (
    select 1 from pg_proc p
    where p.oid in (
      to_regprocedure('crm.gestion_diaria_analista_fn(date,uuid)'),
      to_regprocedure('private.gestion_diaria_analista_core(uuid,date,timestamptz,timestamptz,timestamptz,timestamptz)'),
      to_regprocedure('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])'),
      to_regprocedure('private.gestion_diaria_umbrales()'),
      to_regprocedure('private.registro_actividad_core(timestamptz,timestamptz,uuid[],text[],text,integer,timestamptz,uuid)'))
      and (lower(p.prosrc) ~ '\mcount\s*\(' or lower(p.prosrc) ~ '\msum\s*\(\s*1\s*\)')
  ) then
    raise exception 'POSTFLIGHT: una funcion nueva cuenta a crudo';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
$mig_gd_analista$;

  -- 1) PIN: lo que la migración hizo ES verdad — puerta y núcleos con la
  --    definición ensayada, el núcleo del registro re-sellado y el paraguas OK.
  if to_regprocedure('crm.gestion_diaria_analista_fn(date,uuid)') is null
     or md5(pg_get_functiondef('crm.gestion_diaria_analista_fn(date,uuid)'::regprocedure)) is distinct from 'b93970c865a6abc318a6372b8535c0e2'
     or md5(pg_get_functiondef('private.gestion_diaria_analista_core(uuid,date,timestamptz,timestamptz,timestamptz,timestamptz)'::regprocedure)) is distinct from 'df3712f027acfc8cbc95c7d08a2db5b5'
     or md5(pg_get_functiondef('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])'::regprocedure)) is distinct from '431e9fd8198adcb1cd7416cd0f15acaa'
     or md5(pg_get_functiondef('private.gestion_diaria_umbrales()'::regprocedure)) is distinct from '6ab633af9f5356f3fa11cf309ff4b25c'
     or md5(pg_get_functiondef('private.registro_actividad_core(timestamptz,timestamptz,uuid[],text[],text,integer,timestamptz,uuid)'::regprocedure)) is distinct from '3430460e4ab59aa185ec8305788cc9a4'
     or to_regprocedure('private.assert_gestion_diaria_analista()') is null
     or private.assert_gestion_diaria() not like 'OK: Gestion Diaria [OK%] [OK%] [OK%]' then
    raise exception 'registrar gestion diaria F3: la migración 20260920041500 no está aplicada tal cual — aplicarla antes de registrar';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20260920005000') then
    raise exception 'registrar gestion diaria F3: la Fase 2 (20260920005000) no está registrada — registrarla antes';
  end if;

  -- 2) La versión no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260920041500' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar gestion diaria F3: la versión 20260920041500 existe con OTRO cuerpo — investigar antes de tocar';
  end if;

  -- 3) Registro (idempotente).
  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('20260920041500', 'crm_gestion_diaria_analista', array[v_cuerpo])
  on conflict (version) do nothing;

  -- 4) RELECTURA fail-closed: la fila EXACTA, o se cae la transacción entera.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260920041500' and name = 'crm_gestion_diaria_analista'
     and cardinality(statements) = 1 and statements[1] = v_cuerpo;
  if v_n <> 1 then
    raise exception 'registrar gestion diaria F3: la relectura no encontró la fila exacta';
  end if;
end $reg_gd_analista$;

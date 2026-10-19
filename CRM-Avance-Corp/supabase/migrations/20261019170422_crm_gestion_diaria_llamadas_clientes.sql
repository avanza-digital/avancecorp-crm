-- 20261019170422_crm_gestion_diaria_llamadas_clientes.sql
-- GESTIÓN DIARIA: las llamadas a CLIENTES cuentan en el número de llamadas del analista.
--
-- QUÉ PASABA. El marcador de Gestión Diaria (Mi día, Equipo, «Llamadas de hoy» del supervisor, cortes de jornada,
-- mínimo de llamadas útiles, Pulso y Hábitos) sale de UN lector, `private.gestion_diaria_llamadas_eventos`, que lee
-- solo `crm.actividades` (tabla de leads, `lead_id not null`). Las llamadas a clientes se registran al cerrar una
-- tarea de llamada de postventa y quedan en `crm.inversionista_gestiones` (tipo `cierre`, resultado en `metadata`),
-- que el marcador nunca miraba. Medido en producción el 19/10/2026: Vladimir Jurado cerró 5 llamadas a clientes
-- (3 «agendó reunión», 2 «volver a llamar») y su marcador decía «1 llamada» (la única a un lead).
--
-- DECISIONES DE MIGUEL (19/10/2026): (1) las llamadas a clientes SUMAN al mismo número «Llamadas»; (2) entran en la
-- TASA DE CONTACTO; (3) cuentan hacia los cortes de jornada y el mínimo de llamadas útiles.
-- Revisión de diseño de Codex (r1, 19/10, CHANGES_REQUESTED): aceptados (a) gate propio para el ayudante, (b) el
-- ayudante FILTRA por la visibilidad del actor en vez de lanzar error (no rompe el Pulso de un lector global),
-- (c) «leads tocados» sigue contando SOLO leads (no se promete «personas distintas»: lead y cliente no comparten
-- identidad), (d) misma regla de estado y de legado que el Registro de clientes (`gestiones_clientes_eventos`).
-- Rechazado con evidencia: filtro contra el doble conteo lead/cliente (0 llamadas sobre leads convertidos en 30 días
-- y la encuesta rechaza leads cerrados; un filtro podría borrar llamadas legítimas del mismo día).
--
-- QUÉ HACE.
--   1. Nuevo ayudante `private.gestion_diaria_llamadas_clientes_eventos(p_ini, p_fin, p_vendedor_ids)`
--      (SECURITY DEFINER, justificación: `crm.inversionista_gestiones` NO tiene policy de lectura, deny-by-default; la
--      cadena del marcador corre como el actor). Es un ESPEJO de la visibilidad, no una puerta: devuelve solo los
--      autores pedidos que estén en `private.vendedor_ids_visibles(auth.uid())`, exige sesión y
--      `private.puede_acceder_crm()`, rol vendedor/supervisor/gerencia (nunca un lector global), y devuelve vacío si
--      la postventa no está encendida: `private.resolver_en_puertas_bajo_candado()` y las dos banderas
--      `ficha_360_neutral` + `postventa_neutral` activas (o el actor en el piloto F8), LEÍDAS SIN CANDADO DE FILA.
--      No llama a `crm.postventa_estado_fn()`: esa puerta pasa por `private.postventa_modo()`, que toma `for share`,
--      y PostgREST ejecuta las puertas STABLE (toda la cadena del marcador) en una transacción de SOLO LECTURA, donde
--      `SELECT FOR SHARE` es un error (reproducido en el banco el 19/10/2026). Es la misma lectura sin candado que ya
--      hace `private.postventa_visible_actor` para la RLS de `crm.tareas`. Divergencia declarada con el Registro de
--      clientes: aquel exige además la cobertura de la cartera F5 (`crm.cartera_inversionistas_estado_fn`); si la
--      cartera entrara en «requiere conciliación», el Registro ocultaría las gestiones de clientes y el marcador no.
--      Los NULL de `p_vendedor_ids` se ignoran (una gestión siempre tiene autor). La métrica es POR QUIEN REGISTRÓ:
--      una reasignación de cartera no borra llamadas históricas.
--      El camino legado (`crm.actividades_cliente`, 3 filas en toda la historia) sigue EXACTAMENTE la regla del Registro:
--      no depende de la bandera de postventa (el Registro tampoco la aplica al legado), toma el estado de la tarea
--      enlazada si la hay (`coalesce(t.estado, 'completada')`) y descarta los espejos de un cierre F6 (auditor-rls P2, 19/10).
--      Qué es una llamada a cliente: cierre (`tipo = 'cierre'`) de una tarea de tipo `llamada` con estado
--      `completada` (misma regla que el Registro: `coalesce(metadata->>'tipo_tarea', t.tipo)` y
--      `coalesce(metadata->>'estado', t.estado)`), más el camino legado `crm.actividades_cliente` sin espejo de cierre.
--      Traducción (idéntica a la del Registro de clientes y al catálogo de 7 resultados de los leads):
--        no_contesto, numero_errado, no_es_la_persona → `llamada_no_contestada`; el resto → `llamada_realizada`;
--        útil = resultado ∉ {numero_errado, no_es_la_persona, sin_resultado} (un cierre antiguo sin resultado cuenta
--        como llamada, pero no como contestada ni útil; el legado `llamada_realizada` sí es contacto, como en el
--        Registro).
--   2. `private.gestion_diaria_llamadas_eventos` (INVOKER, misma firma y mismo retorno) devuelve leads ∪ clientes:
--      el cuerpo vivo + `union all` del ayudante. Las filas de clientes llevan `lead_id` NULL.
--   3. `private.gestion_diaria_llamadas` (agregador): cuerpo vivo con DOS cambios: `leads_tocados` excluye el NULL
--      (`array_agg(distinct l.lead_id) filter (where l.lead_id is not null)`: sigue contando leads, nunca +1 por los
--      clientes) y las contestadas POR HORA usan la misma definición que el total (realizada Y útil), para que la suma
--      por hora cuadre también con una llamada a cliente sin resultado (Codex r2). Todo lo demás (llamadas, contestadas,
--      útiles, por resultado, primera/última) incluye a los clientes por construcción.
--   4. Re-sella TRES gates a partir de su cuerpo VIVO con reemplazos anclados: `private.assert_gestion_diaria_analista()`
--      (huella del agregador, huella del lector y la sección 1b nueva, insertada ANTES de la sección 2 para que corra antes de la huella del roster, hoy en rojo por causa ajena), `private.assert_gestion_diaria_citas()` (huella
--      del agregador: G4b exige revisar la lista de citas con la cifra) y `private.assert_gestion_diaria_pulso()` (huellas
--      del agregador y del lector). En el del analista, tres reemplazos
--      (huella del agregador, huella del lector, y una sección 1b nueva que exige al ayudante forma DEFINER, dueño
--      postgres, STABLE, search_path vacío, EXECUTE exactamente postgres y authenticated, sin contador crudo, su espejo
--      de visibilidad por estructura y su huella sellada). No toca la huella de `crm.equipo_visible_fn()` (en rojo
--      desde el 15/10 por la consulta de Coordinación: la re-sella `20261016211001`, trabajo aparte en pausa).
--   5. Mutantes nuevos `private.assert_gestion_diaria_llamadas_clientes_mutantes()` (solo banco): 12 mutaciones que el
--      gate debe detectar; se niega si el gate ya está en rojo (un gate rojo detecta cualquier mutante en vacío).
--
-- EFECTO EN PRODUCCIÓN. Los números del día en que se aplica se recalculan con las llamadas a clientes ya registradas.
-- Los cortes ya reconocidos no se reabren: el reconocimiento se guarda por alerta (`crm.alertas_reconocimientos`),
-- no por cifra. Apagar la postventa vuelve a retirar esas llamadas del marcador (misma bandera que el Registro).
-- Lo que NO cambia: cómo se registra una llamada a cliente; el sub-número «leads distintos» del Pulso
-- (`count(distinct lead_id)` ignora el NULL: sigue siendo solo leads); la cola, los compromisos y la cartera.
--
-- POSTFLIGHT. Verifica forma, ACL, huellas y la sección 1b del gate; exige el gate de citas VERDE; corre los gates del
-- analista y del pulso y acepta SOLO los rojos ajenos conocidos, por su texto Y su huella: `crm.equipo_visible_fn()`
-- con md5 58bd0554… (consulta de Coordinación, 15/10) y, en el pulso, el censo analítico ajeno (otras piezas desde el
-- 01/10, nunca las nuestras); cualquier otro rojo aborta la transacción. Como la sección 1b va ANTES de la huella del
-- roster, ese rojo ajeno demuestra que 1b ya pasó.
--
-- DECISIONES DECLARADAS PARA MIGUEL (auditor-rls 19/10, no bloquean): (a) Directorio (lector global) sigue sin ver llamadas
-- a clientes en Pulso/Equipo/día del analista (el Registro tampoco se las muestra): abrirlo ampliaría la visibilidad y
-- necesita su OK; (b) «llamadas por lead» (llamadas, ahora con clientes, / leads tocados) y los «con actividad» del Pulso
-- (que leen solo actividades de leads) quedan como están y se declaran; corregirlos toca otros tres núcleos sellados.
-- REVERSIÓN: supabase/scripts/gestion-diaria-llamadas-clientes/reversa.sql (devuelve lector, agregador y gate a sus
-- cuerpos de producción del 19/10 y retira el ayudante y los mutantes). Ensayo: ensayar.mjs (banco propio con el
-- esquema de producción; huellas medidas en dos pasadas).

begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local quote_all_identifiers = off;

-- ── PREFLIGHT ─────────────────────────────────────────────────────────────────
do $preflight$
declare
  v_gate text;
  v_n integer;
begin
  if to_regprocedure('private.gestion_diaria_llamadas_clientes_eventos(timestamptz,timestamptz,uuid[])') is not null
     or to_regprocedure('private.assert_gestion_diaria_llamadas_clientes_mutantes()') is not null then
    raise exception 'PREFLIGHT llamadas_clientes: ya instalada (total o parcialmente)';
  end if;
  -- Los dos cuerpos que se reemplazan son los VIVOS en producción (medidos el 19/10/2026, iguales en el banco).
  if md5(pg_get_functiondef('private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])'::regprocedure))
       is distinct from '27d25609c74e04c58f82e36af45d7327' then
    raise exception 'PREFLIGHT llamadas_clientes: private.gestion_diaria_llamadas_eventos no es el cuerpo vivo del 19/10 (md5 %)',
      md5(pg_get_functiondef('private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])'::regprocedure));
  end if;
  if md5(pg_get_functiondef('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])'::regprocedure))
       is distinct from '7c5d14e65cc0e55e57214589d11e9c9d' then
    raise exception 'PREFLIGHT llamadas_clientes: private.gestion_diaria_llamadas no es el cuerpo vivo del 19/10 (md5 %)',
      md5(pg_get_functiondef('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])'::regprocedure));
  end if;
  -- El gate vivo trae las tres anclas EXACTAMENTE una vez (compone con otros re-sellados del mismo gate).
  v_gate := pg_get_functiondef('private.assert_gestion_diaria_analista()'::regprocedure);
  foreach v_n in array array[
    (length(v_gate) - length(replace(v_gate, '''7c5d14e65cc0e55e57214589d11e9c9d''', ''))) / length('''7c5d14e65cc0e55e57214589d11e9c9d'''),
    (length(v_gate) - length(replace(v_gate, '''27d25609c74e04c58f82e36af45d7327''', ''))) / length('''27d25609c74e04c58f82e36af45d7327'''),
    (length(v_gate) - length(replace(v_gate, '  -- 2. Los CUERPOS propios, sellados (medidos en el banco, dos pasadas).', ''))) / length('  -- 2. Los CUERPOS propios, sellados (medidos en el banco, dos pasadas).')
  ] loop
    if v_n <> 1 then
      raise exception 'PREFLIGHT llamadas_clientes: el gate private.assert_gestion_diaria_analista no trae una ancla exactamente una vez (%)', v_n;
    end if;
  end loop;
  if v_gate like '%gestion_diaria_llamadas_clientes_eventos%' then
    raise exception 'PREFLIGHT llamadas_clientes: el gate ya nombra al ayudante';
  end if;
  -- Los otros dos gates que sellan el agregador (citas) y el agregador + lector (pulso): cada huella exactamente una vez.
  v_gate := pg_get_functiondef('private.assert_gestion_diaria_citas()'::regprocedure);
  if (length(v_gate) - length(replace(v_gate, '''7c5d14e65cc0e55e57214589d11e9c9d''', ''))) / 34 <> 1
     or v_gate like '%27d25609c74e04c58f82e36af45d7327%' then
    raise exception 'PREFLIGHT llamadas_clientes: el gate de citas no sella el agregador exactamente una vez';
  end if;
  v_gate := pg_get_functiondef('private.assert_gestion_diaria_pulso()'::regprocedure);
  if (length(v_gate) - length(replace(v_gate, '''7c5d14e65cc0e55e57214589d11e9c9d''', ''))) / 34 <> 1
     or (length(v_gate) - length(replace(v_gate, '''27d25609c74e04c58f82e36af45d7327''', ''))) / 34 <> 1 then
    raise exception 'PREFLIGHT llamadas_clientes: el gate del pulso no sella el agregador y el lector exactamente una vez';
  end if;
  -- Las fuentes que lee el ayudante tienen la forma esperada.
  if to_regclass('crm.inversionista_gestiones') is null or to_regclass('crm.actividades_cliente') is null
     or to_regprocedure('private.vendedor_ids_visibles(uuid)') is null
     or to_regprocedure('private.resolver_en_puertas_bajo_candado()') is null
     or to_regprocedure('private.piloto_f8_actor_activo(uuid)') is null
     or to_regprocedure('private.rol_crm(uuid)') is null or to_regprocedure('private.es_lector_global()') is null
     or to_regprocedure('private.puede_acceder_crm()') is null then
    raise exception 'PREFLIGHT llamadas_clientes: faltan fuentes o ayudantes de visibilidad';
  end if;
end $preflight$;

-- ── CAPA 2 · NÚCLEO · el ayudante de las llamadas a clientes ──────────────────
-- SECURITY DEFINER justificado: crm.inversionista_gestiones no tiene policy de lectura (deny-by-default) y la cadena
-- del marcador corre como el actor. Espejo de la visibilidad: solo autores pedidos que el actor puede ver.
create function private.gestion_diaria_llamadas_clientes_eventos(
  p_ini timestamptz,
  p_fin timestamptz,
  p_vendedor_ids uuid[]
) returns table (
  vendedor_id uuid,
  id uuid,
  lead_id uuid,
  tipo text,
  creado_en timestamptz,
  resultado text,
  util boolean,
  hora integer
)
language sql
stable
security definer
set search_path = ''
as $$
  with actor as (
    -- Espejo de la visibilidad del actor (vendedor_ids_visibles), con la puerta de acceso al CRM y el rol que puede ver
    -- clientes (vendedor/supervisor/gerencia, nunca un lector global): es lo que el Registro de clientes exige para
    -- TODA gestión de clientes. Sin sesión, sin acceso o con otro rol: ningún autor visible. Nunca lanza.
    select case
      when (select auth.uid()) is null or private.puede_acceder_crm() is not true then array[]::uuid[]
      when coalesce(private.rol_crm((select auth.uid())) in ('vendedor', 'supervisor', 'gerencia'), false) is not true
           or coalesce(private.es_lector_global(), false) then array[]::uuid[]
      else coalesce((select array_agg(v.id) from private.vendedor_ids_visibles((select auth.uid())) as v(id)), array[]::uuid[])
    end as visibles
  ),
  postventa as (
    -- La postventa encendida, leída SIN candado de fila (como private.postventa_visible_actor): la cadena del marcador
    -- corre en transacciones de solo lectura. Gobierna solo los cierres F6; el legado no depende de ella (como en el Registro).
    select private.resolver_en_puertas_bajo_candado() is true
       and (coalesce((select bool_and(f.activo) and cardinality(array_agg(f.nombre)) = 2
                      from crm.multiempresa_flags f where f.nombre in ('ficha_360_neutral', 'postventa_neutral')), false)
            or coalesce(private.piloto_f8_actor_activo((select auth.uid())), false)) as encendida
  ),
  autores as (
    select distinct p.id
    from unnest(p_vendedor_ids) as p(id), actor a
    where p.id is not null and p.id = any (a.visibles)
  ),
  cierres as (
    -- Postventa: el cierre de una tarea de llamada, completada (misma regla que gestiones_clientes_eventos).
    select g.creado_por as autor, g.id, g.creado_en,
           coalesce(g.metadata->>'tipo_tarea', t.tipo) as tarea_tipo,
           coalesce(g.metadata->>'estado', t.estado) as estado,
           coalesce(g.metadata->>'resultado', 'sin_resultado') as resultado,
           null::text as tipo_legado
    from crm.inversionista_gestiones g
    join crm.tareas t on t.id = g.tarea_id
    where g.tipo = 'cierre'
      and (select pv.encendida from postventa pv)
      and g.creado_por in (select au.id from autores au)
      and g.creado_en >= p_ini and g.creado_en < p_fin
    union all
    -- Camino legado (crm.actividades_cliente): la misma regla del Registro — estado de la tarea enlazada si la hay,
    -- sin depender de la bandera, y solo sin espejo de cierre F6.
    select a.creado_por, a.id, a.creado_en, 'llamada', coalesce(t.estado, 'completada'), 'sin_resultado', a.tipo
    from crm.actividades_cliente a
    left join crm.tareas t on t.id = a.tarea_id
    where a.tipo in ('llamada_realizada', 'llamada_no_contestada')
      and a.creado_por in (select au.id from autores au)
      and a.creado_en >= p_ini and a.creado_en < p_fin
      and not exists (select 1 from crm.inversionista_gestiones g where g.tarea_id = a.tarea_id and g.tipo = 'cierre')
  )
  select c.autor,
         c.id,
         null::uuid,
         coalesce(c.tipo_legado,
                  case when c.resultado in ('no_contesto', 'numero_errado', 'no_es_la_persona')
                       then 'llamada_no_contestada' else 'llamada_realizada' end),
         c.creado_en,
         c.resultado,
         (c.tipo_legado is not null) or c.resultado not in ('numero_errado', 'no_es_la_persona', 'sin_resultado'),
         extract(hour from c.creado_en at time zone 'America/Lima')::integer
  from cierres c
  where c.tarea_tipo = 'llamada' and c.estado = 'completada';
$$;
comment on function private.gestion_diaria_llamadas_clientes_eventos(timestamptz, timestamptz, uuid[]) is
  'NÚCLEO (Gestión Diaria, 19/10/2026): las llamadas a CLIENTES del marcador: cierres completados de tareas de llamada de postventa (crm.inversionista_gestiones, resultado en metadata) y el legado crm.actividades_cliente sin espejo de cierre, en la ventana [p_ini, p_fin), con la misma forma que el lector de leads (lead_id NULL). DEFINER justificado: la tabla no tiene policy de lectura; es un ESPEJO de la visibilidad del actor (vendedor_ids_visibles + puede_acceder_crm + rol vendedor/supervisor/gerencia sin lector global; los cierres F6 además con las banderas de postventa leídas sin candado, como postventa_visible_actor; el legado sin bandera, como en el Registro), devuelve solo autores visibles y vale en transacciones de solo lectura. Traducción idéntica al Registro de clientes: no_contesto/numero_errado/no_es_la_persona → no contestada; útil = resultado fuera de numero_errado/no_es_la_persona/sin_resultado; el legado llamada_realizada es contacto.';
revoke all on function private.gestion_diaria_llamadas_clientes_eventos(timestamptz, timestamptz, uuid[])
  from public, anon, authenticated, service_role;
grant execute on function private.gestion_diaria_llamadas_clientes_eventos(timestamptz, timestamptz, uuid[]) to authenticated;

-- ── el lector único: leads ∪ clientes (cuerpo vivo + union all) ───────────────
create or replace function private.gestion_diaria_llamadas_eventos(
  p_ini timestamptz,p_fin timestamptz,p_vendedor_ids uuid[])
returns table(vendedor_id uuid,id uuid,lead_id uuid,tipo text,creado_en timestamptz,
  resultado text,util boolean,hora integer)
language sql stable security invoker set search_path='' as $$
  select a.creado_por,a.id,a.lead_id,a.tipo,a.creado_en,
    coalesce(a.metadata->>'resultado','sin_resultado'),
    coalesce(a.metadata->>'resultado','') not in ('numero_errado','no_es_la_persona'),
    extract(hour from a.creado_en at time zone 'America/Lima')::integer
  from crm.actividades a where
    (a.creado_por=any(p_vendedor_ids)
      or (a.creado_por is null and array_position(p_vendedor_ids,null) is not null))
    and a.tipo in ('llamada_realizada','llamada_no_contestada')
    and a.creado_en>=p_ini and a.creado_en<p_fin
  union all
  -- Las llamadas a clientes (19/10/2026): mismo contrato, lead_id NULL, bajo el espejo de visibilidad del ayudante.
  select c.vendedor_id,c.id,c.lead_id,c.tipo,c.creado_en,c.resultado,c.util,c.hora
  from private.gestion_diaria_llamadas_clientes_eventos(p_ini,p_fin,p_vendedor_ids) c;
$$;
comment on function private.gestion_diaria_llamadas_eventos(timestamptz, timestamptz, uuid[]) is
  'NÚCLEO (Gestión Diaria): el lector único de llamadas del marcador, por autor y ventana [p_ini, p_fin): llamadas a leads (crm.actividades, bajo la RLS del actor) ∪ llamadas a clientes (private.gestion_diaria_llamadas_clientes_eventos, espejo de visibilidad; lead_id NULL). Desde el 19/10/2026 las llamadas a clientes cuentan en el mismo número (decisión de Miguel).';

-- ── el agregador: cuerpo vivo con UN cambio (leads_tocados excluye el NULL de los clientes) ─
CREATE OR REPLACE FUNCTION private.gestion_diaria_llamadas(p_ini timestamp with time zone, p_fin timestamp with time zone, p_vendedor_ids uuid[])
 RETURNS TABLE(vendedor_id uuid, llamadas integer, contestadas integer, utiles integer, leads_tocados integer, citas_agendadas integer, primera_llamada_en timestamp with time zone, ultima_llamada_en timestamp with time zone, por_resultado jsonb, por_hora jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with vendedores as (
    select distinct v.id from unnest(p_vendedor_ids) as v(id)
  ),
  ll as (
    select * from private.gestion_diaria_llamadas_eventos(p_ini,p_fin,p_vendedor_ids)
  ),
  agg as (
    select l.vendedor_id,
           cardinality(array_agg(l.id)) as llamadas,
           -- Contestadas ⊆ útiles POR CONSTRUCCIÓN: la tasa nunca puede pasar del
           -- 100 % aunque una fila histórica llevara un resultado incoherente
           -- con su tipo (hoy no hay ninguna: medido en producción el 20/09).
           coalesce(cardinality(array_agg(l.id) filter (where l.tipo = 'llamada_realizada' and l.util)), 0) as contestadas,
           coalesce(cardinality(array_agg(l.id) filter (where l.util)), 0) as utiles,
           -- Leads tocados = leads distintos. Las llamadas a clientes (19/10/2026) traen lead_id NULL y
           -- no cuentan aquí: lead y cliente no comparten identidad.
           cardinality(array_agg(distinct l.lead_id) filter (where l.lead_id is not null)) as leads_tocados,
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
             -- Misma definición de contestada que el total (realizada Y útil): la suma por hora cuadra con el
             -- marcador también cuando una llamada a cliente llega sin resultado (Codex r2, 19/10/2026).
             coalesce(cardinality(array_agg(l.id) filter (where l.tipo = 'llamada_realizada' and l.util)), 0) as c
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
    where (t.vendedor_id in (select v.id from vendedores v)
      or (t.vendedor_id is null and array_position(p_vendedor_ids, null) is not null))
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
  left join agg a on a.vendedor_id is not distinct from v.id
  left join por_resultado r on r.vendedor_id is not distinct from v.id
  left join por_hora h on h.vendedor_id is not distinct from v.id
  left join citas c on c.vendedor_id is not distinct from v.id
  order by v.id;
$function$;
comment on function private.gestion_diaria_llamadas(timestamptz, timestamptz, uuid[]) is
  'NÚCLEO (Gestión Diaria): la definición única de llamada (realizada + no contestada, a leads Y a clientes desde el 19/10/2026), contacto (realizada y útil), útil (resultado ∉ numero_errado/no_es_la_persona; en leads sin resultado cuenta como útil; en clientes sin resultado no), leads tocados (solo leads: las llamadas a clientes no suman aquí), citas agendadas (tarea reunion creada en la ventana), primera/última llamada, desglose por resultado y por hora Lima, por analista y ventana [p_ini, p_fin). Bajo la RLS del actor; sin contadores crudos.';

-- ── GATE · re-sellar private.assert_gestion_diaria_analista desde su cuerpo VIVO ─
do $gate$
declare
  v_def text;
  v_seccion text;
begin
  v_def := pg_get_functiondef('private.assert_gestion_diaria_analista()'::regprocedure);
  -- Huellas nuevas del agregador y del lector (medidas en el banco, dos pasadas).
  v_def := replace(v_def, '''7c5d14e65cc0e55e57214589d11e9c9d''', '''231845001abb2386645231442a5fb103''');
  v_def := replace(v_def, '''27d25609c74e04c58f82e36af45d7327''', '''a209ec1be82b2eeff40c7f6488342d69''');
  -- Sección 1b: el ayudante DEFINER de las llamadas a clientes (antes de la sección 2, la de las huellas).
  v_seccion := $s$  -- 1b. El ayudante DEFINER de las llamadas a CLIENTES (19/10/2026): forma exacta (DEFINER, dueño
  --     postgres, STABLE, search_path vacío), EXECUTE exactamente postgres y authenticated, sin contador crudo,
  --     su espejo de visibilidad por estructura y su cuerpo sellado. Es un ESPEJO de la visibilidad del actor
  --     (vendedor_ids_visibles + puede_acceder_crm + banderas de postventa sin candado), no una puerta.
  v_id := to_regprocedure('private.gestion_diaria_llamadas_clientes_eventos(timestamptz,timestamptz,uuid[])');
  if v_id is null or not exists (
    select 1 from pg_proc p
    where p.oid = v_id and p.prosecdef
      and p.proowner = 'postgres'::regrole::oid
      and p.provolatile = 's'
      and p.proconfig @> array['search_path=""']
  ) then
    raise exception 'Contrato del ayudante de llamadas a clientes alterado (debe ser DEFINER, stable, search_path vacio, dueno postgres)';
  end if;
  if not has_function_privilege('authenticated', v_id, 'EXECUTE')
     or exists (
       select 1 from pg_proc p
       cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
       where p.oid = v_id
         and a.grantee not in ('postgres'::regrole::oid, 'authenticated'::regrole::oid)
     ) then
    raise exception 'ACL del ayudante de llamadas a clientes alterada';
  end if;
  if exists (select 1 from pg_proc p where p.oid = v_id
             and (lower(p.prosrc) ~ '\mcount\s*\(' or lower(p.prosrc) ~ '\msum\s*\(\s*1\s*\)')) then
    raise exception 'El ayudante de llamadas a clientes cuenta a crudo';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = v_id
                 and p.prosrc like '%private.vendedor_ids_visibles(%'
                 and p.prosrc like '%private.puede_acceder_crm()%'
                 and p.prosrc like '%private.resolver_en_puertas_bajo_candado()%'
                 and p.prosrc like '%''postventa_neutral''%'
                 and p.prosrc not like '%for share%') then
    raise exception 'El ayudante de llamadas a clientes perdio su espejo de visibilidad (vendedor_ids_visibles, puede_acceder_crm, resolver_en_puertas y banderas de postventa sin candado)';
  end if;
  if md5(pg_get_functiondef(v_id)) is distinct from '35c22cec66e3f7fa929d1514c338e3b3' then
    raise exception 'El cuerpo de private.gestion_diaria_llamadas_clientes_eventos cambio: re-sellar el dia del analista de Gestion Diaria (md5 %)',
      md5(pg_get_functiondef(v_id));
  end if;

$s$;
  -- Va ANTES de la sección 2: así corre antes de la huella del roster (hoy en rojo por causa ajena) y el postflight
  -- puede demostrar que 1b pasó aunque el gate termine rojo por ese motivo.
  v_def := replace(v_def,
    '  -- 2. Los CUERPOS propios, sellados (medidos en el banco, dos pasadas).',
    v_seccion || '  -- 2. Los CUERPOS propios, sellados (medidos en el banco, dos pasadas).');
  if v_def not like '%231845001abb2386645231442a5fb103%' or v_def not like '%a209ec1be82b2eeff40c7f6488342d69%'
     or v_def not like '%-- 1b. El ayudante DEFINER de las llamadas a CLIENTES%' then
    raise exception 'GATE llamadas_clientes: algun reemplazo anclado no aplico';
  end if;
  execute v_def;
  -- El gate de citas (G4b) sella el agregador: misma cifra, lista de citas revisada (las llamadas a clientes no son citas).
  v_def := pg_get_functiondef('private.assert_gestion_diaria_citas()'::regprocedure);
  v_def := replace(v_def, '''7c5d14e65cc0e55e57214589d11e9c9d''', '''231845001abb2386645231442a5fb103''');
  if v_def not like '%231845001abb2386645231442a5fb103%' then
    raise exception 'GATE llamadas_clientes: el reemplazo en el gate de citas no aplico';
  end if;
  execute v_def;
  -- El gate del pulso sella el agregador y el lector.
  v_def := pg_get_functiondef('private.assert_gestion_diaria_pulso()'::regprocedure);
  v_def := replace(v_def, '''7c5d14e65cc0e55e57214589d11e9c9d''', '''231845001abb2386645231442a5fb103''');
  v_def := replace(v_def, '''27d25609c74e04c58f82e36af45d7327''', '''a209ec1be82b2eeff40c7f6488342d69''');
  if v_def not like '%231845001abb2386645231442a5fb103%' or v_def not like '%a209ec1be82b2eeff40c7f6488342d69%' then
    raise exception 'GATE llamadas_clientes: el reemplazo en el gate del pulso no aplico';
  end if;
  execute v_def;
end $gate$;
comment on function private.assert_gestion_diaria_analista() is
  'Trinquete de Gestión Diaria F3 (el día del analista): puerta y núcleos INVOKER con ACL exacta, huellas selladas (puerta, núcleo, agregador, lector, umbrales, roster), ayudante DEFINER de las llamadas a clientes (sección 1b, 19/10/2026: forma, ACL, espejo de visibilidad y huella, antes de la huella del roster), cola v2 en su forma y perilla del abandono bajo RLS. Re-sellado el 19/10/2026 para contar las llamadas a clientes.';

-- ── MUTANTES (solo banco) ─────────────────────────────────────────────────────
create function private.assert_gestion_diaria_llamadas_clientes_mutantes() returns text
language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_detectados integer := 0;
  v_mutacion text;
  v_nombre text;
  v_previo text;
begin
  if coalesce(current_setting('gestion_diaria.banco', true), '') <> 'on' then
    raise exception 'Los mutantes solo corren en el banco (set gestion_diaria.banco = on)';
  end if;
  -- Un gate en rojo detecta cualquier mutante en vacío: se exige verde antes de mutar.
  begin
    v_previo := private.assert_gestion_diaria_analista();
  exception when others then
    raise exception 'GATE EN ROJO antes de mutar (mutantes no concluyentes): %', sqlerrm;
  end;
  for v_nombre, v_mutacion in select * from (values
    ('1 ayudante invoker',          'alter function private.gestion_diaria_llamadas_clientes_eventos(timestamptz, timestamptz, uuid[]) security invoker'),
    ('2 ayudante para anon',        'grant execute on function private.gestion_diaria_llamadas_clientes_eventos(timestamptz, timestamptz, uuid[]) to anon'),
    ('3 ayudante volatile',         'alter function private.gestion_diaria_llamadas_clientes_eventos(timestamptz, timestamptz, uuid[]) volatile'),
    ('4 ayudante sin search_path',  'alter function private.gestion_diaria_llamadas_clientes_eventos(timestamptz, timestamptz, uuid[]) reset search_path'),
    ('5 ayudante sin EXECUTE',      'revoke execute on function private.gestion_diaria_llamadas_clientes_eventos(timestamptz, timestamptz, uuid[]) from authenticated'),
    ('6 ayudante borrado',          'drop function private.gestion_diaria_llamadas_clientes_eventos(timestamptz, timestamptz, uuid[])'),
    ('7 ayudante sin espejo de visibilidad', $m$create or replace function private.gestion_diaria_llamadas_clientes_eventos(p_ini timestamptz, p_fin timestamptz, p_vendedor_ids uuid[]) returns table (vendedor_id uuid, id uuid, lead_id uuid, tipo text, creado_en timestamptz, resultado text, util boolean, hora integer) language sql stable security definer set search_path = '' as $b$ select g.creado_por, g.id, null::uuid, 'llamada_realizada', g.creado_en, coalesce(g.metadata->>'resultado','sin_resultado'), true, extract(hour from g.creado_en at time zone 'America/Lima')::integer from crm.inversionista_gestiones g where g.tipo = 'cierre' and g.creado_por = any(p_vendedor_ids) and g.creado_en >= p_ini and g.creado_en < p_fin and coalesce((select bool_and(f.activo) and cardinality(array_agg(f.nombre)) = 2 from crm.multiempresa_flags f where f.nombre in ('ficha_360_neutral', 'postventa_neutral')), false) and private.resolver_en_puertas_bajo_candado() and private.puede_acceder_crm() $b$$m$),
    ('8 ayudante sin banderas de postventa (con resolver)', $m$create or replace function private.gestion_diaria_llamadas_clientes_eventos(p_ini timestamptz, p_fin timestamptz, p_vendedor_ids uuid[]) returns table (vendedor_id uuid, id uuid, lead_id uuid, tipo text, creado_en timestamptz, resultado text, util boolean, hora integer) language sql stable security definer set search_path = '' as $b$ select g.creado_por, g.id, null::uuid, 'llamada_realizada', g.creado_en, coalesce(g.metadata->>'resultado','sin_resultado'), true, extract(hour from g.creado_en at time zone 'America/Lima')::integer from crm.inversionista_gestiones g where g.tipo = 'cierre' and g.creado_por = any(p_vendedor_ids) and g.creado_por in (select private.vendedor_ids_visibles((select auth.uid()))) and private.puede_acceder_crm() and private.resolver_en_puertas_bajo_candado() and g.creado_en >= p_ini and g.creado_en < p_fin $b$$m$),
    ('12 ayudante sin resolver_en_puertas (con banderas)', $m$create or replace function private.gestion_diaria_llamadas_clientes_eventos(p_ini timestamptz, p_fin timestamptz, p_vendedor_ids uuid[]) returns table (vendedor_id uuid, id uuid, lead_id uuid, tipo text, creado_en timestamptz, resultado text, util boolean, hora integer) language sql stable security definer set search_path = '' as $b$ select g.creado_por, g.id, null::uuid, 'llamada_realizada', g.creado_en, coalesce(g.metadata->>'resultado','sin_resultado'), true, extract(hour from g.creado_en at time zone 'America/Lima')::integer from crm.inversionista_gestiones g where g.tipo = 'cierre' and g.creado_por = any(p_vendedor_ids) and g.creado_por in (select private.vendedor_ids_visibles((select auth.uid()))) and private.puede_acceder_crm() and coalesce((select bool_and(f.activo) and cardinality(array_agg(f.nombre)) = 2 from crm.multiempresa_flags f where f.nombre in ('ficha_360_neutral', 'postventa_neutral')), false) and g.creado_en >= p_ini and g.creado_en < p_fin $b$$m$),
    ('9 ayudante con contador crudo', $m$create or replace function private.gestion_diaria_llamadas_clientes_eventos(p_ini timestamptz, p_fin timestamptz, p_vendedor_ids uuid[]) returns table (vendedor_id uuid, id uuid, lead_id uuid, tipo text, creado_en timestamptz, resultado text, util boolean, hora integer) language sql stable security definer set search_path = '' as $b$ select g.creado_por, g.id, null::uuid, 'llamada_realizada', g.creado_en, coalesce(g.metadata->>'resultado','sin_resultado'), true, extract(hour from g.creado_en at time zone 'America/Lima')::integer from crm.inversionista_gestiones g where g.tipo = 'cierre' and g.creado_por = any(p_vendedor_ids) and g.creado_por in (select private.vendedor_ids_visibles((select auth.uid()))) and private.puede_acceder_crm() and coalesce((select bool_and(f.activo) and cardinality(array_agg(f.nombre)) = 2 from crm.multiempresa_flags f where f.nombre in ('ficha_360_neutral', 'postventa_neutral')), false) and private.resolver_en_puertas_bajo_candado() and g.creado_en >= p_ini and g.creado_en < p_fin and (select cou$m$ || $m$nt(*) from crm.tareas t where t.id = g.tarea_id) = 1 $b$$m$),
    ('10 lector solo leads',        $m$create or replace function private.gestion_diaria_llamadas_eventos(p_ini timestamptz,p_fin timestamptz,p_vendedor_ids uuid[]) returns table(vendedor_id uuid,id uuid,lead_id uuid,tipo text,creado_en timestamptz, resultado text,util boolean,hora integer) language sql stable security invoker set search_path='' as $b$ select a.creado_por,a.id,a.lead_id,a.tipo,a.creado_en, coalesce(a.metadata->>'resultado','sin_resultado'), coalesce(a.metadata->>'resultado','') not in ('numero_errado','no_es_la_persona'), extract(hour from a.creado_en at time zone 'America/Lima')::integer from crm.actividades a where (a.creado_por=any(p_vendedor_ids) or (a.creado_por is null and array_position(p_vendedor_ids,null) is not null)) and a.tipo in ('llamada_realizada','llamada_no_contestada') and a.creado_en>=p_ini and a.creado_en<p_fin $b$$m$),
    ('11 agregador cuenta el nulo (cuerpo exacto sin el filtro)', $m$CREATE OR REPLACE FUNCTION private.gestion_diaria_llamadas(p_ini timestamp with time zone, p_fin timestamp with time zone, p_vendedor_ids uuid[]) RETURNS TABLE(vendedor_id uuid, llamadas integer, contestadas integer, utiles integer, leads_tocados integer, citas_agendadas integer, primera_llamada_en timestamp with time zone, ultima_llamada_en timestamp with time zone, por_resultado jsonb, por_hora jsonb) LANGUAGE sql STABLE SET search_path TO '' AS $b$
  with vendedores as (
    select distinct v.id from unnest(p_vendedor_ids) as v(id)
  ),
  ll as (
    select * from private.gestion_diaria_llamadas_eventos(p_ini,p_fin,p_vendedor_ids)
  ),
  agg as (
    select l.vendedor_id,
           cardinality(array_agg(l.id)) as llamadas,
           -- Contestadas ⊆ útiles POR CONSTRUCCIÓN: la tasa nunca puede pasar del
           -- 100 % aunque una fila histórica llevara un resultado incoherente
           -- con su tipo (hoy no hay ninguna: medido en producción el 20/09).
           coalesce(cardinality(array_agg(l.id) filter (where l.tipo = 'llamada_realizada' and l.util)), 0) as contestadas,
           coalesce(cardinality(array_agg(l.id) filter (where l.util)), 0) as utiles,
           -- Leads tocados = leads distintos. Las llamadas a clientes (19/10/2026) traen lead_id NULL y
           -- no cuentan aquí: lead y cliente no comparten identidad.
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
             -- Misma definición de contestada que el total (realizada Y útil): la suma por hora cuadra con el
             -- marcador también cuando una llamada a cliente llega sin resultado (Codex r2, 19/10/2026).
             coalesce(cardinality(array_agg(l.id) filter (where l.tipo = 'llamada_realizada' and l.util)), 0) as c
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
    where (t.vendedor_id in (select v.id from vendedores v)
      or (t.vendedor_id is null and array_position(p_vendedor_ids, null) is not null))
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
  left join agg a on a.vendedor_id is not distinct from v.id
  left join por_resultado r on r.vendedor_id is not distinct from v.id
  left join por_hora h on h.vendedor_id is not distinct from v.id
  left join citas c on c.vendedor_id is not distinct from v.id
  order by v.id;
$b$$m$)
  ) as m(nombre, sql) loop
    begin
      begin
        execute v_mutacion;
      exception when others then
        raise exception 'MUTANTE % NO APLICABLE: %', v_nombre, sqlerrm;
      end;
      perform private.assert_gestion_diaria_analista();
      raise exception 'MUTANTE % NO DETECTADO: paso el gate', v_nombre;
    exception when others then
      if sqlerrm like 'MUTANTE %' then raise; end if;
      v_detectados := v_detectados + 1;
    end;
  end loop;
  if v_detectados <> 12 then
    raise exception 'MUTANTES: se esperaban 12 detecciones y hubo %', v_detectados;
  end if;
  return format('OK: %s mutantes detectados por private.assert_gestion_diaria_analista()', v_detectados);
end;
$function$;
comment on function private.assert_gestion_diaria_llamadas_clientes_mutantes() is
  'Mutantes del ayudante de llamadas a clientes de Gestión Diaria (solo banco, exige set gestion_diaria.banco = on): se niega si el gate ya está en rojo (detección en vacío); cada mutación vive en una subtransacción que se deshace; falla si el gate no la detecta o si la mutación no aplica.';
revoke all on function private.assert_gestion_diaria_llamadas_clientes_mutantes() from public, anon, authenticated, service_role;

-- ── POSTFLIGHT ────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_id oid := to_regprocedure('private.gestion_diaria_llamadas_clientes_eventos(timestamptz,timestamptz,uuid[])');
  v_gate text := pg_get_functiondef('private.assert_gestion_diaria_analista()'::regprocedure);
  v_msg text;
begin
  -- Forma y ACL del ayudante; huellas de lo instalado = lo que sella el gate.
  if v_id is null or not exists (select 1 from pg_proc p where p.oid = v_id and p.prosecdef and p.provolatile = 's'
                                   and p.proowner = 'postgres'::regrole::oid and p.proconfig @> array['search_path=""']) then
    raise exception 'POSTFLIGHT llamadas_clientes: el ayudante no tiene la forma esperada';
  end if;
  if not has_function_privilege('authenticated', v_id, 'EXECUTE')
     or exists (select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                where p.oid = v_id and a.grantee not in ('postgres'::regrole::oid, 'authenticated'::regrole::oid)) then
    raise exception 'POSTFLIGHT llamadas_clientes: ACL del ayudante inesperada (debe ser exactamente postgres y authenticated)';
  end if;
  if v_gate not like '%' || md5(pg_get_functiondef(v_id)) || '%'
     or v_gate not like '%' || md5(pg_get_functiondef('private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])'::regprocedure)) || '%'
     or v_gate not like '%' || md5(pg_get_functiondef('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])'::regprocedure)) || '%' then
    raise exception 'POSTFLIGHT llamadas_clientes: el gate no sella las huellas instaladas (ayudante %, lector %, agregador %)',
      md5(pg_get_functiondef(v_id)),
      md5(pg_get_functiondef('private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])'::regprocedure)),
      md5(pg_get_functiondef('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])'::regprocedure));
  end if;
  if v_gate like '%MD5_%PENDIENTE%' then
    raise exception 'POSTFLIGHT llamadas_clientes: el gate quedo con placeholders';
  end if;
  -- El lector devuelve filas de clientes con el contrato esperado (tipo y util coherentes) para cualquier ventana:
  -- como postgres (dueño) el ayudante no ve autores (sin sesión), así que aquí solo se prueba que ejecuta.
  perform 1 from private.gestion_diaria_llamadas_eventos(now() - interval '1 day', now(), array[gen_random_uuid()]);
  if pg_get_functiondef('private.assert_gestion_diaria_citas()'::regprocedure) like '%MD5_%PENDIENTE%'
     or pg_get_functiondef('private.assert_gestion_diaria_pulso()'::regprocedure) like '%MD5_%PENDIENTE%' then
    raise exception 'POSTFLIGHT llamadas_clientes: un gate quedo con placeholders';
  end if;
  -- El gate de citas (G4b) debe quedar VERDE: sellaba el agregador y no depende del roster.
  v_msg := private.assert_gestion_diaria_citas();
  raise notice 'POSTFLIGHT llamadas_clientes: gate de citas %', v_msg;
  -- Los gates del analista y del pulso: verdes, o rojos SOLO por el roster ajeno (crm.equipo_visible_fn, 15/10;
  -- lo re-sella aparte 20261016211001).
  begin
    v_msg := private.assert_gestion_diaria_analista();
    raise notice 'POSTFLIGHT llamadas_clientes: gate del dia del analista %', v_msg;
  exception when others then
    if sqlerrm like 'El cuerpo de crm.equipo_visible_fn() cambio:%(md5 58bd05540d2a3eb576a7b648978707e7)%' then
      -- La sección 1b va antes que esta huella: si el gate llegó aquí, el ayudante pasó forma, ACL, espejo y huella.
      raise notice 'POSTFLIGHT llamadas_clientes: el gate del analista sigue en rojo SOLO por crm.equipo_visible_fn 58bd0554 (ajeno, 15/10; la seccion 1b ya paso): %', sqlerrm;
    else
      raise exception 'POSTFLIGHT llamadas_clientes: el gate del dia del analista esta en rojo por otra causa: %', sqlerrm;
    end if;
  end;
  begin
    v_msg := private.assert_gestion_diaria_pulso();
    raise notice 'POSTFLIGHT llamadas_clientes: gate del pulso %', v_msg;
  exception when others then
    if sqlerrm like 'El cuerpo de crm.equipo_visible_fn() cambio:%(md5 58bd05540d2a3eb576a7b648978707e7)%' then
      raise notice 'POSTFLIGHT llamadas_clientes: el gate del pulso sigue en rojo SOLO por crm.equipo_visible_fn 58bd0554 (ajeno, 15/10): %', sqlerrm;
    elsif sqlerrm like 'Contadores crudos de leads/citas SIN declarar:%' and sqlerrm not like '%llamadas_clientes%'
          and sqlerrm not like '%gestion_diaria_llamadas(%' and sqlerrm not like '%gestion_diaria_llamadas_eventos%' then
      raise notice 'POSTFLIGHT llamadas_clientes: el gate del pulso sigue en rojo SOLO por el censo analitico ajeno (otras piezas, desde el 01/10): %', sqlerrm;
    else
      raise exception 'POSTFLIGHT llamadas_clientes: el gate del pulso esta en rojo por otra causa: %', sqlerrm;
    end if;
  end;
end $postflight$;

commit;

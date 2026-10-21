-- Gestión Diaria (20/10/2026): los pendientes, de lo más reciente a lo más antiguo.
--
-- Pedido de Miguel: «el orden de los pendientes sale de lo más tiempo vencido hasta lo que
-- tiene menos tiempo vencido y quiero que sea al revés». Decisión (20/10/2026):
--   · Pendientes del supervisor/gerencia (H3+G4a): toda la lista por vence_en DESCENDENTE.
--     En «Vencidas», lo que venció hace menos tiempo arriba y lo más viejo al final; en
--     «Todas», lo de fecha más lejana arriba y lo vencido más viejo al final.
--   · Cola del analista («Mi día»): dentro de Vencidas, Sin primer intento y Sin conversación
--     va primero lo más reciente; «Hoy» sigue por hora (ahí nada está vencido). El orden ENTRE
--     grupos no cambia (decisión #2 de Miguel, 19/09/2026).
--
-- Cómo, sin romper a los bundles publicados (v.strictObject + validador de orden ascendente):
--   1) Núcleo NUEVO private.gestion_diaria_pendientes_core(…, p_recientes_primero boolean): el
--      cuerpo de G4a con el SENTIDO como parámetro (orden de la página y lado del cursor). Sin
--      claves nuevas en el payload: la v2 y los bundles abiertos no se enteran.
--   2) El núcleo de 5 argumentos pasa a ser un envoltorio del nuevo con `false`: la v1 y la v2
--      siguen ASCENDENTES (misma población, orden y cursor). Una sola copia del cuerpo.
--   3) Puerta NUEVA crm.gestion_diaria_pendientes_v3_fn: como la v2 (identidad autorizada del
--      cliente) pero con `true` y `version` 3. El front nuevo llama a la v3; el viejo, a la v2.
--   4) crm.gestion_diaria_cola_trabajo_fn: cambia SOLO el ORDER BY de los pendientes.
--   5) Gate H3 (private.assert_gestion_diaria_pendientes) re-sellado: huella nueva del núcleo
--      de 5 argumentos y fila nueva para el de 6 (patrón $sellar$ de G4a).
--
-- Lo que NO cambia: tablas, policies, RLS, grants de tablas, la v1, la v2, el ámbito, el
-- resumen ni la autorización. Todo sigue INVOKER bajo la RLS de crm.tareas, salvo la cola del
-- analista, que ya era DEFINER (compone ayudantes privados; actor = auth.uid()).
--
-- ⚠️ El gate H3 está en ROJO en producción desde antes y por otra causa (medido el 20/10/2026:
-- «El cuerpo de crm.equipo_visible_fn() cambio: re-sellar el dia del analista…», tarea
-- GUARDIANES-1610 en pausa). Esta migración NO lo usa como condición: comprueba sus filas de
-- pendientes inline antes y después, y exige que el VEREDICTO del gate sea el mismo antes y
-- después (si estaba verde sigue verde; si estaba rojo por lo ajeno, sigue rojo por lo mismo y
-- nunca por esto). Aviso a esa tarea: supabase/scripts/pendientes-recientes-20261020/AVISO-GUARDIANES-1610.md.
--
-- Instalación (Miguel, con `!`, UN solo mensaje, desde CRM-Avance-Corp/):
--   supabase db query --linked --file supabase/migrations/20261020214445_crm_gestion_diaria_pendientes_recientes_primero.sql
--   supabase migration repair --status applied 20261020214445 --linked
-- Después, en app/: npm run gen:types (la v3 ya está escrita a mano en database.types.ts).
-- Cómo se revierte: supabase/scripts/pendientes-recientes-20261020/reversa.sql (si el front
-- nuevo ya está publicado, revertir PRIMERO el front: la v3 pasaría a PGRST202).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';
set local search_path = pg_catalog;
lock table private.analitica_leads_citas_exenciones, private.analitica_lc_sello,
  private.analista_vigencia_exenciones in share mode;

create temporary table gdp_censo_antes on commit drop as
  select 'lc'::text as censo, c.tipo, c.objeto, c.declarada, c.huella_ok
  from private.contadores_crudos_leads_citas() c
  union all
  select 'vigencia', v.tipo, v.objeto, v.declarada, v.huella_ok
  from private.puertas_analista_sin_vigencia() v;

-- El veredicto del gate H3 ANTES (su texto exacto, u OK): tiene que ser el mismo DESPUÉS.
create temporary table gdp_gate_antes on commit drop as select ''::text as veredicto;
do $gate_antes$
declare v text;
begin
  begin
    perform private.assert_gestion_diaria_pendientes();
    v := 'OK';
  exception when others then
    v := sqlerrm;
  end;
  update gdp_gate_antes set veredicto = v;
end $gate_antes$;

do $preflight$
declare v_firma text; v_huella text;
begin
  -- Identidad COMPLETA (cuerpo, atributos, dueño y ACL) de lo que se toca y de lo que se usa,
  -- medida en producción el 20/10/2026 e igual en el banco.
  if exists (
    select 1
    from (values
    ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)', 'a0bde87db9ea86694ba4ee79dc109729', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid)', 'd69dd41dbd7106283584e7d6b1cc9e1a', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.gestion_diaria_pendientes_v2_fn(uuid,boolean,integer,timestamptz,uuid)', '01a0d2a2a9bf520f4cf442740e791170', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text)', 'c166b286f6577ebf35809dfd708a0ab4', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.assert_gestion_diaria_pendientes()', '6aecb25a8a66e10cc5dcae69afb66281', '{postgres=X/postgres}'),
    ('private.gestion_diaria_equipo_ambito(uuid)', 'af06caf4d0ea5d392d9c36f069b3501b', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.gestiones_identificar_tareas(jsonb)', 'd4207eb75aec16f8f861c3ffc5a7a6d9', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.gestiones_clientes_identidades(jsonb)', '0023331bba7faf6ea232d572d7ecf2c2', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.rol_crm(uuid)', '99827f3fe2fbc3cfae5668c30015c758', '{postgres=X/postgres,authenticated=X/postgres}')
    ) as d(objeto, md5_def, acl)
    left join pg_catalog.pg_proc p on p.oid = pg_catalog.to_regprocedure(d.objeto)
    where p.oid is null
       or pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) is distinct from d.md5_def
       or p.proowner is distinct from 'postgres'::regrole::oid
       or p.proacl::text is distinct from d.acl
  ) then
    raise exception 'PREFLIGHT pendientes recientes: algo de lo que se toca o se usa no es lo medido el 20/10/2026 (cuerpo, atributos, dueño o ACL); conciliar antes de aplicar';
  end if;
  if pg_catalog.to_regprocedure('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid,boolean)') is not null
     or pg_catalog.to_regprocedure('crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid)') is not null then
    raise exception 'PREFLIGHT pendientes recientes: el núcleo de 6 argumentos o la v3 ya existen; esta migración ya se aplicó o hay otra línea viva';
  end if;
  -- Los COMMENT que se reescriben son los vivos el 20/10/2026 (pg_get_functiondef no los ve; la reversa los repone tal cual) (Codex).
  if pg_catalog.obj_description('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)'::regprocedure, 'pg_proc')
       is distinct from 'Núcleo H3+G4a: tareas actuales de un analista del ámbito de quien consulta (Supervisión: su árbol; Gerencia: toda la operación visible). INVOKER bajo RLS; cursor vence_en/id; supervisor_id = quien consulta.'
     or pg_catalog.obj_description('crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text)'::regprocedure, 'pg_proc')
       is distinct from 'Cola completa del propio analista: pendientes antes de gestionados, avance por actividad vigente en Lima, filtro y pagina anclada por clave. DEFINER porque compone ayudantes privados sin grants API; actor exclusivamente auth.uid().' then
    raise exception 'PREFLIGHT pendientes recientes: el COMMENT del núcleo o de la cola no es el medido el 20/10/2026; conciliar antes de aplicar';
  end if;
  -- Las filas de pendientes del gate H3 están verdes ANTES (lo mismo que exige el gate, sin sus gates anidados).
  for v_firma, v_huella in select * from (values
    ('private.gestion_diaria_equipo_ambito(uuid)', 'af06caf4d0ea5d392d9c36f069b3501b'),
    ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)', 'a0bde87db9ea86694ba4ee79dc109729'),
    ('crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid)', 'd69dd41dbd7106283584e7d6b1cc9e1a')
  ) as firmas(firma, huella) loop
    if not exists (select 1 from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure(v_firma)
      and not p.prosecdef and p.provolatile = 's' and p.proowner = 'postgres'::regrole
      and p.proconfig = array['search_path=""']
      and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
      and not pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE')
      and pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) = v_huella) then
      raise exception 'PREFLIGHT pendientes recientes: la fila % del gate H3 no está verde antes de tocar nada', v_firma;
    end if;
  end loop;
  if (select pg_catalog.count(*) from gdp_censo_antes) = 0 then
    raise exception 'PREFLIGHT pendientes recientes: la foto de los censos salió vacía';
  end if;
end $preflight$;

-- 1) El núcleo con SENTIDO. Es el cuerpo de G4a (20260928043728) más p_recientes_primero:
--    decide el orden de la página y el lado del cursor. Sin claves nuevas en el payload.
create function private.gestion_diaria_pendientes_core(
  p_analista_id uuid, p_solo_vencidas boolean, p_limite integer,
  p_despues_de timestamptz, p_despues_id uuid, p_recientes_primero boolean
) returns jsonb
language plpgsql stable security invoker set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_ambito jsonb;
  v_ahora timestamptz := statement_timestamp();
  v_respuesta jsonb;
  v_invalida boolean;
begin
  -- También protege la invocación directa del núcleo por authenticated. Supervisión y,
  -- desde G4a (27/09/2026), Gerencia; el rol nulo se rechaza explícitamente (Codex).
  if v_uid is null or not coalesce(v_rol in ('supervisor', 'gerencia'), false) then
    raise exception 'No autorizado para consultar pendientes' using errcode = '42501';
  end if;
  -- Supervisión: su árbol, como en H3. Gerencia: el roster canónico con supervisor nulo
  -- (toda la operación visible, «fuera» incluido), el mismo de gestion_diaria_equipo_core.
  v_ambito := private.gestion_diaria_equipo_ambito(case when v_rol = 'supervisor' then v_uid end);
  if p_analista_id is null or p_solo_vencidas is null or p_limite is null
    or p_recientes_primero is null
    or p_limite < 1 or p_limite > 100
    or (p_despues_de is null) <> (p_despues_id is null)
    or (p_despues_de is not null and not isfinite(p_despues_de)) then
    raise exception 'Parámetros de pendientes inválidos' using errcode = '22023';
  end if;
  if not exists (select 1 from jsonb_array_elements(v_ambito->'roster') r
    where (r->>'analista_id')::uuid = p_analista_id) then
    -- Ajeno, inactivo e inexistente tienen idéntica respuesta.
    raise exception 'No autorizado para consultar pendientes' using errcode = '42501';
  end if;

  -- Resumen y página comparten sentencia y RLS. La referencia no determina
  -- quién es responsable de la tarea ni elimina tareas sin lead visible.
  -- El SENTIDO (20/10/2026): con p_recientes_primero la página va por vence_en DESCENDENTE
  -- y el cursor avanza hacia atrás (más antiguo); sin él, ascendente y hacia adelante, como
  -- en H3. `n` es la posición en el sentido elegido y manda en la página y en el cursor.
  with base as materialized (
    select t.id, t.vendedor_id, t.tipo, t.titulo, t.vence_en,
      t.lead_id, t.perfil_id, t.inversionista_id
    from crm.tareas t
    where t.vendedor_id = p_analista_id and t.activo and t.estado = 'pendiente'
  ), resumen as (
    select coalesce(cardinality(array_agg(b.id)), 0) as tareas_pendientes,
      coalesce(cardinality(array_agg(b.id) filter (where b.vence_en < v_ahora)), 0) as tareas_vencidas,
      coalesce(bool_or(num_nonnulls(b.lead_id, b.perfil_id, b.inversionista_id) <> 1
        or not isfinite(b.vence_en)), false) as invalida
    from base b
  ), sonda as materialized (
    select b.*, row_number() over (order by
      case when p_recientes_primero then b.vence_en end desc, b.vence_en,
      case when p_recientes_primero then b.id end desc, b.id) as n
    from base b
    where (not p_solo_vencidas or b.vence_en < v_ahora)
      and (p_despues_de is null
        or (p_recientes_primero and (b.vence_en, b.id) < (p_despues_de, p_despues_id))
        or (not p_recientes_primero and (b.vence_en, b.id) > (p_despues_de, p_despues_id)))
    order by n limit p_limite + 1
  ), pagina as materialized (
    select s.* from sonda s where s.n <= p_limite
  ), estado as (
    select coalesce(cardinality(array_agg(s.id)), 0) > p_limite as hay_mas from sonda s
  )
  select jsonb_build_object(
    'version', 1, 'zona', 'America/Lima', 'supervisor_id', v_uid,
    'analista_id', p_analista_id, 'generado_en', v_ahora, 'pendientes_al', v_ahora,
    'solo_vencidas', p_solo_vencidas, 'limite', p_limite,
    'resumen', jsonb_build_object('tareas_pendientes', r.tareas_pendientes,
      'tareas_vencidas', r.tareas_vencidas),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
      'id', p.id, 'vendedor_id', p.vendedor_id, 'tipo', p.tipo, 'titulo', p.titulo,
      'vence_en', p.vence_en, 'estado', 'pendiente',
      'referencia_tipo', case when p.lead_id is not null then 'lead'
        when p.perfil_id is not null then 'perfil' else 'postventa' end,
      'lead_id', case when nullif(btrim(l.nombre_completo), '') is not null then l.id end,
      'lead_nombre', nullif(btrim(l.nombre_completo), '')
    ) order by p.n) from pagina p left join crm.leads l on l.id = p.lead_id), '[]'::jsonb),
    'hay_mas', e.hay_mas,
    'siguiente_cursor', case when e.hay_mas then (select jsonb_build_object(
      'despues_de', p.vence_en, 'despues_id', p.id)
      from pagina p order by p.n desc limit 1) else null end
  ), r.invalida into v_respuesta, v_invalida from resumen r cross join estado e;
  if v_invalida then
    raise exception 'No se pudo confirmar la integridad de las tareas' using errcode = '22000';
  end if;
  return v_respuesta;
end;
$function$;
revoke all on function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid,boolean)
  from public, anon, authenticated, service_role;
grant execute on function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid,boolean) to authenticated;
comment on function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid,boolean) is
  'Núcleo H3+G4a con SENTIDO (20/10/2026): tareas actuales de un analista del ámbito de quien consulta (Supervisión: su árbol; Gerencia: toda la operación visible). INVOKER bajo RLS; cursor vence_en/id hacia atrás (p_recientes_primero: lo más reciente primero) o hacia adelante (ascendente, como H3); supervisor_id = quien consulta. Mismo payload.';

-- 2) El núcleo de 5 argumentos queda como envoltorio ASCENDENTE del nuevo: la v1 y la v2
--    (bundles publicados) conservan población, orden y cursor al byte.
create or replace function private.gestion_diaria_pendientes_core(
  p_analista_id uuid, p_solo_vencidas boolean, p_limite integer,
  p_despues_de timestamptz, p_despues_id uuid
) returns jsonb
language sql stable security invoker set search_path = ''
as $function$
  select private.gestion_diaria_pendientes_core(p_analista_id, p_solo_vencidas, p_limite,
    p_despues_de, p_despues_id, false);
$function$;
revoke all on function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid) to authenticated;
comment on function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid) is
  'Núcleo H3+G4a (envoltorio desde el 20/10/2026): delega en el núcleo con sentido, ASCENDENTE. Lo usan la v1 y la v2; misma población, orden y cursor que antes.';

-- 3) La puerta v3: como la v2 (identidad autorizada del cliente) pero de lo más reciente a lo
--    más antiguo y con version 3. VOLATILE como la v2: la identidad bloquea filas al resolverse.
create function crm.gestion_diaria_pendientes_v3_fn(p_analista_id uuid, p_solo_vencidas boolean default false,
  p_limite integer default 25, p_despues_de timestamptz default null, p_despues_id uuid default null)
returns jsonb language plpgsql security invoker set search_path = '' as $function$
declare v_r jsonb;
begin
  v_r := private.gestion_diaria_pendientes_core(p_analista_id, p_solo_vencidas, p_limite, p_despues_de, p_despues_id, true);
  return jsonb_set(v_r || jsonb_build_object('version', 3), '{items}', private.gestiones_identificar_tareas(v_r->'items'));
end;
$function$;
revoke all on function crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid) to authenticated;
comment on function crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid) is
  'Pendientes v3 (20/10/2026): la v2 de lo más reciente a lo más antiguo (vence_en descendente, cursor hacia atrás), con la identidad autorizada del cliente. Misma población, mismo resumen, version 3. La v2 sigue ascendente para los bundles publicados.';

-- 4) La cola del analista: SOLO cambia el ORDER BY de los pendientes (el resto, al byte).
CREATE OR REPLACE FUNCTION crm.gestion_diaria_cola_trabajo_fn(p_filtro text DEFAULT 'todo'::text, p_pagina integer DEFAULT 0, p_limite integer DEFAULT 8, p_elegido text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=(select auth.uid()); v_rol text; v_ahora timestamptz:=statement_timestamp();
  v_filas jsonb; v_ordenadas jsonb; v_totales jsonb; v_filtro text:=p_filtro;
  v_total integer; v_pagina integer; v_posicion integer; v_pendientes integer; v_items jsonb;
  v_elegido text; v_siguiente text; v_grupo text;
begin
  if v_actor is null or private.puede_acceder_crm() is not true then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_rol:=private.rol_crm(v_actor);
  if v_rol is null or v_rol not in ('vendedor','supervisor') then
    raise exception 'Esta cola es del analista que gestiona' using errcode='42501';
  end if;
  if p_filtro is null or p_filtro not in ('todo','primera_atencion','tarea_vencida','tarea_hoy','sin_conversacion')
    or p_pagina is null or p_pagina<0 or p_pagina>1000000
    or p_limite is null or p_limite not between 1 and 200
    or (p_elegido is not null and p_elegido !~ '^(lead|tarea):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
    raise exception 'Filtro, pagina o seleccion invalidos' using errcode='22023';
  end if;
  v_filas:=private.gestion_diaria_cola_filas(v_actor,v_rol,v_ahora);
  select f.value->>'grupo' into v_grupo from jsonb_array_elements(v_filas) f where f.value->>'clave'=p_elegido;
  if v_grupo is not null and p_filtro<>'todo' then v_filtro:=v_grupo; end if;

  select jsonb_object_agg(g.grupo,jsonb_build_object('total',g.total,'pendientes',g.pendientes,
    'gestionados',g.gestionados,'programados',g.programados)) into v_totales
  from (
    select grupos.grupo,count(f.value)::integer as total,
      count(f.value) filter (where f.value->>'estado_trabajo'='pendiente')::integer as pendientes,
      count(f.value) filter (where f.value->>'estado_trabajo'='gestionado')::integer as gestionados,
      count(f.value) filter (where f.value->>'estado_trabajo'='programado')::integer as programados
    from unnest(array['todo','primera_atencion','tarea_vencida','tarea_hoy','sin_conversacion']) grupos(grupo)
    left join jsonb_array_elements(v_filas) f on grupos.grupo='todo' or f.value->>'grupo'=grupos.grupo
    group by grupos.grupo
  ) g;

  -- Orden completo ANTES del límite. Pendientes conservan la prioridad SLA entre grupos;
  -- dentro de Vencidas, Sin primer intento y Sin conversación va primero lo más reciente
  -- (Miguel, 20/10/2026) y Hoy sigue por hora; gestionados/programados quedan detrás y el
  -- último guardado queda último.
  select coalesce(jsonb_agg(f.value order by
    (f.value->>'estado_trabajo'<>'pendiente'),
    case when f.value->>'estado_trabajo'='pendiente' then
      case f.value->>'grupo' when 'primera_atencion' then 10 when 'tarea_vencida' then 20 when 'tarea_hoy' then 30 else 40 end else 0 end,
    case when f.value->>'estado_trabajo'='pendiente' and f.value->>'grupo'='tarea_hoy' then (f.value->>'referencia_en')::timestamptz end nulls last,
    case when f.value->>'estado_trabajo'='pendiente' and f.value->>'grupo'<>'tarea_hoy' then (f.value->>'referencia_en')::timestamptz end desc nulls last,
    case when f.value->>'estado_trabajo'<>'pendiente' then (f.value#>>'{ultima_gestion,en}')::timestamptz end nulls first,
    (f.value->>'clave') collate "C"),'[]'::jsonb) into v_ordenadas
  from jsonb_array_elements(v_filas) f where v_filtro='todo' or f.value->>'grupo'=v_filtro;
  v_total:=jsonb_array_length(v_ordenadas);
  v_pendientes:=(v_totales->v_filtro->>'pendientes')::integer;
  select (f.n-1)::integer into v_posicion from jsonb_array_elements(v_ordenadas) with ordinality f(value,n)
    where f.value->>'clave'=p_elegido;
  v_pagina:=case when v_posicion is not null then v_posicion/p_limite
    else least(p_pagina,greatest((v_total-1)/p_limite,0)) end;
  select coalesce(jsonb_agg(f.value order by f.n),'[]'::jsonb) into v_items
    from jsonb_array_elements(v_ordenadas) with ordinality f(value,n)
    where f.n>v_pagina*p_limite and f.n<=(v_pagina+1)*p_limite;
  v_elegido:=case when v_posicion is not null then p_elegido else (
    select f.value->>'clave' from jsonb_array_elements(v_items) f
    where f.value->>'estado_trabajo'='pendiente' limit 1) end;
  select f.value->>'clave' into v_siguiente
    from jsonb_array_elements(v_ordenadas) with ordinality f(value,n)
    where f.value->>'estado_trabajo'='pendiente' and f.value->>'clave' is distinct from v_elegido
    order by case when f.n-1>coalesce(v_posicion,v_pagina*p_limite) then 0 else 1 end,f.n limit 1;
  return jsonb_build_object('version',1,'dia',(v_ahora at time zone 'America/Lima')::date,
    'zona','America/Lima','analista_id',v_actor,'generado_en',v_ahora,'filtro',v_filtro,
    'pagina',v_pagina,'limite',p_limite,'total',v_total,'totales',v_totales,'items',v_items,
    'elegido',v_elegido,'siguiente',v_siguiente,'vuelta_completa',v_pendientes=0,
    'proximo_cambio_en',least(
      (((v_ahora at time zone 'America/Lima')::date+1)::timestamp at time zone 'America/Lima'),
      (select min(x.en) from jsonb_array_elements(v_filas) f cross join lateral (
        select case when f.value->>'tipo'='cliente' then (f.value->>'referencia_en')::timestamptz
          else (f.value#>>'{proxima_tarea,vence_en}')::timestamptz end as en
      ) x where x.en>v_ahora)));
end;
$function$;
revoke all on function crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text)
  from public,anon,authenticated,service_role;
grant execute on function crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text) to authenticated;
comment on function crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text) is
  'Cola completa del propio analista: pendientes antes de gestionados; entre grupos, la prioridad SLA; dentro de Vencidas, Sin primer intento y Sin conversación, lo más reciente primero (20/10/2026) y Hoy por hora; avance por actividad vigente en Lima, filtro y pagina anclada por clave. DEFINER porque compone ayudantes privados sin grants API; actor exclusivamente auth.uid().';

-- 5) Gate H3 re-sellado: la huella nueva del núcleo de 5 argumentos (ahora envoltorio) y la fila
--    del núcleo de 6. Igual que antes, llama a los gates anidados (el del equipo sigue en rojo
--    por lo ajeno; ver cabecera). Las huellas son las medidas en el banco con ESTE cuerpo.
CREATE OR REPLACE FUNCTION private.assert_gestion_diaria_pendientes()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_firma text; v_hash text;
begin
  for v_firma, v_hash in select * from (values
    ('private.gestion_diaria_equipo_ambito(uuid)', 'af06caf4d0ea5d392d9c36f069b3501b'),
    ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)', '681d76d982dbba77c2cc556e725ead0a'),
    ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid,boolean)', 'b55e6776ebfdbb2fdd61789ef06b26b6'),
    ('crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid)', 'd69dd41dbd7106283584e7d6b1cc9e1a')
  ) as firmas(firma, huella) loop
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure(v_firma)
      and not p.prosecdef and p.provolatile = 's' and p.proowner = 'postgres'::regrole
      and p.proconfig = array['search_path=""']
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and not has_function_privilege('service_role', p.oid, 'EXECUTE')
      and md5(pg_get_functiondef(p.oid)) = v_hash) then
      raise exception 'H3: contrato, cuerpo o permisos alterados en %', v_firma;
    end if;
  end loop;
  perform private.assert_tareas_pendientes_base();
  perform private.assert_gestion_diaria_equipo();
  return 'OK: pendientes H3 paginados, ámbito canónico compartido, invoker/RLS y referencias mínimas';
end;
$function$;
revoke all on function private.assert_gestion_diaria_pendientes() from public, anon, authenticated, service_role;

do $postflight$
declare v_firma text; v_huella text; v_antes text; v_despues text;
begin
  -- Lo creado es EXACTAMENTE lo ensayado en el banco (identidad completa) y lo que no se toca sigue igual.
  if exists (
    select 1
    from (values
    ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid,boolean)', 'b55e6776ebfdbb2fdd61789ef06b26b6', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)', '681d76d982dbba77c2cc556e725ead0a', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid)', '454617dc48913ab05fc74e46464d5571', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text)', '4dc88038f8664a4ef8318f68151ac7b7', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.assert_gestion_diaria_pendientes()', '81c4ce510bcc0de7eaeffa17c15c67ec', '{postgres=X/postgres}'),
    ('crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid)', 'd69dd41dbd7106283584e7d6b1cc9e1a', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.gestion_diaria_pendientes_v2_fn(uuid,boolean,integer,timestamptz,uuid)', '01a0d2a2a9bf520f4cf442740e791170', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.gestion_diaria_equipo_ambito(uuid)', 'af06caf4d0ea5d392d9c36f069b3501b', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.gestiones_identificar_tareas(jsonb)', 'd4207eb75aec16f8f861c3ffc5a7a6d9', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.gestiones_clientes_identidades(jsonb)', '0023331bba7faf6ea232d572d7ecf2c2', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.rol_crm(uuid)', '99827f3fe2fbc3cfae5668c30015c758', '{postgres=X/postgres,authenticated=X/postgres}')
    ) as d(objeto, md5_def, acl)
    left join pg_catalog.pg_proc p on p.oid = pg_catalog.to_regprocedure(d.objeto)
    where p.oid is null
       or pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) is distinct from d.md5_def
       or p.proowner is distinct from 'postgres'::regrole::oid
       or p.proacl::text is distinct from d.acl
  ) then
    raise exception 'POSTFLIGHT pendientes recientes: algo no quedó con la identidad ensayada (cuerpo, atributos, dueño o ACL)';
  end if;
  -- Atributos: los dos núcleos y la v1 INVOKER y STABLE; la v3 INVOKER y VOLATILE (como la v2); la cola DEFINER y STABLE (como estaba).
  if exists (
    select 1 from (values
      ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid,boolean)', false, 's'),
      ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)', false, 's'),
      ('crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid)', false, 's'),
      ('crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid)', false, 'v'),
      ('crm.gestion_diaria_pendientes_v2_fn(uuid,boolean,integer,timestamptz,uuid)', false, 'v'),
      ('crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text)', true, 's')
    ) as d(objeto, definer, vol)
    join pg_catalog.pg_proc p on p.oid = pg_catalog.to_regprocedure(d.objeto)
    where p.prosecdef is distinct from d.definer or p.provolatile::text is distinct from d.vol or p.proisstrict
       or p.proconfig is distinct from array['search_path=""']::text[]
  ) then
    raise exception 'POSTFLIGHT pendientes recientes: atributos inesperados (DEFINER, volatilidad, STRICT o search_path)';
  end if;
  if pg_catalog.has_function_privilege('anon', 'crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid)', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', 'crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid)', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid,boolean)', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', 'private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid,boolean)', 'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated', 'crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid)', 'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated', 'private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid,boolean)', 'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated', 'crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text)', 'EXECUTE') then
    raise exception 'POSTFLIGHT pendientes recientes: permisos efectivos inesperados';
  end if;
  if coalesce(pg_catalog.strpos(pg_catalog.obj_description('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid,boolean)'::regprocedure, 'pg_proc'), 'SENTIDO'), 0) = 0
     or coalesce(pg_catalog.strpos(pg_catalog.obj_description('crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid)'::regprocedure, 'pg_proc'), 'v3'), 0) = 0
     or coalesce(pg_catalog.strpos(pg_catalog.obj_description('crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text)'::regprocedure, 'pg_proc'), '20/10/2026'), 0) = 0 then
    raise exception 'POSTFLIGHT pendientes recientes: falta un COMMENT ON';
  end if;
  -- Las filas del gate H3, con su misma regla, verdes DESPUÉS (sin sus gates anidados).
  for v_firma, v_huella in select * from (values
    ('private.gestion_diaria_equipo_ambito(uuid)', 'af06caf4d0ea5d392d9c36f069b3501b'),
    ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)', '681d76d982dbba77c2cc556e725ead0a'),
    ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid,boolean)', 'b55e6776ebfdbb2fdd61789ef06b26b6'),
    ('crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid)', 'd69dd41dbd7106283584e7d6b1cc9e1a')
  ) as firmas(firma, huella) loop
    if not exists (select 1 from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure(v_firma)
      and not p.prosecdef and p.provolatile = 's' and p.proowner = 'postgres'::regrole
      and p.proconfig = array['search_path=""']
      and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
      and not pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE')
      and pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) = v_huella) then
      raise exception 'POSTFLIGHT pendientes recientes: la fila % del gate H3 re-sellado no está verde', v_firma;
    end if;
  end loop;
  -- El veredicto del gate H3 es EL MISMO que antes: verde sigue verde; rojo ajeno sigue rojo por lo mismo.
  select veredicto into v_antes from gdp_gate_antes;
  begin
    perform private.assert_gestion_diaria_pendientes();
    v_despues := 'OK';
  exception when others then
    v_despues := sqlerrm;
  end;
  if v_despues is distinct from v_antes then
    raise exception 'POSTFLIGHT pendientes recientes: el gate H3 cambió de veredicto (antes: %; después: %)', v_antes, v_despues;
  end if;
  if v_despues like '%gestion_diaria_pendientes%' then
    raise exception 'POSTFLIGHT pendientes recientes: el gate H3 señala a pendientes (%)', v_despues;
  end if;
  -- Los dos censos quedan EXACTAMENTE como estaban.
  create temporary table gdp_censo_despues on commit drop as
    select 'lc'::text as censo, c.tipo, c.objeto, c.declarada, c.huella_ok
    from private.contadores_crudos_leads_citas() c
    union all
    select 'vigencia', v.tipo, v.objeto, v.declarada, v.huella_ok
    from private.puertas_analista_sin_vigencia() v;
  if exists ((select * from gdp_censo_antes except all select * from gdp_censo_despues)
             union all
             (select * from gdp_censo_despues except all select * from gdp_censo_antes)) then
    raise exception 'POSTFLIGHT pendientes recientes: cambió un censo (analítico o de vigencia)';
  end if;
  -- Ningún cuerpo nuevo nombra una pieza cerrada de F7.
  if exists (select 1 from private.f7_piezas_en_observacion r
             cross join pg_catalog.pg_proc p
             where r.estado in ('observacion', 'cerrada_permanente')
               and p.oid in ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid,boolean)'::regprocedure,
                             'private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)'::regprocedure,
                             'crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid)'::regprocedure,
                             'crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text)'::regprocedure)
               and pg_catalog.lower(pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.regexp_replace(p.prosrc,
                     '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'), '"', '')) ~ r.patron_censo) then
    raise exception 'POSTFLIGHT pendientes recientes: un cuerpo nuevo nombra una pieza cerrada de F7';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;

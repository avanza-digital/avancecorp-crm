ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo de revisión LEVEL 3 — Gestión Diaria: pendientes de lo más reciente a lo más antiguo (20/10/2026)

Eres el revisor secundario (solo análisis, sin herramientas, sin base ni red). Todo lo que necesitas está transcrito abajo.
Tu trabajo es REFUTAR: busca cómo esto falla en producción (fugas entre roles, filas perdidas o repetidas al paginar,
bundles viejos rotos, gates/censos que se ponen en rojo, reversa que no vuelve al byte). Sin hallazgo sin evidencia (cita archivo y línea
o fragmento). Distingue hipótesis de hechos. Responde en español con: VERDICT (APPROVE / APPROVE_WITH_NOTES / CHANGES_REQUESTED),
SUMMARY, FINDINGS P0–P3 (cada uno con evidencia y propuesta), RIESGOS / TEST GAPS, NEXT ACTIONS, CONFIDENCE.

## Contexto y decisión
- Pedido de Miguel: «el orden de los pendientes sale de lo más tiempo vencido hasta lo que tiene menos tiempo vencido y quiero que sea al revés».
  Confirmó el plan: (a) Pendientes del supervisor/gerencia: toda la lista por vence_en DESCENDENTE (Vencidas: lo que venció hace menos arriba;
  Todas: lo de fecha más lejana arriba). (b) Cola del analista («Mi día»): dentro de Vencidas, Sin primer intento y Sin conversación lo más
  reciente primero; «Hoy» sigue por hora; el orden entre grupos no cambia.
- Arquitectura: capa Tablas → Núcleo (`private`) → Puerta (`crm`, expuesto por la API) → Pantalla. Cambiar un contrato de puerta se versiona.
- Hechos medidos en PRODUCCIÓN el 20/10/2026 (md5 de pg_get_functiondef, dueño postgres):
  core5 `a0bde87db9ea86694ba4ee79dc109729` ACL {postgres=X,authenticated=X}; `crm.gestion_diaria_pendientes_fn` `d69dd41d…`; v2 `01a0d2a2…` (plpgsql, VOLATILE);
  `crm.gestion_diaria_cola_trabajo_fn` `c166b286…` (DEFINER, STABLE); gate `private.assert_gestion_diaria_pendientes()` `6aecb25a…` ACL {postgres=X};
  `gestiones_identificar_tareas` `d4207eb7…`; `gestiones_clientes_identidades` `0023331b…` (DEFINER, VOLATILE); `rol_crm` `99827f3f…`.
  Ningún otro objeto de la base cita esas huellas ni nombra `gestion_diaria_cola_trabajo_fn`; no están en las exenciones del censo analítico ni en F7.
  El gate H3 YA está en rojo en producción por una causa ajena: `select private.assert_gestion_diaria_pendientes()` → «El cuerpo de crm.equipo_visible_fn() cambio:
  re-sellar el dia del analista de Gestion Diaria (md5 58bd0554…)» (tarea GUARDIANES-1610, en pausa). Por eso la migración exige «mismo veredicto antes y después».
- Banco Docker propio `crm-banco-pendientes-recientes-20261020` montado desde `supabase db dump --linked` fresco (365 funciones crm / 782 private):
  las 9 huellas de arriba IGUALES a producción. Ciclo: migración OK → repetida se niega (preflight) → reversa OK (core5 vuelve a `a0bde87d…`, cola a `c166b286…`,
  gate a `6aecb25a…`, v3 y core6 desaparecen) → reversa repetida se niega → migración OK → repetida se niega. Huellas ensayadas: core6 `b55e6776…`, core5 `681d76d9…`,
  v3 `454617dc…`, cola `4dc88038…`, gate `81c4ce51…`.
- Prueba sintética (abajo) PASS: v3 = v1 al revés (25 tareas, 17 vencidas, empate exacto de vence_en desempatado por id desc), recorrido 7 por página (4 páginas, sin
  repetir ni saltar, descendente también entre páginas, cada página anterior al cursor), solo vencidas 5 por página (17 filas, todas < pendientes_al), v2 sigue
  ascendente y version 2, mismas claves que la v2, gerencia/sup2/vendedor/coordinador/nadie/anon, 22023 para límite 0/101, cursor a medias y p_recientes_primero null;
  cola: el orden nuevo del día con filas controladas (ayudante sustituido dentro de la transacción), filtro Vencidas paginado, ancla por clave, gerencia 42501, y
  «fuera del ORDER BY el cuerpo de la cola es el vivo al byte» (md5(prosrc) = `2679f956…`). Mutantes de la prueba (deben fallar y fallan): cola con el orden viejo,
  cursor hacia adelante en el núcleo, v3 ascendente.
- Front: vitest 7 archivos / 207 tests PASS sobre lo tocado; `npm run check` completo en curso; e2e Docker de 4 specs en curso.
- Publicación: primero la migración (Miguel, `supabase db query --linked --file` + `migration repair`), después el front con `/release-crm`. Los bundles viejos llaman
  a la v2 (ascendente, v.strictObject con version 1|2) y siguen válidos; el nuevo llama a la v3 (version literal 3).

## Migración `supabase/migrations/20261020214445_crm_gestion_diaria_pendientes_recientes_primero.sql`
```sql
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

```

## Reversa `supabase/scripts/pendientes-recientes-20261020/reversa.sql`
```sql
-- Reversa de 20261020214445 (pendientes de lo más reciente a lo más antiguo). Devuelve la base
-- al estado EXACTO anterior, medido en producción el 20/10/2026: el núcleo H3+G4a de 5
-- argumentos con su cuerpo de 20260928043728 (a0bde87d…), la cola del analista con su ORDER BY
-- de 20260930190028 (c166b286…) y el gate H3 con su sello de G4a (6aecb25a…); retira la v3 y el
-- núcleo de 6 argumentos. No toca tablas, datos ni policies.
--
-- ⚠️ Antes de correrla, el front publicado NO debe llamar a crm.gestion_diaria_pendientes_v3_fn
-- (pasaría a PGRST202): revertir PRIMERO el front (release anterior) y después esto.
-- Un solo mensaje:
--   supabase db query --linked --file supabase/scripts/pendientes-recientes-20261020/reversa.sql
-- y, si la migración estaba registrada:
--   supabase migration repair --status reverted 20261020214445 --linked
begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';
set local search_path = pg_catalog;
lock table private.analitica_leads_citas_exenciones, private.analitica_lc_sello,
  private.analista_vigencia_exenciones in share mode;

create temporary table gdp_rev_censo_antes on commit drop as
  select 'lc'::text as censo, c.tipo, c.objeto, c.declarada, c.huella_ok
  from private.contadores_crudos_leads_citas() c
  union all
  select 'vigencia', v.tipo, v.objeto, v.declarada, v.huella_ok
  from private.puertas_analista_sin_vigencia() v;
create temporary table gdp_rev_gate_antes on commit drop as select ''::text as veredicto;
do $gate_antes$
declare v text;
begin
  begin
    perform private.assert_gestion_diaria_pendientes();
    v := 'OK';
  exception when others then
    v := sqlerrm;
  end;
  update gdp_rev_gate_antes set veredicto = v;
end $gate_antes$;

do $preflight$
begin
  -- Lo que se revierte está instalado EXACTAMENTE como lo dejó la migración (identidad completa).
  if exists (
    select 1
    from (values
    ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid,boolean)', 'b55e6776ebfdbb2fdd61789ef06b26b6', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)', '681d76d982dbba77c2cc556e725ead0a', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid)', '454617dc48913ab05fc74e46464d5571', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text)', '4dc88038f8664a4ef8318f68151ac7b7', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.assert_gestion_diaria_pendientes()', '81c4ce510bcc0de7eaeffa17c15c67ec', '{postgres=X/postgres}'),
    ('crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid)', 'd69dd41dbd7106283584e7d6b1cc9e1a', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.gestion_diaria_pendientes_v2_fn(uuid,boolean,integer,timestamptz,uuid)', '01a0d2a2a9bf520f4cf442740e791170', '{postgres=X/postgres,authenticated=X/postgres}')
    ) as d(objeto, md5_def, acl)
    left join pg_catalog.pg_proc p on p.oid = pg_catalog.to_regprocedure(d.objeto)
    where p.oid is null
       or pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) is distinct from d.md5_def
       or p.proowner is distinct from 'postgres'::regrole::oid
       or p.proacl::text is distinct from d.acl
  ) then
    raise exception 'REVERSA pendientes recientes: la base no está como la dejó 20261020214445; nada coherente que revertir';
  end if;
  -- Nadie más en la base llama a la v3 ni al núcleo de 6 argumentos (pg_depend no ve llamadas entre funciones).
  if exists (
    select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname not in ('pg_catalog', 'information_schema')
      and p.oid <> 'crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid)'::regprocedure
      and pg_catalog.strpos(pg_catalog.lower(p.prosrc), 'gestion_diaria_pendientes_v3_fn') > 0
  ) or exists (
    select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname not in ('pg_catalog', 'information_schema')
      -- El gate H3 lo NOMBRA (sella su huella) pero no lo llama: se re-sella aquí mismo.
      and p.oid not in ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid,boolean)'::regprocedure,
                        'private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)'::regprocedure,
                        'crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid)'::regprocedure,
                        'crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid)'::regprocedure,
                        'private.assert_gestion_diaria_pendientes()'::regprocedure)
      and pg_catalog.strpos(pg_catalog.lower(p.prosrc), 'gestion_diaria_pendientes_core') > 0
  ) then
    raise exception 'REVERSA pendientes recientes: otra función de la base llama a la v3 o al núcleo; retirarla primero';
  end if;
end $preflight$;

drop function crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid);

-- El núcleo de 5 argumentos vuelve a su cuerpo de G4a (20260928043728), al byte.
CREATE OR REPLACE FUNCTION private.gestion_diaria_pendientes_core(
  p_analista_id uuid, p_solo_vencidas boolean, p_limite integer,
  p_despues_de timestamptz, p_despues_id uuid
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
    select b.* from base b
    where (not p_solo_vencidas or b.vence_en < v_ahora)
      and (p_despues_de is null or (b.vence_en, b.id) > (p_despues_de, p_despues_id))
    order by b.vence_en, b.id limit p_limite + 1
  ), pagina as materialized (
    select s.* from sonda s order by s.vence_en, s.id limit p_limite
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
    ) order by p.vence_en, p.id) from pagina p left join crm.leads l on l.id = p.lead_id), '[]'::jsonb),
    'hay_mas', e.hay_mas,
    'siguiente_cursor', case when e.hay_mas then (select jsonb_build_object(
      'despues_de', p.vence_en, 'despues_id', p.id)
      from pagina p order by p.vence_en desc, p.id desc limit 1) else null end
  ), r.invalida into v_respuesta, v_invalida from resumen r cross join estado e;
  if v_invalida then
    raise exception 'No se pudo confirmar la integridad de las tareas' using errcode = '22000';
  end if;
  return v_respuesta;
end;
$function$;
revoke all on function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid) to authenticated;
comment on function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid) is
  'Núcleo H3+G4a: tareas actuales de un analista del ámbito de quien consulta (Supervisión: su árbol; Gerencia: toda la operación visible). INVOKER bajo RLS; cursor vence_en/id; supervisor_id = quien consulta.';

drop function private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid,boolean);

-- La cola del analista vuelve a su ORDER BY de 20260930190028, al byte.
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

  -- Orden completo ANTES del límite. Pendientes conservan la prioridad SLA;
  -- gestionados/programados quedan detrás y el último guardado queda último.
  select coalesce(jsonb_agg(f.value order by
    (f.value->>'estado_trabajo'<>'pendiente'),
    case when f.value->>'estado_trabajo'='pendiente' then
      case f.value->>'grupo' when 'primera_atencion' then 10 when 'tarea_vencida' then 20 when 'tarea_hoy' then 30 else 40 end else 0 end,
    case when f.value->>'estado_trabajo'='pendiente' then (f.value->>'referencia_en')::timestamptz end nulls last,
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
  'Cola completa del propio analista: pendientes antes de gestionados, avance por actividad vigente en Lima, filtro y pagina anclada por clave. DEFINER porque compone ayudantes privados sin grants API; actor exclusivamente auth.uid().';

-- El gate H3 vuelve a su sello de G4a, al byte.
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
    ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)', 'a0bde87db9ea86694ba4ee79dc109729'),
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
declare v_antes text; v_despues text;
begin
  if exists (
    select 1
    from (values
    ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)', 'a0bde87db9ea86694ba4ee79dc109729', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text)', 'c166b286f6577ebf35809dfd708a0ab4', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.assert_gestion_diaria_pendientes()', '6aecb25a8a66e10cc5dcae69afb66281', '{postgres=X/postgres}'),
    ('crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid)', 'd69dd41dbd7106283584e7d6b1cc9e1a', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.gestion_diaria_pendientes_v2_fn(uuid,boolean,integer,timestamptz,uuid)', '01a0d2a2a9bf520f4cf442740e791170', '{postgres=X/postgres,authenticated=X/postgres}')
    ) as d(objeto, md5_def, acl)
    left join pg_catalog.pg_proc p on p.oid = pg_catalog.to_regprocedure(d.objeto)
    where p.oid is null
       or pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) is distinct from d.md5_def
       or p.proowner is distinct from 'postgres'::regrole::oid
       or p.proacl::text is distinct from d.acl
  ) then
    raise exception 'REVERSA pendientes recientes: algo no volvió a su identidad anterior (cuerpo, atributos, dueño o ACL)';
  end if;
  if pg_catalog.to_regprocedure('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid,boolean)') is not null
     or pg_catalog.to_regprocedure('crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid)') is not null then
    raise exception 'REVERSA pendientes recientes: la v3 o el núcleo de 6 argumentos siguen ahí';
  end if;
  if pg_catalog.obj_description('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)'::regprocedure, 'pg_proc')
       is distinct from 'Núcleo H3+G4a: tareas actuales de un analista del ámbito de quien consulta (Supervisión: su árbol; Gerencia: toda la operación visible). INVOKER bajo RLS; cursor vence_en/id; supervisor_id = quien consulta.' then
    raise exception 'REVERSA pendientes recientes: el COMMENT del núcleo no es el de G4a';
  end if;
  select veredicto into v_antes from gdp_rev_gate_antes;
  begin
    perform private.assert_gestion_diaria_pendientes();
    v_despues := 'OK';
  exception when others then
    v_despues := sqlerrm;
  end;
  if v_despues is distinct from v_antes then
    raise exception 'REVERSA pendientes recientes: el gate H3 cambió de veredicto (antes: %; después: %)', v_antes, v_despues;
  end if;
  create temporary table gdp_rev_censo_despues on commit drop as
    select 'lc'::text as censo, c.tipo, c.objeto, c.declarada, c.huella_ok
    from private.contadores_crudos_leads_citas() c
    union all
    select 'vigencia', v.tipo, v.objeto, v.declarada, v.huella_ok
    from private.puertas_analista_sin_vigencia() v;
  if exists ((select * from gdp_rev_censo_antes except all select * from gdp_rev_censo_despues)
             union all
             (select * from gdp_rev_censo_despues except all select * from gdp_rev_censo_antes)) then
    raise exception 'REVERSA pendientes recientes: cambió un censo (analítico o de vigencia)';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;

```

## Prueba sintética `supabase/scripts/pendientes-recientes-20261020/prueba-banco.sql`
```sql
-- Pendientes de lo más reciente a lo más antiguo (20261020214445): prueba sintética en el BANCO
-- Docker propio (esquema de producción sin datos). Siembra sus propios actores y tareas SIN
-- triggers (session_replication_role), lee como authenticated/anon con identidad efectiva y
-- termina SIEMPRE en ROLLBACK. Requiere la migración instalada. Nunca contra producción.
--
--   docker exec -i -e PGPASSWORD=postgres <banco> psql -U supabase_admin -h 127.0.0.1 -d postgres \
--     -v ON_ERROR_STOP=1 -f supabase/scripts/pendientes-recientes-20261020/prueba-banco.sql
begin;
set local statement_timeout = '300s';
set local timezone = 'America/Lima';
do $$ begin
  if shobj_description((select oid from pg_database where datname = current_database()), 'pg_database')
    is distinct from 'BANCO SINTETICO PENDIENTES RECIENTES / sin produccion' then
    raise exception 'PENDIENTES RECIENTES: sólo en el banco sintético (comment on database)';
  end if;
end $$;

create function pg_temp.afirmar(ok boolean, mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'PENDIENTES RECIENTES: %', mensaje; end if; end $$;
create function pg_temp.codigo(comando text) returns text language plpgsql as $$
declare recibido text; begin
  begin execute comando; exception when others then recibido := sqlstate; end;
  return coalesce(recibido, 'ninguno');
end $$;
create function pg_temp.denegada(comando text, codigo text default '42501') returns void language plpgsql as $$
declare recibido text := pg_temp.codigo(comando); begin
  perform pg_temp.afirmar(recibido = codigo, format('error esperado %s; recibido %s: %s', codigo, recibido, comando));
end $$;
-- La imagen del banco lee request.jwt.claim.sub; producción también request.jwt.claims: se fijan las dos.
create function pg_temp.como(actor uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(actor::text, ''), true);
  perform set_config('request.jwt.claims', case when actor is null then '' else json_build_object('sub', actor, 'role', 'authenticated')::text end, true);
end $$;
-- Orden estricto de una página: (vence_en, id) baja (desc) o sube (asc) fila a fila.
create function pg_temp.estricta(items jsonb, descendente boolean) returns boolean language sql as $$
  select coalesce(bool_and(case when descendente then (f.v, f.id) < (f.v_ant, f.id_ant) else (f.v, f.id) > (f.v_ant, f.id_ant) end), true)
  from (
    select (x.value->>'vence_en')::timestamptz v, (x.value->>'id')::uuid id,
      lag((x.value->>'vence_en')::timestamptz) over (order by x.n) v_ant, lag((x.value->>'id')::uuid) over (order by x.n) id_ant
    from jsonb_array_elements(items) with ordinality x(value, n)
  ) f where f.v_ant is not null
$$;
create function pg_temp.ids(items jsonb, al_reves boolean default false) returns uuid[] language sql as $$
  select coalesce(array_agg((x.value->>'id')::uuid order by case when al_reves then -x.n else x.n end), '{}')
  from jsonb_array_elements(items) with ordinality x(value, n)
$$;

-- Actores y datos sintéticos (nombres que cantan que son de banco).
create temporary table pr_actores as select
  'a0000000-0000-4000-8000-000000000001'::uuid sup1, 'a0000000-0000-4000-8000-000000000002'::uuid v1,
  'a0000000-0000-4000-8000-000000000003'::uuid v2, 'a0000000-0000-4000-8000-000000000004'::uuid gerente,
  'a0000000-0000-4000-8000-000000000005'::uuid coordinador, 'a0000000-0000-4000-8000-000000000006'::uuid sup2,
  'a0000000-0000-4000-8000-000000000007'::uuid ajeno, 'a0000000-0000-4000-8000-000000000009'::uuid nadie,
  'b0000000-0000-4000-8000-000000000001'::uuid lead1;
grant select on pr_actores to authenticated, anon;
set local session_replication_role = replica;
insert into auth.users (id, email)
select x.id, x.correo
from pr_actores a cross join lateral (values (a.sup1, 'banco.sup1@pendientes.test'), (a.v1, 'banco.v1@pendientes.test'),
  (a.v2, 'banco.v2@pendientes.test'), (a.gerente, 'banco.gerente@pendientes.test'), (a.coordinador, 'banco.coord@pendientes.test'),
  (a.sup2, 'banco.sup2@pendientes.test'), (a.ajeno, 'banco.ajeno@pendientes.test')) x(id, correo);
insert into public.perfiles (id, nombre_completo, rol, activo, tipo_documento, debe_cambiar_password, titular_distinto, titular_distinto_usd)
select x.id, x.nombre, x.rol, true, 'DNI', false, false, false
from pr_actores a cross join lateral (values (a.sup1, 'BANCO SUP1', 'analista'), (a.v1, 'BANCO V1', 'analista'), (a.v2, 'BANCO V2', 'analista'),
  (a.gerente, 'BANCO GERENTE', 'admin'), (a.coordinador, 'BANCO COORD', 'analista'), (a.sup2, 'BANCO SUP2', 'analista'),
  (a.ajeno, 'BANCO AJENO', 'analista')) x(id, nombre, rol);
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
select x.id, x.rol, x.sup, true
from pr_actores a cross join lateral (values (a.sup1, 'supervisor', null::uuid), (a.sup2, 'supervisor', null), (a.v1, 'vendedor', a.sup1),
  (a.v2, 'vendedor', a.sup1), (a.ajeno, 'vendedor', a.sup2), (a.gerente, 'gerencia', null), (a.coordinador, 'coordinador', null)) x(id, rol, sup);
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, etapa, vendedor_id, activo)
select a.lead1, 'BANCO LEAD DE V1', '+51987650001', 'landing', 50000, 'PEN', 'contactado', a.v1, true from pr_actores a;
-- 15 vencidas (hace 1..15 h), 8 futuras (dentro de 1..8 h) y un EMPATE exacto de vence_en (ids 21 y 22): 25 pendientes.
insert into crm.tareas (id, lead_id, vendedor_id, tipo, titulo, vence_en, creado_por)
select ('c0000000-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid, a.lead1, a.v1, 'llamada', 'BANCO TAREA ' || i,
  case when i <= 15 then now() - make_interval(hours => i) when i <= 23 then now() + make_interval(hours => i - 15) else now() - interval '30 hours' end, a.v1
from pr_actores a cross join generate_series(1, 25) i
union all
select ('c0000000-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid, a.lead1, a.v2, 'llamada', 'BANCO TAREA V2 ' || i, now() - interval '1 hour', a.v2
from pr_actores a cross join generate_series(31, 32) i
union all
select 'c0000000-0000-4000-8000-000000000033'::uuid, a.lead1, a.ajeno, 'llamada', 'BANCO TAREA AJENO', now() - interval '1 hour', a.ajeno
from pr_actores a;
-- Una tarea cerrada y una inactiva de v1: NO entran.
insert into crm.tareas (id, lead_id, vendedor_id, tipo, titulo, vence_en, creado_por, estado, activo)
select ('c0000000-0000-4000-8000-0000000000' || i)::uuid, a.lead1, a.v1, 'llamada', 'BANCO FUERA ' || i, now() - interval '2 hours', a.v1,
  case when i = 41 then 'completada' else 'pendiente' end, i <> 42
from pr_actores a cross join (values (41), (42)) x(i);
set local session_replication_role = origin;
select pg_temp.afirmar((select count(*) from crm.tareas t, pr_actores a where t.vendedor_id = a.v1 and t.activo and t.estado = 'pendiente') = 25, 'siembra: 25 pendientes de v1');

-- El núcleo G4a con otro nombre, acreditado por md5(prosrc) del cuerpo VIVO de producción (medido el 20/10/2026 en el banco a paridad).
create function pg_temp.core_g4a(
  p_analista_id uuid, p_solo_vencidas boolean, p_limite integer,
  p_despues_de timestamptz, p_despues_id uuid
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
    select b.* from base b
    where (not p_solo_vencidas or b.vence_en < v_ahora)
      and (p_despues_de is null or (b.vence_en, b.id) > (p_despues_de, p_despues_id))
    order by b.vence_en, b.id limit p_limite + 1
  ), pagina as materialized (
    select s.* from sonda s order by s.vence_en, s.id limit p_limite
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
    ) order by p.vence_en, p.id) from pagina p left join crm.leads l on l.id = p.lead_id), '[]'::jsonb),
    'hay_mas', e.hay_mas,
    'siguiente_cursor', case when e.hay_mas then (select jsonb_build_object(
      'despues_de', p.vence_en, 'despues_id', p.id)
      from pagina p order by p.vence_en desc, p.id desc limit 1) else null end
  ), r.invalida into v_respuesta, v_invalida from resumen r cross join estado e;
  if v_invalida then
    raise exception 'No se pudo confirmar la integridad de las tareas' using errcode = '22000';
  end if;
  return v_respuesta;
end;
$function$;
select pg_temp.afirmar(md5(prosrc) = '43f946b14f91bfd7da15d384fecdde67', 'la copia G4a de la prueba no es el cuerpo vivo')
from pg_proc where oid = 'pg_temp.core_g4a(uuid,boolean,integer,timestamptz,uuid)'::regprocedure;

-- 1. La v1 y el envoltorio siguen siendo G4a al byte en la respuesta (misma sentencia = mismo statement_timestamp).
select pg_temp.como(sup1) from pr_actores;
set local role authenticated;
select pg_temp.afirmar(pg_temp.core_g4a(v1, false, 25, null, null) = private.gestion_diaria_pendientes_core(v1, false, 25, null, null)
  and pg_temp.core_g4a(v1, true, 7, null, null) = private.gestion_diaria_pendientes_core(v1, true, 7, null, null)
  and pg_temp.core_g4a(v1, false, 100, null, null) = crm.gestion_diaria_pendientes_fn(v1, false, 100)
  and pg_temp.core_g4a(v1, false, 7, null, null) = private.gestion_diaria_pendientes_core(v1, false, 7, null, null, false),
  'ascendente: v1, envoltorio y núcleo con false = G4a') from pr_actores;
select pg_temp.afirmar(pg_temp.codigo(format('select pg_temp.core_g4a(%L,false,25,null,null)', x))
    = pg_temp.codigo(format('select crm.gestion_diaria_pendientes_v3_fn(%L,false,25,null,null)', x)),
  'la v3 da el mismo error que G4a para ' || coalesce(x::text, 'null'))
from pr_actores, unnest(array[ajeno, nadie, null]) x;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_v3_fn(%L, false, 0)', v1), '22023') from pr_actores;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_v3_fn(%L, false, 101)', v1), '22023') from pr_actores;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_v3_fn(%L, false, 25, now(), null)', v1), '22023') from pr_actores;
select pg_temp.denegada(format('select private.gestion_diaria_pendientes_core(%L, false, 25, null, null, null)', v1), '22023') from pr_actores;

-- 2. La v3 en una página: EXACTAMENTE la v1 al revés; version 3; mismo resumen; cursor nulo.
select pg_temp.afirmar(pg_temp.ids(v3->'items') = pg_temp.ids(v1p->'items', true)
  and jsonb_array_length(v3->'items') = 25 and pg_temp.estricta(v3->'items', true)
  and (v3->>'version')::int = 3 and (v1p->>'version')::int = 1
  and v3->'resumen' = v1p->'resumen' and (v3#>>'{resumen,tareas_pendientes}')::int = 25 and (v3#>>'{resumen,tareas_vencidas}')::int = 17
  and (v3->>'hay_mas')::boolean = false and v3->'siguiente_cursor' = 'null'::jsonb
  and v3->>'supervisor_id' = sup1::text and v3->>'analista_id' = v1::text and (v3->>'solo_vencidas')::boolean = false
  and (v3->>'limite')::int = 100 and v3->>'zona' = 'America/Lima',
  'v3 = v1 al revés, version 3, mismo resumen')
from pr_actores a, lateral (select crm.gestion_diaria_pendientes_v3_fn(a.v1, false, 100) v3, crm.gestion_diaria_pendientes_fn(a.v1, false, 100) v1p) q;
-- El empate exacto de vence_en (ids 21 y 22) se desempata por id DESCENDENTE: 22 antes que 21.
select pg_temp.afirmar(array_position(pg_temp.ids(v3->'items'), 'c0000000-0000-4000-8000-000000000022'::uuid) + 1
  = array_position(pg_temp.ids(v3->'items'), 'c0000000-0000-4000-8000-000000000021'::uuid), 'empate: id descendente')
from pr_actores a, lateral (select crm.gestion_diaria_pendientes_v3_fn(a.v1, false, 100) v3) q;
-- Primera fila de «Vencidas»: la que venció hace MENOS (1 h); última: la más vieja (30 h, el empate).
select pg_temp.afirmar(v3->'items'->0->>'titulo' = 'BANCO TAREA 1' and v3->'items'->16->>'titulo' in ('BANCO TAREA 24', 'BANCO TAREA 25')
  and jsonb_array_length(v3->'items') = 17 and (v3->>'solo_vencidas')::boolean,
  'Vencidas: lo que venció hace menos arriba, lo más viejo al final')
from pr_actores a, lateral (select crm.gestion_diaria_pendientes_v3_fn(a.v1, true, 100) v3) q;
-- Primera fila de «Todas»: la de fecha más lejana (dentro de 8 h).
select pg_temp.afirmar(v3->'items'->0->>'titulo' = 'BANCO TAREA 23', 'Todas: lo de fecha más lejana arriba')
from pr_actores a, lateral (select crm.gestion_diaria_pendientes_v3_fn(a.v1, false, 100) v3) q;
-- Los ítems de la v3 llevan las claves de la v2 (identidad) y las mismas claves base que la v1.
select pg_temp.afirmar((select bool_and(i ? 'id' and i ? 'vendedor_id' and i ? 'tipo' and i ? 'titulo' and i ? 'vence_en' and i ? 'estado'
    and i ? 'referencia_tipo' and i ? 'lead_id' and i ? 'lead_nombre' and i->>'referencia_tipo' = 'lead' and i->>'lead_nombre' = 'BANCO LEAD DE V1')
  from jsonb_array_elements(v3->'items') i)
  and (select array_agg(k order by k) from jsonb_object_keys(v3) k) = (select array_agg(k order by k) from jsonb_object_keys(pv2) k)
  and (select array_agg(k order by k) from jsonb_object_keys(v3->'items'->0) k) = (select array_agg(k order by k) from jsonb_object_keys(pv2->'items'->0) k),
  'v3: mismas claves que la v2 (sin claves nuevas)')
from pr_actores a, lateral (select crm.gestion_diaria_pendientes_v3_fn(a.v1, false, 100) v3, crm.gestion_diaria_pendientes_v2_fn(a.v1, false, 100) pv2) q;
-- La v2 sigue ASCENDENTE (bundles publicados) y con version 2.
select pg_temp.afirmar(pg_temp.ids(pv2->'items') = pg_temp.ids(v1p->'items') and pg_temp.estricta(pv2->'items', false) and (pv2->>'version')::int = 2,
  'v2 sigue ascendente y version 2')
from pr_actores a, lateral (select crm.gestion_diaria_pendientes_v2_fn(a.v1, false, 100) pv2, crm.gestion_diaria_pendientes_fn(a.v1, false, 100) v1p) q;
reset role;

-- 3. Recorrido paginado de la v3 (7 por página): 4 páginas, sin repetir ni saltar, descendente también ENTRE páginas,
--    cursor = última fila de la página, y cada página siguiente sólo trae filas anteriores al cursor.
select pg_temp.como(sup1) from pr_actores;
set local role authenticated;
create temporary table pr_ids(id uuid primary key, pagina int, n int, vence_en timestamptz);
do $$ declare p jsonb; c_fecha timestamptz; c_id uuid; n int := 0; fila record; ultima jsonb; begin
  loop
    p := crm.gestion_diaria_pendientes_v3_fn((select v1 from pr_actores), false, 7, c_fecha, c_id);
    n := n + 1;
    perform pg_temp.afirmar(pg_temp.estricta(p->'items', true), format('página %s descendente', n));
    perform pg_temp.afirmar((p->>'version')::int = 3 and (p->>'limite')::int = 7 and jsonb_array_length(p->'items') <= 7, format('página %s: forma', n));
    perform pg_temp.afirmar(c_fecha is null or (select bool_and(((i->>'vence_en')::timestamptz, (i->>'id')::uuid) < (c_fecha, c_id)) from jsonb_array_elements(p->'items') i),
      format('página %s: todo anterior al cursor', n));
    for fila in select x.value, x.ord from jsonb_array_elements(p->'items') with ordinality x(value, ord) loop
      insert into pr_ids values ((fila.value->>'id')::uuid, n, fila.ord, (fila.value->>'vence_en')::timestamptz);
    end loop;
    ultima := p->'items'->(jsonb_array_length(p->'items') - 1);
    exit when not (p->>'hay_mas')::boolean;
    perform pg_temp.afirmar((p->>'hay_mas')::boolean = (jsonb_array_length(p->'items') = 7) and p->'siguiente_cursor' = jsonb_build_object('despues_de', ultima->'vence_en', 'despues_id', ultima->'id'),
      format('página %s: hay_mas sólo con página llena y cursor = última fila', n));
    c_fecha := (p#>>'{siguiente_cursor,despues_de}')::timestamptz; c_id := (p#>>'{siguiente_cursor,despues_id}')::uuid;
    perform pg_temp.afirmar(n < 10, 'el cursor debe terminar');
  end loop;
  perform pg_temp.afirmar(n = 4 and (select count(*) from pr_ids) = 25, format('recorrido completo (%s páginas, %s filas)', n, (select count(*) from pr_ids)));
end $$;
select pg_temp.afirmar(bool_and(ok), 'descendente entre páginas') from (
  select (vence_en, id) < (lag(vence_en) over w, lag(id) over w) ok from pr_ids window w as (order by pagina, n)) x where ok is not null;
reset role;
select pg_temp.afirmar((select count(*) from pr_ids) = count(*) and bool_and(t.id in (select id from pr_ids)),
  'el recorrido es exactamente el conjunto de pendientes activas de v1')
from pr_actores a, crm.tareas t where t.vendedor_id = a.v1 and t.activo and t.estado = 'pendiente';
-- Solo vencidas, paginado (5 por página): 17 filas en 4 páginas, todas anteriores a pendientes_al y descendentes.
select pg_temp.como(sup1) from pr_actores;
set local role authenticated;
do $$ declare p jsonb; c_fecha timestamptz; c_id uuid; n int := 0; filas int := 0; begin
  loop
    p := crm.gestion_diaria_pendientes_v3_fn((select v1 from pr_actores), true, 5, c_fecha, c_id);
    n := n + 1; filas := filas + jsonb_array_length(p->'items');
    perform pg_temp.afirmar(pg_temp.estricta(p->'items', true) and (p->>'solo_vencidas')::boolean
      and (select bool_and((i->>'vence_en')::timestamptz < (p->>'pendientes_al')::timestamptz) from jsonb_array_elements(p->'items') i),
      format('vencidas página %s', n));
    perform pg_temp.afirmar((p#>>'{resumen,tareas_vencidas}')::int = 17 and (p#>>'{resumen,tareas_pendientes}')::int = 25, 'vencidas: resumen previo al filtro');
    exit when not (p->>'hay_mas')::boolean;
    c_fecha := (p#>>'{siguiente_cursor,despues_de}')::timestamptz; c_id := (p#>>'{siguiente_cursor,despues_id}')::uuid;
    perform pg_temp.afirmar(n < 10, 'el cursor debe terminar');
  end loop;
  perform pg_temp.afirmar(n = 4 and filas = 17, format('vencidas: %s páginas, %s filas', n, filas));
end $$;
reset role;

-- 4. Quién puede: Gerencia (toda la operación, supervisor_id = quien consulta); sup2 no lee a v1; analista, coordinación,
--    uid sin rol y sin identidad: 42501 en la v3 y en el núcleo de 6; anon: sin EXECUTE.
select pg_temp.como(gerente) from pr_actores;
set local role authenticated;
select pg_temp.afirmar(p->>'supervisor_id' = gerente::text and p->>'analista_id' = v1::text and jsonb_array_length(p->'items') = 25 and pg_temp.estricta(p->'items', true),
  'Gerencia lee a v1 en la v3') from pr_actores, lateral (select crm.gestion_diaria_pendientes_v3_fn(v1, false, 100) p) q;
select pg_temp.afirmar(jsonb_array_length(p->'items') = 1 and p->'items'->0->>'vendedor_id' = ajeno::text, 'Gerencia lee al ajeno')
from pr_actores, lateral (select crm.gestion_diaria_pendientes_v3_fn(ajeno, false, 100) p) q;
reset role;
select pg_temp.como(sup2) from pr_actores;
set local role authenticated;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_v3_fn(%L)', v1)) from pr_actores;
select pg_temp.afirmar(jsonb_array_length(p->'items') = 1 and p->'items'->0->>'titulo' = 'BANCO TAREA AJENO' and p->>'supervisor_id' = sup2::text, 'sup2 lee a su analista')
from pr_actores, lateral (select crm.gestion_diaria_pendientes_v3_fn(ajeno, false, 100) p) q;
reset role;
do $$ declare actor uuid; begin
  for actor in select unnest(array[v1, v2, coordinador, nadie, null]) from pr_actores loop
    perform pg_temp.como(actor);
    execute 'set local role authenticated';
    perform pg_temp.denegada(format('select crm.gestion_diaria_pendientes_v3_fn(%L)', (select v1 from pr_actores)));
    perform pg_temp.denegada(format('select private.gestion_diaria_pendientes_core(%L,false,25,null,null,true)', (select v1 from pr_actores)));
    execute 'reset role';
  end loop;
end $$;
select pg_temp.afirmar(not has_function_privilege('anon', 'crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid)', 'EXECUTE')
  and not has_function_privilege('service_role', 'crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid,boolean)', 'EXECUTE')
  and has_function_privilege('authenticated', 'crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid)', 'EXECUTE'),
  'ACL: anon y service_role sin EXECUTE; authenticated con EXECUTE');
select pg_temp.como(sup1) from pr_actores;
set local role anon;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_v3_fn(%L)', v1)) from pr_actores;
select pg_temp.denegada(format('select private.gestion_diaria_pendientes_core(%L,false,25,null,null,true)', v1)) from pr_actores;
reset role;

-- 5. La cola del analista: SOLO cambió el ORDER BY (el resto del cuerpo, al byte) y el orden nuevo es el pedido.
select pg_temp.afirmar(md5(replace(replace(p.prosrc,
$nuevo$  -- Orden completo ANTES del límite. Pendientes conservan la prioridad SLA entre grupos;
  -- dentro de Vencidas, Sin primer intento y Sin conversación va primero lo más reciente
  -- (Miguel, 20/10/2026) y Hoy sigue por hora; gestionados/programados quedan detrás y el
  -- último guardado queda último.
$nuevo$, $viejo$  -- Orden completo ANTES del límite. Pendientes conservan la prioridad SLA;
  -- gestionados/programados quedan detrás y el último guardado queda último.
$viejo$),
$nuevo$    case when f.value->>'estado_trabajo'='pendiente' and f.value->>'grupo'='tarea_hoy' then (f.value->>'referencia_en')::timestamptz end nulls last,
    case when f.value->>'estado_trabajo'='pendiente' and f.value->>'grupo'<>'tarea_hoy' then (f.value->>'referencia_en')::timestamptz end desc nulls last,
$nuevo$, $viejo$    case when f.value->>'estado_trabajo'='pendiente' then (f.value->>'referencia_en')::timestamptz end nulls last,
$viejo$)) = '2679f956c5bb271d3aac847b84690592', 'cola: fuera del ORDER BY, el cuerpo es el vivo al byte')
from pg_proc p where p.oid = 'crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text)'::regprocedure;
-- Filas controladas: se sustituye el ayudante privado SOLO dentro de esta transacción (rollback al final).
create or replace function private.gestion_diaria_cola_filas(p_actor uuid, p_rol text, p_ahora timestamptz)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_array(
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000a1','grupo','primera_atencion','estado_trabajo','pendiente','referencia_en',p_ahora - interval '2 days','ultima_gestion',null,'proxima_tarea',null),
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000a2','grupo','primera_atencion','estado_trabajo','pendiente','referencia_en',p_ahora + interval '1 hour','ultima_gestion',null,'proxima_tarea',null),
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000a3','grupo','primera_atencion','estado_trabajo','pendiente','referencia_en',null,'ultima_gestion',null,'proxima_tarea',null),
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000b1','grupo','tarea_vencida','estado_trabajo','pendiente','referencia_en',p_ahora - interval '5 days','ultima_gestion',null,'proxima_tarea',null),
    jsonb_build_object('tipo','cliente','clave','tarea:00000000-0000-4000-8000-0000000000b2','grupo','tarea_vencida','estado_trabajo','pendiente','referencia_en',p_ahora - interval '1 hour','ultima_gestion',null,'proxima_tarea',null),
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000b3','grupo','tarea_vencida','estado_trabajo','pendiente','referencia_en',p_ahora - interval '1 hour','ultima_gestion',null,'proxima_tarea',null),
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000c1','grupo','tarea_hoy','estado_trabajo','pendiente','referencia_en',p_ahora + interval '6 hours','ultima_gestion',null,'proxima_tarea',null),
    jsonb_build_object('tipo','cliente','clave','tarea:00000000-0000-4000-8000-0000000000c2','grupo','tarea_hoy','estado_trabajo','pendiente','referencia_en',p_ahora + interval '1 hour','ultima_gestion',null,'proxima_tarea',null),
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000d1','grupo','sin_conversacion','estado_trabajo','pendiente','referencia_en',p_ahora - interval '20 days','ultima_gestion',null,'proxima_tarea',null),
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000d2','grupo','sin_conversacion','estado_trabajo','pendiente','referencia_en',p_ahora - interval '8 days','ultima_gestion',null,'proxima_tarea',null),
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000e1','grupo','tarea_vencida','estado_trabajo','gestionado','referencia_en',p_ahora - interval '1 hour','ultima_gestion',jsonb_build_object('en',p_ahora - interval '10 minutes'),'proxima_tarea',null),
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000e2','grupo','primera_atencion','estado_trabajo','gestionado','referencia_en',p_ahora - interval '1 hour','ultima_gestion',jsonb_build_object('en',p_ahora - interval '30 minutes'),'proxima_tarea',null),
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000e3','grupo','tarea_hoy','estado_trabajo','programado','referencia_en',p_ahora + interval '3 hours','ultima_gestion',null,'proxima_tarea',jsonb_build_object('vence_en',p_ahora + interval '3 hours'))
  )
$$;
select pg_temp.como(v1) from pr_actores;
set local role authenticated;
select pg_temp.afirmar((select array_agg(i->>'clave' order by n) from jsonb_array_elements(c->'items') with ordinality x(i, n)) = array[
    -- Sin primer intento: lo más reciente primero (la referencia futura, luego la de hace 2 días), sin referencia al final.
    'lead:00000000-0000-4000-8000-0000000000a2', 'lead:00000000-0000-4000-8000-0000000000a1', 'lead:00000000-0000-4000-8000-0000000000a3',
    -- Vencidas: lo que venció hace menos primero; empate exacto por clave (collate "C": «lead:» < «tarea:»); la de hace 5 días al final.
    'lead:00000000-0000-4000-8000-0000000000b3', 'tarea:00000000-0000-4000-8000-0000000000b2', 'lead:00000000-0000-4000-8000-0000000000b1',
    -- Hoy: por hora, lo más próximo primero.
    'tarea:00000000-0000-4000-8000-0000000000c2', 'lead:00000000-0000-4000-8000-0000000000c1',
    -- Sin conversación: lo más reciente primero (8 días antes que 20).
    'lead:00000000-0000-4000-8000-0000000000d2', 'lead:00000000-0000-4000-8000-0000000000d1',
    -- Gestionados/programados detrás, el último guardado al final (como antes).
    'lead:00000000-0000-4000-8000-0000000000e3', 'lead:00000000-0000-4000-8000-0000000000e2', 'lead:00000000-0000-4000-8000-0000000000e1']
  and (c->>'total')::int = 13 and c->>'elegido' = 'lead:00000000-0000-4000-8000-0000000000a2' and c->>'siguiente' = 'lead:00000000-0000-4000-8000-0000000000a1'
  and (c#>>'{totales,todo,pendientes}')::int = 10 and (c->>'vuelta_completa')::boolean = false,
  'cola: el orden nuevo del día')
from pr_actores a, lateral (select crm.gestion_diaria_cola_trabajo_fn('todo', 0, 200) c) q;
-- Filtro «Vencidas», 2 por página: la primera página trae las dos más recientes; elegida la primera, «siguiente» es la segunda.
select pg_temp.afirmar((select array_agg(i->>'clave' order by n) from jsonb_array_elements(c->'items') with ordinality x(i, n))
    = array['lead:00000000-0000-4000-8000-0000000000b3', 'tarea:00000000-0000-4000-8000-0000000000b2']
  and (c->>'total')::int = 4 and c->>'filtro' = 'tarea_vencida' and c->>'elegido' = 'lead:00000000-0000-4000-8000-0000000000b3'
  and c->>'siguiente' = 'tarea:00000000-0000-4000-8000-0000000000b2',
  'cola: filtro Vencidas paginado con el orden nuevo')
from pr_actores a, lateral (select crm.gestion_diaria_cola_trabajo_fn('tarea_vencida', 0, 2) c) q;
-- Anclar por clave sigue funcionando: la página de la vencida más vieja es la segunda (posición 2 → página 1 con límite 2).
select pg_temp.afirmar((c->>'pagina')::int = 1 and c->>'elegido' = 'lead:00000000-0000-4000-8000-0000000000b1' and c->>'siguiente' = 'lead:00000000-0000-4000-8000-0000000000b3',
  'cola: ancla por clave con el orden nuevo')
from pr_actores a, lateral (select crm.gestion_diaria_cola_trabajo_fn('tarea_vencida', 0, 2, 'lead:00000000-0000-4000-8000-0000000000b1') c) q;
reset role;
select pg_temp.como(gerente) from pr_actores;
set local role authenticated;
select pg_temp.denegada('select crm.gestion_diaria_cola_trabajo_fn()');
reset role;

-- 6. El gate H3: sus filas de pendientes en verde con el sello nuevo (su veredicto completo depende de gates ajenos; se muestra).
do $$ declare v_firma text; v_hash text; v text; begin
  for v_firma, v_hash in select * from (values
    ('private.gestion_diaria_equipo_ambito(uuid)', 'af06caf4d0ea5d392d9c36f069b3501b'),
    ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)', '681d76d982dbba77c2cc556e725ead0a'),
    ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid,boolean)', 'b55e6776ebfdbb2fdd61789ef06b26b6'),
    ('crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid)', 'd69dd41dbd7106283584e7d6b1cc9e1a')
  ) as firmas(firma, huella) loop
    perform pg_temp.afirmar(exists (select 1 from pg_proc p where p.oid = to_regprocedure(v_firma)
      and not p.prosecdef and p.provolatile = 's' and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']
      and has_function_privilege('authenticated', p.oid, 'EXECUTE') and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and not has_function_privilege('service_role', p.oid, 'EXECUTE') and md5(pg_get_functiondef(p.oid)) = v_hash), 'gate H3 fila ' || v_firma);
  end loop;
  begin perform private.assert_gestion_diaria_pendientes(); v := 'OK'; exception when others then v := sqlerrm; end;
  raise notice 'veredicto del gate H3 en el banco: %', v;
  perform pg_temp.afirmar(v not like '%gestion_diaria_pendientes%', 'el gate H3 no señala a pendientes');
end $$;

select 'PENDIENTES_RECIENTES_OK' as resultado;
rollback;

```

## Diff del front y de la matriz RLS (`git diff` sobre `main` f9f755c0)
```diff
diff --git a/CRM-Avance-Corp/app/e2e/cola-v3-clientes-supervision.spec.ts b/CRM-Avance-Corp/app/e2e/cola-v3-clientes-supervision.spec.ts
index 58d35696..af7651ff 100644
--- a/CRM-Avance-Corp/app/e2e/cola-v3-clientes-supervision.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/cola-v3-clientes-supervision.spec.ts
@@ -4,7 +4,8 @@
 // argumentos y aplica la regla del servidor para clientes (`p_etapa` los
 // excluye; `p_analista_id` filtra a su responsable). No acredita RLS: eso lo
 // hace el gate del banco. Hoy abre ahora el detalle por analista mediante
-// `gestion_diaria_pendientes_v2_fn`; se conserva la identidad del cliente.
+// `gestion_diaria_pendientes_v3_fn` (de lo más reciente a lo más antiguo); se
+// conserva la identidad del cliente.
 import { expect, test, type Page } from '@playwright/test'
 import { loginReal, UID } from './_helpers'
 import { montarLecturasHoySupervisor } from './_hoy-supervisor'
@@ -80,7 +81,7 @@ test('Hoy del supervisor: la tarea del cliente dice que es de un cliente y abre
       supervisor_id: UID, generado_en: corte, pendientes_al: corte } })
   })
   const pedidos: Record<string, unknown>[] = []
-  await page.route('**/rest/v1/rpc/gestion_diaria_pendientes_v2_fn', async route => {
+  await page.route('**/rest/v1/rpc/gestion_diaria_pendientes_v3_fn', async route => {
     const pedido = route.request().postDataJSON()
     pedidos.push(pedido)
     const propias = CLIENTES.filter(c => c.responsable === pedido.p_analista_id)
@@ -90,8 +91,8 @@ test('Hoy del supervisor: la tarea del cliente dice que es de un cliente y abre
       referencia_tipo: c.inversionista_id ? 'postventa' : 'perfil', lead_id: null, lead_nombre: null,
       sujeto_tipo: c.inversionista_id ? 'inversionista' : 'perfil', sujeto_id: c.inversionista_id ?? c.perfil_id,
       sujeto_nombre: c.nombre, inversionista_id: c.inversionista_id, perfil_id: c.perfil_id, identidad_visible: true,
-    }))
-    await route.fulfill({ json: paginaPendientes(items, { version: 2, supervisor_id: UID,
+    })).sort((a, b) => b.vence_en.localeCompare(a.vence_en) || b.id.localeCompare(a.id)) // como la v3: de lo más reciente a lo más antiguo
+    await route.fulfill({ json: paginaPendientes(items, { version: 3, supervisor_id: UID,
       analista_id: pedido.p_analista_id, solo_vencidas: pedido.p_solo_vencidas, limite: pedido.p_limite,
       generado_en: corte, pendientes_al: corte,
       resumen: { tareas_pendientes: propias.length, tareas_vencidas: propias.filter(c => c.vencida).length } }) })
diff --git a/CRM-Avance-Corp/app/e2e/gestion-diaria-horizontal-h5.spec.ts b/CRM-Avance-Corp/app/e2e/gestion-diaria-horizontal-h5.spec.ts
index 9c1f972c..5d12f9b5 100644
--- a/CRM-Avance-Corp/app/e2e/gestion-diaria-horizontal-h5.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/gestion-diaria-horizontal-h5.spec.ts
@@ -55,7 +55,7 @@ test('H5: consultas iguales con 1 y 32 analistas, bajo demanda y panel estable',
       return responderRegistroV2(route, { json: { version: 1, zona: 'America/Lima', desde: dia, hasta: dia,
         generado_en: instante, limite: 26, items: [] } })
     })
-    await page.route('**/rest/v1/rpc/gestion_diaria_pendientes_v2_fn', route => {
+    await page.route('**/rest/v1/rpc/gestion_diaria_pendientes_v3_fn', route => {
       lecturas.pendientes++
       return route.fulfill({ status: 500, json: { code: 'XX000', message: 'No se debe consultar una pestaña no visitada' } })
     })
diff --git a/CRM-Avance-Corp/app/e2e/gestion-diaria-pendientes.spec.ts b/CRM-Avance-Corp/app/e2e/gestion-diaria-pendientes.spec.ts
index 860bd089..0e729d77 100644
--- a/CRM-Avance-Corp/app/e2e/gestion-diaria-pendientes.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/gestion-diaria-pendientes.spec.ts
@@ -22,16 +22,18 @@ async function preparar(page: Page) {
       creado_por:analista,autor_nombre:'ANA H3',creado_en:`${dia}T15:0${5-i}:00Z`}))
     return responderRegistroV2(route, {json:{version:1,zona:'America/Lima',desde:dia,hasta:dia,limite:26,generado_en:new Date().toISOString(),items}})
   })
-  await page.route('**/rest/v1/rpc/gestion_diaria_pendientes_v2_fn',route=>{
+  await page.route('**/rest/v1/rpc/gestion_diaria_pendientes_v3_fn',route=>{
     estado.consultas++
     if(estado.error) return route.fulfill({status:estado.error==='42501'?403:400,json:{code:estado.error,message:'Error de prueba'}})
     const pedido=route.request().postDataJSON();expect(pedido.p_analista_id).toBe(analista)
+    // Como la v3: de lo más reciente a lo más antiguo (las 25 futuras, ids 64…40, y luego las 30 vencidas de hoy, ids 39…10);
+    // el cursor avanza hacia atrás. Las dos sin persona visible van en la primera página.
     const todas=Array.from({length:55},(_,i)=>tareaPendiente(10+i,{vendedor_id:analista,
       vence_en:i<30?`${dia}T00:00:00Z`:`2099-01-01T00:00:00Z`,lead_id:lead.id,lead_nombre:lead.nombre_completo,
-      ...(i===1?{referencia_tipo:'perfil',lead_id:null,lead_nombre:null}:i===2?{referencia_tipo:'postventa',lead_id:null,lead_nombre:null}:{}),
-    }))
-    const despues=pedido.p_despues_id?Number(pedido.p_despues_id.slice(-12)):0
-    const posibles=todas.filter(t=>(!pedido.p_solo_vencidas||Number(t.id.slice(-12))<40)&&Number(t.id.slice(-12))>despues)
+      ...(i===53?{referencia_tipo:'perfil',lead_id:null,lead_nombre:null}:i===54?{referencia_tipo:'postventa',lead_id:null,lead_nombre:null}:{}),
+    })).reverse()
+    const despues=pedido.p_despues_id?Number(pedido.p_despues_id.slice(-12)):Infinity
+    const posibles=todas.filter(t=>(!pedido.p_solo_vencidas||Number(t.id.slice(-12))<40)&&Number(t.id.slice(-12))<despues)
     const items=posibles.slice(0,25),ultimo=items.at(-1)!,hayMas=posibles.length>25,ahora=new Date().toISOString()
     return route.fulfill({json:paginaPendientes(items,{supervisor_id:UID,analista_id:analista,solo_vencidas:pedido.p_solo_vencidas,
       generado_en:ahora,pendientes_al:ahora,resumen:{tareas_pendientes:55,tareas_vencidas:30},hay_mas:hayMas,
diff --git a/CRM-Avance-Corp/app/e2e/gestion-diaria-vuelta.spec.ts b/CRM-Avance-Corp/app/e2e/gestion-diaria-vuelta.spec.ts
index c540f0cf..ffecf048 100644
--- a/CRM-Avance-Corp/app/e2e/gestion-diaria-vuelta.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/gestion-diaria-vuelta.spec.ts
@@ -23,8 +23,9 @@ test('vuelta real: guardar, error recuperable, siguiente entre páginas y progre
     const pedido: PedidoColaTrabajo = { filtro: args.p_filtro, pagina: args.p_pagina, limite: args.p_limite, elegido: args.p_elegido ?? null }
     pedidos.push(pedido)
     await new Promise((resolve) => setTimeout(resolve, 80))
+    // Sin conversación va de lo más reciente a lo más antiguo (20/10/2026): COLA 01 es la más reciente.
     const filas = leads.map((lead, i) => ({ ...muestra.items[0], clave: `lead:${lead.id}`, lead_id: lead.id,
-      nombre_completo: lead.nombre_completo, referencia_en: new Date(Date.parse(instante) - (40 * 1440 - i) * 60_000).toISOString(),
+      nombre_completo: lead.nombre_completo, referencia_en: new Date(Date.parse(instante) - (40 * 1440 + i) * 60_000).toISOString(),
       senal: { ...muestra.items[0]!.senal, lead_id: lead.id, nombre_completo: lead.nombre_completo },
       estado_trabajo: gestionadas.has(lead.id) ? 'gestionado' : 'pendiente', proxima_tarea: null,
       ultima_gestion: gestionadas.has(lead.id) ? { actividad_id: lead.id, resultado: 'no_contesto', en: gestionadas.get(lead.id), tarea_id: null, etapa_anterior: 'contactado' } : null,
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/pendientes-supervisor.test.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/pendientes-supervisor.test.tsx
index 899c9fee..9376e896 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/pendientes-supervisor.test.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/pendientes-supervisor.test.tsx
@@ -45,9 +45,10 @@ describe('Lista útil de pendientes', () => {
     expect(dobles.recargar).toHaveBeenCalledOnce(); expect(filtro).toHaveFocus(); expect(filtro).toHaveAttribute('aria-pressed','true')
   })
   it('como el resumen: dos cuadros con número que filtran, la vencida se marca y el título no repite el lead (Miguel, 27/09)', () => {
+    // Como llega de la v3: de lo más reciente a lo más antiguo.
     dobles.lista.items = [
-      tareaPendiente(20, { tipo: 'whatsapp', titulo: 'WhatsApp — LEAD VISIBLE', vence_en: '2026-09-23T16:00:00.000001+00:00' }),
       tareaPendiente(21, { titulo: 'Responder propuesta — Lead visible', vence_en: '2026-09-23T18:00:00.000001+00:00' }),
+      tareaPendiente(20, { tipo: 'whatsapp', titulo: 'WhatsApp — LEAD VISIBLE', vence_en: '2026-09-23T16:00:00.000001+00:00' }),
     ]
     dobles.lista.pagina = paginaPendientes(dobles.lista.items, { resumen: { tareas_pendientes: 5, tareas_vencidas: 2 } })
     render(<PendientesSupervisor {...props} />)
@@ -56,12 +57,12 @@ describe('Lista útil de pendientes', () => {
     fireEvent.click(within(filtro).getByRole('button', { name: /^Vencidas 2$/ }))
     expect(dobles.hook).toHaveBeenLastCalledWith(props.dia, props.analista, true, true, 0)
     const [primera, segunda] = within(screen.getByRole('list', { name: 'Lista de tareas pendientes' })).getAllByRole('listitem')
-    // Vence antes del corte de la consulta (17:00 UTC): vencida. La otra, después: no.
-    expect(within(primera!).getByText('Vencida')).toBeVisible()
-    expect(within(segunda!).queryByText('Vencida')).not.toBeInTheDocument()
+    // La segunda vence antes del corte de la consulta (17:00 UTC): vencida. La primera, después: no.
+    expect(within(segunda!).getByText('Vencida')).toBeVisible()
+    expect(within(primera!).queryByText('Vencida')).not.toBeInTheDocument()
     // «WhatsApp — LEAD VISIBLE» ya lo dicen el tipo y el lead: sin título repetido.
-    expect(within(primera!).queryByText(/WhatsApp —/)).not.toBeInTheDocument()
-    expect(within(segunda!).getByText('Responder propuesta')).toBeVisible()
+    expect(within(segunda!).queryByText(/WhatsApp —/)).not.toBeInTheDocument()
+    expect(within(primera!).getByText('Responder propuesta')).toBeVisible()
     expect(screen.getByRole('heading', { name: 'Pendientes de ANA' })).toBeInTheDocument()
   })
   it('las señales de leads solo aparecen con número confirmado mayor que cero', () => {
diff --git a/CRM-Avance-Corp/app/src/components/gestion-diaria/pendientes-supervisor.tsx b/CRM-Avance-Corp/app/src/components/gestion-diaria/pendientes-supervisor.tsx
index cff7f777..11816a28 100644
--- a/CRM-Avance-Corp/app/src/components/gestion-diaria/pendientes-supervisor.tsx
+++ b/CRM-Avance-Corp/app/src/components/gestion-diaria/pendientes-supervisor.tsx
@@ -2,7 +2,8 @@
 // 27/09/2026: «demasiado texto y no se entiende»): dos cuadros que SON el
 // filtro (cada número abre su lista), las señales de leads solo si hay algo que
 // decir, y filas limpias —hora, tipo, lead y «Vencida»—. Los estados que no se
-// pueden confirmar se siguen diciendo, en una línea.
+// pueden confirmar se siguen diciendo, en una línea. El orden lo pone el servidor
+// (v3, 20/10/2026): de lo más reciente a lo más antiguo, también al cargar más.
 import { useEffect, useEffectEvent, useId, useLayoutEffect, useRef, useState } from 'react'
 import { Check } from 'lucide-react'
 import { usePendientesSupervisor } from '@/data/gestion-diaria-pendientes-queries'
diff --git a/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-api.test.ts b/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-api.test.ts
index 2630db74..653e5a35 100644
--- a/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-api.test.ts
+++ b/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-api.test.ts
@@ -13,7 +13,7 @@ describe('Puerta de pendientes', () => {
   it('pide sólo el ámbito y límite; transmite abort; no usa la cartera del navegador', async () => {
     const signal = new AbortController().signal
     expect(await listarPendientesSupervisor(pedidoPendientes, signal)).toEqual(dobles.data)
-    expect(dobles.rpc).toHaveBeenCalledWith('gestion_diaria_pendientes_v2_fn', { p_analista_id: pedidoPendientes.analista, p_solo_vencidas: false, p_limite: 25 })
+    expect(dobles.rpc).toHaveBeenCalledWith('gestion_diaria_pendientes_v3_fn', { p_analista_id: pedidoPendientes.analista, p_solo_vencidas: false, p_limite: 25 })
     expect(dobles.abort).toHaveBeenCalledWith(signal)
   })
   it.each(['42501', 'PGRST202', '22023', 'XX000'])('preserva %s sin convertirlo en vacío', async code => {
diff --git a/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-api.ts b/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-api.ts
index 4f8eadbb..4eb2dc9e 100644
--- a/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-api.ts
+++ b/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-api.ts
@@ -3,9 +3,10 @@ import { validarPaginaPendientes, type PedidoPendientes, type PaginaPendientes }
 import { CrmApiError } from './crm-api'
 import { soloPresentes } from './argumentos-rpc'
 
+/** La v3 (20/10/2026): de lo más reciente a lo más antiguo; la v2 (ascendente) queda para los bundles publicados. */
 export async function listarPendientesSupervisor(pedido: PedidoPendientes, signal?: AbortSignal): Promise<PaginaPendientes> {
   if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
-  let consulta = sb.schema('crm').rpc('gestion_diaria_pendientes_v2_fn', {
+  let consulta = sb.schema('crm').rpc('gestion_diaria_pendientes_v3_fn', {
     p_analista_id: pedido.analista, p_solo_vencidas: pedido.soloVencidas, p_limite: pedido.limite,
     ...soloPresentes({ p_despues_de: pedido.cursor?.despues_de, p_despues_id: pedido.cursor?.despues_id }),
   })
diff --git a/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-queries.test.tsx b/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-queries.test.tsx
index 1394f2a9..918fdaa6 100644
--- a/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-queries.test.tsx
+++ b/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-queries.test.tsx
@@ -19,8 +19,9 @@ beforeEach(() => {
   vi.clearAllMocks(); cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } }); dobles.vendedores = []
   dobles.yo = { id: pedidoPendientes.supervisor, rol: 'supervisor', demo: false } as Yo
   dobles.listar.mockImplementation(async (p: PedidoPendientes) => {
-    const inicio = p.cursor ? Number(p.cursor.despues_id.slice(-12)) + 1 : 10
-    const items = Array.from({ length: 25 }, (_, i) => tareaPendiente(inicio + i))
+    // Como la v3: de lo más reciente a lo más antiguo (aquí, mismo vence_en e ids descendentes) y cursor hacia atrás.
+    const inicio = p.cursor ? Number(p.cursor.despues_id.slice(-12)) - 1 : 100
+    const items = Array.from({ length: 25 }, (_, i) => tareaPendiente(inicio - i))
     return paginaPendientes(items, { solo_vencidas: p.soloVencidas, resumen: { tareas_pendientes: 100, tareas_vencidas: 100 }, hay_mas: true,
       siguiente_cursor: { despues_de: items[24]!.vence_en, despues_id: items[24]!.id } })
   })
diff --git a/CRM-Avance-Corp/app/src/lib/database.types.ts b/CRM-Avance-Corp/app/src/lib/database.types.ts
index dd29df38..f7dd6fb7 100644
--- a/CRM-Avance-Corp/app/src/lib/database.types.ts
+++ b/CRM-Avance-Corp/app/src/lib/database.types.ts
@@ -7102,6 +7102,16 @@ export type Database = {
         }
         Returns: Json
       }
+      gestion_diaria_pendientes_v3_fn: {
+        Args: {
+          p_analista_id: string
+          p_despues_de?: string
+          p_despues_id?: string
+          p_limite?: number
+          p_solo_vencidas?: boolean
+        }
+        Returns: Json
+      }
       gestion_diaria_presentar_corte: {
         Args: { p_alerta_id: string; p_solicitud_id: string }
         Returns: Json
diff --git a/CRM-Avance-Corp/app/src/lib/gestion-diaria-analista.test.ts b/CRM-Avance-Corp/app/src/lib/gestion-diaria-analista.test.ts
index 18565ba0..5537f369 100644
--- a/CRM-Avance-Corp/app/src/lib/gestion-diaria-analista.test.ts
+++ b/CRM-Avance-Corp/app/src/lib/gestion-diaria-analista.test.ts
@@ -48,13 +48,27 @@ describe('ordenarColaDiaria', () => {
     expect(ordenarColaDiaria(cola, cartera).map((f) => f.lead_id)).toEqual(['nuevo', 'vencida', 'hoy', 'abandonado'])
   })
 
-  it('dentro de un grupo manda lo más antiguo, y lo que no trae referencia va al final', () => {
+  it('dentro de Vencidas manda lo más reciente (lo que venció hace menos), y lo que no trae referencia va al final', () => {
     const cola = [
-      item('b', 'tarea_vencida', '2026-09-19T15:00:00Z'),
-      item('sin', 'tarea_vencida', null),
       item('a', 'tarea_vencida', '2026-09-18T15:00:00Z'),
+      item('sin', 'tarea_vencida', null),
+      item('b', 'tarea_vencida', '2026-09-19T15:00:00Z'),
+    ]
+    expect(ordenarColaDiaria(cola, []).map((f) => f.lead_id)).toEqual(['b', 'a', 'sin'])
+  })
+
+  it('Sin primer intento y Sin conversación también van de lo más reciente a lo más antiguo; «Hoy» sigue por hora', () => {
+    const cola = [
+      item('viejo', 'primera_atencion', '2026-09-18T14:00:00Z'),
+      item('nuevo', 'primera_atencion', '2026-09-20T14:00:00Z'),
+      item('tarde', 'tarea_hoy', '2026-09-20T22:00:00Z'),
+      item('temprano', 'tarea_hoy', '2026-09-20T15:00:00Z'),
+    ]
+    const cartera = [
+      senal('ab-20', { sin_conversacion: true, dias_sin_conversacion: 20, ultima_conversacion_en: '2026-08-31T12:00:00Z' }),
+      senal('ab-8', { sin_conversacion: true, dias_sin_conversacion: 8, ultima_conversacion_en: '2026-09-12T12:00:00Z' }),
     ]
-    expect(ordenarColaDiaria(cola, []).map((f) => f.lead_id)).toEqual(['a', 'b', 'sin'])
+    expect(ordenarColaDiaria(cola, cartera).map((f) => f.lead_id)).toEqual(['nuevo', 'viejo', 'temprano', 'tarde', 'ab-8', 'ab-20'])
   })
 
   it('un lead aparece UNA vez, en su grupo más urgente, y los buckets ajenos no entran', () => {
@@ -84,8 +98,9 @@ describe('ordenarColaDiaria', () => {
       cliente('c-hoy-2', 'tarea_hoy', '2026-09-20T20:00:00Z', { perfil_id: 'p-1', nombre: 'SOLO PORTAL' }),
     ]
     const filas = ordenarColaDiaria(cola, [])
+    // Vencidas: la del lead (19/09) venció hace menos que la de ROSA (18/09); Hoy por hora.
     expect(filas.map((f) => `${f.grupo}:${f.clave}`)).toEqual([
-      'primera_atencion:lead:nuevo', 'tarea_vencida:tarea:c-venc', 'tarea_vencida:lead:lv', 'tarea_hoy:tarea:c-hoy-2', 'tarea_hoy:tarea:c-hoy-1',
+      'primera_atencion:lead:nuevo', 'tarea_vencida:lead:lv', 'tarea_vencida:tarea:c-venc', 'tarea_hoy:tarea:c-hoy-2', 'tarea_hoy:tarea:c-hoy-1',
     ])
     // La misma persona con dos tareas = dos filas, cada una con su tarea.
     const rosa = filas.filter((f) => f.nombre_completo === 'ROSA CLIENTE')
@@ -287,8 +302,9 @@ describe('espejo demo', () => {
       { ...base, id: 'dos-sujetos', perfil_id: 'p-2', inversionista_id: 'inv-6', titulo: 'Llamar a ROTA', vence_en: '2026-09-19T15:00:00Z' },
     ]
     const filas = filasDiariasDemo(d.cartera, ahora, dia, deClientes, 'a1')
+    // Vencidas de lo más reciente a lo más antiguo: l3 (19/09 15:00) antes que ROSA (19/09 10:00); Hoy por hora.
     expect(filas.map((f) => `${f.grupo}:${f.clave}`)).toEqual([
-      'primera_atencion:lead:l1', 'tarea_vencida:tarea:cv', 'tarea_vencida:lead:l3', 'tarea_hoy:tarea:ch1', 'tarea_hoy:tarea:ch2',
+      'primera_atencion:lead:l1', 'tarea_vencida:lead:l3', 'tarea_vencida:tarea:cv', 'tarea_hoy:tarea:ch1', 'tarea_hoy:tarea:ch2',
     ])
     expect(filas.filter((f) => f.tipo === 'cliente').map((f) => f.nombre_completo)).toEqual(['ROSA DÍAZ', 'ROSA DÍAZ', 'LUIS PORTAL'])
   })
@@ -305,7 +321,7 @@ describe('finDelDiaLima', () => {
 })
 
 describe('filtro «Todo» y el siguiente al guardar (27/09/2026)', () => {
-  // Dos sin primer intento, una vencida, ninguna de hoy y una sin conversación.
+  // Dos sin primer intento (n2 es la más reciente: va primero), una vencida, ninguna de hoy y una sin conversación.
   const filas = ordenarColaDiaria(
     [item('n1', 'primera_atencion', '2026-09-20T10:00:00Z'), item('n2', 'primera_atencion', '2026-09-20T11:00:00Z'), item('v1', 'tarea_vencida', '2026-09-19T10:00:00Z')],
     [senal('s1', { sin_conversacion: true, dias_sin_conversacion: 9 })],
@@ -315,23 +331,23 @@ describe('filtro «Todo» y el siguiente al guardar (27/09/2026)', () => {
   const L = (id: string) => `lead:${id}`
 
   it('«Todo» es la cola entera en el orden de los grupos; un grupo, solo lo suyo', () => {
-    expect(ids(filasDelFiltro(grupos, 'todo'))).toEqual(['n1', 'n2', 'v1', 's1'])
+    expect(ids(filasDelFiltro(grupos, 'todo'))).toEqual(['n2', 'n1', 'v1', 's1'])
     expect(ids(filasDelFiltro(grupos, 'tarea_vencida'))).toEqual(['v1'])
     expect(filasDelFiltro(grupos, 'tarea_hoy')).toEqual([])
   })
 
   it('al guardar pasa a la que venía DETRÁS en la lista que se miraba', () => {
-    expect(siguienteTrasGuardar(grupos, 'todo', L('n1'))).toEqual({ filtro: 'todo', clave: L('n2') })
+    expect(siguienteTrasGuardar(grupos, 'todo', L('n2'))).toEqual({ filtro: 'todo', clave: L('n1') })
     expect(siguienteTrasGuardar(grupos, 'todo', L('v1'))).toEqual({ filtro: 'todo', clave: L('s1') })
   })
 
   it('si el guardado era el último, pasa al nuevo último de esa lista', () => {
     expect(siguienteTrasGuardar(grupos, 'todo', L('s1'))).toEqual({ filtro: 'todo', clave: L('v1') })
-    expect(siguienteTrasGuardar(grupos, 'primera_atencion', L('n2'))).toEqual({ filtro: 'primera_atencion', clave: L('n1') })
+    expect(siguienteTrasGuardar(grupos, 'primera_atencion', L('n1'))).toEqual({ filtro: 'primera_atencion', clave: L('n2') })
   })
 
   it('si el grupo se queda vacío, sigue con la cola entera desde el principio', () => {
-    expect(siguienteTrasGuardar(grupos, 'tarea_vencida', L('v1'))).toEqual({ filtro: 'todo', clave: L('n1') })
+    expect(siguienteTrasGuardar(grupos, 'tarea_vencida', L('v1'))).toEqual({ filtro: 'todo', clave: L('n2') })
   })
 
   it('un guardado que no estaba en la lista mirada deja «Ahora» en la primera de esa lista', () => {
@@ -339,10 +355,11 @@ describe('filtro «Todo» y el siguiente al guardar (27/09/2026)', () => {
   })
 
   it('con dos tareas de un mismo cliente, guardar una pasa a la OTRA, no salta a la persona', () => {
+    // Vencidas de lo más reciente a lo más antiguo: t1 (19/09 11:00), t2 (19/09 10:00), v9 (18/09).
     const conCliente = pestanasDiarias(ordenarColaDiaria([
-      cliente('t1', 'tarea_vencida', '2026-09-18T10:00:00Z', { inversionista_id: 'inv-1' }),
+      cliente('t1', 'tarea_vencida', '2026-09-19T11:00:00Z', { inversionista_id: 'inv-1' }),
       cliente('t2', 'tarea_vencida', '2026-09-19T10:00:00Z', { inversionista_id: 'inv-1' }),
-      item('v9', 'tarea_vencida', '2026-09-19T11:00:00Z'),
+      item('v9', 'tarea_vencida', '2026-09-18T10:00:00Z'),
     ], []))
     expect(siguienteTrasGuardar(conCliente, 'tarea_vencida', 'tarea:t1')).toEqual({ filtro: 'tarea_vencida', clave: 'tarea:t2' })
     expect(siguienteTrasGuardar(conCliente, 'tarea_vencida', 'tarea:t2')).toEqual({ filtro: 'tarea_vencida', clave: 'lead:v9' })
diff --git a/CRM-Avance-Corp/app/src/lib/gestion-diaria-analista.ts b/CRM-Avance-Corp/app/src/lib/gestion-diaria-analista.ts
index 305a11aa..053a9b1f 100644
--- a/CRM-Avance-Corp/app/src/lib/gestion-diaria-analista.ts
+++ b/CRM-Avance-Corp/app/src/lib/gestion-diaria-analista.ts
@@ -144,7 +144,10 @@ interface FilaComun {
   clave: string
   nombre_completo: string
   grupo: GrupoDia
-  /** Instante que ordena dentro del grupo (vencimiento o límite); null al final. */
+  /**
+   * Instante que ordena dentro del grupo (vencimiento o límite): lo más reciente
+   * primero, salvo en «Hoy», que va por hora (20/10/2026); null al final.
+   */
   referencia_en: string | null
   severidad: 'critica' | 'media' | 'baja'
 }
@@ -188,6 +191,12 @@ const GRUPO_DE_BUCKET: Record<string, GrupoDia> = {
  * urgente. Las tareas de clientes entran en «Vencidas» o «Hoy» según su bucket,
  * una fila por tarea. Función pura: no llama a nada y no decide negocio, solo ordena.
  *
+ * Dentro de cada grupo, el MISMO orden que `crm.gestion_diaria_cola_trabajo_fn`
+ * (Miguel, 20/10/2026, «quiero que sea al revés»): en Sin primer intento, Vencidas
+ * y Sin conversación va primero lo más reciente (lo que venció hace menos arriba,
+ * lo más viejo al final); en «Hoy» nada está vencido y se va por hora, lo más
+ * próximo primero. Sin referencia, al final; empate, por clave.
+ *
  * NO se reutiliza `seleccionarPrioridadesVendedor` (screens/hoy): aquella es el
  * TOP-3 de la franja «Ahora» sobre la cola v1 y sigue gobernando esa pantalla.
  * Lo que sí comparten es el primer ítem: el speed-to-lead manda en las dos.
@@ -247,11 +256,12 @@ export function ordenarColaDiaria(
   return filas.sort((a, b) => {
     const porGrupo = ORDEN_GRUPO[a.grupo] - ORDEN_GRUPO[b.grupo]
     if (porGrupo !== 0) return porGrupo
-    // Dentro del grupo, lo más antiguo primero; sin referencia, al final.
+    // Dentro del grupo: «Hoy» por hora; en los demás, lo más reciente primero. Sin referencia, al final.
     if (a.referencia_en === b.referencia_en) return a.clave.localeCompare(b.clave)
     if (a.referencia_en === null) return 1
     if (b.referencia_en === null) return -1
-    return a.referencia_en.localeCompare(b.referencia_en)
+    const porHora = a.referencia_en.localeCompare(b.referencia_en)
+    return a.grupo === 'tarea_hoy' ? porHora : -porHora
   })
 }
 
diff --git a/CRM-Avance-Corp/app/src/lib/gestion-diaria-cola-demo.ts b/CRM-Avance-Corp/app/src/lib/gestion-diaria-cola-demo.ts
index 038c50ca..701436fd 100644
--- a/CRM-Avance-Corp/app/src/lib/gestion-diaria-cola-demo.ts
+++ b/CRM-Avance-Corp/app/src/lib/gestion-diaria-cola-demo.ts
@@ -15,13 +15,18 @@ export function paginarTrabajoDemo(filas: readonly FilaTrabajo[], p: PedidoColaT
       gestionados: grupo.filter((f) => f.estado_trabajo === 'gestionado').length,
       programados: grupo.filter((f) => f.estado_trabajo === 'programado').length }]
   })) as ColaTrabajo['totales']
+  // El mismo orden que `crm.gestion_diaria_cola_trabajo_fn` (20/10/2026): pendientes por grupo;
+  // dentro del grupo, lo más reciente primero (en «Hoy», por hora); sin referencia, al final.
   const ordenadas = filas.filter((f) => filtro === 'todo' || f.grupo === filtro).sort((a, b) => {
     const ap = a.estado_trabajo === 'pendiente', bp = b.estado_trabajo === 'pendiente'
     if (ap !== bp) return ap ? -1 : 1
     const grupo = ap ? FILTROS_TRABAJO.indexOf(a.grupo) - FILTROS_TRABAJO.indexOf(b.grupo) : 0
-    const t = (f: FilaTrabajo) => ap ? f.referencia_en ? Date.parse(f.referencia_en) : Infinity
+    const t = (f: FilaTrabajo) => ap ? f.referencia_en ? Date.parse(f.referencia_en) : null
       : f.ultima_gestion ? Date.parse(f.ultima_gestion.en) : 0
-    return grupo || t(a) - t(b) || a.clave.localeCompare(b.clave)
+    const ta = t(a), tb = t(b)
+    const sinReferencia = (ta === null ? 1 : 0) - (tb === null ? 1 : 0)
+    const porInstante = ta === null || tb === null ? 0 : ap && a.grupo !== 'tarea_hoy' ? tb - ta : ta - tb
+    return grupo || sinReferencia || porInstante || a.clave.localeCompare(b.clave)
   })
   const posicion = ordenadas.findIndex((f) => f.clave === p.elegido)
   const pagina = posicion >= 0 ? Math.floor(posicion / p.limite) : Math.min(p.pagina, Math.max(0, Math.ceil(ordenadas.length / p.limite) - 1))
diff --git a/CRM-Avance-Corp/app/src/lib/gestion-diaria-pendientes.fixture.ts b/CRM-Avance-Corp/app/src/lib/gestion-diaria-pendientes.fixture.ts
index 51fda7d6..98831c5e 100644
--- a/CRM-Avance-Corp/app/src/lib/gestion-diaria-pendientes.fixture.ts
+++ b/CRM-Avance-Corp/app/src/lib/gestion-diaria-pendientes.fixture.ts
@@ -7,7 +7,7 @@ export const tareaPendiente = (n = 10, cambios: Partial<PendienteSupervisor> = {
   vence_en: '2026-09-23T15:00:00.000001+00:00', estado: 'pendiente', referencia_tipo: 'lead', lead_id: idPendiente(3), lead_nombre: 'Lead visible', ...cambios,
 })
 export function paginaPendientes(items: PendienteSupervisor[] = [tareaPendiente()], cambios: Partial<PaginaPendientes> = {}): PaginaPendientes {
-  return { version: 1, zona: 'America/Lima', supervisor_id: pedidoPendientes.supervisor, analista_id: pedidoPendientes.analista,
+  return { version: 3, zona: 'America/Lima', supervisor_id: pedidoPendientes.supervisor, analista_id: pedidoPendientes.analista,
     generado_en: '2026-09-23T17:00:00.000001+00:00', pendientes_al: '2026-09-23T17:00:00.000001+00:00',
     solo_vencidas: false, limite: 25, resumen: { tareas_pendientes: items.length, tareas_vencidas: items.length },
     items, hay_mas: false, siguiente_cursor: null, ...cambios }
diff --git a/CRM-Avance-Corp/app/src/lib/gestion-diaria-pendientes.test.ts b/CRM-Avance-Corp/app/src/lib/gestion-diaria-pendientes.test.ts
index dd25535a..9cc6dd91 100644
--- a/CRM-Avance-Corp/app/src/lib/gestion-diaria-pendientes.test.ts
+++ b/CRM-Avance-Corp/app/src/lib/gestion-diaria-pendientes.test.ts
@@ -1,22 +1,23 @@
 import { describe, expect, it } from 'vitest'
-import { compararPendientes, instantePendiente, pendientesDesdeDemo, unirPaginasPendientes, validarPaginaPendientes } from './gestion-diaria-pendientes'
+import { compararPendientes, instantePendiente, pendientesDesdeDemo, unirPaginasPendientes, validarPaginaPendientes, type PendienteSupervisor } from './gestion-diaria-pendientes'
 import { idPendiente, paginaPendientes, pedidoPendientes, tareaPendiente } from './gestion-diaria-pendientes.fixture'
 import type { Tarea } from './tipos'
 
 describe('Contrato estricto de pendientes del supervisor', () => {
   it('acepta vacío confirmado, título vacío, referencias ocultas y las tres anclas', () => {
     expect(validarPaginaPendientes(paginaPendientes([]), pedidoPendientes)).not.toBeNull()
-    const items = [tareaPendiente(10, { titulo: '', lead_id: null, lead_nombre: null }),
+    const items = [tareaPendiente(12, { titulo: '', lead_id: null, lead_nombre: null }),
       tareaPendiente(11, { referencia_tipo: 'perfil', lead_id: null, lead_nombre: null }),
-      tareaPendiente(12, { referencia_tipo: 'postventa', lead_id: null, lead_nombre: null })]
+      tareaPendiente(10, { referencia_tipo: 'postventa', lead_id: null, lead_nombre: null })]
     expect(validarPaginaPendientes(paginaPendientes(items), pedidoPendientes)?.items).toHaveLength(3)
   })
   it.each([
     { version: 99 }, { zona: 'UTC' }, { supervisor_id: idPendiente(9) }, { analista_id: idPendiente(9) },
     { solo_vencidas: true }, { limite: 101 }, { generado_en: 'infinity' }, { pendientes_al: '2026-02-30T12:00:00Z' },
     { resumen: { tareas_pendientes: 1, tareas_vencidas: 2 } }, { resumen: { tareas_pendientes: 1.5, tareas_vencidas: 1 } },
-    { hay_mas: true }, { items: [] }, { telefono: 'dato no permitido' },
-    { items: [tareaPendiente(), tareaPendiente()] }, { items: [tareaPendiente(11), tareaPendiente(10)] },
+    { hay_mas: true }, { items: [] }, { telefono: 'dato no permitido' }, { version: 2 },
+    { items: [tareaPendiente(), tareaPendiente()] }, { items: [tareaPendiente(10), tareaPendiente(11)] },
+    { items: [tareaPendiente(10, { vence_en: '2026-09-23T14:00:00Z' }), tareaPendiente(11, { vence_en: '2026-09-23T16:00:00Z' })] },
     { items: [tareaPendiente(10, { vendedor_id: idPendiente(9) })] },
     { items: [tareaPendiente(10, { lead_nombre: null })] },
     { items: [tareaPendiente(10, { lead_nombre: ' ' })] },
@@ -25,36 +26,54 @@ describe('Contrato estricto de pendientes del supervisor', () => {
   ])('rechaza toda la respuesta dañada, sin descartar filas: %j', cambio => {
     expect(validarPaginaPendientes({ ...paginaPendientes(), ...cambio }, pedidoPendientes)).toBeNull()
   })
-  it('valida límite más sonda, cursores coherentes y avance estricto con empate de fecha', () => {
-    const items = Array.from({ length: 25 }, (_, i) => tareaPendiente(10 + i))
+  it('la lista va de lo más reciente a lo más antiguo: la que venció hace menos arriba, la más vieja al final', () => {
+    const reciente = tareaPendiente(10, { vence_en: '2026-09-23T16:00:00Z' }), vieja = tareaPendiente(11, { vence_en: '2026-09-22T09:00:00Z' })
+    expect(compararPendientes(reciente, vieja)).toBeLessThan(0)
+    expect(validarPaginaPendientes(paginaPendientes([reciente, vieja]), pedidoPendientes)?.items.map(t => t.titulo)).toEqual(['Tarea 10', 'Tarea 11'])
+    expect(validarPaginaPendientes(paginaPendientes([vieja, reciente]), pedidoPendientes)).toBeNull()
+    expect(unirPaginasPendientes([paginaPendientes([vieja]), paginaPendientes([reciente])])).toEqual([reciente, vieja])
+  })
+  it('valida límite más sonda, cursores coherentes y avance estricto (hacia atrás) con empate de fecha', () => {
+    // Mismo vence_en en las 25: el empate se desempata por id DESCENDENTE (34 … 10).
+    const items = Array.from({ length: 25 }, (_, i) => tareaPendiente(34 - i))
     const cursor = { despues_de: items[24]!.vence_en, despues_id: items[24]!.id }
     const pagina = paginaPendientes(items, { resumen: { tareas_pendientes: 26, tareas_vencidas: 26 }, hay_mas: true, siguiente_cursor: cursor })
     expect(validarPaginaPendientes(pagina, pedidoPendientes)).not.toBeNull()
     expect(validarPaginaPendientes({ ...pagina, siguiente_cursor: { ...cursor, despues_id: items[0]!.id } }, pedidoPendientes)).toBeNull()
-    expect(validarPaginaPendientes(paginaPendientes([tareaPendiente(35)]), { ...pedidoPendientes, cursor })).not.toBeNull()
+    // «Después» del cursor (id 10) sólo cabe algo más antiguo: el id 9 sí, el 35 no, el propio cursor tampoco.
+    expect(validarPaginaPendientes(paginaPendientes([tareaPendiente(9)]), { ...pedidoPendientes, cursor })).not.toBeNull()
+    expect(validarPaginaPendientes(paginaPendientes([tareaPendiente(35)]), { ...pedidoPendientes, cursor })).toBeNull()
     expect(validarPaginaPendientes(paginaPendientes([items[24]!]), { ...pedidoPendientes, cursor })).toBeNull()
     expect(validarPaginaPendientes(paginaPendientes(), { ...pedidoPendientes, cursor: { ...cursor, despues_de: 'infinity' } })).toBeNull()
   })
   it('conserva microsegundos y no declara vencida una tarea en el mismo instante', () => {
     expect(instantePendiente('2026-09-23T15:00:00.000002Z')! - instantePendiente('2026-09-23T10:00:00.000001-05:00')!).toBe(1n)
-    expect(compararPendientes(tareaPendiente(99), tareaPendiente(1, { vence_en: '2026-09-23T15:00:00.000002Z' }))).toBeLessThan(0)
+    // Un microsegundo más reciente va ANTES, aunque su id sea menor.
+    expect(compararPendientes(tareaPendiente(99), tareaPendiente(1, { vence_en: '2026-09-23T15:00:00.000002Z' }))).toBeGreaterThan(0)
     const p = paginaPendientes([tareaPendiente(10, { vence_en: '2026-09-23T17:00:00.000001Z' })], { solo_vencidas: true })
     expect(validarPaginaPendientes(p, { ...pedidoPendientes, soloVencidas: true })).toBeNull()
   })
-  it('una tarea reprogramada entre páginas aparece una sola vez con su última fecha', () => {
+  it('una tarea reprogramada entre páginas aparece una sola vez con su última fecha, en su sitio', () => {
     const nueva = tareaPendiente(10, { vence_en: '2026-09-25T15:00:00Z' })
-    expect(unirPaginasPendientes([paginaPendientes([tareaPendiente(10), tareaPendiente(11)]), paginaPendientes([nueva])])).toEqual([tareaPendiente(11), nueva])
+    expect(unirPaginasPendientes([paginaPendientes([tareaPendiente(11), tareaPendiente(10)]), paginaPendientes([nueva])])).toEqual([nueva, tareaPendiente(11)])
   })
-  it('demo recorre más de mil tareas, filtra por responsable y no necesita un lead visible', () => {
-    const tareas = Array.from({ length: 1007 }, (_, i) => ({ ...tareaPendiente(i + 10), activo: true, reprogramaciones: 0, creado_en: '2026-09-23T12:00:00Z', lead_id: idPendiente(3), perfil_id: null, inversionista_id: null })) as Tarea[]
+  it('demo recorre más de mil tareas de lo más reciente a lo más antiguo, filtra por responsable y no necesita un lead visible', () => {
+    const tareas = Array.from({ length: 1007 }, (_, i) => ({ ...tareaPendiente(i + 10, { vence_en: `2026-09-${String(1 + (i % 20)).padStart(2, '0')}T15:00:00Z` }), activo: true, reprogramaciones: 0, creado_en: '2026-09-01T12:00:00Z', lead_id: idPendiente(3), perfil_id: null, inversionista_id: null })) as Tarea[]
     tareas.push({ ...tareas[0]!, vendedor_id: idPendiente(9) }, { ...tareas[0]!, activo: false }, { ...tareas[0]!, estado: 'completada' })
     let cursor = null as typeof pedidoPendientes.cursor
     const ids = new Set<string>()
+    let anterior: PendienteSupervisor | null = null
     do {
-      const p = pendientesDesdeDemo({ ...pedidoPendientes, cursor }, tareas, [], Date.parse('2026-09-23T17:00:00Z'))
-      expect(p.resumen.tareas_pendientes).toBe(1007)
-      expect(p.items.every(t => t.lead_id === null && t.lead_nombre === null)).toBe(true)
-      p.items.forEach(t => ids.add(t.id)); cursor = p.siguiente_cursor
+      const p = validarPaginaPendientes(pendientesDesdeDemo({ ...pedidoPendientes, cursor }, tareas, [], Date.parse('2026-09-23T17:00:00Z')), { ...pedidoPendientes, cursor })
+      expect(p).not.toBeNull()
+      expect(p!.version).toBe(3)
+      expect(p!.resumen.tareas_pendientes).toBe(1007)
+      expect(p!.items.every(t => t.lead_id === null && t.lead_nombre === null)).toBe(true)
+      for (const t of p!.items) {
+        if (anterior) expect(compararPendientes(t, anterior)).toBeGreaterThan(0)
+        anterior = t; ids.add(t.id)
+      }
+      cursor = p!.siguiente_cursor
     } while (cursor)
     expect(ids.size).toBe(1007)
     expect(() => pendientesDesdeDemo(pedidoPendientes, [{ ...tareas[0]!, perfil_id: idPendiente(2) }], [], Date.now())).toThrow('integridad')
diff --git a/CRM-Avance-Corp/app/src/lib/gestion-diaria-pendientes.ts b/CRM-Avance-Corp/app/src/lib/gestion-diaria-pendientes.ts
index ad604f59..1062a570 100644
--- a/CRM-Avance-Corp/app/src/lib/gestion-diaria-pendientes.ts
+++ b/CRM-Avance-Corp/app/src/lib/gestion-diaria-pendientes.ts
@@ -1,3 +1,8 @@
+// Pendientes de un analista en la ficha del supervisor / Gerencia (H3+G4a), desde el
+// 20/10/2026 por `crm.gestion_diaria_pendientes_v3_fn`: la lista va DE LO MÁS RECIENTE A LO
+// MÁS ANTIGUO (vence_en descendente; en «Vencidas», lo que venció hace menos arriba y lo más
+// viejo al final) y el cursor avanza hacia atrás. Decisión de Miguel («quiero que sea al
+// revés»). La v2 sigue ascendente para los bundles publicados: no se mezclan.
 import { identidadClienteValida } from './sujeto-gestion'
 import * as v from 'valibot'
 import type { Lead, Tarea } from './tipos'
@@ -30,7 +35,7 @@ export const PendienteSupervisorSchema = v.strictObject({
 })
 export type PendienteSupervisor = v.InferOutput<typeof PendienteSupervisorSchema>
 export const PaginaPendientesSchema = v.strictObject({
-  version: v.union([v.literal(1), v.literal(2)]), zona: v.literal('America/Lima'), supervisor_id: Uuid, analista_id: Uuid,
+  version: v.literal(3), zona: v.literal('America/Lima'), supervisor_id: Uuid, analista_id: Uuid,
   generado_en: Fecha, pendientes_al: Fecha, solo_vencidas: v.boolean(),
   limite: v.pipe(Natural, v.minValue(1), v.maxValue(100)),
   resumen: v.strictObject({ tareas_pendientes: Natural, tareas_vencidas: Natural }),
@@ -42,11 +47,16 @@ export interface PedidoPendientes {
   supervisor: string; analista: string; soloVencidas: boolean; limite: number; cursor: CursorPendientes | null
 }
 
+/**
+ * El orden de la lista: negativo si `a` va ANTES que `b`. De lo más reciente a lo más antiguo
+ * (vence_en descendente, empate por id descendente), el mismo que pone la v3 del servidor y
+ * el que recorre su cursor («después de» = más antiguo que la última fila).
+ */
 export function compararPendientes(a: Pick<PendienteSupervisor, 'vence_en' | 'id'>, b: Pick<PendienteSupervisor, 'vence_en' | 'id'>): number {
   const x = instantePendiente(a.vence_en), y = instantePendiente(b.vence_en)
   if (x === null || y === null) throw new Error('Fecha de tarea inválida')
   const idA = a.id.toLowerCase(), idB = b.id.toLowerCase()
-  return x < y ? -1 : x > y ? 1 : idA < idB ? -1 : idA > idB ? 1 : 0
+  return x > y ? -1 : x < y ? 1 : idA > idB ? -1 : idA < idB ? 1 : 0
 }
 
 /** Frontera estricta: jamás descartar una fila para aparentar lista completa. */
@@ -88,7 +98,7 @@ export function unirPaginasPendientes(paginas: readonly PaginaPendientes[]): Pen
   return [...porId.values()].sort(compararPendientes)
 }
 
-/** Sólo demo: el store demo sí es completo y ya está acotado por su ámbito. */
+/** Sólo demo: el store demo sí es completo y ya está acotado por su ámbito. Mismo orden y cursor que la v3. */
 export function pendientesDesdeDemo(pedido: PedidoPendientes, tareas: readonly Tarea[], leads: readonly Lead[], ahora: number): PaginaPendientes {
   const base = tareas.filter(t => t.activo && t.estado === 'pendiente' && t.vendedor_id === pedido.analista)
   const porId = new Map(leads.filter(l => l.activo).map(l => [l.id, l]))
@@ -105,7 +115,7 @@ export function pendientesDesdeDemo(pedido: PedidoPendientes, tareas: readonly T
   const seleccion = (pedido.soloVencidas ? vencidas : items).sort(compararPendientes)
     .filter(t => !pedido.cursor || compararPendientes(t, { id: pedido.cursor.despues_id, vence_en: pedido.cursor.despues_de }) > 0)
   const pagina = seleccion.slice(0, pedido.limite), ultima = pagina.at(-1), hayMas = seleccion.length > pedido.limite
-  return { version: 1, zona: 'America/Lima', supervisor_id: pedido.supervisor, analista_id: pedido.analista,
+  return { version: 3, zona: 'America/Lima', supervisor_id: pedido.supervisor, analista_id: pedido.analista,
     generado_en: new Date(ahora).toISOString(), pendientes_al: new Date(ahora).toISOString(),
     solo_vencidas: pedido.soloVencidas, limite: pedido.limite,
     resumen: { tareas_pendientes: items.length, tareas_vencidas: vencidas.length }, items: pagina,
diff --git a/CRM-Avance-Corp/app/src/screens/gestion-diaria/analista.test.tsx b/CRM-Avance-Corp/app/src/screens/gestion-diaria/analista.test.tsx
index 55285e50..c7f2cbeb 100644
--- a/CRM-Avance-Corp/app/src/screens/gestion-diaria/analista.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/gestion-diaria/analista.test.tsx
@@ -272,8 +272,9 @@ describe('GestionDiariaAnalista · a quién llamo ahora', () => {
   })
 
   it('elegir una fila de la lista la lleva a «Ahora»', async () => {
+    // l5 va detrás de l1: su límite es más antiguo (12:00 < 14:00; lo más reciente primero).
     dobles.cola = {
-      data: { items: [itemCola('l1', 'primera_atencion', '2026-09-20T14:00:00Z'), itemCola('l5', 'primera_atencion', '2026-09-20T17:00:00Z')] },
+      data: { items: [itemCola('l1', 'primera_atencion', '2026-09-20T14:00:00Z'), itemCola('l5', 'primera_atencion', '2026-09-20T12:00:00Z')] },
       error: null, refetch: vi.fn(), isFetching: false,
     }
     render(<GestionDiariaAnalista />)
@@ -293,7 +294,7 @@ describe('GestionDiariaAnalista · a quién llamo ahora', () => {
     let soltar: () => void = () => {}
     dobles.recargar = vi.fn(() => new Promise<void>((r) => { soltar = () => { r() } }))
     dobles.cola = {
-      data: { items: [itemCola('l1', 'primera_atencion', '2026-09-20T14:00:00Z'), itemCola('l5', 'primera_atencion', '2026-09-20T17:00:00Z')] },
+      data: { items: [itemCola('l1', 'primera_atencion', '2026-09-20T14:00:00Z'), itemCola('l5', 'primera_atencion', '2026-09-20T12:00:00Z')] },
       error: null, refetch: vi.fn(async () => {}), isFetching: false,
     }
     render(<GestionDiariaAnalista />)
@@ -517,12 +518,12 @@ describe('GestionDiariaAnalista · lo que NO está cargado no es lo que NO exist
 })
 
 describe('GestionDiariaAnalista · dos resultados seguidos (carrera)', () => {
-  /** La cola con tres leads del mismo grupo y un `recargar` que se suelta a mano. */
+  /** La cola con tres leads del mismo grupo (l1 la más reciente: va primero) y un `recargar` que se suelta a mano. */
   function tresYControl() {
     const sueltas: Array<() => void> = []
     dobles.recargar = vi.fn(() => new Promise<void>((r) => { sueltas.push(() => { r() }) }))
     dobles.cola = {
-      data: { items: ['l1', 'l5', 'l6'].map((x, i) => itemCola(x, 'primera_atencion', `2026-09-20T1${i}:00:00Z`)) },
+      data: { items: ['l1', 'l5', 'l6'].map((x, i) => itemCola(x, 'primera_atencion', `2026-09-20T1${2 - i}:00:00Z`)) },
       error: null, refetch: vi.fn(async () => {}), isFetching: false,
     }
     return sueltas
@@ -1038,10 +1039,11 @@ const tareaCliente = (id: string, extra: Record<string, unknown> = {}) => ({
 
 describe('GestionDiariaAnalista · tareas de CLIENTES (cola v3)', () => {
   beforeEach(() => {
+    // Vencidas de lo más reciente a lo más antiguo: la del lead (hoy 12:30 Lima) va DELANTE de la del cliente (hoy 12:00 Lima).
     dobles.cola = { data: { items: [
       itemCliente('c-venc', 'tarea_vencida', '2026-09-20T17:00:00Z', { inversionista_id: 'inv-rosa', nombre: 'ROSA CLIENTE' }),
       itemCliente('c-hoy', 'tarea_hoy', '2026-09-20T22:00:00Z', { inversionista_id: 'inv-rosa', nombre: 'ROSA CLIENTE' }),
-      itemCola('l2', 'tarea_vencida', '2026-09-19T15:00:00Z'),
+      itemCola('l2', 'tarea_vencida', '2026-09-20T17:30:00Z'),
     ] }, error: null, refetch: vi.fn(), isFetching: false }
     dobles.tareasAmbito = [tareaCliente('c-venc'), tareaCliente('c-hoy', { vence_en: '2026-09-20T22:00:00Z', titulo: 'Confirmar renovación' })]
     dobles.contactoCliente = { data: { telefono: '+51 988 777 666', contactar: true }, error: null, isPending: false, pedidos: [] }
@@ -1056,7 +1058,7 @@ describe('GestionDiariaAnalista · tareas de CLIENTES (cola v3)', () => {
     const lista = screen.getByRole('list', { name: /^Todo/ })
     expect(within(lista).getAllByRole('button', { name: /ROSA CLIENTE/ })).toHaveLength(2)
     expect(within(lista).getAllByText(/Cliente de tu cartera · gestión agendada/)).toHaveLength(2)
-    // Vencidas: la del cliente (hoy 12:00 Lima) va DETRÁS de la de ayer del lead.
+    // Vencidas: la del cliente (hoy 12:00 Lima) va DETRÁS de la del lead (hoy 12:30 Lima), que venció hace menos.
     expect(within(screen.getByRole('tablist', { name: 'Grupos de la cola' })).getByRole('tab', { name: /Vencidas/ })).toHaveTextContent('2')
   })
 
@@ -1143,7 +1145,7 @@ describe('GestionDiariaAnalista · tareas de CLIENTES (cola v3)', () => {
   it('al guardar (el store ya no la tiene pendiente) «Ahora» pasa a la fila de DETRÁS —la otra tarea de la misma persona— y el foco no se pierde', async () => {
     dobles.cola.refetch = vi.fn(async () => { dobles.cola.data = colaSinLaCerrada(); return dobles.cola })
     render(<GestionDiariaAnalista />)
-    // «Todo»: vencida del lead l2 (ayer), vencida de ROSA (hoy), de hoy de ROSA, sin conversación l3.
+    // «Todo»: vencida del lead l2 (hoy 12:30), vencida de ROSA (hoy 12:00), de hoy de ROSA, sin conversación l3.
     elegirCliente(/ROSA CLIENTE/)
     const registrar = within(screen.getByRole('region', { name: 'Ahora' })).getByRole('button', { name: 'Registrar resultado de ROSA CLIENTE' })
     fireEvent.click(registrar)
diff --git a/CRM-Avance-Corp/supabase/scripts/test-rls.mjs b/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
index e97fa39d..8fc13c7a 100644
--- a/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
+++ b/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
@@ -8784,6 +8784,41 @@ async function testGestionDiariaPendientes(sessions, seed) {
   check(isAuthorizationError(anonRpc.error), 'anon no ejecuta pendientes');
   const limite = await rpc('gerencia', id('vend1'), { p_limite: 0 });
   check(limite.error?.code === '22023', 'gerencia: límite 0 → 22023');
+
+  // 20261020214445: la v3 va de lo más reciente a lo más antiguo (vence_en desc, id desc) con la
+  // misma autorización; la v1/v2 siguen ascendentes para los bundles publicados.
+  const V3 = 'gestion_diaria_pendientes_v3_fn';
+  const rpc3 = (quien, analista, extra = {}) => sessions[quien].client.schema('crm').rpc(V3, { p_analista_id: analista, p_limite: 100, ...extra });
+  const probe3 = await rpc3('sup1', id('vend1'));
+  if (probe3.error?.code === 'PGRST202') {
+    const msg = '⚠ v3 de pendientes no instalada: orden reciente→antiguo SALTADO (no probado)';
+    if (process.env.CRM_RLS_EXIGE_GESTION_DIARIA === '1') fail(msg);
+    else console.log(`  ${msg}`);
+    return;
+  }
+  const posterior = (a, b) => a.vence_en < b.vence_en || (a.vence_en === b.vence_en && a.id < b.id);
+  for (const [quien, analista] of [['sup1', 'vend1'], ['gerencia', 'vend1'], ['gerencia', 'vend3']]) {
+    const [v3, v1] = await Promise.all([rpc3(quien, id(analista)), rpc(quien, id(analista), { p_limite: 100 })]);
+    const items = v3.data?.items ?? [];
+    check(!v3.error && v3.data?.version === 3 && v3.data?.supervisor_id === id(quien) && v3.data?.analista_id === id(analista)
+      && items.every((t, i) => i === 0 || posterior(t, items[i - 1])),
+      `${quien} → ${analista}: v3 autorizada, version 3 y de lo más reciente a lo más antiguo`);
+    check(!v1.error && JSON.stringify(items.map((t) => t.id)) === JSON.stringify([...(v1.data?.items ?? [])].reverse().map((t) => t.id))
+      && JSON.stringify(v3.data?.resumen) === JSON.stringify(v1.data?.resumen),
+      `${quien} → ${analista}: la v3 es la v1 al revés, con el mismo resumen`);
+  }
+  for (const [quien, analista, etiqueta] of [['sup1', id('vend3'), 'vend3 (otro equipo)'], ['gerencia', randomUUID(), 'inexistente']]) {
+    const { error } = await rpc3(quien, analista);
+    check(isAuthorizationError(error), `${quien}: v3 de ${etiqueta} → 42501`);
+  }
+  for (const quien of ['vend1', 'coordinador', 'directorio', 'vendInactive']) {
+    const { error } = await rpc3(quien, id('vend1'));
+    check(isAuthorizationError(error), `${quien}: sin puerta v3 de pendientes → 42501`);
+  }
+  const anonV3 = await anon.schema('crm').rpc(V3, { p_analista_id: id('vend1') });
+  check(isAuthorizationError(anonV3.error), 'anon no ejecuta la v3 de pendientes');
+  const limite3 = await rpc3('gerencia', id('vend1'), { p_limite: 0 });
+  check(limite3.error?.code === '22023', 'gerencia: v3 con límite 0 → 22023');
 }
 
 // G4b (28/09/2026): lista exacta de «Citas agendadas». Ámbito explícito decidido en el

```

## Protocolo global de revisión
# Protocolo global Codex ↔ Claude Code

Aplica al usuario de esta Mac, en cualquier proyecto, aunque no exista `.ai/`.
Las instrucciones del repositorio definen negocio, arquitectura y comandos;
este protocolo define los roles y el aislamiento de las consultas.

## Roles y autoridad

- PRIMARY: posee la tarea, inspecciona, decide, implementa, ejecuta checks,
  evalúa hallazgos y entrega el resultado. Es el único escritor.
- SECONDARY_REVIEWER: analiza evidencia, bugs, regresiones, seguridad,
  arquitectura, casos límite y pruebas faltantes. No escribe archivos, no
  implementa, no hace commits, no cambia configuración, no ejecuta acciones
  destructivas, no llama al otro agente y no delega ni inicia otro review.
- Una tarea normal del usuario define un PRIMARY. Un prompt que comienza con
  `ROLE: SECONDARY_REVIEWER` define un consultor, aunque existan instrucciones
  generales de autonomía. Si le piden otra opinión, devuelve su propio análisis.
- La única cadena permitida es PRIMARY → SECONDARY_REVIEWER → PRIMARY.
- El reviewer es asesor; el PRIMARY decide con evidencia. Un PASS de IA no
  significa que la tarea esté terminada.

## Cuándo consultar

- LEVEL 1: formato, documentación sencilla, CSS pequeño, rename o fix obvio:
  cero consultas.
- LEVEL 2: lógica relevante, integración, endpoint, componente importante o
  refactor moderado: normalmente una consulta si aporta valor independiente.
- LEVEL 3: auth, permisos, secretos, seguridad, schemas/migraciones, arquitectura,
  concurrencia, pagos, lógica financiera, APIs importantes o cambios destructivos:
  una consulta cuando sea razonablemente posible.
- Máximo habitual: dos consultas por tarea, contando reviewers especializados.
  La segunda necesita nueva evidencia, discrepancia importante o corrección de
  riesgo que justifique otra verificación. No repetir hasta conseguir un PASS.
- Las instrucciones explícitas del usuario sobre consultas prevalecen. No
  consultar para confirmar trivialidades ni abrir cadenas recursivas.

## Evidence-first y formato

**NO FINDING WITHOUT EVIDENCE.** Citar archivo/líneas, símbolo, diff, test,
error, log o reproducción. Identificar como hipótesis lo no demostrado.
Omitir secciones vacías y recomendaciones genéricas sin relación con la tarea.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Conclusión técnica breve.

FINDINGS:
[P0 | P1 | P2 | P3] Título
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

TEST GAPS:
- ...
ARCHITECTURE RISKS:
- ...
SECURITY RISKS:
- ...
REGRESSION RISKS:
- ...
RECOMMENDED NEXT ACTIONS:
1. ...
CONFIDENCE:
HIGH | MEDIUM | LOW
```

PASS: sin hallazgos obligatorios en lo revisado. CHANGES_REQUESTED: correcciones
accionables. BLOCK: riesgo crítico o evidencia insuficiente para revisar.
Resolver desacuerdos por requisitos, comportamiento, pruebas y documentación
oficial, no mediante consultas repetitivas.

## Interfaces

Codex PRIMARY usa `~/.local/bin/claude-review`, o el wrapper del repo cuando
sus instrucciones lo requieran. Adjunta código/diff saneado, rutas/líneas,
requisitos y resultados de checks. No enviar secretos. CodeGraph se usa por
el PRIMARY si el proyecto está indexado, nunca se indexa automáticamente.

El wrapper global incorpora este protocolo y, si existe, el protocolo `.ai/`
del proyecto. Claude reviewer tiene todas las herramientas, MCP, hooks y
personalizaciones deshabilitadas; no persiste la sesión. Cinco turnos por
defecto, máximo ocho. Exit 0 indica entrega válida, no necesariamente PASS.
Usa `dontAsk`, sin solicitudes de permiso, y comprueba que el evento de inicio
declare cero herramientas y cero MCP antes de aceptar un resultado único.
Las menciones genéricas a herramientas en el texto del modelo no acreditan
disponibilidad: la comprobación debe usar el inventario efectivo de la CLI.

Claude PRIMARY usa `mcp__codex__codex` con:

```text
sandbox: read-only
approval-policy: never
prompt:
ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
```

Adjuntar el contenido de este protocolo, las reglas relevantes del proyecto y
la evidencia: el reviewer no tiene herramientas para abrirlos. Solo se permite
añadir `model`; no `cwd`, `config` ni overrides de instrucciones. `codex-reply`
está bloqueado; una segunda consulta justificada inicia otro review seguro.

El MCP global usa `~/.local/bin/codex-review-mcp`. Trabaja en una carpeta neutral
de esta instalación para no cargar configuración específica de otros proyectos.
Deshabilita shell, subagentes, apps, hooks, navegador, plugins y cada MCP heredado.
Las tablas vacías TOML se fusionan: no sirven para eliminar los MCP del usuario.
Una entrada MCP local/de proyecto puede tener precedencia; comprobar su
aislamiento antes de usarla. No sustituir una interfaz protegida por una directa.

## Verificación, simultaneidad y límites

Aplicar `~/.config/ai-collaboration/VERIFICATION.md` y los gates concretos del repo.
Dos PRIMARY simultáneos en tareas distintas requieren working trees separados.
No crear worktrees automáticamente; un reviewer read-only no necesita uno.

Los hooks globales de Claude protegen secretos y operaciones peligrosas comunes;
los hooks no analizan los efectos indirectos de scripts arbitrarios. Las reglas
nativas ocultan `.env.*` también en búsquedas; incluyen `.env.example`, que se
gestiona manualmente. El usuario conserva sus modelos, plugins y ajustes normales.

El inventario del MCP se fija al arrancar. No cambiar MCP/plugins/configuración
de agentes durante el review. Tras cambiarlos, reconectar `codex` y ejecutar
`~/.local/bin/codex-review-mcp --check` antes de la siguiente consulta. No se
afirma aislamiento frente a cambios concurrentes de terceros.


## Verificación obligatoria
# Verification Gate global

**A task must not be considered complete merely because the code was written.**

El PRIMARY identifica el stack y los comandos reales de cada proyecto antes de
modificar archivos. Lee instrucciones, manifests, lockfiles, scripts, CI y
configuración de tests/lint/build. Usa la navegación requerida por el proyecto.

Orden: cambio → validación estática relevante → tests relevantes → build cuando
aplique → review según riesgo → correcciones → verificación final → entrega.

- Si existe `.ai/VERIFICATION.md`, usar sus comandos concretos. Respetar gates de
  AGENTS.md, CLAUDE.md, CONTRIBUTING.md y CI. No copiar comandos de otro proyecto.
- Node: usar el gestor del lockfile y los scripts definidos en package.json.
- Python, Rust, Go, Java, .NET, Swift u otros: usar los comandos documentados
  por el repo; no suponer que existen pytest, cargo, Maven o Xcode por el nombre.
- Migraciones, contratos API, autorización y datos: añadir las validaciones
  de dominio y entorno aislado que correspondan; no usar producción como banco.
- Documentación/configuración: validar el formato, rutas y comandos; para
  scripts, sintaxis y casos de comportamiento relevantes.
- No instalar dependencias, crear CI, cambiar ramas o desplegar solo por cargar
  esta configuración. Esas acciones dependen de la tarea autorizada.
- Reportar PASS, FAIL y NOT RUN con motivo. No afirmar pruebas no ejecutadas.
- La revisión no sustituye checks y no da autoridad de cierre al reviewer.
- En tareas con dos PRIMARY simultáneos usar working trees separados. Nunca
  crear uno automáticamente ni confundir dos ramas con aislamiento de carpetas.

Para verificar la instalación global en esta Mac:

```bash
node --test ~/.config/ai-collaboration/global.test.mjs
~/.local/bin/claude-review --help
~/.local/bin/codex-review-mcp --check
```

Validar JSON global y ejecutar `bash -n` individualmente para cada wrapper/hook.
Tras cambiar flags/versiones, comprobar handshake MCP y una revisión real con
evidencia saneada. `--check` verifica MCP efectivos y flags; `--strict-config` se
aplica al lanzamiento del servidor, porque Codex 0.153.4 no lo admite en `mcp list`.

Esta instalación no agrega workflows a futuros repositorios. El PRIMARY utiliza
los gates existentes y propone CI adecuado solo si la tarea lo necesita.


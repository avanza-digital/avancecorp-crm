ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Ronda 2 (misma migración 20261020214445: pendientes de lo más reciente a lo más antiguo) — evidencia nueva

Eres el mismo revisor secundario de la ronda 1 (tu respuesta va abajo). El PRIMARY aplicó parte de tus hallazgos y rechazó otros con
evidencia. Tu trabajo ahora: (1) decir si cada corrección cierra el hallazgo; (2) REFUTAR, si puedes, las tres razones de rechazo
(C1, C2, C6) con un caso concreto reproducible — o aceptar que no hay riesgo nuevo; (3) señalar si algo de lo cambiado abre un hueco.
Sin herramientas ni base: todo está transcrito. Responde en español con VERDICT, SUMMARY, por hallazgo ACEPTADO/REFUTADO con evidencia,
RIESGOS, NEXT ACTIONS, CONFIDENCE. Sin repetir hallazgos cerrados.

## Disposición del PRIMARY por hallazgo de la ronda 1
- C1 (P1, revertir el front no retira los bundles v3 abiertos): RECHAZADO como P1, documentado. Razón: es la regla de toda reversa de
  contrato en este repo (la reversa de G4a ya exigía «revertir PRIMERO el front y después la base»); mientras la v3 siga instalada no
  hace daño (solo el bundle nuevo la llama) y el CRM muestra el aviso de «versión publicada» que pide recargar en cuanto cambia
  version.json. La cabecera de reversa.sql ahora dice: correrla pasado ese rato (p. ej. al día siguiente), no en el mismo minuto.
  No se mantiene la v3 indefinidamente: la reversa es «volver al byte».
- C2 (P2, la cola cambia de orden sin versionar; una pestaña abierta puede repetir/omitir filas una vez): RECHAZADO. Razón: la cola
  pagina por número de página y su contenido ya se mueve entre peticiones por diseño (los gestionados pasan al final, las tareas
  entran a su hora: `proximo_cambio_en` fuerza releer, `refetchOnWindowFocus: 'always'`, `staleTime: 0`), el cliente relee la página
  actual en cada cambio y ancla por clave (`p_elegido`); el contrato validado (`colaTrabajoCoherente`) no incluye el orden ni en el
  commit publicado. Un reorden único al instalar equivale a cualquiera de esos cambios. Base y front se publican seguidos.
- C3 (empate): ACEPTADO (= A5 del auditor). Siembra: el empate real son los ids 24 y 25 (now()-30h); nueva aserción con solo vencidas y
  16 por página: la página 1 termina en el 25 y la 2 es exactamente el 24. Mutante «cursor sin id» (`b.vence_en < p_despues_de`):
  ahora FALLA en esa aserción (antes sobrevivía).
- C4 (línea base de COMMENT): ACEPTADO. El preflight exige los COMMENT vivos del núcleo y de la cola (medidos en producción el 20/10);
  el postflight de la reversa exige los dos. Mutante «comentario vivo distinto» → la migración se niega. Ciclo completo repetido en
  el banco: reversa OK → migración OK → prueba OK → reversa OK → migración OK; huellas sin cambios (los cuerpos no cambiaron).
- C5 (test de reprogramada entre páginas): ACEPTADO. Ahora la tarea se reprograma hacia ATRÁS (lo único que el cursor descendente
  vuelve a entregar en una página posterior); comentario explica que hacia adelante queda por encima del cursor y entra al Actualizar.
- C6 (hipótesis de interbloqueo v2/v3): RECHAZADO. La identidad la resuelve el MISMO ayudante (`private.gestiones_identificar_tareas`
  → `gestiones_clientes_identidades`) con el MISMO conjunto `select distinct … from filas` de sujetos (el orden de los ítems no
  determina el orden de los bloqueos); `FOR SHARE` son bloqueos compartidos que no se bloquean entre lectores; y con la v2 sola el
  orden de los ítems ya era arbitrario entre analistas y páginas. No hay orden de bloqueo nuevo.
- Del auditor-rls (A8): el hook `usePendientesSupervisor` ahora expone el resumen y el corte `pendientes_al` de la PRIMERA página cuando
  hay varias (lo que vence entre páginas queda por encima del cursor y no se recorre hasta «Actualizar»; las páginas siguientes son
  todas anteriores al corte de la primera). Diff abajo.

## Preflight actual de la migración (fragmento)
```sql
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


```

## reversa.sql actual
```sql
-- Reversa de 20261020214445 (pendientes de lo más reciente a lo más antiguo). Devuelve la base
-- al estado EXACTO anterior, medido en producción el 20/10/2026: el núcleo H3+G4a de 5
-- argumentos con su cuerpo de 20260928043728 (a0bde87d…), la cola del analista con su ORDER BY
-- de 20260930190028 (c166b286…) y el gate H3 con su sello de G4a (6aecb25a…); retira la v3 y el
-- núcleo de 6 argumentos. No toca tablas, datos ni policies.
--
-- ⚠️ Antes de correrla, el front publicado NO debe llamar a crm.gestion_diaria_pendientes_v3_fn
-- (pasaría a PGRST202): revertir PRIMERO el front (release anterior) y después esto. Las pestañas
-- que sigan abiertas con el bundle nuevo (Codex, 20/10/2026) llaman a la v3 hasta recargar: el
-- aviso de «versión publicada» del CRM les pide recargar en cuanto cambia version.json; conviene
-- correr esta reversa pasado ese rato (p. ej. al día siguiente), no en el mismo minuto que el front.
-- Mientras la v3 siga instalada no hace daño: solo el bundle nuevo la llama.
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
  -- Los COMMENT vuelven a los que vivían en producción el 20/10/2026 (la migración los fijó en su preflight).
  if pg_catalog.obj_description('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)'::regprocedure, 'pg_proc')
       is distinct from 'Núcleo H3+G4a: tareas actuales de un analista del ámbito de quien consulta (Supervisión: su árbol; Gerencia: toda la operación visible). INVOKER bajo RLS; cursor vence_en/id; supervisor_id = quien consulta.'
     or pg_catalog.obj_description('crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text)'::regprocedure, 'pg_proc')
       is distinct from 'Cola completa del propio analista: pendientes antes de gestionados, avance por actividad vigente en Lima, filtro y pagina anclada por clave. DEFINER porque compone ayudantes privados sin grants API; actor exclusivamente auth.uid().' then
    raise exception 'REVERSA pendientes recientes: el COMMENT del núcleo o de la cola no es el anterior';
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

## prueba-banco.sql actual
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
-- 15 vencidas (hace 1..15 h), 8 futuras (dentro de 1..8 h, ids 16..23) y un EMPATE exacto de vence_en (ids 24 y 25, hace 30 h): 25 pendientes.
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
-- También con cursor intermedio (lo que usan los bundles publicados al «Cargar más»): misma segunda página que G4a, en Todas y en Vencidas.
select pg_temp.afirmar(pg_temp.core_g4a(a.v1, false, 7, (c1->'siguiente_cursor'->>'despues_de')::timestamptz, (c1->'siguiente_cursor'->>'despues_id')::uuid)
    = private.gestion_diaria_pendientes_core(a.v1, false, 7, (c1->'siguiente_cursor'->>'despues_de')::timestamptz, (c1->'siguiente_cursor'->>'despues_id')::uuid)
  and pg_temp.core_g4a(a.v1, true, 5, (c2->'siguiente_cursor'->>'despues_de')::timestamptz, (c2->'siguiente_cursor'->>'despues_id')::uuid)
    = crm.gestion_diaria_pendientes_fn(a.v1, true, 5, (c2->'siguiente_cursor'->>'despues_de')::timestamptz, (c2->'siguiente_cursor'->>'despues_id')::uuid)
  and (c1->>'hay_mas')::boolean and (c2->>'hay_mas')::boolean,
  'ascendente con cursor: envoltorio y v1 = G4a en la segunda página')
from pr_actores a, lateral (select pg_temp.core_g4a(a.v1, false, 7, null, null) c1, pg_temp.core_g4a(a.v1, true, 5, null, null) c2) q;
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
-- El empate exacto de vence_en (ids 24 y 25, las dos más viejas) se desempata por id DESCENDENTE: 25 antes que 24, al final.
select pg_temp.afirmar((pg_temp.ids(v3->'items'))[24:25] = array['c0000000-0000-4000-8000-000000000025', 'c0000000-0000-4000-8000-000000000024']::uuid[],
  'empate: id descendente')
from pr_actores a, lateral (select crm.gestion_diaria_pendientes_v3_fn(a.v1, false, 100) v3) q;
-- El empate CRUZA un borde de página (auditor-rls): solo vencidas, 16 por página → la página 1 termina en el 25 y la 2 es EXACTAMENTE el 24
-- (mismo vence_en que el cursor, id menor). Un cursor que ignorara el id perdería o repetiría esa fila.
select pg_temp.afirmar(jsonb_array_length(p1->'items') = 16 and (p1->>'hay_mas')::boolean
    and p1->'siguiente_cursor'->>'despues_id' = 'c0000000-0000-4000-8000-000000000025'
    and pg_temp.ids(p2->'items') = array['c0000000-0000-4000-8000-000000000024']::uuid[] and (p2->>'hay_mas')::boolean = false,
  'empate en el borde de página: la segunda página es exactamente el id 24')
from pr_actores a, lateral (select crm.gestion_diaria_pendientes_v3_fn(a.v1, true, 16) p1) q1,
  lateral (select crm.gestion_diaria_pendientes_v3_fn(a.v1, true, 16, (q1.p1->'siguiente_cursor'->>'despues_de')::timestamptz, (q1.p1->'siguiente_cursor'->>'despues_id')::uuid) p2) q2;
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

## Diff del front, matriz RLS y arnés de la cola desde la ronda 1
```diff
diff --git a/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-api.test.ts b/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-api.test.ts
index 2630db74..6672988c 100644
--- a/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-api.test.ts
+++ b/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-api.test.ts
@@ -13,9 +13,16 @@ describe('Puerta de pendientes', () => {
   it('pide sólo el ámbito y límite; transmite abort; no usa la cartera del navegador', async () => {
     const signal = new AbortController().signal
     expect(await listarPendientesSupervisor(pedidoPendientes, signal)).toEqual(dobles.data)
-    expect(dobles.rpc).toHaveBeenCalledWith('gestion_diaria_pendientes_v2_fn', { p_analista_id: pedidoPendientes.analista, p_solo_vencidas: false, p_limite: 25 })
+    expect(dobles.rpc).toHaveBeenCalledWith('gestion_diaria_pendientes_v3_fn', { p_analista_id: pedidoPendientes.analista, p_solo_vencidas: false, p_limite: 25 })
     expect(dobles.abort).toHaveBeenCalledWith(signal)
   })
+  it('con cursor manda las dos mitades («después» = más antiguo que la última fila)', async () => {
+    const cursor = { despues_de: '2026-09-23T15:00:00.000001+00:00', despues_id: pedidoPendientes.analista }
+    dobles.data = paginaPendientes([], { resumen: { tareas_pendientes: 1, tareas_vencidas: 1 } })
+    await listarPendientesSupervisor({ ...pedidoPendientes, cursor })
+    expect(dobles.rpc).toHaveBeenCalledWith('gestion_diaria_pendientes_v3_fn',
+      { p_analista_id: pedidoPendientes.analista, p_solo_vencidas: false, p_limite: 25, p_despues_de: cursor.despues_de, p_despues_id: cursor.despues_id })
+  })
   it.each(['42501', 'PGRST202', '22023', 'XX000'])('preserva %s sin convertirlo en vacío', async code => {
     dobles.error = { code, message: 'Error controlado' }
     await expect(listarPendientesSupervisor(pedidoPendientes)).rejects.toMatchObject({ code })
diff --git a/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-queries.ts b/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-queries.ts
index 96a32f31..0676f655 100644
--- a/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-queries.ts
+++ b/CRM-Avance-Corp/app/src/data/gestion-diaria-pendientes-queries.ts
@@ -64,10 +64,15 @@ export function usePendientesSupervisor(dia: string, analista: string, soloVenci
     cliente.setQueriesData({ queryKey: ambitoClave }, { pages: [], pageParams: [] })
   }, [denegada, cliente, ambitoClave])
   const paginas = autorizado && !sinPermiso ? consulta.data?.pages ?? [] : []
-  const ultima = paginas.at(-1)
+  // La foto es la de la PRIMERA página (resumen y corte `pendientes_al`): con el orden de lo más
+  // reciente a lo más antiguo (v3), lo que vence entre una página y la siguiente queda por encima
+  // del cursor y no se recorre hasta «Actualizar»; el resumen de la última página lo contaría y la
+  // lista no cuadraría (auditor-rls, 20/10/2026). Las páginas siguientes son todas anteriores al
+  // corte de la primera, así que el corte sigue valiendo para marcar «Vencida».
+  const primera = paginas[0]
   return {
-    items: unirPaginasPendientes(paginas), pagina: ultima ?? null,
-    congelada: paginas.length > 1, consultadoDesde: paginas[0]?.generado_en ?? null,
+    items: unirPaginasPendientes(paginas), pagina: primera ?? null,
+    congelada: paginas.length > 1, consultadoDesde: primera?.generado_en ?? null,
     cargando: autorizado && !sinPermiso && consulta.isPending,
     enVuelo: consulta.isFetching, error: sinPermiso ? new CrmApiError('Ya no tienes acceso a estas tareas.', '42501') : consulta.error,
     sinPermiso, hayMas: !sinPermiso && !consulta.error && consulta.hasNextPage,
diff --git a/CRM-Avance-Corp/app/src/lib/gestion-diaria-pendientes.test.ts b/CRM-Avance-Corp/app/src/lib/gestion-diaria-pendientes.test.ts
index dd25535a..ec05c841 100644
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
@@ -25,36 +26,56 @@ describe('Contrato estricto de pendientes del supervisor', () => {
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
-    const nueva = tareaPendiente(10, { vence_en: '2026-09-25T15:00:00Z' })
-    expect(unirPaginasPendientes([paginaPendientes([tareaPendiente(10), tareaPendiente(11)]), paginaPendientes([nueva])])).toEqual([tareaPendiente(11), nueva])
+  it('una tarea reprogramada entre páginas aparece una sola vez con su última fecha, en su sitio', () => {
+    // Reprogramada a una fecha ANTERIOR (hacia donde avanza el cursor): el servidor la vuelve a entregar en una página
+    // posterior y gana su última foto. (Reprogramada hacia adelante queda por encima del cursor y sólo entra al Actualizar.)
+    const nueva = tareaPendiente(10, { vence_en: '2026-09-21T15:00:00Z' })
+    expect(unirPaginasPendientes([paginaPendientes([tareaPendiente(11), tareaPendiente(10)]), paginaPendientes([nueva])])).toEqual([tareaPendiente(11), nueva])
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
diff --git a/CRM-Avance-Corp/supabase/scripts/gestion-diaria-cola/ensayar.mjs b/CRM-Avance-Corp/supabase/scripts/gestion-diaria-cola/ensayar.mjs
index 51c61e8e..bf78e1ab 100644
--- a/CRM-Avance-Corp/supabase/scripts/gestion-diaria-cola/ensayar.mjs
+++ b/CRM-Avance-Corp/supabase/scripts/gestion-diaria-cola/ensayar.mjs
@@ -3,13 +3,19 @@ import assert from 'node:assert/strict';
 import { sql, db, ejecutar, objeto, q } from './banco.mjs';
 
 const migracion = readFileSync(new URL('../../migrations/20260930190028_crm_gestion_diaria_cola_trabajo.sql', import.meta.url), 'utf8');
+// 20261020214445 (20/10/2026): la cola cambió SOLO su ORDER BY (lo más reciente primero, salvo
+// «Hoy»); se instala ese cuerpo encima del de 20260930190028 para ensayar lo que está vivo.
+const recientes = readFileSync(new URL('../../migrations/20261020214445_crm_gestion_diaria_pendientes_recientes_primero.sql', import.meta.url), 'utf8');
+const cola = recientes.slice(recientes.indexOf('CREATE OR REPLACE FUNCTION crm.gestion_diaria_cola_trabajo_fn('), recientes.indexOf('-- 5) Gate H3'));
+assert.ok(cola.includes('$function$;') && cola.includes('comment on function crm.gestion_diaria_cola_trabajo_fn'), 'cuerpo de la cola de 20261020214445');
 sql(`begin;
   drop function if exists crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text);
   drop function if exists private.gestion_diaria_cola_filas(uuid,text,timestamptz);
   drop function if exists private.gestion_diaria_cola_hechos(uuid,timestamptz);
   ${migracion.replace(/^begin;$/m, '').replace(/^commit;$/m, '')}
+  ${cola}
   commit;`);
-console.log(`PASS: migración instalada en ${db}`);
+console.log(`PASS: migración instalada en ${db} (cola con el orden de 20261020214445)`);
 const actores = objeto("select jsonb_object_agg(rol_crm,perfil_id) from crm.equipo where activo and rol_crm in ('vendedor','gerencia')");
 for (const [caso, actor, rol, consulta, error] of [
   ['filtro inválido', actores.vendedor, 'authenticated', "crm.gestion_diaria_cola_trabajo_fn('invalido')", '22023'],
diff --git a/CRM-Avance-Corp/supabase/scripts/gestion-diaria-cola/prueba.sql b/CRM-Avance-Corp/supabase/scripts/gestion-diaria-cola/prueba.sql
index 45490017..af79a572 100644
--- a/CRM-Avance-Corp/supabase/scripts/gestion-diaria-cola/prueba.sql
+++ b/CRM-Avance-Corp/supabase/scripts/gestion-diaria-cola/prueba.sql
@@ -55,27 +55,28 @@ select set_config('request.jwt.claim.sub',vendedor::text,true) is not null from
 set local role authenticated;
 insert into g_respuestas values ('antes',crm.gestion_diaria_cola_trabajo_fn('sin_conversacion',0,8));
 select pg_temp.comprobar((valor->>'total')::integer=530,'cola completa superior a 500') from g_respuestas where clave='antes';
-select pg_temp.comprobar(valor#>>'{items,0,lead_id}'=(select id::text from g_leads where n=1),'primero antes de gestionar') from g_respuestas where clave='antes';
-insert into g_respuestas select 'llamada1',crm.registrar_llamada_v4(gen_random_uuid(),id,'no_contesto') from g_leads where n=1;
+-- Sin conversación va de lo más reciente a lo más antiguo (20261020214445): el n=530 (última conversación más reciente) primero.
+select pg_temp.comprobar(valor#>>'{items,0,lead_id}'=(select id::text from g_leads where n=530),'primero antes de gestionar') from g_respuestas where clave='antes';
+insert into g_respuestas select 'llamada1',crm.registrar_llamada_v4(gen_random_uuid(),id,'no_contesto') from g_leads where n=530;
 insert into g_respuestas values ('despues1',crm.gestion_diaria_cola_trabajo_fn('sin_conversacion',0,8));
-select pg_temp.comprobar(valor#>>'{items,0,lead_id}'=(select id::text from g_leads where n=2),'siguiente pendiente tras guardar') from g_respuestas where clave='despues1';
+select pg_temp.comprobar(valor#>>'{items,0,lead_id}'=(select id::text from g_leads where n=529),'siguiente pendiente tras guardar') from g_respuestas where clave='despues1';
 select pg_temp.comprobar((valor#>>'{totales,sin_conversacion,gestionados}')::integer=1,'una gestión confirmada') from g_respuestas where clave='despues1';
-insert into g_respuestas select 'anclada1',crm.gestion_diaria_cola_trabajo_fn('sin_conversacion',0,8,'lead:'||id) from g_leads where n=1;
-select pg_temp.comprobar((valor->>'pagina')::integer=66 and valor#>>'{items,1,lead_id}'=(select id::text from g_leads where n=1),
+insert into g_respuestas select 'anclada1',crm.gestion_diaria_cola_trabajo_fn('sin_conversacion',0,8,'lead:'||id) from g_leads where n=530;
+select pg_temp.comprobar((valor->>'pagina')::integer=66 and valor#>>'{items,1,lead_id}'=(select id::text from g_leads where n=530),
   'el gestionado está en la última página completa') from g_respuestas where clave='anclada1';
 select pg_temp.comprobar(valor#>>'{items,1,ultima_gestion,resultado}'='no_contesto' and
   (valor#>>'{items,1,senal,dias_sin_conversacion}')::integer>=37,'resultado visible sin reiniciar conversación') from g_respuestas where clave='anclada1';
 select 'GESTION_COLA_FIXTURE:'||valor::text from g_respuestas where clave='anclada1';
-insert into g_respuestas select 'llamada2',crm.registrar_llamada_v4(gen_random_uuid(),id,'no_contesto') from g_leads where n=2;
-insert into g_respuestas select 'reintento1',crm.registrar_llamada_v4(gen_random_uuid(),id,'no_contesto') from g_leads where n=1;
+insert into g_respuestas select 'llamada2',crm.registrar_llamada_v4(gen_random_uuid(),id,'no_contesto') from g_leads where n=529;
+insert into g_respuestas select 'reintento1',crm.registrar_llamada_v4(gen_random_uuid(),id,'no_contesto') from g_leads where n=530;
 insert into g_respuestas values ('ultima',crm.gestion_diaria_cola_trabajo_fn('sin_conversacion',66,8));
-select pg_temp.comprobar(valor#>>'{items,0,lead_id}'=(select id::text from g_leads where n=2)
-  and valor#>>'{items,1,lead_id}'=(select id::text from g_leads where n=1)
+select pg_temp.comprobar(valor#>>'{items,0,lead_id}'=(select id::text from g_leads where n=529)
+  and valor#>>'{items,1,lead_id}'=(select id::text from g_leads where n=530)
   and (valor#>>'{totales,sin_conversacion,gestionados}')::integer=2,'dos leads, tres llamadas; el último atendido queda último') from g_respuestas where clave='ultima';
 
--- Siguiente cruza el límite de la página y recorre todos los pendientes.
+-- Siguiente cruza el límite de la página y recorre todos los pendientes (hacia lo más antiguo: tras el n=10 viene el n=9).
 insert into g_respuestas select 'salto',crm.gestion_diaria_cola_trabajo_fn('sin_conversacion',0,8,'lead:'||id) from g_leads where n=10;
-select pg_temp.comprobar(valor->>'siguiente'='lead:'||(select id::text from g_leads where n=11),'siguiente entre páginas') from g_respuestas where clave='salto';
+select pg_temp.comprobar(valor->>'siguiente'='lead:'||(select id::text from g_leads where n=9),'siguiente entre páginas') from g_respuestas where clave='salto';
 
 -- Una clave ajena no amplía el ámbito y no provoca una diferencia de error.
 insert into g_respuestas select 'ajeno',crm.gestion_diaria_cola_trabajo_fn('todo',0,200,'lead:'||id) from g_leads where n=531;
@@ -94,8 +95,8 @@ select pg_temp.comprobar(exists(select 1 from jsonb_array_elements(valor->'items
   and f.value->>'estado_trabajo'='programado'),'reintento futuro fuera de pendientes') from g_respuestas where clave='programada_hoy';
 
 select crm.deshacer_resultado_llamada((valor->>'actividad_id')::uuid)->>'ok' from g_respuestas where clave='llamada2';
-insert into g_respuestas select 'deshecha',crm.gestion_diaria_cola_trabajo_fn('todo',0,8,'lead:'||id) from g_leads where n=2;
-select pg_temp.comprobar(exists(select 1 from jsonb_array_elements(valor->'items') f where f.value->>'lead_id'=(select id::text from g_leads where n=2)
+insert into g_respuestas select 'deshecha',crm.gestion_diaria_cola_trabajo_fn('todo',0,8,'lead:'||id) from g_leads where n=529;
+select pg_temp.comprobar(exists(select 1 from jsonb_array_elements(valor->'items') f where f.value->>'lead_id'=(select id::text from g_leads where n=529)
   and f.value->>'estado_trabajo'='pendiente' and f.value->'ultima_gestion'='null'::jsonb),'deshacer recalcula avance') from g_respuestas where clave='deshecha';
 reset role;
 
diff --git a/CRM-Avance-Corp/supabase/scripts/test-rls.mjs b/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
index e97fa39d..f1d5a919 100644
--- a/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
+++ b/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
@@ -8784,6 +8784,43 @@ async function testGestionDiariaPendientes(sessions, seed) {
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
+  for (const [extra, etiqueta] of [[{ p_limite: 0 }, 'límite 0'], [{ p_limite: 101 }, 'límite 101'], [{ p_despues_de: new Date().toISOString() }, 'cursor a medias']]) {
+    const { error } = await rpc3('gerencia', id('vend1'), extra);
+    check(error?.code === '22023', `gerencia: v3 con ${etiqueta} → 22023`);
+  }
 }
 
 // G4b (28/09/2026): lista exacta de «Citas agendadas». Ámbito explícito decidido en el

```

## Tu respuesta de la ronda 1
**VERDICT: CHANGES_REQUESTED**

**SUMMARY:** El orden SQL y el cursor compuesto son coherentes para una población estable. No identifico una nueva fuga de autorización en el código mostrado. Los problemas principales están en la compatibilidad de sesiones durante la publicación y la reversa; también hay una laguna concreta en las pruebas del cursor.

**FINDINGS**

**[P1] Revertir el front no retira los bundles v3 que siguen abiertos.**

Evidencia: [reversa.sql](/Users/usuario/dev/avancecorp-crm-orden-pendientes-20261020/CRM-Avance-Corp/supabase/scripts/pendientes-recientes-20261020/reversa.sql) exige revertir primero el front y después ejecuta `drop function crm.gestion_diaria_pendientes_v3_fn(...)`. El nuevo `gestion-diaria-pendientes-api.ts` llama exclusivamente a esa puerta.

Una pestaña que haya cargado el bundle nuevo conserva esa llamada después de republicar el front anterior. Cuando consulte nuevamente, recibirá `PGRST202`. La secuencia documentada no acredita que esas sesiones hayan dejado de utilizar v3.

**Propuesta:** separar la reversión del front de la retirada definitiva de v3/core6. Conservarlos hasta retirar o recargar efectivamente las sesiones nuevas. Probar la reversa manteniendo abierta una pestaña con el bundle v3.

**[P2] La cola cambia de orden sin versionar y puede mezclar paginaciones durante la migración.**

Evidencia: la [migración](/Users/usuario/dev/avancecorp-crm-orden-pendientes-20261020/CRM-Avance-Corp/supabase/migrations/20261020214445_crm_gestion_diaria_pendientes_recientes_primero.sql) reemplaza `crm.gestion_diaria_cola_trabajo_fn`, conserva `'version',1` y pagina mediante `f.n>v_pagina*p_limite`. Con `p_elegido=NULL`, no existe ancla que compense el cambio.

Caso reproducible con cuatro pendientes del mismo grupo:

- Antes de migrar: orden `A,B,C,D`; página 0, límite 2 → `A,B`.
- Después de migrar: orden `D,C,B,A`; página 1 → `B,A`.

El recorrido repite dos filas y omite otras dos. La protección mediante v2/v3 cubre Pendientes del supervisor, pero no esta cola.

**Propuesta:** versionar también la puerta de la cola y conservar el contrato anterior para los bundles publicados, conforme a la regla arquitectónica indicada. Añadir una prueba de convivencia de ambos consumidores.

**[P2] El empate documentado no es un empate y ninguno de los recorridos corta el empate real.**

Evidencia: en [prueba-banco.sql](/Users/usuario/dev/avancecorp-crm-orden-pendientes-20261020/CRM-Avance-Corp/supabase/scripts/pendientes-recientes-20261020/prueba-banco.sql), la siembra asigna `now() + make_interval(hours => i - 15)` a los IDs 21 y 22: vencen dentro de seis y siete horas. Comprobar que 22 precede inmediatamente a 21 no prueba el desempate por ID.

El empate real está en 24 y 25, ambos a `now() - interval '30 hours'`. Quedan juntos en la última página tanto con límite 7 como con límite 5. `estricta` sí verifica su orden dentro de la página, pero no se ejercita el cursor entre filas de igual fecha.

**Propuesta:** comprobar explícitamente la igualdad de fechas de 24/25 y dividirlos entre páginas, por ejemplo con límite 24 en «Todas». Verificar que la segunda página devuelve exactamente la fila restante. Un mutante que elimine el ID de la condición del cursor debe fallar.

**[P3] La garantía de reversa exacta no incluye una línea base de los comentarios.**

Evidencia: el preflight compara `md5(pg_get_functiondef(...))`, dueño y ACL. Esa huella no incluye `COMMENT ON`. La reversa restaura comentarios históricos y comprueba el del núcleo contra un literal, sin haber comprobado que ese literal fuera el comentario vivo anterior.

Si únicamente hubiese cambiado un comentario en producción, las huellas seguirían coincidiendo y la reversa sobrescribiría ese cambio. Esto demuestra una garantía incompleta; no demuestra que el banco observado haya quedado diferente.

**Propuesta:** medir y validar los comentarios originales de núcleo y cola antes de migrar, y comprobar ambos después de revertir.

**RIESGOS / TEST GAPS**

- **La prueba de reprogramación no representa una segunda página válida.** En `gestion-diaria-pendientes.test.ts`, la tarea pasa del 23 al 25 de septiembre y se introduce en la página posterior. Con el cursor descendente, esa tarea quedaría antes del cursor y el servidor no la devolvería allí. El test acredita la unión aislada, no la recuperación de una reprogramación durante el recorrido. Además, `statement_timestamp()` cambia entre peticiones: una tarea recién vencida puede incorporarse por delante del cursor. Hace falta acreditar cómo se reinicia o refresca la lista ante esos cambios.
- **Hipótesis de concurrencia pendiente:** la migración indica que la resolución de identidad bloquea filas. v2 y v3 entregan las mismas tareas en órdenes opuestos. Si los ayudantes adquieren bloqueos incompatibles siguiendo ese orden, podrían producirse interbloqueos. Sus cuerpos no están transcritos: verificar un orden canónico de bloqueo independiente del orden recibido.
- **Verificación aportada:** PASS informado para banco, ciclo de reversa y 207 tests. H3 continúa en FAIL por la causa preexistente descrita. `npm run check` y los cuatro E2E siguen en curso; no se aporta resultado de la matriz RLS modificada. Ejecución independiente por este revisor: **NOT RUN**, conforme al encargo sin herramientas.

**NEXT ACTIONS**

1. Resolver la convivencia de versiones de la cola y la retirada segura de v3 durante la reversa.
2. Corregir la prueba de empate entre páginas y completar la comprobación de comentarios originales.
3. Cerrar los checks pendientes y ejecutar la matriz RLS exigiendo v3 mediante `CRM_RLS_EXIGE_GESTION_DIARIA=1`.

**CONFIDENCE: MEDIUM.** Los hallazgos se derivan del material transcrito; los bloqueos de identidad y los mecanismos globales de actualización de sesiones requieren evidencia adicional.


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


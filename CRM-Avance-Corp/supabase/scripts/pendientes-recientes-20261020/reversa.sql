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

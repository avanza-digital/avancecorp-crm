-- Proyección de citas (19/10/2026), Fase 0b: las reuniones con CLIENTES que no
-- tienen lead entran a la pestaña «Proyección». Decisión de Miguel (19/10): en
-- octubre hubo reuniones con clientes que la Proyección no veía porque el lector
-- de Citas (`private.citas_gerencia_consulta`) sólo recorre tareas con lead; la
-- sección «Citas de clientes» (`private.citas_clientes_core`) sí las lista, pero
-- paginadas y por fecha programada. Plan en el vault: «Citas - proyeccion semanal
-- y diaria por analista, plan (2026-10-19)».
--
-- Qué hace: un lector NUEVO y aditivo, propio de la Proyección.
--   · núcleo `private.citas_clientes_proyeccion(date,date)` (SECURITY DEFINER,
--     search_path vacío, VOLATILE a propósito: autoriza con
--     `private.gestiones_validar`, que toma candados de transacción, y consulta
--     `crm.postventa_estado_fn()`, que bloquea filas; en una transacción de solo
--     lectura de PostgREST no podría correr).
--   · puerta `crm.citas_clientes_proyeccion_fn(date,date)` (sql, INVOKER) que
--     sólo llama al núcleo.
-- Devuelve TODAS (sin paginar, tope 10 000 con error explícito) las reuniones
-- activas con cliente y sin lead (`perfil_id`, o `inversionista_id` cuando F6
-- está habilitada para quien consulta) cuyo `creado_en` cae, en día de Lima,
-- dentro de [p_desde, p_hasta]. Se cuenta por fecha de CREACIÓN, como la
-- Proyección cuenta las citas generadas, no por `vence_en`.
-- Alcance: el MISMO de `private.citas_clientes_core` (sesión real; vendedor,
-- supervisor o gerencia; responsable dentro de `private.vendedor_ids_visibles`;
-- las reuniones sin responsable sólo para gerencia). Analista y supervisor se
-- resuelven EXACTAMENTE como `private.citas_gerencia_consulta` (responsable
-- actual de la tarea; supervisor del equipo o, en su defecto, el asignado a la
-- tarea; mismos rótulos «Sin analista»/«Sin supervisor»). La identidad del
-- cliente sale tal cual de `private.gestiones_clientes_identidades` (misma
-- redacción de PII); `identidad_persona` sólo nombra a la persona cuando esa
-- función la deja visible y, si no, es `oculta:<id de la tarea>`.
--
-- Qué NO cambia: ningún lector existente (Resultados, Agenda, Bandeja, Citas de
-- clientes), ninguna tabla, policy ni índice. No usa agregados de conteo: no
-- entra al censo analítico (`private.contadores_crudos_leads_citas`), ni al de
-- vigencia del analista, ni nombra piezas cerradas de F7. El censo global está
-- en ROJO por piezas ajenas (19/10), así que, como 20261019170214, no se llama
-- al guardián: se guarda la foto de los dos censos y se exige que quede idéntica.
--
-- Instalación (Miguel, con `!`, un solo mensaje):
--   supabase db query --linked --file supabase/migrations/20261019213516_crm_citas_clientes_proyeccion.sql
--   supabase migration repair --status applied 20261019213516 --linked
-- Cómo se revierte: supabase/scripts/revertir-20261019213516-citas-clientes-proyeccion.sql
-- (drop de la puerta y del núcleo en una transacción, censos idénticos). Antes
-- de revertir, retirar del front cualquier llamada a la puerta.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';
set local search_path = pg_catalog;
-- Los dos ledgers de los censos no cambian mientras se toma y compara la foto.
lock table private.analitica_leads_citas_exenciones, private.analitica_lc_sello,
  private.analista_vigencia_exenciones in share mode;

create temporary table cc_proy_censo_antes on commit drop as
  select 'lc'::text as censo, c.tipo, c.objeto, c.declarada, c.huella_ok
  from private.contadores_crudos_leads_citas() c
  union all
  select 'vigencia', v.tipo, v.objeto, v.declarada, v.huella_ok
  from private.puertas_analista_sin_vigencia() v;

do $preflight$
begin
  if pg_catalog.to_regprocedure('private.citas_clientes_proyeccion(date,date)') is not null
     or pg_catalog.to_regprocedure('crm.citas_clientes_proyeccion_fn(date,date)') is not null then
    raise exception 'PREFLIGHT citas_clientes_proyeccion: el lector ya existe';
  end if;
  -- Autorización, redacción y las dos referencias de paridad (alcance de
  -- citas_clientes_core; analista/supervisor de citas_gerencia_consulta) tienen
  -- que ser EXACTAMENTE las ensayadas (md5 de prosrc medidos iguales en
  -- producción y en el banco el 19/10/2026). Si una cambió, conciliar antes.
  if exists (
    select 1
    from (values
      ('private.gestiones_validar(date,date,uuid[])', '9f9f8399062d970cddeeebb545969e18'),
      ('private.gestiones_clientes_identidades(jsonb)', '1607c892c8fb5cd2844e7b2ad0d70fab'),
      ('private.vendedor_ids_visibles(uuid)', '33ece9bae4828f7ffdb837c6128ca9d6'),
      ('private.rol_crm(uuid)', 'd2878a210be96ac85973d51dfcfb27a5'),
      ('crm.postventa_estado_fn()', '74cf97ec7ef00b076e5da0b2fe970056'),
      ('private.citas_clientes_core(date,date,uuid[],integer,timestamptz,uuid)', 'ebeb44803955df27105d4d93d19b844a'),
      ('private.citas_gerencia_consulta(date,date)', '676f078a7755583c10cb2611bc88eb0c')
    ) as d(objeto, md5_ensayado)
    where pg_catalog.to_regprocedure(d.objeto) is null
       or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
           where p.oid = pg_catalog.to_regprocedure(d.objeto)) is distinct from d.md5_ensayado
  ) then
    raise exception 'PREFLIGHT citas_clientes_proyeccion: una dependencia falta o cambió desde el ensayo; conciliar antes de aplicar';
  end if;
  if (select pg_catalog.count(*) from cc_proy_censo_antes) = 0 then
    raise exception 'PREFLIGHT citas_clientes_proyeccion: la foto de los censos salió vacía';
  end if;
end;
$preflight$;

create function private.citas_clientes_proyeccion(p_desde date, p_hasta date)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_ahora timestamptz := now();
  v_ids uuid[];
  v_gerencia boolean;
  v_f6 boolean;
  v_citas jsonb;
begin
  -- Sesión real; vendedor, supervisor o gerencia; rango válido de hasta un año.
  perform private.gestiones_validar(p_desde, p_hasta, null);
  v_ids := array(select private.vendedor_ids_visibles(v_uid));
  v_gerencia := coalesce(private.rol_crm(v_uid) = 'gerencia', false);
  v_f6 := coalesce((crm.postventa_estado_fn()->>'habilitada')::boolean, false);

  with base as materialized (
    -- Mismo alcance que private.citas_clientes_core, por fecha de creación.
    select t.id, t.creado_en, t.vence_en, t.estado, t.cancelada_por,
           t.vendedor_id, t.asignado_supervisor_id, t.perfil_id, t.inversionista_id
    from crm.tareas t
    where t.activo and t.tipo = 'reunion' and t.lead_id is null
      and (t.vendedor_id = any(v_ids) or (t.vendedor_id is null and v_gerencia))
      and (t.perfil_id is not null or (v_f6 and t.inversionista_id is not null))
      and t.creado_en >= p_desde::timestamp at time zone 'America/Lima'
      and t.creado_en < (p_hasta + 1)::timestamp at time zone 'America/Lima'
    -- La fila extra dispara un error: nunca se entrega una lista truncada.
    order by t.creado_en, t.id
    limit 10001
  ), asistencias as (
    -- Instante en que se registró la entrevista: cierre F6 de la tarea o
    -- actividad de cliente «realizada» enlazada a ella (la primera de ambas).
    select x.tarea_id, min(x.en) as en
    from (
      select g.tarea_id, g.creado_en as en
      from crm.inversionista_gestiones g join base b on b.id = g.tarea_id
      where g.tipo = 'cierre' and b.estado = 'completada'
        and coalesce(g.metadata->>'estado', b.estado) = 'completada'
      union all
      select a.tarea_id, a.creado_en
      from crm.actividades_cliente a join base b on b.id = a.tarea_id
      where a.tipo = 'reunion_realizada' and b.estado = 'completada'
    ) x
    where x.en <= v_ahora
    group by x.tarea_id
  ), sujetos as materialized (
    select * from private.gestiones_clientes_identidades(coalesce((
      select jsonb_agg(jsonb_build_object('persona', b.inversionista_id, 'perfil', b.perfil_id))
      from base b), '[]'::jsonb))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', b.id, 'creado_en', b.creado_en, 'vence_en', b.vence_en,
      'estado', b.estado, 'cancelada_por', b.cancelada_por,
      'asistencia_registrada_en', case when b.estado = 'completada' then a.en end,
      'analista_id', b.vendedor_id,
      'analista_nombre', coalesce(p.nombre_completo, 'Sin analista'),
      'supervisor_id', coalesce(e.supervisor_id, b.asignado_supervisor_id),
      'supervisor_nombre', coalesce(ps.nombre_completo, 'Sin supervisor'),
      'identidad_persona', case when (s.identidad->>'identidad_visible')::boolean is true
        then coalesce('persona:' || (s.identidad->>'inversionista_id'),
                      'perfil:' || (s.identidad->>'perfil_id'),
                      'oculta:' || b.id::text)
        else 'oculta:' || b.id::text end
    ) || coalesce(s.identidad, '{"identidad_visible":null}'::jsonb)
    order by b.creado_en, b.id), '[]'::jsonb)
  into v_citas
  from base b
  left join asistencias a on a.tarea_id = b.id
  left join sujetos s on s.persona is not distinct from b.inversionista_id
                     and s.perfil is not distinct from b.perfil_id
  left join public.perfiles p on p.id = b.vendedor_id
  left join crm.equipo e on e.perfil_id = b.vendedor_id
  left join public.perfiles ps on ps.id = coalesce(e.supervisor_id, b.asignado_supervisor_id);

  if jsonb_array_length(v_citas) > 10000 then
    raise exception 'La consulta supera el tamaño admitido; acota el rango' using errcode = '54000';
  end if;
  -- Toda fila sale con su identidad resuelta (visible o redactada), nunca sin ella.
  if exists (select 1 from jsonb_array_elements(v_citas) c
             where jsonb_typeof(c->'identidad_visible') is distinct from 'boolean') then
    raise exception 'Identidad de cliente sin resolver en la proyección' using errcode = 'XX000';
  end if;

  return jsonb_build_object('version', 1,
    'periodo', jsonb_build_object('desde', p_desde, 'hasta', p_hasta),
    'criterio', 'creado_en', 'generado_en', v_ahora, 'citas', v_citas);
end;
$function$;

create function crm.citas_clientes_proyeccion_fn(p_desde date, p_hasta date)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.citas_clientes_proyeccion(p_desde, p_hasta);
$function$;

alter function private.citas_clientes_proyeccion(date,date) owner to postgres;
alter function crm.citas_clientes_proyeccion_fn(date,date) owner to postgres;

-- ACL explícitas, como 20261006012208: la puerta es INVOKER, así que
-- authenticated necesita EXECUTE también sobre el núcleo (private no se expone
-- por la API; el núcleo vuelve a autorizar la sesión al invocarse).
revoke all on function private.citas_clientes_proyeccion(date,date),
  crm.citas_clientes_proyeccion_fn(date,date) from public, anon, authenticated, service_role;
grant execute on function private.citas_clientes_proyeccion(date,date),
  crm.citas_clientes_proyeccion_fn(date,date) to authenticated;

comment on function private.citas_clientes_proyeccion(date,date) is
  'Proyección de citas (Fase 0b, 19/10/2026): todas las reuniones activas con cliente y sin lead (perfil, o persona F6 si está habilitada) GENERADAS (creado_en, día de Lima) en el rango, sin paginar (tope 10 000 con error). Alcance de private.citas_clientes_core; analista y supervisor como private.citas_gerencia_consulta; identidad de private.gestiones_clientes_identidades (identidad_persona = oculta:<tarea> si no es visible). SECURITY DEFINER y VOLATILE (candados de gestiones_validar).';
comment on function crm.citas_clientes_proyeccion_fn(date,date) is
  'Puerta de la Proyección de citas para reuniones con clientes sin lead, por fecha de creación; sólo delega en private.citas_clientes_proyeccion.';

do $postflight$
declare
  v_fn record;
begin
  select p.prosecdef, p.provolatile, p.proconfig, r.rolname, l.lanname into v_fn
  from pg_catalog.pg_proc p
  join pg_catalog.pg_roles r on r.oid = p.proowner
  join pg_catalog.pg_language l on l.oid = p.prolang
  where p.oid = 'private.citas_clientes_proyeccion(date,date)'::regprocedure;
  if v_fn.rolname is distinct from 'postgres' or not v_fn.prosecdef
     or v_fn.provolatile is distinct from 'v' or v_fn.lanname is distinct from 'plpgsql'
     or v_fn.proconfig is distinct from array['search_path=""']::text[] then
    raise exception 'POSTFLIGHT citas_clientes_proyeccion: atributos inesperados en el núcleo';
  end if;
  select p.prosecdef, p.provolatile, p.proconfig, r.rolname, l.lanname into v_fn
  from pg_catalog.pg_proc p
  join pg_catalog.pg_roles r on r.oid = p.proowner
  join pg_catalog.pg_language l on l.oid = p.prolang
  where p.oid = 'crm.citas_clientes_proyeccion_fn(date,date)'::regprocedure;
  if v_fn.rolname is distinct from 'postgres' or v_fn.prosecdef
     or v_fn.provolatile is distinct from 'v' or v_fn.lanname is distinct from 'sql'
     or v_fn.proconfig is distinct from array['search_path=""']::text[] then
    raise exception 'POSTFLIGHT citas_clientes_proyeccion: atributos inesperados en la puerta';
  end if;
  -- EXECUTE exactamente para postgres y authenticated en las dos funciones.
  if exists (
    select 1 from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
    where p.oid in ('private.citas_clientes_proyeccion(date,date)'::regprocedure,
                    'crm.citas_clientes_proyeccion_fn(date,date)'::regprocedure)
      and (a.grantee not in ('postgres'::regrole::oid, 'authenticated'::regrole::oid)
           or a.privilege_type <> 'EXECUTE' or a.is_grantable)
  ) then
    raise exception 'POSTFLIGHT citas_clientes_proyeccion: ACL fuera de postgres/authenticated';
  end if;
  if pg_catalog.has_function_privilege('anon', 'crm.citas_clientes_proyeccion_fn(date,date)', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'private.citas_clientes_proyeccion(date,date)', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', 'crm.citas_clientes_proyeccion_fn(date,date)', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', 'private.citas_clientes_proyeccion(date,date)', 'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated', 'crm.citas_clientes_proyeccion_fn(date,date)', 'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated', 'private.citas_clientes_proyeccion(date,date)', 'EXECUTE') then
    raise exception 'POSTFLIGHT citas_clientes_proyeccion: permisos efectivos inesperados';
  end if;
  if pg_catalog.obj_description('private.citas_clientes_proyeccion(date,date)'::regprocedure, 'pg_proc') is null
     or pg_catalog.obj_description('crm.citas_clientes_proyeccion_fn(date,date)'::regprocedure, 'pg_proc') is null then
    raise exception 'POSTFLIGHT citas_clientes_proyeccion: falta COMMENT ON';
  end if;
  -- Los dos censos quedan EXACTAMENTE como estaban (ninguna de las dos entra).
  create temporary table cc_proy_censo_despues on commit drop as
    select 'lc'::text as censo, c.tipo, c.objeto, c.declarada, c.huella_ok
    from private.contadores_crudos_leads_citas() c
    union all
    select 'vigencia', v.tipo, v.objeto, v.declarada, v.huella_ok
    from private.puertas_analista_sin_vigencia() v;
  if exists ((select * from cc_proy_censo_antes except all select * from cc_proy_censo_despues)
             union all
             (select * from cc_proy_censo_despues except all select * from cc_proy_censo_antes)) then
    raise exception 'POSTFLIGHT citas_clientes_proyeccion: cambió un censo (analítico o de vigencia)';
  end if;
  if exists (select 1 from cc_proy_censo_despues d
             where d.objeto in ('private.citas_clientes_proyeccion(date,date)',
                                'crm.citas_clientes_proyeccion_fn(date,date)')) then
    raise exception 'POSTFLIGHT citas_clientes_proyeccion: el lector entró a un censo';
  end if;
  -- Ninguna de las dos nombra una pieza en observación o cerrada de F7.
  if exists (select 1 from private.f7_piezas_en_observacion r
             cross join pg_catalog.pg_proc p
             where r.estado in ('observacion', 'cerrada_permanente')
               and p.oid in ('private.citas_clientes_proyeccion(date,date)'::regprocedure,
                             'crm.citas_clientes_proyeccion_fn(date,date)'::regprocedure)
               and pg_catalog.lower(pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.regexp_replace(p.prosrc,
                     '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'), '"', '')) ~ r.patron_censo) then
    raise exception 'POSTFLIGHT citas_clientes_proyeccion: nombra una pieza cerrada de F7';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;

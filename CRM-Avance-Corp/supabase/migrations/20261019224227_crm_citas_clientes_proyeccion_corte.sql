-- Proyección de citas, Fase 0b — ENMIENDA (19/10/2026): corte coherente del lector de
-- reuniones con clientes sin lead. Se instala JUSTO DESPUÉS de 20261019213516, que no se
-- edita (ya está commiteada). Atiende la revisión de Codex LEVEL 3 sobre la 0b
-- (CHANGES_REQUESTED, docs/encargos/2026-10-19-codex-citas-clientes-proyeccion-0b-RESPUESTA.md):
--
-- 1) `generado_en` es `now()` (inicio de la transacción), pero la cohorte no exigía
--    `creado_en <= generado_en`: en READ COMMITTED, una reunión confirmada por otra sesión
--    después de ese instante entraba con `creado_en` posterior a `generado_en`, y el
--    consumidor (que exige esa coherencia) rechazaba el payload entero. Ahora `generado_en`
--    ES EL CORTE: el núcleo sólo devuelve reuniones creadas hasta ese instante (la asistencia
--    ya se cortaba igual). No cambia nada más: ni alcance, ni forma, ni ACL, ni la puerta.
-- 2) El preflight de la 0b acreditaba las dependencias sólo por md5(prosrc), que no ve los
--    atributos: `ALTER FUNCTION private.gestiones_validar(...) STRICT` desactiva la validación
--    (la llamada pasa NULL) sin cambiar ese hash. Esta enmienda acredita por IDENTIDAD
--    COMPLETA: md5(pg_get_functiondef) (incluye STRICT, SECURITY DEFINER, SET y volatilidad)
--    + propietario + ACL, de las siete dependencias (medidas iguales en producción y en el
--    banco el 19/10/2026) y de las dos funciones de la 0b tal como se commitearon (00c32abb).
--
-- Si esta enmienda se niega tras instalar la 0b, NO forzar: revertir la 0b
-- (supabase/scripts/revertir-20261019213516-citas-clientes-proyeccion.sql) y conciliar.
--
-- Instalación (Miguel, con `!`, después de la 0b):
--   supabase db query --linked --file supabase/migrations/20261019224227_crm_citas_clientes_proyeccion_corte.sql
--   supabase migration repair --status applied 20261019224227 --linked
-- Cómo se revierte: supabase/scripts/revertir-20261019224227-citas-clientes-proyeccion-corte.sql
-- (devuelve el núcleo al cuerpo EXACTO de la 0b); para quitarlo todo, después la reversión de la 0b.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';
set local search_path = pg_catalog;
lock table private.analitica_leads_citas_exenciones, private.analitica_lc_sello,
  private.analista_vigencia_exenciones in share mode;

create temporary table cc_corte_censo_antes on commit drop as
  select 'lc'::text as censo, c.tipo, c.objeto, c.declarada, c.huella_ok
  from private.contadores_crudos_leads_citas() c
  union all
  select 'vigencia', v.tipo, v.objeto, v.declarada, v.huella_ok
  from private.puertas_analista_sin_vigencia() v;

do $preflight$
begin
  -- La 0b instalada EXACTAMENTE como se commiteó (identidad completa ensayada en el banco).
  if exists (
    select 1
    from (values
    ('private.citas_clientes_proyeccion(date,date)', 'ac59c50fc9a3bdca3f2ca277c860b1b4'),
    ('crm.citas_clientes_proyeccion_fn(date,date)', 'a9b640342d51a77dafe42b37fe2fa6a4')
    ) as d(objeto, md5_def)
    left join pg_catalog.pg_proc p on p.oid = pg_catalog.to_regprocedure(d.objeto)
    where p.oid is null
       or pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) is distinct from d.md5_def
       or p.proowner is distinct from 'postgres'::regrole::oid
       or p.proacl::text is distinct from '{postgres=X/postgres,authenticated=X/postgres}'
  ) then
    raise exception 'PREFLIGHT corte: el lector 0b no está instalado exactamente como se commiteó (20261019213516); conciliar antes de aplicar';
  end if;
  -- Las siete dependencias con su IDENTIDAD COMPLETA (cuerpo, STRICT, DEFINER, SET, volatilidad, dueño y ACL).
  if exists (
    select 1
    from (values
    ('private.gestiones_validar(date,date,uuid[])', '10d9cc942ccad196a883641f9ddf55c0'),
    ('private.gestiones_clientes_identidades(jsonb)', '0023331bba7faf6ea232d572d7ecf2c2'),
    ('private.vendedor_ids_visibles(uuid)', '85544c70a0920f3a7a1b5da06935f236'),
    ('private.rol_crm(uuid)', '99827f3fe2fbc3cfae5668c30015c758'),
    ('crm.postventa_estado_fn()', '2d1e2176a210fae2ec12215447ea8c0f'),
    ('private.citas_clientes_core(date,date,uuid[],integer,timestamptz,uuid)', '40e11225ae6ec73defd7ec21f8f433a2'),
    ('private.citas_gerencia_consulta(date,date)', 'e8c51315f6f2a9be82733850428f7a4f')
    ) as d(objeto, md5_def)
    left join pg_catalog.pg_proc p on p.oid = pg_catalog.to_regprocedure(d.objeto)
    where p.oid is null
       or pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) is distinct from d.md5_def
       or p.proowner is distinct from 'postgres'::regrole::oid
       or p.proacl::text is distinct from '{postgres=X/postgres,authenticated=X/postgres}'
  ) then
    raise exception 'PREFLIGHT corte: una dependencia falta o cambió (cuerpo, STRICT, DEFINER, SET, volatilidad, dueño o ACL); conciliar antes de aplicar';
  end if;
  if (select pg_catalog.count(*) from cc_corte_censo_antes) = 0 then
    raise exception 'PREFLIGHT corte: la foto de los censos salió vacía';
  end if;
end;
$preflight$;

create or replace function private.citas_clientes_proyeccion(p_desde date, p_hasta date)
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
      -- Corte coherente (20261019224227): sólo lo creado hasta generado_en.
      and t.creado_en <= v_ahora
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

-- Misma ACL que la 0b (create or replace la conserva; se reafirma explícitamente).
revoke all on function private.citas_clientes_proyeccion(date,date) from public, anon, authenticated, service_role;
grant execute on function private.citas_clientes_proyeccion(date,date) to authenticated;

comment on function private.citas_clientes_proyeccion(date,date) is
  'Proyección de citas (Fase 0b, 19/10/2026; corte 20261019224227): todas las reuniones activas con cliente y sin lead (perfil, o persona F6 si está habilitada) GENERADAS (creado_en, día de Lima) en el rango y hasta generado_en (corte coherente: inicio de la transacción), sin paginar (tope 10 000 con error). Alcance de private.citas_clientes_core; analista y supervisor como private.citas_gerencia_consulta; identidad de private.gestiones_clientes_identidades (identidad_persona = oculta:<tarea> si no es visible). SECURITY DEFINER y VOLATILE (candados de gestiones_validar).';

do $postflight$
declare
  v_fn record;
begin
  -- El núcleo es EXACTAMENTE el ensayado y la puerta sigue como en la 0b.
  if exists (
    select 1
    from (values
    ('private.citas_clientes_proyeccion(date,date)', '44006907908162603701c82521359b35'),
    ('crm.citas_clientes_proyeccion_fn(date,date)', 'a9b640342d51a77dafe42b37fe2fa6a4')
    ) as d(objeto, md5_def)
    left join pg_catalog.pg_proc p on p.oid = pg_catalog.to_regprocedure(d.objeto)
    where p.oid is null
       or pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) is distinct from d.md5_def
       or p.proowner is distinct from 'postgres'::regrole::oid
       or p.proacl::text is distinct from '{postgres=X/postgres,authenticated=X/postgres}'
  ) then
    raise exception 'POSTFLIGHT corte: el núcleo o la puerta no quedaron con la identidad ensayada';
  end if;
  select p.prosecdef, p.provolatile, p.proisstrict, p.proconfig, l.lanname into v_fn
  from pg_catalog.pg_proc p join pg_catalog.pg_language l on l.oid = p.prolang
  where p.oid = 'private.citas_clientes_proyeccion(date,date)'::regprocedure;
  if not v_fn.prosecdef or v_fn.provolatile is distinct from 'v' or v_fn.proisstrict
     or v_fn.lanname is distinct from 'plpgsql'
     or v_fn.proconfig is distinct from array['search_path=""']::text[] then
    raise exception 'POSTFLIGHT corte: atributos inesperados en el núcleo';
  end if;
  if pg_catalog.has_function_privilege('anon', 'private.citas_clientes_proyeccion(date,date)', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', 'private.citas_clientes_proyeccion(date,date)', 'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated', 'crm.citas_clientes_proyeccion_fn(date,date)', 'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated', 'private.citas_clientes_proyeccion(date,date)', 'EXECUTE') then
    raise exception 'POSTFLIGHT corte: permisos efectivos inesperados';
  end if;
  if coalesce(pg_catalog.strpos(pg_catalog.obj_description('private.citas_clientes_proyeccion(date,date)'::regprocedure, 'pg_proc'), 'corte 20261019224227'), 0) = 0 then
    raise exception 'POSTFLIGHT corte: falta el COMMENT ON del núcleo';
  end if;
  -- Las dependencias no cambiaron durante la instalación.
  if exists (
    select 1
    from (values
    ('private.gestiones_validar(date,date,uuid[])', '10d9cc942ccad196a883641f9ddf55c0'),
    ('private.gestiones_clientes_identidades(jsonb)', '0023331bba7faf6ea232d572d7ecf2c2'),
    ('private.vendedor_ids_visibles(uuid)', '85544c70a0920f3a7a1b5da06935f236'),
    ('private.rol_crm(uuid)', '99827f3fe2fbc3cfae5668c30015c758'),
    ('crm.postventa_estado_fn()', '2d1e2176a210fae2ec12215447ea8c0f'),
    ('private.citas_clientes_core(date,date,uuid[],integer,timestamptz,uuid)', '40e11225ae6ec73defd7ec21f8f433a2'),
    ('private.citas_gerencia_consulta(date,date)', 'e8c51315f6f2a9be82733850428f7a4f')
    ) as d(objeto, md5_def)
    left join pg_catalog.pg_proc p on p.oid = pg_catalog.to_regprocedure(d.objeto)
    where p.oid is null
       or pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) is distinct from d.md5_def
       or p.proowner is distinct from 'postgres'::regrole::oid
       or p.proacl::text is distinct from '{postgres=X/postgres,authenticated=X/postgres}'
  ) then
    raise exception 'POSTFLIGHT corte: cambió una dependencia durante la instalación';
  end if;
  -- Los dos censos quedan EXACTAMENTE como estaban.
  create temporary table cc_corte_censo_despues on commit drop as
    select 'lc'::text as censo, c.tipo, c.objeto, c.declarada, c.huella_ok
    from private.contadores_crudos_leads_citas() c
    union all
    select 'vigencia', v.tipo, v.objeto, v.declarada, v.huella_ok
    from private.puertas_analista_sin_vigencia() v;
  if exists ((select * from cc_corte_censo_antes except all select * from cc_corte_censo_despues)
             union all
             (select * from cc_corte_censo_despues except all select * from cc_corte_censo_antes)) then
    raise exception 'POSTFLIGHT corte: cambió un censo (analítico o de vigencia)';
  end if;
  if exists (select 1 from private.f7_piezas_en_observacion r
             cross join pg_catalog.pg_proc p
             where r.estado in ('observacion', 'cerrada_permanente')
               and p.oid = 'private.citas_clientes_proyeccion(date,date)'::regprocedure
               and pg_catalog.lower(pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.regexp_replace(p.prosrc,
                     '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'), '"', '')) ~ r.patron_censo) then
    raise exception 'POSTFLIGHT corte: el núcleo nombra una pieza cerrada de F7';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;

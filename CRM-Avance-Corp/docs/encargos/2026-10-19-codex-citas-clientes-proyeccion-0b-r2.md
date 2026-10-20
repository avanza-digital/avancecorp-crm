ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo (LEVEL 3, SEGUNDA y última pasada): REFUTA la enmienda `20261019224227_crm_citas_clientes_proyeccion_corte.sql`

En tu primera pasada sobre `20261019213516_crm_citas_clientes_proyeccion.sql` (lector nuevo de reuniones con clientes sin lead para la Proyección de Citas) diste CHANGES_REQUESTED con tres hallazgos, todos aceptados:
1. P2: el preflight solo comparaba `md5(prosrc)` de las dependencias; un `ALTER FUNCTION private.gestiones_validar(...) STRICT` desactivaba la validación sin cambiar ese hash.
2. P2: `generado_en = now()` (inicio de la transacción) sin cortar la cohorte; una reunión creada después hacía rechazar el payload en el front (`creado_en <= generado_en`).
3. P3: la batería imprimía FAIL sin fallar y no exigía 54000 en el tope.

Como la 0b ya estaba commiteada (regla de la casa: una migración commiteada no se edita), la corrección va en una migración NUEVA que se instala justo después de la 0b. Abajo: la enmienda, su reversión, la entrada del ledger y la batería nueva.

Verificación reportada por el implementador (NOT RUN por ti): banco Docker con el esquema de producción; batería 53/53 PASS (código 0 sobre 0b + enmienda; código 3 sobre la 0b sola); 9/9 mutantes muertos (incluido tu contraejemplo STRICT: la 0b se instala igual y devuelve `[]` con rango invertido, la enmienda se niega); dos sesiones reales (la reunión creada 1,5 s después del inicio de la transacción queda fuera con la enmienda); `tareas_un_solo_sujeto` (`num_nonnulls(lead_id, perfil_id, inversionista_id) = 1`) impide una reunión con lead Y cliente (probado: 23514), así que el predicado `lead_id is null` no se puede aislar con datos; tope con 10 000 clientes DISTINTOS = 10 000 filas y 10 001 = 54000. Reversión de la enmienda vuelve al md5 exacto de la 0b; reversión de las dos deja 1 183 funciones con la misma huella.
Riesgo de coste declarado (aceptado por el PRIMARY, sin cambio): con clientes de tipo PERFIL la resolución de identidad compartida (`gestiones_clientes_identidades` → `puede_consultar_cliente_ficha` por perfil) cuesta ~6 ms por perfil (1 000 perfiles = 6,2 s; `statement_timeout` de `authenticated` = 8 s → 57014 explícito). Producción: 0 reuniones con perfil; las 39 históricas son de persona F6 (0,68 s por 1 000).

Tu trabajo: REFUTAR SOLO lo nuevo, con evidencia: ¿el preflight de identidad completa cubre de verdad lo que dice (propietario, ACL, STRICT, SECURITY, SET, volatilidad) y falla cerrado?; ¿la exigencia de «0b instalada tal como se commiteó» es correcta?; ¿el corte `creado_en <= v_ahora` es coherente con `generado_en` y con la asistencia?; ¿la reversión deja exactamente la 0b?; ¿la batería ahora falla ante discrepancias? No repitas hallazgos ya atendidos salvo que la corrección sea incorrecta.

Formato: VERDICT, SUMMARY, FINDINGS P0–P3 con evidencia, TEST GAPS, NEXT ACTIONS, CONFIDENCE.

## Enmienda
```sql
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
```

## Reversión de la enmienda
```sql
-- Reversión de 20261019224227_crm_citas_clientes_proyeccion_corte.sql (ensayada en el banco
-- Docker el 19/10/2026): devuelve private.citas_clientes_proyeccion al cuerpo EXACTO de la 0b
-- (20261019213516, sin el corte por generado_en), con su ACL y su COMMENT. No toca la puerta.
-- Para quitar también la 0b, después: supabase/scripts/revertir-20261019213516-citas-clientes-proyeccion.sql
-- Un solo mensaje:
--   supabase db query --linked --file supabase/scripts/revertir-20261019224227-citas-clientes-proyeccion-corte.sql
-- y, si la enmienda ya estaba registrada:
--   supabase migration repair --status reverted 20261019224227 --linked
begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';
set local search_path = pg_catalog;
lock table private.analitica_leads_citas_exenciones, private.analitica_lc_sello,
  private.analista_vigencia_exenciones in share mode;

create temporary table cc_corte_rev_censo_antes on commit drop as
  select 'lc'::text as censo, c.tipo, c.objeto, c.declarada, c.huella_ok
  from private.contadores_crudos_leads_citas() c
  union all
  select 'vigencia', v.tipo, v.objeto, v.declarada, v.huella_ok
  from private.puertas_analista_sin_vigencia() v;

do $preflight$
begin
  -- Sólo se revierte lo que esta enmienda instaló, tal cual.
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
    raise exception 'REVERSIÓN corte: el lector no está como lo dejó la enmienda; conciliar antes de revertir';
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
revoke all on function private.citas_clientes_proyeccion(date,date) from public, anon, authenticated, service_role;
grant execute on function private.citas_clientes_proyeccion(date,date) to authenticated;

comment on function private.citas_clientes_proyeccion(date,date) is
  'Proyección de citas (Fase 0b, 19/10/2026): todas las reuniones activas con cliente y sin lead (perfil, o persona F6 si está habilitada) GENERADAS (creado_en, día de Lima) en el rango, sin paginar (tope 10 000 con error). Alcance de private.citas_clientes_core; analista y supervisor como private.citas_gerencia_consulta; identidad de private.gestiones_clientes_identidades (identidad_persona = oculta:<tarea> si no es visible). SECURITY DEFINER y VOLATILE (candados de gestiones_validar).';

do $postflight$
begin
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
    raise exception 'REVERSIÓN corte: el lector no volvió exactamente a la 0b';
  end if;
  create temporary table cc_corte_rev_censo_despues on commit drop as
    select 'lc'::text as censo, c.tipo, c.objeto, c.declarada, c.huella_ok
    from private.contadores_crudos_leads_citas() c
    union all
    select 'vigencia', v.tipo, v.objeto, v.declarada, v.huella_ok
    from private.puertas_analista_sin_vigencia() v;
  if exists ((select * from cc_corte_rev_censo_antes except all select * from cc_corte_rev_censo_despues)
             union all
             (select * from cc_corte_rev_censo_despues except all select * from cc_corte_rev_censo_antes)) then
    raise exception 'REVERSIÓN corte: cambió un censo (analítico o de vigencia)';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
```

## Entrada del ledger
```md
## 20261019224227 — Citas: corte coherente del lector de reuniones con clientes (enmienda de la 0b)

**PENDIENTE: instalar Miguel con `!` JUSTO DESPUÉS de `20261019213516`** (ensayada en el banco Docker propio el 19/10/2026, 18:11 Lima; SIN APLICAR en producción). Orden, desde `/Users/usuario/dev/avancecorp-crm-proyeccion-f2/CRM-Avance-Corp`: (1) instalar la 0b, (2) instalar esta enmienda, (3) registrar la 0b, (4) registrar esta (`supabase migration repair --status applied 20261019224227 --linked`). Si la enmienda se niega con la 0b ya instalada, NO forzar: revertir la 0b y conciliar. Después, `npm run gen:types` en `app/`.

**Qué y por qué.** Revisión de Codex LEVEL 3 sobre la 0b (`docs/encargos/2026-10-19-codex-citas-clientes-proyeccion-0b-RESPUESTA.md`, CHANGES_REQUESTED, sin fugas entre roles ni de PII; los tres hallazgos aceptados). La 0b ya estaba commiteada (`00c32abb`) y no se edita: esta migración la enmienda. (1) **Corte:** `generado_en` es `now()` (inicio de la transacción), pero la cohorte no exigía `creado_en <= generado_en`; en READ COMMITTED una reunión confirmada por otra sesión durante la consulta entraba con `creado_en` posterior y el validador del front rechazaba el payload entero. Ahora `generado_en` ES EL CORTE: `create or replace` del núcleo `private.citas_clientes_proyeccion` con `and t.creado_en <= v_ahora` (la asistencia ya se cortaba igual); misma ACL (reafirmada), COMMENT nuevo; la puerta no cambia. (2) **Identidad completa:** el preflight de la 0b acreditaba dependencias por `md5(prosrc)`, que no ve atributos (`ALTER FUNCTION private.gestiones_validar(...) STRICT` desactiva la validación sin cambiar ese hash). La enmienda acredita por `md5(pg_get_functiondef)` (incluye STRICT, DEFINER, SET y volatilidad) + dueño + ACL las siete dependencias (medidas iguales en producción y banco el 19/10) y las dos funciones de la 0b tal como se commitearon (núcleo `ac59c50f…`, puerta `a9b64034…`); postflight: núcleo con la identidad ensayada `44006907…`, no STRICT, DEFINER, VOLATILE, ACL exacta, COMMENT, dependencias intactas, los dos censos idénticos y fuera de F7.

**Evidencia (banco `crm-banco-proyeccion-0b-20261019`).** Ciclos: 0b → enmienda (COMMIT); reaplicar enmienda → se niega; revertir enmienda → núcleo vuelve al md5 exacto de la 0b y a su COMMENT; revertir otra vez → se niega; enmienda sin la 0b → se niega; revertir las dos → las 1 183 funciones restantes con la misma huella y censo en su foto; 0b commiteada (`git show 00c32abb`) + enmienda → COMMIT. Batería con aserciones (cualquier discrepancia lanza excepción y el proceso sale con error): **53/53 PASS** sobre 0b + enmienda (exit 0) y **EN ROJO sobre la 0b sola** (exit 3: la reunión creada después del corte entra en alcance y paridad). Casos nuevos: reunión creada 2 s después de `generado_en` no entra; `generado_en` = inicio de la transacción; ninguna cita creada o asistida después de `generado_en` en ninguna respuesta; el predicado `lead_id is null` no se puede aislar con datos porque la restricción VALIDADA `tareas_un_solo_sujeto` (`num_nonnulls(lead_id, perfil_id, inversionista_id) = 1`) rechaza lead + perfil con 23514 (comprobado). Tope exacto con 10 000 clientes DISTINTOS (5 000 perfiles + 5 000 personas F6): 10 000 filas, 10 000 visibles, 10 000 personas; 10 001 → 54000. **Dos sesiones reales** (A abre la transacción, B crea y confirma una reunión 1,5 s después, A consulta a los 4 s): con la 0b sola la reunión de B entra con `creado_en` > `generado_en` (el front rechazaría el payload); con la enmienda no entra y el payload es coherente. **Mutantes 9/9 muertos:** dependencia `STRICT` (contraejemplo de Codex: la 0b se instala igual y un rango invertido devuelve `[]` en vez de 22023; la enmienda se niega; restaurada vuelve a `10d9cc94…` y a 22023), ACL de una dependencia, 0b alterada tras instalarse, enmienda sin corte, núcleo STRICT, EXECUTE a anon, sin COMMENT, `count(` en el cuerpo, reversión con el núcleo tocado. **Coste** (función completa, gerencia): 10 000 clientes distintos 61–74 s; curva por mes con clientes distintos: perfiles 250 → 1,3 s, 500 → 2,7 s, 1 000 → 6,2 s, 2 000 → 14,1 s; personas F6 250 → 0,19 s, 500 → 0,30 s, 1 000 → 0,68 s, 2 000 → 1,64 s. El coste por perfil está en la resolución de identidad compartida (`private.gestiones_clientes_identidades` → `puede_consultar_cliente_ficha` por perfil), que la 0b reutiliza tal cual. Con `statement_timeout=8s` de `authenticated` (medido en producción), un rango con más de ~1 000 perfiles distintos daría 57014 (error explícito, nunca lista truncada). Producción: 0 reuniones de perfil en toda la historia; las 39 son de persona F6 (634 perfiles cliente, 719 personas canónicas); con las 37 de octubre la llamada tarda 150–540 ms.

## 20261019213516 — Citas: reuniones con clientes sin lead en la Proyección (Fase 0b)

**PENDIENTE: instalar Miguel con `!`, SIEMPRE junto con su enmienda `20261019224227`** (corte coherente e identidad completa de dependencias; ver la entrada de arriba), en este orden: 0b, enmienda, registrar 0b, registrar enmienda (ensayada en banco Docker propio el 19/10/2026, 17:33 Lima; SIN APLICAR en producción). Nota: el preflight de esta migración sólo acredita dependencias por `md5(prosrc)`; la identidad completa la exige la enmienda. Desde `/Users/usuario/dev/avancecorp-crm-proyeccion-f2/CRM-Avance-Corp`, un solo mensaje: `supabase db query --linked --file supabase/migrations/20261019213516_crm_citas_clientes_proyeccion.sql` y luego `supabase migration repair --status applied 20261019213516 --linked`. Después, `npm run gen:types` en `app/`.

**Qué y por qué.** Decisión de Miguel (19/10): la pestaña «Proyección» de Citas incluye las reuniones con CLIENTES que no tienen lead (en octubre, 37), que el lector de Citas no recorre. Lector NUEVO y aditivo, propio de la Proyección (no cambia Resultados, Agenda, Bandeja ni «Citas de clientes»): núcleo `private.citas_clientes_proyeccion(date,date)` (plpgsql, SECURITY DEFINER, `search_path=''`, VOLATILE) y puerta `crm.citas_clientes_proyeccion_fn(date,date)` (sql, INVOKER, sólo delega). Devuelve todas (sin paginar; >10 000 = error 54000, nunca una lista truncada) las reuniones activas sin lead con `perfil_id`, o con `inversionista_id` si F6 está habilitada para quien consulta, cuyo `creado_en` (día de Lima) cae en el rango. Cada una: `id`, `creado_en`, `vence_en`, `estado`, `cancelada_por`, `asistencia_registrada_en` (el primero entre el cierre F6 `inversionista_gestiones.tipo='cierre'` completado y la actividad de cliente `reunion_realizada` de la tarea; sólo si está completada), `analista_*`/`supervisor_*` resueltos EXACTAMENTE como `private.citas_gerencia_consulta`, la identidad tal cual de `private.gestiones_clientes_identidades` y `identidad_persona` (`persona:<canónico>` o `perfil:<id>` sólo si la identidad es visible; si no, `oculta:<id de la tarea>`). Cabecera `version` 1, `periodo`, `criterio:'creado_en'`, `generado_en`.

**Alcance y permisos.** Autoriza con `private.gestiones_validar(p_desde,p_hasta,null)` (sesión real; vendedor, supervisor o gerencia; hasta 365 días). Mismo filtro que `private.citas_clientes_core`: responsable en `private.vendedor_ids_visibles(auth.uid())`; sin responsable, sólo gerencia. EXECUTE sólo `postgres` y `authenticated` en las dos (la puerta es INVOKER; `private` no se expone por la API); sin `anon` ni `service_role`. VOLATILE a propósito: `gestiones_validar` toma candados de transacción y `crm.postventa_estado_fn()` bloquea filas, lo que no corre en la transacción de solo lectura que PostgREST usa para STABLE. Sin `count(` en el cuerpo: fuera del censo analítico, del de vigencia y de F7. El censo global sigue en ROJO por nueve piezas ajenas: no se llama al guardián; la migración guarda la foto de los dos censos y exige que quede idéntica, y fija el md5 de las siete dependencias (`gestiones_validar`, `gestiones_clientes_identidades`, `vendedor_ids_visibles`, `rol_crm`, `postventa_estado_fn`, `citas_clientes_core`, `citas_gerencia_consulta`; medidos iguales en producción y banco).

**Evidencia.** Banco Docker propio `crm-banco-proyeccion-0b-20261019` (127.0.0.1:55521) con `supabase db dump --linked` fresco (364 funciones crm / 781 private; md5 de las 13 dependencias iguales a producción) y el censo sembrado de producción (46 exenciones, sello cuadra). Casos sintéticos **48/48 PASS**: alcance gerencia/supervisor/vendedor con F6 on y off; paridad de ids con `crm.citas_clientes_fn` (filtrada por `creado_en`) para G, S1, V1, V2 y V3; creada en el rango y agendada fuera entra; creada fuera y agendada dentro no; bordes de día de Lima; reuniones con lead no entran (y sí están en el lector de Citas); `analista_*`/`supervisor_*` idénticos a `citas_gerencia_consulta` (supervisor por equipo y por tarea); anon, sin sesión, sin rol, coordinador, directorio, inactivo y service_role rechazados; rangos invertido, nulo y de 366 días rechazados (365 aceptado); asistencia por actividad de cliente y por cierre F6; redacción de la persona de otra cartera (`oculta:`). Tope: 10 000 filas en 133–160 ms; 10 001 → 54000. Mutantes 7/7 muertos (EXECUTE a anon, a service_role, `count(` que entra al censo, sin COMMENT, puerta DEFINER, núcleo STABLE, dependencia cambiada). Censos y mensaje del guardián idénticos antes y después. Reversión `supabase/scripts/revertir-20261019213516-citas-clientes-proyeccion.sql` ensayada dos veces: las otras 1 183 funciones de crm/private/public conservan la misma huella y el censo vuelve a su foto; reaplicada después. Producción (solo lectura): 37 reuniones creadas del 1 al 19 y del 1 al 31 de octubre (las 37 son personas F6, 19 completadas): Vladimir Jurado 8; Linda Condori, Lisseth Núñez y Merlys García 5; Alan Yutronic y Betzabeth Fuenmayor 3; Adelayda Gaspar, Daniela Castillo, Fiorella Ruiz y Miguel Briceño 2. Por `vence_en` también son 37, pero no las mismas: una creada el 28/09 y agendada el 09/10 sale y una creada el 07/10 y agendada el 01/11 entra. Coste con el cuerpo real como función temporal en `begin…rollback`: gerencia 190–540 ms (37 filas, 35 con identidad visible), supervisores 150–500 ms (22 + 15 = 37); la consulta sin identidad, 3–5 ms.

**Revisión.** `auditor-rls`: CHANGES_REQUESTED sin P0/P1. Aceptado: ledger, script de reversión ensayado y batería de alcance por rol, paridad, F6, redacción y tope (todo arriba); md5 de las dependencias en el preflight. Documentado, sin cambio: (a) `identidad_persona` no es la misma clave que el `identidad_persona` del lector de leads (aquí un perfil sólo es `persona:` con F6 y si su persona está en la cartera F5 visible; una identidad redactada da una clave por cita): la pantalla no debe emparejar las dos listas por esa clave; (b) el supervisor no ve reuniones de clientes sin responsable (regla de `citas_clientes_core`), mientras que el lector de leads sí le muestra las de su bandeja; (c) la asistencia lee `inversionista_gestiones` aunque F6 esté apagada (sólo una hora de una tarea que ya ve; con F6 apagada no entran reuniones de persona). La pantalla no debe sumar además el total `citas_clientes` del lector de Citas (otra población: perfil, por fecha programada). En producción, 2 de las 37 llegan como «Cliente fuera de tu cartera» incluso para gerencia (personas sin presencia en la cartera F5), igual que en «Citas de clientes». Borrador del front: `app/src/data/citas-clientes-proyeccion.ts` (+ test con el payload ejecutado en el banco), sin conectar a pantallas.

## 20261019170422 — Gestión Diaria cuenta las llamadas a CLIENTES

**APLICADA EN PRODUCCIÓN EL 19/10/2026 (~16:20 Lima, `!` de Miguel, `supabase db query --linked --file`) Y REGISTRADA
(`registrar-20261019170422.sql`, cuerpo md5 `357046d2…` = `main`).** Verificado tras aplicar: huellas vivas = ensayo (ayudante
`35c22cec…`, lector `a209ec1b…`, agregador `23184500…`, gate del analista `b3a4970e…` con la sección 1b); gate de citas OK;
analista y pulso rojos SOLO por el roster ajeno (`58bd0554…`). Por la puerta real: Vladimir Jurado ve 14 llamadas · 11 contestadas
· 14 útiles (9 a leads + 5 a clientes, igual que la cuenta a mano); su supervisor ve lo mismo en Equipo y en los cortes (1.º 6 de 3
cumplido); el Registro de clientes da 5/5 y total 14. Front publicado a las 16:31 Lima: `build-20261019T213057330Z` = `fcf159c0`
(PR #338, squash), smoke 130/130 JS/CSS/HTML idénticos. Decisión de Miguel (19/10): las llamadas a clientes suman al mismo número
«Llamadas» del analista, a la tasa de contacto y a los cortes/mínimo de útiles. Síntoma: Vladimir cerró 5 llamadas a clientes el
```

## Batería nueva (rápida, sin la parte de coste)
```sql
-- Casos de private.citas_clientes_proyeccion / crm.citas_clientes_proyeccion_fn con
-- datos SINTÉTICOS (inventados). Todo se deshace al final.
\set ON_ERROR_STOP 1
begin;
set local session_replication_role = replica;  -- fixtures sin disparadores (banco, no producción)
set local timezone = 'America/Lima';

-- Personas del equipo (prefijo e0..), clientes (c0..), personas F6 (a0..), leads (b0..), tareas (d0..)
insert into public.perfiles (id, nombre_completo, rol, activo, asesor_perfil_id) values
  ('00000000-0000-0000-0000-0000000000e1', 'GERENCIA SINTETICA', 'admin', true, null),
  ('00000000-0000-0000-0000-0000000000e2', 'SUPERVISOR UNO', 'analista', true, null),
  ('00000000-0000-0000-0000-0000000000e3', 'VENDEDOR UNO', 'analista', true, null),
  ('00000000-0000-0000-0000-0000000000e4', 'SUPERVISOR DOS', 'analista', true, null),
  ('00000000-0000-0000-0000-0000000000e5', 'VENDEDOR DOS', 'analista', true, null),
  ('00000000-0000-0000-0000-0000000000e6', 'VENDEDOR TRES SIN SUPERVISOR', 'analista', true, null),
  ('00000000-0000-0000-0000-0000000000e7', 'USUARIO SIN ROL', 'analista', true, null),
  ('00000000-0000-0000-0000-0000000000e8', 'COORDINADOR SINTETICO', 'analista', true, null),
  ('00000000-0000-0000-0000-0000000000e9', 'DIRECTORIO SINTETICO', 'directorio', true, null),
  ('00000000-0000-0000-0000-0000000000ea', 'VENDEDOR INACTIVO', 'analista', true, null),
  ('00000000-0000-0000-0000-0000000000c1', 'CLIENTE PERSONA UNO', 'cliente', true, '00000000-0000-0000-0000-0000000000e3'),
  ('00000000-0000-0000-0000-0000000000c2', 'CLIENTE PERSONA DOS', 'cliente', true, '00000000-0000-0000-0000-0000000000e5'),
  ('00000000-0000-0000-0000-0000000000c3', 'CLIENTE PERFIL TRES', 'cliente', true, '00000000-0000-0000-0000-0000000000e3'),
  ('00000000-0000-0000-0000-0000000000c4', 'CLIENTE PERFIL CUATRO', 'cliente', true, '00000000-0000-0000-0000-0000000000e5'),
  ('00000000-0000-0000-0000-0000000000c5', 'CLIENTE PERFIL CINCO', 'cliente', true, '00000000-0000-0000-0000-0000000000e6');
insert into crm.equipo (perfil_id, rol_crm, activo, supervisor_id) values
  ('00000000-0000-0000-0000-0000000000e1', 'gerencia', true, null),
  ('00000000-0000-0000-0000-0000000000e2', 'supervisor', true, null),
  ('00000000-0000-0000-0000-0000000000e3', 'vendedor', true, '00000000-0000-0000-0000-0000000000e2'),
  ('00000000-0000-0000-0000-0000000000e4', 'supervisor', true, null),
  ('00000000-0000-0000-0000-0000000000e5', 'vendedor', true, '00000000-0000-0000-0000-0000000000e4'),
  ('00000000-0000-0000-0000-0000000000e6', 'vendedor', true, null),
  ('00000000-0000-0000-0000-0000000000e8', 'coordinador', true, null),
  ('00000000-0000-0000-0000-0000000000e9', 'directorio', true, null),
  ('00000000-0000-0000-0000-0000000000ea', 'vendedor', false, '00000000-0000-0000-0000-0000000000e2');
insert into crm.inversionistas (id, estado, perfil_id, responsable_relacion_id) values
  ('00000000-0000-0000-0000-0000000000a1', 'activo', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000e3'),
  ('00000000-0000-0000-0000-0000000000a2', 'activo', '00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000e5');
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, activo, vendedor_id, asignado_supervisor_id, creado_en, monto_estimado) values
  ('00000000-0000-0000-0000-0000000000b1', 'LEAD SINTETICO UNO', '999000101', 'landing', 'reunion_agendada', true, '00000000-0000-0000-0000-0000000000e3', null, timestamptz '2026-10-01 09:00-05', 10000),
  ('00000000-0000-0000-0000-0000000000b2', 'LEAD SINTETICO DOS', '999000102', 'landing', 'reunion_agendada', true, '00000000-0000-0000-0000-0000000000e6', null, timestamptz '2026-10-01 09:00-05', 10000);

-- Reuniones. vendedor e3 (V1, equipo de S1), e5 (V2, equipo de S2), e6 (V3, sin supervisor en equipo).
insert into crm.tareas (id, lead_id, perfil_id, inversionista_id, postventa_revision, vendedor_id, asignado_supervisor_id, tipo, titulo, vence_en, estado, resultado_reunion, motivo_no_realizada, cancelada_por, activo, creado_en, modalidad_reunion) values
  -- d1 perfil c3 de V1, creada y agendada en octubre, completada (actividad de cliente)
  ('00000000-0000-0000-0000-0000000000d1', null, '00000000-0000-0000-0000-0000000000c3', null, null, '00000000-0000-0000-0000-0000000000e3', null, 'reunion', 'R d1', timestamptz '2026-10-07 10:00-05', 'completada', 'interesado', null, null, true, timestamptz '2026-10-05 10:00-05', 'sin_clasificar'),
  -- d2 persona a1 (F6) de V1, CREADA en octubre pero AGENDADA en noviembre, completada (cierre F6)
  ('00000000-0000-0000-0000-0000000000d2', null, null, '00000000-0000-0000-0000-0000000000a1', 1, '00000000-0000-0000-0000-0000000000e3', null, 'reunion', 'R d2', timestamptz '2026-11-05 10:00-05', 'completada', 'propuesta', null, null, true, timestamptz '2026-10-10 10:00-05', 'sin_clasificar'),
  -- d3 persona a1 de V1, CREADA en septiembre y AGENDADA en octubre: NO entra en octubre
  ('00000000-0000-0000-0000-0000000000d3', null, null, '00000000-0000-0000-0000-0000000000a1', 1, '00000000-0000-0000-0000-0000000000e3', null, 'reunion', 'R d3', timestamptz '2026-10-03 10:00-05', 'pendiente', null, null, null, true, timestamptz '2026-09-28 10:00-05', 'sin_clasificar'),
  -- d4 persona a2 (cartera de V2) en una reunión de V1: identidad redactada para V1/S1
  ('00000000-0000-0000-0000-0000000000d4', null, null, '00000000-0000-0000-0000-0000000000a2', 1, '00000000-0000-0000-0000-0000000000e3', null, 'reunion', 'R d4', timestamptz '2026-10-14 10:00-05', 'no_show', null, 'cliente_no_asistio', null, true, timestamptz '2026-10-12 10:00-05', 'sin_clasificar'),
  -- d5 perfil c4 de V2
  ('00000000-0000-0000-0000-0000000000d5', null, '00000000-0000-0000-0000-0000000000c4', null, null, '00000000-0000-0000-0000-0000000000e5', null, 'reunion', 'R d5', timestamptz '2026-10-16 10:00-05', 'pendiente', null, null, null, true, timestamptz '2026-10-15 10:00-05', 'sin_clasificar'),
  -- d6 perfil c3 SIN responsable (bandeja de S1): sólo gerencia
  ('00000000-0000-0000-0000-0000000000d6', null, '00000000-0000-0000-0000-0000000000c3', null, null, null, '00000000-0000-0000-0000-0000000000e2', 'reunion', 'R d6', timestamptz '2026-10-20 10:00-05', 'pendiente', null, null, null, true, timestamptz '2026-10-16 10:00-05', 'sin_clasificar'),
  -- d7 reunión CON LEAD de V1: no entra (la trae el lector de Citas)
  ('00000000-0000-0000-0000-0000000000d7', '00000000-0000-0000-0000-0000000000b1', null, null, null, '00000000-0000-0000-0000-0000000000e3', null, 'reunion', 'R d7', timestamptz '2026-10-08 10:00-05', 'pendiente', null, null, null, true, timestamptz '2026-10-06 10:00-05', 'sin_clasificar'),
  -- d8 perfil c5 de V3 (sin supervisor en equipo) con asignado_supervisor_id S1
  ('00000000-0000-0000-0000-0000000000d8', null, '00000000-0000-0000-0000-0000000000c5', null, null, '00000000-0000-0000-0000-0000000000e6', '00000000-0000-0000-0000-0000000000e2', 'reunion', 'R d8', timestamptz '2026-10-09 10:00-05', 'cancelada', null, 'cancelada_cliente', 'asesor', true, timestamptz '2026-10-08 10:00-05', 'sin_clasificar'),
  -- d9 reunión CON LEAD de V3 con asignado_supervisor_id S1 (para comparar supervisor)
  ('00000000-0000-0000-0000-0000000000d9', '00000000-0000-0000-0000-0000000000b2', null, null, null, '00000000-0000-0000-0000-0000000000e6', '00000000-0000-0000-0000-0000000000e2', 'reunion', 'R d9', timestamptz '2026-10-09 11:00-05', 'pendiente', null, null, null, true, timestamptz '2026-10-08 11:00-05', 'sin_clasificar'),
  -- da inactiva, db llamada (no reunión): no entran
  ('00000000-0000-0000-0000-0000000000da', null, '00000000-0000-0000-0000-0000000000c3', null, null, '00000000-0000-0000-0000-0000000000e3', null, 'reunion', 'R da', timestamptz '2026-10-11 10:00-05', 'pendiente', null, null, null, false, timestamptz '2026-10-11 09:00-05', 'sin_clasificar'),
  ('00000000-0000-0000-0000-0000000000db', null, '00000000-0000-0000-0000-0000000000c3', null, null, '00000000-0000-0000-0000-0000000000e3', null, 'llamada', 'L db', timestamptz '2026-10-11 10:00-05', 'pendiente', null, null, null, true, timestamptz '2026-10-11 09:00-05', null),
  -- dc perfil c1 (misma persona que a1) de V1: con F6 comparte identidad_persona con d2
  ('00000000-0000-0000-0000-0000000000dc', null, '00000000-0000-0000-0000-0000000000c1', null, null, '00000000-0000-0000-0000-0000000000e3', null, 'reunion', 'R dc', timestamptz '2026-10-18 10:00-05', 'pendiente', null, null, null, true, timestamptz '2026-10-17 10:00-05', 'sin_clasificar'),
  -- Bordes de septiembre en día de Lima (perfil c3, V1)
  ('00000000-0000-0000-0000-0000000000f1', null, '00000000-0000-0000-0000-0000000000c3', null, null, '00000000-0000-0000-0000-0000000000e3', null, 'reunion', 'B f1', timestamptz '2026-10-02 10:00-05', 'pendiente', null, null, null, true, timestamptz '2026-08-31 23:59:59.999-05', 'sin_clasificar'),
  ('00000000-0000-0000-0000-0000000000f2', null, '00000000-0000-0000-0000-0000000000c3', null, null, '00000000-0000-0000-0000-0000000000e3', null, 'reunion', 'B f2', timestamptz '2026-10-02 10:00-05', 'pendiente', null, null, null, true, timestamptz '2026-09-01 00:00:00-05', 'sin_clasificar'),
  ('00000000-0000-0000-0000-0000000000f3', null, '00000000-0000-0000-0000-0000000000c3', null, null, '00000000-0000-0000-0000-0000000000e3', null, 'reunion', 'B f3', timestamptz '2026-10-02 10:00-05', 'pendiente', null, null, null, true, timestamptz '2026-09-30 23:59:59.999-05', 'sin_clasificar'),
  ('00000000-0000-0000-0000-0000000000f4', null, '00000000-0000-0000-0000-0000000000c3', null, null, '00000000-0000-0000-0000-0000000000e3', null, 'reunion', 'B f4', timestamptz '2026-10-02 10:00-05', 'pendiente', null, null, null, true, timestamptz '2026-10-01 00:00:00-05', 'sin_clasificar');
-- Entrevistas registradas: d1 por actividad de cliente, d2 por cierre F6 (+ su espejo heredado 5 s después)
insert into crm.actividades_cliente (id, cliente_id, vendedor_id, tarea_id, tipo, detalle, creado_por, creado_en) values
  ('00000000-0000-0000-0000-000000000ac1', '00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000d1', 'reunion_realizada', 'sintetico', '00000000-0000-0000-0000-0000000000e3', timestamptz '2026-10-07 11:00-05'),
  ('00000000-0000-0000-0000-000000000ac2', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000d2', 'reunion_realizada', 'sintetico', '00000000-0000-0000-0000-0000000000e3', timestamptz '2026-10-11 12:00:05-05');
insert into crm.inversionista_gestiones (id, inversionista_id, tarea_id, tipo, detalle, metadata, creado_por, creado_en) values
  ('00000000-0000-0000-0000-000000000a91', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000d2', 'cierre', 'sintetico', '{"estado":"completada","tipo_tarea":"reunion"}', '00000000-0000-0000-0000-0000000000e3', timestamptz '2026-10-11 12:00-05');

-- de: reunión de perfil (V1) creada 2 s DESPUÉS del inicio de la transacción (= generado_en):
-- simula la que otra sesión confirma durante la consulta. Con el corte no entra.
insert into crm.tareas (id, perfil_id, vendedor_id, tipo, titulo, vence_en, estado, activo, creado_en, modalidad_reunion) values
  ('00000000-0000-0000-0000-0000000000de', '00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000e3', 'reunion', 'R de', now() + interval '1 day', 'pendiente', true, now() + interval '2 seconds', 'sin_clasificar');
-- El predicado lead_id is null no se puede aislar con datos: la restricción validada
-- tareas_un_solo_sujeto exige exactamente un sujeto. Se demuestra que rechaza lead+perfil.
create temporary table restriccion (resultado text, validada boolean, definicion text);
do $r$
begin
  begin
    insert into crm.tareas (lead_id, perfil_id, vendedor_id, tipo, titulo, vence_en, estado, activo, modalidad_reunion)
    values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000e3', 'reunion', 'mixta', timestamptz '2026-10-20 10:00-05', 'pendiente', true, 'sin_clasificar');
    insert into restriccion values ('INSERTÓ (la restricción no protege)', null, null);
  exception when check_violation then
    declare v_c text;
    begin
      get stacked diagnostics v_c = constraint_name;
      insert into restriccion select '23514|' || v_c, c.convalidated, pg_get_constraintdef(c.oid)
        from pg_constraint c where c.conrelid = 'crm.tareas'::regclass and c.conname = v_c;
    end;
  end;
end $r$;

-- Interruptores F6 (postventa) en el banco: encendidos para el bloque «F6 on».
insert into crm.multiempresa_flags (nombre, activo) values
  ('resolver_en_puertas', true), ('ficha_360_neutral', true), ('postventa_neutral', true)
  on conflict (nombre) do update set activo = excluded.activo;

-- Llama a la puerta con un rol de la API y una sesión dada; devuelve el error como dato.
create function pg_temp.llamar(p_rol text, p_uid uuid, p_desde date, p_hasta date, p_puerta text default 'proyeccion')
returns jsonb language plpgsql as $f$
declare r jsonb;
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '{"role":"' || p_rol || '"}' else json_build_object('sub', p_uid, 'role', p_rol)::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    execute format('set local role %I', p_rol);
    if p_puerta = 'proyeccion' then
      execute 'select crm.citas_clientes_proyeccion_fn($1, $2)' into r using p_desde, p_hasta;
    elsif p_puerta = 'clientes' then
      execute 'select crm.citas_clientes_fn($1, $2, null, 100, null, null)' into r using p_desde, p_hasta;
    elsif p_puerta = 'citas' then
      execute 'select crm.citas_gerencia_consulta_fn($1, $2)' into r using p_desde, p_hasta;
    else
      execute 'select private.citas_clientes_proyeccion($1, $2)' into r using p_desde, p_hasta;
    end if;
    execute 'reset role';
  exception when others then
    return jsonb_build_object('error', sqlstate, 'msg', sqlerrm);
  end;
  return r;
end $f$;
-- Ids cortos (dos últimos caracteres) ordenados.
create function pg_temp.ids(p jsonb) returns text language sql as $f$
  select coalesce(string_agg(right(c->>'id', 2), ',' order by right(c->>'id', 2)), '(ninguna)')
  from jsonb_array_elements(p->'citas') c
$f$;
create function pg_temp.ids_cc_oct(p jsonb) returns text language sql as $f$
  select coalesce(string_agg(right(c->>'id', 2), ',' order by right(c->>'id', 2)), '(ninguna)')
  from jsonb_array_elements(p->'items') c join crm.tareas t on t.id = (c->>'id')::uuid
  where (t.creado_en at time zone 'America/Lima')::date between date '2026-10-01' and date '2026-10-31'
    and t.creado_en <= now()
$f$;
create function pg_temp.cita(p jsonb, p_id text) returns jsonb language sql as $f$
  select c from jsonb_array_elements(p->'citas') c where c->>'id' = '00000000-0000-0000-0000-0000000000' || p_id
$f$;

create temporary table r_on as
select 'G'::text as quien, pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e1', date '2026-10-01', date '2026-10-31') as p
union all select 'S1', pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e2', date '2026-10-01', date '2026-10-31')
union all select 'V1', pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e3', date '2026-10-01', date '2026-10-31')
union all select 'S2', pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e4', date '2026-10-01', date '2026-10-31')
union all select 'V2', pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e5', date '2026-10-01', date '2026-10-31')
union all select 'V3', pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e6', date '2026-10-01', date '2026-10-31')
union all select 'G-sep', pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e1', date '2026-09-01', date '2026-09-30')
union all select 'G-citas', pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e1', date '2026-10-01', date '2026-10-31', 'citas')
union all select 'anon', pg_temp.llamar('anon', null, date '2026-10-01', date '2026-10-31')
union all select 'anon-nucleo', pg_temp.llamar('anon', null, date '2026-10-01', date '2026-10-31', 'nucleo')
union all select 'sin-sesion', pg_temp.llamar('authenticated', null, date '2026-10-01', date '2026-10-31')
union all select 'sin-rol', pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e7', date '2026-10-01', date '2026-10-31')
union all select 'coordinador', pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e8', date '2026-10-01', date '2026-10-31')
union all select 'service_role', pg_temp.llamar('service_role', null, date '2026-10-01', date '2026-10-31')
union all select 'rango-invertido', pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e1', date '2026-10-31', date '2026-10-01')
union all select 'rango-366', pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e1', date '2026-01-01', date '2027-01-02')
union all select 'rango-nulo', pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e1', null, date '2026-10-31')
union all select 'directorio', pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e9', date '2026-10-01', date '2026-10-31')
union all select 'inactivo', pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000ea', date '2026-10-01', date '2026-10-31')
union all select 'G-cc', pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e1', date '2026-01-01', date '2026-12-31', 'clientes')
union all select 'S1-cc', pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e2', date '2026-01-01', date '2026-12-31', 'clientes')
union all select 'V1-cc', pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e3', date '2026-01-01', date '2026-12-31', 'clientes')
union all select 'V2-cc', pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e5', date '2026-01-01', date '2026-12-31', 'clientes')
union all select 'V3-cc', pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e6', date '2026-01-01', date '2026-12-31', 'clientes')
union all select 'rango-365', pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e1', date '2026-01-01', date '2027-01-01');

update crm.multiempresa_flags set activo = false where nombre = 'postventa_neutral';
create temporary table r_off as
select 'G'::text as quien, pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e1', date '2026-10-01', date '2026-10-31') as p
union all select 'V1', pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e3', date '2026-10-01', date '2026-10-31');

create temporary table casos (n serial, caso text, esperado text, obtenido text);
insert into casos (caso, esperado, obtenido)
select x.caso, x.esperado, x.obtenido from (values
  ('F6 on · gerencia ve todas (sin lead, activas, reunión, creadas en oct)', 'd1,d2,d4,d5,d6,d8,dc,f4', (select pg_temp.ids(p) from r_on where quien='G')),
  ('F6 on · supervisor 1 solo su equipo (sin bandeja sin responsable)',      'd1,d2,d4,dc,f4',          (select pg_temp.ids(p) from r_on where quien='S1')),
  ('F6 on · vendedor 1 solo las suyas',                                         'd1,d2,d4,dc,f4',          (select pg_temp.ids(p) from r_on where quien='V1')),
  ('F6 on · supervisor 2 solo su equipo',                                       'd5',                       (select pg_temp.ids(p) from r_on where quien='S2')),
  ('F6 on · vendedor 2 solo las suyas',                                         'd5',                       (select pg_temp.ids(p) from r_on where quien='V2')),
  ('F6 on · vendedor 3 (sin supervisor en equipo) solo las suyas',             'd8',                       (select pg_temp.ids(p) from r_on where quien='V3')),
  ('F6 off · gerencia: sin reuniones de persona F6',                            'd1,d5,d6,d8,dc,f4',        (select pg_temp.ids(p) from r_off where quien='G')),
  ('F6 off · vendedor 1: sin reuniones de persona F6',                          'd1,dc,f4',                 (select pg_temp.ids(p) from r_off where quien='V1')),
  ('creada en oct y agendada en nov (d2) entra en oct',                         'true', (select (pg_temp.cita(p,'d2') is not null)::text from r_on where quien='G')),
  ('creada en sep y agendada en oct (d3) NO entra en oct',                      'false', (select (pg_temp.cita(p,'d3') is not null)::text from r_on where quien='G')),
  ('septiembre por día de Lima: d3, f2 (1/9 00:00), f3 (30/9 23:59:59.999)',    'd3,f2,f3', (select pg_temp.ids(p) from r_on where quien='G-sep')),
  ('reuniones con lead (d7, d9) NO entran',                                     'false', (select (pg_temp.cita(p,'d7') is not null or pg_temp.cita(p,'d9') is not null)::text from r_on where quien='G')),
  ('reuniones con lead (d7, d9) SÍ están en el lector de Citas',                'd7,d9', (select string_agg(right(c->>'id',2), ',' order by right(c->>'id',2)) from r_on, jsonb_array_elements(p->'citas') c where quien='G-citas')),
  ('anon rechazado en la puerta',                                               '42501', (select p->>'error' from r_on where quien='anon')),
  ('anon rechazado en el núcleo',                                               '42501', (select p->>'error' from r_on where quien='anon-nucleo')),
  ('authenticated sin sesión rechazado',                                        '42501', (select p->>'error' from r_on where quien='sin-sesion')),
  ('usuario sin rol CRM rechazado',                                             '42501', (select p->>'error' from r_on where quien='sin-rol')),
  ('coordinador rechazado',                                                     '42501', (select p->>'error' from r_on where quien='coordinador')),
  ('service_role sin EXECUTE',                                                  '42501', (select p->>'error' from r_on where quien='service_role')),
  ('rango invertido rechazado',                                                 '22023', (select p->>'error' from r_on where quien='rango-invertido')),
  ('rango de más de un año rechazado',                                          '22023', (select p->>'error' from r_on where quien='rango-366')),
  ('rango nulo rechazado',                                                      '22023', (select p->>'error' from r_on where quien='rango-nulo')),
  ('rango de exactamente 365 días aceptado',                                    '1', (select p->>'version' from r_on where quien='rango-365')),
  ('cabecera: version/criterio/periodo',                                        '1|creado_en|2026-10-01|2026-10-31', (select concat_ws('|', p->>'version', p->>'criterio', p->'periodo'->>'desde', p->'periodo'->>'hasta') from r_on where quien='G')),
  ('d1 asistencia = actividad de cliente realizada',                            '2026-10-07 11:00:00-05', (select ((pg_temp.cita(p,'d1')->>'asistencia_registrada_en')::timestamptz)::text from r_on where quien='V1')),
  ('d2 asistencia = cierre F6 (el primero, no el espejo)',                      '2026-10-11 12:00:00-05', (select ((pg_temp.cita(p,'d2')->>'asistencia_registrada_en')::timestamptz)::text from r_on where quien='V1')),
  ('d4 no_show sin asistencia',                                                 'null', (select coalesce(pg_temp.cita(p,'d4')->>'asistencia_registrada_en','null') from r_on where quien='V1')),
  ('d8 cancelada_por',                                                          'cancelada|asesor', (select concat_ws('|', pg_temp.cita(p,'d8')->>'estado', pg_temp.cita(p,'d8')->>'cancelada_por') from r_on where quien='G')),
  ('V1 · d4 (cliente de la cartera de V2) redactado',                           'false|Cliente fuera de tu cartera|||oculta:00000000-0000-0000-0000-0000000000d4',
     (select concat_ws('|', c->>'identidad_visible', c->>'sujeto_nombre', coalesce(c->>'sujeto_id',''), coalesce(c->>'inversionista_id',''), c->>'identidad_persona') from r_on, pg_temp.cita(p,'d4') c where quien='V1')),
  ('S1 · d4 también redactado',                                                 'false|oculta:00000000-0000-0000-0000-0000000000d4',
     (select concat_ws('|', c->>'identidad_visible', c->>'identidad_persona') from r_on, pg_temp.cita(p,'d4') c where quien='S1')),
  ('G · d4 visible como persona canónica a2',                                   'true|CLIENTE PERSONA DOS|persona:00000000-0000-0000-0000-0000000000a2',
     (select concat_ws('|', c->>'identidad_visible', c->>'sujeto_nombre', c->>'identidad_persona') from r_on, pg_temp.cita(p,'d4') c where quien='G')),
  ('V1 · d2 visible como persona a1',                                           'true|CLIENTE PERSONA UNO|persona:00000000-0000-0000-0000-0000000000a1',
     (select concat_ws('|', c->>'identidad_visible', c->>'sujeto_nombre', c->>'identidad_persona') from r_on, pg_temp.cita(p,'d2') c where quien='V1')),
  ('F6 on · dc (perfil c1 de a1) comparte identidad_persona con d2',           'persona:00000000-0000-0000-0000-0000000000a1',
     (select pg_temp.cita(p,'dc')->>'identidad_persona' from r_on where quien='V1')),
  ('F6 off · dc vuelve a su perfil',                                            'perfil:00000000-0000-0000-0000-0000000000c1',
     (select pg_temp.cita(p,'dc')->>'identidad_persona' from r_off where quien='V1')),
  ('V1 · d1 perfil visible',                                                    'true|CLIENTE PERFIL TRES|perfil:00000000-0000-0000-0000-0000000000c3',
     (select concat_ws('|', c->>'identidad_visible', c->>'sujeto_nombre', c->>'identidad_persona') from r_on, pg_temp.cita(p,'d1') c where quien='V1')),
  ('claves de una cita',
     'analista_id,analista_nombre,asistencia_registrada_en,cancelada_por,creado_en,estado,id,identidad_persona,identidad_visible,inversionista_id,perfil_id,sujeto_id,sujeto_nombre,sujeto_tipo,supervisor_id,supervisor_nombre,vence_en',
     (select string_agg(k, ',' order by k) from r_on, jsonb_object_keys(pg_temp.cita(p,'d1')) k where quien='G')),
  ('d1 (V1) analista/supervisor = d7 del lector de Citas (V1)',
     (select concat_ws('|', c->>'analista_id', c->>'analista_nombre', c->>'supervisor_id', c->>'supervisor_nombre') from r_on, pg_temp.cita(p,'d7') c where quien='G-citas'),
     (select concat_ws('|', c->>'analista_id', c->>'analista_nombre', c->>'supervisor_id', c->>'supervisor_nombre') from r_on, pg_temp.cita(p,'d1') c where quien='G')),
  ('d8 (V3, supervisor por tarea) = d9 del lector de Citas (V3)',
     (select concat_ws('|', c->>'analista_id', c->>'analista_nombre', c->>'supervisor_id', c->>'supervisor_nombre') from r_on, pg_temp.cita(p,'d9') c where quien='G-citas'),
     (select concat_ws('|', c->>'analista_id', c->>'analista_nombre', c->>'supervisor_id', c->>'supervisor_nombre') from r_on, pg_temp.cita(p,'d8') c where quien='G')),
  ('d1 analista/supervisor literal',
     '00000000-0000-0000-0000-0000000000e3|VENDEDOR UNO|00000000-0000-0000-0000-0000000000e2|SUPERVISOR UNO',
     (select concat_ws('|', c->>'analista_id', c->>'analista_nombre', c->>'supervisor_id', c->>'supervisor_nombre') from r_on, pg_temp.cita(p,'d1') c where quien='G')),
  ('directorio rechazado',                                                    '42501', (select p->>'error' from r_on where quien='directorio')),
  ('vendedor inactivo rechazado',                                             '42501', (select p->>'error' from r_on where quien='inactivo')),
  ('paridad G: ids = citas_clientes_fn filtrada por creado_en',              (select pg_temp.ids_cc_oct(p) from r_on where quien='G-cc'), (select pg_temp.ids(p) from r_on where quien='G')),
  ('paridad S1: ids = citas_clientes_fn filtrada por creado_en',             (select pg_temp.ids_cc_oct(p) from r_on where quien='S1-cc'), (select pg_temp.ids(p) from r_on where quien='S1')),
  ('paridad V1: ids = citas_clientes_fn filtrada por creado_en',             (select pg_temp.ids_cc_oct(p) from r_on where quien='V1-cc'), (select pg_temp.ids(p) from r_on where quien='V1')),
  ('paridad V2: ids = citas_clientes_fn filtrada por creado_en',             (select pg_temp.ids_cc_oct(p) from r_on where quien='V2-cc'), (select pg_temp.ids(p) from r_on where quien='V2')),
  ('paridad V3: ids = citas_clientes_fn filtrada por creado_en',             (select pg_temp.ids_cc_oct(p) from r_on where quien='V3-cc'), (select pg_temp.ids(p) from r_on where quien='V3')),
  ('citas_clientes_fn no paginó (hay_mas=false)',                              'false', (select string_agg(distinct p->>'hay_mas', ',') from r_on where quien like '%-cc')),
  ('corte: reunión creada después de generado_en (de) no entra (G, S1, V1)', 'false',
     (select bool_or(pg_temp.cita(p,'de') is not null)::text from r_on where quien in ('G','S1','V1'))),
  ('corte: generado_en = inicio de la transacción', (select now()::text),
     (select ((p->>'generado_en')::timestamptz)::text from r_on where quien='G')),
  ('coherencia: ninguna cita creada o asistida después de generado_en (todas las respuestas)', '0',
     (select count(*)::text from (select p from r_on where not p ? 'error' union all select p from r_off) x,
        jsonb_array_elements(x.p->'citas') c
      where (c->>'creado_en')::timestamptz > (x.p->>'generado_en')::timestamptz
         or (c->>'asistencia_registrada_en')::timestamptz > (x.p->>'generado_en')::timestamptz)),
  ('restricción: lead + perfil en la misma tarea se rechaza (23514)', '23514|tareas_un_solo_sujeto', (select resultado from restriccion)),
  ('restricción validada: num_nonnulls(lead_id, perfil_id, inversionista_id) = 1', 'true',
     (select (validada and definicion like '%num_nonnulls(lead_id, perfil_id, inversionista_id) = 1%')::text from restriccion)),
  ('d6 sin responsable: Sin analista + supervisor de la tarea',
     '|Sin analista|00000000-0000-0000-0000-0000000000e2|SUPERVISOR UNO',
     (select concat_ws('|', coalesce(c->>'analista_id',''), c->>'analista_nombre', c->>'supervisor_id', c->>'supervisor_nombre') from r_on, pg_temp.cita(p,'d6') c where quien='G'))
) as x(caso, esperado, obtenido);

select n, case when esperado is not distinct from obtenido then 'PASS' else 'FAIL' end as veredicto, caso,
       case when esperado is distinct from obtenido then 'esperado=' || coalesce(esperado,'∅') || ' obtenido=' || coalesce(obtenido,'∅') else '' end as detalle
from casos order by n;
select 'TOTAL ' || sum((esperado is not distinct from obtenido)::int) || '/' || max(n) from casos;
do $a$
declare v_fallos text;
begin
  select string_agg(n || ' ' || caso || ' [esperado=' || coalesce(esperado,'∅') || ' obtenido=' || coalesce(obtenido,'∅') || ']', '; ' order by n)
    into v_fallos from casos where esperado is distinct from obtenido;
  if v_fallos is not null then raise exception 'BATERÍA EN ROJO: %', v_fallos; end if;
  if (select count(*) from casos) <> 53 then raise exception 'BATERÍA: se esperaban 53 casos y hay %', (select count(*) from casos); end if;
  raise notice 'BATERÍA EN VERDE: % casos', (select count(*) from casos);
end $a$;
-- Mensajes de los rechazos, para el informe
select quien, p->>'error' as sqlstate, p->>'msg' as mensaje from r_on where p ? 'error' order by quien;

rollback;
```

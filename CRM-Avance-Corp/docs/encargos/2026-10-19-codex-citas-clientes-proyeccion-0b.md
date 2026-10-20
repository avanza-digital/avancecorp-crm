ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo (LEVEL 3, primera pasada): REFUTA la migración `20261019213516_crm_citas_clientes_proyeccion.sql` (Supabase/Postgres)

Contexto. CRM Avance Corp, proyecto Supabase con esquema `crm` (puertas expuestas por PostgREST) y `private` (núcleo, no expuesto). Roles de negocio: vendedor (analista), supervisor, gerencia; además coordinador/directorio sin acceso a estas lecturas. La visibilidad por equipo la da `private.vendedor_ids_visibles(auth.uid())`. PII de clientes protegida por `private.gestiones_clientes_identidades(jsonb)`. F6 = postventa (cuando está habilitada, `crm.tareas.inversionista_id` cuenta como cliente).

Decisión del dueño (19/10/2026): la pestaña «Proyección» de Citas debe incluir las reuniones con CLIENTES que no tienen lead (hoy el lector de Citas `private.citas_gerencia_consulta` solo trae tareas con lead; en octubre hubo 37 reuniones así). Diseño: lector NUEVO, aditivo y propio (`crm.citas_clientes_proyeccion_fn(date,date)` → `private.citas_clientes_proyeccion(date,date)`), sin tocar el lector compartido. Cohorte por FECHA DE CREACIÓN (día de Lima de `crm.tareas.creado_en`), sin paginar (tope 10 000 → error 54000), misma visibilidad que `private.citas_clientes_core` (la sección «Citas de clientes», paginada por `vence_en`), y misma atribución analista/supervisor que el lector de Citas. La pantalla las fusionará como origen «Cliente» (Fase posterior; aún no conectada).

Verificación ya hecha por el PRIMARY/implementador (no ejecutada por ti): banco Docker con el esquema de producción (`supabase db dump --linked`), 48/48 casos PASS (gerencia todo, supervisor su equipo, vendedor lo suyo, con F6 encendida y apagada; ids iguales a `crm.citas_clientes_fn` filtrada por `creado_en` para 5 usuarios; bordes del día de Lima; reunión con lead excluida; analista/supervisor iguales al lector de Citas; rechazos de anon, sin sesión, sin rol, coordinador, directorio, inactivo, service_role; rangos inválidos; asistencia; cliente de otra cartera redactado; tope 10 000/10 001), 7/7 mutantes de defensas muertos, `auditor-rls` CHANGES_REQUESTED sin hallazgos graves (atendidos: ledger, reversión ensayada, batería, md5 de 7 dependencias fijado en el preflight e igual en prod y banco), reversión ensayada dos veces (1 183 funciones con la misma huella después), censo analítico idéntico antes y después. Producción (solo lectura): 37 reuniones del 1 al 19/10, 190–540 ms la función completa.

Tu trabajo: REFUTAR con evidencia (línea del SQL, caso concreto). Busca: (a) fugas entre roles o de PII (¿un supervisor o vendedor ve algo que `citas_clientes_core` no le mostraría?, ¿`identidad_persona` o algún campo filtra datos de un cliente que el usuario no puede ver?), (b) `SECURITY DEFINER` sin `search_path` vacío, nombres sin calificar, ACL incompletas (PUBLIC, anon, service_role), funciones `private` invocables directamente sin sesión, (c) que la cohorte por creación pierda o duplique reuniones (bordes de zona horaria, `activo`, reasignaciones, reunión con lead), (d) que la atribución analista/supervisor difiera del lector de Citas, (e) el preflight md5 y la reversión: ¿deja la base exactamente como estaba?, ¿se puede aplicar dos veces?, (f) coste/bloqueos (VOLATILE, candados de `gestiones_validar`, tope), (g) pruebas que no prueben lo que dicen.

Formato: VERDICT (APPROVE / CHANGES_REQUESTED), SUMMARY, FINDINGS P0–P3 con evidencia, TEST GAPS, NEXT ACTIONS, CONFIDENCE.

## La migración
```sql
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
```

## Script de reversión
```sql
-- Reversión de 20261019213516_crm_citas_clientes_proyeccion.sql (ensayada en el
-- banco Docker el 19/10/2026). Retira la puerta y el núcleo del lector de reuniones
-- con clientes de la Proyección. No toca tablas, datos, policies ni ningún otro
-- lector. Antes de correrla, el front no debe llamar a
-- crm.citas_clientes_proyeccion_fn (si lo hace, esa llamada pasará a PGRST202).
-- Un solo mensaje:
--   supabase db query --linked --file supabase/scripts/revertir-20261019213516-citas-clientes-proyeccion.sql
-- y, si la migración ya estaba registrada:
--   supabase migration repair --status reverted 20261019213516 --linked
begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';
set local search_path = pg_catalog;
lock table private.analitica_leads_citas_exenciones, private.analitica_lc_sello,
  private.analista_vigencia_exenciones in share mode;

create temporary table cc_proy_rev_censo_antes on commit drop as
  select 'lc'::text as censo, c.tipo, c.objeto, c.declarada, c.huella_ok
  from private.contadores_crudos_leads_citas() c
  union all
  select 'vigencia', v.tipo, v.objeto, v.declarada, v.huella_ok
  from private.puertas_analista_sin_vigencia() v;

do $preflight$
begin
  if pg_catalog.to_regprocedure('private.citas_clientes_proyeccion(date,date)') is null
     or pg_catalog.to_regprocedure('crm.citas_clientes_proyeccion_fn(date,date)') is null then
    raise exception 'REVERSIÓN citas_clientes_proyeccion: falta alguna de las dos funciones; nada coherente que revertir';
  end if;
  -- Nada más en la base puede depender del lector (pg_depend sólo ve vistas y
  -- defaults; las llamadas desde otras funciones se buscan en el cuerpo).
  if exists (
    select 1 from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname not in ('pg_catalog', 'information_schema')
      and p.oid not in ('private.citas_clientes_proyeccion(date,date)'::regprocedure,
                        'crm.citas_clientes_proyeccion_fn(date,date)'::regprocedure)
      and pg_catalog.strpos(pg_catalog.lower(p.prosrc), 'citas_clientes_proyeccion') > 0
  ) then
    raise exception 'REVERSIÓN citas_clientes_proyeccion: otra función de la base llama al lector; retirarla primero';
  end if;
end;
$preflight$;

drop function crm.citas_clientes_proyeccion_fn(date,date);
drop function private.citas_clientes_proyeccion(date,date);

do $postflight$
begin
  if pg_catalog.to_regprocedure('private.citas_clientes_proyeccion(date,date)') is not null
     or pg_catalog.to_regprocedure('crm.citas_clientes_proyeccion_fn(date,date)') is not null then
    raise exception 'REVERSIÓN citas_clientes_proyeccion: alguna función sigue existiendo';
  end if;
end;
$postflight$;

-- Los dos censos quedan EXACTAMENTE como estaban.
do $censo$
begin
  create temporary table cc_proy_rev_censo_despues on commit drop as
    select 'lc'::text as censo, c.tipo, c.objeto, c.declarada, c.huella_ok
    from private.contadores_crudos_leads_citas() c
    union all
    select 'vigencia', v.tipo, v.objeto, v.declarada, v.huella_ok
    from private.puertas_analista_sin_vigencia() v;
  if exists ((select * from cc_proy_rev_censo_antes except all select * from cc_proy_rev_censo_despues)
             union all
             (select * from cc_proy_rev_censo_despues except all select * from cc_proy_rev_censo_antes)) then
    raise exception 'REVERSIÓN citas_clientes_proyeccion: cambió un censo (analítico o de vigencia)';
  end if;
end;
$censo$;

notify pgrst, 'reload schema';
commit;
```

## Dependencias tal como están en el repo (20261006012208): gestiones_validar, gestiones_clientes_identidades, citas_clientes_core
```sql
-- Lectura operativa de clientes, aditiva a captación. No cambia sus núcleos ni metas.
-- Preparada para revisión humana; aplicar primero en un banco autorizado.
begin;
set local lock_timeout = '5s';

-- Autoriza siempre con la sesión real. No acepta p_actor ni concede SELECT a F6.
create function private.gestiones_validar(p_desde date,p_hasta date,p_autores uuid[] default null)
returns void language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
begin
  if auth.uid() is null then
    raise exception 'No autorizado para consultar gestiones' using errcode='42501'; end if;
  if p_desde is null or p_hasta is null or not isfinite(p_desde) or not isfinite(p_hasta)
    or p_desde>p_hasta or p_hasta-p_desde>365 then
    raise exception 'Elige un rango válido de hasta un año' using errcode='22023'; end if;
  perform private.resolver_en_puertas_bajo_candado();
  perform pg_advisory_xact_lock_shared(hashtextextended('crm.equipo.usuarios_jerarquia',0));
  if not private.puede_acceder_crm()
    or coalesce(private.rol_crm(auth.uid()),'') not in ('vendedor','supervisor','gerencia') then
    raise exception 'No autorizado para consultar gestiones' using errcode='42501'; end if;
  if p_autores is not null and (cardinality(p_autores)=0 or exists(
    select 1 from unnest(p_autores) a where a is null
      or a not in (select private.vendedor_ids_visibles(auth.uid())))) then
    raise exception 'Solo puedes consultar autores de tu equipo' using errcode='42501'; end if;
end;
$$;

-- Identidad de ficha autorizada: incluso un autor histórico no recupera PII
-- de un cliente reasignado. El resultado siempre tiene una forma explícita.
create function private.gestiones_clientes_identidades(p_sujetos jsonb)
returns table(persona uuid,perfil uuid,identidad jsonb)
language plpgsql security definer set search_path='' as $$
declare v_f6 boolean;
begin
  perform private.gestiones_validar(current_date,current_date);
  if jsonb_typeof(p_sujetos) is distinct from 'array' then
    raise exception 'Lista de clientes inválida' using errcode='22023'; end if;
  -- Una página de leads o un conteo no necesita recorrer la cartera F5.
  if jsonb_array_length(p_sujetos)=0 then return; end if;
  if exists(select 1 from jsonb_to_recordset(p_sujetos) x(persona uuid,perfil uuid)
    where num_nonnulls(x.persona,x.perfil)<>1) then
    raise exception 'Indica un único cliente por referencia' using errcode='22023'; end if;
  v_f6:=coalesce((crm.postventa_estado_fn()->>'habilitada')::boolean,false);
  return query
  with sujetos as materialized (
    select distinct x.persona,x.perfil,case when x.persona is not null then private.inversionista_canonica(x.persona) end canonica
    from jsonb_to_recordset(p_sujetos) x(persona uuid,perfil uuid)
  ), visibles as materialized (
    -- Una lectura F5 para toda la página, con sus mismas fuentes y reglas de nombre.
    select p.inversionista_id,p.nombre,p.perfil_ids from private.cartera_f5_personas_visibles() p
    where v_f6 and (p.inversionista_id in (select s.canonica from sujetos s)
      or p.perfil_ids && array(select s.perfil from sujetos s where s.perfil is not null))
      and private.postventa_visible(p.inversionista_id)
  ), resueltos as (
    select s.*,v.inversionista_id,case when s.persona is not null then v.nombre
        when private.puede_consultar_cliente_ficha(s.perfil) then p.nombre_completo end nombre
    from sujetos s left join lateral (
      select v.* from visibles v where (s.persona is not null and v.inversionista_id=s.canonica)
        or (s.perfil is not null and s.perfil=any(v.perfil_ids)) order by v.inversionista_id limit 1
    ) v on true left join public.perfiles p on p.id=s.perfil
  )
  select r.persona,r.perfil,jsonb_build_object(
    'sujeto_tipo',case when r.persona is not null then 'inversionista' else 'perfil' end,
    'sujeto_id',case when r.nombre is not null then coalesce(r.canonica,r.perfil) end,
    'sujeto_nombre',case when r.nombre is null then 'Cliente fuera de tu cartera'
      else coalesce(nullif(btrim(r.nombre),''),'Sin nombre') end,
    'inversionista_id',case when r.nombre is not null then r.inversionista_id end,
    'perfil_id',case when r.nombre is not null then r.perfil end,
    'identidad_visible',r.nombre is not null)
  from resueltos r;
end;
$$;

create function private.citas_clientes_core(p_desde date,p_hasta date,p_analista_ids uuid[] default null,
  p_limite integer default 25,p_despues_de timestamptz default null,p_despues_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_r jsonb; v_ids uuid[]; v_f6 boolean;
begin
  perform private.gestiones_validar(p_desde,p_hasta,p_analista_ids);
  if p_limite is null or p_limite not between 1 and 100 or num_nonnulls(p_despues_de,p_despues_id) not in (0,2)
    or (p_despues_de is not null and not isfinite(p_despues_de)) then
    raise exception 'Página de citas inválida' using errcode='22023'; end if;
  select array_agg(x) into v_ids from private.vendedor_ids_visibles(auth.uid()) x
    where p_analista_ids is null or x=any(p_analista_ids);
  v_f6:=coalesce((crm.postventa_estado_fn()->>'habilitada')::boolean,false);
  with base as materialized (
    select t.* from crm.tareas t where t.activo and t.tipo='reunion'
      and (t.vendedor_id=any(v_ids) or (t.vendedor_id is null and p_analista_ids is null and private.rol_crm(auth.uid())='gerencia'))
      and (t.perfil_id is not null or (v_f6 and t.inversionista_id is not null))
      and t.vence_en>=p_desde::timestamp at time zone 'America/Lima'
      and t.vence_en<(p_hasta+1)::timestamp at time zone 'America/Lima'
  ), sonda as materialized (
    select * from base where p_despues_de is null or (vence_en,id)>(p_despues_de,p_despues_id)
    order by vence_en,id limit p_limite+1
  ), pagina as materialized (select * from sonda order by vence_en,id limit p_limite),
  sujetos as materialized (select * from private.gestiones_clientes_identidades(coalesce((
    select jsonb_agg(jsonb_build_object('persona',p.inversionista_id,'perfil',p.perfil_id)) from pagina p),'[]'))),
  filas as (select p.id,p.vence_en,p.estado,p.confirmada_en,p.resultado_reunion,p.vendedor_id,
    coalesce(private.nombre_de_autor(p.vendedor_id),'Sin responsable') vendedor_nombre,s.identidad from pagina p
    join sujetos s on s.persona is not distinct from p.inversionista_id and s.perfil is not distinct from p.perfil_id)
  select jsonb_build_object('version',1,'desde',p_desde,'hasta',p_hasta,'generado_en',now(),'limite',p_limite,
    'resumen',jsonb_build_object('total',(select count(*) from base),
      'pendientes',(select count(*) from base where estado='pendiente'),
      'entrevistas',(select count(*) from base where estado='completada'),
      'no_asistio',(select count(*) from base where estado='no_show'),
      'reprogramadas',(select count(*) from base where estado='reprogramada'),
      'canceladas',(select count(*) from base where estado='cancelada')),
    'items',coalesce((select jsonb_agg((to_jsonb(f)-'identidad')||f.identidad order by vence_en,id) from filas f),'[]'),
    'hay_mas',(select count(*)>p_limite from sonda),
    'siguiente_cursor',case when (select count(*)>p_limite from sonda) then
      (select jsonb_build_object('despues_de',vence_en,'despues_id',id) from pagina order by vence_en desc,id desc limit 1) end) into v_r;
  return v_r;
end;
$$;

create function crm.citas_clientes_fn(p_desde date,p_hasta date,p_analista_ids uuid[] default null,
  p_limite integer default 25,p_despues_de timestamptz default null,p_despues_id uuid default null)
returns jsonb language sql security invoker set search_path='' as $$
  select private.citas_clientes_core(p_desde,p_hasta,p_analista_ids,p_limite,p_despues_de,p_despues_id);
$$;


-- ACL explícitas. Las funciones privadas siguen comprobando sesión al invocarse directamente.
revoke all on function private.gestiones_validar(date,date,uuid[]),private.gestion_cliente_identidad(uuid,uuid),
  private.gestiones_clientes_eventos(date,date,uuid[],boolean,integer,text[],timestamptz,uuid,text),
  private.gestiones_operativas_eventos(date,date,uuid[],boolean,integer,text[],timestamptz,uuid,text,text,text),
  private.gestiones_clientes_identidades(jsonb),private.gestiones_identificar_tareas(jsonb),
  private.citas_clientes_core(date,date,uuid[],integer,timestamptz,uuid),
  crm.registro_actividad_v2_fn(date,date,uuid[],text[],text,integer,timestamptz,uuid,text,text),
  crm.gestiones_resumen_fn(date,date,uuid[]),crm.citas_clientes_fn(date,date,uuid[],integer,timestamptz,uuid),
  crm.gestion_diaria_citas_v2_fn(date,text,uuid,integer,timestamptz,uuid),
  crm.gestion_diaria_pendientes_v2_fn(uuid,boolean,integer,timestamptz,uuid) from public,anon,authenticated,service_role;
grant execute on function private.gestiones_validar(date,date,uuid[]),private.gestion_cliente_identidad(uuid,uuid),
  private.gestiones_clientes_eventos(date,date,uuid[],boolean,integer,text[],timestamptz,uuid,text),
  private.gestiones_operativas_eventos(date,date,uuid[],boolean,integer,text[],timestamptz,uuid,text,text,text),
  private.gestiones_clientes_identidades(jsonb),private.gestiones_identificar_tareas(jsonb),
  private.citas_clientes_core(date,date,uuid[],integer,timestamptz,uuid),
  crm.registro_actividad_v2_fn(date,date,uuid[],text[],text,integer,timestamptz,uuid,text,text),
  crm.gestiones_resumen_fn(date,date,uuid[]),crm.citas_clientes_fn(date,date,uuid[],integer,timestamptz,uuid),
  crm.gestion_diaria_citas_v2_fn(date,text,uuid,integer,timestamptz,uuid),
  crm.gestion_diaria_pendientes_v2_fn(uuid,boolean,integer,timestamptz,uuid) to authenticated;

```

## Entrada del ledger
```md
++ b/CRM-Avance-Corp/supabase/migrations/MIGRACIONES.md
## 20261019213516 — Citas: reuniones con clientes sin lead en la Proyección (Fase 0b)

**PENDIENTE: instalar Miguel con `!`** (ensayada en banco Docker propio el 19/10/2026, 17:33 Lima; SIN APLICAR en producción). Desde `/Users/usuario/dev/avancecorp-crm-proyeccion-f2/CRM-Avance-Corp`, un solo mensaje: `supabase db query --linked --file supabase/migrations/20261019213516_crm_citas_clientes_proyeccion.sql` y luego `supabase migration repair --status applied 20261019213516 --linked`. Después, `npm run gen:types` en `app/`.

**Qué y por qué.** Decisión de Miguel (19/10): la pestaña «Proyección» de Citas incluye las reuniones con CLIENTES que no tienen lead (en octubre, 37), que el lector de Citas no recorre. Lector NUEVO y aditivo, propio de la Proyección (no cambia Resultados, Agenda, Bandeja ni «Citas de clientes»): núcleo `private.citas_clientes_proyeccion(date,date)` (plpgsql, SECURITY DEFINER, `search_path=''`, VOLATILE) y puerta `crm.citas_clientes_proyeccion_fn(date,date)` (sql, INVOKER, sólo delega). Devuelve todas (sin paginar; >10 000 = error 54000, nunca una lista truncada) las reuniones activas sin lead con `perfil_id`, o con `inversionista_id` si F6 está habilitada para quien consulta, cuyo `creado_en` (día de Lima) cae en el rango. Cada una: `id`, `creado_en`, `vence_en`, `estado`, `cancelada_por`, `asistencia_registrada_en` (el primero entre el cierre F6 `inversionista_gestiones.tipo='cierre'` completado y la actividad de cliente `reunion_realizada` de la tarea; sólo si está completada), `analista_*`/`supervisor_*` resueltos EXACTAMENTE como `private.citas_gerencia_consulta`, la identidad tal cual de `private.gestiones_clientes_identidades` y `identidad_persona` (`persona:<canónico>` o `perfil:<id>` sólo si la identidad es visible; si no, `oculta:<id de la tarea>`). Cabecera `version` 1, `periodo`, `criterio:'creado_en'`, `generado_en`.

**Alcance y permisos.** Autoriza con `private.gestiones_validar(p_desde,p_hasta,null)` (sesión real; vendedor, supervisor o gerencia; hasta 365 días). Mismo filtro que `private.citas_clientes_core`: responsable en `private.vendedor_ids_visibles(auth.uid())`; sin responsable, sólo gerencia. EXECUTE sólo `postgres` y `authenticated` en las dos (la puerta es INVOKER; `private` no se expone por la API); sin `anon` ni `service_role`. VOLATILE a propósito: `gestiones_validar` toma candados de transacción y `crm.postventa_estado_fn()` bloquea filas, lo que no corre en la transacción de solo lectura que PostgREST usa para STABLE. Sin `count(` en el cuerpo: fuera del censo analítico, del de vigencia y de F7. El censo global sigue en ROJO por nueve piezas ajenas: no se llama al guardián; la migración guarda la foto de los dos censos y exige que quede idéntica, y fija el md5 de las siete dependencias (`gestiones_validar`, `gestiones_clientes_identidades`, `vendedor_ids_visibles`, `rol_crm`, `postventa_estado_fn`, `citas_clientes_core`, `citas_gerencia_consulta`; medidos iguales en producción y banco).

**Evidencia.** Banco Docker propio `crm-banco-proyeccion-0b-20261019` (127.0.0.1:55521) con `supabase db dump --linked` fresco (364 funciones crm / 781 private; md5 de las 13 dependencias iguales a producción) y el censo sembrado de producción (46 exenciones, sello cuadra). Casos sintéticos **48/48 PASS**: alcance gerencia/supervisor/vendedor con F6 on y off; paridad de ids con `crm.citas_clientes_fn` (filtrada por `creado_en`) para G, S1, V1, V2 y V3; creada en el rango y agendada fuera entra; creada fuera y agendada dentro no; bordes de día de Lima; reuniones con lead no entran (y sí están en el lector de Citas); `analista_*`/`supervisor_*` idénticos a `citas_gerencia_consulta` (supervisor por equipo y por tarea); anon, sin sesión, sin rol, coordinador, directorio, inactivo y service_role rechazados; rangos invertido, nulo y de 366 días rechazados (365 aceptado); asistencia por actividad de cliente y por cierre F6; redacción de la persona de otra cartera (`oculta:`). Tope: 10 000 filas en 133–160 ms; 10 001 → 54000. Mutantes 7/7 muertos (EXECUTE a anon, a service_role, `count(` que entra al censo, sin COMMENT, puerta DEFINER, núcleo STABLE, dependencia cambiada). Censos y mensaje del guardián idénticos antes y después. Reversión `supabase/scripts/revertir-20261019213516-citas-clientes-proyeccion.sql` ensayada dos veces: las otras 1 183 funciones de crm/private/public conservan la misma huella y el censo vuelve a su foto; reaplicada después. Producción (solo lectura): 37 reuniones creadas del 1 al 19 y del 1 al 31 de octubre (las 37 son personas F6, 19 completadas): Vladimir Jurado 8; Linda Condori, Lisseth Núñez y Merlys García 5; Alan Yutronic y Betzabeth Fuenmayor 3; Adelayda Gaspar, Daniela Castillo, Fiorella Ruiz y Miguel Briceño 2. Por `vence_en` también son 37, pero no las mismas: una creada el 28/09 y agendada el 09/10 sale y una creada el 07/10 y agendada el 01/11 entra. Coste con el cuerpo real como función temporal en `begin…rollback`: gerencia 190–540 ms (37 filas, 35 con identidad visible), supervisores 150–500 ms (22 + 15 = 37); la consulta sin identidad, 3–5 ms.

**Revisión.** `auditor-rls`: CHANGES_REQUESTED sin P0/P1. Aceptado: ledger, script de reversión ensayado y batería de alcance por rol, paridad, F6, redacción y tope (todo arriba); md5 de las dependencias en el preflight. Documentado, sin cambio: (a) `identidad_persona` no es la misma clave que el `identidad_persona` del lector de leads (aquí un perfil sólo es `persona:` con F6 y si su persona está en la cartera F5 visible; una identidad redactada da una clave por cita): la pantalla no debe emparejar las dos listas por esa clave; (b) el supervisor no ve reuniones de clientes sin responsable (regla de `citas_clientes_core`), mientras que el lector de leads sí le muestra las de su bandeja; (c) la asistencia lee `inversionista_gestiones` aunque F6 esté apagada (sólo una hora de una tarea que ya ve; con F6 apagada no entran reuniones de persona). La pantalla no debe sumar además el total `citas_clientes` del lector de Citas (otra población: perfil, por fecha programada). En producción, 2 de las 37 llegan como «Cliente fuera de tu cartera» incluso para gerencia (personas sin presencia en la cartera F5), igual que en «Citas de clientes». Borrador del front: `app/src/data/citas-clientes-proyeccion.ts` (+ test con el payload ejecutado en el banco), sin conectar a pantallas.

```

## Borrador del esquema del front (sin conectar)
```ts
import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import { CrmApiError } from './crm-api'
import { camposIdentidadCliente, identidadClienteValida } from '@/lib/sujeto-gestion'
import { FechaSchema } from '@/lib/esquemas-rpc'

/**
 * Proyección de citas, Fase 0b (19/10/2026): reuniones con CLIENTES que no tienen lead,
 * contadas por fecha de CREACIÓN (día de Lima), sin paginar. Puerta
 * `crm.citas_clientes_proyeccion_fn` → núcleo `private.citas_clientes_proyeccion`
 * (migración 20261019213516). BORRADOR: todavía no lo usa ninguna pantalla.
 *
 * Para la pantalla:
 * - Estas reuniones NO están en `crm.citas_gerencia_consulta[_v2]_fn` (que sólo recorre
 *   tareas con lead): se suman sin duplicar. El total `citas_clientes` de ese lector
 *   cuenta otra población (perfil, por fecha programada): no sumar ambos.
 * - Todas son citas con quien ya es cliente (perfil o persona F6).
 * - `identidad_persona` sólo nombra a la persona si su identidad es visible; si no, es
 *   `oculta:<id de la tarea>` (una por cita). No sirve para emparejar con el
 *   `identidad_persona` del lector de leads.
 */
const Instante = v.pipe(v.string(), v.check(s => Number.isFinite(Date.parse(s))))
const Id = v.pipe(v.string(), v.uuid())
const UUID_TEXTO = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

const CitaClienteProyeccionCampos = v.object({
  ...camposIdentidadCliente,
  id: Id, creado_en: Instante, vence_en: Instante,
  estado: v.picklist(['pendiente','completada','no_show','cancelada','reprogramada']),
  cancelada_por: v.nullable(v.string()),
  asistencia_registrada_en: v.nullable(Instante),
  analista_id: v.nullable(Id), analista_nombre: v.string(),
  supervisor_id: v.nullable(Id), supervisor_nombre: v.string(),
  identidad_persona: v.pipe(v.string(), v.regex(new RegExp(`^(persona|perfil|oculta):${UUID_TEXTO}$`))),
})
type CitaClienteProyeccionCruda = v.InferOutput<typeof CitaClienteProyeccionCampos>

/** La clave de persona tiene que salir de la identidad que el servidor dejó ver, y de nada más. */
function identidadPersonaCoherente(c: CitaClienteProyeccionCruda): boolean {
  if (!c.identidad_visible) return c.identidad_persona === `oculta:${c.id}`
  if (c.inversionista_id) return c.identidad_persona === `persona:${c.inversionista_id}`
  return c.perfil_id !== null && c.identidad_persona === `perfil:${c.perfil_id}`
}

export const CitaClienteProyeccionSchema = v.pipe(CitaClienteProyeccionCampos, v.check(c =>
  identidadClienteValida(c) && identidadPersonaCoherente(c)
  && (c.asistencia_registrada_en === null || c.estado === 'completada')))

export const CitasClientesProyeccionSchema = v.object({
  version: v.literal(1),
  periodo: v.object({ desde: FechaSchema, hasta: FechaSchema }),
  criterio: v.literal('creado_en'),
  generado_en: Instante,
  citas: v.pipe(v.array(CitaClienteProyeccionSchema), v.maxLength(10000)),
})
export type CitasClientesProyeccionRpc = v.InferOutput<typeof CitasClientesProyeccionSchema>
export type CitaClienteProyeccion = CitasClientesProyeccionRpc['citas'][number]

const fechaLima = (instante: string) => new Intl.DateTimeFormat('en-CA', {
  timeZone:'America/Lima', year:'numeric', month:'2-digit', day:'2-digit' }).format(new Date(instante))

/** El payload corresponde a lo pedido: mismo período, ids únicos y cada cita GENERADA dentro del rango. */
export function citasClientesProyeccionCoherentes(d: CitasClientesProyeccionRpc, desde: string, hasta: string): boolean {
  if (d.periodo.desde !== desde || d.periodo.hasta !== hasta) return false
  if (new Set(d.citas.map(c => c.id)).size !== d.citas.length) return false
  const generado = Date.parse(d.generado_en)
  return d.citas.every(c => {
    const dia = fechaLima(c.creado_en)
    return dia >= desde && dia <= hasta && Date.parse(c.creado_en) <= generado
      && (c.asistencia_registrada_en === null || Date.parse(c.asistencia_registrada_en) <= generado)
  })
}

type RespuestaSinTipos = { data: unknown; error: { code?: string | null; message?: string | null } | null }
type ConsultaSinTipos = PromiseLike<RespuestaSinTipos> & { abortSignal: (s: AbortSignal) => PromiseLike<RespuestaSinTipos> }

/**
 * La puerta todavía no sale de `gen:types` (se instala con la migración 20261019213516).
 * Misma llamada que `.rpc()` tipado; la respuesta se valida siempre con su esquema.
 * Se retira el cast cuando los tipos generados la conozcan.
 */
function rpcProyeccionClientes(args: { p_desde: string; p_hasta: string }, signal?: AbortSignal): PromiseLike<RespuestaSinTipos> {
  if (!sb) throw new CrmApiError('No se pudo conectar con el CRM.', 'CITAS_SIN_CONEXION')
  const crm = sb.schema('crm') as unknown as { rpc: (fn: string, a: Record<string, unknown>) => ConsultaSinTipos }
  const consulta = crm.rpc('citas_clientes_proyeccion_fn', args)
  return signal ? consulta.abortSignal(signal) : consulta
}

/** Reuniones con clientes sin lead generadas entre `desde` y `hasta` (YYYY-MM-DD, día de Lima; hasta un año). */
export async function cargarCitasClientesProyeccion(desde: string, hasta: string, signal?: AbortSignal): Promise<CitasClientesProyeccionRpc> {
  if (!v.is(FechaSchema, desde) || !v.is(FechaSchema, hasta) || desde > hasta) {
    throw new CrmApiError('Selecciona un rango válido.', 'CITAS_PERIODO')
  }
  const { data, error } = await rpcProyeccionClientes({ p_desde: desde, p_hasta: hasta }, signal)
  if (error) throw new CrmApiError(error.code === 'PGRST202'
    ? 'Las reuniones con clientes de la Proyección aún no están habilitadas en este servidor.'
    : 'No se pudieron cargar las reuniones con clientes. Reintenta la consulta.', error.code ?? undefined)
  const resultado = v.safeParse(CitasClientesProyeccionSchema, data)
  if (!resultado.success || !citasClientesProyeccionCoherentes(resultado.output, desde, hasta)) {
    throw new CrmApiError('La respuesta de reuniones con clientes está incompleta o no corresponde al rango.', 'CITAS_CONTRATO')
  }
  return resultado.output
}
```

## Batería del banco (datos sintéticos)
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
  ('d6 sin responsable: Sin analista + supervisor de la tarea',
     '|Sin analista|00000000-0000-0000-0000-0000000000e2|SUPERVISOR UNO',
     (select concat_ws('|', coalesce(c->>'analista_id',''), c->>'analista_nombre', c->>'supervisor_id', c->>'supervisor_nombre') from r_on, pg_temp.cita(p,'d6') c where quien='G'))
) as x(caso, esperado, obtenido);

select n, case when esperado is not distinct from obtenido then 'PASS' else 'FAIL' end as veredicto, caso,
       case when esperado is distinct from obtenido then 'esperado=' || coalesce(esperado,'∅') || ' obtenido=' || coalesce(obtenido,'∅') else '' end as detalle
from casos order by n;
select 'TOTAL ' || sum((esperado is not distinct from obtenido)::int) || '/' || max(n) from casos;
-- Mensajes de los rechazos, para el informe
select quien, p->>'error' as sqlstate, p->>'msg' as mensaje from r_on where p ? 'error' order by quien;

-- Tope: 10 000 reuniones creadas en junio pasan; la 10 001 devuelve 54000 (nunca una lista truncada).
update crm.multiempresa_flags set activo = true where nombre = 'postventa_neutral';
insert into crm.tareas (lead_id, perfil_id, vendedor_id, tipo, titulo, vence_en, estado, activo, creado_en, modalidad_reunion)
select null, '00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000e3', 'reunion', 'T ' || g,
       timestamptz '2026-06-20 10:00-05', 'pendiente', true, timestamptz '2026-06-01 08:00-05' + (g || ' seconds')::interval, 'sin_clasificar'
from generate_series(1, 10000) g;
\timing on
select 'tope 10000 → ' || coalesce(jsonb_array_length(p->'citas')::text, p->>'error') from (select pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e1', date '2026-06-01', date '2026-06-30') p) x;
\timing off
insert into crm.tareas (lead_id, perfil_id, vendedor_id, tipo, titulo, vence_en, estado, activo, creado_en, modalidad_reunion)
values (null, '00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000e3', 'reunion', 'T extra',
       timestamptz '2026-06-20 10:00-05', 'pendiente', true, timestamptz '2026-06-30 08:00-05', 'sin_clasificar');
select 'tope 10001 → ' || coalesce(p->>'error', 'SIN ERROR (FAIL)') || ' · ' || coalesce(p->>'msg','') from (select pg_temp.llamar('authenticated', '00000000-0000-0000-0000-0000000000e1', date '2026-06-01', date '2026-06-30') p) x;
rollback;
```

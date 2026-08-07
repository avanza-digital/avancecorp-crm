-- LEGACY / FIXTURE HISTORICO PRE-20260807203757.
-- Define las metas antiguas solo para reproducir migraciones históricas; no es
-- el gate vigente de Metas. Usar test-metas-versionadas.sql para esa frontera.
\set ON_ERROR_STOP on

-- Oráculo autocontenido de 20260805180000, 20260805200000 y 20260805213000.
-- Se ejecuta exclusivamente contra un PostgreSQL temporal y desechable: crea
-- la frontera previa mínima, aplica LAS migraciones reales y prueba sus
-- contratos sin depender del proyecto remoto.

do $$
declare v_rol text;
begin
  foreach v_rol in array array['anon', 'authenticated', 'service_role'] loop
    if not exists (select 1 from pg_roles where rolname = v_rol) then
      execute format('create role %I nologin', v_rol);
    end if;
  end loop;
end;
$$;

create schema auth;
create schema crm;
create schema private;

-- Helpers locales del oráculo. Son SECURITY INVOKER, fijan search_path y no se
-- exponen a PUBLIC: únicamente compactan assertions sin alterar privilegios.
create function private.test_fallar_si(
  p_condicion_de_fallo boolean,
  p_mensaje text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_condicion_de_fallo then
    raise exception using message = p_mensaje;
  end if;
end;
$$;

create function private.test_esperar_sqlstate(
  p_sentencia text,
  p_sqlstate_esperado text,
  p_mensaje_si_aceptada text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  execute p_sentencia;
  raise exception using message = p_mensaje_si_aceptada;
exception
  when others then
    if sqlstate <> p_sqlstate_esperado then
      raise;
    end if;
end;
$$;

revoke all on function private.test_fallar_si(boolean, text) from public;
revoke all on function private.test_esperar_sqlstate(text, text, text) from public;

create function auth.uid()
returns uuid
language sql
stable
set search_path = ''
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create table auth.users (
  id uuid primary key
);

create table public.perfiles (
  id uuid primary key,
  nombre_completo text,
  rol text not null default 'analista',
  activo boolean not null default true
);

create table public.contratos (
  id uuid primary key,
  creado_en timestamptz not null default now(),
  capital numeric not null,
  moneda text not null
);

create table crm.equipo (
  perfil_id uuid primary key references public.perfiles(id),
  rol_crm text not null,
  supervisor_id uuid,
  activo boolean not null default true,
  capacidad_leads_objetivo integer
);

create table crm.leads (
  id uuid primary key default gen_random_uuid(),
  activo boolean not null default true,
  etapa text not null default 'nuevo',
  vendedor_id uuid,
  asignado_supervisor_id uuid,
  perfil_id uuid,
  contrato_id uuid,
  origen text,
  categoria_interes text,
  convertido_en timestamptz,
  creado_en timestamptz not null default now()
);

create table crm.lead_asignaciones (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null
);

create table crm.actividades (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null,
  tipo text not null,
  detalle text,
  metadata jsonb not null default '{}'::jsonb,
  creado_por uuid,
  creado_en timestamptz not null default now()
);

create table crm.tareas (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid,
  perfil_id uuid,
  vendedor_id uuid,
  asignado_supervisor_id uuid,
  tipo text not null,
  titulo text not null,
  nota text,
  vence_en timestamptz not null,
  duracion_min smallint,
  estado text not null default 'pendiente',
  resultado_actividad_id uuid,
  reagendada_de uuid,
  confirmada_en timestamptz,
  reprogramaciones integer not null default 0,
  activo boolean not null default true,
  cancelada_por text,
  cancelada_por_id uuid,
  creado_por uuid,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint tareas_estado_valido
    check (estado in ('pendiente','completada','cancelada','no_show'))
);

create table crm.agenda_ics (
  perfil_id uuid primary key,
  token uuid not null unique
);

alter table crm.leads enable row level security;
alter table crm.actividades enable row level security;
alter table crm.tareas enable row level security;

create function private.rol_crm(p_uid uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select e.rol_crm
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_uid and e.activo and p.activo;
$$;

create function private.vendedor_ids_visibles(p_uid uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select e.perfil_id
  from crm.equipo e
  where e.activo and (
    private.rol_crm(p_uid) = 'gerencia'
    or e.perfil_id = p_uid
    or (private.rol_crm(p_uid) = 'supervisor' and e.supervisor_id = p_uid)
  );
$$;

create function private.es_lector_global()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select false; $$;

create function private.retroceso_por_anular_reunion(uuid, uuid, uuid)
returns text
language sql
set search_path = ''
as $$ select null::text; $$;

-- Dependencias preexistentes de la tabla de metas individuales.
create function private.set_actualizado_en_crm()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.actualizado_en := now();
  return new;
end;
$$;

create function private.log_audit_crm()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

-- La migración nueva conserva la RPC anterior únicamente para trazabilidad y
-- debe quitarle EXECUTE a authenticated.
create function crm.fijar_objetivos(date, jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$ begin null; end; $$;

revoke all on function crm.fijar_objetivos(date, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function crm.fijar_objetivos(date, jsonb)
  to authenticated, service_role;

revoke all on function private.set_actualizado_en_crm()
  from public, anon, authenticated, service_role;
revoke all on function private.log_audit_crm()
  from public, anon, authenticated, service_role;

-- Los triggers ya existen antes de la migración; CREATE OR REPLACE debe
-- cambiar su implementación sin perder su vínculo con la tabla.
create function private.trg_tareas_before_insert()
returns trigger language plpgsql as $$ begin return new; end; $$;
create function private.trg_tareas_before_update()
returns trigger language plpgsql as $$ begin return new; end; $$;
create trigger trg_tareas_before_insert
before insert on crm.tareas
for each row execute function private.trg_tareas_before_insert();
create trigger trg_tareas_before_update
before update on crm.tareas
for each row execute function private.trg_tareas_before_update();

-- Convención de fixtures: 100… perfiles, 200… leads, 300… tareas,
-- 400… contratos y 500… tokens de agenda. El sufijo identifica cada escenario.
insert into public.perfiles (id, nombre_completo) values
  ('10000000-0000-4000-8000-000000000001', 'Gerencia'),
  ('10000000-0000-4000-8000-000000000002', 'Supervisión'),
  ('10000000-0000-4000-8000-000000000003', 'Analista'),
  ('10000000-0000-4000-8000-000000000004', 'Cliente'),
  ('10000000-0000-4000-8000-000000000005', 'Analista sin muestra');
insert into auth.users (id) values
  ('10000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-000000000002'),
  ('10000000-0000-4000-8000-000000000003'),
  ('10000000-0000-4000-8000-000000000004'),
  ('10000000-0000-4000-8000-000000000005');
insert into crm.equipo (perfil_id, rol_crm, supervisor_id) values
  ('10000000-0000-4000-8000-000000000001', 'gerencia', null),
  ('10000000-0000-4000-8000-000000000002', 'supervisor', null),
  ('10000000-0000-4000-8000-000000000003', 'vendedor', '10000000-0000-4000-8000-000000000002'),
  ('10000000-0000-4000-8000-000000000005', 'vendedor', '10000000-0000-4000-8000-000000000002');
insert into crm.leads (
  id, etapa, vendedor_id, origen, categoria_interes, creado_en
) values (
  '20000000-0000-4000-8000-000000000001', 'reunion_agendada',
  '10000000-0000-4000-8000-000000000003', 'referido', 'inversion', now() - interval '10 days'
);

-- Historia previa: la migración debe clasificarla sin inventar modalidad.
insert into crm.tareas (
  id, lead_id, vendedor_id, tipo, titulo, vence_en, estado, creado_por
) values (
  '30000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000003',
  'reunion', 'Reunión histórica', now() - interval '4 days', 'completada',
  '10000000-0000-4000-8000-000000000003'
);

-- Reproduce la frontera de permisos ya existente antes de las migraciones.
grant usage on schema auth, crm, private to authenticated;
grant usage on schema crm, private to service_role;
grant select on public.perfiles, crm.equipo to authenticated;
grant execute on function private.rol_crm(uuid) to authenticated;
grant execute on function private.vendedor_ids_visibles(uuid) to authenticated;
grant execute on function private.es_lector_global() to authenticated;

\ir ../migrations/20260805180000_crm_inteligencia_comercial_reuniones.sql
\ir ../migrations/20260805200000_crm_conversion_vendedor_detalle.sql
\ir ../migrations/20260805213000_crm_objetivos_por_vendedor.sql

-- Seguridad estructural: search_path fijo y privilegios mínimos por superficie.
do $$
declare
  v_firma text;
begin
  foreach v_firma in array array[
    'private.trg_tareas_before_insert()',
    'private.trg_tareas_before_update()',
    'private.crear_siguiente_tarea(crm.tareas,jsonb,uuid,uuid)',
    'crm.cerrar_tarea(uuid,text,text,text,jsonb)',
    'crm.cerrar_reunion(uuid,text,text,text,text,jsonb)',
    'crm.reprogramar_reunion(uuid,timestamp with time zone,uuid)',
    'crm.metricas_conversiones_fn(date,date)',
    'crm.metricas_reuniones_fn(date,date)',
    'crm.fijar_objetivos_vendedores(date,jsonb)'
  ]
  loop
    if not exists (
      select 1
      from pg_proc p
      where p.oid = v_firma::regprocedure
        and p.prosecdef
        and 'search_path=""' = any(coalesce(p.proconfig, '{}'::text[]))
    ) then
      raise exception 'SECURITY DEFINER sin search_path vacío: %', v_firma;
    end if;
  end loop;

  if has_function_privilege(
       'authenticated',
       'private.crear_siguiente_tarea(crm.tareas,jsonb,uuid,uuid)',
       'execute'
     )
     or has_function_privilege(
       'anon',
       'crm.cerrar_reunion(uuid,text,text,text,text,jsonb)',
       'execute'
     )
     or not has_function_privilege(
       'authenticated',
       'crm.cerrar_reunion(uuid,text,text,text,text,jsonb)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'crm.agenda_ics_feed_fn(uuid,timestamp with time zone)',
       'execute'
     )
     or not has_function_privilege(
       'service_role',
       'crm.agenda_ics_feed_fn(uuid,timestamp with time zone)',
       'execute'
     )
     or has_function_privilege(
       'anon',
       'crm.metricas_conversiones_fn(date,date)',
       'execute'
     )
     or not has_function_privilege(
       'authenticated',
       'crm.metricas_conversiones_fn(date,date)',
       'execute'
     )
     or has_function_privilege(
       'service_role',
       'crm.metricas_conversiones_fn(date,date)',
       'execute'
     )
     or has_function_privilege(
       'anon',
       'crm.fijar_objetivos_vendedores(date,jsonb)',
       'execute'
     )
     or not has_function_privilege(
       'authenticated',
       'crm.fijar_objetivos_vendedores(date,jsonb)',
       'execute'
     )
     or not has_function_privilege(
       'service_role',
       'crm.fijar_objetivos_vendedores(date,jsonb)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'crm.fijar_objetivos(date,jsonb)',
       'execute'
     ) then
    raise exception 'Los privilegios EXECUTE no respetan el mínimo necesario';
  end if;

  if not exists (
       select 1
       from pg_class c
       where c.oid = 'crm.objetivos_vendedores'::regclass
         and c.relrowsecurity
     )
     or not has_table_privilege(
       'authenticated', 'crm.objetivos_vendedores', 'select'
     )
     or has_table_privilege(
       'authenticated', 'crm.objetivos_vendedores', 'insert,update,delete'
     )
     or has_table_privilege(
       'anon', 'crm.objetivos_vendedores', 'select'
     )
     or not has_table_privilege(
       'service_role', 'crm.objetivos_vendedores', 'select,insert,update,delete'
     ) then
    raise exception 'La tabla de metas individuales no conserva RLS y privilegios mínimos';
  end if;
end;
$$;

-- La falta de sesión se rechaza incluso usando el rol de clientes autenticados.
reset request.jwt.claim.sub;
set role authenticated;
do $$
begin
  begin
    perform crm.metricas_conversiones_fn(current_date - 30, current_date);
    raise exception 'Una sesión sin auth.uid() pudo consultar conversiones';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;
reset role;

-- Anon no puede cruzar ninguna de las dos RPC nuevas ni leer las metas.
set role anon;
do $$
begin
  begin
    perform crm.metricas_conversiones_fn(current_date - 30, current_date);
    raise exception 'Anon pudo consultar conversiones';
  exception
    when insufficient_privilege then null;
  end;
  begin
    perform crm.fijar_objetivos_vendedores(
      date_trunc('month', current_date)::date,
      '{}'::jsonb
    );
    raise exception 'Anon pudo fijar metas individuales';
  exception
    when insufficient_privilege then null;
  end;
  begin
    perform 1 from crm.objetivos_vendedores;
    raise exception 'Anon pudo leer metas individuales';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;
reset role;

-- Gerencia reemplaza atómicamente una meta por cada vendedor activo.
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
set role authenticated;
do $$
declare
  v_periodo date := date_trunc('month', current_date)::date;
  v_filas integer;
begin
  select count(*)::integer
  into v_filas
  from crm.fijar_objetivos_vendedores(
    v_periodo,
    jsonb_build_object(
      '10000000-0000-4000-8000-000000000003', jsonb_build_object(
        'capital_objetivo', 300000,
        'ventas_objetivo', 2,
        'conversion_objetivo', 18
      ),
      '10000000-0000-4000-8000-000000000005', jsonb_build_object(
        'capital_objetivo', 150000,
        'ventas_objetivo', 1,
        'conversion_objetivo', 15
      )
    )
  );

  if v_filas <> 2
     or (select count(*) from crm.objetivos_vendedores where periodo = v_periodo) <> 2
     or not exists (
       select 1
       from crm.objetivos_vendedores
       where periodo = v_periodo
         and vendedor_id = '10000000-0000-4000-8000-000000000003'
         and supervisor_id = '10000000-0000-4000-8000-000000000002'
         and capital_objetivo = 300000
         and ventas_objetivo = 2
         and conversion_objetivo = 18
         and actualizado_por = '10000000-0000-4000-8000-000000000001'
     )
  then
    raise exception 'Gerencia no pudo persistir el bloque completo de metas';
  end if;

  begin
    perform *
    from crm.fijar_objetivos_vendedores(
      v_periodo,
      jsonb_build_object(
        '10000000-0000-4000-8000-000000000003', jsonb_build_object(
          'capital_objetivo', 1,
          'ventas_objetivo', 1,
          'conversion_objetivo', 1
        )
      )
    );
    raise exception 'Se aceptó un bloque incompleto de metas';
  exception
    when invalid_parameter_value then null;
  end;

  if (select count(*) from crm.objetivos_vendedores where periodo = v_periodo) <> 2
     or not exists (
       select 1
       from crm.objetivos_vendedores
       where periodo = v_periodo
         and vendedor_id = '10000000-0000-4000-8000-000000000003'
         and capital_objetivo = 300000
     )
  then
    raise exception 'El rechazo de metas incompletas no fue atómico';
  end if;
end;
$$;
reset role;

-- RLS: cada vendedor ve solo su meta; el supervisor ve las de su equipo. Ninguno
-- puede usar la puerta de escritura reservada a Gerencia.
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';
set role authenticated;
do $$
begin
  if (select count(*) from crm.objetivos_vendedores) <> 1
     or not exists (
       select 1 from crm.objetivos_vendedores
       where vendedor_id = '10000000-0000-4000-8000-000000000003'
     )
  then
    raise exception 'RLS no aisló la meta del vendedor';
  end if;

  begin
    perform *
    from crm.fijar_objetivos_vendedores(
      date_trunc('month', current_date)::date,
      '{}'::jsonb
    );
    raise exception 'Un vendedor pudo fijar metas';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;
reset role;

set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';
set role authenticated;
do $$
begin
  if (select count(*) from crm.objetivos_vendedores) <> 2 then
    raise exception 'RLS no mostró al supervisor las metas de su equipo';
  end if;

  begin
    perform *
    from crm.fijar_objetivos_vendedores(
      date_trunc('month', current_date)::date,
      '{}'::jsonb
    );
    raise exception 'Un supervisor pudo fijar metas';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;
reset role;
reset request.jwt.claim.sub;

do $$
begin
  perform private.test_fallar_si(
    not exists (
      select 1 from crm.tareas
      where id = '30000000-0000-4000-8000-000000000001'
        and modalidad_reunion = 'sin_clasificar'
        and resultado_reunion = 'sin_clasificar'
    ),
    'La historia de reuniones no se clasificó honestamente'
  );
end;
$$;

-- Nueva reunión presencial y reprogramación: la original no se pisa.
insert into crm.tareas (
  id, lead_id, tipo, titulo, vence_en, modalidad_reunion,
  ubicacion_reunion, creado_por
) values (
  '30000000-0000-4000-8000-000000000002',
  '20000000-0000-4000-8000-000000000001',
  'reunion', 'Reunión operativa', now() - interval '2 days', 'presencial',
  'Av. Arequipa 123', '10000000-0000-4000-8000-000000000003'
);

set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';
select crm.reprogramar_reunion(
  '30000000-0000-4000-8000-000000000002',
  now() - interval '1 day',
  '30000000-0000-4000-8000-000000000003'
);

do $$
begin
  perform private.test_fallar_si(
    not exists (
      select 1 from crm.tareas
      where id = '30000000-0000-4000-8000-000000000002'
        and estado = 'reprogramada'
        and motivo_no_realizada = 'reprogramada'
    ),
    'La reunión original no conservó la reprogramación'
  );
  perform private.test_fallar_si(
    not exists (
      select 1 from crm.tareas
      where id = '30000000-0000-4000-8000-000000000003'
        and estado = 'pendiente'
        and reagendada_de = '30000000-0000-4000-8000-000000000002'
        and modalidad_reunion = 'presencial'
        and ubicacion_reunion = 'Av. Arequipa 123'
        and reprogramaciones = 1
    ),
    'La reunión nueva no quedó enlazada y clasificada'
  );
end;
$$;

-- Cierre estructurado y rechazo de un cierre sin resultado.
do $$
begin
  perform private.test_esperar_sqlstate(
    $sql$
      select crm.cerrar_reunion(
        '30000000-0000-4000-8000-000000000003',
        'completada', null, null, null, null
      )
    $sql$,
    '22023',
    'Se aceptó una reunión realizada sin resultado'
  );
end;
$$;

select crm.cerrar_reunion(
  '30000000-0000-4000-8000-000000000003',
  'completada', 'propuesta', null, 'Solicitó propuesta formal', null
);

do $$
begin
  perform private.test_fallar_si(
    not exists (
      select 1 from crm.tareas
      where id = '30000000-0000-4000-8000-000000000003'
        and estado = 'completada'
        and resultado_reunion = 'propuesta'
    ),
    'El cierre estructurado no persistió'
  );
  perform private.test_fallar_si(
    not exists (
      select 1 from crm.actividades
      where lead_id = '20000000-0000-4000-8000-000000000001'
        and tipo = 'reunion_realizada'
        and metadata->>'resultado_reunion' = 'propuesta'
    ),
    'El cierre no dejó actividad auditable'
  );
end;
$$;

reset request.jwt.claim.sub;
insert into public.contratos (id, creado_en, capital, moneda) values (
  '40000000-0000-4000-8000-000000000001', now() - interval '1 day', 250000, 'PEN'
);
update crm.leads set
  etapa = 'convertido',
  perfil_id = '10000000-0000-4000-8000-000000000004',
  contrato_id = '40000000-0000-4000-8000-000000000001',
  convertido_en = now() - interval '1 day'
where id = '20000000-0000-4000-8000-000000000001';

-- Gerencia puede editar capacidad, pero no operar leads/tareas/actividades.
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
update crm.equipo set capacidad_leads_objetivo = 40
where perfil_id = '10000000-0000-4000-8000-000000000003';

do $$
begin
  perform private.test_esperar_sqlstate(
    $sql$
      update crm.leads set etapa = 'nuevo'
      where id = '20000000-0000-4000-8000-000000000001'
    $sql$,
    '42501',
    'Gerencia pudo operar un lead'
  );
end;
$$;

-- El bloqueo de Gerencia cubre insert/update/delete en las tres tablas operativas.
do $$
begin
  perform private.test_esperar_sqlstate(
    $sql$
      insert into crm.leads select * from crm.leads
      where id = '20000000-0000-4000-8000-000000000001'
    $sql$,
    '42501',
    'Gerencia pudo insertar un lead'
  );
  perform private.test_esperar_sqlstate(
    $sql$
      delete from crm.leads
      where id = '20000000-0000-4000-8000-000000000001'
    $sql$,
    '42501',
    'Gerencia pudo eliminar un lead'
  );
  perform private.test_esperar_sqlstate(
    $sql$
      update crm.tareas set titulo = titulo
      where id = '30000000-0000-4000-8000-000000000003'
    $sql$,
    '42501',
    'Gerencia pudo actualizar una tarea'
  );
  perform private.test_esperar_sqlstate(
    $sql$
      insert into crm.tareas select * from crm.tareas
      where id = '30000000-0000-4000-8000-000000000003'
    $sql$,
    '42501',
    'Gerencia pudo insertar una tarea'
  );
  perform private.test_esperar_sqlstate(
    $sql$
      delete from crm.tareas
      where id = '30000000-0000-4000-8000-000000000003'
    $sql$,
    '42501',
    'Gerencia pudo eliminar una tarea'
  );
  perform private.test_esperar_sqlstate(
    $sql$
      update crm.actividades set detalle = detalle
      where lead_id = '20000000-0000-4000-8000-000000000001'
        and tipo = 'reunion_realizada'
    $sql$,
    '42501',
    'Gerencia pudo actualizar una actividad'
  );
  perform private.test_esperar_sqlstate(
    $sql$
      insert into crm.actividades select * from crm.actividades
      where lead_id = '20000000-0000-4000-8000-000000000001'
        and tipo = 'reunion_realizada'
    $sql$,
    '42501',
    'Gerencia pudo insertar una actividad'
  );
  perform private.test_esperar_sqlstate(
    $sql$
      delete from crm.actividades
      where lead_id = '20000000-0000-4000-8000-000000000001'
        and tipo = 'reunion_realizada'
    $sql$,
    '42501',
    'Gerencia pudo eliminar una actividad'
  );
end;
$$;

-- Un vendedor no puede consultar fotografías globales ni alterar reuniones cerradas.
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';
do $$
begin
  perform private.test_esperar_sqlstate(
    $sql$
      select crm.metricas_conversiones_fn(current_date - 30, current_date)
    $sql$,
    '42501',
    'Un vendedor pudo consultar métricas globales'
  );
  perform private.test_esperar_sqlstate(
    $sql$
      select crm.metricas_reuniones_fn(current_date - 30, current_date)
    $sql$,
    '42501',
    'Un vendedor pudo consultar métricas de reuniones'
  );
  perform private.test_esperar_sqlstate(
    $sql$
      update crm.tareas set resultado_reunion = 'interesado'
      where id = '30000000-0000-4000-8000-000000000003'
    $sql$,
    '22023',
    'Se pudo alterar el resultado de una reunión cerrada'
  );
  perform private.test_esperar_sqlstate(
    $sql$
      update crm.tareas set titulo = 'Original alterada'
      where id = '30000000-0000-4000-8000-000000000002'
    $sql$,
    '22023',
    'Se pudo alterar la reunión original reprogramada'
  );
end;
$$;

-- Los datos estructurados no admiten modalidades ni enlaces inseguros.
reset request.jwt.claim.sub;
do $$
begin
  perform private.test_esperar_sqlstate(
    $sql$
      insert into crm.tareas (
        id, perfil_id, tipo, titulo, vence_en, modalidad_reunion, creado_por
      ) values (
        '30000000-0000-4000-8000-000000000005',
        '10000000-0000-4000-8000-000000000003',
        'reunion', 'Modalidad inválida', now() + interval '4 days', 'telefonica',
        '10000000-0000-4000-8000-000000000003'
      )
    $sql$,
    '23514',
    'Se aceptó una modalidad inválida'
  );
  perform private.test_esperar_sqlstate(
    $sql$
      insert into crm.tareas (
        id, perfil_id, tipo, titulo, vence_en, modalidad_reunion,
        enlace_reunion, creado_por
      ) values (
        '30000000-0000-4000-8000-000000000006',
        '10000000-0000-4000-8000-000000000003',
        'reunion', 'Enlace inseguro', now() + interval '4 days', 'virtual',
        'javascript:alert(1)', '10000000-0000-4000-8000-000000000003'
      )
    $sql$,
    '23514',
    'Se aceptó un enlace de reunión inseguro'
  );
  perform private.test_esperar_sqlstate(
    $sql$
      insert into crm.tareas (
        id, perfil_id, tipo, titulo, vence_en, modalidad_reunion,
        enlace_reunion, creado_por
      ) values (
        '30000000-0000-4000-8000-000000000009',
        '10000000-0000-4000-8000-000000000003',
        'reunion', 'Enlace sin cifrar', now() + interval '4 days', 'virtual',
        'http://meet.example.com/sala', '10000000-0000-4000-8000-000000000003'
      )
    $sql$,
    '23514',
    'Se aceptó un enlace HTTP sin cifrar'
  );
  perform private.test_esperar_sqlstate(
    $sql$
      insert into crm.tareas (
        id, perfil_id, tipo, titulo, vence_en, modalidad_reunion, creado_por
      ) values (
        '30000000-0000-4000-8000-000000000010',
        '10000000-0000-4000-8000-000000000003',
        'reunion', 'Virtual sin destino', now() + interval '4 days', 'virtual',
        '10000000-0000-4000-8000-000000000003'
      )
    $sql$,
    '23514',
    'Se aceptó una reunión virtual sin enlace'
  );
  perform private.test_esperar_sqlstate(
    $sql$
      insert into crm.tareas (
        id, perfil_id, tipo, titulo, vence_en, modalidad_reunion,
        ubicacion_reunion, enlace_reunion, creado_por
      ) values (
        '30000000-0000-4000-8000-000000000011',
        '10000000-0000-4000-8000-000000000003',
        'reunion', 'Presencial contradictoria', now() + interval '4 days', 'presencial',
        'Av. Arequipa 123', 'https://meet.example.com/sala',
        '10000000-0000-4000-8000-000000000003'
      )
    $sql$,
    '23514',
    'Se aceptaron lugar y enlace contradictorios'
  );
end;
$$;

-- Reunión pendiente para probar motivo obligatorio y veto operativo de Gerencia.
insert into crm.leads (
  id, etapa, vendedor_id, origen, categoria_interes, creado_en
) values (
  '20000000-0000-4000-8000-000000000002', 'contactado',
  '10000000-0000-4000-8000-000000000003', 'web', 'nuevo', now() - interval '40 days'
);

insert into crm.tareas (
  id, lead_id, tipo, titulo, vence_en, modalidad_reunion, enlace_reunion, creado_por
) values (
  '30000000-0000-4000-8000-000000000007',
  '20000000-0000-4000-8000-000000000002',
  'reunion', 'Reunión protegida', now() + interval '5 days', 'virtual',
  'https://meet.google.com/pro-teg-ida',
  '10000000-0000-4000-8000-000000000003'
);

set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';
do $$
begin
  perform private.test_esperar_sqlstate(
    $sql$
      select crm.cerrar_reunion(
        '30000000-0000-4000-8000-000000000007',
        null, null, null, null, null
      )
    $sql$,
    '22023',
    'Se aceptó un estado nulo'
  );
  perform private.test_esperar_sqlstate(
    $sql$
      select crm.cerrar_reunion(
        '30000000-0000-4000-8000-000000000007',
        'cancelada', null, null, null, null
      )
    $sql$,
    '22023',
    'Se aceptó una cancelación sin motivo'
  );
  perform private.test_esperar_sqlstate(
    $sql$
      select crm.cerrar_reunion(
        '30000000-0000-4000-8000-000000000007',
        'cancelada', null, 'otro', null, null
      )
    $sql$,
    '22023',
    'Se aceptó otro motivo sin detalle'
  );
end;
$$;

set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
do $$
begin
  perform private.test_esperar_sqlstate(
    $sql$
      select crm.cerrar_reunion(
        '30000000-0000-4000-8000-000000000007',
        'cancelada', null, 'cancelada_empresa', null, null
      )
    $sql$,
    '42501',
    'Gerencia pudo cerrar una reunión'
  );
  perform private.test_esperar_sqlstate(
    $sql$
      select crm.reprogramar_reunion(
        '30000000-0000-4000-8000-000000000007',
        now() + interval '6 days',
        '30000000-0000-4000-8000-000000000008'
      )
    $sql$,
    '42501',
    'Gerencia pudo reprogramar una reunión'
  );
end;
$$;

-- Las dos fotografías deben ejecutar y conservar su contrato mínimo.
do $$
declare
  v_metricas_conversion jsonb;
  v_metricas_reuniones jsonb;
  v_modalidad_presencial jsonb;
  v_responsable_con_datos jsonb;
  v_responsable_sin_muestra jsonb;
  v_tendencia_leads integer;
  v_tendencia_clientes integer;
begin
  v_metricas_conversion := crm.metricas_conversiones_fn(current_date - 30, current_date);
  v_metricas_reuniones := crm.metricas_reuniones_fn(current_date - 30, current_date);
  select modalidad into v_modalidad_presencial
  from jsonb_array_elements(v_metricas_reuniones->'modalidades') modalidad
  where modalidad->>'modalidad' = 'presencial';
  select responsable into v_responsable_con_datos
  from jsonb_array_elements(v_metricas_conversion->'responsables') responsable
  where responsable->>'vendedor_id' = '10000000-0000-4000-8000-000000000003';
  select responsable into v_responsable_sin_muestra
  from jsonb_array_elements(v_metricas_conversion->'responsables') responsable
  where responsable->>'vendedor_id' = '10000000-0000-4000-8000-000000000005';
  select
    coalesce(sum((semana->>'leads')::integer), 0)::integer,
    coalesce(sum((semana->>'clientes')::integer), 0)::integer
  into v_tendencia_leads, v_tendencia_clientes
  from jsonb_array_elements(v_responsable_con_datos->'tendencia_semanal') semana;
  perform private.test_fallar_si(
    (v_metricas_conversion->>'version')::int <> 1
      or (v_metricas_conversion#>>'{cohorte,leads}')::int <> 1
      or (v_metricas_conversion#>>'{cohorte,contratos}')::int <> 1
      or (v_metricas_conversion#>>'{produccion,capital_pen}')::numeric <> 250000,
    'La fotografía de conversiones no coincide con la cohorte'
  );
  perform private.test_fallar_si(
    jsonb_typeof(v_metricas_conversion->'responsables') is distinct from 'array'
      or jsonb_array_length(v_metricas_conversion->'responsables') <> 2
      or v_responsable_con_datos is null
      or (v_responsable_con_datos->>'leads')::integer <> 1
      or (v_responsable_con_datos->>'contactados')::integer <> 1
      or (v_responsable_con_datos->>'reuniones_realizadas')::integer <> 1
      or (v_responsable_con_datos->>'clientes')::integer <> 1
      or (v_responsable_con_datos->>'conversion_pct')::numeric <> 100
      or (v_responsable_con_datos->>'capital_pen')::numeric <> 250000
      or (v_responsable_con_datos->>'capital_usd')::numeric <> 0
      or jsonb_array_length(v_responsable_con_datos->'tendencia_semanal') = 0
      or v_tendencia_leads <> 1
      or v_tendencia_clientes <> 1,
    'El detalle del vendedor con datos no coincide con su cohorte y producción'
  );
  perform private.test_fallar_si(
    v_responsable_sin_muestra is null
      or (v_responsable_sin_muestra->>'leads')::integer <> 0
      or (v_responsable_sin_muestra->>'contactados')::integer <> 0
      or (v_responsable_sin_muestra->>'reuniones_realizadas')::integer <> 0
      or (v_responsable_sin_muestra->>'clientes')::integer <> 0
      or v_responsable_sin_muestra->'conversion_pct' is distinct from 'null'::jsonb
      or (v_responsable_sin_muestra->>'capital_pen')::numeric <> 0
      or (v_responsable_sin_muestra->>'capital_usd')::numeric <> 0
      or jsonb_array_length(v_responsable_sin_muestra->'tendencia_semanal') = 0
      or exists (
        select 1
        from jsonb_array_elements(v_responsable_sin_muestra->'tendencia_semanal') semana
        where (semana->>'leads')::integer <> 0
          or (semana->>'clientes')::integer <> 0
          or semana->'conversion_pct' is distinct from 'null'::jsonb
      ),
    'El vendedor sin muestra no quedó representado con ceros y conversión nula'
  );
  perform private.test_fallar_si(
    (v_metricas_reuniones->>'version')::int <> 1
      or (v_metricas_reuniones#>>'{resumen,reprogramadas}')::int <> 1
      or (v_metricas_reuniones#>>'{resumen,pct_realizacion}')::numeric <> 100
      or (v_metricas_reuniones#>>'{conversion,contratos}')::int <> 1
      or v_modalidad_presencial is null
      or (v_modalidad_presencial->>'pct_realizacion')::numeric <> 100,
    'La fotografía de reuniones no coincide con la ejecución'
  );
end;
$$;

-- El feed externo conserva modalidad y ubicación de una reunión pendiente.
reset request.jwt.claim.sub;
insert into crm.tareas (
  id, lead_id, tipo, titulo, vence_en, modalidad_reunion, enlace_reunion, creado_por
) values (
  '30000000-0000-4000-8000-000000000004',
  '20000000-0000-4000-8000-000000000002',
  'reunion', 'Reunión virtual', now() + interval '3 days', 'virtual',
  'https://meet.google.com/abc-defg-hij', '10000000-0000-4000-8000-000000000003'
);
insert into crm.agenda_ics (perfil_id, token) values (
  '10000000-0000-4000-8000-000000000003',
  '50000000-0000-4000-8000-000000000001'
);

do $$
declare v_feed_ics jsonb;
begin
  v_feed_ics := crm.agenda_ics_feed_fn(
    '50000000-0000-4000-8000-000000000001', now() - interval '1 day'
  );
  perform private.test_fallar_si(
    not (v_feed_ics->>'autorizado')::boolean
      or v_feed_ics#>>'{tareas,0,modalidad_reunion}' <> 'virtual'
      or v_feed_ics#>>'{tareas,0,enlace_reunion}' <> 'https://meet.google.com/abc-defg-hij',
    'El feed ICS perdió la clasificación de la reunión'
  );
end;
$$;

select 'OK: inteligencia comercial, detalle por vendedor, metas y reuniones auditables' as resultado;

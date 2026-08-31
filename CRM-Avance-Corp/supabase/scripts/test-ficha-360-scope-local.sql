-- Oráculo local autocontenido de 20260829183627_crm_ficha_360_scope_historial.
-- Se ejecuta sobre una base PostgreSQL desechable y termina con
-- FICHA_360_SCOPE_LOCAL_OK. Nunca debe apuntarse a producción.

\set ON_ERROR_STOP on

create schema auth;
create schema crm;
create schema private;

grant usage on schema crm, private to authenticated;

create function auth.uid()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $function$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$function$;

grant execute on function auth.uid() to public, anon, authenticated, service_role;

create table public.perfiles (
  id uuid primary key,
  nombres text,
  apellidos text,
  nombre_completo text not null,
  tipo_documento text,
  dni text,
  correo text,
  telefono text,
  domicilio text,
  banco text,
  asesor_perfil_id uuid,
  creado_por uuid,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  rol text not null
);

create table crm.equipo (
  perfil_id uuid primary key references public.perfiles(id),
  rol_crm text not null,
  supervisor_id uuid,
  activo boolean not null default true
);

create table crm.actividades_cliente (
  id bigint generated always as identity primary key,
  cliente_id uuid not null references public.perfiles(id),
  vendedor_id uuid not null references crm.equipo(perfil_id),
  tarea_id uuid,
  tipo text not null constraint actividades_cliente_tipo_check check (tipo in (
    'llamada_realizada', 'llamada_no_contestada', 'whatsapp_enviado',
    'whatsapp_recibido', 'reunion_realizada', 'nota'
  )),
  detalle text,
  creado_por uuid,
  creado_en timestamptz not null default now()
);

create table crm.operaciones_cartera (
  id bigint generated always as identity primary key,
  cliente_id uuid not null references public.perfiles(id),
  vendedor_id uuid not null references crm.equipo(perfil_id),
  detalle text,
  creado_en timestamptz not null default now()
);

alter table crm.actividades_cliente enable row level security;
alter table crm.operaciones_cartera enable row level security;
grant select on crm.actividades_cliente, crm.operaciones_cartera to authenticated;

-- Estado anterior: la lectura seguía al responsable histórico y no a la
-- asignación viva del cliente.
create policy actividades_cliente_select on crm.actividades_cliente
  for select to authenticated
  using (vendedor_id = (select auth.uid()));
create policy operaciones_cartera_select on crm.operaciones_cartera
  for select to authenticated
  using (vendedor_id = (select auth.uid()));

create function private.cliente_ids_visibles_crm()
returns table(cliente_id uuid)
language sql
stable
security definer
set search_path = ''
as $function$
  with actor as (
    select e.rol_crm, e.activo
    from crm.equipo e
    where e.perfil_id = (select auth.uid())
  ), visibles as (
    select (select auth.uid()) as perfil_id
    union all
    select e.perfil_id
    from crm.equipo e
    where e.supervisor_id = (select auth.uid())
      and e.activo
  )
  select p.id
  from public.perfiles p
  cross join actor a
  where a.activo
    and p.rol = 'cliente'
    and (
      a.rol_crm in ('gerencia', 'directorio')
      or p.asesor_perfil_id in (select v.perfil_id from visibles v)
      or (
        p.asesor_perfil_id is null
        and p.creado_por in (select v.perfil_id from visibles v)
      )
    );
$function$;

revoke all on function private.cliente_ids_visibles_crm()
  from public, anon, authenticated, service_role;

\ir ../migrations/20260829183627_crm_ficha_360_scope_historial.sql

begin;

insert into public.perfiles (
  id, nombres, apellidos, nombre_completo, tipo_documento, dni, correo,
  telefono, domicilio, banco, asesor_perfil_id, creado_por, activo, rol
)
values
  ('36000000-0000-4000-8000-000000000001', 'ANA', 'UNO', 'ANA UNO', 'DNI', '70000001', 'ana@test.invalid', '900000001', null, null, null, null, true, 'comercial'),
  ('36000000-0000-4000-8000-000000000002', 'BETO', 'DOS', 'BETO DOS', 'DNI', '70000002', 'beto@test.invalid', '900000002', null, null, null, null, true, 'comercial'),
  ('36000000-0000-4000-8000-000000000003', 'CARLA', 'TRES', 'CARLA TRES', 'DNI', '70000003', 'carla@test.invalid', '900000003', null, null, null, null, true, 'comercial'),
  ('36000000-0000-4000-8000-000000000004', 'SOFIA', 'SUPERVISORA', 'SOFIA SUPERVISORA', 'DNI', '70000004', 'supervision@test.invalid', '900000004', null, null, null, null, true, 'comercial'),
  ('36000000-0000-4000-8000-000000000005', 'DINA', 'DIRECTORIO', 'DINA DIRECTORIO', 'DNI', '70000005', 'directorio@test.invalid', '900000005', null, null, null, null, true, 'directorio'),
  ('36000000-0000-4000-8000-000000000101', 'CLIENTE', 'A', 'CLIENTE A', 'DNI', '71000101', 'cliente-a@test.invalid', '910000101', 'DATO PRIVADO A', 'BANCO PRIVADO A', '36000000-0000-4000-8000-000000000001', '36000000-0000-4000-8000-000000000001', true, 'cliente'),
  ('36000000-0000-4000-8000-000000000102', 'CLIENTE', 'B', 'CLIENTE B', 'DNI', '71000102', 'cliente-b@test.invalid', '910000102', 'DATO PRIVADO B', 'BANCO PRIVADO B', '36000000-0000-4000-8000-000000000003', '36000000-0000-4000-8000-000000000003', true, 'cliente'),
  ('36000000-0000-4000-8000-000000000103', 'CLIENTE', 'SIN ASIGNACION', 'CLIENTE SIN ASIGNACION', 'DNI', '71000103', 'cliente-sin-asignacion@test.invalid', '910000103', 'DATO PRIVADO C', 'BANCO PRIVADO C', null, '36000000-0000-4000-8000-000000000001', true, 'cliente');

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  ('36000000-0000-4000-8000-000000000001', 'vendedor', '36000000-0000-4000-8000-000000000004', true),
  ('36000000-0000-4000-8000-000000000002', 'vendedor', '36000000-0000-4000-8000-000000000004', true),
  ('36000000-0000-4000-8000-000000000003', 'vendedor', null, true),
  ('36000000-0000-4000-8000-000000000004', 'supervisor', null, true),
  ('36000000-0000-4000-8000-000000000005', 'directorio', null, true);

-- Ambos hechos fueron registrados por otra persona a propósito. La policy
-- nueva debe entregarlos a quien tenga el cliente hoy.
insert into crm.actividades_cliente (
  cliente_id, vendedor_id, tipo, detalle, creado_por
)
values (
  '36000000-0000-4000-8000-000000000101',
  '36000000-0000-4000-8000-000000000002',
  'nota',
  'Hecho histórico',
  '36000000-0000-4000-8000-000000000002'
);

insert into crm.operaciones_cartera (cliente_id, vendedor_id, detalle)
values (
  '36000000-0000-4000-8000-000000000101',
  '36000000-0000-4000-8000-000000000002',
  'Movimiento histórico'
);

do $estructura$
declare
  v_rpc pg_catalog.pg_proc%rowtype;
begin
  select p.* into v_rpc
  from pg_catalog.pg_proc p
  where p.oid = 'crm.cliente_ficha_fn(uuid)'::regprocedure;

  if v_rpc.prosecdef
     or v_rpc.provolatile <> 's'
     or not (v_rpc.proconfig @> array['search_path=""']) then
    raise exception 'F360-01: la RPC expuesta no quedó invoker/stable/search_path vacío';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated', 'crm.cliente_ficha_fn(uuid)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon', 'crm.cliente_ficha_fn(uuid)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role', 'crm.cliente_ficha_fn(uuid)', 'EXECUTE'
     ) then
    raise exception 'F360-02: ACL inesperada en la RPC';
  end if;

  if exists (
    select 1
    from unnest(coalesce(v_rpc.proargnames, '{}'::text[])) salida(nombre)
    where salida.nombre like any (array[
      'domicilio', 'banco%', 'tipo_cuenta%', 'numero_cuenta%', 'cci%',
      'titular_distinto%', 'beneficiario_%', 'creado_por'
    ])
  ) then
    raise exception 'F360-03: la RPC expone datos fuera de la frontera mínima';
  end if;
end;
$estructura$;

select set_config('request.jwt.claim.sub', '36000000-0000-4000-8000-000000000001', true);
set local role authenticated;

do $analista_a$
begin
  if (select count(*) from crm.cliente_ficha_fn('36000000-0000-4000-8000-000000000101')) <> 1
     or (select count(*) from crm.cliente_ficha_fn('36000000-0000-4000-8000-000000000103')) <> 1
     or exists (
       select 1 from crm.cliente_ficha_fn('36000000-0000-4000-8000-000000000102')
     ) then
    raise exception 'F360-04: el ámbito del Analista A no coincide con la cartera canónica';
  end if;

  if (select count(*) from crm.actividades_cliente where cliente_id = '36000000-0000-4000-8000-000000000101') <> 1
     or (select count(*) from crm.operaciones_cartera where cliente_id = '36000000-0000-4000-8000-000000000101') <> 1 then
    raise exception 'F360-05: historial o movimientos no siguieron al cliente actual';
  end if;
end;
$analista_a$;

reset role;

select set_config('request.jwt.claim.sub', '36000000-0000-4000-8000-000000000003', true);
set local role authenticated;

do $analista_ajena$
begin
  if exists (
       select 1 from crm.cliente_ficha_fn('36000000-0000-4000-8000-000000000101')
     )
     or exists (
       select 1 from crm.actividades_cliente where cliente_id = '36000000-0000-4000-8000-000000000101'
     )
     or exists (
       select 1 from crm.operaciones_cartera where cliente_id = '36000000-0000-4000-8000-000000000101'
     ) then
    raise exception 'F360-06: una Analista ajena descubrió la ficha o su historial';
  end if;
end;
$analista_ajena$;

reset role;

-- Reasignar mueve ficha, historial y movimientos como una sola unidad y deja
-- un evento con terminología de Analista.
select set_config('request.jwt.claim.sub', '36000000-0000-4000-8000-000000000004', true);
update public.perfiles
set asesor_perfil_id = '36000000-0000-4000-8000-000000000002'
where id = '36000000-0000-4000-8000-000000000101';

select set_config('request.jwt.claim.sub', '36000000-0000-4000-8000-000000000001', true);
set local role authenticated;

do $revocada$
begin
  if exists (
       select 1 from crm.cliente_ficha_fn('36000000-0000-4000-8000-000000000101')
     )
     or exists (
       select 1 from crm.actividades_cliente where cliente_id = '36000000-0000-4000-8000-000000000101'
     )
     or exists (
       select 1 from crm.operaciones_cartera where cliente_id = '36000000-0000-4000-8000-000000000101'
     ) then
    raise exception 'F360-07: la asignación anterior conservó acceso';
  end if;
end;
$revocada$;

reset role;

select set_config('request.jwt.claim.sub', '36000000-0000-4000-8000-000000000002', true);
set local role authenticated;

do $analista_b$
declare
  v_evento text;
begin
  if (select count(*) from crm.cliente_ficha_fn('36000000-0000-4000-8000-000000000101')) <> 1
     or (select count(*) from crm.actividades_cliente where cliente_id = '36000000-0000-4000-8000-000000000101') <> 2
     or (select count(*) from crm.operaciones_cartera where cliente_id = '36000000-0000-4000-8000-000000000101') <> 1 then
    raise exception 'F360-08: la nueva asignación no recibió la ficha completa';
  end if;

  select a.detalle into v_evento
  from crm.actividades_cliente a
  where a.cliente_id = '36000000-0000-4000-8000-000000000101'
    and a.tipo = 'reasignacion';

  if v_evento not ilike '%Analista%'
     or lower(v_evento) like '%asesor%'
     or lower(v_evento) like '%vendedor%' then
    raise exception 'F360-09: el evento de reasignación no usa la terminología Analista';
  end if;
end;
$analista_b$;

reset role;

select set_config('request.jwt.claim.sub', '36000000-0000-4000-8000-000000000005', true);
set local role authenticated;

do $directorio$
begin
  if (select count(*) from crm.cliente_ficha_fn('36000000-0000-4000-8000-000000000101')) <> 1 then
    raise exception 'F360-10: Directorio no recibió su lectura global mínima';
  end if;
end;
$directorio$;

reset role;

do $anonimo$
declare
  v_aceptado boolean := false;
begin
  begin
    set local role anon;
    perform * from crm.cliente_ficha_fn('36000000-0000-4000-8000-000000000101');
    v_aceptado := true;
  exception when insufficient_privilege then
    null;
  end;
  reset role;
  if v_aceptado then
    raise exception 'F360-11: anon pudo ejecutar la RPC';
  end if;
end;
$anonimo$;

rollback;

select 'FICHA_360_SCOPE_LOCAL_OK';

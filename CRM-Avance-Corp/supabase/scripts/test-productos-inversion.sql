\set ON_ERROR_STOP on

-- Oráculo autocontenido del catálogo versionado. Ejecutar en PostgreSQL
-- desechable: psql "$DATABASE_URL" -f supabase/scripts/test-productos-inversion.sql
-- El setup se confirma antes de incluir la migración para probar que el archivo
-- abre/cierra su propia transacción. Los casos de negocio posteriores hacen
-- ROLLBACK; usar siempre una base desechable.

begin;

do $roles$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end;
$roles$;

create schema auth;
create schema crm;
create schema private;
grant usage on schema crm, private to authenticated, service_role;

create function auth.uid()
returns uuid
language sql
stable
set search_path = ''
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create table public.perfiles (
  id uuid primary key,
  nombre_completo text not null,
  correo text,
  rol text not null,
  activo boolean not null default true,
  asesor_perfil_id uuid,
  creado_por uuid
);

create function public.es_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.perfiles p
    where p.id = (select auth.uid())
      and p.activo is true
      and p.rol in ('admin', 'superadmin')
  );
$$;

create function public.es_analista()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.perfiles p
    where p.id = (select auth.uid())
      and p.activo is true
      and p.rol = 'analista'
  );
$$;

create function public.es_superadmin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.perfiles p
    where p.id = (select auth.uid())
      and p.activo is true
      and p.rol = 'superadmin'
  );
$$;

create table crm.equipo (
  perfil_id uuid primary key references public.perfiles(id),
  rol_crm text not null,
  activo boolean not null default true,
  supervisor_id uuid references crm.equipo(perfil_id)
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  tabla text not null,
  operacion text not null,
  fila_id uuid,
  usuario_id uuid,
  data_antes jsonb,
  data_despues jsonb,
  creado_en timestamptz not null default now()
);

create function private.rol_crm(p_perfil_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select e.rol_crm
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_perfil_id
    and e.activo is true and p.activo is true
    and e.rol_crm in (
      'vendedor', 'supervisor', 'gerencia', 'coordinador', 'directorio'
    )
    and (p.rol is distinct from 'superadmin' or e.rol_crm = 'gerencia');
$$;

create function private.es_lector_global()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.perfiles p
    left join crm.equipo e on e.perfil_id = p.id
    where p.id = (select auth.uid())
      and p.activo is true
      and (
        (e.perfil_id is not null
          and e.activo is true
          and e.rol_crm = 'directorio'
          and p.rol is distinct from 'superadmin')
        or (e.perfil_id is null and p.rol = 'directorio')
      )
  );
$$;

create function private.vendedor_ids_visibles(p_perfil_id uuid)
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rol text := private.rol_crm(p_perfil_id);
begin
  if p_perfil_id is distinct from (select auth.uid())
     and not private.es_lector_global() then
    return;
  elsif v_rol = 'gerencia' then
    return query select e.perfil_id from crm.equipo e;
  elsif v_rol = 'supervisor' then
    return query
    with recursive subarbol as (
      select e.perfil_id
      from crm.equipo e
      where e.perfil_id = p_perfil_id
      union
      select e.perfil_id
      from crm.equipo e
      join subarbol s on e.supervisor_id = s.perfil_id
    )
    select s.perfil_id from subarbol s;
  elsif v_rol = 'vendedor' then
    return next p_perfil_id;
  else
    return;
  end if;
end;
$$;

create function private.puede_gestionar_cuentas_cliente(p_cliente_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select false;
$$;

create function private.log_audit_crm()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fila jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
begin
  insert into public.audit_log (
    tabla, operacion, fila_id, usuario_id, data_antes, data_despues
  ) values (
    tg_table_schema || '.' || tg_table_name,
    tg_op,
    (v_fila->>'id')::uuid,
    (select auth.uid()),
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end
  );
  return coalesce(new, old);
end;
$$;

create table public.contratos (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references public.perfiles(id),
  numero_contrato text not null unique,
  capital numeric(12,2) not null check (capital between 100 and 100000000),
  moneda text not null check (moneda in ('PEN', 'USD')),
  tasa_anual numeric(5,2) not null check (tasa_anual > 0 and tasa_anual <= 50),
  modalidad text not null check (modalidad in ('mensual', 'trimestral', 'semestral', 'anual')),
  tipo_interes text not null check (tipo_interes in ('simple', 'compuesto')),
  fecha_inicio date not null,
  fecha_vencimiento date not null,
  categoria text check (categoria in ('nuevo', 'renovacion', 'upgrade')),
  estado text not null default 'activo',
  notas_internas text,
  creado_por uuid,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
grant select on public.contratos to authenticated;

create table public.cronograma_pagos (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos(id) on delete cascade,
  numero_cuota integer not null,
  fecha_programada date not null,
  monto_programado numeric(12,2) not null,
  estado text not null default 'pendiente',
  tipo text not null default 'cuota',
  monto_pagado numeric(12,2)
);

create function public._sync_contrato_titulares(
  p_contrato_id uuid,
  p_titulares jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_contrato_id is null or p_titulares is null then
    raise exception 'Titulares inválidos' using errcode = '22023';
  end if;
end;
$$;

create function public.set_actualizado_en()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.actualizado_en := now();
  return new;
end;
$$;
create trigger trg_contratos_actualizado_en
before update on public.contratos
for each row execute function public.set_actualizado_en();

create function crm.contratos_cartera_fn()
returns table (
  id uuid, numero_contrato text, cliente_id uuid, cliente_nombre text,
  asesor_perfil_id uuid, capital numeric, moneda text, tasa_anual numeric,
  modalidad text, tipo_interes text, categoria text, estado text,
  fecha_inicio date, fecha_vencimiento date, notas_internas text,
  creado_por uuid, creado_en timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.numero_contrato, c.cliente_id, p.nombre_completo,
         p.asesor_perfil_id, c.capital, c.moneda, c.tasa_anual,
         c.modalidad, c.tipo_interes, c.categoria, c.estado,
         c.fecha_inicio, c.fecha_vencimiento, c.notas_internas,
         c.creado_por, c.creado_en
  from public.contratos c
  join public.perfiles p on p.id = c.cliente_id;
$$;

create view crm.contratos_cartera
with (security_invoker = true)
as select * from crm.contratos_cartera_fn();

-- Stubs de los escritores vigentes que las RPC aditivas deben envolver.
create function public.crear_contrato(p_contrato jsonb, p_cronograma jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_uid uuid := (select auth.uid());
  v_cliente_id uuid := (p_contrato->>'cliente_id')::uuid;
begin
  if not ((select public.es_admin()) or (select public.es_analista()))
     and private.rol_crm(v_uid) <> 'gerencia' then
    raise insufficient_privilege using message = 'No autorizado para crear contratos';
  end if;
  if (select public.es_analista()) and not (select public.es_admin())
     and not exists (
       select 1 from public.perfiles cli
       where cli.id = v_cliente_id and cli.rol = 'cliente' and cli.activo
         and (
           cli.asesor_perfil_id = v_uid
           or (cli.asesor_perfil_id is null and cli.creado_por = v_uid)
         )
     ) then
    raise insufficient_privilege using message = 'Cliente fuera de cartera Portal';
  end if;
  insert into public.contratos (
    cliente_id, numero_contrato, capital, moneda, tasa_anual, modalidad,
    tipo_interes, fecha_inicio, fecha_vencimiento, categoria, creado_por
  ) values (
    (p_contrato->>'cliente_id')::uuid,
    p_contrato->>'numero_contrato',
    (p_contrato->>'capital')::numeric,
    p_contrato->>'moneda',
    (p_contrato->>'tasa_anual')::numeric,
    p_contrato->>'modalidad',
    p_contrato->>'tipo_interes',
    (p_contrato->>'fecha_inicio')::date,
    (p_contrato->>'fecha_vencimiento')::date,
    p_contrato->>'categoria',
    (select auth.uid())
  ) returning id into v_id;
  return jsonb_build_object('id', v_id, 'ok', true);
end;
$$;

create function public.actualizar_contrato(
  p_id uuid, p_contrato jsonb, p_cronograma jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_row public.contratos%rowtype;
begin
  select * into v_row from public.contratos where id = p_id;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
  if (select public.es_admin()) or private.rol_crm(v_uid) = 'gerencia' then
    null;
  elsif (select public.es_analista()) then
    if v_row.creado_por is distinct from v_uid
       or v_row.creado_en <= now() - interval '5 hours'
       or not exists (
         select 1 from public.perfiles cli
         where cli.id = v_row.cliente_id and cli.rol = 'cliente' and cli.activo
           and (
             cli.asesor_perfil_id = v_uid
             or (cli.asesor_perfil_id is null and cli.creado_por = v_uid)
           )
       ) then
      raise insufficient_privilege using message = 'Contrato fuera de alcance Portal';
    end if;
  else
    raise insufficient_privilege using message = 'No autorizado para actualizar contratos';
  end if;
  update public.contratos
     set capital = (p_contrato->>'capital')::numeric,
         moneda = p_contrato->>'moneda',
         tasa_anual = (p_contrato->>'tasa_anual')::numeric,
         modalidad = p_contrato->>'modalidad',
         tipo_interes = p_contrato->>'tipo_interes',
         fecha_inicio = (p_contrato->>'fecha_inicio')::date,
         fecha_vencimiento = (p_contrato->>'fecha_vencimiento')::date,
         categoria = p_contrato->>'categoria',
         actualizado_en = now()
   where id = p_id;
  return jsonb_build_object('id', p_id, 'ok', true);
end;
$$;

create function crm.crear_contrato_con_cuenta(
  p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select public.crear_contrato(p_contrato, p_cronograma);
$$;

create function crm.actualizar_contrato_con_cuenta(
  p_id uuid, p_contrato jsonb, p_cronograma jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cliente_id uuid;
begin
  select ct.cliente_id into v_cliente_id
  from public.contratos ct where ct.id = p_id;
  if not found or not private.puede_gestionar_cuentas_cliente(v_cliente_id) then
    raise insufficient_privilege using message = 'Contrato fuera de alcance de cuentas';
  end if;
  perform public.actualizar_contrato(p_id, p_contrato, p_cronograma);
end;
$$;

insert into public.perfiles (id, nombre_completo, correo, rol, activo)
values
  ('51000000-0000-4000-8000-000000000001', 'Productos Gerencia', 'prod-g@test.invalid', 'superadmin', true),
  ('51000000-0000-4000-8000-000000000002', 'Productos Vendedor', 'prod-v@test.invalid', 'comercial', true),
  ('51000000-0000-4000-8000-000000000003', 'Productos Directorio', 'prod-d@test.invalid', 'directorio', true),
  ('51000000-0000-4000-8000-000000000004', 'Gerencia Inactiva', 'prod-gi@test.invalid', 'comercial', false),
  ('51000000-0000-4000-8000-000000000005', 'Cliente Portal', 'prod-c@test.invalid', 'cliente', true),
  ('51000000-0000-4000-8000-000000000006', 'Productos Supervisor', 'prod-s@test.invalid', 'comercial', true),
  ('51000000-0000-4000-8000-000000000007', 'Superadmin Portal', 'prod-sa@test.invalid', 'superadmin', true),
  ('51000000-0000-4000-8000-000000000008', 'Admin Portal', 'prod-a@test.invalid', 'admin', true),
  ('51000000-0000-4000-8000-000000000009', 'Analista Portal', 'prod-ap@test.invalid', 'analista', true),
  ('51000000-0000-4000-8000-000000000010', 'Cliente Analista', 'prod-ca@test.invalid', 'cliente', true),
  ('51000000-0000-4000-8000-000000000011', 'Productos Coordinador', 'prod-co@test.invalid', 'comercial', true),
  ('51000000-0000-4000-8000-000000000012', 'Productos Gerencia CRM', 'prod-gc@test.invalid', 'comercial', true),
  ('51000000-0000-4000-8000-000000000013', 'Productos Directorio CRM', 'prod-dc@test.invalid', 'comercial', true);

insert into crm.equipo (perfil_id, rol_crm, activo, supervisor_id)
values
  ('51000000-0000-4000-8000-000000000001', 'gerencia', true, null),
  ('51000000-0000-4000-8000-000000000006', 'supervisor', true, null),
  ('51000000-0000-4000-8000-000000000002', 'vendedor', true, '51000000-0000-4000-8000-000000000006'),
  ('51000000-0000-4000-8000-000000000004', 'gerencia', true, null),
  ('51000000-0000-4000-8000-000000000007', 'vendedor', true, '51000000-0000-4000-8000-000000000006'),
  ('51000000-0000-4000-8000-000000000011', 'coordinador', true, null),
  ('51000000-0000-4000-8000-000000000012', 'gerencia', true, null),
  ('51000000-0000-4000-8000-000000000013', 'directorio', true, null);

update public.perfiles
set asesor_perfil_id = '51000000-0000-4000-8000-000000000002'
where id = '51000000-0000-4000-8000-000000000005';

update public.perfiles
set asesor_perfil_id = '51000000-0000-4000-8000-000000000009',
    creado_por = '51000000-0000-4000-8000-000000000009'
where id = '51000000-0000-4000-8000-000000000010';

-- Dos historias contradictorias a propósito: categoría NULL y renovación sin
-- predecesor. El backfill debe fotografiarlas, no reinterpretarlas.
insert into public.contratos (
  id, cliente_id, numero_contrato, capital, moneda, tasa_anual, modalidad,
  tipo_interes, fecha_inicio, fecha_vencimiento, categoria, notas_internas
) values
  ('52000000-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000005',
   'LEGACY-001', 25000, 'PEN', 15, 'mensual', 'simple',
   date '2025-01-15', date '2026-01-15', null, 'No reclasificar'),
  ('52000000-0000-4000-8000-000000000002', '51000000-0000-4000-8000-000000000005',
   'LEGACY-002', 12000, 'USD', 18, 'trimestral', 'compuesto',
   date '2025-03-01', date '2027-03-01', 'renovacion', 'Excepción real');

commit;

-- Se incluye sin una transacción exterior: esto detecta migraciones que solo
-- funcionan por accidente bajo el BEGIN del oráculo.
\ir ../migrations/20260807203751_crm_catalogo_productos_versionado.sql
\ir ../migrations/20260807235933_crm_portal_catalogo_productos.sql

begin;

-- DDL, backfill exacto y ACL base.
do $test$
declare
  v_n integer;
begin
  if exists (select 1 from public.contratos where producto_condicion_id is null) then
    raise exception 'P01 quedó un contrato histórico sin snapshot';
  end if;

  select count(*) into v_n
  from public.contratos ct
  join crm.producto_condiciones c on c.id = ct.producto_condicion_id
  join crm.producto_versiones v on v.id = c.version_id
  join crm.productos_inversion p on p.id = v.producto_id
  where c.es_legacy and v.estado = 'retirada'
    and p.codigo = 'HISTORICO-SIN-CATALOGO' and p.estado = 'archivado';
  if v_n <> 2 then
    raise exception 'P02 esperaba dos snapshots legacy retirados, obtuvo %', v_n;
  end if;

  if (select categoria from public.contratos where numero_contrato = 'LEGACY-001') is not null
     or (select notas_internas from public.contratos where numero_contrato = 'LEGACY-001') <> 'No reclasificar'
     or (select categoria from public.contratos where numero_contrato = 'LEGACY-002') <> 'renovacion' then
    raise exception 'P03 el backfill reinterpretó o alteró términos históricos';
  end if;

  if not exists (
    select 1 from pg_attribute a
    where a.attrelid = 'public.contratos'::regclass
      and a.attname = 'producto_condicion_id' and a.attnotnull
  ) then
    raise exception 'P04 producto_condicion_id no quedó NOT NULL';
  end if;

  if has_table_privilege('authenticated', 'crm.productos_inversion', 'INSERT')
     or has_table_privilege('authenticated', 'crm.producto_versiones', 'UPDATE')
     or has_table_privilege('authenticated', 'crm.producto_condiciones', 'DELETE') then
    raise exception 'P05 authenticated conserva escritura directa de catálogo';
  end if;
  if has_table_privilege('anon', 'crm.productos_inversion', 'SELECT')
     or has_function_privilege('anon', 'crm.crear_producto_inversion(text,text,text,date,date,jsonb)', 'EXECUTE')
     or has_function_privilege('anon', 'public.productos_inversion_seleccion_fn(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.crear_contrato_producto(uuid,jsonb,jsonb)', 'EXECUTE')
     or has_function_privilege('anon', 'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)', 'EXECUTE')
     or has_function_privilege('anon', 'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)', 'EXECUTE') then
    raise exception 'P06 anon puede leer o mutar el catálogo';
  end if;

  if has_function_privilege(
       'authenticated', 'private.puede_gestionar_cuentas_cliente(uuid)', 'EXECUTE'
     ) then
    raise exception 'P06a authenticated ejecuta el helper privado de alcance';
  end if;
end;
$test$;

-- Gerencia crea y edita un borrador; stale expected_revision falla cerrado.
select set_config(
  'request.jwt.claim.sub', '51000000-0000-4000-8000-000000000001', true
);
set local role authenticated;

do $test$
declare
  v_resultado jsonb;
  v_version_id uuid;
  v_revision bigint;
begin
  v_resultado := crm.crear_producto_inversion(
    ' RENTA-12 ',
    'Renta 12 meses',
    'Producto del oráculo',
    current_date - 1,
    current_date + 365,
    jsonb_build_array(jsonb_build_object(
      'categoria', 'nuevo',
      'moneda', 'PEN',
      'plazo_meses', 12,
      'modalidad', 'mensual',
      'tipo_interes', 'simple',
      'capital_minimo', 1000,
      'capital_maximo', 100000,
      'tasa_referencia', 15,
      'tasa_minima', 14,
      'tasa_maxima', 16
    ))
  );
  if v_resultado->>'estado' <> 'borrador'
     or (v_resultado->>'producto_revision')::int <> 1
     or (v_resultado->>'version_revision')::int <> 1 then
    raise exception 'P07 respuesta de alta de producto inesperada: %', v_resultado;
  end if;

  select v.id, v.revision into v_version_id, v_revision
  from crm.producto_versiones v
  join crm.productos_inversion p on p.id = v.producto_id
  where p.codigo = 'RENTA-12' and v.estado = 'borrador';

  begin
    perform crm.actualizar_borrador_producto_inversion(
      v_version_id, 99, 'Renta 12 meses', 'stale',
      current_date - 1, current_date + 365,
      jsonb_build_array(jsonb_build_object(
        'categoria', 'nuevo', 'moneda', 'PEN', 'plazo_meses', 12,
        'modalidad', 'mensual', 'tipo_interes', 'simple',
        'capital_minimo', 1000, 'capital_maximo', 100000,
        'tasa_referencia', 15
      ))
    );
    raise exception 'P08 aceptó expected_revision obsoleto';
  exception when serialization_failure then null;
  end;

  v_resultado := crm.actualizar_borrador_producto_inversion(
    v_version_id, v_revision, 'Renta 12 meses', 'Borrador corregido',
    current_date - 1, current_date + 365,
    jsonb_build_array(jsonb_build_object(
      'categoria', 'nuevo', 'moneda', 'PEN', 'plazo_meses', 12,
      'modalidad', 'mensual', 'tipo_interes', 'simple',
      'capital_minimo', 500, 'capital_maximo', 150000,
      'tasa_referencia', 15, 'tasa_minima', 14, 'tasa_maxima', 16
    ))
  );
  if (v_resultado->>'version_revision')::int <> 2
     or (v_resultado->>'producto_revision')::int <> 2 then
    raise exception 'P09 las revisiones del borrador no avanzaron: %', v_resultado;
  end if;
  if (select count(*) from crm.producto_condiciones c
      where c.version_id = v_version_id) <> 2
     or (select count(*) from crm.producto_condiciones c
         where c.version_id = v_version_id and c.activa) <> 1 then
    raise exception 'P10 reemplazar condiciones borró historia o dejó dos activas';
  end if;

  v_resultado := crm.publicar_version_producto_inversion(v_version_id, 2);
  if v_resultado->>'estado' <> 'publicada'
     or (v_resultado->>'producto_revision')::int <> 3
     or (v_resultado->>'version_revision')::int <> 3 then
    raise exception 'P11 publicación/revisiones inesperadas: %', v_resultado;
  end if;
end;
$test$;
reset role;


-- Analista Portal: selector público, alta y corrección dentro de su cartera y
-- ventana. Ni el selector por contrato ni el writer cruzan a clientes ajenos.
select set_config(
  'request.jwt.claim.sub', '51000000-0000-4000-8000-000000000009', true
);
set local role authenticated;
do $test$
declare
  v_condicion_id uuid;
  v_contrato_id uuid;
  v_resultado jsonb;
begin
  select condicion_id into v_condicion_id
  from public.productos_inversion_seleccion_fn(null)
  where producto_codigo = 'RENTA-12' and seleccionable_nuevo;
  if v_condicion_id is null then
    raise exception 'P11a Analista Portal no recibió el catálogo vigente';
  end if;

  v_resultado := public.crear_contrato_producto(
    v_condicion_id,
    jsonb_build_object(
      'cliente_id', '51000000-0000-4000-8000-000000000010',
      'numero_contrato', 'PORTAL-ANALISTA-001',
      'capital', 20000, 'moneda', 'PEN', 'tasa_anual', 15,
      'modalidad', 'mensual', 'tipo_interes', 'simple',
      'fecha_inicio', current_date,
      'fecha_vencimiento', (current_date + interval '12 months')::date,
      'categoria', 'nuevo'
    ),
    jsonb_build_array(jsonb_build_object(
      'numero_cuota', 1, 'fecha_programada', current_date + 30,
      'monto_programado', 250, 'tipo', 'cuota'
    ))
  );
  v_contrato_id := (v_resultado->>'id')::uuid;

  if (select count(*) from public.productos_inversion_seleccion_fn(v_contrato_id)
      where es_actual and condicion_id = v_condicion_id) <> 1 then
    raise exception 'P11b selector Portal no devolvió el producto actual propio';
  end if;

  v_resultado := public.actualizar_contrato_producto(
    v_contrato_id,
    v_condicion_id,
    jsonb_build_object(
      'capital', 21000, 'moneda', 'PEN', 'tasa_anual', 15,
      'modalidad', 'mensual', 'tipo_interes', 'simple',
      'fecha_inicio', current_date,
      'fecha_vencimiento', (current_date + interval '12 months')::date,
      'categoria', 'nuevo', 'notas_internas', 'Corrección Portal'
    ),
    '[]'::jsonb
  );
  if (v_resultado->>'producto_condicion_id')::uuid is distinct from v_condicion_id
     or (select capital from public.contratos where id = v_contrato_id) <> 21000 then
    raise exception 'P11c corrección Portal perdió condición o términos';
  end if;

  begin
    perform public.productos_inversion_seleccion_fn(
      '52000000-0000-4000-8000-000000000001'
    );
    raise exception 'P11d Analista consultó producto de contrato ajeno';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.crear_contrato_producto(
      v_condicion_id,
      jsonb_build_object(
        'cliente_id', '51000000-0000-4000-8000-000000000005',
        'numero_contrato', 'PORTAL-AJENO-BLOQUEADO',
        'capital', 20000, 'moneda', 'PEN', 'tasa_anual', 15,
        'modalidad', 'mensual', 'tipo_interes', 'simple',
        'fecha_inicio', current_date,
        'fecha_vencimiento', (current_date + interval '12 months')::date,
        'categoria', 'nuevo'
      ),
      jsonb_build_array(jsonb_build_object(
        'numero_cuota', 1, 'fecha_programada', current_date + 30,
        'monto_programado', 250, 'tipo', 'cuota'
      ))
    );
    raise exception 'P11e Analista creó contrato fuera de cartera';
  exception when insufficient_privilege then null;
  end;
end;
$test$;
reset role;


-- Alta catalogada: el wrapper conserva la FK y devuelve metadatos de revisión.
select set_config(
  'request.jwt.claim.sub', '51000000-0000-4000-8000-000000000002', true
);
set local role authenticated;
do $test$
declare
  v_condicion_id uuid;
  v_resultado jsonb;
begin
  select condicion_id into v_condicion_id
  from crm.productos_inversion_seleccion_fn();

  begin
    perform public.crear_contrato(
      jsonb_build_object(
        'cliente_id', '51000000-0000-4000-8000-000000000005',
        'numero_contrato', 'CRM-DIRECTO-BLOQUEADO',
        'capital', 20000, 'moneda', 'PEN', 'tasa_anual', 15,
        'modalidad', 'mensual', 'tipo_interes', 'simple',
        'fecha_inicio', current_date,
        'fecha_vencimiento', (current_date + interval '12 months')::date,
        'categoria', 'nuevo'
      ),
      jsonb_build_array(jsonb_build_object(
        'numero_cuota', 1, 'fecha_programada', current_date + 30,
        'monto_programado', 250, 'tipo', 'cuota'
      ))
    );
    raise exception 'P17a Vendedor saltó el wrapper catalogado';
  exception when insufficient_privilege then null;
  end;

  v_resultado := crm.crear_contrato_producto(
    v_condicion_id,
    jsonb_build_object(
      'cliente_id', '51000000-0000-4000-8000-000000000005',
      'numero_contrato', 'CAT-001',
      'capital', 20000,
      'moneda', 'PEN',
      'tasa_anual', 15,
      'modalidad', 'mensual',
      'tipo_interes', 'simple',
      'fecha_inicio', current_date,
      'fecha_vencimiento', (current_date + interval '12 months')::date,
      'categoria', 'nuevo'
    ),
    jsonb_build_array(jsonb_build_object(
      'numero_cuota', 1,
      'fecha_programada', current_date + 30,
      'monto_programado', 250,
      'tipo', 'cuota'
    ))
  );

  if (v_resultado->>'producto_condicion_id')::uuid is distinct from v_condicion_id
     or (v_resultado->>'producto_revision')::int <> 3
     or (v_resultado->>'version_revision')::int <> 3 then
    raise exception 'P18 wrapper contractual no devolvió origen/revisiones: %', v_resultado;
  end if;
  if (select producto_condicion_id from public.contratos
      where numero_contrato = 'CAT-001') is distinct from v_condicion_id then
    raise exception 'P19 el contrato catalogado no guardó la condición elegida';
  end if;
  if (select producto_codigo from crm.contratos_cartera
      where numero_contrato = 'CAT-001') <> 'RENTA-12' then
    raise exception 'P20 la cartera canónica no expone el origen del producto';
  end if;
end;
$test$;
reset role;

-- Supervisor: puede contratar para la cartera de su subárbol solo mediante el
-- wrapper CRM; un cliente del Analista Portal queda fuera de alcance.
select set_config(
  'request.jwt.claim.sub', '51000000-0000-4000-8000-000000000006', true
);
set local role authenticated;
do $test$
declare
  v_condicion_id uuid;
  v_resultado jsonb;
begin
  select condicion_id into v_condicion_id
  from crm.productos_inversion_seleccion_fn();

  v_resultado := crm.crear_contrato_producto(
    v_condicion_id,
    jsonb_build_object(
      'cliente_id', '51000000-0000-4000-8000-000000000005',
      'numero_contrato', 'CAT-SUP-001',
      'capital', 22000, 'moneda', 'PEN', 'tasa_anual', 15,
      'modalidad', 'mensual', 'tipo_interes', 'simple',
      'fecha_inicio', current_date,
      'fecha_vencimiento', (current_date + interval '12 months')::date,
      'categoria', 'nuevo'
    ),
    jsonb_build_array(jsonb_build_object(
      'numero_cuota', 1, 'fecha_programada', current_date + 30,
      'monto_programado', 275, 'tipo', 'cuota'
    ))
  );
  if (v_resultado->>'producto_condicion_id')::uuid is distinct from v_condicion_id then
    raise exception 'P20a Supervisor no creó dentro de su subárbol';
  end if;

  begin
    perform crm.crear_contrato_producto(
      v_condicion_id,
      jsonb_build_object(
        'cliente_id', '51000000-0000-4000-8000-000000000010',
        'numero_contrato', 'CAT-SUP-AJENO',
        'capital', 22000, 'moneda', 'PEN', 'tasa_anual', 15,
        'modalidad', 'mensual', 'tipo_interes', 'simple',
        'fecha_inicio', current_date,
        'fecha_vencimiento', (current_date + interval '12 months')::date,
        'categoria', 'nuevo'
      ),
      jsonb_build_array(jsonb_build_object(
        'numero_cuota', 1, 'fecha_programada', current_date + 30,
        'monto_programado', 275, 'tipo', 'cuota'
      ))
    );
    raise exception 'P20b Supervisor creó fuera de su subárbol';
  exception when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- Caller Portal antiguo: temporalmente recibe snapshot exacto, nunca queda NULL.
select set_config(
  'request.jwt.claim.sub', '51000000-0000-4000-8000-000000000008', true
);
set local role authenticated;
do $test$
declare
  v_resultado jsonb;
  v_id uuid;
begin
  v_resultado := public.crear_contrato(
    jsonb_build_object(
      'cliente_id', '51000000-0000-4000-8000-000000000005',
      'numero_contrato', 'LEGACY-NUEVO-001',
      'capital', 7000,
      'moneda', 'USD',
      'tasa_anual', 18,
      'modalidad', 'trimestral',
      'tipo_interes', 'compuesto',
      'fecha_inicio', current_date,
      'fecha_vencimiento', (current_date + interval '24 months')::date,
      'categoria', 'upgrade'
    ),
    jsonb_build_array(jsonb_build_object(
      'numero_cuota', 1,
      'fecha_programada', current_date + 90,
      'monto_programado', 300,
      'tipo', 'cuota'
    ))
  );
  v_id := (v_resultado->>'id')::uuid;
  if (select producto_condicion_id from public.contratos where id = v_id) is null then
    raise exception 'P21 compatibilidad dejó el contrato sin snapshot';
  end if;
end;
$test$;
reset role;

do $test$
begin
  if not exists (
    select 1
    from public.contratos ct
    join crm.producto_condiciones c on c.id = ct.producto_condicion_id
    where ct.numero_contrato = 'LEGACY-NUEVO-001'
      and c.es_legacy and c.legacy_contrato_id = ct.id
      and c.categoria = 'upgrade' and c.capital_minimo = 7000
  ) then
    raise exception 'P21b el snapshot de compatibilidad no es exacto';
  end if;
end;
$test$;

-- Gerencia publica v2; v1 y el contrato que la referencia permanecen intactos.
select set_config(
  'request.jwt.claim.sub', '51000000-0000-4000-8000-000000000001', true
);
set local role authenticated;
do $test$
declare
  v_producto_id uuid;
  v_version_1 uuid;
  v_version_2 uuid;
  v_condicion_1 uuid;
  v_resultado jsonb;
begin
  select p.id into v_producto_id
  from crm.productos_inversion p where p.codigo = 'RENTA-12';
  select v.id into v_version_1
  from crm.producto_versiones v
  where v.producto_id = v_producto_id and v.estado = 'publicada';
  select c.id into v_condicion_1
  from crm.producto_condiciones c
  where c.version_id = v_version_1 and c.activa;

  begin
    perform crm.crear_version_producto_inversion(
      v_producto_id, 2, 'Renta v2 stale', null,
      current_date - 1, current_date + 365,
      jsonb_build_array(jsonb_build_object(
        'categoria', 'nuevo', 'moneda', 'PEN', 'plazo_meses', 12,
        'modalidad', 'mensual', 'tipo_interes', 'simple',
        'capital_minimo', 1000, 'capital_maximo', 100000,
        'tasa_referencia', 16
      ))
    );
    raise exception 'P22 crear versión aceptó revision de producto obsoleta';
  exception when serialization_failure then null;
  end;

  v_resultado := crm.crear_version_producto_inversion(
    v_producto_id, 3, 'Renta 12 meses v2', 'Nueva referencia',
    current_date - 1, current_date + 365,
    jsonb_build_array(jsonb_build_object(
      'categoria', 'nuevo', 'moneda', 'PEN', 'plazo_meses', 12,
      'modalidad', 'mensual', 'tipo_interes', 'simple',
      'capital_minimo', 1000, 'capital_maximo', 200000,
      'tasa_referencia', 16, 'tasa_minima', 15, 'tasa_maxima', 17
    ))
  );
  v_version_2 := (v_resultado->>'version_id')::uuid;
  if (v_resultado->>'producto_revision')::int <> 4 then
    raise exception 'P23 crear v2 no avanzó revisión de producto';
  end if;

  v_resultado := crm.publicar_version_producto_inversion(v_version_2, 1);
  if (v_resultado->>'producto_revision')::int <> 5
     or (select estado from crm.producto_versiones where id = v_version_1) <> 'retirada'
     or (select estado from crm.producto_versiones where id = v_version_2) <> 'publicada' then
    raise exception 'P24 publicar v2 no retiró v1 atómicamente: %', v_resultado;
  end if;
  if (select producto_condicion_id from public.contratos
      where numero_contrato = 'CAT-001') is distinct from v_condicion_1 then
    raise exception 'P25 v2 reescribió el snapshot contractual v1';
  end if;
end;
$test$;
reset role;

-- La condición retirada se conserva para notas/número; cambiar términos exige
-- una condición actualmente publicada/vigente.
select set_config(
  'request.jwt.claim.sub', '51000000-0000-4000-8000-000000000002', true
);
set local role authenticated;
do $test$
declare
  v_id uuid;
  v_condicion_id uuid;
  v_payload jsonb;
begin
  select id, producto_condicion_id into v_id, v_condicion_id
  from public.contratos where numero_contrato = 'CAT-001';
  v_payload := jsonb_build_object(
    'capital', 20000, 'moneda', 'PEN', 'tasa_anual', 15,
    'modalidad', 'mensual', 'tipo_interes', 'simple',
    'fecha_inicio', current_date,
    'fecha_vencimiento', (current_date + interval '12 months')::date,
    'categoria', 'nuevo'
  );
  perform crm.actualizar_contrato_producto(
    v_id, v_condicion_id, v_payload, '[]'::jsonb
  );

  begin
    perform crm.actualizar_contrato_producto(
      v_id,
      v_condicion_id,
      v_payload || jsonb_build_object('tasa_anual', 15.5),
      '[]'::jsonb
    );
    raise exception 'P26 cambió términos usando una versión retirada';
  exception when check_violation then null;
  end;
end;
$test$;
reset role;


-- Publicada = inmutable incluso para SQL privilegiado.
do $test$
declare
  v_condicion_id uuid;
begin
  select c.id into v_condicion_id
  from crm.producto_condiciones c
  join crm.producto_versiones v on v.id = c.version_id
  join crm.productos_inversion p on p.id = v.producto_id
  where p.codigo = 'RENTA-12' and v.estado = 'publicada' and c.activa;
  begin
    update crm.producto_condiciones
       set tasa_referencia = 17
     where id = v_condicion_id;
    raise exception 'P12 alteró una condición publicada';
  exception when check_violation then null;
  end;
end;
$test$;

-- Vendedor ve selector/publicada y no administra.
select set_config(
  'request.jwt.claim.sub', '51000000-0000-4000-8000-000000000002', true
);
set local role authenticated;
do $test$
declare
  v_estado jsonb;
begin
  if (select count(*) from crm.productos_inversion_seleccion_fn()) <> 1 then
    raise exception 'P13 el vendedor no ve la única condición seleccionable';
  end if;
  v_estado := crm.productos_inversion_gestion_fn();
  if jsonb_array_length(v_estado->'productos') <> 1
     or (v_estado->>'puede_administrar')::boolean then
    raise exception 'P14 contrato de gestión incorrecto para vendedor: %', v_estado;
  end if;
  begin
    perform crm.archivar_producto_inversion(
      (select id from crm.productos_inversion where codigo = 'RENTA-12'), 3
    );
    raise exception 'P15 un vendedor archivó el producto';
  exception when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- Directorio ve el estado de gestión, pero sigue siendo read-only.
select set_config(
  'request.jwt.claim.sub', '51000000-0000-4000-8000-000000000003', true
);
set local role authenticated;
do $test$
declare
  v_estado jsonb := crm.productos_inversion_gestion_fn();
begin
  if jsonb_array_length(v_estado->'productos') <> 1
     or (v_estado->>'puede_administrar')::boolean then
    raise exception 'P16 Directorio no recibió gestión read-only: %', v_estado;
  end if;
  begin
    perform crm.crear_producto_inversion(
      'NO-DEBE', 'No debe crear', null, current_date, null,
      jsonb_build_array(jsonb_build_object(
        'categoria', 'nuevo', 'moneda', 'PEN', 'plazo_meses', 12,
        'modalidad', 'mensual', 'tipo_interes', 'simple',
        'capital_minimo', 1000, 'capital_maximo', 2000,
        'tasa_referencia', 15
      ))
    );
    raise exception 'P17 Directorio creó un producto';
  exception when insufficient_privilege then null;
  end;
end;
$test$;
reset role;
-- Archivado lógico y cierre irreversible del puente legacy.
select set_config(
  'request.jwt.claim.sub', '51000000-0000-4000-8000-000000000001', true
);
set local role authenticated;
do $test$
declare
  v_producto_id uuid;
  v_version_id uuid;
  v_resultado jsonb;
begin
  select id into v_producto_id
  from crm.productos_inversion where codigo = 'RENTA-12';
  v_resultado := crm.archivar_producto_inversion(v_producto_id, 5);
  if v_resultado->>'estado' <> 'archivado'
     or (v_resultado->>'producto_revision')::int <> 6 then
    raise exception 'P27 archivado/revisión inesperados: %', v_resultado;
  end if;
  if (select count(*) from crm.productos_inversion_seleccion_fn()) <> 0 then
    raise exception 'P28 un producto archivado sigue siendo seleccionable';
  end if;

  begin
    perform crm.cerrar_altas_legacy_productos(1);
    raise exception 'P29 cerró el bridge sin una condición comercial vigente';
  exception when check_violation then null;
  end;

  begin
    perform crm.crear_producto_inversion(
      'COMPUESTO-INVALIDO', 'No publicable', null,
      current_date - 1, current_date + 365,
      jsonb_build_array(jsonb_build_object(
        'categoria', 'nuevo', 'moneda', 'PEN', 'plazo_meses', 18,
        'modalidad', 'mensual', 'tipo_interes', 'compuesto',
        'capital_minimo', 1000, 'capital_maximo', 10000,
        'tasa_referencia', 12
      ))
    );
    raise exception 'P29a aceptó compuesto sin años exactos/modalidad anual';
  exception when check_violation then null;
  end;

  v_resultado := crm.crear_producto_inversion(
    'PORTAL-24', 'Producto Portal 24 meses', 'Condición de continuidad',
    current_date - 1, current_date + 365,
    jsonb_build_array(jsonb_build_object(
      'categoria', 'upgrade', 'moneda', 'USD', 'plazo_meses', 24,
      'modalidad', 'anual', 'tipo_interes', 'compuesto',
      'capital_minimo', 5000, 'capital_maximo', 500000,
      'tasa_referencia', 12, 'tasa_minima', 11, 'tasa_maxima', 13
    ))
  );
  v_version_id := (v_resultado->>'version_id')::uuid;
  perform crm.publicar_version_producto_inversion(v_version_id, 1);
  if (select count(*) from crm.productos_inversion_seleccion_fn()) <> 1 then
    raise exception 'P29b el reemplazo vigente no quedó seleccionable';
  end if;

  v_resultado := crm.cerrar_altas_legacy_productos(1);
  if (v_resultado->>'compatibilidad_altas_legacy')::boolean
     or (v_resultado->>'compatibilidad_revision')::int <> 2 then
    raise exception 'P29c no cerró el puente legacy: %', v_resultado;
  end if;
  begin
    perform crm.cerrar_altas_legacy_productos(2);
    raise exception 'P30 reejecutó o reabrió el cierre irreversible';
  exception when check_violation then null;
  end;
end;
$test$;
reset role;

-- Tras el cierre: las firmas antiguas no crean ni generan snapshots nuevos.
-- Conservar términos históricos sigue permitido, pero cambiarlos exige migrar
-- el contrato a una condición comercial publicada mediante los wrappers Portal.
select set_config(
  'request.jwt.claim.sub', '51000000-0000-4000-8000-000000000008', true
);
set local role authenticated;
do $test$
declare
  v_condicion_portal uuid;
  v_id_creado uuid;
  v_id_legacy_1 uuid;
  v_id_legacy_2 uuid;
  v_snapshot_1 uuid;
  v_snapshot_2 uuid;
  v_resultado jsonb;
begin
  select condicion_id into v_condicion_portal
  from public.productos_inversion_seleccion_fn(null)
  where producto_codigo = 'PORTAL-24' and seleccionable_nuevo;

  begin
    perform public.crear_contrato(
      jsonb_build_object(
        'cliente_id', '51000000-0000-4000-8000-000000000005',
        'numero_contrato', 'LEGACY-BLOQUEADO',
        'capital', 5000, 'moneda', 'PEN', 'tasa_anual', 15,
        'modalidad', 'mensual', 'tipo_interes', 'simple',
        'fecha_inicio', current_date,
        'fecha_vencimiento', (current_date + interval '12 months')::date,
        'categoria', 'nuevo'
      ),
      jsonb_build_array(jsonb_build_object(
        'numero_cuota', 1, 'fecha_programada', current_date + 30,
        'monto_programado', 100, 'tipo', 'cuota'
      ))
    );
    raise exception 'P31 un caller antiguo creó contrato tras cerrar el puente';
  exception when check_violation then null;
  end;

  v_resultado := public.crear_contrato_producto(
    v_condicion_portal,
    jsonb_build_object(
      'cliente_id', '51000000-0000-4000-8000-000000000005',
      'numero_contrato', 'PORTAL-CATALOGADO-001',
      'capital', 6000, 'moneda', 'USD', 'tasa_anual', 12,
      'modalidad', 'anual', 'tipo_interes', 'compuesto',
      'fecha_inicio', current_date,
      'fecha_vencimiento', (current_date + interval '24 months')::date,
      'categoria', 'upgrade'
    ),
    jsonb_build_array(jsonb_build_object(
      'numero_cuota', 1, 'fecha_programada', current_date + 730,
      'monto_programado', 1500, 'tipo', 'devolucion'
    ))
  );
  v_id_creado := (v_resultado->>'id')::uuid;
  if (v_resultado->>'producto_condicion_id')::uuid
       is distinct from v_condicion_portal
     or (select producto_condicion_id from public.contratos
         where id = v_id_creado) is distinct from v_condicion_portal then
    raise exception 'P31a el wrapper Portal no creó con la condición vigente';
  end if;

  select id, producto_condicion_id into v_id_legacy_1, v_snapshot_1
  from public.contratos where numero_contrato = 'LEGACY-001';
  select id, producto_condicion_id into v_id_legacy_2, v_snapshot_2
  from public.contratos where numero_contrato = 'LEGACY-002';

  if (select count(*) from public.productos_inversion_seleccion_fn(v_id_legacy_1)
      where es_actual and es_legacy) <> 1
     or (select count(*) from public.productos_inversion_seleccion_fn(v_id_legacy_1)
         where seleccionable_nuevo) <> 1 then
    raise exception 'P31b el selector Portal no combinó origen actual y catálogo vigente';
  end if;

  v_resultado := public.actualizar_contrato_con_cuenta_producto(
    v_id_legacy_1,
    v_snapshot_1,
    jsonb_build_object(
      'capital', 25000, 'moneda', 'PEN', 'tasa_anual', 15,
      'modalidad', 'mensual', 'tipo_interes', 'simple',
      'fecha_inicio', date '2025-01-15',
      'fecha_vencimiento', date '2026-01-15',
      'categoria', null
    ),
    '[]'::jsonb
  );
  if (v_resultado->>'producto_condicion_id')::uuid is distinct from v_snapshot_1 then
    raise exception 'P32 conservar términos legacy cambió su snapshot';
  end if;

  begin
    perform public.actualizar_contrato_con_cuenta_producto(
      v_id_legacy_1,
      v_snapshot_1,
      jsonb_build_object(
        'capital', 26000, 'moneda', 'PEN', 'tasa_anual', 15,
        'modalidad', 'mensual', 'tipo_interes', 'simple',
        'fecha_inicio', date '2025-01-15',
        'fecha_vencimiento', date '2026-01-15',
        'categoria', null
      ),
      '[]'::jsonb
    );
    raise exception 'P32a una corrección creó otro snapshot tras el cierre';
  exception when check_violation then null;
  end;

  v_resultado := public.actualizar_contrato_con_cuenta_producto(
    v_id_legacy_1,
    v_condicion_portal,
    jsonb_build_object(
      'capital', 6000, 'moneda', 'USD', 'tasa_anual', 12,
      'modalidad', 'anual', 'tipo_interes', 'compuesto',
      'fecha_inicio', current_date,
      'fecha_vencimiento', (current_date + interval '24 months')::date,
      'categoria', 'upgrade'
    ),
    '[]'::jsonb
  );
  if (v_resultado->>'producto_condicion_id')::uuid
       is distinct from v_condicion_portal then
    raise exception 'P32b el wrapper con cuenta no migró legacy al catálogo';
  end if;

  v_resultado := public.actualizar_contrato_producto(
    v_id_legacy_2,
    v_condicion_portal,
    jsonb_build_object(
      'capital', 7000, 'moneda', 'USD', 'tasa_anual', 13,
      'modalidad', 'anual', 'tipo_interes', 'compuesto',
      'fecha_inicio', current_date,
      'fecha_vencimiento', (current_date + interval '24 months')::date,
      'categoria', 'upgrade'
    ),
    '[]'::jsonb
  );
  if (v_resultado->>'producto_condicion_id')::uuid
       is distinct from v_condicion_portal then
    raise exception 'P32c el wrapper sin cuenta no migró legacy al catálogo';
  end if;
end;
$test$;
reset role;

do $test$
begin
  if (select count(*) from crm.producto_condiciones c
      where c.legacy_contrato_id = '52000000-0000-4000-8000-000000000001') <> 1
     or (select count(*) from crm.producto_condiciones c
         where c.legacy_contrato_id = '52000000-0000-4000-8000-000000000002') <> 1 then
    raise exception 'P32d el cierre permitió crear historia legacy nueva';
  end if;

  if exists (
       select 1 from crm.productos_inversion p
       where p.es_legacy and p.permite_altas_legacy
     ) then
    raise exception 'P32e una corrección reabrió las altas legacy';
  end if;

  if (select count(*)
      from public.contratos ct
      join crm.producto_condiciones c on c.id = ct.producto_condicion_id
      join crm.producto_versiones v on v.id = c.version_id
      join crm.productos_inversion p on p.id = v.producto_id
      where ct.id in (
        '52000000-0000-4000-8000-000000000001',
        '52000000-0000-4000-8000-000000000002'
      ) and p.codigo = 'PORTAL-24') <> 2 then
    raise exception 'P32f los contratos legacy no terminaron catalogados';
  end if;
end;
$test$;

-- Perfil inactivo y cliente portal: fail closed.
select set_config(
  'request.jwt.claim.sub', '51000000-0000-4000-8000-000000000004', true
);
set local role authenticated;
do $test$
begin
  begin
    perform crm.productos_inversion_gestion_fn();
    raise exception 'P33 Gerencia con perfil inactivo leyó gestión';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.crear_producto_inversion(
      'INACTIVO', 'No debe crear', null, current_date, null,
      jsonb_build_array(jsonb_build_object(
        'categoria', 'nuevo', 'moneda', 'PEN', 'plazo_meses', 12,
        'modalidad', 'mensual', 'tipo_interes', 'simple',
        'capital_minimo', 1000, 'capital_maximo', 2000,
        'tasa_referencia', 15
      ))
    );
    raise exception 'P34 Gerencia inactiva mutó catálogo';
  exception when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

select set_config(
  'request.jwt.claim.sub', '51000000-0000-4000-8000-000000000005', true
);
set local role authenticated;
do $test$
begin
  if (select count(*) from crm.productos_inversion) <> 0 then
    raise exception 'P35 cliente portal ve filas del catálogo';
  end if;
  begin
    perform crm.productos_inversion_seleccion_fn();
    raise exception 'P36 cliente portal ejecutó selector';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.productos_inversion_seleccion_fn(null);
    raise exception 'P36e cliente portal ejecutó selector público';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.crear_contrato_producto(null, null, null);
    raise exception 'P36f cliente portal ejecutó writer público';
  exception when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- Superadmin y Admin exclusivamente Portal no heredan lectura CRM. La cuenta
-- que suma Superadmin + Gerencia es el actor ...001 ejercitado arriba.
set local role authenticated;
do $test$
declare
  v_actor uuid;
begin
  foreach v_actor in array array[
    '51000000-0000-4000-8000-000000000007'::uuid,
    '51000000-0000-4000-8000-000000000008'::uuid
  ] loop
    perform set_config('request.jwt.claim.sub', v_actor::text, true);

    if (select count(*) from crm.productos_inversion) <> 0
       or (select count(*) from crm.producto_versiones) <> 0
       or (select count(*) from crm.producto_condiciones) <> 0 then
      raise exception 'P36a actor Portal % ve tablas del catálogo', v_actor;
    end if;

    begin
      perform crm.productos_inversion_gestion_fn();
      raise exception 'P36b actor Portal % leyó gestión de productos', v_actor;
    exception when insufficient_privilege then null;
    end;

    begin
      perform crm.productos_inversion_seleccion_fn();
      raise exception 'P36c actor Portal % ejecutó selector de productos', v_actor;
    exception when insufficient_privilege then null;
    end;

    if (select count(*) from public.productos_inversion_seleccion_fn(null)
        where seleccionable_nuevo) <> 1 then
      raise exception 'P36c0 actor Portal % no recibió selector público', v_actor;
    end if;

    begin
      perform crm.crear_contrato_producto(null, null, null);
      raise exception 'P36c1 actor Portal % creó contrato por wrapper CRM', v_actor;
    exception when insufficient_privilege then null;
    end;

    begin
      perform crm.crear_contrato_con_cuenta_producto(null, null, null, null);
      raise exception 'P36c2 actor Portal % creó contrato con cuenta por wrapper CRM', v_actor;
    exception when insufficient_privilege then null;
    end;

    begin
      perform crm.actualizar_contrato_producto(null, null, null, null);
      raise exception 'P36c3 actor Portal % actualizó contrato por wrapper CRM', v_actor;
    exception when insufficient_privilege then null;
    end;

    begin
      perform crm.actualizar_contrato_con_cuenta_producto(null, null, null, null);
      raise exception 'P36c4 actor Portal % actualizó contrato con cuenta por wrapper CRM', v_actor;
    exception when insufficient_privilege then null;
    end;

    if (select count(*) from crm.contratos_cartera_fn()) <> 0 then
      raise exception 'P36d actor Portal % leyó contratos operativos', v_actor;
    end if;
  end loop;
end;
$test$;
reset role;

do $test$
begin
  begin
    delete from crm.productos_inversion where codigo = 'RENTA-12';
    raise exception 'P37a eliminó físicamente un producto archivado';
  exception when check_violation then null;
  end;
  begin
    delete from crm.producto_condiciones
    where id = (
      select c.id
      from crm.producto_condiciones c
      join crm.producto_versiones v on v.id = c.version_id
      join crm.productos_inversion p on p.id = v.producto_id
      where p.codigo = 'RENTA-12'
      limit 1
    );
    raise exception 'P37b eliminó físicamente una condición';
  exception when check_violation then null;
  end;

  if (select count(*) from public.audit_log
      where tabla in (
        'crm.productos_inversion',
        'crm.producto_versiones',
        'crm.producto_condiciones'
      )) < 8 then
    raise exception 'P37 faltan eventos de auditoría del catálogo';
  end if;
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where (
        (n.nspname in ('crm', 'private') and p.proname like '%producto%')
        or (
          n.nspname = 'public'
          and p.proname in (
            'productos_inversion_seleccion_fn',
            'crear_contrato', 'actualizar_contrato',
            'crear_contrato_producto', 'actualizar_contrato_producto',
            'actualizar_contrato_con_cuenta_producto'
          )
        )
      )
      and p.prosecdef
      and not exists (
        select 1 from unnest(coalesce(p.proconfig, '{}')) cfg
        where cfg = 'search_path=' or cfg like 'search_path=%'
      )
  ) then
    raise exception 'P38 hay una función privilegiada sin search_path fijo';
  end if;

  if exists (
    select 1
    from pg_constraint fk
    join pg_class t on t.oid = fk.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where fk.contype = 'f'
      and n.nspname = 'crm'
      and t.relname in (
        'productos_inversion', 'producto_versiones', 'producto_condiciones'
      )
      and not exists (
        select 1 from pg_index i
        where i.indrelid = fk.conrelid
          and fk.conkey[1] = any(i.indkey)
      )
  ) then
    raise exception 'P39 existe una FK nueva sin índice';
  end if;

  if exists (
    select 1
    from pg_class t
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'crm'
      and t.relname in (
        'productos_inversion', 'producto_versiones', 'producto_condiciones'
      )
      and not t.relrowsecurity
  ) then
    raise exception 'P40 existe una tabla expuesta del catálogo sin RLS';
  end if;
end;
$test$;

rollback;
select 'PRODUCTOS_INVERSION_TX_OK' as resultado;

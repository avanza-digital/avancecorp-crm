-- LEGACY / ORACULO HISTORICO PRE-20260807203757.
-- Depende deliberadamente del fixture antiguo de Inteligencia Comercial; no es
-- el gate vigente de Metas. La frontera actual se valida con
-- test-metas-versionadas.sql.
\set ON_ERROR_STOP on

-- Oraculo autocontenido: levanta la frontera de Inteligencia (que instalaba el
-- veto de solo lectura), completa el minimo del portal y aplica la migracion
-- REAL de Gerencia operativa. Solo debe correr en PostgreSQL desechable.

\ir test-inteligencia-comercial-reuniones.sql

alter table public.perfiles
  add column nombres text,
  add column apellidos text,
  add column tipo_documento text default 'DNI',
  add column dni text,
  add column correo text,
  add column telefono text,
  add column asesor_perfil_id uuid,
  add column creado_por uuid,
  add column creado_en timestamptz not null default now(),
  add column banco text,
  add column tipo_cuenta text,
  add column numero_cuenta text,
  add column cci text,
  add column titular_distinto boolean not null default false,
  add column beneficiario_nombre text,
  add column beneficiario_dni text,
  add column banco_usd text,
  add column tipo_cuenta_usd text,
  add column numero_cuenta_usd text,
  add column cci_usd text,
  add column titular_distinto_usd boolean not null default false,
  add column beneficiario_nombre_usd text,
  add column beneficiario_dni_usd text,
  add column actualizado_en timestamptz not null default now();

alter table public.contratos
  alter column id set default gen_random_uuid(),
  add column numero_contrato text unique,
  add column cliente_id uuid references public.perfiles(id),
  add column tasa_anual numeric,
  add column modalidad text,
  add column tipo_interes text,
  add column categoria text,
  add column estado text not null default 'activo',
  add column fecha_inicio date,
  add column fecha_vencimiento date,
  add column notas_internas text,
  add column creado_por uuid;

create table public.cronograma_pagos (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos(id),
  numero_cuota integer not null,
  fecha_programada date not null,
  monto_programado numeric not null,
  estado text not null,
  tipo text not null,
  monto_pagado numeric
);

alter table crm.leads
  add column dni text,
  add column creado_por uuid;

alter table public.perfiles enable row level security;

create function public.es_admin()
returns boolean language sql stable set search_path = ''
as $$ select false; $$;
create function public.es_analista()
returns boolean language sql stable set search_path = ''
as $$ select false; $$;
create function public.es_superadmin()
returns boolean language sql stable set search_path = ''
as $$ select false; $$;
create function public.mi_rol()
returns text language sql stable set search_path = ''
as $$ select null::text; $$;

create function public._sync_contrato_titulares(uuid, jsonb)
returns void language plpgsql set search_path = ''
as $$ begin null; end; $$;

create function private.puede_acceder_crm()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.rol_crm((select auth.uid())) is not null;
$$;

create function private.puede_gestionar_cuentas_cliente(uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select false; $$;

-- Firmas vigentes requeridas por el preflight de la migracion.
create function public.crear_contrato(jsonb, jsonb)
returns jsonb language sql security definer set search_path = ''
as $$ select '{}'::jsonb; $$;
create function public.actualizar_contrato(uuid, jsonb, jsonb)
returns jsonb language sql security definer set search_path = ''
as $$ select '{}'::jsonb; $$;

grant usage on schema public, crm, private to authenticated;
grant select, update on public.perfiles to authenticated;
grant select, insert, update, delete on crm.leads to authenticated;
grant select, insert, update, delete on crm.actividades to authenticated;
grant select, insert, update, delete on crm.tareas to authenticated;
grant execute on function auth.uid() to authenticated;
grant execute on function private.rol_crm(uuid) to authenticated;
grant execute on function private.vendedor_ids_visibles(uuid) to authenticated;
grant execute on function private.test_fallar_si(boolean, text) to authenticated;
grant execute on function private.test_esperar_sqlstate(text, text, text)
  to authenticated;

-- El arnés base se concentra en RPCs y no traía las policies SELECT históricas
-- de F0. Se añaden aquí para reproducir la frontera real que UPDATE/EXISTS usa.
create policy oraculo_leads_select on crm.leads
  for select to authenticated
  using (private.rol_crm((select auth.uid())) is not null);
create policy oraculo_tareas_select on crm.tareas
  for select to authenticated
  using (private.rol_crm((select auth.uid())) is not null);
create policy oraculo_actividades_select on crm.actividades
  for select to authenticated
  using (private.rol_crm((select auth.uid())) is not null);

\ir ../migrations/20260807123000_crm_gerencia_operativa.sql

-- El veto desaparecio tanto de escritura directa como de RPC definer.
do $$
begin
  perform private.test_fallar_si(
    to_regprocedure('private.trg_gerencia_inteligencia_solo_lectura()') is not null,
    'Sigue viva la funcion de solo lectura de Gerencia'
  );
  perform private.test_fallar_si(
    exists (
      select 1
      from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'crm'
        and c.relname in ('leads', 'tareas', 'actividades')
        and t.tgname = 'trg_00_gerencia_solo_lectura'
        and not t.tgisinternal
    ),
    'Sigue vivo un trigger de solo lectura de Gerencia'
  );
end;
$$;

-- Cliente y caso de Gerencia sobre cartera de un analista.
update public.perfiles
set rol = 'cliente', dni = '87654321', asesor_perfil_id =
  '10000000-0000-4000-8000-000000000003'
where id = '10000000-0000-4000-8000-000000000004';

insert into crm.leads (
  id, activo, etapa, vendedor_id, dni, origen, categoria_interes, creado_por
) values (
  '20000000-0000-4000-8000-000000000090',
  true,
  'contactado',
  '10000000-0000-4000-8000-000000000003',
  '87654321',
  'referido',
  'nuevo',
  '10000000-0000-4000-8000-000000000003'
);

set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
set role authenticated;

select private.test_esperar_sqlstate(
  $sql$
    insert into crm.tareas (
      lead_id, vendedor_id, tipo, titulo, vence_en, creado_por
    ) values (
      null,
      '10000000-0000-4000-8000-000000000004',
      'llamada',
      'Tarea sobre perfil ajeno al equipo',
      now() + interval '1 day',
      auth.uid()
    )
  $sql$,
  '42501',
  'Gerencia pudo asignar una tarea a un perfil ajeno al equipo CRM'
);

update crm.leads
set etapa = 'reunion_agendada'
where id = '20000000-0000-4000-8000-000000000090';

insert into crm.actividades (
  lead_id, tipo, detalle, creado_por
) values (
  '20000000-0000-4000-8000-000000000090',
  'nota',
  'Gestion de Gerencia',
  auth.uid()
);

insert into crm.tareas (
  id, lead_id, tipo, titulo, vence_en, creado_por
) values (
  '30000000-0000-4000-8000-000000000090',
  '20000000-0000-4000-8000-000000000090',
  'llamada',
  'Seguimiento de Gerencia',
  now() + interval '1 day',
  auth.uid()
);

select crm.cerrar_tarea(
  '30000000-0000-4000-8000-000000000090',
  'completada',
  'llamada_realizada',
  'Atendido por Gerencia',
  null
);

select crm.convertir_lead(
  '20000000-0000-4000-8000-000000000090',
  '10000000-0000-4000-8000-000000000004'
);

update public.perfiles
set telefono = '+51911111111'
where id = '10000000-0000-4000-8000-000000000004';

reset role;
select private.test_fallar_si(
  exists (
    select 1 from public.perfiles
    where id = '10000000-0000-4000-8000-000000000004'
      and telefono = '+51911111111'
  ),
  'Gerencia obtuvo UPDATE crudo sobre public.perfiles'
);

set role authenticated;
select crm.actualizar_cliente_gerencia(
  '10000000-0000-4000-8000-000000000004',
  jsonb_build_object('telefono', '+51999999999')
);

reset role;
select private.test_esperar_sqlstate(
  $sql$
    select crm.actualizar_cliente_gerencia(
      '10000000-0000-4000-8000-000000000004',
      '{"rol":"admin"}'::jsonb
    )
  $sql$,
  '22023',
  'Gerencia pudo inyectar un campo fuera del formulario de cliente'
);
select private.test_esperar_sqlstate(
  $sql$
    select crm.actualizar_cliente_gerencia(
      '10000000-0000-4000-8000-000000000003',
      '{"telefono":"+51900000000"}'::jsonb
    )
  $sql$,
  'P0002',
  'Gerencia pudo usar la RPC de clientes sobre un perfil staff'
);

set role authenticated;
select private.test_fallar_si(
  exists (
    select 1 from public.perfiles
    where id = '10000000-0000-4000-8000-000000000003'
  ),
  'Gerencia obtuvo lectura cruda de perfiles staff ajenos'
);
reset role;

set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';
select private.test_esperar_sqlstate(
  $sql$
    select crm.actualizar_cliente_gerencia(
      '10000000-0000-4000-8000-000000000004',
      '{"telefono":"+51900000000"}'::jsonb
    )
  $sql$,
  '42501',
  'Un analista pudo invocar la correccion global de Gerencia'
);
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

select private.test_fallar_si(
  not private.puede_gestionar_cuentas_cliente(
    '10000000-0000-4000-8000-000000000004'
  ),
  'Gerencia no obtuvo banca contractual del cliente'
);

set role authenticated;
select public.crear_contrato(
  jsonb_build_object(
    'cliente_id', '10000000-0000-4000-8000-000000000004',
    'capital', 10000,
    'moneda', 'PEN',
    'tasa_anual', 12,
    'modalidad', 'mensual',
    'tipo_interes', 'simple',
    'categoria', 'nuevo',
    'fecha_inicio', current_date,
    'fecha_vencimiento', current_date + 30,
    'notas_internas', null
  ),
  jsonb_build_array(
    jsonb_build_object(
      'numero_cuota', 1,
      'fecha_programada', current_date + 30,
      'monto_programado', 100
    )
  )
);

reset role;
update public.contratos
set estado = 'renovado'
where cliente_id = '10000000-0000-4000-8000-000000000004';
select private.test_esperar_sqlstate(
  format(
    'select public.actualizar_contrato(%L::uuid, ''{}''::jsonb, null)',
    (
      select id
      from public.contratos
      where cliente_id = '10000000-0000-4000-8000-000000000004'
      limit 1
    )
  ),
  'P0001',
  'Gerencia pudo reescribir un contrato legalmente cerrado'
);
set role authenticated;

-- No se abre hard-delete: la sentencia es valida pero RLS toca cero filas.
delete from crm.leads
where id = '20000000-0000-4000-8000-000000000090';

reset role;
reset request.jwt.claim.sub;

do $$
begin
  perform private.test_fallar_si(
    (select etapa from crm.leads
     where id = '20000000-0000-4000-8000-000000000090') <> 'convertido',
    'Gerencia no pudo convertir el lead global'
  );
  perform private.test_fallar_si(
    not exists (
      select 1
      from crm.tareas
      where id = '30000000-0000-4000-8000-000000000090'
        and estado = 'completada'
    ),
    'Gerencia no pudo cerrar la tarea'
  );
  perform private.test_fallar_si(
    not exists (
      select 1
      from public.perfiles
      where id = '10000000-0000-4000-8000-000000000004'
        and telefono = '+51999999999'
    ),
    'Gerencia no pudo corregir el cliente'
  );
  perform private.test_fallar_si(
    not exists (
      select 1
      from public.contratos
      where cliente_id = '10000000-0000-4000-8000-000000000004'
        and creado_por = '10000000-0000-4000-8000-000000000001'
    ),
    'Gerencia no pudo crear el contrato'
  );
  perform private.test_fallar_si(
    not exists (
      select 1
      from crm.leads
      where id = '20000000-0000-4000-8000-000000000090'
    ),
    'Gerencia obtuvo DELETE fisico sobre leads'
  );
end;
$$;

select 'GERENCIA_OPERATIVA_TX_OK' as resultado;

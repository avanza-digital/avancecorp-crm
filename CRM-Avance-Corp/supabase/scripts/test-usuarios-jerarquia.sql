\set ON_ERROR_STOP on

-- Oraculo autocontenido. Ejecutar solo en PostgreSQL desechable: crea una
-- frontera minima compatible con P04, aplica la migracion REAL y verifica
-- autoridad, aislamiento, invariantes, concurrencia y handoff atomico.

do $$
declare v_rol text;
begin
  foreach v_rol in array array['anon','authenticated','service_role'] loop
    if not exists (select 1 from pg_roles where rolname = v_rol) then
      execute format('create role %I nologin', v_rol);
    end if;
  end loop;
end;
$$;

create schema auth;
create schema crm;
create schema private;

create function auth.uid()
returns uuid language sql stable set search_path = ''
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create function private.test_fallar_si(p_falla boolean, p_mensaje text)
returns void language plpgsql security invoker set search_path = ''
as $$
begin
  if p_falla then raise exception using message = p_mensaje; end if;
end;
$$;

create function private.test_esperar_sqlstate(
  p_sql text, p_estado text, p_mensaje text
)
returns void language plpgsql security invoker set search_path = ''
as $$
declare
  v_fallo boolean := false;
begin
  begin
    execute p_sql;
  exception when others then
    if sqlstate <> p_estado then raise; end if;
    v_fallo := true;
  end;
  if not v_fallo then
    raise exception using message = p_mensaje;
  end if;
end;
$$;

revoke all on function private.test_fallar_si(boolean, text) from public;
revoke all on function private.test_esperar_sqlstate(text, text, text) from public;

create table auth.users (
  id uuid primary key,
  email text unique,
  raw_app_meta_data jsonb not null default '{}'::jsonb
);

create table public.perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nombre_completo text,
  tipo_documento text not null default 'DNI',
  dni text,
  correo text unique,
  telefono text,
  whatsapp text,
  cargo text,
  rol text not null default 'cliente' check (rol in (
    'cliente','analista','admin','superadmin','directorio','comercial'
  )),
  activo boolean not null default true,
  asesor_perfil_id uuid references public.perfiles(id),
  creado_por uuid references public.perfiles(id),
  creado_en timestamptz not null default clock_timestamp(),
  actualizado_en timestamptz not null default clock_timestamp(),
  debe_cambiar_password boolean not null default false,
  banco text,
  numero_cuenta text
);

create unique index perfiles_dni_staff_test
  on public.perfiles (dni) where rol <> 'cliente';

create table crm.equipo (
  perfil_id uuid primary key references public.perfiles(id),
  rol_crm text not null check (rol_crm in (
    'vendedor','supervisor','gerencia','coordinador'
  )),
  supervisor_id uuid references crm.equipo(perfil_id),
  activo boolean not null default true,
  creado_por uuid references public.perfiles(id),
  creado_en timestamptz not null default clock_timestamp(),
  actualizado_en timestamptz not null default clock_timestamp(),
  capacidad_leads_objetivo smallint,
  check (supervisor_id is null or supervisor_id <> perfil_id)
);

create table crm.leads (
  id uuid primary key,
  vendedor_id uuid references crm.equipo(perfil_id),
  asignado_supervisor_id uuid references crm.equipo(perfil_id),
  activo boolean not null default true,
  etapa text not null default 'nuevo'
);

create table crm.tareas (
  id uuid primary key,
  lead_id uuid references crm.leads(id),
  vendedor_id uuid references crm.equipo(perfil_id),
  asignado_supervisor_id uuid references crm.equipo(perfil_id),
  activo boolean not null default true,
  estado text not null default 'pendiente'
);

create table crm.agenda_ics (
  perfil_id uuid primary key references crm.equipo(perfil_id),
  token uuid not null
);

create function private.touch_equipo_test()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  new.actualizado_en := clock_timestamp();
  return new;
end;
$$;
create trigger trg_equipo_touch before update on crm.equipo
for each row execute function private.touch_equipo_test();

create function private.rotar_ics_test()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  update crm.agenda_ics set token = gen_random_uuid()
  where perfil_id = new.perfil_id;
  return new;
end;
$$;
create trigger trg_equipo_rotar_agenda_ics_offboarding
after update of activo on crm.equipo
for each row when (old.activo and not new.activo)
execute function private.rotar_ics_test();

alter table public.perfiles enable row level security;
alter table crm.equipo enable row level security;
alter table crm.leads enable row level security;
alter table crm.tareas enable row level security;
alter table crm.agenda_ics enable row level security;

-- Solo para que el arnes pueda inspeccionar postcondiciones como
-- authenticated. La migracion bajo prueba no crea ni modifica estas policies;
-- en produccion siguen rigiendo las policies historicas del Portal/P04.
create policy oraculo_perfiles_inspeccion on public.perfiles
  for select to authenticated using (true);
create policy oraculo_equipo_inspeccion on crm.equipo
  for select to authenticated using (true);
create policy oraculo_leads_inspeccion on crm.leads
  for select to authenticated using (true);
create policy oraculo_tareas_inspeccion on crm.tareas
  for select to authenticated using (true);
create policy oraculo_ics_inspeccion on crm.agenda_ics
  for select to authenticated using (true);

create function private.rol_crm(p_perfil_id uuid)
returns text language sql stable security definer set search_path = ''
as $$
  select e.rol_crm from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_perfil_id and e.activo and p.activo;
$$;

create function private.vendedor_ids_visibles(p_perfil_id uuid)
returns setof uuid language sql stable security definer set search_path = ''
as $$
  select e.perfil_id
  from crm.equipo e
  where private.rol_crm(p_perfil_id) = 'gerencia'
     or e.perfil_id = p_perfil_id
     or e.supervisor_id = p_perfil_id;
$$;

create function private.es_lector_global()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.perfiles p
    where p.id = (select auth.uid()) and p.activo
      and p.rol in ('directorio','admin','superadmin')
  ) and not exists (
    select 1 from crm.equipo e where e.perfil_id = (select auth.uid())
  );
$$;

create function private.puede_acceder_crm()
returns boolean language sql stable security definer set search_path = ''
as $$
  select private.rol_crm((select auth.uid())) is not null
      or private.es_lector_global();
$$;

create function crm.mi_acceso_fn()
returns jsonb language sql stable security definer set search_path = ''
as $$ select '{}'::jsonb; $$;

-- Superficies C1/C1b/C1c mínimas: la migración real las encapsula para que el
-- gate canónico prevalezca sobre sus comprobaciones históricas directas.
create function crm.leads_por_repartir()
returns table (
  id uuid, nombre_completo text, distrito text, origen text,
  categoria_interes text, monto_estimado numeric, moneda text,
  creado_en timestamptz, clasificacion_auto text, comentario text
)
language sql stable security definer set search_path = ''
as $$
  select null::uuid,null::text,null::text,null::text,null::text,null::numeric,
         null::text,null::timestamptz,null::text,null::text where false;
$$;

create function crm.supervisores_para_reparto()
returns table (
  perfil_id uuid, nombre text, activo boolean, bandeja_pendiente integer
)
language sql stable security definer set search_path = ''
as $$
  select e.perfil_id,p.nombre_completo,e.activo,0::integer
  from crm.equipo e
  join public.perfiles p on p.id=e.perfil_id
  where e.rol_crm='supervisor' and e.activo and p.activo;
$$;

create function crm.repartir_lead(p_lead uuid, p_supervisor uuid)
returns jsonb language sql security definer set search_path = ''
as $$ select jsonb_build_object('lead_id',p_lead,'supervisor_id',p_supervisor); $$;

create function crm.descartar_lead(
  p_lead uuid, p_motivo text, p_nota text default null
)
returns jsonb language sql security definer set search_path = ''
as $$ select jsonb_build_object('lead_id',p_lead,'motivo',p_motivo,'nota',p_nota); $$;

create function crm.deshacer_descarte(p_lead uuid)
returns jsonb language sql security definer set search_path = ''
as $$ select jsonb_build_object('lead_id',p_lead); $$;

create function crm.leads_descartados()
returns table (
  id uuid, nombre_completo text, distrito text, origen text,
  categoria_interes text, monto_estimado numeric, moneda text, creado_en timestamptz,
  clasificacion_auto text, comentario text, nota_descarte text,
  motivo_descarte text, descartado_en timestamptz,
  descartado_por_nombre text, es_mio boolean, puede_deshacer boolean
)
language sql stable security definer set search_path = ''
as $$
  select null::uuid,null::text,null::text,null::text,null::text,null::numeric,
         null::text,null::timestamptz,null::text,null::text,null::text,null::text,
         null::timestamptz,null::text,null::boolean,null::boolean where false;
$$;

create function crm.agenda_ics_feed_fn(p_token uuid, p_desde timestamptz)
returns jsonb language sql stable security invoker set search_path = ''
as $$
  select jsonb_build_object(
    'autorizado', exists(select 1 from crm.agenda_ics a where a.token=p_token),
    'tareas', '[]'::jsonb
  );
$$;

grant usage on schema auth, crm, private to authenticated;
grant usage on schema crm to service_role;
grant execute on function auth.uid() to authenticated;
grant execute on function private.rol_crm(uuid) to authenticated;
grant execute on function private.vendedor_ids_visibles(uuid) to authenticated;
grant execute on function private.es_lector_global() to authenticated;
grant execute on function private.puede_acceder_crm() to authenticated;
grant execute on function crm.mi_acceso_fn() to authenticated;
grant execute on function private.test_fallar_si(boolean, text) to authenticated;
grant execute on function private.test_esperar_sqlstate(text, text, text)
  to authenticated;
grant select on public.perfiles to authenticated;
grant select on crm.equipo to authenticated;
grant select on crm.leads, crm.tareas, crm.agenda_ics to authenticated;

insert into auth.users (id, email) values
  ('10000000-0000-4000-8000-000000000001','gerencia@test.invalid'),
  ('10000000-0000-4000-8000-000000000002','superadmin@test.invalid'),
  ('10000000-0000-4000-8000-000000000003','admin@test.invalid'),
  ('10000000-0000-4000-8000-000000000004','sup1@test.invalid'),
  ('10000000-0000-4000-8000-000000000005','sup2@test.invalid'),
  ('10000000-0000-4000-8000-000000000006','vend1@test.invalid'),
  ('10000000-0000-4000-8000-000000000007','vend2@test.invalid'),
  ('10000000-0000-4000-8000-000000000008','cliente@test.invalid'),
  ('10000000-0000-4000-8000-000000000009','nuevo@test.invalid'),
  ('10000000-0000-4000-8000-000000000010','directorio-crm@test.invalid'),
  ('10000000-0000-4000-8000-000000000011','suspendido@test.invalid'),
  ('10000000-0000-4000-8000-000000000012','doble@test.invalid'),
  ('10000000-0000-4000-8000-000000000013','directorio@test.invalid'),
  ('10000000-0000-4000-8000-000000000014','superadmin-vendedor@test.invalid'),
  ('10000000-0000-4000-8000-000000000015','superadmin-coordinador@test.invalid'),
  ('10000000-0000-4000-8000-000000000016','coordinador@test.invalid'),
  ('10000000-0000-4000-8000-000000000017','superadmin-supervisor@test.invalid'),
  ('10000000-0000-4000-8000-000000000018','analista-pendiente@test.invalid');

insert into auth.users (id, email, raw_app_meta_data) values
  ('10000000-0000-4000-8000-000000000019','alta-directa@test.invalid','{"origen_app":"crm"}'::jsonb),
  ('10000000-0000-4000-8000-000000000020','supervisor-invalido@test.invalid','{"origen_app":"crm"}'::jsonb),
  ('10000000-0000-4000-8000-000000000021','alan-pendiente@test.invalid','{"origen_app":"crm"}'::jsonb);

insert into public.perfiles (
  id, nombre_completo, dni, correo, rol, activo, telefono, banco, numero_cuenta
) values
  ('10000000-0000-4000-8000-000000000001','Gerencia','10000001','gerencia@test.invalid','analista',true,'+51900000001','SECRETO','111'),
  ('10000000-0000-4000-8000-000000000002','Superadmin','10000002','superadmin@test.invalid','superadmin',true,'+51900000002','SECRETO','222'),
  ('10000000-0000-4000-8000-000000000003','Admin','10000003','admin@test.invalid','admin',true,'+51900000003','SECRETO','333'),
  ('10000000-0000-4000-8000-000000000004','Supervisor Uno','10000004','sup1@test.invalid','analista',true,'+51900000004','SECRETO','444'),
  ('10000000-0000-4000-8000-000000000005','Supervisor Dos','10000005','sup2@test.invalid','analista',true,'+51900000005','SECRETO','555'),
  ('10000000-0000-4000-8000-000000000006','Vendedor Uno','10000006','vend1@test.invalid','analista',true,'+51900000006','SECRETO','666'),
  ('10000000-0000-4000-8000-000000000007','Vendedor Dos','10000007','vend2@test.invalid','analista',true,'+51900000007','SECRETO','777'),
  ('10000000-0000-4000-8000-000000000008','Cliente','10000008','cliente@test.invalid','cliente',true,'+51900000008','SECRETO','888'),
  ('10000000-0000-4000-8000-000000000010','Directorio CRM','10000010','directorio-crm@test.invalid','comercial',true,'+51900000010','SECRETO','1010'),
  ('10000000-0000-4000-8000-000000000011','Suspendido','10000011','suspendido@test.invalid','comercial',false,'+51900000011','SECRETO','1111'),
  ('10000000-0000-4000-8000-000000000012','Superadmin Gerencia','10000012','doble@test.invalid','superadmin',true,'+51900000012','SECRETO','1212'),
  ('10000000-0000-4000-8000-000000000013','Directorio Portal','10000013','directorio@test.invalid','directorio',true,'+51900000013','SECRETO','1313'),
  ('10000000-0000-4000-8000-000000000014','Superadmin Vendedor','10000014','superadmin-vendedor@test.invalid','superadmin',true,'+51900000014','SECRETO','1414'),
  ('10000000-0000-4000-8000-000000000015','Superadmin Coordinador','10000015','superadmin-coordinador@test.invalid','superadmin',true,'+51900000015','SECRETO','1515'),
  ('10000000-0000-4000-8000-000000000016','Coordinador','10000016','coordinador@test.invalid','comercial',true,'+51900000016','SECRETO','1616'),
  ('10000000-0000-4000-8000-000000000017','Superadmin Supervisor','10000017','superadmin-supervisor@test.invalid','superadmin',true,'+51900000017','SECRETO','1717'),
  ('10000000-0000-4000-8000-000000000018','Analista Portal Pendiente','10000018','analista-pendiente@test.invalid','analista',true,'+51900000018','SECRETO','1818');

insert into public.perfiles (
  id, nombre_completo, tipo_documento, dni, correo, rol, activo, telefono
) values (
  '10000000-0000-4000-8000-000000000021','Alan Pendiente','CE','001237707',
  'alan-pendiente@test.invalid','comercial',true,'+51900000021'
);

update public.perfiles set asesor_perfil_id =
  '10000000-0000-4000-8000-000000000006'
where id = '10000000-0000-4000-8000-000000000008';

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values
  ('10000000-0000-4000-8000-000000000001','gerencia',null,true),
  ('10000000-0000-4000-8000-000000000004','supervisor',null,true),
  ('10000000-0000-4000-8000-000000000005','supervisor',null,true),
  ('10000000-0000-4000-8000-000000000006','vendedor','10000000-0000-4000-8000-000000000004',true),
  ('10000000-0000-4000-8000-000000000007','vendedor','10000000-0000-4000-8000-000000000004',true),
  ('10000000-0000-4000-8000-000000000011','vendedor',null,false),
  ('10000000-0000-4000-8000-000000000012','gerencia',null,true),
  ('10000000-0000-4000-8000-000000000014','vendedor','10000000-0000-4000-8000-000000000004',false),
  ('10000000-0000-4000-8000-000000000015','coordinador',null,false),
  ('10000000-0000-4000-8000-000000000016','coordinador',null,true),
  ('10000000-0000-4000-8000-000000000017','supervisor',null,false);

insert into crm.leads (id, vendedor_id) values
  ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000006');
insert into crm.leads (id, asignado_supervisor_id) values
  ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000004');
insert into crm.tareas (id, lead_id, vendedor_id) values
  ('30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000006');
insert into crm.tareas (id, lead_id, asignado_supervisor_id) values
  ('30000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000004');
insert into crm.agenda_ics (perfil_id, token) values
  ('10000000-0000-4000-8000-000000000006','50000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-000000000012','50000000-0000-4000-8000-000000000002'),
  ('10000000-0000-4000-8000-000000000015','50000000-0000-4000-8000-000000000003');

\ir ../migrations/20260807203740_crm_usuarios_jerarquia_autoservicio.sql
\ir ../migrations/20260821212628_crm_admision_analista_portal_como_candidato.sql
\ir ../migrations/20260821214502_crm_corregir_validacion_correo_candidato.sql
\ir ../migrations/20260821223019_crm_eliminar_recuperacion_credenciales.sql
\ir ../migrations/20260821233241_crm_alta_vendedor_completa_gerencia.sql

-- Estructura/ACL: Directorio entra al dominio, eventos quedan cerrados y no
-- reaparece escritura directa sobre crm.equipo.
do $$
begin
  perform private.test_fallar_si(
    not pg_catalog.pg_get_constraintdef((
      select oid from pg_constraint
      where conrelid = 'crm.equipo'::regclass
        and conname = 'equipo_rol_crm_check'
    )) like '%directorio%',
    'El CHECK de equipo no incluyo Directorio'
  );
  perform private.test_fallar_si(
    not (select relrowsecurity from pg_class where oid='crm.usuario_eventos'::regclass),
    'usuario_eventos quedo sin RLS'
  );
  perform private.test_fallar_si(
    has_table_privilege('authenticated','crm.usuario_eventos','SELECT')
      or has_table_privilege('authenticated','crm.usuario_eventos','INSERT'),
    'authenticated obtuvo acceso directo al audit de usuarios'
  );
  perform private.test_fallar_si(
    pg_catalog.to_regprocedure(
      'crm.preparar_recuperacion_usuario_fn(uuid,uuid)'
    ) is not null,
    'La RPC retirada de recuperacion sigue disponible'
  );
  perform private.test_fallar_si(
    not has_function_privilege(
      'authenticated',
      'crm.registrar_vendedor_usuario_fn(uuid,text,text,text,text,text,text,text,uuid,uuid)',
      'EXECUTE'
    )
      or has_function_privilege(
        'anon',
        'crm.registrar_vendedor_usuario_fn(uuid,text,text,text,text,text,text,text,uuid,uuid)',
        'EXECUTE'
      )
      or has_function_privilege(
        'service_role',
        'crm.registrar_vendedor_usuario_fn(uuid,text,text,text,text,text,text,text,uuid,uuid)',
        'EXECUTE'
      ),
    'La ACL del alta atomica de Vendedor no es la esperada'
  );
  perform private.test_fallar_si(
    has_function_privilege(
      'authenticated', 'private.es_directorio_crm_activo()', 'EXECUTE'
    )
      or has_function_privilege(
        'authenticated', 'private.puede_listar_usuarios_crm()', 'EXECUTE'
    ),
    'authenticated obtuvo EXECUTE directo sobre helpers privados de Usuarios'
  );
  perform private.test_fallar_si(
    private.es_destino_crm_activo(
      '10000000-0000-4000-8000-000000000014', array['vendedor']
    )
      or private.es_destino_crm_activo(
        '10000000-0000-4000-8000-000000000015', array['coordinador']
      )
      or not private.es_destino_crm_activo(
        '10000000-0000-4000-8000-000000000006', array['vendedor']
      )
      or not private.es_destino_crm_activo(
        '10000000-0000-4000-8000-000000000012', array['gerencia']
      ),
    'El rol efectivo no gobierna actores y destinos con la misma semantica'
  );
  perform private.test_fallar_si(
    has_function_privilege(
      'authenticated', 'private.leads_por_repartir_implementacion()', 'EXECUTE'
    )
      or has_function_privilege(
        'authenticated', 'private.repartir_lead_implementacion(uuid,uuid)', 'EXECUTE'
      )
      or not has_function_privilege(
        'authenticated', 'crm.leads_por_repartir()', 'EXECUTE'
      )
      or not has_function_privilege(
        'authenticated', 'crm.repartir_lead(uuid,uuid)', 'EXECUTE'
      ),
    'Las implementaciones C1 quedaron expuestas o sus fronteras sin EXECUTE'
  );
end;
$$;

select private.test_esperar_sqlstate(
  $$update crm.equipo set activo=true
    where perfil_id='10000000-0000-4000-8000-000000000014'$$,
  'P0001','El trigger permitio activar Superadmin + Vendedor'
);
select private.test_esperar_sqlstate(
  $$update public.perfiles set rol='superadmin'
    where id='10000000-0000-4000-8000-000000000016'$$,
  'P0001','El trigger permitio convertir a Superadmin un Coordinador activo'
);
update public.perfiles set activo=false
where id='10000000-0000-4000-8000-000000000016';
update public.perfiles set activo=true
where id='10000000-0000-4000-8000-000000000016';

-- Defensa en profundidad: simula una fila legacy corrupta saltando triggers
-- con autoridad de owner. Aun asi las fronteras de lectura/RPC deben fallar.
set session_replication_role = replica;
update crm.equipo set activo=true
where perfil_id in (
  '10000000-0000-4000-8000-000000000015',
  '10000000-0000-4000-8000-000000000017'
);
set session_replication_role = origin;

set role service_role;
do $$
declare v_normal jsonb; v_doble jsonb; v_invalido jsonb;
begin
  v_normal := crm.agenda_ics_feed_fn(
    '50000000-0000-4000-8000-000000000001', now()
  );
  v_doble := crm.agenda_ics_feed_fn(
    '50000000-0000-4000-8000-000000000002', now()
  );
  v_invalido := crm.agenda_ics_feed_fn(
    '50000000-0000-4000-8000-000000000003', now()
  );
  if (v_normal->>'autorizado')::boolean is distinct from true
     or (v_doble->>'autorizado')::boolean is distinct from true
     or (v_invalido->>'autorizado')::boolean is distinct from false then
    raise exception 'El feed ICS no respeto el rol CRM efectivo';
  end if;
end;
$$;
reset role;

set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000015';
set role authenticated;
do $$
declare v jsonb;
begin
  v := crm.mi_acceso_fn();
  perform private.test_fallar_si(
    v->>'estado' <> 'administrador_roles'
      or v ? 'rol_crm'
      or private.rol_crm((select auth.uid())) is not null
      or private.puede_acceder_crm(),
    'Superadmin + Coordinador obtuvo un rol operativo efectivo'
  );
end;
$$;
select private.test_esperar_sqlstate(
  $$select * from crm.leads_por_repartir()$$,
  '42501','Superadmin + Coordinador leyo la cola'
);
select private.test_esperar_sqlstate(
  $$select * from crm.supervisores_para_reparto()$$,
  '42501','Superadmin + Coordinador enumero supervisores'
);
select private.test_esperar_sqlstate(
  $$select crm.repartir_lead(
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000004')$$,
  '42501','Superadmin + Coordinador repartio un lead'
);
select private.test_esperar_sqlstate(
  $$select crm.descartar_lead(
    '20000000-0000-4000-8000-000000000001','otro',null)$$,
  '42501','Superadmin + Coordinador descarto un lead'
);
select private.test_esperar_sqlstate(
  $$select crm.deshacer_descarte(
    '20000000-0000-4000-8000-000000000001')$$,
  '42501','Superadmin + Coordinador deshizo un descarte'
);
select private.test_esperar_sqlstate(
  $$select * from crm.leads_descartados()$$,
  '42501','Superadmin + Coordinador leyo descartes'
);

reset role;
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000016';
set role authenticated;
do $$
declare v jsonb;
begin
  v := crm.mi_acceso_fn();
  perform private.test_fallar_si(
    v->>'estado' <> 'miembro' or v->>'rol_crm' <> 'coordinador',
    'Coordinador ordinario perdio su membresia operativa'
  );
  perform * from crm.leads_por_repartir();
  perform * from crm.leads_descartados();
  perform crm.descartar_lead(
    '20000000-0000-4000-8000-000000000001','otro',null
  );
  perform crm.deshacer_descarte('20000000-0000-4000-8000-000000000001');
  if (select count(*) from crm.supervisores_para_reparto()
      where perfil_id='10000000-0000-4000-8000-000000000004')<>1
     or (select count(*) from crm.supervisores_para_reparto()
      where perfil_id='10000000-0000-4000-8000-000000000017')<>0 then
    raise exception 'El roster de reparto no uso roles efectivos';
  end if;
  perform crm.repartir_lead(
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000004'
  );
end;
$$;
select private.test_esperar_sqlstate(
  $$select crm.repartir_lead(
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000017')$$,
  '22023','Superadmin + Supervisor fue aceptado como destino'
);

reset role;
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
set role authenticated;
do $$
begin
  if exists (
    select 1 from crm.equipo_visible_fn()
    where perfil_id in (
      '10000000-0000-4000-8000-000000000015',
      '10000000-0000-4000-8000-000000000017'
    )
  ) or not exists (
    select 1 from crm.equipo_visible_fn()
    where perfil_id='10000000-0000-4000-8000-000000000006'
  ) then
    raise exception 'equipo_visible_fn no filtro por rol efectivo';
  end if;
end;
$$;

reset role;
set session_replication_role = replica;
update crm.equipo set activo=false
where perfil_id in (
  '10000000-0000-4000-8000-000000000015',
  '10000000-0000-4000-8000-000000000017'
);
set session_replication_role = origin;

set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
set role authenticated;

select private.test_esperar_sqlstate(
  $$update crm.equipo set activo=false where perfil_id='10000000-0000-4000-8000-000000000007'$$,
  '42501', 'Gerencia obtuvo UPDATE directo sobre equipo'
);

do $$
declare v jsonb;
begin
  v := crm.mi_acceso_fn();
  perform private.test_fallar_si(
    not (v->>'puede_listar_usuarios')::boolean
      or not (v->>'puede_administrar_usuarios')::boolean
      or not (v->>'puede_organizar_jerarquia')::boolean
      or (v->>'puede_administrar_roles')::boolean,
    'Capacidades de Gerencia incorrectas'
  );
end;
$$;

-- Gerencia ve los campos operativos seguros y crea el candidato pendiente.
do $$
declare v record;
begin
  select * into v from crm.usuarios_administrables_fn('Vendedor Uno',50,0)
  where perfil_id='10000000-0000-4000-8000-000000000006';
  perform private.test_fallar_si(
    v.correo is null or v.documento is null or v.supervisor_id is null
      or v.version_perfil is null,
    'Gerencia recibio una proyeccion incompleta'
  );
end;
$$;

select crm.registrar_candidato_usuario_fn(
  '10000000-0000-4000-8000-000000000009',
  'nuevo@test.invalid','Nuevo Candidato','DNI','10000009',
  '+51900000009','+51900000009','Asesor',
  'a0000000-0000-4000-8000-000000000001'
);

do $$
declare v jsonb;
begin
  v := crm.registrar_candidato_usuario_fn(
    '10000000-0000-4000-8000-000000000009',
    'nuevo@test.invalid','Nuevo Candidato','DNI','10000009',
    '+51900000009','+51900000009','Asesor',
    'a0000000-0000-4000-8000-000000000001'
  );
  perform private.test_fallar_si(
    (v->>'idempotente')::boolean is not true,
    'El retry del alta no fue idempotente'
  );
end;
$$;

reset role;
do $$
begin
  perform private.test_fallar_si(
    not exists (
      select 1 from public.perfiles p
      where p.id='10000000-0000-4000-8000-000000000009'
        and p.rol='comercial' and p.activo
    ) or exists (
      select 1 from crm.equipo e
      where e.perfil_id='10000000-0000-4000-8000-000000000009'
    ),
    'El alta no quedo pendiente de rol'
  );
  perform private.test_fallar_si(
    exists (
      select 1 from crm.usuario_eventos ue
      where lower(ue.detalle::text) ~ '(nuevo@test|10000009|password|token|secret)'
    ),
    'La auditoria contiene PII o secretos'
  );
end;
$$;

-- Superadmin Portal puro: solo lista minima y administra rol.
reset role;
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';
set role authenticated;

do $$
declare v_acceso jsonb; v record;
begin
  v_acceso := crm.mi_acceso_fn();
  perform private.test_fallar_si(
    v_acceso->>'estado' <> 'administrador_roles'
      or v_acceso ? 'rol_crm'
      or v_acceso->>'rol_portal' <> 'superadmin'
      or private.es_lector_global()
      or private.puede_acceder_crm()
      or not (v_acceso->>'puede_listar_usuarios')::boolean
      or not (v_acceso->>'puede_administrar_roles')::boolean
      or (v_acceso->>'puede_administrar_usuarios')::boolean
      or (v_acceso->>'puede_organizar_jerarquia')::boolean,
    'Superadmin puro recibio capacidades incorrectas'
  );

  select * into v from crm.usuarios_administrables_fn('Nuevo Candidato',50,0)
  where perfil_id='10000000-0000-4000-8000-000000000009';
  perform private.test_fallar_si(
    v.nombre_completo is null or v.estado <> 'pendiente_rol'
      or v.correo is not null or v.documento is not null
      or v.telefono is not null or v.supervisor_id is not null
      or v.version_perfil is not null,
    'La lista minima de Superadmin filtro mal sus campos'
  );
end;
$$;

-- Una membresia inactiva veta toda la sesion, tambien para Superadmin. Las
-- combinaciones no-Gerencia nunca se activan ni operan como fallback.
reset role;
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000014';
set role authenticated;
do $$
declare v_acceso jsonb;
begin
  v_acceso := crm.mi_acceso_fn();
  perform private.test_fallar_si(
    v_acceso->>'estado' <> 'revocado'
      or v_acceso ? 'rol_crm'
      or private.rol_crm((select auth.uid())) is not null
      or private.es_lector_global()
      or private.puede_acceder_crm()
      or (v_acceso->>'puede_listar_usuarios')::boolean
      or (v_acceso->>'puede_administrar_roles')::boolean,
    'Superadmin + Vendedor inactivo recibio alguna capacidad CRM'
  );
end;
$$;

reset role;
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';
set role authenticated;

select private.test_esperar_sqlstate(
  $$select crm.actualizar_usuario_administrable_fn(
    '10000000-0000-4000-8000-000000000009','Intento','DNI','10000009',
    null,null,null,(select actualizado_en from public.perfiles where id='10000000-0000-4000-8000-000000000009'),
    'a0000000-0000-4000-8000-000000000002')$$,
  '42501', 'Superadmin pudo editar datos'
);

select private.test_esperar_sqlstate(
  $$select crm.asignar_rol_usuario_fn(
    '10000000-0000-4000-8000-000000000002','vendedor',null,
    'a0000000-0000-4000-8000-000000000026')$$,
  'P0001','Superadmin pudo asignarse una membresia CRM no-Gerencia'
);

select crm.asignar_rol_usuario_fn(
  '10000000-0000-4000-8000-000000000009','vendedor',null,
  'a0000000-0000-4000-8000-000000000003'
);

do $$
declare v jsonb;
begin
  v := crm.asignar_rol_usuario_fn(
    '10000000-0000-4000-8000-000000000009','vendedor',null,
    'a0000000-0000-4000-8000-000000000003'
  );
  perform private.test_fallar_si(
    (v->>'idempotente')::boolean is not true,
    'El retry de asignacion de rol no fue idempotente'
  );
end;
$$;

do $$
begin
  perform private.test_fallar_si(
    not exists (
      select 1 from crm.equipo e
      where e.perfil_id='10000000-0000-4000-8000-000000000009'
        and e.rol_crm='vendedor' and e.activo=false and e.supervisor_id is null
    ),
    'La primera asignacion de rol no creo membresia inactiva/neutra'
  );
end;
$$;

select private.test_esperar_sqlstate(
  $$select crm.actualizar_jerarquia_usuario_fn(
    '10000000-0000-4000-8000-000000000009',null,
    (select actualizado_en from crm.equipo where perfil_id='10000000-0000-4000-8000-000000000009'),
    'a0000000-0000-4000-8000-000000000004')$$,
  '42501', 'Superadmin pudo organizar jerarquia'
);
select private.test_esperar_sqlstate(
  $$select crm.fijar_membresia_activa_fn(
    '10000000-0000-4000-8000-000000000009',true,null,
    (select actualizado_en from crm.equipo where perfil_id='10000000-0000-4000-8000-000000000009'),
    'a0000000-0000-4000-8000-000000000005')$$,
  '42501', 'Superadmin pudo activar membresia'
);

-- Gerencia organiza, activa, edita y queda protegida por version optimista.
reset role;
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
set role authenticated;

select private.test_esperar_sqlstate(
  $$select crm.fijar_membresia_activa_fn(
    '10000000-0000-4000-8000-000000000014',true,null,
    (select actualizado_en from crm.equipo
      where perfil_id='10000000-0000-4000-8000-000000000014'),
    'a0000000-0000-4000-8000-000000000027')$$,
  'P0001','Gerencia activo a un Superadmin con rol CRM no-Gerencia'
);

-- El alta deliberadamente pasa por rol -> jerarquia -> activacion. Un vendedor
-- inactivo puede estar temporalmente sin superior; uno activo, nunca.
select private.test_esperar_sqlstate(
  $$select crm.fijar_membresia_activa_fn(
    '10000000-0000-4000-8000-000000000009',true,null,
    (select actualizado_en from crm.equipo where perfil_id='10000000-0000-4000-8000-000000000009'),
    'a0000000-0000-4000-8000-000000000023')$$,
  'P0001','Se activo un vendedor sin Supervisor'
);

select crm.actualizar_jerarquia_usuario_fn(
  '10000000-0000-4000-8000-000000000009',
  '10000000-0000-4000-8000-000000000004',
  (select actualizado_en from crm.equipo where perfil_id='10000000-0000-4000-8000-000000000009'),
  'a0000000-0000-4000-8000-000000000006'
);
do $$
declare v jsonb;
begin
  v := crm.actualizar_jerarquia_usuario_fn(
    '10000000-0000-4000-8000-000000000009',
    '10000000-0000-4000-8000-000000000004',
    (select actualizado_en from crm.equipo where perfil_id='10000000-0000-4000-8000-000000000009'),
    'a0000000-0000-4000-8000-000000000006'
  );
  perform private.test_fallar_si(
    (v->>'idempotente')::boolean is not true,
    'El retry de jerarquia no fue idempotente'
  );
end;
$$;
select crm.fijar_membresia_activa_fn(
  '10000000-0000-4000-8000-000000000009',true,null,
  (select actualizado_en from crm.equipo where perfil_id='10000000-0000-4000-8000-000000000009'),
  'a0000000-0000-4000-8000-000000000007'
);
do $$
declare v jsonb;
begin
  v := crm.fijar_membresia_activa_fn(
    '10000000-0000-4000-8000-000000000009',true,null,
    (select actualizado_en from crm.equipo where perfil_id='10000000-0000-4000-8000-000000000009'),
    'a0000000-0000-4000-8000-000000000007'
  );
  perform private.test_fallar_si(
    (v->>'idempotente')::boolean is not true,
    'El retry de activacion no fue idempotente'
  );
end;
$$;

select private.test_esperar_sqlstate(
  $$select crm.actualizar_jerarquia_usuario_fn(
    '10000000-0000-4000-8000-000000000009',
    '10000000-0000-4000-8000-000000000001',
    (select actualizado_en from crm.equipo where perfil_id='10000000-0000-4000-8000-000000000009'),
    'a0000000-0000-4000-8000-000000000024')$$,
  'P0001','Se asigno Gerencia directamente como superior de un vendedor activo'
);

do $$
declare v_vieja timestamptz; v_nueva timestamptz; v_retry jsonb;
begin
  select actualizado_en into v_vieja from public.perfiles
  where id='10000000-0000-4000-8000-000000000009';
  perform crm.actualizar_usuario_administrable_fn(
    '10000000-0000-4000-8000-000000000009','Nuevo Candidato Editado',
    'DNI','10000009','+51999999999',null,'Ejecutivo',v_vieja,
    'a0000000-0000-4000-8000-000000000008'
  );
  select actualizado_en into v_nueva from public.perfiles
  where id='10000000-0000-4000-8000-000000000009';
  perform private.test_fallar_si(v_nueva <= v_vieja, 'La edicion no avanzo version');
  v_retry := crm.actualizar_usuario_administrable_fn(
    '10000000-0000-4000-8000-000000000009','Nuevo Candidato Editado',
    'DNI','10000009','+51999999999',null,'Ejecutivo',v_vieja,
    'a0000000-0000-4000-8000-000000000008'
  );
  perform private.test_fallar_si(
    (v_retry->>'idempotente')::boolean is not true,
    'El retry de edicion no fue idempotente'
  );
  perform private.test_esperar_sqlstate(
    format($sql$select crm.actualizar_usuario_administrable_fn(
      '10000000-0000-4000-8000-000000000009','Stale','DNI','10000009',
      null,null,null,%L::timestamptz,'a0000000-0000-4000-8000-000000000009')$sql$, v_vieja),
    '40001','Una version obsoleta pudo sobrescribir el perfil'
  );
end;
$$;

-- Supervisor puede estar en raiz o depender de Supervisor/Gerencia. Aqui sup2
-- depende de Gerencia y sup1 de sup2; el inverso debe fallar por ciclo.
select crm.actualizar_jerarquia_usuario_fn(
  '10000000-0000-4000-8000-000000000005',
  '10000000-0000-4000-8000-000000000001',
  (select actualizado_en from crm.equipo where perfil_id='10000000-0000-4000-8000-000000000005'),
  'a0000000-0000-4000-8000-000000000025'
);
select crm.actualizar_jerarquia_usuario_fn(
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000005',
  (select actualizado_en from crm.equipo where perfil_id='10000000-0000-4000-8000-000000000004'),
  'a0000000-0000-4000-8000-000000000010'
);
select private.test_esperar_sqlstate(
  $$select crm.actualizar_jerarquia_usuario_fn(
    '10000000-0000-4000-8000-000000000005',
    '10000000-0000-4000-8000-000000000004',
    (select actualizado_en from crm.equipo where perfil_id='10000000-0000-4000-8000-000000000005'),
    'a0000000-0000-4000-8000-000000000011')$$,
  'P0001','Se acepto un ciclo jerarquico'
);

-- Handoff de vendedor: sin reemplazo aborta; con reemplazo mueve todo y rota ICS.
do $$
declare v jsonb;
begin
  v := crm.impacto_desactivacion_usuario_fn('10000000-0000-4000-8000-000000000006');
  perform private.test_fallar_si(
    (v->>'leads_abiertos')::int <> 1
      or (v->>'tareas_pendientes')::int <> 1
      or (v->>'clientes_activos')::int <> 1
      or not (v->>'requiere_reemplazo')::boolean,
    'Impacto de vendedor incorrecto'
  );
end;
$$;
select private.test_esperar_sqlstate(
  $$select crm.fijar_membresia_activa_fn(
    '10000000-0000-4000-8000-000000000006',false,null,
    (select actualizado_en from crm.equipo where perfil_id='10000000-0000-4000-8000-000000000006'),
    'a0000000-0000-4000-8000-000000000012')$$,
  'P0001','La baja con dependencias entro sin reemplazo'
);

select crm.fijar_membresia_activa_fn(
  '10000000-0000-4000-8000-000000000006',false,
  '10000000-0000-4000-8000-000000000007',
  (select actualizado_en from crm.equipo where perfil_id='10000000-0000-4000-8000-000000000006'),
  'a0000000-0000-4000-8000-000000000013'
);

do $$
begin
  perform private.test_fallar_si(
    (select activo from crm.equipo where perfil_id='10000000-0000-4000-8000-000000000006')
      or (select vendedor_id from crm.leads where id='20000000-0000-4000-8000-000000000001')
        <> '10000000-0000-4000-8000-000000000007'
      or (select vendedor_id from crm.tareas where id='30000000-0000-4000-8000-000000000001')
        <> '10000000-0000-4000-8000-000000000007'
      or (select asesor_perfil_id from public.perfiles where id='10000000-0000-4000-8000-000000000008')
        <> '10000000-0000-4000-8000-000000000007'
      or (select token from crm.agenda_ics where perfil_id='10000000-0000-4000-8000-000000000006')
        = '50000000-0000-4000-8000-000000000001',
    'El handoff de vendedor no fue atomico/completo'
  );
end;
$$;

-- Handoff de supervisor transfiere hijos, bandeja y tarea al supervisor par.
select crm.fijar_membresia_activa_fn(
  '10000000-0000-4000-8000-000000000004',false,
  '10000000-0000-4000-8000-000000000005',
  (select actualizado_en from crm.equipo where perfil_id='10000000-0000-4000-8000-000000000004'),
  'a0000000-0000-4000-8000-000000000014'
);

do $$
begin
  perform private.test_fallar_si(
    exists (select 1 from crm.equipo e where e.supervisor_id='10000000-0000-4000-8000-000000000004' and e.activo)
      or (select asignado_supervisor_id from crm.leads where id='20000000-0000-4000-8000-000000000002')
        <> '10000000-0000-4000-8000-000000000005'
      or (select asignado_supervisor_id from crm.tareas where id='30000000-0000-4000-8000-000000000002')
        <> '10000000-0000-4000-8000-000000000005',
    'El handoff de supervisor dejo dependencias'
  );
end;
$$;

select private.test_esperar_sqlstate(
  $$select crm.fijar_membresia_activa_fn(
    '10000000-0000-4000-8000-000000000001',false,null,
    (select actualizado_en from crm.equipo where perfil_id='10000000-0000-4000-8000-000000000001'),
    'a0000000-0000-4000-8000-000000000015')$$,
  'P0001','Gerencia pudo auto-desactivarse'
);
select private.test_esperar_sqlstate(
  $$select crm.fijar_membresia_activa_fn(
    '10000000-0000-4000-8000-000000000011',true,null,
    (select actualizado_en from crm.equipo where perfil_id='10000000-0000-4000-8000-000000000011'),
    'a0000000-0000-4000-8000-000000000016')$$,
  'P0001','Gerencia activo un perfil suspendido en Portal'
);

-- Superadmin no puede cambiar a Directorio mientras queden hijos activos.
reset role;
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';
set role authenticated;
select private.test_esperar_sqlstate(
  $$select crm.asignar_rol_usuario_fn(
    '10000000-0000-4000-8000-000000000005','directorio',
    (select actualizado_en from crm.equipo where perfil_id='10000000-0000-4000-8000-000000000005'),
    'a0000000-0000-4000-8000-000000000019')$$,
  'P0001','El cambio de rol dejo subordinados incompatibles'
);

-- Directorio CRM explicito: rol asignado por Superadmin, estado por Gerencia.
select crm.asignar_rol_usuario_fn(
  '10000000-0000-4000-8000-000000000010','directorio',null,
  'a0000000-0000-4000-8000-000000000020'
);
reset role;
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
set role authenticated;
select crm.fijar_membresia_activa_fn(
  '10000000-0000-4000-8000-000000000010',true,null,
  (select actualizado_en from crm.equipo where perfil_id='10000000-0000-4000-8000-000000000010'),
  'a0000000-0000-4000-8000-000000000022'
);

reset role;
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000010';
set role authenticated;
do $$
declare
  v jsonb;
  v_fila record;
  v_coincidencias integer;
begin
  v := crm.mi_acceso_fn();
  perform private.test_fallar_si(
    v->>'estado' <> 'miembro' or v->>'rol_crm' <> 'directorio'
      or not private.es_lector_global()
      or not (v->>'puede_listar_usuarios')::boolean
      or (v->>'puede_administrar_usuarios')::boolean
      or (v->>'puede_organizar_jerarquia')::boolean
      or (v->>'puede_administrar_roles')::boolean,
    'Directorio CRM explicito no quedo lector redactado sin administracion'
  );

  select * into v_fila
  from crm.usuarios_administrables_fn(null,50,0)
  where perfil_id='10000000-0000-4000-8000-000000000007';
  perform private.test_fallar_si(
    v_fila.perfil_id is null
      or v_fila.nombre_completo <> 'Usuario CRM · 00000007'
      or v_fila.nombre_completo = 'Vendedor Dos'
      or v_fila.tipo_documento is not null
      or v_fila.documento is not null
      or v_fila.correo is not null
      or v_fila.telefono is not null
      or v_fila.whatsapp is not null
      or v_fila.cargo is not null
      or v_fila.supervisor_id is not null
      or v_fila.version_perfil is not null
      or v_fila.version_equipo is not null
      or v_fila.rol_crm <> 'vendedor'
      or v_fila.estado <> 'activo',
    'Directorio CRM recibio PII/jerarquia/version o perdio rol/estado seguro'
  );

  select count(*) into v_coincidencias
  from crm.usuarios_administrables_fn('Vendedor Dos',50,0);
  perform private.test_fallar_si(
    v_coincidencias <> 0,
    'La busqueda de Directorio filtro por el nombre real oculto'
  );
  select count(*) into v_coincidencias
  from crm.usuarios_administrables_fn('vend2@test.invalid',50,0);
  perform private.test_fallar_si(
    v_coincidencias <> 0,
    'La busqueda de Directorio filtro por correo oculto'
  );
  select count(*) into v_coincidencias
  from crm.usuarios_administrables_fn('vendedor',50,0)
  where perfil_id='10000000-0000-4000-8000-000000000007';
  perform private.test_fallar_si(
    v_coincidencias <> 1,
    'Directorio no pudo filtrar por el rol seguro visible'
  );
end;
$$;

select private.test_esperar_sqlstate(
  $$select crm.buscar_candidato_por_correo_fn('vend2@test.invalid')$$,
  '42501','Directorio pudo buscar candidatos por correo'
);
select private.test_esperar_sqlstate(
  $$select crm.registrar_candidato_usuario_fn(
    '10000000-0000-4000-8000-000000000014','otro@test.invalid','Otro',
    'DNI','10000014',null,null,null,
    'b0000000-0000-4000-8000-000000000001')$$,
  '42501','Directorio pudo crear candidatos'
);
select private.test_esperar_sqlstate(
  $$select crm.actualizar_usuario_administrable_fn(
    '10000000-0000-4000-8000-000000000007','Intento','DNI','10000007',
    null,null,null,'2026-08-07T00:00:00Z'::timestamptz,
    'b0000000-0000-4000-8000-000000000002')$$,
  '42501','Directorio pudo editar datos'
);
select private.test_esperar_sqlstate(
  $$select crm.asignar_rol_usuario_fn(
    '10000000-0000-4000-8000-000000000007','supervisor',
    '2026-08-07T00:00:00Z'::timestamptz,
    'b0000000-0000-4000-8000-000000000003')$$,
  '42501','Directorio pudo cambiar roles'
);
select private.test_esperar_sqlstate(
  $$select crm.actualizar_jerarquia_usuario_fn(
    '10000000-0000-4000-8000-000000000007',null,
    '2026-08-07T00:00:00Z'::timestamptz,
    'b0000000-0000-4000-8000-000000000004')$$,
  '42501','Directorio pudo cambiar jerarquia'
);
select private.test_esperar_sqlstate(
  $$select crm.impacto_desactivacion_usuario_fn(
    '10000000-0000-4000-8000-000000000007')$$,
  '42501','Directorio pudo evaluar una baja'
);
select private.test_esperar_sqlstate(
  $$select crm.fijar_membresia_activa_fn(
    '10000000-0000-4000-8000-000000000007',false,null,
    '2026-08-07T00:00:00Z'::timestamptz,
    'b0000000-0000-4000-8000-000000000005')$$,
  '42501','Directorio pudo cambiar membresia'
);
select private.test_esperar_sqlstate(
  $$update crm.equipo set activo=false
    where perfil_id='10000000-0000-4000-8000-000000000007'$$,
  '42501','Directorio obtuvo UPDATE directo sobre equipo'
);

-- Admin Portal sigue fuera: no se confunde lectura global con Directorio.
reset role;
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';
set role authenticated;
do $$
declare v_acceso jsonb;
begin
  v_acceso := crm.mi_acceso_fn();
  perform private.test_fallar_si(
    v_acceso->>'estado' <> 'no_enrolado'
      or private.es_lector_global()
      or private.puede_acceder_crm()
      or (v_acceso->>'puede_listar_usuarios')::boolean
      or (v_acceso->>'puede_administrar_usuarios')::boolean
      or (v_acceso->>'puede_organizar_jerarquia')::boolean
      or (v_acceso->>'puede_administrar_roles')::boolean,
    'Admin Portal recibio acceso o capacidades CRM'
  );
end;
$$;
select private.test_esperar_sqlstate(
  $$select * from crm.usuarios_administrables_fn(null,50,0)$$,
  '42501','Admin Portal pudo enumerar usuarios CRM'
);
select private.test_esperar_sqlstate(
  $$select crm.asignar_rol_usuario_fn(
    '10000000-0000-4000-8000-000000000007','supervisor',
    '2026-08-07T00:00:00Z'::timestamptz,
    'b0000000-0000-4000-8000-000000000009')$$,
  '42501','Admin Portal pudo cambiar roles CRM'
);

-- Directorio Portal sin membresia tambien es Directorio real, pero conserva
-- exactamente la misma lectura seudonimizada y cero mutaciones.
reset role;
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000013';
set role authenticated;
do $$
declare
  v_acceso jsonb;
  v_fila record;
begin
  v_acceso := crm.mi_acceso_fn();
  perform private.test_fallar_si(
    v_acceso->>'estado' <> 'global'
      or v_acceso->>'rol_crm' <> 'directorio'
      or not private.es_lector_global()
      or not private.puede_acceder_crm()
      or not (v_acceso->>'puede_listar_usuarios')::boolean
      or (v_acceso->>'puede_administrar_usuarios')::boolean
      or (v_acceso->>'puede_organizar_jerarquia')::boolean
      or (v_acceso->>'puede_administrar_roles')::boolean,
    'Directorio Portal recibio capacidades incorrectas'
  );

  select * into v_fila
  from crm.usuarios_administrables_fn(null,50,0)
  where perfil_id='10000000-0000-4000-8000-000000000007';
  perform private.test_fallar_si(
    v_fila.nombre_completo <> 'Usuario CRM · 00000007'
      or v_fila.correo is not null
      or v_fila.documento is not null
      or v_fila.supervisor_id is not null
      or v_fila.version_equipo is not null,
    'Directorio Portal no recibio la proyeccion seudonimizada'
  );
end;
$$;
select private.test_esperar_sqlstate(
  $$select crm.asignar_rol_usuario_fn(
    '10000000-0000-4000-8000-000000000007','supervisor',
    '2026-08-07T00:00:00Z'::timestamptz,
    'b0000000-0000-4000-8000-000000000007')$$,
  '42501','Directorio Portal pudo cambiar roles'
);
-- Un Analista ya creado por el Portal reutiliza su identidad Auth en CRM. La
-- secuencia preserva las tres autoridades: Gerencia prepara/organiza,
-- Superadmin asigna el rol y Gerencia activa la membresia.
reset role;
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
set role authenticated;

do $$
declare
  v_candidato uuid;
  v_fila record;
begin
  v_candidato := crm.buscar_candidato_por_correo_fn(
    'analista-pendiente@test.invalid'
  );
  perform private.test_fallar_si(
    v_candidato is distinct from '10000000-0000-4000-8000-000000000018'::uuid,
    'Gerencia no encontro al Analista Portal existente como candidato CRM'
  );

  select * into v_fila
  from crm.usuarios_administrables_fn('Analista Portal Pendiente',50,0)
  where perfil_id='10000000-0000-4000-8000-000000000018';
  perform private.test_fallar_si(
    v_fila.perfil_id is distinct from '10000000-0000-4000-8000-000000000018'::uuid
      or v_fila.tipo_cuenta <> 'compartida_portal'
      or v_fila.estado <> 'pendiente_rol'
      or v_fila.rol_crm is not null
      or v_fila.correo <> 'analista-pendiente@test.invalid'
      or v_fila.documento <> '10000018'
      or v_fila.version_perfil is null,
    'El Analista Portal pendiente no tuvo la proyeccion CRM esperada'
  );
end;
$$;

select private.test_esperar_sqlstate(
  $$select crm.buscar_candidato_por_correo_fn('correo-sin-dominio')$$,
  'P0001','El buscador acepto un correo invalido'
);

select crm.actualizar_usuario_administrable_fn(
  '10000000-0000-4000-8000-000000000018',
  'Analista Portal Pendiente Actualizado','DNI','10000018',
  '+51900000018','+51900000018','Asesora Portal',
  (select actualizado_en from public.perfiles
   where id='10000000-0000-4000-8000-000000000018'),
  'c0000000-0000-4000-8000-000000000001'
);

do $$
declare
  v jsonb;
begin
  v := crm.registrar_vendedor_usuario_fn(
    '10000000-0000-4000-8000-000000000018',
    'analista-pendiente@test.invalid',
    'Analista Portal Pendiente Actualizado','DNI','10000018',
    '+51900000018','+51900000018','Asesora Portal',
    '10000000-0000-4000-8000-000000000005',
    'c0000000-0000-4000-8000-000000000006'
  );
  perform private.test_fallar_si(
    v->>'estado' <> 'candidato_existente'
      or exists (
        select 1 from crm.equipo
        where perfil_id='10000000-0000-4000-8000-000000000018'
      ),
    'El alta directa modifico una identidad pendiente compartida con el Portal'
  );
end;
$$;

reset role;
do $$
begin
  perform private.test_fallar_si(
    not exists (
      select 1 from public.perfiles p
      where p.id='10000000-0000-4000-8000-000000000018'
        and p.rol='analista'
        and p.nombre_completo='Analista Portal Pendiente Actualizado'
        and p.cargo='Asesora Portal'
    ) or exists (
      select 1 from crm.equipo e
      where e.perfil_id='10000000-0000-4000-8000-000000000018'
    ) or exists (
      select 1 from crm.usuario_eventos ue
      where ue.actor_id='10000000-0000-4000-8000-000000000001'
        and ue.idempotencia='c0000000-0000-4000-8000-000000000006'
    ),
    'La edicion CRM cambio el rol Portal o creo membresia antes de tiempo'
  );
end;
$$;

set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';
set role authenticated;
select private.test_esperar_sqlstate(
  $$select crm.asignar_rol_usuario_fn(
    '10000000-0000-4000-8000-000000000008','vendedor',null,
    'c0000000-0000-4000-8000-000000000002')$$,
  'P0001','Superadmin admitio a un Cliente Portal como candidato CRM'
);
select crm.asignar_rol_usuario_fn(
  '10000000-0000-4000-8000-000000000018','vendedor',null,
  'c0000000-0000-4000-8000-000000000003'
);

reset role;
do $$
begin
  perform private.test_fallar_si(
    not exists (
      select 1 from crm.equipo e
      where e.perfil_id='10000000-0000-4000-8000-000000000018'
        and e.rol_crm='vendedor' and e.activo=false and e.supervisor_id is null
    ),
    'Superadmin no asigno al Analista Portal una membresia CRM neutra'
  );
end;
$$;

set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
set role authenticated;
select crm.actualizar_jerarquia_usuario_fn(
  '10000000-0000-4000-8000-000000000018',
  '10000000-0000-4000-8000-000000000005',
  (select actualizado_en from crm.equipo
   where perfil_id='10000000-0000-4000-8000-000000000018'),
  'c0000000-0000-4000-8000-000000000004'
);
select crm.fijar_membresia_activa_fn(
  '10000000-0000-4000-8000-000000000018',true,null,
  (select actualizado_en from crm.equipo
   where perfil_id='10000000-0000-4000-8000-000000000018'),
  'c0000000-0000-4000-8000-000000000005'
);

reset role;
do $$
begin
  perform private.test_fallar_si(
    not exists (
      select 1 from crm.equipo e
      where e.perfil_id='10000000-0000-4000-8000-000000000018'
        and e.rol_crm='vendedor'
        and e.supervisor_id='10000000-0000-4000-8000-000000000005'
        and e.activo
    ),
    'El flujo Analista Portal a Vendedor CRM no termino activo y jerarquizado'
  );
end;
$$;

reset role;
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000012';
set role authenticated;
do $$
declare v jsonb;
begin
  v := crm.mi_acceso_fn();
  perform private.test_fallar_si(
    v->>'estado' <> 'miembro'
      or v->>'rol_crm' <> 'gerencia'
      or v->>'rol_portal' <> 'superadmin'
      or private.es_lector_global()
      or not private.puede_acceder_crm()
      or not (v->>'puede_listar_usuarios')::boolean
      or not (v->>'puede_administrar_usuarios')::boolean
      or not (v->>'puede_organizar_jerarquia')::boolean
      or not (v->>'puede_administrar_roles')::boolean,
    'La identidad que es Gerencia y Superadmin no sumo capacidades'
  );
end;
$$;

-- Gerencia puede completar de una vez SOLO un Vendedor exclusivo del CRM.
-- El rol no viaja como parametro y el Supervisor activo es obligatorio.
reset role;
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
set role authenticated;

-- Caso real de Alan: Auth y perfil exclusivo CRM ya existen, pero todavia no
-- hay fila en crm.equipo. Una discrepancia documental aborta; el documento
-- exacto completa rol, Supervisor y activacion sin recrear la identidad.
select private.test_esperar_sqlstate(
  $$select crm.registrar_vendedor_usuario_fn(
    '10000000-0000-4000-8000-000000000021',
    'alan-pendiente@test.invalid','Alan Pendiente','CE','009999999',
    '+51900000021',null,null,
    '10000000-0000-4000-8000-000000000005',
    'd0000000-0000-4000-8000-000000000004')$$,
  'P0001','El alta pendiente acepto un documento distinto al de Auth/perfil'
);

do $$
declare v jsonb;
begin
  perform private.test_fallar_si(
    exists (
      select 1 from crm.equipo
      where perfil_id='10000000-0000-4000-8000-000000000021'
    ),
    'El documento divergente dejo una membresia parcial'
  );
  v := crm.registrar_vendedor_usuario_fn(
    '10000000-0000-4000-8000-000000000021',
    'alan-pendiente@test.invalid','Alan Pendiente','CE','001237707',
    '+51900000021',null,null,
    '10000000-0000-4000-8000-000000000005',
    'd0000000-0000-4000-8000-000000000005'
  );
  perform private.test_fallar_si(
    v->>'estado' <> 'activo'
      or v->>'rol_crm' <> 'vendedor'
      or v->>'supervisor_id' <> '10000000-0000-4000-8000-000000000005'
      or not (v->>'activo_crm')::boolean,
    'El caso Alan no termino activo y jerarquizado'
  );
end;
$$;

do $$
declare v jsonb;
begin
  v := crm.registrar_vendedor_usuario_fn(
    '10000000-0000-4000-8000-000000000019',
    'alta-directa@test.invalid','Alta Directa','DNI','10000019',
    null,null,'Vendedora',
    '10000000-0000-4000-8000-000000000005',
    'd0000000-0000-4000-8000-000000000001'
  );
  perform private.test_fallar_si(
    v->>'estado' <> 'activo'
      or v->>'rol_crm' <> 'vendedor'
      or (v->>'activo_crm')::boolean is not true
      or v->>'supervisor_id' <> '10000000-0000-4000-8000-000000000005',
    'El alta directa no devolvio un Vendedor activo y jerarquizado'
  );

  v := crm.registrar_vendedor_usuario_fn(
    '10000000-0000-4000-8000-000000000019',
    'alta-directa@test.invalid','Alta Directa','DNI','10000019',
    null,null,'Vendedora',
    '10000000-0000-4000-8000-000000000005',
    'd0000000-0000-4000-8000-000000000001'
  );
  perform private.test_fallar_si(
    (v->>'idempotente')::boolean is not true,
    'El retry del alta directa no fue idempotente'
  );
end;
$$;

reset role;
do $$
begin
  perform private.test_fallar_si(
    not exists (
      select 1 from public.perfiles p
      join crm.equipo e on e.perfil_id=p.id
      where p.id='10000000-0000-4000-8000-000000000019'
        and p.rol='comercial' and p.activo
        and e.rol_crm='vendedor' and e.activo
        and e.supervisor_id='10000000-0000-4000-8000-000000000005'
    ) or (select count(*) from crm.usuario_eventos
          where objetivo_id='10000000-0000-4000-8000-000000000019') <> 4
      or (select count(distinct accion) from crm.usuario_eventos
          where objetivo_id='10000000-0000-4000-8000-000000000019') <> 4,
    'El alta directa no persistio perfil y membresia correctos'
  );
  perform private.test_fallar_si(
    (select count(*) from crm.usuario_eventos
     where objetivo_id='10000000-0000-4000-8000-000000000021') <> 3,
    'El caso Alan no produjo la auditoria esperada'
  );
  perform private.test_fallar_si(
    exists (
      select 1 from crm.usuario_eventos ue
      where ue.objetivo_id='10000000-0000-4000-8000-000000000019'
        and lower(ue.detalle::text) ~
          '(alta-directa@test|10000019|password|contrase|token|secret|clave)'
    ),
    'La auditoria del alta directa contiene PII o secretos'
  );
end;
$$;

update public.perfiles set activo=false
where id='10000000-0000-4000-8000-000000000019';
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
set role authenticated;
select private.test_esperar_sqlstate(
  $$select crm.registrar_vendedor_usuario_fn(
    '10000000-0000-4000-8000-000000000019',
    'alta-directa@test.invalid','Alta Directa','DNI','10000019',
    null,null,'Vendedora','10000000-0000-4000-8000-000000000005',
    'd0000000-0000-4000-8000-000000000001')$$,
  'P0001','El retry devolvio activo para un perfil ya suspendido'
);
reset role;
update public.perfiles set activo=true
where id='10000000-0000-4000-8000-000000000019';

set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000019';
set role authenticated;
do $$
declare v jsonb;
begin
  v := crm.mi_acceso_fn();
  perform private.test_fallar_si(
    v->>'estado' <> 'miembro' or v->>'rol_crm' <> 'vendedor',
    'El Vendedor de alta directa no obtuvo acceso CRM'
  );
end;
$$;

reset role;
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';
set role authenticated;
select private.test_esperar_sqlstate(
  $$select crm.registrar_vendedor_usuario_fn(
    '10000000-0000-4000-8000-000000000019',
    'alta-directa@test.invalid','Alta Directa','DNI','10000019',
    null,null,'Vendedora','10000000-0000-4000-8000-000000000005',
    'd0000000-0000-4000-8000-000000000002')$$,
  '42501','Superadmin sin Gerencia pudo usar el alta directa'
);

reset role;
set request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
set role authenticated;
select private.test_esperar_sqlstate(
  $$select crm.registrar_vendedor_usuario_fn(
    '10000000-0000-4000-8000-000000000020',
    'supervisor-invalido@test.invalid','Supervisor Invalido','DNI','10000020',
    null,null,'Vendedora','10000000-0000-4000-8000-000000000001',
    'd0000000-0000-4000-8000-000000000003')$$,
  'P0001','Gerencia fue aceptada como Supervisor de un Vendedor'
);

reset role;
do $$
begin
  perform private.test_fallar_si(
    exists (select 1 from public.perfiles where id='10000000-0000-4000-8000-000000000020')
      or exists (select 1 from crm.equipo where perfil_id='10000000-0000-4000-8000-000000000020'),
    'El alta invalida dejo estado parcial'
  );
end;
$$;

reset role;
reset request.jwt.claim.sub;

select 'USUARIOS_JERARQUIA_TX_OK' as resultado;

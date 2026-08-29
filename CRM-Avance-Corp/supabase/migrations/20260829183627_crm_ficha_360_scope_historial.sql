-- Ficha 360 de cliente: frontera mínima de identidad y continuidad del
-- historial según la asignación actual. Esta migración es aditiva respecto de
-- 20260828210351_crm_gestion_cartera_autorizacion_integral.sql: reutiliza su
-- fuente canónica private.cliente_ids_visibles_crm() y no redefine contratos,
-- tareas, numeración, PDF ni escrituras de cartera.

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

do $preflight$
begin
  if to_regprocedure('private.cliente_ids_visibles_crm()') is null
     or to_regclass('public.perfiles') is null
     or to_regclass('crm.actividades_cliente') is null
     or to_regclass('crm.operaciones_cartera') is null then
    raise exception
      'PREFLIGHT FICHA 360: falta la autorización integral de Gestión de cartera';
  end if;

  if exists (
    select 1
    from unnest(array[
      'id', 'nombres', 'apellidos', 'nombre_completo', 'tipo_documento',
      'dni', 'correo', 'telefono', 'asesor_perfil_id', 'activo', 'creado_en',
      'rol'
    ]) as requerida(nombre)
    where not exists (
      select 1
      from information_schema.columns c
      where c.table_schema = 'public'
        and c.table_name = 'perfiles'
        and c.column_name = requerida.nombre
    )
  ) then
    raise exception
      'PREFLIGHT FICHA 360: public.perfiles no conserva la proyección requerida';
  end if;
end;
$preflight$;

-- Único punto nuevo de autorización. No reconstruye jerarquías: consume la
-- misma lista de ids que ya gobierna crm.clientes_basicos_fn y
-- crm.cliente_detalle_fn. SECURITY DEFINER es necesario porque el helper
-- canónico y public.perfiles no son superficies de lectura del navegador.
create or replace function private.puede_consultar_cliente_ficha(
  p_cliente_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select p_cliente_id is not null
    and exists (
      select 1
      from private.cliente_ids_visibles_crm() v
      where v.cliente_id = p_cliente_id
    );
$function$;

comment on function private.puede_consultar_cliente_ficha(uuid) is
  'Autoriza la Ficha 360 con la fuente canónica de alcance de Gestión de cartera.';

revoke all on function private.puede_consultar_cliente_ficha(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.puede_consultar_cliente_ficha(uuid)
  to authenticated;

create or replace function private.cliente_ficha_autorizada_fn(
  p_cliente_id uuid
)
returns table (
  id uuid,
  nombres text,
  apellidos text,
  nombre_completo text,
  tipo_documento text,
  dni text,
  correo text,
  telefono text,
  asesor_perfil_id uuid,
  activo boolean,
  creado_en timestamptz
)
language sql
stable
security definer
set search_path = ''
rows 1
as $function$
  select
    p.id,
    p.nombres,
    p.apellidos,
    p.nombre_completo,
    p.tipo_documento,
    p.dni,
    p.correo,
    p.telefono,
    p.asesor_perfil_id,
    p.activo,
    p.creado_en
  from public.perfiles p
  where p.id = p_cliente_id
    and p.rol = 'cliente'
    and private.puede_consultar_cliente_ficha(p.id);
$function$;

comment on function private.cliente_ficha_autorizada_fn(uuid) is
  'Proyección mínima de identidad y contacto de la Ficha 360. No devuelve domicilio, banca ni autoría.';

revoke all on function private.cliente_ficha_autorizada_fn(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.cliente_ficha_autorizada_fn(uuid)
  to authenticated;

-- La función expuesta conserva SECURITY INVOKER. El único salto privilegiado
-- vive en private, con search_path vacío y comprobación del auth.uid() efectivo
-- a través de la fuente canónica de alcance.
create or replace function crm.cliente_ficha_fn(
  p_cliente_id uuid
)
returns table (
  id uuid,
  nombres text,
  apellidos text,
  nombre_completo text,
  tipo_documento text,
  dni text,
  correo text,
  telefono text,
  asesor_perfil_id uuid,
  activo boolean,
  creado_en timestamptz
)
language sql
stable
security invoker
set search_path = ''
rows 1
as $function$
  select *
  from private.cliente_ficha_autorizada_fn(p_cliente_id);
$function$;

comment on function crm.cliente_ficha_fn(uuid) is
  'Ficha comercial mínima de un cliente visible para el actor actual. No expone domicilio, banca ni autoría.';

revoke all on function crm.cliente_ficha_fn(uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.cliente_ficha_fn(uuid)
  to authenticated;

-- Historial y movimientos siguen al cliente, no a la persona que registró el
-- hecho. Una reasignación revoca la lectura anterior y habilita el nuevo ámbito
-- en la siguiente sentencia.
drop policy if exists actividades_cliente_select on crm.actividades_cliente;
create policy actividades_cliente_select on crm.actividades_cliente
  for select to authenticated
  using ((select private.puede_consultar_cliente_ficha(cliente_id)));

comment on policy actividades_cliente_select on crm.actividades_cliente is
  'El historial de la Ficha 360 sigue la asignación actual del cliente.';

drop policy if exists operaciones_cartera_select on crm.operaciones_cartera;
create policy operaciones_cartera_select on crm.operaciones_cartera
  for select to authenticated
  using ((select private.puede_consultar_cliente_ficha(cliente_id)));

comment on policy operaciones_cartera_select on crm.operaciones_cartera is
  'Renovaciones y aumentos siguen la asignación actual del cliente; la atribución histórica no concede lectura.';

-- La reasignación es un hecho de la relación comercial. El responsable puede
-- quedar nulo solamente en ese tipo de actividad cuando el cambio provenga de
-- sistema o de un actor que no pertenece al equipo CRM.
alter table crm.actividades_cliente
  alter column vendedor_id drop not null;

alter table crm.actividades_cliente
  drop constraint if exists actividades_cliente_tipo_check;
alter table crm.actividades_cliente
  add constraint actividades_cliente_tipo_check check (tipo in (
    'llamada_realizada', 'llamada_no_contestada', 'whatsapp_enviado',
    'whatsapp_recibido', 'reunion_realizada', 'nota', 'reasignacion'
  ));

alter table crm.actividades_cliente
  drop constraint if exists actividades_cliente_responsable_check;
alter table crm.actividades_cliente
  add constraint actividades_cliente_responsable_check check (
    vendedor_id is not null or tipo = 'reasignacion'
  );

comment on column crm.actividades_cliente.vendedor_id is
  'Identificador técnico legado del responsable del hecho. Solo una reasignación puede carecer de responsable.';

create or replace function private.trg_cliente_historial_reasignacion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_responsable uuid := coalesce(new.asesor_perfil_id, old.asesor_perfil_id);
  v_anterior text;
  v_nuevo text;
  v_detalle text;
begin
  if new.rol <> 'cliente'
     or new.asesor_perfil_id is not distinct from old.asesor_perfil_id then
    return new;
  end if;

  select p.nombre_completo
    into v_anterior
  from public.perfiles p
  where p.id = old.asesor_perfil_id;

  select p.nombre_completo
    into v_nuevo
  from public.perfiles p
  where p.id = new.asesor_perfil_id;

  if v_responsable is not null
     and not exists (
       select 1
       from crm.equipo e
       where e.perfil_id = v_responsable
     ) then
    v_responsable := null;
  end if;

  v_detalle := case
    when old.asesor_perfil_id is null then
      format('Cliente asignado a Analista: %s.', coalesce(v_nuevo, 'no disponible'))
    when new.asesor_perfil_id is null then
      format('Cliente quedó sin Analista. Analista anterior: %s.', coalesce(v_anterior, 'no disponible'))
    else
      format(
        'Asignación actualizada. Analista anterior: %s. Analista actual: %s.',
        coalesce(v_anterior, 'no disponible'),
        coalesce(v_nuevo, 'no disponible')
      )
  end;

  insert into crm.actividades_cliente (
    cliente_id,
    vendedor_id,
    tarea_id,
    tipo,
    detalle,
    creado_por
  ) values (
    new.id,
    v_responsable,
    null,
    'reasignacion',
    v_detalle,
    (select auth.uid())
  );

  return new;
end;
$function$;

comment on function private.trg_cliente_historial_reasignacion() is
  'Registra en la Ficha 360 cada cambio de Analista del cliente.';

revoke all on function private.trg_cliente_historial_reasignacion()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_zz_perfiles_cliente_historial_reasignacion
  on public.perfiles;
create trigger trg_zz_perfiles_cliente_historial_reasignacion
after update of asesor_perfil_id on public.perfiles
for each row
execute function private.trg_cliente_historial_reasignacion();

do $postflight$
declare
  v_expuesta pg_catalog.pg_proc%rowtype;
  v_autorizacion pg_catalog.pg_proc%rowtype;
  v_proyeccion pg_catalog.pg_proc%rowtype;
  v_trigger pg_catalog.pg_proc%rowtype;
begin
  select p.* into v_expuesta
  from pg_catalog.pg_proc p
  where p.oid = 'crm.cliente_ficha_fn(uuid)'::regprocedure;

  select p.* into v_autorizacion
  from pg_catalog.pg_proc p
  where p.oid = 'private.puede_consultar_cliente_ficha(uuid)'::regprocedure;

  select p.* into v_proyeccion
  from pg_catalog.pg_proc p
  where p.oid = 'private.cliente_ficha_autorizada_fn(uuid)'::regprocedure;

  select p.* into v_trigger
  from pg_catalog.pg_proc p
  where p.oid = 'private.trg_cliente_historial_reasignacion()'::regprocedure;

  if v_expuesta.prosecdef
     or v_expuesta.provolatile <> 's'
     or not (v_expuesta.proconfig @> array['search_path=""'])
     or not v_autorizacion.prosecdef
     or v_autorizacion.provolatile <> 's'
     or not (v_autorizacion.proconfig @> array['search_path=""'])
     or not v_proyeccion.prosecdef
     or v_proyeccion.provolatile <> 's'
     or not (v_proyeccion.proconfig @> array['search_path=""'])
     or not v_trigger.prosecdef
     or not (v_trigger.proconfig @> array['search_path=""']) then
    raise exception
      'POSTFLIGHT FICHA 360: funciones sin flags o search_path esperados';
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
    raise exception 'POSTFLIGHT FICHA 360: ACL inesperada en la RPC expuesta';
  end if;

  if exists (
    select 1
    from unnest(coalesce(v_expuesta.proargnames, '{}'::text[])) salida(nombre)
    where salida.nombre like any (array[
      'banco%', 'tipo_cuenta%', 'numero_cuenta%', 'cci%',
      'titular_distinto%', 'beneficiario_%', 'domicilio', 'creado_por'
    ])
  ) then
    raise exception 'POSTFLIGHT FICHA 360: la RPC publicó datos fuera de su frontera';
  end if;

  if not exists (
       select 1
       from pg_catalog.pg_policy p
       where p.polrelid = 'crm.actividades_cliente'::regclass
         and p.polname = 'actividades_cliente_select'
         and p.polcmd = 'r'
         and pg_catalog.pg_get_expr(p.polqual, p.polrelid)
           ilike '%puede_consultar_cliente_ficha%'
     )
     or not exists (
       select 1
       from pg_catalog.pg_policy p
       where p.polrelid = 'crm.operaciones_cartera'::regclass
         and p.polname = 'operaciones_cartera_select'
         and p.polcmd = 'r'
         and pg_catalog.pg_get_expr(p.polqual, p.polrelid)
           ilike '%puede_consultar_cliente_ficha%'
     ) then
    raise exception 'POSTFLIGHT FICHA 360: historial o movimientos no usan el alcance actual';
  end if;

  if (
       select c.is_nullable
       from information_schema.columns c
       where c.table_schema = 'crm'
         and c.table_name = 'actividades_cliente'
         and c.column_name = 'vendedor_id'
     ) <> 'YES'
     or not exists (
       select 1
       from pg_catalog.pg_constraint c
       where c.conrelid = 'crm.actividades_cliente'::regclass
         and c.conname = 'actividades_cliente_tipo_check'
         and pg_catalog.pg_get_constraintdef(c.oid) ilike '%reasignacion%'
     )
     or not exists (
       select 1
       from pg_catalog.pg_constraint c
       where c.conrelid = 'crm.actividades_cliente'::regclass
         and c.conname = 'actividades_cliente_responsable_check'
     )
     or not exists (
       select 1
       from pg_catalog.pg_trigger t
       where t.tgrelid = 'public.perfiles'::regclass
         and t.tgname = 'trg_zz_perfiles_cliente_historial_reasignacion'
         and not t.tgisinternal
         and t.tgfoid = 'private.trg_cliente_historial_reasignacion()'::regprocedure
     ) then
    raise exception 'POSTFLIGHT FICHA 360: historial de reasignación incompleto';
  end if;
end;
$postflight$;

commit;

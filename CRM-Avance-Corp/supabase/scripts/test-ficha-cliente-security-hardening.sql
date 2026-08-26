-- Oraculo aislado para F41: capacidades PDF y linealizacion de reasignaciones.
-- Solo puede ejecutarse en la base desechable creada por su runner local.

\set ON_ERROR_STOP on

do $guardia_destino$
begin
  if current_database() <> 'crm_ficha_security_test' then
    raise exception 'F41-QA solo puede ejecutarse en crm_ficha_security_test';
  end if;
  if to_regrole('anon') is null
     or to_regrole('authenticated') is null
     or to_regrole('service_role') is null then
    raise exception 'F41-QA requiere los roles locales de Supabase';
  end if;
end;
$guardia_destino$;

create extension dblink;
create extension pgcrypto;

create schema auth;
create schema private;
create schema crm;
create schema qa;

grant usage on schema public, crm to authenticated, service_role;
grant usage on schema private to authenticated;
grant usage on schema auth to anon, authenticated, service_role;

create function auth.uid()
returns uuid
language sql
stable
set search_path = ''
as $function$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$function$;

create table public.perfiles (
  id uuid primary key,
  rol text not null,
  activo boolean not null default true,
  asesor_perfil_id uuid
);

create table crm.equipo (
  perfil_id uuid primary key references public.perfiles(id),
  rol_crm text not null,
  supervisor_id uuid,
  activo boolean not null default true
);

create table public.contratos (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references public.perfiles(id),
  numero_contrato text not null,
  notas_internas text,
  categoria text,
  capital numeric not null default 1000,
  moneda text not null default 'PEN',
  estado text not null default 'activo',
  fecha_vencimiento date not null default (current_date + 365),
  renovado_a_id uuid references public.contratos(id) on delete restrict,
  cerrado_en timestamptz,
  cerrado_por uuid,
  creado_por uuid not null,
  creado_en timestamptz not null default statement_timestamp(),
  actualizado_en timestamptz
);

-- Reproduce el ACL historico que permitia a PostgREST escribir directo. La
-- migracion F41 debe cerrarlo sin afectar al worker service_role.
grant insert, update, delete, truncate on public.contratos
  to anon, authenticated, service_role;

create table public.cronograma_pagos (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos(id),
  numero_cuota integer not null,
  fecha_programada date not null,
  monto_programado numeric not null,
  estado text not null,
  fecha_pago_real date,
  monto_pagado numeric,
  registrado_por uuid,
  creado_en timestamptz default statement_timestamp(),
  tipo text not null,
  notif_pago_enviada_en timestamptz,
  recordatorio_3d_enviado_en timestamptz
);

create table public.contrato_titulares (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos(id),
  orden integer not null,
  nombre_completo text not null,
  tipo_documento text not null,
  documento text not null,
  creado_por uuid
);

grant all on public.cronograma_pagos, public.contrato_titulares
  to anon, authenticated, service_role;

-- La instalación histórica de la helper SECURITY DEFINER pudo nacer con
-- EXECUTE de PUBLIC. F41 debe cerrarla y dejar solo al backend confiable.
create function public._sync_contrato_titulares(
  p_contrato_id uuid,
  p_titulares jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform p_contrato_id, p_titulares;
end;
$function$;

create table crm.cuentas_bancarias (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references public.perfiles(id),
  cci text not null
);

create table crm.contrato_cuentas_pago (
  contrato_id uuid primary key references public.contratos(id),
  cuenta_bancaria_id uuid not null references crm.cuentas_bancarias(id)
);

create table private.contrato_escritura_atomica_capacidades (
  token uuid primary key,
  backend_pid integer not null,
  transaccion_id bigint not null,
  actor_id uuid not null,
  operacion text not null,
  cliente_id uuid not null,
  contrato_id uuid
);

create table private.contrato_pdf_jobs (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos(id),
  revision integer not null default 1,
  estado text not null default 'pendiente',
  solicitado_por uuid not null,
  storage_path text,
  lease_expira_en timestamptz
);

create table private.contrato_pdfs (
  job_id uuid primary key references private.contrato_pdf_jobs(id),
  contrato_id uuid not null references public.contratos(id),
  generado_por uuid not null,
  storage_path text
);

create table private.contrato_eliminaciones (
  contrato_id uuid primary key references public.contratos(id),
  token uuid not null default gen_random_uuid(),
  solicitado_por uuid not null,
  objetos jsonb not null default '[]'::jsonb
);

-- Proyeccion minima del ledger que consume el trigger legacy de renovaciones.
-- Solo se omiten columnas que el trigger no lee ni escribe en estas carreras.
create table crm.periodos_cerrados (
  periodo date primary key
);

create table crm.operaciones_cartera (
  id uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('renovacion', 'upgrade')),
  contrato_origen_id uuid references public.contratos(id) on delete restrict,
  contrato_nuevo_id uuid not null unique
    references public.contratos(id) on delete restrict,
  periodo date not null
);

create table qa.efectos (
  id bigint generated always as identity primary key,
  cliente_id uuid not null,
  contrato_id uuid,
  tipo text not null
);

create function private.puede_gestionar_cuentas_cliente(p_cliente_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.perfiles cliente
    join public.perfiles actor on actor.id = (select auth.uid())
    left join crm.equipo equipo on equipo.perfil_id = actor.id
    where cliente.id = p_cliente_id
      and cliente.rol = 'cliente'
      and cliente.activo
      and actor.activo
      and (
        actor.rol in ('admin', 'superadmin', 'analista')
        or (equipo.activo and equipo.rol_crm = 'gerencia')
        or (
          equipo.activo
          and equipo.rol_crm = 'supervisor'
          and exists (
            select 1
            from crm.equipo vendedor
            where vendedor.perfil_id = cliente.asesor_perfil_id
              and vendedor.activo
              and vendedor.rol_crm = 'vendedor'
              and vendedor.supervisor_id = actor.id
          )
        )
        or cliente.asesor_perfil_id = actor.id
      )
  );
$function$;

revoke all on function private.puede_gestionar_cuentas_cliente(uuid)
  from public, anon, authenticated, service_role;

create function public.es_gestor_cartera()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.perfiles actor
    where actor.id = (select auth.uid())
      and actor.activo
      and actor.rol in ('admin', 'superadmin', 'analista')
  );
$function$;

create function public.es_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1 from public.perfiles actor
    where actor.id = (select auth.uid())
      and actor.activo
      and actor.rol in ('admin', 'superadmin')
  );
$function$;

create function public.es_superadmin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1 from public.perfiles actor
    where actor.id = (select auth.uid())
      and actor.activo
      and actor.rol = 'superadmin'
  );
$function$;

create function private.membresia_crm_revocada()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from crm.equipo e
    where e.perfil_id = (select auth.uid())
      and e.activo is false
  );
$function$;

create function private.es_superadmin_portal_activo()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.perfiles actor
    where actor.id = (select auth.uid())
      and actor.activo
      and actor.rol = 'superadmin'
  );
$function$;

create function private.es_gerencia_crm_activa()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.perfiles actor
    join crm.equipo e on e.perfil_id = actor.id
    where actor.id = (select auth.uid())
      and actor.activo
      and e.activo
      and e.rol_crm = 'gerencia'
  );
$function$;

create function private.rol_crm(p_actor_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $function$
  select e.rol_crm
  from crm.equipo e
  where e.perfil_id = p_actor_id
    and e.activo is true;
$function$;

create function private.validar_supervisor_usuario_crm(
  p_perfil_id uuid,
  p_rol text,
  p_supervisor_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if p_perfil_id is null or p_rol is null then
    raise exception 'Membresia CRM invalida';
  end if;
end;
$function$;

revoke all on function public.es_gestor_cartera()
  from public, anon, authenticated, service_role;
grant execute on function public.es_gestor_cartera() to authenticated;
revoke all on function public.es_admin()
  from public, anon, authenticated, service_role;
revoke all on function public.es_superadmin()
  from public, anon, authenticated, service_role;
revoke all on function private.membresia_crm_revocada()
  from public, anon, authenticated, service_role;
revoke all on function private.es_superadmin_portal_activo()
  from public, anon, authenticated, service_role;
revoke all on function private.es_gerencia_crm_activa()
  from public, anon, authenticated, service_role;
revoke all on function private.rol_crm(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.validar_supervisor_usuario_crm(uuid,text,uuid)
  from public, anon, authenticated, service_role;

create function public.puede_ver_contrato(p_contrato_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.contratos contrato
    join public.perfiles cliente on cliente.id = contrato.cliente_id
    join public.perfiles actor on actor.id = (select auth.uid())
    left join crm.equipo equipo on equipo.perfil_id = actor.id
    where contrato.id = p_contrato_id
      and actor.activo
      and (
        actor.rol in ('directorio', 'admin', 'superadmin')
        or (
          equipo.activo
          and equipo.rol_crm in ('directorio', 'gerencia')
        )
        or (
          equipo.activo
          and equipo.rol_crm = 'supervisor'
          and exists (
            select 1
            from crm.equipo vendedor
            where vendedor.perfil_id = cliente.asesor_perfil_id
              and vendedor.activo
              and vendedor.rol_crm = 'vendedor'
              and vendedor.supervisor_id = actor.id
          )
        )
        or cliente.asesor_perfil_id = actor.id
      )
  );
$function$;

revoke all on function public.puede_ver_contrato(uuid)
  from public, anon, authenticated, service_role;

create function private.puede_leer_contrato_pdf(p_contrato_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select public.puede_ver_contrato(p_contrato_id);
$function$;

revoke all on function private.puede_leer_contrato_pdf(uuid)
  from public, anon, authenticated, service_role;

create function private.puede_leer_contrato_pdf_como(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_anterior text := current_setting('request.jwt.claim.sub', true);
  v_resultado boolean;
begin
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  v_resultado := private.puede_leer_contrato_pdf(p_contrato_id);
  perform set_config('request.jwt.claim.sub', coalesce(v_anterior, ''), true);
  return v_resultado;
exception when others then
  perform set_config('request.jwt.claim.sub', coalesce(v_anterior, ''), true);
  raise;
end;
$function$;

revoke all on function private.puede_leer_contrato_pdf_como(uuid,uuid)
  from public, anon, authenticated, service_role;

create function private.tiene_capacidad_contrato_atomico(
  p_operacion text,
  p_cliente_id uuid,
  p_contrato_id uuid
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_token uuid;
begin
  begin
    v_token := nullif(
      current_setting('crm.contrato_escritura_atomica_token', true),
      ''
    )::uuid;
  exception when invalid_text_representation then
    return false;
  end;
  return exists (
    select 1
    from private.contrato_escritura_atomica_capacidades capacidad
    where capacidad.token = v_token
      and capacidad.backend_pid = pg_backend_pid()
      and capacidad.transaccion_id = txid_current()
      and capacidad.actor_id = (select auth.uid())
      and capacidad.operacion = p_operacion
      and capacidad.cliente_id = p_cliente_id
      and capacidad.contrato_id is not distinct from p_contrato_id
  );
end;
$function$;

revoke all on function private.tiene_capacidad_contrato_atomico(text,uuid,uuid)
  from public, anon, authenticated, service_role;

-- Writers canonicos minimos. Sus marcadores reproducen las fronteras que la
-- migracion clona; las tablas QA permiten comprobar atomicidad y rollback.
create function public.crear_contrato(p_contrato jsonb, p_cronograma jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_cliente_id uuid := (p_contrato->>'cliente_id')::uuid;
  v_id uuid;
begin
  if not private.puede_gestionar_cuentas_cliente(v_cliente_id)
     or not private.tiene_capacidad_contrato_atomico(
       'alta', v_cliente_id, null
     ) then
    raise insufficient_privilege using
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;
  insert into public.contratos (
    cliente_id,
    numero_contrato,
    creado_por
  ) values (
    v_cliente_id,
    coalesce(p_contrato->>'numero_contrato', gen_random_uuid()::text),
    (select auth.uid())
  ) returning id into v_id;
  insert into qa.efectos (cliente_id, contrato_id, tipo)
  values (v_cliente_id, v_id, 'contrato_creado');
  return jsonb_build_object('id', v_id);
end;
$function$;

create function public.actualizar_contrato(
  p_id uuid,
  p_contrato jsonb,
  p_cronograma jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_cliente_id uuid;
  v_pause bigint;
begin
  select contrato.cliente_id into strict v_cliente_id
  from public.contratos contrato
  where contrato.id = p_id;
  if not (
       public.es_gestor_cartera()
       and not private.membresia_crm_revocada()
     )
     and (
       not private.puede_gestionar_cuentas_cliente(v_cliente_id)
       or not private.tiene_capacidad_contrato_atomico(
         'correccion', v_cliente_id, p_id
       )
     ) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
  v_pause := nullif(p_contrato->>'pause_key', '')::bigint;
  if v_pause is not null then
    perform pg_advisory_xact_lock(v_pause);
  end if;
  update public.contratos
  set actualizado_en = statement_timestamp()
  where id = p_id;
  -- Reproduce el writer canonico parent→child; la carrera de cobro debe
  -- demostrar que el REST toma el padre antes de intentar esta misma cuota.
  update public.cronograma_pagos
  set monto_programado = monto_programado
  where contrato_id = p_id;
  insert into qa.efectos (cliente_id, contrato_id, tipo)
  values (v_cliente_id, p_id, 'contrato_corregido');
  return jsonb_build_object('id', p_id);
end;
$function$;

create function public.cerrar_contrato(
  p_id uuid,
  p_resultado text,
  p_contrato_nuevo_id uuid default null::uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = 'public'
as $function$
declare
  v_contrato public.contratos%rowtype;
  v_pause bigint := nullif(
    current_setting('qa.cierre_pause_key', true),
    ''
  )::bigint;
begin
  if not public.es_admin() then
    raise insufficient_privilege using message = 'No autorizado';
  end if;
  if p_resultado not in ('renovado', 'retirado') then
    raise exception 'Resultado invalido' using errcode = '22023';
  end if;
  select contrato.* into strict v_contrato
  from public.contratos contrato
  where contrato.id = p_id
  for update;
  if v_pause is not null then
    perform pg_advisory_xact_lock(v_pause);
  end if;
  if v_contrato.estado not in ('activo', 'vencido')
     or v_contrato.renovado_a_id is not null then
    raise exception 'El contrato ya fue cerrado o renovado'
      using errcode = 'P0409';
  end if;
  if p_resultado = 'renovado' then
    if p_contrato_nuevo_id is null
       or p_contrato_nuevo_id = p_id
       or not exists (
         select 1 from public.contratos nuevo
         where nuevo.id = p_contrato_nuevo_id
       ) then
      raise exception 'Contrato nuevo invalido' using errcode = '22023';
    end if;
    update contratos
    set estado = 'renovado',
        renovado_a_id = p_contrato_nuevo_id,
        cerrado_en = statement_timestamp(),
        cerrado_por = (select auth.uid())
    where id = p_id;
    update cronograma_pagos
    set estado = 'trasladado'
    where contrato_id = p_id
      and estado in ('pendiente', 'vencido');
  else
    update contratos
    set estado = 'retirado',
        renovado_a_id = null,
        cerrado_en = statement_timestamp(),
        cerrado_por = (select auth.uid())
    where id = p_id;
  end if;
  return jsonb_build_object(
    'ok', true,
    'estado', p_resultado,
    'contrato_nuevo_id', p_contrato_nuevo_id,
    'id', v_contrato.id
  );
end;
$function$;

revoke all on function public.cerrar_contrato(uuid,text,uuid)
  from public, anon;
grant execute on function public.cerrar_contrato(uuid,text,uuid)
  to authenticated, service_role;

create function public.actualizar_numero_contrato(
  p_id uuid,
  p_numero text,
  p_notas text default null::text,
  p_categoria text default null::text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = 'public', 'pg_temp'
as $function$
declare
  v_cliente_id uuid;
  v_pause bigint := nullif(
    current_setting('qa.numero_pause_key', true),
    ''
  )::bigint;
begin
  if not public.es_gestor_cartera()
     or private.membresia_crm_revocada() then
    raise insufficient_privilege using message = 'No autorizado';
  end if;
  select contrato.cliente_id into strict v_cliente_id
  from public.contratos contrato
  where contrato.id = p_id;
  if v_pause is not null then
    perform pg_advisory_xact_lock(v_pause);
  end if;
  update public.contratos
  set numero_contrato = nullif(btrim(p_numero), ''),
      notas_internas = coalesce(p_notas, notas_internas),
      categoria = coalesce(p_categoria, categoria),
      actualizado_en = statement_timestamp()
  where id = p_id;
  insert into qa.efectos (cliente_id, contrato_id, tipo)
  values (v_cliente_id, p_id, 'numero_corregido');
  return jsonb_build_object('id', p_id, 'ok', true);
end;
$function$;

create function crm.crear_contrato_con_cuenta(
  p_contrato jsonb,
  p_cronograma jsonb,
  p_cuenta jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_cliente_id uuid := (p_contrato->>'cliente_id')::uuid;
  v_cuenta_id uuid;
  v_pause bigint;
  v_resultado jsonb;
  v_contrato_id uuid;
begin
  if not private.puede_gestionar_cuentas_cliente(v_cliente_id) then
    raise insufficient_privilege using
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;
  perform pg_advisory_xact_lock(
    hashtextextended(v_cliente_id::text || '|cuenta', 0)
  );
  v_pause := nullif(p_contrato->>'pause_key', '')::bigint;
  if v_pause is not null then
    perform pg_advisory_xact_lock(v_pause);
  end if;
  if p_cuenta->>'tipo' = 'nueva' then
    insert into crm.cuentas_bancarias (cliente_id, cci)
    values (v_cliente_id, coalesce(p_cuenta->>'cci', '00000000000000000000'))
    returning id into v_cuenta_id;
  elsif p_cuenta->>'tipo' = 'existente' then
    v_cuenta_id := (p_cuenta->>'cuenta_id')::uuid;
    perform 1 from crm.cuentas_bancarias cuenta
    where cuenta.id = v_cuenta_id and cuenta.cliente_id = v_cliente_id;
    if not found then
      raise exception 'Cuenta inexistente' using errcode = '22023';
    end if;
  else
    raise exception 'Tipo de cuenta invalido' using errcode = '22023';
  end if;
  insert into qa.efectos (cliente_id, tipo)
  values (v_cliente_id, 'cuenta_preparada');
  v_resultado := public.crear_contrato(p_contrato, p_cronograma);
  v_contrato_id := (v_resultado->>'id')::uuid;
  insert into crm.contrato_cuentas_pago (contrato_id, cuenta_bancaria_id)
  values (v_contrato_id, v_cuenta_id);
  return v_resultado || jsonb_build_object('cuenta_bancaria_id', v_cuenta_id);
end;
$function$;

create function crm.actualizar_contrato_con_cuenta(
  p_id uuid,
  p_contrato jsonb,
  p_cronograma jsonb
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_cliente_id uuid;
begin
  select contrato.cliente_id into strict v_cliente_id
  from public.contratos contrato
  where contrato.id = p_id;
  if not private.puede_gestionar_cuentas_cliente(v_cliente_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
  perform public.actualizar_contrato(p_id, p_contrato, p_cronograma);
end;
$function$;

revoke all on function public.crear_contrato(jsonb,jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.crear_contrato(jsonb,jsonb)
  to authenticated, service_role;
revoke all on function public.actualizar_contrato(uuid,jsonb,jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.actualizar_contrato(uuid,jsonb,jsonb)
  to authenticated;
revoke all on function public.actualizar_numero_contrato(uuid,text,text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.actualizar_numero_contrato(uuid,text,text,text)
  to authenticated, service_role;
revoke all on function crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)
  from public, anon, authenticated, service_role;
grant execute on function crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)
  to authenticated;
revoke all on function crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)
  from public, anon, authenticated, service_role;
grant execute on function crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)
  to authenticated;

create function private.contrato_en_eliminacion(p_contrato_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$ select false; $function$;

create function private.crear_job_contrato_pdf_base(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_cliente_id uuid;
  v_job_id uuid;
begin
  if not private.puede_leer_contrato_pdf_como(p_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
  select contrato.cliente_id into strict v_cliente_id
  from public.contratos contrato where contrato.id = p_contrato_id;
  insert into private.contrato_pdf_jobs (
    contrato_id, revision, solicitado_por
  ) values (
    p_contrato_id, 1, p_actor_id
  ) returning id into v_job_id;
  insert into qa.efectos (cliente_id, contrato_id, tipo)
  values (v_cliente_id, p_contrato_id, 'pdf_job');
  return jsonb_build_object(
    'job_id', v_job_id,
    'contrato_id', p_contrato_id,
    'estado', 'pendiente'
  );
end;
$function$;

create function private.crear_revision_contrato_pdf_base(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_cliente_id uuid;
  v_job_id uuid;
  v_revision integer;
begin
  if not private.puede_leer_contrato_pdf_como(p_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
  select contrato.cliente_id into strict v_cliente_id
  from public.contratos contrato where contrato.id = p_contrato_id;
  select coalesce(max(job.revision), 0) + 1 into v_revision
  from private.contrato_pdf_jobs job
  where job.contrato_id = p_contrato_id;
  insert into private.contrato_pdf_jobs (
    contrato_id, revision, solicitado_por
  ) values (
    p_contrato_id, v_revision, p_actor_id
  ) returning id into v_job_id;
  insert into qa.efectos (cliente_id, contrato_id, tipo)
  values (v_cliente_id, p_contrato_id, 'pdf_revision');
  return jsonb_build_object(
    'job_id', v_job_id,
    'contrato_id', p_contrato_id,
    'estado', 'pendiente'
  );
end;
$function$;

revoke all on function private.contrato_en_eliminacion(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.crear_job_contrato_pdf_base(uuid,uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.crear_revision_contrato_pdf_base(uuid,uuid)
  from public, anon, authenticated, service_role;

create function crm.crear_contrato_con_cuenta_pdf_v2(
  p_contrato jsonb,
  p_cronograma jsonb,
  p_cuenta jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  return crm.crear_contrato_con_cuenta(p_contrato, p_cronograma, p_cuenta);
end;
$function$;

create function crm.actualizar_contrato_con_cuenta_pdf_v3(
  p_id uuid,
  p_contrato jsonb,
  p_cronograma jsonb,
  p_revision_esperada timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform crm.actualizar_contrato_con_cuenta(p_id, p_contrato, p_cronograma);
  return jsonb_build_object('id', p_id);
end;
$function$;

create function crm.actualizar_numero_contrato_pdf_v3(
  p_id uuid,
  p_numero text,
  p_notas text default null,
  p_categoria text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_resultado jsonb;
  v_pdf jsonb;
begin
  if v_actor_id is null then
    raise insufficient_privilege using message = 'Sesion no valida';
  end if;
  perform set_config('crm.contrato_pdf_revision_autorizada', p_id::text, true);
  begin
    v_resultado := public.actualizar_numero_contrato(
      p_id, p_numero, p_notas, p_categoria
    );
  exception when others then
    perform set_config('crm.contrato_pdf_revision_autorizada', '', true);
    raise;
  end;
  perform set_config('crm.contrato_pdf_revision_autorizada', '', true);
  v_pdf := private.crear_revision_contrato_pdf_base(p_id, v_actor_id);
  return v_resultado || jsonb_build_object('pdf', v_pdf);
end;
$function$;

create function crm.contrato_pdf_estado_fn(p_contrato_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not private.puede_leer_contrato_pdf(p_contrato_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
  return jsonb_build_object('contrato_id', p_contrato_id, 'estado', 'sellado');
end;
$function$;

create function crm.contrato_pdf_reservar(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  return private.crear_job_contrato_pdf_base(p_contrato_id, p_actor_id);
end;
$function$;

create function private.bloquear_fila_contrato_pdf(p_contrato_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_pause bigint := nullif(
    current_setting('qa.pdf_pre_update_pause_key', true),
    ''
  )::bigint;
begin
  if v_pause is not null then
    perform pg_advisory_xact_lock(v_pause);
  end if;
  perform 1
  from public.contratos contrato
  where contrato.id = p_contrato_id
  for update;
end;
$function$;

revoke all on function private.bloquear_fila_contrato_pdf(uuid)
  from public, anon, authenticated, service_role;

create function private.poder_eliminar_contrato_como(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_sub_anterior text := current_setting('request.jwt.claim.sub', true);
  v_admin boolean;
  v_superadmin boolean;
begin
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  v_admin := public.es_admin();
  v_superadmin := public.es_superadmin();
  perform set_config(
    'request.jwt.claim.sub', coalesce(v_sub_anterior, ''), true
  );
  return jsonb_build_object(
    'admin', v_admin,
    'superadmin', v_superadmin,
    'tiene_pagos', false,
    'contrato_id', p_contrato_id
  );
exception when others then
  perform set_config(
    'request.jwt.claim.sub', coalesce(v_sub_anterior, ''), true
  );
  raise;
end;
$function$;

revoke all on function private.poder_eliminar_contrato_como(uuid,uuid)
  from public, anon, authenticated, service_role;

create function crm.contrato_eliminacion_preparar(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_poder jsonb;
  v_eliminacion private.contrato_eliminaciones%rowtype;
begin
  perform private.bloquear_fila_contrato_pdf(p_contrato_id);
  v_poder := private.poder_eliminar_contrato_como(
    p_contrato_id, p_actor_id
  );
  if not coalesce((v_poder->>'admin')::boolean, false) then
    raise insufficient_privilege using message = 'Solo Admin o Superadmin';
  end if;
  select * into v_eliminacion
  from private.contrato_eliminaciones e
  where e.contrato_id = p_contrato_id
  for update;
  if not found then
    insert into private.contrato_eliminaciones (
      contrato_id, solicitado_por, objetos
    ) values (
      p_contrato_id, p_actor_id, '[]'::jsonb
    ) returning * into v_eliminacion;
  end if;
  return jsonb_build_object(
    'contrato_id', v_eliminacion.contrato_id,
    'token', v_eliminacion.token,
    'objetos', v_eliminacion.objetos
  );
end;
$function$;

create function crm.contrato_eliminacion_finalizar(
  p_contrato_id uuid,
  p_token uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_eliminacion private.contrato_eliminaciones%rowtype;
begin
  perform private.bloquear_fila_contrato_pdf(p_contrato_id);
  select * into v_eliminacion
  from private.contrato_eliminaciones e
  where e.contrato_id = p_contrato_id
    and e.token = p_token
    and e.solicitado_por = p_actor_id
  for update;
  if not found then
    raise exception 'Preparacion inexistente' using errcode = 'P0002';
  end if;
  perform set_config(
    'crm.contrato_pdf_eliminacion_autorizada',
    p_contrato_id::text,
    true
  );
  delete from private.contrato_pdfs where contrato_id = p_contrato_id;
  delete from private.contrato_pdf_jobs where contrato_id = p_contrato_id;
  delete from private.contrato_eliminaciones where contrato_id = p_contrato_id;
  delete from public.contratos where id = p_contrato_id;
  perform set_config('crm.contrato_pdf_eliminacion_autorizada', '', true);
  return jsonb_build_object('ok', true, 'contrato_id', p_contrato_id);
end;
$function$;

revoke all on function crm.contrato_eliminacion_preparar(uuid,uuid)
  from public, anon, authenticated, service_role;
revoke all on function crm.contrato_eliminacion_finalizar(uuid,uuid,uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.contrato_eliminacion_preparar(uuid,uuid)
  to service_role;
grant execute on function crm.contrato_eliminacion_finalizar(uuid,uuid,uuid)
  to service_role;

create function crm.contrato_pdf_reclamar(
  p_contrato_id uuid,
  p_actor_id uuid,
  p_lease_segundos integer default 120
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  perform private.bloquear_fila_contrato_pdf(p_contrato_id);
  if not private.puede_leer_contrato_pdf_como(p_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
  return jsonb_build_object(
    'contrato_id', p_contrato_id,
    'estado', 'procesando',
    'lease_segundos', p_lease_segundos
  );
end;
$function$;

create function crm.contrato_pdf_marcar_subido(
  p_job_id uuid,
  p_lease_token uuid,
  p_actor_id uuid,
  p_sha256 text,
  p_bytes bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_contrato_id uuid;
begin
  select job.contrato_id into strict v_contrato_id
  from private.contrato_pdf_jobs job
  where job.id = p_job_id;
  perform private.bloquear_fila_contrato_pdf(v_contrato_id);
  if not private.puede_leer_contrato_pdf_como(v_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
  update private.contrato_pdf_jobs
  set estado = 'subido_verificado'
  where id = p_job_id;
  return jsonb_build_object(
    'contrato_id', v_contrato_id,
    'estado', 'subido_verificado',
    'sha256', p_sha256,
    'bytes', p_bytes,
    'lease_token', p_lease_token
  );
end;
$function$;

create function crm.contrato_pdf_marcar_error(
  p_job_id uuid,
  p_lease_token uuid,
  p_actor_id uuid,
  p_error_codigo text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_contrato_id uuid;
begin
  select job.contrato_id into strict v_contrato_id
  from private.contrato_pdf_jobs job
  where job.id = p_job_id;
  perform private.bloquear_fila_contrato_pdf(v_contrato_id);
  if not private.puede_leer_contrato_pdf_como(v_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
  update private.contrato_pdf_jobs
  set estado = 'error_reintentable'
  where id = p_job_id;
  return jsonb_build_object(
    'contrato_id', v_contrato_id,
    'estado', 'error_reintentable',
    'codigo', p_error_codigo,
    'lease_token', p_lease_token
  );
end;
$function$;

create function crm.contrato_pdf_finalizar(
  p_job_id uuid,
  p_lease_token uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_contrato_id uuid;
  v_cliente_id uuid;
  v_pause bigint;
begin
  select job.contrato_id, contrato.cliente_id
    into strict v_contrato_id, v_cliente_id
  from private.contrato_pdf_jobs job
  join public.contratos contrato on contrato.id = job.contrato_id
  where job.id = p_job_id;
  perform private.bloquear_fila_contrato_pdf(v_contrato_id);
  if not private.puede_leer_contrato_pdf_como(v_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
  v_pause := nullif(current_setting('qa.pdf_pause_key', true), '')::bigint;
  if v_pause is not null then
    perform pg_advisory_xact_lock(v_pause);
  end if;
  insert into private.contrato_pdfs (job_id, contrato_id, generado_por)
  values (p_job_id, v_contrato_id, p_actor_id)
  on conflict (job_id) do nothing;
  update private.contrato_pdf_jobs set estado = 'sellado' where id = p_job_id;
  insert into qa.efectos (cliente_id, contrato_id, tipo)
  values (v_cliente_id, v_contrato_id, 'pdf_sellado');
  return jsonb_build_object(
    'contrato_id', v_contrato_id,
    'estado', 'sellado',
    'lease_token', p_lease_token
  );
end;
$function$;

revoke all on function crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)
  from public, anon, authenticated, service_role;
grant execute on function crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)
  to authenticated;
revoke all on function crm.actualizar_contrato_con_cuenta_pdf_v3(
  uuid,jsonb,jsonb,timestamptz
) from public, anon, authenticated, service_role;
grant execute on function crm.actualizar_contrato_con_cuenta_pdf_v3(
  uuid,jsonb,jsonb,timestamptz
) to authenticated;
revoke all on function crm.actualizar_numero_contrato_pdf_v3(
  uuid,text,text,text
) from public, anon, authenticated, service_role;
grant execute on function crm.actualizar_numero_contrato_pdf_v3(
  uuid,text,text,text
) to authenticated;
revoke all on function crm.contrato_pdf_estado_fn(uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.contrato_pdf_estado_fn(uuid) to authenticated;
revoke all on function crm.contrato_pdf_reservar(uuid,uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.contrato_pdf_reservar(uuid,uuid) to service_role;
revoke all on function crm.contrato_pdf_reclamar(uuid,uuid,integer)
  from public, anon, authenticated, service_role;
grant execute on function crm.contrato_pdf_reclamar(uuid,uuid,integer)
  to service_role;
revoke all on function crm.contrato_pdf_marcar_subido(
  uuid,uuid,uuid,text,bigint
) from public, anon, authenticated, service_role;
grant execute on function crm.contrato_pdf_marcar_subido(
  uuid,uuid,uuid,text,bigint
) to service_role;
revoke all on function crm.contrato_pdf_marcar_error(uuid,uuid,uuid,text)
  from public, anon, authenticated, service_role;
grant execute on function crm.contrato_pdf_marcar_error(uuid,uuid,uuid,text)
  to service_role;
revoke all on function crm.contrato_pdf_finalizar(uuid,uuid,uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.contrato_pdf_finalizar(uuid,uuid,uuid)
  to service_role;

-- Mutadores exclusivos canonicos minimos. La migracion debe conservar sus
-- cuerpos/OIDs y anteponer una reautorizacion del actor bajo la llave global.
create function qa.pausar_mutador_si_configurado()
returns void
language plpgsql
volatile
set search_path = ''
as $function$
declare
  v_pause bigint := nullif(
    current_setting('qa.mutator_pause_key', true),
    ''
  )::bigint;
begin
  if v_pause is not null then
    perform pg_advisory_xact_lock(v_pause);
  end if;
end;
$function$;

create function crm.impacto_desactivacion_usuario_fn(p_perfil_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object('perfil_id', p_perfil_id);
$function$;

create function crm.asignar_rol_usuario_fn(
  p_perfil_id uuid,
  p_rol_crm text,
  p_version_equipo timestamptz,
  p_idempotencia uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if not private.es_superadmin_portal_activo() then
    raise insufficient_privilege using message = 'Solo Superadmin';
  end if;
  if not exists (
    select 1 from crm.equipo e where e.perfil_id = p_perfil_id
  ) and not exists (
    select 1
    from public.perfiles p
    where p.id = p_perfil_id
      and p.rol in ('comercial', 'analista')
  ) then
    raise exception 'Solo Comercial o Analista Portal puede ingresar al CRM';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );
  perform qa.pausar_mutador_si_configurado();
  update crm.equipo set rol_crm = p_rol_crm
  where perfil_id = p_perfil_id;
  insert into qa.efectos (cliente_id, tipo)
  values (p_perfil_id, 'rol_mutado');
  return jsonb_build_object(
    'perfil_id', p_perfil_id,
    'rol_crm', p_rol_crm,
    'idempotencia', p_idempotencia,
    'version', p_version_equipo
  );
end;
$function$;

create function crm.actualizar_jerarquia_usuario_fn(
  p_perfil_id uuid,
  p_supervisor_id uuid,
  p_version_equipo timestamptz,
  p_idempotencia uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_rol text;
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );
  perform qa.pausar_mutador_si_configurado();
  select rol_crm into strict v_rol
  from crm.equipo where perfil_id = p_perfil_id;
  perform private.validar_supervisor_usuario_crm(
    p_perfil_id, v_rol, p_supervisor_id
  );
  update crm.equipo set supervisor_id = p_supervisor_id
  where perfil_id = p_perfil_id;
  insert into qa.efectos (cliente_id, tipo)
  values (p_perfil_id, 'jerarquia_mutada');
  return jsonb_build_object(
    'perfil_id', p_perfil_id,
    'supervisor_id', p_supervisor_id,
    'idempotencia', p_idempotencia,
    'version', p_version_equipo
  );
end;
$function$;

create function crm.fijar_membresia_activa_fn(
  p_perfil_id uuid,
  p_activo boolean,
  p_reemplazo_id uuid,
  p_version_equipo timestamptz,
  p_idempotencia uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );
  perform qa.pausar_mutador_si_configurado();
  if p_activo is false then
    perform crm.impacto_desactivacion_usuario_fn(p_perfil_id);
  end if;
  update crm.equipo set activo = p_activo
  where perfil_id = p_perfil_id;
  insert into qa.efectos (cliente_id, tipo)
  values (p_perfil_id, 'membresia_mutada');
  return jsonb_build_object(
    'perfil_id', p_perfil_id,
    'activo', p_activo,
    'reemplazo_id', p_reemplazo_id,
    'idempotencia', p_idempotencia,
    'version', p_version_equipo
  );
end;
$function$;

create function crm.registrar_vendedor_usuario_fn(
  p_perfil_id uuid,
  p_correo text,
  p_nombre_completo text,
  p_tipo_documento text,
  p_documento text,
  p_telefono text,
  p_whatsapp text,
  p_cargo text,
  p_supervisor_id uuid,
  p_idempotencia uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );
  perform qa.pausar_mutador_si_configurado();
  perform private.validar_supervisor_usuario_crm(
    p_perfil_id, 'vendedor', p_supervisor_id
  );
  insert into crm.equipo (
    perfil_id, rol_crm, supervisor_id, activo
  ) values (
    p_perfil_id, 'vendedor', p_supervisor_id, true
  ) on conflict (perfil_id) do update
    set rol_crm = excluded.rol_crm,
        supervisor_id = excluded.supervisor_id,
        activo = excluded.activo;
  insert into qa.efectos (cliente_id, tipo)
  values (p_perfil_id, 'vendedor_registrado');
  return jsonb_build_object(
    'perfil_id', p_perfil_id,
    'correo', p_correo,
    'nombre', p_nombre_completo,
    'tipo_documento', p_tipo_documento,
    'documento', p_documento,
    'telefono', p_telefono,
    'whatsapp', p_whatsapp,
    'cargo', p_cargo,
    'supervisor_id', p_supervisor_id,
    'idempotencia', p_idempotencia
  );
end;
$function$;

revoke all on function crm.impacto_desactivacion_usuario_fn(uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.impacto_desactivacion_usuario_fn(uuid)
  to authenticated;
revoke all on function crm.asignar_rol_usuario_fn(
  uuid,text,timestamptz,uuid
) from public, anon, authenticated, service_role;
grant execute on function crm.asignar_rol_usuario_fn(
  uuid,text,timestamptz,uuid
) to authenticated;
revoke all on function crm.actualizar_jerarquia_usuario_fn(
  uuid,uuid,timestamptz,uuid
) from public, anon, authenticated, service_role;
grant execute on function crm.actualizar_jerarquia_usuario_fn(
  uuid,uuid,timestamptz,uuid
) to authenticated;
revoke all on function crm.fijar_membresia_activa_fn(
  uuid,boolean,uuid,timestamptz,uuid
) from public, anon, authenticated, service_role;
grant execute on function crm.fijar_membresia_activa_fn(
  uuid,boolean,uuid,timestamptz,uuid
) to authenticated;
revoke all on function crm.registrar_vendedor_usuario_fn(
  uuid,text,text,text,text,text,text,text,uuid,uuid
) from public, anon, authenticated, service_role;
grant execute on function crm.registrar_vendedor_usuario_fn(
  uuid,text,text,text,text,text,text,text,uuid,uuid
) to authenticated;

-- Superficie historica real de Pagos: policy UPDATE permisiva y trigger hijo
-- que vuelve a bloquear el contrato. F41 deja RLS pura, antepone un mutex de
-- sentencia al PATCH directo y conserva el fast path estricto de sellos.
create function private.bloquear_contratos_hijo_documental(
  p_anterior uuid,
  p_nuevo uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  perform contrato.id
  from public.contratos contrato
  where contrato.id in (p_anterior, p_nuevo)
  order by contrato.id
  for update;
end;
$function$;

create function private.mutacion_documental_autorizada(
  p_contrato_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select false;
$function$;

create function private.contrato_documental_congelado(
  p_contrato_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select false;
$function$;

create function private.proteger_cronograma_documental()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_anterior uuid := case
    when tg_op in ('UPDATE', 'DELETE') then old.contrato_id
  end;
  v_nuevo uuid := case
    when tg_op in ('INSERT', 'UPDATE') then new.contrato_id
  end;
begin
  perform private.bloquear_contratos_hijo_documental(v_anterior, v_nuevo);
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$function$;

create trigger trg_cronograma_pagos_00_documental_congelado
before insert or update or delete on public.cronograma_pagos
for each row execute function private.proteger_cronograma_documental();

alter table public.cronograma_pagos enable row level security;
create policy cronograma_select
on public.cronograma_pagos
as permissive
for select
to authenticated
using (public.es_gestor_cartera());
create policy cronograma_admin_actualiza
on public.cronograma_pagos
as permissive
for update
to authenticated
using (public.es_gestor_cartera())
with check (public.es_gestor_cartera());

-- Trigger legacy real de renovaciones. Al borrar el contrato nuevo restaura
-- primero las cuotas del origen y solo despues su fila padre (hijo→padre).
create function private.trg_preparar_eliminacion_operacion_cartera()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_op crm.operaciones_cartera%rowtype;
begin
  select * into v_op from crm.operaciones_cartera o
  where o.contrato_nuevo_id = new.contrato_id
     or o.contrato_origen_id = new.contrato_id
  order by (o.contrato_nuevo_id = new.contrato_id) desc
  limit 1;
  if not found then return new; end if;
  if v_op.contrato_origen_id = new.contrato_id then
    raise exception 'Primero elimina el contrato nuevo que renovó este contrato'
      using errcode = 'P0409';
  end if;
  if exists (
    select 1 from crm.periodos_cerrados pc where pc.periodo = v_op.periodo
  ) then
    raise exception
      'El contrato pertenece a un mes comercial cerrado y no se puede eliminar'
      using errcode = 'P0409';
  end if;
  return new;
end;
$function$;

create trigger trg_contrato_eliminaciones_00_operacion
before insert on private.contrato_eliminaciones
for each row execute function
  private.trg_preparar_eliminacion_operacion_cartera();

create function private.trg_restaurar_operacion_antes_borrar_contrato()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_op crm.operaciones_cartera%rowtype;
begin
  select * into v_op from crm.operaciones_cartera o
  where o.contrato_nuevo_id = old.id for update;
  if not found then return old; end if;
  if exists (
    select 1 from crm.periodos_cerrados pc where pc.periodo = v_op.periodo
  ) then
    raise exception
      'El contrato pertenece a un mes comercial cerrado y no se puede eliminar'
      using errcode = 'P0409';
  end if;

  perform set_config('crm.elimina_operacion_cartera', 'on', true);
  delete from crm.operaciones_cartera o where o.id = v_op.id;
  perform set_config('crm.elimina_operacion_cartera', 'off', true);

  if v_op.tipo = 'renovacion' and v_op.contrato_origen_id is not null then
    update public.cronograma_pagos cp
       set estado = case
         when cp.fecha_programada <
           (now() at time zone 'America/Lima')::date
           then 'vencido'
         else 'pendiente'
       end
     where cp.contrato_id = v_op.contrato_origen_id
       and cp.estado = 'trasladado';
    update public.contratos c
       set estado = case
         when c.fecha_vencimiento <
           (now() at time zone 'America/Lima')::date
           then 'vencido'
         else 'activo'
       end,
       renovado_a_id = null,
       cerrado_en = null,
       cerrado_por = null
     where c.id = v_op.contrato_origen_id
       and c.renovado_a_id = old.id;
  end if;
  return old;
end;
$function$;

create trigger trg_contratos_05_restaurar_operacion
before delete on public.contratos
for each row execute function
  private.trg_restaurar_operacion_antes_borrar_contrato();

revoke all on function private.trg_preparar_eliminacion_operacion_cartera()
  from public, anon, authenticated, service_role;
revoke all on function private.trg_restaurar_operacion_antes_borrar_contrato()
  from public, anon, authenticated, service_role;

\ir ../migrations/20260826164831_crm_ficha_cliente_security_hardening.sql

do $qa_acl_contratos$
begin
  if exists (
       select 1
       from pg_catalog.unnest(array['anon', 'authenticated']) as rol(nombre)
       cross join pg_catalog.unnest(
         array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']
       ) as privilegio(nombre)
       where pg_catalog.has_table_privilege(
         rol.nombre,
         'public.contratos',
         privilegio.nombre
       )
     )
     or exists (
       select 1
       from pg_catalog.unnest(
         array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']
       ) as privilegio(nombre)
       where not pg_catalog.has_table_privilege(
         'service_role',
         'public.contratos',
         privilegio.nombre
       )
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'public._sync_contrato_titulares(uuid,jsonb)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'public._sync_contrato_titulares(uuid,jsonb)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role',
       'public._sync_contrato_titulares(uuid,jsonb)',
       'EXECUTE'
     ) then
    raise exception
      'F41-QA: ACL contractual directo inseguro o worker bloqueado';
  end if;
end;
$qa_acl_contratos$;

do $qa_acl_hijos_contractuales$
declare
  v_columna text;
  v_privilegio text;
begin
  foreach v_columna in array array[
    'id',
    'contrato_id',
    'numero_cuota',
    'fecha_programada',
    'monto_programado',
    'creado_en',
    'tipo',
    'notif_pago_enviada_en',
    'recordatorio_3d_enviado_en'
  ] loop
    if pg_catalog.has_column_privilege(
      'authenticated',
      'public.cronograma_pagos',
      v_columna,
      'UPDATE'
    ) then
      raise exception 'F41-QA: termino de cronograma actualizable: %', v_columna;
    end if;
  end loop;

  foreach v_columna in array array[
    'estado', 'fecha_pago_real', 'monto_pagado', 'registrado_por'
  ] loop
    if not pg_catalog.has_column_privilege(
      'authenticated',
      'public.cronograma_pagos',
      v_columna,
      'UPDATE'
    ) then
      raise exception 'F41-QA: columna operativa bloqueada: %', v_columna;
    end if;
  end loop;

  foreach v_privilegio in array array['INSERT', 'DELETE', 'TRUNCATE'] loop
    if pg_catalog.has_table_privilege(
      'authenticated', 'public.cronograma_pagos', v_privilegio
    ) then
      raise exception 'F41-QA: DML directo de cronograma abierto';
    end if;
  end loop;

  if pg_catalog.has_table_privilege(
       'authenticated', 'public.contrato_titulares', 'INSERT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.contrato_titulares', 'UPDATE'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.contrato_titulares', 'DELETE'
     )
     or pg_catalog.has_table_privilege(
       'authenticated', 'public.contrato_titulares', 'TRUNCATE'
     ) then
    raise exception 'F41-QA: DML directo de titulares abierto';
  end if;
end;
$qa_acl_hijos_contractuales$;

-- Actores y casos independientes para no ocultar efectos entre carreras.
insert into public.perfiles (id, rol, activo) values
  ('f4100000-0000-4000-8000-000000000001', 'comercial', true),
  ('f4100000-0000-4000-8000-000000000002', 'comercial', true),
  ('f4100000-0000-4000-8000-000000000003', 'comercial', true),
  ('f4100000-0000-4000-8000-000000000004', 'directorio', true),
  ('f4100000-0000-4000-8000-000000000005', 'superadmin', true),
  ('f4100000-0000-4000-8000-000000000006', 'directorio', true),
  ('f4100000-0000-4000-8000-000000000007', 'comercial', true),
  ('f4100000-0000-4000-8000-000000000008', 'comercial', true),
  ('f4100000-0000-4000-8000-000000000009', 'comercial', true),
  ('f4100000-0000-4000-8000-000000000010', 'superadmin', true),
  ('f4100000-0000-4000-8000-000000000011', 'comercial', true),
  ('f4100000-0000-4000-8000-000000000012', 'comercial', true),
  ('f4100000-0000-4000-8000-000000000013', 'comercial', true),
  ('f4100000-0000-4000-8000-000000000014', 'admin', true),
  ('f4100000-0000-4000-8000-000000000015', 'admin', true);

insert into crm.equipo (perfil_id, rol_crm, activo) values
  ('f4100000-0000-4000-8000-000000000001', 'vendedor', true),
  ('f4100000-0000-4000-8000-000000000002', 'vendedor', true),
  ('f4100000-0000-4000-8000-000000000003', 'gerencia', true),
  ('f4100000-0000-4000-8000-000000000005', 'directorio', true),
  ('f4100000-0000-4000-8000-000000000006', 'gerencia', true),
  ('f4100000-0000-4000-8000-000000000007', 'supervisor', true),
  ('f4100000-0000-4000-8000-000000000008', 'supervisor', true),
  ('f4100000-0000-4000-8000-000000000011', 'gerencia', true),
  ('f4100000-0000-4000-8000-000000000012', 'vendedor', true);

insert into crm.equipo (perfil_id, rol_crm, activo, supervisor_id) values
  (
    'f4100000-0000-4000-8000-000000000009',
    'vendedor',
    true,
    'f4100000-0000-4000-8000-000000000007'
  );

insert into public.perfiles (id, rol, activo, asesor_perfil_id)
select
  ('f4110000-0000-4000-8000-' || lpad(numero::text, 12, '0'))::uuid,
  'cliente',
  true,
  'f4100000-0000-4000-8000-000000000001'::uuid
from generate_series(101, 106) as serie(numero);

insert into public.perfiles (id, rol, activo, asesor_perfil_id) values
  (
    'f4110000-0000-4000-8000-000000000107',
    'cliente',
    true,
    'f4100000-0000-4000-8000-000000000009'
  ),
  (
    'f4110000-0000-4000-8000-000000000108',
    'cliente',
    true,
    'f4100000-0000-4000-8000-000000000009'
  );

insert into public.contratos (
  id, cliente_id, numero_contrato, creado_por, creado_en
) values
  (
    'f4150000-0000-4000-8000-000000000103',
    'f4110000-0000-4000-8000-000000000103',
    'F41-CORRECCION-REASIGNA-GANA',
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000106',
    'f4110000-0000-4000-8000-000000000106',
    'F41-CORRECCION-WRITER-GANA',
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000107',
    'f4110000-0000-4000-8000-000000000107',
    'F41-AUTORIDAD-EQUIPO',
    'f4100000-0000-4000-8000-000000000009',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000108',
    'f4110000-0000-4000-8000-000000000108',
    'F41-PDF-WRITER',
    'f4100000-0000-4000-8000-000000000009',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000109',
    'f4110000-0000-4000-8000-000000000101',
    'F41-DELETE-OFFBOARD',
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000110',
    'f4110000-0000-4000-8000-000000000101',
    'F41-DELETE-PREPARE-WINS',
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000111',
    'f4110000-0000-4000-8000-000000000101',
    'F41-DELETE-TAKEOVER',
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000112',
    'f4110000-0000-4000-8000-000000000101',
    'F41-DELETE-PORTAL-DIRECTORIO',
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000113',
    'f4110000-0000-4000-8000-000000000101',
    'F41-DELETE-CRM-DIRECTORIO',
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  );

-- Casos aislados para cobro directo, cierre y restauracion de renovaciones.
insert into public.contratos (
  id, cliente_id, numero_contrato, creado_por, creado_en
) values
  (
    'f4150000-0000-4000-8000-000000000114',
    'f4110000-0000-4000-8000-000000000101',
    'F41-PAGO-BAJA-GANA',
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000115',
    'f4110000-0000-4000-8000-000000000101',
    'F41-PAGO-WRITER-GANA',
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000116',
    'f4110000-0000-4000-8000-000000000101',
    'F41-CIERRE-ANTES-PAGO',
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000117',
    'f4110000-0000-4000-8000-000000000101',
    'F41-PAGO-ANTES-CIERRE',
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000118',
    'f4110000-0000-4000-8000-000000000101',
    'F41-CIERRE-ANTES-PAGO-NUEVO',
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000119',
    'f4110000-0000-4000-8000-000000000101',
    'F41-PAGO-ANTES-CIERRE-NUEVO',
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000131',
    'f4110000-0000-4000-8000-000000000101',
    'F41-RESTORE-CIERRE-FINALIZA-REEMPLAZO',
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000132',
    'f4110000-0000-4000-8000-000000000101',
    'F41-RESTORE-CIERRE-WRITER-REEMPLAZO',
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  );

insert into public.contratos (
  id,
  cliente_id,
  numero_contrato,
  estado,
  fecha_vencimiento,
  renovado_a_id,
  cerrado_en,
  cerrado_por,
  creado_por,
  creado_en
) values
  (
    'f4150000-0000-4000-8000-000000000121',
    'f4110000-0000-4000-8000-000000000101',
    'F41-RESTORE-CORRECCION-FINALIZA-ORIGEN',
    'renovado', current_date + 90,
    'f4150000-0000-4000-8000-000000000122',
    statement_timestamp(),
    'f4100000-0000-4000-8000-000000000014',
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000122',
    'f4110000-0000-4000-8000-000000000101',
    'F41-RESTORE-CORRECCION-FINALIZA-NUEVO',
    'activo', current_date + 365, null, null, null,
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000123',
    'f4110000-0000-4000-8000-000000000101',
    'F41-RESTORE-CORRECCION-WRITER-ORIGEN',
    'renovado', current_date + 90,
    'f4150000-0000-4000-8000-000000000124',
    statement_timestamp(),
    'f4100000-0000-4000-8000-000000000014',
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000124',
    'f4110000-0000-4000-8000-000000000101',
    'F41-RESTORE-CORRECCION-WRITER-NUEVO',
    'activo', current_date + 365, null, null, null,
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000125',
    'f4110000-0000-4000-8000-000000000101',
    'F41-RESTORE-CIERRE-FINALIZA-ORIGEN',
    'renovado', current_date + 90,
    'f4150000-0000-4000-8000-000000000126',
    statement_timestamp(),
    'f4100000-0000-4000-8000-000000000014',
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000126',
    'f4110000-0000-4000-8000-000000000101',
    'F41-RESTORE-CIERRE-FINALIZA-NUEVO',
    'activo', current_date + 365, null, null, null,
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000127',
    'f4110000-0000-4000-8000-000000000101',
    'F41-RESTORE-CIERRE-WRITER-ORIGEN',
    'renovado', current_date + 90,
    'f4150000-0000-4000-8000-000000000128',
    statement_timestamp(),
    'f4100000-0000-4000-8000-000000000014',
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000128',
    'f4110000-0000-4000-8000-000000000101',
    'F41-RESTORE-CIERRE-WRITER-NUEVO',
    'activo', current_date + 365, null, null, null,
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000129',
    'f4110000-0000-4000-8000-000000000101',
    'F41-RESTORE-MISMA-TX-ORIGEN',
    'renovado', current_date + 90,
    'f4150000-0000-4000-8000-000000000130',
    statement_timestamp(),
    'f4100000-0000-4000-8000-000000000014',
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  ),
  (
    'f4150000-0000-4000-8000-000000000130',
    'f4110000-0000-4000-8000-000000000101',
    'F41-RESTORE-MISMA-TX-NUEVO',
    'activo', current_date + 365, null, null, null,
    'f4100000-0000-4000-8000-000000000001',
    statement_timestamp()
  );

insert into public.cronograma_pagos (
  id,
  contrato_id,
  numero_cuota,
  fecha_programada,
  monto_programado,
  estado,
  tipo
) values
  (
    'f4190000-0000-4000-8000-000000000106',
    'f4150000-0000-4000-8000-000000000106',
    1, current_date + 30, 100, 'pendiente', 'interes'
  ),
  (
    'f4190000-0000-4000-8000-000000000114',
    'f4150000-0000-4000-8000-000000000114',
    1, current_date + 30, 100, 'pendiente', 'interes'
  ),
  (
    'f4190000-0000-4000-8000-000000000115',
    'f4150000-0000-4000-8000-000000000115',
    1, current_date + 30, 100, 'pendiente', 'interes'
  ),
  (
    'f4190000-0000-4000-8000-000000000116',
    'f4150000-0000-4000-8000-000000000116',
    1, current_date + 30, 100, 'pendiente', 'interes'
  ),
  (
    'f4190000-0000-4000-8000-000000000117',
    'f4150000-0000-4000-8000-000000000117',
    1, current_date + 30, 100, 'pendiente', 'interes'
  ),
  (
    'f4190000-0000-4000-8000-000000000121',
    'f4150000-0000-4000-8000-000000000121',
    1, current_date + 30, 100, 'trasladado', 'interes'
  ),
  (
    'f4190000-0000-4000-8000-000000000123',
    'f4150000-0000-4000-8000-000000000123',
    1, current_date + 30, 100, 'trasladado', 'interes'
  ),
  (
    'f4190000-0000-4000-8000-000000000125',
    'f4150000-0000-4000-8000-000000000125',
    1, current_date + 30, 100, 'trasladado', 'interes'
  ),
  (
    'f4190000-0000-4000-8000-000000000225',
    'f4150000-0000-4000-8000-000000000125',
    2, current_date + 60, 100, 'pendiente', 'interes'
  ),
  (
    'f4190000-0000-4000-8000-000000000127',
    'f4150000-0000-4000-8000-000000000127',
    1, current_date + 30, 100, 'trasladado', 'interes'
  ),
  (
    'f4190000-0000-4000-8000-000000000227',
    'f4150000-0000-4000-8000-000000000127',
    2, current_date + 60, 100, 'pendiente', 'interes'
  ),
  (
    'f4190000-0000-4000-8000-000000000129',
    'f4150000-0000-4000-8000-000000000129',
    1, current_date + 30, 100, 'trasladado', 'interes'
  );

insert into crm.operaciones_cartera (
  id, tipo, contrato_origen_id, contrato_nuevo_id, periodo
) values
  (
    'f41a0000-0000-4000-8000-000000000121', 'renovacion',
    'f4150000-0000-4000-8000-000000000121',
    'f4150000-0000-4000-8000-000000000122',
    date_trunc('month', current_date)::date
  ),
  (
    'f41a0000-0000-4000-8000-000000000123', 'renovacion',
    'f4150000-0000-4000-8000-000000000123',
    'f4150000-0000-4000-8000-000000000124',
    date_trunc('month', current_date)::date
  ),
  (
    'f41a0000-0000-4000-8000-000000000125', 'renovacion',
    'f4150000-0000-4000-8000-000000000125',
    'f4150000-0000-4000-8000-000000000126',
    date_trunc('month', current_date)::date
  ),
  (
    'f41a0000-0000-4000-8000-000000000127', 'renovacion',
    'f4150000-0000-4000-8000-000000000127',
    'f4150000-0000-4000-8000-000000000128',
    date_trunc('month', current_date)::date
  ),
  (
    'f41a0000-0000-4000-8000-000000000129', 'renovacion',
    'f4150000-0000-4000-8000-000000000129',
    'f4150000-0000-4000-8000-000000000130',
    date_trunc('month', current_date)::date
  );

insert into private.contrato_pdf_jobs (
  id, contrato_id, revision, estado, solicitado_por
) values
  (
    'f4170000-0000-4000-8000-000000000108',
    'f4150000-0000-4000-8000-000000000108',
    1,
    'subido_verificado',
    'f4100000-0000-4000-8000-000000000007'
  ),
  (
    'f4170000-0000-4000-8000-000000000109',
    'f4150000-0000-4000-8000-000000000108',
    2,
    'subido_verificado',
    'f4100000-0000-4000-8000-000000000007'
  ),
  (
    'f4170000-0000-4000-8000-000000000110',
    'f4150000-0000-4000-8000-000000000108',
    3,
    'subido_verificado',
    'f4100000-0000-4000-8000-000000000007'
  ),
  (
    'f4170000-0000-4000-8000-000000000111',
    'f4150000-0000-4000-8000-000000000108',
    4,
    'subido_verificado',
    'f4100000-0000-4000-8000-000000000007'
  ),
  (
    'f4170000-0000-4000-8000-000000000112',
    'f4150000-0000-4000-8000-000000000108',
    5,
    'subido_verificado',
    'f4100000-0000-4000-8000-000000000007'
  ),
  (
    'f4170000-0000-4000-8000-000000000113',
    'f4150000-0000-4000-8000-000000000108',
    6,
    'subido_verificado',
    'f4100000-0000-4000-8000-000000000007'
  );

insert into crm.cuentas_bancarias (id, cliente_id, cci) values
  (
    'f4160000-0000-4000-8000-000000000101',
    'f4110000-0000-4000-8000-000000000101',
    '10100000000000000001'
  ),
  (
    'f4160000-0000-4000-8000-000000000104',
    'f4110000-0000-4000-8000-000000000104',
    '10400000000000000004'
  );

create function qa.assert_true(p_condicion boolean, p_mensaje text)
returns void
language plpgsql
set search_path = ''
as $function$
begin
  if p_condicion is not true then
    raise exception 'F41-QA: %', p_mensaje;
  end if;
end;
$function$;

grant usage on schema qa to authenticated;
grant execute on function qa.assert_true(boolean,text) to authenticated;

-- Matriz: lectura sellada separada de materializacion.
set role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'f4100000-0000-4000-8000-000000000004',
  false
);
select qa.assert_true(
  crm.contrato_pdf_estado_fn(
    'f4150000-0000-4000-8000-000000000103'
  )->>'estado' = 'sellado',
  'Directorio Portal perdio lectura sellada'
);
select qa.assert_true(
  not crm.contrato_pdf_puede_materializar_fn(
    'f4150000-0000-4000-8000-000000000103'
  ),
  'Directorio Portal materializo'
);

select set_config(
  'request.jwt.claim.sub',
  'f4100000-0000-4000-8000-000000000005',
  false
);
select qa.assert_true(
  crm.contrato_pdf_estado_fn(
    'f4150000-0000-4000-8000-000000000103'
  )->>'estado' = 'sellado',
  'Directorio CRM hibrido perdio lectura sellada'
);
select qa.assert_true(
  not crm.contrato_pdf_puede_materializar_fn(
    'f4150000-0000-4000-8000-000000000103'
  ),
  'Directorio CRM + Superadmin materializo'
);

select set_config(
  'request.jwt.claim.sub',
  'f4100000-0000-4000-8000-000000000003',
  false
);
select qa.assert_true(
  crm.contrato_pdf_puede_materializar_fn(
    'f4150000-0000-4000-8000-000000000103'
  ),
  'Gerencia perdio materializacion'
);

select set_config(
  'request.jwt.claim.sub',
  'f4100000-0000-4000-8000-000000000006',
  false
);
select qa.assert_true(
  crm.contrato_pdf_puede_materializar_fn(
    'f4150000-0000-4000-8000-000000000103'
  ),
  'Directorio Portal + Gerencia CRM fue vetado por el rol Portal'
);

select set_config(
  'request.jwt.claim.sub',
  'f4100000-0000-4000-8000-000000000001',
  false
);
select qa.assert_true(
  crm.contrato_pdf_puede_materializar_fn(
    'f4150000-0000-4000-8000-000000000103'
  ),
  'Vendedor asignado perdio materializacion'
);
reset role;

create temporary table qa_conteo_directorio as
select count(*)::bigint as jobs from private.contrato_pdf_jobs;

set role service_role;
do $directorio_reserva$
begin
  begin
    perform crm.contrato_pdf_reservar(
      'f4150000-0000-4000-8000-000000000103',
      'f4100000-0000-4000-8000-000000000005'
    );
    raise exception 'Directorio reservo un job PDF';
  exception when insufficient_privilege then
    null;
  end;
end;
$directorio_reserva$;
reset role;

select qa.assert_true(
  (select count(*) from private.contrato_pdf_jobs)
    = (select jobs from qa_conteo_directorio),
  'la reserva denegada de Directorio dejo jobs'
);

-- La autoridad administrativa Portal se conserva en la correccion publica,
-- pero una membresia CRM Directorio no puede convertirla en materializacion.
set role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'f4100000-0000-4000-8000-000000000005',
  false
);
select qa.assert_true(
  public.actualizar_numero_contrato(
    'f4150000-0000-4000-8000-000000000106',
    'F41-NUMERO-PORTAL-ADMIN',
    null,
    'nuevo'
  )->>'ok' = 'true',
  'Admin Portal perdio su correccion administrativa heredada'
);
reset role;

create temporary table qa_numero_hibrido_snapshot as
select
  numero_contrato,
  (select count(*) from qa.efectos)::bigint as efectos,
  (select count(*) from private.contrato_pdf_jobs)::bigint as jobs
from public.contratos
where id = 'f4150000-0000-4000-8000-000000000103';

set role authenticated;
do $numero_hibrido_pdf$
begin
  begin
    perform crm.actualizar_numero_contrato_pdf_v3(
      'f4150000-0000-4000-8000-000000000103',
      'F41-NUMERO-HIBRIDO-NO-DEBE-PERSISTIR',
      null,
      'nuevo'
    );
    raise exception 'Directorio CRM materializo una revision por numero';
  exception when insufficient_privilege then
    null;
  end;
end;
$numero_hibrido_pdf$;
reset role;

select qa.assert_true(
  (select contrato.numero_contrato
   from public.contratos contrato
   where contrato.id = 'f4150000-0000-4000-8000-000000000103')
    = (select numero_contrato from qa_numero_hibrido_snapshot)
  and (select count(*) from qa.efectos)
    = (select efectos from qa_numero_hibrido_snapshot)
  and (select count(*) from private.contrato_pdf_jobs)
    = (select jobs from qa_numero_hibrido_snapshot),
  'el veto PDF hibrido no revirtio numero, efecto o job'
);

-- Compatibilidad historica: Admin Portal corrige aunque el cliente ya este
-- inactivo y sin asignacion. Los wrappers Ficha exteriores siguen estrictos.
update public.perfiles
set activo = false, asesor_perfil_id = null
where id = 'f4110000-0000-4000-8000-000000000101';
set role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'f4100000-0000-4000-8000-000000000014',
  false
);
select qa.assert_true(
  public.actualizar_numero_contrato(
    'f4150000-0000-4000-8000-000000000109',
    'F41-HISTORICO-NUMERO',
    null,
    'nuevo'
  )->>'ok' = 'true',
  'Admin perdio correccion de numero sobre cliente historico'
);
select qa.assert_true(
  public.actualizar_contrato(
    'f4150000-0000-4000-8000-000000000109',
    '{}'::jsonb,
    '[]'::jsonb
  )->>'id' = 'f4150000-0000-4000-8000-000000000109',
  'Admin perdio correccion de terminos sobre cliente historico'
);
reset role;
update public.perfiles
set activo = true,
    asesor_perfil_id = 'f4100000-0000-4000-8000-000000000001'
where id = 'f4110000-0000-4000-8000-000000000101';

-- Hard-delete usa autoridad Portal pura: CRM Gerencia no rescata Portal
-- Directorio, mientras Portal Superadmin conserva poder aun con CRM Directorio.
do $delete_portal_directorio$
begin
  begin
    perform crm.contrato_eliminacion_preparar(
      'f4150000-0000-4000-8000-000000000112',
      'f4100000-0000-4000-8000-000000000006'
    );
    raise exception 'Portal Directorio elimino por su Gerencia CRM';
  exception when insufficient_privilege then
    null;
  end;
end;
$delete_portal_directorio$;
select qa.assert_true(
  not exists (
    select 1 from private.contrato_eliminaciones
    where contrato_id = 'f4150000-0000-4000-8000-000000000112'
  ),
  'delete denegado dejo intent'
);

create temporary table qa_delete_crm_directorio as
select crm.contrato_eliminacion_preparar(
  'f4150000-0000-4000-8000-000000000113',
  'f4100000-0000-4000-8000-000000000005'
) as resultado;
select crm.contrato_eliminacion_finalizar(
  'f4150000-0000-4000-8000-000000000113',
  ((select resultado from qa_delete_crm_directorio)->>'token')::uuid,
  'f4100000-0000-4000-8000-000000000005'
);
select qa.assert_true(
  not exists (
    select 1 from public.contratos
    where id = 'f4150000-0000-4000-8000-000000000113'
  ),
  'Portal Superadmin + CRM Directorio perdio hard-delete'
);

-- Helpers del arnes de concurrencia.
create function qa.try_create(
  p_actor_id uuid,
  p_cliente_id uuid,
  p_modo text,
  p_pause_key bigint default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_cuenta jsonb;
  v_cuenta_id uuid;
begin
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  if p_modo = 'existente' then
    select cuenta.id into strict v_cuenta_id
    from crm.cuentas_bancarias cuenta
    where cuenta.cliente_id = p_cliente_id;
    v_cuenta := jsonb_build_object(
      'tipo', 'existente',
      'cuenta_id', v_cuenta_id
    );
  elsif p_modo = 'nueva' then
    v_cuenta := jsonb_build_object(
      'tipo', 'nueva',
      'cci', replace(p_cliente_id::text, '-', '')
    );
  else
    raise exception 'Modo QA invalido';
  end if;
  begin
    perform crm.crear_contrato_con_cuenta_pdf_v2(
      jsonb_strip_nulls(jsonb_build_object(
        'cliente_id', p_cliente_id,
        'numero_contrato', 'QA-' || p_cliente_id::text,
        'pause_key', p_pause_key
      )),
      '[]'::jsonb,
      v_cuenta
    );
    return 'OK';
  exception when others then
    return sqlstate;
  end;
end;
$function$;

create function qa.try_correction(
  p_actor_id uuid,
  p_contrato_id uuid,
  p_pause_key bigint default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_revision timestamptz;
begin
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  select coalesce(
    contrato.actualizado_en,
    contrato.creado_en,
    'epoch'::timestamptz
  ) into strict v_revision
  from public.contratos contrato
  where contrato.id = p_contrato_id;
  begin
    perform crm.actualizar_contrato_con_cuenta_pdf_v3(
      p_contrato_id,
      jsonb_strip_nulls(jsonb_build_object('pause_key', p_pause_key)),
      '[]'::jsonb,
      v_revision
    );
    return 'OK';
  exception when others then
    return sqlstate;
  end;
end;
$function$;

create function qa.try_payment(
  p_actor_id uuid,
  p_cuota_id uuid
)
returns text
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  begin
    update public.cronograma_pagos cuota
    set estado = case
          when cuota.estado = 'pagado' then 'pendiente'
          else 'pagado'
        end,
        fecha_pago_real = case
          when cuota.estado = 'pagado' then null
          else current_date
        end,
        monto_pagado = case
          when cuota.estado = 'pagado' then null
          else cuota.monto_programado
        end,
        registrado_por = p_actor_id
    where cuota.id = p_cuota_id;
    if not found then
      return 'P0002';
    end if;
    return 'OK';
  exception when others then
    return sqlstate;
  end;
end;
$function$;

grant execute on function qa.try_payment(uuid,uuid) to authenticated;

create function qa.try_payment_and_pause(
  p_actor_id uuid,
  p_cuota_id uuid,
  p_pause_key bigint
)
returns text
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_resultado text;
begin
  v_resultado := qa.try_payment(p_actor_id, p_cuota_id);
  if v_resultado = 'OK' then
    perform pg_catalog.pg_advisory_xact_lock(p_pause_key);
  end if;
  return v_resultado;
end;
$function$;

grant execute on function qa.try_payment_and_pause(uuid,uuid,bigint)
  to authenticated;

create function qa.try_close(
  p_actor_id uuid,
  p_contrato_id uuid,
  p_contrato_nuevo_id uuid,
  p_pause_key bigint default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  perform set_config(
    'qa.cierre_pause_key',
    coalesce(p_pause_key::text, ''),
    true
  );
  begin
    perform public.cerrar_contrato(
      p_contrato_id,
      'renovado',
      p_contrato_nuevo_id
    );
    return 'OK';
  exception when others then
    return sqlstate;
  end;
end;
$function$;

create function qa.try_contract_correction(
  p_actor_id uuid,
  p_contrato_id uuid,
  p_pause_key bigint default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  begin
    perform public.actualizar_contrato(
      p_contrato_id,
      jsonb_strip_nulls(jsonb_build_object('pause_key', p_pause_key)),
      '[]'::jsonb
    );
    return 'OK';
  exception when others then
    return sqlstate;
  end;
end;
$function$;

create function qa.try_delete_finalize(
  p_contrato_id uuid,
  p_token uuid,
  p_actor_id uuid,
  p_pause_key bigint default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform set_config(
    'qa.pdf_pre_update_pause_key',
    coalesce(p_pause_key::text, ''),
    true
  );
  begin
    perform crm.contrato_eliminacion_finalizar(
      p_contrato_id,
      p_token,
      p_actor_id
    );
    return 'OK:' || txid_current()::text;
  exception when others then
    return sqlstate;
  end;
end;
$function$;

create function qa.cleanup_renewal_case(
  p_contrato_origen_id uuid,
  p_contrato_nuevo_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  delete from private.contrato_pdfs
  where contrato_id = p_contrato_nuevo_id;
  delete from private.contrato_pdf_jobs
  where contrato_id = p_contrato_nuevo_id;
  delete from private.contrato_eliminaciones
  where contrato_id = p_contrato_nuevo_id;
  delete from crm.operaciones_cartera
  where contrato_nuevo_id = p_contrato_nuevo_id
     or contrato_origen_id = p_contrato_origen_id;
  update public.contratos
  set estado = 'activo',
      renovado_a_id = null,
      cerrado_en = null,
      cerrado_por = null
  where id = p_contrato_origen_id;
  delete from public.contratos where id = p_contrato_nuevo_id;
  update public.cronograma_pagos
  set estado = 'pendiente',
      fecha_pago_real = null,
      monto_pagado = null,
      registrado_por = null
  where contrato_id = p_contrato_origen_id;
end;
$function$;

create function qa.lock_payment_row_and_pause(
  p_cuota_id uuid,
  p_pause_key bigint
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform cuota.id
  from public.cronograma_pagos cuota
  where cuota.id = p_cuota_id
  for update;
  if not found then
    raise exception 'Cuota QA inexistente';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(p_pause_key);
  return true;
end;
$function$;

create function qa.try_number_correction(
  p_actor_id uuid,
  p_contrato_id uuid,
  p_pause_key bigint default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  perform set_config(
    'qa.numero_pause_key',
    coalesce(p_pause_key::text, ''),
    true
  );
  begin
    perform public.actualizar_numero_contrato(
      p_contrato_id,
      'QA-NUM-' || gen_random_uuid()::text,
      'correccion QA',
      'nuevo'
    );
    return 'OK';
  exception when others then
    return sqlstate;
  end;
end;
$function$;

create function qa.reassign_and_pause(
  p_cliente_id uuid,
  p_nuevo_asesor uuid,
  p_pause_key bigint
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  update public.perfiles
  set asesor_perfil_id = p_nuevo_asesor
  where id = p_cliente_id;
  perform pg_advisory_xact_lock(p_pause_key);
  return true;
end;
$function$;

create function qa.reassign(
  p_cliente_id uuid,
  p_nuevo_asesor uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  update public.perfiles
  set asesor_perfil_id = p_nuevo_asesor
  where id = p_cliente_id;
  return true;
end;
$function$;

create function qa.mutar_autoridad_equipo(
  p_mutacion text,
  p_pause_key bigint default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if p_mutacion <> 'baja_portal' then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
    );
  end if;
  if p_mutacion = 'jerarquia' then
    update crm.equipo
    set supervisor_id = 'f4100000-0000-4000-8000-000000000008'
    where perfil_id = 'f4100000-0000-4000-8000-000000000009';
  elsif p_mutacion = 'rol' then
    update crm.equipo
    set rol_crm = 'directorio'
    where perfil_id = 'f4100000-0000-4000-8000-000000000007';
  elsif p_mutacion = 'baja' then
    update crm.equipo
    set activo = false
    where perfil_id = 'f4100000-0000-4000-8000-000000000007';
  elsif p_mutacion = 'baja_portal' then
    -- Reproduce el UPDATE directo permitido por la policy del perfil: esta
    -- ruta no comparte la advisory de crm.equipo.
    update public.perfiles
    set activo = false
    where id = 'f4100000-0000-4000-8000-000000000007';
  else
    raise exception 'Mutacion QA invalida';
  end if;
  if p_pause_key is not null then
    perform pg_advisory_xact_lock(p_pause_key);
  end if;
  return true;
end;
$function$;

create function qa.restaurar_autoridad_equipo()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );
  update crm.equipo
  set rol_crm = 'supervisor', activo = true
  where perfil_id = 'f4100000-0000-4000-8000-000000000007';
  update crm.equipo
  set supervisor_id = 'f4100000-0000-4000-8000-000000000007'
  where perfil_id = 'f4100000-0000-4000-8000-000000000009';
  update public.perfiles
  set activo = true
  where id = 'f4100000-0000-4000-8000-000000000007';
end;
$function$;

create function qa.try_finalize(
  p_actor_id uuid,
  p_job_id uuid,
  p_pause_key bigint default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform set_config(
    'qa.pdf_pause_key',
    coalesce(p_pause_key::text, ''),
    true
  );
  begin
    perform crm.contrato_pdf_finalizar(
      p_job_id,
      'f4180000-0000-4000-8000-000000000001',
      p_actor_id
    );
    return 'OK';
  exception when others then
    return sqlstate;
  end;
end;
$function$;

create function qa.try_finalize_pre_update_pause(
  p_actor_id uuid,
  p_job_id uuid,
  p_pause_key bigint
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform set_config(
    'qa.pdf_pre_update_pause_key',
    p_pause_key::text,
    true
  );
  perform set_config('qa.pdf_pause_key', '', true);
  begin
    perform crm.contrato_pdf_finalizar(
      p_job_id,
      'f4180000-0000-4000-8000-000000000001',
      p_actor_id
    );
    return 'OK';
  exception when others then
    return sqlstate;
  end;
end;
$function$;

create function qa.wait_for_lock(
  p_pid integer,
  p_advisory boolean,
  p_etiqueta text
)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  v_limite timestamptz := clock_timestamp() + interval '5 seconds';
begin
  loop
    if p_advisory and exists (
      select 1 from pg_catalog.pg_locks bloqueo
      where bloqueo.pid = p_pid
        and bloqueo.locktype = 'advisory'
        and not bloqueo.granted
    ) then
      return;
    end if;
    if not p_advisory and exists (
      select 1 from pg_catalog.pg_stat_activity actividad
      where actividad.pid = p_pid
        and actividad.wait_event_type = 'Lock'
    ) then
      return;
    end if;
    if clock_timestamp() > v_limite then
      raise exception 'F41-QA: % no quedo esperando un lock', p_etiqueta;
    end if;
    perform pg_sleep(0.01);
  end loop;
end;
$function$;

create function qa.close_dblink(p_nombre text)
returns void
language plpgsql
set search_path = ''
as $function$
begin
  if p_nombre = any(coalesce(public.dblink_get_connections(), '{}'::text[])) then
    perform public.dblink_disconnect(p_nombre);
  end if;
end;
$function$;

create function qa.try_exclusive_mutator(
  p_tipo text,
  p_actor_id uuid,
  p_pause_key bigint default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  perform set_config(
    'qa.mutator_pause_key',
    coalesce(p_pause_key::text, ''),
    true
  );
  begin
    if p_tipo = 'rol' then
      perform crm.asignar_rol_usuario_fn(
        'f4100000-0000-4000-8000-000000000012',
        'supervisor',
        statement_timestamp(),
        gen_random_uuid()
      );
    elsif p_tipo = 'jerarquia' then
      perform crm.actualizar_jerarquia_usuario_fn(
        'f4100000-0000-4000-8000-000000000012',
        'f4100000-0000-4000-8000-000000000008',
        statement_timestamp(),
        gen_random_uuid()
      );
    elsif p_tipo = 'membresia' then
      perform crm.fijar_membresia_activa_fn(
        'f4100000-0000-4000-8000-000000000012',
        false,
        null,
        statement_timestamp(),
        gen_random_uuid()
      );
    elsif p_tipo = 'registro' then
      perform crm.registrar_vendedor_usuario_fn(
        'f4100000-0000-4000-8000-000000000013',
        'qa-vendedor@avance.test',
        'QA VENDEDOR',
        'DNI',
        '99999999',
        null,
        null,
        'Vendedor',
        'f4100000-0000-4000-8000-000000000008',
        gen_random_uuid()
      );
    else
      raise exception 'Tipo de mutador QA invalido';
    end if;
    return 'OK';
  exception when others then
    return sqlstate;
  end;
end;
$function$;

create function qa.restaurar_mutador_exclusivo()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  update public.perfiles
  set activo = true
  where id in (
    'f4100000-0000-4000-8000-000000000010',
    'f4100000-0000-4000-8000-000000000011'
  );
  update crm.equipo
  set rol_crm = 'vendedor', supervisor_id = null, activo = true
  where perfil_id = 'f4100000-0000-4000-8000-000000000012';
  delete from crm.equipo
  where perfil_id = 'f4100000-0000-4000-8000-000000000013';
end;
$function$;

create function qa.race_actor_offboarding_wins(
  p_conn text,
  p_tipo text
)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  v_actor_id uuid := case when p_tipo = 'rol'
    then 'f4100000-0000-4000-8000-000000000010'::uuid
    else 'f4100000-0000-4000-8000-000000000011'::uuid
  end;
  v_mutator text := left('f41_xm_' || md5(p_tipo), 63);
  v_offboard text := left('f41_xo_' || md5(p_tipo), 63);
  v_global bigint := hashtextextended(
    'crm.equipo.usuarios_jerarquia', 0
  );
  v_mutator_pid integer;
  v_mutator_result text;
  v_offboard_result boolean;
  v_efectos bigint;
begin
  select count(*) into v_efectos from qa.efectos;
  perform pg_advisory_lock_shared(v_global);
  perform public.dblink_connect(v_mutator, p_conn);
  perform public.dblink_connect(v_offboard, p_conn);
  select remoto.pid into v_mutator_pid
  from public.dblink(v_mutator, 'select pg_backend_pid()')
    as remoto(pid integer);

  perform public.dblink_send_query(
    v_mutator,
    format(
      'select qa.try_exclusive_mutator(%L,%L::uuid,null)',
      p_tipo,
      v_actor_id
    )
  );
  perform qa.wait_for_lock(
    v_mutator_pid,
    true,
    p_tipo || ': mutador esperando autoridad global'
  );

  select remoto.actualizado into v_offboard_result
  from public.dblink(
    v_offboard,
    format(
      'with cambio as (update public.perfiles set activo=false where id=%L::uuid returning 1) select exists(select 1 from cambio)',
      v_actor_id
    )
  ) as remoto(actualizado boolean);
  perform pg_advisory_unlock_shared(v_global);
  select remoto.resultado into v_mutator_result
  from public.dblink_get_result(v_mutator) as remoto(resultado text);

  perform qa.assert_true(
    v_offboard_result,
    p_tipo || ': la baja Portal no confirmo'
  );
  perform qa.assert_true(
    v_mutator_result = '42501',
    p_tipo || ': actor revocado produjo efecto, obtuvo '
      || coalesce(v_mutator_result, 'null')
  );
  perform qa.assert_true(
    (select count(*) from qa.efectos) = v_efectos,
    p_tipo || ': mutador denegado dejo efectos'
  );

  perform qa.close_dblink(v_offboard);
  perform qa.close_dblink(v_mutator);
  perform qa.restaurar_mutador_exclusivo();
exception when others then
  perform pg_advisory_unlock_shared(v_global);
  perform qa.close_dblink(v_offboard);
  perform qa.close_dblink(v_mutator);
  perform qa.restaurar_mutador_exclusivo();
  raise;
end;
$function$;

create function qa.race_exclusive_mutator_wins(
  p_conn text,
  p_tipo text
)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  v_actor_id uuid := case when p_tipo = 'rol'
    then 'f4100000-0000-4000-8000-000000000010'::uuid
    else 'f4100000-0000-4000-8000-000000000011'::uuid
  end;
  v_mutator text := left('f41_ym_' || md5(p_tipo), 63);
  v_offboard text := left('f41_yo_' || md5(p_tipo), 63);
  v_pause bigint := hashtextextended('mutador-gana|' || p_tipo, 0);
  v_mutator_pid integer;
  v_offboard_pid integer;
  v_mutator_result text;
  v_offboard_result boolean;
  v_efectos bigint;
begin
  select count(*) into v_efectos from qa.efectos;
  perform pg_advisory_lock(v_pause);
  perform public.dblink_connect(v_mutator, p_conn);
  perform public.dblink_connect(v_offboard, p_conn);
  select remoto.pid into v_mutator_pid
  from public.dblink(v_mutator, 'select pg_backend_pid()')
    as remoto(pid integer);
  select remoto.pid into v_offboard_pid
  from public.dblink(v_offboard, 'select pg_backend_pid()')
    as remoto(pid integer);

  perform public.dblink_send_query(
    v_mutator,
    format(
      'select qa.try_exclusive_mutator(%L,%L::uuid,%s::bigint)',
      p_tipo,
      v_actor_id,
      v_pause
    )
  );
  perform qa.wait_for_lock(
    v_mutator_pid,
    true,
    p_tipo || ': mutador no alcanzo el sink'
  );

  perform public.dblink_send_query(
    v_offboard,
    format(
      'with cambio as (update public.perfiles set activo=false where id=%L::uuid returning 1) select exists(select 1 from cambio)',
      v_actor_id
    )
  );
  perform qa.wait_for_lock(
    v_offboard_pid,
    false,
    p_tipo || ': baja no espero el perfil actor'
  );

  perform pg_advisory_unlock(v_pause);
  select remoto.resultado into v_mutator_result
  from public.dblink_get_result(v_mutator) as remoto(resultado text);
  select remoto.actualizado into v_offboard_result
  from public.dblink_get_result(v_offboard) as remoto(actualizado boolean);

  perform qa.assert_true(
    v_mutator_result = 'OK',
    p_tipo || ': mutador linealizado fallo con '
      || coalesce(v_mutator_result, 'null')
  );
  perform qa.assert_true(
    v_offboard_result,
    p_tipo || ': baja posterior no confirmo'
  );
  perform qa.assert_true(
    (select count(*) from qa.efectos) = v_efectos + 1,
    p_tipo || ': mutador ganador no dejo exactamente un efecto'
  );
  perform qa.assert_true(
    (select activo from public.perfiles where id = v_actor_id) is false,
    p_tipo || ': baja posterior no quedo aplicada'
  );

  perform qa.close_dblink(v_offboard);
  perform qa.close_dblink(v_mutator);
  perform qa.restaurar_mutador_exclusivo();
exception when others then
  perform pg_advisory_unlock(v_pause);
  perform qa.close_dblink(v_offboard);
  perform qa.close_dblink(v_mutator);
  perform qa.restaurar_mutador_exclusivo();
  raise;
end;
$function$;

create function qa.offboard_actor_and_pause(
  p_actor_id uuid,
  p_pause_key bigint
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  update public.perfiles set activo = false where id = p_actor_id;
  perform pg_advisory_xact_lock(p_pause_key);
  return found;
end;
$function$;

create function qa.race_number_offboarding_wins(p_conn text)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  v_actor_id constant uuid :=
    'f4100000-0000-4000-8000-000000000010'::uuid;
  v_contrato_id constant uuid :=
    'f4150000-0000-4000-8000-000000000103'::uuid;
  v_offboard text := 'f41_num_offboard';
  v_writer text := 'f41_num_writer_denied';
  v_pause bigint := hashtextextended('numero-offboarding-gana', 0);
  v_offboard_pid integer;
  v_writer_pid integer;
  v_offboard_result boolean;
  v_writer_result text;
  v_numero text;
  v_efectos bigint;
begin
  select numero_contrato into v_numero
  from public.contratos where id = v_contrato_id;
  select count(*) into v_efectos from qa.efectos;
  perform pg_advisory_lock(v_pause);
  perform public.dblink_connect(v_offboard, p_conn);
  perform public.dblink_connect(v_writer, p_conn);
  select remoto.pid into v_offboard_pid
  from public.dblink(v_offboard, 'select pg_backend_pid()')
    as remoto(pid integer);
  select remoto.pid into v_writer_pid
  from public.dblink(v_writer, 'select pg_backend_pid()')
    as remoto(pid integer);

  perform public.dblink_send_query(
    v_offboard,
    format(
      'select qa.offboard_actor_and_pause(%L::uuid,%s::bigint)',
      v_actor_id,
      v_pause
    )
  );
  perform qa.wait_for_lock(
    v_offboard_pid,
    true,
    'numero: baja Portal no alcanzo la pausa'
  );
  perform public.dblink_send_query(
    v_writer,
    format(
      'select qa.try_number_correction(%L::uuid,%L::uuid,null)',
      v_actor_id,
      v_contrato_id
    )
  );
  perform qa.wait_for_lock(
    v_writer_pid,
    false,
    'numero: writer no espero la baja Portal'
  );

  perform pg_advisory_unlock(v_pause);
  select remoto.resultado into v_offboard_result
  from public.dblink_get_result(v_offboard) as remoto(resultado boolean);
  select remoto.resultado into v_writer_result
  from public.dblink_get_result(v_writer) as remoto(resultado text);

  perform qa.assert_true(v_offboard_result, 'numero: baja Portal fallo');
  perform qa.assert_true(
    v_writer_result = '42501',
    'numero: writer revocado obtuvo ' || coalesce(v_writer_result, 'null')
  );
  perform qa.assert_true(
    (select numero_contrato from public.contratos where id = v_contrato_id)
      = v_numero
    and (select count(*) from qa.efectos) = v_efectos,
    'numero: denegacion post-baja dejo efectos'
  );
  perform qa.close_dblink(v_writer);
  perform qa.close_dblink(v_offboard);
  update public.perfiles set activo = true where id = v_actor_id;
exception when others then
  perform pg_advisory_unlock(v_pause);
  perform qa.close_dblink(v_writer);
  perform qa.close_dblink(v_offboard);
  update public.perfiles set activo = true where id = v_actor_id;
  raise;
end;
$function$;

create function qa.race_number_writer_wins(p_conn text)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  v_actor_id constant uuid :=
    'f4100000-0000-4000-8000-000000000010'::uuid;
  v_contrato_id constant uuid :=
    'f4150000-0000-4000-8000-000000000103'::uuid;
  v_writer text := 'f41_num_writer_ok';
  v_offboard text := 'f41_num_offboard_wait';
  v_pause bigint := hashtextextended('numero-writer-gana', 0);
  v_writer_pid integer;
  v_offboard_pid integer;
  v_writer_result text;
  v_offboard_result boolean;
  v_numero text;
  v_efectos bigint;
begin
  select numero_contrato into v_numero
  from public.contratos where id = v_contrato_id;
  select count(*) into v_efectos from qa.efectos;
  perform pg_advisory_lock(v_pause);
  perform public.dblink_connect(v_writer, p_conn);
  perform public.dblink_connect(v_offboard, p_conn);
  select remoto.pid into v_writer_pid
  from public.dblink(v_writer, 'select pg_backend_pid()')
    as remoto(pid integer);
  select remoto.pid into v_offboard_pid
  from public.dblink(v_offboard, 'select pg_backend_pid()')
    as remoto(pid integer);

  perform public.dblink_send_query(
    v_writer,
    format(
      'select qa.try_number_correction(%L::uuid,%L::uuid,%s::bigint)',
      v_actor_id,
      v_contrato_id,
      v_pause
    )
  );
  perform qa.wait_for_lock(
    v_writer_pid,
    true,
    'numero: writer no alcanzo el sink'
  );
  perform public.dblink_send_query(
    v_offboard,
    format(
      'with cambio as (update public.perfiles set activo=false where id=%L::uuid returning 1) select exists(select 1 from cambio)',
      v_actor_id
    )
  );
  perform qa.wait_for_lock(
    v_offboard_pid,
    false,
    'numero: baja Portal no espero actor SHARE'
  );

  perform pg_advisory_unlock(v_pause);
  select remoto.resultado into v_writer_result
  from public.dblink_get_result(v_writer) as remoto(resultado text);
  select remoto.resultado into v_offboard_result
  from public.dblink_get_result(v_offboard) as remoto(resultado boolean);

  perform qa.assert_true(
    v_writer_result = 'OK',
    'numero: writer linealizado obtuvo ' || coalesce(v_writer_result, 'null')
  );
  perform qa.assert_true(v_offboard_result, 'numero: baja posterior fallo');
  perform qa.assert_true(
    (select numero_contrato from public.contratos where id = v_contrato_id)
      is distinct from v_numero
    and (select count(*) from qa.efectos) = v_efectos + 1,
    'numero: writer ganador no dejo exactamente su efecto'
  );
  perform qa.close_dblink(v_offboard);
  perform qa.close_dblink(v_writer);
  update public.perfiles set activo = true where id = v_actor_id;
exception when others then
  perform pg_advisory_unlock(v_pause);
  perform qa.close_dblink(v_offboard);
  perform qa.close_dblink(v_writer);
  update public.perfiles set activo = true where id = v_actor_id;
  raise;
end;
$function$;

create function qa.try_delete_prepare(
  p_contrato_id uuid,
  p_actor_id uuid,
  p_pause_key bigint default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_resultado jsonb;
begin
  begin
    v_resultado := crm.contrato_eliminacion_preparar(
      p_contrato_id,
      p_actor_id
    );
    if p_pause_key is not null then
      perform pg_advisory_xact_lock(p_pause_key);
    end if;
    return 'OK:' || (v_resultado->>'token');
  exception when others then
    return sqlstate;
  end;
end;
$function$;

create function qa.mutate_delete_actor_and_pause(
  p_actor_id uuid,
  p_mutacion text,
  p_pause_key bigint
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if p_mutacion = 'baja' then
    update public.perfiles set activo = false where id = p_actor_id;
  elsif p_mutacion = 'rol' then
    update public.perfiles set rol = 'directorio' where id = p_actor_id;
  else
    raise exception 'Mutacion delete QA invalida';
  end if;
  perform pg_advisory_xact_lock(p_pause_key);
  return true;
end;
$function$;

create function qa.restore_delete_actor()
returns void
language sql
volatile
security definer
set search_path = ''
as $function$
  update public.perfiles
  set activo = true, rol = 'admin'
  where id = 'f4100000-0000-4000-8000-000000000014';
$function$;

create function qa.race_delete_actor_mutation_wins(
  p_conn text,
  p_mutacion text
)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  v_actor_id constant uuid :=
    'f4100000-0000-4000-8000-000000000014'::uuid;
  v_contrato_id constant uuid :=
    'f4150000-0000-4000-8000-000000000109'::uuid;
  v_mutator text := left('f41_dm_' || md5(p_mutacion), 63);
  v_writer text := left('f41_dw_' || md5(p_mutacion), 63);
  v_pause bigint := hashtextextended('delete-mutacion|' || p_mutacion, 0);
  v_mutator_pid integer;
  v_writer_pid integer;
  v_mutator_result boolean;
  v_writer_result text;
begin
  perform pg_advisory_lock(v_pause);
  perform public.dblink_connect(v_mutator, p_conn);
  perform public.dblink_connect(v_writer, p_conn);
  select remoto.pid into v_mutator_pid
  from public.dblink(v_mutator, 'select pg_backend_pid()')
    as remoto(pid integer);
  select remoto.pid into v_writer_pid
  from public.dblink(v_writer, 'select pg_backend_pid()')
    as remoto(pid integer);

  perform public.dblink_send_query(
    v_mutator,
    format(
      'select qa.mutate_delete_actor_and_pause(%L::uuid,%L,%s::bigint)',
      v_actor_id,
      p_mutacion,
      v_pause
    )
  );
  perform qa.wait_for_lock(
    v_mutator_pid,
    true,
    'delete ' || p_mutacion || ': mutacion no alcanzo pausa'
  );
  perform public.dblink_send_query(
    v_writer,
    format(
      'select qa.try_delete_prepare(%L::uuid,%L::uuid,null)',
      v_contrato_id,
      v_actor_id
    )
  );
  perform qa.wait_for_lock(
    v_writer_pid,
    false,
    'delete ' || p_mutacion || ': preparar no espero perfil'
  );

  perform pg_advisory_unlock(v_pause);
  select remoto.resultado into v_mutator_result
  from public.dblink_get_result(v_mutator) as remoto(resultado boolean);
  select remoto.resultado into v_writer_result
  from public.dblink_get_result(v_writer) as remoto(resultado text);

  perform qa.assert_true(
    v_mutator_result,
    'delete ' || p_mutacion || ': mutacion fallo'
  );
  perform qa.assert_true(
    v_writer_result = '42501',
    'delete ' || p_mutacion || ': preparar revocado obtuvo '
      || coalesce(v_writer_result, 'null')
  );
  perform qa.assert_true(
    not exists (
      select 1 from private.contrato_eliminaciones
      where contrato_id = v_contrato_id
    ),
    'delete ' || p_mutacion || ': denegacion dejo intent'
  );
  perform qa.close_dblink(v_writer);
  perform qa.close_dblink(v_mutator);
  perform qa.restore_delete_actor();
exception when others then
  perform pg_advisory_unlock(v_pause);
  perform qa.close_dblink(v_writer);
  perform qa.close_dblink(v_mutator);
  perform qa.restore_delete_actor();
  raise;
end;
$function$;

create function qa.race_delete_prepare_wins(p_conn text)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  v_actor_id constant uuid :=
    'f4100000-0000-4000-8000-000000000014'::uuid;
  v_contrato_id constant uuid :=
    'f4150000-0000-4000-8000-000000000110'::uuid;
  v_writer text := 'f41_delete_prepare_ok';
  v_offboard text := 'f41_delete_offboard_wait';
  v_pause bigint := hashtextextended('delete-preparar-gana', 0);
  v_writer_pid integer;
  v_offboard_pid integer;
  v_writer_result text;
  v_offboard_result boolean;
  v_token uuid;
begin
  perform pg_advisory_lock(v_pause);
  perform public.dblink_connect(v_writer, p_conn);
  perform public.dblink_connect(v_offboard, p_conn);
  select remoto.pid into v_writer_pid
  from public.dblink(v_writer, 'select pg_backend_pid()')
    as remoto(pid integer);
  select remoto.pid into v_offboard_pid
  from public.dblink(v_offboard, 'select pg_backend_pid()')
    as remoto(pid integer);

  perform public.dblink_send_query(
    v_writer,
    format(
      'select qa.try_delete_prepare(%L::uuid,%L::uuid,%s::bigint)',
      v_contrato_id,
      v_actor_id,
      v_pause
    )
  );
  perform qa.wait_for_lock(
    v_writer_pid,
    true,
    'delete: preparar no alcanzo linearizacion'
  );
  perform public.dblink_send_query(
    v_offboard,
    format(
      'with cambio as (update public.perfiles set activo=false where id=%L::uuid returning 1) select exists(select 1 from cambio)',
      v_actor_id
    )
  );
  perform qa.wait_for_lock(
    v_offboard_pid,
    false,
    'delete: baja no espero actor SHARE'
  );

  perform pg_advisory_unlock(v_pause);
  select remoto.resultado into v_writer_result
  from public.dblink_get_result(v_writer) as remoto(resultado text);
  select remoto.resultado into v_offboard_result
  from public.dblink_get_result(v_offboard) as remoto(resultado boolean);
  begin
    v_token := split_part(v_writer_result, ':', 2)::uuid;
  exception when invalid_text_representation then
    raise exception 'F41-QA: delete preparar devolvio %', v_writer_result;
  end;

  perform qa.assert_true(
    left(v_writer_result, 3) = 'OK:' and v_offboard_result,
    'delete: orden preparar->baja no confirmo'
  );
  perform qa.assert_true(
    exists (
      select 1 from private.contrato_eliminaciones e
      where e.contrato_id = v_contrato_id
        and e.token = v_token
        and e.solicitado_por = v_actor_id
    ),
    'delete: preparar ganador no dejo capability durable'
  );

  perform crm.contrato_eliminacion_finalizar(
    v_contrato_id,
    v_token,
    v_actor_id
  );
  perform qa.assert_true(
    not exists (
      select 1 from public.contratos where id = v_contrato_id
    ),
    'delete: finalizacion capability-based fallo tras baja'
  );
  perform qa.close_dblink(v_offboard);
  perform qa.close_dblink(v_writer);
  perform qa.restore_delete_actor();
exception when others then
  perform pg_advisory_unlock(v_pause);
  perform qa.close_dblink(v_offboard);
  perform qa.close_dblink(v_writer);
  perform qa.restore_delete_actor();
  raise;
end;
$function$;

create function qa.race_reassignment_wins(
  p_conn text,
  p_etiqueta text,
  p_cliente_id uuid,
  p_modo text,
  p_contrato_id uuid default null,
  p_operacion text default 'correccion'
)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  v_locker text := left('f41_l_' || md5(p_etiqueta), 63);
  v_writer text := left('f41_w_' || md5(p_etiqueta), 63);
  v_key bigint := hashtextextended('reasigna|' || p_etiqueta, 0);
  v_locker_pid integer;
  v_writer_pid integer;
  v_locker_result boolean;
  v_writer_result text;
  v_contratos bigint;
  v_cuentas bigint;
  v_vinculos bigint;
  v_jobs bigint;
  v_efectos bigint;
begin
  select count(*) into v_contratos from public.contratos;
  select count(*) into v_cuentas from crm.cuentas_bancarias;
  select count(*) into v_vinculos from crm.contrato_cuentas_pago;
  select count(*) into v_jobs from private.contrato_pdf_jobs;
  select count(*) into v_efectos from qa.efectos;

  perform pg_advisory_lock(v_key);
  perform public.dblink_connect(v_locker, p_conn);
  perform public.dblink_connect(v_writer, p_conn);
  select remoto.pid into v_locker_pid
  from public.dblink(v_locker, 'select pg_backend_pid()') as remoto(pid integer);
  select remoto.pid into v_writer_pid
  from public.dblink(v_writer, 'select pg_backend_pid()') as remoto(pid integer);

  perform public.dblink_send_query(
    v_locker,
    format(
      'select qa.reassign_and_pause(%L::uuid,%L::uuid,%s::bigint)',
      p_cliente_id,
      'f4100000-0000-4000-8000-000000000002',
      v_key
    )
  );
  perform qa.wait_for_lock(v_locker_pid, true, p_etiqueta || ' locker');

  perform public.dblink_send_query(
    v_writer,
    case when p_contrato_id is null then format(
      'select qa.try_create(%L::uuid,%L::uuid,%L,null)',
      'f4100000-0000-4000-8000-000000000001',
      p_cliente_id,
      p_modo
    ) when p_operacion = 'numero' then format(
      'select qa.try_number_correction(%L::uuid,%L::uuid,null)',
      'f4100000-0000-4000-8000-000000000010',
      p_contrato_id
    ) else format(
      'select qa.try_correction(%L::uuid,%L::uuid,null)',
      'f4100000-0000-4000-8000-000000000001',
      p_contrato_id
    ) end
  );
  perform qa.wait_for_lock(v_writer_pid, false, p_etiqueta || ' writer');

  perform pg_advisory_unlock(v_key);
  select remoto.resultado into v_locker_result
  from public.dblink_get_result(v_locker) as remoto(resultado boolean);
  select remoto.resultado into v_writer_result
  from public.dblink_get_result(v_writer) as remoto(resultado text);

  perform qa.assert_true(v_locker_result, p_etiqueta || ': reasignacion fallo');
  perform qa.assert_true(
    v_writer_result = '42501',
    p_etiqueta || ': writer no fue denegado, obtuvo ' || coalesce(v_writer_result, 'null')
  );
  perform qa.assert_true(
    (select count(*) from public.contratos) = v_contratos
      and (select count(*) from crm.cuentas_bancarias) = v_cuentas
      and (select count(*) from crm.contrato_cuentas_pago) = v_vinculos
      and (select count(*) from private.contrato_pdf_jobs) = v_jobs
      and (select count(*) from qa.efectos) = v_efectos
      and not exists (
        select 1 from private.contrato_escritura_atomica_capacidades
      ),
    p_etiqueta || ': la denegacion dejo efectos parciales'
  );
  perform qa.close_dblink(v_writer);
  perform qa.close_dblink(v_locker);
exception when others then
  perform pg_advisory_unlock(v_key);
  perform qa.close_dblink(v_writer);
  perform qa.close_dblink(v_locker);
  raise;
end;
$function$;

create function qa.race_writer_wins(
  p_conn text,
  p_etiqueta text,
  p_cliente_id uuid,
  p_modo text,
  p_contrato_id uuid default null,
  p_operacion text default 'correccion'
)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  v_writer text := left('f41_w_' || md5(p_etiqueta), 63);
  v_reassign text := left('f41_r_' || md5(p_etiqueta), 63);
  v_key bigint := hashtextextended('writer|' || p_etiqueta, 0);
  v_writer_pid integer;
  v_reassign_pid integer;
  v_writer_result text;
  v_reassign_result boolean;
  v_contratos bigint;
  v_cuentas bigint;
  v_jobs bigint;
begin
  select count(*) into v_contratos from public.contratos;
  select count(*) into v_cuentas from crm.cuentas_bancarias;
  select count(*) into v_jobs from private.contrato_pdf_jobs;

  perform pg_advisory_lock(v_key);
  perform public.dblink_connect(v_writer, p_conn);
  perform public.dblink_connect(v_reassign, p_conn);
  select remoto.pid into v_writer_pid
  from public.dblink(v_writer, 'select pg_backend_pid()') as remoto(pid integer);
  select remoto.pid into v_reassign_pid
  from public.dblink(v_reassign, 'select pg_backend_pid()') as remoto(pid integer);

  perform public.dblink_send_query(
    v_writer,
    case when p_contrato_id is null then format(
      'select qa.try_create(%L::uuid,%L::uuid,%L,%s::bigint)',
      'f4100000-0000-4000-8000-000000000001',
      p_cliente_id,
      p_modo,
      v_key
    ) when p_operacion = 'numero' then format(
      'select qa.try_number_correction(%L::uuid,%L::uuid,%s::bigint)',
      'f4100000-0000-4000-8000-000000000010',
      p_contrato_id,
      v_key
    ) else format(
      'select qa.try_correction(%L::uuid,%L::uuid,%s::bigint)',
      'f4100000-0000-4000-8000-000000000001',
      p_contrato_id,
      v_key
    ) end
  );
  perform qa.wait_for_lock(
    v_writer_pid,
    true,
    p_etiqueta || ' writer'
  );

  perform public.dblink_send_query(
    v_reassign,
    format(
      'select qa.reassign(%L::uuid,%L::uuid)',
      p_cliente_id,
      'f4100000-0000-4000-8000-000000000002'
    )
  );
  perform qa.wait_for_lock(v_reassign_pid, false, p_etiqueta || ' reasignacion');

  perform pg_advisory_unlock(v_key);
  select remoto.resultado into v_writer_result
  from public.dblink_get_result(v_writer) as remoto(resultado text);
  select remoto.resultado into v_reassign_result
  from public.dblink_get_result(v_reassign) as remoto(resultado boolean);

  perform qa.assert_true(
    v_writer_result = 'OK',
    p_etiqueta || ': writer no confirmo, obtuvo ' || coalesce(v_writer_result, 'null')
  );
  perform qa.assert_true(v_reassign_result, p_etiqueta || ': reasignacion fallo');
  perform qa.assert_true(
    (select perfil.asesor_perfil_id from public.perfiles perfil
     where perfil.id = p_cliente_id)
      = 'f4100000-0000-4000-8000-000000000002'::uuid,
    p_etiqueta || ': no confirmo la reasignacion posterior'
  );
  perform qa.assert_true(
    (select count(*) from private.contrato_pdf_jobs)
      = v_jobs + case when p_operacion = 'numero' then 0 else 1 end
      and not exists (
        select 1 from private.contrato_escritura_atomica_capacidades
      ),
    p_etiqueta || ': writer dejo job/capacidad inconsistente'
  );
  if p_contrato_id is null then
    perform qa.assert_true(
      (select count(*) from public.contratos) = v_contratos + 1,
      p_etiqueta || ': alta no creo exactamente un contrato'
    );
    perform qa.assert_true(
      (select count(*) from crm.cuentas_bancarias)
        = v_cuentas + case when p_modo = 'nueva' then 1 else 0 end,
      p_etiqueta || ': alta altero cuentas inesperadamente'
    );
  else
    perform qa.assert_true(
      (select count(*) from public.contratos) = v_contratos,
      p_etiqueta || ': correccion creo o borro contratos'
    );
  end if;
  perform qa.close_dblink(v_reassign);
  perform qa.close_dblink(v_writer);
exception when others then
  perform pg_advisory_unlock(v_key);
  perform qa.close_dblink(v_reassign);
  perform qa.close_dblink(v_writer);
  raise;
end;
$function$;

create function qa.race_authority_mutation_wins(
  p_conn text,
  p_etiqueta text,
  p_mutacion text,
  p_writer text,
  p_job_id uuid default null
)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  v_mutator text := left('f41_m_' || md5(p_etiqueta), 63);
  v_writer text := left('f41_w_' || md5(p_etiqueta), 63);
  v_key bigint := hashtextextended('authority-mutates|' || p_etiqueta, 0);
  v_mutator_pid integer;
  v_writer_pid integer;
  v_mutator_result boolean;
  v_writer_result text;
  v_mutacion_aplicada boolean;
  v_efectos bigint;
  v_pdfs bigint;
begin
  select count(*) into v_efectos from qa.efectos;
  select count(*) into v_pdfs from private.contrato_pdfs;
  perform pg_advisory_lock(v_key);
  perform public.dblink_connect(v_mutator, p_conn);
  perform public.dblink_connect(v_writer, p_conn);
  select remoto.pid into v_mutator_pid
  from public.dblink(v_mutator, 'select pg_backend_pid()') as remoto(pid integer);
  select remoto.pid into v_writer_pid
  from public.dblink(v_writer, 'select pg_backend_pid()') as remoto(pid integer);

  perform public.dblink_send_query(
    v_mutator,
    format(
      'select qa.mutar_autoridad_equipo(%L,%s::bigint)',
      p_mutacion,
      v_key
    )
  );
  perform qa.wait_for_lock(
    v_mutator_pid,
    true,
    p_etiqueta || ' mutador'
  );

  perform public.dblink_send_query(
    v_writer,
    case when p_writer = 'correccion' then format(
      'select qa.try_correction(%L::uuid,%L::uuid,null)',
      'f4100000-0000-4000-8000-000000000007',
      'f4150000-0000-4000-8000-000000000107'
    ) when p_writer = 'finalizar' then format(
      'select qa.try_finalize(%L::uuid,%L::uuid,null)',
      'f4100000-0000-4000-8000-000000000007',
      p_job_id
    ) else null end
  );
  if p_writer not in ('correccion', 'finalizar') then
    raise exception 'Writer QA invalido';
  end if;
  perform qa.wait_for_lock(
    v_writer_pid,
    p_mutacion <> 'baja_portal',
    p_etiqueta || ' writer'
  );

  perform pg_advisory_unlock(v_key);
  select remoto.resultado into v_mutator_result
  from public.dblink_get_result(v_mutator) as remoto(resultado boolean);
  select remoto.resultado into v_writer_result
  from public.dblink_get_result(v_writer) as remoto(resultado text);

  select case p_mutacion
    when 'jerarquia' then (
      select equipo.supervisor_id =
        'f4100000-0000-4000-8000-000000000008'::uuid
      from crm.equipo equipo
      where equipo.perfil_id =
        'f4100000-0000-4000-8000-000000000009'::uuid
    )
    when 'rol' then (
      select equipo.rol_crm = 'directorio'
      from crm.equipo equipo
      where equipo.perfil_id =
        'f4100000-0000-4000-8000-000000000007'::uuid
    )
    when 'baja' then (
      select equipo.activo is false
      from crm.equipo equipo
      where equipo.perfil_id =
        'f4100000-0000-4000-8000-000000000007'::uuid
    )
    when 'baja_portal' then (
      select perfil.activo is false
      from public.perfiles perfil
      where perfil.id =
        'f4100000-0000-4000-8000-000000000007'::uuid
    )
    else false
  end into v_mutacion_aplicada;

  perform qa.assert_true(
    v_mutator_result and v_mutacion_aplicada,
    p_etiqueta || ': la mutacion de autoridad no confirmo'
  );
  perform qa.assert_true(
    v_writer_result = '42501',
    p_etiqueta || ': el writer no fue denegado, obtuvo '
      || coalesce(v_writer_result, 'null')
  );
  perform qa.assert_true(
    (select count(*) from qa.efectos) = v_efectos
      and (select count(*) from private.contrato_pdfs) = v_pdfs,
    p_etiqueta || ': la denegacion dejo un efecto durable'
  );

  perform qa.close_dblink(v_writer);
  perform qa.close_dblink(v_mutator);
  perform qa.restaurar_autoridad_equipo();
exception when others then
  perform pg_advisory_unlock(v_key);
  perform qa.close_dblink(v_writer);
  perform qa.close_dblink(v_mutator);
  perform qa.restaurar_autoridad_equipo();
  raise;
end;
$function$;

create function qa.race_authority_writer_wins(
  p_conn text,
  p_etiqueta text,
  p_mutacion text,
  p_writer text,
  p_job_id uuid default null
)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  v_writer text := left('f41_w_' || md5(p_etiqueta), 63);
  v_mutator text := left('f41_m_' || md5(p_etiqueta), 63);
  v_key bigint := hashtextextended('authority-writer|' || p_etiqueta, 0);
  v_writer_pid integer;
  v_mutator_pid integer;
  v_writer_result text;
  v_mutator_result boolean;
  v_efectos bigint;
  v_pdfs bigint;
begin
  select count(*) into v_efectos from qa.efectos;
  select count(*) into v_pdfs from private.contrato_pdfs;
  perform pg_advisory_lock(v_key);
  perform public.dblink_connect(v_writer, p_conn);
  perform public.dblink_connect(v_mutator, p_conn);
  select remoto.pid into v_writer_pid
  from public.dblink(v_writer, 'select pg_backend_pid()') as remoto(pid integer);
  select remoto.pid into v_mutator_pid
  from public.dblink(v_mutator, 'select pg_backend_pid()') as remoto(pid integer);

  perform public.dblink_send_query(
    v_writer,
    case when p_writer = 'correccion' then format(
      'select qa.try_correction(%L::uuid,%L::uuid,%s::bigint)',
      'f4100000-0000-4000-8000-000000000007',
      'f4150000-0000-4000-8000-000000000107',
      v_key
    ) when p_writer = 'finalizar' then format(
      'select qa.try_finalize(%L::uuid,%L::uuid,%s::bigint)',
      'f4100000-0000-4000-8000-000000000007',
      p_job_id,
      v_key
    ) else null end
  );
  if p_writer not in ('correccion', 'finalizar') then
    raise exception 'Writer QA invalido';
  end if;
  perform qa.wait_for_lock(v_writer_pid, true, p_etiqueta || ' writer');

  perform public.dblink_send_query(
    v_mutator,
    format('select qa.mutar_autoridad_equipo(%L,null)', p_mutacion)
  );
  perform qa.wait_for_lock(
    v_mutator_pid,
    p_mutacion <> 'baja_portal',
    p_etiqueta || ' mutador'
  );

  perform pg_advisory_unlock(v_key);
  select remoto.resultado into v_writer_result
  from public.dblink_get_result(v_writer) as remoto(resultado text);
  select remoto.resultado into v_mutator_result
  from public.dblink_get_result(v_mutator) as remoto(resultado boolean);

  perform qa.assert_true(
    v_writer_result = 'OK',
    p_etiqueta || ': writer no confirmo, obtuvo '
      || coalesce(v_writer_result, 'null')
  );
  perform qa.assert_true(
    v_mutator_result,
    p_etiqueta || ': mutacion posterior no confirmo'
  );
  perform qa.assert_true(
    (select count(*) from qa.efectos)
      = v_efectos + case when p_writer = 'correccion' then 2 else 1 end,
    p_etiqueta || ': writer no dejo exactamente un efecto'
  );
  perform qa.assert_true(
    (select count(*) from private.contrato_pdfs)
      = v_pdfs + case when p_writer = 'finalizar' then 1 else 0 end,
    p_etiqueta || ': ledger PDF inesperado'
  );

  perform qa.close_dblink(v_mutator);
  perform qa.close_dblink(v_writer);
  perform qa.restaurar_autoridad_equipo();
exception when others then
  perform pg_advisory_unlock(v_key);
  perform qa.close_dblink(v_mutator);
  perform qa.close_dblink(v_writer);
  perform qa.restaurar_autoridad_equipo();
  raise;
end;
$function$;

create function qa.race_two_pdf_writers_same_contract(
  p_conn text,
  p_etiqueta text,
  p_job_uno uuid,
  p_job_dos uuid
)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  v_uno text := left('f41_p1_' || md5(p_etiqueta), 63);
  v_dos text := left('f41_p2_' || md5(p_etiqueta), 63);
  v_key bigint := hashtextextended('pdf-two-writers|' || p_etiqueta, 0);
  v_uno_pid integer;
  v_dos_pid integer;
  v_uno_result text;
  v_dos_result text;
  v_efectos bigint;
  v_pdfs bigint;
begin
  select count(*) into v_efectos from qa.efectos;
  select count(*) into v_pdfs from private.contrato_pdfs;
  perform pg_advisory_lock(v_key);
  perform public.dblink_connect(v_uno, p_conn);
  perform public.dblink_connect(v_dos, p_conn);
  select remoto.pid into v_uno_pid
  from public.dblink(v_uno, 'select pg_backend_pid()') as remoto(pid integer);
  select remoto.pid into v_dos_pid
  from public.dblink(v_dos, 'select pg_backend_pid()') as remoto(pid integer);

  -- El primer worker se pausa justo antes del UPDATE interno canonico. Con la
  -- guardia segura ya posee UPDATE; con la version SHARE antigua aun no.
  perform public.dblink_send_query(
    v_uno,
    format(
      'select qa.try_finalize_pre_update_pause(%L::uuid,%L::uuid,%s::bigint)',
      'f4100000-0000-4000-8000-000000000007',
      p_job_uno,
      v_key
    )
  );
  perform qa.wait_for_lock(v_uno_pid, true, p_etiqueta || ' worker uno');

  perform public.dblink_send_query(
    v_dos,
    format(
      'select qa.try_finalize(%L::uuid,%L::uuid,null)',
      'f4100000-0000-4000-8000-000000000007',
      p_job_dos
    )
  );
  perform qa.wait_for_lock(v_dos_pid, false, p_etiqueta || ' worker dos');

  perform pg_advisory_unlock(v_key);
  select remoto.resultado into v_uno_result
  from public.dblink_get_result(v_uno) as remoto(resultado text);
  select remoto.resultado into v_dos_result
  from public.dblink_get_result(v_dos) as remoto(resultado text);

  perform qa.assert_true(
    v_uno_result = 'OK' and v_dos_result = 'OK',
    p_etiqueta || ': hubo deadlock/fallo: '
      || coalesce(v_uno_result, 'null') || '/' || coalesce(v_dos_result, 'null')
  );
  perform qa.assert_true(
    (select count(*) from qa.efectos) = v_efectos + 2
      and (select count(*) from private.contrato_pdfs) = v_pdfs + 2,
    p_etiqueta || ': los writers no serializaron ambos ledgers'
  );

  perform qa.close_dblink(v_dos);
  perform qa.close_dblink(v_uno);
exception when others then
  perform pg_advisory_unlock(v_key);
  perform qa.close_dblink(v_dos);
  perform qa.close_dblink(v_uno);
  raise;
end;
$function$;

create function qa.race_correction_before_payment(
  p_conn text,
  p_etiqueta text
)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  v_writer text := left('f41_cp_w_' || md5(p_etiqueta), 63);
  v_payment text := left('f41_cp_p_' || md5(p_etiqueta), 63);
  v_payment_conn text := pg_catalog.format(
    '%s options=%L', p_conn, '-c role=authenticated'
  );
  v_key bigint := hashtextextended('correction-payment|' || p_etiqueta, 0);
  v_writer_pid integer;
  v_payment_pid integer;
  v_payment_role text;
  v_writer_result text;
  v_payment_result text;
begin
  perform pg_advisory_lock(v_key);
  perform public.dblink_connect(v_writer, p_conn);
  perform public.dblink_connect(v_payment, v_payment_conn);
  select remoto.pid into v_writer_pid
  from public.dblink(v_writer, 'select pg_backend_pid()') as remoto(pid integer);
  select remoto.pid into v_payment_pid
  from public.dblink(v_payment, 'select pg_backend_pid()') as remoto(pid integer);
  select remoto.rol into v_payment_role
  from public.dblink(v_payment, 'select current_user') as remoto(rol text);
  perform qa.assert_true(
    v_payment_role = 'authenticated',
    p_etiqueta || ': dblink de cobro no asumio authenticated'
  );

  -- La correccion ya sostiene contrato y se pausa antes de tocar la cuota.
  perform public.dblink_send_query(
    v_writer,
    format(
      'select qa.try_correction(%L::uuid,%L::uuid,%s::bigint)',
      'f4100000-0000-4000-8000-000000000002',
      'f4150000-0000-4000-8000-000000000106',
      v_key
    )
  );
  perform qa.wait_for_lock(v_writer_pid, true, p_etiqueta || ' correction');

  -- Con la policy segura espera el mutex de cobros antes de que PostgreSQL
  -- intente adquirir la cuota. El diseño antiguo formaba cuota→contrato.
  perform public.dblink_send_query(
    v_payment,
    format(
      'select qa.try_payment(%L::uuid,%L::uuid)',
      'f4100000-0000-4000-8000-000000000014',
      'f4190000-0000-4000-8000-000000000106'
    )
  );
  perform qa.wait_for_lock(v_payment_pid, true, p_etiqueta || ' payment');

  perform pg_advisory_unlock(v_key);
  select remoto.resultado into v_writer_result
  from public.dblink_get_result(v_writer) as remoto(resultado text);
  select remoto.resultado into v_payment_result
  from public.dblink_get_result(v_payment) as remoto(resultado text);

  perform qa.assert_true(
    v_writer_result = 'OK' and v_payment_result = 'OK',
    p_etiqueta || ': deadlock/fallo correction→payment: '
      || coalesce(v_writer_result, 'null') || '/'
      || coalesce(v_payment_result, 'null')
  );
  perform qa.close_dblink(v_payment);
  perform qa.close_dblink(v_writer);
exception when others then
  perform pg_advisory_unlock(v_key);
  perform qa.close_dblink(v_payment);
  perform qa.close_dblink(v_writer);
  raise;
end;
$function$;

create function qa.race_payment_before_correction(
  p_conn text,
  p_etiqueta text
)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  v_locker text := left('f41_pc_l_' || md5(p_etiqueta), 63);
  v_payment text := left('f41_pc_p_' || md5(p_etiqueta), 63);
  v_writer text := left('f41_pc_w_' || md5(p_etiqueta), 63);
  v_payment_conn text := pg_catalog.format(
    '%s options=%L', p_conn, '-c role=authenticated'
  );
  v_key bigint := hashtextextended('payment-correction|' || p_etiqueta, 0);
  v_locker_pid integer;
  v_payment_pid integer;
  v_writer_pid integer;
  v_payment_role text;
  v_locker_result boolean;
  v_payment_result text;
  v_writer_result text;
begin
  perform pg_advisory_lock(v_key);
  perform public.dblink_connect(v_locker, p_conn);
  perform public.dblink_connect(v_payment, v_payment_conn);
  perform public.dblink_connect(v_writer, p_conn);
  select remoto.pid into v_locker_pid
  from public.dblink(v_locker, 'select pg_backend_pid()') as remoto(pid integer);
  select remoto.pid into v_payment_pid
  from public.dblink(v_payment, 'select pg_backend_pid()') as remoto(pid integer);
  select remoto.pid into v_writer_pid
  from public.dblink(v_writer, 'select pg_backend_pid()') as remoto(pid integer);
  select remoto.rol into v_payment_role
  from public.dblink(v_payment, 'select current_user') as remoto(rol text);
  perform qa.assert_true(
    v_payment_role = 'authenticated',
    p_etiqueta || ': dblink de cobro no asumio authenticated'
  );

  -- El locker artificial deja observar que el cobro ya sostiene su mutex
  -- exclusivo antes de intentar la fila hija, sin pausas en codigo productivo.
  perform public.dblink_send_query(
    v_locker,
    format(
      'select qa.lock_payment_row_and_pause(%L::uuid,%s::bigint)',
      'f4190000-0000-4000-8000-000000000106',
      v_key
    )
  );
  perform qa.wait_for_lock(v_locker_pid, true, p_etiqueta || ' row locker');

  perform public.dblink_send_query(
    v_payment,
    format(
      'select qa.try_payment(%L::uuid,%L::uuid)',
      'f4100000-0000-4000-8000-000000000014',
      'f4190000-0000-4000-8000-000000000106'
    )
  );
  perform qa.wait_for_lock(v_payment_pid, false, p_etiqueta || ' payment');

  perform public.dblink_send_query(
    v_writer,
    format(
      'select qa.try_correction(%L::uuid,%L::uuid,null)',
      'f4100000-0000-4000-8000-000000000002',
      'f4150000-0000-4000-8000-000000000106'
    )
  );
  perform qa.wait_for_lock(v_writer_pid, true, p_etiqueta || ' correction');

  perform pg_advisory_unlock(v_key);
  select remoto.resultado into v_locker_result
  from public.dblink_get_result(v_locker) as remoto(resultado boolean);
  select remoto.resultado into v_payment_result
  from public.dblink_get_result(v_payment) as remoto(resultado text);
  select remoto.resultado into v_writer_result
  from public.dblink_get_result(v_writer) as remoto(resultado text);

  perform qa.assert_true(
    v_locker_result
      and v_payment_result = 'OK'
      and v_writer_result = 'OK',
    p_etiqueta || ': deadlock/fallo payment→correction: '
      || coalesce(v_payment_result, 'null') || '/'
      || coalesce(v_writer_result, 'null')
  );
  perform qa.close_dblink(v_writer);
  perform qa.close_dblink(v_payment);
  perform qa.close_dblink(v_locker);
exception when others then
  perform pg_advisory_unlock(v_key);
  perform qa.close_dblink(v_writer);
  perform qa.close_dblink(v_payment);
  perform qa.close_dblink(v_locker);
  raise;
end;
$function$;

create function qa.race_payment_offboarding_wins(
  p_conn text,
  p_etiqueta text,
  p_cuota_id uuid
)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  v_actor_id constant uuid :=
    'f4100000-0000-4000-8000-000000000015'::uuid;
  v_offboard text := left('f41_po_' || md5(p_etiqueta), 63);
  v_payment text := left('f41_pp_' || md5(p_etiqueta), 63);
  v_payment_conn text := pg_catalog.format(
    '%s options=%L', p_conn, '-c role=authenticated'
  );
  v_pause bigint := hashtextextended(
    'payment-offboarding|' || p_etiqueta,
    0
  );
  v_offboard_pid integer;
  v_payment_pid integer;
  v_offboard_result boolean;
  v_payment_result text;
  v_antes public.cronograma_pagos%rowtype;
begin
  select * into strict v_antes
  from public.cronograma_pagos where id = p_cuota_id;
  perform pg_advisory_lock(v_pause);
  perform public.dblink_connect(v_offboard, p_conn);
  perform public.dblink_connect(v_payment, v_payment_conn);
  select remoto.pid into v_offboard_pid
  from public.dblink(v_offboard, 'select pg_backend_pid()')
    as remoto(pid integer);
  select remoto.pid into v_payment_pid
  from public.dblink(v_payment, 'select pg_backend_pid()')
    as remoto(pid integer);

  perform public.dblink_send_query(
    v_offboard,
    format(
      'select qa.offboard_actor_and_pause(%L::uuid,%s::bigint)',
      v_actor_id,
      v_pause
    )
  );
  perform qa.wait_for_lock(
    v_offboard_pid,
    true,
    p_etiqueta || ': baja no alcanzo la pausa'
  );

  perform public.dblink_send_query(
    v_payment,
    format(
      'select qa.try_payment(%L::uuid,%L::uuid)',
      v_actor_id,
      p_cuota_id
    )
  );
  perform qa.wait_for_lock(
    v_payment_pid,
    false,
    p_etiqueta || ': cobro no espero el perfil actor'
  );

  perform pg_advisory_unlock(v_pause);
  select remoto.resultado into v_offboard_result
  from public.dblink_get_result(v_offboard) as remoto(resultado boolean);
  select remoto.resultado into v_payment_result
  from public.dblink_get_result(v_payment) as remoto(resultado text);

  perform qa.assert_true(
    v_offboard_result,
    p_etiqueta || ': la baja Portal no confirmo'
  );
  perform qa.assert_true(
    v_payment_result = '42501',
    p_etiqueta || ': cobro revocado obtuvo '
      || coalesce(v_payment_result, 'null')
  );
  perform qa.assert_true(
    exists (
      select 1
      from public.cronograma_pagos cuota
      where cuota.id = p_cuota_id
        and cuota.estado is not distinct from v_antes.estado
        and cuota.fecha_pago_real is not distinct from v_antes.fecha_pago_real
        and cuota.monto_pagado is not distinct from v_antes.monto_pagado
        and cuota.registrado_por is not distinct from v_antes.registrado_por
    ),
    p_etiqueta || ': el cobro denegado dejo efectos'
  );

  perform qa.close_dblink(v_payment);
  perform qa.close_dblink(v_offboard);
  update public.perfiles set activo = true where id = v_actor_id;
exception when others then
  perform pg_advisory_unlock(v_pause);
  perform qa.close_dblink(v_payment);
  perform qa.close_dblink(v_offboard);
  update public.perfiles set activo = true where id = v_actor_id;
  update public.cronograma_pagos
  set estado = v_antes.estado,
      fecha_pago_real = v_antes.fecha_pago_real,
      monto_pagado = v_antes.monto_pagado,
      registrado_por = v_antes.registrado_por
  where id = p_cuota_id;
  raise;
end;
$function$;

create function qa.race_payment_writer_wins_offboarding(
  p_conn text,
  p_etiqueta text,
  p_cuota_id uuid
)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  v_actor_id constant uuid :=
    'f4100000-0000-4000-8000-000000000015'::uuid;
  v_payment text := left('f41_pw_' || md5(p_etiqueta), 63);
  v_offboard text := left('f41_pb_' || md5(p_etiqueta), 63);
  v_payment_conn text := pg_catalog.format(
    '%s options=%L', p_conn, '-c role=authenticated'
  );
  v_pause bigint := hashtextextended(
    'payment-writer-offboarding|' || p_etiqueta,
    0
  );
  v_payment_pid integer;
  v_offboard_pid integer;
  v_payment_result text;
  v_offboard_result boolean;
  v_antes public.cronograma_pagos%rowtype;
begin
  select * into strict v_antes
  from public.cronograma_pagos where id = p_cuota_id;
  perform pg_advisory_lock(v_pause);
  perform public.dblink_connect(v_payment, v_payment_conn);
  perform public.dblink_connect(v_offboard, p_conn);
  select remoto.pid into v_payment_pid
  from public.dblink(v_payment, 'select pg_backend_pid()')
    as remoto(pid integer);
  select remoto.pid into v_offboard_pid
  from public.dblink(v_offboard, 'select pg_backend_pid()')
    as remoto(pid integer);

  perform public.dblink_send_query(
    v_payment,
    format(
      'select qa.try_payment_and_pause(%L::uuid,%L::uuid,%s::bigint)',
      v_actor_id,
      p_cuota_id,
      v_pause
    )
  );
  perform qa.wait_for_lock(
    v_payment_pid,
    true,
    p_etiqueta || ': cobro no alcanzo la pausa'
  );

  perform public.dblink_send_query(
    v_offboard,
    format(
      'with cambio as (update public.perfiles set activo=false where id=%L::uuid returning 1) select exists(select 1 from cambio)',
      v_actor_id
    )
  );
  perform qa.wait_for_lock(
    v_offboard_pid,
    false,
    p_etiqueta || ': baja no espero el perfil actor'
  );

  perform pg_advisory_unlock(v_pause);
  select remoto.resultado into v_payment_result
  from public.dblink_get_result(v_payment) as remoto(resultado text);
  select remoto.resultado into v_offboard_result
  from public.dblink_get_result(v_offboard) as remoto(resultado boolean);

  perform qa.assert_true(
    v_payment_result = 'OK' and v_offboard_result,
    p_etiqueta || ': orden cobro→baja fallo: '
      || coalesce(v_payment_result, 'null')
  );
  perform qa.assert_true(
    exists (
      select 1
      from public.cronograma_pagos cuota
      where cuota.id = p_cuota_id
        and cuota.estado = 'pagado'
        and cuota.fecha_pago_real = current_date
        and cuota.monto_pagado = cuota.monto_programado
        and cuota.registrado_por = v_actor_id
    ),
    p_etiqueta || ': el cobro ganador no quedo completo'
  );

  perform qa.close_dblink(v_offboard);
  perform qa.close_dblink(v_payment);
  update public.perfiles set activo = true where id = v_actor_id;
  update public.cronograma_pagos
  set estado = v_antes.estado,
      fecha_pago_real = v_antes.fecha_pago_real,
      monto_pagado = v_antes.monto_pagado,
      registrado_por = v_antes.registrado_por
  where id = p_cuota_id;
exception when others then
  perform pg_advisory_unlock(v_pause);
  perform qa.close_dblink(v_offboard);
  perform qa.close_dblink(v_payment);
  update public.perfiles set activo = true where id = v_actor_id;
  update public.cronograma_pagos
  set estado = v_antes.estado,
      fecha_pago_real = v_antes.fecha_pago_real,
      monto_pagado = v_antes.monto_pagado,
      registrado_por = v_antes.registrado_por
  where id = p_cuota_id;
  raise;
end;
$function$;

create function qa.race_close_before_payment(
  p_conn text,
  p_etiqueta text,
  p_contrato_id uuid,
  p_contrato_nuevo_id uuid,
  p_cuota_id uuid
)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  v_actor_id constant uuid :=
    'f4100000-0000-4000-8000-000000000014'::uuid;
  v_close text := left('f41_cl_' || md5(p_etiqueta), 63);
  v_payment text := left('f41_cp_' || md5(p_etiqueta), 63);
  v_payment_conn text := pg_catalog.format(
    '%s options=%L', p_conn, '-c role=authenticated'
  );
  v_pause bigint := hashtextextended('close-payment|' || p_etiqueta, 0);
  v_close_pid integer;
  v_payment_pid integer;
  v_close_result text;
  v_payment_result text;
begin
  perform pg_advisory_lock(v_pause);
  perform public.dblink_connect(v_close, p_conn);
  perform public.dblink_connect(v_payment, v_payment_conn);
  select remoto.pid into v_close_pid
  from public.dblink(v_close, 'select pg_backend_pid()') as remoto(pid integer);
  select remoto.pid into v_payment_pid
  from public.dblink(v_payment, 'select pg_backend_pid()')
    as remoto(pid integer);

  perform public.dblink_send_query(
    v_close,
    format(
      'select qa.try_close(%L::uuid,%L::uuid,%L::uuid,%s::bigint)',
      v_actor_id,
      p_contrato_id,
      p_contrato_nuevo_id,
      v_pause
    )
  );
  perform qa.wait_for_lock(
    v_close_pid,
    true,
    p_etiqueta || ': cierre no alcanzo la pausa'
  );
  perform public.dblink_send_query(
    v_payment,
    format(
      'select qa.try_payment(%L::uuid,%L::uuid)',
      v_actor_id,
      p_cuota_id
    )
  );
  perform qa.wait_for_lock(
    v_payment_pid,
    true,
    p_etiqueta || ': cobro no espero mutex de cierre'
  );

  perform pg_advisory_unlock(v_pause);
  select remoto.resultado into v_close_result
  from public.dblink_get_result(v_close) as remoto(resultado text);
  select remoto.resultado into v_payment_result
  from public.dblink_get_result(v_payment) as remoto(resultado text);

  perform qa.assert_true(
    v_close_result = 'OK' and v_payment_result = 'OK',
    p_etiqueta || ': deadlock/fallo cierre→cobro: '
      || coalesce(v_close_result, 'null') || '/'
      || coalesce(v_payment_result, 'null')
  );
  perform qa.assert_true(
    exists (
      select 1 from public.cronograma_pagos cuota
      where cuota.id = p_cuota_id
        and cuota.estado = 'pagado'
        and cuota.registrado_por = v_actor_id
    ) and exists (
      select 1 from public.contratos contrato
      where contrato.id = p_contrato_id
        and contrato.estado = 'renovado'
        and contrato.renovado_a_id = p_contrato_nuevo_id
    ),
    p_etiqueta || ': cierre/cobro posterior no persistio'
  );

  perform qa.close_dblink(v_payment);
  perform qa.close_dblink(v_close);
  update public.cronograma_pagos
  set estado = 'pendiente',
      fecha_pago_real = null,
      monto_pagado = null,
      registrado_por = null
  where id = p_cuota_id;
  update public.contratos
  set estado = 'activo',
      renovado_a_id = null,
      cerrado_en = null,
      cerrado_por = null
  where id = p_contrato_id;
exception when others then
  perform pg_advisory_unlock(v_pause);
  perform qa.close_dblink(v_payment);
  perform qa.close_dblink(v_close);
  update public.cronograma_pagos
  set estado = 'pendiente',
      fecha_pago_real = null,
      monto_pagado = null,
      registrado_por = null
  where id = p_cuota_id;
  update public.contratos
  set estado = 'activo',
      renovado_a_id = null,
      cerrado_en = null,
      cerrado_por = null
  where id = p_contrato_id;
  raise;
end;
$function$;

create function qa.race_payment_before_close(
  p_conn text,
  p_etiqueta text,
  p_contrato_id uuid,
  p_contrato_nuevo_id uuid,
  p_cuota_id uuid
)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  v_actor_id constant uuid :=
    'f4100000-0000-4000-8000-000000000014'::uuid;
  v_payment text := left('f41_pc_' || md5(p_etiqueta), 63);
  v_close text := left('f41_cw_' || md5(p_etiqueta), 63);
  v_payment_conn text := pg_catalog.format(
    '%s options=%L', p_conn, '-c role=authenticated'
  );
  v_pause bigint := hashtextextended('payment-close|' || p_etiqueta, 0);
  v_payment_pid integer;
  v_close_pid integer;
  v_payment_result text;
  v_close_result text;
begin
  perform pg_advisory_lock(v_pause);
  perform public.dblink_connect(v_payment, v_payment_conn);
  perform public.dblink_connect(v_close, p_conn);
  select remoto.pid into v_payment_pid
  from public.dblink(v_payment, 'select pg_backend_pid()')
    as remoto(pid integer);
  select remoto.pid into v_close_pid
  from public.dblink(v_close, 'select pg_backend_pid()') as remoto(pid integer);

  perform public.dblink_send_query(
    v_payment,
    format(
      'select qa.try_payment_and_pause(%L::uuid,%L::uuid,%s::bigint)',
      v_actor_id,
      p_cuota_id,
      v_pause
    )
  );
  perform qa.wait_for_lock(
    v_payment_pid,
    true,
    p_etiqueta || ': cobro no alcanzo la pausa'
  );
  perform public.dblink_send_query(
    v_close,
    format(
      'select qa.try_close(%L::uuid,%L::uuid,%L::uuid,null)',
      v_actor_id,
      p_contrato_id,
      p_contrato_nuevo_id
    )
  );
  perform qa.wait_for_lock(
    v_close_pid,
    true,
    p_etiqueta || ': cierre no espero mutex de cobro'
  );

  perform pg_advisory_unlock(v_pause);
  select remoto.resultado into v_payment_result
  from public.dblink_get_result(v_payment) as remoto(resultado text);
  select remoto.resultado into v_close_result
  from public.dblink_get_result(v_close) as remoto(resultado text);

  perform qa.assert_true(
    v_payment_result = 'OK' and v_close_result = 'OK',
    p_etiqueta || ': deadlock/fallo cobro→cierre: '
      || coalesce(v_payment_result, 'null') || '/'
      || coalesce(v_close_result, 'null')
  );
  perform qa.assert_true(
    exists (
      select 1 from public.cronograma_pagos cuota
      where cuota.id = p_cuota_id
        and cuota.estado = 'pagado'
        and cuota.registrado_por = v_actor_id
    ) and exists (
      select 1 from public.contratos contrato
      where contrato.id = p_contrato_id
        and contrato.estado = 'renovado'
        and contrato.renovado_a_id = p_contrato_nuevo_id
    ),
    p_etiqueta || ': cierre posterior quedo incoherente con el cobro'
  );

  perform qa.close_dblink(v_close);
  perform qa.close_dblink(v_payment);
  update public.cronograma_pagos
  set estado = 'pendiente',
      fecha_pago_real = null,
      monto_pagado = null,
      registrado_por = null
  where id = p_cuota_id;
  update public.contratos
  set estado = 'activo',
      renovado_a_id = null,
      cerrado_en = null,
      cerrado_por = null
  where id = p_contrato_id;
exception when others then
  perform pg_advisory_unlock(v_pause);
  perform qa.close_dblink(v_close);
  perform qa.close_dblink(v_payment);
  update public.cronograma_pagos
  set estado = 'pendiente',
      fecha_pago_real = null,
      monto_pagado = null,
      registrado_por = null
  where id = p_cuota_id;
  update public.contratos
  set estado = 'activo',
      renovado_a_id = null,
      cerrado_en = null,
      cerrado_por = null
  where id = p_contrato_id;
  raise;
end;
$function$;

create function qa.race_two_exclusive_mutators(
  p_conn text,
  p_etiqueta text
)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  v_uno text := left('f41_x1_' || md5(p_etiqueta), 63);
  v_dos text := left('f41_x2_' || md5(p_etiqueta), 63);
  v_pause bigint := hashtextextended('two-exclusive|' || p_etiqueta, 0);
  v_uno_pid integer;
  v_dos_pid integer;
  v_uno_result text;
  v_dos_result text;
  v_efectos bigint;
begin
  select count(*) into v_efectos from qa.efectos;
  perform pg_advisory_lock(v_pause);
  perform public.dblink_connect(v_uno, p_conn);
  perform public.dblink_connect(v_dos, p_conn);
  select remoto.pid into v_uno_pid
  from public.dblink(v_uno, 'select pg_backend_pid()') as remoto(pid integer);
  select remoto.pid into v_dos_pid
  from public.dblink(v_dos, 'select pg_backend_pid()') as remoto(pid integer);

  perform public.dblink_send_query(
    v_uno,
    format(
      'select qa.try_exclusive_mutator(%L,%L::uuid,%s::bigint)',
      'rol',
      'f4100000-0000-4000-8000-000000000010',
      v_pause
    )
  );
  perform qa.wait_for_lock(
    v_uno_pid,
    true,
    p_etiqueta || ': primer mutador no alcanzo la pausa'
  );
  perform qa.assert_true(
    exists (
      select 1 from pg_catalog.pg_locks bloqueo
      where bloqueo.pid = v_uno_pid
        and bloqueo.locktype = 'advisory'
        and bloqueo.mode = 'ExclusiveLock'
        and bloqueo.granted
    ) and not exists (
      select 1 from pg_catalog.pg_locks bloqueo
      where bloqueo.pid = v_uno_pid
        and bloqueo.locktype = 'advisory'
        and bloqueo.mode = 'ShareLock'
        and bloqueo.granted
    ),
    p_etiqueta || ': primer mutador no tomo X desde el inicio'
  );

  perform public.dblink_send_query(
    v_dos,
    format(
      'select qa.try_exclusive_mutator(%L,%L::uuid,null)',
      'jerarquia',
      'f4100000-0000-4000-8000-000000000011'
    )
  );
  perform qa.wait_for_lock(
    v_dos_pid,
    true,
    p_etiqueta || ': segundo mutador no espero X'
  );
  perform qa.assert_true(
    exists (
      select 1 from pg_catalog.pg_locks bloqueo
      where bloqueo.pid = v_dos_pid
        and bloqueo.locktype = 'advisory'
        and bloqueo.mode = 'ExclusiveLock'
        and not bloqueo.granted
    ) and not exists (
      select 1 from pg_catalog.pg_locks bloqueo
      where bloqueo.pid = v_dos_pid
        and bloqueo.locktype = 'advisory'
        and bloqueo.mode = 'ShareLock'
        and bloqueo.granted
    ),
    p_etiqueta || ': segundo mutador intento upgrade S→X'
  );

  perform pg_advisory_unlock(v_pause);
  select remoto.resultado into v_uno_result
  from public.dblink_get_result(v_uno) as remoto(resultado text);
  select remoto.resultado into v_dos_result
  from public.dblink_get_result(v_dos) as remoto(resultado text);

  perform qa.assert_true(
    v_uno_result = 'OK' and v_dos_result = 'OK',
    p_etiqueta || ': mutadores exclusivos fallaron: '
      || coalesce(v_uno_result, 'null') || '/'
      || coalesce(v_dos_result, 'null')
  );
  perform qa.assert_true(
    (select count(*) from qa.efectos) = v_efectos + 2,
    p_etiqueta || ': no persistieron exactamente ambos efectos'
  );

  perform qa.close_dblink(v_dos);
  perform qa.close_dblink(v_uno);
  perform qa.restaurar_mutador_exclusivo();
exception when others then
  perform pg_advisory_unlock(v_pause);
  perform qa.close_dblink(v_dos);
  perform qa.close_dblink(v_uno);
  perform qa.restaurar_mutador_exclusivo();
  raise;
end;
$function$;

create function qa.race_delete_restore_vs_writer(
  p_conn text,
  p_etiqueta text,
  p_contrato_origen_id uuid,
  p_contrato_nuevo_id uuid,
  p_writer text,
  p_cierre_nuevo_id uuid,
  p_finalizador_gana boolean
)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  v_actor_id constant uuid :=
    'f4100000-0000-4000-8000-000000000014'::uuid;
  v_finalizador text := left('f41_df_' || md5(p_etiqueta), 63);
  v_writer text := left('f41_dw_' || md5(p_etiqueta), 63);
  v_pause bigint := hashtextextended('delete-restore|' || p_etiqueta, 0);
  v_finalizador_pid integer;
  v_writer_pid integer;
  v_token uuid;
  v_preparar_xid bigint;
  v_finalizar_xid bigint;
  v_finalizador_result text;
  v_writer_result text;
  v_writer_esperado text;
  v_efectos bigint;
  v_estado_esperado text;
begin
  if p_writer not in ('correccion', 'cierre') then
    raise exception 'Writer de restauracion QA invalido';
  end if;
  if p_writer = 'cierre' and p_cierre_nuevo_id is null then
    raise exception 'El cierre QA requiere contrato nuevo';
  end if;
  select count(*) into v_efectos from qa.efectos;
  perform public.dblink_connect(v_finalizador, p_conn);
  perform public.dblink_connect(v_writer, p_conn);
  select remoto.pid into v_finalizador_pid
  from public.dblink(v_finalizador, 'select pg_backend_pid()')
    as remoto(pid integer);
  select remoto.pid into v_writer_pid
  from public.dblink(v_writer, 'select pg_backend_pid()')
    as remoto(pid integer);

  -- El flujo Edge confirma preparar antes del IO externo y abre otra
  -- transaccion para finalizar. Estas dos consultas dblink autocommit modelan
  -- exactamente esa frontera, y sus XID se comparan despues.
  select remoto.token, remoto.transaccion
    into v_token, v_preparar_xid
  from public.dblink(
    v_finalizador,
    format(
      'select (p.resultado->>''token'')::uuid, txid_current() from (select crm.contrato_eliminacion_preparar(%L::uuid,%L::uuid) as resultado) p',
      p_contrato_nuevo_id,
      v_actor_id
    )
  ) as remoto(token uuid, transaccion bigint);
  perform qa.assert_true(
    exists (
      select 1 from private.contrato_eliminaciones e
      where e.contrato_id = p_contrato_nuevo_id
        and e.token = v_token
        and e.solicitado_por = v_actor_id
    ),
    p_etiqueta || ': preparar no dejo capability durable'
  );

  perform pg_advisory_lock(v_pause);
  if p_finalizador_gana then
    perform public.dblink_send_query(
      v_finalizador,
      format(
        'select qa.try_delete_finalize(%L::uuid,%L::uuid,%L::uuid,%s::bigint)',
        p_contrato_nuevo_id,
        v_token,
        v_actor_id,
        v_pause
      )
    );
    perform qa.wait_for_lock(
      v_finalizador_pid,
      true,
      p_etiqueta || ': finalizador no alcanzo la pausa'
    );
    perform public.dblink_send_query(
      v_writer,
      case when p_writer = 'correccion' then format(
        'select qa.try_contract_correction(%L::uuid,%L::uuid,null)',
        v_actor_id,
        p_contrato_origen_id
      ) else format(
        'select qa.try_close(%L::uuid,%L::uuid,%L::uuid,null)',
        v_actor_id,
        p_contrato_origen_id,
        p_cierre_nuevo_id
      ) end
    );
    perform qa.wait_for_lock(
      v_writer_pid,
      true,
      p_etiqueta || ': writer no espero cobros X'
    );
  else
    perform public.dblink_send_query(
      v_writer,
      case when p_writer = 'correccion' then format(
        'select qa.try_contract_correction(%L::uuid,%L::uuid,%s::bigint)',
        v_actor_id,
        p_contrato_origen_id,
        v_pause
      ) else format(
        'select qa.try_close(%L::uuid,%L::uuid,%L::uuid,%s::bigint)',
        v_actor_id,
        p_contrato_origen_id,
        p_cierre_nuevo_id,
        v_pause
      ) end
    );
    perform qa.wait_for_lock(
      v_writer_pid,
      true,
      p_etiqueta || ': writer no alcanzo la pausa'
    );
    perform public.dblink_send_query(
      v_finalizador,
      format(
        'select qa.try_delete_finalize(%L::uuid,%L::uuid,%L::uuid,null)',
        p_contrato_nuevo_id,
        v_token,
        v_actor_id
      )
    );
    perform qa.wait_for_lock(
      v_finalizador_pid,
      true,
      p_etiqueta || ': finalizador no espero cobros compartido'
    );
  end if;

  perform pg_advisory_unlock(v_pause);
  select remoto.resultado into v_finalizador_result
  from public.dblink_get_result(v_finalizador) as remoto(resultado text);
  select remoto.resultado into v_writer_result
  from public.dblink_get_result(v_writer) as remoto(resultado text);

  v_writer_esperado := case
    when p_writer = 'cierre' and not p_finalizador_gana then 'P0409'
    else 'OK'
  end;
  perform qa.assert_true(
    v_finalizador_result like 'OK:%'
      and v_writer_result = v_writer_esperado,
    p_etiqueta || ': deadlock/fallo finalizador/writer: '
      || coalesce(v_finalizador_result, 'null') || '/'
      || coalesce(v_writer_result, 'null')
  );
  begin
    v_finalizar_xid := split_part(v_finalizador_result, ':', 2)::bigint;
  exception when invalid_text_representation then
    raise exception
      'F41-QA: % devolvio XID final invalido: %',
      p_etiqueta,
      v_finalizador_result;
  end;
  perform qa.assert_true(
    v_preparar_xid is distinct from v_finalizar_xid,
    p_etiqueta || ': preparar y finalizar se combinaron en una transaccion'
  );

  v_estado_esperado := case
    when p_finalizador_gana and p_writer = 'cierre' then 'trasladado'
    else 'pendiente'
  end;
  perform qa.assert_true(
    not exists (
      select 1 from public.contratos c where c.id = p_contrato_nuevo_id
    ) and not exists (
      select 1 from crm.operaciones_cartera o
      where o.contrato_nuevo_id = p_contrato_nuevo_id
    ) and exists (
      select 1 from public.contratos c
      where c.id = p_contrato_origen_id
        and c.estado = case
          when p_finalizador_gana and p_writer = 'cierre'
            then 'renovado'
          else 'activo'
        end
        and c.renovado_a_id is not distinct from case
          when p_finalizador_gana and p_writer = 'cierre'
            then p_cierre_nuevo_id
          else null::uuid
        end
        and (
          (
            p_finalizador_gana
            and p_writer = 'cierre'
            and c.cerrado_en is not null
            and c.cerrado_por = v_actor_id
          )
          or (
            not (p_finalizador_gana and p_writer = 'cierre')
            and c.cerrado_en is null
            and c.cerrado_por is null
          )
        )
    ) and exists (
      select 1 from public.cronograma_pagos cp
      where cp.contrato_id = p_contrato_origen_id
    ) and not exists (
      select 1 from public.cronograma_pagos cp
      where cp.contrato_id = p_contrato_origen_id
        and cp.estado <> v_estado_esperado
    ),
    p_etiqueta || ': restauracion hijo→padre quedo incoherente'
  );
  perform qa.assert_true(
    (select count(*) from qa.efectos)
      = v_efectos + case when p_writer = 'correccion' then 1 else 0 end,
    p_etiqueta || ': writer dejo un numero inesperado de efectos'
  );

  perform qa.close_dblink(v_writer);
  perform qa.close_dblink(v_finalizador);
exception when others then
  perform pg_advisory_unlock(v_pause);
  perform qa.close_dblink(v_writer);
  perform qa.close_dblink(v_finalizador);
  perform qa.cleanup_renewal_case(
    p_contrato_origen_id,
    p_contrato_nuevo_id
  );
  raise;
end;
$function$;

create function qa.assert_delete_prepare_finalize_same_transaction(
  p_contrato_origen_id uuid,
  p_contrato_nuevo_id uuid,
  p_actor_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_preparacion jsonb;
  v_xid_inicial bigint := txid_current();
  v_xid_preparado bigint;
  v_xid_finalizado bigint;
begin
  v_preparacion := crm.contrato_eliminacion_preparar(
    p_contrato_nuevo_id,
    p_actor_id
  );
  v_xid_preparado := txid_current();
  perform crm.contrato_eliminacion_finalizar(
    p_contrato_nuevo_id,
    (v_preparacion->>'token')::uuid,
    p_actor_id
  );
  v_xid_finalizado := txid_current();

  perform qa.assert_true(
    v_xid_inicial = v_xid_preparado
      and v_xid_preparado = v_xid_finalizado,
    'delete misma TX no conservo un XID unico'
  );
  perform qa.assert_true(
    not exists (
      select 1 from public.contratos c where c.id = p_contrato_nuevo_id
    ) and not exists (
      select 1 from private.contrato_eliminaciones e
      where e.contrato_id = p_contrato_nuevo_id
    ) and not exists (
      select 1 from crm.operaciones_cartera o
      where o.contrato_nuevo_id = p_contrato_nuevo_id
    ) and exists (
      select 1 from public.contratos c
      where c.id = p_contrato_origen_id
        and c.estado = 'activo'
        and c.renovado_a_id is null
        and c.cerrado_en is null
        and c.cerrado_por is null
    ) and exists (
      select 1 from public.cronograma_pagos cp
      where cp.contrato_id = p_contrato_origen_id
        and cp.estado = 'pendiente'
    ),
    'delete misma TX no fue reentrante X→X o no restauro hijo→padre'
  );
end;
$function$;

\set test_conn 'host=host.docker.internal port=55322 dbname=crm_ficha_security_test user=postgres password=postgres application_name=f41_security_race'

select qa.race_reassignment_wins(
  :'test_conn',
  'alta existente: reasignacion gana',
  'f4110000-0000-4000-8000-000000000101',
  'existente'
);
select qa.race_reassignment_wins(
  :'test_conn',
  'alta nueva: reasignacion gana',
  'f4110000-0000-4000-8000-000000000102',
  'nueva'
);
select qa.race_reassignment_wins(
  :'test_conn',
  'correccion: reasignacion gana',
  'f4110000-0000-4000-8000-000000000103',
  'correccion',
  'f4150000-0000-4000-8000-000000000103'
);

select qa.race_writer_wins(
  :'test_conn',
  'alta existente: writer gana',
  'f4110000-0000-4000-8000-000000000104',
  'existente'
);
select qa.race_writer_wins(
  :'test_conn',
  'alta nueva: writer gana',
  'f4110000-0000-4000-8000-000000000105',
  'nueva'
);
select qa.race_writer_wins(
  :'test_conn',
  'correccion: writer gana',
  'f4110000-0000-4000-8000-000000000106',
  'correccion',
  'f4150000-0000-4000-8000-000000000106'
);

-- Cobro REST y correccion contractual comparten mutex en ambos ordenes.
select qa.race_correction_before_payment(
  :'test_conn',
  'cronograma: correccion gana mutex'
);
select qa.race_payment_before_correction(
  :'test_conn',
  'cronograma: cobro gana mutex'
);

-- Cobro directo revalida el perfil actor bajo lock y se serializa con cierre.
select qa.race_payment_offboarding_wins(
  :'test_conn',
  'cobro directo: baja actor gana',
  'f4190000-0000-4000-8000-000000000114'
);
select qa.race_payment_writer_wins_offboarding(
  :'test_conn',
  'cobro directo: writer gana antes de baja',
  'f4190000-0000-4000-8000-000000000115'
);
select qa.race_close_before_payment(
  :'test_conn',
  'cierre renovado gana antes de cobro',
  'f4150000-0000-4000-8000-000000000116',
  'f4150000-0000-4000-8000-000000000118',
  'f4190000-0000-4000-8000-000000000116'
);
select qa.race_payment_before_close(
  :'test_conn',
  'cobro gana antes de cierre renovado',
  'f4150000-0000-4000-8000-000000000117',
  'f4150000-0000-4000-8000-000000000119',
  'f4190000-0000-4000-8000-000000000117'
);

select qa.race_number_offboarding_wins(:'test_conn');
select qa.race_number_writer_wins(:'test_conn');

select qa.race_delete_actor_mutation_wins(:'test_conn', 'baja');
select qa.race_delete_actor_mutation_wins(:'test_conn', 'rol');
select qa.race_delete_prepare_wins(:'test_conn');

create temporary table qa_delete_primera as
select crm.contrato_eliminacion_preparar(
  'f4150000-0000-4000-8000-000000000111',
  'f4100000-0000-4000-8000-000000000014'
) as resultado;
create temporary table qa_delete_adopcion as
select crm.contrato_eliminacion_preparar(
  'f4150000-0000-4000-8000-000000000111',
  'f4100000-0000-4000-8000-000000000015'
) as resultado;
select qa.assert_true(
  (select resultado->>'token' from qa_delete_primera)
    = (select resultado->>'token' from qa_delete_adopcion)
  and (
    select solicitado_por from private.contrato_eliminaciones
    where contrato_id = 'f4150000-0000-4000-8000-000000000111'
  ) = 'f4100000-0000-4000-8000-000000000015'::uuid,
  'otro Admin no adopto token/manifiesto del delete'
);
select crm.contrato_eliminacion_finalizar(
  'f4150000-0000-4000-8000-000000000111',
  ((select resultado from qa_delete_adopcion)->>'token')::uuid,
  'f4100000-0000-4000-8000-000000000015'
);
select qa.assert_true(
  not exists (
    select 1 from public.contratos
    where id = 'f4150000-0000-4000-8000-000000000111'
  ),
  'Admin adoptante no finalizo hard-delete'
);

-- El trigger legacy del DELETE restaura cronograma antes que contrato origen.
-- El mutex cobros X del finalizador lo separa de writers parent→child.
select qa.race_delete_restore_vs_writer(
  :'test_conn',
  'delete restaura antes de correccion origen',
  'f4150000-0000-4000-8000-000000000121',
  'f4150000-0000-4000-8000-000000000122',
  'correccion',
  null,
  true
);
select qa.race_delete_restore_vs_writer(
  :'test_conn',
  'correccion origen antes de delete restaura',
  'f4150000-0000-4000-8000-000000000123',
  'f4150000-0000-4000-8000-000000000124',
  'correccion',
  null,
  false
);
select qa.race_delete_restore_vs_writer(
  :'test_conn',
  'delete restaura antes de cierre origen',
  'f4150000-0000-4000-8000-000000000125',
  'f4150000-0000-4000-8000-000000000126',
  'cierre',
  'f4150000-0000-4000-8000-000000000131',
  true
);
select qa.race_delete_restore_vs_writer(
  :'test_conn',
  'cierre origen antes de delete restaura',
  'f4150000-0000-4000-8000-000000000127',
  'f4150000-0000-4000-8000-000000000128',
  'cierre',
  'f4150000-0000-4000-8000-000000000132',
  false
);

-- Caso no concurrente: preparar y finalizar pueden compartir XID porque el
-- mutex de cobros ya se toma X en preparar y la segunda toma X es reentrante.
select qa.assert_delete_prepare_finalize_same_transaction(
  'f4150000-0000-4000-8000-000000000129',
  'f4150000-0000-4000-8000-000000000130',
  'f4100000-0000-4000-8000-000000000014'
);

-- El actor de cada mutador exclusivo se reautoriza despues de esperar la
-- global y su perfil queda congelado hasta COMMIT. Se prueban ambos ordenes.
select qa.race_actor_offboarding_wins(:'test_conn', 'rol');
select qa.race_exclusive_mutator_wins(:'test_conn', 'rol');
select qa.race_actor_offboarding_wins(:'test_conn', 'jerarquia');
select qa.race_exclusive_mutator_wins(:'test_conn', 'jerarquia');
select qa.race_actor_offboarding_wins(:'test_conn', 'membresia');
select qa.race_exclusive_mutator_wins(:'test_conn', 'membresia');
select qa.race_actor_offboarding_wins(:'test_conn', 'registro');
select qa.race_exclusive_mutator_wins(:'test_conn', 'registro');
select qa.race_two_exclusive_mutators(
  :'test_conn',
  'dos mutadores toman X sin upgrade S→X'
);

-- La autorizacion del supervisor tambien depende de equipo.rol_crm,
-- equipo.activo y la arista vendedor -> supervisor. Los mutadores canonicos
-- toman la llave global en exclusivo; los writers F41 la comparten hasta
-- COMMIT. Se prueban ambos ordenes para las tres dimensiones revocables.
select qa.race_authority_mutation_wins(
  :'test_conn',
  'jerarquia: mutacion gana',
  'jerarquia',
  'correccion'
);
select qa.race_authority_writer_wins(
  :'test_conn',
  'jerarquia: writer gana',
  'jerarquia',
  'correccion'
);
select qa.race_authority_mutation_wins(
  :'test_conn',
  'rol CRM: mutacion gana',
  'rol',
  'correccion'
);
select qa.race_authority_writer_wins(
  :'test_conn',
  'rol CRM: writer gana',
  'rol',
  'correccion'
);
select qa.race_authority_mutation_wins(
  :'test_conn',
  'baja CRM: mutacion gana',
  'baja',
  'correccion'
);
select qa.race_authority_writer_wins(
  :'test_conn',
  'baja CRM: writer gana',
  'baja',
  'correccion'
);
select qa.race_authority_mutation_wins(
  :'test_conn',
  'baja Portal directa: mutacion gana',
  'baja_portal',
  'correccion'
);
select qa.race_authority_writer_wins(
  :'test_conn',
  'baja Portal directa: writer gana',
  'baja_portal',
  'correccion'
);

-- La misma frontera cubre el sink durable service-role del ledger PDF.
select qa.race_authority_mutation_wins(
  :'test_conn',
  'PDF finalizar: baja gana',
  'baja',
  'finalizar',
  'f4170000-0000-4000-8000-000000000108'
);
select qa.race_authority_writer_wins(
  :'test_conn',
  'PDF finalizar: writer gana',
  'jerarquia',
  'finalizar',
  'f4170000-0000-4000-8000-000000000109'
);
select qa.race_authority_mutation_wins(
  :'test_conn',
  'PDF finalizar: baja Portal gana',
  'baja_portal',
  'finalizar',
  'f4170000-0000-4000-8000-000000000110'
);
select qa.race_authority_writer_wins(
  :'test_conn',
  'PDF finalizar: writer gana antes de baja Portal',
  'baja_portal',
  'finalizar',
  'f4170000-0000-4000-8000-000000000111'
);
select qa.race_two_pdf_writers_same_contract(
  :'test_conn',
  'dos writers PDF del mismo contrato',
  'f4170000-0000-4000-8000-000000000112',
  'f4170000-0000-4000-8000-000000000113'
);

select qa.assert_true(
  not exists (select 1 from private.contrato_escritura_atomica_capacidades),
  'quedaron capacidades efimeras al terminar'
);
select qa.assert_true(
  not exists (
    select 1 from pg_catalog.pg_stat_activity actividad
    where actividad.datname = current_database()
      and actividad.pid <> pg_backend_pid()
      and actividad.application_name = 'f41_security_race'
  ),
  'quedaron conexiones dblink abiertas'
);

\echo FICHA_CLIENTE_SECURITY_HARDENING_SQL_OK

\set ON_ERROR_STOP on

-- Oráculo autocontenido de crm.crear_lead_si_disponible.
-- Se ejecuta únicamente en un PostgreSQL vacío y desechable. Construye la
-- frontera mínima previa a P-048, aplica LA migración real y verifica contrato,
-- autorización, idempotencia, estados y concurrencia con dos conexiones.

do $$
declare v_rol text;
begin
  foreach v_rol in array array['anon', 'authenticated', 'service_role'] loop
    if not exists (select 1 from pg_catalog.pg_roles where rolname = v_rol) then
      execute pg_catalog.format('create role %I nologin', v_rol);
    end if;
  end loop;
end;
$$;

create extension dblink;

create schema auth;
create schema crm;
create schema private;

create function auth.uid()
returns uuid
language sql
stable
set search_path = ''
as $$
  select nullif(pg_catalog.current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create table public.perfiles (
  id uuid primary key,
  nombre_completo text,
  rol text not null,
  activo boolean not null default true,
  telefono text,
  dni text,
  asesor_perfil_id uuid
);

create table crm.equipo (
  perfil_id uuid primary key references public.perfiles(id),
  rol_crm text not null,
  supervisor_id uuid,
  activo boolean not null default true
);

create table crm.enfriamiento_politica (
  motivo text primary key,
  dias integer not null
);

insert into crm.enfriamiento_politica (motivo, dias) values
  ('sin_interes', 30),
  ('sin_fondos', 90),
  ('competencia', 180),
  ('no_responde', 15),
  ('datos_invalidos', 0),
  ('pide_credito', 0),
  ('otro', 20);

create table crm.leads (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  nombre_completo text not null,
  telefono text not null,
  correo text,
  dni text,
  genero text,
  fecha_nacimiento date,
  distrito text,
  origen text not null default 'otro',
  etapa text not null default 'nuevo',
  motivo_descarte text,
  monto_estimado numeric not null,
  moneda text not null default 'PEN',
  categoria_interes text,
  vendedor_id uuid,
  asignado_supervisor_id uuid,
  perfil_id uuid,
  contrato_id uuid,
  convertido_en timestamptz,
  nota text,
  no_contactar boolean not null default false,
  descartado_en timestamptz,
  descartado_por uuid,
  activo boolean not null default true,
  creado_por uuid,
  creado_en timestamptz not null default pg_catalog.now(),
  tenencia_desde timestamptz,
  actualizado_en timestamptz not null default pg_catalog.now()
);

create unique index uq_leads_telefono_vivo on crm.leads (telefono)
  where activo = true and etapa not in ('convertido', 'descartado');
create unique index uq_leads_dni_vivo on crm.leads (dni)
  where dni is not null and activo = true and etapa not in ('convertido', 'descartado');

create function private.normalizar_telefono(p text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p is null or pg_catalog.btrim(p) = '' then p
    when pg_catalog.length(pg_catalog.regexp_replace(p, '[^0-9]', '', 'g')) = 9
      then '+51' || pg_catalog.regexp_replace(p, '[^0-9]', '', 'g')
    when pg_catalog.regexp_replace(p, '[^0-9]', '', 'g') ~ '^51[0-9]{9}$'
      then '+' || pg_catalog.regexp_replace(p, '[^0-9]', '', 'g')
    else '+' || pg_catalog.regexp_replace(p, '[^0-9]', '', 'g')
  end;
$$;

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
    and e.activo = true
    and p.activo = true
    and e.rol_crm in ('vendedor', 'supervisor', 'gerencia', 'coordinador');
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
  if v_rol = 'gerencia' then
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
  end if;
end;
$$;

create function private.es_destino_crm_activo(p_perfil_id uuid, p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.perfil_id = p_perfil_id
      and e.activo = true
      and p.activo = true
      and e.rol_crm = any (p_roles)
  );
$$;

create function private.verificar_disponibilidad_lead_impl(
  p_telefono text,
  p_dni text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tel text := private.normalizar_telefono(p_telefono);
  v_lead record;
  v_perfil record;
  v_dias integer;
  v_disponible_desde timestamptz;
begin
  if v_tel is null or pg_catalog.length(v_tel) = 0 then
    return pg_catalog.jsonb_build_object('estado', 'error', 'detalle', 'telefono_invalido');
  end if;

  if exists (
    select 1 from crm.leads l
    where l.no_contactar = true
      and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  ) then
    return pg_catalog.jsonb_build_object('estado', 'no_contactar');
  end if;

  select per.id, asesor.nombre_completo as asesor_nombre
    into v_perfil
  from public.perfiles per
  left join public.perfiles asesor on asesor.id = per.asesor_perfil_id
  where per.rol = 'cliente'
    and per.activo = true
    and (
      private.normalizar_telefono(per.telefono) = v_tel
      or (p_dni is not null and per.dni = p_dni)
    )
  limit 1;

  if found then
    return pg_catalog.jsonb_build_object(
      'estado', 'ya_es_cliente',
      'asesor', coalesce(v_perfil.asesor_nombre, 'sin asesor asignado')
    );
  end if;

  select l.tenencia_desde, l.vendedor_id, l.asignado_supervisor_id,
         coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
    into v_lead
  from crm.leads l
  left join public.perfiles pv on pv.id = l.vendedor_id
  left join public.perfiles ps on ps.id = l.asignado_supervisor_id
  where l.activo = true
    and l.etapa not in ('convertido', 'descartado')
    and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  limit 1;

  if found then
    if v_lead.vendedor_id is null and v_lead.asignado_supervisor_id is null then
      return pg_catalog.jsonb_build_object('estado', 'en_bolsa');
    end if;
    return pg_catalog.jsonb_build_object(
      'estado', 'tomado',
      'vendedor', v_lead.tenedor,
      'tenencia_desde', v_lead.tenencia_desde
    );
  end if;

  select l.motivo_descarte, l.descartado_en, pd.nombre_completo as descartado_por_nombre
    into v_lead
  from crm.leads l
  left join public.perfiles pd on pd.id = l.descartado_por
  where l.etapa = 'descartado'
    and l.descartado_en is not null
    and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  order by l.descartado_en desc
  limit 1;

  if found then
    select ep.dias into v_dias
    from crm.enfriamiento_politica ep
    where ep.motivo = v_lead.motivo_descarte;

    v_dias := coalesce(v_dias, 0);
    v_disponible_desde := v_lead.descartado_en + pg_catalog.make_interval(days => v_dias);
    if v_dias > 0 and v_disponible_desde > pg_catalog.now() then
      return pg_catalog.jsonb_build_object(
        'estado', 'enfriamiento',
        'motivo_descarte', v_lead.motivo_descarte,
        'disponible_desde', v_disponible_desde,
        'descartado_por', v_lead.descartado_por_nombre
      );
    end if;
  end if;

  return pg_catalog.jsonb_build_object('estado', 'libre');
end;
$$;

grant usage on schema auth, crm to authenticated;
grant execute on function auth.uid() to authenticated;
grant select, insert, update on crm.leads to authenticated, service_role;

-- Actores y dos subárboles independientes.
insert into public.perfiles (id, nombre_completo, rol, activo) values
  ('10000000-0000-0000-0000-000000000001', 'VENDEDOR UNO', 'analista', true),
  ('10000000-0000-0000-0000-000000000002', 'SUPERVISOR UNO', 'supervisor', true),
  ('10000000-0000-0000-0000-000000000003', 'VENDEDOR DOS', 'analista', true),
  ('10000000-0000-0000-0000-000000000004', 'GERENCIA', 'gerencia', true),
  ('10000000-0000-0000-0000-000000000005', 'COORDINADOR', 'coordinador', true),
  ('10000000-0000-0000-0000-000000000007', 'SUPERVISOR DOS', 'supervisor', true);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values
  ('10000000-0000-0000-0000-000000000001', 'vendedor', '10000000-0000-0000-0000-000000000002', true),
  ('10000000-0000-0000-0000-000000000002', 'supervisor', null, true),
  ('10000000-0000-0000-0000-000000000003', 'vendedor', '10000000-0000-0000-0000-000000000007', true),
  ('10000000-0000-0000-0000-000000000004', 'gerencia', null, true),
  ('10000000-0000-0000-0000-000000000005', 'coordinador', null, true),
  ('10000000-0000-0000-0000-000000000007', 'supervisor', null, true);

\ir ../migrations/20260804165440_crm_creacion_lead_atomica.sql

-- ACL mínima: solo authenticated ve la frontera RPC.
do $$
declare
  v_rol text;
  v_firma text;
begin
  if not pg_catalog.has_function_privilege(
    'authenticated',
    'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text)',
    'EXECUTE'
  ) then
    raise exception 'ACL01 authenticated sin EXECUTE';
  end if;
  if pg_catalog.has_function_privilege(
    'anon',
    'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text)',
    'EXECUTE'
  ) then
    raise exception 'ACL02 anon con EXECUTE';
  end if;
  if pg_catalog.has_function_privilege(
    'service_role',
    'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text)',
    'EXECUTE'
  ) then
    raise exception 'ACL03 service_role con EXECUTE';
  end if;

  foreach v_rol in array array['anon', 'authenticated', 'service_role'] loop
    foreach v_firma in array array[
      'private.bloquear_contactos_lead(text[],text[])',
      'private.verificar_disponibilidad_lead_impl(text,text)',
      'private.verificar_disponibilidad_lead_impl(text,text,uuid)',
      'private.trg_leads_disponibilidad_atomica()'
    ] loop
      if pg_catalog.has_function_privilege(v_rol, v_firma, 'EXECUTE') then
        raise exception 'ACL04 % conserva EXECUTE sobre %', v_rol, v_firma;
      end if;
    end loop;
  end loop;
end;
$$;

begin;

-- Libre → creado; el vendedor se autoasigna y el mismo p_id es idempotente.
do $$
declare
  v_resultado jsonb;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  v_resultado := crm.crear_lead_si_disponible(
    p_nombre_completo => 'ALTA LIBRE',
    p_telefono => '900 000 001',
    p_origen => 'formulario',
    p_monto_estimado => 10000,
    p_moneda => 'PEN',
    p_id => '20000000-0000-0000-0000-000000000001',
    p_dni => '70000001'
  );
  if v_resultado <> '{"estado":"creado","lead_id":"20000000-0000-0000-0000-000000000001"}'::jsonb then
    raise exception 'A01 respuesta inesperada: %', v_resultado;
  end if;
  if not exists (
    select 1 from crm.leads l
    where l.id = '20000000-0000-0000-0000-000000000001'
      and l.telefono = '+51900000001'
      and l.vendedor_id = '10000000-0000-0000-0000-000000000001'
      and l.asignado_supervisor_id is null
      and l.creado_por = '10000000-0000-0000-0000-000000000001'
  ) then
    raise exception 'A02 fila o autoridad derivada incorrecta';
  end if;

  v_resultado := crm.crear_lead_si_disponible(
    p_nombre_completo => 'ALTA LIBRE',
    p_telefono => '900 000 001',
    p_origen => 'formulario',
    p_monto_estimado => 10000,
    p_moneda => 'PEN',
    p_id => '20000000-0000-0000-0000-000000000001',
    p_dni => '70000001'
  );
  if v_resultado ->> 'estado' <> 'creado'
     or (select count(*) from crm.leads where id = '20000000-0000-0000-0000-000000000001') <> 1 then
    raise exception 'A03 retry no idempotente: %', v_resultado;
  end if;

  begin
    perform crm.crear_lead_si_disponible(
      p_nombre_completo => 'PAYLOAD DISTINTO',
      p_telefono => '900000001',
      p_origen => 'formulario',
      p_monto_estimado => 10000,
      p_moneda => 'PEN',
      p_id => '20000000-0000-0000-0000-000000000001',
      p_dni => '70000001'
    );
    raise exception 'A04 reutilizó p_id con otro payload';
  exception when sqlstate '22023' then
    null;
  end;
end;
$$;

-- Mismo contacto con otro id: tomado y cero segunda fila.
do $$
declare v_resultado jsonb;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
  v_resultado := crm.crear_lead_si_disponible(
    'OTRO INTENTO', '900000001', 'formulario', 9000, 'PEN',
    '20000000-0000-0000-0000-000000000002', p_dni => '70000001'
  );
  if v_resultado ->> 'estado' <> 'tomado'
     or (select count(*) from crm.leads where telefono = '+51900000001') <> 1 then
    raise exception 'B01 no bloqueó tomado: %', v_resultado;
  end if;
end;
$$;

-- No contactar bloquea también al INSERT directo de un bundle anterior.
do $$
declare
  v_resultado jsonb;
  v_detalle text;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
  insert into crm.leads (
    id, nombre_completo, telefono, dni, origen, etapa, motivo_descarte,
    monto_estimado, moneda, no_contactar
  ) values (
    '20000000-0000-0000-0000-000000000010', 'NO CONTACTAR HISTORICO',
    '900000010', '70000010', 'otro', 'descartado', 'otro', 1000, 'PEN', true
  );

  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  v_resultado := crm.crear_lead_si_disponible(
    'PROHIBIDO', '900000010', 'formulario', 8000, 'PEN',
    '20000000-0000-0000-0000-000000000011'
  );
  if v_resultado <> '{"estado":"no_contactar"}'::jsonb then
    raise exception 'C01 no_contactar no bloqueó: %', v_resultado;
  end if;

  begin
    insert into crm.leads (
      id, nombre_completo, telefono, origen, monto_estimado, moneda,
      vendedor_id, creado_por
    ) values (
      '20000000-0000-0000-0000-000000000012', 'BUNDLE VIEJO',
      '900000010', 'formulario', 8000, 'PEN',
      '10000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000001'
    );
    raise exception 'C02 INSERT directo saltó no_contactar';
  exception when sqlstate 'P0481' then
    get stacked diagnostics v_detalle = pg_exception_detail;
    if v_detalle::jsonb ->> 'estado' <> 'no_contactar' then
      raise exception 'C03 DETAIL inesperado: %', v_detalle;
    end if;
  end;

  begin
    insert into crm.leads (
      id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
      vendedor_id, creado_por
    ) values (
      '20000000-0000-0000-0000-000000000013', 'TERMINAL INYECTADO',
      '900000013', 'formulario', 'convertido', 8000, 'PEN',
      '10000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000001'
    );
    raise exception 'C04 INSERT humano creó un lead terminal';
  exception when sqlstate '22023' then null;
  end;

  begin
    update crm.leads
    set telefono = '900000010'
    where id = '20000000-0000-0000-0000-000000000001';
    raise exception 'C05 UPDATE de identidad saltó no_contactar';
  exception when sqlstate 'P0481' then
    get stacked diagnostics v_detalle = pg_exception_detail;
    if v_detalle::jsonb ->> 'estado' <> 'no_contactar' then
      raise exception 'C06 UPDATE devolvió DETAIL inesperado: %', v_detalle;
    end if;
  end;

  -- El veto de la propia fila no se puede «mudar» a datos nuevos dejando
  -- disponibles el teléfono o DNI originales.
  begin
    update crm.leads
    set telefono = '900000014'
    where id = '20000000-0000-0000-0000-000000000010';
    raise exception 'C07 movió el teléfono de su propio no_contactar';
  exception when sqlstate 'P0481' then
    get stacked diagnostics v_detalle = pg_exception_detail;
    if v_detalle::jsonb <> '{"estado":"no_contactar"}'::jsonb then
      raise exception 'C08 veto propio devolvió DETAIL inesperado: %', v_detalle;
    end if;
  end;

  begin
    update crm.leads
    set dni = '70000014'
    where id = '20000000-0000-0000-0000-000000000010';
    raise exception 'C09 movió el DNI de su propio no_contactar';
  exception when sqlstate 'P0481' then null;
  end;

  begin
    update crm.leads
    set telefono = '900000014', dni = '70000014'
    where id = '20000000-0000-0000-0000-000000000010';
    raise exception 'C10 movió ambos datos de su propio no_contactar';
  exception when sqlstate 'P0481' then null;
  end;

  if not exists (
    select 1 from crm.leads
    where id = '20000000-0000-0000-0000-000000000010'
      and telefono = '+51900000010'
      and dni = '70000010'
  ) then
    raise exception 'C11 los intentos alteraron la identidad vetada';
  end if;
end;
$$;

-- Cliente existente, enfriamiento vigente y bolsa global.
do $$
declare
  v_resultado jsonb;
  v_detalle text;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
  insert into public.perfiles (id, nombre_completo, rol, activo, telefono, dni)
  values (
    '30000000-0000-0000-0000-000000000001', 'CLIENTE EXISTENTE', 'cliente', true,
    '900 000 020', '70000020'
  );
  insert into crm.leads (
    id, nombre_completo, telefono, dni, origen, etapa, motivo_descarte,
    monto_estimado, moneda, descartado_en
  ) values (
    '20000000-0000-0000-0000-000000000021', 'ENFRIAMIENTO', '900000021',
    '70000021', 'otro', 'descartado', 'no_responde', 1000, 'PEN', pg_catalog.now()
  );
  insert into crm.leads (
    id, nombre_completo, telefono, origen, monto_estimado, moneda
  ) values (
    '20000000-0000-0000-0000-000000000022', 'EN BOLSA', '900000022',
    'otro', 1000, 'PEN'
  );

  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  v_resultado := crm.crear_lead_si_disponible(
    'CLIENTE REPETIDO', '900000020', 'referido', 9000, 'PEN',
    '20000000-0000-0000-0000-000000000023', p_dni => '70000020'
  );
  if v_resultado ->> 'estado' <> 'ya_es_cliente' then
    raise exception 'D01 cliente existente no bloqueó: %', v_resultado;
  end if;

  begin
    update crm.leads
    set dni = '70000020'
    where id = '20000000-0000-0000-0000-000000000001';
    raise exception 'D01b UPDATE de DNI saltó ya_es_cliente';
  exception when sqlstate 'P0481' then
    get stacked diagnostics v_detalle = pg_exception_detail;
    if v_detalle::jsonb ->> 'estado' <> 'ya_es_cliente' then
      raise exception 'D01c UPDATE de DNI devolvió DETAIL inesperado: %', v_detalle;
    end if;
  end;

  v_resultado := crm.crear_lead_si_disponible(
    'FRIO', '900000021', 'referido', 9000, 'PEN',
    '20000000-0000-0000-0000-000000000024', p_dni => '70000021'
  );
  if v_resultado ->> 'estado' <> 'enfriamiento' then
    raise exception 'D02 enfriamiento no bloqueó: %', v_resultado;
  end if;

  begin
    update crm.leads
    set telefono = '900000026'
    where id = '20000000-0000-0000-0000-000000000021';
    raise exception 'D02a movió el teléfono de su propio enfriamiento';
  exception when sqlstate 'P0481' then
    get stacked diagnostics v_detalle = pg_exception_detail;
    if v_detalle::jsonb ->> 'estado' <> 'enfriamiento' then
      raise exception 'D02b enfriamiento propio devolvió DETAIL inesperado: %', v_detalle;
    end if;
  end;

  begin
    update crm.leads
    set dni = '70000026'
    where id = '20000000-0000-0000-0000-000000000021';
    raise exception 'D02c movió el DNI de su propio enfriamiento';
  exception when sqlstate 'P0481' then null;
  end;

  begin
    update crm.leads
    set telefono = '900000026', dni = '70000026'
    where id = '20000000-0000-0000-0000-000000000021';
    raise exception 'D02d movió ambos datos de su propio enfriamiento';
  exception when sqlstate 'P0481' then null;
  end;

  if not exists (
    select 1 from crm.leads
    where id = '20000000-0000-0000-0000-000000000021'
      and telefono = '+51900000021'
      and dni = '70000021'
  ) then
    raise exception 'D02e los intentos alteraron la identidad en enfriamiento';
  end if;

  v_resultado := crm.crear_lead_si_disponible(
    'BOLSA REPETIDA', '900000022', 'referido', 9000, 'PEN',
    '20000000-0000-0000-0000-000000000025'
  );
  if v_resultado ->> 'estado' <> 'en_bolsa' then
    raise exception 'D03 bolsa no bloqueó: %', v_resultado;
  end if;
end;
$$;

-- Enfriamiento vencido crea; teléfono inválido no escribe.
do $$
declare v_resultado jsonb;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
  insert into crm.leads (
    id, nombre_completo, telefono, origen, etapa, motivo_descarte,
    monto_estimado, moneda, descartado_en
  ) values (
    '20000000-0000-0000-0000-000000000030', 'FRIO VENCIDO', '900000030',
    'otro', 'descartado', 'no_responde', 1000, 'PEN', pg_catalog.now() - interval '16 days'
  );

  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  v_resultado := crm.crear_lead_si_disponible(
    'REINGRESO', '900000030', 'referido', 9000, 'PEN',
    '20000000-0000-0000-0000-000000000031'
  );
  if v_resultado ->> 'estado' <> 'creado' then
    raise exception 'E01 enfriamiento vencido no creó: %', v_resultado;
  end if;

  v_resultado := crm.crear_lead_si_disponible(
    'INVALIDO', '123', 'referido', 9000, 'PEN',
    '20000000-0000-0000-0000-000000000032'
  );
  if v_resultado <> '{"estado":"error","detalle":"telefono_invalido"}'::jsonb
     or exists (select 1 from crm.leads where id = '20000000-0000-0000-0000-000000000032') then
    raise exception 'E02 teléfono inválido: %', v_resultado;
  end if;

  update crm.leads
  set telefono = '900000033'
  where id = '20000000-0000-0000-0000-000000000030';
  if not exists (
    select 1 from crm.leads
    where id = '20000000-0000-0000-0000-000000000030'
      and telefono = '+51900000033'
  ) then
    raise exception 'E03 enfriamiento vencido impidió corregir una identidad libre';
  end if;
end;
$$;

-- Supervisor parquea en SU bandeja; ámbito lateral, coordinador y P04 fallan.
do $$
declare v_resultado jsonb;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
  v_resultado := crm.crear_lead_si_disponible(
    'PARQUEADO', '900000040', 'oficina', 9000, 'USD',
    '20000000-0000-0000-0000-000000000040'
  );
  if v_resultado ->> 'estado' <> 'creado' or not exists (
    select 1 from crm.leads l
    where l.id = '20000000-0000-0000-0000-000000000040'
      and l.vendedor_id is null
      and l.asignado_supervisor_id = '10000000-0000-0000-0000-000000000002'
  ) then
    raise exception 'F01 supervisor no parqueó correctamente: %', v_resultado;
  end if;

  update crm.leads
  set telefono = '900000044', dni = '70000044'
  where id = '20000000-0000-0000-0000-000000000040';
  if not exists (
    select 1 from crm.leads
    where id = '20000000-0000-0000-0000-000000000040'
      and telefono = '+51900000044'
      and dni = '70000044'
  ) then
    raise exception 'F01b lead operativo no aceptó una identidad libre';
  end if;

  begin
    perform crm.crear_lead_si_disponible(
      'LATERAL', '900000041', 'oficina', 9000, 'PEN',
      '20000000-0000-0000-0000-000000000041',
      p_vendedor_id => '10000000-0000-0000-0000-000000000003'
    );
    raise exception 'F02 supervisor escribió en otro subárbol';
  exception when sqlstate '42501' then null;
  end;

  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000005', true);
  begin
    perform crm.crear_lead_si_disponible(
      'COORDINADOR', '900000042', 'oficina', 9000, 'PEN',
      '20000000-0000-0000-0000-000000000042'
    );
    raise exception 'F03 coordinador creó lead';
  exception when sqlstate '42501' then null;
  end;

  update crm.equipo set activo = false
  where perfil_id = '10000000-0000-0000-0000-000000000001';
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
  begin
    perform crm.crear_lead_si_disponible(
      'REVOCADO', '900000043', 'oficina', 9000, 'PEN',
      '20000000-0000-0000-0000-000000000043'
    );
    raise exception 'F04 membresía inactiva creó lead';
  exception when sqlstate '42501' then null;
  end;
end;
$$;

rollback;

-- Concurrencia real: la conexión worker crea y conserva el advisory lock un
-- segundo. La conexión principal entra después sobre el mismo teléfono; debe
-- esperar al COMMIT, reconsultar y responder tomado. Nunca hay dos filas.
create table private.worker_test (pid integer primary key);

select dblink_connect('worker', :'test_conn');
insert into private.worker_test (pid)
select pid from dblink('worker', 'select pg_backend_pid()') as remoto(pid integer);

select dblink_send_query(
  'worker',
  $worker$
    begin;
    select pg_catalog.set_config(
      'request.jwt.claim.sub',
      '10000000-0000-0000-0000-000000000001',
      false
    );
    select private.bloquear_contactos_lead(array['900000090'], array[]::text[]);
    select crm.crear_lead_si_disponible(
      'GANADOR CONCURRENTE', '900000090', 'formulario', 10000, 'PEN',
      '20000000-0000-0000-0000-000000000090', p_dni => '70000090'
    );
    select pg_catalog.pg_sleep(1);
    commit;
  $worker$
);

do $$
declare v_limite timestamptz := pg_catalog.clock_timestamp() + interval '3 seconds';
begin
  while not exists (
    select 1 from pg_catalog.pg_locks l
    where l.pid = (select w.pid from private.worker_test w)
      and l.locktype = 'advisory'
      and l.granted
  ) loop
    if pg_catalog.clock_timestamp() > v_limite then
      raise exception 'G01 worker nunca adquirió advisory lock';
    end if;
    perform pg_catalog.pg_sleep(0.01);
  end loop;
end;
$$;

do $$
declare
  v_resultado jsonb;
  v_inicio timestamptz := pg_catalog.clock_timestamp();
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', false);
  v_resultado := crm.crear_lead_si_disponible(
    'PERDEDOR CONCURRENTE', '900000090', 'formulario', 10000, 'PEN',
    '20000000-0000-0000-0000-000000000091', p_dni => '70000091'
  );
  if v_resultado ->> 'estado' <> 'tomado' then
    raise exception 'G02 carrera no reconsultó al ganador: %', v_resultado;
  end if;
  if pg_catalog.clock_timestamp() - v_inicio < interval '500 milliseconds' then
    raise exception 'G03 segunda conexión no esperó el lock';
  end if;
  if (select count(*) from crm.leads where telefono = '+51900000090') <> 1 then
    raise exception 'G04 carrera dejó más de una fila';
  end if;
end;
$$;

select dblink_disconnect('worker');

-- Misma garantía cuando la colisión es por DNI y los teléfonos son distintos.
truncate table private.worker_test;
select dblink_connect('worker_dni', :'test_conn');
insert into private.worker_test (pid)
select pid from dblink('worker_dni', 'select pg_backend_pid()') as remoto(pid integer);

select dblink_send_query(
  'worker_dni',
  $worker$
    begin;
    select pg_catalog.set_config(
      'request.jwt.claim.sub',
      '10000000-0000-0000-0000-000000000001',
      false
    );
    select private.bloquear_contactos_lead(array[]::text[], array['70000092']);
    select crm.crear_lead_si_disponible(
      'GANADOR DNI', '900000092', 'formulario', 10000, 'PEN',
      '20000000-0000-0000-0000-000000000092', p_dni => '70000092'
    );
    select pg_catalog.pg_sleep(1);
    commit;
  $worker$
);

do $$
declare v_limite timestamptz := pg_catalog.clock_timestamp() + interval '3 seconds';
begin
  while not exists (
    select 1 from pg_catalog.pg_locks l
    where l.pid = (select w.pid from private.worker_test w)
      and l.locktype = 'advisory'
      and l.granted
  ) loop
    if pg_catalog.clock_timestamp() > v_limite then
      raise exception 'G05 worker DNI nunca adquirió advisory lock';
    end if;
    perform pg_catalog.pg_sleep(0.01);
  end loop;
end;
$$;

do $$
declare
  v_resultado jsonb;
  v_inicio timestamptz := pg_catalog.clock_timestamp();
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', false);
  v_resultado := crm.crear_lead_si_disponible(
    'PERDEDOR DNI', '900000093', 'formulario', 10000, 'PEN',
    '20000000-0000-0000-0000-000000000093', p_dni => '70000092'
  );
  if v_resultado ->> 'estado' <> 'tomado' then
    raise exception 'G06 carrera por DNI no reconsultó al ganador: %', v_resultado;
  end if;
  if pg_catalog.clock_timestamp() - v_inicio < interval '500 milliseconds' then
    raise exception 'G07 segunda conexión no esperó el lock de DNI';
  end if;
  if (select count(*) from crm.leads where dni = '70000092') <> 1 then
    raise exception 'G08 carrera por DNI dejó más de una fila';
  end if;
end;
$$;

select dblink_disconnect('worker_dni');

-- Si quien obtuvo primero el lock revierte, la siguiente sesión debe despertar,
-- reconsultar libre y poder crear: el advisory lock sigue la transacción real.
truncate table private.worker_test;
select dblink_connect('worker_rollback', :'test_conn');
insert into private.worker_test (pid)
select pid from dblink('worker_rollback', 'select pg_backend_pid()') as remoto(pid integer);

select dblink_send_query(
  'worker_rollback',
  $worker$
    begin;
    select pg_catalog.set_config(
      'request.jwt.claim.sub',
      '10000000-0000-0000-0000-000000000001',
      false
    );
    select private.bloquear_contactos_lead(array['900000094'], array[]::text[]);
    select crm.crear_lead_si_disponible(
      'GANADOR QUE REVIERTE', '900000094', 'formulario', 10000, 'PEN',
      '20000000-0000-0000-0000-000000000094'
    );
    select pg_catalog.pg_sleep(1);
    rollback;
  $worker$
);

do $$
declare v_limite timestamptz := pg_catalog.clock_timestamp() + interval '3 seconds';
begin
  while not exists (
    select 1 from pg_catalog.pg_locks l
    where l.pid = (select w.pid from private.worker_test w)
      and l.locktype = 'advisory'
      and l.granted
  ) loop
    if pg_catalog.clock_timestamp() > v_limite then
      raise exception 'G09 worker rollback nunca adquirió advisory lock';
    end if;
    perform pg_catalog.pg_sleep(0.01);
  end loop;
end;
$$;

do $$
declare
  v_resultado jsonb;
  v_inicio timestamptz := pg_catalog.clock_timestamp();
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', false);
  v_resultado := crm.crear_lead_si_disponible(
    'DESPIERTA TRAS ROLLBACK', '900000094', 'formulario', 10000, 'PEN',
    '20000000-0000-0000-0000-000000000095'
  );
  if v_resultado <> jsonb_build_object(
    'estado', 'creado',
    'lead_id', '20000000-0000-0000-0000-000000000095'::uuid
  ) then
    raise exception 'G10 rollback no liberó el contacto: %', v_resultado;
  end if;
  if pg_catalog.clock_timestamp() - v_inicio < interval '500 milliseconds' then
    raise exception 'G11 segunda conexión no esperó el rollback';
  end if;
  if (select count(*) from crm.leads where telefono = '+51900000094') <> 1 then
    raise exception 'G12 rollback dejó un resultado incorrecto';
  end if;
end;
$$;

select dblink_disconnect('worker_rollback');

-- La malla también serializa un bundle anterior que todavía haga INSERT
-- directo: la RPC espera al trigger legacy y reconsulta al ganador.
truncate table private.worker_test;
select dblink_connect('worker_legacy', :'test_conn');
insert into private.worker_test (pid)
select pid from dblink('worker_legacy', 'select pg_backend_pid()') as remoto(pid integer);

select dblink_send_query(
  'worker_legacy',
  $worker$
    begin;
    select pg_catalog.set_config(
      'request.jwt.claim.sub',
      '10000000-0000-0000-0000-000000000001',
      false
    );
    select private.bloquear_contactos_lead(array['900000096'], array[]::text[]);
    insert into crm.leads (
      id, nombre_completo, telefono, origen, monto_estimado, moneda,
      vendedor_id, creado_por
    ) values (
      '20000000-0000-0000-0000-000000000096',
      'GANADOR BUNDLE ANTERIOR',
      '900000096',
      'formulario',
      10000,
      'PEN',
      '10000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000001'
    );
    select pg_catalog.pg_sleep(1);
    commit;
  $worker$
);

do $$
declare v_limite timestamptz := pg_catalog.clock_timestamp() + interval '3 seconds';
begin
  while not exists (
    select 1 from pg_catalog.pg_locks l
    where l.pid = (select w.pid from private.worker_test w)
      and l.locktype = 'advisory'
      and l.granted
  ) loop
    if pg_catalog.clock_timestamp() > v_limite then
      raise exception 'G13 bundle anterior nunca adquirió advisory lock';
    end if;
    perform pg_catalog.pg_sleep(0.01);
  end loop;
end;
$$;

do $$
declare
  v_resultado jsonb;
  v_inicio timestamptz := pg_catalog.clock_timestamp();
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', false);
  v_resultado := crm.crear_lead_si_disponible(
    'PERDEDOR CONTRA BUNDLE', '900000096', 'formulario', 10000, 'PEN',
    '20000000-0000-0000-0000-000000000097'
  );
  if v_resultado ->> 'estado' <> 'tomado' then
    raise exception 'G14 RPC no reconsultó el INSERT legacy: %', v_resultado;
  end if;
  if pg_catalog.clock_timestamp() - v_inicio < interval '500 milliseconds' then
    raise exception 'G15 RPC no esperó el trigger del bundle anterior';
  end if;
  if (select count(*) from crm.leads where telefono = '+51900000096') <> 1 then
    raise exception 'G16 carrera legacy dejó más de una fila';
  end if;
end;
$$;

select dblink_disconnect('worker_legacy');

-- P04 se revalida después de esperar: si la membresía se revoca mientras otra
-- transacción retiene el contacto, la sesión dormida no inserta al despertar.
create table private.revocation_worker (
  nombre text primary key,
  pid integer not null
);
create table private.revocation_outcome (
  resultado text primary key
);

select dblink_connect('revocation_locker', :'test_conn');
select dblink_connect('revocation_waiter', :'test_conn');
insert into private.revocation_worker (nombre, pid)
select 'locker', pid
from dblink('revocation_locker', 'select pg_backend_pid()') as remoto(pid integer)
union all
select 'waiter', pid
from dblink('revocation_waiter', 'select pg_backend_pid()') as remoto(pid integer);

select dblink_send_query(
  'revocation_locker',
  $worker$
    begin;
    select private.bloquear_contactos_lead(array['900000100'], array[]::text[]);
    select pg_catalog.pg_sleep(2);
    commit;
  $worker$
);

do $$
declare v_limite timestamptz := pg_catalog.clock_timestamp() + interval '3 seconds';
begin
  while not exists (
    select 1 from pg_catalog.pg_locks l
    where l.pid = (
      select w.pid from private.revocation_worker w where w.nombre = 'locker'
    )
      and l.locktype = 'advisory'
      and l.granted
  ) loop
    if pg_catalog.clock_timestamp() > v_limite then
      raise exception 'H01 locker de revocación nunca adquirió el contacto';
    end if;
    perform pg_catalog.pg_sleep(0.01);
  end loop;
end;
$$;

select dblink_send_query(
  'revocation_waiter',
  $worker$
    begin;
    select pg_catalog.set_config(
      'request.jwt.claim.sub',
      '10000000-0000-0000-0000-000000000001',
      false
    );
    do $body$
    begin
      perform crm.crear_lead_si_disponible(
        'REVOCADO MIENTRAS ESPERA', '900000100', 'formulario', 10000, 'PEN',
        '20000000-0000-0000-0000-000000000100'
      );
      insert into private.revocation_outcome (resultado) values ('creado');
    exception when sqlstate '42501' then
      insert into private.revocation_outcome (resultado) values ('denegado');
    end;
    $body$;
    commit;
  $worker$
);

do $$
declare v_limite timestamptz := pg_catalog.clock_timestamp() + interval '3 seconds';
begin
  while not exists (
    select 1 from pg_catalog.pg_locks l
    where l.pid = (
      select w.pid from private.revocation_worker w where w.nombre = 'waiter'
    )
      and l.locktype = 'advisory'
      and not l.granted
  ) loop
    if pg_catalog.clock_timestamp() > v_limite then
      raise exception 'H02 RPC nunca quedó esperando el contacto';
    end if;
    perform pg_catalog.pg_sleep(0.01);
  end loop;
end;
$$;

update crm.equipo
set activo = false
where perfil_id = '10000000-0000-0000-0000-000000000001';

do $$
declare v_limite timestamptz := pg_catalog.clock_timestamp() + interval '5 seconds';
begin
  while not exists (select 1 from private.revocation_outcome) loop
    if pg_catalog.clock_timestamp() > v_limite then
      raise exception 'H03 RPC revocada no terminó';
    end if;
    perform pg_catalog.pg_sleep(0.01);
  end loop;

  if (select o.resultado from private.revocation_outcome o) <> 'denegado' then
    raise exception 'H04 RPC insertó después de revocar P04';
  end if;
  if exists (
    select 1 from crm.leads
    where id = '20000000-0000-0000-0000-000000000100'
  ) then
    raise exception 'H05 revocación dejó un lead';
  end if;
end;
$$;

update crm.equipo
set activo = true
where perfil_id = '10000000-0000-0000-0000-000000000001';

select dblink_disconnect('revocation_waiter');
select dblink_disconnect('revocation_locker');

select 'CREACION_LEAD_ATOMICA_TX_OK' as resultado;

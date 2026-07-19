-- Metas comerciales del mes · crm.objetivos (Fase 1 de "funciones de gerencia").
--
-- Hasta hoy las metas solo existian en demo (METAS_DEMO): la sesion real
-- sembraba objetivos vacios. Esta tabla las hace dato de verdad:
--   * UNA fila por (mes, rol) — vendedor / supervisor / gerencia.
--   * capital_objetivo SIEMPRE en PEN (regla de la casa: PEN y USD jamas se
--     suman; la UI convierte USD con el TC semanal antes de comparar).
--   * Lectura: todo el arbol comercial + lector global (directorio/admin).
--   * Escritura: SOLO gerencia y SOLO via crm.fijar_objetivos() — sin policies
--     de INSERT/UPDATE, mismo patron que capacidad_leads_objetivo sobre equipo.
--
-- Frontera: solo esquema crm (FK a public.perfiles ya existente en el patron).

set local lock_timeout = '10s';

-- ── 1) Tabla ──────────────────────────────────────────────────────────────────

create table crm.objetivos (
  -- id propio (y no PK compuesta) para que private.log_audit_crm registre
  -- fila_id como en todas las tablas del esquema.
  id                  uuid primary key default gen_random_uuid(),
  periodo             date not null
                      constraint objetivos_periodo_primer_dia
                      check (extract(day from periodo) = 1)
                      constraint objetivos_periodo_cuerdo
                      check (periodo >= date '2026-01-01' and periodo < date '2100-01-01'),
  rol                 text not null
                      constraint objetivos_rol_valido
                      check (rol in ('vendedor','supervisor','gerencia')),
  capital_objetivo    numeric(14,2) not null default 0
                      constraint objetivos_capital_valido
                      check (capital_objetivo >= 0 and capital_objetivo <= 100000000),
  ventas_objetivo     smallint not null default 0
                      constraint objetivos_ventas_validas
                      check (ventas_objetivo between 0 and 1000),
  conversion_objetivo numeric(5,2) not null default 0
                      constraint objetivos_conversion_valida
                      check (conversion_objetivo between 0 and 100),
  actualizado_por     uuid references public.perfiles(id) on delete set null,
  creado_en           timestamptz not null default now(),
  actualizado_en      timestamptz not null default now(),
  constraint objetivos_un_periodo_rol unique (periodo, rol)
);

comment on table crm.objetivos is
  'Metas comerciales del mes por rol (vendedor/supervisor/gerencia). capital_objetivo en PEN. Escritura solo via crm.fijar_objetivos() (gerencia); lectura por RLS.';
comment on column crm.objetivos.periodo is
  'Primer dia del mes de la meta (mes calendario de America/Lima; la UI calcula el periodo vigente en Lima).';
comment on column crm.objetivos.capital_objetivo is
  'Meta de capital cerrado del mes, SIEMPRE en PEN (los montos USD se comparan convertidos con el TC semanal; jamas se suman monedas).';
comment on column crm.objetivos.conversion_objetivo is
  'Meta de conversion en porcentaje (0-100).';

-- Indice FK (clase de advisor conocida: FKs sin indice).
create index objetivos_actualizado_por_idx on crm.objetivos (actualizado_por)
  where actualizado_por is not null;

create trigger trg_objetivos_touch before update on crm.objetivos
  for each row execute function private.set_actualizado_en_crm();
create trigger trg_audit_objetivos after insert or delete or update on crm.objetivos
  for each row execute function private.log_audit_crm();

-- ── 2) RLS ────────────────────────────────────────────────────────────────────

alter table crm.objetivos enable row level security;

create policy objetivos_select on crm.objetivos
  for select to authenticated
  using (
    (select private.rol_crm((select auth.uid()))) is not null
    or (select private.es_lector_global())
  );
-- SIN policies de INSERT/UPDATE/DELETE: la escritura va exclusivamente por la
-- RPC SECURITY DEFINER gerencia-gated de abajo (espejo de capacidad_leads).

grant select on crm.objetivos to authenticated;
grant select, insert, update, delete on crm.objetivos to service_role;
-- anon: nada (deny-by-default).

-- ── 3) RPC crm.fijar_objetivos — la unica puerta de escritura ────────────────

create function crm.fijar_objetivos(
  p_periodo date,
  p_objetivos jsonb
) returns setof crm.objetivos
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_item jsonb;
  v_capital numeric;
  v_ventas int;
  v_conversion numeric;
begin
  -- Actor: SOLO gerencia activa con perfil de portal activo (mismo gate que
  -- actualizar_capacidad_leads_objetivo — un JWT vivo no otorga autoridad).
  if v_actor is null or not exists (
    select 1
    from crm.equipo actor_equipo
    join public.perfiles actor_perfil
      on actor_perfil.id = actor_equipo.perfil_id
    where actor_equipo.perfil_id = v_actor
      and actor_equipo.rol_crm = 'gerencia'
      and actor_equipo.activo = true
      and actor_perfil.activo = true
  ) then
    raise exception 'Solo Gerencia puede fijar las metas del mes'
      using errcode = '42501';
  end if;

  if p_periodo is null
     or extract(day from p_periodo) <> 1
     or p_periodo < date '2026-01-01'
     or p_periodo >= date '2100-01-01' then
    raise exception 'El periodo debe ser el primer dia de un mes valido'
      using errcode = '22023';
  end if;

  if p_objetivos is null
     or jsonb_typeof(p_objetivos) <> 'object'
     or p_objetivos = '{}'::jsonb then
    raise exception 'Se requiere al menos una meta por rol'
      using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_object_keys(p_objetivos) k
    where k not in ('vendedor','supervisor','gerencia')
  ) then
    raise exception 'Rol desconocido en las metas'
      using errcode = '22023';
  end if;

  for v_rol, v_item in
    select key, value from jsonb_each(p_objetivos)
  loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'La meta de % debe ser un objeto', v_rol
        using errcode = '22023';
    end if;
    begin
      v_capital    := coalesce((v_item->>'capital_objetivo')::numeric, 0);
      v_ventas     := coalesce((v_item->>'ventas_objetivo')::int, 0);
      v_conversion := coalesce((v_item->>'conversion_objetivo')::numeric, 0);
    exception when others then
      raise exception 'Meta de % con numeros invalidos', v_rol
        using errcode = '22023';
    end;
    if v_capital < 0 or v_capital > 100000000 then
      raise exception 'Capital objetivo de % fuera de rango (0 a 100 millones PEN)', v_rol
        using errcode = '22023';
    end if;
    if v_ventas < 0 or v_ventas > 1000 then
      raise exception 'Ventas objetivo de % fuera de rango (0 a 1000)', v_rol
        using errcode = '22023';
    end if;
    if v_conversion < 0 or v_conversion > 100 then
      raise exception 'Conversion objetivo de % fuera de rango (0 a 100%%)', v_rol
        using errcode = '22023';
    end if;

    insert into crm.objetivos as o
      (periodo, rol, capital_objetivo, ventas_objetivo, conversion_objetivo, actualizado_por)
    values
      (p_periodo, v_rol, v_capital, v_ventas, v_conversion, v_actor)
    on conflict (periodo, rol) do update
      set capital_objetivo    = excluded.capital_objetivo,
          ventas_objetivo     = excluded.ventas_objetivo,
          conversion_objetivo = excluded.conversion_objetivo,
          actualizado_por     = excluded.actualizado_por,
          actualizado_en      = statement_timestamp();
  end loop;

  return query
  select * from crm.objetivos o
  where o.periodo = p_periodo
  order by o.rol;
end;
$$;

comment on function crm.fijar_objetivos(date, jsonb) is
  'Gerencia fija las metas del mes por rol en una pasada atomica (upsert por (periodo, rol)); cada cambio queda auditado. Payload: {"vendedor":{"capital_objetivo":..,"ventas_objetivo":..,"conversion_objetivo":..},...} (roles parciales permitidos).';

revoke all on function crm.fijar_objetivos(date, jsonb) from public, anon;
grant execute on function crm.fijar_objetivos(date, jsonb) to authenticated, service_role;
-- WARN authenticated_security_definer_function_executable: clase ACEPTADA y
-- documentada (mismo patron que actualizar_capacidad_leads_objetivo): la RPC
-- revoca PUBLIC/anon y gatea por gerencia activa adentro.

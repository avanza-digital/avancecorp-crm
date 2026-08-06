begin;

create table crm.objetivos_vendedores (
  id uuid primary key default gen_random_uuid(),
  periodo date not null,
  vendedor_id uuid not null references crm.equipo(perfil_id),
  supervisor_id uuid not null references crm.equipo(perfil_id),
  capital_objetivo numeric(14,2) not null default 0,
  ventas_objetivo integer not null default 0,
  conversion_objetivo numeric(5,2) not null default 0,
  actualizado_por uuid not null references auth.users(id),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint objetivos_vendedores_periodo_mes check (periodo = date_trunc('month', periodo)::date),
  constraint objetivos_vendedores_personas_distintas check (vendedor_id <> supervisor_id),
  constraint objetivos_vendedores_capital_rango check (capital_objetivo between 0 and 100000000),
  constraint objetivos_vendedores_ventas_rango check (ventas_objetivo between 0 and 1000),
  constraint objetivos_vendedores_conversion_rango check (conversion_objetivo between 0 and 100),
  constraint objetivos_vendedores_periodo_vendedor_uk unique (periodo, vendedor_id)
);

comment on table crm.objetivos_vendedores is
  'Metas mensuales individuales por vendedor. Supervisor y empresa se calculan; no se almacenan.';
comment on column crm.objetivos_vendedores.supervisor_id is
  'Supervisor resuelto desde crm.equipo por la RPC al guardar; el cliente no lo decide.';

alter table crm.objetivos_vendedores enable row level security;

create trigger trg_objetivos_vendedores_actualizado
before update on crm.objetivos_vendedores
for each row execute function private.set_actualizado_en_crm();

create trigger trg_audit_objetivos_vendedores
after insert or delete or update on crm.objetivos_vendedores
for each row execute function private.log_audit_crm();

revoke all on table crm.objetivos_vendedores from public, anon, authenticated;
grant select on table crm.objetivos_vendedores to authenticated;
grant all on table crm.objetivos_vendedores to service_role;

create policy objetivos_vendedores_select
on crm.objetivos_vendedores
for select
to authenticated
using (
  (select private.es_lector_global())
  or exists (
    select 1
    from crm.equipo actor
    join public.perfiles perfil_actor on perfil_actor.id = actor.perfil_id
    where actor.perfil_id = auth.uid()
      and actor.activo
      and perfil_actor.activo
      and (
        actor.rol_crm::text = 'gerencia'
        or (actor.rol_crm::text = 'supervisor' and objetivos_vendedores.supervisor_id = actor.perfil_id)
        or (actor.rol_crm::text = 'vendedor' and objetivos_vendedores.vendedor_id = actor.perfil_id)
      )
  )
);

create or replace function crm.fijar_objetivos_vendedores(
  p_periodo date,
  p_objetivos jsonb
)
returns setof crm.objetivos_vendedores
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_periodo date := date_trunc('month', p_periodo)::date;
  v_total_vendedores integer;
  v_item record;
  v_vendedor_id uuid;
  v_supervisor_id uuid;
  v_capital numeric;
  v_ventas_num numeric;
  v_ventas integer;
  v_conversion numeric;
begin
  perform 1
  from crm.equipo actor
  join public.perfiles perfil_actor on perfil_actor.id = actor.perfil_id
  where actor.perfil_id = auth.uid()
    and actor.activo
    and perfil_actor.activo
    and actor.rol_crm::text = 'gerencia';

  if not found then
    raise exception 'Solo Gerencia puede fijar metas comerciales'
      using errcode = '42501';
  end if;

  if p_periodo is null or p_periodo <> v_periodo then
    raise exception 'El periodo debe ser el primer día del mes'
      using errcode = '22023';
  end if;

  if p_objetivos is null or jsonb_typeof(p_objetivos) <> 'object' then
    raise exception 'Las metas deben enviarse como un objeto por vendedor'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from crm.equipo vendedor
    join public.perfiles perfil_vendedor on perfil_vendedor.id = vendedor.perfil_id
    left join crm.equipo supervisor
      on supervisor.perfil_id = vendedor.supervisor_id
      and supervisor.activo
      and supervisor.rol_crm::text = 'supervisor'
    left join public.perfiles perfil_supervisor
      on perfil_supervisor.id = supervisor.perfil_id
      and perfil_supervisor.activo
    where vendedor.activo
      and perfil_vendedor.activo
      and vendedor.rol_crm::text = 'vendedor'
      and (supervisor.perfil_id is null or perfil_supervisor.id is null)
  ) then
    raise exception 'Todos los vendedores activos deben tener un supervisor activo'
      using errcode = '23514';
  end if;

  select count(*)::integer
  into v_total_vendedores
  from crm.equipo vendedor
  join public.perfiles perfil_vendedor on perfil_vendedor.id = vendedor.perfil_id
  where vendedor.activo
    and perfil_vendedor.activo
    and vendedor.rol_crm::text = 'vendedor';

  if (select count(*) from jsonb_object_keys(p_objetivos)) <> v_total_vendedores
    or exists (
      select 1
      from crm.equipo vendedor
      join public.perfiles perfil_vendedor on perfil_vendedor.id = vendedor.perfil_id
      where vendedor.activo
        and perfil_vendedor.activo
        and vendedor.rol_crm::text = 'vendedor'
        and not (p_objetivos ? vendedor.perfil_id::text)
    )
  then
    raise exception 'Debe enviarse exactamente una meta por cada vendedor activo'
      using errcode = '22023';
  end if;

  for v_item in select key, value from jsonb_each(p_objetivos)
  loop
    begin
      v_vendedor_id := v_item.key::uuid;
    exception when invalid_text_representation then
      raise exception 'Identificador de vendedor inválido'
        using errcode = '22023';
    end;

    if jsonb_typeof(v_item.value) <> 'object'
      or (v_item.value - array['capital_objetivo', 'ventas_objetivo', 'conversion_objetivo']) <> '{}'::jsonb
      or jsonb_typeof(v_item.value -> 'capital_objetivo') is distinct from 'number'
      or jsonb_typeof(v_item.value -> 'ventas_objetivo') is distinct from 'number'
      or jsonb_typeof(v_item.value -> 'conversion_objetivo') is distinct from 'number'
    then
      raise exception 'Formato de meta inválido para el vendedor %', v_vendedor_id
        using errcode = '22023';
    end if;

    v_capital := (v_item.value ->> 'capital_objetivo')::numeric;
    v_ventas_num := (v_item.value ->> 'ventas_objetivo')::numeric;
    v_conversion := (v_item.value ->> 'conversion_objetivo')::numeric;

    if v_capital < 0 or v_capital > 100000000
      or v_ventas_num < 0 or v_ventas_num > 1000 or trunc(v_ventas_num) <> v_ventas_num
      or v_conversion < 0 or v_conversion > 100
    then
      raise exception 'Meta fuera de rango para el vendedor %', v_vendedor_id
        using errcode = '22023';
    end if;
    v_ventas := v_ventas_num::integer;

    select vendedor.supervisor_id
    into v_supervisor_id
    from crm.equipo vendedor
    join public.perfiles perfil_vendedor on perfil_vendedor.id = vendedor.perfil_id
    join crm.equipo supervisor
      on supervisor.perfil_id = vendedor.supervisor_id
      and supervisor.activo
      and supervisor.rol_crm::text = 'supervisor'
    join public.perfiles perfil_supervisor
      on perfil_supervisor.id = supervisor.perfil_id
      and perfil_supervisor.activo
    where vendedor.perfil_id = v_vendedor_id
      and vendedor.activo
      and perfil_vendedor.activo
      and vendedor.rol_crm::text = 'vendedor';

    if not found then
      raise exception 'Vendedor o supervisor fuera de la jerarquía activa'
        using errcode = '23503';
    end if;

    insert into crm.objetivos_vendedores (
      periodo,
      vendedor_id,
      supervisor_id,
      capital_objetivo,
      ventas_objetivo,
      conversion_objetivo,
      actualizado_por
    ) values (
      v_periodo,
      v_vendedor_id,
      v_supervisor_id,
      v_capital,
      v_ventas,
      v_conversion,
      auth.uid()
    )
    on conflict (periodo, vendedor_id) do update
    set supervisor_id = excluded.supervisor_id,
        capital_objetivo = excluded.capital_objetivo,
        ventas_objetivo = excluded.ventas_objetivo,
        conversion_objetivo = excluded.conversion_objetivo,
        actualizado_por = excluded.actualizado_por,
        actualizado_en = now();
  end loop;

  delete from crm.objetivos_vendedores objetivo
  where objetivo.periodo = v_periodo
    and not exists (
      select 1
      from crm.equipo vendedor
      join public.perfiles perfil_vendedor on perfil_vendedor.id = vendedor.perfil_id
      where vendedor.perfil_id = objetivo.vendedor_id
        and vendedor.activo
        and perfil_vendedor.activo
        and vendedor.rol_crm::text = 'vendedor'
    );

  return query
  select objetivo.*
  from crm.objetivos_vendedores objetivo
  where objetivo.periodo = v_periodo
  order by objetivo.supervisor_id, objetivo.vendedor_id;
end;
$$;

comment on function crm.fijar_objetivos_vendedores(date, jsonb) is
  'Reemplazo atómico de metas del mes: Gerencia envía una meta por vendedor; el servidor resuelve supervisores.';

revoke all on function crm.fijar_objetivos_vendedores(date, jsonb) from public, anon;
grant execute on function crm.fijar_objetivos_vendedores(date, jsonb) to authenticated, service_role;

-- El contrato anterior permitía metas independientes por rol. Se conserva
-- para trazabilidad, pero ningún navegador autenticado puede volver a usarlo.
revoke execute on function crm.fijar_objetivos(date, jsonb) from authenticated;

commit;

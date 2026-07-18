-- Distribucion de leads por capital · paso 4A (expansion compatible).
-- Gerencia puede registrar la capacidad objetivo (numero de leads activos)
-- de cada analista, sin abrir escritura directa sobre crm.equipo.
--
-- Frontera: solo objetos del esquema crm. No modifica public ni el portal.

begin;

alter table crm.equipo
  add column capacidad_leads_objetivo smallint;

alter table crm.equipo
  add constraint equipo_capacidad_leads_objetivo_positiva
    check (capacidad_leads_objetivo is null or capacidad_leads_objetivo between 1 and 1000),
  add constraint equipo_capacidad_leads_solo_analista
    check (
      capacidad_leads_objetivo is null
      or rol_crm in ('vendedor', 'supervisor')
    );

comment on column crm.equipo.capacidad_leads_objetivo is
  'Cantidad objetivo de leads activos que puede gestionar el analista. NULL = aun no configurada.';

create function crm.actualizar_capacidad_leads_objetivo(
  p_analista_id uuid,
  p_capacidad_leads_objetivo integer
)
returns table (
  perfil_id uuid,
  capacidad_leads_objetivo smallint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
begin
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
    raise exception 'Solo Gerencia puede configurar la capacidad de los analistas'
      using errcode = '42501';
  end if;

  if p_capacidad_leads_objetivo is not null
     and p_capacidad_leads_objetivo not between 1 and 1000 then
    raise exception 'La capacidad debe estar entre 1 y 1000 leads, o quedar sin configurar'
      using errcode = '22023';
  end if;

  return query
  update crm.equipo e
     set capacidad_leads_objetivo = p_capacidad_leads_objetivo,
         actualizado_en = statement_timestamp()
   where e.perfil_id = p_analista_id
     and e.activo = true
     and e.rol_crm in ('vendedor', 'supervisor')
     and exists (
       select 1
       from public.perfiles perfil_objetivo
       where perfil_objetivo.id = e.perfil_id
         and perfil_objetivo.activo = true
     )
  returning e.perfil_id, e.capacidad_leads_objetivo;

  if not found then
    raise exception 'Analista activo no encontrado'
      using errcode = 'P0002';
  end if;
end;
$$;

comment on function crm.actualizar_capacidad_leads_objetivo(uuid, integer) is
  'Gerencia fija o limpia la capacidad objetivo de un vendedor/supervisor activo; el cambio queda auditado.';

revoke all on function crm.actualizar_capacidad_leads_objetivo(uuid, integer)
  from public, anon;
grant execute on function crm.actualizar_capacidad_leads_objetivo(uuid, integer)
  to authenticated;

commit;

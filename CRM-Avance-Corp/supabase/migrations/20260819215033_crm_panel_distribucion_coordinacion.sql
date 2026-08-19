-- ============================================================================
-- CRM · Panel de distribución para Coordinación
--
-- Foto actual, sin PII, de los leads que Rosa ya distribuyó: una fila por
-- supervisor (su bandeja + la cartera de sus analistas) y una por analista.
-- El origen se filtra en el servidor; por defecto incluye Referido, Walking
-- (`oficina`) y cualquier otro origen vigente o histórico.
-- ============================================================================

begin;

set local lock_timeout = '5s';

create or replace function crm.panel_distribucion_reparto(
  p_supervisor uuid default null,
  p_analista uuid default null,
  p_origen text default null,
  p_solo_activos boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_payload jsonb;
begin
  if p_solo_activos is null then
    raise exception 'El filtro de leads activos es obligatorio'
      using errcode = '22023';
  end if;

  if not private.puede_operar_reparto_crm() then
    raise exception 'Solo Coordinacion o Gerencia puede ver el panel de distribución'
      using errcode = '42501';
  end if;

  with
  supervisores_base as materialized (
    select equipo.perfil_id, perfil.nombre_completo
    from crm.equipo equipo
    join public.perfiles perfil on perfil.id = equipo.perfil_id
    where equipo.rol_crm = 'supervisor'
      and equipo.activo = true
      and perfil.activo = true
      and (p_supervisor is null or equipo.perfil_id = p_supervisor)
  ),
  analistas as materialized (
    select
      equipo.perfil_id,
      equipo.supervisor_id,
      perfil.nombre_completo,
      coalesce(supervisor_perfil.nombre_completo, 'Sin supervisor') as supervisor_nombre
    from crm.equipo equipo
    join public.perfiles perfil on perfil.id = equipo.perfil_id
    left join public.perfiles supervisor_perfil on supervisor_perfil.id = equipo.supervisor_id
    where equipo.rol_crm = 'vendedor'
      and equipo.activo = true
      and perfil.activo = true
      and (p_supervisor is null or equipo.supervisor_id = p_supervisor)
      and (p_analista is null or equipo.perfil_id = p_analista)
  ),
  leads_filtrados as materialized (
    select lead.id, lead.vendedor_id, lead.asignado_supervisor_id
    from crm.leads lead
    where (not p_solo_activos or lead.activo = true)
      and (p_origen is null or lead.origen = p_origen)
  ),
  conteos_analistas as materialized (
    select
      analista.perfil_id,
      analista.supervisor_id,
      analista.nombre_completo,
      analista.supervisor_nombre,
      count(lead.id)::int as total_leads
    from analistas analista
    left join leads_filtrados lead on lead.vendedor_id = analista.perfil_id
    group by
      analista.perfil_id,
      analista.supervisor_id,
      analista.nombre_completo,
      analista.supervisor_nombre
  ),
  conteos_supervisores as materialized (
    select
      supervisor.perfil_id,
      supervisor.nombre_completo,
      (
        case when p_analista is null then (
          select count(*)::int
          from leads_filtrados lead
          where lead.asignado_supervisor_id = supervisor.perfil_id
        ) else 0 end
        + coalesce((
          select sum(analista.total_leads)::int
          from conteos_analistas analista
          where analista.supervisor_id = supervisor.perfil_id
        ), 0)
      )::int as total_leads
    from supervisores_base supervisor
    where p_analista is null
       or exists (
         select 1
         from conteos_analistas analista
         where analista.supervisor_id = supervisor.perfil_id
       )
  ),
  leads_visibles as materialized (
    select lead.id
    from leads_filtrados lead
    where p_analista is null
      and lead.asignado_supervisor_id in (
        select supervisor.perfil_id from conteos_supervisores supervisor
      )
    union
    select lead.id
    from leads_filtrados lead
    where lead.vendedor_id in (
      select analista.perfil_id from conteos_analistas analista
    )
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', now(),
    'total_leads', (select count(*)::int from leads_visibles),
    'supervisores', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'perfil_id', supervisor.perfil_id,
          'nombre', supervisor.nombre_completo,
          'total_leads', supervisor.total_leads
        )
        order by supervisor.nombre_completo
      )
      from conteos_supervisores supervisor
    ), '[]'::jsonb),
    'analistas', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'perfil_id', analista.perfil_id,
          'nombre', analista.nombre_completo,
          'supervisor_id', analista.supervisor_id,
          'supervisor_nombre', analista.supervisor_nombre,
          'total_leads', analista.total_leads
        )
        order by analista.nombre_completo
      )
      from conteos_analistas analista
    ), '[]'::jsonb)
  )
  into v_payload;

  return v_payload;
end;
$function$;

comment on function crm.panel_distribucion_reparto(uuid, uuid, text, boolean) is
  'Foto filtrable y sin PII de la carga actual por supervisor y analista. Incluye todos los orígenes por defecto. Solo Coordinación o Gerencia activas.';

revoke all on function crm.panel_distribucion_reparto(uuid, uuid, text, boolean)
  from public, anon, authenticated, service_role;
grant execute on function crm.panel_distribucion_reparto(uuid, uuid, text, boolean)
  to authenticated;

commit;

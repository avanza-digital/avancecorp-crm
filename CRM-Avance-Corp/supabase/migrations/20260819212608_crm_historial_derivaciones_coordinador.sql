-- ============================================================================
-- CRM · Historial de derivaciones para Coordinación
--
-- La bitácora de reasignaciones registra la entrada a una bandeja de supervisor
-- y los pases posteriores a un analista. Es la fuente completa del movimiento;
-- el ledger no abre episodio cuando el lead solo entra a una bandeja.
--
-- Coordinación sigue sin SELECT directo sobre leads ni actividades. Esta RPC
-- devuelve solo datos de seguimiento, sin contacto, notas ni gestión comercial.
-- ============================================================================

begin;

set local lock_timeout = '5s';

create index if not exists actividades_reasignacion_historial_idx
  on crm.actividades (creado_en desc, id desc)
  where tipo = 'reasignacion';

create or replace function crm.historial_derivaciones(
  p_limite integer default 100,
  p_derivado_antes timestamptz default null,
  p_actividad_antes uuid default null
)
returns table (
  actividad_id uuid,
  lead_id uuid,
  nombre_completo text,
  distrito text,
  origen text,
  monto_estimado numeric,
  moneda text,
  etapa_actual text,
  movimiento text,
  derivado_en timestamptz,
  responsable_anterior text,
  responsable_nuevo text,
  derivado_por_nombre text
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
begin
  if p_limite is null or p_limite < 1 or p_limite > 100 then
    raise exception 'El límite del historial debe estar entre 1 y 100'
      using errcode = '22023';
  end if;

  if (p_derivado_antes is null) <> (p_actividad_antes is null) then
    raise exception 'El cursor del historial está incompleto'
      using errcode = '22023';
  end if;

  if v_actor is null or not exists (
    select 1
    from crm.equipo actor_equipo
    join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
    where actor_equipo.perfil_id = v_actor
      and actor_equipo.rol_crm in ('coordinador', 'gerencia')
      and actor_equipo.activo = true
      and actor_perfil.activo = true
  ) then
    raise exception 'Solo Coordinación puede ver el historial de derivaciones'
      using errcode = '42501';
  end if;

  return query
  select
    actividad.id,
    lead.id,
    lead.nombre_completo,
    lead.distrito,
    lead.origen,
    lead.monto_estimado,
    lead.moneda,
    lead.etapa,
    coalesce(actividad.metadata ->> 'movimiento', 'reasignacion'),
    actividad.creado_en,
    case
      when actividad.metadata ->> 'vendedor_anterior' is not null
        then coalesce(vendedor_anterior.nombre_completo, 'Responsable no disponible')
      when actividad.metadata ->> 'supervisor_anterior' is not null
        then coalesce('Bandeja de ' || supervisor_anterior.nombre_completo, 'Bandeja no disponible')
      else 'Sin asignar'
    end,
    case
      when actividad.metadata ->> 'vendedor_nuevo' is not null
        then coalesce(vendedor_nuevo.nombre_completo, 'Responsable no disponible')
      when actividad.metadata ->> 'supervisor_nuevo' is not null
        then coalesce('Bandeja de ' || supervisor_nuevo.nombre_completo, 'Bandeja no disponible')
      else 'Sin asignar'
    end,
    coalesce(actor.nombre_completo, 'Sistema')
  from crm.actividades actividad
  join crm.leads lead on lead.id = actividad.lead_id
  left join public.perfiles vendedor_anterior
    on vendedor_anterior.id::text = actividad.metadata ->> 'vendedor_anterior'
  left join public.perfiles supervisor_anterior
    on supervisor_anterior.id::text = actividad.metadata ->> 'supervisor_anterior'
  left join public.perfiles vendedor_nuevo
    on vendedor_nuevo.id::text = actividad.metadata ->> 'vendedor_nuevo'
  left join public.perfiles supervisor_nuevo
    on supervisor_nuevo.id::text = actividad.metadata ->> 'supervisor_nuevo'
  left join public.perfiles actor on actor.id = actividad.creado_por
  where actividad.tipo = 'reasignacion'
    and (
      p_derivado_antes is null
      or (actividad.creado_en, actividad.id) < (p_derivado_antes, p_actividad_antes)
    )
  order by actividad.creado_en desc, actividad.id desc
  limit p_limite;
end;
$function$;

comment on function crm.historial_derivaciones(integer, timestamptz, uuid) is
  'Historial paginado y sin PII de las derivaciones de leads. Solo Coordinación o Gerencia activas; no concede SELECT directo sobre leads ni actividades.';

revoke all on function crm.historial_derivaciones(integer, timestamptz, uuid)
  from public, anon;
grant execute on function crm.historial_derivaciones(integer, timestamptz, uuid)
  to authenticated;

commit;

-- Alinea el texto visible con el predicado de autorizacion centralizado.
-- private.es_lector_global() incluye los roles globales vigentes del portal
-- (directorio/admin/superadmin); no se amplia ningun permiso.

begin;

create or replace function crm.metricas_distribucion_leads_fn(
  p_desde date,
  p_hasta date
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_ahora timestamptz := statement_timestamp();
  v_hoy date := (v_ahora at time zone 'America/Lima')::date;
begin
  if v_actor is null or not (
    exists (
      select 1
      from crm.equipo e
      join public.perfiles p on p.id = e.perfil_id
      where e.perfil_id = v_actor
        and e.rol_crm = 'gerencia'
        and e.activo = true
        and p.activo = true
    )
    or private.es_lector_global()
  ) then
    raise exception 'Solo Gerencia o un lector global puede consultar estas metricas'
      using errcode = '42501';
  end if;

  if p_desde is null
     or p_hasta is null
     or p_desde > p_hasta
     or p_hasta > v_hoy
     or (p_hasta - p_desde) > 365 then
    raise exception 'Periodo invalido: usa fechas hasta hoy y un maximo de 366 dias'
      using errcode = '22023';
  end if;

  return private.metricas_distribucion_leads_core(p_desde, p_hasta, v_ahora);
end;
$function$;

comment on function crm.metricas_distribucion_leads_fn(date, date) is
  'Fotografia descriptiva de distribucion, capacidad, resultados y SLA por episodio; exclusiva de Gerencia o lectores globales autorizados.';

revoke all on function crm.metricas_distribucion_leads_fn(date, date)
  from public, anon;
grant execute on function crm.metricas_distribucion_leads_fn(date, date)
  to authenticated;

commit;

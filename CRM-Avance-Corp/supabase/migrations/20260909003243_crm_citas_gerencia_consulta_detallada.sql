-- Consulta de Citas de Gerencia: filas completas del mes y su seguimiento.
-- Lectura nueva. No altera escritores, métricas anteriores ni objetos de public.
-- Los cierres NO prueban depósitos; esa fuente queda explícitamente sin verificar.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

create or replace function private.citas_gerencia_consulta(p_desde date, p_hasta date)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_uid uuid := (select auth.uid());
  v_ahora timestamptz := now();
  v_ini timestamptz;
  v_fin timestamptz;
  v_filas jsonb;
  v_clientes integer;
begin
  -- Esta puerta entrega identidades; directorio conserva su agregador sin PII.
  if v_uid is null or private.rol_crm(v_uid) is distinct from 'gerencia'
  then raise exception 'No autorizado' using errcode='42501'; end if;
  if p_desde is null or p_hasta is null or p_desde > p_hasta
    or p_desde <> date_trunc('month',p_desde)::date
    or p_hasta <> (date_trunc('month',p_desde)+interval '1 month - 1 day')::date
    or p_desde < date '2000-01-01'
    or p_desde > ((v_ahora at time zone 'America/Lima')::date + interval '1 year')::date
  then raise exception 'Seleccione un mes válido' using errcode='22023'; end if;
  v_ini := p_desde::timestamp at time zone 'America/Lima';
  v_fin := (p_hasta+1)::timestamp at time zone 'America/Lima';

  with cohorte as materialized (
    select distinct t.lead_id from crm.tareas t join crm.leads l on l.id=t.lead_id
    where t.tipo='reunion' and t.activo and l.activo and t.creado_en<=v_ahora
      and t.vence_en>=v_ini and t.vence_en<v_fin
  ), historial as materialized (
    select t.*, l.nombre_completo, l.telefono, l.origen, l.moneda, l.monto_estimado
    from crm.tareas t join cohorte c on c.lead_id=t.lead_id join crm.leads l on l.id=t.lead_id
    where t.tipo='reunion' and t.activo and t.creado_en<=v_ahora
    -- La fila extra dispara un error; nunca se entrega un historial truncado.
    order by t.vence_en,t.id limit 10001
  ), cierres as materialized (
    -- Misma evidencia de cierre que conversion_episodios: resultado de una
    -- asignación y exclusión de cierres anulados. No calcula pesos ni índices.
    -- Incluye cierres previos al mes para describir bien todo el historial.
    select la.lead_id, coalesce(la.resultado_en,la.finalizado_en) as fecha_numerador
    from crm.lead_asignaciones la join cohorte c on c.lead_id=la.lead_id
    where la.resultado='convertido' and not private.cierre_externo_anulado(la.lead_id)
      and coalesce(la.resultado_en,la.finalizado_en)<=v_ahora
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',t.id,'lead_id',t.lead_id,'nombre',t.nombre_completo,'telefono',t.telefono,
    'analista_id',t.vendedor_id,'analista_nombre',coalesce(p.nombre_completo,'Sin analista'),
    'supervisor_id',coalesce(e.supervisor_id,t.asignado_supervisor_id),
    'supervisor_nombre',coalesce(ps.nombre_completo,'Sin supervisor'),
    'vence_en',t.vence_en,'estado',t.estado,'cancelada_por',t.cancelada_por,
    'modalidad',coalesce(t.modalidad_reunion,'sin_clasificar'),'origen',t.origen,
    'moneda',t.moneda,'monto_estimado',t.monto_estimado,
    'resultado',coalesce(t.resultado_reunion,'sin_clasificar'),
    'nota',coalesce(t.detalle_cierre_reunion,t.nota,''),
    'reagendada_de',case when exists (select 1 from historial a where a.id=t.reagendada_de and a.lead_id=t.lead_id) then t.reagendada_de end,
    'creado_en',t.creado_en,
    'asistencia_registrada_en',case when t.estado='completada' then a.creado_en end,
    'cierre_posterior',exists(select 1 from cierres c where c.lead_id=t.lead_id and c.fecha_numerador>=t.vence_en)
  ) order by t.vence_en,t.id),'[]'::jsonb) into v_filas
  from historial t
  left join public.perfiles p on p.id=t.vendedor_id
  left join crm.equipo e on e.perfil_id=t.vendedor_id
  left join public.perfiles ps on ps.id=coalesce(e.supervisor_id,t.asignado_supervisor_id)
  left join crm.actividades a on a.id=t.resultado_actividad_id and a.lead_id=t.lead_id
    and a.tipo='reunion_realizada' and a.creado_en<=v_ahora;

  -- Nunca devolver un subconjunto como si fuera la totalidad de la consulta.
  if jsonb_array_length(v_filas)>10000 then
    raise exception 'La consulta supera el tamaño admitido; requiere paginación de servidor'
      using errcode='54000';
  end if;
  select count(*) into v_clientes from crm.tareas
    where tipo='reunion' and activo and perfil_id is not null and creado_en<=v_ahora
      and vence_en>=v_ini and vence_en<v_fin;
  return jsonb_build_object('version',1,'periodo',jsonb_build_object('desde',p_desde,'hasta',p_hasta),
    'generado_en',v_ahora,'citas',v_filas,'depositos','[]'::jsonb,
    'disponibilidad_depositos','sin_registro','citas_clientes',v_clientes);
end;
$fn$;
revoke all on function private.citas_gerencia_consulta(date,date) from public,anon,authenticated;
grant execute on function private.citas_gerencia_consulta(date,date) to authenticated;

create or replace function crm.citas_gerencia_consulta_fn(p_desde date,p_hasta date)
returns jsonb language sql stable security invoker set search_path = '' as $fn$
  select private.citas_gerencia_consulta(p_desde,p_hasta);
$fn$;
revoke all on function crm.citas_gerencia_consulta_fn(date,date) from public,anon,authenticated;
grant execute on function crm.citas_gerencia_consulta_fn(date,date) to authenticated;
comment on function crm.citas_gerencia_consulta_fn(date,date) is
  'Gerencia activa: citas de leads del mes e historial explícito. Depósitos sin verificar; no se infieren de cierres. Postventa en Agenda.';
notify pgrst,'reload schema';
commit;

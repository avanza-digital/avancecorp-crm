-- REVERSION PREPARADA. No ejecutar sin decisión expresa de volver a la versión anterior.
-- Restaura solamente el lector de Citas y su declaración. Conserva historial/configuración.
-- Requiere también restaurar el artefacto frontend previo verificado.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
lock table private.analitica_leads_citas_exenciones,private.analitica_lc_sello in share row exclusive mode;
do $guard$ begin
 if md5(pg_get_functiondef('private.citas_gerencia_consulta(date,date)'::regprocedure))
   is distinct from '4ad2b90baf96b11b63a626122bd5d64b' then
   raise exception 'El lector no es la candidata ensayada; revisar antes de revertir';
 end if;
 perform private.assert_analitica_leads_citas();
end $guard$;
CREATE OR REPLACE FUNCTION private.citas_gerencia_consulta(p_desde date, p_hasta date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_ahora timestamptz := now();
  v_ini timestamptz;
  v_fin timestamptz;
  v_filas jsonb;
  v_clientes integer;
  v_conversiones jsonb;
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
    select distinct e.lead_id
    from private.citas_episodios(v_ini,v_fin,v_ahora) e
    join crm.tareas t on t.id=e.tarea_id
    join crm.leads l on l.id=e.lead_id
    where l.activo and t.creado_en<=v_ahora
  ), limites_historial as (
    -- Sólo acota la lectura del núcleo; no clasifica ni cuenta estas tareas.
    select min(t.vence_en) as inicio, max(t.vence_en)+interval '1 microsecond' as fin
    from crm.tareas t join cohorte c on c.lead_id=t.lead_id
    where t.tipo='reunion' and t.activo and t.creado_en<=v_ahora
  ), historial as materialized (
    select t.*, l.nombre_completo, l.telefono, l.origen, l.moneda, l.monto_estimado,
      e.modalidad as modalidad_canonica, e.resultado as resultado_canonico,
      case when e.pendiente_cierre then 'vencida'
        when e.programada_futura then 'programada'
        when e.realizada then 'realizada'
        when e.no_show then 'no_show'
        when e.reprogramada then 'reprogramada'
        when e.cancelada_asesor then 'cancelada'
        when e.cancelada_sistema then 'sistema'
      end as estado_comercial
    from limites_historial b
    cross join lateral private.citas_episodios(
      coalesce(b.inicio,v_ini),coalesce(b.fin,v_fin),v_ahora,
      coalesce((select array_agg(c.lead_id) from cohorte c),'{}'::uuid[])) e
    join cohorte c on c.lead_id=e.lead_id
    join crm.tareas t on t.id=e.tarea_id
    join crm.leads l on l.id=e.lead_id
    where t.creado_en<=v_ahora
    -- La fila extra dispara un error; nunca se entrega un historial truncado.
    order by t.vence_en,t.id limit 10001
  ), cierres as materialized (
    -- Los hechos de cierre proceden del núcleo. Ningún aporte ponderado
    -- participa en este indicador operativo. El factor no modifica el hecho.
    -- Basta desde la primera cita: sólo se pregunta por cierres posteriores.
    select e.lead_id,max(e.fecha_numerador) as ultimo_cierre
    from private.conversion_cierres(
      coalesce((select min(h.vence_en) from historial h),v_ini),
      v_ahora+interval '1 microsecond',p_desde,true,'{}'::uuid[],1,
      coalesce((select array_agg(c.lead_id) from cohorte c),'{}'::uuid[])) e
    join cohorte c on c.lead_id=e.lead_id
    where e.tipo='cierre' and not e.anulado and e.fecha_numerador<=v_ahora
    group by e.lead_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',t.id,'lead_id',t.lead_id,'nombre',t.nombre_completo,'telefono',t.telefono,
    'analista_id',t.vendedor_id,'analista_nombre',coalesce(p.nombre_completo,'Sin analista'),
    'supervisor_id',coalesce(e.supervisor_id,t.asignado_supervisor_id),
    'supervisor_nombre',coalesce(ps.nombre_completo,'Sin supervisor'),
    'vence_en',t.vence_en,'estado',t.estado,'estado_comercial',t.estado_comercial,'cancelada_por',t.cancelada_por,
    'modalidad',t.modalidad_canonica,'origen',t.origen,
    'moneda',t.moneda,'monto_estimado',t.monto_estimado,
    'resultado',t.resultado_canonico,
    'nota',coalesce(t.detalle_cierre_reunion,t.nota,''),
    'reagendada_de',anterior.id,
    'creado_en',t.creado_en,
    'asistencia_registrada_en',case when t.estado='completada' then a.creado_en end,
    'cierre_posterior',coalesce(c.ultimo_cierre>=t.vence_en,false)
  ) order by t.vence_en,t.id),'[]'::jsonb) into v_filas
  from historial t
  left join historial anterior on anterior.id=t.reagendada_de and anterior.lead_id=t.lead_id
  left join cierres c on c.lead_id=t.lead_id
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
  if exists(select 1 from jsonb_array_elements(v_filas) c where c->>'estado_comercial' is null) then
    raise exception 'Estado de reunión sin clasificación canónica: %',
      (select c->>'estado' from jsonb_array_elements(v_filas) c where c->>'estado_comercial' is null limit 1)
      using errcode='22023';
  end if;
  select count(*) into v_clientes
    from private.citas_episodios(v_ini,v_fin,v_ahora) e
    join crm.tareas t on t.id=e.tarea_id
    where t.perfil_id is not null and t.creado_en<=v_ahora;
  -- Un evento por lead, con cliente vinculado y conversión vigente al corte.
  -- El estado convertido también existe en cierres externos sin cliente del
  -- portal: esos registros no se equiparan automáticamente a esta regla.
  select coalesce(jsonb_agg(jsonb_build_object(
    'lead_id',l.id,'perfil_id',l.perfil_id,'convertido_en',l.convertido_en
  ) order by l.convertido_en,l.id),'[]'::jsonb) into v_conversiones
  from crm.leads l join public.perfiles pc on pc.id=l.perfil_id and pc.rol='cliente'
  where l.id in (select (c->>'lead_id')::uuid from jsonb_array_elements(v_filas) c)
    and l.activo and l.etapa='convertido' and l.perfil_id is not null
    and l.convertido_en is not null and l.convertido_en<=v_ahora
    and not private.cierre_anulado(l.id);
  -- Inactivar el acceso del cliente no anula su conversión. La anulación de
  -- negocio se decide exclusivamente con el helper canónico anterior.
  return jsonb_build_object('version',2,'periodo',jsonb_build_object('desde',p_desde,'hasta',p_hasta),
    'generado_en',v_ahora,'citas',v_filas,'conversiones',v_conversiones,
    'disponibilidad_depositos','conversion_cliente','citas_clientes',v_clientes);
end;
$function$;

update private.analitica_leads_citas_exenciones
set huella='201ec55e8c57ee8cbb83edead86a29f8',
 razon='Detalle operativo de Gerencia: citas y estados desde citas_episodios; cierres desde conversion_cierres, compartido por conversion_episodios, sin ponderar. Joins crudos sólo para identidad, historial y evidencia de conversión vigente a perfil cliente; no calcula capital ni metas.'
where objeto='private.citas_gerencia_consulta(date,date)';
update private.analitica_lc_sello set sello=private.huella_exenciones_analitica_lc(),sellado_en=now() where id;
select private.assert_analitica_leads_citas();
do $verify$ begin
 if md5(pg_get_functiondef('private.citas_gerencia_consulta(date,date)'::regprocedure))
   is distinct from '8b2eeffc547a1c095926ddb76876d262' then
   raise exception 'La reversión no coincide con la definición productiva capturada';
 end if;
end $verify$;
commit;

-- CANDIDATA: fuentes de gestión mensual de Citas. No publicar durante la preparación.
-- Depende de borradores, base asignada y aplicación versionada de configuración.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
lock table private.analitica_leads_citas_exenciones,private.analitica_lc_sello in share row exclusive mode;
do $preflight$ begin
  if md5(pg_get_functiondef('private.citas_gerencia_consulta(date,date)'::regprocedure))
    is distinct from '62c37bf3b3921ad3ffacd0e3ebfe88b9' then
    raise exception 'La consulta de Citas cambió; revisar el contrato antes de aplicar';
  end if;
  if md5(pg_get_functiondef('private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure))
    is distinct from 'c9e58c1da9dd7a5d52991c9e47dc19d5' then
    raise exception 'El núcleo de capital cambió; revisar el contrato del ticket';
  end if;
  perform private.assert_analitica_leads_citas();
end $preflight$;
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
  v_asignaciones jsonb;
  v_poblacion jsonb;
  v_conversiones_gestion jsonb;
  v_capital jsonb;
  v_config jsonb;
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
    union
    -- Citas generadas en el mes aunque su fecha prevista esté en otro mes.
    select t.lead_id from crm.tareas t join crm.leads l on l.id=t.lead_id
    where t.tipo='reunion' and t.activo and l.activo
      and t.creado_en>=v_ini and t.creado_en<v_fin and t.creado_en<=v_ahora
    union
    -- Entrevistas registradas este mes, aun cuando se programaron antes.
    select t.lead_id from crm.tareas t
    join crm.leads l on l.id=t.lead_id
    join crm.actividades a on a.id=t.resultado_actividad_id and a.lead_id=t.lead_id
    where t.tipo='reunion' and t.activo and l.activo and t.estado='completada'
      and a.tipo='reunion_realizada' and a.creado_en>=v_ini and a.creado_en<v_fin and a.creado_en<=v_ahora
    union
    select la.lead_id from crm.lead_asignaciones la
    where la.asignado_en>=v_ini and la.asignado_en<v_fin and la.asignado_en<=v_ahora
    union
    select c.lead_id from private.conversion_cierres(v_ini,least(v_fin,v_ahora+interval '1 microsecond'),
      p_desde,true,'{}'::uuid[],1,null::uuid[]) c where not c.anulado
  ), limites_historial as (
    -- Sólo acota la lectura del núcleo; no clasifica ni cuenta estas tareas.
    select min(t.vence_en) as inicio, max(t.vence_en)+interval '1 microsecond' as fin
    from crm.tareas t join cohorte c on c.lead_id=t.lead_id
    where t.tipo='reunion' and t.activo and t.creado_en<=v_ahora
  ), historial as materialized (
    select t.*, l.nombre_completo, l.telefono, l.origen, l.moneda, l.monto_estimado, l.alta_manual, l.creado_por as lead_creado_por,
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
    'manual_propio',coalesce(t.alta_manual and t.lead_creado_por=t.vendedor_id,false),
    'registro_manual',coalesce(t.alta_manual,false),
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
  -- Base completa: una persona por analista y mes, incluso sin citas,
  -- transferida o descartada. No se reconstruye desde la cartera actual.
  -- El registro propio se acredita con alta_manual Y el autor del alta.
  with asignadas as (
    select distinct on (la.lead_id,la.analista_id)
      la.lead_id,la.analista_id,la.asignado_en,la.supervisor_origen_id,
      l.nombre_completo,l.telefono,l.origen,l.moneda,l.monto_estimado,l.alta_manual,
      coalesce(l.alta_manual and l.creado_por=la.analista_id,false) as manual_propio
    from crm.lead_asignaciones la join crm.leads l on l.id=la.lead_id
    where la.asignado_en>=v_ini and la.asignado_en<v_fin and la.asignado_en<=v_ahora
    order by la.lead_id,la.analista_id,la.asignado_en,la.id
    limit 10001
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'lead_id',a.lead_id,'analista_id',a.analista_id,
    'analista_nombre',coalesce(p.nombre_completo,'Sin analista'),
    'supervisor_id',coalesce(e.supervisor_id,a.supervisor_origen_id),
    'supervisor_nombre',coalesce(ps.nombre_completo,'Sin supervisor'),
    'asignado_en',a.asignado_en,'manual_propio',a.manual_propio,'registro_manual',coalesce(a.alta_manual,false),
    'nombre',a.nombre_completo,'telefono',a.telefono,'origen',a.origen,
    'moneda',a.moneda,'monto_estimado',a.monto_estimado
  ) order by a.asignado_en,a.lead_id,a.analista_id),'[]'::jsonb) into v_asignaciones
  from asignadas a
  left join public.perfiles p on p.id=a.analista_id
  left join crm.equipo e on e.perfil_id=a.analista_id
  left join public.perfiles ps on ps.id=coalesce(e.supervisor_id,a.supervisor_origen_id);
  if jsonb_array_length(v_asignaciones)>10000 then
    raise exception 'La base de leads asignados supera el tamaño admitido'
      using errcode='54000';
  end if;
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
  -- Identidad de origen retenida para configurar atribución sin reconstruirla
  -- desde el responsable actual. Incluye asignados sin citas y cierres del mes.
  with ids as (
    select (c->>'lead_id')::uuid as id from jsonb_array_elements(v_filas) c
    union select (a->>'lead_id')::uuid from jsonb_array_elements(v_asignaciones) a
    union select c.lead_id from private.conversion_cierres(v_ini,least(v_fin,v_ahora+interval '1 microsecond'),
      p_desde,true,'{}'::uuid[],1,null::uuid[]) c where not c.anulado
  ), personas as (
    select l.*,primera.analista_id as analista_origen,primera.asignado_en as primera_asignacion,
      primera.supervisor_origen_id
    from ids join crm.leads l on l.id=ids.id
    left join lateral (select la.analista_id,la.asignado_en,la.supervisor_origen_id from crm.lead_asignaciones la
      where la.lead_id=l.id and la.asignado_en<=v_ahora
      order by la.asignado_en,la.ciclo_n,la.episodio_n,la.id limit 1) primera on true
    order by l.id limit 10001
  )
  select coalesce(jsonb_agg(jsonb_build_object('lead_id',p.id,'nombre',p.nombre_completo,
    'telefono',p.telefono,'origen',p.origen,'moneda',p.moneda,'monto_estimado',p.monto_estimado,
    'registro_manual',coalesce(p.alta_manual,false),'creado_por',p.creado_por,
    'analista_origen_id',p.analista_origen,'primera_asignacion_en',p.primera_asignacion,
    'analista_origen_nombre',coalesce(pa.nombre_completo,'Sin analista'),
    'supervisor_origen_id',coalesce(e.supervisor_id,p.supervisor_origen_id),
    'supervisor_origen_nombre',coalesce(ps.nombre_completo,'Sin supervisor')
  ) order by p.id),'[]'::jsonb) into v_poblacion from personas p
  left join public.perfiles pa on pa.id=p.analista_origen
  left join crm.equipo e on e.perfil_id=p.analista_origen
  left join public.perfiles ps on ps.id=coalesce(e.supervisor_id,p.supervisor_origen_id);
  if jsonb_array_length(v_poblacion)>10000 then
    raise exception 'La población de gestión supera el tamaño admitido' using errcode='54000';
  end if;

  -- La atribución procede del ledger de conversión; no del dueño actual.
  with cierres as materialized (
    select c.lead_id,c.analista_id,c.fecha_numerador from private.conversion_cierres(
      '-infinity'::timestamptz,v_ahora+interval '1 microsecond',p_desde,true,'{}'::uuid[],1,
      array(select (p->>'lead_id')::uuid from jsonb_array_elements(v_poblacion) p)) c
    where not c.anulado
  )
  select coalesce(jsonb_agg(jsonb_build_object('lead_id',l.id,'perfil_id',l.perfil_id,
    'convertido_en',l.convertido_en,'analista_id',c.analista_id,
    'analista_nombre',coalesce(pa.nombre_completo,'Sin analista'),
    'supervisor_id',e.supervisor_id,'supervisor_nombre',coalesce(ps.nombre_completo,'Sin supervisor'),
    'contrato_id',l.contrato_id
  ) order by l.convertido_en,l.id),'[]'::jsonb) into v_conversiones_gestion
  from crm.leads l join public.perfiles pc on pc.id=l.perfil_id and pc.rol='cliente'
  left join cierres c on c.lead_id=l.id
  left join public.perfiles pa on pa.id=c.analista_id
  left join crm.equipo e on e.perfil_id=c.analista_id
  left join public.perfiles ps on ps.id=e.supervisor_id
  where l.id=any(array(select (p->>'lead_id')::uuid from jsonb_array_elements(v_poblacion) p))
    and l.activo and l.etapa='convertido' and l.convertido_en is not null
    and l.convertido_en<=v_ahora and not private.cierre_anulado(l.id);

  -- Importes reales del mes: contratos nuevos vinculados al perfil cliente.
  -- El vínculo canónico es contratos.cliente_id=leads.perfil_id. contrato_id
  -- del lead no se completa en el flujo actual; no es una fuente del ticket.
  -- El núcleo devuelve el capital; no se cuenta el monto estimado del lead,
  -- ni se añaden renovaciones, upgrades o desgloses al ticket inicial.
  with capital as materialized (
    select k.* from private.capital_episodios(v_ini,
      least(v_fin,((v_ahora at time zone 'America/Lima')::date+1)::timestamp at time zone 'America/Lima'),
      true,'{}'::uuid[]) k
    where k.tipo='contrato_nuevo' and k.medida='stock' and not k.anulado
  ), iniciales as (
    select distinct on(k.contrato_id) k.*,c->>'lead_id' as lead_cliente
    from capital k join jsonb_array_elements(v_conversiones_gestion) c
      on (c->>'perfil_id')::uuid=k.cliente_id
    where (c->>'convertido_en')::timestamptz>=v_ini and (c->>'convertido_en')::timestamptz<v_fin
    order by k.contrato_id,(c->>'convertido_en')::timestamptz,c->>'lead_id'
  )
  select coalesce(jsonb_agg(jsonb_build_object('contrato_id',k.contrato_id,'lead_id',k.lead_cliente,
    'perfil_id',k.cliente_id,'analista_id',k.analista_id,'moneda',k.moneda,'monto',k.monto,'fecha',k.fecha
  ) order by k.contrato_id),'[]'::jsonb) into v_capital from iniciales k;

  v_config:=private.control_citas_vigente(p_desde);
  return jsonb_build_object('version',2,'periodo',jsonb_build_object('desde',p_desde,'hasta',p_hasta),
    'generado_en',v_ahora,'citas',v_filas,'conversiones',v_conversiones,
    'disponibilidad_depositos','conversion_cliente','citas_clientes',v_clientes,
    'gestion',jsonb_build_object('version',2,
      'citas_por_lead',(v_config->'configuracion'->>'citas_por_lead')::numeric,
      'entrevistas_porcentaje',(v_config->'configuracion'->>'entrevistas_porcentaje')::numeric,
      'depositos_porcentaje',(v_config->'configuracion'->>'depositos_porcentaje')::numeric,
      'actividad_manuales',v_config->'configuracion'->>'actividad_manuales',
      'asignaciones',v_asignaciones,'control',v_config,
      'poblacion',v_poblacion,'conversiones',v_conversiones_gestion,'capital',v_capital));
end;
$function$;

-- Conserva la puerta Gerencia y sus ACL; actualiza sólo su declaración existente.
update private.analitica_leads_citas_exenciones e
set huella=md5(regexp_replace(regexp_replace(lower(p.prosrc),
  '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
  razon='Detalle operativo Gerencia: citas desde citas_episodios y cierres desde conversion_cierres. Base mensual desde ledger inmutable lead_asignaciones, personas distintas por analista; identidad y autor de alta manual desde leads. Incluye hechos mensuales de registro de citas, atribución de origen y de cierre, y capital inicial real desde capital_episodios. No usa importes estimados como depósitos.'
from pg_proc p where p.oid='private.citas_gerencia_consulta(date,date)'::regprocedure
  and e.objeto='private.citas_gerencia_consulta(date,date)';
update private.analitica_lc_sello set sello=private.huella_exenciones_analitica_lc(),sellado_en=now() where id;
select private.assert_analitica_leads_citas();
commit;

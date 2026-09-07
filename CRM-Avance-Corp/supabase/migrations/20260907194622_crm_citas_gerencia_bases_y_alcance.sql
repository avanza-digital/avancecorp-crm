-- Citas de Gerencia: bases ya calculadas y explicación de cierres previos.
-- Sólo amplía la respuesta del agregador existente. No cambia fórmulas,
-- atribución temporal, fachada, ACL, datos de negocio ni núcleos.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
create temporary table citas_guardas_20260907 on commit drop as
select p.oid, n.nspname, p.proname, md5(pg_get_functiondef(p.oid)) as huella,
       p.proacl, p.proowner, p.prosecdef, p.proconfig
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where (n.nspname='private' and p.proname in (
  'metricas_reuniones_implementacion','citas_episodios','conversion_episodios',
  'capital_episodios','filtrar_desglose_sujetos_crm'))
  or (n.nspname='crm' and p.proname='metricas_reuniones_fn');
do $guardas$
begin
  if md5(pg_get_functiondef('private.metricas_reuniones_implementacion(date,date)'::regprocedure))
      <> '6e8935eae3cf1a4c049a93cb20e1f3bd' then
    raise exception 'El agregador de Citas cambió; revisar antes de aplicar';
  end if;
  if (select count(*) from citas_guardas_20260907) <> 6 then
    raise exception 'Faltan dependencias protegidas de Citas';
  end if;
end;
$guardas$;

CREATE OR REPLACE FUNCTION private.metricas_reuniones_implementacion(p_desde date, p_hasta date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_ahora timestamptz := now();
  v_payload jsonb;
  v_autorizado boolean;
begin
  select exists (
    select 1 from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.perfil_id = v_uid and e.activo and p.activo and e.rol_crm = 'gerencia'
  ) or private.es_lector_global() into v_autorizado;
  if v_uid is null or not coalesce(v_autorizado, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_desde is null or p_hasta is null or p_desde > p_hasta
     or p_hasta > v_hoy or p_hasta - p_desde > 365 then
    raise exception 'Periodo invalido' using errcode = '22023';
  end if;
  v_ini := p_desde::timestamp at time zone 'America/Lima';
  v_fin := (p_hasta + 1)::timestamp at time zone 'America/Lima';

  with cierres_del_nucleo as materialized (
    -- F2.5: los cierres que el NUCLEO reconoce (sin anulados), de la
    -- tabla-base. La ventana llega hasta `ahora` porque una reunion del rango
    -- puede acabar en cierre despues; ese cierre sigue siendo suyo.
    select distinct e.lead_id, min(e.fecha_numerador) as cerrado_en
    from private.conversion_episodios(
      v_ini, greatest(v_fin, v_ahora), null::date, true, '{}'::uuid[],
      private.peso_referido_conversion(date_trunc('month', p_hasta)::date)
    ) e
    where e.tipo = 'cierre' and not e.anulado and e.lead_id is not null
    group by e.lead_id
  ),
  base as materialized (
    select t.*, ce.modalidad as modalidad,
      coalesce(l.origen, 'sin_origen') as origen,
      l.perfil_id as cliente_id, l.contrato_id, l.convertido_en,
      case when l.moneda = 'USD' then c.capital_usd_nucleo else c.capital_pen_nucleo end as capital,
      l.moneda, c.contrato_creado_en_nucleo as contrato_creado_en,
      coalesce(p.nombre_completo, 'Sin responsable') as responsable_nombre,
      e.rol_crm, e.supervisor_id,
      coalesce(ps.nombre_completo, 'Sin equipo') as supervisor_nombre,
      ce.debio_ocurrir as metrica_debio_ocurrir,
      ce.realizada as metrica_realizada,
      ce.no_show as metrica_no_show,
      ce.cancelada_asesor as metrica_cancelada_asesor,
      ce.cancelada_sistema as metrica_cancelada_sistema,
      ce.reprogramada as metrica_reprogramada,
      ce.pendiente_cierre as metrica_pendiente_cierre,
      ce.programada_futura as metrica_programada_futura
    from private.citas_episodios(v_ini, v_fin, v_ahora) ce
    join crm.tareas t on t.id = ce.tarea_id
    left join crm.leads l on l.id = t.lead_id
    left join lateral (
      -- F4.i: el capital VIVO del lead, del NUCLEO (misma regla que el panel
      -- de Conversiones): contratos del perfil + cooperativas del lead. El
      -- enlace leads.contrato_id jamas se rello (0/466) y por eso esta
      -- pantalla mostro capital 0 SIEMPRE.
      select sum(k.monto) filter (where k.moneda='PEN') as capital_pen_nucleo,
             sum(k.monto) filter (where k.moneda='USD') as capital_usd_nucleo,
             min(k.fecha) as contrato_creado_en_nucleo
      from private.capital_episodios('-infinity'::timestamptz,'infinity'::timestamptz,true,'{}'::uuid[]) k
      where k.medida = 'stock'
        and ((k.tipo like 'contrato_%' and k.cliente_id = l.perfil_id)
          or (k.tipo = 'cooperativa' and k.lead_id = l.id))
    ) c on true
    left join public.perfiles p on p.id = t.vendedor_id
    left join crm.equipo e on e.perfil_id = t.vendedor_id
    left join public.perfiles ps on ps.id = e.supervisor_id
  ),
  ultima_realizada as materialized (
    select distinct on (lead_id)
      lead_id, modalidad, origen, vendedor_id, responsable_nombre,
      supervisor_id, supervisor_nombre, cliente_id, contrato_id, convertido_en,
      capital, moneda, contrato_creado_en, vence_en,
      -- ANTES: `cliente_id is not null and convertido_en >= vence_en` (la
      -- ficha del lead) y la columna de contrato enlazado, que nadie rellena
      -- — por eso «terminan en contrato» valia 0 SIEMPRE.
      -- AHORA: el cierre del LEDGER, sin anulados, ocurrido despues de la
      -- reunion. Es la misma verdad que HOY, Ranking, Conversiones y
      -- Distribucion. Las dos banderas miden ya lo mismo: en este CRM el
      -- cierre ES el hecho; el enlace al contrato no existe (se rotula en F3).
      exists (select 1 from cierres_del_nucleo cn
               where cn.lead_id = base.lead_id and cn.cerrado_en >= base.vence_en)
        as metrica_conversion_cliente,
      exists (select 1 from cierres_del_nucleo cn
               where cn.lead_id = base.lead_id and cn.cerrado_en >= base.vence_en)
        as metrica_conversion_contrato,
      -- Explica los cierres que existen en el horizonte consultado pero
      -- preceden la hora prevista de la última cita. No cambia la atribución.
      exists (select 1 from cierres_del_nucleo cn
               where cn.lead_id = base.lead_id and cn.cerrado_en < base.vence_en)
        as metrica_cierre_previo
    from base
    where metrica_realizada and lead_id is not null
    order by lead_id, vence_en desc, id desc
  ),
  resumen as (
    select count(*)::int as pactadas,
      count(*) filter (where metrica_debio_ocurrir)::int as debieron_ocurrir,
      count(*) filter (where metrica_realizada)::int as realizadas,
      count(*) filter (where metrica_no_show)::int as no_show,
      count(*) filter (where metrica_cancelada_asesor)::int as canceladas,
      count(*) filter (where metrica_cancelada_sistema)::int as canceladas_sistema,
      count(*) filter (where metrica_reprogramada)::int as reprogramadas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_sistema
      )::int as canceladas_sistema_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_reprogramada
      )::int as reprogramadas_vencidas,
      count(*) filter (where metrica_pendiente_cierre)::int as pendientes_cierre,
      count(*) filter (where metrica_programada_futura)::int as programadas_futuras
    from base
  ),
  modalidad_base as (
    select modalidad,
      count(*)::int as pactadas,
      count(*) filter (where metrica_debio_ocurrir)::int as debieron_ocurrir,
      count(*) filter (where metrica_realizada)::int as realizadas,
      count(*) filter (where metrica_no_show)::int as no_show,
      count(*) filter (where metrica_cancelada_asesor)::int as canceladas,
      count(*) filter (where metrica_reprogramada)::int as reprogramadas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_sistema
      )::int as canceladas_sistema_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_reprogramada
      )::int as reprogramadas_vencidas,
      count(*) filter (where metrica_pendiente_cierre)::int as pendientes_cierre
    from base group by modalidad
  ),
  modalidad_conversion as (
    select modalidad,
      count(*)::int as leads_reunidos,
      count(*) filter (where metrica_conversion_cliente)::int as clientes,
      count(*) filter (where metrica_conversion_contrato)::int as contratos,
      count(*) filter (where metrica_cierre_previo)::int as leads_con_cierre_previo,
      coalesce(sum(capital) filter (where metrica_conversion_contrato and moneda = 'PEN'),0) as capital_pen,
      coalesce(sum(capital) filter (where metrica_conversion_contrato and moneda = 'USD'),0) as capital_usd
    from ultima_realizada group by modalidad
  ),
  origen_base as (
    select origen,
      count(*)::int as pactadas,
      count(*) filter (where metrica_debio_ocurrir)::int as debieron_ocurrir,
      count(*) filter (where metrica_realizada)::int as realizadas,
      count(*) filter (where metrica_no_show)::int as no_show,
      count(*) filter (where metrica_cancelada_asesor)::int as canceladas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_sistema
      )::int as canceladas_sistema_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_reprogramada
      )::int as reprogramadas_vencidas
    from base group by origen
  ),
  origen_conversion as (
    select origen,
      count(*)::int as leads_reunidos,
      count(*) filter (where metrica_conversion_cliente)::int as clientes,
      count(*) filter (where metrica_conversion_contrato)::int as contratos,
      count(*) filter (where metrica_cierre_previo)::int as leads_con_cierre_previo
    from ultima_realizada group by origen
  ),
  responsables as (
    select vendedor_id, responsable_nombre, rol_crm, supervisor_id, supervisor_nombre,
      count(*)::int as pactadas,
      count(*) filter (where metrica_debio_ocurrir)::int as debieron_ocurrir,
      count(*) filter (where metrica_realizada)::int as realizadas,
      count(*) filter (where metrica_no_show)::int as no_show,
      count(*) filter (where metrica_cancelada_asesor)::int as canceladas,
      count(*) filter (where metrica_reprogramada)::int as reprogramadas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_sistema
      )::int as canceladas_sistema_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_asesor
          and cancelada_por_id is distinct from vendedor_id
      )::int as canceladas_ajenas_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_reprogramada
      )::int as reprogramadas_vencidas,
      count(*) filter (where metrica_programada_futura)::int as programadas_futuras,
      count(*) filter (where metrica_pendiente_cierre)::int as pendientes_cierre
    from base
    group by vendedor_id, responsable_nombre, rol_crm, supervisor_id, supervisor_nombre
  ),
  resultados as (
    select coalesce(resultado_reunion, 'sin_clasificar') as resultado,
      count(*)::int as cantidad
    from base where metrica_realizada
    group by coalesce(resultado_reunion, 'sin_clasificar')
  ),
  conversion_global as (
    select count(*)::int as leads_reunidos,
      count(*) filter (where metrica_conversion_cliente)::int as clientes,
      count(*) filter (where metrica_conversion_contrato)::int as contratos,
      count(*) filter (where metrica_cierre_previo)::int as leads_con_cierre_previo,
      coalesce(sum(capital) filter (where metrica_conversion_contrato and moneda = 'PEN'),0) as capital_pen,
      coalesce(sum(capital) filter (where metrica_conversion_contrato and moneda = 'USD'),0) as capital_usd
    from ultima_realizada
  )
  select jsonb_build_object(
    'version', 1, 'generado_en', now(),
    'periodo', jsonb_build_object(
      'desde', p_desde, 'hasta', p_hasta,
      'dias', (p_hasta-p_desde)+1, 'zona', 'America/Lima'
    ),
    'resumen', jsonb_build_object(
      'pactadas', r.pactadas, 'debieron_ocurrir', r.debieron_ocurrir,
      'divisor_realizacion', r.debieron_ocurrir-r.canceladas_sistema_vencidas-r.reprogramadas_vencidas,
      'divisor_asistencia', r.realizadas+r.no_show,
      'canceladas_sistema_vencidas', r.canceladas_sistema_vencidas,
      'reprogramadas_vencidas', r.reprogramadas_vencidas,
      'realizadas', r.realizadas, 'no_concretadas', r.no_show+r.canceladas,
      'no_show', r.no_show, 'canceladas', r.canceladas,
      'canceladas_sistema', r.canceladas_sistema,
      'reprogramadas', r.reprogramadas,
      'pendientes_cierre', r.pendientes_cierre,
      'programadas_futuras', r.programadas_futuras,
      'pct_realizacion', case
        when r.debieron_ocurrir-r.canceladas_sistema_vencidas-r.reprogramadas_vencidas > 0
        then round(
          100.0*r.realizadas
          /(r.debieron_ocurrir-r.canceladas_sistema_vencidas-r.reprogramadas_vencidas),
          1
        )
      end,
      'pct_asistencia', case when r.realizadas+r.no_show > 0
        then round(100.0*r.realizadas/(r.realizadas+r.no_show),1) end
    ),
    'conversion', jsonb_build_object(
      'leads_reunidos', cg.leads_reunidos, 'clientes', cg.clientes,
      'leads_con_cierre_previo', cg.leads_con_cierre_previo,
      'contratos', cg.contratos,
      'conversion_cliente_pct', case when cg.leads_reunidos > 0 then round(100.0*cg.clientes/cg.leads_reunidos,1) end,
      'conversion_contrato_pct', case when cg.leads_reunidos > 0 then round(100.0*cg.contratos/cg.leads_reunidos,1) end,
      'capital_pen', cg.capital_pen, 'capital_usd', cg.capital_usd
    ),
    'modalidades', coalesce((select jsonb_agg(jsonb_build_object(
      'modalidad', mb.modalidad, 'pactadas', mb.pactadas,
      'debieron_ocurrir', mb.debieron_ocurrir, 'realizadas', mb.realizadas,
      'no_concretadas', mb.no_show+mb.canceladas, 'no_show', mb.no_show,
      'canceladas', mb.canceladas, 'reprogramadas', mb.reprogramadas,
      'divisor_realizacion',
        mb.debieron_ocurrir-mb.canceladas_sistema_vencidas-mb.reprogramadas_vencidas,
      'canceladas_sistema_vencidas', mb.canceladas_sistema_vencidas,
      'reprogramadas_vencidas', mb.reprogramadas_vencidas,
      'pendientes_cierre', mb.pendientes_cierre,
      'pct_realizacion', case
        when mb.debieron_ocurrir-mb.canceladas_sistema_vencidas-mb.reprogramadas_vencidas > 0
        then round(
          100.0*mb.realizadas
          /(mb.debieron_ocurrir-mb.canceladas_sistema_vencidas-mb.reprogramadas_vencidas),
          1
        )
      end,
      'pct_asistencia', case when mb.realizadas+mb.no_show > 0 then round(100.0*mb.realizadas/(mb.realizadas+mb.no_show),1) end,
      'leads_reunidos', coalesce(mc.leads_reunidos,0),
      'leads_con_cierre_previo', coalesce(mc.leads_con_cierre_previo,0),
      'clientes', coalesce(mc.clientes,0), 'contratos', coalesce(mc.contratos,0),
      'conversion_cliente_pct', case when coalesce(mc.leads_reunidos,0)>0 then round(100.0*mc.clientes/mc.leads_reunidos,1) end,
      'conversion_contrato_pct', case when coalesce(mc.leads_reunidos,0)>0 then round(100.0*mc.contratos/mc.leads_reunidos,1) end,
      'capital_pen', coalesce(mc.capital_pen,0), 'capital_usd', coalesce(mc.capital_usd,0)
    ) order by case mb.modalidad when 'presencial' then 1 when 'virtual' then 2 else 3 end)
      from modalidad_base mb left join modalidad_conversion mc using (modalidad)), '[]'::jsonb),
    'origenes', coalesce((select jsonb_agg(jsonb_build_object(
      'origen', ob.origen, 'pactadas', ob.pactadas, 'realizadas', ob.realizadas,
      'no_show', ob.no_show, 'canceladas', ob.canceladas,
      'pct_realizacion', case
        when ob.debieron_ocurrir-ob.canceladas_sistema_vencidas-ob.reprogramadas_vencidas > 0
        then round(
          100.0*ob.realizadas
          /(ob.debieron_ocurrir-ob.canceladas_sistema_vencidas-ob.reprogramadas_vencidas),
          1
        )
      end,
      'leads_reunidos', coalesce(oc.leads_reunidos,0),
      'leads_con_cierre_previo', coalesce(oc.leads_con_cierre_previo,0),
      'clientes', coalesce(oc.clientes,0), 'contratos', coalesce(oc.contratos,0),
      'conversion_contrato_pct', case when coalesce(oc.leads_reunidos,0)>0 then round(100.0*oc.contratos/oc.leads_reunidos,1) end
    ) order by ob.realizadas desc, ob.pactadas desc, ob.origen)
      from origen_base ob left join origen_conversion oc using (origen)), '[]'::jsonb),
    'responsables', coalesce((select jsonb_agg(jsonb_build_object(
      'responsable_id', rr.vendedor_id, 'nombre', rr.responsable_nombre,
      'rol', rr.rol_crm, 'supervisor_id', rr.supervisor_id,
      'supervisor_nombre', rr.supervisor_nombre,
      'pactadas', rr.pactadas, 'realizadas', rr.realizadas,
      'debieron_ocurrir', rr.debieron_ocurrir,
      'divisor_realizacion', rr.debieron_ocurrir-rr.canceladas_sistema_vencidas
        -rr.canceladas_ajenas_vencidas-rr.reprogramadas_vencidas,
      'canceladas_sistema_vencidas', rr.canceladas_sistema_vencidas,
      'canceladas_ajenas_vencidas', rr.canceladas_ajenas_vencidas,
      'reprogramadas_vencidas', rr.reprogramadas_vencidas,
      'programadas_futuras', rr.programadas_futuras,
      'no_show', rr.no_show, 'canceladas', rr.canceladas,
      'reprogramadas', rr.reprogramadas,
      'pendientes_cierre', rr.pendientes_cierre,
      'pct_realizacion', case
        when rr.debieron_ocurrir-rr.canceladas_sistema_vencidas
          -rr.canceladas_ajenas_vencidas-rr.reprogramadas_vencidas > 0
        then round(
          100.0*rr.realizadas
          /(rr.debieron_ocurrir-rr.canceladas_sistema_vencidas
            -rr.canceladas_ajenas_vencidas-rr.reprogramadas_vencidas),
          1
        )
      end
    ) order by rr.realizadas desc, rr.pactadas desc, rr.responsable_nombre) from responsables rr), '[]'::jsonb),
    'resultados', coalesce((select jsonb_agg(jsonb_build_object(
      'resultado', resultado, 'cantidad', cantidad
    ) order by cantidad desc, resultado) from resultados), '[]'::jsonb)
  ) into v_payload
  from resumen r cross join conversion_global cg;

  return v_payload;
end;
$function$;

do $guardas$
begin
  if exists (
    select 1 from citas_guardas_20260907 g left join pg_proc p on p.oid=g.oid
    where p.oid is null or p.proacl is distinct from g.proacl
       or p.proowner is distinct from g.proowner or p.prosecdef is distinct from g.prosecdef
       or p.proconfig is distinct from g.proconfig
       or (g.proname <> 'metricas_reuniones_implementacion'
           and md5(pg_get_functiondef(p.oid)) is distinct from g.huella)
  ) then
    raise exception 'Se alteró una dependencia, núcleo o permiso protegido';
  end if;
  if md5(pg_get_functiondef('private.metricas_reuniones_implementacion(date,date)'::regprocedure))
      <> 'cec7ee9ec1c31ddd8fa17f1d42e88fc1' then
    raise exception 'El cuerpo aplicado de Citas no coincide con el revisado';
  end if;
end;
$guardas$;
commit;

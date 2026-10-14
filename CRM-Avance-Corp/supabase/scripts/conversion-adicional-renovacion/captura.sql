-- Solo lectura. Usar la MISMA branch quieta antes y después de la migración.
-- No contiene contactos, documentos, cuentas bancarias ni credenciales.
with actor as materialized (
  select set_config('request.jwt.claim.sub',
    (select perfil_id::text from crm.equipo
     where rol_crm='gerencia' and activo order by perfil_id limit 1),true)
), meses as materialized (
  select d::date as mes
  from generate_series(date '2026-01-01',date '2026-10-01',interval '1 month') d
), lecturas as materialized (
  select m.mes,
    crm.conversion_mensual_fn(m.mes) as oficial,
    crm.conversion_divisor_coordinacion_fn(m.mes) as coordinacion,
    crm.metricas_conversiones_fn(m.mes,least((m.mes+interval '1 month - 1 day')::date,
      (statement_timestamp() at time zone 'America/Lima')::date)) as metricas,
    crm.metricas_conversiones_equipo_fn(m.mes,least((m.mes+interval '1 month - 1 day')::date,
      (statement_timestamp() at time zone 'America/Lima')::date)) as equipo,
    crm.cumplimiento_metas_fn(m.mes) as metas,
    (select coalesce(jsonb_agg(to_jsonb(e) order by e.tipo,e.analista_id,e.lead_id,e.operacion_id),'[]')
     from private.conversion_episodios(
       m.mes::timestamp at time zone 'America/Lima',
       (m.mes+interval '1 month')::timestamp at time zone 'America/Lima',
       m.mes,true,'{}',private.peso_referido_conversion(m.mes)) e) as episodios,
    (select coalesce(jsonb_agg(to_jsonb(c) order by c.analista_id),'[]')
     from private.conversion_mensual_por_vendedor(
       m.mes::timestamp at time zone 'America/Lima',
       (m.mes+interval '1 month')::timestamp at time zone 'America/Lima',
       true,'{}',private.peso_referido_conversion(m.mes)) c) as nucleo
  from actor cross join meses m
)
select jsonb_build_object(
  'capturado_en',statement_timestamp(),
  'meses',(select jsonb_agg(to_jsonb(l) order by l.mes) from lecturas l),
  'analistas',(select jsonb_agg(jsonb_build_object(
    'id',e.perfil_id,'nombre',p.nombre_completo,'activo',e.activo) order by e.perfil_id)
    from crm.equipo e join public.perfiles p on p.id=e.perfil_id where e.rol_crm='vendedor'),
  'operaciones_octubre',(select jsonb_agg(to_jsonb(o)||jsonb_build_object(
    'contrato',c.numero_contrato,'analista_efectivo',
    private.analista_efectivo_contrato(o.contrato_nuevo_id,o.vendedor_id)) order by o.id)
    from crm.operaciones_cartera o
    left join public.contratos c on c.id=o.contrato_nuevo_id
    where o.periodo=date '2026-10-01'),
  'huellas',jsonb_build_object(
    'pesos',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by vigente_desde)::text,'[]'))
      from crm.conversion_pesos x),
    'periodos_cerrados',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by periodo)::text,'[]'))
      from crm.periodos_cerrados x),
    'fotos',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by periodo,vendedor_id)::text,'[]'))
      from crm.cierre_mes_vendedor x),
    'operaciones',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by id)::text,'[]'))
      from crm.operaciones_cartera x),
    'contratos',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by id)::text,'[]'))
      from public.contratos x)
  )
) as captura;

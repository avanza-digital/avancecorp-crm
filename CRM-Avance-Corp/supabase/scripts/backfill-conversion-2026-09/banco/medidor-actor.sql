begin;
create temp table foto_tmp(rpc text primary key, ok boolean, resultado jsonb) on commit drop;
-- La lista de llamadas se arma como postgres (necesita leer ids); se EJECUTA como el actor.
do $lista$
declare v_id uuid; v_leads uuid[];
begin
  insert into foto_tmp(rpc) select unnest(array[
    'crm.metricas_capital_mes_fn(12)', 'crm.metricas_vendedores_fn()', 'crm.resumen_cartera_fn()',
    'crm.resumen_cartera_clientes_fn()', 'crm.metricas_multiempresa_fn(''2026-09-01'')',
    'crm.metricas_multiempresa_estado_fn()', 'crm.conversion_mensual_fn(''2026-09-01'')',
    'crm.metricas_conversiones_fn(''2026-09-01'',''2026-09-23'',null)',
    'crm.metricas_conversiones_equipo_fn(''2026-09-01'',''2026-09-23'')',
    'crm.altas_nuevas_por_analista_fn(12)', 'crm.citas_gerencia_consulta_fn(''2026-09-01'',''2026-09-30'')',
    'crm.facturacion_diaria_fn(''2026-09-23'')', 'crm.cumplimiento_metas_fn(''2026-09-01'')',
    'crm.cierre_mes_estado_fn()', 'crm.ingresos_reparto_mes_fn(''2026-09-01'')',
    'crm.cartera_inversionistas_estado_fn()', 'crm.cartera_inversionistas_filtrada_fn()',
    'crm.metricas_pagos_mes_fn(12)', 'crm.metricas_vencimientos_fn(400)',
    'crm.postventa_estado_fn()', 'crm.postventa_vencimientos_fn()',
    'crm.metricas_distribucion_leads_v3_fn(''2026-09-01'',''2026-09-23'')',
    'crm.leads_recibidos_analista_fn(''2026-09-01'',''2026-09-23'')',
    'crm.gestion_diaria_analista_fn(''2026-09-23'',''b0000000-0000-4000-8000-000000000002'')',
    'crm.cartera_pagina_fn()', 'crm.tareas_pendientes_fn()', 'crm.cola_accion_v2_fn()',
    'crm.avisos_sla_resumen_v2_fn()',
    'crm.registro_actividad_fn(''2026-09-01'',''2026-09-23'')']);
  for v_id in select i.id from crm.inversionistas i where i.perfil_id::text like 'c0000000%' order by i.perfil_id loop
    insert into foto_tmp(rpc) values (format('crm.inversionista_ficha_fn(%L)', v_id)), (format('crm.postventa_ficha_fn(%L)', v_id));
  end loop;
  for v_id in select p.id from public.perfiles p where p.id::text like 'c0000000%' order by p.id loop
    insert into foto_tmp(rpc) values (format('crm.cliente_ficha_fn(%L)', v_id)), (format('crm.cliente_detalle_fn(%L)', v_id)),
      (format('crm.postventa_perfil_fn(%L)', v_id));
  end loop;
  for v_id in select c.id from public.contratos c where c.numero_contrato like 'BANCO-%' order by c.numero_contrato loop
    insert into foto_tmp(rpc) values (format('crm.atribucion_contrato_fn(%L)', v_id));
  end loop;
  -- El lead de backfill (si existe): lo que abre «Ver inversión y bienvenida» y su historial.
  for v_id in select l.id from crm.leads l where l.nota like 'Backfill 2026-09%' order by l.creado_en loop
    insert into foto_tmp(rpc) values (format('crm.contexto_conversion_inversion_fn(%L)', v_id)),
      (format('crm.actividades_de_lead_fn(%L)', v_id));
  end loop;
  select array_agg(id order by id) into v_leads from crm.leads where nombre_completo like 'BANCO LEAD FONDO%';
  insert into foto_tmp(rpc) values (format('crm.cierres_estado_fn(%L::uuid[])', v_leads)),
    (format('crm.estado_sla_leads_v2_fn(%L::uuid[])', v_leads));
  -- Sin EXECUTE para authenticated NO se llama: en la imagen local eso TUMBA el Postgres
  -- (segfault, memoria «postgres-cae-por-permiso-de-funcion»). Queda registrada como omitida.
  update foto_tmp set ok = false,
    resultado = jsonb_build_object('omitida', 'authenticated no tiene EXECUTE')
  where not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname || '.' || p.proname = split_part(rpc, '(', 1)
                      and has_function_privilege('authenticated', p.oid, 'EXECUTE'));
end $lista$;
grant all on foto_tmp to authenticated;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', :'actor_id', 'role', 'authenticated')::text, true) \gset ignorar_
do $m$
declare r record; v_res jsonb;
begin
  for r in select rpc from foto_tmp where ok is null order by rpc loop
    begin
      execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from %s t', r.rpc) into v_res;
      update foto_tmp set ok = true, resultado = v_res where rpc = r.rpc;
    exception when others then
      update foto_tmp set ok = false, resultado = jsonb_build_object('sqlstate', sqlstate, 'mensaje', sqlerrm) where rpc = r.rpc;
    end;
  end loop;
end $m$;
reset role;
insert into ensayo.foto select :'etapa', :'actor', rpc, ok, resultado from foto_tmp;
commit;

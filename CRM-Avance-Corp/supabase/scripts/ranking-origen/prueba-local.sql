-- Ejecutar DESPUÉS de la migración, dentro de la MISMA transacción local.
-- Compara una fila por vendedor/categoría/moneda y rechaza cualquier capital
-- inventado o contrato duplicado. El caller termina con ROLLBACK.
-- Dos leads del mismo cliente, ligados al mismo contrato y con canales
-- distintos: el capital se atribuye una vez y se rotula sin_origen.
do $ambiguo$
declare
  v_cantidad integer;
  v_origen text;
  v_capital numeric;
  v_meta_id uuid;
  v_meta_vendedor_id uuid;
  v_cierre_id uuid;
  v_leads integer;
  v_cierres integer;
  v_pct numeric;
  v_rpc jsonb;
  v_denegado boolean := false;
begin
  update crm.leads
  set contrato_id = 'e0000000-0000-4000-8000-00000000000e'::uuid
  where id = '79119955-54e8-441b-8298-dcbc9ed20291'::uuid;
  update crm.leads
  set perfil_id = 'c0000000-0000-4000-8000-000000000004'::uuid,
    contrato_id = 'e0000000-0000-4000-8000-00000000000e'::uuid
  where id = '53110c32-d029-4cb1-9207-17401443a477'::uuid;
  select mp.id into v_meta_id from crm.meta_periodos mp
  where mp.periodo = date '2026-09-01' order by mp.revision desc limit 1;
  insert into crm.metas_vendedor (
    meta_periodo_id, vendedor_id, supervisor_id, conversion_objetivo
  ) values (
    v_meta_id,
    'b0000000-0000-4000-8000-000000000002'::uuid,
    'b0000000-0000-4000-8000-000000000001'::uuid, 10
  ) returning id into v_meta_vendedor_id;
  insert into crm.metas_vendedor_detalle (
    meta_vendedor_id, categoria, moneda, capital_objetivo, contratos_objetivo
  ) select v_meta_vendedor_id, c.categoria, m.moneda, 0, 0
  from (values ('nuevo'), ('renovacion'), ('upgrade')) c(categoria)
  cross join (values ('PEN'), ('USD')) m(moneda);
  select count(*)::integer, min(f.origen), sum(f.capital)
  into v_cantidad, v_origen, v_capital
  from private.ranking_capital_origen_filas(
    timestamp '2026-09-01' at time zone 'America/Lima',
    timestamp '2026-10-01' at time zone 'America/Lima',
    v_meta_id
  ) f where f.operacion_id = 'e0000000-0000-4000-8000-00000000000e'::uuid;
  if v_cantidad <> 1 or v_origen <> 'sin_origen' or v_capital <> 20000 then
    raise exception 'Contrato con varios leads: esperado una fila sin origen por S/ 20.000';
  end if;
  raise notice 'Ranking origen: varios leads y canal ambiguo PASS';

  insert into crm.cierres_externos (
    lead_id, cooperativa, monto, moneda, documento_tipo, documento,
    nombre_completo, numero_transaccion, vendedor_id, creado_por, creado_en
  ) values (
    '79119955-54e8-441b-8298-dcbc9ed20291'::uuid,
    'qorilazo', 1000, 'PEN', 'DNI', '12345678',
    'Prueba origen', 'ORIGEN-TEST-20260925',
    'b0000000-0000-4000-8000-000000000002'::uuid,
    'b0000000-0000-4000-8000-000000000003'::uuid,
    timestamptz '2026-09-15 12:00:00-05'
  ) returning id into v_cierre_id;
  select count(*)::integer, min(f.origen), sum(f.capital)
  into v_cantidad, v_origen, v_capital
  from private.ranking_capital_origen_filas(
    timestamp '2026-09-01' at time zone 'America/Lima',
    timestamp '2026-10-01' at time zone 'America/Lima',
    v_meta_id
  ) f where f.operacion_id = v_cierre_id;
  if v_cantidad <> 1 or v_origen <> 'landing' or v_capital <> 1000 then
    raise exception 'Cierre cooperativo no recibió el canal y monto de su lead';
  end if;
  raise notice 'Ranking origen: cierre cooperativo PASS';

  select c.leads, c.cierres, c.conversion_pct
  into v_leads, v_cierres, v_pct
  from private.ranking_conversion_origen_mes(
    timestamp '2026-09-01' at time zone 'America/Lima',
    timestamp '2026-10-01' at time zone 'America/Lima',
    date '2026-09-01', 0.15
  ) c where c.vendedor_id = 'b0000000-0000-4000-8000-000000000002'::uuid
    and c.origen = 'referido';
  if v_leads <> 1 or v_cierres <> 1 or v_pct <> 15 then
    raise exception 'Referido: esperaba un cierre ponderado sobre un lead (15%%)';
  end if;
  select c.conversion_pct into v_pct
  from private.ranking_conversion_origen_mes(
    timestamp '2026-09-01' at time zone 'America/Lima',
    timestamp '2026-10-01' at time zone 'America/Lima',
    date '2026-09-01', null
  ) c where c.vendedor_id = 'b0000000-0000-4000-8000-000000000002'::uuid
    and c.origen = 'referido';
  if v_pct is not null then
    raise exception 'Referido sin peso no debe afirmar una tasa';
  end if;
  raise notice 'Ranking origen: conversión Referido y peso ausente PASS';

  perform set_config('request.jwt.claim.sub',
    'b0000000-0000-4000-8000-000000000003', true);
  select crm.ranking_origen_vendedor_fn(
    date '2026-09-01', 'b0000000-0000-4000-8000-000000000002'::uuid
  ) into v_rpc;
  if (v_rpc->>'disponible')::boolean is not true then
    raise exception 'Gerencia no pudo leer al vendedor de la foto mensual';
  end if;
  perform set_config('request.jwt.claim.sub',
    'b0000000-0000-4000-8000-000000000001', true);
  select crm.ranking_origen_vendedor_fn(
    date '2026-09-01', 'b0000000-0000-4000-8000-000000000002'::uuid
  ) into v_rpc;
  if (v_rpc->>'disponible')::boolean is not true then
    raise exception 'El supervisor no pudo leer a su analista';
  end if;
  perform set_config('request.jwt.claim.sub',
    'b0000000-0000-4000-8000-000000000002', true);
  begin
    perform crm.ranking_origen_vendedor_fn(
      date '2026-09-01', 'b0000000-0000-4000-8000-000000000001'::uuid
    );
  exception when insufficient_privilege then
    v_denegado := true;
  end;
  if not v_denegado then
    raise exception 'Vendedor pudo consultar otra identidad';
  end if;
  perform set_config('request.jwt.claim.sub', '', true);
  raise notice 'Ranking origen: ámbito Gerencia/Supervisión y denegación PASS';

end;
$ambiguo$;

do $prueba$
declare
  v_mes date;
  v_id uuid;
  v_discrepancias integer;
  v_filas integer;
  v_json jsonb;
  v_vendor uuid;
  v_update_rechazado boolean := false;
begin
  for v_mes, v_id in
    select distinct on (mp.periodo) mp.periodo, mp.id
    from crm.meta_periodos mp
    where mp.periodo >= date '2026-07-01'
    order by mp.periodo, mp.revision desc
  loop
    with original as (
      select p.* from private.produccion_mes_por_vendedor(
        v_mes::timestamp at time zone 'America/Lima',
        (v_mes + interval '1 month')::timestamp at time zone 'America/Lima',
        v_id
      ) p
    ), detalle as (
      select d.vendedor_id, d.categoria, d.moneda,
        count(*)::integer as contratos_real, sum(d.capital) as capital_real
      from private.ranking_capital_origen_filas(
        v_mes::timestamp at time zone 'America/Lima',
        (v_mes + interval '1 month')::timestamp at time zone 'America/Lima',
        v_id
      ) d
      group by d.vendedor_id, d.categoria, d.moneda
    )
    select count(*)::integer,
      count(*) filter (where o.contratos_real is distinct from d.contratos_real
        or o.capital_real is distinct from d.capital_real)::integer
    into v_filas, v_discrepancias
    from original o full join detalle d
      using (vendedor_id, categoria, moneda);

    if v_discrepancias <> 0 then
      raise exception 'Paridad rota en %: % de % grupos', v_mes, v_discrepancias, v_filas;
    end if;

    if exists (
      select 1 from private.ranking_capital_origen_filas(
        v_mes::timestamp at time zone 'America/Lima',
        (v_mes + interval '1 month')::timestamp at time zone 'America/Lima',
        v_id
      ) d
      group by d.categoria, d.operacion_id
      having count(*) > 1
    ) then
      raise exception 'Un contrato o cierre externo aparece dos veces en %', v_mes;
    end if;

    for v_vendor in
      select distinct p.vendedor_id from private.produccion_mes_por_vendedor(
        v_mes::timestamp at time zone 'America/Lima',
        (v_mes + interval '1 month')::timestamp at time zone 'America/Lima',
        v_id
      ) p
    loop
      select private.ranking_origen_live(
        v_mes, v_vendor,
        coalesce(jsonb_agg(jsonb_build_object(
          'moneda', p.moneda, 'capital_real', p.capital_real
        )), '[]'::jsonb)
      ) into v_json
      from private.produccion_mes_por_vendedor(
        v_mes::timestamp at time zone 'America/Lima',
        (v_mes + interval '1 month')::timestamp at time zone 'America/Lima',
        v_id
      ) p where p.vendedor_id = v_vendor;

      if coalesce((v_json->>'disponible')::boolean, false) is not true then
        raise exception 'Desglose no concilia en % para %', v_mes, v_vendor;
      end if;

      -- Un ajuste neto tiene una fila negativa y conserva el bruto canónico.
      select private.ranking_origen_live(v_mes, v_vendor, jsonb_agg(
        jsonb_build_object(
          'moneda', p.moneda,
          'capital_real', p.capital_real - case when p.primera = 1 then 1 else 0 end,
          'capital_ajuste', case when p.primera = 1 then 1 else 0 end
        )
      )) into v_json
      from (
        select p.*, row_number() over (order by p.categoria, p.moneda) as primera
        from private.produccion_mes_por_vendedor(
          v_mes::timestamp at time zone 'America/Lima',
          (v_mes + interval '1 month')::timestamp at time zone 'America/Lima',
          v_id
        ) p where p.vendedor_id = v_vendor
      ) p;
      if coalesce((v_json->>'disponible')::boolean, false) is not true
        or not exists (
          select 1 from jsonb_array_elements(v_json->'filas') f(valor)
          where f.valor->>'origen' = 'ajuste'
            and ((f.valor->>'capital_pen')::numeric = -1
              or (f.valor->>'capital_usd')::numeric = -1)
        ) then
        raise exception 'Ajuste de cierre incorrecto en % para %', v_mes, v_vendor;
      end if;

      -- Un desajuste no se publica como si el origen fuera confiable.
      select private.ranking_origen_live(v_mes, v_vendor, jsonb_agg(
        jsonb_build_object('moneda', p.moneda, 'capital_real', p.capital_real + 1)
      )) into v_json
      from private.produccion_mes_por_vendedor(
        v_mes::timestamp at time zone 'America/Lima',
        (v_mes + interval '1 month')::timestamp at time zone 'America/Lima',
        v_id
      ) p where p.vendedor_id = v_vendor;
      if (v_json->>'disponible')::boolean is not false then
        raise exception 'Un desglose descuadrado fue publicado en % para %', v_mes, v_vendor;
      end if;
    end loop;

    raise notice 'Ranking origen: % · % grupos · paridad PASS', v_mes, v_filas;
  end loop;

  if has_function_privilege('anon', 'crm.ranking_origen_vendedor_fn(date,uuid)', 'EXECUTE')
    or not has_function_privilege('authenticated', 'crm.ranking_origen_vendedor_fn(date,uuid)', 'EXECUTE')
    or has_function_privilege('authenticated', 'private.ranking_origen_live(date,uuid,jsonb)', 'EXECUTE') then
    raise exception 'ACL del detalle por origen incorrecta';
  end if;
  raise notice 'Ranking origen: ACL PASS';

  -- La foto se calcula dentro del INSERT de cierre y queda en la fila sellada.
  select distinct on (mp.periodo) mp.periodo, mp.id into v_mes, v_id
  from crm.meta_periodos mp
  where mp.periodo = date '2026-09-01'
  order by mp.periodo, mp.revision desc;
  select p.vendedor_id into v_vendor
  from private.produccion_mes_por_vendedor(
    v_mes::timestamp at time zone 'America/Lima',
    (v_mes + interval '1 month')::timestamp at time zone 'America/Lima',
    v_id
  ) p limit 1;
  if v_vendor is not null and not exists (
    select 1 from crm.periodos_cerrados where periodo = v_mes
  ) then
    insert into crm.periodos_cerrados (
      periodo, ponderacion_referido, meta_revision, cobertura
    ) values (v_mes, 0.15, 1, '{}'::jsonb);

    insert into crm.cierre_mes_vendedor (
      periodo, vendedor_id, nombre_completo, supervisor_id, supervisor_nombre,
      divisor, cierres_no_referidos, cierres_referidos, cierres_de_arrastre,
      numerador, estado, referidos_recibidos, referidos_dados_de_alta,
      conversion_objetivo, detalles
    )
    select v_mes, v_vendor, 'Prueba local', v_vendor, 'Prueba local',
      0, 0, 0, 0, 0, 'sin_actividad', 0, 0, 0,
      coalesce(jsonb_agg(jsonb_build_object(
        'moneda', p.moneda, 'capital_real', p.capital_real
      )), '[]'::jsonb)
    from private.produccion_mes_por_vendedor(
      v_mes::timestamp at time zone 'America/Lima',
      (v_mes + interval '1 month')::timestamp at time zone 'America/Lima',
      v_id
    ) p where p.vendedor_id = v_vendor;

    select s.origenes_ranking into v_json
    from crm.cierre_mes_vendedor s
    where s.periodo = v_mes and s.vendedor_id = v_vendor;
    if coalesce((v_json->>'disponible')::boolean, false) is not true then
      raise exception 'La foto de orígenes no se selló en el cierre';
    end if;
    raise notice 'Ranking origen: foto de cierre PASS';

    -- Un fallo del detalle no puede abortar el cierre del mes.
    insert into crm.cierre_mes_vendedor (
      periodo, vendedor_id, nombre_completo, supervisor_id, supervisor_nombre,
      divisor, cierres_no_referidos, cierres_referidos, cierres_de_arrastre,
      numerador, estado, referidos_recibidos, referidos_dados_de_alta,
      conversion_objetivo, detalles
    ) values (
      v_mes, 'b0000000-0000-4000-8000-000000000001'::uuid,
      'Prueba de fallo', 'b0000000-0000-4000-8000-000000000001'::uuid,
      'Prueba de fallo', 0, 0, 0, 0, 0, 'sin_actividad', 0, 0, 0,
      '[{"moneda":"PEN","capital_real":"inválido"}]'::jsonb
    );
    select s.origenes_ranking into v_json from crm.cierre_mes_vendedor s
    where s.periodo = v_mes
      and s.vendedor_id = 'b0000000-0000-4000-8000-000000000001'::uuid;
    if (v_json->>'disponible')::boolean is not false then
      raise exception 'Un fallo del detalle no quedó aislado del sello';
    end if;
    raise notice 'Ranking origen: fallo aislado del cierre PASS';

    begin
      update crm.cierre_mes_vendedor s set origenes_ranking = null
      where s.periodo = v_mes and s.vendedor_id = v_vendor;
    exception when sqlstate 'P0409' then
      v_update_rechazado := true;
    end;
    if not v_update_rechazado then
      raise exception 'La foto por origen admitió UPDATE';
    end if;
    raise notice 'Ranking origen: foto inmutable PASS';
  end if;
end;
$prueba$;

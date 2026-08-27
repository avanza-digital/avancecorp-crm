-- Oraculo de F2.4 (la ventana de 45 dias deja de ser una METRICA).
--
-- Prueba las DOS mitades de la decision D1, que es lo que hace delicada esta
-- migracion:
--   · la METRICA de conversion pasa al mes calendario del nucleo
--   · la VISTA de cartera SIGUE filtrando por 45 dias (regla del 08/08)
-- Si una de las dos se mueve sin la otra, algo esta mal.

set search_path = '';
set test.uid = '11111111-1111-4111-8111-111111111111';

insert into public.perfiles (id, nombre_completo) values
  ('11111111-1111-4111-8111-111111111111','Gerencia'),
  ('22222222-2222-4222-8222-222222222222','Vendedora Uno') on conflict do nothing;
insert into crm.equipo (perfil_id, rol_crm) values
  ('11111111-1111-4111-8111-111111111111','gerencia'),
  ('22222222-2222-4222-8222-222222222222','vendedor') on conflict do nothing;

-- L1: recibido y cerrado ESTE MES (cuenta en la metrica)
-- L2: recibido y cerrado este mes pero ANULADO (no cuenta)
-- L3: recibido este mes, abierto (solo divisor)
-- L4: convertido hace 100 dias → FUERA de la vista de 45 dias, y su cierre no
--     es de este mes: no cuenta en ninguna de las dos.
insert into crm.leads (id, etapa, moneda, monto_estimado, vendedor_id, creado_en, convertido_en, activo) values
  ('44444444-0000-4000-8000-000000000001','convertido','PEN',1000,'22222222-2222-4222-8222-222222222222', now() - interval '10 days', now() - interval '3 days', true),
  ('44444444-0000-4000-8000-000000000002','convertido','PEN',1000,'22222222-2222-4222-8222-222222222222', now() - interval '9 days',  now() - interval '2 days', true),
  ('44444444-0000-4000-8000-000000000003','contactado','PEN',1000,'22222222-2222-4222-8222-222222222222', now() - interval '8 days',  null, true),
  ('44444444-0000-4000-8000-000000000004','convertido','PEN',1000,'22222222-2222-4222-8222-222222222222', now() - interval '200 days', now() - interval '100 days', true);

insert into crm.lead_asignaciones (analista_id, lead_id, origen, asignado_en, resultado, resultado_en) values
  ('22222222-2222-4222-8222-222222222222','44444444-0000-4000-8000-000000000001','campania', now() - interval '10 days','convertido', now() - interval '3 days'),
  ('22222222-2222-4222-8222-222222222222','44444444-0000-4000-8000-000000000002','campania', now() - interval '9 days', 'convertido', now() - interval '2 days'),
  ('22222222-2222-4222-8222-222222222222','44444444-0000-4000-8000-000000000003','campania', now() - interval '8 days', null, null),
  ('22222222-2222-4222-8222-222222222222','44444444-0000-4000-8000-000000000004','campania', now() - interval '200 days','convertido', now() - interval '100 days');
insert into private.anulados_stub values ('44444444-0000-4000-8000-000000000002') on conflict do nothing;

do $$
declare v jsonb; f jsonb; e text := '';
begin
  v := crm.metricas_vendedores_fn();
  select value into f from jsonb_array_elements(v->'vendedores') value
   where value->>'vendedor_id' = '22222222-2222-4222-8222-222222222222';

  -- GUARDA ANTI-VACUIDAD (la trampa que ya mordio dos veces en esta fase)
  if f is null then
    raise exception 'ORACULO VACUO: la vendedora no aparece en `vendedores`';
  end if;
  if f->>'convertidos' is null or f->>'nucleo_divisor' is null then
    raise exception 'ORACULO VACUO: faltan las claves nuevas (%)', f;
  end if;

  -- METRICA: cierres del MES, sin anulados → L1 = 1. Divisor: los 3 recibidos
  -- de este mes (L4 es de hace 200 dias) = 3. numerador 1 → 33 %
  if (f->>'convertidos')::int <> 1 then
    e := e || format(' convertidos=%s(≠1: o cuenta el anulado, o sigue contando la cartera visible)',
                     f->>'convertidos'); end if;
  if (f->>'nucleo_divisor')::int <> 3 then
    e := e || format(' nucleo_divisor=%s(≠3)', f->>'nucleo_divisor'); end if;
  if (f->>'conversion_pct')::int <> 33 then
    e := e || format(' conversion_pct=%s(≠33)', f->>'conversion_pct'); end if;
  if (f->>'nucleo_conversion_pct')::numeric <> 33.33 then
    e := e || format(' nucleo_conversion_pct=%s(≠33.33)', f->>'nucleo_conversion_pct'); end if;
  if v->>'ventana_metrica' <> 'mes_calendario' then
    e := e || ' falta ventana_metrica=mes_calendario'; end if;

  -- LA VISTA NO SE TOCA: la ventana de 45 dias sigue declarada
  if (v->>'ventana_convertidos_dias')::int <> 45 then
    e := e || ' se perdio ventana_convertidos_dias=45 (la regla de la VISTA)'; end if;

  if e <> '' then raise exception 'ORACULO ROTO (equipo):%', e; end if;
  raise notice 'EQUIPO OK · metrica = mes (1 de 3, 33.33%%) · vista de 45 dias intacta';
end $$;

do $$
declare v jsonb; e text := '';
begin
  v := crm.resumen_cartera_fn();
  if v->'totales'->>'convertidos' is null then
    raise exception 'ORACULO VACUO: totales.convertidos ausente (%)', v->'totales';
  end if;
  -- el tile pasa a contar cierres del MES: L1 = 1 (L2 anulado, L4 de hace 100 d)
  if (v->'totales'->>'convertidos')::int <> 1 then
    e := e || format(' totales.convertidos=%s(≠1)', v->'totales'->>'convertidos'); end if;
  -- pero la VISTA sigue con su ventana: L4 (convertido hace 100 dias) NO se ve
  if (v->'totales'->>'vivos')::int <> 3 then
    e := e || format(' totales.vivos=%s(≠3: la vista de 45 dias cambio)',
                     v->'totales'->>'vivos'); end if;
  if e <> '' then raise exception 'ORACULO ROTO (cartera):%', e; end if;
  raise notice 'CARTERA OK · tile = cierres del mes (1) · vista sigue a 45 dias (3 vivos)';
end $$;

do $$
declare v jsonb; e text := ''; v_total int;
begin
  v := crm.series_comerciales_fn(6);

  -- GUARDA ANTI-VACUIDAD: la serie usa ARRAYS PARALELOS (`meses`, `nuevos`,
  -- `cierres`), no objetos por mes. Si la forma cambiara, esto falla en vez de
  -- comparar contra NULL y pasar sin comprobar nada.
  if v->'cierres' is null or jsonb_typeof(v->'cierres') <> 'array' then
    raise exception 'ORACULO VACUO: `cierres` no es un array (%)',
      (select string_agg(k, ',') from jsonb_object_keys(v) k);
  end if;
  if jsonb_array_length(v->'meses') <> 6 then
    raise exception 'ORACULO VACUO: la serie no trae 6 meses';
  end if;

  -- Con la columna muerta la serie de cierres era 0 SIEMPRE. Ahora hay 2
  -- cierres reales: L4 (hace 100 dias) y L1 (este mes). L2 esta ANULADO y no
  -- cuenta — es la misma regla que el resto del CRM.
  select coalesce(sum(x::int), 0) into v_total
    from jsonb_array_elements_text(v->'cierres') x;
  if v_total <> 2 then
    e := e || format(' cierres en la serie=%s(≠2: o volvio la columna muerta, o cuenta el anulado)', v_total);
  end if;

  if e <> '' then raise exception 'ORACULO ROTO (series):%', e; end if;
  raise notice 'SERIES OK · 2 cierres reales donde antes habia 0 estructural';
end $$;

select 'TEST-F2-CARTERA: TODO VERDE' as resultado;

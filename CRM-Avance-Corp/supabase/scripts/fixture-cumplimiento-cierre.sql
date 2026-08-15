-- ---------------------------------------------------------------------------
-- Generador de fixtures: el payload REAL de `crm.cumplimiento_metas_fn`
-- ---------------------------------------------------------------------------
-- Escupe los DOS payloads que la pantalla de metas puede recibir —mes VIVO y
-- foto de un mes SELLADO— ejecutando la funcion de verdad. Alimentan a
-- `app/src/lib/cumplimiento-cierre-de-mes.test.ts`.
--
-- POR QUE EXISTE. El 2026-08-15 el servidor del cierre de mes se desplegó antes
-- que el front y empezó a mandar CUATRO claves nuevas. `CumplimientoMetasSchema`
-- es fail-closed, asi que rechazó el payload entero y la pantalla de metas se
-- apagó para los tres roles a la vez. Leyendo la migracion encontré 2 de las 4;
-- las otras dos (`capital_ajuste` y `contratos_ajuste`, que solo viajan en la
-- foto) las encontró ESTE script al ejecutar. Leer no es ejecutar.
--
-- USO:
--   dropdb --if-exists cierre_fixture && createdb cierre_fixture
--   psql -q -v ON_ERROR_STOP=1 -d cierre_fixture -f supabase/scripts/banco-local-cierre-mes.sql
--   # aplicar las 20260815* SIN sus bloques `do $preflight$` (anclan md5 de PROD)
--   psql -q -v ON_ERROR_STOP=1 -d cierre_fixture \
--     -v sellado=/tmp/pago-sellado.json -v abierto=/tmp/pago-abierto.json \
--     -f supabase/scripts/fixture-cumplimiento-cierre.sql
--
-- Termina en ROLLBACK: no deja nada sembrado.
--
-- ⚠️ Se impersona al DIRECTORIO (lector global). Con gerencia el calco local de
-- `private.vendedor_ids_visibles` devuelve vacio —solo modela vendedor y
-- supervisor— y el payload saldria con `vendedores: []`, que no prueba nada.
-- ---------------------------------------------------------------------------
\set ON_ERROR_STOP on
begin;
do $siembra$
declare
  v_g   uuid := '11111111-1111-4111-8111-111111111111';
  v_s   uuid := '22222222-2222-4222-8222-222222222222';
  v_v   uuid := '33333333-3333-4333-8333-333333333333';
  v_v2  uuid := '33333333-3333-4333-8333-333333333334';
  v_cli uuid := '44444444-4444-4444-8444-444444444444';
  v_mp_a uuid := '55555555-5555-4555-8555-555555555551';
  v_mp_b uuid := '55555555-5555-4555-8555-555555555552';
  v_mv_a uuid := '66666666-6666-4666-8666-666666666661';
  v_mv_b uuid := '66666666-6666-4666-8666-666666666662';
  v_mv_a2 uuid := '66666666-6666-4666-8666-666666666663';
  v_mv_b2 uuid := '66666666-6666-4666-8666-666666666664';
  v_la  uuid := '77777777-7777-4777-8777-777777777771';
  v_lb  uuid := '77777777-7777-4777-8777-777777777772';
  v_mA  date := (date_trunc('month', now() at time zone 'America/Lima') - interval '8 months')::date;
  v_mB  date := (date_trunc('month', now() at time zone 'America/Lima') - interval '7 months')::date;
  v_r jsonb;
begin
  insert into public.perfiles (id, nombre_completo, rol, activo) values
    (v_g,  'GERENTE DE PRUEBA',    'admin',     true),
    (v_s,  'SUPERVISOR DE PRUEBA', 'comercial', true),
    (v_v,  'VENDEDOR DE PRUEBA',   'comercial', true),
    (v_v2, 'VENDEDOR SIN MUESTRA', 'comercial', true),
    (v_cli,'CLIENTE DE PRUEBA',    'cliente',   true);

  insert into crm.conversion_pesos (vigente_desde, peso_referido, nota)
  values (v_mA, 0.150, 'fixture') on conflict do nothing;

  insert into crm.meta_periodos (id, periodo, revision, publicada_en) values
    (v_mp_a, v_mA, 1, now()), (v_mp_b, v_mB, 1, now());
  insert into crm.metas_vendedor (id, meta_periodo_id, vendedor_id, supervisor_id, conversion_objetivo) values
    (v_mv_a, v_mp_a, v_v,  v_s, 15), (v_mv_b, v_mp_b, v_v,  v_s, 15),
    (v_mv_a2,v_mp_a, v_v2, v_s, 40), (v_mv_b2,v_mp_b, v_v2, v_s, 40);
  -- Las SEIS dimensiones (categoria x moneda) para cada meta: el front exige
  -- exactamente 6 y produccion las tiene. Un fixture con una sola linea probaria
  -- otra cosa.
  insert into crm.metas_vendedor_detalle (meta_vendedor_id, categoria, moneda, capital_objetivo, contratos_objetivo)
  select mv, c, m,
         case when c='nuevo' and m='PEN' then base else 0 end,
         case when c='nuevo' and m='PEN' then cont else 0 end
  from (values (v_mv_a,100000,5),(v_mv_b,100000,5),(v_mv_a2,250000,8),(v_mv_b2,250000,8)) as t(mv,base,cont)
  cross join (values ('nuevo'),('renovacion'),('upgrade')) as cat(c)
  cross join (values ('PEN'),('USD')) as mon(m);

  -- Mes A: 4 recibidos, 2 cerrados (uno referido) → conversion por encima del objetivo.
  insert into crm.leads (id, nombre_completo, etapa, origen, vendedor_id, perfil_id, convertido_en) values
    (v_la, 'LEAD A', 'convertido', 'formulario', v_v, v_cli, (v_mA + interval '9 days 16 hours')),
    (v_lb, 'LEAD B', 'convertido', 'referido',   v_v, null,  (v_mA + interval '11 days 16 hours'));
  insert into crm.leads (id, nombre_completo, etapa, origen, vendedor_id, convertido_en) values
    ('77777777-7777-4777-8777-777777777773','LEAD C','descartado','formulario', v_v, null),
    ('77777777-7777-4777-8777-777777777774','LEAD D','descartado','formulario', v_v, null);
  insert into crm.lead_asignaciones (lead_id, analista_id, resultado, resultado_en, asignado_en, origen) values
    (v_la, v_v,'convertido',(v_mA + interval '9 days 16 hours'), (v_mA + interval '1 day 16 hours'),'formulario'),
    (v_lb, v_v,'convertido',(v_mA + interval '11 days 16 hours'),(v_mA + interval '2 days 16 hours'),'referido'),
    ('77777777-7777-4777-8777-777777777773', v_v,'descartado',(v_mA + interval '19 days 16 hours'),(v_mA + interval '3 days 16 hours'),'formulario'),
    ('77777777-7777-4777-8777-777777777774', v_v,'descartado',(v_mA + interval '20 days 16 hours'),(v_mA + interval '4 days 16 hours'),'formulario');
  insert into public.contratos (cliente_id, capital, moneda, categoria, estado, creado_por, creado_en)
  values (v_cli, 40000,'PEN','nuevo','activo', v_v, (v_mA + interval '9 days 17 hours'));

  -- Sellar SOLO el mes A. El B queda abierto: los dos payloads salen de la misma siembra.
  perform set_config('test.uid','',true);      -- sin uid = cierre automatico
  v_r := crm.cerrar_periodo(v_mA);
  if (v_r->>'ok')::boolean is not true then
    raise exception 'la siembra no pudo sellar el mes A: %', v_r;
  end if;
end $siembra$;

select set_config('test.uid','99999999-9999-4999-8999-999999999999',true);
\pset tuples_only on
\pset format unaligned
\o :sellado
select jsonb_pretty(crm.cumplimiento_metas_fn(
  (date_trunc('month', now() at time zone 'America/Lima') - interval '8 months')::date));
\o
\o :abierto
select jsonb_pretty(crm.cumplimiento_metas_fn(
  (date_trunc('month', now() at time zone 'America/Lima') - interval '7 months')::date));
\o
rollback;

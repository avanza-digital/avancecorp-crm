-- Oraculo de F2.2 (Ranking del equipo sobre la tabla-base).
--
-- Reutiliza el mundo sembrado por test-f2-conversiones.sql (mismo banco, misma
-- base desechable): V1 vendedor con 6 leads de julio/junio, un cierre anulado,
-- un referido, una operacion de cartera y un lead que madura en agosto.
-- Aqui se anaden un SEGUNDO vendedor y un SUPERVISOR para probar el AMBITO,
-- que es lo propio de esta pantalla.
--
-- Numeros calculados a mano. Julio 2026: mes ya pasado, para que la maduracion
-- no dependa de la hora ni del huso de quien ejecuta.

set search_path = '';
set test.uid = '11111111-1111-4111-8111-111111111111';

-- ── Un segundo vendedor (V2) y un supervisor que SOLO ve a V2 ──────────────
insert into public.perfiles (id) values
  ('55555555-5555-4555-8555-555555555555'),   -- V2
  ('66666666-6666-4666-8666-666666666666');   -- SUP
insert into crm.equipo (perfil_id, rol_crm) values
  ('55555555-5555-4555-8555-555555555555', 'vendedor'),
  ('66666666-6666-4666-8666-666666666666', 'supervisor');
insert into crm.equipo_supervision (supervisor_id, vendedor_id) values
  ('66666666-6666-4666-8666-666666666666', '55555555-5555-4555-8555-555555555555');

-- V2: 2 leads de julio, uno cierra en julio
insert into crm.leads (id, creado_en, origen, categoria_interes, etapa, vendedor_id, activo) values
  ('44444444-0000-4000-8000-000000000101', '2026-07-04 09:00-05', 'campania', 'renta', 'convertido', '55555555-5555-4555-8555-555555555555', true),
  ('44444444-0000-4000-8000-000000000102', '2026-07-08 09:00-05', 'campania', 'renta', 'contactado', '55555555-5555-4555-8555-555555555555', true);
insert into crm.lead_asignaciones
  (analista_id, lead_id, origen, motivo_apertura, asignado_en, resultado, resultado_en) values
  ('55555555-5555-4555-8555-555555555555', '44444444-0000-4000-8000-000000000101', 'campania', 'nuevo', '2026-07-04 10:00-05', 'convertido', '2026-07-21 15:00-05'),
  ('55555555-5555-4555-8555-555555555555', '44444444-0000-4000-8000-000000000102', 'campania', 'nuevo', '2026-07-08 10:00-05', null, null);

-- Los leads de V1 sembrados por el otro test necesitan `activo` (el ranking lo
-- exige, la pantalla Conversiones no).
update crm.leads set activo = true where activo is null;

-- ---------------------------------------------------------------------------
-- 1. GERENCIA (alcance global)
-- ---------------------------------------------------------------------------
do $$
declare v jsonb; r jsonb; e text := '';
begin
  v := crm.metricas_conversiones_equipo_fn('2026-07-01', '2026-07-31');

  if v->>'alcance' <> 'global' then
    e := e || format(' alcance=%s(≠global)', v->>'alcance'); end if;

  -- V1: leads de julio con vendedor y activos = L1,L2,L3,L4,L6 = 5
  --     cerraron (ledger, sin anulados, madurando): L1,L2,L6 = 3
  --     ANTES esto valia 0 para todos: el ranking se ordenaba por leads.
  select value into r from jsonb_array_elements(v->'responsables') value
   where value->>'vendedor_id' = '22222222-2222-4222-8222-222222222222';
  if (r->>'leads')::int <> 5 then
    e := e || format(' V1.leads=%s(≠5)', r->>'leads'); end if;
  if (r->>'clientes')::int <> 3 then
    e := e || format(' V1.clientes=%s(≠3 — ¿volvio el numerador muerto?)', r->>'clientes'); end if;
  -- nucleo de V1: divisor 5 · numerador 2 + 0.15 + 1(cartera) = 3.15 · 63.00 %
  if (r->>'nucleo_divisor')::int <> 5 then
    e := e || format(' V1.nucleo_divisor=%s(≠5)', r->>'nucleo_divisor'); end if;
  if (r->>'nucleo_conversion_pct')::numeric <> 63.00 then
    e := e || format(' V1.nucleo_pct=%s(≠63.00)', r->>'nucleo_conversion_pct'); end if;

  -- V2: 2 leads, 1 cierre · nucleo divisor 2, numerador 1 → 50.00 %
  select value into r from jsonb_array_elements(v->'responsables') value
   where value->>'vendedor_id' = '55555555-5555-4555-8555-555555555555';
  if (r->>'leads')::int <> 2 then
    e := e || format(' V2.leads=%s(≠2)', r->>'leads'); end if;
  if (r->>'clientes')::int <> 1 then
    e := e || format(' V2.clientes=%s(≠1)', r->>'clientes'); end if;
  if (r->>'nucleo_conversion_pct')::numeric <> 50.00 then
    e := e || format(' V2.nucleo_pct=%s(≠50.00)', r->>'nucleo_conversion_pct'); end if;

  -- El ranking se ordena por clientes: V1 (3) antes que V2 (1). Antes, con
  -- todo a 0, el orden lo decidia `leads` — es decir, nada de resultados.
  if (v->'responsables'->0->>'vendedor_id') <> '22222222-2222-4222-8222-222222222222' then
    e := e || ' el primero del ranking no es V1'; end if;

  -- Sondas: la paridad contra el nucleo real debe cuadrar y haber comparado algo
  if (v->'sondas'->>'paridad_nucleo')::numeric <> 0 then
    e := e || format(' paridad=%s(≠0)', v->'sondas'->>'paridad_nucleo'); end if;
  if (v->'sondas'->>'cuadra') <> 'true' then
    e := e || ' sondas.cuadra≠true'; end if;
  if (v->'sondas'->>'paridad_filas')::int < 2 then
    e := e || ' la paridad no comparo ni dos vendedores'; end if;
  if (v->'sondas'->>'cierres_anulados')::int <> 1 then
    e := e || format(' anulados=%s(≠1)', v->'sondas'->>'cierres_anulados'); end if;

  if e <> '' then raise exception 'ORACULO ROTO (gerencia):%', e; end if;
  raise notice 'RANKING GLOBAL OK · V1 3/5 (nucleo 63.00%%) · V2 1/2 (nucleo 50.00%%) · paridad 0';
end $$;

-- ---------------------------------------------------------------------------
-- 2. AMBITO: el supervisor SOLO ve a su vendedor, y su nucleo tambien
-- ---------------------------------------------------------------------------
do $$
declare v jsonb; e text := '';
begin
  perform set_config('test.uid', '66666666-6666-4666-8666-666666666666', true);
  v := crm.metricas_conversiones_equipo_fn('2026-07-01', '2026-07-31');

  if v->>'alcance' <> 'equipo' then
    e := e || format(' alcance=%s(≠equipo)', v->>'alcance'); end if;
  if jsonb_array_length(v->'responsables') <> 1 then
    e := e || format(' el supervisor ve %s responsables(≠1)', jsonb_array_length(v->'responsables')); end if;
  if (v->'responsables'->0->>'vendedor_id') <> '55555555-5555-4555-8555-555555555555' then
    e := e || ' el supervisor ve a un vendedor que no es el suyo'; end if;
  -- Y el NUCLEO tambien va recortado: solo los episodios de V2 (divisor 2)
  if (v->'responsables'->0->>'nucleo_divisor')::int <> 2 then
    e := e || format(' nucleo del supervisor sin recortar: divisor=%s(≠2)',
                     v->'responsables'->0->>'nucleo_divisor'); end if;
  if (v->'sondas'->>'paridad_nucleo')::numeric <> 0 then
    e := e || format(' paridad del ambito=%s(≠0)', v->'sondas'->>'paridad_nucleo'); end if;

  if e <> '' then raise exception 'ORACULO ROTO (ambito):%', e; end if;
  raise notice 'AMBITO OK · el supervisor ve 1 vendedor y su nucleo va recortado';
end $$;

-- ---------------------------------------------------------------------------
-- 2b. COHERENCIA (objecion A2): un lead cuyo DUENO ACTUAL no es quien lo
--     CERRO debe contar IGUAL mire gerencia o mire su supervisor. Si la
--     cosecha se recortara por ambito, gerencia veria 1 cliente y el
--     supervisor 0 para el mismo vendedor: dos verdades del mismo dato.
-- ---------------------------------------------------------------------------
do $$
declare v_ger jsonb; v_sup jsonb; r_ger jsonb; r_sup jsonb; e text := '';
begin
  -- Lead de V2 (dueno actual) CERRADO por V1, que esta fuera del subarbol del
  -- supervisor de V2. Es el escenario que el repo documenta como real:
  -- `crm.leads.vendedor_id` es MUTABLE y el `analista_id` del ledger no.
  insert into crm.leads (id, creado_en, origen, categoria_interes, etapa, vendedor_id, activo)
  values ('44444444-0000-4000-8000-000000000103', '2026-07-14 09:00-05', 'campania',
          'renta', 'convertido', '55555555-5555-4555-8555-555555555555', true);
  insert into crm.lead_asignaciones
    (analista_id, lead_id, origen, motivo_apertura, asignado_en, resultado, resultado_en)
  values ('22222222-2222-4222-8222-222222222222', '44444444-0000-4000-8000-000000000103',
          'campania', 'nuevo', '2026-07-14 10:00-05', 'convertido', '2026-07-26 15:00-05');

  perform set_config('test.uid', '11111111-1111-4111-8111-111111111111', true);
  v_ger := crm.metricas_conversiones_equipo_fn('2026-07-01', '2026-07-31');
  perform set_config('test.uid', '66666666-6666-4666-8666-666666666666', true);
  v_sup := crm.metricas_conversiones_equipo_fn('2026-07-01', '2026-07-31');

  select value into r_ger from jsonb_array_elements(v_ger->'responsables') value
   where value->>'vendedor_id' = '55555555-5555-4555-8555-555555555555';
  select value into r_sup from jsonb_array_elements(v_sup->'responsables') value
   where value->>'vendedor_id' = '55555555-5555-4555-8555-555555555555';

  if (r_ger->>'clientes') is distinct from (r_sup->>'clientes') then
    e := e || format(' gerencia ve %s clientes y el supervisor %s para el MISMO vendedor',
                     r_ger->>'clientes', r_sup->>'clientes'); end if;
  if (r_ger->>'conversion_pct') is distinct from (r_sup->>'conversion_pct') then
    e := e || ' el % del mismo vendedor difiere segun quien mire'; end if;
  -- y debe contar: el lead cerro, aunque lo cerrara otro
  if (r_ger->>'clientes')::int <> 2 then
    e := e || format(' V2.clientes=%s(≠2: el lead cerrado por otro no cuenta)', r_ger->>'clientes'); end if;
  -- Y la discrepancia de acreditacion queda MEDIDA, no escondida: este lead
  -- lo cerro V1 pero se acredita a V2 (su dueno actual).
  if (v_ger->'sondas'->>'clientes_acreditados_a_otro_dueno')::int <> 1 then
    e := e || format(' sonda de acreditacion=%s(≠1)',
                     v_ger->'sondas'->>'clientes_acreditados_a_otro_dueno'); end if;

  -- limpieza para no contaminar los bloques siguientes
  delete from crm.lead_asignaciones where lead_id = '44444444-0000-4000-8000-000000000103';
  delete from crm.leads where id = '44444444-0000-4000-8000-000000000103';

  if e <> '' then raise exception 'ORACULO ROTO (coherencia):%', e; end if;
  raise notice 'COHERENCIA OK · dueno≠cerrador: gerencia y supervisor ven lo MISMO';
end $$;

-- ---------------------------------------------------------------------------
-- 2c. SONDAS del roster (objecion M4): un supervisor con episodios PROPIOS
--     deja divisor fuera del roster de vendedores. Sin este caso, la sonda
--     valia 0 por construccion y estaba verde por vacuidad.
-- ---------------------------------------------------------------------------
do $$
declare v jsonb; e text := '';
begin
  -- El propio supervisor recibe un lead (se ve a si mismo en su ambito)
  insert into crm.equipo_supervision (supervisor_id, vendedor_id)
  values ('66666666-6666-4666-8666-666666666666', '66666666-6666-4666-8666-666666666666');
  insert into crm.leads (id, creado_en, origen, categoria_interes, etapa, vendedor_id, activo)
  values ('44444444-0000-4000-8000-000000000104', '2026-07-16 09:00-05', 'campania',
          'renta', 'contactado', '66666666-6666-4666-8666-666666666666', true);
  insert into crm.lead_asignaciones
    (analista_id, lead_id, origen, motivo_apertura, asignado_en, resultado, resultado_en)
  values ('66666666-6666-4666-8666-666666666666', '44444444-0000-4000-8000-000000000104',
          'campania', 'nuevo', '2026-07-16 10:00-05', null, null);

  perform set_config('test.uid', '66666666-6666-4666-8666-666666666666', true);
  v := crm.metricas_conversiones_equipo_fn('2026-07-01', '2026-07-31');

  -- El supervisor NO esta en el roster de vendedores, pero su episodio SI
  -- entra en el nucleo: ese hueco es lo que la sonda debe publicar.
  if (v->'sondas'->>'divisor_fuera_del_roster')::int <> 1 then
    e := e || format(' divisor_fuera_del_roster=%s(≠1)', v->'sondas'->>'divisor_fuera_del_roster'); end if;
  -- y el desglose sigue sin traerlo (no es vendedor)
  if exists (select 1 from jsonb_array_elements(v->'responsables') x
              where x.value->>'vendedor_id' = '66666666-6666-4666-8666-666666666666') then
    e := e || ' el supervisor se colo en el desglose de vendedores'; end if;
  -- la sonda del supervisor no puede superar la de gerencia
  perform set_config('test.uid', '11111111-1111-4111-8111-111111111111', true);
  if (v->'sondas'->>'divisor_fuera_del_roster')::int >
     (crm.metricas_conversiones_equipo_fn('2026-07-01','2026-07-31')->'sondas'->>'divisor_fuera_del_roster')::int then
    e := e || ' la sonda del supervisor supera la de gerencia (ambito roto)'; end if;

  delete from crm.lead_asignaciones where lead_id = '44444444-0000-4000-8000-000000000104';
  delete from crm.leads where id = '44444444-0000-4000-8000-000000000104';
  delete from crm.equipo_supervision
   where supervisor_id = '66666666-6666-4666-8666-666666666666'
     and vendedor_id = '66666666-6666-4666-8666-666666666666';

  if e <> '' then raise exception 'ORACULO ROTO (sondas del roster):%', e; end if;
  raise notice 'SONDAS DEL ROSTER OK · el hueco supervisor/roster se publica y no se cuela';
end $$;

-- ---------------------------------------------------------------------------
-- 3. EL GATE: quien NO puede, no pasa
-- ---------------------------------------------------------------------------
do $$
declare v jsonb; e text := '';
begin
  -- vendedor: esta pantalla es de supervisor/gerencia
  perform set_config('test.uid', '22222222-2222-4222-8222-222222222222', true);
  begin
    v := crm.metricas_conversiones_equipo_fn('2026-07-01', '2026-07-31');
    e := e || ' un VENDEDOR obtuvo el ranking';
  exception when sqlstate '42501' then null; end;

  -- anonimo
  perform set_config('test.uid', '', true);
  begin
    v := crm.metricas_conversiones_equipo_fn('2026-07-01', '2026-07-31');
    e := e || ' un ANONIMO obtuvo el ranking';
  exception when sqlstate '42501' then null; end;

  -- periodo invalido con gerencia legitima
  perform set_config('test.uid', '11111111-1111-4111-8111-111111111111', true);
  begin
    v := crm.metricas_conversiones_equipo_fn('2026-07-01', '2099-01-01');
    e := e || ' un periodo futuro fue aceptado';
  exception when sqlstate '22023' then null; end;

  if e <> '' then raise exception 'ORACULO ROTO (gate):%', e; end if;
  raise notice 'GATE DEL RANKING OK (vendedor, anonimo y periodo invalido rechazados)';
end $$;

-- ---------------------------------------------------------------------------
-- 4. El desglose no puede traer a nadie que no sea vendedor
-- ---------------------------------------------------------------------------
do $$
declare v jsonb; v_malos int;
begin
  perform set_config('test.uid', '11111111-1111-4111-8111-111111111111', true);
  v := crm.metricas_conversiones_equipo_fn('2026-07-01', '2026-07-31');
  select count(*) into v_malos
    from jsonb_array_elements(v->'responsables') e
   where private.rol_crm((e.value->>'vendedor_id')::uuid) is distinct from 'vendedor';
  if v_malos <> 0 then
    raise exception 'ORACULO ROTO: % elementos del desglose no son vendedores', v_malos;
  end if;
  raise notice 'DESGLOSE OK (solo vendedores)';
end $$;

select 'TEST-F2-RANKING: TODO VERDE' as resultado;

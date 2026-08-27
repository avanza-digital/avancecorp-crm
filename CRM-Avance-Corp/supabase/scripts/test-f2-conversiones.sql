-- Oraculo de F2.1 (pantalla Conversiones sobre la tabla-base).
-- El mundo lo siembra fixture-f2-conversion.sql; aqui solo se comprueba.
-- Todos los numeros estan calculados A MANO desde ese fixture.

set search_path = '';
set test.uid = '11111111-1111-4111-8111-111111111111';

-- ---------------------------------------------------------------------------
-- ORACULO
-- ---------------------------------------------------------------------------
do $$
declare
  v jsonb;
  e text := '';
begin
  v := private.metricas_conversiones_implementacion('2026-07-01', '2026-07-31');

  -- ── NUCLEO (cifra principal) ──────────────────────────────────────────
  -- divisor  = recibidos NO referidos de julio: L1,L3,L4,L5,L6 = 5
  -- cierres  = de julio y sin anular: L1,L5 (no ref) = 2 · L2 (ref) = 1
  -- cartera  = 1 operacion elegible
  -- numerador = 2 + 0.15*1 + 1 = 3.15  →  pct = 100*3.15/5 = 63.0
  if (v->'nucleo'->>'divisor')::int <> 5 then
    e := e || format(' nucleo.divisor=%s(≠5)', v->'nucleo'->>'divisor'); end if;
  if (v->'nucleo'->>'referidos_recibidos')::int <> 1 then
    e := e || format(' nucleo.referidos=%s(≠1)', v->'nucleo'->>'referidos_recibidos'); end if;
  if (v->'nucleo'->>'cierres_no_referidos')::int <> 2 then
    e := e || format(' nucleo.cnr=%s(≠2)', v->'nucleo'->>'cierres_no_referidos'); end if;
  if (v->'nucleo'->>'cierres_referidos')::int <> 1 then
    e := e || format(' nucleo.cr=%s(≠1)', v->'nucleo'->>'cierres_referidos'); end if;
  if (v->'nucleo'->>'operaciones_cartera')::int <> 1 then
    e := e || format(' nucleo.ops=%s(≠1)', v->'nucleo'->>'operaciones_cartera'); end if;
  if (v->'nucleo'->>'numerador')::numeric <> 3.15 then
    e := e || format(' nucleo.numerador=%s(≠3.15)', v->'nucleo'->>'numerador'); end if;
  if (v->'nucleo'->>'conversion_pct')::numeric <> 63.00 then
    e := e || format(' nucleo.pct=%s(≠63.00)', v->'nucleo'->>'conversion_pct'); end if;
  if (v->'nucleo'->>'incluye_cartera') <> 'true' then
    e := e || ' nucleo.incluye_cartera≠true'; end if;
  if (v->'nucleo'->>'peso_referido')::numeric <> 0.15 then
    e := e || format(' nucleo.peso=%s(≠0.15)', v->'nucleo'->>'peso_referido'); end if;

  -- ── COSECHA (segunda lectura, D2) ─────────────────────────────────────
  -- altas de julio: L1,L2,L3,L4,L6 = 5 (L5 es de junio)
  -- cerraron (hasta hoy, sin anulados): L1,L2,L6 = 3  → 60.0 %
  -- L6 cerro en AGOSTO: la cosecha SI lo cuenta (maduracion); el nucleo no.
  if (v->'cosecha'->>'leads')::int <> 5 then
    e := e || format(' cosecha.leads=%s(≠5)', v->'cosecha'->>'leads'); end if;
  if (v->'cosecha'->>'cerraron')::int <> 3 then
    e := e || format(' cosecha.cerraron=%s(≠3)', v->'cosecha'->>'cerraron'); end if;
  if (v->'cosecha'->>'conversion_pct')::numeric <> 60.0 then
    e := e || format(' cosecha.pct=%s(≠60.0)', v->'cosecha'->>'conversion_pct'); end if;

  -- ── EL FIX DE H3: el numerador muerto ya no manda ─────────────────────
  -- Con `contrato_id` (columna que nadie rellena) esto valia 0 SIEMPRE.
  if (v->'cohorte'->>'contratos')::int <> 3 then
    e := e || format(' cohorte.contratos=%s(≠3 — ¿volvio el numerador muerto?)', v->'cohorte'->>'contratos'); end if;
  if (v->'cohorte'->>'clientes')::int <> 3 then
    e := e || format(' cohorte.clientes=%s(≠3)', v->'cohorte'->>'clientes'); end if;
  if (v->'cohorte'->>'conversion_contratos_pct')::numeric <> 60.0 then
    e := e || format(' cohorte.conv_contratos=%s(≠60.0)', v->'cohorte'->>'conversion_contratos_pct'); end if;
  -- el ultimo escalon del embudo tambien deja de ser 0
  if (v->'embudo'->6->>'cantidad')::int <> 3 then
    e := e || format(' embudo[contratos]=%s(≠3)', v->'embudo'->6->>'cantidad'); end if;

  -- ── SONDAS ────────────────────────────────────────────────────────────
  -- El recomputo desde episodios debe cuadrar EXACTAMENTE con el nucleo real.
  if (v->'sondas'->>'paridad_nucleo')::numeric <> 0 then
    e := e || format(' sondas.paridad=%s(≠0)', v->'sondas'->>'paridad_nucleo'); end if;
  if (v->'sondas'->>'cuadra') <> 'true' then
    e := e || ' sondas.cuadra≠true'; end if;
  if (v->'sondas'->>'cierres_anulados')::int <> 1 then
    e := e || format(' sondas.anulados=%s(≠1)', v->'sondas'->>'cierres_anulados'); end if;

  -- ── D6: el referido viaja con su peso, no con 1 ───────────────────────
  if (select ori->>'peso_en_nucleo' from jsonb_array_elements(v->'origenes') ori
       where ori->>'origen' = 'referido')::numeric <> 0.15 then
    e := e || ' origenes[referido].peso_en_nucleo≠0.15'; end if;
  if (select ori->>'fuera_del_divisor_del_nucleo' from jsonb_array_elements(v->'origenes') ori
       where ori->>'origen' = 'referido') <> 'true' then
    e := e || ' origenes[referido].fuera_del_divisor≠true'; end if;

  -- ── El vendedor lleva su cifra del nucleo (la de Ranking/Metas) ───────
  if (select rr->>'nucleo_divisor' from jsonb_array_elements(v->'responsables') rr
       where rr->>'vendedor_id' = banco.uid('V1')::text)::int <> 5 then
    e := e || ' responsables[V1].nucleo_divisor≠5'; end if;
  if (select rr->>'nucleo_conversion_pct' from jsonb_array_elements(v->'responsables') rr
       where rr->>'vendedor_id' = banco.uid('V1')::text)::numeric <> 63.0 then
    e := e || ' responsables[V1].nucleo_pct≠63.0'; end if;

  -- ── Lo que NO debe cambiar: produccion mide CONTRATOS (H14) ───────────
  -- Sin contratos enlazados en el fixture, sigue en 0: no se contamino con
  -- la conversion.
  if (v->'produccion'->>'contratos')::int <> 0 then
    e := e || format(' produccion.contratos=%s(≠0 — se contamino con conversion)', v->'produccion'->>'contratos'); end if;

  if e <> '' then
    raise exception 'ORACULO ROTO:%', e;
  end if;
  raise notice 'ORACULO F2.1 OK · nucleo 63.0%% (3.15/5) · cosecha 60.0%% (3/5) · sondas cuadran';
end $$;

-- ---------------------------------------------------------------------------
-- Objecion A2 del auditor: un rango que EMPIEZA el dia 1 pero NO llega a fin
-- de mes no puede arrastrar la cartera del mes entero. Julio 1→10: la
-- operacion del 15 de julio NO debe contar.
-- ---------------------------------------------------------------------------
do $$
declare v jsonb; e text := '';
begin
  v := private.metricas_conversiones_implementacion('2026-07-01', '2026-07-10');
  if (v->'nucleo'->>'incluye_cartera') <> 'false' then
    e := e || ' un rango parcial del mes NO debe incluir cartera'; end if;
  if (v->'nucleo'->>'operaciones_cartera')::int <> 0 then
    e := e || format(' ops=%s(≠0): la operacion del 15-jul se colo en un rango 1→10',
                     v->'nucleo'->>'operaciones_cartera'); end if;
  -- divisor = recibidos no referidos hasta el 10: L5(2-jul), L1(3-jul), L3(6-jul), L4(10-jul) = 4
  -- cierres en ese rango: ninguno (el primero cierra el 20) → numerador 0
  if (v->'nucleo'->>'divisor')::int <> 4 then
    e := e || format(' divisor parcial=%s(≠4)', v->'nucleo'->>'divisor'); end if;
  if (v->'nucleo'->>'numerador')::numeric <> 0 then
    e := e || format(' numerador parcial=%s(≠0)', v->'nucleo'->>'numerador'); end if;
  if e <> '' then raise exception 'ORACULO ROTO (rango parcial):%', e; end if;
  raise notice 'RANGO PARCIAL OK (1→10 jul: sin cartera, 0/4)';
end $$;

-- ---------------------------------------------------------------------------
-- Sondas que miden los huecos reales (objeciones M3/M4 del auditor)
-- ---------------------------------------------------------------------------
do $$
declare v jsonb; e text := '';
begin
  v := private.metricas_conversiones_implementacion('2026-07-01', '2026-07-31');
  -- Todo el divisor es de V1, que SI esta en el roster de vendedores.
  if (v->'sondas'->>'divisor_fuera_del_roster')::int <> 0 then
    e := e || format(' divisor_fuera_del_roster=%s(≠0)', v->'sondas'->>'divisor_fuera_del_roster'); end if;
  -- L3 tiene etapa='convertido' pero su cierre esta ANULADO: es exactamente el
  -- desacuerdo que la sonda debe sacar a la luz (1 lead).
  if (v->'sondas'->>'cohorte_convertidos_sin_cierre_elegible')::int <> 1 then
    e := e || format(' convertidos_sin_cierre=%s(≠1)', v->'sondas'->>'cohorte_convertidos_sin_cierre_elegible'); end if;
  if (v->'sondas'->>'numerador_fuera_del_roster')::numeric <> 0 then
    e := e || format(' numerador_fuera_del_roster=%s(≠0)', v->'sondas'->>'numerador_fuera_del_roster'); end if;
  if (v->'sondas'->>'cierres_sin_ficha_convertida')::int <> 0 then
    e := e || format(' cierres_sin_ficha=%s(≠0)', v->'sondas'->>'cierres_sin_ficha_convertida'); end if;
  if (v->'sondas'->>'origen_ficha_distinto_del_ledger')::int <> 0 then
    e := e || format(' origen_discrepante=%s(≠0)', v->'sondas'->>'origen_ficha_distinto_del_ledger'); end if;
  if (v->'sondas'->>'cartera_fuera_del_rango')::int <> 0 then
    e := e || format(' cartera_fuera_del_rango=%s(≠0)', v->'sondas'->>'cartera_fuera_del_rango'); end if;
  if e <> '' then raise exception 'ORACULO ROTO (sondas):%', e; end if;
  raise notice 'SONDAS OK (roster 0 · convertidos sin cierre 1 · cartera en rango)';
end $$;

-- ---------------------------------------------------------------------------
-- Contrato de rangos libres: si el rango NO es un mes, no hay cartera y la
-- sonda de paridad se declara no aplicable en vez de mentir.
-- ---------------------------------------------------------------------------
do $$
declare v jsonb;
begin
  v := private.metricas_conversiones_implementacion('2026-07-10', '2026-08-05');
  if (v->'nucleo'->>'incluye_cartera') <> 'false' then
    raise exception 'ORACULO ROTO: un rango que cruza meses NO debe incluir cartera';
  end if;
  if (v->'nucleo'->>'operaciones_cartera')::int <> 0 then
    raise exception 'ORACULO ROTO: rango libre con operaciones de cartera';
  end if;
  if v->'sondas'->>'paridad_nucleo' is not null then
    raise exception 'ORACULO ROTO: la sonda de paridad debe ser NULL fuera de un mes';
  end if;
  raise notice 'CONTRATO RANGO LIBRE OK (sin cartera, sonda no aplicable)';
end $$;

-- ---------------------------------------------------------------------------
-- EL GATE DE ROL (objecion de Codex, punto 7): sin estos casos, borrar la
-- puerta de autorizacion no rompia ni una prueba.
-- ---------------------------------------------------------------------------
do $$
declare v jsonb; v_err text := '';
begin
  -- 1) Vendedor: NO puede ver la pantalla de gerencia
  perform set_config('test.uid', '22222222-2222-4222-8222-222222222222', true);
  begin
    v := private.metricas_conversiones_implementacion('2026-07-01', '2026-07-31');
    v_err := v_err || ' un VENDEDOR obtuvo el payload (gate abierto)';
  exception when sqlstate '42501' then null;
  end;

  -- 2) Anonimo (sin identidad): tampoco
  perform set_config('test.uid', '', true);
  begin
    v := private.metricas_conversiones_implementacion('2026-07-01', '2026-07-31');
    v_err := v_err || ' un ANONIMO obtuvo el payload (gate abierto)';
  exception when sqlstate '42501' then null;
  end;

  -- 3) Gerencia INACTIVA: tampoco
  perform set_config('test.uid', '11111111-1111-4111-8111-111111111111', true);
  update crm.equipo set activo = false where perfil_id = '11111111-1111-4111-8111-111111111111';
  begin
    v := private.metricas_conversiones_implementacion('2026-07-01', '2026-07-31');
    v_err := v_err || ' una GERENCIA INACTIVA obtuvo el payload';
  exception when sqlstate '42501' then null;
  end;
  update crm.equipo set activo = true where perfil_id = '11111111-1111-4111-8111-111111111111';

  -- 4) Periodo invalido (futuro) con gerencia legitima → 22023, no 42501
  begin
    v := private.metricas_conversiones_implementacion('2026-07-01', '2099-01-01');
    v_err := v_err || ' un periodo futuro fue aceptado';
  exception when sqlstate '22023' then null;
  end;

  if v_err <> '' then raise exception 'ORACULO ROTO (gate):%', v_err; end if;
  raise notice 'GATE DE ROL OK (vendedor, anonimo, gerencia inactiva y periodo invalido rechazados)';
end $$;

-- ---------------------------------------------------------------------------
-- La cifra del nucleo debe poder compararse con la de HOY: misma escala.
-- ---------------------------------------------------------------------------
do $$
declare v jsonb; v_pct numeric; v_nucleo numeric;
begin
  v := private.metricas_conversiones_implementacion('2026-07-01', '2026-07-31');
  v_pct := (v->'nucleo'->>'conversion_pct')::numeric;
  select cm.conversion_pct into v_nucleo
    from private.conversion_mensual_por_vendedor(
      '2026-07-01 00:00-05'::timestamptz, '2026-08-01 00:00-05'::timestamptz,
      true, null, 0.15) cm
   where cm.analista_id = '22222222-2222-4222-8222-222222222222';
  if v_pct is distinct from v_nucleo then
    raise exception 'ORACULO ROTO: el %% del bloque nucleo (%) no coincide con el nucleo real (%)',
      v_pct, v_nucleo;
  end if;
  -- y la sonda tuvo sustancia: comparo al menos una fila
  if (v->'sondas'->>'paridad_filas')::int < 1 then
    raise exception 'ORACULO ROTO: la sonda de paridad no comparo ni una fila (cero vacuo)';
  end if;
  raise notice 'ESCALA OK · nucleo % = nucleo real % · paridad sobre % fila(s)',
    v_pct, v_nucleo, v->'sondas'->>'paridad_filas';
end $$;

select 'TEST-F2-CONVERSIONES: TODO VERDE' as resultado;

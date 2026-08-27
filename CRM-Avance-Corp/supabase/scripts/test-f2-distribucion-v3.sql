-- Oraculo de F2.3b (Distribucion v3: porcentajes servidos + nucleo + sondas).
-- El mundo lo montan el runner y los fixtures; aqui solo se comprueba, con
-- valores CALCULADOS A MANO del fixture:
--   fixture julio: 6 episodios (5 PEN + 1 USD) de una vendedora + 1 operacion
--   de cartera elegible.
--     PEN: lead1 convertido 20/07 · lead2 convertido 21/07 pero ANULADO ·
--          lead3 descartado · lead4 convertido en AGOSTO (madura fuera) ·
--          lead6 REFERIDO convertido 26/07
--     USD: lead5 convertido 25/07.
--   punteria PEN  = 3 cerrados (lead1+lead4+lead6) ÷ 4 resueltos = 75 %
--   punteria USD  = 1 ÷ 1 = 100 %
--   nucleo        = divisor 5 (recibidos julio NO referidos: leads1-4 + lead5)
--                   · numerador 3.15 = 2 cierres de julio sin anulados (lead1
--                   + lead5) + 0.15 del referido (lead6) + 1 operacion de
--                   cartera (lead4 cerro en agosto: el flujo no lo cuenta)
--                   → 63.00 %

set search_path = '';

-- Mismo instante para las dos versiones: la paridad es byte a byte.
create or replace function banco.t() returns timestamptz
  language sql immutable as $$ select '2026-08-27 12:00:00-05'::timestamptz $$;

-- ---------------------------------------------------------------------------
-- 1. PARIDAD: v3 sin sus claves nuevas ES v2, byte a byte
-- ---------------------------------------------------------------------------
do $$
declare
  v2 jsonb; v3 jsonb; v3s jsonb; v_analistas jsonb;
begin
  v2 := private.metricas_distribucion_leads_v2_core('2026-07-01','2026-07-31', banco.t());
  v3 := private.metricas_distribucion_leads_v3_core('2026-07-01','2026-07-31', banco.t());

  if v2 is null or v3 is null then
    raise exception 'ORACULO VACUO: un motor devolvio NULL';
  end if;

  v3s := v3 - 'sondas';
  v3s := jsonb_set(v3s, '{version}', '2'::jsonb);
  v3s := jsonb_set(v3s, '{alcances}', (v3s->'alcances')
    - 'conversion_punteria' - 'conversion_nucleo' - 'conversion_incluye_cartera');
  v3s := jsonb_set(v3s, '{resumen}', (v3s->'resumen') - 'conversion');
  select coalesce(jsonb_agg(
    jsonb_set(
      a.elemento - 'conversion',
      '{pen,rangos}',
      (select coalesce(jsonb_agg((r.elemento - 'conversion') order by r.orden), '[]'::jsonb)
         from jsonb_array_elements(a.elemento#>'{pen,rangos}')
              with ordinality as r(elemento, orden))
    ) order by a.orden), '[]'::jsonb)
    into v_analistas
    from jsonb_array_elements(v3s->'analistas') with ordinality as a(elemento, orden);
  v3s := jsonb_set(v3s, '{analistas}', v_analistas);

  -- Por TEXTO serializado, no por igualdad jsonb (Codex d5): jsonb compara
  -- 1 y 1.0 como iguales pero serializan distinto — y lo que viaja al front
  -- son los bytes serializados.
  if v3s::text is distinct from v2::text then
    raise exception 'ORACULO ROTO (paridad): v3 sin sus claves nuevas NO es v2 byte a byte. delta claves resumen v3=[%] v2=[%]',
      (select string_agg(k, ',' order by k) from jsonb_object_keys(v3s->'resumen') k),
      (select string_agg(k, ',' order by k) from jsonb_object_keys(v2->'resumen') k);
  end if;
  raise notice 'PARIDAD OK · v3 = v2 + claves nuevas, sin cambiar un byte de lo que ya existia';
end $$;

-- ---------------------------------------------------------------------------
-- 2. LOS VALORES: punteria, nucleo y sondas contra el calculo a mano
-- ---------------------------------------------------------------------------
do $$
declare
  v3 jsonb; a jsonb; c jsonb; rc jsonb; e text := '';
begin
  v3 := private.metricas_distribucion_leads_v3_core('2026-07-01','2026-07-31', banco.t());

  select a2.elemento into a
    from jsonb_array_elements(v3->'analistas') a2(elemento)
   where a2.elemento->>'analista_id' = '22222222-2222-4222-8222-222222222222';

  -- GUARDAS ANTI-VACUIDAD (ya paso DOS veces en F2: una ruta equivocada
  -- compara contra NULL y la prueba pasa sin comprobar nada)
  if a is null then
    raise exception 'ORACULO VACUO: la vendedora no aparece en analistas';
  end if;
  if (a#>>'{pen,cohorte,episodios_recibidos}')::int <> 5 then
    raise exception 'ORACULO VACUO: el fixture PEN no llego (recibidos=%)',
      a#>>'{pen,cohorte,episodios_recibidos}';
  end if;
  if (a#>>'{usd_no_segmentado,cohorte_episodios_recibidos}')::int <> 1 then
    raise exception 'ORACULO VACUO: el fixture USD no llego';
  end if;
  c := a->'conversion';
  if c is null or jsonb_typeof(c) <> 'object' then
    raise exception 'ORACULO VACUO: falta analista.conversion';
  end if;

  -- punteria por analista
  if (c#>>'{pen,convertidos}')::int <> 3 then e := e || format(' pen.convertidos=%s(≠3)', c#>>'{pen,convertidos}'); end if;
  if (c#>>'{pen,resueltos}')::int <> 4 then e := e || format(' pen.resueltos=%s(≠4)', c#>>'{pen,resueltos}'); end if;
  if (c#>>'{pen,pct}')::numeric <> 75 then e := e || format(' pen.pct=%s(≠75)', c#>>'{pen,pct}'); end if;
  if (c#>>'{usd,convertidos}')::int <> 1 then e := e || format(' usd.convertidos=%s(≠1)', c#>>'{usd,convertidos}'); end if;
  if (c#>>'{usd,pct}')::numeric <> 100 then e := e || format(' usd.pct=%s(≠100)', c#>>'{usd,pct}'); end if;

  -- nucleo por analista (la MISMA cifra que HOY/Metas/Ranking). El referido
  -- va FUERA del divisor y pondera 0.15; la operacion de cartera suma 1
  -- (Codex b6: sin estos dos terminos vivos en el fixture, un mutante que
  -- los rompiera pasaria verde).
  if (c->>'nucleo_divisor')::int <> 5 then e := e || format(' nucleo_divisor=%s(≠5: ¿el referido entro al divisor?)', c->>'nucleo_divisor'); end if;
  if (c->>'nucleo_numerador')::numeric <> 3.15 then e := e || format(' nucleo_numerador=%s(≠3.15: ¿anulado dentro, referido sin ponderar o cartera fuera?)', c->>'nucleo_numerador'); end if;
  if (c->>'nucleo_conversion_pct')::numeric <> 63.00 then e := e || format(' nucleo_pct=%s(≠63.00)', c->>'nucleo_conversion_pct'); end if;
  if (c->>'nucleo_referidos_recibidos')::int <> 1 then e := e || format(' referidos=%s(≠1)', c->>'nucleo_referidos_recibidos'); end if;

  -- resumen: misma cuenta, a nivel de la casa (el USD que hoy suma el navegador)
  c := v3#>'{resumen,conversion}';
  if c is null then raise exception 'ORACULO VACUO: falta resumen.conversion'; end if;
  if (c#>>'{pen,convertidos}')::int <> 3 or (c#>>'{pen,resueltos}')::int <> 4
     or (c#>>'{pen,pct}')::numeric <> 75 then
    e := e || format(' resumen.pen=%s', c->'pen'); end if;
  if (c#>>'{usd,convertidos}')::int <> 1 or (c#>>'{usd,pct}')::numeric <> 100 then
    e := e || format(' resumen.usd=%s', c->'usd'); end if;
  if (c->>'nucleo_divisor')::int <> 5 or (c->>'nucleo_numerador')::numeric <> 3.15
     or (c->>'nucleo_conversion_pct')::numeric <> 63.00 then
    e := e || format(' resumen.nucleo=%s/%s→%s', c->>'nucleo_numerador', c->>'nucleo_divisor', c->>'nucleo_conversion_pct'); end if;

  -- rangos: el rango con datos convierte; el vacio dice «no se sabe», no 0
  rc := a#>'{pen,rangos,0,conversion}';
  if rc is null then raise exception 'ORACULO VACUO: falta rangos[0].conversion'; end if;
  if (rc->>'convertidos')::int <> 3 or (rc->>'resueltos')::int <> 4
     or (rc->>'pct')::numeric <> 75 then
    e := e || format(' rango0.conversion=%s', rc); end if;
  rc := a#>'{pen,rangos,2,conversion}';
  if rc is null then raise exception 'ORACULO VACUO: falta rangos[2].conversion'; end if;
  if rc->'pct' <> 'null'::jsonb or (rc->>'resueltos')::int <> 0 then
    e := e || format(' rango2.conversion=%s(vacio: pct debia ser null)', rc); end if;

  -- sondas: la red que F3 usara para ocultar en vez de fabricar ceros
  c := v3->'sondas';
  if c is null then raise exception 'ORACULO VACUO: falta el bloque sondas'; end if;
  if c->'cuadra' <> 'true'::jsonb then e := e || format(' sondas.cuadra=%s(≠true)', c->'cuadra'); end if;
  if (c->>'paridad_nucleo')::numeric <> 0 then e := e || format(' paridad=%s(≠0)', c->>'paridad_nucleo'); end if;
  if (c->>'paridad_filas')::int < 1 then e := e || ' paridad_filas=0(la sonda no midio nada)'; end if;
  if (c->>'cierres_anulados')::int <> 1 then e := e || format(' anulados=%s(≠1)', c->>'cierres_anulados'); end if;
  if (c->>'divisor_sin_analista')::int <> 0 then e := e || format(' sin_analista=%s(≠0)', c->>'divisor_sin_analista'); end if;
  if (c->>'peso_referido')::numeric <> 0.15 then e := e || format(' peso=%s(≠0.15)', c->>'peso_referido'); end if;
  if (c->>'nucleo_sin_ficha')::int <> 0 then e := e || format(' nucleo_sin_ficha=%s(≠0)', c->>'nucleo_sin_ficha'); end if;

  if (v3->>'version') <> '3' then e := e || format(' version=%s(≠3)', v3->>'version'); end if;
  if v3#>'{alcances,conversion_incluye_cartera}' <> 'true'::jsonb then
    e := e || ' conversion_incluye_cartera≠true(mes entero debia activar la pierna de cartera)'; end if;

  if e <> '' then raise exception 'ORACULO ROTO (valores):%', e; end if;
  raise notice 'VALORES OK · punteria 75%%/100%% · nucleo 3.15/5=63%% (referido 0.15 + cartera 1) · sondas cuadran';
end $$;

-- ---------------------------------------------------------------------------
-- 3. LA PUERTA Y EL GATE: quien no es gerencia no entra; v1/v2 siguen intactas
-- ---------------------------------------------------------------------------
do $$
declare v jsonb;
begin
  -- vendedora: fuera
  update banco.uid_actual set uid = '22222222-2222-4222-8222-222222222222';
  begin
    v := crm.metricas_distribucion_leads_v3_fn('2026-07-01','2026-07-31');
    raise exception 'ORACULO ROTO (gate): una VENDEDORA leyo la puerta v3';
  exception when insufficient_privilege then null;
  end;

  -- sin sesion: fuera
  update banco.uid_actual set uid = null;
  begin
    v := crm.metricas_distribucion_leads_v3_fn('2026-07-01','2026-07-31');
    raise exception 'ORACULO ROTO (gate): SIN SESION se leyo la puerta v3';
  exception when insufficient_privilege then null;
  end;

  -- gerencia: dentro, con las claves nuevas y SIN transporte de SLA
  update banco.uid_actual set uid = '33333333-3333-4333-8333-333333333333';
  v := crm.metricas_distribucion_leads_v3_fn('2026-07-01','2026-07-31');
  if v is null or jsonb_typeof(v->'sondas') <> 'object'
     or jsonb_typeof(v#>'{resumen,conversion}') <> 'object' then
    raise exception 'ORACULO ROTO (puerta): gerencia no recibe las claves nuevas: %', v->'sondas';
  end if;
  if v->'resumen' ? 'sla_global_contactos' or v->'resumen' ? 'sla_global_en_24h' then
    raise exception 'ORACULO ROTO (puerta): la v3 transporta SLA y no debia';
  end if;
  if (select bool_or(a.value#>'{operacion}' ? 'contactos_asignacion')
        from jsonb_array_elements(v->'analistas') a) then
    raise exception 'ORACULO ROTO (puerta): operacion del analista transporta SLA';
  end if;

  -- las versiones viejas siguen respondiendo, SIN las claves nuevas y CADA
  -- UNA con su forma propia (Codex c3: «no tiene sondas» no distingue una v1
  -- desviada a v2 — se exige la clave que SOLO esa version tiene).
  v := private.metricas_distribucion_leads_autorizada('2026-07-01','2026-07-31', 1::smallint);
  if v is null or v ? 'sondas' then
    raise exception 'ORACULO ROTO (dispatcher): la v1 cambio (sondas=%s)', v ? 'sondas';
  end if;
  if (v->>'version') is distinct from '1'
     or (v#>'{resumen}' ? 'sla_evaluables') is distinct from true then
    raise exception 'ORACULO ROTO (dispatcher): la v1 no tiene la forma v1 (version=%, sla_evaluables=%)',
      v->>'version', v#>'{resumen}' ? 'sla_evaluables';
  end if;
  v := private.metricas_distribucion_leads_autorizada('2026-07-01','2026-07-31', 2::smallint);
  if v is null or v ? 'sondas' or v#>'{resumen}' ? 'conversion' then
    raise exception 'ORACULO ROTO (dispatcher): la v2 cambio';
  end if;
  if (v->>'version') is distinct from '2'
     or (v#>'{resumen}' ? 'sla_global_contactos') is distinct from true
     or (v#>'{resumen}' ? 'sla_evaluables') is distinct from false then
    raise exception 'ORACULO ROTO (dispatcher): la v2 no tiene la forma v2 (version=%)', v->>'version';
  end if;

  raise notice 'GATE OK · vendedora y anonimo fuera · gerencia dentro · v1/v2 intactas';
end $$;

select 'TEST-F2-DISTRIBUCION-V3: TODO VERDE' as resultado;

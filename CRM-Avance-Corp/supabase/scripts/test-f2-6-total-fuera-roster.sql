-- ============================================================================
-- Banco F2.6 — el total del mes abierto suma el agregado fuera de roster (D8)
--
-- Corre sobre la base de stubs que monta run-test-f2-6-total-fuera-roster-local.sh:
--  · crm.conversion_mensual_sin_cartera_fn        = la NUEVA (migración F2.6)
--  · crm.conversion_mensual_sin_cartera_fn_vieja  = la VIEJA (texto pre-F2.6)
--  · private.conversion_mensual_por_vendedor lee private.nucleo_stub
--  · private.roster_metas_vendedores lee private.roster_stub
--
-- Regla anti-oráculo-vacío (mordió DOS veces en F2): toda aserción sobre una
-- ruta del payload va precedida de una guarda que falla si la ruta NO existe.
-- ============================================================================

create or replace function private.asegura(p_cond boolean, p_msg text)
returns void language plpgsql as $$
begin
  if p_cond is distinct from true then
    raise exception 'BANCO F2.6 ❌ %', p_msg;
  end if;
end $$;

-- ── CASO A · sin ex-roster: paridad byte a byte con la versión vieja ────────
truncate private.roster_stub, private.nucleo_stub;
insert into private.roster_stub values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000051'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000051');
insert into private.nucleo_stub values
  ('00000000-0000-0000-0000-0000000000a1', 10, 3, '{"normal": 10}', 2, 1, 0, 2.15, 21.50, '[]', 4, 1.50),
  ('00000000-0000-0000-0000-0000000000a2', 0, 0, '{}', 0, 0, 0, 0, null, '[]', 0, null);

do $caso_a$
declare
  j_nuevo jsonb := crm.conversion_mensual_sin_cartera_fn('2026-08-01');
  j_viejo jsonb := crm.conversion_mensual_sin_cartera_fn_vieja('2026-08-01');
begin
  perform private.asegura(j_nuevo #> '{total,numerador}' is not null, 'A: guarda — total.numerador no existe');
  perform private.asegura(j_nuevo #> '{cobertura,fuera_de_roster,numerador}' is not null, 'A: guarda — cobertura.fuera_de_roster.numerador no existe');
  perform private.asegura((j_nuevo #>> '{cobertura,fuera_de_roster,analistas}')::int = 0, 'A: fuera_de_roster debería estar vacío');
  -- jsonb = es estructural (1 ≡ 1.0): la paridad byte a byte compara ::text
  perform private.asegura(j_nuevo::text = j_viejo::text, 'A: con fuera vacío el payload debe ser byte-idéntico al viejo');
end $caso_a$;

-- ── CASO B · ex-roster con un cierre (el caso real de prod) ─────────────────
insert into private.nucleo_stub values
  ('00000000-0000-0000-0000-0000000000ee', 0, 0, '{}', 1, 0, 0, 1.0, null, '[]', 0, null);

do $caso_b$
declare
  j_nuevo jsonb := crm.conversion_mensual_sin_cartera_fn('2026-08-01');
  j_viejo jsonb := crm.conversion_mensual_sin_cartera_fn_vieja('2026-08-01');
begin
  perform private.asegura(j_nuevo #> '{total,numerador}' is not null and j_viejo #> '{total,numerador}' is not null, 'B: guarda — total.numerador no existe');
  perform private.asegura((j_nuevo #>> '{total,numerador}')::numeric = (j_viejo #>> '{total,numerador}')::numeric + 1.0, 'B: total.numerador debe sumar el cierre del ex-roster');
  perform private.asegura((j_nuevo #>> '{total,analistas}')::int = (j_viejo #>> '{total,analistas}')::int + 1, 'B: total.analistas debe contar al ex-roster');
  perform private.asegura((j_nuevo #>> '{total,divisor}')::int = (j_viejo #>> '{total,divisor}')::int, 'B: divisor sin cambios (el ex-roster no trae leads)');
  perform private.asegura((j_nuevo #>> '{total,cierres_no_referidos}')::int = (j_viejo #>> '{total,cierres_no_referidos}')::int + 1, 'B: cierres_no_referidos debe sumar el del ex-roster');
  -- el % se recalcula sobre el numerador nuevo
  perform private.asegura((j_nuevo #>> '{total,conversion_pct}')::numeric = round(100.0 * (j_nuevo #>> '{total,numerador}')::numeric / (j_nuevo #>> '{total,divisor}')::numeric, 2), 'B: conversion_pct debe salir del numerador que incluye al ex-roster');
  -- el agregado declarado no cambia de forma ni de valor entre versiones
  perform private.asegura(j_nuevo #> '{cobertura,fuera_de_roster}' = j_viejo #> '{cobertura,fuera_de_roster}', 'B: cobertura.fuera_de_roster debe seguir declarándose igual');
  perform private.asegura((j_nuevo #>> '{cobertura,fuera_de_roster,analistas}')::int = 1, 'B: fuera_de_roster.analistas = 1');
  -- sin identidad: responsables idéntico al viejo (ninguna fila nueva)
  perform private.asegura(j_nuevo -> 'responsables' = j_viejo -> 'responsables', 'B: responsables no puede ganar filas');
  perform private.asegura(position('0000000000ee' in j_nuevo::text) = 0, 'B: el uuid del ex-roster no puede salir en el payload');
  -- la FORMA no cambia: mismas claves en cada nivel tocado
  perform private.asegura(
    (select array_agg(k order by k) from jsonb_object_keys(j_nuevo) k) = (select array_agg(k order by k) from jsonb_object_keys(j_viejo) k)
    and (select array_agg(k order by k) from jsonb_object_keys(j_nuevo -> 'total') k) = (select array_agg(k order by k) from jsonb_object_keys(j_viejo -> 'total') k)
    and (select array_agg(k order by k) from jsonb_object_keys(j_nuevo -> 'cobertura') k) = (select array_agg(k order by k) from jsonb_object_keys(j_viejo -> 'cobertura') k)
    and (select array_agg(k order by k) from jsonb_object_keys(j_nuevo #> '{cobertura,fuera_de_roster}') k) = (select array_agg(k order by k) from jsonb_object_keys(j_viejo #> '{cobertura,fuera_de_roster}') k),
    'B: el shape del payload cambió (claves distintas)');
end $caso_b$;

-- ── CASO C · ex-roster con divisor, motivo y referidos ──────────────────────
update private.nucleo_stub
   set divisor = 5, divisor_aproximado = 2, divisor_por_motivo = '{"traspaso": 5}',
       cierres_referidos = 1, cierres_de_arrastre = 1, referidos_recibidos = 2,
       numerador = 1.15
 where analista_id = '00000000-0000-0000-0000-0000000000ee';

do $caso_c$
declare
  j_nuevo jsonb := crm.conversion_mensual_sin_cartera_fn('2026-08-01');
  j_viejo jsonb := crm.conversion_mensual_sin_cartera_fn_vieja('2026-08-01');
begin
  perform private.asegura(j_nuevo #> '{total,divisor}' is not null, 'C: guarda — total.divisor no existe');
  perform private.asegura((j_nuevo #>> '{total,divisor}')::int = (j_viejo #>> '{total,divisor}')::int + 5, 'C: total.divisor debe sumar los leads del ex-roster');
  perform private.asegura((j_nuevo #>> '{cobertura,divisor_aproximado}')::int = (j_viejo #>> '{cobertura,divisor_aproximado}')::int + 2, 'C: divisor_aproximado debe cubrir el divisor que ahora se cuenta');
  perform private.asegura((j_nuevo #>> '{total,cierres_referidos}')::int = (j_viejo #>> '{total,cierres_referidos}')::int + 1, 'C: cierres_referidos debe sumar el del ex-roster');
  perform private.asegura((j_nuevo #>> '{total,cierres_de_arrastre}')::int = (j_viejo #>> '{total,cierres_de_arrastre}')::int + 1, 'C: cierres_de_arrastre debe sumar el del ex-roster');
  perform private.asegura((j_nuevo #>> '{total,referidos_recibidos}')::int = (j_viejo #>> '{total,referidos_recibidos}')::int + 2, 'C: referidos_recibidos debe sumar los del ex-roster');
  perform private.asegura(j_nuevo #> '{cobertura,divisor_por_motivo,traspaso}' is not null, 'C: guarda — motivo traspaso no existe');
  perform private.asegura((j_nuevo #>> '{cobertura,divisor_por_motivo,traspaso}')::int = 5 and (j_nuevo #>> '{cobertura,divisor_por_motivo,normal}')::int = 10, 'C: divisor_por_motivo debe cubrir roster Y fuera de roster');
end $caso_c$;

-- ── CASO D · roster vacío, solo ex-roster: no revienta y el total lo dice ───
truncate private.roster_stub;

do $caso_d$
declare
  j_nuevo jsonb := crm.conversion_mensual_sin_cartera_fn('2026-08-01');
begin
  perform private.asegura(j_nuevo #> '{total,analistas}' is not null, 'D: guarda — total.analistas no existe');
  perform private.asegura((j_nuevo #>> '{total,analistas}')::int = 3, 'D: solo productores fuera de roster, total.analistas = 3');
  perform private.asegura(j_nuevo -> 'responsables' = '[]'::jsonb, 'D: sin roster no hay filas con identidad');
  perform private.asegura((j_nuevo #>> '{total,divisor}')::int = 15 and (j_nuevo #>> '{total,numerador}')::numeric = 3.30, 'D: el total es exactamente el agregado fuera de roster');
end $caso_d$;

-- ── CASO E · divisor total 0: conversion_pct NULL, jamás un número inventado ─
truncate private.nucleo_stub;
insert into private.nucleo_stub values
  ('00000000-0000-0000-0000-0000000000ee', 0, 0, '{}', 1, 0, 0, 1.0, null, '[]', 0, null);

do $caso_e$
declare
  j_nuevo jsonb := crm.conversion_mensual_sin_cartera_fn('2026-08-01');
begin
  perform private.asegura(j_nuevo -> 'total' ? 'conversion_pct', 'E: guarda — la clave conversion_pct debe existir');
  perform private.asegura(j_nuevo #> '{total,conversion_pct}' = 'null'::jsonb, 'E: con divisor 0 el pct es NULL, no un número');
  perform private.asegura((j_nuevo #>> '{total,numerador}')::numeric = 1.0, 'E: el numerador del ex-roster se declara aunque no haya divisor');
end $caso_e$;

select 'BANCO F2.6 ✅ casos A-E verdes' as resultado;

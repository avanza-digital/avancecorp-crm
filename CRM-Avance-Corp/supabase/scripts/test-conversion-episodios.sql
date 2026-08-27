-- Prueba de PARIDAD de F1 (conversion_episodios): el nucleo redefinido como
-- agrupacion sobre la tabla-base debe devolver EXACTAMENTE (byte a byte) lo
-- mismo que el nucleo vivo, sobre fixtures adversariales que pisan cada rama.
--
-- COMO CORRE: en un Postgres local desechable con STUBS del catalogo
-- (run-test-conversion-episodios-local.sh). NO corre contra produccion.
-- Antes de este script el runner ya creo: schemas, tablas stub, helpers
-- vivos (cierre_externo_anulado -> cierre_anulado stub, etiqueta_mes_es),
-- el nucleo VIVO bajo su nombre real y una copia _vieja, y aplico la
-- migracion F1 (que reemplaza el nombre real).
--
-- Este script: siembra fixtures -> compara vieja vs nueva en 6 llamadas
-- distintas -> paridad de CONJUNTO (except bidireccional) y de BYTES
-- (md5 de las filas ::text ordenadas). Cualquier diferencia = EXCEPTION.
--
-- El vigia (a) del plan — "toda funcion crm.* con conversion en el payload
-- consume el nucleo o la tabla-base" — corre en PRODUCCION via el guion de
-- aplicacion, no aqui: el banco no tiene el resto de funciones.

set search_path = '';

-- ---------------------------------------------------------------------------
-- 1. Fixtures adversariales (agosto 2026, zona America/Lima)
-- ---------------------------------------------------------------------------
create temp table v (k text primary key, id uuid not null default gen_random_uuid());
insert into v(k) values ('V1'),('V2'),('V3'),('V4'),('V5'),('C1'),('C2'),('C3');

create or replace function pg_temp.uid(p text) returns uuid
language sql stable as $$ select id from v where k = p $$;

create or replace function pg_temp.lead(n int) returns uuid
language sql immutable as
$$ select ('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;

-- LEADS / ASIGNACIONES ------------------------------------------------------
-- L1: V1, campania, agosto, cerrado agosto (normal)
insert into crm.lead_asignaciones (analista_id, lead_id, origen, motivo_apertura, aproximado, asignado_en, resultado, resultado_en, finalizado_en)
values (pg_temp.uid('V1'), pg_temp.lead(1), 'campania', 'nuevo', false, '2026-08-03 10:00-05', 'convertido', '2026-08-20 15:00-05', null);

-- L2: V1, referido de JULIO cerrado en agosto = arrastre + referido
insert into crm.lead_asignaciones values (default, pg_temp.uid('V1'), pg_temp.lead(2), 'referido', 'nuevo', false, '2026-07-10 09:00-05', 'convertido', '2026-08-05 11:00-05', null);

-- L3: V1, campania agosto, cerrado agosto pero ANULADO (via stub)
insert into crm.lead_asignaciones values (default, pg_temp.uid('V1'), pg_temp.lead(3), 'campania', 'reactivado', true, '2026-08-04 10:00-05', 'convertido', '2026-08-22 10:00-05', null);
insert into private.anulados_stub values (pg_temp.lead(3));

-- L4: DOS episodios para V1 en agosto (1o campania, 2o referido) y cerrado
--     una vez -> divisor 1 no-referido (origen del PRIMERO), cierre distinct 1
insert into crm.lead_asignaciones values
 (default, pg_temp.uid('V1'), pg_temp.lead(4), 'campania', 'nuevo', false, '2026-08-06 09:00-05', null, null, '2026-08-08 09:00-05'),
 (default, pg_temp.uid('V1'), pg_temp.lead(4), 'referido', 'reasignado', false, '2026-08-09 09:00-05', 'convertido', '2026-08-25 09:00-05', null);

-- L5: compartido V1 y V2 en agosto (cuenta en el divisor de ambos); V2 cierra
insert into crm.lead_asignaciones values
 (default, pg_temp.uid('V1'), pg_temp.lead(5), 'campania', 'nuevo', false, '2026-08-07 09:00-05', null, null, '2026-08-07 12:00-05'),
 (default, pg_temp.uid('V2'), pg_temp.lead(5), 'campania', 'reasignado', false, '2026-08-07 13:00-05', 'convertido', '2026-08-28 09:00-05', null);

-- L6: V2, cerrado DOS veces en agosto (episodios julio y agosto: dos
--     mes_origen distintos -> dos cubos de procedencia, distinct por cubo)
insert into crm.lead_asignaciones values
 (default, pg_temp.uid('V2'), pg_temp.lead(6), 'campania', 'nuevo', false, '2026-07-02 09:00-05', 'convertido', '2026-08-10 09:00-05', null),
 (default, pg_temp.uid('V2'), pg_temp.lead(6), 'campania', 'retomado', false, '2026-08-11 09:00-05', 'convertido', '2026-08-27 09:00-05', null);

-- L7: V5, cierre con resultado_en NULL -> cae en finalizado_en (agosto)
insert into crm.lead_asignaciones values (default, pg_temp.uid('V5'), pg_temp.lead(7), 'campania', 'nuevo', false, '2026-08-02 09:00-05', 'convertido', null, '2026-08-19 09:00-05');

-- L8: V5, cierre cuyo origen es de hace 14 meses -> cubo 'anteriores'
insert into crm.lead_asignaciones values (default, pg_temp.uid('V5'), pg_temp.lead(8), 'campania', 'nuevo', false, '2025-06-15 09:00-05', 'convertido', '2026-08-16 09:00-05', null);

-- L9: bordes de ventana: asignado exactamente en p_fin (SEPTIEMBRE, fuera)
--     y otro exactamente en p_ini (dentro)
insert into crm.lead_asignaciones values
 (default, pg_temp.uid('V2'), pg_temp.lead(9),  'campania', 'nuevo', false, '2026-09-01 00:00-05', null, null, null),
 (default, pg_temp.uid('V2'), pg_temp.lead(10), 'campania', 'nuevo', false, '2026-08-01 00:00-05', null, null, null);

-- L11: referido que SOLO cierra (recibido en junio, fuera de la ventana):
--     analista sin divisor con cierre -> camino del full outer join
insert into crm.lead_asignaciones values (default, pg_temp.uid('V4'), pg_temp.lead(11), 'referido', 'nuevo', false, '2026-06-20 09:00-05', 'convertido', '2026-08-14 09:00-05', null);

-- OPERACIONES DE CARTERA ----------------------------------------------------
-- C1: dos ops del MISMO cliente en agosto para vendedores DISTINTOS:
--     solo la primera (V3, dia 5) cuenta; la de V4 (dia 9) queda orden 2.
insert into crm.operaciones_cartera (cliente_id, vendedor_id, tipo, fecha_operacion, periodo, moneda, capital_renovado, capital_adicional, elegible_conversion, desglose_completo, fuente, creado_por, creado_en)
values
 (pg_temp.uid('C1'), pg_temp.uid('V3'), 'renovacion', '2026-08-05', '2026-08-01', 'PEN', 1000, 0, true,  true, 'flujo_cartera', pg_temp.uid('V3'), '2026-08-05 10:00-05'),
 (pg_temp.uid('C1'), pg_temp.uid('V4'), 'renovacion', '2026-08-09', '2026-08-01', 'PEN', 2000, 0, true,  true, 'flujo_cartera', pg_temp.uid('V4'), '2026-08-09 10:00-05');

-- C2: op1 de V5 (dia 1) y op2 de V3 (dia 2): con visibles=[V1,V3] la orden 1
--     es de V5 (invisible) -> V3 NO cuenta (el orden se calcula ANTES del filtro)
insert into crm.operaciones_cartera (cliente_id, vendedor_id, tipo, fecha_operacion, periodo, moneda, capital_renovado, capital_adicional, elegible_conversion, desglose_completo, fuente, creado_por, creado_en)
values
 (pg_temp.uid('C2'), pg_temp.uid('V5'), 'renovacion', '2026-08-01', '2026-08-01', 'USD', 500,  0, true, true, 'flujo_cartera', pg_temp.uid('V5'), '2026-08-01 10:00-05'),
 (pg_temp.uid('C2'), pg_temp.uid('V3'), 'upgrade',    '2026-08-02', '2026-08-01', 'USD', null, null, true, true, 'flujo_cartera', pg_temp.uid('V3'), '2026-08-02 10:00-05');

-- C3: op NO elegible (no cuenta) + V3 sin leads: vendedor solo-cartera
insert into crm.operaciones_cartera (cliente_id, vendedor_id, tipo, fecha_operacion, periodo, moneda, capital_renovado, capital_adicional, elegible_conversion, desglose_completo, fuente, creado_por, creado_en)
values
 (pg_temp.uid('C3'), pg_temp.uid('V3'), 'upgrade', '2026-08-12', '2026-08-01', 'PEN', null, null, false, true, 'flujo_cartera', pg_temp.uid('V3'), '2026-08-12 10:00-05');

-- ---------------------------------------------------------------------------
-- 2. Paridad: 6 llamadas que pisan todas las ramas
-- ---------------------------------------------------------------------------
create or replace function pg_temp.paridad(
  p_caso text,
  p_ini timestamptz, p_fin timestamptz,
  p_global boolean, p_visibles uuid[], p_factor numeric
) returns void language plpgsql as $$
declare
  v_solo_vieja int; v_solo_nueva int;
  v_md5_vieja text; v_md5_nueva text;
  v_filas int;
begin
  select count(*) into v_solo_vieja from (
    select * from private.conversion_mensual_por_vendedor_vieja(p_ini,p_fin,p_global,p_visibles,p_factor)
    except
    select * from private.conversion_mensual_por_vendedor(p_ini,p_fin,p_global,p_visibles,p_factor)) x;
  select count(*) into v_solo_nueva from (
    select * from private.conversion_mensual_por_vendedor(p_ini,p_fin,p_global,p_visibles,p_factor)
    except
    select * from private.conversion_mensual_por_vendedor_vieja(p_ini,p_fin,p_global,p_visibles,p_factor)) x;
  select md5(coalesce(string_agg(t::text, E'\n' order by t::text), '<vacio>')), count(*)
    into v_md5_vieja, v_filas
    from private.conversion_mensual_por_vendedor_vieja(p_ini,p_fin,p_global,p_visibles,p_factor) t;
  select md5(coalesce(string_agg(t::text, E'\n' order by t::text), '<vacio>'))
    into v_md5_nueva
    from private.conversion_mensual_por_vendedor(p_ini,p_fin,p_global,p_visibles,p_factor) t;

  if v_solo_vieja <> 0 or v_solo_nueva <> 0 or v_md5_vieja <> v_md5_nueva then
    raise exception 'PARIDAD ROTA [%]: solo_vieja=% solo_nueva=% md5_vieja=% md5_nueva=%',
      p_caso, v_solo_vieja, v_solo_nueva, v_md5_vieja, v_md5_nueva;
  end if;
  raise notice 'PARIDAD OK [%] · % filas · md5 %', p_caso, v_filas, v_md5_vieja;
end $$;

do $$
begin
  perform pg_temp.paridad('agosto global f=0.15',
    '2026-08-01 00:00-05', '2026-09-01 00:00-05', true, null, 0.15);
  perform pg_temp.paridad('agosto global f=1',
    '2026-08-01 00:00-05', '2026-09-01 00:00-05', true, null, 1.0);
  perform pg_temp.paridad('agosto global f=0',
    '2026-08-01 00:00-05', '2026-09-01 00:00-05', true, null, 0);
  perform pg_temp.paridad('agosto visibles V1,V3 (orden de cartera antes del filtro)',
    '2026-08-01 00:00-05', '2026-09-01 00:00-05', false,
    array[(select id from v where k='V1'), (select id from v where k='V3')], 0.15);
  perform pg_temp.paridad('julio global (ventana con otra cartera, arrastres cero)',
    '2026-07-01 00:00-05', '2026-08-01 00:00-05', true, null, 0.15);
  perform pg_temp.paridad('ventana vacia (2026-01)',
    '2026-01-01 00:00-05', '2026-02-01 00:00-05', true, null, 0.15);
end $$;

-- ---------------------------------------------------------------------------
-- 3. Oraculo de contenido: la paridad no puede ser vacua. La foto de agosto
--    global debe tener EXACTAMENTE estos numeros (calculados a mano de los
--    fixtures). Si un mutante del fixture los cambiara sin romper la paridad,
--    este oraculo lo caza.
-- ---------------------------------------------------------------------------
do $$
declare r record; v_err text := '';
begin
  -- V1: divisor 3 (L1, L4 primer-origen campania, L5; L3 aproximado tambien
  --     cuenta: 4? NO — L3 es campania+aproximado: divisor 4) →
  --     divisor: L1, L3, L4, L5 = 4 (L2 es referido de julio: ni divisor)
  --     cierres_no_referidos: L1 (L3 anulado fuera, L4 cerro como referido) = 1
  --     cierres_referidos: L2 + L4 = 2 · arrastre: L2 (julio) = 1
  --     referidos_recibidos: 0 (L2 llego en julio; L4 primer episodio campania)
  select * into r from private.conversion_mensual_por_vendedor(
    '2026-08-01 00:00-05','2026-09-01 00:00-05',true,null,0.15)
   where analista_id = (select id from v where k='V1');
  if r.divisor <> 4 then v_err := v_err || format(' V1.divisor=%s(≠4)', r.divisor); end if;
  if r.divisor_aproximado <> 1 then v_err := v_err || format(' V1.aprox=%s(≠1)', r.divisor_aproximado); end if;
  if r.cierres_no_referidos <> 1 then v_err := v_err || format(' V1.cnr=%s(≠1)', r.cierres_no_referidos); end if;
  if r.cierres_referidos <> 2 then v_err := v_err || format(' V1.cr=%s(≠2)', r.cierres_referidos); end if;
  if r.cierres_de_arrastre <> 1 then v_err := v_err || format(' V1.arr=%s(≠1)', r.cierres_de_arrastre); end if;
  if r.numerador <> 1.30 then v_err := v_err || format(' V1.num=%s(≠1.30)', r.numerador); end if;

  -- V2: divisor 3 (L5, L6 episodio agosto... OJO L6 agosto es 'retomado'
  --     pero su PRIMER episodio en ventana es el de agosto -> campania?
  --     L6 tiene episodios 2026-07 (fuera) y 2026-08 (dentro): divisor por el
  --     de agosto; L9 fuera (p_fin exacto), L10 dentro. => L5, L6, L10 = 3
  --     cierres: L5 + L6 (distinct, dos episodios) = 2 no referidos
  --     arrastre: episodio julio de L6 = 1
  select * into r from private.conversion_mensual_por_vendedor(
    '2026-08-01 00:00-05','2026-09-01 00:00-05',true,null,0.15)
   where analista_id = (select id from v where k='V2');
  if r.divisor <> 3 then v_err := v_err || format(' V2.divisor=%s(≠3)', r.divisor); end if;
  if r.cierres_no_referidos <> 2 then v_err := v_err || format(' V2.cnr=%s(≠2)', r.cierres_no_referidos); end if;
  if r.cierres_de_arrastre <> 1 then v_err := v_err || format(' V2.arr=%s(≠1)', r.cierres_de_arrastre); end if;

  -- V3: solo cartera: C1 (orden 1) cuenta; C2 (orden 2) no; C3 no elegible no.
  --     divisor 0, numerador 1, conversion NULL.
  select * into r from private.conversion_mensual_por_vendedor(
    '2026-08-01 00:00-05','2026-09-01 00:00-05',true,null,0.15)
   where analista_id = (select id from v where k='V3');
  if r.divisor <> 0 or r.numerador <> 1 or r.conversion_pct is not null then
    v_err := v_err || format(' V3=(div %s,num %s,pct %s)(≠0,1,NULL)', r.divisor, r.numerador, r.conversion_pct);
  end if;

  -- V4: cierre referido sin divisor (L11) y su op de C1 quedo orden 2:
  --     divisor 0 · cierres_referidos 1 · numerador 0.15 · arrastre 1
  select * into r from private.conversion_mensual_por_vendedor(
    '2026-08-01 00:00-05','2026-09-01 00:00-05',true,null,0.15)
   where analista_id = (select id from v where k='V4');
  if r.divisor <> 0 or r.cierres_referidos <> 1 or r.numerador <> 0.15 then
    v_err := v_err || format(' V4=(div %s,cr %s,num %s)(≠0,1,0.15)', r.divisor, r.cierres_referidos, r.numerador);
  end if;

  -- V5: divisor 1 (L7; L8 es de 2025) · cierres 2 (L7 fallback finalizado_en,
  --     L8 cubo anteriores) · op C2 orden 1 => numerador 3 · pct 300
  select * into r from private.conversion_mensual_por_vendedor(
    '2026-08-01 00:00-05','2026-09-01 00:00-05',true,null,0.15)
   where analista_id = (select id from v where k='V5');
  if r.divisor <> 1 or r.cierres_no_referidos <> 2 or r.numerador <> 3 or r.conversion_pct <> 300.00 then
    v_err := v_err || format(' V5=(div %s,cnr %s,num %s,pct %s)(≠1,2,3,300)', r.divisor, r.cierres_no_referidos, r.numerador, r.conversion_pct);
  end if;
  if (select count(*) from jsonb_array_elements(r.procedencia) e
       where e.value->>'mes_nombre' = 'anteriores') <> 1 then
    v_err := v_err || ' V5.procedencia sin cubo anteriores';
  end if;

  if v_err <> '' then
    raise exception 'ORACULO ROTO:%', v_err;
  end if;
  raise notice 'ORACULO OK: V1..V5 con los numeros calculados a mano';
end $$;

-- ---------------------------------------------------------------------------
-- 4. Contrato propio de la tabla-base (lo nuevo que F2 usara)
-- ---------------------------------------------------------------------------
do $$
declare v_n int;
begin
  -- p_periodo NULL: la pierna de cartera se OMITE (rangos libres)
  select count(*) into v_n from private.conversion_episodios(
    '2026-08-01 00:00-05','2026-09-01 00:00-05', null, true, null, 0.15) e
   where e.tipo = 'operacion';
  if v_n <> 0 then raise exception 'p_periodo NULL debe omitir operaciones (hay %)', v_n; end if;

  -- los cierres anulados VIAJAN marcados con aporte 0
  select count(*) into v_n from private.conversion_episodios(
    '2026-08-01 00:00-05','2026-09-01 00:00-05', '2026-08-01', true, null, 0.15) e
   where e.tipo = 'cierre' and e.anulado and e.aporte_numerador = 0;
  if v_n <> 1 then raise exception 'esperaba 1 cierre anulado marcado, hay %', v_n; end if;

  -- referidos ya ponderados en aporte_numerador
  select count(*) into v_n from private.conversion_episodios(
    '2026-08-01 00:00-05','2026-09-01 00:00-05', '2026-08-01', true, null, 0.15) e
   where e.tipo = 'cierre' and e.fue_referido and not e.anulado
     and e.aporte_numerador = 0.15;
  if v_n <> 3 then raise exception 'esperaba 3 cierres referidos ponderados 0.15, hay %', v_n; end if;

  raise notice 'CONTRATO EPISODIOS OK (p_periodo NULL, anulados marcados, ponderacion)';
end $$;

select 'TEST-CONVERSION-EPISODIOS: TODO VERDE' as resultado;

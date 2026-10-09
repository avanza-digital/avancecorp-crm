#!/usr/bin/env python3
"""Genera oraculo-despues.sql (SOLO LECTURA) a partir de la medición de producción (medir-categoria.json, R1–R4).

Las cifras esperadas (capital de septiembre por moneda y por analista DESPUÉS de pasar los 12 a 'upgrade', a quién cuenta
cada operación en la conversión y cómo estaba cada PDF) salen de la medición y se escriben en el SQL: así nadie las
transcribe a mano. Con la medición del banco sale la variante del banco (para ensayar el propio oráculo).

Uso:  python3 generar_oraculo.py <medir-categoria.json> [salida.sql]     (por defecto: oraculo-despues.sql junto a este script)
"""
import json
import pathlib
import sys

AQUI = pathlib.Path(__file__).resolve().parent

PLANTILLA = r"""-- oraculo-despues.sql — Categoría de los 12 contratos de septiembre. SOLO LECTURA. Se corre DESPUÉS de 2-REAL.sql.
-- GENERADO por generar_oraculo.py desde la medición de producción (medir-categoria.json, __MEDIDO__ Lima): no editar a mano.
--
-- QUÉ COMPRUEBA (contra lo medido ANTES de corregir)
--   1. los 12: en 'upgrade', con su operación 'upgrade', la corrección de la puerta como última fila de motivo y el PDF sin
--      trabajos nuevos (un solo trabajo, revisión 1; un sellado sigue igual, un pendiente puede haberse sellado después).
--   2. capital de septiembre por moneda: el total no cambia; «nuevo» y «upgrade» quedan en lo que la medición simuló.
--   3. por analista y moneda (Metas): Δnuevo = −Δupgrade = lo de los 12 de ese analista; y las cifras simuladas.
--   4. conversión: cada operación de los 12 sigue sumando (o no) y a la MISMA persona que antes.
--   5. deriva: contratos de septiembre creados o cambiados DESPUÉS de la medición (explican una diferencia en 2 o 3).
--   6. (informativo) capital de septiembre por ORIGEN (Ranking): los 12 cuentan ahora como «cartera».
-- Veredicto PASS si 1–4 cuadran; si no, REVISAR (mirar la deriva antes de concluir nada). No sellar septiembre sin PASS.
--
-- CÓMO LO CORRE MIGUEL (con `!`, desde CRM-Avance-Corp):
--   supabase db query --linked -f supabase/scripts/categoria-por-operacion/oraculo-despues.sql
begin transaction read only;
set local statement_timeout = '120s';
set local lock_timeout = '5s';

do $oraculo$
declare
  -- ESPERADO-INICIO (generado; ver la cabecera)
  c_esperado constant jsonb := $esperado$__ESPERADO__$esperado$;
  -- ESPERADO-FIN
  c_motivo constant text := 'Upgrade registrado como nuevo: la operación de cartera manda (decisión de Miguel 08/10/2026, auditoría de Facturación)';
  c_periodo constant date := date '2026-09-01';
  c_ini constant timestamptz := timestamp '2026-09-01 00:00:00' at time zone 'America/Lima';
  c_fin constant timestamptz := timestamp '2026-10-01 00:00:00' at time zone 'America/Lima';
  c_medido_en constant timestamptz := (c_esperado ->> 'medido_en_lima')::timestamp at time zone 'America/Lima';
  v_numeros text[] := array(select jsonb_array_elements_text(c_esperado -> 'numeros'));
  v_periodo_meta uuid;
  v_res jsonb := '{}'::jsonb;
  v_tmp jsonb;
  v_ok1 boolean; v_ok2 boolean; v_ok3 boolean; v_ok4 boolean;
begin
  select mp.id into v_periodo_meta from crm.meta_periodos mp where mp.periodo = c_periodo order by mp.revision desc limit 1;

  -- 1. Los 12.
  select jsonb_agg(jsonb_build_object(
           'numero', c.numero_contrato,
           'ok', c.categoria = 'upgrade' and o.tipo = 'upgrade' and m.filas = 1
                 and j.trabajos = 1 and split_part(j.ultimo, '/', 2) = '1'
                 and (j.ultimo = (pe ->> 'ultimo') or (pe ->> 'ultimo') = 'pendiente/1')
                 and j.archivos >= (pe ->> 'archivos')::int,
           'categoria', c.categoria, 'operacion', o.tipo, 'ultima_fila_es_la_correccion', m.filas = 1,
           'pdf', jsonb_build_object('ultimo', j.ultimo, 'trabajos', j.trabajos, 'archivos', j.archivos),
           'pdf_esperado', pe) order by c.numero_contrato),
         bool_and(c.categoria = 'upgrade' and o.tipo = 'upgrade' and m.filas = 1
                  and j.trabajos = 1 and split_part(j.ultimo, '/', 2) = '1'
                  and (j.ultimo = (pe ->> 'ultimo') or (pe ->> 'ultimo') = 'pendiente/1')
                  and j.archivos >= (pe ->> 'archivos')::int)
           and count(*) = 12
    into v_tmp, v_ok1
    from public.contratos c
    left join crm.operaciones_cartera o on o.contrato_nuevo_id = c.id
    cross join lateral (select coalesce((select (a.data_despues ->> 'motivo' = c_motivo and a.data_despues ->> 'categoria' = 'upgrade'
                                                 and a.data_despues ->> 'via' = 'puerta')::int
                                          from public.audit_log a
                                         where a.tabla = 'contratos.categoria' and a.fila_id = c.id::text
                                         order by a.ts desc, a.id desc limit 1), 0) as filas) m
    cross join lateral (select (select x.estado || '/' || x.revision from private.contrato_pdf_jobs x
                                 where x.contrato_id = c.id order by x.revision desc limit 1) as ultimo,
                               (select count(*) from private.contrato_pdf_jobs x where x.contrato_id = c.id) as trabajos,
                               (select count(*) from private.contrato_pdfs x where x.contrato_id = c.id) as archivos) j
    cross join lateral (select c_esperado -> 'pdf' -> c.numero_contrato as pe) e
   where c.numero_contrato = any(v_numeros);
  v_res := v_res || jsonb_build_object('1_los_12', jsonb_build_object('ok', coalesce(v_ok1, false), 'detalle', v_tmp));

  -- 2. Capital de septiembre por moneda.
  select jsonb_object_agg(t.moneda, jsonb_build_object(
           'ok', t.total = (c_esperado -> 'capital' -> t.moneda ->> 'total')::numeric
                 and t.nuevo = (c_esperado -> 'capital' -> t.moneda ->> 'nuevo')::numeric
                 and t.up = (c_esperado -> 'capital' -> t.moneda ->> 'upgrade')::numeric,
           'total', t.total, 'nuevo', t.nuevo, 'upgrade', t.up, 'esperado', c_esperado -> 'capital' -> t.moneda)),
         bool_and(t.total = (c_esperado -> 'capital' -> t.moneda ->> 'total')::numeric
                  and t.nuevo = (c_esperado -> 'capital' -> t.moneda ->> 'nuevo')::numeric
                  and t.up = (c_esperado -> 'capital' -> t.moneda ->> 'upgrade')::numeric)
    into v_tmp, v_ok2
    from (select e.moneda, sum(e.monto) as total,
                 coalesce(sum(e.monto) filter (where e.tipo = 'contrato_nuevo'), 0) as nuevo,
                 coalesce(sum(e.monto) filter (where e.tipo = 'contrato_upgrade'), 0) as up
            from private.capital_episodios(c_ini, c_fin, true, '{}'::uuid[]) e
           where e.medida = 'stock' group by e.moneda) t;
  v_res := v_res || jsonb_build_object('2_capital_por_moneda', jsonb_build_object('ok', coalesce(v_ok2, false), 'detalle', v_tmp));

  -- 3. Por analista y moneda (núcleo de Metas): Δnuevo = −Δupgrade = los 12 de ese analista, y las cifras simuladas.
  with esperado as (
    select x ->> 'analista' as analista, x ->> 'moneda' as moneda,
           (x ->> 'nuevo_antes')::numeric as nuevo_antes, (x ->> 'nuevo_despues')::numeric as nuevo_despues,
           (x ->> 'upgrade_antes')::numeric as upgrade_antes, (x ->> 'upgrade_despues')::numeric as upgrade_despues,
           (x ->> 'contratos_nuevo_despues')::int as cn_despues, (x ->> 'contratos_upgrade_despues')::int as cu_despues
      from jsonb_array_elements(c_esperado -> 'por_analista') x
  ), hoy as (
    select pf.nombre_completo as analista, r.categoria, r.moneda, r.capital_real, r.contratos_real
      from private.produccion_mes_por_vendedor(c_ini, c_fin, v_periodo_meta) r
      left join public.perfiles pf on pf.id = r.vendedor_id
  ), los12 as (
    select pf.nombre_completo as analista, c.moneda, sum(c.capital) as capital
      from public.contratos c left join public.perfiles pf on pf.id = c.analista_cierre_id
     where c.numero_contrato = any(v_numeros) group by 1, 2
  ), filas as (
    select e.analista, e.moneda,
           coalesce(hn.capital_real, 0) as nuevo_hoy, coalesce(hu.capital_real, 0) as upgrade_hoy,
           coalesce(hn.contratos_real, 0) as cn_hoy, coalesce(hu.contratos_real, 0) as cu_hoy,
           e.nuevo_antes - coalesce(hn.capital_real, 0) as sale_de_nuevo,
           coalesce(hu.capital_real, 0) - e.upgrade_antes as entra_en_upgrade,
           coalesce(l.capital, 0) as los_12,
           e.nuevo_despues, e.upgrade_despues, e.cn_despues, e.cu_despues
      from esperado e
      left join hoy hn on hn.analista = e.analista and hn.moneda = e.moneda and hn.categoria = 'nuevo'
      left join hoy hu on hu.analista = e.analista and hu.moneda = e.moneda and hu.categoria = 'upgrade'
      left join los12 l on l.analista = e.analista and l.moneda = e.moneda
  )
  select jsonb_agg(jsonb_build_object(
           'analista', f.analista, 'moneda', f.moneda,
           'ok', f.sale_de_nuevo = f.los_12 and f.entra_en_upgrade = f.los_12
                 and f.nuevo_hoy = f.nuevo_despues and f.upgrade_hoy = f.upgrade_despues
                 and f.cn_hoy = f.cn_despues and f.cu_hoy = f.cu_despues,
           'sale_de_nuevo', f.sale_de_nuevo, 'entra_en_upgrade', f.entra_en_upgrade, 'los_12', f.los_12,
           'nuevo_hoy', f.nuevo_hoy, 'nuevo_esperado', f.nuevo_despues,
           'upgrade_hoy', f.upgrade_hoy, 'upgrade_esperado', f.upgrade_despues) order by f.moneda, f.analista),
         bool_and(f.sale_de_nuevo = f.los_12 and f.entra_en_upgrade = f.los_12
                  and f.nuevo_hoy = f.nuevo_despues and f.upgrade_hoy = f.upgrade_despues
                  and f.cn_hoy = f.cn_despues and f.cu_hoy = f.cu_despues)
    into v_tmp, v_ok3
    from filas f;
  v_res := v_res || jsonb_build_object('3_por_analista', jsonb_build_object('ok', coalesce(v_ok3, false), 'detalle', v_tmp));

  -- 4. Conversión: la operación de cada uno sigue sumando (o no) y a la misma persona.
  with ops as (
    select o.id, row_number() over (partition by o.cliente_id, o.periodo order by o.fecha_operacion, o.creado_en, o.id) as orden
      from crm.operaciones_cartera o where o.elegible_conversion and o.periodo = c_periodo
  ), filas as (
    select c.numero_contrato, coalesce(oo.orden = 1, false) as suma, p.nombre_completo as cuenta_a,
           c_esperado -> 'conversion' -> c.numero_contrato as esperado
      from crm.operaciones_cartera o
      join public.contratos c on c.id = o.contrato_nuevo_id
      left join ops oo on oo.id = o.id
      left join public.perfiles p on p.id = coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id)
     where c.numero_contrato = any(v_numeros)
  )
  select jsonb_agg(jsonb_build_object('numero', f.numero_contrato,
           'ok', f.suma = (f.esperado ->> 'suma')::boolean and f.cuenta_a is not distinct from (f.esperado ->> 'cuenta_a'),
           'suma', f.suma, 'cuenta_a', f.cuenta_a, 'esperado', f.esperado) order by f.numero_contrato),
         bool_and(f.suma = (f.esperado ->> 'suma')::boolean and f.cuenta_a is not distinct from (f.esperado ->> 'cuenta_a'))
           and count(*) = 12
    into v_tmp, v_ok4
    from filas f;
  v_res := v_res || jsonb_build_object('4_conversion', jsonb_build_object('ok', coalesce(v_ok4, false), 'detalle', v_tmp));

  -- 5. Deriva: lo que se movió en septiembre DESPUÉS de la medición, aparte de la corrección de los 12.
  select coalesce(jsonb_agg(jsonb_build_object('numero', c.numero_contrato, 'operacion', a.operacion,
                                               'cuando_lima', (a.ts at time zone 'America/Lima')::text) order by a.ts), '[]'::jsonb)
    into v_tmp
    from public.audit_log a
    join public.contratos c on c.id::text = a.fila_id
   where a.tabla = 'contratos' and a.ts > c_medido_en
     and c.fecha_cierre_comercial >= c_periodo and c.fecha_cierre_comercial < date '2026-10-01'
     and not (c.numero_contrato = any(v_numeros) and a.operacion = 'UPDATE'
              and (a.data_antes ->> 'categoria') = 'nuevo' and (a.data_despues ->> 'categoria') = 'upgrade');
  v_res := v_res || jsonb_build_object('5_deriva_desde_la_medicion', v_tmp,
    'septiembre_sellado', exists (select 1 from crm.periodos_cerrados pc where pc.periodo = c_periodo));

  -- 6. Informativo: capital de septiembre por origen y moneda (Ranking por origen).
  select coalesce(jsonb_object_agg(t.origen || '|' || t.moneda, t.capital), '{}') into v_tmp
    from (select r.origen, r.moneda, sum(r.capital) as capital
            from private.ranking_capital_origen_filas(c_ini, c_fin, v_periodo_meta) r group by 1, 2) t;
  v_res := v_res || jsonb_build_object('6_ranking_origen_septiembre', v_tmp);

  v_res := jsonb_build_object('veredicto',
             case when coalesce(v_ok1, false) and coalesce(v_ok2, false) and coalesce(v_ok3, false) and coalesce(v_ok4, false)
                  then 'PASS' else 'REVISAR' end,
             'medido_en_lima', c_esperado ->> 'medido_en_lima',
             'generado_en_lima', (now() at time zone 'America/Lima')::text) || v_res;
  perform set_config('categoria.oraculo', v_res::text, true);
end
$oraculo$;

select current_setting('categoria.oraculo', true)::jsonb as resultado;

rollback;
"""


def esperado_desde(medicion):
    r = medicion["rows"][0]["resultado"] if "rows" in medicion else medicion
    numeros = [x["numero"] for x in r["R1_contratos"]]
    assert len(numeros) == 12, f"R1 trae {len(numeros)} contratos, no 12"
    capital = {m: {"total": v["total_stock_no_cambia"], "nuevo": v["contrato_nuevo_despues"],
                   "upgrade": v["contrato_upgrade_despues"]} for m, v in r["R3_capital_sep"].items()}
    por_analista = [{
        "analista": x["analista"], "moneda": x["moneda"],
        "nuevo_antes": x["nuevo"]["antes"], "nuevo_despues": x["nuevo"]["despues"],
        "upgrade_antes": x["upgrade"]["antes"], "upgrade_despues": x["upgrade"]["despues"],
        "contratos_nuevo_despues": x["nuevo"]["contratos_despues"],
        "contratos_upgrade_despues": x["upgrade"]["contratos_despues"]} for x in r["R2_metas_sep"]["por_analista"]]
    assert all(x["cuadra"] for x in r["R2_metas_sep"]["por_analista"]), "R2 tiene filas que no cuadran"
    conversion = {x["numero"]: {"suma": x["suma_en_numerador"], "cuenta_a": x["despues_contaria_a"]}
                  for x in r["R4_conversion"]["filas"]}
    pdf = {x["numero"]: {"ultimo": f'{x["pdf"]["ultimo_trabajo"]["estado"]}/{x["pdf"]["ultimo_trabajo"]["revision"]}',
                         "archivos": x["pdf"]["archivos"]} for x in r["R1_contratos"]}
    medido = r["R0_resumen"]["generado_en_lima"][:19]
    return medido, {"medido_en_lima": medido, "numeros": sorted(numeros), "capital": capital,
                    "por_analista": por_analista, "conversion": conversion, "pdf": pdf}


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    medicion = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
    salida = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else AQUI / "oraculo-despues.sql"
    medido, esperado = esperado_desde(medicion)
    texto = json.dumps(esperado, ensure_ascii=False, indent=1)
    assert "$esperado$" not in texto
    sql = PLANTILLA.replace("__MEDIDO__", medido).replace("__ESPERADO__", texto)
    salida.write_text(sql, encoding="utf-8")
    print(f"{salida} · medido {medido} · {len(esperado['por_analista'])} filas por analista")


if __name__ == "__main__":
    main()

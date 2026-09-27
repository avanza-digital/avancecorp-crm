#!/usr/bin/env python3
"""Genera banco/backfill-B-banco.sql a partir del script REAL de producción.
Solo cambia la lista de contratos (los sintéticos del banco) y los recuentos esperados;
el cuerpo es el mismo byte a byte. Uso: python3 banco/generar-B-banco.py"""
import pathlib, re, sys
aqui = pathlib.Path(__file__).resolve().parent
src = (aqui.parent / "backfill-B-setiembre-2026.sql").read_text()
ini = src.index("v_ids constant uuid[] := array[")
fin = src.index("]::uuid[];", ini)
ids = ("v_ids constant uuid[] := array[\n"
       "    'e0000000-0000-4000-8000-00000000000d', -- BANCO-B1-SEP (cliente con contrato de julio → elegible)\n"
       "    'e0000000-0000-4000-8000-00000000000f'  -- BANCO-B2-2 (mismo mes que su 1.er contrato → no elegible)\n  ")
out = src[:ini] + ids + src[fin:]
reemplazos = [("v_n <> 11", "v_n <> 2"),
              ("Se esperaban 11 contratos", "Se esperaban 2 contratos"),
              ("Solo % de 11 contratos", "Solo % de 2 contratos"),
              ("v_no_elegible constant uuid := 'baeefea1-b97b-4a57-840a-0d2165c360f1'; -- 001408",
               "v_no_elegible constant uuid := 'e0000000-0000-4000-8000-00000000000f'; -- BANCO-B2-2"),
              ("tenía que ser la de 001408", "tenía que ser la de BANCO-B2-2"),
              ("11 operaciones upgrade, 10 elegibles", "2 operaciones upgrade, 1 elegible")]
for a, b in reemplazos:
    if a not in out:
        sys.exit(f"No encontré «{a}» en el script de producción: revisar el generador")
    out = out.replace(a, b)
out = "-- GENERADO por banco/generar-B-banco.py desde backfill-B-setiembre-2026.sql. NO EDITAR A MANO.\n" + out
(aqui / "backfill-B-banco.sql").write_text(out)
print("backfill-B-banco.sql generado")

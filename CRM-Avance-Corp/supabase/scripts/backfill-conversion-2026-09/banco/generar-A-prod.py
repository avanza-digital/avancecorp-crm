#!/usr/bin/env python3
"""Genera el script de PRODUCCIÓN del backfill tipo A desde el molde ensayado en el banco.

Cambia solo tres cosas del molde (backfill-A-banco.sql); el resto del cuerpo queda byte a byte:
  1. la cabecera;
  2. el modo, fijado en 'transitorio' (el modo 'conservar' era solo para el banco);
  3. la lista de casos, que sale de la lista de Miguel (origenes-A.csv) y de los ids leídos de
     prod (ids-contratos-A.json). Además añade un recuento final contra el tamaño de la lista.

⚠️ La lista lleva un teléfono: entrada y salida viven en _DEV_NO_SUBIR/ (gitignored), nunca en
el repositorio. Uso: python3 banco/generar-A-prod.py
"""
import csv, json, pathlib, re, sys

aqui = pathlib.Path(__file__).resolve().parent
raiz = aqui.parents[4]                                   # AVANCECORP-desktop
privado = raiz / "_DEV_NO_SUBIR" / "backfill-conversion-2026-09"
molde = (aqui.parent / "backfill-A-banco.sql").read_text()
ids = json.loads((privado / "ids-contratos-A.json").read_text())
ORIGENES = {"referido", "landing", "formulario", "oficina"}
# El conjunto APROBADO por Miguel el 23/09 (paso a paso): exactamente estos 32 contratos.
APROBADOS = {f"2026-01-{n}" for n in (
    "001196", "001218", "001356", "001360", "001363", "001364", "001365", "001370", "001372", "001373",
    "001374", "001377", "001378", "001382", "001385", "001386", "001392", "001393", "001394", "001395",
    "001396", "001397", "001398", "001402", "001412", "001413", "001414", "001416", "001417", "001420",
    "001430", "001432")}
assert len(APROBADOS) == 32
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
NUMERO = re.compile(r"2026-01-\d{6}")

with open(privado / "origenes-A.csv", newline="") as f:
    filas = list(csv.DictReader(f))
casos = []
for fila in filas:
    num, origen = fila["contrato"].strip(), fila["origen"].strip()
    tel = (fila.get("telefono_para_el_lead") or "").strip()
    if origen not in ORIGENES:
        sys.exit(f"{num}: origen «{origen}» no admitido")
    if not NUMERO.fullmatch(num):
        sys.exit(f"{num!r}: número de contrato con forma inesperada")
    if num not in ids or not UUID.fullmatch(ids[num]):
        sys.exit(f"{num}: sin id válido leído de prod")
    if tel and not re.fullmatch(r"9\d{8}", tel):
        sys.exit(f"{num}: teléfono con forma inesperada")
    casos.append((num, ids[num], origen, tel))
nums = [c[0] for c in casos]
if len(set(nums)) != len(nums):
    sys.exit("hay contratos repetidos en la lista")
if len({c[1] for c in casos}) != len(casos):
    sys.exit("dos contratos de la lista apuntan al mismo id")
if set(nums) != APROBADOS:
    sys.exit(f"la lista no es el conjunto aprobado: faltan {sorted(APROBADOS - set(nums))}, sobran {sorted(set(nums) - APROBADOS)}")
n = len(casos)
assert n == 32

# 1. Cabecera.
ini = molde.index("do $a$")
cabecera = (
    "-- Backfill único · tipo A · setiembre 2026 · PRODUCCIÓN.\n"
    "-- GENERADO por banco/generar-A-prod.py desde backfill-A-banco.sql (molde ensayado en el banco).\n"
    "-- Solo cambian la cabecera, el modo (fijo en transitorio) y la lista de casos. NO EDITAR A MANO.\n"
    f"-- {n} clientes nuevos: lead a nombre de su analista, convertido por crm.convertir_lead como ADMIN.\n"
    "-- ⛔ NO EJECUTAR sin OK explícito de Miguel sobre ESTE texto. ⚠️ Lleva un teléfono: no subir.\n")
cuerpo = molde[ini:]

# 2. Modo fijo.
modo_banco = "  v_modo text := coalesce(nullif(current_setting('ensayo.modo', true), ''), 'transitorio');"
if modo_banco not in cuerpo:
    sys.exit("no encontré la línea del modo en el molde")
cuerpo = cuerpo.replace(modo_banco, "  v_modo constant text := 'transitorio';")

# 3. Lista de casos.
a = cuerpo.index("  for v_caso in select * from (values\n")
b = cuerpo.index("    ) x(contrato_id, numero, origen, telefono) loop")
lineas = ["  for v_caso in select * from (values",
          "      -- (contrato, su número, origen que dio Miguel, teléfono SOLO si la ficha del cliente no lo tiene)"]
for i, (num, uid, origen, tel) in enumerate(sorted(casos)):
    tel_sql = f"'{tel}'" if tel else "null"
    if i == 0:
        tel_sql += "::text"
    coma = "," if i < n - 1 else " "
    lineas.append(f"      ('{uid}'::uuid, '{num}', '{origen}', {tel_sql}){coma}")
cuerpo = cuerpo[:a] + "\n".join(lineas) + "\n" + cuerpo[b:]

# Recuento final: cada caso o se convierte o se salta (ya tenía lead); si no, algo se perdió.
aviso = "  raise notice 'Backfill A (%): % convertidos, % ya tenían lead', v_modo, v_hechos, v_saltados;"
if aviso not in cuerpo:
    sys.exit("no encontré el aviso final en el molde")
cuerpo = cuerpo.replace(aviso, (
    f"  if v_hechos + v_saltados <> {n} then\n"
    f"    raise exception 'Se esperaban {n} casos y se procesaron %', v_hechos + v_saltados;\n"
    "  end if;\n" + aviso))

salida = privado / "backfill-A-setiembre-2026.sql"
salida.write_text(cabecera + cuerpo)
print(f"{salida.name}: {n} casos · " + ", ".join(f"{o}={sum(1 for c in casos if c[2] == o)}" for o in sorted(ORIGENES)))

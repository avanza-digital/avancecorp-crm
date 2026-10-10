#!/usr/bin/env python3
"""Compara todos los textos v9/v10 y anexo v1/v2 con snapshots idénticos.

Uso: python3 comparar-pdf.py <carpeta-antes> <carpeta-muestras>
Solo descuenta cabeceras/pies de página y cabeceras repetidas de tablas.
No elimina números, importes, fechas ni palabras del cuerpo del contrato.
"""
import difflib
import json
from pathlib import Path
import re
import subprocess
import sys


def exigir(condicion, mensaje):
    if not condicion:
        raise SystemExit(mensaje)


def texto(path, numero):
    raw = subprocess.check_output(["pdftotext", str(path), "-"], text=True)
    pages = [page for page in raw.split("\f") if page.strip()]
    body = []
    for page in pages:
        lines = [line.strip() for line in page.splitlines() if line.strip()]
        exigir(lines.pop(0) == numero, f"Cabecera inesperada: {path}")
        exigir(re.fullmatch(r"\d+\s*/\s*\d+", lines.pop()), f"Pie inesperado: {path}")
        body.extend(lines)
    compact = re.sub(r"\s+", "", " ".join(body))
    # Poppler puede intercalar el número de la primera cuota entre las
    # columnas de una cabecera repetida. Se conserva ese número íntegro.
    compact = re.sub(r"#Fechadelaliquidación(\d+)Participación",
                     r"#FechadelaliquidaciónParticipación\1", compact)
    # En el cuerpo se mantiene la primera cabecera; únicamente se quitan sus
    # repeticiones por salto de página, que pueden variar al añadir la cuenta.
    for header in ["#FechadelaliquidaciónParticipación",
                   "HitoPeriodicidad/fechaNaturalezajurídicaEfectocontractual"]:
        if header in compact:
            first, rest = compact.split(header, 1)
            compact = first + header + rest.replace(header, "")
    return compact, len(pages)


def main():
    before, after = map(Path, sys.argv[1:])
    result = []
    for item in json.loads((after / "manifest.json").read_text()):
        name = item["destino"]
        case = name.removeprefix(item["documento"] + "-").removesuffix(".pdf")
        snapshot = json.loads((after / (case + ".json")).read_text())
        a, pages_a = texto(before / name, snapshot["contrato"]["numero"])
        b, pages_b = texto(after / name, snapshot["contrato"]["numero"])
        if item["documento"] == "contrato":
            old, new = "atencionalcliente@mascapitalgroup.com", "atencionalcliente@groupmascapital.com"
            exigir(a.count(old) == 2 and b.count(new) == 2 and old not in b, name)
            a = a.replace(old, new)
        else:
            account = snapshot["cuentaPago"]["numeroCuenta"]
            exigir(isinstance(account, str) and account.startswith("00"), name)
            row = "Númerodecuentadestino" + account
            exigir(row not in a and b.count(row) == 1, name)
            b = b.replace(row, "", 1)
        if a != b:
            print("FAIL", name)
            print("\n".join(difflib.unified_diff([a], [b])))
            return 1
        result.append({"archivo": name, "estado": "PASS", "paginas_antes": pages_a,
                       "paginas_despues": pages_b, "texto_restante_identico": True})
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Prueba que la letra más grande NO cambió ni una palabra del contrato.

Actualizar el golden del renderer demuestra que los BYTES cambiaron; no demuestra
que el TEXTO sea el mismo (hallazgo de Codex, 08/09/2026). Esto lo demuestra:
extrae el texto de los dos PDFs, descuenta lo que es paginación y compara.

  python3 comparar-texto.py <pdf-8.6pt> <pdf-9.6pt>

Requiere `pdftotext` (poppler).
"""
import hashlib
import re
import subprocess
import sys

CABECERA_TABLA = "HitoPeriodicidad/fechaNaturalezajurídicaEfectocontractual"


def texto(ruta: str) -> tuple[str, int]:
    crudo = subprocess.run(
        ["pdftotext", "-nopgbrk", ruta, "-"], capture_output=True, text=True, check=True
    ).stdout
    # Lo que es paginación y no contrato:
    crudo = re.sub(r"\b\d{4}-\d{2}-\d{6}\b", " ", crudo)   # número de contrato (cabecera de cada hoja)
    crudo = re.sub(r"\b\d+\s*/\s*\d+\b", " ", crudo)        # pie «n / m»
    sin_espacios = re.sub(r"\s+", "", crudo)
    # pdfmake repite la cabecera de la tabla cada vez que esta parte de hoja:
    # con menos hojas se repite menos veces. Tampoco es contenido.
    veces = sin_espacios.count(CABECERA_TABLA)
    return sin_espacios.replace(CABECERA_TABLA, ""), veces


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    a, va = texto(sys.argv[1])
    b, vb = texto(sys.argv[2])
    print(f"cabecera de la tabla repetida: {va} vez/veces vs {vb}")
    print(f"{len(a)} caracteres · {hashlib.sha256(a.encode()).hexdigest()[:16]}")
    print(f"{len(b)} caracteres · {hashlib.sha256(b.encode()).hexdigest()[:16]}")
    if a == b:
        print("✅ el texto del contrato es idéntico carácter a carácter")
        return 0
    import difflib
    for i, s in enumerate(difflib.ndiff(a, b)):
        if s[0] in "+-":
            print(f"❌ primera diferencia en el carácter {i}: {s!r}")
            print(f"   ...{a[max(0, i - 90):i + 90]}...")
            print(f"   ...{b[max(0, i - 90):i + 90]}...")
            break
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

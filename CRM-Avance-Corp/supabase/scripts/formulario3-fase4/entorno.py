#!/usr/bin/env python3
"""Credenciales solo en fichero 0600 temporal; ninguna se imprime o se versiona."""
from pathlib import Path
import json
import os
import secrets
import subprocess
import sys

REF = "oemmpccapplmiygcpvxr"
PROD = "dctqcbznekcyxhjujuci"
BRANCH = "formulario3-fase4-20261014"
PRIVATE = Path("/private/tmp/formulario3-fase4-privado")
EVIDENCE = Path(__file__).resolve().parent
ROOT = EVIDENCE.parents[2]


def cli(args):
    p = subprocess.run(["supabase", *args, "--output", "json"], capture_output=True, text=True)
    if p.returncode:
        # CLI puede incluir tokens o URL en errores. Nunca volcar stdout/stderr.
        raise RuntimeError(f"Supabase {args[0]} no disponible (exit {p.returncode})")
    return json.loads(p.stdout)


def private_file(name, text):
    PRIVATE.mkdir(mode=0o700, exist_ok=True)
    os.chmod(PRIVATE, 0o700)
    target = PRIVATE / name
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.chmod(target, 0o600)
    return target


def branch():
    data = cli(["branches", "get", BRANCH, "--project-ref", PROD])
    private_file("branch.json", json.dumps(data))
    print(json.dumps({"branch": BRANCH, "ref": REF, "campos_disponibles": list(data)}))
    secret_path = PRIVATE / "importar.env"
    if not secret_path.exists():
        private_file("importar.env", "CRM_IMPORTAR_SECRET=" + secrets.token_hex(32) + "\n")


def realidad():
    keys = cli(["projects", "api-keys", "--project-ref", PROD])
    key = next(x["api_key"] for x in keys if x.get("name") == "service_role")
    env = {**os.environ, "SUPABASE_URL": f"https://{PROD}.supabase.co", "SUPABASE_SERVICE_ROLE_KEY": key}
    p = subprocess.run(["node", "supabase/scripts/gate-realidad.mjs", "--json"], env=env, cwd=ROOT, capture_output=True, text=True)
    # El gate auditado es solo lectura y emite conteos; revisión defensiva adicional.
    output = p.stdout.replace(key, "[REDACTADO]")
    (EVIDENCE / "gate-realidad.json").write_text(output)
    print(json.dumps({"gate": "realidad", "exit_code": p.returncode, "evidencia": "gate-realidad.json"}))
    if p.returncode:
        raise RuntimeError("Gate realidad no completado; revisar salida saneada")


if __name__ == "__main__":
    try:
        {"branch": branch, "realidad": realidad}[sys.argv[1]]()
    except Exception as e:
        print(f"{type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)


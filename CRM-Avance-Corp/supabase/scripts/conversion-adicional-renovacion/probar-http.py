#!/usr/bin/env python3
"""Compara la RPC HTTP con SQL para cinco sesiones de negocio y dos roles técnicos.

Obtiene sesiones reales de Auth mediante enlaces generados y consumidos
internamente: no envía correos ni cambia contraseñas. Solo en la branch.
"""
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import subprocess
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen

REF = "yeiwghzhcrvwfcybymxy"
ROOT = Path(__file__).resolve().parent
config = json.loads(subprocess.check_output([
    "supabase", "branches", "get", "conversion-adicional-renovacion-20261014",
    "--project-ref", "dctqcbznekcyxhjujuci", "--output", "json"], text=True))
assert config["SUPABASE_URL"].rstrip("/") == "https://" + REF + ".supabase.co"
cases = json.loads(Path("/private/tmp/conversion-adicional-http-esperado.json").read_text())["rows"][0]["casos"]
assert len(cases) == 43
selected = {'2c10b18a-a15d-4952-952b-c4ab91b96153','d571aeed-e65d-4369-ac86-00a83bf9d389',
            '0eeb8c64-25e4-418b-b5d5-e07b06758b5e'}
selected.update(next(c['id'] for c in cases if c['rol']==role and c['activo']) for role in ('gerencia','coordinador'))
cases = [c for c in cases if c['id'] in selected or c['dbrol'] != 'authenticated']
assert len(cases) == 7

def auth_request(path, bearer, data=None):
    req = Request(config['SUPABASE_URL']+'/auth/v1/'+path,
                  data=None if data is None else json.dumps(data).encode(),
                  method='GET' if data is None else 'POST', headers={
                      'apikey':config['SUPABASE_ANON_KEY'], 'Authorization':'Bearer '+bearer,
                      'Content-Type':'application/json'})
    for attempt in range(4):
        try:
            with urlopen(req,timeout=30) as response:
                raw=response.read()
                return json.loads(raw) if raw else {}
        except HTTPError as error:
            if error.code!=429 or attempt==3:
                raise
            wait=max(15,int(error.headers.get('Retry-After','15')))
            if wait>60:
                raise RuntimeError('Límite Auth: esperar antes de repetir el banco') from None
            time.sleep(wait)

def token(case):
    if case["dbrol"] == "anon":
        return config["SUPABASE_ANON_KEY"]
    if case["dbrol"] == "service_role":
        return config["SUPABASE_SERVICE_ROLE_KEY"]
    admin=config['SUPABASE_SERVICE_ROLE_KEY']
    raw=auth_request('admin/users/'+case['id'],admin)
    user=raw.get('user',raw)
    assert user['id']==case['id'] and user.get('email')
    link=auth_request('admin/generate_link',admin,{'type':'magiclink','email':user['email']})
    hashed=link.get('hashed_token') or link.get('properties',{}).get('hashed_token')
    assert hashed
    session=auth_request('verify',config['SUPABASE_ANON_KEY'],{'token_hash':hashed,'type':'email'})
    assert session['user']['id']==case['id']
    return session['access_token']

def normal(value):
    if isinstance(value, dict):
        return {k: normal(v) for k, v in sorted(value.items()) if k != "generado_en"}
    if isinstance(value, list):
        return sorted((normal(v) for v in value), key=lambda v: json.dumps(v, sort_keys=True))
    return value

def check(case):
    bearer=token(case)
    request = Request(config["SUPABASE_URL"] + "/rest/v1/rpc/conversion_mensual_fn",
                      data=b'{"p_periodo":"2026-10-01"}', method="POST", headers={
                          "apikey": config["SUPABASE_ANON_KEY"], "Authorization": "Bearer " + bearer,
                          "Content-Type": "application/json", "Content-Profile": "crm", "Accept-Profile": "crm"})
    try:
        with urlopen(request, timeout=30) as response:
            status, actual = response.status, json.load(response)
    except HTTPError as error:
        status, actual = error.code, json.loads(error.read())
    if case['dbrol']=='authenticated':
        auth_request('logout?scope=local',bearer,{})
    expected = case["esperado"]
    if "sqlstate" in expected:
        ok = status in (400, 401, 403) and actual.get("code") == expected["sqlstate"]
    else:
        ok = status == 200 and normal(actual) == normal(expected)
    return {"id": case["id"], "rol": case["rol"], "activo": case["activo"],
            "dbrol": case["dbrol"], "http_status": status, "estado": "PASS" if ok else "FAIL",
            "codigo": actual.get("code") if isinstance(actual, dict) else None,
            "mensaje": actual.get("message") if not ok and isinstance(actual, dict) else None}

with ThreadPoolExecutor(max_workers=1) as pool:
    results = list(pool.map(check, cases))
report = {"branch": REF, "casos": len(results), "pass": sum(r["estado"] == "PASS" for r in results),
          "metodo": "Sesiones reales Auth generadas sin enviar correos; HTTP PostgREST idéntico a SQL por rol. No prueba login con contraseña ni recuperación.",
          "resultados": results}
(ROOT / "http.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({"branch": REF, "casos": report["casos"], "pass": report["pass"],
                  "fallos": [r for r in results if r["estado"] != "PASS"]}, ensure_ascii=False))
assert report["pass"] == report["casos"], "Ver http.json"

environ = dict(os.environ)
for key in ("SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY"):
    environ[key] = config[key]
environ['CRM_DEMO_PASSWORD']='SoloPreflightLocalNoCuenta2026'
preflight = subprocess.run(["npm", "run", "test:rls:preflight"], env=environ, capture_output=True, text=True)
Path("/private/tmp/conversion-adicional-rls-preflight.log").write_text(preflight.stdout + preflight.stderr)
print(json.dumps({"rls_preflight_exit_code": preflight.returncode}))

#!/usr/bin/env python3
"""Contrato PostgREST real con JWT de actores exclusivamente sintéticos del banco."""
import base64
import hashlib
import hmac
import json
import time
import urllib.error
import urllib.request
from remoto import CFG, sql

LEAD = 'c0000000-0000-4000-8000-000000000071'
S1 = 'c0000000-0000-4000-8000-000000000002'
S2 = 'c0000000-0000-4000-8000-000000000003'
VENDEDORES = ('c0000000-0000-4000-8000-000000000004', 'c0000000-0000-4000-8000-000000000005')


def jwt(actor):
    def b64(data):
        return base64.urlsafe_b64encode(data).decode().rstrip('=')
    payload = {'sub': actor, 'role': 'authenticated', 'aud': 'authenticated', 'exp': int(time.time())+300}
    body = b64(b'{"alg":"HS256","typ":"JWT"}')+'.'+b64(json.dumps(payload).encode())
    return body+'.'+b64(hmac.new(CFG['SUPABASE_JWT_SECRET'].encode(), body.encode(), hashlib.sha256).digest())


def asignar(actor, destino):
    request = urllib.request.Request(CFG['SUPABASE_URL']+'/rest/v1/leads?id=eq.'+LEAD+'&select=id,vendedor_id',
        data=json.dumps({'vendedor_id': destino}).encode(), method='PATCH', headers={
            'apikey': CFG['SUPABASE_ANON_KEY'], 'Authorization': 'Bearer '+jwt(actor),
            'Content-Type': 'application/json', 'Content-Profile': 'crm', 'Accept-Profile': 'crm',
            'Prefer': 'return=representation'})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)


origen = sql(f"select vendedor_id from crm.leads where id='{LEAD}';")[0].strip()
assert origen in VENDEDORES
destino = next(v for v in VENDEDORES if v != origen)
status, data = asignar(S2, destino)
assert data == [] or (status >= 400 and data.get('code') == '42501'), (status, data)
assert sql(f"select vendedor_id from crm.leads where id='{LEAD}';")[0].strip() == origen
print('PASS HTTP: supervisor de otro equipo no mueve el lead')
status, data = asignar(origen, destino)
assert status >= 400 and data.get('message') == 'Un vendedor no puede reasignar leads', (status, data)
print('PASS HTTP: analista conserva el veto a reasignar')
status, data = asignar(S1, destino)
assert status == 200 and data == [{'id': LEAD, 'vendedor_id': destino}], (status, data)
alineado = sql(f"select l.vendedor_id=i.responsable_relacion_id and i.responsable_relacion_id=s.responsable_esperado_id from crm.leads l join crm.inversionistas i on i.id=l.inversionista_id join crm.inversion_solicitudes s on s.lead_origen_id=l.id where l.id='{LEAD}' and s.estado='preparada';")[0].strip()
assert alineado == 't', alineado
print('PASS HTTP: antes de responder éxito, COMMIT alinea lead, persona y borrador')

import json, subprocess, os, sys
S = os.environ['S']
CRM = '/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp'
pend = [l.split('|') for l in open(f'{S}/pendientes.txt').read().split('\n') if l.strip()]
lote = 8
hechos = 0
for i in range(0, len(pend), lote):
    trozo = pend[i:i+lote]
    vers = ','.join("'" + v[0] + "'" for v in trozo)
    q = (f"select jsonb_object_agg(version, array_to_string(statements, E';\\n') || E';\\n') as cuerpos "
         f"from supabase_migrations.schema_migrations where version in ({vers});")
    open(f'{S}/vol.sql','w').write(q)
    r = subprocess.run(['npx','supabase','db','query','--linked','--file',f'{S}/vol.sql'],
                       cwd=CRM, capture_output=True, text=True, timeout=300)
    raw = r.stdout
    j = raw.find('{')
    if j < 0:
        print('FALLO lote', i, raw[:300], flush=True); sys.exit(1)
    o = json.loads(raw[j:])
    cuerpos = o['rows'][0]['cuerpos']
    if isinstance(cuerpos, str):
        cuerpos = json.loads(cuerpos)
    for v, nombre, _sz in trozo:
        sql = cuerpos.get(v)
        if not sql:
            print('SIN CUERPO:', v, flush=True); sys.exit(1)
        open(f'{S}/banco-sql/{v}_{nombre}.sql','w').write(sql)
        hechos += 1
    print(f'lote {i//lote+1}: {hechos}/{len(pend)}', flush=True)
print('VOLCADO COMPLETO', hechos)

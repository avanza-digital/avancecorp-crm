import json, subprocess, os, sys

# ---------------------------------------------------------------------------
# Re-registra en el banco las versiones con la MISMA FORMA DE ARRAY que
# produccion, no solo con el mismo texto.
#
# 🔴 LECCION DEL 01/09 (Ola R): `statements` es un ARRAY de sentencias. El
# replay lo guardaba como UN solo elemento con el texto unido — mismo texto,
# fronteras distintas. La Ola R comprueba la identidad POR ELEMENTO
# (`md5(string_agg(md5(elemento) order by ord))`) y el numero de sentencias,
# justamente porque el md5 del texto unido NO ve fronteras desplazadas. Con un
# solo bloque, la Ola R dice —con razon— que ese cuerpo no es el objetivo.
#
# Un banco que replaya el registro tiene que reproducir el registro ENTERO:
# texto Y fronteras.
# ---------------------------------------------------------------------------
S = os.environ['S']
CRM = '/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp'
PG = open(f'{S}/banco-pooler.txt').read().strip()
pend = [l.split('|') for l in open(f'{S}/pendientes.txt').read().split('\n') if l.strip()]


def tag_libre(txt):
    for i in range(200):
        t = f'$arr{i}$'
        if t not in txt:
            return t
    raise SystemExit('sin delimitador libre')


lote = 4
hechos = 0
for i in range(0, len(pend), lote):
    trozo = pend[i:i + lote]
    vers = ','.join("'" + v[0] + "'" for v in trozo)
    q = (f"select jsonb_object_agg(version, to_jsonb(statements)) as arrs "
         f"from supabase_migrations.schema_migrations where version in ({vers});")
    open(f'{S}/vol-arr.sql', 'w').write(q)
    r = subprocess.run(['npx', 'supabase', 'db', 'query', '--linked', '--file', f'{S}/vol-arr.sql'],
                       cwd=CRM, capture_output=True, text=True, timeout=300)
    j = r.stdout.find('{')
    if j < 0:
        print('FALLO lote', i, r.stdout[:300], r.stderr[:300], flush=True)
        sys.exit(1)
    o = json.loads(r.stdout[j:])
    arrs = o['rows'][0]['arrs']
    if isinstance(arrs, str):
        arrs = json.loads(arrs)

    partes = []
    for v, nombre, _sz in trozo:
        a = arrs.get(v)
        if a is None:
            print('SIN ARRAY:', v, flush=True)
            sys.exit(1)
        js = json.dumps(a, ensure_ascii=False)
        t = tag_libre(js)
        partes.append(
            f"update supabase_migrations.schema_migrations set statements = "
            f"(select array_agg(x order by ord) from jsonb_array_elements_text({t}{js}{t}::jsonb) "
            f"with ordinality as u(x, ord)) where version = '{v}';")
        hechos += 1
    open(f'{S}/rearr.sql', 'w').write('begin;\n' + '\n'.join(partes) + '\ncommit;\n')
    r2 = subprocess.run(['psql', PG, '-v', 'ON_ERROR_STOP=1', '-f', f'{S}/rearr.sql'],
                        capture_output=True, text=True, timeout=600)
    if r2.returncode != 0:
        print('FALLO al re-registrar lote', i, (r2.stderr or '')[-900:], flush=True)
        sys.exit(2)
    print(f'lote {i//lote+1}: {hechos}/{len(pend)}', flush=True)
print('RE-REGISTRO COMPLETO', hechos, flush=True)

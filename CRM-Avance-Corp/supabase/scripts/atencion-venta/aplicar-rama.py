"""Aplica solo las dos candidatas en el banco reconstruido y cotejado."""
import json
from pathlib import Path
from remoto import sql, REF

for nombre in ['atencion-base-paridad', 'atencion-edge-paridad']:
    assert json.loads(Path('/private/tmp/' + nombre + '.json').read_text())['estado'] == 'PASS'
base = json.loads(Path('/private/tmp/atencion-catalogo-productivo.json').read_text())['rows'][0]['catalogo']['ledger']
base = [{k:r[k] for k in ['version','name','statements']} for r in base]
consulta = "select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name,'statements',statements) order by version),'[]') from supabase_migrations.schema_migrations"
actual = json.loads(sql(consulta))
assert actual == sorted(base, key=lambda r: r['version']), 'La base del ledger debe ser idéntica'
assert json.loads(sql("select jsonb_build_object('usuarios',(select count(*) from auth.users),'cron',(select count(*) from cron.job where active))")) == {'usuarios': 0, 'cron': 0}
candidatas = ['20261013192850_crm_atencion_venta_separadas.sql', '20261013193653_crm_atencion_venta_hardening.sql']
q = lambda s: "'" + s.replace("'", "''") + "'"
for archivo in candidatas:
    version, nombre = archivo[:-4].split('_', 1)
    texto = (Path(__file__).parents[2] / 'migrations' / archivo).read_bytes().decode()
    assert texto.rstrip().endswith('commit;') and '\nbegin;\n' in texto
    assert not any(r['version'] == version for r in actual)
    registro = 'insert into supabase_migrations.schema_migrations(version,name,statements) values (' + q(version) + ',' + q(nombre) + ',array[' + q(texto) + ']);'
    # DDL y su entrada del ledger se confirman juntos. Historial previo intacto.
    sql(texto.rstrip()[:-len('commit;')] + registro + '\ncommit;')
    actual.append({'version': version, 'name': nombre, 'statements': [texto]})
    print('PASS aplicada en ' + REF + ': ' + archivo, flush=True)
assert json.loads(sql(consulta)) == sorted(actual, key=lambda r: r['version'])
sql("notify pgrst,'reload schema';")
Path('/private/tmp/atencion-candidatas-rama.json').write_text(json.dumps({'estado':'PASS','ref':REF,'base':len(base),'candidatas':candidatas,'historial_previo':'idéntico'},indent=2))

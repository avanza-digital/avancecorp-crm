# Venta cruzada · mutantes de las pruebas SQL. Cada mutante neutraliza UNA defensa
# (reescribe el cuerpo vivo de una función dentro de la transacción de la prueba) y la
# prueba tiene que FALLAR. Si pasa, esa defensa no está probada. Nada queda escrito: la
# prueba termina en rollback y el mutante vive dentro de ella.
# Solo en el banco sintético (puerto 53322 por defecto).
# Uso: python3 supabase/scripts/venta-cruzada/mutantes.py test-fase4.sql mutantes-fase4.json
import json, os, subprocess, sys

AQUI = os.path.dirname(os.path.abspath(__file__))
PSQL = ['psql', '-X', '-q', '-h', os.environ.get('VC_HOST', '127.0.0.1'), '-p', os.environ.get('VC_PORT', '53322'),
        '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-At']
ENTORNO = dict(os.environ, PGPASSWORD=os.environ.get('PGPASSWORD', 'postgres'))

def ruta(p):
    return p if os.path.isabs(p) else os.path.join(AQUI, p)

def main(prueba, casos):
    cuerpo = open(ruta(prueba), encoding='utf-8').read()
    if '\nbegin;\n' not in cuerpo or not cuerpo.rstrip().endswith('rollback;'):
        sys.exit('La prueba tiene que abrir con begin; y terminar en rollback;')
    cuerpo = cuerpo.replace('\nbegin;\n', '\n', 1)
    fallos = 0
    for c in json.load(open(ruta(casos), encoding='utf-8')):
        r = subprocess.run(PSQL + ['-c', f"select pg_get_functiondef('{c['firma']}'::regprocedure)"],
                           capture_output=True, text=True, env=ENTORNO, check=True)
        d = r.stdout
        if d.count(c['desde']) != 1:
            print(f"MUTANTE {c['nombre']}: el texto a mutar aparece {d.count(c['desde'])} veces ✗")
            fallos += 1
            continue
        mutado = 'begin;\n' + d.replace(c['desde'], c['hacia']).rstrip() + ';\n' + cuerpo
        r = subprocess.run(PSQL, input=mutado, capture_output=True, text=True, env=ENTORNO)
        if r.returncode != 0 and '_OK' not in r.stdout:
            error = next((l for l in (r.stdout + r.stderr).splitlines() if 'ERROR' in l), '')
            print(f"MUTANTE {c['nombre']}: MUERTO ✓  ({error.split('ERROR:')[-1].strip()[:140]})")
        else:
            print(f"MUTANTE {c['nombre']}: SOBREVIVIÓ ✗")
            fallos += 1
    print('MUTANTES_OK' if not fallos else f'MUTANTES_FALLAN: {fallos}')
    sys.exit(1 if fallos else 0)

if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit('Uso: mutantes.py <prueba.sql> <mutantes.json>')
    main(sys.argv[1], sys.argv[2])

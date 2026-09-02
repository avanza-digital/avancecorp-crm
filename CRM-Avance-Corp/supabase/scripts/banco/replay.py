import os, subprocess, sys, re

# ---------------------------------------------------------------------------
# Replay del registro de produccion sobre un banco.
#
# 🔴 LECCION DEL 01/09 (F2.3b): un fichero SIN transaccion propia que muere en
# su postflight deja los objetos COMMITEADOS y la version SIN registrar. En el
# siguiente intento el preflight ancla el estado ANTERIOR, ya no existe, y el
# rojo se lee como «el banco esta corrupto» cuando en realidad el banco tiene
# el trabajo hecho. Por eso: si el fichero no abre transaccion, la abrimos
# nosotros con `psql -1`. O entra entero, o no entra nada.
# ---------------------------------------------------------------------------
S = os.environ['S']
PG = open(f'{S}/banco-pooler.txt').read().strip()
pend = [l.split('|') for l in open(f'{S}/pendientes.txt').read().split('\n') if l.strip()]

RE_BEGIN = re.compile(r'(?mi)^\s*begin\s*;')
RE_COMMIT = re.compile(r'(?mi)^\s*commit\s*;')


# ---------------------------------------------------------------------------
# Zona horaria de la sesion: America/Lima.
#
# 🔴 LECCION DEL 01/09 (F4.d): banco y produccion corren con `TimeZone=UTC`.
# Los gates del sistema comparan contra el "hoy" de LIMA
# (`(now() at time zone 'America/Lima')::date`), pero `current_date` en una
# sesion UTC devuelve el dia de UTC. Entre las 19:00 y las 24:00 de Lima los
# dos NO coinciden, y un oraculo que pasa `current_date` como `p_hasta` se
# come un «Periodo invalido» — tambien en produccion.
#
# Poner la sesion en Lima reproduce las condiciones en que produccion aplico
# estas migraciones (a una hora en que ambas fechas coincidian). No toca la
# logica de nadie: solo alinea el reloj del que ejecuta.
#
# ⚠️ `PGOPTIONS` NO SIRVE: el pooler de Supabase se come las opciones de
#    arranque (medido: sigue diciendo UTC). Hay que mandar un `SET` explicito
#    como primera sentencia de cada invocacion.
# ---------------------------------------------------------------------------
TZ = ['-c', "set timezone='America/Lima'"]


def psql(args, timeout=900):
    return subprocess.run(['psql', PG, '-v', 'ON_ERROR_STOP=1'] + args,
                          capture_output=True, text=True, timeout=timeout)


def trae_su_transaccion(texto):
    return bool(RE_BEGIN.search(texto) and RE_COMMIT.search(texto))


ya = set(psql(['-At', '-c',
               "select version from supabase_migrations.schema_migrations"]).stdout.split())
ok = 0
for ver, nombre, _sz in pend:
    if ver in ya:
        continue
    # Un PARCHE de banco (divergencia declarada en banco-parches/DIVERGENCIAS.md)
    # manda sobre el SQL de produccion. Solo neutralizan aserciones con hambre
    # de datos; jamas la logica que la migracion instala.
    f = f'{S}/banco-parches/{ver}_{nombre}.sql'
    parcheada = os.path.exists(f)
    if not parcheada:
        f = f'{S}/banco-sql/{ver}_{nombre}.sql'

    # Atomicidad: la del fichero si la trae, la nuestra si no.
    # ---------------------------------------------------------------------
    # 🔴 LECCION DEL 01/09 (F7.1): el fichero va en UN SOLO MENSAJE (`-c`),
    # no sentencia a sentencia (`-f`).
    #
    # Produccion aplica con `supabase db query --linked --file`, que manda el
    # fichero entero como una sola consulta. `statement_timestamp()` es «la
    # hora del ULTIMO MENSAJE recibido del cliente», asi que con un solo
    # mensaje NO AVANZA en toda la migracion. Con `-f`, psql manda una
    # sentencia por mensaje y el reloj corre entre ellas: el oraculo de la
    # F7.1 —que fotografia un payload y lo vuelve a pedir despues— veia
    # cambiar `generado_en` y abortaba, diciendo la verdad sobre un mundo que
    # produccion nunca vive.
    #
    # `-c` con varias sentencias ademas las corre en UNA transaccion salvo que
    # el fichero traiga sus propios BEGIN/COMMIT — la misma atomicidad que
    # buscaba el `-1`, y la misma que tiene produccion.
    #
    # Medido: fichero mayor 200 KB, ARG_MAX 1 MB. Cabe con holgura.
    # ---------------------------------------------------------------------
    propia = trae_su_transaccion(open(f).read())
    r = psql(TZ + ['-c', open(f).read()])
    if r.returncode != 0:
        print(f'\n🔴 MURIO EN {ver}_{nombre}', flush=True)
        print(f'   transaccion: {"la del fichero" if propia else "la implicita del -c"}'
              f'  →  el banco quedo SIN cambios de esta migracion', flush=True)
        print((r.stderr or r.stdout)[-1800:], flush=True)
        print(f'\naplicadas en esta tanda: {ok}', flush=True)
        sys.exit(2)

    # registrar la version en el banco
    # Se registra el cuerpo de PRODUCCION, nunca el parcheado: el registro del
    # banco debe poder compararse con el de prod.
    # `volcar.py` guardo el texto con un `;\n` de cortesia al final. Se lo
    # quitamos para que el registro del banco compare BYTE A BYTE con el de
    # produccion; si no, todo diferiria por dos caracteres y una comparacion
    # honesta se volveria imposible de leer.
    cuerpo = open(f'{S}/banco-sql/{ver}_{nombre}.sql').read()
    if cuerpo.endswith(';\n'):
        cuerpo = cuerpo[:-2]
    tag = None
    for cand in ['$reg_banco$', '$rb_x9$', '$rb_z7$', '$rb_q4$']:
        if cand not in cuerpo:
            tag = cand
            break
    if tag is None:
        print('sin delimitador libre para', ver, flush=True)
        sys.exit(3)
    ins = (f"insert into supabase_migrations.schema_migrations (version, name, statements) "
           f"values ('{ver}', '{nombre}', array[{tag}{cuerpo}{tag}]) on conflict (version) do nothing;")
    open(f'{S}/reg.sql', 'w').write(ins)
    r2 = psql(['-f', f'{S}/reg.sql'])
    if r2.returncode != 0:
        print('🔴 fallo al REGISTRAR', ver, (r2.stderr or '')[-800:], flush=True)
        sys.exit(4)
    ok += 1
    print(f'✓ {ok:3d}  {ver}  {nombre}'
          + ('  [PARCHE DE BANCO]' if parcheada else '')
          + ('' if propia else '  [tx implicita]'), flush=True)
print(f'\nREPLAY COMPLETO: {ok} versiones aplicadas', flush=True)

#!/usr/bin/env python3
"""Transporte de UN solo mensaje y candados de los guiones que escriben (migración 20261009120000). SOLO banco local.

Corre cada archivo como lo manda `supabase db query --linked -f`: el archivo ENTERO en un solo mensaje (`psql -c`), como
`postgres`; varios pasos con una sesión cuyo default_transaction_isolation es 'repeatable read' (los guiones y la
migración abren su transacción en READ COMMITTED de forma explícita). Después de cada paso, otra conexión comprueba que
no queda ningún candado de aviso tomado (ni el del mes ni el de sesión de las migraciones).

  T1  1-ENSAYO (sesión READ COMMITTED) → «LISTO PARA 2-REAL».            T2  1-ENSAYO (sesión REPEATABLE READ) → lo mismo.
  T3  2-REAL con un sello de septiembre en curso (simulado: los candados de crm.cerrar_periodo y su fila) → sale al
      instante con «Hay actividad en curso», sin escribir.
  T4  2-REAL con un alta real de septiembre detenida entre contrato y operación → sale al instante; el alta termina bien.
  T5  2-REAL con el contrato 11 de 12 (001445) en proceso de eliminación → aborta y no queda NADA escrito.
  T6  2-REAL (sesión REPEATABLE READ) → última fila «OK: 12 contratos de nuevo a upgrade».
  T7  oráculo (si se pasa --oraculo <archivo>; en el banco, el generado con la medición del banco) → PASS.
  T8  reversa.sql → sin puerta, núcleo ni triggers; el candado de sesión de migraciones queda suelto.
  T9  reversa-datos (REPEATABLE READ) con un sello en curso → sale al instante, sin escribir.
  T10 reversa-datos (REPEATABLE READ) con septiembre YA sellado (fila simulada, se quita después) → «ya está sellado»,
      sin escribir: no puede reescribir un mes sellado.
  T11 reversa-datos (REPEATABLE READ) → «OK: 12 contratos de vuelta a nuevo».
  T12 la migración otra vez (sesión REPEATABLE READ) → postflight OK; vuelve el estado del principio.
«Sin escribir» = mismas categorías de los 12, mismas filas de motivo y mismas filas del libro de rentabilidad.
Al final imprime «TRANSPORTE OK n/n» o «TRANSPORTE FALLA: …» (salida 1). Deja el banco como lo encontró (los 12 en 'nuevo'
y la migración puesta).

Uso:  python3 -I transporte.py [contenedor] [--oraculo <oraculo.sql>]   (por defecto supabase_db_avancecorp-categoria-20261008)
"""
import pathlib
import subprocess
import sys
import time
import uuid

AQUI = pathlib.Path(__file__).resolve().parent
MIGRACION = AQUI.parent.parent / "migrations" / "20261009120000_crm_categoria_contrato_por_operacion.sql"
ARGS = sys.argv[1:]
ORACULO = None
if "--oraculo" in ARGS:
    i = ARGS.index("--oraculo")
    ORACULO = pathlib.Path(ARGS[i + 1])
    ARGS = ARGS[:i] + ARGS[i + 2:]
CONTENEDOR = ARGS[0] if ARGS else "supabase_db_avancecorp-categoria-20261008"
RR = "-c default_transaction_isolation=repeatable\\ read"
ACTIVIDAD = "Hay actividad en curso: vuelve a correr el guion en unos minutos"
SEPTIEMBRE = "(date '2026-09-01' - date '2000-01-01')::integer"
GERENCIA = "ca7e0000-0000-4000-8000-000000000001"
NUMEROS = ("'2026-01-001362', '2026-01-001369', '2026-01-001401', '2026-01-001408', '2026-01-001400', '2026-01-001439', "
           "'2026-01-001440', '2026-01-001441', '2026-01-001424', '2026-01-001425', '2026-01-001445', '2026-01-001447'")
RAPIDO = 2.0


def psql_args(usuario="supabase_admin", opciones=None):
    entorno = ["-e", "PGPASSWORD=postgres"] + (["-e", f"PGOPTIONS={opciones}"] if opciones else [])
    return ["docker", "exec", "-i", *entorno, CONTENEDOR, "psql", "-X", "-q", "-At",
            "-U", usuario, "-h", "127.0.0.1", "-d", "postgres", "-v", "ON_ERROR_STOP=1"]


def correr(sql):
    r = subprocess.run(psql_args(), input=sql, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"fixture falló: {r.stderr.strip()[:300]}")
    return r.stdout.strip()


def lanzar(sql):
    p = subprocess.Popen(psql_args(), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    p.stdin.write(sql)
    p.stdin.close()
    return p


def esperar(p):
    out, err = p.stdout.read(), p.stderr.read()
    p.wait(timeout=90)
    return p.returncode, out, err


def mensaje(ruta, opciones=None):
    """El archivo ENTERO como UN solo mensaje (psql -c), como postgres. Devuelve (código, salida+error, segundos)."""
    t0 = time.monotonic()
    r = subprocess.run(psql_args("postgres", opciones) + ["-c", pathlib.Path(ruta).read_text(encoding="utf-8")],
                       capture_output=True, text=True, timeout=300)
    return r.returncode, r.stdout + r.stderr, time.monotonic() - t0


def candados():
    return int(correr("select count(*) from pg_locks where locktype = 'advisory';") or 0)


def foto():
    return correr(f"""select (select string_agg(c.categoria, ',' order by c.numero_contrato) from public.contratos c
                              where c.numero_contrato in ({NUMEROS}))
                  || ' · motivo ' || (select count(*) from public.audit_log a join public.contratos c on a.fila_id = c.id::text
                                       where a.tabla = 'contratos.categoria' and c.numero_contrato in ({NUMEROS}))
                  || ' · libro ' || (select count(*) from crm.ledger_rentabilidad l join public.contratos c on c.id = l.contrato_id
                                      where c.numero_contrato in ({NUMEROS}));""")


def en(categoria):
    return foto().split(" · ")[0] == ",".join([categoria] * 12)


def sello_simulado(pausa):
    return lanzar("begin;\n"
                  "select pg_advisory_xact_lock(hashtext('crm.periodos_cerrados')::bigint);\n"
                  f"select pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'), {SEPTIEMBRE});\n"
                  "lock table crm.equipo in share mode;\n"
                  "insert into crm.periodos_cerrados (periodo, cerrado_por, automatico, ponderacion_referido, meta_revision, "
                  "cobertura, ponderacion_renovacion) values (date '2026-09-01', null, true, 0.15, 1, "
                  "'{\"banco\": \"sello simulado\"}', 0.15);\n"
                  f"select pg_sleep({pausa});\nrollback;\n")


def sale_al_instante(nombre, opciones, contra):
    antes = foto()
    proceso = contra()
    time.sleep(1.0)
    c, salida, s = mensaje(AQUI / nombre, opciones)
    otra = esperar(proceso)
    despues = foto()
    ok = c != 0 and ACTIVIDAD in salida and s < RAPIDO and antes == despues
    return ok, otra, (f"sale en {s:.1f} s sin escribir" if ok else
                      f"NO: código {c}, {s:.1f} s, {'escribió' if antes != despues else 'sin escribir'}: {salida.strip()[-200:]}")


def alta_detenida():
    numero = "CAT-TR-" + uuid.uuid4().hex[:8]
    return lanzar(f"""begin;
select set_config('prueba.pausa_alta', '4', true);
select set_config('crm.rentabilidad_origen_upgrade', 'ca7e0000-0000-4000-8000-00000000010e|ca7e0000-0000-4000-8000-00000000110e', true);
select set_config('request.jwt.claims', '{{"sub": "{GERENCIA}", "role": "authenticated"}}', true);
select set_config('request.jwt.claim.sub', '{GERENCIA}', true);
set local role authenticated;
select (public.crear_contrato(
  jsonb_build_object('cliente_id', 'ca7e0000-0000-4000-8000-00000000010e', 'numero_contrato', '{numero}', 'capital', 30000,
                     'moneda', 'PEN', 'tasa_anual', 15, 'modalidad', 'mensual', 'tipo_interes', 'simple',
                     'fecha_inicio', date '2026-09-28', 'fecha_vencimiento', date '2027-09-28', 'categoria', 'upgrade'),
  jsonb_build_array(jsonb_build_object('numero_cuota', 1, 'fecha_programada', date '2026-10-28', 'monto_programado', 375)))) is not null;
reset role;
select 'ALTA ' || c.categoria || '/' || o.tipo || '/' || to_char(c.fecha_cierre_comercial, 'YYYY-MM')
  from public.contratos c join crm.operaciones_cartera o on o.contrato_nuevo_id = c.id where c.numero_contrato = '{numero}';
set constraints all immediate;
rollback;
""")


PAUSA_ALTA = """create or replace function private.prueba_pausa_alta() returns trigger language plpgsql as $f$
begin
  if coalesce(current_setting('prueba.pausa_alta', true), '') <> '' then
    perform pg_sleep(current_setting('prueba.pausa_alta', true)::numeric);
  end if;
  return null;
end $f$;
drop trigger if exists trg_contratos_zz_prueba_pausa on public.contratos;
create trigger trg_contratos_zz_prueba_pausa after insert on public.contratos
  for each row execute function private.prueba_pausa_alta();
"""
QUITA_PAUSA = ("drop trigger if exists trg_contratos_zz_prueba_pausa on public.contratos;\n"
               "drop function if exists private.prueba_pausa_alta();\n")
OBJETOS = ("select count(*) from pg_proc where proname in ('fijar_categoria_contrato', 'corregir_categoria_contrato_fn', "
           "'trg_operacion_cartera_fija_categoria', 'trg_contrato_categoria_por_operacion');")


def t1():
    c, salida, s = mensaje(AQUI / "1-ENSAYO.sql")
    return "LISTO PARA 2-REAL" in salida, f"{'LISTO' if 'LISTO PARA 2-REAL' in salida else salida.strip()[-200:]} en {s:.1f} s"


def t2():
    c, salida, s = mensaje(AQUI / "1-ENSAYO.sql", RR)
    return "LISTO PARA 2-REAL" in salida, f"{'LISTO' if 'LISTO PARA 2-REAL' in salida else salida.strip()[-200:]} en {s:.1f} s"


def t3():
    ok, sello, txt = sale_al_instante("2-REAL.sql", RR, lambda: sello_simulado(4))
    return ok and sello[0] == 0, txt


def t4():
    correr(PAUSA_ALTA)
    try:
        ok, alta, txt = sale_al_instante("2-REAL.sql", None, alta_detenida)
    finally:
        correr(QUITA_PAUSA)
    alta_ok = alta[0] == 0 and "ALTA upgrade/upgrade/2026-09" in alta[1]
    return ok and alta_ok, txt + (" · el alta termina bien" if alta_ok else f" · alta NO: {alta[2].strip()[-160:]}")


def t5():
    correr("begin; set local session_replication_role = replica;\n"
           "insert into private.contrato_eliminaciones (contrato_id, token, solicitado_por, objetos)\n"
           f"select c.id, gen_random_uuid(), '{GERENCIA}', '[]'::jsonb from public.contratos c where c.numero_contrato = '2026-01-001445';\n"
           "commit;\n")
    try:
        antes = foto()
        c, salida, s = mensaje(AQUI / "2-REAL.sql", RR)
        despues = foto()
    finally:
        correr("begin; set local session_replication_role = replica;\n"
               "delete from private.contrato_eliminaciones e using public.contratos c\n"
               " where c.id = e.contrato_id and c.numero_contrato = '2026-01-001445';\ncommit;\n")
    ok = c != 0 and "en proceso de eliminación" in salida and antes == despues
    return ok, ("aborta en el 11 de 12 sin escribir nada" if ok else f"NO: {salida.strip()[-200:]} · antes {antes} · después {despues}")


def t6():
    c, salida, s = mensaje(AQUI / "2-REAL.sql", RR)
    ok = c == 0 and "OK: 12 contratos de nuevo a upgrade" in salida and en("upgrade")
    return ok, (f"OK en {s:.1f} s · {foto()}" if ok else f"NO: {salida.strip()[-240:]}")


def t7():
    if ORACULO is None:
        return True, "sin --oraculo: no se corre"
    c, salida, s = mensaje(ORACULO)
    ok = c == 0 and '"veredicto": "PASS"' in salida
    return ok, ("PASS" if ok else salida.strip()[:240])


def t8():
    c, salida, s = mensaje(AQUI / "reversa.sql")
    ok = c == 0 and correr(OBJETOS) == "0"
    return ok, ("esquema retirado" if ok else f"NO: {salida.strip()[-200:]}")


def t9():
    ok, sello, txt = sale_al_instante("reversa-datos.sql", RR, lambda: sello_simulado(4))
    return ok and sello[0] == 0, txt


def t10():
    correr("begin; set local session_replication_role = replica;\n"
           "insert into crm.periodos_cerrados (periodo, cerrado_por, automatico, ponderacion_referido, meta_revision, cobertura,"
           " ponderacion_renovacion) values (date '2026-09-01', null, true, 0.15, 1, '{\"banco\": \"sello simulado confirmado\"}', 0.15);\n"
           "commit;\n")
    try:
        antes = foto()
        c, salida, s = mensaje(AQUI / "reversa-datos.sql", RR)
        despues = foto()
    finally:
        correr("begin; set local session_replication_role = replica;\n"
               "delete from crm.periodos_cerrados where periodo = date '2026-09-01' and cobertura ->> 'banco' = 'sello simulado confirmado';\n"
               "commit;\n")
    ok = c != 0 and "septiembre 2026 ya está sellado" in salida and antes == despues
    return ok, ("se niega («ya está sellado») sin escribir" if ok else f"NO: {salida.strip()[-200:]}")


def t11():
    c, salida, s = mensaje(AQUI / "reversa-datos.sql", RR)
    ok = c == 0 and "OK: 12 contratos de vuelta a nuevo" in salida and en("nuevo")
    return ok, (f"OK en {s:.1f} s · {foto()}" if ok else f"NO: {salida.strip()[-240:]}")


def t12():
    c, salida, s = mensaje(MIGRACION, RR)
    ok = c == 0 and correr(OBJETOS) == "4"
    return ok, ("postflight OK" if ok else f"NO: {salida.strip()[-240:]}")


def main():
    if correr("select coalesce(current_setting('app.settings.jwt_secret', true), '')") != \
            "super-secret-jwt-token-with-at-least-32-characters-long":
        sys.exit("transporte.py solo corre en un banco LOCAL de Docker")
    if correr(OBJETOS) != "4" or not en("nuevo") or candados() != 0 or \
            correr("select count(*) from crm.periodos_cerrados where periodo = date '2026-09-01'") != "0":
        sys.exit("el banco no está en el estado de partida (migración puesta, los 12 en 'nuevo', septiembre abierto, 0 candados)")
    pasos = [("T1 ENSAYO, sesión READ COMMITTED", t1), ("T2 ENSAYO, sesión REPEATABLE READ", t2),
             ("T3 REAL frente a un sello en curso", t3), ("T4 REAL frente a un alta de septiembre detenida", t4),
             ("T5 REAL que falla en el contrato 11", t5), ("T6 REAL, sesión REPEATABLE READ", t6),
             ("T7 oráculo", t7), ("T8 reversa.sql", t8),
             ("T9 reversa-datos frente a un sello en curso", t9), ("T10 reversa-datos con septiembre sellado", t10),
             ("T11 reversa-datos, sesión REPEATABLE READ", t11), ("T12 la migración otra vez, sesión REPEATABLE READ", t12)]
    fallos = []
    for nombre, f in pasos:
        try:
            ok, detalle = f()
        except Exception as e:   # noqa: BLE001
            ok, detalle = False, f"no se pudo correr: {e}"
        restos = candados()
        ok = ok and restos == 0
        print(f"{'OK   ' if ok else 'FALLA'} {nombre} — {detalle} · {restos} candados de aviso")
        if not ok:
            fallos.append(nombre.split(" ")[0])
            if nombre[:3] in ("T6 ", "T8 ", "T11", "T12"):
                break   # un paso que cambia el estado falló: lo que sigue no tendría sentido
    if fallos:
        print(f"TRANSPORTE FALLA: {', '.join(fallos)}")
        sys.exit(1)
    print(f"TRANSPORTE OK {len(pasos)}/{len(pasos)}")


if __name__ == "__main__":
    main()

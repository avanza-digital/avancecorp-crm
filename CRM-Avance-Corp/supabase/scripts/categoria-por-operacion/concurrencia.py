#!/usr/bin/env python3
"""Carreras con DOS conexiones reales (migración 20261009120000). SOLO banco local de Docker, con el mundo de banco/mundo.sql.

Cada escenario crea su propio contrato (queda en el banco; no molesta a prueba.sql) o deshace lo que hace:
  C1  T1 cambia la categoría de un contrato SIN operación ('upgrade' → 'nuevo') y no confirma; T2 registra una operación
      'upgrade' sobre ese contrato. La sincronización bloquea la fila: T2 espera a T1, lee 'nuevo' y lo pasa a 'upgrade'.
      Al final, contrato y operación coinciden (nunca 'nuevo' con operación 'upgrade').
  C2  El orden inverso: T2 registra la operación y no confirma (la sincronización ya bloqueó la fila aunque la categoría
      coincidía); T1 intenta pasar el contrato a 'nuevo' → espera a T2 y recibe 23514. Al final coinciden.
  C3  Orden de candados mes → fila: una sesión que hace de SELLO toma el candado de septiembre, espera y después lee la
      fila (FOR SHARE); mientras, Gerencia corrige ese contrato. Con el orden correcto la corrección espera al mes sin
      tener la fila, así que las dos terminan bien; con el orden al revés, interbloqueo.
  C4  El día comercial cambia mientras la corrección espera el candado del mes (corregir_fecha_cierre_comercial lo mueve
      de septiembre a octubre) → la corrección recibe 40001 («vuelve a intentarlo») y no escribe.
  N1  (Codex r2) Foto REPEATABLE READ anterior a la operación: T1 abre la foto; T2 (READ COMMITTED) registra una operación
      'upgrade' sobre un contrato que YA es 'upgrade' (camino que coincide: no reescribe la fila) y confirma; T1 pasa el
      contrato a 'nuevo' → 25001 (la guarda no busca la operación con una foto vieja). Al final coinciden.
  N2  (Codex r2) Los guiones con una sesión cuyo default_transaction_isolation es 'repeatable read': 1-ENSAYO llega a
      «LISTO PARA 2-REAL» (el núcleo rechaza REPEATABLE READ: llegar ahí prueba READ COMMITTED) y reversa-datos pasa el
      bloque de candados (se para después, en «la prevención sigue puesta»). Con un SELLO de septiembre simulado en curso
      (los candados de crm.cerrar_periodo; recién empezado, o ya con su fila en crm.periodos_cerrados, que escribe
      crm.conversion_acreditaciones), los dos salen AL INSTANTE con «Hay actividad en curso» y sin escribir nada.
  N3  (Codex r2) Un alta REAL de upgrade de septiembre (public.crear_contrato) detenida entre el contrato y su operación
      (ya tiene public.contratos y el candado del mes): 1-ENSAYO y reversa-datos salen al instante con «Hay actividad en
      curso», el alta termina bien (se deshace al final para no dejar datos) y después 1-ENSAYO corre limpio.
  N4  (auditor-rls r2) Corregir la FECHA y la CATEGORÍA del mismo contrato a la vez. crm.corregir_fecha_cierre_comercial
      (pieza previa, no se toca) bloquea la fila y DESPUÉS el mes; el núcleo, el mes y después la fila (orden del sello).
      Con este intercalado Postgres detecta el interbloqueo y aborta una de las dos (40P01: se reintenta); la otra termina.
      Se exige lo que importa: a lo sumo una falla, solo con 40P01, lo que termina deja su efecto y lo que aborta no deja
      nada, y no queda ningún candado (si algún día la corrección de fecha toma el mes primero, las dos terminarán y la
      prueba sigue valiendo).
  Además, antes de todo (P0): el bloque de candados ($candados$) es idéntico en 1-ENSAYO, 2-REAL y reversa-datos, y los
  tres empiezan con `begin isolation level read committed;` (2-REAL no se corre aquí porque escribe: lo prueba
  transporte.py).
Tras cada escenario, otra conexión comprueba que no queda ningún candado de aviso tomado.
Los guiones corren como `postgres` y como UN solo mensaje (`psql -c`), igual que `supabase db query --linked -f`.
Imprime una línea por escenario y al final «CONCURRENCIA OK n/n» o «CONCURRENCIA FALLA: …» (salida 1).

Uso:  python3 -I concurrencia.py [contenedor] [--solo P0,N3]   (por defecto supabase_db_avancecorp-categoria-20261008)
      CATEGORIA_GUIONES=<carpeta> toma los guiones de otra carpeta (mutantes.py la usa para los guiones mutados).
"""
import os
import pathlib
import re
import subprocess
import sys
import time
import uuid

AQUI = pathlib.Path(__file__).resolve().parent
GUIONES = pathlib.Path(os.environ.get("CATEGORIA_GUIONES") or AQUI)
SOLO = None
ARGS = sys.argv[1:]
if "--solo" in ARGS:
    i = ARGS.index("--solo")
    SOLO = set(ARGS[i + 1].split(","))
    ARGS = ARGS[:i] + ARGS[i + 2:]
CONTENEDOR = ARGS[0] if ARGS else "supabase_db_avancecorp-categoria-20261008"
GERENCIA = "ca7e0000-0000-4000-8000-000000000001"
ADMIN = "ca7e0000-0000-4000-8000-00000000000b"
ANALISTA = "ca7e0000-0000-4000-8000-000000000003"
CLIENTE = "ca7e0000-0000-4000-8000-000000000110"     # cliente 16 del mundo
SEPTIEMBRE = "(date '2026-09-01' - date '2000-01-01')::integer"
RR = "-c default_transaction_isolation=repeatable\\ read"
ACTIVIDAD = "Hay actividad en curso: vuelve a correr el guion en unos minutos"
RAPIDO = 2.0   # segundos: «al instante» (incluye el arranque de docker exec y de psql)


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
    out = p.stdout.read()
    err = p.stderr.read()
    p.wait(timeout=90)
    return p.returncode, out, err


def guion(nombre, opciones=None):
    """Corre un guion como UN solo mensaje (psql -c), como postgres. Devuelve (código, salida+error, segundos)."""
    texto = (GUIONES / nombre).read_text(encoding="utf-8")
    t0 = time.monotonic()
    r = subprocess.run(psql_args("postgres", opciones) + ["-c", texto], capture_output=True, text=True, timeout=240)
    return r.returncode, r.stdout + r.stderr, time.monotonic() - t0


def candados_de_aviso():
    return int(correr("select count(*) from pg_locks where locktype = 'advisory';") or 0)


def como_gerencia(sql):
    return (f"select set_config('request.jwt.claims', '{{\"sub\": \"{GERENCIA}\", \"role\": \"authenticated\"}}', true);\n"
            f"select set_config('request.jwt.claim.sub', '{GERENCIA}', true);\n"
            f"set local role authenticated;\n{sql}")


def contrato(categoria_final, con_operacion=False, fecha="2026-09-21"):
    """Crea un contrato (nace 'nuevo' por la vía normal) y lo deja en categoria_final; con_operacion = op upgrade previa
    insertada SIN sincronizar (replica), es decir, el estado incoherente de producción."""
    cid = str(uuid.uuid4())
    numero = "CAT-CC-" + cid[:8]
    sql = f"""
insert into public.contratos (id, numero_contrato, cliente_id, capital, moneda, tasa_anual, modalidad, tipo_interes,
                              fecha_inicio, fecha_vencimiento, estado, categoria, creado_por, analista_cierre_id)
values ('{cid}', '{numero}', '{CLIENTE}', 30000, 'PEN', 15, 'mensual', 'simple', date '{fecha}',
        (date '{fecha}' + interval '12 months')::date, 'activo', 'nuevo', '{ADMIN}', '{ANALISTA}');
"""
    if categoria_final != "nuevo":
        # Un 'upgrade' ANTIGUO sin operación (como los ~106 de marzo a julio): desde 20261009180000 la guarda ya no deja
        # crearlo con un UPDATE (sin operación, solo 'nuevo'), así que el fixture la apaga SOLO durante este UPDATE (el
        # resto de triggers corre, como cuando nacieron). Con la guarda de 20261009120000, el apagado no cambia nada. Los
        # diferidos del UPDATE (observador de rentabilidad) se disparan antes de volver a encenderla: ALTER TABLE no
        # admite eventos pendientes (es lo mismo que haría el commit).
        sql += (f"begin;\nalter table public.contratos disable trigger trg_contratos_01_categoria_por_operacion;\n"
                f"update public.contratos set categoria = '{categoria_final}' where id = '{cid}';\n"
                f"set constraints all immediate;\n"
                f"alter table public.contratos enable trigger trg_contratos_01_categoria_por_operacion;\ncommit;\n")
    if con_operacion:
        sql += f"""
begin;
set local session_replication_role = replica;
insert into crm.operaciones_cartera (cliente_id, vendedor_id, tipo, contrato_nuevo_id, fecha_operacion, periodo, moneda,
                                     elegible_conversion, desglose_completo, fuente, creado_por)
select c.cliente_id, c.analista_cierre_id, 'upgrade', c.id, c.fecha_cierre_comercial,
       date_trunc('month', c.fecha_cierre_comercial)::date, c.moneda, true, true, 'flujo_cartera', '{ADMIN}'
  from public.contratos c where c.id = '{cid}';
commit;
"""
    correr(sql)
    return cid


def insertar_operacion(cid, espera_antes_de_confirmar=0.0):
    pausa = f"select pg_sleep({espera_antes_de_confirmar});\n" if espera_antes_de_confirmar else ""
    return f"""begin;
insert into crm.operaciones_cartera (cliente_id, vendedor_id, tipo, contrato_nuevo_id, fecha_operacion, periodo, moneda,
                                     elegible_conversion, desglose_completo, fuente, creado_por)
select c.cliente_id, c.analista_cierre_id, 'upgrade', c.id, c.fecha_cierre_comercial,
       date_trunc('month', c.fecha_cierre_comercial)::date, c.moneda, true, true, 'flujo_cartera', '{ADMIN}'
  from public.contratos c where c.id = '{cid}';
{pausa}commit;
"""


def estado(cid):
    return correr(f"select coalesce(c.categoria, '-') || '|' || coalesce(o.tipo, '-') from public.contratos c "
                  f"left join crm.operaciones_cartera o on o.contrato_nuevo_id = c.id where c.id = '{cid}';")


def coherente(cid):
    cat, op = estado(cid).split("|")
    return op == "-" or cat == op, f"{cat}/{op}"


def c1():
    cid = contrato("upgrade")
    t1 = lanzar(f"begin;\nupdate public.contratos set categoria = 'nuevo' where id = '{cid}';\nselect pg_sleep(2);\ncommit;\n")
    time.sleep(0.6)
    t2 = lanzar(insertar_operacion(cid))
    r1, r2 = esperar(t1), esperar(t2)
    ok, est = coherente(cid)
    return ok, f"T1 {'ok' if r1[0] == 0 else 'falló'} · T2 {'ok' if r2[0] == 0 else 'falló'} · final {est}"


def c2():
    cid = contrato("upgrade")
    t2 = lanzar(insertar_operacion(cid, espera_antes_de_confirmar=2))
    time.sleep(0.6)
    t1 = lanzar(f"begin;\nupdate public.contratos set categoria = 'nuevo' where id = '{cid}';\ncommit;\n")
    r2, r1 = esperar(t2), esperar(t1)
    ok, est = coherente(cid)
    rechazo = r1[0] != 0 and "La categoría la decide la operación de cartera" in r1[2]
    return ok and rechazo and r2[0] == 0, f"T2 {'ok' if r2[0] == 0 else 'falló'} · T1 {'23514' if rechazo else 'NO rechazado: ' + r1[2].strip()[:120]} · final {est}"


def c3():
    cid = contrato("nuevo", con_operacion=True)
    sello = lanzar(f"begin;\nselect pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'), {SEPTIEMBRE});\n"
                   f"select pg_sleep(1.5);\nselect 1 from public.contratos where id = '{cid}' for share;\n"
                   f"select pg_sleep(0.5);\ncommit;\n")
    time.sleep(0.5)
    puerta = lanzar("begin;\n" + como_gerencia(
        f"select crm.corregir_categoria_contrato_fn('{cid}', 'upgrade', 'Prueba de concurrencia: orden de candados');\n") + "commit;\n")
    rs, rp = esperar(sello), esperar(puerta)
    ok, est = coherente(cid)
    return rs[0] == 0 and rp[0] == 0 and est == "upgrade/upgrade", \
        f"sello {'ok' if rs[0] == 0 else 'falló: ' + rs[2].strip()[:100]} · puerta {'ok' if rp[0] == 0 else 'falló: ' + rp[2].strip()[:100]} · final {est}"


def c4():
    cid = contrato("nuevo", con_operacion=True)
    fecha = lanzar("begin;\n" + como_gerencia(
        f"select crm.corregir_fecha_cierre_comercial('{cid}', date '2026-10-02', 'Prueba de concurrencia del día comercial');\n")
        + "select pg_sleep(1.5);\ncommit;\n")
    time.sleep(0.6)
    puerta = lanzar("begin;\n" + como_gerencia(
        f"select crm.corregir_categoria_contrato_fn('{cid}', 'upgrade', 'Prueba de concurrencia: el mes cambió');\n") + "commit;\n")
    rf, rp = esperar(fecha), esperar(puerta)
    est = estado(cid)
    reintenta = rp[0] != 0 and "vuelve a intentarlo" in rp[2]
    return rf[0] == 0 and reintenta and est.startswith("nuevo|"), \
        f"fecha {'ok' if rf[0] == 0 else 'falló: ' + rf[2].strip()[:100]} · puerta {'40001 (reintenta)' if reintenta else 'NO: ' + (rp[2].strip()[:120] or 'pasó')} · final {est}"


def n1():
    cid = contrato("upgrade")    # legacy 'upgrade' sin operación: la operación llegará por el camino que coincide
    t1 = lanzar("begin isolation level repeatable read;\n"
                "select count(*) from crm.operaciones_cartera;\n"          # la foto se toma AQUÍ, antes de la operación
                "select pg_sleep(1.5);\n"
                f"update public.contratos set categoria = 'nuevo' where id = '{cid}';\n"
                "commit;\n")
    time.sleep(0.5)
    r2 = subprocess.run(psql_args(), input=insertar_operacion(cid), capture_output=True, text=True)
    r1 = esperar(t1)
    ok, est = coherente(cid)
    rechazo = r1[0] != 0 and "solo se cambia en una transacción READ COMMITTED" in r1[2]
    return ok and rechazo and r2.returncode == 0 and est == "upgrade/upgrade", \
        (f"T2 {'ok' if r2.returncode == 0 else 'falló: ' + r2.stderr.strip()[:100]} · "
         f"T1 {'25001' if rechazo else 'NO rechazado: ' + (r1[2].strip()[:140] or 'pasó')} · final {est}")


def sello_simulado(pausa, con_fila):
    """Los candados de crm.cerrar_periodo (global, mes, SHARE sobre crm.equipo); con_fila = además su fila en
    crm.periodos_cerrados (su trigger escribe crm.conversion_acreditaciones). Siempre se deshace."""
    fila = ("insert into crm.periodos_cerrados (periodo, cerrado_por, automatico, ponderacion_referido, meta_revision, "
            "cobertura, ponderacion_renovacion) values (date '2026-09-01', null, true, 0.15, 1, "
            "'{\"banco\": \"sello simulado\"}', 0.15);\n") if con_fila else ""
    return lanzar("begin;\n"
                  "select pg_advisory_xact_lock(hashtext('crm.periodos_cerrados')::bigint);\n"
                  f"select pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'), {SEPTIEMBRE});\n"
                  "lock table crm.equipo in share mode;\n"
                  f"{fila}select pg_sleep({pausa});\nrollback;\n")


def n2():
    detalle, ok = [], True
    sesion = subprocess.run(psql_args("postgres", RR) + ["-c", "show default_transaction_isolation"],
                            capture_output=True, text=True).stdout.strip()
    if sesion != "repeatable read":
        return False, f"la sesión de prueba no quedó en repeatable read (quedó «{sesion}»)"
    c, salida, s = guion("1-ENSAYO.sql", RR)
    listo = "LISTO PARA 2-REAL" in salida
    ok &= listo
    detalle.append(f"ENSAYO bajo RR {'LISTO' if listo else 'NO: ' + salida.strip()[-160:]}")
    c, salida, s = guion("reversa-datos.sql", RR)
    paso = "la prevención sigue puesta" in salida
    ok &= paso
    detalle.append(f"reversa-datos bajo RR {'pasa los candados' if paso else 'NO: ' + salida.strip()[-160:]}")
    for etiqueta, con_fila, motivo in (("recién empezado", False, "el mes de septiembre"),
                                       ("con su fila", True, "una de las tablas")):
        sello = sello_simulado(4, con_fila)
        time.sleep(1.0)
        for nombre in ("1-ENSAYO.sql", "reversa-datos.sql"):
            c, salida, s = guion(nombre, RR)
            rapido = c != 0 and ACTIVIDAD in salida and motivo in salida and s < RAPIDO
            ok &= rapido
            detalle.append(f"sello {etiqueta} → {nombre.split('.')[0]} "
                           + (f"sale en {s:.1f} s ({motivo})" if rapido else f"NO: {s:.1f} s {salida.strip()[-140:]}"))
        rs = esperar(sello)
        ok &= rs[0] == 0
    return ok, " · ".join(detalle)


def n4():
    cid = contrato("nuevo", con_operacion=True)           # incoherente: la puerta tendría que escribir
    sello = lanzar(f"begin;\nselect pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'), {SEPTIEMBRE});\n"
                   "select pg_sleep(2);\ncommit;\n")
    time.sleep(0.3)
    puerta = lanzar("begin;\n" + como_gerencia(
        f"select crm.corregir_categoria_contrato_fn('{cid}', 'upgrade', 'Prueba: fecha y categoría a la vez');\n") + "commit;\n")
    time.sleep(0.5)
    fecha = lanzar("begin;\n" + como_gerencia(
        f"select crm.corregir_fecha_cierre_comercial('{cid}', date '2026-09-25', 'Prueba: fecha y categoría a la vez');\n")
        + "commit;\n")
    rs, rp, rf = esperar(sello), esperar(puerta), esperar(fecha)
    est = estado(cid)
    dia = correr(f"select fecha_cierre_comercial from public.contratos where id = '{cid}';")
    fallos = [r for r in (rp, rf) if r[0] != 0]
    solo_40p01 = all("deadlock detected" in r[2] for r in fallos)
    # Lo que termina deja su efecto; lo que aborta no deja NADA (el contrato empezó como los 12: nuevo con operación upgrade).
    efecto_ok = (est == ("upgrade|upgrade" if rp[0] == 0 else "nuevo|upgrade")) and \
                (dia == ("2026-09-25" if rf[0] == 0 else "2026-09-21"))

    def res(r):
        return "ok" if r[0] == 0 else ("40P01" if "deadlock detected" in r[2] else r[2].strip()[:100])
    return rs[0] == 0 and len(fallos) <= 1 and solo_40p01 and efecto_ok, \
        f"puerta {res(rp)} · fecha {res(rf)} · final {est.replace('|', '/')} del {dia} (lo que abortó no escribió nada)"


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


def n3():
    numero = "CAT-N3-" + uuid.uuid4().hex[:8]
    detalle, ok = [], True
    correr(PAUSA_ALTA)
    try:
        alta = lanzar(f"""begin;
select set_config('prueba.pausa_alta', '5', true);
select set_config('crm.rentabilidad_origen_upgrade', 'ca7e0000-0000-4000-8000-00000000010e|ca7e0000-0000-4000-8000-00000000110e', true);
{como_gerencia('')}select (public.crear_contrato(
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
        time.sleep(1.0)
        for nombre in ("1-ENSAYO.sql", "reversa-datos.sql"):
            c, salida, s = guion(nombre)
            rapido = c != 0 and ACTIVIDAD in salida and s < RAPIDO
            ok &= rapido
            detalle.append(f"{nombre.split('.')[0]} " + (f"sale en {s:.1f} s" if rapido else f"NO: {s:.1f} s {salida.strip()[-140:]}"))
        ra = esperar(alta)
        alta_ok = ra[0] == 0 and "ALTA upgrade/upgrade/2026-09" in ra[1] and "deadlock" not in ra[2]
        ok &= alta_ok
        detalle.append("el alta de septiembre termina bien" if alta_ok else f"alta NO: {ra[2].strip()[-160:]}")
    finally:
        correr(QUITA_PAUSA)
    c, salida, s = guion("1-ENSAYO.sql")
    limpio = "LISTO PARA 2-REAL" in salida
    ok &= limpio
    detalle.append("después, ENSAYO limpio (LISTO)" if limpio else f"después, ENSAYO NO: {salida.strip()[-160:]}")
    return ok, " · ".join(detalle)


def preludio_igual():
    bloques, primeras = {}, {}
    for nombre in ("1-ENSAYO.sql", "2-REAL.sql", "reversa-datos.sql"):
        texto = (GUIONES / nombre).read_text(encoding="utf-8")
        m = re.search(r"^do \$candados\$\n.*?^\$candados\$;\n", texto, re.S | re.M)
        bloques[nombre] = m.group(0) if m else None
        primeras[nombre] = next((linea for linea in texto.splitlines() if linea.strip() and not linea.startswith("--")), "")
        if any(linea.startswith("\\") for linea in texto.splitlines()):
            return False, f"{nombre} tiene comandos de psql (no viajaría como un solo mensaje)"
    if None in bloques.values() or len(set(bloques.values())) != 1:
        return False, "el bloque $candados$ falta o no es idéntico en los tres guiones"
    if set(primeras.values()) != {"begin isolation level read committed;"}:
        return False, f"no todos empiezan con begin isolation level read committed: {primeras}"
    return True, "bloque $candados$ idéntico en los tres; los tres abren en READ COMMITTED"


def main():
    escenarios = [("P0 preludio de los guiones", preludio_igual),
                  ("C1 T1 cambia la categoría y T2 registra la operación", c1),
                  ("C2 T2 registra la operación y T1 cambia la categoría", c2),
                  ("C3 orden de candados mes → fila frente al sello", c3),
                  ("C4 el día comercial cambia mientras se espera el mes", c4),
                  ("N1 foto REPEATABLE READ anterior a la operación frente a la guarda", n1),
                  ("N2 guiones bajo REPEATABLE READ por defecto y frente a un sello en curso", n2),
                  ("N3 guiones frente a un alta de septiembre detenida entre contrato y operación", n3),
                  ("N4 corregir la fecha y la categoría del mismo contrato a la vez", n4)]
    if SOLO:
        escenarios = [e for e in escenarios if e[0].split(" ")[0] in SOLO]
    fallos = []
    for nombre, f in escenarios:
        try:
            ok, detalle = f()
        except Exception as e:   # noqa: BLE001 — un escenario que no se pudo montar cuenta como fallo
            ok, detalle = False, f"no se pudo correr: {e}"
        if not nombre.startswith("P0"):
            restos = candados_de_aviso()
            if restos:
                ok, detalle = False, detalle + f" · QUEDAN {restos} candados de aviso"
            else:
                detalle += " · 0 candados de aviso"
        print(f"{'OK   ' if ok else 'FALLA'} {nombre} — {detalle}")
        if not ok:
            fallos.append(nombre.split(" ")[0])
    if fallos:
        print(f"CONCURRENCIA FALLA: {', '.join(fallos)}")
        sys.exit(1)
    print(f"CONCURRENCIA OK {len(escenarios)}/{len(escenarios)}")


if __name__ == "__main__":
    main()

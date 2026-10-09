#!/usr/bin/env python3
"""Mutantes de la migración 20261009120000 (categoría por operación). SOLO banco local de Docker.

Cada mutante de FUNCIÓN cambia UN trozo de una función (texto exacto, que tiene que aparecer una sola vez) y/o la
definición del trigger de public.contratos, corre prueba.sql (incluida su transacción REPEATABLE READ) y concurrencia.py
(dos conexiones), y lo repone todo byte a byte (se comprueba el md5 del cuerpo y la definición del trigger). Cada mutante
de GUION cambia el bloque de candados de 1-ENSAYO, 2-REAL y reversa-datos (copias en una carpeta temporal; los archivos
del repo no se tocan) y corre los escenarios de concurrencia.py que usan los guiones. Un mutante MUERE si la suite termina
en «PRUEBA CATEGORIA FALLA» (fallo de aserción) o las carreras en «CONCURRENCIA FALLA»; SOBREVIVE si todo termina en OK.
Cualquier otra salida (SQL inválido, la suite revienta) aborta la corrida: no se cuenta como muerte.
Dos controles se declaran SUPERVIVIENTES a propósito (defensa duplicada, no observable desde SQL); si alguno muere, se avisa.
La corrida falla si sobrevive un mutante que debía morir.

Uso:  python3 -I mutantes.py [contenedor]      (por defecto supabase_db_avancecorp-categoria-20261008)
"""
import os
import pathlib
import re
import subprocess
import sys
import tempfile

AQUI = pathlib.Path(__file__).resolve().parent
SUITE = (AQUI / "prueba.sql").read_text(encoding="utf-8")
CONTENEDOR = sys.argv[1] if len(sys.argv) > 1 else "supabase_db_avancecorp-categoria-20261008"

NUCLEO = "private.fijar_categoria_contrato(uuid,text,text,text,uuid)"
PUERTA = "crm.corregir_categoria_contrato_fn(uuid,text,text)"
GUARDA = "private.trg_contrato_categoria_por_operacion()"
SINCRONIA = "private.trg_operacion_cartera_fija_categoria()"
TRIGGER_GUARDA = ("public.contratos", "trg_contratos_01_categoria_por_operacion")
GUARDA_SIN_WHEN = ("create trigger trg_contratos_01_categoria_por_operacion after update on public.contratos "
                   "for each row execute function private.trg_contrato_categoria_por_operacion()")
GUARDA_BEFORE = ("create trigger trg_contratos_01_categoria_por_operacion before update of categoria on public.contratos "
                 "for each row execute function private.trg_contrato_categoria_por_operacion()")
RESTAURA_PDF_Y_ORIGEN = ("  perform pg_catalog.set_config('crm.contrato_pdf_revision_autorizada', v_guc_previo, true);\n"
                         "  perform pg_catalog.set_config('crm.rentabilidad_origen_upgrade', v_origen_previo, true);\n\n")

# (clave, descripción, [(función, [(texto original, reemplazo), ...]), ...], trigger nuevo o None, ¿debe morir?)
MUTANTES = [
    ("M1", "sin rechazo de mes sellado (núcleo: puerta y sincronización)",
     [(NUCLEO, [("  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo) then",
                 "  if false and exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo) then")])], None, True),
    ("M2", "sin respaldo (núcleo: con operación = la de la operación; sin operación solo nuevo)",
     [(NUCLEO, [("  if v_operacion_id is not null then\n    if p_categoria is distinct from v_operacion_tipo then",
                 "  if false and v_operacion_id is not null then\n    if p_categoria is distinct from v_operacion_tipo then"),
                ("  elsif p_categoria <> 'nuevo' then", "  elsif false then")])], None, True),
    ("M3", "sin rol (la puerta deja pasar a cualquier sesión)",
     [(PUERTA, [("  if v_uid is null or v_rol is distinct from 'gerencia'\n     or (select private.membresia_crm_revocada()) is not false then",
                 "  if v_uid is null then")])], None, True),
    ("M4", "trigger de public.contratos sin efecto",
     [(GUARDA, [("  if found and new.categoria is distinct from v_tipo then",
                 "  if false and found and new.categoria is distinct from v_tipo then")])], None, True),
    ("M5", "congelación del PDF sin cerrar tras el UPDATE (núcleo)",
     [(NUCLEO, [(RESTAURA_PDF_Y_ORIGEN,
                 "  perform pg_catalog.set_config('crm.rentabilidad_origen_upgrade', v_origen_previo, true);\n\n")])], None, True),
    ("M6", "sin fila de motivo en public.audit_log (núcleo)",
     [(NUCLEO, [("  insert into public.audit_log (tabla, operacion, fila_id, usuario_id, data_antes, data_despues)\n  values (\n    'contratos.categoria'",
                 "  if false then insert into public.audit_log (tabla, operacion, fila_id, usuario_id, data_antes, data_despues)\n  values (\n    'contratos.categoria'"),
                ("                       'operacion_id', v_operacion_id, 'operacion_tipo', v_operacion_tipo)\n  );",
                 "                       'operacion_id', v_operacion_id, 'operacion_tipo', v_operacion_tipo)\n  ); end if;")])], None, True),
    ("M7", "sincronización desactivada (la operación ya no fija la categoría)",
     [(SINCRONIA, [("  if v_categoria is not distinct from new.tipo then\n    return null;\n  end if;\n  perform private.fijar_categoria_contrato(",
                    "  if true then\n    return null;\n  end if;\n  perform private.fijar_categoria_contrato(")])], None, True),
    ("M8", "la sincronización borra la declaración de origen también en el alta normal",
     [(SINCRONIA, [("  if v_categoria is not distinct from new.tipo then\n    return null;",
                    "  perform pg_catalog.set_config('crm.rentabilidad_origen_upgrade', '', true);\n"
                    "  if v_categoria is not distinct from new.tipo then\n    return null;")])], None, True),
    ("M9", "sin idempotencia (vuelve a escribir aunque ya tenga la categoría)",
     [(NUCLEO, [("  if v_contrato.categoria is not distinct from p_categoria then", "  if false then")])], None, True),
    ("M10", "el núcleo no vacía la declaración de origen durante el UPDATE (la corrección heredaría tasa)",
     [(NUCLEO, [("  perform pg_catalog.set_config('crm.rentabilidad_origen_upgrade', '', true);", "  perform 1;")])], None, True),
    ("M11", "sin comprobar que el contrato se está eliminando",
     [(NUCLEO, [("  if private.contrato_en_eliminacion(p_contrato_id) then", "  if false then")])], None, True),
    ("M12", "la puerta no valida el motivo (lo valida el núcleo con otro mensaje)",
     [(PUERTA, [("  if v_motivo is null or length(v_motivo) < 5 or length(v_motivo) > 300 then", "  if false then")])], None, True),
    ("M13", "la guarda revisa aunque la categoría NO cambie (sin WHEN ni salida temprana: rompería «Corregir»)",
     [(GUARDA, [("  if new.categoria is not distinct from old.categoria then\n    return new;\n  end if;\n",
                 "  -- (mutante: sin salida temprana)\n")])], GUARDA_SIN_WHEN, True),
    ("M14", "F1 · la sincronización lee la categoría SIN bloquear la fila (carrera con un UPDATE en curso)",
     [(SINCRONIA, [("    from public.contratos c where c.id = new.contrato_nuevo_id for update;",
                    "    from public.contratos c where c.id = new.contrato_nuevo_id;")])], None, True),
    ("M15", "F2 · el núcleo acepta REPEATABLE READ (foto vieja frente al sello)",
     [(NUCLEO, [("  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then", "  if false then")])], None, True),
    ("M16", "F3 · orden de candados invertido en el núcleo (la fila antes que el mes)",
     [(NUCLEO, [("  select c.fecha_cierre_comercial into v_fecha from public.contratos c where c.id = p_contrato_id;",
                 "  select c.fecha_cierre_comercial into v_fecha from public.contratos c where c.id = p_contrato_id for update;")])], None, True),
    ("M17", "F5 · la guarda vuelve a ser BEFORE UPDATE OF categoria (no ve lo que otro BEFORE cambie)",
     [], GUARDA_BEFORE, True),
    ("M18", "F6a · el núcleo no repone la declaración de origen pendiente (la pierde un alta de la misma transacción)",
     [(NUCLEO, [(RESTAURA_PDF_Y_ORIGEN,
                 "  perform pg_catalog.set_config('crm.contrato_pdf_revision_autorizada', v_guc_previo, true);\n\n")])], None, True),
    ("M19", "F3 · el núcleo no revalida el mes después de bloquear la fila",
     [(NUCLEO, [("  if date_trunc('month', v_contrato.fecha_cierre_comercial)::date is distinct from v_periodo then",
                 "  if false then")])], None, True),
    ("M20", "N1 · la guarda acepta REPEATABLE READ (con una foto vieja no ve una operación recién confirmada)",
     [(GUARDA, [("  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then\n"
                 "    raise exception 'La categoría de un contrato solo se cambia",
                 "  if false then\n    raise exception 'La categoría de un contrato solo se cambia")])], None, True),
    ("M21", "N1 · la sincronización acepta REPEATABLE READ (también por el camino que coincide)",
     [(SINCRONIA, [("  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then\n"
                    "    raise exception 'Una renovación o un upgrade",
                    "  if false then\n    raise exception 'Una renovación o un upgrade")])], None, True),
    # Supervivientes A PROPÓSITO (defensa duplicada): se corren para dejar constancia.
    ("C1", "CONTROL · sin reponer los GUC cuando el UPDATE falla: Postgres ya los revierte al abortar la subtransacción, "
           "así que no se ve desde SQL (se mantiene como cinturón, igual que las puertas pdf_v3)",
     [(NUCLEO, [("  exception when others then\n"
                 "    perform pg_catalog.set_config('crm.contrato_pdf_revision_autorizada', v_guc_previo, true);\n"
                 "    perform pg_catalog.set_config('crm.rentabilidad_origen_upgrade', v_origen_previo, true);\n"
                 "    raise;",
                 "  exception when others then\n    raise;")])], None, False),
    ("C2", "CONTROL · la puerta no pregunta por la membresía revocada: private.rol_crm ya exige equipo.activo",
     [(PUERTA, [("  if v_uid is null or v_rol is distinct from 'gerencia'\n     or (select private.membresia_crm_revocada()) is not false then",
                 "  if v_uid is null or v_rol is distinct from 'gerencia' then")])], None, False),
]


# Mutantes de GUION: (clave, descripción, [(texto original, reemplazo), ...] en CADA uno de los tres guiones, escenarios).
GUIONES = ("1-ENSAYO.sql", "2-REAL.sql", "reversa-datos.sql")
MUTANTES_GUION = [
    ("G1", "N3 · los guiones sin NOWAIT (esperan al alta o al sello en vez de salir al instante)",
     [("      in share mode nowait;\n", "      in share mode;\n"), ("       for update nowait;\n", "       for update;\n")],
     "N2,N3"),
    ("G2", "N2 · los guiones heredan el aislamiento de la sesión (BEGIN sin READ COMMITTED)",
     [("begin isolation level read committed;\n", "begin;\n")], "N2"),
]


def psql(sql, *extra):
    r = subprocess.run(
        ["docker", "exec", "-i", "-e", "PGPASSWORD=postgres", CONTENEDOR, "psql", "-X", "-q", "-U", "supabase_admin",
         "-h", "127.0.0.1", "-d", "postgres", "-v", "ON_ERROR_STOP=1", *extra],
        input=sql, capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def carreras(guiones=None, solo=None):
    entorno = dict(os.environ, CATEGORIA_GUIONES=str(guiones)) if guiones else None
    return subprocess.run([sys.executable, "-I", str(AQUI / "concurrencia.py"), CONTENEDOR] + (["--solo", solo] if solo else []),
                          capture_output=True, text=True, env=entorno)


def casos_que_fallan(out, salida, rc_stdout):
    casos = [c.split(" ")[0] for c in re.findall(r"\| ([A-Z]\d+[a-z]? [^|]*?) \| FALLA", out)]
    linea = next((l for l in salida.splitlines() if "PRUEBA CATEGORIA FALLA: aislamiento" in l), "")
    casos += sorted(set(re.findall(r"\b(F2[a-z])\b", linea)))
    casos += re.findall(r"^FALLA ([CNP]\d)", rc_stdout, re.M)
    return casos


def leer(firma):
    code, out, err = psql(f"select pg_get_functiondef('{firma}'::regprocedure) || '<<FIN>>', "
                          f"md5(prosrc) from pg_proc where oid = '{firma}'::regprocedure;", "-At", "-F", "\x1f")
    if code != 0:
        sys.exit(f"no se pudo leer {firma}: {err}")
    definicion, huella_md5 = out.rsplit("\x1f", 1)
    return definicion.split("<<FIN>>")[0], huella_md5.strip()


def huella(firma):
    return psql(f"select md5(prosrc) from pg_proc where oid = '{firma}'::regprocedure;", "-At")[1].strip()


def trigger_def():
    tabla, nombre = TRIGGER_GUARDA
    return psql(f"select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = '{tabla}'::regclass "
                f"and t.tgname = '{nombre}';", "-At")[1].strip()


def poner_trigger(definicion):
    tabla, nombre = TRIGGER_GUARDA
    return psql(f"begin;\ndrop trigger {nombre} on {tabla};\n{definicion};\ncommit;\n")


def main():
    code, out, err = psql("select 1;", "-At")
    if code != 0:
        sys.exit(f"no hay banco en {CONTENEDOR}: {err}")
    # La suite y las carreras tienen que pasar ANTES (si no, un «muere» no significaría nada).
    code, out, err = psql(SUITE)
    if "PRUEBA CATEGORIA OK" not in out or "PRUEBA AISLAMIENTO OK" not in out:
        sys.exit("la suite NO pasa sin mutantes: arreglar antes de mutar\n" + (err[-2000:] or out[-2000:]))
    rc = carreras()
    if rc.returncode != 0:
        sys.exit("las carreras NO pasan sin mutantes:\n" + rc.stdout[-1500:] + rc.stderr[-500:])
    trigger_original = trigger_def()
    filas, mal = [], []
    for clave, descripcion, cambios, trigger_nuevo, debe_morir in MUTANTES:
        originales = {}
        for firma, trozos in cambios:
            original, md5_original = leer(firma)
            originales[firma] = (original, md5_original)
            mutado = original
            for antes, despues in trozos:
                n = mutado.count(antes)
                if n != 1:
                    sys.exit(f"{clave}: el trozo a mutar aparece {n} veces en {firma} (tiene que ser 1)")
                mutado = mutado.replace(antes, despues)
            code, out, err = psql(mutado + ";\n")
            if code != 0:
                sys.exit(f"{clave}: el mutante NO compila (aborta la corrida): {err.strip()[:400]}")
        if trigger_nuevo:
            code, out, err = poner_trigger(trigger_nuevo)
            if code != 0:
                sys.exit(f"{clave}: el trigger mutante NO se pudo crear: {err.strip()[:400]}")
        try:
            code, out, err = psql(SUITE)
            rc = carreras()
        finally:
            for firma, (original, md5_original) in originales.items():
                c2, o2, e2 = psql(original + ";\n")
                if c2 != 0 or huella(firma) != md5_original:
                    sys.exit(f"{clave}: NO se pudo reponer {firma} (revisar el banco a mano): {e2}")
            if trigger_nuevo:
                c3, o3, e3 = poner_trigger(trigger_original)
                if c3 != 0 or trigger_def() != trigger_original:
                    sys.exit(f"{clave}: NO se pudo reponer el trigger (revisar el banco a mano): {e3}")
        salida = out + err
        suite_falla = "PRUEBA CATEGORIA FALLA" in salida
        suite_ok = "PRUEBA CATEGORIA OK" in salida and "PRUEBA AISLAMIENTO OK" in salida
        carreras_falla = "CONCURRENCIA FALLA" in rc.stdout
        carreras_ok = "CONCURRENCIA OK" in rc.stdout
        if not (suite_falla or suite_ok) or not (carreras_falla or carreras_ok):
            sys.exit(f"{clave}: sin veredicto (no cuenta como muerte):\n{salida[-1200:]}\n{rc.stdout[-600:]}{rc.stderr[-300:]}")
        casos = casos_que_fallan(out, salida, rc.stdout)
        if suite_falla or carreras_falla:
            estado, quien = "MUERE", ", ".join(casos[:14]) or "(veredicto de la suite)"
        else:
            estado, quien = "SOBREVIVE", "-"
        filas.append((clave, estado, descripcion, quien))
        if debe_morir and estado != "MUERE":
            mal.append(clave)
        if not debe_morir and estado == "MUERE":
            print(f"(aviso) el control {clave} murió: la defensa no era tan duplicada como se creía")
    # Mutantes de guion: copias mutadas de los tres guiones en una carpeta temporal; solo los escenarios que los usan.
    for clave, descripcion, trozos, solo in MUTANTES_GUION:
        with tempfile.TemporaryDirectory(prefix="categoria-mutante-") as carpeta:
            for nombre in GUIONES:
                texto = (AQUI / nombre).read_text(encoding="utf-8")
                for antes, despues in trozos:
                    if texto.count(antes) != 1:
                        sys.exit(f"{clave}: el trozo a mutar aparece {texto.count(antes)} veces en {nombre} (tiene que ser 1)")
                    texto = texto.replace(antes, despues)
                (pathlib.Path(carpeta) / nombre).write_text(texto, encoding="utf-8")
            rc = carreras(carpeta, solo)
        if "CONCURRENCIA FALLA" not in rc.stdout and "CONCURRENCIA OK" not in rc.stdout:
            sys.exit(f"{clave}: sin veredicto (no cuenta como muerte):\n{rc.stdout[-600:]}{rc.stderr[-300:]}")
        if "CONCURRENCIA FALLA" in rc.stdout:
            estado, quien = "MUERE", ", ".join(re.findall(r"^FALLA ([CNP]\d)", rc.stdout, re.M))
        else:
            estado, quien = "SOBREVIVE", "-"
        filas.append((clave, estado, descripcion, quien))
        if estado != "MUERE":
            mal.append(clave)
    ancho = max(len(f[0]) for f in filas)
    for clave, estado, descripcion, quien in filas:
        print(f"{clave.ljust(ancho)}  {estado:9}  {descripcion}\n{' ' * (ancho + 13)}casos que fallan: {quien}")
    muertos = sum(1 for f in filas if f[1] == "MUERE" and not f[0].startswith("C"))
    esperados = sum(1 for m in MUTANTES if m[4]) + len(MUTANTES_GUION)
    print(f"\n{muertos} de {esperados} mutantes que deben morir, MUEREN; controles: "
          + ", ".join(f"{f[0]} {f[1]}" for f in filas if f[0].startswith("C")))
    if mal:
        sys.exit(f"SOBREVIVEN mutantes que debían morir: {', '.join(mal)}")


if __name__ == "__main__":
    main()

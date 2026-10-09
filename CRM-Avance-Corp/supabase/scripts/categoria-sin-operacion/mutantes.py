#!/usr/bin/env python3
"""Mutantes de la migración 20261009180000 (sin operación de cartera, solo 'nuevo'). SOLO banco local de Docker.

Cada mutante cambia UN trozo de la guarda private.trg_contrato_categoria_por_operacion() (texto exacto, que tiene que
aparecer una sola vez) y/o la definición de su trigger, corre prueba.sql (incluida su transacción REPEATABLE READ) y lo
repone todo byte a byte (se comprueba el md5 del cuerpo, SECURITY, search_path y ACL, la definición del trigger y su
comentario). Un mutante MUERE si
la suite termina en «PRUEBA SIN OPERACION FALLA» (fallo de aserción); SOBREVIVE si termina en OK. Cualquier otra salida
(SQL inválido, la suite revienta) aborta la corrida: no se cuenta como muerte.
Un control se declara SUPERVIVIENTE a propósito (mutante equivalente: no cambia nada observable); si muere, se avisa.
La corrida falla si sobrevive un mutante que debía morir.

Uso:  python3 -I mutantes.py [contenedor]      (por defecto supabase_db_avancecorp-categoria-20261008)
"""
import pathlib
import re
import subprocess
import sys

AQUI = pathlib.Path(__file__).resolve().parent
SUITE = (AQUI / "prueba.sql").read_text(encoding="utf-8")
CONTENEDOR = sys.argv[1] if len(sys.argv) > 1 else "supabase_db_avancecorp-categoria-20261008"

GUARDA = "private.trg_contrato_categoria_por_operacion()"
TRIGGER = ("public.contratos", "trg_contratos_01_categoria_por_operacion")
TRIGGER_SIN_WHEN = ("create trigger trg_contratos_01_categoria_por_operacion after update on public.contratos "
                    "for each row execute function private.trg_contrato_categoria_por_operacion()")
REGLA = "  if not v_con_operacion and coalesce(new.categoria, 'nuevo') <> 'nuevo' then"
# Huella de la guarda para reponerla: cuerpo, SECURITY, search_path y permisos.
HUELLA = "md5(prosrc) || '|' || prosecdef || '|' || coalesce(proconfig::text, '') || '|' || coalesce(proacl::text, '')"
MENSAJE = "    raise exception 'Un contrato sin operación de cartera solo puede quedar como nuevo'"
AISLAMIENTO = "  -- Solo READ COMMITTED, ANTES de buscar la operación:"

# (clave, descripción, [(texto original, reemplazo), ...] en la guarda, trigger nuevo o None, ¿debe morir?)
MUTANTES = [
    ("S1", "(i) guarda SIN la regla nueva (vuelve el hueco: sin operación pasa a upgrade/renovacion)",
     [(REGLA, "  if false and not v_con_operacion and coalesce(new.categoria, 'nuevo') <> 'nuevo' then")], None, True),
    ("S2", "(ii) la regla rechaza también el paso a 'nuevo' (y a vacía)",
     [(REGLA, "  if not v_con_operacion then")], None, True),
    ("S3", "(iii-b) sin coalesce, con IS DISTINCT FROM: la categoría vacía deja de contar como nuevo",
     [(REGLA, "  if not v_con_operacion and new.categoria is distinct from 'nuevo' then")], None, True),
    # Mismo error completo (texto, código, detail y hint): en READ COMMITTED no cambia nada; solo el ORDEN frente al
    # rechazo de aislamiento, que ve la prueba en REPEATABLE READ (F1).
    ("S4", "la regla nueva ANTES del rechazo de aislamiento (en REPEATABLE READ daría 23514 en vez de 25001)",
     [(AISLAMIENTO,
       "  if not exists (select 1 from crm.operaciones_cartera o where o.contrato_nuevo_id = new.id)\n"
       "     and coalesce(new.categoria, 'nuevo') <> 'nuevo' then\n"
       "    raise exception 'Un contrato sin operación de cartera solo puede quedar como nuevo'\n"
       "      using errcode = '23514',\n"
       "            detail = format('El contrato no tiene operación de cartera; su categoría no puede pasar a %s.', new.categoria),\n"
       "            hint = 'Una renovación o un upgrade se registran desde la cartera del cliente, que crea su operación.';\n"
       "  end if;\n" + AISLAMIENTO)], None, True),
    ("S5", "otro texto en el error (el de «con operación»: la pantalla y el núcleo usan el de «sin operación»)",
     [(MENSAJE, "    raise exception 'La categoría la decide la operación de cartera'")], None, True),
    ("S6", "otro código de error (P0001 en vez de 23514)",
     [("      using errcode = '23514',\n            detail = format('El contrato no tiene operación",
       "      using errcode = 'P0001',\n            detail = format('El contrato no tiene operación")], None, True),
    ("S7", "la regla invertida: mira los contratos CON operación (rompería la sincronización y el alta)",
     [(REGLA, "  if v_con_operacion and coalesce(new.categoria, 'nuevo') <> 'nuevo' then")], None, True),
    ("S9", "la guarda SECURITY INVOKER: no vería la operación que la RLS le oculta a quien edita (el admin del portal)",
     [("\n SECURITY DEFINER\n", "\n SECURITY INVOKER\n")], None, True),
    ("S8", "la guarda revisa aunque la categoría NO cambie (sin WHEN ni salida temprana: tocaría los 106 antiguos)",
     [("  if new.categoria is not distinct from old.categoria then\n    return new;\n  end if;\n",
       "  -- (mutante: sin salida temprana)\n")], TRIGGER_SIN_WHEN, True),
    # Superviviente A PROPÓSITO: mutante equivalente.
    ("C1", "CONTROL (iii) sin coalesce, con <>: equivalente. En PL/pgSQL un IF cuya condición es NULL no entra, así que "
           "para una categoría vacía «NULL <> 'nuevo'» se comporta como «'nuevo' <> 'nuevo'» (falso): no se ve desde SQL. "
           "El coalesce se queda porque dice la regla (vacía cuenta como nuevo, igual que el núcleo) y porque la "
           "reescritura natural (IS DISTINCT FROM, S3) sí la rompe",
     [(REGLA, "  if not v_con_operacion and new.categoria <> 'nuevo' then")], None, False),
]


def psql(sql, *extra):
    r = subprocess.run(
        ["docker", "exec", "-i", "-e", "PGPASSWORD=postgres", CONTENEDOR, "psql", "-X", "-q", "-U", "supabase_admin",
         "-h", "127.0.0.1", "-d", "postgres", "-v", "ON_ERROR_STOP=1", *extra],
        input=sql, capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def leer_guarda():
    code, out, err = psql(f"select pg_get_functiondef('{GUARDA}'::regprocedure) || '<<FIN>>', {HUELLA} "
                          f"from pg_proc where oid = '{GUARDA}'::regprocedure;", "-At", "-F", "\x1f")
    if code != 0:
        sys.exit(f"no se pudo leer {GUARDA}: {err}")
    definicion, huella_md5 = out.rsplit("\x1f", 1)
    return definicion.split("<<FIN>>")[0], huella_md5.strip()


def huella_guarda():
    return psql(f"select {HUELLA} from pg_proc where oid = '{GUARDA}'::regprocedure;", "-At")[1].strip()


def trigger_actual():
    tabla, nombre = TRIGGER
    return psql(f"select pg_get_triggerdef(t.oid) || '<<>>' || coalesce(obj_description(t.oid, 'pg_trigger'), '') "
                f"from pg_trigger t where t.tgrelid = '{tabla}'::regclass and t.tgname = '{nombre}';", "-At")[1].strip()


def poner_trigger(definicion, comentario):
    tabla, nombre = TRIGGER
    sql = f"begin;\ndrop trigger {nombre} on {tabla};\n{definicion};\n"
    if comentario:
        sql += f"comment on trigger {nombre} on {tabla} is $c${comentario}$c$;\n"
    return psql(sql + "commit;\n")


def casos_que_fallan(salida):
    casos = [c.split(" ")[0] for c in re.findall(r"\| ([A-Z]\d+[a-z]? [^|]*?) \| FALLA", salida)]
    linea = next((l for l in salida.splitlines() if "PRUEBA SIN OPERACION FALLA: aislamiento" in l), "")
    return casos + sorted(set(re.findall(r"\b(F\d)\b", linea)))


def main():
    code, out, err = psql("select 1;", "-At")
    if code != 0:
        sys.exit(f"no hay banco en {CONTENEDOR}: {err}")
    # La suite tiene que pasar ANTES (si no, un «muere» no significaría nada).
    code, out, err = psql(SUITE)
    if "PRUEBA SIN OPERACION OK" not in out or "PRUEBA AISLAMIENTO SIN OPERACION OK" not in out:
        sys.exit("la suite NO pasa sin mutantes: arreglar antes de mutar\n" + (err[-2000:] or out[-2000:]))
    original, md5_original = leer_guarda()
    trigger_original = trigger_actual()
    definicion_trigger, comentario_trigger = trigger_original.split("<<>>", 1)
    filas, mal = [], []
    for clave, descripcion, trozos, trigger_nuevo, debe_morir in MUTANTES:
        mutado = original
        for antes, despues in trozos:
            n = mutado.count(antes)
            if n != 1:
                sys.exit(f"{clave}: el trozo a mutar aparece {n} veces en la guarda (tiene que ser 1)")
            mutado = mutado.replace(antes, despues)
        code, out, err = psql(mutado + ";\n")
        if code != 0:
            sys.exit(f"{clave}: el mutante NO compila (aborta la corrida): {err.strip()[:400]}")
        if trigger_nuevo:
            code, out, err = poner_trigger(trigger_nuevo, comentario_trigger)
            if code != 0:
                sys.exit(f"{clave}: el trigger mutante NO se pudo crear: {err.strip()[:400]}")
        try:
            code, out, err = psql(SUITE)
        finally:
            c2, o2, e2 = psql(original + ";\n")
            if c2 != 0 or huella_guarda() != md5_original:
                sys.exit(f"{clave}: NO se pudo reponer la guarda (revisar el banco a mano): {e2}")
            if trigger_nuevo:
                c3, o3, e3 = poner_trigger(definicion_trigger, comentario_trigger)
                if c3 != 0 or trigger_actual() != trigger_original:
                    sys.exit(f"{clave}: NO se pudo reponer el trigger (revisar el banco a mano): {e3}")
        salida = out + err
        falla = "PRUEBA SIN OPERACION FALLA" in salida
        ok = "PRUEBA SIN OPERACION OK" in salida and "PRUEBA AISLAMIENTO SIN OPERACION OK" in salida
        if not (falla or ok):
            sys.exit(f"{clave}: sin veredicto (no cuenta como muerte):\n{salida[-1500:]}")
        if falla:
            estado, quien = "MUERE", ", ".join(casos_que_fallan(salida)[:16]) or "(veredicto de la suite)"
        else:
            estado, quien = "SOBREVIVE", "-"
        filas.append((clave, estado, descripcion, quien))
        if debe_morir and estado != "MUERE":
            mal.append(clave)
        if not debe_morir and estado == "MUERE":
            print(f"(aviso) el control {clave} murió: no era tan equivalente como se creía")
    ancho = max(len(f[0]) for f in filas)
    for clave, estado, descripcion, quien in filas:
        print(f"{clave.ljust(ancho)}  {estado:9}  {descripcion}\n{' ' * (ancho + 13)}casos que fallan: {quien}")
    muertos = sum(1 for f in filas if f[1] == "MUERE" and not f[0].startswith("C"))
    esperados = sum(1 for m in MUTANTES if m[4])
    print(f"\n{muertos} de {esperados} mutantes que deben morir, MUEREN; controles: "
          + ", ".join(f"{f[0]} {f[1]}" for f in filas if f[0].startswith("C")))
    if mal:
        sys.exit(f"SOBREVIVEN mutantes que debían morir: {', '.join(mal)}")


if __name__ == "__main__":
    main()

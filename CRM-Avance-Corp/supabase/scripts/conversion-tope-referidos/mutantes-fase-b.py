#!/usr/bin/env python3
"""Mutantes de la FASE B del tope de referidos: cada uno rompe UNA defensa de una de las seis funciones y prueba-origen.sql debe CAER.
Uso:  python3 -I mutantes-fase-b.py <contenedor>   (el banco ya tiene las migraciones 20261007160937 y 20261007203000 aplicadas)
Cada mutante se aplica dentro de la transacción de la prueba (que termina en rollback): el banco no cambia.
Sale con 1 si algún mutante SOBREVIVE."""
import pathlib, re, subprocess, sys
AQUI = pathlib.Path(__file__).resolve().parent
MIGRACION = next((AQUI.parent.parent / "migrations").glob("*_crm_conversion_tope_referidos_origen.sql")).read_text()
contenedor = sys.argv[1]


def funcion(cabecera):
    """El texto de una función de la migración: desde su CREATE hasta el $function$ que la cierra."""
    i = MIGRACION.index(cabecera)
    ab = MIGRACION.index("AS $function$", i) + len("AS $function$")
    t = MIGRACION[i:MIGRACION.index("$function$", ab) + len("$function$")]
    return t.replace("CREATE FUNCTION", "CREATE OR REPLACE FUNCTION", 1)


def expandir(nombre):
    out = []
    for linea in (AQUI / nombre).read_text().split("\n"):
        m = re.match(r"\\i (\S+)\s*$", linea)
        out.append(expandir(m.group(1)) if m else linea)
    return "\n".join(out)


FUNCS = {
    "rco": funcion("CREATE FUNCTION private.ranking_conversion_origen_mes("),
    "rol": funcion("CREATE OR REPLACE FUNCTION private.ranking_origen_live("),
    "cde": funcion("CREATE OR REPLACE FUNCTION private.conversion_divisor_empresa("),
    "mci": funcion("CREATE OR REPLACE FUNCTION private.metricas_conversiones_implementacion("),
    "cms": funcion("CREATE OR REPLACE FUNCTION crm.conversion_mensual_sin_cartera_fn("),
    "cdc": funcion("CREATE OR REPLACE FUNCTION crm.conversion_divisor_coordinacion_fn("),
    "cp": funcion("CREATE OR REPLACE FUNCTION crm.cerrar_periodo("),
    "rap": funcion("CREATE FUNCTION private.referidos_aporte_por_analista("),
}

MUTANTES = [
  ("rco", "B1 el referido aporta p_factor aunque el tope lo recorte", [("then c.aporte_numerador else p_factor end", "then p_factor else p_factor end")]),
  ("rco", "B3 el porcentaje del origen usa los cierres y no el aporte", [("round(100 * coalesce(c.numerador, 0) / l.leads, 2)", "round(100 * coalesce(c.cierres, 0) / l.leads, 2)")]),
  ("rco", "B4 la columna `aporte` devuelve los cierres", [("    coalesce(c.numerador, 0::numeric)\n  from llegadas l", "    coalesce(c.cierres, 0)::numeric\n  from llegadas l")]),
  ("rco", "B2 los cierres vuelven a salir de conversion_cierres (sin tope)", [("from private.conversion_episodios(\n      p_ini, p_fin, p_periodo, true, '{}'::uuid[], p_factor\n    ) c", "from private.conversion_cierres(\n      p_ini, p_fin, p_periodo, true, '{}'::uuid[], p_factor, null::uuid[]\n    ) c"), ("then c.aporte_numerador else p_factor end", "then p_factor else p_factor end")]),
  ("rol", "B5 la foto no guarda el aporte de la fila", [("'aporte', coalesce(cv.aporte, 0)", "'aporte', 0")]),
  ("cde", "B6 Coordinación sellado vuelve a peso × cierres", [("case when v_cierre.tope_referidos_pct is not null then coalesce(o.referido_aporte, 0)", "case when false then coalesce(o.referido_aporte, 0)")]),
  ("mci", "B8 la ponderada del referido ignora el tope", [("then (case when v_tope is not null then o.aporte_cierres else o.contratos * v_factor end)", "then (case when false then o.aporte_cierres else o.contratos * v_factor end)")]),
  ("mci", "B8b el paquete no declara el tope", [("'tope_referidos_pct', v_tope,", "'tope_referidos_pct', null::numeric,")]),
  ("cms", "B10 el total del mes abierto vuelve a peso × cierres", [("case when private.tope_referidos_conversion(p_periodo) is not null then v_aporte_ref", "case when false then v_aporte_ref")]),
  ("cms", "B11 el aporte del mes abierto no lee el núcleo de TODO el ámbito", [("from private.referidos_aporte_por_analista(v_ini, v_fin, p_periodo, v_global, v_visibles, v_factor) r;", "from private.referidos_aporte_por_analista(v_ini, v_fin, p_periodo, false, '{}'::uuid[], v_factor) r;")]),
  ("cms", "B12 el total del mes sellado vuelve a peso × cierres", [("case when v_cierre.tope_referidos_pct is not null then r.aporte_referidos", "case when false then r.aporte_referidos")]),
  ("cms", "B17 el aporte sellado de un supervisor no se limita a sus visibles", [("where v_global or exists (select 1 from visibles vv where vv.vendedor_id::text = m.key)) as aporte_referidos", "where true) as aporte_referidos")]),
  ("cp", "B16 la foto no guarda el aporte exacto por analista", [("jsonb_build_object('referidos_aporte', coalesce((", "jsonb_build_object('otra_clave', coalesce((")]),
  ("rap", "B19 el aporte cuenta TODOS los cierres, no solo los referidos", [("where e.tipo = 'cierre' and e.fue_referido and not e.anulado", "where e.tipo = 'cierre' and not e.anulado")]),
  ("cms", "B13 el mes sellado no declara el tope de la foto", [("'tope_referidos_pct', v_cierre.tope_referidos_pct,", "'tope_referidos_pct', null::numeric,")]),
  ("cms", "B14 el mes abierto no declara el tope", [("'tope_referidos_pct', private.tope_referidos_conversion(p_periodo),", "'tope_referidos_pct', null::numeric,")]),
  ("cdc", "B15 Coordinación en vivo no declara el tope", [("else private.tope_referidos_conversion(pg_catalog.date_trunc('month', v_hasta)::date) end,", "else null::numeric end,")]),
]
sobreviven = []
prueba = expandir("prueba-origen.sql")
assert prueba.lstrip().startswith("--") and "\nbegin;\n" in prueba
for cual, nombre, cambios in MUTANTES:
    texto = FUNCS[cual]
    for a, b in cambios:
        assert texto.count(a) == 1, f"{nombre}: el texto a mutar aparece {texto.count(a)} veces: {a[:60]!r}"
        texto = texto.replace(a, b)
    if cual == "rco":
        # Cambia el tipo de retorno de la función viva: el mutante la recrea con la misma firma.
        texto = ("drop function private.ranking_conversion_origen_mes(timestamptz, timestamptz, date, numeric);\n"
                 + texto.replace("CREATE OR REPLACE FUNCTION", "CREATE FUNCTION", 1))
    # El mutante entra en TODAS las transacciones de la prueba (cada bloque deshace la suya).
    cuerpo = prueba.replace("\nbegin;\n", "\nbegin;\n" + texto + ";\n")
    r = subprocess.run(["docker", "exec", "-i", "-e", "PGPASSWORD=postgres", contenedor, "psql", "-U", "postgres", "-h", "127.0.0.1", "-d", "postgres", "-qAt", "-v", "ON_ERROR_STOP=1"],
                       input=cuerpo, capture_output=True, text=True)
    salida = r.stdout + r.stderr
    if "syntax error" in salida:
        sys.exit(f"{nombre}: el mutante es SQL inválido:\n{salida[:600]}")   # un error de sintaxis no prueba nada
    cayo = ("FALLA" in salida) or (r.returncode != 0 and "PRUEBA-ORIGEN: OK" not in salida)
    print(("CAYÓ      " if cayo else "SOBREVIVIÓ ") + nombre + ("" if cayo else "   <<<<<<"))
    if not cayo:
        sobreviven.append(nombre)
print(f"\nmutantes que sobreviven: {len(sobreviven)} de {len(MUTANTES)}")
sys.exit(1 if sobreviven else 0)

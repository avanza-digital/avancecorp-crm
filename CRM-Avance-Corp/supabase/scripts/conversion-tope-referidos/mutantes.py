#!/usr/bin/env python3
"""Mutantes del tope de referidos: cada uno rompe UNA defensa de la función viva del banco y la prueba debe CAER.
Uso:  python3 -I mutantes.py <contenedor>      (el banco ya tiene la migración 20261007160937 aplicada)
Cada mutante se aplica dentro de la transacción de la prueba (que termina en rollback): el banco no cambia.
Sale con 1 si algún mutante SOBREVIVE."""
import pathlib, subprocess, sys
AQUI = pathlib.Path(__file__).resolve().parent
MIGRACION = next((AQUI.parent.parent / "migrations").glob("*_crm_conversion_tope_referidos.sql")).read_text()
contenedor = sys.argv[1]

def funcion(cabecera):
    """El texto de una función de la migración: desde su CREATE OR REPLACE hasta el $function$ que la cierra."""
    i = MIGRACION.index(cabecera)
    ab = MIGRACION.index("AS $function$", i) + len("AS $function$")
    return MIGRACION[i:MIGRACION.index("$function$", ab) + len("$function$")]

EPISODIOS = funcion("CREATE OR REPLACE FUNCTION private.conversion_episodios(")
SELLO = funcion("CREATE OR REPLACE FUNCTION private.conversion_fijar_sello_trg()")

MUTANTES = [
  ("episodios", "M1 redondeo hacia abajo (floor)", [("ceil(t.base_cierres", "floor(t.base_cierres")], "prueba-tope.sql"),
  ("episodios", "M2 cuentan los referidos MÁS RECIENTES", [("order by m.fecha_numerador, m.registrado_en, m.lead_id) as orden_referido", "order by m.fecha_numerador desc, m.registrado_en, m.lead_id) as orden_referido")], "prueba-tope.sql"),
  ("episodios", "M3 la base ignora upgrades y renovaciones", [("or (c.tipo = 'operacion' and c.categoria in ('renovacion', 'upgrade'))", "or false")], "prueba-tope.sql"),
  ("episodios", "M4 el tope se calcula solo sobre el rango pedido", [("v_ini_mes timestamptz := date_trunc('month', p_ini at time zone 'America/Lima') at time zone 'America/Lima';", "v_ini_mes timestamptz := p_ini;"), ("v_fin_mes timestamptz := (v_mes_ult::timestamp + interval '1 month') at time zone 'America/Lima';", "v_fin_mes timestamptz := p_fin;")], "prueba-tope.sql"),
  ("episodios", "M5 la base mezcla a todos los analistas", [("over (partition by m.analista_id, m.mes_cierre) as base_cierres", "over (partition by m.mes_cierre) as base_cierres")], "prueba-tope.sql"),
  ("episodios", "M6 la base cuenta los cierres anulados", [("(not c.anulado and ((c.tipo = 'cierre'", "(((c.tipo = 'cierre'")], "prueba-tope.sql"),
  ("episodios", "M7 el tope rige en todos los meses (ignora la versión)", [("t.tope_pct is not null", "true"), ("ceil(t.base_cierres * t.tope_pct / 100.0)", "ceil(t.base_cierres * 15 / 100.0)")], "prueba-tope.sql"),
  # El ámbito está defendido DOS veces (antes del tope, dentro de los cierres y las operaciones, y al final): quitar solo una
  # mitad no cambia el resultado y por eso M8a y M8b SOBREVIVEN a propósito. El mutante DOBLE sí debe caer.
  ("episodios", "M8a (a propósito: defensa duplicada) sin recorte final al ámbito", [("  and (p_global or t.analista_id = any(p_visibles));", "  and true;")], "prueba-tope.sql", True),
  ("episodios", "M8b (a propósito: defensa duplicada) sin ámbito dentro de los cierres y las operaciones", [("v_ini_mes, v_fin_mes, p_periodo, p_global, p_visibles, p_factor, null::uuid[])", "v_ini_mes, v_fin_mes, p_periodo, true, '{}'::uuid[], p_factor, null::uuid[])"), ("    and (p_global or coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id),\n                             o.vendedor_id) = any(p_visibles))\n), marcados as (", "\n), marcados as (")], "prueba-tope.sql", True),
  ("episodios", "M8 DOBLE: sin ámbito en ningún lado", [("  and (p_global or t.analista_id = any(p_visibles));", "  and true;"), ("v_ini_mes, v_fin_mes, p_periodo, p_global, p_visibles, p_factor, null::uuid[])", "v_ini_mes, v_fin_mes, p_periodo, true, '{}'::uuid[], p_factor, null::uuid[])"), ("    and (p_global or coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id),\n                             o.vendedor_id) = any(p_visibles))\n), marcados as (", "\n), marcados as (")], "prueba-tope.sql"),
  ("episodios", "M12 el desempate ignora cuándo se acreditó cada cierre", [("order by m.fecha_numerador, m.registrado_en, m.lead_id) as orden_referido,", "order by m.fecha_numerador, m.lead_id) as orden_referido,")], "prueba-tope.sql"),
  ("episodios", "M9 el referido anulado sigue ocupando un lugar del tope", [("(c.tipo = 'cierre' and c.fue_referido and not c.anulado) as es_referido", "(c.tipo = 'cierre' and c.fue_referido) as es_referido")], "prueba-tope.sql"),
  ("episodios", "M10 el tope no se aplica (aporte sin recortar)", [("then 0::numeric else t.aporte_numerador end", "then t.aporte_numerador else t.aporte_numerador end")], "prueba-tope.sql"),
  ("episodios", "M11 el peso del referido que cuenta se pierde (vale 0 siempre)", [("then 0::numeric else t.aporte_numerador end", "then 0::numeric else (case when t.es_referido then 0 else t.aporte_numerador end) end")], "prueba-tope.sql"),
  ("sello", "T1 todos los referidos quedan incluidos en el sello", [("or ca.lead_id = any(v_cuentan)))", "or true))")], "prueba-sello-deuda.sql"),
  ("sello", "T2 la condición del referido está invertida", [("ca.origen is distinct from 'referido'", "ca.origen is not distinct from 'referido'")], "prueba-sello-deuda.sql"),
  ("sello", "T3 un mes sin tope deja fuera a los referidos", [("(new.tope_referidos_pct is null or ca.origen", "(false or ca.origen")], "prueba-sello-deuda.sql"),
  ("sello", "T4 el sello ignora el tope guardado y siempre excluye el exceso", [("if new.tope_referidos_pct is not null then", "if false then")], "prueba-sello-deuda.sql"),
]
base = {"episodios": EPISODIOS, "sello": SELLO}
sobreviven = []
for mut in MUTANTES:
    cual, nombre, cambios, prueba = mut[:4]
    a_proposito = len(mut) > 4 and mut[4]
    texto = base[cual]
    for a, b in cambios:
        assert texto.count(a) == 1, f"{nombre}: el texto a mutar aparece {texto.count(a)} veces: {a[:60]!r}"
        texto = texto.replace(a, b)
    cuerpo = (AQUI / prueba).read_text()
    assert cuerpo.lstrip().startswith("--") and "\nbegin;\n" in cuerpo
    cuerpo = cuerpo.replace("\nbegin;\n", "\nbegin;\n" + texto + ";\n" if cual == "episodios" else "\nbegin;\n" + texto + "\n", 1)
    r = subprocess.run(["docker", "exec", "-i", "-w", "/tmp", "-e", "PGPASSWORD=postgres", contenedor, "psql", "-U", "postgres", "-h", "127.0.0.1", "-d", "postgres", "-qAt", "-v", "ON_ERROR_STOP=1"],
                       input=cuerpo.replace("\\i anterior-episodios.sql", "\\i /tmp/anterior-episodios.sql"), capture_output=True, text=True)
    salida = r.stdout + r.stderr
    cayo = ("FALLA" in salida) or (r.returncode != 0 and "PASS" not in salida)
    if a_proposito:
        print(("SOBREVIVIÓ (esperado) " if not cayo else "CAYÓ (no se esperaba) ") + nombre)
        if cayo:
            sobreviven.append(nombre)
        continue
    print(("CAYÓ      " if cayo else "SOBREVIVIÓ ") + nombre + ("" if cayo else "   <<<<<<"))
    if not cayo:
        sobreviven.append(nombre)
print(f"\nmutantes con resultado inesperado: {len(sobreviven)} de {len(MUTANTES)}")
sys.exit(1 if sobreviven else 0)

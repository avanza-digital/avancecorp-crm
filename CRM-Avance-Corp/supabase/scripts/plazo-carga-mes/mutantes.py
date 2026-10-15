#!/usr/bin/env python3
"""Mutantes de 20261015000852_crm_plazo_carga_mes: cada defensa se rompe a propósito y prueba.sql tiene que CAER.

Para cada mutante: toma el cuerpo de la función TAL COMO ESTÁ EN LA MIGRACIÓN, le aplica UN cambio de texto (que tiene
que encontrarse exactamente una vez), y corre prueba.sql en una transacción que empieza instalando el mutante y termina
en ROLLBACK. Muerto = la corrida termina con «PRUEBA FALLA» (una aserción, no un error cualquiera). Antes, una corrida
de control sin mutar tiene que dar «PRUEBA PLAZO CARGA OK».

Los controles «C…» son defensas redundantes o inalcanzables: se espera que SOBREVIVAN y se dice por qué.

Uso (banco Docker propio con la migración aplicada, NUNCA producción):
    python3 -I supabase/scripts/plazo-carga-mes/mutantes.py supabase_db_<project_id>
"""
import pathlib
import re
import subprocess
import sys

AQUI = pathlib.Path(__file__).resolve().parent
MIGRACION = AQUI.parent.parent / "migrations" / "20261015000852_crm_plazo_carga_mes.sql"
PRUEBA = AQUI / "prueba.sql"

if len(sys.argv) != 2 or not sys.argv[1].startswith("supabase_db_"):
    sys.exit("Uso: mutantes.py supabase_db_<project_id> (un banco local, nunca producción)")
CONTENEDOR = sys.argv[1]

TEXTO_MIG = MIGRACION.read_text(encoding="utf-8")
TEXTO_PRUEBA = PRUEBA.read_text(encoding="utf-8")


def funcion(nombre: str) -> str:
    """El CREATE de la función tal como está en la migración, como CREATE OR REPLACE."""
    m = re.search(r"(?im)^(create function|CREATE OR REPLACE FUNCTION) " + re.escape(nombre) + r"\(", TEXTO_MIG)
    if not m:
        raise SystemExit(f"no encuentro {nombre} en la migración")
    fin = TEXTO_MIG.index("$function$;", TEXTO_MIG.index("$function$", m.end()) + len("$function$")) + len("$function$;")
    bloque = TEXTO_MIG[m.start():fin]
    return re.sub(r"(?i)^(create function)", "create or replace function", bloque)


def mutar(nombre: str, viejo, nuevo) -> str:
    """Uno o varios cambios (listas paralelas) sobre el mismo cuerpo; cada texto tiene que aparecer exactamente una vez."""
    bloque = funcion(nombre)
    viejos = viejo if isinstance(viejo, list) else [viejo]
    nuevos = nuevo if isinstance(nuevo, list) else [nuevo]
    for v, n_ in zip(viejos, nuevos):
        n = bloque.count(v)
        if n != 1:
            raise SystemExit(f"mutante sobre {nombre}: el texto a cambiar aparece {n} veces (tiene que ser 1): {v!r}")
        bloque = bloque.replace(v, n_)
    return bloque


def correr(ddl: str):
    lineas = TEXTO_PRUEBA.split("\n")
    i = lineas.index("begin;")
    sql = "\n".join(lineas[: i + 1] + [ddl] + lineas[i + 1 :])
    r = subprocess.run(
        ["docker", "exec", "-i", "-e", "PGPASSWORD=postgres", CONTENEDOR, "psql", "-X", "-U", "postgres", "-h",
         "127.0.0.1", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-q", "-f", "-"],
        input=sql, capture_output=True, text=True, timeout=600)
    salida = r.stdout + r.stderr
    if r.returncode == 0 and "PRUEBA PLAZO CARGA OK" in salida:
        return "SOBREVIVE", ""
    if "PRUEBA FALLA" in salida:
        linea = next(l for l in salida.splitlines() if "PRUEBA FALLA" in l)
        return "MUERE", linea[linea.index("PRUEBA FALLA"):][:200]
    return "ERROR DE CORRIDA", salida.strip().splitlines()[-1][:300] if salida.strip() else "(sin salida)"


IMP = "private.reapertura_impedimento"
REEV = "private.conversion_reevaluar_plazo"
F4 = "private.f4_fuente_inmutable"
CE = "private.trg_cierres_externos_inmutables"
AP = "private.trg_cierre_mes_append_only"
GATE = "crm.fijar_plazo_carga_mes"
LEC = "crm.plazos_carga_mes_fn"
LECN = "private.plazos_carga_mes_lectura"
FIJ = "private.fijar_plazo_carga"
LLAVE = "private.trg_reaperturas_mes_llave"
REAB = "private.reabrir_mes"
AUT = "private.reapertura_autoriza"
PLAZO = "private.conversion_plazo_hasta"
AUT_MES = "private.reapertura_autoriza(pg_catalog.date_trunc('month', old.fecha_comercial::timestamp)::date"
AUT_IMP = AUT_MES + ", old.id)"
VALVULA_CE = ("  if not v_priv\n     and (" + AUT_IMP + "\n          and new.fecha_imputacion is not distinct from old.fecha_comercial\n"
              "          and (pg_catalog.to_jsonb(new) - 'fecha_imputacion') = (pg_catalog.to_jsonb(old) - 'fecha_imputacion')) is not true then")

MUTANTES = [
    # Candado del sello y la foto
    ("M01 sello/foto: sin la rama de la reapertura", AP,
     "  if tg_op = 'DELETE' and private.reapertura_autoriza(old.periodo) then\n    return old;\n  end if;\n", ""),
    ("M02 sello/foto: borrar sin autorización", AP,
     "if tg_op = 'DELETE' and private.reapertura_autoriza(old.periodo) then", "if tg_op = 'DELETE' then"),
    ("M03 sello/foto: la reapertura también deja EDITAR", AP,
     "if tg_op = 'DELETE' and private.reapertura_autoriza(old.periodo) then", "if private.reapertura_autoriza(old.periodo) then"),
    # Candado del historial de inversiones / imputación del cierre
    ("M04 rastro: sin la rama de la reapertura", F4,
     "    if private.reapertura_autoriza(old.periodo_origen) then return old; end if;\n", ""),
    ("M05 rastro: borrar sin autorización", F4,
     "if private.reapertura_autoriza(old.periodo_origen) then return old; end if;", "return old;"),
    ("M06 imputación: a cualquier fecha", F4, "       and new.fecha_imputacion = old.fecha_comercial\n", ""),
    # Revisión Codex r1 (P2): la rama exige la fila entera igual salvo la imputación (antes, solo clase, fecha comercial y
    # comprobante: con la válvula de corrección abierta dejaba cambiar el monto o la nota a la vez). Cubre M07–M09 de antes.
    ("M07 imputación: sin la igualdad de la fila (cambia también comprobante, clase, monto o nota)", F4,
     "       and (pg_catalog.to_jsonb(new) - 'fecha_imputacion') = (pg_catalog.to_jsonb(old) - 'fecha_imputacion')\n", ""),
    ("M10 imputación: sin autorización", F4,
     "\n       and " + AUT_IMP + " then\n      return new;", " then\n      return new;"),
    ("M10b imputación: cualquier venta del mes (sin atar a la respaldada)", F4,
     "       and " + AUT_IMP + " then", "       and " + AUT_MES + ") then"),
    ("M11 imputación: sin la rama de la reapertura", F4,
     "  if tg_table_schema='crm' and tg_table_name='cierres_externos' and tg_op='UPDATE' then\n",
     "  if false then\n"),
    # Candado de los cierres externos (válvula de UPDATE)
    ("M12 cierre externo: la reapertura no abre la válvula", CE, VALVULA_CE, "  if not v_priv then"),
    ("M13 cierre externo: válvula abierta para todos", CE, VALVULA_CE, "  if false then"),
    ("M13b cierre externo: la reapertura deja cambiar otras columnas (P2)", CE,
     "\n          and (pg_catalog.to_jsonb(new) - 'fecha_imputacion') = (pg_catalog.to_jsonb(old) - 'fecha_imputacion')) is not true then",
     ") is not true then"),
    ("M13c cierre externo: la reapertura deja otra imputación", CE,
     "\n          and new.fecha_imputacion is not distinct from old.fecha_comercial", ""),
    ("M13d cierre externo: cualquier venta del mes (sin atar a la respaldada)", CE,
     "     and (" + AUT_IMP + "\n", "     and (" + AUT_MES + ")\n"),
    ("M14 cierre externo: la reapertura también deja BORRAR", CE,
     "    if private.inversion_eliminacion_autoriza('cierre', old.id, pg_catalog.to_jsonb(old)) then",
     "    if " + AUT_IMP + " or private.inversion_eliminacion_autoriza('cierre', old.id, pg_catalog.to_jsonb(old)) then"),
    # La llave de la reapertura
    ("M14b autorización: sin el instante (una fila vieja con el mismo id de transacción autoriza)", AUT,
     "\n       and r.reabierto_en = pg_catalog.now()", ""),
    ("M14c autorización: sin atar el cierre a la reapertura que lo respaldó", AUT,
     "       and (p_cierre_externo is null\n            or r.respaldo -> 'cierres_externos'\n"
     "                 @> pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('id', p_cierre_externo)))\n",
     ""),
    ("M14d la llave la elige quien inserta (sin el trigger que la fija)", LLAVE,
     "  new.transaccion := pg_catalog.pg_current_xact_id();\n  new.reabierto_en := pg_catalog.now();\n", ""),
    ("M56 la llave con el instante de la SENTENCIA (el alcance dejaría de ser la transacción superior)", LLAVE,
     "  new.reabierto_en := pg_catalog.now();", "  new.reabierto_en := pg_catalog.statement_timestamp();"),
    # La autorización
    ("M15 autorización: de cualquier transacción", AUT,
     "\n       and r.transaccion = pg_catalog.pg_current_xact_id_if_assigned()", ""),
    ("M16 autorización: de cualquier mes", AUT,
     "     where r.periodo = p_periodo\n       and r.transaccion", "     where r.transaccion"),
    # Quién se puede reabrir (cada comprobación)
    ("M17 reapertura: un mes abierto se «reabre»", IMP,
     "  if not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = p_periodo) then", "  if false then"),
    ("M18 reapertura: sin «último sellado»", IMP, "  if v_ultimo > p_periodo then", "  if false then"),
    ("M19 reapertura: sin «mes anterior»", IMP,
     "  if p_periodo <> (v_mes_actual - interval '1 month')::date then", "  if false then"),
    ("M20 reapertura: sin foto", IMP,
     "  if not exists (select 1 from crm.cierre_mes_vendedor f where f.periodo = p_periodo) then", "  if false then"),
    ("M21 reapertura: sin «deudas nacidas»", IMP,
     "  if exists (select 1 from crm.ajustes_mes_cerrado a where a.periodo_origen = p_periodo) then", "  if false then"),
    ("M22 reapertura: sin «deudas absorbidas»", IMP,
     "(f.ajuste_numerador <> 0 or f.ajuste_pen <> 0 or f.ajuste_usd <> 0)", "false"),
    ("M23 reapertura: rastro sin comparar la imputación", IMP,
     "                     or ce.fecha_imputacion is distinct from ia.fecha_imputacion\n", ""),
    # Dos condiciones cubren «imputada dentro del mes o a un mes sellado» (con el mes sellado, dentro del mes ES un mes
    # sellado): el mutante DOBLE tiene que caer; los simples son los controles C1 y C3.
    ("M24 reapertura: rastro imputado dentro del mes (las dos condiciones)", IMP,
     "                     or ce.fecha_imputacion < v_fin\n"
     "                     or exists (select 1 from crm.periodos_cerrados pc\n"
     "                                 where pc.periodo = pg_catalog.date_trunc('month', ce.fecha_imputacion::timestamp)::date))) then",
     "                     )) then"),
    ("M25 reapertura: rastro con fecha comercial de otro mes", IMP,
     "                     or ce.fecha_comercial < p_periodo or ce.fecha_comercial >= v_fin\n", ""),
    # Un rastro de contrato (sin cierre) lo rechazan tres condiciones a la vez (sin cierre, sin fecha, imputación
    # distinta): el mutante TRIPLE tiene que caer; el que solo quita las dos primeras es el control C2.
    ("M26 reapertura: rastro de contrato (las tres condiciones)", IMP,
     ["                and (ce.id is null\n                     or ce.fecha_comercial is null\n",
      "                     or ce.fecha_imputacion is distinct from ia.fecha_imputacion\n"],
     ["                and (false\n", ""]),
    ("M27 reapertura: sin «analista con meta»", IMP,
     "                and (ef.analista_id is null\n", "                and false and (ef.analista_id is null\n"),
    ("M28 reapertura: sin «cooperativa sin rastro»", IMP,
     "                and ce.fecha_imputacion >= v_fin\n", "                and false and ce.fecha_imputacion >= v_fin\n"),
    ("M58 reapertura: reabre un mes sellado sin metas (Codex r2)", IMP,
     "  if not exists (select 1 from crm.meta_periodos mp where mp.periodo = p_periodo) then\n"
     "    return pg_catalog.format('%s no tiene metas publicadas",
     "  if false then\n    return pg_catalog.format('%s no tiene metas publicadas"),
    # La reevaluación
    ("M29 reevaluación: sin el conflicto de identidad", REEV,
     "                    and ca.estado = 'acreditada'\n", "                    and false and ca.estado = 'acreditada'\n"),
    ("M30 reevaluación: sin la exclusión de fuente", REEV,
     "    v_estado := case v_exclusion when 'fuente_demo' then 'fuente_demo'\n"
     "                                 when 'operacion_cartera' then 'operacion_cartera'\n"
     "                                 else v_decision.estado end;",
     "    v_estado := v_decision.estado;"),
    ("M31 reevaluación: sin el filtro «antes del plazo»", REEV, "       and ca.acreditado_en < v_plazo\n", ""),
    ("M32 reevaluación: también las fuentes retiradas", REEV,
     "    if v_exclusion is distinct from 'elegible' and v_exclusion is distinct from 'fuente_demo'\n"
     "       and v_exclusion is distinct from 'operacion_cartera' then",
     "    if false then"),
    ("M33 reevaluación: identidad cruda en las otras", REEV,
     "and private.inversionista_canonica(ca.inversionista_id) = v_persona", "and ca.inversionista_id = v_persona"),
    ("M34 reevaluación: identidad cruda en la propia", REEV,
     "select private.inversionista_canonica(l.inversionista_id) into v_persona", "select l.inversionista_id into v_persona"),
    ("M53 reevaluación: la identidad solo para fuentes elegibles (como antes de Codex r1, P3)", REEV,
     "    if v_persona is not null then\n      perform", "    if v_persona is not null and v_exclusion = 'elegible' then\n      perform"),
    # El plazo vigente
    ("M35 plazo: ignora las decisiones", PLAZO, "  return coalesce(v_decidido, v_base);", "  return v_base;"),
    ("M36 plazo: la primera decisión y no la última", PLAZO,
     "   order by d.decidido_en desc, d.id desc", "   order by d.decidido_en asc, d.id asc"),
    # La puerta
    ("M37 puerta: sin rol (cualquier sesión)", GATE,
     "  if v_uid is null or private.rol_crm(v_uid) is distinct from 'gerencia' then\n    raise exception 'Solo Gerencia decide",
     "  if v_uid is null then\n    raise exception 'Solo Gerencia decide"),
    ("M38 puerta: último día en el pasado", GATE, "  if p_ultimo_dia < v_hoy then", "  if false then"),
    ("M39 puerta: antes de la base", GATE,
     "  if ((p_ultimo_dia + 1)::timestamp at time zone 'America/Lima') < v_base then", "  if false then"),
    ("M40 puerta: mes futuro", GATE, "  if p_periodo > v_mes_actual then", "  if false then"),
    ("M41 puerta: sin motivo", GATE, "  if pg_catalog.char_length(v_motivo) not between 5 and 300 then", "  if false then"),
    ("M42 puerta: no reabre el mes sellado", FIJ,
     "    v_reapertura := private.reabrir_mes(p_periodo, p_motivo, p_por);", "    v_reapertura := null;"),
    ("M42b puerta: admite un mes sin sellar por detrás del último cierre", FIJ,
     "    if v_ultimo_sellado > p_periodo then", "    if false then"),
    ("M57 puerta: admite plazo en un mes sin metas (Codex r2)", FIJ,
     "  if not exists (select 1 from crm.meta_periodos mp where mp.periodo = p_periodo) then\n"
     "    raise exception using errcode = '22023',",
     "  if false then\n    raise exception using errcode = '22023',"),
    ("M43 puerta: no reevalúa", FIJ,
     "  v_reeval := private.conversion_reevaluar_plazo(p_periodo);",
     "  v_reeval := '{\"reevaluadas\": 0, \"conflictos\": 0}'::jsonb;"),
    # La lectura
    ("M44 lectura: sin rol (cualquier sesión)", LEC,
     "  if v_uid is null or private.rol_crm(v_uid) is distinct from 'gerencia' then\n    raise exception 'Solo Gerencia ve",
     "  if v_uid is null then\n    raise exception 'Solo Gerencia ve"),
    ("M45 lectura: «reabrible» sin la regla de la reapertura", LECN,
     "           'reabrible', s.sellado and i.impedimento is null,", "           'reabrible', s.sellado,"),
    ("M52 lectura: el nombre de quien decide, crudo (puede salir en blanco)", LECN,
     "coalesce(nullif(pg_catalog.btrim(pf.nombre_completo), ''),\n"
     "                                       '(sin nombre · ' || pg_catalog.left(dd.decidido_por::text, 8) || ')') as nombre",
     "pf.nombre_completo as nombre"),
    # La reapertura
    ("M46 reapertura: respaldo sin las acreditaciones", REAB,
     "from crm.conversion_acreditaciones ca where ca.periodo_comercial = p_periodo),\n    'rastros_tardios'",
     "from crm.conversion_acreditaciones ca where false),\n    'rastros_tardios'"),
    ("M46b reapertura: respaldo con documento y nombre del cliente", REAB,
     "pg_catalog.to_jsonb(ce) - 'documento' - 'documento_tipo' - 'nombre_completo'", "pg_catalog.to_jsonb(ce)"),
    ("M47 reapertura: no devuelve las ventas tardías", REAB,
     "  update crm.cierres_externos ce set fecha_imputacion = ce.fecha_comercial where ce.id = any (v_tardias);",
     "  update crm.cierres_externos ce set fecha_imputacion = ce.fecha_imputacion where false;"),
    ("M48 reapertura: no retira el rastro tardío", REAB,
     "  delete from crm.inversion_ajustes_mes_cerrado ia where ia.periodo_origen = p_periodo;",
     "  delete from crm.inversion_ajustes_mes_cerrado ia where false;"),
]

# El CHECK de plazo: con el de IGUALDAD de antes, el sello no puede marcar filas ya decididas con otro plazo.
CHECK_VIEJO = ("alter table crm.conversion_acreditaciones drop constraint conversion_acreditaciones_plazo_minimo_check;\n"
               "alter table crm.conversion_acreditaciones add constraint conversion_acreditaciones_check3 "
               "check (plazo_hasta = private.conversion_plazo_hasta(periodo_comercial));")

# Revisión Codex r1 (P3): con la llave única de antes (solo la transacción), una reapertura vieja con el mismo id de
# transacción (volcado restaurado en otro cluster) impide registrar una legítima (23505).
UNICA_VIEJA = ("alter table crm.reaperturas_mes drop constraint reaperturas_mes_transaccion_key;\n"
               "alter table crm.reaperturas_mes add constraint reaperturas_mes_transaccion_key unique (transaccion);")

CONTROLES = [
    ("C4 lectura: sin los meses abiertos con decisión (redundante desde Codex r2: todo mes con decisión tiene metas —la "
     "puerta lo exige y crm.meta_periodos es inmutable—, así que ya entra por la primera rama o es el mes en curso)", LECN,
     "    union\n    select dd.periodo\n      from crm.plazos_carga_mes dd\n     where dd.periodo <= v_mes_actual\n"
     "       and dd.periodo > coalesce(v_ultimo_sellado, '-infinity'::date)\n"
     "       and not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = dd.periodo)\n", ""),
    ("C1 reapertura: sin «imputada a un mes sellado» (solo: la cubre «dentro del mes», porque con el mes como último "
     "sellado ningún mes posterior está sellado)", IMP,
     "\n                     or exists (select 1 from crm.periodos_cerrados pc\n"
     "                                 where pc.periodo = pg_catalog.date_trunc('month', ce.fecha_imputacion::timestamp)::date))) then",
     ")) then"),
    ("C2 reapertura: sin «sin cierre» ni «sin fecha» (solo: un rastro sin cierre ya tiene la imputación distinta de "
     "la del rastro)", IMP,
     "                and (ce.id is null\n                     or ce.fecha_comercial is null\n",
     "                and (false\n"),
    ("C3 reapertura: sin «imputada dentro del mes» (solo: con el mes sellado, dentro del mes es un mes sellado)", IMP,
     "                     or ce.fecha_imputacion < v_fin\n", ""),
]

estado, detalle = correr("-- control: sin mutar")
print(f"CONTROL sin mutar: {estado} {detalle}")
if estado != "SOBREVIVE":
    sys.exit("La corrida de control no está en verde: no se pueden medir mutantes")

muertos = 0
problemas = []
for nombre, fn, viejo, nuevo in MUTANTES:
    estado, detalle = correr(mutar(fn, viejo, nuevo))
    print(f"{nombre}: {estado} {detalle}")
    if estado == "MUERE":
        muertos += 1
    else:
        problemas.append(nombre)
estado, detalle = correr(UNICA_VIEJA)
print(f"M54 llave única solo por transacción (la de antes de Codex r1): {estado} {detalle}")
if estado == "MUERE":
    muertos += 1
else:
    problemas.append("M54 llave única solo por transacción")
# M49 solo se puede cazar desde el día 11 (antes, el plazo base del mes anterior no venció y el bloque B2 no sella).
dia = subprocess.run(["docker", "exec", "-e", "PGPASSWORD=postgres", CONTENEDOR, "psql", "-X", "-U", "postgres", "-h",
                      "127.0.0.1", "-d", "postgres", "-At", "-c",
                      "select extract(day from now() at time zone 'America/Lima')::int"],
                     capture_output=True, text=True, timeout=60).stdout.strip()
total = len(MUTANTES) + 1   # + M54 (DDL)
if dia.isdigit() and int(dia) >= 11:
    total += 1
    estado, detalle = correr(CHECK_VIEJO)
    print(f"M49 CHECK de igualdad (el de antes): {estado} {detalle}")
    if estado == "MUERE":
        muertos += 1
    else:
        problemas.append("M49 CHECK de igualdad")
else:
    print(f"M49 CHECK de igualdad: NO EJECUTABLE HOY (día {dia} de Lima; se caza desde el día 11)")
for nombre, fn, viejo, nuevo in CONTROLES:
    estado, detalle = correr(mutar(fn, viejo, nuevo))
    print(f"{nombre}: {estado} {detalle} (se espera SOBREVIVE)")
    if estado != "SOBREVIVE":
        problemas.append(nombre)
print(f"MUTANTES: {muertos} de {total} mueren; controles: {len(CONTROLES)}")
if problemas:
    sys.exit("REVISAR: " + "; ".join(problemas))
print("MUTANTES OK")

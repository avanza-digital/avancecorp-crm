#!/usr/bin/env python3
"""Los guiones de producción, tal como los correrá Miguel (un solo mensaje), en el banco y sin dejar nada.

  E1 · El ENSAYO del LEEME (paso 1): la migración sin su `commit;` + vista-previa.sql (termina en ROLLBACK), sobre un
       mundo sembrado como producción el 14/10: agosto sellado con foto, un rastro tardío de agosto, septiembre abierto
       con conversiones «fuera de plazo» y una Gerencia activa. Como la migración ya está aplicada en el banco, un mensaje
       ANTERIOR de la misma sesión y transacción la retira con reversa.sql y siembra (juntos pasarían de 128 KB, el límite
       de un argumento): el mensaje probado es exactamente el del paso 1, y el ROLLBACK final lo deshace TODO.
       Comprueba: «ENSAYO OK», septiembre no se reabre, cuántas se reevalúan, y que el postflight ejecutó sus intentos
       «que deben rebotar» (avisos).
  E1b · El ensayo FALLA si la operación simulada falla (revisión Codex r1): el mismo mensaje sobre un mundo donde fijar el
       plazo de septiembre no se puede (octubre ya sellado: septiembre quedó por detrás) no dice «ENSAYO OK».
  E1c · Sobre ese mismo mundo, el ciclo entero de producción en una transacción que se deshace: aplicar → registrar →
       verificar («APLICADA Y REGISTRADA», con la declaración analítica re-sellada) → reversa (la declaración vuelve a la
       huella de antes, vigente).
  E2 · La reversa se NIEGA si ya hay una decisión de plazo (y no toca nada).
  E3 · El registrador: registra, es idempotente, y se niega si la migración no está.
  E4 · Mutantes del RE-SELLADO del censo analítico (el primer ensayo en producción, 15/10, se negó porque
       crm.cerrar_periodo está declarada allí y el banco no la tenía): sin el re-sellado, otra huella, tocar la razón o la
       clase, o no re-sellar la lista. Cada migración mutada, sobre el mundo de E1, tiene que NEGARSE.

El mundo de E1 lleva los REGISTROS de los trinquetes de producción si se pasa la salida de leer-registros-produccion.sql
(exenciones, tope y sello analíticos; F7; vigencia; auditoría): así el banco ve las declaraciones que ve producción. Sin
ese archivo, se siembra solo la declaración analítica de crm.cerrar_periodo como la de producción (y su sello).

Uso:  python3 -I supabase/scripts/plazo-carga-mes/transporte.py supabase_db_<project_id> [/tmp/registros-produccion.json]
"""
import json
import pathlib
import re
import subprocess
import sys

if len(sys.argv) not in (2, 3) or not sys.argv[1].startswith("supabase_db_"):
    sys.exit("Uso: transporte.py supabase_db_<project_id> [registros.json] (un banco local, nunca producción)")
C = sys.argv[1]
AQUI = pathlib.Path(__file__).resolve().parent
MIG = (AQUI.parent.parent / "migrations" / "20261015000852_crm_plazo_carga_mes.sql").read_text(encoding="utf-8")
REVERSA = (AQUI / "reversa.sql").read_text(encoding="utf-8")
VISTA = (AQUI / "vista-previa.sql").read_text(encoding="utf-8")
REG = (AQUI / "registrar" / "20261015000852.sql").read_text(encoding="utf-8")


def sin_tx(texto):
    """Quita el PRIMER `begin;` y el ÚLTIMO `commit;` (líneas exactas) de un guion, para encadenarlo dentro de otra
    transacción. (El registrador lleva la migración entera como texto: dentro hay más líneas begin/commit.)"""
    lineas = texto.split("\n")
    assert "begin;" in lineas and "commit;" in lineas, "el guion no tiene begin/commit"
    del lineas[lineas.index("begin;")]
    del lineas[len(lineas) - 1 - lineas[::-1].index("commit;")]
    return "\n".join(lineas)


def un_mensaje(sql, usuario="postgres", por_archivo=False, previo=None):
    """UN mensaje (`-c`, como `db query --file`). Con `por_archivo`, sentencia a sentencia (`-f`): solo para textos de
    más de 128 KB (el límite de un argumento del shell del contenedor), donde el transporte no es lo que se prueba.
    `previo`: el andamiaje de la prueba (retirar la migración del banco, sembrar), en OTRO mensaje ANTES y en la misma
    sesión y transacción; así el mensaje que se prueba es exactamente el de producción aunque juntos pasen de 128 KB."""
    if previo is not None:
        assert not por_archivo
        r = subprocess.run(["docker", "exec", "-i", C, "sh", "-c", "cat > /tmp/transporte-previo.sql"],
                           input=previo, capture_output=True, text=True, timeout=60)
        assert r.returncode == 0, r.stderr
    modo = "-f /tmp/transporte.sql" if por_archivo else '-c "$(cat /tmp/transporte.sql)"'
    if previo is not None:
        modo = '-c "$(cat /tmp/transporte-previo.sql)" ' + modo
    r = subprocess.run(["docker", "exec", "-i", "-e", "PGPASSWORD=postgres", C, "sh", "-c",
                        f'cat > /tmp/transporte.sql && psql -X -U {usuario} -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 '
                        f'-At {modo}'],
                       input=sql, capture_output=True, text=True, timeout=600)
    return r.returncode, r.stdout + r.stderr


resultados = []


def caso(nombre, ok, detalle=""):
    resultados.append(ok)
    print(("PASS" if ok else "FALLA") + f": {nombre}" + ("" if ok else f" — {detalle[-1500:]}"))


G = "ca7e15f0-0000-4000-8000-0000000000a1"
V = "ca7e15f0-0000-4000-8000-0000000000b1"
S = "ca7e15f0-0000-4000-8000-0000000000b2"
SIEMBRA = f"""
-- Mundo como producción el 14/10 (sintético): agosto sellado con foto y un rastro tardío; septiembre abierto.
set local session_replication_role = replica;
insert into public.perfiles (id, nombre_completo, rol, activo) values
  ('{G}', 'ADMINISTRADOR AVANCE CORP', 'comercial', true), ('{V}', 'ANALISTA TRANSPORTE', 'comercial', true),
  ('{S}', 'SUPERVISOR TRANSPORTE', 'comercial', true);
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values
  ('{G}', 'gerencia', null, true), ('{S}', 'supervisor', null, true), ('{V}', 'vendedor', '{S}', true);
insert into crm.periodos_cerrados (periodo, cerrado_en, automatico, ponderacion_referido, meta_revision, cobertura)
values (date '2026-08-01', timestamptz '2026-09-11 09:20-05', true, 0.15, 1, '{{}}');
-- Metas publicadas de agosto y septiembre, como en producción: solo un mes con metas admite plazo (revisión Codex r2).
insert into crm.meta_periodos (id, periodo, revision, publicada_en, publicada_por) values
  ('ca7e15f0-0000-4000-8000-000000000701', date '2026-08-01', 1, timestamptz '2026-08-01 09:00-05', '{G}'),
  ('ca7e15f0-0000-4000-8000-000000000702', date '2026-09-01', 1, timestamptz '2026-09-01 09:00-05', '{G}');
insert into crm.cierre_mes_vendedor (periodo, vendedor_id, nombre_completo, supervisor_id, supervisor_nombre, divisor,
  cierres_no_referidos, cierres_referidos, cierres_de_arrastre, numerador, estado, referidos_recibidos,
  referidos_dados_de_alta, conversion_objetivo)
values (date '2026-08-01', '{V}', 'ANALISTA TRANSPORTE', '{S}', 'SUPERVISOR TRANSPORTE', 10, 1, 0, 0, 1, 'sellado', 0, 0, 10);
insert into crm.inversionistas (id, estado) values ('ca7e15f0-0000-4000-8000-000000000101', 'activo'),
  ('ca7e15f0-0000-4000-8000-000000000102', 'activo'), ('ca7e15f0-0000-4000-8000-000000000103', 'activo');
insert into storage.objects (id, bucket_id, name) values ('ca7e15f0-0000-4000-8000-000000000901', 'prueba', 'transporte/1');
insert into crm.cierres_externos (id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo,
  numero_transaccion, vendedor_id, creado_por, inversionista_id, es_cierre_inicial, fecha_comercial, fecha_imputacion,
  comprobante_objeto_id, referencia_externa)
values ('ca7e15f0-0000-4000-8000-000000000201', 'qorilazo', 9000, 'PEN', 'DNI', '71234567', 'CLIENTE TRANSPORTE',
  'OP-TRANSPORTE-1', '{V}', '{V}', 'ca7e15f0-0000-4000-8000-000000000101', false, date '2026-08-20', date '2026-09-15',
  'ca7e15f0-0000-4000-8000-000000000901', 'REF-TR-1');
insert into crm.inversiones (id, inversionista_id, empresa_id, cierre_externo_id, estado, fecha_comercial)
values ('ca7e15f0-0000-4000-8000-000000000301', 'ca7e15f0-0000-4000-8000-000000000101', gen_random_uuid(),
  'ca7e15f0-0000-4000-8000-000000000201', 'vigente', date '2026-08-20');
insert into crm.inversion_ajustes_mes_cerrado (inversion_id, periodo_origen, fecha_imputacion, creado_por)
values ('ca7e15f0-0000-4000-8000-000000000301', date '2026-08-01', date '2026-09-15', '{G}');
-- Dos conversiones de septiembre: una a tiempo y otra «fuera de plazo».
insert into crm.leads (id, nombre_completo, telefono, etapa, origen, vendedor_id, inversionista_id, convertido_en, monto_estimado, creado_en)
values ('ca7e15f0-0000-4000-8000-000000000401', 'LEAD TRANSPORTE 1', '+51961000001', 'convertido', 'formulario', '{V}',
        'ca7e15f0-0000-4000-8000-000000000102', timestamptz '2026-09-20 10:00-05', 1000, timestamptz '2026-09-10 10:00-05'),
       ('ca7e15f0-0000-4000-8000-000000000402', 'LEAD TRANSPORTE 2', '+51961000002', 'convertido', 'formulario', '{V}',
        'ca7e15f0-0000-4000-8000-000000000103', timestamptz '2026-09-25 10:00-05', 1000, timestamptz '2026-09-12 10:00-05');
insert into crm.lead_asignaciones (id, lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en, moneda, origen,
  sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en, primer_contacto_limite_en, resultado,
  resultado_en, finalizado_en, finalizado_por, motivo_cierre)
values ('ca7e15f0-0000-4000-8000-000000000501', 'ca7e15f0-0000-4000-8000-000000000401', 1, 1, '{V}', 'asignado',
        timestamptz '2026-09-10 10:00-05', 'PEN', 'formulario', timestamptz '2026-09-10 10:00-05', gen_random_uuid(),
        timestamptz '2026-09-10 10:00-05', timestamptz '2026-09-10 10:00-05', 'convertido', timestamptz '2026-09-20 10:00-05',
        timestamptz '2026-09-20 10:00-05', '{V}', 'convertido'),
       ('ca7e15f0-0000-4000-8000-000000000502', 'ca7e15f0-0000-4000-8000-000000000402', 1, 1, '{V}', 'asignado',
        timestamptz '2026-09-12 10:00-05', 'PEN', 'formulario', timestamptz '2026-09-12 10:00-05', gen_random_uuid(),
        timestamptz '2026-09-12 10:00-05', timestamptz '2026-09-12 10:00-05', 'convertido', timestamptz '2026-09-25 10:00-05',
        timestamptz '2026-09-25 10:00-05', '{V}', 'convertido');
insert into crm.cierres_externos (id, lead_id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo,
  numero_transaccion, vendedor_id, creado_por, inversionista_id, es_cierre_inicial, fecha_comercial, fecha_imputacion)
values ('ca7e15f0-0000-4000-8000-000000000601', 'ca7e15f0-0000-4000-8000-000000000401', 'prodelco', 5000, 'PEN', 'DNI', '72345678',
        'CLIENTE TRANSPORTE DOS', 'OP-TRANSPORTE-2', '{V}', '{V}', 'ca7e15f0-0000-4000-8000-000000000102', true, date '2026-09-20', date '2026-09-20'),
       ('ca7e15f0-0000-4000-8000-000000000602', 'ca7e15f0-0000-4000-8000-000000000402', 'prodelco', 6000, 'PEN', 'DNI', '73456789',
        'CLIENTE TRANSPORTE TRES', 'OP-TRANSPORTE-3', '{V}', '{V}', 'ca7e15f0-0000-4000-8000-000000000103', true, date '2026-09-25', date '2026-09-25');
set local session_replication_role = origin;
insert into crm.conversion_acreditaciones (lead_id, episodio_id, inversionista_id, analista_id, origen, fuente_tipo, fuente_id,
  fecha_comercial, confirmado_en, vinculado_en, acreditado_en, periodo_comercial, plazo_hasta, estado, motivo)
values ('ca7e15f0-0000-4000-8000-000000000401', 'ca7e15f0-0000-4000-8000-000000000501', 'ca7e15f0-0000-4000-8000-000000000102',
        '{V}', 'formulario', 'cierre_externo', 'ca7e15f0-0000-4000-8000-000000000601', date '2026-09-20',
        timestamptz '2026-09-20 10:00-05', timestamptz '2026-09-20 10:00-05', timestamptz '2026-09-20 10:00-05',
        date '2026-09-01', timestamptz '2026-10-11 00:00-05', 'acreditada', 'Siembra del transporte'),
       ('ca7e15f0-0000-4000-8000-000000000402', 'ca7e15f0-0000-4000-8000-000000000502', 'ca7e15f0-0000-4000-8000-000000000103',
        '{V}', 'formulario', 'cierre_externo', 'ca7e15f0-0000-4000-8000-000000000602', date '2026-09-25',
        now() - interval '1 hour', now() - interval '1 hour', now() - interval '1 hour',
        date '2026-09-01', timestamptz '2026-10-11 00:00-05', 'fuera_de_plazo', 'Siembra del transporte');
"""

# Los registros de los trinquetes de producción (leer-registros-produccion.sql), tabla por tabla; o, sin ellos, solo la
# declaración analítica de crm.cerrar_periodo como la de producción (clase analitica, huella del cuerpo de antes).
TABLAS_REGISTROS = {
    "f7": "private.f7_piezas_en_observacion",
    "analitica_exenciones": "private.analitica_leads_citas_exenciones",
    "analitica_tope": "private.analitica_leads_citas_tope",
    "analitica_sello": "private.analitica_lc_sello",
    "vigencia_exenciones": "private.analista_vigencia_exenciones",
    "vigencia_tope": "private.analista_vigencia_tope",
    "auditoria_exenciones": "private.auditoria_exenciones",
    "auditoria_condicionada": "private.auditoria_condicionada",
    "auditoria_sello": "private.auditoria_sello",
}


def registros_de(ruta):
    """El objeto `registros` de la salida JSON de `db query -o json` (filas envueltas)."""
    def hallar(x):
        if isinstance(x, dict):
            if "registros" in x:
                return x["registros"]
            for v in x.values():
                r = hallar(v)
                if r is not None:
                    return r
        if isinstance(x, list):
            for v in x:
                r = hallar(v)
                if r is not None:
                    return r
        return None
    r = hallar(json.loads(pathlib.Path(ruta).read_text(encoding="utf-8")))
    return json.loads(r) if isinstance(r, str) else r


if len(sys.argv) == 3:
    REGS = registros_de(sys.argv[2])
    partes = ["set local session_replication_role = replica;"]
    for clave, tabla in TABLAS_REGISTROS.items():
        j = json.dumps(REGS.get(clave) or [], ensure_ascii=False)
        assert "$registros$" not in j
        partes.append(f"insert into {tabla} select * from pg_catalog.jsonb_populate_recordset(null::{tabla}, "
                      f"$registros${j}$registros$::jsonb);")
    partes.append("set local session_replication_role = origin;")
    REGISTROS = "\n".join(partes) + "\n"
    ORIGEN_REGISTROS = f"registros reales de producción ({len(REGS.get('analitica_exenciones') or [])} declaraciones analíticas)"
else:
    REGISTROS = """
insert into private.analitica_leads_citas_exenciones (objeto, tipo, huella, razon, clase)
values ('crm.cerrar_periodo(date)', 'funcion', '8073f806d602fd55532f1f9d4651b7d4',
        'TRANSPORTE: declaración analítica sembrada como la de producción (clase analitica, huella del cuerpo de antes).',
        'analitica');
insert into private.analitica_leads_citas_tope (id, tope) values (true, 14);
insert into private.analitica_lc_sello (id, sello) values (true, private.huella_exenciones_analitica_lc());
"""
    ORIGEN_REGISTROS = "declaración analítica sintética de crm.cerrar_periodo"
print(f"Mundo de E1: {ORIGEN_REGISTROS}")

# ── E1 · el ensayo del LEEME (sed '/^commit;$/d' + vista-previa.sql), sobre el mundo sembrado ──────────────────────────
assert len(re.findall(r"(?m)^commit;$", MIG)) == 1
ensayo = re.sub(r"(?m)^commit;$\n?", "", MIG) + VISTA
# El andamiaje (retirar la migración del banco y sembrar) va en un mensaje ANTERIOR de la misma sesión y transacción; el
# mensaje que se prueba es EXACTAMENTE el del paso 1 del LEEME (la migración sin su commit + la vista previa).
REVERSA_SIN_RESULTADO = sin_tx(REVERSA).replace(
    "select 'REVERSA de 20261015000852_crm_plazo_carga_mes aplicada: plazo fijo, candados y CHECK como antes; tablas y "
    "puertas retiradas' as resultado;", "")
andamiaje = ("begin;\n" + REVERSA_SIN_RESULTADO
    + "\ndrop table pg_temp._plazo_trinquetes;\nset local search_path = '';\n" + SIEMBRA + "\n" + REGISTROS + "\n")
for nombre, texto in (("andamiaje", andamiaje), ("ensayo", ensayo)):
    assert len(texto.encode("utf-8")) < 128 * 1024, f"el {nombre} pasa de 128 KB ({len(texto.encode('utf-8'))} bytes)"
CENSO = ("select 'CENSO ' || c::text || ' · huella ' || coalesce((select e.huella from private.analitica_leads_citas_exenciones e "
         "where e.objeto = 'crm.cerrar_periodo(date)'), '-') || ' · sello al dia ' || coalesce(((select s.sello from "
         "private.analitica_lc_sello s where s.id) = private.huella_exenciones_analitica_lc())::text, '-') "
         "from private.contadores_crudos_leads_citas() c where c.objeto = 'crm.cerrar_periodo(date)';")
rc, out = un_mensaje(ensayo, previo=andamiaje)
caso("E1 el ensayo del LEEME pasa preflight, postflight y la foto de trinquetes, y termina en ROLLBACK",
     rc == 0 and "ENSAYO OK" in out, out)
caso("E1 el postflight ejecutó los intentos que deben rebotar (foto, sello, rastro y cierre externo)",
     all(x in out for x in ["rebota la foto", "rebota el sello", "rebota el rastro", "rebota el cierre externo"]), out)
caso("E1 la vista previa: septiembre abierto no se reabre, una reevaluada, sin conflictos",
     '"reabierto": false' in out and '"acreditaciones_reevaluadas": 1' in out and '"conflictos_identidad": 0' in out, out)
rc2, out2 = un_mensaje("select (select count(*) from crm.periodos_cerrados) + (select count(*) from public.perfiles) "
                       "+ (select count(*) from crm.plazos_carga_mes) + (select count(*) from public.audit_log);")
caso("E1 el banco quedó como estaba (todo deshecho)", rc2 == 0 and out2.strip() == "0", out2)

# ── E1b · la vista previa falla si fijar el plazo de septiembre falla ───────────────────────────────────────────────
OCTUBRE_SELLADO = """
set local session_replication_role = replica;
insert into crm.periodos_cerrados (periodo, cerrado_en, automatico, ponderacion_referido, meta_revision, cobertura)
values (date '2026-10-01', now(), true, 0.15, 1, '{}');
set local session_replication_role = origin;
"""
rc, out = un_mensaje(ensayo, previo=andamiaje.replace(SIEMBRA, SIEMBRA + OCTUBRE_SELLADO, 1))
caso("E1b el ensayo FALLA (sin «ENSAYO OK») si la operación simulada falla",
     rc != 0 and "ENSAYO OK" not in out and "VISTA PREVIA: fijar el plazo de septiembre falló" in out
     and "quedó por detrás del último mes cerrado" in out, out)
rc2, out2 = un_mensaje("select (select count(*) from crm.periodos_cerrados) + (select count(*) from public.perfiles) "
                       "+ (select count(*) from crm.plazos_carga_mes) + (select count(*) from public.audit_log);")
caso("E1b el banco quedó como estaba (todo deshecho)", rc2 == 0 and out2.strip() == "0", out2)

# ── E1c · aplicar → registrar → verificar → reversa, sobre el mismo mundo, en una transacción que se deshace ─────────
# (Pasa de 128 KB: va por archivo, sentencia a sentencia; aquí no se prueba el transporte sino el ciclo.)
SOLTAR_TEMPORALES = ("\ndrop table if exists pg_temp._plazo_trinquetes;\ndrop table if exists pg_temp._reversa_censo_antes;\n"
                     "drop table if exists pg_temp._reversa_censo_tope_antes;\n")
ciclo = (andamiaje
         + "select 'CENSO_ANTES';\n" + CENSO + "\n"
         + sin_tx(MIG) + "\n"
         + sin_tx(REG) + "\n"
         + (AQUI / "verificar-produccion.sql").read_text(encoding="utf-8") + "\n"
         + "select 'CENSO_APLICADA';\n" + CENSO + "\n"
         + SOLTAR_TEMPORALES + REVERSA_SIN_RESULTADO + "\n"
         + "select 'CENSO_REVERSA';\n" + CENSO + "\n"
         + "select 'tablas nuevas tras la reversa: ' || (to_regclass('crm.plazos_carga_mes') is not null)::text;\n"
         + "rollback;\n")
rc, out = un_mensaje(ciclo, por_archivo=True)
tramos = re.split(r"(?m)^CENSO_(?:ANTES|APLICADA|REVERSA)$", out)
caso("E1c el ciclo entero corre sin error (aplicar, registrar, verificar, reversa)", rc == 0 and len(tramos) == 4, out)
if rc == 0 and len(tramos) == 4:
    vivo = '(funcion,"crm.cerrar_periodo(date)",t,t)'
    caso("E1c antes: la declaración de producción, vigente, con la huella de antes y el sello al día",
         f"CENSO {vivo} · huella 8073f806d602fd55532f1f9d4651b7d4 · sello al dia true" in tramos[1], tramos[1])
    # La salida de verificar-produccion.sql sale ANTES de la marca CENSO_APLICADA: está en el tramo 1.
    caso("E1c verificar: «APLICADA Y REGISTRADA» con la declaración re-sellada",
         '"veredicto": "APLICADA Y REGISTRADA"' in tramos[1] and '"huella": "4b89856af0ebc6c4e46f6ffef8be61af"' in tramos[1]
         and '"vigente": true' in tramos[1] and '"sello_al_dia": true' in tramos[1], tramos[1][-3000:])
    caso("E1c aplicada: el censo la ve vigente con la huella nueva y el sello al día",
         f"CENSO {vivo} · huella 4b89856af0ebc6c4e46f6ffef8be61af · sello al dia true" in tramos[2], tramos[2][-1500:])
    caso("E1c reversa: vuelve a la huella de antes, vigente, con el sello al día, y retira las tablas",
         f"CENSO {vivo} · huella 8073f806d602fd55532f1f9d4651b7d4 · sello al dia true" in tramos[3]
         and "tablas nuevas tras la reversa: false" in tramos[3], tramos[3])
rc2, out2 = un_mensaje("select (select count(*) from crm.periodos_cerrados) + (select count(*) from public.perfiles) "
                       "+ (select count(*) from crm.plazos_carga_mes) + (select count(*) from public.audit_log) "
                       "+ (select count(*) from private.analitica_leads_citas_exenciones) "
                       "+ (select count(*) from private.analitica_lc_sello);")
caso("E1c el banco quedó como estaba (todo deshecho, sin registros sembrados)", rc2 == 0 and out2.strip() == "0", out2)

# ── E4 · mutantes del re-sellado: la migración mutada, sobre el mundo de E1, tiene que NEGARSE ────────────────────────
RESELLO_UPDATE = ("  update private.analitica_leads_citas_exenciones\n     set huella = v_huella\n"
                  "   where objeto = 'crm.cerrar_periodo(date)' and huella = '8073f806d602fd55532f1f9d4651b7d4';\n")
RESELLO_SELLO = ("    update private.analitica_lc_sello\n       set sello = private.huella_exenciones_analitica_lc(), "
                 "sellado_en = pg_catalog.now()\n     where id;\n")
inicio_resello = MIG.index("do $resello$\n")
fin_resello = MIG.index("$resello$;\n", inicio_resello) + len("$resello$;\n")
MUTANTES_RESELLO = [
    ("MR1 sin el re-sellado", MIG[inicio_resello:fin_resello], ""),
    ("MR2 re-sella OTRA huella", RESELLO_UPDATE, RESELLO_UPDATE.replace("set huella = v_huella",
                                                                        "set huella = pg_catalog.md5(v_huella)")),
    ("MR3 toca la razón", RESELLO_UPDATE, RESELLO_UPDATE.replace("set huella = v_huella",
                                                                 "set huella = v_huella, razon = razon || ' (re-sellada)'")),
    ("MR4 toca la clase", RESELLO_UPDATE, RESELLO_UPDATE.replace("set huella = v_huella",
                                                                 "set huella = v_huella, clase = 'mixta'")),
    ("MR5 no re-sella la lista", RESELLO_SELLO, "    perform 1;\n"),
]
for nombre, viejo, nuevo in MUTANTES_RESELLO:
    assert MIG.count(viejo) == 1, f"{nombre}: el texto a cambiar aparece {MIG.count(viejo)} veces"
    mutada = re.sub(r"(?m)^commit;$\n?", "", MIG.replace(viejo, nuevo, 1)) + "\nrollback;\n"
    rc, out = un_mensaje(mutada, previo=andamiaje)
    caso(f"E4 {nombre}: la migración mutada se NIEGA sobre el mundo de producción",
         rc != 0 and ("POSTFLIGHT plazo_carga_mes" in out or "RESELLO plazo_carga_mes" in out), out)
rc2, out2 = un_mensaje("select (select count(*) from crm.periodos_cerrados) + (select count(*) from public.perfiles) "
                       "+ (select count(*) from crm.plazos_carga_mes) + (select count(*) from public.audit_log) "
                       "+ (select count(*) from private.analitica_leads_citas_exenciones);")
caso("E4 el banco quedó como estaba (todo deshecho)", rc2 == 0 and out2.strip() == "0", out2)

# ── E2 · la reversa se niega con una decisión de plazo ──────────────────────────────────────────────────────────────
rc, out = un_mensaje(f"""begin;
set local session_replication_role = replica;
insert into public.perfiles (id, nombre_completo, rol, activo) values ('{G}', 'GERENCIA REVERSA', 'comercial', true);
set local session_replication_role = origin;
insert into crm.plazos_carga_mes (periodo, ultimo_dia, plazo_hasta, motivo, decidido_por)
values (date '2026-09-01', date '2026-10-20', timestamptz '2026-10-21 00:00-05', 'Decisión que impide la reversa', '{G}');
{sin_tx(REVERSA)}
rollback;""")
caso("E2 la reversa se niega si ya hay decisiones de plazo", rc != 0 and "ya hay decisiones de plazo o reaperturas" in out, out)

# ── E3 · el registrador ─────────────────────────────────────────────────────────────────────────────────────────────
reg = sin_tx(REG)
rc, out = un_mensaje("begin;\n" + reg + "\n" + reg + "\nselect 'filas=' || count(*) from supabase_migrations.schema_migrations "
                     "where version = '20261015000852';\nrollback;", por_archivo=True)
caso("E3 el registrador registra el archivo entero y es idempotente", rc == 0 and "filas=1" in out, out)
rc, out = un_mensaje("begin;\n" + sin_tx(REVERSA) + "\n" + reg + "\nrollback;", por_archivo=True)
caso("E3 el registrador se niega si la migración no está aplicada", rc != 0 and "no está aplicada" in out, out)

fallas = resultados.count(False)
print(f"TRANSPORTE: {len(resultados) - fallas}/{len(resultados)} PASS")
sys.exit(1 if fallas else 0)

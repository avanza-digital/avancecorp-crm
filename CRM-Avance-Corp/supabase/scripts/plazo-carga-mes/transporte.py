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
  E2 · La reversa se NIEGA si ya hay una decisión de plazo (y no toca nada).
  E3 · El registrador: registra, es idempotente, y se niega si la migración no está.

Uso:  python3 -I supabase/scripts/plazo-carga-mes/transporte.py supabase_db_<project_id>
"""
import pathlib
import re
import subprocess
import sys

if len(sys.argv) != 2 or not sys.argv[1].startswith("supabase_db_"):
    sys.exit("Uso: transporte.py supabase_db_<project_id> (un banco local, nunca producción)")
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

# ── E1 · el ensayo del LEEME (sed '/^commit;$/d' + vista-previa.sql), sobre el mundo sembrado ──────────────────────────
assert len(re.findall(r"(?m)^commit;$", MIG)) == 1
ensayo = re.sub(r"(?m)^commit;$\n?", "", MIG) + VISTA
# El andamiaje (retirar la migración del banco y sembrar) va en un mensaje ANTERIOR de la misma sesión y transacción; el
# mensaje que se prueba es EXACTAMENTE el del paso 1 del LEEME (la migración sin su commit + la vista previa).
andamiaje = ("begin;\n" + sin_tx(REVERSA).replace(
    "select 'REVERSA de 20261015000852_crm_plazo_carga_mes aplicada: plazo fijo, candados y CHECK como antes; tablas y "
    "puertas retiradas' as resultado;", "")
    + "\ndrop table pg_temp._plazo_trinquetes;\nset local search_path = '';\n" + SIEMBRA + "\n")
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

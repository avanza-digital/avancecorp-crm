#!/usr/bin/env python3
"""Lo que prueba.sql no puede probar en UNA sesión, con dos conexiones reales al banco (NUNCA producción).

  T1 · La autorización NO pasa a otra transacción: una reapertura de un mes registrada y confirmada (COMMIT) en otra
       transacción no deja borrar el sello de ese mes después. Y dentro de su propia transacción, sí.
  T2 · La puerta espera el candado MENSUAL del cierre (el que toman crm.cerrar_periodo y los escritores de dinero): con
       otra sesión reteniéndolo, la puerta no avanza (lock_timeout → 55P03).
  T3 · Lo mismo con el candado GLOBAL.
  T4 · Mutante: la puerta SIN sus dos candados ya no espera (el T2 lo detecta).
  T5 · La reevaluación espera el candado de la IDENTIDAD (el del escritor de acreditaciones) antes de acreditar.
  T6 · Mutante: la reevaluación sin ese candado ya no espera (el T5 lo detecta).
  T7 · La carrera del sello (revisión Codex r1, P1): Gerencia amplía un mes cuya ventana ya abrió (sin confirmar, con los
       candados del cierre); el sello de ese mes —crm.cerrar_periodo a mano y el ciclo diario— pasa la primera mirada a
       la ventana y espera el candado; Gerencia confirma; el sello vuelve a mirar la ventana con los candados y se NIEGA
       (22023): el mes no se sella antes del último día que decidió Gerencia. Control: sin la ampliación, sí se sella.
  T8 · Mutante: crm.cerrar_periodo con su cuerpo de antes (sin la segunda mirada) sella igual (el T7 lo detecta).

Siembra y limpia lo suyo (un mes sellado sintético de 2001, un perfil de Gerencia y una conversión «fuera de plazo»), como supabase_admin con los
disparadores apagados solo para sembrar y limpiar. Deja el banco como estaba.

Uso:  python3 -I supabase/scripts/plazo-carga-mes/dos-sesiones.py supabase_db_<project_id>
"""
import pathlib
import re
import subprocess
import sys
import time

if len(sys.argv) != 2 or not sys.argv[1].startswith("supabase_db_"):
    sys.exit("Uso: dos-sesiones.py supabase_db_<project_id> (un banco local, nunca producción)")
C = sys.argv[1]
MIGRACION = (pathlib.Path(__file__).resolve().parent.parent.parent / "migrations"
             / "20261015000852_crm_plazo_carga_mes.sql").read_text(encoding="utf-8")
G = "ca7e15d0-0000-4000-8000-0000000000a1"
P2099 = "2001-07-01"   # un mes sellado sintético ANTERIOR a todo (no deja meses «por detrás» de él)
PERSONA = "ca7e15d0-0000-4000-8000-000000000101"
LEAD = "ca7e15d0-0000-4000-8000-000000000201"
EPISODIO = "ca7e15d0-0000-4000-8000-000000000301"
CIERRE = "ca7e15d0-0000-4000-8000-000000000401"
META = "ca7e15d0-0000-4000-8000-000000000501"
META_ANT = "ca7e15d0-0000-4000-8000-000000000502"
MES_ANT = "(date_trunc('month', now() at time zone 'America/Lima') - interval '1 month')::date"
# Hace dos meses: su ventana de sello abrió hace un mes, cualquier día que se corra (T7/T8).
M2 = "(date_trunc('month', now() at time zone 'America/Lima') - interval '2 month')::date"
REVERSA = (pathlib.Path(__file__).resolve().parent / "reversa.sql").read_text(encoding="utf-8")


def psql(sql, usuario="postgres", esperar_error=False):
    r = subprocess.run(["docker", "exec", "-i", "-e", "PGPASSWORD=postgres", C, "psql", "-X", "-U", usuario, "-h",
                        "127.0.0.1", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-qAt"],
                       input=sql, capture_output=True, text=True, timeout=120)
    if r.returncode != 0 and not esperar_error:
        raise SystemExit(f"FALLA de corrida: {r.stderr.strip()}")
    return r.returncode, (r.stdout + r.stderr).strip()


class Sesion:
    """Una conexión que se queda abierta con una transacción viva."""
    def __init__(self, sql_inicial, marca):
        self.p = subprocess.Popen(["docker", "exec", "-i", "-e", "PGPASSWORD=postgres", C, "psql", "-X", "-U", "postgres",
                                   "-h", "127.0.0.1", "-d", "postgres", "-qAt"],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.p.stdin.write(sql_inicial + f"\nselect '{marca}';\n")
        self.p.stdin.flush()
        while True:
            linea = self.p.stdout.readline()
            if not linea:
                raise SystemExit("la sesión que retiene el candado se cerró antes de tiempo")
            if linea.strip() == marca:
                break

    def cerrar(self):
        self.p.stdin.write("rollback;\n\\q\n")
        self.p.stdin.flush()
        self.p.wait(timeout=30)

    def confirmar(self):
        self.p.stdin.write("commit;\n\\q\n")
        self.p.stdin.flush()
        self.p.wait(timeout=30)


resultados = []


def caso(nombre, ok, detalle=""):
    resultados.append((nombre, ok))
    print(("PASS" if ok else "FALLA") + f": {nombre}" + (f" — {detalle}" if detalle and not ok else ""))


SIEMBRA = f"""
begin;
set local session_replication_role = replica;
insert into public.perfiles (id, nombre_completo, rol, activo) values ('{G}', 'GERENCIA DOS SESIONES', 'comercial', true);
insert into crm.equipo (perfil_id, rol_crm, activo) values ('{G}', 'gerencia', true);
insert into crm.periodos_cerrados (periodo, cerrado_en, automatico, ponderacion_referido, meta_revision, cobertura)
values ('{P2099}', now(), true, 0.15, 1, '{{}}'::jsonb);
-- Metas de hace dos meses (sin analistas): así el ciclo diario lo ve como el mes pendiente de sellar (T7/T8). Y lo que
-- el sello necesita para calcular la foto (el peso del referido y la política de conversión), como en prueba.sql.
insert into crm.meta_periodos (id, periodo, revision, publicada_en, publicada_por) values ('{META}', {M2}, 1, now(), '{G}');
-- Metas del mes anterior: solo un mes con metas admite plazo (revisión Codex r2), y T2/T3/T5 fijan el del mes anterior.
insert into crm.meta_periodos (id, periodo, revision, publicada_en, publicada_por) values ('{META_ANT}', {MES_ANT}, 1, now(), '{G}');
insert into crm.conversion_pesos (vigente_desde, peso_referido, nota) values (date '2025-01-01', 0.150, 'dos sesiones plazo');
insert into crm.conversion_politica (unica, vigente_desde, activada_en, manifiesto_huella, resultado)
values (true, date '2026-09-01', now() - interval '45 days', 'dos-sesiones-plazo', '{{}}'::jsonb);
-- Una conversión del mes anterior «fuera de plazo» (para que la reevaluación tenga a quién acreditar).
insert into crm.inversionistas (id, estado) values ('{PERSONA}', 'activo');
insert into crm.leads (id, nombre_completo, telefono, etapa, origen, vendedor_id, inversionista_id, convertido_en, monto_estimado, creado_en)
values ('{LEAD}', 'LEAD DOS SESIONES', '+51962000001', 'convertido', 'formulario', '{G}', '{PERSONA}', now() - interval '2 days', 1000,
        now() - interval '9 days');
insert into crm.lead_asignaciones (id, lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en, moneda, origen,
  sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en, primer_contacto_limite_en, resultado, resultado_en,
  finalizado_en, finalizado_por, motivo_cierre)
values ('{EPISODIO}', '{LEAD}', 1, 1, '{G}', 'asignado', now() - interval '9 days', 'PEN', 'formulario', now() - interval '9 days',
        gen_random_uuid(), now() - interval '9 days', now() - interval '9 days', 'convertido', now() - interval '2 days',
        now() - interval '2 days', '{G}', 'convertido');
insert into crm.cierres_externos (id, lead_id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo,
  numero_transaccion, vendedor_id, creado_por, inversionista_id, es_cierre_inicial, fecha_comercial, fecha_imputacion)
values ('{CIERRE}', '{LEAD}', 'qorilazo', 1000, 'PEN', 'DNI', '74000001', 'CLIENTE DOS SESIONES', 'OP-DOS-SESIONES-1',
        '{G}', '{G}', '{PERSONA}', true, {MES_ANT} + 20, {MES_ANT} + 20);
insert into crm.conversion_acreditaciones (lead_id, episodio_id, inversionista_id, analista_id, origen, fuente_tipo, fuente_id,
  fecha_comercial, confirmado_en, vinculado_en, acreditado_en, periodo_comercial, plazo_hasta, estado, motivo)
values ('{LEAD}', '{EPISODIO}', '{PERSONA}', '{G}', 'formulario', 'cierre_externo', '{CIERRE}', {MES_ANT} + 20,
        now() - interval '1 hour', now() - interval '1 hour', now() - interval '1 hour', {MES_ANT},
        private.conversion_plazo_base({MES_ANT}), 'fuera_de_plazo', 'Siembra de dos sesiones');
commit;
"""
LIMPIEZA = f"""
begin;
set local session_replication_role = replica;
delete from public.audit_log where usuario_id = '{G}'
   or fila_id in (select id::text from crm.reaperturas_mes where periodo = '{P2099}' or decidido_por = '{G}');
delete from crm.plazos_carga_mes where decidido_por = '{G}';
delete from crm.conversion_acreditaciones where lead_id = '{LEAD}';
delete from crm.cierres_externos where id = '{CIERRE}';
delete from crm.lead_asignaciones where id = '{EPISODIO}';
delete from crm.leads where id = '{LEAD}';
delete from crm.inversionistas where id = '{PERSONA}';
delete from crm.reaperturas_mes where periodo = '{P2099}' or decidido_por = '{G}';
delete from crm.periodos_cerrados where periodo = '{P2099}';
delete from crm.cierre_mes_vendedor where periodo = {M2};
delete from crm.periodos_cerrados where periodo = {M2};
delete from crm.meta_periodos where id in ('{META}', '{META_ANT}');
delete from crm.conversion_pesos where nota = 'dos sesiones plazo';
delete from crm.conversion_politica where manifiesto_huella = 'dos-sesiones-plazo';
delete from crm.equipo where perfil_id = '{G}';
delete from public.perfiles where id = '{G}';
commit;
"""
psql(LIMPIEZA, "supabase_admin")
psql(SIEMBRA, "supabase_admin")
try:
    # ── T1 · otra transacción ─────────────────────────────────────────────────────────────────────────────────────────
    psql(f"""begin;
insert into crm.reaperturas_mes (periodo, motivo, decidido_por, respaldo, resumen)
values ('{P2099}', 'Reapertura confirmada en otra transacción', '{G}',
        '{{"sello":{{}},"foto":[],"acreditaciones":[],"rastros_tardios":[],"cierres_externos":[]}}'::jsonb, '{{}}'::jsonb);
commit;""")
    rc, out = psql(f"begin; delete from crm.periodos_cerrados where periodo = '{P2099}'; rollback;", esperar_error=True)
    caso("T1 una reapertura de OTRA transacción (confirmada) no autoriza a borrar el sello",
         rc != 0 and "Un mes cerrado no se edita ni se borra" in out, out)
    rc, out = psql(f"""begin;
insert into crm.reaperturas_mes (periodo, motivo, decidido_por, respaldo, resumen)
values ('{P2099}', 'Reapertura de esta transacción', '{G}',
        '{{"sello":{{}},"foto":[],"acreditaciones":[],"rastros_tardios":[],"cierres_externos":[]}}'::jsonb, '{{}}'::jsonb);
delete from crm.periodos_cerrados where periodo = '{P2099}';
select 'borrado ' || (not exists (select 1 from crm.periodos_cerrados where periodo = '{P2099}'))::text;
rollback;""", esperar_error=True)
    caso("T1 en SU transacción la reapertura sí autoriza (control)", rc == 0 and "borrado true" in out, out)

    # ── T2/T3 · los candados ──────────────────────────────────────────────────────────────────────────────────────────
    def llamar_puerta(extra=""):
        return psql(f"""begin;
set local lock_timeout = '2s';
{extra}
select set_config('request.jwt.claim.sub', '{G}', true),
       set_config('request.jwt.claims', json_build_object('sub', '{G}', 'role', 'authenticated')::text, true);
select crm.fijar_plazo_carga_mes(
  (date_trunc('month', now() at time zone 'America/Lima') - interval '1 month')::date,
  (now() at time zone 'America/Lima')::date + 5, 'Prueba de candados con dos sesiones');
rollback;""", esperar_error=True)

    mensual = ("select pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'), "
               "((date_trunc('month', now() at time zone 'America/Lima') - interval '1 month')::date - date '2000-01-01')::integer);")
    rc, out = llamar_puerta()
    caso("T2 control: sin nadie reteniendo, la puerta responde", rc == 0 and '"ok": true' in out, out)

    a = Sesion("begin;\n" + mensual, "MENSUAL TOMADO")
    t0 = time.monotonic()
    rc, out = llamar_puerta()
    a.cerrar()
    caso("T2 la puerta ESPERA el candado mensual del cierre (55P03 con otra sesión reteniéndolo)",
         rc != 0 and "lock timeout" in out and time.monotonic() - t0 >= 1.5, out)

    a = Sesion("begin;\nselect pg_advisory_xact_lock(hashtext('crm.periodos_cerrados')::bigint);", "GLOBAL TOMADO")
    rc, out = llamar_puerta()
    a.cerrar()
    caso("T3 la puerta ESPERA el candado global del cierre", rc != 0 and "lock timeout" in out, out)

    # ── T4 · mutante: la puerta sin sus candados ──────────────────────────────────────────────────────────────────────
    m = re.search(r"(?m)^create function private\.fijar_plazo_carga\(", MIGRACION)
    fin = MIGRACION.index("$function$;", MIGRACION.index("$function$", m.end()) + 10) + len("$function$;")
    cuerpo = MIGRACION[m.start():fin].replace("create function", "create or replace function", 1)
    candados = ("  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);\n"
                "  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),\n"
                "    (p_periodo - date '2000-01-01')::integer);\n")
    assert cuerpo.count(candados) == 1, "no encuentro los candados del núcleo de la puerta"
    mutante = cuerpo.replace(candados, "")
    a = Sesion("begin;\n" + mensual, "MENSUAL TOMADO")
    rc, out = llamar_puerta(mutante)
    a.cerrar()
    caso("T4 mutante «núcleo de la puerta sin candados»: ya no espera (el T2 lo caza)", rc == 0 and '"ok": true' in out, out)

    # ── T5/T6 · el candado de la identidad en la reevaluación ───────────────────────────────────────────────────────
    identidad = ("select pg_advisory_xact_lock(hashtext('crm.conversion_acreditaciones'), "
                 f"hashtext('{PERSONA}'));")
    rc, out = llamar_puerta()
    caso("T5 control: sin nadie reteniendo la identidad, la puerta reevalúa (una acreditada)",
         rc == 0 and '"acreditaciones_reevaluadas": 1' in out, out)
    a = Sesion("begin;\n" + identidad, "IDENTIDAD TOMADA")
    rc, out = llamar_puerta()
    a.cerrar()
    caso("T5 la reevaluación ESPERA el candado de la identidad (como el escritor)", rc != 0 and "lock timeout" in out, out)
    m = re.search(r"(?m)^create function private\.conversion_reevaluar_plazo\(", MIGRACION)
    fin = MIGRACION.index("$function$;", MIGRACION.index("$function$", m.end()) + 10) + len("$function$;")
    cuerpo = MIGRACION[m.start():fin].replace("create function", "create or replace function", 1)
    candado = ("      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.conversion_acreditaciones'),\n"
               "        pg_catalog.hashtext(v_persona::text));\n")
    assert cuerpo.count(candado) == 1, "no encuentro el candado de identidad de la reevaluación"
    a = Sesion("begin;\n" + identidad, "IDENTIDAD TOMADA")
    rc, out = llamar_puerta(cuerpo.replace(candado, ""))
    a.cerrar()
    caso("T6 mutante «reevaluación sin el candado de identidad»: ya no espera (el T5 lo caza)",
         rc == 0 and '"acreditaciones_reevaluadas": 1' in out, out)

    # ── T7/T8 · la carrera del sello con una ampliación (revisión Codex r1, P1) ───────────────────────────────────────
    def quitar_decision():
        psql(f"""begin;
set local session_replication_role = replica;
delete from public.audit_log where usuario_id = '{G}' and tabla = 'crm.plazos_carga_mes';
delete from crm.plazos_carga_mes where periodo = {M2} and decidido_por = '{G}';
commit;""", "supabase_admin")

    def carrera(llamada_b, ddl_b=""):
        """A amplía hace dos meses SIN confirmar (con los candados global y mensual); B intenta sellarlo: pasa la primera
        mirada a la ventana (abierta) y espera el candado; A confirma. Devuelve si B llegó a esperar y lo que respondió."""
        a = Sesion(f"""begin;
select set_config('request.jwt.claim.sub', '{G}', true),
       set_config('request.jwt.claims', json_build_object('sub', '{G}', 'role', 'authenticated')::text, true);
select crm.fijar_plazo_carga_mes({M2}, (now() at time zone 'America/Lima')::date + 5,
                                 'Ampliación mientras el ciclo sella');""", "AMPLIACION SIN CONFIRMAR")
        b = subprocess.Popen(["docker", "exec", "-i", "-e", "PGPASSWORD=postgres", C, "psql", "-X", "-U", "postgres", "-h",
                              "127.0.0.1", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-qAt"],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        b.stdin.write(f"begin;\nset local lock_timeout = '30s';\n{ddl_b}\n{llamada_b}\nrollback;\n")
        b.stdin.close()
        esperando = False
        t0 = time.monotonic()
        while time.monotonic() - t0 < 20:
            _, n = psql("select count(*) from pg_stat_activity where wait_event_type = 'Lock' and wait_event = 'advisory'"
                        " and query ~ '(cerrar_periodo|ciclo_cierre_mes)';")
            if n.strip() == "1":
                esperando = True
                break
            time.sleep(0.2)
        a.confirmar()
        salida = b.stdout.read()
        b.wait(timeout=120)
        return esperando, b.returncode, salida

    _, nuevo_dia = psql("select to_char((now() at time zone 'America/Lima')::date + 6, 'DD/MM/YYYY');")
    _, m2_mes = psql(f"select to_char({M2}, 'YYYY-MM');")
    sellar_m2 = f"select crm.cerrar_periodo({M2});"
    ciclo = "select crm.ciclo_cierre_mes();"
    rc, out = psql(f"begin;\n{sellar_m2}\nrollback;", esperar_error=True)
    caso("T7 control: sin ampliación, hace dos meses se sella (en una transacción que se deshace)",
         rc == 0 and '"ok": true' in out, out)
    esperando, rc, out = carrera(sellar_m2)
    _, quedo = psql(f"select count(*) from crm.periodos_cerrados where periodo = {M2};")
    caso("T7 crm.cerrar_periodo esperó a la ampliación y se NIEGA con el plazo ya confirmado (22023), sin sellar",
         esperando and rc != 0 and "no se puede cerrar antes del " + nuevo_dia.strip() in out
         and "Gerencia amplió el plazo de carga de ese mes mientras se cerraba" in out and quedo.strip() == "0", out)
    quitar_decision()
    esperando, rc, out = carrera(ciclo)
    _, quedo = psql(f"select count(*) from crm.periodos_cerrados where periodo = {M2};")
    caso("T7 el ciclo diario esperó a la ampliación: ok=false, fallo 22023 con la fecha nueva, sin sellar",
         esperando and rc == 0 and '"ok": false' in out and '"cerrados": 0' in out and '"sqlstate": "22023"' in out
         and "no se puede cerrar antes del " + nuevo_dia.strip() in out and quedo.strip() == "0", out)
    quitar_decision()
    # T8 · mutante: el cuerpo de la migración SIN la segunda mirada, que es exactamente el de antes (el de reversa.sql).
    m = re.search(r"(?m)^CREATE OR REPLACE FUNCTION crm\.cerrar_periodo\(", MIGRACION)
    fin = MIGRACION.index("$function$;", MIGRACION.index("$function$", m.end()) + 10) + len("$function$;")
    cuerpo = MIGRACION[m.start():fin]
    i = cuerpo.index("\n\n  -- 14/10/2026 (plazo de carga por mes, revisión Codex P1)")
    j = cuerpo.index("\n  end if;\n", i) + len("\n  end if;")
    sin_segunda = cuerpo[:i] + cuerpo[j:]
    m = re.search(r"(?m)^CREATE OR REPLACE FUNCTION crm\.cerrar_periodo\(", REVERSA)
    fin = REVERSA.index("$function$;", REVERSA.index("$function$", m.end()) + 10) + len("$function$;")
    assert sin_segunda == REVERSA[m.start():fin], "el mutante no es el cuerpo de antes (el de reversa.sql)"
    esperando, rc, out = carrera(sellar_m2, sin_segunda)
    caso("T8 mutante «crm.cerrar_periodo sin la segunda mirada» (el cuerpo de antes): sella igual (el T7 lo caza)",
         esperando and rc == 0 and '"ok": true' in out, out)
    quitar_decision()
    esperando, rc, out = carrera(ciclo, sin_segunda)
    # (desde el día 11 el ciclo sigue y sella también el mes anterior, que tiene metas: basta con que selle hace dos meses)
    caso("T8 mutante, por el ciclo diario: sella igual (el T7 lo caza)",
         esperando and rc == 0 and '"ok": true' in out and '"cerrados": 0' not in out
         and f'"periodo": "{m2_mes.strip()}"' in out, out)
    quitar_decision()
finally:
    psql(LIMPIEZA, "supabase_admin")
    rc, out = psql(f"select (select count(*) from crm.reaperturas_mes where periodo = '{P2099}')"
                   f" + (select count(*) from public.audit_log where tabla = 'crm.reaperturas_mes')"
                   f" + (select count(*) from public.perfiles where id = '{G}')")
    print("limpieza:", "OK" if out.strip() == "0" else out)

fallas = [n for n, ok in resultados if not ok]
print(f"DOS SESIONES: {len(resultados) - len(fallas)}/{len(resultados)} PASS")
sys.exit(1 if fallas else 0)

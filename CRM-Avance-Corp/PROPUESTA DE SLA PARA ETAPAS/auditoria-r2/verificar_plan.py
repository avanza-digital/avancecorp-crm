"""Contraejemplos del plan SLA-R1 y comprobaciones acotadas de SLA-R2.

No implementa el CRM. Las pruebas SQL usan exclusivamente cuatro tablas sintéticas
en un clúster desechable indicado explícitamente por --socket y --port.
"""
import argparse
import json
import subprocess
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


checks = []


def verify(name, condition, detail=None):
    checks.append({"caso": name, "ok": bool(condition), "detalle": detail})
    if not condition:
        raise AssertionError(name)


def models():
    day = 1440
    base, adopted_extra, later_extra = 8 * day, 8 * day, 16 * day
    verify("R1: techo legacy se mueve con politica nueva", base + later_extra != base + adopted_extra)
    verify("R2: techo legacy queda ligado a politica de adopcion", base + adopted_extra == 16 * day)

    due, margin = 12 * day, day
    before, at = due + margin - 1, due + margin
    old_before = max(base, due + margin if before < due + margin else base)
    old_at = max(base, due + margin if at < due + margin else base)
    verify("R1: al terminar margen el limite salta hacia atras", old_at < old_before,
           {"antes_dias": old_before / day, "despues_dias": old_at / day})
    stable_limit = min(max(base, due + margin), 16 * day)
    verify("R2: limite de compromiso pendiente conserva fecha al vencer", stable_limit == 13 * day)
    verify("R2: cobertura activa antes de frontera", before < stable_limit)
    verify("R2: cobertura termina exactamente en frontera", not at < stable_limit)
    verify("R2: revision empieza en frontera conservada", at >= stable_limit)

    tasks = [{"vence": 1, "contexto": False}, {"vence": 20, "contexto": True}]
    chosen_r1 = min((t for t in tasks if t["contexto"]), key=lambda t: t["vence"])
    verify("R1: filtrar contexto oculta tarea atrasada ambigua", chosen_r1["vence"] == 20)
    ambiguous = any(not t["contexto"] for t in tasks)
    verify("R2: contexto ambiguo impide usar otra tarea como cobertura", ambiguous)

    window = day
    first_event = base - 60
    too_short_extension = 30
    next_limit = base + too_short_extension
    verify("R1: prorroga corta permite consumir otra enseguida", next_limit - window <= first_event < next_limit)
    verify("R2: configuracion rechaza prorroga <= ventana", not too_short_extension > window)
    valid_extension = 4 * day
    verify("R2: segunda conversacion inmediata fuera de ventana", not base + valid_extension - window <= first_event)
    verify("R2: evento exactamente al limite no prorroga", not base < base)
    verify("R2: evento al comienzo de ventana si califica", base - window <= base - window < base)

    extra, step, maximum = 6 * day, 4 * day, 2
    verify("R1: constraint de presupuesto impide probar techo parcial", maximum * step > extra)
    grants = [step, min(step, extra - step)]
    verify("R2: techo parcial registra ganancia real", grants == [4 * day, 2 * day] and sum(grants) == extra)

    pending = {"id": "actividad-estable", "lead": "L1", "tipo": "llamada_realizada", "detalle": "A"}
    verify("R2: reintento exacto conserva identidad", dict(pending) == pending)
    collision = {**pending, "detalle": "B"}
    verify("R2: misma llave con payload diferente no confirma", collision != pending)


class Psql:
    def __init__(self, socket, port, app):
        self.proc = subprocess.Popen(
            ["/opt/homebrew/opt/postgresql@16/bin/psql", "-X", "-qAt", "-h", socket,
             "-p", str(port), "-d", "postgres", "-U", "usuario"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1,
        )
        self.run("\\set VERBOSITY verbose\nSET deadlock_timeout='150ms'; SET statement_timeout='5s'; "
                 f"SET application_name='{app}';")

    def run(self, sql):
        marker = "DONE_" + uuid.uuid4().hex
        self.proc.stdin.write(sql + "\n\\echo " + marker + "\n")
        self.proc.stdin.flush()
        out = []
        for line in self.proc.stdout:
            if line.strip() == marker:
                return "".join(out)
            out.append(line)
        raise RuntimeError("psql termino antes del marcador")

    def close(self):
        if self.proc.poll() is None:
            self.proc.stdin.write("ROLLBACK;\n\\q\n")
            self.proc.stdin.flush()
            self.proc.wait(timeout=10)


def sql_cases(socket, port):
    # Evita apuntar por accidente a un socket productivo o al PostgreSQL habitual.
    if not str(Path(socket).resolve()).startswith("/private/tmp/sla-plan-audit-r2-"):
        raise ValueError("Solo se permite el cluster temporal de esta auditoria")
    a, b, monitor = [Psql(socket, port, name) for name in ("sla_r2_a", "sla_r2_b", "sla_r2_monitor")]
    try:
        version = monitor.run("SELECT version();").strip()
        setup = monitor.run("""
CREATE TABLE audit_lead(id integer PRIMARY KEY, valor integer NOT NULL DEFAULT 0);
CREATE TABLE audit_task(id integer PRIMARY KEY, valor integer NOT NULL DEFAULT 0);
CREATE TABLE audit_control(id integer PRIMARY KEY, modo text NOT NULL);
CREATE TABLE audit_ajuste(id integer PRIMARY KEY);
INSERT INTO audit_lead VALUES(1,0);
INSERT INTO audit_task VALUES(1,0);
INSERT INTO audit_control VALUES(1,'activo');
""")
        verify("Banco SQL sintetico creado", "ERROR" not in setup, version)

        with ThreadPoolExecutor(max_workers=2) as pool:
            a.run("BEGIN; SELECT id FROM audit_lead WHERE id=1 FOR SHARE;")
            b.run("BEGIN; SELECT id FROM audit_lead WHERE id=1 FOR SHARE;")
            fa = pool.submit(a.run, "SELECT id FROM audit_lead WHERE id=1 FOR UPDATE;")
            fb = pool.submit(b.run, "SELECT id FROM audit_lead WHERE id=1 FOR UPDATE;")
            outputs = [fa.result(timeout=10), fb.result(timeout=10)]
            verify("R1/live: escalamiento SHARE a UPDATE puede hacer deadlock", sum("40P01" in x for x in outputs) == 1, outputs)
            a.run("ROLLBACK;")
            b.run("ROLLBACK;")

            a.run("BEGIN; SELECT id FROM audit_task WHERE id=1 FOR UPDATE;")
            b.run("BEGIN; SELECT id FROM audit_lead WHERE id=1 FOR UPDATE;")
            fa = pool.submit(a.run, "SELECT id FROM audit_lead WHERE id=1 FOR UPDATE;")
            fb = pool.submit(b.run, "SELECT id FROM audit_task WHERE id=1 FOR UPDATE;")
            outputs = [fa.result(timeout=10), fb.result(timeout=10)]
            verify("R1/live: tarea-lead contra lead-tarea puede hacer deadlock", sum("40P01" in x for x in outputs) == 1, outputs)
            a.run("ROLLBACK;")
            b.run("ROLLBACK;")

            def wait_blocked():
                until = time.monotonic() + 2
                while time.monotonic() < until:
                    if monitor.run("SELECT count(*) FROM pg_stat_activity WHERE application_name='sla_r2_b' AND wait_event_type='Lock';").strip() == "1":
                        return True
                    time.sleep(.02)
                return False

            a.run("BEGIN; SELECT id FROM audit_lead WHERE id=1 FOR UPDATE;")
            fb = pool.submit(b.run, "BEGIN; SELECT id FROM audit_lead WHERE id=1 FOR UPDATE; SELECT id FROM audit_task WHERE id=1 FOR UPDATE; COMMIT;")
            verify("R2: segundo escritor espera lead antes de tomar tarea", wait_blocked())
            out_a = a.run("SELECT id FROM audit_task WHERE id=1 FOR UPDATE; COMMIT;")
            out_b = fb.result(timeout=10)
            verify("R2: orden lead-tarea y lock fuerte desde inicio completa ambas", "ERROR" not in out_a + out_b)

            a.run("BEGIN; SELECT modo FROM audit_control WHERE id=1;")
            b.run("UPDATE audit_control SET modo='legado' WHERE id=1;")
            a.run("INSERT INTO audit_ajuste VALUES(1); COMMIT;")
            after = monitor.run("SELECT modo,(SELECT count(*) FROM audit_ajuste) FROM audit_control;").strip()
            verify("R1: lectura simple de modo permite ajuste despues de apagar", after == "legado|1", after)

            monitor.run("UPDATE audit_control SET modo='activo' WHERE id=1;")
            a.run("BEGIN; SELECT modo FROM audit_control WHERE id=1 FOR SHARE; INSERT INTO audit_ajuste VALUES(2);")
            fb = pool.submit(b.run, "UPDATE audit_control SET modo='legado' WHERE id=1;")
            verify("R2: cambio de modo espera escritor admitido", wait_blocked())
            a.run("COMMIT;")
            out_b = fb.result(timeout=10)
            after = monitor.run("SELECT modo,(SELECT count(*) FROM audit_ajuste) FROM audit_control;").strip()
            verify("R2: apagado confirma despues de terminar escritor anterior", "ERROR" not in out_b and after == "legado|2", after)
            a.run("BEGIN; SELECT modo FROM audit_control WHERE id=1 FOR SHARE; INSERT INTO audit_ajuste SELECT 3 WHERE (SELECT modo FROM audit_control WHERE id=1)='activo'; COMMIT;")
            verify("R2: evento posterior al apagado no concede ajuste", monitor.run("SELECT count(*) FROM audit_ajuste;").strip() == "2")
    finally:
        for session in (a, b, monitor):
            session.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket")
    parser.add_argument("--port", type=int, default=65461)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    models()
    if args.socket:
        sql_cases(args.socket, args.port)
    result = {"alcance": "Formulas parciales y patrones SQL sinteticos; no es prueba integral del CRM", "comprobaciones": len(checks), "aprobadas": sum(c["ok"] for c in checks), "casos": checks}
    Path(args.output).write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"comprobaciones": result["comprobaciones"], "aprobadas": result["aprobadas"], "output": args.output}))

#!/usr/bin/env python3
"""Tres conflictos reales + reintento, exclusivamente en el banco aislado sintético."""
import json
import subprocess
import time
import uuid

CONTENEDOR = "supabase_db_avancecorp-venta-cruzada"
BANCO = "reasignacion_conversion_v3_20260929"
PSQL = ["docker", "exec", "-i", CONTENEDOR, "psql", "-X", "-qAt", "-U", "postgres", "-d", BANCO, "-v", "ON_ERROR_STOP=1"]
LEAD = "c0000000-0000-4000-8000-000000000071"
ANALISTAS = ("c0000000-0000-4000-8000-000000000004", "c0000000-0000-4000-8000-000000000005")
SUPERVISOR = "c0000000-0000-4000-8000-000000000002"


def sql(query):
    result = subprocess.run(PSQL, input=query, text=True, capture_output=True, timeout=15)
    if result.returncode:
        raise RuntimeError(result.stderr)
    return result.stdout.strip()


assert sql("select count(*)<200 and exists(select 1 from public.perfiles where id='c0000000-0000-4000-8000-000000000001' and nombre_completo='VC GERENCIA') from crm.leads;") == "t"
persona = sql(f"select inversionista_id from crm.leads where id='{LEAD}';")
ANTERIOR = sql(f"select vendedor_id from crm.leads where id='{LEAD}';")
assert ANTERIOR in ANALISTAS
NUEVO = next(actor for actor in ANALISTAS if actor != ANTERIOR)
clave = str(uuid.uuid4())
solicitud = sql(f"select id from crm.inversion_solicitudes where lead_origen_id='{LEAD}' and estado='preparada';") or sql(f"""
begin;
set local request.jwt.claim.sub='{ANTERIOR}';
select crm.preparar_inversion_fn('{clave}',jsonb_build_object(
 'inversionista_id','{persona}','lead_id','{LEAD}','empresa','prodelco','monto',5000,'moneda','PEN',
 'fecha_comercial',(now() at time zone 'America/Lima')::date,
 'vence_en',((now() at time zone 'America/Lima')::date+interval '12 months')::date,
 'plazo_meses',12,'tasa_anual',18,'numero_transaccion','REASIGNACION-CONCURRENCIA',
 'referencia','PRUEBA SINTETICA','evidencia',jsonb_build_object('ruta','{persona}/{clave}/prueba.pdf')))->>'solicitud_id';
commit;
""")


def foto():
    return json.loads(sql(f"""select jsonb_build_object(
      'lead',(select to_jsonb(l) from crm.leads l where id='{LEAD}'),
      'persona',(select to_jsonb(i) from crm.inversionistas i where id='{persona}'),
      'solicitud',(select to_jsonb(s) from crm.inversion_solicitudes s where id='{solicitud}'),
      'tramos',(select jsonb_agg(to_jsonb(r) order by id) from crm.inversionista_responsables r where inversionista_id='{persona}'),
      'revisiones',(select count(*) from crm.inversion_solicitud_revisiones where solicitud_id='{solicitud}'),
      'actividades',(select count(*) from crm.actividades where lead_id='{LEAD}'));"""))


foto_antes = foto()
operacion = f"""\\set VERBOSITY verbose
begin;
set local statement_timeout='5s';
set local request.jwt.claim.sub='{SUPERVISOR}';
set local role authenticated;
update crm.leads set vendedor_id='{NUEVO}' where id='{LEAD}';
commit;
"""
for nombre, lock in [
    ("persona", f"select 1 from crm.inversionistas where id='{persona}' for update"),
    ("documento", "select private.identidad_bloquear_documento('DNI','70000027')"),
    ("solicitud", f"select 1 from crm.inversion_solicitudes where id='{solicitud}' for update"),
]:
    holder = subprocess.Popen(PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    holder.stdin.write(f"begin; set local statement_timeout='8s'; set local application_name='prueba_reasignacion_{nombre}'; {lock}; select pg_sleep(3); rollback;\n")
    holder.stdin.close()
    try:
        deadline = time.monotonic() + 3
        while sql(f"select exists(select 1 from pg_stat_activity where application_name='prueba_reasignacion_{nombre}' and wait_event='PgSleep');") != "t":
            if time.monotonic() > deadline:
                raise RuntimeError(f"No se adquirió el lock de {nombre}")
            time.sleep(0.05)
        start = time.monotonic()
        result = subprocess.run(PSQL, input=operacion, text=True, capture_output=True, timeout=7)
        assert result.returncode != 0 and "40001" in result.stderr, result.stderr
        assert time.monotonic() - start < 2, "La operación esperó con el lead bloqueado"
        assert foto() == foto_antes, "Quedaron efectos parciales"
        print(f"PASS: conflicto de {nombre} devuelve 40001 rápido y revierte todo", flush=True)
    finally:
        holder.wait(timeout=10)
        assert holder.returncode == 0, holder.stderr.read()

sql(operacion)
assert sql(f"select l.vendedor_id=i.responsable_relacion_id and i.responsable_relacion_id=s.responsable_esperado_id from crm.leads l join crm.inversionistas i on i.id=l.inversionista_id join crm.inversion_solicitudes s on s.lead_origen_id=l.id where l.id='{LEAD}' and s.id='{solicitud}';") == "t"
print("PASS: al liberar los locks, el mismo intento sincroniza las tres referencias", flush=True)
print("REASIGNACION_CONCURRENCIA_OK", flush=True)

"""Ensayo de dos sesiones PostgreSQL; requiere un clon local vacío ya migrado.

Uso: python3 concurrencia.py <contenedor Docker> <permisos_coordinacion_...>
Deja únicamente fixtures sintéticos en ese banco; nunca apunta a una URL remota.
"""
import subprocess
import sys
import time
from pathlib import Path

contenedor, banco = sys.argv[1:]
if not banco.startswith("permisos_coordinacion_"):
    raise SystemExit("Se requiere un banco de pruebas aislado")
comando = ["docker", "exec", "-i", contenedor, "psql", "-U", "postgres", "-d", banco,
           "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose"]


def consulta(sql):
    resultado = subprocess.run(comando, input=sql, text=True, capture_output=True, timeout=20)
    if resultado.returncode:
        raise RuntimeError(resultado.stderr)
    return resultado.stdout.strip()


def sesion(sql):
    proceso = subprocess.Popen(comando, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True)
    proceso.stdin.write(sql + "\n")
    proceso.stdin.flush()
    return proceso


def carrera(nombre, bloqueo, estado):
    bloqueador = sesion("begin; set local statement_timeout='15s';\n" + bloqueo +
                        "\nselect 'LISTO';")
    competidor = None
    try:
        while True:
            linea = bloqueador.stdout.readline().strip()
            if linea == "LISTO":
                break
            if bloqueador.poll() is not None:
                raise RuntimeError(bloqueador.stderr.read())
        competidor = sesion(f"""
          set application_name='{nombre}';
          begin; set local statement_timeout='15s';
          select set_config('request.jwt.claim.sub','cc150000-0000-4000-8000-000000000001',true);
          set local role authenticated;
          select crm.corregir_categoria_contrato_fn(
            'cc150000-0000-4000-8000-000000002010','renovacion','Corrección concurrente de prueba');
          commit;
        """)
        limite = time.monotonic() + 8
        while consulta(f"select exists(select 1 from pg_stat_activity where datname=current_database() "
                       f"and application_name='{nombre}' and wait_event_type='Lock');") != "t":
            if time.monotonic() > limite or competidor.poll() is not None:
                raise RuntimeError("La corrección no esperó el candado del ensayo")
            time.sleep(0.1)
        bloqueador.communicate("commit;\n", timeout=20)
        _, error = competidor.communicate(timeout=20)
        if competidor.returncode == 0 or estado not in error:
            raise AssertionError(f"Se esperaba {estado}: {error}")
        assert consulta("select count(*) from crm.correcciones_categoria_contrato;") == "0"
        assert consulta("select categoria from public.contratos where "
                        "id='cc150000-0000-4000-8000-000000002010';") == "nuevo"
        print(f"PASS: {nombre}: espera, rechaza {estado}, sin escritura ni auditoría parcial")
    finally:
        for proceso in (competidor, bloqueador):
            if proceso is not None and proceso.poll() is None:
                proceso.terminate()
                proceso.wait(timeout=5)


consulta("begin;\n" + Path(__file__).with_name("fixtures.sql").read_text() + "\ncommit;")
carrera("categoria_revocacion", "update crm.equipo set activo=false where "
        "perfil_id='cc150000-0000-4000-8000-000000000001';", "42501")
consulta("update crm.equipo set activo=true where perfil_id='cc150000-0000-4000-8000-000000000001';")
carrera("categoria_sello", """
  select pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'),(date '2026-10-01'-date '2000-01-01')::int);
  insert into crm.periodos_cerrados(periodo,ponderacion_referido,meta_revision,cobertura)
    values('2026-10-01',0.15,1,'{}');
""", "P0409")

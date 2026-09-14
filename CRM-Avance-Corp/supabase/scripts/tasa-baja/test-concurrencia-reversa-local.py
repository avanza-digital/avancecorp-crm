"""Reversa/reserva en dos sesiones reales de una copia local descartable.

Comprueba ambas órdenes y observa el bloqueo en pg_stat_activity antes de liberar
la primera transacción. No usa tiempos de sueño como prueba de concurrencia.
"""
from pathlib import Path
import re
import subprocess
import sys
import time

if len(sys.argv) != 2 or not re.fullmatch(r'crm_tasa_baja_[a-f0-9]{12}', sys.argv[1]):
    raise SystemExit('Usa únicamente la copia local aleatoria del runner de tasa-baja')

HERE = Path(__file__).resolve().parent
CMD = ['docker', 'exec', '-i', 'supabase_db_avancecorp-f4-bank', 'psql',
       '-X', '-U', 'supabase_admin', '-d', sys.argv[1], '-Atq', '-v', 'ON_ERROR_STOP=1']
ACTOR = """select set_config('request.jwt.claims',
 '{"sub":"f3000000-0000-0000-0000-000000000001","role":"authenticated"}',true);"""
INTENCION = """jsonb_build_object('categoria','nuevo','capital',20000,'moneda','PEN',
 'modalidad','mensual','tipo_interes','simple','fecha_inicio','2026-09-15',
 'fecha_vencimiento','2027-09-15','tasa_anual',12.5)"""
HUELLAS = """select string_agg(md5(prosrc),',' order by oid::regprocedure::text) from pg_proc
 where oid in ('private.resolver_tasa(uuid,text,uuid,timestamptz,uuid)'::regprocedure,
 'private.validar_tasa_conversion_lead(uuid,uuid,jsonb,boolean)'::regprocedure,
 'private.trg_contratos_observar_rentabilidad()'::regprocedure,
 'public.crear_contrato(jsonb,jsonb)'::regprocedure);"""
PROCESOS = []


def sql(texto):
    return subprocess.run(CMD, input=texto, text=True, capture_output=True, timeout=40, check=True).stdout


def iniciar(nombre, texto, cerrar=False):
    p = subprocess.Popen(CMD, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    PROCESOS.append(p)
    escribir(p, f"set application_name='{nombre}';\nset statement_timeout='15s';\n"+texto, cerrar)
    return p


def escribir(p, texto, cerrar=False):
    p.stdin.write(texto+'\n')
    p.stdin.flush()
    if cerrar:
        p.stdin.close()
        p.stdin = None


def esperar_marca(p, marca):
    while True:
        linea = p.stdout.readline()
        if not linea:
            raise AssertionError('La sesión terminó antes de '+marca+': '+p.stderr.read())
        if linea.strip() == marca:
            return


def esperar_bloqueo(p, nombre):
    limite = time.monotonic()+5
    while time.monotonic() < limite:
        assert p.poll() is None, 'La segunda sesión terminó sin esperar el candado: '+p.stderr.read()
        if sql(f"select count(*) from pg_stat_activity where datname=current_database() and application_name='{nombre}' and wait_event_type='Lock';").strip() == '1':
            return
        time.sleep(0.05)
    raise AssertionError('No se observó el bloqueo real de la segunda sesión')


def terminar(p, error=None):
    salida, stderr = p.communicate(timeout=40)
    if error:
        assert p.returncode != 0 and error in stderr, salida+stderr
    else:
        assert p.returncode == 0, salida+stderr


try:
    sql(f"""begin; {ACTOR}
update crm.multiempresa_flags set activo=false where nombre in ('resolver_en_puertas','inversiones_escritura');
insert into crm.leads(id,nombre_completo,telefono,dni,origen,monto_estimado,vendedor_id,creado_por)
select ('d7140000-0000-4000-8000-0000000000'||n)::uuid,'QA CARRERA REVERSA '||n,
 '+519990140'||n,'714090'||n,'otro',20000,
 'f3000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001'
from generate_series(50,51) n;
commit;""")
    reversa = (HERE/'revertir-antes-del-primer-uso.sql').read_text()
    candado = 'lock table public.contratos,crm.leads,crm.conversion_reservas,crm.ledger_rentabilidad in access exclusive mode;'
    assert reversa.count(candado) == 1
    prefijo, resto = reversa.split(candado)
    candidata = sql(HUELLAS)

    # Reversa primero: la reserva no puede validar con el cuerpo anterior al cambio.
    a = iniciar('qa_tasa_reversa_a', prefijo+candado+'\n\\echo REVERSA_CON_CANDADO')
    esperar_marca(a, 'REVERSA_CON_CANDADO')
    b = iniciar('qa_tasa_reversa_b', f"""begin; {ACTOR}
set local role authenticated;
do $$ begin
 begin
   perform crm.reservar_conversion_lead_tasa_fn('d7140000-0000-4000-8000-000000000050',{INTENCION});
   raise exception 'La reserva validó 12.5 después de restaurar el mínimo 15';
 exception when sqlstate 'P0410' then null; end;
end $$;
commit;""", cerrar=True)
    esperar_bloqueo(b, 'qa_tasa_reversa_b')
    escribir(a, resto, cerrar=True)
    terminar(a)
    terminar(b)
    assert sql("select count(*) from crm.conversion_reservas where lead_id='d7140000-0000-4000-8000-000000000050';").strip() == '0'
    assert sql(HUELLAS) != candidata, 'La reversa no se confirmó'
    sql((HERE.parent.parent/'migrations/20260914042114_crm_tasas_inferiores_nuevas_inversiones.sql').read_text())
    assert sql(HUELLAS) == candidata
    print('PASS: reversa primero; reserva rival espera y rechaza 12.5 con P0410, sin reserva parcial', flush=True)

    # Reserva primero: la reversa drena esa transacción y ve su compromiso al validar.
    a = iniciar('qa_tasa_reserva_a', f"""begin; {ACTOR}
set local role authenticated;
select crm.reservar_conversion_lead_tasa_fn('d7140000-0000-4000-8000-000000000051',{INTENCION}) is not null;
\\echo RESERVA_CON_CANDADO""")
    esperar_marca(a, 'RESERVA_CON_CANDADO')
    b = iniciar('qa_tasa_reserva_b', reversa, cerrar=True)
    esperar_bloqueo(b, 'qa_tasa_reserva_b')
    escribir(a, 'commit;', cerrar=True)
    terminar(a)
    terminar(b, 'Hay conversiones comprometidas con una tasa inferior')
    assert sql(HUELLAS) == candidata, 'La reversa bloqueada alteró alguna función'
    print('PASS: reserva primero; reversa rival espera y se rechaza por la reserva activa OFF, sin alterar funciones', flush=True)

    # Limpieza de este fixture exclusivamente, después de las aserciones; así la
    # prueba siguiente comprueba su reserva sellada y no queda tapada por esta.
    sql("""do $$ begin
 assert exists(select 1 from crm.conversion_reservas
   where lead_id='d7140000-0000-4000-8000-000000000051' and efectos_iniciados_en is null);
 delete from crm.conversion_reservas where lead_id='d7140000-0000-4000-8000-000000000051';
end $$;""")
finally:
    for p in PROCESOS:
        if p.poll() is None:
            p.kill()
            p.wait()

"""Dos sesiones reales: solicitar primero obliga a la conversión rival a esperar.

Solo una copia descartable del banco SQL, con actores F3 y migración aplicada.
Uso: python3 test-concurrencia-local.py tasa_lead_concurrencia_AAAAMMDD
No se conecta a Supabase remoto ni crea/elimina bases de datos.
"""
import re
import subprocess
import sys

if len(sys.argv) != 2 or not re.fullmatch(r'tasa_lead_concurrencia_\d{8}', sys.argv[1]):
    raise SystemExit('Usa únicamente una copia local tasa_lead_concurrencia_AAAAMMDD')

cmd = ['docker', 'exec', '-i', 'supabase_db_avancecorp-f4-bank', 'psql',
       '-X', '-U', 'supabase_admin', '-d', sys.argv[1], '-At', '-v', 'ON_ERROR_STOP=1']
actor = "select set_config('request.jwt.claims','{\"sub\":\"f3000000-0000-0000-0000-000000000001\",\"role\":\"authenticated\"}',true);"
lead = 'd7090000-0000-4000-8000-000000000010'
intencion = """jsonb_build_object('categoria','nuevo','capital',20000,'moneda','PEN',
 'modalidad','mensual','tipo_interes','simple','fecha_inicio','2026-09-15',
 'fecha_vencimiento','2027-09-15','tasa_anual',18)"""

def sql(texto):
    return subprocess.run(cmd, input=texto, text=True, capture_output=True, timeout=20, check=True)

sql(f"""begin; {actor}
update crm.multiempresa_flags set activo=false where nombre in ('resolver_en_puertas','inversiones_escritura');
insert into crm.leads(id,nombre_completo,telefono,dni,origen,monto_estimado,vendedor_id,creado_por)
values('{lead}','QA CARRERA TASA','+51999009010','70909010','otro',20000,
'f3000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001');
insert into crm.politica_rentabilidad(version,vigente_desde,tasa_base_nueva,tope_tecnico,vigencia_solicitud_dias,modo)
select coalesce(max(version),0)+1,clock_timestamp()-interval '1 hour',15,50,7,'enforcement' from crm.politica_rentabilidad;
commit;""")

a = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
try:
    a.stdin.write(f"""begin; {actor}
select crm.solicitar_tasa_fn({intencion}||jsonb_build_object('lead_id','{lead}',
'tasa_solicitada',18,'motivo','Prueba sintética de concurrencia')) is not null;
\echo SOLICITUD_CON_CANDADO
select pg_sleep(2);
commit;
""")
    a.stdin.close()
    a.stdin = None
    while True:
        linea = a.stdout.readline()
        if not linea:
            raise RuntimeError('La sesión de solicitud terminó antes de tomar el candado: '+a.stderr.read())
        if linea.strip() == 'SOLICITUD_CON_CANDADO':
            break
    assert a.poll() is None, 'No hubo sesiones concurrentes'
    b = sql(f"""begin; {actor}
do $$ begin
 begin
   perform crm.reservar_conversion_lead_tasa_fn('{lead}',{intencion}||'{{"tasa_anual":15}}'::jsonb);
   raise exception 'La conversión eludió la petición rival';
 exception when sqlstate 'P0411' then null; end;
 assert not exists(select 1 from crm.conversion_reservas where lead_id='{lead}');
 assert exists(select 1 from crm.solicitudes_tasa where lead_id='{lead}' and estado='pendiente');
end $$;
commit;""")
    _, error_a = a.communicate(timeout=10)
    assert a.returncode == 0, error_a
    print('PASS: dos sesiones reales, espera del candado y rechazo P0411 sin reserva parcial')
finally:
    if a.poll() is None:
        a.kill()
        a.wait()

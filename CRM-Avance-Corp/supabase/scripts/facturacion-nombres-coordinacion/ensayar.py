"""Matriz transaccional real: nombres autorizados, v1 compatible y escritura cerrada."""
from pathlib import Path
import subprocess
import sys

BASE = Path(__file__).resolve().parent
siembra = (BASE.parent / 'facturacion-lista/ensayo-sintetico.sql').read_text()
siembra = 'do $siembra$' + siembra.split('do $siembra$', 1)[1].split('end $siembra$;', 1)[0] + 'end $siembra$;'
coordinador = (BASE.parent / 'coordinacion-reportes/prueba.sql').read_text()
coordinador = coordinador.split('create temporary table resultados', 1)[0]
prueba = (BASE / 'prueba.sql').read_text()

sql = """\\set ON_ERROR_STOP on
begin;
set transaction isolation level read committed;
set local statement_timeout='180s';
set local jit=off;
set local max_parallel_workers_per_gather=0;
do $banco$ begin
  if current_database()<>'coordinacion_nombres_20261013'
     or (select shobj_description(oid,'pg_database') from pg_database where datname=current_database())
        is distinct from 'BANCO SINTETICO nombres Facturacion Coordinacion 20261013 / sin produccion'
     or current_user<>'postgres' or current_setting('session_replication_role')<>'origin'
     or exists(select 1 from crm.equipo) or exists(select 1 from public.contratos) then
    raise exception 'Solo banco sintético exclusivo, vacío y con triggers encendidos';
  end if;
end $banco$;
insert into crm.productos_inversion(codigo,es_legacy,permite_altas_legacy,estado,archivado_en)
values('HISTORICO-SIN-CATALOGO',true,true,'archivado',now());
insert into crm.sla_politicas(version,vigente_desde,zona_horaria,tipo_reloj,primera_gestion_minutos,primer_contacto_minutos)
values(1,'2000-01-01','America/Lima','corrido',60,120);
insert into crm.conversion_pesos(vigente_desde,peso_referido,peso_renovacion,nota)
values('2000-01-01',0.15,0.15,'Banco sintético nombres');
""" + siembra + '\n' + coordinador + '\n' + prueba

for tabla, columna in [('crm.equipo', 'perfil_id'), ('public.perfiles', 'id')]:
    def guardas(accion):
        return f"""do $fixture$ declare t record; begin
          for t in select tgname from pg_trigger where tgrelid='{tabla}'::regclass
            and not tgisinternal and (tgtype & 2)=2 loop
            execute format('alter table {tabla} {accion} trigger %I',t.tgname);
          end loop; end $fixture$;
"""
    sql += "reset role; select set_config('crm.op_privilegiada','on',true);\n"
    sql += guardas('disable')
    sql += f"update {tabla} set activo=false where {columna}=(select uid from pg_temp.f3b_actores where clase='coordinador');\n"
    sql += guardas('enable')
    sql += "select set_config('crm.op_privilegiada','',true); set local role authenticated;\n"
    sql += "select pg_temp.sesion((select uid from pg_temp.f3b_actores where clase='coordinador'));\nselect pg_temp.probar_baja();\nreset role;\n"
    sql += "select set_config('crm.op_privilegiada','on',true);\n" + guardas('disable')
    sql += f"update {tabla} set activo=true where {columna}=(select uid from pg_temp.f3b_actores where clase='coordinador');\n"
    sql += guardas('enable') + "select set_config('crm.op_privilegiada','',true);\n"

sql += """do $fin$ begin
  if exists(select 1 from pg_trigger where tgrelid in ('crm.equipo'::regclass,'public.perfiles'::regclass)
    and not tgisinternal and tgenabled='D') then raise exception 'Quedó un trigger desactivado'; end if;
  raise notice 'PASS: baja CRM y baja Portal cortan nombres con el mismo JWT; guards restaurados';
end $fin$;
rollback;
"""
if '--sql' in sys.argv:
    print(sql)
    raise SystemExit(0)
resultado = subprocess.run(['docker', 'exec', '-i', 'avancecorp-coordinacion-pg-actual', 'psql', '-X', '-U', 'postgres',
                            '-d', 'coordinacion_nombres_20261013', '-v', 'ON_ERROR_STOP=1', '-q'],
                           input=sql, text=True, capture_output=True)
if resultado.returncode == 0:
    print('\n'.join(l for l in resultado.stderr.splitlines() if 'PASS:' in l))
else:
    print(resultado.stdout[-1200:])
    print(resultado.stderr)
raise SystemExit(resultado.returncode)

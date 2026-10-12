"""Matriz real en banco sintético exclusivo; todos los datos se deshacen."""
from pathlib import Path
import json
import re
import subprocess
import sys

BASE = Path(__file__).resolve().parent
BANCO = 'coordinacion_reportes_20261012'
CONTENEDOR = 'avancecorp-coordinacion-pg-actual'
siembra = (BASE.parent / 'facturacion-lista/ensayo-sintetico.sql').read_text()
assert siembra.count('do $siembra$') == 1
siembra = 'do $siembra$' + siembra.split('do $siembra$', 1)[1].split('end $siembra$;', 1)[0] + 'end $siembra$;'
originales = json.loads((BASE / 'vivo/catalogo.json').read_text())
migracion = (BASE.parents[1] / 'migrations/20261012165115_crm_coordinacion_reportes_lectura.sql').read_text()
# Los CREATE OR REPLACE publicados se extraen sin ejecutar BEGIN/COMMIT del instalador.
inicio = migracion.index('CREATE OR REPLACE FUNCTION')
fin = migracion.index('do $guardia$', inicio)
nuevos = migracion[inicio:fin]
prueba = (BASE / 'prueba.sql').read_text()
assert prueba.count('-- CUERPOS ANTERIORES') == prueba.count('-- CUERPOS NUEVOS') == 1
prueba = prueba.replace('-- CUERPOS ANTERIORES', '\n'.join(t + ';' for t in originales.values()))
prueba = prueba.replace('-- CUERPOS NUEVOS', nuevos)
consultas_texto = prueba.split('for r in select * from (values', 1)[1].split(') llamadas(nombre,consulta)', 1)[0]
consultas = [(n, c.replace("''", "'")) for n, c in re.findall(r"\('([^']+)','((?:''|[^'])+)'\)", consultas_texto)]
assert len(consultas) == 8


def capturar(fase, clases):
    partes = ['set local role authenticated;']
    for clase in clases:
        for desplazamiento in (0, 1, 2):
            mes = f"(date_trunc('month',now() at time zone 'America/Lima')-interval '{desplazamiento} months')::date"
            partes += [f"select pg_temp.sesion((select uid from pg_temp.f3b_actores where clase='{clase}'));",
                       f"insert into pg_temp.resultados values('{clase}',{mes},'{fase}','{{}}');"]
            for nombre, consulta in consultas:
                literal = consulta.replace("'", "''")
                partes.append(f"update pg_temp.resultados set cifras=cifras||jsonb_build_object('{nombre}',"
                              f"pg_temp.lectura('{literal}',{mes})) where clase='{clase}' and periodo={mes} and fase='{fase}';")
    return '\n'.join(partes) + '\nreset role;\n'


clases = ['gerencia','directorio','sup1','sup2','vendedor']
prueba = prueba.replace('-- SNAPSHOTS ANTES', capturar('antes', clases))
prueba = prueba.replace('-- SNAPSHOTS DESPUES', capturar('despues', clases + ['coordinador']))
bajas = ['reset role;', 'discard plans;']
for tabla, id_columna in [('crm.equipo','perfil_id'),('public.perfiles','id')]:
    # Fabricar estados revocados: no se ensaya aquí el comando de offboarding.
    # Sus BEFORE guards pueden reparar un cambio directo. Se restauran antes de leer.
    def estado_guardas(estado):
        return f"""do $fixture$ declare t record; begin
          for t in select tgname from pg_trigger where tgrelid='{tabla}'::regclass
            and not tgisinternal and (tgtype & 2)=2 loop
            execute format('alter table {tabla} {estado} trigger %I',t.tgname);
          end loop; end $fixture$;"""
    bajas += ["select set_config('crm.op_privilegiada','on',true);", estado_guardas('disable'),
              f"update {tabla} set activo=false where {id_columna}=(select uid from pg_temp.f3b_actores where clase='coordinador') returning activo,current_user;",
              estado_guardas('enable'),
              "select set_config('crm.op_privilegiada','',true);",
              "set local role authenticated;",
              "select pg_temp.sesion((select uid from pg_temp.f3b_actores where clase='coordinador'));",
              "reset role;",
              "select jsonb_build_object('crm_activo',e.activo,'portal_activo',p.activo,'rol_efectivo',private.rol_crm(e.perfil_id),'actor_correcto',auth.uid()=e.perfil_id,'lector_global',private.es_lector_global(),'coordinador_reportes',private.es_coordinador_reportes()) as baja from crm.equipo e join public.perfiles p on p.id=e.perfil_id where e.perfil_id=(select uid from pg_temp.f3b_actores where clase='coordinador');",
              "set local role authenticated;",
              "select pg_temp.probar_baja();", "reset role;",
              "select set_config('crm.op_privilegiada','on',true);", estado_guardas('disable'),
              f"update {tabla} set activo=true where {id_columna}=(select uid from pg_temp.f3b_actores where clase='coordinador');",
              estado_guardas('enable'),
              "select set_config('crm.op_privilegiada','',true);"]
prueba = prueba.replace('-- BAJAS EN SENTENCIAS INDEPENDIENTES', '\n'.join(bajas))
sql = """\\set ON_ERROR_STOP on
begin;
set transaction isolation level read committed;
set local statement_timeout = '180s';
set local jit = off;
set local max_parallel_workers_per_gather = 0;
do $banco$ begin
  if current_database() <> 'coordinacion_reportes_20261012'
     or (select shobj_description(oid, 'pg_database') from pg_database where datname=current_database())
        is distinct from 'BANCO SINTETICO Coordinacion reportes 20261012 / sin produccion'
     or current_user <> 'postgres' or current_setting('session_replication_role') <> 'origin'
     or exists(select 1 from crm.equipo) or exists(select 1 from public.contratos) then
    raise exception 'Solo banco exclusivo VACIO con triggers encendidos';
  end if;
end $banco$;
insert into crm.productos_inversion(codigo,es_legacy,permite_altas_legacy,estado,archivado_en)
values('HISTORICO-SIN-CATALOGO',true,true,'archivado',now());
insert into crm.sla_politicas(version,vigente_desde,zona_horaria,tipo_reloj,primera_gestion_minutos,primer_contacto_minutos)
values(1,'2000-01-01','America/Lima','corrido',60,120);
insert into crm.conversion_pesos(vigente_desde,peso_referido,peso_renovacion,nota)
values('2000-01-01',0.15,0.15,'Banco sintético Coordinación');
""" + siembra + '\n' + prueba + '\nrollback;\n'
if '--sql' in sys.argv:
    print(sql)
    raise SystemExit(0)
resultado = subprocess.run(['docker', 'exec', '-i', CONTENEDOR, 'psql', '-X', '-U', 'postgres',
                            '-d', BANCO, '-v', 'ON_ERROR_STOP=1', '-q'],
                           input=sql, text=True, capture_output=True)
if resultado.returncode == 0:
    print('\n'.join(l for l in resultado.stderr.splitlines() if 'PASS:' in l))
else:
    print(resultado.stdout[-2200:], end='')
    print(resultado.stderr, end='')
raise SystemExit(resultado.returncode)

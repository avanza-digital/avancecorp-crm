"""Ejecuta el cierre mensual REAL con correcciones y eventos comerciales sintéticos.
Usa septiembre (mes terminado) desplazando exclusivamente las fechas del fixture.
Todos los datos y el sello se revierten. No modifica el reloj ni la función de cierre.
"""
import subprocess
import sys
from pathlib import Path

contenedor, banco = sys.argv[1:]
if not banco.startswith("permisos_coordinacion_"):
    raise SystemExit("Solo admite el banco aislado de permisos")
fixture = Path(__file__).with_name("fixtures.sql").read_text()
fixture = fixture.replace("2026-09", "2026-08").replace("2026-10", "2026-09")
sql = "begin; set local statement_timeout='90s';\n" + fixture + """
select pg_temp.sesion(2);
set local role authenticated;
select crm.corregir_categoria_contrato_fn(pg_temp.uid(2010),'renovacion','Corrección sintética antes del sello');
select crm.corregir_categoria_contrato_fn(pg_temp.uid(2011),'nuevo','Corrección sintética antes del sello');
select crm.corregir_categoria_contrato_fn(pg_temp.uid(2012),'upgrade','Corrección sintética antes del sello');
select crm.corregir_categoria_contrato_fn(pg_temp.uid(2013),'upgrade','Corrección sintética antes del sello');
select crm.corregir_categoria_contrato_fn(pg_temp.uid(2014),'renovacion','Corrección sintética antes del sello');
select crm.corregir_categoria_contrato_fn(pg_temp.uid(2015),'nuevo','Corrección sintética antes del sello');
reset role;
create temporary table conversion_viva as select * from private.conversion_mensual_por_vendedor(
  '2026-09-01 00:00:00-05','2026-10-01 00:00:00-05',true,'{}',0.15);
create temporary table cartera_viva as select * from private.metricas_cartera_por_vendedor('2026-09-01');
set local role authenticated;
select crm.cerrar_periodo('2026-09-01');
reset role;
do $$ begin
  if not exists(select 1 from crm.cierre_mes_vendedor c join conversion_viva v on v.analista_id=c.vendedor_id
    join cartera_viva k on k.vendedor_id=c.vendedor_id
    where c.periodo='2026-09-01' and c.vendedor_id=pg_temp.uid(4)
      and c.numerador=v.numerador and c.divisor=v.divisor
      and (c.cartera->>'operaciones_renovacion')::int=k.operaciones_renovacion
      and (c.cartera->>'operaciones_upgrade')::int=k.operaciones_upgrade
      and (select sum((d->>'capital_real')::numeric) from jsonb_array_elements(c.detalles) d)=22000) then
    raise exception 'El sello no coincide con conversión, operaciones o capital vivos';
  end if;
  if (select count(*) from private.operaciones_cartera_clasificadas() where fuente='correccion_categoria')<>2 then
    raise exception 'El ensayo no cubrió las dos operaciones comerciales sin operación financiera';
  end if;
end; $$;
set constraints all immediate;
select 'PASS: cierre mensual real conserva conversión, operaciones y capital tras las seis transiciones';
rollback;
"""
r = subprocess.run(["docker", "exec", "-i", contenedor, "psql", "-U", "postgres", "-d", banco,
                    "-X", "-qAt", "-v", "ON_ERROR_STOP=1"], input=sql,
                   text=True, capture_output=True, timeout=120)
if r.returncode:
    raise SystemExit(r.stderr)
print("\n".join(linea for linea in r.stdout.splitlines() if linea.startswith("PASS:")))

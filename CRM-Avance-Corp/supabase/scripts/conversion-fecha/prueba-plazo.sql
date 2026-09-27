-- Banco sintético: todos los cambios de esta prueba terminan en ROLLBACK.
begin;
set local statement_timeout = '20s';
set local lock_timeout = '3s';
-- @MIGRACION@

create function pg_temp.exigir(p_ok boolean, p_motivo text)
returns void language plpgsql as $$
begin
  if p_ok is distinct from true then raise exception 'FAIL: %',p_motivo; end if;
end $$;

select pg_temp.exigir(private.conversion_plazo_hasta('2026-09-01') =
  '2026-10-11 05:00:00+00'::timestamptz, 'dia 10 completo Lima');
select pg_temp.exigir(private.conversion_plazo_hasta('2026-12-01') =
  '2027-01-11 05:00:00+00'::timestamptz, 'cruce de anio');
select pg_temp.exigir(private.conversion_plazo_hasta('2028-02-01') =
  '2028-03-11 05:00:00+00'::timestamptz, 'febrero bisiesto');
select pg_temp.exigir(private.cierre_mes_ventana_desde('2026-09-01') =
  private.conversion_plazo_hasta('2026-09-01'), 'sello comparte corte');

create temp table casos (
  caso text primary key, comercial date, confirmacion timestamptz,
  vinculo timestamptz, sello timestamptz, esperado text
);
insert into casos values
('normal','2026-09-17','2026-09-21 13:15-05','2026-09-26 22:00-05',null,'acreditada'),
('antes del 10','2026-09-30','2026-10-09 23:59-05','2026-10-09 23:59-05',null,'acreditada'),
('inicio del 10','2026-09-30','2026-10-10 00:00-05','2026-10-10 00:00-05',null,'acreditada'),
('ultimo microsegundo','2026-09-30','2026-10-10 23:59:59.999999-05','2026-10-10 23:59:59.999999-05',null,'acreditada'),
('corte exacto','2026-09-30','2026-10-11 00:00-05','2026-10-11 00:00-05',null,'fuera_de_plazo'),
('confirmacion tardia','2026-09-30','2026-10-11 00:00-05','2026-10-09 12:00-05',null,'fuera_de_plazo'),
('vinculo tardio','2026-09-30','2026-09-30 12:00-05','2026-10-11 00:00-05',null,'fuera_de_plazo'),
('enero cargado septiembre','2026-01-26','2026-09-26 12:00-05','2026-09-26 12:00-05',null,'fuera_de_plazo'),
('fuente antigua de mayo','2026-05-21','2026-09-21 13:14-05','2026-09-26 22:00-05',null,'fuera_de_plazo'),
('fuente elegida de septiembre','2026-09-17','2026-09-21 13:15-05','2026-09-26 22:00-05',null,'acreditada'),
('pendiente no reserva','2026-09-30',null,'2026-10-09 12:00-05',null,'pendiente_confirmacion'),
('sin vinculo','2026-09-30','2026-10-09 12:00-05',null,null,'pendiente_vinculo'),
('sin fuente',null,null,null,null,'pendiente_fuente'),
('fuente sin confirmar ni vincular','2026-09-30',null,null,null,'pendiente_confirmacion'),
('antes del sello','2026-09-30','2026-10-09 12:00-05','2026-10-09 12:00-05','2026-10-11 10:00-05','acreditada'),
('sello ya existente','2026-09-30','2026-10-09 12:00-05','2026-10-09 12:00-05','2026-10-09 11:00-05','mes_sellado'),
('sello en mismo instante','2026-09-30','2026-10-09 12:00-05','2026-10-09 12:00-05','2026-10-09 12:00-05','mes_sellado'),
('futuro','2026-10-01','2026-09-26 12:00-05','2026-09-26 12:00-05',null,'fecha_futura');

select pg_temp.exigir(d.estado = c.esperado, c.caso)
from casos c cross join lateral private.conversion_decidir_plazo(
  c.comercial,c.confirmacion,c.vinculo,c.sello) d;

select pg_temp.exigir(d.acreditado_en = '2026-09-26 22:00-05'::timestamptz,
  'usa el ultimo hecho requerido, no el primero')
from private.conversion_decidir_plazo('2026-09-17','2026-09-21 13:15-05',
  '2026-09-26 22:00-05',null) d;
select pg_temp.exigir(d.acreditado_en is null, 'NULL no confirma por greatest')
from private.conversion_decidir_plazo('2026-09-17',null,'2026-09-26 22:00-05',null) d;

-- Reloj estable: el helper es puro y no consulta el instante de lectura.
select pg_temp.exigir(p.provolatile='i' and not p.prosecdef,
  'decision inmutable y sin privilegios elevados')
from pg_proc p where p.oid='private.conversion_decidir_plazo(date,timestamptz,timestamptz,timestamptz)'::regprocedure;
set local timezone='Pacific/Auckland';
select pg_temp.exigir(private.conversion_plazo_hasta('2026-09-01') =
  '2026-10-11 05:00+00'::timestamptz, 'timezone de sesion no cambia corte');
select pg_temp.exigir(d.estado='acreditada','timezone de sesion no cambia decision')
from private.conversion_decidir_plazo('2026-09-30','2026-10-10 23:59:59.999999-05',
 '2026-10-10 23:59:59.999999-05',null) d;

do $$
begin
  begin
    perform private.conversion_plazo_hasta('2026-09-02');
    raise exception 'FAIL: periodo invalido aceptado';
  exception when invalid_parameter_value then null; end;
  begin
    perform private.conversion_decidir_plazo('2026-09-01','infinity',now(),null);
    raise exception 'FAIL: timestamp infinito aceptado';
  exception when invalid_parameter_value then null; end;
end $$;

select pg_temp.exigir(not has_function_privilege(r.rol,
 'private.conversion_decidir_plazo(date,timestamptz,timestamptz,timestamptz)','EXECUTE'),
 'decision privada no invocable por '||r.rol)
from (values('anon'),('authenticated')) r(rol);
select pg_temp.exigir(not has_function_privilege(r.rol,
 'private.conversion_plazo_hasta(date)','EXECUTE'), 'corte privado no invocable por '||r.rol)
from (values('anon'),('authenticated')) r(rol);

select 'PASS: calendario y decision temporal; integracion de escritores pendiente' as resultado;
rollback;

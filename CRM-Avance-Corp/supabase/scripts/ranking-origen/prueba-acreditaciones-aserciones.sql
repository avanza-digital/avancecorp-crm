create temp table despues as select * from private.ranking_capital_origen_filas('2026-09-01 00:00-05','2026-10-01 00:00-05',null);
do $prueba$
declare n integer; esperado text; actual text;
begin
  for n,esperado in select * from (values
    (1,'formulario'),(2,'referido'),(3,'sin_origen'),(4,'sin_origen'),
    (5,'sin_origen'),(6,'oficina'),(7,'sin_origen'),(8,'cartera'),(9,'cartera'),
    (10,'sin_origen'),(11,'sin_origen'),(12,'landing'),(13,'sin_origen')
  ) x(n,origen) loop
    select origen into actual from despues where operacion_id=private.test_id(n);
    if actual is distinct from esperado then raise exception 'Caso %: esperado %, recibido %',n,esperado,actual; end if;
  end loop;
  if exists(
    (select vendedor_id,moneda,capital,categoria,operacion_id from antes
     except all select vendedor_id,moneda,capital,categoria,operacion_id from despues)
    union all
    (select vendedor_id,moneda,capital,categoria,operacion_id from despues
     except all select vendedor_id,moneda,capital,categoria,operacion_id from antes)
  ) then raise exception 'Cambió un importe, categoría, atribución o cantidad de filas'; end if;
  if (select count(*) from antes a join despues d using(operacion_id) where a.origen<>d.origen) <> 2 then
    raise exception 'El cambio debe afectar solo dos canales';
  end if;
  if has_function_privilege('anon','private.ranking_origenes_acreditados_filas(uuid[])','execute')
    or has_function_privilege('authenticated','private.ranking_origenes_acreditados_filas(uuid[])','execute')
    or has_function_privilege('service_role','private.ranking_origenes_acreditados_filas(uuid[])','execute') then
    raise exception 'El helper quedó accesible a clientes';
  end if;
  raise notice 'PASS: 13 casos, paridad monetaria exacta y permisos del helper';
end;
$prueba$;
update crm.conversion_politica set activada_en=null;
do $politica$
begin
  if exists(select 1 from private.ranking_origenes_acreditados_filas(array[private.test_id(1)])) then
    raise exception 'Se utilizó una acreditación con la política inactiva';
  end if;
  raise notice 'PASS: política inactiva no atribuye nuevos canales';
end;
$politica$;
rollback;

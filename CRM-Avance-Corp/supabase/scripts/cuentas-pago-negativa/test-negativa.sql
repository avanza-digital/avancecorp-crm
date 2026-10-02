-- PRUEBA de la negativa de modo de transacción en «Retirar cuenta» y «Cambiar cuenta de pago» — SOLO BANCO.
-- No siembra nada: llama a los dos núcleos y a las dos puertas con identificadores al azar y sin actor.
--   · En REPEATABLE READ y en SERIALIZABLE deben negarse con 0A000 ANTES de mirar nada.
--   · En READ COMMITTED deben pasar la negativa y caer en la comprobación siguiente (42501: sin actor no hay
--     administración vigente): prueba que la negativa va primera y que no rompe el camino normal.
-- Nada queda escrito salvo la tabla temporal de resultados. Uso: psql "$DB_URL" -v ON_ERROR_STOP=1 -f test-negativa.sql
\set ON_ERROR_STOP 1
\set QUIET 1
-- Los núcleos fallan antes de escribir (0A000 o 42501), cada llamada va en su propio bloque EXCEPTION
-- (savepoint implícito) y la transacción se CONFIRMA para que queden solo los resultados.
create temporary table _veredicto (n int generated always as identity, caso text, esperado text, obtenido text, ok boolean);

\echo [negativa] REPEATABLE READ
begin isolation level repeatable read;
do $t$
declare v_caso text; v_sql text; v_est text;
begin
  for v_caso, v_sql in values
    ('nucleo retirar · RR', 'select private.retirar_cuenta_cliente_autorizado(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), ''motivo de prueba'', null)'),
    ('nucleo cambiar · RR', 'select private.cambiar_cuenta_pago_contratos_autorizado(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), array[gen_random_uuid()], ''motivo de prueba'', ''ruta/x.pdf'')'),
    ('puerta retirar · RR', 'select crm.retirar_cuenta_cliente(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), ''motivo de prueba'', null)'),
    ('puerta cambiar · RR', 'select crm.cambiar_cuenta_pago_contratos(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), array[gen_random_uuid()], ''motivo de prueba'', ''ruta/x.pdf'')')
  loop
    begin
      execute v_sql; v_est := 'SIN ERROR';
    exception when others then v_est := sqlstate;
    end;
    insert into _veredicto(caso, esperado, obtenido, ok) values (v_caso, '0A000', v_est, v_est = '0A000');
  end loop;
end $t$;
commit;

\echo [negativa] SERIALIZABLE
begin isolation level serializable;
do $t$
declare v_est text;
begin
  begin
    perform private.retirar_cuenta_cliente_autorizado(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'motivo de prueba', null); v_est := 'SIN ERROR';
  exception when others then v_est := sqlstate; end;
  insert into _veredicto(caso, esperado, obtenido, ok) values ('nucleo retirar · SERIALIZABLE', '0A000', v_est, v_est = '0A000');
  begin
    perform private.cambiar_cuenta_pago_contratos_autorizado(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), array[gen_random_uuid()], 'motivo de prueba', 'ruta/x.pdf'); v_est := 'SIN ERROR';
  exception when others then v_est := sqlstate; end;
  insert into _veredicto(caso, esperado, obtenido, ok) values ('nucleo cambiar · SERIALIZABLE', '0A000', v_est, v_est = '0A000');
  begin
    perform crm.retirar_cuenta_cliente(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'motivo de prueba', null); v_est := 'SIN ERROR';
  exception when others then v_est := sqlstate; end;
  insert into _veredicto(caso, esperado, obtenido, ok) values ('puerta retirar · SERIALIZABLE', '0A000', v_est, v_est = '0A000');
  begin
    perform crm.cambiar_cuenta_pago_contratos(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), array[gen_random_uuid()], 'motivo de prueba', 'ruta/x.pdf'); v_est := 'SIN ERROR';
  exception when others then v_est := sqlstate; end;
  insert into _veredicto(caso, esperado, obtenido, ok) values ('puerta cambiar · SERIALIZABLE', '0A000', v_est, v_est = '0A000');
end $t$;
commit;

\echo [negativa] READ UNCOMMITTED: Postgres lo ejecuta como READ COMMITTED, pero el ajuste no dice 'read committed' y la negativa salta (igual que en «Asignar»)
begin isolation level read uncommitted;
do $t$
declare v_est text;
begin
  begin
    perform private.retirar_cuenta_cliente_autorizado(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'motivo de prueba', null); v_est := 'SIN ERROR';
  exception when others then v_est := sqlstate; end;
  insert into _veredicto(caso, esperado, obtenido, ok) values ('nucleo retirar · READ UNCOMMITTED', '0A000', v_est, v_est = '0A000');
  begin
    perform private.cambiar_cuenta_pago_contratos_autorizado(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), array[gen_random_uuid()], 'motivo de prueba', 'ruta/x.pdf'); v_est := 'SIN ERROR';
  exception when others then v_est := sqlstate; end;
  insert into _veredicto(caso, esperado, obtenido, ok) values ('nucleo cambiar · READ UNCOMMITTED', '0A000', v_est, v_est = '0A000');
end $t$;
commit;

\echo [negativa] READ COMMITTED (explícito): la negativa deja pasar y cae en la comprobación de administración (42501)
begin isolation level read committed;
do $t$
declare v_est text;
begin
  begin
    perform private.retirar_cuenta_cliente_autorizado(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'motivo de prueba', null); v_est := 'SIN ERROR';
  exception when others then v_est := sqlstate; end;
  insert into _veredicto(caso, esperado, obtenido, ok) values ('nucleo retirar · READ COMMITTED sin actor', '42501', v_est, v_est = '42501');
  begin
    perform private.cambiar_cuenta_pago_contratos_autorizado(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), array[gen_random_uuid()], 'motivo de prueba', 'ruta/x.pdf'); v_est := 'SIN ERROR';
  exception when others then v_est := sqlstate; end;
  insert into _veredicto(caso, esperado, obtenido, ok) values ('nucleo cambiar · READ COMMITTED sin actor', '42501', v_est, v_est = '42501');
  begin
    perform crm.retirar_cuenta_cliente(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'motivo de prueba', null); v_est := 'SIN ERROR';
  exception when others then v_est := sqlstate; end;
  insert into _veredicto(caso, esperado, obtenido, ok) values ('puerta retirar · READ COMMITTED sin actor', '42501', v_est, v_est = '42501');
  begin
    perform crm.cambiar_cuenta_pago_contratos(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), array[gen_random_uuid()], 'motivo de prueba', 'ruta/x.pdf'); v_est := 'SIN ERROR';
  exception when others then v_est := sqlstate; end;
  insert into _veredicto(caso, esperado, obtenido, ok) values ('puerta cambiar · READ COMMITTED sin actor', '42501', v_est, v_est = '42501');
end $t$;
commit;

\set QUIET 0
select caso, esperado, obtenido, case when ok then '✓' else '✗' end as res from _veredicto order by n;
select (count(*) filter (where not ok)) > 0 as hay_fallos, count(*) filter (where not ok) as fallos, count(*) as casos from _veredicto \gset
\if :hay_fallos
  \echo [negativa] FALLOS: :fallos de :casos
  do $f$ begin raise exception 'NEGATIVA: hay casos sin la respuesta esperada'; end $f$;
\else
  \echo [negativa] PASS: :casos casos
\endif
drop table _veredicto;

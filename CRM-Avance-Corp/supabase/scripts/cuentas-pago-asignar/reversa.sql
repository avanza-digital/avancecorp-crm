-- REVERSA de 20261002005004_crm_asignar_cuenta_pago.
--   · Si NO hay ninguna asignación registrada y las piezas son las de la migración: deja todo
--     como antes (quita la puerta, el núcleo, el candado y la tabla de constancias, que está
--     vacía) y borra su fila de supabase_migrations.schema_migrations, para que el registro no
--     diga que está aplicada.
--   · En cualquier otro caso NO borra nada: solo CIERRA la puerta (retira el permiso de
--     ejecutar), para que nadie asigne más. Las constancias y los vínculos que crearon son
--     instrucciones de pago en uso, y la versión sigue registrada (sus piezas siguen ahí).
--     Cerrar es siempre seguro, por eso no exige que las piezas sigan siendo las de la
--     migración. Para reabrir: reabrir-puerta.sql.
-- No toca ningún vínculo en ningún caso.
-- Límite conocido: una asignación que ya había empezado cuando se lanza la reversa espera a que
-- esta termine y luego se completa (el permiso se comprueba al entrar). Si el veredicto dice
-- PUERTA_CERRADA, vuelve a contar las asignaciones un minuto después.
-- Solo Miguel, con autorización expresa. Nunca la ejecuta un revisor.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $reversa$
declare
  v_asignaciones bigint;
  v_intactas boolean;
begin
  -- Se cuenta DESPUÉS de tomar el candado de la tabla: eso solo vale en READ COMMITTED (con una
  -- fotografía anterior al candado se podría borrar una tabla que ya tiene una asignación).
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'REVERSA ASIGNAR: la transacción debe ir en READ COMMITTED (va en %)',
      pg_catalog.current_setting('transaction_isolation');
  end if;
  if pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') is null
     or pg_catalog.to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)') is null
     or pg_catalog.to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)') is null
     or pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_asignaciones_inmutable()') is null then
    raise exception 'REVERSA ASIGNAR: la migración 20261002005004 no está aplicada; no hay nada que revertir';
  end if;

  -- Nadie asigna mientras se decide: la asignación escribe en esta tabla.
  lock table crm.contrato_cuenta_pago_asignaciones in access exclusive mode;
  select pg_catalog.count(*) into v_asignaciones from crm.contrato_cuenta_pago_asignaciones;

  v_intactas :=
    (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
     where p.oid = 'private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'::regprocedure)
      = '57297bc7f18279578c2f16f6aaad7247'
    and (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
         where p.oid = 'crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'::regprocedure)
      = '46e03517fc68ffd79fed6892d1128c2b'
    and (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
         where p.oid = 'private.trg_contrato_cuenta_pago_asignaciones_inmutable()'::regprocedure)
      = '49bb93b9429aa7b0c168cc8ceb43acfc';

  if v_asignaciones = 0 and v_intactas then
    execute 'drop function crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)';
    execute 'drop function private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)';
    execute 'drop table crm.contrato_cuenta_pago_asignaciones';
    execute 'drop function private.trg_contrato_cuenta_pago_asignaciones_inmutable()';
    if pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') is not null
       or pg_catalog.to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)') is not null
       or pg_catalog.to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)') is not null
       or pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_asignaciones_inmutable()') is not null then
      raise exception 'REVERSA ASIGNAR: quedó alguna pieza de la migración';
    end if;
    -- Ya no está aplicada: que el registro de versiones tampoco lo diga.
    if pg_catalog.to_regclass('supabase_migrations.schema_migrations') is not null then
      execute 'delete from supabase_migrations.schema_migrations where version = ''20261002005004''';
    end if;
    perform pg_catalog.set_config('crm.reversa_asignar_resultado',
      'RETIRADA: sin asignaciones registradas; se quitaron la puerta, el núcleo, el candado, la tabla y el registro de la versión', false);
  else
    execute 'revoke all on function crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text) from public, anon, authenticated, service_role';
    execute 'revoke all on function private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text) from public, anon, authenticated, service_role';
    if pg_catalog.has_function_privilege('authenticated', 'crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)', 'EXECUTE')
       or pg_catalog.has_function_privilege('authenticated', 'private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)', 'EXECUTE') then
      raise exception 'REVERSA ASIGNAR: la puerta no quedó cerrada';
    end if;
    perform pg_catalog.set_config('crm.reversa_asignar_resultado',
      pg_catalog.format('PUERTA_CERRADA: %s asignaciones conservadas; no se borró nada%s', v_asignaciones,
        case when v_intactas then '' else ' (las piezas cambiaron después de la migración)' end), false);
  end if;
end;
$reversa$;

notify pgrst, 'reload schema';
commit;

-- El veredicto viaja como fila. (Si este archivo se relanza en la MISMA sesión y se niega, esta
-- fila repetiría el veredicto anterior: se lanza con `db query --file`, una sesión por archivo.)
select pg_catalog.current_setting('crm.reversa_asignar_resultado', true) as resultado;

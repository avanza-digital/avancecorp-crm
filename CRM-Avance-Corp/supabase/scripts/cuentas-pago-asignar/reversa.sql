-- REVERSA de 20261002005004_crm_asignar_cuenta_pago.sql. GENERADA por generar-derivados.py (no se edita a mano).
--   · Si NO hay ninguna asignación registrada y las piezas están ENTERAS como las dejó la migración:
--     deja todo como antes (quita la puerta, el núcleo, el candado y la tabla de constancias, que
--     está vacía) y borra su fila de supabase_migrations.schema_migrations.
--   · En cualquier otro caso NO borra nada: solo CIERRA la puerta. Retira el permiso de ejecutar
--     de la puerta y del núcleo a TODO el que lo tenga (no solo a los roles conocidos) y comprueba
--     que no quede nadie salvo el dueño. Las constancias y los vínculos que crearon son
--     instrucciones de pago en uso, y la versión sigue registrada. Cerrar es siempre seguro: se
--     hace aunque falte una pieza o alguna haya cambiado. Para reabrir: reabrir-puerta.sql.
-- No toca ningún vínculo en ningún caso.
-- Límite conocido: una asignación que ya había empezado cuando se lanza la reversa espera a que
-- esta termine y luego se completa (el permiso se comprueba al entrar). Si el veredicto dice
-- PUERTA_CERRADA, vuelve a contar las asignaciones un minuto después.
-- El veredicto final se lee del ESTADO real de la base, no de esta sesión.
-- Solo Miguel, con autorización expresa. Nunca la ejecuta un revisor.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $reversa$
declare
  v_asignaciones bigint;
  v_intactas boolean;
  v_f record;
begin
  -- Se cuenta DESPUÉS de tomar el candado de la tabla: eso solo vale en READ COMMITTED (con una
  -- fotografía anterior al candado se podría borrar una tabla que ya tiene una asignación).
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'REVERSA ASIGNAR: la transacción debe ir en READ COMMITTED (va en %)',
      pg_catalog.current_setting('transaction_isolation');
  end if;
  if pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') is null
     and pg_catalog.to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)') is null
     and pg_catalog.to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)') is null
     and pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_asignaciones_inmutable()') is null then
    raise exception 'REVERSA ASIGNAR: la migración 20261002005004 no está aplicada; no hay nada que revertir';
  end if;

  -- Nadie asigna mientras se decide: la asignación escribe en esta tabla.
  if pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') is not null then
    execute 'lock table crm.contrato_cuenta_pago_asignaciones in access exclusive mode';
    execute 'select pg_catalog.count(*) from crm.contrato_cuenta_pago_asignaciones' into v_asignaciones;
  end if;

  v_intactas := coalesce((
    -- las tres funciones: cuerpo, DEFINER/INVOKER, search_path exacto y dueño
    (select pg_catalog.count(*)
     from (values
       ('private.trg_contrato_cuenta_pago_asignaciones_inmutable()', true, '49bb93b9429aa7b0c168cc8ceb43acfc'),
       ('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)', true, '3642871283e7306a179ea3795bad1389'),
       ('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)', false, '46e03517fc68ffd79fed6892d1128c2b')
     ) as f(firma, definer, huella)
     join pg_catalog.pg_proc p on p.oid = pg_catalog.to_regprocedure(f.firma)
     where pg_catalog.md5(p.prosrc) = f.huella
       and p.prosecdef = f.definer
       and p.proconfig = array['search_path=""']
       and pg_catalog.pg_get_userbyid(p.proowner) = current_user::text) = 3
    -- nadie de más las ejecuta: authenticated, solo en la puerta y el núcleo
    and not exists (
      select 1 from pg_catalog.pg_proc p
      where p.oid in (pg_catalog.to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'), pg_catalog.to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'),
                      pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_asignaciones_inmutable()'))
        and (p.proacl is null
             or exists (select 1 from pg_catalog.aclexplode(p.proacl) a
                        where a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner
                          and (a.grantee <> 'authenticated'::regrole::oid
                               or p.oid = pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_asignaciones_inmutable()')))))
    -- las piezas de F3 de las que depende: la compuerta de administración y los candados del vínculo
    and (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
         where p.oid = pg_catalog.to_regprocedure('private.admin_banca_vigente(uuid)')) = '810dce30e37d1da9d913ef48ab6a4aa1'
    and (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
         where p.oid = pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_coherente()')) = '7e946a5af78a827c18ee5b218896f24c'
    and (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
         where p.oid = pg_catalog.to_regprocedure('private.trg_registro_cuenta_pago_no_borrar()')) = 'e95919db53c44ff1fe6632c346f27a06'
    and (select pg_catalog.count(*) from pg_catalog.pg_trigger t
         where t.tgrelid = pg_catalog.to_regclass('crm.contrato_cuentas_pago') and t.tgenabled = 'O'
           and (t.tgname, t.tgfoid) in (
             ('trg_contrato_cuenta_pago_coherente', pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_coherente()')::oid),
             ('trg_audit_contrato_cuentas_pago', pg_catalog.to_regprocedure('private.log_audit_crm()')::oid),
             ('trg_contrato_cuenta_pago_00_inmutable', pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_inmutable()')::oid))) = 3
    -- la constancia: RLS, sin acceso de la API, sus tres candados con su forma, bitácora y reglas
    and coalesce((select t.relrowsecurity from pg_catalog.pg_class t
                  where t.oid = pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones')), false)
    and not exists (
      select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol)
      where pg_catalog.has_table_privilege(r.rol, pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones')::oid,
              'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'))
    and (select pg_catalog.count(*) from pg_catalog.pg_trigger t
         where t.tgrelid = pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones')
           and t.tgenabled = 'O' and t.tgqual is null and t.tgattr::text = ''
           -- tgtype: fila 1 · antes 2 · borrar 8 · modificar 16 · vaciar 32
           and (t.tgname, t.tgfoid, t.tgtype::integer) in (
             ('trg_contrato_cuenta_pago_asignaciones_00_no_borrar',
              pg_catalog.to_regprocedure('private.trg_registro_cuenta_pago_no_borrar()')::oid, 11),
             ('trg_contrato_cuenta_pago_asignaciones_00_inmutable',
              pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_asignaciones_inmutable()')::oid, 19),
             ('trg_contrato_cuenta_pago_asignaciones_00_sin_vaciar',
              pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_asignaciones_inmutable()')::oid, 34))) = 3
    and exists (
      select 1 from pg_catalog.pg_trigger t
      where t.tgrelid = pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones')
        and t.tgname = 'trg_audit_contrato_cuenta_pago_asignaciones'
        and t.tgfoid = pg_catalog.to_regprocedure('private.log_audit_crm()')::oid
        and t.tgenabled = 'O' and (t.tgtype & 1) = 1 and (t.tgtype & 2) = 0 and (t.tgtype & 28) = 28
        and t.tgqual is null and t.tgattr::text = '')
    and exists (
      select 1 from pg_catalog.pg_constraint c
      where c.conrelid = pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') and c.contype = 'u'
        and c.conname = 'contrato_cuenta_pago_asignaciones_solicitud_uq' and not c.condeferrable)
    and exists (
      select 1 from pg_catalog.pg_constraint c
      where c.conrelid = pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') and c.contype = 'c'
        and c.conname = 'contrato_cuenta_pago_asignaciones_motivo_valido' and c.convalidated)
  ), false);

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
      execute 'delete from supabase_migrations.schema_migrations where version = '
        || pg_catalog.quote_literal('20261002005004');
    end if;
  else
    -- Cerrar: a TODO el que tenga EXECUTE (salvo el dueño), en la puerta y en el núcleo que existan.
    for v_f in
      select p.oid::regprocedure::text as firma,
             case when a.grantee = 0 then 'public' else pg_catalog.quote_ident(r.rolname) end as quien
      from pg_catalog.pg_proc p
      cross join lateral pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
      left join pg_catalog.pg_roles r on r.oid = a.grantee
      where p.oid in (pg_catalog.to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'), pg_catalog.to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'))
        and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner
    loop
      execute pg_catalog.format('revoke all on function %s from %s', v_f.firma, v_f.quien);
    end loop;
    if exists (
      select 1 from pg_catalog.pg_proc p
      where p.oid in (pg_catalog.to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'), pg_catalog.to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'))
        and (p.proacl is null
             or exists (select 1 from pg_catalog.aclexplode(p.proacl) a
                        where a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner))) then
      raise exception 'REVERSA ASIGNAR: la puerta no quedó cerrada';
    end if;
  end if;
end;
$reversa$;

notify pgrst, 'reload schema';
commit;

-- El veredicto viaja como fila y sale del ESTADO real (si la reversa se negó, dice lo que hay).
select case
         when pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') is null
          and pg_catalog.to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)') is null
          and pg_catalog.to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)') is null
           then 'RETIRADA: no queda la puerta, el núcleo ni la tabla de constancias'
         when not exists (
      select 1 from pg_catalog.pg_proc p
      where p.oid in (pg_catalog.to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'), pg_catalog.to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'))
        and (p.proacl is null
             or exists (select 1 from pg_catalog.aclexplode(p.proacl) a
                        where a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner)))
           then 'PUERTA_CERRADA: nadie puede asignar; no se borró nada (las constancias y los vínculos siguen)'
         else 'SIN_CAMBIOS: la puerta sigue abierta'
       end as resultado;

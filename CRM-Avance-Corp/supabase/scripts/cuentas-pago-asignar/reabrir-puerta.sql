-- REABRIR la puerta de «Asignar cuenta de pago» después de haberla cerrado con reversa.sql.
-- GENERADO por generar-derivados.py (no se edita a mano).
-- Solo devuelve el permiso de ejecutar a authenticated en la puerta y en su núcleo (la compuerta
-- de administración sigue dentro del núcleo). Se niega si las piezas no están ENTERAS como las
-- dejó la migración 20261002005004: cuerpos, DEFINER/INVOKER, search_path, dueño, permisos, RLS,
-- candados, bitácora, reglas de la tabla y las piezas de F3 de las que depende (la compuerta de
-- administración y los candados del vínculo). No se reabre una puerta que alguien cambió sin revisarla.
-- El veredicto final se lee del ESTADO real de la base, no de esta sesión.
-- Solo Miguel, con autorización expresa.
begin;
set local lock_timeout = '5s';

do $reabrir$
begin
  if not coalesce((
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
    -- lo que el núcleo da por hecho del vínculo: UNO por contrato, con el nombre por el que lo reconoce
    and exists (
      select 1
      from pg_catalog.pg_constraint c
      join pg_catalog.pg_index i on i.indexrelid = c.conindid
      where c.conrelid = pg_catalog.to_regclass('crm.contrato_cuentas_pago') and c.contype = 'u'
        and c.conname = 'contrato_cuentas_pago_contrato_id_key' and not c.condeferrable
        and i.indisunique and i.indpred is null and i.indisvalid and i.indimmediate and i.indnatts = 1
        and i.indkey[0] = (select a.attnum from pg_catalog.pg_attribute a
                           where a.attrelid = pg_catalog.to_regclass('crm.contrato_cuentas_pago')
                             and a.attname = 'contrato_id'))
    -- la puerta y el núcleo escriben: las dos VOLATILE
    and (select pg_catalog.count(*) from pg_catalog.pg_proc p
         where p.oid in (pg_catalog.to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'), pg_catalog.to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'))
           and p.provolatile = 'v') = 2
    -- la constancia sigue sin claves foráneas, sin permisos por columna y sin disparadores de más
    and not exists (
      select 1 from pg_catalog.pg_constraint c
      where c.conrelid = pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') and c.contype = 'f')
    and not exists (
      select 1 from pg_catalog.pg_attribute a
      where a.attrelid = pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') and a.attnum > 0 and not a.attisdropped
        and a.attacl is not null)
    and not exists (
      select 1 from pg_catalog.pg_trigger t
      where t.tgrelid = pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') and not t.tgisinternal
        and t.tgname not in ('trg_contrato_cuenta_pago_asignaciones_00_no_borrar',
                             'trg_contrato_cuenta_pago_asignaciones_00_inmutable',
                             'trg_contrato_cuenta_pago_asignaciones_00_sin_vaciar',
                             'trg_audit_contrato_cuenta_pago_asignaciones'))
  ), false) then
    raise exception 'REABRIR ASIGNAR: las piezas no están enteras como las dejó la migración 20261002005004 (cuerpos, forma, permisos, candados, bitácora, reglas o las piezas de F3 de las que depende); no se reabre';
  end if;
  execute 'grant execute on function private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text) to authenticated';
  execute 'grant execute on function crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text) to authenticated';
  if not coalesce((
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
    -- lo que el núcleo da por hecho del vínculo: UNO por contrato, con el nombre por el que lo reconoce
    and exists (
      select 1
      from pg_catalog.pg_constraint c
      join pg_catalog.pg_index i on i.indexrelid = c.conindid
      where c.conrelid = pg_catalog.to_regclass('crm.contrato_cuentas_pago') and c.contype = 'u'
        and c.conname = 'contrato_cuentas_pago_contrato_id_key' and not c.condeferrable
        and i.indisunique and i.indpred is null and i.indisvalid and i.indimmediate and i.indnatts = 1
        and i.indkey[0] = (select a.attnum from pg_catalog.pg_attribute a
                           where a.attrelid = pg_catalog.to_regclass('crm.contrato_cuentas_pago')
                             and a.attname = 'contrato_id'))
    -- la puerta y el núcleo escriben: las dos VOLATILE
    and (select pg_catalog.count(*) from pg_catalog.pg_proc p
         where p.oid in (pg_catalog.to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'), pg_catalog.to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'))
           and p.provolatile = 'v') = 2
    -- la constancia sigue sin claves foráneas, sin permisos por columna y sin disparadores de más
    and not exists (
      select 1 from pg_catalog.pg_constraint c
      where c.conrelid = pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') and c.contype = 'f')
    and not exists (
      select 1 from pg_catalog.pg_attribute a
      where a.attrelid = pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') and a.attnum > 0 and not a.attisdropped
        and a.attacl is not null)
    and not exists (
      select 1 from pg_catalog.pg_trigger t
      where t.tgrelid = pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') and not t.tgisinternal
        and t.tgname not in ('trg_contrato_cuenta_pago_asignaciones_00_no_borrar',
                             'trg_contrato_cuenta_pago_asignaciones_00_inmutable',
                             'trg_contrato_cuenta_pago_asignaciones_00_sin_vaciar',
                             'trg_audit_contrato_cuenta_pago_asignaciones'))
  ), false) then
    raise exception 'REABRIR ASIGNAR: tras abrir, las piezas no quedaron como las de la migración';
  end if;
end;
$reabrir$;

notify pgrst, 'reload schema';
commit;

-- El veredicto viaja como fila y sale del ESTADO real.
select case
         when pg_catalog.has_function_privilege('authenticated', pg_catalog.to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'), 'EXECUTE')
          and pg_catalog.has_function_privilege('authenticated', pg_catalog.to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'), 'EXECUTE')
          and coalesce((
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
    -- lo que el núcleo da por hecho del vínculo: UNO por contrato, con el nombre por el que lo reconoce
    and exists (
      select 1
      from pg_catalog.pg_constraint c
      join pg_catalog.pg_index i on i.indexrelid = c.conindid
      where c.conrelid = pg_catalog.to_regclass('crm.contrato_cuentas_pago') and c.contype = 'u'
        and c.conname = 'contrato_cuentas_pago_contrato_id_key' and not c.condeferrable
        and i.indisunique and i.indpred is null and i.indisvalid and i.indimmediate and i.indnatts = 1
        and i.indkey[0] = (select a.attnum from pg_catalog.pg_attribute a
                           where a.attrelid = pg_catalog.to_regclass('crm.contrato_cuentas_pago')
                             and a.attname = 'contrato_id'))
    -- la puerta y el núcleo escriben: las dos VOLATILE
    and (select pg_catalog.count(*) from pg_catalog.pg_proc p
         where p.oid in (pg_catalog.to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'), pg_catalog.to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'))
           and p.provolatile = 'v') = 2
    -- la constancia sigue sin claves foráneas, sin permisos por columna y sin disparadores de más
    and not exists (
      select 1 from pg_catalog.pg_constraint c
      where c.conrelid = pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') and c.contype = 'f')
    and not exists (
      select 1 from pg_catalog.pg_attribute a
      where a.attrelid = pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') and a.attnum > 0 and not a.attisdropped
        and a.attacl is not null)
    and not exists (
      select 1 from pg_catalog.pg_trigger t
      where t.tgrelid = pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') and not t.tgisinternal
        and t.tgname not in ('trg_contrato_cuenta_pago_asignaciones_00_no_borrar',
                             'trg_contrato_cuenta_pago_asignaciones_00_inmutable',
                             'trg_contrato_cuenta_pago_asignaciones_00_sin_vaciar',
                             'trg_audit_contrato_cuenta_pago_asignaciones'))
  ), false)
           then 'PUERTA_REABIERTA'
         else 'PUERTA_CERRADA: no se reabrió'
       end as resultado;

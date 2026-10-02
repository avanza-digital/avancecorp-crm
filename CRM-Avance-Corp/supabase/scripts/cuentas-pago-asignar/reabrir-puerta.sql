-- REABRIR la puerta de «Asignar cuenta de pago» después de haberla cerrado con reversa.sql.
-- Solo devuelve el permiso de ejecutar a authenticated en la puerta y en su núcleo (la compuerta
-- de administración sigue dentro del núcleo). Se niega si las piezas no están ENTERAS como las
-- dejó la migración 20261002005004: cuerpos, DEFINER/INVOKER, search_path, candados, bitácora,
-- RLS y permisos. No se reabre una puerta que alguien cambió sin revisarla.
-- Solo Miguel, con autorización expresa.
begin;
set local lock_timeout = '5s';

do $reabrir$
begin
  if pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') is null
     or pg_catalog.to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)') is null
     or pg_catalog.to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)') is null
     or pg_catalog.to_regprocedure('private.trg_contrato_cuenta_pago_asignaciones_inmutable()') is null then
    raise exception 'REABRIR ASIGNAR: la migración 20261002005004 no está aplicada; no hay nada que reabrir';
  end if;
  -- Cuerpo, forma, search_path vacío y dueño de las tres funciones.
  if (select pg_catalog.count(*)
      from (values
        ('private.trg_contrato_cuenta_pago_asignaciones_inmutable()', true, '49bb93b9429aa7b0c168cc8ceb43acfc'),
        ('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)', true, '57297bc7f18279578c2f16f6aaad7247'),
        ('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)', false, '46e03517fc68ffd79fed6892d1128c2b')
      ) as f(firma, definer, huella)
      join pg_catalog.pg_proc p on p.oid = f.firma::regprocedure
      where pg_catalog.md5(p.prosrc) = f.huella
        and p.prosecdef = f.definer
        and p.proconfig = array['search_path=""']
        and pg_catalog.pg_get_userbyid(p.proowner) = current_user::text) <> 3 then
    raise exception 'REABRIR ASIGNAR: el cuerpo, la forma, el search_path o el dueño de alguna función no son los de la migración 20261002005004; no se reabre';
  end if;
  -- Nadie más que el dueño (y, si ya estaba abierta, authenticated) puede ejecutar ninguna de las tres.
  if exists (
    select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
    where p.oid in ('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'::regprocedure,
                    'crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'::regprocedure,
                    'private.trg_contrato_cuenta_pago_asignaciones_inmutable()'::regprocedure)
      and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner
      and (a.grantee <> 'authenticated'::regrole::oid
           or p.oid = 'private.trg_contrato_cuenta_pago_asignaciones_inmutable()'::regprocedure)
  ) or exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid in ('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'::regprocedure,
                    'crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'::regprocedure,
                    'private.trg_contrato_cuenta_pago_asignaciones_inmutable()'::regprocedure)
      and p.proacl is null
  ) then
    raise exception 'REABRIR ASIGNAR: hay un permiso de ejecutar que no es de la migración; no se reabre';
  end if;
  -- La constancia: RLS, sin acceso de la API, sus tres candados con su forma y su bitácora.
  if not (select t.relrowsecurity from pg_catalog.pg_class t
          where t.oid = 'crm.contrato_cuenta_pago_asignaciones'::regclass)
     or exists (
       select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol)
       where pg_catalog.has_table_privilege(r.rol, 'crm.contrato_cuenta_pago_asignaciones',
               'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'))
     or (select pg_catalog.count(*) from pg_catalog.pg_trigger t
         where t.tgrelid = 'crm.contrato_cuenta_pago_asignaciones'::regclass
           and t.tgenabled = 'O' and t.tgqual is null and t.tgattr::text = ''
           and (t.tgname, t.tgfoid, t.tgtype::integer) in (
             ('trg_contrato_cuenta_pago_asignaciones_00_no_borrar',
              'private.trg_registro_cuenta_pago_no_borrar()'::regprocedure::oid, 11),
             ('trg_contrato_cuenta_pago_asignaciones_00_inmutable',
              'private.trg_contrato_cuenta_pago_asignaciones_inmutable()'::regprocedure::oid, 19),
             ('trg_contrato_cuenta_pago_asignaciones_00_sin_vaciar',
              'private.trg_contrato_cuenta_pago_asignaciones_inmutable()'::regprocedure::oid, 34))) <> 3
     or not exists (
       select 1 from pg_catalog.pg_trigger t
       where t.tgrelid = 'crm.contrato_cuenta_pago_asignaciones'::regclass
         and t.tgname = 'trg_audit_contrato_cuenta_pago_asignaciones'
         and t.tgfoid = 'private.log_audit_crm()'::regprocedure
         and t.tgenabled = 'O' and (t.tgtype & 1) = 1 and (t.tgtype & 2) = 0 and (t.tgtype & 28) = 28
         and t.tgqual is null and t.tgattr::text = '')
     or not exists (
       select 1 from pg_catalog.pg_constraint c
       where c.conrelid = 'crm.contrato_cuenta_pago_asignaciones'::regclass and c.contype = 'u'
         and c.conname = 'contrato_cuenta_pago_asignaciones_solicitud_uq' and not c.condeferrable)
     or not exists (
       select 1 from pg_catalog.pg_constraint c
       where c.conrelid = 'crm.contrato_cuenta_pago_asignaciones'::regclass and c.contype = 'c'
         and c.conname = 'contrato_cuenta_pago_asignaciones_motivo_valido' and c.convalidated) then
    raise exception 'REABRIR ASIGNAR: la constancia no está como la dejó la migración (RLS, permisos, candados, bitácora o reglas); no se reabre';
  end if;

  execute 'grant execute on function private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text) to authenticated';
  execute 'grant execute on function crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text) to authenticated';
  perform pg_catalog.set_config('crm.reabrir_asignar_resultado', 'PUERTA_REABIERTA', false);
end;
$reabrir$;

notify pgrst, 'reload schema';
commit;

-- El veredicto viaja como fila (se lanza con `db query --file`, una sesión por archivo).
select pg_catalog.current_setting('crm.reabrir_asignar_resultado', true) as resultado;

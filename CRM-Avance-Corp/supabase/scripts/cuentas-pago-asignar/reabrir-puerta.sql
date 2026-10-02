-- REABRIR la puerta de «Asignar cuenta de pago» después de haberla cerrado con reversa.sql.
-- Solo devuelve el permiso de ejecutar a authenticated en la puerta y en su núcleo (la compuerta
-- de administración sigue dentro del núcleo). Se niega si las piezas no son las de la migración
-- 20261002005004: no se reabre una puerta que alguien cambió sin revisarla.
-- Solo Miguel, con autorización expresa.
begin;
set local lock_timeout = '5s';

do $reabrir$
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
      where p.oid = pg_catalog.to_regprocedure('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'))
       is distinct from 'c636b7394d82f9659cad78da2d3a301a'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
         where p.oid = pg_catalog.to_regprocedure('crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'))
       is distinct from '46e03517fc68ffd79fed6892d1128c2b'
     or pg_catalog.to_regclass('crm.contrato_cuenta_pago_asignaciones') is null then
    raise exception 'REABRIR ASIGNAR: las piezas vivas no son las de la migración 20261002005004; no se reabre';
  end if;
  execute 'grant execute on function private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text) to authenticated';
  execute 'grant execute on function crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text) to authenticated';
  if exists (
    select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
    where p.oid in ('private.asignar_cuenta_pago_contrato_autorizado(uuid,uuid,uuid,text)'::regprocedure,
                    'crm.asignar_cuenta_pago_contrato(uuid,uuid,uuid,text)'::regprocedure)
      and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner
      and a.grantee <> 'authenticated'::regrole::oid
  ) then
    raise exception 'REABRIR ASIGNAR: quedó un permiso de ejecutar de más';
  end if;
  perform pg_catalog.set_config('crm.reabrir_asignar_resultado', 'PUERTA_REABIERTA', false);
end;
$reabrir$;

notify pgrst, 'reload schema';
commit;

select pg_catalog.current_setting('crm.reabrir_asignar_resultado', true) as resultado;

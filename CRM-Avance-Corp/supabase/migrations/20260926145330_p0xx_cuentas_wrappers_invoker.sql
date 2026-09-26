-- P-0XX: puertas de pantalla sin elevacion de privilegios.
-- Excepcion SECURITY INVOKER autorizada por Miguel para ensayo en rama.
-- La autorizacion y los hechos permanecen en private como SECURITY DEFINER.
-- No se conceden permisos de tabla ni se cambian firmas, cuerpos o search_path.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $precondicion$
begin
  if not pg_catalog.has_schema_privilege('authenticated', 'private', 'USAGE') then
    raise exception 'Revisar el permiso de esquema antes de aplicar esta propuesta';
  end if;
end;
$precondicion$;

revoke execute on function private.registrar_cuenta_cliente_autorizado(uuid,jsonb)
  from public, anon;
revoke execute on function private.cuentas_cliente_propias_autorizado()
  from public, anon;
grant execute on function private.registrar_cuenta_cliente_autorizado(uuid,jsonb)
  to authenticated;
grant execute on function private.cuentas_cliente_propias_autorizado()
  to authenticated;

alter function crm.registrar_cuenta_cliente(uuid,jsonb) security invoker;
alter function public.mis_cuentas_bancarias_fn() security invoker;

notify pgrst, 'reload schema';
commit;

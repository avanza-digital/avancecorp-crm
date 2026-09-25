-- P-0XX: el cliente del portal consulta sus cuentas activas del mismo ledger
-- que usa CRM. Solo se devuelven los cuatro ultimos digitos; nunca se concede
-- SELECT directo a authenticated sobre crm.cuentas_bancarias.

-- Capa de autorizacion: auth.uid() delimita la consulta a la propia fila.
create or replace function private.cuentas_cliente_propias_autorizado()
returns table (
  moneda text, banco text, tipo_cuenta text,
  numero_cuenta_mascara text, cci_mascara text,
  origen text, creada_en timestamptz
)
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_cliente_id uuid := (select auth.uid());
begin
  if v_cliente_id is null or not exists (
    select 1 from public.perfiles p
    where p.id = v_cliente_id and p.rol = 'cliente' and p.activo is true
  ) then
    raise exception using errcode = '42501',
      message = 'No autorizado para consultar cuentas bancarias';
  end if;

  return query
  select c.moneda, c.banco, c.tipo_cuenta,
         '••••' || pg_catalog.right(c.numero_cuenta, 4),
         '••••' || pg_catalog.right(c.cci, 4),
         c.origen, c.creada_en
  from private.cuentas_cliente_vigentes(v_cliente_id) c
  order by c.moneda, c.creada_en desc, c.cuenta_id desc;
end;
$function$;
revoke all on function private.cuentas_cliente_propias_autorizado()
  from public, anon, authenticated, service_role;

-- Capa de pantalla: firma sin parametros para que el cliente no pueda pedir
-- otra identidad ni convertir la RPC en un oraculo de existencia de cuentas.
create or replace function public.mis_cuentas_bancarias_fn()
returns table (
  moneda text, banco text, tipo_cuenta text,
  numero_cuenta_mascara text, cci_mascara text,
  origen text, creada_en timestamptz
)
language sql
stable security definer
set search_path to ''
as $function$
  select c.moneda, c.banco, c.tipo_cuenta,
         c.numero_cuenta_mascara, c.cci_mascara, c.origen, c.creada_en
  from private.cuentas_cliente_propias_autorizado() c;
$function$;
revoke all on function public.mis_cuentas_bancarias_fn()
  from public, anon, authenticated, service_role;
grant execute on function public.mis_cuentas_bancarias_fn()
  to authenticated;

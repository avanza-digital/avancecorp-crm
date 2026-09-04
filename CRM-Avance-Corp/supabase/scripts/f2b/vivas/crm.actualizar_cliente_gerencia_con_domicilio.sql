CREATE OR REPLACE FUNCTION crm.actualizar_cliente_gerencia_con_domicilio(p_cliente_id uuid, p_patch jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_domicilio text;
  v_actualizado boolean;
begin
  if private.rol_crm((select auth.uid())) is distinct from 'gerencia' then
    raise insufficient_privilege using
      message = 'Solo Gerencia puede corregir clientes fuera de cartera';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object'
     or not p_patch ? 'domicilio'
     or jsonb_typeof(p_patch->'domicilio') <> 'string' then
    raise exception 'El domicilio legal del cliente es obligatorio'
      using errcode = '22023';
  end if;

  v_domicilio := crm.normalizar_domicilio_legal(p_patch->>'domicilio');

  v_actualizado := crm.actualizar_cliente_gerencia(
    p_cliente_id,
    p_patch - 'domicilio'
  );
  if not v_actualizado then return false; end if;

  update public.perfiles
     set domicilio = v_domicilio
   where id = p_cliente_id
     and rol = 'cliente';
  if not found then
    raise exception 'Cliente no encontrado' using errcode = 'P0002';
  end if;
  return true;
end;
$function$


CREATE OR REPLACE FUNCTION crm.verificar_disponibilidad_lead(p_telefono text, p_dni text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_rol text := private.rol_crm((select auth.uid()));
  v_resultado jsonb;
begin
  if v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using
      errcode = '42501',
      message = 'Acceso CRM revocado';
  end if;

  v_resultado := private.verificar_disponibilidad_lead_impl(p_telefono, p_dni);

  -- Registro anti-pesca (F1 lead libre): la búsqueda por identidad deja
  -- rastro legible por gerencia. Se asienta TODO intento, también el teléfono
  -- inválido — iterar identidades es exactamente lo que se vigila. Si el
  -- normalizado no existe se guarda lo tecleado, acotado.
  insert into crm.verificaciones_lead (verificado_por, telefono_consultado, dni_consultado, veredicto)
  values (
    (select auth.uid()),
    pg_catalog.left(coalesce(private.normalizar_telefono(p_telefono), p_telefono, ''), 32),
    pg_catalog.left(p_dni, 16),
    v_resultado ->> 'estado'
  );

  return v_resultado;
end;
$function$


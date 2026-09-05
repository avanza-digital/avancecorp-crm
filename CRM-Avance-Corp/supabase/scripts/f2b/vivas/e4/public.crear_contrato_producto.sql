CREATE OR REPLACE FUNCTION public.crear_contrato_producto(p_producto_condicion_id uuid, p_contrato jsonb, p_cronograma jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_resultado jsonb;
  v_contrato_id uuid;
  v_condicion_resultante uuid;
  v_config_anterior text := current_setting('crm.producto_condicion_id', true);
begin
  if not (select private.puede_registrar_ventas()) then
    raise insufficient_privilege using message = 'No autorizado para crear contratos desde el Portal';
  end if;
  if p_producto_condicion_id is null then
    raise exception 'Selecciona un producto de inversión'
      using errcode = '22023';
  end if;

  perform pg_catalog.set_config(
    'crm.producto_condicion_id', p_producto_condicion_id::text, true
  );
  v_resultado := public.crear_contrato(p_contrato, p_cronograma);
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', coalesce(v_config_anterior, ''), true
  );

  v_contrato_id := (v_resultado->>'id')::uuid;
  select ct.producto_condicion_id into v_condicion_resultante
  from public.contratos ct
  where ct.id = v_contrato_id;
  if not found then
    raise exception 'Contrato no encontrado después del alta' using errcode = 'P0002';
  end if;
  return v_resultado
    || private.metadata_condicion_producto(v_condicion_resultante);
exception when others then
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', coalesce(v_config_anterior, ''), true
  );
  raise;
end;
$function$


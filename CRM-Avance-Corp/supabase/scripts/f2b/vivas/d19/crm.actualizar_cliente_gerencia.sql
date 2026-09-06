CREATE OR REPLACE FUNCTION crm.actualizar_cliente_gerencia(p_cliente_id uuid, p_patch jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cliente public.perfiles%rowtype;
begin
  if private.rol_crm((select auth.uid())) <> 'gerencia' then
    raise exception 'Solo Gerencia puede corregir clientes fuera de cartera'
      using errcode = '42501';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'Los datos del cliente son invalidos'
      using errcode = '22023';
  end if;
  if (
    p_patch - array[
      'nombre_completo', 'nombres', 'apellidos', 'tipo_documento',
      'dni', 'telefono',
      'banco', 'tipo_cuenta', 'numero_cuenta', 'cci',
      'titular_distinto', 'beneficiario_nombre', 'beneficiario_dni',
      'banco_usd', 'tipo_cuenta_usd', 'numero_cuenta_usd', 'cci_usd',
      'titular_distinto_usd', 'beneficiario_nombre_usd',
      'beneficiario_dni_usd', 'actualizado_en'
    ]::text[]
  ) <> '{}'::jsonb then
    raise exception 'El formulario intento modificar campos no permitidos'
      using errcode = '22023';
  end if;

  select *
    into v_cliente
  from public.perfiles
  where id = p_cliente_id
    and rol = 'cliente'
  for update;
  if not found then
    raise exception 'Cliente no encontrado' using errcode = 'P0002';
  end if;
  -- F2.b (b3): el documento de un cliente ENLAZADO a una identidad solo cambia por la
  -- corrección de documento de Gerencia (b5), que realinea identificador, perfil y lead.
  if (p_patch ? 'dni' or p_patch ? 'tipo_documento')
     and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
     and exists (select 1 from crm.inversionistas i where i.perfil_id = p_cliente_id and i.estado <> 'fusionado')
     and ((p_patch ? 'dni' and p_patch->>'dni' is distinct from v_cliente.dni)
          or (p_patch ? 'tipo_documento' and p_patch->>'tipo_documento' is distinct from v_cliente.tipo_documento)) then
    raise exception 'El documento de un cliente reconocido como persona solo se corrige por la corrección de documento (Gerencia)'
      using errcode = 'P0409';
  end if;

  update public.perfiles
     set nombre_completo = case
           when p_patch ? 'nombre_completo'
             then p_patch->>'nombre_completo'
           else nombre_completo
         end,
         nombres = case
           when p_patch ? 'nombres' then p_patch->>'nombres'
           else nombres
         end,
         apellidos = case
           when p_patch ? 'apellidos' then p_patch->>'apellidos'
           else apellidos
         end,
         tipo_documento = case
           when p_patch ? 'tipo_documento'
             then p_patch->>'tipo_documento'
           else tipo_documento
         end,
         dni = case
           when p_patch ? 'dni' then p_patch->>'dni'
           else dni
         end,
         telefono = case
           when p_patch ? 'telefono' then p_patch->>'telefono'
           else telefono
         end,
         banco = case
           when p_patch ? 'banco' then p_patch->>'banco'
           else banco
         end,
         tipo_cuenta = case
           when p_patch ? 'tipo_cuenta' then p_patch->>'tipo_cuenta'
           else tipo_cuenta
         end,
         numero_cuenta = case
           when p_patch ? 'numero_cuenta'
             then p_patch->>'numero_cuenta'
           else numero_cuenta
         end,
         cci = case
           when p_patch ? 'cci' then p_patch->>'cci'
           else cci
         end,
         titular_distinto = case
           when p_patch ? 'titular_distinto'
             then (p_patch->>'titular_distinto')::boolean
           else titular_distinto
         end,
         beneficiario_nombre = case
           when p_patch ? 'beneficiario_nombre'
             then p_patch->>'beneficiario_nombre'
           else beneficiario_nombre
         end,
         beneficiario_dni = case
           when p_patch ? 'beneficiario_dni'
             then p_patch->>'beneficiario_dni'
           else beneficiario_dni
         end,
         banco_usd = case
           when p_patch ? 'banco_usd' then p_patch->>'banco_usd'
           else banco_usd
         end,
         tipo_cuenta_usd = case
           when p_patch ? 'tipo_cuenta_usd'
             then p_patch->>'tipo_cuenta_usd'
           else tipo_cuenta_usd
         end,
         numero_cuenta_usd = case
           when p_patch ? 'numero_cuenta_usd'
             then p_patch->>'numero_cuenta_usd'
           else numero_cuenta_usd
         end,
         cci_usd = case
           when p_patch ? 'cci_usd' then p_patch->>'cci_usd'
           else cci_usd
         end,
         titular_distinto_usd = case
           when p_patch ? 'titular_distinto_usd'
             then (p_patch->>'titular_distinto_usd')::boolean
           else titular_distinto_usd
         end,
         beneficiario_nombre_usd = case
           when p_patch ? 'beneficiario_nombre_usd'
             then p_patch->>'beneficiario_nombre_usd'
           else beneficiario_nombre_usd
         end,
         beneficiario_dni_usd = case
           when p_patch ? 'beneficiario_dni_usd'
             then p_patch->>'beneficiario_dni_usd'
           else beneficiario_dni_usd
         end,
         actualizado_en = now()
   where id = p_cliente_id;

  return true;
end;
$function$

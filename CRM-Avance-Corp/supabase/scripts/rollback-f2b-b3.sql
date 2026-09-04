-- ============================================================================
-- REVERSA de F2.b sub-lote b3 (20260905100000_crm_f2b_b3_alta_cliente_identidad)
-- ============================================================================
-- Suelta las RPC/helpers nuevos y restaura byte a byte crm.actualizar_cliente_gerencia
-- (verificado por md5 contra el vivo de producción). Conserva claims, enlaces y tramos
-- creados con la bandera encendida (hechos). Bandera APAGADA. Repetible dos veces.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_b3_reversa'));
do $pre$
begin
  if to_regprocedure('crm.saga_conversion_fn(text,jsonb)') is not null then
    raise exception 'REVERSA b3: b4 (20260905110000) sigue instalada y usa la saga de b3; revierte b4 primero';
  end if;
end
$pre$;
update crm.multiempresa_flags set activo = false, actualizado_en = now()
  where nombre = 'resolver_en_puertas' and activo = true;

drop function if exists crm.alta_cliente_identidad_fn(text, jsonb);
drop function if exists crm.cliente_eliminable_fn(uuid);
drop function if exists private.asegurar_identidad_perfil(uuid, text);
drop function if exists private.puede_alta_cliente();
drop function if exists private.saga_auth_avanzar(uuid, text, text, uuid, uuid, integer);
drop function if exists private.saga_auth_localizar(uuid);
drop function if exists private.saga_auth_reclamar(uuid, text, jsonb, uuid, text);
drop function if exists private.saga_token_hash(text);

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
;

do $post$
begin
  if to_regprocedure('crm.alta_cliente_identidad_fn(text,jsonb)') is not null
     or to_regprocedure('private.saga_auth_reclamar(uuid,text,jsonb,uuid,text)') is not null then
    raise exception 'REVERSA b3: quedó algo del lote';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='crm' and p.proname='actualizar_cliente_gerencia') <> 'dc02fd3a57d55e033e2e05cff71996ff' then
    raise exception 'REVERSA b3: actualizar_cliente_gerencia no volvió byte a byte al vivo de producción';
  end if;
  raise notice 'REVERSA F2.b b3 OK';
end
$post$;
commit;

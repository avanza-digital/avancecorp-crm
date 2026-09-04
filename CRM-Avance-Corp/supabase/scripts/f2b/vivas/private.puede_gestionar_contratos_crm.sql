CREATE OR REPLACE FUNCTION private.puede_gestionar_contratos_crm()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    private.rol_crm((select auth.uid())) in ('vendedor','supervisor','gerencia'),
    false
  );
$function$


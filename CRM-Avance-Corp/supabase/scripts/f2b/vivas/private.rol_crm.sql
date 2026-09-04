CREATE OR REPLACE FUNCTION private.rol_crm(p_perfil_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select e.rol_crm
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_perfil_id
    and e.activo is true and p.activo is true
    and e.rol_crm in (
      'vendedor','supervisor','gerencia','coordinador','directorio'
    )
    -- Directorio es una capacidad de lectura, no un alias operativo de
    -- Gerencia. Una pareja desalineada no recibe ningún rol efectivo.
    and (
      (p.rol = 'directorio' and e.rol_crm = 'directorio')
      or (p.rol is distinct from 'directorio' and e.rol_crm <> 'directorio')
    )
    -- Superadmin Portal gobierna roles CRM; solo una membresía de Gerencia le
    -- suma autoridad operativa. Cualquier otro rol queda fuera del gate global.
    and (p.rol is distinct from 'superadmin' or e.rol_crm = 'gerencia');
$function$


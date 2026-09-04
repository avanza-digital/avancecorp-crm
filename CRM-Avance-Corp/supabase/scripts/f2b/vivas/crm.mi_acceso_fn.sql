CREATE OR REPLACE FUNCTION crm.mi_acceso_fn()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_nombre text;
  v_rol_portal text;
  v_perfil_activo boolean;
  v_tiene_equipo boolean;
  v_rol_crm text;
  v_equipo_activo boolean;
  v_es_gerencia boolean := false;
  v_es_superadmin boolean := false;
  v_es_directorio boolean := false;
begin
  if v_actor is null then
    raise insufficient_privilege using message = 'Sesion CRM requerida';
  end if;

  select p.nombre_completo, p.rol, p.activo,
         e.perfil_id is not null, e.rol_crm, e.activo
    into v_nombre, v_rol_portal, v_perfil_activo,
         v_tiene_equipo, v_rol_crm, v_equipo_activo
  from public.perfiles p
  left join crm.equipo e on e.perfil_id = p.id
  where p.id = v_actor;

  if not found then
    return pg_catalog.jsonb_build_object(
      'estado', 'no_enrolado', 'perfil_id', v_actor,
      'puede_listar_usuarios', false,
      'puede_administrar_usuarios', false,
      'puede_organizar_jerarquia', false,
      'puede_administrar_roles', false,
      'puede_contratar', false
    );
  end if;

  if v_perfil_activo is not true
     or (v_tiene_equipo and (
       v_equipo_activo is not true
       or v_rol_crm not in ('vendedor','supervisor','gerencia','coordinador','directorio')
     )) then
    return pg_catalog.jsonb_build_object(
      'estado', 'revocado', 'perfil_id', v_actor,
      'puede_listar_usuarios', false,
      'puede_administrar_usuarios', false,
      'puede_organizar_jerarquia', false,
      'puede_administrar_roles', false,
      'puede_contratar', false
    );
  end if;

  v_es_gerencia := private.es_gerencia_crm_activa();
  v_es_superadmin := private.es_superadmin_portal_activo();
  v_es_directorio := private.es_directorio_crm_activo();

  if v_es_superadmin and not v_es_gerencia then
    return pg_catalog.jsonb_build_object(
      'estado', 'administrador_roles', 'perfil_id', v_actor,
      'rol_portal', v_rol_portal,
      'nombre_completo', v_nombre,
      'puede_listar_usuarios', true,
      'puede_administrar_usuarios', false,
      'puede_organizar_jerarquia', false,
      'puede_administrar_roles', true,
      'puede_contratar', false
    );
  end if;

  if v_tiene_equipo then
    return pg_catalog.jsonb_build_object(
      'estado', 'miembro', 'perfil_id', v_actor,
      'rol_crm', v_rol_crm, 'rol_portal', v_rol_portal,
      'nombre_completo', v_nombre,
      'puede_listar_usuarios',
        v_es_gerencia or v_es_superadmin or v_es_directorio,

-- P-058 · Capacidad única para convertir leads
--
-- Incidente: los usuarios creados por Gerencia nacen correctamente como
-- public.perfiles.rol='comercial' + crm.equipo.rol_crm='vendedor'. La base ya
-- los autorizaba, pero el frontend y la edge exigían además un rol Portal
-- legacy ('analista'/'admin'/'superadmin'), por lo que quedaban bloqueados.
--
-- Fuente única: private.puede_gestionar_contratos_crm(). crm.mi_acceso_fn()
-- publica su resultado como `puede_contratar`; las cuatro puertas SQL de
-- conversión consumen el mismo predicado. No se toca public.*.

begin;

set local lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- 0. Preflight: cada reemplazo debe tener exactamente una huella conocida.
-- ---------------------------------------------------------------------------
do $preflight$
declare
  v_oid regprocedure;
  v_def text;
  v_ancla text;
  v_veces integer;
  v_owner text;
  v_security_definer boolean;
  v_volatilidad "char";
  v_config text[];
begin
  if to_regprocedure('private.puede_gestionar_contratos_crm()') is null then
    raise exception 'P058 preflight: falta private.puede_gestionar_contratos_crm()';
  end if;
  if to_regprocedure('crm.mi_acceso_fn()') is null then
    raise exception 'P058 preflight: falta crm.mi_acceso_fn()';
  end if;

  v_oid := 'private.puede_gestionar_contratos_crm()'::regprocedure;
  select pg_get_userbyid(p.proowner), p.prosecdef, p.provolatile, p.proconfig
    into v_owner, v_security_definer, v_volatilidad, v_config
  from pg_proc p where p.oid = v_oid;
  if v_owner <> 'postgres'
     or not v_security_definer
     or v_volatilidad <> 's'
     or v_config is distinct from array['search_path=""']::text[] then
    raise exception 'P058 preflight: el perímetro de private.puede_gestionar_contratos_crm cambió';
  end if;
  if has_function_privilege('anon', v_oid, 'execute')
     or has_function_privilege('authenticated', v_oid, 'execute')
     or has_function_privilege('service_role', v_oid, 'execute') then
    raise exception 'P058 preflight: la capacidad privada quedó ejecutable desde la API';
  end if;

  v_def := pg_get_functiondef('crm.mi_acceso_fn()'::regprocedure);
  if position('puede_contratar' in v_def) > 0 then
    raise exception 'P058 preflight: crm.mi_acceso_fn ya publica puede_contratar; re-auditar antes de aplicar';
  end if;

  -- Dos salidas cerradas dentro de ramas: perfil ausente y revocado.
  v_ancla := $ancla$
      'puede_administrar_roles', false
    );$ancla$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 2 then
    raise exception 'P058 preflight: esperaba 2 ramas cerradas en mi_acceso_fn; encontró %', v_veces;
  end if;

  -- La salida no_enrolado final tiene dos espacios menos de indentación.
  v_ancla := $ancla$
    'puede_administrar_roles', false
  );$ancla$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'P058 preflight: la salida no_enrolado final cambió';
  end if;

  v_ancla := $ancla$
      'puede_organizar_jerarquia', false,
      'puede_administrar_roles', true
    );$ancla$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'P058 preflight: la salida administrador_roles cambió';
  end if;

  v_ancla := $ancla$
      'puede_organizar_jerarquia', v_es_gerencia,
      'puede_administrar_roles', v_es_superadmin
    );$ancla$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'P058 preflight: la salida miembro cambió';
  end if;

  v_ancla := $ancla$
      'puede_organizar_jerarquia', false,
      'puede_administrar_roles', v_es_superadmin
    );$ancla$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'P058 preflight: la salida global cambió';
  end if;

  foreach v_oid in array array[
    'crm.convertir_lead(uuid,uuid)'::regprocedure,
    'crm.reservar_conversion_lead(uuid)'::regprocedure,
    'crm.marcar_efectos_conversion(uuid)'::regprocedure,
    'crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)'::regprocedure
  ] loop
    v_def := pg_get_functiondef(v_oid);
    if v_oid = 'crm.convertir_lead(uuid,uuid)'::regprocedure then
      v_ancla := $ancla$
  if v_uid is null
     or v_rol not in ('vendedor', 'supervisor', 'gerencia') then$ancla$;
    else
      v_ancla := $ancla$
  if v_uid is null
     or not coalesce(v_rol in ('vendedor', 'supervisor', 'gerencia'), false) then$ancla$;
    end if;

    v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
    if v_veces <> 1 then
      raise exception 'P058 preflight: la puerta de autoridad de % cambió (anclas=%)', v_oid, v_veces;
    end if;
  end loop;

  v_def := pg_get_functiondef(
    'crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)'::regprocedure
  );
  v_ancla := $ancla$
  -- ALLOWLIST con coalesce, NO el `not in` de convertir_lead: con rol_crm NULL
  -- (un cliente del portal, un directorio puro) `v_rol not in (...)` da NULL y
  -- el gate no dispara — el actor moriría después en el ámbito, denegado pero
  -- con el error equivocado (P0001 en vez de 42501). Es la misma trampa que
  -- conversion_mensual_fn documenta; el gate RLS la cazó aquí en vivo.$ancla$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'P058 preflight: el comentario del gate externo cambió';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Publicar la capacidad operativa en el contrato canónico de acceso.
--    Se parchea pg_get_functiondef para preservar íntegro cualquier cambio
--    posterior ajeno a esta capacidad, además del owner y ACL de la función.
-- ---------------------------------------------------------------------------
do $aplicar_acceso$
declare
  v_def text := pg_get_functiondef('crm.mi_acceso_fn()'::regprocedure);
begin
  v_def := replace(
    v_def,
    $ancla$
      'puede_administrar_roles', false
    );$ancla$,
    $reemplazo$
      'puede_administrar_roles', false,
      'puede_contratar', false
    );$reemplazo$
  );

  v_def := replace(
    v_def,
    $ancla$
    'puede_administrar_roles', false
  );$ancla$,
    $reemplazo$
    'puede_administrar_roles', false,
    'puede_contratar', false
  );$reemplazo$
  );

  v_def := replace(
    v_def,
    $ancla$
      'puede_organizar_jerarquia', false,
      'puede_administrar_roles', true
    );$ancla$,
    $reemplazo$
      'puede_organizar_jerarquia', false,
      'puede_administrar_roles', true,
      'puede_contratar', false
    );$reemplazo$
  );

  v_def := replace(
    v_def,
    $ancla$
      'puede_organizar_jerarquia', v_es_gerencia,
      'puede_administrar_roles', v_es_superadmin
    );$ancla$,
    $reemplazo$
      'puede_organizar_jerarquia', v_es_gerencia,
      'puede_administrar_roles', v_es_superadmin,
      'puede_contratar', private.puede_gestionar_contratos_crm()
    );$reemplazo$
  );

  v_def := replace(
    v_def,
    $ancla$
      'puede_organizar_jerarquia', false,
      'puede_administrar_roles', v_es_superadmin
    );$ancla$,
    $reemplazo$
      'puede_organizar_jerarquia', false,
      'puede_administrar_roles', v_es_superadmin,
      'puede_contratar', false
    );$reemplazo$
  );

  execute v_def;
end;
$aplicar_acceso$;

comment on function crm.mi_acceso_fn() is
  'Acceso P04 y capacidades vivas. `puede_contratar` proviene exclusivamente de private.puede_gestionar_contratos_crm(): miembro CRM activo Vendedor, Supervisor o Gerencia; el rol Portal no concede esta capacidad.';

revoke all on function crm.mi_acceso_fn()
  from public, anon, authenticated, service_role;
grant execute on function crm.mi_acceso_fn() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Las cuatro puertas de conversión consumen el mismo predicado privado.
--    v_rol se conserva porque sigue definiendo el ámbito y la atribución.
-- ---------------------------------------------------------------------------
do $aplicar_puertas$
declare
  v_oid regprocedure;
  v_def text;
  v_ancla text;
begin
  foreach v_oid in array array[
    'crm.convertir_lead(uuid,uuid)'::regprocedure,
    'crm.reservar_conversion_lead(uuid)'::regprocedure,
    'crm.marcar_efectos_conversion(uuid)'::regprocedure,
    'crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)'::regprocedure
  ] loop
    v_def := pg_get_functiondef(v_oid);
    if v_oid = 'crm.convertir_lead(uuid,uuid)'::regprocedure then
      v_ancla := $ancla$
  if v_uid is null
     or v_rol not in ('vendedor', 'supervisor', 'gerencia') then$ancla$;
    else
      v_ancla := $ancla$
  if v_uid is null
     or not coalesce(v_rol in ('vendedor', 'supervisor', 'gerencia'), false) then$ancla$;
    end if;

    v_def := replace(
      v_def,
      v_ancla,
      $reemplazo$
  if not private.puede_gestionar_contratos_crm() then$reemplazo$
    );

    if v_oid = 'crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)'::regprocedure then
      v_def := replace(
        v_def,
        $ancla$
  -- ALLOWLIST con coalesce, NO el `not in` de convertir_lead: con rol_crm NULL
  -- (un cliente del portal, un directorio puro) `v_rol not in (...)` da NULL y
  -- el gate no dispara — el actor moriría después en el ámbito, denegado pero
  -- con el error equivocado (P0001 en vez de 42501). Es la misma trampa que
  -- conversion_mensual_fn documenta; el gate RLS la cazó aquí en vivo.$ancla$,
        $reemplazo$
  -- La autoridad no se reinterpreta en esta puerta. El helper canónico
  -- resuelve identidad, vigencia y membresía CRM activa, incluido el caso NULL.$reemplazo$
      );
    end if;
    execute v_def;
  end loop;
end;
$aplicar_puertas$;

-- ---------------------------------------------------------------------------
-- 3. Postflight estructural y de privilegios.
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_oid regprocedure;
  v_def text;
  v_veces integer;
  v_owner text;
  v_security_definer boolean;
  v_volatilidad "char";
  v_config text[];
begin
  v_oid := 'private.puede_gestionar_contratos_crm()'::regprocedure;
  select pg_get_userbyid(p.proowner), p.prosecdef, p.provolatile, p.proconfig
    into v_owner, v_security_definer, v_volatilidad, v_config
  from pg_proc p where p.oid = v_oid;
  if v_owner <> 'postgres'
     or not v_security_definer
     or v_volatilidad <> 's'
     or v_config is distinct from array['search_path=""']::text[] then
    raise exception 'P058 postflight: el perímetro de private.puede_gestionar_contratos_crm cambió';
  end if;
  if has_function_privilege('anon', v_oid, 'execute')
     or has_function_privilege('authenticated', v_oid, 'execute')
     or has_function_privilege('service_role', v_oid, 'execute') then
    raise exception 'P058 postflight: la capacidad privada quedó ejecutable desde la API';
  end if;

  v_oid := 'crm.mi_acceso_fn()'::regprocedure;
  v_def := pg_get_functiondef(v_oid);
  v_veces := (length(v_def) - length(replace(v_def, 'puede_contratar', ''))) / length('puede_contratar');
  if v_veces <> 6 then
    raise exception 'P058 postflight: mi_acceso_fn debe publicar 6 salidas de puede_contratar; encontró %', v_veces;
  end if;
  if position($huella$'puede_contratar', private.puede_gestionar_contratos_crm()$huella$ in v_def) = 0 then
    raise exception 'P058 postflight: la membresía no consume la capacidad canónica';
  end if;

  select pg_get_userbyid(p.proowner), p.prosecdef, p.provolatile, p.proconfig
    into v_owner, v_security_definer, v_volatilidad, v_config
  from pg_proc p where p.oid = v_oid;
  if v_owner <> 'postgres'
     or not v_security_definer
     or v_volatilidad <> 's'
     or v_config is distinct from array['search_path=""']::text[] then
    raise exception 'P058 postflight: atributos de seguridad de mi_acceso_fn cambiaron';
  end if;
  if has_function_privilege('anon', v_oid, 'execute')
     or has_function_privilege('service_role', v_oid, 'execute')
     or not has_function_privilege('authenticated', v_oid, 'execute') then
    raise exception 'P058 postflight: ACL inesperada en mi_acceso_fn';
  end if;

  foreach v_oid in array array[
    'crm.convertir_lead(uuid,uuid)'::regprocedure,
    'crm.reservar_conversion_lead(uuid)'::regprocedure,
    'crm.marcar_efectos_conversion(uuid)'::regprocedure,
    'crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)'::regprocedure
  ] loop
    v_def := pg_get_functiondef(v_oid);
    v_veces := (
      length(v_def)
      - length(replace(v_def, 'if not private.puede_gestionar_contratos_crm() then', ''))
    ) / length('if not private.puede_gestionar_contratos_crm() then');
    if v_veces <> 1 then
      raise exception 'P058 postflight: % no consume una única puerta canónica (veces=%)', v_oid, v_veces;
    end if;
    if v_oid = 'crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)'::regprocedure
       and (
         position('ALLOWLIST con coalesce' in v_def) > 0
         or position('La autoridad no se reinterpreta en esta puerta' in v_def) = 0
       ) then
      raise exception 'P058 postflight: el comentario del gate externo quedó obsoleto';
    end if;

    select pg_get_userbyid(p.proowner), p.prosecdef, p.provolatile, p.proconfig
      into v_owner, v_security_definer, v_volatilidad, v_config
    from pg_proc p where p.oid = v_oid;
    if v_owner <> 'postgres'
       or not v_security_definer
       or v_volatilidad <> 'v'
       or v_config is distinct from array['search_path=""']::text[] then
      raise exception 'P058 postflight: atributos de seguridad de % cambiaron', v_oid;
    end if;
    if has_function_privilege('anon', v_oid, 'execute')
       or has_function_privilege('service_role', v_oid, 'execute')
       or not has_function_privilege('authenticated', v_oid, 'execute') then
      raise exception 'P058 postflight: ACL inesperada en %', v_oid;
    end if;
  end loop;
end;
$postflight$;

commit;

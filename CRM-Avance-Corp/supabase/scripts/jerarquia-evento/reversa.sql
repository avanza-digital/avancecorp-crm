-- Reversa de 20261009223000: restaura los dos pg_get_functiondef exactos de vivo/.
-- Idempotente y fail-closed: rechaza estados mixtos, huellas/ACL/WHEN divergentes.
-- No borra eventos ya registrados ni schema_migrations; sin CASCADE.
-- Completar las mismas cuatro huellas medidas en banco que en la migración.
begin;
set transaction isolation level read committed;
set local lock_timeout = '10s';
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
lock table crm.equipo in share row exclusive mode;

do $mig$
declare
  v_funcion record;
  v_catalogo record;
  v_trigger record;
  v_paso integer;
  v_estado_nuevo boolean;
  v_ya_revertida boolean;
  v_etapa text;
begin
  -- INICIO CATÁLOGO ESPERADO (idéntico en reversa)
  create temporary table jerarquia_funciones (
    firma text primary key, anterior text, nueva text not null,
    modificada boolean not null, definidor boolean not null,
    volatilidad text not null, lenguaje text not null, acl text
  ) on commit drop;
  insert into pg_temp.jerarquia_funciones values
    ('crm.actualizar_jerarquia_usuario_fn(uuid,uuid,timestamptz,uuid)', '79c43d9888cf0d54b92eb26e8b46c3af', '394a9fdc88b7100b8c194f5aadc07b07', true, true, 'v', 'plpgsql', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.registrar_vendedor_usuario_fn(uuid,text,text,text,text,text,text,text,uuid,uuid)', 'c3b73f85fdd791534d6edcc5015b14ff', 'f73bc219788ab19266124cee57931bc7', true, true, 'v', 'plpgsql', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamptz,uuid)', '9be9925a221e64119b21e0f6a299ceb9', '9be9925a221e64119b21e0f6a299ceb9', false, true, 'v', 'plpgsql', null),
    ('private.registrar_evento_usuario(text,uuid,jsonb,uuid)', '8c423da784e0ff61e7eb91c896d851f2', '8c423da784e0ff61e7eb91c896d851f2', false, true, 'v', 'plpgsql', null),
    ('crm.facturacion_diaria_fn(date)', '4b11e1da336f2f296c81f064ce30e35b', '4b11e1da336f2f296c81f064ce30e35b', false, true, 's', 'sql', null),
    ('private.actor_sistema_eventos()', null, '1636285efc3ba6f1b2a6c98a01fdbc53', true, false, 'i', 'sql', '{postgres=X/postgres}'),
    ('private.trg_equipo_evento_jerarquia()', null, '93906f654ba2e4c358ecfe6da1c95f77', true, true, 'v', 'plpgsql', '{postgres=X/postgres}');
  create temporary table jerarquia_triggers (nombre text primary key, definicion text not null) on commit drop;
  insert into pg_temp.jerarquia_triggers values
    ('trg_equipo_evento_jerarquia_insert', 'CREATE TRIGGER trg_equipo_evento_jerarquia_insert AFTER INSERT ON crm.equipo FOR EACH ROW WHEN (new.supervisor_id IS NOT NULL) EXECUTE FUNCTION private.trg_equipo_evento_jerarquia()'),
    ('trg_equipo_evento_jerarquia_update', 'CREATE TRIGGER trg_equipo_evento_jerarquia_update AFTER UPDATE ON crm.equipo FOR EACH ROW WHEN (old.supervisor_id IS DISTINCT FROM new.supervisor_id) EXECUTE FUNCTION private.trg_equipo_evento_jerarquia()');
  -- FIN CATÁLOGO ESPERADO

  select bool_and(coalesce((select md5(pg_catalog.pg_get_functiondef(p.oid))
    from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure(f.firma)) = f.anterior, false))
    into v_ya_revertida from pg_temp.jerarquia_funciones f where f.anterior is not null;
  for v_paso in 1..2 loop
    v_etapa := case when v_paso = 1 then 'PREFLIGHT REVERSA' else 'POSTFLIGHT REVERSA' end;
    v_estado_nuevo := not v_ya_revertida and v_paso = 1;
    -- INICIO VALIDACIÓN DE ESTADO (idéntica en reversa)
    for v_funcion in select * from pg_temp.jerarquia_funciones loop
      select md5(pg_catalog.pg_get_functiondef(p.oid)) as huella,
        pg_catalog.pg_get_userbyid(p.proowner) as dueno, p.proacl::text as acl,
        p.prosecdef as definidor, p.provolatile::text as volatilidad,
        l.lanname as lenguaje, p.proconfig as configuracion
      into v_catalogo from pg_catalog.pg_proc p
      join pg_catalog.pg_language l on l.oid = p.prolang
      where p.oid = pg_catalog.to_regprocedure(v_funcion.firma);
      if v_funcion.anterior is null and not v_estado_nuevo then
        if pg_catalog.to_regprocedure(v_funcion.firma) is not null then
          raise exception '%: ya existe % en un estado sin migrar; no se sobrescribe', v_etapa, v_funcion.firma;
        end if;
        continue;
      end if;
      if (v_catalogo.huella = case when v_estado_nuevo then v_funcion.nueva else v_funcion.anterior end) is not true then
        raise exception '%: huella inesperada en %: %; se deshace todo', v_etapa, v_funcion.firma, v_catalogo.huella;
      end if;
      -- Los tres cuerpos de solo lectura se sellan por huella; las cuatro funciones afectadas, además por ACL.
      if v_funcion.modificada and (v_catalogo.dueno = 'postgres'
          and v_catalogo.acl = v_funcion.acl and v_catalogo.definidor = v_funcion.definidor
          and v_catalogo.volatilidad = v_funcion.volatilidad and v_catalogo.lenguaje = v_funcion.lenguaje
          and cardinality(v_catalogo.configuracion) = 1
          and v_catalogo.configuracion[1] in ('search_path=', 'search_path=""')) is not true then
        raise exception '%: dueño, ACL, prosecdef, volatilidad, lenguaje o search_path inesperado en %: %',
          v_etapa, v_funcion.firma, row_to_json(v_catalogo);
      end if;
    end loop;
    for v_trigger in select * from pg_temp.jerarquia_triggers loop
      select t.tgenabled, t.tgisinternal, t.tgfoid, pg_catalog.pg_get_triggerdef(t.oid) as definicion
      into v_catalogo from pg_catalog.pg_trigger t
      where t.tgrelid = 'crm.equipo'::regclass and t.tgname = v_trigger.nombre;
      if not v_estado_nuevo then
        if found then
          raise exception '%: ya existe el trigger % en un estado sin migrar', v_etapa, v_trigger.nombre;
        end if;
      elsif (v_catalogo.tgenabled = 'O' and not v_catalogo.tgisinternal
          and v_catalogo.tgfoid = pg_catalog.to_regprocedure('private.trg_equipo_evento_jerarquia()')
          -- tgtype no demuestra el WHEN: se compara TODA la definición, incluyendo su predicado.
          and regexp_replace(lower(v_catalogo.definicion), '[[:space:]()]', '', 'g')
            = regexp_replace(lower(v_trigger.definicion), '[[:space:]()]', '', 'g')) is not true then
        raise exception '%: trigger % ausente, deshabilitado o distinto (incluido WHEN): %',
          v_etapa, v_trigger.nombre, v_catalogo.definicion;
      end if;
    end loop;
    if v_estado_nuevo and (select count(*) from pg_catalog.pg_trigger t
        where t.tgfoid = pg_catalog.to_regprocedure('private.trg_equipo_evento_jerarquia()')) <> 2 then
      raise exception '%: la función nueva debe tener exactamente sus dos triggers', v_etapa;
    end if;
    -- FIN VALIDACIÓN DE ESTADO
    if v_paso = 2 then
      exit;
    end if;
    if v_ya_revertida then
      raise notice 'crm_jerarquia_evento_en_toda_via: ya revertida; estado original verificado';
      return;
    end if;

  -- INICIO CUERPOS GENERADOS
  execute $def$
CREATE OR REPLACE FUNCTION crm.actualizar_jerarquia_usuario_fn(p_perfil_id uuid, p_supervisor_id uuid, p_version_equipo timestamp with time zone, p_idempotencia uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_supervisor_anterior uuid;
  v_version timestamptz;
  v_evento_objetivo uuid;
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia puede organizar la jerarquia CRM';
  end if;
  if p_version_equipo is null or p_idempotencia is null then
    raise exception 'Version e idempotencia requeridas';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );

  select e.rol_crm, e.supervisor_id, e.actualizado_en
    into v_rol, v_supervisor_anterior, v_version
  from crm.equipo e where e.perfil_id = p_perfil_id
  for update;
  if not found then
    raise exception 'Membresia CRM no encontrada';
  end if;
  select ue.objetivo_id into v_evento_objetivo
  from crm.usuario_eventos ue
  where ue.actor_id = v_actor
    and ue.accion = 'jerarquia_actualizada'
    and ue.idempotencia = p_idempotencia;
  if found then
    if v_evento_objetivo is distinct from p_perfil_id then
      raise exception 'La idempotencia ya fue usada para otro usuario';
    end if;
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id,
      'supervisor_id', v_supervisor_anterior,
      'version_equipo', v_version, 'idempotente', true
    );
  end if;
  if v_version is distinct from p_version_equipo then
    raise exception using errcode = '40001', message = 'La jerarquia fue modificada por otra sesion';
  end if;

  perform private.validar_supervisor_usuario_crm(
    p_perfil_id, v_rol, p_supervisor_id
  );

  if v_supervisor_anterior is not distinct from p_supervisor_id then
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id, 'supervisor_id', p_supervisor_id,
      'version_equipo', v_version, 'idempotente', true
    );
  end if;

  update crm.equipo e
  set supervisor_id = p_supervisor_id
  where e.perfil_id = p_perfil_id;

  select e.actualizado_en into v_version
  from crm.equipo e where e.perfil_id = p_perfil_id;

  perform private.registrar_evento_usuario(
    'jerarquia_actualizada', p_perfil_id,
    pg_catalog.jsonb_build_object(
      'supervisor_anterior', v_supervisor_anterior,
      'supervisor_nuevo', p_supervisor_id
    ),
    p_idempotencia
  );

  return pg_catalog.jsonb_build_object(
    'perfil_id', p_perfil_id, 'supervisor_id', p_supervisor_id,
    'version_equipo', v_version, 'idempotente', false
  );
end;
$function$
$def$;

  execute $def$
CREATE OR REPLACE FUNCTION crm.registrar_vendedor_usuario_fn(p_perfil_id uuid, p_correo text, p_nombre_completo text, p_tipo_documento text, p_documento text, p_telefono text, p_whatsapp text, p_cargo text, p_supervisor_id uuid, p_idempotencia uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_correo text := lower(pg_catalog.btrim(coalesce(p_correo, '')));
  v_tipo text := upper(pg_catalog.btrim(coalesce(p_tipo_documento, '')));
  v_documento text := upper(pg_catalog.btrim(coalesce(p_documento, '')));
  v_auth_correo text;
  v_origen_app text;
  v_perfil public.perfiles%rowtype;
  v_equipo crm.equipo%rowtype;
  v_perfil_nuevo boolean := false;
  v_eventos bigint;
  v_evento_otro_objetivo boolean;
  v_tiene_rol boolean;
  v_tiene_jerarquia boolean;
  v_tiene_activacion boolean;
  v_version timestamptz;
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message =
      'Solo Gerencia puede completar altas de vendedores CRM';
  end if;
  if p_perfil_id is null or p_supervisor_id is null
     or p_idempotencia is null then
    raise exception 'Perfil, Supervisor e idempotencia son requeridos';
  end if;
  if v_correo !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
     or length(v_correo) > 254 then
    raise exception 'Correo invalido';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );
  -- La autoridad se revalida dentro del candado: un actor revocado mientras
  -- esperaba no puede continuar el alta con una decisión obsoleta.
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message =
      'Solo Gerencia puede completar altas de vendedores CRM';
  end if;

  select
    pg_catalog.count(*),
    coalesce(
      pg_catalog.bool_or(ue.objetivo_id is distinct from p_perfil_id), false
    ),
    coalesce(pg_catalog.bool_or(ue.accion = 'rol_asignado'), false),
    coalesce(
      pg_catalog.bool_or(ue.accion = 'jerarquia_actualizada'), false
    ),
    coalesce(
      pg_catalog.bool_or(ue.accion = 'membresia_activada'), false
    )
    into v_eventos, v_evento_otro_objetivo, v_tiene_rol,
         v_tiene_jerarquia, v_tiene_activacion
  from crm.usuario_eventos ue
  where ue.actor_id = v_actor
    and ue.idempotencia = p_idempotencia;
  if v_eventos > 0 then
    if v_evento_otro_objetivo or not v_tiene_rol
       or not v_tiene_jerarquia or not v_tiene_activacion then
      raise exception 'La idempotencia ya fue usada por otra operacion';
    end if;

    select p.* into v_perfil
    from public.perfiles p where p.id = p_perfil_id;
    select lower(u.email), u.raw_app_meta_data->>'origen_app'
      into v_auth_correo, v_origen_app
    from auth.users u where u.id = p_perfil_id;
    select e.* into v_equipo
    from crm.equipo e where e.perfil_id = p_perfil_id;
    if not found
       or v_perfil.id is null
       or v_perfil.activo is not true
       or v_perfil.rol <> 'comercial'
       or lower(v_perfil.correo) is distinct from v_correo
       or upper(pg_catalog.btrim(v_perfil.tipo_documento)) is distinct from v_tipo
       or upper(pg_catalog.btrim(v_perfil.dni)) is distinct from v_documento
       or v_auth_correo is distinct from v_correo
       or v_origen_app is distinct from 'crm'
       or v_equipo.rol_crm <> 'vendedor'
       or v_equipo.activo is not true
       or v_equipo.supervisor_id is distinct from p_supervisor_id then
      raise exception 'La operacion idempotente perdio su membresia';
    end if;
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id, 'estado', 'activo',
      'rol_crm', 'vendedor', 'supervisor_id', p_supervisor_id,
      'activo_crm', true, 'version_equipo', v_equipo.actualizado_en,
      'idempotente', true
    );
  end if;

  perform private.validar_datos_usuario_crm(
    p_nombre_completo, v_tipo, v_documento,
    nullif(pg_catalog.btrim(p_telefono), ''),
    nullif(pg_catalog.btrim(p_whatsapp), ''),
    nullif(pg_catalog.btrim(p_cargo), '')
  );

  select lower(u.email), u.raw_app_meta_data->>'origen_app'
    into v_auth_correo, v_origen_app
  from auth.users u where u.id = p_perfil_id;
  if not found or v_auth_correo is distinct from v_correo then
    raise exception 'La identidad Auth no coincide con el vendedor';
  end if;

  select p.* into v_perfil
  from public.perfiles p
  where p.id = p_perfil_id
  for update;

  if found then
    if lower(v_perfil.correo) is distinct from v_correo then
      raise exception 'La identidad Auth ya pertenece a otro perfil Portal';
    end if;
    -- Una identidad compartida con el Portal conserva exactamente el flujo y
    -- credenciales previos. Esta frontera solo completa cuentas cuyo origen
    -- servidor y perfil prueban que nacieron exclusivamente en el CRM.
    if v_perfil.rol <> 'comercial' or v_origen_app is distinct from 'crm' then
      return pg_catalog.jsonb_build_object(
        'perfil_id', p_perfil_id, 'estado', 'candidato_existente',
        'idempotente', true
      );
    end if;
    if v_perfil.activo is not true then
      raise exception 'El perfil esta suspendido en Portal';
    end if;
    if upper(pg_catalog.btrim(v_perfil.tipo_documento)) is distinct from v_tipo
       or upper(pg_catalog.btrim(v_perfil.dni)) is distinct from v_documento then
      raise exception 'El documento no coincide con la identidad CRM existente';
    end if;
  else
    if v_origen_app is distinct from 'crm' then
      raise exception 'La identidad nueva no pertenece exclusivamente al CRM';
    end if;
    insert into public.perfiles (
      id, nombre_completo, tipo_documento, dni, correo,
      telefono, whatsapp, cargo, rol, activo, debe_cambiar_password,
      creado_por, creado_en, actualizado_en
    ) values (
      p_perfil_id,
      pg_catalog.btrim(p_nombre_completo),
      v_tipo,
      v_documento,
      v_correo,
      nullif(pg_catalog.btrim(p_telefono), ''),
      nullif(pg_catalog.btrim(p_whatsapp), ''),
      nullif(pg_catalog.btrim(p_cargo), ''),
      'comercial', true, false,
      v_actor, pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
    );
    v_perfil_nuevo := true;
  end if;

  select e.* into v_equipo
  from crm.equipo e where e.perfil_id = p_perfil_id
  for update;
  if found then
    if v_equipo.rol_crm = 'vendedor'
       and v_equipo.activo is true
       and v_equipo.supervisor_id is not distinct from p_supervisor_id then
      return pg_catalog.jsonb_build_object(
        'perfil_id', p_perfil_id, 'estado', 'candidato_existente',
        'rol_crm', v_equipo.rol_crm,
        'supervisor_id', v_equipo.supervisor_id,
        'activo_crm', v_equipo.activo,
        'version_equipo', v_equipo.actualizado_en,
        'idempotente', true
      );
    end if;
    raise exception 'El usuario ya tiene una membresia CRM; usa sus controles de administracion';
  end if;

  perform private.validar_supervisor_usuario_crm(
    p_perfil_id, 'vendedor', p_supervisor_id
  );

  insert into crm.equipo (
    perfil_id, rol_crm, supervisor_id, activo,
    creado_por, creado_en, actualizado_en
  ) values (
    p_perfil_id, 'vendedor', p_supervisor_id, true,
    v_actor, pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

  select e.actualizado_en into v_version
  from crm.equipo e where e.perfil_id = p_perfil_id;

  if v_perfil_nuevo then
    perform private.registrar_evento_usuario(
      'candidato_creado', p_perfil_id,
      pg_catalog.jsonb_build_object('estado', 'activo'),
      p_idempotencia
    );
  end if;
  perform private.registrar_evento_usuario(
    'rol_asignado', p_perfil_id,
    pg_catalog.jsonb_build_object(
      'rol_anterior', null, 'rol_nuevo', 'vendedor'
    ),
    p_idempotencia
  );
  perform private.registrar_evento_usuario(
    'jerarquia_actualizada', p_perfil_id,
    pg_catalog.jsonb_build_object(
      'supervisor_anterior', null, 'supervisor_nuevo', p_supervisor_id
    ),
    p_idempotencia
  );
  perform private.registrar_evento_usuario(
    'membresia_activada', p_perfil_id,
    pg_catalog.jsonb_build_object('activo', true),
    p_idempotencia
  );

  return pg_catalog.jsonb_build_object(
    'perfil_id', p_perfil_id, 'estado', 'activo',
    'rol_crm', 'vendedor', 'supervisor_id', p_supervisor_id,
    'activo_crm', true, 'version_equipo', v_version,
    'idempotente', false
  );
end;
$function$
$def$;

  -- FIN CUERPOS GENERADOS
  drop trigger trg_equipo_evento_jerarquia_insert on crm.equipo;
  drop trigger trg_equipo_evento_jerarquia_update on crm.equipo;
  drop function private.trg_equipo_evento_jerarquia();
  drop function private.actor_sistema_eventos();
  end loop;
  raise notice 'crm_jerarquia_evento_en_toda_via: revertida; eventos existentes conservados';
end $mig$;

-- En producción esta función NO tenía comentario (obj_description NULL, leído el 09/10/2026): se restaura NULL.
comment on function crm.actualizar_jerarquia_usuario_fn(uuid,uuid,timestamptz,uuid) is null;
comment on function crm.registrar_vendedor_usuario_fn(uuid,text,text,text,text,text,text,text,uuid,uuid) is 'Alta inicial atomica de Vendedor exclusivo CRM por Gerencia: supervisor obligatorio, rol fijo y membresia activa. No permite promociones, cambios de rol ni mutaciones sobre identidades Portal.';
commit;

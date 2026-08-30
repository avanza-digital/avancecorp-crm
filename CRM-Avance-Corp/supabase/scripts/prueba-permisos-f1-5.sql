-- PRUEBA DE PUERTAS de la F1.4/F1.5 — ⛔ SOLO en un espejo desechable.
--
-- Lo que la maquinaria nueva NO puede dejar abierto: `authenticated` tiene
-- USAGE sobre el esquema `private`, así que los `revoke` son lo ÚNICO que
-- separa a un usuario del portal de la regla, del vigía y de la lista blanca.
do $puertas$
declare
  v_rol text;
  v_fugas text := '';
begin
  foreach v_rol in array array['anon','authenticated','service_role'] loop
    -- Funciones: ninguna ejecutable
    if pg_catalog.has_function_privilege(v_rol, 'private.tablas_sin_rastro()', 'EXECUTE') then
      v_fugas := v_fugas || v_rol || ' puede EJECUTAR tablas_sin_rastro; ';
    end if;
    if pg_catalog.has_function_privilege(v_rol, 'private.vigia_auditoria()', 'EXECUTE') then
      v_fugas := v_fugas || v_rol || ' puede EJECUTAR vigia_auditoria; ';
    end if;
    if pg_catalog.has_function_privilege(v_rol, 'private.huella_exenciones()', 'EXECUTE') then
      v_fugas := v_fugas || v_rol || ' puede EJECUTAR huella_exenciones; ';
    end if;
    if pg_catalog.has_function_privilege(v_rol, 'private.enmascarar_claves(jsonb,text[])', 'EXECUTE') then
      v_fugas := v_fugas || v_rol || ' puede EJECUTAR enmascarar_claves; ';
    end if;
    -- Tablas: ni leer ni escribir
    if pg_catalog.has_table_privilege(v_rol, 'private.auditoria_exenciones', 'SELECT')
       or pg_catalog.has_table_privilege(v_rol, 'private.auditoria_exenciones', 'INSERT') then
      v_fugas := v_fugas || v_rol || ' alcanza auditoria_exenciones; ';
    end if;
    if pg_catalog.has_table_privilege(v_rol, 'private.auditoria_alertas', 'SELECT') then
      v_fugas := v_fugas || v_rol || ' alcanza auditoria_alertas; ';
    end if;
    if pg_catalog.has_table_privilege(v_rol, 'private.auditoria_sello', 'SELECT') then
      v_fugas := v_fugas || v_rol || ' alcanza auditoria_sello; ';
    end if;
  end loop;

  -- El permiso puede venir de PUBLIC aunque el rol no lo tenga nombrado:
  -- revocar solo a `anon` no cierra nada (trampa ya pagada en este proyecto).
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    cross join lateral pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
    where n.nspname = 'private'
      and p.proname in ('tablas_sin_rastro','vigia_auditoria','huella_exenciones',
                        'enmascarar_claves','log_audit_sin_secretos')
      and a.grantee = 0            -- 0 = PUBLIC
      and a.privilege_type = 'EXECUTE'
  ) then
    v_fugas := v_fugas || 'PUBLIC conserva EXECUTE sobre alguna función nueva; ';
  end if;

  -- Las tres tablas nuevas con RLS encendida y sin una sola política
  if exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private'
      and c.relname in ('auditoria_exenciones','auditoria_alertas','auditoria_sello')
      and not c.relrowsecurity
  ) then
    v_fugas := v_fugas || 'alguna tabla nueva tiene la seguridad por filas APAGADA; ';
  end if;

  if v_fugas <> '' then
    raise exception 'PUERTAS ABIERTAS: %', v_fugas;
  end if;
end
$puertas$;

select 'PUERTAS_CERRADAS_OK' as veredicto;

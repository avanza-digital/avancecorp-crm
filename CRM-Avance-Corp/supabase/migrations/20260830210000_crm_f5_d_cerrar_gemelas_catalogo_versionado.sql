-- P-055 Fase 5.d - CERRAR LA PUERTA GEMELA MUERTA (residual del paso 2 de la Fase 5).
--
-- DECISION DE FONDO (ya firmada por Miguel en la F0, 28/08): "el catalogo de
-- productos versionados se elimina". La F5.b unifico la PREGUNTA de las gemelas
-- (todas preguntan ya puede_registrar_ventas / puede_ver_catalogo_productos);
-- este residual cierra las que SOBRAN por el camino seguro del plan:
-- CERRAR (revoke) -> OBSERVAR -> BORRAR (drop, Fase 7, con OK de Miguel por pieza).
-- Aqui SOLO se cierra. No se borra nada (regla de Miguel: no borrar lo que esta
-- en produccion; estas ni se usan, pero el drop espera su fase).
--
-- LO MEDIDO (30/08, contra produccion y contra los DOS frentes del repo):
--   * 7 funciones CRUD del catalogo versionado son RAMA MUERTA TOTAL:
--       public.crear_contrato_producto(uuid,jsonb,jsonb)
--       public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)
--       public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)
--       crm.crear_contrato_producto(uuid,jsonb,jsonb)
--       crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)
--       crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)
--       crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)
--     - 0 llamadas en el portal (public_html), 0 en el CRM (app/src), 0 en edges,
--       0 llamadas server-side: lo UNICO que las nombra es
--       crm.cerrar_altas_legacy_productos(bigint), y solo como comprobacion de
--       EXISTENCIA (to_regprocedure) -> un REVOKE no la rompe (un DROP si lo haria;
--       por eso el drop va aparte, en la F7).
--   * Las 2 de SELECCION quedan VIVAS y no se tocan (una por frente):
--       public.productos_inversion_seleccion_fn(uuid)  <- portal (productos-contrato-ui.js)
--       crm.productos_inversion_seleccion_fn()         <- CRM (crm-config-api.ts)
--   * ACL medida de las 7: EXECUTE solo authenticated + postgres (sin PUBLIC,
--     sin anon, sin service_role).
--
-- DOS CUIDADOS HEREDADOS:
--   1) has_function_privilege MIENTE si PUBLIC tiene el permiso -> el juez del
--      postflight es el ACL crudo con aclexplode (grantee=0 = PUBLIC), y
--      has_function_privilege queda de segundo testigo.
--   2) NO se llama a una funcion revocada dentro del ensayo (select fn() sin
--      EXECUTE segfaulteo el backend en la imagen 17.6.1.105): la conducta 42501
--      via PostgREST la probara test-rls en el proximo ciclo de banco; aqui la
--      prueba es de ACL, no de conducta.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- =====================================================================
-- 0) PREFLIGHT.
-- =====================================================================
do $$
declare
  v_fn constant text[][] := array[
    array['public.crear_contrato_producto(uuid,jsonb,jsonb)',                     '893c857e27ec6405a3ac6e291458c346'],
    array['public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',           'f0e519cc4ee79c9334ae59a23844b23b'],
    array['public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)','b7e0de18b559ec7fd650619cd22b9cb5'],
    array['crm.crear_contrato_producto(uuid,jsonb,jsonb)',                        '1148d0ca1beb33797995eeff3c579bd4'],
    array['crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',       '06f79b07b4d65dcf50cd4359fb598723'],
    array['crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',              '4156191492c25479be73b0365263d946'],
    array['crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',   '8640b1246f620ab40558cec2875ada23']
  ];
  v_fila text[]; v_h text; v_acl text; v_n integer; v_oids oid[];
begin
  -- a) Las 7 existen y su cuerpo es EL MEDIDO (si alguien las cambio despues
  --    de la medicion, este cierre ya no esta justificado: se re-mide).
  foreach v_fila slice 1 in array v_fn loop
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'F5.d preflight: % cambio desde la medicion (huella %)', v_fila[1], v_h;
    end if;

    -- b) Su ACL EXECUTE es exactamente {authenticated, postgres}: ni PUBLIC
    --    (grantee=0), ni anon, ni service_role. Si difiere, alguien la abrio o
    --    cerro por fuera y este guion no describe la realidad.
    select string_agg(s.quien, ',' order by s.quien)
      into v_acl
      from (select distinct case when a.grantee = 0 then 'PUBLIC' else r.rolname end as quien
              from pg_proc p
              cross join lateral aclexplode(p.proacl) a
              left join pg_roles r on r.oid = a.grantee
             where p.oid = v_fila[1]::regprocedure and a.privilege_type = 'EXECUTE') s;
    if v_acl is distinct from 'authenticated,postgres' then
      raise exception 'F5.d preflight: ACL inesperada en % (%)', v_fila[1], coalesce(v_acl, 'sin-acl');
    end if;
  end loop;

  -- c) Las 2 de seleccion (las VIVAS) existen y authenticated las ejecuta:
  --    son las que NO se tocan y el postflight exige que sigan igual.
  if not has_function_privilege('authenticated', 'public.productos_inversion_seleccion_fn(uuid)'::regprocedure, 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.productos_inversion_seleccion_fn()'::regprocedure, 'EXECUTE') then
    raise exception 'F5.d preflight: una funcion de seleccion del catalogo no esta viva para authenticated';
  end if;

  -- d) Rama muerta CONFIRMADA en el servidor: la unica funcion que nombra a
  --    cualquiera de las 7 es cerrar_altas_legacy_productos (existencia, no llamada).
  --    La exclusion es POR OID (auditoria F5.d, P2-5): una homonima inesperada
  --    en cualquier esquema contaria y reventaria este preflight (fail-closed),
  --    en vez de escaparse del censo por compartir nombre.
  select array_agg(distinct p.oid) into v_oids
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname not in ('pg_catalog', 'information_schema')
     and p.oid <> all (array[
           'public.crear_contrato_producto(uuid,jsonb,jsonb)'::regprocedure,
           'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)'::regprocedure,
           'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)'::regprocedure,
           'crm.crear_contrato_producto(uuid,jsonb,jsonb)'::regprocedure,
           'crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)'::regprocedure,
           'crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)'::regprocedure,
           'crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)'::regprocedure
         ]::oid[])
     and (strpos(p.prosrc, 'crear_contrato_producto') > 0
       or strpos(p.prosrc, 'actualizar_contrato_producto') > 0
       or strpos(p.prosrc, 'actualizar_contrato_con_cuenta_producto') > 0
       or strpos(p.prosrc, 'crear_contrato_con_cuenta_producto') > 0);
  -- El unico match debe SER cerrar_altas_legacy_productos POR OID (auditoria
  -- Codex, P2: un count=1 podria satisfacerlo otra funcion mientras esa
  -- perdio sus menciones — se ata la identidad, no la cuenta).
  if v_oids is distinct from array['crm.cerrar_altas_legacy_productos(bigint)'::regprocedure::oid] then
    raise exception 'F5.d preflight: las gemelas las nombra % (se esperaba SOLO cerrar_altas_legacy_productos)',
      (select string_agg(o::regprocedure::text, ', ') from unnest(coalesce(v_oids, '{}'::oid[])) o);
  end if;

  -- e) Las superficies que prosrc NO cubre, re-medidas EN EL INSTANTE del
  --    publish (auditoria F5.d, P2-4): policies RLS, defaults de columna,
  --    CHECKs y cron. Las tres primeras se evaluan como INVOKER y SI se
  --    romperian con el revoke; la medicion del 30/08 dio 0 en todas y este
  --    guion lo exige de nuevo aqui.
  select (select count(*)
            from pg_policy pol
           where coalesce(pg_get_expr(pol.polqual, pol.polrelid), '') ~ '(crear|actualizar)_contrato(_con_cuenta)?_producto'
              or coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '') ~ '(crear|actualizar)_contrato(_con_cuenta)?_producto')
       + (select count(*)
            from pg_attrdef ad
           where pg_get_expr(ad.adbin, ad.adrelid) ~ '(crear|actualizar)_contrato(_con_cuenta)?_producto')
       + (select count(*)
            from pg_constraint c
           where c.contype = 'c'
             and pg_get_constraintdef(c.oid) ~ '(crear|actualizar)_contrato(_con_cuenta)?_producto')
       + (select count(*)
            from cron.job j
           where j.command ~ '(crear|actualizar)_contrato(_con_cuenta)?_producto')
    into v_n;
  if v_n <> 0 then
    raise exception 'F5.d preflight: % usos de las gemelas en policies/defaults/checks/cron (se esperaba 0)', v_n;
  end if;
  if not exists (
    select 1 from pg_proc p
     where p.oid = 'crm.cerrar_altas_legacy_productos(bigint)'::regprocedure
       and strpos(p.prosrc, 'to_regprocedure') > 0
  ) then
    raise exception 'F5.d preflight: cerrar_altas_legacy_productos ya no comprueba por to_regprocedure';
  end if;
end $$;

-- =====================================================================
-- 1) EL CIERRE: se revoca la ejecucion a la API. postgres (owner) conserva
--    la suya - la consola y un futuro drop de F7 no dependen de esto.
--    PUBLIC y anon van de cinturon: hoy no lo tienen (preflight b), y asi
--    quedo dicho que NO deben tenerlo.
-- =====================================================================
revoke execute on function public.crear_contrato_producto(uuid,jsonb,jsonb)                      from authenticated, anon, public;
revoke execute on function public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)            from authenticated, anon, public;
revoke execute on function public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb) from authenticated, anon, public;
revoke execute on function crm.crear_contrato_producto(uuid,jsonb,jsonb)                         from authenticated, anon, public;
revoke execute on function crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)        from authenticated, anon, public;
revoke execute on function crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)               from authenticated, anon, public;
revoke execute on function crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)    from authenticated, anon, public;

-- =====================================================================
-- 2) POSTFLIGHT (en la MISMA transaccion: si algo no cuadra, nada se aplico).
-- =====================================================================
do $$
declare
  v_cerradas constant text[] := array[
    'public.crear_contrato_producto(uuid,jsonb,jsonb)',
    'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
    'crm.crear_contrato_producto(uuid,jsonb,jsonb)',
    'crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',
    'crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)'
  ];
  v_obj text; v_acl text;
begin
  foreach v_obj in array v_cerradas loop
    -- a) El juez: el ACL crudo. Queda EXACTAMENTE {postgres} con EXECUTE;
    --    en particular ni authenticated, ni anon, ni PUBLIC (grantee=0),
    --    ni service_role.
    select string_agg(s.quien, ',' order by s.quien)
      into v_acl
      from (select distinct case when a.grantee = 0 then 'PUBLIC' else r.rolname end as quien
              from pg_proc p
              cross join lateral aclexplode(p.proacl) a
              left join pg_roles r on r.oid = a.grantee
             where p.oid = v_obj::regprocedure and a.privilege_type = 'EXECUTE') s;
    if v_acl is distinct from 'postgres' then
      raise exception 'F5.d postflight: % no quedo cerrada (EXECUTE de: %)', v_obj, coalesce(v_acl, 'nadie');
    end if;
    -- a2) El ACL LITERAL, entero (auditoria Codex, P1: grantee no basta —
    --     grantor, grant option y orden tambien cuentan). El original medido
    --     era {postgres=X/postgres,authenticated=X/postgres}; quitarle
    --     authenticated deja EXACTAMENTE esto:
    if (select p.proacl::text from pg_proc p where p.oid = v_obj::regprocedure)
       is distinct from '{postgres=X/postgres}' then
      raise exception 'F5.d postflight: proacl de % no es el literal esperado (%)', v_obj,
        (select p.proacl::text from pg_proc p where p.oid = v_obj::regprocedure);
    end if;
    -- b) Segundo testigo (vale porque (a) ya nego a PUBLIC, que es quien lo hace mentir).
    if has_function_privilege('authenticated', v_obj::regprocedure, 'EXECUTE') then
      raise exception 'F5.d postflight: authenticated aun ejecuta %', v_obj;
    end if;
    -- c) La funcion SIGUE EXISTIENDO: cerrar_altas_legacy_productos comprueba
    --    existencia por to_regprocedure y este cierre no debe romperla.
    if to_regprocedure(v_obj) is null then
      raise exception 'F5.d postflight: % desaparecio (aqui solo se cierra, no se borra)', v_obj;
    end if;
  end loop;

  -- d) Las VIVAS del catalogo no se tocaron: cada frente conserva la suya.
  if not has_function_privilege('authenticated', 'public.productos_inversion_seleccion_fn(uuid)'::regprocedure, 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.productos_inversion_seleccion_fn()'::regprocedure, 'EXECUTE') then
    raise exception 'F5.d postflight: una funcion de seleccion del catalogo perdio su permiso';
  end if;

  -- e) LECCION F1.6, por higiene: los dos guardianes corren AQUI, en la misma
  --    transaccion. Un revoke no toca prosrc (los censos miden llamadas en el
  --    cuerpo), pero si esta premisa cambiara algun dia, esto revienta y deshace.
  perform private.assert_analista_vigencia();
  perform private.assert_analitica_leads_citas();
end $$;

commit;

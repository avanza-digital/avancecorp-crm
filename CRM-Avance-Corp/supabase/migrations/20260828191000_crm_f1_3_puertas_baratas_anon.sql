-- P-055 Fase 1.3 - Las puertas baratas: lo que la seguridad por filas NO mira.
--
-- QUE, en una linea: se le quita a los visitantes sin cuenta -y a cualquier
-- sesion iniciada- los cuatro permisos de fabrica que la seguridad por filas no
-- gobierna, y se le quita al visitante sin cuenta el acceso a las 5 consultas
-- de administracion. Nada de lo que el portal usa se toca.
--
-- AVISO SOBRE LA REINCIDENCIA: `alter default privileges` deja una entrada en
-- `pg_default_acl` que la plataforma puede volver a pisar -Supabase reejecuta
-- sus `grant all` en restauraciones y reseteos de esquema-. El endurecimiento
-- no se repara solo: conviene que el gate de realidad lo mire de vez en cuando.
--
-- AVISO SOBRE EL REVOKE A `public`: quitarle EXECUTE a PUBLIC se lo quita
-- tambien a cualquier rol que lo tuviera SOLO por herencia de PUBLIC -por
-- ejemplo `dashboard_user` o `supabase_read_only_user`-. Se ha verificado que
-- los dos que importan (`authenticated` para las pantallas, `service_role`
-- para las edges) tienen concesion propia y no pierden nada.
--
-- 1) VACIAR TABLAS Y TRES PRIMOS SUYOS. Las 10 tablas de `public` nacieron con
--    el permiso completo de fabrica de Supabase (arwdDxtm) para `anon` y para
--    `authenticated`. De esas ocho letras, cuatro NO pasan por la seguridad por
--    filas y por eso son las unicas peligrosas:
--      TRUNCATE   - vacia la tabla entera de un golpe; RLS no la mira.
--      REFERENCES - deja apuntar claves foraneas contra ella.
--      TRIGGER    - deja colgarle triggers.
--      MAINTAIN   - deja lanzarle VACUUM/ANALYZE/REINDEX (candados pesados).
--    Las otras cuatro (SELECT/INSERT/UPDATE/DELETE) SI las gobierna RLS y son
--    exactamente las que el portal necesita: se quedan intactas.
--
--    Se le quitan tambien a `authenticated`, no solo a `anon`, aunque el plan
--    solo hablaba del visitante sin cuenta: el agujero es el mismo para
--    cualquiera con una sesion, y ninguna pantalla del portal ni del CRM vacia
--    tablas, crea triggers, ni lanza mantenimientos. `service_role` conserva
--    todo -es quien opera de verdad-.
--
--    LO QUE ESTA MIGRACION NO TOCA, Y NO ES UN OLVIDO: `anon` conserva
--    INSERT/UPDATE/DELETE sobre esas 10 tablas, y `authenticated` los conserva
--    sobre `public.audit_log`, donde ninguna policy los respalda. Son grants
--    MUERTOS -la seguridad por filas los deja en cero- y recortarlos toca la
--    superficie viva del portal: eso es la Fase 5, que va con prueba completa
--    con cuenta real el mismo dia. Aqui solo se cierra lo que la RLS no mira.
--    El postflight, por eso, comprueba unicamente que este cambio no se lleve
--    por delante el SELECT de nadie: no exige que los grants muertos sigan ahi,
--    para no cementarlos y no hacer fallar a quien manana los recorte.
--
--    Y se corta la reincidencia: los permisos por defecto de `public` los daba
--    tambien a cualquier tabla FUTURA. A partir de aqui, una tabla nueva creada
--    por las migraciones nace sin esas cuatro letras. (Las que crea Supabase
--    por su cuenta, como rol `supabase_admin`, siguen fuera de nuestro alcance:
--    queda declarado.)
--
-- 2) LAS 5 CONSULTAS DE ADMINISTRACION. Cualquiera puede ejecutarlas hoy. No
--    filtran nada -son SECURITY INVOKER, corren como quien llama y RLS las deja
--    en cero filas-, pero no tienen ningun motivo para estar abiertas. Se
--    conservan intactas para `authenticated`, que es quien las usa desde las
--    pantallas de administracion del portal (js/admin/dashboard.js,
--    js/admin/pagos.js), y para `service_role`.
--
--    AVISO: SE REVOCA A `public`, NO SOLO A `anon` - y esto costo una sonda. La
--    primera version de esta migracion revocaba a `anon` y NO CAMBIABA NADA:
--    medido contra produccion, `anon` seguia pudiendo ejecutarlas. El permiso no
--    le venia de su nombre sino de `PUBLIC`: el ACL de las cinco empieza por
--    `{=X/postgres...}`, que es "EXECUTE para todo el mundo". Quitarselo a un rol
--    que lo hereda de PUBLIC no quita nada. Por eso aqui se revoca a `public` y
--    a `anon`, y se vuelven a conceder explicitamente los dos accesos que si
--    existen hoy. Es exactamente el patron que ya usan las funciones del CRM
--    (`crear_contrato` no tiene entrada de PUBLIC en su ACL).
--
-- AVISO: RIESGO CONOCIDO Y ACEPTADO, dicho en voz alta. En la imagen local de
--    Postgres 17.6.1.105 -misma version y mismas librerias que produccion-
--    llamar a una funcion SIN permiso de EXECUTE no da "permission denied":
--    revienta el proceso de Postgres (reproducido 4 veces el 20/08; sospechoso
--    principal `plan_filter`). Nunca se ha probado contra produccion y no debe
--    probarse. Cerrar estas 5 no crea esa exposicion: hay ya casi 300 funciones
--    en los esquemas expuestos que `anon` tampoco puede ejecutar, asi que el
--    vector -si existe en produccion- ya esta abierto y no depende de esta
--    migracion. Lo que si hay que hacer despues de aplicar: comprobar que
--    ninguna pagina PUBLICA del portal (sin sesion) llama a estas 5. Verificado
--    por lectura el 28/08: las 5 solo se invocan desde /admin, detras del login.
--
-- AVISO: PASO OBLIGATORIO EN EL BANCO ANTES DE PUBLICAR ESTA MIGRACION.
--    El riesgo del parrafo anterior no se acepta a ciegas: se COMPRUEBA, y en un
--    branch, que corre la MISMA imagen de Postgres que produccion. Despues de
--    aplicar las cuatro migraciones ahi, hay que hacer una llamada anonima real:
--
--      curl -s -o /dev/null -w '%{http_code}\n' -X POST \
--        "$SUPABASE_URL/rest/v1/rpc/dashboard_admin_metricas" \
--        -H "apikey: $ANON_KEY" -H "Content-Type: application/json" -d '{}'
--
--    Tiene que responder **401/403 con codigo 42501** y el banco tiene que
--    SEGUIR VIVO (una segunda llamada cualquiera debe responder). Si en cambio
--    se cae la conexion o el banco entra en recuperacion, esa es la confirmacion
--    de que el fallo de la imagen tambien afecta aqui: en ese caso NO se publica
--    el bloque 2 de esta migracion -las 5 consultas se quedan como estan, que no
--    filtran nada- y se escala a soporte de Supabase.
--    Motivo de que sea obligatorio: los nombres de esas 5 funciones estan en el
--    JavaScript publicado del portal, asi que son endpoints CONOCIDOS; cerrarlos
--    sin comprobar convertiria un fallo teorico de la plataforma en cinco
--    palancas concretas al alcance de cualquiera con la clave publicable.
--
-- NO crea ni modifica ninguna funcion, policy ni tabla. Solo quita permisos.
--
-- AUTORIZACION: toca permisos de objetos de `public` (portal en produccion) con
-- el OK explicito de Miguel al aprobar la Fase 1 del PLAN MAESTRO P-055.

-- == Preflight: el mundo vivo es el que este cambio describe ==================
do $preflight$
declare
  v_tablas int;
  v_rpcs   int;
begin
  -- Las 10 tablas siguen teniendo las cuatro letras peligrosas para anon.
  select count(*) into v_tablas
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
    and c.relname in ('asesores','audit_log','contrato_titulares','contratos',
                      'cronograma_pagos','documentos','novedades','novedades_leidas',
                      'perfiles','suscripciones_push')
    and has_table_privilege('anon', c.oid, 'TRUNCATE');
  if v_tablas <> 10 then
    raise exception 'PREFLIGHT: se esperaban 10 tablas con TRUNCATE para anon y hay %', v_tablas;
  end if;

  -- Y que no haya aparecido una 11.a tabla en `public` igual de expuesta que
  -- esta lista no nombre. Hoy las 10 nombradas son TODAS las de `public`.
  if (select count(*) from pg_catalog.pg_class c
      where c.relnamespace = 'public'::regnamespace and c.relkind = 'r') <> 10 then
    raise exception 'PREFLIGHT: `public` ya no tiene exactamente 10 tablas; revisar la lista antes de aplicar';
  end if;

  -- Las 5 consultas de administracion siguen abiertas a TODO EL MUNDO (PUBLIC).
  -- Se mira el ACL, no has_function_privilege: esa funcion dice "si" tambien
  -- cuando el permiso viene heredado de PUBLIC, que es justo lo que enmascaro
  -- el problema la primera vez.
  select count(*) into v_rpcs
  from pg_catalog.pg_proc p
  where p.oid in (
      'public.admin_pagos_metricas()'::regprocedure,
      'public.admin_pagos_resumen()'::regprocedure,
      'public.dashboard_admin_metricas()'::regprocedure,
      'public.pagos_admin_metricas_globales()'::regprocedure,
      'public.pagos_admin_resumen_contratos(text,text,text,integer,integer)'::regprocedure)
    and exists (
      select 1 from aclexplode(p.proacl) a
      where a.grantee = 0 and a.privilege_type = 'EXECUTE');
  if v_rpcs <> 5 then
    raise exception 'PREFLIGHT: se esperaban 5 RPC de administracion abiertas a PUBLIC y hay %', v_rpcs;
  end if;
end
$preflight$;

-- == 1. Las cuatro letras que RLS no gobierna ================================
revoke truncate, references, trigger, maintain on table
  public.asesores,
  public.audit_log,
  public.contrato_titulares,
  public.contratos,
  public.cronograma_pagos,
  public.documentos,
  public.novedades,
  public.novedades_leidas,
  public.perfiles,
  public.suscripciones_push
from anon, authenticated;

-- Y que no vuelva a pasar con las tablas que nazcan de aqui en adelante.
alter default privileges for role postgres in schema public
  revoke truncate, references, trigger, maintain on tables from anon, authenticated;

-- == 2. Las 5 consultas de administracion, cerradas al visitante sin cuenta ==
revoke execute on function
  public.admin_pagos_metricas(),
  public.admin_pagos_resumen(),
  public.dashboard_admin_metricas(),
  public.pagos_admin_metricas_globales(),
  public.pagos_admin_resumen_contratos(text,text,text,integer,integer)
from public, anon;

-- Y se devuelve, explicito, exactamente el acceso que existia hoy: nadie pierde
-- una capacidad que estuviera usando.
grant execute on function
  public.admin_pagos_metricas(),
  public.admin_pagos_resumen(),
  public.dashboard_admin_metricas(),
  public.pagos_admin_metricas_globales(),
  public.pagos_admin_resumen_contratos(text,text,text,integer,integer)
to authenticated, service_role;

-- == Postflight: cerrado lo que tocaba y NADA de lo que el portal usa ========
do $postflight$
declare
  v_malas text[] := '{}';
  v_t     record;
  v_rpcs  int;
  v_auth  int;
begin
  for v_t in
    select c.oid, c.relname
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
      and c.relname in ('asesores','audit_log','contrato_titulares','contratos',
                        'cronograma_pagos','documentos','novedades','novedades_leidas',
                        'perfiles','suscripciones_push')
  loop
    -- Lo que tiene que haber desaparecido, para los dos roles.
    if has_table_privilege('anon', v_t.oid, 'TRUNCATE')
       or has_table_privilege('authenticated', v_t.oid, 'TRUNCATE')
       or has_table_privilege('anon', v_t.oid, 'REFERENCES')
       or has_table_privilege('authenticated', v_t.oid, 'REFERENCES')
       or has_table_privilege('anon', v_t.oid, 'TRIGGER')
       or has_table_privilege('authenticated', v_t.oid, 'TRIGGER')
       or has_table_privilege('anon', v_t.oid, 'MAINTAIN')
       or has_table_privilege('authenticated', v_t.oid, 'MAINTAIN') then
      v_malas := v_malas || ('sigue abierta: ' || v_t.relname);
    end if;
    -- Lo que NO se puede haber movido: el portal lee y escribe con RLS delante.
    -- Lo que NO se puede haber movido: la lectura que el portal usa de verdad,
    -- y el rol que opera. Deliberadamente NO se exige aqui que sigan los grants
    -- de escritura de `anon` ni los de `authenticated` sobre `audit_log`: estan
    -- muertos y son tarea de la Fase 5; exigirlos los cementaria.
    if not has_table_privilege('authenticated', v_t.oid, 'SELECT')
       or not has_table_privilege('anon', v_t.oid, 'SELECT')
       or not has_table_privilege('service_role', v_t.oid, 'TRUNCATE') then
      v_malas := v_malas || ('se llevo por delante permisos vivos: ' || v_t.relname);
    end if;
  end loop;
  if array_length(v_malas, 1) is not null then
    raise exception 'POSTFLIGHT: %', array_to_string(v_malas, ' | ');
  end if;

  -- Las 5 consultas: cerradas a anon, INTACTAS para authenticated.
  select count(*) filter (
           where has_function_privilege('anon', p.oid, 'EXECUTE')
              or exists (select 1 from aclexplode(p.proacl) a
                         where a.grantee = 0 and a.privilege_type = 'EXECUTE')),
         count(*) filter (where has_function_privilege('authenticated', p.oid, 'EXECUTE'))
    into v_rpcs, v_auth
  from pg_catalog.pg_proc p
  where p.oid in (
      'public.admin_pagos_metricas()'::regprocedure,
      'public.admin_pagos_resumen()'::regprocedure,
      'public.dashboard_admin_metricas()'::regprocedure,
      'public.pagos_admin_metricas_globales()'::regprocedure,
      'public.pagos_admin_resumen_contratos(text,text,text,integer,integer)'::regprocedure);
  if v_rpcs <> 0 then
    raise exception 'POSTFLIGHT: quedan % consultas de administracion abiertas a anon o a PUBLIC', v_rpcs;
  end if;
  if not has_function_privilege('service_role',
        'public.dashboard_admin_metricas()'::regprocedure, 'EXECUTE') then
    raise exception 'POSTFLIGHT: service_role perdio la consulta de administracion';
  end if;
  if v_auth <> 5 then
    raise exception 'POSTFLIGHT: authenticated perdio acceso a las consultas de administracion (solo % de 5)', v_auth;
  end if;

  -- Y la reincidencia: el permiso por defecto de `public` ya no regala las
  -- cuatro letras a las tablas que nazcan de las migraciones.
  if exists (
    select 1 from pg_catalog.pg_default_acl d, aclexplode(d.defaclacl) a
    where d.defaclrole = 'postgres'::regrole
      and d.defaclnamespace = 'public'::regnamespace
      and d.defaclobjtype = 'r'
      and a.grantee in ('anon'::regrole::oid, 'authenticated'::regrole::oid)
      and a.privilege_type in ('TRUNCATE','REFERENCES','TRIGGER','MAINTAIN')
  ) then
    raise exception 'POSTFLIGHT: el permiso por defecto de public sigue regalando las cuatro letras';
  end if;

  raise notice 'POSTFLIGHT OK: 4 letras cerradas en 10 tablas y en el default de public; 5 RPC cerradas a anon/PUBLIC y vivas para authenticated y service_role';
end
$postflight$;

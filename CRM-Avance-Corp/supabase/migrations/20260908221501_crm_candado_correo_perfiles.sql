-- El candado del correo de acceso: cierra el UPDATE suelto de `perfiles.correo`.
--
-- 🔴 TOCA UN OBJETO DE `public` (trigger sobre `public.perfiles`, que es el
--    portal en producción) ⇒ NO se aplica sin el OK explícito de Miguel
--    anotado en `MIGRACIONES.md`. Por eso viaja separada de
--    `20260908221500_crm_correccion_correo_cliente_superadmin.sql`, que solo
--    vive en el esquema `crm` y no necesita ese permiso.
--
-- EL AGUJERO QUE TAPA, medido el 08/09/2026: el rol `authenticated` tiene
-- GRANT de UPDATE sobre `public.perfiles.correo` a nivel de COLUMNA. Lo único
-- que hoy impide que un analista, dentro de su ventana de corrección de 5 h,
-- desalinee la identidad de su cliente es que el formulario del CRM no manda
-- ese campo en el patch (`app/src/components/app/cliente-form.tsx`). Eso es una
-- defensa de PANTALLA: una llamada a PostgREST hecha a mano la salta entera, y
-- el resultado sería un cliente que no puede entrar al portal sin ningún error
-- visible en ninguna parte — `auth.users` seguiría con el correo viejo.
--
-- Molde: `trg_perfiles_zz_documento_protegido` / `private.trg_perfiles_documento_protegido`,
-- que resuelve exactamente esto para el documento, con las mismas dos llaves de
-- paso en la transacción.
--
-- QUÉ NO ROMPE, comprobado contra los flujos vivos:
--   · el ALTA (`crear-cliente`) escribe el correo en un INSERT, y este trigger
--     es BEFORE UPDATE: no lo ve.
--   · los guiones de operador con `service_role` (p. ej.
--     `supabase/scripts/cambiar-dominio-correo-crm.mjs`) corren sin `auth.uid()`
--     y siguen pasando: quien tiene la llave maestra ya podía hacerlo.
--   · el UPDATE de «corregir cliente» del analista no manda `correo`, y si lo
--     mandara con el MISMO valor tampoco dispara (compara valor, no presencia:
--     PostgREST pone todas las columnas en el SET aunque no cambien).
--
-- 🔴 QUÉ AUTORIDAD CAMBIA (léase antes de dar el OK: es un cambio deliberado
--    sobre el Portal, no solo sobre el analista):
--   · `admin` y `operaciones` PIERDEN una vía que hoy tienen: `perfiles_update`
--     les deja actualizar una fila `rol='cliente'` y el grant de columna cubre
--     `correo`. Tras esto reciben 42501. Comprobado que no rompe nada vivo: el
--     Portal nunca manda `correo` (el campo está `disabled` en
--     `public_html/admin/clientes.html` y no viaja en el payload de
--     `js/admin/clientes.js` ni de `js/admin/analista.js`) y el CRM tampoco.
--   · el propio CLIENTE pierde la vía teórica de cambiarse el correo por
--     `perfiles_update` (`auth.uid() = id`). Hoy el portal no se lo ofrece —el
--     cambio de clave va por GoTrue— así que es latente, pero es el único caso
--     en que este mensaje se le mostraría a un cliente.
--   · el SUPERADMIN pierde el atajo del `PATCH` suelto: tiene que usar la
--     puerta. Ese es el punto (ver el filo P1-1 en el cuerpo).

begin;
set local lock_timeout='5s';
set local check_function_bodies=true;
select pg_advisory_xact_lock(hashtext('crm_candado_correo_perfiles'));

do $guard$
begin
  if exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'perfiles'
      and t.tgname = 'trg_perfiles_zz_correo_protegido'
  ) then
    raise exception 'El candado del correo ya existe';
  end if;
  -- La puerta legítima tiene que estar puesta antes que su reja: si no, este
  -- trigger deja al superadmin sin ninguna vía de corregir el correo.
  if to_regproc('crm.corregir_correo_cliente_admin_fn(uuid, text, text)') is null then
    raise exception 'Falta la puerta crm.corregir_correo_cliente_admin_fn; aplicar antes 20260908221500';
  end if;
  if md5(pg_get_functiondef('public.es_superadmin()'::regprocedure))
     is distinct from '12a443a1fd1597612d12a696ba501671' then
    raise exception 'Cambió public.es_superadmin(); recapturar y revisar antes de aplicar';
  end if;
end
$guard$;

create or replace function private.trg_perfiles_correo_protegido()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
BEGIN
  -- El correo se guarda normalizado SIEMPRE. GoTrue almacena en minúsculas, así
  -- que sin esto « Juan@X.com » entraría al espejo tal cual y se separaría de
  -- `auth.users.email` por pura deriva de formato — la misma familia de
  -- desalineación que este trigger existe para matar.
  new.correo := pg_catalog.lower(pg_catalog.btrim(new.correo));

  -- Solo interesa el cambio real de valor; un upsert de PostgREST pone todas
  -- las columnas en el SET aunque no cambie ninguna.
  IF pg_catalog.lower(pg_catalog.btrim(coalesce(old.correo, '')))
     = coalesce(new.correo, '') THEN
    RETURN new;
  END IF;

  -- La puerta legítima deja sus dos llaves puestas en la transacción.
  IF coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false)
     AND coalesce(pg_catalog.current_setting('crm.correccion_correo', true) = 'on', false) THEN
    RETURN new;
  END IF;

  -- Sin sesión (service_role, `postgres`, los guiones de operador como
  -- `cambiar-dominio-correo-crm.mjs`) esto no aplica: quien tiene la llave
  -- maestra ya podía hacerlo y no se le quita una herramienta que se usa.
  IF (SELECT auth.uid()) IS NULL THEN
    RETURN new;
  END IF;

  IF NOT public.es_superadmin() THEN
    RAISE EXCEPTION 'El correo de acceso de un cliente solo se corrige por la puerta administrativa del superadmin'
      USING ERRCODE = '42501';
  END IF;

  -- 🔑 EL FILO QUE DE VERDAD PROTEGE (hallazgo P1-1 del auditor-rls, 08/09).
  --
  -- Cerrar por ROL no basta: dejaba pasar al superadmin con un `PATCH` suelto a
  -- PostgREST, que mueve SOLO el espejo — sin rastro, sin motivo y sin tocar
  -- `auth`. Es exactamente el accidente que este trigger existe para impedir,
  -- ejecutado por la ÚNICA persona autorizada a usar la pantalla, o sea por
  -- quien más probabilidades tiene de provocarlo.
  --
  -- Con esto la RPC pasa a ser el ÚNICO canal para el correo de un CLIENTE. El
  -- personal (admin, analistas, gerencia) no entra por aquí: su correo se sigue
  -- moviendo con los guiones de operador, que corren sin `auth.uid()`.
  --
  -- Espejo del molde: `private.trg_perfiles_documento_protegido` tiene la misma
  -- segunda cláusula, que fuerza incluso al `admin` a pasar por la puerta
  -- auditada cuando el cliente ya es una identidad reconocida.
  IF old.rol = 'cliente' THEN
    RAISE EXCEPTION 'El correo de un cliente solo se mueve por crm.corregir_correo_cliente_admin_fn, que además mueve su acceso (auth). Un UPDATE suelto lo dejaría sin poder entrar.'
      USING ERRCODE = 'P0409';
  END IF;

  RETURN new;
END
$function$;

-- Las funciones nacen con EXECUTE para PUBLIC y `authenticated` tiene USAGE
-- sobre `private`: sin esto el invariante que el proyecto verifica en el objeto
-- gemelo quedaría roto en este. «Revocar a anon no basta» — se revoca a todos.
revoke all on function private.trg_perfiles_correo_protegido()
  from public, anon, authenticated, service_role;

comment on function private.trg_perfiles_correo_protegido() is
  'Cierra el UPDATE suelto de perfiles.correo: authenticated tiene grant de columna, y hasta ahora lo único que evitaba desalinear la identidad era que el formulario no mandara el campo.';

-- El sufijo `zz` mantiene el orden alfabético de disparo detrás de las guardas
-- de identidad, igual que el candado del documento.
create trigger trg_perfiles_zz_correo_protegido
  before update of correo on public.perfiles
  for each row execute function private.trg_perfiles_correo_protegido();

-- Postflight. `aclexplode` y no `has_function_privilege`: con PUBLIC (grantee 0)
-- en el ACL, `has_function_privilege` dice que sí y el revoke parecería hecho.
do $post$
declare v_fugas int;
begin
  select count(*) into v_fugas
  from pg_proc p, aclexplode(p.proacl) a
  where p.oid = 'private.trg_perfiles_correo_protegido()'::regprocedure
    and a.privilege_type = 'EXECUTE'
    and a.grantee in (0, 'anon'::regrole::oid, 'authenticated'::regrole::oid, 'service_role'::regrole::oid);
  if v_fugas <> 0 then
    raise exception 'POSTFLIGHT: la función del candado conserva % EXECUTE que debía revocarse', v_fugas;
  end if;
end
$post$;

-- El veredicto viaja como FILA: `supabase db query` no transporta los
-- `raise notice`, así que un gate que buscara un aviso estaría verde por vacío.
select 'CANDADO_CORREO_OK' as resultado,
       (select count(*) from pg_trigger t
          join pg_class c on c.oid = t.tgrelid
          join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public' and c.relname = 'perfiles'
          and t.tgname = 'trg_perfiles_zz_correo_protegido') as candado;

commit;

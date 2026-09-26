-- REGISTRO en supabase_migrations.schema_migrations de 20260926193424_crm_historial_cuentas_cliente.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega
-- si las funciones no existen (la migración no se aplicó) o si la versión ya está con otro nombre.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_historial_cuentas_cliente'));
do $chk$
begin
  if to_regprocedure('crm.historial_cuentas_cliente_fn(uuid)') is null
     or to_regprocedure('private.historial_cuentas_cliente_autorizado(uuid)') is null then
    raise exception 'REGISTRO: aplica primero la migración 20260926193424';
  end if;
  -- Identidad, no solo existencia: el cuerpo vivo debe ser EXACTAMENTE el ensayado (con tapado).
  if (select md5(prosrc) from pg_catalog.pg_proc
      where oid = 'private.historial_cuentas_cliente_autorizado(uuid)'::regprocedure)
       is distinct from '22019f9bee83548f756ef3de03157b1a'
     or (select md5(prosrc) from pg_catalog.pg_proc
      where oid = 'crm.historial_cuentas_cliente_fn(uuid)'::regprocedure)
       is distinct from '83f7b235db051264bd6672450248912e' then
    raise exception 'REGISTRO: el cuerpo vivo no es el ensayado; no se registra';
  end if;
  if exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260926193424' and coalesce(name, '') <> 'crm_historial_cuentas_cliente'
  ) then
    raise exception 'REGISTRO: la versión 20260926193424 ya está registrada con otro nombre';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260926193424', 'crm_historial_cuentas_cliente',
        array[$registro$-- Cuentas de Gloria · F2: historial de cuentas bancarias retiradas del cliente.
--
-- Qué hace: añade UNA lectura nueva, crm.historial_cuentas_cliente_fn(p_cliente_id), que
-- devuelve las versiones INACTIVAS (activa = false) de crm.cuentas_bancarias del cliente,
-- con la fecha de retiro y el nombre de quién la retiró. La ventana «Cuentas» del panel
-- admin del portal (miavance.com) la muestra como «Cuentas anteriores».
--
-- Por qué: Miguel (26/09/2026) pidió que Gloria vea todas las cuentas que tuvo el cliente,
-- sin ninguna oculta. Hoy solo se leen las vigentes (private.cuentas_cliente_vigentes).
-- Plan: tablero «Plan Cuentas Gloria» (FigJam de Pagos, nodo 18:42) y la nota del vault
-- «Cuentas bancarias - Gloria ve y añade cuentas, fase 1 publicada (2026-09-26)».
--
-- Diseño (mismo patrón que 20260926145330_p0xx_cuentas_wrappers_invoker):
--   · private.historial_cuentas_cliente_autorizado: SECURITY DEFINER. Justificación: el
--     cliente API no tiene (ni debe tener) grants sobre crm.cuentas_bancarias; la función
--     comprueba ANTES de leer la misma autorización que crm.cuentas_bancarias_cliente_fn
--     (private.puede_gestionar_cuentas_cliente: gestor de cartera, analista de su cartera
--     o rol CRM con visibilidad; nunca un cliente ni anon). search_path vacío, nombres
--     calificados. No está en un esquema expuesto.
--   · crm.historial_cuentas_cliente_fn: puerta de pantalla SECURITY INVOKER, sin elevar
--     privilegios en el esquema expuesto; solo delega.
-- No cambia ninguna función, política, tabla ni permiso existente. Solo lectura.
-- Datos sensibles, TAPADOS EN EL SERVIDOR en esta función (revisión Codex 26/09, P1): N° de
-- cuenta, CCI y los datos del beneficiario (nombre y DNI) salen completos SOLO para
-- public.es_admin() (admin o superadmin activo: Gloria); al resto de autorizados (Operaciones,
-- analista de su cartera, roles CRM) N° y CCI les llegan tapados ('••••' + como mucho 4) y el
-- beneficiario en NULL, igual que en pantalla. Así el historial no abre ninguna fuga nueva.
-- Las lecturas vigentes (cuentas_bancarias_cliente_fn, cliente_detalle_fn, Pagos) no se tocan:
-- taparlas es la fase F2b, aparte.
--
-- Reversión: ../scripts/cuentas-gloria/reversa-historial-cuentas-cliente.sql (borra las dos
-- funciones nuevas; nada más depende de ellas).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $precondicion$
begin
  if to_regclass('crm.cuentas_bancarias') is null
     or to_regprocedure('private.puede_gestionar_cuentas_cliente(uuid)') is null
     or to_regprocedure('public.es_admin()') is null then
    raise exception 'HISTORIAL: faltan crm.cuentas_bancarias, private.puede_gestionar_cuentas_cliente(uuid) o public.es_admin()';
  end if;
  if not pg_catalog.has_schema_privilege('authenticated', 'private', 'USAGE') then
    raise exception 'HISTORIAL: authenticated necesita USAGE sobre private para la puerta INVOKER';
  end if;
  if to_regprocedure('crm.historial_cuentas_cliente_fn(uuid)') is not null
     or to_regprocedure('private.historial_cuentas_cliente_autorizado(uuid)') is not null then
    raise exception 'HISTORIAL: las funciones ya existen; no se sobrescriben';
  end if;
end;
$precondicion$;

-- Núcleo: autoriza y lee.
create function private.historial_cuentas_cliente_autorizado(p_cliente_id uuid)
returns table (
  cuenta_id uuid, moneda text, banco text, tipo_cuenta text,
  numero_cuenta text, cci text, titular_distinto boolean,
  beneficiario_nombre text, beneficiario_dni text, origen text,
  creada_en timestamptz, desactivada_en timestamptz, desactivada_por_nombre text
)
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_completo boolean;
begin
  if p_cliente_id is null
     or not coalesce(private.puede_gestionar_cuentas_cliente(p_cliente_id), false) then
    raise exception using errcode = '42501',
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;
  v_completo := coalesce((select public.es_admin()), false);

  return query
  select cb.id, cb.moneda, cb.banco, cb.tipo_cuenta,
         -- El N° admite de 1 a 30 caracteres: se muestran como mucho 4 y nunca más de la
         -- mitad, para que un número corto no salga entero (revisión Codex R2).
         case when v_completo then cb.numero_cuenta
              else '••••' || pg_catalog.right(cb.numero_cuenta,
                     least(4, pg_catalog.length(cb.numero_cuenta) / 2)) end,
         case when v_completo then cb.cci
              else '••••' || pg_catalog.right(cb.cci, 4) end,
         cb.titular_distinto,
         case when v_completo then cb.beneficiario_nombre end,
         case when v_completo then cb.beneficiario_dni end,
         cb.origen,
         cb.creado_en, cb.desactivada_en, pr.nombre_completo
  from crm.cuentas_bancarias cb
  -- Solo se resuelve el nombre de personal (nunca el de un cliente) bajo DEFINER.
  left join public.perfiles pr on pr.id = cb.desactivada_por and pr.rol <> 'cliente'
  where cb.cliente_id = p_cliente_id
    and cb.activa is false
  order by cb.desactivada_en desc nulls last, cb.creado_en desc, cb.id desc;
end;
$function$;

-- Puerta de pantalla: solo delega.
create function crm.historial_cuentas_cliente_fn(p_cliente_id uuid)
returns table (
  cuenta_id uuid, moneda text, banco text, tipo_cuenta text,
  numero_cuenta text, cci text, titular_distinto boolean,
  beneficiario_nombre text, beneficiario_dni text, origen text,
  creada_en timestamptz, desactivada_en timestamptz, desactivada_por_nombre text
)
language sql
stable security invoker
set search_path to ''
as $function$
  select h.cuenta_id, h.moneda, h.banco, h.tipo_cuenta,
         h.numero_cuenta, h.cci, h.titular_distinto,
         h.beneficiario_nombre, h.beneficiario_dni, h.origen,
         h.creada_en, h.desactivada_en, h.desactivada_por_nombre
  from private.historial_cuentas_cliente_autorizado(p_cliente_id) h;
$function$;

-- Permisos: solo authenticated; la autorización fina vive en el núcleo.
revoke all on function private.historial_cuentas_cliente_autorizado(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.historial_cuentas_cliente_autorizado(uuid)
  to authenticated;
revoke all on function crm.historial_cuentas_cliente_fn(uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.historial_cuentas_cliente_fn(uuid)
  to authenticated;

comment on function private.historial_cuentas_cliente_autorizado(uuid) is
  'Cuentas bancarias RETIRADAS (activa = false) del cliente, con fecha y nombre de quien las retiró. Autoriza con private.puede_gestionar_cuentas_cliente; 42501 si no. SECURITY DEFINER porque authenticated no tiene grants sobre crm.cuentas_bancarias. DATOS SENSIBLES: N° de cuenta, CCI y beneficiario (nombre y DNI) salen completos solo para public.es_admin(); al resto, N° y CCI tapados y beneficiario NULL.';
comment on function crm.historial_cuentas_cliente_fn(uuid) is
  'Puerta de pantalla (INVOKER) del historial de cuentas retiradas del cliente; delega en private.historial_cuentas_cliente_autorizado. La usa la ventana «Cuentas» del panel admin del portal. DATOS SENSIBLES: el núcleo los tapa para quien no es admin/superadmin.';

do $postflight$
begin
  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'private.historial_cuentas_cliente_autorizado(uuid)'::regprocedure
      and p.prosecdef and p.proconfig @> array['search_path=""']
  ) or not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'crm.historial_cuentas_cliente_fn(uuid)'::regprocedure
      and not p.prosecdef and p.proconfig @> array['search_path=""']
  ) then
    raise exception 'HISTORIAL: modo de seguridad o search_path inesperado';
  end if;
  -- EXECUTE exactamente a authenticated en las dos funciones (ni anon, ni PUBLIC, ni service_role).
  if exists (
    select 1
    from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
    where p.oid in ('crm.historial_cuentas_cliente_fn(uuid)'::regprocedure,
                    'private.historial_cuentas_cliente_autorizado(uuid)'::regprocedure)
      and a.privilege_type = 'EXECUTE'
      and a.grantee not in ('authenticated'::regrole::oid, p.proowner)
  ) or not pg_catalog.has_function_privilege('authenticated', 'crm.historial_cuentas_cliente_fn(uuid)', 'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated', 'private.historial_cuentas_cliente_autorizado(uuid)', 'EXECUTE')
     or pg_catalog.has_table_privilege('authenticated', 'crm.cuentas_bancarias', 'SELECT') then
    raise exception 'HISTORIAL: permisos inesperados tras aplicar';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
$registro$])
on conflict (version) do nothing;
select version, name from supabase_migrations.schema_migrations where version = '20260926193424';
commit;

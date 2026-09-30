-- Cuentas de Gloria · F2b: el historial de cuentas retiradas deja de tapar datos.
--
-- Qué hace: recrea private.historial_cuentas_cliente_autorizado (de 20260926193424) SIN el
-- tapado por rol. Misma firma, misma autorización (private.puede_gestionar_cuentas_cliente),
-- mismo filtro activa = false, mismo join de personal. Todo autorizado recibe N°, CCI y
-- beneficiario (nombre y DNI) completos.
--
-- Por qué: decisión de Miguel (26/09/2026) tras ver el mapa de las 4 vías: «quiero que el
-- analista también vea las cuentas»; eligió «todos los que ya ven la cuenta la ven completa»
-- (admin, superadmin, Operaciones y analistas; igual que el CRM, que ya deja copiar el N°).
-- Esto revierte a propósito el tapado que se añadió por la revisión de Codex (R1 P1): aquella
-- «fuga» dejó de serlo porque el negocio decide que ese público debe ver los datos.
-- El público NO cambia: el mismo gate que ya lee las cuentas vigentes completas por
-- crm.cuentas_bancarias_cliente_fn. Permisos, firma y puerta crm.* sin cambios.
--
-- Reversión: ../scripts/cuentas-gloria/reversa-historial-sin-tapado.sql (repone el cuerpo
-- exacto de 20260926193424; exige la firma completa de la F2b antes de tocar nada).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $precondicion$
declare v_firma text;
begin
  -- Firma completa de las dos funciones: cuerpo, SECURITY, search_path y comentario.
  select pg_catalog.string_agg(p.proname || '|' || pg_catalog.md5(p.prosrc) || '|' || p.prosecdef
           || '|' || pg_catalog.array_to_string(p.proconfig, ',') || '|'
           || pg_catalog.md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), '')), ';' order by p.proname)
    into v_firma
  from pg_catalog.pg_proc p
  where p.oid in (to_regprocedure('crm.historial_cuentas_cliente_fn(uuid)'),
                  to_regprocedure('private.historial_cuentas_cliente_autorizado(uuid)'));
  if v_firma is distinct from 'historial_cuentas_cliente_autorizado|22019f9bee83548f756ef3de03157b1a|true|search_path=""|1b76d52290ff6fc83a529431ef9ffc17;historial_cuentas_cliente_fn|83f7b235db051264bd6672450248912e|false|search_path=""|e83e854caa962f70c2dfd229ec72142f' then
    raise exception 'SIN_TAPADO: las funciones vivas no son exactamente la versión de 20260926193424; no se toca';
  end if;
end;
$precondicion$;

create or replace function private.historial_cuentas_cliente_autorizado(p_cliente_id uuid)
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
begin
  if p_cliente_id is null
     or not coalesce(private.puede_gestionar_cuentas_cliente(p_cliente_id), false) then
    raise exception using errcode = '42501',
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  -- Decisión de Miguel (26/09): quien puede ver la cuenta la ve completa; sin tapado.
  return query
  select cb.id, cb.moneda, cb.banco, cb.tipo_cuenta,
         cb.numero_cuenta, cb.cci, cb.titular_distinto,
         cb.beneficiario_nombre, cb.beneficiario_dni, cb.origen,
         cb.creado_en, cb.desactivada_en, pr.nombre_completo
  from crm.cuentas_bancarias cb
  -- Solo se resuelve el nombre de personal (nunca el de un cliente) bajo DEFINER.
  left join public.perfiles pr on pr.id = cb.desactivada_por and pr.rol <> 'cliente'
  where cb.cliente_id = p_cliente_id
    and cb.activa is false
  order by cb.desactivada_en desc nulls last, cb.creado_en desc, cb.id desc;
end;
$function$;

comment on function private.historial_cuentas_cliente_autorizado(uuid) is
  'Cuentas bancarias RETIRADAS (activa = false) del cliente, con fecha y nombre (solo de personal) de quien las retiró. Autoriza con private.puede_gestionar_cuentas_cliente; 42501 si no. SECURITY DEFINER porque authenticated no tiene grants sobre crm.cuentas_bancarias. DATOS SENSIBLES: N° de cuenta, CCI y beneficiario (nombre y DNI) completos para todo autorizado (decisión de Miguel 26/09/2026).';
comment on function crm.historial_cuentas_cliente_fn(uuid) is
  'Puerta de pantalla (INVOKER) del historial de cuentas retiradas del cliente; delega en private.historial_cuentas_cliente_autorizado. La usa la ventana «Cuentas» del panel admin del portal. DATOS SENSIBLES: completos para todo autorizado.';

do $postflight$
begin
  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'private.historial_cuentas_cliente_autorizado(uuid)'::regprocedure
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and pg_catalog.strpos(p.prosrc, 'es_admin') = 0
  ) then
    raise exception 'SIN_TAPADO: modo de seguridad, search_path o cuerpo inesperado';
  end if;
  -- EXECUTE exactamente a authenticated (create or replace conserva la ACL; se comprueba).
  if exists (
    select 1
    from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
    where p.oid in ('crm.historial_cuentas_cliente_fn(uuid)'::regprocedure,
                    'private.historial_cuentas_cliente_autorizado(uuid)'::regprocedure)
      and a.privilege_type = 'EXECUTE'
      and a.grantee not in ('authenticated'::regrole::oid, p.proowner)
  ) or not pg_catalog.has_function_privilege('authenticated', 'private.historial_cuentas_cliente_autorizado(uuid)', 'EXECUTE') then
    raise exception 'SIN_TAPADO: permisos inesperados tras aplicar';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;

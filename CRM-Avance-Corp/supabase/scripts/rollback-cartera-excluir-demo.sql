begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $revision$
begin
  if (
    select md5(pg_get_functiondef(p.oid))
    from pg_proc p
    where p.oid = to_regprocedure('crm.contratos_cartera_fn()')
  ) is distinct from 'afa02c967897b50312d1a963deed0d44' then
    raise exception 'La fachada cambio o no existe. Revalidar antes de continuar.';
  end if;

  if not exists (
    select 1 from pg_proc p
    where p.oid = to_regprocedure('crm.contratos_cartera_fn()')
      and p.proowner = 'postgres'::regrole
      and p.proacl::text =
        '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
      and p.proconfig = array['search_path=""']
      and p.provolatile = 's' and p.prosecdef
  ) then
    raise exception 'Los permisos o atributos cambiaron. Revalidar antes de continuar.';
  end if;
end;
$revision$;

CREATE OR REPLACE FUNCTION crm.contratos_cartera_fn()
 RETURNS TABLE(id uuid, numero_contrato text, cliente_id uuid, cliente_nombre text, asesor_perfil_id uuid, capital numeric, moneda text, tasa_anual numeric, modalidad text, tipo_interes text, categoria text, estado text, fecha_inicio date, fecha_vencimiento date, notas_internas text, creado_por uuid, creado_en timestamp with time zone, producto_condicion_id uuid, producto_id uuid, producto_codigo text, producto_version_id uuid, producto_version integer, producto_nombre text, producto_version_estado text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    c.id, c.numero_contrato, c.cliente_id, cli.nombre_completo,
    cli.asesor_perfil_id, c.capital, c.moneda, c.tasa_anual, c.modalidad,
    c.tipo_interes, c.categoria, c.estado, c.fecha_inicio,
    c.fecha_vencimiento, c.notas_internas, c.creado_por, c.creado_en,
    c.producto_condicion_id, p.id, p.codigo, v.id, v.numero_version,
    v.nombre, v.estado
  from public.contratos c
  join public.perfiles cli on cli.id = c.cliente_id
  join crm.producto_condiciones pc on pc.id = c.producto_condicion_id
  join crm.producto_versiones v on v.id = pc.version_id
  join crm.productos_inversion p on p.id = v.producto_id
  where (
    (select private.es_lector_global())
    or (select private.rol_crm((select auth.uid()))) = 'gerencia'
    or cli.asesor_perfil_id in (
      select private.vendedor_ids_visibles((select auth.uid()))
    )
    or (
      cli.asesor_perfil_id is null
      and cli.creado_por in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
    )
  );
$function$;

do $verificacion$
begin
  if (
    select md5(pg_get_functiondef(p.oid))
    from pg_proc p
    where p.oid = to_regprocedure('crm.contratos_cartera_fn()')
  ) is distinct from '6ed1e840295a31bc3c464418411c773c' then
    raise exception 'La definicion resultante no coincide con la aprobada.';
  end if;

  if not exists (
    select 1 from pg_proc p
    where p.oid = to_regprocedure('crm.contratos_cartera_fn()')
      and p.proowner = 'postgres'::regrole
      and p.proacl::text =
        '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
      and p.proconfig = array['search_path=""']
      and p.provolatile = 's' and p.prosecdef
  ) then
    raise exception 'No se conservaron los permisos o atributos de la fachada.';
  end if;
end;
$verificacion$;

commit;

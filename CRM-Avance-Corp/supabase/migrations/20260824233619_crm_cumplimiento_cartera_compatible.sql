-- Compatibilidad de despliegue escalonado: el bundle vigente valida esta RPC
-- con strictObject. Conserva la conversión de cartera dentro de los campos ya
-- existentes (convertidos/numerador/conversion_real) y no publica todavía el
-- bloque descriptivo `cartera`; el desglose vive en operaciones_cartera.
begin;

do $preflight$
begin
  if (select md5(p.prosrc)
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'crm'
        and p.proname = 'cumplimiento_metas_fn'
        and pg_get_function_identity_arguments(p.oid) = 'p_periodo date')
     is distinct from '6a75a8d72f6d1ad514430c51618b23cf' then
    raise exception 'crm.cumplimiento_metas_fn cambió desde la migración de cartera';
  end if;
end;
$preflight$;

create or replace function crm.cumplimiento_metas_fn(p_periodo date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_lector boolean := private.es_lector_global();
  v_base jsonb;
  v_vendedores jsonb;
begin
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  v_base := crm.cumplimiento_metas_sin_cartera_fn(p_periodo);

  with m as materialized (
    select x.* from private.metricas_cartera_por_vendedor(p_periodo) x
  )
  select coalesce(jsonb_agg(
    jsonb_set(
      e.value,
      '{convertidos}',
      to_jsonb(coalesce((e.value->>'convertidos')::int, 0)
               + coalesce(m.conversiones_clientes, 0)),
      true
    ) order by e.ord
  ), '[]'::jsonb) into v_vendedores
  from jsonb_array_elements(coalesce(v_base->'vendedores','[]'::jsonb))
       with ordinality e(value, ord)
  left join m on m.vendedor_id = (e.value->>'vendedor_id')::uuid;

  return jsonb_set(v_base, '{vendedores}', v_vendedores, true);
end;
$function$;

revoke all on function crm.cumplimiento_metas_fn(date) from public, anon;
grant execute on function crm.cumplimiento_metas_fn(date) to authenticated, service_role;

commit;

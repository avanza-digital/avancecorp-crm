CREATE OR REPLACE FUNCTION crm.resumen_reparto_fn()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ahora timestamptz := now();
  v_payload jsonb;
begin
  if not private.puede_operar_reparto_crm() then
    raise exception 'Solo Coordinacion o Gerencia puede ver el resumen de reparto'
      using errcode = '42501';
  end if;

  with cola as materialized (
    select l.origen, l.moneda, coalesce(l.monto_estimado, 0) as monto,
           l.creado_en, l.clasificacion_auto
    from crm.leads l
    where l.activo = true
      and l.vendedor_id is null
      and l.asignado_supervisor_id is null
      and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
      and l.no_contactar = false
  ),
  por_origen as (
    select coalesce(
             jsonb_agg(jsonb_build_object('origen', x.origen, 'n', x.n)
                       order by x.n desc, x.origen),
             '[]'::jsonb) as j
    from (select c.origen, count(*)::int as n from cola c group by c.origen) x
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'cola', jsonb_build_object(
      'total', count(*),
      'capital', jsonb_build_object(
        'pen', coalesce(sum(c.monto) filter (where c.moneda is distinct from 'USD'), 0),
        'usd', coalesce(sum(c.monto) filter (where c.moneda = 'USD'), 0)
      ),
      -- Días ENTEROS del lead más viejo (espejo de diasEnCola: floor, nunca
      -- negativo). 0 con cola vacía — el front pinta el vacío.
      'espera_max_dias', coalesce(
        (select greatest(floor(extract(epoch from (v_ahora - min(c2.creado_en))) / 86400.0), 0)::int
         from cola c2), 0),
      'posible_credito', count(*) filter (where c.clasificacion_auto = 'posible_credito'),
      'por_origen', (select j from por_origen)
    )
  )
  into v_payload
  from cola c;

  return v_payload;
end;
$function$


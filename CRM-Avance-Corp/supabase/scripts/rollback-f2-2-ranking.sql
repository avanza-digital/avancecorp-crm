-- Vuelta atrás de F2.2: restaura el Ranking del equipo tal y como estaba
-- (md5 4c0cf65902ea5477b63d893e24e01e2b). Ejecutar SOLO si algo se rompe tras
-- aplicar F2.2. OJO: al volver, el ranking marca 0 clientes para TODOS otra
-- vez y se ordena por leads — es el estado anterior, no un arreglo.

CREATE OR REPLACE FUNCTION crm.metricas_conversiones_equipo_fn(p_desde date, p_hasta date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_global boolean;
  v_visibles uuid[];
  v_ahora timestamptz := now();
  v_hoy date := (v_ahora at time zone 'America/Lima')::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_payload jsonb;
begin
  -- 1) GATE EXPLICITO, ANTES DE TOCAR NINGUN DATO.
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null
     or not coalesce(v_rol in ('supervisor', 'gerencia') or v_lector, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- 2) Validacion de parametros (identica a la global).
  if p_desde is null or p_hasta is null or p_desde > p_hasta
     or p_hasta > v_hoy or p_hasta - p_desde > 365 then
    raise exception 'Periodo invalido' using errcode = '22023';
  end if;

  -- 3) Ambito capturado UNA vez en array para que `= any(...)` sea indexable.
  v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
  v_visibles := case when v_global then '{}'::uuid[]
                     else array(select private.vendedor_ids_visibles(v_uid)) end;

  v_ini := p_desde::timestamp at time zone 'America/Lima';
  v_fin := (p_hasta + 1)::timestamp at time zone 'America/Lima';

  with roster as materialized (
    select e.perfil_id as vendedor_id
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.rol_crm = 'vendedor'
      and e.activo is true
      and p.activo is true
      and (v_global or e.perfil_id = any(v_visibles))
  ),
  cohorte as materialized (
    -- `activo is true`: espejo de leads_select. Sin el, un supervisor que apaga
    -- un lead lo seguiria contando en su propio denominador.
    select l.id as lead_id,
           l.vendedor_id,
           (l.contrato_id is not null) as contrato
    from crm.leads l
    where l.creado_en >= v_ini
      and l.creado_en < v_fin
      and l.activo is true
      and l.vendedor_id is not null
      and (v_global or l.vendedor_id = any(v_visibles))
  ),
  responsables_resumen as (
    select r.vendedor_id,
      count(c.lead_id)::int as leads,
      count(c.lead_id) filter (where c.contrato)::int as clientes
    from roster r
    left join cohorte c on c.vendedor_id = r.vendedor_id
    group by r.vendedor_id
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'alcance', case when v_global then 'global' else 'equipo' end,
    'periodo', jsonb_build_object(
      'desde', p_desde,
      'hasta', p_hasta,
      'dias', (p_hasta - p_desde) + 1,
      'zona', 'America/Lima'
    ),
    'responsables', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'vendedor_id', rr.vendedor_id,
          'leads', rr.leads,
          'clientes', rr.clientes,
          'conversion_pct', case when rr.leads > 0
            then round(100.0 * rr.clientes / rr.leads, 1) end
        )
        order by rr.clientes desc, rr.leads desc, rr.vendedor_id
      )
      from responsables_resumen rr
    ), '[]'::jsonb)
  ) into v_payload;

  return private.filtrar_desglose_sujetos_crm(
    v_payload, 'responsables', 'vendedor_id', array['vendedor']
  );
end;
$function$;

do $verifica$
begin
  if (select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'metricas_conversiones_equipo_fn'
         and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_desde date, p_hasta date')
     is distinct from '4c0cf65902ea5477b63d893e24e01e2b' then
    raise exception 'el rollback NO restauró el ranking esperado';
  end if;
end;
$verifica$;

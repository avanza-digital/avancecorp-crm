CREATE OR REPLACE FUNCTION private.cartera_f5_fuentes()
 RETURNS TABLE(fuente_id uuid, inversionista_id uuid, inversion_id uuid, empresa text, perfil_id uuid, lead_id uuid, numero text, capital numeric, moneda text, estado text, fecha_comercial date, fecha_imputacion date, vence_en date, analista_origen_id uuid, es_inicial boolean, es_demo boolean, identidad_coherente boolean, creado_en timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- La canónica de cada persona y el analista atribuido de cada contrato se calculan UNA vez por
  -- llamada (mapas jsonb) en vez de una CTE recursiva por FILA: medido el 30/09/2026, cada llamada
  -- hacía ~1.900 llamadas a inversionista_canonica() y ~685 a analista_atribuido_cadena() (42 ms);
  -- con los mapas, 11 ms y las mismas 726 filas. Los mapas repiten el criterio EXACTO de esas dos
  -- funciones (que no cambian): paseo hacia la raíz con tope 16 y, sin raíz, el propio id; primer
  -- ancestro «upgrade» por operaciones_cartera con lista de visitados y tope 100.
  with recursive
  paseo as (
    select i.id as origen, i.id, i.inversionista_canonico_id, 1 as n from crm.inversionistas i
    union all
    select w.origen, i.id, i.inversionista_canonico_id, w.n+1
    from paseo w join crm.inversionistas i on i.id = w.inversionista_canonico_id where w.n < 16
  ),
  canon as (
    select origen as id,
      coalesce((array_agg(id order by n desc) filter (where inversionista_canonico_id is null))[1], origen) as canon
    from paseo group by origen
  ),
  cadena as (
    select c.id as raiz, c.id as contrato_id, 0 as nivel, array[c.id] as visitados from public.contratos c
    union all
    select cd.raiz, o.contrato_origen_id, cd.nivel + 1, cd.visitados || o.contrato_origen_id
    from cadena cd join crm.operaciones_cartera o on o.contrato_nuevo_id = cd.contrato_id
    where o.contrato_origen_id is not null and not (o.contrato_origen_id = any(cd.visitados)) and cd.nivel < 100
  ),
  atrib as (
    select distinct on (cd.raiz) cd.raiz, con.analista_cierre_id
    from cadena cd join public.contratos con on con.id = cd.contrato_id
    where con.categoria = 'upgrade' order by cd.raiz, cd.nivel asc
  ),
  canon_map as (select coalesce(jsonb_object_agg(id::text, canon::text), '{}'::jsonb) as m from canon),
  atrib_map as (select coalesce(jsonb_object_agg(raiz::text, analista_cierre_id::text), '{}'::jsonb) as m from atrib)
  select c.id, ids.personas[1], iv.id, 'avance'::text, c.cliente_id, null::uuid,
    c.numero_contrato, c.capital, c.moneda, c.estado,
    c.fecha_cierre_comercial, c.fecha_cierre_comercial, c.fecha_vencimiento,
    coalesce((((select m from atrib_map)->>c.id::text)::uuid),c.analista_cierre_id),
    iv.es_primera_conversion,c.es_demo,
    cardinality(ids.personas)=1, c.creado_en
  from public.contratos c
  left join crm.inversiones iv on iv.contrato_id=c.id
  cross join lateral (
    select array_agg(distinct coalesce(((select m from canon_map)->>x.id::text)::uuid, x.id)) as personas
    from (
      select i.id from crm.inversionistas i where i.perfil_id=c.cliente_id
      union select iv.inversionista_id where iv.inversionista_id is not null
    ) x
  ) ids
  union all
  select ce.id, ids.personas[1],iv.id,ce.cooperativa,null::uuid,ce.lead_id,
    ce.referencia_externa,ce.monto,ce.moneda,
    case when ce.anulado_en is not null then 'anulado_comercialmente'
      when ce.vence_en < (statement_timestamp() at time zone 'America/Lima')::date
      then 'vencido' else 'vigente' end,
    coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
    coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date),
    ce.vence_en,ce.vendedor_id,ce.es_cierre_inicial,
    ce.id='a112aead-184a-4979-9041-943978fadae4'::uuid,
    cardinality(ids.personas)=1,ce.creado_en
  from crm.cierres_externos ce
  left join crm.inversiones iv on iv.cierre_externo_id=ce.id
  left join crm.leads l on l.id=ce.lead_id
  cross join lateral (
    select array_agg(distinct coalesce(((select m from canon_map)->>x.id::text)::uuid, x.id)) as personas
    from (select ce.inversionista_id as id union select iv.inversionista_id
          union select l.inversionista_id) x where x.id is not null
  ) ids;
$function$

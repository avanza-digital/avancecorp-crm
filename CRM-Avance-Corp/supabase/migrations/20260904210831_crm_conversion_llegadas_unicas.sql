-- Conversión comercial: llegadas únicas, atribuidas al primer analista.
-- Conserva firmas, permisos y las fotografías ya cerradas. No toca Auth.
begin;
set local lock_timeout = '10s';

-- Abortamos ante deriva del código. Se capturaron las siete funciones de
-- producción el 04/09/2026; no se sobreescriben cambios posteriores.
create temporary table conversion_llegadas_perimetro on commit drop as
select p.oid, p.proowner, p.proacl, p.prosecdef, p.provolatile, p.proconfig
from pg_proc p
where p.oid in ('crm.cerrar_periodo(date)'::regprocedure,
  'private.conversion_episodios(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric)'::regprocedure,
  'private.conversion_mensual_por_vendedor(timestamp with time zone,timestamp with time zone,boolean,uuid[],numeric)'::regprocedure,
  'crm.conversion_mensual_sin_cartera_fn(date)'::regprocedure,
  'crm.metricas_conversiones_equipo_fn(date,date)'::regprocedure,
  'private.metricas_conversiones_implementacion(date,date,text)'::regprocedure,
  'private.metricas_distribucion_leads_v3_core(date,date,timestamp with time zone)'::regprocedure);
do $preflight$
declare r record;
begin
  for r in select * from (values
    ('crm.cerrar_periodo(date)', 'a3fe78f62b637412f780835c9cd9a0db'),
    ('private.conversion_episodios(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric)', '81965aed36e11d77d18ea2cb4c94b550'),
    ('private.conversion_mensual_por_vendedor(timestamp with time zone,timestamp with time zone,boolean,uuid[],numeric)', '7d2940a0f3368bacf3a5e719c76bfff5'),
    ('crm.conversion_mensual_sin_cartera_fn(date)', 'bb80938ccc6bd0f1e48a5f14706c0f01'),
    ('crm.metricas_conversiones_equipo_fn(date,date)', '5e2e49d46e341eeceaf386ae173db00a'),
    ('private.metricas_conversiones_implementacion(date,date,text)', '9571a83135075e062c44c81bfdfee937'),
    ('private.metricas_distribucion_leads_v3_core(date,date,timestamp with time zone)', '9faa7e6342713d2df07450a4473a90b6')
  ) esperado(firma, huella) loop
    if md5(pg_get_functiondef(r.firma::regprocedure)) <> r.huella then
      raise exception 'Conversión llegadas: cambió %, recapturar y revisar antes de aplicar', r.firma;
    end if;
  end loop;
end;
$preflight$;

create or replace function private.conversion_episodios(
  p_ini timestamptz, p_fin timestamptz, p_periodo date,
  p_global boolean, p_visibles uuid[], p_factor numeric
)
returns table (
  tipo text, analista_id uuid, lead_id uuid, operacion_id uuid,
  fue_referido boolean, aproximado boolean, motivo text, anulado boolean,
  origen text, categoria text, mes_origen date, monto numeric, moneda text,
  fecha_divisor timestamptz, fecha_numerador timestamptz,
  aporte_divisor integer, aporte_numerador numeric
)
language plpgsql stable security definer set search_path = ''
as $function$
#variable_conflict use_column
begin
return query
-- Una llegada por id, por su alta ORIGINAL en Lima. No depende del estado
-- actual ni de cuántas veces se asigne, descarte, rescate o cambie de dueño.
-- La primera asignación se busca en toda la historia ANTES de aplicar ámbito.
-- Sin asignación aún: cuenta en empresa, nunca se inventa un responsable.
select 'recibido'::text, primera.analista_id, l.id, null::uuid,
  l.origen = 'referido', coalesce(primera.aproximado, false),
  'llegada'::text, false, l.origen, null::text,
  date_trunc('month', l.creado_en at time zone 'America/Lima')::date,
  null::numeric, null::text, l.creado_en, null::timestamptz,
  case when l.origen in ('landing', 'formulario') and not l.alta_manual
    then 1 else 0 end, 0::numeric
from crm.leads l
left join lateral (
  select la.analista_id, la.aproximado
  from crm.lead_asignaciones la
  where la.lead_id = l.id
  order by la.asignado_en, la.ciclo_n, la.episodio_n, la.id
  limit 1
) primera on true
where l.creado_en >= p_ini and l.creado_en < p_fin
  and l.origen in ('landing', 'formulario', 'referido')
  and (p_global or primera.analista_id = any(p_visibles))

union all

-- El índice único del ledger garantiza un cierre por lead. El cierre queda
-- en quien lo consiguió, no en quien recibió la llegada. Los otros canales
-- siguen disponibles para consumidores operativos/capital, con aporte CERO.
select 'cierre'::text, la.analista_id, la.lead_id, null::uuid,
  l.origen = 'referido', null::boolean, null::text,
  private.cierre_externo_anulado(la.lead_id), l.origen, null::text,
  date_trunc('month', l.creado_en at time zone 'America/Lima')::date,
  null::numeric, null::text, null::timestamptz,
  coalesce(la.resultado_en, la.finalizado_en), 0,
  case when private.cierre_externo_anulado(la.lead_id) then 0
    when l.origen = 'referido' then
      case when p_periodo is not null then p_factor else
        private.peso_referido_conversion(date_trunc('month',
          coalesce(la.resultado_en, la.finalizado_en) at time zone 'America/Lima')::date) end
    when l.origen in ('landing', 'formulario') then 1
    else 0 end
from crm.lead_asignaciones la
join crm.leads l on l.id = la.lead_id
where la.resultado = 'convertido'
  and coalesce(la.resultado_en, la.finalizado_en) >= p_ini
  and coalesce(la.resultado_en, la.finalizado_en) < p_fin
  and (p_global or la.analista_id = any(p_visibles))

union all

-- La primera operación ELEGIBLE por cliente/mes, antes de filtrar el rango
-- o el ámbito. Renovación usa el mismo peso que Referido; Upgrade conserva 1.
-- Un rango parcial incluye solo las operaciones efectivamente ocurridas allí.
select 'operacion'::text,
  coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id),
  null::uuid, o.id, false, null::boolean, null::text, false,
  null::text, o.tipo, o.periodo, null::numeric, o.moneda,
  null::timestamptz, o.fecha_operacion::timestamp at time zone 'America/Lima', 0,
  case when o.tipo = 'renovacion' then
    case when p_periodo is not null then p_factor
      else private.peso_referido_conversion(o.periodo) end
    when o.tipo = 'upgrade' then 1 else 0 end
from (
  select o0.*, row_number() over (
    partition by o0.cliente_id, o0.periodo
    order by o0.fecha_operacion, o0.creado_en, o0.id
  ) as orden_conversion
  from crm.operaciones_cartera o0
  where o0.elegible_conversion
    and o0.periodo >= date_trunc('month', p_ini at time zone 'America/Lima')::date
    and o0.periodo <= date_trunc('month', p_fin at time zone 'America/Lima')::date
) o
where o.orden_conversion = 1
  and o.fecha_operacion::timestamp at time zone 'America/Lima' >= p_ini
  and o.fecha_operacion::timestamp at time zone 'America/Lima' < p_fin
  and (p_global or coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id),
                           o.vendedor_id) = any(p_visibles));
end;
$function$;

comment on function private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)
is 'Núcleo comercial único v2: alta original de Landing/Formulario/Referido; divisor solo automáticos Landing/Formulario, primera atribución histórica. Referido y renovación ponderados igual; upgrade 1. Consumidores SUMAN aporte_divisor/aporte_numerador, nunca asignaciones.';

CREATE OR REPLACE FUNCTION private.conversion_mensual_por_vendedor(p_ini timestamp with time zone, p_fin timestamp with time zone, p_global boolean, p_visibles uuid[], p_factor numeric)
 RETURNS TABLE(analista_id uuid, divisor integer, divisor_aproximado integer, divisor_por_motivo jsonb, cierres_no_referidos integer, cierres_referidos integer, cierres_de_arrastre integer, numerador numeric, conversion_pct numeric, procedencia jsonb, referidos_recibidos integer, referidos_aporta_pct numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
return query
with ep as (
  select e.* from private.conversion_episodios(
    p_ini, p_fin,
    case when date_trunc('month', p_ini at time zone 'America/Lima') =
      date_trunc('month', (p_fin - interval '1 microsecond') at time zone 'America/Lima')
      then date_trunc('month', p_ini at time zone 'America/Lima')::date end,
    p_global, p_visibles, p_factor
  ) e
), recibidos as (
  select e.analista_id, e.lead_id, e.fue_referido, e.motivo, e.aproximado, e.aporte_divisor
  from ep e where e.tipo = 'recibido'
), cierres as (
  select e.analista_id, e.lead_id, e.fue_referido, e.mes_origen,
    date_trunc('month', p_ini at time zone 'America/Lima')::date as mes_periodo
  from ep e where e.tipo = 'cierre' and not e.anulado
    and e.origen in ('landing', 'formulario', 'referido')
), motivos as (
  select r.analista_id, r.motivo, count(*)::int as n
  from recibidos r where r.aporte_divisor > 0
  group by r.analista_id, r.motivo
), motivos_json as (
  select m.analista_id, jsonb_object_agg(m.motivo, m.n) as divisor_por_motivo
  from motivos m group by m.analista_id
), agg_div as (
  select r.analista_id,
    sum(r.aporte_divisor)::int as divisor,
    coalesce(sum(r.aporte_divisor) filter (where r.aproximado), 0)::int as divisor_aproximado,
    count(*) filter (where r.fue_referido)::int as referidos_recibidos
  from recibidos r group by r.analista_id
), agg_cie as (
  select c.analista_id,
    count(distinct c.lead_id) filter (where not c.fue_referido)::int as cierres_no_referidos,
    count(distinct c.lead_id) filter (where c.fue_referido)::int as cierres_referidos,
    count(distinct c.lead_id) filter (where c.mes_origen < c.mes_periodo)::int as cierres_de_arrastre
  from cierres c group by c.analista_id
), aportes as (
  select e.analista_id,
    sum(e.aporte_divisor)::int as divisor,
    sum(e.aporte_numerador) as numerador,
    coalesce(sum(e.aporte_numerador) filter (where e.tipo = 'cierre' and e.fue_referido), 0) as aporte_referidos
  from ep e group by e.analista_id
), proc as (
  select c.analista_id, c.mes_cubo,
    (count(distinct c.lead_id) filter (where not c.fue_referido)
     + count(distinct c.lead_id) filter (where c.fue_referido))::int as cierres,
    count(distinct c.lead_id) filter (where c.fue_referido)::int as cierres_referidos
  from (
    select c0.analista_id, c0.lead_id, c0.fue_referido,
      case when
        (extract(year from p_ini at time zone 'America/Lima')::int * 12
         + extract(month from p_ini at time zone 'America/Lima')::int)
        - (extract(year from c0.mes_origen)::int * 12
           + extract(month from c0.mes_origen)::int) <= 11
      then c0.mes_origen end as mes_cubo
    from cierres c0
  ) c
  group by c.analista_id, c.mes_cubo
), proc_json as (
  select p.analista_id,
    jsonb_agg(jsonb_build_object(
      'mes', case when p.mes_cubo is not null then to_char(p.mes_cubo, 'YYYY-MM') end,
      'mes_nombre', case when p.mes_cubo is not null
        then private.etiqueta_mes_es(p.mes_cubo) else 'anteriores' end,
      'anio', case when p.mes_cubo is not null then extract(year from p.mes_cubo)::int end,
      'cierres', p.cierres, 'cierres_referidos', p.cierres_referidos
    ) order by p.mes_cubo desc nulls last) as procedencia
  from proc p group by p.analista_id
)
select
  a.analista_id,
  a.divisor,
  coalesce(d.divisor_aproximado, 0),
  coalesce(mj.divisor_por_motivo, '{}'::jsonb),
  coalesce(c.cierres_no_referidos, 0),
  coalesce(c.cierres_referidos, 0),
  coalesce(c.cierres_de_arrastre, 0),
  a.numerador,
  case when a.divisor > 0 then round(100.0 * a.numerador / a.divisor, 2) end,
  coalesce(pj.procedencia, '[]'::jsonb),
  coalesce(d.referidos_recibidos, 0),
  case when a.divisor > 0 then round(100.0 * a.aporte_referidos / a.divisor, 2) end
from aportes a
left join agg_div d on d.analista_id is not distinct from a.analista_id
left join agg_cie c on c.analista_id is not distinct from a.analista_id
left join motivos_json mj on mj.analista_id is not distinct from a.analista_id
left join proc_json pj on pj.analista_id is not distinct from a.analista_id;
end;
$function$;

CREATE OR REPLACE FUNCTION private.metricas_conversiones_implementacion(p_desde date, p_hasta date, p_origen text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_cosecha_fin timestamptz;
  v_mes date;
  v_factor numeric;
  v_periodo date;
  v_payload jsonb;
  v_autorizado boolean;
begin
  select exists (
    select 1 from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.perfil_id = v_uid and e.activo and p.activo and e.rol_crm = 'gerencia'
  ) or private.es_lector_global() into v_autorizado;
  if v_uid is null or not coalesce(v_autorizado, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_desde is null or p_hasta is null or p_desde > p_hasta
     or p_hasta > v_hoy or p_hasta - p_desde > 365 then
    raise exception 'Periodo invalido' using errcode = '22023';
  end if;
  v_ini := p_desde::timestamp at time zone 'America/Lima';
  v_fin := (p_hasta + 1)::timestamp at time zone 'America/Lima';

  -- La cosecha mira hasta HOY: un lead que entro en el rango puede haber
  -- cerrado despues, y esa maduracion es justamente lo que la lectura por
  -- cosecha responde («de ese lote, cuantos acabaron cerrando»).
  v_cosecha_fin := greatest(v_fin, now());

  -- Peso del referido del mes del `hasta` — la MISMA regla que usa el heroe
  -- de HOY para el mes del rango.
  v_mes := date_trunc('month', p_hasta)::date;
  v_factor := private.peso_referido_conversion(v_mes);

  -- El periodo identifica una ventana mensual; ya NO habilita/deshabilita
  -- cartera: el núcleo limita toda operación a su fecha efectiva en el rango.
  -- En rangos libres aplica el peso de cada mes dentro del propio núcleo.
  v_periodo := case
    when p_desde = date_trunc('month', p_desde)::date
     and date_trunc('month', p_hasta)::date = date_trunc('month', p_desde)::date
     and (p_hasta = (date_trunc('month', p_desde) + interval '1 month' - interval '1 day')::date
          or p_hasta = v_hoy)
    then p_desde
  end;

  with vendedores_base as materialized (
    select e.perfil_id as vendedor_id
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.activo and p.activo and e.rol_crm = 'vendedor'
  ),
  -- ── TABLA-BASE ──────────────────────────────────────────────────────────
  -- Flujo comercial del rango: llegadas únicas y aportes del núcleo.
  ep_flujo as materialized (
    select e.* from private.conversion_episodios(
      v_ini, v_fin, v_periodo, true, null, v_factor
    ) e
  ),
  -- Cierres del ledger que sirven de numerador a la COSECHA: los de sus
  -- leads, ocurran cuando ocurran (hasta hoy). Sin anulados.
  ep_cosecha as materialized (
    select distinct e.lead_id
    from private.conversion_episodios(
      v_ini, v_cosecha_fin, null, true, null, v_factor
    ) e
    where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.lead_id is not null
  ),
  cohorte_base as materialized (
    -- F1.3b: el capital del lead se mide por los caminos VIVOS y HASTA HOY
    -- (lectura de cosecha: «de ese lote, cuanto ha producido»): contratos del
    -- portal de su perfil + cierres en coops vigentes. Aqui muere la primera
    -- de las dos ultimas lecturas del enlace jamas poblado (leads.contrato_id).
    select l.id, l.origen, l.etapa, l.categoria_interes, l.creado_en,
      l.convertido_en, l.perfil_id, l.contrato_id, l.asignado_supervisor_id,
      l.creado_por, llegada.analista_id as vendedor_id,
      (coalesce((select sum(k.monto) from private.capital_episodios(
           '-infinity'::timestamptz,
           'infinity'::timestamptz, true, '{}'::uuid[]) k
         where k.moneda = 'PEN'
           and (   (k.tipo like 'contrato_%' and k.cliente_id = l.perfil_id)
                or (k.tipo = 'cooperativa'   and k.lead_id   = l.id))), 0)) as capital_lead_pen,
      (coalesce((select sum(k.monto) from private.capital_episodios(
           '-infinity'::timestamptz,
           'infinity'::timestamptz, true, '{}'::uuid[]) k
         where k.moneda = 'USD'
           and (   (k.tipo like 'contrato_%' and k.cliente_id = l.perfil_id)
                or (k.tipo = 'cooperativa'   and k.lead_id   = l.id))), 0)) as capital_lead_usd
    from ep_flujo llegada
    join crm.leads l on l.id = llegada.lead_id
    where llegada.tipo = 'recibido'
      -- Filtro de ORIGEN (pedido de Miguel 27/08): recorta el LOTE — cohorte,
      -- embudo, origenes, categorias, responsables y tendencia beben todos de
      -- aqui. 'sin_origen' selecciona los leads sin origen registrado. El
      -- nucleo y las sondas de paridad NO se filtran (miden el MES de la
      -- empresa y esta pantalla ya no los pinta): el payload declara el
      -- filtro en `origen_filtrado` para que nadie confunda las dos aguas.
      and (p_origen is null or coalesce(l.origen, 'sin_origen') = p_origen)
  ),
  senales as materialized (
    select cb.*,
      (cb.vendedor_id is not null or cb.asignado_supervisor_id is not null or exists (
        select 1 from crm.lead_asignaciones la where la.lead_id = cb.id
      )) as h_asignado,
      exists (
        select 1 from crm.actividades a
        where a.lead_id = cb.id and (
          a.tipo in ('llamada_realizada','whatsapp_recibido','reunion_realizada')
          or (a.tipo = 'cambio_etapa' and a.metadata->>'etapa_nueva' in (
            'contactado','reunion_agendada','propuesta_enviada','convertido'
          ))
        )
      ) as h_contacto,
      exists (
        select 1 from crm.tareas t where t.lead_id = cb.id and t.tipo = 'reunion'
      ) or exists (
        select 1 from crm.actividades a where a.lead_id = cb.id
          and a.tipo = 'cambio_etapa' and a.metadata->>'etapa_nueva' = 'reunion_agendada'
      ) as h_reunion_agendada,
      exists (
        select 1 from crm.tareas t where t.lead_id = cb.id
          and t.tipo = 'reunion' and t.estado = 'completada'
      ) or exists (
        select 1 from crm.actividades a where a.lead_id = cb.id and a.tipo = 'reunion_realizada'
      ) as h_reunion_realizada,
      exists (
        select 1 from crm.actividades a where a.lead_id = cb.id
          and a.tipo = 'cambio_etapa' and a.metadata->>'etapa_nueva' = 'propuesta_enviada'
      ) or cb.etapa = 'propuesta_enviada' as h_propuesta,
      -- ANTES: (perfil_id is not null or etapa = 'convertido') / (contrato_id is not null)
      -- AHORA: el cierre del LEDGER, sin anulados. Un cierre anulado por
      -- gerencia deja de contar aqui igual que en el nucleo.
      (cb.id in (select ec.lead_id from ep_cosecha ec)) as h_cliente,
      (cb.id in (select ec.lead_id from ep_cosecha ec)) as h_contrato
    from cohorte_base cb
  ),
  cohorte as materialized (
    select s.*,
      h_asignado as asignado,
      (h_contacto or h_reunion_agendada or h_reunion_realizada or h_propuesta or h_cliente or h_contrato) as contactado,
      (h_reunion_agendada or h_reunion_realizada or h_propuesta or h_cliente or h_contrato) as reunion_agendada,
      (h_reunion_realizada or h_propuesta or h_cliente or h_contrato) as reunion_realizada,
      (h_propuesta or h_cliente or h_contrato) as propuesta,
      (h_cliente or h_contrato) as cliente,
      h_contrato as contrato
    from senales s
  ),
  resumen as (
    select
      count(*)::int as leads,
      count(*) filter (where asignado)::int as asignados,
      count(*) filter (where contactado)::int as contactados,
      count(*) filter (where reunion_agendada)::int as reuniones_agendadas,
      count(*) filter (where reunion_realizada)::int as reuniones_realizadas,
      count(*) filter (where propuesta)::int as propuestas,
      count(*) filter (where cliente)::int as clientes,
      count(*) filter (where contrato)::int as contratos,
      count(*) filter (where etapa = 'descartado')::int as descartados
    from cohorte
  ),
  -- ── NUCLEO (cifra principal) ────────────────────────────────────────────
  -- Se agrupa POR ANALISTA con la misma aritmetica del nucleo y luego se suma.
  -- OJO: el total NO tiene por que ser la suma de `responsables`: aqui entran
  -- TODOS los analistas con episodios (supervisores incluidos), mientras que
  -- `responsables` sale del roster de vendedores activos y ademas el wrapper
  -- publico elimina del array a quien no sea vendedor. La sonda
  -- `divisor_fuera_del_roster` mide exactamente ese hueco.
  nucleo_vendedor as (
    select e.analista_id,
      coalesce(sum(e.aporte_divisor), 0)::int as divisor,
      count(*) filter (where e.tipo = 'recibido' and e.fue_referido)::int as referidos_recibidos,
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and not e.fue_referido)::int as cierres_no_referidos,
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.fue_referido)::int as cierres_referidos,
      count(*) filter (where e.tipo = 'operacion')::int as operaciones,
      coalesce(sum(e.aporte_numerador), 0)::numeric as numerador
    from ep_flujo e
    group by e.analista_id
  ),
  nucleo as (
    select
      coalesce(sum(nv.divisor), 0)::int as divisor,
      coalesce(sum(nv.referidos_recibidos), 0)::int as referidos_recibidos,
      coalesce(sum(nv.cierres_no_referidos), 0)::int as cierres_no_referidos,
      coalesce(sum(nv.cierres_referidos), 0)::int as cierres_referidos,
      coalesce(sum(nv.operaciones), 0)::int as operaciones,
      coalesce(sum(nv.numerador), 0)::numeric as numerador
    from nucleo_vendedor nv
  ),
  -- Sonda de paridad: cuando el rango es un mes exacto, este recomputo debe
  -- coincidir EXACTAMENTE con el nucleo. Si no, el front avisa.
  -- Sonda de paridad: compara TODOS los terminos (divisor, ambos tipos de
  -- cierre y el numerador entero — que es donde vive la cartera), y declara
  -- cuantas filas comparo: sin filas la paridad no prueba nada y se dice
  -- (`cuadra` = null), en vez de dar un cero tranquilizador y vacuo.
  comparacion as (
    select nv.analista_id as a_nuevo, cm.analista_id as a_nucleo,
      abs(coalesce(nv.divisor, 0) - coalesce(cm.divisor, 0))
      + abs(coalesce(nv.cierres_no_referidos, 0) - coalesce(cm.cierres_no_referidos, 0))
      + abs(coalesce(nv.cierres_referidos, 0) - coalesce(cm.cierres_referidos, 0))
      + abs(coalesce(
          nv.numerador, 0)
        - coalesce(cm.numerador, 0)) as delta
    from nucleo_vendedor nv
    full outer join private.conversion_mensual_por_vendedor(
      v_ini, v_fin, true, null, v_factor
    ) cm on coalesce(cm.analista_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(nv.analista_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ),
  sonda_paridad as (
    select
      coalesce(sum(c.delta), 0) as desvio,
      count(*)::int as filas
    from comparacion c
  ),
  produccion as (
    select
      (select count(*)::int from crm.leads l
        where l.convertido_en >= v_ini and l.convertido_en < v_fin) as clientes,
      -- F1.3 (27/08): el enlace leads.contrato_id JAMAS se poblo (auditoria en
      -- prod: 0 enlaces historicos, S/ 0 eterno con capital real cerrado) y
      -- ningun flujo lo escribe. El camino VIVO es el perfil nacido del lead
      -- (leads.perfil_id = contratos.cliente_id) mas los cierres en
      -- cooperativas (crm.cierres_externos por lead, sin anulados). La columna
      -- contrato_id no se toca: en produccion no se borra nada.
      ((select count(*)::int from (select * from public.contratos where not es_demo) c
        where c.fecha_cierre_comercial >= p_desde and c.fecha_cierre_comercial <= p_hasta
          and exists (select 1 from crm.leads l where l.perfil_id = c.cliente_id))
       + (select count(*)::int from crm.cierres_externos ce
          where ce.anulado_en is null
            and (ce.creado_en at time zone 'America/Lima')::date between p_desde and p_hasta)) as contratos,
      (coalesce((select sum(k.monto) from private.capital_episodios(
           (p_desde::timestamp at time zone 'America/Lima'),
           ((p_hasta + 1)::timestamp at time zone 'America/Lima'), true, '{}'::uuid[]) k
         where k.moneda = 'PEN'
           and (   (k.tipo like 'contrato_%'
                    and exists (select 1 from crm.leads l where l.perfil_id = k.cliente_id))
                or k.tipo = 'cooperativa')), 0)) as capital_pen,
      (coalesce((select sum(k.monto) from private.capital_episodios(
           (p_desde::timestamp at time zone 'America/Lima'),
           ((p_hasta + 1)::timestamp at time zone 'America/Lima'), true, '{}'::uuid[]) k
         where k.moneda = 'USD'
           and (   (k.tipo like 'contrato_%'
                    and exists (select 1 from crm.leads l where l.perfil_id = k.cliente_id))
                or k.tipo = 'cooperativa')), 0)) as capital_usd,
      -- Sonda F1.3: convertidos del rango SIN rastro de capital (ni perfil ni
      -- cierre externo vigente). El hueco se declara; el front lo rotula.
      (select count(*)::int from crm.leads l
        where l.convertido_en >= v_ini and l.convertido_en < v_fin
          and l.perfil_id is null
          and not exists (select 1 from crm.cierres_externos ce
                          where ce.lead_id = l.id and ce.anulado_en is null)) as sin_rastro
  ),
  origenes as (
    select coalesce(origen, 'sin_origen') as origen,
      count(*)::int as leads,
      count(*) filter (where contactado)::int as contactados,
      count(*) filter (where reunion_agendada)::int as reuniones_agendadas,
      count(*) filter (where reunion_realizada)::int as reuniones_realizadas,
      count(*) filter (where cliente)::int as clientes,
      count(*) filter (where contrato)::int as contratos,
      count(*) filter (where etapa = 'descartado')::int as descartados,
      coalesce(sum(capital_lead_pen), 0) as capital_pen,
      coalesce(sum(capital_lead_usd), 0) as capital_usd
    from cohorte group by coalesce(origen, 'sin_origen')
  ),
  categorias as (
    select coalesce(categoria_interes, 'sin_categoria') as categoria,
      count(*)::int as leads,
      count(*) filter (where cliente)::int as clientes,
      count(*) filter (where contrato)::int as contratos,
      count(*) filter (where etapa = 'descartado')::int as descartados
    from cohorte group by coalesce(categoria_interes, 'sin_categoria')
  ),
  responsables_resumen as (
    select vb.vendedor_id,
      count(c.id)::int as leads,
      count(c.id) filter (where c.contactado)::int as contactados,
      count(c.id) filter (where c.reunion_realizada)::int as reuniones_realizadas,
      count(c.id) filter (where c.contrato)::int as contratos
    from vendedores_base vb
    left join cohorte c on c.vendedor_id = vb.vendedor_id
    group by vb.vendedor_id
  ),
  capital_responsables as (
    -- F1.3b: capital DEL RANGO por vendedor, por los caminos vivos — contratos
    -- del portal (fecha de cierre en el rango) de perfiles nacidos de SUS
    -- leads (el `in` dedupe si dos leads compartieran perfil) + sus cierres en
    -- coops del rango. Aqui muere la ULTIMA lectura del enlace jamas poblado.
    select vb.vendedor_id,
      (coalesce((select sum(k.monto) from private.capital_episodios(
           (p_desde::timestamp at time zone 'America/Lima'),
           ((p_hasta + 1)::timestamp at time zone 'America/Lima'), true, '{}'::uuid[]) k
         where k.moneda = 'PEN'
           and (   (k.tipo like 'contrato_%'
                    and k.cliente_id in (select l.perfil_id from crm.leads l
                                         where l.vendedor_id = vb.vendedor_id and l.perfil_id is not null))
                or (k.tipo = 'cooperativa' and k.analista_id = vb.vendedor_id))), 0)) as capital_pen,
      (coalesce((select sum(k.monto) from private.capital_episodios(
           (p_desde::timestamp at time zone 'America/Lima'),
           ((p_hasta + 1)::timestamp at time zone 'America/Lima'), true, '{}'::uuid[]) k
         where k.moneda = 'USD'
           and (   (k.tipo like 'contrato_%'
                    and k.cliente_id in (select l.perfil_id from crm.leads l
                                         where l.vendedor_id = vb.vendedor_id and l.perfil_id is not null))
                or (k.tipo = 'cooperativa' and k.analista_id = vb.vendedor_id))), 0)) as capital_usd
    from vendedores_base vb
  )
  select jsonb_build_object(
    'version', 1,
    'origen_filtrado', p_origen,
    'generado_en', now(),
    'periodo', jsonb_build_object(
      'desde', p_desde, 'hasta', p_hasta,
      'dias', (p_hasta - p_desde) + 1, 'zona', 'America/Lima'
    ),
    'nucleo', jsonb_build_object(
      'llegadas', (select count(*) from ep_flujo e where e.tipo = 'recibido'),
      'altas_manuales', (select count(*) from ep_flujo e
        where e.tipo = 'recibido' and not e.fue_referido and e.aporte_divisor = 0),
      'renovaciones', (select count(*) from ep_flujo e where e.tipo = 'operacion' and e.categoria = 'renovacion'),
      'upgrades', (select count(*) from ep_flujo e where e.tipo = 'operacion' and e.categoria = 'upgrade'),
      'aporte_cartera', (select coalesce(sum(e.aporte_numerador), 0) from ep_flujo e where e.tipo = 'operacion'),
      'base', 'llegada_unica',
      'atribucion', 'primer_analista',
      'peso_renovacion', v_factor,
      'incluye_cartera', true,
      'peso_referido', v_factor,
      'mes_peso', v_mes,
      'divisor', n.divisor,
      'referidos_recibidos', n.referidos_recibidos,
      'cierres_no_referidos', n.cierres_no_referidos,
      'cierres_referidos', n.cierres_referidos,
      'operaciones_cartera', n.operaciones,
      'numerador', n.numerador,
      -- DOS decimales, como el nucleo real: este numero DEBE poder compararse
      -- byte a byte con el heroe de HOY, no redondearse distinto.
      'conversion_pct', case when n.divisor > 0
        then round(100.0 * n.numerador / n.divisor, 2) end,
      'referidos_cierran_pct', case when n.referidos_recibidos > 0
        then round(100.0 * n.cierres_referidos / n.referidos_recibidos, 1) end
    ),
    'cosecha', jsonb_build_object(
      'base', 'alta',
      'madura_hasta', v_cosecha_fin,
      'leads', r.leads,
      'cerraron', r.clientes,
      'conversion_pct', case when r.leads > 0
        then round(100.0 * r.clientes / r.leads, 1) end
    ),
    'sondas', jsonb_build_object(
      'paridad_nucleo', sp.desvio,
      'paridad_filas', sp.filas,
      -- null = la sonda NO probo nada (rango sin mes, o sin una sola fila que
      -- comparar). Un true solo se afirma cuando hubo sustancia.
      'cuadra', case when sp.desvio is null or sp.filas = 0 then null
                     else sp.desvio = 0 end,
      'episodios_sin_origen', (
        select count(*)::int from ep_flujo e
        where e.tipo in ('recibido','cierre') and e.origen is null
      ),
      'cierres_anulados', (
        select count(*)::int from ep_flujo e
        where e.tipo = 'cierre' and e.anulado
      ),
      -- Cuanto divisor NO aparecera en `responsables`: episodios de analistas
      -- fuera del roster de vendedores activos (supervisores, bajas). Sin esto
      -- el desglose parece que no suma el total y nadie sabe por que.
      'divisor_fuera_del_roster', (
        select coalesce(sum(nv2.divisor), 0)::int
        from nucleo_vendedor nv2
        where nv2.analista_id is null
           or nv2.analista_id not in (select vb2.vendedor_id from vendedores_base vb2)
      ),
      -- Numerador que tampoco aparecera en `responsables`, por la misma razon
      -- que el divisor: analistas con cierres/cartera fuera del roster.
      'numerador_fuera_del_roster', (
        select coalesce(sum(
          nv3.numerador
        ), 0)
        from nucleo_vendedor nv3
        where nv3.analista_id is null
           or nv3.analista_id not in (select vb3.vendedor_id from vendedores_base vb3)
      ),
      -- Leads que la ficha da por convertidos pero SIN cierre elegible (o con
      -- el cierre anulado) en el ledger: el desacuerdo entre las dos verdades,
      -- medido en vez de tapado. Nombre explicito: «elegible», no «cierre».
      'cohorte_convertidos_sin_cierre_elegible', (
        select count(*)::int from cohorte c2
        where (c2.perfil_id is not null or c2.etapa = 'convertido')
          and c2.id not in (select ec2.lead_id from ep_cosecha ec2)
      ),
      -- El desacuerdo INVERSO: cierre elegible cuyo lead no figura convertido
      -- en su ficha. Sin esta, la sonda solo miraba en una direccion.
      'cierres_sin_ficha_convertida', (
        select count(*)::int from cohorte c3
        where c3.id in (select ec3.lead_id from ep_cosecha ec3)
          and c3.perfil_id is null and c3.etapa is distinct from 'convertido'
      ),
      -- Leads cuyo origen en la FICHA no coincide con el del ledger: mientras
      -- sea 0, rotular `peso_en_nucleo` sobre la fila de origen es seguro; si
      -- sube, la barra «Referido» de la ficha y la del nucleo hablan de
      -- poblaciones distintas (aviso de F3).
      'origen_ficha_distinto_del_ledger', (
        select count(*)::int
        from cohorte c4
        join (
          select e4.lead_id, bool_or(e4.fue_referido) as ref_ledger
          from ep_flujo e4 where e4.tipo = 'recibido' group by e4.lead_id
        ) l4 on l4.lead_id = c4.id
        where (c4.origen = 'referido') is distinct from l4.ref_ledger
      ),
      -- Operaciones de cartera contadas cuya fecha cae FUERA del rango pedido
      -- (solo puede pasar con fechas futuras dentro del mes en curso). NO se
      -- descuentan: el heroe de HOY las cuenta igual y la paridad manda; se
      -- DECLARAN para que F3 avise.
      'cartera_fuera_del_rango', (
        select count(*)::int from ep_flujo e
        where e.tipo = 'operacion'
          and (e.fecha_numerador at time zone 'America/Lima')::date not between p_desde and p_hasta
      ),
      -- F1.3b (hallazgo MEDIO-1 del auditor): un cliente puede volver como
      -- lead NUEVO de OTRO vendedor (los unicos de leads excluyen convertido y
      -- la edge reutiliza el perfil por DNI). Si pasa, su capital de portal
      -- cuenta ENTERO para ambos vendedores y el desglose suma mas que el
      -- total. Hoy es 0 (medido 27/08); esta sonda lo vigila para siempre y
      -- el front avisa si sube.
      'perfiles_con_leads_de_varios_vendedores', (
        select count(*)::int from (
          select l2.perfil_id
          from crm.leads l2
          where l2.perfil_id is not null and l2.vendedor_id is not null
          group by l2.perfil_id
          having count(distinct l2.vendedor_id) > 1
        ) dobles
      )
    ),
    'cohorte', jsonb_build_object(
      'leads', r.leads, 'asignados', r.asignados, 'contactados', r.contactados,
      'reuniones_agendadas', r.reuniones_agendadas,
      'reuniones_realizadas', r.reuniones_realizadas,
      'propuestas', r.propuestas, 'clientes', r.clientes,
      'contratos', r.contratos, 'descartados', r.descartados,
      'conversion_clientes_pct', case when r.leads > 0 then round(100.0 * r.clientes / r.leads, 1) end,
      'conversion_contratos_pct', case when r.leads > 0 then round(100.0 * r.contratos / r.leads, 1) end,
      'conversion_resueltos_pct', case when r.clientes + r.descartados > 0
        then round(100.0 * r.clientes / (r.clientes + r.descartados), 1) end
    ),
    'produccion', jsonb_build_object(
      'clientes', p.clientes, 'contratos', p.contratos,
      'capital_pen', p.capital_pen, 'capital_usd', p.capital_usd,
      'sin_rastro', p.sin_rastro
    ),
    'embudo', jsonb_build_array(
      jsonb_build_object('etapa','leads','cantidad',r.leads,'pct_anterior',case when r.leads > 0 then 100 else null end,'pct_total',case when r.leads > 0 then 100 else null end),
      jsonb_build_object('etapa','contactados','cantidad',r.contactados,'pct_anterior',case when r.leads > 0 then round(100.0*r.contactados/r.leads,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.contactados/r.leads,1) end),
      jsonb_build_object('etapa','reuniones_agendadas','cantidad',r.reuniones_agendadas,'pct_anterior',case when r.contactados > 0 then round(100.0*r.reuniones_agendadas/r.contactados,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.reuniones_agendadas/r.leads,1) end),
      jsonb_build_object('etapa','reuniones_realizadas','cantidad',r.reuniones_realizadas,'pct_anterior',case when r.reuniones_agendadas > 0 then round(100.0*r.reuniones_realizadas/r.reuniones_agendadas,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.reuniones_realizadas/r.leads,1) end),
      jsonb_build_object('etapa','propuestas','cantidad',r.propuestas,'pct_anterior',case when r.reuniones_realizadas > 0 then round(100.0*r.propuestas/r.reuniones_realizadas,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.propuestas/r.leads,1) end),
      jsonb_build_object('etapa','clientes','cantidad',r.clientes,'pct_anterior',case when r.propuestas > 0 then round(100.0*r.clientes/r.propuestas,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.clientes/r.leads,1) end),
      jsonb_build_object('etapa','contratos','cantidad',r.contratos,'pct_anterior',case when r.clientes > 0 then round(100.0*r.contratos/r.clientes,1) end,'pct_total',case when r.leads > 0 then round(100.0*r.contratos/r.leads,1) end)
    ),
    'origenes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'origen', o.origen, 'leads', o.leads, 'contactados', o.contactados,
        'reuniones_agendadas', o.reuniones_agendadas,
        'reuniones_realizadas', o.reuniones_realizadas,
        'clientes', o.clientes, 'contratos', o.contratos, 'descartados', o.descartados,
        'conversion_clientes_pct', case when o.leads > 0 then round(100.0*o.clientes/o.leads,1) end,
        'conversion_contratos_pct', case when o.leads > 0 then round(100.0*o.contratos/o.leads,1) end,
        'conversion_resueltos_pct', case when o.clientes+o.descartados > 0 then round(100.0*o.clientes/(o.clientes+o.descartados),1) end,
        -- D6: el referido NO pesa 1 en el nucleo. Viaja el peso para que la
        -- barra se pueda rotular sin recalcular nada (F3).
        'peso_en_nucleo', case when o.origen = 'referido' then v_factor else 1 end,
        'fuera_del_divisor_del_nucleo', o.origen = 'referido',
        'capital_pen', o.capital_pen, 'capital_usd', o.capital_usd
      ) order by o.contratos desc, o.clientes desc, o.leads desc, o.origen) from origenes o
    ), '[]'::jsonb),
    'categorias', coalesce((
      select jsonb_agg(jsonb_build_object(
        'categoria', c.categoria, 'leads', c.leads, 'clientes', c.clientes,
        'contratos', c.contratos, 'descartados', c.descartados,
        'conversion_pct', case when c.leads > 0 then round(100.0*c.contratos/c.leads,1) end
      ) order by c.contratos desc, c.leads desc, c.categoria) from categorias c
    ), '[]'::jsonb),
    'responsables', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vendedor_id', rr.vendedor_id,
        'leads', rr.leads,
        'contactados', rr.contactados,
        'reuniones_realizadas', rr.reuniones_realizadas,
        'clientes', rr.contratos,
        'conversion_pct', case when rr.leads > 0 then round(100.0*rr.contratos/rr.leads,1) end,
        -- Cifra principal por vendedor (nucleo): la MISMA que Ranking y Metas.
        'nucleo_divisor', coalesce(nv.divisor, 0),
        'nucleo_numerador', coalesce(
          nv.numerador, 0),
        'nucleo_conversion_pct', case when coalesce(nv.divisor, 0) > 0
          then round(100.0 * nv.numerador / nv.divisor, 2) end,
        'capital_pen', cr.capital_pen,
        'capital_usd', cr.capital_usd,
        'tendencia_semanal', coalesce((
          select jsonb_agg(jsonb_build_object(
            'semana', semanal.semana,
            'desde', semanal.desde,
            'hasta', semanal.hasta,
            'leads', semanal.leads,
            'clientes', semanal.clientes,
            'conversion_pct', case when semanal.leads > 0
              then round(100.0*semanal.clientes/semanal.leads,1) end
          ) order by semanal.semana)
          from (
            select gs.semana_indice + 1 as semana,
              p_desde + (gs.semana_indice * 7) as desde,
              least(p_hasta, p_desde + (gs.semana_indice * 7) + 6) as hasta,
              count(c.id)::int as leads,
              count(c.id) filter (where c.contrato)::int as clientes
            from generate_series(0, ((p_hasta - p_desde) / 7)) as gs(semana_indice)
            left join cohorte c on c.vendedor_id = rr.vendedor_id
              and (c.creado_en at time zone 'America/Lima')::date >= p_desde + (gs.semana_indice * 7)
              and (c.creado_en at time zone 'America/Lima')::date <= least(p_hasta, p_desde + (gs.semana_indice * 7) + 6)
            group by gs.semana_indice
          ) semanal
        ), '[]'::jsonb)
      ) order by rr.contratos desc, rr.leads desc, rr.vendedor_id)
      from responsables_resumen rr
      join capital_responsables cr on cr.vendedor_id = rr.vendedor_id
      left join nucleo_vendedor nv on nv.analista_id = rr.vendedor_id
    ), '[]'::jsonb)
  ) into v_payload
  from resumen r cross join produccion p cross join nucleo n cross join sonda_paridad sp;

  return v_payload;
end;
$function$;

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
  v_mes_actual date := date_trunc('month', v_hoy)::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_cosecha_fin timestamptz;
  v_mes date;
  v_factor numeric;
  v_periodo date;
  v_es_mes_historico boolean := false;
  v_cerrado boolean := false;
  v_meta_periodo_id uuid;
  v_revision integer;
  v_cerrado_en timestamptz;
  v_cierre_automatico boolean;
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

  -- 3) Ambito vigente por defecto. Solo un mes CERRADO lo sustituye por el
  -- ambito sellado; un historico aun abierto usa el mismo recorte vigente que
  -- cumplimiento_metas_fn durante la ventana de ajuste.
  v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
  v_visibles := case when v_global then '{}'::uuid[]
                     else array(select private.vendedor_ids_visibles(v_uid)) end;

  v_ini := p_desde::timestamp at time zone 'America/Lima';
  v_fin := (p_hasta + 1)::timestamp at time zone 'America/Lima';

  -- La cosecha madura hasta hoy: un lead que entro en el rango puede cerrar
  -- despues, y esa maduracion es el sentido de la lectura por cosecha.
  v_cosecha_fin := greatest(v_fin, v_ahora);

  v_mes := date_trunc('month', p_hasta)::date;
  v_factor := private.peso_referido_conversion(v_mes);

  -- Identifica la foto mensual del roster; los rangos parciales también
  -- contienen cartera, siempre acotada por la fecha efectiva de operación.
  v_periodo := case
    when p_desde = date_trunc('month', p_desde)::date
     and date_trunc('month', p_hasta)::date = date_trunc('month', p_desde)::date
     and (p_hasta = (date_trunc('month', p_desde) + interval '1 month' - interval '1 day')::date
          or p_hasta = v_hoy)
    then p_desde
  end;

  -- Solo un mes calendario ANTERIOR cambia de poblacion. Un rango libre y el
  -- mes actual conservan la semantica vigente de roster activo.
  v_es_mes_historico := v_periodo is not null and v_periodo < v_mes_actual;

  -- Para cualquier mes calendario (historico o el vigente) se publica el mismo
  -- token que conversion/cumplimiento. Un rango libre no finge tener revision.
  if v_periodo is not null then
    select pc.meta_revision, pc.cerrado_en, pc.automatico
      into v_revision, v_cerrado_en, v_cierre_automatico
    from crm.periodos_cerrados pc
    where pc.periodo = v_periodo;

    if found then
      v_cerrado := true;
    else
      v_cerrado := false;
      select mp.id, mp.revision into v_meta_periodo_id, v_revision
      from crm.meta_periodos mp
      where mp.periodo = v_periodo
      order by mp.revision desc
      limit 1;
      v_revision := coalesce(v_revision, 0);
    end if;
  end if;

  if v_es_mes_historico and v_cerrado and not v_global then
    -- El ambito de los episodios tambien debe ser el SELLADO. Cambiar solo
    -- las filas del roster mostraria al vendedor historico con ceros.
    select coalesce(
      array_agg(f.vendedor_id order by f.vendedor_id), '{}'::uuid[]
    ) into v_visibles
    from private.cierre_mes_visible(v_periodo, v_uid) f;
  end if;

  with roster as materialized (
    -- Mes sellado: quien estaba en la foto, con el supervisor de ese mes. No se
    -- vuelve a preguntar si hoy sigue activo o conserva rol de vendedor.
    select f.vendedor_id
    from private.cierre_mes_visible(v_periodo, v_uid) f
    where v_es_mes_historico and v_cerrado

    union all

    -- Mes historico aun abierto: ultima publicacion mensual, exactamente la
    -- poblacion que cumplimiento_metas_fn devuelve durante el ajuste.
    select mv.vendedor_id
    from crm.metas_vendedor mv
    where v_es_mes_historico
      and not v_cerrado
      and mv.meta_periodo_id = v_meta_periodo_id
      and (v_global or mv.vendedor_id = any(v_visibles))

    union all

    -- Mes actual y rangos libres: comportamiento anterior, sin cambios.
    select e.perfil_id as vendedor_id
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where not v_es_mes_historico
      and e.rol_crm = 'vendedor'
      and e.activo is true
      and p.activo is true
      and (v_global or e.perfil_id = any(v_visibles))
  ),
  -- TABLA-BASE, ya recortada al ambito del que pregunta. Para un cierre, el
  -- array v_visibles fue sustituido por los vendedores de su foto.
  ep_flujo as materialized (
    select e.* from private.conversion_episodios(
      v_ini, v_fin, v_periodo, v_global, v_visibles, v_factor
    ) e
  ),
  -- Esta pierna va GLOBAL a proposito. `cohorte` conserva el primer analista
  -- mientras el ledger acredita a quien lo cerro. El conjunto no
  -- sale al payload; solo prueba cierres de leads ya recortados en `cohorte`.
  ep_cosecha as materialized (
    select distinct e.lead_id
    from private.conversion_episodios(
      v_ini, v_cosecha_fin, null::date, true, '{}'::uuid[], v_factor
    ) e
    where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.lead_id is not null
  ),
  cohorte as materialized (
    select e.lead_id, e.analista_id as vendedor_id,
      (e.lead_id in (select ec.lead_id from ep_cosecha ec)) as contrato
    from ep_flujo e
    where e.tipo = 'recibido' and e.analista_id is not null
  ),
  responsables_resumen as (
    select r.vendedor_id,
      count(c.lead_id)::int as leads,
      count(c.lead_id) filter (where c.contrato)::int as clientes
    from roster r
    left join cohorte c on c.vendedor_id = r.vendedor_id
    group by r.vendedor_id
  ),
  nucleo_vendedor as (
    select e.analista_id,
      coalesce(sum(e.aporte_divisor), 0)::int as divisor,
      count(*) filter (where e.tipo = 'recibido' and e.fue_referido)::int as referidos_recibidos,
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and not e.fue_referido)::int as cierres_no_referidos,
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.fue_referido)::int as cierres_referidos,
      count(*) filter (where e.tipo = 'operacion')::int as operaciones,
      coalesce(sum(e.aporte_numerador), 0)::numeric as numerador
    from ep_flujo e
    group by e.analista_id
  ),
  comparacion as (
    select
      abs(coalesce(nv.divisor, 0) - coalesce(cm.divisor, 0))
      + abs(coalesce(nv.cierres_no_referidos, 0) - coalesce(cm.cierres_no_referidos, 0))
      + abs(coalesce(nv.cierres_referidos, 0) - coalesce(cm.cierres_referidos, 0))
      + abs(coalesce(
          nv.numerador, 0)
        - coalesce(cm.numerador, 0)) as delta
    from nucleo_vendedor nv
    full outer join private.conversion_mensual_por_vendedor(
      v_ini, v_fin, v_global, v_visibles, v_factor
    ) cm on coalesce(cm.analista_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(nv.analista_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ),
  sonda_paridad as (
    select
      coalesce(sum(c.delta), 0) as desvio,
      count(*)::int as filas
    from comparacion c
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'alcance', case when v_global then 'global' else 'equipo' end,
    'revision', case when v_periodo is null then null else v_revision end,
    'cierre', case
      when v_periodo is null then null
      when v_cerrado then jsonb_build_object(
        'cerrado', true,
        'cerrado_en', v_cerrado_en,
        'automatico', v_cierre_automatico
      )
      else jsonb_build_object('cerrado', false)
    end,
    'periodo', jsonb_build_object(
      'desde', p_desde,
      'hasta', p_hasta,
      'dias', (p_hasta - p_desde) + 1,
      'zona', 'America/Lima'
    ),
    'nucleo', jsonb_build_object(
      'base', 'llegada_unica',
      'atribucion', 'primer_analista',
      'peso_renovacion', v_factor,
      'incluye_cartera', true,
      'peso_referido', v_factor,
      'mes_peso', v_mes
    ),
    'sondas', jsonb_build_object(
      'paridad_nucleo', sp.desvio,
      'paridad_filas', sp.filas,
      'cuadra', case when sp.desvio is null or sp.filas = 0 then null
                     else sp.desvio = 0 end,
      'divisor_fuera_del_roster', (
        select coalesce(sum(nv2.divisor), 0)::int
        from nucleo_vendedor nv2
        where nv2.analista_id is null
           or nv2.analista_id not in (select r2.vendedor_id from roster r2)
      ),
      'numerador_fuera_del_roster', (
        select coalesce(sum(
          nv3.numerador
        ), 0)
        from nucleo_vendedor nv3
        where nv3.analista_id is null
           or nv3.analista_id not in (select r3.vendedor_id from roster r3)
      ),
      'cierres_anulados', (
        select count(*)::int from ep_flujo e where e.tipo = 'cierre' and e.anulado
      ),
      'clientes_acreditados_a_otro_dueno', (
        select count(*)::int
        from cohorte c
        join crm.lead_asignaciones la on la.lead_id = c.lead_id
        where c.contrato
          and la.resultado = 'convertido'
          and la.analista_id is distinct from c.vendedor_id
      )
    ),
    'responsables', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'vendedor_id', rr.vendedor_id,
          'leads', rr.leads,
          'clientes', rr.clientes,
          'conversion_pct', case when rr.leads > 0
            then round(100.0 * rr.clientes / rr.leads, 1) end,
          'nucleo_divisor', coalesce(nv.divisor, 0),
          'nucleo_numerador', coalesce(
            nv.numerador, 0),
          'nucleo_conversion_pct', case when coalesce(nv.divisor, 0) > 0
            then round(100.0 * nv.numerador / nv.divisor, 2) end
        )
        order by rr.clientes desc, rr.leads desc, rr.vendedor_id
      )
      from responsables_resumen rr
      left join nucleo_vendedor nv on nv.analista_id = rr.vendedor_id
    ), '[]'::jsonb)
  ) into v_payload
  from sonda_paridad sp;

  -- Un roster mensual ya fue validado por su propia fuente. Volver a filtrarlo
  -- por el rol ACTUAL borraria precisamente a las bajas historicas. Rangos
  -- libres y mes actual conservan la defensa previa.
  if v_es_mes_historico then
    return v_payload;
  end if;

  return private.filtrar_desglose_sujetos_crm(
    v_payload, 'responsables', 'vendedor_id', array['vendedor']
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.metricas_distribucion_leads_v3_core(p_desde date, p_hasta date, p_ahora timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_base jsonb;
  v_hoy date := (p_ahora at time zone 'America/Lima')::date;
  v_ini timestamptz := p_desde::timestamp at time zone 'America/Lima';
  v_fin timestamptz := (p_hasta + 1)::timestamp at time zone 'America/Lima';
  v_mes date := date_trunc('month', p_hasta)::date;
  v_factor numeric;
  v_periodo date;
  v_nucleo jsonb;
  v_div_total integer;
  v_num_total numeric;
  v_ref_total integer;
  v_div_sin_analista integer;
  v_num_sin_analista numeric;
  v_anulados integer;
  v_sin_origen integer;
  v_paridad numeric;
  v_paridad_filas integer;
  v_analistas jsonb;
  v_usd_conv integer;
  v_usd_desc integer;
  v_sin_ficha integer;
begin
  v_base := private.metricas_distribucion_leads_v2_core(p_desde, p_hasta, p_ahora);
  v_factor := private.peso_referido_conversion(v_mes);

  -- (auditor RLS, objecion 10) Si el motor v2 renombrara las claves de las
  -- que esta funcion LEE, el coalesce de la punteria fabricaria ceros en
  -- silencio — exactamente lo que este plan vino a matar. Falla ruidosa.
  if exists (
    select 1 from jsonb_array_elements(v_base->'analistas') fila(elemento)
    where (fila.elemento#>'{pen,cohorte}' ? 'convertidos') is distinct from true
       or (fila.elemento#>'{pen,cohorte}' ? 'descartados') is distinct from true
       or (fila.elemento->'usd_no_segmentado' ? 'convertidos') is distinct from true
       or (fila.elemento->'usd_no_segmentado' ? 'descartados') is distinct from true
  ) or exists (
    select 1 from jsonb_array_elements(v_base->'analistas') fila(elemento),
                  jsonb_array_elements(fila.elemento#>'{pen,rangos}') rango(elemento)
    where (rango.elemento->'cohorte' ? 'convertidos') is distinct from true
       or (rango.elemento->'cohorte' ? 'descartados') is distinct from true
  ) or (v_base->'resumen' ? 'convertidos_pen') is distinct from true
    or (v_base->'resumen' ? 'descartados_pen') is distinct from true then
    raise exception 'Contrato interno v2 inesperado: faltan las claves de conversion'
      using errcode = '55000';
  end if;

  -- El núcleo admite también rangos parciales y aplica su ventana a cartera.
  v_periodo := case
    when p_desde = date_trunc('month', p_desde)::date
     and date_trunc('month', p_hasta)::date = date_trunc('month', p_desde)::date
     and (p_hasta = (date_trunc('month', p_desde) + interval '1 month' - interval '1 day')::date
          or p_hasta = v_hoy)
    then p_desde
  end;

  -- Esta pantalla solo la ve gerencia o un lector global (el gate vive en
  -- `..._autorizada`, aguas arriba), asi que la tabla-base va SIEMPRE global.
  with ep as materialized (
    select e.* from private.conversion_episodios(
      v_ini, v_fin, v_periodo, true, '{}'::uuid[], v_factor
    ) e
  ),
  nv as (
    select e.analista_id,
      coalesce(sum(e.aporte_divisor), 0)::int as divisor,
      count(*) filter (where e.tipo = 'recibido' and e.fue_referido)::int as referidos_recibidos,
      count(distinct e.lead_id) filter (
        where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and not e.fue_referido)::int as cierres_no_referidos,
      count(distinct e.lead_id) filter (
        where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.fue_referido)::int as cierres_referidos,
      count(*) filter (where e.tipo = 'operacion')::int as operaciones,
      coalesce(sum(e.aporte_numerador), 0)::numeric as numerador
    from ep e
    group by e.analista_id
  ),
  agg as (
    select
      coalesce(jsonb_object_agg(
        nv.analista_id::text,
        jsonb_build_object(
          'nucleo_divisor', nv.divisor,
          'nucleo_referidos_recibidos', nv.referidos_recibidos,
          'nucleo_numerador',
            nv.numerador,
          'nucleo_conversion_pct', case when nv.divisor > 0
            then round(100.0 * nv.numerador / nv.divisor, 2) end
        )
      ) filter (where nv.analista_id is not null), '{}'::jsonb) as mapa,
      coalesce(sum(nv.divisor), 0)::int as div_total,
      coalesce(sum(nv.numerador), 0) as num_total,
      coalesce(sum(nv.referidos_recibidos), 0)::int as ref_total,
      coalesce(sum(nv.divisor) filter (where nv.analista_id is null), 0)::int as div_sin,
      coalesce(sum(
        nv.numerador
      ) filter (where nv.analista_id is null), 0) as num_sin
    from nv
  ),
  extras as (
    select
      count(*) filter (where e.tipo = 'cierre' and e.anulado)::int as anulados,
      count(*) filter (where e.tipo = 'recibido' and e.origen is null)::int as sin_origen
    from ep e
  ),
  -- Sonda de paridad contra el nucleo REAL (el que sirve HOY/Metas). Solo se
  -- calcula cuando va a valer algo: con `v_periodo` NULL el resultado se
  -- descarta y esta pierna es la mas cara.
  comparacion as (
    select
      abs(coalesce(nv.divisor, 0) - coalesce(cm.divisor, 0))
      + abs(coalesce(nv.cierres_no_referidos, 0) - coalesce(cm.cierres_no_referidos, 0))
      + abs(coalesce(nv.cierres_referidos, 0) - coalesce(cm.cierres_referidos, 0))
      + abs(coalesce(
          nv.numerador, 0)
        - coalesce(cm.numerador, 0)) as delta
    from nv
    -- `=` y no `is not distinct from`: PG no admite este ultimo en un FULL
    -- JOIN (no es hash/merge-joinable). Es seguro porque ninguna de las dos
    -- relaciones puede traer `analista_id` NULL en el lado que importa; si eso
    -- cambiara, la sonda gritaria (paridad <> 0) en vez de callarse.
    full outer join private.conversion_mensual_por_vendedor(
      v_ini, v_fin, true, '{}'::uuid[], v_factor
    ) cm on coalesce(cm.analista_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(nv.analista_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ),
  sonda as (
    select
      coalesce(sum(c.delta), 0) as desvio,
      count(*)::int as filas
    from comparacion c
  )
  select agg.mapa, agg.div_total, agg.num_total, agg.ref_total, agg.div_sin, agg.num_sin,
         extras.anulados, extras.sin_origen, sonda.desvio, sonda.filas
    into v_nucleo, v_div_total, v_num_total, v_ref_total, v_div_sin_analista, v_num_sin_analista,
         v_anulados, v_sin_origen, v_paridad, v_paridad_filas
    from agg cross join extras cross join sonda;

  -- ── Por analista: punteria PEN/USD, sus rangos, y su cifra del nucleo ─────
  select coalesce(jsonb_agg(
    jsonb_set(
      fila.elemento || jsonb_build_object(
        'conversion',
        jsonb_build_object(
          'pen', private.conversion_punteria(
            (fila.elemento#>>'{pen,cohorte,convertidos}')::int,
            (fila.elemento#>>'{pen,cohorte,descartados}')::int),
          'usd', private.conversion_punteria(
            (fila.elemento#>>'{usd_no_segmentado,convertidos}')::int,
            (fila.elemento#>>'{usd_no_segmentado,descartados}')::int)
        )
        || coalesce(v_nucleo->(fila.elemento->>'analista_id'), jsonb_build_object(
             'nucleo_divisor', 0,
             'nucleo_referidos_recibidos', 0,
             'nucleo_numerador', 0::numeric,
             'nucleo_conversion_pct', null
           ))
      ),
      '{pen,rangos}',
      rr.rangos,
      false
    ) order by fila.orden
  ), '[]'::jsonb)
  into v_analistas
  from jsonb_array_elements(v_base->'analistas') with ordinality as fila(elemento, orden)
  cross join lateral (
    select coalesce(jsonb_agg(
      rango.elemento || jsonb_build_object(
        'conversion', private.conversion_punteria(
          (rango.elemento#>>'{cohorte,convertidos}')::int,
          (rango.elemento#>>'{cohorte,descartados}')::int)
      ) order by rango.orden
    ), '[]'::jsonb) as rangos
    from jsonb_array_elements(fila.elemento#>'{pen,rangos}') with ordinality as rango(elemento, orden)
  ) rr;

  v_base := jsonb_set(v_base, '{analistas}', v_analistas, false);

  -- (auditor RLS, objecion 9) Los totales nucleo_* del resumen suman TODOS
  -- los analistas del ledger; el array `analistas` solo trae a quien sigue en
  -- el roster de vendedores/supervisores. Un ex-vendedor reenrolado conserva
  -- su historia: cuenta en el resumen y no tiene ficha. Esta sonda lo dice.
  select count(*) into v_sin_ficha
    from jsonb_object_keys(v_nucleo) k
   where k not in (
     select fila.elemento->>'analista_id'
       from jsonb_array_elements(v_base->'analistas') fila(elemento));

  -- ── Resumen: lo mismo, a nivel de toda la casa ────────────────────────────
  -- El USD del resumen lo suma HOY el navegador (`cierresUsd`, la suma en
  -- cliente de `distribucion-leads-gerencia.tsx:341-345`). Se suma aqui, de los
  -- MISMOS elementos, para que el numero sea identico y el front deje de
  -- hacerlo.
  select
    coalesce(sum((elemento#>>'{usd_no_segmentado,convertidos}')::int), 0),
    coalesce(sum((elemento#>>'{usd_no_segmentado,descartados}')::int), 0)
  into v_usd_conv, v_usd_desc
  from jsonb_array_elements(v_base->'analistas') as fila(elemento);

  v_base := jsonb_set(
    v_base,
    '{resumen}',
    (v_base->'resumen') || jsonb_build_object(
      'conversion', jsonb_build_object(
        'pen', private.conversion_punteria(
          (v_base#>>'{resumen,convertidos_pen}')::int,
          (v_base#>>'{resumen,descartados_pen}')::int),
        'usd', private.conversion_punteria(v_usd_conv, v_usd_desc),
        'nucleo_divisor', v_div_total,
        'nucleo_referidos_recibidos', v_ref_total,
        'nucleo_numerador', v_num_total,
        'nucleo_conversion_pct', case when v_div_total > 0
          then round(100.0 * v_num_total / v_div_total, 2) end
      )
    ),
    false
  );

  v_base := jsonb_set(v_base, '{version}', '3'::jsonb, false);
  v_base := jsonb_set(
    v_base,
    '{alcances}',
    (v_base->'alcances') || jsonb_build_object(
      'conversion_punteria', 'CERRADOS_ENTRE_RESUELTOS',
      'conversion_nucleo', 'LLEGADAS_UNICAS_PRIMER_ANALISTA',
      'conversion_incluye_cartera', true
    ),
    false
  );

  -- ── Sondas: para que F3 pueda OCULTAR un numero en vez de fabricar un cero ─
  v_base := jsonb_set(
    v_base,
    '{sondas}',
    jsonb_build_object(
      'peso_referido', v_factor,
      'mes_peso', v_mes,
      'paridad_nucleo', v_paridad,
      'paridad_filas', v_paridad_filas,
      'cuadra', case when v_paridad is null or v_paridad_filas = 0 then null
                     else v_paridad = 0 end,
      -- Episodios que NO apareceran en `analistas` (analista nulo en la
      -- tabla-base): si esto crece, el resumen y la suma de fichas dejan de
      -- cuadrar y hay que saberlo.
      'divisor_sin_analista', v_div_sin_analista,
      'numerador_sin_analista', v_num_sin_analista,
      'cierres_anulados', v_anulados,
      'episodios_sin_origen', v_sin_origen,
      'nucleo_sin_ficha', v_sin_ficha
    ),
    true
  );

  return v_base;
end;
$function$;

CREATE OR REPLACE FUNCTION crm.conversion_mensual_sin_cartera_fn(p_periodo date)
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
  v_alcance text;
  v_visibles uuid[];
  v_ahora timestamptz := now();
  v_mes_actual date := date_trunc('month', v_ahora at time zone 'America/Lima')::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_factor numeric;
  v_suelo timestamptz;
  v_suelo_mes date;
  v_medible boolean;
  v_motivo_no_medible text;
  v_motivo_roster text;
  v_meta_periodo_id uuid;
  v_es_historico_abierto boolean := false;
  v_payload jsonb;
  v_cierre crm.periodos_cerrados%rowtype;
begin
  -- 1) GATE EXPLICITO, ANTES DE TOCAR NINGUN DATO. Nunca RLS implicita: esta
  --    funcion es SECURITY DEFINER y las policies no se evaluan. ALLOWLIST, no
  --    «rol_crm is not null»: ese idioma (el de cumplimiento_metas_fn) dejaria
  --    pasar al COORDINADOR, que aqui esta denegado por contrato.
  --    Orden deliberado: un actor denegado recibe 42501 aunque el periodo sea
  --    basura, para que el codigo de error no funcione como oraculo.
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null
     or not coalesce(v_rol in ('vendedor', 'supervisor', 'gerencia') or v_lector, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- 2) Validacion del periodo.
  if p_periodo is null or p_periodo <> date_trunc('month', p_periodo)::date then
    raise exception 'Periodo invalido: debe ser el primer dia del mes'
      using errcode = '22023';
  end if;
  if p_periodo > v_mes_actual then
    raise exception 'Periodo invalido: el mes no puede ser futuro'
      using errcode = '22023';
  end if;

  v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
  v_alcance := case
    when v_global then 'global'
    when v_rol = 'supervisor' then 'equipo'
    else 'propio'
  end;

  -- 3) ¿MES CERRADO? Entonces se sirve la foto y no se calcula nada. Va aqui,
  --    despues del gate y de validar el periodo, para que un mes cerrado
  --    responda igual de fail-closed que uno abierto.
  select * into v_cierre from crm.periodos_cerrados pc where pc.periodo = p_periodo;
  if found then
    with visibles as (
      select f.* from private.cierre_mes_visible(p_periodo, v_uid) f
    ), fuera_foto as materialized (
      select e.value as fila
      from jsonb_array_elements(
        coalesce(v_cierre.cobertura->'fuera_ranking', '[]'::jsonb)
      ) e
      where v_global and e.value->'conversion' <> 'null'::jsonb
      union all
      select jsonb_build_object('conversion', v_cierre.cobertura->'conversion_sin_analista')
      where v_global and v_cierre.cobertura ? 'conversion_sin_analista'
    ), resumen as (
      -- El total suma la foto rankeable y el agregado empresarial congelado.
      -- Las identidades externas nunca se materializan como responsables.
      select
        count(*)::int as analistas,
        (coalesce(sum(v.divisor), 0)
          + coalesce((select sum((f.fila#>>'{conversion,divisor}')::int)
                      from fuera_foto f), 0))::int as divisor,
        (coalesce(sum(v.divisor_aproximado), 0)
          + coalesce((select sum((f.fila#>>'{conversion,divisor_aproximado}')::int)
                      from fuera_foto f), 0))::int as divisor_aproximado,
        (coalesce(sum(v.cierres_no_referidos), 0)
          + coalesce((select sum((f.fila#>>'{conversion,cierres_no_referidos}')::int)
                      from fuera_foto f), 0))::int as cierres_no_referidos,
        (coalesce(sum(v.cierres_referidos), 0)
          + coalesce((select sum((f.fila#>>'{conversion,cierres_referidos}')::int)
                      from fuera_foto f), 0))::int as cierres_referidos,
        (coalesce(sum(v.cierres_de_arrastre), 0)
          + coalesce((select sum((f.fila#>>'{conversion,cierres_de_arrastre}')::int)
                      from fuera_foto f), 0))::int as cierres_de_arrastre,
        (coalesce(sum(v.referidos_recibidos), 0)
          + coalesce((select sum((f.fila#>>'{conversion,referidos_recibidos}')::int)
                      from fuera_foto f), 0))::int as referidos_recibidos,
        (coalesce(sum(v.numerador), 0::numeric)
          + coalesce((select sum((f.fila#>>'{conversion,numerador}')::numeric)
                      from fuera_foto f), 0::numeric)) as numerador
      from visibles v
    ), motivos as (
      select e.key as motivo, sum(e.value::int)::int as n
      from (
        select v.divisor_por_motivo from visibles v
        union all
        select coalesce(f.fila#>'{conversion,divisor_por_motivo}', '{}'::jsonb)
        from fuera_foto f
      ) dm, jsonb_each_text(dm.divisor_por_motivo) e
      group by e.key
    )
    select jsonb_build_object(
      'version', 1,
      'generado_en', v_ahora,
      'alcance', v_alcance,
      'periodo', jsonb_build_object(
        'mes', pg_catalog.to_char(p_periodo, 'YYYY-MM'),
        'mes_nombre', private.etiqueta_mes_es(p_periodo),
        'anio', extract(year from p_periodo)::int,
        'zona', 'America/Lima',
        'desde', p_periodo::timestamp at time zone 'America/Lima',
        'hasta', (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima'
      ),
      'ponderacion', jsonb_build_object(
        'referido', v_cierre.ponderacion_referido,
        'renovacion', case when v_cierre.cobertura->>'modelo_conversion' = 'llegadas_v2'
          then v_cierre.ponderacion_referido else 1 end,
        'fuente', 'crm.conversion_pesos'
      ),
      -- La fuente indica la semántica sellada. Las fotos anteriores no se
      -- reescriben ni se hacen pasar por llegadas únicas.
      'fuentes', jsonb_build_object(
        'divisor', case when v_cierre.cobertura->>'modelo_conversion' = 'llegadas_v2'
          then 'crm.leads.creado_en' else 'crm.lead_asignaciones.asignado_en' end,
        'numerador', 'crm.lead_asignaciones.resultado_en',
        'referido', case when v_cierre.cobertura->>'modelo_conversion' = 'llegadas_v2'
          then 'crm.leads.origen' else 'crm.lead_asignaciones.origen' end
      ),
      -- LA CLAVE NUEVA. El front la usa para decir «cerrado el 10/09, ya no
      -- cambia»; un cliente viejo la ignora y no se entera de nada.
      'cierre', jsonb_build_object(
        'cerrado', true,
        'cerrado_en', v_cierre.cerrado_en,
        'automatico', v_cierre.automatico
      ),
      'cobertura', jsonb_build_object(
        'medible', coalesce((v_cierre.cobertura->>'medible')::boolean, false),
        'suelo_historico', v_cierre.cobertura->>'suelo_historico',
        'motivo_no_medible', v_cierre.cobertura->>'motivo_no_medible',
        'divisor_aproximado', (select r.divisor_aproximado from resumen r),
        'divisor_por_motivo', coalesce(
          (select jsonb_object_agg(m.motivo, m.n) from motivos m), '{}'::jsonb),
        -- La sonda de cierres sin episodio se calculaba sobre datos vivos; en un
        -- mes sellado no se recalcula (mentiria sobre el momento del sello) y se
        -- declara en cero, que es lo que la foto puede afirmar.
        'cierres_sin_episodio', 0,
        -- La producción de supervisores u otras identidades no rankeables se
        -- conserva en el total, pero no se convierte en una fila de analista.
        'fuera_de_roster', jsonb_build_object(
          'analistas', (select count(*)::int from fuera_foto f where f.fila->>'persona_id' is not null),
          'divisor', coalesce((select sum(
            (f.fila#>>'{conversion,divisor}')::int) from fuera_foto f), 0)::int,
          'cierres', coalesce((select sum(
            (f.fila#>>'{conversion,cierres_no_referidos}')::int
            + (f.fila#>>'{conversion,cierres_referidos}')::int
          ) from fuera_foto f), 0)::int,
          'numerador', coalesce((select sum(
            (f.fila#>>'{conversion,numerador}')::numeric
          ) from fuera_foto f), 0::numeric))
      ),
      'total', (
        select jsonb_build_object(
          'analistas', r.analistas,
          'divisor', r.divisor,
          'cierres_no_referidos', r.cierres_no_referidos,
          'cierres_referidos', r.cierres_referidos,
          'cierres_de_arrastre', r.cierres_de_arrastre,
          'referidos_recibidos', r.referidos_recibidos,
          'numerador', r.numerador,
          'conversion_pct', case when r.divisor > 0
            then round(100.0 * r.numerador / r.divisor, 2) end,
          'referidos_aporta_pct', case when r.divisor > 0
            then round(100.0 * v_cierre.ponderacion_referido * r.cierres_referidos / r.divisor, 2) end
        ) from resumen r),
      'responsables', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'vendedor_id', v.vendedor_id,
            'supervisor_id', v.supervisor_id,
            'divisor', v.divisor,
            'cierres_no_referidos', v.cierres_no_referidos,
            'cierres_referidos', v.cierres_referidos,
            'cierres_de_arrastre', v.cierres_de_arrastre,
            'numerador', v.numerador,
            'conversion_pct', v.conversion_pct,
            'estado', v.estado,
            'procedencia', v.procedencia,
            'referidos', jsonb_build_object(
              'recibidos', v.referidos_recibidos,
              'cerrados', v.cierres_referidos,
              'dados_de_alta', v.referidos_dados_de_alta,
              'aporta_pct', v.referidos_aporta_pct
            ),
            -- En un mes cerrado ya no queda nada pendiente de ese mes: lo que se
            -- pudo descontar se descontó al sellar, y lo que no, sigue vivo en
            -- el mes siguiente. Por eso `pendiente` es 0 y `aplicado` no.
            'ajuste', jsonb_build_object(
              'aplicado', v.ajuste_numerador,
              'pendiente', 0,
              'origenes', '[]'::jsonb)
          )
          order by v.conversion_pct desc nulls last,
                   v.numerador desc, v.divisor desc, v.vendedor_id
        )
        from visibles v
      ), '[]'::jsonb)
    ) into v_payload;

    -- ⚠️ SIN `filtrar_desglose_sujetos_crm`. Esa defensa descarta a quien hoy no
    -- sea vendedor, y sobre una foto de pago borraria justo a quien se fue del
    -- equipo — el caso que el sello congela el nombre para conservar.
    return v_payload;
  end if;

  -- 4) Mes ABIERTO. Si es historico durante la ventana de ajuste, manda la
  -- ultima publicacion de ESE mes; el vigente conserva el roster operativo.
  v_es_historico_abierto := p_periodo < v_mes_actual;
  if v_es_historico_abierto then
    select mp.id into v_meta_periodo_id
    from crm.meta_periodos mp
    where mp.periodo = p_periodo
    order by mp.revision desc
    limit 1;
  end if;

  v_visibles := case when v_global then '{}'::uuid[]
                     else array(select private.vendedor_ids_visibles(v_uid)) end;

  v_ini := p_periodo::timestamp at time zone 'America/Lima';
  v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';

  v_factor := private.peso_referido_conversion(p_periodo);

  select min(la.asignado_en)
    into v_suelo
  from crm.lead_asignaciones la
  where not la.aproximado;

  v_suelo_mes := date_trunc('month', v_suelo at time zone 'America/Lima')::date;

  if v_suelo is null then
    v_medible := false;
    v_motivo_no_medible := 'sin_ledger';
  elsif v_ini < v_suelo then
    v_medible := false;
    v_motivo_no_medible := case
      when p_periodo < v_suelo_mes then 'anterior_al_ledger'
      else 'mes_parcial'
    end;
  else
    v_medible := true;
    v_motivo_no_medible := null;
  end if;

  if v_alcance = 'propio'
     and not (
       (v_es_historico_abierto and exists (
         select 1 from crm.metas_vendedor mv
         where mv.meta_periodo_id = v_meta_periodo_id
           and mv.vendedor_id = v_uid
       ))
       or (not v_es_historico_abierto and exists (
         select 1 from private.roster_metas_vendedores() r
         where r.vendedor_id = v_uid
       ))
     ) then
    select vs.motivo
      into v_motivo_roster
    from private.vendedores_sin_supervisor() vs
    where vs.vendedor_id = v_uid;

    v_medible := false;
    v_motivo_no_medible := coalesce(v_motivo_roster, 'sin_supervisor');
  end if;

  with roster as materialized (
    select r.vendedor_id, r.supervisor_id
    from private.roster_metas_vendedores() r
    where not v_es_historico_abierto
      and (v_global or r.vendedor_id = any(v_visibles))

    union all

    select mv.vendedor_id, mv.supervisor_id
    from crm.metas_vendedor mv
    where v_es_historico_abierto
      and mv.meta_periodo_id = v_meta_periodo_id
      and (v_global or mv.vendedor_id = any(v_visibles))
  ),
  base as materialized (
    select cm.*
    from private.conversion_mensual_por_vendedor(
      v_ini, v_fin, v_global, v_visibles, v_factor
    ) cm
  ),
  alta_referidos as materialized (
    select l.creado_por as analista_id, count(*)::int as dados_de_alta
    from crm.leads l
    where l.origen = 'referido'
      and l.creado_en >= v_ini
      and l.creado_en < v_fin
      and l.creado_por is not null
      and (v_global or l.creado_por = any(v_visibles))
    group by l.creado_por
  ),
  pendientes as materialized (
    -- Lo que cada vendedor arrastra de meses YA CERRADOS: cierres anulados
    -- despues de pagar. Se descuenta aqui, en la LECTURA, y no dentro de
    -- `private.conversion_mensual_por_vendedor`: el cierre de mes ya lo aplica
    -- al saldar, y si viviera en el nucleo se descontaria dos veces.
    select ap.vendedor_id, ap.numerador as pendiente, ap.origenes
    from private.ajuste_pendiente_por_vendedor() ap
  ),
  filas as (
    select
      r.vendedor_id,
      r.supervisor_id,
      coalesce(b.divisor, 0) as divisor,
      coalesce(b.divisor_aproximado, 0) as divisor_aproximado,
      coalesce(b.divisor_por_motivo, '{}'::jsonb) as divisor_por_motivo,
      coalesce(b.cierres_no_referidos, 0) as cierres_no_referidos,
      coalesce(b.cierres_referidos, 0) as cierres_referidos,
      coalesce(b.cierres_de_arrastre, 0) as cierres_de_arrastre,
      -- NETO de lo que se le debe descontar, con suelo en cero. El bruto sigue
      -- siendo recuperable sumandole `ajuste_pendiente`.
      private.conversion_con_ajuste(b.numerador, pd.pendiente) as numerador,
      -- El porcentaje se RECALCULA sobre el neto: el que trae el nucleo es el
      -- del bruto y enseñarlo aqui contradiria al numerador de su propia fila.
      case when coalesce(b.divisor, 0) > 0
        then round(100.0 * private.conversion_con_ajuste(b.numerador, pd.pendiente)
                   / coalesce(b.divisor, 0), 2) end as conversion_pct,
      coalesce(pd.pendiente, 0::numeric) as ajuste_pendiente,
      coalesce(pd.origenes, '[]'::jsonb) as ajuste_origenes,
      coalesce(b.procedencia, '[]'::jsonb) as procedencia,
      coalesce(b.referidos_recibidos, 0) as referidos_recibidos,
      b.referidos_aporta_pct,
      coalesce(a.dados_de_alta, 0) as dados_de_alta
    from roster r
    left join base b on b.analista_id = r.vendedor_id
    left join alta_referidos a on a.analista_id = r.vendedor_id
    left join pendientes pd on pd.vendedor_id = r.vendedor_id
  ),
  fuera as (
    -- Quien produjo dentro del ambito pero NO esta en el roster: el que se dio
    -- de baja a mitad de mes, el supervisor con cartera propia, el vendedor
    -- sin supervisor. Sigue siendo un AGREGADO SIN IDENTIDAD (ningun uuid
    -- sale), pero desde D8 (Miguel, 27/08/2026) ademas de declararse en
    -- `cobertura.fuera_de_roster` se SUMA al total: por eso aqui se agregan
    -- tambien los desgloses que `resumen` necesita. BRUTO a proposito: el
    -- ajuste de meses ya pagados se descuenta por fila del roster
    -- (`pendientes`) y el ex-roster no tiene fila donde descontarlo.
    select
      count(b.analista_id)::int as analistas,
      coalesce(sum(b.divisor), 0)::int as divisor,
      coalesce(sum(b.cierres_no_referidos + b.cierres_referidos), 0)::int as cierres,
      coalesce(sum(b.numerador), 0::numeric) as numerador,
      coalesce(sum(b.divisor_aproximado), 0)::int as divisor_aproximado,
      coalesce(sum(b.cierres_no_referidos), 0)::int as cierres_no_referidos,
      coalesce(sum(b.cierres_referidos), 0)::int as cierres_referidos,
      coalesce(sum(b.cierres_de_arrastre), 0)::int as cierres_de_arrastre,
      coalesce(sum(b.referidos_recibidos), 0)::int as referidos_recibidos
    from base b
    where not exists (select 1 from roster r where r.vendedor_id = b.analista_id)
  ),
  motivos_totales as (
    -- D8: el desglose por motivo cubre TODO el divisor que el total cuenta —
    -- las filas del roster y las del agregado fuera de roster. Sin la segunda
    -- pierna, `divisor_por_motivo` dejaria de cuadrar con `total.divisor`.
    select e.key as motivo, sum(e.value::int)::int as n
    from (
      select f.divisor_por_motivo from filas f
      union all
      select coalesce(b.divisor_por_motivo, '{}'::jsonb)
      from base b
      where not exists (select 1 from roster r where r.vendedor_id = b.analista_id)
    ) dm, jsonb_each_text(dm.divisor_por_motivo) e
    group by e.key
  ),
  sonda as (
    select count(*)::int as cierres_sin_episodio
    from crm.leads l
    where l.etapa = 'convertido'
      and l.origen in ('landing', 'formulario', 'referido')
      and l.convertido_en >= v_ini
      and l.convertido_en < v_fin
      and (v_global
           or l.vendedor_id = any(v_visibles)
           or l.asignado_supervisor_id = any(v_visibles)
           or exists (
             select 1
             from crm.lead_asignaciones lv
             where lv.lead_id = l.id
               and lv.analista_id = any(v_visibles)
           ))
      and not exists (
        select 1
        from crm.lead_asignaciones la
        where la.lead_id = l.id
          and la.resultado = 'convertido'
          and coalesce(la.resultado_en, la.finalizado_en) >= v_ini
          and coalesce(la.resultado_en, la.finalizado_en) < v_fin
      )
  ),
  resumen as (
    -- D8 (Miguel, 27/08/2026): el total de empresa INCLUYE la produccion fuera
    -- de roster — el mismo agregado sin identidad que declara
    -- `cobertura.fuera_de_roster`. Con el agregado en cero el total queda
    -- identico al de antes. Quien sale del roster a mitad de mes cuenta aqui
    -- entero (el roster es estado ACTUAL, no historico): su mes se mueve al
    -- agregado y su fila desaparece de `responsables`; con esto el mes abierto
    -- dice lo mismo que dira su foto al sellarse, donde todo el que produjo
    -- entra con nombre (20260815003742, «no hay fuera de roster en una foto»).
    select
      count(*)::int as analistas,
      (coalesce(sum(f.divisor), 0)
        + (select fr.divisor from fuera fr))::int as divisor,
      (coalesce(sum(f.divisor_aproximado), 0)
        + (select fr.divisor_aproximado from fuera fr))::int as divisor_aproximado,
      (coalesce(sum(f.cierres_no_referidos), 0)
        + (select fr.cierres_no_referidos from fuera fr))::int as cierres_no_referidos,
      (coalesce(sum(f.cierres_referidos), 0)
        + (select fr.cierres_referidos from fuera fr))::int as cierres_referidos,
      (coalesce(sum(f.cierres_de_arrastre), 0)
        + (select fr.cierres_de_arrastre from fuera fr))::int as cierres_de_arrastre,
      (coalesce(sum(f.referidos_recibidos), 0)
        + (select fr.referidos_recibidos from fuera fr))::int as referidos_recibidos,
      (coalesce(sum(f.numerador), 0::numeric)
        + (select fr.numerador from fuera fr)) as numerador
    from filas f
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'alcance', v_alcance,
    'periodo', jsonb_build_object(
      'mes', pg_catalog.to_char(p_periodo, 'YYYY-MM'),
      'mes_nombre', private.etiqueta_mes_es(p_periodo),
      'anio', extract(year from p_periodo)::int,
      'zona', 'America/Lima',
      'desde', v_ini,
      'hasta', v_fin
    ),
    'ponderacion', jsonb_build_object(
      'referido', v_factor,
      'renovacion', v_factor,
      'fuente', 'crm.conversion_pesos'
    ),
    'fuentes', jsonb_build_object(
      'divisor', 'crm.leads.creado_en',
      'numerador', 'crm.lead_asignaciones.resultado_en',
      'referido', 'crm.leads.origen'
    ),
    -- Mes abierto: se dice explicitamente que NO esta cerrado, para que la
    -- pantalla no tenga que deducirlo de la ausencia de la clave.
    'cierre', jsonb_build_object('cerrado', false),
    'cobertura', jsonb_build_object(
      'medible', v_medible,
      'suelo_historico', v_suelo,
      'motivo_no_medible', v_motivo_no_medible,
      'divisor_aproximado', (select r.divisor_aproximado from resumen r),
      'divisor_por_motivo', coalesce(
        (select jsonb_object_agg(mt.motivo, mt.n) from motivos_totales mt),
        '{}'::jsonb),
      'cierres_sin_episodio', (select s.cierres_sin_episodio from sonda s),
      'fuera_de_roster', (
        select jsonb_build_object(
          'analistas', fr.analistas,
          'divisor', fr.divisor,
          'cierres', fr.cierres,
          'numerador', fr.numerador
        ) from fuera fr)
    ),
    'total', (
      select jsonb_build_object(
        'analistas', r.analistas,
        'divisor', r.divisor,
        'cierres_no_referidos', r.cierres_no_referidos,
        'cierres_referidos', r.cierres_referidos,
        'cierres_de_arrastre', r.cierres_de_arrastre,
        'referidos_recibidos', r.referidos_recibidos,
        'numerador', r.numerador,
        'conversion_pct', case when r.divisor > 0
          then round(100.0 * r.numerador / r.divisor, 2) end,
        'referidos_aporta_pct', case when r.divisor > 0
          then round(100.0 * v_factor * r.cierres_referidos / r.divisor, 2) end
      ) from resumen r),
    'responsables', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'vendedor_id', f.vendedor_id,
          'supervisor_id', f.supervisor_id,
          'divisor', f.divisor,
          'cierres_no_referidos', f.cierres_no_referidos,
          'cierres_referidos', f.cierres_referidos,
          'cierres_de_arrastre', f.cierres_de_arrastre,
          'numerador', f.numerador,
          'conversion_pct', f.conversion_pct,
          'estado', case
            when f.divisor > 0 then 'medible'
            when f.referidos_recibidos > 0 then 'solo_referidos'
            when (f.cierres_no_referidos + f.cierres_referidos) > 0 then 'solo_arrastre'
            else 'sin_actividad'
          end,
          'procedencia', f.procedencia,
          'referidos', jsonb_build_object(
            'recibidos', f.referidos_recibidos,
            'cerrados', f.cierres_referidos,
            'dados_de_alta', f.dados_de_alta,
            'aporta_pct', f.referidos_aporta_pct
          ),
          -- Lo que se le esta descontando de meses ya pagados, con su
          -- procedencia. Un numero que baja sin explicacion es una llamada a
          -- soporte; con el motivo al lado es una consecuencia.
          'ajuste', jsonb_build_object(
            'pendiente', f.ajuste_pendiente,
            'origenes', f.ajuste_origenes
          )
        )
        order by f.conversion_pct desc nulls last,
                 f.numerador desc,
                 f.divisor desc,
                 f.vendedor_id
      )
      from filas f
    ), '[]'::jsonb)
  ) into v_payload;

  -- El roster historico ya fue validado por su publicacion mensual. Aplicarle
  -- el rol/actividad de hoy borraria precisamente a una baja de ese mes.
  if v_es_historico_abierto then
    return v_payload;
  end if;
  return private.filtrar_desglose_sujetos_crm(
    v_payload, 'responsables', 'vendedor_id', array['vendedor']
  );
end;
$function$;

CREATE OR REPLACE FUNCTION crm.cerrar_periodo(p_periodo date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid         uuid := (select auth.uid());
  v_rol         text;
  v_automatico  boolean;
  v_mes_actual  date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_ini         timestamptz;
  v_fin         timestamptz;
  v_factor      numeric;
  v_periodo_id  uuid;
  v_revision    integer;
  v_suelo       timestamptz;
  v_medible     boolean;
  v_motivo      text;
  v_cobertura   jsonb;
  v_vendedores  integer;
  v_fuera_ranking jsonb := '[]'::jsonb;
  v_pendiente   date;
  v_ventana     timestamptz;
  v_ultimo_sellado date;
begin
  -- 1) Gate. `auth.uid()` nulo = el ciclo automatico (service_role); con uid,
  --    solo gerencia. Un vendedor o un supervisor no cierran meses.
  v_rol := private.rol_crm(v_uid);
  v_automatico := v_uid is null;
  if not v_automatico and v_rol is distinct from 'gerencia' then
    raise exception 'Solo gerencia cierra un mes' using errcode = '42501';
  end if;

  -- 2) El periodo.
  if p_periodo is null or p_periodo <> date_trunc('month', p_periodo)::date then
    raise exception 'El periodo debe ser el primer dia del mes' using errcode = '22023';
  end if;
  -- El mes en curso NO se cierra: todavia esta pasando. Y el siguiente tampoco,
  -- obviamente. La ventana de ajuste (del 1 al 10) vive en el mes SIGUIENTE al
  -- que se cierra, asi que aqui basta con exigir que el mes ya haya terminado.
  if p_periodo >= v_mes_actual then
    raise exception 'Un mes solo se cierra cuando ya termino' using errcode = '22023';
  end if;

  -- 2bis) EL CANDADO. Del 1 al 10 del mes siguiente el mes todavia admite
  --    correcciones, asi que NADIE lo sella: ni gerencia ni el ciclo. Sin esto,
  --    el momento de cerrar decide de que mes sale el dinero de una correccion.
  --    Es un SUELO, no una fecha exacta (decision de Miguel, 2026-08-15): pasado
  --    el dia 10 se puede cerrar cualquier dia, para que un fallo del ciclo no
  --    deje el mes atascado bloqueando a todos los siguientes.
  v_ventana := private.cierre_mes_ventana_desde(p_periodo);
  if now() < v_ventana then
    raise exception using
      errcode = '22023',
      message = format('El mes %s no se puede cerrar antes del %s',
                       to_char(p_periodo, 'YYYY-MM'),
                       to_char(v_ventana at time zone 'America/Lima', 'DD/MM/YYYY')),
      hint    = 'Del 1 al 10 hay ventana de ajuste: el mes todavia puede recibir correcciones.';
  end if;

  -- 2ter) EL CERROJO DEL PERIODO. Se toma ANTES de leer `periodos_cerrados` y de
  --    escribir nada, y lo comparte `private.registrar_ajuste_si_mes_cerrado`.
  --    Sin el hay una carrera que PIERDE DINERO EN SILENCIO: una anulacion que
  --    arranca mientras el cierre esta a medias ve el mes todavia ABIERTO —el
  --    sello aun no ha hecho commit—, decide que no hay deuda que registrar, y
  --    la foto que se esta sellando ya habia contado ese cierre. Resultado: un
  --    cierre anulado queda pagado para siempre y sin una linea que lo explique.
  --    Antes era una carrera teorica (alguien tenia que decidir cerrar); con el
  --    ciclo automatico hay una cita fija, mensual y a hora conocida, justo
  --    cuando gerencia esta mirando esos numeros. Mismo patron que usa
  --    `crm.publicar_metas_vendedores`.
  -- CANDADO GLOBAL primero (20260815235500): serializa este sellado con
  -- CUALQUIER publicacion de metas en vuelo — tambien la de OTRO mes. El
  -- trigger del candado toma el mismo global antes de mirar; sin esto,
  -- publicar P durante el sellado de M>P paria metas muertas bajo el suelo.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados')::bigint
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (p_periodo - date '2000-01-01')::integer
  );

  lock table crm.equipo in share mode;

  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo = p_periodo) then
    raise exception using
      errcode = 'P0409',
      message = 'Ese mes ya estaba cerrado',
      hint    = 'Un mes cerrado no se reescribe: lo que haya que corregir se descuenta en el mes vivo.';
  end if;

  -- 2quater) NUNCA POR DETRAS DE UN MES YA SELLADO. La regla de «sin huecos»
  --    del paso 3 protege el orden dado un conjunto de meses FIJO, y el conjunto
  --    no es fijo: `crm.publicar_metas_vendedores` acepta cualquier mes, asi que
  --    unas metas publicadas hacia atras pueden fabricar un «mes pendiente»
  --    anterior a uno que ya se pago. Sellarlo despues reescribiria la historia
  --    por el unico hueco que quedaba, y `private.saldar_ajustes` le cobraria a
  --    ese mes viejo deudas que tocaban al mes vivo.
  --    En el camino normal esto es un no-op: el ciclo siempre va de viejo a
  --    nuevo. Cuesta una consulta y cierra la ultima puerta.
  select max(pc.periodo) into v_ultimo_sellado from crm.periodos_cerrados pc;
  if v_ultimo_sellado is not null and p_periodo < v_ultimo_sellado then
    raise exception using
      errcode = '22023',
      message = format('No se sella %s: %s ya esta cerrado y es posterior',
                       to_char(p_periodo, 'YYYY-MM'), to_char(v_ultimo_sellado, 'YYYY-MM')),
      hint    = 'Los meses se sellan hacia adelante. Un mes que aparece por detras de lo ya pagado se corrige en el mes vivo, no sellandolo.';
  end if;

  -- 3) Sin huecos: no se cierra un mes si queda alguno anterior CON DATOS
  --    abierto. «Con datos» = tiene metas publicadas; un mes sin metas nunca
  --    tuvo nada que pagar y no bloquea la secuencia.
  v_pendiente := private.cierre_mes_pendiente(p_periodo);
  if v_pendiente is not null then
    raise exception using
      errcode = '22023',
      message = format('Falta cerrar %s antes que %s', v_pendiente, p_periodo),
      hint    = 'Los meses se cierran en orden: si no, el que se salta queda abierto para siempre.';
  end if;

  v_ini := p_periodo::timestamp at time zone 'America/Lima';
  v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';
  v_factor := private.peso_referido_conversion(p_periodo);

  select mp.id, mp.revision into v_periodo_id, v_revision
  from crm.meta_periodos mp
  where mp.periodo = p_periodo
  order by mp.revision desc
  limit 1;
  -- Un mes sin metas publicadas se puede cerrar igual: se sella lo que hubo
  -- (conversion sin objetivo). Cerrar es fijar la historia, no premiarla.
  v_revision := coalesce(v_revision, 0);

  -- 4) La cobertura, con el MISMO criterio que la pantalla. Se recalcula aqui en
  --    vez de leerse de `conversion_mensual_fn` porque esa funcion recorta por
  --    `auth.uid()` y el cierre necesita la foto completa.
  select min(la.asignado_en) into v_suelo
  from crm.lead_asignaciones la
  where not la.aproximado;

  if v_suelo is null then
    v_medible := false;
    v_motivo := 'sin_ledger';
  elsif v_ini < v_suelo then
    v_medible := false;
    v_motivo := case
      when p_periodo < date_trunc('month', v_suelo at time zone 'America/Lima')::date
        then 'anterior_al_ledger'
      else 'mes_parcial'
    end;
  else
    v_medible := true;
    v_motivo := null;
  end if;
  v_cobertura := jsonb_build_object(
    'modelo_conversion', 'llegadas_v2',
    'medible', v_medible,
    'suelo_historico', v_suelo,
    'motivo_no_medible', v_motivo
  );

  with conv as materialized (
    select cm.*
    from private.conversion_mensual_por_vendedor(
      v_ini, v_fin, true, '{}'::uuid[], v_factor
    ) cm
  ), prod as materialized (
    select r.*
    from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
  ), car as materialized (
    select m.* from private.metricas_cartera_por_vendedor(p_periodo) m
  ), roster as materialized (
    select distinct mv.vendedor_id
    from crm.metas_vendedor mv
    where mv.meta_periodo_id = v_periodo_id
  ), personas as (
    select c.analista_id as persona_id from conv c where c.analista_id is not null
    union
    select p.vendedor_id from prod p where p.vendedor_id is not null
    union
    select c.vendedor_id from car c where c.vendedor_id is not null
  ), elegibles as (
    select r.vendedor_id as persona_id from roster r
    union
    select p.persona_id
    from personas p
    join crm.equipo e
      on e.perfil_id = p.persona_id and e.rol_crm = 'vendedor'
    join crm.equipo s
      on s.perfil_id = e.supervisor_id and s.rol_crm = 'supervisor'
  ), fuera as (
    select
      p.persona_id,
      coalesce(nullif(btrim(pf.nombre_completo), ''),
               '(sin nombre · ' || left(p.persona_id::text, 8) || ')') as nombre,
      coalesce(e.rol_crm, 'fuera_equipo') as rol_crm,
      case
        when e.rol_crm = 'vendedor' then 'analista_sin_supervisor'
        when e.rol_crm = 'supervisor' then 'supervisor'
        when e.rol_crm = 'gerencia' then 'gerencia'
        else 'fuera_estructura'
      end as motivo
    from personas p
    left join crm.equipo e on e.perfil_id = p.persona_id
    left join public.perfiles pf on pf.id = p.persona_id
    where not exists (
      select 1 from elegibles ok where ok.persona_id = p.persona_id
    )
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'persona_id', f.persona_id,
    'nombre', f.nombre,
    'rol_crm', f.rol_crm,
    'motivo', f.motivo,
    'conversion', case when cv.analista_id is null then null else jsonb_build_object(
      'divisor', coalesce(cv.divisor, 0),
      'divisor_aproximado', coalesce(cv.divisor_aproximado, 0),
      'divisor_por_motivo', coalesce(cv.divisor_por_motivo, '{}'::jsonb),
      'cierres_no_referidos', coalesce(cv.cierres_no_referidos, 0),
      'cierres_referidos', coalesce(cv.cierres_referidos, 0),
      'cierres_de_arrastre', coalesce(cv.cierres_de_arrastre, 0),
      'referidos_recibidos', coalesce(cv.referidos_recibidos, 0),
      'numerador', coalesce(cv.numerador, 0)
    ) end,
    'detalles', det.detalles,
    'cartera', jsonb_build_object(
      'conversiones_clientes', coalesce(car.conversiones_clientes, 0),
      'conversiones_renovacion', coalesce(car.conversiones_renovacion, 0),
      'conversiones_upgrade', coalesce(car.conversiones_upgrade, 0),
      'operaciones_renovacion', coalesce(car.operaciones_renovacion, 0),
      'operaciones_upgrade', coalesce(car.operaciones_upgrade, 0),
      'capital_renovado_pen', coalesce(car.capital_renovado_pen, 0),
      'capital_renovado_usd', coalesce(car.capital_renovado_usd, 0),
      'capital_adicional_pen', coalesce(car.capital_adicional_pen, 0),
      'capital_adicional_usd', coalesce(car.capital_adicional_usd, 0),
      'renovaciones_sin_desglose', coalesce(car.renovaciones_sin_desglose, 0)
    )
  ) order by f.nombre, f.persona_id), '[]'::jsonb)
    into v_fuera_ranking
  from fuera f
  left join conv cv on cv.analista_id = f.persona_id
  left join car on car.vendedor_id = f.persona_id
  left join lateral (
    select jsonb_agg(jsonb_build_object(
      'categoria', d.categoria,
      'moneda', d.moneda,
      'capital_objetivo', 0,
      'capital_real', coalesce(pr.capital_real, 0),
      'capital_cumplimiento_pct', null,
      'contratos_objetivo', 0,
      'contratos_real', coalesce(pr.contratos_real, 0),
      'contratos_cumplimiento_pct', null,
      'capital_ajuste', 0,
      'contratos_ajuste', 0
    ) order by array_position(
      array['nuevo','renovacion','upgrade'], d.categoria
    ), d.moneda) as detalles
    from (values
      ('nuevo'::text, 'PEN'::text), ('nuevo', 'USD'),
      ('renovacion', 'PEN'), ('renovacion', 'USD'),
      ('upgrade', 'PEN'), ('upgrade', 'USD')
    ) d(categoria, moneda)
    left join prod pr on pr.vendedor_id = f.persona_id
      and pr.categoria = d.categoria and pr.moneda = d.moneda
  ) det on true;

  v_cobertura := v_cobertura || jsonb_build_object(
    'fuera_ranking', v_fuera_ranking
  );

  -- Sin analista forma parte del total de empresa, no del ranking de personas.
  -- Se congela junto a la foto; una asignación posterior no reescribe el cierre.
  v_cobertura := v_cobertura || coalesce((
    select jsonb_build_object('conversion_sin_analista', to_jsonb(cm) - 'analista_id')
    from private.conversion_mensual_por_vendedor(v_ini, v_fin, true, '{}'::uuid[], v_factor) cm
    where cm.analista_id is null
  ), '{}'::jsonb);

  insert into crm.periodos_cerrados (
    periodo, cerrado_por, automatico, ponderacion_referido, meta_revision, cobertura
  ) values (
    p_periodo,
    case when v_automatico then null else v_uid end,
    v_automatico, v_factor, v_revision, v_cobertura
  );

  -- 5) La foto. El conjunto de personas es el ROSTER DEL MES (quien tenia meta),
  --    en union con quien PRODUJO aunque no tuviera meta: los dos importan para
  --    una foto de pago, y quien produjo sin meta tiene que quedar registrado
  --    con su nombre en vez de disolverse en un agregado anonimo — que es lo que
  --    hace la pantalla viva, y esta bien alli (privacidad) y mal aqui (pago).
  with conv as (
    select cm.*
    from private.conversion_mensual_por_vendedor(v_ini, v_fin, true, '{}'::uuid[], v_factor) cm
  ), prod as (
    select r.vendedor_id, r.categoria, r.moneda, r.contratos_real, r.capital_real
    from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
  ), car as (
    select m.* from private.metricas_cartera_por_vendedor(p_periodo) m
  ), roster as (
    -- `distinct on`: una fila por persona, pase lo que pase. La foto tiene la
    -- clave (periodo, vendedor), asi que dos metas del mismo vendedor en el
    -- mismo periodo harian reventar el cierre entero con un duplicado — un mes
    -- que no se puede cerrar por una fila repetida es peor que el duplicado.
    -- (Lo cazo el oraculo ejecutando, no leyendo.)
    select distinct on (mv.vendedor_id)
      mv.vendedor_id, mv.supervisor_id, mv.conversion_objetivo, mv.id as meta_vendedor_id
    from crm.metas_vendedor mv
    where mv.meta_periodo_id = v_periodo_id
    order by mv.vendedor_id, mv.id
  ), personas as (
    select vendedor_id from roster
    union
    select analista_id from conv
    union
    select vendedor_id from prod where vendedor_id is not null
    union
    select vendedor_id from car where vendedor_id is not null
  ), foto as (
    select
      pe.vendedor_id,
      r.meta_vendedor_id,
      coalesce(r.supervisor_id, supervisor_actual.perfil_id) as supervisor_id,
      coalesce(r.conversion_objetivo, 0::numeric) as conversion_objetivo
    from personas pe
    left join roster r on r.vendedor_id = pe.vendedor_id
    left join crm.equipo vendedor_actual
      on vendedor_actual.perfil_id = pe.vendedor_id
    left join crm.equipo supervisor_actual
      on supervisor_actual.perfil_id = vendedor_actual.supervisor_id
     and supervisor_actual.rol_crm = 'supervisor'
    where r.meta_vendedor_id is not null
       or (
         vendedor_actual.rol_crm = 'vendedor'
         and supervisor_actual.perfil_id is not null
       )
  )
  insert into crm.cierre_mes_vendedor (
    periodo, vendedor_id, nombre_completo, supervisor_id, supervisor_nombre,
    divisor, divisor_aproximado, divisor_por_motivo,
    cierres_no_referidos, cierres_referidos, cierres_de_arrastre,
    numerador, conversion_pct, estado,
    referidos_recibidos, referidos_dados_de_alta, referidos_aporta_pct, procedencia,
    ajuste_numerador, ajuste_pen, ajuste_usd,
    conversion_objetivo, detalles, cartera
  )
  select
    p_periodo,
    pe.vendedor_id,
    coalesce(nullif(btrim(pf.nombre_completo), ''),
             '(sin nombre · ' || left(pe.vendedor_id::text, 8) || ')'),
    pe.supervisor_id,
    coalesce(nullif(btrim(sup.nombre_completo), ''), '(sin ficha)'),
    coalesce(c.divisor, 0),
    coalesce(c.divisor_aproximado, 0),
    coalesce(c.divisor_por_motivo, '{}'::jsonb),
    coalesce(c.cierres_no_referidos, 0),
    coalesce(c.cierres_referidos, 0),
    coalesce(c.cierres_de_arrastre, 0),
    -- NETO: lo bruto menos lo que este mes absorbio de deudas viejas. Es lo que
    -- se paga, asi que es lo que se sella.
    coalesce(c.numerador, 0::numeric) - sal.aplicado_numerador,
    case when coalesce(c.divisor, 0) > 0
      then round(100.0 * (coalesce(c.numerador, 0::numeric) - sal.aplicado_numerador)
                 / coalesce(c.divisor, 0), 2) end,
    case
      when coalesce(c.divisor, 0) > 0 then 'medible'
      when coalesce(c.referidos_recibidos, 0) > 0 then 'solo_referidos'
      when coalesce(c.cierres_no_referidos, 0) + coalesce(c.cierres_referidos, 0) > 0 then 'solo_arrastre'
      else 'sin_actividad'
    end,
    coalesce(c.referidos_recibidos, 0),
    coalesce(alta.dados_de_alta, 0),
    c.referidos_aporta_pct,
    coalesce(c.procedencia, '[]'::jsonb),
    sal.aplicado_numerador,
    sal.aplicado_pen,
    sal.aplicado_usd,
    pe.conversion_objetivo,
    coalesce(det.detalles, '[]'::jsonb),
    jsonb_build_object(
      'conversiones_clientes', coalesce(car.conversiones_clientes, 0),
      'conversiones_renovacion', coalesce(car.conversiones_renovacion, 0),
      'conversiones_upgrade', coalesce(car.conversiones_upgrade, 0),
      'operaciones_renovacion', coalesce(car.operaciones_renovacion, 0),
      'operaciones_upgrade', coalesce(car.operaciones_upgrade, 0),
      'capital_renovado_pen', coalesce(car.capital_renovado_pen, 0),
      'capital_renovado_usd', coalesce(car.capital_renovado_usd, 0),
      'capital_adicional_pen', coalesce(car.capital_adicional_pen, 0),
      'capital_adicional_usd', coalesce(car.capital_adicional_usd, 0),
      'renovaciones_sin_desglose', coalesce(car.renovaciones_sin_desglose, 0)
    )
  from foto pe
  left join conv c on c.analista_id = pe.vendedor_id
  left join car on car.vendedor_id = pe.vendedor_id
  left join public.perfiles pf on pf.id = pe.vendedor_id
  left join public.perfiles sup on sup.id = pe.supervisor_id
  left join lateral (
    -- El capital bruto del mes por moneda, que es el techo de lo que este mes
    -- puede absorber. PEN y USD por separado: una deuda en soles no se paga con
    -- produccion en dolares.
    -- ⚠️ Va ANTES del `saldar_ajustes` que lo consume: un LATERAL solo puede
    -- mirar a su izquierda.
    select
      coalesce(sum(pr.capital_real) filter (where pr.moneda = 'PEN'), 0) as pen,
      coalesce(sum(pr.capital_real) filter (where pr.moneda = 'USD'), 0) as usd
    from prod pr
    where pr.vendedor_id = pe.vendedor_id
  ) cap on true
  -- Lo que este mes puede absorber de las deudas viejas del vendedor. Es
  -- VOLATIL a proposito: ademas de devolver lo aplicado, DESCUENTA lo saldado y
  -- deja el resto arrastrandose. Se llama una vez por persona, que es la unica
  -- forma en que la cuenta cuadra.
  left join lateral private.saldar_ajustes(
    pe.vendedor_id,
    coalesce(c.numerador, 0::numeric),
    coalesce(cap.pen, 0::numeric),
    coalesce(cap.usd, 0::numeric)
  ) sal on true
  left join lateral (
    select count(*)::int as dados_de_alta
    from crm.leads l
    where l.origen = 'referido'
      and l.creado_en >= v_ini and l.creado_en < v_fin
      and l.creado_por = pe.vendedor_id
  ) alta on true
  left join lateral (
    -- ⚠️ `capital_real` y `contratos_real` van NETOS del descuento que este mes
    -- absorbio, casilla a casilla. Es la correccion de un fallo de DINERO: la
    -- primera version marcaba la deuda como saldada y NO la restaba de ninguna
    -- cifra, asi que el asesor cobraba igual y la deuda desaparecia — miles de
    -- soles perdonados en silencio, sin una sola linea que lo dijera.
    select jsonb_agg(jsonb_build_object(
      'categoria', dimensiones.categoria,
      'moneda', dimensiones.moneda,
      'capital_objetivo', coalesce(d.capital_objetivo, 0),
      'capital_real', greatest(coalesce(pr.capital_real, 0) - coalesce(aj.capital, 0), 0),
      'capital_cumplimiento_pct', case when coalesce(d.capital_objetivo, 0) > 0
        then round(100.0 * greatest(coalesce(pr.capital_real, 0) - coalesce(aj.capital, 0), 0)
                   / d.capital_objetivo, 2) end,
      'contratos_objetivo', coalesce(d.contratos_objetivo, 0),
      'contratos_real', greatest(coalesce(pr.contratos_real, 0) - coalesce(aj.contratos, 0), 0),
      'contratos_cumplimiento_pct', case when coalesce(d.contratos_objetivo, 0) > 0
        then round(100.0 * greatest(coalesce(pr.contratos_real, 0) - coalesce(aj.contratos, 0), 0)
                   / d.contratos_objetivo, 2) end,
      'capital_ajuste', coalesce(aj.capital, 0),
      'contratos_ajuste', coalesce(aj.contratos, 0)
    ) order by array_position(
      array['nuevo','renovacion','upgrade'], dimensiones.categoria
    ), dimensiones.moneda) as detalles
    from (values
      ('nuevo'::text, 'PEN'::text), ('nuevo', 'USD'),
      ('renovacion', 'PEN'), ('renovacion', 'USD'),
      ('upgrade', 'PEN'), ('upgrade', 'USD')
    ) dimensiones(categoria, moneda)
    left join crm.metas_vendedor_detalle d
      on d.meta_vendedor_id = pe.meta_vendedor_id
     and d.categoria = dimensiones.categoria
     and d.moneda = dimensiones.moneda
    left join prod pr on pr.vendedor_id = pe.vendedor_id
      and pr.categoria = dimensiones.categoria
     and pr.moneda = dimensiones.moneda
    left join lateral (
      select coalesce((e->>'capital')::numeric, 0) as capital,
             coalesce((e->>'contratos')::int, 0) as contratos
      from jsonb_array_elements(sal.aplicado_detalle) e
      where e->>'categoria' = dimensiones.categoria
        and e->>'moneda' = dimensiones.moneda
      limit 1
    ) aj on true
  ) det on true;

  get diagnostics v_vendedores = row_count;

  -- El rastro del cierre NO se escribe en `crm.actividades`: esa tabla cuelga de
  -- un lead y un cierre de mes no es de ningun lead. El registro lo deja el
  -- trigger de auditoria sobre `crm.periodos_cerrados`, con quien, cuando y que.

  return jsonb_build_object(
    'ok', true,
    'periodo', to_char(p_periodo, 'YYYY-MM'),
    'automatico', v_automatico,
    'vendedores', v_vendedores,
    'meta_revision', v_revision,
    'cobertura', v_cobertura
  );
end;
$function$;

do $postflight$
begin
  if exists (
    select 1 from pg_temp.conversion_llegadas_perimetro antes
    left join pg_proc ahora on ahora.oid = antes.oid
    where ahora.oid is null
      or (ahora.proowner, ahora.proacl, ahora.prosecdef, ahora.provolatile, ahora.proconfig)
         is distinct from
         (antes.proowner, antes.proacl, antes.prosecdef, antes.provolatile, antes.proconfig)
  ) then
    raise exception 'Conversión llegadas: cambió el perímetro de permisos o una firma; rollback';
  end if;
end;
$postflight$;
notify pgrst, 'reload schema';
commit;

-- Filtro de ORIGEN del lead en las metricas de conversiones (Miguel, 27/08).
--
-- QUE: `crm.metricas_conversiones_fn` y su implementacion aprenden
-- `p_origen text default null`. Con filtro, el LOTE entero se recorta al
-- origen elegido (cohorte, embudo, origenes, categorias, responsables y
-- tendencia semanal); 'sin_origen' selecciona los leads sin origen
-- registrado. El nucleo del mes y las sondas de paridad NO se filtran (miden
-- a la EMPRESA y la pantalla de Conversiones ya no los pinta — desde hoy su
-- cifra grande es la cosecha BRUTA); el payload declara `origen_filtrado`
-- SIEMPRE (null sin filtro) para que la forma sea estable y auditable.
--
-- CAMBIO DE FIRMA, NO BORRADO: las firmas de 2 argumentos se reemplazan por
-- las de 3 con default — toda llamada existente ({p_desde,p_hasta}, el front
-- vivo y el gate) resuelve identica a la nueva. Se DROPean las viejas en el
-- mismo archivo que crea las nuevas porque dos sobrecargas del mismo nombre
-- volverian ambigua la llamada por PostgREST. La capacidad queda intacta y
-- ampliada; nada de produccion pierde nada.
--
-- NO toca objetos de `public`. Autorizacion identica (gerencia/lector
-- global). ACLs replicadas: implementacion owner-only, wrapper EXECUTE solo
-- para authenticated.

-- ── Preflight: las vivas deben ser EXACTAMENTE las conocidas ────────────────
do $preflight$
declare
  v_md5_impl text;
  v_md5_wrap text;
begin
  select md5(p.prosrc) into v_md5_impl
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.proname = 'metricas_conversiones_implementacion'
    and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_desde date, p_hasta date';
  if v_md5_impl is distinct from '698f5999a4743e69b3e1d8df15345921' then
    raise exception 'implementacion viva (md5 %) NO es la de F1.3b; re-basar antes de aplicar', v_md5_impl;
  end if;
  select md5(p.prosrc) into v_md5_wrap
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm'
    and p.proname = 'metricas_conversiones_fn'
    and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_desde date, p_hasta date';
  if v_md5_wrap is distinct from '593e97a185ac23bf1a78d2a872a289c3' then
    raise exception 'wrapper vivo (md5 %) NO es el conocido; re-basar antes de aplicar', v_md5_wrap;
  end if;
end;
$preflight$;

-- Reemplazo de firma (ver cabecera): fuera las 2-arg, entran las 3-arg.
drop function crm.metricas_conversiones_fn(date, date);
drop function private.metricas_conversiones_implementacion(date, date);

create function private.metricas_conversiones_implementacion(p_desde date, p_hasta date, p_origen text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
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

  -- La pierna de cartera solo tiene sentido si el rango ES un mes (entero o
  -- lo que va de el): una operacion de cartera pertenece a un mes, no a un
  -- rango libre. Si el rango cruza meses o no empieza el dia 1, se omite y el
  -- payload lo declara (`nucleo.incluye_cartera`) para que F3 lo rotule.
  -- OJO (objecion A2 del auditor): la pierna de cartera de la tabla-base
  -- filtra por MES de la operacion, no por la ventana. Un rango 01→10 de julio
  -- sumaria las operaciones del 11 al 31 y el % saldria inflado. Por eso solo
  -- se activa cuando el rango cubre el mes ENTERO o TODO lo que va del mes en
  -- curso; cualquier otro recorte va sin cartera y el payload lo declara.
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
  -- Flujo del rango (cohorte por asignacion): la cifra principal, la misma
  -- que HOY/Ranking/Metas.
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
    where e.tipo = 'cierre' and not e.anulado and e.lead_id is not null
  ),
  cohorte_base as materialized (
    -- F1.3b: el capital del lead se mide por los caminos VIVOS y HASTA HOY
    -- (lectura de cosecha: «de ese lote, cuanto ha producido»): contratos del
    -- portal de su perfil + cierres en coops vigentes. Aqui muere la primera
    -- de las dos ultimas lecturas del enlace jamas poblado (leads.contrato_id).
    select l.*,
      (coalesce((select sum(ct.capital) from public.contratos ct
         where ct.cliente_id = l.perfil_id and ct.moneda = 'PEN'), 0)
       + coalesce((select sum(ce.monto) from crm.cierres_externos ce
         where ce.lead_id = l.id and ce.anulado_en is null and ce.moneda = 'PEN'), 0)) as capital_lead_pen,
      (coalesce((select sum(ct.capital) from public.contratos ct
         where ct.cliente_id = l.perfil_id and ct.moneda = 'USD'), 0)
       + coalesce((select sum(ce.monto) from crm.cierres_externos ce
         where ce.lead_id = l.id and ce.anulado_en is null and ce.moneda = 'USD'), 0)) as capital_lead_usd
    from crm.leads l
    where l.creado_en >= v_ini and l.creado_en < v_fin
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
      count(*) filter (where e.tipo = 'recibido' and not e.fue_referido)::int as divisor,
      count(*) filter (where e.tipo = 'recibido' and e.fue_referido)::int as referidos_recibidos,
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and not e.fue_referido)::int as cierres_no_referidos,
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and e.fue_referido)::int as cierres_referidos,
      count(*) filter (where e.tipo = 'operacion')::int as operaciones
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
      (coalesce(sum(nv.cierres_no_referidos), 0)
       + v_factor * coalesce(sum(nv.cierres_referidos), 0)
       + coalesce(sum(nv.operaciones), 0))::numeric as numerador
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
          (nv.cierres_no_referidos + v_factor * nv.cierres_referidos + nv.operaciones)::numeric, 0)
        - coalesce(cm.numerador, 0)) as delta
    from nucleo_vendedor nv
    full outer join private.conversion_mensual_por_vendedor(
      v_ini, v_fin, true, null, v_factor
    ) cm on cm.analista_id = nv.analista_id
  ),
  sonda_paridad as (
    select
      case when v_periodo is null then null else coalesce(sum(c.delta), 0) end as desvio,
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
      ((select count(*)::int from public.contratos c
        where c.fecha_cierre_comercial >= p_desde and c.fecha_cierre_comercial <= p_hasta
          and exists (select 1 from crm.leads l where l.perfil_id = c.cliente_id))
       + (select count(*)::int from crm.cierres_externos ce
          where ce.anulado_en is null
            and (ce.creado_en at time zone 'America/Lima')::date between p_desde and p_hasta)) as contratos,
      (coalesce((select sum(c.capital) from public.contratos c
        where c.fecha_cierre_comercial >= p_desde and c.fecha_cierre_comercial <= p_hasta and c.moneda = 'PEN'
          and exists (select 1 from crm.leads l where l.perfil_id = c.cliente_id)), 0)
       + coalesce((select sum(ce.monto) from crm.cierres_externos ce
          where ce.anulado_en is null and ce.moneda = 'PEN'
            and (ce.creado_en at time zone 'America/Lima')::date between p_desde and p_hasta), 0)) as capital_pen,
      (coalesce((select sum(c.capital) from public.contratos c
        where c.fecha_cierre_comercial >= p_desde and c.fecha_cierre_comercial <= p_hasta and c.moneda = 'USD'
          and exists (select 1 from crm.leads l where l.perfil_id = c.cliente_id)), 0)
       + coalesce((select sum(ce.monto) from crm.cierres_externos ce
          where ce.anulado_en is null and ce.moneda = 'USD'
            and (ce.creado_en at time zone 'America/Lima')::date between p_desde and p_hasta), 0)) as capital_usd,
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
      (coalesce((select sum(ct.capital) from public.contratos ct
         where ct.moneda = 'PEN'
           and ct.fecha_cierre_comercial >= p_desde and ct.fecha_cierre_comercial <= p_hasta
           and ct.cliente_id in (select l.perfil_id from crm.leads l
                                 where l.vendedor_id = vb.vendedor_id and l.perfil_id is not null)), 0)
       + coalesce((select sum(ce.monto) from crm.cierres_externos ce
         where ce.vendedor_id = vb.vendedor_id and ce.anulado_en is null and ce.moneda = 'PEN'
           and (ce.creado_en at time zone 'America/Lima')::date between p_desde and p_hasta), 0)) as capital_pen,
      (coalesce((select sum(ct.capital) from public.contratos ct
         where ct.moneda = 'USD'
           and ct.fecha_cierre_comercial >= p_desde and ct.fecha_cierre_comercial <= p_hasta
           and ct.cliente_id in (select l.perfil_id from crm.leads l
                                 where l.vendedor_id = vb.vendedor_id and l.perfil_id is not null)), 0)
       + coalesce((select sum(ce.monto) from crm.cierres_externos ce
         where ce.vendedor_id = vb.vendedor_id and ce.anulado_en is null and ce.moneda = 'USD'
           and (ce.creado_en at time zone 'America/Lima')::date between p_desde and p_hasta), 0)) as capital_usd
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
      'base', 'asignacion',
      'incluye_cartera', v_periodo is not null,
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
          (nv3.cierres_no_referidos + v_factor * nv3.cierres_referidos + nv3.operaciones)::numeric
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
          (nv.cierres_no_referidos + v_factor * nv.cierres_referidos + nv.operaciones)::numeric, 0),
        'nucleo_conversion_pct', case when coalesce(nv.divisor, 0) > 0
          then round(100.0 * (nv.cierres_no_referidos + v_factor * nv.cierres_referidos
                              + nv.operaciones) / nv.divisor, 2) end,
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

revoke all on function private.metricas_conversiones_implementacion(date, date, text) from public;

comment on function private.metricas_conversiones_implementacion(date,date,text) is
  'Implementacion de metricas_conversiones_fn. p_origen (27/08) recorta el LOTE al origen elegido (sin_origen = sin registrar); nucleo y paridad siguen midiendo a la empresa y el payload declara origen_filtrado. Todo el capital por los caminos vivos (F1.3b); leads.contrato_id no se consulta.';

create function crm.metricas_conversiones_fn(p_desde date, p_hasta date, p_origen text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $wrapper$
declare
  v_actor uuid := (select auth.uid());
  v_payload jsonb;
begin
  if v_actor is null or not coalesce(
    private.rol_crm(v_actor)='gerencia' or private.es_lector_global(),
    false
  ) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_payload:=private.metricas_conversiones_implementacion(p_desde,p_hasta,p_origen);
  return private.filtrar_desglose_sujetos_crm(
    v_payload,'responsables','vendedor_id',array['vendedor']
  );
end;
$wrapper$;

revoke all on function crm.metricas_conversiones_fn(date, date, text) from public, anon, authenticated, service_role;
grant execute on function crm.metricas_conversiones_fn(date, date, text) to authenticated;

comment on function crm.metricas_conversiones_fn(date,date,text) is
  'Metricas de conversiones del rango para gerencia/lector global. p_origen filtra el lote por origen del lead (null = todos). El desglose de responsables se recorta a vendedores.';

-- ── Postflight ──────────────────────────────────────────────────────────────
do $postflight$
declare
  v_src text;
begin
  -- Unicidad: una sola firma por nombre, o PostgREST se vuelve ambiguo.
  if (select count(*) from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'metricas_conversiones_fn') <> 1
     or (select count(*) from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private' and p.proname = 'metricas_conversiones_implementacion') <> 1 then
    raise exception 'quedo mas de una sobrecarga (o ninguna); rollback';
  end if;

  select p.prosrc into v_src
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private'
     and p.proname = 'metricas_conversiones_implementacion'
     and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_desde date, p_hasta date, p_origen text';
  if v_src is null then
    raise exception 'la implementacion 3-arg no existe; rollback';
  end if;
  if md5(v_src) is distinct from 'b4875f18423045c23c52b1cd8dfe25c3' then
    raise exception 'md5 de la implementacion (%) no es el esperado; rollback', md5(v_src);
  end if;
  -- strpos, JAMAS like (guion bajo comodin).
  if strpos(v_src, 'origen_filtrado') = 0
     or strpos(v_src, $$coalesce(l.origen, 'sin_origen') = p_origen$$) = 0 then
    raise exception 'el filtro de origen no quedo escrito; rollback';
  end if;
  if strpos(v_src, 'l.contrato_id') > 0 then
    raise exception 'el enlace muerto revivio; rollback';
  end if;
  if strpos(v_src, 'perfiles_con_leads_de_varios_vendedores') = 0 or strpos(v_src, 'sin_rastro') = 0 then
    raise exception 'una sonda de F1.3/F1.3b desaparecio; rollback';
  end if;

  select p.prosrc into v_src
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'crm'
     and p.proname = 'metricas_conversiones_fn'
     and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_desde date, p_hasta date, p_origen text';
  if v_src is null then
    raise exception 'el wrapper 3-arg no existe; rollback';
  end if;
  if md5(v_src) is distinct from 'f6e436743f650391e8d654c46187d16d' then
    raise exception 'md5 del wrapper (%) no es el esperado; rollback', md5(v_src);
  end if;
  if strpos(v_src, 'No autorizado') = 0 or strpos(v_src, 'filtrar_desglose_sujetos_crm') = 0 then
    raise exception 'el wrapper perdio su gate o su recorte de sujetos; rollback';
  end if;

  -- DEFINER + search_path fijo en AMBAS (identity args siempre).
  if (select count(*) from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where ((n.nspname = 'private' and p.proname = 'metricas_conversiones_implementacion')
           or (n.nspname = 'crm' and p.proname = 'metricas_conversiones_fn'))
         and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_desde date, p_hasta date, p_origen text'
         and p.prosecdef
         and p.proconfig @> array['search_path=""']::text[]) <> 2 then
    raise exception 'alguna funcion perdio definer/search_path; rollback';
  end if;

  -- ACL de la implementacion: owner-only (NULL rechazado aparte — aclexplode
  -- de NULL devuelve cero filas y aprobaria una funcion abierta).
  if (select p.proacl from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private' and p.proname = 'metricas_conversiones_implementacion') is null then
    raise exception 'implementacion con ACL por defecto (EXECUTE a PUBLIC); rollback';
  end if;
  if exists (
    select 1 from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace,
      lateral pg_catalog.aclexplode(p.proacl) a
     where n.nspname = 'private' and p.proname = 'metricas_conversiones_implementacion'
       and a.grantee <> p.proowner
  ) then
    raise exception 'implementacion con EXECUTE fuera del owner; rollback';
  end if;

  -- ACL del wrapper: authenticated DEBE poder ejecutarlo, y nadie mas ajeno.
  if not has_function_privilege('authenticated', 'crm.metricas_conversiones_fn(date,date,text)'::regprocedure, 'execute') then
    raise exception 'authenticated perdio EXECUTE del wrapper; rollback';
  end if;
  if has_function_privilege('anon', 'crm.metricas_conversiones_fn(date,date,text)'::regprocedure, 'execute') then
    raise exception 'anon puede ejecutar el wrapper; rollback';
  end if;
  -- Objecion 2 del auditor: el wrapper historico revocaba tambien de
  -- service_role; si algun default privilege futuro se lo regalara, que este
  -- candado lo cace (el gate interno con auth.uid() nulo ya lo frena hoy).
  if has_function_privilege('service_role', 'crm.metricas_conversiones_fn(date,date,text)'::regprocedure, 'execute') then
    raise exception 'service_role puede ejecutar el wrapper; rollback';
  end if;
end;
$postflight$;

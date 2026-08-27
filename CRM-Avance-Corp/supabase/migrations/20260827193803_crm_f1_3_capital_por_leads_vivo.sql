-- F1.3 «capital por leads vivo» (plan del Hoy de gerencia, 2026-08-27).
--
-- QUE: el bloque `produccion` de private.metricas_conversiones_implementacion
-- dejaba capital_pen/capital_usd/contratos SIEMPRE en 0 porque contaba solo
-- contratos enlazados via crm.leads.contrato_id — y ese enlace JAMAS se
-- escribio (auditoria en prod 27/08: 0 enlaces historicos; agosto real:
-- 111 contratos y S/ 3,7 M con el KPI en S/ 0). Decision de Miguel: medir el
-- capital por leads por los caminos VIVOS:
--   * contratos del portal cuyo titular es un perfil nacido de un lead
--     (crm.leads.perfil_id = public.contratos.cliente_id), y
--   * cierres en cooperativas (crm.cierres_externos por lead, sin anulados).
-- Ademas `produccion.sin_rastro` declara los convertidos del rango sin perfil
-- ni cierre externo (hoy: 1 — lead de prueba «miguel alvarez» 19/08), para que
-- el front rotule el hueco en vez de taparlo.
--
-- ALCANCE ACOTADO (objecion 1 del auditor RLS, 27/08): el enlace muerto deja
-- de consultarse EN EL CTE `produccion`, y SOLO ahi. Sigue vivo — escrito como
-- `c.id = l.contrato_id` — en `cohorte_base` y `capital_responsables`, asi que
-- `origenes[].capital_*` y `responsables[].capital_*` continuan en 0 eterno.
-- Deuda DECLARADA para una F1.3b, no un descuido: esta migracion cambia una
-- sola pregunta (el capital de `produccion`) para poder verificarla sola.
--
-- Notas del auditor aceptadas y documentadas:
--   * La pierna USD sobre cierres_externos es hoy codigo muerto: la tabla
--     tiene CHECK (moneda = 'PEN'). Se deja por simetria; si el CHECK se
--     ampliara, esto ya suma bien.
--   * Las dos piernas pueden solaparse (lead cerrado en coop cuya persona
--     luego firma contrato del portal) y la pierna del portal cuenta TODO
--     contrato de un titular ex-lead (renovaciones incluidas): es la
--     definicion elegida por Miguel — «capital de clientes nacidos de un
--     lead» — no un bug; ninguna sonda lo mide todavia.
--   * `sin_rastro` es unidireccional: caza convertidos SIN perfil ni cierre;
--     un convertido CON perfil pero sin contrato aun no es «hueco», es
--     pipeline en curso.
--
-- NO toca objetos de `public` (solo LEE public.contratos, igual que la version
-- anterior). No cambia autorizacion, policies ni grants. La columna
-- crm.leads.contrato_id queda intacta (regla: nada de prod se borra).
--
-- Medido en prod antes de escribir (rango 2026-08-01..27): portal 6 contratos
-- S/ 58.000 + US$ 123.000 · externos 3 cierres S/ 55.000 · sin_rastro 1.

-- ── Preflight: la viva debe ser EXACTAMENTE la de F2.1 ──────────────────────
do $preflight$
declare
  v_md5 text;
begin
  select md5(p.prosrc) into v_md5
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.proname = 'metricas_conversiones_implementacion'
    and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_desde date, p_hasta date';
  if v_md5 is distinct from 'f38599fe3b1987b52b4f80676eca16af' then
    raise exception 'metricas_conversiones_implementacion viva (md5 %) NO es la de F2.1; re-basar F1.3 sobre la viva antes de aplicar', v_md5;
  end if;
end;
$preflight$;

create or replace function private.metricas_conversiones_implementacion(p_desde date, p_hasta date)
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
    select l.*, c.capital as capital_contrato, c.moneda as moneda_contrato,
           c.creado_en as contrato_creado_en
    from crm.leads l
    left join public.contratos c on c.id = l.contrato_id
    where l.creado_en >= v_ini and l.creado_en < v_fin
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
      coalesce(sum(capital_contrato) filter (where moneda_contrato = 'PEN'), 0) as capital_pen,
      coalesce(sum(capital_contrato) filter (where moneda_contrato = 'USD'), 0) as capital_usd
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
    select vb.vendedor_id,
      coalesce(sum(ct.capital) filter (where ct.moneda = 'PEN'), 0) as capital_pen,
      coalesce(sum(ct.capital) filter (where ct.moneda = 'USD'), 0) as capital_usd
    from vendedores_base vb
    left join crm.leads l on l.vendedor_id = vb.vendedor_id
    left join public.contratos ct on ct.id = l.contrato_id
      and ct.fecha_cierre_comercial >= p_desde and ct.fecha_cierre_comercial <= p_hasta
    group by vb.vendedor_id
  )
  select jsonb_build_object(
    'version', 1,
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

comment on function private.metricas_conversiones_implementacion(date,date) is
  'Implementacion de metricas_conversiones_fn. F1.3: el CTE produccion mide el capital por leads por los caminos vivos (perfil del lead en contratos del portal + cierres externos sin anular) y declara sin_rastro. El enlace leads.contrato_id (jamas poblado) ya no se consulta EN produccion; sigue en cohorte_base/capital_responsables (capitales por origen/vendedor en 0, deuda F1.3b).';

-- ── Postflight: la funcion quedo como se escribio, con sus candados ─────────
do $postflight$
declare
  v_src text;
begin
  select p.prosrc into v_src
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private'
     and p.proname = 'metricas_conversiones_implementacion'
     and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_desde date, p_hasta date';

  if v_src is null then
    raise exception 'metricas_conversiones_implementacion desaparecio; rollback';
  end if;
  if md5(v_src) is distinct from '47fb852c532bce508dff4463e5c7f2bc' then
    raise exception 'md5 vivo % no es el esperado de F1.3', md5(v_src);
  end if;
  -- strpos, JAMAS like: el guion bajo es comodin en LIKE.
  -- Asserts POSITIVOS: los dos caminos vivos y la sonda quedaron escritos.
  if strpos(v_src, 'l.perfil_id = c.cliente_id') = 0 then
    raise exception 'el camino perfil->contrato no quedo en produccion; rollback';
  end if;
  if strpos(v_src, 'crm.cierres_externos') = 0 then
    raise exception 'la pierna de cierres externos no quedo en produccion; rollback';
  end if;
  if strpos(v_src, 'sin_rastro') = 0 then
    raise exception 'la sonda sin_rastro no quedo en la funcion';
  end if;
  -- Assert NEGATIVO acotado: la variante `l.contrato_id = c.id` era EXCLUSIVA
  -- del CTE produccion de F2.1 y debe desaparecer. OJO: las joins de
  -- cohorte_base/capital_responsables usan la forma invertida
  -- `c.id = l.contrato_id` y SIGUEN VIVAS a proposito (deuda F1.3b) — este
  -- check NO las cubre ni pretende cubrirlas.
  if strpos(v_src, 'l.contrato_id = c.id') > 0 then
    raise exception 'el CTE produccion sigue consultando el enlace muerto; rollback';
  end if;

  -- Identity arguments SIEMPRE: sin ellos una sobrecarga futura haria pasar
  -- este assert sobre una funcion distinta (nota del auditor en F1).
  if not exists (
    select 1 from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'private' and p.proname = 'metricas_conversiones_implementacion'
       and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_desde date, p_hasta date'
       and p.prosecdef
       and p.proconfig @> array['search_path=""']::text[]
  ) then
    raise exception 'la funcion perdio definer/search_path; rollback';
  end if;

  -- La ACL es lo unico que impide que PostgREST alcance la implementacion
  -- saltandose el wrapper. CREATE OR REPLACE la conserva; se comprueba igual.
  -- OJO (Codex): `proacl IS NULL` NO es seguro — significa privilegios POR
  -- DEFECTO, que para una funcion incluyen EXECUTE a PUBLIC, y
  -- `aclexplode(null)` devuelve CERO filas, asi que un `exists` sobre el
  -- explode aprobaria una funcion abierta. El NULL se rechaza aparte.
  if (select p.proacl from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private' and p.proname = 'metricas_conversiones_implementacion'
         and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_desde date, p_hasta date')
     is null then
    raise exception 'la implementacion quedo con ACL por defecto (EXECUTE a PUBLIC); rollback';
  end if;
  if exists (
    select 1 from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace,
      lateral pg_catalog.aclexplode(p.proacl) a
     where n.nspname = 'private' and p.proname = 'metricas_conversiones_implementacion'
       and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_desde date, p_hasta date'
       and a.grantee <> p.proowner
  ) then
    raise exception 'la implementacion quedo con EXECUTE fuera del owner; rollback';
  end if;
end;
$postflight$;

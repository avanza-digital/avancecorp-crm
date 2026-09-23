-- =========================================================================
-- REVERSA de 20260923185001_crm_origenes_conversion_ponderada
-- =========================================================================
-- Vuelve a declarar el cuerpo EXACTO de antes (pg_get_functiondef de produccion
-- del 23/09/2026, el que dejo 20260923172517), restaura el COMMENT ON, la huella y
-- la razon del censo (literales) y refresca el sello, que queda con `sellado_en` de
-- hoy. Solo revierte ESTA migracion: el preflight exige el cuerpo y la declaracion
-- que ella dejo.
--   supabase db query --linked --file supabase/scripts/conversion/reversa-origenes-ponderada.sql
-- =========================================================================

begin;

set local statement_timeout = '120s';
set local lock_timeout = '5s';
lock table private.analitica_leads_citas_exenciones,
           private.analitica_lc_sello in share row exclusive mode;

do $preflight$
begin
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p
       where p.oid = 'private.metricas_conversiones_implementacion(date,date,text)'::regprocedure)
     is distinct from '6e4fedb3d6f9ba485ece9afeb322b491' then
    raise exception 'REVERSA: el cuerpo vivo no es el que instalo 20260923185001; no se revierte a ciegas';
  end if;
  if (select e.huella from private.analitica_leads_citas_exenciones e
       where e.objeto = 'private.metricas_conversiones_implementacion(date,date,text)')
     is distinct from '315549aa87482ba7ecc9148d53b78f1f'
     or (select e.razon from private.analitica_leads_citas_exenciones e
          where e.objeto = 'private.metricas_conversiones_implementacion(date,date,text)')
        is distinct from 'CONSUME EL NUCLEO DE CONVERSION Y EL NUCLEO DE CITAS. Conserva el embudo histórico por cohorte y añade contratos explícitos: llegadas únicas con cita realizada, operaciones seleccionadas por el núcleo vivo y cierres por su fecha real. No calcula pesos ni elige operaciones localmente. F4 publicada: contratos cooperativos por fecha de imputación y rastro por cierre inicial. Conserva los núcleos de conversión, citas y capital y sus fórmulas. Ola 1a (22/09/2026): DECLARA su fuente sin sustituir la cifra (es_mes_calendario, fuente=rango_vivo, sellado=null, ajuste_aplicado=false). Su conversion_pct sigue saliendo de su propia division sobre ep_flujo; la sustitucion por crm.conversion_mensual_fn va en un paquete aparte. Ola 1b (22/09/2026): cuando el rango es un mes calendario completo y no hay filtro de origen, DELEGA divisor, numerador y conversion_pct en crm.conversion_mensual_fn (fuente=mensual, sellado=<lo que diga la oficial>, ajuste_aplicado=true). Fuera de esa condicion sigue calculando en vivo y lo declara. 23/09/2026: el peso de la RENOVACION se guarda con la foto (cerrar_periodo) o se declara tal como se aplica (las dos puertas), en vez de reconstruirse desde el del referido. Conversion ponderada por origen (23/09/2026): cada fila de origenes publica conversion_ponderada_pct, la misma cifra con el referido a su peso; la pantalla solo la muestra.' then
    raise exception 'REVERSA: la declaracion del censo cambio despues de la migracion; no se pisa';
  end if;
  if private.assert_analitica_leads_citas() not like 'OK:%' then
    raise exception 'REVERSA: el trinquete ya estaba en rojo';
  end if;
end;
$preflight$;

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
  v_ahora timestamptz := now();
  v_mes date;
  v_factor numeric;
  v_periodo date;
  v_payload jsonb;
  v_autorizado boolean;
  v_oficial jsonb;
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
  v_cosecha_fin := greatest(v_fin, v_ahora);

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
  -- N1: citas clasificadas por el núcleo, sobre el lote de llegadas. El
  -- instante disponible es vence_en (fecha prevista); no se inventa una fecha
  -- física de asistencia ni una identidad de persona distinta de lead_id.
  citas_reales_ep as materialized (
    select ce.*
    from private.citas_episodios(v_ini, v_ahora, v_ahora) ce
    where ce.realizada and ce.debio_ocurrir
  ),
  citas_reales_cohorte as materialized (
    select cb.id as lead_id,
      count(ce.tarea_id) filter (where ce.vence_en >= cb.creado_en)::int
        as citas_realizadas,
      count(ce.tarea_id) filter (where ce.vence_en < cb.creado_en)::int
        as citas_anteriores_al_alta
    from cohorte_base cb
    left join citas_reales_ep ce on ce.lead_id = cb.id
    group by cb.id
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
      (cr.citas_realizadas > 0) as cita_real,
      cr.citas_realizadas as citas_realizadas_reales,
      cr.citas_anteriores_al_alta,
      h_asignado as asignado,
      (h_contacto or h_reunion_agendada or h_reunion_realizada or h_propuesta or h_cliente or h_contrato) as contactado,
      (h_reunion_agendada or h_reunion_realizada or h_propuesta or h_cliente or h_contrato) as reunion_agendada,
      (h_reunion_realizada or h_propuesta or h_cliente or h_contrato) as reunion_realizada,
      (h_propuesta or h_cliente or h_contrato) as propuesta,
      (h_cliente or h_contrato) as cliente,
      h_contrato as contrato
    from senales s
    join citas_reales_cohorte cr on cr.lead_id = s.id
  ),
  resumen as (
    select
      count(*)::int as leads,
      count(*) filter (where asignado)::int as asignados,
      count(*) filter (where contactado)::int as contactados,
      count(*) filter (where reunion_agendada)::int as reuniones_agendadas,
      count(*) filter (where reunion_realizada)::int as reuniones_realizadas,
      count(*) filter (where cita_real)::int as leads_con_cita_real,
      coalesce(sum(citas_realizadas_reales), 0)::int as citas_realizadas_reales,
      coalesce(sum(citas_anteriores_al_alta), 0)::int as citas_anteriores_al_alta,
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
            and (coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) at time zone 'America/Lima')::date between p_desde and p_hasta)) as contratos,
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
                          where ce.lead_id = l.id and ce.es_cierre_inicial and ce.anulado_en is null)) as sin_rastro
  ),
  origenes as (
    select coalesce(origen, 'sin_origen') as origen,
      count(*)::int as leads,
      count(*) filter (where contactado)::int as contactados,
      count(*) filter (where reunion_agendada)::int as reuniones_agendadas,
      count(*) filter (where reunion_realizada)::int as reuniones_realizadas,
      count(*) filter (where cita_real)::int as leads_con_cita_real,
      coalesce(sum(citas_realizadas_reales), 0)::int as citas_realizadas_reales,
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
      count(c.id) filter (where c.cita_real)::int as leads_con_cita_real,
      coalesce(sum(c.citas_realizadas_reales), 0)::int as citas_realizadas_reales,
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
      -- ── EL CONTRATO DE LA UNIFICACION (Ola 1a: DECLARAR, sin sustituir) ────
      -- Esta puerta publica el NUMERO GRANDE de Resumen y Conversiones, y hoy
      -- lo CALCULA ella: `conversion_pct` sale de su propia division sobre
      -- `ep_flujo`. Llama a `conversion_mensual_por_vendedor`, pero SOLO dentro
      -- del CTE `comparacion`, cuya unica salida es `sondas.paridad_nucleo`:
      -- esa llamada nunca toca la clave publicada.
      --
      -- 🔑 ESTE PASO NO CAMBIA NI UN NUMERO. Solo DECLARA de donde sale. La
      -- sustitucion —pedirle el bloque a `crm.conversion_mensual_fn` cuando el
      -- rango es un mes completo— es el paso siguiente y va aparte, porque
      -- mueve el heroe que ve gerencia y merece su propio ensayo.
      --
      -- Mientras tanto, declarar ya sirve: el dia que exista un mes sellado o
      -- una deuda cruzando meses, esta pantalla dira EN SU PAQUETE que su cifra
      -- es un recalculo en vivo, en vez de callarlo. Hoy el desacuerdo seria
      -- mudo; con esto, es legible.
      --
      -- `v_periodo` YA distingue el mes calendario, y bien: exige dia 1, mismo
      -- mes, y fin de mes O HOY (regla de Miguel: para el mes vigente, «mes
      -- completo» es del 1 a hoy). `v_hoy` va en hora de Lima.
      'es_mes_calendario', v_periodo is not null,
      -- Hasta que se haga la sustitucion, SIEMPRE es un recalculo en vivo. Se
      -- dice tal cual: mentir aqui seria peor que callar.
      'fuente', 'rango_vivo',
      -- `null` = «no se delego, asi que no se sabe si el mes esta sellado».
      -- NO es lo mismo que `false`, que afirmaria que no lo esta.
      'sellado', null,
      -- Su numerador no descuenta la deuda por cierres anulados: esa resta vive
      -- en la LECTURA mensual, y esta puerta no la hace.
      'ajuste_aplicado', false,
      'llegadas', (select count(*) from ep_flujo e where e.tipo = 'recibido'),
      'altas_manuales', (select count(*) from ep_flujo e
        where e.tipo = 'recibido' and not e.fue_referido and e.aporte_divisor = 0),
      'renovaciones', (select count(*) from ep_flujo e where e.tipo = 'operacion' and e.categoria = 'renovacion'),
      'upgrades', (select count(*) from ep_flujo e where e.tipo = 'operacion' and e.categoria = 'upgrade'),
      'aporte_cartera', (select coalesce(sum(e.aporte_numerador), 0) from ep_flujo e where e.tipo = 'operacion'),
      'base', 'llegada_unica',
      'atribucion', 'primer_analista',
      -- 23/09/2026: publicaba `v_factor`, el peso del REFERIDO, mientras el nucleo
      -- ya aplica el de la RENOVACION. Misma correccion que en
      -- crm.metricas_conversiones_equipo_fn: se declara el que se aplica.
      'peso_renovacion', private.peso_renovacion_conversion(v_mes),
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
    'citas_reales', jsonb_build_object(
      'version', 1,
      'unidad', 'lead_id',
      'base', 'llegadas_unicas',
      'fecha_cita', 'vence_en',
      'seguimiento_hasta', v_ahora,
      'origen_filtrado', p_origen,
      'atribucion', 'primer_analista',
      'leads_base', r.leads,
      'leads_con_cita_real', r.leads_con_cita_real,
      'citas_realizadas', r.citas_realizadas_reales,
      'citas_anteriores_al_alta', r.citas_anteriores_al_alta,
      'pct_llegadas_con_cita_real', case when r.leads > 0
        then round(100.0 * r.leads_con_cita_real / r.leads, 1) end
    ),
    'conversion_operaciones', jsonb_build_object(
      'version', 1,
      'lectura', 'viva',
      'completo', true,
      'desde', p_desde,
      'hasta', p_hasta,
      'zona', 'America/Lima',
      'origen_filtrado', null,
      'cantidad', (
        select count(*)::int from ep_flujo e where e.tipo = 'operacion'
      ),
      'aporte_total', (
        select coalesce(sum(e.aporte_numerador), 0)
        from ep_flujo e where e.tipo = 'operacion'
      ),
      'detalle', coalesce((
        select jsonb_agg(jsonb_build_object(
          'operacion_id', e.operacion_id,
          'analista_id', e.analista_id,
          'categoria', e.categoria,
          'periodo', e.mes_origen,
          'fecha_numerador', e.fecha_numerador,
          'aporte_numerador', e.aporte_numerador
        ) order by e.fecha_numerador, e.operacion_id)
        from ep_flujo e
        where e.tipo = 'operacion' and e.operacion_id is not null
      ), '[]'::jsonb)
    ),
    'cierres_por_semana', jsonb_build_object(
      'version', 1,
      'desde', p_desde,
      'hasta', p_hasta,
      'base', 'fecha_numerador',
      'atribucion', 'autor_cierre',
      'agrupacion', 'bloques_7_dias_desde_inicio',
      'zona', 'America/Lima',
      'origen_filtrado', p_origen,
      'incluye_operaciones_cartera', false,
      'cierres', (
        select count(distinct e.lead_id)::int
        from ep_flujo e
        where e.tipo = 'cierre' and not e.anulado
          and e.origen in ('landing', 'formulario', 'referido')
          and (p_origen is null or e.origen = p_origen)
      ),
      'aporte_cierres', (
        select coalesce(sum(e.aporte_numerador), 0)
        from ep_flujo e
        where e.tipo = 'cierre' and not e.anulado
          and e.origen in ('landing', 'formulario', 'referido')
          and (p_origen is null or e.origen = p_origen)
      ),
      -- El total global conserva cierres de bajas, supervisores o autor nulo,
      -- mientras responsables[] sólo enumera vendedores activos. El residual
      -- hace visible esa diferencia sin reasignar el cierre a otra persona.
      'cierres_fuera_del_roster', (
        select count(distinct e.lead_id)::int
        from ep_flujo e
        where e.tipo = 'cierre' and not e.anulado
          and e.origen in ('landing', 'formulario', 'referido')
          and (p_origen is null or e.origen = p_origen)
          and (e.analista_id is null or not exists (
            select 1 from vendedores_base vb
            where vb.vendedor_id = e.analista_id
          ))
      ),
      'aporte_cierres_fuera_del_roster', (
        select coalesce(sum(e.aporte_numerador), 0)
        from ep_flujo e
        where e.tipo = 'cierre' and not e.anulado
          and e.origen in ('landing', 'formulario', 'referido')
          and (p_origen is null or e.origen = p_origen)
          and (e.analista_id is null or not exists (
            select 1 from vendedores_base vb
            where vb.vendedor_id = e.analista_id
          ))
      ),
      'semanas', coalesce((
        select jsonb_agg(jsonb_build_object(
          'semana', semanal.semana,
          'desde', semanal.desde,
          'hasta', semanal.hasta,
          'cierres', semanal.cierres,
          'aporte_cierres', semanal.aporte_cierres,
          'cierres_fuera_del_roster', semanal.cierres_fuera_del_roster,
          'aporte_cierres_fuera_del_roster', semanal.aporte_cierres_fuera_del_roster
        ) order by semanal.semana)
        from (
          select gs.semana_indice + 1 as semana,
            p_desde + (gs.semana_indice * 7) as desde,
            least(p_hasta, p_desde + (gs.semana_indice * 7) + 6) as hasta,
            count(distinct e.lead_id)::int as cierres,
            coalesce(sum(e.aporte_numerador), 0) as aporte_cierres,
            count(distinct e.lead_id) filter (
              where e.analista_id is null or not exists (
                select 1 from vendedores_base vb
                where vb.vendedor_id = e.analista_id
              )
            )::int as cierres_fuera_del_roster,
            coalesce(sum(e.aporte_numerador) filter (
              where e.analista_id is null or not exists (
                select 1 from vendedores_base vb
                where vb.vendedor_id = e.analista_id
              )
            ), 0) as aporte_cierres_fuera_del_roster
          from generate_series(
            0, ((p_hasta - p_desde) / 7)
          ) as gs(semana_indice)
          left join ep_flujo e
            on e.tipo = 'cierre' and not e.anulado
           and e.origen in ('landing', 'formulario', 'referido')
           and (p_origen is null or e.origen = p_origen)
           and (e.fecha_numerador at time zone 'America/Lima')::date
               between p_desde + (gs.semana_indice * 7)
                   and least(p_hasta, p_desde + (gs.semana_indice * 7) + 6)
          group by gs.semana_indice
        ) semanal
      ), '[]'::jsonb)
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
        'leads_con_cita_real', o.leads_con_cita_real,
        'citas_realizadas', o.citas_realizadas_reales,
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
        'leads_con_cita_real', rr.leads_con_cita_real,
        'citas_realizadas', rr.citas_realizadas_reales,
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
        'cierres_por_semana', coalesce((
          select jsonb_agg(jsonb_build_object(
            'semana', cierre_semanal.semana,
            'desde', cierre_semanal.desde,
            'hasta', cierre_semanal.hasta,
            'cierres', cierre_semanal.cierres,
            'aporte_cierres', cierre_semanal.aporte_cierres
          ) order by cierre_semanal.semana)
          from (
            select gs.semana_indice + 1 as semana,
              p_desde + (gs.semana_indice * 7) as desde,
              least(p_hasta, p_desde + (gs.semana_indice * 7) + 6) as hasta,
              count(distinct e.lead_id)::int as cierres,
              coalesce(sum(e.aporte_numerador), 0) as aporte_cierres
            from generate_series(
              0, ((p_hasta - p_desde) / 7)
            ) as gs(semana_indice)
            left join ep_flujo e
              on e.tipo = 'cierre' and not e.anulado
             and e.origen in ('landing', 'formulario', 'referido')
             and e.analista_id = rr.vendedor_id
             and (p_origen is null or e.origen = p_origen)
             and (e.fecha_numerador at time zone 'America/Lima')::date
                 between p_desde + (gs.semana_indice * 7)
                     and least(p_hasta, p_desde + (gs.semana_indice * 7) + 6)
            group by gs.semana_indice
          ) cierre_semanal
        ), '[]'::jsonb),
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

  -- ══ OLA 1b · LA SUSTITUCION ════════════════════════════════════════════
  -- REGLA DE MIGUEL (21/09/2026): mes calendario completo y sin filtro de
  -- fuente -> la cifra la sirve `crm.conversion_mensual_fn`. Cualquier otro
  -- caso -> calculo en vivo, DECLARADO.
  --
  -- Aqui se cumple la primera mitad. Lo de arriba sigue calculandose igual y
  -- sigue alimentando `sondas.paridad_nucleo`; lo que cambia es QUE SE PUBLICA
  -- en las tres claves de la cifra cuando la condicion se da.
  --
  -- Por que la oficial y no un recalculo: la mensual sabe hacer dos cosas que
  -- esta puerta no hace y no debe aprender —servir la FOTO SELLADA de un mes
  -- cerrado, y restar la deuda de los cierres anulados de un mes ya sellado—.
  -- Duplicar esas dos reglas aqui seria crear la tercera copia; pedirselas es
  -- lo que hace que la cifra sea UNA.
  --
  -- Su gate es MAS ANCHO que el de esta funcion (vendedor/supervisor/gerencia/
  -- lector global frente a gerencia/lector global), asi que quien llega hasta
  -- aqui siempre pasa el suyo: no se abre ninguna puerta. Y como recorta por
  -- `auth.uid()`, el alcance del que pregunta se respeta —aqui, gerencia, que
  -- es global—.
  if v_periodo is not null and p_origen is null then
    v_oficial := crm.conversion_mensual_fn(v_periodo);
    v_payload := jsonb_set(v_payload, '{nucleo}',
      (v_payload -> 'nucleo') || jsonb_build_object(
        'fuente', 'mensual',
        -- Ahora SI se sabe si el mes esta sellado, porque lo dice la oficial.
        'sellado', coalesce((v_oficial #>> '{cierre,cerrado}')::boolean, false),
        -- La lectura mensual descuenta la deuda por cierres anulados.
        'ajuste_aplicado', true,
        'divisor', v_oficial #> '{total,divisor}',
        'numerador', v_oficial #> '{total,numerador}',
        'conversion_pct', v_oficial #> '{total,conversion_pct}',
        -- 🔑 LA PONDERACION DE LA FOTO, al lado de la cifra de la foto. Cierra
        -- el P2 de Codex (23/09): una cifra sellada no puede publicarse sin
        -- decir con que pesos se calculo.
        --
        -- 🔴 ADITIVA, no sustitutiva, y eso es deliberado. La primera version
        -- movia `peso_referido`/`peso_renovacion` al peso sellado, y Codex lo
        -- refuto en la segunda vuelta con un contraejemplo: esas dos claves
        -- ROTULAN EL DESGLOSE (`conversion-vendedores.ts:258,272`), que se
        -- recalcula vivo. Un cliente con bundle viejo —que no conoce esta clave
        -- nueva— habria rotulado con el peso de la foto un desglose calculado
        -- con el peso de hoy. El servidor anterior publicaba ahi el vivo y
        -- acertaba: era una REGRESION. Asi, quien no conozca
        -- `ponderacion_oficial` ve exactamente lo de siempre.
        'ponderacion_oficial', v_oficial #> '{ponderacion}',
        -- Lo que ESTA funcion habria publicado, conservado al lado. Sin esto,
        -- la distancia entre la cifra oficial y el recalculo vivo solo se podria
        -- DEDUCIR de una igualdad que la propia delegacion rompe
        -- (`conversion-vendedores.ts:183` compara el divisor del paquete sin
        -- filtro contra el de los paquetes CON filtro, que no delegan). Con
        -- `recalculo_vivo` la pantalla puede decir «4,16 % oficial · 4,32 %
        -- recalculado» en vez de quedarse en blanco.
        -- Cabe sin romper nada: `NucleoConversionesSchema` del front es
        -- `v.object` (`app/src/lib/metricas-conversiones.ts`), que ignora lo
        -- que no conoce.
        'recalculo_vivo', jsonb_build_object(
          'divisor', v_payload #> '{nucleo,divisor}',
          'numerador', v_payload #> '{nucleo,numerador}',
          'conversion_pct', v_payload #> '{nucleo,conversion_pct}')
      ), false);
  end if;
  -- Fuera de esa condicion no se toca nada: el bloque sigue diciendo
  -- `fuente: rango_vivo`, `sellado: null`, `ajuste_aplicado: false`, que es la
  -- verdad de un rango libre o de una consulta con filtro de origen.

  return v_payload;
end;
$function$;

comment on function private.metricas_conversiones_implementacion(date, date, text) is
  'Motor de la conversion que publica crm.metricas_conversiones_fn. Desde la Ola 1b (22/09/2026) aplica la regla de Miguel del 21/09: si el rango es un mes calendario completo y no hay filtro de origen, DELEGA divisor, numerador y conversion_pct en crm.conversion_mensual_fn —la unica capa que sabe servir la foto sellada de un mes cerrado y restar la deuda de los cierres anulados— y lo declara con fuente=mensual, sellado=<lo que diga la oficial> y ajuste_aplicado=true. En cualquier otro caso calcula en vivo sobre conversion_episodios y lo declara con fuente=rango_vivo, sellado=null y ajuste_aplicado=false. Los recuentos descriptivos del bloque siguen siendo siempre los del calculo en vivo.';

update private.analitica_leads_citas_exenciones e
   set huella = md5(regexp_replace(regexp_replace(
                      lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
                      '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')),
       razon  = 'CONSUME EL NUCLEO DE CONVERSION Y EL NUCLEO DE CITAS. Conserva el embudo histórico por cohorte y añade contratos explícitos: llegadas únicas con cita realizada, operaciones seleccionadas por el núcleo vivo y cierres por su fecha real. No calcula pesos ni elige operaciones localmente. F4 publicada: contratos cooperativos por fecha de imputación y rastro por cierre inicial. Conserva los núcleos de conversión, citas y capital y sus fórmulas. Ola 1a (22/09/2026): DECLARA su fuente sin sustituir la cifra (es_mes_calendario, fuente=rango_vivo, sellado=null, ajuste_aplicado=false). Su conversion_pct sigue saliendo de su propia division sobre ep_flujo; la sustitucion por crm.conversion_mensual_fn va en un paquete aparte. Ola 1b (22/09/2026): cuando el rango es un mes calendario completo y no hay filtro de origen, DELEGA divisor, numerador y conversion_pct en crm.conversion_mensual_fn (fuente=mensual, sellado=<lo que diga la oficial>, ajuste_aplicado=true). Fuera de esa condicion sigue calculando en vivo y lo declara. 23/09/2026: el peso de la RENOVACION se guarda con la foto (cerrar_periodo) o se declara tal como se aplica (las dos puertas), en vez de reconstruirse desde el del referido.'
  from pg_proc p
 where p.oid = to_regprocedure(e.objeto)
   and e.objeto = 'private.metricas_conversiones_implementacion(date,date,text)';

update private.analitica_lc_sello
   set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
 where id;

do $postflight$
begin
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p
       where p.oid = 'private.metricas_conversiones_implementacion(date,date,text)'::regprocedure)
     is distinct from '1af7e330fb79341a10b088d6011b1ae0' then
    raise exception 'REVERSA: el cuerpo no volvio al exacto de antes';
  end if;
  if (select e.huella from private.analitica_leads_citas_exenciones e
       where e.objeto = 'private.metricas_conversiones_implementacion(date,date,text)')
     is distinct from '6dc8df003cdf50292453c31870e21535' then
    raise exception 'REVERSA: la huella del censo no volvio a la de antes';
  end if;
  if private.assert_analitica_leads_citas() not like 'OK:%' then
    raise exception 'REVERSA: el trinquete quedo en rojo';
  end if;
end;
$postflight$;

commit;

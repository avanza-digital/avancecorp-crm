-- REQ-GER-MET-001 — contrato único de cuatro datos para Gerencia.
--
-- Alcance:
--   N1 llegadas únicas con una cita registrada como realizada;
--   N2 divisor y exclusiones exactas del porcentaje por modalidad;
--   N3 operaciones seleccionadas por el núcleo vivo y su aporte;
--   N4 cierres agrupados por la fecha real del cierre.
--
-- No crea RPC ni calculadoras. No modifica conversion_episodios,
-- citas_episodios, capital_episodios ni las fachadas crm.*.
--
-- Estado heredado medido el 05/09/2026: el censo global ya está rojo por
-- contadores ajenos a este requerimiento y por exenciones caducas. Esta
-- migración no los repara ni los re-sella. Toma una fotografía del censo
-- ajeno y exige igualdad exacta al terminar; sólo pueden cambiar los dos
-- agregadores declarados abajo.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- Evita que dos publicaciones de analítica alteren simultáneamente el censo.
select pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtext('private.analitica_leads_citas_exenciones'),
  pg_catalog.hashtext('REQ-GER-MET-001')
);
lock table private.analitica_leads_citas_exenciones in share row exclusive mode;
lock table private.analitica_lc_sello in share row exclusive mode;

-- =====================================================================
-- 0) PREFLIGHT: cuerpos, núcleos, fachadas, ACL y declaraciones exactas.
-- =====================================================================
do $$
declare
  v_h text;
  v_acl text;
begin
  select md5(pg_get_functiondef(
    'private.metricas_conversiones_implementacion(date,date,text)'::regprocedure
  )) into v_h;
  if v_h is distinct from '372a4cfaf71bbbfcc1c921ca48096125' then
    raise exception 'REQ-GER-MET-001 preflight: cambió el agregador de conversión (%)', v_h;
  end if;

  select md5(pg_get_functiondef(
    'private.metricas_reuniones_implementacion(date,date)'::regprocedure
  )) into v_h;
  if v_h is distinct from '7f4f885e2d044afdd2fd0766991517a0' then
    raise exception 'REQ-GER-MET-001 preflight: cambió el agregador de reuniones (%)', v_h;
  end if;

  select md5(pg_get_functiondef(
    'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure
  )) into v_h;
  if v_h is distinct from '8a2549dbfa59c732da04900ed90b6361' then
    raise exception 'REQ-GER-MET-001 preflight: cambió el núcleo de conversión (%)', v_h;
  end if;

  select md5(pg_get_functiondef(
    'private.citas_episodios(timestamptz,timestamptz,timestamptz)'::regprocedure
  )) into v_h;
  if v_h is distinct from 'ea636888a266941e959f26c6a5727216' then
    raise exception 'REQ-GER-MET-001 preflight: cambió el núcleo de citas (%)', v_h;
  end if;

  select md5(pg_get_functiondef(
    'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure
  )) into v_h;
  if v_h is distinct from 'b8f375fbb377582835f4cfe222240c5b' then
    raise exception 'REQ-GER-MET-001 preflight: cambió el núcleo de capital (%)', v_h;
  end if;

  select md5(pg_get_functiondef(
    'crm.metricas_conversiones_fn(date,date,text)'::regprocedure
  )) into v_h;
  if v_h is distinct from '5edb160355011bd0485661485c9317df' then
    raise exception 'REQ-GER-MET-001 preflight: cambió la fachada de conversión (%)', v_h;
  end if;

  select md5(pg_get_functiondef(
    'crm.metricas_reuniones_fn(date,date)'::regprocedure
  )) into v_h;
  if v_h is distinct from 'de328143bd9221fb19bfa6af46695290' then
    raise exception 'REQ-GER-MET-001 preflight: cambió la fachada de reuniones (%)', v_h;
  end if;

  select pg_get_userbyid(p.proowner) || '/' || p.proacl::text into v_acl
  from pg_proc p
  where p.oid =
    'private.metricas_conversiones_implementacion(date,date,text)'::regprocedure;
  if v_acl is distinct from 'postgres/{postgres=X/postgres}' then
    raise exception 'REQ-GER-MET-001 preflight: propietario/ACL inesperado en conversión (%)', v_acl;
  end if;

  select pg_get_userbyid(p.proowner) || '/' || p.proacl::text into v_acl
  from pg_proc p
  where p.oid =
    'private.metricas_reuniones_implementacion(date,date)'::regprocedure;
  if v_acl is distinct from 'postgres/{postgres=X/postgres}' then
    raise exception 'REQ-GER-MET-001 preflight: propietario/ACL inesperado en reuniones (%)', v_acl;
  end if;

  select string_agg(
    p.oid::regprocedure::text || '=' || pg_get_userbyid(p.proowner)
      || '/' || coalesce(p.proacl::text, '<NULL>'),
    ', ' order by p.oid::regprocedure::text
  ) into v_acl
  from (values
    ('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure,
     '{postgres=X/postgres}'::text),
    ('private.citas_episodios(timestamptz,timestamptz,timestamptz)'::regprocedure,
     '{postgres=X/postgres}'::text),
    ('private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure,
     '{postgres=X/postgres}'::text),
    ('crm.metricas_conversiones_fn(date,date,text)'::regprocedure,
     '{postgres=X/postgres,authenticated=X/postgres}'::text),
    ('crm.metricas_reuniones_fn(date,date)'::regprocedure,
     '{postgres=X/postgres,authenticated=X/postgres}'::text)
  ) esperado(objeto, acl)
  join pg_proc p on p.oid = esperado.objeto
  where pg_get_userbyid(p.proowner) <> 'postgres'
     or p.proacl::text is distinct from esperado.acl;
  if v_acl is not null then
    raise exception 'REQ-GER-MET-001 preflight: propietario/ACL inesperado en dependencias (%)', v_acl;
  end if;

  if (select count(*) from private.analitica_leads_citas_exenciones
      where objeto in (
        'private.metricas_conversiones_implementacion(date,date,text)',
        'private.metricas_reuniones_implementacion(date,date)'
      )) <> 2 then
    raise exception 'REQ-GER-MET-001 preflight: faltan declaraciones de los agregadores';
  end if;

  if (select huella from private.analitica_leads_citas_exenciones
      where objeto =
        'private.metricas_conversiones_implementacion(date,date,text)')
     is distinct from '081face102b1b9e39b0ecc29d0eb50e0' then
    raise exception 'REQ-GER-MET-001 preflight: cambió la declaración heredada de conversión';
  end if;

  if (select huella from private.analitica_leads_citas_exenciones
      where objeto =
        'private.metricas_reuniones_implementacion(date,date)')
     is distinct from 'd94f54fb29b8ea11dfd84f107684c326' then
    raise exception 'REQ-GER-MET-001 preflight: cambió la declaración de reuniones';
  end if;

  -- La lista estaba sellada aunque el censo global no estuviera verde.
  if (select sello from private.analitica_lc_sello where id)
     is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'REQ-GER-MET-001 preflight: la lista de exenciones ya no conserva su sello';
  end if;
end $$;

create temporary table gerencia_censo_ajeno_pre
on commit drop
as
select tipo, objeto, declarada, huella_ok
from private.contadores_crudos_leads_citas()
where objeto not in (
  'private.metricas_conversiones_implementacion(date,date,text)',
  'private.metricas_reuniones_implementacion(date,date)'
);

-- =====================================================================
-- 1) AMPLIAR los dos agregadores existentes.
-- =====================================================================
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

  return v_payload;
end;
$function$;


-- Privadas igual que antes: sólo el propietario postgres puede ejecutarlas.
revoke all on function
  private.metricas_conversiones_implementacion(date,date,text)
  from public, anon, authenticated, service_role;
grant execute on function
  private.metricas_conversiones_implementacion(date,date,text)
  to postgres;

CREATE OR REPLACE FUNCTION private.metricas_reuniones_implementacion(p_desde date, p_hasta date)
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
  v_ahora timestamptz := now();
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

  with cierres_del_nucleo as materialized (
    -- F2.5: los cierres que el NUCLEO reconoce (sin anulados), de la
    -- tabla-base. La ventana llega hasta `ahora` porque una reunion del rango
    -- puede acabar en cierre despues; ese cierre sigue siendo suyo.
    select distinct e.lead_id, min(e.fecha_numerador) as cerrado_en
    from private.conversion_episodios(
      v_ini, greatest(v_fin, v_ahora), null::date, true, '{}'::uuid[],
      private.peso_referido_conversion(date_trunc('month', p_hasta)::date)
    ) e
    where e.tipo = 'cierre' and not e.anulado and e.lead_id is not null
    group by e.lead_id
  ),
  base as materialized (
    select t.*, ce.modalidad as modalidad,
      coalesce(l.origen, 'sin_origen') as origen,
      l.perfil_id as cliente_id, l.contrato_id, l.convertido_en,
      case when l.moneda = 'USD' then c.capital_usd_nucleo else c.capital_pen_nucleo end as capital,
      l.moneda, c.contrato_creado_en_nucleo as contrato_creado_en,
      coalesce(p.nombre_completo, 'Sin responsable') as responsable_nombre,
      e.rol_crm, e.supervisor_id,
      coalesce(ps.nombre_completo, 'Sin equipo') as supervisor_nombre,
      ce.debio_ocurrir as metrica_debio_ocurrir,
      ce.realizada as metrica_realizada,
      ce.no_show as metrica_no_show,
      ce.cancelada_asesor as metrica_cancelada_asesor,
      ce.cancelada_sistema as metrica_cancelada_sistema,
      ce.reprogramada as metrica_reprogramada,
      ce.pendiente_cierre as metrica_pendiente_cierre,
      ce.programada_futura as metrica_programada_futura
    from private.citas_episodios(v_ini, v_fin, v_ahora) ce
    join crm.tareas t on t.id = ce.tarea_id
    left join crm.leads l on l.id = t.lead_id
    left join lateral (
      -- F4.i: el capital VIVO del lead, del NUCLEO (misma regla que el panel
      -- de Conversiones): contratos del perfil + cooperativas del lead. El
      -- enlace leads.contrato_id jamas se rello (0/466) y por eso esta
      -- pantalla mostro capital 0 SIEMPRE.
      select sum(k.monto) filter (where k.moneda='PEN') as capital_pen_nucleo,
             sum(k.monto) filter (where k.moneda='USD') as capital_usd_nucleo,
             min(k.fecha) as contrato_creado_en_nucleo
      from private.capital_episodios('-infinity'::timestamptz,'infinity'::timestamptz,true,'{}'::uuid[]) k
      where k.medida = 'stock'
        and ((k.tipo like 'contrato_%' and k.cliente_id = l.perfil_id)
          or (k.tipo = 'cooperativa' and k.lead_id = l.id))
    ) c on true
    left join public.perfiles p on p.id = t.vendedor_id
    left join crm.equipo e on e.perfil_id = t.vendedor_id
    left join public.perfiles ps on ps.id = e.supervisor_id
  ),
  ultima_realizada as materialized (
    select distinct on (lead_id)
      lead_id, modalidad, origen, vendedor_id, responsable_nombre,
      supervisor_id, supervisor_nombre, cliente_id, contrato_id, convertido_en,
      capital, moneda, contrato_creado_en, vence_en,
      -- ANTES: `cliente_id is not null and convertido_en >= vence_en` (la
      -- ficha del lead) y la columna de contrato enlazado, que nadie rellena
      -- — por eso «terminan en contrato» valia 0 SIEMPRE.
      -- AHORA: el cierre del LEDGER, sin anulados, ocurrido despues de la
      -- reunion. Es la misma verdad que HOY, Ranking, Conversiones y
      -- Distribucion. Las dos banderas miden ya lo mismo: en este CRM el
      -- cierre ES el hecho; el enlace al contrato no existe (se rotula en F3).
      exists (select 1 from cierres_del_nucleo cn
               where cn.lead_id = base.lead_id and cn.cerrado_en >= base.vence_en)
        as metrica_conversion_cliente,
      exists (select 1 from cierres_del_nucleo cn
               where cn.lead_id = base.lead_id and cn.cerrado_en >= base.vence_en)
        as metrica_conversion_contrato
    from base
    where metrica_realizada and lead_id is not null
    order by lead_id, vence_en desc, id desc
  ),
  resumen as (
    select count(*)::int as pactadas,
      count(*) filter (where metrica_debio_ocurrir)::int as debieron_ocurrir,
      count(*) filter (where metrica_realizada)::int as realizadas,
      count(*) filter (where metrica_no_show)::int as no_show,
      count(*) filter (where metrica_cancelada_asesor)::int as canceladas,
      count(*) filter (where metrica_cancelada_sistema)::int as canceladas_sistema,
      count(*) filter (where metrica_reprogramada)::int as reprogramadas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_sistema
      )::int as canceladas_sistema_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_reprogramada
      )::int as reprogramadas_vencidas,
      count(*) filter (where metrica_pendiente_cierre)::int as pendientes_cierre,
      count(*) filter (where metrica_programada_futura)::int as programadas_futuras
    from base
  ),
  modalidad_base as (
    select modalidad,
      count(*)::int as pactadas,
      count(*) filter (where metrica_debio_ocurrir)::int as debieron_ocurrir,
      count(*) filter (where metrica_realizada)::int as realizadas,
      count(*) filter (where metrica_no_show)::int as no_show,
      count(*) filter (where metrica_cancelada_asesor)::int as canceladas,
      count(*) filter (where metrica_reprogramada)::int as reprogramadas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_sistema
      )::int as canceladas_sistema_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_reprogramada
      )::int as reprogramadas_vencidas,
      count(*) filter (where metrica_pendiente_cierre)::int as pendientes_cierre
    from base group by modalidad
  ),
  modalidad_conversion as (
    select modalidad,
      count(*)::int as leads_reunidos,
      count(*) filter (where metrica_conversion_cliente)::int as clientes,
      count(*) filter (where metrica_conversion_contrato)::int as contratos,
      coalesce(sum(capital) filter (where metrica_conversion_contrato and moneda = 'PEN'),0) as capital_pen,
      coalesce(sum(capital) filter (where metrica_conversion_contrato and moneda = 'USD'),0) as capital_usd
    from ultima_realizada group by modalidad
  ),
  origen_base as (
    select origen,
      count(*)::int as pactadas,
      count(*) filter (where metrica_debio_ocurrir)::int as debieron_ocurrir,
      count(*) filter (where metrica_realizada)::int as realizadas,
      count(*) filter (where metrica_no_show)::int as no_show,
      count(*) filter (where metrica_cancelada_asesor)::int as canceladas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_sistema
      )::int as canceladas_sistema_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_reprogramada
      )::int as reprogramadas_vencidas
    from base group by origen
  ),
  origen_conversion as (
    select origen,
      count(*)::int as leads_reunidos,
      count(*) filter (where metrica_conversion_cliente)::int as clientes,
      count(*) filter (where metrica_conversion_contrato)::int as contratos
    from ultima_realizada group by origen
  ),
  responsables as (
    select vendedor_id, responsable_nombre, rol_crm, supervisor_id, supervisor_nombre,
      count(*)::int as pactadas,
      count(*) filter (where metrica_debio_ocurrir)::int as debieron_ocurrir,
      count(*) filter (where metrica_realizada)::int as realizadas,
      count(*) filter (where metrica_no_show)::int as no_show,
      count(*) filter (where metrica_cancelada_asesor)::int as canceladas,
      count(*) filter (where metrica_reprogramada)::int as reprogramadas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_sistema
      )::int as canceladas_sistema_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_cancelada_asesor
          and cancelada_por_id is distinct from vendedor_id
      )::int as canceladas_ajenas_vencidas,
      count(*) filter (
        where metrica_debio_ocurrir and metrica_reprogramada
      )::int as reprogramadas_vencidas,
      count(*) filter (where metrica_pendiente_cierre)::int as pendientes_cierre
    from base
    group by vendedor_id, responsable_nombre, rol_crm, supervisor_id, supervisor_nombre
  ),
  resultados as (
    select coalesce(resultado_reunion, 'sin_clasificar') as resultado,
      count(*)::int as cantidad
    from base where metrica_realizada
    group by coalesce(resultado_reunion, 'sin_clasificar')
  ),
  conversion_global as (
    select count(*)::int as leads_reunidos,
      count(*) filter (where metrica_conversion_cliente)::int as clientes,
      count(*) filter (where metrica_conversion_contrato)::int as contratos,
      coalesce(sum(capital) filter (where metrica_conversion_contrato and moneda = 'PEN'),0) as capital_pen,
      coalesce(sum(capital) filter (where metrica_conversion_contrato and moneda = 'USD'),0) as capital_usd
    from ultima_realizada
  )
  select jsonb_build_object(
    'version', 1, 'generado_en', now(),
    'periodo', jsonb_build_object(
      'desde', p_desde, 'hasta', p_hasta,
      'dias', (p_hasta-p_desde)+1, 'zona', 'America/Lima'
    ),
    'resumen', jsonb_build_object(
      'pactadas', r.pactadas, 'debieron_ocurrir', r.debieron_ocurrir,
      'realizadas', r.realizadas, 'no_concretadas', r.no_show+r.canceladas,
      'no_show', r.no_show, 'canceladas', r.canceladas,
      'canceladas_sistema', r.canceladas_sistema,
      'reprogramadas', r.reprogramadas,
      'pendientes_cierre', r.pendientes_cierre,
      'programadas_futuras', r.programadas_futuras,
      'pct_realizacion', case
        when r.debieron_ocurrir-r.canceladas_sistema_vencidas-r.reprogramadas_vencidas > 0
        then round(
          100.0*r.realizadas
          /(r.debieron_ocurrir-r.canceladas_sistema_vencidas-r.reprogramadas_vencidas),
          1
        )
      end,
      'pct_asistencia', case when r.realizadas+r.no_show > 0
        then round(100.0*r.realizadas/(r.realizadas+r.no_show),1) end
    ),
    'conversion', jsonb_build_object(
      'leads_reunidos', cg.leads_reunidos, 'clientes', cg.clientes,
      'contratos', cg.contratos,
      'conversion_cliente_pct', case when cg.leads_reunidos > 0 then round(100.0*cg.clientes/cg.leads_reunidos,1) end,
      'conversion_contrato_pct', case when cg.leads_reunidos > 0 then round(100.0*cg.contratos/cg.leads_reunidos,1) end,
      'capital_pen', cg.capital_pen, 'capital_usd', cg.capital_usd
    ),
    'modalidades', coalesce((select jsonb_agg(jsonb_build_object(
      'modalidad', mb.modalidad, 'pactadas', mb.pactadas,
      'debieron_ocurrir', mb.debieron_ocurrir, 'realizadas', mb.realizadas,
      'no_concretadas', mb.no_show+mb.canceladas, 'no_show', mb.no_show,
      'canceladas', mb.canceladas, 'reprogramadas', mb.reprogramadas,
      'divisor_realizacion',
        mb.debieron_ocurrir-mb.canceladas_sistema_vencidas-mb.reprogramadas_vencidas,
      'canceladas_sistema_vencidas', mb.canceladas_sistema_vencidas,
      'reprogramadas_vencidas', mb.reprogramadas_vencidas,
      'pendientes_cierre', mb.pendientes_cierre,
      'pct_realizacion', case
        when mb.debieron_ocurrir-mb.canceladas_sistema_vencidas-mb.reprogramadas_vencidas > 0
        then round(
          100.0*mb.realizadas
          /(mb.debieron_ocurrir-mb.canceladas_sistema_vencidas-mb.reprogramadas_vencidas),
          1
        )
      end,
      'pct_asistencia', case when mb.realizadas+mb.no_show > 0 then round(100.0*mb.realizadas/(mb.realizadas+mb.no_show),1) end,
      'leads_reunidos', coalesce(mc.leads_reunidos,0),
      'clientes', coalesce(mc.clientes,0), 'contratos', coalesce(mc.contratos,0),
      'conversion_cliente_pct', case when coalesce(mc.leads_reunidos,0)>0 then round(100.0*mc.clientes/mc.leads_reunidos,1) end,
      'conversion_contrato_pct', case when coalesce(mc.leads_reunidos,0)>0 then round(100.0*mc.contratos/mc.leads_reunidos,1) end,
      'capital_pen', coalesce(mc.capital_pen,0), 'capital_usd', coalesce(mc.capital_usd,0)
    ) order by case mb.modalidad when 'presencial' then 1 when 'virtual' then 2 else 3 end)
      from modalidad_base mb left join modalidad_conversion mc using (modalidad)), '[]'::jsonb),
    'origenes', coalesce((select jsonb_agg(jsonb_build_object(
      'origen', ob.origen, 'pactadas', ob.pactadas, 'realizadas', ob.realizadas,
      'no_show', ob.no_show, 'canceladas', ob.canceladas,
      'pct_realizacion', case
        when ob.debieron_ocurrir-ob.canceladas_sistema_vencidas-ob.reprogramadas_vencidas > 0
        then round(
          100.0*ob.realizadas
          /(ob.debieron_ocurrir-ob.canceladas_sistema_vencidas-ob.reprogramadas_vencidas),
          1
        )
      end,
      'leads_reunidos', coalesce(oc.leads_reunidos,0),
      'clientes', coalesce(oc.clientes,0), 'contratos', coalesce(oc.contratos,0),
      'conversion_contrato_pct', case when coalesce(oc.leads_reunidos,0)>0 then round(100.0*oc.contratos/oc.leads_reunidos,1) end
    ) order by ob.realizadas desc, ob.pactadas desc, ob.origen)
      from origen_base ob left join origen_conversion oc using (origen)), '[]'::jsonb),
    'responsables', coalesce((select jsonb_agg(jsonb_build_object(
      'responsable_id', rr.vendedor_id, 'nombre', rr.responsable_nombre,
      'rol', rr.rol_crm, 'supervisor_id', rr.supervisor_id,
      'supervisor_nombre', rr.supervisor_nombre,
      'pactadas', rr.pactadas, 'realizadas', rr.realizadas,
      'no_show', rr.no_show, 'canceladas', rr.canceladas,
      'reprogramadas', rr.reprogramadas,
      'pendientes_cierre', rr.pendientes_cierre,
      'pct_realizacion', case
        when rr.debieron_ocurrir-rr.canceladas_sistema_vencidas
          -rr.canceladas_ajenas_vencidas-rr.reprogramadas_vencidas > 0
        then round(
          100.0*rr.realizadas
          /(rr.debieron_ocurrir-rr.canceladas_sistema_vencidas
            -rr.canceladas_ajenas_vencidas-rr.reprogramadas_vencidas),
          1
        )
      end
    ) order by rr.realizadas desc, rr.pactadas desc, rr.responsable_nombre) from responsables rr), '[]'::jsonb),
    'resultados', coalesce((select jsonb_agg(jsonb_build_object(
      'resultado', resultado, 'cantidad', cantidad
    ) order by cantidad desc, resultado) from resultados), '[]'::jsonb)
  ) into v_payload
  from resumen r cross join conversion_global cg;

  return v_payload;
end;
$function$;

-- Privada igual que antes.
revoke all on function
  private.metricas_reuniones_implementacion(date,date)
  from public, anon, authenticated, service_role;
grant execute on function
  private.metricas_reuniones_implementacion(date,date)
  to postgres;

-- =====================================================================
-- 2) RE-SELLAR exclusivamente los dos agregadores que sí cambiaron.
-- =====================================================================
do $$
declare
  v_filas integer;
begin
  update private.analitica_leads_citas_exenciones e
     set huella = (
       select md5(regexp_replace(regexp_replace(
         lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
         '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
       from pg_proc p
       where p.oid = e.objeto::regprocedure
     ),
         razon = case e.objeto
           when 'private.metricas_conversiones_implementacion(date,date,text)'
             then 'CONSUME EL NUCLEO DE CONVERSION Y EL NUCLEO DE CITAS. Conserva el embudo histórico por cohorte y añade contratos explícitos: llegadas únicas con cita realizada, operaciones seleccionadas por el núcleo vivo y cierres por su fecha real. No calcula pesos ni elige operaciones localmente.'
           when 'private.metricas_reuniones_implementacion(date,date)'
             then 'CONSUME LOS DOS NUCLEOS (citas_episodios para banderas, conversion_episodios para cierres): agrega filas ya servidas por los núcleos y expone el divisor y sus exclusiones por modalidad; no reconstruye esas reglas.'
         end
   where e.objeto in (
     'private.metricas_conversiones_implementacion(date,date,text)',
     'private.metricas_reuniones_implementacion(date,date)'
   );
  get diagnostics v_filas = row_count;
  if v_filas <> 2 then
    raise exception 'REQ-GER-MET-001: se re-sellaron % agregadores, se esperaban 2', v_filas;
  end if;

  update private.analitica_lc_sello
     set sello = private.huella_exenciones_analitica_lc(),
         sellado_en = now()
   where id;
  if not found then
    raise exception 'REQ-GER-MET-001: no existe la fila única del sello';
  end if;
end $$;

-- =====================================================================
-- 3) POSTFLIGHT: cuerpos nuevos exactos y todo lo ajeno idéntico.
-- =====================================================================
do $$
declare
  v_h text;
  v_src text;
  v_acl text;
begin
  select md5(pg_get_functiondef(
    'private.metricas_conversiones_implementacion(date,date,text)'::regprocedure
  )) into v_h;
  if v_h is distinct from 'be4e1c283a1f3042828cbb8c66332252' then
    raise exception 'REQ-GER-MET-001 postflight: cuerpo inesperado en conversión (%)', v_h;
  end if;

  select md5(pg_get_functiondef(
    'private.metricas_reuniones_implementacion(date,date)'::regprocedure
  )) into v_h;
  if v_h is distinct from '6e8935eae3cf1a4c049a93cb20e1f3bd' then
    raise exception 'REQ-GER-MET-001 postflight: cuerpo inesperado en reuniones (%)', v_h;
  end if;

  select p.prosrc into v_src
  from pg_proc p
  where p.oid =
    'private.metricas_conversiones_implementacion(date,date,text)'::regprocedure;
  if v_src is null
     or strpos(v_src, $k$'citas_reales'$k$) = 0
     or strpos(v_src, $k$'conversion_operaciones'$k$) = 0
     or strpos(v_src, $k$'cierres_por_semana'$k$) = 0 then
    raise exception 'REQ-GER-MET-001 postflight: falta N1, N3 o N4';
  end if;

  select p.prosrc into v_src
  from pg_proc p
  where p.oid =
    'private.metricas_reuniones_implementacion(date,date)'::regprocedure;
  if v_src is null
     or strpos(v_src, $k$'divisor_realizacion'$k$) = 0
     or strpos(v_src, $k$'canceladas_sistema_vencidas'$k$) = 0
     or strpos(v_src, $k$'reprogramadas_vencidas'$k$) = 0 then
    raise exception 'REQ-GER-MET-001 postflight: falta N2';
  end if;

  -- Los tres núcleos y las dos fachadas permanecen byte por byte.
  select md5(pg_get_functiondef(
    'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure
  )) into v_h;
  if v_h is distinct from '8a2549dbfa59c732da04900ed90b6361' then
    raise exception 'REQ-GER-MET-001 postflight: se alteró el núcleo de conversión';
  end if;
  select md5(pg_get_functiondef(
    'private.citas_episodios(timestamptz,timestamptz,timestamptz)'::regprocedure
  )) into v_h;
  if v_h is distinct from 'ea636888a266941e959f26c6a5727216' then
    raise exception 'REQ-GER-MET-001 postflight: se alteró el núcleo de citas';
  end if;
  select md5(pg_get_functiondef(
    'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure
  )) into v_h;
  if v_h is distinct from 'b8f375fbb377582835f4cfe222240c5b' then
    raise exception 'REQ-GER-MET-001 postflight: se alteró el núcleo de capital';
  end if;
  select md5(pg_get_functiondef(
    'crm.metricas_conversiones_fn(date,date,text)'::regprocedure
  )) into v_h;
  if v_h is distinct from '5edb160355011bd0485661485c9317df' then
    raise exception 'REQ-GER-MET-001 postflight: se alteró la fachada de conversión';
  end if;
  select md5(pg_get_functiondef(
    'crm.metricas_reuniones_fn(date,date)'::regprocedure
  )) into v_h;
  if v_h is distinct from 'de328143bd9221fb19bfa6af46695290' then
    raise exception 'REQ-GER-MET-001 postflight: se alteró la fachada de reuniones';
  end if;

  select pg_get_userbyid(p.proowner) || '/' || p.proacl::text into v_acl
  from pg_proc p
  where p.oid =
    'private.metricas_conversiones_implementacion(date,date,text)'::regprocedure;
  if v_acl is distinct from 'postgres/{postgres=X/postgres}' then
    raise exception 'REQ-GER-MET-001 postflight: propietario/ACL inesperado en conversión (%)', v_acl;
  end if;
  select pg_get_userbyid(p.proowner) || '/' || p.proacl::text into v_acl
  from pg_proc p
  where p.oid =
    'private.metricas_reuniones_implementacion(date,date)'::regprocedure;
  if v_acl is distinct from 'postgres/{postgres=X/postgres}' then
    raise exception 'REQ-GER-MET-001 postflight: propietario/ACL inesperado en reuniones (%)', v_acl;
  end if;

  select string_agg(
    p.oid::regprocedure::text || '=' || pg_get_userbyid(p.proowner)
      || '/' || coalesce(p.proacl::text, '<NULL>'),
    ', ' order by p.oid::regprocedure::text
  ) into v_acl
  from (values
    ('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure,
     '{postgres=X/postgres}'::text),
    ('private.citas_episodios(timestamptz,timestamptz,timestamptz)'::regprocedure,
     '{postgres=X/postgres}'::text),
    ('private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure,
     '{postgres=X/postgres}'::text),
    ('crm.metricas_conversiones_fn(date,date,text)'::regprocedure,
     '{postgres=X/postgres,authenticated=X/postgres}'::text),
    ('crm.metricas_reuniones_fn(date,date)'::regprocedure,
     '{postgres=X/postgres,authenticated=X/postgres}'::text)
  ) esperado(objeto, acl)
  join pg_proc p on p.oid = esperado.objeto
  where pg_get_userbyid(p.proowner) <> 'postgres'
     or p.proacl::text is distinct from esperado.acl;
  if v_acl is not null then
    raise exception 'REQ-GER-MET-001 postflight: se alteró propietario/ACL de dependencias (%)', v_acl;
  end if;

  if (select count(*) from private.contadores_crudos_leads_citas()
      where objeto in (
        'private.metricas_conversiones_implementacion(date,date,text)',
        'private.metricas_reuniones_implementacion(date,date)'
      ) and declarada and huella_ok) <> 2 then
    raise exception 'REQ-GER-MET-001 postflight: uno de los dos agregadores no quedó declarado y vigente';
  end if;

  if (select sello from private.analitica_lc_sello where id)
     is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'REQ-GER-MET-001 postflight: la lista no quedó sellada';
  end if;

  -- Ningún contador ajeno puede aparecer, desaparecer ni cambiar de estado.
  if exists (
    (select * from pg_temp.gerencia_censo_ajeno_pre
     except
     select tipo, objeto, declarada, huella_ok
     from private.contadores_crudos_leads_citas()
     where objeto not in (
       'private.metricas_conversiones_implementacion(date,date,text)',
       'private.metricas_reuniones_implementacion(date,date)'
     ))
    union all
    (select tipo, objeto, declarada, huella_ok
     from private.contadores_crudos_leads_citas()
     where objeto not in (
       'private.metricas_conversiones_implementacion(date,date,text)',
       'private.metricas_reuniones_implementacion(date,date)'
     )
     except
     select * from pg_temp.gerencia_censo_ajeno_pre)
  ) then
    raise exception 'REQ-GER-MET-001 postflight: cambió el censo ajeno al requerimiento';
  end if;
end $$;

commit;

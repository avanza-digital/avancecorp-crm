-- ⛔ BORRADOR DE LA FASE 4 — NO APLICAR EN LA SEMANA QUIETA (30/08–09/09).
-- Se publica DESPUES del primer sellado del 10/09, empezando por el nucleo y
-- la ventana (aditivos), y luego las tandas a→b→c del contrato fichado en el
-- vault: «Contrato de la capa semantica - Capital (F4, 2026-08-29)».
--
-- P-055 Fase 4.0 — EL NUCLEO DE CAPITAL: private.capital_episodios
--
-- Una sola calculadora. Devuelve FILAS-HECHO, no totales: la pantalla suma,
-- el nucleo decide que existe. Molde: private.conversion_episodios (vivo).
--
-- Las decisiones que este nucleo ENCARNA (todas de Miguel, Fase 0 + 29/08):
--   d1/d2  el capital es del ANALISTA QUE CIERRA (analista_cierre_id)
--   d3     el mes es el de fecha_cierre_comercial
--   d4     las cooperativas SON capital (solo vigentes; anuladas aportan 0)
--   d5     renovado/adicional viajan DESGLOSADOS desde operaciones_cartera
--   d6     los demos NO SALEN del nucleo
--   d15    sin filtro de equipo: en_roster es INFORMATIVO, no descuenta
--   d16    el pipeline estimado NO vive aqui
--   d17    mes y AUM son DOS PREGUNTAS a la misma calculadora (tipo/estado)
--   29/08  los ajustes del analista NO son capital de la empresa: fuera

begin;

create or replace function private.capital_episodios(
  p_ini      timestamptz,
  p_fin      timestamptz,
  p_global   boolean,
  p_visibles uuid[]
) returns table(
  tipo              text,
  contrato_id       uuid,
  cierre_externo_id uuid,
  cliente_id        uuid,
  analista_id       uuid,
  registrado_por    uuid,
  en_roster         boolean,
  moneda            text,
  monto             numeric,
  categoria         text,
  mes_comercial     date,
  fecha             timestamptz,
  estado            text,
  anulado           boolean
)
language sql
stable
security definer
set search_path to ''
as $fn$
  -- Pierna CONTRATO: cada contrato NO-demo es un episodio de capital, con su
  -- categoria de negocio (nuevo/renovacion/upgrade). El monto es el capital
  -- del contrato; el desglose renovado/adicional viaja en piernas aparte.
  select
    'contrato_' || coalesce(c.categoria, 'nuevo'),
    c.id,
    null::uuid,
    c.cliente_id,
    c.analista_cierre_id,
    c.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      join crm.meta_periodos mp on mp.id = mv.meta_periodo_id
      where mp.periodo = date_trunc('month', c.fecha_cierre_comercial)::date
        and mv.vendedor_id = c.analista_cierre_id
    ),
    c.moneda,
    c.capital,
    c.categoria,
    date_trunc('month', c.fecha_cierre_comercial)::date,
    (c.fecha_cierre_comercial::timestamp at time zone 'America/Lima'),
    c.estado,
    false
  from public.contratos c
  where not c.es_demo
    and c.fecha_cierre_comercial >= (p_ini at time zone 'America/Lima')::date
    and c.fecha_cierre_comercial <  (p_fin at time zone 'America/Lima')::date
    and (p_global or c.analista_cierre_id = any(p_visibles))

  union all

  -- Pierna DESGLOSE: para una renovacion, cuanto del capital CONTINUA
  -- (renovado) y cuanto es dinero NUEVO (adicional). Decision 5: se completa.
  -- Son hechos HIJOS del contrato nuevo: mismas fechas, mismo analista.
  select
    'desglose_' || parte.tipo,
    o.contrato_nuevo_id,
    null::uuid,
    o.cliente_id,
    c.analista_cierre_id,
    o.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      join crm.meta_periodos mp on mp.id = mv.meta_periodo_id
      where mp.periodo = o.periodo and mv.vendedor_id = c.analista_cierre_id
    ),
    o.moneda,
    parte.monto,
    o.tipo,
    o.periodo,
    (o.fecha_operacion::timestamp at time zone 'America/Lima'),
    c.estado,
    false
  from crm.operaciones_cartera o
  join public.contratos c on c.id = o.contrato_nuevo_id and not c.es_demo
  cross join lateral (values
    ('renovado',  o.capital_renovado),
    ('adicional', o.capital_adicional)
  ) as parte(tipo, monto)
  where parte.monto is not null
    and o.fecha_operacion >= (p_ini at time zone 'America/Lima')::date
    and o.fecha_operacion <  (p_fin at time zone 'America/Lima')::date
    and (p_global or c.analista_cierre_id = any(p_visibles))

  union all

  -- Pierna COOPERATIVA (decision 4): capital que no tiene contrato Avance.
  -- Las anuladas VIAJAN con monto 0 y anulado=true: se listan (historial,
  -- decision 15) pero no suman. El analista es el del cierre (foto inmutable).
  select
    'cooperativa',
    null::uuid,
    ce.id,
    l.perfil_id,
    ce.vendedor_id,
    ce.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      join crm.meta_periodos mp on mp.id = mv.meta_periodo_id
      where mp.periodo = date_trunc('month', ce.creado_en at time zone 'America/Lima')::date
        and mv.vendedor_id = ce.vendedor_id
    ),
    ce.moneda,
    case when ce.anulado_en is null then ce.monto else 0::numeric end,
    'nuevo',
    date_trunc('month', ce.creado_en at time zone 'America/Lima')::date,
    ce.creado_en,
    case when ce.anulado_en is null then 'vigente' else 'anulado' end,
    ce.anulado_en is not null
  from crm.cierres_externos ce
  left join crm.leads l on l.id = ce.lead_id
  where ce.creado_en >= p_ini and ce.creado_en < p_fin
    and (p_global or ce.vendedor_id = any(p_visibles));
$fn$;

revoke execute on function private.capital_episodios(timestamptz, timestamptz, boolean, uuid[])
  from public, anon, authenticated;

-- ------------------------------------------------------------- LA VENTANA --
-- Autoriza UNA vez y pregunta por el actor; el nucleo no sabe quien llama.
create or replace function private.capital_autorizada(
  p_desde date,
  p_hasta date
) returns table(
  tipo text, contrato_id uuid, cierre_externo_id uuid, cliente_id uuid,
  analista_id uuid, registrado_por uuid, en_roster boolean, moneda text,
  monto numeric, categoria text, mes_comercial date, fecha timestamptz,
  estado text, anulado boolean
)
language plpgsql
stable
security definer
set search_path to ''
as $fn$
declare
  v_uid     uuid := (select auth.uid());
  v_rol     text := private.rol_crm((select auth.uid()));
  v_global  boolean;
  v_visibles uuid[];
begin
  if v_uid is null then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  v_global := coalesce(v_rol = 'gerencia', false) or (select private.es_lector_global());
  if not v_global then
    v_visibles := array(select private.vendedor_ids_visibles(v_uid));
    if v_visibles is null or array_length(v_visibles, 1) is null then
      raise exception 'No autorizado' using errcode = '42501';
    end if;
  end if;

  return query select * from private.capital_episodios(
    (p_desde::timestamp at time zone 'America/Lima'),
    ((p_hasta + 1)::timestamp at time zone 'America/Lima'),
    v_global,
    coalesce(v_visibles, '{}'::uuid[])
  );
end;
$fn$;

revoke execute on function private.capital_autorizada(date, date)
  from public, anon, authenticated;

commit;

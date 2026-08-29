-- Version ORIGINAL de private.registrar_ajuste_si_mes_cerrado
-- huella md5 del prosrc: e07c89715b96ee2604ce435fea3e2c34 (VERIFICADA al escribir este archivo)
-- Capturada de produccion el 2026-08-29, ANTES de publicar 20260829170000.
-- Paso 6 de rollback-f3-p055.sql: restaura el calculo previo de la sancion.
create or replace function private.registrar_ajuste_si_mes_cerrado(
  p_lead_id uuid, p_motivo text, p_por uuid
) returns uuid language plpgsql security definer set search_path to ''
as $original$
declare
  v_lead        crm.leads%rowtype;
  v_periodo     date;
  v_acreditado  uuid;
  v_referido    boolean;
  v_peso        numeric;
  v_numerador   numeric;
  v_pen         numeric := 0;
  v_usd         numeric := 0;
  v_detalle     jsonb := '[]'::jsonb;
  v_id          uuid;
begin
  select * into v_lead from crm.leads where id = p_lead_id;
  if not found or v_lead.convertido_en is null then
    return null;
  end if;

  v_periodo := date_trunc('month', v_lead.convertido_en at time zone 'America/Lima')::date;

  -- ⚠️ EL CERROJO, antes de mirar si el mes esta cerrado. Sin el, una anulacion
  -- concurrente con el sellado de ESE mes lee «abierto» —porque el sello aun no
  -- ha commiteado—, devuelve NULL, y el cierre anulado se queda pagado para
  -- siempre. Misma clave que en `crm.cerrar_periodo`.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (v_periodo - date '2000-01-01')::integer
  );

  -- Mes ABIERTO: no hay deuda que registrar. El mes se recalcula y el cierre
  -- desaparece de el, que es el comportamiento de siempre.
  if not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo) then
    return null;
  end if;

  -- A quien se le descuenta: el mismo acreditado que usa la cuota.
  v_acreditado := coalesce(
    (select ca.acreditado_a from crm.cierres_avance_anulados ca where ca.lead_id = p_lead_id),
    private.vendedor_acreditado_del_cierre(p_lead_id));
  if v_acreditado is null then
    -- Sin acreditado no hay a quien descontarle. No se inventa un deudor.
    return null;
  end if;

  -- Lo que valia el cierre en la conversion. El origen sale del LEDGER (la foto
  -- del episodio), no de `crm.leads.origen`, que es una columna viva.
  select coalesce(bool_or(la.origen = 'referido'), false) into v_referido
  from crm.lead_asignaciones la
  where la.lead_id = p_lead_id and la.resultado = 'convertido';

  v_peso := private.peso_referido_conversion(v_periodo);
  v_numerador := case when v_referido then v_peso else 1 end;

  -- Y lo que valia en capital: los contratos que dejan de acreditar, con la
  -- MISMA regla que la cuota. PEN y USD por separado, y ADEMAS desglosado por
  -- categoria: es la casilla exacta de la que habra que descontarlo.
  select
    coalesce(sum(c.capital) filter (where c.moneda = 'PEN'), 0),
    coalesce(sum(c.capital) filter (where c.moneda = 'USD'), 0)
    into v_pen, v_usd
  from private.contratos_afectados_por_anulacion(p_lead_id) x
  join public.contratos c on c.id = x;

  select coalesce(jsonb_agg(jsonb_build_object(
           'categoria', d.categoria, 'moneda', d.moneda,
           'capital', d.capital, 'contratos', d.contratos)), '[]'::jsonb)
    into v_detalle
  from (
    select c.categoria, c.moneda, sum(c.capital) as capital, count(*)::int as contratos
    from private.contratos_afectados_por_anulacion(p_lead_id) x
    join public.contratos c on c.id = x
    group by c.categoria, c.moneda
  ) d;

  -- Un cierre que no valia nada no genera deuda.
  if v_numerador <= 0 and v_pen = 0 and v_usd = 0 then
    return null;
  end if;

  insert into crm.ajustes_mes_cerrado (
    vendedor_id, periodo_origen, lead_id, motivo, creado_por,
    numerador, capital_pen, capital_usd, detalle,
    pendiente_numerador, pendiente_pen, pendiente_usd, pendiente_detalle
  ) values (
    v_acreditado, v_periodo, p_lead_id, p_motivo, p_por,
    v_numerador, v_pen, v_usd, v_detalle,
    v_numerador, v_pen, v_usd, v_detalle
  )
  on conflict (lead_id) do nothing
  returning id into v_id;

  return v_id;
end;
$original$;

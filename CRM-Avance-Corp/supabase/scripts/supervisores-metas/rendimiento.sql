-- Lectura únicamente: EXPLAIN no devuelve nombres, identidades ni importes.
-- Bloque exacto nuevo de producción propia para un supervisor activo. No crea funciones.
-- v_base vacío representa a un supervisor sin meta de analista (los cuatro actuales).
begin read only;
set local statement_timeout='15s';
explain (analyze,buffers,format text)
    with conv as materialized (
      -- La MISMA pieza del nucleo que la oficial y que la #8. Solo quien aparece
      -- en el nucleo del mes: una deuda sin actividad no crea fila aqui.
      select n.*
      from private.conversion_neta_por_vendedor(date '2026-10-01', true, '{}'::uuid[]) n
      where n.en_nucleo
    ), nombrados as materialized (
      -- A quien la oficial NOMBRA en `responsables` le publica el NETO; al resto
      -- lo suma BRUTO y sin nombre en `cobertura.fuera_de_roster`. Aqui se
      -- publica, para cada persona, lo mismo que la oficial (C2, auditoria 21/09).
      select r.vendedor_id
      from private.roster_conversion_mensual(date '2026-10-01', true, '{}'::uuid[]) r
    ), prod as materialized (
      select r.*
      from private.produccion_mes_por_vendedor(timestamptz '2026-10-01 00:00:00-05', timestamptz '2026-11-01 00:00:00-05', (select id from crm.meta_periodos where periodo=date '2026-10-01' order by revision desc limit 1)) r
    ), car as materialized (
      select m.* from private.metricas_cartera_por_vendedor(date '2026-10-01') m
  ), personas_fuente as (
    select c.analista_id as persona_id from conv c where c.analista_id is not null
      union
      select p.vendedor_id from prod p where p.vendedor_id is not null
      union
      select c.vendedor_id from car c where c.vendedor_id is not null
    ), personas as (
      -- Los núcleos traen el universo. Recortar ANTES de los joins: el conjunto
      -- dentro solo contiene los analistas visibles para el actor actual.
      select p.persona_id from personas_fuente p
      where false or (true and p.persona_id = (select e.perfil_id from crm.equipo e join public.perfiles p on p.id=e.perfil_id where e.rol_crm='supervisor' and e.activo and p.activo order by e.perfil_id limit 1))
    ), dentro as (
      select (e.value->>'vendedor_id')::uuid as persona_id
      from jsonb_array_elements(coalesce('{}'::jsonb->'vendedores', '[]'::jsonb)) e
    ), fuera as (
      select
        p.persona_id,
        coalesce(nullif(btrim(pf.nombre_completo), ''),
                 '(sin nombre · ' || left(p.persona_id::text, 8) || ')') as nombre,
        coalesce(eq.rol_crm, 'fuera_equipo') as rol_crm,
        case
          when eq.rol_crm = 'vendedor' and sup.perfil_id is not null
            then 'analista_sin_meta'
          when eq.rol_crm = 'vendedor' then 'analista_sin_supervisor'
          when eq.rol_crm = 'supervisor' then 'supervisor'
          when eq.rol_crm = 'gerencia' then 'gerencia'
          else 'fuera_estructura'
        end as motivo
      from personas p
      left join crm.equipo eq on eq.perfil_id = p.persona_id
      left join crm.equipo sup
        on sup.perfil_id = eq.supervisor_id and sup.rol_crm = 'supervisor'
      left join public.perfiles pf on pf.id = p.persona_id
      where not exists (
        select 1 from dentro d where d.persona_id = p.persona_id
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
        'numerador', case
          when exists (select 1 from nombrados nm where nm.vendedor_id = f.persona_id)
            then coalesce(cv.numerador, 0)
          else coalesce(cv.numerador_bruto, 0) end
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
rollback;

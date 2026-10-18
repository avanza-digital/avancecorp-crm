-- Reversa protegida: solo restaura la función exacta reemplazada por este cambio.
begin;
set local lock_timeout = '5s';
do $preflight$ begin
  if (select md5(prosrc) from pg_catalog.pg_proc
      where oid=to_regprocedure('crm.cumplimiento_metas_fn(date)'))
      is distinct from 'b1b3661f98745096d4a7d584981b19a2' then
    raise exception 'PREFLIGHT: la función cambió después de supervisores; revisar antes de revertir';
  end if;
end $preflight$;
CREATE OR REPLACE FUNCTION crm.cumplimiento_metas_fn(p_periodo date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_lector boolean := private.es_lector_global() or private.es_coordinador_reportes();
  v_base jsonb;
  v_vendedores jsonb;
  v_fuera_ranking jsonb := '[]'::jsonb;
  v_cerrado boolean;
  v_global boolean;
  v_periodo_id uuid;
  v_ini timestamptz;
  v_fin timestamptz;
begin
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  v_base := crm.cumplimiento_metas_sin_cartera_fn(p_periodo);
  v_cerrado := coalesce((v_base #>> '{cierre,cerrado}')::boolean, false);

  -- Solo Gerencia y el lector global reciben identidades fuera del ranking.
  -- Para un mes cerrado salen del JSON append-only del sello; para uno abierto
  -- se proyectan en vivo desde los mismos nucleos de conversion, produccion y
  -- cartera. Los demás roles reciben siempre un arreglo vacío.
  v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
  if v_global and v_cerrado then
    select coalesce(pc.cobertura->'fuera_ranking', '[]'::jsonb)
      into v_fuera_ranking
    from crm.periodos_cerrados pc
    where pc.periodo = p_periodo;
  elsif v_global then
    v_ini := p_periodo::timestamp at time zone 'America/Lima';
    v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';
    select mp.id into v_periodo_id
    from crm.meta_periodos mp
    where mp.periodo = p_periodo
    order by mp.revision desc
    limit 1;

    with conv as materialized (
      -- La MISMA pieza del nucleo que la oficial y que la #8. Solo quien aparece
      -- en el nucleo del mes: una deuda sin actividad no crea fila aqui.
      select n.*
      from private.conversion_neta_por_vendedor(p_periodo, true, '{}'::uuid[]) n
      where n.en_nucleo
    ), nombrados as materialized (
      -- A quien la oficial NOMBRA en `responsables` le publica el NETO; al resto
      -- lo suma BRUTO y sin nombre en `cobertura.fuera_de_roster`. Aqui se
      -- publica, para cada persona, lo mismo que la oficial (C2, auditoria 21/09).
      select r.vendedor_id
      from private.roster_conversion_mensual(p_periodo, true, '{}'::uuid[]) r
    ), prod as materialized (
      select r.*
      from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
    ), car as materialized (
      select m.* from private.metricas_cartera_por_vendedor(p_periodo) m
  ), personas as (
    select c.analista_id as persona_id from conv c where c.analista_id is not null
      union
      select p.vendedor_id from prod p where p.vendedor_id is not null
      union
      select c.vendedor_id from car c where c.vendedor_id is not null
    ), dentro as (
      select (e.value->>'vendedor_id')::uuid as persona_id
      from jsonb_array_elements(coalesce(v_base->'vendedores', '[]'::jsonb)) e
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
  end if;

  with m as materialized (
    select x.*
    from private.metricas_cartera_por_vendedor(p_periodo) x
    where not v_cerrado
    union all
    select
      f.vendedor_id,
      (f.cartera->>'conversiones_clientes')::int,
      (f.cartera->>'conversiones_renovacion')::int,
      (f.cartera->>'conversiones_upgrade')::int,
      (f.cartera->>'operaciones_renovacion')::int,
      (f.cartera->>'operaciones_upgrade')::int,
      (f.cartera->>'capital_renovado_pen')::numeric,
      (f.cartera->>'capital_renovado_usd')::numeric,
      (f.cartera->>'capital_adicional_pen')::numeric,
      (f.cartera->>'capital_adicional_usd')::numeric,
      (f.cartera->>'renovaciones_sin_desglose')::int
    from private.cierre_mes_reportes_visible(p_periodo, v_uid) f
    where v_cerrado
  )
  select coalesce(jsonb_agg(
    jsonb_set(
      e.value,
      '{convertidos}',
      to_jsonb(coalesce((e.value->>'convertidos')::int, 0)
               + coalesce(m.conversiones_clientes, 0)),
      true
    ) order by e.ord
  ), '[]'::jsonb) into v_vendedores
  from jsonb_array_elements(coalesce(v_base->'vendedores','[]'::jsonb))
       with ordinality e(value, ord)
  left join m on m.vendedor_id = (e.value->>'vendedor_id')::uuid;

  v_base := jsonb_set(v_base, '{vendedores}', v_vendedores, true);
  return jsonb_set(v_base, '{fuera_ranking}', v_fuera_ranking, true);
end;
$function$;
commit;

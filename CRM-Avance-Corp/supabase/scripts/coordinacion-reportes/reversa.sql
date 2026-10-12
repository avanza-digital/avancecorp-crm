-- REVERSA Coordinación: Facturación y Ranking generales, exclusivamente lectura.
-- Aprobado por Miguel el 12/10/2026. Clientes/contratos/PII permanecen ocultos.
-- No modifica es_lector_global, vendedor_ids_visibles, policies, escrituras ni datos.
-- Las únicas diferencias de los cuerpos vivos son autorización/alcance del reporte.
-- Reversa: supabase/scripts/coordinacion-reportes/reversa.sql (antes de cambios posteriores).
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
do $guardia$
declare r record;
begin
  for r in select * from (values
    ('crm.conversion_mensual_fn(date)', '04dbf71510436cb2752dbbaf5268c551'),
    ('crm.conversion_mensual_sin_cartera_fn(date)', '9f23eb0926eac7dd1745a2af493b9900'),
    ('crm.cumplimiento_metas_fn(date)', 'd0320f34c6f9faab2bc9bf9fbb4da440'),
    ('crm.cumplimiento_metas_sin_cartera_fn(date)', 'fe6d91ab0678bcf31a78be3003e222b3'),
    ('crm.metricas_conversiones_equipo_fn(date,date)', 'ff20043aa97e87278b5a9200e7ba83cb'),
    ('crm.metricas_conversiones_fn(date,date,text)', '75469f933c044e831a33d28efd5f4dc3'),
    ('private.facturacion_lista(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)', 'f98f0bea3397cb7f054e4f25b6ae5cb8'),
    ('private.facturacion_operaciones_visibles(timestamp with time zone,timestamp with time zone)', 'a278e622f2cfcadb6767eaf9a48ffb22'),
    ('private.metricas_conversiones_implementacion(date,date,text)', 'db8c3125778f39c4d32d984a7c2cb32d'),
    ('crm.metricas_cartera_fn(date)', '67cdc767f0d38277a920b2ec5aebf2ae')
  ) f(firma, huella) loop
    if (select md5(pg_get_functiondef(to_regprocedure(r.firma)))) is distinct from r.huella then
      raise exception 'Permisos de Coordinación: cuerpo inesperado en %, se deshace todo', r.firma;
    end if;
  end loop;
end $guardia$;
create temporary table coord_acl on commit drop as
select oid, proacl, proowner, prosecdef, provolatile, proconfig
from pg_proc where oid in (
  to_regprocedure('crm.conversion_mensual_fn(date)'),
  to_regprocedure('crm.conversion_mensual_sin_cartera_fn(date)'),
  to_regprocedure('crm.cumplimiento_metas_fn(date)'),
  to_regprocedure('crm.cumplimiento_metas_sin_cartera_fn(date)'),
  to_regprocedure('crm.metricas_conversiones_equipo_fn(date,date)'),
  to_regprocedure('crm.metricas_conversiones_fn(date,date,text)'),
  to_regprocedure('private.facturacion_lista(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)'),
  to_regprocedure('private.facturacion_operaciones_visibles(timestamp with time zone,timestamp with time zone)'),
  to_regprocedure('private.metricas_conversiones_implementacion(date,date,text)'),
  to_regprocedure('crm.metricas_cartera_fn(date)')
);
CREATE OR REPLACE FUNCTION crm.conversion_mensual_fn(p_periodo date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_lector boolean := private.es_lector_global();
  v_global boolean;  v_base jsonb;
  v_total jsonb;
  v_cerrado boolean;
  v_revision integer;
  v_cartera_fila record;  v_responsables jsonb;
begin
  -- Gate antes de cualquier lectura. La base vuelve a validarlo y valida el
  -- periodo; la duplicacion deliberada conserva el borde publico fail-closed.
  if v_uid is null or not coalesce(
    v_rol in ('vendedor', 'supervisor', 'gerencia') or v_lector, false
  ) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
  v_base := crm.conversion_mensual_sin_cartera_fn(p_periodo);
  v_cerrado := coalesce((v_base #>> '{cierre,cerrado}')::boolean, false);
  if v_cerrado then
    select pc.meta_revision into v_revision
    from crm.periodos_cerrados pc where pc.periodo = p_periodo;
  else
    select mp.revision into v_revision
    from crm.meta_periodos mp
    where mp.periodo = p_periodo
    order by mp.revision desc
    limit 1;
  end if;
  v_revision := coalesce(v_revision, 0);
  -- Abierto: cartera viva. Cerrado: suma exclusivamente la columna congelada
  -- de las mismas filas que el actor puede ver en la foto mensual.
  if v_cerrado then
    v_total := jsonb_build_object(
      'conversiones_clientes', 0,
      'conversiones_renovacion', 0,
      'conversiones_upgrade', 0,
      'operaciones_renovacion', 0,
      'operaciones_upgrade', 0,
      'capital_renovado_pen', 0,
      'capital_renovado_usd', 0,
      'capital_adicional_pen', 0,
      'capital_adicional_usd', 0,
      'renovaciones_sin_desglose', 0
    );
    for v_cartera_fila in
      select f.cartera from private.cierre_mes_visible(p_periodo, v_uid) f
      union all
      select e.value->'cartera' as cartera
      from crm.periodos_cerrados pc
      cross join lateral jsonb_array_elements(
        coalesce(pc.cobertura->'fuera_ranking', '[]'::jsonb)
      ) e
      where pc.periodo = p_periodo and v_global
    loop
      v_total := jsonb_build_object(
        'conversiones_clientes',
          (v_total->>'conversiones_clientes')::int
          + (v_cartera_fila.cartera->>'conversiones_clientes')::int,
        'conversiones_renovacion',
          (v_total->>'conversiones_renovacion')::int
          + (v_cartera_fila.cartera->>'conversiones_renovacion')::int,
        'conversiones_upgrade',
          (v_total->>'conversiones_upgrade')::int
          + (v_cartera_fila.cartera->>'conversiones_upgrade')::int,
        'operaciones_renovacion',
          (v_total->>'operaciones_renovacion')::int
          + (v_cartera_fila.cartera->>'operaciones_renovacion')::int,
        'operaciones_upgrade',
          (v_total->>'operaciones_upgrade')::int
          + (v_cartera_fila.cartera->>'operaciones_upgrade')::int,
        'capital_renovado_pen',
          (v_total->>'capital_renovado_pen')::numeric
          + (v_cartera_fila.cartera->>'capital_renovado_pen')::numeric,
        'capital_renovado_usd',
          (v_total->>'capital_renovado_usd')::numeric
          + (v_cartera_fila.cartera->>'capital_renovado_usd')::numeric,
        'capital_adicional_pen',
          (v_total->>'capital_adicional_pen')::numeric
          + (v_cartera_fila.cartera->>'capital_adicional_pen')::numeric,
        'capital_adicional_usd',
          (v_total->>'capital_adicional_usd')::numeric
          + (v_cartera_fila.cartera->>'capital_adicional_usd')::numeric,
        'renovaciones_sin_desglose',
          (v_total->>'renovaciones_sin_desglose')::int
          + (v_cartera_fila.cartera->>'renovaciones_sin_desglose')::int
      );
    end loop;
  else
    v_total := crm.metricas_cartera_fn(p_periodo)->'total';
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
    from private.cierre_mes_visible(p_periodo, v_uid) f
    where v_cerrado
  )
  select coalesce(jsonb_agg(
    e.value
    || jsonb_build_object('cartera', jsonb_build_object(
      'conversiones_clientes', coalesce(m.conversiones_clientes, 0),
      'conversiones_renovacion', coalesce(m.conversiones_renovacion, 0),
      'conversiones_upgrade', coalesce(m.conversiones_upgrade, 0),
      'capital_renovado_pen', coalesce(m.capital_renovado_pen, 0),
      'capital_renovado_usd', coalesce(m.capital_renovado_usd, 0),
      'capital_adicional_pen', coalesce(m.capital_adicional_pen, 0),
      'capital_adicional_usd', coalesce(m.capital_adicional_usd, 0),
      'renovaciones_sin_desglose', coalesce(m.renovaciones_sin_desglose, 0)
    ))
    || case
      when coalesce(m.conversiones_clientes, 0) > 0
       and coalesce((e.value->>'divisor')::int, 0) = 0
       and e.value->>'estado' = 'sin_actividad'
      then jsonb_build_object('estado', 'solo_arrastre')
      else '{}'::jsonb end
    order by e.ord
  ), '[]'::jsonb) into v_responsables
  from jsonb_array_elements(coalesce(v_base->'responsables', '[]'::jsonb))
       with ordinality e(value, ord)
  left join m on m.vendedor_id = (e.value->>'vendedor_id')::uuid;

  v_base := jsonb_set(v_base, '{responsables}', v_responsables, true);
  v_base := jsonb_set(v_base, '{revision}', to_jsonb(v_revision), true);
  v_base := jsonb_set(v_base, '{cartera}', coalesce(v_total, '{}'::jsonb), true);
  v_base := jsonb_set(v_base, '{total,cartera}', coalesce(v_total, '{}'::jsonb), true);
  return v_base;
end;
$function$
;

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
  v_aporte_ref numeric;
  v_suelo timestamptz;
  v_suelo_mes date;
  v_medible boolean;
  v_motivo_no_medible text;
  v_motivo_roster text;
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
                      from fuera_foto f), 0::numeric)) as numerador,
        -- Tope de referidos: aporte exacto de los referidos que la foto guardó por analista; global = todos (también el fuera de
        -- ranking y sin analista), con alcance de equipo o propio = solo los visibles.
        (select coalesce(sum(m.value::numeric), 0)
           from jsonb_each_text(coalesce(v_cierre.cobertura->'referidos_aporte', '{}'::jsonb)) m
          where v_global or exists (select 1 from visibles vv where vv.vendedor_id::text = m.key)) as aporte_referidos
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
        'tope_referidos_pct', v_cierre.tope_referidos_pct,
        -- 23/09/2026: la foto guarda SU peso de renovacion desde `20260923172517`.
        -- Antes se RECONSTRUIA desde el del referido, cierto solo mientras los dos
        -- valieran lo mismo. Ahora se lee el que se guardo. El `coalesce` cubre las
        -- fotos anteriores a esa columna: para ellas se conserva EXACTAMENTE la
        -- regla con la que se sellaron. Una foto no se reescribe.
        'renovacion', coalesce(
          v_cierre.ponderacion_renovacion,
          case when v_cierre.cobertura->>'modelo_conversion' = 'llegadas_v2'
            then v_cierre.ponderacion_referido else 1 end),
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
            then round(100.0 * (case when v_cierre.tope_referidos_pct is not null then r.aporte_referidos
                                   else v_cierre.ponderacion_referido * r.cierres_referidos end) / r.divisor, 2) end
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

  -- 4) Mes ABIERTO. Quien sale NOMBRADO lo decide una sola regla del nucleo,
  -- `private.roster_conversion_mensual`: el mes vigente conserva el roster
  -- operativo; uno anterior aun abierto (ventana de ajuste), la ultima
  -- publicacion de ESE mes.
  v_es_historico_abierto := p_periodo < v_mes_actual;

  v_visibles := case when v_global then '{}'::uuid[]
                     else array(select private.vendedor_ids_visibles(v_uid)) end;

  v_ini := p_periodo::timestamp at time zone 'America/Lima';
  v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';

  v_factor := private.peso_referido_conversion(p_periodo);
  -- Tope de referidos: el aporte REAL de los referidos de todo el ámbito (roster, fuera de roster y sin analista), del núcleo.
  if private.tope_referidos_conversion(p_periodo) is not null then
    select coalesce(sum(r.aporte), 0) into v_aporte_ref
    from private.referidos_aporte_por_analista(v_ini, v_fin, p_periodo, v_global, v_visibles, v_factor) r;
  end if;

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
     and not exists (
       select 1 from private.roster_conversion_mensual(p_periodo, false, array[v_uid]) r
        where r.vendedor_id = v_uid
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
    from private.roster_conversion_mensual(p_periodo, v_global, v_visibles) r
  ),
  base as materialized (
    -- LA CIFRA POR PERSONA sale de UNA sola pieza del nucleo, la misma que usa
    -- Metas: bruto, deuda de meses ya pagados, neto y porcentaje sobre el neto.
    select n.*
    from private.conversion_neta_por_vendedor(p_periodo, v_global, v_visibles) n
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
      -- NETO de lo que se le debe descontar y porcentaje sobre el neto, tal
      -- como los sirve la pieza. Quien no tiene fila (ni actividad ni deuda)
      -- queda en cero y sin porcentaje, igual que antes.
      coalesce(b.numerador, 0::numeric) as numerador,
      b.conversion_pct,
      coalesce(b.ajuste_pendiente, 0::numeric) as ajuste_pendiente,
      coalesce(b.ajuste_origenes, '[]'::jsonb) as ajuste_origenes,
      coalesce(b.procedencia, '[]'::jsonb) as procedencia,
      coalesce(b.referidos_recibidos, 0) as referidos_recibidos,
      b.referidos_aporta_pct,
      coalesce(a.dados_de_alta, 0) as dados_de_alta
    from roster r
    left join base b on b.analista_id = r.vendedor_id
    left join alta_referidos a on a.analista_id = r.vendedor_id
  ),
  fuera as (
    -- Quien produjo dentro del ambito pero NO esta en el roster: el que se dio
    -- de baja a mitad de mes, el supervisor con cartera propia, el vendedor
    -- sin supervisor. Sigue siendo un AGREGADO SIN IDENTIDAD (ningun uuid
    -- sale), pero desde D8 (Miguel, 27/08/2026) ademas de declararse en
    -- `cobertura.fuera_de_roster` se SUMA al total: por eso aqui se agregan
    -- tambien los desgloses que `resumen` necesita. BRUTO a proposito
    -- (`numerador_bruto`): el ajuste de meses ya pagados se descuenta por fila
    -- del roster y el ex-roster no tiene fila donde descontarlo. Solo cuenta
    -- quien aparece en el nucleo (`en_nucleo`): una deuda sin actividad no es
    -- produccion.
    select
      count(b.analista_id)::int as analistas,
      coalesce(sum(b.divisor), 0)::int as divisor,
      coalesce(sum(b.cierres_no_referidos + b.cierres_referidos), 0)::int as cierres,
      coalesce(sum(b.numerador_bruto), 0::numeric) as numerador,
      coalesce(sum(b.divisor_aproximado), 0)::int as divisor_aproximado,
      coalesce(sum(b.cierres_no_referidos), 0)::int as cierres_no_referidos,
      coalesce(sum(b.cierres_referidos), 0)::int as cierres_referidos,
      coalesce(sum(b.cierres_de_arrastre), 0)::int as cierres_de_arrastre,
      coalesce(sum(b.referidos_recibidos), 0)::int as referidos_recibidos
    from base b
    where b.en_nucleo
      and not exists (select 1 from roster r where r.vendedor_id = b.analista_id)
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
      where b.en_nucleo
        and not exists (select 1 from roster r where r.vendedor_id = b.analista_id)
    ) dm, jsonb_each_text(dm.divisor_por_motivo) e
    group by e.key
  ),
  sonda as (
    select count(*)::int as cierres_sin_episodio
    from crm.leads l
    where l.etapa = 'convertido'
      and private.conversion_origen_con_cierre(l.origen)
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
      'tope_referidos_pct', private.tope_referidos_conversion(p_periodo),
      -- 23/09/2026: publicaba `v_factor`, el peso del REFERIDO, mientras el
      -- nucleo aplica el de la RENOVACION desde `20260923155839`. Declaraba un
      -- peso y se calculaba con otro.
      'renovacion', private.peso_renovacion_conversion(p_periodo),
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
          then round(100.0 * (case when private.tope_referidos_conversion(p_periodo) is not null then v_aporte_ref
                                 else v_factor * r.cierres_referidos end) / r.divisor, 2) end
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
$function$
;

CREATE OR REPLACE FUNCTION crm.cumplimiento_metas_fn(p_periodo date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_lector boolean := private.es_lector_global();
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
    from private.cierre_mes_visible(p_periodo, v_uid) f
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
$function$
;

CREATE OR REPLACE FUNCTION crm.cumplimiento_metas_sin_cartera_fn(p_periodo date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_periodo_id uuid;
  v_revision integer := 0;
  v_publicada_en timestamptz;
  v_ini timestamptz;
  v_fin timestamptz;
  v_payload jsonb;
  v_factor numeric;
  v_cierre crm.periodos_cerrados%rowtype;
begin
  if v_uid is null
    or (private.rol_crm(v_uid) is null and not private.es_lector_global()) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  if p_periodo is null or p_periodo<>date_trunc('month',p_periodo)::date then
    raise exception 'El periodo debe ser el primer dia del mes' using errcode='22023';
  end if;

  -- MES CERRADO: se sirve la foto. Mismo recorte que la conversion, del mismo
  -- helper, para que las dos pantallas no puedan enseñar poblaciones distintas
  -- del mismo mes.
  select * into v_cierre from crm.periodos_cerrados pc where pc.periodo = p_periodo;
  if found then
    select mp.publicada_en into v_publicada_en
    from crm.meta_periodos mp
    where mp.periodo = p_periodo and mp.revision = v_cierre.meta_revision;

    select jsonb_build_object(
      -- DECLARACION. RAMA DEL MES SELLADO: lo que se publica sale de la FOTO
      -- de `crm.periodos_cerrados`, no de un recalculo.
      'es_mes_calendario', true,
      'fuente', 'mensual',
      'sellado', true,
      'ajuste_aplicado', true,
      'version', 1, 'periodo', p_periodo, 'revision', v_cierre.meta_revision,
      'publicada_en', v_publicada_en,
      'fuentes_reales', jsonb_build_object(
        'capital_y_contratos', 'contratos_confirmados',
        'conversion', 'leads_recibidos_ponderado'
      ),
      'ponderacion_referido', v_cierre.ponderacion_referido,
      'cierre', jsonb_build_object(
        'cerrado', true,
        'cerrado_en', v_cierre.cerrado_en,
        'automatico', v_cierre.automatico
      ),
      'vendedores', coalesce((
        select jsonb_agg(jsonb_build_object(
          'vendedor_id', v.vendedor_id, 'nombre', v.nombre_completo,
          'supervisor_id', v.supervisor_id, 'supervisor_nombre', v.supervisor_nombre,
          'conversion_objetivo', v.conversion_objetivo,
          'conversion_real', v.conversion_pct,
          'convertidos', v.cierres_no_referidos + v.cierres_referidos,
          'resueltos', v.divisor,
          'numerador', v.numerador,
          'cierres_no_referidos', v.cierres_no_referidos,
          'cierres_referidos', v.cierres_referidos,
          -- Lo que se le descontó al sellar por deudas de meses anteriores. El
          -- bruto se recupera sumándolo al numerador: la foto es auditable.
          'ajuste', jsonb_build_object(
            'aplicado', v.ajuste_numerador,
            'aplicado_pen', v.ajuste_pen,
            'aplicado_usd', v.ajuste_usd,
            'pendiente', 0),
          'detalles', v.detalles
        ) order by v.supervisor_nombre, v.nombre_completo)
        from private.cierre_mes_visible(p_periodo, v_uid) v
      ), '[]'::jsonb)
    ) into v_payload;
    return v_payload;
  end if;

  -- Mes ABIERTO: el comportamiento de siempre.
  v_ini:=p_periodo::timestamp at time zone 'America/Lima';
  v_fin:=(p_periodo+interval '1 month')::timestamp at time zone 'America/Lima';

  select mp.id,mp.revision,mp.publicada_en
    into v_periodo_id,v_revision,v_publicada_en
  from crm.meta_periodos mp where mp.periodo=p_periodo
  order by mp.revision desc limit 1;
  v_revision:=coalesce(v_revision,0);
  v_factor:=private.peso_referido_conversion(p_periodo);

  with reales as (
    select r.vendedor_id, r.categoria, r.moneda, r.contratos_real, r.capital_real
    from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
  ), conversiones as (
    -- LA CIFRA POR PERSONA ya no se calcula aqui: sale de la MISMA pieza del
    -- nucleo que usa la oficial (crm.conversion_mensual_sin_cartera_fn), asi que
    -- Metas y Ranking no pueden enseñar dos porcentajes del mismo asesor. La
    -- pieza trae tambien la deuda de quien no tuvo actividad en el mes.
    select n.analista_id as vendedor_id,
      (n.cierres_no_referidos+n.cierres_referidos)::integer as convertidos,
      n.divisor::integer as resueltos,
      n.numerador,
      n.cierres_no_referidos,
      n.cierres_referidos,
      n.conversion_pct as conversion_real,
      n.ajuste_pendiente
    from private.conversion_neta_por_vendedor(p_periodo, true, '{}'::uuid[]) n
  ), visibles as (
    select mv.*,p.nombre_completo,s.nombre_completo as supervisor_nombre
    from crm.metas_vendedor mv
    join public.perfiles p on p.id=mv.vendedor_id
    join public.perfiles s on s.id=mv.supervisor_id
    where mv.meta_periodo_id=v_periodo_id
      and (private.es_lector_global()
        or mv.vendedor_id in (select private.vendedor_ids_visibles(v_uid)))
  )
  select jsonb_build_object(
    -- DECLARACION. RAMA DEL MES ABIERTO: la cifra la sirve la misma pieza del
    -- nucleo que la oficial (`private.conversion_neta_por_vendedor`), ya neta de
    -- la deuda. Por eso `mensual`: es la cifra oficial, no un recalculo propio.
    'es_mes_calendario', true,
    'fuente', 'mensual',
    'sellado', false,
    'ajuste_aplicado', true,
    'version',1,'periodo',p_periodo,'revision',v_revision,
    'publicada_en',v_publicada_en,
    'fuentes_reales',jsonb_build_object(
      'capital_y_contratos','contratos_confirmados',
      'conversion','leads_recibidos_ponderado'
    ),
    'ponderacion_referido',v_factor,
    'cierre', jsonb_build_object('cerrado', false),
    'vendedores',coalesce((select jsonb_agg(jsonb_build_object(
      'vendedor_id',mv.vendedor_id,'nombre',mv.nombre_completo,
      'supervisor_id',mv.supervisor_id,'supervisor_nombre',mv.supervisor_nombre,
      'conversion_objetivo',mv.conversion_objetivo,
      'conversion_real',cv.conversion_real,
      'convertidos',coalesce(cv.convertidos,0),'resueltos',coalesce(cv.resueltos,0),
      'numerador',coalesce(cv.numerador,0),
      'cierres_no_referidos',coalesce(cv.cierres_no_referidos,0),
      'cierres_referidos',coalesce(cv.cierres_referidos,0),
      'ajuste',jsonb_build_object('pendiente',coalesce(cv.ajuste_pendiente,0)),
      'detalles',(select jsonb_agg(jsonb_build_object(
        'categoria',d.categoria,'moneda',d.moneda,
        'capital_objetivo',d.capital_objetivo,
        'capital_real',coalesce(r.capital_real,0),
        'capital_cumplimiento_pct',case when d.capital_objetivo>0
          then round(100.0*coalesce(r.capital_real,0)/d.capital_objetivo,2) end,
        'contratos_objetivo',d.contratos_objetivo,
        'contratos_real',coalesce(r.contratos_real,0),
        'contratos_cumplimiento_pct',case when d.contratos_objetivo>0
          then round(100.0*coalesce(r.contratos_real,0)/d.contratos_objetivo,2) end
      ) order by array_position(array['nuevo','renovacion','upgrade'],d.categoria),d.moneda)
      from crm.metas_vendedor_detalle d
      left join reales r on r.vendedor_id=mv.vendedor_id
        and r.categoria=d.categoria and r.moneda=d.moneda
      where d.meta_vendedor_id=mv.id)
    ) order by mv.supervisor_nombre,mv.nombre_completo) from visibles mv
    left join conversiones cv on cv.vendedor_id=mv.vendedor_id),'[]'::jsonb)
  ) into v_payload;
  return v_payload;
end;
$function$
;

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
  v_oficial jsonb;
  v_sin_fila integer;
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
    where e.tipo = 'cierre' and not e.anulado and private.conversion_origen_con_cierre(e.origen) and e.lead_id is not null
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
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and private.conversion_origen_con_cierre(e.origen) and not e.fue_referido)::int as cierres_no_referidos,
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and private.conversion_origen_con_cierre(e.origen) and e.fue_referido)::int as cierres_referidos,
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
      -- 23/09/2026: publicaba `v_factor`, que es el peso del REFERIDO. El nucleo ya
      -- aplica el de la RENOVACION desde 20260923155859, asi que esta clave decia
      -- un peso y el calculo usaba otro. Hoy no se nota porque los dos valen 0,15;
      -- el dia que se separen, el front (`conversion-vendedores.ts:272`, que hace
      -- `peso_renovacion ?? peso_referido`) ponderaria el desglose de renovaciones
      -- con el peso equivocado. Se declara el que de verdad se aplica.
      'peso_renovacion', private.peso_renovacion_conversion(v_mes),
      'incluye_cartera', true,
      'peso_referido', v_factor,
      'mes_peso', v_mes,
      -- DECLARACION (Ola 1a, 22/09/2026). Cuatro claves que NO cambian ninguna
      -- cifra: dicen de donde sale la que ya se publicaba.
      --   es_mes_calendario: el rango es un mes calendario completo (la
      --     condicion de Miguel del 21/09 para poder delegar en la mensual).
      --     Es exactamente `v_periodo is not null`, la misma prueba que esta
      --     funcion ya usaba para identificar la foto del roster.
      --   fuente: 'rango_vivo' SIEMPRE, porque esta puerta sigue calculando
      --     por su cuenta sobre ep_flujo. El dia que delegue, dira 'mensual'.
      --   sellado: null = «no se delego en la foto oficial». El estado del mes
      --     sigue viajando aparte, en el bloque `cierre`.
      --   ajuste_aplicado: false = esta puerta NO resta la deuda de anulacion
      --     de un mes ya sellado. Es el hecho que hace posible la discrepancia
      --     que esta ola viene a hacer VISIBLE antes de corregirla.
      'es_mes_calendario', v_periodo is not null,
      'fuente', 'rango_vivo',
      'sellado', null,
      'ajuste_aplicado', false
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

  -- ══ OLA 1b · LA SUSTITUCION ════════════════════════════════════════════
  -- REGLA DE MIGUEL (21/09/2026): mes calendario completo y sin filtro de
  -- fuente -> la cifra la sirve `crm.conversion_mensual_fn`. Esta funcion no
  -- tiene filtro de fuente en su firma, asi que la condicion se reduce a
  -- `v_periodo is not null`, que es la misma prueba que ya usaba.
  --
  -- Aqui la cifra es POR VENDEDOR: se reescriben las tres claves `nucleo_*` de
  -- cada fila con las de la oficial, emparejando por `vendedor_id`. Lo demas
  -- de la fila (`leads`, `clientes`, `conversion_pct` de la cohorte) es OTRA
  -- medida y no se toca.
  --
  -- El alcance NO se amplia: `crm.conversion_mensual_fn` recorta por
  -- `auth.uid()` igual que esta funcion, y su gate es mas ancho
  -- (vendedor/supervisor/gerencia/lector) que el de aqui
  -- (supervisor/gerencia/lector), asi que quien llega hasta este punto ya pasa
  -- el suyo.
  --
  -- Y si un vendedor del roster NO tiene fila en la oficial, su cifra no se
  -- fabrica: se cuenta en `sondas.sin_fila_en_la_oficial` para que la pantalla
  -- pueda ocultar el numero en vez de pintar un cero tranquilizador.
  if v_periodo is not null then
    v_oficial := crm.conversion_mensual_fn(v_periodo);

    select count(*)::int into v_sin_fila
      from jsonb_array_elements(coalesce(v_payload -> 'responsables', '[]'::jsonb)) f(e)
     where not exists (
       select 1 from jsonb_array_elements(coalesce(v_oficial -> 'responsables', '[]'::jsonb)) r(v)
        where (r.v ->> 'vendedor_id') = (f.e ->> 'vendedor_id'));

    v_payload := jsonb_set(v_payload, '{nucleo}',
      (v_payload -> 'nucleo') || jsonb_build_object(
        'fuente', 'mensual',
        'sellado', coalesce((v_oficial #>> '{cierre,cerrado}')::boolean, false),
        'ajuste_aplicado', true,
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
        -- El total del recalculo vivo, conservado al lado: sin el, la distancia
        -- entre la cifra oficial y la que esta funcion calcularia solo se podria
        -- deducir de una igualdad que la delegacion rompe. `NucleoEquipoSchema`
        -- del front es `v.object`, asi que la clave no molesta a nadie.
        'recalculo_vivo', jsonb_build_object(
          'divisor', (select coalesce(sum((f.e ->> 'nucleo_divisor')::int), 0)
                        from jsonb_array_elements(coalesce(v_payload -> 'responsables', '[]'::jsonb)) f(e)),
          'numerador', (select coalesce(sum((f.e ->> 'nucleo_numerador')::numeric), 0)
                        from jsonb_array_elements(coalesce(v_payload -> 'responsables', '[]'::jsonb)) f(e)))
        ), false);

    v_payload := jsonb_set(v_payload, '{sondas}',
      (v_payload -> 'sondas') || jsonb_build_object(
        'sin_fila_en_la_oficial', v_sin_fila), false);

    v_payload := jsonb_set(v_payload, '{responsables}',
      coalesce((
        select jsonb_agg(
          -- 🔴 A quien la oficial NO tiene, NO se le toca la cifra: se queda la
          -- que calculo esta funcion. Sobrescribirla con ceros le borraria de
          -- la pantalla lo que si tiene. (Medido el 22/09 en la puerta #5, que
          -- comparte esta trampa: 3 de 21 analistas sin fila en la oficial, y
          -- uno de ellos un SUPERVISOR ACTIVO con numerador 2.) Aqui hoy son
          -- 0, y `sondas.sin_fila_en_la_oficial` lo vigila.
          case when o.v is null then f.e
               else f.e || jsonb_build_object(
                 'nucleo_divisor', (o.v -> 'divisor'),
                 'nucleo_numerador', (o.v -> 'numerador'),
                 'nucleo_conversion_pct', (o.v -> 'conversion_pct'))
          end
          order by f.ord)
          from jsonb_array_elements(coalesce(v_payload -> 'responsables', '[]'::jsonb))
               with ordinality f(e, ord)
          left join lateral (
            select r.v from jsonb_array_elements(coalesce(v_oficial -> 'responsables', '[]'::jsonb)) r(v)
             where (r.v ->> 'vendedor_id') = (f.e ->> 'vendedor_id') limit 1
          ) o on true
      ), '[]'::jsonb), false);
  end if;

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
$function$
;

CREATE OR REPLACE FUNCTION crm.metricas_conversiones_fn(p_desde date, p_hasta date, p_origen text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION private.facturacion_lista(p_desde date, p_hasta date, p_dias date[] DEFAULT NULL::date[], p_analistas uuid[] DEFAULT NULL::uuid[], p_sin_analista boolean DEFAULT false, p_equipo uuid DEFAULT NULL::uuid, p_sin_equipo boolean DEFAULT false, p_tipos text[] DEFAULT NULL::text[], p_moneda text DEFAULT NULL::text, p_pagina integer DEFAULT 1, p_tamano integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_contratos_todos boolean;
  v_cooperativas_todas boolean;
  v_clientes uuid[] := '{}'::uuid[];
  v_vendedores uuid[] := '{}'::uuid[];
  v_resultado jsonb;
begin
  if p_desde is null or p_hasta is null or not isfinite(p_desde) or not isfinite(p_hasta)
      or p_hasta < p_desde or p_hasta - p_desde > 30 then
    raise exception 'Fechas inválidas: indicar desde y hasta, en orden, con un máximo de 31 días' using errcode = '22023';
  end if;
  if p_dias is not null and (cardinality(p_dias) = 0 or exists (
    select 1 from unnest(p_dias) d(dia) where d.dia is null or d.dia < p_desde or d.dia > p_hasta
  )) then
    raise exception 'Días inválidos: arreglo no vacío, sin NULL y dentro de desde/hasta' using errcode = '22023';
  end if;
  if p_pagina is null or p_pagina < 1 or p_tamano is null or p_tamano not in (25, 50, 100) then
    raise exception 'Paginación inválida: página desde 1 y tamaño 25, 50 o 100' using errcode = '22023';
  end if;
  if p_moneda is not null and p_moneda not in ('PEN', 'USD') then
    raise exception 'Moneda inválida: PEN, USD o NULL' using errcode = '22023';
  end if;
  if p_analistas is not null and p_sin_analista is true then
    raise exception 'Analistas y sin analista son filtros excluyentes' using errcode = '22023';
  end if;
  if p_equipo is not null and p_sin_equipo is true then
    raise exception 'Equipo y sin equipo son filtros excluyentes' using errcode = '22023';
  end if;
  if cardinality(p_analistas) = 0 or cardinality(p_tipos) = 0 then
    raise exception 'Analistas y tipos no admiten arreglos vacíos; usar NULL para todos' using errcode = '22023';
  end if;
  v_cooperativas_todas := coalesce(private.rol_crm(v_uid) = 'gerencia', false);
  v_contratos_todos := v_cooperativas_todas or coalesce(private.es_lector_global(), false);
  -- Una vez por petición, nunca por fila. La verja de operaciones sigue viviendo en la 3A.
  if not v_contratos_todos then
    v_clientes := array(select c.cliente_id from private.cliente_ids_visibles_crm() c);
    v_vendedores := array(select private.vendedor_ids_visibles(v_uid));
  end if;
  with filtradas as materialized (
    select o.* from private.facturacion_operaciones_visibles(
      (p_desde::timestamp at time zone 'America/Lima'),
      (((p_hasta + 1)::date)::timestamp at time zone 'America/Lima')
    ) o
    where (p_dias is null or o.dia = any(p_dias))
      and (p_analistas is null or o.analista_id = any(p_analistas))
      and (p_sin_analista is not true or o.analista_id is null)
      and (p_equipo is null or o.supervisor_id = p_equipo)
      and (p_sin_equipo is not true or o.supervisor_id is null)
      and (p_tipos is null or o.tipo = any(p_tipos))
      and (p_moneda is null or o.moneda = p_moneda)
  ), pagina as materialized (
    select row_number() over (order by o.fecha, o.tipo, o.operacion_id) as n, o.*
    from filtradas o order by o.fecha, o.tipo, o.operacion_id
    -- bigint evita desbordar integer en páginas grandes, que deben devolver vacío.
    offset (p_pagina::bigint - 1) * p_tamano limit p_tamano
  ), datos as (
    select p.*, c.numero_contrato, pc.nombre_completo as nombre_cliente,
      ce.nombre_completo as nombre_cooperativa, ce.cooperativa, ce.lead_id as lead_cierre,
      coalesce(case when p.tipo = 'cooperativa' then
        v_cooperativas_todas or (not v_contratos_todos and
          case when ce.inversionista_id is not null then i.responsable_relacion_id = any(v_vendedores)
               else l.vendedor_id = any(v_vendedores) end)
        else v_contratos_todos or p.cliente_id = any(v_clientes) end, false) as visible
    from pagina p
    left join public.contratos c on c.id = p.contrato_id
    left join public.perfiles pc on pc.id = p.cliente_id
    left join crm.cierres_externos ce on ce.id = p.cierre_externo_id
    -- Relación de HOY: regla del TELÉFONO VIVO de «En cooperativas» (crm.cierres_externos_fn),
    -- más estricta que el reparto de filas por analista_efectivo_cierre. Directorio siempre enmascara cooperativas.
    -- Resolución canónica solo para filas de la página (≤ 100) y si quien mira no es global.
    left join lateral (select private.inversionista_canonica(ce.inversionista_id) as id
                       where not v_contratos_todos and ce.inversionista_id is not null) can on true
    left join crm.inversionistas i on i.id = can.id
    left join crm.leads l on l.id = ce.lead_id
  ), filas as (
    select d.n, jsonb_build_object(
      'n', d.n, 'fecha', d.dia, 'tipo', d.tipo, 'moneda', d.moneda, 'monto', d.monto,
      'anulado', d.anulado, 'analista_id', d.analista_id,
      'analista_nombre', coalesce(pa.nombre_completo, 'Sin analista'),
      'supervisor_id', d.supervisor_id, 'supervisor_nombre', coalesce(ps.nombre_completo, 'Sin supervisor'),
      'visible', d.visible, 'cliente_nombre', case when not d.visible then 'Cliente de otro equipo'
        when d.tipo = 'cooperativa' then d.nombre_cooperativa else d.nombre_cliente end
    ) || case when not d.visible then '{}'::jsonb else
      jsonb_build_object('estado', d.estado) || case when d.tipo = 'cooperativa' then
        jsonb_build_object('cierre_externo_id', d.cierre_externo_id, 'cooperativa', d.cooperativa, 'lead_id', d.lead_cierre)
      else jsonb_build_object('contrato_id', d.contrato_id, 'numero_contrato', d.numero_contrato, 'cliente_id', d.cliente_id)
      end end as fila
    from datos d
    left join public.perfiles pa on pa.id = d.analista_id
    left join public.perfiles ps on ps.id = d.supervisor_id
  ), totales as (
    select moneda, count(*) as operaciones, sum(monto) as monto from filtradas group by moneda
  )
  select jsonb_build_object('version', 1, 'pagina', p_pagina, 'tamano', p_tamano,
    'total', (select count(*) from filtradas),
    'totales', coalesce((select jsonb_agg(to_jsonb(t) order by t.moneda) from totales t), '[]'::jsonb),
    'filas', coalesce((select jsonb_agg(f.fila order by f.n) from filas f), '[]'::jsonb)) into v_resultado;
  return v_resultado;
end;
$function$
;

CREATE OR REPLACE FUNCTION private.facturacion_operaciones_visibles(p_desde timestamp with time zone, p_hasta timestamp with time zone)
 RETURNS TABLE(operacion_id uuid, dia date, fecha timestamp with time zone, tipo text, moneda text, monto numeric, analista_id uuid, supervisor_id uuid, contrato_id uuid, cierre_externo_id uuid, cliente_id uuid, lead_id uuid, registrado_por uuid, categoria text, estado text, anulado boolean, fecha_vencimiento date)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with quien as materialized (
    -- Una sola vez: quién pregunta y con qué rol. `private.rol_crm` devuelve
    -- NULL para quien no es miembro del CRM.
    select
      (select auth.uid()) as uid,
      private.rol_crm((select auth.uid())) as rol,
      private.es_lector_global() as lector
  ),
  ambito as materialized (
    -- La verja, en tres columnas. NULL = 'gerencia' es NULL, y el coalesce lo
    -- cierra en false. `ok` abre el núcleo; `es_global` y `subarbol` recortan.
    select
      q.uid,
      coalesce(q.uid is not null and (q.rol = 'gerencia' or q.lector), false) as es_global,
      coalesce(q.uid is not null and (q.rol in ('gerencia', 'supervisor') or q.lector), false) as ok,
      -- El subárbol de HOY del supervisor (él incluido). Para cualquier otro
      -- rol queda VACÍO a propósito: así el predicado final no puede abrirse
      -- por accidente para nadie más.
      case when coalesce(q.uid is not null and q.rol = 'supervisor', false)
           then array(select private.vendedor_ids_visibles(q.uid))
           else '{}'::uuid[] end as subarbol
    from quien q
  )
  select ep.*
  from (select * from ambito a where a.ok) a
  -- La dependencia de a.ok mantiene el lateral detrás de la verja incluso si
  -- el planificador reordena joins: con cero actores autorizados no se llama.
  cross join lateral private.facturacion_operaciones(
    case when a.ok then p_desde end, p_hasta
  ) ep
  -- EL RECORTE DEL SUPERVISOR (ver cabecera): el supervisor de entonces es él o
  -- alguien de su subárbol, o la venta es suya. Gerencia y el lector global
  -- pasan enteros. Un `= any('{}')` es false y un supervisor NULL da NULL: para
  -- quien no es supervisor solo queda `es_global`, que para él es false — y de
  -- todos modos `episodios` ya salió vacío por `a.ok`.
  where a.es_global
     or ep.supervisor_id = any(a.subarbol)
     or ep.analista_id = a.uid;
$function$
;

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
  v_tope numeric;
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
  v_tope := private.tope_referidos_conversion(v_mes);

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
    -- Un renglón por lead (como el `distinct` de antes) con lo que su cierre aporta tras el tope de referidos.
    select e.lead_id, sum(e.aporte_numerador) as aporte
    from private.conversion_episodios(
      v_ini, v_cosecha_fin, null, true, null, v_factor
    ) e
    where e.tipo = 'cierre' and not e.anulado and private.conversion_origen_con_cierre(e.origen) and e.lead_id is not null
    group by e.lead_id
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
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and private.conversion_origen_con_cierre(e.origen) and not e.fue_referido)::int as cierres_no_referidos,
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and private.conversion_origen_con_cierre(e.origen) and e.fue_referido)::int as cierres_referidos,
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
      coalesce(sum(capital_lead_usd), 0) as capital_usd,
      coalesce(sum((select ec.aporte from ep_cosecha ec where ec.lead_id = cohorte.id)), 0) as aporte_cierres
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
      'tope_referidos_pct', v_tope,
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
          and private.conversion_origen_con_cierre(e.origen)
          and (p_origen is null or e.origen = p_origen)
      ),
      'aporte_cierres', (
        select coalesce(sum(e.aporte_numerador), 0)
        from ep_flujo e
        where e.tipo = 'cierre' and not e.anulado
          and private.conversion_origen_con_cierre(e.origen)
          and (p_origen is null or e.origen = p_origen)
      ),
      -- El total global conserva cierres de bajas, supervisores o autor nulo,
      -- mientras responsables[] sólo enumera vendedores activos. El residual
      -- hace visible esa diferencia sin reasignar el cierre a otra persona.
      'cierres_fuera_del_roster', (
        select count(distinct e.lead_id)::int
        from ep_flujo e
        where e.tipo = 'cierre' and not e.anulado
          and private.conversion_origen_con_cierre(e.origen)
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
          and private.conversion_origen_con_cierre(e.origen)
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
           and private.conversion_origen_con_cierre(e.origen)
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
        -- La MISMA cifra de la fila con cada cierre pesando lo que pesa en el
        -- numero grande (el referido, v_factor). La calcula el servidor para que
        -- la pantalla solo la muestre (Miguel, 23/09: «el servidor siempre que
        -- haga todo»).
        'conversion_ponderada_pct', case when o.leads > 0
          then round(100.0 * (case when o.origen = 'referido'
                                then (case when v_tope is not null then o.aporte_cierres else o.contratos * v_factor end)
                                else o.contratos end)
                     / o.leads, 1) end,
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
             and private.conversion_origen_con_cierre(e.origen)
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
$function$
;

CREATE OR REPLACE FUNCTION crm.metricas_cartera_fn(p_periodo date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_lector boolean := private.es_lector_global();
  v_global boolean;
  v_visibles uuid[];
  v_mes_actual date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_payload jsonb;
begin
  if v_uid is null or not coalesce(
    v_rol in ('vendedor', 'supervisor', 'gerencia') or v_lector, false
  ) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_periodo is null or p_periodo <> date_trunc('month', p_periodo)::date
     or p_periodo > v_mes_actual then
    raise exception 'Periodo inválido' using errcode = '22023';
  end if;
  v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
  v_visibles := case when v_global then '{}'::uuid[]
    else array(select private.vendedor_ids_visibles(v_uid)) end;

  with m as materialized (
    select x.* from private.metricas_cartera_por_vendedor(p_periodo) x
    where v_global or x.vendedor_id = any(v_visibles)
  ), total as (
    select
      coalesce(sum(m.conversiones_clientes), 0)::int as conversiones_clientes,
      coalesce(sum(m.conversiones_renovacion), 0)::int as conversiones_renovacion,
      coalesce(sum(m.conversiones_upgrade), 0)::int as conversiones_upgrade,
      coalesce(sum(m.operaciones_renovacion), 0)::int as operaciones_renovacion,
      coalesce(sum(m.operaciones_upgrade), 0)::int as operaciones_upgrade,
      coalesce(sum(m.capital_renovado_pen), 0) as capital_renovado_pen,
      coalesce(sum(m.capital_renovado_usd), 0) as capital_renovado_usd,
      coalesce(sum(m.capital_adicional_pen), 0) as capital_adicional_pen,
      coalesce(sum(m.capital_adicional_usd), 0) as capital_adicional_usd,
      coalesce(sum(m.renovaciones_sin_desglose), 0)::int as renovaciones_sin_desglose
    from m
  )
  select jsonb_build_object(
    'version', 1,
    'periodo', p_periodo,
    'alcance', case when v_global then 'global'
                    when v_rol = 'supervisor' then 'equipo' else 'propio' end,
    'total', to_jsonb(t),
    'responsables', coalesce((
      select jsonb_agg(to_jsonb(m) order by m.vendedor_id) from m
    ), '[]'::jsonb)
  ) into v_payload from total t;
  return v_payload;
end;
$function$
;
do $guardia$
declare r record;
begin
  for r in select * from (values
    ('crm.conversion_mensual_fn(date)', 'e8b7bbfa62e46bcd5a680a9a5996a8d0'),
    ('crm.conversion_mensual_sin_cartera_fn(date)', 'b45d501e5d8f6b56b37daaecc68b3baf'),
    ('crm.cumplimiento_metas_fn(date)', '8da0630bf31cb1bb2f22fc929856fc2e'),
    ('crm.cumplimiento_metas_sin_cartera_fn(date)', '1b6ae972783da423859974d142e406d1'),
    ('crm.metricas_conversiones_equipo_fn(date,date)', '49ac2ac5f0a1b8ca32079e32aff4a0fe'),
    ('crm.metricas_conversiones_fn(date,date,text)', '5edb160355011bd0485661485c9317df'),
    ('private.facturacion_lista(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)', 'e8c3178b74ec5718e87b5b5fc697e1fd'),
    ('private.facturacion_operaciones_visibles(timestamp with time zone,timestamp with time zone)', '17c2ca27996adad88f685896915953e3'),
    ('private.metricas_conversiones_implementacion(date,date,text)', 'c3c78d48c672716517af47641d19aa1b'),
    ('crm.metricas_cartera_fn(date)', '0bfcc0d49bec2f6fda3cc844b813118c')
  ) f(firma, huella) loop
    if (select md5(pg_get_functiondef(to_regprocedure(r.firma)))) is distinct from r.huella then
      raise exception 'Permisos de Coordinación: cuerpo inesperado en %, se deshace todo', r.firma;
    end if;
  end loop;
end $guardia$;
do $contrato$
begin
  if exists(select 1 from pg_temp.coord_acl a join pg_proc p on p.oid = a.oid
    where p.proacl is distinct from a.proacl or p.proowner <> a.proowner
      or p.prosecdef <> a.prosecdef or p.provolatile <> a.provolatile or p.proconfig is distinct from a.proconfig) then
    raise exception 'Coordinación reportes: cambió el contrato o ACL de una función existente';
  end if;
end $contrato$;
drop function crm.equipo_reportes_fn();
drop function private.cierre_mes_reportes_visible(date,uuid);
drop function private.es_coordinador_reportes();
commit;

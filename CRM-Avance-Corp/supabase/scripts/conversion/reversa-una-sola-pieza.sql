-- =========================================================================
-- REVERSA de 20260923164903_crm_una_sola_pieza_de_conversion
-- =========================================================================
-- Devuelve las tres puertas a sus cuerpos EXACTOS de antes (copiados de
-- pg_get_functiondef en produccion el 23/09/2026), restaura huella y razon del
-- censo y los tres COMMENT ON, y retira las dos piezas del nucleo. Todo en una
-- transaccion: o vuelve entero o no vuelve nada.
--
-- Restauracion FUNCIONAL: el sello de la lista del censo se recalcula y queda con
-- `sellado_en` de HOY, no con la fecha original (es lo que hace cualquier re-sello).
--
-- SOLO revierte ESTA migracion: el preflight exige que los tres cuerpos vivos sean
-- EXACTAMENTE los que ella instalo. Si alguien los cambio despues, se niega, y hay
-- que escribir una reversa nueva sobre lo que haya entonces.
--
-- COMO SE CORRE (lo aplica Miguel, como toda escritura en produccion):
--   supabase db query --linked --file supabase/scripts/conversion/reversa-una-sola-pieza.sql
--
-- Lo que la migracion cambio y esta reversa deshace: la #8 y la #7 vuelven a
-- declarar `rango_vivo` en el mes abierto y a calcular su cifra por su cuenta.
-- =========================================================================

begin;

set local statement_timeout = '120s';
set local lock_timeout = '5s';
lock table private.analitica_leads_citas_exenciones,
           private.analitica_lc_sello in share row exclusive mode;

do $preflight$
declare r record; v_md5 text;
begin
  for r in
    select * from (values
      ('crm.conversion_mensual_sin_cartera_fn(date)', '3f59adbd9e145b9d20cbbaf9d5238311'),
      ('crm.cumplimiento_metas_sin_cartera_fn(date)', '1b6ae972783da423859974d142e406d1'),
      ('crm.cumplimiento_metas_fn(date)',             '8da0630bf31cb1bb2f22fc929856fc2e')
    ) t(objeto, esperado)
  loop
    select md5(pg_get_functiondef(p.oid)) into v_md5 from pg_proc p where p.oid = to_regprocedure(r.objeto);
    if v_md5 is distinct from r.esperado then
      raise exception 'REVERSA: % no es el cuerpo que instalo 20260923164903 (md5 %); no se revierte a ciegas',
        r.objeto, coalesce(v_md5, 'no existe');
    end if;
  end loop;
  if to_regprocedure('private.conversion_neta_por_vendedor(date,boolean,uuid[])') is null
     or to_regprocedure('private.roster_conversion_mensual(date,boolean,uuid[])') is null then
    raise exception 'REVERSA: las piezas no existen; la migracion no esta aplicada';
  end if;
  if (select e.huella from private.analitica_leads_citas_exenciones e
       where e.objeto = 'crm.conversion_mensual_sin_cartera_fn(date)') is distinct from 'bb316b2398d0001bc9407a699084c8f5' then
    raise exception 'REVERSA: la declaracion de la oficial en el censo no es la que dejo la migracion';
  end if;
  if (select e.razon from private.analitica_leads_citas_exenciones e
       where e.objeto = 'crm.conversion_mensual_sin_cartera_fn(date)') is distinct from 'Nucleo por TRANSITIVIDAD (llama a conversion_mensual_por_vendedor): sirve el mes sellado desde las tablas del cierre y, con el mes ABIERTO, calcula en vivo por el mismo puente; sus counts propios son cobertura y altas del periodo. Recertificada 2026-09-07 sobre fuente exacta revisada: conserva la puerta y la misma pregunta operativa; cambios presentes en producción, sin reescribir cuerpos. Una sola pieza (23/09/2026): la cifra por persona del mes abierto sale de private.conversion_neta_por_vendedor, la misma que usa Metas, y quien sale nombrado, de private.roster_conversion_mensual. Sigue siendo nucleo por transitividad.' then
    raise exception 'REVERSA: la razon del censo de la oficial cambio despues de la migracion; no se pisa';
  end if;
  if private.assert_analitica_leads_citas() not like 'OK:%' then
    raise exception 'REVERSA: el trinquete ya estaba en rojo';
  end if;
end;
$preflight$;

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
    -- El MISMO neto que publica crm.conversion_mensual_fn: si esta pantalla
    -- enseñara el bruto, el mismo asesor tendria dos porcentajes distintos otra
    -- vez — la deuda que la migracion 20260813212332 vino a borrar.
    select cm.analista_id as vendedor_id,
      (cm.cierres_no_referidos+cm.cierres_referidos)::integer as convertidos,
      cm.divisor::integer as resueltos,
      -- ⚠️ `pd.numerador`, NO `pd.pendiente`. Aqui `pd` es la FUNCION
      -- `private.ajuste_pendiente_por_vendedor()`, que devuelve
      -- (vendedor_id, numerador, capital_pen, capital_usd, origenes) — no tiene
      -- ninguna columna `pendiente`. El bloque de la conversion, mas arriba, si
      -- usa `pd.pendiente`, pero alli `pd` es una CTE que renombra
      -- `ap.numerador as pendiente`: mismo alias, dos cosas distintas.
      --
      -- 🔴 ESTO ESTUVO ROTO Y EN VERDE. plpgsql no valida el SQL de un cuerpo al
      -- crearlo, asi que la funcion se creaba sin protestar y reventaba con
      -- 42703 en la PRIMERA llamada, para TODOS los roles: la pantalla de metas
      -- entera. El oraculo daba 20/20 porque nunca la llamaba — solo la
      -- nombraba en un comentario. Lo cazo el gate de RLS en la branch.
      private.conversion_con_ajuste(cm.numerador, pd.numerador) as numerador,
      cm.cierres_no_referidos,
      cm.cierres_referidos,
      case when cm.divisor > 0
        then round(100.0 * private.conversion_con_ajuste(cm.numerador, pd.numerador)
                   / cm.divisor, 2) end as conversion_real,
      coalesce(pd.numerador, 0::numeric) as ajuste_pendiente
    from private.conversion_mensual_por_vendedor(
      v_ini,v_fin,true,'{}'::uuid[],v_factor) cm
    left join private.ajuste_pendiente_por_vendedor() pd
      on pd.vendedor_id = cm.analista_id
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
    -- DECLARACION. RAMA DEL MES ABIERTO: la cifra se CALCULA aqui, sobre
    -- `private.conversion_mensual_por_vendedor`, pero SI resta la deuda con
    -- `private.conversion_con_ajuste`. Por eso `rango_vivo` con
    -- `ajuste_aplicado: true`: coincide con la oficial, pero no se la pidio.
    'es_mes_calendario', true,
    'fuente', 'rango_vivo',
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
$function$;

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
  v_factor numeric;
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
    v_factor := private.peso_referido_conversion(p_periodo);
    select mp.id into v_periodo_id
    from crm.meta_periodos mp
    where mp.periodo = p_periodo
    order by mp.revision desc
    limit 1;

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
$function$;

comment on function crm.conversion_mensual_sin_cartera_fn(date) is
  'Nucleo mensual de conversion: mes vigente con roster operativo, historico abierto con la ultima publicacion de ese mes y cerrado desde la foto sellada. El total.analistas cuenta solo responsables rankeables; Gerencia conserva divisor, numerador, porcentaje y produccion fuera del ranking en el total empresarial.';

comment on function crm.cumplimiento_metas_sin_cartera_fn(date) is
  'Cumplimiento de metas SIN cartera, y motor del payload de crm.cumplimiento_metas_fn, que lo HEREDA (por eso declararla aqui declara tambien la de Metas y Ranking). Declara de donde sale su cifra: en la rama del mes SELLADO, de la foto de crm.periodos_cerrados (fuente=mensual, sellado=true); en la del mes ABIERTO, de private.conversion_mensual_por_vendedor con private.conversion_con_ajuste aplicado (fuente=rango_vivo, sellado=false). En las dos, es_mes_calendario=true y ajuste_aplicado=true: SI resta la deuda de los cierres anulados, y por eso no discrepa de la oficial.';

comment on function crm.cumplimiento_metas_fn(date) is
  'Cumplimiento mensual sobre el nucleo existente. En abierto incorpora conversiones de cartera vivas; en cerrado las incorpora desde la misma foto mensual, sin recalcular el pasado. Solo Gerencia recibe fuera_ranking con la produccion identificada que no pertenece a analistas rankeables.';

drop function private.conversion_neta_por_vendedor(date, boolean, uuid[]);
drop function private.roster_conversion_mensual(date, boolean, uuid[]);

update private.analitica_leads_citas_exenciones e
   set huella = md5(regexp_replace(regexp_replace(
                      lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
                      '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')),
       razon  = 'Nucleo por TRANSITIVIDAD (llama a conversion_mensual_por_vendedor): sirve el mes sellado desde las tablas del cierre y, con el mes ABIERTO, calcula en vivo por el mismo puente; sus counts propios son cobertura y altas del periodo. Recertificada 2026-09-07 sobre fuente exacta revisada: conserva la puerta y la misma pregunta operativa; cambios presentes en producción, sin reescribir cuerpos.'
  from pg_proc p
 where p.oid = to_regprocedure(e.objeto)
   and e.objeto = 'crm.conversion_mensual_sin_cartera_fn(date)';

update private.analitica_lc_sello
   set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
 where id;

do $postflight$
declare r record; v_md5 text;
begin
  for r in
    select * from (values
      ('crm.conversion_mensual_sin_cartera_fn(date)', 'e2e2bf8fe3c71620a3db01de3cddc33b'),
      ('crm.cumplimiento_metas_sin_cartera_fn(date)', '5ae6fb2a02b63658b76b7c368c0c8588'),
      ('crm.cumplimiento_metas_fn(date)',             '0bde18875efbb757801633571e558ca2')
    ) t(objeto, esperado)
  loop
    select md5(pg_get_functiondef(p.oid)) into v_md5 from pg_proc p where p.oid = to_regprocedure(r.objeto);
    if v_md5 is distinct from r.esperado then
      raise exception 'REVERSA: % no volvio a su cuerpo exacto (md5 %)', r.objeto, v_md5;
    end if;
  end loop;
  if to_regprocedure('private.conversion_neta_por_vendedor(date,boolean,uuid[])') is not null
     or to_regprocedure('private.roster_conversion_mensual(date,boolean,uuid[])') is not null then
    raise exception 'REVERSA: una pieza sigue existiendo';
  end if;
  if (select e.huella from private.analitica_leads_citas_exenciones e
       where e.objeto = 'crm.conversion_mensual_sin_cartera_fn(date)')
     is distinct from 'e8308294375859236ecf03e8133c176e' then
    raise exception 'REVERSA: la huella del censo de la oficial no volvio a la de antes';
  end if;
  if (select e.razon from private.analitica_leads_citas_exenciones e
       where e.objeto = 'crm.conversion_mensual_sin_cartera_fn(date)') is distinct from 'Nucleo por TRANSITIVIDAD (llama a conversion_mensual_por_vendedor): sirve el mes sellado desde las tablas del cierre y, con el mes ABIERTO, calcula en vivo por el mismo puente; sus counts propios son cobertura y altas del periodo. Recertificada 2026-09-07 sobre fuente exacta revisada: conserva la puerta y la misma pregunta operativa; cambios presentes en producción, sin reescribir cuerpos.' then
    raise exception 'REVERSA: la razon del censo no volvio a la exacta de antes';
  end if;
  if private.assert_analitica_leads_citas() not like 'OK:%' then
    raise exception 'REVERSA: el trinquete quedo en rojo';
  end if;
end;
$postflight$;

commit;

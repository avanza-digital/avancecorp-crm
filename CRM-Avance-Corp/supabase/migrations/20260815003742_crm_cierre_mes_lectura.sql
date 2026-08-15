-- ---------------------------------------------------------------------------
-- Un mes cerrado se LEE de su foto, no se vuelve a calcular
-- ---------------------------------------------------------------------------
-- QUE HACE. `crm.conversion_mensual_fn` y `crm.cumplimiento_metas_fn` pasan a
-- mirar primero si el mes esta cerrado. Si lo esta, sirven la foto sellada por
-- `crm.cerrar_periodo` (migracion 20260815002914). Si no, se comportan
-- exactamente como hoy.
--
-- Sin esto el sello es un archivo que nadie abre: el mes seguiria moviendose en
-- pantalla mientras la foto, correcta, dormiria en una tabla.
--
-- ⚠️ EL AMBITO DEL MES CERRADO SALE DE LA FOTO, NO DEL EQUIPO DE HOY. Es la
-- parte que menos se ve y la que mas importa. En un mes ABIERTO, un supervisor
-- ve a los vendedores que `private.vendedor_ids_visibles` dice que son suyos
-- HOY. Si un mes cerrado usara ese mismo criterio, bastaria un cambio de equipo
-- en noviembre para que el agosto de ese supervisor cambiara de numero — que es
-- exactamente la enfermedad que el sello viene a curar, solo que por la puerta
-- de al lado. Por eso el mes cerrado se recorta con el `supervisor_id`
-- SELLADO.
--
-- ⚠️ Y NO SE VUELVE A FILTRAR POR «¿SIGUE SIENDO VENDEDOR?». La funcion viva
-- termina en `private.filtrar_desglose_sujetos_crm`, una defensa que descarta a
-- quien hoy no tenga rol de vendedor. Aplicarla sobre una foto BORRARIA del
-- registro de pago a quien se fue del equipo — el caso concreto que el sello
-- congela el nombre para conservar. En un mes cerrado, quien cobro estuvo, y eso
-- ya no cambia.
--
-- EL TOTAL se recalcula sumando las filas VISIBLES de la foto, con la formula de
-- siempre (`sum(numerador)/sum(divisor)`, nunca la media de los porcentajes). No
-- se guarda un total sellado a proposito: dos fuentes para el mismo numero
-- divergen, y aqui la fuente son las filas.
--
-- El payload gana UNA clave, `cierre`, con la fecha del sello. El esquema del
-- front tolera claves nuevas (`v.object` laxo, con test que lo fija), asi que
-- esto no rompe a un cliente viejo: simplemente no la pinta.
--
-- NO TOCA NADA DE `public` ni cambia policies ni grants.
-- ---------------------------------------------------------------------------

begin;

set local lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- 0. Preflight
-- ---------------------------------------------------------------------------
do $preflight$
begin
  if to_regclass('crm.cierre_mes_vendedor') is null
     or to_regclass('crm.periodos_cerrados') is null then
    raise exception 'Faltan las tablas del cierre: aplicar antes 20260815002914.';
  end if;
  -- El cuerpo del que se parte, para que el reemplazo no pise una version
  -- distinta de la que se leyo al escribir esto.
  if (select md5(pg_catalog.pg_get_functiondef(p.oid))
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'conversion_mensual_fn')
     is distinct from 'e6a7ba3f5990346ca47e51e57da8f7fe' then
    raise exception 'crm.conversion_mensual_fn cambio desde que se escribio esta migracion: revisar antes de aplicar.';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. El ambito de un mes cerrado, escrito UNA vez
-- ---------------------------------------------------------------------------
-- Las dos funciones de lectura necesitan el mismo recorte, y escribirlo dos
-- veces es la deuda que este esquema ya pago con la conversion.
create or replace function private.cierre_mes_visible(
  p_periodo date,
  p_uid uuid
)
returns setof crm.cierre_mes_vendedor
language sql
stable
security definer
set search_path = ''
as $$
  select f.*
  from crm.cierre_mes_vendedor f
  where f.periodo = p_periodo
    and (
      -- Gerencia y el lector global ven la foto entera.
      private.es_lector_global()
      or private.rol_crm(p_uid) = 'gerencia'
      -- El supervisor ve a los que eran SUYOS ese mes, no los de hoy, y a si
      -- mismo (puede tener cartera propia).
      or f.supervisor_id = p_uid
      -- Y cualquiera se ve a si mismo.
      or f.vendedor_id = p_uid
    )
$$;

comment on function private.cierre_mes_visible(date, uuid) is
  'Las filas de la foto de un mes cerrado que un actor puede ver. El recorte del supervisor sale del supervisor_id SELLADO, no del equipo de hoy: si no, un cambio de equipo en noviembre movería su agosto.';

revoke all on function private.cierre_mes_visible(date, uuid) from public;

-- ---------------------------------------------------------------------------
-- 2. La conversion de un mes cerrado
-- ---------------------------------------------------------------------------
create or replace function crm.conversion_mensual_fn(p_periodo date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
    ), resumen as (
      -- El total se RECALCULA sumando, nunca promediando porcentajes.
      select
        count(*)::int as analistas,
        coalesce(sum(v.divisor), 0)::int as divisor,
        coalesce(sum(v.divisor_aproximado), 0)::int as divisor_aproximado,
        coalesce(sum(v.cierres_no_referidos), 0)::int as cierres_no_referidos,
        coalesce(sum(v.cierres_referidos), 0)::int as cierres_referidos,
        coalesce(sum(v.cierres_de_arrastre), 0)::int as cierres_de_arrastre,
        coalesce(sum(v.referidos_recibidos), 0)::int as referidos_recibidos,
        coalesce(sum(v.numerador), 0::numeric) as numerador
      from visibles v
    ), motivos as (
      select e.key as motivo, sum(e.value::int)::int as n
      from visibles v, jsonb_each_text(v.divisor_por_motivo) e
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
        'fuente', 'crm.conversion_pesos'
      ),
      -- Los mismos tokens de contrato que el mes abierto: el front los valida
      -- con `v.literal` y un mes cerrado no puede hablar otro idioma.
      'fuentes', jsonb_build_object(
        'divisor', 'crm.lead_asignaciones.asignado_en',
        'numerador', 'crm.lead_asignaciones.resultado_en',
        'referido', 'crm.lead_asignaciones.origen'
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
        -- Y no hay «fuera de roster» en una foto: al sellar, TODO el que produjo
        -- entro con su nombre. Esa es media razon de existir del sello.
        'fuera_de_roster', jsonb_build_object(
          'analistas', 0, 'divisor', 0, 'cierres', 0, 'numerador', 0)
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

  -- 4) Mes ABIERTO: exactamente el comportamiento de siempre.
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
     and not exists (
       select 1 from private.roster_metas_vendedores() r
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
    from private.roster_metas_vendedores() r
    where v_global or r.vendedor_id = any(v_visibles)
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
    select
      count(*)::int as analistas,
      coalesce(sum(b.divisor), 0)::int as divisor,
      coalesce(sum(b.cierres_no_referidos + b.cierres_referidos), 0)::int as cierres,
      coalesce(sum(b.numerador), 0::numeric) as numerador
    from base b
    where not exists (select 1 from roster r where r.vendedor_id = b.analista_id)
  ),
  motivos_totales as (
    select e.key as motivo, sum(e.value::int)::int as n
    from filas f, jsonb_each_text(f.divisor_por_motivo) e
    group by e.key
  ),
  sonda as (
    select count(*)::int as cierres_sin_episodio
    from crm.leads l
    where l.etapa = 'convertido'
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
    select
      count(*)::int as analistas,
      coalesce(sum(f.divisor), 0)::int as divisor,
      coalesce(sum(f.divisor_aproximado), 0)::int as divisor_aproximado,
      coalesce(sum(f.cierres_no_referidos), 0)::int as cierres_no_referidos,
      coalesce(sum(f.cierres_referidos), 0)::int as cierres_referidos,
      coalesce(sum(f.cierres_de_arrastre), 0)::int as cierres_de_arrastre,
      coalesce(sum(f.referidos_recibidos), 0)::int as referidos_recibidos,
      coalesce(sum(f.numerador), 0::numeric) as numerador
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
      'fuente', 'crm.conversion_pesos'
    ),
    'fuentes', jsonb_build_object(
      'divisor', 'crm.lead_asignaciones.asignado_en',
      'numerador', 'crm.lead_asignaciones.resultado_en',
      'referido', 'crm.lead_asignaciones.origen'
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

  return private.filtrar_desglose_sujetos_crm(
    v_payload, 'responsables', 'vendedor_id', array['vendedor']
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. El cumplimiento de metas de un mes cerrado
-- ---------------------------------------------------------------------------
create or replace function crm.cumplimiento_metas_fn(p_periodo date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
      private.conversion_con_ajuste(cm.numerador, pd.pendiente) as numerador,
      cm.cierres_no_referidos,
      cm.cierres_referidos,
      case when cm.divisor > 0
        then round(100.0 * private.conversion_con_ajuste(cm.numerador, pd.pendiente)
                   / cm.divisor, 2) end as conversion_real,
      coalesce(pd.pendiente, 0::numeric) as ajuste_pendiente
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
$$;

-- ---------------------------------------------------------------------------
-- 4. Postflight
-- ---------------------------------------------------------------------------
do $postflight$
begin
  -- Las dos funciones consultan el cierre. `strpos` y NO `like`: el guion bajo
  -- es comodin en LIKE (trampa que ya freno un despliegue el 2026-08-14).
  if (select strpos(p.prosrc, 'periodos_cerrados')
        from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'conversion_mensual_fn') = 0 then
    raise exception 'crm.conversion_mensual_fn no mira si el mes esta cerrado.';
  end if;
  if (select strpos(p.prosrc, 'periodos_cerrados')
        from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'cumplimiento_metas_fn') = 0 then
    raise exception 'crm.cumplimiento_metas_fn no mira si el mes esta cerrado.';
  end if;

  -- El mes ABIERTO conserva su defensa de sujetos. Si esto desapareciera, la
  -- funcion viva estaria publicando a quien ya no es vendedor.
  if (select strpos(p.prosrc, 'filtrar_desglose_sujetos_crm')
        from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'conversion_mensual_fn') = 0 then
    raise exception 'crm.conversion_mensual_fn perdio filtrar_desglose_sujetos_crm en la rama del mes abierto.';
  end if;

  -- El helper de ambito existe y es DEFINER con search_path fijo.
  if not exists (
    select 1 from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname = 'cierre_mes_visible'
      and p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=%'
  ) then
    raise exception 'private.cierre_mes_visible no quedo como DEFINER con search_path fijo.';
  end if;
end;
$postflight$;

commit;

-- ---------------------------------------------------------------------------
-- VUELTA ATRAS
-- ---------------------------------------------------------------------------
-- `supabase/scripts/rollback-cierre-mes-lectura.sql` restaura los cuerpos
-- anteriores de las dos funciones (las fotos se quedan donde estan, sin
-- consumir). Es la vuelta atras SEGURA aunque ya haya meses cerrados.

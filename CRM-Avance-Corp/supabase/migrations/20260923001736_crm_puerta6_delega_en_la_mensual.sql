-- =========================================================================
-- CRM · Ola 1b · La puerta #6 DELEGA su cifra por vendedor en la mensual
-- =========================================================================
-- QUE HACE: cuando el rango es un mes calendario completo,
-- `crm.metricas_conversiones_equipo_fn` deja de publicar su propia division
-- por vendedor y publica `nucleo_divisor`, `nucleo_numerador` y
-- `nucleo_conversion_pct` tal como los sirve `crm.conversion_mensual_fn`,
-- emparejando por `vendedor_id`. Fuera de esa condicion no cambia nada.
--
-- ESTO SI PUEDE MOVER UN NUMERO, y ese es el objetivo. Hoy no lo mueve: no hay
-- ningun mes sellado ni deuda de anulacion. Lo movera el dia que la haya, y la
-- movera HACIA la oficial, la unica capa que descuenta.
--
-- MEDIDO EN PRODUCCION (22/09, deuda de 2 puntos plantada y deshecha): con la
-- deuda puesta, la oficial y las puertas #7 y #8 bajan el numerador de 6 a 4
-- para ese analista; la #6 se quedaba en 6. Eso es lo que esta migracion
-- arregla.
--
-- LO QUE NO SE TOCA: `leads`, `clientes` y el `conversion_pct` de la fila son
-- la medida de COHORTE (convertidos entre leads recibidos), otra cosa distinta
-- de la conversion ponderada del nucleo. Siguen saliendo del calculo propio.
--
-- SI UN VENDEDOR DEL ROSTER NO TIENE FILA EN LA OFICIAL, su cifra no se
-- fabrica: se cuenta en la sonda nueva `sondas.sin_fila_en_la_oficial` (hoy 0,
-- y el postflight lo exige) y `nucleo_conversion_pct` queda en `null`, no en 0.
-- La sonda cabe porque `SondasEquipoSchema` del front es `v.object`, que
-- ignora lo que no conoce (`app/src/lib/metricas-conversiones-equipo.ts:80`).
--
-- FIJADO EN EL PREFLIGHT (medido tras la Ola 1a):
--   · cuerpo vivo: md5(pg_get_functiondef) = b2c5be9fbc975b52ce1d00005cb07189
--   · dueno: postgres · declarada clase `mixta` pero FUERA del censo de
--     contadores crudos, asi que NO se re-sella (escribir una huella que nadie
--     comprueba borraria el aviso del dia que entre). El postflight exige que
--     siga fuera.
--
-- REVERSA: volver a declarar el cuerpo sin el bloque de sustitucion.
-- =========================================================================

begin;

set local statement_timeout = '180s';

do $preflight$
declare v_md5 text; v_dueno text;
begin
  select md5(pg_get_functiondef(p.oid)), p.proowner::regrole::text into v_md5, v_dueno
    from pg_proc p where p.oid = to_regprocedure('crm.metricas_conversiones_equipo_fn(date,date)');
  if v_md5 is null then
    raise exception 'PREFLIGHT: la puerta no existe';
  end if;
  if v_md5 <> 'b2c5be9fbc975b52ce1d00005cb07189' then
    raise exception 'PREFLIGHT: el cuerpo vivo NO es el revisado (md5 %)', v_md5;
  end if;
  if v_dueno <> 'postgres' then
    raise exception 'PREFLIGHT: dueno inesperado %', v_dueno;
  end if;
  if to_regprocedure('crm.conversion_mensual_fn(date)') is null then
    raise exception 'PREFLIGHT: crm.conversion_mensual_fn(date) no existe';
  end if;
end;
$preflight$;

create temp table _p6b_antes (payload jsonb, oficial jsonb) on commit drop;

do $antes$
declare
  v_claims text := current_setting('request.jwt.claims', true);
  v_gerente uuid;
begin
  select e.perfil_id into v_gerente from crm.equipo e
   where e.rol_crm = 'gerencia' and e.activo and private.rol_crm(e.perfil_id) = 'gerencia'
   order by e.perfil_id limit 1;
  if v_gerente is null then
    raise exception 'PREFLIGHT: no hay perfil de gerencia activo';
  end if;
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_gerente, 'role', 'authenticated')::text, true);
  begin
    insert into _p6b_antes (payload, oficial)
    select crm.metricas_conversiones_equipo_fn(
             date_trunc('month', (now() at time zone 'America/Lima'))::date,
             (now() at time zone 'America/Lima')::date),
           crm.conversion_mensual_fn(date_trunc('month', (now() at time zone 'America/Lima'))::date);
  exception when others then
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
end;
$antes$;

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
    where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.lead_id is not null
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
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and not e.fue_referido)::int as cierres_no_referidos,
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.fue_referido)::int as cierres_referidos,
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
      'peso_renovacion', v_factor,
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
$function$;

-- ---------------------------------------------------------------------------
-- POSTFLIGHT
-- ---------------------------------------------------------------------------
create temp table _p6b_despues (payload jsonb) on commit drop;

do $postflight$
declare
  v_ok text; v_antes jsonb; v_of jsonb; v_despues jsonb; v_parcial jsonb;
  v_a jsonb; v_d jsonb; v_desvio int;
  v_claims text := current_setting('request.jwt.claims', true);
  v_gerente uuid;
begin
  v_ok := private.assert_analitica_leads_citas();
  if v_ok not like 'OK:%' then
    raise exception 'POSTFLIGHT: el trinquete quedo en rojo: %', v_ok;
  end if;

  select payload, oficial into v_antes, v_of from _p6b_antes;

  select e.perfil_id into v_gerente from crm.equipo e
   where e.rol_crm = 'gerencia' and e.activo and private.rol_crm(e.perfil_id) = 'gerencia'
   order by e.perfil_id limit 1;
  if v_gerente is null then
    raise exception 'POSTFLIGHT: no hay perfil de gerencia activo';
  end if;
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_gerente, 'role', 'authenticated')::text, true);
  begin
    v_despues := crm.metricas_conversiones_equipo_fn(
                   date_trunc('month', (now() at time zone 'America/Lima'))::date,
                   (now() at time zone 'America/Lima')::date);
    v_parcial := crm.metricas_conversiones_equipo_fn(
                   (date_trunc('month', (now() at time zone 'America/Lima')) - interval '1 month')::date,
                   (date_trunc('month', (now() at time zone 'America/Lima')) - interval '1 month')::date + 1);
  exception when others then
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  insert into _p6b_despues (payload) values (v_despues);

  -- 1) Cada fila publica, exactamente, la cifra de la oficial para ese vendedor.
  select count(*)::int into v_desvio
    from jsonb_array_elements(v_despues -> 'responsables') f(e)
    join jsonb_array_elements(v_of -> 'responsables') r(v)
      on (r.v ->> 'vendedor_id') = (f.e ->> 'vendedor_id')
   where (f.e -> 'nucleo_divisor')        is distinct from (r.v -> 'divisor')
      or (f.e -> 'nucleo_numerador')      is distinct from (r.v -> 'numerador')
      or (f.e -> 'nucleo_conversion_pct') is distinct from (r.v -> 'conversion_pct');
  if v_desvio <> 0 then
    raise exception 'POSTFLIGHT: % filas NO publican la cifra oficial', v_desvio;
  end if;

  -- 2) La sonda cuenta a quien la oficial no tiene (hoy: 0). No es un error
  --    que haya alguno —su cifra se queda como estaba, no se fabrica—, pero la
  --    pantalla tiene que poder saberlo.
  if (v_despues #>> '{sondas,sin_fila_en_la_oficial}') is null then
    raise exception 'POSTFLIGHT: falta la sonda sin_fila_en_la_oficial';
  end if;
  if (v_despues #>> '{sondas,sin_fila_en_la_oficial}')::int <> 0 then
    raise exception 'POSTFLIGHT: hoy deberian ser 0 y son %; revisar antes de seguir',
      v_despues #>> '{sondas,sin_fila_en_la_oficial}';
  end if;

  -- 3) Declara que delego.
  if (v_despues #>> '{nucleo,fuente}') is distinct from 'mensual'
     or (v_despues #> '{nucleo,sellado}') is distinct from (v_of #> '{cierre,cerrado}')
     or (v_despues #>> '{nucleo,ajuste_aplicado}')::boolean is not true
     or (v_despues #>> '{nucleo,es_mes_calendario}')::boolean is not true then
    raise exception 'POSTFLIGHT: delego pero no lo declara: %', v_despues -> 'nucleo';
  end if;

  -- 4) HOY, sin deuda, ninguna cifra se mueve.
  select count(*)::int into v_desvio
    from jsonb_array_elements(v_antes -> 'responsables') a(e)
    join jsonb_array_elements(v_despues -> 'responsables') d(e)
      on (a.e ->> 'vendedor_id') = (d.e ->> 'vendedor_id')
   where (a.e -> 'nucleo_divisor')        is distinct from (d.e -> 'nucleo_divisor')
      or (a.e -> 'nucleo_numerador')      is distinct from (d.e -> 'nucleo_numerador')
      or (a.e -> 'nucleo_conversion_pct') is distinct from (d.e -> 'nucleo_conversion_pct');
  if v_desvio <> 0 then
    raise exception 'POSTFLIGHT: % filas cambiaron HOY, y hoy no hay deuda que justifique un cambio', v_desvio;
  end if;
  if jsonb_array_length(v_antes -> 'responsables') <> jsonb_array_length(v_despues -> 'responsables') then
    raise exception 'POSTFLIGHT: cambio el numero de filas (% -> %)',
      jsonb_array_length(v_antes -> 'responsables'), jsonb_array_length(v_despues -> 'responsables');
  end if;

  -- 5) Y nada mas del payload se movio.
  v_a := (v_antes - 'generado_en' - 'responsables')
           #- '{nucleo,fuente}' #- '{nucleo,sellado}' #- '{nucleo,ajuste_aplicado}'
           #- '{nucleo,recalculo_vivo}' #- '{sondas,sin_fila_en_la_oficial}';
  v_d := (v_despues - 'generado_en' - 'responsables')
           #- '{nucleo,fuente}' #- '{nucleo,sellado}' #- '{nucleo,ajuste_aplicado}'
           #- '{nucleo,recalculo_vivo}' #- '{sondas,sin_fila_en_la_oficial}';
  if v_a is distinct from v_d then
    raise exception 'POSTFLIGHT: cambio algo fuera de la cifra y su declaracion. Bloques distintos: %',
      (select string_agg(k, ', ' order by k) from jsonb_object_keys(v_a) k
        where (v_a -> k) is distinct from (v_d -> k));
  end if;

  -- 5b) `recalculo_vivo` guarda la suma de lo que la puerta calculaba.
  if (v_despues #> '{nucleo,recalculo_vivo,numerador}') is null then
    raise exception 'POSTFLIGHT: falta recalculo_vivo';
  end if;
  if (v_parcial #> '{nucleo,recalculo_vivo}') is not null then
    raise exception 'POSTFLIGHT: un rango que NO delega no debe publicar recalculo_vivo';
  end if;

  -- 6) Un rango parcial NO delega.
  if (v_parcial #>> '{nucleo,fuente}') is distinct from 'rango_vivo'
     or (v_parcial #>> '{nucleo,es_mes_calendario}')::boolean is not false
     or (v_parcial #> '{nucleo,sellado}') <> 'null'::jsonb
     or (v_parcial #>> '{nucleo,ajuste_aplicado}')::boolean is not false then
    raise exception 'POSTFLIGHT: un rango parcial esta delegando, y no debe: %', v_parcial -> 'nucleo';
  end if;

  -- 7) Dueno, definer, volatilidad y search_path, intactos.
  if not exists (select 1 from pg_proc p
                  where p.oid = to_regprocedure('crm.metricas_conversiones_equipo_fn(date,date)')
                    and p.proowner = 'postgres'::regrole
                    and p.prosecdef and p.provolatile = 's'
                    and p.proconfig @> array['search_path=""']) then
    raise exception 'POSTFLIGHT: cambio el dueno, el definer, la volatilidad o el search_path';
  end if;

  -- 8) Sigue FUERA del censo de contadores crudos.
  if exists (select 1 from private.contadores_crudos_leads_citas() c
              where c.objeto = 'crm.metricas_conversiones_equipo_fn(date,date)') then
    raise exception 'POSTFLIGHT: la puerta ENTRO al censo; hay que declarar su huella aqui mismo';
  end if;
end;
$postflight$;

comment on function crm.metricas_conversiones_equipo_fn(date,date) is
  'Conversion por equipo para supervisor y gerencia. Desde la Ola 1b (22/09/2026), cuando el '
  'rango es un mes calendario completo DELEGA nucleo_divisor, nucleo_numerador y '
  'nucleo_conversion_pct de cada fila en crm.conversion_mensual_fn, emparejando por '
  'vendedor_id, y lo declara (fuente=mensual, sellado=<lo que diga la oficial>, '
  'ajuste_aplicado=true). Fuera de esa condicion calcula en vivo y lo declara. Los campos '
  'leads/clientes/conversion_pct de cada fila son la medida de COHORTE, otra cosa, y no se '
  'delegan. sondas.sin_fila_en_la_oficial cuenta los vendedores del roster sin fila en la '
  'oficial, para que la pantalla oculte el numero en vez de pintar un cero.';

select 'puerta6-delega-en-la-mensual' as migracion,
       private.assert_analitica_leads_citas() as trinquete,
       (select payload -> 'nucleo' from _p6b_despues) as nucleo,
       (select payload #> '{sondas,sin_fila_en_la_oficial}' from _p6b_despues) as sin_fila;

commit;

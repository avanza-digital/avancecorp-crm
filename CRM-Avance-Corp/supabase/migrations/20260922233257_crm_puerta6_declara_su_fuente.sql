-- =========================================================================
-- CRM · Ola 1a · La puerta #6 (conversion por equipo) DECLARA su fuente
-- =========================================================================
-- QUE HACE: anade cuatro claves informativas al bloque `nucleo` del payload de
-- `crm.metricas_conversiones_equipo_fn(date,date)`. Nada mas.
--
-- 🔑 ESTA MIGRACION NO CAMBIA NI UN NUMERO. No sustituye la cifra por la de
--    `crm.conversion_mensual_fn`: solo DECLARA con que criterio se calculo la
--    que ya se publicaba. La sustitucion va en un paquete aparte, cuando las
--    tres puertas de la Ola 1 declaren y el front las lea.
--
-- POR QUE: doce puertas publican conversion sobre el mismo nucleo
-- (`private.conversion_episodios`) y cada una pregunta a su manera. Hoy todas
-- coinciden por casualidad: no hay ningun mes sellado ni deuda de anulacion
-- viajando entre meses. El dia que se selle el primer mes, las que calculan en
-- vivo (esta) y las que leen la foto oficial diran cosas distintas. Antes de
-- unificarlas hay que poder VER cual es cual: eso es esta migracion.
--
-- REGLA DE MIGUEL (21/09/2026), que esta migracion NO toca, solo declara:
--   mes calendario completo y sin filtro de fuente -> la cifra la sirve
--   `crm.conversion_mensual_fn`; cualquier otro caso -> calculo en vivo,
--   DECLARADO y rotulado en pantalla.
--
-- MEDIDO EN PRODUCCION EL 22/09/2026, y fijado en el preflight:
--   · cuerpo vivo: md5(pg_get_functiondef) = d67db4c1204456b57d3271d6c94064b6
--   · dueno: postgres
--   · La funcion ESTA declarada en `private.analitica_leads_citas_exenciones`
--     (clase `mixta`) pero NO esta en el censo de contadores crudos: no nombra
--     `crm.leads` (`crm.lead_asignaciones` no casa con `\mcrm\.\s*leads\M`).
--     Por eso su huella declarada ya estaba caduca ANTES de esta migracion y
--     es inerte: `private.contadores_crudos_leads_citas()` no la devuelve, asi
--     que `declarada and not huella_ok` nunca la ve.
--     ⚠️ CONSECUENCIA DELIBERADA: esta migracion NO re-sella su huella. Escribir
--     una huella que nadie comprueba no protege nada y si borraria el aviso que
--     saltaria el dia que esta funcion entre al censo. El cambio de abajo no
--     nombra `crm.leads`, asi que no la mete en el censo. El postflight exige
--     que el trinquete siga verde igualmente.
--
-- REVERSA: volver a declarar el cuerpo sin las cuatro claves. Ninguna pantalla
-- depende de ellas para funcionar: el front las lee como opcionales
-- (`app/src/lib/metricas-conversiones-equipo.ts`, claves `v.optional`).
-- =========================================================================

begin;

set local statement_timeout = '180s';

-- ---------------------------------------------------------------------------
-- (a) PREFLIGHT: acreditar el cuerpo por IDENTIDAD, no por fragmentos.
--     Un preflight que comprueba trozos sella el cuerpo que encuentre; el md5
--     de `pg_get_functiondef` lleva firma, lenguaje, security definer y
--     search_path, que `md5(prosrc)` no lleva.
-- ---------------------------------------------------------------------------
do $preflight$
declare v_md5 text; v_dueno text;
begin
  select md5(pg_get_functiondef(p.oid)), p.proowner::regrole::text
    into v_md5, v_dueno
    from pg_proc p
   where p.oid = to_regprocedure('crm.metricas_conversiones_equipo_fn(date,date)');

  if v_md5 is null then
    raise exception 'PREFLIGHT: crm.metricas_conversiones_equipo_fn(date,date) no existe';
  end if;
  if v_md5 <> 'd67db4c1204456b57d3271d6c94064b6' then
    raise exception 'PREFLIGHT: el cuerpo vivo NO es el revisado (md5 %). Alguien lo cambio despues del 22/09; revisar antes de redeclarar.', v_md5;
  end if;
  if v_dueno <> 'postgres' then
    raise exception 'PREFLIGHT: dueno inesperado %', v_dueno;
  end if;
end;
$preflight$;

-- Foto de referencia ANTES de tocar nada. La puerta es SECURITY DEFINER y se
-- niega a hablar con quien no sea supervisor/gerencia; una migracion corre como
-- `postgres`, que no tiene `auth.uid()`. Se toma prestada una identidad de
-- gerencia igual que hace `crm.alarma_conversion_fn`, y se restaura por los DOS
-- caminos de salida (los claims de `set_config(..., true)` viven hasta el fin
-- de la TRANSACCION, no hasta el `return`).
create temp table _p6_antes (payload jsonb) on commit drop;

do $antes$
declare
  v_claims text := current_setting('request.jwt.claims', true);
  v_gerente uuid;
begin
  select e.perfil_id into v_gerente
    from crm.equipo e
   where e.rol_crm = 'gerencia' and e.activo and private.rol_crm(e.perfil_id) = 'gerencia'
   order by e.perfil_id limit 1;
  if v_gerente is null then
    raise exception 'PREFLIGHT: no hay perfil de gerencia activo; sin foto de referencia no se toca la puerta';
  end if;
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_gerente, 'role', 'authenticated')::text, true);
  begin
    insert into _p6_antes (payload)
    select crm.metricas_conversiones_equipo_fn(
             date_trunc('month', (now() at time zone 'America/Lima'))::date,
             (now() at time zone 'America/Lima')::date);
  exception when others then
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
end;
$antes$;

-- ---------------------------------------------------------------------------
-- (b) La puerta, declarando su fuente. Cuerpo generado POR ANCLAS sobre el
--     vivo acreditado arriba: el unico cambio es el bloque de cuatro claves.
-- ---------------------------------------------------------------------------
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
-- (c) POSTFLIGHT: el trinquete verde, las claves viajan, y NI UN NUMERO MOVIDO.
--     La comparacion es del payload ENTERO, no de la cifra de portada: quitando
--     `generado_en` (un reloj) y las cuatro claves nuevas, lo demas tiene que
--     ser identico byte a byte. Asi no se puede colar un cambio en
--     `responsables`, en `sondas` ni en el bloque `cierre`.
-- ---------------------------------------------------------------------------
create temp table _p6_despues (payload jsonb) on commit drop;

do $postflight$
declare
  v_ok text; v_antes jsonb; v_despues jsonb; v_parcial jsonb; v_nucleo jsonb;
  v_a jsonb; v_d jsonb;
  v_claims text := current_setting('request.jwt.claims', true);
  v_gerente uuid;
begin
  v_ok := private.assert_analitica_leads_citas();
  if v_ok not like 'OK:%' then
    raise exception 'POSTFLIGHT: el trinquete quedo en rojo: %', v_ok;
  end if;

  select payload into v_antes from _p6_antes;

  select e.perfil_id into v_gerente
    from crm.equipo e
   where e.rol_crm = 'gerencia' and e.activo and private.rol_crm(e.perfil_id) = 'gerencia'
   order by e.perfil_id limit 1;
  if v_gerente is null then
    raise exception 'POSTFLIGHT: no hay perfil de gerencia activo; la comparacion no se puede hacer';
  end if;
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_gerente, 'role', 'authenticated')::text, true);
  begin
    v_despues := crm.metricas_conversiones_equipo_fn(
                   date_trunc('month', (now() at time zone 'America/Lima'))::date,
                   (now() at time zone 'America/Lima')::date);
    -- 🔴 NO vale «el dia 1 a el dia 1»: el DIA 1 del mes ese rango SI es mes
    -- calendario por la regla de Miguel (`p_hasta = v_hoy`), y la migracion
    -- seria inaplicable justo ese dia. Un rango del mes ANTERIOR que no
    -- termina ni el ultimo dia ni hoy es parcial SIEMPRE.
    v_parcial := crm.metricas_conversiones_equipo_fn(
                   (date_trunc('month', (now() at time zone 'America/Lima')) - interval '1 month')::date,
                   (date_trunc('month', (now() at time zone 'America/Lima')) - interval '1 month')::date + 1);
  exception when others then
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  insert into _p6_despues (payload) values (v_despues);

  v_nucleo := v_despues -> 'nucleo';

  -- 1) NI UN NUMERO MOVIDO. Esta es la promesa de esta migracion.
  v_a := v_antes - 'generado_en';
  v_d := v_despues - 'generado_en';
  v_d := jsonb_set(v_d, '{nucleo}',
           (v_d -> 'nucleo') - 'es_mes_calendario' - 'fuente' - 'sellado' - 'ajuste_aplicado');
  if v_a is distinct from v_d then
    raise exception 'POSTFLIGHT: el payload SE MOVIO fuera de las cuatro claves nuevas. ANTES: % · DESPUES: %', v_a, v_d;
  end if;

  -- 2) Y las cuatro claves del contrato viajan, con los valores que deben.
  if v_nucleo -> 'es_mes_calendario' is null then
    raise exception 'POSTFLIGHT: no publica es_mes_calendario';
  end if;
  if (v_nucleo ->> 'es_mes_calendario')::boolean is not true then
    raise exception 'POSTFLIGHT: del dia 1 a hoy ES mes calendario y dice %',
      v_nucleo ->> 'es_mes_calendario';
  end if;
  if (v_nucleo ->> 'fuente') is distinct from 'rango_vivo' then
    raise exception 'POSTFLIGHT: fuente = % (esta ola NO sustituye: siempre rango_vivo)',
      v_nucleo ->> 'fuente';
  end if;
  if v_nucleo -> 'sellado' <> 'null'::jsonb then
    raise exception 'POSTFLIGHT: sellado deberia ser null («no se delego»), y es %',
      v_nucleo -> 'sellado';
  end if;
  if (v_nucleo ->> 'ajuste_aplicado')::boolean is not false then
    raise exception 'POSTFLIGHT: ajuste_aplicado deberia ser false; esta puerta no resta la deuda';
  end if;

  -- 3) Un rango PARCIAL no puede declararse mes calendario.
  if (v_parcial -> 'nucleo' ->> 'es_mes_calendario')::boolean is not false then
    raise exception 'POSTFLIGHT: un rango de un solo dia se declara mes calendario; el test esta roto';
  end if;

  -- 4) El dueno, intacto.
  -- `create or replace` REESCRIBE definer, volatilidad y search_path desde el
  -- texto: se acreditan los cuatro, no solo el dueno.
  if not exists (select 1 from pg_proc p
                  where p.oid = to_regprocedure('crm.metricas_conversiones_equipo_fn(date,date)')
                    and p.proowner = 'postgres'::regrole
                    and p.prosecdef
                    and p.provolatile = 's'
                    and p.proconfig @> array['search_path=""']) then
    raise exception 'POSTFLIGHT: cambio el dueno, el definer, la volatilidad o el search_path';
  end if;

  -- 5) Sigue FUERA del censo de contadores crudos, como antes de esta
  --    migracion. Si hubiera entrado, su huella declarada (caduca) pondria el
  --    trinquete en rojo y habria que declararla en la misma transaccion.
  if exists (select 1 from private.contadores_crudos_leads_citas() c
              where c.objeto = 'crm.metricas_conversiones_equipo_fn(date,date)') then
    raise exception 'POSTFLIGHT: la puerta ENTRO al censo de contadores crudos; hay que declarar su huella aqui mismo';
  end if;
end;
$postflight$;

-- (d) El contrato, tambien en el diccionario. `create or replace` CONSERVA el
--     comentario anterior; hay que refrescarlo a mano. No afecta a ninguna
--     huella: el comentario no vive en `prosrc`.
comment on function crm.metricas_conversiones_equipo_fn(date,date) is
  'Conversion por equipo para supervisor y gerencia. Desde la Ola 1a (22/09/2026) su '
  'bloque `nucleo` DECLARA de donde sale la cifra: `es_mes_calendario` (el rango es un mes '
  'calendario completo, la condicion de Miguel del 21/09 para poder delegar en '
  'crm.conversion_mensual_fn), `fuente` (hoy siempre `rango_vivo`), `sellado` (null = no se '
  'delego en la foto oficial; el estado del mes sigue viajando en el bloque `cierre`) y '
  '`ajuste_aplicado` (false = NO resta la deuda de anulacion de un mes ya sellado). '
  'Declarar no es sustituir: da exactamente la misma cifra que antes de esa ola.';

select 'puerta6-declara-su-fuente' as migracion,
       private.assert_analitica_leads_citas() as trinquete,
       (select payload -> 'nucleo' from _p6_despues) as nucleo;

commit;

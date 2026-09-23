-- =========================================================================
-- CRM · Las puertas #7 y #8 declaran su fuente — CON PESTILLO
-- =========================================================================
-- Reintento de `20260923010450`, que hubo que revertir con `20260923011804`.
--
-- 🔴 QUE SALIO MAL LA PRIMERA VEZ, para que quede delante de quien la aplique.
--    Se comprobo que la #8 (`crm.cumplimiento_metas_sin_cartera_fn`) no tiene
--    consumidor en el front. Era cierto. Pero **la #7
--    (`crm.cumplimiento_metas_fn`) construye su payload SOBRE el de la #8**:
--    al declarar la #8 quedo declarada la #7, que si tiene consumidor, y el
--    bundle de entonces validaba `CumplimientoMetasSchema` con
--    `v.strictObject` sin esas claves. Metas y Ranking de gerencia se quedaron
--    sin datos 13 minutos.
--
--    La leccion, ya aplicada: «no tiene consumidor en el front» se comprueba
--    sobre la funcion que se toca Y sobre todas las que la envuelven. La
--    consulta que lo ve:
--      select p.oid::regprocedure::text from pg_proc p
--        join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname in ('crm','private','public')
--         and p.prosrc like '%<la funcion>%' and p.proname <> '<la funcion>';
--
-- 🔒 POR ESO ESTA LLEVA PESTILLO. No entra sin declarar a mano, en la MISMA
--    sesion, que el front ya esta publicado:
--        set local crm.ola1_front_publicado = 'si';
--    Y antes de escribir eso hay que comprobarlo de verdad, en este orden:
--      1. `curl -s https://crm.miavance.com/version.json` -> buildId
--      2. el manifiesto de ese buildId en `releases/` -> commit publicado
--      3. `git merge-base --is-ancestor c2c9274b <ese commit>`
--    `c2c9274b` es el commit que vuelve `v.optional` las cuatro claves en
--    `app/src/lib/objetivos.ts`, que es el modulo que valida la #7.
--
-- QUE HACE: anade las cuatro claves a las DOS ramas de la #8 (mes sellado y
-- mes abierto). La #7 las hereda, que es justamente lo que se quiere: es la que
-- se ve en pantalla. NO cambia ni un numero: medido el 22/09 con 2 puntos de
-- deuda plantados, la #8 baja el numerador de 6 a 4 igual que la oficial.
--
-- POR QUE `fuente: 'rango_vivo'` EN LA RAMA ABIERTA: porque no se le pregunta a
-- `crm.conversion_mensual_fn`; se calcula sobre
-- `private.conversion_mensual_por_vendedor` y se aplica el ajuste aqui mismo.
-- Coincide con la oficial, pero decir 'mensual' seria mentir sobre de donde
-- salio la cifra, y de eso trata toda esta unificacion.
--
-- FIJADO EN EL PREFLIGHT: md5(pg_get_functiondef) de la #8 =
-- b7192138b237571c9955d021aff0920a (el cuerpo restaurado por la reversion).
-- Ni declarada ni en el censo: no hay huella que re-sellar.
--
-- REVERSA: `20260923011804` sirve tal cual — vuelve a declarar el cuerpo sin
-- las cuatro claves.
-- =========================================================================

begin;

set local statement_timeout = '180s';

do $preflight$
declare v_md5 text;
begin
  -- EL PESTILLO.
  if coalesce(current_setting('crm.ola1_front_publicado', true), '') <> 'si' then
    raise exception 'PREFLIGHT: falta declarar que el front ya esta publicado. Comprueba version.json -> manifiesto -> merge-base c2c9274b, y si es cierto ejecuta en la misma sesion: set local crm.ola1_front_publicado = ''si'';';
  end if;

  select md5(pg_get_functiondef(p.oid)) into v_md5 from pg_proc p
   where p.oid = to_regprocedure('crm.cumplimiento_metas_sin_cartera_fn(date)');
  if v_md5 is distinct from 'b7192138b237571c9955d021aff0920a' then
    raise exception 'PREFLIGHT: la #8 no es el cuerpo revisado (md5 %)', v_md5;
  end if;
  if not exists (select 1 from pg_proc p
                  where p.oid = to_regprocedure('crm.cumplimiento_metas_sin_cartera_fn(date)')
                    and p.proowner = 'postgres'::regrole and p.prosecdef and p.provolatile = 's') then
    raise exception 'PREFLIGHT: dueno, definer o volatilidad inesperados';
  end if;
  -- Y que la herencia siga siendo la que creemos: si alguien mas envolviera la
  -- #8, habria que mirar SU front antes de entrar.
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('crm','private','public')
         and p.prosrc like '%cumplimiento_metas_sin_cartera_fn%'
         and p.proname <> 'cumplimiento_metas_sin_cartera_fn') <> 1 then
    raise exception 'PREFLIGHT: la #8 tiene mas envoltorios que la #7; revisar el front de cada uno antes de declarar';
  end if;
end;
$preflight$;

create temp table _p78_antes (puerta text, payload jsonb) on commit drop;

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
    insert into _p78_antes (puerta, payload)
    select 'p8', crm.cumplimiento_metas_sin_cartera_fn(
                   date_trunc('month', (now() at time zone 'America/Lima'))::date);
    insert into _p78_antes (puerta, payload)
    select 'p7', crm.cumplimiento_metas_fn(
                   date_trunc('month', (now() at time zone 'America/Lima'))::date);
  exception when others then
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
end;
$antes$;

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

do $postflight$
declare
  v_ok text; a7 jsonb; a8 jsonb; d7 jsonb; d8 jsonb; v_a jsonb; v_d jsonb;
  v_claims text := current_setting('request.jwt.claims', true);
  v_gerente uuid;
begin
  v_ok := private.assert_analitica_leads_citas();
  if v_ok not like 'OK:%' then
    raise exception 'POSTFLIGHT: el trinquete quedo en rojo: %', v_ok;
  end if;

  select payload into a8 from _p78_antes where puerta = 'p8';
  select payload into a7 from _p78_antes where puerta = 'p7';

  select e.perfil_id into v_gerente from crm.equipo e
   where e.rol_crm = 'gerencia' and e.activo and private.rol_crm(e.perfil_id) = 'gerencia'
   order by e.perfil_id limit 1;
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_gerente, 'role', 'authenticated')::text, true);
  begin
    d8 := crm.cumplimiento_metas_sin_cartera_fn(
            date_trunc('month', (now() at time zone 'America/Lima'))::date);
    d7 := crm.cumplimiento_metas_fn(
            date_trunc('month', (now() at time zone 'America/Lima'))::date);
  exception when others then
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  -- 1) NI UN NUMERO MOVIDO, en ninguna de las dos.
  v_a := a8 - 'generado_en';
  v_d := (d8 - 'generado_en') - 'es_mes_calendario' - 'fuente' - 'sellado' - 'ajuste_aplicado';
  if v_a is distinct from v_d then
    raise exception 'POSTFLIGHT: la #8 movio algo fuera de las cuatro claves. Bloques distintos: %',
      (select string_agg(k, ', ' order by k) from jsonb_object_keys(v_a) k
        where (v_a -> k) is distinct from (v_d -> k));
  end if;
  v_a := a7 - 'generado_en';
  v_d := (d7 - 'generado_en') - 'es_mes_calendario' - 'fuente' - 'sellado' - 'ajuste_aplicado';
  if v_a is distinct from v_d then
    raise exception 'POSTFLIGHT: la #7 movio algo fuera de las cuatro claves. Bloques distintos: %',
      (select string_agg(k, ', ' order by k) from jsonb_object_keys(v_a) k
        where (v_a -> k) is distinct from (v_d -> k));
  end if;

  -- 2) LA HERENCIA ES LO QUE SE BUSCA, no un accidente: la #7 TIENE que quedar
  --    declarada. Es la que se ve en pantalla.
  if (d7 ->> 'es_mes_calendario')::boolean is not true
     or (d7 ->> 'fuente') is distinct from (d8 ->> 'fuente')
     or (d7 -> 'sellado') is distinct from (d8 -> 'sellado')
     or (d7 ->> 'ajuste_aplicado')::boolean is not true then
    raise exception 'POSTFLIGHT: la #7 no heredo la declaracion de la #8. #7 % · #8 %',
      jsonb_build_object('em', d7 -> 'es_mes_calendario', 'f', d7 -> 'fuente',
                         's', d7 -> 'sellado', 'a', d7 -> 'ajuste_aplicado'),
      jsonb_build_object('em', d8 -> 'es_mes_calendario', 'f', d8 -> 'fuente',
                         's', d8 -> 'sellado', 'a', d8 -> 'ajuste_aplicado');
  end if;

  -- 3) Las dos ramas de la #8, coherentes con el estado real del mes.
  if (d8 #>> '{cierre,cerrado}')::boolean is true then
    if (d8 ->> 'fuente') is distinct from 'mensual' or (d8 ->> 'sellado')::boolean is not true then
      raise exception 'POSTFLIGHT: mes sellado y la #8 declara % / %', d8 ->> 'fuente', d8 ->> 'sellado';
    end if;
  else
    if (d8 ->> 'fuente') is distinct from 'rango_vivo' or (d8 ->> 'sellado')::boolean is not false then
      raise exception 'POSTFLIGHT: mes abierto y la #8 declara % / %', d8 ->> 'fuente', d8 ->> 'sellado';
    end if;
  end if;

  -- 4) Dueno, definer, volatilidad y search_path, intactos.
  if not exists (select 1 from pg_proc p
                  where p.oid = to_regprocedure('crm.cumplimiento_metas_sin_cartera_fn(date)')
                    and p.proowner = 'postgres'::regrole and p.prosecdef
                    and p.provolatile = 's' and p.proconfig @> array['search_path=""']) then
    raise exception 'POSTFLIGHT: cambio el dueno, el definer, la volatilidad o el search_path';
  end if;

  -- 5) Sigue FUERA del censo de contadores crudos.
  if exists (select 1 from private.contadores_crudos_leads_citas() c
              where c.objeto = 'crm.cumplimiento_metas_sin_cartera_fn(date)') then
    raise exception 'POSTFLIGHT: la #8 ENTRO al censo; hay que declarar su huella aqui mismo';
  end if;
end;
$postflight$;

comment on function crm.cumplimiento_metas_sin_cartera_fn(date) is
  'Cumplimiento de metas SIN cartera, y motor del payload de crm.cumplimiento_metas_fn, que '
  'lo HEREDA (por eso declararla aqui declara tambien la de Metas y Ranking). Declara de '
  'donde sale su cifra: en la rama del mes SELLADO, de la foto de crm.periodos_cerrados '
  '(fuente=mensual, sellado=true); en la del mes ABIERTO, de '
  'private.conversion_mensual_por_vendedor con private.conversion_con_ajuste aplicado '
  '(fuente=rango_vivo, sellado=false). En las dos, es_mes_calendario=true y '
  'ajuste_aplicado=true: SI resta la deuda de los cierres anulados, y por eso no discrepa de '
  'la oficial.';

select 'puertas7y8-declaran-con-pestillo' as migracion,
       private.assert_analitica_leads_citas() as trinquete;

commit;

-- =========================================================================
-- CRM · El peso de la RENOVACION se GUARDA al sellar y se DECLARA de verdad
-- =========================================================================
-- Continua `20260923155859`, que le dio a la renovacion su propia columna y su
-- propia lectora. Aquella arreglo el CALCULO y dejo sin arreglar la
-- DECLARACION: el nucleo pasa a aplicar el peso real, pero varias puertas
-- seguian publicando el del REFERIDO bajo la clave de la renovacion.
--
-- 🔑 NO CAMBIA NI UN NUMERO. Mientras `peso_referido` y `peso_renovacion` valgan
--    los dos 0,15, lo que se declara y lo que se guarda coincide con lo de hoy.
--    El postflight lo exige.
--
-- ## LAS TRES GRIETAS QUE CIERRA (de las CINCO que encontro el barrido)
--
-- 1. 🔴 **`crm.periodos_cerrados` no guardaba el peso de la renovacion.** Solo
--    `ponderacion_referido`; el de renovacion se RECONSTRUIA al leer. Eso es
--    IRREVERSIBLE: la foto es la unica memoria de con que peso se calculo un mes
--    sellado. Hoy la tabla esta VACIA (0 meses cerrados), asi que la ventana
--    para arreglarlo sin perdida esta abierta. El primer mes que se selle sin
--    esto queda mal para siempre.
-- 2. `crm.metricas_conversiones_equipo_fn` publicaba `'peso_renovacion', v_factor`.
-- 3. `private.metricas_conversiones_implementacion`, lo mismo.
--
-- Las dos ultimas importan mas de lo que parece: el front CONSUME esa clave en
-- `app/src/lib/conversion-vendedores.ts:272` (`peso_renovacion ?? peso_referido`)
-- para ponderar el desglose de renovaciones. Con la clave mintiendo, el dia que
-- se muevan los pesos esa pantalla calcularia con el peso equivocado — un
-- numero mal, no solo una declaracion inexacta.
--
-- ## LAS DOS QUE **NO** CIERRA, Y POR QUE
--
-- `crm.conversion_mensual_sin_cartera_fn` tiene las otras dos (su rama sellada
-- RECONSTRUYE el peso, y su rama abierta declara `v_factor`). No se tocan aqui
-- porque otra sesion esta reescribiendo esa misma funcion ahora mismo
-- (`20260923164903_crm_una_sola_pieza_de_conversion.sql`, acordado: va primero).
-- Van en una migracion aparte, sobre SU cuerpo. Anotado para que nadie las de
-- por hechas.
--
-- ## COMO SE ENCONTRARON
--
-- Con un barrido de TODO objeto vivo que nombre un peso de renovacion, no
-- leyendo las tres que ya conocia. La migracion anterior se escribio sin ese
-- barrido y por eso dejo el hueco. El barrido esta en el encargo como paso
-- obligatorio.
--
-- ## MEDIDO EN PRODUCCION EL 23/09/2026, y fijado en el preflight
--
--   · crm.cerrar_periodo(date)                          md5 9efc07b35e9b34fdb8d84e9bad019d8e  · censada `analitica`
--   · crm.metricas_conversiones_equipo_fn(date,date)    md5 f10e1fc3c6025060e4f1b1d1df704cf4  · censada `mixta`
--   · private.metricas_conversiones_implementacion(...) md5 1634c4375d3dee62c02c304421ea5593  · censada `analitica`
--   · crm.periodos_cerrados: 0 filas.
--
-- Las TRES estan censadas, asi que hay que re-sellar su declaracion en esta
-- misma transaccion, con la normalizacion del censo (`lower`, sin comentarios).
--
-- ## POR QUE LA COLUMNA NACE NULLABLE, al reves que `peso_renovacion`
--
-- En `crm.conversion_pesos` el default 0.15 era correcto: reproducia lo que la
-- renovacion valia. Aqui NO: una foto sellada antes de esta migracion no tiene
-- peso de renovacion propio, y fingir que valia 0.15 seria inventarse un dato
-- historico. `null` dice la verdad — «sellado antes de que esto existiera»— y
-- quien lea decide (la migracion siguiente hara el fallback explicito). Hoy la
-- tabla esta vacia, asi que no hay ni una fila que interpretar.
--
-- REVERSA: volver a declarar los tres cuerpos anteriores, restaurar sus tres
-- huellas, refrescar el sello y quitar la columna. Ninguna cifra se mueve en
-- ningun sentido mientras los dos pesos valgan lo mismo.
-- =========================================================================

begin;

set local statement_timeout = '180s';
set local lock_timeout = '5s';
lock table private.analitica_leads_citas_exenciones,
           private.analitica_lc_sello in share row exclusive mode;

-- ---------------------------------------------------------------------------
-- (a) PREFLIGHT: acreditar por IDENTIDAD los tres cuerpos, y el estado de la
--     tabla del que depende la decision de que la columna nazca nullable.
-- ---------------------------------------------------------------------------
do $preflight$
declare v_md5 text; v_filas int;
begin
  select md5(pg_get_functiondef(p.oid)) into v_md5 from pg_proc p
   where p.oid = to_regprocedure('crm.cerrar_periodo(date)');
  if v_md5 is distinct from '9efc07b35e9b34fdb8d84e9bad019d8e' then
    raise exception 'PREFLIGHT: crm.cerrar_periodo no es el cuerpo revisado (md5 %)', v_md5;
  end if;
  select md5(pg_get_functiondef(p.oid)) into v_md5 from pg_proc p
   where p.oid = to_regprocedure('crm.metricas_conversiones_equipo_fn(date,date)');
  if v_md5 is distinct from 'f10e1fc3c6025060e4f1b1d1df704cf4' then
    raise exception 'PREFLIGHT: la puerta de equipo no es el cuerpo revisado (md5 %)', v_md5;
  end if;
  select md5(pg_get_functiondef(p.oid)) into v_md5 from pg_proc p
   where p.oid = to_regprocedure('private.metricas_conversiones_implementacion(date,date,text)');
  if v_md5 is distinct from '1634c4375d3dee62c02c304421ea5593' then
    raise exception 'PREFLIGHT: la implementacion no es el cuerpo revisado (md5 %)', v_md5;
  end if;

  -- La lectora tiene que existir: esta migracion la usa en los tres cuerpos.
  if to_regprocedure('private.peso_renovacion_conversion(date)') is null then
    raise exception 'PREFLIGHT: falta private.peso_renovacion_conversion(date). ¿Se aplico 20260923155859?';
  end if;

  if exists (select 1 from information_schema.columns
              where table_schema = 'crm' and table_name = 'periodos_cerrados'
                and column_name = 'ponderacion_renovacion') then
    raise exception 'PREFLIGHT: la columna ponderacion_renovacion ya existe';
  end if;

  -- 🔑 La ventana. Si ya hay meses sellados, esta migracion NO los arregla: sus
  -- pesos de renovacion quedaron reconstruidos y no hay de donde recuperarlos.
  select count(*) into v_filas from crm.periodos_cerrados;
  if v_filas <> 0 then
    raise exception 'PREFLIGHT: ya hay % mes(es) sellado(s). Esta migracion se escribio con la tabla VACIA: esos meses no guardaron su peso de renovacion y NO se puede reconstruir. Hay que decidir que hacer con ellos antes de seguir.', v_filas;
  end if;
end;
$preflight$;

-- Foto de referencia ANTES de tocar nada, con identidad de gerencia prestada.
create temp table _pr2_antes (puerta text, payload jsonb) on commit drop;

do $antes$
declare
  v_claims text := current_setting('request.jwt.claims', true);
  v_gerente uuid;
  v_mes date := date_trunc('month', (now() at time zone 'America/Lima'))::date;
  v_hoy date := (now() at time zone 'America/Lima')::date;
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
    insert into _pr2_antes (puerta, payload)
    select 'equipo', crm.metricas_conversiones_equipo_fn(v_mes, v_hoy);
    insert into _pr2_antes (puerta, payload)
    select 'impl', private.metricas_conversiones_implementacion(v_mes, v_hoy, null);
  exception when others then
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
end;
$antes$;

-- ---------------------------------------------------------------------------
-- (b) La columna. NULLABLE a proposito: ver la cabecera.
-- ---------------------------------------------------------------------------
alter table crm.periodos_cerrados
  add column ponderacion_renovacion numeric;

alter table crm.periodos_cerrados
  add constraint periodos_cerrados_ponderacion_renovacion_rango
  check (ponderacion_renovacion is null
         or (ponderacion_renovacion >= 0 and ponderacion_renovacion <= 1));

comment on column crm.periodos_cerrados.ponderacion_renovacion is
  'Peso de la RENOVACION con el que se calculo esta foto mensual. Se guarda desde el '
  '23/09/2026; antes solo se guardaba ponderacion_referido y el de renovacion se '
  'reconstruia a partir de el, lo que dejaba de ser cierto en cuanto los dos pesos se '
  'separaron. NULL = foto sellada antes de que existiera esta columna, que no es lo mismo '
  'que un peso de cero: quien lea decide el respaldo. Una foto NO se reescribe.';

-- ---------------------------------------------------------------------------
-- (c) Los tres cuerpos, generados POR ANCLAS sobre los vivos acreditados.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.cerrar_periodo(p_periodo date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid         uuid := (select auth.uid());
  v_rol         text;
  v_automatico  boolean;
  v_mes_actual  date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_ini         timestamptz;
  v_fin         timestamptz;
  v_factor      numeric;
  v_periodo_id  uuid;
  v_revision    integer;
  v_suelo       timestamptz;
  v_medible     boolean;
  v_motivo      text;
  v_cobertura   jsonb;
  v_vendedores  integer;
  v_fuera_ranking jsonb := '[]'::jsonb;
  v_pendiente   date;
  v_ventana     timestamptz;
  v_ultimo_sellado date;
begin
  -- 1) Gate. `auth.uid()` nulo = el ciclo automatico (service_role); con uid,
  --    solo gerencia. Un vendedor o un supervisor no cierran meses.
  v_rol := private.rol_crm(v_uid);
  v_automatico := v_uid is null;
  if not v_automatico and v_rol is distinct from 'gerencia' then
    raise exception 'Solo gerencia cierra un mes' using errcode = '42501';
  end if;

  -- 2) El periodo.
  if p_periodo is null or p_periodo <> date_trunc('month', p_periodo)::date then
    raise exception 'El periodo debe ser el primer dia del mes' using errcode = '22023';
  end if;
  -- El mes en curso NO se cierra: todavia esta pasando. Y el siguiente tampoco,
  -- obviamente. La ventana de ajuste (del 1 al 10) vive en el mes SIGUIENTE al
  -- que se cierra, asi que aqui basta con exigir que el mes ya haya terminado.
  if p_periodo >= v_mes_actual then
    raise exception 'Un mes solo se cierra cuando ya termino' using errcode = '22023';
  end if;

  -- 2bis) EL CANDADO. Del 1 al 10 del mes siguiente el mes todavia admite
  --    correcciones, asi que NADIE lo sella: ni gerencia ni el ciclo. Sin esto,
  --    el momento de cerrar decide de que mes sale el dinero de una correccion.
  --    Es un SUELO, no una fecha exacta (decision de Miguel, 2026-08-15): pasado
  --    el dia 10 se puede cerrar cualquier dia, para que un fallo del ciclo no
  --    deje el mes atascado bloqueando a todos los siguientes.
  v_ventana := private.cierre_mes_ventana_desde(p_periodo);
  if now() < v_ventana then
    raise exception using
      errcode = '22023',
      message = format('El mes %s no se puede cerrar antes del %s',
                       to_char(p_periodo, 'YYYY-MM'),
                       to_char(v_ventana at time zone 'America/Lima', 'DD/MM/YYYY')),
      hint    = 'Del 1 al 10 hay ventana de ajuste: el mes todavia puede recibir correcciones.';
  end if;

  -- 2ter) EL CERROJO DEL PERIODO. Se toma ANTES de leer `periodos_cerrados` y de
  --    escribir nada, y lo comparte `private.registrar_ajuste_si_mes_cerrado`.
  --    Sin el hay una carrera que PIERDE DINERO EN SILENCIO: una anulacion que
  --    arranca mientras el cierre esta a medias ve el mes todavia ABIERTO —el
  --    sello aun no ha hecho commit—, decide que no hay deuda que registrar, y
  --    la foto que se esta sellando ya habia contado ese cierre. Resultado: un
  --    cierre anulado queda pagado para siempre y sin una linea que lo explique.
  --    Antes era una carrera teorica (alguien tenia que decidir cerrar); con el
  --    ciclo automatico hay una cita fija, mensual y a hora conocida, justo
  --    cuando gerencia esta mirando esos numeros. Mismo patron que usa
  --    `crm.publicar_metas_vendedores`.
  -- CANDADO GLOBAL primero (20260815235500): serializa este sellado con
  -- CUALQUIER publicacion de metas en vuelo — tambien la de OTRO mes. El
  -- trigger del candado toma el mismo global antes de mirar; sin esto,
  -- publicar P durante el sellado de M>P paria metas muertas bajo el suelo.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados')::bigint
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (p_periodo - date '2000-01-01')::integer
  );

  lock table crm.equipo in share mode;

  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo = p_periodo) then
    raise exception using
      errcode = 'P0409',
      message = 'Ese mes ya estaba cerrado',
      hint    = 'Un mes cerrado no se reescribe: lo que haya que corregir se descuenta en el mes vivo.';
  end if;

  -- 2quater) NUNCA POR DETRAS DE UN MES YA SELLADO. La regla de «sin huecos»
  --    del paso 3 protege el orden dado un conjunto de meses FIJO, y el conjunto
  --    no es fijo: `crm.publicar_metas_vendedores` acepta cualquier mes, asi que
  --    unas metas publicadas hacia atras pueden fabricar un «mes pendiente»
  --    anterior a uno que ya se pago. Sellarlo despues reescribiria la historia
  --    por el unico hueco que quedaba, y `private.saldar_ajustes` le cobraria a
  --    ese mes viejo deudas que tocaban al mes vivo.
  --    En el camino normal esto es un no-op: el ciclo siempre va de viejo a
  --    nuevo. Cuesta una consulta y cierra la ultima puerta.
  select max(pc.periodo) into v_ultimo_sellado from crm.periodos_cerrados pc;
  if v_ultimo_sellado is not null and p_periodo < v_ultimo_sellado then
    raise exception using
      errcode = '22023',
      message = format('No se sella %s: %s ya esta cerrado y es posterior',
                       to_char(p_periodo, 'YYYY-MM'), to_char(v_ultimo_sellado, 'YYYY-MM')),
      hint    = 'Los meses se sellan hacia adelante. Un mes que aparece por detras de lo ya pagado se corrige en el mes vivo, no sellandolo.';
  end if;

  -- 3) Sin huecos: no se cierra un mes si queda alguno anterior CON DATOS
  --    abierto. «Con datos» = tiene metas publicadas; un mes sin metas nunca
  --    tuvo nada que pagar y no bloquea la secuencia.
  v_pendiente := private.cierre_mes_pendiente(p_periodo);
  if v_pendiente is not null then
    raise exception using
      errcode = '22023',
      message = format('Falta cerrar %s antes que %s', v_pendiente, p_periodo),
      hint    = 'Los meses se cierran en orden: si no, el que se salta queda abierto para siempre.';
  end if;

  v_ini := p_periodo::timestamp at time zone 'America/Lima';
  v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';
  v_factor := private.peso_referido_conversion(p_periodo);

  select mp.id, mp.revision into v_periodo_id, v_revision
  from crm.meta_periodos mp
  where mp.periodo = p_periodo
  order by mp.revision desc
  limit 1;
  -- Un mes sin metas publicadas se puede cerrar igual: se sella lo que hubo
  -- (conversion sin objetivo). Cerrar es fijar la historia, no premiarla.
  v_revision := coalesce(v_revision, 0);

  -- 4) La cobertura, con el MISMO criterio que la pantalla. Se recalcula aqui en
  --    vez de leerse de `conversion_mensual_fn` porque esa funcion recorta por
  --    `auth.uid()` y el cierre necesita la foto completa.
  select min(la.asignado_en) into v_suelo
  from crm.lead_asignaciones la
  where not la.aproximado;

  if v_suelo is null then
    v_medible := false;
    v_motivo := 'sin_ledger';
  elsif v_ini < v_suelo then
    v_medible := false;
    v_motivo := case
      when p_periodo < date_trunc('month', v_suelo at time zone 'America/Lima')::date
        then 'anterior_al_ledger'
      else 'mes_parcial'
    end;
  else
    v_medible := true;
    v_motivo := null;
  end if;
  v_cobertura := jsonb_build_object(
    'modelo_conversion', 'llegadas_v2',
    'medible', v_medible,
    'suelo_historico', v_suelo,
    'motivo_no_medible', v_motivo
  );

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
  ), roster as materialized (
    select distinct mv.vendedor_id
    from crm.metas_vendedor mv
    where mv.meta_periodo_id = v_periodo_id
  ), personas as (
    select c.analista_id as persona_id from conv c where c.analista_id is not null
    union
    select p.vendedor_id from prod p where p.vendedor_id is not null
    union
    select c.vendedor_id from car c where c.vendedor_id is not null
  ), elegibles as (
    select r.vendedor_id as persona_id from roster r
    union
    select p.persona_id
    from personas p
    join crm.equipo e
      on e.perfil_id = p.persona_id and e.rol_crm = 'vendedor'
    join crm.equipo s
      on s.perfil_id = e.supervisor_id and s.rol_crm = 'supervisor'
  ), fuera as (
    select
      p.persona_id,
      coalesce(nullif(btrim(pf.nombre_completo), ''),
               '(sin nombre · ' || left(p.persona_id::text, 8) || ')') as nombre,
      coalesce(e.rol_crm, 'fuera_equipo') as rol_crm,
      case
        when e.rol_crm = 'vendedor' then 'analista_sin_supervisor'
        when e.rol_crm = 'supervisor' then 'supervisor'
        when e.rol_crm = 'gerencia' then 'gerencia'
        else 'fuera_estructura'
      end as motivo
    from personas p
    left join crm.equipo e on e.perfil_id = p.persona_id
    left join public.perfiles pf on pf.id = p.persona_id
    where not exists (
      select 1 from elegibles ok where ok.persona_id = p.persona_id
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

  v_cobertura := v_cobertura || jsonb_build_object(
    'fuera_ranking', v_fuera_ranking
  );

  -- Sin analista forma parte del total de empresa, no del ranking de personas.
  -- Se congela junto a la foto; una asignación posterior no reescribe el cierre.
  v_cobertura := v_cobertura || coalesce((
    select jsonb_build_object('conversion_sin_analista', to_jsonb(cm) - 'analista_id')
    from private.conversion_mensual_por_vendedor(v_ini, v_fin, true, '{}'::uuid[], v_factor) cm
    where cm.analista_id is null
  ), '{}'::jsonb);

  -- El peso de la RENOVACION se guarda CON la foto desde el 23/09/2026. Antes
  -- solo se guardaba el del referido, y el de renovacion se RECONSTRUIA a
  -- partir de el al leer: mientras los dos valieron lo mismo no se noto, pero
  -- en cuanto se separan (migracion 20260923155859) un mes sellado contaria la
  -- renovacion con un peso que no es el que se uso. Y eso, una vez sellado, ya
  -- no se puede recuperar: la foto es la unica memoria de con que se calculo.
  insert into crm.periodos_cerrados (
    periodo, cerrado_por, automatico, ponderacion_referido, ponderacion_renovacion,
    meta_revision, cobertura
  ) values (
    p_periodo,
    case when v_automatico then null else v_uid end,
    v_automatico, v_factor, private.peso_renovacion_conversion(p_periodo),
    v_revision, v_cobertura
  );

  -- 5) La foto. El conjunto de personas es el ROSTER DEL MES (quien tenia meta),
  --    en union con quien PRODUJO aunque no tuviera meta: los dos importan para
  --    una foto de pago, y quien produjo sin meta tiene que quedar registrado
  --    con su nombre en vez de disolverse en un agregado anonimo — que es lo que
  --    hace la pantalla viva, y esta bien alli (privacidad) y mal aqui (pago).
  with conv as (
    select cm.*
    from private.conversion_mensual_por_vendedor(v_ini, v_fin, true, '{}'::uuid[], v_factor) cm
  ), prod as (
    select r.vendedor_id, r.categoria, r.moneda, r.contratos_real, r.capital_real
    from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
  ), car as (
    select m.* from private.metricas_cartera_por_vendedor(p_periodo) m
  ), roster as (
    -- `distinct on`: una fila por persona, pase lo que pase. La foto tiene la
    -- clave (periodo, vendedor), asi que dos metas del mismo vendedor en el
    -- mismo periodo harian reventar el cierre entero con un duplicado — un mes
    -- que no se puede cerrar por una fila repetida es peor que el duplicado.
    -- (Lo cazo el oraculo ejecutando, no leyendo.)
    select distinct on (mv.vendedor_id)
      mv.vendedor_id, mv.supervisor_id, mv.conversion_objetivo, mv.id as meta_vendedor_id
    from crm.metas_vendedor mv
    where mv.meta_periodo_id = v_periodo_id
    order by mv.vendedor_id, mv.id
  ), personas as (
    select vendedor_id from roster
    union
    select analista_id from conv
    union
    select vendedor_id from prod where vendedor_id is not null
    union
    select vendedor_id from car where vendedor_id is not null
  ), foto as (
    select
      pe.vendedor_id,
      r.meta_vendedor_id,
      coalesce(r.supervisor_id, supervisor_actual.perfil_id) as supervisor_id,
      coalesce(r.conversion_objetivo, 0::numeric) as conversion_objetivo
    from personas pe
    left join roster r on r.vendedor_id = pe.vendedor_id
    left join crm.equipo vendedor_actual
      on vendedor_actual.perfil_id = pe.vendedor_id
    left join crm.equipo supervisor_actual
      on supervisor_actual.perfil_id = vendedor_actual.supervisor_id
     and supervisor_actual.rol_crm = 'supervisor'
    where r.meta_vendedor_id is not null
       or (
         vendedor_actual.rol_crm = 'vendedor'
         and supervisor_actual.perfil_id is not null
       )
  )
  insert into crm.cierre_mes_vendedor (
    periodo, vendedor_id, nombre_completo, supervisor_id, supervisor_nombre,
    divisor, divisor_aproximado, divisor_por_motivo,
    cierres_no_referidos, cierres_referidos, cierres_de_arrastre,
    numerador, conversion_pct, estado,
    referidos_recibidos, referidos_dados_de_alta, referidos_aporta_pct, procedencia,
    ajuste_numerador, ajuste_pen, ajuste_usd,
    conversion_objetivo, detalles, cartera
  )
  select
    p_periodo,
    pe.vendedor_id,
    coalesce(nullif(btrim(pf.nombre_completo), ''),
             '(sin nombre · ' || left(pe.vendedor_id::text, 8) || ')'),
    pe.supervisor_id,
    coalesce(nullif(btrim(sup.nombre_completo), ''), '(sin ficha)'),
    coalesce(c.divisor, 0),
    coalesce(c.divisor_aproximado, 0),
    coalesce(c.divisor_por_motivo, '{}'::jsonb),
    coalesce(c.cierres_no_referidos, 0),
    coalesce(c.cierres_referidos, 0),
    coalesce(c.cierres_de_arrastre, 0),
    -- NETO: lo bruto menos lo que este mes absorbio de deudas viejas. Es lo que
    -- se paga, asi que es lo que se sella.
    coalesce(c.numerador, 0::numeric) - sal.aplicado_numerador,
    case when coalesce(c.divisor, 0) > 0
      then round(100.0 * (coalesce(c.numerador, 0::numeric) - sal.aplicado_numerador)
                 / coalesce(c.divisor, 0), 2) end,
    case
      when coalesce(c.divisor, 0) > 0 then 'medible'
      when coalesce(c.referidos_recibidos, 0) > 0 then 'solo_referidos'
      when coalesce(c.cierres_no_referidos, 0) + coalesce(c.cierres_referidos, 0) > 0 then 'solo_arrastre'
      else 'sin_actividad'
    end,
    coalesce(c.referidos_recibidos, 0),
    coalesce(alta.dados_de_alta, 0),
    c.referidos_aporta_pct,
    coalesce(c.procedencia, '[]'::jsonb),
    sal.aplicado_numerador,
    sal.aplicado_pen,
    sal.aplicado_usd,
    pe.conversion_objetivo,
    coalesce(det.detalles, '[]'::jsonb),
    jsonb_build_object(
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
  from foto pe
  left join conv c on c.analista_id = pe.vendedor_id
  left join car on car.vendedor_id = pe.vendedor_id
  left join public.perfiles pf on pf.id = pe.vendedor_id
  left join public.perfiles sup on sup.id = pe.supervisor_id
  left join lateral (
    -- El capital bruto del mes por moneda, que es el techo de lo que este mes
    -- puede absorber. PEN y USD por separado: una deuda en soles no se paga con
    -- produccion en dolares.
    -- ⚠️ Va ANTES del `saldar_ajustes` que lo consume: un LATERAL solo puede
    -- mirar a su izquierda.
    select
      coalesce(sum(pr.capital_real) filter (where pr.moneda = 'PEN'), 0) as pen,
      coalesce(sum(pr.capital_real) filter (where pr.moneda = 'USD'), 0) as usd
    from prod pr
    where pr.vendedor_id = pe.vendedor_id
  ) cap on true
  -- Lo que este mes puede absorber de las deudas viejas del vendedor. Es
  -- VOLATIL a proposito: ademas de devolver lo aplicado, DESCUENTA lo saldado y
  -- deja el resto arrastrandose. Se llama una vez por persona, que es la unica
  -- forma en que la cuenta cuadra.
  left join lateral private.saldar_ajustes(
    pe.vendedor_id,
    coalesce(c.numerador, 0::numeric),
    coalesce(cap.pen, 0::numeric),
    coalesce(cap.usd, 0::numeric)
  ) sal on true
  left join lateral (
    select count(*)::int as dados_de_alta
    from crm.leads l
    where l.origen = 'referido'
      and l.creado_en >= v_ini and l.creado_en < v_fin
      and l.creado_por = pe.vendedor_id
  ) alta on true
  left join lateral (
    -- ⚠️ `capital_real` y `contratos_real` van NETOS del descuento que este mes
    -- absorbio, casilla a casilla. Es la correccion de un fallo de DINERO: la
    -- primera version marcaba la deuda como saldada y NO la restaba de ninguna
    -- cifra, asi que el asesor cobraba igual y la deuda desaparecia — miles de
    -- soles perdonados en silencio, sin una sola linea que lo dijera.
    select jsonb_agg(jsonb_build_object(
      'categoria', dimensiones.categoria,
      'moneda', dimensiones.moneda,
      'capital_objetivo', coalesce(d.capital_objetivo, 0),
      'capital_real', greatest(coalesce(pr.capital_real, 0) - coalesce(aj.capital, 0), 0),
      'capital_cumplimiento_pct', case when coalesce(d.capital_objetivo, 0) > 0
        then round(100.0 * greatest(coalesce(pr.capital_real, 0) - coalesce(aj.capital, 0), 0)
                   / d.capital_objetivo, 2) end,
      'contratos_objetivo', coalesce(d.contratos_objetivo, 0),
      'contratos_real', greatest(coalesce(pr.contratos_real, 0) - coalesce(aj.contratos, 0), 0),
      'contratos_cumplimiento_pct', case when coalesce(d.contratos_objetivo, 0) > 0
        then round(100.0 * greatest(coalesce(pr.contratos_real, 0) - coalesce(aj.contratos, 0), 0)
                   / d.contratos_objetivo, 2) end,
      'capital_ajuste', coalesce(aj.capital, 0),
      'contratos_ajuste', coalesce(aj.contratos, 0)
    ) order by array_position(
      array['nuevo','renovacion','upgrade'], dimensiones.categoria
    ), dimensiones.moneda) as detalles
    from (values
      ('nuevo'::text, 'PEN'::text), ('nuevo', 'USD'),
      ('renovacion', 'PEN'), ('renovacion', 'USD'),
      ('upgrade', 'PEN'), ('upgrade', 'USD')
    ) dimensiones(categoria, moneda)
    left join crm.metas_vendedor_detalle d
      on d.meta_vendedor_id = pe.meta_vendedor_id
     and d.categoria = dimensiones.categoria
     and d.moneda = dimensiones.moneda
    left join prod pr on pr.vendedor_id = pe.vendedor_id
      and pr.categoria = dimensiones.categoria
     and pr.moneda = dimensiones.moneda
    left join lateral (
      select coalesce((e->>'capital')::numeric, 0) as capital,
             coalesce((e->>'contratos')::int, 0) as contratos
      from jsonb_array_elements(sal.aplicado_detalle) e
      where e->>'categoria' = dimensiones.categoria
        and e->>'moneda' = dimensiones.moneda
      limit 1
    ) aj on true
  ) det on true;

  get diagnostics v_vendedores = row_count;

  -- El rastro del cierre NO se escribe en `crm.actividades`: esa tabla cuelga de
  -- un lead y un cierre de mes no es de ningun lead. El registro lo deja el
  -- trigger de auditoria sobre `crm.periodos_cerrados`, con quien, cuando y que.

  return jsonb_build_object(
    'ok', true,
    'periodo', to_char(p_periodo, 'YYYY-MM'),
    'automatico', v_automatico,
    'vendedores', v_vendedores,
    'meta_revision', v_revision,
    'cobertura', v_cobertura
  );
end;
$function$;

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
    select distinct e.lead_id
    from private.conversion_episodios(
      v_ini, v_cosecha_fin, null, true, null, v_factor
    ) e
    where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.lead_id is not null
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
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and not e.fue_referido)::int as cierres_no_referidos,
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.fue_referido)::int as cierres_referidos,
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
      coalesce(sum(capital_lead_usd), 0) as capital_usd
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
          and e.origen in ('landing', 'formulario', 'referido')
          and (p_origen is null or e.origen = p_origen)
      ),
      'aporte_cierres', (
        select coalesce(sum(e.aporte_numerador), 0)
        from ep_flujo e
        where e.tipo = 'cierre' and not e.anulado
          and e.origen in ('landing', 'formulario', 'referido')
          and (p_origen is null or e.origen = p_origen)
      ),
      -- El total global conserva cierres de bajas, supervisores o autor nulo,
      -- mientras responsables[] sólo enumera vendedores activos. El residual
      -- hace visible esa diferencia sin reasignar el cierre a otra persona.
      'cierres_fuera_del_roster', (
        select count(distinct e.lead_id)::int
        from ep_flujo e
        where e.tipo = 'cierre' and not e.anulado
          and e.origen in ('landing', 'formulario', 'referido')
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
          and e.origen in ('landing', 'formulario', 'referido')
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
           and e.origen in ('landing', 'formulario', 'referido')
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
             and e.origen in ('landing', 'formulario', 'referido')
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
$function$;

-- ---------------------------------------------------------------------------
-- (d) Re-sellar las TRES declaraciones, con la normalizacion DEL CENSO.
-- ---------------------------------------------------------------------------
update private.analitica_leads_citas_exenciones e
   set huella = md5(regexp_replace(regexp_replace(
                      lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
                      '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')),
       razon  = e.razon || ' 23/09/2026: el peso de la RENOVACION se guarda con la foto '
                        || '(cerrar_periodo) o se declara tal como se aplica (las dos puertas), '
                        || 'en vez de reconstruirse desde el del referido.'
  from pg_proc p
 where p.oid = to_regprocedure(e.objeto)
   and e.objeto in ('crm.cerrar_periodo(date)',
                    'crm.metricas_conversiones_equipo_fn(date,date)',
                    'private.metricas_conversiones_implementacion(date,date,text)');

update private.analitica_lc_sello
   set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
 where id;

-- ---------------------------------------------------------------------------
-- (e) POSTFLIGHT
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_ok text; a_eq jsonb; a_im jsonb; d_eq jsonb; d_im jsonb; v_a jsonb; v_d jsonb;
  v_claims text := current_setting('request.jwt.claims', true);
  v_gerente uuid; v_peso numeric; v_sellado numeric;
  v_mes date := date_trunc('month', (now() at time zone 'America/Lima'))::date;
  v_hoy date := (now() at time zone 'America/Lima')::date;
begin
  v_ok := private.assert_analitica_leads_citas();
  if v_ok not like 'OK:%' then
    raise exception 'POSTFLIGHT: el trinquete quedo en rojo: %', v_ok;
  end if;

  select payload into a_eq from _pr2_antes where puerta = 'equipo';
  select payload into a_im from _pr2_antes where puerta = 'impl';

  select e.perfil_id into v_gerente from crm.equipo e
   where e.rol_crm = 'gerencia' and e.activo and private.rol_crm(e.perfil_id) = 'gerencia'
   order by e.perfil_id limit 1;
  if v_gerente is null then
    raise exception 'POSTFLIGHT: no hay perfil de gerencia activo';
  end if;
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_gerente, 'role', 'authenticated')::text, true);
  begin
    d_eq := crm.metricas_conversiones_equipo_fn(v_mes, v_hoy);
    d_im := private.metricas_conversiones_implementacion(v_mes, v_hoy, null);
  exception when others then
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  -- 1) NI UN NUMERO MOVIDO en ninguna de las dos puertas: payload entero.
  v_a := a_eq - 'generado_en';  v_d := d_eq - 'generado_en';
  if v_a is distinct from v_d then
    raise exception 'POSTFLIGHT: la puerta de equipo se movio. Bloques distintos: %',
      (select string_agg(k, ', ' order by k) from jsonb_object_keys(v_a) k
        where (v_a -> k) is distinct from (v_d -> k));
  end if;
  v_a := a_im - 'generado_en';  v_d := d_im - 'generado_en';
  if v_a is distinct from v_d then
    raise exception 'POSTFLIGHT: la implementacion se movio. Bloques distintos: %',
      (select string_agg(k, ', ' order by k) from jsonb_object_keys(v_a) k
        where (v_a -> k) is distinct from (v_d -> k));
  end if;

  -- 2) LA PRUEBA QUE IMPORTA: con los pesos SEPARADOS, lo declarado sigue a lo
  --    aplicado. Se mueve el de renovacion dentro de un savepoint y se exige que
  --    las dos puertas lo declaren; antes declaraban el del referido y esto
  --    habria fallado. Luego se deshace.
  begin
    update crm.conversion_pesos set peso_renovacion = 0.42
     where vigente_desde = (select max(vigente_desde) from crm.conversion_pesos);

    perform set_config('request.jwt.claims',
      jsonb_build_object('sub', v_gerente, 'role', 'authenticated')::text, true);
    d_eq := crm.metricas_conversiones_equipo_fn(v_mes, v_hoy);
    d_im := private.metricas_conversiones_implementacion(v_mes, v_hoy, null);
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

    if (d_eq #>> '{nucleo,peso_renovacion}')::numeric is distinct from 0.42 then
      raise exception 'POSTFLIGHT: la puerta de equipo declara % y el peso de renovacion es 0.42. Sigue publicando el del referido.',
        d_eq #>> '{nucleo,peso_renovacion}';
    end if;
    if (d_im #>> '{nucleo,peso_renovacion}')::numeric is distinct from 0.42 then
      raise exception 'POSTFLIGHT: la implementacion declara % y el peso de renovacion es 0.42.',
        d_im #>> '{nucleo,peso_renovacion}';
    end if;
    -- Y el del REFERIDO no se ha movido: siguen siendo dos palancas.
    if (d_eq #>> '{nucleo,peso_referido}')::numeric is distinct from 0.150 then
      raise exception 'POSTFLIGHT: mover la renovacion movio el peso del referido declarado (%)',
        d_eq #>> '{nucleo,peso_referido}';
    end if;

    raise exception 'DESHACIENDO_LA_PRUEBA';
  exception
    when others then
      if sqlerrm <> 'DESHACIENDO_LA_PRUEBA' then
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
        raise;
      end if;
  end;

  if private.peso_renovacion_conversion(v_mes) is distinct from 0.150 then
    raise exception 'POSTFLIGHT: la prueba dejo el peso en % en vez de 0.150',
      private.peso_renovacion_conversion(v_mes);
  end if;

  -- 3) Y AL SELLAR, la foto guarda su propio peso. Se sella agosto de verdad
  --    dentro de un savepoint que se deshace: `crm.cerrar_periodo` no tiene
  --    efectos fuera de las tablas (ni pg_notify, ni net.http, ni dblink),
  --    comprobado el 23/09, asi que el rollback lo deshace entero.
  begin
    perform set_config('request.jwt.claims',
      jsonb_build_object('sub', v_gerente, 'role', 'authenticated')::text, true);
    perform crm.cerrar_periodo('2026-08-01'::date);
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

    select ponderacion_renovacion, ponderacion_referido into v_sellado, v_peso
      from crm.periodos_cerrados where periodo = '2026-08-01'::date;
    if v_sellado is null then
      raise exception 'POSTFLIGHT: se sello un mes y NO se guardo el peso de la renovacion. Esa es justo la ventana que esta migracion viene a cerrar.';
    end if;
    if v_sellado is distinct from private.peso_renovacion_conversion('2026-08-01'::date) then
      raise exception 'POSTFLIGHT: se guardo % y el peso vigente de renovacion es %',
        v_sellado, private.peso_renovacion_conversion('2026-08-01'::date);
    end if;

    raise exception 'DESHACIENDO_EL_SELLO';
  exception
    when others then
      if sqlerrm <> 'DESHACIENDO_EL_SELLO' then
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
        raise;
      end if;
  end;

  -- 4) Y el sello de prueba se deshizo: la tabla sigue vacia.
  if (select count(*) from crm.periodos_cerrados) <> 0 then
    raise exception 'POSTFLIGHT: quedo un periodo sellado de la prueba. Hay que borrarlo antes de nada.';
  end if;

  -- 5) Dueno, definer, volatilidad y search_path de las tres, intactos.
  if (select count(*) from pg_proc p
       where p.oid in (to_regprocedure('crm.cerrar_periodo(date)'),
                       to_regprocedure('crm.metricas_conversiones_equipo_fn(date,date)'),
                       to_regprocedure('private.metricas_conversiones_implementacion(date,date,text)'))
         and p.proowner = 'postgres'::regrole and p.prosecdef
         and p.proconfig @> array['search_path=""']) <> 3 then
    raise exception 'POSTFLIGHT: cambio el dueno, el definer o el search_path de alguna de las tres';
  end if;
end;
$postflight$;

select 'peso-renovacion-se-guarda-y-se-declara' as migracion,
       private.peso_referido_conversion(current_date) as peso_referido,
       private.peso_renovacion_conversion(current_date) as peso_renovacion,
       (select count(*) from crm.periodos_cerrados) as meses_sellados,
       private.assert_analitica_leads_citas() as trinquete;

commit;

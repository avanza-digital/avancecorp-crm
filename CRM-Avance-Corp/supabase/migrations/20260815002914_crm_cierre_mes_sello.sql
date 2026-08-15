-- ---------------------------------------------------------------------------
-- El sello de un mes: la foto de lo que se pago
-- ---------------------------------------------------------------------------
-- QUE ARREGLA. El CRM no GUARDA el resultado de un mes: lo RECALCULA cada vez
-- que alguien lo abre. Mientras nadie cobre por esos numeros da igual; en cuanto
-- deciden una comision, es un problema contable — porque el mes que se pago
-- puede dejar de coincidir con el mes que la pantalla enseña, sin que nadie haya
-- tocado ese mes.
--
-- No es teorico. Medido el 2026-08-14: el agosto de un vendedor paso de 38,33 %
-- a 5,00 % en dos horas por una anulacion de gerencia. Esa la decidio Miguel;
-- las que preocupan son las que no decide nadie:
--   · el TOTAL DE EMPRESA se calcula sobre quien esta en el roster HOY
--     (`crm.conversion_mensual_fn` arranca en `private.roster_metas_vendedores()`,
--     que no recibe periodo), asi que una baja en octubre cambia agosto;
--   · las metas se pueden REPUBLICAR sobre un mes pasado y el cumplimiento se
--     recalcula contra las nuevas (agosto ya lleva 7 revisiones);
--   · la anulacion es retroactiva y de una sola direccion.
--
-- QUE HACE. Guarda una FOTO por (mes, vendedor) con todo lo que decide pago:
-- conversion, cumplimiento de meta y capital. Esta migracion solo la ESCRIBE;
-- que las pantallas la sirvan en vez de recalcular es la migracion siguiente.
-- El orden es deliberado: primero existe el registro, despues se consume.
--
-- DECISIONES DE MIGUEL (2026-08-14), que son las que dan forma a esto:
--   1. El mes se cierra el DIA 10 del mes siguiente. Del 1 al 10, ventana de
--      ajuste. Se cierra SOLO; el aviso se construye aparte.
--   2. Se sella TODO lo que decide pago, no solo la conversion.
--   3. Un mes cerrado NO SE REESCRIBE NUNCA. Lo que haya que corregir despues se
--      descuenta en el mes vivo, como una planilla. Por eso no hay —ni habra—
--      una operacion de reabrir: append-only de verdad.
--
-- ⚠️ EL NOMBRE SE CONGELA CON EL NUMERO. La foto guarda `nombre_completo` y el
-- del supervisor, no solo los uuid. Un asesor puede irse del equipo, y una foto
-- de lo que se le pago tiene que poder leerse sin depender de que su ficha siga
-- ahi. Es tambien lo que cierra la puerta del roster: la foto no vuelve a
-- preguntar quien esta hoy en el equipo.
--
-- NO TOCA NADA DE `public`. No cambia ninguna policy existente ni ningun grant
-- de una tabla existente.
-- ---------------------------------------------------------------------------

begin;

set local lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- 0. Preflight — las piezas de las que la foto se alimenta
-- ---------------------------------------------------------------------------
do $preflight$
begin
  -- La foto NO reimplementa nada: llama a los dos nucleos unicos. Si alguno
  -- faltara, el cierre los reinventaria y naceria la tercera formula.
  if to_regprocedure('private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)') is null then
    raise exception 'Falta private.conversion_mensual_por_vendedor: el nucleo unico de la conversion.';
  end if;
  if to_regprocedure('private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)') is null then
    raise exception 'Falta private.produccion_mes_por_vendedor: aplicar antes 20260815001957.';
  end if;
  if to_regprocedure('private.peso_referido_conversion(date)') is null then
    raise exception 'Falta private.peso_referido_conversion.';
  end if;
  if to_regprocedure('private.roster_metas_vendedores()') is null then
    raise exception 'Falta private.roster_metas_vendedores.';
  end if;
  -- El cierre SALDA las deudas que arrastran los meses cerrados anteriores, asi
  -- que la maquinaria del ajuste tiene que existir ya.
  if to_regprocedure('private.saldar_ajustes(uuid,numeric,numeric,numeric)') is null then
    raise exception 'Falta private.saldar_ajustes: aplicar antes 20260815002100.';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. El mes cerrado
-- ---------------------------------------------------------------------------
create table crm.periodos_cerrados (
  /** Primer dia del mes cerrado. */
  periodo date primary key
    constraint periodos_cerrados_periodo_mes_check
      check (periodo = date_trunc('month', periodo)::date),
  cerrado_en timestamptz not null default now(),
  /**
   * Quien lo cerro. NULL = lo cerro el ciclo automatico del dia 10, que es el
   * camino normal. Se guarda por si algun dia gerencia cierra a mano.
   */
  cerrado_por uuid references public.perfiles(id) on delete restrict,
  automatico boolean not null default true,
  /** El peso del referido que regia ese mes, sellado con el resto. */
  ponderacion_referido numeric not null,
  /** La revision de metas vigente al sellar: identifica CONTRA QUE se midio. */
  meta_revision integer not null,
  /**
   * La cobertura del mes tal cual la publicaba la pantalla (medible, suelo
   * historico, motivo). Se sella porque forma parte de como se leyo el numero:
   * un mes marcado «provisional» y pagado igual tiene que seguir diciendolo.
   */
  cobertura jsonb not null,
  constraint periodos_cerrados_automatico_check
    check ((automatico and cerrado_por is null) or (not automatico and cerrado_por is not null))
);

comment on table crm.periodos_cerrados is
  'Meses cerrados: a partir del sello, el resultado del mes deja de recalcularse y se sirve la foto. Append-only y SIN operacion de reabrir, por decision de Miguel (2026-08-14): un mes pagado no se reescribe; lo que haya que corregir se descuenta en el mes vivo.';
comment on column crm.periodos_cerrados.cerrado_por is
  'NULL cuando lo cerro el ciclo automatico del dia 10 (el camino normal).';
comment on column crm.periodos_cerrados.cobertura is
  'La cobertura publicada ese mes (medible / motivo / suelo). Se sella porque forma parte de como se leyo el numero.';

alter table crm.periodos_cerrados enable row level security;
revoke all privileges on table crm.periodos_cerrados
  from public, anon, authenticated, service_role;

create trigger trg_audit_periodos_cerrados
after insert or delete or update on crm.periodos_cerrados
for each row execute function private.log_audit_crm();

-- ---------------------------------------------------------------------------
-- 2. La foto por vendedor
-- ---------------------------------------------------------------------------
create table crm.cierre_mes_vendedor (
  periodo date not null references crm.periodos_cerrados(periodo) on delete restrict,
  vendedor_id uuid not null references public.perfiles(id) on delete restrict,
  /**
   * IDENTIDAD CONGELADA. Un asesor puede irse del equipo y su ficha cambiar de
   * nombre; la foto de lo que se le pago tiene que leerse sin depender de eso.
   */
  nombre_completo text not null,
  supervisor_id uuid references public.perfiles(id) on delete restrict,
  supervisor_nombre text,

  -- Conversion: los mismos campos que publica crm.conversion_mensual_fn.
  divisor integer not null,
  divisor_aproximado integer not null default 0,
  divisor_por_motivo jsonb not null default '{}'::jsonb,
  cierres_no_referidos integer not null,
  cierres_referidos integer not null,
  cierres_de_arrastre integer not null,
  numerador numeric not null,
  /** NULL cuando el divisor es 0: no hay porcentaje, y 0 % seria mentira. */
  conversion_pct numeric,
  estado text not null,
  referidos_recibidos integer not null,
  referidos_dados_de_alta integer not null,
  referidos_aporta_pct numeric,
  procedencia jsonb not null default '[]'::jsonb,

  /**
   * LO DESCONTADO en este mes por deudas de meses ya cerrados (cierres anulados
   * despues de pagar). `numerador` de arriba ya viene NETO —es lo que se paga— y
   * esto dice cuanto se le quito y por que, para que la foto sea auditable: el
   * bruto se recupera sumando los dos. Ver `crm.ajustes_mes_cerrado`.
   */
  ajuste_numerador numeric not null default 0,
  ajuste_pen numeric not null default 0,
  ajuste_usd numeric not null default 0,

  -- Meta y capital: los mismos campos que publica crm.cumplimiento_metas_fn.
  conversion_objetivo numeric,
  /**
   * Capital y contratos, objetivo y real, por categoria y moneda — el array
   * `detalles` tal cual lo publica la pantalla. Va en jsonb y no en columnas
   * porque su forma es (categoria x moneda) y crece con el catalogo: aplanarlo
   * obligaria a una migracion cada vez que se añada una categoria.
   * PEN y USD JAMAS se suman: viajan como filas distintas dentro del array.
   */
  detalles jsonb not null default '[]'::jsonb,

  primary key (periodo, vendedor_id)
);

comment on table crm.cierre_mes_vendedor is
  'Foto por (mes, vendedor) de todo lo que decidio pago: conversion, cumplimiento de meta y capital. Es el registro de lo que se pago, asi que congela tambien el NOMBRE: el asesor puede irse del equipo. Deny-by-default: se lee solo via las funciones del esquema crm.';
comment on column crm.cierre_mes_vendedor.nombre_completo is
  'Congelado al sellar. Sin el, la foto de un mes pagado dependeria de que la ficha del asesor siga existiendo.';
comment on column crm.cierre_mes_vendedor.detalles is
  'El array `detalles` publicado: capital y contratos, objetivo y real, por categoria y moneda.';

alter table crm.cierre_mes_vendedor enable row level security;
revoke all privileges on table crm.cierre_mes_vendedor
  from public, anon, authenticated, service_role;

create index idx_cierre_mes_vendedor_vendedor on crm.cierre_mes_vendedor (vendedor_id, periodo desc);

create trigger trg_audit_cierre_mes_vendedor
after insert or delete or update on crm.cierre_mes_vendedor
for each row execute function private.log_audit_crm();

-- ---------------------------------------------------------------------------
-- 3. Append-only, en las dos tablas
-- ---------------------------------------------------------------------------
-- Un mes cerrado no se edita ni se borra. Es la decision de Miguel llevada al
-- esquema: si la foto se pudiera retocar, seria exactamente igual de movil que
-- el recalculo que viene a sustituir, solo que con menos rastro.
create or replace function private.trg_cierre_mes_append_only()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  raise exception using
    errcode = 'P0409',
    message = 'Un mes cerrado no se edita ni se borra',
    hint    = 'Por diseno: lo que haya que corregir de un mes pagado se descuenta en el mes vivo, no se reescribe el mes.';
end;
$function$;

comment on function private.trg_cierre_mes_append_only() is
  'Veta UPDATE y DELETE sobre las dos tablas del cierre de mes. El nombre lleva 00 en el trigger para que corra ANTES que el de auditoria.';

create trigger trg_periodos_cerrados_00_append_only
before update or delete on crm.periodos_cerrados
for each row execute function private.trg_cierre_mes_append_only();

create trigger trg_cierre_mes_vendedor_00_append_only
before update or delete on crm.cierre_mes_vendedor
for each row execute function private.trg_cierre_mes_append_only();

-- ---------------------------------------------------------------------------
-- 4. Cerrar un mes
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER porque escribe en dos tablas deny-by-default y lee de
-- `public.contratos` y del ledger. El gate es EXPLICITO y va antes de tocar
-- nada: gerencia, o el ciclo automatico (que llega como `service_role`, sin
-- `auth.uid()`).
--
-- ⚠️ CIERRA EN ORDEN, sin huecos. Un mes solo se puede cerrar si todos los
-- anteriores con datos ya lo estan. Sin esa regla, cerrar septiembre antes que
-- agosto dejaria agosto abierto para siempre —nadie vuelve a mirarlo— y el
-- arrastre de ajustes, que se apoya en la secuencia de meses, no sabria por
-- donde empezar.
create or replace function crm.cerrar_periodo(p_periodo date)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
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
  v_pendiente   date;
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
  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo = p_periodo) then
    raise exception using
      errcode = 'P0409',
      message = 'Ese mes ya estaba cerrado',
      hint    = 'Un mes cerrado no se reescribe: lo que haya que corregir se descuenta en el mes vivo.';
  end if;

  -- 3) Sin huecos: no se cierra un mes si queda alguno anterior CON DATOS
  --    abierto. «Con datos» = tiene metas publicadas; un mes sin metas nunca
  --    tuvo nada que pagar y no bloquea la secuencia.
  select min(mp.periodo) into v_pendiente
  from crm.meta_periodos mp
  where mp.periodo < p_periodo
    and not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = mp.periodo);
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
    'medible', v_medible,
    'suelo_historico', v_suelo,
    'motivo_no_medible', v_motivo
  );

  insert into crm.periodos_cerrados (
    periodo, cerrado_por, automatico, ponderacion_referido, meta_revision, cobertura
  ) values (
    p_periodo,
    case when v_automatico then null else v_uid end,
    v_automatico, v_factor, v_revision, v_cobertura
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
  )
  insert into crm.cierre_mes_vendedor (
    periodo, vendedor_id, nombre_completo, supervisor_id, supervisor_nombre,
    divisor, divisor_aproximado, divisor_por_motivo,
    cierres_no_referidos, cierres_referidos, cierres_de_arrastre,
    numerador, conversion_pct, estado,
    referidos_recibidos, referidos_dados_de_alta, referidos_aporta_pct, procedencia,
    ajuste_numerador, ajuste_pen, ajuste_usd,
    conversion_objetivo, detalles
  )
  select
    p_periodo,
    pe.vendedor_id,
    coalesce(pf.nombre_completo, '(sin ficha)'),
    r.supervisor_id,
    sup.nombre_completo,
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
    r.conversion_objetivo,
    coalesce(det.detalles, '[]'::jsonb)
  from personas pe
  left join roster r on r.vendedor_id = pe.vendedor_id
  left join conv c on c.analista_id = pe.vendedor_id
  left join public.perfiles pf on pf.id = pe.vendedor_id
  left join public.perfiles sup on sup.id = r.supervisor_id
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
      'categoria', d.categoria,
      'moneda', d.moneda,
      'capital_objetivo', d.capital_objetivo,
      'capital_real', greatest(coalesce(pr.capital_real, 0) - coalesce(aj.capital, 0), 0),
      'capital_cumplimiento_pct', case when d.capital_objetivo > 0
        then round(100.0 * greatest(coalesce(pr.capital_real, 0) - coalesce(aj.capital, 0), 0)
                   / d.capital_objetivo, 2) end,
      'contratos_objetivo', d.contratos_objetivo,
      'contratos_real', greatest(coalesce(pr.contratos_real, 0) - coalesce(aj.contratos, 0), 0),
      'contratos_cumplimiento_pct', case when d.contratos_objetivo > 0
        then round(100.0 * greatest(coalesce(pr.contratos_real, 0) - coalesce(aj.contratos, 0), 0)
                   / d.contratos_objetivo, 2) end,
      -- Y se DECLARA lo descontado en su propia casilla: la foto tiene que poder
      -- explicar por que ese numero no es el bruto.
      'capital_ajuste', coalesce(aj.capital, 0),
      'contratos_ajuste', coalesce(aj.contratos, 0)
    ) order by array_position(array['nuevo','renovacion','upgrade'], d.categoria), d.moneda) as detalles
    from crm.metas_vendedor_detalle d
    left join prod pr on pr.vendedor_id = pe.vendedor_id
      and pr.categoria = d.categoria and pr.moneda = d.moneda
    left join lateral (
      select coalesce((e->>'capital')::numeric, 0) as capital,
             coalesce((e->>'contratos')::int, 0) as contratos
      from jsonb_array_elements(sal.aplicado_detalle) e
      where e->>'categoria' = d.categoria and e->>'moneda' = d.moneda
      limit 1
    ) aj on true
    where d.meta_vendedor_id = r.meta_vendedor_id
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
$$;

comment on function crm.cerrar_periodo(date) is
  'Sella la foto de un mes: conversion, cumplimiento y capital por vendedor. Solo gerencia o el ciclo automatico. Cierra en orden y no reescribe: un mes cerrado no se vuelve a cerrar.';

revoke all on function crm.cerrar_periodo(date) from public, anon;
grant execute on function crm.cerrar_periodo(date) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Postflight
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_n integer;
begin
  -- Las dos tablas nacen deny-by-default: RLS ON, cero policies, cero grants.
  select count(*) into v_n
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'crm'
    and c.relname in ('periodos_cerrados', 'cierre_mes_vendedor')
    and c.relrowsecurity;
  if v_n <> 2 then
    raise exception 'Las tablas del cierre no quedaron con RLS activada (n=%)', v_n;
  end if;

  select count(*) into v_n
  from pg_catalog.pg_policy p
  join pg_catalog.pg_class c on c.oid = p.polrelid
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'crm' and c.relname in ('periodos_cerrados', 'cierre_mes_vendedor');
  if v_n <> 0 then
    raise exception 'Las tablas del cierre no deben tener policies: se leen solo via funciones (n=%)', v_n;
  end if;

  -- Y no son alcanzables por la Data API.
  if has_table_privilege('authenticated', 'crm.cierre_mes_vendedor', 'SELECT')
     or has_table_privilege('anon', 'crm.periodos_cerrados', 'SELECT') then
    raise exception 'Las tablas del cierre quedaron legibles desde la Data API.';
  end if;

  -- El veto de edicion esta puesto en las dos.
  select count(*) into v_n
  from pg_catalog.pg_trigger t
  join pg_catalog.pg_class c on c.oid = t.tgrelid
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'crm'
    and c.relname in ('periodos_cerrados', 'cierre_mes_vendedor')
    and t.tgname like '%append_only'
    and not t.tgisinternal;
  if v_n <> 2 then
    raise exception 'Falta el veto de edicion en alguna tabla del cierre (n=%)', v_n;
  end if;

  -- La RPC es ejecutable por `authenticated` (el gate esta dentro) y NO por anon.
  if not has_function_privilege('authenticated', 'crm.cerrar_periodo(date)', 'EXECUTE') then
    raise exception 'crm.cerrar_periodo no quedo ejecutable por authenticated.';
  end if;
  if has_function_privilege('anon', 'crm.cerrar_periodo(date)', 'EXECUTE') then
    raise exception 'crm.cerrar_periodo quedo ejecutable por anon.';
  end if;
end;
$postflight$;

commit;

-- ---------------------------------------------------------------------------
-- VUELTA ATRAS
-- ---------------------------------------------------------------------------
-- `supabase/scripts/rollback-cierre-mes.sql` borra la RPC y las dos tablas.
-- ⚠️ Solo es seguro mientras NO se haya cerrado ningun mes: en cuanto exista una
-- foto, esa foto es el registro de lo que se pago y borrarla pierde justo lo que
-- esta migracion existe para conservar. Si ya hay meses cerrados, la vuelta
-- atras es dejar de CONSUMIR la foto (revertir la migracion siguiente), no
-- borrarla.

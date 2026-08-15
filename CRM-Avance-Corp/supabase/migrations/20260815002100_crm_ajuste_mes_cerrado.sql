-- ---------------------------------------------------------------------------
-- Corregir un mes ya pagado: el descuento va al mes vivo, y se arrastra
-- ---------------------------------------------------------------------------
-- QUE ARREGLA. Con el mes sellado (migraciones 20260815002914 y 20260815003742),
-- anular en noviembre un cierre de agosto ya no mueve agosto — bien — pero
-- tampoco le cuesta NADA al vendedor: el cierre mal hecho se quedaria pagado y
-- sin consecuencia. Esta migracion cierra ese hueco.
--
-- LA REGLA, decidida por Miguel el 2026-08-14: «un mes pagado no se reescribe;
-- el error se descuenta en el mes vivo, como una planilla». Y si el descuento no
-- cabe en el mes vivo, «se le queda a deber y se arrastra» hasta saldarlo. Un
-- cierre mal hecho no se perdona por caer en un mes flojo.
--
-- COMO FUNCIONA, en tres reglas:
--
--   1. Al anular un cierre de un mes CERRADO nace un AJUSTE con lo que ese
--      cierre valia: cuanto numerador (1 si no era referido, el peso del mes si
--      lo era) y cuanto capital, por moneda.
--   2. El mes VIVO enseña su numero ya descontado, y dice cuanto le queda por
--      saldar. Nunca baja de cero: lo que no cabe queda pendiente.
--   3. Al cerrar un mes se SALDA lo que ese mes pudo absorber y el resto sigue
--      pendiente para el siguiente. El sello guarda el numero descontado, que es
--      el que se paga.
--
-- ⚠️ POR QUE NUNCA BAJA DE CERO. Un porcentaje de conversion negativo no
-- significa nada para la persona que lo mira, y un capital negativo tampoco. La
-- deuda no se perdona: se arrastra. Es la unica combinacion que no miente ni
-- regala.
--
-- ⚠️ PEN Y USD SE SALDAN POR SEPARADO. Una deuda en soles no se paga con
-- produccion en dolares. Son dos saldos, y ninguno se convierte al otro.
--
-- ANULAR UN MES ABIERTO NO CAMBIA: sigue reescribiendo ese mes, que es lo
-- correcto mientras nadie haya cobrado por el.
--
-- NO TOCA NADA DE `public`.
-- ---------------------------------------------------------------------------

begin;

set local lock_timeout = '10s';

do $preflight$
begin
  -- ⚠️ ENMIENDA 2026-08-15, con OK EXPRESO de Miguel para tocar una migracion ya
  -- commiteada (regla que normalmente NO se rompe; aqui no habia alternativa y
  -- el lote no estaba aplicado en NINGUNA base, asi que no hay descuadre posible).
  --
  -- Aqui se exigia `crm.periodos_cerrados`, y eso creaba una DEPENDENCIA CIRCULAR
  -- que hacia INAPLICABLE el lote entero, en cualquier orden:
  --   · esta migracion pedia la tabla que crea 20260815002914;
  --   · 20260815002914 pide `private.saldar_ajustes`, que crea esta.
  --
  -- La dependencia real es de EJECUCION, no de creacion: las funciones de aqui
  -- leen `crm.periodos_cerrados` dentro de su cuerpo, y plpgsql no resuelve eso
  -- al crearlas. El orden correcto —esta ANTES que 20260815002914— lo garantiza
  -- el numero de version, no un preflight.
  --
  -- 🔴 Y LA LECCION, que es lo caro: lo cazo la BRANCH, no el banco local. El
  -- banco aplica estas migraciones SIN sus bloques de preflight (anclan md5 de
  -- funciones de produccion que los calcos no replican), asi que el circulo
  -- (⚠️ y ojo: ese nombre de delimitador NO se puede escribir aqui dentro; el
  -- dolar-quoting es lexico y cerraria el bloque a mitad del comentario)
  -- era invisible ahi y el oraculo daba 20/20 sobre un lote que no se podia
  -- aplicar. Un preflight que nunca se ejecuta no es una defensa: es un
  -- comentario caro.
  if to_regprocedure('private.contratos_afectados_por_anulacion(uuid)') is null then
    raise exception 'Falta private.contratos_afectados_por_anulacion.';
  end if;
  if to_regprocedure('private.vendedor_acreditado_del_cierre(uuid)') is null then
    raise exception 'Falta private.vendedor_acreditado_del_cierre.';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. El ajuste
-- ---------------------------------------------------------------------------
create table crm.ajustes_mes_cerrado (
  id uuid primary key default gen_random_uuid(),
  /** A quien se le descuenta. Es el ACREDITADO del cierre anulado, fotografiado. */
  vendedor_id uuid not null references public.perfiles(id) on delete restrict,
  /** El mes CERRADO del que viene el error. Solo informativo: no se toca. */
  periodo_origen date not null,
  /** El lead cuyo cierre se anulo. UNICO: un cierre genera un ajuste, no dos. */
  lead_id uuid not null unique references crm.leads(id) on delete restrict,
  motivo text not null,
  creado_por uuid not null references public.perfiles(id) on delete restrict,
  creado_en timestamptz not null default now(),

  /**
   * LO QUE VALIA el cierre, sellado al anular. No se recalcula despues: el peso
   * del referido puede cambiar de un mes a otro y la deuda es la de entonces.
   */
  numerador numeric not null check (numerador > 0),
  capital_pen numeric not null default 0 check (capital_pen >= 0),
  capital_usd numeric not null default 0 check (capital_usd >= 0),

  /**
   * El desglose del capital por (categoria, moneda), que es la casilla EXACTA de
   * la que hay que descontarlo. Sin el, el descuento se restaria de un total y
   * la cuota por categoria dejaria de cuadrar con su propia suma.
   * Forma: [{"categoria":"nuevo","moneda":"PEN","capital":40000,"contratos":1}]
   */
  detalle jsonb not null default '[]'::jsonb,

  /** Lo que queda por saldar. Solo lo mueve el cierre de un mes. */
  pendiente_numerador numeric not null check (pendiente_numerador >= 0),
  pendiente_pen numeric not null default 0 check (pendiente_pen >= 0),
  pendiente_usd numeric not null default 0 check (pendiente_usd >= 0),
  /** El desglose de lo que queda, con la misma forma que `detalle`. */
  pendiente_detalle jsonb not null default '[]'::jsonb,
  saldado_en timestamptz,

  constraint ajustes_mes_cerrado_motivo_check
    check (motivo is not null and btrim(motivo) <> '' and length(btrim(motivo)) <= 300),
  constraint ajustes_mes_cerrado_periodo_mes_check
    check (periodo_origen = date_trunc('month', periodo_origen)::date),
  -- Lo pendiente nunca supera lo debido.
  constraint ajustes_mes_cerrado_pendiente_check
    check (pendiente_numerador <= numerador
       and pendiente_pen <= capital_pen
       and pendiente_usd <= capital_usd),
  -- Saldado y con algo pendiente a la vez seria una contradiccion.
  constraint ajustes_mes_cerrado_saldado_check
    check ((saldado_en is null)
        or (pendiente_numerador = 0 and pendiente_pen = 0 and pendiente_usd = 0))
);

comment on table crm.ajustes_mes_cerrado is
  'Deudas que nacen al anular un cierre de un mes YA CERRADO. El mes pagado no se reescribe: el descuento se aplica al mes vivo y lo que no cabe se arrastra hasta saldarse. PEN y USD se saldan por separado.';
comment on column crm.ajustes_mes_cerrado.numerador is
  'Lo que ese cierre valia en la conversion: 1 si no era referido, el peso del mes si lo era. Sellado al anular porque el peso puede cambiar despues.';
comment on column crm.ajustes_mes_cerrado.pendiente_numerador is
  'Lo que queda por descontar. Solo lo mueve crm.cerrar_periodo al saldar.';

alter table crm.ajustes_mes_cerrado enable row level security;
revoke all privileges on table crm.ajustes_mes_cerrado
  from public, anon, authenticated, service_role;

create index idx_ajustes_mes_cerrado_pendiente
  on crm.ajustes_mes_cerrado (vendedor_id)
  where saldado_en is null;

create trigger trg_audit_ajustes_mes_cerrado
after insert or delete or update on crm.ajustes_mes_cerrado
for each row execute function private.log_audit_crm();

-- Un ajuste no se borra: es la razon escrita de un descuento. Se PUEDE
-- actualizar, pero solo para saldarlo — nunca para cambiar lo que se debe.
create or replace function private.trg_ajustes_mes_cerrado_solo_saldar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'DELETE' then
    raise exception using
      errcode = 'P0409',
      message = 'Un ajuste de mes cerrado no se borra',
      hint    = 'Es la razon escrita de un descuento a una persona.';
  end if;
  if new.vendedor_id is distinct from old.vendedor_id
     or new.lead_id is distinct from old.lead_id
     or new.periodo_origen is distinct from old.periodo_origen
     or new.numerador is distinct from old.numerador
     or new.capital_pen is distinct from old.capital_pen
     or new.capital_usd is distinct from old.capital_usd
     or new.detalle is distinct from old.detalle
     or new.motivo is distinct from old.motivo then
    raise exception using
      errcode = 'P0409',
      message = 'De un ajuste solo se puede mover lo pendiente',
      hint    = 'Lo que se debe quedo sellado al anular; cambiarlo reescribiria la deuda.';
  end if;
  -- Y lo pendiente solo BAJA: saldar es descontar, nunca volver a deber.
  if new.pendiente_numerador > old.pendiente_numerador
     or new.pendiente_pen > old.pendiente_pen
     or new.pendiente_usd > old.pendiente_usd then
    raise exception using
      errcode = 'P0409',
      message = 'Lo pendiente de un ajuste solo puede bajar';
  end if;
  return new;
end;
$function$;

create trigger trg_ajustes_mes_cerrado_00_solo_saldar
before update or delete on crm.ajustes_mes_cerrado
for each row execute function private.trg_ajustes_mes_cerrado_solo_saldar();

-- ---------------------------------------------------------------------------
-- 2. Lo que un vendedor debe hoy
-- ---------------------------------------------------------------------------
create or replace function private.ajuste_pendiente_por_vendedor()
returns table (
  vendedor_id uuid,
  numerador numeric,
  capital_pen numeric,
  capital_usd numeric,
  origenes jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    a.vendedor_id,
    sum(a.pendiente_numerador) as numerador,
    sum(a.pendiente_pen) as capital_pen,
    sum(a.pendiente_usd) as capital_usd,
    jsonb_agg(jsonb_build_object(
      'periodo', pg_catalog.to_char(a.periodo_origen, 'YYYY-MM'),
      'motivo', a.motivo,
      'numerador', a.pendiente_numerador
    ) order by a.periodo_origen, a.creado_en) as origenes
  from crm.ajustes_mes_cerrado a
  where a.saldado_en is null
  group by a.vendedor_id
$$;

comment on function private.ajuste_pendiente_por_vendedor() is
  'Lo que cada vendedor debe hoy por cierres anulados de meses ya cerrados, con su procedencia. Lo consumen la pantalla del mes vivo y el cierre de mes.';

revoke all on function private.ajuste_pendiente_por_vendedor() from public;

-- El numerador que se ENSEÑA en un mes vivo. Escrito aparte porque lo usan las
-- dos funciones de lectura y el suelo en cero es una regla de negocio, no un
-- detalle: un porcentaje negativo no significa nada para quien lo mira, y
-- perdonar la diferencia regalaria un cierre mal hecho. Lo que no cabe se
-- arrastra (lo guarda `pendiente_numerador`).
create or replace function private.conversion_con_ajuste(
  p_numerador numeric,
  p_pendiente numeric
)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select greatest(coalesce(p_numerador, 0) - coalesce(p_pendiente, 0), 0)
$$;

comment on function private.conversion_con_ajuste(numeric, numeric) is
  'El numerador que se ENSEÑA en un mes vivo: el bruto menos lo pendiente de meses ya cerrados, con suelo en cero.';

revoke all on function private.conversion_con_ajuste(numeric, numeric) from public;

-- ---------------------------------------------------------------------------
-- 3. Al anular, si el mes esta cerrado, nace la deuda
-- ---------------------------------------------------------------------------
-- Se escribe UNA vez y la usan los dos canales de anulacion (Avance y
-- cooperativas). Devuelve el ajuste creado, o NULL si el mes estaba abierto — en
-- cuyo caso no hay nada que hacer: ese mes se recalcula solo.
create or replace function private.registrar_ajuste_si_mes_cerrado(
  p_lead_id uuid,
  p_motivo text,
  p_por uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lead        crm.leads%rowtype;
  v_periodo     date;
  v_acreditado  uuid;
  v_referido    boolean;
  v_peso        numeric;
  v_numerador   numeric;
  v_pen         numeric := 0;
  v_usd         numeric := 0;
  v_detalle     jsonb := '[]'::jsonb;
  v_id          uuid;
begin
  select * into v_lead from crm.leads where id = p_lead_id;
  if not found or v_lead.convertido_en is null then
    return null;
  end if;

  v_periodo := date_trunc('month', v_lead.convertido_en at time zone 'America/Lima')::date;

  -- Mes ABIERTO: no hay deuda que registrar. El mes se recalcula y el cierre
  -- desaparece de el, que es el comportamiento de siempre.
  if not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo) then
    return null;
  end if;

  -- A quien se le descuenta: el mismo acreditado que usa la cuota.
  v_acreditado := coalesce(
    (select ca.acreditado_a from crm.cierres_avance_anulados ca where ca.lead_id = p_lead_id),
    private.vendedor_acreditado_del_cierre(p_lead_id));
  if v_acreditado is null then
    -- Sin acreditado no hay a quien descontarle. No se inventa un deudor.
    return null;
  end if;

  -- Lo que valia el cierre en la conversion. El origen sale del LEDGER (la foto
  -- del episodio), no de `crm.leads.origen`, que es una columna viva.
  select coalesce(bool_or(la.origen = 'referido'), false) into v_referido
  from crm.lead_asignaciones la
  where la.lead_id = p_lead_id and la.resultado = 'convertido';

  v_peso := private.peso_referido_conversion(v_periodo);
  v_numerador := case when v_referido then v_peso else 1 end;

  -- Y lo que valia en capital: los contratos que dejan de acreditar, con la
  -- MISMA regla que la cuota. PEN y USD por separado, y ADEMAS desglosado por
  -- categoria: es la casilla exacta de la que habra que descontarlo.
  select
    coalesce(sum(c.capital) filter (where c.moneda = 'PEN'), 0),
    coalesce(sum(c.capital) filter (where c.moneda = 'USD'), 0)
    into v_pen, v_usd
  from private.contratos_afectados_por_anulacion(p_lead_id) x
  join public.contratos c on c.id = x;

  select coalesce(jsonb_agg(jsonb_build_object(
           'categoria', d.categoria, 'moneda', d.moneda,
           'capital', d.capital, 'contratos', d.contratos)), '[]'::jsonb)
    into v_detalle
  from (
    select c.categoria, c.moneda, sum(c.capital) as capital, count(*)::int as contratos
    from private.contratos_afectados_por_anulacion(p_lead_id) x
    join public.contratos c on c.id = x
    group by c.categoria, c.moneda
  ) d;

  -- Un cierre que no valia nada no genera deuda.
  if v_numerador <= 0 and v_pen = 0 and v_usd = 0 then
    return null;
  end if;

  insert into crm.ajustes_mes_cerrado (
    vendedor_id, periodo_origen, lead_id, motivo, creado_por,
    numerador, capital_pen, capital_usd, detalle,
    pendiente_numerador, pendiente_pen, pendiente_usd, pendiente_detalle
  ) values (
    v_acreditado, v_periodo, p_lead_id, p_motivo, p_por,
    v_numerador, v_pen, v_usd, v_detalle,
    v_numerador, v_pen, v_usd, v_detalle
  )
  on conflict (lead_id) do nothing
  returning id into v_id;

  return v_id;
end;
$$;

comment on function private.registrar_ajuste_si_mes_cerrado(uuid, text, uuid) is
  'Si el cierre anulado pertenece a un mes YA CERRADO, registra la deuda que el vendedor arrastrara al mes vivo. Si el mes sigue abierto devuelve NULL: ese mes se recalcula solo.';

revoke all on function private.registrar_ajuste_si_mes_cerrado(uuid, text, uuid) from public;

-- ---------------------------------------------------------------------------
-- 4. Saldar al cerrar un mes
-- ---------------------------------------------------------------------------
-- Aplica al mes que se cierra todo lo que ese mes pueda absorber, y deja el
-- resto pendiente. Devuelve, por vendedor, lo aplicado — que es lo que el sello
-- tiene que descontar de la foto.
create or replace function private.saldar_ajustes(
  p_vendedor uuid,
  p_numerador_disponible numeric,
  p_pen_disponible numeric,
  p_usd_disponible numeric
)
returns table (
  aplicado_numerador numeric,
  aplicado_pen numeric,
  aplicado_usd numeric,
  aplicado_detalle jsonb
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_num numeric := greatest(coalesce(p_numerador_disponible, 0), 0);
  v_disp jsonb := jsonb_build_object('PEN', greatest(coalesce(p_pen_disponible, 0), 0),
                                     'USD', greatest(coalesce(p_usd_disponible, 0), 0));
  v_ap_num numeric := 0;
  v_ap jsonb := '{}'::jsonb;          -- clave "categoria|moneda" -> {capital, contratos}
  r record;
  b record;
  v_toma_num numeric;
  v_toma_cap numeric;
  v_toma_con integer;
  v_resto jsonb;
  v_clave text;
  v_prev jsonb;
  v_pen numeric;
  v_usd numeric;
begin
  -- Las deudas MAS VIEJAS primero: una de agosto no espera a que se salde una de
  -- octubre.
  for r in
    select * from crm.ajustes_mes_cerrado
    where vendedor_id = p_vendedor and saldado_en is null
    order by periodo_origen, creado_en
    for update
  loop
    v_toma_num := least(r.pendiente_numerador, v_num);
    v_num := v_num - v_toma_num;
    v_ap_num := v_ap_num + v_toma_num;

    -- El capital se descuenta CASILLA A CASILLA (categoria x moneda). Descontarlo
    -- de un total dejaria la cuota por categoria sin cuadrar con su propia suma,
    -- y —peor— antes ni siquiera se restaba: la deuda se daba por cobrada y el
    -- dinero se perdonaba en silencio.
    v_resto := '[]'::jsonb;
    for b in
      select (e->>'categoria') as categoria, (e->>'moneda') as moneda,
             coalesce((e->>'capital')::numeric, 0) as capital,
             coalesce((e->>'contratos')::int, 0) as contratos
      from jsonb_array_elements(coalesce(r.pendiente_detalle, '[]'::jsonb)) e
    loop
      v_toma_cap := least(b.capital, coalesce((v_disp->>b.moneda)::numeric, 0));
      -- Los contratos se descuentan en proporcion a lo que se pudo pagar: si se
      -- salda entero, se descuentan todos; si no, ninguno (un contrato no se
      -- parte por la mitad).
      v_toma_con := case when v_toma_cap >= b.capital then b.contratos else 0 end;

      if v_toma_cap > 0 then
        v_disp := jsonb_set(v_disp, array[b.moneda],
          to_jsonb(coalesce((v_disp->>b.moneda)::numeric, 0) - v_toma_cap));
        v_clave := b.categoria || '|' || b.moneda;
        v_prev := coalesce(v_ap->v_clave, jsonb_build_object('capital', 0, 'contratos', 0));
        v_ap := jsonb_set(v_ap, array[v_clave], jsonb_build_object(
          'capital', coalesce((v_prev->>'capital')::numeric, 0) + v_toma_cap,
          'contratos', coalesce((v_prev->>'contratos')::int, 0) + v_toma_con));
      end if;

      if b.capital - v_toma_cap > 0 then
        v_resto := v_resto || jsonb_build_array(jsonb_build_object(
          'categoria', b.categoria, 'moneda', b.moneda,
          'capital', b.capital - v_toma_cap,
          'contratos', b.contratos - v_toma_con));
      end if;
    end loop;

    select
      coalesce(sum((e->>'capital')::numeric) filter (where e->>'moneda' = 'PEN'), 0),
      coalesce(sum((e->>'capital')::numeric) filter (where e->>'moneda' = 'USD'), 0)
      into v_pen, v_usd
    from jsonb_array_elements(v_resto) e;

    update crm.ajustes_mes_cerrado
    set pendiente_numerador = r.pendiente_numerador - v_toma_num,
        pendiente_pen = v_pen,
        pendiente_usd = v_usd,
        pendiente_detalle = v_resto,
        saldado_en = case
          when (r.pendiente_numerador - v_toma_num) = 0 and v_pen = 0 and v_usd = 0
          then now() end
    where id = r.id;
  end loop;

  aplicado_numerador := v_ap_num;
  select
    coalesce(sum((v->>'capital')::numeric) filter (where split_part(k, '|', 2) = 'PEN'), 0),
    coalesce(sum((v->>'capital')::numeric) filter (where split_part(k, '|', 2) = 'USD'), 0)
    into aplicado_pen, aplicado_usd
  from jsonb_each(v_ap) as t(k, v);
  aplicado_pen := coalesce(aplicado_pen, 0);
  aplicado_usd := coalesce(aplicado_usd, 0);
  aplicado_detalle := coalesce((
    select jsonb_agg(jsonb_build_object(
      'categoria', split_part(k, '|', 1),
      'moneda', split_part(k, '|', 2),
      'capital', (v->>'capital')::numeric,
      'contratos', (v->>'contratos')::int))
    from jsonb_each(v_ap) as t(k, v)), '[]'::jsonb);
  return next;
end;
$$;

comment on function private.saldar_ajustes(uuid, numeric, numeric, numeric) is
  'Aplica al mes que se cierra todo lo que ese mes puede absorber de las deudas pendientes del vendedor, las mas viejas primero, y deja el resto arrastrandose. Devuelve lo aplicado CASILLA A CASILLA (categoria x moneda) porque es de esas casillas de donde el sello tiene que restarlo: sin el desglose, la deuda se daba por cobrada sin descontar un solo sol.';

revoke all on function private.saldar_ajustes(uuid, numeric, numeric, numeric) from public;

-- ---------------------------------------------------------------------------
-- 5. Postflight
-- ---------------------------------------------------------------------------
do $postflight$
begin
  if not (select relrowsecurity from pg_catalog.pg_class
          where oid = 'crm.ajustes_mes_cerrado'::regclass) then
    raise exception 'crm.ajustes_mes_cerrado no quedo con RLS activada.';
  end if;
  if exists (select 1 from pg_catalog.pg_policy where polrelid = 'crm.ajustes_mes_cerrado'::regclass) then
    raise exception 'crm.ajustes_mes_cerrado no debe tener policies: se lee solo via funciones.';
  end if;
  if has_table_privilege('authenticated', 'crm.ajustes_mes_cerrado', 'SELECT') then
    raise exception 'crm.ajustes_mes_cerrado quedo legible desde la Data API.';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_trigger
    where tgrelid = 'crm.ajustes_mes_cerrado'::regclass
      and tgname = 'trg_ajustes_mes_cerrado_00_solo_saldar') then
    raise exception 'Falta el veto de edicion del ajuste.';
  end if;
end;
$postflight$;

commit;

-- ---------------------------------------------------------------------------
-- VUELTA ATRAS
-- ---------------------------------------------------------------------------
-- `supabase/scripts/rollback-ajuste-mes-cerrado.sql`. ⚠️ Solo seguro si no hay
-- ningun ajuste registrado: cada fila es la razon escrita de un descuento a una
-- persona.

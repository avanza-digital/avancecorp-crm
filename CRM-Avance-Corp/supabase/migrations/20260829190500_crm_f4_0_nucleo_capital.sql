-- P-055 FASE 4.0 — LA CALCULADORA UNICA DE CAPITAL: private.capital_episodios
--
-- Orden de Miguel (29/08): «yo quiero ver todo ya... lo que necesito es crear
-- el sistema». Se publica la Fase 4 completa salvo las TRES piezas del motor
-- del sellado (produccion_mes_por_vendedor, cerrar_periodo,
-- registrar_ajuste_si_mes_cerrado), que no se tocan con el primer sellado a
-- 11 dias — razon de ingenieria, no de calendario: no se cambia el motor de
-- un cohete en la rampa. Van justo despues del 10/09.
--
-- QUE ES ESTO: el nucleo de HECHOS de capital. No devuelve totales: devuelve
-- episodios (un contrato, un desglose de renovacion, un cierre en coop) y las
-- pantallas SUMAN. Contrato completo en el vault:
-- «Contrato de la capa semantica - Capital (F4, 2026-08-29)».
--
-- Decisiones que encarna (todas de Miguel): d1/d2 analista que cierra ·
-- d3 mes comercial · d4 coops SON capital · d5 desglose renovado/adicional ·
-- d6 demos fuera · d15 roster informativo, no descuenta · d16 pipeline fuera ·
-- d17 mes y AUM = dos preguntas a la misma calculadora · 29/08 los ajustes
-- del analista no son capital de la empresa.
--
-- Dos ajustes que la PARIDAD con lo vivo exigio sobre el borrador:
--   * fecha_vencimiento en la fila-hecho (la pregunta «que vence» es capital);
--   * en los desgloses, el analista es el VENDEDOR CONGELADO de la operacion
--     (o.vendedor_id), que es a quien el sistema vivo acredita la economia de
--     cartera — no el analista del contrato nuevo.
--
-- El nucleo NO autoriza (regla 1): sin grants a la API; solo las funciones
-- DEFINER de capa 3 lo alcanzan. La visibilidad por-cliente de cada pantalla
-- se queda EN la pantalla (cada una conserva su gate historico): por eso la
-- paridad es exacta rol por rol.

begin;

do $preflight$
begin
  if not exists (select 1 from pg_attribute
                 where attrelid='public.contratos'::regclass
                   and attname in ('analista_cierre_id','es_demo') and not attisdropped
                 group by attrelid having count(*) = 2) then
    raise exception 'Faltan las columnas de la Fase 3: ABORTA';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='private' and p.proname='capital_episodios') then
    raise exception 'Ya existe private.capital_episodios: ABORTA (¿re-run?)';
  end if;
end
$preflight$;

set local lock_timeout = '5s';

create function private.capital_episodios(
  p_ini      timestamptz,
  p_fin      timestamptz,
  p_global   boolean,
  p_visibles uuid[]
) returns table(
  tipo              text,
  contrato_id       uuid,
  cierre_externo_id uuid,
  lead_id           uuid,
  cliente_id        uuid,
  analista_id       uuid,
  registrado_por    uuid,
  en_roster         boolean,
  moneda            text,
  monto             numeric,
  categoria         text,
  mes_comercial     date,
  fecha             timestamptz,
  fecha_vencimiento date,
  estado            text,
  anulado           boolean
)
language sql
stable
security definer
set search_path to ''
as $fn$
  -- Pierna CONTRATO: cada contrato NO-demo es un episodio, con su categoria.
  select
    'contrato_' || coalesce(c.categoria, 'nuevo'),
    c.id,
    null::uuid,
    null::uuid,
    c.cliente_id,
    c.analista_cierre_id,
    c.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      join crm.meta_periodos mp on mp.id = mv.meta_periodo_id
      where mp.periodo = date_trunc('month', c.fecha_cierre_comercial)::date
        and mv.vendedor_id = c.analista_cierre_id
    ),
    c.moneda,
    c.capital,
    c.categoria,
    date_trunc('month', c.fecha_cierre_comercial)::date,
    (c.fecha_cierre_comercial::timestamp at time zone 'America/Lima'),
    c.fecha_vencimiento,
    c.estado,
    false
  from public.contratos c
  where not c.es_demo
    and c.fecha_cierre_comercial >= (p_ini at time zone 'America/Lima')::date
    and c.fecha_cierre_comercial <  (p_fin at time zone 'America/Lima')::date
    and (p_global or c.analista_cierre_id = any(p_visibles))

  union all

  -- Pierna DESGLOSE (decision 5): en una renovacion, cuanto CONTINUA y cuanto
  -- es dinero NUEVO. El analista es el VENDEDOR CONGELADO de la operacion.
  select
    'desglose_' || parte.tipo,
    o.contrato_nuevo_id,
    null::uuid,
    null::uuid,
    o.cliente_id,
    o.vendedor_id,
    o.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      join crm.meta_periodos mp on mp.id = mv.meta_periodo_id
      where mp.periodo = o.periodo and mv.vendedor_id = o.vendedor_id
    ),
    o.moneda,
    parte.monto,
    o.tipo,
    o.periodo,
    (o.fecha_operacion::timestamp at time zone 'America/Lima'),
    c.fecha_vencimiento,
    c.estado,
    false
  from crm.operaciones_cartera o
  join public.contratos c on c.id = o.contrato_nuevo_id and not c.es_demo
  cross join lateral (values
    ('renovado',  o.capital_renovado),
    ('adicional', o.capital_adicional)
  ) as parte(tipo, monto)
  where parte.monto is not null
    and o.fecha_operacion >= (p_ini at time zone 'America/Lima')::date
    and o.fecha_operacion <  (p_fin at time zone 'America/Lima')::date
    and (p_global or o.vendedor_id = any(p_visibles))

  union all

  -- Pierna COOPERATIVA (decision 4): capital sin contrato Avance. Las
  -- anuladas viajan con monto 0 y anulado=true (historial, decision 15).
  select
    'cooperativa',
    null::uuid,
    ce.id,
    ce.lead_id,
    l.perfil_id,
    ce.vendedor_id,
    ce.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      join crm.meta_periodos mp on mp.id = mv.meta_periodo_id
      where mp.periodo = date_trunc('month', ce.creado_en at time zone 'America/Lima')::date
        and mv.vendedor_id = ce.vendedor_id
    ),
    ce.moneda,
    case when ce.anulado_en is null then ce.monto else 0::numeric end,
    'nuevo',
    date_trunc('month', ce.creado_en at time zone 'America/Lima')::date,
    ce.creado_en,
    ce.vence_en,
    case when ce.anulado_en is null then 'vigente' else 'anulado' end,
    ce.anulado_en is not null
  from crm.cierres_externos ce
  left join crm.leads l on l.id = ce.lead_id
  where ce.creado_en >= p_ini and ce.creado_en < p_fin
    and (p_global or ce.vendedor_id = any(p_visibles));
$fn$;

revoke execute on function private.capital_episodios(timestamptz, timestamptz, boolean, uuid[])
  from public, anon, authenticated;

-- LA VENTANA (regla 2): para pantallas futuras; las 16 vivas conservan su gate.
create function private.capital_autorizada(
  p_desde date,
  p_hasta date
) returns table(
  tipo text, contrato_id uuid, cierre_externo_id uuid, lead_id uuid,
  cliente_id uuid, analista_id uuid, registrado_por uuid, en_roster boolean,
  moneda text, monto numeric, categoria text, mes_comercial date,
  fecha timestamptz, fecha_vencimiento date, estado text, anulado boolean
)
language plpgsql
stable
security definer
set search_path to ''
as $fn$
declare
  v_uid      uuid := (select auth.uid());
  v_rol      text := private.rol_crm((select auth.uid()));
  v_global   boolean;
  v_visibles uuid[] := '{}'::uuid[];
begin
  if v_uid is null then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  v_global := coalesce(v_rol = 'gerencia', false) or (select private.es_lector_global());
  if not v_global then
    v_visibles := array(select private.vendedor_ids_visibles(v_uid));
    if coalesce(array_length(v_visibles, 1), 0) = 0 then
      raise exception 'No autorizado' using errcode = '42501';
    end if;
  end if;
  return query select * from private.capital_episodios(
    (p_desde::timestamp at time zone 'America/Lima'),
    ((p_hasta + 1)::timestamp at time zone 'America/Lima'),
    v_global, v_visibles);
end;
$fn$;

revoke execute on function private.capital_autorizada(date, date)
  from public, anon, authenticated;

-- --------------------------------------------------------------- POSTFLIGHT --
do $postflight$
declare
  v_pen numeric; v_esp numeric; v_cfg text[];
begin
  select p.proconfig into v_cfg from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='capital_episodios';
  if v_cfg is null or not (v_cfg @> array['search_path=""']::text[]) then
    raise exception 'POSTFLIGHT: el nucleo sin search_path vacio'; end if;
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    cross join lateral aclexplode(p.proacl) a
    left join pg_roles pr on pr.oid=a.grantee
    where n.nspname='private' and p.proname in ('capital_episodios','capital_autorizada')
      and a.privilege_type='EXECUTE'
      and (a.grantee = 0 or pr.rolname in ('anon','authenticated'))
  ) then
    raise exception 'POSTFLIGHT: el nucleo quedo alcanzable desde la API'; end if;

  -- Paridad de nacimiento, en LAS DOS monedas y en la pierna cooperativa
  -- (hallazgo M3 del auditor: solo PEN/contratos dejaba nacer verde un error
  -- de mapeo en USD o en coops).
  select coalesce(sum(monto),0) into v_pen
  from private.capital_episodios(
    (date '1900-01-01')::timestamp at time zone 'America/Lima',
    (date '9999-01-01')::timestamp at time zone 'America/Lima', true, '{}'::uuid[])
  where tipo like 'contrato_%' and estado='activo' and moneda='PEN';
  select coalesce(sum(capital),0) into v_esp
  from public.contratos where estado='activo' and moneda='PEN' and not es_demo;
  if v_pen is distinct from v_esp then
    raise exception 'POSTFLIGHT: AUM PEN del nucleo % <> crudo %', v_pen, v_esp; end if;

  select coalesce(sum(monto),0) into v_pen
  from private.capital_episodios(
    (date '1900-01-01')::timestamp at time zone 'America/Lima',
    (date '9999-01-01')::timestamp at time zone 'America/Lima', true, '{}'::uuid[])
  where tipo like 'contrato_%' and estado='activo' and moneda='USD';
  select coalesce(sum(capital),0) into v_esp
  from public.contratos where estado='activo' and moneda='USD' and not es_demo;
  if v_pen is distinct from v_esp then
    raise exception 'POSTFLIGHT: AUM USD del nucleo % <> crudo %', v_pen, v_esp; end if;

  select coalesce(sum(monto),0) into v_pen
  from private.capital_episodios(
    (date '1900-01-01')::timestamp at time zone 'America/Lima',
    (date '9999-01-01')::timestamp at time zone 'America/Lima', true, '{}'::uuid[])
  where tipo = 'cooperativa';
  select coalesce(sum(monto),0) into v_esp
  from crm.cierres_externos where anulado_en is null;
  if v_pen is distinct from v_esp then
    raise exception 'POSTFLIGHT: cooperativas del nucleo % <> tabla %', v_pen, v_esp; end if;

  raise notice 'POSTFLIGHT OK: nucleo vivo, cerrado a la API, AUM PEN+USD y coops al centimo';
end
$postflight$;

commit;

begin;

-- =============================================================================
-- Cartera comercial: gestiones de clientes, renovaciones, upgrades y conversión
-- =============================================================================
-- Reglas cerradas con Miguel (2026-08-24):
--   · una renovación crea OTRO contrato y enlaza/cierra el anterior;
--   · renovación = 1 conversión completa y NUNCA agrega divisor;
--   · upgrade = conversión solo fuera del mes del primer contrato del cliente;
--   · un cliente aporta como máximo 1 conversión por mes, aunque tenga varias
--     renovaciones o combine renovación + upgrade;
--   · capital renovado y capital adicional son dinero, no conversiones. Se
--     conservan separados porque el adicional tiene un esquema de pago distinto;
--   · acredita el asesor dueño de la cartera en el instante de la operación,
--     aunque Gerencia sea quien registre el contrato.

-- -----------------------------------------------------------------------------
-- 0. Preflight: no sobrescribir cuerpos distintos a los revisados
-- -----------------------------------------------------------------------------
do $preflight$
begin
  if to_regclass('crm.operaciones_cartera') is not null then
    raise exception 'crm.operaciones_cartera ya existe: revisar antes de reaplicar';
  end if;

  if (select md5(p.prosrc)
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'crear_contrato'
        and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_contrato jsonb, p_cronograma jsonb')
     is distinct from '18d93976d371e833868272c3b594ae4b' then
    raise exception 'public.crear_contrato cambió desde el preflight revisado';
  end if;

  if (select md5(p.prosrc)
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'private' and p.proname = 'conversion_mensual_por_vendedor')
     is distinct from 'ac9b2f19ba403e08fd40f0008c11866f' then
    raise exception 'private.conversion_mensual_por_vendedor cambió desde el preflight revisado';
  end if;

  if (select md5(p.prosrc)
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'crm' and p.proname = 'conversion_mensual_fn')
     is distinct from '9a5025e4f70c2ee2def4264aae629716' then
    raise exception 'crm.conversion_mensual_fn cambió desde el preflight revisado';
  end if;

  if (select md5(p.prosrc)
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'crm' and p.proname = 'cumplimiento_metas_fn')
     is distinct from '5c12bcdfa74becd5294cb6071ee34a6d' then
    raise exception 'crm.cumplimiento_metas_fn cambió desde el preflight revisado';
  end if;

  if (select md5(p.prosrc)
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'private' and p.proname = 'trg_tareas_before_insert')
     is distinct from '62fd2ca19a9508ed2af18114ddc47677' then
    raise exception 'private.trg_tareas_before_insert cambió desde el preflight revisado';
  end if;

  if (select md5(p.prosrc)
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'crm' and p.proname = 'cerrar_tarea')
     is distinct from 'f19894548c648a6a05a37e21df91cf0e' then
    raise exception 'crm.cerrar_tarea cambió desde el preflight revisado';
  end if;
end;
$preflight$;

-- -----------------------------------------------------------------------------
-- 1. Ledger inmutable de operaciones comerciales sobre clientes
-- -----------------------------------------------------------------------------
create table crm.operaciones_cartera (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references public.perfiles(id) on delete restrict,
  vendedor_id uuid not null references public.perfiles(id) on delete restrict,
  tipo text not null check (tipo in ('renovacion', 'upgrade')),
  contrato_origen_id uuid references public.contratos(id) on delete restrict,
  contrato_nuevo_id uuid not null unique references public.contratos(id) on delete restrict,
  fecha_operacion date not null,
  periodo date not null check (periodo = date_trunc('month', periodo)::date),
  moneda text not null check (moneda in ('PEN', 'USD')),
  capital_renovado numeric,
  capital_adicional numeric,
  elegible_conversion boolean not null,
  desglose_completo boolean not null default true,
  fuente text not null check (fuente in ('flujo_cartera', 'backfill_agosto_2026')),
  creado_por uuid not null references public.perfiles(id) on delete restrict,
  creado_en timestamptz not null default now(),

  constraint operaciones_cartera_periodo_fecha check (
    periodo = date_trunc('month', fecha_operacion)::date
  ),
  constraint operaciones_cartera_forma check (
    (
      tipo = 'renovacion'
      and (
        (
          desglose_completo
          and contrato_origen_id is not null
          and capital_renovado > 0
          and capital_adicional >= 0
        )
        or (
          not desglose_completo
          and fuente = 'backfill_agosto_2026'
          and contrato_origen_id is null
          and capital_renovado is null
          and capital_adicional is null
        )
      )
    )
    or (
      tipo = 'upgrade'
      and contrato_origen_id is null
      and capital_renovado is null
      and capital_adicional is null
      and desglose_completo
    )
  ),
  constraint operaciones_cartera_renovacion_convierte check (
    tipo <> 'renovacion' or elegible_conversion
  )
);

comment on table crm.operaciones_cartera is
  'Ledger de renovaciones y upgrades. Congela asesor, periodo y desglose económico. Una fila es una operación; la conversión deduplica por (cliente, mes).';
comment on column crm.operaciones_cartera.capital_adicional is
  'Capital extra aportado al renovar. Se reporta/paga por separado y jamás agrega otra conversión.';
comment on column crm.operaciones_cartera.elegible_conversion is
  'Renovación=true. Upgrade=true solo si su periodo es posterior al mes del primer contrato del cliente.';

create unique index operaciones_cartera_origen_renovado_uidx
  on crm.operaciones_cartera (contrato_origen_id)
  where contrato_origen_id is not null;
create index operaciones_cartera_periodo_vendedor_idx
  on crm.operaciones_cartera (periodo, vendedor_id);
create index operaciones_cartera_cliente_periodo_idx
  on crm.operaciones_cartera (cliente_id, periodo, fecha_operacion, creado_en, id);

alter table crm.operaciones_cartera enable row level security;
revoke all privileges on table crm.operaciones_cartera
  from public, anon, authenticated, service_role;
grant select on table crm.operaciones_cartera to authenticated;

create policy operaciones_cartera_select on crm.operaciones_cartera
  for select to authenticated
  using (
    (select private.puede_acceder_crm())
    and (
      (select private.es_lector_global())
      or (select private.rol_crm((select auth.uid()))) = 'gerencia'
      or vendedor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
    )
  );

-- El ledger no se edita ni se borra directamente. Una corrección futura deberá
-- ser otra operación explícita; así un cambio de categoría no reescribe pagos.
create or replace function private.trg_operaciones_cartera_append_only()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if coalesce(current_setting('crm.elimina_operacion_cartera', true), 'off') = 'on'
     and tg_op = 'DELETE' then
    return old;
  end if;
  raise exception using
    errcode = 'P0409',
    message = 'Una operación de cartera confirmada no se edita ni se borra directamente';
end;
$function$;

create trigger trg_operaciones_cartera_00_append_only
before update or delete on crm.operaciones_cartera
for each row execute function private.trg_operaciones_cartera_append_only();

revoke all on function private.trg_operaciones_cartera_append_only()
  from public, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 2. Alta atómica: contrato + operación + cierre del contrato renovado
-- -----------------------------------------------------------------------------
create or replace function public.crear_contrato(p_contrato jsonb, p_cronograma jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_es_analista boolean := (select public.es_analista());
  v_es_gestor_cartera boolean := (select public.es_gestor_cartera());
  v_rol_crm text := private.rol_crm(v_uid);
  v_es_gerencia_crm boolean := coalesce(v_rol_crm = 'gerencia', false);
  v_es_crm_catalogado boolean :=
    coalesce(v_rol_crm in ('vendedor', 'supervisor'), false)
    and nullif(current_setting('crm.producto_condicion_id', true), '') is not null;
  v_cliente_id uuid;
  v_numero text := nullif(btrim(p_contrato->>'numero_contrato'), '');
  v_categoria text := p_contrato->>'categoria';
  v_moneda text := upper(coalesce(nullif(p_contrato->>'moneda', ''), 'PEN'));
  v_capital numeric;
  v_anio integer := extract(year from now())::integer;
  v_seq integer;
  v_contrato_id uuid;
  v_fecha_operacion date;
  v_periodo date;
  v_cuota jsonb;
  v_asesor_id uuid;
  v_operacion_id uuid;
  v_origen_id uuid;
  v_origen public.contratos%rowtype;
  v_capital_renovado numeric;
  v_capital_adicional numeric;
  v_primer_periodo date;
  v_upgrade_elegible boolean;
begin
  if p_contrato is null or jsonb_typeof(p_contrato) <> 'object' then
    raise exception 'Faltan los datos del contrato' using errcode = '22023';
  end if;
  begin
    v_cliente_id := (p_contrato->>'cliente_id')::uuid;
    v_capital := (p_contrato->>'capital')::numeric;
  exception when invalid_text_representation then
    raise exception 'Cliente o capital inválido' using errcode = '22023';
  end;

  if not (
    v_es_analista or v_es_gestor_cartera or v_es_gerencia_crm or v_es_crm_catalogado
  ) or not private.puede_gestionar_cuentas_cliente(v_cliente_id) then
    raise insufficient_privilege using
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  if v_capital < 100 or v_capital > 100000000 then
    raise exception 'El capital debe estar entre 100 y 100,000,000';
  end if;
  if (p_contrato->>'tasa_anual')::numeric <= 0
     or (p_contrato->>'tasa_anual')::numeric > 50 then
    raise exception 'La tasa anual debe estar entre 0 y 50%%';
  end if;
  if v_categoria is null or v_categoria not in ('nuevo', 'renovacion', 'upgrade') then
    raise exception 'Selecciona la categoría del contrato (Nuevo, Renovación o Upgrade)';
  end if;
  if v_moneda not in ('PEN', 'USD') then
    raise exception 'Moneda inválida' using errcode = '22023';
  end if;

  -- Las operaciones de cartera necesitan un dueño congelado. No se atribuye a
  -- quien digitó: se atribuye al asesor de perfiles.asesor_perfil_id.
  if v_categoria in ('renovacion', 'upgrade') then
    select p.asesor_perfil_id into v_asesor_id
    from public.perfiles p
    where p.id = v_cliente_id and p.rol = 'cliente'
    for share;
    if v_asesor_id is null or not exists (
      select 1 from crm.equipo e
      where e.perfil_id = v_asesor_id and e.activo
        and e.rol_crm in ('vendedor', 'supervisor')
    ) then
      raise exception using
        errcode = '22023',
        message = 'Asigna un asesor activo al cliente antes de registrar la operación';
    end if;
  end if;

  if v_categoria = 'renovacion' then
    begin
      v_origen_id := (p_contrato->>'contrato_origen_id')::uuid;
      v_capital_renovado := (p_contrato->>'capital_renovado')::numeric;
      v_capital_adicional := coalesce((p_contrato->>'capital_adicional')::numeric, 0);
    exception when invalid_text_representation then
      raise exception 'Completa contrato anterior, capital renovado y adicional válidos'
        using errcode = '22023';
    end;

    select * into v_origen
    from public.contratos c
    where c.id = v_origen_id
    for update;
    if not found then
      raise exception 'El contrato a renovar no existe' using errcode = 'P0002';
    end if;
    if v_origen.cliente_id is distinct from v_cliente_id then
      raise exception 'El contrato anterior pertenece a otro cliente' using errcode = '22023';
    end if;
    if v_origen.estado not in ('activo', 'vencido') or v_origen.renovado_a_id is not null then
      raise exception 'El contrato anterior ya fue cerrado o renovado' using errcode = 'P0409';
    end if;
    if v_origen.fecha_vencimiento > (now() at time zone 'America/Lima')::date then
      raise exception 'La renovación solo se registra cuando el contrato llega a su fecha fin'
        using errcode = '22023';
    end if;
    if v_origen.moneda is distinct from v_moneda then
      raise exception 'La renovación debe conservar la moneda del contrato anterior'
        using errcode = '22023';
    end if;
    if (p_contrato->>'fecha_inicio')::date < v_origen.fecha_vencimiento then
      raise exception 'El contrato nuevo no puede iniciar antes del vencimiento anterior'
        using errcode = '22023';
    end if;
    if v_capital_renovado <= 0 or v_capital_renovado > v_origen.capital then
      raise exception 'El capital renovado debe ser mayor a cero y no superar el contrato anterior'
        using errcode = '22023';
    end if;
    if v_capital_adicional < 0 then
      raise exception 'El capital adicional no puede ser negativo' using errcode = '22023';
    end if;
    if v_capital is distinct from (v_capital_renovado + v_capital_adicional) then
      raise exception 'El nuevo capital debe ser capital renovado + capital adicional'
        using errcode = '22023';
    end if;
  end if;

  if v_numero is null then
    select coalesce(max(nullif(regexp_replace(split_part(c.numero_contrato, '-', 3),
             '[^0-9]', '', 'g'), '')::integer), 0) + 1
      into v_seq
    from public.contratos c
    where c.numero_contrato like 'AC-' || v_anio || '-%';
    v_numero := 'AC-' || v_anio || '-' || lpad(v_seq::text, 4, '0');
  end if;
  if exists (select 1 from public.contratos c where c.numero_contrato = v_numero) then
    raise exception 'El N de contrato % ya existe', v_numero;
  end if;

  insert into public.contratos (
    cliente_id, numero_contrato, capital, moneda, tasa_anual, modalidad,
    tipo_interes, fecha_inicio, fecha_vencimiento, notas_internas,
    categoria, estado, creado_por
  ) values (
    v_cliente_id, v_numero, v_capital, v_moneda,
    (p_contrato->>'tasa_anual')::numeric, p_contrato->>'modalidad',
    coalesce(nullif(p_contrato->>'tipo_interes', ''), 'simple'),
    (p_contrato->>'fecha_inicio')::date,
    (p_contrato->>'fecha_vencimiento')::date,
    nullif(btrim(coalesce(p_contrato->>'notas_internas', '')), ''),
    v_categoria, 'activo', v_uid
  ) returning id, fecha_cierre_comercial into v_contrato_id, v_fecha_operacion;

  if p_cronograma is null or jsonb_typeof(p_cronograma) <> 'array'
     or jsonb_array_length(p_cronograma) = 0 then
    raise exception 'El cronograma no puede estar vacío';
  end if;
  for v_cuota in select value from jsonb_array_elements(p_cronograma)
  loop
    insert into public.cronograma_pagos (
      contrato_id, numero_cuota, fecha_programada, monto_programado, estado, tipo
    ) values (
      v_contrato_id, (v_cuota->>'numero_cuota')::integer,
      (v_cuota->>'fecha_programada')::date,
      (v_cuota->>'monto_programado')::numeric, 'pendiente',
      coalesce(nullif(v_cuota->>'tipo', ''), 'cuota')
    );
  end loop;
  if p_contrato ? 'titulares' then
    perform public._sync_contrato_titulares(v_contrato_id, p_contrato->'titulares');
  end if;

  if v_categoria in ('renovacion', 'upgrade') then
    v_periodo := date_trunc('month', v_fecha_operacion)::date;
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('crm.operaciones_cartera'),
      pg_catalog.hashtext(v_cliente_id::text || '|' || v_periodo::text)
    );

    if v_categoria = 'upgrade' then
      select min(date_trunc('month', c.fecha_cierre_comercial)::date)
        into v_primer_periodo
      from public.contratos c
      where c.cliente_id = v_cliente_id;
      v_upgrade_elegible := v_periodo > v_primer_periodo;
    else
      v_upgrade_elegible := true;
    end if;

    insert into crm.operaciones_cartera (
      cliente_id, vendedor_id, tipo, contrato_origen_id, contrato_nuevo_id,
      fecha_operacion, periodo, moneda, capital_renovado, capital_adicional,
      elegible_conversion, desglose_completo, fuente, creado_por
    ) values (
      v_cliente_id, v_asesor_id, v_categoria, v_origen_id, v_contrato_id,
      v_fecha_operacion, v_periodo, v_moneda,
      case when v_categoria = 'renovacion' then v_capital_renovado end,
      case when v_categoria = 'renovacion' then v_capital_adicional end,
      v_upgrade_elegible, true, 'flujo_cartera', v_uid
    ) returning id into v_operacion_id;
  end if;

  if v_categoria = 'renovacion' then
    update public.cronograma_pagos
       set estado = 'trasladado'
     where contrato_id = v_origen_id and estado in ('pendiente', 'vencido');
    update public.contratos
       set estado = 'renovado', renovado_a_id = v_contrato_id,
           cerrado_en = now(), cerrado_por = v_uid
     where id = v_origen_id;
  end if;

  return jsonb_build_object(
    'id', v_contrato_id,
    'numero_contrato', v_numero,
    'operacion_id', v_operacion_id,
    'conversion_elegible', case
      when v_categoria in ('renovacion', 'upgrade') then v_upgrade_elegible
    end
  );
end;
$function$;

revoke all on function public.crear_contrato(jsonb,jsonb) from public, anon;
grant execute on function public.crear_contrato(jsonb,jsonb) to authenticated, service_role;

-- Cinturón final: ninguna vía directa puede confirmar en commit una categoría
-- de cartera sin su fila del ledger. Es diferido para que contrato y operación
-- se puedan crear dentro de la misma transacción.
create or replace function private.trg_contrato_exige_operacion_cartera()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.categoria in ('renovacion', 'upgrade') and not exists (
    select 1 from crm.operaciones_cartera o where o.contrato_nuevo_id = new.id
  ) then
    raise exception using
      errcode = '23514',
      message = 'Una renovación o upgrade debe registrarse por el flujo de cartera';
  end if;
  return null;
end;
$function$;

create constraint trigger trg_contratos_operacion_cartera_commit
after insert on public.contratos
deferrable initially deferred
for each row execute function private.trg_contrato_exige_operacion_cartera();

revoke all on function private.trg_contrato_exige_operacion_cartera()
  from public, anon, authenticated, service_role;

-- Hard-delete administrado: antes de borrar Storage se veta un mes sellado o
-- el contrato origen. En un mes abierto, borrar el contrato nuevo restaura el
-- contrato anterior y su cronograma antes de soltar los FKs.
create or replace function private.trg_preparar_eliminacion_operacion_cartera()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_op crm.operaciones_cartera%rowtype;
begin
  select * into v_op from crm.operaciones_cartera o
  where o.contrato_nuevo_id = new.contrato_id
     or o.contrato_origen_id = new.contrato_id
  order by (o.contrato_nuevo_id = new.contrato_id) desc
  limit 1;
  if not found then return new; end if;
  if v_op.contrato_origen_id = new.contrato_id then
    raise exception 'Primero elimina el contrato nuevo que renovó este contrato'
      using errcode = 'P0409';
  end if;
  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_op.periodo) then
    raise exception 'El contrato pertenece a un mes comercial cerrado y no se puede eliminar'
      using errcode = 'P0409';
  end if;
  return new;
end;
$function$;

create trigger trg_contrato_eliminaciones_00_operacion
before insert on private.contrato_eliminaciones
for each row execute function private.trg_preparar_eliminacion_operacion_cartera();

create or replace function private.trg_restaurar_operacion_antes_borrar_contrato()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_op crm.operaciones_cartera%rowtype;
begin
  select * into v_op from crm.operaciones_cartera o
  where o.contrato_nuevo_id = old.id for update;
  if not found then return old; end if;
  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_op.periodo) then
    raise exception 'El contrato pertenece a un mes comercial cerrado y no se puede eliminar'
      using errcode = 'P0409';
  end if;

  perform set_config('crm.elimina_operacion_cartera', 'on', true);
  delete from crm.operaciones_cartera o where o.id = v_op.id;
  perform set_config('crm.elimina_operacion_cartera', 'off', true);

  if v_op.tipo = 'renovacion' and v_op.contrato_origen_id is not null then
    update public.cronograma_pagos cp
       set estado = case
         when cp.fecha_programada < (now() at time zone 'America/Lima')::date
           then 'vencido'
         else 'pendiente'
       end
     where cp.contrato_id = v_op.contrato_origen_id and cp.estado = 'trasladado';
    update public.contratos c
       set estado = case
         when c.fecha_vencimiento < (now() at time zone 'America/Lima')::date
           then 'vencido'
         else 'activo'
       end,
       renovado_a_id = null, cerrado_en = null, cerrado_por = null
     where c.id = v_op.contrato_origen_id and c.renovado_a_id = old.id;
  end if;
  return old;
end;
$function$;

create trigger trg_contratos_05_restaurar_operacion
before delete on public.contratos
for each row execute function private.trg_restaurar_operacion_antes_borrar_contrato();

revoke all on function private.trg_preparar_eliminacion_operacion_cartera()
  from public, anon, authenticated, service_role;
revoke all on function private.trg_restaurar_operacion_antes_borrar_contrato()
  from public, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3. Backfill autorizado: agosto 2026
-- -----------------------------------------------------------------------------
-- No se inventa el origen ni el split de renovaciones históricas. Sí se congela
-- el asesor ACTUAL, decisión aprobada por Miguel. Los upgrades del mismo mes del
-- primer contrato quedan en el ledger pero con elegible_conversion=false.
with primer_contrato as (
  select c.cliente_id,
         min(date_trunc('month', c.fecha_cierre_comercial)::date) as primer_periodo
  from public.contratos c
  group by c.cliente_id
)
insert into crm.operaciones_cartera (
  cliente_id, vendedor_id, tipo, contrato_origen_id, contrato_nuevo_id,
  fecha_operacion, periodo, moneda, capital_renovado, capital_adicional,
  elegible_conversion, desglose_completo, fuente, creado_por, creado_en
)
select
  c.cliente_id,
  p.asesor_perfil_id,
  c.categoria,
  null,
  c.id,
  c.fecha_cierre_comercial,
  date_trunc('month', c.fecha_cierre_comercial)::date,
  c.moneda,
  null,
  null,
  c.categoria = 'renovacion'
    or date_trunc('month', c.fecha_cierre_comercial)::date > pc.primer_periodo,
  c.categoria = 'upgrade',
  'backfill_agosto_2026',
  p.asesor_perfil_id,
  c.creado_en
from public.contratos c
join public.perfiles p on p.id = c.cliente_id
join primer_contrato pc on pc.cliente_id = c.cliente_id
join crm.equipo e on e.perfil_id = p.asesor_perfil_id
where c.fecha_cierre_comercial >= date '2026-08-01'
  and c.fecha_cierre_comercial < date '2026-09-01'
  and c.categoria in ('renovacion', 'upgrade')
  and e.activo and e.rol_crm in ('vendedor', 'supervisor')
on conflict (contrato_nuevo_id) do nothing;

-- -----------------------------------------------------------------------------
-- 4. Métricas de cartera y suma al numerador (el divisor queda intacto)
-- -----------------------------------------------------------------------------
create or replace function private.metricas_cartera_por_vendedor(p_periodo date)
returns table (
  vendedor_id uuid,
  conversiones_clientes integer,
  conversiones_renovacion integer,
  conversiones_upgrade integer,
  operaciones_renovacion integer,
  operaciones_upgrade integer,
  capital_renovado_pen numeric,
  capital_renovado_usd numeric,
  capital_adicional_pen numeric,
  capital_adicional_usd numeric,
  renovaciones_sin_desglose integer
)
language sql
stable
security definer
set search_path = ''
as $function$
  with ops as materialized (
    select o.*
    from crm.operaciones_cartera o
    where o.periodo = p_periodo
  ), elegibles as (
    select o.*,
           row_number() over (
             partition by o.cliente_id, o.periodo
             order by o.fecha_operacion, o.creado_en, o.id
           ) as orden_conversion
    from ops o
    where o.elegible_conversion
  ), conversion as (
    select
      e.vendedor_id,
      count(*)::int as conversiones_clientes,
      count(*) filter (where e.tipo = 'renovacion')::int as conversiones_renovacion,
      count(*) filter (where e.tipo = 'upgrade')::int as conversiones_upgrade
    from elegibles e
    where e.orden_conversion = 1
    group by e.vendedor_id
  ), economia as (
    select
      o.vendedor_id,
      count(*) filter (where o.tipo = 'renovacion')::int as operaciones_renovacion,
      count(*) filter (where o.tipo = 'upgrade')::int as operaciones_upgrade,
      coalesce(sum(o.capital_renovado) filter (
        where o.tipo = 'renovacion' and o.moneda = 'PEN'), 0) as capital_renovado_pen,
      coalesce(sum(o.capital_renovado) filter (
        where o.tipo = 'renovacion' and o.moneda = 'USD'), 0) as capital_renovado_usd,
      coalesce(sum(o.capital_adicional) filter (
        where o.tipo = 'renovacion' and o.moneda = 'PEN'), 0) as capital_adicional_pen,
      coalesce(sum(o.capital_adicional) filter (
        where o.tipo = 'renovacion' and o.moneda = 'USD'), 0) as capital_adicional_usd,
      count(*) filter (
        where o.tipo = 'renovacion' and not o.desglose_completo)::int
        as renovaciones_sin_desglose
    from ops o
    group by o.vendedor_id
  ), personas as (
    select c.vendedor_id from conversion c
    union
    select e.vendedor_id from economia e
  )
  select
    p.vendedor_id,
    coalesce(c.conversiones_clientes, 0),
    coalesce(c.conversiones_renovacion, 0),
    coalesce(c.conversiones_upgrade, 0),
    coalesce(e.operaciones_renovacion, 0),
    coalesce(e.operaciones_upgrade, 0),
    coalesce(e.capital_renovado_pen, 0),
    coalesce(e.capital_renovado_usd, 0),
    coalesce(e.capital_adicional_pen, 0),
    coalesce(e.capital_adicional_usd, 0),
    coalesce(e.renovaciones_sin_desglose, 0)
  from personas p
  left join conversion c using (vendedor_id)
  left join economia e using (vendedor_id)
$function$;

comment on function private.metricas_cartera_por_vendedor(date) is
  'Conversión deduplicada por cliente/mes y economía completa de renovaciones por asesor. El adicional solo vive en las columnas de dinero.';
revoke all on function private.metricas_cartera_por_vendedor(date)
  from public, anon, authenticated, service_role;

create or replace function crm.metricas_cartera_fn(p_periodo date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
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
$function$;

revoke all on function crm.metricas_cartera_fn(date) from public, anon;
grant execute on function crm.metricas_cartera_fn(date) to authenticated, service_role;

-- El núcleo conserva su firma para no romper cierre de mes ni cumplimiento.
-- Solo suma `agg_ops.conversiones_clientes` al numerador; el divisor y todos sus
-- desgloses siguen saliendo EXCLUSIVAMENTE de lead_asignaciones.
create or replace function private.conversion_mensual_por_vendedor(
  p_ini timestamptz,
  p_fin timestamptz,
  p_global boolean,
  p_visibles uuid[],
  p_factor numeric
)
returns table (
  analista_id uuid,
  divisor integer,
  divisor_aproximado integer,
  divisor_por_motivo jsonb,
  cierres_no_referidos integer,
  cierres_referidos integer,
  cierres_de_arrastre integer,
  numerador numeric,
  conversion_pct numeric,
  procedencia jsonb,
  referidos_recibidos integer,
  referidos_aporta_pct numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
#variable_conflict use_column
begin
return query
with recibidos as (
  select
    la.analista_id, la.lead_id,
    (array_agg(la.origen order by la.asignado_en asc))[1] = 'referido' as fue_referido,
    (array_agg(la.motivo_apertura order by la.asignado_en asc))[1] as motivo,
    bool_or(la.aproximado) as aproximado
  from crm.lead_asignaciones la
  where la.asignado_en >= p_ini and la.asignado_en < p_fin
    and (p_global or la.analista_id = any(p_visibles))
  group by la.analista_id, la.lead_id
), cierres as (
  select
    la.analista_id, la.lead_id, (la.origen = 'referido') as fue_referido,
    date_trunc('month', la.asignado_en at time zone 'America/Lima')::date as mes_origen,
    date_trunc('month', p_ini at time zone 'America/Lima')::date as mes_periodo
  from crm.lead_asignaciones la
  where la.resultado = 'convertido'
    and coalesce(la.resultado_en, la.finalizado_en) >= p_ini
    and coalesce(la.resultado_en, la.finalizado_en) < p_fin
    and (p_global or la.analista_id = any(p_visibles))
    and not private.cierre_externo_anulado(la.lead_id)
), motivos as (
  select r.analista_id, r.motivo, count(*)::int as n
  from recibidos r where not r.fue_referido
  group by r.analista_id, r.motivo
), motivos_json as (
  select m.analista_id, jsonb_object_agg(m.motivo, m.n) as divisor_por_motivo
  from motivos m group by m.analista_id
), agg_div as (
  select r.analista_id,
    count(*) filter (where not r.fue_referido)::int as divisor,
    count(*) filter (where r.aproximado and not r.fue_referido)::int as divisor_aproximado,
    count(*) filter (where r.fue_referido)::int as referidos_recibidos
  from recibidos r group by r.analista_id
), agg_cie as (
  select c.analista_id,
    count(distinct c.lead_id) filter (where not c.fue_referido)::int as cierres_no_referidos,
    count(distinct c.lead_id) filter (where c.fue_referido)::int as cierres_referidos,
    count(distinct c.lead_id) filter (where c.mes_origen < c.mes_periodo)::int as cierres_de_arrastre
  from cierres c group by c.analista_id
), ops_elegibles as (
  select o.*,
    row_number() over (
      partition by o.cliente_id, o.periodo
      order by o.fecha_operacion, o.creado_en, o.id
    ) as orden_conversion
  from crm.operaciones_cartera o
  where o.periodo = date_trunc('month', p_ini at time zone 'America/Lima')::date
    and o.elegible_conversion
), agg_ops as (
  select o.vendedor_id as analista_id, count(*)::int as conversiones_clientes
  from ops_elegibles o
  where o.orden_conversion = 1
    and (p_global or o.vendedor_id = any(p_visibles))
  group by o.vendedor_id
), proc as (
  select c.analista_id, c.mes_cubo,
    (count(distinct c.lead_id) filter (where not c.fue_referido)
     + count(distinct c.lead_id) filter (where c.fue_referido))::int as cierres,
    count(distinct c.lead_id) filter (where c.fue_referido)::int as cierres_referidos
  from (
    select c0.analista_id, c0.lead_id, c0.fue_referido,
      case when
        (extract(year from p_ini at time zone 'America/Lima')::int * 12
         + extract(month from p_ini at time zone 'America/Lima')::int)
        - (extract(year from c0.mes_origen)::int * 12
           + extract(month from c0.mes_origen)::int) <= 11
      then c0.mes_origen end as mes_cubo
    from cierres c0
  ) c
  group by c.analista_id, c.mes_cubo
), proc_json as (
  select p.analista_id,
    jsonb_agg(jsonb_build_object(
      'mes', case when p.mes_cubo is not null then to_char(p.mes_cubo, 'YYYY-MM') end,
      'mes_nombre', case when p.mes_cubo is not null
        then private.etiqueta_mes_es(p.mes_cubo) else 'anteriores' end,
      'anio', case when p.mes_cubo is not null then extract(year from p.mes_cubo)::int end,
      'cierres', p.cierres, 'cierres_referidos', p.cierres_referidos
    ) order by p.mes_cubo desc nulls last) as procedencia
  from proc p group by p.analista_id
)
select
  coalesce(d.analista_id, c.analista_id, o.analista_id),
  coalesce(d.divisor, 0),
  coalesce(d.divisor_aproximado, 0),
  coalesce(mj.divisor_por_motivo, '{}'::jsonb),
  coalesce(c.cierres_no_referidos, 0),
  coalesce(c.cierres_referidos, 0),
  coalesce(c.cierres_de_arrastre, 0),
  (coalesce(c.cierres_no_referidos, 0)
   + p_factor * coalesce(c.cierres_referidos, 0)
   + coalesce(o.conversiones_clientes, 0))::numeric,
  case when coalesce(d.divisor, 0) > 0 then round(
    100.0 * (coalesce(c.cierres_no_referidos, 0)
      + p_factor * coalesce(c.cierres_referidos, 0)
      + coalesce(o.conversiones_clientes, 0)) / d.divisor, 2)
  end,
  coalesce(pj.procedencia, '[]'::jsonb),
  coalesce(d.referidos_recibidos, 0),
  case when coalesce(d.divisor, 0) > 0 then
    round(100.0 * p_factor * coalesce(c.cierres_referidos, 0) / d.divisor, 2)
  end
from agg_div d
full outer join agg_cie c on c.analista_id = d.analista_id
full outer join agg_ops o on o.analista_id = coalesce(d.analista_id, c.analista_id)
left join motivos_json mj on mj.analista_id = d.analista_id
left join proc_json pj on pj.analista_id = coalesce(d.analista_id, c.analista_id, o.analista_id);
end;
$function$;

comment on function private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric) is
  'Núcleo único: divisor solo leads no referidos recibidos; numerador = cierres de lead ponderados + máximo una operación elegible de cartera por cliente/mes. Renovación/adicional nunca alteran el divisor.';
revoke all on function private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)
  from public, anon, authenticated, service_role;

-- Enriquecer los dos payloads públicos sin copiar sus cuerpos grandes: la
-- función previa queda privada como base y el nombre público conserva firma.
alter function crm.conversion_mensual_fn(date)
  rename to conversion_mensual_sin_cartera_fn;
revoke all on function crm.conversion_mensual_sin_cartera_fn(date)
  from public, anon, authenticated, service_role;

create or replace function crm.conversion_mensual_fn(p_periodo date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_lector boolean := private.es_lector_global();
  v_base jsonb;
  v_total jsonb;
  v_responsables jsonb;
begin
  if v_uid is null or not coalesce(
    v_rol in ('vendedor','supervisor','gerencia') or v_lector, false
  ) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  v_base := crm.conversion_mensual_sin_cartera_fn(p_periodo);
  v_total := crm.metricas_cartera_fn(p_periodo)->'total';

  with m as materialized (
    select x.* from private.metricas_cartera_por_vendedor(p_periodo) x
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
  from jsonb_array_elements(coalesce(v_base->'responsables','[]'::jsonb))
       with ordinality e(value, ord)
  left join m on m.vendedor_id = (e.value->>'vendedor_id')::uuid;

  v_base := jsonb_set(v_base, '{responsables}', v_responsables, true);
  v_base := jsonb_set(v_base, '{cartera}', coalesce(v_total, '{}'::jsonb), true);
  v_base := jsonb_set(v_base, '{total,cartera}', coalesce(v_total, '{}'::jsonb), true);
  return v_base;
end;
$function$;

revoke all on function crm.conversion_mensual_fn(date) from public, anon;
grant execute on function crm.conversion_mensual_fn(date) to authenticated, service_role;

alter function crm.cumplimiento_metas_fn(date)
  rename to cumplimiento_metas_sin_cartera_fn;
revoke all on function crm.cumplimiento_metas_sin_cartera_fn(date)
  from public, anon, authenticated, service_role;

create or replace function crm.cumplimiento_metas_fn(p_periodo date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_lector boolean := private.es_lector_global();
  v_base jsonb;
  v_total jsonb;
  v_vendedores jsonb;
begin
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  v_base := crm.cumplimiento_metas_sin_cartera_fn(p_periodo);
  v_total := crm.metricas_cartera_fn(p_periodo)->'total';
  with m as materialized (
    select x.* from private.metricas_cartera_por_vendedor(p_periodo) x
  )
  select coalesce(jsonb_agg(
    jsonb_set(
      e.value || jsonb_build_object('cartera', jsonb_build_object(
        'conversiones_clientes', coalesce(m.conversiones_clientes, 0),
        'conversiones_renovacion', coalesce(m.conversiones_renovacion, 0),
        'conversiones_upgrade', coalesce(m.conversiones_upgrade, 0),
        'capital_renovado_pen', coalesce(m.capital_renovado_pen, 0),
        'capital_renovado_usd', coalesce(m.capital_renovado_usd, 0),
        'capital_adicional_pen', coalesce(m.capital_adicional_pen, 0),
        'capital_adicional_usd', coalesce(m.capital_adicional_usd, 0),
        'renovaciones_sin_desglose', coalesce(m.renovaciones_sin_desglose, 0)
      )),
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
  return jsonb_set(v_base, '{cartera}', coalesce(v_total, '{}'::jsonb), true);
end;
$function$;

revoke all on function crm.cumplimiento_metas_fn(date) from public, anon;
grant execute on function crm.cumplimiento_metas_fn(date) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 5. Agenda e historial comercial de clientes
-- -----------------------------------------------------------------------------
create table crm.actividades_cliente (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references public.perfiles(id) on delete cascade,
  vendedor_id uuid not null references crm.equipo(perfil_id) on delete restrict,
  tarea_id uuid unique references crm.tareas(id) on delete set null,
  tipo text not null check (tipo in (
    'llamada_realizada', 'llamada_no_contestada', 'whatsapp_enviado',
    'whatsapp_recibido', 'reunion_realizada', 'nota'
  )),
  detalle text check (detalle is null or length(detalle) <= 2000),
  creado_por uuid references public.perfiles(id) on delete set null,
  creado_en timestamptz not null default now()
);

comment on table crm.actividades_cliente is
  'Timeline comercial postventa de clientes. Separado de crm.actividades porque esa tabla pertenece al SLA y etapa de leads.';
create index actividades_cliente_cliente_fecha_idx
  on crm.actividades_cliente (cliente_id, creado_en desc);
create index actividades_cliente_vendedor_fecha_idx
  on crm.actividades_cliente (vendedor_id, creado_en desc);

alter table crm.actividades_cliente enable row level security;
revoke all privileges on table crm.actividades_cliente
  from public, anon, authenticated, service_role;
grant select on table crm.actividades_cliente to authenticated;

create policy actividades_cliente_select on crm.actividades_cliente
  for select to authenticated
  using (
    (select private.puede_acceder_crm())
    and (
      (select private.es_lector_global())
      or (select private.rol_crm((select auth.uid()))) = 'gerencia'
      or vendedor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
    )
  );

create or replace function private.trg_tareas_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_lead crm.leads%rowtype;
  v_cliente public.perfiles%rowtype;
  v_equipo crm.equipo%rowtype;
begin
  if new.lead_id is not null then
    select * into v_lead from crm.leads where id = new.lead_id;
    if not found then raise exception 'El lead de la tarea no existe'; end if;
    if v_lead.activo = false or v_lead.etapa in ('convertido','descartado') then
      raise exception 'El lead está cerrado: no admite tareas nuevas';
    end if;
    new.vendedor_id := v_lead.vendedor_id;
    new.asignado_supervisor_id := v_lead.asignado_supervisor_id;
  elsif new.perfil_id is not null then
    select * into v_cliente from public.perfiles p
    where p.id = new.perfil_id and p.rol = 'cliente';
    if not found then raise exception 'El cliente de la tarea no existe'; end if;
    if not v_cliente.activo then
      raise exception 'El cliente está inactivo: no admite tareas comerciales nuevas';
    end if;
    if v_cliente.asesor_perfil_id is null then
      raise exception 'Asigna un asesor al cliente antes de agendar una gestión';
    end if;
    select * into v_equipo from crm.equipo e
    where e.perfil_id = v_cliente.asesor_perfil_id and e.activo;
    if not found or v_equipo.rol_crm not in ('vendedor','supervisor') then
      raise exception 'El asesor de la cartera no está activo en el CRM';
    end if;
    new.vendedor_id := v_cliente.asesor_perfil_id;
    new.asignado_supervisor_id := case
      when v_equipo.rol_crm = 'vendedor' then v_equipo.supervisor_id
      else null
    end;
  end if;

  if new.estado <> 'pendiente'
     and coalesce(current_setting('crm.op_tarea', true), 'off') <> 'on' then
    raise exception 'Una tarea nace pendiente; los cierres van por una RPC de agenda'
      using errcode = '22023';
  end if;
  if new.tipo = 'reunion' then
    new.modalidad_reunion := coalesce(new.modalidad_reunion, 'sin_clasificar');
  else
    new.modalidad_reunion := null;
    new.ubicacion_reunion := null;
    new.enlace_reunion := null;
    new.resultado_reunion := null;
    new.motivo_no_realizada := null;
    new.detalle_cierre_reunion := null;
  end if;
  if new.estado = 'pendiente' then
    new.resultado_reunion := null;
    new.motivo_no_realizada := null;
    new.detalle_cierre_reunion := null;
  end if;
  new.cancelada_por := case when new.estado = 'cancelada' then 'sistema' else null end;
  new.cancelada_por_id := null;
  return new;
end;
$function$;

revoke all on function private.trg_tareas_before_insert()
  from public, anon, authenticated, service_role;

drop policy if exists tareas_insert on crm.tareas;
create policy tareas_insert on crm.tareas
  for insert to authenticated
  with check (
    activo = true and creado_por = (select auth.uid())
    and private.rol_crm((select auth.uid())) in ('vendedor','supervisor','gerencia')
    and (
      private.rol_crm((select auth.uid())) = 'gerencia'
      or vendedor_id = (select auth.uid())
      or (
        private.rol_crm((select auth.uid())) = 'supervisor'
        and (vendedor_id is null or vendedor_id in (
          select private.vendedor_ids_visibles((select auth.uid()))
        ))
      )
    )
    and (vendedor_id is null or vendedor_id in (
      select private.vendedor_ids_visibles((select auth.uid()))
    ))
    and (asignado_supervisor_id is null or asignado_supervisor_id in (
      select private.vendedor_ids_visibles((select auth.uid()))
    ))
    and (lead_id is null or exists (
      select 1 from crm.leads l where l.id = lead_id
    ))
    and (perfil_id is null or exists (
      select 1 from public.perfiles p
      where p.id = perfil_id and p.rol = 'cliente' and p.activo
        and p.asesor_perfil_id = vendedor_id
    ))
  );

-- Cuando cambia el dueño de una cartera, las tareas pendientes viajan con el
-- cliente. Si queda sin asesor se cancelan por sistema, no se dejan huérfanas.
create or replace function private.trg_cliente_reasigna_tareas_pendientes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_equipo crm.equipo%rowtype;
begin
  if new.rol <> 'cliente'
     or new.asesor_perfil_id is not distinct from old.asesor_perfil_id then
    return new;
  end if;
  if new.asesor_perfil_id is null then
    perform set_config('crm.cancela_sistema', 'on', true);
    update crm.tareas t set estado = 'cancelada'
    where t.perfil_id = new.id and t.activo and t.estado = 'pendiente';
    perform set_config('crm.cancela_sistema', 'off', true);
    return new;
  end if;
  select * into v_equipo from crm.equipo e
  where e.perfil_id = new.asesor_perfil_id and e.activo
    and e.rol_crm in ('vendedor','supervisor');
  if not found then
    raise exception 'El nuevo asesor no está activo en el CRM' using errcode = '22023';
  end if;
  update crm.tareas t
     set vendedor_id = new.asesor_perfil_id,
         asignado_supervisor_id = case
           when v_equipo.rol_crm = 'vendedor' then v_equipo.supervisor_id else null
         end
   where t.perfil_id = new.id and t.activo and t.estado = 'pendiente';
  return new;
end;
$function$;

create trigger trg_perfiles_cliente_reasigna_tareas
after update of asesor_perfil_id on public.perfiles
for each row execute function private.trg_cliente_reasigna_tareas_pendientes();

revoke all on function private.trg_cliente_reasigna_tareas_pendientes()
  from public, anon, authenticated, service_role;

create or replace function crm.cerrar_tarea(
  p_tarea_id uuid,
  p_estado text,
  p_resultado_tipo text default null,
  p_resultado_detalle text default null,
  p_siguiente jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_tarea crm.tareas%rowtype;
  v_act_id uuid;
  v_act_cliente_id uuid;
  v_sig_id uuid;
  v_retroceso text;
begin
  if v_uid is null or v_rol not in ('vendedor','supervisor','gerencia') then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_estado is null or p_estado not in ('completada','no_show','cancelada') then
    raise exception 'Estado de cierre inválido' using errcode = '22023';
  end if;

  select * into v_tarea
  from crm.tareas t
  where t.id = p_tarea_id and t.activo and t.estado = 'pendiente'
    and (
      v_rol = 'gerencia'
      or t.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
      or (t.vendedor_id is null and t.asignado_supervisor_id in (
        select private.vendedor_ids_visibles(v_uid)
      ))
    )
  for update;
  if not found then
    raise exception 'Tarea no encontrada, cerrada o fuera de tu ámbito';
  end if;

  if v_tarea.lead_id is not null then
    perform 1 from crm.leads l where l.id = v_tarea.lead_id for no key update;
  else
    perform 1 from public.perfiles p where p.id = v_tarea.perfil_id for share;
  end if;

  if p_resultado_tipo is not null and p_resultado_tipo not in (
    'llamada_realizada','llamada_no_contestada','whatsapp_enviado',
    'whatsapp_recibido','reunion_realizada','nota'
  ) then
    raise exception 'Tipo de resultado inválido';
  end if;
  if v_tarea.tipo = 'llamada' and p_estado = 'completada'
     and p_resultado_tipo is null then
    raise exception 'Registra el resultado de la llamada (contestó / no contestó)';
  end if;

  if p_resultado_tipo is not null and v_tarea.lead_id is not null then
    insert into crm.actividades (lead_id, tipo, detalle, creado_por)
    values (v_tarea.lead_id, p_resultado_tipo,
      nullif(btrim(coalesce(p_resultado_detalle, '')), ''), v_uid)
    returning id into v_act_id;
  elsif p_resultado_tipo is not null and v_tarea.perfil_id is not null then
    insert into crm.actividades_cliente (
      cliente_id, vendedor_id, tarea_id, tipo, detalle, creado_por
    ) values (
      v_tarea.perfil_id, v_tarea.vendedor_id, v_tarea.id, p_resultado_tipo,
      nullif(btrim(coalesce(p_resultado_detalle, '')), ''), v_uid
    ) returning id into v_act_cliente_id;
  end if;

  perform set_config('crm.op_tarea', 'on', true);
  update crm.tareas set
    estado = p_estado,
    resultado_actividad_id = v_act_id,
    resultado_reunion = case
      when v_tarea.tipo = 'reunion' and p_estado = 'completada'
        then 'sin_clasificar' else null end,
    motivo_no_realizada = case
      when v_tarea.tipo = 'reunion' and p_estado = 'no_show'
        then 'cliente_no_asistio'
      when v_tarea.tipo = 'reunion' and p_estado = 'cancelada'
        then 'otro' else null end,
    detalle_cierre_reunion = case
      when v_tarea.tipo = 'reunion' and p_estado = 'cancelada' then coalesce(
        nullif(btrim(coalesce(p_resultado_detalle, '')), ''),
        'Compatibilidad: motivo no estructurado por cliente anterior')
      when v_tarea.tipo = 'reunion'
        then nullif(btrim(coalesce(p_resultado_detalle, '')), '')
      else null end
  where id = p_tarea_id;
  perform set_config('crm.op_tarea', 'off', true);

  v_sig_id := private.crear_siguiente_tarea(
    v_tarea, p_siguiente,
    case when p_estado = 'no_show' then p_tarea_id else null end,
    v_uid
  );
  if p_estado = 'cancelada' and v_tarea.tipo = 'reunion'
     and v_tarea.lead_id is not null then
    v_retroceso := private.retroceso_por_anular_reunion(
      v_tarea.lead_id, p_tarea_id, v_uid
    );
  end if;
  return jsonb_build_object(
    'ok', true, 'tarea_id', p_tarea_id,
    'actividad_id', v_act_id,
    'actividad_cliente_id', v_act_cliente_id,
    'siguiente_id', v_sig_id, 'retroceso', v_retroceso
  );
end;
$function$;

revoke all on function crm.cerrar_tarea(uuid,text,text,text,jsonb)
  from public, anon;
grant execute on function crm.cerrar_tarea(uuid,text,text,text,jsonb)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 6. Postflight estructural y de negocio
-- -----------------------------------------------------------------------------
do $postflight$
declare
  v_ops integer;
  v_conversiones integer;
  v_adicional numeric;
begin
  select count(*) into v_ops
  from crm.operaciones_cartera o where o.periodo = date '2026-08-01';
  select count(*) into v_conversiones from (
    select o.cliente_id
    from crm.operaciones_cartera o
    where o.periodo = date '2026-08-01' and o.elegible_conversion
    group by o.cliente_id
  ) x;
  if v_ops < 48 or v_conversiones <> 29 then
    raise exception 'Backfill agosto inesperado: % operaciones, % conversiones (esperado >=48 y 29)',
      v_ops, v_conversiones;
  end if;
  select coalesce(sum(o.capital_adicional), 0) into v_adicional
  from crm.operaciones_cartera o where o.periodo = date '2026-08-01';
  if v_adicional <> 0 then
    raise exception 'El backfill inventó capital adicional: %', v_adicional;
  end if;
  if has_table_privilege('authenticated', 'crm.operaciones_cartera', 'INSERT')
     or has_table_privilege('authenticated', 'crm.actividades_cliente', 'INSERT') then
    raise exception 'Las tablas ledger no deben aceptar INSERT directo de authenticated';
  end if;
end;
$postflight$;

commit;

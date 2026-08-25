-- ---------------------------------------------------------------------------
-- Periodo comercial universal de contratos
-- ---------------------------------------------------------------------------
--
-- Un contrato puede registrarse en el CRM despues de haberse cerrado
-- comercialmente. `creado_en` conserva la verdad tecnica de la carga;
-- `fecha_inicio` conserva el inicio del plazo contractual; ninguna de las dos
-- vuelve a decidir, por accidente, el mes comercial.
--
-- La fecha historica se inicializa con la mejor evidencia disponible en el
-- sistema nuevo: el menor valor entre fecha_inicio y el dia de registro en
-- Lima. Es una inferencia de migracion, no una firma reconstruida. Por eso cada
-- fila conserva su fuente y Gerencia dispone de una correccion auditada.
-- ---------------------------------------------------------------------------

begin;

set local lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- 0. Preflight: esta migracion modifica fuentes vivas y debe fallar ante drift
-- ---------------------------------------------------------------------------
-- Mismo candado global que `crm.cerrar_periodo`: si un cierre ya empezo,
-- esperamos a que termine y vemos su sello; si entramos primero, el cierre
-- espera y luego calcula con la nueva fecha comercial.
do $lock_global$
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados')::bigint
  );
end;
$lock_global$;

do $preflight$
begin
  if to_regclass('public.contratos') is null
     or to_regclass('crm.periodos_cerrados') is null
     or to_regclass('public.audit_log') is null then
    raise exception 'Faltan contratos, periodos_cerrados o audit_log';
  end if;

  if exists (
    select 1 from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'contratos'
      and c.column_name in ('fecha_cierre_comercial', 'fuente_cierre_comercial')
  ) then
    raise exception 'El periodo comercial de contratos ya existe; revisar drift';
  end if;

  -- La regla del snapshot no se puede reescribir despues de pagar una foto.
  -- Produccion no tiene meses sellados al preparar esta migracion.
  if exists (select 1 from crm.periodos_cerrados) then
    raise exception 'Ya existen meses sellados: migrar el historico requiere un plan de reexpresion';
  end if;

  if (select md5(pg_catalog.pg_get_functiondef(p.oid))
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private'
         and p.proname = 'produccion_mes_por_vendedor'
         and pg_catalog.pg_get_function_identity_arguments(p.oid) =
             'p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo_id uuid')
     is distinct from 'aa766a509ef66741907c800db09046d1' then
    raise exception 'private.produccion_mes_por_vendedor cambio; revisar antes de aplicar';
  end if;

  if (select md5(pg_catalog.pg_get_functiondef(p.oid))
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm'
         and p.proname = 'metricas_capital_mes_fn'
         and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_meses integer')
     is distinct from 'ed85b2f644fc6034c5162147fef8a076' then
    raise exception 'crm.metricas_capital_mes_fn cambio; revisar antes de aplicar';
  end if;

  if (select md5(pg_catalog.pg_get_functiondef(p.oid))
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private'
         and p.proname = 'metricas_conversiones_implementacion'
         and pg_catalog.pg_get_function_identity_arguments(p.oid) =
             'p_desde date, p_hasta date')
     is distinct from '561f3a43fd4895eac28f4dbbfb0b5095' then
    raise exception 'private.metricas_conversiones_implementacion cambio; revisar antes de aplicar';
  end if;

  if (select md5(pg_catalog.pg_get_functiondef(p.oid))
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname = 'metricas_directorio'
         and pg_catalog.pg_get_function_identity_arguments(p.oid) = '')
     is distinct from 'e113b697035eecaae31d93bf5337e865' then
    raise exception 'public.metricas_directorio cambio; revisar antes de aplicar';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Dato canonico
-- ---------------------------------------------------------------------------
-- GENERATED STORED materializa el backfill sin ejecutar UPDATE: no dispara la
-- auditoria ni altera `actualizado_en` en los contratos historicos. Al quitar
-- la expresion quedan valores normales y corregibles.
alter table public.contratos
  add column fecha_cierre_comercial date
  generated always as (
    least(
      fecha_inicio,
      (creado_en at time zone 'America/Lima')::date
    )
  ) stored;

alter table public.contratos
  alter column fecha_cierre_comercial drop expression,
  alter column fecha_cierre_comercial set not null;

-- Todas las filas previas quedan reconocibles como inferidas. En las altas
-- nuevas, el trigger de abajo distingue registro normal de carga tardia; una
-- correccion posterior queda marcada aparte y exige la RPC auditada.
alter table public.contratos
  add column fuente_cierre_comercial text not null
  default 'migracion_inferida';

alter table public.contratos
  alter column fuente_cierre_comercial set default 'registro',
  add constraint contratos_fuente_cierre_comercial_check
    check (fuente_cierre_comercial in (
      'migracion_inferida', 'fecha_inicio_inferida', 'registro',
      'correccion_manual'
    )),
  add constraint contratos_fecha_cierre_comercial_finita_check
    check (isfinite(fecha_cierre_comercial));

comment on column public.contratos.fecha_cierre_comercial is
  'Fecha de negocio que decide el periodo comercial del contrato. No es fecha_inicio, creado_en ni el cierre de su ciclo contractual.';

comment on column public.contratos.fuente_cierre_comercial is
  'Procedencia de fecha_cierre_comercial: migracion_inferida, fecha_inicio_inferida, registro o correccion_manual.';

-- Las altas futuras que lleguen tarde reciben la misma regla general del
-- historico. No se usa DEFAULT porque un default no puede depender de
-- fecha_inicio; el BEFORE INSERT completa el dato antes del NOT NULL.
create or replace function private.definir_periodo_comercial_contrato()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_dia_registro date := (
    coalesce(new.creado_en, statement_timestamp())
      at time zone 'America/Lima'
  )::date;
  v_periodo date;
begin
  if tg_op = 'UPDATE' then
    if (
      new.fecha_cierre_comercial is distinct from old.fecha_cierre_comercial
      or new.fuente_cierre_comercial is distinct from old.fuente_cierre_comercial
    ) and coalesce(
      current_setting('crm.correccion_periodo_comercial', true), ''
    ) <> 'on' then
      raise exception 'La fecha de cierre comercial solo se corrige mediante su RPC auditada'
        using errcode = '42501';
    end if;
    return new;
  end if;

  if new.fecha_cierre_comercial is not null then
    raise exception 'La fecha de cierre comercial no se envia en el alta'
      using errcode = '42501',
            hint = 'El servidor la infiere; Gerencia puede corregirla despues mediante la RPC auditada.';
  end if;

  new.fecha_cierre_comercial := least(new.fecha_inicio, v_dia_registro);
  new.fuente_cierre_comercial := case
    when new.fecha_inicio < v_dia_registro then 'fecha_inicio_inferida'
    else 'registro'
  end;

  v_periodo := date_trunc('month', new.fecha_cierre_comercial)::date;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (v_periodo - date '2000-01-01')::integer
  );
  if exists (
    select 1
    from crm.periodos_cerrados pc
    where pc.periodo = v_periodo
  ) then
    raise exception 'No se puede registrar un contrato en un mes comercial sellado'
      using errcode = 'P0409',
            hint = 'Registra o corrige el cierre comercial antes del sello mensual.';
  end if;

  return new;
end;
$function$;

comment on function private.definir_periodo_comercial_contrato() is
  'Completa el periodo comercial al insertar y bloquea cambios directos fuera de la RPC auditada.';

revoke all on function private.definir_periodo_comercial_contrato()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_definir_periodo_comercial_contrato
  on public.contratos;
create trigger trg_definir_periodo_comercial_contrato
before insert or update on public.contratos
for each row execute function private.definir_periodo_comercial_contrato();

create index idx_contratos_fecha_cierre_comercial
  on public.contratos (fecha_cierre_comercial);

-- ---------------------------------------------------------------------------
-- 2. Las fuentes mensuales existentes consumen el dato canonico
-- ---------------------------------------------------------------------------
-- Los cuerpos vivos estan protegidos por hash arriba. Se modifican fragmentos
-- exactos para no copiar cientos de lineas ni revertir reglas de atribucion,
-- anulacion, alcance o conversion que no pertenecen a este cambio.
do $patch_functions$
declare
  v_def text;
  v_nueva text;
begin
  select pg_catalog.pg_get_functiondef(
           'private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)'::regprocedure
         ) into v_def;
  v_nueva := replace(
    v_def,
    'where c.creado_en>=p_ini and c.creado_en<p_fin',
    'where c.fecha_cierre_comercial >= (p_ini at time zone ''America/Lima'')::date
      and c.fecha_cierre_comercial < (p_fin at time zone ''America/Lima'')::date'
  );
  if v_nueva = v_def then
    raise exception 'No se encontro la ventana de contratos en produccion_mes_por_vendedor';
  end if;
  execute v_nueva;

  select pg_catalog.pg_get_functiondef(
           'crm.metricas_capital_mes_fn(integer)'::regprocedure
         ) into v_def;
  v_nueva := replace(v_def, 'c.fecha_inicio', 'c.fecha_cierre_comercial');
  if v_nueva = v_def then
    raise exception 'No se encontro fecha_inicio en metricas_capital_mes_fn';
  end if;
  execute v_nueva;

  select pg_catalog.pg_get_functiondef(
           'private.metricas_conversiones_implementacion(date,date)'::regprocedure
         ) into v_def;
  v_nueva := replace(
    v_def,
    'c.creado_en >= v_ini and c.creado_en < v_fin',
    'c.fecha_cierre_comercial >= p_desde and c.fecha_cierre_comercial <= p_hasta'
  );
  v_nueva := replace(
    v_nueva,
    'ct.creado_en >= v_ini and ct.creado_en < v_fin',
    'ct.fecha_cierre_comercial >= p_desde and ct.fecha_cierre_comercial <= p_hasta'
  );
  if v_nueva = v_def
     or position('c.creado_en >= v_ini and c.creado_en < v_fin' in v_nueva) > 0
     or position('ct.creado_en >= v_ini and ct.creado_en < v_fin' in v_nueva) > 0 then
    raise exception 'No se reemplazaron todas las ventanas de produccion en metricas_conversiones';
  end if;
  execute v_nueva;

  select pg_catalog.pg_get_functiondef('public.metricas_directorio()'::regprocedure)
    into v_def;
  v_nueva := replace(v_def, 'fecha_inicio', 'fecha_cierre_comercial');
  if v_nueva = v_def then
    raise exception 'No se encontro fecha_inicio en metricas_directorio';
  end if;
  execute v_nueva;
end;
$patch_functions$;

comment on function private.produccion_mes_por_vendedor(timestamptz, timestamptz, uuid) is
  'Capital y contratos acreditados por vendedor en el periodo de fecha_cierre_comercial. Lo consumen cumplimiento de metas y el sello mensual; cierres externos conservan su fecha automatica.';

comment on function crm.metricas_capital_mes_fn(integer) is
  'Capital colocado por periodo comercial, moneda y categoria. Sin PII; conserva el ambito CRM vigente.';

-- ---------------------------------------------------------------------------
-- 3. Lectura universal: funciona aunque el mes no tenga metas publicadas
-- ---------------------------------------------------------------------------
create or replace function crm.contratos_por_periodo_comercial_fn(p_periodo date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_lector boolean := private.es_lector_global();
  v_payload jsonb;
begin
  -- Sin una meta publicada no existe atribucion fiable por vendedor. Esta
  -- lectura completa es solo para Gerencia o lectores globales.
  if v_uid is null
     or not coalesce(v_rol = 'gerencia' or v_lector, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if p_periodo is null
     or p_periodo <> date_trunc('month', p_periodo)::date then
    raise exception 'El periodo debe ser el primer dia del mes'
      using errcode = '22023';
  end if;

  with base as materialized (
    select
      c.id,
      c.numero_contrato,
      c.cliente_id,
      c.fecha_cierre_comercial,
      c.fuente_cierre_comercial,
      c.creado_en,
      c.fecha_inicio,
      c.categoria,
      c.moneda,
      c.capital,
      c.estado
    from public.contratos c
    where c.fecha_cierre_comercial >= p_periodo
      and c.fecha_cierre_comercial < (p_periodo + interval '1 month')::date
  ), por_categoria as (
    select
      coalesce(b.categoria, 'sin_categoria') as categoria,
      b.moneda,
      count(*)::integer as contratos,
      coalesce(sum(b.capital), 0) as capital
    from base b
    group by coalesce(b.categoria, 'sin_categoria'), b.moneda
  )
  select jsonb_build_object(
    'version', 1,
    'periodo', p_periodo,
    'hasta_exclusivo', (p_periodo + interval '1 month')::date,
    'generado_en', now(),
    'totales', jsonb_build_object(
      'contratos', (select count(*)::integer from base),
      'capital_pen', coalesce((
        select sum(b.capital) from base b where b.moneda = 'PEN'
      ), 0),
      'capital_usd', coalesce((
        select sum(b.capital) from base b where b.moneda = 'USD'
      ), 0)
    ),
    'por_categoria', coalesce((
      select jsonb_agg(jsonb_build_object(
        'categoria', pc.categoria,
        'moneda', pc.moneda,
        'contratos', pc.contratos,
        'capital', pc.capital
      ) order by pc.categoria, pc.moneda)
      from por_categoria pc
    ), '[]'::jsonb),
    'contratos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id,
        'numero_contrato', b.numero_contrato,
        'cliente_id', b.cliente_id,
        'fecha_cierre_comercial', b.fecha_cierre_comercial,
        'fuente_cierre_comercial', b.fuente_cierre_comercial,
        'fecha_registro', b.creado_en,
        'fecha_inicio', b.fecha_inicio,
        'categoria', b.categoria,
        'moneda', b.moneda,
        'capital', b.capital,
        'estado', b.estado
      ) order by b.fecha_cierre_comercial, b.creado_en, b.id)
      from base b
    ), '[]'::jsonb)
  ) into v_payload;

  return v_payload;
end;
$function$;

comment on function crm.contratos_por_periodo_comercial_fn(date) is
  'Lista y totales de contratos por fecha_cierre_comercial para cualquier mes, incluso sin metas. Lectura completa solo Gerencia o lector global.';

revoke all on function crm.contratos_por_periodo_comercial_fn(date)
  from public, anon, authenticated, service_role;
grant execute on function crm.contratos_por_periodo_comercial_fn(date)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Correccion controlada y auditada
-- ---------------------------------------------------------------------------
create or replace function crm.corregir_fecha_cierre_comercial(
  p_contrato_id uuid,
  p_fecha date,
  p_motivo text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_motivo text := nullif(btrim(p_motivo), '');
  v_hoy_lima date := (clock_timestamp() at time zone 'America/Lima')::date;
  v_contrato public.contratos%rowtype;
  v_periodo_anterior date;
  v_periodo_nuevo date;
  v_lock_primero date;
  v_lock_segundo date;
begin
  if v_uid is null or v_rol is distinct from 'gerencia' then
    raise exception 'Solo Gerencia puede corregir el cierre comercial'
      using errcode = '42501';
  end if;

  if p_contrato_id is null then
    raise exception 'El contrato es obligatorio' using errcode = '22023';
  end if;
  if p_fecha is null or not isfinite(p_fecha) or p_fecha > v_hoy_lima then
    raise exception 'La fecha de cierre comercial es invalida o futura'
      using errcode = '22023';
  end if;
  if v_motivo is null or length(v_motivo) < 5 or length(v_motivo) > 300 then
    raise exception 'El motivo debe tener entre 5 y 300 caracteres'
      using errcode = '22023';
  end if;

  select c.* into v_contrato
  from public.contratos c
  where c.id = p_contrato_id
  for update;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;

  if v_contrato.fecha_cierre_comercial = p_fecha then
    return jsonb_build_object(
      'ok', true,
      'cambio', false,
      'contrato_id', p_contrato_id,
      'fecha_cierre_comercial', p_fecha
    );
  end if;

  v_periodo_anterior := date_trunc(
    'month', v_contrato.fecha_cierre_comercial
  )::date;
  v_periodo_nuevo := date_trunc('month', p_fecha)::date;
  v_lock_primero := least(v_periodo_anterior, v_periodo_nuevo);
  v_lock_segundo := greatest(v_periodo_anterior, v_periodo_nuevo);

  -- Mismas llaves del sello mensual, siempre en orden para no crear deadlocks.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (v_lock_primero - date '2000-01-01')::integer
  );
  if v_lock_segundo is distinct from v_lock_primero then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('crm.periodos_cerrados'),
      (v_lock_segundo - date '2000-01-01')::integer
    );
  end if;

  if exists (
    select 1 from crm.periodos_cerrados pc
    where pc.periodo in (v_periodo_anterior, v_periodo_nuevo)
  ) then
    raise exception 'No se puede reescribir un mes comercial sellado'
      using errcode = 'P0409',
            hint = 'La correccion debe hacerse antes del sello mensual.';
  end if;

  perform pg_catalog.set_config(
    'crm.correccion_periodo_comercial', 'on', true
  );
  update public.contratos c
     set fecha_cierre_comercial = p_fecha,
         fuente_cierre_comercial = 'correccion_manual'
   where c.id = p_contrato_id;
  perform pg_catalog.set_config(
    'crm.correccion_periodo_comercial', 'off', true
  );

  -- El trigger general conserva la fila completa. Esta segunda entrada agrega
  -- el motivo de negocio que audit_log no tiene como columna propia.
  insert into public.audit_log (
    tabla, operacion, fila_id, usuario_id, data_antes, data_despues
  ) values (
    'contratos.fecha_cierre_comercial',
    'UPDATE',
    p_contrato_id::text,
    v_uid,
    jsonb_build_object(
      'fecha_cierre_comercial', v_contrato.fecha_cierre_comercial,
      'fuente', v_contrato.fuente_cierre_comercial
    ),
    jsonb_build_object(
      'fecha_cierre_comercial', p_fecha,
      'fuente', 'correccion_manual',
      'motivo', v_motivo
    )
  );

  return jsonb_build_object(
    'ok', true,
    'cambio', true,
    'contrato_id', p_contrato_id,
    'fecha_anterior', v_contrato.fecha_cierre_comercial,
    'fecha_cierre_comercial', p_fecha
  );
end;
$function$;

comment on function crm.corregir_fecha_cierre_comercial(uuid, date, text) is
  'Corrige el periodo comercial de un contrato antes del sello mensual. Solo Gerencia, motivo obligatorio y auditoria antes/despues.';

revoke all on function crm.corregir_fecha_cierre_comercial(uuid, date, text)
  from public, anon, authenticated, service_role;
grant execute on function crm.corregir_fecha_cierre_comercial(uuid, date, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Postflight estructural
-- ---------------------------------------------------------------------------
do $postflight$
begin
  if exists (
    select 1 from public.contratos c
    where c.fecha_cierre_comercial is null
       or not isfinite(c.fecha_cierre_comercial)
  ) then
    raise exception 'El backfill dejo fechas comerciales invalidas';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_indexes i
    where i.schemaname = 'public'
      and i.tablename = 'contratos'
      and i.indexname = 'idx_contratos_fecha_cierre_comercial'
  ) then
    raise exception 'Falta el indice de fecha_cierre_comercial';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger t
    where t.tgrelid = 'public.contratos'::regclass
      and t.tgname = 'trg_definir_periodo_comercial_contrato'
      and not t.tgisinternal
      and t.tgenabled <> 'D'
  ) then
    raise exception 'Falta el trigger de altas del periodo comercial';
  end if;

  if position(
       'c.fecha_cierre_comercial >= (p_ini AT TIME ZONE ''America/Lima''::text)::date'
       in pg_catalog.pg_get_functiondef(
         'private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)'::regprocedure
       )
     ) = 0 then
    -- pg_get_functiondef normaliza casts y mayusculas; el chequeo semantico de
    -- abajo cubre variantes de impresion sin depender de su formato exacto.
    if pg_catalog.pg_get_functiondef(
         'private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)'::regprocedure
       ) not ilike '%c.fecha_cierre_comercial%' then
      raise exception 'produccion_mes_por_vendedor no usa fecha_cierre_comercial';
    end if;
  end if;

  if to_regprocedure('crm.contratos_por_periodo_comercial_fn(date)') is null
     or to_regprocedure(
       'crm.corregir_fecha_cierre_comercial(uuid,date,text)'
     ) is null then
    raise exception 'Faltan las RPC del periodo comercial';
  end if;
end;
$postflight$;

commit;

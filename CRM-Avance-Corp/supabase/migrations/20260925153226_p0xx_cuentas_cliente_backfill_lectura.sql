-- P-0XX / S1: cuentas versionadas como fuente de lectura y conciliacion.
-- En la rama se prueba con datos sustituidos. Al fusionar, la migracion se
-- ejecutaria sobre datos reales; las excepciones se conservan para operaciones.
-- El lote no se atribuye a una persona: creado_por/usuario_id quedan NULL y
-- private.backfill_cuentas_p0xx identifica cada fila como migracion P-0XX.
begin;
set local lock_timeout = '10s';
-- Un alta concurrente no puede crear otra candidata entre el censo y el
-- enlace historico. Las lecturas ordinarias siguen permitidas.
lock table crm.cuentas_bancarias in share row exclusive mode;

-- El audit log es append-only. Desde este punto, sus filas bancarias nuevas
-- conservan ids, estado y procedencia, pero no duplican numero, CCI ni DNI del
-- beneficiario. Los registros historicos previos no se modifican.
create or replace function private.log_audit_crm()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_fila uuid;
  v_actor uuid;
  v_antes jsonb;
  v_despues jsonb;
begin
  begin
    v_fila := coalesce(
      (pg_catalog.to_jsonb(coalesce(new, old)) ->> 'id')::uuid,
      (pg_catalog.to_jsonb(coalesce(new, old)) ->> 'perfil_id')::uuid
    );
  exception when invalid_text_representation then
    v_fila := null;
  end;

  select p.id into v_actor
  from public.perfiles p where p.id = (select auth.uid());

  if tg_op in ('UPDATE', 'DELETE') then
    v_antes := pg_catalog.to_jsonb(old);
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    v_despues := pg_catalog.to_jsonb(new);
  end if;
  if tg_table_schema = 'crm' and tg_table_name = 'cuentas_bancarias' then
    v_antes := v_antes - array['numero_cuenta', 'cci', 'beneficiario_dni'];
    v_despues := v_despues - array['numero_cuenta', 'cci', 'beneficiario_dni'];
  end if;

  insert into public.audit_log
    (tabla, operacion, fila_id, usuario_id, data_antes, data_despues)
  values
    (tg_table_schema || '.' || tg_table_name, tg_op, v_fila, v_actor,
     v_antes, v_despues);
  return coalesce(new, old);
end;
$function$;

-- Excepcion acotada al limite public: su trigger historico audita TODA la
-- fila de perfiles incluso cuando cambia un dato de contacto. Las columnas
-- bancarias legacy permanecen en la tabla, pero sus futuras imagenes de
-- auditoria no deben volver a copiar numeros/CCI. Otros objetos conservan la
-- forma previa de su auditoria.
create or replace function public.log_audit_change()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_user_id uuid;
  v_fila_id text;
  v_antes jsonb;
  v_despues jsonb;
  v_claves_modificadas text[];
  v_claves_bancarias text[] := array[
    'banco', 'tipo_cuenta', 'numero_cuenta', 'cci',
    'titular_distinto', 'beneficiario_nombre', 'beneficiario_dni',
    'banco_usd', 'tipo_cuenta_usd', 'numero_cuenta_usd', 'cci_usd',
    'titular_distinto_usd', 'beneficiario_nombre_usd', 'beneficiario_dni_usd'];
begin
  v_user_id := auth.uid();
  if tg_op in ('UPDATE', 'DELETE') then
    v_fila_id := old.id::text;
    v_antes := pg_catalog.to_jsonb(old);
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    v_fila_id := new.id::text;
    v_despues := pg_catalog.to_jsonb(new);
  end if;
  if tg_table_schema = 'public' and tg_table_name = 'perfiles' then
    if tg_op = 'UPDATE' then
      select pg_catalog.array_agg(k order by k) into v_claves_modificadas
      from pg_catalog.unnest(v_claves_bancarias) as x(k)
      where v_antes -> k is distinct from v_despues -> k;
    end if;
    v_antes := v_antes - v_claves_bancarias;
    v_despues := v_despues - v_claves_bancarias;
    if v_claves_modificadas is not null then
      v_despues := v_despues || pg_catalog.jsonb_build_object(
        '_audit_campos_bancarios_modificados', v_claves_modificadas);
    end if;
  end if;
  insert into public.audit_log
    (tabla, operacion, fila_id, usuario_id, data_antes, data_despues)
  values
    (tg_table_name, tg_op, v_fila_id, v_user_id, v_antes, v_despues);
  return coalesce(new, old);
end;
$function$;

-- La misma normalizacion y validacion se usara en S2 por el alta de contrato
-- (modos nueva/perfil) y por registrar_cuenta_cliente.
create or replace function private.validar_cuenta_bancaria(p_cuenta jsonb)
returns jsonb
language plpgsql
immutable security definer
set search_path to ''
as $function$
declare
  v_banco text;
  v_tipo text;
  v_numero text;
  v_cci text;
  v_titular_distinto boolean;
  v_beneficiario_nombre text;
  v_beneficiario_dni text;
begin
  if p_cuenta is null or pg_catalog.jsonb_typeof(p_cuenta) <> 'object' then
    raise exception using errcode = '22023', message = 'Datos bancarios invalidos';
  end if;
  v_banco := pg_catalog.btrim(coalesce(p_cuenta->>'banco', ''));
  v_tipo := pg_catalog.lower(pg_catalog.btrim(coalesce(p_cuenta->>'tipo_cuenta', '')));
  v_numero := pg_catalog.upper(pg_catalog.btrim(coalesce(p_cuenta->>'numero_cuenta', '')));
  v_cci := pg_catalog.btrim(coalesce(p_cuenta->>'cci', ''));
  begin
    v_titular_distinto := coalesce((p_cuenta->>'titular_distinto')::boolean, false);
  exception when invalid_text_representation then
    raise exception using errcode = '22023', message = 'Indicador de beneficiario invalido';
  end;
  if v_titular_distinto then
    v_beneficiario_nombre := pg_catalog.upper(pg_catalog.regexp_replace(
      pg_catalog.btrim(coalesce(p_cuenta->>'beneficiario_nombre', '')), '\s+', ' ', 'g'));
    v_beneficiario_dni := pg_catalog.btrim(coalesce(p_cuenta->>'beneficiario_dni', ''));
  end if;

  if pg_catalog.length(v_banco) not between 1 and 100 then
    raise exception using errcode = '22023', message = 'Selecciona el banco de la cuenta';
  end if;
  if v_tipo not in ('ahorros', 'corriente') then
    raise exception using errcode = '22023', message = 'Selecciona un tipo de cuenta valido';
  end if;
  if v_numero !~ '^[A-Za-z0-9-]{1,30}$' then
    raise exception using errcode = '22023', message = 'El numero de cuenta solo puede contener letras, numeros y guiones';
  end if;
  if v_cci !~ '^[0-9]{20}$' then
    raise exception using errcode = '22023', message = 'El CCI debe tener exactamente 20 digitos';
  end if;
  if v_titular_distinto and (
    pg_catalog.length(v_beneficiario_nombre) not between 1 and 200
    or v_beneficiario_dni !~ '^[0-9]{8,12}$'
  ) then
    raise exception using errcode = '22023', message = 'Completa correctamente los datos del beneficiario';
  end if;

  return pg_catalog.jsonb_build_object(
    'banco', v_banco, 'tipo_cuenta', v_tipo, 'numero_cuenta', v_numero,
    'cci', v_cci, 'titular_distinto', v_titular_distinto,
    'beneficiario_nombre', v_beneficiario_nombre,
    'beneficiario_dni', v_beneficiario_dni);
end;
$function$;
revoke all on function private.validar_cuenta_bancaria(jsonb) from public, anon, authenticated;

create table if not exists private.backfill_cuentas_p0xx (
  tipo text not null check (tipo in ('cuenta', 'vinculo')),
  fila_id uuid not null,
  cliente_id uuid not null,
  contrato_id uuid,
  marca_actor text not null default 'migracion:p0xx:s1',
  insertada_en timestamptz not null default pg_catalog.now(),
  revertida_en timestamptz,
  primary key (tipo, fila_id),
  check ((tipo = 'cuenta' and contrato_id is null)
      or (tipo = 'vinculo' and contrato_id is not null))
);
alter table private.backfill_cuentas_p0xx enable row level security;
revoke all on private.backfill_cuentas_p0xx from public, anon, authenticated;
-- Denegacion explicita: evita exposicion accidental y no deja RLS sin policy.
do $policy$
begin
  if not exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'private' and tablename = 'backfill_cuentas_p0xx'
      and policyname = 'p0xx_solo_interno'
  ) then
    create policy p0xx_solo_interno on private.backfill_cuentas_p0xx
      as restrictive for all to public using (false) with check (false);
  end if;
end;
$policy$;

create table if not exists private.conciliacion_cuentas_p0xx (
  id bigint generated always as identity primary key,
  clase text not null check (clase in ('perfil', 'contrato')),
  cliente_id uuid not null,
  moneda text not null check (moneda in ('PEN', 'USD')),
  contrato_id uuid,
  motivo text not null check (motivo in (
    'perfil_invalido', 'mismo_cci_datos_distintos', 'varias_activas',
    'sin_cuenta', 'cuentas_ambiguas', 'perfil_conflictivo')),
  observado_en timestamptz not null default pg_catalog.now()
);
alter table private.conciliacion_cuentas_p0xx enable row level security;
revoke all on private.conciliacion_cuentas_p0xx from public, anon, authenticated;
do $policy$
begin
  if not exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'private' and tablename = 'conciliacion_cuentas_p0xx'
      and policyname = 'p0xx_solo_interno'
  ) then
    create policy p0xx_solo_interno on private.conciliacion_cuentas_p0xx
      as restrictive for all to public using (false) with check (false);
  end if;
end;
$policy$;

-- Una transaccion mantiene cuentas, vinculos y reporte atomicos. El candado
-- de tabla serializa toda escritura de cuentas durante el backfill; tomar
-- aqui tambien el advisory lock del alta contractual invertiría el orden de
-- candados y permitiria un deadlock. S2 usa el advisory lock en su RPC.
do $backfill$
declare
  v_cliente_id uuid;
  v_perfil public.perfiles%rowtype;
  v_moneda text;
  v_banco text;
  v_tipo text;
  v_numero text;
  v_cci text;
  v_titular boolean;
  v_beneficiario_nombre text;
  v_beneficiario_dni text;
  v_normalizada jsonb;
  v_actual crm.cuentas_bancarias%rowtype;
  v_cuenta_id uuid;
  v_contrato_id uuid;
  v_contrato public.contratos%rowtype;
  v_candidatas bigint;
  v_vinculo_id uuid;
begin
  delete from private.conciliacion_cuentas_p0xx;
  for v_cliente_id in
    select p.id from public.perfiles p where p.rol = 'cliente' order by p.id
  loop
    select p.* into v_perfil from public.perfiles p
    where p.id = v_cliente_id and p.rol = 'cliente' for share;
    if not found then continue; end if;

    foreach v_moneda in array array['PEN', 'USD'] loop
      if v_moneda = 'PEN' then
        v_banco := v_perfil.banco;
        v_tipo := v_perfil.tipo_cuenta;
        v_numero := v_perfil.numero_cuenta;
        v_cci := v_perfil.cci;
        v_titular := v_perfil.titular_distinto;
        v_beneficiario_nombre := v_perfil.beneficiario_nombre;
        v_beneficiario_dni := v_perfil.beneficiario_dni;
      else
        v_banco := v_perfil.banco_usd;
        v_tipo := v_perfil.tipo_cuenta_usd;
        v_numero := v_perfil.numero_cuenta_usd;
        v_cci := v_perfil.cci_usd;
        v_titular := v_perfil.titular_distinto_usd;
        v_beneficiario_nombre := v_perfil.beneficiario_nombre_usd;
        v_beneficiario_dni := v_perfil.beneficiario_dni_usd;
      end if;
      if v_banco is null and v_tipo is null and v_numero is null
         and v_cci is null and not coalesce(v_titular, false)
         and v_beneficiario_nombre is null and v_beneficiario_dni is null then
        continue;
      end if;

      -- Una cadena legacy con espacios en sus identificadores no se corrige
      -- automaticamente: operaciones debe confirmar el dato original.
      if coalesce(v_numero, '') ~ '[[:space:]]'
         or coalesce(v_cci, '') ~ '[[:space:]]'
         or (coalesce(v_titular, false)
             and coalesce(v_beneficiario_dni, '') ~ '[[:space:]]') then
        insert into private.conciliacion_cuentas_p0xx
          (clase, cliente_id, moneda, motivo)
        values ('perfil', v_cliente_id, v_moneda, 'perfil_invalido');
        continue;
      end if;

      begin
        v_normalizada := private.validar_cuenta_bancaria(pg_catalog.jsonb_build_object(
          'banco', v_banco, 'tipo_cuenta', v_tipo,
          'numero_cuenta', v_numero, 'cci', v_cci,
          'titular_distinto', coalesce(v_titular, false),
          'beneficiario_nombre', v_beneficiario_nombre,
          'beneficiario_dni', v_beneficiario_dni));
      exception when sqlstate '22023' then
        insert into private.conciliacion_cuentas_p0xx
          (clase, cliente_id, moneda, motivo)
        values ('perfil', v_cliente_id, v_moneda, 'perfil_invalido');
        continue;
      end;

      v_cci := v_normalizada->>'cci';
      select cb.* into v_actual from crm.cuentas_bancarias cb
      where cb.cliente_id = v_cliente_id and cb.moneda = v_moneda
        and cb.cci = v_cci and cb.activa is true
      for update;
      if found then
        if pg_catalog.lower(v_actual.banco) = pg_catalog.lower(v_normalizada->>'banco')
           and v_actual.tipo_cuenta = v_normalizada->>'tipo_cuenta'
           and v_actual.numero_cuenta = v_normalizada->>'numero_cuenta'
           and v_actual.titular_distinto = (v_normalizada->>'titular_distinto')::boolean
           and v_actual.beneficiario_nombre is not distinct from v_normalizada->>'beneficiario_nombre'
           and v_actual.beneficiario_dni is not distinct from v_normalizada->>'beneficiario_dni' then
          continue;
        end if;
        -- La unicidad activa por CCI impide insertar sin reemplazar una cuenta
        -- CRM potencialmente contractual. Esa decision es manual.
        insert into private.conciliacion_cuentas_p0xx
          (clase, cliente_id, moneda, motivo)
        values ('perfil', v_cliente_id, v_moneda, 'mismo_cci_datos_distintos');
        continue;
      end if;

      insert into crm.cuentas_bancarias
        (cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci,
         titular_distinto, beneficiario_nombre, beneficiario_dni,
         activa, origen, creado_por)
      values
        (v_cliente_id, v_moneda, v_normalizada->>'banco',
         v_normalizada->>'tipo_cuenta', v_normalizada->>'numero_cuenta', v_cci,
         (v_normalizada->>'titular_distinto')::boolean,
         v_normalizada->>'beneficiario_nombre', v_normalizada->>'beneficiario_dni',
         true, 'perfil', null)
      returning id into v_cuenta_id;
      insert into private.backfill_cuentas_p0xx
        (tipo, fila_id, cliente_id)
      values ('cuenta', v_cuenta_id, v_cliente_id);
    end loop;
  end loop;

  insert into private.conciliacion_cuentas_p0xx
    (clase, cliente_id, moneda, motivo)
  select 'perfil', cb.cliente_id, cb.moneda, 'varias_activas'
  from crm.cuentas_bancarias cb
  where cb.activa is true
  group by cb.cliente_id, cb.moneda
  having pg_catalog.count(distinct cb.cci) > 1
     and pg_catalog.bool_or(cb.origen = 'perfil');

  for v_contrato_id in
    select ct.id from public.contratos ct
    where not exists (
      select 1 from crm.contrato_cuentas_pago cp where cp.contrato_id = ct.id)
    order by ct.id
  loop
    select ct.* into v_contrato from public.contratos ct
    where ct.id = v_contrato_id for share;
    if not found or exists (
      select 1 from crm.contrato_cuentas_pago cp where cp.contrato_id = v_contrato_id
    ) then continue; end if;

    -- Una sola fila CRM no es inequivoca si el perfil trae una instruccion
    -- invalida o datos distintos para el mismo CCI. El caso va a operaciones.
    if exists (
      select 1 from private.conciliacion_cuentas_p0xx x
      where x.clase = 'perfil' and x.cliente_id = v_contrato.cliente_id
        and x.moneda = v_contrato.moneda
        and x.motivo in ('perfil_invalido', 'mismo_cci_datos_distintos')
    ) then
      insert into private.conciliacion_cuentas_p0xx
        (clase, cliente_id, moneda, contrato_id, motivo)
      values ('contrato', v_contrato.cliente_id, v_contrato.moneda,
              v_contrato.id, 'perfil_conflictivo');
      continue;
    end if;

    select pg_catalog.count(*), (pg_catalog.array_agg(cb.id))[1]
      into v_candidatas, v_cuenta_id
    from crm.cuentas_bancarias cb
    where cb.cliente_id = v_contrato.cliente_id
      and cb.moneda = v_contrato.moneda and cb.activa is true;
    if v_candidatas = 1 then
      -- El trigger de coherencia aborta toda la migracion si la pareja no vale.
      insert into crm.contrato_cuentas_pago
        (contrato_id, cuenta_bancaria_id, creado_por)
      values (v_contrato.id, v_cuenta_id, null)
      returning id into v_vinculo_id;
      insert into private.backfill_cuentas_p0xx
        (tipo, fila_id, cliente_id, contrato_id)
      values ('vinculo', v_vinculo_id, v_contrato.cliente_id, v_contrato.id);
    else
      insert into private.conciliacion_cuentas_p0xx
        (clase, cliente_id, moneda, contrato_id, motivo)
      values ('contrato', v_contrato.cliente_id, v_contrato.moneda,
              v_contrato.id,
              case when v_candidatas = 0 then 'sin_cuenta' else 'cuentas_ambiguas' end);
    end if;
  end loop;
end;
$backfill$;

-- Hecho bancario: solo filas activas. No decide autorizacion ni expone una
-- segunda copia desde public.perfiles.
create or replace function private.cuentas_cliente_vigentes(p_cliente_id uuid)
returns table (
  cuenta_id uuid, moneda text, banco text, tipo_cuenta text,
  numero_cuenta text, cci text, titular_distinto boolean,
  beneficiario_nombre text, beneficiario_dni text, origen text,
  creada_en timestamptz
)
language sql
stable security definer
set search_path to ''
as $function$
  select cb.id, cb.moneda, cb.banco, cb.tipo_cuenta,
         cb.numero_cuenta, cb.cci, cb.titular_distinto,
         cb.beneficiario_nombre, cb.beneficiario_dni, cb.origen,
         cb.creado_en
  from crm.cuentas_bancarias cb
  where cb.cliente_id = p_cliente_id and cb.activa is true
  order by cb.moneda, cb.creado_en desc, cb.id desc;
$function$;
revoke all on function private.cuentas_cliente_vigentes(uuid)
  from public, anon, authenticated;

-- Wrapper de autorizacion existente; conserva exactamente su firma y forma
-- de respuesta para el selector de cuentas del CRM.
create or replace function crm.cuentas_bancarias_cliente_fn(
  p_cliente_id uuid, p_moneda text)
returns table (
  cuenta_id uuid, moneda text, banco text, tipo_cuenta text,
  numero_cuenta text, cci text, titular_distinto boolean,
  beneficiario_nombre text, beneficiario_dni text, origen text,
  es_cuenta_perfil boolean, creada_en timestamptz
)
language plpgsql
stable security definer
set search_path to ''
as $function$
begin
  if p_moneda is null or p_moneda not in ('PEN', 'USD') then
    raise exception using errcode = '22023', message = 'Moneda bancaria invalida';
  end if;
  if not private.puede_gestionar_cuentas_cliente(p_cliente_id) then
    raise exception using errcode = '42501',
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  return query
  select c.cuenta_id, c.moneda, c.banco, c.tipo_cuenta,
         c.numero_cuenta, c.cci, c.titular_distinto,
         c.beneficiario_nombre, c.beneficiario_dni, c.origen,
         false, c.creada_en
  from private.cuentas_cliente_vigentes(p_cliente_id) c
  where c.moneda = p_moneda
  order by c.creada_en desc, c.cuenta_id desc;
end;
$function$;

-- Ficha: mismos parametros, columnas y permisos de identidad/contacto.
-- La visibilidad de banca responde al gate bancario, y el slot por moneda
-- representa la cuenta activa mas reciente para esa moneda.
create or replace function crm.cliente_detalle_fn(p_cliente_id uuid)
returns table (
  id uuid, nombre_completo text, nombres text, apellidos text,
  tipo_documento text, dni text, correo text, telefono text,
  domicilio text, asesor_perfil_id uuid, creado_por uuid,
  creado_en timestamptz, banca_visible boolean,
  cuentas_bancarias_visibles boolean, banco text, tipo_cuenta text,
  numero_cuenta text, cci text, titular_distinto boolean,
  beneficiario_nombre text, beneficiario_dni text,
  banco_usd text, tipo_cuenta_usd text, numero_cuenta_usd text,
  cci_usd text, titular_distinto_usd boolean,
  beneficiario_nombre_usd text, beneficiario_dni_usd text
)
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol_crm text := private.rol_crm(v_uid);
  v_cliente public.perfiles%rowtype;
  v_acceso_crudo boolean;
  v_acceso_crm boolean;
  v_banca_visible boolean;
begin
  if v_uid is null or p_cliente_id is null then
    return;
  end if;

  select p.* into v_cliente
  from public.perfiles p
  where p.id = p_cliente_id and p.rol = 'cliente';
  if not found then
    return;
  end if;

  v_acceso_crudo :=
    v_cliente.id = v_uid
    or (select public.es_gestor_cartera())
    or (
      (select private.es_analista_vigente())
      and (
        v_cliente.asesor_perfil_id = v_uid
        or (v_cliente.asesor_perfil_id is null and v_cliente.creado_por = v_uid)
      )
    )
    or v_rol_crm = 'gerencia';

  select exists (
    select 1 from private.cliente_ids_visibles_crm() v
    where v.cliente_id = v_cliente.id
  ) into v_acceso_crm;
  if not coalesce(v_acceso_crudo, false)
     and not coalesce(v_acceso_crm, false) then
    return;
  end if;

  v_banca_visible := coalesce(
    private.puede_gestionar_cuentas_cliente(v_cliente.id), false);

  return query
  select
    v_cliente.id, v_cliente.nombre_completo, v_cliente.nombres,
    v_cliente.apellidos, v_cliente.tipo_documento, v_cliente.dni,
    v_cliente.correo, v_cliente.telefono,
    case when private.es_lector_global() then null else v_cliente.domicilio end,
    v_cliente.asesor_perfil_id, v_cliente.creado_por, v_cliente.creado_en,
    v_banca_visible, v_banca_visible,
    case when v_banca_visible then pen.banco end,
    case when v_banca_visible then pen.tipo_cuenta end,
    case when v_banca_visible then pen.numero_cuenta end,
    case when v_banca_visible then pen.cci end,
    case when v_banca_visible then coalesce(pen.titular_distinto, false) else false end,
    case when v_banca_visible then pen.beneficiario_nombre end,
    case when v_banca_visible then pen.beneficiario_dni end,
    case when v_banca_visible then usd.banco end,
    case when v_banca_visible then usd.tipo_cuenta end,
    case when v_banca_visible then usd.numero_cuenta end,
    case when v_banca_visible then usd.cci end,
    case when v_banca_visible then coalesce(usd.titular_distinto, false) else false end,
    case when v_banca_visible then usd.beneficiario_nombre end,
    case when v_banca_visible then usd.beneficiario_dni end
  from (values (true)) as uno(x)
  left join lateral (
    select c.* from private.cuentas_cliente_vigentes(v_cliente.id) c
    where c.moneda = 'PEN' and v_banca_visible
    order by c.creada_en desc, c.cuenta_id desc limit 1
  ) pen on true
  left join lateral (
    select c.* from private.cuentas_cliente_vigentes(v_cliente.id) c
    where c.moneda = 'USD' and v_banca_visible
    order by c.creada_en desc, c.cuenta_id desc limit 1
  ) usd on true;
end;
$function$;
commit;

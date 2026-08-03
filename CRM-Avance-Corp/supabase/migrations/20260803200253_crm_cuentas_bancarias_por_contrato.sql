-- Cuentas bancarias reutilizables y cuenta de pago INMUTABLE por contrato.
--
-- Frontera de compatibilidad:
--   * NO altera ningun objeto de public (el portal sigue siendo su dueno).
--   * Las 14 columnas bancarias de public.perfiles siguen siendo el slot legacy.
--   * Al elegir ese slot para un contrato NUEVO, esta migracion lo copia a una
--     fila versionada de crm.cuentas_bancarias; los cambios posteriores del
--     perfil no mueven el destino historico del contrato.
--   * Los contratos anteriores a esta migracion no se enlazan por inferencia:
--     pagos conserva su fallback legacy hasta una conciliacion expresa.
--
-- No existe estado de verificacion. Una cuenta creada desde el contrato queda
-- activa y seleccionable en la misma transaccion. "activa" solo es ciclo de
-- vida (una version reemplazada deja de ofrecerse para contratos futuros).

set local lock_timeout = '10s';

-- ── 1) Ledger append-only de cuentas del cliente ────────────────────────────

create table crm.cuentas_bancarias (
  id                   uuid primary key default gen_random_uuid(),
  cliente_id           uuid not null references public.perfiles(id) on delete cascade,
  moneda               text not null
                       constraint cuentas_bancarias_moneda_valida
                       check (moneda in ('PEN', 'USD')),
  banco                text not null
                       constraint cuentas_bancarias_banco_valido
                       check (banco = btrim(banco) and length(banco) between 1 and 100),
  tipo_cuenta          text not null
                       constraint cuentas_bancarias_tipo_valido
                       check (tipo_cuenta in ('ahorros', 'corriente')),
  numero_cuenta        text not null
                       constraint cuentas_bancarias_numero_valido
                       check (numero_cuenta ~ '^[A-Za-z0-9-]{1,30}$'),
  cci                  text not null
                       constraint cuentas_bancarias_cci_valido
                       check (cci ~ '^[0-9]{20}$'),
  titular_distinto     boolean not null default false,
  beneficiario_nombre text,
  beneficiario_dni    text,
  activa               boolean not null default true,
  -- perfil = copia versionada del slot PEN/USD de public.perfiles;
  -- contrato = cuenta escrita inline al crear un contrato.
  origen               text not null
                       constraint cuentas_bancarias_origen_valido
                       check (origen in ('perfil', 'contrato')),
  creado_por           uuid references public.perfiles(id) on delete set null,
  creado_en            timestamptz not null default now(),
  desactivada_por      uuid references public.perfiles(id) on delete set null,
  desactivada_en       timestamptz,
  constraint cuentas_bancarias_beneficiario_coherente check (
    (
      titular_distinto = false
      and beneficiario_nombre is null
      and beneficiario_dni is null
    )
    or
    (
      titular_distinto = true
      and beneficiario_nombre is not null
      and beneficiario_nombre = btrim(beneficiario_nombre)
      and length(beneficiario_nombre) between 1 and 200
      and beneficiario_dni is not null
      and beneficiario_dni ~ '^[0-9]{8,12}$'
    )
  ),
  constraint cuentas_bancarias_desactivacion_coherente check (
    (activa = true and desactivada_por is null and desactivada_en is null)
    or
    (activa = false and desactivada_en is not null)
  )
);

alter table crm.cuentas_bancarias enable row level security;

comment on table crm.cuentas_bancarias is
  'Versiones reutilizables de cuentas bancarias del cliente. Sin verificacion: una cuenta nueva nace activa. Sus datos son inmutables; corregir crea otra version.';
comment on column crm.cuentas_bancarias.activa is
  'Ciclo de vida, no verificacion. False impide elegirla en contratos futuros; los contratos historicos conservan la referencia.';

-- Una sola version ACTIVA por CCI/cliente/moneda. Si el perfil conserva el CCI
-- pero cambia otro dato, la RPC desactiva la version anterior e inserta la nueva.
create unique index cuentas_bancarias_cci_activa_uidx
  on crm.cuentas_bancarias (cliente_id, moneda, cci)
  where activa = true;
-- FK ON DELETE CASCADE debe encontrar tambien las versiones INACTIVAS.
create index cuentas_bancarias_cliente_fk_idx
  on crm.cuentas_bancarias (cliente_id);
create index cuentas_bancarias_cliente_moneda_idx
  on crm.cuentas_bancarias (cliente_id, moneda, creado_en desc)
  where activa = true;
create index cuentas_bancarias_creado_por_idx
  on crm.cuentas_bancarias (creado_por)
  where creado_por is not null;
create index cuentas_bancarias_desactivada_por_idx
  on crm.cuentas_bancarias (desactivada_por)
  where desactivada_por is not null;

-- Los datos de una version nunca se corrigen in-place. Solo puede pasar de
-- activa a inactiva, con sello de actor/fecha; el pago historico sigue leyendo
-- la fila aunque ya no se ofrezca para un contrato nuevo.
create or replace function private.trg_cuentas_bancarias_version_inmutable()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if row(
    new.id, new.cliente_id, new.moneda, new.banco, new.tipo_cuenta,
    new.numero_cuenta, new.cci, new.titular_distinto,
    new.beneficiario_nombre, new.beneficiario_dni,
    new.origen, new.creado_en
  ) is distinct from row(
    old.id, old.cliente_id, old.moneda, old.banco, old.tipo_cuenta,
    old.numero_cuenta, old.cci, old.titular_distinto,
    old.beneficiario_nombre, old.beneficiario_dni,
    old.origen, old.creado_en
  ) then
    raise exception using
      errcode = '22023',
      message = 'Los datos de una cuenta bancaria son historicos; registra una cuenta nueva';
  end if;

  -- La unica excepcion de autoria es el SET NULL de su FK cuando el perfil
  -- autor fue eliminado. No es una correccion de negocio y evita que el trigger
  -- convierta el ON DELETE SET NULL declarado arriba en una promesa falsa.
  if new.creado_por is distinct from old.creado_por
     and not (
       new.creado_por is null
       and old.creado_por is not null
       and not exists (select 1 from public.perfiles p where p.id = old.creado_por)
     ) then
    raise exception using errcode = '22023', message = 'La autoria de la cuenta es inmutable';
  end if;

  if old.activa = false and new.activa = true then
    raise exception using
      errcode = '22023',
      message = 'Una version bancaria historica no se reactiva; registra una cuenta nueva';
  end if;

  if old.activa = true and new.activa = false then
    if new.desactivada_en is null then
      raise exception using errcode = '22023', message = 'Falta el sello de desactivacion de la cuenta';
    end if;
  elsif new.activa is distinct from old.activa
     or new.desactivada_en is distinct from old.desactivada_en then
    raise exception using errcode = '22023', message = 'Cambio de estado bancario invalido';
  elsif new.desactivada_por is distinct from old.desactivada_por
     and not (
       new.desactivada_por is null
       and old.desactivada_por is not null
       and not exists (select 1 from public.perfiles p where p.id = old.desactivada_por)
     ) then
    raise exception using errcode = '22023', message = 'La autoria de desactivacion es inmutable';
  end if;

  return new;
end;
$$;

create trigger trg_cuentas_bancarias_version_inmutable
  before update on crm.cuentas_bancarias
  for each row execute function private.trg_cuentas_bancarias_version_inmutable();

create trigger trg_audit_cuentas_bancarias
  after insert or delete or update on crm.cuentas_bancarias
  for each row execute function private.log_audit_crm();

-- ── 2) Enlace exacto contrato → cuenta ──────────────────────────────────────

create table crm.contrato_cuentas_pago (
  id                  uuid primary key default gen_random_uuid(),
  contrato_id         uuid not null unique
                      references public.contratos(id) on delete cascade,
  cuenta_bancaria_id  uuid not null
                      references crm.cuentas_bancarias(id) on delete restrict,
  creado_por          uuid references public.perfiles(id) on delete set null,
  creado_en           timestamptz not null default now()
);

alter table crm.contrato_cuentas_pago enable row level security;

comment on table crm.contrato_cuentas_pago is
  'Cuenta bancaria fija para todos los desembolsos del contrato (intereses, devoluciones y retorno de capital). Una fila por contrato.';

create index contrato_cuentas_pago_cuenta_idx
  on crm.contrato_cuentas_pago (cuenta_bancaria_id);
create index contrato_cuentas_pago_creado_por_idx
  on crm.contrato_cuentas_pago (creado_por)
  where creado_por is not null;

create or replace function private.trg_contrato_cuenta_pago_inmutable()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if row(new.id, new.contrato_id, new.cuenta_bancaria_id, new.creado_en)
     is distinct from
     row(old.id, old.contrato_id, old.cuenta_bancaria_id, old.creado_en) then
    raise exception using
      errcode = '22023',
      message = 'La cuenta de pago del contrato es historica y no se reemplaza';
  end if;
  if new.creado_por is distinct from old.creado_por
     and not (
       new.creado_por is null
       and old.creado_por is not null
       and not exists (select 1 from public.perfiles p where p.id = old.creado_por)
     ) then
    raise exception using errcode = '22023', message = 'La autoria del enlace bancario es inmutable';
  end if;
  return new;
end;
$$;

create trigger trg_contrato_cuenta_pago_00_inmutable
  before update on crm.contrato_cuentas_pago
  for each row execute function private.trg_contrato_cuenta_pago_inmutable();

-- Defensa estructural aun frente a una escritura privilegiada: la cuenta debe
-- pertenecer al MISMO cliente y moneda del contrato. El cliente API no tiene
-- grants directos sobre esta tabla; la insercion normal va por la RPC atomica.
create or replace function private.trg_contrato_cuenta_pago_coherente()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.contratos ct
    join crm.cuentas_bancarias cb
      on cb.id = new.cuenta_bancaria_id
     and cb.cliente_id = ct.cliente_id
     and cb.moneda = ct.moneda
    where ct.id = new.contrato_id
  ) then
    raise exception using
      errcode = '23514',
      message = 'La cuenta bancaria no pertenece al cliente o a la moneda del contrato';
  end if;
  return new;
end;
$$;

create trigger trg_contrato_cuenta_pago_coherente
  before insert or update on crm.contrato_cuentas_pago
  for each row execute function private.trg_contrato_cuenta_pago_coherente();

create trigger trg_audit_contrato_cuentas_pago
  after insert or delete or update on crm.contrato_cuentas_pago
  for each row execute function private.log_audit_crm();

-- ── 3) Autorizacion comun (misma cartera que public.crear_contrato) ─────────

create or replace function private.puede_gestionar_cuentas_cliente(p_cliente_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.perfiles cli
      where cli.id = p_cliente_id
        and cli.rol = 'cliente'
        and cli.activo = true
        and (
          (select public.es_admin())
          or (
            (select public.es_analista())
            and (
              cli.asesor_perfil_id = (select auth.uid())
              or (cli.asesor_perfil_id is null and cli.creado_por = (select auth.uid()))
            )
          )
        )
    );
$$;

-- ── 4) Listado de cuentas elegibles para un contrato nuevo ─────────────────

create or replace function crm.cuentas_bancarias_cliente_fn(
  p_cliente_id uuid,
  p_moneda text
) returns table (
  cuenta_id uuid,
  moneda text,
  banco text,
  tipo_cuenta text,
  numero_cuenta text,
  cci text,
  titular_distinto boolean,
  beneficiario_nombre text,
  beneficiario_dni text,
  origen text,
  es_cuenta_perfil boolean,
  creada_en timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_moneda is null or p_moneda not in ('PEN', 'USD') then
    raise exception using errcode = '22023', message = 'Moneda bancaria invalida';
  end if;
  if not private.puede_gestionar_cuentas_cliente(p_cliente_id) then
    raise exception using errcode = '42501', message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  return query
  with perfil_actual as (
    select
      null::uuid as cuenta_id,
      p_moneda as moneda,
      btrim(case when p_moneda = 'USD' then p.banco_usd else p.banco end) as banco,
      lower(btrim(case when p_moneda = 'USD' then p.tipo_cuenta_usd else p.tipo_cuenta end)) as tipo_cuenta,
      upper(btrim(case when p_moneda = 'USD' then p.numero_cuenta_usd else p.numero_cuenta end)) as numero_cuenta,
      btrim(case when p_moneda = 'USD' then p.cci_usd else p.cci end) as cci,
      case when p_moneda = 'USD' then p.titular_distinto_usd else p.titular_distinto end as titular_distinto,
      case
        when (case when p_moneda = 'USD' then p.titular_distinto_usd else p.titular_distinto end)
        then upper(regexp_replace(btrim(case when p_moneda = 'USD' then p.beneficiario_nombre_usd else p.beneficiario_nombre end), '\s+', ' ', 'g'))
        else null
      end as beneficiario_nombre,
      case
        when (case when p_moneda = 'USD' then p.titular_distinto_usd else p.titular_distinto end)
        then btrim(case when p_moneda = 'USD' then p.beneficiario_dni_usd else p.beneficiario_dni end)
        else null
      end as beneficiario_dni
    from public.perfiles p
    where p.id = p_cliente_id
  ),
  perfil_valido as (
    select pa.*
    from perfil_actual pa
    where length(pa.banco) between 1 and 100
      and pa.tipo_cuenta in ('ahorros', 'corriente')
      and pa.numero_cuenta ~ '^[A-Za-z0-9-]{1,30}$'
      and pa.cci ~ '^[0-9]{20}$'
      and (
        pa.titular_distinto = false
        or (
          pa.beneficiario_nombre is not null
          and length(pa.beneficiario_nombre) between 1 and 200
          and pa.beneficiario_dni ~ '^[0-9]{8,12}$'
        )
      )
  ),
  seleccionables as (
    select
      cb.id as cuenta_id,
      cb.moneda,
      cb.banco,
      cb.tipo_cuenta,
      cb.numero_cuenta,
      cb.cci,
      cb.titular_distinto,
      cb.beneficiario_nombre,
      cb.beneficiario_dni,
      cb.origen,
      false as es_cuenta_perfil,
      cb.creado_en as creada_en
    from crm.cuentas_bancarias cb
    where cb.cliente_id = p_cliente_id
      and cb.moneda = p_moneda
      and cb.activa = true

    union all

    select
      pv.cuenta_id,
      pv.moneda,
      pv.banco,
      pv.tipo_cuenta,
      pv.numero_cuenta,
      pv.cci,
      pv.titular_distinto,
      pv.beneficiario_nombre,
      pv.beneficiario_dni,
      'perfil'::text as origen,
      true as es_cuenta_perfil,
      null::timestamptz as creada_en
    from perfil_valido pv
    where not exists (
      select 1
      from crm.cuentas_bancarias cb
      where cb.cliente_id = p_cliente_id
        and cb.moneda = p_moneda
        and cb.activa = true
        and lower(cb.banco) = lower(pv.banco)
        and cb.tipo_cuenta = pv.tipo_cuenta
        and cb.numero_cuenta = pv.numero_cuenta
        and cb.cci = pv.cci
        and cb.titular_distinto = pv.titular_distinto
        and cb.beneficiario_nombre is not distinct from pv.beneficiario_nombre
        and cb.beneficiario_dni is not distinct from pv.beneficiario_dni
    )
  )
  select s.cuenta_id, s.moneda, s.banco, s.tipo_cuenta, s.numero_cuenta, s.cci,
         s.titular_distinto, s.beneficiario_nombre, s.beneficiario_dni,
         s.origen, s.es_cuenta_perfil, s.creada_en
  from seleccionables s
  order by s.es_cuenta_perfil desc, s.creada_en desc nulls last, s.cuenta_id;
end;
$$;

-- ── 5) Alta atomica: cuenta existente/perfil/nueva + contrato + cronograma ──

create or replace function crm.crear_contrato_con_cuenta(
  p_contrato jsonb,
  p_cronograma jsonb,
  p_cuenta jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid                  uuid := (select auth.uid());
  v_cliente_id           uuid;
  v_moneda               text;
  v_tipo_seleccion       text;
  v_cuenta_id            uuid;
  v_cuenta_activa        crm.cuentas_bancarias%rowtype;
  v_banco                text;
  v_tipo_cuenta          text;
  v_numero_cuenta        text;
  v_cci                  text;
  v_titular_distinto     boolean := false;
  v_beneficiario_nombre  text;
  v_beneficiario_dni     text;
  v_cuenta_esperada      jsonb;
  v_origen               text;
  v_resultado            jsonb;
  v_contrato_id          uuid;
begin
  if p_contrato is null or jsonb_typeof(p_contrato) <> 'object' then
    raise exception using errcode = '22023', message = 'Faltan los datos del contrato';
  end if;
  if p_cuenta is null or jsonb_typeof(p_cuenta) <> 'object' then
    raise exception using errcode = '22023', message = 'Selecciona la cuenta para el pago de intereses';
  end if;

  begin
    v_cliente_id := (p_contrato->>'cliente_id')::uuid;
  exception when invalid_text_representation then
    raise exception using errcode = '22023', message = 'Cliente invalido';
  end;
  v_moneda := upper(btrim(coalesce(p_contrato->>'moneda', '')));
  if v_moneda not in ('PEN', 'USD') then
    raise exception using errcode = '22023', message = 'Moneda del contrato invalida';
  end if;
  if v_uid is null or not private.puede_gestionar_cuentas_cliente(v_cliente_id) then
    raise exception using errcode = '42501', message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  v_tipo_seleccion := lower(btrim(coalesce(p_cuenta->>'tipo', '')));

  if v_tipo_seleccion = 'existente' then
    begin
      v_cuenta_id := (p_cuenta->>'cuenta_id')::uuid;
    exception when invalid_text_representation then
      raise exception using errcode = '22023', message = 'Cuenta bancaria invalida';
    end;

    select cb.* into v_cuenta_activa
    from crm.cuentas_bancarias cb
    where cb.id = v_cuenta_id
      and cb.cliente_id = v_cliente_id
      and cb.moneda = v_moneda
      and cb.activa = true
    for share;
    if not found then
      raise exception using
        errcode = '22023',
        message = 'La cuenta bancaria no esta disponible para este cliente y moneda';
    end if;

  elsif v_tipo_seleccion in ('perfil', 'nueva') then
    if v_tipo_seleccion = 'perfil' then
      select
        btrim(case when v_moneda = 'USD' then p.banco_usd else p.banco end),
        lower(btrim(case when v_moneda = 'USD' then p.tipo_cuenta_usd else p.tipo_cuenta end)),
        upper(btrim(case when v_moneda = 'USD' then p.numero_cuenta_usd else p.numero_cuenta end)),
        btrim(case when v_moneda = 'USD' then p.cci_usd else p.cci end),
        case when v_moneda = 'USD' then p.titular_distinto_usd else p.titular_distinto end,
        case when v_moneda = 'USD' then p.beneficiario_nombre_usd else p.beneficiario_nombre end,
        case when v_moneda = 'USD' then p.beneficiario_dni_usd else p.beneficiario_dni end
      into v_banco, v_tipo_cuenta, v_numero_cuenta, v_cci,
           v_titular_distinto, v_beneficiario_nombre, v_beneficiario_dni
      from public.perfiles p
      where p.id = v_cliente_id
      -- La fotografia del perfil debe seguir siendo cierta hasta que termine
      -- el alta. Sin este lock, un UPDATE concurrente podia confirmar despues
      -- del SELECT y antes de crear el vinculo contractual.
      for share;
      v_origen := 'perfil';
    else
      v_banco := btrim(coalesce(p_cuenta->>'banco', ''));
      v_tipo_cuenta := lower(btrim(coalesce(p_cuenta->>'tipo_cuenta', '')));
      v_numero_cuenta := upper(btrim(coalesce(p_cuenta->>'numero_cuenta', '')));
      v_cci := btrim(coalesce(p_cuenta->>'cci', ''));
      begin
        v_titular_distinto := coalesce((p_cuenta->>'titular_distinto')::boolean, false);
      exception when invalid_text_representation then
        raise exception using errcode = '22023', message = 'Indicador de beneficiario invalido';
      end;
      v_beneficiario_nombre := p_cuenta->>'beneficiario_nombre';
      v_beneficiario_dni := p_cuenta->>'beneficiario_dni';
      v_origen := 'contrato';
    end if;

    v_banco := btrim(coalesce(v_banco, ''));
    v_tipo_cuenta := lower(btrim(coalesce(v_tipo_cuenta, '')));
    v_numero_cuenta := upper(btrim(coalesce(v_numero_cuenta, '')));
    v_cci := btrim(coalesce(v_cci, ''));
    if v_titular_distinto then
      v_beneficiario_nombre := upper(regexp_replace(btrim(coalesce(v_beneficiario_nombre, '')), '\s+', ' ', 'g'));
      v_beneficiario_dni := btrim(coalesce(v_beneficiario_dni, ''));
    else
      v_beneficiario_nombre := null;
      v_beneficiario_dni := null;
    end if;

    if v_tipo_seleccion = 'perfil' then
      v_cuenta_esperada := jsonb_build_object(
        'banco', v_banco,
        'tipo_cuenta', v_tipo_cuenta,
        'numero_cuenta', v_numero_cuenta,
        'cci', v_cci,
        'titular_distinto', v_titular_distinto,
        'beneficiario_nombre', v_beneficiario_nombre,
        'beneficiario_dni', v_beneficiario_dni
      );
      if jsonb_typeof(p_cuenta->'cuenta_esperada') is distinct from 'object'
         or (p_cuenta->'cuenta_esperada') is distinct from v_cuenta_esperada then
        raise exception using
          errcode = 'P0001',
          message = 'La cuenta actual del cliente cambio. Recarga las cuentas y vuelve a seleccionarla';
      end if;
    end if;

    if length(v_banco) not between 1 and 100 then
      raise exception using errcode = '22023', message = 'Selecciona el banco de la cuenta';
    end if;
    if v_tipo_cuenta not in ('ahorros', 'corriente') then
      raise exception using errcode = '22023', message = 'Selecciona un tipo de cuenta valido';
    end if;
    if v_numero_cuenta !~ '^[A-Za-z0-9-]{1,30}$' then
      raise exception using errcode = '22023', message = 'El numero de cuenta solo puede contener letras, numeros y guiones';
    end if;
    if v_cci !~ '^[0-9]{20}$' then
      raise exception using errcode = '22023', message = 'El CCI debe tener exactamente 20 digitos';
    end if;
    if v_titular_distinto and (
      length(v_beneficiario_nombre) not between 1 and 200
      or v_beneficiario_dni !~ '^[0-9]{8,12}$'
    ) then
      raise exception using errcode = '22023', message = 'Completa correctamente los datos del beneficiario';
    end if;

    -- Serializa dos altas simultaneas del mismo CCI sin bloquear otras cuentas.
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(v_cliente_id::text || '|' || v_moneda || '|' || v_cci, 0)
    );

    select cb.* into v_cuenta_activa
    from crm.cuentas_bancarias cb
    where cb.cliente_id = v_cliente_id
      and cb.moneda = v_moneda
      and cb.cci = v_cci
      and cb.activa = true
    for update;

    if found
       and lower(v_cuenta_activa.banco) = lower(v_banco)
       and v_cuenta_activa.tipo_cuenta = v_tipo_cuenta
       and v_cuenta_activa.numero_cuenta = v_numero_cuenta
       and v_cuenta_activa.titular_distinto = v_titular_distinto
       and v_cuenta_activa.beneficiario_nombre is not distinct from v_beneficiario_nombre
       and v_cuenta_activa.beneficiario_dni is not distinct from v_beneficiario_dni then
      v_cuenta_id := v_cuenta_activa.id;
    else
      if found then
        update crm.cuentas_bancarias
           set activa = false,
               desactivada_por = v_uid,
               desactivada_en = now()
         where id = v_cuenta_activa.id;
      end if;

      insert into crm.cuentas_bancarias (
        cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci,
        titular_distinto, beneficiario_nombre, beneficiario_dni,
        activa, origen, creado_por
      ) values (
        v_cliente_id, v_moneda, v_banco, v_tipo_cuenta, v_numero_cuenta, v_cci,
        v_titular_distinto, v_beneficiario_nombre, v_beneficiario_dni,
        true, v_origen, v_uid
      )
      returning id into v_cuenta_id;
    end if;
  else
    raise exception using
      errcode = '22023',
      message = 'Selecciona una cuenta existente o registra una cuenta nueva';
  end if;

  -- public.crear_contrato mantiene su validacion de rol/cartera, numeracion,
  -- contrato, cronograma y co-titulares. La llamada anidada participa de ESTA
  -- transaccion: si el enlace bancario falla, todo (incluida una cuenta nueva)
  -- se revierte.
  v_resultado := public.crear_contrato(p_contrato, p_cronograma);
  begin
    v_contrato_id := (v_resultado->>'id')::uuid;
  exception when invalid_text_representation then
    raise exception using errcode = 'P0001', message = 'El contrato no devolvio un identificador valido';
  end;
  if v_contrato_id is null then
    raise exception using errcode = 'P0001', message = 'El contrato no devolvio un identificador';
  end if;

  insert into crm.contrato_cuentas_pago (
    contrato_id, cuenta_bancaria_id, creado_por
  ) values (
    v_contrato_id, v_cuenta_id, v_uid
  );

  return v_resultado || jsonb_build_object('cuenta_bancaria_id', v_cuenta_id);
end;
$$;

-- ── 6) Correccion contractual sin romper la moneda de la cuenta fijada ──────

create or replace function crm.actualizar_contrato_con_cuenta(
  p_id uuid,
  p_contrato jsonb,
  p_cronograma jsonb
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cliente_id      uuid;
  v_cliente_cuenta  uuid;
  v_moneda_actual   text;
  v_moneda_cuenta   text;
  v_moneda_nueva    text;
begin
  if p_contrato is null or jsonb_typeof(p_contrato) <> 'object' then
    raise exception using errcode = '22023', message = 'Faltan los datos del contrato';
  end if;

  select ct.cliente_id, cb.cliente_id, ct.moneda, cb.moneda
    into v_cliente_id, v_cliente_cuenta, v_moneda_actual, v_moneda_cuenta
  from public.contratos ct
  join crm.contrato_cuentas_pago ccp on ccp.contrato_id = ct.id
  join crm.cuentas_bancarias cb on cb.id = ccp.cuenta_bancaria_id
  where ct.id = p_id;

  if found then
    if not private.puede_gestionar_cuentas_cliente(v_cliente_id) then
      raise exception using errcode = '42501', message = 'Contrato no encontrado o fuera de tu cartera';
    end if;
    if v_cliente_id is distinct from v_cliente_cuenta
       or v_moneda_actual is distinct from v_moneda_cuenta then
      raise exception using
        errcode = 'P0001',
        message = 'El contrato tiene una cuenta de pago con moneda inconsistente; requiere conciliacion';
    end if;
    v_moneda_nueva := upper(btrim(coalesce(p_contrato->>'moneda', v_moneda_actual)));
    if v_moneda_nueva is distinct from v_moneda_cuenta then
      raise exception using
        errcode = '22023',
        message = 'La moneda de un contrato con cuenta de pago fijada no se puede cambiar desde Corregir';
    end if;
  end if;

  -- Para contratos legacy sin enlace conserva exactamente el comportamiento
  -- vigente. En ambos casos public.actualizar_contrato mantiene la ventana de
  -- 5 h, autor/cartera y regeneracion segura del cronograma.
  perform public.actualizar_contrato(p_id, p_contrato, p_cronograma);
end;
$$;

-- ── 7) Lectura de cuentas contractuales para Pagos/Excel ───────────────────

create or replace function crm.cuentas_pago_contratos_fn(p_contrato_ids uuid[])
returns table (
  contrato_id uuid,
  cuenta_bancaria_id uuid,
  moneda text,
  banco text,
  tipo_cuenta text,
  numero_cuenta text,
  cci text,
  titular_distinto boolean,
  beneficiario_nombre text,
  beneficiario_dni text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (select public.es_admin()) then
    raise exception using errcode = '42501', message = 'No autorizado para consultar cuentas de pago';
  end if;
  if coalesce(cardinality(p_contrato_ids), 0) > 5000 then
    raise exception using errcode = '22023', message = 'Demasiados contratos en una sola consulta';
  end if;
  if coalesce(cardinality(p_contrato_ids), 0) = 0 then
    return;
  end if;

  -- Una edicion legacy/privilegiada de public.contratos no puede desviar el
  -- pago: si altero cliente o moneda despues del enlace, se bloquea la agenda
  -- completa y exige conciliacion en vez de caer al perfil silenciosamente.
  if exists (
    select 1
    from crm.contrato_cuentas_pago ccp
    join public.contratos ct on ct.id = ccp.contrato_id
    join crm.cuentas_bancarias cb on cb.id = ccp.cuenta_bancaria_id
    where ccp.contrato_id = any(p_contrato_ids)
      and (cb.cliente_id is distinct from ct.cliente_id or cb.moneda is distinct from ct.moneda)
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'Hay un contrato con cuenta de pago inconsistente; requiere conciliacion antes de pagar';
  end if;

  return query
  select
    ccp.contrato_id,
    cb.id as cuenta_bancaria_id,
    cb.moneda,
    cb.banco,
    cb.tipo_cuenta,
    cb.numero_cuenta,
    cb.cci,
    cb.titular_distinto,
    cb.beneficiario_nombre,
    cb.beneficiario_dni
  from crm.contrato_cuentas_pago ccp
  join crm.cuentas_bancarias cb on cb.id = ccp.cuenta_bancaria_id
  where ccp.contrato_id = any(p_contrato_ids);
end;
$$;

-- ── 8) Grants y hardening ──────────────────────────────────────────────────

-- Las tablas sensibles quedan deny-by-default para sesiones humanas. Toda
-- lectura/escritura pasa por una RPC con gate y payload recortado.
revoke all on table crm.cuentas_bancarias from public, anon, authenticated;
revoke all on table crm.contrato_cuentas_pago from public, anon, authenticated;
grant select, insert, update on crm.cuentas_bancarias to service_role;
grant select, insert on crm.contrato_cuentas_pago to service_role;

revoke all on function crm.cuentas_bancarias_cliente_fn(uuid, text) from public, anon;
grant execute on function crm.cuentas_bancarias_cliente_fn(uuid, text) to authenticated;

revoke all on function crm.crear_contrato_con_cuenta(jsonb, jsonb, jsonb) from public, anon;
grant execute on function crm.crear_contrato_con_cuenta(jsonb, jsonb, jsonb) to authenticated;

revoke all on function crm.cuentas_pago_contratos_fn(uuid[]) from public, anon;
grant execute on function crm.cuentas_pago_contratos_fn(uuid[]) to authenticated;

revoke all on function crm.actualizar_contrato_con_cuenta(uuid, jsonb, jsonb) from public, anon;
grant execute on function crm.actualizar_contrato_con_cuenta(uuid, jsonb, jsonb)
  to authenticated;

revoke all on function private.puede_gestionar_cuentas_cliente(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.trg_cuentas_bancarias_version_inmutable()
  from public, anon, authenticated, service_role;
revoke all on function private.trg_contrato_cuenta_pago_coherente()
  from public, anon, authenticated, service_role;
revoke all on function private.trg_contrato_cuenta_pago_inmutable()
  from public, anon, authenticated, service_role;

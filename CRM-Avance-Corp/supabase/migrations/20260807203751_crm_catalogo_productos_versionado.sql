-- Catálogo versionado de productos de inversión.
--
-- Invariantes:
--   * producto = identidad comercial estable; nunca se elimina;
--   * versión publicada/retirada = inmutable; un cambio crea otra versión;
--   * condición = combinación comercial normalizada y seleccionable;
--   * public.contratos conserva los términos legales pactados y referencia la
--     condición que les dio origen (snapshot por FK a filas inmutables);
--   * los contratos anteriores no se reclasifican: cada uno recibe una
--     versión legacy retirada con una copia exacta de sus términos actuales;
--   * las escrituras humanas pasan exclusivamente por RPC de Gerencia activa.

begin;

do $precondiciones$
begin
  if to_regclass('public.contratos') is null
     or to_regclass('public.perfiles') is null
     or to_regclass('crm.equipo') is null then
    raise exception
      'El catálogo requiere public.contratos, public.perfiles y crm.equipo';
  end if;
  if to_regprocedure('private.rol_crm(uuid)') is null
     or to_regprocedure('private.es_lector_global()') is null
     or to_regprocedure('private.log_audit_crm()') is null then
    raise exception
      'El catálogo requiere los helpers canónicos de autorización y auditoría CRM';
  end if;
end;
$precondiciones$;

create table crm.productos_inversion (
  id uuid primary key default gen_random_uuid(),
  codigo text not null,
  estado text not null default 'activo'
    check (estado in ('activo', 'archivado')),
  revision bigint not null default 1 check (revision > 0),
  es_legacy boolean not null default false,
  permite_altas_legacy boolean not null default false,
  creado_por uuid references public.perfiles(id) on delete set null,
  creado_en timestamptz not null default now(),
  actualizado_por uuid references public.perfiles(id) on delete set null,
  actualizado_en timestamptz not null default now(),
  archivado_por uuid references public.perfiles(id) on delete set null,
  archivado_en timestamptz,
  constraint productos_inversion_codigo_formato check (
    codigo = upper(btrim(codigo))
    and codigo ~ '^[A-Z0-9][A-Z0-9._-]{1,39}$'
  ),
  constraint productos_inversion_archivo_coherente check (
    (estado = 'activo' and archivado_en is null and archivado_por is null)
    or (estado = 'archivado' and archivado_en is not null)
  ),
  constraint productos_inversion_legacy_archivado check (
    not es_legacy or estado = 'archivado'
  ),
  constraint productos_inversion_compatibilidad_check check (
    not permite_altas_legacy or es_legacy
  )
);

create unique index productos_inversion_codigo_uk
  on crm.productos_inversion (lower(codigo));
create index productos_inversion_estado_idx
  on crm.productos_inversion (estado, codigo);
create index productos_inversion_creado_por_idx
  on crm.productos_inversion (creado_por) where creado_por is not null;
create index productos_inversion_actualizado_por_idx
  on crm.productos_inversion (actualizado_por) where actualizado_por is not null;
create index productos_inversion_archivado_por_idx
  on crm.productos_inversion (archivado_por) where archivado_por is not null;

comment on table crm.productos_inversion is
  'Identidad estable de un producto de inversión. Se archiva; nunca se borra ni se recicla su código.';
comment on column crm.productos_inversion.revision is
  'Control optimista del agregado producto para RPCs expected_revision.';
comment on column crm.productos_inversion.es_legacy is
  'Producto técnico ocultable usado únicamente para snapshots de contratos sin catálogo previo.';
comment on column crm.productos_inversion.permite_altas_legacy is
  'Puente temporal e irreversible: permite callers antiguos sin condición hasta que CRM y portal migren a los wrappers catalogados.';

create table crm.producto_versiones (
  id uuid primary key default gen_random_uuid(),
  producto_id uuid not null
    references crm.productos_inversion(id) on delete restrict,
  numero_version integer not null check (numero_version > 0),
  estado text not null default 'borrador'
    check (estado in ('borrador', 'publicada', 'retirada')),
  nombre text not null check (length(btrim(nombre)) between 3 and 160),
  descripcion text check (descripcion is null or length(descripcion) <= 2000),
  vigente_desde date not null,
  vigente_hasta date,
  revision bigint not null default 1 check (revision > 0),
  creado_por uuid references public.perfiles(id) on delete set null,
  creado_en timestamptz not null default now(),
  actualizado_por uuid references public.perfiles(id) on delete set null,
  actualizado_en timestamptz not null default now(),
  publicada_por uuid references public.perfiles(id) on delete set null,
  publicada_en timestamptz,
  retirada_por uuid references public.perfiles(id) on delete set null,
  retirada_en timestamptz,
  constraint producto_versiones_numero_uk
    unique (producto_id, numero_version),
  constraint producto_versiones_vigencia_check
    check (vigente_hasta is null or vigente_hasta >= vigente_desde),
  constraint producto_versiones_estado_coherente check (
    (estado = 'borrador'
      and publicada_en is null and publicada_por is null
      and retirada_en is null and retirada_por is null)
    or (estado = 'publicada'
      and publicada_en is not null
      and retirada_en is null and retirada_por is null)
    or (estado = 'retirada' and retirada_en is not null)
  )
);

create unique index producto_versiones_un_borrador_uk
  on crm.producto_versiones (producto_id)
  where estado = 'borrador';
create unique index producto_versiones_una_publicada_uk
  on crm.producto_versiones (producto_id)
  where estado = 'publicada';
create index producto_versiones_producto_estado_idx
  on crm.producto_versiones (producto_id, estado, numero_version desc);
create index producto_versiones_creado_por_idx
  on crm.producto_versiones (creado_por) where creado_por is not null;
create index producto_versiones_actualizado_por_idx
  on crm.producto_versiones (actualizado_por) where actualizado_por is not null;
create index producto_versiones_publicada_por_idx
  on crm.producto_versiones (publicada_por) where publicada_por is not null;
create index producto_versiones_retirada_por_idx
  on crm.producto_versiones (retirada_por) where retirada_por is not null;

comment on table crm.producto_versiones is
  'Versión comercial. Solo borrador puede editarse; publicada y retirada son snapshots inmutables.';

create table crm.producto_condiciones (
  id uuid primary key default gen_random_uuid(),
  version_id uuid not null
    references crm.producto_versiones(id) on delete restrict,
  orden integer not null check (orden > 0),
  categoria text check (categoria in ('nuevo', 'renovacion', 'upgrade')),
  moneda text not null check (moneda in ('PEN', 'USD')),
  plazo_meses integer,
  modalidad text not null
    check (modalidad in ('mensual', 'trimestral', 'semestral', 'anual')),
  tipo_interes text not null
    check (tipo_interes in ('simple', 'compuesto')),
  capital_minimo numeric(14,2) not null,
  capital_maximo numeric(14,2) not null,
  tasa_referencia numeric(7,4) not null,
  tasa_minima numeric(7,4) not null,
  tasa_maxima numeric(7,4) not null,
  activa boolean not null default true,
  es_legacy boolean not null default false,
  legacy_contrato_id uuid,
  fecha_inicio_legacy date,
  fecha_vencimiento_legacy date,
  creado_por uuid references public.perfiles(id) on delete set null,
  creado_en timestamptz not null default now(),
  retirada_por uuid references public.perfiles(id) on delete set null,
  retirada_en timestamptz,
  constraint producto_condiciones_capital_check check (
    capital_minimo between 100 and 100000000
    and capital_maximo between capital_minimo and 100000000
  ),
  constraint producto_condiciones_tasa_check check (
    tasa_minima > 0
    and tasa_minima <= tasa_referencia
    and tasa_referencia <= tasa_maxima
    and tasa_maxima <= 50
  ),
  constraint producto_condiciones_activa_check check (
    (activa and retirada_en is null and retirada_por is null)
    or (not activa and retirada_en is not null)
  ),
  constraint producto_condiciones_legacy_check check (
    (es_legacy
      and legacy_contrato_id is not null
      and plazo_meses is null
      and fecha_inicio_legacy is not null
      and fecha_vencimiento_legacy is not null)
    or (not es_legacy
      and legacy_contrato_id is null
      and categoria is not null
      and plazo_meses between 1 and 600
      and fecha_inicio_legacy is null
      and fecha_vencimiento_legacy is null)
  )
);

create index producto_condiciones_version_activas_idx
  on crm.producto_condiciones (version_id, orden)
  where activa;
create unique index producto_condiciones_orden_activo_uk
  on crm.producto_condiciones (version_id, orden)
  where activa;
create unique index producto_condiciones_combinacion_activa_uk
  on crm.producto_condiciones (
    version_id, categoria, moneda, plazo_meses, modalidad, tipo_interes,
    capital_minimo, capital_maximo, tasa_referencia, tasa_minima, tasa_maxima
  )
  where activa and not es_legacy;
create index producto_condiciones_selector_idx
  on crm.producto_condiciones
    (categoria, moneda, plazo_meses, modalidad, tipo_interes)
  where activa and not es_legacy;
create index producto_condiciones_legacy_contrato_idx
  on crm.producto_condiciones (legacy_contrato_id, creado_en desc)
  where es_legacy;
create index producto_condiciones_creado_por_idx
  on crm.producto_condiciones (creado_por) where creado_por is not null;
create index producto_condiciones_retirada_por_idx
  on crm.producto_condiciones (retirada_por) where retirada_por is not null;

comment on table crm.producto_condiciones is
  'Combinaciones normalizadas de categoría, moneda, plazo, modalidad, capital y tasa. Las retiradas se conservan.';
comment on column crm.producto_condiciones.tasa_referencia is
  'Referencia comercial; el contrato conserva por separado la tasa efectiva pactada.';

-- Guardas estructurales: también protegen frente a service_role/SQL accidental.
create or replace function private.trg_productos_inversion_inmutables()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'DELETE' then
    raise exception 'Los productos se archivan; no se eliminan'
      using errcode = '23514';
  end if;

  if new.id is distinct from old.id
     or new.codigo is distinct from old.codigo
     or new.es_legacy is distinct from old.es_legacy
     or new.creado_por is distinct from old.creado_por
     or new.creado_en is distinct from old.creado_en then
    raise exception 'La identidad y autoría del producto son inmutables'
      using errcode = '23514';
  end if;
  if old.estado = 'archivado' then
    if old.es_legacy
       and old.permite_altas_legacy
       and not new.permite_altas_legacy
       and new.estado = old.estado
       and new.revision = old.revision + 1
       and new.archivado_por is not distinct from old.archivado_por
       and new.archivado_en is not distinct from old.archivado_en then
      return new;
    end if;
    raise exception 'Un producto archivado es inmutable'
      using errcode = '23514';
  end if;
  if new.estado not in ('activo', 'archivado')
     or new.revision <> old.revision + 1 then
    raise exception 'Transición o revisión de producto inválida'
      using errcode = '23514';
  end if;
  return new;
end;
$function$;

create trigger trg_productos_inversion_inmutables
before update or delete on crm.productos_inversion
for each row execute function private.trg_productos_inversion_inmutables();

create or replace function private.trg_producto_versiones_inmutables()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_producto_estado text;
  v_producto_legacy boolean;
begin
  if tg_op = 'INSERT' then
    if new.estado <> 'borrador' then
      raise exception 'Toda versión nace como borrador'
        using errcode = '23514';
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    raise exception 'Las versiones se retiran; no se eliminan'
      using errcode = '23514';
  end if;

  if new.id is distinct from old.id
     or new.producto_id is distinct from old.producto_id
     or new.numero_version is distinct from old.numero_version
     or new.creado_por is distinct from old.creado_por
     or new.creado_en is distinct from old.creado_en
     or new.revision <> old.revision + 1 then
    raise exception 'Identidad, autoría o revisión de versión inválida'
      using errcode = '23514';
  end if;

  if old.estado = 'retirada' then
    raise exception 'Una versión retirada es inmutable'
      using errcode = '23514';
  elsif old.estado = 'publicada' then
    if new.estado <> 'retirada'
       or new.nombre is distinct from old.nombre
       or new.descripcion is distinct from old.descripcion
       or new.vigente_desde is distinct from old.vigente_desde
       or new.vigente_hasta is distinct from old.vigente_hasta
       or new.publicada_por is distinct from old.publicada_por
       or new.publicada_en is distinct from old.publicada_en then
      raise exception 'Una versión publicada solo puede retirarse sin cambiar contenido'
        using errcode = '23514';
    end if;
  elsif new.estado not in ('borrador', 'publicada', 'retirada') then
    raise exception 'Transición de versión inválida'
      using errcode = '23514';
  elsif new.estado <> 'borrador' and (
    new.nombre is distinct from old.nombre
    or new.descripcion is distinct from old.descripcion
    or new.vigente_desde is distinct from old.vigente_desde
    or new.vigente_hasta is distinct from old.vigente_hasta
  ) then
    raise exception 'Publicar o retirar no puede cambiar el contenido del borrador'
      using errcode = '23514';
  end if;

  if new.estado = 'publicada' then
    select p.estado, p.es_legacy
      into v_producto_estado, v_producto_legacy
    from crm.productos_inversion p
    where p.id = new.producto_id;

    if v_producto_estado <> 'activo' or v_producto_legacy then
      raise exception 'Solo un producto comercial activo puede publicar versiones'
        using errcode = '23514';
    end if;
    if not exists (
      select 1
      from crm.producto_condiciones c
      where c.version_id = new.id
        and c.activa
        and not c.es_legacy
    ) then
      raise exception 'Una versión publicada requiere condiciones activas'
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$function$;

create trigger trg_producto_versiones_inmutables
before insert or update or delete on crm.producto_versiones
for each row execute function private.trg_producto_versiones_inmutables();

create or replace function private.trg_producto_condiciones_inmutables()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_estado text;
  v_producto_legacy boolean;
begin
  if tg_op = 'DELETE' then
    raise exception 'Las condiciones se retiran; no se eliminan'
      using errcode = '23514';
  end if;

  select v.estado, p.es_legacy
    into v_estado, v_producto_legacy
  from crm.producto_versiones v
  join crm.productos_inversion p on p.id = v.producto_id
  where v.id = coalesce(new.version_id, old.version_id)
  for update of v;

  if not found or v_estado <> 'borrador' then
    raise exception 'Las condiciones solo cambian mientras la versión es borrador'
      using errcode = '23514';
  end if;

  if tg_op = 'INSERT' then
    if new.es_legacy is distinct from v_producto_legacy then
      raise exception 'La condición legacy no coincide con su producto'
        using errcode = '23514';
    end if;
    return new;
  end if;

  if not old.activa or new.activa
     or new.id is distinct from old.id
     or new.version_id is distinct from old.version_id
     or new.orden is distinct from old.orden
     or new.categoria is distinct from old.categoria
     or new.moneda is distinct from old.moneda
     or new.plazo_meses is distinct from old.plazo_meses
     or new.modalidad is distinct from old.modalidad
     or new.tipo_interes is distinct from old.tipo_interes
     or new.capital_minimo is distinct from old.capital_minimo
     or new.capital_maximo is distinct from old.capital_maximo
     or new.tasa_referencia is distinct from old.tasa_referencia
     or new.tasa_minima is distinct from old.tasa_minima
     or new.tasa_maxima is distinct from old.tasa_maxima
     or new.es_legacy is distinct from old.es_legacy
     or new.legacy_contrato_id is distinct from old.legacy_contrato_id
     or new.fecha_inicio_legacy is distinct from old.fecha_inicio_legacy
     or new.fecha_vencimiento_legacy is distinct from old.fecha_vencimiento_legacy
     or new.creado_por is distinct from old.creado_por
     or new.creado_en is distinct from old.creado_en
     or new.retirada_en is null then
    raise exception 'Una condición solo puede pasar de activa a retirada'
      using errcode = '23514';
  end if;
  return new;
end;
$function$;

create trigger trg_producto_condiciones_inmutables
before insert or update or delete on crm.producto_condiciones
for each row execute function private.trg_producto_condiciones_inmutables();

-- Inserta el arreglo normalizado de condiciones de una versión comercial.
create or replace function private.insertar_condiciones_producto(
  p_version_id uuid,
  p_condiciones jsonb,
  p_actor uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_item jsonb;
  v_orden integer;
  v_categoria text;
  v_moneda text;
  v_plazo integer;
  v_modalidad text;
  v_tipo text;
  v_capital_min numeric;
  v_capital_max numeric;
  v_tasa_ref numeric;
  v_tasa_min numeric;
  v_tasa_max numeric;
begin
  if p_condiciones is null
     or jsonb_typeof(p_condiciones) <> 'array'
     or jsonb_array_length(p_condiciones) not between 1 and 100 then
    raise exception 'Envía entre 1 y 100 condiciones'
      using errcode = '22023';
  end if;

  for v_item, v_orden in
    select value, ordinality::integer
    from jsonb_array_elements(p_condiciones) with ordinality
  loop
    if jsonb_typeof(v_item) <> 'object'
       or (v_item - array[
         'categoria', 'moneda', 'plazo_meses', 'modalidad', 'tipo_interes',
         'capital_minimo', 'capital_maximo', 'tasa_referencia',
         'tasa_minima', 'tasa_maxima'
       ]) <> '{}'::jsonb
       or jsonb_typeof(v_item->'plazo_meses') is distinct from 'number'
       or jsonb_typeof(v_item->'capital_minimo') is distinct from 'number'
       or jsonb_typeof(v_item->'capital_maximo') is distinct from 'number'
       or jsonb_typeof(v_item->'tasa_referencia') is distinct from 'number'
       or (
         v_item ? 'tasa_minima'
         and jsonb_typeof(v_item->'tasa_minima') is distinct from 'number'
       )
       or (
         v_item ? 'tasa_maxima'
         and jsonb_typeof(v_item->'tasa_maxima') is distinct from 'number'
       ) then
      raise exception 'Condición % tiene formato o campos inválidos', v_orden
        using errcode = '22023';
    end if;

    begin
      v_categoria := lower(btrim(v_item->>'categoria'));
      v_moneda := upper(btrim(v_item->>'moneda'));
      v_plazo := (v_item->>'plazo_meses')::integer;
      v_modalidad := lower(btrim(v_item->>'modalidad'));
      v_tipo := lower(btrim(v_item->>'tipo_interes'));
      v_capital_min := (v_item->>'capital_minimo')::numeric;
      v_capital_max := (v_item->>'capital_maximo')::numeric;
      v_tasa_ref := (v_item->>'tasa_referencia')::numeric;
      v_tasa_min := coalesce((v_item->>'tasa_minima')::numeric, v_tasa_ref);
      v_tasa_max := coalesce((v_item->>'tasa_maxima')::numeric, v_tasa_ref);
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'Condición % contiene números inválidos', v_orden
          using errcode = '22023';
    end;

    if v_categoria not in ('nuevo', 'renovacion', 'upgrade')
       or v_moneda not in ('PEN', 'USD')
       or v_plazo not between 1 and 600
       or v_modalidad not in ('mensual', 'trimestral', 'semestral', 'anual')
       or v_tipo not in ('simple', 'compuesto')
       or v_capital_min < 100
       or v_capital_max < v_capital_min
       or v_capital_max > 100000000
       or v_tasa_min <= 0
       or v_tasa_min > v_tasa_ref
       or v_tasa_ref > v_tasa_max
       or v_tasa_max > 50 then
      raise exception 'Condición % está fuera del contrato permitido', v_orden
        using errcode = '22023';
    end if;

    insert into crm.producto_condiciones (
      version_id, orden, categoria, moneda, plazo_meses, modalidad,
      tipo_interes, capital_minimo, capital_maximo, tasa_referencia,
      tasa_minima, tasa_maxima, creado_por
    ) values (
      p_version_id, v_orden, v_categoria, v_moneda, v_plazo, v_modalidad,
      v_tipo, v_capital_min, v_capital_max, v_tasa_ref,
      v_tasa_min, v_tasa_max, p_actor
    );
  end loop;

  return jsonb_array_length(p_condiciones);
end;
$function$;

-- Snapshot de compatibilidad: una versión retirada por contrato, sin inferir
-- categoría, producto o plazo a partir de cronología. El lock del producto
-- técnico serializa max(numero_version)+1 en altas legacy concurrentes.
create or replace function private.crear_snapshot_producto_legacy(
  p_contrato_id uuid,
  p_categoria text,
  p_moneda text,
  p_modalidad text,
  p_tipo_interes text,
  p_capital numeric,
  p_tasa_anual numeric,
  p_fecha_inicio date,
  p_fecha_vencimiento date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_producto_id uuid;
  v_numero_version integer;
  v_version_id uuid;
  v_condicion_id uuid;
  v_actor uuid := (select auth.uid());
begin
  if p_contrato_id is null
     or p_moneda not in ('PEN', 'USD')
     or p_modalidad not in ('mensual', 'trimestral', 'semestral', 'anual')
     or p_tipo_interes not in ('simple', 'compuesto')
     or p_capital not between 100 and 100000000
     or p_tasa_anual <= 0 or p_tasa_anual > 50
     or p_fecha_inicio is null or p_fecha_vencimiento is null
     or p_fecha_vencimiento < p_fecha_inicio
     or (p_categoria is not null
       and p_categoria not in ('nuevo', 'renovacion', 'upgrade')) then
    raise exception 'No se puede fotografiar un contrato con términos inválidos'
      using errcode = '23514';
  end if;

  select p.id into v_producto_id
  from crm.productos_inversion p
  where p.codigo = 'HISTORICO-SIN-CATALOGO'
    and p.es_legacy
  for update;
  if not found then
    raise exception 'Falta el producto técnico de contratos históricos'
      using errcode = 'P0001';
  end if;

  select coalesce(max(v.numero_version), 0) + 1
    into v_numero_version
  from crm.producto_versiones v
  where v.producto_id = v_producto_id;

  insert into crm.producto_versiones (
    producto_id, numero_version, estado, nombre, descripcion,
    vigente_desde, vigente_hasta, creado_por, actualizado_por
  ) values (
    v_producto_id, v_numero_version, 'borrador',
    'Histórico sin catálogo',
    'Snapshot técnico del contrato ' || p_contrato_id::text,
    p_fecha_inicio, p_fecha_vencimiento, v_actor, v_actor
  ) returning id into v_version_id;

  insert into crm.producto_condiciones (
    version_id, orden, categoria, moneda, plazo_meses, modalidad,
    tipo_interes, capital_minimo, capital_maximo, tasa_referencia,
    tasa_minima, tasa_maxima, es_legacy, legacy_contrato_id,
    fecha_inicio_legacy, fecha_vencimiento_legacy, creado_por
  ) values (
    v_version_id, 1, p_categoria, p_moneda, null, p_modalidad,
    p_tipo_interes, p_capital, p_capital, p_tasa_anual,
    p_tasa_anual, p_tasa_anual, true, p_contrato_id,
    p_fecha_inicio, p_fecha_vencimiento, v_actor
  ) returning id into v_condicion_id;

  update crm.producto_versiones
     set estado = 'retirada',
         revision = revision + 1,
         actualizado_por = v_actor,
         actualizado_en = now(),
         retirada_por = v_actor,
         retirada_en = now()
   where id = v_version_id;

  return v_condicion_id;
end;
$function$;

create or replace function private.validar_cabecera_version_producto(
  p_nombre text,
  p_descripcion text,
  p_vigente_desde date,
  p_vigente_hasta date
)
returns void
language plpgsql
immutable
set search_path = ''
as $function$
begin
  if length(btrim(coalesce(p_nombre, ''))) not between 3 and 160
     or (p_descripcion is not null and length(p_descripcion) > 2000)
     or p_vigente_desde is null
     or (p_vigente_hasta is not null and p_vigente_hasta < p_vigente_desde) then
    raise exception 'Nombre o vigencia del producto inválidos'
      using errcode = '22023';
  end if;
end;
$function$;

create or replace function crm.crear_producto_inversion(
  p_codigo text,
  p_nombre text,
  p_descripcion text,
  p_vigente_desde date,
  p_vigente_hasta date,
  p_condiciones jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_codigo text := upper(btrim(coalesce(p_codigo, '')));
  v_producto_id uuid;
  v_version_id uuid;
begin
  if private.rol_crm(v_actor) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia puede administrar productos de inversión'
      using errcode = '42501';
  end if;
  if v_codigo = 'HISTORICO-SIN-CATALOGO'
     or v_codigo !~ '^[A-Z0-9][A-Z0-9._-]{1,39}$' then
    raise exception 'Código de producto inválido o reservado'
      using errcode = '22023';
  end if;
  perform private.validar_cabecera_version_producto(
    p_nombre, p_descripcion, p_vigente_desde, p_vigente_hasta
  );

  insert into crm.productos_inversion (
    codigo, creado_por, actualizado_por
  ) values (
    v_codigo, v_actor, v_actor
  ) returning id into v_producto_id;

  insert into crm.producto_versiones (
    producto_id, numero_version, nombre, descripcion,
    vigente_desde, vigente_hasta, creado_por, actualizado_por
  ) values (
    v_producto_id, 1, btrim(p_nombre), nullif(btrim(p_descripcion), ''),
    p_vigente_desde, p_vigente_hasta, v_actor, v_actor
  ) returning id into v_version_id;

  perform private.insertar_condiciones_producto(
    v_version_id, p_condiciones, v_actor
  );

  return jsonb_build_object(
    'producto_id', v_producto_id,
    'producto_revision', 1,
    'version_id', v_version_id,
    'version_revision', 1,
    'numero_version', 1,
    'estado', 'borrador'
  );
end;
$function$;

create or replace function crm.crear_version_producto_inversion(
  p_producto_id uuid,
  p_expected_revision bigint,
  p_nombre text,
  p_descripcion text,
  p_vigente_desde date,
  p_vigente_hasta date,
  p_condiciones jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_producto crm.productos_inversion%rowtype;
  v_numero integer;
  v_version_id uuid;
begin
  if private.rol_crm(v_actor) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia puede administrar productos de inversión'
      using errcode = '42501';
  end if;
  perform private.validar_cabecera_version_producto(
    p_nombre, p_descripcion, p_vigente_desde, p_vigente_hasta
  );

  select * into v_producto
  from crm.productos_inversion p
  where p.id = p_producto_id
  for update;
  if not found then
    raise exception 'Producto no encontrado' using errcode = 'P0002';
  end if;
  if v_producto.es_legacy or v_producto.estado <> 'activo' then
    raise exception 'El producto está archivado o es de uso interno'
      using errcode = '23514';
  end if;
  if p_expected_revision is distinct from v_producto.revision then
    raise exception 'El producto cambió; recarga antes de crear otra versión'
      using errcode = '40001';
  end if;
  if exists (
    select 1 from crm.producto_versiones v
    where v.producto_id = p_producto_id and v.estado = 'borrador'
  ) then
    raise exception 'Ya existe un borrador para este producto'
      using errcode = '23505';
  end if;

  select coalesce(max(v.numero_version), 0) + 1 into v_numero
  from crm.producto_versiones v
  where v.producto_id = p_producto_id;

  insert into crm.producto_versiones (
    producto_id, numero_version, nombre, descripcion,
    vigente_desde, vigente_hasta, creado_por, actualizado_por
  ) values (
    p_producto_id, v_numero, btrim(p_nombre), nullif(btrim(p_descripcion), ''),
    p_vigente_desde, p_vigente_hasta, v_actor, v_actor
  ) returning id into v_version_id;

  perform private.insertar_condiciones_producto(
    v_version_id, p_condiciones, v_actor
  );

  update crm.productos_inversion
     set revision = revision + 1,
         actualizado_por = v_actor,
         actualizado_en = now()
   where id = p_producto_id;

  return jsonb_build_object(
    'producto_id', p_producto_id,
    'producto_revision', v_producto.revision + 1,
    'version_id', v_version_id,
    'version_revision', 1,
    'numero_version', v_numero,
    'estado', 'borrador'
  );
end;
$function$;

create or replace function crm.actualizar_borrador_producto_inversion(
  p_version_id uuid,
  p_expected_revision bigint,
  p_nombre text,
  p_descripcion text,
  p_vigente_desde date,
  p_vigente_hasta date,
  p_condiciones jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_producto crm.productos_inversion%rowtype;
  v_version crm.producto_versiones%rowtype;
begin
  if private.rol_crm(v_actor) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia puede administrar productos de inversión'
      using errcode = '42501';
  end if;
  perform private.validar_cabecera_version_producto(
    p_nombre, p_descripcion, p_vigente_desde, p_vigente_hasta
  );

  select p.* into v_producto
  from crm.productos_inversion p
  where p.id = (
    select v.producto_id from crm.producto_versiones v
    where v.id = p_version_id
  )
  for update;
  if not found then
    raise exception 'Versión no encontrada' using errcode = 'P0002';
  end if;

  select * into v_version
  from crm.producto_versiones v
  where v.id = p_version_id
  for update;

  if v_producto.es_legacy or v_producto.estado <> 'activo'
     or v_version.estado <> 'borrador' then
    raise exception 'Solo puede editarse un borrador de producto activo'
      using errcode = '23514';
  end if;
  if p_expected_revision is distinct from v_version.revision then
    raise exception 'El borrador cambió; recarga antes de guardar'
      using errcode = '40001';
  end if;

  update crm.producto_condiciones
     set activa = false,
         retirada_por = v_actor,
         retirada_en = now()
   where version_id = p_version_id
     and activa;

  perform private.insertar_condiciones_producto(
    p_version_id, p_condiciones, v_actor
  );

  update crm.producto_versiones
     set nombre = btrim(p_nombre),
         descripcion = nullif(btrim(p_descripcion), ''),
         vigente_desde = p_vigente_desde,
         vigente_hasta = p_vigente_hasta,
         revision = revision + 1,
         actualizado_por = v_actor,
         actualizado_en = now()
   where id = p_version_id;

  update crm.productos_inversion
     set revision = revision + 1,
         actualizado_por = v_actor,
         actualizado_en = now()
   where id = v_producto.id;

  return jsonb_build_object(
    'producto_id', v_producto.id,
    'producto_revision', v_producto.revision + 1,
    'version_id', p_version_id,
    'version_revision', v_version.revision + 1,
    'numero_version', v_version.numero_version,
    'estado', 'borrador'
  );
end;
$function$;

create or replace function crm.publicar_version_producto_inversion(
  p_version_id uuid,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_producto crm.productos_inversion%rowtype;
  v_version crm.producto_versiones%rowtype;
begin
  if private.rol_crm(v_actor) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia puede publicar productos de inversión'
      using errcode = '42501';
  end if;

  select p.* into v_producto
  from crm.productos_inversion p
  where p.id = (
    select v.producto_id from crm.producto_versiones v
    where v.id = p_version_id
  )
  for update;
  if not found then
    raise exception 'Versión no encontrada' using errcode = 'P0002';
  end if;

  select * into v_version
  from crm.producto_versiones v
  where v.id = p_version_id
  for update;

  if v_producto.es_legacy or v_producto.estado <> 'activo'
     or v_version.estado <> 'borrador' then
    raise exception 'Solo puede publicarse un borrador de producto activo'
      using errcode = '23514';
  end if;
  if p_expected_revision is distinct from v_version.revision then
    raise exception 'El borrador cambió; recarga antes de publicar'
      using errcode = '40001';
  end if;
  if v_version.vigente_desde > current_date
     or (v_version.vigente_hasta is not null
       and v_version.vigente_hasta < current_date) then
    raise exception 'La versión debe estar vigente el día de su publicación'
      using errcode = '23514';
  end if;
  if not exists (
    select 1 from crm.producto_condiciones c
    where c.version_id = p_version_id and c.activa and not c.es_legacy
  ) then
    raise exception 'La versión no tiene condiciones activas'
      using errcode = '23514';
  end if;

  update crm.producto_versiones
     set estado = 'retirada',
         revision = revision + 1,
         actualizado_por = v_actor,
         actualizado_en = now(),
         retirada_por = v_actor,
         retirada_en = now()
   where producto_id = v_producto.id
     and estado = 'publicada';

  update crm.producto_versiones
     set estado = 'publicada',
         revision = revision + 1,
         actualizado_por = v_actor,
         actualizado_en = now(),
         publicada_por = v_actor,
         publicada_en = now()
   where id = p_version_id;

  update crm.productos_inversion
     set revision = revision + 1,
         actualizado_por = v_actor,
         actualizado_en = now()
   where id = v_producto.id;

  return jsonb_build_object(
    'producto_id', v_producto.id,
    'producto_revision', v_producto.revision + 1,
    'version_id', p_version_id,
    'version_revision', v_version.revision + 1,
    'numero_version', v_version.numero_version,
    'estado', 'publicada'
  );
end;
$function$;

create or replace function crm.archivar_producto_inversion(
  p_producto_id uuid,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_producto crm.productos_inversion%rowtype;
begin
  if private.rol_crm(v_actor) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia puede archivar productos de inversión'
      using errcode = '42501';
  end if;

  select * into v_producto
  from crm.productos_inversion p
  where p.id = p_producto_id
  for update;
  if not found then
    raise exception 'Producto no encontrado' using errcode = 'P0002';
  end if;
  if v_producto.es_legacy then
    raise exception 'El producto histórico es interno'
      using errcode = '23514';
  end if;
  if v_producto.estado = 'archivado' then
    raise exception 'El producto ya está archivado'
      using errcode = '23514';
  end if;
  if p_expected_revision is distinct from v_producto.revision then
    raise exception 'El producto cambió; recarga antes de archivarlo'
      using errcode = '40001';
  end if;

  update crm.producto_versiones
     set estado = 'retirada',
         revision = revision + 1,
         actualizado_por = v_actor,
         actualizado_en = now(),
         retirada_por = v_actor,
         retirada_en = now()
   where producto_id = p_producto_id
     and estado in ('borrador', 'publicada');

  update crm.productos_inversion
     set estado = 'archivado',
         revision = revision + 1,
         actualizado_por = v_actor,
         actualizado_en = now(),
         archivado_por = v_actor,
         archivado_en = now()
   where id = p_producto_id;

  return jsonb_build_object(
    'producto_id', p_producto_id,
    'producto_revision', v_producto.revision + 1,
    'estado', 'archivado'
  );
end;
$function$;

create or replace function crm.cerrar_altas_legacy_productos(
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_producto crm.productos_inversion%rowtype;
begin
  if private.rol_crm(v_actor) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia puede cerrar la compatibilidad legacy'
      using errcode = '42501';
  end if;

  select * into v_producto
  from crm.productos_inversion p
  where p.es_legacy
  for update;
  if not found then
    raise exception 'Configuración legacy no encontrada' using errcode = 'P0002';
  end if;
  if p_expected_revision is distinct from v_producto.revision then
    raise exception 'La compatibilidad cambió; recarga antes de cerrarla'
      using errcode = '40001';
  end if;
  if not v_producto.permite_altas_legacy then
    raise exception 'La compatibilidad legacy ya está cerrada y no se reactiva'
      using errcode = '23514';
  end if;

  update crm.productos_inversion
     set permite_altas_legacy = false,
         revision = revision + 1,
         actualizado_por = v_actor,
         actualizado_en = now()
   where id = v_producto.id;

  return jsonb_build_object(
    'compatibilidad_altas_legacy', false,
    'compatibilidad_revision', v_producto.revision + 1
  );
end;
$function$;

create or replace function crm.productos_inversion_gestion_fn()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_actor);
  v_lector_global boolean := private.es_lector_global();
  v_puede_administrar boolean;
  v_productos jsonb;
  v_compatibilidad_legacy boolean;
  v_compatibilidad_revision bigint;
begin
  if v_actor is null or (v_rol is null and not v_lector_global) then
    raise exception 'No autorizado para consultar productos de inversión'
      using errcode = '42501';
  end if;
  v_puede_administrar := v_rol = 'gerencia';
  select p.permite_altas_legacy, p.revision
    into v_compatibilidad_legacy, v_compatibilidad_revision
  from crm.productos_inversion p
  where p.es_legacy;

  select coalesce(jsonb_agg(producto_json order by codigo), '[]'::jsonb)
    into v_productos
  from (
    select
      p.codigo,
      jsonb_build_object(
        'id', p.id,
        'codigo', p.codigo,
        'estado', p.estado,
        'revision', p.revision,
        'creado_por', p.creado_por,
        'creado_en', p.creado_en,
        'actualizado_por', p.actualizado_por,
        'actualizado_en', p.actualizado_en,
        'archivado_por', p.archivado_por,
        'archivado_en', p.archivado_en,
        'versiones', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', v.id,
              'numero_version', v.numero_version,
              'estado', v.estado,
              'revision', v.revision,
              'nombre', v.nombre,
              'descripcion', v.descripcion,
              'vigente_desde', v.vigente_desde,
              'vigente_hasta', v.vigente_hasta,
              'creado_por', v.creado_por,
              'creado_en', v.creado_en,
              'actualizado_por', v.actualizado_por,
              'actualizado_en', v.actualizado_en,
              'publicada_por', v.publicada_por,
              'publicada_por_nombre', (
                select pp.nombre_completo
                from public.perfiles pp
                where pp.id = v.publicada_por
              ),
              'publicada_en', v.publicada_en,
              'retirada_por', v.retirada_por,
              'retirada_en', v.retirada_en,
              'condiciones', coalesce((
                select jsonb_agg(
                  jsonb_build_object(
                    'id', c.id,
                    'orden', c.orden,
                    'categoria', c.categoria,
                    'moneda', c.moneda,
                    'plazo_meses', c.plazo_meses,
                    'modalidad', c.modalidad,
                    'tipo_interes', c.tipo_interes,
                    'capital_minimo', c.capital_minimo,
                    'capital_maximo', c.capital_maximo,
                    'tasa_referencia', c.tasa_referencia,
                    'tasa_minima', c.tasa_minima,
                    'tasa_maxima', c.tasa_maxima,
                    'activa', c.activa,
                    'creado_en', c.creado_en,
                    'retirada_en', c.retirada_en
                  ) order by c.activa desc, c.orden, c.creado_en
                )
                from crm.producto_condiciones c
                where c.version_id = v.id
                  and not c.es_legacy
                  and (v_puede_administrar or v_lector_global or c.activa)
              ), '[]'::jsonb)
            ) order by v.numero_version desc
          )
          from crm.producto_versiones v
          where v.producto_id = p.id
            and (
              v_puede_administrar
              or v_lector_global
              or v.estado in ('publicada', 'retirada')
            )
        ), '[]'::jsonb)
      ) as producto_json
    from crm.productos_inversion p
    where not p.es_legacy
      and (
        v_puede_administrar
        or v_lector_global
        or exists (
          select 1 from crm.producto_versiones visible
          where visible.producto_id = p.id
            and visible.estado in ('publicada', 'retirada')
        )
      )
  ) productos;

  return jsonb_build_object(
    'version', 1,
    'generado_en', now(),
    'puede_administrar', v_puede_administrar,
    'compatibilidad_altas_legacy', v_compatibilidad_legacy,
    'compatibilidad_revision', v_compatibilidad_revision,
    'productos', v_productos
  );
end;
$function$;

create or replace function crm.productos_inversion_seleccion_fn()
returns table (
  condicion_id uuid,
  producto_id uuid,
  producto_codigo text,
  producto_revision bigint,
  version_id uuid,
  numero_version integer,
  version_nombre text,
  vigente_desde date,
  vigente_hasta date,
  categoria text,
  moneda text,
  plazo_meses integer,
  modalidad text,
  tipo_interes text,
  capital_minimo numeric,
  capital_maximo numeric,
  tasa_referencia numeric,
  tasa_minima numeric,
  tasa_maxima numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
begin
  if v_actor is null
     or (
       private.rol_crm(v_actor) is null
       and not private.es_lector_global()
     ) then
    raise exception 'No autorizado para consultar productos de inversión'
      using errcode = '42501';
  end if;

  return query
  select
    c.id, p.id, p.codigo, p.revision,
    v.id, v.numero_version, v.nombre, v.vigente_desde, v.vigente_hasta,
    c.categoria, c.moneda, c.plazo_meses, c.modalidad, c.tipo_interes,
    c.capital_minimo, c.capital_maximo, c.tasa_referencia,
    c.tasa_minima, c.tasa_maxima
  from crm.productos_inversion p
  join crm.producto_versiones v on v.producto_id = p.id
  join crm.producto_condiciones c on c.version_id = v.id
  where p.estado = 'activo'
    and not p.es_legacy
    and v.estado = 'publicada'
    and v.vigente_desde <= current_date
    and (v.vigente_hasta is null or v.vigente_hasta >= current_date)
    and c.activa
    and not c.es_legacy
  order by c.categoria, p.codigo, v.numero_version desc, c.orden;
end;
$function$;

-- Producto técnico único. Cada contrato legacy obtiene SU propia versión
-- retirada; compartir la identidad técnica no mezcla snapshots contractuales.
insert into crm.productos_inversion (
  codigo, estado, revision, es_legacy, permite_altas_legacy, archivado_en
) values (
  'HISTORICO-SIN-CATALOGO', 'archivado', 1, true, true, now()
);

-- Captura previa para demostrar dentro de la propia migración que el backfill
-- solo añade la FK y no modifica ningún término, estado ni sello del contrato.
create temporary table catalogo_contratos_antes
on commit drop
as
select c.id, to_jsonb(c) as fila
from public.contratos c;

create temporary table catalogo_touch_contratos_estado
on commit drop
as
select t.tgenabled
from pg_trigger t
where t.tgrelid = 'public.contratos'::regclass
  and t.tgname = 'trg_contratos_actualizado_en'
  and not t.tgisinternal;

alter table public.contratos
  add column producto_condicion_id uuid;

alter table public.contratos
  add constraint contratos_producto_condicion_fk
  foreign key (producto_condicion_id)
  references crm.producto_condiciones(id)
  on delete restrict
  not valid;

create index contratos_producto_condicion_idx
  on public.contratos (producto_condicion_id);

comment on column public.contratos.producto_condicion_id is
  'Condición/version inmutable que originó el contrato. Los demás campos son los términos legales efectivos pactados.';

create or replace function private.trg_contratos_producto_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_solicitada_text text := nullif(
    current_setting('crm.producto_condicion_id', true), ''
  );
  v_producto_id uuid;
  v_producto_estado text;
  v_version_estado text;
  v_vigente_desde date;
  v_vigente_hasta date;
  v_condicion_activa boolean;
  v_es_legacy boolean;
  v_legacy_contrato_id uuid;
  v_categoria text;
  v_moneda text;
  v_plazo integer;
  v_modalidad text;
  v_tipo_interes text;
  v_capital_min numeric;
  v_capital_max numeric;
  v_tasa_min numeric;
  v_tasa_max numeric;
  v_fecha_inicio_legacy date;
  v_fecha_vencimiento_legacy date;
  v_old_es_legacy boolean;
  v_terminos_legacy_coinciden boolean;
  v_terminos_cambiaron boolean := false;
begin
  if v_solicitada_text is not null then
    begin
      new.producto_condicion_id := v_solicitada_text::uuid;
    exception when invalid_text_representation then
      raise exception 'Condición de producto inválida'
        using errcode = '22023';
    end;
  end if;

  if tg_op = 'UPDATE'
     and new.producto_condicion_id is null
     and old.producto_condicion_id is not null then
    select c.es_legacy into v_old_es_legacy
    from crm.producto_condiciones c
    where c.id = old.producto_condicion_id;
    if not coalesce(v_old_es_legacy, false) then
      raise exception 'Un contrato catalogado no puede perder su producto'
        using errcode = '23514';
    end if;
  end if;

  if new.producto_condicion_id is null then
    if tg_op = 'INSERT' and not exists (
      select 1
      from crm.productos_inversion p
      where p.es_legacy and p.permite_altas_legacy
    ) then
      raise exception 'Selecciona un producto de inversión publicado'
        using errcode = '23514';
    end if;
    new.producto_condicion_id := private.crear_snapshot_producto_legacy(
      new.id, new.categoria, new.moneda, new.modalidad, new.tipo_interes,
      new.capital, new.tasa_anual, new.fecha_inicio, new.fecha_vencimiento
    );
  end if;

  select v.producto_id, c.es_legacy into v_producto_id, v_es_legacy
  from crm.producto_condiciones c
  join crm.producto_versiones v on v.id = c.version_id
  where c.id = new.producto_condicion_id;
  if not found then
    raise exception 'Condición de producto no encontrada'
      using errcode = '23503';
  end if;

  -- Mismo orden de locks que publicar/archivar: producto -> versión. Las
  -- correcciones legacy toman el lock exclusivo desde el inicio porque crear
  -- su nueva versión serializa numero_version sobre el producto técnico.
  if v_es_legacy then
    perform 1
    from crm.productos_inversion p
    where p.id = v_producto_id
    for update;
  else
    perform 1
    from crm.productos_inversion p
    where p.id = v_producto_id
    for share;
  end if;

  select
    p.estado, v.estado, v.vigente_desde, v.vigente_hasta,
    c.activa, c.es_legacy, c.legacy_contrato_id,
    c.categoria, c.moneda, c.plazo_meses, c.modalidad, c.tipo_interes,
    c.capital_minimo, c.capital_maximo, c.tasa_minima, c.tasa_maxima,
    c.fecha_inicio_legacy, c.fecha_vencimiento_legacy
  into
    v_producto_estado, v_version_estado, v_vigente_desde, v_vigente_hasta,
    v_condicion_activa, v_es_legacy, v_legacy_contrato_id,
    v_categoria, v_moneda, v_plazo, v_modalidad, v_tipo_interes,
    v_capital_min, v_capital_max, v_tasa_min, v_tasa_max,
    v_fecha_inicio_legacy, v_fecha_vencimiento_legacy
  from crm.producto_condiciones c
  join crm.producto_versiones v on v.id = c.version_id
  join crm.productos_inversion p on p.id = v.producto_id
  where c.id = new.producto_condicion_id
  for share of v, c;

  if v_es_legacy then
    if v_legacy_contrato_id is distinct from new.id then
      raise exception 'Un snapshot histórico no puede reutilizarse en otro contrato'
        using errcode = '23514';
    end if;

    if tg_op = 'UPDATE'
       and old.producto_condicion_id is not null
       and new.producto_condicion_id is distinct from old.producto_condicion_id then
      raise exception 'Una corrección histórica debe partir del snapshot vigente del contrato'
        using errcode = '23514';
    end if;

    v_terminos_legacy_coinciden :=
      v_categoria is not distinct from new.categoria
      and v_moneda is not distinct from new.moneda
      and v_modalidad is not distinct from new.modalidad
      and v_tipo_interes is not distinct from new.tipo_interes
      and v_capital_min is not distinct from new.capital
      and v_capital_max is not distinct from new.capital
      and v_tasa_min is not distinct from new.tasa_anual
      and v_tasa_max is not distinct from new.tasa_anual
      and v_fecha_inicio_legacy is not distinct from new.fecha_inicio
      and v_fecha_vencimiento_legacy is not distinct from new.fecha_vencimiento;

    if not v_terminos_legacy_coinciden then
      if tg_op = 'UPDATE'
         and new.producto_condicion_id is not distinct from old.producto_condicion_id then
        -- Tanto el caller legacy como los wrappers vigentes conservan el
        -- snapshot actual durante el UPDATE. Si cambian los términos, se crea
        -- otro snapshot retirado en vez de reescribir o reutilizar historia.
        new.producto_condicion_id := private.crear_snapshot_producto_legacy(
          new.id, new.categoria, new.moneda, new.modalidad, new.tipo_interes,
          new.capital, new.tasa_anual, new.fecha_inicio, new.fecha_vencimiento
        );
      else
        raise exception 'El snapshot histórico no coincide con los términos del contrato'
          using errcode = '23514';
      end if;
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE' then
    v_terminos_cambiaron :=
      new.categoria is distinct from old.categoria
      or new.moneda is distinct from old.moneda
      or new.modalidad is distinct from old.modalidad
      or new.tipo_interes is distinct from old.tipo_interes
      or new.capital is distinct from old.capital
      or new.tasa_anual is distinct from old.tasa_anual
      or new.fecha_inicio is distinct from old.fecha_inicio
      or new.fecha_vencimiento is distinct from old.fecha_vencimiento;
  end if;

  -- Una selección nueva exige catálogo vigente. Un contrato ya vinculado puede
  -- conservar/corregir su snapshot aunque después se publique v2 o se archive.
  if tg_op = 'INSERT'
     or new.producto_condicion_id is distinct from old.producto_condicion_id
     or v_terminos_cambiaron then
    if not v_condicion_activa
       or v_producto_estado <> 'activo'
       or v_version_estado <> 'publicada'
       or v_vigente_desde > current_date
       or (v_vigente_hasta is not null and v_vigente_hasta < current_date) then
      raise exception 'La condición no está publicada y vigente para contratos nuevos'
        using errcode = '23514';
    end if;
  end if;

  if new.categoria is distinct from v_categoria
     or new.moneda is distinct from v_moneda
     or new.modalidad is distinct from v_modalidad
     or new.tipo_interes is distinct from v_tipo_interes
     or new.capital < v_capital_min or new.capital > v_capital_max
     or new.tasa_anual < v_tasa_min or new.tasa_anual > v_tasa_max
     or new.fecha_vencimiento is distinct from
       (new.fecha_inicio + make_interval(months => v_plazo))::date then
    raise exception 'Los términos del contrato no cumplen la condición seleccionada'
      using errcode = '23514';
  end if;

  return new;
end;
$function$;

create trigger trg_contratos_producto_snapshot
before insert or update on public.contratos
for each row execute function private.trg_contratos_producto_snapshot();

-- Un snapshot exacto por contrato existente. No usa orden cronológico, cliente,
-- frecuencia ni monto para inventar Nuevo/Renovación/Upgrade.
-- El trigger genérico de touch se suspende dentro del mismo bloque atómico:
-- añadir una FK técnica no debe cambiar actualizado_en de 320 contratos. Si el
-- UPDATE falla, la subtransacción del bloque restaura tanto datos como trigger.
do $backfill_snapshot$
declare
  v_touch_habilitado boolean := exists (
    select 1 from catalogo_touch_contratos_estado where tgenabled = 'O'
  );
begin
  if v_touch_habilitado then
    execute 'alter table public.contratos disable trigger trg_contratos_actualizado_en';
  end if;

  update public.contratos c
  set producto_condicion_id = private.crear_snapshot_producto_legacy(
    c.id, c.categoria, c.moneda, c.modalidad, c.tipo_interes,
    c.capital, c.tasa_anual, c.fecha_inicio, c.fecha_vencimiento
  )
  where c.producto_condicion_id is null;

  if v_touch_habilitado then
    execute 'alter table public.contratos enable trigger trg_contratos_actualizado_en';
  end if;
exception
  when others then
    -- La entrada al handler ya revirtió el DISABLE; ENABLE es deliberadamente
    -- idempotente y deja explícita la garantía aun sin transacción exterior.
    if v_touch_habilitado then
      execute 'alter table public.contratos enable trigger trg_contratos_actualizado_en';
    end if;
    raise;
end;
$backfill_snapshot$;

do $backfill_invariantes$
begin
  if exists (
    select 1 from public.contratos c
    where c.producto_condicion_id is null
  ) then
    raise exception 'Backfill incompleto: hay contratos sin snapshot';
  end if;

  if exists (
    select 1
    from catalogo_contratos_antes antes
    join public.contratos c on c.id = antes.id
    where antes.fila is distinct from (to_jsonb(c) - 'producto_condicion_id')
  ) then
    raise exception 'El backfill alteró términos o metadatos de contratos existentes';
  end if;

  if (select count(*) from catalogo_contratos_antes)
     <> (
       select count(*)
       from crm.producto_condiciones c
       where c.es_legacy
         and c.legacy_contrato_id in (
           select id from catalogo_contratos_antes
         )
     ) then
    raise exception 'El backfill no creó exactamente un snapshot por contrato';
  end if;

  if exists (
    select 1
    from public.contratos ct
    join crm.producto_condiciones c on c.id = ct.producto_condicion_id
    where not c.es_legacy
       or c.legacy_contrato_id is distinct from ct.id
       or c.categoria is distinct from ct.categoria
       or c.moneda is distinct from ct.moneda
       or c.modalidad is distinct from ct.modalidad
       or c.tipo_interes is distinct from ct.tipo_interes
       or c.capital_minimo is distinct from ct.capital
       or c.capital_maximo is distinct from ct.capital
       or c.tasa_minima is distinct from ct.tasa_anual
       or c.tasa_maxima is distinct from ct.tasa_anual
       or c.fecha_inicio_legacy is distinct from ct.fecha_inicio
       or c.fecha_vencimiento_legacy is distinct from ct.fecha_vencimiento
  ) then
    raise exception 'Un snapshot legacy no coincide exactamente con su contrato';
  end if;
end;
$backfill_invariantes$;

alter table public.contratos
  validate constraint contratos_producto_condicion_fk;
alter table public.contratos
  alter column producto_condicion_id set not null;

create or replace function private.metadata_condicion_producto(
  p_condicion_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'producto_condicion_id', c.id,
    'producto_id', p.id,
    'producto_revision', p.revision,
    'version_id', v.id,
    'version_revision', v.revision,
    'numero_version', v.numero_version,
    'version_estado', v.estado,
    'version_nombre', v.nombre
  )
  from crm.producto_condiciones c
  join crm.producto_versiones v on v.id = c.version_id
  join crm.productos_inversion p on p.id = v.producto_id
  where c.id = p_condicion_id;
$function$;

-- Wrappers aditivos: no rompen las firmas legacy. Los callers antiguos reciben
-- snapshot técnico automático; los nuevos fijan una condición publicada en la
-- misma transacción que contrato, cronograma y, cuando aplica, cuenta bancaria.
create or replace function private.puede_gestionar_contratos_crm()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(
    private.rol_crm((select auth.uid())) in ('vendedor','supervisor','gerencia'),
    false
  );
$function$;

comment on function private.puede_gestionar_contratos_crm() is
  'Frontera contractual CRM: Vendedor, Supervisor o Gerencia efectivos. Un rol Portal admin/superadmin no concede acceso por sí solo.';

revoke all on function private.puede_gestionar_contratos_crm()
  from public, anon, authenticated, service_role;

create or replace function crm.crear_contrato_producto(
  p_producto_condicion_id uuid,
  p_contrato jsonb,
  p_cronograma jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_resultado jsonb;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise insufficient_privilege using message = 'No autorizado para gestionar contratos desde el CRM';
  end if;
  if p_producto_condicion_id is null then
    raise exception 'Selecciona un producto de inversión'
      using errcode = '22023';
  end if;
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', p_producto_condicion_id::text, true
  );
  v_resultado := public.crear_contrato(p_contrato, p_cronograma);
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  return v_resultado
    || private.metadata_condicion_producto(p_producto_condicion_id);
exception when others then
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  raise;
end;
$function$;

create or replace function crm.crear_contrato_con_cuenta_producto(
  p_producto_condicion_id uuid,
  p_contrato jsonb,
  p_cronograma jsonb,
  p_cuenta jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_resultado jsonb;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise insufficient_privilege using message = 'No autorizado para gestionar contratos desde el CRM';
  end if;
  if p_producto_condicion_id is null then
    raise exception 'Selecciona un producto de inversión'
      using errcode = '22023';
  end if;
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', p_producto_condicion_id::text, true
  );
  v_resultado := crm.crear_contrato_con_cuenta(
    p_contrato, p_cronograma, p_cuenta
  );
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  return v_resultado
    || private.metadata_condicion_producto(p_producto_condicion_id);
exception when others then
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  raise;
end;
$function$;

create or replace function crm.actualizar_contrato_producto(
  p_id uuid,
  p_producto_condicion_id uuid,
  p_contrato jsonb,
  p_cronograma jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_resultado jsonb;
  v_condicion_resultante uuid;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise insufficient_privilege using message = 'No autorizado para gestionar contratos desde el CRM';
  end if;
  if p_producto_condicion_id is null then
    raise exception 'Selecciona un producto de inversión'
      using errcode = '22023';
  end if;
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', p_producto_condicion_id::text, true
  );
  v_resultado := public.actualizar_contrato(p_id, p_contrato, p_cronograma);
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  select c.producto_condicion_id into v_condicion_resultante
  from public.contratos c
  where c.id = p_id;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
  return v_resultado
    || private.metadata_condicion_producto(v_condicion_resultante);
exception when others then
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  raise;
end;
$function$;

create or replace function crm.actualizar_contrato_con_cuenta_producto(
  p_id uuid,
  p_producto_condicion_id uuid,
  p_contrato jsonb,
  p_cronograma jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_resultado jsonb;
  v_condicion_resultante uuid;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise insufficient_privilege using message = 'No autorizado para gestionar contratos desde el CRM';
  end if;
  if p_producto_condicion_id is null then
    raise exception 'Selecciona un producto de inversión'
      using errcode = '22023';
  end if;
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', p_producto_condicion_id::text, true
  );
  perform crm.actualizar_contrato_con_cuenta(
    p_id, p_contrato, p_cronograma
  );
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  select c.producto_condicion_id into v_condicion_resultante
  from public.contratos c
  where c.id = p_id;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
  v_resultado := jsonb_build_object('id', p_id, 'ok', true)
    || private.metadata_condicion_producto(v_condicion_resultante);
  return v_resultado;
exception when others then
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  raise;
end;
$function$;

create or replace function private.producto_inversion_tiene_version_visible(
  p_producto_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null and exists (
    select 1 from crm.producto_versiones v
    where v.producto_id = p_producto_id
      and v.estado in ('publicada', 'retirada')
  );
$function$;

-- RLS deny-by-default. Directorio/admin/superadmin globales auditan todo;
-- Gerencia CRM ve borradores y administra por RPC; los demás miembros activos
-- solo ven catálogo comercial no-legacy publicado/retirado.
alter table crm.productos_inversion enable row level security;
alter table crm.producto_versiones enable row level security;
alter table crm.producto_condiciones enable row level security;

create policy productos_inversion_select
on crm.productos_inversion
for select
to authenticated
using (
  (select private.es_lector_global())
  or (select private.rol_crm((select auth.uid()))) = 'gerencia'
  or (
    (select private.rol_crm((select auth.uid()))) is not null
    and not es_legacy
    and (select private.producto_inversion_tiene_version_visible(productos_inversion.id))
  )
);

create policy producto_versiones_select
on crm.producto_versiones
for select
to authenticated
using (
  (select private.es_lector_global())
  or (select private.rol_crm((select auth.uid()))) = 'gerencia'
  or (
    (select private.rol_crm((select auth.uid()))) is not null
    and estado in ('publicada', 'retirada')
    and exists (
      select 1 from crm.productos_inversion p
      where p.id = producto_versiones.producto_id
        and not p.es_legacy
    )
  )
);

create policy producto_condiciones_select
on crm.producto_condiciones
for select
to authenticated
using (
  (select private.es_lector_global())
  or (select private.rol_crm((select auth.uid()))) = 'gerencia'
  or (
    (select private.rol_crm((select auth.uid()))) is not null
    and activa
    and not es_legacy
    and exists (
      select 1
      from crm.producto_versiones v
      join crm.productos_inversion p on p.id = v.producto_id
      where v.id = producto_condiciones.version_id
        and v.estado in ('publicada', 'retirada')
        and not p.es_legacy
    )
  )
);

-- Auditoría append-only del catálogo. El backfill se identifica por la propia
-- migración; a partir de aquí cada mutación de negocio queda en audit_log.
create trigger trg_audit_productos_inversion
after insert or update or delete on crm.productos_inversion
for each row execute function private.log_audit_crm();
create trigger trg_audit_producto_versiones
after insert or update or delete on crm.producto_versiones
for each row execute function private.log_audit_crm();
create trigger trg_audit_producto_condiciones
after insert or update or delete on crm.producto_condiciones
for each row execute function private.log_audit_crm();

revoke all on table crm.productos_inversion
  from public, anon, authenticated;
revoke all on table crm.producto_versiones
  from public, anon, authenticated;
revoke all on table crm.producto_condiciones
  from public, anon, authenticated;
grant select on table crm.productos_inversion,
  crm.producto_versiones, crm.producto_condiciones to authenticated;
grant select, insert, update on table crm.productos_inversion,
  crm.producto_versiones, crm.producto_condiciones to service_role;

revoke all on function crm.crear_producto_inversion(
  text, text, text, date, date, jsonb
) from public, anon, authenticated, service_role;
revoke all on function crm.crear_version_producto_inversion(
  uuid, bigint, text, text, date, date, jsonb
) from public, anon, authenticated, service_role;
revoke all on function crm.actualizar_borrador_producto_inversion(
  uuid, bigint, text, text, date, date, jsonb
) from public, anon, authenticated, service_role;
revoke all on function crm.publicar_version_producto_inversion(uuid, bigint)
  from public, anon, authenticated, service_role;
revoke all on function crm.archivar_producto_inversion(uuid, bigint)
  from public, anon, authenticated, service_role;
revoke all on function crm.cerrar_altas_legacy_productos(bigint)
  from public, anon, authenticated, service_role;
revoke all on function crm.productos_inversion_gestion_fn()
  from public, anon, authenticated, service_role;
revoke all on function crm.productos_inversion_seleccion_fn()
  from public, anon, authenticated, service_role;
revoke all on function crm.crear_contrato_producto(uuid, jsonb, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function crm.crear_contrato_con_cuenta_producto(
  uuid, jsonb, jsonb, jsonb
) from public, anon, authenticated, service_role;
revoke all on function crm.actualizar_contrato_producto(
  uuid, uuid, jsonb, jsonb
) from public, anon, authenticated, service_role;
revoke all on function crm.actualizar_contrato_con_cuenta_producto(
  uuid, uuid, jsonb, jsonb
) from public, anon, authenticated, service_role;

grant execute on function crm.crear_producto_inversion(
  text, text, text, date, date, jsonb
) to authenticated;
grant execute on function crm.crear_version_producto_inversion(
  uuid, bigint, text, text, date, date, jsonb
) to authenticated;
grant execute on function crm.actualizar_borrador_producto_inversion(
  uuid, bigint, text, text, date, date, jsonb
) to authenticated;
grant execute on function crm.publicar_version_producto_inversion(uuid, bigint)
  to authenticated;
grant execute on function crm.archivar_producto_inversion(uuid, bigint)
  to authenticated;
grant execute on function crm.cerrar_altas_legacy_productos(bigint)
  to authenticated;
grant execute on function crm.productos_inversion_gestion_fn()
  to authenticated;
grant execute on function crm.productos_inversion_seleccion_fn()
  to authenticated;
grant execute on function crm.crear_contrato_producto(uuid, jsonb, jsonb)
  to authenticated;
grant execute on function crm.crear_contrato_con_cuenta_producto(
  uuid, jsonb, jsonb, jsonb
) to authenticated;
grant execute on function crm.actualizar_contrato_producto(
  uuid, uuid, jsonb, jsonb
) to authenticated;
grant execute on function crm.actualizar_contrato_con_cuenta_producto(
  uuid, uuid, jsonb, jsonb
) to authenticated;

-- Helpers/trigger functions nunca son endpoints Data API.
revoke all on function private.trg_productos_inversion_inmutables()
  from public, anon, authenticated, service_role;
revoke all on function private.trg_producto_versiones_inmutables()
  from public, anon, authenticated, service_role;
revoke all on function private.trg_producto_condiciones_inmutables()
  from public, anon, authenticated, service_role;
revoke all on function private.insertar_condiciones_producto(uuid, jsonb, uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.crear_snapshot_producto_legacy(
  uuid, text, text, text, text, numeric, numeric, date, date
) from public, anon, authenticated, service_role;
revoke all on function private.validar_cabecera_version_producto(
  text, text, date, date
) from public, anon, authenticated, service_role;
revoke all on function private.metadata_condicion_producto(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.producto_inversion_tiene_version_visible(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.producto_inversion_tiene_version_visible(uuid)
  to authenticated;
revoke all on function private.trg_contratos_producto_snapshot()
  from public, anon, authenticated, service_role;

comment on function crm.productos_inversion_gestion_fn() is
  'Contrato JSON v1 anidado producto→versiones→condiciones. Gerencia/lector global ven borradores; otros roles solo historia comercial autorizada.';
comment on function crm.productos_inversion_seleccion_fn() is
  'Selector plano de condiciones activas, publicadas y vigentes para altas contractuales.';
comment on function crm.publicar_version_producto_inversion(uuid, bigint) is
  'Publicación atómica con expected_revision; retira la versión publicada anterior sin reescribir contratos.';
comment on function crm.archivar_producto_inversion(uuid, bigint) is
  'Archivado lógico atómico con expected_revision. Retira borrador/publicada y conserva toda la historia.';
comment on function crm.cerrar_altas_legacy_productos(bigint) is
  'Cierre irreversible del puente para callers antiguos. Ejecutar solo después de migrar CRM y portal a wrappers con producto_condicion_id.';

-- Proyección canónica consumida por la cartera/corrección del CRM. Las columnas
-- existentes conservan orden y semántica; el origen de producto se añade al final.
drop view if exists crm.contratos_cartera;
drop function if exists crm.contratos_cartera_fn();

create function crm.contratos_cartera_fn()
returns table (
  id uuid,
  numero_contrato text,
  cliente_id uuid,
  cliente_nombre text,
  asesor_perfil_id uuid,
  capital numeric,
  moneda text,
  tasa_anual numeric,
  modalidad text,
  tipo_interes text,
  categoria text,
  estado text,
  fecha_inicio date,
  fecha_vencimiento date,
  notas_internas text,
  creado_por uuid,
  creado_en timestamptz,
  producto_condicion_id uuid,
  producto_id uuid,
  producto_codigo text,
  producto_version_id uuid,
  producto_version integer,
  producto_nombre text,
  producto_version_estado text
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    c.id, c.numero_contrato, c.cliente_id, cli.nombre_completo,
    cli.asesor_perfil_id, c.capital, c.moneda, c.tasa_anual, c.modalidad,
    c.tipo_interes, c.categoria, c.estado, c.fecha_inicio,
    c.fecha_vencimiento, c.notas_internas, c.creado_por, c.creado_en,
    c.producto_condicion_id, p.id, p.codigo, v.id, v.numero_version,
    v.nombre, v.estado
  from public.contratos c
  join public.perfiles cli on cli.id = c.cliente_id
  join crm.producto_condiciones pc on pc.id = c.producto_condicion_id
  join crm.producto_versiones v on v.id = pc.version_id
  join crm.productos_inversion p on p.id = v.producto_id
  where (
    (select private.es_lector_global())
    or (select private.rol_crm((select auth.uid()))) = 'gerencia'
    or cli.asesor_perfil_id in (
      select private.vendedor_ids_visibles((select auth.uid()))
    )
    or (
      cli.asesor_perfil_id is null
      and cli.creado_por in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
    )
  );
$function$;

create view crm.contratos_cartera
with (security_invoker = true)
as
select
  id, numero_contrato, cliente_id, cliente_nombre, asesor_perfil_id,
  capital, moneda, tasa_anual, modalidad, tipo_interes, categoria, estado,
  fecha_inicio, fecha_vencimiento, notas_internas, creado_por, creado_en,
  producto_condicion_id, producto_id, producto_codigo, producto_version_id,
  producto_version, producto_nombre, producto_version_estado
from crm.contratos_cartera_fn();

revoke all on function crm.contratos_cartera_fn()
  from public, anon, authenticated, service_role;
grant execute on function crm.contratos_cartera_fn()
  to authenticated, service_role;
revoke all on table crm.contratos_cartera
  from public, anon, authenticated;
grant select on table crm.contratos_cartera
  to authenticated, service_role;

comment on view crm.contratos_cartera is
  'Cartera contractual scopeada con FK, código, nombre y versión del producto; preserva snapshots retirados/legacy para corrección y auditoría.';

commit;

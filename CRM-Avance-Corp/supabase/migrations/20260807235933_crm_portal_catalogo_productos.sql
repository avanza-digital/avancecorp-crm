-- Frontera Portal del catálogo de productos y cierre total de compatibilidad.
--
-- Mantiene separados los poderes intencionales del Portal de los roles CRM:
--   * public.* conserva Admin/Superadmin/Analista del Portal;
--   * crm.* conserva exclusivamente los roles CRM efectivos ya definidos;
--   * cerrar altas legacy también cierra nuevas fotografías por correcciones
--     contractuales, pero no bloquea cambios de metadatos sin términos.

begin;

do $preflight$
begin
  if to_regprocedure('private.rol_crm(uuid)') is null
     or to_regprocedure('private.vendedor_ids_visibles(uuid)') is null
     or to_regprocedure('private.crear_snapshot_producto_legacy(uuid,text,text,text,text,numeric,numeric,date,date)') is null
     or to_regprocedure('private.metadata_condicion_producto(uuid)') is null
     or to_regprocedure('private.puede_gestionar_cuentas_cliente(uuid)') is null
     or to_regprocedure('public.es_admin()') is null
     or to_regprocedure('public.es_analista()') is null
     or to_regprocedure('public.es_superadmin()') is null
     or to_regprocedure('public._sync_contrato_titulares(uuid,jsonb)') is null
     or to_regprocedure('public.crear_contrato(jsonb,jsonb)') is null
     or to_regprocedure('public.actualizar_contrato(uuid,jsonb,jsonb)') is null
     or to_regprocedure('crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)') is null
     or to_regclass('crm.productos_inversion') is null
     or to_regclass('crm.producto_versiones') is null
     or to_regclass('crm.producto_condiciones') is null
     or to_regclass('public.contratos') is null
     or to_regclass('public.cronograma_pagos') is null then
    raise exception 'Faltan dependencias del catálogo versionado o de contratos Portal';
  end if;
end;
$preflight$;

-- El generador contractual compartido liquida el interés compuesto por años
-- exactos y no usa una frecuencia de pago intermedia. El catálogo no puede
-- publicar una combinación que ninguno de los dos portales pueda materializar.
-- Los snapshots legacy quedan fuera: describen historia y nunca se reinterpretan.
alter table crm.producto_condiciones
  add constraint producto_condiciones_compuesto_cronograma_check check (
    es_legacy
    or tipo_interes = 'simple'
    or (
      modalidad = 'anual'
      and plazo_meses >= 12
      and plazo_meses % 12 = 0
    )
  );

-- El helper de P04 tenía un gate anidado imposible para Vendedor/Supervisor:
-- primero exigía acceso CRM, pero dentro solo aceptaba Gerencia o roles Portal.
-- La autorización siguiente separa ambos poderes y usa el alcance canónico para
-- que un vendedor vea solo su cartera y un supervisor su subárbol.
create or replace function private.puede_gestionar_cuentas_cliente(
  p_cliente_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.perfiles cli
      where cli.id = p_cliente_id
        and cli.rol = 'cliente'
        and cli.activo is true
        and (
          -- Poder propio e independiente del Portal compartido.
          (select public.es_admin())
          or (
            (select public.es_analista())
            and (
              cli.asesor_perfil_id = (select auth.uid())
              or (
                cli.asesor_perfil_id is null
                and cli.creado_por = (select auth.uid())
              )
            )
          )
          or (
            private.rol_crm((select auth.uid())) in (
              'vendedor', 'supervisor', 'gerencia'
            )
            and (
              private.rol_crm((select auth.uid())) = 'gerencia'
              or cli.asesor_perfil_id in (
                select private.vendedor_ids_visibles((select auth.uid()))
              )
            )
          )
        )
    );
$function$;

comment on function private.puede_gestionar_cuentas_cliente(uuid) is
  'Autoridad compartida de cuentas: Admin/Superadmin/Analista Portal según cartera, o Vendedor/Supervisor/Gerencia CRM efectivos según vendedor_ids_visibles. Coordinador y Directorio no gestionan.';

revoke all on function private.puede_gestionar_cuentas_cliente(uuid)
  from public, anon, authenticated, service_role;

-- Los wrappers CRM de Productos ya admitían Vendedor/Supervisor, pero los
-- escritores canónicos public.* a los que delegaban solo reconocían roles del
-- Portal o Gerencia. El resultado era una autorización imposible en la segunda
-- capa. Se conserva UNA escritura canónica y se habilita al CRM operativo solo
-- cuando el wrapper ya fijó una condición catalogada en esta misma transacción.
-- Una llamada directa de Vendedor/Supervisor, sin esa condición, sigue cerrada.
create or replace function public.crear_contrato(
  p_contrato jsonb,
  p_cronograma jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_es_analista boolean := (select public.es_analista());
  v_es_admin boolean := (select public.es_admin());
  v_rol_crm text := private.rol_crm(v_uid);
  v_es_gerencia_crm boolean := coalesce(v_rol_crm = 'gerencia', false);
  v_es_crm_catalogado boolean :=
    coalesce(v_rol_crm in ('vendedor', 'supervisor'), false)
    and nullif(
      current_setting('crm.producto_condicion_id', true), ''
    ) is not null;
  v_cliente_id uuid := (p_contrato->>'cliente_id')::uuid;
  v_numero text := nullif(btrim(p_contrato->>'numero_contrato'), '');
  v_categoria text := p_contrato->>'categoria';
  v_anio integer := extract(year from now())::integer;
  v_seq integer;
  v_contrato_id uuid;
  v_cuota jsonb;
begin
  if not (
    v_es_analista
    or v_es_admin
    or v_es_gerencia_crm
    or v_es_crm_catalogado
  ) or not private.puede_gestionar_cuentas_cliente(v_cliente_id) then
    raise insufficient_privilege using
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  if (p_contrato->>'capital')::numeric < 100
     or (p_contrato->>'capital')::numeric > 100000000 then
    raise exception 'El capital debe estar entre 100 y 100,000,000';
  end if;
  if (p_contrato->>'tasa_anual')::numeric <= 0
     or (p_contrato->>'tasa_anual')::numeric > 50 then
    raise exception 'La tasa anual debe estar entre 0 y 50%%';
  end if;

  if v_categoria is null
     or v_categoria not in ('nuevo', 'renovacion', 'upgrade') then
    raise exception
      'Selecciona la categoria del contrato (Nuevo, Renovacion o Upgrade)';
  end if;

  if v_numero is null then
    select
      coalesce(
        max(
          nullif(
            regexp_replace(
              split_part(c.numero_contrato, '-', 3),
              '[^0-9]',
              '',
              'g'
            ),
            ''
          )::integer
        ),
        0
      ) + 1
      into v_seq
    from public.contratos c
    where c.numero_contrato like 'AC-' || v_anio || '-%';

    v_numero := 'AC-' || v_anio || '-' || lpad(v_seq::text, 4, '0');
  end if;

  if exists (
    select 1
    from public.contratos c
    where c.numero_contrato = v_numero
  ) then
    raise exception 'El N de contrato % ya existe', v_numero;
  end if;

  insert into public.contratos (
    cliente_id,
    numero_contrato,
    capital,
    moneda,
    tasa_anual,
    modalidad,
    tipo_interes,
    fecha_inicio,
    fecha_vencimiento,
    notas_internas,
    categoria,
    estado,
    creado_por
  ) values (
    v_cliente_id,
    v_numero,
    (p_contrato->>'capital')::numeric,
    coalesce(nullif(p_contrato->>'moneda', ''), 'PEN'),
    (p_contrato->>'tasa_anual')::numeric,
    p_contrato->>'modalidad',
    coalesce(nullif(p_contrato->>'tipo_interes', ''), 'simple'),
    (p_contrato->>'fecha_inicio')::date,
    (p_contrato->>'fecha_vencimiento')::date,
    nullif(btrim(coalesce(p_contrato->>'notas_internas', '')), ''),
    v_categoria,
    'activo',
    v_uid
  )
  returning id into v_contrato_id;

  if p_cronograma is null or jsonb_array_length(p_cronograma) = 0 then
    raise exception 'El cronograma no puede estar vacio';
  end if;

  for v_cuota in
    select value from jsonb_array_elements(p_cronograma)
  loop
    insert into public.cronograma_pagos (
      contrato_id,
      numero_cuota,
      fecha_programada,
      monto_programado,
      estado,
      tipo
    ) values (
      v_contrato_id,
      (v_cuota->>'numero_cuota')::integer,
      (v_cuota->>'fecha_programada')::date,
      (v_cuota->>'monto_programado')::numeric,
      'pendiente',
      coalesce(nullif(v_cuota->>'tipo', ''), 'cuota')
    );
  end loop;

  if p_contrato ? 'titulares' then
    perform public._sync_contrato_titulares(
      v_contrato_id,
      p_contrato->'titulares'
    );
  end if;

  return jsonb_build_object(
    'id', v_contrato_id,
    'numero_contrato', v_numero
  );
end;
$function$;

create or replace function public.actualizar_contrato(
  p_id uuid,
  p_contrato jsonb,
  p_cronograma jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_es_analista boolean := (select public.es_analista());
  v_es_admin boolean := (select public.es_admin());
  v_rol_crm text := private.rol_crm(v_uid);
  v_es_gerencia_crm boolean := coalesce(v_rol_crm = 'gerencia', false);
  v_es_crm_catalogado boolean :=
    coalesce(v_rol_crm in ('vendedor', 'supervisor'), false)
    and nullif(
      current_setting('crm.producto_condicion_id', true), ''
    ) is not null;
  v_row public.contratos%rowtype;
  v_cuota jsonb;
  v_numero text;
begin
  select *
    into v_row
  from public.contratos c
  where c.id = p_id;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;

  if v_es_admin or v_es_gerencia_crm then
    null;
  elsif v_es_analista or v_es_crm_catalogado then
    if v_row.creado_por is distinct from v_uid then
      raise insufficient_privilege using
        message = 'Solo puedes corregir contratos que tu creaste';
    end if;
    if v_row.creado_en <= now() - interval '5 hours' then
      raise insufficient_privilege using
        message = 'La ventana de correccion de 5 horas ya vencio para este contrato';
    end if;
    if not private.puede_gestionar_cuentas_cliente(v_row.cliente_id) then
      raise insufficient_privilege using
        message = 'Este cliente ya no esta en tu cartera; no puedes corregir su contrato';
    end if;
  else
    raise insufficient_privilege using message = 'No autorizado';
  end if;

  if v_row.estado in ('renovado', 'retirado')
     and not (select public.es_superadmin()) then
    raise exception
      'El contrato esta cerrado (%): no se pueden editar sus terminos',
      v_row.estado;
  end if;

  if (p_contrato->>'capital')::numeric < 100
     or (p_contrato->>'capital')::numeric > 100000000 then
    raise exception 'El capital debe estar entre 100 y 100,000,000';
  end if;
  if (p_contrato->>'tasa_anual')::numeric <= 0
     or (p_contrato->>'tasa_anual')::numeric > 50 then
    raise exception 'La tasa anual debe estar entre 0 y 50%%';
  end if;

  if (p_contrato->>'categoria') is not null
     and (p_contrato->>'categoria') not in (
       'nuevo', 'renovacion', 'upgrade'
     ) then
    raise exception 'Categoria invalida';
  end if;

  v_numero := nullif(btrim(p_contrato->>'numero_contrato'), '');
  if v_numero is not null
     and v_numero is distinct from v_row.numero_contrato then
    if exists (
      select 1
      from public.contratos c
      where c.numero_contrato = v_numero
        and c.id <> p_id
    ) then
      raise exception
        'El N de contrato % ya existe en otro contrato',
        v_numero;
    end if;
  end if;

  update public.contratos
     set numero_contrato = coalesce(v_numero, numero_contrato),
         capital = (p_contrato->>'capital')::numeric,
         moneda = coalesce(nullif(p_contrato->>'moneda', ''), moneda),
         tasa_anual = (p_contrato->>'tasa_anual')::numeric,
         modalidad = p_contrato->>'modalidad',
         tipo_interes = coalesce(
           nullif(p_contrato->>'tipo_interes', ''),
           tipo_interes
         ),
         fecha_inicio = (p_contrato->>'fecha_inicio')::date,
         fecha_vencimiento = (p_contrato->>'fecha_vencimiento')::date,
         notas_internas = nullif(
           btrim(coalesce(p_contrato->>'notas_internas', '')),
           ''
         ),
         categoria = coalesce(
           nullif(p_contrato->>'categoria', ''),
           categoria
         )
   where id = p_id;

  if p_cronograma is not null
     and jsonb_array_length(p_cronograma) > 0 then
    if not exists (
      select 1
      from public.cronograma_pagos cp
      where cp.contrato_id = p_id
        and (cp.estado = 'pagado' or cp.monto_pagado is not null)
    ) then
      delete from public.cronograma_pagos cp
      where cp.contrato_id = p_id;

      for v_cuota in
        select value from jsonb_array_elements(p_cronograma)
      loop
        insert into public.cronograma_pagos (
          contrato_id,
          numero_cuota,
          fecha_programada,
          monto_programado,
          estado,
          tipo
        ) values (
          p_id,
          (v_cuota->>'numero_cuota')::integer,
          (v_cuota->>'fecha_programada')::date,
          (v_cuota->>'monto_programado')::numeric,
          'pendiente',
          coalesce(nullif(v_cuota->>'tipo', ''), 'cuota')
        );
      end loop;
    else
      delete from public.cronograma_pagos cp
      where cp.contrato_id = p_id
        and not (cp.estado = 'pagado' or cp.monto_pagado is not null);

      for v_cuota in
        select je.value
        from jsonb_array_elements(p_cronograma) as je(value)
        where not exists (
          select 1
          from public.cronograma_pagos cp
          where cp.contrato_id = p_id
            and (cp.estado = 'pagado' or cp.monto_pagado is not null)
            and cp.numero_cuota = (je.value->>'numero_cuota')::integer
        )
      loop
        insert into public.cronograma_pagos (
          contrato_id,
          numero_cuota,
          fecha_programada,
          monto_programado,
          estado,
          tipo
        ) values (
          p_id,
          (v_cuota->>'numero_cuota')::integer,
          (v_cuota->>'fecha_programada')::date,
          (v_cuota->>'monto_programado')::numeric,
          'pendiente',
          coalesce(nullif(v_cuota->>'tipo', ''), 'cuota')
        );
      end loop;
    end if;
  end if;

  if p_contrato ? 'titulares' then
    perform public._sync_contrato_titulares(
      p_id,
      p_contrato->'titulares'
    );
  end if;

  return jsonb_build_object('id', p_id, 'ok', true);
end;
$function$;

revoke all on function public.crear_contrato(jsonb, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.actualizar_contrato(uuid, jsonb, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.crear_contrato(jsonb, jsonb)
  to authenticated;
grant execute on function public.actualizar_contrato(uuid, jsonb, jsonb)
  to authenticated;

-- El cierre es irreversible y deja de existir cualquier fallback técnico. No
-- se permite ejecutarlo si todavía no hay al menos una condición comercial que
-- los portales puedan seleccionar, ni si esta migración de callers no terminó.
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
    raise insufficient_privilege using
      message = 'Solo Gerencia puede cerrar la compatibilidad legacy';
  end if;

  if to_regprocedure(
       'public.productos_inversion_seleccion_fn(uuid)'
     ) is null
     or to_regprocedure(
       'public.crear_contrato_producto(uuid,jsonb,jsonb)'
     ) is null
     or to_regprocedure(
       'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)'
     ) is null
     or to_regprocedure(
       'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)'
     ) is null then
    raise exception
      'La frontera catalogada del Portal todavía no está instalada'
      using errcode = '55000';
  end if;

  if not exists (
    select 1
    from crm.producto_condiciones c
    join crm.producto_versiones v on v.id = c.version_id
    join crm.productos_inversion p on p.id = v.producto_id
    where p.estado = 'activo'
      and not p.es_legacy
      and v.estado = 'publicada'
      and v.vigente_desde <= current_date
      and (v.vigente_hasta is null or v.vigente_hasta >= current_date)
      and c.activa
      and not c.es_legacy
  ) then
    raise exception
      'Publica al menos una condición de producto vigente antes de cerrar la compatibilidad legacy'
      using errcode = '23514';
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

comment on function crm.cerrar_altas_legacy_productos(bigint) is
  'Cierre irreversible: exige frontera Portal instalada y al menos una condición comercial publicada/vigente; después no admite altas ni nuevos snapshots legacy por corrección.';

-- Una vez cerrado permite_altas_legacy, la misma bandera impide crear una nueva
-- versión histórica al corregir términos. El trigger solo llama este helper si
-- los términos legacy cambiaron; número, notas, titulares u otros metadatos no
-- contractuales conservan el snapshot y siguen funcionando.
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
  v_permite_legacy boolean;
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

  select p.id, p.permite_altas_legacy
    into v_producto_id, v_permite_legacy
  from crm.productos_inversion p
  where p.codigo = 'HISTORICO-SIN-CATALOGO'
    and p.es_legacy
  for update;
  if not found then
    raise exception 'Falta el producto técnico de contratos históricos'
      using errcode = 'P0001';
  end if;
  if not v_permite_legacy then
    raise exception
      'La compatibilidad legacy está cerrada; selecciona un producto publicado para cambiar términos'
      using errcode = '23514';
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

revoke all on function private.crear_snapshot_producto_legacy(
  uuid, text, text, text, text, numeric, numeric, date, date
) from public, anon, authenticated, service_role;

-- Selector propio del Portal. Sin contrato devuelve solo condiciones vigentes;
-- con contrato agrega su condición actual aunque sea histórica/retirada. Así la
-- UI puede explicar el origen sin hacer visibles borradores ni historia ajena.
create or replace function public.productos_inversion_seleccion_fn(
  p_contrato_id uuid default null
)
returns table (
  condicion_id uuid,
  producto_id uuid,
  producto_codigo text,
  producto_revision bigint,
  version_id uuid,
  numero_version integer,
  version_nombre text,
  version_estado text,
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
  tasa_maxima numeric,
  es_actual boolean,
  es_legacy boolean,
  seleccionable_nuevo boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_actual uuid;
begin
  if v_actor is null
     or not ((select public.es_admin()) or (select public.es_analista())) then
    raise exception 'No autorizado para consultar productos del Portal'
      using errcode = '42501';
  end if;

  if p_contrato_id is not null then
    select ct.producto_condicion_id
      into v_actual
    from public.contratos ct
    join public.perfiles cli on cli.id = ct.cliente_id
    where ct.id = p_contrato_id
      and (
        (select public.es_admin())
        or (
          (select public.es_analista())
          and ct.creado_por = v_actor
          and ct.creado_en > now() - interval '5 hours'
          and (
            cli.asesor_perfil_id = v_actor
            or (
              cli.asesor_perfil_id is null
              and cli.creado_por = v_actor
            )
          )
        )
      );
    if not found then
      raise exception 'Contrato no encontrado o fuera de tu alcance Portal'
        using errcode = '42501';
    end if;
  end if;

  return query
  select
    q.condicion_id, q.producto_id, q.producto_codigo,
    q.producto_revision, q.version_id, q.numero_version, q.version_nombre,
    q.version_estado,
    q.vigente_desde, q.vigente_hasta, q.categoria, q.moneda,
    q.plazo_meses, q.modalidad, q.tipo_interes, q.capital_minimo,
    q.capital_maximo, q.tasa_referencia, q.tasa_minima, q.tasa_maxima,
    coalesce(q.condicion_id = v_actual, false),
    q.es_legacy,
    q.seleccionable_nuevo
  from (
    select
      c.id as condicion_id,
      p.id as producto_id,
      p.codigo as producto_codigo,
      p.revision as producto_revision,
      v.id as version_id,
      v.numero_version,
      v.nombre as version_nombre,
      v.estado as version_estado,
      v.vigente_desde,
      v.vigente_hasta,
      c.categoria,
      c.moneda,
      c.plazo_meses,
      c.modalidad,
      c.tipo_interes,
      c.capital_minimo,
      c.capital_maximo,
      c.tasa_referencia,
      c.tasa_minima,
      c.tasa_maxima,
      c.es_legacy,
      (
        p.estado = 'activo'
        and not p.es_legacy
        and v.estado = 'publicada'
        and v.vigente_desde <= current_date
        and (v.vigente_hasta is null or v.vigente_hasta >= current_date)
        and c.activa
        and not c.es_legacy
      ) as seleccionable_nuevo
    from crm.producto_condiciones c
    join crm.producto_versiones v on v.id = c.version_id
    join crm.productos_inversion p on p.id = v.producto_id
  ) q
  where q.seleccionable_nuevo
     or q.condicion_id = v_actual
  order by
    coalesce(q.condicion_id = v_actual, false) desc,
    q.categoria nulls last,
    q.producto_codigo,
    q.numero_version desc;
end;
$function$;

comment on function public.productos_inversion_seleccion_fn(uuid) is
  'Selector Portal: Admin/Superadmin/Analista. Devuelve condiciones seleccionables y, al editar, la condición actual autorizada con flags explícitos.';

create or replace function public.crear_contrato_producto(
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
  v_contrato_id uuid;
  v_condicion_resultante uuid;
  v_config_anterior text := current_setting('crm.producto_condicion_id', true);
begin
  if not ((select public.es_admin()) or (select public.es_analista())) then
    raise insufficient_privilege using message = 'No autorizado para crear contratos desde el Portal';
  end if;
  if p_producto_condicion_id is null then
    raise exception 'Selecciona un producto de inversión'
      using errcode = '22023';
  end if;

  perform pg_catalog.set_config(
    'crm.producto_condicion_id', p_producto_condicion_id::text, true
  );
  v_resultado := public.crear_contrato(p_contrato, p_cronograma);
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', coalesce(v_config_anterior, ''), true
  );

  v_contrato_id := (v_resultado->>'id')::uuid;
  select ct.producto_condicion_id into v_condicion_resultante
  from public.contratos ct
  where ct.id = v_contrato_id;
  if not found then
    raise exception 'Contrato no encontrado después del alta' using errcode = 'P0002';
  end if;
  return v_resultado
    || private.metadata_condicion_producto(v_condicion_resultante);
exception when others then
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', coalesce(v_config_anterior, ''), true
  );
  raise;
end;
$function$;

comment on function public.crear_contrato_producto(uuid, jsonb, jsonb) is
  'Alta Portal catalogada; conserva la autorización de public.crear_contrato y fija la condición en la misma transacción.';

create or replace function public.actualizar_contrato_producto(
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
  v_config_anterior text := current_setting('crm.producto_condicion_id', true);
begin
  if not ((select public.es_admin()) or (select public.es_analista())) then
    raise insufficient_privilege using message = 'No autorizado para actualizar contratos desde el Portal';
  end if;
  if p_producto_condicion_id is null then
    raise exception 'Selecciona un producto de inversión'
      using errcode = '22023';
  end if;

  perform pg_catalog.set_config(
    'crm.producto_condicion_id', p_producto_condicion_id::text, true
  );
  v_resultado := public.actualizar_contrato(p_id, p_contrato, p_cronograma);
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', coalesce(v_config_anterior, ''), true
  );

  select ct.producto_condicion_id into v_condicion_resultante
  from public.contratos ct
  where ct.id = p_id;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
  return v_resultado
    || private.metadata_condicion_producto(v_condicion_resultante);
exception when others then
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', coalesce(v_config_anterior, ''), true
  );
  raise;
end;
$function$;

comment on function public.actualizar_contrato_producto(uuid, uuid, jsonb, jsonb) is
  'Corrección Portal catalogada; conserva Admin/Superadmin/Analista, cartera, ventana y cierres de public.actualizar_contrato.';

create or replace function public.actualizar_contrato_con_cuenta_producto(
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
  v_condicion_resultante uuid;
  v_resultado jsonb;
  v_config_anterior text := current_setting('crm.producto_condicion_id', true);
begin
  if not ((select public.es_admin()) or (select public.es_analista())) then
    raise insufficient_privilege using message = 'No autorizado para actualizar contratos con cuenta desde el Portal';
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
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', coalesce(v_config_anterior, ''), true
  );

  select ct.producto_condicion_id into v_condicion_resultante
  from public.contratos ct
  where ct.id = p_id;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
  v_resultado := jsonb_build_object('id', p_id, 'ok', true)
    || private.metadata_condicion_producto(v_condicion_resultante);
  return v_resultado;
exception when others then
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', coalesce(v_config_anterior, ''), true
  );
  raise;
end;
$function$;

comment on function public.actualizar_contrato_con_cuenta_producto(
  uuid, uuid, jsonb, jsonb
) is
  'Corrección Portal catalogada que además conserva la coherencia de la cuenta bancaria contractual.';

revoke all on function public.productos_inversion_seleccion_fn(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.crear_contrato_producto(uuid, jsonb, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.actualizar_contrato_producto(
  uuid, uuid, jsonb, jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.actualizar_contrato_con_cuenta_producto(
  uuid, uuid, jsonb, jsonb
) from public, anon, authenticated, service_role;

grant execute on function public.productos_inversion_seleccion_fn(uuid)
  to authenticated;
grant execute on function public.crear_contrato_producto(uuid, jsonb, jsonb)
  to authenticated;
grant execute on function public.actualizar_contrato_producto(
  uuid, uuid, jsonb, jsonb
) to authenticated;
grant execute on function public.actualizar_contrato_con_cuenta_producto(
  uuid, uuid, jsonb, jsonb
) to authenticated;

commit;

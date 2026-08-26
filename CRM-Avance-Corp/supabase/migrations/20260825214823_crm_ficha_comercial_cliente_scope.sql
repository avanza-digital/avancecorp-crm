-- F4.1 · Ficha comercial del cliente con una frontera de lectura propia.
--
-- La lista de Mi cartera ya llega recortada por crm.clientes_basicos_fn(),
-- pero la ficha reutilizaba public.perfiles para completar la identidad. Esa
-- tabla pertenece al Portal: un vendedor directo puede leer su
-- cliente, pero un supervisor, Gerencia o Directorio no comparten necesariamente
-- esa policy. Además, leer la tabla completa acerca columnas bancarias a una
-- pantalla que solo necesita identidad y contacto.
--
-- Esta migración crea una proyección mínima, sin banca ni domicilio legal, y
-- copia EXACTAMENTE el alcance vigente de clientes_basicos_fn:
--   · Directorio lee toda la cartera;
--   · Gerencia lee toda la cartera;
--   · supervisor/vendedor leen clientes cuyo asesor está en su ámbito visible;
--   · coordinador, miembro revocado, ajeno al CRM y anon no reciben acceso.
--
-- El mismo helper de alcance protege la ficha y el historial: una reasignación
-- entrega las gestiones al asesor actual y deja fuera al asesor anterior.
-- Los helpers que cruzan public.perfiles viven en private y fijan search_path=''.
-- La única función expuesta por la Data API es SECURITY INVOKER. Los grants se
-- declaran de forma explícita porque Supabase está retirando la exposición
-- automática de objetos nuevos.

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

do $preflight$
begin
  if to_regprocedure('private.rol_crm(uuid)') is null
     or to_regprocedure('private.es_lector_global()') is null
     or to_regprocedure('private.vendedor_ids_visibles(uuid)') is null
     or to_regprocedure('private.es_destino_crm_activo(uuid,text[])') is null
     or to_regprocedure('private.membresia_crm_revocada()') is null
     or to_regprocedure('public.es_analista()') is null
     or to_regprocedure('public.es_gestor_cartera()') is null
     or to_regprocedure('public.crear_contrato(jsonb,jsonb)') is null
     or to_regprocedure('public.actualizar_contrato(uuid,jsonb,jsonb)') is null
     or to_regprocedure('public.puede_ver_contrato(uuid)') is null
     or to_regprocedure('private.puede_gestionar_cuentas_cliente(uuid)') is null
     or to_regprocedure('private.puede_leer_contrato_pdf(uuid)') is null
     or to_regprocedure('private.crear_job_contrato_pdf_base(uuid,uuid)') is null
     or to_regprocedure('private.crear_revision_contrato_pdf_base(uuid,uuid)') is null
     or to_regprocedure('crm.cuentas_bancarias_cliente_fn(uuid,text)') is null
     or to_regprocedure('crm.contratos_cartera_fn()') is null then
    raise exception 'PREFLIGHT: faltan helpers canónicos de alcance CRM';
  end if;

  if to_regprocedure(
       'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'
     ) is null
     or (
       to_regprocedure(
         'crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb)'
       ) is null
       and to_regprocedure(
         'crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb,timestamptz)'
       ) is null
     )
     or to_regprocedure(
       'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)'
     ) is null
     or to_regprocedure(
       'crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)'
     ) is null then
    raise exception 'PREFLIGHT: faltan los flujos atómicos canónicos de contratos';
  end if;

  if to_regclass('public.perfiles') is null
     or to_regclass('public.contratos') is null
     or to_regclass('public.cronograma_pagos') is null
     or to_regclass('public.contrato_titulares') is null
     or to_regclass('crm.cuentas_bancarias') is null
     or to_regclass('crm.actividades_cliente') is null
     or to_regclass('crm.operaciones_cartera') is null then
    raise exception 'PREFLIGHT: faltan perfiles, contratos o historial comercial';
  end if;

  if exists (
    select 1
    from unnest(array[
      'id', 'nombres', 'apellidos', 'nombre_completo', 'tipo_documento',
      'dni', 'correo', 'telefono', 'asesor_perfil_id',
      'creado_por', 'activo', 'creado_en', 'rol'
    ]) as requerida(nombre)
    where not exists (
      select 1
      from information_schema.columns c
      where c.table_schema = 'public'
        and c.table_name = 'perfiles'
        and c.column_name = requerida.nombre
    )
  ) then
    raise exception 'PREFLIGHT: public.perfiles no conserva el contrato requerido por la ficha';
  end if;
end;
$preflight$;

drop policy if exists actividades_cliente_select on crm.actividades_cliente;
drop policy if exists operaciones_cartera_select on crm.operaciones_cartera;
drop function if exists crm.cliente_ficha_fn(uuid);
drop function if exists private.cliente_ficha_autorizada_fn(uuid);
drop function if exists private.puede_consultar_cliente_fn(uuid);

create function private.puede_consultar_cliente_fn(
  p_cliente_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_lector boolean := private.es_lector_global();
  v_visibles uuid[] := '{}'::uuid[];
begin
  if v_uid is null
     or (
       not coalesce(
         v_rol = any (array['vendedor', 'supervisor', 'gerencia']::text[]),
         false
       )
       and not coalesce(v_lector, false)
     ) then
    raise insufficient_privilege using message = 'No autorizado';
  end if;

  if v_rol in ('vendedor', 'supervisor') then
    v_visibles := array(
      select private.vendedor_ids_visibles(v_uid)
    );
  end if;

  return exists (
    select 1
    from public.perfiles p
    where p.id = p_cliente_id
      and p.rol = 'cliente'
      and (
        v_lector
        or v_rol = 'gerencia'
        or p.asesor_perfil_id = any (v_visibles)
      )
  );
end;
$function$;

-- Cuerpo canónico vigente de public.actualizar_contrato. El permiso atómico
-- no reemplaza autoría, ventana de cinco horas, cartera, catálogo ni cierre
-- documental; solo demuestra que la corrección libre llegó desde la RPC PDF.
create or replace function public.actualizar_contrato(
  p_id uuid,
  p_contrato jsonb,
  p_cronograma jsonb
)
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
  v_es_crm_atomico boolean := false;
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

  v_es_crm_atomico :=
    coalesce(v_rol_crm in ('vendedor', 'supervisor'), false)
    and private.es_destino_crm_activo(
      v_uid,
      array['vendedor', 'supervisor']::text[]
    )
    and private.tiene_capacidad_contrato_atomico(
      'correccion',
      v_row.cliente_id,
      p_id
    );

  if v_es_gestor_cartera or v_es_gerencia_crm then
    -- P04: una membresía CRM revocada prevalece sobre el poder de Portal
    -- también para corregir términos, no solo para la banca y el alta.
    if (select private.membresia_crm_revocada()) then
      raise insufficient_privilege using
        message = 'Tu membresía CRM fue revocada; no puedes corregir contratos';
    end if;
  elsif v_es_analista or v_es_crm_catalogado or v_es_crm_atomico then
    if v_row.creado_por is distinct from v_uid then
      raise insufficient_privilege using
        message = 'Solo puedes corregir contratos que tú creaste';
    end if;
    if v_row.creado_en <= now() - interval '5 hours' then
      raise insufficient_privilege using
        message = 'La ventana de corrección de 5 horas ya venció para este contrato';
    end if;
    if not private.puede_gestionar_cuentas_cliente(v_row.cliente_id) then
      raise insufficient_privilege using
        message = 'Este cliente ya no está en tu cartera; no puedes corregir su contrato';
    end if;
  else
    raise insufficient_privilege using
      message = 'Abre la ficha del cliente para corregir este contrato';
  end if;

  if v_row.estado in ('renovado', 'retirado')
     and not (select public.es_superadmin()) then
    raise exception
      'El contrato está cerrado (%): no se pueden editar sus términos',
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
    raise exception 'Categoría inválida';
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

comment on function private.puede_consultar_cliente_fn(uuid) is
  'Autoriza por la asignación actual del cliente: ámbito global para Directorio/Gerencia y subárbol para supervisor/vendedor; creado_por no concede lectura.';

revoke all on function private.puede_consultar_cliente_fn(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.puede_consultar_cliente_fn(uuid)
  to authenticated;

create function private.cliente_ficha_autorizada_fn(
  p_cliente_id uuid
)
returns table (
  id uuid,
  nombres text,
  apellidos text,
  nombre_completo text,
  tipo_documento text,
  dni text,
  correo text,
  telefono text,
  asesor_perfil_id uuid,
  activo boolean,
  creado_en timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
rows 1
as $function$
begin
  if not private.puede_consultar_cliente_fn(p_cliente_id) then return; end if;
  return query
  select
    p.id,
    p.nombres,
    p.apellidos,
    p.nombre_completo,
    p.tipo_documento,
    p.dni,
    p.correo,
    p.telefono,
    p.asesor_perfil_id,
    p.activo,
    p.creado_en
  from public.perfiles p
  where p.id = p_cliente_id
    and p.rol = 'cliente';
end;
$function$;

comment on function private.cliente_ficha_autorizada_fn(uuid) is
  'Proyección mínima de identidad/contacto para una ficha comercial. SECURITY DEFINER interno, search_path vacío y alcance idéntico a crm.clientes_basicos_fn; no devuelve banca ni domicilio legal.';

revoke all on function private.cliente_ficha_autorizada_fn(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.cliente_ficha_autorizada_fn(uuid)
  to authenticated;

create policy actividades_cliente_select on crm.actividades_cliente
  for select to authenticated
  using (private.puede_consultar_cliente_fn(cliente_id));

comment on policy actividades_cliente_select on crm.actividades_cliente is
  'El historial sigue al asesor actual del cliente; una reasignación revoca al asesor anterior y habilita al nuevo dentro de su ámbito.';

create function crm.cliente_ficha_fn(
  p_cliente_id uuid
)
returns table (
  id uuid,
  nombres text,
  apellidos text,
  nombre_completo text,
  tipo_documento text,
  dni text,
  correo text,
  telefono text,
  asesor_perfil_id uuid,
  activo boolean,
  creado_en timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $function$
  select *
  from private.cliente_ficha_autorizada_fn(p_cliente_id);
$function$;

comment on function crm.cliente_ficha_fn(uuid) is
  'Ficha comercial de un cliente dentro del ámbito vivo del actor. Identidad y contacto, sin banca ni domicilio legal; 0 filas para inexistente o fuera de cartera.';

revoke all on function crm.cliente_ficha_fn(uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.cliente_ficha_fn(uuid)
  to authenticated;

-- El historial completo sigue a la asignación VIVA del cliente. El vendedor
-- nuevo recibe también renovaciones/aumentos anteriores; el anterior deja de
-- verlos. vendedor_id conserva atribución histórica, nunca autoridad.
create policy operaciones_cartera_select on crm.operaciones_cartera
  for select to authenticated
  using (private.puede_consultar_cliente_fn(cliente_id));

comment on policy operaciones_cartera_select on crm.operaciones_cartera is
  'Renovaciones y aumentos siguen la asignación actual del cliente; vendedor_id es atribución histórica, no permiso.';

-- Las reasignaciones son hechos del mismo historial postventa. Pueden nacer
-- desde un actor de Portal o desde sistema, por eso vendedor_id es opcional en
-- este único tipo de evento; creado_por conserva al actor cuando existe.
alter table crm.actividades_cliente
  alter column vendedor_id drop not null;
alter table crm.actividades_cliente
  drop constraint if exists actividades_cliente_tipo_check;
alter table crm.actividades_cliente
  add constraint actividades_cliente_tipo_check check (tipo in (
    'llamada_realizada', 'llamada_no_contestada', 'whatsapp_enviado',
    'whatsapp_recibido', 'reunion_realizada', 'nota', 'reasignacion'
  ));

comment on column crm.actividades_cliente.vendedor_id is
  'Responsable comercial del hecho. Puede ser null únicamente para una reasignación iniciada por sistema o por un actor ajeno al equipo CRM.';

create or replace function private.trg_cliente_historial_reasignacion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_responsable uuid := coalesce(new.asesor_perfil_id, old.asesor_perfil_id);
  v_anterior text;
  v_nuevo text;
  v_detalle text;
begin
  if new.rol <> 'cliente'
     or new.asesor_perfil_id is not distinct from old.asesor_perfil_id then
    return new;
  end if;

  select p.nombre_completo into v_anterior
  from public.perfiles p where p.id = old.asesor_perfil_id;
  select p.nombre_completo into v_nuevo
  from public.perfiles p where p.id = new.asesor_perfil_id;

  if v_responsable is not null
     and not exists (select 1 from crm.equipo e where e.perfil_id = v_responsable) then
    v_responsable := null;
  end if;

  v_detalle := case
    when old.asesor_perfil_id is null then
      format('Cliente asignado a %s.', coalesce(v_nuevo, 'un nuevo asesor'))
    when new.asesor_perfil_id is null then
      format('Cliente quedó sin asesor. Antes: %s.', coalesce(v_anterior, 'asesor anterior'))
    else
      format(
        'Cliente reasignado de %s a %s.',
        coalesce(v_anterior, 'asesor anterior'),
        coalesce(v_nuevo, 'nuevo asesor')
      )
  end;

  insert into crm.actividades_cliente (
    cliente_id, vendedor_id, tarea_id, tipo, detalle, creado_por
  ) values (
    new.id, v_responsable, null, 'reasignacion', v_detalle, (select auth.uid())
  );
  return new;
end;
$function$;

revoke all on function private.trg_cliente_historial_reasignacion()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_zz_perfiles_cliente_historial_reasignacion on public.perfiles;
create trigger trg_zz_perfiles_cliente_historial_reasignacion
after update of asesor_perfil_id on public.perfiles
for each row execute function private.trg_cliente_historial_reasignacion();

-- Un contrato, su cronograma y sus co-titulares siguen exactamente la
-- asignación actual del cliente. Haber creado al cliente no concede lectura.
-- La vista depende del tipo de retorno de la función; se recrean juntas para
-- publicar revision_contrato sin dejar una firma antigua sobrecargada.
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
  revision_contrato timestamptz,
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
    coalesce(c.actualizado_en, c.creado_en, 'epoch'::timestamptz),
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
  );
$function$;

comment on function crm.contratos_cartera_fn() is
  'Cartera contractual por asignación actual. revision_contrato es el comprobante de vigencia para corregir sin pisar cambios de otra sesión; creado_por no concede lectura.';

revoke all on function crm.contratos_cartera_fn()
  from public, anon, authenticated, service_role;
grant execute on function crm.contratos_cartera_fn()
  to authenticated, service_role;

create view crm.contratos_cartera
with (security_invoker = true)
as
select
  id,
  numero_contrato,
  cliente_id,
  cliente_nombre,
  asesor_perfil_id,
  capital,
  moneda,
  tasa_anual,
  modalidad,
  tipo_interes,
  categoria,
  estado,
  fecha_inicio,
  fecha_vencimiento,
  notas_internas,
  creado_por,
  creado_en,
  revision_contrato,
  producto_condicion_id,
  producto_id,
  producto_codigo,
  producto_version_id,
  producto_version,
  producto_nombre,
  producto_version_estado
from crm.contratos_cartera_fn();

comment on view crm.contratos_cartera is
  'Vista invoker de contratos visibles. revision_contrato debe volver a enviarse al corregir para evitar sobrescribir una versión más nueva.';

revoke all on table crm.contratos_cartera
  from public, anon, authenticated, service_role;
grant select on table crm.contratos_cartera
  to authenticated, service_role;

create or replace function crm.cronograma_contrato_fn(p_contrato_id uuid)
returns table (
  id uuid,
  numero_cuota integer,
  fecha_programada date,
  monto_programado numeric,
  estado text,
  tipo text,
  fecha_pago_real date,
  monto_pagado numeric
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    cp.id, cp.numero_cuota, cp.fecha_programada, cp.monto_programado,
    cp.estado, cp.tipo, cp.fecha_pago_real, cp.monto_pagado
  from public.cronograma_pagos cp
  where cp.contrato_id = p_contrato_id
    and exists (
      select 1 from crm.contratos_cartera_fn() cc
      where cc.id = p_contrato_id
    )
  order by cp.numero_cuota;
$function$;

create or replace function crm.titulares_contrato_fn(p_contrato_id uuid)
returns table (
  id uuid,
  orden smallint,
  nombre_completo text,
  tipo_documento text,
  documento text
)
language sql
stable
security definer
set search_path = ''
as $function$
  select t.id, t.orden, t.nombre_completo, t.tipo_documento, t.documento
  from public.contrato_titulares t
  where t.contrato_id = p_contrato_id
    and exists (
      select 1 from crm.contratos_cartera_fn() cc
      where cc.id = p_contrato_id
    )
  order by t.orden;
$function$;

revoke all on function crm.cronograma_contrato_fn(uuid)
  from public, anon, authenticated, service_role;
revoke all on function crm.titulares_contrato_fn(uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.cronograma_contrato_fn(uuid)
  to authenticated, service_role;
grant execute on function crm.titulares_contrato_fn(uuid)
  to authenticated, service_role;

comment on function crm.cronograma_contrato_fn(uuid) is
  'Cronograma de un contrato visible en la cartera actual; fuera de ámbito devuelve cero filas.';
comment on function crm.titulares_contrato_fn(uuid) is
  'Co-titulares de un contrato visible en la cartera actual; fuera de ámbito devuelve cero filas.';

create or replace function public.puede_ver_contrato(p_contrato_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
    and not (select private.membresia_crm_revocada())
    and exists (
      select 1
      from public.contratos c
      left join public.perfiles cli on cli.id = c.cliente_id
      where c.id = p_contrato_id
        and (
          (select public.es_gestor_cartera())
          or c.cliente_id = (select auth.uid())
          or (
            (select public.es_analista())
            and cli.rol = 'cliente'
            and cli.asesor_perfil_id = (select auth.uid())
          )
          or (select private.es_lector_global())
          or private.rol_crm((select auth.uid())) = 'gerencia'
          or (
            private.rol_crm((select auth.uid())) in ('vendedor', 'supervisor')
            and cli.asesor_perfil_id in (
              select private.vendedor_ids_visibles((select auth.uid()))
            )
          )
        )
    );
$function$;

comment on function public.puede_ver_contrato(uuid) is
  'Lectura contractual por poder Portal o asignación CRM actual. Una membresía CRM revocada prevalece y creado_por nunca concede acceso.';

-- Leer banca y operar son decisiones distintas: un supervisor conserva el
-- contexto de un cliente cuyo asesor fue desactivado, pero no puede registrar
-- ni corregir inversiones hasta que el cliente tenga un responsable activo.
create or replace function private.puede_consultar_cuentas_cliente_fn(
  p_cliente_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
    and not (select private.membresia_crm_revocada())
    and exists (
      select 1
      from public.perfiles cli
      where cli.id = p_cliente_id
        and cli.rol = 'cliente'
        and cli.activo is true
        and (
          (select public.es_gestor_cartera())
          or (
            (select public.es_analista())
            and cli.asesor_perfil_id = (select auth.uid())
          )
          or private.rol_crm((select auth.uid())) = 'gerencia'
          or (
            private.rol_crm((select auth.uid())) in ('vendedor', 'supervisor')
            and cli.asesor_perfil_id in (
              select private.vendedor_ids_visibles((select auth.uid()))
            )
          )
        )
    );
$function$;

comment on function private.puede_consultar_cuentas_cliente_fn(uuid) is
  'Autoriza solo la consulta bancaria de un cliente activo por asignación actual. Un asesor inactivo sigue visible para su supervisor; creado_por nunca concede acceso.';

revoke all on function private.puede_consultar_cuentas_cliente_fn(uuid)
  from public, anon, authenticated, service_role;

-- El helper histórico conserva su nombre porque ya es la autoridad de las
-- rutas de alta/corrección. Ahora exige también que la asignación apunte a un
-- vendedor o supervisor activo: la interfaz deja de ser el único candado.
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
    and not (select private.membresia_crm_revocada())
    and exists (
      select 1
      from public.perfiles cli
      where cli.id = p_cliente_id
        and cli.rol = 'cliente'
        and cli.activo is true
        and private.es_destino_crm_activo(
          cli.asesor_perfil_id,
          array['vendedor', 'supervisor']::text[]
        )
        and (
          (select public.es_gestor_cartera())
          or (
            (select public.es_analista())
            and cli.asesor_perfil_id = (select auth.uid())
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
  'Autoriza mutaciones contractuales solo con cliente y asesor activos dentro de la asignación actual. La revocación CRM prevalece; creado_por es solo trazabilidad.';

revoke all on function private.puede_gestionar_cuentas_cliente(uuid)
  from public, anon, authenticated, service_role;

-- El alta/corrección libre no debe fingir una selección de catálogo para que
-- el trigger pueda crear el snapshot legacy. Tampoco se puede abrir
-- public.crear_contrato/actualizar_contrato a cualquier perfil comercial. La
-- capacidad siguiente existe únicamente mientras el wrapper PDF delega en el
-- escritor efectivo y queda ligada al actor, backend, transacción y objetivo
-- exactos. El token de sesión por sí solo no sirve: debe existir su fila
-- privada, que los roles API no pueden insertar ni consultar.
create table if not exists private.contrato_escritura_atomica_capacidades (
  token uuid primary key,
  backend_pid integer not null,
  transaccion_id bigint not null,
  actor_id uuid not null,
  operacion text not null,
  cliente_id uuid not null,
  contrato_id uuid,
  constraint contrato_escritura_atomica_operacion_check check (
    (operacion = 'alta' and contrato_id is null)
    or (operacion = 'correccion' and contrato_id is not null)
  )
);

alter table private.contrato_escritura_atomica_capacidades
  enable row level security;

comment on table private.contrato_escritura_atomica_capacidades is
  'Capacidades efímeras de alta/corrección contractual: solo viven durante la delegación del wrapper PDF y se eliminan antes de devolver el resultado.';

revoke all on table private.contrato_escritura_atomica_capacidades
  from public, anon, authenticated, service_role;

create or replace function private.tiene_capacidad_contrato_atomico(
  p_operacion text,
  p_cliente_id uuid,
  p_contrato_id uuid default null
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_token_text text := nullif(
    current_setting('crm.contrato_escritura_atomica_token', true),
    ''
  );
  v_token uuid;
begin
  if v_token_text is null
     or (select auth.uid()) is null
     or p_cliente_id is null then
    return false;
  end if;

  begin
    v_token := v_token_text::uuid;
  exception when invalid_text_representation then
    return false;
  end;

  return exists (
    select 1
    from private.contrato_escritura_atomica_capacidades c
    where c.token = v_token
      and c.backend_pid = pg_catalog.pg_backend_pid()
      and c.transaccion_id = pg_catalog.txid_current()
      and c.actor_id = (select auth.uid())
      and c.operacion = p_operacion
      and c.cliente_id = p_cliente_id
      and c.contrato_id is not distinct from p_contrato_id
  );
end;
$function$;

comment on function private.tiene_capacidad_contrato_atomico(text,uuid,uuid) is
  'Valida una capacidad efímera por token, actor, backend, transacción, operación y cliente/contrato exactos. Un GUC fabricado sin fila privada siempre falla.';

revoke all on function private.tiene_capacidad_contrato_atomico(text,uuid,uuid)
  from public, anon, authenticated, service_role;

-- Cuerpo canónico vigente de public.crear_contrato (F4), con una sola
-- ampliación: el vendedor/supervisor activo puede usar el contrato libre
-- únicamente cuando el wrapper PDF mantiene una capacidad exacta. El camino
-- catalogado y los poderes Portal/Gerencia conservan sus gates anteriores.
create or replace function public.crear_contrato(
  p_contrato jsonb,
  p_cronograma jsonb
)
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
  v_es_crm_atomico boolean := false;
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
  v_origen_revision_esperada timestamptz;
  v_origen_revision_actual timestamptz;
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

  v_es_crm_atomico :=
    coalesce(v_rol_crm in ('vendedor', 'supervisor'), false)
    and private.es_destino_crm_activo(
      v_uid,
      array['vendedor', 'supervisor']::text[]
    )
    and private.tiene_capacidad_contrato_atomico(
      'alta',
      v_cliente_id,
      null
    );

  if not (
    v_es_analista
    or v_es_gestor_cartera
    or v_es_gerencia_crm
    or v_es_crm_catalogado
    or v_es_crm_atomico
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
      v_origen_revision_esperada :=
        (p_contrato->>'contrato_origen_revision')::timestamptz;
      v_capital_renovado := (p_contrato->>'capital_renovado')::numeric;
      v_capital_adicional := coalesce((p_contrato->>'capital_adicional')::numeric, 0);
    exception when invalid_text_representation then
      raise exception 'Completa el contrato anterior, su versión vigente y los capitales de la renovación'
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
    v_origen_revision_actual := coalesce(
      v_origen.actualizado_en,
      v_origen.creado_en,
      'epoch'::timestamptz
    );
    if v_origen_revision_esperada is null
       or v_origen_revision_esperada is distinct from v_origen_revision_actual then
      raise exception using
        errcode = '40001',
        message = 'El contrato anterior cambió desde que preparaste la renovación. Recarga la información antes de confirmar.';
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

  -- producto_condicion_id se omite de forma deliberada. Si el wrapper libre no
  -- eligió catálogo, trg_contratos_producto_snapshot crea un snapshot legacy
  -- inmutable con los términos confirmados.
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

-- Los dos wrappers PDF son las únicas funciones que emiten la capacidad. La
-- restauran incluso si el escritor interno falla, antes de reservar el job o
-- la revisión documental.
create or replace function crm.crear_contrato_con_cuenta_pdf_v2(
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
  v_actor_id uuid := (select auth.uid());
  v_cliente_id uuid;
  v_capacidad_token uuid := pg_catalog.gen_random_uuid();
  v_capacidad_anterior text := current_setting(
    'crm.contrato_escritura_atomica_token',
    true
  );
  v_resultado jsonb;
  v_contrato_id uuid;
  v_pdf jsonb;
begin
  if v_actor_id is null then
    raise insufficient_privilege using message = 'Sesión no válida';
  end if;
  if p_contrato is null or jsonb_typeof(p_contrato) <> 'object' then
    raise exception 'Faltan los datos del contrato' using errcode = '22023';
  end if;
  begin
    v_cliente_id := (p_contrato->>'cliente_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'Selecciona un cliente válido' using errcode = '22023';
  end;
  if v_cliente_id is null then
    raise exception 'Selecciona un cliente válido' using errcode = '22023';
  end if;

  insert into private.contrato_escritura_atomica_capacidades (
    token,
    backend_pid,
    transaccion_id,
    actor_id,
    operacion,
    cliente_id,
    contrato_id
  ) values (
    v_capacidad_token,
    pg_catalog.pg_backend_pid(),
    pg_catalog.txid_current(),
    v_actor_id,
    'alta',
    v_cliente_id,
    null
  );
  perform set_config(
    'crm.contrato_escritura_atomica_token',
    v_capacidad_token::text,
    true
  );

  begin
    -- Contrato, cronograma, cuenta, vínculo, snapshot y job se confirman o se
    -- revierten juntos dentro de esta misma transacción.
    v_resultado := crm.crear_contrato_con_cuenta(
      p_contrato,
      p_cronograma,
      p_cuenta
    );
  exception when others then
    delete from private.contrato_escritura_atomica_capacidades
    where token = v_capacidad_token;
    perform set_config(
      'crm.contrato_escritura_atomica_token',
      coalesce(v_capacidad_anterior, ''),
      true
    );
    raise;
  end;

  delete from private.contrato_escritura_atomica_capacidades
  where token = v_capacidad_token;
  perform set_config(
    'crm.contrato_escritura_atomica_token',
    coalesce(v_capacidad_anterior, ''),
    true
  );

  begin
    v_contrato_id := (v_resultado->>'id')::uuid;
  exception when invalid_text_representation then
    raise exception 'El alta no devolvió un contrato válido'
      using errcode = 'P0001';
  end;
  if v_contrato_id is null then
    raise exception 'El alta no devolvió un contrato válido'
      using errcode = 'P0001';
  end if;

  v_pdf := private.crear_job_contrato_pdf_base(v_contrato_id, v_actor_id);
  return v_resultado || jsonb_build_object('pdf', v_pdf);
end;
$function$;

drop function if exists crm.actualizar_contrato_con_cuenta_pdf_v3(
  uuid,
  jsonb,
  jsonb
);
drop function if exists crm.actualizar_contrato_con_cuenta_pdf_v3(
  uuid,
  jsonb,
  jsonb,
  timestamptz
);

create function crm.actualizar_contrato_con_cuenta_pdf_v3(
  p_id uuid,
  p_contrato jsonb,
  p_cronograma jsonb,
  p_revision_esperada timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_cliente_id uuid;
  v_cliente_bloqueado_id uuid;
  v_revision_actual timestamptz;
  v_capacidad_token uuid;
  v_capacidad_anterior text := current_setting(
    'crm.contrato_escritura_atomica_token',
    true
  );
  v_revision_anterior text := current_setting(
    'crm.contrato_pdf_revision_autorizada',
    true
  );
  v_pdf jsonb;
begin
  if v_actor_id is null then
    raise insufficient_privilege using message = 'Sesión no válida';
  end if;

  select c.cliente_id
    into v_cliente_id
  from public.contratos c
  where c.id = p_id;
  if not found then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
  if not private.puede_gestionar_cuentas_cliente(v_cliente_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  -- El candado padre serializa dos pestañas que intenten corregir el mismo
  -- contrato. El ámbito se revalida después de esperar: una reasignación no
  -- puede convertir una revisión vieja en acceso ni en un oráculo de versión.
  select
    c.cliente_id,
    coalesce(c.actualizado_en, c.creado_en, 'epoch'::timestamptz)
    into v_cliente_bloqueado_id, v_revision_actual
  from public.contratos c
  where c.id = p_id
  for update;
  if not found
     or v_cliente_bloqueado_id is distinct from v_cliente_id
     or not private.puede_gestionar_cuentas_cliente(v_cliente_bloqueado_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
  v_cliente_id := v_cliente_bloqueado_id;

  if private.contrato_en_eliminacion(p_id) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;

  if p_revision_esperada is null
     or p_revision_esperada is distinct from v_revision_actual then
    raise exception using
      errcode = '40001',
      message = 'El contrato cambió desde que abriste la ficha. Recarga la información antes de guardar.';
  end if;

  v_capacidad_token := pg_catalog.gen_random_uuid();
  insert into private.contrato_escritura_atomica_capacidades (
    token,
    backend_pid,
    transaccion_id,
    actor_id,
    operacion,
    cliente_id,
    contrato_id
  ) values (
    v_capacidad_token,
    pg_catalog.pg_backend_pid(),
    pg_catalog.txid_current(),
    v_actor_id,
    'correccion',
    v_cliente_id,
    p_id
  );
  perform set_config(
    'crm.contrato_escritura_atomica_token',
    v_capacidad_token::text,
    true
  );
  perform set_config(
    'crm.contrato_pdf_revision_autorizada',
    p_id::text,
    true
  );

  begin
    -- El vendedor conserva además autoría, cartera y ventana de cinco horas;
    -- los poderes administrativos mantienen sus gates anteriores.
    perform crm.actualizar_contrato_con_cuenta(
      p_id,
      p_contrato,
      p_cronograma
    );
  exception when others then
    delete from private.contrato_escritura_atomica_capacidades
    where token = v_capacidad_token;
    perform set_config(
      'crm.contrato_escritura_atomica_token',
      coalesce(v_capacidad_anterior, ''),
      true
    );
    perform set_config(
      'crm.contrato_pdf_revision_autorizada',
      coalesce(v_revision_anterior, ''),
      true
    );
    raise;
  end;

  delete from private.contrato_escritura_atomica_capacidades
  where token = v_capacidad_token;
  perform set_config(
    'crm.contrato_escritura_atomica_token',
    coalesce(v_capacidad_anterior, ''),
    true
  );
  perform set_config(
    'crm.contrato_pdf_revision_autorizada',
    coalesce(v_revision_anterior, ''),
    true
  );

  v_pdf := private.crear_revision_contrato_pdf_base(p_id, v_actor_id);
  return jsonb_build_object('id', p_id, 'ok', true, 'pdf', v_pdf);
end;
$function$;

comment on function crm.actualizar_contrato_con_cuenta_pdf_v3(
  uuid,
  jsonb,
  jsonb,
  timestamptz
) is
  'Corrige contrato, cronograma y PDF de forma atómica. Exige revision_contrato vigente; una revisión ausente o antigua pide recargar sin tocar datos.';

revoke all on function crm.actualizar_contrato_con_cuenta_pdf_v3(
  uuid,
  jsonb,
  jsonb,
  timestamptz
) from public, anon, authenticated, service_role;
grant execute on function crm.actualizar_contrato_con_cuenta_pdf_v3(
  uuid,
  jsonb,
  jsonb,
  timestamptz
) to authenticated;

-- La ficha bancaria usa el gate de consulta, no el de operación. Se conserva
-- exactamente la proyección vigente del ledger y del perfil.
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
as $function$
begin
  if p_moneda is null or p_moneda not in ('PEN', 'USD') then
    raise exception using errcode = '22023', message = 'Moneda bancaria invalida';
  end if;
  if not private.puede_consultar_cuentas_cliente_fn(p_cliente_id) then
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
$function$;

comment on function crm.cuentas_bancarias_cliente_fn(uuid,text) is
  'Cuentas visibles para consultar en la ficha comercial. Mantiene lectura durante una reasignación pendiente, pero no concede autoridad para operar.';

revoke all on function crm.cuentas_bancarias_cliente_fn(uuid,text)
  from public, anon, authenticated, service_role;
grant execute on function crm.cuentas_bancarias_cliente_fn(uuid,text)
  to authenticated;

create or replace function private.puede_leer_contrato_pdf(
  p_contrato_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
    and public.puede_ver_contrato(p_contrato_id);
$function$;

comment on function private.puede_leer_contrato_pdf(uuid) is
  'Lectura documental con el mismo alcance actual del detalle contractual; no hereda el candado adicional de mutación.';

revoke all on function private.puede_leer_contrato_pdf(uuid)
  from public, anon, authenticated, service_role;

do $postflight$
declare
  v_expuesta pg_catalog.pg_proc%rowtype;
  v_privada pg_catalog.pg_proc%rowtype;
  v_alcance pg_catalog.pg_proc%rowtype;
  v_contratos pg_catalog.pg_proc%rowtype;
  v_ver_contrato pg_catalog.pg_proc%rowtype;
  v_banca pg_catalog.pg_proc%rowtype;
  v_banca_lectura pg_catalog.pg_proc%rowtype;
  v_banca_rpc pg_catalog.pg_proc%rowtype;
  v_pdf pg_catalog.pg_proc%rowtype;
  v_reasignacion pg_catalog.pg_proc%rowtype;
  v_cronograma pg_catalog.pg_proc%rowtype;
  v_titulares pg_catalog.pg_proc%rowtype;
  v_capacidad pg_catalog.pg_proc%rowtype;
  v_crear_contrato pg_catalog.pg_proc%rowtype;
  v_actualizar_contrato pg_catalog.pg_proc%rowtype;
  v_alta_pdf pg_catalog.pg_proc%rowtype;
  v_correccion_pdf pg_catalog.pg_proc%rowtype;
begin
  select p.* into v_expuesta
  from pg_catalog.pg_proc p
  where p.oid = 'crm.cliente_ficha_fn(uuid)'::regprocedure;

  select p.* into v_privada
  from pg_catalog.pg_proc p
    where p.oid = 'private.cliente_ficha_autorizada_fn(uuid)'::regprocedure;

  select p.* into v_alcance
  from pg_catalog.pg_proc p
  where p.oid = 'private.puede_consultar_cliente_fn(uuid)'::regprocedure;

  select p.* into v_contratos
  from pg_catalog.pg_proc p
  where p.oid = 'crm.contratos_cartera_fn()'::regprocedure;

  select p.* into v_ver_contrato
  from pg_catalog.pg_proc p
  where p.oid = 'public.puede_ver_contrato(uuid)'::regprocedure;

  select p.* into v_banca
  from pg_catalog.pg_proc p
  where p.oid = 'private.puede_gestionar_cuentas_cliente(uuid)'::regprocedure;

  select p.* into v_banca_lectura
  from pg_catalog.pg_proc p
  where p.oid = 'private.puede_consultar_cuentas_cliente_fn(uuid)'::regprocedure;

  select p.* into v_banca_rpc
  from pg_catalog.pg_proc p
  where p.oid = 'crm.cuentas_bancarias_cliente_fn(uuid,text)'::regprocedure;

  select p.* into v_pdf
  from pg_catalog.pg_proc p
  where p.oid = 'private.puede_leer_contrato_pdf(uuid)'::regprocedure;

  select p.* into v_reasignacion
  from pg_catalog.pg_proc p
  where p.oid = 'private.trg_cliente_historial_reasignacion()'::regprocedure;

  select p.* into v_cronograma
  from pg_catalog.pg_proc p
  where p.oid = 'crm.cronograma_contrato_fn(uuid)'::regprocedure;

  select p.* into v_titulares
  from pg_catalog.pg_proc p
  where p.oid = 'crm.titulares_contrato_fn(uuid)'::regprocedure;

  select p.* into v_capacidad
  from pg_catalog.pg_proc p
  where p.oid =
    'private.tiene_capacidad_contrato_atomico(text,uuid,uuid)'::regprocedure;

  select p.* into v_crear_contrato
  from pg_catalog.pg_proc p
  where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure;

  select p.* into v_actualizar_contrato
  from pg_catalog.pg_proc p
  where p.oid = 'public.actualizar_contrato(uuid,jsonb,jsonb)'::regprocedure;

  select p.* into v_alta_pdf
  from pg_catalog.pg_proc p
  where p.oid =
    'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure;

  select p.* into v_correccion_pdf
  from pg_catalog.pg_proc p
  where p.oid =
    'crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb,timestamptz)'::regprocedure;

  if v_expuesta.prosecdef
     or v_expuesta.provolatile <> 's'
     or not (v_expuesta.proconfig @> array['search_path=""']) then
    raise exception 'POSTFLIGHT: la RPC expuesta debe ser invoker, stable y search_path vacío';
  end if;

  if not v_privada.prosecdef
     or v_privada.provolatile <> 's'
     or not (v_privada.proconfig @> array['search_path=""']) then
    raise exception 'POSTFLIGHT: el helper privado debe ser definer, stable y search_path vacío';
  end if;

  if not v_alcance.prosecdef
     or v_alcance.provolatile <> 's'
     or not (v_alcance.proconfig @> array['search_path=""']) then
    raise exception 'POSTFLIGHT: el helper de alcance debe ser definer, stable y search_path vacío';
  end if;

  if not v_contratos.prosecdef
     or v_contratos.provolatile <> 's'
     or not (v_contratos.proconfig @> array['search_path=""'])
     or v_contratos.prosrc ilike '%cli.creado_por%'
     or v_contratos.prosrc not ilike '%coalesce(c.actualizado_en, c.creado_en, ''epoch''::timestamptz)%'
     or not ('revision_contrato' = any(v_contratos.proargnames)) then
    raise exception 'POSTFLIGHT: la cartera contractual todavía concede lectura histórica';
  end if;

  if to_regclass('crm.contratos_cartera') is null
     or not coalesce((
       select c.reloptions @> array['security_invoker=true']
       from pg_catalog.pg_class c
       where c.oid = 'crm.contratos_cartera'::regclass
     ), false)
     or not exists (
       select 1
       from information_schema.columns c
       where c.table_schema = 'crm'
         and c.table_name = 'contratos_cartera'
         and c.column_name = 'revision_contrato'
         and c.data_type = 'timestamp with time zone'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated', 'crm.contratos_cartera_fn()', 'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role', 'crm.contratos_cartera_fn()', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon', 'crm.contratos_cartera_fn()', 'EXECUTE'
     )
     or not pg_catalog.has_table_privilege(
       'authenticated', 'crm.contratos_cartera', 'SELECT'
     )
     or not pg_catalog.has_table_privilege(
       'service_role', 'crm.contratos_cartera', 'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'anon', 'crm.contratos_cartera', 'SELECT'
     ) then
    raise exception 'POSTFLIGHT: revision_contrato no quedó visible con ACL e invoker exactos';
  end if;

  if not v_ver_contrato.prosecdef
     or v_ver_contrato.provolatile <> 's'
     or not (v_ver_contrato.proconfig @> array['search_path=""'])
     or v_ver_contrato.prosrc ilike '%cli.creado_por%' then
    raise exception 'POSTFLIGHT: el detalle contractual todavía concede lectura histórica';
  end if;

  if not v_banca.prosecdef
     or v_banca.provolatile <> 's'
     or not (v_banca.proconfig @> array['search_path=""'])
     or v_banca.prosrc ilike '%cli.creado_por%'
     or v_banca.prosrc not ilike '%es_destino_crm_activo%' then
    raise exception 'POSTFLIGHT: las mutaciones no exigen asignación actual y responsable activo';
  end if;

  if not v_banca_lectura.prosecdef
     or v_banca_lectura.provolatile <> 's'
     or not (v_banca_lectura.proconfig @> array['search_path=""'])
     or v_banca_lectura.prosrc ilike '%cli.creado_por%'
     or not v_banca_rpc.prosecdef
     or v_banca_rpc.provolatile <> 's'
     or not (v_banca_rpc.proconfig @> array['search_path=""'])
     or v_banca_rpc.prosrc not ilike '%puede_consultar_cuentas_cliente_fn%'
     or not v_pdf.prosecdef
     or v_pdf.provolatile <> 's'
     or not (v_pdf.proconfig @> array['search_path=""'])
     or v_pdf.prosrc not ilike '%puede_ver_contrato%' then
    raise exception 'POSTFLIGHT: la lectura bancaria/documental no quedó separada de las mutaciones';
  end if;

  if not v_reasignacion.prosecdef
     or not (v_reasignacion.proconfig @> array['search_path=""']) then
    raise exception 'POSTFLIGHT: el emisor de reasignaciones no quedó endurecido';
  end if;

  if not v_cronograma.prosecdef
     or v_cronograma.provolatile <> 's'
     or not (v_cronograma.proconfig @> array['search_path=""'])
     or not v_titulares.prosecdef
     or v_titulares.provolatile <> 's'
     or not (v_titulares.proconfig @> array['search_path=""']) then
    raise exception 'POSTFLIGHT: cronograma o co-titulares no heredaron el alcance contractual';
  end if;

  if to_regclass(
       'private.contrato_escritura_atomica_capacidades'
     ) is null
     or not (
       select c.relrowsecurity
       from pg_catalog.pg_class c
       where c.oid =
         'private.contrato_escritura_atomica_capacidades'::regclass
     )
     or pg_catalog.has_table_privilege(
       'authenticated',
       'private.contrato_escritura_atomica_capacidades',
       'SELECT,INSERT,UPDATE,DELETE'
     )
     or pg_catalog.has_table_privilege(
       'anon',
       'private.contrato_escritura_atomica_capacidades',
       'SELECT,INSERT,UPDATE,DELETE'
     )
     or pg_catalog.has_table_privilege(
       'service_role',
       'private.contrato_escritura_atomica_capacidades',
       'SELECT,INSERT,UPDATE,DELETE'
     ) then
    raise exception 'POSTFLIGHT: el registro de capacidades no quedó privado y protegido';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid =
      'private.contrato_escritura_atomica_capacidades'::regclass
      and c.contype = 'p'
      and pg_catalog.pg_get_constraintdef(c.oid) ilike '%token%'
  ) or not exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid =
      'private.contrato_escritura_atomica_capacidades'::regclass
      and c.conname = 'contrato_escritura_atomica_operacion_check'
      and pg_catalog.pg_get_constraintdef(c.oid) ilike '%alta%'
      and pg_catalog.pg_get_constraintdef(c.oid) ilike '%correccion%'
  ) then
    raise exception 'POSTFLIGHT: la capacidad no quedó ligada a una operación y objetivo exactos';
  end if;

  if not v_capacidad.prosecdef
     or v_capacidad.provolatile <> 'v'
     or not (v_capacidad.proconfig @> array['search_path=""'])
     or pg_catalog.has_function_privilege(
       'authenticated',
       'private.tiene_capacidad_contrato_atomico(text,uuid,uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'private.tiene_capacidad_contrato_atomico(text,uuid,uuid)',
       'EXECUTE'
     ) then
    raise exception 'POSTFLIGHT: el verificador de capacidad no quedó privado, volatile y endurecido';
  end if;

  if not v_crear_contrato.prosecdef
     or v_crear_contrato.provolatile <> 'v'
     or not (v_crear_contrato.proconfig @> array['search_path=""'])
     or v_crear_contrato.prosrc not ilike '%tiene_capacidad_contrato_atomico%'
     or v_crear_contrato.prosrc not ilike '%puede_gestionar_cuentas_cliente%'
     or v_crear_contrato.prosrc not ilike '%es_destino_crm_activo%'
     or v_crear_contrato.prosrc not ilike '%crm.producto_condicion_id%'
     or v_crear_contrato.prosrc not ilike '%contrato_origen_revision%'
     or v_crear_contrato.prosrc not ilike '%v_origen_revision_esperada is null%'
     or v_crear_contrato.prosrc not ilike '%40001%'
     or pg_catalog.strpos(
       pg_catalog.lower(
         pg_catalog.substr(
           v_crear_contrato.prosrc,
           pg_catalog.strpos(
             pg_catalog.lower(v_crear_contrato.prosrc),
             'insert into public.contratos'
           )
         )
       ),
       'producto_condicion_id'
     ) > 0 then
    raise exception 'POSTFLIGHT: el alta efectiva perdió catálogo, snapshot libre o capacidad atómica';
  end if;

  if not v_actualizar_contrato.prosecdef
     or v_actualizar_contrato.provolatile <> 'v'
     or not (v_actualizar_contrato.proconfig @> array['search_path=""'])
     or v_actualizar_contrato.prosrc not ilike '%tiene_capacidad_contrato_atomico%'
     or v_actualizar_contrato.prosrc not ilike '%puede_gestionar_cuentas_cliente%'
     or v_actualizar_contrato.prosrc not ilike '%es_destino_crm_activo%'
     or v_actualizar_contrato.prosrc not ilike '%crm.producto_condicion_id%' then
    raise exception 'POSTFLIGHT: la corrección efectiva perdió sus gates canónicos o la capacidad atómica';
  end if;

  if not v_alta_pdf.prosecdef
     or v_alta_pdf.provolatile <> 'v'
     or not (v_alta_pdf.proconfig @> array['search_path=""'])
     or v_alta_pdf.prosrc not ilike '%contrato_escritura_atomica_capacidades%'
     or v_alta_pdf.prosrc not ilike '%coalesce(v_capacidad_anterior, '''')%'
     or v_alta_pdf.prosrc ilike '%crm.producto_condicion_id%'
     or not v_correccion_pdf.prosecdef
     or v_correccion_pdf.provolatile <> 'v'
     or not (v_correccion_pdf.proconfig @> array['search_path=""'])
     or v_correccion_pdf.prosrc not ilike '%contrato_escritura_atomica_capacidades%'
     or v_correccion_pdf.prosrc not ilike '%coalesce(v_capacidad_anterior, '''')%'
     or v_correccion_pdf.prosrc not ilike '%coalesce(v_revision_anterior, '''')%'
     or v_correccion_pdf.prosrc not ilike '%for update%'
     or v_correccion_pdf.prosrc not ilike '%p_revision_esperada is null%'
     or v_correccion_pdf.prosrc not ilike '%40001%'
     or v_correccion_pdf.pronargdefaults <> 1 then
    raise exception 'POSTFLIGHT: los wrappers PDF no fijan y restauran sus capacidades';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_proc p
    where p.prosrc ilike
      '%set_config(%crm.contrato_escritura_atomica_token%'
  ) <> 2 or (
    select count(*)
    from pg_catalog.pg_proc p
    where p.prosrc ilike
      '%insert into private.contrato_escritura_atomica_capacidades%'
  ) <> 2 then
    raise exception 'POSTFLIGHT: una función distinta de los dos wrappers emite capacidades';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated', 'public.crear_contrato(jsonb,jsonb)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon', 'public.crear_contrato(jsonb,jsonb)', 'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'public.actualizar_contrato(uuid,jsonb,jsonb)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'public.actualizar_contrato(uuid,jsonb,jsonb)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb,timestamptz)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb,timestamptz)',
       'EXECUTE'
     ) then
    raise exception 'POSTFLIGHT: las ACL de los escritores o wrappers contractuales cambiaron';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated', 'crm.cliente_ficha_fn(uuid)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon', 'crm.cliente_ficha_fn(uuid)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role', 'crm.cliente_ficha_fn(uuid)', 'EXECUTE'
     ) then
    raise exception 'POSTFLIGHT: ACL inesperada en crm.cliente_ficha_fn(uuid)';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated', 'private.cliente_ficha_autorizada_fn(uuid)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon', 'private.cliente_ficha_autorizada_fn(uuid)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role', 'private.cliente_ficha_autorizada_fn(uuid)', 'EXECUTE'
     ) then
    raise exception 'POSTFLIGHT: ACL inesperada en el helper privado de ficha';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated', 'private.puede_consultar_cliente_fn(uuid)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon', 'private.puede_consultar_cliente_fn(uuid)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role', 'private.puede_consultar_cliente_fn(uuid)', 'EXECUTE'
     ) then
    raise exception 'POSTFLIGHT: ACL inesperada en el helper de alcance';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_policies p
    where p.schemaname = 'crm'
      and p.tablename = 'actividades_cliente'
      and p.policyname = 'actividades_cliente_select'
      and p.cmd = 'SELECT'
      and p.roles = array['authenticated']::name[]
  ) then
    raise exception 'POSTFLIGHT: el historial no quedó protegido por la asignación actual';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_policies p
    where p.schemaname = 'crm'
      and p.tablename = 'operaciones_cartera'
      and p.policyname = 'operaciones_cartera_select'
      and p.cmd = 'SELECT'
      and p.roles = array['authenticated']::name[]
      and p.qual ilike '%puede_consultar_cliente_fn%'
  ) then
    raise exception 'POSTFLIGHT: renovaciones y aumentos no siguen la asignación actual';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_attribute a
    where a.attrelid = 'crm.actividades_cliente'::regclass
      and a.attname = 'vendedor_id'
      and a.attnotnull
  ) or not exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid = 'crm.actividades_cliente'::regclass
      and c.conname = 'actividades_cliente_tipo_check'
      and pg_catalog.pg_get_constraintdef(c.oid) ilike '%reasignacion%'
  ) then
    raise exception 'POSTFLIGHT: el historial no admite reasignaciones de forma coherente';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger t
    where t.tgrelid = 'public.perfiles'::regclass
      and t.tgname = 'trg_zz_perfiles_cliente_historial_reasignacion'
      and not t.tgisinternal
      and t.tgenabled = 'O'
  ) then
    raise exception 'POSTFLIGHT: la reasignación no quedó conectada al historial';
  end if;

  if pg_catalog.has_function_privilege(
       'authenticated', 'private.puede_gestionar_cuentas_cliente(uuid)', 'EXECUTE'
     ) or pg_catalog.has_function_privilege(
       'anon', 'private.puede_gestionar_cuentas_cliente(uuid)', 'EXECUTE'
     ) or pg_catalog.has_function_privilege(
       'authenticated', 'private.puede_consultar_cuentas_cliente_fn(uuid)', 'EXECUTE'
     ) or pg_catalog.has_function_privilege(
       'anon', 'private.puede_consultar_cuentas_cliente_fn(uuid)', 'EXECUTE'
     ) then
    raise exception 'POSTFLIGHT: un helper bancario privado quedó ejecutable desde la API';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated', 'crm.cuentas_bancarias_cliente_fn(uuid,text)', 'EXECUTE'
     ) or pg_catalog.has_function_privilege(
       'anon', 'crm.cuentas_bancarias_cliente_fn(uuid,text)', 'EXECUTE'
     ) then
    raise exception 'POSTFLIGHT: ACL inesperada en la consulta bancaria de la ficha';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated', 'crm.cronograma_contrato_fn(uuid)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon', 'crm.cronograma_contrato_fn(uuid)', 'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated', 'crm.titulares_contrato_fn(uuid)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon', 'crm.titulares_contrato_fn(uuid)', 'EXECUTE'
     ) then
    raise exception 'POSTFLIGHT: ACL inesperada en el detalle contractual';
  end if;

  if exists (
    select 1
    from unnest(coalesce(v_expuesta.proargnames, '{}'::text[])) as salida(nombre)
    where salida.nombre in (
      'banco', 'tipo_cuenta', 'numero_cuenta', 'cci',
      'titular_distinto', 'beneficiario_nombre', 'beneficiario_dni',
      'banco_usd', 'tipo_cuenta_usd', 'numero_cuenta_usd', 'cci_usd',
      'titular_distinto_usd', 'beneficiario_nombre_usd', 'beneficiario_dni_usd',
      'domicilio'
    )
  ) then
    raise exception 'POSTFLIGHT: la ficha comercial expone un dato restringido';
  end if;
end;
$postflight$;

commit;

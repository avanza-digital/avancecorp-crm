-- Asiento «Operaciones» del Portal (2026-08-21)
--
-- Gloria es hoy la unica cuenta `admin` del Portal, y `admin` es un interruptor
-- de todo o nada: las nueve pantallas del panel pasan por el mismo portero
-- (`verificarAdmin`) y, en la base, por la misma llave (`public.es_admin`). Su
-- asistente necesita exactamente cuatro de esas pantallas —Clientes, Contratos,
-- Pagos y Documentos— y ninguna de las otras cinco.
--
-- Este asiento nuevo se construye FALLANDO CERRADO: `public.es_admin()` NO se
-- toca, asi que todo objeto que hoy la usa —y todo objeto futuro que la use—
-- sigue significando exactamente «admin o superadmin» y niega al asiento nuevo
-- por omision. Lo que se abre se abre UNO A UNO, con nombre y apellido, a traves
-- de una llave distinta: `public.es_gestor_cartera()`.
--
-- PUEDE (paridad con Gloria en las cuatro pantallas):
--   · Clientes  — ver, crear, corregir, activar/desactivar.
--   · Contratos — ver, crear, corregir terminos y numero.
--   · Pagos     — ver el cronograma, registrar un pago y revertirlo.
--   · Documentos— ver, descargar y SUBIR.
--
-- NO PUEDE (queda en `es_admin()`, intacto):
--   · Comunicados y push a los clientes.
--   · Equipo: crear, editar o desactivar personal.
--   · Eliminar nada: ni clientes, ni contratos, ni cuotas, ni documentos.
--   · Actividad (`bandeja_actividad`), `audit_log`, Conciliacion, Directorio.
--   · Importar clientes masivamente.
--   · Cerrar el ciclo de un contrato (renovado/retirado): sigue en `es_admin()`.
--   · Reasignar el asesor de un cliente: lo corta el trigger (bloque 5 bis).
--   · Resetear la contrasena de nadie, ni de un cliente.
--   · Nada del CRM: no es candidato a rol CRM y no entra a crm.miavance.com.
--
-- Registro de excepciones a `public`: SI. Esta migracion vive en el repo del CRM
-- porque es el unico indice de migraciones del proyecto, pero su materia es el
-- Portal: altera el CHECK de `public.perfiles.rol`, ocho politicas de `public` y
-- `storage`, y siete funciones (`public`, `private` y una de `crm` que el panel
-- de Pagos consume).

-- ---------------------------------------------------------------------------
-- 1) El catalogo de roles admite el asiento nuevo.
-- ---------------------------------------------------------------------------
alter table public.perfiles drop constraint perfiles_rol_check;
alter table public.perfiles add constraint perfiles_rol_check
  check (rol = any (array[
    'cliente', 'analista', 'admin', 'superadmin',
    'directorio', 'comercial', 'operaciones'
  ]));

-- ---------------------------------------------------------------------------
-- 2) Identidad del asiento. Espejo exacto de `es_admin()`: rol + activo.
-- ---------------------------------------------------------------------------
create or replace function public.es_operaciones()
returns boolean
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  SELECT EXISTS (
    SELECT 1 FROM public.perfiles
    WHERE id = auth.uid()
      AND rol = 'operaciones'
      AND activo = true
  );
$function$;

comment on function public.es_operaciones() is
  'Asiento Operaciones del Portal: opera la cartera (clientes, contratos, pagos '
  'y documentos) con alcance total, y NADA mas. No administra personal, no '
  'comunica, no elimina. Ver es_gestor_cartera().';

-- ---------------------------------------------------------------------------
-- 3) La llave de la OPERACION de cartera.
--
-- Responde UNA sola pregunta —«¿puede operar la cartera con alcance total?»— y
-- no se usa como proxy de ninguna otra (leccion P04, 2026-08-09). `es_admin()`
-- sigue respondiendo la suya: «¿es el personal administrativo del Portal?».
-- ---------------------------------------------------------------------------
create or replace function public.es_gestor_cartera()
returns boolean
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  SELECT public.es_admin() OR public.es_operaciones();
$function$;

comment on function public.es_gestor_cartera() is
  'Quien gestiona la cartera operativa del Portal con alcance total: admin, '
  'superadmin u operaciones. NO implica administrar personal, comunicar ni '
  'eliminar: para eso sigue mandando es_admin().';

-- ---------------------------------------------------------------------------
-- 4) Politicas que se abren, una a una.
-- ---------------------------------------------------------------------------

-- 4.1 perfiles — LEE igual que Gloria (el selector de asesor del panel lista a
--     analistas Y administradores; recortarlo dejaria clientes con el asesor en
--     blanco). ESCRIBE solo filas de cliente: nunca personal.
alter policy perfiles_select on public.perfiles
using (
  ((select auth.uid()) = id)
  or public.es_gestor_cartera()
  or (rol = 'cliente' and private.rol_crm((select auth.uid())) = 'gerencia')
);

alter policy perfiles_update on public.perfiles
using (
  ((select auth.uid()) = id)
  or (select public.es_superadmin())
  or ((select public.es_admin()) and rol = any (array['cliente', 'analista']))
  or ((select public.es_operaciones()) and rol = 'cliente')
)
with check (
  (select public.es_superadmin())
  or ((select public.es_admin()) and rol = any (array['cliente', 'analista']))
  or ((select public.es_operaciones()) and rol = 'cliente')
  or (((select auth.uid()) = id) and rol = (select public.mi_rol()))
);

-- `admin_crea_perfiles` (INSERT) y `superadmin_elimina_perfiles` (DELETE) NO se
-- tocan: el alta de un cliente entra por la edge `crear-cliente` con
-- service_role, y borrar personas no es de este asiento.

-- 4.2 contratos — solo LECTURA directa. La escritura entra por las RPC
--     `crear_contrato` / `actualizar_contrato` / `cerrar_contrato`, que son
--     SECURITY DEFINER y llevan su propio porton (ver bloque 5). Las politicas
--     de INSERT y UPDATE se dejan en `es_admin()` a proposito: la puerta de
--     tabla no se abre si la puerta de la RPC ya alcanza.
alter policy contratos_select on public.contratos
using (
  (cliente_id = (select auth.uid()))
  or public.es_gestor_cartera()
);

-- 4.3 cronograma_pagos — la pantalla de Pagos escribe DIRECTO sobre la tabla
--     (registrar un pago y revertirlo son UPDATE), asi que aqui si hace falta.
--     El DELETE sigue siendo de `es_admin()`.
alter policy cronograma_select on public.cronograma_pagos
using (
  (exists (
    select 1
    from public.contratos c
    where c.id = cronograma_pagos.contrato_id
      and c.cliente_id = (select auth.uid())
  ))
  or public.es_gestor_cartera()
);

alter policy cronograma_admin_actualiza on public.cronograma_pagos
using (public.es_gestor_cartera())
with check (public.es_gestor_cartera());

-- 4.4 documentos — ve, lista y SUBE. No corrige ni borra: `documentos_admin_actualiza`
--     y `documentos_admin_elimina` se quedan en `es_admin()`.
alter policy documentos_select on public.documentos
using (
  (exists (
    select 1
    from public.contratos c
    where c.id = documentos.contrato_id
      and c.cliente_id = (select auth.uid())
  ))
  or public.es_gestor_cartera()
);

alter policy documentos_admin_inserta on public.documentos
with check (public.es_gestor_cartera());

-- 4.5 storage — el archivo en si. Descargar (la URL firmada de 1 h) y subir.
--     `admin_elimina_docs` y las dos de `comunicados` NO se tocan.
alter policy admin_descarga_docs on storage.objects
using (
  bucket_id = 'documentos'
  and public.es_gestor_cartera()
);

alter policy admin_sube_docs on storage.objects
with check (
  bucket_id = 'documentos'
  and public.es_gestor_cartera()
);

-- ---------------------------------------------------------------------------
-- 5) Funciones que se abren. Cuerpos identicos a los vivos en produccion: el
--    unico cambio es la llave (`es_admin` -> `es_gestor_cartera`) y, donde
--    correspondia, el comentario que la explicaba.
--
--    `contrato_tiene_pagos` hereda por `puede_ver_contrato` y no se toca.
--    `bandeja_actividad` (Actividad) sigue en `es_admin()`, cerrada.
-- ---------------------------------------------------------------------------

create or replace function public.puede_ver_contrato(p_contrato_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.contratos c
    LEFT JOIN public.perfiles cli ON cli.id = c.cliente_id
    WHERE c.id = p_contrato_id
      AND (
        public.es_gestor_cartera()
        OR c.cliente_id = auth.uid()
        OR ( public.es_analista()
             AND cli.rol = 'cliente'
             AND ( cli.asesor_perfil_id = auth.uid()
                   OR (cli.asesor_perfil_id IS NULL AND cli.creado_por = auth.uid()) ) )
      )
  );
$function$
;

create or replace function private.puede_gestionar_cuentas_cliente(p_cliente_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select (select auth.uid()) is not null
    -- Prevalencia P04 (2026-08-09): lo que prevalece sobre el rol de portal es
    -- la REVOCACIÓN explícita de la membresía CRM, no su ausencia. Quien nunca
    -- fue del CRM conserva el fallback global que P04 documentó desde el origen.
    and not (select private.membresia_crm_revocada())
    and exists (
      select 1
      from public.perfiles cli
      where cli.id = p_cliente_id
        and cli.rol = 'cliente'
        and cli.activo is true
        and (
          -- Poder del portal, ya condicionado por el gate P04 de arriba.
          (select public.es_gestor_cartera())
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
$function$
;

create or replace function public.crear_contrato(p_contrato jsonb, p_cronograma jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_es_analista boolean := (select public.es_analista());
  v_es_gestor_cartera boolean := (select public.es_gestor_cartera());
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
    or v_es_gestor_cartera
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
$function$
;

create or replace function public.actualizar_contrato(p_id uuid, p_contrato jsonb, p_cronograma jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_es_analista boolean := (select public.es_analista());
  v_es_gestor_cartera boolean := (select public.es_gestor_cartera());
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

  if v_es_gestor_cartera or v_es_gerencia_crm then
    -- P04 (2026-08-09): una membresía CRM REVOCADA prevalece sobre el poder de
    -- portal también para CORREGIR términos, no solo para la banca y el alta.
    -- Se pregunta por la revocación y NO por el guard bancario completo: ese
    -- exige cliente activo, y desactivar a un cliente no debe impedir corregir
    -- sus contratos históricos.
    if (select private.membresia_crm_revocada()) then
      raise insufficient_privilege using
        message = 'Tu membresia CRM fue revocada; no puedes corregir contratos';
    end if;
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
$function$
;

create or replace function public.actualizar_numero_contrato(p_id uuid, p_numero text, p_notas text DEFAULT NULL::text, p_categoria text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_numero text;
BEGIN
  -- Solo el personal que gestiona la cartera (admin, superadmin u operaciones)
  -- puede corregir un contrato existente por esta via.
  IF NOT public.es_gestor_cartera() THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;
  -- P04 (2026-08-09): la revocacion de la membresia CRM prevalece sobre el rol
  -- de portal tambien en esta puerta. La ausencia de membresia NO bloquea.
  IF (SELECT private.membresia_crm_revocada()) THEN
    RAISE EXCEPTION 'Tu membresia CRM fue revocada; no puedes corregir contratos'
      USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.contratos WHERE id = p_id) THEN
    RAISE EXCEPTION 'Contrato no encontrado';
  END IF;

  -- Categoria valida si viene
  IF p_categoria IS NOT NULL AND p_categoria NOT IN ('nuevo','renovacion','upgrade') THEN
    RAISE EXCEPTION 'Categoria invalida';
  END IF;

  v_numero := NULLIF(btrim(p_numero), '');
  IF v_numero IS NULL THEN
    RAISE EXCEPTION 'El N de contrato no puede quedar vacio';
  END IF;
  IF EXISTS (SELECT 1 FROM public.contratos
             WHERE numero_contrato = v_numero AND id <> p_id) THEN
    RAISE EXCEPTION 'El N de contrato % ya existe en otro contrato', v_numero;
  END IF;

  -- SOLO numero + notas + categoria. NO toca capital/tasa/modalidad/tipo/fechas NI el
  -- cronograma -> funciona aunque el contrato ya tenga cuotas pagadas.
  UPDATE public.contratos
     SET numero_contrato = v_numero,
         notas_internas  = CASE WHEN p_notas IS NULL THEN notas_internas
                                ELSE NULLIF(btrim(p_notas), '') END,
         categoria       = COALESCE(NULLIF(btrim(p_categoria),''), categoria)
   WHERE id = p_id;

  RETURN jsonb_build_object('id', p_id, 'ok', true);
END; $function$
;

-- `cerrar_contrato` (renovado/retirado) se queda FUERA a proposito y sigue en
-- `es_admin()`: cerrar el ciclo de un contrato es de Gloria. Decision de Miguel,
-- 2026-08-21.
create or replace function crm.cuentas_pago_contratos_fn(p_contrato_ids uuid[])
 RETURNS TABLE(contrato_id uuid, cuenta_bancaria_id uuid, moneda text, banco text, tipo_cuenta text, numero_cuenta text, cci text, titular_distinto boolean, beneficiario_nombre text, beneficiario_dni text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- P04 (2026-08-09): bloquea la revocación explícita, no la ausencia de
  -- membresía. El poder de gestión de cartera del portal (admin, superadmin
  -- u operaciones) sigue siendo condición necesaria.
  if (select private.membresia_crm_revocada())
     or not (select public.es_gestor_cartera()) then
    raise exception using errcode = '42501', message = 'No autorizado para consultar cuentas de pago';
  end if;
  if coalesce(cardinality(p_contrato_ids), 0) > 5000 then
    raise exception using errcode = '22023', message = 'Demasiados contratos en una sola consulta';
  end if;
  if coalesce(cardinality(p_contrato_ids), 0) = 0 then
    return;
  end if;

  if exists (
    select 1
    from crm.contrato_cuentas_pago ccp
    join public.contratos ct on ct.id = ccp.contrato_id
    join crm.cuentas_bancarias cb on cb.id = ccp.cuenta_bancaria_id
    where ccp.contrato_id = any(p_contrato_ids)
      and (
        cb.cliente_id is distinct from ct.cliente_id
        or cb.moneda is distinct from ct.moneda
      )
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
$function$
;

-- ---------------------------------------------------------------------------
-- 5 bis) Lo que el asiento NO puede cambiar de un cliente: su ASESOR.
--
-- Mover un cliente de un analista a otro es una decision comercial, no trabajo
-- de cartera (decision de Miguel, 2026-08-21). No se puede expresar con una
-- politica —la RLS decide por FILA y aqui hay que decidir por COLUMNA— asi que
-- se cierra donde ya se cierran las columnas privilegiadas de `perfiles`: el
-- trigger `proteger_campos_inmutables`.
--
-- Levanta la voz (excepcion) en vez de restaurar en silencio como hace la rama
-- del analista: un guardado que dice «listo» y no reasigna nada es peor que un
-- error claro. Y solo salta si de verdad CAMBIA el asesor, para no romper el
-- guardado normal del formulario, que reenvia el mismo valor cada vez.
--
-- Cuerpo identico al vivo en produccion + el bloque nuevo.
create or replace function public.proteger_campos_inmutables()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
BEGIN
  NEW.id         := OLD.id;
  NEW.creado_en  := OLD.creado_en;
  NEW.creado_por := OLD.creado_por;

  -- Campos privilegiados / de asignacion: se congelan para el usuario que edita su PROPIA
  -- fila (cliente) y TAMBIEN para un ANALISTA que edita la fila de un cliente. Antes solo se
  -- congelaban en la auto-edicion (NEW.id=auth.uid()), por eso un analista podia togglear
  -- activo / debe_cambiar_password / blanquear asesor_perfil_id de su cliente via UPDATE forjado.
  -- admin/superadmin quedan EXCLUIDOS (siguen reasignando/activando). service_role
  -- (auth.uid() IS NULL, no es_analista) NO se ve afectado -> las edges de alta/baja siguen igual.
  IF TG_TABLE_NAME = 'perfiles'
     AND NOT public.es_admin()
     AND ( NEW.id = auth.uid() OR public.es_analista() ) THEN
    NEW.activo           := OLD.activo;
    NEW.rol              := OLD.rol;
    NEW.asesor_id        := OLD.asesor_id;
    NEW.asesor_perfil_id := OLD.asesor_perfil_id;
    NEW.cargo            := OLD.cargo;
    -- El flag de cambio de clave solo lo baja el PROPIO usuario (primer login);
    -- un analista editando a un cliente NO puede tocarlo.
    IF NEW.id <> auth.uid() THEN
      NEW.debe_cambiar_password := OLD.debe_cambiar_password;
    END IF;
  END IF;

  -- Asiento «Operaciones» (2026-08-21): edita al cliente y lo activa o desactiva,
  -- pero NO lo mueve de analista. El `rol` se congela ademas por si acaso: la
  -- politica ya lo acota a 'cliente', esto es la segunda linea de defensa.
  IF TG_TABLE_NAME = 'perfiles'
     AND NOT public.es_admin()
     AND public.es_operaciones()
     AND NEW.id <> auth.uid() THEN
    IF NEW.asesor_perfil_id IS DISTINCT FROM OLD.asesor_perfil_id
       OR NEW.asesor_id IS DISTINCT FROM OLD.asesor_id THEN
      RAISE EXCEPTION 'El asiento Operaciones no puede reasignar el asesor de un cliente'
        USING ERRCODE = '42501';
    END IF;
    NEW.rol := OLD.rol;
  END IF;

  -- Ciclo de vida de contratos (2026-07-13): una vez cerrado un ciclo, el
  -- enlace de renovacion y los sellos de cierre quedan congelados para
  -- cualquier no-superadmin (correcciones = superadmin).
  IF TG_TABLE_NAME = 'contratos' AND NOT public.es_superadmin() THEN
    IF OLD.renovado_a_id IS NOT NULL THEN NEW.renovado_a_id := OLD.renovado_a_id; END IF;
    IF OLD.cerrado_en    IS NOT NULL THEN NEW.cerrado_en    := OLD.cerrado_en;    END IF;
    IF OLD.cerrado_por   IS NOT NULL THEN NEW.cerrado_por   := OLD.cerrado_por;   END IF;
  END IF;

  RETURN NEW;
END; $function$
;

-- ---------------------------------------------------------------------------
-- 6) Permisos de ejecucion: mismo trato que sus hermanas `es_admin()`,
--    `es_analista()` y `es_superadmin()` — nada para PUBLIC.
-- ---------------------------------------------------------------------------
revoke execute on function public.es_operaciones() from public;
revoke execute on function public.es_gestor_cartera() from public;
grant execute on function public.es_operaciones() to authenticated, service_role;
grant execute on function public.es_gestor_cartera() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7) Verificacion en la misma transaccion: si algo de lo anterior no quedo como
--    se describe, la migracion no se aplica.
-- ---------------------------------------------------------------------------
do $verificacion$
declare
  v_faltan text[] := '{}';
  v_sobran text[] := '{}';
  v_abiertas constant text[] := array[
    'perfiles:perfiles_select', 'perfiles:perfiles_update',
    'contratos:contratos_select',
    'cronograma_pagos:cronograma_select',
    'cronograma_pagos:cronograma_admin_actualiza',
    'documentos:documentos_select', 'documentos:documentos_admin_inserta'
  ];
  -- Puertas que DEBEN seguir cerradas al asiento nuevo.
  v_cerradas constant text[] := array[
    'perfiles:admin_crea_perfiles',
    'cronograma_pagos:cronograma_admin_elimina',
    'documentos:documentos_admin_actualiza',
    'documentos:documentos_admin_elimina',
    'novedades:novedades_admin_inserta',
    'novedades:novedades_update',
    'novedades_leidas:novedades_leidas_admin_delete',
    'audit_log:audit_log_admin_select'
  ];
  v_clave text;
begin
  -- El rol nuevo existe en el catalogo.
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.perfiles'::regclass
      and conname = 'perfiles_rol_check'
      and strpos(pg_get_constraintdef(oid), '''operaciones''') > 0
  ) then
    raise exception 'El CHECK de perfiles.rol no admite el rol operaciones';
  end if;

  -- `es_admin()` NO cambio de significado: sigue siendo admin + superadmin.
  if (select count(*)
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname = 'es_admin'
         and strpos(pg_get_functiondef(p.oid), 'operaciones') > 0) > 0 then
    raise exception 'es_admin() fue contaminada con el rol operaciones';
  end if;

  -- Las puertas que se abren mencionan la llave nueva.
  foreach v_clave in array v_abiertas loop
    if not exists (
      select 1 from pg_policies
      where schemaname = 'public'
        and tablename = split_part(v_clave, ':', 1)
        and policyname = split_part(v_clave, ':', 2)
        and (coalesce(qual, '') || coalesce(with_check, '')) ~ '(es_gestor_cartera|es_operaciones)'
    ) then
      v_faltan := v_faltan || v_clave;
    end if;
  end loop;
  if cardinality(v_faltan) > 0 then
    raise exception 'Politicas sin abrir al asiento nuevo: %',
      array_to_string(v_faltan, ', ');
  end if;

  -- Las puertas que deben seguir cerradas NO la mencionan.
  foreach v_clave in array v_cerradas loop
    if exists (
      select 1 from pg_policies
      where schemaname = 'public'
        and tablename = split_part(v_clave, ':', 1)
        and policyname = split_part(v_clave, ':', 2)
        and (coalesce(qual, '') || coalesce(with_check, '')) ~ '(es_gestor_cartera|es_operaciones)'
    ) then
      v_sobran := v_sobran || v_clave;
    end if;
  end loop;
  if cardinality(v_sobran) > 0 then
    raise exception 'Politicas abiertas de mas al asiento nuevo: %',
      array_to_string(v_sobran, ', ');
  end if;

  -- Storage: sube y descarga si; borra no.
  if (
    select count(*) from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname in ('admin_descarga_docs', 'admin_sube_docs')
      and (coalesce(qual, '') || coalesce(with_check, '')) ~ '(es_gestor_cartera|es_operaciones)'
  ) <> 2 then
    raise exception 'Las politicas de storage del bucket documentos no quedaron abiertas';
  end if;
  if exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname in ('admin_elimina_docs', 'admin_sube_comunicados', 'admin_borra_comunicados')
      and (coalesce(qual, '') || coalesce(with_check, '')) ~ '(es_gestor_cartera|es_operaciones)'
  ) then
    raise exception 'Se abrio de mas una politica de storage (borrado o comunicados)';
  end if;
end
$verificacion$;

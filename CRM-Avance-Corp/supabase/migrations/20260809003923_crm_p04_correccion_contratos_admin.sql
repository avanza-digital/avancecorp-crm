-- P04 alcanza la CORRECCIÓN de contratos por la vía admin del Portal.
--
-- ⚠️ [PORTAL — toca `public`, con OK explícito de Miguel el 2026-08-09
-- («ok dale con la migracion de actualizar_contrato»)]
--
-- Es al menos la 7ª migración del CRM que toca `public`, no la 3ª: preceden
-- 20260711000001 (rol comercial), 20260714000001 (tipo_documento),
-- 20260728044338 (trigger sobre public.perfiles), 20260801092924
-- (public.contrato_tiene_pagos) y las dos del ciclo de configuración operativa
-- —20260807123000 y 20260807235933— que definen media docena de funciones
-- `public.*`, incluida la propia `actualizar_contrato`. La cabecera de
-- MIGRACIONES.md decía «única excepción documentada: 20260711000001»; se
-- corrige en el mismo commit. El registro de excepciones había dejado de
-- funcionar como control y por eso este encabezado nació con el conteo errado.
--
-- Deuda que cierra (registrada en el ledger el 2026-08-08 por el auditor-rls
-- durante la reconciliación del gate F0): el alta de contratos ya estaba
-- gateada — `public.crear_contrato` consulta
-- `private.puede_gestionar_cuentas_cliente` para TODO actor, admin incluido —
-- pero la CORRECCIÓN no. Un admin del portal con la membresía CRM REVOCADA
-- seguía pudiendo modificar contratos existentes.
--
-- Al auditar para cerrarla apareció una SEGUNDA puerta que la deuda no
-- mencionaba y que es más silenciosa, porque no aparece en ninguna búsqueda por
-- el nombre del guard:
--
--   | Función                            | Qué permite cambiar                  | Gate previo |
--   |------------------------------------|--------------------------------------|-------------|
--   | public.actualizar_contrato         | capital, tasa, fechas, cronograma,   | rama admin  |
--   |   (rama admin: `null`)             | modalidad, titulares                 | SIN gate    |
--   | public.actualizar_numero_contrato  | N° de contrato, notas, categoría     | solo        |
--   |                                    | (funciona con cuotas YA PAGADAS)     | es_admin()  |
--
-- Ambas quedan sometidas a la invariante de offboarding de P04.
--
-- POR QUÉ EL PREDICADO ESTRECHO Y NO EL GUARD COMPLETO. La deuda decía «someter
-- la rama admin al guard bancario», es decir llamar a
-- `private.puede_gestionar_cuentas_cliente`. Se descartó a propósito: ese guard
-- exige además `cli.activo is true` y `cli.rol = 'cliente'`, de modo que
-- desactivar a un cliente bloquearía en silencio que un admin corrija sus
-- contratos históricos. Hoy hay 0 contratos de clientes inactivos (330
-- contratos, todos de clientes activos), pero es una trampa esperando a que
-- alguien desactive al primero. Es EXACTAMENTE el error que se corrigió horas
-- antes en 20260809000530: dejar que un predicado responda dos preguntas.
-- Aquí se pregunta solo lo que P04 quiere saber: «¿le revocamos el CRM?».
--
-- Alcance del cambio, medido en prod (2026-08-09):
--   · Personas que PIERDEN algo: solo quien tenga fila APAGADA en crm.equipo y
--     rol de portal admin/superadmin. Hoy: 0 (los 3 revocados son `comercial`,
--     que ya caía en la rama `else` → 'No autorizado').
--   · gloria@ y AdminCorp@ (admin/superadmin SIN fila): NO les afecta —
--     `membresia_crm_revocada()` es false para quien no tiene fila.
--   · Gerencia CRM, analistas y CRM catalogado: sin cambios (sus ramas no se
--     tocan; la de gerencia ya exige membresía activa vía `rol_crm()`).
--
-- El resto de ambos cuerpos se copia VERBATIM de la definición viva en
-- producción (`pg_get_functiondef`, 2026-08-09). No se toca la ventana de 5 h,
-- la autoría, el cierre renovado/retirado, las validaciones de capital/tasa, el
-- cronograma, los titulares ni ningún ACL. El preflight ASSERTA el md5 de ambos
-- cuerpos antes de reemplazarlos: `actualizar_numero_contrato` nunca fue
-- definida por una migración de este repo (su cuerpo es un pegado de
-- `pg_get_functiondef` que nadie puede contrastar contra el árbol), así que la
-- guarda de hash es la única red que existe para ella.
--
-- ASIMETRÍA DELIBERADA, anotada para que un auditor futuro no la «unifique»:
-- para un cliente INACTIVO, un admin ya no puede CREAR contrato
-- (`public.crear_contrato` aplica el guard completo, que exige cliente activo)
-- pero SÍ puede CORREGIRLO (predicado estrecho). Es intencional: crear para un
-- cliente dado de baja es un error de negocio; corregir su historia no lo es.
--
-- ⚠️ DEUDA P04-b QUE ESTA MIGRACIÓN NO CIERRA (alcance contenido a propósito:
-- en una migración a `public`, la disciplina de alcance vale más que la
-- completitud). Siguen SIN la invariante de offboarding, todas por vías de
-- admin del Portal:
--   1. **PRIORITARIA — hard-DELETE de contratos** por PostgREST
--      (`public_html/js/admin/contratos.js:1525`,
--      `.from('contratos').delete()`), con CASCADE a `cronograma_pagos` y
--      `documentos`. Un admin revocado no puede corregir un contrato pero sí
--      BORRARLO entero, que es estrictamente peor. Gobernado por una policy
--      DELETE de `public.contratos`, no por una RPC.
--   2. `public.cerrar_contrato` (renovado/retirado + traslado de cuotas).
--   3. UPDATE directo sobre `public.cronograma_pagos` (registrar, importar y
--      revertir pagos).
-- Mientras eso siga abierto, NO se puede comunicar «la operación contractual
-- está bajo P04»: lo está la corrección, no el borrado ni los pagos.
--
-- ⚠️ Riesgo residual del pegado verbatim: si una migración futura modifica
-- `public.actualizar_contrato` y luego alguien REAPLICA esta, la revertiría en
-- silencio. La guarda de hash del preflight lo convierte en un fallo ruidoso.

begin;

set local lock_timeout = '10s';

do $preflight$
begin
  if to_regprocedure('private.membresia_crm_revocada()') is null then
    raise exception 'Falta private.membresia_crm_revocada(); aplica 20260809000530 antes que esta';
  end if;
  if to_regprocedure('public.actualizar_contrato(uuid,jsonb,jsonb)') is null
     or to_regprocedure('public.actualizar_numero_contrato(uuid,text,text,text)') is null
     or to_regprocedure('public.es_admin()') is null
     or to_regprocedure('public.es_analista()') is null
     or to_regprocedure('public.es_superadmin()') is null
     or to_regprocedure('public._sync_contrato_titulares(uuid,jsonb)') is null
     or to_regprocedure('private.rol_crm(uuid)') is null
     or to_regprocedure('private.puede_gestionar_cuentas_cliente(uuid)') is null
     or to_regclass('public.contratos') is null
     or to_regclass('public.cronograma_pagos') is null then
    raise exception 'Falta una dependencia de la correccion de contratos del Portal';
  end if;

  -- GUARDA DE FIDELIDAD. Ambos cuerpos son un pegado verbatim de la definición
  -- viva auditada el 2026-08-09; si producción cambió desde entonces, este
  -- reemplazo REVERTIRÍA ese cambio en silencio. Se convierte en fallo ruidoso.
  -- Es el mismo control que 20260809000530 ejecutó a mano fuera de banda; en una
  -- migración a `public` debe vivir DENTRO de la transacción.
  if md5(pg_get_functiondef('public.actualizar_contrato(uuid,jsonb,jsonb)'::regprocedure))
     <> '2a55ddea7379217661e541913896c9c6' then
    raise exception 'public.actualizar_contrato cambio en prod desde la auditoria del 2026-08-09; re-auditar antes de aplicar';
  end if;
  if md5(pg_get_functiondef('public.actualizar_numero_contrato(uuid,text,text,text)'::regprocedure))
     <> 'c9184d972c2f6e2840ff8f68cbbd8cef' then
    raise exception 'public.actualizar_numero_contrato cambio en prod desde la auditoria del 2026-08-09; re-auditar antes de aplicar';
  end if;

  -- `actualizar_numero_contrato` es legacy: nunca la definió una migración de
  -- este repo y esta es la PRIMERA vez que llama a algo de `private`. Si su
  -- owner no pudiera ejecutar el helper, plpgsql no fallaría al crear sino EN
  -- RUNTIME, en cada corrección de N de contrato. Se verifica antes.
  if not exists (
    select 1
    from pg_proc p
    where p.oid in (
      'public.actualizar_contrato(uuid,jsonb,jsonb)'::regprocedure,
      'public.actualizar_numero_contrato(uuid,text,text,text)'::regprocedure
    )
    group by ()
    having bool_and(
      pg_catalog.has_function_privilege(
        p.proowner, 'private.membresia_crm_revocada()', 'EXECUTE'
      )
    )
  ) then
    raise exception 'El owner de alguna RPC de correccion no puede ejecutar private.membresia_crm_revocada()';
  end if;

  -- Esta migración estrena un consumidor nuevo del predicado de revocación, que
  -- distingue revocado de ajeno con `activo is false`. Ese predicado da FALSE
  -- para NULL: sin el NOT NULL, una fila con activo NULL dejaría de contar como
  -- revocada (fail-OPEN silencioso). Se reafirma la premisa aquí también.
  if not exists (
    select 1
    from pg_attribute a
    where a.attrelid = 'crm.equipo'::regclass
      and a.attname = 'activo'
      and a.attnotnull
      and not a.attisdropped
  ) then
    raise exception 'crm.equipo.activo dejo de ser NOT NULL: revisar membresia_crm_revocada antes de aplicar';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Corrección completa de términos (capital, tasa, fechas, cronograma)
-- ---------------------------------------------------------------------------
--
-- Único cambio respecto de prod: la rama `if v_es_admin or v_es_gerencia_crm`
-- dejaba pasar con `null`. Ahora consulta la revocación. La rama de gerencia CRM
-- ya exigía membresía activa (`rol_crm()` la devuelve solo con ambos flags), así
-- que el efecto real recae sobre admin/superadmin del Portal.
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
$function$;

-- ---------------------------------------------------------------------------
-- 2. La segunda puerta: corrección de N° / notas / categoría
-- ---------------------------------------------------------------------------
--
-- Es la vía que sigue funcionando cuando el contrato YA TIENE CUOTAS PAGADAS
-- (por eso no toca términos ni cronograma), y su único gate era `es_admin()`.
-- Se conserva su `search_path` legacy ('public','pg_temp') y su estilo original:
-- la referencia al helper va calificada, así que el gate no depende de él.
create or replace function public.actualizar_numero_contrato(
  p_id uuid,
  p_numero text,
  p_notas text default null::text,
  p_categoria text default null::text
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
DECLARE v_numero text;
BEGIN
  -- Solo admin/superadmin pueden corregir un contrato existente por esta via.
  IF NOT public.es_admin() THEN
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
END; $function$;

comment on function public.actualizar_contrato(uuid, jsonb, jsonb) is
  'Correccion de contratos del Portal. Admin/Superadmin y Gerencia CRM corrigen sin ventana ni autoria, pero una membresia CRM REVOCADA lo impide (P04, 2026-08-09); analista y CRM catalogado conservan autoria, ventana de 5 h y guard de cartera.';

comment on function public.actualizar_numero_contrato(uuid, text, text, text) is
  'Correccion administrativa de N/notas/categoria que sobrevive a cuotas pagadas. Exige admin del Portal y, desde P04 (2026-08-09), que su membresia CRM no este revocada.';

-- POST-CONDICIÓN DE ACL. `create or replace function` preserva OID, owner y
-- proacl, así que ningún grant debería perderse — pero eso es una creencia sobre
-- el motor, no una aserción. En una migración a `public` se comprueba: si el
-- reemplazo alterara los privilegios, la transacción entera se revierte.
-- Nótese la asimetría preexistente que NO se toca aquí (sería otro cambio a
-- `public` fuera de alcance): `actualizar_numero_contrato` conserva EXECUTE para
-- service_role y `actualizar_contrato` no. Hoy es inofensiva porque sin
-- `auth.uid()` la función corta en 'No autorizado' antes del gate nuevo.
do $postcondicion$
declare
  v_acl_actualizar text;
  v_acl_numero     text;
begin
  select array_to_string(p.proacl, ',') into v_acl_actualizar
  from pg_proc p where p.oid = 'public.actualizar_contrato(uuid,jsonb,jsonb)'::regprocedure;

  select array_to_string(p.proacl, ',') into v_acl_numero
  from pg_proc p where p.oid = 'public.actualizar_numero_contrato(uuid,text,text,text)'::regprocedure;

  if v_acl_actualizar is distinct from 'postgres=X/postgres,authenticated=X/postgres' then
    raise exception 'ACL inesperado en public.actualizar_contrato tras el reemplazo: %', v_acl_actualizar;
  end if;
  if v_acl_numero is distinct from 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres' then
    raise exception 'ACL inesperado en public.actualizar_numero_contrato tras el reemplazo: %', v_acl_numero;
  end if;
end;
$postcondicion$;

commit;

-- ⛔ ESTO NO ES UNA MIGRACION. NO APLICAR TAL CUAL. ⛔
--
-- Vive fuera de `migrations/` a proposito: si estuviera alli, un replay o un
-- push lo aplicaria sin que nadie lo hubiera decidido.
--
-- QUE ES: el cerrojo que le faltaba a la numeracion AUTOMATICA de contratos
-- dentro de `public.crear_contrato`. Estaba escrito y verificado como cuarta
-- migracion de la Fase 1 del P-055, y **Miguel lo saco de esa fase el 28/08**:
-- la numeracion automatica no se necesita todavia -mas adelante si-, y no tiene
-- sentido reemplazar una funcion viva del portal para proteger una rama que hoy
-- no usa nadie (466 contratos, TODOS con numero escrito a mano, cero
-- autogenerados).
--
-- CUANDO SE RETOME - las cuatro cosas se deciden JUNTAS, no solo el cerrojo:
--
--   1. EL FORMATO. Esta rama fabrica `AC-<anio>-NNNN`, pero los 466 contratos
--      vivos usan `2026-01-NNNNNN`: CERO llevan `AC-`. Encenderla tal cual
--      pariria contratos con un formato que no usa nadie. Es una decision de
--      negocio de Miguel, no una correccion tecnica.
--   2. EL CERROJO (lo unico que este archivo ya trae hecho y probado). El
--      calculo es "el ultimo + 1" sin candado: dos altas simultaneas del mismo
--      anio leen el mismo maximo y la segunda muere contra el UNIQUE
--      `contratos_numero_contrato_key` con un error crudo en la cara de quien
--      registra. Se resuelve con `pg_advisory_xact_lock` POR ANIO, en el mismo
--      idioma que el cerrojo de `crm.operaciones_cartera` que la funcion ya usa.
--   3. EL ANO SALE DE LA ZONA DE LA SESION, no de America/Lima: entre las 19:00
--      y medianoche del 31 de diciembre, hora de Lima, en UTC ya es el anio
--      siguiente, y el contrato saldria numerado con el anio que no es.
--   4. EL NUMERO MANUAL NO SE VALIDA EN SERVIDOR. Uno con formato `AC-<anio>-N`
--      no toma el cerrojo y puede competir con una alta automatica; y uno con
--      muchos digitos desborda el `::integer` del calculo y rompe TODA la
--      numeracion automatica a partir de ahi.
--
-- ESTADO DE ESTE TEXTO: el cuerpo de mas abajo es el de `public.crear_contrato`
-- VIVO al 2026-08-28 (md5 del cuerpo original f50b62e1a9839d2fb68363b8a53e7603),
-- con UN solo cambio -el `perform pg_advisory_xact_lock` y su comentario-, y se
-- verifico programaticamente que el resto del texto es identico. Ya paso una
-- prueba completa contra produccion dentro de un bloque que se deshace solo:
-- compila, conserva SECURITY DEFINER, `search_path` y permisos, y el cerrojo
-- resuelve la sobrecarga (int,int). **Antes de reutilizarlo hay que re-anclar el
-- md5**: la funcion viva habra cambiado.
--
-- Auditorias que lo miraron: `auditor-rls` (28/08) y Codex (28/08, que fue quien
-- encontro los puntos 1, 3 y 4, y ademas un fallo real en el postflight de aqui
-- abajo -ya corregido- por la forma en que Postgres guarda `search_path`).

-- == Preflight: la funcion viva es EXACTAMENTE la auditada el 28/08 ==========
do $preflight$
declare
  v_md5 text;
begin
  -- El orden importa: si la guarda YA estuviera puesta, el md5 tambien seria
  -- distinto, y abortar por md5 daria un mensaje enganoso ("no es la de la
  -- auditoria") para un caso que en realidad es "ya aplicada". Primero lo
  -- concreto, despues lo general.
  if exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure
      and strpos(p.prosrc, 'public.contratos.numero_contrato') > 0
  ) then
    raise exception 'la guarda de numeracion ya estaba puesta: nada que hacer';
  end if;

  select md5(p.prosrc) into v_md5
  from pg_catalog.pg_proc p
  where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure;
  if v_md5 is distinct from 'f50b62e1a9839d2fb68363b8a53e7603' then
    raise exception 'public.crear_contrato viva (md5 %) no es la de la auditoria; re-basar antes de aplicar', v_md5;
  end if;
end
$preflight$;

-- == La funcion, con el cerrojo y sin un solo cambio mas ======================
CREATE OR REPLACE FUNCTION public.crear_contrato(p_contrato jsonb, p_cronograma jsonb)
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
    -- GUARDA DE NUMERACION (P-055 F1.4). El "ultimo + 1" se calculaba sin
    -- candado: dos altas simultaneas del mismo anio leen el mismo maximo,
    -- fabrican el mismo numero y la segunda muere contra el UNIQUE
    -- `contratos_numero_contrato_key` con un error crudo en la cara del
    -- usuario. El cerrojo es POR ANIO y de transaccion -se suelta solo al
    -- commit-, asi que serializa unicamente a quien esta numerando
    -- automaticamente y no roza el camino del numero escrito a mano. Mismo
    -- idioma que el cerrojo de `crm.operaciones_cartera` que esta funcion ya
    -- usa mas abajo.
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('public.contratos.numero_contrato'),
      v_anio
    );
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

-- == Postflight: el cerrojo esta, y lo demas sigue en su sitio ================
do $postflight$
declare
  v_src text;
begin
  select p.prosrc into v_src
  from pg_catalog.pg_proc p
  where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure;

  if strpos(v_src, 'public.contratos.numero_contrato') = 0 then
    raise exception 'POSTFLIGHT: el cerrojo de numeracion no quedo puesto';
  end if;
  -- El cerrojo tiene que estar DENTRO de la rama del numero automatico: si
  -- quedara fuera, serializaria tambien las altas con numero escrito a mano.
  if strpos(v_src, 'public.contratos.numero_contrato') < strpos(v_src, 'if v_numero is null then') then
    raise exception 'POSTFLIGHT: el cerrojo quedo fuera de la rama del numero automatico';
  end if;
  if strpos(v_src, 'public.contratos.numero_contrato') > strpos(v_src, 'lpad(v_seq::text, 4, ''0'')') then
    raise exception 'POSTFLIGHT: el cerrojo quedo despues de calcular el numero: no sirve de nada';
  end if;
  -- Y nada de lo que sostiene el resto de la funcion se ha caido.
  if strpos(v_src, 'crm.operaciones_cartera') = 0
     or strpos(v_src, '_sync_contrato_titulares') = 0
     or strpos(v_src, 'El capital debe estar entre 100 y 100,000,000') = 0 then
    raise exception 'POSTFLIGHT: el reemplazo se llevo por delante parte del cuerpo';
  end if;
  if not (select p.prosecdef from pg_catalog.pg_proc p
          where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure) then
    raise exception 'POSTFLIGHT: la funcion dejo de ser SECURITY DEFINER';
  end if;
  -- Un SECURITY DEFINER sin `search_path` fijado es la puerta clasica al
  -- secuestro por esquema: se comprueba, no se supone.
  -- OJO CON LA FORMA EXACTA: `SET search_path TO ''` se guarda en `proconfig`
  -- como search_path seguido de dos comillas dobles, NO como `search_path=` a
  -- secas. Buscar la version sin comillas no encuentra nunca nada y hace fallar
  -- el postflight SIEMPRE - lo cazo la auditoria de Codex, y esta medido contra
  -- produccion. El literal de abajo lleva las dos comillas dentro.
  if not (select coalesce(p.proconfig, '{}') @> array['search_path=""']::text[]
          from pg_catalog.pg_proc p
          where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure) then
    raise exception 'POSTFLIGHT: la funcion perdio su search_path vacio (proconfig = %)',
      (select coalesce(p.proconfig::text, '(nulo)') from pg_catalog.pg_proc p
       where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure);
  end if;
  -- Y el ACL: ni PUBLIC ni el visitante sin cuenta; `authenticated` intacto.
  if exists (select 1 from pg_catalog.pg_proc p, aclexplode(p.proacl) a
             where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure
               and a.grantee = 0 and a.privilege_type = 'EXECUTE') then
    raise exception 'POSTFLIGHT: crear_contrato quedo abierta a PUBLIC';
  end if;
  if has_function_privilege('anon', 'public.crear_contrato(jsonb,jsonb)'::regprocedure, 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.crear_contrato(jsonb,jsonb)'::regprocedure, 'EXECUTE') then
    raise exception 'POSTFLIGHT: los permisos de crear_contrato cambiaron con el reemplazo';
  end if;
  raise notice 'POSTFLIGHT OK: cerrojo por anio dentro de la rama automatica; cuerpo, search_path y permisos intactos';
end
$postflight$;

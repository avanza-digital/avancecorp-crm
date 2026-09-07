-- ============================================================================
-- REVERSA de RENTABILIDAD R4 (20260907093000): APAGA Y DESMONTA el candado del servidor.
-- Devuelve el observador de R2 (mide, nunca aborta), la puerta del alta, crm.solicitar_tasa_fn y publicar_politica al
-- estado previo, deja el trigger vigilando las 7 columnas de R2, suelta los cuatro helpers y desregistra la versión.
-- No toca datos: las autorizaciones ya consumidas siguen consumidas y el libro conserva sus filas origen=enforcement.
--
-- LA TARJETA DE GERENCIA NO SE REVIERTE a propósito (Codex R4 #11): las filas origen=enforcement que el candado dejó
-- en el libro son reales, y devolverle el filtro «solo observacion» haría desaparecer importes y aparecer huecos
-- falsos. Contar las dos orillas es correcto con el candado puesto y con el candado quitado.
--
-- ANTES DE ESTO: si la política está en «enforcement», la vuelta atrás NORMAL es publicar una versión en
-- «observacion» (Configuración → Política de rentabilidad). Esta reversa se niega con el candado encendido: apagarlo
-- es una decisión de Gerencia, no de una migración.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_rentabilidad_r4'));
do $pre$
begin
  if (select p.modo from private.politica_rentabilidad_vigente(statement_timestamp()) p) is distinct from 'observacion' then
    raise exception 'REVERSA R4: la política vigente está en enforcement. Publica una versión en observacion antes de desmontar el candado';
  end if;
  -- Se aceptan los cuerpos CONOCIDOS de R4 (las versiones intermedias solo existieron en el banco).
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_contratos_observar_rentabilidad()'))
       not in ('0e73d5d01bf7aa3c1e39368a1cb20cd3', 'a1827ee340a091ae9aeb9b539e37652b', 'e5f9d8d8872be5aeb35d4c3493533b33', 'a6c0f22a9ba7d25faabd35b224953ee3', '10056b887295bf8c5a5c8f2b3479b91a') then
    raise exception 'REVERSA R4: el observador no lleva un cuerpo conocido de R4; hay otra versión encima';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)')) is distinct from 'a363ad7e514c8eef3257acd7a1a54d44' then
    raise exception 'REVERSA R4: la puerta del alta no lleva el cuerpo de R4 (a363ad7e…); no se toca';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.publicar_politica_rentabilidad_fn(integer,jsonb)')) is distinct from 'ec070a86678c3a952ed15b3fc7d7cafd' then
    raise exception 'REVERSA R4: publicar_politica_rentabilidad_fn no lleva el cuerpo de R4 (ec070a86…); no se toca';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.solicitar_tasa_fn(jsonb)')) not in ('0e2b20efbc05c5facd8769bc5ae88164', '1db7a86959289e9168147595bd6a1a3f') then
    raise exception 'REVERSA R4: crm.solicitar_tasa_fn no lleva un cuerpo conocido; no se toca';
  end if;
end
$pre$;

-- 1. El observador de R2, byte a byte.
create or replace function private.trg_contratos_observar_rentabilidad()
returns trigger
language plpgsql security definer set search_path = '' set lock_timeout = '2s'
as $function$
declare
  v_c          public.contratos%rowtype;   -- el estado FINAL de la fila al commit (no la imagen del evento; Codex R2 #4)
  v_xid        text := pg_current_xact_id()::text;
  v_marca      text := 'crm.r2_obs_' || replace(new.id::text, '-', '');   -- GUC transaccional: «este contrato ya se procesó en esta tx»
  v_pol        crm.politica_rentabilidad;
  v_prev       record;
  v_prev_id    uuid;
  v_conservada boolean := false;
  v_pol_id     uuid;
  v_origen     uuid;
  v_candidatos integer := 0;
  v_cand_id    uuid;
  v_cand_num   text;
  v_cand_tasa  numeric;
  v_res        jsonb;
  v_base       numeric;
  v_regla      text;
  v_motivo     text;
  v_cambios    jsonb;
  v_detalle    jsonb;
begin
 -- TODO el cuerpo va bajo una excepción externa: el observador no puede abortar un alta ni una corrección. lock_timeout=2s
 -- convierte una espera de candado en 55P03 (atrapable). Lo único que WHEN OTHERS no atrapa es query_canceled (57014):
 -- en PostgreSQL 17 statement_timeout se desactiva antes del commit, y aquí no hay más esperas que las de candado.
 begin
  select * into v_c from public.contratos c where c.id = new.id;
  if v_c.id is null then
    return null;   -- borrado en la misma transacción: nada que observar
  end if;
  -- UNA observación por contrato y transacción: varios eventos (alta + correcciones en la misma tx) → una sola foto FINAL.
  -- El marcador es un GUC transaccional (se fija también cuando el cambio neto es vacío: 15→18→15 no es una corrección; Codex R2 #25).
  -- Límite declarado: si un cliente ejecutara SET CONSTRAINTS … IMMEDIATE a mitad de transacción, la foto sería la de ese
  -- momento (nadie lo hace en el proyecto; Codex R2 #19).
  if coalesce(current_setting(v_marca, true), '') = '1' then
    return null;
  end if;
  perform set_config(v_marca, '1', true);
  if tg_op = 'UPDATE' then
    -- Solo si cambió algo que determine la regla o el margen (Codex R2 #5), comparando la imagen previa con el estado final.
    v_cambios := jsonb_strip_nulls(jsonb_build_object(
      'tasa_anual',        case when old.tasa_anual        is distinct from v_c.tasa_anual        then jsonb_build_array(old.tasa_anual, v_c.tasa_anual) end,
      'categoria',         case when old.categoria         is distinct from v_c.categoria         then jsonb_build_array(old.categoria, v_c.categoria) end,
      'cliente_id',        case when old.cliente_id        is distinct from v_c.cliente_id        then jsonb_build_array(old.cliente_id, v_c.cliente_id) end,
      'capital',           case when old.capital           is distinct from v_c.capital           then jsonb_build_array(old.capital, v_c.capital) end,
      'moneda',            case when old.moneda            is distinct from v_c.moneda            then jsonb_build_array(old.moneda, v_c.moneda) end,
      'fecha_inicio',      case when old.fecha_inicio      is distinct from v_c.fecha_inicio      then jsonb_build_array(old.fecha_inicio, v_c.fecha_inicio) end,
      'fecha_vencimiento', case when old.fecha_vencimiento is distinct from v_c.fecha_vencimiento then jsonb_build_array(old.fecha_vencimiento, v_c.fecha_vencimiento) end));
    if v_cambios = '{}'::jsonb then
      return null;
    end if;
  end if;
  v_pol := private.politica_rentabilidad_vigente(statement_timestamp());
  if v_pol.id is null then
    return null;   -- sin política publicada no se observa (R1 garantiza la v1)
  end if;

  -- En una CORRECCIÓN que no cambia cliente ni categoría, la base de comparación es la RESOLUCIÓN ORIGINAL del alta
  -- (base, regla, origen), no una reevaluación con el estado de hoy (Codex R2 #8). Si cambió cliente o categoría, se resuelve de nuevo.
  v_pol_id := v_pol.id;
  if tg_op = 'UPDATE' and not (v_cambios ? 'categoria' or v_cambios ? 'cliente_id') then
    -- Solo se conserva una resolución del MISMO cliente y la MISMA categoría (Codex R2 #20), con la política que la produjo (#21).
    select l.tasa_base, l.regla, l.contrato_origen_id, l.politica_id, l.id, l.detalle ->> 'motivo' as motivo into v_prev
    from crm.ledger_rentabilidad l
    where l.contrato_id = v_c.id and l.origen = 'observacion'
      and l.categoria = v_c.categoria and l.cliente_id = v_c.cliente_id
    order by l.secuencia asc limit 1;
    if v_prev.regla is not null then
      -- Se conserva la resolución original… y también su INCERTIDUMBRE (Codex #8): un sin_regla no se «resuelve» al corregir.
      v_regla := v_prev.regla; v_origen := v_prev.contrato_origen_id; v_pol_id := v_prev.politica_id; v_prev_id := v_prev.id; v_conservada := true;
      if v_prev.regla = 'sin_regla' then
        v_base := v_c.tasa_anual; v_motivo := coalesce(v_prev.motivo, 'sin_motivo');
      else
        v_base := v_prev.tasa_base;
      end if;
    end if;
  end if;

  if not v_conservada then
    begin
      if v_c.categoria is null then
        v_regla := 'sin_regla'; v_base := v_c.tasa_anual; v_motivo := 'categoria_nula';
      elsif v_c.categoria = 'renovacion' then
        select o.contrato_origen_id into v_origen from crm.operaciones_cartera o where o.contrato_nuevo_id = v_c.id;
        if v_origen is null then
          v_regla := 'sin_regla'; v_base := v_c.tasa_anual; v_motivo := 'renovacion_sin_origen_registrado';
        else
          v_res := private.resolver_tasa(v_c.cliente_id, v_c.categoria, v_origen, statement_timestamp(), v_c.id);
          v_base := (v_res ->> 'tasa_base')::numeric; v_regla := v_res ->> 'regla';
        end if;
      elsif v_c.categoria = 'upgrade' then
        -- D2 exige que el analista SELECCIONE el origen (R3). Hoy la puerta no lo registra: el observador solo apunta el
        -- candidato cuando es único —contrato activo del cliente que ya EXISTÍA antes y seguía vigente al inicio del
        -- nuevo— y lo deja como sin_regla (una inferencia es una hipótesis, no una regla; Codex R2 #7).
        select count(*), min(c.id::text)::uuid into v_candidatos, v_origen
        from public.contratos c
        where c.cliente_id = v_c.cliente_id and c.id <> v_c.id and c.estado = 'activo' and c.renovado_a_id is null
          and not c.es_demo and c.creado_en < v_c.creado_en and c.fecha_vencimiento >= v_c.fecha_inicio;
        if v_candidatos = 1 then
          select c.id, c.numero_contrato, c.tasa_anual into v_cand_id, v_cand_num, v_cand_tasa from public.contratos c where c.id = v_origen;
          v_regla := 'sin_regla'; v_base := v_c.tasa_anual; v_motivo := 'upgrade_origen_inferido';
        else
          v_origen := null; v_regla := 'sin_regla'; v_base := v_c.tasa_anual;
          v_motivo := case when v_candidatos = 0 then 'upgrade_sin_contrato_activo_previo' else 'upgrade_origen_ambiguo' end;
        end if;
        v_origen := null;   -- sin origen DEMOSTRADO no se anota como origen; el candidato va en detalle
      else
        v_res := private.resolver_tasa(v_c.cliente_id, v_c.categoria, null, statement_timestamp(), v_c.id);
        v_base := (v_res ->> 'tasa_base')::numeric; v_regla := v_res ->> 'regla';
      end if;
    exception when others then
      -- El núcleo no pudo decidir (cliente inactivo, origen raro…): se anota, no se bloquea.
      v_regla := 'sin_regla'; v_base := v_c.tasa_anual;
      v_motivo := 'resolver:' || sqlstate || ':' || left(sqlerrm, 160);
      v_res := null; v_origen := null;
    end;
  end if;

  v_detalle := jsonb_strip_nulls(jsonb_build_object(
    'xid', v_xid, 'evento', tg_op,
    'capital', v_c.capital, 'moneda', v_c.moneda,
    'fecha_inicio', v_c.fecha_inicio, 'fecha_vencimiento', v_c.fecha_vencimiento,
    'plazo_dias', (v_c.fecha_vencimiento - v_c.fecha_inicio),
    'analista_cierre_id', v_c.analista_cierre_id, 'creado_por', v_c.creado_por,
    'es_demo', v_c.es_demo, 'estado', v_c.estado, 'operacion', tg_op,
    'tasa_anterior', case when tg_op = 'UPDATE' then old.tasa_anual end,
    'cambios', case when tg_op = 'UPDATE' then v_cambios end,
    'base_conservada', case when v_conservada then true end,
    'observacion_base_id', v_prev_id,
    'politica_vigente_al_observar', v_pol.version,
    'motivo', v_motivo,
    'candidato_origen', case when v_cand_id is null then null else jsonb_build_object('id', v_cand_id, 'numero_contrato', v_cand_num, 'tasa_anual', v_cand_tasa) end,
    'politica_version', (select pp.version from crm.politica_rentabilidad pp where pp.id = v_pol_id),
    'resolucion', case when v_res is null then null else v_res - 'politica' - 'cliente_id' - 'categoria' end
  ));
  begin
    insert into crm.ledger_rentabilidad (
      contrato_id, numero_contrato, cliente_id, categoria, contrato_origen_id, politica_id, solicitud_id,
      tasa_base, tasa_final, tasa_recibida, regla, origen, actor_id, detalle
    ) values (
      v_c.id, v_c.numero_contrato, v_c.cliente_id, v_c.categoria, v_origen, v_pol_id, null,
      v_base, v_c.tasa_anual, v_c.tasa_anual, v_regla, 'observacion', (select auth.uid()), v_detalle
    );
  exception when others then
    raise warning 'RENTABILIDAD R2: no se pudo observar el contrato % (% %)', v_c.id, sqlstate, sqlerrm;
  end;
  return null;
 exception when others then
  raise warning 'RENTABILIDAD R2: el observador falló y se ignora (% %) en el contrato %', sqlstate, sqlerrm, new.id;
  return null;
 end;
end;
$function$;
revoke all on function private.trg_contratos_observar_rentabilidad() from public, anon, authenticated, service_role;
comment on function private.trg_contratos_observar_rentabilidad() is
  'Rentabilidad R2: observador diferido de public.contratos (INSERT y UPDATE de tasa, categoría, cliente, capital, moneda o fechas). Al commit relee el estado FINAL de la fila y escribe UNA fila origen=observacion por contrato y transacción (detalle.xid) en crm.ledger_rentabilidad: base del núcleo vs la que quedó; en una corrección conserva la resolución original del alta (base_conservada); sin_regla con motivo cuando no decide (upgrade: solo candidato, nunca origen inferido); nunca aborta (lock_timeout 2 s → 55P03 atrapado; WARNING). No bloquea: eso es R4.';

-- 2. El trigger vuelve a vigilar las 7 columnas de R2.
drop trigger if exists trg_contratos_zz_observar_rentabilidad on public.contratos;
create constraint trigger trg_contratos_zz_observar_rentabilidad
after insert or update of tasa_anual, categoria, cliente_id, capital, moneda, fecha_inicio, fecha_vencimiento on public.contratos
deferrable initially deferred
for each row execute function private.trg_contratos_observar_rentabilidad();

-- 3. La puerta del alta, byte a byte (sin el set_config del origen del upgrade).
create or replace function crm.crear_contrato_con_cuenta_pdf_v2(p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_contrato jsonb := p_contrato;
  v_resultado jsonb;
  v_contrato_id uuid;
  v_pdf jsonb;
  v_clave_texto text := nullif(btrim(coalesce(p_contrato->>'clave_idempotencia', '')), '');
  v_clave uuid;
  v_huella text;
  v_huella_previa text;
begin
  if v_actor_id is null then
    raise insufficient_privilege using message = 'Sesión no válida';
  end if;

  -- IDEMPOTENCIA DEL ALTA (05/09/2026). El front manda una clave (uuid) por intento de
  -- formulario, la MISMA en cada reintento. Si este actor ya registró un alta con esa
  -- clave, se devuelve el MISMO contrato en vez de crear otro. Viaja DENTRO de
  -- p_contrato para no cambiar la firma del RPC; es del transporte, no del contrato:
  -- se quita antes de bajar a la cadena, que recibe EXACTAMENTE lo que recibía.
  -- Sin clave, nada cambia (los clientes que no la mandan siguen igual).
  if v_clave_texto is not null then
    begin
      v_clave := v_clave_texto::uuid;
    exception when invalid_text_representation then
      raise exception 'La clave de idempotencia del alta no es válida'
        using errcode = '22023';
    end;
    -- Dos envíos simultáneos con la misma clave del mismo actor (doble clic, dos
    -- pestañas) se serializan aquí: el segundo espera y lee el alta del primero.
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'crm.alta_contrato_idempotente|' || v_actor_id::text || '|' || v_clave::text, 0
      )
    );
    -- La huella de LO QUE SE PIDE (sin la clave): la misma clave solo vale para la
    -- misma solicitud. jsonb::text es canónico (claves ordenadas), así que dos
    -- envíos iguales dan la misma huella.
    v_huella := md5(
      (p_contrato - 'clave_idempotencia')::text || '|'
      || coalesce(p_cronograma::text, '') || '|'
      || coalesce(p_cuenta::text, '')
    );
    select a.respuesta, a.contrato_id, a.huella
      into v_resultado, v_contrato_id, v_huella_previa
    from private.contrato_altas_idempotentes a
    where a.actor_id = v_actor_id and a.clave = v_clave;
    if found then
      -- El replay pasa por la MISMA autorización que el alta (Codex 05/09): una
      -- membresía revocada o un contrato fuera de cartera no recuperan nada.
      if not (select private.puede_registrar_ventas()) then
        raise insufficient_privilege using
          message = 'Cliente no encontrado o fuera de tu cartera';
      end if;
      -- Lápida: el contrato de este intento fue eliminado después (FK SET NULL).
      -- Un reintento tardío NO recrea lo que Gerencia borró a propósito.
      if v_contrato_id is null then
        raise exception 'El contrato de este intento fue eliminado después; vuelve a registrar el alta'
          using errcode = 'P0409', hint = 'ALTA_ELIMINADA';
      end if;
      -- Misma fila que bloquea la puerta de eliminación: replay y borrado se
      -- serializan. Si el contrato desaparece mientras esperamos, es lápida.
      begin
        perform private.bloquear_fila_contrato_pdf(v_contrato_id);
      exception when sqlstate 'P0002' then
        raise exception 'El contrato de este intento fue eliminado después; vuelve a registrar el alta'
          using errcode = 'P0409', hint = 'ALTA_ELIMINADA';
      end;
      -- Eliminación PREPARADA y aún no finalizada (Gerencia pulsó «Eliminar» y la edge todavía
      -- no borró): no se devuelve como «alta recuperada» un contrato que está a punto de
      -- desaparecer. La misma pregunta y el mismo 55000 que hace el alta
      -- (private.crear_job_contrato_pdf_base); la fila ya está bloqueada, así que la
      -- respuesta es estable hasta que esta transacción termine.
      if private.contrato_en_eliminacion(v_contrato_id) then
        raise exception 'El contrato está en proceso de eliminación'
          using errcode = '55000';
      end if;
      if not private.puede_leer_contrato_pdf_como(v_contrato_id, v_actor_id) then
        raise insufficient_privilege using
          message = 'Contrato no encontrado o fuera de tu cartera';
      end if;
      -- Misma clave pero OTROS datos (el analista editó el formulario tras un
      -- intento que SÍ creó el contrato): no se devuelve el viejo como si fuera
      -- el nuevo ni se crea otro. Se le dice la verdad, con el número.
      if v_huella_previa is distinct from v_huella then
        raise exception 'Este intento ya creó el contrato % con otros datos; no se creó otro. Revísalo antes de registrar uno nuevo',
          coalesce(v_resultado->>'numero_contrato', v_contrato_id::text)
          using errcode = 'P0409',
                hint = 'ALTA_YA_CREADA_CON_OTROS_DATOS',
                detail = jsonb_build_object(
                  'contrato_id', v_contrato_id,
                  'numero_contrato', v_resultado->>'numero_contrato'
                )::text;
      end if;
      -- El MISMO contrato, con el estado documental de HOY (la reserva pudo avanzar
      -- desde el primer intento) y la marca de que es un alta ya registrada.
      return (v_resultado - 'pdf')
        || jsonb_build_object('pdf', private.contrato_pdf_estado_base(v_contrato_id))
        || jsonb_build_object('idempotente', true);
    end if;
    v_contrato := p_contrato - 'clave_idempotencia';
  end if;

  -- El contrato, cronograma, cuenta, vínculo, snapshot y job se confirman o
  -- revierten juntos porque toda la cadena corre en esta transacción RPC.
  v_resultado := crm.crear_contrato_con_cuenta(
    v_contrato,
    p_cronograma,
    p_cuenta
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
  v_resultado := v_resultado || jsonb_build_object('pdf', v_pdf);
  if v_clave is not null then
    -- Misma transacción que el alta: o quedan los dos, o ninguno.
    insert into private.contrato_altas_idempotentes (actor_id, clave, contrato_id, huella, respuesta)
    values (v_actor_id, v_clave, v_contrato_id, v_huella, v_resultado);
  end if;
  return v_resultado;
end;
$function$;

-- 4. crm.solicitar_tasa_fn tal como la dejó R1 (sin contexto de corrección).
create or replace function crm.solicitar_tasa_fn(p_solicitud jsonb)
returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_cliente uuid; v_cat text; v_origen uuid; v_pc uuid;
  v_capital numeric; v_moneda text; v_mod text; v_ti text; v_fi date; v_fv date;
  v_tasa numeric; v_motivo text;
  v_res jsonb; v_base numeric; v_tope numeric; v_dias integer; v_pol_id uuid;
  v_huella text; v_viva record; v_fila crm.solicitudes_tasa;
  v_previo text := coalesce(current_setting('crm.solicitud_tasa_por_puerta', true), 'off');
begin
  -- La AUTORIDAD se pregunta antes de mirar el JSON (auditor n2): un no autorizado muere en el 42501 uniforme sin
  -- distinguir «formato inválido»; el cliente (activo, rol cliente) se comprueba justo después de leerlo.
  if v_uid is null or not private.puede_registrar_ventas() then
    raise exception 'Cliente no encontrado o fuera de tu cartera' using errcode = '42501';
  end if;
  if p_solicitud is null or jsonb_typeof(p_solicitud) <> 'object' then
    raise exception 'Faltan los datos de la solicitud' using errcode = '22023';
  end if;
  begin
    v_cliente := (p_solicitud ->> 'cliente_id')::uuid;
    v_cat     := p_solicitud ->> 'categoria';
    v_origen  := (p_solicitud ->> 'contrato_origen_id')::uuid;
    v_pc      := (p_solicitud ->> 'producto_condicion_id')::uuid;
    v_capital := (p_solicitud ->> 'capital')::numeric;
    v_moneda  := p_solicitud ->> 'moneda';
    v_mod     := p_solicitud ->> 'modalidad';
    v_ti      := p_solicitud ->> 'tipo_interes';
    v_fi      := (p_solicitud ->> 'fecha_inicio')::date;
    v_fv      := (p_solicitud ->> 'fecha_vencimiento')::date;
    v_tasa    := round((p_solicitud ->> 'tasa_solicitada')::numeric, 2);   -- misma escala que contratos.tasa_anual (auditor m5)
    v_motivo  := btrim(p_solicitud ->> 'motivo');
  exception when others then
    raise exception 'Datos de la solicitud inválidos' using errcode = '22023';
  end;
  if not private.puede_operar_tasa_cliente(v_cliente) then
    raise exception 'Cliente no encontrado o fuera de tu cartera' using errcode = '42501';
  end if;
  if v_capital is null or v_capital < 100 or v_capital > 100000000 then
    raise exception 'El capital debe estar entre 100 y 100,000,000' using errcode = '22023';
  end if;
  if v_moneda is null or v_moneda not in ('PEN', 'USD') then
    raise exception 'Moneda inválida' using errcode = '22023';
  end if;
  if v_mod is null or v_mod not in ('mensual', 'trimestral', 'semestral', 'anual')
     or v_ti is null or v_ti not in ('simple', 'compuesto') then
    raise exception 'Modalidad o tipo de interés inválidos' using errcode = '22023';
  end if;
  if v_fi is null or v_fv is null or v_fv <= v_fi then
    raise exception 'El plazo del contrato es inválido' using errcode = '22023';
  end if;
  if v_motivo is null or length(v_motivo) < 5 or length(v_motivo) > 500 then
    raise exception 'Escribe el motivo comercial (entre 5 y 500 caracteres)' using errcode = '22023';
  end if;
  if v_tasa is null or v_tasa <= 0 then
    raise exception 'La tasa solicitada es inválida' using errcode = '22023';
  end if;

  perform private.vencer_solicitudes_tasa();
  -- EL NÚCLEO decide la base y la regla; esta puerta no calcula tasa.
  v_res := private.resolver_tasa(v_cliente, v_cat, v_origen, statement_timestamp());
  v_base := (v_res ->> 'tasa_base')::numeric;
  v_tope := (v_res #>> '{politica,tope_tecnico}')::numeric;
  v_dias := (v_res #>> '{politica,vigencia_solicitud_dias}')::integer;
  v_pol_id := (v_res #>> '{politica,id}')::uuid;
  if v_tasa <= v_base then
    raise exception 'La excepción debe ser superior a la tasa base de % %%', rtrim(rtrim(to_char(v_base, 'FM999990.99'), '0'), '.') using errcode = '22023';
  end if;
  if v_tasa > v_tope then
    raise exception 'La tasa solicitada supera el tope técnico de % %%', rtrim(rtrim(to_char(v_tope, 'FM999990.99'), '0'), '.') using errcode = '22023';
  end if;

  v_huella := private.huella_solicitud_tasa(v_cliente, v_cat, v_origen, v_pc, v_capital, v_moneda, v_mod, v_ti, v_fi, v_fv);
  perform pg_advisory_xact_lock(hashtext('crm.solicitudes_tasa'), hashtext(v_huella));
  select s.id, s.estado, s.solicitada_por into v_viva from crm.solicitudes_tasa s
   where s.huella = v_huella
     and s.estado in ('pendiente', 'aprobada', 'aprobada_con_tope', 'aceptada_por_analista')
   limit 1;
  if v_viva.id is not null then
    raise exception 'Ya hay una solicitud viva para este contrato (estado «%»)', v_viva.estado
      using errcode = 'P0409',
            detail = jsonb_build_object('solicitud_id', v_viva.id, 'estado', v_viva.estado, 'solicitada_por', v_viva.solicitada_por,
                                        'propia', v_viva.solicitada_por = v_uid)::text;
  end if;

  perform set_config('crm.solicitud_tasa_por_puerta', 'on', true);
  insert into crm.solicitudes_tasa (
    politica_id, cliente_id, categoria, contrato_origen_id, contrato_origen_numero, producto_condicion_id,
    capital, moneda, modalidad, tipo_interes, fecha_inicio, fecha_vencimiento, huella,
    tasa_base, regla_base, contratos_previos, prioridad_bandeja, tasa_solicitada, motivo,
    estado, solicitada_por, solicitada_en, vence_en
  ) values (
    v_pol_id, v_cliente, v_cat, v_origen, v_res #>> '{contrato_origen,numero_contrato}', v_pc,
    v_capital, v_moneda, v_mod, v_ti, v_fi, v_fv, v_huella,
    v_base, v_res ->> 'regla', (v_res ->> 'contratos_previos')::integer, (v_res ->> 'prioridad_bandeja')::boolean, v_tasa, v_motivo,
    'pendiente', v_uid, statement_timestamp(), statement_timestamp() + make_interval(days => v_dias)
  ) returning * into v_fila;
  perform set_config('crm.solicitud_tasa_por_puerta', v_previo, true);
  return to_jsonb(v_fila) || jsonb_build_object('ok', true, 'resolucion', v_res);
end;
$function$;
revoke all on function crm.solicitar_tasa_fn(jsonb) from public, anon, service_role;
grant execute on function crm.solicitar_tasa_fn(jsonb) to authenticated;
comment on function crm.solicitar_tasa_fn(jsonb) is
  'Rentabilidad R1: el analista pide una tasa SUPERIOR a la base para un contrato en intención {cliente_id, categoria, contrato_origen_id?, producto_condicion_id?, capital, moneda, modalidad, tipo_interes, fecha_inicio, fecha_vencimiento, tasa_solicitada, motivo}. Autoridad del alta + cliente en ámbito (42501); base y regla del núcleo; base < tasa <= tope técnico (22023); una viva por huella (P0409). Devuelve la solicitud + resolucion.';

-- 5. publicar_politica con la guarda 0A000 (el hotfix del P0409 se conserva).
create or replace function crm.publicar_politica_rentabilidad_fn(p_expected_version integer, p_config jsonb)
returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_actual integer; v_anterior uuid; v_ultimo timestamptz;
  v_tasa numeric; v_tope numeric; v_dias numeric; v_modo text; v_nota text;
  v_fila crm.politica_rentabilidad;
  v_desde timestamptz := clock_timestamp();
begin
  if v_uid is null or private.rol_crm(v_uid) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia activa publica la política de rentabilidad' using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception 'expected_version inválido' using errcode = '22023';
  end if;
  if p_config is null or jsonb_typeof(p_config) <> 'object'
     or not (p_config ?& array['tasa_base_nueva', 'tope_tecnico', 'vigencia_solicitud_dias', 'modo'])
     or (p_config - array['tasa_base_nueva', 'tope_tecnico', 'vigencia_solicitud_dias', 'modo', 'nota']) <> '{}'::jsonb
     or jsonb_typeof(p_config -> 'tasa_base_nueva') is distinct from 'number'
     or jsonb_typeof(p_config -> 'tope_tecnico') is distinct from 'number'
     or jsonb_typeof(p_config -> 'vigencia_solicitud_dias') is distinct from 'number'
     or jsonb_typeof(p_config -> 'modo') is distinct from 'string'
     or (p_config ? 'nota' and jsonb_typeof(p_config -> 'nota') not in ('string', 'null')) then
    raise exception 'Formato de política inválido' using errcode = '22023';
  end if;
  v_tasa := (p_config ->> 'tasa_base_nueva')::numeric;
  v_tope := (p_config ->> 'tope_tecnico')::numeric;
  v_dias := (p_config ->> 'vigencia_solicitud_dias')::numeric;
  v_modo := p_config ->> 'modo';
  v_nota := nullif(btrim(p_config ->> 'nota'), '');
  if v_tasa <= 0 or v_tasa > 50 or v_tope <= 0 or v_tope > 50 or v_tope < v_tasa
     or trunc(v_dias) <> v_dias or v_dias < 1 or v_dias > 30 then
    raise exception 'Política fuera de rango (tasa 0-50, tope >= tasa y <= 50, vigencia 1-30 días)' using errcode = '22023';
  end if;
  if v_modo not in ('observacion', 'enforcement') then
    raise exception 'Modo inválido: observacion o enforcement' using errcode = '22023';
  end if;
  if v_modo = 'enforcement' then
    -- R1/R2: nada lee aún el modo enforcement; publicarlo prometería un bloqueo que no existe. Se habilita en R4.
    raise exception 'El modo enforcement todavía no está construido (llega en R4); publica en observacion' using errcode = '0A000';
  end if;
  if v_nota is not null and length(v_nota) > 500 then
    raise exception 'La nota no puede superar 500 caracteres' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtext('crm.politica_rentabilidad'), 1);
  select p.id, p.version, p.vigente_desde into v_anterior, v_actual, v_ultimo
  from crm.politica_rentabilidad p order by p.version desc limit 1;
  if p_expected_version <> v_actual then
    raise exception 'Conflicto de versión: esperada %, vigente %', p_expected_version, v_actual using errcode = 'P0409';
  end if;
  if v_desde <= v_ultimo then
    v_desde := v_ultimo + interval '1 millisecond';
  end if;
  insert into crm.politica_rentabilidad (version, version_anterior_id, vigente_desde, tasa_base_nueva, tope_tecnico,
                                         vigencia_solicitud_dias, modo, nota, publicada_por)
  values (v_actual + 1, v_anterior, v_desde, v_tasa, v_tope, v_dias::integer, v_modo, v_nota, v_uid)
  returning * into v_fila;
  return to_jsonb(v_fila) || jsonb_build_object('ok', true);
end;
$function$;
comment on function crm.publicar_politica_rentabilidad_fn(integer, jsonb) is
  'Rentabilidad R1: Gerencia publica una revisión {tasa_base_nueva, tope_tecnico, vigencia_solicitud_dias, modo, nota?} con control optimista por versión (P0409). En R1 el modo enforcement se rechaza (0A000).';

-- 6. Los helpers del candado.
drop function if exists private.rentabilidad_consumir_autorizacion(public.contratos, numeric, uuid, uuid, timestamptz);
drop function if exists private.rentabilidad_consumir_autorizacion(public.contratos, numeric, uuid, timestamptz);
drop function if exists private.rentabilidad_origen_declarado(public.contratos);
drop function if exists private.rentabilidad_condicion_declarada(uuid);
drop function if exists private.rentabilidad_condicion_declarada(public.contratos);
drop function if exists private.rentabilidad_tasa_txt(numeric);

do $post$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.trg_contratos_observar_rentabilidad()')) is distinct from '8cd6c5bb1e9a51e4b20d2a6e90bedeb0' then
    raise exception 'REVERSA R4: el observador no volvió al cuerpo de R2 (8cd6c5bb…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)')) is distinct from '0fd6fa8d1d8f8106cb52662cb64193e0' then
    raise exception 'REVERSA R4: la puerta del alta no volvió a su cuerpo previo (0fd6fa8d…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.solicitar_tasa_fn(jsonb)')) is distinct from '1db7a86959289e9168147595bd6a1a3f' then
    raise exception 'REVERSA R4: crm.solicitar_tasa_fn no volvió al cuerpo de R1 (1db7a869…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.publicar_politica_rentabilidad_fn(integer,jsonb)')) is distinct from '5519377757c09621da1671fb60b9f49f' then
    raise exception 'REVERSA R4: publicar_politica_rentabilidad_fn no volvió al cuerpo del hotfix (55193777…)';
  end if;
  if to_regprocedure('private.rentabilidad_consumir_autorizacion(public.contratos,numeric,uuid,uuid,timestamptz)') is not null
     or to_regprocedure('private.rentabilidad_origen_declarado(public.contratos)') is not null
     or to_regprocedure('private.rentabilidad_condicion_declarada(uuid)') is not null
     or to_regprocedure('private.rentabilidad_tasa_txt(numeric)') is not null then
    raise exception 'REVERSA R4: quedó algún helper vivo';
  end if;
  if not exists (select 1 from pg_trigger t where t.tgname = 'trg_contratos_zz_observar_rentabilidad'
                   and t.tgrelid = 'public.contratos'::regclass and t.tgdeferrable and t.tginitdeferred and t.tgenabled = 'O'
                   and (select count(*) from unnest(t.tgattr::int2[]) a) = 7) then
    raise exception 'REVERSA R4: el trigger no volvió a las 7 columnas de R2';
  end if;
  -- El hito NO se borra (crm.rentabilidad_hitos es append-only por trigger, y además es un hecho histórico):
  -- se le anota la reversa.
  update crm.rentabilidad_hitos
     set valor = valor || jsonb_build_object('revertido_en', clock_timestamp())
   where clave = 'enforcement_construido_desde';
  delete from supabase_migrations.schema_migrations where version = '20260907093000';
  raise notice 'REVERSA RENTABILIDAD R4 OK: candado desmontado, observador y trigger de R2 restaurados, versión 20260907093000 desregistrada si estaba (la tarjeta de Gerencia se queda contando las dos orillas: a propósito)';
end
$post$;
commit;

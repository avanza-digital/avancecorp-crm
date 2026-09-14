-- Solo antes del primer uso de una tasa inferior. Revisión humana antes de publicar.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
-- Drena también las lecturas/bloqueos del lead que preceden a validar una reserva.
-- Si no puede obtenerse en 5 segundos, se aborta sin restaurar ninguna función.
lock table public.contratos,crm.leads,crm.conversion_reservas,crm.ledger_rentabilidad in access exclusive mode;
do $preflight$ begin
 if exists(select 1 from crm.ledger_rentabilidad where detalle->>'tasa_inferior_sin_excepcion'='true') then
   raise exception 'Ya existen tasas inferiores registradas: corregir hacia delante; no restaurar el candado anterior';
 end if;
 if exists(
   select 1 from crm.conversion_reservas r join crm.leads l on l.id=r.lead_id
   cross join lateral (
     select p.tasa_base_nueva from crm.politica_rentabilidad p
     where p.vigente_desde<=coalesce(r.efectos_iniciados_en,r.reservado_en)
     order by p.vigente_desde desc,p.version desc limit 1
   ) vigente
   where r.condiciones_tasa->>'categoria'='nuevo'
     and (r.condiciones_tasa->>'tasa_anual')::numeric<greatest(vigente.tasa_base_nueva,
       (select p.tasa_base_nueva from crm.politica_rentabilidad p where p.vigente_desde<=now()
        order by p.vigente_desde desc,p.version desc limit 1))
     and (r.expira_en>now() or r.efectos_iniciados_en is not null or l.etapa='convertido')
 ) then
   raise exception 'Hay conversiones comprometidas con una tasa inferior: corregir hacia delante, aunque aún no exista contrato';
 end if;
 if (select md5(prosrc) from pg_proc where oid=to_regprocedure('crear_contrato(jsonb,jsonb)')) is distinct from '1adfbe1a72739a1863c7321c3fd20439' then raise exception 'La función crear_contrato(jsonb,jsonb) cambió después de la candidata'; end if;
 if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.resolver_tasa(uuid,text,uuid,timestamp with time zone,uuid)')) is distinct from '12456bd7ecb3fa4673885bd468ba9339' then raise exception 'La función private.resolver_tasa(uuid,text,uuid,timestamp with time zone,uuid) cambió después de la candidata'; end if;
 if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.trg_contratos_observar_rentabilidad()')) is distinct from '24846a709156006298e10edd65ee3ef9' then raise exception 'La función private.trg_contratos_observar_rentabilidad() cambió después de la candidata'; end if;
 if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.validar_tasa_conversion_lead(uuid,uuid,jsonb,boolean)')) is distinct from 'fba3d4ed01dc9fd440ab945d63010099' then raise exception 'La función private.validar_tasa_conversion_lead(uuid,uuid,jsonb,boolean) cambió después de la candidata'; end if;
end; $preflight$;
CREATE OR REPLACE FUNCTION private.resolver_tasa(p_cliente_id uuid, p_categoria text, p_contrato_origen_id uuid, p_instante timestamp with time zone, p_contrato_nuevo_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_pol      crm.politica_rentabilidad;
  v_cli      record;
  v_origen   public.contratos%rowtype;
  v_previos  integer;
  v_activos  integer;
  v_base     numeric;
  v_regla    text;
begin
  -- Sin perfil aún: únicamente una intención nueva sin origen; misma política central.
  if p_cliente_id is null and (p_categoria is distinct from 'nuevo' or p_contrato_origen_id is not null) then
    raise exception 'Una renovación o ampliación requiere su cliente y contrato origen' using errcode='22023';
  end if;
  if p_categoria is null or p_categoria not in ('nuevo', 'renovacion', 'upgrade') then
    raise exception 'Selecciona la categoría del contrato (nuevo, renovacion o upgrade)' using errcode = '22023';
  end if;
  v_pol := private.politica_rentabilidad_vigente(p_instante);
  if v_pol.id is null then
    raise exception 'No hay política de rentabilidad vigente' using errcode = 'P0002';
  end if;
  select p.id, p.activo, p.asesor_perfil_id into v_cli
  from public.perfiles p where p.id = p_cliente_id and p.rol = 'cliente';
  if p_cliente_id is not null and v_cli.id is null then
    raise exception 'Cliente no encontrado' using errcode = 'P0002';
  end if;
  if p_cliente_id is not null and v_cli.activo is not true then
    raise exception 'El cliente está inactivo' using errcode = 'P0409';
  end if;
  -- «Previos» = los contratos del cliente sin contar el que se está observando (al commit, el nuevo ya existe).
  select count(*), count(*) filter (where c.estado = 'activo')
    into v_previos, v_activos
  from public.contratos c
  where c.cliente_id = p_cliente_id and not c.es_demo and c.id is distinct from p_contrato_nuevo_id;

  if p_categoria = 'nuevo' then
    if p_contrato_origen_id is not null then
      raise exception 'Una primera inversión no lleva contrato origen' using errcode = '22023';
    end if;
    v_base := v_pol.tasa_base_nueva;
    v_regla := 'primera_inversion';
  else
    if p_contrato_origen_id is null then
      raise exception 'Selecciona el contrato que se % (contrato origen)', case when p_categoria = 'renovacion' then 'renueva' else 'amplía' end
        using errcode = '22023';
    end if;
    select * into v_origen from public.contratos c where c.id = p_contrato_origen_id;
    if v_origen.id is null then
      raise exception 'El contrato origen no existe' using errcode = 'P0002';
    end if;
    if v_origen.cliente_id is distinct from p_cliente_id then
      raise exception 'El contrato origen pertenece a otro cliente' using errcode = 'P0409';
    end if;
    if p_categoria = 'renovacion' then
      -- Mismo criterio que public.crear_contrato: se renueva un contrato activo o vencido que aún no fue renovado…
      -- …salvo que ya haya quedado renovado POR ESTE contrato (observación al commit): sigue siendo su origen.
      -- IS NOT TRUE (no «NOT»): con renovado_a_id NULL la segunda alternativa es NULL y un «NOT NULL» dejaría pasar un
      -- origen retirado (Codex R2 #3). La segunda alternativa exige además estado 'renovado'.
      if (
           (v_origen.estado in ('activo', 'vencido') and v_origen.renovado_a_id is null)
        or (p_contrato_nuevo_id is not null and v_origen.estado = 'renovado' and v_origen.renovado_a_id = p_contrato_nuevo_id)
      ) is not true then
        raise exception 'El contrato origen ya fue cerrado o renovado (estado «%»)', v_origen.estado using errcode = 'P0409';
      end if;
      v_regla := 'heredada_renovacion';
    else
      -- D2: el upgrade amplía un contrato ACTIVO concreto que el analista selecciona.
      if v_origen.estado <> 'activo' or v_origen.renovado_a_id is not null then
        raise exception 'El upgrade solo amplía un contrato activo (este está «%»)', v_origen.estado using errcode = 'P0409';
      end if;
      v_regla := 'heredada_upgrade';
    end if;
    v_base := v_origen.tasa_anual;
  end if;

  return jsonb_build_object(
    'tasa_base', v_base,
    'regla', v_regla,
    'categoria', p_categoria,
    'cliente_id', p_cliente_id,
    'contrato_origen', case when v_origen.id is null then null else jsonb_build_object(
        'id', v_origen.id, 'numero_contrato', v_origen.numero_contrato, 'tasa_anual', v_origen.tasa_anual,
        'estado', v_origen.estado, 'moneda', v_origen.moneda, 'capital', v_origen.capital,
        'fecha_vencimiento', v_origen.fecha_vencimiento) end,
    'contratos_previos', v_previos,
    'contratos_activos', v_activos,
    'prioridad_bandeja', (p_categoria = 'nuevo' and v_previos > 0),
    'politica', jsonb_build_object('id', v_pol.id, 'version', v_pol.version, 'modo', v_pol.modo,
        'tasa_base_nueva', v_pol.tasa_base_nueva, 'tope_tecnico', v_pol.tope_tecnico,
        'vigencia_solicitud_dias', v_pol.vigencia_solicitud_dias),
    'resuelto_en', coalesce(p_instante, statement_timestamp())
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION private.trg_contratos_observar_rentabilidad()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '2s'
AS $function$
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
  -- R4 (el candado)
  v_modo       text;               -- modo de la política vigente (null = no se pudo leer)
  v_enforce    boolean := false;
  v_anotar     boolean := true;    -- ¿toca escribir la fila del libro en esta transacción?
  v_en_juego   boolean := false;   -- ¿esta transacción fija o altera la tasa (o la intención que la amparaba)?
  v_huella_mov boolean := false;   -- ¿cambió alguna dimensión de la huella autorizada?
  v_rechazo    text;               -- motivo del rechazo (se lanza FUERA del manejador)
  v_origen_dec uuid;               -- origen DECLARADO por la puerta (upgrade, D2)
  v_cond       uuid;               -- condición DECLARADA (null cuando es el snapshot legacy del puente)
  v_aut        jsonb;
  v_solicitud  uuid;
begin
 -- TODO el cuerpo va bajo una excepción externa: el observador no puede abortar un alta ni una corrección. lock_timeout=2s
 -- convierte una espera de candado en 55P03 (atrapable). Lo único que WHEN OTHERS no atrapa es query_canceled (57014):
 -- en PostgreSQL 17 statement_timeout se desactiva antes del commit, y aquí no hay más esperas que las de candado.
 begin
  select * into v_c from public.contratos c where c.id = new.id;
  if v_c.id is null then
    return null;   -- borrado en la misma transacción: nada que observar
  end if;
  -- UNA fila de libro por contrato y transacción: varios eventos (alta + correcciones en la misma tx) → una sola foto
  -- FINAL. El marcador es un GUC transaccional (se fija también cuando el cambio neto es vacío: 15→18→15 no es una
  -- corrección; Codex R2 #25). OJO (Codex R4 #4): el marcador decide solo si se ESCRIBE en el libro; NO exime de
  -- validar. Con SET CONSTRAINTS ALL IMMEDIATE a mitad de transacción el trigger vuelve a dispararse, y antes se
  -- saltaba la comprobación: un alta válida servía de pasaporte a una corrección no autorizada.
  v_anotar := coalesce(current_setting(v_marca, true), '') <> '1';
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
      'fecha_vencimiento', case when old.fecha_vencimiento is distinct from v_c.fecha_vencimiento then jsonb_build_array(old.fecha_vencimiento, v_c.fecha_vencimiento) end,
      -- R4 (Codex #1): la huella de una autorización también lleva modalidad, tipo de interés y producto. Si no se
      -- comparan, una autorización para 20 000 a 12 meses ampara luego 100 000 a 24: bastaba corregir el capital.
      'modalidad',         case when old.modalidad             is distinct from v_c.modalidad             then jsonb_build_array(old.modalidad, v_c.modalidad) end,
      'tipo_interes',      case when old.tipo_interes          is distinct from v_c.tipo_interes          then jsonb_build_array(old.tipo_interes, v_c.tipo_interes) end,
      -- Se compara la condición DECLARADA, no el id crudo: el puente legacy sintetiza un snapshot NUEVO en cada
      -- cambio de términos, y eso no mueve la huella (declarada = null en las dos orillas). Cambiar de producto de
      -- catálogo sí la mueve.
      'producto_condicion_id', case when private.rentabilidad_condicion_declarada(old.producto_condicion_id)
                                      is distinct from private.rentabilidad_condicion_declarada(v_c.producto_condicion_id)
                                    then jsonb_build_array(old.producto_condicion_id, v_c.producto_condicion_id) end,
      -- R4 (Codex #6): pasar un contrato de prueba a real es un cambio de rentabilidad como cualquier otro.
      'es_demo',           case when old.es_demo               is distinct from v_c.es_demo               then jsonb_build_array(old.es_demo, v_c.es_demo) end));
    if v_cambios = '{}'::jsonb then
      return null;
    end if;
  end if;
  v_pol := private.politica_rentabilidad_vigente(statement_timestamp());
  if v_pol.id is null then
    return null;   -- sin política publicada no se observa (R1 garantiza la v1)
  end if;
  -- R4: el interruptor. En «observacion» este trigger hace EXACTAMENTE lo de R2 (mide, no bloquea).
  v_modo := v_pol.modo;
  v_enforce := (v_modo = 'enforcement');

  -- En una CORRECCIÓN que no cambia cliente ni categoría, la base de comparación es la RESOLUCIÓN ORIGINAL del alta
  -- (base, regla, origen), no una reevaluación con el estado de hoy (Codex R2 #8). Si cambió cliente o categoría, se resuelve de nuevo.
  v_pol_id := v_pol.id;
  if tg_op = 'UPDATE' and not (v_cambios ? 'categoria' or v_cambios ? 'cliente_id') then
    -- Solo se conserva una resolución del MISMO cliente y la MISMA categoría (Codex R2 #20), con la política que la produjo (#21).
    select l.tasa_base, l.regla, l.contrato_origen_id, l.politica_id, l.id, l.detalle ->> 'motivo' as motivo into v_prev
    from crm.ledger_rentabilidad l
    where l.contrato_id = v_c.id and l.origen in ('observacion', 'enforcement')
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

  -- El origen declarado se lee UNA sola vez: la lectura consume la declaración, para que un segundo contrato de la
  -- misma transacción no herede la del primero (Codex R4 #5).
  if v_c.categoria = 'upgrade' then
    v_origen_dec := private.rentabilidad_origen_declarado(v_c);
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
      elsif v_c.categoria = 'upgrade' and v_origen_dec is not null then
        -- D2: el upgrade DECLARA el contrato que amplía. R4: la puerta del CRM lo publica y aquí SÍ es una regla
        -- (heredada_upgrade), no una hipótesis.
        v_res := private.resolver_tasa(v_c.cliente_id, v_c.categoria, v_origen_dec, statement_timestamp(), v_c.id);
        v_base := (v_res ->> 'tasa_base')::numeric; v_regla := v_res ->> 'regla'; v_origen := v_origen_dec;
      elsif v_c.categoria = 'upgrade' then
        -- Sin declaración (portal, RPC antigua, alta anterior a R3) se mantiene lo de R2: solo se apunta el candidato
        -- único —contrato activo del cliente que ya EXISTÍA antes y seguía vigente al inicio del nuevo— como
        -- hipótesis, y queda sin_regla (una inferencia no es una regla; Codex R2 #7). Bajo enforcement se rechaza.
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

  -- ── R4 · EL CANDADO ──────────────────────────────────────────────────────────────────────────────────────────
  -- Solo con la política en enforcement, y nunca sobre datos de prueba. La tasa se juzga cuando ESTA transacción la
  -- fija (alta), la cambia (corrección) o mueve la INTENCIÓN que amparaba una tasa excepcional: conservar una tasa
  -- por encima de la base exige conservar el contrato que Gerencia autorizó (Codex R4 #1).
  if v_enforce and v_c.es_demo is not true then
    v_huella_mov := (tg_op = 'UPDATE') and (v_cambios ?| array['capital', 'moneda', 'fecha_inicio', 'fecha_vencimiento',
                     'modalidad', 'tipo_interes', 'producto_condicion_id', 'categoria', 'cliente_id']);
    v_en_juego := (tg_op = 'INSERT')
      or (v_cambios ? 'tasa_anual')
      -- Pasar de prueba a real es un alta a efectos de la política.
      or (v_cambios ? 'es_demo')
      -- Tasa por encima de la base + intención movida = la autorización ya no ampara esto.
      or (v_huella_mov and v_base is not null and v_c.tasa_anual is distinct from v_base);
    if v_en_juego then
      if v_regla = 'sin_regla' then
        -- Sin regla no hay base con la que comparar: bajo enforcement no pasa, y se dice qué falta.
        v_rechazo := case coalesce(v_motivo, '')
          when 'categoria_nula' then 'El contrato debe declarar su categoría (nuevo, renovación o upgrade).'
          when 'renovacion_sin_origen_registrado' then 'La renovación debe declarar el contrato que renueva.'
          when 'upgrade_origen_inferido' then 'El upgrade debe declarar el contrato que amplía: regístralo desde el CRM.'
          when 'upgrade_origen_ambiguo' then 'El upgrade debe declarar el contrato que amplía: regístralo desde el CRM.'
          when 'upgrade_sin_contrato_activo_previo' then 'Un upgrade amplía un contrato activo del cliente y no se encontró ninguno.'
          else 'No se pudo determinar qué tasa corresponde a este contrato (' || coalesce(v_motivo, 'sin motivo') || '). La tasa la decide la política.'
        end;
      elsif v_c.tasa_anual < v_base then
        -- D4: por debajo de la base no se autoriza nada, así que tampoco se ofrece pedir permiso (Codex R4 #12).
        v_rechazo := 'La tasa de este contrato la fija la política: ' || private.rentabilidad_tasa_txt(v_base)
          || '%, y no puede quedar por debajo. Corrige la tasa antes de guardar.';
      elsif v_c.tasa_anual > v_base then
        -- Por encima de la base: solo pasa con una autorización VIVA de Gerencia para esta MISMA intención (huella),
        -- que se consume aquí, en esta transacción y de un solo uso.
        v_cond := private.rentabilidad_condicion_declarada(v_c.producto_condicion_id);
        v_aut := private.rentabilidad_consumir_autorizacion(v_c, v_base, v_origen, v_cond, statement_timestamp());
        if v_aut is null then
          v_rechazo := 'La tasa de este contrato la fija la política: ' || private.rentabilidad_tasa_txt(v_base)
            || '%. Para cerrar a ' || private.rentabilidad_tasa_txt(v_c.tasa_anual)
            || '% hace falta una autorización vigente de Gerencia para estos mismos datos (cliente, capital, plazo, modalidad y origen).';
        else
          v_solicitud := (v_aut ->> 'solicitud_id')::uuid;
        end if;
      end if;
    end if;
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
    'modo', v_modo,
    'tasa_en_juego', case when v_enforce then v_en_juego end,
    'huella_movida', case when v_enforce and tg_op = 'UPDATE' then v_huella_mov end,
    'autorizacion', v_aut,
    'origen_declarado', v_origen_dec,
    'resolucion', case when v_res is null then null else v_res - 'politica' - 'cliente_id' - 'categoria' end
  ));
  -- Si el candado rechaza no se anota nada (la transacción se aborta unas líneas más abajo); y solo se escribe UNA
  -- fila por contrato y transacción. OJO: no se puede «return» aquí — un return sale de la función y el rechazo, que
  -- vive fuera del manejador, nunca se lanzaría.
  if v_rechazo is null and v_anotar then
  begin
    insert into crm.ledger_rentabilidad (
      contrato_id, numero_contrato, cliente_id, categoria, contrato_origen_id, politica_id, solicitud_id,
      tasa_base, tasa_final, tasa_recibida, regla, origen, actor_id, detalle
    ) values (
      v_c.id, v_c.numero_contrato, v_c.cliente_id, v_c.categoria, v_origen, v_pol_id, v_solicitud,
      v_base, v_c.tasa_anual, v_c.tasa_anual, v_regla,
      case when v_enforce then 'enforcement' else 'observacion' end, (select auth.uid()), v_detalle
    );
  exception when others then
    if v_enforce then
      -- Bajo enforcement no puede pasar un contrato SIN su fila en el libro: el candado también falla cerrado aquí.
      v_rechazo := 'No se pudo registrar la tasa de este contrato en el libro de rentabilidad (' || sqlstate || '). Reintenta.';
    else
      raise warning 'RENTABILIDAD R2: no se pudo observar el contrato % (% %)', v_c.id, sqlstate, sqlerrm;
    end if;
  end;
  end if;
 exception when others then
  if v_enforce then
    -- Bajo enforcement el candado FALLA CERRADO: si no pudo verificar la tasa, el contrato no pasa. La vuelta atrás
    -- es publicar la política en «observacion» (sin migración).
    v_rechazo := 'No se pudo verificar la tasa contra la política de rentabilidad (' || sqlstate || '). Reintenta; si persiste, avisa a Gerencia.';
  else
    -- Límite DECLARADO y deliberado (frente a Codex R4 #7): si el fallo impidió incluso LEER el modo, v_enforce sigue
    -- en false y el contrato pasa. Fallar cerrado ahí convertiría un problema al leer una tabla de una fila en una
    -- parada de TODAS las altas mientras el candado está apagado, que es justo lo que estas fases prometen no hacer.
    -- El contrato queda sin fila en el libro, así que la tarjeta de Gerencia lo cuenta como hueco de cobertura.
    raise warning 'RENTABILIDAD R2: el observador falló y se ignora (% %) en el contrato %', sqlstate, sqlerrm, new.id;
  end if;
 end;

 -- Fuera del manejador de observación: ni los errores ni P0411 se ignoran.
 -- R4 ya resolvió el origen y consumió su GUC una sola vez; no volver a leerlo.
 if tg_op = 'INSERT' and v_c.id is not null and v_c.es_demo is not true then
   perform private.rentabilidad_exigir_respuesta(v_c.cliente_id, v_c.categoria, coalesce(v_origen, v_origen_dec));
 end if;
 -- El rechazo vive AQUÍ, fuera del manejador: dentro, el propio WHEN OTHERS se lo tragaría.
 if v_rechazo is not null then
   raise exception '%', v_rechazo using errcode = 'P0410';
 end if;
 return null;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.validar_tasa_conversion_lead(p_lead uuid, p_cliente uuid, p_i jsonb, p_solo_pendientes boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_cliente uuid := coalesce(p_cliente,private.cliente_tasa_lead(p_lead));
 v_categoria text := coalesce(p_i->>'categoria','nuevo');
 v_origen uuid := (p_i->>'contrato_origen_id')::uuid;
 v_base numeric; v_tasa numeric; v_ahora timestamptz := clock_timestamp(); v_huella text; v_huella_lead text;
begin
 -- El caller conserva los locks de identidad/lead; operación viene después.
 perform private.rentabilidad_bloquear_operacion(v_cliente,v_categoria,v_origen);
 if exists(select 1 from crm.solicitudes_tasa s where
     (s.lead_id=p_lead or (v_cliente is not null and s.cliente_id=v_cliente and s.categoria=v_categoria
       and s.contrato_origen_id is not distinct from v_origen))
     and s.estado='pendiente' and s.vence_en>v_ahora) then
   raise exception 'La solicitud de tasa está pendiente de Gerencia. Espera su respuesta antes de convertir, incluso a la tasa base.' using errcode='P0411';
 end if;
 if exists(select 1 from crm.solicitudes_tasa s join crm.leads l on l.id=s.lead_id
   where s.lead_id=p_lead and s.documento_lead is not null
     and s.estado in ('pendiente','aprobada','aprobada_con_tope','aceptada_por_analista') and s.vence_en>v_ahora
     and (s.documento_lead is distinct from l.dni or (p_cliente is not null and s.documento_lead is distinct from (select p.dni from public.perfiles p where p.id=p_cliente)))) then
   raise exception 'El documento cambió después de solicitar la tasa. La aprobación no corresponde a esta persona.' using errcode='P0409';
 end if;
 if p_solo_pendientes then return; end if;
 if p_i is null or p_i='null'::jsonb then
   if exists(select 1 from crm.solicitudes_tasa s where s.lead_id=p_lead
     and s.estado in ('aprobada','aprobada_con_tope','aceptada_por_analista') and s.vence_en>v_ahora) then
     raise exception 'Confirma las condiciones de inversión desde la ficha del lead antes de convertir.' using errcode='P0410';
   end if;
   return; -- Cliente anterior sin propuesta: la base se controla igualmente al contratar.
 end if;
 if jsonb_typeof(p_i)<>'object' or (p_i->>'capital')::numeric is null
   or (p_i->>'capital')::numeric not between 100 and 100000000
   or coalesce(p_i->>'moneda','') not in ('PEN','USD')
   or coalesce(p_i->>'modalidad','') not in ('mensual','trimestral','semestral','anual')
   or coalesce(p_i->>'tipo_interes','') not in ('simple','compuesto')
   or (p_i->>'fecha_inicio')::date is null or (p_i->>'fecha_vencimiento')::date is null
   or (p_i->>'fecha_vencimiento')::date <= (p_i->>'fecha_inicio')::date then
   raise exception 'Completa las condiciones de inversión antes de convertir.' using errcode='22023';
 end if;
 v_base := (private.resolver_tasa(v_cliente,v_categoria,v_origen,v_ahora,null)->>'tasa_base')::numeric;
 v_tasa := (p_i->>'tasa_anual')::numeric;
 if v_tasa is null or v_tasa<v_base or v_tasa>50 or v_tasa<>round(v_tasa,2) then
   raise exception 'La tasa no está dentro del rango permitido.' using errcode='P0410';
 end if;
 if v_tasa=v_base then return; end if;
 -- Una reserva ya sellada conserva la validación del punto de no retorno.
 -- La vigencia ACTUAL sigue siendo obligatoria al crear el contrato (R4).
 select coalesce(r.efectos_iniciados_en,v_ahora) into v_ahora from crm.conversion_reservas r where r.lead_id=p_lead;
 v_ahora:=coalesce(v_ahora,clock_timestamp());
 v_huella:=private.huella_intencion_tasa(coalesce(v_cliente,p_lead),p_i);
 v_huella_lead:=private.huella_intencion_tasa(p_lead,p_i);
 if not exists(select 1 from crm.solicitudes_tasa s where
   ((s.lead_id=p_lead and s.huella in (v_huella,v_huella_lead)) or (s.cliente_id=v_cliente and s.huella=v_huella))
   and s.estado in ('aprobada','aceptada_por_analista') and s.vence_en>=v_ahora
   and s.tasa_maxima_autorizada>=v_tasa) then
   raise exception 'La tasa requiere una aprobación vigente para estas mismas condiciones. Si hubo un tope, acéptalo primero.' using errcode='P0410';
 end if;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.crear_contrato(p_contrato jsonb, p_cronograma jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
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
  v_anio integer := extract(year from now() at time zone 'America/Lima')::integer;
  v_contrato_id uuid;
  v_fecha_operacion date;
  v_periodo date;
  v_cuota jsonb;
  v_asesor_id uuid;
  v_asesor_rol text;
  v_operacion_id uuid;
  v_origen_id uuid;
  v_origen public.contratos%rowtype;
  v_capital_renovado numeric;
  v_capital_adicional numeric;
  v_primer_periodo date;
  v_upgrade_elegible boolean;
  v_analista_cierre uuid;
begin
  perform private.inversiones_escritura_bajo_candado(); -- F4: bandera antes de persona/cuenta/PDF
  if p_contrato is null or jsonb_typeof(p_contrato) <> 'object' then
    raise exception 'Faltan los datos del contrato' using errcode = '22023';
  end if;
  begin
    v_cliente_id := (p_contrato->>'cliente_id')::uuid;
    v_capital := (p_contrato->>'capital')::numeric;
  exception when invalid_text_representation then
    raise exception 'Cliente o capital inválido' using errcode = '22023';
  end;

  -- Vincula autorización y escritura a la misma versión de la cartera. Una
  -- reasignación concurrente espera este lock; si ganó antes, aquí ya se lee el
  -- nuevo Analista y el anterior queda fuera del gate.
  -- F2.b (E4) [D-1, OK de Miguel 05/09]: con la identidad unificada ENCENDIDA, crear un contrato RECONOCE
  -- a la persona ANTES del FOR SHARE de abajo (jerarquía -> documento -> identidad -> perfil, reentrante).
  -- Solo si el cliente existe activo (así un id inexistente sigue muriendo en el 42501 de siempre).
  -- Sin documento válido o con documento de otra persona reconocida -> P0409 (contrato §4.3, fail-closed).
  -- [auditor A1] la AUTORIDAD se pregunta antes de reconocer: un no autorizado sigue muriendo en el 42501 uniforme
  -- de abajo (sin aprender nada del documento), con ON igual que con OFF.
  if private.resolver_en_puertas_bajo_candado()
     and (select private.puede_registrar_ventas())
     and exists (select 1 from public.perfiles p where p.id = v_cliente_id and p.rol = 'cliente' and p.activo) then
    perform private.asegurar_identidad_perfil(v_cliente_id, 'contrato');
  end if;
  select p.asesor_perfil_id into v_asesor_id
  from public.perfiles p
  where p.id = v_cliente_id and p.rol = 'cliente' and p.activo
  for share;
  if not found then
    raise insufficient_privilege using
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;

  if not (select private.puede_registrar_ventas()) then
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

  -- EL ANALISTA QUE CIERRA (decision 2 del plan P-055). Es de quien VENDIO, no
  -- de quien tecleo: `creado_por` se conserva aparte y no se pisa.
  begin
    v_analista_cierre := nullif(btrim(coalesce(p_contrato->>'analista_cierre_id', '')), '')::uuid;
  exception when invalid_text_representation then
    raise exception 'El analista que cierra no es valido' using errcode = '22023';
  end;

  if v_analista_cierre is not null then
    -- Elegido a mano: tiene que poder tener ventas. SOLO ACTIVOS (decision de
    -- Miguel, 29/08): una venta NUEVA es de alguien que esta trabajando; la
    -- venta vieja de alguien que se fue entra por la reasignacion de gerencia
    -- (que si acepta inactivos, con motivo y rastro). Y los roles OFF-ROSTER
    -- (coordinador, directorio) no son organigrama comercial por diseno.
    if not exists (
      select 1 from crm.equipo e where e.perfil_id = v_analista_cierre
        and e.activo
        and e.rol_crm in ('vendedor','supervisor','gerencia')
    ) then
      raise exception 'El analista que cierra tiene que estar activo en el equipo comercial'
        using errcode = '22023';
    end if;
  else
    -- No vino. «Si no corresponde a nadie, lo pone a su nombre» (decision 2):
    -- eso solo tiene sentido si quien registra PUEDE tener ventas. Si no puede
    -- -una administrativa, por ejemplo-, tiene que elegir a quien corresponde.
    if not exists (select 1 from crm.equipo e where e.perfil_id = v_uid and e.activo) then
      raise exception 'Elige el analista de la venta'
        using errcode = '22023',
              hint = 'Quien registra no forma parte del equipo comercial, asi que la venta no puede quedar a su nombre.';
    end if;
    v_analista_cierre := v_uid;
  end if;

  -- Las operaciones de cartera necesitan un dueño congelado. No se atribuye a
  -- quien digitó: se atribuye al Analista de perfiles.asesor_perfil_id.
  if v_categoria in ('renovacion', 'upgrade') then
    select e.rol_crm into v_asesor_rol
    from crm.equipo e
    where e.perfil_id = v_asesor_id and e.activo
    for share;
    if v_asesor_id is null
       or not found
       or v_asesor_rol not in ('vendedor', 'supervisor') then
      raise exception using
        errcode = '22023',
        message = 'Asigna un Analista activo al cliente antes de registrar la operación';
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
    v_numero := private.siguiente_numero_contrato(v_anio);
  end if;
  if exists (select 1 from public.contratos c where c.numero_contrato = v_numero) then
    raise exception 'El N de contrato % ya existe', v_numero;
  end if;

  insert into public.contratos (
    cliente_id, numero_contrato, capital, moneda, tasa_anual, modalidad,
    tipo_interes, fecha_inicio, fecha_vencimiento, notas_internas,
    categoria, estado, creado_por, analista_cierre_id
  ) values (
    v_cliente_id, v_numero, v_capital, v_moneda,
    (p_contrato->>'tasa_anual')::numeric, p_contrato->>'modalidad',
    coalesce(nullif(p_contrato->>'tipo_interes', ''), 'simple'),
    (p_contrato->>'fecha_inicio')::date,
    (p_contrato->>'fecha_vencimiento')::date,
    nullif(btrim(coalesce(p_contrato->>'notas_internas', '')), ''),
    v_categoria, 'activo', v_uid, v_analista_cierre
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
$function$
;
drop function private.rentabilidad_minimo_alta(text,numeric);
notify pgrst, 'reload schema';
commit;

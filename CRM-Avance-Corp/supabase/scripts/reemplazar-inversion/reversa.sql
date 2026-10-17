-- Reversa de 20261017162053_crm_reemplazar_inversion.sql («Reemplazar inversión», Fase 1).
-- Retira las dos puertas y los dos núcleos, y devuelve private.trg_contratos_observar_rentabilidad a su cuerpo de
-- producción del 17/10/2026 (huella 9a0c04118488b8ec0058a40d71cebcec). La columna crm.inversiones_eliminadas.reemplazada_por
-- y su CHECK se retiran SOLO si ninguna copia la usa (si ya hubo reemplazos, se conservan: la copia es inmutable y es la
-- única memoria de qué contrato quedó). Falla cerrado si el candado de tasa no tiene la huella que dejó la migración.
-- Aplicar en UN mensaje (`supabase db query --linked --file`), como la migración.
-- VOLVER A APLICAR después de una reversa que CONSERVÓ la columna (ya hubo reemplazos): la migración se niega en su
-- preflight («los objetos nuevos ya existen»). En ese caso no se reaplica a ciegas: se escribe una migración nueva que
-- reinstale solo las funciones y el candado (la columna y su CHECK ya están).
begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

begin;
set transaction isolation level repeatable read;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
begin
  if md5(pg_catalog.pg_get_functiondef('private.trg_contratos_observar_rentabilidad()'::regprocedure))
       is distinct from '1606e0a61a83f80a7873d7fafe7c4faa' then
    raise exception 'REVERSA reemplazar_inversion: el candado de tasa no tiene la huella que dejó la migración';
  end if;
end
$preflight$;

drop function crm.reemplazar_inversion_fn(uuid, text, jsonb, jsonb, jsonb);
drop function crm.reemplazar_inversion_por_existente_fn(uuid, uuid, text);
drop function private.reemplazar_inversion_avance(uuid, jsonb, uuid, text, jsonb, jsonb, jsonb, uuid);
drop function private.registrar_inversion_reemplazada_avance(jsonb, uuid, uuid, text, text, uuid, text, jsonb);

-- El candado de tasa, idéntico a producción del 17/10/2026 (candados-produccion/trg_contratos_observar_rentabilidad.sql).
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
  v_admin_corr boolean := false;
  v_admin_motivo text;
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
  if tg_op = 'UPDATE' then
    v_admin_motivo := nullif(btrim(current_setting('crm.tasa_admin_motivo', true)), '');
    v_admin_corr := coalesce(v_c.tasa_anual is distinct from old.tasa_anual
      and current_setting('crm.tasa_admin_contrato_id', true) = v_c.id::text
      and length(v_admin_motivo) between 5 and 500
      and not (v_cambios ?| array['capital', 'moneda', 'fecha_inicio', 'fecha_vencimiento',
                       'modalidad', 'tipo_interes', 'producto_condicion_id', 'categoria', 'cliente_id'])
      and public.es_admin(), false);
    if v_admin_corr then
      v_en_juego := true;
      v_huella_mov := v_cambios ?| array['capital', 'moneda', 'fecha_inicio', 'fecha_vencimiento',
                       'modalidad', 'tipo_interes', 'producto_condicion_id', 'categoria', 'cliente_id'];
    end if;
  end if;

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
  if v_enforce and v_c.es_demo is not true and not v_admin_corr then
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
      elsif v_c.tasa_anual < v_base and not (
        v_c.categoria in ('nuevo','upgrade')
        and v_c.tasa_anual >= private.rentabilidad_minimo_alta(v_c.categoria,v_base)
        and (tg_op='INSERT' or (tg_op='UPDATE'
          and old.categoria=v_c.categoria and old.es_demo is not true
          and old.cliente_id is not distinct from v_c.cliente_id
          and old.tasa_anual is not distinct from v_c.tasa_anual))
      ) then
        -- Alta nueva y upgrade admiten una tasa menor. Una corrección solo
        -- conserva esa tasa; no concede permiso para rebajar contratos emitidos.
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
    'tasa_inferior_sin_excepcion', case when v_c.categoria in ('nuevo','upgrade') and v_c.tasa_anual<v_base then true end,
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
    'correccion_admin_directa', case when v_admin_corr then true end,
    'motivo_correccion_admin', case when v_admin_corr then v_admin_motivo end,
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

 -- El modo observación retira aprobaciones, no las validaciones numéricas.
 -- Fuera del manejador: un error de rango nunca se convierte en un WARNING.
 if v_modo = 'observacion' and v_c.es_demo is not true
    and (tg_op = 'INSERT' or v_cambios ?| array['tasa_anual','es_demo'])
    and (v_c.tasa_anual is null or v_c.tasa_anual < 0.01
      or v_c.tasa_anual > least(50,greatest(v_pol.tope_tecnico,case when v_c.categoria in ('renovacion','upgrade') and v_regla in ('heredada_renovacion','heredada_upgrade') then v_base else 0 end))
      or v_c.tasa_anual <> round(v_c.tasa_anual,2)) then
   raise exception 'La tasa debe ser positiva, tener hasta dos decimales y respetar el límite vigente de esta operación' using errcode = 'P0410';
 end if;

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
$function$;

do $columna$
begin
  if not exists (select 1 from crm.inversiones_eliminadas e where e.reemplazada_por is not null) then
    alter table crm.inversiones_eliminadas drop constraint inversiones_eliminadas_reemplazo_check;
    alter table crm.inversiones_eliminadas drop column reemplazada_por;
  else
    raise notice 'REVERSA reemplazar_inversion: hay copias de reemplazos; la columna reemplazada_por se conserva';
  end if;
end
$columna$;

do $postflight$
begin
  if md5(pg_catalog.pg_get_functiondef('private.trg_contratos_observar_rentabilidad()'::regprocedure))
       is distinct from '9a0c04118488b8ec0058a40d71cebcec' then
    raise exception 'REVERSA reemplazar_inversion: el candado de tasa no volvió a su huella de producción';
  end if;
  if not exists (select 1 from pg_catalog.pg_proc p where p.oid = 'private.trg_contratos_observar_rentabilidad()'::regprocedure
                 and p.proowner = 'postgres'::regrole and p.prosecdef and p.provolatile = 'v'
                 and p.proconfig = array['search_path=""', 'lock_timeout=2s']
                 and p.proacl = '{postgres=X/postgres}'::aclitem[]) then
    raise exception 'REVERSA reemplazar_inversion: dueño, seguridad, configuración o permisos del candado de tasa';
  end if;
  if to_regprocedure('crm.reemplazar_inversion_fn(uuid,text,jsonb,jsonb,jsonb)') is not null
     or to_regprocedure('crm.reemplazar_inversion_por_existente_fn(uuid,uuid,text)') is not null
     or to_regprocedure('private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)') is not null
     or to_regprocedure('private.registrar_inversion_reemplazada_avance(jsonb,uuid,uuid,text,text,uuid,text,jsonb)') is not null then
    raise exception 'REVERSA reemplazar_inversion: quedó una función del reemplazo';
  end if;
end
$postflight$;

notify pgrst, 'reload schema';
commit;
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));

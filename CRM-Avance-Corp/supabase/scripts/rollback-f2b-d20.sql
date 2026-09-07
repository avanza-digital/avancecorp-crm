-- ============================================================================
-- REVERSA de F2.b [D-20] (20260906210000): restaura crm.importar_lead_fn byte a byte (texto vivo de producción), suelta
-- private.registrar_solicitud_cliente_fn(uuid,text,jsonb) y desregistra la versión. Repetible dos veces.
-- ⚠️ Revertirla NO borra las notas ni las tareas que ya se crearon: son trabajo real de la operación.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d20_solicitud_de_cliente'));
do $pre$
begin
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  if not exists (select 1 from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas') then
    raise exception 'REVERSA D-20: no existe la bandera resolver_en_puertas (¿F1 aplicada?)';
  end if;
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'REVERSA D-20: la bandera resolver_en_puertas está ENCENDIDA; apágala antes de revertir';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.importar_lead_fn(jsonb)')), '') not in ('321770b5349d70af1767d7d27bcedc93', 'cf1d8388fcf2aae71fd8e5e9c99c52d5') then
    raise exception 'REVERSA D-20: crm.importar_lead_fn no es ni el texto de D-20 ni el vivo de producción; no se pisa a ciegas';
  end if;
end
$pre$;

CREATE OR REPLACE FUNCTION crm.importar_lead_fn(p_fila jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_id         uuid := pg_catalog.gen_random_uuid();
  v_nombre     text := nullif(pg_catalog.btrim(p_fila->>'nombre_completo'), '');
  v_telefono   text := nullif(pg_catalog.btrim(p_fila->>'telefono'), '');
  v_alt        text := nullif(pg_catalog.btrim(p_fila->>'telefono_alternativo'), '');
  v_alt_crudo  text := nullif(pg_catalog.btrim(p_fila->>'telefono_alternativo_crudo'), '');
  v_correo     text := nullif(pg_catalog.btrim(p_fila->>'correo'), '');
  v_dni        text := nullif(pg_catalog.btrim(p_fila->>'dni'), '');
  v_genero     text := nullif(pg_catalog.btrim(p_fila->>'genero'), '');
  v_fecha      date;
  v_distrito   text := nullif(pg_catalog.btrim(p_fila->>'distrito'), '');
  v_origen     text := nullif(pg_catalog.btrim(p_fila->>'origen'), '');
  v_monto      numeric;
  v_moneda     text := nullif(pg_catalog.btrim(p_fila->>'moneda'), '');
  v_categoria  text := nullif(pg_catalog.btrim(p_fila->>'categoria_interes'), '');
  v_nota       text := nullif(pg_catalog.btrim(p_fila->>'nota'), '');
  v_cons_en    timestamptz;
  v_cons_fuente text := nullif(pg_catalog.btrim(p_fila->>'consentimiento_fuente'), '');
  v_vendedor   uuid;
  v_detalle    text;
  v_constraint text;
  v_veredicto  jsonb;
  v_resultado  text;
  v_lead       uuid;
  v_reingreso  jsonb;
  v_datos      jsonb;
  v_prev       uuid;
begin
  -- F2.b [D-4]: solo el importador (service_role, sin sesión de usuario), la misma regla que registrar_reingreso_lead_fn.
  if (select auth.uid()) is not null then
    raise exception 'Solo el importador (service_role) usa esta puerta' using errcode = '42501';
  end if;
  -- Defensa en profundidad (auditor N5): esta puerta nunca corre como operación privilegiada, venga como venga la sesión.
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  if p_fila is null or pg_catalog.jsonb_typeof(p_fila) <> 'object' then
    raise exception 'Fila invalida' using errcode = '22023';
  end if;
  -- Los casts van DESPUÉS de la autorización (Codex v3 #6): un payload malformado no cambia el 42501 por un 22xxx.
  v_fecha    := nullif(pg_catalog.btrim(p_fila->>'fecha_nacimiento'), '')::date;
  v_monto    := nullif(pg_catalog.btrim(p_fila->>'monto_estimado'), '')::numeric;
  v_cons_en  := nullif(pg_catalog.btrim(p_fila->>'consentimiento_en'), '')::timestamptz;
  v_vendedor := nullif(pg_catalog.btrim(p_fila->>'vendedor_id'), '')::uuid;
  -- La puerta NO valida el formato: lo hace la fila al nacer (trigger 00: teléfono y DNI → 22023 con el mismo texto de
  -- hoy; NOT NULL y CHECKs de la tabla), con la MISMA prioridad que el INSERT directo —el veto de la persona (000) va
  -- antes que el formato— (Codex v4 #9). El teléfono viaja crudo, como lo manda el edge; lo normaliza el trigger de la tabla.

  -- Orden TOTAL de candados (b1/D-13, el de crm.crear_lead_si_disponible): documento → persona → contactos → fila.
  -- El INSERT directo de hoy YA los toma en ese orden (triggers BEFORE 000 → 00, antes de tocar tupla e índice). Aquí
  -- se toman explícitos SOLO los de identidad (documento → persona; apagada la bandera no toman nada), antes del
  -- sub-bloque para que sobrevivan a su rollback y el reingreso corra con la persona retenida. Los de CONTACTO los toma
  -- el trigger 00 del INSERT, DESPUÉS del veto de la persona (000), exactamente como el INSERT directo: una persona
  -- vetada recibe su «no insistir» sin esperar por un teléfono retenido (Codex v3 #3). D-4 no cambia el orden: lo que
  -- aporta es un veredicto único sin parsear SQLSTATE y el reingreso en la misma transacción.
  perform private.identidad_bloquear_documento('DNI', v_dni);
  perform private.identidad_bloquear_persona('DNI', v_dni);

  -- El CONTRATO del importador es el de la fila al nacer sin sesión humana (trigger de disponibilidad: «un escritor
  -- interno se serializa pero conserva su contrato especializado»): NO se consulta la disponibilidad comercial
  -- (enfriamiento, ficha de cliente, «no insistir» de un lead viejo) —el cliente que vuelve por la hoja es el mejor
  -- lead posible—; sí mandan el índice único de teléfono VIVO (duplicado) y, con la identidad encendida, los triggers
  -- de nacimiento: 000 (la persona vetada → P0429) y zz (la persona ya tiene lead o está en conversión → P0481 por
  -- identidad). Por eso la puerta hace el MISMO INSERT (payload exacto del edge: sin sesión, cola global, alta_manual
  -- por defecto) y convierte esos tres resultados en un veredicto en vez de una excepción.
  begin
    insert into crm.leads (
      id, nombre_completo, telefono, telefono_alternativo, telefono_alternativo_crudo, correo, dni, genero,
      fecha_nacimiento, distrito, origen, etapa, monto_estimado, moneda, categoria_interes, nota, no_contactar,
      consentimiento_en, consentimiento_fuente, vendedor_id, asignado_supervisor_id, activo, creado_por
    ) values (
      v_id, v_nombre, v_telefono, v_alt, v_alt_crudo, v_correo, v_dni, v_genero,
      v_fecha, v_distrito, v_origen, 'nuevo', v_monto, v_moneda, v_categoria, v_nota, false,
      v_cons_en, v_cons_fuente, v_vendedor, null, true, null
    );
    return pg_catalog.jsonb_build_object('resultado', 'importado', 'lead_id', v_id, 'veredicto', null, 'reingreso', null);
  exception
    when unique_violation then
      -- uq_leads_telefono_vivo (o uq_leads_dni_vivo): ya hay un lead VIVO con ese contacto → DUPLICADO (hoy: 23505).
      -- Se devuelve el NOMBRE del índice, no el DETAIL (que lleva el teléfono o el DNI en claro; auditor N1).
      get stacked diagnostics v_constraint = constraint_name;
      v_veredicto := pg_catalog.jsonb_build_object('estado', 'duplicado', 'indice', coalesce(v_constraint, 'desconocido'));
      v_resultado := 'duplicado';
    when sqlstate 'P0481' then
      -- «Contacto no disponible» con el veredicto en DETAIL (hoy lo parsea el edge): ya_es_cliente por identidad
      -- (con lead_id) o en conversión → ya_cliente; cualquier otro → rechazado.
      get stacked diagnostics v_detalle = pg_exception_detail;
      begin
        v_veredicto := v_detalle::jsonb;
      exception when others then
        v_veredicto := pg_catalog.jsonb_build_object('estado', 'no_disponible', 'detalle', pg_catalog.left(coalesce(v_detalle, ''), 200));
      end;
      v_resultado := case when v_veredicto->>'estado' = 'ya_es_cliente' and v_veredicto->>'via' = 'identidad' then 'ya_cliente' else 'rechazado' end;
    when sqlstate 'P0429' then
      -- La persona tiene «No insistir» (trigger 000, identidad encendida) → RECHAZADO (hoy: P0429).
      get stacked diagnostics v_detalle = pg_exception_detail;
      begin
        v_veredicto := coalesce(nullif(v_detalle, '')::jsonb, pg_catalog.jsonb_build_object('estado', 'no_contactar'));
      exception when others then
        v_veredicto := pg_catalog.jsonb_build_object('estado', 'no_contactar');
      end;
      v_resultado := 'rechazado';
  end;

  v_lead := nullif(v_veredicto->>'lead_id', '')::uuid;
  if v_resultado = 'ya_cliente' and v_lead is not null then
    -- El reingreso en la MISMA transacción (hoy el edge lo pedía aparte tras leer el error). Si fallara de forma
    -- DEFINITIVA, la fila sigue siendo «ya cliente» y el edge lo dice en la hoja, como hoy.
    v_datos := pg_catalog.jsonb_build_object(
      'fila', p_fila->'fila', 'nombre', v_nombre, 'telefono', v_telefono, 'telefono_alternativo', v_alt,
      'correo', v_correo, 'capital', v_monto, 'moneda', v_moneda, 'canal', v_origen, 'distrito', v_distrito,
      'interes', v_categoria, 'nota', v_nota);
    -- IDEMPOTENCIA (Codex v4 #7, v5 #3): si la hoja reenvía la MISMA fila (perdió la confirmación HTTP o el lote falló
    -- después), el reingreso ya anotado vale: no se escribe una segunda nota. Misma persona, mismo origen y los mismos
    -- DATOS —sin el número de fila, que cambia si alguien inserta una fila encima— en los últimos 7 días (una caída larga
    -- del CRM tampoco la burla). Es lo que registrar_reingreso_lead_fn guarda en metadata.datos.
    select a.id into v_prev
      from crm.actividades a
     where a.lead_id = v_lead
       and a.metadata->>'evento' = 'reingreso'
       and a.metadata->>'origen' = 'hoja'
       and (a.metadata->'datos') - 'fila' = v_datos - 'fila'
       and a.creado_en > pg_catalog.now() - interval '7 days'
     order by a.creado_en desc
     limit 1;
    if v_prev is not null then
      v_reingreso := pg_catalog.jsonb_build_object('ok', true, 'actividad_id', v_prev, 'repetido', true);
    else
      begin
        v_reingreso := crm.registrar_reingreso_lead_fn(v_lead, 'hoja', v_datos);
      exception when others then
        -- Solo los errores DE NEGOCIO quedan anotados como definitivos en la respuesta (datos 22xxx, integridad 23xxx y
        -- los P0xxx que levantan nuestras funciones: lead inexistente, origen inválido, identidad apagada). Cualquier
        -- otro —transacción, recursos, candado, cancelación, E/S, límites (54), internos, configuración— sube entero: el
        -- edge lo trata como temporal y la hoja reintenta la fila (auditor M4; Codex v4 #8 y v5 #4).
        if pg_catalog.left(sqlstate, 2) not in ('22', '23', 'P0') then
          raise;
        end if;
        v_reingreso := pg_catalog.jsonb_build_object('ok', false, 'error', sqlstate || ': ' || pg_catalog.left(sqlerrm, 120));
      end;
    end if;
  end if;

  return pg_catalog.jsonb_build_object('resultado', v_resultado, 'lead_id', v_lead, 'veredicto', v_veredicto, 'reingreso', v_reingreso);
end;
$function$;

drop function if exists private.registrar_solicitud_cliente_fn(uuid,text,jsonb);

do $post$
begin
  if not exists (select 1 from pg_proc p where p.oid = 'crm.importar_lead_fn(jsonb)'::regprocedure
                  and md5(p.prosrc) = 'cf1d8388fcf2aae71fd8e5e9c99c52d5' and p.prosecdef and p.proowner = 'postgres'::regrole
                  and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s']
                  and coalesce((select string_agg(a.grantee::regrole::text, ',' order by a.grantee::regrole::text) from aclexplode(p.proacl) a), 'null') = 'postgres,service_role') then
    raise exception 'REVERSA D-20: crm.importar_lead_fn no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
  if to_regprocedure('private.registrar_solicitud_cliente_fn(uuid,text,jsonb)') is not null then
    raise exception 'REVERSA D-20: private.registrar_solicitud_cliente_fn(uuid,text,jsonb) sigue viva';
  end if;
  delete from supabase_migrations.schema_migrations where version = '20260906210000';
  raise notice 'REVERSA F2.b D-20 OK (versión 20260906210000 desregistrada si estaba)';
end
$post$;
commit;

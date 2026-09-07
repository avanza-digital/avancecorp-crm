-- ============================================================================
-- REGISTRO de F2.b [D-20] (20260906210000). Idempotente. md5 del archivo de migración: d1aae01d2a942db5258db5e84bfad11e
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d20_solicitud_de_cliente'));
do $chk$
begin
  if to_regprocedure('private.registrar_solicitud_cliente_fn(uuid,text,jsonb)') is null then
    raise exception 'REGISTRO D-20: no está el ayudante: ¿aplicaste la migración?';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = 'crm.importar_lead_fn(jsonb)'::regprocedure), '') <> '321770b5349d70af1767d7d27bcedc93' then
    raise exception 'REGISTRO D-20: crm.importar_lead_fn no es la de D-20';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20260906210000'
               and (statements is null or array_length(statements, 1) is distinct from 1 or statements[1] is null
                    or md5(statements[1]) <> 'd1aae01d2a942db5258db5e84bfad11e')) then
    raise exception 'REGISTRO D-20: la versión 20260906210000 ya está registrada con otro contenido';
  end if;
end
$chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260906210000', 'crm_f2b_d20_cliente_que_vuelve_deja_tarea_a_su_analista', array[$m$-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b [D-20] — EL CLIENTE QUE VUELVE DEJA TAREA A SU ANALISTA
--
-- Por qué. Con la identidad unificada ENCENDIDA, una persona que ya es cliente y llena el formulario de la web deja de
-- generar un lead nuevo: el CRM la reconoce y responde «ya es cliente». Eso evita duplicarle la ficha. Pero hasta hoy
-- el importador solo anotaba la visita si esa persona CONSERVABA un lead vivo, y en producción (06/09) de 424 clientes
-- activos solo 17 lo conservan: los otros 407 cerraron su lead al convertirse. Para esos 407 no quedaba nada en el CRM
-- —ni nota, ni tarea, ni aviso— y la solicitud moría en la hoja. Con la bandera apagada, esa misma persona genera hoy
-- un lead que alguien trabaja: encender sin esto habría sido un retroceso comercial para el 96 % de la cartera.
--
-- La regla (Miguel, 06/09): la solicitud SIEMPRE acaba siendo trabajo de alguien, y nunca por dos vías a la vez.
--   · con lead vivo  → ese lead es el trabajo; se le anota el reingreso, exactamente como hasta ahora;
--   · sin lead vivo  → nota en la ficha del cliente + TAREA de llamada para el analista de su cartera.
--
-- Qué toca: crea private.registrar_solicitud_cliente_fn(uuid,text,jsonb) y transforma `crm.importar_lead_fn`
-- (texto vivo de producción, md5 del cuerpo cf1d8388…) añadiendo la rama del cliente sin lead. La respuesta gana la
-- clave `solicitud`; el edge y la hoja no cambian (la hoja ya pinta «YA ES CLIENTE» y no reenvía).
--
-- APAGADA no hace nada: el ayudante exige la bandera encendida y esa rama solo se alcanza con el veredicto
-- `ya_es_cliente`, que solo existe con la identidad encendida. Aterriza APAGADA. Reversa: scripts/rollback-f2b-d20.sql.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d20_solicitud_de_cliente'));

do $guard$
begin
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  if not exists (select 1 from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas') then
    raise exception 'F2.b D-20: no existe la bandera resolver_en_puertas (¿F1 aplicada?)';
  end if;
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'F2.b D-20: la bandera resolver_en_puertas está ENCENDIDA; este lote aterriza apagado';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.importar_lead_fn(jsonb)')), '') not in ('cf1d8388fcf2aae71fd8e5e9c99c52d5', '321770b5349d70af1767d7d27bcedc93') then
    raise exception 'F2.b D-20: crm.importar_lead_fn no es ni el texto vivo de producción (cf1d8388…) ni el de D-20';
  end if;
  if to_regprocedure('private.resolver_en_puertas_bajo_candado()') is null then
    raise exception 'F2.b D-20: falta D-19 (20260906200000): el ayudante lee la bandera bajo su candado';
  end if;
  if to_regprocedure('crm.registrar_reingreso_lead_fn(uuid,text,jsonb)') is null then
    raise exception 'F2.b D-20: falta D-4 (20260906130000)';
  end if;
  if to_regclass('crm.actividades_cliente') is null or to_regclass('crm.tareas') is null then
    raise exception 'F2.b D-20: faltan crm.actividades_cliente o crm.tareas';
  end if;
  if not exists (select 1 from pg_trigger t join pg_proc pr on pr.oid = t.tgfoid
                  where t.tgrelid = 'crm.tareas'::regclass and t.tgname = 'trg_tareas_00_before_insert'
                    and t.tgenabled = 'O' and pr.proname = 'trg_tareas_before_insert'
                    and md5(pr.prosrc) = '293f17f12beccd952e65295a02c595b5') then
    raise exception 'F2.b D-20: el trigger que resuelve el analista de la cartera no es el esperado (toda la atribución de la tarea depende de él)';
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'crm.actividades_cliente'::regclass
                   and conname = 'actividades_cliente_responsable_check') then
    raise exception 'F2.b D-20: falta el CHECK que exige responsable en la nota de la ficha';
  end if;
end
$guard$;

-- ── El ayudante que deja la huella donde el analista mira ────────────────────────────────────────
create or replace function private.registrar_solicitud_cliente_fn(p_perfil uuid, p_origen text, p_datos jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path to ''
set lock_timeout to '5s'
as $function$
declare
  v_cliente   public.perfiles%rowtype;
  v_huella    text;
  v_detalle   text;
  v_prev_act  uuid;
  v_act       uuid;
  v_tarea     uuid;
  v_sin_asesor boolean := false;
  v_motivo    text;
  v_dest      uuid;      -- a nombre de quién queda la nota (la tabla exige responsable)
begin
  -- F2.b [D-20]. Solo el importador, la misma regla que registrar_reingreso_lead_fn: nunca una sesión humana.
  if (select auth.uid()) is not null then
    raise exception 'Solo el importador (service_role) registra solicitudes de cliente' using errcode = '42501';
  end if;
  if not private.resolver_en_puertas_bajo_candado() then
    raise exception 'Identidad unificada apagada: la solicitud no se registra' using errcode = 'P0409';
  end if;
  if p_origen is null or p_origen not in ('hoja', 'landing', 'web') then
    raise exception 'Origen inválido' using errcode = '22023';
  end if;
  select * into v_cliente from public.perfiles p where p.id = p_perfil and p.rol = 'cliente';
  if not found then
    raise exception 'Cliente inexistente' using errcode = 'P0002';
  end if;
  if not v_cliente.activo then
    raise exception 'Cliente inactivo: la solicitud no se registra' using errcode = 'P0409';
  end if;
  -- Auditor D-20 #A2: los dos triggers de veto se EXIMEN cuando no hay sesión (auth.uid() null), que es justo el caso
  -- del importador. La ley 29571 no puede depender de un razonamiento sobre el orden de los triggers: se comprueba aquí.
  if private.persona_vetada_perfil(p_perfil) then
    return pg_catalog.jsonb_build_object('ok', false, 'vetado', true, 'sin_tarea', true,
      'error', 'La persona tiene la restricción «No insistir»: no se registra seguimiento');
  end if;
  -- Auditor #M6: la idempotencia se sostiene sola. Hoy el importador ya serializa por persona, pero el ayudante no
  -- puede depender de quién lo llame.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('solicitud_cliente:' || p_perfil::text));

  -- Huella de la solicitud SIN el número de fila (que cambia si alguien inserta una fila encima), igual que el
  -- reingreso: si la hoja reenvía la misma fila porque perdió la confirmación, no se duplica ni la nota ni la tarea.
  v_huella := pg_catalog.md5(coalesce((p_datos - 'fila')::text, ''));
  v_detalle := 'Pidió información por la web'
    || coalesce(' · interés: ' || nullif(pg_catalog.btrim(coalesce(p_datos->>'interes', '')), ''), '')
    || coalesce(' · capital: ' || nullif(pg_catalog.btrim(coalesce(p_datos->>'capital', '')), ''), '')
    || coalesce(' ' || nullif(pg_catalog.btrim(coalesce(p_datos->>'moneda', '')), ''), '')
    || coalesce(' · distrito: ' || nullif(pg_catalog.btrim(coalesce(p_datos->>'distrito', '')), ''), '')
    || coalesce(' · canal: ' || nullif(pg_catalog.btrim(coalesce(p_datos->>'canal', '')), ''), '')
    || coalesce(' · teléfono: ' || nullif(pg_catalog.btrim(coalesce(p_datos->>'telefono', '')), ''), '')
    || coalesce(' · nota: ' || nullif(pg_catalog.btrim(coalesce(p_datos->>'nota', '')), ''), '');
  -- `detalle` y `nota` topan en 2000 caracteres, pero la nota del formulario no tiene límite: se recorta el cuerpo y
  -- la huella se añade DESPUÉS, porque recortar por el final la destruiría y con ella la idempotencia (auditor #M1).
  v_detalle := pg_catalog.left(v_detalle, 1900) || ' · Ref: ' || v_huella;

  select a.id into v_prev_act
    from crm.actividades_cliente a
   where a.cliente_id = p_perfil
     and a.tipo = 'nota'
     and pg_catalog.strpos(coalesce(a.detalle, ''), 'Ref: ' || v_huella) > 0
     and a.creado_por is null   -- auditor #M2: solo cuenta la nota que escribió el importador, no una copiada a mano
     and a.creado_en > pg_catalog.now() - interval '7 days'
   order by a.creado_en desc
   limit 1;
  if v_prev_act is not null then
    return pg_catalog.jsonb_build_object('ok', true, 'actividad_id', v_prev_act, 'repetido', true);
  end if;

  -- `actividades_cliente` exige responsable en toda nota (CHECK) y que ese responsable esté en el equipo (FK). El
  -- analista de la cartera es el destino natural; si el perfil no lo tiene, se usa el responsable VIVO de su identidad
  -- (423 de los 424 clientes activos lo tienen). Sin ninguno de los dos no hay a quién atribuirla: se dice y ya.
  v_dest := v_cliente.asesor_perfil_id;
  if v_dest is null or not exists (select 1 from crm.equipo e where e.perfil_id = v_dest and e.activo and e.rol_crm in ('vendedor','supervisor')) then
    select r.responsable_id into v_dest
      from crm.inversionista_responsables r
      join crm.inversionistas i on i.id = r.inversionista_id
     where i.perfil_id = p_perfil and r.hasta is null
       and exists (select 1 from crm.equipo e where e.perfil_id = r.responsable_id and e.activo and e.rol_crm in ('vendedor','supervisor'))
     order by r.desde desc
     limit 1;
  end if;
  if v_dest is null then
    return pg_catalog.jsonb_build_object('ok', false, 'sin_ficha', true, 'sin_tarea', true,
      'error', 'el cliente no tiene analista ni responsable activo: nadie a quien atribuir la solicitud');
  end if;

  insert into crm.actividades_cliente (cliente_id, vendedor_id, tipo, detalle, creado_por)
  values (p_perfil, v_dest, 'nota', v_detalle, null)
  returning id into v_act;

  -- La TAREA es lo que hace que alguien la trabaje. El trigger de la tabla resuelve el analista desde la cartera del
  -- cliente y rechaza si no lo tiene o si no está activo en el CRM; eso NO puede tumbar la importación de la fila, así
  -- que se anota como «sin analista» y la nota queda igual en la ficha para que Gerencia lo vea.
  begin
    insert into crm.tareas (perfil_id, tipo, titulo, nota, vence_en, estado, creado_por)
    values (p_perfil, 'llamada', 'Pidió información por la web', v_detalle,
            pg_catalog.now() + interval '1 day', 'pendiente', null)
    returning id into v_tarea;
  exception when others then
    if pg_catalog.left(sqlstate, 2) not in ('22', '23', 'P0') then
      raise;
    end if;
    v_sin_asesor := true;
    v_motivo := sqlstate || ': ' || pg_catalog.left(sqlerrm, 120);
  end;

  return pg_catalog.jsonb_build_object('ok', true, 'actividad_id', v_act, 'tarea_id', v_tarea,
                                       'repetido', false, 'sin_tarea', v_sin_asesor, 'motivo', v_motivo);
end;
$function$;
alter function private.registrar_solicitud_cliente_fn(uuid,text,jsonb) owner to postgres;
revoke all on function private.registrar_solicitud_cliente_fn(uuid,text,jsonb) from public;

-- ── El importador, con la rama del cliente que vuelve sin lead ───────────────────────────────────
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
  v_perfil     uuid;      -- F2.b [D-20]
  v_lead_vivo  uuid;      -- F2.b [D-20]
  v_solicitud  jsonb;     -- F2.b [D-20]
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
  -- F2.b [D-20] (auditor A1): `private.leads_de_personas` devuelve enlace ∪ puente ∪ sueltos, así que `v_lead`
  -- también trae leads CONVERTIDOS y descartados. Anotar el reingreso en uno cerrado es escribir donde nadie mira.
  -- La bifurcación va por el lead VIVO: solo ése es un trabajo que alguien tiene en su bandeja.
  select l.id into v_lead_vivo
    from crm.leads l
   where l.id = v_lead and l.activo and l.etapa not in ('convertido', 'descartado');
  if v_resultado = 'ya_cliente' and v_lead_vivo is not null then
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
  elsif v_resultado = 'ya_cliente' then
    -- F2.b [D-20]: es cliente y NO conserva lead vivo (el caso de 407 de los 424 clientes activos en producción al
    -- 06/09). Sin esta rama la solicitud se perdía: la hoja la daba por cerrada y en el CRM no quedaba nada. Se deja
    -- la huella donde el analista mira: nota en la ficha del cliente y tarea de llamada para el responsable de su
    -- cartera. Nunca las dos vías a la vez: si hubiera lead vivo, la rama de arriba ya anotó el reingreso.
    v_datos := pg_catalog.jsonb_build_object(
      'fila', p_fila->'fila', 'nombre', v_nombre, 'telefono', v_telefono, 'telefono_alternativo', v_alt,
      'correo', v_correo, 'capital', v_monto, 'moneda', v_moneda, 'canal', v_origen, 'distrito', v_distrito,
      'interes', v_categoria, 'nota', v_nota);
    -- La persona ya está reconocida (el veredicto lo dice), así que su ficha de cliente sale de la identidad. El
    -- respaldo por documento exacto cubre a un cliente cuya identidad todavía no lleva el perfil enlazado.
    select i.perfil_id into v_perfil
      from crm.inversionistas i
     where i.id = private.inversionista_por_documento('DNI', v_dni) and i.perfil_id is not null;
    if v_perfil is null and nullif(pg_catalog.btrim(coalesce(v_dni, '')), '') is not null then
      select p.id into v_perfil
        from public.perfiles p
       where p.rol = 'cliente' and p.activo
         and nullif(pg_catalog.btrim(coalesce(p.dni, '')), '') is not null
         and (coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI') || ':' ||
              pg_catalog.upper(pg_catalog.regexp_replace(p.dni, '[^A-Za-z0-9]', '', 'g')))
             = ('DNI:' || pg_catalog.upper(pg_catalog.regexp_replace(coalesce(v_dni, ''), '[^A-Za-z0-9]', '', 'g')))
       limit 1;
    end if;
    if v_perfil is not null then
      begin
        v_solicitud := private.registrar_solicitud_cliente_fn(v_perfil, 'hoja', v_datos);
      exception when others then
        -- Mismo criterio que el reingreso: solo los errores DE NEGOCIO se anotan como definitivos; cualquier otro
        -- sube entero para que la hoja reintente la fila.
        if pg_catalog.left(sqlstate, 2) not in ('22', '23', 'P0') then
          raise;
        end if;
        v_solicitud := pg_catalog.jsonb_build_object('ok', false, 'error', sqlstate || ': ' || pg_catalog.left(sqlerrm, 120));
      end;
    else
      v_solicitud := pg_catalog.jsonb_build_object('ok', false, 'error', 'no se pudo ubicar la ficha del cliente');
    end if;
  end if;

  return pg_catalog.jsonb_build_object('resultado', v_resultado, 'lead_id', v_lead, 'veredicto', v_veredicto, 'reingreso', v_reingreso, 'solicitud', v_solicitud);
end;
$function$;

do $post$
begin
  if not exists (select 1 from pg_proc p where p.oid = 'crm.importar_lead_fn(jsonb)'::regprocedure
                  and md5(p.prosrc) = '321770b5349d70af1767d7d27bcedc93' and p.prosecdef and p.proowner = 'postgres'::regrole
                  and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s']
                  and coalesce((select string_agg(a.grantee::regrole::text, ',' order by a.grantee::regrole::text) from aclexplode(p.proacl) a), 'null') = 'postgres,service_role') then
    raise exception 'POSTFLIGHT D-20: crm.importar_lead_fn no quedó como se esperaba (cuerpo, definer, dueño, config o permisos)';
  end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'private' and p.proname = 'registrar_solicitud_cliente_fn'
                    and p.prosecdef and p.provolatile = 'v' and p.proowner = 'postgres'::regrole
                    and p.proconfig @> array['search_path=""']
                    and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)
                    and not has_function_privilege('authenticated', 'private.registrar_solicitud_cliente_fn(uuid,text,jsonb)', 'EXECUTE')
                    and not has_function_privilege('anon', 'private.registrar_solicitud_cliente_fn(uuid,text,jsonb)', 'EXECUTE')
                    and not has_function_privilege('service_role', 'private.registrar_solicitud_cliente_fn(uuid,text,jsonb)', 'EXECUTE')) then
    raise exception 'POSTFLIGHT D-20: private.registrar_solicitud_cliente_fn(uuid,text,jsonb) no quedó como se esperaba';
  end if;
  raise notice 'F2.b D-20 OK: el cliente que vuelve sin lead deja nota en su ficha y tarea a su analista (apagada: sin efecto).';
end
$post$;
commit;
$m$])
on conflict (version) do nothing;
commit;

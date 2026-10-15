-- Formulario 3, fase 1. Cambio aditivo; ninguna reclasificación histórica.
-- Solo crm/private. Las mismas puertas y transacciones conservan reparto e identidad.
begin;
set local lock_timeout = '5s';

-- Atributos previos para probar también su conservación después de reemplazar.
create temporary table formulario3_funciones_previas on commit drop as
select p.oid, p.proconfig, p.prosecdef, p.proowner, p.proacl
from pg_catalog.pg_proc p where p.oid in (
  'crm.importar_lead_fn(jsonb)'::regprocedure,
  'crm.registrar_reingreso_lead_fn(uuid,text,jsonb)'::regprocedure,
  'private.registrar_solicitud_cliente_fn(uuid,text,jsonb)'::regprocedure
);

-- Baseline leído de la base viva: cuerpo, definición, dueño y ACL completos.
do $preflight$
declare r record;
begin
  for r in select * from (values
    ('crm.importar_lead_fn(jsonb)', '261411a75326cbe78220d3ef1a61a7cd','0518b2643f258ca458d3a6acc492a7bf','{postgres=X/postgres,service_role=X/postgres}'),
    ('crm.registrar_reingreso_lead_fn(uuid,text,jsonb)', '2875987459d47958333637736c057ffb','c3c4ab696ba6f3e30895cae1a9a27b77','{postgres=X/postgres,service_role=X/postgres}'),
    ('private.registrar_solicitud_cliente_fn(uuid,text,jsonb)', '38cc98b993d92b10816c95a479994d20','23c2b6216684ac77801e39af5efe4b7c','{postgres=X/postgres}')
  ) as f(firma, huella, definicion, permisos) loop
    if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
         where p.oid = pg_catalog.to_regprocedure(r.firma)) is distinct from r.huella then
      raise exception 'Deriva previa en %; revisar antes de aplicar', r.firma;
    end if;
    if not exists (
      select 1 from pg_catalog.pg_proc p
       where p.oid=pg_catalog.to_regprocedure(r.firma)
         and pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))=r.definicion
         and pg_catalog.pg_get_userbyid(p.proowner)='postgres'
         and p.proacl::text=r.permisos
    ) then raise exception 'Deriva de atributos o permisos en %',r.firma; end if;
  end loop;
  if not (select relrowsecurity from pg_catalog.pg_class where oid='crm.leads'::regclass) then
    raise exception 'crm.leads debe conservar RLS';
  end if;
end;
$preflight$;

-- En la base viva authenticated tiene UPDATE de tabla. Convertirlo a los mismos
-- permisos efectivos sobre columnas existentes, ANTES de agregar la nueva.
-- REVOKE de una sola columna no vencería al grant de tabla.
do $permisos$
declare v_columnas text;
begin
  select pg_catalog.string_agg(pg_catalog.quote_ident(a.attname), ', ' order by a.attnum)
    into v_columnas
    from pg_catalog.pg_attribute a
   where a.attrelid='crm.leads'::regclass and a.attnum>0 and not a.attisdropped
     and pg_catalog.has_column_privilege('authenticated', a.attrelid, a.attnum, 'UPDATE');
  revoke update on crm.leads from authenticated;
  if v_columnas is not null then
    execute 'grant update (' || v_columnas || ') on crm.leads to authenticated';
  end if;
end;
$permisos$;

alter table crm.leads add column campania_origen text;
comment on column crm.leads.campania_origen is
  'Campaña de la primera importación; NULL en históricos. El canal origen conserva las reglas comerciales.';
grant select (campania_origen) on crm.leads to authenticated;

-- Validador compartido por el importador, sin otra superficie de escritura.
create function private.normalizar_campania_origen(p_valor jsonb, p_origen text)
returns text language plpgsql immutable set search_path = '' as $normalizar$
declare v text;
begin
  if p_valor is null or p_valor='null'::jsonb then return null; end if;
  if pg_catalog.jsonb_typeof(p_valor)<>'string' then
    raise exception 'Campaña debe ser texto' using errcode='22023';
  end if;
  v := pg_catalog.btrim(p_valor #>> '{}');
  if pg_catalog.char_length(v) not between 1 and 80 or v ~ '[[:cntrl:]]' then
    raise exception 'Campaña debe tener de 1 a 80 caracteres sin controles' using errcode='22023';
  end if;
  if pg_catalog.lower(v)='formulario 3' then
    if p_origen is distinct from 'formulario' then
      raise exception 'Formulario 3 requiere el canal FORMULARIO' using errcode='22023';
    end if;
    v := 'Formulario 3';
  end if;
  return v;
end;
$normalizar$;
revoke all on function private.normalizar_campania_origen(jsonb,text) from public, anon, authenticated, service_role;

alter table crm.leads add constraint leads_campania_origen_valida check (
  campania_origen is null or (
    campania_origen=pg_catalog.btrim(campania_origen)
    and pg_catalog.char_length(campania_origen) between 1 and 80
    and campania_origen !~ '[[:cntrl:]]'
    and (pg_catalog.lower(campania_origen)<>'formulario 3'
         or campania_origen='Formulario 3')
  )
);

-- El grant impide PATCH directo. El trigger también protege las rutas DEFINER
-- que actúan con auth.uid() humano; no basta con mirar current_user=postgres.
create function private.proteger_campania_lead()
returns trigger language plpgsql set search_path = '' as $proteger$
begin
  if (tg_op='INSERT' and new.campania_origen is not null)
     or (tg_op='UPDATE' and new.campania_origen is distinct from old.campania_origen) then
    if (select auth.uid()) is not null or current_user not in ('postgres','service_role','supabase_admin') then
      raise exception 'La campaña de origen solo la escribe el servidor' using errcode='42501';
    end if;
  end if;
  return new;
end;
$proteger$;
revoke all on function private.proteger_campania_lead() from public, anon, authenticated, service_role;
create trigger trg_leads_campania_controlada before insert or update on crm.leads
  for each row execute function private.proteger_campania_lead();

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
  v_campania   text;
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
  v_campania := private.normalizar_campania_origen(p_fila->'campania_origen', v_origen);
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
      fecha_nacimiento, distrito, origen, campania_origen, etapa, monto_estimado, moneda, categoria_interes, nota, no_contactar,
      consentimiento_en, consentimiento_fuente, vendedor_id, asignado_supervisor_id, activo, creado_por
    ) values (
      v_id, v_nombre, v_telefono, v_alt, v_alt_crudo, v_correo, v_dni, v_genero,
      v_fecha, v_distrito, v_origen, v_campania, 'nuevo', v_monto, v_moneda, v_categoria, v_nota, false,
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
  -- Y no basta con mirar el lead que trae el veredicto: si ése está cerrado pero la persona conserva OTRO vivo, crear
  -- una tarea duplicaría el trabajo (Codex). Se busca cualquier lead vivo suyo, prefiriendo el del veredicto.
  select l.id into v_lead_vivo
    from crm.leads l
   where l.activo
     and l.etapa not in ('convertido', 'descartado')
     and (l.id = v_lead
          or (nullif(pg_catalog.btrim(coalesce(v_dni, '')), '') is not null and l.dni = v_dni)
          or (l.inversionista_id is not null
              and l.inversionista_id = private.inversionista_por_documento('DNI', v_dni)))
   order by (l.id = v_lead) desc, l.creado_en desc
   limit 1;
  if v_resultado = 'ya_cliente' and v_lead_vivo is not null then
    -- El reingreso en la MISMA transacción (hoy el edge lo pedía aparte tras leer el error). Si fallara de forma
    -- DEFINITIVA, la fila sigue siendo «ya cliente» y el edge lo dice en la hoja, como hoy.
    v_datos := pg_catalog.jsonb_build_object(
      'fila', p_fila->'fila', 'nombre', v_nombre, 'telefono', v_telefono, 'telefono_alternativo', v_alt,
      'correo', v_correo, 'capital', v_monto, 'moneda', v_moneda, 'canal', v_origen, 'distrito', v_distrito,
      'interes', v_categoria, 'nota', v_nota);
    -- Ausente no añade una clave nula: se conserva la igualdad de solicitudes antiguas.
    if v_campania is not null then
      v_datos := v_datos || pg_catalog.jsonb_build_object('campania_origen', v_campania);
    end if;
    -- IDEMPOTENCIA (Codex v4 #7, v5 #3): si la hoja reenvía la MISMA fila (perdió la confirmación HTTP o el lote falló
    -- después), el reingreso ya anotado vale: no se escribe una segunda nota. Misma persona, mismo origen y los mismos
    -- DATOS —sin el número de fila, que cambia si alguien inserta una fila encima— en los últimos 7 días (una caída larga
    -- del CRM tampoco la burla). Es lo que registrar_reingreso_lead_fn guarda en metadata.datos.
    select a.id into v_prev
      from crm.actividades a
     where a.lead_id = v_lead_vivo
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
        v_reingreso := crm.registrar_reingreso_lead_fn(v_lead_vivo, 'hoja', v_datos);
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
    -- Ausente no añade una clave nula: se conserva la igualdad de solicitudes antiguas.
    if v_campania is not null then
      v_datos := v_datos || pg_catalog.jsonb_build_object('campania_origen', v_campania);
    end if;
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

  return pg_catalog.jsonb_build_object('resultado', v_resultado, 'lead_id', v_lead, 'veredicto', v_veredicto, 'reingreso', v_reingreso)
      || case when v_solicitud is null then '{}'::jsonb else pg_catalog.jsonb_build_object('solicitud', v_solicitud) end;
end;
$function$;

CREATE OR REPLACE FUNCTION crm.registrar_reingreso_lead_fn(p_lead_id uuid, p_origen text, p_datos jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
  v_datos jsonb;
begin
  if (select auth.uid()) is not null then
    raise exception 'Solo el importador (service_role) registra reingresos' using errcode = '42501';
  end if;
  -- Paridad apagada: superficie inerte mientras la identidad no esté activa (Codex E1).
  if not private.resolver_en_puertas_bajo_candado() then
    raise exception 'Identidad unificada apagada: el reingreso no se registra' using errcode = 'P0409';
  end if;
  if p_lead_id is null or not exists (select 1 from crm.leads l where l.id = p_lead_id) then
    raise exception 'Lead inexistente' using errcode = 'P0002';
  end if;
  if p_origen is null or pg_catalog.length(pg_catalog.btrim(p_origen)) not between 1 and 40 then
    raise exception 'Origen inválido' using errcode = '22023';
  end if;
  -- Sin documento en claro en la actividad: solo datos comerciales del formulario.
  v_datos := (
    select coalesce(pg_catalog.jsonb_object_agg(e.key, e.value), '{}'::jsonb)
    from pg_catalog.jsonb_each(coalesce(p_datos, '{}'::jsonb)) e
    where e.key in ('nombre','telefono','telefono_alternativo','correo','capital','moneda','canal','distrito','interes','nota','fila','campania_origen')
  );
  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
  values (
    p_lead_id, 'nota',
    'Reingreso por ' || pg_catalog.btrim(p_origen) || ': la persona volvió a dejar sus datos'
      || coalesce(' · campaña: ' || nullif(v_datos->>'campania_origen', ''), ''),
    pg_catalog.jsonb_build_object('evento', 'reingreso', 'origen', pg_catalog.btrim(p_origen), 'datos', v_datos),
    null)
  returning id into v_id;
  return pg_catalog.jsonb_build_object('ok', true, 'actividad_id', v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION private.registrar_solicitud_cliente_fn(p_perfil uuid, p_origen text, p_datos jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
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
    -- Antes de la nota larga; la huella sigue al final y conserva la campaña.
    || coalesce(' · campaña: ' || nullif(p_datos->>'campania_origen', ''), '')
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
     -- La comparación va contra la COLA, no contra el interior (Codex): el sufijo « · Ref: <huella>» lo añadimos
     -- nosotros SIEMPRE al final, mientras que la nota del visitante queda antes y recortada. Con `strpos`, un texto
     -- del formulario que contuviera «Ref: <huella>» podía hacer pasar por repetida una solicitud jamás registrada.
     and pg_catalog.right(coalesce(a.detalle, ''), pg_catalog.length(' · Ref: ' || v_huella)) = ' · Ref: ' || v_huella
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

-- CREATE OR REPLACE preserva dueño/ACL de las tres puertas, sin ampliarlos.
-- Defensa posterior: nunca permitir que un grant heredado habilite la nueva escritura.
do $postflight$
begin
  if exists (
    select 1 from formulario3_funciones_previas a
    join pg_catalog.pg_proc p on p.oid=a.oid
    where row(a.proconfig,a.prosecdef,a.proowner,a.proacl)
          is distinct from row(p.proconfig,p.prosecdef,p.proowner,p.proacl)
  ) then raise exception 'Se alteraron atributos o permisos de una puerta existente'; end if;
  if pg_catalog.has_column_privilege('authenticated','crm.leads','campania_origen','UPDATE')
     or pg_catalog.has_column_privilege('authenticated','crm.leads','campania_origen','INSERT') then
    raise exception 'La campaña no debe admitir escritura authenticated';
  end if;
  if not pg_catalog.has_column_privilege('authenticated','crm.leads','campania_origen','SELECT') then
    raise exception 'Falta lectura de campaña bajo RLS';
  end if;
end;
$postflight$;
notify pgrst, 'reload schema';
commit;

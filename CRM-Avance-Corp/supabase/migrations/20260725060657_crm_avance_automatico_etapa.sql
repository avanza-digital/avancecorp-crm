-- ============================================================================
-- CRM · La etapa avanza sola cuando el hecho YA ocurrió
--
-- Pedido de Miguel (2026-07-25), textual: "cuando el vendedor registre una
-- acción de que SÍ contactó a la persona, y el lead está en la primera fase del
-- pipeline, el prospecto se mueva solo de etapa" — y de ahí el principio
-- general: una acción debe ayudar a las otras, no obligar a repetirlas.
--
-- Dos automatismos, ambos AFTER INSERT y ambos SOLO DE SUBIDA:
--   1. Registrar una CONVERSACIÓN  → el lead sube de `nuevo` a `contactado`.
--   2. Agendar una REUNIÓN         → el lead sube a `reunion_agendada`.
--
-- ¿POR QUÉ EN LA BASE Y NO EN EL FRONT? El contacto entra por tres puertas
-- distintas: los botones de la cola (components/app/contacto.tsx), el composer
-- de la ficha, y `crm.cerrar_tarea` — que es SECURITY DEFINER y escribe
-- server-side, donde el navegador no puede interceptar nada. Solo el INSERT al
-- log las cubre a las tres. El front lleva un espejo optimista
-- (app/src/lib/avance-automatico.ts) para no pintar "Nuevo" hasta el resync y
-- para ser la única implementación del modo demo; la VERDAD es esta migración.
--
-- NUNCA BAJAN DE ETAPA. Un `cambio_etapa` es un hecho registrado con autor, no
-- un estado reversible: una reunión con plantón no borra que se agendó. El
-- retroceso sigue siendo decisión explícita de una persona desde el kanban.
--
-- No crea columnas ni tablas: no hay GRANTs nuevos que dar sobre crm.leads
-- (que los tiene POR COLUMNA) ni hace falta `gen:types`. Las tres funciones
-- nuevas se ENDURECEN con `revoke all … from public, anon, authenticated,
-- service_role`: son cuerpos de trigger, nadie debe poder invocarlas suelto.
--
-- Auditada por `auditor-rls` ANTES de aplicar: veredicto NO-GO → 1 crítico
-- (C1), 2 altos y 6 medios corregidos aquí. El detalle de C1 y del ciclo de
-- bloqueo, abajo en sus secciones.
-- ============================================================================

begin;

-- CREATE TRIGGER toma SHARE ROW EXCLUSIVE sobre crm.actividades y crm.tareas
-- (dos tablas calientes): sin timeout, esta migración podría encolarse tras una
-- transacción larga y congelar todo registro de actividad y de agenda.
set local lock_timeout = '5s';

-- ── 0. Distinguir en el timeline lo que movió el SISTEMA ──────────────────────
-- `private.trg_leads_cambio_etapa` ya escribe la actividad de cada cambio de
-- etapa, pero no puede saber si la ordenó una persona o un automatismo: en
-- ambos casos ve un UPDATE con el `auth.uid()` del actor. Sin esta marca, el
-- historial atribuiría al vendedor movimientos que él no pidió — y con ella se
-- puede medir después cuánto embudo mueve el sistema solo.
--
-- El flag es una GUC LOCAL a la transacción (tercer argumento `true`): no se
-- filtra entre peticiones de PostgREST, revierte también al abortar una
-- subtransacción, y el cliente no puede encenderlo (PostgREST solo puebla
-- `request.*`; `set_config` no está expuesto). Mismo patrón que `crm.op_tarea`.
--
-- CREATE OR REPLACE a propósito (jamás DROP+CREATE: borraría la ACL). El único
-- cambio es la clave `automatico`; el resto es idéntico a 20260709000001.
create or replace function private.trg_leads_cambio_etapa()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
begin
  if new.etapa is distinct from old.etapa then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (
      new.id, 'cambio_etapa', old.etapa || ' → ' || new.etapa,
      jsonb_build_object(
        'etapa_anterior', old.etapa,
        'etapa_nueva', new.etapa,
        'automatico', coalesce(current_setting('crm.avance_auto', true), 'off') = 'on'
      ),
      coalesce((select auth.uid()), new.creado_por)
    );
    if new.etapa = 'convertido' and new.convertido_en is null then
      new.convertido_en := now();
    end if;
  end if;
  return new;
end;
$function$;

-- ── 1. Conversación → `contactado` ───────────────────────────────────────────
create or replace function private.trg_actividades_avance_etapa()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
begin
  -- GUARDA DE REENTRADA. Hoy no hay recursión posible por dominio (ningún
  -- trigger ni RPC del esquema inserta actividades de conversación: los
  -- automáticos son cambio_etapa/reasignacion/conversion). Pero esa garantía
  -- depende de que nadie añada NUNCA un webhook de WhatsApp o un auto-log de
  -- llamadas — perfectamente plausible en este CRM. Si eso pasara, la actividad
  -- nacería DENTRO de un UPDATE de crm.leads y provocaría un UPDATE anidado
  -- sobre la misma fila en vuelo. Esta línea lo corta estructuralmente.
  if coalesce(current_setting('crm.avance_auto', true), 'off') = 'on' then
    return null;
  end if;

  -- Defensa repetida a propósito: el WHEN del trigger ya filtra estos tipos,
  -- pero si alguien recreara el trigger sin él, esta guarda sigue en pie.
  if new.tipo not in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada') then
    return null;
  end if;
  if new.lead_id is null then
    return null;
  end if;

  perform set_config('crm.avance_auto', 'on', true);
  -- El predicado va DENTRO del UPDATE, no en un `if` previo: así no hay ventana
  -- entre leer la etapa y escribirla. Cero filas afectadas = nada que hacer,
  -- que es exactamente lo que queremos para un lead ya avanzado (idempotencia:
  -- tres contactos seguidos escriben UN solo cambio_etapa).
  --
  -- Aquí NO hace falta gate de ámbito (a diferencia del trigger de tareas, ver
  -- C1 abajo): la policy `actividades_insert` SÍ consulta `crm.leads` bajo RLS,
  -- así que quien pudo insertar la fila disparadora ya estaba autorizado sobre
  -- ese lead. Verificado en la auditoría, incluido el caso del miembro con
  -- `crm.equipo.activo = false` (leads_select se lo deniega).
  update crm.leads
     set etapa = 'contactado'
   where id = new.lead_id
     and activo = true
     and etapa = 'nuevo';
  perform set_config('crm.avance_auto', 'off', true);

  return null;
end;
$function$;

comment on function private.trg_actividades_avance_etapa() is
  'Sube el lead de nuevo a contactado cuando se registra una CONVERSACIÓN (el cliente respondió: llamada_realizada, whatsapp_recibido, reunion_realizada). "No contestó" y "mensaje enviado" NO avanzan: son intentos, y avanzar por ellos convertiría el botón en un posponer-la-alarma (umbral nuevo 24h → contactado 72h) e inflaría la conversión. Espejo del front en app/src/lib/avance-automatico.ts (TIPOS_CONVERSACION).';

revoke all on function private.trg_actividades_avance_etapa() from public, anon, authenticated, service_role;

drop trigger if exists trg_actividades_zz_avance_etapa on crm.actividades;
drop trigger if exists trg_zz_actividades_avance_etapa on crm.actividades;
-- Postgres ordena los triggers por NOMBRE COMPLETO, no por sufijo: un
-- `trg_actividades_zz_…` correría ANTES que `trg_audit_actividades` y dejaría
-- `public.audit_log` en orden causal invertido (primero el cambio de etapa,
-- después la actividad que lo provocó). Con el prefijo `trg_zz_` sí queda
-- último, que es lo que se quiere.
create trigger trg_zz_actividades_avance_etapa
after insert on crm.actividades
for each row
when (new.tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada'))
execute function private.trg_actividades_avance_etapa();

-- ── 2. Reunión agendada → `reunion_agendada` ─────────────────────────────────
create or replace function private.trg_tareas_avance_etapa()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_uid uuid := (select auth.uid());
begin
  if coalesce(current_setting('crm.avance_auto', true), 'off') = 'on' then
    return null;
  end if;

  perform set_config('crm.avance_auto', 'on', true);
  update crm.leads l
     set etapa = 'reunion_agendada'
   where l.id = new.lead_id
     and l.activo = true
     -- Desde `propuesta_enviada` sería un RETROCESO, y encima reiniciaría el
     -- umbral de SLA de 120 h a 72 h.
     and l.etapa in ('nuevo', 'contactado')
     -- Agendar en el pasado no es agendar (seeds, backfills, imports).
     and new.vence_en > now()
     -- ── C1 (CRÍTICO de la auditoría): GATE DE ÁMBITO EXPLÍCITO ──────────────
     -- Esta función es SECURITY DEFINER sobre una tabla sin FORCE RLS: el
     -- UPDATE IGNORA `leads_update`. Y a diferencia de `actividades_insert`, la
     -- policy `tareas_insert` NUNCA consulta `crm.leads`: valida el
     -- `vendedor_id` de la fila NUEVA, que `trg_tareas_before_insert` (también
     -- DEFINER) ya derivó del lead saltándose la RLS. Para un lead de la COLA
     -- GLOBAL ese valor sale null, y la rama `supervisor|gerencia AND
     -- vendedor_id IS NULL` del WITH CHECK lo deja pasar.
     --
     -- Sin este gate, CUALQUIER supervisor que conozca el UUID de un lead de la
     -- cola global (lo tuvo en su bandeja, o gerencia lo devolvió) podría
     -- ascenderlo insertando una reunión — sobre un lead que `leads_select` ni
     -- siquiera le deja VER. Verificado en prod: 61 leads en esa cola.
     --
     -- Primero: un lead sin dueño no tiene "reunión agendada" con nadie.
     and coalesce(l.vendedor_id, l.asignado_supervisor_id) is not null
     -- Segundo: el actor debe alcanzar a ese dueño. `v_uid is null` cubre
     -- service_role, seeds y el cron (sin sesión), que son de sistema.
     and (
       v_uid is null
       or private.rol_crm(v_uid) = 'gerencia'
       or private.puede_ver_cartera(v_uid, coalesce(l.vendedor_id, l.asignado_supervisor_id))
     )
     -- Jamás afirmar "reunión agendada" sobre un lead que NADIE tocó nunca.
     -- Aquí valen los 5 tipos de CONTACTO (no los 3 de conversación): para
     -- agendar basta con haberlo trabajado de verdad.
     and exists (
       select 1 from crm.actividades a
        where a.lead_id = new.lead_id
          and a.tipo in ('llamada_realizada', 'llamada_no_contestada',
                         'whatsapp_enviado', 'whatsapp_recibido', 'reunion_realizada')
     );
  perform set_config('crm.avance_auto', 'off', true);

  return null;
end;
$function$;

comment on function private.trg_tareas_avance_etapa() is
  'Sube el lead a reunion_agendada al agendar una reunión REAL. Excluye reagendada_de is not null (el rebote automático tras un no-show NO es progreso: ascender por un plantón sería la mentira más fácil de fabricar), tareas nacidas cerradas y fechas pasadas. Lleva GATE DE ÁMBITO propio porque tareas_insert no consulta crm.leads y dejaría a un supervisor ascender leads de la cola global que ni puede ver. Nunca baja de etapa. Espejo del front en app/src/lib/avance-automatico.ts.';

revoke all on function private.trg_tareas_avance_etapa() from public, anon, authenticated, service_role;

drop trigger if exists trg_tareas_zz_avance_etapa on crm.tareas;
drop trigger if exists trg_zz_tareas_avance_etapa on crm.tareas;
create trigger trg_zz_tareas_avance_etapa
after insert on crm.tareas
for each row
when (
  new.tipo = 'reunion'
  and new.lead_id is not null
  and new.reagendada_de is null
  and new.estado = 'pendiente'
  and new.activo = true
)
execute function private.trg_tareas_avance_etapa();

-- ── 3. Unificar el ORDEN DE BLOQUEO (A1 de la auditoría) ─────────────────────
-- Hasta hoy `crm.cerrar_tarea` NUNCA tocaba `crm.leads`: bloqueaba la tarea
-- (`for update`) y punto. Con el trigger de arriba, el INSERT de la actividad
-- pasa a bloquear también la fila del lead → orden `tareas → leads`.
--
-- En sentido contrario ya existe `private.trg_leads_sync_tareas` (AFTER UPDATE
-- sobre crm.leads, que actualiza crm.tareas) → orden `leads → tareas`. Los dos
-- órdenes juntos son un ciclo de deadlock: el vendedor cierra una tarea del
-- lead L mientras el supervisor reasigna L → 40P01, PostgREST devuelve 500 y
-- una de las dos operaciones se pierde sin explicación.
--
-- Se unifica tomando SIEMPRE el lead primero. `for no key update` es el modo
-- más débil que sirve (no bloquea lecturas ni FKs). Si la tarea no tiene lead
-- (tarea de cliente), el subselect da null y el statement es un no-op.
--
-- CREATE OR REPLACE con el cuerpo VERBATIM de producción + esas 2 líneas; se
-- reproduce entero porque no se puede parchear una función a trozos.
create or replace function crm.cerrar_tarea(
  p_tarea_id uuid,
  p_estado text,
  p_resultado_tipo text default null,
  p_resultado_detalle text default null,
  p_siguiente jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'crm', 'private', 'public'
as $function$
declare
  v_uid    uuid := (select auth.uid());
  v_rol    text := private.rol_crm((select auth.uid()));
  v_tarea  crm.tareas%rowtype;
  v_act_id uuid;
  v_sig_id uuid;
  v_sig_tipo text;
  v_sig_titulo text;
  v_sig_vence timestamptz;
  v_sig_duracion smallint;
begin
  if v_uid is null or v_rol is null then
    raise exception 'No autorizado';
  end if;

  if p_estado not in ('completada','no_show','cancelada') then
    raise exception 'Estado de cierre invalido';
  end if;

  -- ORDEN DE BLOQUEO: el lead ANTES que la tarea (ver cabecera de esta seccion).
  -- El subselect REPITE el filtro de ambito del `for update` de abajo a
  -- proposito: si solo buscara por id, un usuario con rol podria tomar un lock
  -- sobre el lead de una tarea AJENA que ni puede ver — y, si otra transaccion
  -- lo tuviera tomado, quedarse esperando hasta el statement_timeout antes de
  -- recibir "fuera de tu ambito", que es un oraculo de temporizacion sobre si
  -- ese lead se esta escribiendo ahora mismo. Con el filtro repetido, el no
  -- autorizado no bloquea nada y sale por el `if not found` de siempre.
  perform 1 from crm.leads
   where id = (
     select t.lead_id from crm.tareas t
      where t.id = p_tarea_id
        and t.activo = true
        and t.estado = 'pendiente'
        and (
          t.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
          or (t.vendedor_id is null
              and t.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid)))
          or v_rol = 'gerencia'
        )
   )
     for no key update;

  select * into v_tarea
  from crm.tareas t
  where t.id = p_tarea_id
    and t.activo = true
    and t.estado = 'pendiente'
    and (
      t.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
      or (t.vendedor_id is null
          and t.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid)))
      or v_rol = 'gerencia'
    )
  for update;
  if not found then
    raise exception 'Tarea no encontrada, cerrada o fuera de tu ambito';
  end if;

  if p_resultado_tipo is not null then
    if v_tarea.lead_id is null then
      raise exception 'Una tarea de cliente no registra actividad de lead';
    end if;
    if p_resultado_tipo not in
       ('llamada_realizada','llamada_no_contestada','whatsapp_enviado',
        'whatsapp_recibido','reunion_realizada','nota') then
      raise exception 'Tipo de resultado invalido';
    end if;
  end if;
  if v_tarea.tipo = 'llamada' and p_estado = 'completada' and p_resultado_tipo is null then
    raise exception 'Registra el resultado de la llamada (contesto / no contesto)';
  end if;

  if p_resultado_tipo is not null then
    insert into crm.actividades (lead_id, tipo, detalle, creado_por)
    values (v_tarea.lead_id, p_resultado_tipo, nullif(btrim(coalesce(p_resultado_detalle,'')), ''), v_uid)
    returning id into v_act_id;
  end if;

  perform set_config('crm.op_tarea', 'on', true);
  update crm.tareas
     set estado = p_estado,
         resultado_actividad_id = v_act_id
   where id = p_tarea_id;

  if p_siguiente is not null then
    v_sig_tipo   := p_siguiente->>'tipo';
    v_sig_titulo := btrim(coalesce(p_siguiente->>'titulo',''));
    begin
      v_sig_vence := (p_siguiente->>'vence_en')::timestamptz;
    exception when others then
      raise exception 'Fecha invalida en la tarea siguiente';
    end;
    if p_siguiente->>'duracion_min' is not null then
      v_sig_duracion := (p_siguiente->>'duracion_min')::smallint;
    end if;
    if v_sig_tipo is null or v_sig_titulo = '' or v_sig_vence is null then
      raise exception 'La tarea siguiente exige tipo, titulo y vence_en';
    end if;
    perform set_config('crm.op_tarea', 'off', true);
    insert into crm.tareas
      (lead_id, perfil_id, tipo, titulo, nota, vence_en, duracion_min,
       reagendada_de, creado_por)
    values
      (v_tarea.lead_id, v_tarea.perfil_id, v_sig_tipo, v_sig_titulo,
       nullif(btrim(coalesce(p_siguiente->>'nota','')), ''), v_sig_vence, v_sig_duracion,
       case when p_estado = 'no_show' then p_tarea_id else null end, v_uid)
    returning id into v_sig_id;
  end if;
  perform set_config('crm.op_tarea', 'off', true);

  return jsonb_build_object(
    'ok', true,
    'tarea_id', p_tarea_id,
    'actividad_id', v_act_id,
    'siguiente_id', v_sig_id
  );
end;
$function$;

commit;

-- ORÁCULO de «No asistió espera a la hora de la cita» — se ejecuta en el
-- LABORATORIO (banco Docker local), NUNCA contra producción, y no escribe nada.
--
-- La regla (Miguel, 2026-10-05): «una reunión realizada antes de la hora
-- pactada puede marcarse realizada inmediatamente […]. Solo "No asistió" debe
-- esperar a que haya pasado la hora pactada». La hora pactada es
-- `crm.tareas.vence_en`.
--
-- El escenario se levanta contra la FORMA real del esquema (los CHECK, los
-- triggers, la jerarquía de equipo y los actores del banco) y el bloque termina
-- SIEMPRE en `raise`, así que Postgres deshace el lead sintético, las citas, las
-- actividades, los recibos y hasta la función recién reemplazada.
--
-- Este archivo NO se ejecuta a mano: `armar-ensayo.mjs` lo pega DETRÁS de la
-- migración real (a la que le quita su `begin;`/`commit;`) dentro de una única
-- transacción que termina en `rollback`. Con `--sin-migracion` lo pega solo, y
-- entonces TIENE que salir ROJO: es la medición del defecto.
--
-- Quién llama: la sesión del banco, con la identidad del actor fijada en los
-- claims del JWT (las puertas son `security definer` y deciden por
-- `auth.uid()`). NO se cambia de rol con `set role`: llamar bajo `set role` a
-- una función sin EXECUTE tumba el Postgres del banco, así que los permisos se
-- leen del catálogo (sección 9) y nunca se prueban llamando.

-- El oráculo espera a propósito (la frontera se mide con reloj real): necesita
-- su propio límite, no el de 30 s que deja puesto la migración.
set local statement_timeout = '120s';

-- Identidad de la sesión, en las DOS formas: el `auth.uid()` de producción lee
-- `request.jwt.claims` (->> 'sub') y el de algunas imágenes del banco solo
-- `request.jwt.claim.sub`.
create function pg_temp.sesion(p_actor uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_actor::text, ''), true),
         set_config('request.jwt.claims',
           case when p_actor is null then '' else json_build_object('sub', p_actor, 'role', 'authenticated')::text end, true);
$$;

-- Siembra una tarea de lead como la crea el analista. `trg_gestion_lead_serializada`
-- exige que `creado_por` sea el usuario autenticado: por eso fija antes la sesión
-- del dueño (quien llame después vuelve a fijar la suya).
create function pg_temp.sembrar(p_lead uuid, p_vendedor uuid, p_tipo text, p_titulo text, p_vence timestamptz)
returns uuid language plpgsql as $f$
declare v_id uuid;
begin
  perform pg_temp.sesion(p_vendedor);
  insert into crm.tareas (lead_id, tipo, titulo, vence_en, vendedor_id, modalidad_reunion, creado_por)
  values (p_lead, p_tipo, p_titulo, p_vence, p_vendedor,
          case when p_tipo = 'reunion' then 'sin_clasificar' end, p_vendedor)
  returning id into v_id;
  return v_id;
end;
$f$;

-- Foto de todo lo que un cierre puede tocar alrededor de una cita: su estado y
-- lo que cuelga del lead (o de la persona, en postventa). Si la foto de después
-- es igual a la de antes, el rechazo no dejó NADA: ni la cita cerrada, ni una
-- actividad, ni una tarea siguiente, ni un recibo.
create function pg_temp.foto(p_tarea uuid) returns text language sql as $$
  select format('estado=%s motivo=%s revision=%s etapa=%s tareas=%s actividades=%s recibos=%s gestiones=%s operaciones=%s',
           t.estado, coalesce(t.motivo_no_realizada, '-'), coalesce(t.postventa_revision::text, '-'),
           coalesce((select l.etapa from crm.leads l where l.id = t.lead_id), '-'),
           (select count(*) from crm.tareas x
             where x.lead_id is not distinct from t.lead_id
               and x.perfil_id is not distinct from t.perfil_id
               and x.inversionista_id is not distinct from t.inversionista_id),
           (select count(*) from crm.actividades a where a.lead_id = t.lead_id),
           (select count(*) from crm.sla_operacion_recibos r where r.lead_id = t.lead_id),
           (select count(*) from crm.inversionista_gestiones g where g.inversionista_id = t.inversionista_id),
           (select count(*) from crm.postventa_operaciones o where o.inversionista_id = t.inversionista_id))
  from crm.tareas t
  where t.id = p_tarea;
$$;

-- ENVÍA «No asistió» por UNA entrada, como el actor de la sesión. Devuelve
-- 'ok|<respuesta de la puerta>' o 'SQLSTATE|mensaje'. Va SIEMPRE con nota y con
-- tarea siguiente: así, si la entrada aceptara, quedarían una actividad y una
-- tarea nuevas que la foto delata (un rechazo que no rechaza no puede pasar por
-- rechazo limpio).
-- Sin `p_operacion`, cada envío lleva un identificador nuevo. Con él, es el
-- MISMO envío repetido: mismo identificador y mismo contenido (la tarea
-- siguiente se fecha con `now()`, fijo en toda la transacción). En postventa el
-- contenido incluye la revisión: quien repite un envío manda la que mandó la
-- primera vez (`p_revision`), no la que tenga ahora la tarea.
create function pg_temp.enviar_no_asistio(p_entrada text, p_tarea uuid,
                                          p_operacion uuid default null, p_revision integer default null)
returns text language plpgsql as $f$
declare
  v_nota constant text := 'No asistió (ensayo)';
  v_siguiente constant jsonb := jsonb_build_object(
    'tipo', 'llamada', 'titulo', 'ENSAYO Reagendar', 'vence_en', now() + interval '1 day');
  v_operacion constant uuid := coalesce(p_operacion, gen_random_uuid());
  v_respuesta jsonb;
begin
  case p_entrada
    when 'cerrar_reunion_v3' then
      v_respuesta := crm.cerrar_reunion_v3(v_operacion, p_tarea, 'no_show', null, null, v_nota, v_siguiente, null, null);
    when 'cerrar_reunion_v2' then
      v_respuesta := crm.cerrar_reunion_v2(v_operacion, p_tarea, 'no_show', null, null, v_nota, v_siguiente);
    when 'cerrar_reunion' then
      v_respuesta := crm.cerrar_reunion(p_tarea, 'no_show', null, null, v_nota, v_siguiente);
    when 'cerrar_tarea_v2' then
      v_respuesta := crm.cerrar_tarea_v2(v_operacion, p_tarea, 'no_show', 'nota', v_nota, v_siguiente, null, null);
    when 'cerrar_tarea' then
      v_respuesta := crm.cerrar_tarea(p_tarea, 'no_show', 'nota', v_nota, v_siguiente, null, null);
    when 'postventa_tarea_fn' then
      v_respuesta := crm.postventa_tarea_fn(v_operacion, p_tarea,
        coalesce(p_revision, (select t.postventa_revision from crm.tareas t where t.id = p_tarea)), 'cerrar',
        jsonb_build_object('estado', 'no_show', 'detalle', v_nota, 'siguiente', v_siguiente));
  end case;
  return 'ok|' || coalesce(v_respuesta::text, 'null');
exception when others then
  return sqlstate || '|' || sqlerrm;
end;
$f$;

-- Lo mismo, con identificador nuevo y sin la respuesta: 'ok' o 'SQLSTATE|mensaje'.
create function pg_temp.marcar_no_asistio(p_entrada text, p_tarea uuid) returns text language sql as $$
  select case when r like 'ok|%' then 'ok' else r end
  from pg_temp.enviar_no_asistio(p_entrada, p_tarea) r;
$$;

-- Exige el RECHAZO de la regla: SQLSTATE y mensaje exactos, y la foto intacta.
-- Devuelve '' si todo está bien, o la línea del fallo. La respuesta cruda del
-- intento queda en `ensayo.ultimo_envio`, para quien quiera citarla literal.
create function pg_temp.exigir_rechazo(p_caso text, p_entrada text, p_tarea uuid,
                                       p_operacion uuid default null, p_revision integer default null)
returns text language plpgsql as $f$
declare
  v_esperado constant text :=
    '22023|Aún no llega la hora de la cita: «No asistió» se registra cuando pase la hora pactada';
  v_antes text;
  v_resultado text;
  v_despues text;
  v_motivos text[] := '{}';
begin
  perform set_config('ensayo.ultimo_envio', 'no enviado', true);
  v_antes := pg_temp.foto(p_tarea);
  if v_antes is null or v_antes not like 'estado=pendiente %' then
    return format(E'FALLO %s (%s): la cita no estaba pendiente antes de probar (%s)\n',
      p_caso, p_entrada, coalesce(v_antes, 'no existe'));
  end if;
  v_resultado := pg_temp.enviar_no_asistio(p_entrada, p_tarea, p_operacion, p_revision);
  if v_resultado like 'ok|%' then v_resultado := 'ok'; end if;
  perform set_config('ensayo.ultimo_envio', v_resultado, true);
  v_despues := pg_temp.foto(p_tarea);
  if v_resultado = 'ok' then
    v_motivos := v_motivos || 'el servidor ACEPTÓ «No asistió» antes de la hora'::text;
  elsif v_resultado <> v_esperado then
    v_motivos := v_motivos || ('rechazó, pero no con la regla: ' || v_resultado);
  end if;
  if v_despues is distinct from v_antes then
    v_motivos := v_motivos || format('no quedó como estaba: [%s] → [%s]', v_antes, coalesce(v_despues, 'no existe'));
  end if;
  if cardinality(v_motivos) = 0 then
    return '';
  end if;
  return format(E'FALLO %s (%s): %s\n', p_caso, p_entrada, array_to_string(v_motivos, '; '));
end;
$f$;

-- Exige que «No asistió» ENTRE: respuesta ok y la tarea en `no_show` (con su
-- motivo si es una reunión). Devuelve '' o la línea del fallo.
create function pg_temp.exigir_aceptado(p_caso text, p_entrada text, p_tarea uuid) returns text language plpgsql as $f$
declare
  v_resultado text;
  v_tarea crm.tareas%rowtype;
begin
  v_resultado := pg_temp.marcar_no_asistio(p_entrada, p_tarea);
  select * into v_tarea from crm.tareas t where t.id = p_tarea;
  if v_resultado <> 'ok' then
    return format(E'FALLO %s (%s): «No asistió» debía entrar y se rechazó (%s)\n', p_caso, p_entrada, v_resultado);
  end if;
  if v_tarea.estado is distinct from 'no_show'
     or (v_tarea.tipo = 'reunion' and v_tarea.motivo_no_realizada is distinct from 'cliente_no_asistio') then
    return format(E'FALLO %s (%s): respondió ok pero la tarea quedó en %s/%s\n',
      p_caso, p_entrada, v_tarea.estado, coalesce(v_tarea.motivo_no_realizada, '-'));
  end if;
  return '';
end;
$f$;

do $ensayo$
declare
  v_vendedor uuid;
  v_supervisor uuid;
  v_gerencia uuid;
  v_sin_rol uuid;
  v_persona uuid;
  v_actor uuid;
  v_lead uuid;
  v_cita uuid;
  v_cita_nueva uuid;
  v_cita_antes uuid;
  v_cita_despues uuid;
  v_post_antes uuid := gen_random_uuid();
  v_post_despues uuid := gen_random_uuid();
  v_post_realizada uuid := gen_random_uuid();
  -- Identificadores FIJOS del caso «mismo identificador» (frontera): la
  -- operación del cierre de lead y la clave del cierre de postventa.
  v_op_lead constant uuid := gen_random_uuid();
  v_clave_post constant uuid := gen_random_uuid();
  v_op uuid;
  v_rev integer;
  v_primero_lead text;
  v_primero_post text;
  v_primero text;
  v_segundo text;
  v_tercero text;
  v_despues text;
  v_hora timestamptz;
  v_margen_lead numeric;
  v_margen_post numeric;
  v_retraso numeric;
  v_res jsonb;
  v_entrada text;
  v_tipo text;
  v_rol text;
  v_txt text;
  v_error text;
  v_antes text;
  v_estado text;
  v_pasada_entra boolean := true;
  v_rodeo_mover text;
  v_rodeo_nueva text;
  v_rodeo_marcar text;
  v_informe text := '';
  v_fallos integer := 0;
begin
  -- ── Actores reales del banco ──────────────────────────────────────────────
  -- Un vendedor efectivo con supervisor efectivo y con al menos una persona de
  -- postventa a su cargo (la reunión de cliente del caso 3 se agenda con él).
  -- Se toman del banco porque `private.rol_crm` y `private.vendedor_ids_visibles`
  -- leen la jerarquía viva: un actor inventado no probaría la autoridad.
  select e.perfil_id, e.supervisor_id into v_vendedor, v_supervisor
  from crm.equipo e
  where private.rol_crm(e.perfil_id) = 'vendedor'
    and private.rol_crm(e.supervisor_id) = 'supervisor'
    and exists (
      select 1 from crm.inversionistas i
      where i.responsable_relacion_id = e.perfil_id and i.estado = 'activo'
        and not i.no_contactar and i.inversionista_canonico_id is null)
  order by e.perfil_id limit 1;
  select e.perfil_id into v_gerencia
  from crm.equipo e where private.rol_crm(e.perfil_id) = 'gerencia'
  order by e.perfil_id limit 1;
  -- Un usuario del Portal SIN fila en el equipo del CRM (un cliente, p. ej.):
  -- autenticado, pero sin rol CRM. Es el actor de H-10.
  select p.id into v_sin_rol
  from public.perfiles p
  where p.activo and private.rol_crm(p.id) is null
    and not exists (select 1 from crm.equipo e where e.perfil_id = p.id)
  order by p.id limit 1;
  select i.id into v_persona
  from crm.inversionistas i
  where i.responsable_relacion_id = v_vendedor and i.estado = 'activo'
    and not i.no_contactar and i.inversionista_canonico_id is null
  order by i.id limit 1;

  -- Los actores son OBLIGATORIOS: sin ellos un caso se saltaría en silencio y el
  -- ensayo saldría verde sin haber mirado nada.
  if v_vendedor is null or v_supervisor is null or v_gerencia is null
     or v_sin_rol is null or v_persona is null then
    raise exception 'ENSAYO ABORTADO: faltan actores (vendedor=%, supervisor=%, gerencia=%, sin_rol=%, persona=%)',
      v_vendedor, v_supervisor, v_gerencia, v_sin_rol, v_persona;
  end if;

  -- ── Escenario: un lead contactado, dueño el vendedor ──────────────────────
  -- Teléfono aleatorio con el formato del CHECK. Ningún lead puede nacer en
  -- etapa terminal ni con origen «otro» (`private.leads_before_insert`).
  insert into crm.leads (nombre_completo, telefono, etapa, vendedor_id,
                         monto_estimado, moneda, origen, creado_por)
  values ('ENSAYO No Asistio Espera Hora',
          '+519' || lpad((floor(random() * 100000000))::bigint::text, 8, '0'),
          'contactado', v_vendedor, 1000.00, 'PEN', 'landing', v_vendedor)
  returning id into v_lead;

  -- ── 1. RECHAZO por las tres entradas de la cita de lead ───────────────────
  -- Cada entrada con SU cita: si una aceptara, no arrastraría a las demás.
  foreach v_entrada in array array['cerrar_reunion_v3', 'cerrar_reunion_v2', 'cerrar_reunion'] loop
    v_cita := pg_temp.sembrar(v_lead, v_vendedor, 'reunion', 'Cita futura · ' || v_entrada, now() + interval '1 hour');
    v_txt := pg_temp.exigir_rechazo('1', v_entrada, v_cita);
    if v_txt <> '' then v_fallos := v_fallos + 1; v_informe := v_informe || v_txt; end if;
  end loop;

  -- ── 2. RECHAZO por la vía genérica de tareas, sobre una reunión ───────────
  foreach v_entrada in array array['cerrar_tarea_v2', 'cerrar_tarea'] loop
    v_cita := pg_temp.sembrar(v_lead, v_vendedor, 'reunion', 'Cita futura · ' || v_entrada, now() + interval '1 hour');
    v_txt := pg_temp.exigir_rechazo('2', v_entrada, v_cita);
    if v_txt <> '' then v_fallos := v_fallos + 1; v_informe := v_informe || v_txt; end if;
  end loop;

  -- ── 4a. POSITIVO: con la hora ya pasada, «No asistió» entra por las cinco ─
  -- La mitad negativa no basta: una regla demasiado ancha dejaría las
  -- inasistencias de verdad sin poder registrarse.
  foreach v_entrada in array array['cerrar_reunion_v3', 'cerrar_reunion_v2', 'cerrar_reunion',
                                   'cerrar_tarea_v2', 'cerrar_tarea'] loop
    v_cita := pg_temp.sembrar(v_lead, v_vendedor, 'reunion', 'Cita pasada · ' || v_entrada, now() - interval '1 hour');
    v_txt := pg_temp.exigir_aceptado('4a', v_entrada, v_cita);
    if v_txt <> '' then
      v_fallos := v_fallos + 1; v_informe := v_informe || v_txt; v_pasada_entra := false;
    end if;
  end loop;

  -- ── 4b. POSITIVO: «Se realizó» ANTES de la hora sigue entrando ────────────
  -- La reunión anticipada es la mitad de la regla de Miguel: se acepta en el
  -- acto. Va por la puerta de la pantalla, con su capital.
  v_cita := pg_temp.sembrar(v_lead, v_vendedor, 'reunion', 'Cita anticipada', now() + interval '1 hour');
  v_error := null;
  begin
    v_res := crm.cerrar_reunion_v3(gen_random_uuid(), v_cita, 'completada', 'interesado',
               null, 'Llegó antes de la hora (ensayo)', null, 5000.00, 'PEN');
  exception when others then
    v_error := sqlstate || '|' || sqlerrm;
  end;
  select t.estado into v_estado from crm.tareas t where t.id = v_cita;
  if v_error is not null or v_estado is distinct from 'completada' then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 4b: «Se realizó» antes de la hora no entró (%s; la cita quedó en %s)\n',
      coalesce(v_error, 'sin error'), v_estado);
  end if;

  -- ── 4c. POSITIVO: cancelar antes de la hora sigue entrando ────────────────
  v_cita := pg_temp.sembrar(v_lead, v_vendedor, 'reunion', 'Cita que se cancela', now() + interval '1 hour');
  v_error := null;
  begin
    v_res := crm.cerrar_reunion_v3(gen_random_uuid(), v_cita, 'cancelada', null,
               'cancelada_cliente', null, null, null, null);
  exception when others then
    v_error := sqlstate || '|' || sqlerrm;
  end;
  select t.estado into v_estado from crm.tareas t where t.id = v_cita;
  if v_error is not null or v_estado is distinct from 'cancelada' then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 4c: cancelar antes de la hora no entró (%s; la cita quedó en %s)\n',
      coalesce(v_error, 'sin error'), v_estado);
  end if;

  -- ── 4d. POSITIVO: reprogramar antes de la hora sigue entrando ─────────────
  v_cita := pg_temp.sembrar(v_lead, v_vendedor, 'reunion', 'Cita que se mueve', now() + interval '1 hour');
  v_error := null;
  begin
    v_res := crm.reprogramar_reunion_v2(gen_random_uuid(), v_cita, now() + interval '2 days');
  exception when others then
    v_error := sqlstate || '|' || sqlerrm;
  end;
  select t.estado into v_estado from crm.tareas t where t.id = v_cita;
  if v_error is not null or v_estado is distinct from 'reprogramada'
     or not exists (select 1 from crm.tareas t
                    where t.reagendada_de = v_cita and t.estado = 'pendiente' and t.tipo = 'reunion') then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 4d: reprogramar antes de la hora no entró (%s; la cita quedó en %s)\n',
      coalesce(v_error, 'sin error'), v_estado);
  end if;

  -- ── 6. La regla es la MISMA para el supervisor del equipo y para gerencia ─
  -- El dueño ya quedó probado en 1 y 2. Aquí se exige el rechazo de la regla
  -- (22023 y su mensaje, no un «fuera de tu ámbito») y, pasada la hora, que el
  -- mismo actor sí pueda registrar la inasistencia.
  foreach v_rol in array array['supervisor', 'gerencia'] loop
    v_actor := case v_rol when 'supervisor' then v_supervisor else v_gerencia end;
    v_cita := pg_temp.sembrar(v_lead, v_vendedor, 'reunion', 'Cita futura · ' || v_rol, now() + interval '1 hour');
    perform pg_temp.sesion(v_actor);
    v_txt := pg_temp.exigir_rechazo('6-' || v_rol, 'cerrar_reunion_v3', v_cita);
    if v_txt <> '' then v_fallos := v_fallos + 1; v_informe := v_informe || v_txt; end if;

    v_cita := pg_temp.sembrar(v_lead, v_vendedor, 'reunion', 'Cita pasada · ' || v_rol, now() - interval '1 hour');
    perform pg_temp.sesion(v_actor);
    v_txt := pg_temp.exigir_aceptado('6-' || v_rol || '-pasada', 'cerrar_reunion_v3', v_cita);
    if v_txt <> '' then v_fallos := v_fallos + 1; v_informe := v_informe || v_txt; end if;
  end loop;

  -- ── 7. Lo que NO es reunión queda como estaba ─────────────────────────────
  -- Medido el 06/10 antes del cambio: la vía genérica acepta `no_show` en una
  -- llamada, un WhatsApp o una tarea aunque su hora no haya llegado. No es una
  -- regla de negocio que este cambio defienda: es la conducta de HOY, y la
  -- regla nueva no debe moverla ni para bien ni para mal.
  foreach v_tipo in array array['llamada', 'whatsapp', 'tarea'] loop
    foreach v_entrada in array array['cerrar_tarea_v2', 'cerrar_tarea'] loop
      v_cita := pg_temp.sembrar(v_lead, v_vendedor, v_tipo, 'Pendiente futura · ' || v_tipo, now() + interval '1 hour');
      v_txt := pg_temp.exigir_aceptado('7-' || v_tipo, v_entrada, v_cita);
      if v_txt <> '' then v_fallos := v_fallos + 1; v_informe := v_informe || v_txt; end if;
    end loop;
  end loop;

  -- ── 8. H-10 (se MIDE, no se corrige) ──────────────────────────────────────
  -- La guarda de rol de `crm.cerrar_reunion` no frena un rol nulo
  -- (`v_rol not in (…)` no se cumple con NULL); la segunda barrera —el ámbito—
  -- sí. Se llama a la v1 directa como un autenticado sin rol CRM, sobre una
  -- cita con la hora ya PASADA (para que la regla nueva no sea quien frene), y
  -- se exige que no entre y que no deje nada. El error que recibe se anota tal
  -- cual, sin fijarlo: cuando H-10 se corrija cambiará a «No autorizado».
  v_cita := pg_temp.sembrar(v_lead, v_vendedor, 'reunion', 'Cita pasada · sin rol', now() - interval '1 hour');
  perform pg_temp.sesion(v_sin_rol);
  v_antes := pg_temp.foto(v_cita);
  v_txt := pg_temp.marcar_no_asistio('cerrar_reunion', v_cita);
  if v_txt = 'ok' or pg_temp.foto(v_cita) is distinct from v_antes then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 8 (H-10): un autenticado sin rol CRM movió una cita (%s) [%s] → [%s]\n',
      v_txt, v_antes, pg_temp.foto(v_cita));
  end if;
  v_informe := v_informe || format(E'medida 8 (H-10): sin rol CRM, crm.cerrar_reunion directa responde «%s» y la cita queda igual\n', v_txt);

  -- ── P2-1. El RODEO por la hora (se MIDE, no se corrige) ───────────────────
  -- La regla compara contra la hora GUARDADA de la cita. Si el servidor deja
  -- mover esa hora al pasado, «No asistió» entra en dos pasos legítimos: la
  -- cita de las cinco se reprograma a «hace un minuto» y se marca la cita
  -- nueva. Lo hace el vendedor dueño, por las puertas de siempre. NO es una
  -- aserción ni suma fallos: es un límite conocido que decide Miguel, así que
  -- se anota tal cual lo que responde hoy el servidor.
  v_cita := pg_temp.sembrar(v_lead, v_vendedor, 'reunion', 'Cita futura · rodeo', now() + interval '1 hour');
  v_cita_nueva := null;
  begin
    v_res := crm.reprogramar_reunion_v2(gen_random_uuid(), v_cita, clock_timestamp() - interval '1 minute');
    v_rodeo_mover := 'ok';
    select t.id into v_cita_nueva
    from crm.tareas t
    where t.id = (v_res->>'tarea_nueva_id')::uuid and t.reagendada_de = v_cita;
  exception when others then
    v_rodeo_mover := sqlstate || '|' || sqlerrm;
  end;
  -- La foto de la cita nueva se toma ANTES de marcarla: cómo nace tras mover la hora.
  v_rodeo_nueva := coalesce((
    select format('%s, con su hora %s s atrás', t.estado, round(extract(epoch from clock_timestamp() - t.vence_en)))
    from crm.tareas t where t.id = v_cita_nueva), 'no existe');
  v_rodeo_marcar := case
    when v_cita_nueva is null then 'no medido: no hay cita nueva'
    else pg_temp.marcar_no_asistio('cerrar_reunion_v3', v_cita_nueva)
  end;
  v_informe := v_informe || format(
    E'medida P2-1 (rodeo por la hora): el dueño reprograma una cita futura a «hace un minuto» por crm.reprogramar_reunion_v2 y el servidor responde «%s» (la cita original queda: %s; la cita nueva nace: %s); «No asistió» sobre la cita nueva por crm.cerrar_reunion_v3 responde «%s» (la cita nueva queda: %s). Crear directamente una reunión de lead con la hora ya pasada y marcarla «No asistió» %s (caso 4a).\n',
    v_rodeo_mover,
    (select t.estado from crm.tareas t where t.id = v_cita),
    v_rodeo_nueva,
    v_rodeo_marcar,
    coalesce((select t.estado from crm.tareas t where t.id = v_cita_nueva), 'no existe'),
    case when v_pasada_entra then 'también entra' else 'NO entró en esta corrida' end);

  -- ── 3 y 5. POSTVENTA y FRONTERA, con reloj real ───────────────────────────
  -- Todas estas citas comparten una hora pactada a pocos segundos. La reunión
  -- de cliente se agenda por SU puerta (`postventa_agendar_fn`), que solo
  -- admite horas futuras: no hay otra forma honrada de tener una cita de
  -- postventa «antes de la hora».
  v_hora := clock_timestamp() + interval '3 seconds';
  v_cita_antes := pg_temp.sembrar(v_lead, v_vendedor, 'reunion', 'Cita de frontera · antes', v_hora);
  v_cita_despues := pg_temp.sembrar(v_lead, v_vendedor, 'reunion', 'Cita de frontera · después', v_hora);
  -- De aquí al final el actor es el vendedor: dueño del lead y responsable de
  -- la persona de postventa.
  perform pg_temp.sesion(v_vendedor);
  begin
    perform crm.postventa_agendar_fn(v_post_antes, v_persona, jsonb_build_object(
      'tipo', 'reunion', 'titulo', 'ENSAYO Reunión de cliente · antes', 'vence_en', v_hora,
      'modalidad_reunion', 'presencial', 'ubicacion_reunion', 'Oficina de ensayo'));
    perform crm.postventa_agendar_fn(v_post_despues, v_persona, jsonb_build_object(
      'tipo', 'reunion', 'titulo', 'ENSAYO Reunión de cliente · después', 'vence_en', v_hora,
      'modalidad_reunion', 'presencial', 'ubicacion_reunion', 'Oficina de ensayo'));
    perform crm.postventa_agendar_fn(v_post_realizada, v_persona, jsonb_build_object(
      'tipo', 'reunion', 'titulo', 'ENSAYO Reunión de cliente · anticipada', 'vence_en', now() + interval '1 hour',
      'modalidad_reunion', 'presencial', 'ubicacion_reunion', 'Oficina de ensayo'));
  exception when others then
    -- Sin la reunión de cliente el caso 3 no se prueba: se aborta, no se simula.
    raise exception 'ENSAYO ABORTADO: no se pudo agendar la reunión de postventa (% %)', sqlstate, sqlerrm;
  end;

  -- 4b-bis. La reunión de cliente anticipada también entra como realizada.
  v_error := null;
  begin
    v_res := crm.postventa_tarea_fn(gen_random_uuid(), v_post_realizada, 1, 'cerrar',
               jsonb_build_object('estado', 'completada', 'detalle', 'Se reunió antes de la hora (ensayo)'));
  exception when others then
    v_error := sqlstate || '|' || sqlerrm;
  end;
  select t.estado into v_estado from crm.tareas t where t.id = v_post_realizada;
  if v_error is not null or v_estado is distinct from 'completada' then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 4b-postventa: «Se realizó» antes de la hora no entró (%s; quedó en %s)\n',
      coalesce(v_error, 'sin error'), v_estado);
  end if;

  -- JUSTO ANTES de la hora: se espera hasta que falten unas décimas y se intenta.
  -- Estos dos intentos llevan un identificador FIJO (y, en postventa, la
  -- revisión 1 con la que nació la cita): son el primer envío del caso «mismo
  -- identificador» de más abajo.
  while clock_timestamp() < v_hora - interval '0.7 seconds' loop
    perform pg_sleep(0.01);
  end loop;
  v_txt := pg_temp.exigir_rechazo('3', 'postventa_tarea_fn', v_post_antes, v_clave_post, 1);
  v_margen_post := extract(epoch from v_hora - clock_timestamp());
  v_primero_post := current_setting('ensayo.ultimo_envio', true);
  if v_txt <> '' then v_fallos := v_fallos + 1; v_informe := v_informe || v_txt; end if;
  v_txt := pg_temp.exigir_rechazo('5-antes', 'cerrar_reunion_v3', v_cita_antes, v_op_lead);
  v_margen_lead := extract(epoch from v_hora - clock_timestamp());
  v_primero_lead := current_setting('ensayo.ultimo_envio', true);
  if v_txt <> '' then v_fallos := v_fallos + 1; v_informe := v_informe || v_txt; end if;
  -- Si la hora llegó MIENTRAS se intentaba, el «antes» no se midió: es un
  -- fallo del ensayo, no un verde (se repite la corrida).
  if v_margen_post <= 0 or v_margen_lead <= 0 then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 5-antes: no concluyente, la hora llegó durante el intento (márgenes %s s y %s s)\n',
      round(v_margen_post, 3), round(v_margen_lead, 3));
  end if;

  -- DESDE EL INSTANTE de la hora: se rechaza mientras `vence_en` sea posterior
  -- al reloj y se acepta cuando `vence_en <= reloj`.
  while clock_timestamp() < v_hora loop
    perform pg_sleep(0.005);
  end loop;
  v_txt := pg_temp.exigir_aceptado('5-despues', 'cerrar_reunion_v3', v_cita_despues);
  v_retraso := extract(epoch from clock_timestamp() - v_hora);
  if v_txt <> '' then v_fallos := v_fallos + 1; v_informe := v_informe || v_txt; end if;
  v_txt := pg_temp.exigir_aceptado('3-despues', 'postventa_tarea_fn', v_post_despues);
  if v_txt <> '' then v_fallos := v_fallos + 1; v_informe := v_informe || v_txt; end if;
  v_informe := v_informe || format(
    E'medida 5 (frontera): intentos a %s s (postventa) y %s s (lead) ANTES de la hora; intento %s s DESPUÉS de la hora\n',
    round(v_margen_post, 3), round(v_margen_lead, 3), round(v_retraso, 3));

  -- MISMO IDENTIFICADOR. La pantalla guarda el identificador de un envío y lo
  -- repite tal cual. Aquí se repite el envío que se rechazó «justo antes»
  -- —misma operación o clave, mismo contenido y, en postventa, la misma
  -- revisión 1— ya con la hora cumplida: tiene que entrar, porque el rechazo
  -- no dejó recibo ni consumió el identificador. Y un TERCER envío idéntico
  -- tiene que devolver la misma respuesta sin duplicar actividad, tarea
  -- siguiente ni recibo (lo dice la foto de antes y de después).
  foreach v_entrada in array array['cerrar_reunion_v3', 'postventa_tarea_fn'] loop
    if v_entrada = 'cerrar_reunion_v3' then
      v_cita := v_cita_antes; v_op := v_op_lead; v_rev := null; v_primero := v_primero_lead;
    else
      v_cita := v_post_antes; v_op := v_clave_post; v_rev := 1; v_primero := v_primero_post;
    end if;
    v_segundo := pg_temp.enviar_no_asistio(v_entrada, v_cita, v_op, v_rev);
    select t.estado into v_estado from crm.tareas t where t.id = v_cita;
    if v_segundo not like 'ok|%' or v_estado is distinct from 'no_show' then
      v_fallos := v_fallos + 1;
      v_informe := v_informe || format(E'FALLO 5-misma-cita (%s): el mismo envío, repetido con la hora ya cumplida, no entró (%s; la cita quedó en %s)\n',
        v_entrada, v_segundo, v_estado);
    end if;
    v_antes := pg_temp.foto(v_cita);
    v_tercero := pg_temp.enviar_no_asistio(v_entrada, v_cita, v_op, v_rev);
    v_despues := pg_temp.foto(v_cita);
    -- El tercer envío solo se juzga si el segundo entró: si no, el fallo ya
    -- está contado arriba y no hay respuesta con la que comparar.
    if v_segundo like 'ok|%' and (v_tercero is distinct from v_segundo or v_despues is distinct from v_antes) then
      v_fallos := v_fallos + 1;
      v_informe := v_informe || format(E'FALLO 5-replay (%s): el tercer envío idéntico %s; [%s] → [%s]\n',
        v_entrada,
        case when v_tercero is distinct from v_segundo then 'devolvió OTRA respuesta: ' || v_tercero
             else 'devolvió la misma respuesta, pero dejó algo nuevo' end,
        v_antes, v_despues);
    end if;
    v_informe := v_informe || format(
      E'medida 5 (mismo identificador, %s): 1.er envío, justo antes de la hora → «%s»; 2.º envío, mismo identificador y mismo contenido, con la hora cumplida → «%s» (la cita queda: %s); 3.er envío idéntico → %s; alrededor del 3.º: [%s] → [%s]\n',
      v_entrada, v_primero,
      case when v_segundo like 'ok|%' then 'ok' else v_segundo end, v_estado,
      case when v_segundo not like 'ok|%' then 'no juzgado (el 2.º no entró): «' || v_tercero || '»'
           when v_tercero is not distinct from v_segundo then 'la misma respuesta que el 2.º'
           else 'OTRA respuesta que el 2.º' end,
      v_antes, v_despues);
  end loop;

  -- ── 9. El candado conserva su forma y las entradas, sus permisos ──────────
  -- Dueño, `security definer`, `search_path` vacío y NINGÚN rol con EXECUTE
  -- salvo el dueño; y sigue colgado de `crm.tareas` como BEFORE UPDATE por
  -- fila, habilitado, sin WHEN y sin lista de columnas: con cualquiera de esas
  -- dos cláusulas habría UPDATE que no pasarían por la regla.
  if not exists (
       select 1 from pg_proc p
       where p.oid = 'private.trg_tareas_before_update()'::regprocedure
         and p.prosecdef and p.proowner = 'postgres'::regrole::oid
         and p.proconfig = array['search_path=""'])
     or exists (
       select 1 from pg_proc p
       cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
       where p.oid = 'private.trg_tareas_before_update()'::regprocedure
         and a.grantee <> 'postgres'::regrole::oid) then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || E'FALLO 9a: el candado cambió de dueño, de atributos o de permisos\n';
  end if;
  if not exists (
       select 1 from pg_trigger t
       where t.tgrelid = 'crm.tareas'::regclass and t.tgname = 'trg_tareas_00_before_update'
         and t.tgfoid = 'private.trg_tareas_before_update()'::regprocedure
         and t.tgenabled = 'O' and t.tgtype = 19
         and t.tgqual is null and cardinality(t.tgattr::int2[]) = 0) then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || E'FALLO 9b: el candado ya no cuelga de crm.tareas como BEFORE UPDATE por fila, habilitado, sin WHEN y sobre todas las columnas\n';
  end if;
  -- Las seis entradas siguen concedidas a `authenticated` (leído del catálogo).
  foreach v_entrada in array array[
    'crm.cerrar_reunion_v3(uuid,uuid,text,text,text,text,jsonb,numeric,text)',
    'crm.cerrar_reunion_v2(uuid,uuid,text,text,text,text,jsonb)',
    'crm.cerrar_reunion(uuid,text,text,text,text,jsonb)',
    'crm.cerrar_tarea_v2(uuid,uuid,text,text,text,jsonb,text,text)',
    'crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text)',
    'crm.postventa_tarea_fn(uuid,uuid,integer,text,jsonb,uuid)'] loop
    if not has_function_privilege('authenticated', v_entrada::regprocedure, 'EXECUTE') then
      v_fallos := v_fallos + 1;
      v_informe := v_informe || format(E'FALLO 9c: authenticated ya no puede llamar a %s\n', v_entrada);
    end if;
  end loop;
  -- La regla compara `old.vence_en > reloj`: con una hora NULL esa comparación
  -- no se cumple y «No asistió» pasaría. La columna tiene que seguir NOT NULL.
  if not exists (
       select 1 from pg_attribute a
       where a.attrelid = 'crm.tareas'::regclass and a.attname = 'vence_en'
         and not a.attisdropped and a.attnotnull) then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || E'FALLO 9d: crm.tareas.vence_en ya no es NOT NULL: una cita sin hora esquivaría la regla\n';
  end if;

  -- ── 10. Los gates que sellan a los writers siguen pasando ─────────────────
  -- El cambio no toca `crm.cerrar_reunion` ni `crm.cerrar_tarea`: sus sellos
  -- md5 tienen que seguir intactos.
  begin
    v_informe := v_informe || format(E'gate: %s\n', private.assert_sla_comandos());
    v_informe := v_informe || format(E'gate: %s\n', private.assert_entrevista_al_asistir());
  exception when others then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 10: un gate cayó (%s %s)\n', sqlstate, sqlerrm);
  end;

  -- ── 11. Lo diferido se comprueba AHORA, no en un COMMIT que nunca llega ───
  -- El ensayo termina en `raise`, así que las restricciones diferidas (las FKs
  -- de los recibos y su confirmación, que Postgres mira al COMMIT) no llegarían
  -- a comprobarse: un «ok» que no sobreviviría al COMMIT pasaría por bueno. Se
  -- fuerzan aquí y un fallo cuenta como fallo del ensayo.
  begin
    set constraints all immediate;
  exception when others then
    v_fallos := v_fallos + 1;
    v_informe := v_informe || format(E'FALLO 11: algo de lo aceptado no sobreviviría al COMMIT (%s %s)\n', sqlstate, sqlerrm);
  end;

  -- ── Veredicto, y rollback SIEMPRE ─────────────────────────────────────────
  raise exception E'ENSAYO %:\n%(rollback a propósito — nada queda escrito)',
    case when v_fallos = 0 then 'VERDE — 0 fallos' else format('ROJO — %s fallo(s)', v_fallos) end,
    v_informe;
end;
$ensayo$;

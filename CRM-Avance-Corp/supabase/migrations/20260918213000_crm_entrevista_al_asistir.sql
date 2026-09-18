-- ENTREVISTA AL ASISTIR — marcar «Se realizó» registra la entrevista.
--
-- Pedido de Miguel (2026-09-18): «cuando el analista diga que una cita vino a
-- la cita, esto se convierta automáticamente en una entrevista». La regla de
-- negocio ya existía en Gerencia desde el 13/09 —«Cita: generada en el CRM.
-- Entrevista: asistencia a una cita»— y sus contadores la aplican solos
-- (private.citas_episodios cuenta t.estado='completada'). Lo que NO ocurría es
-- el pipeline del lead: `crm.cerrar_reunion` escribe la actividad
-- `reunion_realizada` y con eso el avance automático solo sube de `nuevo` a
-- `contactado`, así que una cita atendida sobre un lead ya contactado no movía
-- NADA y el analista tenía que arrastrar la tarjeta a mano. La etapa se
-- rotula «Entrevista realizada» en la pantalla y su clave en la base es
-- `propuesta_enviada` (app/src/lib/tipos.ts).
--
-- ── Las cuatro capas (estándar Avanza Digital) ───────────────────────────────
--   1. TABLA    `crm.leads` — ya existe. Sus CHECK (`leads_etapa_check`,
--               `leads_monto_estimado_valido`, `leads_moneda_check`) son el
--               último candado: lo que no debe romperse vive en la base.
--   2. NÚCLEO   `private.entrevista_registrar(uuid,uuid,numeric,text)` — LA
--               OPERACIÓN DE NEGOCIO: comprueba autoridad sobre el lead, sube
--               la etapa a «Entrevista realizada» y asienta el capital
--               propuesto. Privada: revocada a todos los roles.
--   3. PUERTA   `crm.cerrar_reunion_v3(...)` — expuesta a `authenticated`.
--               Valida el INPUT, delega el cierre en `crm.cerrar_reunion_v2` y
--               la entrevista en el núcleo. Sin lógica de negocio propia.
--   4. PANTALLA el diálogo de cerrar la cita, que solo llama a esta puerta.
--
-- POR QUÉ UNA PUERTA NUEVA Y NO TOCAR `crm.cerrar_reunion`: el cuerpo de ese
-- writer está SELLADO por md5 en `private.assert_sla_comandos` (y el sello se
-- re-ejecuta en cada publicación posterior) porque de él depende el orden de
-- bloqueos lead→tarea de los comandos SLA. Cambiarlo obligaría a re-sellar y a
-- re-auditar ese orden para conseguir un efecto que se logra POR ENCIMA, sin
-- tocarlo. `cerrar_reunion_v3` compone: delega el cierre entero en
-- `cerrar_reunion_v2` (recibo idempotente incluido) y después registra la
-- entrevista. Las dos cosas viven en la MISMA transacción: o la cita queda
-- cerrada Y la entrevista registrada, o no pasa ninguna de las dos.
--
-- EL CAPITAL VIAJA EN EL MISMO ACTO (decisión de Miguel, 2026-09-18). Nadie
-- llega hoy a «Entrevista realizada» sin declarar el capital propuesto: el
-- diálogo de capital-propuesta.tsx lo exige desde el 2026-07-25 porque de esa
-- cifra viven el capital en proceso y las metas del mes, y el `monto_estimado`
-- del primer contacto es una corazonada. Si la etapa subiera sola sin
-- preguntar, el avance automático fabricaría entrevistas con capital en blanco
-- —el mismo bug que ese diálogo vino a cerrar, ahora invisible—. Por eso el
-- capital es OBLIGATORIO cuando la cita se cierra como realizada, se valida en
-- la puerta ANTES de cerrar nada, y el núcleo lo escribe en la misma sentencia
-- que la etapa.
--
-- CON UNA EXCEPCIÓN: `no_interesado`. A quien dijo que no, nadie le propuso un
-- capital; exigir ahí una cifra > 0 obligaría al analista a INVENTARLA, y esa
-- invención entraría al capital en proceso y a las metas del mes por la misma
-- puerta que las cifras reales. La entrevista SÍ se registra (ocurrió, y así lo
-- cuenta Gerencia), pero el capital del lead se queda como estaba. Es la única
-- asimetría del cambio y sale de un hallazgo de la auditoría del 18/09.
--
-- SEGUNDA ENTREVISTA DE LA MISMA PERSONA: la etapa ya no puede subir más, pero
-- el capital que se acaba de proponer SÍ es el vigente. El núcleo por eso
-- separa las dos cosas: la etapa solo sube (jamás baja, doctrina de
-- lib/avance-automatico.ts), el capital declarado se asienta siempre.
--
-- REVERSIÓN: `drop function crm.cerrar_reunion_v3(uuid,uuid,text,text,text,text,jsonb,numeric,text);`
-- luego `drop function private.entrevista_registrar(uuid,uuid,numeric,text);`
-- y `drop function private.assert_entrevista_al_asistir();`. El front vuelve a
-- `cerrar_reunion_v2` y la etapa se mueve a mano como hasta hoy. Nada de lo
-- escrito por esta puerta necesita deshacerse: un lead en «Entrevista
-- realizada» con su capital declarado es exactamente lo que el analista
-- afirmó.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';

do $preflight$
begin
  -- La puerta nueva se APOYA en estas dos; si alguna no está donde se auditó,
  -- no se instala (fail-closed: mejor no existir que existir a medias).
  if to_regprocedure('crm.cerrar_reunion_v2(uuid,uuid,text,text,text,text,jsonb)') is null
     or to_regprocedure('private.sla_gestion_permitida(uuid,uuid)') is null then
    raise exception 'Instalar primero los comandos SLA N3';
  end if;
  -- El writer sellado NO se toca en esta migración: se comprueba que sigue
  -- siendo el auditado, porque `cerrar_reunion_v2` delega en él.
  if (select md5(p.prosrc) from pg_proc p
       where p.oid='crm.cerrar_reunion(uuid,text,text,text,text,jsonb)'::regprocedure)
     is distinct from '8ccb961e63d5bcc4bd459af12c7d1dd0' then
    raise exception 'El writer de agenda cambió desde el sello SLA: re-auditar antes de componer sobre él';
  end if;
  if to_regprocedure('crm.cerrar_reunion_v3(uuid,uuid,text,text,text,text,jsonb,numeric,text)') is not null
     or to_regprocedure('private.entrevista_registrar(uuid,uuid,numeric,text)') is not null then
    raise exception 'La entrevista automatica ya esta instalada';
  end if;
end;
$preflight$;

-- ── CAPA 2 · NÚCLEO ─────────────────────────────────────────────────────────
-- Registrar la entrevista: UNA operación de negocio, completa y atómica. No
-- sabe nada de citas ni de tareas; recibe el lead ya cerrado por el writer de
-- agenda y afirma el hecho comercial —«esta persona fue entrevistada y se le
-- propuso este capital»— sobre el pipeline.
create function private.entrevista_registrar(
  p_lead uuid,
  p_actor uuid,
  p_capital numeric,
  p_moneda text
) returns jsonb
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_etapa_previa text;
  v_etapa text;
  v_avance_auto_previo text := current_setting('crm.avance_auto', true);
  v_filas integer;
begin
  if p_lead is null or p_actor is null then
    raise exception 'Una entrevista necesita lead y actor' using errcode = '22023';
  end if;
  -- El capital es OPCIONAL para el núcleo: nulo significa «no lo toques» (la
  -- entrevista que terminó en `no_interesado`). Quien decide si puede faltar es
  -- la puerta; aquí solo se respeta. Su forma la garantiza el CHECK
  -- `leads_monto_estimado_valido` de la tabla, que es el último candado.
  if (p_capital is null) <> (p_moneda is null) then
    raise exception 'El capital y su moneda viajan juntos o no viajan'
      using errcode = '22023';
  end if;

  -- AUTORIDAD. La puerta ya la exigió al ejecutar el comando de cierre; el
  -- núcleo la vuelve a exigir porque es `security definer` y su UPDATE no pasa
  -- por la RLS de `crm.leads`. Es la MISMA autoridad, nunca más ancha:
  -- `sla_gestion_permitida` es estrictamente más estrecha que la policy
  -- `leads_update` (al vendedor le exige ser el dueño exacto del lead, no solo
  -- verlo) y `private.rol_crm` ya descarta a los actores inactivos.
  if private.sla_gestion_permitida(p_actor, p_lead) is distinct from true then
    raise exception 'Gestion no disponible en tu ambito' using errcode = '42501';
  end if;

  select l.etapa into v_etapa_previa
  from crm.leads l
  where l.id = p_lead;

  -- La fila ya está bloqueada por el comando de cierre (`for update` sobre el
  -- lead), así que entre la lectura de la etapa y este UPDATE no se cuela nadie.
  --
  -- El avance queda MARCADO como automático en el historial: lo ordenó el
  -- sistema al registrar la asistencia, no el analista pidiendo un cambio de
  -- etapa. Misma GUC local que usan los dos triggers de avance
  -- (20260725060657), y se restaura al valor que traía la transacción.
  --
  -- La etapa SOLO SUBE; el capital declarado se asienta siempre. Las dos reglas
  -- van en una sola sentencia para que una segunda entrevista no pueda dejar la
  -- cifra nueva a medio camino.
  perform set_config('crm.avance_auto', 'on', true);
  update crm.leads l
     set etapa = case
           when l.etapa in ('nuevo', 'contactado', 'reunion_agendada')
             then 'propuesta_enviada'
           else l.etapa
         end,
         monto_estimado = coalesce(p_capital, l.monto_estimado),
         moneda = coalesce(p_moneda, l.moneda)
   where l.id = p_lead
     and l.activo
     and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada');
  get diagnostics v_filas = row_count;
  perform set_config('crm.avance_auto', coalesce(v_avance_auto_previo, 'off'), true);

  -- NADA A MEDIAS. Si la fila no se dejó tocar —lead ya convertido, descartado
  -- o inactivo: el writer de agenda no mira la etapa del lead antes de cerrar
  -- su cita— la cita NO puede quedar cerrada con el capital perdido en el
  -- camino. Se cae la transacción entera y la cita sigue abierta. Hallazgo P2-2
  -- de la auditoría del 18/09: devolver `ok` con `capital_asentado=false` era
  -- justo el fallo silencioso que este cambio venía a cerrar.
  if v_filas <> 1 then
    raise exception 'Este lead ya no admite registrar la entrevista'
      using errcode = 'P0409';
  end if;

  select l.etapa into v_etapa from crm.leads l where l.id = p_lead;
  return jsonb_build_object(
    'etapa', v_etapa,
    'etapa_previa', v_etapa_previa,
    'entrevista_registrada', v_etapa_previa <> 'propuesta_enviada',
    'capital_asentado', p_capital is not null
  );
end;
$function$;

comment on function private.entrevista_registrar(uuid,uuid,numeric,text) is
  'NÚCLEO: registra la entrevista de un lead — sube la etapa a propuesta_enviada («Entrevista realizada») si venía de una anterior y asienta el capital propuesto. La etapa solo sube; el capital se asienta siempre.';

revoke all on function private.entrevista_registrar(uuid,uuid,numeric,text)
  from public, anon, authenticated, service_role;

-- ── CAPA 3 · PUERTA ─────────────────────────────────────────────────────────
-- Valida el input, autoriza delegando y compone las dos operaciones. Ninguna
-- regla de negocio vive aquí.
create function crm.cerrar_reunion_v3(
  p_operacion_id uuid,
  p_tarea_id uuid,
  p_estado text,
  p_resultado_reunion text default null,
  p_motivo_no_realizada text default null,
  p_detalle text default null,
  p_siguiente jsonb default null,
  p_capital_estimado numeric default null,
  p_moneda text default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_respuesta jsonb;
  v_lead uuid;
  v_replay boolean;
begin
  -- EL INPUT SE VALIDA ANTES DE CERRAR NADA. Si la cifra no vale, la cita sigue
  -- abierta y el analista reintenta con el MISMO p_operacion_id: no hay recibo
  -- consumido ni entrevista a medio registrar.
  -- El capital se exige en toda cita realizada MENOS cuando el cliente dijo que
  -- no: ahí no hubo propuesta que declarar y pedir una cifra sería pedir que se
  -- la invente (ver la cabecera). El resultado comercial lo valida el writer.
  if p_estado = 'completada' and coalesce(p_resultado_reunion, '') <> 'no_interesado' then
    if p_capital_estimado is null
       or not (p_capital_estimado > 0)
       -- `trunc`, no `round`: espejo EXACTO del CHECK
       -- `leads_monto_estimado_valido`. Se rechaza una cifra con más de dos
       -- decimales en vez de redondearla — redondear movería el capital que el
       -- analista declaró sin que nadie se enterara.
       or p_capital_estimado <> trunc(p_capital_estimado, 2)
       -- Mismo rango que `numeric(12,2)` de la columna y que MONTO_ESTIMADO_MAX
       -- del front (lib/validacion.ts): ni más estrecho —rechazaría cifras que
       -- la ficha sí acepta— ni más ancho —el UPDATE reventaría con 23514—.
       or p_capital_estimado > 9999999999.99 then
      raise exception 'Declara el capital que le propusiste en la entrevista'
        using errcode = '22023';
    end if;
    if p_moneda is null or p_moneda not in ('PEN', 'USD') then
      raise exception 'La moneda del capital propuesto es obligatoria'
        using errcode = '22023';
    end if;
  elsif p_capital_estimado is not null or p_moneda is not null then
    -- Un plantón, una cancelación o un «no interesado» no proponen capital a
    -- nadie. Recibirlo aquí delata un llamador confundido, y aceptarlo en
    -- silencio escribiría una cifra que nadie declaró.
    raise exception 'El capital solo acompaña a una cita realizada con propuesta'
      using errcode = '22023';
  end if;

  -- ¿ES UN REPLAY? El recibo del comando (crm.sla_operacion_recibos) guarda el
  -- payload del CIERRE, no el capital, así que reenviar la misma operación con
  -- otra cifra no se detectaría allí: `cerrar_reunion_v2` devolvería la
  -- respuesta guardada sin trabajar y el núcleo, en cambio, volvería a escribir
  -- el capital nuevo. Se mira ANTES de delegar —y se sigue delegando, para que
  -- el writer valide la identidad del recibo y rechace un contenido distinto—
  -- pero si ya venía confirmado, esta llamada no escribe NADA. Hallazgo P2-1 de
  -- la auditoría del 18/09.
  select r.respuesta is not null into v_replay
  from crm.sla_operacion_recibos r
  where r.actor_id = (select auth.uid()) and r.operacion_id = p_operacion_id;

  -- El cierre ENTERO sigue siendo del writer auditado: estados válidos,
  -- ámbito, locks lead→tarea, actividad, tarea siguiente, retroceso al
  -- cancelar, episodio SLA de la gestión y recibo idempotente.
  v_respuesta := crm.cerrar_reunion_v2(
    p_operacion_id, p_tarea_id, p_estado,
    p_resultado_reunion, p_motivo_no_realizada, p_detalle, p_siguiente
  );

  if p_estado <> 'completada' then
    return v_respuesta;
  end if;

  v_lead := (v_respuesta->>'lead_id')::uuid;
  if v_lead is null then
    return v_respuesta;
  end if;

  if coalesce(v_replay, false) then
    -- Confirmada antes: se devuelve lo guardado con una foto de solo lectura
    -- del lead. Ni etapa ni capital se vuelven a tocar (eso movería también
    -- `actualizado_en` y añadiría ruido a la auditoría por una repetición).
    return v_respuesta || jsonb_build_object(
      'etapa', (select l.etapa from crm.leads l where l.id = v_lead),
      'entrevista_registrada', false,
      'capital_asentado', false
    );
  end if;

  return v_respuesta || private.entrevista_registrar(
    v_lead, (select auth.uid()), p_capital_estimado, p_moneda
  );
end;
$function$;

comment on function crm.cerrar_reunion_v3(uuid,uuid,text,text,text,text,jsonb,numeric,text) is
  'PUERTA: cierra una cita de lead y, si el cliente asistió, registra la entrevista (etapa propuesta_enviada + capital propuesto) en la misma transacción. Valida el input y delega: el cierre en cerrar_reunion_v2, la entrevista en private.entrevista_registrar.';

revoke all on function crm.cerrar_reunion_v3(uuid,uuid,text,text,text,text,jsonb,numeric,text)
  from public, anon, authenticated, service_role;
grant execute on function crm.cerrar_reunion_v3(uuid,uuid,text,text,text,text,jsonb,numeric,text)
  to authenticated;

-- ── Gate propio ──────────────────────────────────────────────────────────────
-- Mismo trinquete que `private.assert_sla_comandos`: la puerta no puede perder
-- su autoridad ni su aislamiento de search_path, el núcleo no puede quedar
-- expuesto a ningún rol, y el writer sobre el que se compone no puede cambiar
-- sin que un control lo grite.
create function private.assert_entrevista_al_asistir() returns text
language plpgsql stable security definer set search_path='' as $function$
declare
  v_puerta constant text := 'crm.cerrar_reunion_v3(uuid,uuid,text,text,text,text,jsonb,numeric,text)';
  v_nucleo constant text := 'private.entrevista_registrar(uuid,uuid,numeric,text)';
  v_firma text;
  v_id oid;
begin
  foreach v_firma in array array[v_puerta, v_nucleo] loop
    v_id := to_regprocedure(v_firma);
    if v_id is null or not exists(
      select 1 from pg_proc p
      where p.oid = v_id and p.prosecdef
        and p.proowner = 'postgres'::regrole::oid
        and p.provolatile = 'v'
        and p.proconfig @> array['search_path=""']
    ) then
      raise exception 'Contrato de la entrevista automatica alterado: %', v_firma;
    end if;
  end loop;

  -- La puerta es la ÚNICA expuesta, y solo a `authenticated`.
  v_id := to_regprocedure(v_puerta);
  if not has_function_privilege('authenticated', v_id, 'EXECUTE')
     or exists(
       select 1 from pg_proc p
       cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
       where p.oid = v_id
         and a.grantee not in ('postgres'::regrole::oid, 'authenticated'::regrole::oid)
     ) then
    raise exception 'ACL de la puerta de entrevista alterado: %', v_puerta;
  end if;

  -- El núcleo NO se llama desde la pantalla: si alguien le abre la puerta, la
  -- capa 3 deja de ser la única entrada y la autoridad se puede saltar.
  v_id := to_regprocedure(v_nucleo);
  if exists(
    select 1 from pg_proc p
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where p.oid = v_id and a.grantee <> 'postgres'::regrole::oid
  ) then
    raise exception 'El nucleo de entrevista quedo expuesto: %', v_nucleo;
  end if;

  -- La puerta compone sobre el writer sellado: si ese cuerpo cambia, el orden
  -- de bloqueos que hereda dejó de ser el auditado.
  if (select md5(p.prosrc) from pg_proc p
       where p.oid='crm.cerrar_reunion(uuid,text,text,text,text,jsonb)'::regprocedure)
     is distinct from '8ccb961e63d5bcc4bd459af12c7d1dd0' then
    raise exception 'Writer de agenda cambió bajo la entrevista automatica';
  end if;
  return 'OK: nucleo privado, puerta unica y una sola transaccion para cita y entrevista';
end;
$function$;
comment on function private.assert_entrevista_al_asistir() is
  'Trinquete de la entrevista automática: núcleo privado sin ningún rol, puerta expuesta solo a authenticated, y writer de agenda sellado sin cambios.';
revoke all on function private.assert_entrevista_al_asistir()
  from public, anon, authenticated, service_role;

do $postflight$
begin
  perform private.assert_entrevista_al_asistir();
  -- Los gates del mundo SLA, que es el que esta migración toca. Los otros
  -- cuatro controles del servidor (auditoría, analítica de leads/citas,
  -- vigencia de analistas y piezas F7) están en ROJO en producción desde antes
  -- de este cambio y por trabajos ajenos a él; llamarlos aquí abortaría una
  -- migración que no los empeora ni los arregla.
  perform private.assert_sla_nucleo();
  perform private.assert_sla_operacion();
  perform private.assert_sla_comandos();
  perform private.assert_sla_avisos();
end;
$postflight$;

notify pgrst, 'reload schema';
commit;

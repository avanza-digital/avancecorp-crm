-- Devolver un lead a la cola CANCELA sus tareas pendientes y RETROCEDE su etapa.
--
-- Decisión de Miguel (2026-08-09): opción B del conflicto documentado en el
-- vault «Conflicto re-encolado vs destino efectivo (2026-08-08)», y la etapa
-- sigue la MISMA regla que ya usa anular una reunión.
--
-- EL PROBLEMA. Dos triggers correctos por separado chocaban, y el resultado
-- estaba EN PRODUCCIÓN desde el 2026-08-08:
--   1. `private.trg_leads_sync_tareas` — al cambiar la tenencia de un lead, sus
--      tareas PENDIENTES espejan al nuevo dueño.
--   2. `private.trg_tareas_destino_efectivo` (metas/SLA versionados) — una tarea
--      pendiente y activa NO puede quedarse sin destino (23514), para nadie, ni
--      siquiera service_role.
-- Al devolver un lead a la cola global su tenencia queda en NULL, el sync
-- espejaba ese NULL sobre la tarea y el destino efectivo abortaba TODO el update
-- del lead. Efecto real: **un lead con una cita agendada no se podía devolver a
-- la cola**, y quien lo intentaba recibía un 23514 crudo.
--
-- PARTE 1 — CANCELAR. El propio trigger YA SABE cancelar: lo hace en
-- convertido/descartado/inactivo con el flag `crm.cancela_sistema`, que
-- `private.trg_tareas_before_update` reconoce para sellar `cancelada_por =
-- 'sistema'` con `cancelada_por_id` NULL. El re-encolado pasa a comportarse
-- igual. No se inventa mecanismo: se extiende el que ya existe al caso que
-- faltaba.
--
-- PARTE 2 — RETROCEDER LA ETAPA (hallazgo del auditor-rls, 2026-08-09).
-- Cancelar sin más dejaba al lead volviendo a la cola con `etapa =
-- 'reunion_agendada'` y CERO reuniones vivas. La doctrina de
-- `20260726151751_crm_anular_autoria_y_retroceso_reunion` es explícita:
-- «sostener reunion_agendada sin reunión viva no conserva un hecho, sostiene
-- uno falso, y el más caro». Sin esta parte, el coordinador repartiría un lead
-- que AFIRMA tener cita y no la tiene, el nuevo dueño heredaría un dato falso,
-- el SLA usaría la ventana de `reunion_agendada` y el embudo lo contaría como
-- reunión pendiente.
--
-- No se pudo reutilizar `private.retroceso_por_anular_reunion` por dos motivos
-- verificados contra prod: (a) solo la llaman las RPC HUMANAS `crm.cerrar_tarea`
-- y `crm.cerrar_reunion`, así que una cancelación por trigger se la salta; y (b)
-- exige `coalesce(vendedor_id, asignado_supervisor_id) is not null`, y en el
-- re-encolado la tenencia YA es NULL cuando corre el sync. Se replica su regla
-- exacta —`contactado` si hay contacto registrado en el ciclo, `nuevo` si no; y
-- no retrocede si ya hubo `reunion_realizada`— con el mismo flag
-- `crm.avance_auto`, que `private.trg_leads_cambio_etapa` consulta para marcar
-- el cambio como `automatico: true` en vez de imputárselo a una persona.
--
-- RE-ENTRADA, analizada: el UPDATE de la etapa vuelve a disparar este mismo
-- trigger. Segunda pasada: la tenencia NO cambia (NULL → NULL) ⇒ el primer `if`
-- es falso; la etapa nueva (`contactado`/`nuevo`) no está en
-- ('convertido','descartado') y `activo` no baja ⇒ el segundo `if` también es
-- falso ⇒ `return null`. Termina en la segunda pasada, sin recursión.
--
-- ALCANCE PRECISO — solo el re-encolado REAL:
--   · vendedor y supervisor pasan AMBOS a NULL → cancela y retrocede.
--   · bajar de bandeja a vendedor, subir de vendedor a bandeja o cambiar de
--     bandeja → sigue ESPEJANDO como hasta hoy. En particular `vendedor_id =
--     NULL` con `asignado_supervisor_id` intacto NO es un re-encolado: es
--     devolver el lead a la bandeja del supervisor, y ahí la tarea debe
--     seguirlo, no morir.
--
-- Estado en prod al aplicar: 1 lead, 0 tareas. El cambio no puede alterar
-- ningún dato existente; llega ANTES de que haya volumen, que es cuando este
-- conflicto empezaría a morder.
--
-- No contiene statements sobre objetos de `public`.

begin;

set local lock_timeout = '10s';

do $preflight$
declare
  v_hash text;
begin
  if to_regprocedure('private.trg_leads_sync_tareas()') is null
     or to_regprocedure('private.trg_tareas_destino_efectivo()') is null
     or to_regprocedure('private.trg_tareas_before_update()') is null
     or to_regprocedure('private.trg_leads_cambio_etapa()') is null
     or to_regprocedure('private.inicio_ciclo_lead(uuid)') is null
     or to_regclass('crm.tareas') is null
     or to_regclass('crm.leads') is null
     or to_regclass('crm.actividades') is null then
    raise exception 'Falta una dependencia del sync de tareas o del retroceso de etapa';
  end if;

  -- GUARDA DE FIDELIDAD DE DOS HASHES. El cuerpo nuevo es el de prod más las
  -- dos partes, así que un reemplazo a ciegas revertiría en silencio cualquier
  -- cambio posterior. Se distinguen los DOS estados legítimos:
  --   · PRE  = el cuerpo auditado de prod          → aplicar;
  --   · POST = exactamente el cuerpo de ESTA migración → ya aplicada, salir.
  -- Cualquier otro md5 aborta. No basta con detectar la palabra «RE-ENCOLADO»
  -- en el cuerpo: un cambio futuro que la conservara pasaría por «ya aplicada»
  -- y este CREATE OR REPLACE —que vive FUERA del bloque— lo pisaría sin avisar,
  -- que es justo lo que esta guarda existe para impedir.
  select md5(pg_get_functiondef('private.trg_leads_sync_tareas()'::regprocedure))
    into v_hash;
  if v_hash = '6874c23294da0027f25475b4e1fc49d7' then
    raise notice 'private.trg_leads_sync_tareas ya tiene la rama de re-encolado; reaplicacion identica';
  elsif v_hash <> 'b10c9f95e44e5ea3a58021b67967b4dd' then
    raise exception 'private.trg_leads_sync_tareas cambio en prod desde la auditoria (md5 %); re-auditar antes de aplicar', v_hash;
  end if;

  -- Premisas que hacen posible la corrección (hallazgo del auditor-rls):
  --  · sin `trg_tareas_00_before_update`, el update de cancelación caería en
  --    «Anular una tarea va por crm.cerrar_tarea()» (22023) y el re-encolado
  --    seguiría roto, con otro error;
  --  · sin `trg_leads_zz_sync_tareas` vivo, esta migración es un no-op silencioso
  --    y el re-encolado «funcionaría» por la razón equivocada;
  --  · sin `trg_tareas_01_destino_efectivo_update`, la premisa entera desaparece:
  --    estaríamos cancelando citas que se podían haber espejado.
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'crm' and c.relname = 'tareas'
      and t.tgname = 'trg_tareas_00_before_update' and t.tgenabled <> 'D'
  ) then
    raise exception 'trg_tareas_00_before_update ausente o deshabilitado: la cancelacion por sistema no funcionaria';
  end if;
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'crm' and c.relname = 'tareas'
      and t.tgname = 'trg_tareas_01_destino_efectivo_update' and t.tgenabled <> 'D'
  ) then
    raise exception 'trg_tareas_01_destino_efectivo_update ausente o deshabilitado: desaparece la premisa de esta correccion';
  end if;
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'crm' and c.relname = 'leads'
      and t.tgname = 'trg_leads_zz_sync_tareas' and t.tgenabled <> 'D'
  ) then
    raise exception 'trg_leads_zz_sync_tareas ausente o deshabilitado: esta migracion seria un no-op silencioso';
  end if;
end;
$preflight$;

create or replace function private.trg_leads_sync_tareas()
returns trigger
language plpgsql
security definer
set search_path to 'crm', 'private', 'public'
as $function$
declare
  -- «Quien lo enciende, lo apaga» — el mismo invariante que sostiene
  -- private.retroceso_por_anular_reunion. Apagar a ciegas dejaría a un llamador
  -- externo sin su flag a media operación. Hoy es inalcanzable (los tres
  -- escritores de crm.avance_auto mueven la etapa, nunca la tenencia, así que
  -- no llegan hasta aquí), pero el contrato no debe depender de eso.
  v_avance_previo text := coalesce(current_setting('crm.avance_auto', true), 'off');
begin
  if (new.vendedor_id is distinct from old.vendedor_id)
     or (new.asignado_supervisor_id is distinct from old.asignado_supervisor_id) then
    if new.vendedor_id is null and new.asignado_supervisor_id is null then
      -- RE-ENCOLADO (2026-08-09, opción B de Miguel): el lead vuelve a la cola
      -- global y se queda SIN dueño. Espejar esa tenencia nula sobre la tarea
      -- pendiente disparaba 23514 en trg_tareas_destino_efectivo y abortaba el
      -- re-encolado entero. Se cancela por sistema, igual que en
      -- convertido/descartado; la tarea conserva su bandeja anterior como
      -- historia y `cancelada_por` queda sellado en 'sistema'.
      perform set_config('crm.cancela_sistema', 'on', true);
      update crm.tareas t
         set estado = 'cancelada'
       where t.lead_id = new.id and t.estado = 'pendiente';
      perform set_config('crm.cancela_sistema', 'off', true);

      -- Y el lead no puede volver a la cola SOSTENIENDO una reunión que se
      -- acaba de cancelar: sería el «hecho falso más caro» de la doctrina de
      -- 20260726151751. Misma regla que anular una reunión —`contactado` si hay
      -- contacto en el ciclo, `nuevo` si no— porque
      -- private.retroceso_por_anular_reunion no sirve aquí: solo la llaman las
      -- RPC humanas y exige tenencia no nula, que a esta altura ya es NULL.
      -- `crm.avance_auto` hace que trg_leads_cambio_etapa lo registre como
      -- automatico en vez de imputárselo a la persona que re-encoló.
      --
      -- DOS CASOS QUE A PROPOSITO NO RETROCEDEN (auditor-rls, 2026-08-09):
      --  · si YA hubo `reunion_realizada` en el ciclo, la etapa se sostiene en
      --    un hecho verdadero y la doctrina manda conservarla. Queda el residuo
      --    de que el lead llega a la cola global en `reunion_agendada` sin cita
      --    viva; cambiarlo seria cambiar la doctrina, y eso pasa por Miguel.
      --  · un lead YA inactivo que se re-encola despues (solo alcanzable por
      --    service_role sobre un soft-borrado): el filtro `l.activo = true`
      --    lo deja quieto, igual que en anular reunion.
      if new.etapa = 'reunion_agendada'
         and new.activo = true
         and not exists (
           select 1
           from crm.actividades a
           where a.lead_id = new.id
             and a.tipo = 'reunion_realizada'
             and a.creado_en >= private.inicio_ciclo_lead(new.id)
         ) then
        perform set_config('crm.avance_auto', 'on', true);
        update crm.leads l
           set etapa = case
                 when exists (
                   select 1
                   from crm.actividades a
                   where a.lead_id = l.id
                     and a.tipo in ('llamada_realizada','llamada_no_contestada',
                                    'whatsapp_enviado','whatsapp_recibido',
                                    'reunion_realizada')
                     and a.creado_en >= private.inicio_ciclo_lead(l.id)
                 ) then 'contactado'
                 else 'nuevo'
               end
         where l.id = new.id
           and l.activo = true
           and l.etapa = 'reunion_agendada';
        perform set_config('crm.avance_auto', v_avance_previo, true);
      end if;
    else
      -- Reasignacion / reparto de parkeado: propaga tenencia a las PENDIENTES.
      -- Cubre bajar a un vendedor, subir a la bandeja del supervisor y cambiar
      -- de bandeja. La tarea SIGUE al lead; no muere.
      update crm.tareas t
         set vendedor_id = new.vendedor_id,
             asignado_supervisor_id = new.asignado_supervisor_id
       where t.lead_id = new.id and t.estado = 'pendiente';
    end if;
  end if;
  -- Cierre o soft-delete del lead: cancela las pendientes. Esto NO es gestión
  -- del asesor, por eso va sellado como sistema.
  if (new.etapa in ('convertido','descartado') and old.etapa not in ('convertido','descartado'))
     or (old.activo = true and new.activo = false) then
    perform set_config('crm.cancela_sistema', 'on', true);
    update crm.tareas t
       set estado = 'cancelada'
     where t.lead_id = new.id and t.estado = 'pendiente';
    perform set_config('crm.cancela_sistema', 'off', true);
  end if;
  return null;
end;
$function$;

comment on function private.trg_leads_sync_tareas() is
  'Las tareas pendientes siguen la tenencia del lead. Re-encolar (vendedor y supervisor a NULL) las CANCELA por sistema y ademas retrocede la etapa desde reunion_agendada a contactado/nuevo, con la misma regla que anular una reunion: espejar destino nulo abortaba el re-encolado con 23514, y volver a la cola sosteniendo una reunion cancelada seria un hecho falso (decision de Miguel 2026-08-09). Convertido/descartado/inactivo cancelan como siempre.';

commit;

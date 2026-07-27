-- ============================================================================
-- CRM · La anulación que ordena OTRO no le baja la nota al vendedor
--
-- Pedido de Miguel (2026-07-26, cerrando la decisión que quedó ABIERTA al
-- desplegar 20260726151751): «si el supervisor anula una tarea el vendedor no
-- debería poder hacer nada sobre esa tarea». La mitad literal ya estaba: una
-- tarea cerrada es inmutable (`trg_tareas_00_before_update` aborta cualquier
-- UPDATE) y ni siquiera viaja al navegador (`listarTareasDelAmbito` filtra
-- `estado='pendiente'`). Lo que faltaba es la consecuencia: si no tuvo control
-- sobre ella, esa tarea no puede pesar en su % de cumplimiento.
--
-- ▶ QUÉ FALTABA, EXACTAMENTE. 20260726151751 separó CÓMO entró la cancelación
--   (`cancelada_por` = 'asesor' | 'sistema') y sacó las del sistema del
--   denominador de `pct_completadas`. Pero 'asesor' dice que la ordenó UNA
--   PERSONA, no CUÁL: las filas se agrupan por `vendedor_id`, así que un
--   supervisor —o gerencia— anulando la tarea de su vendedor le bajaba el % a
--   ÉL. El propio comentario de columna lo dejó anotado como límite conocido
--   ("dice CÓMO entró la cancelación, no QUIÉN la firmó"); esta migración lo
--   levanta y reescribe ese comentario para que no siga afirmando un límite
--   que ya no existe.
--
-- ▶ LA REGLA, EN UNA LÍNEA: una anulación pesa en el % de alguien SOLO si se
--   puede AFIRMAR que la ordenó esa misma persona. Todo lo demás —el sistema,
--   el jefe, o un autor que no se puede determinar— queda fuera del
--   denominador. Una sola regla, cero casos especiales, y falla siempre hacia
--   el lado que no castiga a quien no decidió.
--
-- ▶ POR QUÉ UNA COLUMNA Y NO UN TERCER VALOR EN `cancelada_por`. Un
--   'supervisor' junto a 'asesor'/'sistema' obligaría a recalcular la etiqueta
--   cada vez que el lead cambia de dueño: la misma anulación sería "propia" o
--   "ajena" según quién tenga el lead HOY. Guardar el uuid de quien firmó
--   congela el hecho; "propia o ajena" se deriva comparándolo con el
--   `vendedor_id` de la fila, que es justo el eje por el que agrupa la métrica.
--
-- ▶ SIN CLAVE FORÁNEA A `public.perfiles`, a propósito, y NO por la regla de
--   "no tocar public" (el hermano `crm.tareas.creado_por` sí la tiene, así que
--   el precedente existe). La razón es la métrica: con `on delete set null`,
--   borrar el perfil de un supervisor vaciaría su firma y MOVERÍA hacia atrás
--   el % de un vendedor que no hizo nada — un número histórico cambiando solo
--   porque alguien se dio de baja. La integridad no se pierde: el valor lo
--   sella el trigger desde `auth.uid()`, nunca llega del payload, así que no
--   puede haber un uuid inventado. Aquí `public` solo se LEE (el backfill).
--
-- Requiere `npm run gen:types` en app/ (columna nueva) DESPUÉS de aplicar.
-- ============================================================================

begin;

set local lock_timeout = '5s';

-- ── 1. La columna: QUIÉN firmó la anulación ──────────────────────────────────
alter table crm.tareas add column cancelada_por_id uuid;

-- BACKFILL DESDE EL HISTORIAL, con los tres triggers que estorban apagados uno
-- por uno y POR SU NOMBRE (mismo criterio que 20260726151751: `disable trigger
-- user` no RESTAURA el estado previo, lo FIJA en 'O'). Las tres razones son las
-- mismas de entonces y siguen vigentes:
--   a) `trg_tareas_00_before_update` aborta cualquier update sobre una tarea ya
--      cerrada — sin apagarlo el backfill ni corre.
--   b) `trg_tareas_touch` movería `actualizado_en`, que es EXACTAMENTE el campo
--      por el que `crm.metricas_agenda_fn` atribuye los cierres a un periodo:
--      cada anulación histórica saltaría al mes en curso.
--   c) `log_audit_crm` escribiría un evento de negocio que no ocurrió.
-- El `add column` de arriba ya tomó ACCESS EXCLUSIVE y lo sostiene hasta el
-- commit, así que no hay ventana concurrente; y el begin/commit revierte
-- también los `disable` si algo falla.
--
-- En producción esto atribuye 3 filas (verificado 2026-07-26: las tres las
-- anuló MIGUEL BRICEÑO sobre SUS PROPIAS tareas, o sea que quedan "propias" y
-- el % de nadie se mueve hacia atrás). Es el motivo de recuperarlo del
-- historial en vez de asumir: asumir habría acertado aquí por casualidad.
alter table crm.tareas disable trigger trg_tareas_00_before_update;
alter table crm.tareas disable trigger trg_tareas_touch;
alter table crm.tareas disable trigger trg_audit_tareas;

-- GUARDA DE ENTORNO: `public.audit_log` la crea el PORTAL, no este repo (aquí
-- solo se inserta en ella desde `private.log_audit_crm`). Un branch de Supabase
-- levantado sin las migraciones del portal no la tendría y el UPDATE de abajo
-- reventaría la migración entera por una atribución que en ese entorno afecta a
-- 0 filas. plpgsql resuelve los nombres de tabla al EJECUTAR, no al crear el
-- bloque, así que si la rama no entra el UPDATE ni se parsea.
do $backfill$
begin
  if to_regclass('public.audit_log') is null then
    raise notice 'public.audit_log ausente: 0 anulaciones que atribuir';
    return;
  end if;
  -- `distinct on` + `order by ts` toma la PRIMERA transición a cancelada. Hoy
  -- solo puede haber una (cerrar es terminal), pero apoyarse en esa invariante
  -- para que el UPDATE sea determinista sale gratis y no depende de ella.
  --
  -- TIPOS DE `public.audit_log`, VERIFICADOS CONTRA PROD 2026-07-26 (A2 de la
  -- auditoría, que los pedía porque el DDL de esa tabla vive en el portal y no
  -- en este repo): `usuario_id` es **uuid** y `fila_id` es **text**. Por eso la
  -- asignación a `cancelada_por_id` va sin cast (uuid→uuid) y la comparación de
  -- abajo sí lleva `t.id::text` (text=uuid no tiene operador). Si algún día el
  -- portal cambia esos tipos, esta migración falla RUIDOSAMENTE y dentro de la
  -- transacción — no deja estado a medias.
  update crm.tareas t
     set cancelada_por_id = sub.usuario_id
    from (
      select distinct on (al.fila_id) al.fila_id, al.usuario_id
        from public.audit_log al
       where al.tabla = 'crm.tareas'
         and al.operacion = 'UPDATE'
         and (al.data_despues->>'estado') = 'cancelada'
         and (al.data_antes->>'estado') is distinct from 'cancelada'
         and al.usuario_id is not null
       order by al.fila_id, al.ts
    ) sub
   where t.estado = 'cancelada'
     and t.cancelada_por = 'asesor'
     and sub.fila_id = t.id::text;
end
$backfill$;

alter table crm.tareas enable trigger trg_tareas_00_before_update;
alter table crm.tareas enable trigger trg_tareas_touch;
alter table crm.tareas enable trigger trg_audit_tareas;

-- CASE Y NO `or`, por la trampa que costó una ronda de auditoría en la
-- migración anterior: `cancelada_por = 'asesor'` con la columna a null evalúa a
-- NULL, y un CHECK solo se viola con FALSE — un `check (cancelada_por =
-- 'asesor' or cancelada_por_id is null)` dejaría entrar una firma en una fila
-- que no está cancelada. Con CASE, el WHEN que da NULL cae al ELSE, que sí
-- exige la columna vacía. Verificado abajo por el oráculo, no por confianza.
--
-- DELIBERADAMENTE PERMISIVO en la otra mitad: 'asesor' NO exige firma. Para las
-- filas NUEVAS la firma está garantizada por construcción (el trigger solo pone
-- 'asesor' en la rama donde `v_uid is not null`, y ahí escribe ese mismo uid),
-- así que el hueco solo cubre historia inatribuible. Prohibirlo convertiría una
-- laguna del pasado en una migración que no aplica; permitirlo la deja caer,
-- por la regla de arriba, del lado que no castiga al vendedor.
alter table crm.tareas
  add constraint tareas_cancelada_por_id_valida
  check (
    case
      when cancelada_por = 'asesor' then true
      else cancelada_por_id is null
    end
  );

comment on column crm.tareas.cancelada_por_id is
  'QUIÉN firmó la anulación: el perfil con sesión que llamó a crm.cerrar_tarea(). Sellada por los BEFORE triggers (jamás llega del payload), null cuando cancelada_por = ''sistema'' porque ahí no hay persona a la que atribuir. Se compara contra vendedor_id para saber si la anulación fue PROPIA (pesa en el % de esa persona) o AJENA — el jefe anulándole la tarea a su vendedor — que NO pesa. Sin FK a public.perfiles a propósito: con on delete set null, dar de baja a un supervisor reescribiría hacia atrás el % de sus vendedores.';

comment on column crm.tareas.cancelada_por is
  'Autoría de la cancelación, sellada por los BEFORE triggers (el cliente nunca la escribe, ni en INSERT ni en UPDATE). asesor = una PERSONA con sesión la anuló por crm.cerrar_tarea() porque ya no hacía falta. sistema = la canceló private.trg_leads_sync_tareas al convertirse/descartarse/darse de baja el lead, o un proceso sin sesión (service_role, seeds, cron). Dice CÓMO entró la cancelación; QUIÉN la firmó vive desde 20260727 en cancelada_por_id. En el denominador de pct_completadas solo entran las de asesor firmadas por el PROPIO vendedor de la tarea: las del sistema y las que ordena un tercero (supervisor o gerencia) quedan fuera — decisión de Miguel, 2026-07-26.';

-- SIN ÍNDICE NUEVO, por el mismo motivo que la columna hermana: el CTE
-- `cierres` ya escanea las filas acotado por `actualizado_en` y los desgloses
-- salen de `count(*) filter` sobre filas YA leídas. Nacería como unused index.

-- ── 2. El sello: una sola decisión, dos columnas ─────────────────────────────
-- Cuerpo VERBATIM de producción (prosrc verificado 2026-07-26) con el bloque de
-- autoría reescrito. El `case` de `cancelada_por` y el de `cancelada_por_id`
-- salían del mismo criterio y podían divergir en un futuro edit; ahora los dos
-- se derivan de UN booleano, así que "etiquetada como asesor pero sin firma" —
-- o al revés — deja de ser expresable.
create or replace function private.trg_tareas_before_update()
returns trigger
language plpgsql
security definer
set search_path = crm, private, public
as $$
declare
  v_op      boolean := coalesce(current_setting('crm.op_tarea', true), 'off') = 'on';
  v_sistema boolean := coalesce(current_setting('crm.cancela_sistema', true), 'off') = 'on';
  v_uid     uuid    := (select auth.uid());
  v_asesor  boolean;
begin
  if old.estado <> 'pendiente' then
    raise exception 'La tarea ya esta cerrada; reagendar crea una tarea nueva';
  end if;
  if new.estado in ('completada','no_show') and not v_op then
    raise exception 'Completar o marcar no-show va por crm.cerrar_tarea()';
  end if;
  if new.estado = 'cancelada' and not v_op and not v_sistema and v_uid is not null then
    raise exception 'Anular una tarea va por crm.cerrar_tarea()';
  end if;
  if new.resultado_actividad_id is distinct from old.resultado_actividad_id and not v_op then
    raise exception 'El resultado lo escribe crm.cerrar_tarea()';
  end if;
  -- La autoría la deriva el servidor de CÓMO entró la escritura, jamás del
  -- payload. `crm.cancela_sistema` gana sobre `crm.op_tarea` porque el
  -- bookkeeping de un lead cerrado puede correr dentro de la misma transacción
  -- en la que la RPC dejó su flag encendido.
  -- ⚠️ SI AÑADES OTRO ESCRITOR DE `crm.op_tarea` QUE CANCELE, replica en él la
  -- llamada a `private.retroceso_por_anular_reunion`: hoy el retroceso vive
  -- INLINE en crm.cerrar_tarea (único sitio del repo que enciende este flag).
  if new.estado = 'cancelada' then
    v_asesor := (not v_sistema) and v_op and v_uid is not null;
    new.cancelada_por    := case when v_asesor then 'asesor' else 'sistema' end;
    new.cancelada_por_id := case when v_asesor then v_uid   else null     end;
  else
    -- old.estado es 'pendiente' por el primer raise, luego las dos columnas de
    -- old son null: esta rama impide que el cliente inyecte etiqueta o firma.
    new.cancelada_por    := old.cancelada_por;
    new.cancelada_por_id := old.cancelada_por_id;
  end if;
  -- Trazabilidad inmutable (mismo criterio que leads): el origen no se reescribe.
  new.creado_por := old.creado_por;
  new.creado_en  := old.creado_en;
  new.lead_id    := old.lead_id;
  new.perfil_id  := old.perfil_id;
  new.reagendada_de := old.reagendada_de;
  -- Contador de sistema: reprogramar = cambiar la fecha de una pendiente.
  if new.vence_en is distinct from old.vence_en then
    new.reprogramaciones := old.reprogramaciones + 1;
  else
    new.reprogramaciones := old.reprogramaciones;
  end if;
  return new;
end;
$$;

-- ── 3. El mismo sello en INSERT ──────────────────────────────────────────────
-- Cuerpo VERBATIM de 20260726151751 + la línea de la firma. Una tarea que nace
-- cancelada es de sistema por definición, así que tampoco tiene a quién
-- atribuirse. La línea hace falta igual: el GRANT de `crm.tareas` es de TABLA,
-- así que `authenticated` puede mandar `cancelada_por_id` en el payload de un
-- INSERT. El CHECK lo atraparía —una tarea que nace pendiente con firma lo
-- viola— pero el cliente recibiría un 400 de constraint en vez de que el campo
-- se ignore, que es el contrato de todas las demás columnas selladas. Ponerlo a
-- null explícitamente lo convierte en lo segundo.
create or replace function private.trg_tareas_before_insert()
returns trigger
language plpgsql
security definer
set search_path = crm, private, public
as $$
declare
  v_lead crm.leads%rowtype;
begin
  if new.lead_id is not null then
    select * into v_lead from crm.leads where id = new.lead_id;
    if not found then
      raise exception 'El lead de la tarea no existe';
    end if;
    if v_lead.activo = false or v_lead.etapa in ('convertido','descartado') then
      raise exception 'El lead esta cerrado: no admite tareas nuevas';
    end if;
    new.vendedor_id := v_lead.vendedor_id;
    new.asignado_supervisor_id := v_lead.asignado_supervisor_id;
  end if;
  -- Nacer cerrada solo con el flag privilegiado (RPC/seed), nunca desde el cliente.
  if new.estado <> 'pendiente'
     and coalesce(current_setting('crm.op_tarea', true), 'off') <> 'on' then
    raise exception 'Una tarea nace pendiente; los cierres van por crm.cerrar_tarea()';
  end if;
  -- La autoría tampoco entra por el payload al nacer. Una tarea que nace
  -- cancelada es por definición de sistema: no hay asesor que haya decidido
  -- nada sobre una tarea que nunca estuvo viva, y por tanto tampoco firma.
  new.cancelada_por := case when new.estado = 'cancelada' then 'sistema' else null end;
  new.cancelada_por_id := null;
  return new;
end;
$$;

-- ── 4. La métrica deja de cobrarle al vendedor lo que decidió su jefe ────────
-- Cuerpo VERBATIM de 20260726151751 con UN cambio, en el CTE `cierres` y su
-- consumo:
--
--   a) `canceladas_asesor` NO cambia de significado (sigue siendo "las que
--      ordenó una persona") y se le suma `canceladas_ajenas` como clave NUEVA.
--
--      ⚠️ ORDEN DE DESPLIEGUE OBLIGATORIO: **FRONT PRIMERO, MIGRACIÓN DESPUÉS.**
--      Aditivo lo es en el SERVIDOR, pero el contrato del front es
--      `v.strictObject` (app/src/lib/metricas-agenda.ts): `v.optional` solo
--      aplica a claves DECLARADAS, y una clave que el esquema NO conoce hace
--      fallar la validación ENTERA — el propio comentario de ese archivo lo
--      dice. Con el front viejo desplegado, esta clave no degrada el panel
--      «Agenda del equipo»: lo MATA, para supervisor y gerencia.
--      El orden inverso sí es seguro: front nuevo + BD vieja = clave ausente =
--      opcional = panel en pie. Lo detectó `auditor-rls` (A1) y corrige de paso
--      una afirmación falsa que 20260726151751 dejó escrita en su ledger
--      ("ninguno de los dos órdenes rompe el panel"): allí se ACERTÓ el orden,
--      no se garantizó.
--
--   b) EL DENOMINADOR DE pct_completadas PASA A `canceladas_propias` — las que
--      firmó el propio vendedor de la tarea. Las que ordenó un tercero salen,
--      por la decisión de Miguel del 2026-07-26. Las propias SIGUEN contando:
--      anular lo tuyo es una decisión sobre tu propia agenda, y sacarlas
--      convertiría el botón en una salida gratis para no hacer nada.
--
-- `is distinct from` y no `<>`: en este CTE `vendedor_id` nunca es null (lo
-- filtra el WHERE), pero `cancelada_por_id` SÍ puede serlo en la historia
-- inatribuible del backfill — y con `<>` esas filas se caerían de las DOS
-- cuentas, dejando `propias + ajenas < canceladas_asesor` sin que nada avise.
-- Así las dos mitades siempre suman el total, que es lo que hace la métrica
-- auditable de un vistazo.
--
-- `version` sigue en 1: la clave nueva es ADITIVA.
create or replace function crm.metricas_agenda_fn(p_desde date, p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_es_lector boolean;
  v_miembro_activo boolean;
  v_hoy_lima date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_ahora timestamptz := pg_catalog.now();
  v_dias integer;
  v_payload jsonb;
begin
  if v_uid is null then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- Gate fail-closed: miembro ACTIVO de crm.equipo (con perfil activo) y con
  -- ROL OPERATIVO, o lector global. El coordinador (C1) queda excluido: no
  -- lleva cartera ni supervisa, su ámbito de agenda es ∅ por definición.
  select exists (
    select 1
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.perfil_id = v_uid and e.activo and p.activo
      and e.rol_crm in ('vendedor','supervisor','gerencia')
  ) into v_miembro_activo;

  v_es_lector := private.es_lector_global();

  if not v_miembro_activo and not v_es_lector then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- Validación de periodo (mismas reglas que metricas_distribucion):
  if p_desde is null or p_hasta is null then
    raise exception 'Periodo invalido: desde y hasta son obligatorios' using errcode = '22023';
  end if;
  if p_desde > p_hasta then
    raise exception 'Periodo invalido: desde no puede ser posterior a hasta' using errcode = '22023';
  end if;
  if p_hasta > v_hoy_lima then
    raise exception 'Periodo invalido: hasta no puede ser futuro' using errcode = '22023';
  end if;
  if p_hasta - p_desde > 365 then
    raise exception 'Periodo invalido: maximo 366 dias' using errcode = '22023';
  end if;

  v_ini := (p_desde::timestamp) at time zone 'America/Lima';
  v_fin := ((p_hasta + 1)::timestamp) at time zone 'America/Lima';
  v_dias := (p_hasta - p_desde) + 1;

  with visibles as (
    -- Miembros del ámbito del caller con cartera propia posible (vendedor o
    -- supervisor; gerencia no lleva cartera). Lector global ve a todos.
    select e.perfil_id, p.nombre_completo, e.rol_crm, e.activo
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.rol_crm in ('vendedor', 'supervisor')
      and (
        v_es_lector
        or e.perfil_id in (select private.vendedor_ids_visibles(v_uid))
      )
  ),
  toques as (
    select
      a.creado_por as perfil_id,
      count(*) filter (
        where a.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')
      ) as n_toques,
      count(*) filter (where a.tipo = 'reunion_realizada') as n_reuniones_realizadas
    from crm.actividades a
    where a.creado_por is not null
      and a.creado_en >= v_ini and a.creado_en < v_fin
    group by a.creado_por
  ),
  cierres as (
    select
      t.vendedor_id as perfil_id,
      count(*) filter (where t.estado = 'completada') as n_completadas,
      count(*) filter (where t.estado = 'no_show') as n_no_asistio,
      count(*) filter (where t.estado = 'cancelada') as n_canceladas,
      -- `is distinct from` y no `= 'sistema'`: cinturón y tirantes. El CHECK
      -- bicondicional ya prohíbe una cancelada sin etiqueta, pero si alguna vez
      -- se relajara, esta forma la deja del lado que NO castiga al vendedor.
      count(*) filter (where t.estado = 'cancelada' and t.cancelada_por = 'asesor') as n_canceladas_asesor,
      count(*) filter (where t.estado = 'cancelada' and t.cancelada_por is distinct from 'asesor') as n_canceladas_sistema,
      -- Las dos mitades de `n_canceladas_asesor`, complementarias por
      -- construcción: la firma o coincide con el dueño de la tarea o no.
      count(*) filter (
        where t.estado = 'cancelada'
          and t.cancelada_por = 'asesor'
          and t.cancelada_por_id is not distinct from t.vendedor_id
      ) as n_canceladas_propias,
      count(*) filter (
        where t.estado = 'cancelada'
          and t.cancelada_por = 'asesor'
          and t.cancelada_por_id is distinct from t.vendedor_id
      ) as n_canceladas_ajenas
    from crm.tareas t
    where t.vendedor_id is not null
      and t.estado in ('completada','no_show','cancelada')
      and t.actualizado_en >= v_ini and t.actualizado_en < v_fin
    group by t.vendedor_id
  ),
  creadas as (
    select
      t.vendedor_id as perfil_id,
      count(*) as n_creadas,
      count(*) filter (where t.tipo = 'reunion') as n_reuniones_agendadas
    from crm.tareas t
    where t.vendedor_id is not null
      and t.creado_en >= v_ini and t.creado_en < v_fin
    group by t.vendedor_id
  ),
  movidas as (
    select
      t.vendedor_id as perfil_id,
      coalesce(sum(t.reprogramaciones), 0) as n_reprogramaciones
    from crm.tareas t
    where t.vendedor_id is not null
      and t.reprogramaciones > 0
      and t.actualizado_en >= v_ini and t.actualizado_en < v_fin
    group by t.vendedor_id
  ),
  foto as (
    select
      t.vendedor_id as perfil_id,
      count(*) filter (where t.estado = 'pendiente' and t.activo) as n_pendientes,
      count(*) filter (where t.estado = 'pendiente' and t.activo and t.vence_en < v_ahora) as n_vencidas
    from crm.tareas t
    where t.vendedor_id is not null
    group by t.vendedor_id
  ),
  sin_accion as (
    -- El amarillo del semáforo, por vendedor: lead abierto con dueño y sin
    -- tarea pendiente (mismo criterio que sinProximaAccion del frontend).
    select l.vendedor_id as perfil_id, count(*) as n_sin_accion
    from crm.leads l
    where l.activo
      and l.vendedor_id is not null
      and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
      and not exists (
        select 1 from crm.tareas t
        where t.lead_id = l.id and t.estado = 'pendiente' and t.activo
      )
    group by l.vendedor_id
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'periodo', jsonb_build_object(
      'desde', p_desde, 'hasta', p_hasta, 'dias', v_dias, 'zona', 'America/Lima'
    ),
    'vendedores', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'vendedor_id', v.perfil_id,
            'nombre', v.nombre_completo,
            'rol', v.rol_crm,
            'activo', v.activo,
            'toques', coalesce(tq.n_toques, 0),
            'toques_por_dia', round(coalesce(tq.n_toques, 0)::numeric / v_dias, 1),
            'reuniones_realizadas', coalesce(tq.n_reuniones_realizadas, 0),
            'completadas', coalesce(c.n_completadas, 0),
            'no_asistio', coalesce(c.n_no_asistio, 0),
            'canceladas', coalesce(c.n_canceladas, 0),
            'canceladas_asesor', coalesce(c.n_canceladas_asesor, 0),
            'canceladas_sistema', coalesce(c.n_canceladas_sistema, 0),
            'canceladas_ajenas', coalesce(c.n_canceladas_ajenas, 0),
            'pct_completadas', case
              when coalesce(c.n_completadas, 0) + coalesce(c.n_no_asistio, 0) + coalesce(c.n_canceladas_propias, 0) > 0
              then round(
                100.0 * coalesce(c.n_completadas, 0)
                / (coalesce(c.n_completadas, 0) + coalesce(c.n_no_asistio, 0) + coalesce(c.n_canceladas_propias, 0))
              )
              else null
            end,
            'tareas_creadas', coalesce(cr.n_creadas, 0),
            'reuniones_agendadas', coalesce(cr.n_reuniones_agendadas, 0),
            'reprogramaciones', coalesce(m.n_reprogramaciones, 0),
            'pendientes', coalesce(f.n_pendientes, 0),
            'vencidas', coalesce(f.n_vencidas, 0),
            'leads_sin_accion', coalesce(sa.n_sin_accion, 0)
          )
          order by v.nombre_completo
        )
        from visibles v
        left join toques tq on tq.perfil_id = v.perfil_id
        left join cierres c on c.perfil_id = v.perfil_id
        left join creadas cr on cr.perfil_id = v.perfil_id
        left join movidas m on m.perfil_id = v.perfil_id
        left join foto f on f.perfil_id = v.perfil_id
        left join sin_accion sa on sa.perfil_id = v.perfil_id
      ),
      '[]'::jsonb
    )
  )
  into v_payload;

  return v_payload;
end;
$$;

commit;

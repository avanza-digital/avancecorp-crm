-- ============================================================================
-- CRM · Anular con AUTORÍA, y la reunión que se cae devuelve el lead a su etapa
--
-- Dos pedidos de Miguel (2026-07-26), textuales:
--   1. "si se anula la reu y no se reagenda una en ese mismo momento, debería
--       bajar de etapa"
--   2. "separa lo que cancela el sistema y lo que cancela el asesor"
--
-- Son la misma pieza: sin (2) no se puede hacer (1) con precisión. Hoy
-- `estado='cancelada'` mezcla dos hechos que no se parecen en nada:
--   · el ASESOR anuló la tarea porque ya no hacía falta (decisión comercial), y
--   · el SISTEMA la canceló sola porque el lead se convirtió, se descartó o se
--     dio de baja (`private.trg_leads_sync_tareas`, bookkeeping).
-- Distinguirlos habilita el retroceso —que debe ordenarlo SOLO una persona— y
-- de paso arregla un sesgo real de la métrica (ver § 6).
--
-- ▶ POR QUÉ EL RETROCESO NO ES UN TRIGGER (1ª auditoría, hallazgo M1)
--   La versión anterior lo colgaba de un AFTER UPDATE sobre `crm.tareas`. Falla
--   con `crm.cerrar_tarea(..., p_estado='cancelada', p_siguiente={reunion})`:
--   el trigger corre al terminar el UPDATE, o sea ANTES de que exista la
--   reunión nueva, así que ve "ninguna reunión viva", baja la etapa, y el
--   trigger de subida la vuelve a subir un statement después. Resultado: dos
--   `cambio_etapa` espurios por gesto en un log INMUTABLE (no se pueden
--   borrar) — y, en un lead que llegó a `reunion_agendada` a mano desde el
--   kanban sin ningún contacto registrado, la subida NI SIQUIERA lo devuelve
--   (exige `exists` de contacto real): anular-y-reagendar lo degradaba DOS
--   etapas. Aquí va INLINE al final de la RPC, después de insertar la
--   siguiente. No pierde cobertura: la etiqueta 'asesor' solo la puede poner
--   esta RPC, así que el trigger jamás podía dispararse desde otro sitio.
--   De regalo, el orden de bloqueo queda explícito y verificable en un solo
--   cuerpo (la RPC ya tomó el lead con `for no key update`, A1 de la migración
--   20260725060657), en vez de depender de una invariante no escrita.
--
-- ▶ GRANTS: `crm.tareas` tiene grants A NIVEL DE TABLA (no por columna como
--   `crm.leads`), así que la columna nueva queda visible para PostgREST sin
--   GRANT adicional. Que `authenticated` pueda mandarla en el payload es
--   inocuo: los BEFORE triggers la sobrescriben SIEMPRE, en INSERT y en UPDATE.
--
-- Requiere `npm run gen:types` en app/ (columna nueva) DESPUÉS de aplicar.
-- Auditada por `auditor-rls`: veredicto NO-GO → 1 alto (A1: el CHECK no
-- restringía nada, `NULL in (...)` es NULL y un CHECK solo se viola con FALSE —
-- confirmado ejecutándolo contra el motor), 4 medios y 3 bajos, todos
-- corregidos aquí. El detalle, en cada sección.
-- ============================================================================

begin;

-- ALTER TABLE toma ACCESS EXCLUSIVE sobre una tabla caliente: sin timeout esta
-- migración podría encolarse tras una transacción larga y congelar la agenda.
set local lock_timeout = '5s';

-- ── 1. La columna: quién canceló ─────────────────────────────────────────────
alter table crm.tareas add column cancelada_por text;

-- BACKFILL CON LOS TRES TRIGGERS QUE ESTORBAN APAGADOS, uno por uno y por su
-- nombre (M4 de la auditoría: `disable trigger user` no RESTAURA el estado
-- previo, lo FIJA en 'O' — cualquier trigger que estuviera en ENABLE ALWAYS o
-- REPLICA saldría cambiado en silencio, y apagaría 5 para esquivar 3).
-- Las tres razones para apagarlos:
--   a) `trg_tareas_00_before_update` aborta CUALQUIER update sobre una tarea ya
--      cerrada ("La tarea ya esta cerrada") — sin apagarlo el backfill ni corre.
--   b) `trg_tareas_touch` movería `actualizado_en`, que es EXACTAMENTE el campo
--      por el que `crm.metricas_agenda_fn` atribuye los cierres a un periodo:
--      cada cancelación histórica saltaría al mes en curso y falsearía el panel
--      de supervisión de golpe.
--   c) `log_audit_crm` escribiría un evento de negocio que no ocurrió: rellenar
--      una columna derivada no es que alguien haya cancelado algo hoy. Es una
--      excepción CONSCIENTE a "trigger de auditoría en toda tabla crm.*".
-- No hay ventana de seguridad: el `add column` de arriba ya tomó ACCESS
-- EXCLUSIVE y lo sostiene hasta el commit, así que ninguna sesión concurrente
-- puede escribir mientras tanto; y si algo falla, el `begin/commit` revierte
-- también los `disable`.
-- En producción hoy afecta a 0 filas (verificado 2026-07-26: 4 completadas,
-- 2 pendientes, 1 no_show, 0 canceladas) — el botón de anular todavía no se ha
-- desplegado, así que TODA cancelación preexistente en cualquier entorno es, por
-- construcción, del sistema.
alter table crm.tareas disable trigger trg_tareas_00_before_update;
alter table crm.tareas disable trigger trg_tareas_touch;
alter table crm.tareas disable trigger trg_audit_tareas;
update crm.tareas
   set cancelada_por = 'sistema'
 where estado = 'cancelada' and cancelada_por is null;
alter table crm.tareas enable trigger trg_tareas_00_before_update;
alter table crm.tareas enable trigger trg_tareas_touch;
alter table crm.tareas enable trigger trg_audit_tareas;

-- BICONDICIONAL DE VERDAD (A1 de la auditoría). La primera versión decía
--   `when estado = 'cancelada' then cancelada_por in ('asesor','sistema')`
-- y NO restringía nada por la mitad que importa: con la columna a null,
-- `null in ('asesor','sistema')` evalúa a NULL, y un CHECK solo se viola cuando
-- da FALSE — o sea que la fila "cancelada sin autor" entraba tan campante,
-- justo el estado que el comentario juraba imposible. El `is not null` explícito
-- es lo único que convierte esto en una garantía de la TABLA en vez de una
-- costumbre del código.
alter table crm.tareas
  add constraint tareas_cancelada_por_valida
  check (
    case
      when estado = 'cancelada'
        then cancelada_por is not null and cancelada_por in ('asesor','sistema')
      else cancelada_por is null
    end
  );

comment on column crm.tareas.cancelada_por is
  'Autoría de la cancelación, sellada por los BEFORE triggers (el cliente nunca la escribe, ni en INSERT ni en UPDATE). asesor = una PERSONA con sesión la anuló por crm.cerrar_tarea() porque ya no hacía falta. sistema = la canceló private.trg_leads_sync_tareas al convertirse/descartarse/darse de baja el lead, o un proceso sin sesión (service_role, seeds, cron). Solo las de asesor cuentan en el denominador de pct_completadas. OJO al leer la métrica: dice CÓMO entró la cancelación, no QUIÉN la firmó — un supervisor puede anular la tarea de su vendedor y la fila se agrupa igual por vendedor_id, como el resto de métricas de agenda. La autoría nominal vive en public.audit_log.';

-- SIN ÍNDICE NUEVO (B4 de la auditoría). El índice parcial que traía la primera
-- versión no servía al filtro que decía servir: el CTE `cierres` escanea
-- `estado in ('completada','no_show','cancelada')` acotado por `actualizado_en`,
-- y los desgloses salen de un `count(*) filter` sobre filas YA leídas. Habría
-- nacido como unused index en advisors.

-- ── 2. El sello de autoría en UPDATE (y el portazo al bypass) ────────────────
-- Cuerpo VERBATIM de producción (verificado 2026-07-26) + tres bloques nuevos.
--
-- HALLAZGO QUE ESTA MIGRACIÓN CIERRA: hasta hoy el guard solo exigía la RPC para
-- `completada` y `no_show`. `cancelada` estaba abierta — cualquiera con la clave
-- anon y una sesión válida podía vaciar su agenda con un PATCH directo a
-- /rest/v1/tareas, sin pasar por crm.cerrar_tarea(). Con la columna nueva eso
-- sería peor que un descuido: dejaría anular SIN quedar etiquetado como asesor,
-- justo la rendición de cuentas que Miguel pide, y además saltándose el
-- retroceso de etapa de § 5.
--
-- El portazo se limita a las sesiones HUMANAS (`v_uid is not null`) a propósito:
-- service_role, seeds y el teardown del gate RLS cancelan por UPDATE directo y
-- no pueden fijar una GUC de transacción. Para ellos el camino sigue abierto y
-- la etiqueta que reciben —'sistema'— es la verdad literal: ahí no hay asesor.
-- No queda hueco humano: `anon` no tiene USAGE sobre el esquema `crm`, y un JWT
-- sin `sub` deja `private.rol_crm(null)` en null → el USING de `tareas_update`
-- no le devuelve NINGUNA fila.
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
begin
  if old.estado <> 'pendiente' then
    raise exception 'La tarea ya esta cerrada; reagendar crea una tarea nueva';
  end if;
  if new.estado in ('completada','no_show') and not v_op then
    raise exception 'Completar o marcar no-show va por crm.cerrar_tarea()';
  end if;
  -- NUEVO: anular es un cierre como los otros dos.
  if new.estado = 'cancelada' and not v_op and not v_sistema and v_uid is not null then
    raise exception 'Anular una tarea va por crm.cerrar_tarea()';
  end if;
  if new.resultado_actividad_id is distinct from old.resultado_actividad_id and not v_op then
    raise exception 'El resultado lo escribe crm.cerrar_tarea()';
  end if;
  -- NUEVO: la autoría la deriva el servidor de CÓMO entró la escritura, jamás
  -- del payload. `crm.cancela_sistema` gana sobre `crm.op_tarea` porque el
  -- bookkeeping de un lead cerrado puede correr dentro de la misma transacción
  -- en la que la RPC dejó su flag encendido.
  -- ⚠️ SI AÑADES OTRO ESCRITOR DE `crm.op_tarea` QUE CANCELE, replica en él la
  -- llamada a `private.retroceso_por_anular_reunion`: hoy el retroceso vive
  -- INLINE en crm.cerrar_tarea (único sitio del repo que enciende este flag), y
  -- una RPC nueva que cancelara reuniones marcaría 'asesor' sin retroceder.
  -- Falla en la dirección segura (un no-op), pero silenciosa.
  if new.estado = 'cancelada' then
    new.cancelada_por := case
      when v_sistema then 'sistema'
      when v_op and v_uid is not null then 'asesor'
      else 'sistema'
    end;
  else
    -- old.estado es 'pendiente' por el primer raise, luego old.cancelada_por es
    -- null: esta rama es la que impide que el cliente inyecte una etiqueta.
    new.cancelada_por := old.cancelada_por;
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

-- ── 3. El mismo sello en INSERT (M2 de la auditoría) ─────────────────────────
-- La primera versión afirmaba "el cliente nunca la escribe" y era cierto solo en
-- UPDATE: `trg_tareas_before_insert` no tocaba la columna y el GRANT es de
-- TABLA, así que `authenticated` la lleva en el payload. Quedaba a salvo por
-- ACCIDENTE DE SECUENCIA (nacer cerrada exige `crm.op_tarea`, que solo enciende
-- la RPC, y ésta lo apaga antes de insertar la siguiente), no por diseño.
-- Cuerpo VERBATIM de 20260718180001 + las dos líneas del sello.
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
  -- nada sobre una tarea que nunca estuvo viva.
  new.cancelada_por := case when new.estado = 'cancelada' then 'sistema' else null end;
  return new;
end;
$$;

-- ── 4. El sistema se declara como tal ────────────────────────────────────────
-- Cuerpo VERBATIM de producción + el encendido/apagado de la GUC alrededor del
-- ÚNICO update que cancela. LOCAL a la transacción (tercer argumento `true`):
-- no se filtra entre peticiones de PostgREST y revierte al abortar.
create or replace function private.trg_leads_sync_tareas()
returns trigger
language plpgsql
security definer
set search_path = crm, private, public
as $$
begin
  -- Reasignacion / reparto de parkeado: propaga tenencia a las PENDIENTES.
  if (new.vendedor_id is distinct from old.vendedor_id)
     or (new.asignado_supervisor_id is distinct from old.asignado_supervisor_id) then
    update crm.tareas t
       set vendedor_id = new.vendedor_id,
           asignado_supervisor_id = new.asignado_supervisor_id
     where t.lead_id = new.id and t.estado = 'pendiente';
  end if;
  -- Cierre o soft-delete del lead: cancela las pendientes. Esto NO es gestión
  -- del asesor y desde hoy queda dicho en la fila, no solo en el comentario.
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
$$;

-- ── 5. El retroceso: si ya no hay reunión, el lead no está "en reunión" ──────
-- Inicio del ciclo vigente del lead: primera asignación registrada del ciclo, o
-- la creación del lead si nunca se repartió. Aísla el anclaje temporal para que
-- los dos `exists` de arriba no dupliquen la misma subconsulta.
-- IDEMPOTENCIA, y no es teorica: la 1a version de ESTA migracion colgaba el
-- retroceso de un AFTER UPDATE. Si quedo aplicada en algun branch de Supabase
-- —y el branch del gate nace de un snapshot—, el trigger SOBREVIVE al REPLACE y
-- se suma al inline: la etapa se moveria dos veces y volverian los dos
-- `cambio_etapa` espurios al log inmutable, en silencio. Misma convencion que
-- 20260725060657, que borra dos nombres heredados antes de crear el suyo.
drop trigger if exists trg_zz_tareas_retroceso_etapa on crm.tareas;
drop function if exists private.trg_tareas_retroceso_etapa();

create or replace function private.inicio_ciclo_lead(p_lead_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  select coalesce(
    (select min(la.sla_global_iniciado_en)
       from crm.lead_asignaciones la
       join crm.leads l2 on l2.id = la.lead_id
      where la.lead_id = p_lead_id
        and la.ciclo_n = l2.ciclo_actual),
    (select l3.creado_en from crm.leads l3 where l3.id = p_lead_id)
  );
$function$;

comment on function private.inicio_ciclo_lead(uuid) is
  'Instante en que empezó el CICLO vigente del lead (primera asignación de ese ciclo en el ledger crm.lead_asignaciones, o creado_en si nunca se repartió). Existe porque crm.actividades no tiene columna de ciclo: un lead reabierto arrastra toda su historia, y sin anclar los EXISTS a este instante una reunión realizada hace dos ciclos bloquearía el retroceso de etapa para siempre. ⚠️ OJO AL RELOJ: crm.leads.creado_en lo fija un trigger con statement_timestamp() y crm.actividades usa el DEFAULT now() = transaction_timestamp. Hoy es inocuo porque cada request de PostgREST es su propia transacción, pero una RPC futura que cree un lead y registre contacto EN LA MISMA transacción dejaría ese contacto fuera de su propio ciclo.';

revoke all on function private.inicio_ciclo_lead(uuid) from public, anon, authenticated, service_role;

-- LA EXCEPCIÓN A "LAS ETAPAS NUNCA BAJAN SOLAS", y conviene decir por qué esta
-- sí. La doctrina de 20260725060657 protege los hechos: una reunión con plantón
-- no borra que se agendó, así que el sistema no la deshace. Aquí el hecho es el
-- CONTRARIO: una persona con sesión acaba de declarar que esa reunión ya no
-- existe. Dejar el lead en `reunion_agendada` sin ninguna reunión viva no es
-- conservar un hecho, es sostener uno falso — y encima el caro: ese lead deja de
-- aparecer como pendiente de agendar en la cola de todos.
--
-- Baja a `contactado`, o a `nuevo` si NUNCA hubo contacto real EN ESTE CICLO:
-- el retroceso no puede inventar hacia abajo un contacto que no está en el
-- timeline.
--
-- Guardas, todas contra una forma concreta de mentir:
--   · `etapa = 'reunion_agendada'` — desde `propuesta_enviada` la etapa ya no la
--     sostiene la reunión; bajar sería borrar progreso posterior. Espejo exacto
--     del `etapa in ('nuevo','contactado')` de la subida.
--   · NINGUNA otra reunión pendiente viva — es literalmente el "y no se reagenda
--     una en ese mismo momento" del pedido. Como esta función corre DESPUÉS de
--     insertar la tarea siguiente, reagendar en el mismo gesto la ve y no baja:
--     cero movimientos de etapa, cero filas espurias en el log.
--   · NINGUNA `reunion_realizada` EN EL CICLO VIGENTE — si la reunión llegó a
--     ocurrir, bajar a `contactado` borraría el hito más caro del embudo por
--     limpiar una tarea residual. Conservador a propósito: ante la duda, no baja.
--   · el gate de ámbito de C1 (dueño + alcance del actor), porque esta función
--     es SECURITY DEFINER sobre una tabla sin FORCE RLS y su UPDATE ignora
--     `leads_update`. `p_uid is null` cubre sistema/seeds/cron.
--
-- ANCLAJE AL CICLO (M3 de la auditoría): `crm.actividades` no tiene columna de
-- ciclo y un lead reabierto (`descartado → nuevo`, `ciclo_actual + 1`) arrastra
-- su historia entera. Sin este anclaje, una `reunion_realizada` del ciclo 1
-- bloquearía el retroceso PARA SIEMPRE en todos los ciclos siguientes, en
-- silencio; y un contacto de hace seis meses elegiría `contactado` en un ciclo
-- donde nadie ha hablado con nadie. El inicio del ciclo sale del ledger
-- `crm.lead_asignaciones` (inmutable) y degrada a `creado_en` si el lead nunca
-- se repartió.
--
-- LIMITACIÓN DE PRODUCTO, dicha aquí para que no sorprenda (B5): un lead de la
-- COLA GLOBAL (sin analista y sin bandeja) NUNCA retrocede — el gate de ámbito
-- lo excluye por seguridad. Si uno acaba en `reunion_agendada` sin dueño y se
-- anula su reunión, se queda ahí hasta que alguien lo mueva a mano.
create or replace function private.retroceso_por_anular_reunion(
  p_lead_id uuid,
  p_tarea_id uuid,
  p_uid uuid
)
returns text
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_etapa_nueva text;
begin
  if p_lead_id is null then
    return null;
  end if;

  -- Guarda de reentrada, gemela de la de los triggers de subida: este UPDATE
  -- dispara `trg_leads_cambio_etapa` (que marca la actividad como automática) y
  -- `trg_leads_zz_sync_tareas`; ninguno puede reentrar aquí.
  if coalesce(current_setting('crm.avance_auto', true), 'off') = 'on' then
    return null;
  end if;

  perform set_config('crm.avance_auto', 'on', true);
  -- TODO el predicado va DENTRO del UPDATE: cero ventana entre leer la etapa y
  -- escribirla, y cero filas afectadas = nada que hacer (idempotente).
  update crm.leads l
     set etapa = case
           when exists (
             select 1 from crm.actividades a
              where a.lead_id = l.id
                and a.tipo in ('llamada_realizada','llamada_no_contestada',
                               'whatsapp_enviado','whatsapp_recibido','reunion_realizada')
                and a.creado_en >= private.inicio_ciclo_lead(l.id)
           ) then 'contactado'
           else 'nuevo'
         end
   where l.id = p_lead_id
     and l.activo = true
     and l.etapa = 'reunion_agendada'
     and not exists (
       select 1 from crm.tareas t
        where t.lead_id = l.id
          and t.id <> p_tarea_id
          and t.tipo = 'reunion'
          and t.estado = 'pendiente'
          and t.activo = true
     )
     and not exists (
       select 1 from crm.actividades a
        where a.lead_id = l.id
          and a.tipo = 'reunion_realizada'
          and a.creado_en >= private.inicio_ciclo_lead(l.id)
     )
     and coalesce(l.vendedor_id, l.asignado_supervisor_id) is not null
     and (
       p_uid is null
       or private.rol_crm(p_uid) = 'gerencia'
       or private.puede_ver_cartera(p_uid, coalesce(l.vendedor_id, l.asignado_supervisor_id))
     )
  returning l.etapa into v_etapa_nueva;
  perform set_config('crm.avance_auto', 'off', true);

  return v_etapa_nueva;
end;
$function$;

comment on function private.retroceso_por_anular_reunion(uuid, uuid, uuid) is
  'Devuelve el lead de reunion_agendada a contactado (o a nuevo si nunca hubo contacto real en el ciclo vigente) cuando UNA PERSONA anula la última reunión pendiente sin reagendar. Única excepción a "las etapas nunca bajan solas", y solo porque el disparo es una decisión humana explícita. La llama crm.cerrar_tarea DESPUÉS de insertar la tarea siguiente, para que reagendar en el mismo gesto no produzca un baja-y-sube con dos cambio_etapa espurios. No baja si queda otra reunión viva, si la reunión llegó a realizarse, si el lead ya pasó a propuesta_enviada o si está en la cola global. Espejo del front en app/src/lib/avance-automatico.ts (retrocesoPorAnularReunion).';

revoke all on function private.retroceso_por_anular_reunion(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;


-- ── 6. La RPC llama al retroceso, al final y una sola vez ────────────────────
-- Cuerpo VERBATIM de producción (20260725060657) + el bloque final. El orden
-- importa y por eso está inline: primero el UPDATE de la tarea, después el
-- INSERT de la siguiente (si la hay), y SOLO ENTONCES el retroceso — que así ve
-- el estado definitivo de la agenda del lead.
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
  v_retroceso text;
begin
  if v_uid is null or v_rol is null then
    raise exception 'No autorizado';
  end if;

  if p_estado not in ('completada','no_show','cancelada') then
    raise exception 'Estado de cierre invalido';
  end if;

  -- ORDEN DE BLOQUEO: el lead ANTES que la tarea (A1 de 20260725060657). Es
  -- tambien lo que hace seguro el retroceso del final: cuando llega, esta
  -- transaccion ya tiene la fila del lead tomada desde el principio, asi que no
  -- puede cerrar ciclo con trg_leads_sync_tareas (que bloquea leads -> tareas).
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

  -- NUEVO (Miguel, 2026-07-26): anular la ultima reunion viva sin reagendar
  -- devuelve el lead a su etapa real. AQUI, al final, es lo que hace que
  -- "anular y reagendar en el mismo gesto" sea un no-op: la reunion nueva ya
  -- esta insertada, el `not exists` la ve, y no se mueve ninguna etapa.
  if p_estado = 'cancelada' and v_tarea.tipo = 'reunion' and v_tarea.lead_id is not null then
    v_retroceso := private.retroceso_por_anular_reunion(v_tarea.lead_id, p_tarea_id, v_uid);
  end if;

  return jsonb_build_object(
    'ok', true,
    'tarea_id', p_tarea_id,
    'actividad_id', v_act_id,
    'siguiente_id', v_sig_id,
    'retroceso', v_retroceso
  );
end;
$function$;

-- ── 7. La métrica deja de mezclar (y de castigar convertir un lead) ──────────
-- Cuerpo VERBATIM de producción (md5 20f6d4087bcdcf0c23c7479ee561d485, verificado
-- 2026-07-26) con DOS cambios, ambos en el bloque de cierres:
--
--   a) `canceladas_asesor` y `canceladas_sistema` como claves nuevas. `canceladas`
--      SIGUE siendo el total y no cambia de significado: el front viejo que se
--      quede sin desplegar unos minutos sigue leyendo lo mismo que ayer.
--
--   b) EL DENOMINADOR DE pct_completadas PIERDE LAS DEL SISTEMA. Esto arregla un
--      sesgo que existía desde 20260719013000 y que nadie había mirado de cerca:
--      convertir un lead cancela todas sus tareas pendientes
--      (trg_leads_sync_tareas), y cada una de esas cancelaciones BAJABA el % del
--      vendedor. Es decir, el mejor resultado posible del embudo —cerrar la
--      venta— le empeoraba la nota, y más cuanto mejor planificado tuviera el
--      lead. Las del ASESOR sí siguen contando: anular es una decisión suya
--      sobre su propia agenda, y sacarlas del denominador convertiría el botón
--      nuevo en una salida gratis para no hacer nada.
--
-- `version` sigue en 1: las claves nuevas son ADITIVAS. El contrato Valibot del
-- front las declara opcionales precisamente para que ninguno de los dos órdenes
-- de despliegue (migración→front o front→migración) rompa el panel.
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
      count(*) filter (where t.estado = 'cancelada' and t.cancelada_por is distinct from 'asesor') as n_canceladas_sistema
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
            'pct_completadas', case
              when coalesce(c.n_completadas, 0) + coalesce(c.n_no_asistio, 0) + coalesce(c.n_canceladas_asesor, 0) > 0
              then round(
                100.0 * coalesce(c.n_completadas, 0)
                / (coalesce(c.n_completadas, 0) + coalesce(c.n_no_asistio, 0) + coalesce(c.n_canceladas_asesor, 0))
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

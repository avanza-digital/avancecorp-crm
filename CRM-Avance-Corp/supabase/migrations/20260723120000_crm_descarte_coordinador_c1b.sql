-- ============================================================================
-- C1-bis — Segunda malla: el código MARCA, Rosa DESCARTA
--
-- Qué habilita: los leads que piden préstamo/crédito (no son clientes de plazo
-- fijo) dejan de llegar al vendedor. Dos filtros, como pidió Miguel:
--   (1) el CÓDIGO marca automáticamente el comentario del cliente
--       (crm.leads.clasificacion_auto) — MARCA, NUNCA CIERRA;
--   (2) Rosa (coordinador) cierra con crm.descartar_lead(), con motivo
--       obligatorio y atribución nominal.
--
-- Principio de diseño (por qué el código no descarta solo): sobre los 187 leads
-- reales del formulario SOLO 1 pide préstamo (tasa base 0.53%). Con esa tasa,
-- un clasificador con 2% de falsos positivos destruiría ~4 depositantes reales
-- por cada 1 lead basura que ahorra. El coste de un falso positivo (perder un
-- depósito a plazo fijo) es órdenes de magnitud mayor que el de un falso
-- negativo (una llamada perdida de Rosa). Por eso: marcar sí, cerrar no.
--   Corolario verificado: 'el plazo fijo sirve de garantía para un crédito?' es
--   un DEPOSITANTE y la regla lo marca. Si la marca cerrara, se perdería.
--
-- "Nada se pierde": el descarte NO borra ni desactiva (activo sigue true), deja
-- sello nominal (descartado_por/descartado_en), actividad 'cambio_etapa' a
-- nombre del actor, fila completa en public.audit_log, y tiene DESHACER de 24 h
-- (crm.deshacer_descarte) sobre los descartes del propio actor.
--
-- Frontera: solo crm.leads y RPCs del esquema crm. NO toca public.perfiles, ni
-- el portal de clientes, ni ninguna función viva ajena (cero CREATE OR REPLACE
-- sobre funciones de producción: el sello va en un trigger NUEVO que corre el
-- último entre los BEFORE, así que no hay copia-verbatim que pueda derivar).
--
-- Plan: vault "Distribución de leads y base fría (plan revisado)" — Fase C1-bis.
--
-- Bloques: (a) motivo 'pide_credito' en el catálogo · (b) columnas de marca y
--          sello + grants por columna · (c) redactor de PII · (d) trigger de
--          clasificación/sello/inmutabilidad · (e) leads_por_repartir v2
--          (DROP+CREATE: cambia el tipo de retorno) · (f) descartar_lead ·
--          (g) deshacer_descarte.
-- ============================================================================

begin;
set local lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- (a) Catálogo de motivos: se añade 'pide_credito'
--
--     Decisión: NO se reusa 'sin_interes'. Miguel necesita MEDIR cuánta basura
--     de crédito entra por la landing y el formulario; enterrarla en
--     'sin_interes' contamina la métrica de conversión y borra justo el dato
--     que justifica endurecer o aflojar la regla del clasificador.
--     Se añade UN solo valor (no se infla el catálogo por si acaso).
--
--     El CHECK original es anónimo (crm.leads, F0) → nombre autogenerado
--     'leads_motivo_descarte_check'. Se dropea por nombre si existe, patrón
--     idéntico al bloque (a) de la migración C1.
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from pg_constraint
    where conname = 'leads_motivo_descarte_check' and conrelid = 'crm.leads'::regclass
  ) then
    alter table crm.leads drop constraint leads_motivo_descarte_check;
  end if;
end $$;

alter table crm.leads add constraint leads_motivo_descarte_check
  check (motivo_descarte in (
    'sin_interes','sin_fondos','competencia','no_responde',
    'datos_invalidos','pide_credito','otro'
  ));

-- ---------------------------------------------------------------------------
-- (b) Columnas nuevas en crm.leads
--
--     Por qué COLUMNA y no otra cosa (decisión, no omisión):
--       * NO como valor de `etapa`: 'etapa' es el embudo comercial y aparece
--         hardcodeada en 6 sitios (los 2 índices únicos parciales
--         uq_leads_*_vivo, el guard de tenencia, el ledger 0C, las 3 RPC de
--         reparto y todas las métricas). Un valor nuevo rompería todo eso sin
--         aportar nada: 'descartado' + motivo YA expresa el estado terminal.
--       * NO dentro de `nota`: es texto libre editable por el vendedor; medir
--         por parseo de texto no es indexable, no es auditable y se corrompe
--         a la primera edición.
--       * NO como tabla aparte: sería un 1:1 con crm.leads (a lo sumo una fila
--         por lead) a cambio de un JOIN en la cola, RLS nueva, grants nuevos y
--         un trigger de auditoría nuevo. La HISTORIA (que sí es un evento) ya
--         vive en crm.actividades ('cambio_etapa') y en public.audit_log.
--       * SÍ como 3 columnas: son atributos del lead, se filtran e indexan, y
--         el trigger trg_audit_leads ya las versiona fila a fila.
--
--     Atribución "código vs Rosa", legible sin joins:
--       clasificacion_auto not null            → el CÓDIGO lo marcó
--       descartado_por not null                → una PERSONA lo cerró
--                                                (su rol sale de crm.equipo)
--       descartado_por null + etapa descartado → cierre de sistema (hoy
--                                                imposible: leads_before_insert
--                                                prohíbe nacer terminal y las
--                                                RPC exigen sesión)
--     Cruzando ambas se obtiene la matriz de confusión REAL del clasificador:
--       marcado + descartado 'pide_credito' = acierto
--       marcado + repartido                 = FALSO POSITIVO (aflojar la regla)
--       no marcado + 'pide_credito'         = FALSO NEGATIVO (falta una regla)
--     Sin persistir clasificacion_auto esa matriz no se puede calcular nunca.
-- ---------------------------------------------------------------------------
alter table crm.leads
  add column clasificacion_auto text
    constraint leads_clasificacion_auto_valida
    check (clasificacion_auto is null or clasificacion_auto in ('posible_credito')),
  add column descartado_en timestamptz,
  add column descartado_por uuid references public.perfiles(id) on delete set null;

comment on column crm.leads.clasificacion_auto is
  'Veredicto AUTOMÁTICO del clasificador sobre el comentario del cliente, sellado en el INSERT y luego inmutable. Es una MARCA para que el coordinador priorice: NUNCA descarta por sí sola. null = el código no detectó nada. Catálogo extensible por migración.';
comment on column crm.leads.descartado_en is
  'Cuándo se cerró el lead como descartado (sello del trigger, no del cliente API). Se limpia al reabrir: describe el cierre VIGENTE; el histórico vive en public.audit_log y crm.actividades.';
comment on column crm.leads.descartado_por is
  'Quién descartó el lead (perfil del actor con sesión). null en un lead descartado significaría cierre sin sesión humana. Junto a motivo_descarte responde quién y por qué, sin parsear texto.';

-- crm.leads: los GRANT por columna son la convención de la casa desde
-- 20260718000001. Estado REAL verificado en prod (pg_class.relacl): el ACL es
-- de TABLA (authenticated=arw), que en PostgreSQL cubre también las columnas
-- futuras — o sea que estas 3 líneas son hoy redundantes. Se emiten igual:
-- son inofensivas y son la única red si alguien revoca el grant de tabla.
grant select (clasificacion_auto, descartado_en, descartado_por)
  on crm.leads to authenticated, service_role;
grant insert (clasificacion_auto, descartado_en, descartado_por)
  on crm.leads to authenticated, service_role;
grant update (clasificacion_auto, descartado_en, descartado_por)
  on crm.leads to authenticated, service_role;

-- AVISO PARA QUIEN VENGA DESPUÉS (verificado en PG16, no es folclore):
--   `revoke update (columna) on crm.leads from authenticated;` es un NO-OP
--   SILENCIOSO mientras exista el GRANT DE TABLA: relacl no cambia,
--   pg_attribute.attacl sigue null, has_column_privilege() sigue devolviendo
--   true y Postgres no emite ni un WARNING.
--   ⇒ NO se puede hacer una columna de solo-lectura con grants sin desmontar
--     antes el grant de tabla (operación de alto riesgo, fuera de alcance).
--     Por eso la inmutabilidad de clasificacion_auto y del sello de descarte
--     va por TRIGGER en el bloque (d) — que además es el patrón ya vivo
--     (private.leads_before_update restaura id/creado_por/creado_en/perfil_id/
--     contrato_id desde OLD).

-- Índices parciales: soporte del deshacer (ventana de 24 h) y del reporte de
-- descartes. El de descartado_por cubre la FK nueva (convención de la casa).
-- Advisors: nacerán como INFO 'unused index' hasta que haya volumen — clase
-- aceptada y documentada, igual que el índice FK de crm.objetivos.
create index idx_leads_descarte on crm.leads (descartado_en desc)
  where etapa = 'descartado';
create index idx_leads_descartado_por on crm.leads (descartado_por)
  where descartado_por is not null;
create index idx_leads_clasificacion_auto on crm.leads (clasificacion_auto)
  where clasificacion_auto is not null;

-- ---------------------------------------------------------------------------
-- (c) private.redactar_pii — el comentario del cliente sin datos de contacto
--
--     C1 construyó la cola "SIN PII de contacto" a propósito (Rosa enruta, no
--     contacta). Pero el comentario real trae correos DENTRO del texto libre
--     ("grimaldoescalante7@gmail.com") y esa pestaña del origen ni siquiera
--     tiene columna de correo. Mostrar `nota` cruda REINTRODUCIRÍA la PII que
--     C1 sacó a mano. Solución: una sola función de redacción, usada por la
--     cola y por cualquier reporte futuro (fuente única).
--     Orden obligatorio: correo → celular → documento. Al revés, el redactado
--     del documento partiría un correo o un celular y dejaría restos legibles.
-- ---------------------------------------------------------------------------
create or replace function private.redactar_pii(p_texto text)
returns text
language sql
immutable
parallel safe
set search_path to 'pg_catalog'
as $function$
  select regexp_replace(
           regexp_replace(
             regexp_replace(
               coalesce(p_texto, ''),
               '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}', '[correo oculto]', 'g'),
             -- Celular peruano TAMBIÉN con separadores ("987 654 321",
             -- "987-654-321"): el formato más común en texto libre. La versión
             -- anterior solo ocultaba los 9 dígitos pegados (auditoría 2026-07-23).
             '(\+?51[[:space:]]*)?9([[:space:].-]?[0-9]){8}', '[teléfono oculto]', 'g'),
           '\m[0-9]{8}\M', '[documento oculto]', 'g');
$function$;

comment on function private.redactar_pii(text) is
  'Quita correo, celular peruano y documento de 8 dígitos de un texto libre. Fuente única de redacción para superficies que muestran el comentario del cliente a quien no debe contactarlo (Ley 29733).';

revoke execute on function private.redactar_pii(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- (d) Trigger — clasificación en el alta, sello en el cierre, inmutabilidad
--
--     Por qué la regla vive en SQL y no en el puente ni en la edge:
--       * el puente y el conector son Apps Script posicional: meter una columna
--         nueva desplaza 16 índices en DOS archivos y obliga a redesplegar la
--         edge, que HOY difiere del repo (fix de teléfonos con coma desplegado
--         sin commitear) → redesplegarla lo revertiría en silencio;
--       * aquí la regla aplica a TODO lead, entre por la hoja, por creación
--         manual de un vendedor o por un canal futuro;
--       * cambiarla es una migración versionada y probada por el oráculo, no
--         un pegado a mano en el editor de Apps Script.
--     Cero cambios en la hoja, en el conector y en la edge.
--
--     Nombre 'zz_': entre los BEFORE de crm.leads los triggers disparan en
--     orden alfabético (00_guard_tenencia → before_insert/update →
--     bloquear_reasignacion → cambio_etapa → normalizar_tel → reasignacion →
--     zz_sello_descarte). Corre el ÚLTIMO a propósito: así su restauración de
--     clasificacion_auto y su sello ganan sobre cualquier trigger anterior
--     y sobre lo que mande el cliente API. Misma convención que
--     trg_leads_00_guard_tenencia (primero) y trg_leads_zz_sync_tareas.
-- ---------------------------------------------------------------------------
create or replace function private.trg_leads_zz_sello_descarte()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_txt text;
begin
  if tg_op = 'INSERT' then
    -- El cliente API NO decide su propia clasificación ni su sello de cierre.
    -- translate() quita tildes sin depender de la extensión unaccent.
    v_txt := lower(translate(coalesce(new.nota, ''),
                             'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'));
    -- Prefijos con frontera de palabra a la izquierda: 'prestam*' (préstamo,
    -- préstamos, prestamista) y 'financiamient*'. Regla ESTRECHA a propósito
    -- (auditoría 2026-07-23): 'credit*' marcaba "¿son cooperativa de ahorro y
    -- CRÉDITO?" — la identidad de la propia empresa y la pregunta MÁS común de
    -- un buen cliente — y 'prestar' marcaba "prestar información". Con tasa
    -- base 0.5%, un falso positivo cuesta más que un falso negativo: lo que
    -- esta regla no atrape lo atrapa Rosa leyendo el comentario redactado.
    if v_txt ~ '\m(prestam|financiamient)' then
      new.clasificacion_auto := 'posible_credito';
    else
      new.clasificacion_auto := null;
    end if;
    new.descartado_en := null;
    new.descartado_por := null;
    return new;
  end if;

  -- El veredicto del código es un DATO DE MEDICIÓN: si un humano pudiera
  -- reescribirlo, la matriz de confusión (falsos positivos vs negativos)
  -- dejaría de ser calculable. Inmutable, como id/creado_por/creado_en.
  new.clasificacion_auto := old.clasificacion_auto;

  if new.etapa = 'descartado' and old.etapa is distinct from 'descartado' then
    new.descartado_en := statement_timestamp();
    new.descartado_por := auth.uid();
  elsif new.etapa is distinct from 'descartado' then
    -- Reapertura: el sello describe el cierre VIGENTE, no uno viejo. Dejarlo
    -- rancio corrompería en silencio cualquier informe de "descartes del mes".
    -- El histórico completo queda en public.audit_log y en crm.actividades.
    new.descartado_en := null;
    new.descartado_por := null;
  else
    new.descartado_en := old.descartado_en;
    new.descartado_por := old.descartado_por;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_leads_zz_sello_descarte on crm.leads;
create trigger trg_leads_zz_sello_descarte
before insert or update on crm.leads
for each row
execute function private.trg_leads_zz_sello_descarte();

revoke execute on function private.trg_leads_zz_sello_descarte()
  from public, anon, authenticated;

-- Backfill: los leads ya descartados (si los hubiera) no tienen sello y no se
-- inventa uno. Su autoría real está en public.audit_log. La clasificación no
-- se retro-calcula: describir como "marcado por el código" algo que el código
-- nunca vio falsearía la métrica desde el día uno.

-- ---------------------------------------------------------------------------
-- (e) crm.leads_por_repartir() v2 — ahora Rosa VE lo que escribió el cliente
--
--     DROP + CREATE obligatorio: añadir columnas al RETURNS TABLE cambia el
--     tipo de retorno y CREATE OR REPLACE fallaría con 42P13. El DROP borra la
--     ACL → se reemiten revoke/grant abajo o Rosa recibe 42501 en la siguiente
--     carga (misma trampa que documenta la migración C1).
--
--     Las 2 columnas nuevas van al FINAL: PostgREST devuelve objetos JSON y el
--     esquema Valibot del frontend ignora claves desconocidas, así que el
--     despliegue es seguro en cualquier orden (BD antes o después del build).
--
--     WHERE idéntico al de C1 (cola global, etapas abiertas, no_contactar=false
--     por Ley 29571) y ORDER BY creado_en asc: el FIFO NO se toca. Priorizar
--     por clasificacion_auto rompería la garantía de justicia que ya asevera el
--     gate; la marca se resalta en la UI, no reordena la cola.
-- ---------------------------------------------------------------------------
drop function if exists crm.leads_por_repartir();

create function crm.leads_por_repartir()
returns table (
  id uuid, nombre_completo text, distrito text, origen text,
  categoria_interes text, monto_estimado numeric, moneda text,
  creado_en timestamptz, clasificacion_auto text, comentario text
)
language plpgsql stable security definer set search_path = ''
as $$
declare v_actor uuid := (select auth.uid());
begin
  if v_actor is null or not exists (
    select 1 from crm.equipo actor_equipo
    join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
    where actor_equipo.perfil_id = v_actor
      and actor_equipo.rol_crm in ('coordinador','gerencia')
      and actor_equipo.activo = true and actor_perfil.activo = true
  ) then
    raise exception 'Solo el coordinador puede ver la cola de leads por repartir'
      using errcode = '42501';
  end if;

  return query
  select l.id, l.nombre_completo, l.distrito, l.origen,
         l.categoria_interes, l.monto_estimado, l.moneda, l.creado_en,
         l.clasificacion_auto,
         -- Comentario REDACTADO (correo/celular/documento fuera) y acotado a
         -- 400 caracteres: Rosa necesita leer la pregunta, no los datos de
         -- contacto. Mantiene la premisa "sin PII de contacto" de C1.
         nullif(left(private.redactar_pii(l.nota), 400), '')
  from crm.leads l
  where l.activo = true
    and l.vendedor_id is null
    and l.asignado_supervisor_id is null                     -- cola global (sin dueño)
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
    and l.no_contactar = false                               -- Ley 29571: nunca listar 'No Insista'
  order by l.creado_en asc;                                  -- FIFO justo
end;
$$;

comment on function crm.leads_por_repartir() is
  'Cola de leads nuevos sin dueño que el coordinador reparte o descarta. Sin PII de contacto: el comentario del cliente viaja REDACTADO (correo/celular/documento ocultos) y trunco a 400. Incluye clasificacion_auto (marca del código, nunca cierra). Excluye no_contactar=true (Ley 29571). FIFO. Solo coordinador/gerencia activos.';

revoke all on function crm.leads_por_repartir() from public, anon;
grant execute on function crm.leads_por_repartir() to authenticated;

-- ---------------------------------------------------------------------------
-- (f) crm.descartar_lead(p_lead, p_motivo, p_nota) — la segunda malla humana
--
--     Por qué una RPC y no un UPDATE por RLS: la policy leads_update exige que
--     el lead caiga dentro de private.vendedor_ids_visibles(actor), que para el
--     coordinador es ∅ por diseño (bloque (b) de C1) → 0 filas afectadas y un
--     'Lead no encontrado' engañoso. La escritura del coordinador vive
--     EXCLUSIVAMENTE en RPCs SECURITY DEFINER con gate propio.
--
--     ALCANCE deliberado: SOLO la cola global (vendedor_id y
--     asignado_supervisor_id null). Rosa no cierra el trabajo de nadie; además
--     así jamás hay episodio abierto en crm.lead_asignaciones que cerrar (el
--     ledger solo abre episodio cuando hay vendedor_id) y el guard de tenencia
--     no tiene nada que reclamar.
--
--     NO toca `activo` (el guard prohíbe cerrar y desactivar en el mismo
--     UPDATE) ni la tenencia (el guard aborta si cambia al entrar en terminal).
--     La actividad 'cambio_etapa' y la fila de public.audit_log las escriben
--     los triggers, acreditando a auth.uid(): la traza sale gratis.
--
--     no_contactar: descartar a un 'No Insista' SÍ se permite — decisión, no
--     omisión. P0429 protege el CONTACTO (repartir a un vendedor que llamará);
--     cerrar la ficha no contacta a nadie y de hecho es lo correcto.
--
--     SQLSTATE (contrato con el frontend):
--       42501 gate de rol · 22023 argumento inválido · P0002 fuera de la cola,
--       carrera, ya cerrado con otro motivo o convertido.
-- ---------------------------------------------------------------------------
create or replace function crm.descartar_lead(
  p_lead uuid,
  p_motivo text,
  p_nota text default null
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_lead  crm.leads%rowtype;
  v_nota  text := nullif(btrim(coalesce(p_nota, '')), '');
begin
  -- 1) Gate: coordinador|gerencia activos, con perfil de portal activo.
  if v_actor is null or not exists (
    select 1 from crm.equipo ae
    join public.perfiles ap on ap.id = ae.perfil_id
    where ae.perfil_id = v_actor
      and ae.rol_crm in ('coordinador','gerencia')
      and ae.activo = true and ap.activo = true
  ) then
    raise exception 'Solo el coordinador puede descartar leads de la cola'
      using errcode = '42501';
  end if;

  -- 2) Argumentos. La lista es el ESPEJO de leads_motivo_descarte_check: el
  --    CHECK sigue siendo la autoridad, esto solo da un mensaje humano antes
  --    de tocar la fila (un 23514 crudo no se puede traducir al usuario).
  if p_lead is null then
    raise exception 'El lead es obligatorio' using errcode = '22023';
  end if;
  if p_motivo is null or p_motivo not in (
    'sin_interes','sin_fondos','competencia','no_responde',
    'datos_invalidos','pide_credito','otro'
  ) then
    raise exception 'Motivo de descarte inválido' using errcode = '22023';
  end if;
  if v_nota is not null and length(v_nota) > 500 then
    raise exception 'La nota del descarte no puede pasar de 500 caracteres'
      using errcode = '22023';
  end if;

  -- 3) Toma el lead de la COLA GLOBAL y bloquéalo en la MISMA tx. El filtro NO
  --    incluye `etapa`: hace falta leer la etapa ya bloqueada para resolver la
  --    idempotencia del paso 4 (si se filtrara por etapa abierta, un reintento
  --    legítimo caería en P0002 y la UI mostraría un error falso).
  select * into v_lead
  from crm.leads l
  where l.id = p_lead and l.activo = true
    and l.vendedor_id is null and l.asignado_supervisor_id is null
  for update;
  if not found then
    raise exception 'El lead no está en la cola por repartir (tiene dueño, está inactivo o no existe)'
      using errcode = 'P0002';
  end if;

  -- 4) IDEMPOTENCIA: el mismo actor repitiendo el mismo descarte (doble clic,
  --    reintento de red, perdedor de una carrera consigo mismo) recibe el mismo
  --    resultado con 'ya_estaba', sin segunda actividad ni segunda fila de
  --    auditoría. Con OTRO motivo o de OTRO actor NO es idempotente: eso es un
  --    conflicto real y debe verse.
  if v_lead.etapa = 'descartado' then
    if v_lead.motivo_descarte = p_motivo
       and v_lead.descartado_por is not distinct from v_actor then
      return jsonb_build_object(
        'lead_id', p_lead,
        'motivo_descarte', v_lead.motivo_descarte,
        'clasificacion_auto', v_lead.clasificacion_auto,
        'descartado_por', v_lead.descartado_por,
        'descartado_en', v_lead.descartado_en,
        'ya_estaba', true);
    end if;
    raise exception 'El lead ya fue descartado con otro motivo o por otra persona'
      using errcode = 'P0002';
  end if;

  if v_lead.etapa = 'convertido' then
    raise exception 'Un lead convertido no se descarta' using errcode = 'P0002';
  end if;

  -- 5) UPDATE con CANDADO CAS: el predicado de tenencia y de etapa va TAMBIÉN
  --    aquí (no solo en el SELECT del paso 3) → la mutación se auto-defiende de
  --    la carrera aunque un refactor futuro debilite el FOR UPDATE.
  --    La nota se APPENDEA, jamás se pisa: el comentario del cliente no se
  --    pierde (regla dura de Miguel).
  update crm.leads
     set etapa = 'descartado',
         motivo_descarte = p_motivo,
         nota = case
                  when v_nota is null then nota
                  else coalesce(nullif(nota, '') || ' · ', '') || 'DESCARTE: ' || v_nota
                end
   where id = p_lead and activo = true
     and vendedor_id is null and asignado_supervisor_id is null
     and etapa not in ('descartado','convertido');
  if not found then
    raise exception 'El lead ya no está en la cola por repartir (carrera de descarte)'
      using errcode = 'P0002';
  end if;

  select * into v_lead from crm.leads where id = p_lead;

  return jsonb_build_object(
    'lead_id', p_lead,
    'motivo_descarte', v_lead.motivo_descarte,
    'clasificacion_auto', v_lead.clasificacion_auto,
    'descartado_por', v_lead.descartado_por,
    'descartado_en', v_lead.descartado_en,
    'ya_estaba', false);
end;
$$;

comment on function crm.descartar_lead(uuid, text, text) is
  'El coordinador cierra un lead de la COLA GLOBAL con motivo obligatorio (catálogo de leads_motivo_descarte_check, incluido pide_credito). No toca activo ni la tenencia (el guard exige operaciones separadas). Idempotente para el mismo actor y motivo. La nota se appendea, nunca se pisa. Descartar un no_contactar SÍ se permite: cerrar no es contactar. Actividad y auditoría por trigger. Solo coordinador/gerencia activos. 42501 rol, 22023 argumento, P0002 fuera de cola o carrera.';

-- WARN authenticated_security_definer_function_executable: clase ACEPTADA y
-- documentada (todas las RPC del CRM viven así).
revoke all on function crm.descartar_lead(uuid, text, text) from public, anon;
grant execute on function crm.descartar_lead(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- (g) crm.deshacer_descarte(p_lead) — "nada se pierde", operativo
--
--     Sin esto, descartar es una puerta de un solo sentido dentro de la
--     pantalla de Rosa y el único remedio sería que gerencia edite a mano.
--     Ventana estrecha a propósito: 24 h, SOLO los descartes del PROPIO actor y
--     SOLO si el lead sigue sin dueño. No es una reapertura general (eso es
--     otra decisión, con su propia RPC, si algún día se pide).
--
--     Reabrir en 'nuevo' es la única transición que permite el guard desde
--     'descartado', e incrementa ciclo_actual (lo hace el guard, no esta RPC).
--     Los índices únicos parciales uq_leads_telefono_vivo / uq_leads_dni_vivo
--     excluyen 'descartado': si mientras tanto entró otro lead vivo con el
--     mismo teléfono o DNI, la reapertura choca con 23505 → se traduce a 22023
--     con mensaje humano en vez de escupir el mensaje crudo de Postgres.
-- ---------------------------------------------------------------------------
create or replace function crm.deshacer_descarte(p_lead uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_actor   uuid := (select auth.uid());
  v_ventana interval := interval '24 hours';
  v_lead    crm.leads%rowtype;
begin
  if v_actor is null or not exists (
    select 1 from crm.equipo ae
    join public.perfiles ap on ap.id = ae.perfil_id
    where ae.perfil_id = v_actor
      and ae.rol_crm in ('coordinador','gerencia')
      and ae.activo = true and ap.activo = true
  ) then
    raise exception 'Solo el coordinador puede deshacer un descarte'
      using errcode = '42501';
  end if;

  if p_lead is null then
    raise exception 'El lead es obligatorio' using errcode = '22023';
  end if;

  select * into v_lead
  from crm.leads l
  where l.id = p_lead and l.activo = true
    and l.vendedor_id is null and l.asignado_supervisor_id is null
    and l.etapa = 'descartado'
    and l.descartado_por = v_actor
    and l.descartado_en > (statement_timestamp() - v_ventana)
  for update;
  if not found then
    raise exception 'Solo puedes deshacer tus propios descartes de las últimas 24 horas, y solo si el lead sigue sin dueño'
      using errcode = 'P0002';
  end if;

  begin
    update crm.leads
       set etapa = 'nuevo', motivo_descarte = null
     where id = p_lead and activo = true and etapa = 'descartado'
       and vendedor_id is null and asignado_supervisor_id is null;
    if not found then
      raise exception 'El descarte ya no se puede deshacer (carrera)'
        using errcode = 'P0002';
    end if;
  exception
    when unique_violation then
      raise exception 'Ya existe otro lead vivo con ese mismo teléfono o documento: no se puede reabrir'
        using errcode = '22023';
  end;

  select * into v_lead from crm.leads where id = p_lead;

  return jsonb_build_object(
    'lead_id', p_lead,
    'etapa', v_lead.etapa,
    'ciclo_actual', v_lead.ciclo_actual,
    'reabierto_por', v_actor,
    'reabierto_en', statement_timestamp());
end;
$$;

comment on function crm.deshacer_descarte(uuid) is
  'Deshace un descarte del PROPIO actor hecho en las últimas 24 horas, si el lead sigue sin dueño: vuelve a etapa nuevo, limpia motivo_descarte y el sello (lo hace el trigger) y el guard incrementa ciclo_actual. Choque con el índice único de teléfono/DNI vivo se traduce a 22023. 42501 rol, 22023 argumento o choque, P0002 fuera de ventana o carrera.';

revoke all on function crm.deshacer_descarte(uuid) from public, anon;
grant execute on function crm.deshacer_descarte(uuid) to authenticated;

commit;

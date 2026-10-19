ROLE: SECONDARY_REVIEWER.
Codex is PRIMARY. Independent architecture review ONLY. Do not modify files, implement, invoke Codex, delegate or initiate another review chain. Follow .ai/REVIEW_PROTOCOL.md: VERDICT, evidence-backed FINDINGS P0-P3, relevant risks/test gaps, NEXT ACTIONS, CONFIDENCE. No findings without provided evidence. Distinguish assumptions.

User ACTIVATED implementation goal: full first-conversion-by-evidence plan (8 phases) through merged PR/Main and ZIP, no production deployment/activation. This is phase 1 architecture gate; no product implementation yet. Previous PLANNING review asked to establish cycle/identity rules, modes before guard, office permissions, post-confirm immutability and version-skew. Current live SQL evidence answers most of those.

Important architecture question: root CLAUDE generic standard says all new domain tables have negocio_id, but current CRM has NO such dimension anywhere (catalog query returned zero columns/tables negocio_id/organizacion_id/tenant_id; roles/visible analyst and canonical identity define authorization). crm.multiempresa_flags only supports booleans, while crm.sla_operacion_control has an unrelated immutable SLA adoption contract. Do NOT invent a tenant model or couple recorrido settings to SLA. Recommend minimal coherent administrative mode/cohort storage, respecting CRM-specific rule new tables crm+RLS+auditing, no public changes. Consider an administrative singleton (not domain tenant data) with explicit documented scope vs any better existing-shape approach. We must not weaken isolation.

Review causal activity context capture, evaluator consistency under cancellation/undo concurrency, office reuse (no fake contact before a completed visit), guard placement/recoverable access, and necessary historical classification. Do not ask to block independent implementation on legacy activation decisions; default observe and rollout is excluded.

CodeGraph was tried first; returned unrelated portal source. Targeted reads and READ ONLY live pg_proc catalog are supplied. No private client records or secrets.

# Fase 1 · Contrato del recorrido por hechos

Base de código: Main 6ace3d441bd874a1e06613ee5718b1023e08c39d. Catálogo de producción leído el 18/10/2026; cuerpos en evidencia/. Este documento define implementación y pruebas, no autoriza activación productiva.

## Decisiones sustentadas

1. **Ciclo:** usar crm.leads.ciclo_actual y crm.lead_sla_ciclos. private.trg_leads_guard_tenencia fija 1 al nacer, lo conserva en reasignaciones, lo incrementa exclusivamente al salir de descartado hacia nuevo, e impide reabrir convertido. private.trg_leads_sla_global sella el inicio; private.trg_leads_sla_versionado crea su fila. tarea_sla_contexto deriva del ciclo del lead, no lo define.
2. **Primera conversión:** conservar el contrato de identidad canónica actual, compartido entre empresas. private.inversion_persona_contexto_para exige resolver una conversión inicial pendiente y rechaza otra primera conversión de la misma persona. Cambiar empresa, retirar una inversión o fusionar una identidad no reinicia el recorrido. El servidor distingue solicitudes con lead_origen_id de inversiones adicionales, renovación, upgrade y venta cruzada.
3. **Caducidad:** una evidencia vigente no vence solo por el transcurso de un SLA. Una nueva reapertura sí cambia el ciclo. Cancelar, inactivar o deshacer la evidencia retira su crédito, sin borrar historial.
4. **Orden:** contacto anterior a la creación de la cita que se acredita, o mismo gesto compuesto explícito de oficina. La entrevista por sí sola no inventa contacto anterior.
5. **Oficina:** los roles/ámbitos que hoy pueden gestionar el lead (vendedor propio, supervisor visible, gerencia). No autoriza otras empresas/personas o leads vetados. Una acción explícita reutiliza el formulario de cierre, registra una cita inmediata y su asistencia real, resultado comercial, capital cuando corresponde y próxima acción. No permite fecha retrospectiva ni simula una llamada.
6. **Confirmado:** reintentos y lectura de inversiones confirmadas conservan su resultado. Guardar referencias de ciclo/evidencias usadas al confirmar; una anulación posterior no revierte contratos ni clientes y respeta permisos actuales.
7. **Antiguos:** sin exenciones por etapa/origen/rol. Los casos no demostrables son ambiguos, no completos. El modo inicial es observación; la activación productiva depende de política comercial posterior. Un borrador abierto no recibe excepción automática.
8. **n8n:** fuera de este alcance. Las decisiones de conversión dependen de transacciones del CRM.

## Matriz de hechos

| Paso | Evidencia acreditable | No acredita |
|---|---|---|
| Nuevo | Lead y ciclo actual verificables | Manipular ciclo desde el cliente |
| Gestionado | Actividad real del ciclo, no deshecha: llamada realizada/no contestada, WhatsApp enviado/recibido o visita/reunión válida | Abrir enlace, nota administrativa, cambio de etapa |
| Contactado | Llamada realizada, WhatsApp recibido o contacto real de la operación oficina | Llamada no contestada, WhatsApp enviado, etiqueta Contactado, entrevista sin vínculo previo |
| Cita agendada | Tarea de reunión activa del ciclo, pendiente o completada, posterior al contacto; la completada debe ser la de la asistencia acreditada | Cancelada, no_show, tarea de otro ciclo, cita aislada de la entrevista |
| Entrevista | Cita completada + resultado_actividad_id + actividad reunion_realizada cuyo metadata.tarea_id concuerda, sin deshacer y sin fecha futura | Etapa propuesta_enviada, actividad de otra cita, reunión cancelada o futura |
| Convertido | Confirmación transaccional del flujo actual con inversión y recorrido válido cuando la regla es exigible | Cambiar la etapa directamente |

Un acto puede acreditar varios pasos, pero no fabricar una secuencia inexistente. Con varias citas, elegir una pareja válida tarea/asistencia; no mezclar el contacto de un ciclo con la cita de otro. Seguir la tarea efectivamente reprogramada mediante su contexto.

## Cobertura y ambigüedad histórica

Censo de estructura (READ ONLY): 1.965 leads operativos, 0 sin fila del ciclo actual, 29.982 actividades, 11.917 tareas, 72 citas activas sin tarea_sla_contexto, 0 ciclos marcados aproximados. No es todavía el censo de elegibilidad: no se cuentan como completos por estas cifras.

Las actividades no tienen hoy una clave causal de ciclo. Propuesta: un trigger adicional del servidor estampa un contexto reservado en metadata al insertar una actividad relevante bajo el lock del lead. No se altera el contador de ciclos ni se crea un ledger paralelo de hechos. UPDATE preserva el contexto; un cliente no puede falsificarlo por metadata.

Para historia previa, usar vínculo de tarea/ciclo o de actividad/episodio que ya sea demostrable. No asignar un ciclo por comparación de horas únicamente. Registros sin vínculo suficiente se informan como ambiguos; no se reescriben durante la migración.

## Piezas y límites de integración

- Cierres: RegistrarResultado (modal y Mi día), CerrarTareaDialog, ejecutarCierreTarea, cerrar_reunion_v3 y cerrar_tarea_v2.
- Propuestas: sugerirSiguiente/camposDeSugerencia siguen siendo la única fuente de próxima tarea.
- Guardado: onGuardado solo tras persistencia confirmada; consulta de recorrido independiente del guardado.
- Entrada: lead-drawer e InversionDesdeLead; preparación con preparar_persona_lead_inversion_fn.
- Preparación/reanudación: private.inversion_persona_contexto_para y su variante de lectura; conservar ámbito canónico.
- Acceso externo: crm-inversion-portal → acceso_inversion_fn('reclamar',...). Cubrir tanto reclamo nuevo como recuperación antes de crear Auth; no bloquear los pasos necesarios para recuperar un alta externa ya efectuada.
- Confirmación: confirmar_inversion_revisada_fn, antes de escribir inversión, bajo locks existentes.
- Última defensa: conversion_lead_con_inversion y controles existentes de INSERT/UPDATE terminales.
- Deshacer: deshacer_resultado_llamada toma actividad → lead; el evaluador no debe tomar locks sobre actividad después del lead y formar una espera circular.
- Tareas: cierre/cancelación toma lead → tarea. El guard final comparte el lock del lead y reevalúa después; comprobar lecturas frescas, incluso cuando hubo espera.
- No modificar objetos de public ni los guardianes/contratos del núcleo SLA como efecto colateral.

## Diseño técnico candidato

- Evaluador privado único por lote de IDs; salida sin PII, con pasos, evidencia, pendiente y acción.
- Puerta de lectura crm.recorrido_leads_fn valida actor/ámbito; máximo 100 IDs, una RPC por página.
- Lectura del cliente: estados cargando/desconocido/listo; RPC ausente no impide guardar o avanzar en Mi día.
- Configuración administrativa mínima y auditada de recorrido, separada de la política SLA: apagado, observacion, exigir. Grupo definido por inicio del ciclo desde una fecha explícita; la fecha no se reinicia al apagar/reencender. Sin excepciones recibidas desde el cliente.
- Reversión: cambiar solo el modo del recorrido. No down-migration, borrado de evidencia ni relajación de permisos financieros.
- La configuración pertenece al CRM de esta instalación: empresa del contrato no es tenant de lead y no se aceptan negocio_id/rol/empresa del cliente como autorización. El modelo actual no contiene tablas/columnas de negocio_id, organizacion_id o tenant_id. Resolver forma de almacenamiento en revisión de arquitectura antes de escribir la migración.
- Captura al confirmar en columna JSON de la solicitud o registro auditable equivalente con referencias mínimas, no copias de datos personales.
- Oficina: tarea inmediata + actividad real de asistencia como gesto compuesto explícito, marcada únicamente por el núcleo. Reutilizar el recibo de cierre y una clave estable; comprobar que un replay con datos distintos no altera capital ni siguiente tarea.

## Pruebas exigidas

Matriz: rol/ámbito/empresa, origen referido/base, lead sin tareas, reasignado/reabierto, contacto deshecho, varias citas, cita futura, no_show/cancelada/reprogramada, oficina, error de lectura/guardado, doble envío, respuesta perdida, borrador invalidado, acceso ya creado, confirmación vs deshacer/cancelar, anulación posterior y operaciones de cliente existente.

Rendimiento: banco sintético con al menos 4.000 leads operativos y 60.000 actividades (aprox. 2× censo actual), página de 50 y máximo 100 IDs; objetivo inicial p95 < 300 ms para la RPC en el banco local, registrar máquina/datos/plan y no extrapolar a producción. Sin consulta por tarjeta ni agregación del universo completo para un listado paginado.

Criterio de cierre de fase 1: contratos cerrados con fuente verificable, inventario de rutas completo, revisión de arquitectura de Claude evaluada por Codex y correcciones documentadas. No declarar PASS de runtime por haber escrito este contrato.



LIVE SOURCE private.trg_leads_guard_tenencia.sql
CREATE OR REPLACE FUNCTION private.trg_leads_guard_tenencia()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_rol_actor text;
  v_entra_terminal boolean;
begin
  if new.vendedor_id is not null and new.asignado_supervisor_id is not null then
    raise exception 'Un lead no puede tener analista y bandeja al mismo tiempo';
  end if;

  -- Solo un miembro plenamente activo puede recibir responsabilidad nueva.
  if new.vendedor_id is not null
     and (
       tg_op = 'INSERT'
       or new.vendedor_id is distinct from old.vendedor_id
       or (old.activo = false and new.activo = true)
       or (
         old.etapa in ('convertido', 'descartado')
         and new.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
       )
     )
     and not private.es_destino_crm_activo(
       new.vendedor_id,
       array['vendedor', 'supervisor']::text[]
     ) then
    raise exception 'El analista destino no existe, no esta activo o no puede recibir leads';
  end if;

  -- Una bandeja pertenece exclusivamente a un supervisor plenamente activo.
  if new.asignado_supervisor_id is not null
     and (
       tg_op = 'INSERT'
       or new.asignado_supervisor_id is distinct from old.asignado_supervisor_id
       or (old.activo = false and new.activo = true)
       or (
         old.etapa in ('convertido', 'descartado')
         and new.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
       )
     )
     and not private.es_destino_crm_activo(
       new.asignado_supervisor_id,
       array['supervisor']::text[]
     ) then
    raise exception 'La bandeja destino no pertenece a un supervisor activo';
  end if;

  -- Un usuario CRM no gerencial no puede liberar un lead a la cola global.
  if new.vendedor_id is null
     and new.asignado_supervisor_id is null
     and (
       tg_op = 'INSERT'
       or old.vendedor_id is not null
       or old.asignado_supervisor_id is not null
     )
     and auth.uid() is not null then
    v_rol_actor := private.rol_crm(auth.uid());
    if v_rol_actor is distinct from 'gerencia' then
      raise exception 'Solo Gerencia puede dejar un lead en la cola global';
    end if;
  end if;

  if tg_op = 'INSERT' then
    new.creado_en := statement_timestamp();
    new.actualizado_en := new.creado_en;
    new.ciclo_actual := 1;
    return new;
  end if;

  new.ciclo_actual := old.ciclo_actual;

  if old.etapa = 'convertido' and new.etapa is distinct from old.etapa then
    raise exception 'Un lead convertido no se puede reabrir';
  end if;

  if old.etapa = 'descartado' and new.etapa is distinct from old.etapa then
    if new.etapa <> 'nuevo' then
      raise exception 'Un lead descartado solo se puede reabrir en etapa nuevo';
    end if;
    new.ciclo_actual := old.ciclo_actual + 1;
  end if;

  v_entra_terminal := old.etapa not in ('convertido', 'descartado')
    and new.etapa in ('convertido', 'descartado');

  if v_entra_terminal
     and (
       new.vendedor_id is distinct from old.vendedor_id
       or new.asignado_supervisor_id is distinct from old.asignado_supervisor_id
     ) then
    raise exception 'Asigna al responsable antes de cerrar el lead';
  end if;

  if v_entra_terminal and old.activo = false then
    raise exception 'Reactiva el lead antes de cerrarlo';
  end if;

  if v_entra_terminal and old.activo = true and new.activo = false then
    raise exception 'Cierra o desactiva el lead en operaciones separadas';
  end if;

  if old.etapa <> 'convertido' and new.etapa = 'convertido'
     and old.vendedor_id is null then
    raise exception 'Asigna un analista antes de convertir el lead';
  end if;

  if old.activo = true and new.activo = false
     and (
       new.vendedor_id is distinct from old.vendedor_id
       or new.asignado_supervisor_id is distinct from old.asignado_supervisor_id
     ) then
    raise exception 'Reasigna o desactiva el lead en operaciones separadas';
  end if;

  return new;
end;
$function$


LIVE SOURCE private.trg_sla_tarea_contexto.sql
CREATE OR REPLACE FUNCTION private.trg_sla_tarea_contexto()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_lead crm.leads%rowtype;v_anterior text:=coalesce(current_setting('crm.sla_contexto_writer',true),'off');
begin
  if new.lead_id is null then return null;end if;
  -- Reutiliza el lock fuerte adquirido en BEFORE INSERT, incluso con auth NULL.
  select * into strict v_lead from crm.leads where id=new.lead_id for update;
  if not exists(select 1 from crm.lead_sla_ciclos where lead_id=new.lead_id and ciclo_n=v_lead.ciclo_actual) then
    raise exception 'Falta ciclo causal para tarea nueva' using errcode='23514';end if;
  perform set_config('crm.sla_contexto_writer','evento',true);
  insert into crm.tarea_sla_contexto(tarea_id,lead_id,ciclo_n,fuente)
    values(new.id,new.lead_id,v_lead.ciclo_actual,'evento');
  perform set_config('crm.sla_contexto_writer',v_anterior,true);
  return null;
end;
$function$


LIVE SOURCE private.trg_gestion_lead_serializada.sql
CREATE OR REPLACE FUNCTION private.trg_gestion_lead_serializada()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_autorizado boolean := false;
begin
  -- Los writers internos (auth.uid NULL) y los eventos de sistema ya tienen
  -- sus propios gates. No deben quedar atrapados al dispararse desde un UPDATE
  -- del lead que ya posee el lock.
  if v_actor is null
     or (
       tg_table_name = 'actividades'
       and new.tipo in ('cambio_etapa', 'reasignacion', 'conversion')
     ) then
    return new;
  end if;

  -- `crm.tareas` también admite tareas de perfil sin lead; no participan en
  -- una devolución y conservan su policy existente.
  if new.lead_id is null then
    return new;
  end if;

  -- `creado_en` no es inmutable durante INSERT en las tablas heredadas. Un
  -- asesor podría enviar una fecha anterior a la asignación y hacer invisible
  -- su gestión para el candado de devolución. Los inserts manuales reciben un
  -- sello del servidor; writers internos con auth.uid NULL conservan backfill.
  -- Se preservan antes los contratos heredados de NOT NULL/fecha finita: el
  -- sello no debe convertir un payload imposible en una escritura válida.
  if new.creado_en is null then
    raise exception 'La fecha de creación de la gestión es obligatoria'
      using errcode = '23502';
  end if;
  if not pg_catalog.isfinite(new.creado_en) then
    raise exception 'La fecha de creación de la gestión debe ser finita'
      using errcode = '23514';
  end if;

  if new.creado_por is distinct from v_actor then
    raise exception 'La gestión debe quedar atribuida al usuario autenticado'
      using errcode = '42501';
  end if;

  v_rol := private.rol_crm(v_actor);
  select true
    into v_autorizado
  from crm.leads lead
  where lead.id = new.lead_id
    and lead.activo = true
    and (
      v_rol = 'gerencia'
      or lead.vendedor_id = v_actor
      or (
        v_rol = 'supervisor'
        and (
          lead.vendedor_id in (
            select private.vendedor_ids_visibles(v_actor)
          )
          or (
            lead.vendedor_id is null
            and lead.asignado_supervisor_id in (
              select private.vendedor_ids_visibles(v_actor)
            )
          )
        )
      )
    )
  for update;

  if v_autorizado is distinct from true then
    raise exception 'El lead cambió de responsable; recarga antes de registrar la gestión'
      using errcode = '42501';
  end if;
  -- F2.b (b2): el veto de la PERSONA bloquea el SEGUIMIENTO (contrato §7.3): los tipos
  -- de CONTACTO y las tareas. Las notas administrativas (corrección/anulación de un
  -- cierre, fusión, reingreso) no son contacto y siguen entrando; la nota de las RPC
  -- de veto entra además bajo la válvula op_privilegiada.
  if not coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false)
     and (tg_table_name = 'tareas'
          or new.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada'))
     and private.persona_vetada(new.lead_id) then
    raise exception '%: no se registra seguimiento', 'La persona tiene la restricción «No insistir»'
      using errcode = 'P0429';
  end if;

  -- El sello se toma DESPUÉS del lock y de la revalidación. `statement_timestamp`
  -- conservaría la hora previa a una espera: si una derivación ganara durante
  -- esa espera, la gestión podría quedar fechada antes del episodio y el
  -- supervisor aún la vería como reversible. `clock_timestamp` registra el
  -- orden causal ya serializado por el lock.
  new.creado_en := pg_catalog.clock_timestamp();

  return new;
end;
$function$


LIVE SOURCE private.inversion_persona_contexto_para.sql
CREATE OR REPLACE FUNCTION private.inversion_persona_contexto_para(p_persona uuid, p_lead uuid, p_solicitud uuid, p_busqueda uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_i crm.inversionistas%rowtype;
  v_p public.perfiles%rowtype;
  v_l crm.leads%rowtype;
  v_doc crm.inversionista_identificadores%rowtype;
  v_leads uuid[];
  v_nombre text;
  v_persona uuid;
begin
  v_persona := (private.inversion_persona_autorizada_para(p_persona,p_solicitud,p_busqueda)->>'inversionista_id')::uuid;
  select * into v_i from crm.inversionistas where id=v_persona for update;
  if v_i.estado <> 'activo' or v_i.no_contactar then
    raise exception 'La persona no permite nuevas inversiones: revisa su estado o No insistir' using errcode='P0429';
  end if;
  if v_i.responsable_relacion_id is null or not exists (
    select 1 from crm.equipo e join public.perfiles p on p.id=e.perfil_id
    where e.perfil_id=v_i.responsable_relacion_id and e.activo and p.activo
      and e.rol_crm in ('vendedor','supervisor')
  ) then
    raise exception 'Asigna un responsable comercial activo antes de registrar la inversión' using errcode='P0409';
  end if;
  select * into v_doc from crm.inversionista_identificadores
  where inversionista_id=v_persona and estado='vigente' and verificado
  order by case tipo_documento when 'DNI' then 1 when 'CE' then 2 else 3 end,id limit 1;
  if not found then
    raise exception 'La inversión requiere un documento verificado' using errcode='P0409';
  end if;
  if v_i.perfil_id is not null then
    select * into v_p from public.perfiles where id=v_i.perfil_id for share;
    if not found or v_p.activo is not true or v_p.rol <> 'cliente' then
      raise exception 'El perfil Avance requiere revisión antes de operar' using errcode='P0409';
    end if;
    if not private.documento_es_de_identidad(v_persona,v_p.tipo_documento,v_p.dni) then
      raise exception 'El documento del perfil requiere conciliación con la persona' using errcode='P0409';
    end if;
  end if;
  select array_agg(distinct id order by id) into v_leads from (
    select l.id from crm.leads l where l.inversionista_id=v_persona
    union select il.lead_id from crm.inversionista_leads il
      where il.inversionista_id=v_persona and il.rol='canonico'
  ) l;
  if coalesce(cardinality(v_leads),0)>1 then
    raise exception 'Hay más de un lead canónico; corresponde conciliación de identidad' using errcode='P0409';
  end if;
  if cardinality(v_leads)=1 then
    -- NOWAIT mantiene el orden de la corrección/fusión y evita esperar una reasignación que ya tomó el lead.
    select * into v_l from crm.leads where id=v_leads[1] for share nowait;
    if v_l.no_contactar then
      raise exception 'La persona tiene No insistir en su lead' using errcode='P0429';
    end if;
    if p_lead is null and v_l.etapa <> 'convertido' then
      raise exception 'Completa la conversión inicial antes de registrar otra inversión' using errcode='P0409';
    end if;
  end if;
  if p_lead is not null then
    if v_l.id is distinct from p_lead or v_l.activo is not true or
      not coalesce((private.rol_crm((select auth.uid()))='gerencia' or
        v_l.vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))),false) then
      raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode='42501';
    end if;
    if v_l.etapa in ('convertido','descartado') then
      raise exception 'El lead ya está cerrado; consulta su inversión en Cartera' using errcode='P0409';
    end if;
    if v_l.vendedor_id is distinct from v_i.responsable_relacion_id then
      raise exception 'El responsable de la persona y el analista del lead deben coincidir antes de invertir' using errcode='P0409';
    end if;
    if exists(select 1 from private.leads_de_personas(array[v_persona]) x where x<>p_lead)
      or exists(select 1 from crm.inversiones where inversionista_id=v_persona and es_primera_conversion) then
      raise exception 'La persona ya tiene una conversión inicial; requiere conciliación' using errcode='P0409';
    end if;
    if exists(select 1 from crm.conversion_reservas r where
      (r.lead_id=p_lead or r.inversionista_id=v_persona) and
      (r.efectos_iniciados_en is not null or r.expira_en>now()) for update nowait) then
      raise exception 'Hay una conversión anterior pendiente; revisa su acceso antes de continuar' using errcode='P0409';
    end if;
  end if;
  v_nombre := coalesce(nullif(btrim(v_p.nombre_completo),''),nullif(btrim(v_l.nombre_completo),''),
    (select ce.nombre_completo from crm.cierres_externos ce where ce.inversionista_id=v_persona order by ce.creado_en desc,ce.id desc limit 1));
  if v_nombre is null then
    raise exception 'La persona necesita un antecedente con su nombre completo' using errcode='P0409';
  end if;
  return jsonb_build_object('inversionista_id',v_i.id,'perfil_id',v_i.perfil_id,
    'responsable_id',v_i.responsable_relacion_id,'lead_id',v_l.id,
    'documento_tipo',v_doc.tipo_documento,'documento',v_doc.documento_normalizado,'nombre',v_nombre);
end;
$function$


LIVE SOURCE private.trg_sla_nucleo_entrada_guard.sql
CREATE OR REPLACE FUNCTION private.trg_sla_nucleo_entrada_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_lead uuid;v_evento crm.actividades%rowtype;v_etapa crm.lead_sla_etapas%rowtype;
  v_regla crm.sla_politica_etapas_operacion%rowtype;v_hechos record;v_control crm.sla_operacion_control%rowtype;v_decision record;
begin
  if tg_op = 'DELETE' then
    -- Única excepción: la vía oficial crm.eliminar_lead_error_carga, y solo para una fila ya copiada en
    -- crm.leads_eliminados en ESTA transacción (ver private.borrado_lead_error_autoriza).
    if private.borrado_lead_error_autoriza(tg_table_name, pg_catalog.to_jsonb(old)) then return old; end if;
  end if;
  if tg_op in ('DELETE','TRUNCATE') then raise exception 'Los hechos SLA no se borran' using errcode='55000';end if;
  if current_user::regrole::oid<>(select relowner from pg_class where oid=tg_relid) then
    raise exception 'Solo el nucleo escribe entradas SLA' using errcode='42501';end if;
  if tg_table_name='sla_operacion_control' then
    if tg_op<>'UPDATE' or current_setting('crm.sla_control_writer',true) is distinct from 'on' then
      raise exception 'El modo solo cambia por su comando' using errcode='55000';end if;
    if (old.primera_activacion_en is not null and
       (new.primera_activacion_en is distinct from old.primera_activacion_en
        or new.politica_adopcion_id is distinct from old.politica_adopcion_id))
      or new.revision<>old.revision+1 then
      raise exception 'Adopcion inmutable o revision invalida' using errcode='55000';end if;
    if new.politica_adopcion_id is not null and not private.sla_reglas_operacion_validas(
      (select jsonb_agg(to_jsonb(r)-'politica_id') from crm.sla_politica_etapas_operacion r where r.politica_id=new.politica_adopcion_id)) then
      raise exception 'La adopcion requiere cuatro reglas completas' using errcode='23514';end if;
  elsif tg_op='UPDATE' then
    raise exception 'Entrada SLA inmutable' using errcode='55000';
  elsif tg_table_name='sla_politica_etapas_operacion' then
    if current_setting('crm.sla_config_writer',true) is distinct from 'on'
      or exists(select 1 from crm.lead_sla_etapas e where e.politica_id=new.politica_id) then
      raise exception 'Reglas solo durante publicacion, nunca sobre episodios existentes' using errcode='55000';end if;
  elsif tg_table_name='tarea_sla_contexto' then
    if ((new.fuente='evento' and pg_trigger_depth()>=2
               and current_setting('crm.sla_contexto_writer',true)='evento')
         or (new.fuente='reconstruido' and current_setting('crm.sla_contexto_writer',true)='reconstruido')) is distinct from true then
      raise exception 'Contexto solo por captura o reconstruccion privada' using errcode='55000';end if;
    select lead_id into v_lead from crm.tareas where id=new.tarea_id;
    if v_lead is distinct from new.lead_id then
      raise exception 'Contexto ajeno a tarea' using errcode='23514';end if;
  elsif tg_table_name='lead_sla_etapa_ajustes' then
    if (pg_trigger_depth()<2 and current_setting('crm.sla_finalizando_gesto',true) is distinct from 'on')
      or current_setting('crm.sla_ajuste_writer',true) is distinct from 'on' then
      raise exception 'Ajuste solo desde evento de gestion' using errcode='55000';end if;
    select * into strict v_evento from crm.actividades where id=new.origen_actividad_id;
    select * into strict v_etapa from crm.lead_sla_etapas where id=new.etapa_sla_id;
    select * into strict v_regla from crm.sla_politica_etapas_operacion
      where politica_id=v_etapa.politica_id and etapa=v_etapa.etapa;
    select * into strict v_control from crm.sla_operacion_control where id;
    select * into strict v_hechos from private.sla_etapa_hechos(v_etapa.id,v_etapa.lead_id,v_etapa.ciclo_n,v_etapa.etapa);
    select * into strict v_decision from private.sla_evaluar_prorroga(v_etapa.etapa,v_evento.tipo,v_evento.creado_por,
      v_etapa.finalizado_en is null,v_control.modo,v_control.primera_activacion_en,v_evento.creado_en,
      v_etapa.limite_en+v_hechos.minutos*interval '1 minute',v_etapa.limite_en+v_regla.tope_extra_minutos*interval '1 minute',
      v_regla.prorroga_minutos,v_regla.prorroga_max,v_hechos.usadas,false);
    if v_evento.lead_id<>v_etapa.lead_id or v_evento.creado_por is distinct from new.creado_por
      or auth.uid() is distinct from new.creado_por or not v_decision.elegible
      or new.secuencia<>v_hechos.usadas+1 or new.minutos_reales<>v_decision.minutos_reales
      or new.limite_antes<>v_etapa.limite_en+v_hechos.minutos*interval '1 minute'
      or new.limite_despues<>v_decision.limite_despues then
      raise exception 'Ajuste fuera de causa, secuencia o presupuesto' using errcode='23514';end if;
  end if;
  return new;
end;
$function$


LIVE SOURCE private.sla_ejecutar_comando.sql
CREATE OR REPLACE FUNCTION private.sla_ejecutar_comando(p_operacion uuid, p_comando text, p_sujeto uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid(); v_lead uuid; v_recibo crm.sla_operacion_recibos%rowtype;
  v_respuesta jsonb; v_actividad uuid; v_siguiente uuid; v_fecha timestamptz; v_etapa text;
  v_gesto_sla jsonb;
  v_tarea crm.tareas%rowtype;
begin
  if v_actor is null or private.rol_crm(v_actor) is null
      or private.rol_crm(v_actor) not in ('vendedor','supervisor','gerencia') then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  if p_operacion is null or p_sujeto is null or p_comando is null
      or p_comando not in ('registrar_actividad','cerrar_tarea','cerrar_reunion','reprogramar_reunion','reprogramar_tarea')
      or p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'Operacion de gestion invalida' using errcode='22023';
  end if;
  if p_comando='registrar_actividad' then v_lead:=p_sujeto;
  else select t.lead_id into v_lead from crm.tareas t where t.id=p_sujeto and t.activo;
  end if;
  if private.sla_gestion_permitida(v_actor,v_lead) is distinct from true then
    raise exception 'Gestion no disponible en tu ambito' using errcode='42501';
  end if;

  insert into crm.sla_operacion_recibos(actor_id,operacion_id,lead_id,sujeto_id,comando,payload)
  values(v_actor,p_operacion,v_lead,p_sujeto,p_comando,p_payload)
  on conflict(actor_id,operacion_id) do nothing;
  select * into strict v_recibo from crm.sla_operacion_recibos r
  where r.actor_id=v_actor and r.operacion_id=p_operacion for update;
  if v_recibo.comando<>p_comando or v_recibo.sujeto_id<>p_sujeto
      or v_recibo.lead_id<>v_lead or v_recibo.payload is distinct from p_payload then
    raise exception 'Esta operacion ya corresponde a otro contenido' using errcode='23505';
  end if;
  if private.sla_gestion_permitida(v_actor,v_lead) is distinct from true then
    raise exception 'Gestion no disponible en tu ambito' using errcode='42501';
  end if;
  if v_recibo.respuesta is not null then return v_recibo.respuesta; end if;

  perform 1 from crm.leads l where l.id=v_lead for update;
  if private.sla_gestion_permitida(v_actor,v_lead) is distinct from true then
    raise exception 'El lead cambio de responsable; recarga la ficha' using errcode='42501';
  end if;
  if p_comando='registrar_actividad' then
    if p_payload->>'tipo' is null or p_payload->>'tipo' not in
       ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada','nota') then
      raise exception 'Tipo de gestion invalido' using errcode='22023';
    end if;
    if exists(select 1 from crm.leads l where l.id=v_lead and l.etapa in ('convertido','descartado')) then
      raise exception 'El lead esta cerrado' using errcode='22023';
    end if;
    v_gesto_sla:=private.sla_gesto_abrir(v_lead);
    insert into crm.actividades(id,lead_id,tipo,detalle,creado_por)
    values(p_operacion,v_lead,p_payload->>'tipo',p_payload->>'detalle',v_actor)
    returning id,creado_en into v_actividad,v_fecha;
    -- El writer de agenda toma del contexto solo lead/perfil. No se inventa
    -- una tarea anterior ni un enlace de reprogramacion para el primer plan.
    v_tarea.lead_id:=v_lead;
    v_siguiente:=private.crear_siguiente_tarea(v_tarea,nullif(p_payload->'siguiente','null'::jsonb),null,v_actor);
    perform private.sla_gesto_cerrar(v_actividad,v_gesto_sla);
    select l.etapa into v_etapa from crm.leads l where l.id=v_lead;
    v_respuesta:=jsonb_build_object('ok',true,'actividad_id',v_actividad,'creado_en',v_fecha,'etapa',v_etapa,'siguiente_id',v_siguiente);
  elsif p_comando='cerrar_tarea' then
    v_respuesta:=crm.cerrar_tarea(p_sujeto,p_payload->>'estado',p_payload->>'resultado_tipo',
      p_payload->>'resultado_detalle',nullif(p_payload->'siguiente','null'::jsonb),
      p_payload->>'resultado_reunion',p_payload->>'motivo_no_realizada');
  elsif p_comando='cerrar_reunion' then
    v_respuesta:=crm.cerrar_reunion(p_sujeto,p_payload->>'estado',p_payload->>'resultado_reunion',
      p_payload->>'motivo_no_realizada',p_payload->>'detalle',nullif(p_payload->'siguiente','null'::jsonb));
  elsif p_comando='reprogramar_reunion' then
    v_respuesta:=crm.reprogramar_reunion(p_sujeto,(p_payload->>'vence_en')::timestamptz,
      (p_payload->>'nueva_id')::uuid);
  else
    select * into v_tarea from crm.tareas t where t.id=p_sujeto and t.lead_id=v_lead
      and t.activo and t.estado='pendiente' and t.tipo<>'reunion' for update;
    if not found then raise exception 'Tarea no disponible' using errcode='22023'; end if;
    v_fecha:=(p_payload->>'vence_en')::timestamptz;
    if v_fecha is null or not isfinite(v_fecha) or v_fecha<timestamptz '2026-01-01Z'
        or v_fecha>=timestamptz '2100-01-01Z' then
      raise exception 'Fecha de tarea invalida' using errcode='22023';
    end if;
    if v_fecha=v_tarea.vence_en then raise exception 'La nueva fecha debe ser distinta' using errcode='22023'; end if;
    update crm.tareas set vence_en=v_fecha,confirmada_en=null where id=p_sujeto;
    v_respuesta:=jsonb_build_object('ok',true,'tarea_id',p_sujeto);
  end if;
  if coalesce((v_respuesta->>'ok')::boolean,false) is not true then
    raise exception 'El servidor no confirmo la gestion' using errcode='23514';
  end if;
  v_respuesta:=v_respuesta||jsonb_build_object('version',2,'operacion_id',p_operacion,'lead_id',v_lead,'comando',p_comando);
  update crm.sla_operacion_recibos set respuesta=v_respuesta,confirmado_en=clock_timestamp()
    where actor_id=v_actor and operacion_id=p_operacion;
  return v_respuesta;
end;
$function$

No product tests run yet; contract-only phase. Return concise actionable architecture corrections. Maximum 1 review now; implementation high-risk review later with new evidence.
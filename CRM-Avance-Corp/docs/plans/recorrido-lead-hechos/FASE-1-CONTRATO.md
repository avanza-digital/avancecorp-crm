# Fase 1 · Contrato del recorrido por hechos

Base de código: Main 6ace3d441bd874a1e06613ee5718b1023e08c39d. Catálogo de producción leído el 18/10/2026; cuerpos en evidencia/. Este documento define implementación y pruebas, no autoriza activación productiva.

**Aclaración vinculante del usuario durante el goal:** «el objetivo es que no convierta a clientes sin marcar que ya vino a cita y ya tuvo una entrevista». El candado de primera conversión exige asistencia declarada y entrevista cerrada, vinculadas a la misma cita del ciclo vigente. El servidor comprueba el registro, no presencia física. Gestión/contacto se muestran como guía comercial; no son bloqueos adicionales si la asistencia y la entrevista ya están demostradas. Esta decisión sustituye el requisito anterior de contacto previo obligatorio.

## Decisiones sustentadas

1. **Ciclo:** usar crm.leads.ciclo_actual y crm.lead_sla_ciclos. private.trg_leads_guard_tenencia fija 1 al nacer, lo conserva en reasignaciones, lo incrementa exclusivamente al salir de descartado hacia nuevo, e impide reabrir convertido. private.trg_leads_sla_global sella el inicio; private.trg_leads_sla_versionado crea su fila. tarea_sla_contexto deriva del ciclo del lead, no lo define.
2. **Primera conversión:** conservar el contrato de identidad canónica actual, compartido entre empresas. private.inversion_persona_contexto_para exige resolver una conversión inicial pendiente y rechaza otra primera conversión de la misma persona. Cambiar empresa, retirar una inversión o fusionar una identidad no reinicia el recorrido. El servidor distingue solicitudes con lead_origen_id de inversiones adicionales, renovación, upgrade y venta cruzada.
3. **Caducidad:** una evidencia vigente no vence solo por el transcurso de un SLA. Una nueva reapertura sí cambia el ciclo. Cancelar, inactivar o deshacer la evidencia retira su crédito, sin borrar historial.
4. **Condición obligatoria:** cita completada con asistencia real y resultado de entrevista registrado, del ciclo vigente y de esa misma cita. Agendar o mover de columna no basta. Gestión/contacto se conservan como información y guía, sin impedir conversión por falta de un contacto previo independiente cuando ya se cumplió asistencia+entrevista. La entrevista no inventa una llamada anterior.
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
| Cita agendada | Tarea de reunión activa del ciclo, pendiente o completada; la completada debe ser la de la asistencia acreditada | Cancelada, no_show, tarea de otro ciclo, cita aislada de la entrevista |
| Entrevista (obligatoria) | Cita completada + resultado comercial explícito (no sin_clasificar) + resultado_actividad_id + actividad reunion_realizada cuyo metadata.tarea_id concuerda, sin deshacer y sin fecha futura | Etapa propuesta_enviada, actividad de otra cita, reunión cancelada o futura |
| Convertido | Confirmación transaccional del flujo actual con inversión y recorrido válido cuando la regla es exigible | Cambiar la etapa directamente |

Un acto puede acreditar varios pasos. Con varias citas, elegir una pareja válida tarea/asistencia/entrevista; no mezclar registros de citas o ciclos distintos. Seguir la tarea efectivamente reprogramada mediante su contexto. Un recorrido puede estar habilitado para convertir con gestión/contacto anteriores sin registrar, si la asistencia y entrevista obligatorias sí están acreditadas.

## Cobertura y ambigüedad histórica

Censo de estructura (READ ONLY): 1.965 leads operativos, 0 sin fila del ciclo actual, 29.982 actividades, 11.917 tareas, 72 citas activas sin tarea_sla_contexto, 0 ciclos marcados aproximados. No es todavía el censo de elegibilidad: no se cuentan como completos por estas cifras.

Las actividades no tienen hoy una clave causal de ciclo. Se añade `crm.actividad_ciclo_contexto`, relación 1:1 inmutable, con lead, ciclo, hora del servidor y gesto de oficina opcional. Un BEFORE INSERT propio toma FOR UPDATE del lead incluso con auth NULL; el AFTER captura clock_timestamp después del lock. Así los inserts internos no compiten subiendo un bloqueo previo de FK. La metadata del cliente no define este contexto. Una base cargada que aún está dormida registra `base_sin_ciclo` y ciclo NULL: el intento previo a su reactivación no inventa un ciclo SLA. No se altera el contador de ciclos ni se duplica el hecho comercial.

Para tareas se reutiliza `tarea_sla_contexto`: el catálogo vigente confirma que su default es clock_timestamp() y que su trigger inserta después del FOR UPDATE del lead. No hace falta otra tabla de contexto para tareas. El gesto de oficina se vincula por tarea y actividad, con marca reservada escrita por el núcleo.

Para historia previa, usar vínculo de tarea/ciclo o de actividad/episodio que ya sea demostrable; un único ciclo 1 prueba pertenencia, pero no orden temporal. El siguiente_id de un resultado de llamada sellado permite demostrar la cita creada por ese contacto. No asignar un ciclo por comparación de horas únicamente ni dar por fiable la cronología de eventos internos retrospectivos. Registros sin vínculo suficiente se informan como ambiguos; no se reescriben durante la migración.

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
- Tareas y actividades: un guard propio de invalidación toma el lead con NOWAIT ante UPDATE/DELETE que afecte evidencias, también para escritores internos. Evita esperar en orden inverso fila → lead; las rutas normales ya tienen lead → fila. El guard final comparte el lock del lead y evalúa en otra sentencia con lectura VOLATILE fresca, sin bloquear actividades/tareas.
- No modificar objetos de public ni los guardianes/contratos del núcleo SLA como efecto colateral.

## Diseño técnico candidato

- Evaluador privado único por lote de IDs; salida sin PII, con pasos, evidencia, pendiente y acción.
- Puerta de lectura crm.recorrido_leads_fn valida actor/ámbito; máximo 100 IDs, una RPC por página.
- Lectura del cliente: estados cargando/desconocido/listo; RPC ausente no impide guardar o avanzar en Mi día.
- Configuración administrativa mínima y auditada de recorrido, separada de la política SLA: apagado, observacion, exigir. Grupo definido por inicio del ciclo desde una fecha explícita; la fecha no se reinicia al apagar/reencender. Sin excepciones recibidas desde el cliente.
- Reversión: cambiar solo el modo del recorrido. No down-migration, borrado de evidencia ni relajación de permisos financieros.
- La configuración pertenece al CRM de esta instalación: empresa del contrato no es tenant de lead y no se aceptan negocio_id/rol/empresa del cliente como autorización. El modelo actual no contiene tablas/columnas de negocio_id, organizacion_id o tenant_id. ADR: singleton administrativo `crm.recorrido_control`, sin tenant ficticio, RLS cerrado y auditoría existente. Cambios solo por puerta de gerencia; revisión creciente y corte inmutable tras fijarse. Primera exigencia solo para ciclos que empiecen desde esa activación o después. El guard lee FOR SHARE; el comando de cambio toma FOR UPDATE. El snapshot registra la revisión efectiva. Apagar y reencender conserva el corte.
- Captura al confirmar en columna JSON de la solicitud o registro auditable equivalente con referencias mínimas, no copias de datos personales.
- Oficina: tarea inmediata + actividad real de asistencia como gesto compuesto explícito, marcada únicamente por el núcleo. Exige analista asignado; no reasigna implícitamente ni obliga a resolver identidad de inversión para guardar una visita legítima. Usa `multiempresa_idempotencia` y helpers idem_* existentes con namespace propio y hash del payload íntegro, incluido capital estimado y siguiente tarea; delega en cerrar_reunion_v3. No cambia el dispatcher ni recibos SLA. Nunca activa op_privilegiada. Un replay distinto conserva el error P0409 existente.
- Recuperación de acceso: el flujo vigente usa solicitud.auth_claim_id/auth_contexto y la saga auth_persona en multiempresa_idempotencia. Debe probar Auth ya creado (saga o usuario con claim persistido), no basta un reclamo sin efecto. El guard de alta nueva va antes del efecto externo; la recuperación conserva los datos y la confirmación vuelve a validar. No usar conversion_reservas de un flujo anterior como prueba de esta saga.
- Borrado oficial por error: la nueva relación no debe romper eliminar_lead_error_carga. Sus cuatro FK se incorporan a la lista cerrada y la copia versión 3 conserva cada contexto. La puerta elimina explícitamente esos contextos antes de las tareas, con autorización de copia exacta, actor y transacción, y comprueba el número de filas. No abre DELETE al cliente ni elimina hechos por cambiar de modo.
- Una reunión suelta puede acreditar gestión, pero no contacto previo ni entrevista del recorrido. “Sin fecha futura” compara tareas.vence_en con la hora real registrada de la asistencia; una cita reprogramada debe cumplir por su nueva tarea y contexto.

## Pruebas exigidas

Matriz: rol/ámbito/empresa, origen referido/base, lead sin tareas, reasignado/reabierto, contacto deshecho, varias citas, cita futura, no_show/cancelada/reprogramada, oficina, error de lectura/guardado, doble envío, respuesta perdida, borrador invalidado, acceso ya creado, confirmación vs deshacer/cancelar, anulación posterior y operaciones de cliente existente.

Rendimiento: banco sintético con al menos 4.000 leads operativos y 60.000 actividades (aprox. 2× censo actual), página de 50 y máximo 100 IDs; objetivo inicial p95 < 300 ms para la RPC en el banco local, registrar máquina/datos/plan y no extrapolar a producción. Sin consulta por tarjeta ni agregación del universo completo para un listado paginado.

Cierre de fase 1: contrato revisado por Codex y observaciones de arquitectura resueltas en REVISION-ARQUITECTURA.md. Las rutas conocidas se cubren por puertas más guard sobre las tablas, no solo por una lista de callers. Las pruebas de las fases siguientes deben demostrar esos contratos; este cierre documental no declara PASS de runtime.

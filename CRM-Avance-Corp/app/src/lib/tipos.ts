import type { Moneda } from './format'
import type { Rol } from './roles'

// Pipeline de inversión (espejo del CHECK de crm.leads.etapa)
export const ETAPAS = [
  { k: 'nuevo', label: 'Nuevo', color: '#8b95a7' },
  { k: 'contactado', label: 'Contactado', color: '#2563eb' },
  { k: 'reunion_agendada', label: 'Reunión agendada', color: '#7c3aed' },
  { k: 'propuesta_enviada', label: 'Propuesta enviada', color: '#d97706' },
] as const

export const TERMINALES = [
  { k: 'convertido', label: 'Convertido', color: '#111e3d' }, // ganado = navy (sin verde)
  { k: 'descartado', label: 'Descartado', color: '#dc2626' },
] as const

export type Etapa = (typeof ETAPAS)[number]['k'] | (typeof TERMINALES)[number]['k']

/** Etapas en las que un lead puede vivir/nacer (el kanban). Nunca nace terminal. */
export type EtapaActiva = (typeof ETAPAS)[number]['k']

/** Etapas terminales como set runtime — derivado de TERMINALES (fuente única). */
export const TERMINALES_K: ReadonlySet<string> = new Set(TERMINALES.map((t) => t.k))

/** Motivos del CHECK de crm.leads.motivo_descarte (F0; 'pide_credito' desde C1-bis).
 *  Descartar SIEMPRE lleva motivo. */
export type MotivoDescarte =
  | 'sin_interes'
  | 'sin_fondos'
  | 'competencia'
  | 'no_responde'
  | 'datos_invalidos'
  | 'pide_credito'
  | 'otro'

/** Tipos de actividad del timeline (espejo del CHECK de crm.actividades.tipo). */
export type TipoActividad =
  | 'llamada_realizada'
  | 'llamada_no_contestada'
  | 'whatsapp_enviado'
  | 'whatsapp_recibido'
  | 'reunion_realizada'
  | 'nota'
  | 'cambio_etapa'
  | 'reasignacion'
  | 'conversion'

/** Tipos que SOLO emite el store al mutar (espejo del veto de actividades_insert). */
export const TIPOS_AUTO = ['cambio_etapa', 'reasignacion', 'conversion'] as const satisfies readonly TipoActividad[]

/** Set runtime de los tipos automáticos — derivado de TIPOS_AUTO (fuente única). */
export const TIPOS_AUTO_K: ReadonlySet<string> = new Set(TIPOS_AUTO)

/** Actividades que el usuario registra a mano (las automáticas SOLO las emite el store). */
export type TipoActividadManual = Exclude<TipoActividad, (typeof TIPOS_AUTO)[number]>

/**
 * GESTIÓN registrada sobre el lead. El nombre histórico TIPOS_CONTACTO se
 * conserva por compatibilidad, pero incluye intentos sin respuesta.
 *
 * ESPEJO EXACTO del índice `crm.actividades_contacto_episodio_idx` y de
 * la primera-gestión del SLA versionado — la BD ya define este conjunto y aquí
 * NO se reinventa. Si allá cambia, cambia aquí (y al revés): son la misma regla.
 *
 * Es una LISTA BLANCA a propósito, no "todo lo que no sea automático": si
 * mañana se añade un tipo nuevo de actividad de sistema, no debe colarse en
 * silencio como si alguien hubiera contactado al cliente.
 *
 * `nota` queda FUERA por decisión de Miguel (2026-07-25): escribir una nota
 * interna no es haber hablado con la persona, y el lead debe seguir gritando
 * en la cola hasta que alguien lo llame de verdad.
 */
export const TIPOS_CONTACTO = [
  'llamada_realizada',
  'llamada_no_contestada',
  'whatsapp_enviado',
  'whatsapp_recibido',
  'reunion_realizada',
] as const satisfies readonly TipoActividad[]

/** Set runtime de los tipos de contacto — derivado de TIPOS_CONTACTO (fuente única). */
export const TIPOS_CONTACTO_K: ReadonlySet<string> = new Set(TIPOS_CONTACTO)

/**
 * CONVERSACIÓN — el cliente estuvo del otro lado. SUBCONJUNTO ESTRICTO de
 * TIPOS_CONTACTO, y espejo del `WHEN` de `trg_zz_actividades_avance_etapa`.
 *
 * La diferencia con TIPOS_CONTACTO no es un matiz, son dos preguntas distintas:
 *   · TIPOS_CONTACTO responde «¿el asesor TRABAJÓ el lead?» → mide esfuerzo, y
 *     de eso viven el SLA y la cola (un intento fallido SÍ es trabajo).
 *   · TIPOS_CONVERSACION responde «¿el cliente RESPONDIÓ?» → mide el embudo, y
 *     de eso vive la etapa (un intento fallido NO es haber hablado con nadie).
 *
 * Por qué importa que sean distintas (decisión de Miguel, 2026-07-25): si «no
 * contestó» avanzara la etapa, una gestión fallida reiniciaría indebidamente el
 * episodio de etapa versionado sobre alguien con quien nadie habló — y la
 * conversión del embudo se inflaría sola, sin que nadie mienta a propósito.
 *
 * JAMÁS fusionar los dos conjuntos, ni "simplificar" uno en términos del otro.
 */
export const TIPOS_CONVERSACION = [
  'llamada_realizada',
  'whatsapp_recibido',
  'reunion_realizada',
] as const satisfies readonly (typeof TIPOS_CONTACTO)[number][]

/** Set runtime de los tipos de conversación — derivado de TIPOS_CONVERSACION. */
export const TIPOS_CONVERSACION_K: ReadonlySet<string> = new Set(TIPOS_CONVERSACION)

/** Orígenes retirados del selector, conservados para leer leads históricos. */
const ORIGENES_HEREDADOS = [
  { k: 'web', label: 'Web' },
  { k: 'campania', label: 'Campaña' },
  { k: 'whatsapp', label: 'WhatsApp' },
] as const

/** Orígenes disponibles al crear o editar leads, con label es-PE. */
export const ORIGENES = [
  { k: 'referido', label: 'Referido' },
  { k: 'landing', label: 'LANDING' },
  { k: 'formulario', label: 'FORMULARIO' },
  { k: 'oficina', label: 'Walking' },
  { k: 'otro', label: 'Otro' },
] as const

/** Catálogo completo para lectura, validación de Supabase y métricas históricas. */
export const ORIGENES_TODOS = [...ORIGENES, ...ORIGENES_HEREDADOS] as const

export type Origen = (typeof ORIGENES_TODOS)[number]['k']

/** Type guard para datos externos (Supabase/formularios): ¿origen del catálogo? */
export function esOrigen(valor: unknown): valor is Origen {
  return typeof valor === 'string' && ORIGENES_TODOS.some((o) => o.k === valor)
}

/** Label es-PE de un origen — fuente única (antes copiado en 5 pantallas). */
export const origenLabel = (k: string): string => ORIGENES_TODOS.find((o) => o.k === k)?.label ?? k

/** Categorías de interés del CHECK de crm.leads.categoria_interes (F0). */
export const CATEGORIAS_INTERES = [
  { k: 'nuevo', label: 'Nueva inversión' },
  { k: 'renovacion', label: 'Renovación' },
  { k: 'upgrade', label: 'Aumento de inversión' },
] as const

export type CategoriaInteres = (typeof CATEGORIAS_INTERES)[number]['k']

/** Labels es-PE por categoría — fuente única (antes CAT_LABEL copiado en 3 pantallas). */
export const CAT_LABEL: Record<CategoriaInteres, string> = Object.fromEntries(
  CATEGORIAS_INTERES.map((c) => [c.k, c.label]),
) as Record<CategoriaInteres, string>

/** Labels es-PE de los tipos de evento de agenda (antes copiado en 2 pantallas). */
export const TIPO_EVENTO: Record<string, string> = {
  reunion: 'Reunión',
  llamada: 'Llamada',
  whatsapp: 'WhatsApp',
  tarea: 'Tarea',
  vencimiento: 'Vencimiento',
}

// ── Tareas de la agenda (crm.tareas — Fase A del plan v2) ─────────────────────
// Mismo catálogo que el CHECK tareas_tipo_valido. `vencimiento` NO es un tipo
// de tarea: los vencimientos de contrato son eventos DERIVADOS del cronograma.
export const TIPOS_TAREA = [
  { k: 'llamada', label: 'Llamada' },
  { k: 'whatsapp', label: 'WhatsApp' },
  { k: 'reunion', label: 'Reunión' },
  { k: 'tarea', label: 'Tarea' },
] as const

export type TipoTarea = (typeof TIPOS_TAREA)[number]['k']

/** Narrow derivado del catálogo; no replica sus literales en un segundo sitio. */
export const esTipoTarea = (valor: string): valor is TipoTarea => TIPOS_TAREA.some(({ k }) => k === valor)

/**
 * Máquina mínima (CHECK tareas_estado_valido): `pendiente` es el único estado
 * vivo. "Vencida" NO existe como estado: SE DERIVA (pendiente + vence_en <
 * ahora) — sin cron, sin drift. Reagendar un no_show crea una tarea NUEVA.
 */
export const ESTADOS_TAREA = ['pendiente', 'completada', 'cancelada', 'no_show', 'reprogramada'] as const

export type EstadoTarea = (typeof ESTADOS_TAREA)[number]

export const MODALIDADES_REUNION = [
  { k: 'presencial', label: 'Presencial' },
  { k: 'virtual', label: 'Virtual' },
] as const

export type ModalidadReunionOperativa = (typeof MODALIDADES_REUNION)[number]['k']

/** Contrato completo del CHECK; `sin_clasificar` nunca aparece en el selector. */
export const MODALIDADES_REUNION_TODAS = [...MODALIDADES_REUNION.map(({ k }) => k), 'sin_clasificar'] as const

export type ModalidadReunion = (typeof MODALIDADES_REUNION_TODAS)[number]

export const RESULTADOS_REUNION = [
  { k: 'interesado', label: 'Interesado' },
  { k: 'seguimiento', label: 'Requiere seguimiento' },
  { k: 'propuesta', label: 'Propuesta presentada' },
  { k: 'inicia_registro', label: 'Inicia registro' },
  { k: 'no_interesado', label: 'No interesado' },
] as const

export type ResultadoReunionOperativo = (typeof RESULTADOS_REUNION)[number]['k']

/** Contrato completo del CHECK; el valor legacy no es un resultado elegible. */
export const RESULTADOS_REUNION_TODOS = [...RESULTADOS_REUNION.map(({ k }) => k), 'sin_clasificar'] as const

export type ResultadoReunion = (typeof RESULTADOS_REUNION_TODOS)[number]

export const MOTIVOS_NO_REALIZADA = [
  { k: 'cancelada_cliente', label: 'Cancelada por el cliente' },
  { k: 'cancelada_empresa', label: 'Cancelada por la empresa' },
  { k: 'otro', label: 'Otro motivo' },
] as const

export type MotivoNoRealizadaManual = (typeof MOTIVOS_NO_REALIZADA)[number]['k']

/** Contrato completo del CHECK, incluidos los motivos que asigna el servidor. */
export const MOTIVOS_NO_REALIZADA_TODOS = [
  'cliente_no_asistio',
  ...MOTIVOS_NO_REALIZADA.map(({ k }) => k),
  'reprogramada',
] as const

export type MotivoNoRealizada = (typeof MOTIVOS_NO_REALIZADA_TODOS)[number]

export interface Tarea {
  id: string
  /** Exactamente UNO de los dos (CHECK tareas_un_solo_sujeto); v1 usa solo lead. */
  lead_id: string | null
  perfil_id?: string | null
  /** Tenencia espejo del lead, derivada por trigger (null = bandeja del supervisor). */
  vendedor_id?: string | null
  asignado_supervisor_id?: string | null
  tipo: TipoTarea
  titulo: string
  nota?: string | null
  /** Cuándo TOCA — aviso, no deadline (ISO timestamptz). */
  vence_en: string
  duracion_min?: number | null
  estado: EstadoTarea
  modalidad_reunion?: ModalidadReunion | null
  ubicacion_reunion?: string | null
  enlace_reunion?: string | null
  resultado_reunion?: ResultadoReunion | null
  motivo_no_realizada?: MotivoNoRealizada | null
  detalle_cierre_reunion?: string | null
  confirmada_en?: string | null // anti no-show: el cliente confirmó la cita
  reagendada_de?: string | null
  reprogramaciones: number
  activo: boolean
  creado_en: string
}

/** Respuesta autoritativa de crm.reprogramar_reunion (F2). La validación
 * runtime vive en la frontera Supabase de data/crm-api.ts. */
export interface RespuestaReprogramarReunion {
  ok: true
  tarea_nueva_id: string
  tarea_anterior_id: string
  reprogramaciones: number
}

export const MOTIVOS_DESCARTE: ReadonlyArray<{ k: MotivoDescarte; label: string }> = [
  { k: 'sin_interes', label: 'Sin interés' },
  { k: 'sin_fondos', label: 'Sin fondos' },
  { k: 'competencia', label: 'Se fue a la competencia' },
  { k: 'no_responde', label: 'No responde' },
  { k: 'datos_invalidos', label: 'Datos inválidos' },
  // C1-bis: motivo propio para MEDIR la basura de crédito que entra por la
  // landing/formulario (enterrarla en 'sin_interes' contamina la conversión).
  { k: 'pide_credito', label: 'Pide préstamo / crédito' },
  { k: 'otro', label: 'Otro' },
]

export const TIPOS_ACTIVIDAD: Record<TipoActividad, string> = {
  llamada_realizada: 'Llamada realizada',
  llamada_no_contestada: 'Llamada no contestada',
  whatsapp_enviado: 'WhatsApp enviado',
  whatsapp_recibido: 'WhatsApp recibido',
  reunion_realizada: 'Reunión realizada',
  nota: 'Nota',
  cambio_etapa: 'Cambio de etapa',
  reasignacion: 'Reasignación',
  conversion: 'Conversión',
}

/** Ítem inmutable del timeline de un lead (no se edita ni se borra). */
export interface Actividad {
  id: string
  lead_id: string
  tipo: TipoActividad
  detalle: string | null
  autor_nombre: string
  creado_en: string // ISO
}

export const ETAPA_INFO: Record<Etapa, { label: string; color: string }> = Object.fromEntries(
  [...ETAPAS, ...TERMINALES].map((e) => [e.k, { label: e.label, color: e.color }]),
) as Record<Etapa, { label: string; color: string }>

// ── Género (para el avatar humano y los datos del contacto) ───────────────────
// Binario a propósito: mapea al sexo del documento (RENIEC) y decide la silueta.
// Es OPCIONAL en el lead; sin género el avatar cae a la silueta neutra.
export type Genero = 'F' | 'M'

export const GENEROS: ReadonlyArray<{ k: Genero; label: string }> = [
  { k: 'F', label: 'Femenino' },
  { k: 'M', label: 'Masculino' },
]

/** Narrow de string → Genero (para leer selects/formularios sin castear). */
export const esGenero = (v: string): v is Genero => v === 'F' || v === 'M'

export interface Lead {
  id: string
  nombre_completo: string
  telefono: string
  /** Segundo celular de contacto importado desde la fuente, si es distinto. */
  telefono_alternativo?: string | null
  correo?: string | null
  etapa: Etapa
  origen: Origen
  monto_estimado: number
  moneda: Moneda
  categoria_interes?: CategoriaInteres | null
  vendedor_id?: string | null
  vendedor_nombre?: string | null
  /** Parkeado = vendedor_id null asignado a la bandeja de un supervisor (espejo F0). */
  asignado_supervisor_id?: string | null
  creado_en: string
  /**
   * Instante en que el VENDEDOR ACTUAL recibió el lead (null si no tiene dueño,
   * está inactivo o cerrado). Es el reloj que mide AL ASESOR: `creado_en` mide
   * cuánto lleva esperando EL CLIENTE, y entre uno y otro puede haber días de
   * cola de Rosa y bandeja del supervisor. La cola de acción usa este para no
   * pintar en rojo a quien acaba de recibir el lead. Lo sella el servidor
   * (trigger espejo del ledger `crm.lead_asignaciones`); opcional porque el
   * modo demo no lo trae y una base sin la migración tampoco.
   */
  tenencia_desde?: string | null
  /**
   * Sello del CIERRE GANADO, puesto por el trigger `trg_leads_cambio_etapa` en
   * la misma transacción en que la etapa pasa a `convertido`, e INMUTABLE para
   * el cliente API (`leads_before_update` lo restaura desde OLD salvo operación
   * privilegiada). Es el ÚNICO dato honesto del "mes de cierre": ver
   * `lib/cierres-del-mes.ts`. Opcional: null mientras el lead no se convirtió,
   * y ausente en modo demo o contra una base sin la columna.
   */
  convertido_en?: string | null
  /** Enlace opaco al contrato que acredita una inversión formalizada. */
  contrato_id?: string | null
  /** Última escritura de CUALQUIER columna (trigger `set_actualizado_en_crm`).
   *  NO es el sello del cierre: editar un lead lo reescribe. Sirve de último
   *  recurso cuando `convertido_en` no viaja (demo). */
  actualizado_en?: string
  activo: boolean
  // Espejo del esquema F0 (opcionales)
  dni?: string | null // exactamente 8 dígitos si existe
  genero?: Genero | null // decide la silueta del avatar; null → neutra
  fecha_nacimiento?: string | null // ISO 'YYYY-MM-DD' (sin hora)
  distrito?: string | null
  nota?: string | null
  motivo_descarte?: MotivoDescarte | null // solo si etapa === 'descartado'
  /**
   * "No Insista" (Ley 29571 / INDECOPI): el titular pidió no ser contactado.
   * La columna existe en `crm.leads` desde F0 y ya la respeta el reparto
   * (`crm.leads_por_repartir` la excluye), pero NO viajaba al navegador — por
   * eso el kill-switch legal de `motor-siguiente.ts` estaba muerto: nadie podía
   * pasarle el flag. Viaja desde 2026-07-25 para que ningún automatismo agende
   * insistencia contra un "No Insista". Opcional: el modo demo no lo trae.
   */
  no_contactar?: boolean | null
  /**
   * Último CONTACTO real del lead (los 5 tipos de TIPOS_CONTACTO; una nota o
   * una reasignación NO cuentan) — el dato del semáforo del kanban. Solo lo
   * sirve la página keyset de la cartera (`crm.cartera_pagina_fn`, F2): el
   * store carga el ámbito sin él y lo deriva del timeline completo. Opcional
   * por eso, y porque `null` significa «nadie lo ha contactado jamás», que es
   * distinto de «no lo sé».
   */
  ultimo_contacto_en?: string | null
}

export interface Miembro {
  perfil_id: string
  nombre_completo: string
  // OFF-ROSTER: 'directorio' es lector global del portal y 'coordinador' (C1)
  // reparte la cola sin cartera ni jerarquía. Ninguno es fila del organigrama.
  rol_crm: Exclude<Rol, 'directorio' | 'coordinador'>
  supervisor_id?: string | null
  activo: boolean
}

/**
 * Fila de la COLA de reparto (C1) — proyección de `crm.leads_por_repartir()`.
 * NO es un Lead: la RPC omite a propósito toda la PII de contacto (teléfono,
 * correo, DNI) porque el coordinador enruta, no contacta.
 */
export interface ColaLead {
  id: string
  nombre_completo: string
  distrito?: string | null
  origen: Origen
  categoria_interes?: CategoriaInteres | null
  monto_estimado: number
  moneda: Moneda
  creado_en: string
  /** C1-bis: veredicto del clasificador (trigger del INSERT). MARCA, nunca
   *  cierra: el coordinador decide leyendo el comentario. */
  clasificacion_auto?: 'posible_credito' | null
  /** C1-bis: lo que escribió el cliente, ya REDACTADO por el servidor
   *  (correo/celular/documento ocultos) y trunco a 400. */
  comentario?: string | null
}

/** Movimiento de distribución sin datos de contacto del prospecto. */
export interface HistorialDerivacion {
  actividad_id: string
  lead_id: string
  nombre_completo: string
  distrito?: string | null
  origen: Origen
  monto_estimado: number
  moneda: Moneda
  etapa_actual: Etapa
  movimiento: string
  derivado_en: string
  responsable_anterior: string
  responsable_nuevo: string
  derivado_por_nombre: string
}

/**
 * Foto agregada de la distribución actual para Coordinación. No incluye
 * etapas, capacidad ni datos de contacto: Rosa solo necesita saber cuántos
 * leads tiene cada responsable.
 */
export interface DistribucionSupervisor {
  perfil_id: string
  nombre: string
  total_leads: number
}

export interface DistribucionAnalista {
  perfil_id: string
  nombre: string
  supervisor_id?: string | null
  supervisor_nombre: string
  total_leads: number
}

export interface PanelDistribucionReparto {
  version: 1
  generado_en: string
  total_leads: number
  supervisores: DistribucionSupervisor[]
  analistas: DistribucionAnalista[]
}

/** Los dos carriles que Rosa planifica en su agenda de reparto diaria. */
export type OrigenAgendaReparto = 'landing' | 'formulario'

/** Supervisora habilitada de forma explícita para el turno Landing/Formulario. */
export interface DestinoAgendaReparto {
  perfil_id: string
  nombre: string
  alias: string
}

/** Una fila de la agenda: el plan y su evidencia real, sin exponer leads. */
export interface AsignacionAgendaReparto {
  origen: OrigenAgendaReparto
  supervisor_id: string | null
  supervisor_nombre: string | null
  supervisor_alias: string | null
  derivados: number
}

export interface DiaAgendaReparto {
  fecha: string
  asignaciones: AsignacionAgendaReparto[]
}

/** Semana de turnos para Coordinación; solo fecha, origen, destino y conteos. */
export interface AgendaRepartoDiaria {
  version: 1
  fecha_desde: string
  destinos: DestinoAgendaReparto[]
  dias: DiaAgendaReparto[]
}

/**
 * Fila de la vista de DESCARTADOS (C1-ter) — proyección de
 * `crm.leads_descartados()`. Como la cola, SIN PII de contacto. `comentario`
 * (del cliente) y `nota_descarte` (lo que Rosa escribió al cerrar) llegan
 * redactados y truncados por separado. `puede_deshacer` es un hint de UI: el
 * servidor re-valida en `deshacer_descarte`.
 */
export interface LeadDescartado {
  id: string
  nombre_completo: string
  distrito?: string | null
  origen: Origen
  categoria_interes?: CategoriaInteres | null
  monto_estimado: number
  moneda: Moneda
  creado_en: string
  clasificacion_auto?: 'posible_credito' | null
  comentario?: string | null
  nota_descarte?: string | null
  motivo_descarte?: MotivoDescarte | null
  descartado_en: string
  descartado_por_nombre: string
  es_mio: boolean
  puede_deshacer: boolean
}

/** Destino de reparto — proyección de `crm.supervisores_para_reparto()`. */
export interface SupervisorReparto {
  perfil_id: string
  nombre: string
  activo: boolean
  /** Leads que ya esperan en su bandeja (sin vendedor todavía). */
  bandeja_pendiente: number
}

export interface Yo {
  id: string
  nombre_completo: string
  rol: Rol
  /** Rol global del Portal, solo para excepciones explícitas revalidadas por servidor. */
  rol_portal?: string
  /** Capacidades vivas calculadas por `crm.mi_acceso_fn`; la RLS/RPC manda. */
  capacidades_config?: {
    puede_listar_usuarios: boolean
    puede_administrar_usuarios: boolean
    puede_organizar_jerarquia: boolean
    puede_administrar_roles: boolean
  }
  demo: boolean
  /**
   * Si su identidad puede contratar desde el CRM. La fuerza de ventas pasa por
   * su rol del portal; Gerencia pasa por su rol CRM sin convertirse en admin.
   *
   * OJO, dos límites que NO hay que olvidar:
   * 1. `crear_contrato` pide ADEMÁS que el cliente sea de tu cartera. Este flag
   *    NO lo cubre (depende del lead) — ver `seraMiCliente` en lead-drawer.
   * 2. Sigue siendo solo un hint de UX: las edge/RPC/RLS revalidan el rol CRM,
   *    la membresía activa y el alcance de la fila en el servidor.
   */
  puede_contratar: boolean
}

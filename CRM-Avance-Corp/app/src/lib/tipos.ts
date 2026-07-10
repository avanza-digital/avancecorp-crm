import type { Moneda } from './format'
import type { Rol } from './roles'

// Pipeline de inversión (espejo del CHECK de crm.leads.etapa)
export const ETAPAS = [
  { k: 'nuevo',              label: 'Nuevo',             color: '#8b95a7' },
  { k: 'contactado',         label: 'Contactado',        color: '#2563eb' },
  { k: 'reunion_agendada',   label: 'Reunión agendada',  color: '#7c3aed' },
  { k: 'propuesta_enviada',  label: 'Propuesta enviada', color: '#d97706' },
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

/** Motivos del CHECK de crm.leads.motivo_descarte (F0). Descartar SIEMPRE lleva motivo. */
export type MotivoDescarte =
  | 'sin_interes'
  | 'sin_fondos'
  | 'competencia'
  | 'no_responde'
  | 'datos_invalidos'
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

/** Orígenes del CHECK de crm.leads.origen (F0), con label es-PE. */
export const ORIGENES = [
  { k: 'referido', label: 'Referido' },
  { k: 'web', label: 'Web' },
  { k: 'whatsapp', label: 'WhatsApp' },
  { k: 'campania', label: 'Campaña' },
  { k: 'oficina', label: 'Oficina' },
  { k: 'otro', label: 'Otro' },
] as const

export type Origen = (typeof ORIGENES)[number]['k']

/** Type guard para datos externos (Supabase/formularios): ¿origen del catálogo? */
export function esOrigen(valor: unknown): valor is Origen {
  return typeof valor === 'string' && ORIGENES.some((o) => o.k === valor)
}

/** Label es-PE de un origen — fuente única (antes copiado en 5 pantallas). */
export const origenLabel = (k: string): string => ORIGENES.find((o) => o.k === k)?.label ?? k

/** Categorías de interés del CHECK de crm.leads.categoria_interes (F0). */
export const CATEGORIAS_INTERES = [
  { k: 'nuevo', label: 'Nuevo' },
  { k: 'renovacion', label: 'Renovación' },
  { k: 'upgrade', label: 'Upgrade' },
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
  vencimiento: 'Vencimiento',
}

export const MOTIVOS_DESCARTE: ReadonlyArray<{ k: MotivoDescarte; label: string }> = [
  { k: 'sin_interes', label: 'Sin interés' },
  { k: 'sin_fondos', label: 'Sin fondos' },
  { k: 'competencia', label: 'Se fue a la competencia' },
  { k: 'no_responde', label: 'No responde' },
  { k: 'datos_invalidos', label: 'Datos inválidos' },
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

export interface Lead {
  id: string
  nombre_completo: string
  telefono: string
  correo?: string | null
  etapa: Etapa
  origen: Origen
  monto_estimado?: number | null
  moneda: Moneda
  categoria_interes?: CategoriaInteres | null
  vendedor_id?: string | null
  vendedor_nombre?: string | null
  /** Parkeado = vendedor_id null asignado a la bandeja de un supervisor (espejo F0). */
  asignado_supervisor_id?: string | null
  creado_en: string
  activo: boolean
  // Espejo del esquema F0 (opcionales)
  dni?: string | null // exactamente 8 dígitos si existe
  distrito?: string | null
  nota?: string | null
  motivo_descarte?: MotivoDescarte | null // solo si etapa === 'descartado'
}

export interface Miembro {
  perfil_id: string
  nombre_completo: string
  rol_crm: Exclude<Rol, 'directorio'>
  supervisor_id?: string | null
  activo: boolean
}

export interface Yo {
  id: string
  nombre_completo: string
  rol: Rol
  demo: boolean
}

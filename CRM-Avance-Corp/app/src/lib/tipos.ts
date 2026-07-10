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
export type EtapaActiva = 'nuevo' | 'contactado' | 'reunion_agendada' | 'propuesta_enviada'

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

/** Actividades que el usuario registra a mano (las automáticas SOLO las emite el store). */
export type TipoActividadManual = Exclude<TipoActividad, 'cambio_etapa' | 'reasignacion' | 'conversion'>

/** Orígenes del CHECK de crm.leads.origen (F0), con label es-PE. */
export const ORIGENES: ReadonlyArray<{ k: string; label: string }> = [
  { k: 'referido', label: 'Referido' },
  { k: 'web', label: 'Web' },
  { k: 'whatsapp', label: 'WhatsApp' },
  { k: 'campania', label: 'Campaña' },
  { k: 'oficina', label: 'Oficina' },
  { k: 'otro', label: 'Otro' },
]

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
  origen: string
  monto_estimado?: number | null
  moneda: Moneda
  categoria_interes?: 'nuevo' | 'renovacion' | 'upgrade' | null
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

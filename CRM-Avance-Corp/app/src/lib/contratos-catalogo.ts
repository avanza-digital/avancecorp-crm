// Catálogo ÚNICO del dominio de CONTRATOS del portal (espejo de analista.js):
// estas constantes vivían COPIADAS en contratos.tsx, contrato-detalle.tsx,
// contrato-nuevo.tsx y contrato-corregir.tsx — cuatro fuentes de la misma
// verdad que ya divergían en comentarios. OJO: NO fusionar con
// CATEGORIAS_INTERES de lib/tipos.ts — aquello es dominio de LEADS (el interés
// declarado del prospecto) y solo COINCIDE en labels hoy; contratos y leads
// evolucionan por separado.
import type { EstadoContrato } from '@/lib/clientes-tipos'
import type { CategoriaContrato, ModalidadContrato } from '@/lib/cronograma'

// Categoría: valor en BD → etiqueta visible (con tilde) — espejo de analista.js.
// La lista {k,label} alimenta los <Select> de los formularios; el Record
// derivado pinta tablas y detalle. UNA fuente, dos formas.
export const CATEGORIAS_CONTRATO_UI: { k: CategoriaContrato; label: string }[] = [
  { k: 'nuevo', label: 'Nuevo' },
  { k: 'renovacion', label: 'Renovación' },
  { k: 'upgrade', label: 'Upgrade' },
]
export const CATEGORIA_LABEL = Object.fromEntries(
  CATEGORIAS_CONTRATO_UI.map((c) => [c.k, c.label]),
) as Record<CategoriaContrato, string>

// Los analistas leían «Aumentar inversión» como «modificar el contrato que el
// cliente ya tiene». No es eso: el upgrade CREA un contrato aparte que solo
// DECLARA el activo que amplía, para heredar su base de tasa y la atribución
// (crm.crear_contrato / modo rentabilidad integral). Una sola frase para las
// tres pantallas que ofrecen la operación.
export const ETIQUETA_UPGRADE = 'Registrar upgrade'
export const AYUDA_UPGRADE =
  'El upgrade abre un contrato NUEVO para el aporte adicional y toma como referencia la tasa del contrato que amplía. El contrato actual no cambia.'
export const MOTIVO_NUEVA_INVERSION_BLOQUEADA =
  'Este cliente ya tiene una inversión registrada. Si corresponde, usa un upgrade, renovación o reinversión.'

export const MODALIDADES_UI: { k: ModalidadContrato; label: string }[] = [
  { k: 'mensual', label: 'Mensual' },
  { k: 'trimestral', label: 'Trimestral' },
  { k: 'semestral', label: 'Semestral' },
  { k: 'anual', label: 'Anual' },
]
export const MODALIDAD_LABEL = Object.fromEntries(
  MODALIDADES_UI.map((m) => [m.k, m.label]),
) as Record<ModalidadContrato, string>

// El analista elige el prefijo del contrato físico y transcribe sus 6 dígitos.
// El segmento 01 no es el mes. Se conserva 2026 como opción inicial del alta.
export const PREFIJOS_CONTRATO = ['2024-01-', '2025-01-', '2026-01-'] as const
export type PrefijoContrato = (typeof PREFIJOS_CONTRATO)[number]
export const PREFIJO_CONTRATO = '2026-01-'
export const RE_SEIS_DIGITOS = /^\d{6}$/

/** Reconoce los formatos seleccionables sin reinterpretar números antiguos. */
export function separarNumeroContrato(valor: string | null | undefined): { prefijo: PrefijoContrato; numero: string } | null {
  const prefijo = PREFIJOS_CONTRATO.find((opcion) => valor?.startsWith(opcion))
  if (!prefijo || !valor) return null
  const numero = valor.slice(prefijo.length)
  return RE_SEIS_DIGITOS.test(numero) ? { prefijo, numero } : null
}

// Colores de estado sobre los tokens del CRM (no hay verde: "positivo" = azul).
// Es la paleta de la TABLA de contratos; el detalle mantiene la suya local
// (allí 'vencido' es deuda → destructive), no es una copia de esta.
export const ESTADO_COLOR: Record<EstadoContrato, string> = {
  activo: 'var(--accent)',
  vencido: 'var(--warning)',
  renovado: 'var(--chart-4)',
  retirado: 'var(--muted-foreground)',
}

export const ESTADO_CONTRATO_LABEL: Record<EstadoContrato, string> = {
  activo: 'Vigente',
  vencido: 'Vencido',
  renovado: 'Renovado',
  retirado: 'Retirado',
}

/**
 * Presets del select de plazo del portal; los años exactos sirven para el
 * interés compuesto (capitaliza anual). Es la BASE compartida: cada formulario
 * la mapea a SU forma — contrato-nuevo usa value string y le suma su opción
 * 'custom' (vencimiento manual); contrato-corregir consume los meses directo.
 */
export const PLAZOS_BASE: { meses: number; label: string; anioExacto: boolean }[] = [
  { meses: 6, label: '6 meses', anioExacto: false },
  { meses: 12, label: '1 año', anioExacto: true },
  { meses: 24, label: '2 años', anioExacto: true },
  { meses: 36, label: '3 años', anioExacto: true },
  { meses: 48, label: '4 años', anioExacto: true },
  { meses: 60, label: '5 años', anioExacto: true },
]

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

export const MODALIDADES_UI: { k: ModalidadContrato; label: string }[] = [
  { k: 'mensual', label: 'Mensual' },
  { k: 'trimestral', label: 'Trimestral' },
  { k: 'semestral', label: 'Semestral' },
  { k: 'anual', label: 'Anual' },
]
export const MODALIDAD_LABEL = Object.fromEntries(
  MODALIDADES_UI.map((m) => [m.k, m.label]),
) as Record<ModalidadContrato, string>

// Prefijo FIJO del N° de contrato: el asesor solo escribe los 6 dígitos (espejo
// de PREFIJO_CONTRATO de analista.js). Si el número no viaja, el servidor
// inventa la numeración VIEJA 'AC-2026-XXXX' — por eso el campo es obligatorio
// en ambos formularios y RE_SEIS_DIGITOS es su validación exacta.
export const PREFIJO_CONTRATO = '2026-01-'
export const RE_SEIS_DIGITOS = /^\d{6}$/

// Colores de estado sobre los tokens del CRM (no hay verde: "positivo" = azul).
// Es la paleta de la TABLA de contratos; el detalle mantiene la suya local
// (allí 'vencido' es deuda → destructive), no es una copia de esta.
export const ESTADO_COLOR: Record<EstadoContrato, string> = {
  activo: 'var(--accent)',
  vencido: 'var(--warning)',
  renovado: 'var(--chart-4)',
  retirado: 'var(--muted-foreground)',
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

/** Contrato del escenario de ejemplo compartido por las dos propuestas.
 * No representa la respuesta del servidor ni define métricas comerciales. */
export type EstadoCita = 'vencida' | 'programada' | 'realizada' | 'no_show' | 'reprogramada' | 'cancelada' | 'sistema'
export interface PersonaEjemplo { id: string; nombre: string; supervisor: string }
export interface CitaEjemplo {
  id: string
  nombre: string
  telefono: string
  analista: string
  supervisor: string
  fecha: string
  hora: string
  estado: EstadoCita
  modalidad: string
  origen: string
  moneda: 'PEN' | 'USD'
  monto: number
  resultado: string
  cerrado: boolean
  seguimiento: boolean
  nuevaFecha: string | null
  nota: string
}
export interface FiltrosCitas {
  q: string
  equipo: string
  analista: string
  periodo: string
  desde: string
  hasta: string
  estados: EstadoCita[]
  modalidad: string
  origen: string
  resultado: string
  seguimiento: string
  moneda: string
  min: string
  max: string
  sort: string
}
export const CORTE: string
export const ESTADOS: Record<EstadoCita, { label: string; short: string; icon: string; next: string }>
export const EQUIPO: PersonaEjemplo[]
export const CITAS: CitaEjemplo[]
export function defaults(): FiltrosCitas
export function rango(filtros: FiltrosCitas): [string, string]
export function normalizar(valor: unknown): string
export function fechaValida(fecha: string): boolean
export function errorFiltros(filtros: FiltrosCitas): string
export function filtrar<T extends CitaEjemplo = CitaEjemplo>(filtros: FiltrosCitas, citas?: T[]): T[]
export function ordenar<T extends CitaEjemplo>(citas: T[], orden: string): T[]
export function agruparAnalistas(citas: CitaEjemplo[]): (PersonaEjemplo & {
  total: number; realizadas: number; vencidas: number; programadas: number; noShow: number; otras: number
})[]
export function csv(citas: CitaEjemplo[]): string

// Catálogo de columnas de la Proyección y de las listas que abren sus cifras:
// lo comparten la hoja (escritorio) y las tarjetas (celular). Módulo PURO.
import { cn } from '@/lib/utils'
import { COLUMNA_DE_ORIGEN, type CitaProyectada, type ColumnaNumerica, type ColumnaProyeccion, type MetricasProyeccion, type OrigenCita } from './proyeccion'
import type { TramoProyeccion } from './proyeccion-rango'

export type TipoColumna = 'texto' | 'num' | 'monto' | 'personas'
/** `corto`: la etiqueta de la cifra en la tarjeta del celular. */
export const COLUMNAS: readonly { id: ColumnaProyeccion; titulo: string; corto: string; tipo: TipoColumna }[] = [
  { id: 'analista', titulo: 'Analista', corto: 'Analista', tipo: 'texto' },
  { id: 'citas', titulo: 'Citas', corto: 'Citas', tipo: 'num' },
  { id: 'monto', titulo: 'Monto S/', corto: 'Monto', tipo: 'monto' },
  // «Ticket cita» y «Proyectado citas»: Resultados ya llama «Ticket del mes» y «Cierre proyectado» a otras cifras.
  { id: 'ticket', titulo: 'Ticket cita S/', corto: 'Ticket cita', tipo: 'num' },
  { id: 'entrevistas', titulo: '% Entrev.', corto: '% Entrev.', tipo: 'num' },
  { id: 'conversion', titulo: '% Conv.', corto: '% Conv.', tipo: 'num' },
  { id: 'proyectado', titulo: 'Proyectado citas S/', corto: 'Proyectado citas', tipo: 'num' },
  { id: 'referidos', titulo: 'Referidos', corto: 'Referidos', tipo: 'personas' },
  { id: 'clientes', titulo: 'Clientes', corto: 'Clientes', tipo: 'personas' },
  { id: 'leads', titulo: 'Leads', corto: 'Leads', tipo: 'personas' },
]
/** Las columnas con cifra (todas menos Analista), en el orden de la hoja. */
export const CIFRAS = COLUMNAS.filter((c): c is (typeof COLUMNAS)[number] & { id: ColumnaNumerica } => c.id !== 'analista')
export const ORIGEN_DE_COLUMNA: Partial<Record<ColumnaProyeccion, OrigenCita>> = { referidos: 'referido', clientes: 'cliente', leads: 'lead' }

/** «conLead»: la base de Ticket cita y Proyectado citas (todo número se abre, también los calculados). */
export type TipoLista = 'citas' | 'monto' | 'entrevistas' | 'conversion' | 'conLead' | OrigenCita
/** Abre la lista de una cifra; `tramo`, la de una columna de tiempo. */
export type AbrirLista = (tipo: TipoLista, tramo?: string) => void
export const TITULOS_LISTA: Record<TipoLista, string> = {
  citas: 'Citas', monto: 'Monto en citas', entrevistas: 'Entrevistas', conversion: 'Entrevistas que cerraron cliente', conLead: 'Citas con lead',
  referido: 'Citas de referidos', cliente: 'Citas con clientes', lead: 'Citas con leads',
}
const ETIQUETAS_CITAS: Record<'citas' | OrigenCita, [string, string]> = {
  citas: ['cita', 'citas'], referido: ['cita de referido', 'citas de referidos'],
  cliente: ['cita con cliente', 'citas con clientes'], lead: ['cita con lead', 'citas con leads'],
}
export const etiquetaCitas = (tipo: 'citas' | OrigenCita, n: number) => ETIQUETAS_CITAS[tipo][n === 1 ? 0 : 1]
export const listaDe = (m: MetricasProyeccion, tipo: TipoLista) => tipo === 'citas' ? m.citas : tipo === 'monto' ? m.conMonto : tipo === 'conLead' ? m.citasConLead
  : tipo === 'entrevistas' ? m.entrevistas : tipo === 'conversion' ? m.convertidas : m[COLUMNA_DE_ORIGEN[tipo]]
/** Orden de toda lista de citas (y de su CSV): fecha y hora de la cita; a igualdad, el código. */
export const porFechaDeCita = (a: CitaProyectada, b: CitaProyectada) =>
  `${a.cita.fecha} ${a.cita.hora}`.localeCompare(`${b.cita.fecha} ${b.cita.hora}`) || a.cita.id.localeCompare(b.cita.id)
export const claseTramo = (t: TramoProyeccion) => cn('pc-tiempo', t.domingo && 'pc-domingo', t.hoy && 'pc-hoy', t.futuro && 'pc-futuro')

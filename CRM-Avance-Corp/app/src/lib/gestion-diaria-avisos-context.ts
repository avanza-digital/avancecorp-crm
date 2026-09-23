import { createContext, useContext } from 'react'
import type { AvisoCorte, AvisosCortes } from './gestion-diaria-avisos'

export interface AvisosGestionDiaria {
  datos: AvisosCortes | null
  cargando: boolean
  error: unknown
  errorPresentacion?: unknown
  ocupada: boolean
  recargar: () => void
  actuar: (aviso: AvisoCorte, accion: 'reconocer' | 'posponer') => Promise<void>
  registroPedido: { actor: string; dia: string; analista: string; secuencia: number } | null
  abrirRegistro: (aviso: AvisoCorte, analista: string) => void
  consumirRegistro: () => void
}
export const GestionDiariaAvisosContext = createContext<AvisosGestionDiaria | null>(null)
export const useGestionDiariaAvisos = () => useContext(GestionDiariaAvisosContext)

/** Un campo enfocado, un diálogo o una pestaña oculta aplazan la presentación. */
export function puedeInterrumpirConCorte(doc: Document): boolean {
  if (doc.visibilityState === 'hidden') return false
  if (doc.querySelector('[role="dialog"], [role="alertdialog"], [aria-modal="true"]')) return false
  const foco = doc.activeElement
  return !(foco instanceof HTMLElement && (foco.isContentEditable
    || foco.closest('input, textarea, select, [contenteditable="true"], [role="textbox"], [role="combobox"]')))
}

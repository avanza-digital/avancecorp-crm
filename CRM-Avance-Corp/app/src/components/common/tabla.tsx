// Primitivas de TABLA del CRM — extraídas de las tablas de clientes.tsx y
// cartera.tsx: envoltura con scroll horizontal propio, thead canónico y celdas
// con la densidad centralizada en DOS constantes — compactar TODAS las tablas
// del CRM es cambiar una línea aquí, no perseguir px-4 por pantalla. Mantener
// <table>/<th>/<td> semánticos REALES: los E2E navegan por
// getByRole('row'/'columnheader'), nunca por clases.
//
// Las columnas condicionales por rol siguen siendo JSX condicional en cada
// pantalla (verEquipo/puedeContratar deciden allá). El "vacío por filtro" con
// cabecera viva se resuelve con un <tr> de colSpan DENTRO del tbody (patrón de
// la comparativa de hoy/gerencia.tsx) — no es primitiva: cada pantalla pone su
// copy y su colSpan.
import type { ReactNode, TdHTMLAttributes, ThHTMLAttributes } from 'react'
import { cn } from '@/lib/utils'

// Densidad COMPACTA (pedido de Miguel): con carteras de 164+ filas la métrica
// que importa es cuántos registros entran por pantalla, no el aire de cada
// celda — py-1.5 deja la fila en ~33-37 px (antes 57+) sin tocar semántica.
/** Densidad de la cabecera — fuente ÚNICA. */
export const DENSIDAD_TH = 'px-3 py-2'
/** Densidad de las celdas — fuente ÚNICA. */
export const DENSIDAD_TD = 'px-3 py-1.5'

/** div con scroll propio + <table> semántica; el aria-label lo pone la pantalla. */
export function TablaEnvoltura({ ariaLabel, children }: { ariaLabel?: string; children: ReactNode }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm" aria-label={ariaLabel}>
        {children}
      </table>
    </div>
  )
}

/** thead canónico del CRM: UNA fila de cabecera con el estilo de la casa. */
export function TheadCrm({ children }: { children: ReactNode }) {
  return (
    <thead>
      <tr className="border-b border-border bg-muted/50 text-left text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
        {children}
      </tr>
    </thead>
  )
}

/** <th> con la densidad de la casa; variantes (text-right, hidden lg:table-cell) por className. */
export function Th({ className, ...props }: ThHTMLAttributes<HTMLTableCellElement>) {
  return <th className={cn(DENSIDAD_TH, className)} {...props} />
}

/** <td> con la densidad de la casa; variantes por className (cn mergea). */
export function Td({ className, ...props }: TdHTMLAttributes<HTMLTableCellElement>) {
  return <td className={cn(DENSIDAD_TD, className)} {...props} />
}

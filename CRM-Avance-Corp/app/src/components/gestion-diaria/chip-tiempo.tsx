// El tiempo de una fila del día, dicho en palabras y con su tono.
//
// Reemplaza al chip «Crítica» y a toda mención de «SLA» en pantalla: el analista
// lee «Quedan 40 min» o «Se pasó hace 2 días», no una sigla (regla de Miguel,
// 20/09/2026). El estado NO viaja solo en el color — el texto ya lo dice —, así
// que cumple la regla de la casa por construcción.
//
// Tamaño: el chip del diseño de Gestión Diaria (27/09/2026, Miguel: respetar la
// escala del diseño): 11,5 px en negrita y 22 px de alto. El color va por la
// variante «-text» (oscura) porque `soft` pinta sobre un tinte al 12 % y los
// tonos puros no llegan al contraste de texto (está escrito en `index.css`).
import type { JSX } from 'react'
import { Badge } from '@/components/ui/badge'
import { textoTiempoDeFila, type FilaDiaria } from '@/lib/gestion-diaria-analista'

const COLOR_TONO = {
  vencido: 'var(--destructive-text)',
  pendiente: 'var(--accent-press)',
  neutro: 'var(--muted-foreground-strong)',
} as const

export function ChipTiempo({ fila, ahora, className }: {
  fila: FilaDiaria
  ahora: number
  className?: string | undefined
}): JSX.Element {
  const { texto, tono } = textoTiempoDeFila(fila, ahora)
  return (
    <Badge
      color={COLOR_TONO[tono]}
      className={`min-h-[22px] whitespace-nowrap py-0 text-[11.5px] ${className ?? ''}`}
    >
      {texto}
    </Badge>
  )
}

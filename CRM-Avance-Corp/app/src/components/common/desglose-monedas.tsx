// desglose-monedas.tsx — la segunda línea que acompaña SIEMPRE a un total unificado.
//
// Fuente única desde la decisión #10 (Miguel, 2026-08-10): el monto unificado llega a
// las filas de equipo, y sin el desglose sería una suma de monedas sin explicar —
// justo lo que la regla de la casa prohíbe. Vivía privado en ranking-vendedores.tsx.
//
// Dos detalles NO son cosméticos y se conservan tal cual:
//  1. Sin TC el texto va DESTACADO, no en gris flojo: es cuando más importa leerlo
//     (el USD quedó fuera del total). Es un hallazgo de contraste, no un capricho.
//  2. Con `usd <= 0` no se pinta nada: repetir «S/ X + US$ 0» sería ruido.
import { money, moneyK } from '@/lib/format'
import { cn } from '@/lib/utils'

/**
 * Los tokens `--gi-*` existen SOLO dentro de `.gerencia-inteligencia`
 * (components/gerencia/gerencia.css): fuera de ese contenedor no resuelven y el
 * texto se quedaría sin color. Por eso el tono es explícito y no heredado.
 */
const TONOS = {
  /** Resto del CRM: tokens de la casa. */
  casa: { conTc: 'text-muted-foreground', sinTc: 'text-foreground' },
  /** Dentro del panel de inteligencia de gerencia. */
  gerencia: { conTc: 'text-[var(--gi-muted)]', sinTc: 'text-[var(--gi-navy)]' },
  /** Filas con fondo tintado (selección): el gris flojo baja de 4,5:1 a 11 px. */
  fuerte: { conTc: 'text-muted-foreground-strong', sinTc: 'text-foreground' },
} as const

export interface DesgloseMonedasProps {
  pen: number
  usd: number
  /** TC APLICADO (el que devolvió la conversión), no el que se pidió. */
  tc: number | null
  /** Formato corto (S/ 113k) para filas densas; largo para tiles. */
  compacto?: boolean
  tono?: keyof typeof TONOS
}

export function DesgloseMonedas({
  pen,
  usd,
  tc,
  compacto = false,
  tono = 'casa',
}: DesgloseMonedasProps) {
  if (usd <= 0) return null
  // Mezclar `money` y `moneyK` en la misma celda hace que las dos cifras se lean
  // como inconsistentes: el formato lo manda quien monta la fila.
  const fmt = compacto ? moneyK : money
  const paleta = TONOS[tono]
  return (
    <span className={cn('block text-[11px] font-medium', tc != null ? paleta.conTc : paleta.sinTc)}>
      <span className="sr-only">Desglose: </span>
      {tc != null
        ? `${fmt(pen, 'PEN').replace(' ', '\u00a0')} + ${fmt(usd, 'USD').replace(' ', '\u00a0')}`
        : `+ ${fmt(usd, 'USD').replace(' ', '\u00a0')} aparte (sin TC)`}
    </span>
  )
}

import type { JSX } from 'react'
import { cn } from '@/lib/utils'
import { iniciales } from '@/lib/format'
import type { Genero } from '@/lib/tipos'

// Siluetas humanas — diseño Claude Design v2 (Avatares Silueta v2). Todas
// `fill="currentColor"`, viewBox 0 0 24 24, fondo transparente → se tiñen por CSS.
// Hay 3 PEINADOS por género: se elige uno por hash del nombre, así cada persona
// tiene su variante y no se ven todas iguales, sin perder la lectura de género.
const SILUETAS: Record<Genero, string[][]> = {
  F: [
    // ondas a los hombros
    [
      'M12 2.8c-3.5 0-5.8 2.5-5.8 5.9 0 2.2-.4 3.9-1.2 5.4-.4.8 0 1.8 1 1.9 1.5.2 2.8-.1 3.8-.8.7.3 1.4.5 2.2.5s1.5-.2 2.2-.5c1 .7 2.3 1 3.8.8 1-.1 1.4-1.1 1-1.9-.8-1.5-1.2-3.2-1.2-5.4 0-3.4-2.3-5.9-5.8-5.9z',
      'M12 15.1c-3 0-5.6 1-6.9 2.6-.7.9-.1 2.2 1.1 2.2h11.6c1.2 0 1.8-1.3 1.1-2.2-1.3-1.6-3.9-2.6-6.9-2.6z',
    ],
    // bob
    [
      'M12 3c-3.3 0-5.5 2.4-5.5 5.6 0 1.6-.15 2.9-.5 4.1-.3 1 .45 2 1.5 2h9c1.05 0 1.8-1 1.5-2-.35-1.2-.5-2.5-.5-4.1C17.5 5.4 15.3 3 12 3z',
      'M12 14c-4.5 0-7.6 2.3-7.6 5.4v.2c0 .8.6 1.4 1.4 1.4h12.4c.8 0 1.4-.6 1.4-1.4v-.2c0-3.1-3.1-5.4-7.6-5.4z',
    ],
    // moño / recogido
    [
      'M12 1.6a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3z',
      'M12 4.4a3.7 3.7 0 1 1 0 7.4 3.7 3.7 0 0 1 0-7.4z',
      'M12 14.2c-4.4 0-7.4 2.3-7.4 5.3v.2c0 .8.6 1.4 1.4 1.4h12c.8 0 1.4-.6 1.4-1.4v-.2c0-3-3-5.3-7.4-5.3z',
    ],
  ],
  M: [
    // corto clásico (con cuello)
    [
      'M12 3.7a3.9 3.9 0 1 1 0 7.8 3.9 3.9 0 0 1 0-7.8z',
      'M10.6 11v2.1c-3.3.5-5.9 2.1-6.7 4.3-.4 1 .3 2.1 1.4 2.1h13.4c1.1 0 1.8-1.1 1.4-2.1-.8-2.2-3.4-3.8-6.7-4.3V11c-.45.19-.92.29-1.4.29-.48 0-.95-.1-1.4-.29z',
    ],
    // con volumen / texturizado
    [
      'M12 2.7c-2.9 0-5 2-5.2 4.8 0 .4.3.6.7.5 1.6-.5 4-1.4 5.3-2.8.9.9 2.6 1.9 4.4 2.4.4.1.8-.2.7-.6C17.5 4.5 14.9 2.7 12 2.7z',
      'M12 4.4a3.7 3.7 0 1 1 0 7.4 3.7 3.7 0 0 1 0-7.4z',
      'M10.6 11.2v1.9c-3.3.5-5.9 2.1-6.7 4.3-.4 1 .3 2.1 1.4 2.1h13.4c1.1 0 1.8-1.1 1.4-2.1-.8-2.2-3.4-3.8-6.7-4.3v-1.9c-.45.19-.92.29-1.4.29-.48 0-.95-.1-1.4-.29z',
    ],
    // rapado (hombros anchos)
    [
      'M12 3.7a3.9 3.9 0 1 1 0 7.8 3.9 3.9 0 0 1 0-7.8z',
      'M12 13.6c-4.6 0-7.8 2.4-7.8 5.6v.2c0 .8.6 1.4 1.4 1.4h12.8c.8 0 1.4-.6 1.4-1.4v-.2c0-3.2-3.2-5.6-7.8-5.6z',
    ],
  ],
}

const COLOR_GENERO: Record<Genero, string> = { F: '#7c3aed', M: '#2563eb' }

/** Hash estable del nombre → índice de peinado dentro del set del género. */
function indicePeinado(nombre: string | null | undefined, n: number): number {
  let h = 0
  for (const c of nombre ?? '') h = (h * 31 + c.charCodeAt(0)) >>> 0
  return n > 0 ? h % n : 0
}

const BASE = 'inline-flex size-8 shrink-0 items-center justify-center overflow-hidden rounded-full'

/**
 * Avatar de persona o de equipo.
 * - Con género conocido (F/M) → silueta HUMANA tinteada por género, con su peinado
 *   por hash del nombre.
 * - Sin género (null o prop ausente) → INICIALES: distinguen a cada persona cuando
 *   no hay dato (mejor que una silueta neutra idéntica para todos). Cuando el campo
 *   género exista en la BD, cada lead pasa por sí solo a su silueta.
 */
export function Avatar({
  nombre,
  genero,
  color = 'var(--accent)',
  relleno = false,
  className,
}: {
  nombre: string | null | undefined
  genero?: Genero | null
  color?: string | undefined
  /**
   * Iniciales en blanco sobre el color pleno: marca a la persona ELEGIDA en una
   * lista (Gestión Diaria, 27/09/2026). Nunca va sola: la fila lo dice también
   * con `aria-current` y con texto.
   */
  relleno?: boolean | undefined
  className?: string | undefined
}): JSX.Element {
  // Silueta SOLO con género conocido; sin dato (null/ausente) → iniciales.
  if (genero === 'F' || genero === 'M') {
    const c = COLOR_GENERO[genero]
    const set = SILUETAS[genero]
    const paths = set[indicePeinado(nombre, set.length)] ?? []
    return (
      <span
        className={cn(BASE, className)}
        style={{ background: `color-mix(in srgb, ${c} 14%, transparent)`, color: c }}
        aria-hidden
      >
        <svg viewBox="0 0 24 24" fill="currentColor" className="size-full" aria-hidden>
          {paths.map((d, i) => (
            <path key={i} d={d} />
          ))}
        </svg>
      </span>
    )
  }

  // Modo iniciales (equipo, o cuando no aplica el género de una persona).
  return (
    <span
      className={cn(BASE, 'text-[11px] font-bold', className)}
      style={relleno ? { background: color, color: '#fff' } : { background: `color-mix(in srgb, ${color} 14%, transparent)`, color }}
      aria-hidden
    >
      {iniciales(nombre)}
    </span>
  )
}

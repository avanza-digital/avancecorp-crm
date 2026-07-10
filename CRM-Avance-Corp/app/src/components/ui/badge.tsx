import type { HTMLAttributes, CSSProperties } from 'react'
import { cn } from '@/lib/utils'

type Variante = 'soft' | 'solid' | 'outline'

/**
 * Badge tintado por color de familia (patrón chip de VITANOVA).
 * - soft (default): fondo tinte + texto del color (`.ac-chip`)
 * - solid: fondo pleno del color + texto blanco
 * - outline: borde del color + texto del color, fondo transparente
 * `dot` antepone un punto del color (estado).
 */
export function Badge({
  className,
  color,
  variant = 'soft',
  dot = false,
  style,
  children,
  ...props
}: HTMLAttributes<HTMLSpanElement> & { color?: string; variant?: Variante; dot?: boolean }) {
  const c = color ?? 'var(--accent)'
  const st: CSSProperties & { '--c'?: string } = { ...style, '--c': c }

  if (variant === 'solid') {
    st.background = c
    st.color = '#fff'
  } else if (variant === 'outline') {
    st.border = `1px solid color-mix(in srgb, ${c} 45%, transparent)`
    st.color = c
  }

  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-[11px] font-bold leading-none',
        variant === 'soft' ? 'ac-chip' : 'py-[3px]',
        className,
      )}
      style={st}
      {...props}
    >
      {dot && <span className="size-1.5 shrink-0 rounded-full" style={{ background: c }} />}
      {children}
    </span>
  )
}

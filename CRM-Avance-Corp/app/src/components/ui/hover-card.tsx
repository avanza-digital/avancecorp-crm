// Hover card sobre Radix (misma familia que Dialog/Sheet): preview al pasar el
// mouse, con posicionamiento inteligente (Popper), portal y accesibilidad
// (hover Y foco). Desktop-first; en táctil no aparece → el click sigue mandando.
import type { ReactNode } from 'react'
import * as RadixHoverCard from '@radix-ui/react-hover-card'
import { cn } from '@/lib/utils'

const KEYFRAMES = `
@keyframes acHoverIn { from { opacity: 0; transform: scale(.97) translateY(3px) } to { opacity: 1; transform: none } }
[data-slot='hover-card-content'][data-state='open'] { animation: acHoverIn 0.14s var(--ease-out-expo) both }
@media (prefers-reduced-motion: reduce) { [data-slot='hover-card-content'] { animation: none !important } }
`

export function HoverCard({
  openDelay = 350,
  closeDelay = 150,
  children,
}: {
  openDelay?: number
  closeDelay?: number
  children: ReactNode
}) {
  return (
    <RadixHoverCard.Root openDelay={openDelay} closeDelay={closeDelay}>
      {children}
    </RadixHoverCard.Root>
  )
}

/** El disparador ES su hijo (asChild): no agrega DOM, solo engancha el hover. */
export function HoverCardTrigger({ children }: { children: ReactNode }) {
  return <RadixHoverCard.Trigger asChild>{children}</RadixHoverCard.Trigger>
}

export function HoverCardContent({
  children,
  className,
  side = 'right',
  align = 'start',
  sideOffset = 8,
}: {
  children: ReactNode
  className?: string
  side?: 'top' | 'right' | 'bottom' | 'left'
  align?: 'start' | 'center' | 'end'
  sideOffset?: number
}) {
  return (
    <RadixHoverCard.Portal>
      <RadixHoverCard.Content
        data-slot="hover-card-content"
        side={side}
        align={align}
        sideOffset={sideOffset}
        collisionPadding={12}
        className={cn(
          'z-50 w-72 rounded-xl border border-border bg-card p-3 text-card-foreground shadow-[var(--shadow-pop)] outline-none',
          className,
        )}
      >
        <style>{KEYFRAMES}</style>
        {children}
      </RadixHoverCard.Content>
    </RadixHoverCard.Portal>
  )
}

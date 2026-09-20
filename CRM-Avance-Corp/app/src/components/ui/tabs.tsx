// Pestañas accesibles (patrón WAI-ARIA APG «tabs» con activación automática).
// Nace en la Fase 0 de Gestión Diaria como PRIMITIVA: hasta ahora el tablist se
// copiaba a mano en cada pantalla (ranking, supervisor, repartir, rentabilidad).
// Contrato: flechas con vuelta, Home/End, `tabIndex` móvil (roving), el panel
// activo enlazado por `aria-labelledby` y objetivos de 44 px.
import { useId, type KeyboardEvent, type ReactNode } from 'react'
import { cn } from '@/lib/utils'

export interface PestanaTabs<V extends string> {
  valor: V
  etiqueta: ReactNode
  /** Contador o marca corta junto a la etiqueta (p. ej. «12»). */
  extra?: ReactNode | undefined
}

interface TabsProps<V extends string> {
  /** Nombre del grupo para el lector de pantalla (obligatorio). */
  etiqueta: string
  pestanas: readonly PestanaTabs<V>[]
  valor: V
  onCambio: (valor: V) => void
  /** Contenido del panel activo (un solo `tabpanel`, enlazado al tab seleccionado). */
  children?: ReactNode | undefined
  className?: string | undefined
  /**
   * `grande` para pantallas de trabajo donde la letra no puede bajar de 16 px
   * y el objetivo táctil es de 48 (queja de los analistas del 20/09/2026:
   * «muchas letras pequeñas»). El default `normal` deja intacto lo que ya
   * usaba esta primitiva: ranking, supervisor, repartir y rentabilidad.
   */
  tamano?: 'normal' | 'grande' | undefined
}

const CLASES_TAMANO = {
  normal: { tab: 'min-h-11 px-3 py-2 text-xs font-semibold', extra: 'text-[11px]' },
  grande: { tab: 'min-h-12 px-4 py-2 text-base font-normal', extra: 'text-base' },
} as const

// Ids del tab y del panel de un valor (interno: el panel activo vive dentro del componente).
function idsDeTab(idBase: string, valor: string): { tab: string; panel: string } {
  return { tab: `${idBase}-tab-${valor}`, panel: `${idBase}-panel-${valor}` }
}

export function Tabs<V extends string>({ etiqueta, pestanas, valor, onCambio, children, className, tamano = 'normal' }: TabsProps<V>) {
  const medidas = CLASES_TAMANO[tamano]
  const idAuto = useId()
  const base = `tabs${idAuto.replaceAll(':', '')}`
  const valores = pestanas.map((p) => p.valor)

  const alTecla = (evento: KeyboardEvent<HTMLButtonElement>) => {
    const indice = valores.indexOf(valor)
    if (indice < 0 || valores.length === 0) return
    const siguiente = evento.key === 'ArrowRight' ? valores[(indice + 1) % valores.length]
      : evento.key === 'ArrowLeft' ? valores[(indice + valores.length - 1) % valores.length]
      : evento.key === 'Home' ? valores[0]
      : evento.key === 'End' ? valores[valores.length - 1]
      : undefined
    if (siguiente === undefined) return
    evento.preventDefault()
    onCambio(siguiente)
    document.getElementById(idsDeTab(base, siguiente).tab)?.focus()
  }

  const activo = idsDeTab(base, valor)
  return (
    <div className={cn('space-y-3', className)}>
      <div role="tablist" aria-label={etiqueta} className="flex w-full flex-col rounded-xl bg-muted p-1 min-[380px]:flex-row sm:w-fit">
        {pestanas.map((p) => {
          const ids = idsDeTab(base, p.valor)
          const seleccionada = p.valor === valor
          return (
            <button
              key={p.valor}
              id={ids.tab}
              type="button"
              role="tab"
              aria-selected={seleccionada}
              aria-controls={ids.panel}
              tabIndex={seleccionada ? 0 : -1}
              onClick={() => onCambio(p.valor)}
              onKeyDown={alTecla}
              className={cn(
                'inline-flex min-w-0 flex-1 cursor-pointer items-center justify-center gap-1.5 rounded-lg transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-accent/40 sm:flex-none',
                medidas.tab,
                seleccionada ? 'bg-white text-primary shadow-sm' : 'text-[var(--muted-foreground-strong)] hover:text-primary',
              )}
            >
              {p.etiqueta}
              {p.extra !== undefined && <span className={cn('tabular-nums font-bold text-[var(--muted-foreground-strong)]', medidas.extra)}>{p.extra}</span>}
            </button>
          )
        })}
      </div>
      {children !== undefined && (
        <div role="tabpanel" id={activo.panel} aria-labelledby={activo.tab} tabIndex={0} className="focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-accent/40">
          {children}
        </div>
      )}
    </div>
  )
}

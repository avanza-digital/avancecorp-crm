// Pestañas accesibles (patrón WAI-ARIA APG «tabs» con activación automática).
// Nace en la Fase 0 de Gestión Diaria como PRIMITIVA: hasta ahora el tablist se
// copiaba a mano en cada pantalla (ranking, supervisor, repartir, rentabilidad).
// Contrato: flechas con vuelta, Home/End, `tabIndex` móvil (roving) y el panel
// activo enlazado por `aria-labelledby`. Los objetivos miden 44–48 px en
// `segmentado`; las variantes del diseño de Gestión Diaria son más compactas
// (decisión de Miguel del 27/09/2026) y crecen a 44 px en pantallas táctiles.
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
  /**
   * Aspecto del tablist (27/09/2026, diseño de Gestión Diaria). `segmentado`
   * es el de siempre y el default: nadie que ya lo use cambia. `subrayado`
   * separa las vistas de una tarjeta con una raya bajo la activa; `pastilla`
   * pinta filtros redondos con el activo relleno. El patrón APG no cambia:
   * siguen siendo `tab`/`tabpanel`, para el lector de pantalla y las pruebas.
   */
  variante?: 'segmentado' | 'subrayado' | 'pastilla' | undefined
  /** Clases del `tabpanel` (p. ej. para que herede la altura de la tarjeta). */
  clasePanel?: string | undefined
  /**
   * El panel es una parada del tabulador (default: sí, como siempre). `false`
   * cuando el panel ARRANCA con controles: la parada vacía sobra, y con
   * pestañas anidadas se suman dos antes de llegar a algo útil (a11y, 27/09).
   */
  panelEnfocable?: boolean | undefined
}

const CLASES_TAMANO = {
  normal: { tab: 'min-h-11 px-3 py-2 text-xs font-semibold', extra: 'text-[11px]' },
  grande: { tab: 'min-h-12 px-4 py-2 text-base font-normal', extra: 'text-base' },
} as const

const CLASES_VARIANTE = {
  segmentado: {
    lista: 'flex w-full flex-col rounded-xl bg-muted p-1 min-[380px]:flex-row sm:w-fit',
    tab: 'flex-1 justify-center rounded-lg sm:flex-none',
    activa: 'bg-white text-primary shadow-sm',
    inactiva: 'text-[var(--muted-foreground-strong)] hover:text-primary',
    extra: 'text-[var(--muted-foreground-strong)]',
  },
  // La raya de la activa es una sombra INTERIOR y no un borde con margen
  // negativo: con `overflow-x-auto` ese margen se recortaba (1 de los 2 px) y
  // también el foco; por lo mismo el contorno del foco va hacia adentro.
  subrayado: {
    lista: 'flex w-full gap-6 overflow-x-auto border-b border-border',
    tab: 'shrink-0 justify-center whitespace-nowrap !px-0.5 font-semibold focus-visible:!-outline-offset-2',
    activa: 'font-bold text-[var(--accent-press)] shadow-[inset_0_-2px_0_var(--color-accent)]',
    inactiva: 'text-[var(--muted-foreground-strong)] hover:text-primary',
    extra: '',
  },
  pastilla: {
    lista: 'flex w-full flex-wrap gap-2',
    tab: 'shrink-0 justify-center whitespace-nowrap rounded-full border font-semibold',
    activa: 'border-accent bg-accent text-accent-foreground',
    inactiva: 'border-border bg-card text-[var(--muted-foreground-strong)] hover:border-border-strong hover:text-primary',
    extra: '',
  },
} as const

// Ids del tab y del panel de un valor (interno: el panel activo vive dentro del componente).
function idsDeTab(idBase: string, valor: string): { tab: string; panel: string } {
  return { tab: `${idBase}-tab-${valor}`, panel: `${idBase}-panel-${valor}` }
}

export function Tabs<V extends string>({ etiqueta, pestanas, valor, onCambio, children, className, tamano = 'normal', variante = 'segmentado', clasePanel, panelEnfocable = true }: TabsProps<V>) {
  const medidas = CLASES_TAMANO[tamano]
  const aspecto = CLASES_VARIANTE[variante]
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
      <div role="tablist" aria-label={etiqueta} className={aspecto.lista}>
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
                'inline-flex min-w-0 cursor-pointer items-center gap-1.5 transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-accent/40',
                medidas.tab,
                aspecto.tab,
                seleccionada ? aspecto.activa : aspecto.inactiva,
              )}
            >
              {p.etiqueta}
              {p.extra !== undefined && <span className={cn('tabular-nums font-bold', aspecto.extra, medidas.extra)}>{p.extra}</span>}
            </button>
          )
        })}
      </div>
      {children !== undefined && (
        <div role="tabpanel" id={activo.panel} aria-labelledby={activo.tab} tabIndex={panelEnfocable ? 0 : undefined} className={cn('focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-accent/40', clasePanel)}>
          {children}
        </div>
      )}
    </div>
  )
}

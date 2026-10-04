// Las piezas de la línea de tiempo de un lead: el riel vertical con sus hitos, la fila
// de una actividad, la racha plegada de cambios de etapa y el esqueleto de carga.
// Salieron de la ficha del lead (lead-drawer) para que la ficha de «Base para gestión»
// pinte su historial con la MISMA línea; la ficha del lead las usa sin cambiar nada
// de lo que se ve. Lo propio de cada ficha (qué título e icono lleva una actividad,
// qué filas extra van en el riel) entra por props, no se copia.
import { useEffect, useRef, useState, type ReactNode } from 'react'
import type { LucideIcon } from 'lucide-react'
import { ArrowRightLeft } from 'lucide-react'
import { cn } from '@/lib/utils'
import { presentarCitas } from '@/lib/terminologia'
import type { ItemTimeline } from '@/lib/timeline-lead'
import { TIPOS_ACTIVIDAD, type Actividad } from '@/lib/tipos'
import { haceRelativo, ICONO_ACTIVIDAD } from './actividad-visual'

/** El círculo del hito sobre el riel (icono a 14 px). Se exporta para las filas extra
 *  que cada ficha añade al riel («Lead creado», «Cargar más»…). */
export const CLASE_HITO =
  'relative z-[1] grid size-7 shrink-0 place-items-center rounded-full border border-border bg-card text-muted-foreground [&_svg]:size-3.5'

/** Cómo se presenta una actividad. Lo que no se indique toma el valor de siempre:
 *  título de `TIPOS_ACTIVIDAD`, icono de `ICONO_ACTIVIDAD` y «hace X» de `haceRelativo`. */
export interface PresentacionActividad {
  titulo?: string | undefined
  Icono?: LucideIcon | undefined
  cuando?: string | undefined
}

/** Una actividad suelta de la línea (hito + título + detalle + autor/tiempo). */
export function FilaActividad({ a, ahora, titulo, Icono, cuando }: { a: Actividad; ahora: number } & PresentacionActividad) {
  const Hito = Icono ?? ICONO_ACTIVIDAD[a.tipo]
  const esConversion = a.tipo === 'conversion'
  return (
    <li className="flex gap-2.5">
      <span className={cn(CLASE_HITO, esConversion && 'border-primary/30 text-primary')}>
        <Hito aria-hidden />
      </span>
      <div className="min-w-0 flex-1 pt-0.5">
        <p className="text-xs font-bold text-foreground">{titulo ?? TIPOS_ACTIVIDAD[a.tipo]}</p>
        {a.detalle && (
          // pre-line: una nota escrita en varias líneas se lee en varias líneas.
          <p className="mt-0.5 whitespace-pre-line break-words text-xs leading-relaxed text-muted-foreground">
            {presentarCitas(a.detalle)}
          </p>
        )}
        <p className="mt-0.5 text-[11px] text-muted-foreground">
          {a.autor_nombre} · {cuando ?? haceRelativo(a.creado_en, ahora)}
        </p>
      </div>
    </li>
  )
}

/** Racha colapsada de cambios de etapa: resumen contraído + expandir a la lista. */
export function GrupoEtapa({
  items,
  ahora,
  presentar,
}: {
  items: Actividad[]
  ahora: number
  presentar?: ((a: Actividad) => PresentacionActividad) | undefined
}) {
  const [abierto, setAbierto] = useState(false)
  // Desplegar o agrupar cambia de rama y el botón pulsado se desmonta: el foco pasa al botón que lo sustituye
  // (si no, caería en <body>; WCAG 2.4.3). Solo tras un clic del usuario, nunca al montar.
  const alternado = useRef(false)
  const boton = useRef<HTMLButtonElement>(null)
  useEffect(() => {
    if (!alternado.current) return
    alternado.current = false
    boton.current?.focus()
  }, [abierto])
  const alternar = () => {
    alternado.current = true
    setAbierto((v) => !v)
  }
  const reciente = items[0]
  if (!reciente) return null
  if (abierto) {
    return (
      <>
        {items.map((a) => (
          <FilaActividad key={a.id} a={a} ahora={ahora} {...presentar?.(a)} />
        ))}
        <li className="flex gap-2.5">
          <span className="w-7 shrink-0" aria-hidden />
          <button
            ref={boton}
            type="button"
            onClick={alternar}
            className="cursor-pointer text-[11px] font-semibold text-muted-foreground transition-colors hover:text-foreground"
          >
            Agrupar {items.length} cambios de etapa
          </button>
        </li>
      </>
    )
  }
  return (
    <li className="flex gap-2.5">
      <span className={CLASE_HITO}>
        <ArrowRightLeft aria-hidden />
      </span>
      <button
        ref={boton}
        type="button"
        onClick={alternar}
        className="min-w-0 flex-1 cursor-pointer pt-0.5 text-left"
        aria-label={`Ver los ${items.length} cambios de etapa`}
      >
        <p className="text-xs font-bold text-foreground">{items.length} cambios de etapa</p>
        {reciente.detalle && (
          <p className="mt-0.5 truncate text-xs leading-relaxed text-muted-foreground">
            Último: {presentarCitas(reciente.detalle)}
          </p>
        )}
        <p className="mt-0.5 text-[11px] text-muted-foreground">
          {reciente.autor_nombre} · {haceRelativo(reciente.creado_en, ahora)} · toca para ver todos
        </p>
      </button>
    </li>
  )
}

/** Filas grises mientras llega el historial. Ocultas a los lectores de pantalla: el
 *  estado «cargando» lo dicen el `aria-busy` del riel y la región viva de cada ficha. */
export function EsqueletoLinea({ filas = 2 }: { filas?: number }) {
  return (
    <>
      {Array.from({ length: filas }, (_, n) => (
        <li key={`esq-${n}`} className="flex gap-2.5" aria-hidden>
          <span className={CLASE_HITO} />
          <div className="min-w-0 flex-1 pt-1">
            <div className="h-3 w-40 animate-pulse rounded bg-muted motion-reduce:animate-none" />
            <div className="mt-1.5 h-2.5 w-24 animate-pulse rounded bg-muted motion-reduce:animate-none" />
          </div>
        </li>
      ))}
    </>
  )
}

/**
 * El riel (`<ol>` con la línea vertical) y sus ítems: cada actividad suelta en una
 * {@link FilaActividad} y cada racha de etapas en un {@link GrupoEtapa}. `antes` va
 * ANTES de los ítems (esqueleto, error, vacío) y `children` DESPUÉS («Ver anteriores»,
 * «Cargar más», «Lead creado»…): cada ficha pone sus filas extra sin tocar el riel.
 * `presentar` decide título, icono y tiempo de cada actividad (por defecto, los de siempre).
 */
export function LineaDeTiempo({
  items,
  ahora,
  presentar,
  'aria-label': ariaLabel,
  ariaBusy,
  antes,
  children,
}: {
  items: readonly ItemTimeline[]
  ahora: number
  presentar?: ((a: Actividad) => PresentacionActividad) | undefined
  'aria-label'?: string | undefined
  ariaBusy?: boolean | undefined
  antes?: ReactNode
  children?: ReactNode
}) {
  return (
    <ol
      className="relative space-y-4 before:absolute before:inset-y-2 before:left-[13px] before:w-px before:bg-border"
      aria-label={ariaLabel}
      aria-busy={ariaBusy}
    >
      {antes}
      {items.map((it) =>
        it.clase === 'act' ? (
          <FilaActividad key={it.act.id} a={it.act} ahora={ahora} {...presentar?.(it.act)} />
        ) : (
          <GrupoEtapa key={it.id} items={it.items} ahora={ahora} presentar={presentar} />
        ),
      )}
      {children}
    </ol>
  )
}

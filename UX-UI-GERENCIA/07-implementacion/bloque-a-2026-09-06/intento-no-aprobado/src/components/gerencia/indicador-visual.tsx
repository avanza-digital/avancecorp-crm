import { useRef, type ReactNode } from 'react'
import type { LucideIcon } from 'lucide-react'
import { ArrowUpRight, Info } from 'lucide-react'
import gsap from 'gsap'
import { useGSAP } from '@gsap/react'
import { cn } from '@/lib/utils'

type Tono = 'capital' | 'conversion' | 'citas'
export interface BarraIndicador {
  etiqueta: string
  texto: string
  valor: number | null
  color?: 'azul' | 'verde' | 'naranja' | 'meta'
}

/** Sólo presenta valores de la fuente. La escala compartida cambia el largo
 * de las barras; nunca produce un porcentaje comercial nuevo. */
export function IndicadorVisual({ etiqueta, valor, contexto, icono: Icono, tono,
  barras = [], pie, estado = 'neutro', detalle, enlace, cargando = false, className,
}: {
  etiqueta: string
  valor: string
  contexto: ReactNode
  icono: LucideIcon
  tono: Tono
  barras?: BarraIndicador[]
  pie: ReactNode
  estado?: 'neutro' | 'atencion' | 'cumplida'
  detalle?: ReactNode
  enlace?: { href: string; etiqueta: string }
  cargando?: boolean
  className?: string
}) {
  const alcance = useRef<HTMLElement>(null)
  const clave = barras.map((barra) => `${barra.etiqueta}:${barra.valor}`).join('|')
  const maximo = Math.max(1, ...barras.map((barra) => barra.valor ?? 0))
  useGSAP(() => {
    const medios = gsap.matchMedia()
    medios.add('(prefers-reduced-motion: no-preference)', () => {
      gsap.from('[data-barra-visual]', { scaleX: 0, transformOrigin: 'left center', duration: .5, stagger: .06, ease: 'power2.out', clearProps: 'transform' })
    })
    return () => medios.revert()
  }, { scope: alcance, dependencies: [clave], revertOnUpdate: true })

  return (
    <section ref={alcance} data-gi-kpi className={cn('gi-visual-card', `gi-tono-${tono}`, className)} aria-label={etiqueta} aria-busy={cargando}>
      <div className="gi-visual-heading">
        <span className="gi-visual-icon"><Icono size={21} aria-hidden /></span>
        <div className="min-w-0 flex-1">
          <h3 className="gi-visual-label">{etiqueta}</h3>
          <p className="gi-visual-value">{valor}</p>
        </div>
        {enlace && <a className="gi-icon-link" href={enlace.href} aria-label={enlace.etiqueta}><ArrowUpRight size={18} aria-hidden /></a>}
      </div>
      <div className="gi-visual-context">{contexto}</div>
      <div className="gi-visual-bars">
        {barras.map((barra) => <div key={barra.etiqueta}>
          <div className="gi-bar-label"><span>{barra.etiqueta}</span><strong>{barra.texto}</strong></div>
          <div className="gi-visual-track" aria-hidden="true"><div data-barra-visual className={cn('gi-visual-fill', barra.color && `gi-bar-${barra.color}`)} style={{ width: `${barra.valor == null ? 0 : Math.min(100, Math.max(0, barra.valor / maximo * 100))}%` }} /></div>
        </div>)}
      </div>
      <div className={cn('gi-visual-foot', `gi-estado-${estado}`)}>{pie}</div>
      {detalle && <details className="gi-visual-detail"><summary aria-label={`Ver contexto de ${etiqueta}`}><Info size={16} aria-hidden /></summary><div>{detalle}</div></details>}
    </section>
  )
}

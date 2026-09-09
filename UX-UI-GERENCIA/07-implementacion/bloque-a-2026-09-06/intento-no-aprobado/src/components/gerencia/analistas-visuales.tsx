import { useRef, useState, type ReactNode } from 'react'
import gsap from 'gsap'
import { useGSAP } from '@gsap/react'
import { ArrowUpRight } from 'lucide-react'
import { Skeleton } from '@/components/ui/skeleton'
import { numero, porcentajeConversionCanonica } from '@/lib/format'
import type { ConversionVendedorAdaptada, DetalleConversionMensual } from '@/lib/conversion-vendedores'

export function AnalistasVisuales({ filas, periodo, baseAutomatica, cargando, disponible, seleccionado, onSeleccionar, accion, compacto = false }: {
  filas: ConversionVendedorAdaptada<DetalleConversionMensual>[]
  periodo: string
  baseAutomatica: boolean
  cargando: boolean
  disponible: boolean
  seleccionado?: string
  onSeleccionar?: (id: string) => void
  accion?: ReactNode
  compacto?: boolean
}) {
  const alcance = useRef<HTMLElement>(null)
  const [todos, setTodos] = useState(false)
  const medibles = filas.filter((fila) => fila.detalle?.conversion_pct != null)
  const visibles = todos ? medibles : medibles.slice(0, 4)
  const maximo = Math.max(1, ...medibles.map((fila) => fila.detalle?.conversion_pct ?? 0))
  const clave = visibles.map((fila) => `${fila.vendedorId}:${fila.detalle?.conversion_pct}`).join('|')
  useGSAP(() => {
    const medios = gsap.matchMedia()
    medios.add('(prefers-reduced-motion: no-preference)', () => {
      gsap.from('[data-analista-barra]', { scaleX: 0, transformOrigin: 'left center', duration: .45, stagger: .045, ease: 'power2.out', clearProps: 'transform' })
    })
    return () => medios.revert()
  }, { scope: alcance, dependencies: [clave], revertOnUpdate: true })
  return <section ref={alcance} data-gi-panel className={`gi-card gi-analysts p-4${compacto ? ' gi-analysts-compact' : ''}`} aria-label="Conversión por analista">
    <h2 className="gi-title">Conversión por analista</h2>
    <p className="gi-caption mt-2">Mes calendario · {periodo}{compacto ? ` · base ${baseAutomatica ? 'automática' : 'histórica'}` : ''}</p>
    {cargando ? <Skeleton className="mt-4 h-44" aria-label="Consultando ranking mensual" /> : !disponible || medibles.length === 0 ? <p className="gi-chart-empty">{disponible ? 'Aún no hay analistas medibles este mes' : 'Detalle por analista no disponible'}</p> : <div className="gi-analyst-list">
      {visibles.map((fila) => {
        const contenido = <><span className="gi-bar-label"><span>{fila.nombre}{compacto && <span className="gi-analyst-inline-base"> · Base {numero(fila.detalle!.divisor)}</span>}</span><strong>{porcentajeConversionCanonica(fila.detalle!.conversion_pct)}</strong></span><span className="gi-visual-track" aria-hidden="true"><span data-analista-barra className="gi-visual-fill gi-bar-verde" style={{ width: `${Math.max(0, (fila.detalle!.conversion_pct ?? 0) / maximo * 100)}%` }} /></span>{!compacto && <span className="gi-analyst-base">Base {baseAutomatica ? 'automática' : 'histórica'}: {numero(fila.detalle!.divisor)} {baseAutomatica ? 'leads' : 'registros'}{onSeleccionar && <ArrowUpRight size={13} aria-hidden />}</span>}</>
        return onSeleccionar ? <button key={fila.vendedorId} type="button" className="gi-analyst-row" aria-label={`Ver detalle de ${fila.nombre}`} aria-current={seleccionado === fila.vendedorId ? 'true' : undefined} onClick={() => onSeleccionar(fila.vendedorId)}>{contenido}</button> : <div key={fila.vendedorId} className="gi-analyst-row">{contenido}</div>
      })}
    </div>}
    {medibles.length > 4 && <button type="button" className="gi-text-button" aria-expanded={todos} onClick={() => setTodos(!todos)}>{todos ? 'Ver menos analistas' : `Ver los ${medibles.length} analistas`}</button>}
    {!compacto && <p className="gi-caption mt-2">El verde identifica conversión; el largo compara porcentajes.</p>}
    {accion && <div className="mt-3">{accion}</div>}
  </section>
}

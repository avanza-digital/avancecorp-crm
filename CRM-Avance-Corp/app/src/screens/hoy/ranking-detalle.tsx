import { X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Sheet, SheetTitle } from '@/components/ui/sheet'
import { DesgloseMonedas } from '@/components/common/desglose-monedas'
import { totalEnSoles } from '@/lib/capital-unificado'
import { money, numero, porcentajeConversionCanonica } from '@/lib/format'
import type { RankingCapitalTotalVendedores } from '@/lib/conversion-vendedores'
import type { RankingOrigenVendedor } from '@/lib/ranking-origen'
import { etiquetaOrigen } from '@/lib/tipos'

type FilaCapital = RankingCapitalTotalVendedores['conPuesto'][number]

// Sólo para enseñar la disposición en el modo demo local. La producción del
// ranking real se consulta por RPC; este reparto jamás se presenta como dato.
const ORIGENES_EJEMPLO = [
  { nombre: 'Landing', pen: 40, usd: 6, conversion: { leads: 80, cierres: 6, peso: 1 } },
  { nombre: 'Formulario', pen: 24, usd: 5, conversion: { leads: 60, cierres: 5, peso: 1 } },
  { nombre: 'Referido', pen: 16, usd: 4, conversion: { leads: 20, cierres: 4, peso: 0.15 } },
  { nombre: 'Walking', pen: 8, usd: 2, conversion: { leads: 30, cierres: 2, peso: 1 } },
  { nombre: 'Cartera', pen: 12, usd: 1, conversion: null },
] as const

function repartirEjemplo(total: number, pesos: readonly number[]): number[] {
  const centimos = Math.round(total * 100)
  let asignado = 0
  return pesos.map((peso, indice) => {
    const parte = indice === pesos.length - 1
      ? centimos - asignado
      : Math.floor(centimos * peso / pesos.reduce((suma, valor) => suma + valor, 0))
    asignado += parte
    return parte / 100
  })
}

interface OrigenPresentado {
  origen: string
  capitalPen: number
  capitalUsd: number
  conversionPct: number | null
  mostrarConversion: boolean
}

function nombreOrigen(origen: string): string {
  if (origen === 'landing') return 'Landing'
  if (origen === 'formulario') return 'Formulario'
  if (origen === 'referido') return 'Referido'
  if (origen === 'oficina') return 'Walking'
  if (origen === 'cartera') return 'Cartera'
  if (origen === 'ajuste') return 'Ajustes de cierre'
  if (origen === 'sin_origen') return 'Sin origen identificado'
  return etiquetaOrigen(origen)
}

function filasEjemplo(fila: FilaCapital): OrigenPresentado[] {
  const pen = repartirEjemplo(fila.capitalPen, ORIGENES_EJEMPLO.map((origen) => origen.pen))
  const usd = repartirEjemplo(fila.capitalUsd, ORIGENES_EJEMPLO.map((origen) => origen.usd))
  return ORIGENES_EJEMPLO.map((origen, indice) => ({
    origen: origen.nombre,
    capitalPen: pen[indice] ?? 0,
    capitalUsd: usd[indice] ?? 0,
    conversionPct: origen.conversion
      ? 100 * origen.conversion.cierres * origen.conversion.peso / origen.conversion.leads
      : null,
    mostrarConversion: origen.conversion != null,
  }))
}

function VistaOrigenes({ filas, tc, total, ejemplo, cartera }: {
  filas: OrigenPresentado[]
  tc: number | null
  total: number | null
  ejemplo: boolean
  cartera?: RankingOrigenVendedor['cartera'] | FilaCapital['cartera']
}) {
  return (
    <section aria-label={ejemplo ? 'Vista de ejemplo del capital y conversión por origen' : 'Capital y conversión por origen'} className="rounded-2xl border border-[var(--gi-line)] bg-white p-4">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h3 className="text-sm font-bold text-[var(--gi-navy)]">Capital y conversión por origen</h3>
        {ejemplo && <span className="rounded-full bg-amber-50 px-2 py-1 text-[10px] font-bold text-amber-900">Ejemplo ficticio</span>}
      </div>
      <ul className="mt-2 divide-y divide-[var(--gi-line)]">
        {filas.map(({ origen, capitalPen, capitalUsd, conversionPct, mostrarConversion }) => {
          const capitalTotal = totalEnSoles(capitalPen, capitalUsd, tc).total
          const esCartera = origen === 'cartera'
          const carteraConcilia = cartera != null && cartera.length >= 2
            && Math.round(cartera.reduce((suma, fila) => suma + fila.pen, 0) * 100) === Math.round(capitalPen * 100)
            && Math.round(cartera.reduce((suma, fila) => suma + fila.usd, 0) * 100) === Math.round(capitalUsd * 100)
          return (
            <li key={origen} className="py-3">
              <div className="flex items-start justify-between gap-3">
                <span className="min-w-0 text-xs font-semibold text-[var(--gi-navy)]">{nombreOrigen(origen)}</span>
                <span className="min-w-0 text-right">
                  <strong className="block text-sm tabular-nums text-[var(--gi-navy)]">{money(capitalTotal, 'PEN')}</strong>
                  {capitalUsd < 0
                    ? <span className="block text-[11px] text-[var(--gi-muted)]">{money(capitalPen, 'PEN')} · {money(capitalUsd, 'USD')}</span>
                    : <DesgloseMonedas pen={capitalPen} usd={capitalUsd} tc={tc} tono="gerencia" />}
                </span>
              </div>
              {esCartera && (
                carteraConcilia ? <div role="group" aria-label="Desglose de cartera"><dl className="mt-3 space-y-3 border-l-2 border-[var(--gi-line)] pl-3 text-xs text-[var(--gi-navy)]">
                  {cartera!.filter((detalle) => detalle.categoria !== 'sin_clasificar' || detalle.pen !== 0 || detalle.usd !== 0).map((detalle) => (
                    <div key={detalle.categoria} className="flex items-start justify-between gap-3">
                      <dt>{detalle.categoria === 'renovacion' ? 'Renovación' : detalle.categoria === 'upgrade' ? 'Upgrade' : detalle.categoria === 'nuevo' ? 'Nueva inversión' : 'Sin clasificación'}</dt>
                      <dd className="text-right tabular-nums">
                        <strong>{money(totalEnSoles(detalle.pen, detalle.usd, tc).total, 'PEN')}</strong>
                        <DesgloseMonedas pen={detalle.pen} usd={detalle.usd} tc={tc} tono="gerencia" />
                      </dd>
                    </div>
                  ))}
                </dl></div> : <p className="mt-2 text-xs text-[var(--gi-muted)]">Desglose de renovación y upgrade no disponible</p>
              )}
              {mostrarConversion && (
                <div className="mt-2 flex items-center justify-between gap-3 rounded-lg bg-[var(--gi-soft)] px-3 py-2 text-[11px] text-[var(--muted-foreground-strong)]">
                  <span>Conversión</span>
                  <strong className="whitespace-nowrap text-xs tabular-nums text-[var(--gi-blue)]">
                    {conversionPct == null ? '—' : porcentajeConversionCanonica(conversionPct)}
                  </strong>
                </div>
              )}
            </li>
          )
        })}
      </ul>
      <div className="flex items-baseline justify-between gap-3 border-t border-[var(--gi-line)] pt-3 text-xs font-bold text-[var(--gi-navy)]">
        <span>{ejemplo ? 'Total ilustrado' : 'Total'}</span>
        <span className="tabular-nums">{money(total, 'PEN')}</span>
      </div>
    </section>
  )
}

export function BotonDetalleRanking({ id, nombre, equipo, variante, onAbrir }: {
  id: string | null
  nombre: string
  equipo?: string
  variante: 'tabla' | 'lista'
  onAbrir: (id: string) => void
}) {
  if (!id) return <span>{nombre}</span>
  return (
    <button
      id={`ranking-analista-${id}-${variante}`}
      type="button"
      aria-label={`Ver detalle de ${nombre}`}
      onClick={() => onAbrir(id)}
      className="block min-h-11 max-w-full cursor-pointer rounded text-left normal-case tracking-normal focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-accent/40"
    >
      <span className="block text-sm font-semibold text-[var(--gi-navy)]">{nombre}</span>
      {equipo && <span className="mt-1 block text-xs font-normal text-[var(--muted-foreground-strong)]">{equipo}</span>}
      <span className="mt-1 block text-xs font-semibold text-[var(--gi-blue)] underline-offset-4 hover:underline">Ver detalle</span>
    </button>
  )
}

export function DetalleCapitalRanking({ abierto, fila, periodo, tc, fuenteTc, cargando, error, origenes, origenesCargando, origenesError, onReintentarOrigenes, onCerrar, onReintentar, onAbrirConversiones }: {
  abierto: boolean
  fila: FilaCapital | null
  periodo: string
  tc: number | null
  fuenteTc?: string | undefined
  cargando: boolean
  error: string | null
  origenes?: RankingOrigenVendedor | null | undefined
  origenesCargando?: boolean
  origenesError?: boolean
  onReintentarOrigenes?: () => void
  onCerrar: () => void
  onReintentar: () => void
  onAbrirConversiones?: ((id: string) => void) | undefined
}) {
  const disponible = !cargando && !error && fila != null
  const ejemplo = import.meta.env.DEV && fila?.vendedor.vendedorId?.startsWith('demo-') === true
  const filasReales = origenes?.filas ?? []
  const concilia = fila != null && origenes?.disponible === true
    && Math.abs(filasReales.reduce((suma, origen) => suma + origen.capital_pen, 0) - fila.capitalPen) <= 0.01
    && Math.abs(filasReales.reduce((suma, origen) => suma + origen.capital_usd, 0) - fila.capitalUsd) <= 0.01
  return (
    <Sheet open={abierto} onClose={onCerrar} ariaLabel="Detalle de capital del analista" className="gerencia-inteligencia max-w-full sm:max-w-[92vw]">
      <div className="ac-scroll space-y-4 overflow-y-auto p-5 sm:p-6">
        <header className="relative space-y-2 pr-12">
          <Button type="button" variant="ghost" size="icon" aria-label="Cerrar detalle" className="absolute right-0 top-0 size-11 text-[var(--gi-navy)]" onClick={onCerrar}>
            <X aria-hidden="true" />
          </Button>
          <p className="text-xs text-[var(--muted-foreground-strong)]">Ranking · Capital total</p>
          <SheetTitle className="text-2xl leading-8 text-[var(--gi-navy)]">{disponible ? fila.vendedor.nombre : 'Detalle del analista'}</SheetTitle>
          {disponible && <p className="text-sm text-[var(--muted-foreground-strong)]">{fila.vendedor.supervisorNombre}</p>}
          <p className="text-xs font-semibold text-[var(--gi-blue)]">Mes calendario · {periodo}</p>
        </header>
        {cargando ? <p role="status" className="text-sm">Consultando los datos del mes…</p>
          : error ? (
            <div className="space-y-3">
              <p role="alert" className="text-sm text-destructive-text">{error}</p>
              <Button variant="outline" className="min-h-11" onClick={onReintentar}>Reintentar</Button>
            </div>
          ) : !fila ? <p role="status" className="text-sm">Este analista ya no tiene una posición de capital disponible en la consulta actual.</p>
          : (
            <>
              <dl className="space-y-3 rounded-2xl bg-[var(--gi-soft)] p-4">
                <div>
                  <dt className="text-xs font-semibold text-[var(--muted-foreground-strong)]">Capital confirmado (S/)</dt>
                  <dd className="mt-3 space-y-3">
                    <strong className="block text-2xl leading-8 tabular-nums text-[var(--gi-navy)]">{money(fila.capitalTotal, 'PEN')}</strong>
                    <DesgloseMonedas pen={fila.capitalPen} usd={fila.capitalUsd} tc={tc} tono="gerencia" />
                  </dd>
                </div>
                <div>
                  <dt className="text-xs font-semibold text-[var(--muted-foreground-strong)]">Meta mensual (S/)</dt>
                  <dd className="mt-3 space-y-3">
                    <strong className="block text-sm tabular-nums text-[var(--gi-navy)]">{money(fila.metaCapital, 'PEN')}</strong>
                    <DesgloseMonedas pen={fila.metaPen} usd={fila.metaUsd} tc={tc} tono="gerencia" />
                  </dd>
                </div>
                <div>
                  <dt className="text-xs font-semibold text-[var(--muted-foreground-strong)]">Cumplimiento de la meta</dt>
                  <dd className="mt-3 text-2xl font-bold leading-8 tabular-nums text-[var(--gi-blue)]">{porcentajeConversionCanonica(fila.avance)}</dd>
                </div>
              </dl>
              {!concilia && (fila.capitalAjustePen > 0 || fila.capitalAjusteUsd > 0 || fila.contratosAjuste > 0) && (
                <p className="text-xs text-[var(--muted-foreground-strong)]">
                    Ajustes de cierre descontados: {money(fila.capitalAjustePen, 'PEN')} · {money(fila.capitalAjusteUsd, 'USD')}.
                </p>
              )}
              <p className="text-xs text-[var(--muted-foreground-strong)]">
                {tc != null ? `TC S/ ${numero(tc, 4)} · ${fuenteTc ?? 'BCRP'}` : 'TC no disponible · US$ separado'}
              </p>
              {ejemplo
                ? <VistaOrigenes filas={filasEjemplo(fila)} tc={tc} total={fila.capitalTotal} ejemplo />
                : origenesCargando
                  ? <p role="status" className="text-xs text-[var(--gi-muted)]">Cargando orígenes…</p>
                  : concilia
                    ? <VistaOrigenes filas={filasReales.map((origen) => ({
                      origen: origen.origen,
                      capitalPen: origen.capital_pen,
                      capitalUsd: origen.capital_usd,
                      conversionPct: origen.conversion_pct,
                      mostrarConversion: ['landing', 'formulario', 'referido', 'oficina'].includes(origen.origen),
                    }))} tc={tc} total={fila.capitalTotal} ejemplo={false} cartera={origenes?.cartera ?? fila.cartera} />
                    : <div className="flex items-center justify-between gap-3 text-xs text-[var(--gi-muted)]">
                        <span>Desglose no disponible</span>
                        {origenesError && onReintentarOrigenes && <Button variant="outline" size="sm" onClick={onReintentarOrigenes}>Reintentar</Button>}
                      </div>}
            </>
          )}
        {disponible && fila.vendedor.vendedorId && onAbrirConversiones && (
          <div className="flex flex-col items-start gap-4">
            <Button className="h-11 min-w-45 rounded-lg bg-[var(--gi-navy)] hover:bg-[var(--gi-blue)]" onClick={() => {
              if (!fila.vendedor.vendedorId) return
              onAbrirConversiones(fila.vendedor.vendedorId)
            }}>Abrir Conversiones</Button>
          </div>
        )}
      </div>
    </Sheet>
  )
}

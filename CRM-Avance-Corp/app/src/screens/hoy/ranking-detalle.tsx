import { Button } from '@/components/ui/button'
import { Sheet, SheetTitle } from '@/components/ui/sheet'
import { DesgloseMonedas } from '@/components/common/desglose-monedas'
import { money, numero, porcentajeConversionCanonica } from '@/lib/format'
import type { RankingCapitalTotalVendedores } from '@/lib/conversion-vendedores'

type FilaCapital = RankingCapitalTotalVendedores['conPuesto'][number]

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

export function DetalleCapitalRanking({ abierto, fila, periodo, tc, fuenteTc, cargando, error, onCerrar, onReintentar, onAbrirConversiones }: {
  abierto: boolean
  fila: FilaCapital | null
  periodo: string
  tc: number | null
  fuenteTc?: string | undefined
  cargando: boolean
  error: string | null
  onCerrar: () => void
  onReintentar: () => void
  onAbrirConversiones?: ((id: string) => void) | undefined
}) {
  const disponible = !cargando && !error && fila != null
  return (
    <Sheet open={abierto} onClose={onCerrar} ariaLabel="Detalle de capital del analista" className="gerencia-inteligencia max-w-full sm:max-w-[92vw]">
      <div className="ac-scroll space-y-4 overflow-y-auto p-5 sm:p-6">
        <header className="space-y-2">
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
              {(fila.capitalAjustePen > 0 || fila.capitalAjusteUsd > 0 || fila.contratosAjuste > 0) && (
                <p className="text-xs leading-relaxed text-warning-text">
                  Neto tras ajuste de cierre
                  {fila.capitalAjustePen > 0 ? ` · −${money(fila.capitalAjustePen, 'PEN')}` : ''}
                  {fila.capitalAjusteUsd > 0 ? ` · −${money(fila.capitalAjusteUsd, 'USD')}` : ''}
                  {fila.contratosAjuste > 0 ? ` · −${numero(fila.contratosAjuste)} contratos` : ''}
                </p>
              )}
              <p className="text-xs leading-relaxed text-[var(--muted-foreground-strong)]">
                {tc != null ? `TC S/ ${numero(tc, 4)} (${fuenteTc ?? 'BCRP'}). Capital y meta conservan su desglose original en S/ y US$.`
                  : 'Tipo de cambio no disponible (fuente BCRP): el total muestra sólo S/ y US$ permanece aparte.'}
              </p>
            </>
          )}
        <div className="flex flex-col items-start gap-4">
          {disponible && fila.vendedor.vendedorId && onAbrirConversiones && (
            <Button className="h-11 min-w-45 rounded-lg bg-[var(--gi-navy)] hover:bg-[var(--gi-blue)]" onClick={() => {
              if (!fila.vendedor.vendedorId) return
              onAbrirConversiones(fila.vendedor.vendedorId)
            }}>Abrir Conversiones</Button>
          )}
          <Button variant="outline" className="h-11 min-w-45 rounded-lg text-[var(--gi-navy)]" onClick={onCerrar}>Volver a Ranking</Button>
        </div>
      </div>
    </Sheet>
  )
}

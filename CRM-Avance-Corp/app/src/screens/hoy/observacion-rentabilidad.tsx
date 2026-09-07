// Rentabilidad R2 — la tarjeta de OBSERVACIÓN de Gerencia.
//
// QUÉ MUESTRA. Desde R2, cada alta y cada corrección de tasa quedan anotadas en el
// ledger del servidor con la tasa base que dice el núcleo (política vigente o la
// heredada del contrato origen) frente a la que quedó en el contrato. Esta tarjeta
// enseña, para los últimos N días: cuántos contratos se observaron, cuántos se
// apartaron de la base, cuánto margen se CEDIÓ en el plazo (capital × puntos sobre
// la base × plazo/365) por moneda, quién lo cedió (por analista) y los casos en los
// que el núcleo no pudo decidir (por ejemplo, un upgrade sin contrato origen claro).
// En observación NO se bloquea nada: es la medida previa a R3 (bandeja) y R4.
//
// FUENTES (regla de Miguel: las métricas se enlazan en el servidor). TODO sale de
// crm.observacion_rentabilidad_fn (una sola fuente, el ledger). El servidor manda una
// sonda `coherente`; si dice false, la tarjeta lo DECLARA en vez de pintar cifras que
// no cuadran. En sesión DEMO la RPC queda inerte (enabled=false) y se muestra un vacío
// honesto: la observación solo existe sobre datos reales.
import { useState, type JSX } from 'react'
import { AlertTriangle, Percent, RotateCcw } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { SectionHead } from '@/components/common/section-head'
import { PanelVacio } from '@/components/common/estado-panel'
import { useAuth } from '@/lib/auth-context'
import { cn } from '@/lib/utils'
import { money, numero } from '@/lib/format'
import { useObservacionRentabilidad } from '@/data/crm-queries'
import type { ObservacionRentabilidad } from '@/data/crm-api'
import { motivoSinRegla, etiquetaModoPolitica } from '@/lib/rentabilidad'

const HORIZONTES = [7, 30, 90] as const
type Horizonte = (typeof HORIZONTES)[number]
const HORIZONTE_INICIAL: Horizonte = 30
const TOP_N = 8

type Estado = 'cargando' | 'error' | 'vacio' | 'ok'

function estadoDe(cargando: boolean, error: boolean, vacio: boolean): Estado {
  if (cargando) return 'cargando'
  if (error) return 'error'
  if (vacio) return 'vacio'
  return 'ok'
}

function tasaTxt(n: number): string {
  return `${n.toLocaleString('es-PE', { minimumFractionDigits: 0, maximumFractionDigits: 2 })}%`
}

function TabsHorizonte({ valor, onCambio }: { valor: Horizonte; onCambio: (h: Horizonte) => void }): JSX.Element {
  return (
    <div role="group" aria-label="Horizonte de observación" className="flex gap-1">
      {HORIZONTES.map((h) => (
        <button
          key={h}
          type="button"
          onClick={() => onCambio(h)}
          aria-pressed={valor === h}
          aria-label={`${h} días`}
          className={cn(
            'min-h-11 min-w-11 rounded-full border px-2.5 py-0.5 text-[11px] font-bold transition-colors',
            'focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
            valor === h
              ? 'border-transparent bg-primary text-primary-foreground'
              : 'border-border text-muted-foreground-strong hover:bg-muted/60',
          )}
        >
          {h} d
        </button>
      ))}
    </div>
  )
}

function Tile({ etiqueta, valor, detalle }: { etiqueta: string; valor: string; detalle?: string }): JSX.Element {
  return (
    <div className="min-w-0 rounded-lg border border-border bg-muted/30 px-3 py-2">
      <div className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground-strong">{etiqueta}</div>
      <div className="mt-0.5 break-words text-base font-bold tabular-nums sm:text-lg">{valor}</div>
      {detalle && <div className="text-[11px] text-muted-foreground">{detalle}</div>}
    </div>
  )
}

function Cuerpo({ datos, horizonte }: { datos: ObservacionRentabilidad; horizonte: Horizonte }): JSX.Element {
  const t = datos.totales
  const pctDivergentes = t.observados > 0 ? Math.round((t.divergentes / t.observados) * 100) : 0
  const ranking = datos.por_analista.filter((a) => a.divergentes > 0).slice(0, TOP_N)
  const maximo = ranking[0]?.cedido_pen ?? 0
  return (
    <>
      {(!datos.coherente || datos.altas_sin_observar > 0) && (
        <div role="alert" className="mb-3 flex items-start gap-2 rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-900">
          <AlertTriangle className="mt-0.5 size-4 shrink-0" aria-hidden />
          <span>
            {datos.altas_sin_observar > 0
              ? `${numero(datos.altas_sin_observar)} ${datos.altas_sin_observar === 1 ? 'alta del periodo quedó' : 'altas del periodo quedaron'} sin observar en el servidor: las cifras están incompletas. Revisa el ledger antes de decidir.`
              : 'Las cifras de esta tarjeta no cuadran entre sí en el servidor. No las uses para decidir hasta revisar el ledger.'}
          </span>
        </div>
      )}
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        <Tile etiqueta="Observados" valor={numero(t.observados)} detalle={`${numero(t.correcciones)} ${t.correcciones === 1 ? 'corrección' : 'correcciones'}`} />
        <Tile etiqueta="Fuera de la base" valor={numero(t.divergentes)} detalle={`${pctDivergentes}% · ${numero(t.ceden)} ceden · ${numero(t.retienen)} retienen`} />
        <Tile
          etiqueta="Margen cedido"
          valor={money(t.cedido.PEN, 'PEN')}
          detalle={t.cedido.USD > 0 ? `+ ${money(t.cedido.USD, 'USD')} · ${tasaTxt(t.puntos_promedio_cedido)} prom.` : `${tasaTxt(t.puntos_promedio_cedido)} sobre la base, en promedio`}
        />
        <Tile etiqueta="Sin regla" valor={numero(t.sin_regla)} detalle="el núcleo no pudo decidir" />
      </div>

      {ranking.length > 0 && (
        <div className="mt-4">
          <h4 className="mb-2 text-xs font-bold uppercase tracking-wide text-muted-foreground-strong">Quién cede margen</h4>
          {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
          <ol role="list" className="flex flex-col gap-2" aria-label="Margen cedido por analista">
            {ranking.map((a, i) => (
              <li key={a.analista_id} className="grid grid-cols-[1.5rem_1fr_auto] items-center gap-2">
                <span className="text-xs font-bold tabular-nums text-muted-foreground">{i + 1}</span>
                <div className="min-w-0">
                  <div className="flex items-baseline justify-between gap-2">
                    <span className="truncate text-sm font-medium" title={a.analista_nombre}>{a.analista_nombre}</span>
                    <span className="shrink-0 text-[11px] tabular-nums text-muted-foreground">
                      {numero(a.divergentes)} de {numero(a.observados)}<span className="sr-only"> contratos fuera de la base</span> · {tasaTxt(a.puntos_promedio_cedido)} <abbr title="promedio">prom.</abbr>
                    </span>
                  </div>
                  <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-muted" aria-hidden>
                    <div className="h-full rounded-full bg-primary" style={{ width: `${maximo > 0 ? Math.round((a.cedido_pen / maximo) * 100) : 0}%` }} />
                  </div>
                </div>
                <span className="text-sm font-bold tabular-nums">
                  {money(a.cedido_pen, 'PEN')}
                  {a.cedido_usd > 0 && <span className="ml-1 text-xs font-medium text-muted-foreground">+ {money(a.cedido_usd, 'USD')}</span>}
                  <span className="sr-only"> cedidos en el plazo</span>
                </span>
              </li>
            ))}
          </ol>
        </div>
      )}

      {datos.sin_regla.length > 0 && (
        <div className="mt-4">
          <h4 className="mb-2 text-xs font-bold uppercase tracking-wide text-muted-foreground-strong">Casos que la política no define</h4>
          {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
          <ul role="list" className="flex flex-wrap gap-1.5" aria-label="Casos sin regla por motivo">
            {datos.sin_regla.map((m) => (
              <li key={m.motivo} className="rounded-full border border-border px-2.5 py-1 text-[11px] font-medium">
                {motivoSinRegla(m.motivo)}<span className="sr-only">, </span><span aria-hidden> × </span>
                <span className="font-bold tabular-nums">{numero(m.n)}<span className="sr-only"> {m.n === 1 ? 'caso' : 'casos'}</span></span>
              </li>
            ))}
          </ul>
        </div>
      )}

      <p className="mt-3 text-[11px] text-muted-foreground">
        Observación de los últimos {horizonte} días{datos.politica ? ` · política v${datos.politica.version}: base ${tasaTxt(datos.politica.tasa_base_nueva)}, ${etiquetaModoPolitica(datos.politica.modo)}` : ''}.
        Cedido = capital × puntos sobre la base × plazo/365, por contrato.{' '}
        {datos.politica == null
          ? 'No se pudo leer el modo de la política: no se puede afirmar si el servidor bloquea.'
          : datos.politica.modo === 'enforcement'
            ? 'Con el candado activo, lo que aparece aquí ya solo puede venir de una autorización de Gerencia.'
            : 'Nada se bloquea todavía.'}
      </p>
    </>
  )
}

export function ObservacionRentabilidadPanel(): JSX.Element {
  const { yo } = useAuth()
  const esDemo = yo?.demo === true
  const sesionReal = !!yo && !esDemo
  const [horizonte, setHorizonte] = useState<Horizonte>(HORIZONTE_INICIAL)
  const consulta = useObservacionRentabilidad(sesionReal, horizonte)
  const datos = consulta.data
  // La alarma del servidor manda sobre el vacío (Codex #27): con 0 observados pero altas sin observar o incoherencia,
  // se muestra el diagnóstico, nunca «aparecerán en cuanto entre la primera».
  const alarma = !!datos && (!datos.coherente || datos.altas_sin_observar > 0)
  const estado: Estado = esDemo
    ? 'vacio'
    : estadoDe(consulta.isPending && datos === undefined, consulta.isError, (datos?.totales.observados ?? 0) === 0 && !alarma)

  return (
    <Card className="min-w-0" data-testid="observacion-rentabilidad">
      <SectionHead
        icon={Percent}
        title="Rentabilidad: margen cedido"
        right={
          <div className="flex items-center gap-3">
            {estado === 'ok' && datos && (
              <span className="text-xs font-bold tabular-nums text-muted-foreground">
                {numero(datos.totales.divergentes)} de {numero(datos.totales.observados)} fuera de la base
              </span>
            )}
            <TabsHorizonte valor={horizonte} onCambio={setHorizonte} />
          </div>
        }
      />
      <CardContent className="min-w-0 pt-1">
        <p role="status" className="sr-only">
          {estado === 'cargando' && 'Cargando la observación de rentabilidad…'}
          {estado === 'error' && 'No se pudo cargar la observación de rentabilidad.'}
          {estado === 'vacio' && (esDemo ? 'En demo no hay observación de rentabilidad.' : 'Sin contratos observados en el horizonte elegido.')}
          {estado === 'ok' && datos && !datos.coherente && 'Cifras en revisión: la observación no cuadra en el servidor; no las uses para decidir.'}
          {estado === 'ok' && datos && datos.coherente && `${numero(datos.totales.divergentes)} de ${numero(datos.totales.observados)} contratos fuera de la base en los últimos ${horizonte} días; margen cedido ${money(datos.totales.cedido.PEN, 'PEN')}.`}
        </p>
        {estado === 'cargando' && <Skeleton className="h-[180px] w-full" aria-busy />}
        {estado === 'error' && (
          <div className="flex h-[180px] flex-col items-center justify-center gap-3 text-center">
            <p className="text-xs text-muted-foreground">No se pudo cargar la observación. Revisa tu conexión y vuelve a intentarlo.</p>
            <Button type="button" size="sm" variant="outline" onClick={() => void consulta.refetch()}>
              <RotateCcw className="size-4" aria-hidden /> Reintentar
            </Button>
          </div>
        )}
        {estado === 'vacio' && (
          <PanelVacio
            icono={Percent}
            titulo={esDemo ? 'La observación solo existe en sesión real' : `Sin altas observadas en los últimos ${horizonte} días`}
            detalle={esDemo
              ? 'En demo no hay ledger de rentabilidad que observar.'
              : 'Desde el 06/09/2026 cada alta y cada corrección de tasa quedan anotadas con la tasa base que dice la política. Aparecerán aquí en cuanto entre la primera.'}
          />
        )}
        {estado === 'ok' && datos && <Cuerpo datos={datos} horizonte={horizonte} />}
      </CardContent>
    </Card>
  )
}

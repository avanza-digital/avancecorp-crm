// Altas de contratos NUEVOS por el analista que cierra — panel de GERENCIA.
// Sustituye al reporte viejo «altas por analista» (F7 Ola 2b lo demuele el
// 14/09): Miguel pidió que existiera ANTES de borrar el viejo (04/09).
//
// QUÉ CUENTA (decisión de Miguel: «solo contratos nuevos, por el que cierra»):
//   un contrato con categoría 'nuevo' cerrado en el período, acreditado al
//   analista que lo cerró (para un contrato nuevo esa ES la regla ATR). Las
//   renovaciones y los upgrades NO cuentan aquí (son monto, no conversión); los
//   cierres anulados quedan fuera (anular es sanción). El ámbito lo resuelve el
//   SERVIDOR: gerencia ve a todos, un vendedor solo lo suyo.
//
// FUENTES (nunca mezcladas), mismo patrón que graficas-gerencia:
//  - Sesión REAL: RPC crm.altas_nuevas_por_analista_fn vía TanStack Query
//    (enabled solo en real). Skeleton al cargar, error con reintento, vacío
//    HONESTO (regla A3: sin datos no se pinta nada inventado).
//  - Sesión DEMO: derivación en cliente de las fixtures (lib/demo-metricas),
//    import() dinámico gated → cero red y cero fuga al bundle de prod.
import { useEffect, useMemo, useState, type JSX } from 'react'
import { RotateCcw, UserPlus } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { SectionHead } from '@/components/common/section-head'
import { PanelVacio } from '@/components/common/estado-panel'
import { useAuth } from '@/lib/auth-context'
import { cn } from '@/lib/utils'
import { numero } from '@/lib/format'
import { registrarError } from '@/lib/observabilidad'
import { inicioHorizonte, topAltasPorAnalista, type FilaAltasAnalista } from '@/lib/metricas'
import { useAltasNuevasPorAnalista } from '@/data/crm-queries'

const HORIZONTES = [3, 6, 12] as const
type Horizonte = (typeof HORIZONTES)[number]
const HORIZONTE_INICIAL: Horizonte = 6
const TOP_N = 12

type Estado = 'cargando' | 'error' | 'vacio' | 'ok'

function estadoDe(cargando: boolean, error: boolean, vacio: boolean): Estado {
  if (cargando) return 'cargando'
  if (error) return 'error'
  if (vacio) return 'vacio'
  return 'ok'
}

function TabsHorizonte({
  valor,
  onCambio,
}: {
  valor: Horizonte
  onCambio: (h: Horizonte) => void
}): JSX.Element {
  return (
    <div role="group" aria-label="Horizonte" className="flex gap-1">
      {HORIZONTES.map((h) => (
        <button
          key={h}
          type="button"
          onClick={() => onCambio(h)}
          aria-pressed={valor === h}
          // M4 (a11y): el texto visible «3 m» es prefijo del nombre («3 meses»),
          // asi el lector no oye «tres eme» (2.5.3 Label in Name).
          aria-label={`${h} meses`}
          className={cn(
            'rounded-full border px-2.5 py-0.5 text-[11px] font-bold transition-colors',
            'focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
            valor === h
              ? 'border-transparent bg-primary text-primary-foreground'
              // M1 (a11y): sobre hover:bg-muted/60 el gris base cae a 4,44:1;
              // --muted-foreground-strong (index.css) da 7,1:1 ahi.
              : 'border-border text-muted-foreground-strong hover:bg-muted/60',
          )}
        >
          {h} m
        </button>
      ))}
    </div>
  )
}

export function AltasNuevasAnalistaPanel(): JSX.Element {
  const { yo } = useAuth()
  const esDemo = yo?.demo === true
  // Solo una sesión autenticada real consulta la RPC (enabled): en demo la
  // query queda inerte y NINGÚN request sale hacia Supabase.
  const sesionReal = !!yo && !esDemo

  const [horizonte, setHorizonte] = useState<Horizonte>(HORIZONTE_INICIAL)

  const [filasDemo, setFilasDemo] = useState<FilaAltasAnalista[] | null>(null)
  useEffect(() => {
    if (!esDemo) return undefined
    let vivo = true
    // Guard literal (mismo que graficas-gerencia): en prod DEV es false →
    // Rolldown elimina el chunk de fixtures/derivación del bundle.
    if (import.meta.env.DEV && import.meta.env.VITE_ENABLE_DEMO === 'true') {
      void import('@/lib/demo-metricas')
        .then((m) => {
          if (vivo) setFilasDemo(m.demoAltasNuevasPorAnalista())
        })
        .catch((error: unknown) => {
          if (!vivo) return
          registrarError('demo.altas_nuevas_carga_fallida', error)
          setFilasDemo([]) // fixtures inaccesibles: vacío honesto, nunca cifras inventadas
        })
    }
    return () => {
      vivo = false
    }
  }, [esDemo])

  const consulta = useAltasNuevasPorAnalista(sesionReal, horizonte)

  // Fuente unificada. En real la RPC ya acotó el horizonte; en demo se acota
  // aquí con la misma regla (primer día del mes de arranque).
  const filas = useMemo(() => {
    if (!esDemo) return consulta.data ?? []
    const desde = inicioHorizonte(horizonte)
    return (filasDemo ?? []).filter((f) => f.mes >= desde)
  }, [esDemo, filasDemo, consulta.data, horizonte])

  const ranking = useMemo(() => topAltasPorAnalista(filas, TOP_N), [filas])
  const total = useMemo(() => filas.reduce((suma, f) => suma + f.altas, 0), [filas])
  const maximo = ranking[0]?.altas ?? 0

  const demoCargando = esDemo && filasDemo == null
  const estado = esDemo
    ? estadoDe(demoCargando, false, filas.length === 0)
    : estadoDe(consulta.isPending && consulta.data === undefined, consulta.isError, filas.length === 0)

  return (
    <Card className="min-w-0" data-testid="altas-nuevas-analista">
      <SectionHead
        icon={UserPlus}
        title="Altas nuevas por analista"
        right={
          <div className="flex items-center gap-3">
            {estado === 'ok' && (
              <span className="text-xs font-bold tabular-nums text-muted-foreground">
                {numero(total)} {total === 1 ? 'alta' : 'altas'}
              </span>
            )}
            <TabsHorizonte valor={horizonte} onCambio={setHorizonte} />
          </div>
        }
      />
      <CardContent className="min-w-0 pt-1">
        {/* M5 (a11y, WCAG 4.1.3): region viva PERSISTENTE que anuncia carga, error
            y resultado al cambiar de horizonte sin mover el foco. Redaccion
            distinta a la del PanelVacio para no duplicar texto visible. */}
        <p role="status" className="sr-only">
          {estado === 'cargando' && 'Cargando altas nuevas…'}
          {estado === 'error' && 'No se pudieron cargar las altas.'}
          {estado === 'vacio' && 'Sin altas nuevas en el horizonte elegido.'}
          {estado === 'ok' && `${numero(total)} ${total === 1 ? 'alta' : 'altas'} en los últimos ${horizonte} meses`}
        </p>
        {estado === 'cargando' && <Skeleton className="h-[200px] w-full" aria-busy />}
        {estado === 'error' && (
          <div className="flex h-[200px] flex-col items-center justify-center gap-3 text-center">
            <p className="text-xs text-muted-foreground">
              No se pudieron cargar las altas. Revisa tu conexión y vuelve a intentarlo.
            </p>
            <Button type="button" size="sm" variant="outline" onClick={() => void consulta.refetch()}>
              <RotateCcw className="size-4" aria-hidden /> Reintentar
            </Button>
          </div>
        )}
        {estado === 'vacio' && (
          <PanelVacio
            icono={UserPlus}
            titulo={`Sin altas nuevas en los últimos ${horizonte} meses`}
            detalle="Aquí se cuentan los contratos NUEVOS cerrados en el período, por el analista que los cerró. Aparece el primero en cuanto se cierre un contrato nuevo (renovaciones y upgrades no cuentan)."
          />
        )}
        {estado === 'ok' && (
          <>
            {/* M2 (a11y F4.4 #1): role="list" EXPLICITO — el preflight pone
                list-style:none y Safari+VoiceOver borra la semantica del ol nativo.
                Restauracion documentada en .oxlintrc.json. */}
            {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
            <ol role="list" className="flex flex-col gap-2" aria-label="Ranking de altas nuevas por analista">
            {ranking.map((fila, i) => (
              <li key={fila.analista_id} className="grid grid-cols-[1.5rem_1fr_auto] items-center gap-2">
                <span className="text-xs font-bold tabular-nums text-muted-foreground">{i + 1}</span>
                <div className="min-w-0">
                  <div className="truncate text-sm font-medium" title={fila.nombre}>{fila.nombre}</div>
                  {/* Barra decorativa: la informacion va en la cifra (texto). */}
                  <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-muted" aria-hidden>
                    <div
                      className="h-full rounded-full bg-primary"
                      style={{ width: `${maximo > 0 ? Math.round((fila.altas / maximo) * 100) : 0}%` }}
                    />
                  </div>
                </div>
                <span className="text-sm font-bold tabular-nums">
                  {numero(fila.altas)}
                  {/* M3 (a11y): la cifra sin unidad se oye como «7» a secas. */}
                  <span className="sr-only"> {fila.altas === 1 ? 'alta' : 'altas'}</span>
                </span>
              </li>
            ))}
            </ol>
          </>
        )}
        {estado === 'ok' && (
          <p className="mt-3 text-[11px] text-muted-foreground">
            Contratos nuevos por el analista que cierra, por mes de cierre. Renovaciones y upgrades no cuentan; los cierres anulados se excluyen.
          </p>
        )}
      </CardContent>
    </Card>
  )
}

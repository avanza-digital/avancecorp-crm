// Gráficas ejecutivas de GERENCIA (fila nueva del panel Hoy) — recharts vía el
// wrapper ui/chart. Tres vistas del negocio de contratos del portal:
//   (a) capital colocado por mes (apilado por categoría) · (b) pagos:
//   pagado vs vencido · (c) vencimientos.
//
// FUENTES (nunca mezcladas):
//  - Sesión REAL: 3 RPCs crm.metricas_*_fn vía TanStack Query (enabled solo en
//    real). El ámbito lo resuelve el SERVIDOR. Skeleton al cargar, error con
//    reintento por tarjeta y estado vacío HONESTO (regla A3: sin datos no se
//    pinta nada inventado).
//  - Sesión DEMO: agregados derivados en cliente de las fixtures existentes
//    (lib/demo-metricas), cargados por import() dinámico gated (patrón
//    store.tsx ↔ demo.ts) → cero red y cero fuga al bundle de prod.
//
// Reglas de marca: SIN verde; navy reservado (aquí no se usa); PEN y USD JAMÁS
// se suman en una serie — cada gráfica monetaria pinta UNA moneda con tabs.
// Paleta apilada validada (dataviz, pares adyacentes, deutan/protan/tritan):
// azul #2563eb → ámbar #d97706 → violeta #7c3aed → cian #0891b2.
import { useEffect, useMemo, useState, type JSX, type ReactNode } from 'react'
import {
  Bar,
  BarChart,
  CartesianGrid,
  XAxis,
} from 'recharts'
import {
  CalendarClock,
  ChartColumnStacked,
  HandCoins,
  RotateCcw,
  type LucideIcon,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import {
  ChartContainer,
  ChartLegend,
  ChartLegendContent,
  ChartTooltip,
  ChartTooltipContent,
  type ChartConfig,
} from '@/components/ui/chart'
import { SectionHead } from '@/components/common/section-head'
import { PanelVacio } from '@/components/common/estado-panel'
import { useAuth } from '@/lib/auth-context'
import { cn } from '@/lib/utils'
import { money, type Moneda } from '@/lib/format'
import { SEMAFORO } from '@/lib/semaforo'
import { registrarError } from '@/lib/observabilidad'
import {
  monedasConDatos,
  pivotCapitalPorMes,
  pivotPagosPorMes,
  pivotVencimientosPorMes,
  type FilaCapitalMes,
  type FilaPagosMes,
  type FilaVencimientos,
} from '@/lib/metricas'
import {
  useMetricasCapitalMes,
  useMetricasPagosMes,
  useMetricasVencimientos,
} from '@/data/crm-queries'

// Horizonte de vencimientos: 12 meses (la RPC acepta p_dias; el default de 90
// dejaría la gráfica casi siempre vacía con contratos anuales — para planear
// renovaciones gerencia necesita ver el año completo).
const DIAS_VENCIMIENTOS = 365

// ── Configs de series (labels + colores de la paleta de AVANCE) ────────────────
// Apilado por categoría — orden de stack = orden validado de adyacencia.
const CFG_CAPITAL = {
  nuevo: { label: 'Nuevo', color: 'var(--chart-1)' }, // azul
  renovacion: { label: 'Renovación', color: 'var(--chart-3)' }, // ámbar
  upgrade: { label: 'Upgrade', color: 'var(--chart-2)' }, // violeta
  sin_categoria: { label: 'Sin categoría', color: 'var(--chart-4)' }, // cian (categoria null → '—')
} satisfies ChartConfig

const CATEGORIAS_STACK = ['nuevo', 'renovacion', 'upgrade', 'sin_categoria'] as const

// Semáforo del repo: pagado en azul (ok) y vencido en rojo (crítico). El navy
// queda reservado a convertido/ganado y aquí no se toca.
const CFG_PAGOS = {
  pagado: { label: 'Pagado', color: SEMAFORO.ok },
  vencido: { label: 'Vencido', color: SEMAFORO.critico },
} satisfies ChartConfig

const CFG_VENCIMIENTOS = {
  capital: { label: 'Capital por vencer', color: 'var(--chart-3)' }, // ámbar: atención
} satisfies ChartConfig

// ── Piezas compartidas ─────────────────────────────────────────────────────────

type EstadoGrafica = 'cargando' | 'error' | 'vacio' | 'ok'

function estadoDe(cargando: boolean, error: boolean, vacio: boolean): EstadoGrafica {
  if (cargando) return 'cargando'
  if (error) return 'error'
  if (vacio) return 'vacio'
  return 'ok'
}

/** Tabs PEN/USD (solo si hay datos en ambas — jamás se suman en una serie). */
function TabsMoneda({
  monedas,
  valor,
  onCambio,
}: {
  monedas: Moneda[]
  valor: Moneda
  onCambio: (m: Moneda) => void
}): JSX.Element | null {
  if (monedas.length === 0) return null
  if (monedas.length === 1) {
    return (
      <span className="text-xs font-bold text-muted-foreground">
        {monedas[0] === 'PEN' ? 'Soles' : 'Dólares'}
      </span>
    )
  }
  return (
    <div role="group" aria-label="Moneda" className="flex gap-1">
      {monedas.map((m) => (
        <button
          key={m}
          type="button"
          onClick={() => onCambio(m)}
          aria-pressed={valor === m}
          className={cn(
            'rounded-full border px-2.5 py-0.5 text-[11px] font-bold transition-colors',
            valor === m
              ? 'border-transparent bg-primary text-primary-foreground'
              : 'border-border text-muted-foreground hover:bg-muted/60',
          )}
        >
          {m === 'PEN' ? 'Soles' : 'Dólares'}
        </button>
      ))}
    </div>
  )
}

/** Card de gráfica con los 4 estados: skeleton / error+reintento / vacío / chart. */
function CardGrafica({
  icon,
  title,
  right,
  nota,
  vacioTitulo,
  vacioDetalle,
  estado,
  onReintentar,
  className,
  testid,
  children,
}: {
  icon: LucideIcon
  title: string
  right?: ReactNode | undefined
  /** Pie de lectura: qué significa cada serie/período (contexto honesto). */
  nota?: string | undefined
  /** Vacío accionable (PanelVacio): título corto + fuente y camino para llenarla. */
  vacioTitulo: string
  vacioDetalle: string
  estado: EstadoGrafica
  onReintentar?: (() => void) | undefined
  className?: string | undefined
  testid: string
  children?: ReactNode | undefined
}): JSX.Element {
  return (
    <Card className={cn('min-w-0', className)} data-testid={testid}>
      <SectionHead icon={icon} title={title} right={right} />
      <CardContent className="min-w-0 pt-1">
        {estado === 'cargando' && <Skeleton className="h-[240px] w-full" aria-busy />}
        {estado === 'error' && (
          <div className="flex h-[240px] flex-col items-center justify-center gap-3 text-center">
            <p className="text-xs text-muted-foreground">
              No se pudieron cargar las métricas. Revisa tu conexión y vuelve a intentarlo.
            </p>
            {onReintentar && (
              <Button type="button" size="sm" variant="outline" onClick={onReintentar}>
                <RotateCcw className="size-4" aria-hidden /> Reintentar
              </Button>
            )}
          </div>
        )}
        {/* Vacío honesto Y accionable (patrón de la casa): qué alimenta la
            gráfica y qué la hará aparecer; sin alto fijo — tres vacíos a la vez
            no deben consumir una pantalla entera. */}
        {estado === 'vacio' && (
          <PanelVacio icono={icon} titulo={vacioTitulo} detalle={vacioDetalle} />
        )}
        {estado === 'ok' && children}
        {estado === 'ok' && nota && (
          <p className="mt-2 text-[11px] text-muted-foreground">{nota}</p>
        )}
      </CardContent>
    </Card>
  )
}

/** Fila de tooltip con monto en formato money es-PE (reemplaza el default). */
function FilaTooltipMoney({
  color,
  etiqueta,
  texto,
}: {
  color: string | undefined
  etiqueta: string
  texto: string
}): JSX.Element {
  return (
    <>
      <span
        className="h-2.5 w-2.5 shrink-0 rounded-[2px]"
        style={{ background: color ?? 'var(--muted-foreground)' }}
      />
      <div className="flex flex-1 items-center justify-between gap-3 leading-none">
        <span className="text-muted-foreground">{etiqueta}</span>
        <span className="font-mono font-medium tabular-nums text-foreground">{texto}</span>
      </div>
    </>
  )
}

// Filas demo ya derivadas (shape idéntico al de las RPCs).
interface FilasDemo {
  capital: FilaCapitalMes[]
  pagos: FilaPagosMes[]
  vencimientos: FilaVencimientos[]
}

// ── Componente principal ───────────────────────────────────────────────────────

export function GraficasGerencia(): JSX.Element {
  const { yo } = useAuth()
  const esDemo = yo?.demo === true
  // Solo una sesión autenticada real consulta las RPCs (enabled): en demo las
  // queries quedan inertes y NINGÚN request sale hacia Supabase.
  const sesionReal = !!yo && !esDemo

  const [filasDemo, setFilasDemo] = useState<FilasDemo | null>(null)
  useEffect(() => {
    if (!esDemo) return undefined
    let vivo = true
    // Guard literal (mismo que store.tsx/contratos.tsx): en prod DEV es false →
    // Rolldown elimina el chunk de fixtures/derivación del bundle.
    if (import.meta.env.DEV && import.meta.env.VITE_ENABLE_DEMO === 'true') {
      void import('@/lib/demo-metricas')
        .then((m) => {
          if (!vivo) return
          setFilasDemo({
            capital: m.demoMetricasCapitalMes(),
            pagos: m.demoMetricasPagosMes(),
            vencimientos: m.demoMetricasVencimientos(DIAS_VENCIMIENTOS),
          })
        })
        .catch((error: unknown) => {
          if (!vivo) return
          registrarError('demo.metricas_carga_fallida', error)
          // Fixtures inaccesibles: estados vacíos honestos, jamás cifras inventadas.
          setFilasDemo({ capital: [], pagos: [], vencimientos: [] })
        })
    }
    return () => {
      vivo = false
    }
  }, [esDemo])

  const qCapital = useMetricasCapitalMes(sesionReal)
  const qPagos = useMetricasPagosMes(sesionReal)
  const qVencimientos = useMetricasVencimientos(sesionReal, DIAS_VENCIMIENTOS)

  // Fuente unificada por gráfica: filas demo derivadas o data de la RPC.
  // useMemo con el `?? []` DENTRO: el fallback debe ser una referencia estable
  // o los useMemo de los pivots recalcularían en cada render (aviso del lint).
  const filasCapital = useMemo(
    () => (esDemo ? (filasDemo?.capital ?? []) : (qCapital.data ?? [])),
    [esDemo, filasDemo, qCapital.data],
  )
  const filasVencimientos = useMemo(
    () => (esDemo ? (filasDemo?.vencimientos ?? []) : (qVencimientos.data ?? [])),
    [esDemo, filasDemo, qVencimientos.data],
  )
  // La gráfica de pagos solo habla de pagado/vencido: las filas 'pendiente'/
  // 'trasladado' no deben abrir tabs de moneda vacíos ni fingir que "hay data".
  const filasPagos = useMemo(() => {
    const crudas = esDemo ? (filasDemo?.pagos ?? []) : (qPagos.data ?? [])
    return crudas.filter((f) => f.estado === 'pagado' || f.estado === 'vencido')
  }, [esDemo, filasDemo, qPagos.data])

  const demoCargando = esDemo && filasDemo == null

  const estadoCapital = esDemo
    ? estadoDe(demoCargando, false, filasCapital.length === 0)
    : estadoDe(qCapital.isPending, qCapital.isError, filasCapital.length === 0)
  const estadoPagos = esDemo
    ? estadoDe(demoCargando, false, filasPagos.length === 0)
    : estadoDe(qPagos.isPending, qPagos.isError, filasPagos.length === 0)
  const estadoVencimientos = esDemo
    ? estadoDe(demoCargando, false, filasVencimientos.length === 0)
    : estadoDe(qVencimientos.isPending, qVencimientos.isError, filasVencimientos.length === 0)

  // Moneda activa por gráfica (por defecto la primera con datos, PEN primero).
  const [monedaCapital, setMonedaCapital] = useState<Moneda>('PEN')
  const [monedaPagos, setMonedaPagos] = useState<Moneda>('PEN')
  const [monedaVencimientos, setMonedaVencimientos] = useState<Moneda>('PEN')

  const monedasCapital = useMemo(() => monedasConDatos(filasCapital), [filasCapital])
  // Los pagos pueden registrarse en cualquiera de las dos monedas. El selector
  // permanece visible aunque una de ellas todavía no tenga movimientos.
  const monedasPagos: Moneda[] = ['PEN', 'USD']
  const monedasVencimientos = useMemo(() => monedasConDatos(filasVencimientos), [filasVencimientos])

  const monCapital = monedasCapital.includes(monedaCapital) ? monedaCapital : (monedasCapital[0] ?? 'PEN')
  const monPagos = monedasPagos.includes(monedaPagos) ? monedaPagos : (monedasPagos[0] ?? 'PEN')
  const monVencimientos = monedasVencimientos.includes(monedaVencimientos)
    ? monedaVencimientos
    : (monedasVencimientos[0] ?? 'PEN')

  const puntosCapital = useMemo(
    () => pivotCapitalPorMes(filasCapital, monCapital),
    [filasCapital, monCapital],
  )
  const puntosPagos = useMemo(
    () => pivotPagosPorMes(filasPagos, monPagos),
    [filasPagos, monPagos],
  )
  const puntosVencimientos = useMemo(
    () => pivotVencimientosPorMes(filasVencimientos, monVencimientos),
    [filasVencimientos, monVencimientos],
  )

  // Solo se declaran (y salen en la leyenda) las categorías con capital real.
  const categoriasPresentes = useMemo(
    () => CATEGORIAS_STACK.filter((c) => puntosCapital.some((p) => p[c] > 0)),
    [puntosCapital],
  )

  return (
    <div className="grid gap-5 lg:grid-cols-2">
      {/* (a) Capital colocado por mes — barras apiladas por categoría */}
      <CardGrafica
        icon={ChartColumnStacked}
        title="Capital colocado por mes"
        right={<TabsMoneda monedas={monedasCapital} valor={monCapital} onCambio={setMonedaCapital} />}
        nota="Últimos 12 meses · capital de contratos registrados, apilado por categoría."
        vacioTitulo="Aún no hay capital para graficar"
        vacioDetalle="Se llena con los contratos registrados en el portal — al registrar el primer contrato verás el capital colocado por mes."
        estado={estadoCapital}
        onReintentar={esDemo ? undefined : () => void qCapital.refetch()}
        className="lg:col-span-2"
        testid="grafica-capital"
      >
        <ChartContainer config={CFG_CAPITAL} className="h-[240px] w-full">
          <BarChart accessibilityLayer data={puntosCapital} margin={{ top: 8, right: 8, left: 4 }}>
            <CartesianGrid vertical={false} strokeDasharray="3 3" />
            <XAxis dataKey="etiqueta" tickLine={false} axisLine={false} tickMargin={8} />
            <ChartTooltip
              content={
                <ChartTooltipContent
                  formatter={(value, name, item) => (
                    <FilaTooltipMoney
                      color={item.color}
                      etiqueta={String(CFG_CAPITAL[name as keyof typeof CFG_CAPITAL]?.label ?? name)}
                      texto={money(Number(value), monCapital)}
                    />
                  )}
                />
              }
            />
            <ChartLegend content={<ChartLegendContent />} />
            {categoriasPresentes.map((c, i) => (
              <Bar
                key={c}
                dataKey={c}
                stackId="capital"
                fill={`var(--color-${c})`}
                maxBarSize={28}
                radius={i === categoriasPresentes.length - 1 ? [4, 4, 0, 0] : [0, 0, 0, 0]}
              />
            ))}
          </BarChart>
        </ChartContainer>
      </CardGrafica>

      {/* (b) Pagos a inversionistas por mes */}
      <CardGrafica
        icon={HandCoins}
        title="Pagos a inversionistas"
        right={<TabsMoneda monedas={monedasPagos} valor={monPagos} onCambio={setMonedaPagos} />}
        nota="Pagado = intereses del cronograma pagados en el mes · Vencido = intereses vencidos sin pago · No incluye retornos de capital."
        vacioTitulo="Aún no hay pagos para graficar"
        vacioDetalle="Se llena con los cronogramas de los contratos del portal — cuando existan intereses pagados o vencidos verás la comparación mes a mes."
        estado={estadoPagos}
        onReintentar={esDemo ? undefined : () => void qPagos.refetch()}
        testid="grafica-pagos"
      >
        <ChartContainer config={CFG_PAGOS} className="h-[240px] w-full">
          <BarChart accessibilityLayer data={puntosPagos} margin={{ top: 8, right: 8, left: 4 }}>
            <CartesianGrid vertical={false} strokeDasharray="3 3" />
            <XAxis dataKey="etiqueta" tickLine={false} axisLine={false} tickMargin={8} />
            <ChartTooltip
              content={
                <ChartTooltipContent
                  formatter={(value, name, item) => (
                    <FilaTooltipMoney
                      color={item.color}
                      etiqueta={String(CFG_PAGOS[name as keyof typeof CFG_PAGOS]?.label ?? name)}
                      texto={money(Number(value), monPagos)}
                    />
                  )}
                />
              }
            />
            <ChartLegend content={<ChartLegendContent />} />
            <Bar dataKey="pagado" fill="var(--color-pagado)" radius={[4, 4, 0, 0]} maxBarSize={18} />
            <Bar dataKey="vencido" fill="var(--color-vencido)" radius={[4, 4, 0, 0]} maxBarSize={18} />
          </BarChart>
        </ChartContainer>
      </CardGrafica>

      {/* (d) Vencimientos próximos — capital por mes */}
      <CardGrafica
        icon={CalendarClock}
        title="Vencimientos — 12 meses"
        right={
          <TabsMoneda
            monedas={monedasVencimientos}
            valor={monVencimientos}
            onCambio={setMonedaVencimientos}
          />
        }
        nota="Capital de contratos que vencen, mes a mes, para planear renovaciones."
        vacioTitulo="Aún no hay vencimientos para graficar"
        vacioDetalle="Se llena con las fechas de fin de los contratos vigentes — al registrar contratos verás el capital que vence en los próximos 12 meses."
        estado={estadoVencimientos}
        onReintentar={esDemo ? undefined : () => void qVencimientos.refetch()}
        testid="grafica-vencimientos"
      >
        <ChartContainer config={CFG_VENCIMIENTOS} className="h-[240px] w-full">
          <BarChart accessibilityLayer data={puntosVencimientos} margin={{ top: 8, right: 8, left: 4 }}>
            <CartesianGrid vertical={false} strokeDasharray="3 3" />
            <XAxis dataKey="etiqueta" tickLine={false} axisLine={false} tickMargin={8} />
            <ChartTooltip
              content={
                <ChartTooltipContent
                  formatter={(value, _name, item) => {
                    const punto = item.payload as { contratos?: number } | undefined
                    const n = punto?.contratos ?? 0
                    return (
                      <FilaTooltipMoney
                        color={item.color}
                        etiqueta={`${n} ${n === 1 ? 'contrato' : 'contratos'}`}
                        texto={money(Number(value), monVencimientos)}
                      />
                    )
                  }}
                />
              }
            />
            <Bar dataKey="capital" fill="var(--color-capital)" radius={[4, 4, 0, 0]} maxBarSize={28} />
          </BarChart>
        </ChartContainer>
      </CardGrafica>
    </div>
  )
}

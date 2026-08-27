// Hoy · Gerencia — "Distribución de leads": pirámide de lectura en 3 niveles.
//
//   Nivel 1 (5 segundos):  resumen en lenguaje natural + "Lo que merece tu
//                          atención" (evidencia, nunca órdenes).
//   Nivel 2 (30 segundos): una tarjeta legible por analista, con orden
//                          elegible y criterio declarado.
//   Nivel 3 (bajo demanda): asistente de reparto por monto + tabla completa
//                          por rangos como respaldo.
//
// Reglas congeladas que la interfaz respeta (vault "Distribución de leads por
// capital y trazabilidad CRM"): PEN y USD jamás se suman; conversión =
// ventas ÷ (ventas + descartes) y sin denominador se dice "sin resultados"
// (jamás un 0% inventado); recibidos del período y cartera actual se muestran
// juntos; ninguna pieza emite "Priorizar/Pausar" — orden con criterio visible.
import {
  useEffect,
  useId,
  useMemo,
  useState,
  type FormEvent,
  type JSX,
} from 'react'
import {
  AlertTriangle,
  CalendarDays,
  Check,
  ChevronDown,
  Inbox,
  Pencil,
  RefreshCw,
  Users,
  X,
} from 'lucide-react'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { Progress } from '@/components/ui/progress'
import { Skeleton } from '@/components/ui/skeleton'
import type {
  MetricasDistribucionLeadsV3 as MetricasDistribucionLeadsContrato,
  MetricaDistribucionAnalistaV3,
  MetricasPorRepartir,
  RangoCapitalPen,
  RangoCapitalPenId,
  RangoDistribucionAnalistaV3,
} from '@/lib/metricas-distribucion'
import {
  avisosAtencion,
  candidatosReparto,
  equiposDistribucion,
  estadoSondasDistribucion,
  fichaAnalista,
  hoyLimaIso,
  idEquipoDeAnalista,
  ordenarFichas,
  plural,
  porcentajePunteria,
  presetsPeriodo,
  resumenEquipo,
  ORDEN_FICHAS_ETIQUETAS,
  type EquipoDistribucion,
  type FichaAnalista,
  type OrdenFichas,
  type SeleccionReparto,
} from '@/lib/distribucion-lecturas'
import { money, type Moneda } from '@/lib/format'
import { SEMAFORO, SEV_COLOR } from '@/lib/semaforo'
import { cn } from '@/lib/utils'

// Alias públicos para que componente, API y tests compartan una sola verdad:
// el contrato Valibot que valida la fotografía completa de la RPC (V3 desde
// F3 de «Conversión única»: la puntería y el núcleo vienen servidos).
export type MetricasDistribucionLeads = MetricasDistribucionLeadsContrato
export type RangoCapitalDistribucion = RangoCapitalPen
export type RangoAnalistaDistribucion = RangoDistribucionAnalistaV3
export type AnalistaDistribucionLeads = MetricaDistribucionAnalistaV3
export type RangoColaDistribucion = MetricasPorRepartir['total']['pen']['rangos'][number]
export type BandejaDistribucion = MetricasPorRepartir['bandejas'][number]
type ColaDistribucion = MetricasPorRepartir['total']

export interface DistribucionLeadsGerenciaProps {
  datos?: MetricasDistribucionLeads | null | undefined
  cargando: boolean
  error: string | null
  modoDemo?: boolean
  mostrarOperacion?: boolean
  mostrarPeriodo?: boolean
  desde: string
  hasta: string
  onCambiarPeriodo: (desde: string, hasta: string) => void
  onReintentar: () => void
  onEditarCapacidad: (analistaId: string, capacidad: number | null) => void | Promise<void>
}

const ENTERO = new Intl.NumberFormat('es-PE', { maximumFractionDigits: 0 })
const MARGEN_RECORTE = 2
const TARJETA_RESUMEN_CLASS =
  'min-w-0 rounded-xl border border-border/80 bg-card px-4 py-4 shadow-[0_10px_24px_-24px_rgba(15,31,61,0.8)]'

type AvisoAtencion = ReturnType<typeof avisosAtencion>[number]
type CandidatoReparto = ReturnType<typeof candidatosReparto>['candidatos'][number]
type ModoTablaRangos = 'carga' | 'conversion'

interface ListaRecortada<T> {
  elementos: T[]
  ocultos: number
}

function recortarConMargen<T>(
  elementos: T[],
  limite: number,
  mostrarTodos: boolean,
): ListaRecortada<T> {
  const visibles =
    !mostrarTodos && elementos.length > limite + MARGEN_RECORTE
      ? elementos.slice(0, limite)
      : elementos
  return { elementos: visibles, ocultos: elementos.length - visibles.length }
}

function filtrarFichasPorEquipo(
  fichas: FichaAnalista[],
  equipoId: string | null,
): FichaAnalista[] {
  if (equipoId == null) return fichas
  return fichas.filter((ficha) => idEquipoDeAnalista(ficha.analista) === equipoId)
}

function capacidadDesdeTexto(valor: string): number | null | undefined {
  const limpio = valor.trim()
  if (limpio === '') return null
  const capacidad = Number(limpio)
  return Number.isInteger(capacidad) && capacidad >= 1 && capacidad <= 1000
    ? capacidad
    : undefined
}

function avisoVisible(aviso: AvisoAtencion, mostrarOperacion: boolean): boolean {
  if (mostrarOperacion) return true
  return !(
    aviso.id === 'altos-sin-asignar'
    || aviso.id === 'cola-gerencia'
    || aviso.id.startsWith('bandeja-')
  )
}

/** Montos de cartera SIEMPRE redondeados a enteros: lectura gerencial. */
function dinero(valor: number, moneda: Moneda): string {
  return money(Math.round(valor), moneda)
}

function rangosPen(datos: MetricasDistribucionLeads): RangoCapitalDistribucion[] {
  return datos.rangos
    .filter((rango) => rango.id !== 'sin_monto')
    .sort((a, b) => a.orden - b.orden)
}

function rangoDeCola(
  cola: ColaDistribucion,
  rangoId: RangoColaDistribucion['rango_id'],
): RangoColaDistribucion {
  return (
    cola.pen.rangos.find((rango) => rango.rango_id === rangoId) ?? {
      rango_id: rangoId,
      cantidad: 0,
      capital: 0,
    }
  )
}

function rangoDeAnalista(
  analista: AnalistaDistribucionLeads,
  rangoId: RangoCapitalPenId,
): RangoAnalistaDistribucion {
  return (
    analista.pen.rangos.find((rango) => rango.rango_id === rangoId) ?? {
      rango_id: rangoId,
      cartera_actual: { episodios: 0, capital: 0 },
      cohorte: {
        episodios_recibidos: 0,
        leads_unicos_recibidos: 0,
        convertidos: 0,
        descartados: 0,
        leads_unicos_resueltos: 0,
      },
      // Rango vacío del fallback: sin resueltos el % es «aún no se sabe».
      conversion: { convertidos: 0, resueltos: 0, pct: null },
    }
  )
}

/** Mes del período en palabras («agosto de 2026»): el rótulo nombra el mes (H4/H5). */
function mesEnPalabras(fechaIso: string): string {
  return new Intl.DateTimeFormat('es-PE', {
    timeZone: 'America/Lima',
    month: 'long',
    year: 'numeric',
  }).format(new Date(`${fechaIso}T12:00:00Z`))
}

/** % del núcleo tal cual lo sirve el servidor (2 decimales), en es-PE. */
function porcentajeNucleo(pct: number | null): string {
  if (pct == null) return '—'
  return `${new Intl.NumberFormat('es-PE', { maximumFractionDigits: 2 }).format(pct)}%`
}

// ── Período: atajos + personalizado ──────────────────────────────────────────

function PeriodoControl({
  desde,
  hasta,
  cargando,
  onCambiarPeriodo,
}: Pick<
  DistribucionLeadsGerenciaProps,
  'desde' | 'hasta' | 'cargando' | 'onCambiarPeriodo'
>): JSX.Element {
  const [hoy] = useState(() => hoyLimaIso())
  const presets = useMemo(() => presetsPeriodo(hoy), [hoy])
  const presetActivo = presets.find((preset) => preset.desde === desde && preset.hasta === hasta)
  const [personalizadoAbierto, setPersonalizadoAbierto] = useState(false)
  const [desdeBorrador, setDesdeBorrador] = useState(desde)
  const [hastaBorrador, setHastaBorrador] = useState(hasta)
  const [errorPeriodo, setErrorPeriodo] = useState<string | null>(null)

  useEffect(() => {
    setDesdeBorrador(desde)
    setHastaBorrador(hasta)
    setErrorPeriodo(null)
  }, [desde, hasta])

  const aplicar = (evento: FormEvent<HTMLFormElement>) => {
    evento.preventDefault()
    if (!desdeBorrador || !hastaBorrador) {
      setErrorPeriodo('Selecciona las dos fechas del período.')
      return
    }
    if (desdeBorrador > hastaBorrador) {
      setErrorPeriodo('La fecha Desde no puede ser posterior a la fecha Hasta.')
      return
    }
    setErrorPeriodo(null)
    onCambiarPeriodo(desdeBorrador, hastaBorrador)
  }

  return (
    <div className="space-y-2" role="group" aria-label="Período de análisis">
      <div className="flex flex-wrap gap-1.5">
        {presets.map((preset) => {
          const activo = preset.id === presetActivo?.id
          return (
            <Button
              key={preset.id}
              type="button"
              size="sm"
              variant={activo ? 'default' : 'outline'}
              aria-pressed={activo}
              disabled={cargando}
              onClick={() => {
                setPersonalizadoAbierto(false)
                onCambiarPeriodo(preset.desde, preset.hasta)
              }}
            >
              {preset.etiqueta}
            </Button>
          )
        })}
        <Button
          type="button"
          size="sm"
          variant={!presetActivo || personalizadoAbierto ? 'default' : 'outline'}
          aria-pressed={personalizadoAbierto || !presetActivo}
          onClick={() => setPersonalizadoAbierto((abierto) => !abierto)}
        >
          <CalendarDays /> Personalizado
        </Button>
      </div>
      {(personalizadoAbierto || !presetActivo) && (
        <form className="flex flex-wrap items-end gap-2" onSubmit={aplicar} noValidate>
          <label className="grid gap-1 text-xs font-bold text-muted-foreground">
            Desde
            <input
              type="date"
              value={desdeBorrador}
              onChange={(evento) => setDesdeBorrador(evento.target.value)}
              className="h-9 rounded-md border border-input bg-card px-2 text-sm font-medium text-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
              required
            />
          </label>
          <label className="grid gap-1 text-xs font-bold text-muted-foreground">
            Hasta
            <input
              type="date"
              value={hastaBorrador}
              onChange={(evento) => setHastaBorrador(evento.target.value)}
              className="h-9 rounded-md border border-input bg-card px-2 text-sm font-medium text-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
              required
            />
          </label>
          <Button type="submit" variant="outline" size="sm" disabled={cargando}>
            Aplicar
          </Button>
          {errorPeriodo && (
            <p className="basis-full text-xs font-medium text-destructive" role="alert">
              {errorPeriodo}
            </p>
          )}
        </form>
      )}
    </div>
  )
}

function CargandoDistribucion(): JSX.Element {
  return (
    <CardContent className="space-y-4 py-5" aria-busy="true" role="status">
      <span className="sr-only">Cargando distribución de leads</span>
      <div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-4">
        {Array.from({ length: 4 }, (_, indice) => (
          <Skeleton key={indice} className="h-20" />
        ))}
      </div>
      <Skeleton className="h-14 w-full" />
      {Array.from({ length: 3 }, (_, indice) => (
        <Skeleton key={indice} className="h-28 w-full" />
      ))}
    </CardContent>
  )
}

// ── Nivel 1: resumen + atención ──────────────────────────────────────────────

function ResumenDistribucion({
  datos,
  mostrarOperacion,
}: {
  datos: MetricasDistribucionLeads
  mostrarOperacion: boolean
}): JSX.Element {
  // Todo servido por la RPC V3 (F3): la puntería PEN/USD —incluida la suma de
  // dólares que antes hacía este componente— y la cifra del núcleo. Aquí no
  // se suma ni se divide nada.
  const punteria = datos.resumen.conversion
  const conversionPen = porcentajePunteria(punteria.pen.pct)
  const conversionUsd = porcentajePunteria(punteria.usd.pct)
  const porRepartir = datos.resumen.por_repartir_actuales
  const sondas = estadoSondasDistribucion(datos)

  return (
    <dl className={`grid gap-3 sm:grid-cols-2 ${mostrarOperacion ? 'xl:grid-cols-4' : 'xl:grid-cols-3'}`}>
      <div className={TARJETA_RESUMEN_CLASS}>
        <dt className="text-[11px] font-bold uppercase tracking-[0.08em] text-muted-foreground">
          Leads con analista
        </dt>
        <dd className="mt-1.5 text-3xl font-extrabold tracking-tight tabular-nums text-primary">
          {ENTERO.format(datos.resumen.asignados_actuales)}
        </dd>
        <dd className="mt-1 text-xs leading-relaxed text-muted-foreground">
          {dinero(datos.resumen.capital_pen_asignado_actual, 'PEN')} en soles ·{' '}
          {dinero(datos.resumen.capital_usd_asignado_actual, 'USD')} en dólares
        </dd>
      </div>

      {mostrarOperacion && <div className={TARJETA_RESUMEN_CLASS}>
        <dt className="text-[11px] font-bold uppercase tracking-[0.08em] text-muted-foreground">
          Por repartir
        </dt>
        <dd
          className="mt-1.5 text-3xl font-extrabold tracking-tight tabular-nums"
          style={{ color: porRepartir > 0 ? SEMAFORO.atencion : SEMAFORO.ok }}
        >
          {ENTERO.format(porRepartir)}
        </dd>
        <dd className="mt-1 text-xs leading-relaxed text-muted-foreground">
          {porRepartir > 0
            ? 'Esperan en Gerencia o en bandejas de supervisor'
            : 'Todo está asignado'}
        </dd>
      </div>}

      <div className={TARJETA_RESUMEN_CLASS}>
        <dt className="text-[11px] font-bold uppercase tracking-[0.08em] text-muted-foreground">
          Conversión del mes
        </dt>
        {sondas.mostrarNucleo ? (
          <>
            <dd className="mt-1.5 text-3xl font-extrabold tracking-tight tabular-nums text-primary">
              {porcentajeNucleo(punteria.nucleo_conversion_pct)}
            </dd>
            <dd className="mt-1 text-xs leading-relaxed text-muted-foreground">
              {/* D8 + F2.6 (27/08): el total de HOY suma también al ex-roster,
                  así que la identidad volvió a ser verdad MEDIDA (verificada
                  contra el servidor en el mismo snapshot antes de afirmarla
                  aquí). Si dejara de cuadrar, el aviso de sondas lo dice. */}
              La misma cifra que HOY, Metas, Conversiones y el Ranking · cohorte por asignación,{' '}
              {mesEnPalabras(datos.cohorte.desde_inclusivo)} · referidos ponderados y fuera de la
              base
            </dd>
          </>
        ) : (
          <>
            <dd className="mt-1.5 text-3xl font-extrabold tracking-tight tabular-nums text-muted-foreground">
              —
            </dd>
            <dd className="mt-1 text-xs leading-relaxed text-muted-foreground">
              {sondas.motivoOculto === 'descuadre'
                ? 'Cifras en revisión: la verificación interna no cuadró.'
                : 'La cifra única del mes se verifica solo con un mes completo. Elige «Este mes» para verla.'}
            </dd>
          </>
        )}
      </div>

      <div className={TARJETA_RESUMEN_CLASS}>
        <dt className="text-[11px] font-bold uppercase tracking-[0.08em] text-muted-foreground">
          Puntería del período
        </dt>
        <dd
          role="group"
          aria-label="Cierres sobre leads resueltos, por moneda"
          className="mt-2 grid grid-cols-2 divide-x divide-border"
        >
          <div className="min-w-0 pr-3">
            <span className="block text-[11px] font-extrabold tracking-wide text-accent">Soles</span>
            <span className="mt-0.5 block text-2xl font-extrabold tracking-tight tabular-nums text-primary">
              {conversionPen ?? '—'}
            </span>
            <span className="mt-1 block text-xs leading-snug text-muted-foreground">
              {punteria.pen.resueltos > 0
                ? `${punteria.pen.convertidos} ${plural(punteria.pen.convertidos, 'venta', 'ventas')} de ${punteria.pen.resueltos} leads resueltos`
                : 'Aún sin leads resueltos'}
            </span>
          </div>
          <div className="min-w-0 pl-3">
            <span className="block text-[11px] font-extrabold tracking-wide text-accent">Dólares</span>
            <span className="mt-0.5 block text-2xl font-extrabold tracking-tight tabular-nums text-primary">
              {conversionUsd ?? '—'}
            </span>
            <span className="mt-1 block text-xs leading-snug text-muted-foreground">
              {punteria.usd.resueltos > 0
                ? `${punteria.usd.convertidos} ${plural(punteria.usd.convertidos, 'venta', 'ventas')} de ${punteria.usd.resueltos} leads resueltos`
                : 'Aún sin leads resueltos'}
            </span>
          </div>
        </dd>
        <dd className="mt-1.5 text-[11px] leading-relaxed text-muted-foreground">
          De lo que cada quien terminó de trabajar en el período, cuánto ganó.
        </dd>
      </div>
    </dl>
  )
}

/** F3.4: los avisos de las sondas se dicen; los descuadres además ocultan. */
function AvisoSondas({ datos }: { datos: MetricasDistribucionLeads }): JSX.Element | null {
  const sondas = estadoSondasDistribucion(datos)
  const descuadre = sondas.motivoOculto === 'descuadre'
  if (!descuadre && sondas.avisos.length === 0) return null

  return (
    <div
      className="flex items-start gap-3 rounded-lg border border-warning/35 bg-warning/5 px-4 py-3"
      role="status"
    >
      <AlertTriangle className="mt-0.5 size-4 shrink-0 text-warning" aria-hidden />
      <div>
        <p className="text-sm font-bold text-foreground">
          {descuadre ? 'Cifras en revisión' : 'Aviso sobre la cifra del mes'}
        </p>
        <div className="mt-0.5 space-y-0.5 text-xs leading-relaxed text-muted-foreground">
          {descuadre && (
            <p>
              La verificación interna del mes no cuadró y la conversión del mes se oculta hasta
              revisarla. El resto del tablero sigue siendo confiable.
            </p>
          )}
          {sondas.avisos.map((aviso) => (
            <p key={aviso}>{aviso}</p>
          ))}
        </div>
      </div>
    </div>
  )
}

function AtencionHoy({
  datos,
  mostrarOperacion,
}: {
  datos: MetricasDistribucionLeads
  mostrarOperacion: boolean
}): JSX.Element {
  const avisos = avisosAtencion(datos).filter((aviso) => avisoVisible(aviso, mostrarOperacion))

  if (avisos.length === 0) {
    return (
      <section
        aria-labelledby="atencion-hoy-titulo"
        className="flex items-start gap-3 rounded-xl border border-border/80 bg-card px-4 py-3.5"
      >
        <Check className="mt-0.5 size-5 shrink-0" style={{ color: SEMAFORO.ok }} aria-hidden />
        <div>
          <h4 id="atencion-hoy-titulo" className="text-sm font-extrabold text-foreground">
            Sin pendientes urgentes
          </h4>
          <p className="mt-0.5 text-xs leading-relaxed text-muted-foreground">
            No hay alertas de carga, asignación ni actividad en esta fotografía.
          </p>
        </div>
      </section>
    )
  }

  return (
    <section
      aria-labelledby="atencion-hoy-titulo"
      className="rounded-xl border border-border/80 bg-card px-4 py-3.5"
    >
      <h4 id="atencion-hoy-titulo" className="text-sm font-extrabold text-foreground">
        Lo que merece tu atención
      </h4>
      <ul className="mt-2 space-y-1.5">
        {avisos.map((aviso) => (
          <li key={aviso.id} className="flex items-start gap-2.5 text-sm leading-relaxed text-foreground">
            <span
              className="mt-1.5 size-2.5 shrink-0 rounded-full"
              style={{ backgroundColor: SEV_COLOR[aviso.severidad === 'critica' ? 'critica' : 'media'] }}
              aria-hidden
            />
            <span>
              {aviso.severidad === 'critica' && <span className="sr-only">Crítico: </span>}
              {aviso.texto}
            </span>
          </li>
        ))}
      </ul>
      <p className="mt-2 text-[11px] leading-relaxed text-muted-foreground">
        Evidencia del tablero — la decisión de qué hacer es de Gerencia.
      </p>
    </section>
  )
}

// ── Nivel 2: tarjetas por analista ───────────────────────────────────────────

interface EdicionCapacidad {
  analistaId: string
  valor: string
}

function TarjetaAnalista({
  ficha,
  mostrarEquipo,
  edicion,
  guardando,
  errorCapacidad,
  onEmpezarEdicion,
  onCambiarEdicion,
  onCancelarEdicion,
  onGuardarCapacidad,
}: {
  ficha: FichaAnalista
  mostrarEquipo: boolean
  edicion: EdicionCapacidad | null
  guardando: boolean
  errorCapacidad: string | null
  onEmpezarEdicion: (analista: AnalistaDistribucionLeads) => void
  onCambiarEdicion: (valor: string) => void
  onCancelarEdicion: () => void
  onGuardarCapacidad: (evento: FormEvent<HTMLFormElement>, analista: AnalistaDistribucionLeads) => void
}): JSX.Element {
  const { analista } = ficha
  const editando = edicion?.analistaId === analista.analista_id
  const objetivo = analista.capacidad.objetivo
  const carga = analista.capacidad.carga_activa

  return (
    <article
      aria-label={`Ficha de ${analista.nombre}`}
      className="flex flex-col gap-3 rounded-2xl border border-border/80 bg-card p-4 shadow-[0_14px_30px_-28px_rgba(15,31,61,0.85)]"
    >
      <div className="flex items-start justify-between gap-3">
        <div className="flex min-w-0 items-center gap-3">
          <Avatar nombre={analista.nombre} className="size-10" />
          <div className="min-w-0">
            <h5 className="truncate text-sm font-extrabold text-foreground">{analista.nombre}</h5>
            <p className="truncate text-xs text-muted-foreground">
              {analista.rol === 'supervisor' ? 'Supervisor con cartera' : 'Analista'}
              {mostrarEquipo && analista.supervisor_nombre
                ? ` · Equipo de ${analista.supervisor_nombre}`
                : ''}
            </p>
          </div>
        </div>
        {!analista.disponible_para_recibir && (
          <Badge color="var(--warning)" variant="outline" dot>
            No recibe por ahora
          </Badge>
        )}
      </div>

      <div>
        <div className="flex items-center justify-between gap-2">
          <p className="text-xs font-bold uppercase tracking-wide text-muted-foreground">
            Cartera actual
          </p>
          {analista.disponible_para_recibir && !editando && (
            <Button
              type="button"
              variant="ghost"
              size="xs"
              className="size-7 px-0"
              onClick={() => onEmpezarEdicion(analista)}
              aria-label={`Editar límite de cartera de ${analista.nombre}`}
              title="Editar límite de cartera"
            >
              <Pencil />
            </Button>
          )}
        </div>
        {editando ? (
          <form
            className="mt-1.5 space-y-1.5"
            onSubmit={(evento) => onGuardarCapacidad(evento, analista)}
            noValidate
          >
            <label className="sr-only" htmlFor={`capacidad-${analista.analista_id}`}>
              Límite de cartera para {analista.nombre}
            </label>
            <input
              id={`capacidad-${analista.analista_id}`}
              type="number"
              min={1}
              max={1000}
              step={1}
              value={edicion.valor}
              onChange={(evento) => onCambiarEdicion(evento.target.value)}
              placeholder="Sin límite"
              className="h-9 w-full rounded-md border border-input bg-card px-2 text-right text-sm tabular-nums focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
              disabled={guardando}
            />
            <div className="flex justify-end gap-1">
              <Button type="submit" size="xs" variant="default" disabled={guardando}>
                <Check /> Guardar
              </Button>
              <Button
                type="button"
                size="xs"
                variant="ghost"
                onClick={onCancelarEdicion}
                disabled={guardando}
                aria-label={`Cancelar edición del límite de cartera de ${analista.nombre}`}
              >
                <X />
              </Button>
            </div>
            {errorCapacidad && (
              <p className="text-xs font-medium leading-tight text-destructive" role="alert">
                {errorCapacidad}
              </p>
            )}
          </form>
        ) : (
          <>
            <p className="mt-1 text-base font-extrabold tabular-nums text-primary">
              {carga}
              <span className="font-medium text-muted-foreground">
                {objetivo != null ? ` de ${objetivo} leads` : ' leads · sin límite definido'}
              </span>
            </p>
            {objetivo != null && (
              <>
                <Progress
                  value={Math.min(100, ficha.uso ?? 0)}
                  color={
                    ficha.lleno
                      ? 'var(--destructive)'
                      : (ficha.uso ?? 0) >= 85
                        ? 'var(--warning)'
                        : 'var(--accent)'
                  }
                  className="mt-1.5 h-2"
                />
                <p className="mt-1 text-xs tabular-nums text-muted-foreground">
                  {ficha.lleno
                    ? `Al tope de su límite (${ficha.uso}%)`
                    : `${ficha.cuposLibres} ${plural(ficha.cuposLibres ?? 0, 'cupo libre', 'cupos libres')} · ${ficha.uso}% del límite`}
                </p>
              </>
            )}
          </>
        )}
      </div>

      <div className="space-y-1 border-t border-border/70 pt-2.5 text-sm leading-relaxed text-foreground">
        <p>
          Recibió <strong className="tabular-nums">{ficha.recibidosPeriodo}</strong>{' '}
          {plural(ficha.recibidosPeriodo, 'lead', 'leads')} en el período.
        </p>
        <p>
          {ficha.conversionPen
            ? (
                <>
                  Cierra el <strong className="tabular-nums">{ficha.conversionPen.pct}</strong> de lo
                  que resuelve en soles ({ficha.conversionPen.convertidos} de{' '}
                  {ficha.conversionPen.resueltos})
                </>
              )
            : 'Aún sin ventas ni descartes en soles'}
          {ficha.conUsd && (
            <span className="text-muted-foreground">
              {' · '}en dólares:{' '}
              {ficha.conversionUsd
                ? `${ficha.conversionUsd.pct} (${ficha.conversionUsd.convertidos} de ${ficha.conversionUsd.resueltos})`
                : 'sin resultados aún'}
            </span>
          )}
        </p>
      </div>

      {ficha.sinAtender > 0 && (
        <div className="flex flex-wrap gap-1.5 text-xs font-semibold">
          <span
            className="rounded-md px-2 py-1 tabular-nums"
            style={{
              color: SEMAFORO.atencion,
              backgroundColor: 'color-mix(in oklab, currentColor 10%, transparent)',
            }}
          >
            {ficha.sinAtender} sin atender
          </span>
        </div>
      )}

      <div className="mt-auto border-t border-border/70 pt-2.5 text-xs leading-relaxed text-muted-foreground">
        <p className="tabular-nums">
          {dinero(ficha.capitalPen, 'PEN')} en soles
          {ficha.conUsd ? ` · ${dinero(ficha.capitalUsd, 'USD')} en dólares` : ''}
        </p>
        {ficha.transferidos + ficha.parqueados > 0 && (
          <p className="mt-0.5">
            Salidas del período: {ficha.transferidos}{' '}
            {plural(ficha.transferidos, 'transferido', 'transferidos')} · {ficha.parqueados}{' '}
            {plural(ficha.parqueados, 'parqueado', 'parqueados')}
          </p>
        )}
      </div>
    </article>
  )
}

/** Tope del primer vistazo: con equipos grandes, el resto se abre bajo demanda. */
const TOPE_FICHAS = 6

function TarjetaEquipoFiltro({
  titulo,
  subtitulo,
  fichas,
  activo,
  onClick,
}: {
  titulo: string
  subtitulo: string
  fichas: FichaAnalista[]
  activo: boolean
  onClick: () => void
}): JSX.Element {
  const resumen = resumenEquipo(fichas)
  return (
    <button
      type="button"
      aria-pressed={activo}
      onClick={onClick}
      className={cn(
        'rounded-xl border bg-card p-3 text-left transition-colors hover:bg-muted/40 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
        activo ? 'border-accent ring-2 ring-accent/15' : 'border-border/80',
      )}
    >
      <p className="text-sm font-extrabold text-foreground">{titulo}</p>
      <p className="mt-0.5 text-xs text-muted-foreground">{subtitulo}</p>
      <p className="mt-1.5 text-sm font-bold tabular-nums text-primary">
        {resumen.cargaActiva}
        <span className="font-medium text-muted-foreground">
          {resumen.limiteDefinido != null
            ? ` de ${resumen.limiteDefinido} leads · ${resumen.cuposLibres} ${plural(resumen.cuposLibres, 'cupo libre', 'cupos libres')}`
            : ' leads · límites por definir'}
        </span>
      </p>
      {(resumen.sinAtender > 0 || resumen.llenos > 0) && (
        <p className="mt-1 flex flex-wrap gap-x-3 text-xs font-semibold" style={{ color: SEMAFORO.atencion }}>
          {resumen.sinAtender > 0 && <span>{resumen.sinAtender} sin atender</span>}
          {resumen.llenos > 0 && (
            <span>
              {resumen.llenos} {plural(resumen.llenos, 'analista al tope', 'analistas al tope')}
            </span>
          )}
        </p>
      )}
    </button>
  )
}

function EquipoPorPersona({
  fichas,
  equipos,
  filtroEquipoId,
  onFiltrarEquipo,
  onEditarCapacidad,
}: {
  fichas: FichaAnalista[]
  equipos: EquipoDistribucion[]
  filtroEquipoId: string | null
  onFiltrarEquipo: (equipoId: string | null) => void
  onEditarCapacidad: DistribucionLeadsGerenciaProps['onEditarCapacidad']
}): JSX.Element {
  const [orden, setOrden] = useState<OrdenFichas>('cupos')
  const [mostrarTodas, setMostrarTodas] = useState(false)
  const [edicion, setEdicion] = useState<EdicionCapacidad | null>(null)
  const [guardando, setGuardando] = useState(false)
  const [errorCapacidad, setErrorCapacidad] = useState<string | null>(null)
  const ordenSelectId = useId()

  // El primer vistazo vuelve a ser corto cada vez que cambia la lectura.
  useEffect(() => {
    setMostrarTodas(false)
  }, [filtroEquipoId, orden])

  const visibles = useMemo(() => {
    const filtradas = filtrarFichasPorEquipo(fichas, filtroEquipoId)
    return ordenarFichas(filtradas, orden)
  }, [fichas, filtroEquipoId, orden])

  // Recorte con margen: jamás esconder solo 1-2 tarjetas detrás de un botón.
  const { elementos: recortadas, ocultos: ocultas } = recortarConMargen(
    visibles,
    TOPE_FICHAS,
    mostrarTodas,
  )

  const empezarEdicion = (analista: AnalistaDistribucionLeads) => {
    setEdicion({
      analistaId: analista.analista_id,
      valor: analista.capacidad.objetivo == null ? '' : String(analista.capacidad.objetivo),
    })
    setErrorCapacidad(null)
  }

  const guardarCapacidad = async (
    evento: FormEvent<HTMLFormElement>,
    analista: AnalistaDistribucionLeads,
  ) => {
    evento.preventDefault()
    if (!edicion || edicion.analistaId !== analista.analista_id) return
    const capacidad = capacidadDesdeTexto(edicion.valor)
    if (capacidad === undefined) {
      setErrorCapacidad('Usa un entero entre 1 y 1000, o déjalo vacío.')
      return
    }
    setGuardando(true)
    setErrorCapacidad(null)
    try {
      await onEditarCapacidad(analista.analista_id, capacidad)
      setEdicion(null)
    } catch {
      setErrorCapacidad('No se pudo guardar el límite de cartera. Inténtalo otra vez.')
    } finally {
      setGuardando(false)
    }
  }

  if (fichas.length === 0) {
    return (
      <div className="rounded-lg border border-dashed border-border px-5 py-10 text-center">
        <Users className="mx-auto size-7 text-muted-foreground" aria-hidden />
        <p className="mt-2 text-sm font-semibold">Aún no hay analistas para comparar</p>
        <p className="mt-1 text-xs text-muted-foreground">
          La comparación aparecerá cuando exista un analista activo o un lead asignado.
        </p>
      </div>
    )
  }

  return (
    <section aria-labelledby="equipo-por-persona" className="space-y-3">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h4 id="equipo-por-persona" className="text-base font-extrabold text-primary">
            Tu equipo, persona por persona
          </h4>
          <p className="mt-1 text-xs leading-relaxed text-muted-foreground">
            Carga, resultados y alertas de cada analista. El límite de cartera lo fija Gerencia con
            el lápiz de cada tarjeta.
          </p>
        </div>
        <label
          htmlFor={ordenSelectId}
          className="flex items-center gap-2 text-xs font-bold text-muted-foreground"
        >
          Ordenar por
          <select
            id={ordenSelectId}
            value={orden}
            onChange={(evento) => setOrden(evento.target.value as OrdenFichas)}
            className="h-9 rounded-md border border-input bg-card px-2 text-sm font-medium text-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
          >
            {Object.entries(ORDEN_FICHAS_ETIQUETAS).map(([valor, etiqueta]) => (
              <option key={valor} value={valor}>
                {etiqueta}
              </option>
            ))}
          </select>
        </label>
      </div>

      {equipos.length > 1 && (
        <div
          className="grid gap-2 sm:grid-cols-2 xl:grid-cols-3"
          role="group"
          aria-label="Filtrar por equipo"
        >
          <TarjetaEquipoFiltro
            titulo="Todos los equipos"
            subtitulo={`${fichas.length} ${plural(fichas.length, 'analista', 'analistas')} · toda la operación`}
            fichas={fichas}
            activo={filtroEquipoId == null}
            onClick={() => onFiltrarEquipo(null)}
          />
          {equipos
            .filter((equipo) => equipo.analistas.length > 0)
            .map((equipo) => {
              const fichasEquipo = filtrarFichasPorEquipo(fichas, equipo.id)
              return (
                <TarjetaEquipoFiltro
                  key={equipo.id}
                  titulo={`Equipo de ${equipo.nombre}`}
                  subtitulo={`${fichasEquipo.length} ${plural(fichasEquipo.length, 'analista', 'analistas')} · ${
                    equipo.pendientesBandeja > 0
                      ? `bandeja: ${equipo.pendientesBandeja} ${plural(equipo.pendientesBandeja, 'pendiente', 'pendientes')}`
                      : 'bandeja sin pendientes'
                  }`}
                  fichas={fichasEquipo}
                  activo={filtroEquipoId === equipo.id}
                  onClick={() => onFiltrarEquipo(equipo.id)}
                />
              )
            })}
        </div>
      )}

      <p className="text-[11px] font-medium text-muted-foreground">
        Ordenado por {ORDEN_FICHAS_ETIQUETAS[orden].toLowerCase()}; quien no recibe leads va al
        final. Es un criterio de lectura, no una recomendación.
      </p>

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        {recortadas.map((ficha) => (
          <TarjetaAnalista
            key={ficha.analista.analista_id}
            ficha={ficha}
            mostrarEquipo={filtroEquipoId == null}
            edicion={edicion}
            guardando={guardando}
            errorCapacidad={edicion ? errorCapacidad : null}
            onEmpezarEdicion={empezarEdicion}
            onCambiarEdicion={(valor) =>
              setEdicion((actual) => (actual ? { ...actual, valor } : actual))}
            onCancelarEdicion={() => {
              setEdicion(null)
              setErrorCapacidad(null)
            }}
            onGuardarCapacidad={(evento, analista) => void guardarCapacidad(evento, analista)}
          />
        ))}
      </div>

      {(ocultas > 0 || (mostrarTodas && visibles.length > TOPE_FICHAS + 2)) && (
        <div className="flex justify-center">
          <Button
            type="button"
            variant="outline"
            onClick={() => setMostrarTodas((estado) => !estado)}
          >
            <ChevronDown className={cn('transition-transform', mostrarTodas && 'rotate-180')} />
            {ocultas > 0
              ? `Mostrar ${ocultas === 1 ? 'el analista restante' : `los ${ocultas} analistas restantes`}`
              : 'Mostrar menos'}
          </Button>
        </div>
      )}
    </section>
  )
}

// ── Nivel 3a: asistente de reparto ───────────────────────────────────────────

/** El asistente muestra los primeros candidatos: con orden por espacio, el resto rara vez decide. */
const TOPE_CANDIDATOS = 5

function CandidatoRepartoItem({
  candidato,
  indice,
  moneda,
}: {
  candidato: CandidatoReparto
  indice: number
  moneda: Moneda
}): JSX.Element {
  const { segmento } = candidato
  const enSegmento = moneda === 'PEN' ? 'con este monto' : 'en dólares'

  return (
    <li className="flex flex-wrap items-center gap-3 px-4 py-3 sm:px-5">
      <span
        className="w-6 shrink-0 text-center text-sm font-extrabold tabular-nums text-muted-foreground"
        aria-hidden
      >
        {indice + 1}
      </span>
      <Avatar nombre={candidato.analista.nombre} className="size-9" />
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-bold text-foreground">{candidato.analista.nombre}</p>
        <p className="text-xs leading-snug text-muted-foreground">
          {segmento.conversion
            ? `Cierra el ${segmento.conversion.pct} ${enSegmento} (${segmento.conversion.convertidos} de ${segmento.conversion.resueltos})`
            : `Sin resultados ${enSegmento} aún`}
          {' · '}
          {segmento.activos > 0
            ? `hoy tiene ${segmento.activos} ${enSegmento}`
            : `hoy no tiene leads ${enSegmento}`}
        </p>
      </div>
      <div className="shrink-0 text-right">
        {candidato.cuposLibres != null && candidato.cuposLibres > 0 && (
          <p className="text-sm font-extrabold tabular-nums" style={{ color: SEMAFORO.ok }}>
            {candidato.cuposLibres}{' '}
            {plural(candidato.cuposLibres, 'cupo libre', 'cupos libres')}
          </p>
        )}
        {candidato.cuposLibres == null && (
          <p className="text-sm font-bold text-foreground">Sin límite definido</p>
        )}
        {candidato.lleno && (
          <p className="text-sm font-bold" style={{ color: SEMAFORO.atencion }}>
            Sin cupo
          </p>
        )}
        <p className="text-xs tabular-nums text-muted-foreground">
          {candidato.cargaActiva}{' '}
          {plural(candidato.cargaActiva, 'lead activo', 'leads activos')} en total
        </p>
      </div>
    </li>
  )
}

function AsistenteReparto({ datos }: { datos: MetricasDistribucionLeads }): JSX.Element {
  const rangos = rangosPen(datos)
  const [moneda, setMoneda] = useState<Moneda>('PEN')
  const [rangoId, setRangoId] = useState<RangoCapitalPenId>(rangos[0]?.id ?? 'pen_0_1000')
  const [verTodos, setVerTodos] = useState(false)
  const monedaSelectId = useId()
  const rangoSelectId = useId()

  useEffect(() => {
    setVerTodos(false)
  }, [moneda, rangoId])

  const { candidatos, noReciben } = useMemo(() => {
    const seleccion: SeleccionReparto = moneda === 'PEN' ? { moneda, rangoId } : { moneda }
    return candidatosReparto(datos, seleccion)
  }, [datos, moneda, rangoId])

  // Mismo margen que las tarjetas: nunca esconder 1-2 filas tras un botón.
  const { elementos: listados, ocultos: restantes } = recortarConMargen(
    candidatos,
    TOPE_CANDIDATOS,
    verTodos,
  )

  return (
    <section
      aria-labelledby="asistente-reparto-titulo"
      className="overflow-hidden rounded-2xl border border-border/80 bg-card"
    >
      <div className="border-b border-border bg-muted/15 px-4 py-4 sm:px-5">
        <p className="text-[10px] font-extrabold uppercase tracking-[0.14em] text-accent">
          Asistente de reparto
        </p>
        <h4 id="asistente-reparto-titulo" className="mt-1 text-base font-extrabold text-primary">
          ¿Vas a repartir un lead?
        </h4>
        <p className="mt-1 max-w-2xl text-xs leading-relaxed text-muted-foreground">
          Elige el monto del lead y mira quién tiene espacio y cómo le fue con montos parecidos en
          el período. La decisión final es tuya.
        </p>
        <div className="mt-3 flex flex-wrap items-end gap-2">
          <label
            htmlFor={monedaSelectId}
            className="grid gap-1 text-xs font-bold text-muted-foreground"
          >
            Moneda
            <select
              id={monedaSelectId}
              value={moneda}
              onChange={(evento) => setMoneda(evento.target.value as Moneda)}
              className="h-9 rounded-md border border-input bg-card px-2 text-sm font-medium text-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
            >
              <option value="PEN">Soles</option>
              <option value="USD">Dólares</option>
            </select>
          </label>
          {moneda === 'PEN' ? (
            <label
              htmlFor={rangoSelectId}
              className="grid gap-1 text-xs font-bold text-muted-foreground"
            >
              Monto del lead
              <select
                id={rangoSelectId}
                value={rangoId}
                onChange={(evento) => setRangoId(evento.target.value as RangoCapitalPenId)}
                className="h-9 rounded-md border border-input bg-card px-2 text-sm font-medium text-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
              >
                {rangos.map((rango) => (
                  <option key={rango.id} value={rango.id}>
                    {rango.etiqueta}
                  </option>
                ))}
              </select>
            </label>
          ) : (
            <p className="rounded-md bg-muted/40 px-2.5 py-2 text-xs leading-snug text-muted-foreground">
              Los dólares aún no tienen rangos aprobados: se muestra el total en dólares de cada
              analista.
            </p>
          )}
        </div>
      </div>

      {candidatos.length === 0 ? (
        <p className="px-5 py-6 text-center text-sm text-muted-foreground">
          No hay analistas disponibles para recibir leads por ahora.
        </p>
      ) : (
        <ol className="divide-y divide-border/70">
          {listados.map((candidato, indice) => (
            <CandidatoRepartoItem
              key={candidato.analista.analista_id}
              candidato={candidato}
              indice={indice}
              moneda={moneda}
            />
          ))}
        </ol>
      )}

      {(restantes > 0 || (verTodos && candidatos.length > TOPE_CANDIDATOS + 2)) && (
        <div className="flex justify-center border-t border-border/70 px-4 py-2.5">
          <Button type="button" variant="ghost" size="sm" onClick={() => setVerTodos((estado) => !estado)}>
            <ChevronDown className={cn('transition-transform', verTodos && 'rotate-180')} />
            {restantes > 0
              ? `Ver ${restantes === 1 ? 'el candidato restante' : `los ${restantes} candidatos restantes`}`
              : 'Ver menos'}
          </Button>
        </div>
      )}

      <p className="border-t border-border bg-muted/15 px-4 py-2.5 text-[11px] leading-relaxed text-muted-foreground sm:px-5">
        Ordenados por espacio libre; a igual espacio va primero quien tiene menos leads de este
        monto. {noReciben > 0
          ? `${noReciben} ${plural(noReciben, 'analista no recibe', 'analistas no reciben')} leads por ahora y no se ${plural(noReciben, 'lista', 'listan')}.`
          : ''}
      </p>
    </section>
  )
}

// ── Nivel 3b: tabla completa por rangos (respaldo) ───────────────────────────

function CeldaRangoAnalista({
  dato,
  modo,
}: {
  dato: RangoAnalistaDistribucion
  modo: ModoTablaRangos
}): JSX.Element {
  // Servido por la RPC V3: convertidos, resueltos y % ya calculados por rango.
  const decisiones = dato.conversion.resueltos
  const conversionRango = porcentajePunteria(dato.conversion.pct)

  return (
    <td className="border-b border-r border-border/70 px-2 py-2 text-center">
      {modo === 'carga' ? (
        <div
          className={cn(
            'mx-auto min-w-14 rounded-lg px-1.5 py-1.5 tabular-nums',
            dato.cartera_actual.episodios === 0
              ? 'text-muted-foreground'
              : 'bg-accent/10 text-primary',
          )}
          title={`${dato.cartera_actual.episodios} leads activos · ${dinero(dato.cartera_actual.capital, 'PEN')}`}
        >
          <p className="text-sm font-extrabold">{dato.cartera_actual.episodios}</p>
          <p className="mt-0.5 text-[11px] font-medium text-muted-foreground">
            recibió {dato.cohorte.episodios_recibidos}
          </p>
        </div>
      ) : (
        <div
          className={cn(
            'mx-auto min-w-16 rounded-lg px-1.5 py-1.5 tabular-nums',
            decisiones === 0 ? 'text-muted-foreground' : 'bg-accent/10 text-primary',
          )}
        >
          <p className="text-sm font-extrabold">{conversionRango ?? '—'}</p>
          <p className="mt-0.5 text-[11px] font-medium text-muted-foreground">
            {decisiones > 0 ? `${dato.conversion.convertidos} de ${decisiones}` : 'Sin casos'}
          </p>
        </div>
      )}
    </td>
  )
}

function TablaRangos({
  datos,
  fichas,
}: {
  datos: MetricasDistribucionLeads
  fichas: FichaAnalista[]
}): JSX.Element {
  const [abierta, setAbierta] = useState(false)
  const [modo, setModo] = useState<ModoTablaRangos>('carga')
  const rangos = rangosPen(datos)
  const analistas = useMemo(
    () => ordenarFichas(fichas, 'nombre').map((ficha) => ficha.analista),
    [fichas],
  )

  return (
    <section className="overflow-hidden rounded-2xl border border-border/80 bg-card">
      <div className="flex flex-wrap items-center justify-between gap-3 px-4 py-4 sm:px-5">
        <div>
          <p className="text-[10px] font-extrabold uppercase tracking-[0.14em] text-accent">
            Detalle completo
          </p>
          <h4 className="mt-1 text-base font-extrabold text-primary">Tabla por rangos de monto</h4>
          <p className="mt-1 text-xs leading-relaxed text-muted-foreground">
            Todos los analistas contra los 7 rangos en soles: cartera de hoy, recibidos del período
            y cierres.
          </p>
        </div>
        <Button type="button" variant="outline" onClick={() => setAbierta((estado) => !estado)}>
          <ChevronDown className={cn('transition-transform', abierta && 'rotate-180')} />
          {abierta ? 'Ocultar tabla por rangos' : 'Ver tabla completa por rangos'}
        </Button>
      </div>

      {abierta && (
        <div className="space-y-3 border-t border-border bg-muted/10 p-4 sm:p-5">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="max-w-2xl text-xs leading-relaxed text-muted-foreground">
              {modo === 'carga'
                ? 'Cada celda: leads activos hoy y, debajo, los recibidos del período en ese rango.'
                : 'Cada celda: ventas cerradas ÷ leads resueltos (ventas + descartes) del período en ese rango.'}
            </p>
            <div className="flex rounded-lg bg-muted p-1" role="group" aria-label="Lectura de la tabla">
              <Button
                type="button"
                size="sm"
                variant={modo === 'carga' ? 'default' : 'ghost'}
                onClick={() => setModo('carga')}
              >
                Carga actual
              </Button>
              <Button
                type="button"
                size="sm"
                variant={modo === 'conversion' ? 'default' : 'ghost'}
                onClick={() => setModo('conversion')}
              >
                Conversión por monto
              </Button>
            </div>
          </div>

          <div
            className="ac-scroll overflow-auto rounded-xl border border-border"
            role="region"
            aria-label="Analistas por rango de monto en soles"
          >
            <table className="min-w-[1080px] border-separate border-spacing-0 bg-card text-sm">
              <caption className="sr-only">
                {modo === 'carga'
                  ? 'Carga actual por analista y rango de monto en soles.'
                  : 'Conversión por analista y rango de monto en soles.'}
              </caption>
              <thead>
                <tr className="bg-muted/55 text-left">
                  <th
                    scope="col"
                    className="sticky left-0 z-20 w-44 border-b border-r border-border bg-muted px-4 py-3 text-xs font-bold uppercase tracking-wide text-muted-foreground"
                  >
                    Analista
                  </th>
                  {rangos.map((rango) => (
                    <th
                      key={rango.id}
                      scope="col"
                      className="w-28 border-b border-r border-border/70 px-2 py-2.5 text-center align-bottom text-xs font-bold leading-tight text-foreground"
                    >
                      {rango.etiqueta}
                    </th>
                  ))}
                  <th
                    scope="col"
                    className="w-24 border-b border-border px-3 py-2.5 text-center text-xs font-bold uppercase tracking-wide text-muted-foreground"
                  >
                    {modo === 'carga' ? 'Total activos' : 'Cierres totales'}
                  </th>
                </tr>
              </thead>
              <tbody>
                {analistas.map((analista) => {
                  // Puntería PEN servida por analista: el total no se recalcula.
                  const resueltos = analista.conversion.pen.resueltos
                  const conversionTotal = porcentajePunteria(analista.conversion.pen.pct)
                  return (
                    <tr key={analista.analista_id} className="group hover:bg-muted/20">
                      <th
                        scope="row"
                        className="sticky left-0 z-10 border-b border-r border-border bg-card px-4 py-2.5 text-left group-hover:bg-muted"
                      >
                        <div className="flex min-w-0 items-center gap-2.5">
                          <Avatar nombre={analista.nombre} className="size-8" />
                          <p className="truncate text-sm font-bold text-foreground">{analista.nombre}</p>
                        </div>
                      </th>
                      {rangos.map((rango) => (
                        <CeldaRangoAnalista
                          key={rango.id}
                          dato={rangoDeAnalista(analista, rango.id)}
                          modo={modo}
                        />
                      ))}
                      {modo === 'carga' ? (
                        <td className="border-b border-border px-3 py-2.5 text-center text-base font-extrabold tabular-nums text-primary">
                          {analista.capacidad.carga_activa}
                        </td>
                      ) : (
                        <td className="border-b border-border px-3 py-2.5 text-center">
                          <p className="text-sm font-extrabold tabular-nums text-primary">
                            {conversionTotal ?? '—'}
                          </p>
                          <p className="text-[11px] tabular-nums text-muted-foreground">
                            {analista.conversion.pen.convertidos} de {resueltos}
                          </p>
                        </td>
                      )}
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </section>
  )
}

// ── Colas pendientes y calidad ───────────────────────────────────────────────

function ColaCard({
  titulo,
  subtitulo,
  cola,
  rangos,
  inactiva = false,
}: {
  titulo: string
  subtitulo: string
  cola: ColaDistribucion
  rangos: RangoCapitalDistribucion[]
  inactiva?: boolean
}): JSX.Element {
  const conPendientes = rangos
    .map((rango) => ({ rango, dato: rangoDeCola(cola, rango.id) }))
    .filter(({ dato }) => dato.cantidad > 0)

  return (
    <article className="overflow-hidden rounded-xl border border-border bg-card" aria-label={titulo}>
      <div className="flex flex-wrap items-start justify-between gap-2 border-b border-border px-4 py-3">
        <div>
          <div className="flex items-center gap-2">
            <h5 className="text-sm font-bold text-foreground">{titulo}</h5>
            {inactiva && (
              <Badge color="var(--warning)" variant="outline">
                Supervisor inactivo
              </Badge>
            )}
          </div>
          <p className="mt-0.5 text-xs text-muted-foreground">{subtitulo}</p>
        </div>
        <div className="text-right">
          <p className="text-xl font-extrabold tabular-nums text-primary">{cola.carga_total}</p>
          <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">leads</p>
        </div>
      </div>
      {conPendientes.length > 0 && (
        <div className="flex flex-wrap gap-2 p-3">
          {conPendientes.map(({ rango, dato }) => (
            <div key={rango.id} className="rounded-md border border-border/70 bg-muted/20 px-2.5 py-2">
              <p className="text-[11px] font-bold leading-tight text-muted-foreground">
                {rango.etiqueta}
              </p>
              <p className="mt-1 text-base font-extrabold tabular-nums text-foreground">
                {dato.cantidad}
              </p>
              <p className="text-[11px] tabular-nums text-muted-foreground">
                {dinero(dato.capital, 'PEN')}
              </p>
            </div>
          ))}
        </div>
      )}
      <div className="flex flex-wrap gap-x-5 gap-y-1 border-t border-border bg-muted/15 px-4 py-2 text-xs text-muted-foreground">
        <span>
          <strong className="text-foreground">Soles:</strong> {cola.pen.cantidad} ·{' '}
          {dinero(cola.pen.capital, 'PEN')}
        </span>
        <span>
          <strong className="text-foreground">Dólares:</strong> {cola.usd.cantidad} ·{' '}
          {dinero(cola.usd.capital, 'USD')}
        </span>
      </div>
    </article>
  )
}

function PorRepartir({ datos }: { datos: MetricasDistribucionLeads }): JSX.Element {
  const rangos = rangosPen(datos)
  const { por_repartir: porRepartir } = datos

  return (
    <section aria-labelledby="por-repartir-titulo" className="space-y-3">
      <div className="flex flex-wrap items-end justify-between gap-2">
        <div>
          <h4
            id="por-repartir-titulo"
            className="flex items-center gap-2 text-base font-extrabold text-primary"
          >
            <Inbox className="size-4 text-accent" aria-hidden /> Pendientes de asignar
          </h4>
          <p className="mt-0.5 text-xs text-muted-foreground">
            {porRepartir.total.carga_total} en total · {porRepartir.total.pen.cantidad} en soles ·{' '}
            {porRepartir.total.usd.cantidad} en dólares
          </p>
        </div>
        <Badge color={porRepartir.total.carga_total > 0 ? 'var(--warning)' : 'var(--accent)'} dot>
          {porRepartir.total.carga_total > 0 ? 'Asignar ahora' : 'Todo asignado'}
        </Badge>
      </div>

      {porRepartir.total.carga_total === 0 ? (
        <div className="rounded-lg border border-dashed border-border px-5 py-8 text-center">
          <Check className="mx-auto size-6 text-accent" aria-hidden />
          <p className="mt-2 text-sm font-semibold">No hay leads pendientes de asignar</p>
          <p className="mt-1 text-xs text-muted-foreground">
            Gerencia y supervisores no tienen pendientes.
          </p>
        </div>
      ) : (
        <div className="grid gap-3 xl:grid-cols-2">
          <ColaCard
            titulo="Pendientes de Gerencia"
            subtitulo="Leads sin responsable: los asigna Gerencia"
            cola={porRepartir.global}
            rangos={rangos}
          />
          {porRepartir.bandejas.map((bandeja) => (
            <ColaCard
              key={bandeja.supervisor_id}
              titulo={`Pendientes de ${bandeja.supervisor_nombre}`}
              subtitulo="En su bandeja, para asignar dentro de su equipo"
              cola={bandeja}
              rangos={rangos}
              inactiva={!bandeja.supervisor_activo}
            />
          ))}
        </div>
      )}
    </section>
  )
}

function AlertaCalidad({ datos }: { datos: MetricasDistribucionLeads }): JSX.Element | null {
  const sinMonto = datos.calidad.episodios_sin_monto_actuales + datos.calidad.episodios_sin_monto_cohorte
  const aproximados =
    datos.calidad.episodios_aproximados_actuales + datos.calidad.episodios_aproximados_cohorte
  if (sinMonto + aproximados === 0) return null

  return (
    <div
      className="flex items-start gap-3 rounded-lg border border-warning/35 bg-warning/5 px-4 py-3"
      role="status"
    >
      <AlertTriangle className="mt-0.5 size-4 shrink-0 text-warning" aria-hidden />
      <div>
        <p className="text-sm font-bold text-foreground">Aviso sobre los datos</p>
        <p className="mt-0.5 text-xs leading-relaxed text-muted-foreground">
          {sinMonto > 0 && <span>{sinMonto} {plural(sinMonto, 'registro no tiene', 'registros no tienen')} monto. </span>}
          {aproximados > 0 && (
            <span>{aproximados} {plural(aproximados, 'registro usa', 'registros usan')} fechas estimadas.</span>
          )}
        </p>
      </div>
    </div>
  )
}

// ── Pantalla ─────────────────────────────────────────────────────────────────

export function DistribucionLeadsGerencia({
  datos,
  cargando,
  error,
  modoDemo = false,
  mostrarOperacion = true,
  mostrarPeriodo = true,
  desde,
  hasta,
  onCambiarPeriodo,
  onReintentar,
  onEditarCapacidad,
}: DistribucionLeadsGerenciaProps): JSX.Element {
  const tituloId = useId()
  const fichas = useMemo(
    () => (datos ? datos.analistas.map(fichaAnalista) : []),
    [datos],
  )
  const equipos = useMemo(() => (datos ? equiposDistribucion(datos) : []), [datos])
  const [filtroEquipoId, setFiltroEquipoId] = useState<string | null>(null)

  useEffect(() => {
    if (filtroEquipoId != null && !equipos.some((equipo) => equipo.id === filtroEquipoId)) {
      setFiltroEquipoId(null)
    }
  }, [equipos, filtroEquipoId])

  const fichasFiltradas = useMemo(
    () => filtrarFichasPorEquipo(fichas, filtroEquipoId),
    [fichas, filtroEquipoId],
  )

  return (
    <Card className="overflow-hidden" aria-labelledby={tituloId}>
      <CardHeader className="gap-4 border-b border-border bg-muted/15 pb-4 lg:flex-row lg:items-end lg:justify-between">
        <div className="max-w-2xl">
          <p className="mb-1 text-[10px] font-extrabold uppercase tracking-[0.16em] text-accent">
            Gerencia comercial
          </p>
          <CardTitle id={tituloId} className="text-lg">
            {mostrarOperacion ? 'Distribución de leads' : 'Rendimiento y capacidad comercial'}
          </CardTitle>
          <CardDescription className="mt-1 max-w-xl leading-relaxed">
            {mostrarOperacion
              ? 'Quién tiene qué, quién tiene espacio y qué falta repartir. Soles y dólares siempre separados.'
              : 'Conversión, carga y capacidad por analista. Soles y dólares siempre separados.'}
          </CardDescription>
        </div>
        {mostrarPeriodo && <PeriodoControl
          desde={desde}
          hasta={hasta}
          cargando={cargando}
          onCambiarPeriodo={onCambiarPeriodo}
        />}
      </CardHeader>

      {error && (
        <div
          className="mx-5 mt-4 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-destructive/35 bg-destructive/5 px-4 py-3"
          role="alert"
        >
          <div className="flex min-w-0 items-start gap-2.5">
            <AlertTriangle className="mt-0.5 size-4 shrink-0 text-destructive" aria-hidden />
            <div>
              <p className="text-sm font-bold text-foreground">
                No se pudo actualizar la distribución
              </p>
              <p className="mt-0.5 text-xs text-muted-foreground">{error}</p>
            </div>
          </div>
          <Button type="button" variant="outline" size="sm" onClick={onReintentar}>
            <RefreshCw /> Reintentar
          </Button>
        </div>
      )}

      {cargando && !datos ? (
        <CargandoDistribucion />
      ) : !datos ? (
        <CardContent className="py-12 text-center">
          <Inbox className="mx-auto size-8 text-muted-foreground" aria-hidden />
          <p className="mt-3 text-sm font-semibold">
            {modoDemo ? 'No hay datos de demostración disponibles' : 'No hay datos para mostrar'}
          </p>
          <p className="mx-auto mt-1 max-w-md text-xs leading-relaxed text-muted-foreground">
            {modoDemo
              ? 'Vuelve a ingresar al modo demostración.'
              : 'Vuelve a cargar para consultar la distribución del período seleccionado.'}
          </p>
          {!error && !modoDemo && (
            <Button type="button" variant="outline" size="sm" className="mt-4" onClick={onReintentar}>
              <RefreshCw /> Cargar distribución
            </Button>
          )}
        </CardContent>
      ) : (
        <CardContent className="space-y-5 py-5">
          {modoDemo && (
            <div className="rounded-lg border border-accent/30 bg-accent/5 px-4 py-3" role="status">
              <p className="text-xs font-extrabold uppercase tracking-[0.12em] text-accent">
                Datos ficticios de demostración
              </p>
              <p className="mt-1 text-xs leading-relaxed text-muted-foreground">
                Sirven únicamente para conocer el tablero. No representan información real de la
                empresa.
              </p>
            </div>
          )}
          {cargando && (
            <p
              className="flex items-center gap-2 text-xs font-medium text-muted-foreground"
              role="status"
            >
              <RefreshCw className="size-3.5 animate-spin" aria-hidden /> Actualizando datos…
            </p>
          )}

          <ResumenDistribucion datos={datos} mostrarOperacion={mostrarOperacion} />
          <AtencionHoy datos={datos} mostrarOperacion={mostrarOperacion} />

          <EquipoPorPersona
            fichas={fichas}
            equipos={equipos}
            filtroEquipoId={filtroEquipoId}
            onFiltrarEquipo={setFiltroEquipoId}
            onEditarCapacidad={onEditarCapacidad}
          />

          {mostrarOperacion && <AsistenteReparto datos={datos} />}
          <TablaRangos datos={datos} fichas={fichasFiltradas} />
          {mostrarOperacion && <PorRepartir datos={datos} />}
          <AvisoSondas datos={datos} />
          <AlertaCalidad datos={datos} />

          <p className="text-[11px] leading-relaxed text-muted-foreground">
            Período: {datos.cohorte.desde_inclusivo} al {datos.cohorte.hasta_inclusivo}. «Recibió»
            cuenta cada vez que un lead entró a la cartera de una persona durante el período; la
            cartera actual es la foto de hoy. La puntería mide, de lo que cada quien terminó de
            trabajar (ventas + descartes), cuánto ganó; la «Conversión del mes» es la cifra única
            del núcleo — la misma de HOY, Metas, Conversiones y el Ranking — y todos estos
            porcentajes los calcula el servidor. Los tiempos de atención se consultan en las
            métricas SLA versionadas, fuera de este tablero de distribución.
          </p>
        </CardContent>
      )}
    </Card>
  )
}

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
  MetricasDistribucionLeads as MetricasDistribucionLeadsContrato,
  MetricaDistribucionAnalista,
  MetricasPorRepartir,
  RangoCapitalPen,
  RangoDistribucionAnalista,
} from '@/lib/metricas-distribucion'
import { cn } from '@/lib/utils'

// Alias públicos para que componente, API y tests compartan una sola verdad:
// el contrato Valibot que valida la fotografía completa de la RPC.
export type MetricasDistribucionLeads = MetricasDistribucionLeadsContrato
export type RangoCapitalDistribucion = RangoCapitalPen
export type RangoAnalistaDistribucion = RangoDistribucionAnalista
export type AnalistaDistribucionLeads = MetricaDistribucionAnalista
export type RangoColaDistribucion = MetricasPorRepartir['total']['pen']['rangos'][number]
export type BandejaDistribucion = MetricasPorRepartir['bandejas'][number]
type ColaDistribucion = MetricasPorRepartir['total']

export interface DistribucionLeadsGerenciaProps {
  datos?: MetricasDistribucionLeads | null | undefined
  cargando: boolean
  error: string | null
  modoDemo?: boolean | undefined
  desde: string
  hasta: string
  onCambiarPeriodo: (desde: string, hasta: string) => void
  onReintentar: () => void
  onEditarCapacidad: (analistaId: string, capacidad: number | null) => void | Promise<void>
}

const ENTERO = new Intl.NumberFormat('es-PE', { maximumFractionDigits: 0 })
const PORCENTAJE = new Intl.NumberFormat('es-PE', { maximumFractionDigits: 1 })
const DINERO: Record<'PEN' | 'USD', Intl.NumberFormat> = {
  PEN: new Intl.NumberFormat('es-PE', {
    style: 'currency',
    currency: 'PEN',
    maximumFractionDigits: 0,
  }),
  USD: new Intl.NumberFormat('es-PE', {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 0,
  }),
}

function dinero(valor: number, moneda: 'PEN' | 'USD'): string {
  return DINERO[moneda].format(valor)
}

function porcentaje(numerador: number, denominador: number): string | null {
  if (denominador <= 0) return null
  return `${PORCENTAJE.format((numerador / denominador) * 100)}%`
}

function rangoDeAnalista(
  analista: AnalistaDistribucionLeads,
  rangoId: RangoAnalistaDistribucion['rango_id'],
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
    }
  )
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

function medianaContacto(minutos: number | null): string | null {
  if (minutos == null) return null
  if (minutos < 60) return `${ENTERO.format(minutos)} min`
  const horas = minutos / 60
  if (horas < 24) return `${PORCENTAJE.format(horas)} h`
  return `${PORCENTAJE.format(horas / 24)} d`
}

function PeriodoControl({
  desde,
  hasta,
  cargando,
  onCambiarPeriodo,
}: Pick<
  DistribucionLeadsGerenciaProps,
  'desde' | 'hasta' | 'cargando' | 'onCambiarPeriodo'
>): JSX.Element {
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
    <form className="flex flex-wrap items-end gap-2" onSubmit={aplicar} noValidate>
      <label className="grid gap-1 text-[11px] font-bold text-muted-foreground">
        Desde
        <input
          type="date"
          value={desdeBorrador}
          onChange={(evento) => setDesdeBorrador(evento.target.value)}
          className="h-8 rounded-md border border-input bg-card px-2 text-xs font-medium text-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
          required
        />
      </label>
      <label className="grid gap-1 text-[11px] font-bold text-muted-foreground">
        Hasta
        <input
          type="date"
          value={hastaBorrador}
          onChange={(evento) => setHastaBorrador(evento.target.value)}
          className="h-8 rounded-md border border-input bg-card px-2 text-xs font-medium text-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
          required
        />
      </label>
      <Button type="submit" variant="outline" size="sm" disabled={cargando}>
        <CalendarDays /> Aplicar
      </Button>
      {errorPeriodo && (
        <p className="basis-full text-xs font-medium text-destructive" role="alert">
          {errorPeriodo}
        </p>
      )}
    </form>
  )
}

function CargandoDistribucion(): JSX.Element {
  return (
    <CardContent className="space-y-4 py-5" aria-busy="true" role="status">
      <span className="sr-only">Cargando distribución de leads</span>
      <div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-4">
        {Array.from({ length: 4 }, (_, indice) => (
          <Skeleton key={indice} className="h-16" />
        ))}
      </div>
      <Skeleton className="h-12 w-full" />
      {Array.from({ length: 3 }, (_, indice) => (
        <Skeleton key={indice} className="h-20 w-full" />
      ))}
    </CardContent>
  )
}

function ResumenDistribucion({ datos }: { datos: MetricasDistribucionLeads }): JSX.Element {
  const resueltos = datos.resumen.convertidos_pen + datos.resumen.descartados_pen
  const conversion = porcentaje(datos.resumen.convertidos_pen, resueltos)
  const sla = porcentaje(datos.resumen.sla_en_24h, datos.resumen.sla_evaluables)

  const items = [
    {
      etiqueta: 'Cartera total con analista',
      valor: ENTERO.format(datos.resumen.asignados_actuales),
      detalle: `${dinero(datos.resumen.capital_pen_asignado_actual, 'PEN')} · ${dinero(datos.resumen.capital_usd_asignado_actual, 'USD')}`,
    },
    {
      etiqueta: 'Por repartir',
      valor: ENTERO.format(datos.resumen.por_repartir_actuales),
      detalle: 'Global + bandejas de supervisión',
    },
    {
      etiqueta: 'Conversión PEN',
      valor: conversion ?? 'Sin muestra',
      detalle: `C ${datos.resumen.convertidos_pen} · D ${datos.resumen.descartados_pen}`,
    },
    {
      etiqueta: 'SLA total de contacto ≤ 24 h',
      valor: sla ?? 'Sin muestra',
      detalle: `${datos.resumen.sla_en_24h} de ${datos.resumen.sla_evaluables} evaluables`,
    },
  ]

  return (
    <dl className="grid overflow-hidden rounded-lg border border-border bg-muted/20 sm:grid-cols-2 xl:grid-cols-4">
      {items.map((item, indice) => (
        <div
          key={item.etiqueta}
          className={cn(
            'min-w-0 px-4 py-3',
            indice > 0 && 'border-t border-border sm:border-l',
            indice === 2 && 'sm:border-l-0 xl:border-l',
            indice > 1 && 'xl:border-t-0',
          )}
        >
          <dt className="text-[10px] font-bold uppercase tracking-wider text-muted-foreground">
            {item.etiqueta}
          </dt>
          <dd className="mt-0.5 text-xl font-extrabold tracking-tight tabular-nums text-primary">
            {item.valor}
          </dd>
          <dd className="mt-0.5 text-[11px] text-muted-foreground">{item.detalle}</dd>
        </div>
      ))}
    </dl>
  )
}

function CapacidadAnalista({
  analista,
  editando,
  valor,
  guardando,
  error,
  onEmpezar,
  onCambiar,
  onCancelar,
  onGuardar,
}: {
  analista: AnalistaDistribucionLeads
  editando: boolean
  valor: string
  guardando: boolean
  error: string | null
  onEmpezar: () => void
  onCambiar: (valor: string) => void
  onCancelar: () => void
  onGuardar: (evento: FormEvent<HTMLFormElement>) => void
}): JSX.Element {
  const objetivo = analista.capacidad.objetivo
  const carga = analista.capacidad.carga_activa
  const uso = objetivo && objetivo > 0 ? Math.round((carga / objetivo) * 100) : 0

  if (editando) {
    return (
      <form className="min-w-32 space-y-1.5" onSubmit={onGuardar} noValidate>
        <label className="sr-only" htmlFor={`capacidad-${analista.analista_id}`}>
          Capacidad objetivo para {analista.nombre}
        </label>
        <input
          id={`capacidad-${analista.analista_id}`}
          type="number"
          min={1}
          max={1000}
          step={1}
          value={valor}
          onChange={(evento) => onCambiar(evento.target.value)}
          placeholder="Sin objetivo"
          className="h-8 w-full rounded-md border border-input bg-card px-2 text-right text-xs tabular-nums focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
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
            onClick={onCancelar}
            disabled={guardando}
            aria-label={`Cancelar edición de capacidad de ${analista.nombre}`}
          >
            <X />
          </Button>
        </div>
        {error && (
          <p className="max-w-40 text-[10px] font-medium leading-tight text-destructive" role="alert">
            {error}
          </p>
        )}
      </form>
    )
  }

  return (
    <div className="min-w-28">
      <div className="flex items-center justify-between gap-1.5">
        <span className="font-extrabold tabular-nums text-foreground">
          {carga}
          <span className="font-medium text-muted-foreground">/{objetivo ?? '—'}</span>
        </span>
        {analista.disponible_para_recibir && (
          <Button
            type="button"
            variant="ghost"
            size="xs"
            className="size-7 px-0"
            onClick={onEmpezar}
            aria-label={`Editar capacidad de ${analista.nombre}`}
            title="Editar capacidad objetivo"
          >
            <Pencil />
          </Button>
        )}
      </div>
      {objetivo ? (
        <>
          <Progress
            value={uso}
            color={uso > 100 ? 'var(--destructive)' : uso >= 85 ? 'var(--warning)' : 'var(--accent)'}
            className="mt-1 h-1.5"
          />
          <p className="mt-1 text-[10px] tabular-nums text-muted-foreground">
            {uso}% de capacidad
          </p>
        </>
      ) : (
        <p className="mt-1 text-[10px] text-muted-foreground">Objetivo por definir</p>
      )}
    </div>
  )
}

function CeldaRango({
  analista,
  rango,
}: {
  analista: AnalistaDistribucionLeads
  rango: RangoCapitalDistribucion
}): JSX.Element {
  const dato = rangoDeAnalista(analista, rango.id)
  const { convertidos, descartados } = dato.cohorte
  const resueltos = convertidos + descartados
  const conversion = porcentaje(convertidos, resueltos)
  const recibidos = dato.cohorte.episodios_recibidos
  const leadsUnicos = dato.cohorte.leads_unicos_recibidos
  const etiqueta = `${analista.nombre}, ${rango.etiqueta}: ${recibidos} episodios recibidos, ${leadsUnicos} leads únicos; ${dato.cartera_actual.episodios} en cartera actual; ${convertidos} convertidos; ${descartados} descartados; conversión ${conversion ?? 'sin muestra'}`

  return (
    <div
      className={cn(
        'min-w-[104px] rounded-lg border px-2.5 py-2',
        recibidos > 0 || dato.cartera_actual.episodios > 0
          ? 'border-accent/30 bg-accent/5'
          : 'border-border/70 bg-muted/15',
      )}
      aria-label={etiqueta}
      title={`${dinero(dato.cartera_actual.capital, 'PEN')} en cartera actual · ${leadsUnicos} leads únicos recibidos`}
    >
      <p className="flex items-baseline gap-1 text-foreground">
        <span className="text-base font-extrabold tabular-nums">{recibidos}</span>
        <span className="text-[9px] font-bold uppercase tracking-wide text-muted-foreground">
          recibidos
        </span>
      </p>
      <p className="mt-0.5 whitespace-nowrap text-[9px] font-medium tabular-nums text-muted-foreground">
        {dato.cartera_actual.episodios} cartera hoy
        {leadsUnicos !== recibidos ? ` · ${leadsUnicos} leads` : ''}
      </p>
      <p className="mt-1 whitespace-nowrap text-[10px] font-semibold tabular-nums text-muted-foreground">
        <span className="text-primary">C {convertidos}</span>
        <span aria-hidden> · </span>
        <span>D {descartados}</span>
      </p>
      <p className="mt-0.5 text-[9px] font-bold tabular-nums text-muted-foreground">
        {conversion ?? 'Sin muestra'}
      </p>
    </div>
  )
}

function SeguimientoAnalista({ analista }: { analista: AnalistaDistribucionLeads }): JSX.Element {
  const { operacion } = analista
  const sla = porcentaje(operacion.sla_en_24h, operacion.sla_evaluables)
  const mediana = medianaContacto(operacion.primer_contacto_mediana_minutos)
  const salidasNoTerminales = operacion.transferidos + operacion.parqueados
  const tasaSalidas = porcentaje(salidasNoTerminales, operacion.cohorte_episodios)

  return (
    <div className="min-w-32 space-y-1.5">
      <div>
        <p className="font-extrabold tabular-nums text-foreground">{sla ?? 'Sin muestra'}</p>
        <p className="text-[10px] tabular-nums text-muted-foreground">
          SLA {operacion.sla_en_24h}/{operacion.sla_evaluables}
          {mediana ? ` · mediana ${mediana}` : ''}
        </p>
      </div>
      <div className="flex flex-wrap gap-1">
        <Badge
          color={operacion.sin_tocar_actual > 0 ? 'var(--warning)' : 'var(--muted-foreground)'}
          variant="outline"
          className="whitespace-nowrap"
        >
          {operacion.sin_tocar_actual} sin tocar
        </Badge>
        <Badge
          color={operacion.estancados_actual > 0 ? 'var(--destructive)' : 'var(--muted-foreground)'}
          variant="outline"
          className="whitespace-nowrap"
        >
          {operacion.estancados_actual} estancados
        </Badge>
      </div>
      <p className="text-[10px] tabular-nums text-muted-foreground">
        Salidas {tasaSalidas ?? '—'} · {salidasNoTerminales}/{operacion.cohorte_episodios}
      </p>
      <p className="text-[10px] tabular-nums text-muted-foreground">
        {operacion.transferidos} transferidos · {operacion.parqueados} parqueados ·{' '}
        {operacion.desactivados} desactivados
      </p>
    </div>
  )
}

function MatrizPen({
  datos,
  onEditarCapacidad,
}: {
  datos: MetricasDistribucionLeads
  onEditarCapacidad: DistribucionLeadsGerenciaProps['onEditarCapacidad']
}): JSX.Element {
  const [edicion, setEdicion] = useState<{ analistaId: string; valor: string } | null>(null)
  const [guardando, setGuardando] = useState(false)
  const [errorCapacidad, setErrorCapacidad] = useState<string | null>(null)
  const rangos = useMemo(
    () =>
      datos.rangos
        .filter((rango) => rango.id !== 'sin_monto')
        .sort((a, b) => a.orden - b.orden)
        .slice(0, 7),
    [datos.rangos],
  )

  const empezarEdicion = (analista: AnalistaDistribucionLeads) => {
    if (!analista.disponible_para_recibir) return
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
    const limpio = edicion.valor.trim()
    const capacidad = limpio === '' ? null : Number(limpio)
    if (capacidad !== null && (!Number.isInteger(capacidad) || capacidad < 1 || capacidad > 1000)) {
      setErrorCapacidad('Usa un entero entre 1 y 1000, o déjalo vacío.')
      return
    }
    setGuardando(true)
    setErrorCapacidad(null)
    try {
      await onEditarCapacidad(analista.analista_id, capacidad)
      setEdicion(null)
    } catch {
      setErrorCapacidad('No se pudo guardar la capacidad. Inténtalo otra vez.')
    } finally {
      setGuardando(false)
    }
  }

  if (datos.analistas.length === 0) {
    return (
      <div className="rounded-lg border border-dashed border-border px-5 py-10 text-center">
        <Users className="mx-auto size-7 text-muted-foreground" aria-hidden />
        <p className="mt-2 text-sm font-semibold">Aún no hay analistas para comparar</p>
        <p className="mt-1 text-xs text-muted-foreground">
          La matriz aparecerá cuando exista un vendedor activo o un episodio de asignación.
        </p>
      </div>
    )
  }

  return (
    <div
      className="overflow-x-auto rounded-lg border border-border"
      role="region"
      aria-label="Matriz PEN desplazable"
    >
      <table className="min-w-[1680px] border-separate border-spacing-0 text-xs">
        <caption className="sr-only">
          Distribución PEN por analista y rango de capital. Cada banda muestra episodios recibidos,
          cartera actual, convertidos y descartados de la cohorte.
        </caption>
        <thead>
          <tr className="bg-muted/55 text-left">
            <th
              scope="col"
              className="sticky left-0 z-20 w-52 border-b border-r border-border bg-muted px-4 py-3 text-[10px] font-bold uppercase tracking-wider text-muted-foreground"
            >
              Analista
            </th>
            <th
              scope="col"
              className="w-36 border-b border-r border-border px-3 py-3 text-[10px] font-bold uppercase tracking-wider text-muted-foreground"
            >
              <span className="block">Carga / capacidad</span>
              <span className="mt-0.5 block text-[9px] font-medium normal-case tracking-normal">
                Total PEN + USD
              </span>
            </th>
            {rangos.map((rango, indice) => (
              <th
                key={rango.id}
                scope="col"
                className="w-32 border-b border-r border-border/70 px-2 py-2.5 align-bottom last:border-r"
              >
                <span className="block text-[9px] font-extrabold tabular-nums text-accent">
                  BANDA {String(indice + 1).padStart(2, '0')}
                </span>
                <span className="mt-0.5 block text-[10px] font-bold leading-tight text-foreground">
                  {rango.etiqueta}
                </span>
              </th>
            ))}
            <th
              scope="col"
              className="w-32 border-b border-r border-border px-3 py-3 text-[10px] font-bold uppercase tracking-wider text-muted-foreground"
            >
              Conversión PEN
            </th>
            <th
              scope="col"
              className="w-44 border-b border-border px-3 py-3 text-[10px] font-bold uppercase tracking-wider text-muted-foreground"
            >
              <span className="block">SLA y seguimiento</span>
              <span className="mt-0.5 block text-[9px] font-medium normal-case tracking-normal">
                Total PEN + USD
              </span>
            </th>
          </tr>
        </thead>
        <tbody>
          {datos.analistas.map((analista) => {
            const resueltos = analista.pen.cohorte.convertidos + analista.pen.cohorte.descartados
            const conversion = porcentaje(analista.pen.cohorte.convertidos, resueltos)
            const editando = edicion?.analistaId === analista.analista_id

            return (
              <tr key={analista.analista_id} className="group hover:bg-muted/20">
                <th
                  scope="row"
                  className="sticky left-0 z-10 border-b border-r border-border bg-card px-4 py-3 text-left group-hover:bg-muted"
                >
                  <div className="flex min-w-0 items-center gap-2.5">
                    <Avatar nombre={analista.nombre} className="size-8" />
                    <div className="min-w-0">
                      <p className="truncate text-xs font-bold text-foreground">{analista.nombre}</p>
                      <p className="truncate text-[10px] font-medium text-muted-foreground">
                        {analista.rol === 'supervisor' ? 'Supervisor' : analista.supervisor_nombre || 'Sin supervisor'}
                      </p>
                    </div>
                  </div>
                  {!analista.activo && (
                    <Badge color="var(--muted-foreground)" variant="outline" className="mt-1.5">
                      Inactivo · histórico
                    </Badge>
                  )}
                </th>
                <td className="border-b border-r border-border px-3 py-3 align-top">
                  <CapacidadAnalista
                    analista={analista}
                    editando={editando}
                    valor={editando ? edicion.valor : ''}
                    guardando={guardando && editando}
                    error={editando ? errorCapacidad : null}
                    onEmpezar={() => empezarEdicion(analista)}
                    onCambiar={(valor) =>
                      setEdicion((actual) =>
                        actual?.analistaId === analista.analista_id ? { ...actual, valor } : actual,
                      )
                    }
                    onCancelar={() => {
                      setEdicion(null)
                      setErrorCapacidad(null)
                    }}
                    onGuardar={(evento) => void guardarCapacidad(evento, analista)}
                  />
                </td>
                {rangos.map((rango) => (
                  <td key={rango.id} className="border-b border-r border-border/70 px-2 py-2 align-top">
                    <CeldaRango analista={analista} rango={rango} />
                  </td>
                ))}
                <td className="border-b border-r border-border px-3 py-3 align-top">
                  <p className="text-base font-extrabold tabular-nums text-primary">
                    {conversion ?? 'Sin muestra'}
                  </p>
                  <p className="mt-1 whitespace-nowrap text-[10px] tabular-nums text-muted-foreground">
                    C {analista.pen.cohorte.convertidos} · D {analista.pen.cohorte.descartados}
                  </p>
                  <p className="mt-1 text-[10px] text-muted-foreground">
                    {analista.pen.cohorte.episodios_recibidos} episodios ·{' '}
                    {analista.pen.cohorte.leads_unicos_recibidos} leads recibidos
                  </p>
                  <p className="mt-1 text-[10px] text-muted-foreground">
                    {analista.pen.cohorte.ciclos_resueltos} ciclos ·{' '}
                    {analista.pen.cohorte.leads_unicos_resueltos} leads resueltos
                  </p>
                </td>
                <td className="border-b border-border px-3 py-3 align-top">
                  <SeguimientoAnalista analista={analista} />
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}

function LecturaUsd({ datos }: { datos: MetricasDistribucionLeads }): JSX.Element {
  const analistasConUsd = datos.analistas.filter((analista) => {
    const usd = analista.usd_no_segmentado
    return usd.cartera_actual_episodios > 0 || usd.cohorte_episodios_recibidos > 0
  })

  return (
    <section aria-labelledby="distribucion-usd-titulo" className="rounded-lg border border-border bg-muted/15">
      <div className="flex flex-wrap items-start justify-between gap-2 border-b border-border px-4 py-3">
        <div>
          <h4 id="distribucion-usd-titulo" className="text-xs font-bold text-foreground">
            USD · lectura separada
          </h4>
          <p className="mt-0.5 text-[11px] text-muted-foreground">
            Se muestra sin bandas de capital y nunca se suma con PEN.
          </p>
        </div>
        <Badge color="var(--accent)" variant="outline">
          {dinero(datos.resumen.capital_usd_asignado_actual, 'USD')} en cartera
        </Badge>
      </div>
      {analistasConUsd.length === 0 ? (
        <p className="px-4 py-5 text-center text-xs text-muted-foreground">
          Sin cartera ni episodios USD en el período.
        </p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[620px] text-xs">
            <caption className="sr-only">Cartera y resultados USD por analista, sin segmentación.</caption>
            <thead>
              <tr className="border-b border-border text-left text-[10px] font-bold uppercase tracking-wider text-muted-foreground">
                <th scope="col" className="px-4 py-2">Analista</th>
                <th scope="col" className="px-3 py-2 text-right">Cartera</th>
                <th scope="col" className="px-3 py-2 text-right">Capital</th>
                <th scope="col" className="px-3 py-2 text-right">Recibidos</th>
                <th scope="col" className="px-4 py-2 text-right">Conversión</th>
              </tr>
            </thead>
            <tbody>
              {analistasConUsd.map((analista) => {
                const usd = analista.usd_no_segmentado
                const resueltos = usd.convertidos + usd.descartados
                return (
                  <tr key={analista.analista_id} className="border-b border-border/60 last:border-0">
                    <th scope="row" className="px-4 py-2.5 text-left font-semibold">{analista.nombre}</th>
                    <td className="px-3 py-2.5 text-right tabular-nums">{usd.cartera_actual_episodios}</td>
                    <td className="px-3 py-2.5 text-right font-semibold tabular-nums">
                      {dinero(usd.cartera_actual_capital, 'USD')}
                    </td>
                    <td className="px-3 py-2.5 text-right tabular-nums">{usd.cohorte_episodios_recibidos}</td>
                    <td className="px-4 py-2.5 text-right">
                      <span className="font-bold tabular-nums text-primary">
                        {porcentaje(usd.convertidos, resueltos) ?? 'Sin muestra'}
                      </span>
                      <span className="ml-2 text-[10px] tabular-nums text-muted-foreground">
                        C {usd.convertidos} · D {usd.descartados}
                      </span>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </section>
  )
}

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
  return (
    <article className="overflow-hidden rounded-lg border border-border bg-card" aria-label={titulo}>
      <div className="flex flex-wrap items-start justify-between gap-2 border-b border-border px-4 py-3">
        <div>
          <div className="flex items-center gap-2">
            <h5 className="text-xs font-bold text-foreground">{titulo}</h5>
            {inactiva && (
              <Badge color="var(--warning)" variant="outline">Supervisor inactivo</Badge>
            )}
          </div>
          <p className="mt-0.5 text-[10px] text-muted-foreground">{subtitulo}</p>
        </div>
        <div className="text-right">
          <p className="text-lg font-extrabold tabular-nums text-primary">{cola.carga_total}</p>
          <p className="text-[9px] font-bold uppercase tracking-wide text-muted-foreground">leads</p>
        </div>
      </div>
      <div className="overflow-x-auto p-3">
        <div className="grid min-w-[760px] grid-cols-7 gap-2">
          {rangos.map((rango) => {
            const dato = rangoDeCola(cola, rango.id)
            return (
              <div key={rango.id} className="rounded-md border border-border/70 bg-muted/20 px-2.5 py-2">
                <p className="min-h-7 text-[9px] font-bold leading-tight text-muted-foreground">
                  {rango.etiqueta}
                </p>
                <p className="mt-1 text-base font-extrabold tabular-nums text-foreground">{dato.cantidad}</p>
                <p className="truncate text-[9px] tabular-nums text-muted-foreground" title={dinero(dato.capital, 'PEN')}>
                  {dinero(dato.capital, 'PEN')}
                </p>
              </div>
            )
          })}
        </div>
      </div>
      <div className="flex flex-wrap gap-x-5 gap-y-1 border-t border-border bg-muted/15 px-4 py-2 text-[10px] text-muted-foreground">
        <span><strong className="text-foreground">PEN:</strong> {cola.pen.cantidad} · {dinero(cola.pen.capital, 'PEN')}</span>
        <span><strong className="text-foreground">USD:</strong> {cola.usd.cantidad} · {dinero(cola.usd.capital, 'USD')}</span>
      </div>
    </article>
  )
}

function PorRepartir({ datos }: { datos: MetricasDistribucionLeads }): JSX.Element {
  const rangos = datos.rangos
    .filter((rango) => rango.id !== 'sin_monto')
    .sort((a, b) => a.orden - b.orden)
    .slice(0, 7)
  const { por_repartir: porRepartir } = datos

  return (
    <section aria-labelledby="por-repartir-titulo" className="space-y-3">
      <div className="flex flex-wrap items-end justify-between gap-2">
        <div>
          <h4 id="por-repartir-titulo" className="flex items-center gap-2 text-sm font-bold text-foreground">
            <Inbox className="size-4 text-accent" aria-hidden /> Leads por repartir
          </h4>
          <p className="mt-0.5 text-[11px] text-muted-foreground">
            {porRepartir.total.carga_total} en total · {porRepartir.total.pen.cantidad} PEN · {porRepartir.total.usd.cantidad} USD
          </p>
        </div>
        <Badge color={porRepartir.total.carga_total > 0 ? 'var(--warning)' : 'var(--accent)'} dot>
          {porRepartir.total.carga_total > 0 ? 'Requieren asignación' : 'Colas al día'}
        </Badge>
      </div>

      {porRepartir.total.carga_total === 0 ? (
        <div className="rounded-lg border border-dashed border-border px-5 py-8 text-center">
          <Check className="mx-auto size-6 text-accent" aria-hidden />
          <p className="mt-2 text-sm font-semibold">No hay leads pendientes de reparto</p>
          <p className="mt-1 text-xs text-muted-foreground">
            La cola global y las bandejas de supervisión están vacías.
          </p>
        </div>
      ) : (
        <div className="grid gap-3 xl:grid-cols-2">
          <ColaCard
            titulo="Cola global"
            subtitulo="Responsabilidad de Gerencia"
            cola={porRepartir.global}
            rangos={rangos}
          />
          {porRepartir.bandejas.map((bandeja) => (
            <ColaCard
              key={bandeja.supervisor_id}
              titulo={`Bandeja de ${bandeja.supervisor_nombre}`}
              subtitulo="Pendientes de asignar dentro del equipo"
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
  const sinMontoActual = datos.calidad.episodios_sin_monto_actuales
  const sinMontoCohorte = datos.calidad.episodios_sin_monto_cohorte
  const aproximadosActual = datos.calidad.episodios_aproximados_actuales
  const aproximadosCohorte = datos.calidad.episodios_aproximados_cohorte
  if (sinMontoActual + sinMontoCohorte + aproximadosActual + aproximadosCohorte === 0) return null

  return (
    <div className="flex items-start gap-3 rounded-lg border border-warning/35 bg-warning/5 px-4 py-3" role="status">
      <AlertTriangle className="mt-0.5 size-4 shrink-0 text-warning" aria-hidden />
      <div>
        <p className="text-xs font-bold text-foreground">Calidad del historial</p>
        <p className="mt-0.5 text-[11px] leading-relaxed text-muted-foreground">
          {sinMontoActual + sinMontoCohorte > 0 && (
            <span>{sinMontoActual} episodios actuales y {sinMontoCohorte} de la cohorte están sin monto válido. </span>
          )}
          {aproximadosActual + aproximadosCohorte > 0 && (
            <span>{aproximadosActual} actuales y {aproximadosCohorte} de la cohorte son reconstruidos o aproximados.</span>
          )}
        </p>
      </div>
    </div>
  )
}

export function DistribucionLeadsGerencia({
  datos,
  cargando,
  error,
  modoDemo = false,
  desde,
  hasta,
  onCambiarPeriodo,
  onReintentar,
  onEditarCapacidad,
}: DistribucionLeadsGerenciaProps): JSX.Element {
  const tituloId = useId()

  return (
    <Card className="overflow-hidden" aria-labelledby={tituloId}>
      <CardHeader className="gap-4 border-b border-border bg-muted/15 pb-4 lg:flex-row lg:items-end lg:justify-between">
        <div className="max-w-2xl">
          <p className="mb-1 text-[10px] font-extrabold uppercase tracking-[0.16em] text-accent">
            Asignación comercial
          </p>
          <CardTitle id={tituloId} className="text-lg">Distribución de leads por capital</CardTitle>
          <CardDescription className="mt-1 max-w-xl leading-relaxed">
            Compara la cartera actual de cada analista con su capacidad. Los resultados C/D y la velocidad de contacto pertenecen a episodios asignados dentro del período.
          </CardDescription>
        </div>
        <PeriodoControl
          desde={desde}
          hasta={hasta}
          cargando={cargando}
          onCambiarPeriodo={onCambiarPeriodo}
        />
      </CardHeader>

      {error && (
        <div
          className="mx-5 mt-4 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-destructive/35 bg-destructive/5 px-4 py-3"
          role="alert"
        >
          <div className="flex min-w-0 items-start gap-2.5">
            <AlertTriangle className="mt-0.5 size-4 shrink-0 text-destructive" aria-hidden />
            <div>
              <p className="text-xs font-bold text-foreground">No se pudo actualizar la distribución</p>
              <p className="mt-0.5 text-[11px] text-muted-foreground">{error}</p>
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
            {modoDemo ? 'La demostración no inventa historial de asignaciones' : 'Aún no hay una fotografía de distribución'}
          </p>
          <p className="mx-auto mt-1 max-w-md text-xs leading-relaxed text-muted-foreground">
            {modoDemo
              ? 'Esta matriz se habilita con los episodios reales del CRM para no mostrar conversiones ni SLA ficticios.'
              : 'Vuelve a cargar para consultar la cartera, la cohorte y las colas de asignación del período seleccionado.'}
          </p>
          {!error && !modoDemo && (
            <Button type="button" variant="outline" size="sm" className="mt-4" onClick={onReintentar}>
              <RefreshCw /> Cargar distribución
            </Button>
          )}
        </CardContent>
      ) : (
        <CardContent className="space-y-5 py-5">
          {cargando && (
            <p className="flex items-center gap-2 text-[11px] font-medium text-muted-foreground" role="status">
              <RefreshCw className="size-3.5 animate-spin" aria-hidden /> Actualizando datos…
            </p>
          )}
          <ResumenDistribucion datos={datos} />

          <div className="space-y-2">
            <div className="flex flex-wrap items-end justify-between gap-2">
              <div>
                <h4 className="text-sm font-bold text-foreground">Matriz PEN por analista</h4>
                <p className="mt-0.5 text-[11px] text-muted-foreground">
                  Número grande = episodios recibidos en el período · debajo = cartera actual. C = convertido · D = descartado · conversión = C/(C+D).
                </p>
              </div>
              <Badge color="var(--accent)" variant="outline">7 bandas comerciales</Badge>
            </div>
            <MatrizPen datos={datos} onEditarCapacidad={onEditarCapacidad} />
          </div>

          <LecturaUsd datos={datos} />
          <PorRepartir datos={datos} />
          <AlertaCalidad datos={datos} />

          <p className="text-[10px] leading-relaxed text-muted-foreground">
            Período {datos.cohorte.desde_inclusivo} a {datos.cohorte.hasta_inclusivo}, zona horaria {datos.cohorte.zona_horaria}. En conversión, “Sin muestra” significa C+D=0; en SLA, que aún no hay episodios evaluables. Ninguno equivale a 0%.
          </p>
        </CardContent>
      )}
    </Card>
  )
}

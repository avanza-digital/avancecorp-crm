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

interface EquipoSupervisado {
  id: string
  nombre: string
  activo: boolean
  analistas: AnalistaDistribucionLeads[]
  pendientes: number
  cargaActiva: number
  limiteDefinido: number
  cuposLibres: number
  conLimite: number
  slaEn24h: number
  slaEvaluables: number
  sinAtender: number
  sinAvance: number
  capitalPen: number
  capitalUsd: number
  convertidosPen: number
  descartadosPen: number
}

function equiposSupervisados(datos: MetricasDistribucionLeads): EquipoSupervisado[] {
  const equipos = new Map<string, EquipoSupervisado>()
  const bandejas = new Map(
    datos.por_repartir.bandejas.map((bandeja) => [bandeja.supervisor_id, bandeja]),
  )

  const obtener = (analista: AnalistaDistribucionLeads): EquipoSupervisado => {
    const id = analista.supervisor_id
      ?? (analista.rol === 'supervisor' ? analista.analista_id : 'sin-supervisor')
    const nombre = analista.supervisor_nombre
      ?? (analista.rol === 'supervisor' ? analista.nombre : 'Sin supervisor')
    const existente = equipos.get(id)
    if (existente) return existente
    const bandeja = bandejas.get(id)
    const creado: EquipoSupervisado = {
      id,
      nombre,
      activo: bandeja?.supervisor_activo ?? true,
      analistas: [],
      pendientes: bandeja?.carga_total ?? 0,
      cargaActiva: 0,
      limiteDefinido: 0,
      cuposLibres: 0,
      conLimite: 0,
      slaEn24h: 0,
      slaEvaluables: 0,
      sinAtender: 0,
      sinAvance: 0,
      capitalPen: 0,
      capitalUsd: 0,
      convertidosPen: 0,
      descartadosPen: 0,
    }
    equipos.set(id, creado)
    return creado
  }

  for (const analista of datos.analistas) {
    const equipo = obtener(analista)
    equipo.analistas.push(analista)
    equipo.cargaActiva += analista.capacidad.carga_activa
    if (analista.capacidad.objetivo != null) {
      equipo.conLimite += 1
      equipo.limiteDefinido += analista.capacidad.objetivo
      equipo.cuposLibres += Math.max(
        0,
        analista.capacidad.objetivo - analista.capacidad.carga_activa,
      )
    }
    equipo.slaEn24h += analista.operacion.sla_asignacion_en_24h
    equipo.slaEvaluables += analista.operacion.sla_asignacion_evaluables
    equipo.sinAtender += analista.operacion.sin_tocar_actual
    equipo.sinAvance += analista.operacion.estancados_actual
    equipo.capitalPen += analista.pen.cartera_actual.capital
    equipo.capitalUsd += analista.usd_no_segmentado.cartera_actual_capital
    equipo.convertidosPen += analista.pen.cohorte.convertidos
    equipo.descartadosPen += analista.pen.cohorte.descartados
  }

  for (const bandeja of datos.por_repartir.bandejas) {
    if (equipos.has(bandeja.supervisor_id)) continue
    equipos.set(bandeja.supervisor_id, {
      id: bandeja.supervisor_id,
      nombre: bandeja.supervisor_nombre,
      activo: bandeja.supervisor_activo,
      analistas: [],
      pendientes: bandeja.carga_total,
      cargaActiva: 0,
      limiteDefinido: 0,
      cuposLibres: 0,
      conLimite: 0,
      slaEn24h: 0,
      slaEvaluables: 0,
      sinAtender: 0,
      sinAvance: 0,
      capitalPen: 0,
      capitalUsd: 0,
      convertidosPen: 0,
      descartadosPen: 0,
    })
  }

  return [...equipos.values()].sort((a, b) => a.nombre.localeCompare(b.nombre, 'es'))
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
  const sla = porcentaje(
    datos.resumen.sla_global_en_24h,
    datos.resumen.sla_global_evaluables,
  )
  const medianaGlobal = medianaContacto(datos.resumen.primer_contacto_global_mediana_minutos)

  const items = [
    {
      etiqueta: 'Leads con analista',
      valor: ENTERO.format(datos.resumen.asignados_actuales),
      detalle: `${dinero(datos.resumen.capital_pen_asignado_actual, 'PEN')} · ${dinero(datos.resumen.capital_usd_asignado_actual, 'USD')}`,
    },
    {
      etiqueta: 'Pendientes de asignar',
      valor: ENTERO.format(datos.resumen.por_repartir_actuales),
      detalle: 'Gerencia y supervisores',
    },
    {
      etiqueta: 'Leads ganados en soles',
      valor: conversion ?? 'Aún sin resultados',
      detalle: `${datos.resumen.convertidos_pen} ganados · ${datos.resumen.descartados_pen} descartados`,
    },
    {
      etiqueta: 'Leads atendidos en 24 horas',
      valor: sla ?? 'Aún sin datos',
      detalle: `${datos.resumen.sla_global_en_24h} de ${datos.resumen.sla_global_evaluables} leads${medianaGlobal ? ` · tiempo habitual ${medianaGlobal}` : ''} · ${datos.resumen.sla_global_sin_contacto_vencidos_actuales} llevan más de 24 h sin atención`,
    },
  ]

  return (
    <dl className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
      {items.map((item) => (
        <div
          key={item.etiqueta}
          className="min-w-0 rounded-xl border border-border/80 bg-card px-4 py-4 shadow-[0_10px_24px_-24px_rgba(15,31,61,0.8)]"
        >
          <dt className="text-[11px] font-bold uppercase tracking-[0.08em] text-muted-foreground">
            {item.etiqueta}
          </dt>
          <dd className="mt-1.5 text-2xl font-extrabold tracking-tight tabular-nums text-primary">
            {item.valor}
          </dd>
          <dd className="mt-1 text-xs leading-relaxed text-muted-foreground">{item.detalle}</dd>
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
          Límite de cartera para {analista.nombre}
        </label>
        <input
          id={`capacidad-${analista.analista_id}`}
          type="number"
          min={1}
          max={1000}
          step={1}
          value={valor}
          onChange={(evento) => onCambiar(evento.target.value)}
          placeholder="Sin límite"
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
            aria-label={`Cancelar edición del límite de cartera de ${analista.nombre}`}
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
          <span className="font-medium text-muted-foreground"> de {objetivo ?? '—'}</span>
        </span>
        {analista.disponible_para_recibir && (
          <Button
            type="button"
            variant="ghost"
            size="xs"
            className="size-7 px-0"
            onClick={onEmpezar}
            aria-label={`Editar límite de cartera de ${analista.nombre}`}
            title="Editar límite de cartera"
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
            {uso}% del límite · {Math.max(0, objetivo - carga)} cupos libres
          </p>
        </>
      ) : (
        <p className="mt-1 text-[10px] text-muted-foreground">Límite por definir</p>
      )}
    </div>
  )
}

function EquiposBajoSupervision({
  equipos,
  seleccionadoId,
  onSeleccionar,
}: {
  equipos: EquipoSupervisado[]
  seleccionadoId: string | null
  onSeleccionar: (equipoId: string) => void
}): JSX.Element | null {
  if (equipos.length === 0) return null

  return (
    <section aria-labelledby="equipos-supervisados" className="space-y-3">
      <div>
        <h4 id="equipos-supervisados" className="text-base font-extrabold text-primary">
          Equipos bajo supervisión
        </h4>
        <p className="mt-1 text-xs leading-relaxed text-muted-foreground">
          Gerencia observa primero al supervisor responsable. El detalle por analista se abre solo cuando hace falta.
        </p>
      </div>
      <div className="grid gap-3 xl:grid-cols-2">
        {equipos.map((equipo) => {
          const sla = porcentaje(equipo.slaEn24h, equipo.slaEvaluables)
          const resueltos = equipo.convertidosPen + equipo.descartadosPen
          const conversion = porcentaje(equipo.convertidosPen, resueltos)
          const seleccionado = equipo.id === seleccionadoId

          return (
            <article
              key={equipo.id}
              className={cn(
                'rounded-2xl border bg-card p-4 shadow-[0_14px_30px_-28px_rgba(15,31,61,0.85)] transition-colors',
                seleccionado ? 'border-accent ring-2 ring-accent/15' : 'border-border/80',
              )}
            >
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="flex min-w-0 items-center gap-3">
                  <Avatar nombre={equipo.nombre} className="size-10" />
                  <div className="min-w-0">
                    <h5 className="truncate text-sm font-extrabold text-foreground">{equipo.nombre}</h5>
                    <p className="text-xs text-muted-foreground">
                      Supervisor · {equipo.analistas.length} analistas
                    </p>
                  </div>
                </div>
                <Badge
                  color={equipo.sinAtender > 0 || equipo.sinAvance > 0 ? 'var(--warning)' : 'var(--accent)'}
                  variant="outline"
                  dot
                >
                  {!equipo.activo
                    ? 'Supervisor inactivo'
                    : equipo.sinAtender > 0 || equipo.sinAvance > 0
                      ? 'Con pendientes'
                      : 'Sin alertas operativas'}
                </Badge>
              </div>

              <dl className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
                <div className="rounded-xl bg-muted/45 p-3">
                  <dt className="text-[9px] font-bold uppercase tracking-wide text-muted-foreground">Leads activos</dt>
                  <dd className="mt-1 text-xl font-extrabold tabular-nums text-primary">{equipo.cargaActiva}</dd>
                  <p className="text-[9px] text-muted-foreground">
                    {equipo.conLimite > 0
                      ? `${equipo.cuposLibres} cupos libres · ${equipo.conLimite}/${equipo.analistas.length} con límite`
                      : 'Límites por definir'}
                  </p>
                </div>
                <div className="rounded-xl bg-muted/45 p-3">
                  <dt className="text-[9px] font-bold uppercase tracking-wide text-muted-foreground">Por asignar</dt>
                  <dd className="mt-1 text-xl font-extrabold tabular-nums text-primary">{equipo.pendientes}</dd>
                  <p className="text-[9px] text-muted-foreground">Bandeja del supervisor</p>
                </div>
                <div className="rounded-xl bg-muted/45 p-3">
                  <dt className="text-[9px] font-bold uppercase tracking-wide text-muted-foreground">Atención en 24 h</dt>
                  <dd className="mt-1 text-xl font-extrabold tabular-nums text-primary">{sla ?? '—'}</dd>
                  <p className="text-[9px] tabular-nums text-muted-foreground">{equipo.slaEn24h} de {equipo.slaEvaluables}</p>
                </div>
                <div className="rounded-xl bg-muted/45 p-3">
                  <dt className="text-[9px] font-bold uppercase tracking-wide text-muted-foreground">Conversión PEN</dt>
                  <dd className="mt-1 text-xl font-extrabold tabular-nums text-primary">{conversion ?? '—'}</dd>
                  <p className="text-[9px] tabular-nums text-muted-foreground">{equipo.convertidosPen} de {resueltos} cierres</p>
                </div>
              </dl>

              <div className="mt-3 flex flex-wrap items-center justify-between gap-3 border-t border-border/70 pt-3">
                <div className="flex flex-wrap gap-2 text-[10px] text-muted-foreground">
                  <span><strong className="text-foreground">{equipo.sinAtender}</strong> sin atender</span>
                  <span><strong className="text-foreground">{equipo.sinAvance}</strong> sin avance</span>
                  <span><strong className="text-foreground">{dinero(equipo.capitalPen, 'PEN')}</strong> activos</span>
                  <span><strong className="text-foreground">{dinero(equipo.capitalUsd, 'USD')}</strong> aparte</span>
                </div>
                <Button type="button" size="sm" variant={seleccionado ? 'default' : 'outline'} onClick={() => onSeleccionar(equipo.id)}>
                  Ver analistas
                </Button>
              </div>
            </article>
          )
        })}
      </div>
    </section>
  )
}

function MatrizPen({
  datos,
  analistas,
  onEditarCapacidad,
}: {
  datos: MetricasDistribucionLeads
  analistas: AnalistaDistribucionLeads[]
  onEditarCapacidad: DistribucionLeadsGerenciaProps['onEditarCapacidad']
}): JSX.Element {
  const [modo, setModo] = useState<'carga' | 'conversion'>('carga')
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
      setErrorCapacidad('No se pudo guardar el límite de cartera. Inténtalo otra vez.')
    } finally {
      setGuardando(false)
    }
  }

  if (analistas.length === 0) {
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
    <section className="overflow-hidden rounded-xl border border-border bg-card">
      <div className="flex flex-wrap items-start justify-between gap-3 border-b border-border bg-muted/20 px-4 py-3">
        <div>
          <h5 className="text-sm font-extrabold text-primary">Analistas por rango de monto</h5>
          <p className="mt-1 max-w-2xl text-[11px] leading-relaxed text-muted-foreground">
            {modo === 'carga'
              ? 'Carga actual muestra cuántos leads activos tiene cada persona. El límite de cartera lo configura Gerencia; no mide desempeño.'
              : 'Conversión histórica: ganados ÷ (ganados + descartados). Los leads todavía activos no entran en el porcentaje.'}
          </p>
        </div>
        <div className="flex rounded-lg bg-muted p-1" role="group" aria-label="Lectura de la matriz">
          <Button type="button" size="sm" variant={modo === 'carga' ? 'default' : 'ghost'} onClick={() => setModo('carga')}>
            Carga actual
          </Button>
          <Button type="button" size="sm" variant={modo === 'conversion' ? 'default' : 'ghost'} onClick={() => setModo('conversion')}>
            Conversión por monto
          </Button>
        </div>
      </div>

      <div className="ac-scroll max-h-[520px] overflow-auto" role="region" aria-label="Analistas por rango de monto en soles">
        <table className="min-w-[1180px] border-separate border-spacing-0 text-xs">
          <caption className="sr-only">
            {modo === 'carga'
              ? 'Carga actual por analista y rango de monto en soles.'
              : 'Conversión por analista y rango de monto en soles.'}
          </caption>
          <thead>
            <tr className="bg-muted/55 text-left">
              <th scope="col" className="sticky left-0 z-20 w-48 border-b border-r border-border bg-muted px-4 py-3 text-[10px] font-bold uppercase tracking-wider text-muted-foreground">Analista</th>
              {rangos.map((rango) => (
                <th key={rango.id} scope="col" className="w-24 border-b border-r border-border/70 px-2 py-2.5 text-center align-bottom">
                  <span className="block text-[9px] font-bold leading-tight text-foreground">{rango.etiqueta}</span>
                  <span className="mt-1 block text-[8px] font-medium text-muted-foreground">
                    {modo === 'carga' ? 'activos' : 'ganados / cerrados'}
                  </span>
                </th>
              ))}
              {modo === 'carga' ? (
                <>
                  <th scope="col" className="w-20 border-b border-r border-border px-2 py-3 text-center text-[9px] font-bold uppercase text-muted-foreground">Total activos</th>
                  <th scope="col" className="w-36 border-b border-r border-border px-3 py-3 text-[9px] font-bold uppercase text-muted-foreground">Carga / límite</th>
                  <th scope="col" className="w-28 border-b border-border px-3 py-3 text-[9px] font-bold uppercase text-muted-foreground">Atención</th>
                </>
              ) : (
                <>
                  <th scope="col" className="w-24 border-b border-r border-border px-2 py-3 text-center text-[9px] font-bold uppercase text-muted-foreground">Conversión total</th>
                  <th scope="col" className="w-20 border-b border-r border-border px-2 py-3 text-center text-[9px] font-bold uppercase text-muted-foreground">Casos cerrados</th>
                  <th scope="col" className="w-24 border-b border-border px-2 py-3 text-center text-[9px] font-bold uppercase text-muted-foreground">Recibidos PEN</th>
                </>
              )}
            </tr>
          </thead>
          <tbody>
            {analistas.map((analista) => {
              const resueltos = analista.pen.cohorte.convertidos + analista.pen.cohorte.descartados
              const conversionTotal = porcentaje(analista.pen.cohorte.convertidos, resueltos)
              const sla = porcentaje(
                analista.operacion.sla_asignacion_en_24h,
                analista.operacion.sla_asignacion_evaluables,
              )
              const editando = edicion?.analistaId === analista.analista_id

              return (
                <tr key={analista.analista_id} className="group hover:bg-muted/20">
                  <th scope="row" className="sticky left-0 z-10 border-b border-r border-border bg-card px-4 py-3 text-left group-hover:bg-muted">
                    <div className="flex min-w-0 items-center gap-2.5">
                      <Avatar nombre={analista.nombre} className="size-8" />
                      <div className="min-w-0">
                        <p className="truncate text-xs font-bold text-foreground">{analista.nombre}</p>
                        <p className="truncate text-[9px] font-medium text-muted-foreground">
                          {analista.disponible_para_recibir ? 'Disponible para recibir' : 'Recepción pausada'}
                        </p>
                      </div>
                    </div>
                  </th>
                  {rangos.map((rango) => {
                    const dato = rangoDeAnalista(analista, rango.id)
                    const cerrados = dato.cohorte.convertidos + dato.cohorte.descartados
                    const conversionRango = porcentaje(dato.cohorte.convertidos, cerrados)
                    const carga = dato.cartera_actual.episodios
                    return (
                      <td key={rango.id} className="border-b border-r border-border/70 px-2 py-2 text-center">
                        {modo === 'carga' ? (
                          <div
                            className={cn(
                              'mx-auto grid size-9 place-items-center rounded-lg border text-sm font-extrabold tabular-nums',
                              carga === 0 && 'border-border/60 bg-muted/20 text-muted-foreground',
                              carga === 1 && 'border-accent/25 bg-accent/10 text-primary',
                              carga >= 2 && carga < 4 && 'border-accent/40 bg-accent/20 text-primary',
                              carga >= 4 && 'border-primary bg-primary text-primary-foreground',
                            )}
                            title={`${dato.cartera_actual.episodios} leads activos · ${dinero(dato.cartera_actual.capital, 'PEN')}`}
                          >
                            {carga}
                          </div>
                        ) : (
                          <div className={cn('mx-auto min-w-16 rounded-lg px-1.5 py-1.5 tabular-nums', cerrados === 0 ? 'bg-muted/25 text-muted-foreground' : 'bg-accent/10 text-primary')}>
                            <p className="text-xs font-extrabold">{conversionRango ?? '—'}</p>
                            <p className="mt-0.5 text-[8px] font-medium text-muted-foreground">
                              {cerrados > 0 ? `${dato.cohorte.convertidos} de ${cerrados}` : 'Sin casos'}
                            </p>
                          </div>
                        )}
                      </td>
                    )
                  })}
                  {modo === 'carga' ? (
                    <>
                      <td className="border-b border-r border-border px-2 py-3 text-center text-base font-extrabold tabular-nums text-primary">{analista.capacidad.carga_activa}</td>
                      <td className="border-b border-r border-border px-3 py-3 align-top">
                        <CapacidadAnalista
                          analista={analista}
                          editando={editando}
                          valor={editando ? edicion.valor : ''}
                          guardando={guardando && editando}
                          error={editando ? errorCapacidad : null}
                          onEmpezar={() => empezarEdicion(analista)}
                          onCambiar={(valor) => setEdicion((actual) => actual?.analistaId === analista.analista_id ? { ...actual, valor } : actual)}
                          onCancelar={() => { setEdicion(null); setErrorCapacidad(null) }}
                          onGuardar={(evento) => void guardarCapacidad(evento, analista)}
                        />
                      </td>
                      <td className="border-b border-border px-3 py-3">
                        <p className="font-extrabold tabular-nums text-primary">{sla ?? '—'}</p>
                        <p className="mt-1 text-[9px] tabular-nums text-muted-foreground">{analista.operacion.sla_asignacion_en_24h} de {analista.operacion.sla_asignacion_evaluables} · {analista.operacion.sin_tocar_actual} sin atender</p>
                      </td>
                    </>
                  ) : (
                    <>
                      <td className="border-b border-r border-border px-2 py-3 text-center">
                        <p className="text-sm font-extrabold tabular-nums text-primary">{conversionTotal ?? '—'}</p>
                        <p className="text-[8px] tabular-nums text-muted-foreground">{analista.pen.cohorte.convertidos} de {resueltos}</p>
                      </td>
                      <td className="border-b border-r border-border px-2 py-3 text-center font-bold tabular-nums">{resueltos}</td>
                      <td className="border-b border-border px-2 py-3 text-center font-bold tabular-nums">{analista.pen.cohorte.leads_unicos_recibidos}</td>
                    </>
                  )}
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
    </section>
  )
}

function LecturaUsd({
  datos,
  analistas = datos.analistas,
}: {
  datos: MetricasDistribucionLeads
  analistas?: AnalistaDistribucionLeads[]
}): JSX.Element {
  const analistasConUsd = analistas.filter((analista) => {
    const usd = analista.usd_no_segmentado
    return usd.cartera_actual_episodios > 0 || usd.cohorte_episodios_recibidos > 0
  })
  const capitalUsd = analistasConUsd.reduce(
    (total, analista) => total + analista.usd_no_segmentado.cartera_actual_capital,
    0,
  )

  return (
    <section aria-labelledby="distribucion-usd-titulo" className="rounded-lg border border-border bg-muted/15">
      <div className="flex flex-wrap items-start justify-between gap-2 border-b border-border px-4 py-3">
        <div>
          <h4 id="distribucion-usd-titulo" className="text-xs font-bold text-foreground">
            Resultados en dólares
          </h4>
          <p className="mt-0.5 text-[11px] text-muted-foreground">
            Se muestran aparte para no mezclar dólares con soles.
          </p>
        </div>
        <Badge color="var(--accent)" variant="outline">
          {dinero(capitalUsd, 'USD')} en leads activos
        </Badge>
      </div>
      {analistasConUsd.length === 0 ? (
        <p className="px-4 py-5 text-center text-xs text-muted-foreground">
          No hay leads en dólares durante este período.
        </p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[620px] text-xs">
            <caption className="sr-only">Leads y resultados en dólares por analista.</caption>
            <thead>
              <tr className="border-b border-border text-left text-[10px] font-bold uppercase tracking-wider text-muted-foreground">
                <th scope="col" className="px-4 py-2">Analista</th>
                <th scope="col" className="px-3 py-2 text-right">Leads actuales</th>
                <th scope="col" className="px-3 py-2 text-right">Monto</th>
                <th scope="col" className="px-3 py-2 text-right">Recibidos</th>
                <th scope="col" className="px-4 py-2 text-right">Leads ganados</th>
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
                        {porcentaje(usd.convertidos, resueltos) ?? 'Sin resultados'}
                      </span>
                      <span className="ml-2 text-[10px] tabular-nums text-muted-foreground">
                        {usd.convertidos} ganados · {usd.descartados} descartados
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
            <Inbox className="size-4 text-accent" aria-hidden /> Pendientes de asignar
          </h4>
          <p className="mt-0.5 text-[11px] text-muted-foreground">
            {porRepartir.total.carga_total} en total · {porRepartir.total.pen.cantidad} en soles · {porRepartir.total.usd.cantidad} en dólares
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
            subtitulo="Asignar a un responsable"
            cola={porRepartir.global}
            rangos={rangos}
          />
          {porRepartir.bandejas.map((bandeja) => (
            <ColaCard
              key={bandeja.supervisor_id}
              titulo={`Pendientes de ${bandeja.supervisor_nombre}`}
              subtitulo="Asignar dentro de su equipo"
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
        <p className="text-xs font-bold text-foreground">Aviso sobre los datos</p>
        <p className="mt-0.5 text-[11px] leading-relaxed text-muted-foreground">
          {sinMontoActual + sinMontoCohorte > 0 && (
            <span>{sinMontoActual + sinMontoCohorte} registros no tienen monto. </span>
          )}
          {aproximadosActual + aproximadosCohorte > 0 && (
            <span>{aproximadosActual + aproximadosCohorte} registros usan fechas estimadas.</span>
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
  const equipos = useMemo(() => (datos ? equiposSupervisados(datos) : []), [datos])
  const [equipoSeleccionadoId, setEquipoSeleccionadoId] = useState<string | null>(null)
  const [analisisAbierto, setAnalisisAbierto] = useState(false)

  useEffect(() => {
    if (equipos.length === 0) {
      setEquipoSeleccionadoId(null)
      return
    }
    if (!equipos.some((equipo) => equipo.id === equipoSeleccionadoId)) {
      setEquipoSeleccionadoId(equipos[0]?.id ?? null)
    }
  }, [equipos, equipoSeleccionadoId])

  const equipoSeleccionado = equipos.find((equipo) => equipo.id === equipoSeleccionadoId) ?? null

  return (
    <Card className="overflow-hidden" aria-labelledby={tituloId}>
      <CardHeader className="gap-4 border-b border-border bg-muted/15 pb-4 lg:flex-row lg:items-end lg:justify-between">
        <div className="max-w-2xl">
          <p className="mb-1 text-[10px] font-extrabold uppercase tracking-[0.16em] text-accent">
            Cadena de mando comercial
          </p>
          <CardTitle id={tituloId} className="text-lg">Supervisión de distribución</CardTitle>
          <CardDescription className="mt-1 max-w-xl leading-relaxed">
            Gerencia revisa la carga de cada equipo, abre el detalle por analista y decide dónde coordinar la siguiente asignación. Soles y dólares permanecen separados.
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
            <div
              className="rounded-lg border border-accent/30 bg-accent/5 px-4 py-3"
              role="status"
            >
              <p className="text-xs font-extrabold uppercase tracking-[0.12em] text-accent">
                Datos ficticios de demostración
              </p>
              <p className="mt-1 text-[11px] leading-relaxed text-muted-foreground">
                Sirven únicamente para conocer el tablero. No representan información real de la empresa.
              </p>
            </div>
          )}
          {cargando && (
            <p className="flex items-center gap-2 text-[11px] font-medium text-muted-foreground" role="status">
              <RefreshCw className="size-3.5 animate-spin" aria-hidden /> Actualizando datos…
            </p>
          )}
          <ResumenDistribucion datos={datos} />

          <EquiposBajoSupervision
            equipos={equipos}
            seleccionadoId={equipoSeleccionadoId}
            onSeleccionar={(equipoId) => {
              setEquipoSeleccionadoId(equipoId)
              setAnalisisAbierto(true)
            }}
          />

          <section className="overflow-hidden rounded-2xl border border-border/80 bg-card">
            <div className="flex flex-wrap items-center justify-between gap-3 px-4 py-4 sm:px-5">
              <div>
                <p className="text-[9px] font-extrabold uppercase tracking-[0.14em] text-accent">Segundo nivel</p>
                <h4 className="mt-1 text-base font-extrabold text-primary">Análisis por analista y monto</h4>
                <p className="mt-1 text-xs text-muted-foreground">
                  Separa disponibilidad actual y conversión histórica para que Gerencia tome la decisión.
                </p>
              </div>
              <Button type="button" variant="outline" onClick={() => setAnalisisAbierto((abierto) => !abierto)} disabled={!equipoSeleccionado}>
                {analisisAbierto ? 'Cerrar análisis' : 'Abrir análisis completo'}
              </Button>
            </div>

            {analisisAbierto && equipoSeleccionado && (
              <div className="space-y-4 border-t border-border bg-muted/10 p-4 sm:p-5">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div>
                    <p className="text-sm font-extrabold text-foreground">Equipo de {equipoSeleccionado.nombre}</p>
                    <p className="mt-0.5 text-[11px] text-muted-foreground">
                      {equipoSeleccionado.analistas.length} analistas · período {datos.cohorte.desde_inclusivo} al {datos.cohorte.hasta_inclusivo}
                    </p>
                  </div>
                  <Badge color="var(--accent)" variant="outline">PEN · 7 rangos</Badge>
                </div>
                <MatrizPen
                  datos={datos}
                  analistas={equipoSeleccionado.analistas}
                  onEditarCapacidad={onEditarCapacidad}
                />
                <LecturaUsd datos={datos} analistas={equipoSeleccionado.analistas} />
              </div>
            )}
          </section>

          <PorRepartir datos={datos} />
          <AlertaCalidad datos={datos} />

          <p className="text-[10px] leading-relaxed text-muted-foreground">
            Período: {datos.cohorte.desde_inclusivo} al {datos.cohorte.hasta_inclusivo}. El tiempo de atención empieza cuando el lead ingresa o se reabre y no se reinicia si cambia de analista.
          </p>
        </CardContent>
      )}
    </Card>
  )
}

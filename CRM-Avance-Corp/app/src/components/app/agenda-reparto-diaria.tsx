import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  AlertTriangle,
  CalendarDays,
  Check,
  ChevronLeft,
  ChevronRight,
  ClipboardPenLine,
  MousePointerClick,
  Shuffle,
  UsersRound,
} from 'lucide-react'
import { toast } from 'sonner'
import { agendaRepartoDiaria, guardarAgendaRepartoDiaria } from '@/data/crm-api'
import type {
  AgendaRepartoDiaria as AgendaRepartoDiariaData,
  AsignacionAgendaReparto,
  OrigenAgendaReparto,
} from '@/lib/tipos'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { SectionHead } from '@/components/common/section-head'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'

const ZONA_HORARIA = 'America/Lima'
const ORIGENES: OrigenAgendaReparto[] = ['landing', 'formulario']

interface EstadoAgenda {
  datos: AgendaRepartoDiariaData | null
  cargando: boolean
  error: string | null
}

function partesFecha(fecha: string): [number, number, number] {
  const [anio = 0, mes = 0, dia = 0] = fecha.split('-').map(Number)
  return [anio, mes, dia]
}

function fechaLima(ahora = new Date()): string {
  const partes = new Intl.DateTimeFormat('en-CA', {
    timeZone: ZONA_HORARIA,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(ahora)
  const toma = (tipo: Intl.DateTimeFormatPartTypes) => partes.find((parte) => parte.type === tipo)?.value ?? ''
  return `${toma('year')}-${toma('month')}-${toma('day')}`
}

function sumarDias(fecha: string, dias: number): string {
  const [anio, mes, dia] = partesFecha(fecha)
  const resultado = new Date(Date.UTC(anio, mes - 1, dia + dias))
  return resultado.toISOString().slice(0, 10)
}

function inicioSemana(fecha: string): string {
  const [anio, mes, dia] = partesFecha(fecha)
  const fechaUtc = new Date(Date.UTC(anio, mes - 1, dia))
  const diasDesdeLunes = (fechaUtc.getUTCDay() + 6) % 7
  return sumarDias(fecha, -diasDesdeLunes)
}

function textoFecha(fecha: string, corto = false): string {
  const [anio, mes, dia] = partesFecha(fecha)
  return new Intl.DateTimeFormat('es-PE', {
    timeZone: 'UTC',
    weekday: corto ? 'short' : 'long',
    day: 'numeric',
    month: corto ? undefined : 'long',
  }).format(new Date(Date.UTC(anio, mes - 1, dia, 12)))
}

function etiquetaOrigen(origen: OrigenAgendaReparto): string {
  return origen === 'landing' ? 'Landing' : 'Formulario'
}

function asignacionDe(
  asignaciones: AsignacionAgendaReparto[] | undefined,
  origen: OrigenAgendaReparto,
): AsignacionAgendaReparto | undefined {
  return asignaciones?.find((asignacion) => asignacion.origen === origen)
}

function IconoOrigen({ origen, className }: { origen: OrigenAgendaReparto; className?: string }) {
  const Icono = origen === 'landing' ? MousePointerClick : ClipboardPenLine
  return <Icono aria-hidden className={className} />
}

/**
 * Reporte operativo de la primera etapa: Coordinación fija el turno y ve cada
 * entrega real a supervisores, aunque después nadie la derive a un analista.
 */
export function AgendaRepartoDiaria() {
  const [fechaSeleccionada, setFechaSeleccionada] = useState(() => fechaLima())
  const [estado, setEstado] = useState<EstadoAgenda>({ datos: null, cargando: true, error: null })
  const [landing, setLanding] = useState('')
  const [formulario, setFormulario] = useState('')
  const [guardando, setGuardando] = useState(false)
  const abortRef = useRef<AbortController | null>(null)
  const desde = useMemo(() => inicioSemana(fechaSeleccionada), [fechaSeleccionada])

  const cargar = useCallback(async () => {
    abortRef.current?.abort()
    const controlador = new AbortController()
    abortRef.current = controlador
    setEstado((anterior) => ({ ...anterior, cargando: true, error: null }))
    try {
      const datos = await agendaRepartoDiaria({ desde, dias: 7 }, controlador.signal)
      if (controlador.signal.aborted) return
      setEstado({ datos, cargando: false, error: null })
    } catch (error) {
      if (controlador.signal.aborted) return
      setEstado((anterior) => ({
        ...anterior,
        cargando: false,
        error: error instanceof Error ? error.message : 'No se pudo cargar la agenda de reparto.',
      }))
    }
  }, [desde])

  useEffect(() => {
    void cargar()
    return () => abortRef.current?.abort()
  }, [cargar])

  const diaSeleccionado = useMemo(
    () => estado.datos?.dias.find((dia) => dia.fecha === fechaSeleccionada),
    [estado.datos, fechaSeleccionada],
  )
  const asignacionLanding = asignacionDe(diaSeleccionado?.asignaciones, 'landing')
  const asignacionFormulario = asignacionDe(diaSeleccionado?.asignaciones, 'formulario')

  useEffect(() => {
    setLanding(asignacionLanding?.supervisor_id ?? '')
    setFormulario(asignacionFormulario?.supervisor_id ?? '')
  }, [asignacionFormulario?.supervisor_id, asignacionLanding?.supervisor_id, fechaSeleccionada])

  const esHistorico = fechaSeleccionada < fechaLima()
  const estaCompleta = Boolean(landing && formulario && landing !== formulario)
  const hayCambios = landing !== (asignacionLanding?.supervisor_id ?? '')
    || formulario !== (asignacionFormulario?.supervisor_id ?? '')

  const guardar = useCallback(async () => {
    if (!estaCompleta || guardando) return
    setGuardando(true)
    try {
      await guardarAgendaRepartoDiaria(fechaSeleccionada, landing, formulario)
      toast.success(`Turno del ${textoFecha(fechaSeleccionada)} guardado`)
      await cargar()
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'No se pudo guardar la agenda de reparto.')
    } finally {
      setGuardando(false)
    }
  }, [cargar, estaCompleta, fechaSeleccionada, formulario, guardando, landing])

  const invertir = useCallback(() => {
    if (!landing || !formulario) return
    setLanding(formulario)
    setFormulario(landing)
  }, [formulario, landing])

  const cambiarDia = useCallback((delta: number) => {
    setFechaSeleccionada((actual) => sumarDias(actual, delta))
  }, [])

  if (estado.cargando && !estado.datos) {
    return (
      <Card className="overflow-hidden">
        <SectionHead icon={CalendarDays} title="Coordinación → supervisores" />
        <PanelCargando filas={4} />
      </Card>
    )
  }

  if (estado.error && !estado.datos) {
    return (
      <Card className="overflow-hidden">
        <SectionHead icon={CalendarDays} title="Coordinación → supervisores" />
        <PanelError mensaje={estado.error} onReintentar={() => void cargar()} reintentando={estado.cargando} />
      </Card>
    )
  }

  const destinos = estado.datos?.destinos ?? []
  const dias = estado.datos?.dias ?? []

  return (
    <Card className="overflow-hidden border-primary/20 bg-gradient-to-br from-card via-card to-primary/[0.045]">
      <SectionHead
        icon={CalendarDays}
        title="Coordinación → supervisores"
        right={<span className="text-[11px] font-semibold text-muted-foreground">Turno y entregas reales</span>}
      />
      <p className="px-4 pb-3 text-xs text-muted-foreground sm:px-5">
        El conteo aumenta apenas Coordinación entrega un lead a una bandeja. No depende de que Supervisión lo reparta después a un analista.
      </p>

      <div className="border-y border-border bg-background/45 px-4 py-3 sm:px-5">
        <div className="flex flex-wrap items-center gap-2">
          <Button
            type="button"
            size="icon"
            variant="ghost"
            aria-label="Ver día anterior"
            onClick={() => cambiarDia(-1)}
          >
            <ChevronLeft />
          </Button>
          <div className="min-w-[13rem] flex-1">
            <p className="text-[11px] font-bold uppercase tracking-[0.12em] text-primary">Turno seleccionado</p>
            <p className="mt-0.5 text-base font-bold capitalize tracking-tight">{textoFecha(fechaSeleccionada)}</p>
          </div>
          <label className="sr-only" htmlFor="fecha-agenda-reparto">Cambiar fecha de agenda</label>
          <Input
            id="fecha-agenda-reparto"
            type="date"
            value={fechaSeleccionada}
            onChange={(event) => setFechaSeleccionada(event.target.value)}
            className="h-9 w-auto min-w-[9.25rem] text-xs"
          />
          <Button
            type="button"
            size="icon"
            variant="ghost"
            aria-label="Ver día siguiente"
            onClick={() => cambiarDia(1)}
          >
            <ChevronRight />
          </Button>
        </div>
      </div>

      <div className="overflow-x-auto border-b border-border px-4 py-3 sm:px-5">
        <div className="grid min-w-[41rem] grid-cols-7 gap-1.5" aria-label="Semana de reparto">
          {dias.map((dia) => {
            const landingSemana = asignacionDe(dia.asignaciones, 'landing')
            const formularioSemana = asignacionDe(dia.asignaciones, 'formulario')
            const seleccionado = dia.fecha === fechaSeleccionada
            return (
              <button
                key={dia.fecha}
                type="button"
                onClick={() => setFechaSeleccionada(dia.fecha)}
                aria-pressed={seleccionado}
                className={`rounded-lg border px-2 py-2 text-left transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 ${
                  seleccionado
                    ? 'border-primary bg-primary text-primary-foreground shadow-sm'
                    : 'border-border bg-card hover:border-primary/40 hover:bg-muted/50'
                }`}
              >
                <span className={`block text-[10px] font-bold uppercase tracking-wide ${seleccionado ? 'text-primary-foreground/75' : 'text-muted-foreground'}`}>
                  {textoFecha(dia.fecha, true)}
                </span>
                <span className="mt-1 block text-sm font-bold tabular-nums">{partesFecha(dia.fecha)[2]}</span>
                <span className={`mt-1.5 block truncate text-[10px] font-semibold ${seleccionado ? 'text-primary-foreground' : 'text-foreground'}`}>
                  L · {landingSemana?.supervisor_alias ?? '—'}
                </span>
                <span className={`block truncate text-[10px] font-semibold ${seleccionado ? 'text-primary-foreground' : 'text-foreground'}`}>
                  F · {formularioSemana?.supervisor_alias ?? '—'}
                </span>
              </button>
            )
          })}
        </div>
      </div>

      {destinos.length < 2 ? (
        <PanelVacio
          icono={UsersRound}
          titulo="Falta habilitar a Carmen y Jor"
          detalle="La agenda se activará cuando ambas supervisoras estén disponibles para reparto."
        />
      ) : !diaSeleccionado ? (
        <PanelVacio
          icono={CalendarDays}
          titulo="No pudimos abrir este día"
          detalle="Elige una fecha dentro de la semana mostrada para programar el turno."
        />
      ) : (
        <div className="p-4 sm:p-5">
          <div className="grid gap-3 lg:grid-cols-2">
            {ORIGENES.map((origen) => {
              const esLanding = origen === 'landing'
              const valor = esLanding ? landing : formulario
              const cambiar = esLanding ? setLanding : setFormulario
              const asignacion = esLanding ? asignacionLanding : asignacionFormulario
              const entregas = asignacion?.entregas ?? []
              const fueraTurno = asignacion?.fuera_turno ?? 0
              const totalEntregado = asignacion?.derivados ?? 0
              return (
                <section
                  key={origen}
                  className={`rounded-xl border p-3.5 ${
                    esLanding ? 'border-primary/20 bg-primary/[0.055]' : 'border-accent/25 bg-accent/[0.07]'
                  }`}
                >
                  <div className="flex items-start justify-between gap-3">
                    <div className="flex items-center gap-2.5">
                      <span className={`grid size-8 place-items-center rounded-lg ${esLanding ? 'bg-primary text-primary-foreground' : 'bg-accent text-accent-foreground'}`}>
                        <IconoOrigen origen={origen} className="size-4" />
                      </span>
                      <div>
                        <h3 className="text-sm font-bold">{etiquetaOrigen(origen)}</h3>
                        <p className="text-[11px] text-muted-foreground">Origen a distribuir</p>
                      </div>
                    </div>
                    <span className="rounded-full border border-border bg-card/80 px-2 py-0.5 text-[11px] font-bold tabular-nums text-foreground">
                      {totalEntregado} {totalEntregado === 1 ? 'entregado' : 'entregados'}
                    </span>
                  </div>
                  <label className="mt-3 block text-[11px] font-bold uppercase tracking-[0.1em] text-muted-foreground" htmlFor={`agenda-${origen}`}>
                    Supervisora de turno
                  </label>
                  <Select
                    id={`agenda-${origen}`}
                    value={valor}
                    disabled={esHistorico || guardando}
                    aria-label={`Asignar ${etiquetaOrigen(origen)} a una supervisora`}
                    onChange={(event) => cambiar(event.target.value)}
                    className="mt-1.5 bg-card"
                  >
                    <option value="">Seleccionar supervisora…</option>
                    {destinos.map((destino) => (
                      <option key={destino.perfil_id} value={destino.perfil_id}>
                        {destino.alias} · {destino.nombre}
                      </option>
                    ))}
                  </Select>
                  <p className="mt-2 text-[11px] text-muted-foreground">
                    {asignacion?.supervisor_alias
                      ? `Turno guardado: ${asignacion.supervisor_alias}`
                      : 'Aún no tiene un turno guardado.'}
                  </p>
                  <div className="mt-3 rounded-lg border border-border/80 bg-card/70 p-2.5">
                    <p className="text-[10px] font-bold uppercase tracking-[0.1em] text-muted-foreground">
                      Entregado realmente por Coordinación
                    </p>
                    {entregas.length > 0 ? (
                      <div className="mt-1.5 flex flex-wrap gap-1.5">
                        {entregas.map((entrega) => (
                          <span
                            key={entrega.supervisor_id ?? entrega.supervisor_nombre}
                            className={`rounded-full border px-2 py-0.5 text-[11px] font-semibold tabular-nums ${
                              entrega.coincide_turno
                                ? 'border-primary/20 bg-primary/[0.06] text-foreground'
                                : 'border-warning/40 bg-warning/10 text-warning-text'
                            }`}
                          >
                            {entrega.supervisor_alias ?? entrega.supervisor_nombre}: {entrega.derivados}
                          </span>
                        ))}
                      </div>
                    ) : totalEntregado > 0 ? (
                      <p className="mt-1.5 text-[11px] font-medium text-foreground">
                        {totalEntregado} registrados. Actualiza la base para ver el desglose por destino.
                      </p>
                    ) : (
                      <p className="mt-1.5 text-[11px] text-muted-foreground">Aún no hay entregas en este origen.</p>
                    )}
                    {fueraTurno > 0 ? (
                      <p className="mt-2 flex items-start gap-1.5 text-[11px] font-semibold text-warning-text" role="status">
                        <AlertTriangle className="mt-px size-3.5 shrink-0" aria-hidden />
                        {fueraTurno} {fueraTurno === 1 ? 'entrega no coincide' : 'entregas no coinciden'} con el turno guardado.
                      </p>
                    ) : null}
                  </div>
                </section>
              )
            })}
          </div>

          <div className="mt-3 flex flex-wrap items-center justify-between gap-3 border-t border-border/80 pt-3">
            <p className="text-xs text-muted-foreground" aria-live="polite">
              {esHistorico
                ? 'Los días anteriores se conservan como registro.'
                : !landing || !formulario
                  ? 'Elige una supervisora para cada origen.'
                  : landing === formulario
                    ? 'Landing y Formulario deben quedar en supervisoras distintas.'
                    : hayCambios
                      ? 'Hay cambios pendientes de guardar.'
                      : <><Check aria-hidden className="mr-1 inline size-3.5 text-success" />Turno guardado.</>}
            </p>
            {!esHistorico ? (
              <div className="flex items-center gap-2">
                <Button
                  type="button"
                  size="sm"
                  variant="outline"
                  disabled={!landing || !formulario || guardando}
                  onClick={invertir}
                >
                  <Shuffle /> Invertir
                </Button>
                <Button
                  type="button"
                  size="sm"
                  disabled={!estaCompleta || !hayCambios || guardando}
                  onClick={() => void guardar()}
                >
                  {guardando ? 'Guardando…' : 'Guardar turno'}
                </Button>
              </div>
            ) : null}
          </div>

          {estado.error ? (
            <p className="mt-3 rounded-lg bg-destructive/10 px-3 py-2 text-xs font-medium text-destructive" role="status">
              {estado.error}
            </p>
          ) : null}
        </div>
      )}
    </Card>
  )
}

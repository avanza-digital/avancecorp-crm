import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  CalendarDays,
  Check,
  ChevronLeft,
  ChevronRight,
  Shuffle,
  UsersRound,
} from 'lucide-react'
import { toast } from 'sonner'
import { origenLabel } from '@/lib/tipos'
import { useRefrescarAlVolver } from '@/lib/use-refrescar-al-volver'
import { TablaEnvoltura, Td, Th, TheadCrm } from '@/components/common/tabla'
import { agendaRepartoDiaria, guardarAgendaRepartoDiaria } from '@/data/crm-api'
import type {
  AgendaRepartoDiaria as AgendaRepartoDiariaData,
  AsignacionAgendaReparto,
  OrigenAgendaReparto,
  OrigenEntregasReparto,
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

/**
 * Reporte operativo de la primera etapa: Coordinación fija el turno y ve cada
 * entrega real a supervisores, aunque después nadie la derive a un analista.
 */
export function AgendaRepartoDiaria({ activo = true }: { activo?: boolean }) {
  const [fechaSeleccionada, setFechaSeleccionada] = useState(() => fechaLima())
  const [estado, setEstado] = useState<EstadoAgenda>({ datos: null, cargando: true, error: null })
  const [borradores, setBorradores] = useState<Record<string, { landing: string; formulario: string }>>({})
  const [filtroOrigen, setFiltroOrigen] = useState('')
  const [filtroSupervisor, setFiltroSupervisor] = useState('')
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
  const cargarActualRef = useRef(cargar)
  useEffect(() => { cargarActualRef.current = cargar }, [cargar])

  const diaSeleccionado = useMemo(
    () => estado.datos?.dias.find((dia) => dia.fecha === fechaSeleccionada),
    [estado.datos, fechaSeleccionada],
  )
  const asignacionLanding = asignacionDe(diaSeleccionado?.asignaciones, 'landing')
  const asignacionFormulario = asignacionDe(diaSeleccionado?.asignaciones, 'formulario')

  const borrador = borradores[fechaSeleccionada]
  const landing = borrador?.landing ?? asignacionLanding?.supervisor_id ?? ''
  const formulario = borrador?.formulario ?? asignacionFormulario?.supervisor_id ?? ''
  const setLanding = (valor: string) => setBorradores((prev) => ({ ...prev, [fechaSeleccionada]: { landing: valor, formulario } }))
  const setFormulario = (valor: string) => setBorradores((prev) => ({ ...prev, [fechaSeleccionada]: { landing, formulario: valor } }))
  const esHistorico = fechaSeleccionada < fechaLima()
  const estaCompleta = Boolean(landing && formulario && landing !== formulario)
  const hayCambios = landing !== (asignacionLanding?.supervisor_id ?? '')
    || formulario !== (asignacionFormulario?.supervisor_id ?? '')

  useRefrescarAlVolver(cargar, !activo || hayCambios || guardando)

  const consultaVisibleRef = useRef('')
  useEffect(() => {
    if (!activo) {
      consultaVisibleRef.current = ''
      return
    }
    const clave = `${activo}:${desde}`
    if (consultaVisibleRef.current === clave || hayCambios || guardando) return
    consultaVisibleRef.current = clave
    void cargar()
  }, [activo, desde, cargar, hayCambios, guardando])
  useEffect(() => () => {
    abortRef.current?.abort()
    consultaVisibleRef.current = ''
  }, [])

  const guardar = useCallback(async () => {
    if (!estaCompleta || guardando) return
    abortRef.current?.abort()
    setEstado((prev) => ({ ...prev, cargando: false }))
    setGuardando(true)
    try {
      await guardarAgendaRepartoDiaria(fechaSeleccionada, landing, formulario)
      // El recibo confirmó estos turnos. Una relectura fallida no debe volver
      // a mostrar los valores anteriores como si fueran los guardados.
      setEstado((prev) => ({ ...prev, datos: prev.datos ? { ...prev.datos,
        dias: prev.datos.dias.map((dia) => dia.fecha !== fechaSeleccionada ? dia : {
          ...dia, asignaciones: dia.asignaciones.map((asignacion) => {
            const id = asignacion.origen === 'landing' ? landing : formulario
            const destino = prev.datos!.destinos.find((d) => d.perfil_id === id)
            return { ...asignacion, supervisor_id: id,
              supervisor_nombre: destino?.nombre ?? null, supervisor_alias: destino?.alias ?? null }
          }),
        }),
      } : null }))
      setBorradores((prev) => {
        const siguientes = { ...prev }
        delete siguientes[fechaSeleccionada]
        return siguientes
      })
      toast.success(`Turno del ${textoFecha(fechaSeleccionada)} guardado`)
      await cargarActualRef.current()
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'No se pudo guardar la agenda de reparto.')
    } finally {
      setGuardando(false)
    }
  }, [estaCompleta, fechaSeleccionada, formulario, guardando, landing])

  const invertir = useCallback(() => {
    if (!landing || !formulario) return
    setBorradores((prev) => ({ ...prev, [fechaSeleccionada]: { landing: formulario, formulario: landing } }))
  }, [fechaSeleccionada, formulario, landing])

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
    <Card className="overflow-hidden">
      <SectionHead
        icon={CalendarDays}
        title="Coordinación → supervisores"
        right={<Button size="sm" variant="outline" disabled={estado.cargando || guardando || hayCambios}
          onClick={() => void cargar()}>Actualizar</Button>}
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
            <p className="text-xs font-medium text-muted-foreground">Turno seleccionado</p>
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
          titulo="Faltan supervisoras para los turnos"
          detalle="Se necesitan al menos dos supervisoras habilitadas para programar los turnos."
        />
      ) : !diaSeleccionado ? (
        <PanelVacio
          icono={CalendarDays}
          titulo="No pudimos abrir este día"
          detalle="Elige una fecha dentro de la semana mostrada para programar el turno."
        />
      ) : (
        <div className="p-4 sm:p-5">
          <div className="grid gap-4 sm:grid-cols-2" aria-label="Turnos del día">
            {ORIGENES.map((origen) => {
              const esLanding = origen === 'landing'
              const asignacion = esLanding ? asignacionLanding : asignacionFormulario
              return (
                <div key={origen}>
                  <label className="mb-1.5 block text-sm font-semibold" htmlFor={`agenda-${origen}`}>
                    {etiquetaOrigen(origen)}
                  </label>
                  <Select id={`agenda-${origen}`} value={esLanding ? landing : formulario}
                    disabled={esHistorico || guardando} aria-label={`Asignar ${etiquetaOrigen(origen)} a una supervisora`}
                    onChange={(event) => (esLanding ? setLanding : setFormulario)(event.target.value)}>
                    <option value="">Seleccionar supervisora…</option>
                    {destinos.map((destino) => <option key={destino.perfil_id} value={destino.perfil_id}>
                      {destino.alias} · {destino.nombre}
                    </option>)}
                  </Select>
                  <p className="mt-1.5 text-xs text-muted-foreground">
                    {asignacion?.supervisor_alias ? `Turno guardado: ${asignacion.supervisor_alias}` : 'Aún no tiene un turno guardado.'}
                    {!esLanding ? ' Formulario y Formulario 3 comparten este turno.' : ''}
                  </p>
                </div>
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

          <section className="mt-6 border-t border-border pt-4" aria-label="Entregas realizadas">
            <div className="mb-3 flex flex-wrap items-center gap-3">
              <h3 className="mr-auto text-sm font-semibold">Entregas realizadas</h3>
              <div className="w-full sm:w-48">
              <Select aria-label="Filtrar entregas a supervisoras por origen" value={filtroOrigen}
                disabled={diaSeleccionado.origenes === undefined} onChange={(e) => setFiltroOrigen(e.target.value)}>
                <option value="">Todos los orígenes</option>
                {[...new Set([...(diaSeleccionado.origenes ?? []).map((fila) => fila.origen), ...(filtroOrigen ? [filtroOrigen] : [])])]
                  .map((origen) => <option key={origen} value={origen}>{origenLabel(origen)}</option>)}
              </Select>
              </div>
              <div className="w-full sm:w-56">
              <Select aria-label="Filtrar entregas por supervisora" value={filtroSupervisor}
                onChange={(e) => setFiltroSupervisor(e.target.value)}>
                <option value="">Todas las supervisoras</option>
                {[...new Map([
                  ...destinos.map((destino) => [destino.perfil_id, destino.alias] as const),
                  ...(diaSeleccionado.origenes ?? []).flatMap((grupo) => grupo.entregas
                    .filter((entrega) => entrega.supervisor_id !== null)
                    .map((entrega) => [entrega.supervisor_id!, entrega.supervisor_alias ?? entrega.supervisor_nombre ?? 'Supervisora'] as const)),
                  ...(filtroSupervisor ? [[filtroSupervisor, destinos.find((d) => d.perfil_id === filtroSupervisor)?.alias ?? 'Supervisora seleccionada'] as const] : []),
                ])].map(([id, nombre]) => <option key={id} value={id}>{nombre}</option>)}
              </Select>
              </div>
            </div>
            {diaSeleccionado.origenes === undefined ? (
              <p className="text-sm text-muted-foreground">Desglose por origen no disponible.
                {' '}{diaSeleccionado.asignaciones.reduce((total, fila) => total + fila.derivados, 0)} entregas registradas en los turnos.
              </p>
            ) : (
              <EntregasPorOrigen origenes={diaSeleccionado.origenes} origen={filtroOrigen} supervisor={filtroSupervisor} />
            )}
          </section>

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

function EntregasPorOrigen({ origenes, origen, supervisor }: {
  origenes: OrigenEntregasReparto[]; origen: string; supervisor: string
}) {
  const filas = origenes.filter((grupo) => !origen || grupo.origen === origen).flatMap((grupo) =>
    grupo.entregas.filter((entrega) => !supervisor || entrega.supervisor_id === supervisor)
      .map((entrega) => ({ ...entrega, origen: grupo.origen, turno: grupo.turno,
        fuera: grupo.turno == null ? null : entrega.coincide_turno ? 0 : entrega.derivados })))
  const total = filas.reduce((suma, fila) => suma + fila.derivados, 0)
  const fuera = filas.reduce((suma, fila) => suma + (fila.fuera ?? 0), 0)
  return <>
    <p className="mb-2 text-xs text-muted-foreground" role="status">{total} entregados · {fuera} fuera de turno</p>
    {filas.length === 0 ? <p className="py-4 text-sm text-muted-foreground">No hay entregas con estos filtros en el día seleccionado.</p> : (
      <TablaEnvoltura ariaLabel="Entregas por origen y supervisora">
        <TheadCrm><Th>Origen</Th><Th>Supervisora destino</Th><Th className="text-right">Entregados</Th><Th className="text-right">Fuera de turno</Th></TheadCrm>
        <tbody>{filas.map((fila) => <tr key={`${fila.origen}:${fila.supervisor_id}`} className="border-b border-border last:border-0">
          <Td>{origenLabel(fila.origen)}</Td><Td>{fila.supervisor_alias ?? fila.supervisor_nombre}</Td>
          <Td className="text-right tabular-nums">{fila.derivados}</Td>
          <Td className={`text-right tabular-nums ${fila.fuera ? 'font-semibold text-warning-text' : ''}`}>{fila.fuera ?? 'No aplica'}</Td>
        </tr>)}</tbody>
      </TablaEnvoltura>
    )}
  </>
}

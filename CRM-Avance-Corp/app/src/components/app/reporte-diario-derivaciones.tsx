import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { CalendarDays, RotateCcw } from 'lucide-react'
import { listarReporteDerivacionesCoordinacion } from '@/data/crm-api'
import { useAhora } from '@/lib/ahora'
import { fmtFecha } from '@/lib/format'
import { paginar } from '@/lib/paginacion'
import type { ReporteDerivacionesCoordinacion } from '@/lib/reporte-derivaciones-coordinacion'
import { etiquetaOrigen, ORIGENES_TODOS } from '@/lib/tipos'
import { usePeriodoDerivaciones } from '@/lib/use-periodo-derivaciones'
import { ControlesPeriodoDerivaciones } from '@/components/common/controles-periodo-derivaciones'
import { Paginacion } from '@/components/common/paginacion'
import { SectionHead } from '@/components/common/section-head'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { TablaEnvoltura, Td, Th, TheadCrm } from '@/components/common/tabla'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Select } from '@/components/ui/select'

const DIAS_POR_PAGINA = 7

interface EstadoReporte {
  datos: ReporteDerivacionesCoordinacion | null
  cargando: boolean
  error: string | null
}

interface FiltrosReporte {
  supervisorId: string
  analistaId: string
  origen: string
}

interface OpcionSupervisor {
  id: string
  nombre: string
}

interface OpcionAnalista {
  id: string
  nombre: string
  supervisores: string[]
}

interface CatalogoReporte {
  supervisores: OpcionSupervisor[]
  analistas: OpcionAnalista[]
  origenes: string[]
}

const FILTROS_VACIOS: FiltrosReporte = { supervisorId: '', analistaId: '', origen: '' }
const ORDEN_ESPANOL = new Intl.Collator('es', { sensitivity: 'base' })

function fusionarCatalogo(
  actual: CatalogoReporte,
  reporte: ReporteDerivacionesCoordinacion,
): CatalogoReporte {
  const supervisores = new Map(actual.supervisores.map((opcion) => [opcion.id, opcion]))
  const analistas = new Map(actual.analistas.map((opcion) => [opcion.id, {
    ...opcion,
    supervisores: new Set(opcion.supervisores),
  }]))
  const origenes = new Set(actual.origenes)

  for (const dia of reporte.dias) {
    for (const entrega of dia.entregas) {
      supervisores.set(entrega.supervisor_id, {
        id: entrega.supervisor_id,
        nombre: entrega.supervisor_nombre,
      })
      const analista = analistas.get(entrega.analista_id) ?? {
        id: entrega.analista_id,
        nombre: entrega.analista_nombre,
        supervisores: new Set<string>(),
      }
      analista.nombre = entrega.analista_nombre
      analista.supervisores.add(entrega.supervisor_id)
      analistas.set(entrega.analista_id, analista)
      origenes.add(entrega.origen)
    }
  }

  return {
    supervisores: [...supervisores.values()].sort((a, b) => ORDEN_ESPANOL.compare(a.nombre, b.nombre)),
    analistas: [...analistas.values()]
      .map((opcion) => ({ ...opcion, supervisores: [...opcion.supervisores] }))
      .sort((a, b) => ORDEN_ESPANOL.compare(a.nombre, b.nombre)),
    origenes: [...origenes].sort((a, b) => ORDEN_ESPANOL.compare(etiquetaOrigen(a), etiquetaOrigen(b))),
  }
}

function colorOrigen(origen: string): string {
  if (origen === 'landing') return 'var(--accent)'
  if (origen === 'formulario') return 'var(--chart-4)'
  if (origen === 'referido') return 'var(--primary)'
  if (origen === 'oficina') return 'var(--warning)'
  return 'var(--muted-foreground)'
}

/** Parte histórico sin filas ni PII de leads; sí identifica a los colaboradores. */
export function ReporteDiarioDerivaciones() {
  const ahora = useAhora()
  const {
    modo,
    setModo,
    desdeRango,
    setDesdeRango,
    hastaRango,
    setHastaRango,
    periodo,
    rangoValido,
    hoy,
  } = usePeriodoDerivaciones(ahora)
  const [estado, setEstado] = useState<EstadoReporte>({ datos: null, cargando: true, error: null })
  const [filtros, setFiltros] = useState<FiltrosReporte>(FILTROS_VACIOS)
  const [catalogo, setCatalogo] = useState<CatalogoReporte>({
    supervisores: [],
    analistas: [],
    origenes: ORIGENES_TODOS.map((origen) => origen.k),
  })
  const [pagina, setPagina] = useState(0)
  const abortRef = useRef<AbortController | null>(null)

  const cargar = useCallback(async () => {
    abortRef.current?.abort()
    if (!rangoValido) {
      setEstado({ datos: null, cargando: false, error: null })
      return
    }
    const controlador = new AbortController()
    abortRef.current = controlador
    setEstado({ datos: null, cargando: true, error: null })
    try {
      const datos = await listarReporteDerivacionesCoordinacion(
        periodo.desde,
        periodo.hasta,
        controlador.signal,
      )
      if (controlador.signal.aborted) return
      setCatalogo((actual) => fusionarCatalogo(actual, datos))
      setEstado({ datos, cargando: false, error: null })
    } catch (error) {
      if (controlador.signal.aborted) return
      setEstado({
        datos: null,
        cargando: false,
        error: error instanceof Error ? error.message : 'No se pudo cargar el reporte diario.',
      })
    }
  }, [periodo.desde, periodo.hasta, rangoValido])

  useEffect(() => {
    setPagina(0)
    void cargar()
    return () => abortRef.current?.abort()
  }, [cargar])

  const cambiarFiltros = useCallback((siguiente: Partial<FiltrosReporte>) => {
    setFiltros((actual) => ({ ...actual, ...siguiente }))
    setPagina(0)
  }, [])

  const analistasElegibles = useMemo(
    () => catalogo.analistas.filter((analista) => (
      !filtros.supervisorId || analista.supervisores.includes(filtros.supervisorId)
    )),
    [catalogo.analistas, filtros.supervisorId],
  )

  const diasFiltrados = useMemo(() => (estado.datos?.dias ?? []).map((dia) => {
    const entregas = dia.entregas.filter((entrega) => (
      (!filtros.supervisorId || entrega.supervisor_id === filtros.supervisorId)
      && (!filtros.analistaId || entrega.analista_id === filtros.analistaId)
      && (!filtros.origen || entrega.origen === filtros.origen)
    ))
    return {
      fecha: dia.fecha,
      entregas,
      total: entregas.reduce((suma, entrega) => suma + entrega.derivados, 0),
    }
  }), [estado.datos?.dias, filtros])

  const resumen = useMemo(() => {
    const analistas = new Set<string>()
    const origenes = new Set<string>()
    let total = 0
    let diasConEntregas = 0
    for (const dia of diasFiltrados) {
      total += dia.total
      if (dia.total > 0) diasConEntregas += 1
      for (const entrega of dia.entregas) {
        analistas.add(entrega.analista_id)
        origenes.add(entrega.origen)
      }
    }
    return { total, analistas: analistas.size, origenes: origenes.size, diasConEntregas }
  }, [diasFiltrados])

  const dias = useMemo(
    () => paginar(diasFiltrados, pagina, DIAS_POR_PAGINA),
    [diasFiltrados, pagina],
  )
  const hayFiltros = Boolean(filtros.supervisorId || filtros.analistaId || filtros.origen)
  const hayCambios = hayFiltros || modo !== 'ayer'

  const limpiarFiltros = useCallback(() => {
    setFiltros(FILTROS_VACIOS)
    setModo('ayer')
    setPagina(0)
  }, [setModo])

  return (
    <Card className="overflow-hidden border-primary/15 shadow-[0_18px_45px_-38px_rgba(17,30,61,0.9)]">
      <SectionHead
        icon={CalendarDays}
        title="Entregas por fecha, analista y origen"
        right={estado.cargando ? (
          <span className="text-[11px] font-semibold text-muted-foreground" role="status">
            Actualizando…
          </span>
        ) : undefined}
      />
      <p className="px-5 pb-3 text-xs text-muted-foreground">
        Revisa cuánto recibió cada analista y de qué fuente provino. Los conteos salen del historial de entregas.
      </p>

      <ControlesPeriodoDerivaciones
        modo={modo}
        desde={desdeRango}
        hasta={hastaRango}
        hoy={hoy}
        rangoInvalido={!rangoValido}
        titulo="Fecha de entrega"
        descripcion="Ayer, los últimos 7 días o un rango de hasta 366 días."
        onModo={setModo}
        onDesde={(fecha) => {
          setModo('rango')
          setDesdeRango(fecha)
        }}
        onHasta={(fecha) => {
          setModo('rango')
          setHastaRango(fecha)
        }}
      />

      <div className="border-b border-border/70 bg-card px-5 py-4">
        <div className="mb-2.5 flex min-h-8 flex-wrap items-center justify-between gap-2">
          <div>
            <p className="text-xs font-semibold text-foreground">Filtrar este reporte</p>
            <p className="text-[11px] text-muted-foreground">Puedes combinar supervisor, analista y origen.</p>
          </div>
          {hayCambios ? (
            <Button type="button" size="sm" variant="ghost" onClick={limpiarFiltros}>
              <RotateCcw aria-hidden /> Restablecer
            </Button>
          ) : null}
        </div>

        <div className="grid gap-3 md:grid-cols-3">
          <label className="grid gap-1.5 text-xs font-semibold text-foreground">
            Supervisor que entregó
            <Select
              value={filtros.supervisorId}
              aria-label="Filtrar entregas por supervisor"
              onChange={(event) => cambiarFiltros({
                supervisorId: event.target.value,
                analistaId: '',
              })}
            >
              <option value="">Todos los supervisores</option>
              {catalogo.supervisores.map((supervisor) => (
                <option key={supervisor.id} value={supervisor.id}>{supervisor.nombre}</option>
              ))}
            </Select>
          </label>

          <label className="grid gap-1.5 text-xs font-semibold text-foreground">
            Analista que recibió
            <Select
              value={filtros.analistaId}
              aria-label="Filtrar entregas por analista"
              onChange={(event) => cambiarFiltros({ analistaId: event.target.value })}
            >
              <option value="">Todos los analistas</option>
              {analistasElegibles.map((analista) => (
                <option key={analista.id} value={analista.id}>{analista.nombre}</option>
              ))}
            </Select>
          </label>

          <label className="grid gap-1.5 text-xs font-semibold text-foreground">
            Origen del lead
            <Select
              value={filtros.origen}
              aria-label="Filtrar entregas por origen"
              onChange={(event) => cambiarFiltros({ origen: event.target.value })}
            >
              <option value="">Todos los orígenes</option>
              {catalogo.origenes.map((origen) => (
                <option key={origen} value={origen}>{etiquetaOrigen(origen)}</option>
              ))}
            </Select>
          </label>
        </div>
      </div>

      {!rangoValido ? (
        <p className="px-5 py-4 text-sm text-muted-foreground">
          Corrige el rango para consultar las entregas.
        </p>
      ) : estado.cargando ? (
        <PanelCargando filas={5} />
      ) : estado.error ? (
        <PanelError mensaje={estado.error} onReintentar={() => void cargar()} reintentando={estado.cargando} />
      ) : estado.datos ? (
        <>
          <div
            className="grid grid-cols-2 border-b border-border/70 bg-primary/[0.025] sm:grid-cols-4"
            aria-live="polite"
            aria-label="Resumen de entregas con los filtros actuales"
          >
            {[
              ['Leads entregados', resumen.total],
              ['Analistas', resumen.analistas],
              ['Orígenes', resumen.origenes],
              ['Días con entregas', resumen.diasConEntregas],
            ].map(([etiqueta, valor], indice) => (
              <div
                key={etiqueta}
                className={`px-5 py-3 ${indice % 2 === 0 ? '' : 'border-l border-border/70'} ${indice > 1 ? 'border-t border-border/70 sm:border-t-0' : ''} ${indice > 0 ? 'sm:border-l sm:border-border/70' : ''}`}
              >
                <p className="text-[11px] font-semibold text-muted-foreground">{etiqueta}</p>
                <p className="mt-0.5 text-xl font-extrabold tabular-nums text-primary">{valor}</p>
              </div>
            ))}
          </div>

          {resumen.total === 0 ? (
            <PanelVacio
              icono={CalendarDays}
              titulo={hayFiltros ? 'No hay entregas que coincidan' : 'No hubo entregas en este período'}
              detalle={hayFiltros
                ? 'Prueba otra combinación o restablece los filtros.'
                : 'Elige otro período para consultar el historial de distribución.'}
            >
              {hayCambios ? (
                <Button type="button" size="sm" variant="outline" onClick={limpiarFiltros}>
                  <RotateCcw aria-hidden /> Restablecer filtros
                </Button>
              ) : null}
            </PanelVacio>
          ) : (
            <>
              <TablaEnvoltura ariaLabel="Entregas por fecha, analista y origen">
                <TheadCrm>
                  <Th>Fecha</Th>
                  <Th>Analista</Th>
                  <Th>Origen</Th>
                  <Th className="hidden lg:table-cell">Supervisor</Th>
                  <Th className="text-right">Leads</Th>
                </TheadCrm>
                <tbody>
                  {dias.visibles.flatMap((dia) => (
                    dia.entregas.length === 0
                      ? [(
                          <tr key={dia.fecha} className="border-b border-border last:border-0">
                            <Td><time dateTime={dia.fecha}>{fmtFecha(dia.fecha)}</time></Td>
                            <Td colSpan={3} className="text-muted-foreground">Sin entregas con estos filtros</Td>
                            <Td className="text-right font-semibold tabular-nums">0</Td>
                          </tr>
                        )]
                      : dia.entregas.map((entrega, indice) => (
                          <tr
                            key={`${dia.fecha}-${entrega.supervisor_id}-${entrega.analista_id}-${entrega.origen}`}
                            className="border-b border-border last:border-0"
                          >
                            {indice === 0 ? (
                              <Td rowSpan={dia.entregas.length} className="align-top font-medium">
                                <time dateTime={dia.fecha}>{fmtFecha(dia.fecha)}</time>
                              </Td>
                            ) : null}
                            <Td className="font-medium">{entrega.analista_nombre}</Td>
                            <Td>
                              <Badge color={colorOrigen(entrega.origen)} variant="outline">
                                {etiquetaOrigen(entrega.origen)}
                              </Badge>
                            </Td>
                            <Td className="hidden text-muted-foreground lg:table-cell">
                              {entrega.supervisor_nombre}
                            </Td>
                            <Td className="text-right text-base font-extrabold tabular-nums text-primary">
                              {entrega.derivados}
                            </Td>
                          </tr>
                        ))
                  ))}
                </tbody>
              </TablaEnvoltura>
              <div className="border-t border-border px-4 py-2.5">
                <Paginacion
                  paginaActual={dias.paginaActual}
                  paginas={dias.paginas}
                  total={diasFiltrados.length}
                  onCambio={setPagina}
                  ariaLabel="Paginación de días del reporte de entregas"
                />
              </div>
            </>
          )}

          <p className="border-t border-border px-5 py-2 text-xs text-muted-foreground">
            Cuenta entregas confirmadas desde Supervisión. Si el lead volvió a la bandeja antes de ser gestionado, no suma.
          </p>
        </>
      ) : null}
    </Card>
  )
}

// Gerencia dentro de un equipo («Toda la operación / Equipo de X», 27/09/2026):
// la pantalla del supervisor —cifras-filtro, buscador, tabla nueva (más
// Pendientes, que gerencia compara) y la ficha protagonista del analista— SIN
// pestaña Pendientes hasta que gerencia tenga permiso sobre esa consulta (G4).
// La selección del usuario vive en la ruta (atrás/adelante, enlaces directos); la
// automática —quien más atención necesita— solo en la pantalla y sin mover el
// foco. Se conservan los autores inactivos y los registros sin autor (Codex).
import { useEffect, useId, useLayoutEffect, useMemo, useRef, useState, type JSX, type MouseEvent } from 'react'
import { ChevronRight, ClipboardList, Users } from 'lucide-react'
import { hashDe } from '@/lib/router'
import type { EquipoPulso } from '@/lib/gestion-diaria-pulso'
import { compararGravedad, filtrarOrdenarEquipo, type FilaEquipoPresentada, type FiltrosEquipo, type OrdenEquipo } from '@/lib/gestion-diaria-equipo'
import { filtrosDePreset, nombreEquipo } from '@/lib/gestion-diaria-operacion'
import { PanelVacio } from '@/components/common/estado-panel'
import { cn } from '@/lib/utils'
import { TablaEquipoDiaria } from './tabla-equipo-diaria'
import { PanelAnalistaSupervisor, type SeleccionSupervisor } from './panel-analista-supervisor'
import { PanelSupervisorAdaptable } from './panel-supervisor-adaptable'
import { BarraEquipo } from './barra-equipo'
import { ErrorConsultaGerencia } from './error-consulta-gerencia'
import { BOTON_CABECERA, FOCO } from './estilos-gestion'

/** Tabla (con su columna extra desplazable) + separación + ficha mínima, como el supervisor. */
const ANCHO_EN_LINEA = 1100
const BASE = filtrosDePreset()

const rutaAnalista = (id: string) => hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'analista', id })
const rutaEquipo = (clave: string) => hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'equipo', id: clave })
const navegarEnVentana = (e: MouseEvent<HTMLAnchorElement>) => !e.ctrlKey && !e.metaKey && !e.shiftKey && !e.altKey

export function VistaEquipoGerencia({ equipo, filas, error, cargando, enVuelo, recargar, minimo, dia, esHoy, ahora, analistaRuta, filtros, setFiltros, actualizacion, revocar, volver, abrirGeneral, enfocarAlEntrar = false }: {
  equipo: EquipoPulso
  /** Filas del detalle de los analistas ACTIVOS del equipo; null mientras llegan. */
  filas: FilaEquipoPresentada[] | null
  error: unknown
  cargando: boolean
  enVuelo: boolean
  recargar: () => Promise<void>
  minimo: number | undefined
  dia: string
  esHoy: boolean
  ahora: number
  analistaRuta: string | null
  filtros: FiltrosEquipo
  setFiltros: (cambio: (f: FiltrosEquipo) => FiltrosEquipo) => void
  actualizacion: number
  revocar: () => void
  volver: () => void
  abrirGeneral: () => void
  /** Solo cuando el usuario ENTRA al equipo; no al volver de una recarga ni por enlace directo. */
  enfocarAlEntrar?: boolean
}): JSX.Element {
  const nombre = nombreEquipo({ fuera: equipo.clave === 'fuera', nombre: equipo.nombre })
  const panelId = useId()
  const raiz = useRef<HTMLElement>(null)
  const tituloEquipo = useRef<HTMLHeadingElement>(null)
  const tituloPanel = useRef<HTMLHeadingElement>(null)
  const origen = useRef<HTMLElement | null>(null)
  const propia = useRef(false)
  const apertura = useRef(0)
  const autoInhibida = useRef(false)
  const [local, setLocal] = useState<SeleccionSupervisor | null>(null)
  const [estrecho, setEstrecho] = useState(false)
  const [ampliado, setAmpliado] = useState(false)
  const [enfocarRuta, setEnfocarRuta] = useState(false)
  const idsEquipo = equipo.personas.flatMap((p) => p.analista_id === null ? [] : [p.analista_id])
  const persona = analistaRuta ? equipo.personas.find((p) => p.analista_id === analistaRuta) : undefined
  const seleccion: SeleccionSupervisor | null = analistaRuta
    ? { analista: analistaRuta, nombre: persona?.nombre_completo ?? null, apertura: 0, pestana: 'todo', enfocar: enfocarRuta, origen: 'usuario' }
    : local
  const mostradas = useMemo(() => filas ? filtrarOrdenarEquipo(filas, filtros) : [], [filas, filtros])
  const fila = filas?.find((f) => f.analista_id === seleccion?.analista)
  const automatica = seleccion?.origen === 'automatica'
  const modal = seleccion !== null && !automatica && (estrecho || ampliado)
  const oculta = Boolean(fila && !mostradas.some((f) => f.analista_id === fila.analista_id))
  const atencion = filas?.filter((f) => f.requiere_atencion).length ?? 0
  const conteos = filas ? {
    analistas: filas.length, con_actividad: filas.filter((f) => f.gestiones_hoy > 0).length,
    sin_actividad: filas.filter((f) => f.gestiones_hoy === 0).length,
    con_pendientes: filas.filter((f) => f.tareas_pendientes > 0 || (f.primer_intento_vencido ?? 0) > 0).length,
  } : null

  // Al entrar desde la operación, el foco llega al título del equipo (con una persona elegida, a su ficha).
  const alEntrar = useRef(enfocarAlEntrar && !analistaRuta)
  useEffect(() => { if (alEntrar.current) tituloEquipo.current?.focus({ preventScroll: true }) }, [])
  // Una persona elegida FUERA de esta tabla (la operación, un enlace) lleva el foco a su ficha;
  // la elegida en la tabla lo deja en su fila, como el supervisor.
  useLayoutEffect(() => {
    if (!analistaRuta) return
    setEnfocarRuta(!propia.current)
    propia.current = false
  }, [analistaRuta])
  useLayoutEffect(() => {
    const nodo = raiz.current
    if (!nodo || typeof ResizeObserver === 'undefined') return
    const medir = () => setEstrecho(nodo.clientWidth < ANCHO_EN_LINEA)
    const observador = new ResizeObserver(medir)
    observador.observe(nodo)
    medir()
    return () => observador.disconnect()
  }, [])
  // Selección automática: pantalla ancha, sin ruta, sin cierre voluntario; el más grave de lo visible.
  useEffect(() => {
    if (analistaRuta || local || autoInhibida.current || estrecho || !filas) return
    const candidata = mostradas.filter((f) => f.requiere_atencion).toSorted(compararGravedad)[0]
    if (candidata) setLocal({ analista: candidata.analista_id, nombre: candidata.nombre_completo, apertura: ++apertura.current, pestana: 'todo', enfocar: false, origen: 'automatica' })
  }, [analistaRuta, local, estrecho, filas, mostradas])
  // Una automática que se queda sin sitio se cierra, sin abrir ninguna ventana.
  useLayoutEffect(() => { if (estrecho && local?.origen === 'automatica') setLocal(null) }, [estrecho, local])

  const devolverFoco = (analista: string | null) => requestAnimationFrame(() => {
    const activo = document.activeElement
    if (activo instanceof HTMLElement && activo !== document.body && !document.getElementById(panelId)?.contains(activo)) return
    const enTabla = analista ? raiz.current?.querySelector<HTMLElement>(`tr[data-analista="${CSS.escape(analista)}"] button`) : null
    const destino = origen.current?.isConnected ? origen.current : enTabla ?? tituloEquipo.current
    destino?.focus({ preventScroll: true })
    destino?.scrollIntoView?.({ block: 'nearest' })
  })
  const seleccionar = (f: FilaEquipoPresentada) => {
    origen.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
    propia.current = true
    setLocal(null)
    if (f.analista_id !== analistaRuta) window.location.hash = rutaAnalista(f.analista_id)
  }
  const seleccionarAutor = (analista: string, control: HTMLElement) => {
    origen.current = control
    propia.current = false
    setLocal(null)
    window.location.hash = rutaAnalista(analista)
  }
  const cerrar = () => {
    const analista = seleccion?.analista ?? null
    autoInhibida.current = true
    setAmpliado(false)
    setLocal(null)
    if (analistaRuta) window.location.hash = rutaEquipo(equipo.clave)
    devolverFoco(analista)
  }
  const abrirRegistroEquipo = (control: HTMLElement) => {
    origen.current = control
    if (analistaRuta) window.location.hash = rutaEquipo(equipo.clave)
    setLocal({ analista: null, nombre: null, apertura: ++apertura.current, pestana: 'todo', enfocar: true, origen: 'usuario' })
  }
  const ordenar = (orden: OrdenEquipo) => setFiltros((f) => ({ ...f, orden, ascendente: f.orden === orden ? !f.ascendente : orden === 'nombre' }))
  const volverClick = (e: MouseEvent<HTMLAnchorElement>) => { if (navegarEnVentana(e)) { e.preventDefault(); volver() } }

  return (
    <section ref={raiz} aria-label={nombre} className="flex min-h-0 flex-1 flex-col gap-3">
      <div className="flex shrink-0 flex-wrap items-end justify-between gap-x-4 gap-y-2">
        <div className="min-w-0">
          <nav aria-label="Ruta de la operación" className="flex flex-wrap items-center gap-1 text-[12.5px] text-[var(--muted-foreground-strong)]">
            <a href={hashDe('gestion-diaria')} onClick={volverClick} className={cn('rounded-md font-semibold text-[var(--accent-press)] underline-offset-2 hover:underline', FOCO)}>Toda la operación</a>
            <ChevronRight aria-hidden className="size-3.5" /><span aria-current="page">{nombre}</span>
          </nav>
          <h3 ref={tituloEquipo} tabIndex={-1} className={cn('mt-0.5 rounded-md text-xl font-extrabold leading-tight text-primary', FOCO)}>{nombre}</h3>
          <p className="text-[12.5px] text-[var(--muted-foreground-strong)]">{equipo.metricas.analistas_activos} {equipo.metricas.analistas_activos === 1 ? 'analista' : 'analistas'} · {equipo.metricas.con_actividad} con registro{esHoy ? ' hoy' : ''}</p>
        </div>
        <button type="button" className={BOTON_CABECERA} onClick={(e) => abrirRegistroEquipo(e.currentTarget)}><ClipboardList aria-hidden className="size-4" />Registro del equipo</button>
      </div>

      <div className={cn('grid min-h-0 flex-1 gap-4', estrecho ? 'grid-cols-1' : 'grid-cols-[minmax(0,1fr)_clamp(360px,32%,440px)]')}>
        <div className="me-equipo flex min-h-0 min-w-0 flex-col overflow-clip rounded-2xl border border-border bg-card">
          {error ? <div className="p-6"><ErrorConsultaGerencia error={error} recargar={recargar} enVuelo={enVuelo} /></div>
            : cargando || !filas || !conteos ? <p role="status" className="p-6 text-[13.5px] text-[var(--muted-foreground-strong)]">Consultando los analistas del equipo…</p>
              : <>
                {filas.length > 0 && <BarraEquipo filtros={filtros} setFiltros={setFiltros} conteos={conteos} atencion={atencion} />}
                {filas.length === 0
                  ? <PanelVacio icono={Users} titulo="Este equipo no tiene analistas activos" detalle="Sus registros de autores inactivos siguen disponibles abajo y en el registro del equipo." />
                  : <TablaEquipoDiaria conPendientes filas={mostradas} filtros={filtros} ordenar={ordenar} seleccion={seleccion?.analista ?? null}
                    seleccionar={seleccionar} panelId={panelId} minimo={minimo ?? 1}
                    irAlDetalle={() => { tituloPanel.current?.focus({ preventScroll: true }); tituloPanel.current?.scrollIntoView?.({ block: 'nearest' }) }} />}
                <div className="flex shrink-0 flex-wrap items-center justify-between gap-x-4 gap-y-1 border-t border-border px-4 py-2.5 text-xs text-[var(--muted-foreground-strong)]">
                  <p><span role="status">{mostradas.length} de {filas.length} analistas</span></p>
                  <p>La actividad registrada no acredita presencia.</p>
                </div>
                {equipo.personas.some((p) => !p.activo) && (
                  <div className="shrink-0 space-y-1.5 border-t border-border px-4 py-3 text-[13px]">
                    <h4 className="font-bold text-primary">Otros autores de los registros</h4>
                    {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
                    <ul role="list" className="space-y-1">
                      {equipo.personas.filter((p) => !p.activo).map((p) => (
                        <li key={p.analista_id ?? 'sin-autor'}>
                          {p.analista_id
                            ? <button type="button" onClick={(e) => seleccionarAutor(p.analista_id!, e.currentTarget)} className={cn('cursor-pointer rounded-md font-semibold text-[var(--accent-press)] underline-offset-2 hover:underline', FOCO)}>{p.nombre_completo ?? 'Autor no disponible'}</button>
                            : 'Sin autor'}: {p.llamadas} llamadas · {p.citas_agendadas} citas agendadas
                        </li>
                      ))}
                    </ul>
                    {equipo.personas.some((p) => p.analista_id === null) && (
                      <button type="button" onClick={abrirGeneral} className={cn('cursor-pointer rounded-md font-semibold text-[var(--accent-press)] underline-offset-2 hover:underline', FOCO)}>Ver registros sin autor en el registro general</button>
                    )}
                  </div>
                )}
              </>}
        </div>
        <PanelSupervisorAdaptable modal={modal} cerrar={cerrar} tituloRef={tituloPanel} claseAlojamiento={cn('me-panel-alojamiento flex min-h-0 min-w-0 flex-col', estrecho && 'hidden')}>
          <PanelAnalistaSupervisor id={panelId} seleccion={seleccion} fila={fila} dia={dia} minimo={minimo} tituloRef={tituloPanel}
            ampliado={ampliado} puedeAmpliar={!estrecho} ampliar={() => { setAmpliado((v) => !v); if (automatica && local) setLocal({ ...local, origen: 'usuario' }) }} cerrar={cerrar}
            oculta={oculta} limpiar={() => setFiltros(() => BASE)} actualizacion={actualizacion} revalidar={revocar} esHoy={esHoy} ahora={ahora}
            vacio="Nadie del equipo necesita atención ahora. Elige un analista para ver su día." silencioso={automatica}
            conPendientes={false} idsEquipo={idsEquipo} subtitulo={equipo.clave === 'fuera' ? 'Analista fuera de equipos comerciales' : `Analista del equipo de ${equipo.nombre}`} />
        </PanelSupervisorAdaptable>
      </div>
    </section>
  )
}

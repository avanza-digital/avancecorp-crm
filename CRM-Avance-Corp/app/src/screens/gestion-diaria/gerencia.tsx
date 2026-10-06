import { AccesoGestionesClientes } from '@/components/gestion-diaria/resumen-gestiones'
// «Toda la operación» de gerencia con el diseño de Gestión Diaria y las mejoras
// del supervisor (Miguel, 27/09/2026): cifras finas que abren su lista, tabla de
// equipos protagonista, ficha del equipo al lado y, dentro de cada equipo, la
// pantalla del supervisor. Plan v2 tras la revisión de Codex (vault).
import { useCallback, useEffect, useId, useLayoutEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode } from 'react'
import { ClipboardList, Columns3, Info, RefreshCw } from 'lucide-react'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { fechaLima } from '@/lib/agenda-derivada'
import { horaLimaDe } from '@/lib/gestion-diaria-analista'
import { cifraPulso, diaPulsoValido, desplazarDia, type MetricasPulso, type PulsoGerencia } from '@/lib/gestion-diaria-pulso'
import { presentarEquipo, type FiltrosEquipo } from '@/lib/gestion-diaria-equipo'
import { equipoConAtencion, filasOperacion, filtrarOrdenarOperacion, filtrosDePreset, nombreEquipo, totalOperacion, type FiltrosOperacion, type OrdenOperacion, type PresetEquipo } from '@/lib/gestion-diaria-operacion'
import { hashDe, leerHash } from '@/lib/router'
import { CrmApiError } from '@/data/crm-api'
import { usePulsoGerencia, useHabitosGerencia, useDetallePulso } from '@/data/gestion-diaria-pulso-queries'
import { ErrorConsultaGerencia } from '@/components/gestion-diaria/error-consulta-gerencia'
import { ReporteHabitos } from '@/components/gestion-diaria/reporte-habitos'
import { TablaEquiposGerencia, type AccionEquipo } from '@/components/gestion-diaria/tabla-equipos-gerencia'
import { PanelOperacionGerencia, type VistaOperacion } from '@/components/gestion-diaria/panel-operacion-gerencia'
import { PanelSupervisorAdaptable } from '@/components/gestion-diaria/panel-supervisor-adaptable'
import { VistaEquipoGerencia } from '@/components/gestion-diaria/vista-equipo-gerencia'
import { BOTON_CABECERA, CONTROL, FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { PanelCargando } from '@/components/common/estado-panel'
import { Button } from '@/components/ui/button'
import { Dialog, DialogHeader, DialogTitle, DialogBody } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Tabs } from '@/components/ui/tabs'
import { cn } from '@/lib/utils'
import './supervisor.css'
import './gerencia.css'
import './mi-equipo.css'


const METRICAS: { campo: keyof MetricasPulso; titulo: string; porcentaje?: boolean }[] = [
  { campo: 'llamadas', titulo: 'Llamadas' }, { campo: 'utiles', titulo: 'Llamadas útiles' },
  { campo: 'contestadas', titulo: 'Contestadas' }, { campo: 'tasa_contacto', titulo: 'Tasa de contacto', porcentaje: true },
  { campo: 'sin_actividad', titulo: 'Analistas sin actividad' }, { campo: 'leads_unicos', titulo: 'Leads distintos' },
  { campo: 'llamadas_por_lead', titulo: 'Llamadas por lead' }, { campo: 'citas_agendadas', titulo: 'Citas agendadas' },
]
// «Pulso diario» era jerga (Miguel, 27/09): la pestaña dice lo que muestra.
const PESTANAS = [{ valor: 'pulso', etiqueta: 'Actividad del día' }, { valor: 'habitos', etiqueta: 'Hábitos del equipo' }] as const
const SIN_PERMISO = new CrmApiError('Permiso de gerencia revocado', '42501')
const suscribirRuta = (cambio: () => void) => { window.addEventListener('hashchange', cambio); return () => window.removeEventListener('hashchange', cambio) }
const fotoRuta = () => window.location.hash
const memoria = (actor: string) => `avancecorp:gestion-diaria:f5:dia:${actor}`
function diaRecordado(actor: string, hoy: string) {
  try { const dia = sessionStorage.getItem(memoria(actor)); return dia && diaPulsoValido(dia, hoy) ? dia : null } catch { return null }
}

export function GestionDiariaGerencia({ accesoSeguimiento }: { accesoSeguimiento?: ReactNode }) {
  const { yo } = useAuth()
  const hoy = fechaLima(useAhora())
  // La gerencia demo entra con la operación de ejemplo del store (G0); otro rol, nunca.
  if (yo?.rol !== 'gerencia') return <p role="alert">El pulso completo requiere una sesión de gerencia.</p>
  return <VistaGerencia key={yo.id} actor={yo.id} hoy={hoy} accesoSeguimiento={accesoSeguimiento} />
}


/**
 * Tabla de equipos con sus seis primeras columnas (nombre ≥ 220 + 404 + rellenos
 * y canal ≥ 40) + separación (16) + ficha mínima (360) = 1040: a 1440 con el menú
 * abierto (~1150) caben lado a lado. Primer intento y Dispersión desplazan dentro
 * de la tabla. Por debajo, la ficha se abre encima.
 */
const ANCHO_EN_LINEA = 1040
const FILTROS_OPERACION: FiltrosOperacion = { busqueda: '', estado: 'todos', orden: 'atencion', ascendente: false }
const FECHA_LARGA = new Intl.DateTimeFormat('es-PE', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'America/Lima' })
const FECHA_CORTE = new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'long', timeZone: 'America/Lima' })
const TITULO_ORDEN: Record<OrdenOperacion, string> = {
  nombre: 'equipo', llamadas: 'llamadas', contacto: 'contacto', citas: 'citas', vencidas: 'vencidas',
  atencion: 'atención', primer_intento: 'primer intento', dispersion: 'dispersión',
}
const rutaDe = (tipo: 'equipo' | 'analista', id: string) => hashDe('gestion-diaria', null, undefined, undefined, { tipo, id })

function VistaGerencia({ actor, hoy, accesoSeguimiento }: { actor: string; hoy: string; accesoSeguimiento?: ReactNode }) {
  const [elegido, setElegido] = useState(() => diaRecordado(actor, hoy))
  const dia = elegido && diaPulsoValido(elegido, hoy) ? elegido : hoy
  const esHoy = dia === hoy
  const ahora = useAhora()
  const entrada = useRef<HTMLInputElement>(null)
  const pantalla = useRef<HTMLElement>(null)
  const titulo = useRef<HTMLHeadingElement>(null)
  const tituloPanel = useRef<HTMLHeadingElement>(null)
  const origenPanel = useRef<HTMLElement | null>(null)
  // Un cierre voluntario apaga la selección automática en esta visita (como el supervisor).
  const autoInhibida = useRef(false)
  const aperturas = useRef(0)
  // Último equipo cuyo título recibió el foco: entrar (o un enlace directo) lo enfoca; volver
  // de una recarga con el mismo equipo, no (como la ruta enfocada de F6).
  const equipoEnfocado = useRef<string | null>(null)
  const panelId = useId()
  const id = useId()
  const [avisoFecha, setAvisoFecha] = useState('')
  const [pestana, setPestana] = useState<'pulso' | 'habitos'>('pulso')
  const [dias, setDias] = useState<7 | 14 | 30>(14)
  const [actualizacion, setActualizacion] = useState(0)
  const [revocada, setRevocada] = useState(false)
  const revocar = useCallback(() => setRevocada(true), [])
  const [dialogo, setDialogo] = useState<'comparacion' | 'definiciones' | null>(null)
  const [estrecho, setEstrecho] = useState(false)
  const [ampliado, setAmpliado] = useState(false)
  const [filtros, setFiltros] = useState<FiltrosOperacion>(FILTROS_OPERACION)
  const [ficha, setFicha] = useState<{ vista: VistaOperacion; origen: 'automatica' | 'usuario' } | null>(null)
  const [filtrosPorEquipo, setFiltrosPorEquipo] = useState<Record<string, FiltrosEquipo>>({})
  const [anuncio, setAnuncio] = useState('')
  const [pedidoFoco, setPedidoFoco] = useState(0)
  const focoPeriodo = useRef(false)
  useSyncExternalStore(suscribirRuta, fotoRuta)
  const detalleRuta = leerHash().detalleGestion
  const ruta = detalleRuta?.tipo === 'cola' ? undefined : detalleRuta
  const activa = ruta ? 'pulso' : pestana
  const pulso = usePulsoGerencia(dia)
  const habitos = useHabitosGerencia(dia, dias, activa === 'habitos')
  // El detalle sostiene la atención y las barras de la operación: se carga al entrar
  // y se actualiza con el pulso, haya o no un equipo abierto (Codex, plan v2).
  const detalle = useDetallePulso(dia, activa === 'pulso' && pulso.datos !== null)
  // Una denegación en cualquier consulta retira toda la vista, aunque se cambie
  // de pestaña o se deshabilite después esa consulta. Revalidar sesión inicia
  // consultas nuevas, sin reutilizar la memoria paginada anterior.
  const sinPermiso = revocada || [pulso.error, detalle.error, habitos.error].some((e) => e instanceof CrmApiError && e.code === '42501')
  if (sinPermiso && !revocada) setRevocada(true)
  const error = sinPermiso ? SIN_PERMISO : activa === 'habitos' ? habitos.error : pulso.error
  const consulta = activa === 'habitos' ? habitos : pulso
  const datos = pulso.datos
  const filasDetalle = useMemo(() => detalle.datos ? presentarEquipo(detalle.datos) : null, [detalle.datos])
  const filasOp = useMemo(() => datos ? filasOperacion(datos, filasDetalle) : [], [datos, filasDetalle])
  const mostradas = filtrarOrdenarOperacion(filasOp, filtros)
  const conteos = { atencion: filasDetalle ? filasOp.filter(equipoConAtencion).length : null, vencidas: filasOp.filter((f) => f.vencidas > 0).length }
  const total = useMemo(() => datos ? totalOperacion(datos, filasOp) : null, [datos, filasOp])
  const grupo = datos && ruta ? datos.equipos.find((e) => ruta.tipo === 'equipo' ? e.clave === ruta.id : e.personas.some((p) => p.analista_id === ruta.id)) : undefined
  const automatica = ficha?.origen === 'automatica'
  const modal = ficha !== null && !automatica && (estrecho || ampliado)
  const registroDisponible = Boolean(datos) && !pulso.error && !sinPermiso

  useEffect(() => { if (entrada.current) entrada.current.value = dia }, [dia])
  useLayoutEffect(() => {
    const nodo = pantalla.current
    if (!nodo || typeof ResizeObserver === 'undefined') return
    const medir = () => setEstrecho(nodo.clientWidth < ANCHO_EN_LINEA)
    const observador = new ResizeObserver(medir)
    observador.observe(nodo)
    medir()
    return () => observador.disconnect()
  }, [])
  // Selección automática del equipo que más atención necesita: solo elige la ficha,
  // no navega ni mueve el foco (Codex: separada de la ruta del equipo).
  useEffect(() => {
    if (ruta || ficha || autoInhibida.current || estrecho || !filasDetalle || activa !== 'pulso') return
    const candidato = filtrarOrdenarOperacion(filasOp, FILTROS_OPERACION).find((f) => !f.fuera && (f.atencion ?? 0) > 0)
    if (candidato) setFicha({ vista: { tipo: 'equipo', clave: candidato.clave }, origen: 'automatica' })
  }, [ruta, ficha, estrecho, filasDetalle, filasOp, activa])
  // Una automática que se queda sin sitio se cierra, sin abrir ninguna ventana.
  useLayoutEffect(() => { if (estrecho && ficha?.origen === 'automatica') setFicha(null) }, [estrecho, ficha])
  useEffect(() => { if (!ruta) equipoEnfocado.current = null; else if (grupo) equipoEnfocado.current = grupo.clave })
  // «Atrás» desde un equipo: su vista se desmonta con el foco dentro y cae en el body;
  // se recoloca en la fila del equipo, como hace la miga (a11y, 27/09).
  const equipoPrevio = useRef<string | null>(null)
  useLayoutEffect(() => {
    const previo = equipoPrevio.current
    equipoPrevio.current = ruta && grupo ? grupo.clave : null
    if (!previo || ruta) return
    requestAnimationFrame(() => {
      const activo = document.activeElement
      if (activo instanceof HTMLElement && activo !== document.body) return
      ;(pantalla.current?.querySelector<HTMLElement>(`tr[data-equipo="${CSS.escape(previo)}"] th button`) ?? titulo.current)?.focus({ preventScroll: true })
    })
  })
  // Abrir una lista lejos del control (registro, sin registro) lleva el foco a la ficha.
  useLayoutEffect(() => { if (pedidoFoco) tituloPanel.current?.focus({ preventScroll: true }) }, [pedidoFoco])
  // El período vive en la barra de Hábitos, que se vuelve a montar con la consulta nueva:
  // quien lo cambió con el teclado lo sigue teniendo enfocado al llegar los datos (G3).
  useLayoutEffect(() => {
    if (!focoPeriodo.current || activa !== 'habitos' || !habitos.datos || habitos.cargando) return
    focoPeriodo.current = false
    document.getElementById(`${id}-periodo`)?.focus({ preventScroll: true })
  })

  const cambiarDia = (nuevo: string) => {
    if (!diaPulsoValido(nuevo, hoy)) {
      setAvisoFecha('Elige una fecha válida entre hoy y los últimos 365 días.')
      if (entrada.current) entrada.current.value = dia
      return
    }
    setElegido(nuevo === hoy ? null : nuevo); setAvisoFecha(''); setFicha(null); setAmpliado(false); autoInhibida.current = false
    try { if (nuevo === hoy) sessionStorage.removeItem(memoria(actor)); else sessionStorage.setItem(memoria(actor), nuevo) } catch { /* Sesión sin almacenamiento: selección en memoria. */ }
  }
  const actualizar = async () => {
    await Promise.all([consulta.recargar(), activa === 'pulso' ? detalle.recargar() : Promise.resolve()])
    setActualizacion((n) => n + 1)
  }
  const abrirFicha = (vista: VistaOperacion, control: HTMLElement | null, enfocar: boolean) => {
    const activo = document.activeElement
    origenPanel.current = control ?? (activo instanceof HTMLElement && activo !== document.body ? activo : null)
    setFicha({ vista, origen: 'usuario' })
    if (enfocar) setPedidoFoco((n) => n + 1)
  }
  const abrirRegistroGeneral = (control: HTMLElement | null, pestanaInicial: 'todo' | 'llamadas' = 'todo') =>
    abrirFicha({ tipo: 'registro', alcance: 'general', pestana: pestanaInicial, apertura: ++aperturas.current }, control, true)
  const cerrarFicha = () => {
    autoInhibida.current = true
    setAmpliado(false)
    setFicha(null)
    requestAnimationFrame(() => {
      const activo = document.activeElement
      if (activo instanceof HTMLElement && activo !== document.body && !document.getElementById(panelId)?.contains(activo)) return
      ;(origenPanel.current?.isConnected ? origenPanel.current : titulo.current)?.focus({ preventScroll: true })
    })
  }
  const entrarEquipo = (clave: string, preset?: PresetEquipo) => {
    if (preset) setFiltrosPorEquipo((p) => ({ ...p, [clave]: filtrosDePreset(preset) }))
    // En pantalla estrecha la ficha es una ventana: volver con la miga no debe reabrirla (E2E, 27/09).
    if (estrecho) setFicha(null)
    setAmpliado(false)
    window.location.hash = rutaDe('equipo', clave)
  }
  const abrirPersona = (analistaId: string) => { setAmpliado(false); window.location.hash = rutaDe('analista', analistaId) }
  // Un solo destino de foco por transición (Codex): quien abre otra lista después no lo pide aquí.
  const volverOperacion = (clave?: string, enfocar = true) => {
    window.location.hash = hashDe('gestion-diaria')
    if (enfocar) requestAnimationFrame(() => {
      const fila = clave ? pantalla.current?.querySelector<HTMLElement>(`tr[data-equipo="${CSS.escape(clave)}"] th button`) : null
      ;(fila ?? titulo.current)?.focus({ preventScroll: true })
    })
  }
  // Las cifras de «Toda la operación» (pie de la tabla) abren su lista exacta:
  // llamadas en el registro general, sin registro con nombres y el resto
  // filtrando u ordenando los equipos (revisión Codex del plan).
  const accionTotal = (tipo: AccionEquipo, control: HTMLElement) => {
    if (tipo === 'llamadas') abrirRegistroGeneral(control, 'llamadas')
    else if (tipo === 'sin_registro') abrirFicha({ tipo: 'sin_registro' }, control, true)
    // G4b: las citas agendadas abren su lista exacta.
    else if (tipo === 'citas') abrirFicha({ tipo: 'citas', ambito: 'operacion', clave: null, apertura: ++aperturas.current }, control, true)
    else {
      setFiltros((f) => ({ ...f, busqueda: '', estado: tipo, orden: tipo, ascendente: false }))
      setAnuncio(tipo === 'vencidas' ? 'Equipos con tareas vencidas, de más a menos.' : 'Equipos con analistas que necesitan atención, de más a menos.')
    }
  }
  const ordenar = (orden: OrdenOperacion) => {
    const ascendente = filtros.orden === orden ? !filtros.ascendente : orden === 'nombre'
    setFiltros((f) => ({ ...f, orden, ascendente }))
    setAnuncio(`Equipos ordenados por ${TITULO_ORDEN[orden]}, ${ascendente ? 'ascendente' : 'descendente'}.`)
  }
  const hora = datos ? horaLimaDe(datos.generado_en) : null

  let contenido: ReactNode
  if (error) contenido = <ErrorConsultaGerencia error={error} recargar={consulta.recargar} enVuelo={consulta.enVuelo} />
  else if (consulta.cargando) contenido = <PanelCargando filas={6} />
  else if (activa === 'habitos') contenido = habitos.datos && <ReporteHabitos key={`${dia}:${dias}`} datos={habitos.datos} equipos={datos?.equipos ?? []} estrecho={estrecho}
    alAbrirAnalista={() => setPestana('pulso')} periodo={<div className="flex items-center gap-2">
      <label htmlFor={`${id}-periodo`} className="text-[13px] font-semibold text-[var(--muted-foreground-strong)]">Período<span className="sr-only"> hasta {dia}</span></label>
      <div className="w-[152px]"><Select id={`${id}-periodo`} className={cn(CONTROL, 'min-h-0')} value={dias}
        onChange={(e) => { focoPeriodo.current = document.activeElement === e.currentTarget; setDias(Number(e.target.value) as 7 | 14 | 30) }}>
        {[7, 14, 30].map((n) => <option key={n} value={n}>{n} días calendario</option>)}</Select></div>
    </div>} />
  else if (!datos) contenido = null
  else if (ruta && grupo) {
    const activos = new Set(grupo.personas.flatMap((p) => p.activo && p.analista_id !== null ? [p.analista_id] : []))
    contenido = <VistaEquipoGerencia key={grupo.clave} equipo={grupo} filas={filasDetalle ? filasDetalle.filter((f) => activos.has(f.analista_id)) : null}
      error={detalle.error} cargando={detalle.cargando} enVuelo={detalle.enVuelo} recargar={detalle.recargar} minimo={detalle.datos?.umbrales.minimo_llamadas_utiles}
      dia={dia} esHoy={esHoy} ahora={ahora} analistaRuta={ruta.tipo === 'analista' ? ruta.id : null}
      filtros={filtrosPorEquipo[grupo.clave] ?? filtrosDePreset()} setFiltros={(cambio) => setFiltrosPorEquipo((p) => ({ ...p, [grupo.clave]: cambio(p[grupo.clave] ?? filtrosDePreset()) }))}
      actualizacion={actualizacion} hora={hora} revocar={revocar} volver={() => volverOperacion(grupo.clave)}
      abrirGeneral={() => { volverOperacion(undefined, false); abrirRegistroGeneral(null) }} enfocarAlEntrar={equipoEnfocado.current !== grupo.clave} />
  } else if (ruta) contenido = <p role="status" className="rounded-2xl border border-border bg-card p-6 text-[13.5px]">Este equipo o autor ya no aparece en el ámbito actual.{' '}
    <button type="button" className={cn('cursor-pointer rounded-md font-semibold text-[var(--accent-press)] underline-offset-2 hover:underline', FOCO)} onClick={() => volverOperacion()}>Volver a toda la operación</button></p>
  else contenido = <>
    <div className={cn('grid min-h-0 flex-1 gap-4', estrecho ? 'grid-cols-1' : 'grid-cols-[minmax(0,1fr)_clamp(360px,32%,440px)]')}>
      <div className="me-equipo flex min-h-0 min-w-0 flex-col overflow-clip rounded-2xl border border-border bg-card">
        {detalle.error && !sinPermiso && <div role="alert" className="flex shrink-0 flex-wrap items-center justify-between gap-2 border-b border-border bg-muted/60 px-4 py-2 text-[13px]">
          No se pudo consultar el detalle por analista: la atención y las barras no están disponibles.
          <Button variant="ghost" className="h-9 text-[13px] pointer-coarse:h-11" onClick={() => void detalle.recargar()} disabled={detalle.enVuelo}>Reintentar</Button>
        </div>}
        <TablaEquiposGerencia filas={mostradas} total={filasOp.length} conteos={conteos} sinDetalle={detalle.error ? 'error' : 'cargando'} umbrales={detalle.datos?.umbrales ?? null}
          filtros={filtros} setFiltros={setFiltros} ordenar={ordenar}
          seleccion={ficha?.vista.tipo === 'equipo' ? ficha.vista.clave : null} seleccionar={(f, control) => {
            abrirFicha({ tipo: 'equipo', clave: f.clave }, control, false)
            // Con la ficha al lado nada se mueve: se anuncia, como el supervisor (a11y, 27/09).
            if (!estrecho) setAnuncio(`Seleccionado ${nombreEquipo(f)}. Detalle disponible.`)
          }}
          accion={(f, tipo, control) => tipo === 'citas'
            ? abrirFicha({ tipo: 'citas', ambito: f.fuera ? 'fuera' : 'equipo', clave: f.fuera ? null : f.clave, apertura: ++aperturas.current }, control, true)
            : tipo === 'llamadas'
            ? abrirFicha({ tipo: 'registro', alcance: f.clave, pestana: 'llamadas', apertura: ++aperturas.current }, control, true)
            : entrarEquipo(f.clave, tipo)} totalOperacion={total!} accionTotal={accionTotal} panelId={panelId}
          irAlDetalle={() => { tituloPanel.current?.focus({ preventScroll: true }); tituloPanel.current?.scrollIntoView?.({ block: 'nearest' }) }} />
        {/* El pie del supervisor: cuántos se ven y cuándo; aquí, además, de qué momento son los pendientes. */}
        <div className="flex shrink-0 flex-wrap items-center justify-between gap-x-4 gap-y-1 border-t border-border px-4 py-2.5 text-xs text-[var(--muted-foreground-strong)]">
          <p><span role="status">{mostradas.length} de {filasOp.length} equipos</span> · Actualizado {hora}</p>
          <p>Organigrama actual · Pendientes al {FECHA_CORTE.format(new Date(datos.pendientes_al))}, {horaLimaDe(datos.pendientes_al)}</p>
        </div>
      </div>
      <PanelSupervisorAdaptable modal={modal} cerrar={cerrarFicha} tituloRef={tituloPanel} claseAlojamiento={cn('me-panel-alojamiento flex min-h-0 min-w-0 flex-col', estrecho && 'hidden')}>
        <PanelOperacionGerencia id={panelId} vista={ficha?.vista ?? null} pulso={datos} detalle={filasDetalle} detalleFallido={Boolean(detalle.error)} esHoy={esHoy} tituloRef={tituloPanel}
          ampliado={ampliado} puedeAmpliar={!estrecho} cerrar={cerrarFicha}
          ampliar={() => { setAmpliado((v) => !v); if (ficha && automatica) setFicha({ ...ficha, origen: 'usuario' }) }}
          abrirVista={(vista) => abrirFicha(vista, null, true)} entrarEquipo={entrarEquipo} abrirPersona={abrirPersona}
          actualizacion={actualizacion} revocar={revocar} />
      </PanelSupervisorAdaptable>
    </div>
  </>

  return (
    <section ref={pantalla} aria-label={esHoy ? 'Toda la operación hoy' : 'Toda la operación'} data-estrecho={estrecho}
      className="me-pantalla mx-auto flex w-full max-w-[1440px] flex-col gap-4 text-foreground">
      <header className="flex shrink-0 flex-wrap items-start justify-between gap-x-6 gap-y-3">
        <div className="min-w-0">
          <h2 ref={titulo} tabIndex={-1} className={cn('rounded-md text-[26px] font-extrabold leading-tight tracking-[-0.02em] text-primary', FOCO)}>{esHoy ? 'Toda la operación hoy' : 'Toda la operación'}</h2>
          <p className="mt-1 text-[13px] text-[var(--muted-foreground-strong)]">
            {esHoy ? 'Cómo va el día frente a ayer y a los días de referencia.' : `El ${FECHA_LARGA.format(new Date(`${dia}T12:00:00-05:00`))} frente al día anterior y a los días de referencia.`}
          </p>
        </div>
        {/* Solo el filtro de fecha junto al título (Miguel, 27/09: «eso debe estar pero no puede
            ocupar tanto espacio»); los demás botones van al final de la fila de pestañas. */}
        <div className="flex min-w-0 flex-wrap items-center gap-2">
          <label><span className="sr-only">Día de la operación</span>
            <Input ref={entrada} type="date" defaultValue={dia} min={desplazarDia(hoy, -365)} max={hoy} aria-describedby={avisoFecha ? `${id}-aviso` : undefined}
              className={cn(CONTROL, 'w-[150px] min-h-0')}
              onChange={(e) => {
                // El campo nativo conserva la escritura por segmentos; solo una fecha completa consulta.
                const valor = e.currentTarget.value
                if (e.currentTarget.validity.valid && valor) cambiarDia(valor)
                else if (valor.length === 10) { setAvisoFecha('Elige una fecha válida entre hoy y los últimos 365 días.'); e.currentTarget.value = dia }
              }}
              onBlur={(e) => { e.currentTarget.value = dia }} />
          </label>
          <button type="button" className={BOTON_CABECERA} aria-disabled={esHoy} onClick={() => { if (!esHoy) cambiarDia(hoy) }}>Hoy</button>
        </div>
      </header>
      {avisoFecha && <p role="alert" id={`${id}-aviso`} className="text-[13px] font-semibold text-[var(--destructive-text)]">{avisoFecha}</p>}
      <p role="status" className="sr-only">{anuncio}</p>
      <Tabs etiqueta="Vistas de gerencia" variante="subrayado" pestanas={PESTANAS} valor={activa} panelEnfocable={false}
        onCambio={(valor) => { setPestana(valor); if (ruta) window.location.hash = hashDe('gestion-diaria') }}
        className="flex min-h-0 flex-1 flex-col space-y-0"
        claseLista="gap-[22px] [&>[role=tab]]:min-h-[42px] [&>[role=tab]]:text-sm pointer-coarse:[&>[role=tab]]:min-h-11"
        acciones={<div role="group" aria-label="Acciones de la operación" className="flex min-w-0 flex-wrap items-center gap-2">
          {accesoSeguimiento}
          <AccesoGestionesClientes dia={dia} autores={ruta?.tipo === 'analista' ? [ruta.id] : grupo ? grupo.personas.flatMap(p => p.analista_id ? [p.analista_id] : []) : null} />
          <button type="button" className={BOTON_CABECERA} aria-disabled={!registroDisponible}
            onClick={(e) => { if (registroDisponible) { if (ruta) window.location.hash = hashDe('gestion-diaria'); setPestana('pulso'); abrirRegistroGeneral(e.currentTarget) } }}>
            <ClipboardList aria-hidden className="size-4" />Registro general
          </button>
          {/* «Actualizado HH:MM» ya va en el pie de la tabla: aquí restaba el sitio que deja la fila en una línea. */}
          <button type="button" className={BOTON_CABECERA} aria-disabled={consulta.enVuelo || sinPermiso} aria-busy={consulta.enVuelo} title={hora ? `Actualizado ${hora}` : undefined}
            onClick={() => { if (!consulta.enVuelo && !sinPermiso) void actualizar() }}>
            <RefreshCw aria-hidden className={cn('size-4', consulta.enVuelo && 'motion-safe:animate-spin')} />Actualizar
          </button>
          <button type="button" className={BOTON_CABECERA} aria-disabled={!datos || sinPermiso} aria-haspopup="dialog" onClick={() => { if (datos && !sinPermiso) setDialogo('comparacion') }}>
            <Columns3 aria-hidden className="size-4" />Comparar días
          </button>
          <button type="button" className={cn(BOTON_CABECERA, 'w-9 justify-center px-0 pointer-coarse:w-11')} aria-label="Definiciones" aria-haspopup="dialog"
            aria-disabled={!datos || sinPermiso} onClick={() => { if (datos && !sinPermiso) setDialogo('definiciones') }}>
            <Info aria-hidden className="size-4" />
          </button>
        </div>}
        clasePanel="flex min-h-0 flex-1 flex-col gap-4 pt-4">
        {contenido}
      </Tabs>
      {datos && !sinPermiso && <DialogoComparacion datos={datos} contenido={dialogo} cerrar={() => setDialogo(null)} />}
    </section>
  )
}

/** «Comparar días» conserva las 8 cifras con el día anterior y la referencia, y las definiciones. */
function DialogoComparacion({ datos: d, contenido, cerrar }: { datos: PulsoGerencia; contenido: 'comparacion' | 'definiciones' | null; cerrar: () => void }) {
  const celda = 'border-t border-border px-3 py-2.5 text-right tabular-nums'
  return <Dialog open={contenido !== null} onClose={cerrar} className="w-[640px]">
    <DialogHeader><DialogTitle>{contenido === 'definiciones' ? 'Fechas y definiciones' : 'Comparación de la operación'}</DialogTitle></DialogHeader>
    <DialogBody><div className="space-y-3 text-[13.5px] leading-relaxed">
      {contenido !== 'definiciones' && <>
        <p className="text-[13px] text-[var(--muted-foreground-strong)]">Día elegido: {d.dia} · Anterior: {d.ayer.dia} completo · Referencia: {d.referencia.cantidad} de 7 jornadas con actividad.</p>
        {d.dia === fechaLima(Date.parse(d.generado_en)) && <p className="text-[13px] text-[var(--muted-foreground-strong)]">Hoy en curso; referencias de jornadas completas.</p>}
        {/* La tabla de la pantalla (G3): 13 px, cabecera tenue, cifras alineadas a la derecha. */}
        {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- La región permite desplazar la comparación con el teclado. */}
        <div className={cn('ac-scroll overflow-x-auto rounded-xl border border-border', FOCO)} tabIndex={0} role="region" aria-label="Desplazar comparación de días">
          <table className="w-full min-w-[480px] border-separate border-spacing-0 text-[13px]" aria-label="Cifras del día, anterior y referencia">
            <thead className="bg-muted/70 text-[12.5px] text-[var(--muted-foreground-strong)]"><tr>
              <th scope="col" className="px-3 py-2 text-left font-semibold">Indicador</th><th scope="col" className="px-3 py-2 text-right font-semibold">Día elegido</th>
              <th scope="col" className="px-3 py-2 text-right font-semibold">Anterior</th><th scope="col" className="px-3 py-2 text-right font-semibold">Promedio / referencia</th>
            </tr></thead>
            <tbody>{METRICAS.map((m) => <tr key={m.campo}><th scope="row" className="border-t border-border px-3 py-2.5 text-left font-semibold text-primary">{m.titulo}</th>
              <td className={cn(celda, 'font-bold text-foreground')}>{cifraPulso(d.actual[m.campo], m.porcentaje)}</td><td className={celda}>{cifraPulso(d.ayer.metricas[m.campo], m.porcentaje)}</td>
              <td className={celda}>{cifraPulso(d.referencia.media[m.campo], m.porcentaje)}</td></tr>)}</tbody>
          </table>
        </div>
        <h3 className="pt-1 text-[15px] font-extrabold text-primary">Fechas y definiciones</h3>
      </>}
      <p>Personas y equipos corresponden al organigrama actual.</p>
      <p>Referencia: {d.referencia.dias.length ? d.referencia.dias.join(' · ') : `Sin jornadas con actividad desde ${d.referencia.busqueda_desde}.`}</p>
      <p>Los recuentos muestran el promedio diario. La tasa de referencia reúne contestadas y útiles de {d.referencia.dias_con_tasa} días; llamadas por lead divide las llamadas por los leads distintos de cada día sumados.</p>
      <p>Contacto = contestaron ÷ llamadas útiles (sin «número errado» ni «no es la persona»). El nivel de un equipo usa los mismos umbrales que el de cada analista.</p>
      <p>Sin registro significa sin llamadas, WhatsApp enviado, reunión realizada, nota ni conversión; no indica ausencia.</p>
      <p>Dispersión: mínimo y máximo individual con al menos {d.minimo_llamadas_utiles} llamadas útiles. Al ordenar, se compara la amplitud entre esos extremos.</p>
      <p>Los leads distintos se deduplican en toda la operación; no se suman entre equipos.</p>
      <p>Las tareas y el primer intento vencido se consultan en el momento actual, incluso al elegir un día pasado.</p>
      <button type="button" className={BOTON_CABECERA} onClick={cerrar}>{contenido === 'definiciones' ? 'Cerrar definiciones' : 'Cerrar comparación'}</button>
    </div></DialogBody>
  </Dialog>
}

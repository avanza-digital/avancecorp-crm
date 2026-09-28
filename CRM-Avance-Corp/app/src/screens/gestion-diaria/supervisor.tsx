import { useEffect, useId, useLayoutEffect, useRef, useState, type JSX, type ReactNode } from 'react'
import { ClipboardList, Info, RefreshCw, Users, X } from 'lucide-react'
import { useAlertasCRM } from '@/lib/alertas-context'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { fechaLima } from '@/lib/agenda-derivada'
import { horaLimaDe } from '@/lib/gestion-diaria-analista'
import { compararGravedad, filtrarOrdenarEquipo, presentarEquipo, type FiltrosEquipo, type OrdenEquipo, type FilaEquipoPresentada } from '@/lib/gestion-diaria-equipo'
import { useDiaEquipo } from '@/data/gestion-diaria-equipo-queries'
import { CrmApiError } from '@/data/crm-api'
import { TablaEquipoDiaria } from '@/components/gestion-diaria/tabla-equipo-diaria'
import { PanelAnalistaSupervisor, type SeleccionSupervisor } from '@/components/gestion-diaria/panel-analista-supervisor'
import { PanelSupervisorAdaptable } from '@/components/gestion-diaria/panel-supervisor-adaptable'
import { PanelVacio } from '@/components/common/estado-panel'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Dialog, DialogBody, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { FranjaCortesSupervisor } from '@/components/gestion-diaria/franja-cortes-supervisor'
import { BarraEquipo } from '@/components/gestion-diaria/barra-equipo'
import { BOTON_CABECERA, CONTROL } from '@/components/gestion-diaria/estilos-gestion'
import { AvisosEquipo } from '@/components/gestion-diaria/avisos-equipo'
import { EstadoCortesEquipo } from '@/components/gestion-diaria/estado-cortes-equipo'
import { useGestionDiariaAvisos } from '@/lib/gestion-diaria-avisos-context'
import { cn } from '@/lib/utils'
// supervisor.css sigue siendo de gerencia y de los diálogos de cortes; la
// pantalla del supervisor tiene sus estilos propios (mi-equipo.css, 27/09).
import './supervisor.css'
import './mi-equipo.css'

const FECHA_JORNADA = new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'America/Lima' })
// «Atención» por gravedad (revisión Codex, 27/09): lo vencido primero.
const FILTROS_INICIALES: FiltrosEquipo = { busqueda: '', estado: 'todos', soloProblemas: false, orden: 'atencion', ascendente: false, gravedad: true }
/**
 * Ancho mínimo de la pantalla para tener tabla y panel LADO A LADO: columnas
 * fijas de la tabla (68 + 132 + 56 + 72 + 156 = 484) + nombre con iniciales
 * (≥ 200) + rellenos y bordes (24) + canal de scroll (16) + separación (16) +
 * panel (360, su mínimo: crece hasta 440 con la pantalla) = 1100. A 1440 con el menú abierto la pantalla mide ~1150: cabe.
 * Por debajo, el detalle se abre encima como siempre. La tabla pasa a tarjetas
 * por debajo de 640 px (mi-equipo.css): nunca en línea. Solo del supervisor.
 */
const ANCHO_EN_LINEA = 1100

export function GestionDiariaSupervisor({ accesoSeguimiento }: { accesoSeguimiento?: ReactNode } = {}): JSX.Element {
  const { yo } = useAuth()
  const hoy = fechaLima(useAhora())
  if (yo?.rol !== 'supervisor') return <p role="alert">Esta vista está disponible para supervisores autorizados.</p>
  // Desmontar el propietario entero limpia selección y listas antes de pintar
  // cualquier cambio de actor, rol, demo o jornada, incluidas respuestas tardías.
  return <VistaSupervisor key={JSON.stringify([yo.id, yo.rol, yo.demo, hoy])} hoy={hoy} actor={yo.id} demo={yo.demo} accesoSeguimiento={accesoSeguimiento} />
}

function VistaSupervisor({ hoy, actor, demo, accesoSeguimiento }: { hoy: string; actor: string; demo: boolean; accesoSeguimiento?: ReactNode }) {
  const [fecha, setFecha] = useState(hoy)
  const entradaFecha = useRef<HTMLInputElement>(null)
  const consulta = useDiaEquipo(fecha)
  const esHoy = fecha === hoy
  // Mismo intervalo inclusivo que gestion_diaria_equipo_fn: 365 días Lima.
  const primeraFecha = fechaLima(Date.parse(`${hoy}T12:00:00-05:00`) - 365 * 86_400_000)
  const avisos = useGestionDiariaAvisos()
  const alertas = useAlertasCRM()
  const panelId = useId()
  const [filtros, setFiltros] = useState(FILTROS_INICIALES)
  const [seleccion, setSeleccion] = useState<SeleccionSupervisor | null>(null)
  const [anuncio, setAnuncio] = useState('')
  const [actualizacion, setActualizacion] = useState(0)
  const [ampliado, setAmpliado] = useState(false)
  const [estrecho, setEstrecho] = useState(false)
  const [auxiliar, setAuxiliar] = useState<'info' | 'avisos' | null>(null)
  const [devolverFocoAuxiliar, setDevolverFocoAuxiliar] = useState(true)
  const pantalla = useRef<HTMLElement>(null)
  const tituloEquipo = useRef<HTMLHeadingElement>(null)
  const tituloPanel = useRef<HTMLHeadingElement>(null)
  const origen = useRef<HTMLElement | null>(null)
  const focoEnPanel = useRef(false)
  const apertura = useRef(0)
  // Un cierre voluntario, una salida de ámbito o una apertura pedida por un aviso
  // apagan la selección automática en esta visita a la pantalla.
  const autoInhibida = useRef(false)
  const ahora = useAhora()
  // «Actualizando…» solo cuando lo pidió el supervisor: el refresco de cada minuto
  // no cambia el botón enfocado ni lo anuncia (revisión a11y, 27/09).
  const [manual, setManual] = useState(false)
  const [reintentando, setReintentando] = useState(false)
  const tituloError = useRef<HTMLHeadingElement>(null)
  const focoEnEquipo = useRef(false)
  const dia = consulta.error ? null : consulta.dia
  const equipo = dia ? presentarEquipo(dia) : []
  const filas = filtrarOrdenarEquipo(equipo, filtros)
  const fila = equipo.find((f) => f.analista_id === seleccion?.analista)
  const atencion = equipo.filter((f) => f.requiere_atencion).length
  const sinPermiso = consulta.error instanceof CrmApiError && consulta.error.code === '42501'
  const fueraDeAmbito = seleccion !== null && (sinPermiso || (dia !== null && seleccion.analista !== null && !fila))
  const automatica = seleccion?.origen === 'automatica'
  useLayoutEffect(() => {
    const nodo = pantalla.current
    if (!nodo || typeof ResizeObserver === 'undefined') return
    const medir = () => {
      const tabla = nodo.querySelector('.gd-tabla-scroll')
      const scrollbar = tabla instanceof HTMLElement ? tabla.offsetWidth - tabla.clientWidth : 0
      setEstrecho(nodo.clientWidth < ANCHO_EN_LINEA + Math.max(0, scrollbar - 16))
    }
    const observador = new ResizeObserver(medir)
    observador.observe(nodo)
    medir()
    return () => observador.disconnect()
  }, [])
  useEffect(() => {
    const recordarFoco = (e: FocusEvent) => {
      focoEnPanel.current = e.target instanceof Node && Boolean(document.getElementById(panelId)?.contains(e.target))
      focoEnEquipo.current = e.target instanceof Element && Boolean(e.target.closest('.me-equipo'))
    }
    document.addEventListener('focusin', recordarFoco)
    return () => document.removeEventListener('focusin', recordarFoco)
  }, [panelId])
  useLayoutEffect(() => {
    if (!fueraDeAmbito) return
    const focoDentro = focoEnPanel.current
    autoInhibida.current = true
    setSeleccion(null)
    setAmpliado(false)
    setAnuncio('Se cerró el detalle porque su ámbito ya no está autorizado. Revisa el equipo antes de abrir otro.')
    if (focoDentro) tituloEquipo.current?.focus()
  }, [fueraDeAmbito, panelId])
  useEffect(() => {
    const pedido = avisos?.registroPedido
    if (!pedido) return
    // Un aviso vigente abre su jornada; nunca usa las cifras del día consultado.
    if (pedido.actor === actor && pedido.dia === hoy && !esHoy) {
      setFecha(hoy)
      if (entradaFecha.current) entradaFecha.current.value = hoy
      setSeleccion(null)
      setAmpliado(false)
      setAuxiliar(null)
      return
    }
    if (sinPermiso) {
      setAnuncio('El registro solicitado ya no está autorizado.')
      avisos?.consumirRegistro()
      return
    }
    if (!dia) return
    if (pedido.actor === actor && pedido.dia === hoy && esHoy && dia.equipo.some((f) => f.analista_id === pedido.analista)) {
      origen.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
      autoInhibida.current = true
      setSeleccion({ analista: pedido.analista, nombre: dia.equipo.find((f) => f.analista_id === pedido.analista)!.nombre_completo,
        pestana: 'llamadas', apertura: ++apertura.current, enfocar: true, origen: 'aviso' })
      setDevolverFocoAuxiliar(false)
      setAuxiliar(null)
      setAnuncio('Abierto el registro de llamadas solicitado.')
    } else setAnuncio('El registro solicitado ya no corresponde a tu equipo o jornada actuales.')
    avisos?.consumirRegistro()
  }, [avisos, dia, hoy, fecha, esHoy, actor, sinPermiso])
  const cambiarFecha = (valor: string) => {
    if (!valor || valor < primeraFecha || valor > hoy) return
    if (entradaFecha.current && entradaFecha.current.value !== valor) entradaFecha.current.value = valor
    if (valor === fecha) return
    setFecha(valor)
    setSeleccion(null)
    setAmpliado(false)
    setAuxiliar(null)
    setAnuncio(`Fecha seleccionada: ${FECHA_JORNADA.format(new Date(`${valor}T12:00:00-05:00`))}.`)
  }
  const abrirLlamadas = (id: string) => {
    const persona = dia?.equipo.find((f) => f.analista_id === id)
    if (!persona || sinPermiso) return
    origen.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
    autoInhibida.current = true
    setSeleccion({ analista: id, nombre: persona.nombre_completo, pestana: 'llamadas', apertura: ++apertura.current, enfocar: true, origen: 'aviso' })
    setDevolverFocoAuxiliar(false); setAuxiliar(null)
    setAnuncio('Abierto el registro de llamadas solicitado.')
  }
  const seleccionar = (persona: FilaEquipoPresentada) => {
    origen.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
    // Pulsar a quien ya abrió la selección automática la hace SUYA.
    if (seleccion?.analista === persona.analista_id) {
      if (automatica) setSeleccion((s) => s && { ...s, origen: 'usuario' })
      return
    }
    setSeleccion({ analista: persona.analista_id, nombre: persona.nombre_completo, pestana: 'todo', apertura: ++apertura.current, enfocar: false, origen: 'usuario' })
    setAnuncio(`Seleccionado ${persona.nombre_completo}. Detalle disponible.`)
  }
  const cerrar = () => {
    autoInhibida.current = true
    const analista = seleccion?.analista ?? null
    setSeleccion(null); setAmpliado(false)
    requestAnimationFrame(() => {
      // Una selección automática no tiene origen: el foco vuelve a SU fila, no al título.
      const fila = analista === null ? null : pantalla.current?.querySelector<HTMLElement>(`[data-analista="${CSS.escape(analista)}"] button[aria-controls]`)
      const destino = origen.current?.isConnected && origen.current.getClientRects().length ? origen.current : fila ?? tituloEquipo.current
      destino?.focus({ preventScroll: true })
      destino?.scrollIntoView?.({ block: 'nearest' })
    })
  }
  const ordenar = (orden: OrdenEquipo) => {
    const titulo = { nombre: 'nombre', llamadas: 'llamadas', contacto: 'contacto', pendientes: 'pendientes', citas: 'citas', vencidas: 'vencidas', atencion: 'atención' }[orden]
    const ascendente = filtros.orden === orden ? !filtros.ascendente : orden === 'nombre'
    setFiltros((f) => ({ ...f, orden, ascendente }))
    setAnuncio(`Ordenado por ${titulo}, ${ascendente ? 'ascendente' : 'descendente'}.`)
  }
  // Selección AUTOMÁTICA (plan v2 tras Codex, 27/09): quien más atención
  // necesita, SOLO con el panel en línea, hoy, con una foto válida de la fecha
  // pedida y sin un aviso esperando; nunca abre una ventana ni mueve el foco.
  const candidata = filas.filter((f) => f.requiere_atencion).toSorted(compararGravedad)[0]
  useEffect(() => {
    if (autoInhibida.current || seleccion !== null || !esHoy || estrecho || !dia || dia.dia !== fecha
      || consulta.cargando || consulta.error || sinPermiso || avisos?.registroPedido || !candidata) return
    origen.current = null
    setSeleccion({ analista: candidata.analista_id, nombre: candidata.nombre_completo, pestana: 'todo', apertura: ++apertura.current, enfocar: false, origen: 'automatica' })
  }, [seleccion, esHoy, estrecho, dia, fecha, consulta.cargando, consulta.error, sinPermiso, avisos?.registroPedido, candidata])
  // Una automática que se queda sin sitio al lado se CIERRA sin abrir ventana;
  // si el supervisor ya la estaba leyendo (foco dentro), pasa a ser suya.
  useLayoutEffect(() => {
    if (!estrecho || !automatica) return
    const activo = document.activeElement
    if (activo && document.getElementById(panelId)?.contains(activo)) setSeleccion((s) => s && { ...s, origen: 'usuario' })
    else setSeleccion(null)
  }, [estrecho, automatica, panelId])
  const modal = seleccion !== null && !fueraDeAmbito && !automatica && (estrecho || ampliado)
  const vacioPanel = dia && esHoy && dia.equipo.length > 0 && !equipo.some((f) => f.requiere_atencion)
    ? 'Nadie necesita atención ahora. Elige un analista para ver su día.' : undefined
  const registroEquipoDisponible = Boolean(dia) && !consulta.error && !consulta.cargando && !sinPermiso
  const abrirRegistroEquipo = () => {
    if (!dia || sinPermiso) return
    origen.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
    setSeleccion({ analista: null, nombre: null, pestana: 'todo', apertura: ++apertura.current, enfocar: true, origen: 'usuario' })
  }
  const actualizar = () => {
    if (consulta.enVuelo || alertas.cargando) return
    setManual(true)
    void consulta.recargar(); alertas.reintentar(); setActualizacion((n) => n + 1)
  }
  const enVuelo = consulta.enVuelo || alertas.cargando
  const actualizando = manual && enVuelo
  useEffect(() => { if (!enVuelo) setManual(false) }, [enVuelo])
  // Reintento: si sale bien, el bloque de error desaparece con el foco dentro →
  // el foco va al título; si vuelve a fallar, se dice (revisión a11y, 27/09).
  useEffect(() => {
    if (!reintentando || consulta.enVuelo) return
    setReintentando(false)
    if (consulta.error) setAnuncio('El reintento no pudo consultar el equipo.')
    else requestAnimationFrame(() => {
      const activo = document.activeElement
      if (!activo || activo === document.body) tituloEquipo.current?.focus({ preventScroll: true })
    })
  }, [reintentando, consulta.enVuelo, consulta.error])
  // Si un refresco falla con el foco en la tabla o la barra, la alerta los reemplaza:
  // el foco pasa a su título en vez de caer al documento.
  useLayoutEffect(() => {
    // Solo si el foco se PERDIÓ (cayó al documento); si sigue en «Reintentar», se queda.
    const activo = document.activeElement
    if (!consulta.error || !focoEnEquipo.current || (activo && activo !== document.body)) return
    focoEnEquipo.current = false
    tituloError.current?.focus({ preventScroll: true })
  }, [consulta.error])
  const hora = dia ? horaLimaDe(dia.generado_en) : null
  return (
    <section ref={pantalla} aria-label={esHoy ? 'Mi equipo hoy' : 'Mi equipo por fecha'} data-estrecho={estrecho}
      className="me-pantalla mx-auto flex w-full max-w-[1440px] flex-col gap-4 text-foreground">
      <header className="flex shrink-0 flex-wrap items-start justify-between gap-x-6 gap-y-3">
        <div className="min-w-0">
          <h2 ref={tituloEquipo} tabIndex={-1} className="rounded-md text-[26px] font-extrabold leading-tight tracking-[-0.02em] text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">{esHoy ? 'Mi equipo hoy' : 'Mi equipo'}</h2>
          <p className="mt-1 text-[13px] text-[var(--muted-foreground-strong)]">Actividad, pendientes y atención de tu equipo.</p>
        </div>
        <div className="flex min-w-0 flex-wrap items-center gap-2">
          {/* El selector ya dice la fecha: al lado solo va la hora de la foto. */}
          <label><span className="sr-only">Fecha de gestión</span>
            <Input ref={entradaFecha} type="date" defaultValue={hoy} min={primeraFecha} max={hoy} className={cn(CONTROL, 'w-[150px] min-h-0')}
              onChange={(e) => {
                // El campo nativo conserva la escritura por segmentos. Volver a
                // asignar value en cada tecla reinicia el año en Chromium.
                if (e.currentTarget.validity.valid) cambiarFecha(e.currentTarget.value)
              }} onBlur={(e) => { e.currentTarget.value = fecha }} />
          </label>
          <button type="button" className={BOTON_CABECERA} aria-disabled={esHoy} onClick={() => { if (!esHoy) cambiarFecha(hoy) }}>Hoy</button>
          {accesoSeguimiento}
          {/* Con cualquier foto válida, aunque no haya analistas. Sin foto se
              deshabilita en vez de desmontarse: no suelta el foco (Codex, 27/09). */}
          <button type="button" className={BOTON_CABECERA} aria-disabled={!registroEquipoDisponible}
            onClick={() => { if (registroEquipoDisponible) abrirRegistroEquipo() }}>
            <ClipboardList aria-hidden className="size-4" />Registro del equipo
          </button>
          {hora && <p className="whitespace-nowrap pl-1 text-xs tabular-nums text-[var(--muted-foreground-strong)]">Actualizado {hora}</p>}
          <button type="button" className={BOTON_CABECERA} aria-disabled={actualizando} aria-busy={actualizando} onClick={actualizar}>
            <RefreshCw className={cn('size-4', actualizando && 'motion-safe:animate-spin')} aria-hidden />{actualizando ? 'Actualizando…' : 'Actualizar'}
          </button>
          <button type="button" className={cn(BOTON_CABECERA, 'w-9 justify-center px-0 pointer-coarse:w-11')} aria-label="Información de esta vista" onClick={() => { setDevolverFocoAuxiliar(true); setAuxiliar('info') }}>
            <Info aria-hidden className="size-4" />
          </button>
        </div>
      </header>

      <div className={cn('grid min-h-0 flex-1 gap-4', estrecho ? 'grid-cols-1' : 'grid-cols-[minmax(0,1fr)_clamp(360px,32%,440px)]')}>
        <div className="me-equipo flex min-h-0 min-w-0 flex-col overflow-clip rounded-2xl border border-border bg-card">
          {consulta.error ? <div role="alert" className="flex flex-col items-start gap-3 p-6 text-[13.5px]">
            <h3 ref={tituloError} tabIndex={-1} className="rounded-md text-[15px] font-extrabold text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">{sinPermiso ? 'Ya no tienes autorización para ver este equipo' : 'No pudimos consultar la actividad y los pendientes del equipo'}</h3>
            <p className="text-[var(--muted-foreground-strong)]">{sinPermiso ? 'Revisa tu acceso con gerencia. No se muestran los datos anteriores.' : 'Los datos no están disponibles; esto no significa que el equipo no tenga actividad o pendientes.'}</p>
            {!sinPermiso && <Button className={cn(CONTROL, 'aria-disabled:cursor-default aria-disabled:opacity-60')} aria-disabled={consulta.enVuelo}
              onClick={() => { if (consulta.enVuelo) return; setReintentando(true); void consulta.recargar() }}>{reintentando ? 'Reintentando…' : 'Reintentar'}</Button>}
          </div> : consulta.cargando || !dia ? <p role="status" className="p-6 text-[13.5px] text-[var(--muted-foreground-strong)]">Consultando el equipo completo…</p>
            : <>
              {dia.equipo.length > 0 && <BarraEquipo filtros={filtros} setFiltros={setFiltros} conteos={dia.resumen} atencion={atencion} />}
              {dia.equipo.length === 0
                ? <PanelVacio icono={Users} titulo="No tienes analistas activos asignados" detalle="Gerencia puede revisar la composición de tu equipo. No es un resultado de actividad cero." />
                : <>
                  <TablaEquipoDiaria filas={filas} filtros={filtros} ordenar={ordenar} seleccion={seleccion?.analista ?? null} seleccionar={seleccionar}
                    panelId={panelId} minimo={dia.umbrales.minimo_llamadas_utiles} irAlDetalle={() => { tituloPanel.current?.focus({ preventScroll: true }); tituloPanel.current?.scrollIntoView?.({ block: 'nearest' }) }} />
                  <div className="flex shrink-0 flex-wrap items-center justify-between gap-x-4 gap-y-1 border-t border-border px-4 py-2.5 text-xs text-[var(--muted-foreground-strong)]">
                    <p><span role="status">{filas.length} de {dia.resumen.analistas} analistas</span> · Actualizado {hora}</p>
                    <p>La actividad registrada no acredita presencia.</p>
                  </div>
                </>}
            </>}
        </div>
        <PanelSupervisorAdaptable modal={modal} cerrar={cerrar} tituloRef={tituloPanel} claseAlojamiento={cn('me-panel-alojamiento flex min-h-0 min-w-0 flex-col', estrecho && 'hidden')}>
          <PanelAnalistaSupervisor key={fecha} id={panelId} seleccion={fueraDeAmbito ? null : seleccion} fila={fila} dia={fecha} minimo={dia?.umbrales.minimo_llamadas_utiles} tituloRef={tituloPanel}
            ampliado={ampliado} puedeAmpliar={!estrecho} ampliar={() => { setAmpliado((v) => !v); if (automatica) setSeleccion((s) => s && { ...s, origen: 'usuario' }) }} cerrar={cerrar}
            oculta={Boolean(dia && seleccion?.analista && !filas.some((f) => f.analista_id === seleccion.analista))}
            limpiar={() => setFiltros(FILTROS_INICIALES)} actualizacion={actualizacion} revalidar={() => { void consulta.recargar() }}
            esHoy={esHoy} ahora={ahora} vacio={vacioPanel} silencioso={automatica} />
        </PanelSupervisorAdaptable>
      </div>
      {esHoy ? <FranjaCortesSupervisor consulta={consulta} abrir={() => { setDevolverFocoAuxiliar(true); setAuxiliar('avisos') }} />
        : <section className="flex shrink-0 flex-wrap items-center gap-x-4 gap-y-1 rounded-2xl border border-border bg-card px-3 py-1.5 text-[13px]" aria-label="Consulta de otra fecha">
          <button type="button" className={BOTON_CABECERA} aria-haspopup="dialog" onClick={() => { setDevolverFocoAuxiliar(true); setAuxiliar('avisos') }}>Cortes del día</button>
          <p className="min-w-0 flex-1 text-[var(--muted-foreground-strong)]">Actividad del día elegido. El equipo y los pendientes reflejan su estado actual.</p>
        </section>}
      <p className="sr-only" role="status">{anuncio}</p>
      <Dialog focoAlCerrar={devolverFocoAuxiliar ? undefined : tituloPanel} open={auxiliar !== null} onClose={() => setAuxiliar(null)} className={auxiliar === 'info' ? 'gd-dialogo-info' : 'gd-dialogo-avisos'}>
        <DialogHeader className="flex-row items-center justify-between"><DialogTitle className="text-base">{auxiliar === 'info' ? 'Información de esta vista' : esHoy ? 'Cortes de llamadas y otros avisos' : 'Cortes del día seleccionado'}</DialogTitle>
          <Button variant="ghost" size="icon" className="size-11 shrink-0" aria-label={auxiliar === 'info' ? 'Cerrar información' : 'Cerrar avisos'} onClick={() => setAuxiliar(null)}><X aria-hidden /></Button></DialogHeader>
        <DialogBody className="space-y-3 text-base">{auxiliar === 'info' ? <>
          <p>{fecha} · Hora de Lima{demo ? ' · Modo demo' : ''}. {dia ? `Datos consultados a las ${horaLimaDe(dia.generado_en)}.` : 'Sin datos confirmados.'} Actualización cada minuto.</p>
          <p>Puedes consultar desde hoy hasta 365 días atrás. Las llamadas y el registro corresponden a la fecha elegida; el equipo y los pendientes reflejan su estado actual.</p>
          <p>Los indicadores cuentan personas del equipo completo, incluso cuando filtras la tabla.</p>
          <p>La tasa usa llamadas útiles; número errado y otra persona quedan fuera. Se califica desde {dia?.umbrales.minimo_llamadas_utiles ?? 'el mínimo vigente de'} llamadas útiles.</p>
          <p>Los pendientes reflejan su estado actual. La actividad registrada no acredita presencia ni explica una ausencia. Los cortes conservan su foto de llamadas y solo avisan durante la jornada.</p>
          {dia?.modo_sla !== 'activo' && <p>Los primeros intentos fuera de plazo no se evalúan con el control actual. «No evaluado» no significa cero.</p>}
        </> : auxiliar === 'avisos' ? esHoy
          ? <AvisosEquipo consulta={consulta} abrirAnalista={abrirLlamadas} alNavegar={() => { setAuxiliar(null); setSeleccion(null); setAmpliado(false) }} />
          : <EstadoCortesEquipo consulta={consulta} abrirAnalista={abrirLlamadas} /> : null}</DialogBody>
      </Dialog>
    </section>
  )
}

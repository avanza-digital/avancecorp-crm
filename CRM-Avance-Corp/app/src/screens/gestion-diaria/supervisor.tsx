import { useEffect, useId, useLayoutEffect, useRef, useState, type JSX } from 'react'
import { Info, ListFilter, RefreshCw, Search, Users, X } from 'lucide-react'
import { useAlertasCRM } from '@/lib/alertas-context'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { fechaLima } from '@/lib/agenda-derivada'
import { horaLimaDe } from '@/lib/gestion-diaria-analista'
import { filtrarOrdenarEquipo, presentarEquipo, type FiltrosEquipo, type OrdenEquipo, type FilaEquipoPresentada, type EstadoEquipo } from '@/lib/gestion-diaria-equipo'
import { useDiaEquipo } from '@/data/gestion-diaria-equipo-queries'
import { CrmApiError } from '@/data/crm-api'
import { TablaEquipoDiaria } from '@/components/gestion-diaria/tabla-equipo-diaria'
import { PanelAnalistaSupervisor, type SeleccionSupervisor } from '@/components/gestion-diaria/panel-analista-supervisor'
import { PanelSupervisorAdaptable } from '@/components/gestion-diaria/panel-supervisor-adaptable'
import { PanelVacio } from '@/components/common/estado-panel'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Dialog, DialogBody, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { FranjaCortesSupervisor } from '@/components/gestion-diaria/franja-cortes-supervisor'
import { AvisosEquipo } from '@/components/gestion-diaria/avisos-equipo'
import { EstadoCortesEquipo } from '@/components/gestion-diaria/estado-cortes-equipo'
import { useGestionDiariaAvisos } from '@/lib/gestion-diaria-avisos-context'
import './supervisor.css'

const FECHA_JORNADA = new Intl.DateTimeFormat('es-PE', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'America/Lima' })
const FILTROS_INICIALES: FiltrosEquipo = { busqueda: '', estado: 'todos', soloProblemas: false, orden: 'atencion', ascendente: false }

export function GestionDiariaSupervisor(): JSX.Element {
  const { yo } = useAuth()
  const hoy = fechaLima(useAhora())
  if (yo?.rol !== 'supervisor') return <p role="alert">Esta vista está disponible para supervisores autorizados.</p>
  // Desmontar el propietario entero limpia selección y listas antes de pintar
  // cualquier cambio de actor, rol, demo o jornada, incluidas respuestas tardías.
  return <VistaSupervisor key={JSON.stringify([yo.id, yo.rol, yo.demo, hoy])} hoy={hoy} actor={yo.id} demo={yo.demo} />
}

function VistaSupervisor({ hoy, actor, demo }: { hoy: string; actor: string; demo: boolean }) {
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
  const dia = consulta.error ? null : consulta.dia
  const equipo = dia ? presentarEquipo(dia) : []
  const filas = filtrarOrdenarEquipo(equipo, filtros)
  const fila = equipo.find((f) => f.analista_id === seleccion?.analista)
  const atencion = equipo.filter((f) => f.requiere_atencion).length
  const sinPermiso = consulta.error instanceof CrmApiError && consulta.error.code === '42501'
  const fueraDeAmbito = seleccion !== null && (sinPermiso || (dia !== null && seleccion.analista !== null && !fila))
  useLayoutEffect(() => {
    const nodo = pantalla.current
    if (!nodo || typeof ResizeObserver === 'undefined') return
    const medir = () => {
      const tabla = nodo.querySelector('.gd-tabla-scroll')
      const scrollbar = tabla instanceof HTMLElement ? tabla.offsetWidth - tabla.clientWidth : 0
      setEstrecho(nodo.clientWidth < 1236 + Math.max(0, scrollbar - 16))
    }
    const observador = new ResizeObserver(medir)
    observador.observe(nodo)
    medir()
    return () => observador.disconnect()
  }, [])
  useEffect(() => {
    const recordarFoco = (e: FocusEvent) => {
      focoEnPanel.current = e.target instanceof Node && Boolean(document.getElementById(panelId)?.contains(e.target))
    }
    document.addEventListener('focusin', recordarFoco)
    return () => document.removeEventListener('focusin', recordarFoco)
  }, [panelId])
  useLayoutEffect(() => {
    if (!fueraDeAmbito) return
    const focoDentro = focoEnPanel.current
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
      setSeleccion({ analista: pedido.analista, nombre: dia.equipo.find((f) => f.analista_id === pedido.analista)!.nombre_completo,
        pestana: 'llamadas', apertura: ++apertura.current, enfocar: true })
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
    setSeleccion({ analista: id, nombre: persona.nombre_completo, pestana: 'llamadas', apertura: ++apertura.current, enfocar: true })
    setDevolverFocoAuxiliar(false); setAuxiliar(null)
    setAnuncio('Abierto el registro de llamadas solicitado.')
  }
  const seleccionar = (persona: FilaEquipoPresentada) => {
    origen.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
    if (seleccion?.analista === persona.analista_id) return
    setSeleccion({ analista: persona.analista_id, nombre: persona.nombre_completo, pestana: 'todo', apertura: ++apertura.current, enfocar: false })
    setAnuncio(`Seleccionado ${persona.nombre_completo}. Detalle disponible.`)
  }
  const cerrar = () => {
    setSeleccion(null); setAmpliado(false)
    requestAnimationFrame(() => {
      if (origen.current?.isConnected && origen.current.getClientRects().length) origen.current.focus({ preventScroll: true })
      else tituloEquipo.current?.focus({ preventScroll: true })
    })
  }
  const ordenar = (orden: OrdenEquipo) => setFiltros((f) => ({ ...f, orden, ascendente: f.orden === orden ? !f.ascendente : orden === 'nombre' }))
  const modal = seleccion !== null && !fueraDeAmbito && (estrecho || ampliado)
  return (
    <section ref={pantalla} aria-label={esHoy ? 'Mi equipo hoy' : 'Mi equipo por fecha'} className="gd-supervisor" data-estrecho={estrecho}>
      <header className="gd-cabecera">
        <h2 ref={tituloEquipo} tabIndex={-1}>{esHoy ? 'Mi equipo hoy' : 'Mi equipo'}</h2>
        <div className="gd-selector-fecha">
          <label><span className="sr-only">Fecha de gestión</span>
            <Input ref={entradaFecha} type="date" defaultValue={hoy} min={primeraFecha} max={hoy} className="min-h-11 text-base"
              onChange={(e) => {
                // El campo nativo conserva la escritura por segmentos. Volver a
                // asignar value en cada tecla reinicia el año en Chromium.
                if (e.currentTarget.validity.valid) cambiarFecha(e.currentTarget.value)
              }} onBlur={(e) => { e.currentTarget.value = fecha }} />
          </label>
          <Button variant="outline" className="min-h-11 text-base" disabled={esHoy} onClick={() => cambiarFecha(hoy)}>Hoy</Button>
          <span className="gd-fecha">Lima{demo ? ' · Demo' : ''}</span>
        </div>
        <div className="gd-acciones-cabecera">
          <Button variant="ghost" className="min-h-11 text-base" disabled={!dia || sinPermiso} onClick={() => {
            origen.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
            setSeleccion({ analista: null, nombre: null, pestana: 'todo', apertura: ++apertura.current, enfocar: true })
          }}>Registro del equipo</Button>
          <Button variant="outline" className="min-h-11 text-base" disabled={consulta.enVuelo || alertas.cargando} onClick={() => { void consulta.recargar(); alertas.reintentar(); setActualizacion((n) => n + 1) }}>
            <RefreshCw className="size-4" aria-hidden />{consulta.enVuelo || alertas.cargando ? 'Actualizando…' : 'Actualizar'}
          </Button>
          <Button variant="ghost" size="icon" className="size-11" aria-label="Información de esta vista" onClick={() => { setDevolverFocoAuxiliar(true); setAuxiliar('info') }}><Info aria-hidden /></Button>
        </div>
      </header>
      <div role="group" aria-label="Resumen del equipo" className="gd-indicadores">
        {dia ? <dl>{[
          ['Analistas', dia.resumen.analistas], ['Con registro', dia.resumen.con_actividad], ['Sin registro', dia.resumen.sin_actividad],
          ['Con pendientes', dia.resumen.con_pendientes], ['Necesitan atención', atencion],
        ].map(([etiqueta, valor]) => <div key={etiqueta}><dt>{etiqueta}</dt><dd>{valor}</dd></div>)}</dl>
          : <p>{consulta.error ? 'Resumen no disponible' : 'Consultando indicadores…'}</p>}
      </div>
      <div className="gd-espacio">
        <div className="gd-equipo">
          {consulta.error ? <div role="alert" className="gd-estado">
            <h3 className="font-semibold">{sinPermiso ? 'Ya no tienes autorización para ver este equipo' : 'No pudimos consultar la actividad y los pendientes del equipo'}</h3>
            <p>{sinPermiso ? 'Revisa tu acceso con gerencia. No se muestran los datos anteriores.' : 'Los datos no están disponibles; esto no significa que el equipo no tenga actividad o pendientes.'}</p>
            {!sinPermiso && <Button className="min-h-11 text-base" disabled={consulta.enVuelo} onClick={() => { void consulta.recargar() }}>Reintentar</Button>}
          </div> : consulta.cargando || !dia ? <p role="status" aria-busy="true" className="gd-estado">Consultando el equipo completo…</p>
            : dia.equipo.length === 0 ? <PanelVacio icono={Users} tamano="grande" titulo="No tienes analistas activos asignados" detalle="Gerencia puede revisar la composición de tu equipo. No es un resultado de actividad cero." />
              : <>
                <div className="gd-filtros">
                  <label className="gd-busqueda"><span className="sr-only">Buscar analista</span><Search aria-hidden />
                    <Input type="search" value={filtros.busqueda} onChange={(e) => setFiltros((f) => ({ ...f, busqueda: e.target.value }))} placeholder="Buscar analista" className="min-h-11 pl-9 text-base" /></label>
                  <Select aria-label="Estado de actividad" value={filtros.estado} onChange={(e) => setFiltros((f) => ({ ...f, estado: e.target.value as EstadoEquipo }))} className="min-h-11 text-base">
                    <option value="todos">Todos</option><option value="con_registro">Con registro</option><option value="sin_registro">Sin registro</option><option value="con_pendientes">Con pendientes</option>
                  </Select>
                  <Button variant={filtros.soloProblemas ? 'default' : 'outline'} className="min-h-11 text-base" aria-pressed={filtros.soloProblemas} onClick={() => setFiltros((f) => ({ ...f, soloProblemas: !f.soloProblemas }))}><ListFilter aria-hidden />Con atención ({atencion})</Button>
                  <p aria-live="polite" className="gd-conteo">{filas.length} de {dia.resumen.analistas}</p>
                </div>
                <TablaEquipoDiaria filas={filas} filtros={filtros} ordenar={ordenar} seleccion={seleccion?.analista ?? null} seleccionar={seleccionar}
                  panelId={panelId} minimo={dia.umbrales.minimo_llamadas_utiles} irAlDetalle={() => tituloPanel.current?.focus({ preventScroll: true })} />
              </>}
        </div>
        <PanelSupervisorAdaptable modal={modal} cerrar={cerrar} tituloRef={tituloPanel}>
          <PanelAnalistaSupervisor key={fecha} id={panelId} seleccion={fueraDeAmbito ? null : seleccion} fila={fila} dia={fecha} minimo={dia?.umbrales.minimo_llamadas_utiles} tituloRef={tituloPanel}
            ampliado={ampliado} puedeAmpliar={!estrecho} ampliar={() => setAmpliado((v) => !v)} cerrar={cerrar} oculta={Boolean(dia && seleccion?.analista && !filas.some((f) => f.analista_id === seleccion.analista))}
            limpiar={() => setFiltros(FILTROS_INICIALES)} actualizacion={actualizacion} revalidar={() => { void consulta.recargar() }} />
        </PanelSupervisorAdaptable>
      </div>
      {esHoy ? <FranjaCortesSupervisor consulta={consulta} abrir={() => { setDevolverFocoAuxiliar(true); setAuxiliar('avisos') }} />
        : <section className="gd-cortes" aria-label="Consulta de otra fecha">
          <Button variant="ghost" className="min-h-11 shrink-0 text-base" aria-haspopup="dialog" onClick={() => { setDevolverFocoAuxiliar(true); setAuxiliar('avisos') }}>Cortes del día</Button>
          <p className="gd-cortes-resumen">Actividad del día elegido. El equipo y los pendientes reflejan su estado actual.</p>
        </section>}
      <p className="sr-only" role="status">{anuncio}</p>
      <Dialog focoAlCerrar={devolverFocoAuxiliar ? undefined : tituloPanel} open={auxiliar !== null} onClose={() => setAuxiliar(null)} className={auxiliar === 'info' ? 'gd-dialogo-info' : 'gd-dialogo-avisos'}>
        <DialogHeader className="flex-row items-center justify-between"><DialogTitle className="text-base">{auxiliar === 'info' ? 'Información de esta vista' : esHoy ? 'Cortes de llamadas y otros avisos' : 'Cortes del día seleccionado'}</DialogTitle>
          <Button variant="ghost" size="icon" className="size-11 shrink-0" aria-label={auxiliar === 'info' ? 'Cerrar información' : 'Cerrar avisos'} onClick={() => setAuxiliar(null)}><X aria-hidden /></Button></DialogHeader>
        <DialogBody className="space-y-3 text-base">{auxiliar === 'info' ? <>
          <p>{fecha} · Hora de Lima. {dia ? `Datos consultados a las ${horaLimaDe(dia.generado_en)}.` : 'Sin datos confirmados.'} Actualización cada minuto.</p>
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

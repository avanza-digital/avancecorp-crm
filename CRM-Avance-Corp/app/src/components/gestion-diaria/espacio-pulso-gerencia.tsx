import { useEffect, useId, useRef, useState, type RefObject, type MouseEvent } from 'react'
import { ArrowLeft, ListFilter, Search } from 'lucide-react'
import { type PulsoGerencia, type EquipoPulso, cifraPulso } from '@/lib/gestion-diaria-pulso'
import { filtrarOrdenarEquipo, presentarEquipo, type FiltrosEquipo } from '@/lib/gestion-diaria-equipo'
import { hashDe } from '@/lib/router'
import type { useDetallePulso } from '@/data/gestion-diaria-pulso-queries'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Tabs } from '@/components/ui/tabs'
import { PanelCargando } from '@/components/common/estado-panel'
import { TablaEquipoDiaria } from './tabla-equipo-diaria'
import { DetalleAnalista } from './detalle-analista'
import { RegistroActividad } from './registro-actividad'
import { PanelGerencia } from './panel-gerencia'
import { ComparacionEquiposGerencia } from './comparacion-equipos-gerencia'
import { ErrorConsultaGerencia } from './error-consulta-gerencia'

type Ruta = { tipo: 'equipo' | 'analista'; id: string } | undefined
type Consulta = ReturnType<typeof useDetallePulso>
const FILTROS: FiltrosEquipo = { busqueda: '', soloProblemas: false, orden: 'atencion', ascendente: false }
const PESTANAS = [{ valor: 'resumen', etiqueta: 'Resumen' }, { valor: 'registro', etiqueta: 'Registro' }] as const
const rutaEquipo = (grupo: EquipoPulso) => hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'equipo', id: grupo.clave })
const navegarEnVentana = (e: MouseEvent<HTMLAnchorElement>) => !e.ctrlKey && !e.metaKey && !e.shiftKey && !e.altKey

/** La tabla conserva su estado al cambiar de analista y al abrir la ficha de un lead. */
export function EspacioPulsoGerencia({ datos, ruta, consulta, actualizacion, estrecho, general, cerrarGeneral, abrirGeneral, rutaEnfocada, oculto, setOculto, origenGeneral, sinPermiso }: {
  datos: PulsoGerencia; ruta: Ruta; consulta: Consulta; actualizacion: number; estrecho: boolean
  general: boolean; cerrarGeneral: () => void; abrirGeneral: () => void
  rutaEnfocada: RefObject<string | null>
  oculto: string | null; setOculto: (clave: string | null) => void
  origenGeneral: RefObject<HTMLButtonElement | null>
  sinPermiso: () => void
}) {
  const grupo = datos.equipos.find((e) => ruta?.tipo === 'equipo' ? e.clave === ruta.id : e.personas.some((p) => p.analista_id === ruta?.id))
  const persona = ruta?.tipo === 'analista' ? grupo?.personas.find((p) => p.analista_id === ruta.id) : null
  const [filtrosPorEquipo, setFiltrosPorEquipo] = useState<Record<string, FiltrosEquipo>>({})
  const filtros = grupo ? filtrosPorEquipo[grupo.clave] ?? FILTROS : FILTROS
  const cambiarFiltros = (cambio: (actual: FiltrosEquipo) => FiltrosEquipo) => {
    if (grupo) setFiltrosPorEquipo((todos) => ({ ...todos, [grupo.clave]: cambio(todos[grupo.clave] ?? FILTROS) }))
  }
  const [ampliado, setAmpliado] = useState(false)
  const [generalVisitado, setGeneralVisitado] = useState(general)
  if (general && !generalVisitado) setGeneralVisitado(true)
  const titulo = useRef<HTMLHeadingElement>(null)
  const tituloTabla = useRef<HTMLHeadingElement>(null)
  const origen = useRef<HTMLElement | null>(null)
  const clave = ruta ? `${ruta.tipo}:${ruta.id}` : null
  const abierto = general || Boolean(ruta && oculto !== clave)
  const anchoAnterior = useRef(estrecho)
  const id = useId()
  useEffect(() => {
    const ampliarDesdeMovil = anchoAnterior.current && !estrecho
    anchoAnterior.current = estrecho
    if (ampliarDesdeMovil && ruta?.tipo === 'equipo' && oculto === clave) setOculto(null)
  }, [estrecho, ruta?.tipo, oculto, clave, setOculto])
  useEffect(() => {
    if (clave && clave !== rutaEnfocada.current && abierto) titulo.current?.focus({ preventScroll: true })
    rutaEnfocada.current = clave
  }, [clave, abierto, rutaEnfocada])
  useEffect(() => { if (general) titulo.current?.focus({ preventScroll: true }) }, [general])
  const recordarOrigen = (control?: HTMLElement | null) => {
    const activo = control ?? document.activeElement
    origen.current = activo instanceof HTMLElement && activo !== document.body ? activo : null
  }
  const devolverFoco = (registroGeneral: boolean) => requestAnimationFrame(() => {
    // Una interacción posterior tiene prioridad sobre el retorno pendiente.
    const activo = document.activeElement
    if (activo instanceof HTMLElement && activo !== document.body && activo.matches('input,select,textarea')) return
    const destino = registroGeneral ? origenGeneral.current : origen.current?.isConnected ? origen.current : tituloTabla.current
    destino?.focus({ preventScroll: true })
    if (document.activeElement !== destino) tituloTabla.current?.focus({ preventScroll: true })
  })
  const cerrar = () => {
    setAmpliado(false)
    if (general) cerrarGeneral()
    else if (ruta?.tipo === 'analista' && grupo) { setOculto(`equipo:${grupo.clave}`); window.location.hash = rutaEquipo(grupo) }
    else setOculto(clave)
    devolverFoco(general)
  }
  const abrirEquipo = (e: EquipoPulso, control?: HTMLElement) => {
    recordarOrigen(control); cerrarGeneral(); setAmpliado(false)
    setOculto(estrecho ? `equipo:${e.clave}` : null)
    rutaEnfocada.current = `equipo:${e.clave}`
    window.location.hash = rutaEquipo(e)
    requestAnimationFrame(() => tituloTabla.current?.focus({ preventScroll: true }))
  }
  const volverOperacion = (e: MouseEvent<HTMLAnchorElement>) => {
    if (!navegarEnVentana(e)) return
    e.preventDefault(); cerrarGeneral(); setOculto(null); setAmpliado(false)
    window.location.hash = hashDe('gestion-diaria')
    requestAnimationFrame(() => tituloTabla.current?.focus({ preventScroll: true }))
  }
  const abrirAnalista = (analista: string, control?: HTMLElement) => {
    const fila = Array.from(tituloTabla.current?.closest('section')?.querySelectorAll<HTMLElement>('tr[data-analista]') ?? []).find((n) => n.dataset.analista === analista)
    recordarOrigen(control ?? fila?.querySelector<HTMLElement>('button')); cerrarGeneral(); setOculto(null)
    rutaEnfocada.current = `analista:${analista}`
    window.location.hash = hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'analista', id: analista })
  }
  const filas = consulta.datos && grupo ? presentarEquipo(consulta.datos).filter((f) => grupo.personas.some((p) => p.analista_id === f.analista_id)) : []
  const mostradas = filtrarOrdenarEquipo(filas, filtros)
  const nombre = persona ? persona.nombre_completo ?? 'Autor no disponible' : grupo?.nombre ?? 'Detalle no disponible'
  return <div className="gd-espacio gp-espacio" data-estrecho={estrecho}>
    <section className="gd-equipo" aria-label={grupo ? 'Analistas del equipo' : 'Equipos de la operación'}>
      <div className="gp-tabla-cabecera">
        <div>{grupo && <a className="gp-volver" href={hashDe('gestion-diaria')} onClick={volverOperacion}><ArrowLeft aria-hidden />Toda la operación</a>}
          <h3 ref={tituloTabla} tabIndex={-1}>{grupo?.nombre ?? 'Equipos y atención actual'}</h3></div>
        {grupo && <Button variant="outline" className="min-h-11 text-base" onClick={() => { recordarOrigen(); cerrarGeneral(); setOculto(null); titulo.current?.focus() }}>Ver detalle</Button>}
      </div>
      <div className="gp-comparacion" hidden={Boolean(grupo)} inert={Boolean(grupo)}><ComparacionEquiposGerencia equipos={datos.equipos} abrir={abrirEquipo} /></div>
      {grupo && <>
        <div className="gd-filtros gp-filtros">
          <div className="gd-busqueda"><Search aria-hidden /><Input type="search" aria-label="Buscar analista del equipo" placeholder="Buscar analista" className="min-h-11 pl-9 text-base" value={filtros.busqueda} onChange={(e) => cambiarFiltros((f) => ({ ...f, busqueda: e.target.value }))} /></div>
          <Button variant={filtros.soloProblemas ? 'default' : 'outline'} className="min-h-11 text-base" aria-pressed={filtros.soloProblemas} onClick={() => cambiarFiltros((f) => ({ ...f, soloProblemas: !f.soloProblemas }))}><ListFilter aria-hidden />Con atención ({filas.filter((f) => f.requiere_atencion).length})</Button>
          <span className="gd-conteo">{mostradas.length} de {filas.length} analistas</span>
        </div>
        {consulta.error ? <ErrorConsultaGerencia error={consulta.error} recargar={consulta.recargar} enVuelo={consulta.enVuelo} /> : consulta.cargando ? <PanelCargando /> : <>
          {persona?.activo && !mostradas.some((f) => f.analista_id === persona.analista_id) && <p className="gd-seleccion-oculta">La selección no aparece con los filtros actuales.</p>}
          <TablaEquipoDiaria filas={mostradas} filtros={filtros} ordenar={(orden) => cambiarFiltros((f) => ({ ...f, orden, ascendente: f.orden === orden ? !f.ascendente : true }))}
            seleccion={persona?.analista_id ?? null} seleccionar={(f) => abrirAnalista(f.analista_id)} panelId={id} irAlDetalle={() => { setOculto(null); titulo.current?.focus() }} minimo={datos.minimo_llamadas_utiles} />
          {grupo.personas.some((p) => !p.activo) && <div className="gp-otros-autores"><h4>Otros autores de los registros</h4><ul>{grupo.personas.filter((p) => !p.activo).map((p) => <li key={p.analista_id ?? 'sin-autor'}>{p.analista_id
            ? <button type="button" onClick={(e) => abrirAnalista(p.analista_id!, e.currentTarget)}>{p.nombre_completo ?? 'Autor no disponible'}</button> : 'Sin autor'}: {p.llamadas} llamadas · {p.citas_agendadas} citas agendadas</li>)}</ul>
            {grupo.personas.some((p) => p.analista_id === null) && <Button variant="outline" className="min-h-11 text-base" onClick={abrirGeneral}>Ver registros sin autor en el registro general</Button>}
          </div>}
        </>}
      </>}
    </section>
    <PanelGerencia id={id} titulo={general ? 'Registro general del día' : ruta ? nombre : 'Detalle de la operación'} abierto={abierto} estrecho={estrecho} ampliado={ampliado}
      ampliar={() => setAmpliado((v) => !v)} cerrar={cerrar} tituloRef={titulo} vacio="Elige un equipo para comparar a sus analistas y consultar sus registros.">
      {generalVisitado && <section className="gd-panel-cuerpo gp-registro" hidden={!general} inert={!general} aria-label="Registro general de la operación">
        <RegistroActividad dia={datos.dia} analistaIds={null} mostrarAnalista permitirEquipo permitirExportar pestanaInicial="todo" actualizacion={actualizacion} onSinPermiso={sinPermiso} />
      </section>}
      {ruta && <div className="gp-detalle-contenido" hidden={general} inert={general}>
        <nav aria-label="Ruta de la operación" className="gp-ruta"><a href={hashDe('gestion-diaria')} onClick={volverOperacion}>Toda la operación</a>{ruta.tipo === 'analista' && grupo && <a href={rutaEquipo(grupo)} onClick={(e) => { if (navegarEnVentana(e)) { e.preventDefault(); abrirEquipo(grupo, e.currentTarget) } }}>{grupo.nombre}</a>}</nav>
        <DetallePulsoGerencia key={`${ruta.tipo}:${ruta.id}`} datos={datos} grupo={grupo} seleccion={ruta} consulta={consulta} actualizacion={actualizacion} abrirGeneral={abrirGeneral} sinPermiso={sinPermiso} />
      </div>}
    </PanelGerencia>
  </div>
}

function DetallePulsoGerencia({ datos, grupo, seleccion, consulta, actualizacion, abrirGeneral, sinPermiso }: {
  datos: PulsoGerencia; grupo: EquipoPulso | undefined; seleccion: NonNullable<Ruta>; consulta: Consulta; actualizacion: number; abrirGeneral: () => void; sinPermiso: () => void
}) {
  const persona = seleccion.tipo === 'analista' ? grupo?.personas.find((p) => p.analista_id === seleccion.id) : null
  const personas = seleccion.tipo === 'equipo' ? grupo?.personas ?? [] : persona ? [persona] : []
  const ids = personas.flatMap((p) => p.analista_id === null ? [] : [p.analista_id])
  const fila = consulta.datos && persona ? presentarEquipo(consulta.datos).find((f) => f.analista_id === persona.analista_id) : undefined
  const [pestana, setPestana] = useState<'resumen' | 'registro'>('resumen')
  const [registroVisitado, setRegistroVisitado] = useState(false)
  const abrirRegistro = () => { setPestana('registro'); setRegistroVisitado(true) }
  if (!grupo || (seleccion.tipo === 'analista' && !persona)) return <p role="status" className="gd-panel-cuerpo">Este equipo o autor ya no aparece en el ámbito actual. Vuelve a toda la operación.</p>
  if (consulta.error) return <ErrorConsultaGerencia error={consulta.error} recargar={consulta.recargar} enVuelo={consulta.enVuelo} />
  if (consulta.cargando) return <PanelCargando />
  return <Tabs etiqueta="Detalle gerencial" className="gd-pestanas-panel" tamano="grande" pestanas={PESTANAS} valor={pestana} onCambio={(v) => { setPestana(v); if (v === 'registro') setRegistroVisitado(true) }}>
    <div className="gd-panel-cuerpo" hidden={pestana !== 'resumen'} inert={pestana !== 'resumen'}>
      {seleccion.tipo === 'equipo' && <>
        <p>{grupo.metricas.analistas_activos} analistas activos · {datos.dia}</p>
        <dl className="gd-metricas-detalle">{[
          ['Llamadas', grupo.metricas.llamadas], ['Contacto', cifraPulso(grupo.metricas.tasa_contacto, true)],
          ['Llamadas útiles', grupo.metricas.utiles], ['Contestadas', grupo.metricas.contestadas],
          ['Sin actividad', grupo.metricas.sin_actividad], ['Leads distintos', grupo.metricas.leads_unicos],
          ['Llamadas por lead', cifraPulso(grupo.metricas.llamadas_por_lead)], ['Citas agendadas', grupo.metricas.citas_agendadas],
          ['Tareas vencidas actuales', grupo.tareas_vencidas], ['Primer intento vencido', grupo.primer_intento_vencido ?? 'SLA no activo'],
        ].map(([etiqueta, valor]) => <div key={etiqueta}><dt>{etiqueta}</dt><dd className="font-semibold">{valor}</dd></div>)}</dl>
        <Button variant="outline" className="min-h-11 text-base" onClick={abrirRegistro}>Ver registro del equipo</Button>
      </>}
      {persona && <>
        <p className="gd-resumen-principal"><strong>{persona.llamadas}</strong> llamadas del día</p>
        {fila && <DetalleAnalista fila={fila} dia={datos.dia} abrirLlamadas={abrirRegistro} />}
        {!persona.activo && <p>Autor fuera del organigrama comercial activo: {persona.llamadas} llamadas, {persona.utiles} útiles, {persona.contestadas} contestadas.</p>}
        {persona.activo && !fila && <p role="status">El analista ya no aparece en la consulta actual del equipo. Actualiza la operación para confirmar su ámbito.</p>}
      </>}
      {personas.some((p) => p.analista_id === null) && <p className="mt-4">Los registros sin autor se consultan en el <button type="button" className="gp-enlace" onClick={abrirGeneral}>registro general del día</button>.</p>}
    </div>
    {registroVisitado && <div className="gd-panel-cuerpo gp-registro" hidden={pestana !== 'registro'} inert={pestana !== 'registro'}>
      {ids.length ? <RegistroActividad dia={datos.dia} analistaIds={ids} mostrarAnalista permitirExportar pestanaInicial="llamadas" actualizacion={actualizacion} onSinPermiso={sinPermiso} />
        : <p>Consulta estos registros desde el <button type="button" className="gp-enlace" onClick={abrirGeneral}>registro general del día</button>.</p>}
    </div>}
  </Tabs>
}

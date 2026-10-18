import { useEffect, useId, useRef, useState, type ReactNode } from 'react'
import { ArrowUpRight, CalendarCheck, ChevronRight, CircleCheck, Inbox, Phone, RefreshCw, X } from 'lucide-react'
import { Avatar } from '@/components/ui/avatar'
import { Button } from '@/components/ui/button'
import { Dialog, DialogBody, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Tabs } from '@/components/ui/tabs'
import { CoberturaCapitalAviso } from '@/components/common/cobertura-capital'
import { PanelAnalistaSupervisor, type SeleccionSupervisor } from '@/components/gestion-diaria/panel-analista-supervisor'
import { PendientesSupervisor } from '@/components/gestion-diaria/pendientes-supervisor'
import { useDiaEquipo } from '@/data/gestion-diaria-equipo-queries'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { fechaLima } from '@/lib/agenda-derivada'
import type { CapitalUnificado } from '@/lib/capital-unificado'
import { filtrarOrdenarEquipo, MOTIVOS_EQUIPO, presentarEquipo, PRIORIDAD_MOTIVO, type FilaEquipoPresentada } from '@/lib/gestion-diaria-equipo'
import { money, numero, porcentajeConversionCanonica } from '@/lib/format'
import { hashDe } from '@/lib/router'
import { useDatosSupervisor } from './datos-supervisor'
import { useDatosCitasGerencia } from './use-datos-citas-gerencia'
import { useResultadosHoy } from './use-resultados-hoy'
import { TasasAutorizadasAnalistaPanel } from './tasas-autorizadas-analista'
import { avanceCapital, capitalComparable, filasMensualesJornada, operacionesConfirmadas, resumirCitasHoy, resumirJornada } from './jornada-supervisor'
import './supervisor-jornada.css'

const FECHA = new Intl.DateTimeFormat('es-PE', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'America/Lima' })
const MES = new Intl.DateTimeFormat('es-PE', { month: 'long', year: 'numeric', timeZone: 'America/Lima' })
const cifra = (n: number | null | undefined) => n == null ? '—' : numero(n)
const tasa = (n: number | null | undefined) => n == null ? '—' : porcentajeConversionCanonica(n)
const SIN_CAPITAL: CapitalUnificado = { pen: null, usd: null, total: null, tc: null, estado: 'indisponible' }
const ETIQUETA_ATENCION: Record<keyof typeof MOTIVOS_EQUIPO, string> = {
  tarea_vencida: 'Tareas vencidas',
  primer_intento_vencido: 'Primer intento tarde',
  datos_incompletos: 'Datos por revisar',
  sin_llamar_2h: 'Más de 2 h sin llamar',
  corte_manana: 'Corte de mañana pendiente',
  corte_tarde: 'Corte de tarde pendiente',
}

/** La portada comercial es la misma en demo, seguimiento activo y legado.
 * Cada lector conserva su autorización y disponibilidad; ningún modo inventa cifras. */
export function HoySupervisorJornada() {
  const { yo } = useAuth()
  const hoy = fechaLima(useAhora())
  if (yo?.rol !== 'supervisor') return <p role="alert">Esta vista está disponible para supervisores autorizados.</p>
  return <JornadaSupervisor key={`${yo.id}|${yo.demo}|${hoy}`} actor={yo.id} hoy={hoy} />
}

function Importe({ capital }: { capital: CapitalUnificado }) {
  if (capital.total === null) return <>—</>
  if (!capitalComparable(capital)) return <>{money(capital.pen!, 'PEN')}<small className="sj-moneda">+ {money(capital.usd!, 'USD')} · sin convertir</small></>
  return <>{money(capital.total, 'PEN')}</>
}

function ErrorFuente({ error, cargando, reintentar, nombre }: { error: boolean; cargando?: boolean; reintentar: () => void; nombre: string }) {
  if (error) return <p role="alert" className="sj-error">{nombre} no disponible. <button type="button" onClick={reintentar}>Reintentar</button></p>
  if (cargando) return <p role="status" className="sj-nota">Consultando {nombre.toLocaleLowerCase('es')}…</p>
  return null
}

function Frente({ icono, titulo, children, accion }: { icono: ReactNode; titulo: string; children: ReactNode; accion: ReactNode }) {
  return <section className="sj-frente" aria-label={titulo}>
    <header><span className="sj-paso" aria-hidden="true">{icono}</span><h2>{titulo}</h2></header>
    <div className="sj-frente-cuerpo">{children}</div><div className="sj-frente-accion">{accion}</div>
  </section>
}

function TablaDesplazable({ nombre, children }: { nombre: string; children: ReactNode }) {
  // La región debe recibir foco para desplazar las columnas con teclado, también en Safari.
  // oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex
  return <div className="sj-tabla-scroll" role="region" aria-label={nombre} tabIndex={0}>{children}</div>
}

function JornadaSupervisor({ actor, hoy }: { actor: string; hoy: string }) {
  const datos = useDatosSupervisor({ conConsultaOperativa: false, actualizarEnVivo: true })
  const consultaDia = useDiaEquipo(hoy)
  const citas = useDatosCitasGerencia(hoy.slice(0, 7))
  const cierres = useResultadosHoy(hoy)
  const resultados = cierres.resultados
  const dia = consultaDia.error ? null : consultaDia.dia
  const equipo = dia ? presentarEquipo(dia) : []
  const jornada = resumirJornada(dia)
  // El hook de Citas puede conservar data al fallar un refresco. No publicarla.
  const errorCitas = datos.sesionReal && Boolean(citas.consulta.error)
  const citasHoy = resumirCitasHoy(errorCitas || !citas.datos ? null : citas.citas, hoy)
  const resumen = datos.resumenOp.error ? null : datos.resumen
  const porRepartir = resumen?.totales.parkeados ?? null
  const estadoMeta = datos.fotoMensualStoreCargando ? 'Meta por confirmar' : datos.objetivosMensualesError ? 'Meta no disponible' : null
  const cumplimiento = datos.cumplimientoMensualError ? null : datos.cumplimientoMensual
  const capital = datos.cumplimientoMensualError ? SIN_CAPITAL : datos.capitalConfirmado
  const meta = datos.objetivosMensualesError ? SIN_CAPITAL : datos.metaCapital
  const avance = avanceCapital(capital, meta)
  const operaciones = operacionesConfirmadas(cumplimiento?.supervisor ?? null)
  const mes = MES.format(new Date(`${hoy}T12:00:00-05:00`))
  const [vista, setVista] = useState<'dia' | 'mes'>('dia')
  const [busqueda, setBusqueda] = useState('')
  const [soloApoyo, setSoloApoyo] = useState(false)
  const [seleccion, setSeleccion] = useState<SeleccionSupervisor | null>(null)
  const [tasasAbiertas, setTasasAbiertas] = useState(false)
  const [resultadosAbiertos, setResultadosAbiertos] = useState(false)
  const [tareasAbiertas, setTareasAbiertas] = useState(false)
  const [tareasAnalista, setTareasAnalista] = useState<{ id: string; vencidas: boolean } | null>(null)
  const [actualizando, setActualizando] = useState(false)
  const [actualizacion, setActualizacion] = useState(0)
  const tituloEquipo = useRef<HTMLHeadingElement>(null)
  const tituloPanel = useRef<HTMLHeadingElement>(null)
  const origenPanel = useRef<HTMLElement | null>(null)
  const origenResultados = useRef<HTMLElement | null>(null)
  const origenTareas = useRef<HTMLElement | null>(null)
  const tituloTareas = useRef<HTMLHeadingElement>(null)
  const idEquipo = useId()
  const idPanel = useId()
  const filaSeleccionada = equipo.find(f => f.analista_id === seleccion?.analista)
  const seleccionVigente = dia && (seleccion?.analista === null || filaSeleccionada) ? seleccion : null
  const filaTareas = equipo.find(f => f.analista_id === tareasAnalista?.id)
  useEffect(() => {
    if (seleccion && !seleccionVigente) { origenPanel.current = tituloEquipo.current; setSeleccion(null) }
  }, [seleccion, seleccionVigente])
  useEffect(() => {
    if (resultadosAbiertos && !resultados) origenResultados.current = tituloEquipo.current
  }, [resultadosAbiertos, resultados])
  useEffect(() => {
    if (!tareasAbiertas || (dia && (!tareasAnalista || filaTareas))) return
    origenTareas.current = tituloEquipo.current
    setTareasAnalista(null)
    tituloTareas.current?.focus()
  }, [tareasAbiertas, dia, tareasAnalista, filaTareas])
  const filas = filtrarOrdenarEquipo(equipo, { busqueda, soloProblemas: soloApoyo, orden: 'atencion', ascendente: false, gravedad: true })
  const filasMes = filasMensualesJornada({ cumplimiento, objetivos: datos.objetivosMensualesError ? null : datos.objetivosMensuales,
    conversion: datos.conversionMensual, supervisorId: actor, tc: datos.tc?.promedio,
    nombres: new Map(datos.equipo.map(f => [f.perfil_id, f.nombre_completo])) })
  const buscar = (nombre: string) => nombre.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('es')
  const filasMesVisibles = filasMes.filter(f => buscar(f.nombre).includes(buscar(busqueda.trim())))
  const irAlEquipo = (modo: 'dia' | 'mes', apoyo = false) => {
    setVista(modo); setSoloApoyo(apoyo); setBusqueda('')
    requestAnimationFrame(() => { tituloEquipo.current?.scrollIntoView({ block: 'start' }); tituloEquipo.current?.focus({ preventScroll: true }) })
  }
  const abrirAnalista = (fila: FilaEquipoPresentada | null, control: HTMLElement) => {
    origenPanel.current = control
    setSeleccion({ analista: fila?.analista_id ?? null, nombre: fila?.nombre_completo ?? null,
      apertura: Date.now(), pestana: 'llamadas', enfocar: fila === null, origen: 'usuario' })
  }
  const actualizar = async () => {
    setActualizando(true)
    try {
      await Promise.allSettled([consultaDia.recargar(), datos.recargarMensual(), cierres.recargar(),
        ...(datos.sesionReal ? [datos.resumenOp.recargar(), citas.consulta.refetch()] : [])])
      setActualizacion(n => n + 1)
    } finally { setActualizando(false) }
  }
  const abrirResultados = (control: HTMLElement) => {
    origenResultados.current = control
    setResultadosAbiertos(true)
  }
  const abrirTareas = (control: HTMLElement, fila?: FilaEquipoPresentada) => {
    origenTareas.current = control
    setTareasAnalista(fila ? { id: fila.analista_id, vencidas: true } : null)
    setTareasAbiertas(true)
  }
  const volverATareasEquipo = () => {
    setTareasAnalista(null)
    tituloTareas.current?.focus()
  }
  const enlaceCitas = hashDe('reuniones', null, undefined, undefined, undefined, undefined, { dia: hoy })

  return <div className="sj-pagina ac-rise">
    <header className="sj-cabecera">
      <div><p className="sj-antetitulo">HOY · SUPERVISIÓN</p><h1>Dirección de la jornada</h1><p>{FECHA.format(new Date(`${hoy}T12:00:00-05:00`))} · Hora de Lima</p></div>
      <Button variant="outline" onClick={() => void actualizar()} disabled={actualizando}><RefreshCw className="size-4" aria-hidden />{actualizando ? 'Actualizando…' : 'Actualizar'}</Button>
    </header>

    <p className="sr-only" role="status" aria-label="Aviso de reparto" aria-atomic="true">{porRepartir != null && porRepartir > 0
      ? `${numero(porRepartir)} ${porRepartir === 1 ? 'lead pendiente' : 'leads pendientes'} de repartir` : ''}</p>
    {porRepartir != null && porRepartir > 0 && <section className="sj-aviso-reparto" aria-label="Leads por repartir">
      <span className="sj-reparto-icono" aria-hidden="true"><Inbox /></span>
      <div className="sj-reparto-resumen">
        <p><strong>{numero(porRepartir)}</strong> {porRepartir === 1 ? 'lead por repartir' : 'leads por repartir'}</p>
        <span className="sj-reparto-estado"><span aria-hidden="true" />Por asignar</span>
      </div>
      <a className="sj-reparto-accion" href={hashDe('derivaciones')}>Repartir leads <ChevronRight aria-hidden /></a>
    </section>}
    <ErrorFuente nombre="Leads por repartir" error={Boolean(datos.resumenOp.error)} reintentar={() => void datos.resumenOp.recargar()} />

    <section className="sj-mes" aria-label={`Resultado del equipo en ${mes}`}>
      <button className="sj-capital" type="button" onClick={() => irAlEquipo('mes')}><span>{mes}</span><strong><Importe capital={capital} /></strong><span>Ver resultado por analista <ArrowUpRight aria-hidden /></span></button>
      <div className="sj-meta">
        <div className="sj-meta-cabecera"><b>{avance ? `${numero(avance.porcentaje, 1)}% de la meta` : estadoMeta ?? (meta.total === null ? 'Meta por confirmar' : meta.total <= 0 ? 'Sin meta fijada' : 'Avance no disponible')}</b><span>{capitalComparable(meta) && (meta.total ?? 0) > 0 ? `Meta ${money(meta.total!, 'PEN')}` : null}</span></div>
        {avance && <>
          <div className="sj-barra" aria-hidden="true"><i style={{ width: `${Math.min(100, avance.porcentaje)}%` }} /></div>
          <p className="sj-brecha">{avance.brecha > 0 ? <>Faltan <strong>{money(avance.brecha, 'PEN')}</strong></> : <strong>Meta del mes alcanzada</strong>}</p>
        </>}
      </div>
      <button type="button" className="sj-resumen-cifra" onClick={() => irAlEquipo('mes')}><strong>{cifra(operaciones)}</strong><span>Operaciones del mes <ArrowUpRight aria-hidden /></span></button>
      <button type="button" className="sj-resumen-cifra" onClick={() => irAlEquipo('mes')}><strong>{tasa(datos.conversionConfirmada)}</strong><span>Conversión oficial <ArrowUpRight aria-hidden /></span><small>{estadoMeta ?? (datos.metaConversion == null ? 'Sin meta de conversión' : `Meta ${tasa(datos.metaConversion)}`)}</small></button>
    </section>
    {(datos.hayErrorMensual || datos.fotoMensualStoreCargando || datos.lecturaConversion.aviso || datos.filasMeta[0]?.nota || cumplimiento?.valoracionCapital) && <div className="sj-contexto-mes">
      <ErrorFuente nombre="Resultado mensual" error={datos.hayErrorMensual} cargando={datos.fotoMensualStoreCargando} reintentar={datos.reintentarMensual} />
      {datos.lecturaConversion.aviso && <p>{datos.lecturaConversion.aviso}</p>}
      {datos.filasMeta[0]?.nota && !datos.cumplimientoMensualError && <p>{datos.filasMeta[0].nota}</p>}
      {cumplimiento?.valoracionCapital && <CoberturaCapitalAviso cobertura={cumplimiento.valoracionCapital.cobertura} sellado={cumplimiento.valoracionCapital.sellado} />}
    </div>}

    <div className="sj-frentes">
      <Frente icono={<Phone />} titulo="Llamadas de hoy" accion={<button type="button" onClick={() => irAlEquipo('dia', true)}><b>{jornada?.primeras == null ? 'Revisar primeras gestiones' : `${numero(jornada.primeras)} primeras gestiones vencidas`}</b><span>Ver quién necesita apoyo <ChevronRight aria-hidden /></span></button>}>
        <button type="button" className="sj-cifra" disabled={!dia} onClick={e => abrirAnalista(null, e.currentTarget)}><strong>{cifra(jornada?.llamadas)}</strong><span>llamadas del equipo <ArrowUpRight aria-hidden /></span></button>
        <div className="sj-linea"><span>Contacto en llamadas útiles</span><b>{tasa(jornada?.contacto)}</b></div>
        <div className="sj-barra" aria-hidden="true"><i style={{ width: `${jornada?.contacto ?? 0}%` }} /></div>
        <p className="sj-nota">{jornada ? `${numero(jornada.contestadas)} contestadas / ${numero(jornada.utiles)} útiles · ${numero(jornada.llamadas - jornada.utiles)} excluidas de la tasa.` : 'La actividad se confirma desde Gestión Diaria.'}</p>
        {jornada && !jornada.muestraSuficiente && <p className="sj-nota">Muestra insuficiente.</p>}
        <ErrorFuente nombre="Actividad de hoy" error={Boolean(consultaDia.error)} cargando={consultaDia.cargando} reintentar={() => void consultaDia.recargar()} />
      </Frente>
      <Frente icono={<CalendarCheck />} titulo="Citas de hoy" accion={<a href={enlaceCitas}><b>{citasHoy ? `${numero(citasHoy.programadas + citasHoy.vencidas)} ${citasHoy.programadas + citasHoy.vencidas === 1 ? 'cita pendiente' : 'citas pendientes'} de resultado` : 'Revisar las citas de hoy'}</b><span>Ver citas del equipo <ChevronRight aria-hidden /></span></a>}>
        <a className="sj-cifra" href={enlaceCitas}><strong>{cifra(citasHoy?.realizadas)}</strong><span>realizadas de {cifra(citasHoy?.total)} previstas <ArrowUpRight aria-hidden /></span></a>
        <div className="sj-linea"><span>{cifra(citasHoy?.programadas)} programadas</span><b>{cifra(citasHoy?.vencidas)} vencidas sin resultado</b></div>
        <div className="sj-barra sj-barra-citas" aria-hidden="true"><i style={{ width: `${citasHoy?.total ? 100 * citasHoy.realizadas / citasHoy.total : 0}%` }} /></div>
        <div className="sj-estados-citas"><span><b>{cifra(citasHoy?.noAsistio)}</b> no asistieron</span><span><b>{cifra(citasHoy?.canceladas)}</b> canceladas</span><span><b>{cifra(citasHoy?.reprogramadas)}</b> reprogramadas</span></div>
        <ErrorFuente nombre="Citas de hoy" error={errorCitas} cargando={datos.sesionReal && citas.consulta.isPending} reintentar={() => void citas.consulta.refetch()} />
      </Frente>
      <Frente icono={<CircleCheck />} titulo="Resultados de hoy" accion={<button type="button" disabled={!resultados} onClick={e => abrirResultados(e.currentTarget)}><b>{resultados ? resultados.operaciones === 0 ? 'Sin cierres registrados hoy' : 'Detalle por analista' : 'Resultados por confirmar'}</b><span>Ver resultados de hoy <ChevronRight aria-hidden /></span></button>}>
        <button type="button" className="sj-cifra" disabled={!resultados} onClick={e => abrirResultados(e.currentTarget)}><strong>{cifra(resultados?.operaciones)}</strong><span>{resultados?.operaciones === 1 ? 'operación cerrada' : 'operaciones cerradas'} <ArrowUpRight aria-hidden /></span></button>
        <div className="sj-linea"><span>Capital cerrado hoy</span></div>
        <p className="sj-importes-dia">{resultados ? <span>{money(resultados.pen, 'PEN')}</span> : '—'}{resultados && <span>{money(resultados.usd, 'USD')}</span>}</p>
        {cierres.aviso && <p className="sj-nota" role={resultadosAbiertos ? undefined : 'status'}>{cierres.aviso}</p>}
        <ErrorFuente nombre="Resultado de hoy" error={cierres.error} cargando={cierres.cargando} reintentar={() => void cierres.recargar()} />
      </Frente>
    </div>

    <section className="sj-equipo" aria-labelledby={idEquipo}>
      <header className="sj-equipo-cabecera">
        <div><h2 id={idEquipo} ref={tituloEquipo} tabIndex={-1}>Con quién trabajar ahora</h2><p>{vista === 'dia' ? 'Hoy · Primero, quienes necesitan apoyo' : `${mes} · Ordenado por capital`}</p></div>
        <div className="sj-equipo-herramientas">
          <div className="sj-pendientes-inline" role="group" aria-label="Pendientes del equipo">
            <div><span><b>{cifra(jornada?.pendientes)}</b> {jornada?.pendientes === 1 ? 'tarea pendiente' : 'tareas pendientes'}</span><small><span className={(jornada?.vencidas ?? 0) > 0 ? 'sj-vencidas' : undefined}>{cifra(jornada?.vencidas)} {jornada?.vencidas === 1 ? 'atrasada' : 'atrasadas'}</span></small></div>
            <button type="button" className="sj-enlace" disabled={!dia} onClick={e => abrirTareas(e.currentTarget)}>Ver pendientes <ChevronRight aria-hidden /></button>
          </div>
          <label className="sj-busqueda"><span className="sr-only">Buscar analista</span><input type="search" placeholder="Buscar analista…" value={busqueda} onChange={e => setBusqueda(e.target.value)} /></label>
        </div>
      </header>
      <Tabs etiqueta="Indicadores del equipo" valor={vista} onCambio={setVista} variante="subrayado" className="sj-tabs" panelEnfocable={false}
        pestanas={[{ valor: 'dia', etiqueta: 'Gestión de hoy' }, { valor: 'mes', etiqueta: 'Resultado del mes' }]}
        acciones={vista === 'dia' ? <label className="sj-filtro"><input type="checkbox" checked={soloApoyo} onChange={e => setSoloApoyo(e.target.checked)} />Solo quienes necesitan apoyo{jornada ? ` (${numero(jornada.requierenApoyo)})` : ''}</label> : <a className="sj-enlace" href={hashDe('facturacion')}>Ver Facturación <ArrowUpRight aria-hidden /></a>}>
        {vista === 'dia' ? <>
          <ErrorFuente nombre="Equipo de hoy" error={Boolean(consultaDia.error)} cargando={consultaDia.cargando} reintentar={() => void consultaDia.recargar()} />
          {dia && (filas.length ? <TablaDesplazable nombre="Gestión de hoy por analista"><table className="sj-tabla sj-tabla-dia"><caption className="sr-only">Llamadas de hoy y pendientes actuales por analista</caption><thead><tr><th scope="col">Analista</th><th scope="col">Llamadas</th><th scope="col">Contacto</th><th scope="col">Citas<br /><small>pendientes hoy</small></th><th scope="col">Tareas<br /><small>vencidas al corte</small></th><th scope="col">Dónde apoyar</th></tr></thead><tbody>
            {filas.map(f => <tr key={f.analista_id}>
              <th scope="row"><button type="button" className="sj-persona" onClick={e => abrirAnalista(f, e.currentTarget)} aria-label={`Ver día de ${f.nombre_completo}`}><Avatar nombre={f.nombre_completo} className="size-8 shrink-0" /><span>{f.nombre_completo}<small>{f.gestiones_hoy > 0 ? `${numero(f.gestiones_hoy)} ${f.gestiones_hoy === 1 ? 'gestión registrada' : 'gestiones registradas'} hoy` : 'Sin actividad registrada hoy'}</small></span><ChevronRight aria-hidden /></button></th>
              <td>{numero(f.marcador.llamadas)}</td>
              <td>{tasa(f.marcador.tasa_contacto_pct)}{f.marcador.nivel === 'bajo' && <small><span className="sj-alerta sj-alerta--aviso">Contacto bajo</span></small>}{f.marcador.nivel === null && <small>Muestra insuficiente</small>}</td>
              <td>{numero(f.citas_hoy)}</td>
              <td><button type="button" className={`sj-tareas-cifra ${f.tareas_vencidas > 0 ? 'sj-vencidas sj-total-vencidas' : ''}`} onClick={e => abrirTareas(e.currentTarget, f)} aria-label={`Ver ${numero(f.tareas_vencidas)} ${f.tareas_vencidas === 1 ? 'tarea atrasada' : 'tareas atrasadas'} de ${f.nombre_completo}`}>{numero(f.tareas_vencidas)}</button></td>
              <td className="sj-motivo"><div className="sj-motivo-lista">{PRIORIDAD_MOTIVO.filter(m => f.motivos_atencion.includes(m)).slice(0, 2).map(m => <span key={m} className={`sj-alerta ${m === 'tarea_vencida' ? 'sj-alerta--vencido' : 'sj-alerta--aviso'}`} title={MOTIVOS_EQUIPO[m]}>{ETIQUETA_ATENCION[m]}</span>)}{!f.requiere_atencion && <span className="sj-nota">Sin avisos de atención</span>}</div></td>
            </tr>)}
          </tbody></table></TablaDesplazable> : <p className="sj-vacio">{equipo.length ? 'Ningún analista coincide con estos filtros.' : 'No hay analistas activos en tu equipo.'}</p>)}
          {jornada && <footer className="sj-tabla-pie"><span>{numero(jornada.conActividad)} de {numero(equipo.length)} analistas con actividad registrada hoy.</span><a href={hashDe('gestion-diaria')}>Abrir Gestión Diaria <ArrowUpRight aria-hidden /></a></footer>}
        </> : <>
          {datos.fotoMensualStoreCargando && filasMesVisibles.length > 0 && <p role="status" className="sj-nota">Consultando capital y metas del mes…</p>}
          {filasMesVisibles.length ? <TablaDesplazable nombre="Resultado mensual por analista"><table className="sj-tabla"><caption className="sr-only">Capital, meta y conversión oficial de {mes}</caption><thead><tr><th scope="col">Analista</th><th scope="col">Capital confirmado</th><th scope="col">Avance de meta</th><th scope="col">Operaciones</th><th scope="col">Conversión oficial</th><th scope="col">Leads recibidos<br /><small>base de conversión</small></th></tr></thead><tbody>
            {filasMesVisibles.map(f => { const progreso = avanceCapital(f.capital, f.meta); return <tr key={f.id}><th scope="row">{f.nombre}{f.esSupervisor && <small>Supervisor · ventas propias</small>}</th><td><Importe capital={f.capital} /></td><td>{progreso ? <>{numero(progreso.porcentaje, 1)}%<small>Meta {money(f.meta.total!, 'PEN')}</small></> : <span className="sj-nota">{f.esSupervisor ? 'Sin meta individual' : f.meta.total === null ? 'No disponible' : f.meta.total <= 0 ? 'Sin meta fijada' : 'No comparable'}</span>}</td><td>{cifra(f.operaciones)}</td><td>{tasa(f.conversion)}{f.recibidos === 0 && <small>Sin base de conversión</small>}</td><td>{cifra(f.recibidos)}</td></tr> })}
          </tbody></table></TablaDesplazable> : <p className="sj-vacio">{busqueda ? 'Ningún analista coincide con la búsqueda.' : datos.fotoMensualStoreCargando ? 'Consultando el resultado del mes…' : 'El resultado mensual por analista no está disponible.'}</p>}
          <footer className="sj-tabla-pie"><span>Atribución oficial del mes, aunque cambie el equipo. «—»: sin confirmar.</span></footer>
        </>}
      </Tabs>
    </section>

    <footer className="sj-accesos"><a href={hashDe('derivaciones')}>Ver derivaciones <ArrowUpRight aria-hidden /></a><button type="button" onClick={() => setTasasAbiertas(true)}>Tasas autorizadas <ArrowUpRight aria-hidden /></button></footer>

    <Dialog open={seleccionVigente !== null} onClose={() => setSeleccion(null)} focoInicial={tituloPanel} focoAlCerrar={origenPanel} className="sj-panel-analista w-[780px]">
      {seleccionVigente && <PanelAnalistaSupervisor id={idPanel} seleccion={seleccionVigente} fila={filaSeleccionada} dia={hoy} minimo={dia?.umbrales.minimo_llamadas_utiles} tituloRef={tituloPanel}
        ampliado={false} puedeAmpliar={false} ampliar={() => {}} cerrar={() => setSeleccion(null)} oculta={false} limpiar={() => {}} actualizacion={actualizacion}
        revalidar={() => void consultaDia.recargar()} esHoy ahora={datos.ahora} />}
    </Dialog>
    <Dialog open={resultadosAbiertos} onClose={() => setResultadosAbiertos(false)} focoAlCerrar={origenResultados} className="sj-detalle-resultados w-[720px]">
      <DialogHeader className="flex-row items-center justify-between"><DialogTitle>Resultados de hoy</DialogTitle><Button variant="ghost" size="icon" aria-label="Cerrar resultados de hoy" onClick={() => setResultadosAbiertos(false)}><X aria-hidden /></Button></DialogHeader>
      <DialogBody>
        <ErrorFuente nombre="Resultado de hoy" error={cierres.error} cargando={cierres.cargando} reintentar={() => void cierres.recargar()} />
        {cierres.aviso && <p className="sj-nota" role="status">{cierres.aviso}</p>}
        {resultados && (resultados.analistas.length > 0 ? <TablaDesplazable nombre="Cierres de hoy por analista"><table className="sj-tabla"><caption className="sr-only">Cierres comerciales del {hoy}, todos los tipos de operación</caption><thead><tr><th scope="col">Analista</th><th scope="col">Operaciones</th><th scope="col">Soles</th><th scope="col">Dólares</th></tr></thead><tbody>
          {resultados.analistas.map(f => <tr key={f.id}><th scope="row">{f.nombre}</th><td>{numero(f.operaciones)}</td><td>{money(f.pen, 'PEN')}</td><td>{money(f.usd, 'USD')}</td></tr>)}
        </tbody><tfoot><tr><th scope="row">Total del día</th><td>{numero(resultados.operaciones)}</td><td>{money(resultados.pen, 'PEN')}</td><td>{money(resultados.usd, 'USD')}</td></tr></tfoot></table></TablaDesplazable> : <p className="sj-vacio">Hoy aún no se registran cierres.</p>)}
        <a className="sj-enlace" href={hashDe('facturacion')}>Ver Facturación <ArrowUpRight className="size-4" aria-hidden /></a>
      </DialogBody>
    </Dialog>
    <Dialog open={tasasAbiertas} onClose={() => setTasasAbiertas(false)} className="w-[900px]"><DialogHeader className="flex-row items-center justify-between"><DialogTitle>Tasas autorizadas del equipo</DialogTitle><Button variant="ghost" size="icon" aria-label="Cerrar tasas autorizadas" onClick={() => setTasasAbiertas(false)}><X aria-hidden /></Button></DialogHeader><DialogBody><TasasAutorizadasAnalistaPanel /></DialogBody></Dialog>
    <Dialog open={tareasAbiertas} onClose={() => setTareasAbiertas(false)} focoInicial={tituloTareas} focoAlCerrar={origenTareas} className="sj-detalle-tareas w-[780px]">
      <DialogHeader className="flex-row items-center justify-between"><DialogTitle ref={tituloTareas} tabIndex={-1}>{filaTareas ? `Tareas de ${filaTareas.nombre_completo}` : 'Pendientes del equipo'}</DialogTitle><Button variant="ghost" size="icon" aria-label="Cerrar tareas" onClick={() => setTareasAbiertas(false)}><X aria-hidden /></Button></DialogHeader>
      <DialogBody>
        <ErrorFuente nombre="Pendientes del equipo" error={Boolean(consultaDia.error)} cargando={consultaDia.cargando} reintentar={() => void consultaDia.recargar()} />
        {dia && (filaTareas && tareasAnalista ? <>
          <button type="button" className="sj-enlace" onClick={volverATareasEquipo}>Volver al equipo</button>
          <PendientesSupervisor key={`${filaTareas.analista_id}:${tareasAnalista.vencidas}`} analista={filaTareas.analista_id} nombre={filaTareas.nombre_completo} dia={hoy} fila={filaTareas}
            visible={tareasAbiertas} soloVencidasInicial={tareasAnalista.vencidas} apertura={0} enfocar={false} actualizacion={actualizacion} revalidar={() => void consultaDia.recargar()} />
        </> : equipo.some(f => f.tareas_pendientes > 0) ? <TablaDesplazable nombre="Tareas pendientes por analista"><table className="sj-tabla"><caption className="sr-only">Pendientes actuales del equipo, incluidas tareas de días anteriores</caption><thead><tr><th scope="col">Analista</th><th scope="col">Pendientes</th><th scope="col">Atrasadas</th></tr></thead><tbody>
          {equipo.filter(f => f.tareas_pendientes > 0).map(f => <tr key={f.analista_id}><th scope="row"><button type="button" className="sj-persona" onClick={() => { setTareasAnalista({ id: f.analista_id, vencidas: false }); tituloTareas.current?.focus() }} aria-label={`Ver tareas de ${f.nombre_completo}`}><span>{f.nombre_completo}</span><ChevronRight aria-hidden /></button></th><td>{numero(f.tareas_pendientes)}</td><td>{numero(f.tareas_vencidas)}</td></tr>)}
        </tbody><tfoot><tr><th scope="row">Total del equipo</th><td>{cifra(jornada?.pendientes)}</td><td>{cifra(jornada?.vencidas)}</td></tr></tfoot></table></TablaDesplazable> : <p className="sj-vacio">No hay tareas pendientes en el equipo.</p>)}
      </DialogBody>
    </Dialog>
  </div>
}

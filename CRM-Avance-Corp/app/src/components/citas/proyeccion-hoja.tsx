// Pestaña «Proyección» de Citas: hoja plana, una fila por analista, con embudos
// tipo Excel en cada cabecera y, a elección, columnas de semanas o días antes de
// «Citas». Todo número se abre en su lista.
import { useCallback, useMemo, useRef, useState } from 'react'
import { ArrowDown, Download, Filter, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Select } from '@/components/ui/select'
import { iniciales, numero } from '@/lib/format'
import { METAS_CITAS_INICIALES } from '@/lib/metas-citas-config'
import { useTipoCambio } from '@/lib/tipo-cambio'
import { cn } from '@/lib/utils'
import { useDatosCitas } from './contexto'
import { fechaLocalCitas } from './fecha-comercial'
import {
  COLUMNA_DE_ORIGEN, ORDEN_INICIAL, ORIGENES, calcularProyeccion, csvProyeccion, opcionesAnalistas, opcionesMonedas,
  opcionesPersonas, type ColumnaNumerica, type ColumnaProyeccion, type FiltrosColumnas,
  type MetricasProyeccion, type OrdenProyeccion, type OrigenCita,
} from './proyeccion'
import {
  diasPermitidos, mesesDelRango, rotuloRango, tiempoEfectivo, type RangoProyeccion, type TiempoProyeccion, type TramoProyeccion,
} from './proyeccion-rango'
import { BarraRango } from './proyeccion-barra-rango'
import { EmbudoColumna, type CambioEmbudo } from './proyeccion-embudo'
import { DetalleProyeccion, type ListaProyeccion } from './proyeccion-detalle'
import { descargarCsv } from './proyeccion-descarga'
import { SenalMetrica } from './senal-resultado'
import './avance-mensual.css'
import './proyeccion.css'

type TipoColumna = 'texto' | 'num' | 'monto' | 'personas'
const COLUMNAS: readonly { id: ColumnaProyeccion; titulo: string; tipo: TipoColumna }[] = [
  { id: 'analista', titulo: 'Analista', tipo: 'texto' },
  { id: 'citas', titulo: 'Citas', tipo: 'num' },
  { id: 'monto', titulo: 'Monto S/', tipo: 'monto' },
  // «Ticket cita» y «Proyectado citas»: Resultados ya llama «Ticket del mes» y «Cierre proyectado» a otras cifras.
  { id: 'ticket', titulo: 'Ticket cita S/', tipo: 'num' },
  { id: 'entrevistas', titulo: '% Entrev.', tipo: 'num' },
  { id: 'conversion', titulo: '% Conv.', tipo: 'num' },
  { id: 'proyectado', titulo: 'Proyectado citas S/', tipo: 'num' },
  { id: 'referidos', titulo: 'Referidos', tipo: 'personas' },
  { id: 'clientes', titulo: 'Clientes', tipo: 'personas' },
  { id: 'leads', titulo: 'Leads', tipo: 'personas' },
]
const ORIGEN_DE_COLUMNA: Partial<Record<ColumnaProyeccion, OrigenCita>> = { referidos: 'referido', clientes: 'cliente', leads: 'lead' }
type TipoLista = 'citas' | 'monto' | 'entrevistas' | 'conversion' | OrigenCita
const TITULOS_LISTA: Record<TipoLista, string> = {
  citas: 'Citas', monto: 'Monto en citas', entrevistas: 'Entrevistas', conversion: 'Entrevistas que cerraron cliente',
  referido: 'Citas de referidos', cliente: 'Citas con clientes', lead: 'Citas con leads',
}
const ETIQUETAS_CITAS: Record<'citas' | OrigenCita, [string, string]> = {
  citas: ['cita', 'citas'], referido: ['cita de referido', 'citas de referidos'],
  cliente: ['cita con cliente', 'citas con clientes'], lead: ['cita con lead', 'citas con leads'],
}
const etiquetaCitas = (tipo: 'citas' | OrigenCita, n: number) => ETIQUETAS_CITAS[tipo][n === 1 ? 0 : 1]
const SIN_CITAS: never[] = []
const listaDe = (m: MetricasProyeccion, tipo: TipoLista) => tipo === 'citas' ? m.citas : tipo === 'monto' ? m.conMonto
  : tipo === 'entrevistas' ? m.entrevistas : tipo === 'conversion' ? m.convertidas : m[COLUMNA_DE_ORIGEN[tipo]]
const soles = (valor: number | null) => valor === null ? '—' : `S/ ${numero(valor)}`
const resumirNombres = (nombres: string[]) => nombres.slice(0, 2).join(', ') + (nombres.length > 2 ? ` +${nombres.length - 2}` : '')
const textoRango = (r: { min?: number | undefined; max?: number | undefined } | undefined) => !r ? ''
  : r.min !== undefined && r.max !== undefined ? `${numero(r.min, 2)} – ${numero(r.max, 2)}` : r.min !== undefined ? `≥ ${numero(r.min, 2)}` : r.max !== undefined ? `≤ ${numero(r.max, 2)}` : ''

const TIEMPOS: readonly { id: TiempoProyeccion; etiqueta: string }[] = [
  { id: 'mes', etiqueta: 'Mes' }, { id: 'semanas', etiqueta: 'Semanas' }, { id: 'dias', etiqueta: 'Días' },
]
const claseTramo = (t: TramoProyeccion) => cn('pc-tiempo', t.domingo && 'pc-domingo', t.hoy && 'pc-hoy', t.futuro && 'pc-futuro')

/** Supervisores del equipo y de las citas del rango; el elegido siempre aparece. «Sin supervisor» al final. */
function supervisoresDe(listas: readonly (readonly { supervisorId: string; supervisor: string }[])[], elegido: string): [string, string][] {
  const nombres = new Map<string, string>()
  for (const lista of listas) for (const p of lista) if (!nombres.has(p.supervisorId)) nombres.set(p.supervisorId, p.supervisor)
  if (elegido && !nombres.has(elegido)) nombres.set(elegido, elegido === 'sin_supervisor' ? 'Sin supervisor' : 'Equipo seleccionado')
  return [...nombres].sort(([a, x], [b, y]) => Number(a === 'sin_supervisor') - Number(b === 'sin_supervisor') || x.localeCompare(y, 'es'))
}

/** Cifra que se abre: un 0 no es botón. */
function Cifra({ cantidad, texto, etiqueta, onAbrir, dinero = false }: { cantidad: number; texto: string; etiqueta: string; onAbrir: () => void; dinero?: boolean }) {
  const contenido = dinero && texto.startsWith('S/ ') ? <><span className="pc-m" aria-hidden>S/</span>{texto.slice(3)}</> : texto
  if (!cantidad) return <span className="pc-n pc-cero">{contenido}</span>
  return <button type="button" className="pc-n" aria-label={`${texto} ${etiqueta}`} onClick={onAbrir}>{contenido}</button>
}

function Celdas({ m, nombre, objetivos, tramos, abrir }: {
  m: MetricasProyeccion; nombre: string; objetivos: { entrevistas: number; conversion: number }
  tramos: readonly TramoProyeccion[]; abrir: (tipo: TipoLista, tramo?: string) => void
}) {
  const de = `de ${nombre}`
  return <>
    {tramos.map((t, i) => {
      const n = m.porTramo[i]?.length ?? 0
      return <td key={t.id} className={claseTramo(t)}><Cifra cantidad={n} texto={numero(n)} etiqueta={`${etiquetaCitas('citas', n)} ${de}, ${t.rotulo}`} onAbrir={() => abrir('citas', t.id)} /></td>
    })}
    <td className={tramos.length ? 'pc-tcierre' : undefined}><Cifra cantidad={m.citas.length} texto={numero(m.citas.length)} etiqueta={`${etiquetaCitas('citas', m.citas.length)} ${de}`} onAbrir={() => abrir('citas')} /></td>
    <td><Cifra cantidad={m.conMonto.length} texto={m.pendienteTc ? 'Pendiente de TC' : m.conMonto.length ? soles(m.monto) : '—'} etiqueta={`en citas ${de}`} onAbrir={() => abrir('monto')} dinero /></td>
    <td><span className={cn('pc-n', m.ticket === null && 'pc-cero')}>{m.ticket === null ? '—' : <><span className="pc-m" aria-hidden>S/</span>{numero(m.ticket)}</>}</span></td>
    <td><SenalMetrica valor={m.pctEntrevistas} objetivo={objetivos.entrevistas} etiqueta={`% Entrev. ${de}`} abrir={m.entrevistas.length ? () => abrir('entrevistas') : undefined} /></td>
    <td><SenalMetrica valor={m.pctConversion} objetivo={objetivos.conversion} etiqueta={`% Conv. ${de}`} abrir={m.convertidas.length ? () => abrir('conversion') : undefined} /></td>
    <td className="pc-proyectado"><span className={cn('pc-n', m.proyectado === null && 'pc-cero')}>{m.proyectado === null ? '—' : <><span className="pc-m" aria-hidden>S/</span>{numero(m.proyectado)}</>}</span></td>
    {ORIGENES.map(origen => {
      const n = m[COLUMNA_DE_ORIGEN[origen]].length
      return <td key={origen}><Cifra cantidad={n} texto={numero(n)} etiqueta={`${etiquetaCitas(origen, n)} ${de}`} onAbrir={() => abrir(origen)} /></td>
    })}
  </>
}

export interface PropsProyeccion {
  /** Supervisor elegido ('' = todos): el mismo estado que la consulta de las otras pestañas. */
  equipo: string
  rango: RangoProyeccion
  /** Lo elegido; con más de 31 días, «Días» se pinta como «Semanas». */
  tiempo: TiempoProyeccion
  onRango: (rango: RangoProyeccion) => void
  onTiempo: (tiempo: TiempoProyeccion) => void
  onEquipo: (equipo: string) => void
}

export function ProyeccionCitas({ equipo, rango, tiempo, onRango, onTiempo, onEquipo }: PropsProyeccion) {
  const datos = useDatosCitas()
  // Con cargador, las citas son las de los meses del rango ya fusionados; sin él
  // (ejemplo y pruebas), las de arriba. Mientras falte un mes no hay cifras.
  const meses = mesesDelRango(rango).join(',')
  const delRango = datos.proyeccion
  const preparado = !delRango || (delRango.meses.join(',') === meses && !delRango.cargando && !delRango.error)
  const citas = preparado ? (delRango ?? datos).citas : SIN_CITAS
  const gestion = (delRango ?? datos).gestion
  const corte = delRango?.corte || datos.corte
  const avance = gestion?.avance
  const [columnas, setColumnas] = useState<FiltrosColumnas>({})
  const [orden, setOrden] = useState<OrdenProyeccion>(ORDEN_INICIAL)
  const [detalle, setDetalle] = useState<{ tipo: TipoLista; filaId: string | null; tramo?: string | undefined } | null>(null)
  const [menu, setMenu] = useState<{ columna: ColumnaProyeccion; ancla: HTMLButtonElement } | null>(null)
  const [aviso, setAviso] = useState('')
  const hojaRef = useRef<HTMLDivElement>(null)
  // Al quitar un filtro su chip desaparece: el foco vuelve al embudo de esa columna.
  const embudos = useRef<Partial<Record<ColumnaProyeccion, HTMLButtonElement | null>>>({})
  // Un embudo de personas o analistas de otro periodo o equipo vaciaría la hoja.
  const { desde, hasta } = rango
  const firma = [desde, hasta, equipo].join('|')
  const [firmaColumnas, setFirmaColumnas] = useState(firma)
  if (firma !== firmaColumnas) { setFirmaColumnas(firma); setColumnas({}) }

  // El tipo de cambio se toma al fin del rango o a hoy, si el rango sigue abierto.
  const hoy = fechaLocalCitas(corte)
  const { tc, recargar } = useTipoCambio(citas.some(c => c.moneda === 'USD' && (c.monto ?? 0) > 0), hasta < hoy ? hasta : hoy)
  const hoja = useMemo(() => calcularProyeccion({
    citas, filtros: { equipo }, rango: { desde, hasta }, tiempo, corte, tipoCambio: tc?.promedio,
    conversiones: avance?.conversiones ?? null, poblacion: avance?.poblacion, analistaResultado: avance?.control.configuracion.analista_resultado,
  }, columnas, orden), [citas, equipo, desde, hasta, tiempo, corte, tc?.promedio, avance, columnas, orden])
  const vistaTiempo = tiempoEfectivo(tiempo, rango)
  const objetivos = {
    entrevistas: avance?.control.configuracion.entrevistas_porcentaje ?? gestion?.entrevistasPorcentaje ?? METAS_CITAS_INICIALES.entrevistas_porcentaje,
    conversion: avance?.control.configuracion.depositos_porcentaje ?? gestion?.depositosPorcentaje ?? METAS_CITAS_INICIALES.depositos_porcentaje,
  }
  const rotulo = rotuloRango(rango)
  const sufijo = `${desde}_${hasta}`
  const t = hoja.total
  const cerrarMenu = useCallback(() => setMenu(null), [])

  const filaAbierta = detalle?.filaId ? hoja.filas.find(f => f.id === detalle.filaId) : undefined
  const fuenteDetalle = detalle && (detalle.filaId === null ? t : filaAbierta)
  const iTramo = detalle?.tramo === undefined ? -1 : hoja.tramos.findIndex(tr => tr.id === detalle.tramo)
  const tramo = hoja.tramos[iTramo]
  // Si la fila o su columna de tiempo salen de la hoja (recarga, embudo u otro
  // rango), la lista se cierra y no reaparece sola.
  const vigente = Boolean(fuenteDetalle && (detalle?.tramo === undefined || tramo))
  if (detalle && !vigente) setDetalle(null)
  const lista: ListaProyeccion | null = detalle && fuenteDetalle && vigente ? {
    titulo: [TITULOS_LISTA[detalle.tipo], tramo?.rotulo, filaAbierta?.nombre ?? 'Total'].filter(Boolean).join(' · '),
    periodo: tramo ? rotuloRango(tramo) : rotulo,
    lista: [...(tramo ? fuenteDetalle.porTramo[iTramo] ?? [] : listaDe(fuenteDetalle, detalle.tipo))].sort((a, b) => `${a.cita.fecha} ${a.cita.hora}`.localeCompare(`${b.cita.fecha} ${b.cita.hora}`) || a.cita.id.localeCompare(b.cita.id)),
    conAnalista: !filaAbierta, archivo: `proyeccion-citas-${detalle.tipo}-${tramo ? `${tramo.desde}_${tramo.hasta}` : sufijo}.csv`,
  } : null

  function alternarOrden(columna: ColumnaProyeccion) {
    setOrden(actual => actual.columna === columna ? { columna, direccion: actual.direccion === 'asc' ? 'desc' : 'asc' }
      : { columna, direccion: columna === 'analista' ? 'asc' : 'desc' })
  }
  function cambiarColumna(columna: ColumnaProyeccion, cambio: CambioEmbudo | null) {
    setColumnas(actual => {
      const siguiente: FiltrosColumnas = { ...actual, personas: { ...actual.personas }, rangos: { ...actual.rangos } }
      const origen = ORIGEN_DE_COLUMNA[columna]
      if (columna === 'analista') siguiente.analistas = cambio?.seleccion
      else if (origen) siguiente.personas![origen] = cambio?.seleccion
      else {
        if (columna === 'monto') siguiente.monedas = cambio?.monedas
        siguiente.rangos![columna] = cambio?.rango
      }
      return siguiente
    })
  }
  function exportar() {
    setAviso(descargarCsv(`proyeccion-citas-${sufijo}.csv`, csvProyeccion(hoja, rotulo)) ? `Se descargó la proyección de ${hoja.filas.length} analistas.` : 'No se pudo descargar el archivo. Vuelve a intentarlo.')
  }

  const nombresAnalista = new Map(hoja.cohorte.map(c => [c.cita.analista, c.cita.analistaNombre]))
  const nombresPersona = new Map(hoja.cohorte.map(c => [c.persona, c.cita.nombre]))
  const chips: { id: ColumnaProyeccion; titulo: string; texto: string }[] = []
  for (const col of COLUMNAS) {
    const origen = ORIGEN_DE_COLUMNA[col.id]
    const seleccion = col.id === 'analista' ? columnas.analistas : origen ? columnas.personas?.[origen] : undefined
    const nombres = seleccion?.map(id => (col.id === 'analista' ? nombresAnalista : nombresPersona).get(id) ?? id)
    const monedas = col.id === 'monto' && columnas.monedas ? (columnas.monedas.length ? columnas.monedas.length === 1 && columnas.monedas[0] === 'PEN' ? 'Solo soles' : columnas.monedas.length === 1 ? 'Solo dólares' : '' : 'Ninguna moneda') : ''
    const texto = [nombres ? (nombres.length ? resumirNombres(nombres) : 'Ninguno') : '', monedas, textoRango(columnas.rangos?.[col.id as ColumnaNumerica])].filter(Boolean).join(' · ')
    if (texto) chips.push({ id: col.id, titulo: col.titulo, texto })
  }
  const columnaMenu = menu && COLUMNAS.find(c => c.id === menu.columna)!
  const origenMenu = menu ? ORIGEN_DE_COLUMNA[menu.columna] : undefined

  // Barra única: Supervisor · periodo · columnas de tiempo · acciones (estas, solo con la hoja lista).
  const supervisores = supervisoresDe([datos.equipo, citas], equipo)
  const barra = (conAcciones: boolean) => <BarraRango rango={rango} hoy={hoy} onRango={onRango}
    antes={<label className="pc-fecha pc-supervisor">Supervisor<Select aria-label="Supervisor" className="h-8" value={equipo} onChange={e => onEquipo(e.target.value)}>
      <option value="">Todos</option>{supervisores.map(([id, nombre]) => <option key={id} value={id}>{nombre}</option>)}
    </Select></label>}>
    <div className="pc-atajos pc-tiempos" role="group" aria-label="Columnas de tiempo">
      {TIEMPOS.map(op => <button key={op.id} type="button" className="pc-atajo" aria-pressed={vistaTiempo === op.id}
        disabled={op.id === 'dias' && !diasPermitidos(rango)} onClick={() => onTiempo(op.id)}>{op.etiqueta}</button>)}
    </div>
    {conAcciones && <div className="pc-acciones">
      {hoja.requiereTc && tc === null && <Button variant="outline" size="sm" onClick={recargar}>Reintentar TC</Button>}
      <Button variant="outline" size="sm" onClick={exportar} disabled={!hoja.filas.length}><Download aria-hidden />Exportar CSV</Button>
    </div>}
  </BarraRango>
  if (delRango?.error) return <div className="pc-panel">{barra(false)}<div role="alert" className="space-y-3 py-8"><p>{delRango.error}</p><Button variant="outline" onClick={delRango.onReintentar}>Reintentar</Button></div></div>
  if (!preparado) return <div className="pc-panel">{barra(false)}<p role="status" className="py-8 text-sm text-muted-foreground-strong">Cargando las citas del rango…</p></div>

  const cabecera = (col: (typeof COLUMNAS)[number]) => {
    const activo = chips.some(ch => ch.id === col.id)
    return <th key={col.id} scope="col" data-col={col.id} data-filtro={activo}
      className={cn(col.id === 'analista' && 'pc-analista pc-texto', col.id === 'citas' && hoja.tramos.length > 0 && 'pc-tcierre') || undefined}
      aria-sort={orden.columna === col.id ? orden.direccion === 'asc' ? 'ascending' : 'descending' : undefined}>
      <div className="pc-th">
        <button type="button" className="pc-th-orden" onClick={() => alternarOrden(col.id)}>{col.titulo}<ArrowDown className="pc-flecha" aria-hidden /></button>
        <button ref={boton => { embudos.current[col.id] = boton }} type="button" className="pc-embudo" aria-label={`Filtrar ${col.titulo}${activo ? ', con filtro' : ''}`} aria-haspopup="dialog" aria-expanded={menu?.columna === col.id}
          onClick={evento => { const ancla = evento.currentTarget; setMenu(actual => actual?.columna === col.id ? null : { columna: col.id, ancla }) }}><Filter aria-hidden /></button>
      </div>
    </th>
  }

  return <div className="pc-panel">
    {barra(true)}
    {chips.length > 0 && <div className="pc-chips" role="group" aria-label="Filtros de columna">
      {chips.map(ch => <span key={ch.id} className="pc-chip"><b>{ch.titulo}</b> {ch.texto}<button type="button" aria-label={`Quitar filtro de ${ch.titulo}`} onClick={() => { cambiarColumna(ch.id, null); embudos.current[ch.id]?.focus() }}><X aria-hidden /></button></span>)}
      <Button variant="ghost" size="sm" onClick={() => { const primero = chips[0]!.id; setColumnas({}); embudos.current[primero]?.focus() }}>Limpiar</Button>
    </div>}
    {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- Hoja ancha consultable con flechas del teclado. */}
    <div ref={hojaRef} className="pc-scroll" role="region" tabIndex={0} aria-label="Hoja de proyección por analista">
      <table className="pc-hoja" data-tiempo={vistaTiempo}>
        <caption className="sr-only">Proyección de citas por analista · {rotulo}</caption>
        <thead><tr>
          <th scope="col" className="pc-n0"><span aria-hidden>#</span><span className="sr-only">Número</span></th>
          {cabecera(COLUMNAS[0]!)}
          {hoja.tramos.map(tr => <th key={tr.id} scope="col" className={claseTramo(tr)}>
            {/* Cada palabra del detalle va entera: si no cabe, solo baja el mes («22–30» / «set»). */}
            <span className="pc-tiempo-cab" aria-hidden>{tr.titulo}<small>{tr.detalle.split(' ').flatMap((parte, i) =>
              i ? [' ', <span key={i}>{parte}</span>] : [<span key={i}>{parte}</span>])}</small></span><span className="sr-only">{tr.nombre}</span>
          </th>)}
          {COLUMNAS.slice(1).map(cabecera)}
        </tr></thead>
        <tbody>{hoja.filas.map((f, i) => <tr key={f.id} className="pc-fila">
          <td className="pc-n0">{i + 1}</td>
          <th scope="row" className="pc-analista"><span className="pc-nombre"><span className="pc-avatar" aria-hidden>{iniciales(f.nombre)}</span>{f.nombre}</span></th>
          <Celdas m={f} nombre={f.nombre} objetivos={objetivos} tramos={hoja.tramos} abrir={(tipo, tramo) => setDetalle({ tipo, filaId: f.id, tramo })} />
        </tr>)}</tbody>
        <tfoot><tr>
          <td className="pc-n0"><span aria-hidden>Σ</span></td>
          <th scope="row" className="pc-analista">Total · {numero(hoja.filas.length)} {hoja.filas.length === 1 ? 'analista' : 'analistas'}</th>
          <Celdas m={t} nombre="todos los analistas" objetivos={objetivos} tramos={hoja.tramos} abrir={(tipo, tramo) => setDetalle({ tipo, filaId: null, tramo })} />
        </tr></tfoot>
      </table>
    </div>
    <p role="status" className={aviso ? 'citas-nota py-2' : 'sr-only'}>{aviso}</p>
    {menu && columnaMenu && <EmbudoColumna key={menu.columna} titulo={columnaMenu.titulo} tipo={columnaMenu.tipo} ancla={menu.ancla}
      orden={orden.columna === menu.columna ? orden.direccion : null}
      opciones={menu.columna === 'analista' ? opcionesAnalistas(hoja, columnas) : origenMenu ? opcionesPersonas(hoja, columnas, origenMenu) : undefined}
      seleccion={menu.columna === 'analista' ? columnas.analistas : origenMenu ? columnas.personas?.[origenMenu] : undefined}
      monedas={menu.columna === 'monto' ? { opciones: opcionesMonedas(hoja, columnas), seleccion: columnas.monedas } : undefined}
      rango={menu.columna === 'analista' ? undefined : columnas.rangos?.[menu.columna]}
      conRango={columnaMenu.tipo === 'num' || columnaMenu.tipo === 'monto'}
      buscarComo={menu.columna === 'analista' ? 'analista' : origenMenu ? origenMenu === 'cliente' ? 'cliente' : origenMenu === 'referido' ? 'referido' : 'lead' : ''}
      onOrdenar={direccion => setOrden({ columna: menu.columna, direccion })}
      onAplicar={cambio => cambiarColumna(menu.columna, cambio)} onBorrar={() => cambiarColumna(menu.columna, null)} onCerrar={cerrarMenu} />}
    <DetalleProyeccion detalle={lista} onCerrar={() => setDetalle(null)} focoRespaldo={() => hojaRef.current} />
  </div>
}

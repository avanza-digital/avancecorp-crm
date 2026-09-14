import { useState, type CSSProperties, type KeyboardEvent, type ReactNode } from 'react'
import { ArrowRight, CalendarDays, ChartNoAxesCombined, Check, ChevronRight, CircleAlert, Download, Info, List, Minus, RotateCcw, SlidersHorizontal, TrendingUp, TriangleAlert, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Select } from '@/components/ui/select'
import { Sheet, SheetHeader, SheetTitle, SheetBody } from '@/components/ui/sheet'
import { MenuCRM } from '../citas-crm/marco'
import { CITAS, CORTE_DIA, EQUIPO, ESTADOS, INICIAL, META_ASISTENCIA, META_CITAS, META_CONVERSION, TRAMOS, citasDe, dinero, enSemana, fecha, metricas, numero, personasConsulta, porcentaje, recorrido, type BaseConversion, type Consulta, type Metricas, type Persona, type Recorrido } from './modelo'
import { RITMO_ESPERADO, SENALES, senalCitas, senalObjetivo, type Senal } from './semantica'

const PESTANAS = [
  { id: 'bandeja', texto: 'Bandeja comercial', icono: List },
  { id: 'agenda', texto: 'Agenda', icono: CalendarDays },
  { id: 'resultados', texto: 'Resultados', icono: ChartNoAxesCombined },
] as const
type Vista = typeof PESTANAS[number]['id']
const ETAPAS = ['No asistieron', 'Reprogramaron', 'Asistieron después', 'Se hicieron clientes']
const enEtapa = (r: Recorrido, etapa: number) => etapa === 0 || (etapa === 1 ? !!r.nueva : etapa === 2 ? !!r.asistencia : r.cliente)
const analistaNombre = (id: string) => EQUIPO.find(a => a.id === id)?.nombre ?? id

function Campo({ titulo, children }: { titulo: string; children: ReactNode }) {
  return <label className="ca-campo"><span>{titulo}</span>{children}</label>
}
function PanelLateral({ titulo, abierto, cerrar, children }: { titulo: string; abierto: boolean; cerrar: () => void; children: ReactNode }) {
  return <Sheet open={abierto} onClose={cerrar} className="ca-detalle w-[530px]">
    <SheetHeader><div className="ca-entre"><SheetTitle>{titulo}</SheetTitle><Button variant="ghost" size="icon" onClick={cerrar} aria-label="Cerrar detalle"><X aria-hidden /></Button></div></SheetHeader>
    <SheetBody>{children}</SheetBody>
  </Sheet>
}
const ICONOS_SENAL = { cumplida: Check, ritmo: TrendingUp, atencion: TriangleAlert, prioridad: CircleAlert, sin_base: Minus }
const estiloSenal = (estado: Senal) => ({ '--ca-senal-color': SENALES[estado].color, '--ca-senal-tinta': SENALES[estado].tinta }) as CSSProperties
function ResultadoVisual({ estado, valor, etiqueta, onDetalle }: { estado: Senal; valor: string; etiqueta: string; onDetalle?: (() => void) | undefined }) {
  const Icono = ICONOS_SENAL[estado]
  const descripcion = `${etiqueta}: ${valor}. ${SENALES[estado].texto}`
  const contenido = <><strong>{valor}</strong>{estado !== 'sin_base' && <Icono aria-hidden />}<span className="sr-only"> · {SENALES[estado].texto}</span></>
  return onDetalle
    ? <button className="ca-senal" data-senal={estado} style={estiloSenal(estado)} title={`${descripcion}. Ver detalle`} aria-label={`${descripcion}. Ver detalle`} onClick={onDetalle}>{contenido}</button>
    : <span className="ca-senal" data-senal={estado} style={estiloSenal(estado)} title={descripcion}>{contenido}</span>
}
function CeldaTasa({ tasa, base, meta, etiqueta, onDetalle }: { tasa: number | null; base: string; meta: number; etiqueta: string; onDetalle?: (() => void) | undefined }) {
  const estado = senalObjetivo(tasa === null ? null : tasa * 100, meta)
  return <><ResultadoVisual estado={estado} valor={porcentaje(tasa)} etiqueta={etiqueta} onDetalle={onDetalle} /><small>{base}</small></>
}
function Celdas({ m, proyeccion = m.proyeccion, parcial = false, moneda, onDetalle }: { m: Metricas; proyeccion?: number | null; parcial?: boolean; moneda: string; onDetalle?: (() => void) | undefined }) {
  const estado = senalCitas(m.cumplimiento)
  return <>
    <td>{numero(m.leads)}</td>
    <td><strong>{numero(m.citas)}</strong><small>{numero(m.promedio, 2)} por lead</small></td>
    <td><ResultadoVisual estado={estado} valor={m.cumplimiento === null ? '—' : numero(m.cumplimiento, 1) + '%'} etiqueta="Avance de citas" onDetalle={onDetalle} /><div className="ca-progreso" style={estiloSenal(estado)} title={`Ritmo orientativo al ${CORTE_DIA} sept.: ${numero(RITMO_ESPERADO, 1)}% de la meta mensual`}><span style={{ width: `${Math.min(100, m.cumplimiento ?? 0)}%` }} /><i style={{ left: `${RITMO_ESPERADO}%` }} aria-hidden /><span className="sr-only">Ritmo orientativo del mes: {numero(RITMO_ESPERADO, 1)}%</span></div></td>
    <td><CeldaTasa tasa={m.asistencia} base={`${m.entrevistas} entrevistas`} meta={META_ASISTENCIA} etiqueta="Entrevistas" onDetalle={onDetalle} /></td>
    <td><CeldaTasa tasa={m.conversion} base={`${m.clientes} clientes`} meta={META_CONVERSION} etiqueta="Conversión" onDetalle={onDetalle} /></td>
    <td className={m.ticket === null ? 'ca-sin-dato' : undefined}>{dinero(m.ticket, moneda)}</td>
    <td className={`ca-cierre${proyeccion === null ? ' ca-sin-dato' : ''}`}><strong>{dinero(proyeccion, moneda)}</strong><small>{proyeccion === null ? 'Sin clientes en el mes' : parcial ? 'Estimación parcial' : 'Estimado al 30 sept.'}</small></td>
  </>
}
function HistorialPersona({ persona }: { persona: Persona }) {
  const citas = CITAS.filter(c => c.lead === persona.id).sort((a, b) => a.dia - b.dia)
  return <>
    <p className="ca-texto">{analistaNombre(persona.analista)} · {persona.origen} · {persona.manual ? 'Registro manual incluido' : 'Lead recibido'}</p>
    <ol className="ca-historial">{citas.map(c => <li key={c.id}><span>{fecha(c.dia)}</span><div><strong>{ESTADOS[c.estado]}</strong><p>{c.anterior ? 'Cita reprogramada, vinculada a la inasistencia.' : 'Cita registrada en el CRM.'}</p></div></li>)}
      {persona.conversion !== null && <li><span>{fecha(persona.conversion)}</span><div><strong>Se convirtió en cliente</strong><p>Depósito acreditado por conversión. Importe del ejemplo: {dinero(persona.importe, persona.moneda)}.</p></div></li>}
    </ol>
    <p className="ca-aclaracion">Cada asistencia suma una entrevista. La persona se cuenta una sola vez como cliente.</p>
  </>
}
function Paginacion({ total, pagina, cambiar, tamano = 8 }: { total: number; pagina: number; cambiar: (n: number) => void; tamano?: number }) {
  return <div className="ca-pie ca-entre"><span>{total ? `${pagina * tamano + 1}–${Math.min((pagina + 1) * tamano, total)} de ${total} personas` : '0 personas'}</span><div className="flex gap-2"><Button variant="outline" size="sm" disabled={pagina === 0} onClick={() => cambiar(pagina - 1)}>Anterior</Button><Button variant="outline" size="sm" disabled={(pagina + 1) * tamano >= total} onClick={() => cambiar(pagina + 1)}>Siguiente</Button></div></div>
}
function DatosAnalista({ personas, base }: { personas: Persona[]; base: BaseConversion }) {
  const m = metricas(personas, base)
  const [verPersonas, setVerPersonas] = useState(false)
  const [soloSinCita, setSoloSinCita] = useState(false)
  const [paginaLeads, setPaginaLeads] = useState(0)
  const [persona, setPersona] = useState<Persona | null>(null)
  const pendientes = Math.max(0, Math.ceil(personas.length * META_CITAS) - m.citas)
  const lista = personas.filter(p => !soloSinCita || !CITAS.some(c => c.lead === p.id))
  return <>
    <p className="ca-texto">Septiembre 2026 · acumulado al {CORTE_DIA} sept.</p>
    <dl className="ca-desglose">
      <div><dt>Avance de citas</dt><dd><ResultadoVisual estado={senalCitas(m.cumplimiento)} valor={m.cumplimiento === null ? '—' : numero(m.cumplimiento, 1) + '%'} etiqueta="Avance de citas" /><small>{pendientes ? `Faltan ${pendientes} citas para la meta mensual` : 'Meta mensual alcanzada'}</small></dd></div>
      <div><dt>Entrevistas · objetivo 70%</dt><dd><ResultadoVisual estado={senalObjetivo(m.asistencia === null ? null : m.asistencia * 100, META_ASISTENCIA)} valor={porcentaje(m.asistencia)} etiqueta="Entrevistas" /><small>{m.entrevistas} entrevistas / {m.resueltas} citas con resultado</small></dd></div>
      <div><dt>Conversión · objetivo 70%</dt><dd><ResultadoVisual estado={senalObjetivo(m.conversion === null ? null : m.conversion * 100, META_CONVERSION)} valor={porcentaje(m.conversion)} etiqueta="Conversión" /><small>{m.clientes} clientes / {base === 'personas' ? `${m.unicas} personas entrevistadas` : `${m.entrevistas} entrevistas`}</small></dd></div>
      <div><dt>Ticket de septiembre</dt><dd>{dinero(m.ticket)}<small>{dinero(m.capital)} captados / {m.clientes} clientes</small></dd></div>
      <div><dt>Cierre mensual estimado</dt><dd>{dinero(m.proyeccion)}<small>{m.clientesEsperados === null ? 'Hace falta una base de conversiones e importes' : `Aproximadamente ${numero(m.clientesEsperados)} clientes al cierre`}</small></dd></div>
    </dl>
    <p className="ca-aclaracion">{m.leads} leads, incluidos {m.manuales} manuales. {m.sinCita} todavía sin cita. {m.entrevistas - m.unicas} entrevistas adicionales de personas que ya habían asistido.</p>
    <details className="ca-reglas"><summary>Cómo se obtiene la proyección</summary><p>Se extiende el ritmo de citas registradas al día {CORTE_DIA} hasta el día 30 y se aplica la asistencia observada. Las entrevistas se relacionan con personas distintas antes de estimar clientes, con un límite de {m.leads} leads.</p><p>Se usa la conversión observada y el ticket de este mes. El resultado incluye {dinero(m.capital)} ya captados; no es un importe adicional. Es una fórmula propuesta, no un cierre asegurado.</p><p>{m.sinResultado} citas sin resultado y {m.futuras} futuras no entran en la tasa de asistencia.</p></details>
    <Button variant="outline" className="ca-ancho" onClick={() => setVerPersonas(!verPersonas)} aria-expanded={verPersonas}>{verPersonas ? 'Ocultar leads' : 'Ver leads y citas'}<ChevronRight aria-hidden /></Button>
    {verPersonas && <div className="ca-personas"><label className="ca-check"><input type="checkbox" checked={soloSinCita} onChange={e => { setSoloSinCita(e.target.checked); setPaginaLeads(0) }} />Solo leads sin citas ({m.sinCita})</label><p className="ca-texto">{lista.length} leads del analista</p>{lista.slice(paginaLeads * 20, paginaLeads * 20 + 20).map(p => <Button key={p.id} variant="ghost" className="ca-persona" onClick={() => setPersona(p)}><span>{p.nombre}<small>{CITAS.filter(c => c.lead === p.id).length} citas{p.manual ? ' · Manual' : ''}</small></span><ChevronRight aria-hidden /></Button>)}<Paginacion total={lista.length} pagina={paginaLeads} cambiar={setPaginaLeads} tamano={20} /></div>}
    <PanelLateral titulo={persona?.nombre ?? 'Persona'} abierto={!!persona} cerrar={() => setPersona(null)}>{persona && <HistorialPersona persona={persona} />}</PanelLateral>
  </>
}
function VistaOperativa({ personas, semana, agenda, abrir }: { personas: Persona[]; semana: string; agenda: boolean; abrir: (p: Persona) => void }) {
  const [estado, setEstado] = useState('')
  const [pagina, setPagina] = useState(0)
  const citas = citasDe(personas).filter(c => enSemana(c.dia, semana) && (!estado || c.estado === estado)).sort((a, b) => agenda ? a.dia - b.dia : (a.estado === 'pendiente' ? -1 : 1) - (b.estado === 'pendiente' ? -1 : 1) || a.dia - b.dia)
  const ultima = Math.max(0, Math.ceil(citas.length / 10) - 1)
  const actual = Math.min(pagina, ultima)
  return <section className="ca-panel">
    <div className="ca-seccion"><div><h2>{agenda ? 'Agenda del período' : 'Citas de tu consulta'}</h2><p>{citas.length} citas del ejemplo · {agenda ? 'ordenadas por fecha' : 'sin resultado primero'}</p></div><Campo titulo="Estado"><Select aria-label="Estado" value={estado} onChange={e => { setEstado(e.target.value); setPagina(0) }}><option value="">Todos los estados</option>{Object.entries(ESTADOS).map(([id, nombre]) => <option key={id} value={id}>{nombre}</option>)}</Select></Campo></div>
    <div className="ca-scroll"><table className="ca-tabla ca-operativa"><thead><tr><th scope="col">Persona</th><th scope="col">Analista</th><th scope="col">Fecha prevista</th><th scope="col">Estado</th><th scope="col">Seguimiento</th></tr></thead><tbody>{citas.slice(actual * 10, actual * 10 + 10).map(c => {
      const p = personas.find(p => p.id === c.lead)!
      return <tr key={c.id}><th scope="row"><button onClick={() => abrir(p)}>{p.nombre}</button></th><td>{analistaNombre(c.analista)}</td><td>{fecha(c.dia)}</td><td>{ESTADOS[c.estado]}</td><td>{c.anterior ? 'Cita reprogramada' : p.conversion ? 'Cliente' : 'En gestión'}</td></tr>
    })}</tbody></table></div>
    {!citas.length && <p className="ca-vacio">No hay citas con estos filtros. Elige otra semana o estado.</p>}
    <div className="ca-pie ca-entre"><span>{citas.length ? `${actual * 10 + 1}–${Math.min(citas.length, actual * 10 + 10)} de ${citas.length}` : '0 citas'}</span><div className="flex gap-2"><Button variant="outline" size="sm" disabled={actual === 0} onClick={() => setPagina(actual - 1)}>Anterior</Button><Button variant="outline" size="sm" disabled={actual === ultima} onClick={() => setPagina(actual + 1)}>Siguiente</Button></div></div>
  </section>
}

export function Propuesta() {
  const [f, setF] = useState<Consulta>(INICIAL)
  const [mas, setMas] = useState(false)
  const [vista, setVista] = useState<Vista>('resultados')
  const [base, setBase] = useState<BaseConversion>('personas')
  const [ayuda, setAyuda] = useState(false)
  const [etapa, setEtapa] = useState<number | null>(null)
  const [paginaFlujo, setPaginaFlujo] = useState(0)
  const [soloPendientes, setSoloPendientes] = useState(false)
  const [analista, setAnalista] = useState<string | null>(null)
  const [persona, setPersona] = useState<Persona | null>(null)
  const [anuncio, setAnuncio] = useState('')
  const personas = personasConsulta(f)
  const filas = EQUIPO.filter(a => personas.some(p => p.analista === a.id)).map(a => ({ ...a, m: metricas(personas.filter(p => p.analista === a.id), base) }))
  const total = metricas(personas, base)
  const flujo = recorrido(personas, f.semana)
  const cantidades = ETAPAS.map((_, i) => flujo.filter(r => enEtapa(r, i)).length)
  const sinNueva = flujo.filter(r => !r.nueva).length
  const visibles = flujo.filter(r => soloPendientes ? !r.nueva : enEtapa(r, etapa ?? 0))
  const actualFlujo = Math.min(paginaFlujo, Math.max(0, Math.ceil(visibles.length / 8) - 1))
  const conBase = filas.filter(a => a.m.proyeccion !== null)
  const proyectado = conBase.length ? conBase.reduce((n, a) => n + a.m.proyeccion!, 0) : null
  const tramo = TRAMOS.find(t => t.id === f.semana)
  const actividadSemana = citasDe(personas).filter(c => enSemana(c.dia, f.semana))
  function cambiar(clave: keyof Consulta, valor: string) {
    setF(prev => ({ ...prev, [clave]: valor, ...(clave === 'supervisor' ? { analista: '' } : {}) }))
    setEtapa(null); setSoloPendientes(false)
  }
  function teclas(evento: KeyboardEvent<HTMLButtonElement>, i: number) {
    const destino = evento.key === 'ArrowRight' ? (i + 1) % 3 : evento.key === 'ArrowLeft' ? (i + 2) % 3 : evento.key === 'Home' ? 0 : evento.key === 'End' ? 2 : null
    if (destino === null) return
    evento.preventDefault(); setVista(PESTANAS[destino]!.id)
    document.getElementById(`ca-tab-${PESTANAS[destino]!.id}`)?.focus()
  }
  function exportar() {
    const contenido = [['Vista de ejemplo; cifras ficticias'], ['Mes', 'Analista', 'Leads', 'Citas', 'Citas por lead', 'Cumplimiento %', 'Entrevistas', 'Personas entrevistadas', 'Entrevistas %', 'Clientes', 'Conversion %', 'Base conversion propuesta', 'Ticket mes', 'Cierre estimado', 'Moneda'], ...filas.map(a => [f.mes, a.nombre, a.m.leads, a.m.citas, a.m.promedio, a.m.cumplimiento, a.m.entrevistas, a.m.unicas, a.m.asistencia === null ? '' : a.m.asistencia * 100, a.m.clientes, a.m.conversion === null ? '' : a.m.conversion * 100, base, a.m.ticket, a.m.proyeccion, f.moneda])]
    const csv = contenido.map(fila => fila.map(v => `"${String(v ?? '').replaceAll('"', '""')}"`).join(';')).join('\r\n')
    const url = URL.createObjectURL(new Blob(['\ufeff', csv], { type: 'text/csv;charset=utf-8' }))
    const enlace = document.createElement('a'); enlace.href = url; enlace.download = `ejemplo-citas-${f.mes}.csv`; enlace.click()
    setTimeout(() => URL.revokeObjectURL(url), 1000)
    setAnuncio('Se descargó el avance mensual con datos de ejemplo y los filtros de equipo actuales.')
  }
  return <div className="ca-app">
    <MenuCRM />
    <div className="ca-principal">
      <header className="ca-top"><div><strong>Citas</strong><span>Gerencia comercial</span></div><span className="ca-ejemplo">Vista local · Datos de ejemplo</span></header>
      <main className="ca-contenido" id="consulta-citas" tabIndex={-1}>
        <div className="ca-titulo"><div><h1>Citas del equipo</h1><p>Del seguimiento al avance comercial de cada analista.</p></div><Button variant="outline" onClick={() => setAyuda(true)}><Info aria-hidden />Cómo se calcula</Button></div>
        <section className="ca-filtros" aria-label="Filtros de la consulta">
          <div className="ca-filtros-fila">
            <Campo titulo="Mes"><Select aria-label="Mes" value={f.mes} onChange={e => cambiar('mes', e.target.value)}><option value="2026-09">Septiembre 2026</option><option value="2026-08">Agosto 2026</option></Select></Campo>
            <Campo titulo="Semana del seguimiento"><Select aria-label="Semana del seguimiento" value={f.semana} onChange={e => cambiar('semana', e.target.value)}><option value="">Todo el mes</option>{TRAMOS.map(t => <option key={t.id} value={t.id}>{t.nombre}</option>)}</Select></Campo>
            <Campo titulo="Supervisor"><Select aria-label="Supervisor" value={f.supervisor} onChange={e => cambiar('supervisor', e.target.value)}><option value="">Todos</option>{[...new Set(EQUIPO.map(a => a.supervisor))].map(s => <option key={s}>{s}</option>)}</Select></Campo>
            <Campo titulo="Analista"><Select aria-label="Analista" value={f.analista} onChange={e => cambiar('analista', e.target.value)}><option value="">Todos los analistas</option>{EQUIPO.filter(a => !f.supervisor || a.supervisor === f.supervisor).map(a => <option key={a.id} value={a.id}>{a.nombre}</option>)}</Select></Campo>
            <Button variant="outline" aria-expanded={mas} aria-controls="ca-mas-filtros" onClick={() => setMas(!mas)}><SlidersHorizontal aria-hidden />Más filtros{(f.origen || f.registro || f.moneda !== 'PEN') && ' •'}</Button>
            <Button variant="ghost" size="icon" aria-label="Restablecer filtros" onClick={() => { setF(INICIAL); setEtapa(null); setSoloPendientes(false) }}><RotateCcw aria-hidden /></Button>
          </div>
          {mas && <div className="ca-mas" id="ca-mas-filtros">
            <Campo titulo="Origen"><Select aria-label="Origen" value={f.origen} onChange={e => cambiar('origen', e.target.value)}><option value="">Todos los orígenes</option>{['Facebook', 'Web', 'Referido'].map(o => <option key={o}>{o}</option>)}</Select></Campo>
            <Campo titulo="Registro del lead"><Select aria-label="Registro del lead" value={f.registro} onChange={e => cambiar('registro', e.target.value)}><option value="">Todos, incluidos manuales</option><option value="manual">Solo manuales</option><option value="recibido">Solo recibidos</option></Select></Campo>
            <Campo titulo="Moneda"><Select aria-label="Moneda" value={f.moneda} onChange={e => cambiar('moneda', e.target.value)}><option value="PEN">Soles (S/)</option><option value="USD">Dólares (US$)</option></Select></Campo>
          </div>}
        </section>
        <div className="ca-vistas"><div role="tablist" aria-label="Vistas de citas">{PESTANAS.map((t, i) => <Button key={t.id} id={`ca-tab-${t.id}`} variant="ghost" role="tab" aria-selected={vista === t.id} aria-controls="ca-panel-vista" tabIndex={vista === t.id ? 0 : -1} onClick={() => setVista(t.id)} onKeyDown={e => teclas(e, i)}><t.icono aria-hidden />{t.texto}</Button>)}</div><span>Ejemplo al {CORTE_DIA} sept. 2026 · Lima</span></div>
        <div id="ca-panel-vista" role="tabpanel" aria-labelledby={`ca-tab-${vista}`}>
          {vista !== 'resultados' ? <VistaOperativa key={vista} personas={personas} semana={f.semana} agenda={vista === 'agenda'} abrir={setPersona} /> : <>
            <section className="ca-panel ca-recuperacion" aria-labelledby="ca-recuperacion-titulo">
              <div className="ca-seccion"><div><h2 id="ca-recuperacion-titulo">¿Qué pasó con quienes no asistieron?</h2>{tramo && <p>{tramo.nombre} · seguimiento hasta el {CORTE_DIA} sept.</p>}</div><Button variant="ghost" className="ca-pendiente" data-hay-pendientes={sinNueva > 0} onClick={() => { setEtapa(0); setSoloPendientes(!soloPendientes); setPaginaFlujo(0) }} aria-pressed={soloPendientes}>{sinNueva > 0 && <TriangleAlert aria-hidden />}{sinNueva} sin nueva cita<ChevronRight aria-hidden /></Button></div>
              <div className="ca-recorrido"><div className="ca-etapas">{ETAPAS.map((titulo, i) => <div key={titulo} className="ca-etapa" data-etapa={i} data-con-datos={cantidades[i]! > 0}><button aria-pressed={etapa === i && !soloPendientes} onClick={() => { setEtapa(etapa === i && !soloPendientes ? null : i); setSoloPendientes(false); setPaginaFlujo(0) }} aria-label={`${titulo}: ${cantidades[i]}. Ver personas`}><strong>{cantidades[i]}</strong><span className="ca-label-escritorio">{titulo}</span><span className="ca-label-movil" aria-hidden>{['No asistieron', 'Nueva cita', 'Asistieron', 'Clientes'][i]}</span></button>{i < 3 && <ArrowRight aria-hidden />}</div>)}</div><div className="ca-recuperado"><strong>{porcentaje(cantidades[0] ? cantidades[3]! / cantidades[0]! : null)}</strong><span>llegaron a depósito</span></div></div>
              {etapa !== null && <div className="ca-lista-recuperacion"><div className="ca-subcabecera"><strong>{soloPendientes ? 'Personas sin nueva cita' : ETAPAS[etapa]} <span>({visibles.length})</span></strong><Button variant="ghost" size="icon" aria-label="Ocultar personas del recorrido" onClick={() => { setEtapa(null); setSoloPendientes(false) }}><X aria-hidden /></Button></div><div className="ca-scroll"><table className="ca-tabla ca-operativa"><thead><tr><th scope="col">Persona</th><th scope="col">Analista</th><th scope="col">No asistió</th><th scope="col">Nueva cita</th><th scope="col">Entrevista</th><th scope="col">Cliente</th></tr></thead><tbody>{visibles.slice(actualFlujo * 8, actualFlujo * 8 + 8).map(r => <tr key={r.persona.id}><th scope="row"><button onClick={() => setPersona(r.persona)}>{r.persona.nombre}</button></th><td>{analistaNombre(r.persona.analista)}</td><td>{fecha(r.falta.dia)}</td><td>{r.nueva ? fecha(r.nueva.dia) : <span className="ca-texto-pendiente">Sin nueva cita</span>}</td><td>{r.asistencia ? fecha(r.asistencia.dia) : 'Pendiente'}</td><td>{r.cliente ? fecha(r.persona.conversion!) : '—'}</td></tr>)}</tbody></table></div>{!visibles.length && <p className="ca-vacio">No hay personas en esta etapa con los filtros elegidos.</p>}{visibles.length > 8 && <Paginacion total={visibles.length} pagina={actualFlujo} cambiar={setPaginaFlujo} />}</div>}
              <div className="ca-pie">Cada etapa parte de la anterior. Depósito = conversión a cliente después de asistir.</div>
            </section>
            <section className="ca-panel ca-equipo" aria-labelledby="ca-equipo-titulo">
              <div className="ca-seccion"><div><h2 id="ca-equipo-titulo">Avance mensual por analista</h2><p>{f.mes === '2026-09' ? 'Septiembre' : 'Agosto'} · leads manuales incluidos · importes en {f.moneda === 'PEN' ? 'soles' : 'dólares'}</p></div><Button variant="ghost" onClick={exportar} disabled={!filas.length}><Download aria-hidden />Exportar</Button></div>
              {tramo && <div className="ca-aclaracion-semana"><CalendarDays aria-hidden /><span>{tramo.nombre}: <strong>{actividadSemana.length} citas, {actividadSemana.filter(c => c.estado === 'realizada').length} entrevistas.</strong> La tabla y la proyección conservan el acumulado mensual.</span></div>}
              {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- La región permite desplazar la tabla con el teclado. */}
              <div className="ca-scroll" role="region" aria-label="Avance mensual por analista" tabIndex={0}>
                <table className="ca-tabla ca-metas"><caption className="sr-only">Datos ficticios del mes. Entrevistas frente a 70%, conversión frente a 70%. El cierre es una estimación.</caption><thead><tr><th scope="col">Analista</th><th scope="col">Leads</th><th scope="col">Citas</th><th scope="col">Avance de citas<small>Meta mensual</small></th><th scope="col">Entrevistas<small>Objetivo 70%</small></th><th scope="col">Conversión<small>Objetivo 70%</small></th><th scope="col">Ticket del mes</th><th scope="col">Cierre proyectado</th></tr></thead><tbody>{filas.map(a => <tr key={a.id}><th scope="row"><button className="ca-nombre" onClick={() => setAnalista(a.id)}><span className="ca-avatar" aria-hidden>{a.iniciales}</span><span>{a.nombre}<small>{a.supervisor}</small></span><ChevronRight aria-hidden /></button></th><Celdas m={a.m} moneda={f.moneda} onDetalle={() => setAnalista(a.id)} /></tr>)}</tbody>{filas.length > 0 && <tfoot><tr><th scope="row">Total del equipo<small>{conBase.length} de {filas.length} con proyección</small></th><Celdas m={total} proyeccion={proyectado} parcial={conBase.length < filas.length} moneda={f.moneda} /></tr></tfoot>}</table>
              </div>
              {!filas.length && <div className="ca-vacio"><h3>No hay datos de ejemplo para esta consulta</h3><p>El ejemplo contiene septiembre de 2026 en soles.</p><Button variant="outline" onClick={() => setF(INICIAL)}>Volver al ejemplo</Button></div>}
              <div className="ca-pie ca-entre"><div className="ca-leyenda" aria-label="Significado de los colores"><span className="ca-leyenda-logro"><Check aria-hidden />Meta alcanzada</span><span><TrendingUp aria-hidden />A ritmo</span><span className="ca-leyenda-atencion"><TriangleAlert aria-hidden />Por mejorar</span><span className="ca-leyenda-prioridad"><CircleAlert aria-hidden />Prioridad</span><span><Minus aria-hidden />Sin base</span></div><button className="ca-enlace" onClick={() => setAyuda(true)}>Conversión por {base === 'personas' ? 'personas únicas' : 'entrevistas'} · propuesta<Info aria-hidden /></button></div>
            </section>
          </>}
        </div>
        <p className="ca-disclaimer">Vista para revisar la propuesta. Cifras ficticias y fórmulas de proyección pendientes de aprobación.</p>
        <p className="sr-only" role="status" aria-live="polite">{anuncio || `${filas.length} analistas en la consulta mensual. ${flujo.length} personas con inasistencias en el seguimiento.`}</p>
      </main>
    </div>
    <PanelLateral titulo="Cómo se calcula" abierto={ayuda} cerrar={() => setAyuda(false)}>
      <p className="ca-aclaracion">Esta vista usa datos ficticios. Puedes comparar aquí las dos bases de conversión; cambiarla no guarda una configuración en el CRM.</p>
      <Campo titulo="Base propuesta para la conversión"><Select aria-label="Base propuesta para la conversión" value={base} onChange={e => setBase(e.target.value as BaseConversion)}><option value="personas">Personas entrevistadas, una vez cada una</option><option value="entrevistas">Todas las entrevistas, incluidas repeticiones</option></Select></Campo>
      <div className="ca-ayuda"><section><h3>Qué indican los colores</h3><p>Azul con ✓: meta alcanzada. Ámbar con triángulo: resultado por debajo del objetivo, pero al menos a la mitad. Rojo con !: brecha de más de la mitad; abre el indicador para revisar el detalle. Gris con —: no hay base para evaluar.</p><p>En citas, antes del cierre se compara el avance con un ritmo diario orientativo. Al día 13, la referencia es 43,3%: un avance de 50% está a ritmo y no se marca como retraso. La línea en la barra señala esa referencia; la meta mensual no cambia. El indicador pasa a azul con ✓ cuando alcanza el 100%.</p><p>Ticket y proyección se muestran sin semáforo: todavía no tienen una meta monetaria. La conversión del recorrido tampoco se compara con el 70%, porque utiliza otra población.</p></section><section><h3>Citas y avance</h3><p>Cuentan todas las citas registradas hasta el corte. La base incluye los leads del mes, incluso los manuales y quienes todavía no tienen citas. El avance compara la cantidad conseguida con la meta interna de Superadmin.</p></section><section><h3>Entrevistas · objetivo 70%</h3><p>Entrevistas / citas con resultado de asistencia o inasistencia. Cada visita cuenta. Las citas futuras y sin resultado se muestran en Bandeja y no entran en esta tasa.</p></section><section><h3>Conversión · objetivo 70%</h3><p>Clientes convertidos después de asistir / {base === 'personas' ? 'personas distintas entrevistadas' : 'total de entrevistas realizadas'}. Una conversión cuenta una sola vez, aunque la persona haya asistido varias veces.</p><p>Por ejemplo, Ana tiene 70 entrevistas de 60 personas y 42 clientes: 70% sobre personas o 60% sobre entrevistas. Esta base está propuesta para que la revisemos.</p></section><section><h3>Ticket y proyección del mes</h3><p>Ticket = importe real del mes / clientes del mes. La proyección extiende el ritmo actual al cierre, aplica tasas observadas y limita las personas esperadas a los leads de la consulta. Sin conversiones no se inventa un ticket.</p><p>El total suma las proyecciones de los analistas que tienen base y lo indica cuando es parcial. No promedia porcentajes ni mezcla monedas.</p></section><section><h3>Mes y semanas</h3><p>El mes y los filtros de equipo se aplican a todos los bloques. La semana selecciona las citas del recorrido, la bandeja y la agenda. El avance y la proyección permanecen mensuales; mostramos aparte la actividad de la semana.</p></section><section><h3>Tu control de Superadmin</h3><p>La integración permitirá configurar metas, reglas y vigencia con historial. Esta propuesta visual todavía no activa ni modifica esa configuración.</p></section></div>
    </PanelLateral>
    <PanelLateral titulo={analista ? analistaNombre(analista) : 'Detalle del analista'} abierto={!!analista} cerrar={() => setAnalista(null)}>{analista && <DatosAnalista key={`${analista}-${base}`} personas={personas.filter(p => p.analista === analista)} base={base} />}</PanelLateral>
    <PanelLateral titulo={persona?.nombre ?? 'Detalle de persona'} abierto={!!persona} cerrar={() => setPersona(null)}>{persona && <HistorialPersona persona={persona} />}</PanelLateral>
  </div>
}

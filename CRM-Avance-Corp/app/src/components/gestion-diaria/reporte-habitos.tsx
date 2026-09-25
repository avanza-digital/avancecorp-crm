/* oxlint-disable jsx-a11y/no-redundant-roles, jsx-a11y/no-interactive-element-to-noninteractive-role -- Conserva la semántica de tabla en WebKit al apilar celdas. */
import { useId, useRef, useState } from 'react'
import { ArrowDown, ArrowUp, ArrowRight, Info, Search } from 'lucide-react'
import { horaLimaDe } from '@/lib/gestion-diaria-analista'
import { cifraPulso, type EquipoPulso } from '@/lib/gestion-diaria-pulso'
import type { HabitosGerencia, PersonaHabitos } from '@/lib/gestion-diaria-habitos'
import { hashDe } from '@/lib/router'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Button } from '@/components/ui/button'
import { Dialog, DialogHeader, DialogTitle, DialogBody } from '@/components/ui/dialog'
import { PanelGerencia } from './panel-gerencia'

const ESTADO_CORTE = { pendiente: 'Aún pendiente', sin_cartera: 'Sin cartera', cumplido: 'A tiempo', recuperado: 'Recuperado', incumplido: 'Incumplido' } as const
function cortesDelDia(d: PersonaHabitos['dias'][number]) {
  if (d.cortes.estado !== 'activo') return d.cortes.estado === 'no_laborable' ? 'No laborable' : 'Desactivados'
  return [d.cortes.primer_corte, d.cortes.segundo_corte].filter((c) => c !== null).map((c, i) => `${i + 1}. ${ESTADO_CORTE[c.estado]}`).join(' · ') || 'Sin cortes programados'
}

type Orden = 'nombre' | 'llamadas' | 'contacto' | 'mediana' | 'cortes'
const COLUMNAS: { orden: Orden; titulo: string }[] = [
  { orden: 'nombre', titulo: 'Analista' }, { orden: 'llamadas', titulo: 'Llamadas' },
  { orden: 'contacto', titulo: 'Contacto' }, { orden: 'mediana', titulo: 'Mediana diaria' }, { orden: 'cortes', titulo: 'Cortes a tiempo' },
]
function valor(p: PersonaHabitos, orden: Exclude<Orden, 'nombre'>) {
  switch (orden) {
    case 'llamadas': return p.resumen.llamadas
    case 'contacto': return p.resumen.tasa_contacto
    case 'mediana': return p.distribucion_contacto.mediana
    case 'cortes': return p.cumplimiento.evaluables ? p.cumplimiento.cumplidos_a_tiempo / p.cumplimiento.evaluables : null
  }
}

export function ReporteHabitos({ datos, equipos, estrecho, alAbrirAnalista }: {
  datos: HabitosGerencia; equipos: EquipoPulso[]; estrecho: boolean; alAbrirAnalista: () => void
}) {
  const [busqueda, setBusqueda] = useState('')
  const [equipo, setEquipo] = useState('todos')
  const [orden, setOrden] = useState<Orden>('nombre')
  const [ascendente, setAscendente] = useState(true)
  const [seleccion, setSeleccion] = useState<string | null>(null)
  const [ampliado, setAmpliado] = useState(false)
  const [info, setInfo] = useState(false)
  const titulo = useRef<HTMLHeadingElement>(null)
  const tituloTabla = useRef<HTMLHeadingElement>(null)
  const origen = useRef<HTMLElement | null>(null)
  const id = useId()
  const equipoDe = (p: PersonaHabitos) => p.supervisor_id === null ? 'sin-equipo' : equipos.some((e) => e.supervisor_id === p.supervisor_id) ? p.supervisor_id : 'desconocido'
  const nombreEquipo = (p: PersonaHabitos) => p.supervisor_id === null ? 'Sin equipo asignado' : equipos.find((e) => e.supervisor_id === p.supervisor_id)?.nombre ?? 'Equipo no disponible'
  const opciones = [...new Set(datos.personas.map(equipoDe))].map((clave) => ({ clave, nombre: nombreEquipo(datos.personas.find((p) => equipoDe(p) === clave)!) }))
  const filas = datos.personas.filter((p) => p.nombre_completo.toLocaleLowerCase('es').includes(busqueda.trim().toLocaleLowerCase('es')) && (equipo === 'todos' || equipoDe(p) === equipo))
    .toSorted((a, b) => {
      const nombre = a.nombre_completo.localeCompare(b.nombre_completo, 'es')
      if (orden === 'nombre') return nombre * (ascendente ? 1 : -1)
      const va = valor(a, orden), vb = valor(b, orden)
      if (va === null || vb === null) return va === vb ? nombre : va === null ? 1 : -1
      return (va - vb) * (ascendente ? 1 : -1) || nombre
    })
  const persona = datos.personas.find((p) => p.analista_id === seleccion)
  const cerrar = () => {
    setSeleccion(null); setAmpliado(false)
    requestAnimationFrame(() => {
      const destino = origen.current?.isConnected ? origen.current : tituloTabla.current
      destino?.focus({ preventScroll: true })
      if (document.activeElement !== destino) tituloTabla.current?.focus({ preventScroll: true })
    })
  }
  return <section aria-label="Reporte de hábitos" className="gp-habitos">
    <div className="gp-habitos-contexto">
      <div><strong>{datos.desde} al {datos.hasta}</strong> · {datos.dias_incluidos} días calendario{datos.dias_incluidos < datos.dias_solicitados ? ' (histórico disponible)' : ''}
        <p>Contacto de la operación: <strong>{cifraPulso(datos.operacion.tasa_contacto, true)}</strong> · {datos.operacion.contestadas} de {datos.operacion.utiles} útiles.</p></div>
      <Button variant="ghost" className="min-h-11 text-base" onClick={() => setInfo(true)}><Info aria-hidden />Cómo leer los hábitos</Button>
    </div>
    <div className="gd-espacio gp-espacio" data-estrecho={estrecho}>
      <section className="gd-equipo" aria-label="Comparación de hábitos">
        <div className="gp-tabla-cabecera"><h3 ref={tituloTabla} tabIndex={-1}>Hábitos por analista</h3><span>{datos.personas.length} analistas</span></div>
        <div className="gd-filtros gp-filtros">
          <div className="gd-busqueda"><Search aria-hidden /><Input type="search" aria-label="Buscar analista en hábitos" placeholder="Buscar analista" className="min-h-11 pl-9 text-base" value={busqueda} onChange={(e) => setBusqueda(e.target.value)} /></div>
          <Select aria-label="Equipo en hábitos" className="min-h-11 text-base" value={equipo} onChange={(e) => setEquipo(e.target.value)}><option value="todos">Todos los equipos</option>{opciones.map((e) => <option key={e.clave} value={e.clave}>{e.nombre}</option>)}</Select>
          <span className="gd-conteo">{filas.length} resultados</span>
        </div>
        {persona && !filas.includes(persona) && <p className="gd-seleccion-oculta">La selección no aparece con los filtros actuales.</p>}
        <div className="gd-tabla-scroll ac-scroll"><table role="table" className="gp-tabla gp-tabla-habitos" aria-label="Comparación de hábitos por analista">
          <thead role="rowgroup"><tr role="row">{COLUMNAS.map((c) => <th role="columnheader" scope="col" key={c.orden} aria-sort={orden === c.orden ? ascendente ? 'ascending' : 'descending' : 'none'}>
            <button type="button" onClick={() => { setOrden(c.orden); setAscendente(orden === c.orden ? !ascendente : c.orden === 'nombre') }} aria-label={`Ordenar hábitos por ${c.titulo.toLocaleLowerCase('es')}`}>{c.titulo}{orden === c.orden && (ascendente ? <ArrowUp aria-hidden /> : <ArrowDown aria-hidden />)}</button>
          </th>)}</tr></thead>
          <tbody role="rowgroup">
            {filas.length === 0 && <tr role="row"><td role="cell" colSpan={5}>{datos.personas.length ? 'Ningún analista coincide con estos filtros.' : 'No hay analistas activos en el organigrama actual.'}</td></tr>}
            {filas.map((p) => <tr role="row" key={p.analista_id} data-activa={seleccion === p.analista_id}>
              <th role="rowheader" scope="row"><div className="gp-persona"><button type="button" className="gp-nombre" aria-label={`Ver hábitos de ${p.nombre_completo}`} aria-controls={id} aria-current={seleccion === p.analista_id ? 'true' : undefined} onClick={(e) => { origen.current = e.currentTarget; setSeleccion(p.analista_id) }}><span>{p.nombre_completo}</span><span className="gp-metadato">{nombreEquipo(p)}</span></button>
                {seleccion === p.analista_id && <button type="button" className="gp-ir-detalle" aria-label={`Ir al detalle de hábitos de ${p.nombre_completo}`} onClick={() => titulo.current?.focus()}><ArrowRight aria-hidden /></button>}</div></th>
              <td role="cell" data-etiqueta="Llamadas">{p.resumen.llamadas}</td>
              <td role="cell" data-etiqueta="Contacto">{cifraPulso(p.resumen.tasa_contacto, true)}<p>{p.resumen.contestadas}/{p.resumen.utiles} útiles</p></td>
              <td role="cell" data-etiqueta="Mediana diaria">{cifraPulso(p.distribucion_contacto.mediana, true)}<p>{p.distribucion_contacto.dias_validos} días con muestra</p></td>
              <td role="cell" data-etiqueta="Cortes a tiempo">{p.cumplimiento.evaluables ? `${p.cumplimiento.cumplidos_a_tiempo} de ${p.cumplimiento.evaluables}` : 'Sin cortes evaluables'}</td>
            </tr>)}
          </tbody>
        </table></div>
      </section>
      <PanelGerencia id={id} etiqueta="Detalle de hábitos" titulo={persona?.nombre_completo ?? 'Detalle de hábitos'} abierto={Boolean(persona)} estrecho={estrecho} ampliado={ampliado} ampliar={() => setAmpliado((v) => !v)} cerrar={cerrar} tituloRef={titulo} vacio="Elige un analista para ver sus hábitos día a día y compararlos con su equipo.">
        {persona && <div className="gd-panel-cuerpo"><DetalleHabitos key={persona.analista_id} persona={persona} alAbrirAnalista={alAbrirAnalista} /></div>}
      </PanelGerencia>
    </div>
    <Dialog open={info} onClose={() => setInfo(false)} className="gp-definiciones"><DialogHeader><DialogTitle>Cómo leer los hábitos</DialogTitle></DialogHeader><DialogBody><div className="space-y-4 text-base">
      <p>Equipo y cartera de referencia actuales. Los cortes usan la política vigente en cada fecha.</p>
      <p>Estos datos orientan la capacitación; no explican las causas de una pausa.</p>
      <p>La alerta de tasa muy baja sigue apagada. No se ha fijado un umbral.</p>
      <p>La tasa de contacto reúne contestadas y útiles del período; no promedia los porcentajes diarios. La mediana y la mitad central usan sólo días con muestra suficiente.</p>
      <p>Los cortes se ordenan por la proporción cumplida a tiempo entre los evaluables. Los pendientes y sin cartera se muestran en el detalle.</p>
      <Button variant="outline" className="min-h-11 text-base" onClick={() => setInfo(false)}>Cerrar explicación</Button>
    </div></DialogBody></Dialog>
  </section>
}

function DetalleHabitos({ persona: p, alAbrirAnalista }: { persona: PersonaHabitos; alAbrirAnalista: () => void }) {
  return <article>
    <div className="gp-cabecera-fila"><p>{p.resumen.llamadas} llamadas en el período</p><a href={hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'analista', id: p.analista_id })} onClick={(e) => { if (!e.ctrlKey && !e.metaKey && !e.shiftKey && !e.altKey) alAbrirAnalista() }}>Ver pulso y registro</a></div>
      <dl className="gp-habitos-resumen">
        <div><dt>Contacto personal</dt><dd>{cifraPulso(p.resumen.tasa_contacto, true)}</dd><p>{p.resumen.contestadas} de {p.resumen.utiles} útiles</p></div>
        <div><dt>Contacto del equipo</dt><dd>{cifraPulso(p.equipo.tasa_contacto, true)}</dd><p>{p.equipo.utiles === null ? 'Sin equipo comercial asignado' : `${p.equipo.contestadas} de ${p.equipo.utiles} útiles`}</p></div>
        <div><dt>Distribución diaria</dt><dd>{p.distribucion_contacto.dias_validos ? `Mediana ${cifraPulso(p.distribucion_contacto.mediana, true)}` : 'Muestra insuficiente'}</dd><p>{p.distribucion_contacto.dias_validos} días con muestra suficiente</p>
          {p.distribucion_contacto.dias_validos > 0 && <p>Mitad central: {cifraPulso(p.distribucion_contacto.p25, true)} a {cifraPulso(p.distribucion_contacto.p75, true)}</p>}</div>
        <div><dt>Cortes a tiempo</dt><dd>{p.cumplimiento.evaluables ? `${p.cumplimiento.cumplidos_a_tiempo} de ${p.cumplimiento.evaluables}` : 'Sin cortes evaluables'}</dd><p>{p.cumplimiento.recuperados} recuperados · {p.cumplimiento.incumplidos} incumplidos</p><p>{p.cumplimiento.pendientes} pendientes · {p.cumplimiento.sin_cartera} sin cartera</p></div>
      </dl>
      <details className="gp-dias-habitos">
        <summary>Ver días de {p.nombre_completo}</summary>
        <div className="gp-tabla-scroll"><table role="table" className="gp-tabla" aria-label={`Hábitos diarios de ${p.nombre_completo}`}>
          <thead role="rowgroup"><tr role="row"><th role="columnheader" scope="col">Día</th><th role="columnheader" scope="col">Primera llamada</th><th role="columnheader" scope="col">Mayor hueco entre llamadas</th><th role="columnheader" scope="col">Contacto</th><th role="columnheader" scope="col">Cortes</th></tr></thead>
          <tbody role="rowgroup">{p.dias.map((d) => <tr role="row" key={d.dia}>
            <th role="rowheader" scope="row">{d.dia}</th>
            <td role="cell" data-etiqueta="Primera llamada">{horaLimaDe(d.primera_llamada_en)}{d.llamadas === 0 && <p>Sin llamadas</p>}</td>
            <td role="cell" data-etiqueta="Mayor hueco">{d.jornada.estado === 'no_laborable' ? 'No laborable' : d.jornada.hueco
              ? <>{cifraPulso(d.jornada.hueco.minutos)} min<p>{horaLimaDe(d.jornada.hueco.desde)}–{horaLimaDe(d.jornada.hueco.hasta)}</p></>
              : d.jornada.estado === 'no_iniciada' ? 'Jornada sin iniciar' : 'Menos de dos llamadas en jornada'}
              {d.jornada.estado !== 'no_laborable' && d.jornada.estado !== 'no_iniciada' && <p>Desde apertura: {cifraPulso(d.jornada.silencio_inicio_minutos)} min · hasta {horaLimaDe(d.jornada.observado_hasta)}: {cifraPulso(d.jornada.silencio_final_minutos)} min</p>}</td>
            <td role="cell" data-etiqueta="Contacto">{cifraPulso(d.tasa_contacto, true)}<p>{d.contestadas} de {d.utiles} útiles{d.utiles < d.minimo_llamadas_utiles ? ` · muestra insuficiente (mín. ${d.minimo_llamadas_utiles})` : ''}</p></td>
            <td role="cell" data-etiqueta="Cortes">{cortesDelDia(d)}</td>
          </tr>)}</tbody>
        </table></div>
        <p className="mt-3">Hora de Lima. El hueco requiere dos llamadas dentro de la jornada: 09–18 h; sábado 09–13 h. Los silencios de apertura y cierre se muestran aparte; el día en curso llega hasta la consulta.</p>
      </details>
  </article>
}

/* oxlint-disable jsx-a11y/no-redundant-roles, jsx-a11y/no-interactive-element-to-noninteractive-role -- Conserva la semántica de tabla en WebKit al apilar celdas. */
/* oxlint-disable jsx-a11y/no-noninteractive-tabindex -- La región permite desplazar las columnas con el teclado. */
import { useState } from 'react'
import { ArrowDown, ArrowUp, ListFilter, Search } from 'lucide-react'
import { cifraPulso, type EquipoPulso } from '@/lib/gestion-diaria-pulso'
import { hashDe } from '@/lib/router'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'

type Orden = 'nombre' | 'llamadas' | 'contacto' | 'sin_actividad' | 'vencidas' | 'primer_intento' | 'dispersion'
const COLUMNAS: { orden: Orden; titulo: string }[] = [
  { orden: 'nombre', titulo: 'Equipo' }, { orden: 'llamadas', titulo: 'Llamadas' },
  { orden: 'contacto', titulo: 'Contacto' }, { orden: 'sin_actividad', titulo: 'Sin actividad' },
  { orden: 'vencidas', titulo: 'Vencidas' }, { orden: 'primer_intento', titulo: 'Primer intento vencido' },
  { orden: 'dispersion', titulo: 'Dispersión de contacto' },
]
function valor(e: EquipoPulso, orden: Exclude<Orden, 'nombre'>) {
  switch (orden) {
    case 'llamadas': return e.metricas.llamadas
    case 'contacto': return e.metricas.tasa_contacto
    case 'sin_actividad': return e.metricas.sin_actividad
    case 'vencidas': return e.tareas_vencidas
    case 'primer_intento': return e.primer_intento_vencido
    case 'dispersion': return e.dispersion.maximo === null || e.dispersion.minimo === null ? null : e.dispersion.maximo - e.dispersion.minimo
  }
}

export function ComparacionEquiposGerencia({ equipos, abrir }: { equipos: EquipoPulso[]; abrir: (equipo: EquipoPulso, origen: HTMLElement) => void }) {
  const [busqueda, setBusqueda] = useState('')
  const [atencion, setAtencion] = useState(false)
  const [orden, setOrden] = useState<Orden>('nombre')
  const [ascendente, setAscendente] = useState(true)
  const conAtencion = equipos.filter((e) => e.metricas.sin_actividad > 0 || e.tareas_vencidas > 0 || (e.primer_intento_vencido ?? 0) > 0)
  const filas = equipos.filter((e) => e.nombre.toLocaleLowerCase('es').includes(busqueda.trim().toLocaleLowerCase('es'))
    && (!atencion || conAtencion.includes(e)))
    .toSorted((a, b) => {
      const nombre = a.nombre.localeCompare(b.nombre, 'es')
      if (orden === 'nombre') return nombre * (ascendente ? 1 : -1)
      const va = valor(a, orden), vb = valor(b, orden)
      if (va === null || vb === null) return va === vb ? nombre : va === null ? 1 : -1
      return (va - vb) * (ascendente ? 1 : -1) || nombre
    })
  return <>
    <div className="gd-filtros gp-filtros">
      <div className="gd-busqueda"><Search aria-hidden /><Input type="search" aria-label="Buscar equipo" placeholder="Buscar equipo" className="min-h-11 pl-9 text-base" value={busqueda} onChange={(e) => setBusqueda(e.target.value)} /></div>
      <Button variant={atencion ? 'default' : 'outline'} className="min-h-11 text-base" aria-pressed={atencion} onClick={() => setAtencion(!atencion)}><ListFilter aria-hidden />Con atención ({conAtencion.length})</Button>
      <span className="gd-conteo">{filas.length} de {equipos.length} equipos</span>
    </div>
    <div className="gd-tabla-scroll ac-scroll" tabIndex={0} role="region" aria-label="Desplazar tabla de equipos"><table role="table" className="gp-tabla gp-tabla-equipos" aria-label="Resumen por supervisor">
      <thead role="rowgroup"><tr role="row">{COLUMNAS.map((c) => <th role="columnheader" scope="col" key={c.orden} aria-sort={orden === c.orden ? ascendente ? 'ascending' : 'descending' : 'none'}>
        <button type="button" onClick={() => { setOrden(c.orden); setAscendente(orden === c.orden ? !ascendente : c.orden === 'nombre') }} aria-label={`Ordenar equipos por ${c.titulo.toLocaleLowerCase('es')}`}>
          {c.titulo}{orden === c.orden && (ascendente ? <ArrowUp aria-hidden /> : <ArrowDown aria-hidden />)}
        </button>
      </th>)}</tr></thead>
      <tbody role="rowgroup">
        {filas.length === 0 && <tr role="row"><td role="cell" colSpan={7} className="gd-sin-filas">Ningún equipo coincide con estos filtros.</td></tr>}
        {filas.map((e) => <tr role="row" key={e.clave}>
          <th role="rowheader" scope="row"><a className="gp-nombre" aria-label={e.nombre} href={hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'equipo', id: e.clave })} onClick={(evento) => {
            if (!evento.ctrlKey && !evento.metaKey && !evento.shiftKey && !evento.altKey) { evento.preventDefault(); abrir(e, evento.currentTarget) }
          }}><span>{e.nombre}</span><span className="gp-metadato">{e.metricas.analistas_activos} analistas activos</span></a></th>
          <td role="cell" data-etiqueta="Llamadas">{e.metricas.llamadas}</td>
          <td role="cell" data-etiqueta="Contacto">{cifraPulso(e.metricas.tasa_contacto, true)}<p>{e.metricas.contestadas}/{e.metricas.utiles} útiles</p></td>
          <td role="cell" data-etiqueta="Sin actividad">{e.metricas.sin_actividad}</td>
          <td role="cell" data-etiqueta="Vencidas" className={e.tareas_vencidas ? 'text-[var(--danger-text)] font-semibold' : ''}>{e.tareas_vencidas}</td>
          <td role="cell" data-etiqueta="Primer intento vencido">{cifraPulso(e.primer_intento_vencido)}{e.primer_intento_vencido === null && <p>SLA no activo</p>}</td>
          <td role="cell" data-etiqueta="Dispersión de contacto">{e.dispersion.personas ? <>{cifraPulso(e.dispersion.minimo, true)}–{cifraPulso(e.dispersion.maximo, true)}<p>{e.dispersion.personas} con muestra</p></> : 'Muestra insuficiente'}</td>
        </tr>)}
      </tbody>
    </table></div>
  </>
}

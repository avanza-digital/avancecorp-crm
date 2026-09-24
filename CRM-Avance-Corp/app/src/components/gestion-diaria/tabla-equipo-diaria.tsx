import { ArrowDown, ArrowUp, ArrowRight } from 'lucide-react'
import { COLOR_NIVEL, ETIQUETA_NIVEL, textoTasa } from '@/lib/gestion-diaria-analista'
import { MOTIVOS_EQUIPO, type FilaEquipoPresentada, type FiltrosEquipo, type OrdenEquipo } from '@/lib/gestion-diaria-equipo'

const COLUMNAS: { orden: OrdenEquipo; titulo: string }[] = [
  { orden: 'nombre', titulo: 'Analista' }, { orden: 'llamadas', titulo: 'Llamadas' },
  { orden: 'contacto', titulo: 'Contacto' }, { orden: 'pendientes', titulo: 'Pendientes' },
  { orden: 'vencidas', titulo: 'Vencidas' }, { orden: 'atencion', titulo: 'Atención' },
]

/** Una tabla semántica; en contenedores estrechos sus celdas llevan rótulos. */
export function TablaEquipoDiaria({ filas, filtros, ordenar, seleccion, seleccionar, panelId, irAlDetalle, minimo }: {
  filas: readonly FilaEquipoPresentada[]
  filtros: FiltrosEquipo
  ordenar: (orden: OrdenEquipo) => void
  seleccion: string | null
  seleccionar: (fila: FilaEquipoPresentada) => void
  panelId: string
  irAlDetalle: () => void
  minimo: number
}) {
  return (
    <div className="gd-tabla-scroll ac-scroll">
      <table aria-label="Actividad y pendientes por analista" className="gd-tabla">
        <colgroup>{COLUMNAS.map((c) => <col key={c.orden} className={`gd-col-${c.orden}`} />)}</colgroup>
        <thead><tr>{COLUMNAS.map((c) => (
          <th key={c.orden} scope="col" aria-sort={filtros.orden === c.orden ? filtros.ascendente ? 'ascending' : 'descending' : 'none'}>
            <button type="button" onClick={() => ordenar(c.orden)} aria-label={`Ordenar por ${c.titulo.toLocaleLowerCase('es')}`}>
              {c.titulo}{filtros.orden === c.orden && (filtros.ascendente ? <ArrowUp aria-hidden /> : <ArrowDown aria-hidden />)}
            </button>
          </th>
        ))}</tr></thead>
        <tbody>
          {filas.length === 0 && <tr><td colSpan={6} className="gd-sin-filas">Ningún analista coincide con estos filtros.</td></tr>}
          {filas.map((f) => {
            const activa = f.analista_id === seleccion
            const sinMuestra = f.marcador.nivel === null
            const contacto = f.marcador.utiles === 0 ? '—' : sinMuestra ? 'Sin muestra' : `${f.marcador.tasa_contacto_pct} %`
            const contextoContacto = f.marcador.utiles === 0 ? 'Sin llamadas útiles' : `${textoTasa(f.marcador)}; ${f.marcador.contestadas} de ${f.marcador.utiles} útiles; mínimo ${minimo}${sinMuestra ? '; sin muestra suficiente' : `; nivel ${ETIQUETA_NIVEL[f.marcador.nivel!]}`}`
            return (
              <tr key={f.analista_id} data-analista={f.analista_id} data-activa={activa}>
                <th scope="row" className="gd-nombre"><div>
                  <button type="button" aria-label={`Seleccionar a ${f.nombre_completo}`} aria-current={activa ? 'true' : undefined}
                    aria-controls={panelId} onClick={() => seleccionar(f)}>{f.nombre_completo}</button>
                  {activa && <button type="button" className="gd-ir-detalle" aria-label={`Ir al detalle de ${f.nombre_completo}`} onClick={irAlDetalle}><ArrowRight aria-hidden /></button>}
                </div></th>
                <td data-etiqueta="Llamadas">{f.marcador.llamadas}</td>
                <td data-etiqueta="Contacto"><span style={f.marcador.nivel ? { color: COLOR_NIVEL[f.marcador.nivel] } : undefined}><span aria-hidden>{contacto}{f.marcador.nivel && <span className="gd-nivel-contacto">{ETIQUETA_NIVEL[f.marcador.nivel]}</span>}</span><span className="sr-only">{contextoContacto}</span></span></td>
                <td data-etiqueta="Pendientes">{f.tareas_pendientes}</td>
                <td data-etiqueta="Vencidas"><span className={f.tareas_vencidas > 0 ? 'text-[var(--danger-text)] font-semibold' : ''}>{f.tareas_vencidas}</span></td>
                <td data-etiqueta="Atención"><span className={f.requiere_atencion ? 'gd-motivos' : 'text-[var(--muted-foreground-strong)]'}>
                  {f.motivos_atencion.length ? `${f.motivos_atencion.length} ${f.motivos_atencion.length === 1 ? 'motivo' : 'motivos'}` : f.gestiones_hoy === 0 ? 'Sin registro' : 'Sin alertas'}
                  {f.motivos_atencion.length > 0 && <span className="sr-only">: {f.motivos_atencion.map((m) => MOTIVOS_EQUIPO[m]).join('; ')}</span>}
                </span></td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}

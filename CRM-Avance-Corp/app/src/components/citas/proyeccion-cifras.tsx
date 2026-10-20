// Cifras de la Proyección: la misma pieza en la celda de la hoja (escritorio) y
// en la tarjeta (celular). Todo número se abre en su lista; un 0 o «—» no es botón.
import { numero } from '@/lib/format'
import { cn } from '@/lib/utils'
import type { ColumnaNumerica, MetricasProyeccion } from './proyeccion'
import { ORIGEN_DE_COLUMNA, etiquetaCitas, type AbrirLista } from './proyeccion-columnas'
import type { TramoProyeccion } from './proyeccion-rango'
import { SenalMetrica } from './senal-resultado'

export interface ObjetivosProyeccion { entrevistas: number; conversion: number }
const soles = (valor: number | null) => valor === null ? '—' : `S/ ${numero(valor)}`

/** Cifra que se abre: un 0 no es botón. */
function Cifra({ cantidad, texto, etiqueta, onAbrir, dinero = false }: { cantidad: number; texto: string; etiqueta: string; onAbrir: () => void; dinero?: boolean }) {
  const contenido = dinero && texto.startsWith('S/ ') ? <><span className="pc-m" aria-hidden>S/</span>{texto.slice(3)}</> : texto
  if (!cantidad) return <span className="pc-n pc-cero">{contenido}</span>
  return <button type="button" className="pc-n" aria-label={`${texto} ${etiqueta}`} onClick={onAbrir}>{contenido}</button>
}

/** Ticket cita y Proyectado citas: se calculan con las citas con lead y abren esa lista (Codex 19/10: «todo número se abre»); «—» sin base. */
function Derivada({ valor, etiqueta, base, onAbrir }: { valor: number | null; etiqueta: string; base: number; onAbrir: () => void }) {
  if (valor === null) return <span className={cn('pc-n', 'pc-cero')}>—</span>
  return <Cifra cantidad={base} texto={soles(valor)} etiqueta={etiqueta} onAbrir={onAbrir} dinero />
}

/** La cifra de una columna para una fila (`nombre`: el analista o «todos los analistas»). */
export function CifraColumna({ columna, m, nombre, objetivos, abrir }: {
  columna: ColumnaNumerica; m: MetricasProyeccion; nombre: string; objetivos: ObjetivosProyeccion; abrir: AbrirLista
}) {
  const de = `de ${nombre}`
  switch (columna) {
    case 'citas': return <Cifra cantidad={m.citas.length} texto={numero(m.citas.length)} etiqueta={`${etiquetaCitas('citas', m.citas.length)} ${de}`} onAbrir={() => abrir('citas')} />
    case 'monto': return <Cifra cantidad={m.conMonto.length} texto={m.pendienteTc ? 'Pendiente de TC' : m.conMonto.length ? soles(m.monto) : '—'} etiqueta={`en citas ${de}`} onAbrir={() => abrir('monto')} dinero />
    case 'ticket': return <Derivada valor={m.ticket} base={m.citasConLead.length} etiqueta={`de ticket cita ${de}`} onAbrir={() => abrir('conLead')} />
    case 'entrevistas': return <SenalMetrica valor={m.pctEntrevistas} objetivo={objetivos.entrevistas} etiqueta={`% Entrev. ${de}`} abrir={m.entrevistas.length ? () => abrir('entrevistas') : undefined} />
    case 'conversion': return <SenalMetrica valor={m.pctConversion} objetivo={objetivos.conversion} etiqueta={`% Conv. ${de}`} abrir={m.convertidas.length ? () => abrir('conversion') : undefined} />
    case 'proyectado': return <Derivada valor={m.proyectado} base={m.citasConLead.length} etiqueta={`proyectado en citas ${de}`} onAbrir={() => abrir('conLead')} />
    default: {
      const origen = ORIGEN_DE_COLUMNA[columna]!
      const n = m[columna].length
      return <Cifra cantidad={n} texto={numero(n)} etiqueta={`${etiquetaCitas(origen, n)} ${de}`} onAbrir={() => abrir(origen)} />
    }
  }
}

/** Citas de una columna de tiempo (`i`: su posición en los tramos de la hoja). */
export function CifraTramo({ m, i, tramo, nombre, abrir }: { m: MetricasProyeccion; i: number; tramo: TramoProyeccion; nombre: string; abrir: AbrirLista }) {
  const n = m.porTramo[i]?.length ?? 0
  return <Cifra cantidad={n} texto={numero(n)} etiqueta={`${etiquetaCitas('citas', n)} de ${nombre}, ${tramo.rotulo}`} onAbrir={() => abrir('citas', tramo.id)} />
}

/** Título de una columna de tiempo: «S2» sobre «8–14» o «19» sobre «lun»; el lector oye «S2 8–14 oct» o «lun 19 oct». */
export function CabeceraTramo({ tramo }: { tramo: TramoProyeccion }) {
  // Cada palabra del detalle va entera: si no cabe, solo baja el mes («22–30» / «set»).
  return <><span className="pc-tiempo-cab" aria-hidden>{tramo.titulo}<small>{tramo.detalle.split(' ').flatMap((parte, i) =>
    i ? [' ', <span key={i}>{parte}</span>] : [<span key={i}>{parte}</span>])}</small></span><span className="sr-only">{tramo.nombre}</span></>
}

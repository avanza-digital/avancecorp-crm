// Proyección en el celular (< 768 px): la hoja no cabe en un teléfono, así que
// cada analista es una tarjeta con las mismas cifras, en el mismo orden y con los
// mismos embudos. El Total va PRIMERO: en escritorio la fila Σ queda fija a la
// vista; en el celular, arriba es donde se ve sin recorrer todas las tarjetas.
// Las columnas de tiempo van en una fila que se desplaza dentro de la tarjeta:
// así cada tarjeta mide lo mismo con 3 semanas que con 31 días.
import type { Ref } from 'react'
import { ArrowDownWideNarrow, ArrowUpNarrowWide, Filter } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { DropdownItem, DropdownMenu } from '@/components/ui/dropdown-menu'
import { Select } from '@/components/ui/select'
import { numero } from '@/lib/format'
import type { ColumnaProyeccion, HojaProyeccion, MetricasProyeccion, OrdenProyeccion } from './proyeccion'
import { CIFRAS, COLUMNAS, claseTramo, type AbrirLista } from './proyeccion-columnas'
import { CabeceraTramo, CifraColumna, CifraTramo, type ObjetivosProyeccion } from './proyeccion-cifras'
import type { TiempoProyeccion, TramoProyeccion } from './proyeccion-rango'

function Tarjeta({ m, marca, nombre, para, supervisor, objetivos, tramos, vista, abrir }: {
  m: MetricasProyeccion; marca: string; nombre: string
  /** Cómo se nombra la fila en cada cifra: el analista o «todos los analistas». */
  para: string; supervisor?: string | undefined
  objetivos: ObjetivosProyeccion; tramos: readonly TramoProyeccion[]; vista: TiempoProyeccion; abrir: AbrirLista
}) {
  return <div role="listitem" className="pc-tarjeta" data-total={marca === 'Σ' || undefined}>
    <div className="pc-tarjeta-cab">
      <span className="pc-tarjeta-n" aria-hidden>{marca}</span>
      <p className="pc-tarjeta-nombre">{nombre}</p>
      {supervisor && <p className="pc-tarjeta-sup">{supervisor}</p>}
    </div>
    {tramos.length > 0 && (
      // Sin citas no hay botones que lleven el foco: la fila se alcanza con Tab para desplazarla.
      // oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex
      <div className="pc-tarjeta-tramos" role="group" aria-label={`Citas por ${vista === 'dias' ? 'día' : 'semana'} de ${para}`} tabIndex={m.citas.length ? undefined : 0}>
        {tramos.map((t, i) => <div key={t.id} className={claseTramo(t)}><CabeceraTramo tramo={t} /><CifraTramo m={m} i={i} tramo={t} nombre={para} abrir={abrir} /></div>)}
      </div>
    )}
    <dl className="pc-tarjeta-cifras">
      {CIFRAS.map(col => <div key={col.id} data-col={col.id}><dt>{col.corto}</dt>
        <dd><CifraColumna columna={col.id} m={m} nombre={para} objetivos={objetivos} abrir={abrir} /></dd></div>)}
    </dl>
  </div>
}

export function TarjetasProyeccion({ hoja, rotulo, objetivos, vista, abrirDe, listaRef }: {
  hoja: HojaProyeccion; rotulo: string; objetivos: ObjetivosProyeccion; vista: TiempoProyeccion
  /** Las listas de una fila (`null`: el Total). */
  abrirDe: (filaId: string | null) => AbrirLista
  listaRef: Ref<HTMLDivElement>
}) {
  const n = hoja.filas.length
  return <div ref={listaRef} role="list" tabIndex={-1} className="pc-tarjetas" aria-label={`Proyección de citas por analista · ${rotulo}`}>
    <Tarjeta m={hoja.total} marca="Σ" nombre={`Total · ${numero(n)} ${n === 1 ? 'analista' : 'analistas'}`} para="todos los analistas"
      objetivos={objetivos} tramos={hoja.tramos} vista={vista} abrir={abrirDe(null)} />
    {hoja.filas.map((f, i) => <Tarjeta key={f.id} m={f} marca={String(i + 1)} nombre={f.nombre} para={f.nombre} supervisor={f.supervisor}
      objetivos={objetivos} tramos={hoja.tramos} vista={vista} abrir={abrirDe(f.id)} />)}
  </div>
}

/** En tarjetas no hay cabeceras: el orden y los embudos de columna se ofrecen aquí, sobre el mismo estado de la hoja. */
export function ControlesTarjetas({ orden, onOrdenar, conFiltro, onFiltrar, filtrosRef }: {
  orden: OrdenProyeccion
  /** Como pulsar la cabecera: otra columna toma su sentido inicial; la misma lo invierte. */
  onOrdenar: (columna: ColumnaProyeccion) => void
  conFiltro: ReadonlySet<ColumnaProyeccion>
  onFiltrar: (columna: ColumnaProyeccion) => void
  filtrosRef: Ref<HTMLButtonElement>
}) {
  const texto = orden.columna === 'analista'
  const asc = orden.direccion === 'asc'
  const sentido = asc ? texto ? 'de A a Z' : 'de menor a mayor' : texto ? 'de Z a A' : 'de mayor a menor'
  const Icono = asc ? ArrowUpNarrowWide : ArrowDownWideNarrow
  return <div className="pc-controles" role="group" aria-label="Orden y filtros">
    <div className="pc-ordenar">
      <label className="pc-fecha">Ordenar por<Select aria-label="Ordenar por" className="h-8" value={orden.columna} onChange={e => onOrdenar(e.target.value as ColumnaProyeccion)}>
        {COLUMNAS.map(c => <option key={c.id} value={c.id}>{c.corto}</option>)}
      </Select></label>
      <Button variant="outline" size="icon" className="pc-sentido" aria-label={`Orden ${sentido}`} title={`Orden ${sentido}`} onClick={() => onOrdenar(orden.columna)}><Icono aria-hidden /></Button>
    </div>
    <DropdownMenu className="pc-filtros" menuClassName="pc-filtros-menu" trigger={
      <Button ref={filtrosRef} variant="outline" size="sm" aria-label={conFiltro.size ? `Filtros, ${conFiltro.size} con filtro` : 'Filtros'}>
        <Filter aria-hidden />Filtros{conFiltro.size > 0 && <span className="pc-filtros-n" aria-hidden>{conFiltro.size}</span>}
      </Button>}>
      {COLUMNAS.map(c => <DropdownItem key={c.id} onSelect={() => onFiltrar(c.id)}>{c.corto}{conFiltro.has(c.id) && <><span className="sr-only">, con filtro</span><span className="pc-con-filtro" aria-hidden>con filtro</span></>}</DropdownItem>)}
    </DropdownMenu>
  </div>
}

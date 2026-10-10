import { accionOperaciones, celdaDeColumna, nombreColumna, type ColumnaHoja, type crearFormatoCifras } from './presentacion'
import { valorCelda, type MallaFacturacion, type MetricaFacturacion } from '@/lib/facturacion'
import { numero } from '@/lib/format'

/** Misma malla y mismo ámbito que escritorio; no hay una segunda tabla escondida. */
export function TarjetasFacturacion({ malla, columnas, formato, metrica, seleccionados, onMarcar, onAbrir, onAbrirColumna, onAbrirConteo, onAbrirEquipo, onAbrirTotal, tituloTotal, tramo }: {
  malla: MallaFacturacion
  columnas: readonly ColumnaHoja[]
  formato: ReturnType<typeof crearFormatoCifras>
  metrica: MetricaFacturacion
  seleccionados: readonly string[]
  onMarcar: (id: string) => void
  onAbrir: (analistaId: string, supervisorId: string) => void
  onAbrirColumna: (analistaId: string, supervisorId: string, columna: ColumnaHoja) => void
  onAbrirConteo: (analistaId: string, supervisorId: string) => void
  onAbrirEquipo: (id: string, nombre: string, valor: number) => void
  onAbrirTotal: () => void
  tituloTotal: string
  tramo: string
}) {
  return <div className="facturacion-tarjetas space-y-5 p-3" role="region" tabIndex={-1} aria-label="Facturación por analista">
    {malla.grupos.map((grupo, indice) => {
      const inicio = malla.grupos.slice(0, indice).reduce((n, g) => n + g.analistas.length, 0)
      return <div key={grupo.id} className="space-y-2.5">
        <div className="flex flex-wrap items-center gap-2">
          <h3 className="text-base font-bold">{grupo.nombre}</h3>
          <span className="text-sm">{grupo.analistas.length} {grupo.analistas.length === 1 ? 'analista' : 'analistas'}</span>
          <button type="button" className="ml-auto min-h-11 rounded-lg border border-border bg-muted px-3 py-2 text-sm font-bold tabular-nums" aria-label={`Total del equipo de ${grupo.nombre}: ${formato(valorCelda(grupo.total, metrica))}${metrica === 'contratos' ? ' contratos' : ''}, ${accionOperaciones(grupo.total.contratos)}`} onClick={() => onAbrirEquipo(grupo.id, grupo.nombre, valorCelda(grupo.total, metrica))}>{formato(valorCelda(grupo.total, metrica))}</button>
        </div>
        <ul role="list" className="space-y-2.5">
          {grupo.analistas.map((analista, i) => {
            const total = formato(valorCelda(analista.total, metrica))
            const operaciones = `${numero(analista.total.contratos)} ${analista.total.contratos === 1 ? 'operación' : 'operaciones'}`
            const conVentas = columnas.filter((c) => {
              const celda = celdaDeColumna(malla, c, grupo.id, analista.id)
              return celda.capital !== 0 || celda.contratos !== 0
            })
            return <li key={analista.id} className="facturacion-tarjeta rounded-[14px] border border-border bg-card p-3.5">
              <button type="button" className="block min-h-11 w-full min-w-0 text-left text-base"
                title={`Ver ${tramo} de ${analista.nombre}`} aria-label={`Ver ${tramo} de ${analista.nombre}: total ${total}${metrica === 'contratos' ? ' contratos' : ''} en ${operaciones} — ver el desglose`}
                data-foco-clave={`facturacion-fila:${grupo.id}:${analista.id}`}
                onClick={() => onAbrir(analista.id, grupo.id)}>
                <span className="flex items-center gap-2.5">
                  <span className="text-sm tabular-nums">{inicio + i + 1}</span>
                  <span className="text-base font-semibold">{analista.nombre}</span>
                </span>
              </button>
              <div className="mt-2.5 flex flex-wrap gap-2">
                <button type="button" className="min-h-11 rounded-lg border border-border px-3 py-2 text-sm font-bold tabular-nums" aria-label={`Total de ${analista.nombre}: ${total}${metrica === 'contratos' ? ' contratos' : ''}, ${accionOperaciones(analista.total.contratos)}`} onClick={() => onAbrir(analista.id, grupo.id)}>{total}</button>
                <button type="button" className="min-h-11 rounded-lg border border-border px-3 py-2 text-sm" aria-label={`${operaciones} de ${analista.nombre}: ${accionOperaciones(analista.total.contratos)}`} onClick={() => onAbrirConteo(analista.id, grupo.id)}>{operaciones}</button>
              </div>
              {conVentas.length > 0 ? <>
                <p className="mt-3 text-sm font-semibold">{columnas[0]?.tipo ? 'Por tipo' : 'Días en que vendió'}</p>
                <div className="mt-1.5 flex flex-wrap gap-1.5">
                  {conVentas.map((c) => {
                    const celda = celdaDeColumna(malla, c, grupo.id, analista.id)
                    return <button key={c.clave} type="button"
                    className="min-h-11 rounded-lg border border-border bg-muted px-2.5 text-sm"
                    aria-label={`${analista.nombre}, ${nombreColumna(c)}: ${formato(valorCelda(celda, metrica))}${metrica === 'contratos' ? ' contratos' : ''}, ${accionOperaciones(celda.contratos)}`}
                    onClick={() => onAbrirColumna(analista.id, grupo.id, c)}>
                    {c.titulo} · {formato(valorCelda(celda, metrica))}
                  </button>})}
                </div>
              </> : <p className="mt-2.5 text-sm text-muted-foreground-strong">Sin ventas en este tramo.</p>}
              <label className="mt-2 inline-flex min-h-11 items-center gap-2 text-sm">
                <input type="checkbox" checked={seleccionados.includes(analista.id)} onChange={() => onMarcar(analista.id)}
                  aria-label={`Comparar a ${analista.nombre}`} /> Comparar
              </label>
            </li>
          })}
        </ul>
      </div>
    })}
    <div className="rounded-[14px] border border-border bg-muted p-3.5">
      <h3 className="text-base font-bold">{tituloTotal}</h3>
      <button type="button" className="mt-2 min-h-11 rounded-lg border border-border bg-card px-3 py-2 text-sm font-bold tabular-nums" aria-label={`${tituloTotal}: ${formato(valorCelda(malla.total, metrica))}${metrica === 'contratos' ? ' contratos' : ''}, ${accionOperaciones(malla.total.contratos)}`} onClick={onAbrirTotal}>{formato(valorCelda(malla.total, metrica))}</button>
    </div>
  </div>
}

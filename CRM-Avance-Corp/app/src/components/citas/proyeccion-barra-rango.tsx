// Barra de la Proyección: Desde–Hasta propios de la pestaña y atajos, con lo que
// la pestaña ponga antes (Supervisor) y después (columnas de tiempo y acciones),
// en una sola línea que se parte si no cabe. Un rango inválido no se aplica: se
// avisa y la hoja conserva el último válido.
import { useState, type ReactNode } from 'react'
import { Input } from '@/components/ui/input'
import { atajosRango, errorRango, rotuloRango, type RangoProyeccion } from './proyeccion-rango'

export function BarraRango({ rango, hoy, onRango, antes, children }: {
  rango: RangoProyeccion; hoy: string; onRango: (rango: RangoProyeccion) => void; antes?: ReactNode; children?: ReactNode
}) {
  const [borrador, setBorrador] = useState(rango)
  const [previo, setPrevio] = useState(rango)
  // Un cambio que llega de fuera (atajo, otro mes arriba) reemplaza lo escrito.
  if (previo.desde !== rango.desde || previo.hasta !== rango.hasta) { setPrevio(rango); setBorrador(rango) }
  const error = errorRango(borrador)
  function cambiar(cambio: Partial<RangoProyeccion>) {
    const siguiente = { ...borrador, ...cambio }
    setBorrador(siguiente)
    if (!errorRango(siguiente)) onRango(siguiente)
  }
  return <div className="pc-periodo" role="group" aria-label="Consulta de la proyección">
    {antes}
    <strong className="pc-rotulo" data-testid="pc-rotulo-rango">{rotuloRango(rango)}</strong>
    <label className="pc-fecha">Desde<Input type="date" className="h-8" value={borrador.desde} aria-invalid={Boolean(error)} aria-describedby={error ? 'pc-rango-error' : undefined} onChange={e => cambiar({ desde: e.target.value })} /></label>
    <label className="pc-fecha">Hasta<Input type="date" className="h-8" value={borrador.hasta} aria-invalid={Boolean(error)} aria-describedby={error ? 'pc-rango-error' : undefined} onChange={e => cambiar({ hasta: e.target.value })} /></label>
    <div className="pc-atajos" role="group" aria-label="Atajos de periodo">
      {atajosRango(hoy, rango.hasta).map(atajo => {
        const activo = atajo.rango.desde === rango.desde && atajo.rango.hasta === rango.hasta
        return <button key={atajo.id} type="button" className="pc-atajo" aria-pressed={activo} onClick={() => onRango(atajo.rango)}>{atajo.etiqueta}</button>
      })}
    </div>
    {children}
    {error && <p id="pc-rango-error" role="alert" className="pc-rango-error">{error}</p>}
  </div>
}

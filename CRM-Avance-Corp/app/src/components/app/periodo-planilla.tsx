import { useState } from 'react'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Button } from '@/components/ui/button'
import { type PeriodoPlanilla } from '@/lib/planilla-reparto'

export function PeriodoPlanillaControl({ etiqueta, valor, onCambio, permitirTodas = false }: {
  etiqueta: string; valor: PeriodoPlanilla; onCambio: (valor: PeriodoPlanilla) => void; permitirTodas?: boolean
}) {
  const [diaNuevo, setDiaNuevo] = useState(valor.desde)
  return <fieldset className="min-w-0 space-y-2">
    <legend className="mb-2 text-xs font-semibold">{etiqueta}</legend>
    <div className="flex flex-wrap gap-2">
      <div className="w-60 max-w-full"><Select aria-label={`${etiqueta}: período`} value={valor.modo} onChange={(e) => onCambio({ ...valor, modo: e.target.value as PeriodoPlanilla['modo'] })}>
        {permitirTodas ? <option value="todas">Todas las fechas</option> : null}
        <option value="semana">Semana (lunes a domingo)</option><option value="dia">Un día</option><option value="rango">Rango</option><option value="dias">Días específicos</option>
      </Select></div>
      {valor.modo !== 'todas' && valor.modo !== 'dias' ? <Input type="date" className="w-auto" aria-label={`${etiqueta}: inicio`} value={valor.desde} onChange={(e) => onCambio({ ...valor, desde: e.target.value })} /> : null}
      {valor.modo === 'rango' ? <Input type="date" className="w-auto" aria-label={`${etiqueta}: fin`} value={valor.hasta} onChange={(e) => onCambio({ ...valor, hasta: e.target.value })} /> : null}
      {valor.modo === 'dias' ? <><Input type="date" className="w-auto" aria-label={`${etiqueta}: añadir día`} value={diaNuevo} onChange={(e) => setDiaNuevo(e.target.value)} /><Button variant="outline" size="sm" disabled={!diaNuevo} onClick={() => onCambio({ ...valor, dias: [...new Set([...valor.dias, diaNuevo])].sort() })}>Añadir día</Button></> : null}
    </div>
    {valor.modo === 'dias' ? <div className="flex flex-wrap gap-1">{valor.dias.map((dia) => <Button key={dia} variant="outline" size="sm" aria-label={`Quitar ${dia} de ${etiqueta}`} onClick={() => onCambio({ ...valor, dias: valor.dias.filter((d) => d !== dia) })}>{dia} ×</Button>)}</div> : null}
  </fieldset>
}

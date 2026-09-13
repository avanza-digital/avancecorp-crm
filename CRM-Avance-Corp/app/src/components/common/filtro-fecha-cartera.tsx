import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import type { ModoFechaCartera, RangoFechaCartera } from '@/lib/filtro-fecha-cartera'

export function FiltroFechaCartera({ modo, rango, hoy, invalido, onModo, onRango }: {
  modo: ModoFechaCartera
  rango: RangoFechaCartera
  hoy: string
  invalido: boolean
  onModo: (modo: ModoFechaCartera) => void
  onRango: (rango: RangoFechaCartera) => void
}) {
  return <>
    <div className="w-[210px]">
      <Select aria-label="Filtrar por fecha de recepción" value={modo}
        onChange={(e) => onModo(e.target.value as ModoFechaCartera)}>
        <option value="todas">Todas las fechas</option>
        <option value="hoy">Recibidos hoy</option>
        <option value="ayer">Recibidos ayer</option>
        <option value="semana">Últimos 7 días</option>
        <option value="rango">Rango de fechas</option>
      </Select>
    </div>
    {modo === 'rango' && <div className="flex w-full flex-wrap items-center gap-2 sm:w-auto">
      <label className="flex items-center gap-2 text-xs text-muted-foreground">
        Desde
        <Input type="date" aria-label="Fecha inicial de recepción" max={hoy}
          aria-invalid={invalido} aria-describedby={invalido ? 'error-fechas-cartera' : undefined}
          className="w-[155px]" value={rango.desde}
          onChange={(e) => onRango({ ...rango, desde: e.target.value })} />
      </label>
      <label className="flex items-center gap-2 text-xs text-muted-foreground">
        Hasta
        <Input type="date" aria-label="Fecha final de recepción" min={rango.desde} max={hoy}
          aria-invalid={invalido} aria-describedby={invalido ? 'error-fechas-cartera' : undefined}
          className="w-[155px]" value={rango.hasta}
          onChange={(e) => onRango({ ...rango, hasta: e.target.value })} />
      </label>
    </div>}
  </>
}

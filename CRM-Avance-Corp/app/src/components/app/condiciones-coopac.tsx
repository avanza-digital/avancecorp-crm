import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { fechaLima } from '@/lib/agenda-derivada'
import { vencimientoCoopac, type CampoCondicionesCoopac } from '@/lib/coopac-condiciones'

/** Formulario compartido del cierre inicial y las inversiones adicionales. */
export function CondicionesCoopac({prefijo, fecha, plazo, tasa, ocupado, invalido, errorId, onFecha, onPlazo, onTasa}: {
  prefijo: string; fecha: string; plazo: string; tasa: string; ocupado: boolean
  invalido?: CampoCondicionesCoopac | null
  errorId?: string
  onFecha?: ((valor: string) => void) | undefined
  onPlazo: (valor: string) => void; onTasa: (valor: string) => void
}) {
  const vencimiento = vencimientoCoopac(fecha, plazo) ?? ''
  return <div className="grid gap-3 sm:grid-cols-2">
    <div className="min-w-0 space-y-1">
      <Label htmlFor={`${prefijo}-fecha`}>Fecha comercial (inicio)</Label>
      <Input id={`${prefijo}-fecha`} type="date" required value={fecha} max={fechaLima(Date.now())}
        aria-invalid={invalido === 'fecha'} aria-describedby={invalido === 'fecha' ? errorId : undefined}
        readOnly={!onFecha} disabled={ocupado} onChange={e => onFecha?.(e.target.value)} />
      {!onFecha && <p className="text-[11px] text-muted-foreground">Se registra con la fecha de hoy.</p>}
    </div>
    <div className="min-w-0 space-y-1">
      <Label htmlFor={`${prefijo}-plazo`}>Plazo (meses)</Label>
      <Input id={`${prefijo}-plazo`} inputMode="numeric" required value={plazo}
        aria-invalid={invalido === 'plazo'} aria-describedby={invalido === 'plazo' ? errorId : undefined}
        placeholder="Ej. 12" disabled={ocupado} onChange={e => onPlazo(e.target.value)} />
    </div>
    <div className="min-w-0 space-y-1">
      <Label htmlFor={`${prefijo}-vence`}>Vencimiento</Label>
      <Input id={`${prefijo}-vence`} type="date" value={vencimiento} readOnly disabled={ocupado}
        aria-describedby={`${prefijo}-ayuda-vence`} />
      <p id={`${prefijo}-ayuda-vence`} className="text-[11px] text-muted-foreground">Se calcula según la fecha de inicio y el plazo.{!onFecha && ' La fecha definitiva se confirma al guardar.'}</p>
    </div>
    <div className="min-w-0 space-y-1">
      <Label htmlFor={`${prefijo}-tasa`}>Rentabilidad anual (%)</Label>
      <Input id={`${prefijo}-tasa`} inputMode="decimal" required value={tasa} placeholder="Ej. 12"
        disabled={ocupado} onChange={e => onTasa(e.target.value)} aria-invalid={invalido === 'tasa'}
        aria-describedby={[`${prefijo}-ayuda-tasa`, invalido === 'tasa' ? errorId : null].filter(Boolean).join(' ')} />
      <p id={`${prefijo}-ayuda-tasa`} className="text-[11px] text-muted-foreground">Porcentaje anual pactado con el cliente. Ejemplo: 12% anual.</p>
    </div>
  </div>
}

// Diálogo de UN campo: al pasar un lead a "Propuesta enviada", preguntar el
// capital REAL que se le propuso.
//
// Por qué (pedido de Miguel, 2026-07-25): hoy queda el `monto_estimado` que se
// escribió al crear el lead —una corazonada del primer contacto— y de ESE
// número viven el capital en proceso, el ranking del equipo y las metas del
// mes. El momento en que se envía la propuesta es el único en que la cifra es
// un HECHO y no una estimación; es ahí donde hay que preguntarla.
//
// El capital y la etapa se guardan en UNA sola escritura (`cambiarEtapa` con
// `capital`): partirlo en dos updates dejaría el lead avanzado con la cifra
// vieja si el segundo fallara — el mismo bug, ahora invisible.
import { useState, type JSX } from 'react'
import { toast } from 'sonner'
import { Dialog, DialogBody, DialogFooter, DialogHeader, DialogDescription, DialogTitle } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { useCRMData } from '@/lib/store-context'
import { money, primerNombre } from '@/lib/format'
import type { Moneda } from '@/lib/format'
import type { Lead } from '@/lib/tipos'

export function DialogCapitalPropuesta({
  lead,
  onClose,
}: {
  lead: Lead
  onClose: () => void
}): JSX.Element {
  const { cambiarEtapa } = useCRMData()
  // Precargado con lo que ya hay: Enter confirma tal cual y el paso cuesta un
  // gesto, no un formulario. Solo si el número cambió hay algo que corregir.
  const [monto, setMonto] = useState(String(lead.monto_estimado ?? ''))
  const [moneda, setMoneda] = useState<Moneda>(lead.moneda)

  const confirmar = () => {
    const valor = Number(monto)
    const res = cambiarEtapa(lead.id, 'propuesta_enviada', { monto_estimado: valor, moneda })
    if (!res.ok) {
      toast.error(res.error ?? 'No se pudo mover el lead')
      return
    }
    onClose()
    toast.success(`Entrevista realizada · capital propuesto ${money(valor, moneda)}`)
  }

  return (
    <Dialog open onClose={onClose} ariaLabel="Capital de la propuesta" className="w-[420px]">
      <DialogHeader>
        <DialogTitle>¿Cuánto le propusiste a {primerNombre(lead.nombre_completo)}?</DialogTitle>
        <DialogDescription>
          De esta cifra salen el capital en proceso y las metas del mes — el estimado inicial casi
          nunca es lo que se propone.
        </DialogDescription>
      </DialogHeader>
      <DialogBody>
        <div className="space-y-1.5">
          <Label htmlFor="cp-monto">Capital propuesto</Label>
          <div className="grid grid-cols-[1fr_96px] gap-2">
            <Input
              id="cp-monto"
              type="number"
              inputMode="decimal"
              min="0"
              step="0.01"
              autoFocus
              value={monto}
              onChange={(e) => setMonto(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.preventDefault()
                  confirmar()
                }
              }}
            />
            {/* La moneda viaja PEGADA al monto: PEN y USD jamás se suman, así
                que un número sin su moneda no significa nada. */}
            <Select
              aria-label="Moneda de la propuesta"
              value={moneda}
              onChange={(e) => setMoneda(e.target.value === 'USD' ? 'USD' : 'PEN')}
            >
              <option value="PEN">PEN</option>
              <option value="USD">USD</option>
            </Select>
          </div>
        </div>
      </DialogBody>
      <DialogFooter>
        <Button variant="outline" size="sm" onClick={onClose}>
          Cancelar
        </Button>
        <Button size="sm" onClick={confirmar}>
          Confirmar propuesta
        </Button>
      </DialogFooter>
    </Dialog>
  )
}

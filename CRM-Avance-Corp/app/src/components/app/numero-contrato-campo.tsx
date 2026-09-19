import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { PREFIJOS_CONTRATO, type PrefijoContrato } from '@/lib/contratos-catalogo'

interface NumeroContratoCampoProps {
  id: string
  prefijo: PrefijoContrato
  numero: string
  onPrefijoChange: (prefijo: PrefijoContrato) => void
  onNumeroChange: (numero: string) => void
  disabled: boolean
}

/** Campo compartido por el alta y la corrección: prefijo elegido + seis dígitos. */
export function NumeroContratoCampo({ id, prefijo, numero, onPrefijoChange, onNumeroChange, disabled }: NumeroContratoCampoProps) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={id}>N° de contrato</Label>
      <div className="grid grid-cols-[8rem_minmax(0,1fr)] gap-1.5">
        <Select
          id={`${id}-prefijo`}
          aria-label="Prefijo del contrato"
          aria-describedby={`${id}-ayuda`}
          value={prefijo}
          onChange={(e) => {
            const elegido = PREFIJOS_CONTRATO.find((opcion) => opcion === e.target.value)
            if (elegido) onPrefijoChange(elegido)
          }}
          disabled={disabled}
        >
          {PREFIJOS_CONTRATO.map((opcion) => <option key={opcion} value={opcion}>{opcion}</option>)}
        </Select>
        <Input
          id={id}
          inputMode="numeric"
          maxLength={6}
          placeholder="000000"
          autoComplete="off"
          title="Exactamente 6 dígitos"
          aria-describedby={`${id}-ayuda`}
          value={numero}
          onChange={(e) => onNumeroChange(e.target.value.replace(/\D/g, '').slice(0, 6))}
          disabled={disabled}
        />
      </div>
      <p id={`${id}-ayuda`} className="text-[11px] text-muted-foreground">
        Selecciona el prefijo y escribe los 6 dígitos del contrato.
      </p>
    </div>
  )
}

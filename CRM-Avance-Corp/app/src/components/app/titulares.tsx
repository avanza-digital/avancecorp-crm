// Editor de CO-TITULARES (cuentas mancomunadas) del formulario de contrato —
// homólogo del crearEditorTitulares de titulares-ui.js del portal, pero
// CONTROLADO: las filas viven en el estado del form padre y la validación al
// guardar es de lib/titulares (normalizarTitulares). Este componente es solo
// UI "tonta": agrega/quita filas y ajusta teclado/placeholder/hint por tipo de
// documento (lib/documento), igual que initCampoDocumento en el portal.
import { UserPlus2, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { TIPOS_DOCUMENTO, TIPOS_DOCUMENTO_K, type TipoDocumento } from '@/lib/documento'
import { MAX_TITULARES, titularVacio, type TitularBorrador } from '@/lib/titulares'

export interface TitularesEditorProps {
  /** Filas crudas (sin validar) — el padre las manda a normalizarTitulares al guardar. */
  value: TitularBorrador[]
  onChange: (filas: TitularBorrador[]) => void
  disabled?: boolean
  /** Prefijo de los ids de los inputs (para no chocar si hay dos forms montados). */
  idPrefix?: string
}

export function TitularesEditor({ value, onChange, disabled, idPrefix = 'tit' }: TitularesEditorProps) {
  const setFila = (i: number, cambios: Partial<TitularBorrador>) => {
    onChange(value.map((fila, idx) => (idx === i ? { ...fila, ...cambios } : fila)))
  }
  const quitar = (i: number) => {
    onChange(value.filter((_, idx) => idx !== i))
  }

  return (
    <div className="space-y-2">
      <div>
        <p className="text-xs font-bold text-foreground">Co-titulares (cuenta mancomunada) — opcional</p>
        <p className="text-[11px] leading-relaxed text-muted-foreground">
          Personas adicionales que figuran como titulares del contrato, además del cliente principal.
        </p>
      </div>

      {value.map((fila, i) => {
        const regla = TIPOS_DOCUMENTO[fila.tipo_documento]
        return (
          // key por índice a propósito: las filas son posicionales (como en el
          // portal) y solo se reordenan al quitar — con valores controlados no
          // hay estado interno que se pueda "quedar" en la fila equivocada.
          <div key={i} className="space-y-2 rounded-xl border border-border bg-muted/30 p-2.5">
            <div className="grid grid-cols-2 gap-2.5">
              <div className="space-y-1.5">
                <Label htmlFor={`${idPrefix}-${i}-tipo`}>Tipo de documento</Label>
                <Select
                  id={`${idPrefix}-${i}-tipo`}
                  value={fila.tipo_documento}
                  onChange={(e) => setFila(i, { tipo_documento: e.target.value as TipoDocumento })}
                  disabled={disabled}
                >
                  {/* Poblado POR CÓDIGO desde el catálogo — nunca <option> a mano. */}
                  {TIPOS_DOCUMENTO_K.map((k) => (
                    <option key={k} value={k}>{TIPOS_DOCUMENTO[k].etiqueta}</option>
                  ))}
                </Select>
              </div>
              <div className="space-y-1.5">
                <Label htmlFor={`${idPrefix}-${i}-doc`}>Documento</Label>
                <Input
                  id={`${idPrefix}-${i}-doc`}
                  inputMode={regla.inputmode}
                  placeholder={regla.placeholder}
                  // Tope ÚNICO 12 (no por tipo): un maxLength de 8 en modo DNI
                  // truncaría EN SILENCIO un CE pegado (hallazgo del portal).
                  maxLength={12}
                  autoComplete="off"
                  className={regla.mayusculas ? 'uppercase' : undefined}
                  value={fila.documento}
                  onChange={(e) => setFila(i, { documento: e.target.value })}
                  disabled={disabled}
                />
                <p className="text-[11px] text-muted-foreground">{regla.regla}</p>
              </div>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor={`${idPrefix}-${i}-nombre`}>Nombre completo del co-titular</Label>
              <Input
                id={`${idPrefix}-${i}-nombre`}
                className="uppercase"
                autoComplete="off"
                value={fila.nombre_completo}
                onChange={(e) => setFila(i, { nombre_completo: e.target.value })}
                disabled={disabled}
              />
            </div>
            <div className="flex justify-end">
              <Button type="button" variant="ghost" size="sm" onClick={() => quitar(i)} disabled={disabled}>
                <X /> Quitar
              </Button>
            </div>
          </div>
        )
      })}

      <Button
        type="button"
        variant="outline"
        size="sm"
        onClick={() => onChange([...value, titularVacio()])}
        disabled={disabled || value.length >= MAX_TITULARES}
      >
        <UserPlus2 /> + Agregar co-titular
      </Button>
      {value.length >= MAX_TITULARES && (
        <p className="text-[11px] text-muted-foreground">Máximo {MAX_TITULARES} co-titulares por contrato.</p>
      )}
    </div>
  )
}

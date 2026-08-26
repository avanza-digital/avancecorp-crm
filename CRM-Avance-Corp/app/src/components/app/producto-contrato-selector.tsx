import { PackageCheck, RotateCcw } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { money } from '@/lib/format'
import { etiquetaCondicionProducto, type ProductoCondicionSeleccion } from '@/lib/productos-inversion'

export const CODIGO_PRODUCTO_HISTORICO = 'HISTORICO-SIN-CATALOGO'

export interface ProductoActualContrato {
  condicionId: string
  codigo: string
  nombre: string
  version: number
  estado: 'borrador' | 'publicada' | 'retirada'
}

interface ProductoContratoSelectorProps {
  id: string
  value: string
  condiciones: ProductoCondicionSeleccion[]
  actual?: ProductoActualContrato
  cargando: boolean
  error: boolean
  reintentando: boolean
  disabled?: boolean
  onChange: (id: string, condicion: ProductoCondicionSeleccion | null) => void
  onReintentar: () => void
}

const CATEGORIA = {
  nuevo: 'Nueva inversión',
  renovacion: 'Renovación',
  upgrade: 'Aumento de inversión',
} as const

const MODALIDAD = {
  mensual: 'Mensual',
  trimestral: 'Trimestral',
  semestral: 'Semestral',
  anual: 'Anual',
} as const

/**
 * Selector compartido por alta/corrección. Nunca inventa un fallback legacy:
 * la opción histórica solo aparece cuando YA pertenece al contrato abierto.
 */
export function ProductoContratoSelector({
  id,
  value,
  condiciones,
  actual,
  cargando,
  error,
  reintentando,
  disabled = false,
  onChange,
  onReintentar,
}: ProductoContratoSelectorProps) {
  const condicion = condiciones.find((item) => item.condicion_id === value) ?? null
  const actualNoSeleccionable = actual && !condiciones.some((item) => item.condicion_id === actual.condicionId)
  const esHistorico = actual?.codigo === CODIGO_PRODUCTO_HISTORICO
  // Un contrato con condiciones propias (las que se firmaron) solo tiene ALGO
  // que decidir si el catálogo ofrece alternativas. Sin catálogo publicado
  // —hoy, el 100 % de los contratos— explicarlo es ruido en cada corrección:
  // el vendedor lee jerga de base de datos sobre una elección que no existe.
  const explicarCondicionesPropias = esHistorico && condiciones.length > 0

  return (
    <section className="space-y-2 rounded-xl border border-primary/25 bg-primary/[0.035] p-3">
      <div className="flex items-center justify-between gap-3">
        <div className="flex min-w-0 items-center gap-2">
          <span className="grid size-8 shrink-0 place-items-center rounded-lg bg-primary/10 text-primary">
            <PackageCheck className="size-4" aria-hidden />
          </span>
          <div className="min-w-0">
            <Label htmlFor={id}>Producto de inversión</Label>
            <p className="text-[11px] text-muted-foreground">
              Elige la opción que corresponda a esta venta: tipo de inversión, moneda, plazo y forma de pago.
            </p>
          </div>
        </div>
        {error && (
          <Button type="button" variant="outline" size="xs" onClick={onReintentar} disabled={reintentando || disabled}>
            <RotateCcw aria-hidden /> {reintentando ? 'Reintentando…' : 'Reintentar'}
          </Button>
        )}
      </div>

      <Select
        id={id}
        value={value}
        onChange={(evento) => {
          const siguiente = evento.target.value
          onChange(siguiente, condiciones.find((item) => item.condicion_id === siguiente) ?? null)
        }}
        disabled={disabled || cargando || error}
        aria-invalid={error || undefined}
      >
        <option value="" disabled>
          {cargando
            ? 'Cargando productos…'
            : condiciones.length === 0
              ? 'Sin productos vigentes'
              : '— Seleccionar producto —'}
        </option>
        {actualNoSeleccionable && (
          <option value={actual.condicionId}>
            {esHistorico
              ? 'Mantener las condiciones con las que se firmó'
              : `${actual.nombre} (ya no disponible para nuevas ventas)`}
          </option>
        )}
        {condiciones.map((item) => (
          <option key={item.condicion_id} value={item.condicion_id}>
            {etiquetaCondicionProducto(item)} · {item.version_nombre}
          </option>
        ))}
      </Select>

      {error ? (
        <p className="text-xs font-semibold text-destructive">
          {actual
            ? 'No pudimos actualizar las opciones vigentes. Puedes mantener lo que ya se acordó, pero no cambiarlo hasta volver a intentar.'
            : 'No pudimos cargar las opciones vigentes. Vuelve a intentar antes de confirmar la inversión.'}
        </p>
      ) : !cargando && condiciones.length === 0 && !actual ? (
        <p className="text-xs font-semibold text-warning-text">
          No hay opciones disponibles para vender. Gerencia debe habilitar al menos una antes de registrar inversiones.
        </p>
      ) : condicion ? (
        <div className="grid grid-cols-2 gap-x-4 gap-y-1 border-t border-primary/15 pt-2 text-[11px] sm:grid-cols-4">
          <p>
            <span className="text-muted-foreground">Opción elegida</span>
            <br />
            <b>{condicion.version_nombre}</b>
          </p>
          <p>
            <span className="text-muted-foreground">Tipo de inversión</span>
            <br />
            <b>
              {CATEGORIA[condicion.categoria]} · {condicion.moneda}
            </b>
          </p>
          <p>
            <span className="text-muted-foreground">Plazo y pago</span>
            <br />
            <b>
              {condicion.plazo_meses} meses · {MODALIDAD[condicion.modalidad]}
            </b>
          </p>
          <p>
            <span className="text-muted-foreground">Capital</span>
            <br />
            <b>
              {money(condicion.capital_minimo, condicion.moneda)}–{money(condicion.capital_maximo, condicion.moneda)}
            </b>
          </p>
          <p className="col-span-2 sm:col-span-4">
            <span className="text-muted-foreground">Rango de tasa anual</span>{' '}
            <b>
              {condicion.tasa_minima}%–{condicion.tasa_maxima}%
            </b>
            <span className="text-muted-foreground"> · tasa sugerida {condicion.tasa_referencia}%</span>
          </p>
        </div>
      ) : actualNoSeleccionable && (!esHistorico || explicarCondicionesPropias) ? (
        <p className="border-t border-primary/15 pt-2 text-xs text-muted-foreground">
          {esHistorico
            ? 'Este contrato mantiene lo que se acordó al firmarlo. Puedes corregir sus datos sin cambiar esas condiciones; para ofrecer una opción actual, registra una inversión nueva.'
            : 'Esta opción ya no está disponible para nuevas ventas. Puedes conservar lo acordado o elegir una opción vigente.'}
        </p>
      ) : null}
    </section>
  )
}

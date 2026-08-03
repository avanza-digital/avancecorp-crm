import { useEffect, useId, useRef } from 'react'
import { Landmark, Plus, RefreshCw } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { SeccionBancariaCampos } from '@/components/app/secciones-bancarias'
import type { CuentaBancariaSeleccionable } from '@/lib/clientes-tipos'
import type {
  CampoSeccionBancaria,
  SeccionBancariaForm,
} from '@/lib/cliente-form-logica'
import type { Moneda } from '@/lib/format'
import {
  CUENTA_NUEVA,
  claveCuenta,
  enmascararCuenta,
} from '@/lib/cuentas-bancarias-contrato'

export interface CuentaPagoContratoProps {
  moneda: Moneda
  cuentas: readonly CuentaBancariaSeleccionable[]
  seleccion: string
  nueva: SeccionBancariaForm
  cargando: boolean
  error: boolean
  reintentando: boolean
  deshabilitado: boolean
  campoNuevaInvalido?: CampoSeccionBancaria | null
  errorId?: string
  onSeleccion: (seleccion: string) => void
  onNueva: (cuenta: SeccionBancariaForm) => void
  onReintentar: () => void
}

function etiquetaTipo(tipo: CuentaBancariaSeleccionable['tipo_cuenta']): string {
  return tipo === 'corriente' ? 'Corriente' : 'Ahorros'
}

/**
 * Selector presentacional de la cuenta contractual. La consulta y el payload
 * viven fuera para que este componente no mezcle red, dominio y renderizado.
 */
export function CuentaPagoContrato({
  moneda,
  cuentas,
  seleccion,
  nueva,
  cargando,
  error,
  reintentando,
  deshabilitado,
  campoNuevaInvalido = null,
  errorId,
  onSeleccion,
  onNueva,
  onReintentar,
}: CuentaPagoContratoProps) {
  const monedaLabel = moneda === 'USD' ? 'Dólares (USD)' : 'Soles (PEN)'
  const idDescripcion = useId()
  const nombreGrupo = `cuenta-pago-${useId()}`
  const primerControlRef = useRef<HTMLInputElement>(null)
  const enfocarTrasRecargaRef = useRef(false)

  useEffect(() => {
    if (!enfocarTrasRecargaRef.current || cargando || error) return
    primerControlRef.current?.focus()
    enfocarTrasRecargaRef.current = false
  }, [cargando, error, cuentas.length])

  const reintentar = () => {
    enfocarTrasRecargaRef.current = true
    onReintentar()
  }

  return (
    <fieldset
      disabled={deshabilitado}
      aria-describedby={idDescripcion}
      className="space-y-2.5 rounded-xl border border-border p-3"
    >
      <legend className="px-1 text-xs font-bold text-primary">
        Cuenta de pago del contrato
      </legend>
      <p id={idDescripcion} className="text-xs leading-relaxed text-muted-foreground">
        <b className="text-foreground">Selección obligatoria.</b> Elige la cuenta de{' '}
        <b className="text-foreground">{monedaLabel}</b> que quedará
        fijada para sus intereses y devolución de capital. Los contratos anteriores no cambian.
      </p>

      <span className="sr-only" role="status" aria-live="polite" aria-atomic="true">
        {!cargando && !error
          ? `${cuentas.length} cuenta${cuentas.length === 1 ? '' : 's'} disponible${cuentas.length === 1 ? '' : 's'} en ${monedaLabel}.`
          : ''}
      </span>

      {cargando && (
        <p className="rounded-lg bg-muted/50 px-3 py-2 text-xs text-muted-foreground" aria-live="polite">
          Cargando cuentas bancarias…
        </p>
      )}

      {error && (
        <div className="flex flex-col items-stretch gap-3 rounded-lg bg-destructive/10 px-3 py-2 sm:flex-row sm:items-center sm:justify-between" role="alert">
          <p className="text-xs font-semibold text-destructive">
            No se pudieron cargar las cuentas. No se guardará el contrato sin confirmar el destino.
          </p>
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={reintentar}
            disabled={reintentando || deshabilitado}
            className="shrink-0"
          >
            <RefreshCw className={reintentando ? 'animate-spin' : ''} />
            {reintentando ? 'Reintentando…' : 'Reintentar'}
          </Button>
        </div>
      )}

      {!cargando && !error && (
        <div className="space-y-2">
          {cuentas.length === 0 && (
            <p className="rounded-lg bg-muted/50 px-3 py-2 text-xs text-muted-foreground">
              El cliente todavía no tiene una cuenta completa en esta moneda. Registra una nueva para continuar.
            </p>
          )}

          {cuentas.map((cuenta, indice) => {
            const clave = claveCuenta(cuenta)
            return (
              <label
                key={clave}
                className="flex cursor-pointer items-start gap-3 rounded-lg border border-border px-3 py-2.5 transition-colors focus-within:ring-2 focus-within:ring-primary/30 has-[:checked]:border-primary has-[:checked]:bg-primary/5 has-[:disabled]:cursor-not-allowed has-[:disabled]:opacity-60"
              >
                <input
                  ref={indice === 0 ? primerControlRef : undefined}
                  type="radio"
                  name={nombreGrupo}
                  value={clave}
                  checked={seleccion === clave}
                  onChange={(e) => onSeleccion(e.target.value)}
                  required
                  className="mt-0.5 size-3.5 accent-primary"
                />
                <Landmark className="mt-0.5 size-4 shrink-0 text-primary" aria-hidden />
                <span className="min-w-0 flex-1">
                  <span className="flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs font-bold text-foreground">
                    <span>{cuenta.banco}</span>
                    <span className="font-medium text-muted-foreground">
                      {etiquetaTipo(cuenta.tipo_cuenta)} · {enmascararCuenta(cuenta.numero_cuenta)}
                    </span>
                  </span>
                  <span className="mt-0.5 block text-xs text-muted-foreground">
                    CCI {enmascararCuenta(cuenta.cci)} · {cuenta.es_cuenta_perfil ? 'Cuenta actual del cliente' : 'Cuenta guardada'}
                  </span>
                  {cuenta.titular_distinto && cuenta.beneficiario_nombre && (
                    <span className="mt-0.5 block text-xs text-muted-foreground">
                      Beneficiario: {cuenta.beneficiario_nombre}
                    </span>
                  )}
                </span>
              </label>
            )
          })}

          <label className="flex cursor-pointer items-center gap-3 rounded-lg border border-dashed border-border px-3 py-2.5 transition-colors focus-within:ring-2 focus-within:ring-primary/30 has-[:checked]:border-primary has-[:checked]:bg-primary/5 has-[:disabled]:cursor-not-allowed has-[:disabled]:opacity-60">
            <input
              ref={cuentas.length === 0 ? primerControlRef : undefined}
              type="radio"
              name={nombreGrupo}
              value={CUENTA_NUEVA}
              checked={seleccion === CUENTA_NUEVA}
              onChange={(e) => onSeleccion(e.target.value)}
              required
              className="size-3.5 accent-primary"
            />
            <Plus className="size-4 text-primary" aria-hidden />
            <span className="text-xs font-bold text-foreground">Añadir una cuenta nueva</span>
          </label>
        </div>
      )}

      {!cargando && !error && seleccion === CUENTA_NUEVA && (
        <div className="pt-1">
          <SeccionBancariaCampos
            titulo={`Nueva cuenta en ${monedaLabel}`}
            idBase="ct"
            prefijo="nueva"
            valores={nueva}
            onCambio={onNueva}
            deshabilitado={deshabilitado}
            requerida
            campoInvalido={campoNuevaInvalido}
            {...(errorId ? { errorId } : {})}
          />
        </div>
      )}
    </fieldset>
  )
}

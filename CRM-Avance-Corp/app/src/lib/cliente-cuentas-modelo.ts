import type { ClienteDetalle, CuentaBancariaSeleccionable } from './clientes-tipos'
import type { Moneda } from './format'

export interface CuentaClienteVista {
  clave: string
  banco: string | null
  tipoCuenta: string | null
  numeroCuenta: string | null
  cci: string | null
  titularDistinto: boolean
  beneficiarioNombre: string | null
  beneficiarioDni: string | null
  origen?: CuentaBancariaSeleccionable['origen'] | null
  /** null = casilla vigente del perfil (no tiene fecha de registro propia). */
  registradaEn: string | null
}

export function valorCliente(valor: string | null): string {
  return valor?.trim() || '—'
}

export function cuentaClienteDesdeRpc(cuenta: CuentaBancariaSeleccionable): CuentaClienteVista {
  return {
    clave: cuenta.cuenta_id ?? `perfil-${cuenta.moneda}`,
    banco: cuenta.banco,
    tipoCuenta: cuenta.tipo_cuenta,
    numeroCuenta: cuenta.numero_cuenta,
    cci: cuenta.cci,
    titularDistinto: cuenta.titular_distinto,
    beneficiarioNombre: cuenta.beneficiario_nombre,
    beneficiarioDni: cuenta.beneficiario_dni,
    origen: cuenta.origen,
    registradaEn: cuenta.creada_en,
  }
}

/** Adapta las dos casillas embebidas usadas por los fixtures demo a la vista común. */
export function cuentasClienteEmbebidas(detalle: ClienteDetalle, moneda: Moneda): CuentaClienteVista[] {
  const cuenta =
    moneda === 'USD'
      ? {
          banco: detalle.banco_usd,
          tipoCuenta: detalle.tipo_cuenta_usd,
          numeroCuenta: detalle.numero_cuenta_usd,
          cci: detalle.cci_usd,
          titularDistinto: detalle.titular_distinto_usd,
          beneficiarioNombre: detalle.beneficiario_nombre_usd,
          beneficiarioDni: detalle.beneficiario_dni_usd,
        }
      : {
          banco: detalle.banco,
          tipoCuenta: detalle.tipo_cuenta,
          numeroCuenta: detalle.numero_cuenta,
          cci: detalle.cci,
          titularDistinto: detalle.titular_distinto,
          beneficiarioNombre: detalle.beneficiario_nombre,
          beneficiarioDni: detalle.beneficiario_dni,
        }
  const tieneCuenta = [cuenta.banco, cuenta.tipoCuenta, cuenta.numeroCuenta, cuenta.cci].some((dato) => dato?.trim())
  return tieneCuenta ? [{ clave: `perfil-${moneda}`, ...cuenta, origen: null, registradaEn: null }] : []
}

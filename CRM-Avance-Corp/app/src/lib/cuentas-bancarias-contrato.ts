import type { Moneda } from './format'
import type {
  CuentaBancariaSeleccionable,
  CuentaPagoContratoInput,
} from './clientes-tipos'
import {
  validarSeccionBancariaDetallada,
  type CampoSeccionBancaria,
  type SeccionBancariaForm,
} from './cliente-form-logica'

/** Valores estables del radio-group; nunca se mandan directamente al servidor. */
export const CUENTA_PERFIL = 'perfil'
export const CUENTA_NUEVA = 'nueva'
const PREFIJO_PERFIL = `${CUENTA_PERFIL}:`
const PREFIJO_EXISTENTE = 'cuenta:'

/**
 * Huella FNV-1a de 64 bits: no deja cuenta/CCI crudos en el value del radio y
 * cambia si una revalidación trae otra fotografía del perfil. No es una firma
 * de seguridad (la RPC revalida); sirve para invalidar la elección visual.
 */
function huellaCuenta(cuenta: CuentaBancariaSeleccionable): string {
  const serializada = JSON.stringify([
    cuenta.moneda,
    cuenta.banco,
    cuenta.tipo_cuenta,
    cuenta.numero_cuenta,
    cuenta.cci,
    cuenta.titular_distinto,
    cuenta.beneficiario_nombre,
    cuenta.beneficiario_dni,
  ])
  let hash = 0xcbf29ce484222325n
  for (let i = 0; i < serializada.length; i += 1) {
    hash ^= BigInt(serializada.charCodeAt(i))
    hash = BigInt.asUintN(64, hash * 0x100000001b3n)
  }
  return hash.toString(16).padStart(16, '0')
}

/** Clave de UI inequívoca para una fila devuelta por la RPC de selección. */
export function claveCuenta(cuenta: CuentaBancariaSeleccionable): string {
  return cuenta.cuenta_id == null
    ? `${PREFIJO_PERFIL}${huellaCuenta(cuenta)}`
    : `${PREFIJO_EXISTENTE}${cuenta.cuenta_id}`
}

/** Oculta el dato sensible y conserva solo lo necesario para distinguir cuentas. */
export function enmascararCuenta(numero: string): string {
  const limpio = numero.trim()
  if (limpio.length <= 4) return limpio
  return `•••• ${limpio.slice(-4)}`
}

export type ResultadoPrepararCuenta =
  | { ok: true; cuenta: CuentaPagoContratoInput }
  | { ok: false; error: string; campo?: CampoSeccionBancaria }

interface PrepararCuentaParams {
  seleccion: string
  moneda: Moneda
  cuentas: readonly CuentaBancariaSeleccionable[]
  nueva: SeccionBancariaForm
}

/**
 * Convierte una selección de UI en el discriminated union que acepta la RPC.
 * Además vuelve a comprobar moneda/pertenencia contra las filas autorizadas:
 * el servidor es la frontera de seguridad, pero el navegador no debe enviar un
 * estado obsoleto o incompatible si el usuario cambió la moneda.
 */
export function prepararCuentaPago({
  seleccion,
  moneda,
  cuentas,
  nueva,
}: PrepararCuentaParams): ResultadoPrepararCuenta {
  if (!seleccion) {
    return { ok: false, error: 'Selecciona la cuenta de pago del contrato.' }
  }

  if (seleccion === CUENTA_NUEVA) {
    const validada = validarSeccionBancariaDetallada(
      nueva,
      moneda === 'USD' ? 'Dólares' : 'Soles',
    )
    if (!validada.ok) return validada
    if (validada.vacia) {
      return {
        ok: false,
        error: 'Completa los datos de la cuenta bancaria nueva.',
        campo: 'banco',
      }
    }
    return {
      ok: true,
      cuenta: {
        tipo: 'nueva',
        banco: validada.datos.banco!,
        // validarSeccionBancaria ya comprobó la allowlist; el DTO compartido
        // con public.perfiles conserva `string` por compatibilidad legacy.
        tipo_cuenta: validada.datos.tipo_cuenta as 'ahorros' | 'corriente',
        numero_cuenta: validada.datos.numero_cuenta!,
        cci: validada.datos.cci!,
        titular_distinto: validada.datos.titular_distinto,
        beneficiario_nombre: validada.datos.beneficiario_nombre,
        beneficiario_dni: validada.datos.beneficiario_dni,
      },
    }
  }

  if (seleccion.startsWith(PREFIJO_PERFIL)) {
    const perfil = cuentas.find(
      (cuenta) => cuenta.moneda === moneda
        && cuenta.cuenta_id == null
        && cuenta.es_cuenta_perfil
        && claveCuenta(cuenta) === seleccion,
    )
    return perfil
      ? {
          ok: true,
          cuenta: {
            tipo: 'perfil',
            // Optimistic concurrency: la RPC comparará esta fotografía con el
            // perfil justo antes de copiarlo. Si otra sesión lo cambió entre
            // la carga y el submit, aborta en lugar de vincular algo no visto.
            cuenta_esperada: {
              banco: perfil.banco,
              tipo_cuenta: perfil.tipo_cuenta,
              numero_cuenta: perfil.numero_cuenta,
              cci: perfil.cci,
              titular_distinto: perfil.titular_distinto,
              beneficiario_nombre: perfil.beneficiario_nombre,
              beneficiario_dni: perfil.beneficiario_dni,
            },
          },
        }
      : { ok: false, error: 'La cuenta actual del perfil ya no está disponible. Recarga e inténtalo nuevamente.' }
  }

  if (seleccion.startsWith(PREFIJO_EXISTENTE)) {
    const cuentaId = seleccion.slice(PREFIJO_EXISTENTE.length)
    const existente = cuentas.find(
      (cuenta) => cuenta.cuenta_id === cuentaId && cuenta.moneda === moneda,
    )
    return existente
      ? { ok: true, cuenta: { tipo: 'existente', cuenta_id: cuentaId } }
      : { ok: false, error: 'La cuenta seleccionada ya no está disponible. Recarga e inténtalo nuevamente.' }
  }

  return { ok: false, error: 'La selección de cuenta bancaria no es válida.' }
}

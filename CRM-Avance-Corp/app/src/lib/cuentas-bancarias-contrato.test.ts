import { describe, expect, it } from 'vitest'
import type { CuentaBancariaSeleccionable } from './clientes-tipos'
import { SECCION_BANCARIA_VACIA } from './cliente-form-logica'
import {
  CUENTA_NUEVA,
  claveCuenta,
  enmascararCuenta,
  prepararCuentaPago,
} from './cuentas-bancarias-contrato'

const PERFIL: CuentaBancariaSeleccionable = {
  cuenta_id: null,
  moneda: 'PEN',
  banco: 'BCP',
  tipo_cuenta: 'ahorros',
  numero_cuenta: '191000001234',
  cci: '00112233445566778899',
  titular_distinto: false,
  beneficiario_nombre: null,
  beneficiario_dni: null,
  origen: 'perfil',
  es_cuenta_perfil: true,
  creada_en: null,
}

const EXISTENTE: CuentaBancariaSeleccionable = {
  ...PERFIL,
  cuenta_id: '20000000-0000-4000-8000-000000000001',
  banco: 'Interbank',
  numero_cuenta: '200000005678',
  cci: '12345678901234567890',
  origen: 'contrato',
  es_cuenta_perfil: false,
  creada_en: '2026-08-03T20:00:00Z',
}

describe('cuentas bancarias por contrato', () => {
  it('prepara la cuenta del perfil con la fotografía completa contra TOCTOU', () => {
    const r = prepararCuentaPago({
      seleccion: claveCuenta(PERFIL),
      moneda: 'PEN',
      cuentas: [PERFIL],
      nueva: { ...SECCION_BANCARIA_VACIA },
    })

    expect(r).toEqual({
      ok: true,
      cuenta: {
        tipo: 'perfil',
        cuenta_esperada: {
          banco: 'BCP',
          tipo_cuenta: 'ahorros',
          numero_cuenta: '191000001234',
          cci: '00112233445566778899',
          titular_distinto: false,
          beneficiario_nombre: null,
          beneficiario_dni: null,
        },
      },
    })
  })

  it('cambia la clave del perfil cuando una revalidación cambia sus datos', () => {
    const perfilActualizado = { ...PERFIL, numero_cuenta: '191999999999' }

    expect(claveCuenta(perfilActualizado)).not.toBe(claveCuenta(PERFIL))
    expect(prepararCuentaPago({
      seleccion: claveCuenta(PERFIL),
      moneda: 'PEN',
      cuentas: [perfilActualizado],
      nueva: { ...SECCION_BANCARIA_VACIA },
    })).toEqual({
      ok: false,
      error: 'La cuenta actual del perfil ya no está disponible. Recarga e inténtalo nuevamente.',
    })
  })

  it('acepta una cuenta existente autorizada de la misma moneda', () => {
    const r = prepararCuentaPago({
      seleccion: claveCuenta(EXISTENTE),
      moneda: 'PEN',
      cuentas: [EXISTENTE],
      nueva: { ...SECCION_BANCARIA_VACIA },
    })
    expect(r).toEqual({
      ok: true,
      cuenta: { tipo: 'existente', cuenta_id: EXISTENTE.cuenta_id },
    })
  })

  it('rechaza una selección forjada o incompatible con la moneda', () => {
    const forjada = prepararCuentaPago({
      seleccion: 'cuenta:20000000-0000-4000-8000-000000000099',
      moneda: 'PEN',
      cuentas: [EXISTENTE],
      nueva: { ...SECCION_BANCARIA_VACIA },
    })
    const otraMoneda = prepararCuentaPago({
      seleccion: claveCuenta(EXISTENTE),
      moneda: 'USD',
      cuentas: [EXISTENTE],
      nueva: { ...SECCION_BANCARIA_VACIA },
    })
    expect(forjada.ok).toBe(false)
    expect(otraMoneda.ok).toBe(false)
  })

  it('normaliza y prepara una cuenta nueva con beneficiario', () => {
    const r = prepararCuentaPago({
      seleccion: CUENTA_NUEVA,
      moneda: 'USD',
      cuentas: [],
      nueva: {
        banco: 'Caja Cusco',
        tipo_cuenta: 'corriente',
        numero_cuenta: 'ABC-123',
        cci: '12345678901234567890',
        titular_distinto: true,
        beneficiario_nombre: '  Ana   María Pérez ',
        beneficiario_dni: '12345678',
      },
    })
    expect(r).toEqual({
      ok: true,
      cuenta: {
        tipo: 'nueva',
        banco: 'Caja Cusco',
        tipo_cuenta: 'corriente',
        numero_cuenta: 'ABC-123',
        cci: '12345678901234567890',
        titular_distinto: true,
        beneficiario_nombre: 'ANA MARÍA PÉREZ',
        beneficiario_dni: '12345678',
      },
    })
  })

  it('rechaza selección vacía y cuenta nueva incompleta', () => {
    const vacia = prepararCuentaPago({
      seleccion: '',
      moneda: 'PEN',
      cuentas: [PERFIL],
      nueva: { ...SECCION_BANCARIA_VACIA },
    })
    const nuevaIncompleta = prepararCuentaPago({
      seleccion: CUENTA_NUEVA,
      moneda: 'PEN',
      cuentas: [],
      nueva: { ...SECCION_BANCARIA_VACIA, banco: 'BCP' },
    })
    expect(vacia).toEqual({ ok: false, error: 'Selecciona la cuenta de pago del contrato.' })
    expect(nuevaIncompleta.ok).toBe(false)
  })

  it('enmascara todo salvo los últimos cuatro caracteres', () => {
    expect(enmascararCuenta('00112233445566778899')).toBe('•••• 8899')
    expect(enmascararCuenta('1234')).toBe('1234')
  })
})

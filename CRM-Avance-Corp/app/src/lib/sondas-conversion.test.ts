import { describe, expect, it } from 'vitest'
import {
  estadoVerificacionNucleo,
  sondasNucleoVerificadas,
  type SondasParidadNucleo,
} from './sondas-conversion'

describe('sondasNucleoVerificadas — fail-closed compartido', () => {
  it.each([
    ['payload ausente', undefined, false],
    ['payload null', null, false],
    ['objeto vacío', {}, false],
    ['solo cuadra', { cuadra: true }, false],
    ['solo paridad', { paridad_nucleo: 0 }, false],
    ['cuadra null', { cuadra: null, paridad_nucleo: 0 }, false],
    ['paridad null', { cuadra: true, paridad_nucleo: null }, false],
    ['cuadra false aunque el desvío sea cero', { cuadra: false, paridad_nucleo: 0 }, false],
    ['cuadra true con desvío positivo', { cuadra: true, paridad_nucleo: 0.01 }, false],
    ['cuadra true con desvío negativo', { cuadra: true, paridad_nucleo: -0.01 }, false],
    ['cuadra true con NaN', { cuadra: true, paridad_nucleo: Number.NaN }, false],
    ['las dos señales exactas', { cuadra: true, paridad_nucleo: 0 }, true],
  ] satisfies ReadonlyArray<readonly [string, SondasParidadNucleo | null | undefined, boolean]>) (
    '%s → %s',
    (_caso, sondas, esperado) => {
      expect(sondasNucleoVerificadas(sondas)).toBe(esperado)
    },
  )

  it('clasifica ausencia por separado de un descuadre explícito', () => {
    expect(estadoVerificacionNucleo(undefined)).toBe('sin_verificacion')
    expect(estadoVerificacionNucleo({ cuadra: true, paridad_nucleo: null })).toBe('sin_verificacion')
    expect(estadoVerificacionNucleo({ cuadra: false, paridad_nucleo: 0 })).toBe('descuadre')
    expect(estadoVerificacionNucleo({ cuadra: true, paridad_nucleo: 2 })).toBe('descuadre')
    expect(estadoVerificacionNucleo({ cuadra: true, paridad_nucleo: 0 })).toBe('verificada')
  })
})

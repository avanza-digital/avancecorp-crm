import { describe, expect, it } from 'vitest'
import {
  INTERVALO_CIERRE_MES_ESTADO_MS,
  opcionesCierreMesEstado,
} from './crm-queries'

/**
 * Exigencia de Miguel antes del release (2026-08-15): la alarma tiene que
 * actualizarse SOLA con la pestaña abierta. La configuración es pura a
 * propósito para que este test la fije — quitar el intervalo «porque molesta»
 * vuelve a dejar la alarma de atascado dependiendo de que alguien reenfoque.
 */
describe('opcionesCierreMesEstado', () => {
  it('re-pregunta periódicamente: la alarma no depende de reenfocar la pestaña', () => {
    const opciones = opcionesCierreMesEstado(true)
    expect(opciones.refetchInterval).toBe(INTERVALO_CIERRE_MES_ESTADO_MS)
    expect(INTERVALO_CIERRE_MES_ESTADO_MS).toBe(300_000)
  })

  it('el gate de habilitada viaja tal cual (demo apagado = sin red)', () => {
    expect(opcionesCierreMesEstado(false).enabled).toBe(false)
    expect(opcionesCierreMesEstado(true).enabled).toBe(true)
  })
})

import { describe, expect, it } from 'vitest'
import { detalleModoPolitica, etiquetaModoPolitica, rangoEfectivo } from './rentabilidad'

const autorizada = { modo: 'autorizada', base: 15, minimo: 15, maximo: 17 }

describe('rangoEfectivo: la vigencia de una autorización se mira con el reloj de AHORA', () => {
  it('sin autorización devuelve el rango tal cual', () => {
    expect(rangoEfectivo({ modo: 'base', base: 15, minimo: 15, maximo: 15, solicitud: null })).toEqual({ minimo: 15, maximo: 15, caducada: false })
  })

  it('autorización vigente: [base, tope]', () => {
    const ahora = Date.parse('2026-09-10T00:00:00Z')
    expect(rangoEfectivo({ ...autorizada, solicitud: { vence_en: '2026-09-13T10:00:00Z', vigente: true } }, ahora)).toEqual({ minimo: 15, maximo: 17, caducada: false })
  })

  it('caducada (en el instante de vence_en o después): vuelve a la base y lo declara', () => {
    const vence = Date.parse('2026-09-13T10:00:00Z')
    const s = { vence_en: '2026-09-13T10:00:00Z', vigente: true }
    expect(rangoEfectivo({ ...autorizada, solicitud: s }, vence)).toEqual({ minimo: 15, maximo: 15, caducada: true })
    expect(rangoEfectivo({ ...autorizada, solicitud: s }, vence + 1000)).toEqual({ minimo: 15, maximo: 15, caducada: true })
    expect(rangoEfectivo({ ...autorizada, solicitud: s }, vence - 1000).caducada).toBe(false)
  })

  it('una solicitud marcada como no vigente por el servidor también vuelve a la base', () => {
    expect(rangoEfectivo({ ...autorizada, solicitud: { vence_en: '2099-01-01T00:00:00Z', vigente: false } })).toEqual({ minimo: 15, maximo: 15, caducada: true })
  })
})

describe('etiquetaModoPolitica / detalleModoPolitica: el modo se nombra sin mentir', () => {
  it('nombra los dos modos conocidos', () => {
    expect(etiquetaModoPolitica('observacion')).toBe('Observación')
    expect(etiquetaModoPolitica('enforcement')).toBe('Candado activo')
    expect(detalleModoPolitica('observacion')).toMatch(/todavía no se bloquea nada/)
    expect(detalleModoPolitica('enforcement')).toMatch(/rechaza cualquier tasa distinta/)
  })

  it('un modo que este CRM no conoce se declara como tal (no se hace pasar por observación)', () => {
    // Son el nombre accesible y la descripción del interruptor del candado: prometer «no bloquea» sobre un modo
    // desconocido sería afirmar algo que el front no sabe.
    expect(etiquetaModoPolitica('candado_total')).toBe('Modo desconocido (candado_total)')
    expect(detalleModoPolitica('candado_total')).toMatch(/no conoce este modo/)
    expect(detalleModoPolitica('candado_total')).not.toMatch(/no se bloquea/)
  })
})

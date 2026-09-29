// Lo que «Ahora» de Gestión diaria toma de la ficha AUTORIZADA de un cliente
// para llamarlo: el número y si se le puede contactar. Si la ficha y la
// persona se contradicen, gana el «no» (revisión de Codex, 29/09/2026).
import { describe, expect, it } from 'vitest'
import { contactoDeFicha } from './inversionistas-queries'

const ficha = (contactar: boolean, noContactar: boolean, telefono: string | null = '+51 988 777 666') =>
  ({ persona: { telefono, no_contactar: noContactar }, capacidades: { contactar } })

describe('contactoDeFicha', () => {
  it('se contacta solo si la ficha lo permite Y la persona no pidió que no la llamen', () => {
    expect(contactoDeFicha(ficha(true, false))).toEqual({ telefono: '+51 988 777 666', contactar: true })
    expect(contactoDeFicha(ficha(false, false)).contactar).toBe(false)
    expect(contactoDeFicha(ficha(true, true)).contactar).toBe(false)
    expect(contactoDeFicha(ficha(false, true)).contactar).toBe(false)
  })
  it('sin número, el número es null (nada que pintar)', () => {
    expect(contactoDeFicha(ficha(true, false, null))).toEqual({ telefono: null, contactar: true })
  })
})

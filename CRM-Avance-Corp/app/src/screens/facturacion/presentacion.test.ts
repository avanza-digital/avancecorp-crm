import { describe, expect, it, vi } from 'vitest'
import * as formatos from '@/lib/format'
import { columnasDeDias, crearFormatoCifras } from './presentacion'

describe('presentación sin alterar importes', () => {
  it('8: reutiliza el formateo de una cifra repetida y separa moneda y métrica', () => {
    const espiar = vi.spyOn(formatos, 'money')
    const soles = crearFormatoCifras('PEN', 'capital')
    expect(soles(1234)).toBe('S/ 1,234')
    expect(soles(1234)).toBe('S/ 1,234')
    expect(espiar).toHaveBeenCalledTimes(1)
    expect(crearFormatoCifras('USD', 'capital')(1234)).toBe('US$ 1,234')
    expect(crearFormatoCifras('PEN', 'contratos')(1234)).toBe('1,234')
    expect(soles(1234, true)).toBe('1k')
    expect(soles(0, true)).toBe('·')
    expect(soles(-400, true)).toBe('-400')
    espiar.mockRestore()
  })
  it('E4: el rango funciona con un único día futuro y con una semana que cruza de mes', () => {
    expect(columnasDeDias(['2026-09-30', '2026-10-01', '2026-10-02'], '2026-09-30').at(-1)?.titulo).toBe('1–2 oct · por venir')
    expect(columnasDeDias(['2026-09-29', '2026-09-30', '2026-10-01'], '2026-09-29').at(-1)?.titulo).toBe('30 set–1 oct · por venir')
    expect(columnasDeDias(['2026-10-30', '2026-10-31'], '2026-10-30').at(-1)?.titulo).toBe('31 oct · por venir')
    expect(columnasDeDias(['2026-09-30'], '2026-10-09')[0]?.futura).toBeUndefined()
  })
})

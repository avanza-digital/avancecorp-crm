import { describe, expect, it, vi } from 'vitest'

vi.mock('@/lib/supabase', () => ({ sb: null }))

import { normalizarBusquedaPostgrest } from './crm-api'

describe('normalizarBusquedaPostgrest', () => {
  it('normaliza texto Unicode sin perder nombres válidos', () => {
    expect(normalizarBusquedaPostgrest('  María-José  ')).toEqual({
      texto: 'María-José',
      digitos: '',
    })
  })

  it('retira delimitadores y comodines de la sintaxis PostgREST', () => {
    const resultado = normalizarBusquedaPostgrest('Ana),activo.eq.false%_(')

    expect(resultado.texto).toBe('Ana activo eq false')
    expect(resultado.texto).not.toMatch(/[(),.%_]/)
  })

  it('separa y limita los dígitos usados para teléfono o DNI', () => {
    expect(normalizarBusquedaPostgrest('+51 999-888-777 123456789').digitos)
      .toBe('519998887771234')
    expect(normalizarBusquedaPostgrest(undefined)).toEqual({ texto: '', digitos: '' })
  })
})

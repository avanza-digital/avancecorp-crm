import { describe, expect, it } from 'vitest'
import { validarReunionOperativa } from './reunion-operativa'

describe('validarReunionOperativa', () => {
  it('no inventa modalidad cuando falta', () => {
    expect(validarReunionOperativa({ modalidad: '' })).toMatchObject({
      ok: false,
      codigo: 'modalidad_reunion_obligatoria',
    })
  })

  it('exige y normaliza la ubicación presencial', () => {
    expect(validarReunionOperativa({ modalidad: 'presencial', ubicacion: '   ' })).toMatchObject({
      ok: false,
      codigo: 'destino_reunion_obligatorio',
    })
    expect(validarReunionOperativa({
      modalidad: 'presencial',
      ubicacion: '  Av. Arequipa 123  ',
      enlace: 'https://no-se-debe-conservar.test',
    })).toEqual({
      ok: true,
      modalidad: 'presencial',
      ubicacion: 'Av. Arequipa 123',
      enlace: null,
    })
  })

  it.each([
    'http://meet.example.com/sala',
    'javascript:alert(1)',
    'https://usuario:clave@example.com/sala',
    'https://meet.example.com/sala con espacio',
  ])('rechaza un enlace virtual inseguro: %s', (enlace) => {
    expect(validarReunionOperativa({ modalidad: 'virtual', enlace })).toMatchObject({
      ok: false,
      codigo: 'enlace_reunion_invalido',
    })
  })

  it('acepta una cita virtual sin pedir enlace', () => {
    expect(validarReunionOperativa({ modalidad: 'virtual' })).toEqual({
      ok: true,
      modalidad: 'virtual',
      ubicacion: null,
      enlace: null,
    })
  })

  it('acepta una URL HTTPS y descarta la ubicación contradictoria', () => {
    expect(validarReunionOperativa({
      modalidad: 'virtual',
      ubicacion: 'No corresponde',
      enlace: '  https://meet.google.com/abc-defg-hij  ',
    })).toEqual({
      ok: true,
      modalidad: 'virtual',
      ubicacion: null,
      enlace: 'https://meet.google.com/abc-defg-hij',
    })
  })
})

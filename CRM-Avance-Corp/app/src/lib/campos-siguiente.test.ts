// Contrato del puente sugerencia ↔ formulario de la siguiente acción.
//
// Existe por un bug REAL medido el 2026-07-25: la sugerencia se calculaba en
// dos sitios y con una tarea genérica (una sola opción, preseleccionada) las
// dos fuentes se desincronizaban → panel visible pero vacío, y `RangeError` al
// confirmar. Estos tests fijan que el puente sea total y que NUNCA construya
// una fecha inválida.
import { describe, expect, it } from 'vitest'
import { camposDeSugerencia, isoDeCampos } from './campos-siguiente'
import type { SugerenciaSiguiente } from './motor-siguiente'

const sug = (parche: Partial<SugerenciaSiguiente> = {}): SugerenciaSiguiente => ({
  tipo: 'llamada',
  titulo: 'Llamar a Ana',
  vence_en: '2026-07-28T15:00:00.000Z', // 10:00 en Lima
  ...parche,
})

describe('camposDeSugerencia — la sugerencia llega ENTERA al formulario', () => {
  it('reparte tipo, título, fecha y hora en reloj de Lima', () => {
    expect(camposDeSugerencia(sug())).toEqual({
      tipo: 'llamada',
      titulo: 'Llamar a Ana',
      fecha: '2026-07-28',
      hora: '10:00',
    })
  })

  it('un instante de madrugada UTC no se va al día siguiente en Lima', () => {
    // 2026-07-29T02:00Z son las 21:00 del 28 en Lima: si se usara el reloj UTC
    // el analista vería la cita un día después de cuando es.
    expect(camposDeSugerencia(sug({ vence_en: '2026-07-29T02:00:00.000Z' }))).toMatchObject({
      fecha: '2026-07-28',
      hora: '21:00',
    })
  })

  it('conserva el tipo que propone el motor (la alternancia de canal no se pierde)', () => {
    expect(camposDeSugerencia(sug({ tipo: 'whatsapp' })).tipo).toBe('whatsapp')
  })
})

describe('isoDeCampos — jamás construye una fecha inválida', () => {
  it('ida y vuelta sin pérdida', () => {
    const campos = camposDeSugerencia(sug())
    expect(isoDeCampos(campos)).toBe('2026-07-28T15:00:00.000Z')
  })

  it('interpreta la hora en Lima, no en la zona del navegador', () => {
    expect(isoDeCampos({ tipo: 'llamada', titulo: 'x', fecha: '2026-07-28', hora: '10:00' }))
      .toBe('2026-07-28T15:00:00.000Z')
  })

  it.each([
    ['fecha vacía', '', '10:00'],
    ['hora vacía', '2026-07-28', ''],
    ['las dos vacías', '', ''],
    ['basura en la fecha', 'no-es-fecha', '10:00'],
    ['basura en la hora', '2026-07-28', 'x'],
    ['fecha a medias', '2026-07', '10:00'],
  ])('%s → null, NO una excepción (ese RangeError se llevaba el diálogo)', (_caso, fecha, hora) => {
    expect(isoDeCampos({ tipo: 'llamada', titulo: 'x', fecha, hora })).toBeNull()
  })

  it('EL AÑO 2000: con fecha Y hora vacías, Date.parse NO da NaN — da 2000-01-01', () => {
    // Verificado 2026-07-25: `Date.parse('T:00-05:00')` = 2000-01-01T10:00:00Z.
    // Sin validar la FORMA, vaciar los dos campos agendaba la siguiente acción
    // 26 años en el pasado, en silencio y con el toast diciendo que todo bien.
    expect(Number.isFinite(Date.parse('T:00-05:00'))).toBe(true)
    expect(isoDeCampos({ tipo: 'llamada', titulo: 'x', fecha: '', hora: '' })).toBeNull()
  })
})

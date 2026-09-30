// Coincidencia exacta del número capturado con los leads (F1.3.1 y F1.3.2), con
// los casos sintéticos de docs/gestion-diaria/piloto-telefonia/ejemplos-sinteticos.md
// (grupos A, B, C, E y F). Todos los números son inventados.
import { describe, expect, it } from 'vitest'
import {
  canonicoLegado, clasificarCoincidencia, digitosParaBuscar, formasCanonicas, leadCoincide, numeroCanonico,
  type LeadCandidato,
} from './coincidencia-telefono'

function lead(id: string, telefono: string, extra: Partial<LeadCandidato> = {}): LeadCandidato {
  return { id, nombre_completo: `LEAD ${id}`, telefono, telefono_alternativo: null, etapa: 'nuevo', activo: true, vendedor_id: 'v1', ...extra }
}

describe('las dos formas canónicas de la base', () => {
  it('la regla legado del trigger: 9 dígitos → +51; lo demás, + y los dígitos tal cual', () => {
    expect(canonicoLegado('900000001')).toBe('+51900000001')
    expect(canonicoLegado('+51 900 000 001')).toBe('+51900000001')
    expect(canonicoLegado('014457890')).toBe('+51014457890')
    expect(canonicoLegado('+34987654321')).toBe('+34987654321')
    expect(canonicoLegado('4457890')).toBe('+4457890')
    expect(canonicoLegado('')).toBeNull()
    expect(canonicoLegado('Número privado')).toBeNull()
  })

  it('un celular tiene una sola forma; un fijo, la E.164 y la legado con el 0; un internacional, la E.164', () => {
    expect([...formasCanonicas('900000001')]).toEqual(['+51900000001'])
    expect([...formasCanonicas('+51 900 000 001')]).toEqual(['+51900000001'])
    expect(new Set(formasCanonicas('014457890'))).toEqual(new Set(['+5114457890', '+51014457890']))
    expect(new Set(formasCanonicas('+5114457890'))).toEqual(new Set(['+5114457890', '+51014457890']))
    expect(new Set(formasCanonicas('084234567'))).toEqual(new Set(['+5184234567', '+51084234567']))
    expect([...formasCanonicas('+34987654321')]).toEqual(['+34987654321'])
    // Sin forma de teléfono solo queda la legado: lo que el trigger hubiera guardado.
    expect([...formasCanonicas('12345678')]).toEqual(['+12345678'])
    expect([...formasCanonicas('+51123456789')]).toEqual(['+51123456789'])
    expect(formasCanonicas('').size).toBe(0)
  })

  it('el número canónico es la E.164 cuando se reconoce y, si no, la legado', () => {
    expect(numeroCanonico('900 000 001')).toBe('+51900000001')
    expect(numeroCanonico('014457890')).toBe('+5114457890')
    expect(numeroCanonico('+51123456789')).toBe('+51123456789')
    expect(numeroCanonico(' Privado ')).toBe('Privado')
  })

  it('los dígitos para el servidor son los nacionales de un número peruano y todos los de uno extranjero', () => {
    expect(digitosParaBuscar('+51 900 000 001')).toBe('900000001')
    expect(digitosParaBuscar('014457890')).toBe('14457890')
    expect(digitosParaBuscar('+34987654321')).toBe('34987654321')
    expect(digitosParaBuscar('+51123456789')).toBe('51123456789')
    expect(digitosParaBuscar('12')).toBeNull()
    expect(digitosParaBuscar('')).toBeNull()
  })
})

describe('A · coincidencia exacta', () => {
  const L1 = lead('L1', '+51900000001')
  it.each([
    ['A1 canónico idéntico', '+51900000001'],
    ['A2 sin código de país', '900000001'],
    ['A3 con espacios', '+51 900 000 001'],
  ])('%s → único L1', (_caso, capturado) => {
    expect(clasificarCoincidencia(capturado, [L1], true)).toMatchObject({ estado: 'unico', lead: { id: 'L1' }, numero: '+51900000001', terminales: [] })
  })

  it('A4 el alternativo también identifica', () => {
    const L2 = lead('L2', '+51900000003', { telefono_alternativo: '+51900000002' })
    expect(clasificarCoincidencia('+51900000002', [L2], true)).toMatchObject({ estado: 'unico', lead: { id: 'L2' } })
    expect(leadCoincide(L2, formasCanonicas('+51900000002'))).toBe(true)
    expect(leadCoincide(L2, formasCanonicas('+51900000009'))).toBe(false)
  })
})

describe('B · históricos (dos formas guardadas)', () => {
  it('B1/B2 un fijo guardado en forma legado se encuentra tecleado con 0 o en E.164', () => {
    const L3 = lead('L3', '+51014457890')
    expect(clasificarCoincidencia('014457890', [L3], true)).toMatchObject({ estado: 'unico', lead: { id: 'L3' }, numero: '+5114457890' })
    expect(clasificarCoincidencia('+5114457890', [L3], true)).toMatchObject({ estado: 'unico', lead: { id: 'L3' } })
  })
  it('B3 el alternativo en forma nueva', () => {
    const L4 = lead('L4', '+51900000004', { telefono_alternativo: '+5114457890' })
    expect(clasificarCoincidencia('014457890', [L4], true)).toMatchObject({ estado: 'unico', lead: { id: 'L4' } })
  })
  it('B4 otra provincia', () => {
    const L5 = lead('L5', '+51084234567')
    expect(clasificarCoincidencia('084234567', [L5], true)).toMatchObject({ estado: 'unico', lead: { id: 'L5' } })
  })
})

describe('C · compartidos y reciclados', () => {
  it('C1 dos leads distintos con el número → ambiguo', () => {
    const L6 = lead('L6', '+51900000010')
    const L7 = lead('L7', '+51900000099', { telefono_alternativo: '+51900000010' })
    expect(clasificarCoincidencia('+51900000010', [L6, L7], true)).toMatchObject({ estado: 'ambiguo', leads: [{ id: 'L6' }, { id: 'L7' }] })
  })
  it('C2 solo cuentan los vivos; el descartado es contexto', () => {
    const L8 = lead('L8', '+51900000011')
    const L9 = lead('L9', '+51900000011', { etapa: 'descartado' })
    expect(clasificarCoincidencia('+51900000011', [L9, L8], true)).toMatchObject({ estado: 'unico', lead: { id: 'L8' }, terminales: [{ id: 'L9' }] })
  })
  it('C3 el mismo lead en dos campos (y repetido en la página) es un lead', () => {
    const L10 = lead('L10', '+51900000012', { telefono_alternativo: '+51900000012' })
    expect(clasificarCoincidencia('+51900000012', [L10, L10], true)).toMatchObject({ estado: 'unico', lead: { id: 'L10' } })
  })
  it('C4 dos convertidos con el número → sin coincidencia en leads, con el aviso de que existe como cliente', () => {
    const L11 = lead('L11', '+51900000013', { etapa: 'convertido' })
    const L12 = lead('L12', '+51900000013', { etapa: 'convertido' })
    expect(clasificarCoincidencia('+51900000013', [L11, L12], true)).toMatchObject({ estado: 'sin_coincidencia', reconocido: true, terminales: [{ id: 'L11' }, { id: 'L12' }] })
  })
  it('un lead inactivo (borrado suave) tampoco cuenta', () => {
    const L = lead('L', '+51900000014', { activo: false })
    expect(clasificarCoincidencia('+51900000014', [L], true)).toMatchObject({ estado: 'sin_coincidencia', terminales: [{ id: 'L' }] })
  })
})

describe('E · internacionales, ocultos e inválidos', () => {
  it('E1 mismo sufijo, distinto país: nunca se recortan nueve dígitos', () => {
    const L18 = lead('L18', '+51987654321')
    expect(clasificarCoincidencia('+34987654321', [L18], true)).toMatchObject({ estado: 'sin_coincidencia', reconocido: true, numero: '+34987654321' })
  })
  it('E2 E.164 completo coincide en el alternativo', () => {
    const L19 = lead('L19', '+51900000019', { telefono_alternativo: '+34987654321' })
    expect(clasificarCoincidencia('+34987654321', [L19], true)).toMatchObject({ estado: 'unico', lead: { id: 'L19' } })
  })
  it('E3 vacío o «Número privado» → inválido (oculto), no error', () => {
    expect(clasificarCoincidencia('', [], true)).toEqual({ estado: 'invalido', numero: '' })
    expect(clasificarCoincidencia('Número privado', [lead('L', '+51900000001')], true)).toMatchObject({ estado: 'invalido' })
  })
  it('E4 ocho dígitos pelados (parece DNI) no son un teléfono: sin coincidencia, no reconocido', () => {
    const L20 = lead('L20', '+51900000020')
    expect(clasificarCoincidencia('12345678', [L20], true)).toMatchObject({ estado: 'sin_coincidencia', reconocido: false, numero: '+12345678' })
  })
  it('E5 dice ser peruano sin forma de celular ni de fijo: sin coincidencia, no reconocido', () => {
    expect(clasificarCoincidencia('+51123456789', [], true)).toMatchObject({ estado: 'sin_coincidencia', reconocido: false })
  })
  it('D3 un dígito distinto es otro número; no se corrige por parecido', () => {
    const L15 = lead('L15', '+51900000030')
    expect(clasificarCoincidencia('+51900000031', [L15], true)).toMatchObject({ estado: 'sin_coincidencia' })
  })
})

describe('F · completitud de la búsqueda', () => {
  it('F1 una página llena no demuestra unicidad: el mismo exacto es único solo si la recuperación fue completa', () => {
    const exacto = lead('L50', '+51900000050')
    const parecidos = Array.from({ length: 8 }, (_, i) => lead(`P${i}`, `+5190000005${i}1`))
    expect(clasificarCoincidencia('+51900000050', [exacto, ...parecidos], false)).toMatchObject({ estado: 'incompleto', leads: [{ id: 'L50' }] })
    expect(clasificarCoincidencia('+51900000050', [exacto, ...parecidos], true)).toMatchObject({ estado: 'unico', lead: { id: 'L50' } })
    // Sin exactos y con la página llena, también puede haber más: incompleto, con lista vacía.
    expect(clasificarCoincidencia('+51900000050', parecidos, false)).toMatchObject({ estado: 'incompleto', leads: [] })
  })
  it('varios exactos siguen siendo ambiguos aunque la página esté llena', () => {
    const dos = [lead('A', '+51900000050'), lead('B', '+51900000050')]
    expect(clasificarCoincidencia('+51900000050', dos, false)).toMatchObject({ estado: 'ambiguo' })
  })
})

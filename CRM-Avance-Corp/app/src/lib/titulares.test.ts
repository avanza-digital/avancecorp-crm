// Tests del núcleo de co-titulares — espejo de los casos que cubre el portal
// en public_html/tests/titulares-core.test.mjs, más la regla extra del CRM
// (documentos duplicados). Si un caso difiere del portal, gana el portal.
import { describe, expect, it } from 'vitest'
import {
  etiquetaDocumento,
  MAX_TITULARES,
  normalizarTitular,
  normalizarTitulares,
  titularVacio,
} from './titulares'

describe('etiquetaDocumento (solo lectura)', () => {
  it('DNI va sin sigla; CE y PASAPORTE la anteponen (espejo del portal)', () => {
    expect(etiquetaDocumento('DNI', '12345678')).toBe('12345678')
    expect(etiquetaDocumento('CE', '001234567')).toBe('CE 001234567')
    expect(etiquetaDocumento('PASAPORTE', 'AB123456')).toBe('PASAPORTE AB123456')
  })

  it('tipo basura o ausente cae al default histórico DNI', () => {
    expect(etiquetaDocumento(null, '12345678')).toBe('12345678')
    expect(etiquetaDocumento(' ce ', '001234567')).toBe('CE 001234567')
  })
})

describe('normalizarTitular', () => {
  it('normaliza el nombre como la BD: MAYÚSCULA, trim y espacios colapsados', () => {
    const r = normalizarTitular({ tipo_documento: 'DNI', documento: '87654321', nombre_completo: '  juana   pérez  ' })
    expect(r).toEqual({
      ok: true,
      valor: { nombre_completo: 'JUANA PÉREZ', tipo_documento: 'DNI', documento: '87654321' },
    })
  })

  it('pasaporte sale en MAYÚSCULA canónica (ab1234 → AB1234)', () => {
    const r = normalizarTitular({ tipo_documento: 'PASAPORTE', documento: 'ab1234', nombre_completo: 'ana lo' })
    expect(r.ok && r.valor.documento).toBe('AB1234')
  })

  it('sin nombre → error de nombre; documento inválido → el error DEL TIPO', () => {
    expect(normalizarTitular({ tipo_documento: 'DNI', documento: '87654321', nombre_completo: '  ' })).toEqual({
      ok: false,
      error: 'Escribe el nombre completo del co-titular.',
    })
    const dniCorto = normalizarTitular({ tipo_documento: 'DNI', documento: '123', nombre_completo: 'ANA' })
    expect(dniCorto.ok).toBe(false)
    if (!dniCorto.ok) expect(dniCorto.error).toMatch(/8 dígitos/)
    const ceCorto = normalizarTitular({ tipo_documento: 'CE', documento: '12345678', nombre_completo: 'ANA' })
    expect(ceCorto.ok).toBe(false)
    if (!ceCorto.ok) expect(ceCorto.error).toMatch(/9 y 12/)
  })
})

describe('normalizarTitulares (lista del editor)', () => {
  it('las filas completamente vacías se ignoran en silencio', () => {
    const r = normalizarTitulares([
      titularVacio(),
      { tipo_documento: 'DNI', documento: '87654321', nombre_completo: 'juana perez' },
      titularVacio(),
    ])
    expect(r).toEqual({
      ok: true,
      titulares: [{ nombre_completo: 'JUANA PEREZ', tipo_documento: 'DNI', documento: '87654321' }],
    })
  })

  it('una fila a medio llenar da error con su POSICIÓN (base 1)', () => {
    const r = normalizarTitulares([
      { tipo_documento: 'DNI', documento: '87654321', nombre_completo: 'ANA UNO' },
      { tipo_documento: 'DNI', documento: '11223344', nombre_completo: '' }, // sin nombre
    ])
    expect(r.ok).toBe(false)
    if (!r.ok) {
      expect(r.error).toBe('Co-titular 2: Escribe el nombre completo del co-titular.')
      expect(r.index).toBe(1)
    }
  })

  it('documento repetido entre filas → error (regla extra del CRM)', () => {
    const r = normalizarTitulares([
      { tipo_documento: 'DNI', documento: '87654321', nombre_completo: 'ANA UNO' },
      { tipo_documento: 'DNI', documento: '87654321', nombre_completo: 'ANA DOS' },
    ])
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.error).toMatch(/repetido/)
  })

  it('el MISMO número con tipo distinto NO es duplicado (DNI vs pasaporte)', () => {
    const r = normalizarTitulares([
      { tipo_documento: 'DNI', documento: '87654321', nombre_completo: 'ANA UNO' },
      { tipo_documento: 'PASAPORTE', documento: '87654321', nombre_completo: 'ANA DOS' },
    ])
    expect(r.ok).toBe(true)
  })

  it(`más de ${MAX_TITULARES} co-titulares → error de tope (espejo del portal)`, () => {
    const filas = Array.from({ length: MAX_TITULARES + 1 }, (_, i) => ({
      tipo_documento: 'DNI' as const,
      documento: String(10000000 + i),
      nombre_completo: `TITULAR ${i + 1}`,
    }))
    const r = normalizarTitulares(filas)
    expect(r).toEqual({ ok: false, error: `Máximo ${MAX_TITULARES} co-titulares por contrato.` })
  })

  it('lista vacía o solo filas vacías → ok con [] (contrato sin co-titulares)', () => {
    expect(normalizarTitulares([])).toEqual({ ok: true, titulares: [] })
    expect(normalizarTitulares([titularVacio(), titularVacio()])).toEqual({ ok: true, titulares: [] })
  })
})

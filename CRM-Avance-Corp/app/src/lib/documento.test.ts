// Candado anti-drift de las reglas de documento: las regex deben ser VERBATIM
// las del portal (public_html/js/admin/documento-core.js). Las fuentes esperadas
// se fijan aquí A MANO (copiadas del portal, no derivadas del módulo bajo
// prueba): si cambias una regla en una copia sin la otra, este test revienta.
// (El candado equivalente del lado portal es tests/documento-core.test.mjs.)
import { describe, expect, it } from 'vitest'
import {
  claveTemporalDesdeDocumento,
  esTipoDocumento,
  normalizarDocumento,
  normalizarTipoDocumento,
  RE_DOC_GENERICO,
  TIPOS_DOCUMENTO,
  TIPOS_DOCUMENTO_K,
  validarDocumento,
} from './documento'

// Las fuentes esperadas, escritas VERBATIM (no derivadas del módulo bajo prueba).
const REGEX_ESPERADAS = {
  DNI: '^\\d{8}$',
  CE: '^\\d{9,12}$',
  PASAPORTE: '^[A-Z0-9]{6,12}$',
} as const

describe('regex verbatim (espejo del portal)', () => {
  it.each(Object.entries(REGEX_ESPERADAS))('%s usa la regex canónica', (tipo, fuente) => {
    expect(TIPOS_DOCUMENTO[tipo as keyof typeof TIPOS_DOCUMENTO].regex.source).toBe(fuente)
  })

  it('el documento genérico (beneficiario) sigue siendo 8–12 dígitos', () => {
    expect(RE_DOC_GENERICO.source).toBe('^[0-9]{8,12}$')
  })
})

describe('normalización de tipo', () => {
  it('absorbe basura y default histórico DNI', () => {
    expect(normalizarTipoDocumento(' ce ')).toBe('CE')
    expect(normalizarTipoDocumento('pasaporte')).toBe('PASAPORTE')
    expect(normalizarTipoDocumento(undefined)).toBe('DNI')
    expect(normalizarTipoDocumento('RUC')).toBe('DNI')
  })

  it('esTipoDocumento NO reconoce etiquetas humanas (deben dar error explícito, no caer a DNI)', () => {
    expect(esTipoDocumento('CE')).toBe(true)
    expect(esTipoDocumento(' dni ')).toBe(true)
    expect(esTipoDocumento('CARNÉ DE EXTRANJERÍA')).toBe(false)
    expect(esTipoDocumento(null)).toBe(false)
  })

  it('el catálogo runtime expone exactamente los 3 tipos', () => {
    expect(TIPOS_DOCUMENTO_K).toEqual(['DNI', 'CE', 'PASAPORTE'])
  })
})

describe('validarDocumento por tipo', () => {
  it('DNI: exactamente 8 dígitos', () => {
    expect(validarDocumento('DNI', '45781234')).toEqual({ ok: true, valor: '45781234' })
    expect(validarDocumento('DNI', ' 45781234 ')).toEqual({ ok: true, valor: '45781234' })
    expect(validarDocumento('DNI', '4578123')).toMatchObject({ ok: false, error: TIPOS_DOCUMENTO.DNI.error })
    expect(validarDocumento('DNI', '457812345')).toMatchObject({ ok: false })
    expect(validarDocumento('DNI', '4578123A')).toMatchObject({ ok: false })
  })

  it('CE: entre 9 y 12 dígitos', () => {
    expect(validarDocumento('CE', '001234567')).toEqual({ ok: true, valor: '001234567' })
    expect(validarDocumento('CE', '123456789012')).toEqual({ ok: true, valor: '123456789012' })
    expect(validarDocumento('CE', '12345678')).toMatchObject({ ok: false, error: TIPOS_DOCUMENTO.CE.error })
    expect(validarDocumento('CE', '1234567890123')).toMatchObject({ ok: false })
  })

  it('PASAPORTE: 6–12 alfanumérico, normaliza a MAYÚSCULA antes de validar', () => {
    expect(validarDocumento('PASAPORTE', 'ab123456')).toEqual({ ok: true, valor: 'AB123456' })
    expect(validarDocumento('PASAPORTE', 'AB1234')).toEqual({ ok: true, valor: 'AB1234' })
    expect(validarDocumento('PASAPORTE', 'A1')).toMatchObject({ ok: false, error: TIPOS_DOCUMENTO.PASAPORTE.error })
    expect(validarDocumento('PASAPORTE', 'AB-123456')).toMatchObject({ ok: false })
  })

  it('normalizarDocumento: uppercase solo para tipos alfanuméricos', () => {
    expect(normalizarDocumento('PASAPORTE', ' ab12x ')).toBe('AB12X')
    expect(normalizarDocumento('DNI', ' 12345678 ')).toBe('12345678')
  })
})

describe('claveTemporalDesdeDocumento', () => {
  it('completa con ceros a la IZQUIERDA hasta 8 (mínimo de Supabase Auth)', () => {
    expect(claveTemporalDesdeDocumento('1234567')).toBe('01234567')
    expect(claveTemporalDesdeDocumento('AB1234')).toBe('00AB1234')
  })

  it('no toca documentos de 8 o más caracteres', () => {
    expect(claveTemporalDesdeDocumento('45781234')).toBe('45781234')
    expect(claveTemporalDesdeDocumento('123456789012')).toBe('123456789012')
  })
})

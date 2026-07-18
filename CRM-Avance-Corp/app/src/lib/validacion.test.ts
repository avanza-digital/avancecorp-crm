import { describe, expect, it } from 'vitest'
import {
  EDAD_MINIMA,
  MONTO_ESTIMADO_MAX,
  edadCumplida,
  normalizarTelefono,
  validarCamposLead,
} from './validacion'

describe('normalizarTelefono', () => {
  it.each([
    ['999 888 777', '+51999888777'],
    ['+51 999-888-777', '+51999888777'],
    ['(999) 888.777', '+51999888777'],
  ])('normaliza %s', (entrada, esperado) => {
    expect(normalizarTelefono(entrada)).toBe(esperado)
  })

  it.each(['', '12345678', '+5199988877', '+52999888777', 'javascript:alert(1)'])(
    'rechaza %s',
    (entrada) => expect(normalizarTelefono(entrada)).toBeNull(),
  )
})

describe('validarCamposLead', () => {
  it('normaliza el teléfono al formato +51…', () => {
    expect(validarCamposLead({ telefono: '987654321' })).toEqual({
      ok: true,
      valores: { telefono: '+51987654321' },
    })
  })

  it('teléfono inválido → codigo telefono_invalido anclado a su campo', () => {
    expect(validarCamposLead({ telefono: '12345678' })).toMatchObject({
      ok: false,
      codigo: 'telefono_invalido',
      campo: 'telefono',
    })
  })

  it('dni vacío se normaliza a null', () => {
    expect(validarCamposLead({ dni: '' })).toEqual({ ok: true, valores: { dni: null } })
    expect(validarCamposLead({ dni: null })).toEqual({ ok: true, valores: { dni: null } })
  })

  it('dni que no son 8 dígitos exactos → dni_invalido', () => {
    expect(validarCamposLead({ dni: '1234567' })).toMatchObject({
      ok: false,
      codigo: 'dni_invalido',
      campo: 'dni',
    })
    expect(validarCamposLead({ dni: '12345678a' })).toMatchObject({
      ok: false,
      codigo: 'dni_invalido',
      campo: 'dni',
    })
  })

  it('correo inválido → correo_invalido anclado a su campo', () => {
    expect(validarCamposLead({ correo: 'no-es-correo' })).toMatchObject({
      ok: false,
      codigo: 'correo_invalido',
      campo: 'correo',
    })
  })

  it('correo vacío se normaliza a null', () => {
    expect(validarCamposLead({ correo: '' })).toEqual({ ok: true, valores: { correo: null } })
  })

  it('origen fuera del catálogo → origen_invalido', () => {
    expect(validarCamposLead({ origen: 'tiktok' })).toMatchObject({
      ok: false,
      codigo: 'origen_invalido',
      campo: 'origen',
    })
  })

  it.each(['landing', 'formulario'] as const)('acepta el origen activo %s', (origen) => {
    expect(validarCamposLead({ origen })).toEqual({ ok: true, valores: { origen } })
  })

  it.each(['web', 'campania', 'whatsapp'] as const)(
    'mantiene lectura compatible del origen histórico %s',
    (origen) => {
      expect(validarCamposLead({ origen })).toEqual({ ok: true, valores: { origen } })
    },
  )

  it.each([null, 0, -1] as const)('monto %s → monto_invalido', (monto) => {
    expect(validarCamposLead({ monto_estimado: monto })).toMatchObject({
      ok: false,
      codigo: 'monto_invalido',
      campo: 'monto_estimado',
    })
  })

  it('acepta y conserva un monto positivo', () => {
    expect(validarCamposLead({ monto_estimado: 5000.5 })).toEqual({
      ok: true,
      valores: { monto_estimado: 5000.5 },
    })
  })

  it.each([0.001, 5000.999])('rechaza monto con más de dos decimales: %s', (monto) => {
    expect(validarCamposLead({ monto_estimado: monto })).toMatchObject({
      ok: false,
      codigo: 'monto_invalido',
      campo: 'monto_estimado',
    })
  })

  it('respeta los bordes exactos de numeric(12,2)', () => {
    expect(validarCamposLead({ monto_estimado: 0.01 })).toEqual({
      ok: true,
      valores: { monto_estimado: 0.01 },
    })
    expect(validarCamposLead({ monto_estimado: MONTO_ESTIMADO_MAX })).toEqual({
      ok: true,
      valores: { monto_estimado: MONTO_ESTIMADO_MAX },
    })
    expect(validarCamposLead({ monto_estimado: MONTO_ESTIMADO_MAX + 0.01 })).toMatchObject({
      ok: false,
      codigo: 'monto_invalido',
      campo: 'monto_estimado',
    })
  })

  it('valida la moneda como parte del mismo contrato comercial', () => {
    expect(validarCamposLead({ moneda: 'USD' })).toEqual({
      ok: true,
      valores: { moneda: 'USD' },
    })
    expect(validarCamposLead({ moneda: 'EUR' })).toMatchObject({
      ok: false,
      codigo: 'moneda_invalida',
      campo: 'moneda',
    })
  })

  it('los campos AUSENTES (undefined) no se validan: objeto vacío → ok con valores {}', () => {
    expect(validarCamposLead({})).toEqual({ ok: true, valores: {} })
    // Editar solo un campo no dispara validaciones de los demás.
    expect(validarCamposLead({ nombre_completo: 'Ana Torres' })).toEqual({
      ok: true,
      valores: { nombre_completo: 'Ana Torres' },
    })
  })

  it('nombre solo con espacios → nombre_obligatorio', () => {
    expect(validarCamposLead({ nombre_completo: '  ' })).toMatchObject({
      ok: false,
      codigo: 'nombre_obligatorio',
      campo: 'nombre_completo',
    })
  })

  it('género: solo F/M; vacío es un dato legítimo (→ null), no un error', () => {
    expect(validarCamposLead({ genero: 'F' })).toEqual({ ok: true, valores: { genero: 'F' } })
    expect(validarCamposLead({ genero: '' })).toEqual({ ok: true, valores: { genero: null } })
    expect(validarCamposLead({ genero: null })).toEqual({ ok: true, valores: { genero: null } })
    expect(validarCamposLead({ genero: 'X' })).toMatchObject({
      ok: false,
      codigo: 'genero_invalido',
      campo: 'genero',
    })
  })

  it('fecha de nacimiento: rechaza forma inválida y días que no existen', () => {
    const hoy = new Date('2026-07-18T12:00:00Z')
    expect(validarCamposLead({ fecha_nacimiento: '1990-05-20' }, hoy)).toEqual({
      ok: true,
      valores: { fecha_nacimiento: '1990-05-20' },
    })
    expect(validarCamposLead({ fecha_nacimiento: '' }, hoy)).toEqual({
      ok: true,
      valores: { fecha_nacimiento: null },
    })
    // 2026 no es bisiesto: el 29 de febrero no existe y la regex sola lo deja pasar.
    expect(validarCamposLead({ fecha_nacimiento: '2026-02-29' }, hoy)).toMatchObject({
      ok: false,
      codigo: 'fecha_nacimiento_invalida',
    })
    expect(validarCamposLead({ fecha_nacimiento: '20/05/1990' }, hoy)).toMatchObject({
      ok: false,
      codigo: 'fecha_nacimiento_invalida',
    })
    // Espejo del CHECK leads_fecha_nacimiento_valida (límite inferior).
    expect(validarCamposLead({ fecha_nacimiento: '1899-12-31' }, hoy)).toMatchObject({
      ok: false,
      codigo: 'fecha_nacimiento_invalida',
    })
  })

  it(`exige ${EDAD_MINIMA} años cumplidos — el límite se evalúa el día del cumpleaños`, () => {
    const hoy = new Date('2026-07-18T12:00:00Z')
    // Cumple 18 HOY → entra.
    expect(validarCamposLead({ fecha_nacimiento: '2008-07-18' }, hoy)).toMatchObject({ ok: true })
    // Los cumple mañana → todavía no.
    expect(validarCamposLead({ fecha_nacimiento: '2008-07-19' }, hoy)).toMatchObject({
      ok: false,
      codigo: 'menor_de_edad',
      campo: 'fecha_nacimiento',
    })
  })
})

describe('edadCumplida', () => {
  const hoy = new Date('2026-07-18T12:00:00Z')

  it.each([
    ['2008-07-18', 18], // cumpleaños hoy
    ['2008-07-19', 17], // mañana
    ['2008-07-17', 18], // ayer
    ['1990-12-31', 35], // cumpleaños aún por venir este año
  ])('%s → %i años', (iso, esperado) => {
    expect(edadCumplida(iso, hoy)).toBe(esperado)
  })
})

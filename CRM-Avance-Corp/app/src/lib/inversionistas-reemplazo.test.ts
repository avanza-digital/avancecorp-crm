import { describe, expect, it } from 'vitest'
import { diferenciasDeCarga, esVentaDeLead, inversionReemplazable, mesLargo, type InversionFuente } from './inversionistas'
import { puedeReemplazarInversion } from './roles'
import { inversionF5 } from '@/test/fixtures/f5'

const avance = (over: Partial<InversionFuente> = {}): InversionFuente => ({
  ...inversionF5, empresa: 'avance', perfil_id: '44444444-4444-4444-8444-444444444444', numero: '2026-01-999999', capital: 5000,
  moneda: 'PEN', estado: 'activo', es_inicial: false, lead_id: null, es_demo: false, vence_en: '2027-10-05', cotitulares: [],
  contrato: { fecha_inicio: '2026-10-05', tasa_anual: 15, modalidad: 'mensual', tipo_interes: 'simple', categoria: 'nuevo' },
  ...over,
})
const identidad = (rol: string, rol_portal: string) => ({ rol, rol_portal }) as Parameters<typeof puedeReemplazarInversion>[0]

describe('quién ve «Reemplazar inversión» (espejo de las puertas; el servidor decide igual)', () => {
  it.each([
    ['gerencia', 'admin', false, true], ['gerencia', 'superadmin', true, true],
    ['vendedor', 'admin', false, true], ['vendedor', 'admin', true, false],   // la venta de un lead exige además Gerencia
    ['gerencia', 'analista', false, false], ['vendedor', 'analista', false, false], ['directorio', 'directorio', false, false],
  ])('%s / %s · venta de lead %s → %s', (rol, portal, venta, esperado) => {
    expect(puedeReemplazarInversion(identidad(rol, portal), avance(venta ? { es_inicial: true } : {}))).toBe(esperado)
  })
  it('una inversión de cooperativa no se reemplaza (por ahora solo Avance)', () => {
    expect(puedeReemplazarInversion(identidad('gerencia', 'admin'), avance({ empresa: 'qorilazo' }))).toBe(false)
  })
  it('sin sesión, no', () => {
    expect(puedeReemplazarInversion(null, avance())).toBe(false)
  })
})

describe('qué inversión se ofrece', () => {
  it('Avance «nuevo», real y activa o vencida', () => {
    expect(inversionReemplazable(avance())).toBe(true)
    expect(inversionReemplazable(avance({ estado: 'vencido' }))).toBe(true)
  })
  it.each([
    ['renovación', { contrato: { fecha_inicio: '2026-10-05', tasa_anual: 15, modalidad: 'mensual' as const, tipo_interes: 'simple' as const, categoria: 'renovacion' } }],
    ['upgrade', { contrato: { fecha_inicio: '2026-10-05', tasa_anual: 15, modalidad: 'mensual' as const, tipo_interes: 'simple' as const, categoria: 'upgrade' } }],
    ['demostración', { es_demo: true }], ['renovada', { estado: 'renovado' }], ['cooperativa', { empresa: 'prodelco' as const }],
    ['sin contrato', { contrato: null }],
  ])('%s no', (_n, over) => {
    expect(inversionReemplazable(avance(over as Partial<InversionFuente>))).toBe(false)
  })
  it('venta de un lead: por lead o por ser la inicial', () => {
    expect(esVentaDeLead({ lead_id: '11111111-1111-4111-8111-111111111111', es_inicial: false })).toBe(true)
    expect(esVentaDeLead({ lead_id: null, es_inicial: true })).toBe(true)
    expect(esVentaDeLead({ lead_id: null, es_inicial: null })).toBe(false)
  })
})

describe('pista de carga doble', () => {
  it('igual: sin diferencias (los cotitulares por documento, en cualquier orden y con espacios)', () => {
    const a = avance({ cotitulares: [{ orden: 1, nombre: 'A', tipo_documento: 'DNI', documento: '41' }, { orden: 2, nombre: 'B', tipo_documento: 'DNI', documento: '42' }] })
    const b = avance({ cotitulares: [{ orden: 1, nombre: 'B', tipo_documento: 'DNI', documento: ' 42 ' }, { orden: 2, nombre: 'A', tipo_documento: 'DNI', documento: '41' }] })
    expect(diferenciasDeCarga(a, b)).toEqual([])
  })
  it('distinta: dice en qué', () => {
    expect(diferenciasDeCarga(avance(), avance({ capital: 800, vence_en: '2027-11-05',
      contrato: { fecha_inicio: '2026-10-05', tasa_anual: 18, modalidad: 'anual', tipo_interes: 'simple', categoria: 'nuevo' },
      cotitulares: [{ orden: 1, nombre: 'C', tipo_documento: 'DNI', documento: '43' }] })))
      .toEqual(['capital', 'tasa', 'fechas', 'pago de intereses', 'cotitulares'])
  })
})

describe('mes largo', () => {
  it('«2026-09-01» → «Septiembre 2026»; lo que no es fecha queda igual', () => {
    expect(mesLargo('2026-09-01')).toBe('Septiembre 2026')
    expect(mesLargo('2026-12-01')).toBe('Diciembre 2026')
    expect(mesLargo('raro')).toBe('raro')
  })
})

import { describe, expect, it } from 'vitest'
import { fechaHora, fmtFecha, iniciales, money, moneyK, numero, primerNombre } from './format'

describe('formato monetario', () => {
  it('separa miles en todas las cantidades', () => {
    expect(numero(1_500_000)).toBe('1,500,000')
    expect(numero(12_345.67, 2)).toBe('12,345.67')
    expect(numero(null)).toBe('—')
  })

  it('formatea PEN y USD sin mezclar símbolos', () => {
    expect(money(1_234.5)).toBe('S/ 1,234.5')
    expect(money(1_234.5, 'USD')).toBe('US$ 1,234.5')
    expect(money(-12.25)).toBe('S/ -12.25')
  })

  it('trata valores ausentes y no finitos como cero seguro', () => {
    expect(money(null)).toBe('S/ 0')
    expect(money(undefined, 'USD')).toBe('US$ 0')
    expect(money(Number.NaN)).toBe('S/ 0')
    expect(money(Number.POSITIVE_INFINITY)).toBe('S/ 0')
    expect(moneyK(Number.NEGATIVE_INFINITY, 'USD')).toBe('US$ 0')
  })

  it('abrevia miles conservando signo y una precisión útil', () => {
    expect(moneyK(1_000)).toBe('S/ 1k')
    expect(moneyK(1_250, 'USD')).toBe('US$ 1.3k')
    expect(moneyK(-1_500)).toBe('S/ -1.5k')
    expect(moneyK(999)).toBe('S/ 999')
  })
})

describe('formato de nombres y fechas', () => {
  it('genera iniciales estables y nunca vacías', () => {
    expect(iniciales('  María   López Castro ')).toBe('ML')
    expect(iniciales('ana')).toBe('A')
    expect(iniciales('')).toBe('·')
    expect(iniciales(null)).toBe('·')
  })

  it('normaliza solo el primer nombre para saludos', () => {
    expect(primerNombre('  JOSÉ   PÉREZ ')).toBe('José')
    expect(primerNombre('maría')).toBe('María')
    expect(primerNombre(undefined)).toBe('')
  })

  it('rechaza fechas vacías o inválidas y localiza fechas válidas', () => {
    expect(fmtFecha(null)).toBe('—')
    expect(fmtFecha('fecha-invalida')).toBe('—')
    expect(fmtFecha('2026-07-10T12:00:00.000Z')).toMatch(/10.*jul.*2026/i)
  })

  // Las fechas del cronograma vienen sin hora; leerlas como UTC las corría un
  // día atrás en Perú (UTC-5) — se veía "14 jul" para el 15/07.
  it('muestra las fechas sin hora en el día correcto (no las lee como UTC)', () => {
    expect(fmtFecha('2026-07-15')).toMatch(/15.*jul.*2026/i)
    expect(fmtFecha('2026-01-01')).toMatch(/01.*ene.*2026/i)
    expect(fmtFecha('2026-13-45')).toBe('—')
  })
})

// fechaHora es para TIMESTAMPS completos (creado_en) — fecha CON año + hora
// local; su contraste es fmtFecha, que formatea fechas SIN hora ('YYYY-MM-DD',
// cronograma) y por eso parsea en local para esquivar el bug UTC.
describe('fechaHora', () => {
  // toMatch, no igualdad exacta: toLocaleString varía coma/espacios entre
  // motores (Node/WebKit/Blink) — se pinea el contenido, no la puntuación.
  it('localiza un timestamp ISO con día, mes, AÑO de 2 dígitos y hora', () => {
    expect(fechaHora('2026-07-15T12:00:00.000Z')).toMatch(/15.*jul.*26.*\d{2}:\d{2}/i)
  })

  it('devuelve — para null, undefined o timestamps inválidos', () => {
    expect(fechaHora(null)).toBe('—')
    expect(fechaHora(undefined)).toBe('—')
    expect(fechaHora('no-es-fecha')).toBe('—')
  })
})

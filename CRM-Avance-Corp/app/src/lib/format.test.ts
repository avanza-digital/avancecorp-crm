import { describe, expect, it } from 'vitest'
import {
  digitosDeMonto, fechaHora, fmtFecha, iniciales, money, moneyK, montoDesdeTexto,
  montoEditable, numero, primerNombre,
} from './format'

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

// El campo de meta mensual del mes: cifras de seis y siete dígitos que se leen
// mal sin separadores («¿50 mil o 500 mil?»), y un `type="number"` que al
// borrarse repintaba un 0 imborrable porque Number('') es 0.
describe('importes que se escriben', () => {
  it('separa miles mientras se teclea', () => {
    expect(montoEditable('50000')).toBe('50,000')
    expect(montoEditable('500000')).toBe('500,000')
    expect(montoEditable('1500000')).toBe('1,500,000')
  })

  it('deja vacío lo vacío — «sin meta» no es «meta cero»', () => {
    expect(montoEditable('')).toBe('')
    expect(montoEditable('S/ ')).toBe('')
    expect(montoDesdeTexto('')).toBe(0)
  })

  it('reformatea lo ya formateado sin duplicar separadores', () => {
    expect(montoEditable('500,000')).toBe('500,000')
    expect(montoEditable(montoEditable('1234567'))).toBe('1,234,567')
  })

  it('tolera lo que llega pegado de una hoja de cálculo', () => {
    expect(montoEditable('S/ 1 234 567')).toBe('1,234,567')
    expect(montoEditable('  80.000  ')).toBe('80,000')
    expect(montoDesdeTexto('S/ 1,234,567')).toBe(1_234_567)
  })

  it('come los ceros a la izquierda en vez de arrastrarlos', () => {
    expect(montoEditable('007')).toBe('7')
    expect(montoEditable('0')).toBe('0')
    expect(montoDesdeTexto('007')).toBe(7)
  })

  it('ignora letras y signos sin romperse', () => {
    expect(digitosDeMonto('a1b2c3')).toBe('123')
    expect(montoEditable('-50000')).toBe('50,000')
    expect(montoEditable('abc')).toBe('')
  })
})

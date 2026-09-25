import { describe, expect, it } from 'vitest'
import {
  digitosDeMonto, etiquetaBloqueSemanal, fechaHora, fmtFecha, iniciales, money, moneyK, montoDesdeTexto,
  montoEditable, numero, porcentajeConversionCanonica, porcentajeDesdeTexto,
  porcentajeEditable, primerNombre,
} from './format'

describe('formato monetario', () => {
  it('separa miles en todas las cantidades', () => {
    expect(numero(1_500_000)).toBe('1,500,000')
    expect(numero(12_345.67, 2)).toBe('12,345.67')
    expect(numero(null)).toBe('—')
  })

  it('presenta la conversión canónica con dos decimales sin inventar NULL', () => {
    expect(porcentajeConversionCanonica(137.63)).toBe('137.63%')
    expect(porcentajeConversionCanonica(9.3)).toBe('9.30%')
    expect(porcentajeConversionCanonica(null)).toBe('—')
    expect(porcentajeConversionCanonica(Number.NaN)).toBe('—')
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

// La meta de conversión se guarda en `numeric(5,2)`. La primera versión de este
// campo reutilizaba el parser de importes, que borra el punto: «1.5» se
// convertía en «15» y «12.5» en «100» por un clamp que además dejaba muerta la
// validación. Un error de un orden de magnitud, plausible y sin señal.
describe('porcentajes que se escriben', () => {
  it('conserva el decimal en vez de multiplicar por diez', () => {
    expect(porcentajeEditable('1.5')).toBe('1.5')
    expect(porcentajeEditable('12.5')).toBe('12.5')
    expect(porcentajeDesdeTexto('1.5')).toBe(1.5)
    expect(porcentajeDesdeTexto('12,5')).toBe(12.5)
  })

  it('deja escribir el punto sin comérselo a mitad de tecleo', () => {
    expect(porcentajeEditable('12')).toBe('12')
    expect(porcentajeEditable('12.')).toBe('12.')
    expect(porcentajeDesdeTexto('12.')).toBe(12)
    expect(porcentajeEditable('.5')).toBe('0.5')
  })

  it('NO recorta a 100: quien avisa es la validación, no un clamp mudo', () => {
    expect(porcentajeEditable('305')).toBe('305')
    expect(porcentajeDesdeTexto('305')).toBe(305)
  })

  it('corta en dos decimales, que es lo que la base guarda', () => {
    expect(porcentajeEditable('12.3456')).toBe('12.34')
  })

  it('ignora un segundo separador y la basura alfabética', () => {
    expect(porcentajeEditable('12.3.4')).toBe('12.34')
    expect(porcentajeEditable('abc')).toBe('')
    expect(porcentajeEditable('')).toBe('')
    expect(porcentajeDesdeTexto('')).toBe(0)
  })

  it('come los ceros a la izquierda sin tocar el «0,algo»', () => {
    expect(porcentajeEditable('007')).toBe('7')
    expect(porcentajeEditable('0.5')).toBe('0.5')
  })
})

describe('etiquetaBloqueSemanal', () => {
  it('una semana completa se rotula con sus dos fechas', () => {
    expect(etiquetaBloqueSemanal('2026-09-01', '2026-09-07')).toMatch(/^01 set\.? – 07 set\.?$/)
  })
  it('el bloque más corto que una semana declara sus días', () => {
    expect(etiquetaBloqueSemanal('2026-09-22', '2026-09-24')).toMatch(/^22 set\.? – 24 set\.? \(3 días\)$/)
    expect(etiquetaBloqueSemanal('2026-09-29', '2026-10-02')).toMatch(/\(4 días\)$/)
    expect(etiquetaBloqueSemanal('2026-09-24', '2026-09-24')).toMatch(/\(1 día\)$/)
  })
})

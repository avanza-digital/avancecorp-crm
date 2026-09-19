// Contrato del exportador CSV: BOM, CRLF, comillas escapadas y, sobre todo,
// que un valor que empieza por = + @ - o espacio NUNCA llegue a Excel como
// fórmula (el detalle de una llamada es texto libre escrito por analistas).
import { afterEach, describe, expect, it, vi } from 'vitest'
import { celdaCsv, csvDe, descargarCsv } from './exportar-csv'

describe('celdaCsv — una celda segura', () => {
  it.each([
    ['texto simple', '"texto simple"'],
    ['dice "hola"', '"dice ""hola"""'],
    ['=SUMA(A1:A9)', '"\'=SUMA(A1:A9)"'],
    ['+51 987 654 321', '"\'+51 987 654 321"'],
    ['@usuario', '"\'@usuario"'],
    ['-5', '"\'-5"'],
    [' con espacio inicial', '"\' con espacio inicial"'],
    [12.5, '"12.5"'],
    [true, '"true"'],
  ])('%p → %s', (entrada, esperado) => {
    expect(celdaCsv(entrada)).toBe(esperado)
  })

  it.each([null, undefined])('%p se exporta como celda vacía', (v) => {
    expect(celdaCsv(v)).toBe('""')
  })
})

describe('csvDe — el archivo completo', () => {
  it('empieza por BOM, separa filas con CRLF y celdas con coma', () => {
    const csv = csvDe(['Hora', 'Detalle'], [['12:59', 'Contestó'], ['12:47', null]])
    expect(csv.startsWith('﻿')).toBe(true)
    expect(csv).toBe('﻿"Hora","Detalle"\r\n"12:59","Contestó"\r\n"12:47",""')
  })

  it('sin filas, solo cabecera', () => {
    expect(csvDe(['A'], [])).toBe('﻿"A"')
  })
})

describe('descargarCsv — la descarga en el navegador', () => {
  afterEach(() => {
    vi.restoreAllMocks()
    vi.useRealTimers()
  })

  it('crea un enlace con el nombre .csv, hace clic, lo retira y revoca la URL un segundo después', () => {
    vi.useFakeTimers()
    const createObjectURL = vi.fn(() => 'blob:csv')
    const revokeObjectURL = vi.fn()
    vi.stubGlobal('URL', { ...URL, createObjectURL, revokeObjectURL })
    const clic = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {})

    expect(descargarCsv('registro-2026-09-19', 'contenido')).toBe(true)
    expect(createObjectURL).toHaveBeenCalledTimes(1)
    expect(clic).toHaveBeenCalledTimes(1)
    const enlace = clic.mock.instances[0] as HTMLAnchorElement
    expect(enlace.download).toBe('registro-2026-09-19.csv')
    expect(enlace.href).toContain('blob:csv')
    expect(document.body.contains(enlace)).toBe(false)
    expect(revokeObjectURL).not.toHaveBeenCalled()
    vi.advanceTimersByTime(1000)
    expect(revokeObjectURL).toHaveBeenCalledWith('blob:csv')
  })

  it('si el clic revienta devuelve false y aun así limpia', () => {
    vi.useFakeTimers()
    const revokeObjectURL = vi.fn()
    vi.stubGlobal('URL', { ...URL, createObjectURL: () => 'blob:x', revokeObjectURL })
    vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => { throw new Error('bloqueado') })
    expect(descargarCsv('x.csv', 'c')).toBe(false)
    expect(document.querySelector('a[download]')).toBeNull()
    vi.advanceTimersByTime(1000)
    expect(revokeObjectURL).toHaveBeenCalledWith('blob:x')
  })
})

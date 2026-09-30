// La pestaña «Conversiones» de Repartir: pinta lo que sirve la puerta del
// núcleo (Astrid 65 + 50 = 115, 11.15, 9,70 %), pide el primer día del mes
// elegido, degrada con reintento cuando la RPC falla, en un mes sellado enseña
// la foto sin desglose por origen y, para el lector de pantalla, cada «—» dice
// su motivo y el estado se anuncia desde una región siempre montada. Sin red.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { ConversionCoordinacion as Datos } from '@/lib/conversion-coordinacion'
import { payloadValido } from '@/lib/conversion-coordinacion.test'

const conversionMock = vi.fn<(periodo: string) => Promise<Datos>>()
vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return {
    ...actual,
    conversionCoordinacion: (periodo: string) => conversionMock(periodo),
  }
})

import { ConversionCoordinacion } from './conversion-coordinacion'

const mesActual = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Lima', year: 'numeric', month: '2-digit',
}).format(new Date()).slice(0, 7)

function conPeriodo(datos: Datos, periodo: string): Datos {
  return { ...datos, periodo: { ...datos.periodo, mes: periodo.slice(0, 7), desde: periodo } }
}

/** Lo que OYE el lector: el «—» va oculto y su motivo, en sr-only. */
const textoHablado = (celda: HTMLElement) => (
  Array.from(celda.querySelectorAll('[aria-hidden="true"]')).reduce(
    (texto, mudo) => texto.replace(mudo.textContent ?? '', ''),
    celda.textContent ?? '',
  )
)

beforeEach(() => {
  conversionMock.mockReset()
  conversionMock.mockImplementation(async (periodo) => conPeriodo(payloadValido(), periodo))
})
afterEach(() => vi.clearAllMocks())

describe('ConversionCoordinacion', () => {
  it('pide el mes vigente en Lima y pinta el divisor del núcleo por analista y por origen', async () => {
    render(<ConversionCoordinacion />)

    expect(await screen.findByRole('heading', { name: 'Conversiones' })).toBeInTheDocument()
    expect(conversionMock).toHaveBeenCalledWith(`${mesActual}-01`)

    const tabla = await screen.findByRole('table', { name: 'Conversión por analista' })
    const astrid = within(tabla).getByRole('row', { name: /ASTRID CENTENARO/ })
    expect(within(astrid).getAllByRole('cell').map((celda) => celda.textContent))
      .toEqual(['ASTRID CENTENARO', 'SUPERVISORA', '65', '50', '115', '11.15', '9.70%'])

    const merlys = within(tabla).getByRole('row', { name: /MERLYS GARCIA/ })
    expect(within(merlys).getAllByRole('cell').map((celda) => celda.textContent))
      .toEqual(['MERLYS GARCIA', 'SUPERVISORA', '60', '28', '88', '9', '10.23%'])

    // La fila sin analista: se ve «—» pero se oye «no aplica».
    const sinAnalista = within(tabla).getByRole('row', { name: /Sin analista asignado/ })
    const celdas = within(sinAnalista).getAllByRole('cell')
    expect(celdas.map(textoHablado))
      .toEqual(['Sin analista asignado', 'no aplica', 'no aplica', 'no aplica', '2', '0', 'no aplica'])
    expect(celdas[1]?.querySelector('[aria-hidden="true"]')?.textContent).toBe('—')

    const resumen = screen.getByRole('group', { name: 'Resumen de conversión del mes' })
    const cifra = (etiqueta: string) => within(resumen).getByText(etiqueta).nextElementSibling?.textContent
    expect(cifra('Llegadas')).toBe('205')
    expect(cifra('Formulario')).toBe('126')
    expect(cifra('Landing')).toBe('79')
    expect(cifra('Cierres ponderados')).toBe('20.15')
    expect(cifra('Conversión')).toBe('9.83%')

    expect(screen.getByRole('status')).toHaveTextContent('Conversión de setiembre 2026: 205 llegadas, 9.83%.')
    expect(screen.getByText(/Este conteo es distinto del reporte de entregas/)).toBeInTheDocument()
    expect(screen.queryByText(/Mes cerrado/)).not.toBeInTheDocument()
  })

  it('al cambiar el mes vuelve a pedir el primer día de ese mes y anuncia la carga y el resultado', async () => {
    const usuario = userEvent.setup()
    render(<ConversionCoordinacion />)
    await screen.findByRole('table', { name: 'Conversión por analista' })

    const mes = screen.getByLabelText('Mes de conversión')
    await usuario.clear(mes)
    await usuario.type(mes, '2026-08')

    await waitFor(() => expect(conversionMock).toHaveBeenLastCalledWith('2026-08-01'))
    expect(screen.getByRole('status')).not.toHaveTextContent('2026-08')
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent(/^Conversión de setiembre 2026/))
    expect(mes).not.toHaveAttribute('aria-invalid')
  })

  it('un mes vaciado es un error del formulario, no un fallo de red', async () => {
    const usuario = userEvent.setup()
    render(<ConversionCoordinacion />)
    await screen.findByRole('table', { name: 'Conversión por analista' })
    const llamadas = conversionMock.mock.calls.length

    const mes = screen.getByLabelText('Mes de conversión')
    await usuario.clear(mes)

    expect(mes).toHaveAttribute('aria-invalid', 'true')
    expect(mes).toHaveAccessibleDescription('Elige un mes válido (año y mes) para consultar la conversión.')
    expect(screen.getByRole('status')).toHaveTextContent('Elige un mes válido (año y mes) para consultar la conversión.')
    expect(screen.queryByText(/Revisa tu conexión/)).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Reintentar/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
    expect(conversionMock).toHaveBeenCalledTimes(llamadas)
  })

  it('en un mes sellado enseña la foto y el lector oye por qué no hay desglose por origen', async () => {
    conversionMock.mockImplementation(async (periodo) => {
      const datos = conPeriodo(payloadValido(), periodo)
      return {
        ...datos,
        sellado: true,
        empresa: { ...datos.empresa, divisor_formulario: null, divisor_landing: null },
        analistas: datos.analistas.map((a) => ({ ...a, divisor_formulario: null, divisor_landing: null })),
      }
    })
    render(<ConversionCoordinacion />)

    // El chip visible y, aparte, el anuncio del estado: el texto está dos veces a propósito.
    expect(await screen.findByText(/Mes cerrado: se muestra la foto del cierre/, { selector: 'span' })).toBeInTheDocument()
    const tabla = screen.getByRole('table', { name: 'Conversión por analista' })
    const astrid = within(tabla).getByRole('row', { name: /ASTRID CENTENARO/ })
    expect(within(astrid).getAllByRole('cell').map(textoHablado))
      .toEqual(['ASTRID CENTENARO', 'SUPERVISORA', 'sin desglose: mes cerrado', 'sin desglose: mes cerrado', '115', '11.15', '9.70%'])
    const resumen = screen.getByRole('group', { name: 'Resumen de conversión del mes' })
    expect(textoHablado(within(resumen).getByText('Formulario').nextElementSibling as HTMLElement)).toBe('sin desglose: mes cerrado')
    expect(screen.getByRole('status')).toHaveTextContent(/Mes cerrado: se muestra la foto del cierre/)
  })

  it('sin llegadas muestra el vacío honesto y un divisor 0 no rompe nada', async () => {
    conversionMock.mockImplementation(async (periodo) => ({
      ...conPeriodo(payloadValido(), periodo),
      empresa: { divisor: 0, numerador: 0, conversion_pct: null, divisor_formulario: 0, divisor_landing: 0 },
      sin_analista: null,
      analistas: [],
    }))
    render(<ConversionCoordinacion />)

    expect(await screen.findByText('Sin llegadas en este mes')).toBeInTheDocument()
    const resumen = screen.getByRole('group', { name: 'Resumen de conversión del mes' })
    expect(textoHablado(within(resumen).getByText('Conversión').nextElementSibling as HTMLElement)).toBe('sin llegadas')
    expect(screen.getByRole('status')).toHaveTextContent('0 llegadas, sin conversión calculable')
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
  })

  it('si la puerta falla, degrada con el mensaje real, reintenta y aterriza el foco en el contenido', async () => {
    const usuario = userEvent.setup()
    conversionMock.mockRejectedValueOnce(new Error('No tienes permiso para consultar la conversión por analista.'))
    render(<ConversionCoordinacion />)

    expect(await screen.findByText('No tienes permiso para consultar la conversión por analista.', { selector: 'p:not([role="status"])' })).toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent('No tienes permiso para consultar la conversión por analista.')
    expect(screen.queryByRole('table')).not.toBeInTheDocument()

    await usuario.click(screen.getByRole('button', { name: /Reintentar/ }))
    const tabla = await screen.findByRole('table', { name: 'Conversión por analista' })
    expect(conversionMock).toHaveBeenCalledTimes(2)
    await waitFor(() => expect(document.activeElement).not.toBe(document.body))
    expect(document.activeElement?.contains(tabla)).toBe(true)
  })

  it('un mes futuro tecleado a mano es un error del formulario y no llama a la puerta', async () => {
    const usuario = userEvent.setup()
    render(<ConversionCoordinacion />)
    await screen.findByRole('table', { name: 'Conversión por analista' })
    const llamadas = conversionMock.mock.calls.length

    const mes = screen.getByLabelText('Mes de conversión')
    await usuario.clear(mes)
    await usuario.type(mes, '2999-01')

    expect(mes).toHaveAttribute('aria-invalid', 'true')
    expect(mes).toHaveAccessibleDescription(`El mes no puede ser futuro: elige ${mesActual} o anterior.`)
    expect(screen.queryByRole('button', { name: /Reintentar/ })).not.toBeInTheDocument()
    expect(conversionMock).toHaveBeenCalledTimes(llamadas)
  })

  it('un mes cerrado con producción solo fuera del ranking no dice «sin llegadas»', async () => {
    conversionMock.mockImplementation(async (periodo) => ({
      ...conPeriodo(payloadValido(), periodo),
      sellado: true,
      empresa: { divisor: 5, numerador: 1, conversion_pct: 20, divisor_formulario: null, divisor_landing: null },
      sin_analista: null,
      analistas: [],
    }))
    render(<ConversionCoordinacion />)

    expect(await screen.findByText('Sin filas por analista en este mes cerrado')).toBeInTheDocument()
    expect(screen.queryByText('Sin llegadas en este mes')).not.toBeInTheDocument()
    const resumen = screen.getByRole('group', { name: 'Resumen de conversión del mes' })
    expect(within(resumen).getByText('Llegadas').nextElementSibling?.textContent).toBe('5')
  })

  it('cambiar de mes tras un fallo no arrastra el error viejo ni roba el foco al campo', async () => {
    const usuario = userEvent.setup()
    conversionMock.mockRejectedValueOnce(new Error('Caída'))
    render(<ConversionCoordinacion />)
    expect(await screen.findByRole('button', { name: /Reintentar/ })).toBeInTheDocument()

    const mes = screen.getByLabelText('Mes de conversión')
    await usuario.clear(mes)
    await usuario.type(mes, '2026-08')

    await screen.findByRole('table', { name: 'Conversión por analista' })
    expect(screen.queryByText('Caída')).not.toBeInTheDocument()
    expect(mes).toHaveFocus()
  })
})

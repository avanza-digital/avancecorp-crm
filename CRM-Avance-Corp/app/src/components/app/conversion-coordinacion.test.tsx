// La pestaña «Conversiones» de Repartir: pinta lo que sirve la puerta del
// núcleo (Astrid 65 + 50 = 115, 11.15, 9,70 %), pide el primer día del mes
// elegido, degrada con reintento cuando la RPC falla, en un mes sellado enseña
// la foto sin desglose por origen y, para el lector de pantalla, cada «—» dice
// su motivo y el estado se anuncia desde una región siempre montada. Sin red.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { ConsultaConversion, ConversionCoordinacion as Datos } from '@/lib/conversion-coordinacion'
import { fechasDeConsulta } from '@/lib/conversion-coordinacion'
import { payloadSellado, payloadValido } from '@/lib/conversion-coordinacion.test'

const conversionMock = vi.fn<(consulta: ConsultaConversion) => Promise<Datos>>()
vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return {
    ...actual,
    conversionCoordinacion: (consulta: ConsultaConversion) => conversionMock(consulta),
  }
})

import { ConversionCoordinacion } from './conversion-coordinacion'

const mesActual = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Lima', year: 'numeric', month: '2-digit',
}).format(new Date()).slice(0, 7)

/** Eco del período como lo hace la puerta: mes exacto con nombre, o rango sin nombre. */
function conPeriodo(datos: Datos, consulta: ConsultaConversion): Datos {
  const fechas = fechasDeConsulta(consulta)!
  const dias = Math.round((Date.parse(`${fechas.hasta}T12:00:00Z`) - Date.parse(`${fechas.desde}T12:00:00Z`)) / 86_400_000) + 1
  return consulta.modo === 'mes'
    ? { ...datos, periodo: { ...datos.periodo, modo: 'mes', mes: consulta.mes, desde: fechas.desde, hasta: fechas.hasta, dias } }
    : { ...datos, sellado: false, fuente: { ...datos.fuente, modo: 'rango_vivo' }, periodo: { modo: 'rango', mes: null, mes_nombre: null, anio: null, zona: 'America/Lima', desde: fechas.desde, hasta: fechas.hasta, dias, cruza_meses_sellados: false } }
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
  conversionMock.mockImplementation(async (consulta) => conPeriodo(payloadValido(), consulta))
})
afterEach(() => vi.clearAllMocks())

describe('ConversionCoordinacion', () => {
  it('pide el mes vigente en Lima y pinta el divisor del núcleo por analista y por origen', async () => {
    render(<ConversionCoordinacion />)

    expect(await screen.findByRole('heading', { name: 'Conversiones' })).toBeInTheDocument()
    expect(conversionMock).toHaveBeenCalledWith({ modo: 'mes', mes: mesActual })

    const tabla = await screen.findByRole('table', { name: 'Conversión por analista' })
    const astrid = within(tabla).getByRole('row', { name: /ASTRID CENTENARO/ })
    // Analista · Supervisor · Llegadas (F, L, total) · Cierres (F, L, referido «n · aporte», sin peso (oficina + otros), upgrade, renovación «n · aporte», ponderados) · %
    expect(within(astrid).getAllByRole('cell').map(textoHablado))
      .toEqual(['ASTRID CENTENARO', 'SUPERVISORA', '65', '50', '115', '5', '2', '1 referido, aporta 0.15', '1', '4', '0 renovaciones, aportan 0', '11.15', '9.70%'])
    expect(within(astrid).getAllByRole('cell')[7]?.querySelector('[aria-hidden="true"]')?.textContent).toBe('1 · 0.15')

    const merlys = within(tabla).getByRole('row', { name: /MERLYS GARCIA/ })
    expect(within(merlys).getAllByRole('cell').map(textoHablado))
      .toEqual(['MERLYS GARCIA', 'SUPERVISORA', '60', '28', '88', '6', '1', '0 referidos, aportan 0', '0', '2', '0 renovaciones, aportan 0', '9', '10.23%'])

    // La fila sin analista: se ve «—» pero se oye «no aplica».
    const sinAnalista = within(tabla).getByRole('row', { name: /Sin analista asignado/ })
    const celdas = within(sinAnalista).getAllByRole('cell')
    expect(celdas.map(textoHablado))
      .toEqual(['Sin analista asignado', 'no aplica', 'no aplica', 'no aplica', '2', 'no aplica', 'no aplica', 'no aplica', 'no aplica', 'no aplica', 'no aplica', '0', 'no aplica'])
    expect(celdas[1]?.querySelector('[aria-hidden="true"]')?.textContent).toBe('—')

    // Cabecera agrupada: Llegadas y Cierres con sus columnas.
    expect(within(tabla).getByRole('columnheader', { name: 'Cierres' })).toHaveAttribute('colspan', '7')
    // El período de lo que se ve, a la vista y sin aviso de desfase cuando los controles coinciden.
    expect(screen.getByTestId('periodo-visible')).toHaveTextContent(/^Conversión de setiembre 2026$/)
    expect(within(tabla).getByRole('columnheader', { name: 'Upgrade' })).toBeInTheDocument()

    const resumen = screen.getByRole('group', { name: 'Resumen de conversión del mes' })
    const cifra = (etiqueta: string) => within(resumen).getByText(etiqueta).nextElementSibling?.textContent
    expect(cifra('Llegadas')).toBe('205')
    expect(cifra('Formulario')).toBe('126')
    expect(cifra('Landing')).toBe('79')
    expect(cifra('Conversión')).toBe('9.83%')
    expect(cifra('Cierres directos')).toBe('14')
    expect(textoHablado(within(resumen).getByText('Referidos').nextElementSibling as HTMLElement)).toBe('1 referido, aporta 0.15')
    expect(cifra('Upgrade')).toBe('6')
    expect(textoHablado(within(resumen).getByText('Renovación').nextElementSibling as HTMLElement)).toBe('0 renovaciones, aportan 0')
    expect(screen.getByTestId('formula-numerador')).toHaveTextContent(
      'Cierres ponderados 20.15 = 14 directos (formulario y landing) + 0.15 de referidos (1 × 0.15) + 6 de upgrade + 0 de renovación (0 × 0.15). Sin peso: 1 de oficina y 0 de otros orígenes.',
    )

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

    await waitFor(() => expect(conversionMock).toHaveBeenLastCalledWith({ modo: 'mes', mes: '2026-08' }))
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
    // El error del formulario no borra lo último cargado: la tabla sigue mientras se corrige el
    // campo, y dice A LA VISTA de qué período es y que los controles ya no coinciden.
    expect(screen.getByRole('table', { name: 'Conversión por analista' })).toBeInTheDocument()
    expect(screen.getByTestId('periodo-visible')).toHaveTextContent(/^Conversión de setiembre 2026 · última consulta válida; corrige el período para actualizar$/)
    expect(conversionMock.mock.calls.length).toBe(llamadas)
    // Un mes anterior al mínimo tampoco consulta ni deja el campo sin marcar.
    await usuario.type(mes, '2024-12')
    expect(mes).toHaveAttribute('aria-invalid', 'true')
    expect(screen.getByRole('status')).toHaveTextContent('El mes más antiguo consultable es 2025-01.')
    expect(conversionMock.mock.calls.length).toBe(llamadas)
    expect(conversionMock).toHaveBeenCalledTimes(llamadas)
  })

  it('en un mes sellado enseña la foto y el lector oye por qué no hay desglose por origen', async () => {
    conversionMock.mockImplementation(async (consulta) => conPeriodo(payloadSellado(true), consulta))
    render(<ConversionCoordinacion />)

    // El chip visible y, aparte, el anuncio del estado: el texto está dos veces a propósito.
    expect(await screen.findByText(/Mes cerrado: se muestra la foto del cierre/, { selector: 'span' })).toBeInTheDocument()
    const tabla = screen.getByRole('table', { name: 'Conversión por analista' })
    const astrid = within(tabla).getByRole('row', { name: /ASTRID CENTENARO/ })
    expect(within(astrid).getAllByRole('cell').map(textoHablado))
      .toEqual(['ASTRID CENTENARO', 'SUPERVISORA', 'sin desglose: mes cerrado', 'sin desglose: mes cerrado', '115', '5', '2', '1 referido, aporta 0.15', '1', '4', '0 renovaciones, aportan 0', '11.15', '9.70%'])
    const resumen = screen.getByRole('group', { name: 'Resumen de conversión del mes' })
    expect(textoHablado(within(resumen).getByText('Formulario').nextElementSibling as HTMLElement)).toBe('sin desglose: mes cerrado')
    expect(screen.getByRole('status')).toHaveTextContent(/Mes cerrado: se muestra la foto del cierre/)
  })

  it('sin llegadas muestra el vacío honesto y un divisor 0 no rompe nada', async () => {
    conversionMock.mockImplementation(async (consulta) => ({
      ...conPeriodo(payloadValido(), consulta),
      empresa: {
        divisor: 0, numerador: 0, conversion_pct: null, divisor_formulario: 0, divisor_landing: 0,
        numerador_bruto: 0, ajuste_pendiente: 0, desglose_disponible: true,
        cierres: { formulario: 0, landing: 0, referido: 0, referido_aporte: 0, oficina: 0, otros: 0 },
        cartera: { upgrade: 0, renovacion: 0, renovacion_aporte: 0 },
      },
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
    conversionMock.mockImplementation(async (consulta) => ({
      ...conPeriodo(payloadSellado(false), consulta),
      empresa: {
        divisor: 5, numerador: 1, conversion_pct: 20, divisor_formulario: null, divisor_landing: null,
        numerador_bruto: null, ajuste_pendiente: null, desglose_disponible: false, cierres: null, cartera: null,
      },
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

  it('en un mes cerrado sin desglose en la foto, cada celda de cierres dice por qué', async () => {
    conversionMock.mockImplementation(async (consulta) => conPeriodo(payloadSellado(false), consulta))
    render(<ConversionCoordinacion />)

    const tabla = await screen.findByRole('table', { name: 'Conversión por analista' })
    const astrid = within(tabla).getByRole('row', { name: /ASTRID CENTENARO/ })
    const celdas = within(astrid).getAllByRole('cell').map(textoHablado)
    expect(celdas.slice(5, 11)).toEqual(Array(6).fill('sin desglose: mes cerrado'))
    expect(celdas[11]).toBe('11.15')
    expect(screen.queryByTestId('formula-numerador')).not.toBeInTheDocument()
  })

  it('cuando hay ajuste de meses pagados, la celda de ponderados lo explica', async () => {
    conversionMock.mockImplementation(async (consulta) => {
      const datos = conPeriodo(payloadValido(), consulta)
      datos.analistas[1] = { ...datos.analistas[1]!, ajuste_pendiente: 1, numerador: 8 }
      datos.empresa = { ...datos.empresa, ajuste_pendiente: 1, numerador: 19.15 }
      return datos
    })
    render(<ConversionCoordinacion />)

    const tabla = await screen.findByRole('table', { name: 'Conversión por analista' })
    const merlys = within(tabla).getByRole('row', { name: /MERLYS GARCIA/ })
    expect(within(merlys).getAllByRole('cell')[11]).toHaveTextContent('8bruto 9 − ajuste 1')
    // La empresa no es «bruto − ajuste»: el suelo en cero va por analista, así que no se afirma esa igualdad.
    expect(screen.getByTestId('formula-numerador')).toHaveTextContent('Ajuste de meses ya pagados: 1, descontado por analista con suelo en cero. Netos: 19.15.')
    expect(screen.getByTestId('formula-numerador')).not.toHaveTextContent('= 19.15')
  })

  it('en modo rango pide las dos fechas inclusivas y anuncia el rango en vivo', async () => {
    const usuario = userEvent.setup()
    render(<ConversionCoordinacion />)
    await screen.findByRole('table', { name: 'Conversión por analista' })

    await usuario.selectOptions(screen.getByLabelText('Tipo de período'), 'rango')
    expect(screen.getByText(/Rango libre: cifras en vivo/, { selector: 'p:not([role="status"])' })).toBeInTheDocument()
    const desde = screen.getByLabelText('Desde')
    const hasta = screen.getByLabelText('Hasta')
    await usuario.clear(desde)
    await usuario.type(desde, '2026-09-01')
    await usuario.clear(hasta)
    await usuario.type(hasta, '2026-09-15')

    await waitFor(() => expect(conversionMock).toHaveBeenLastCalledWith({ modo: 'rango', desde: '2026-09-01', hasta: '2026-09-15' }))
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent(/^Conversión\s+del 1 de setiembre de 2026 al 15 de setiembre de 2026:/))
    expect(screen.getByRole('status')).toHaveTextContent('Rango libre: cifras en vivo')
    expect(screen.queryByText(/Mes cerrado/)).not.toBeInTheDocument()
    // En rango los pesos van por mes de cada episodio: la fórmula no promete «n × peso»,
    // y los textos hablan «del período», no «del mes».
    expect(screen.getByTestId('formula-numerador')).toHaveTextContent('0.15 de referidos (1) + 6 de upgrade + 0 de renovación (0)')
    expect(screen.getByTestId('formula-numerador')).not.toHaveTextContent('×')
    expect(screen.getByRole('region', { name: 'Conversión del período' })).toBeInTheDocument()
    expect(screen.getByRole('group', { name: 'Resumen de conversión del período' })).toBeInTheDocument()
  })

  it('un rango que toca meses ya cerrados lo avisa en pantalla y en el estado vivo', async () => {
    const usuario = userEvent.setup()
    conversionMock.mockImplementation(async (consulta) => {
      const datos = conPeriodo(payloadValido(), consulta)
      if (consulta.modo === 'rango') datos.periodo = { ...datos.periodo, cruza_meses_sellados: true }
      return datos
    })
    render(<ConversionCoordinacion />)
    await screen.findByRole('table', { name: 'Conversión por analista' })
    await usuario.selectOptions(screen.getByLabelText('Tipo de período'), 'rango')

    expect(await screen.findByText(/Este rango toca meses ya cerrados/)).toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent('Toca meses ya cerrados y puede diferir de su foto')
  })

  it('teclear fechas no consulta por cada dígito: espera a que el usuario pare y marca solo el campo que está mal', async () => {
    const usuario = userEvent.setup()
    render(<ConversionCoordinacion />)
    await screen.findByRole('table', { name: 'Conversión por analista' })
    await usuario.selectOptions(screen.getByLabelText('Tipo de período'), 'rango')
    await waitFor(() => expect(conversionMock).toHaveBeenLastCalledWith(expect.objectContaining({ modo: 'rango' })))
    const llamadas = conversionMock.mock.calls.length

    const desde = screen.getByLabelText('Desde')
    const hasta = screen.getByLabelText<HTMLInputElement>('Hasta')
    await usuario.clear(desde)
    // Un campo vacío es un error del formulario solo en ESE campo, y no borra la tabla ya cargada.
    expect(desde).toHaveAttribute('aria-invalid', 'true')
    expect(hasta).not.toHaveAttribute('aria-invalid')
    expect(screen.getByRole('table', { name: 'Conversión por analista' })).toBeInTheDocument()
    await usuario.type(desde, '2026-09-03')
    await usuario.clear(desde)
    await usuario.type(desde, '2026-09-05')
    await waitFor(() => expect(conversionMock).toHaveBeenLastCalledWith({ modo: 'rango', desde: '2026-09-05', hasta: hasta.value }))
    // Dos fechas completas tecleadas seguidas → una sola consulta (la última), no una por cada valor intermedio.
    expect(conversionMock.mock.calls.length - llamadas).toBe(1)
  })

  it('un rango con la fecha inicial después de la final es un error del formulario, sin llamar a la puerta', async () => {
    const usuario = userEvent.setup()
    render(<ConversionCoordinacion />)
    await screen.findByRole('table', { name: 'Conversión por analista' })
    await usuario.selectOptions(screen.getByLabelText('Tipo de período'), 'rango')
    await waitFor(() => expect(conversionMock).toHaveBeenLastCalledWith(expect.objectContaining({ modo: 'rango' })))
    const llamadas = conversionMock.mock.calls.length

    const desde = screen.getByLabelText('Desde')
    await usuario.clear(desde)
    await usuario.type(desde, '2026-09-20')
    const hasta = screen.getByLabelText('Hasta')
    await usuario.clear(hasta)
    await usuario.type(hasta, '2026-09-10')

    expect(hasta).toHaveAttribute('aria-invalid', 'true')
    expect(hasta).toHaveAccessibleDescription('La fecha inicial no puede ser posterior a la final.')
    expect(screen.getByRole('status')).toHaveTextContent('La fecha inicial no puede ser posterior a la final.')
    expect(screen.queryByRole('button', { name: /Reintentar/ })).not.toBeInTheDocument()
    // Hubo llamadas mientras se tecleaban fechas válidas intermedias; ninguna con el rango cruzado.
    expect(conversionMock.mock.calls.slice(llamadas).every(([c]) => c.modo !== 'rango' || c.desde <= c.hasta)).toBe(true)
  })
})

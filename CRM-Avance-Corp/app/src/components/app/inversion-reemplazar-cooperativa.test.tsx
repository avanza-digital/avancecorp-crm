import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { InversionReemplazarCooperativa, type ControlesReemplazoCooperativa } from './inversion-reemplazar-cooperativa'
import { CrmApiError, type InversionCooperativaReemplazadaResultado } from '@/data/crm-api'
import { fechaLima } from '@/lib/agenda-derivada'
import { fichaF5, inversionProdelcoF5, PERSONA_F5 } from '@/test/fixtures/f5'
import type { FichaInversionista, InversionFuente, VistaPreviaReemplazoCooperativa } from '@/lib/inversionistas'

// El diálogo de la Fase 4 contra controles simulados: qué precarga, qué bloquea, qué cambia y qué manda (solo lo que
// cambia, con el comprobante subido ANTES de la puerta). El cliente real de la API tiene su propia batería
// (crm-api-reemplazar-cooperativa-msw.test.ts).
const ORIGINAL = inversionProdelcoF5
const ficha: FichaInversionista = { ...fichaF5, inversiones: [ORIGINAL], inversiones_total: 1 }
const previa = (over: Partial<VistaPreviaReemplazoCooperativa> = {}): VistaPreviaReemplazoCooperativa => ({
  fuente_id: ORIGINAL.fuente_id, cooperativa: 'prodelco', es_inicial: true, anulada: false, venta_de_lead: true, comprobante: true,
  fecha_comercial_actual: '2026-10-05', mes_actual: '2026-10-01', fecha_comercial_resultante: '2026-10-05', mes_resultante: '2026-10-01',
  cambia_mes: false, fecha_futura: false, mes_sellado: false, plazo_vencido: false, no_reemplazable: null, ...over })
/** La previa según la fecha: el mes es el de la fecha y se «muda» si no es octubre. */
const previaDe = (fecha: string, over: Partial<VistaPreviaReemplazoCooperativa> = {}) => previa({ fecha_comercial_resultante: fecha,
  mes_resultante: `${fecha.slice(0, 7)}-01`, cambia_mes: !fecha.startsWith('2026-10'), ...over })
const RESULTADO: InversionCooperativaReemplazadaResultado = { cierreId: '66666666-6666-4666-8666-666666666666', cooperativa: 'qorilazo',
  fechaComercial: '2026-10-05', idempotente: false, periodoVenta: '2026-10-01' }
const RUTA = new RegExp(`^${PERSONA_F5}/reemplazo-${ORIGINAL.fuente_id}/[0-9a-f-]{36}\\.pdf$`)

function montar(over: Partial<ControlesReemplazoCooperativa> = {}, inversion: InversionFuente = ORIGINAL) {
  const controles: ControlesReemplazoCooperativa = {
    puede: () => true,
    vistaPrevia: vi.fn(async (_i: InversionFuente, fecha: string) => previaDe(fecha)),
    subirComprobante: vi.fn(async () => {}),
    reemplazar: vi.fn(async () => RESULTADO),
    alTerminar: vi.fn(),
    ...over,
  }
  const cerrar = vi.fn()
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  render(<QueryClientProvider client={qc}><InversionReemplazarCooperativa inversion={inversion} ficha={ficha} controles={controles} onCerrar={cerrar} /></QueryClientProvider>)
  const dialogo = screen.getByRole('dialog', { name: 'Reemplazar inversión en Prodelco PRODELCO SINTÉTICO' })
  const motivo = () => within(dialogo).getByLabelText('Motivo del reemplazo')
  const enviar = () => within(dialogo).getByRole('button', { name: 'Reemplazar inversión' })
  const region = () => within(dialogo).getByText('La venta queda en').closest('[role="status"]') as HTMLElement
  return { controles, cerrar, dialogo, motivo, enviar, region, user: userEvent.setup() }
}
const pdf = () => new File(['%PDF-1.4 comprobante sintético'], 'comprobante.pdf', { type: 'application/pdf' })
afterEach(() => { cleanup() })

describe('Reemplazar inversión de cooperativa · lo que se ve', () => {
  it('precarga la original (fija) y la correcta con sus mismos datos; el mes lo dice el servidor', async () => {
    const { dialogo, controles, region } = montar()
    const original = within(dialogo).getByRole('region', { name: 'La original' })
    expect(original).toHaveTextContent('ANA SINTÉTICA F5')
    expect(original).toHaveTextContent('ANALISTA DE LA VENTA')
    expect(original).toHaveTextContent('S/ 3,000')
    expect(original).toHaveTextContent('OP-SINTÉTICA-1')
    expect(original).toHaveTextContent('12 meses')
    const correcta = within(dialogo).getByRole('region', { name: 'La correcta' })
    expect(within(correcta).getByRole('radio', { name: /Prodelco/ })).toBeChecked()
    expect(within(correcta).getByRole('radio', { name: /Qorilazo/ })).not.toBeChecked()
    expect(within(correcta).getByLabelText('Fecha comercial')).toHaveValue('2026-10-05')
    expect(within(correcta).getByRole('radio', { name: /Conservar el de la original/ })).toBeChecked()
    // Solo tres controles: lo demás (monto, plazo, tasa, n° de operación) ni se edita aquí.
    expect(within(correcta).queryByRole('textbox')).toBeNull()
    expect(within(correcta).getByText(/se copian de la original/)).toBeVisible()
    await waitFor(() => expect(region()).toHaveTextContent('Octubre 2026'))
    expect(region()).toHaveTextContent('Igual que ahora')
    expect(controles.vistaPrevia).toHaveBeenCalledWith(ORIGINAL, '2026-10-05')
    expect(within(dialogo).getAllByRole('heading', { level: 2 })).toHaveLength(1)
  })

  it('sin cambios no se confirma aunque haya motivo, y la pista dice qué falta', async () => {
    const { motivo, enviar, region, user } = montar()
    await waitFor(() => expect(region()).toHaveTextContent('Octubre 2026'))
    await user.type(motivo(), 'Se cargó mal')
    expect(enviar()).toBeDisabled()
    expect(motivo()).toHaveAccessibleDescription(/no hay nada que reemplazar/)
  })

  it('una moneda que la otra cooperativa no admite no se ofrece, y se explica en el grupo', () => {
    const { dialogo } = montar({}, { ...ORIGINAL, moneda: 'USD' })
    const qorilazo = within(dialogo).getByRole('radio', { name: /Qorilazo/ })
    expect(qorilazo).toBeDisabled()
    expect(within(dialogo).getByRole('group', { name: 'Cooperativa' })).toHaveAccessibleDescription('Qorilazo no admite inversiones en dólares.')
  })

  it('al abrir, el foco cae en la cooperativa de la original (la marcada), no en la otra', async () => {
    const { dialogo } = montar()
    await waitFor(() => expect(within(dialogo).getByRole('radio', { name: /Prodelco/ })).toHaveFocus())
  })

  it('una original sin fecha comercial abre con el campo vacío, sin marcarlo como error: la pista dice qué falta', () => {
    const { dialogo, motivo, enviar, region } = montar({}, { ...ORIGINAL, fecha_comercial: null })
    const fecha = within(dialogo).getByLabelText('Fecha comercial')
    expect(fecha).toHaveValue('')
    expect(fecha).not.toHaveAttribute('aria-invalid')
    expect(region()).toHaveTextContent('Indica la fecha comercial.')
    expect(motivo()).toHaveAccessibleDescription(/Indica la fecha comercial de la venta\./)
    expect(enviar()).toBeDisabled()
  })

  it('las acciones van después del motivo (orden de foco y de lectura)', () => {
    const { motivo, enviar } = montar()
    expect(motivo().compareDocumentPosition(enviar()) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy()
    expect(motivo()).toHaveAttribute('aria-required', 'true')
  })
})

describe('Reemplazar inversión de cooperativa · confirmar', () => {
  it('cambiar la cooperativa: se lista, el motivo bloquea y viaja SOLO la cooperativa', async () => {
    const { dialogo, controles, cerrar, motivo, enviar, user } = montar()
    await user.click(within(dialogo).getByRole('radio', { name: /Qorilazo/ }))
    const cambios = within(dialogo).getByRole('list', { name: 'Cambios' })
    expect(cambios).toHaveTextContent('Cooperativa')
    expect(cambios).toHaveTextContent('antes Prodelco, ahora Qorilazo')
    expect(enviar()).toBeDisabled()
    await user.type(motivo(), 'Se registró en la cooperativa equivocada')
    await waitFor(() => expect(enviar()).toBeEnabled())
    await user.click(enviar())
    await waitFor(() => expect(controles.reemplazar).toHaveBeenCalledWith(ORIGINAL, 'Se registró en la cooperativa equivocada', { cooperativa: 'qorilazo' }))
    expect(controles.subirComprobante).not.toHaveBeenCalled()
    expect(controles.alTerminar).toHaveBeenCalledWith(ORIGINAL, RESULTADO)
    expect(cerrar).toHaveBeenCalled()
  })

  it('cambiar la fecha: el mes se recalcula, se anuncia la mudanza y viaja SOLO la fecha', async () => {
    const { dialogo, controles, motivo, enviar, region, user } = montar()
    await user.type(motivo(), 'La fecha comercial era de septiembre')
    fireEvent.change(within(dialogo).getByLabelText('Fecha comercial'), { target: { value: '2026-09-28' } })
    expect(enviar()).toBeDisabled()                                                        // en el respiro
    await waitFor(() => expect(region()).toHaveTextContent('Septiembre 2026'))
    expect(region()).toHaveTextContent('Se muda desde octubre 2026')
    expect(controles.vistaPrevia).toHaveBeenCalledWith(ORIGINAL, '2026-09-28')
    expect(within(dialogo).getByRole('list', { name: 'Cambios' })).toHaveTextContent('Fecha comercial')
    await waitFor(() => expect(enviar()).toBeEnabled())
    await user.click(enviar())
    await waitFor(() => expect(controles.reemplazar).toHaveBeenCalledWith(ORIGINAL, 'La fecha comercial era de septiembre', { fechaComercial: '2026-09-28' }))
  })

  it('con la fecha recién cambiada no se confirma hasta tener SU mes (la respuesta anterior no sirve)', async () => {
    let soltar: (v: VistaPreviaReemplazoCooperativa) => void = () => {}
    const vistaPrevia = vi.fn(async (_i: InversionFuente, fecha: string) =>
      fecha === '2026-09-28' ? new Promise<VistaPreviaReemplazoCooperativa>(r => { soltar = r }) : previaDe(fecha))
    const { dialogo, motivo, enviar, region, user } = montar({ vistaPrevia })
    await user.click(within(dialogo).getByRole('radio', { name: /Qorilazo/ }))
    await user.type(motivo(), 'Cooperativa y fecha equivocadas')
    await waitFor(() => expect(enviar()).toBeEnabled())
    fireEvent.change(within(dialogo).getByLabelText('Fecha comercial'), { target: { value: '2026-09-28' } })
    await waitFor(() => expect(vistaPrevia).toHaveBeenCalledWith(ORIGINAL, '2026-09-28'))
    expect(region()).toHaveTextContent('Octubre 2026')                                     // la anterior sigue a la vista…
    expect(region()).toHaveAttribute('aria-busy', 'true')
    expect(enviar()).toBeDisabled()                                                        // …pero no sirve para confirmar
    soltar(previaDe('2026-09-28'))
    await waitFor(() => expect(enviar()).toBeEnabled())
  })

  it('comprobante nuevo: se sube ANTES de la puerta, a la carpeta de la persona y del reemplazo, y viaja su ruta', async () => {
    const orden: string[] = []
    const subirComprobante = vi.fn(async () => { orden.push('subir') })
    const reemplazar = vi.fn(async () => { orden.push('puerta'); return RESULTADO })
    const { dialogo, motivo, enviar, user } = montar({ subirComprobante, reemplazar })
    await user.click(within(dialogo).getByRole('radio', { name: /Subir otro comprobante/ }))
    expect(enviar()).toBeDisabled()
    expect(motivo()).toHaveAccessibleDescription(/Elige el archivo del comprobante nuevo/)
    const archivo = pdf()
    await user.upload(within(dialogo).getByLabelText(/Comprobante nuevo/), archivo)
    expect(within(dialogo).getByText('Archivo elegido: comprobante.pdf')).toBeVisible()
    expect(within(dialogo).getByRole('list', { name: 'Cambios' })).toHaveTextContent(/Comprobante\s*Nuevo/)
    await user.type(motivo(), 'El comprobante era de otra operación')
    await waitFor(() => expect(enviar()).toBeEnabled())
    await user.click(enviar())
    await waitFor(() => expect(reemplazar).toHaveBeenCalled())
    expect(orden).toEqual(['subir', 'puerta'])
    const [ruta, enviado] = subirComprobante.mock.calls[0] as unknown as [string, File]
    expect(ruta).toMatch(RUTA)
    expect(enviado).toBe(archivo)
    expect(reemplazar).toHaveBeenCalledWith(ORIGINAL, 'El comprobante era de otra operación', { comprobanteRuta: ruta })
  })

  it('si la subida falla, se dice, NO se llama a la puerta y al reintentar se sube al mismo sitio', async () => {
    const subirComprobante = vi.fn<ControlesReemplazoCooperativa['subirComprobante']>()
      .mockRejectedValueOnce(new CrmApiError('No se pudo cargar el comprobante.', 'COMPROBANTE_PENDIENTE'))
      .mockResolvedValue(undefined)
    const { dialogo, controles, cerrar, motivo, enviar, user } = montar({ subirComprobante })
    await user.click(within(dialogo).getByRole('radio', { name: /Subir otro comprobante/ }))
    await user.upload(within(dialogo).getByLabelText(/Comprobante nuevo/), pdf())
    await user.type(motivo(), 'El comprobante era de otra operación')
    await waitFor(() => expect(enviar()).toBeEnabled())
    await user.click(enviar())
    expect(await within(dialogo).findByRole('alert')).toHaveTextContent('No se pudo subir el comprobante nuevo. No se hizo ningún cambio')
    expect(controles.reemplazar).not.toHaveBeenCalled()
    expect(cerrar).not.toHaveBeenCalled()
    await user.click(enviar())
    await waitFor(() => expect(controles.reemplazar).toHaveBeenCalled())
    expect(subirComprobante).toHaveBeenCalledTimes(2)
    expect(subirComprobante.mock.calls[1]![0]).toBe(subirComprobante.mock.calls[0]![0])
  })

  it('si la puerta rechaza tras subir, el reintento no vuelve a subir el mismo comprobante', async () => {
    const reemplazar = vi.fn<ControlesReemplazoCooperativa['reemplazar']>()
      .mockRejectedValueOnce(new CrmApiError('Otra operación está usando el mes 10/2026; vuelve a intentar en unos segundos', 'REINTENTAR'))
      .mockResolvedValue(RESULTADO)
    const { dialogo, controles, motivo, enviar, user } = montar({ reemplazar })
    await user.click(within(dialogo).getByRole('radio', { name: /Subir otro comprobante/ }))
    await user.upload(within(dialogo).getByLabelText(/Comprobante nuevo/), pdf())
    await user.type(motivo(), 'El comprobante era de otra operación')
    await waitFor(() => expect(enviar()).toBeEnabled())
    await user.click(enviar())
    expect(await within(dialogo).findByRole('alert')).toHaveTextContent('Otra operación está usando el mes 10/2026')
    await user.click(enviar())
    await waitFor(() => expect(controles.alTerminar).toHaveBeenCalled())
    expect(controles.subirComprobante).toHaveBeenCalledTimes(1)
    expect(reemplazar).toHaveBeenCalledTimes(2)
  })

  it('un archivo que no es PDF, JPG o PNG se rechaza al elegirlo y no deja confirmar', async () => {
    const { dialogo, motivo, enviar } = montar()
    const user = userEvent.setup({ applyAccept: false })
    await user.click(within(dialogo).getByRole('radio', { name: /Subir otro comprobante/ }))
    await user.upload(within(dialogo).getByLabelText(/Comprobante nuevo/), new File(['hola'], 'nota.txt', { type: 'text/plain' }))
    expect(within(dialogo).getByRole('alert')).toHaveTextContent('Usa un PDF, JPG o PNG de hasta 10 MB.')
    expect(within(dialogo).getByLabelText(/Comprobante nuevo/)).toHaveAttribute('aria-invalid', 'true')
    await user.type(motivo(), 'El comprobante era de otra operación')
    expect(enviar()).toBeDisabled()
    expect(within(dialogo).queryByRole('list', { name: 'Cambios' })).toBeNull()
  })

  it('volver a «conservar» olvida el archivo elegido', async () => {
    const { dialogo, user } = montar()
    await user.click(within(dialogo).getByRole('radio', { name: /Subir otro comprobante/ }))
    await user.upload(within(dialogo).getByLabelText(/Comprobante nuevo/), pdf())
    await user.click(within(dialogo).getByRole('radio', { name: /Conservar el de la original/ }))
    expect(within(dialogo).queryByRole('list', { name: 'Cambios' })).toBeNull()
    await user.click(within(dialogo).getByRole('radio', { name: /Subir otro comprobante/ }))
    expect(within(dialogo).queryByText(/Archivo elegido/)).toBeNull()
  })

  it('el reintento ya hecho (idempotente) termina igual', async () => {
    const idem = { ...RESULTADO, idempotente: true, periodoVenta: null }
    const { dialogo, controles, cerrar, motivo, enviar, user } = montar({ reemplazar: vi.fn(async () => idem) })
    await user.click(within(dialogo).getByRole('radio', { name: /Qorilazo/ }))
    await user.type(motivo(), 'Cooperativa equivocada')
    await waitFor(() => expect(enviar()).toBeEnabled())
    await user.click(enviar())
    await waitFor(() => expect(controles.alTerminar).toHaveBeenCalledWith(ORIGINAL, idem))
    expect(cerrar).toHaveBeenCalled()
  })

  it('un rechazo del servidor se muestra tal cual y no cierra', async () => {
    const { dialogo, controles, cerrar, motivo, enviar, user } = montar({
      reemplazar: vi.fn(async () => { throw new CrmApiError('El mes de esta venta ya está cerrado: no se reemplaza', 'CONFLICTO') }),
    })
    await user.click(within(dialogo).getByRole('radio', { name: /Qorilazo/ }))
    await user.type(motivo(), 'Cooperativa equivocada')
    await waitFor(() => expect(enviar()).toBeEnabled())
    await user.click(enviar())
    expect(await within(dialogo).findByRole('alert')).toHaveTextContent('El mes de esta venta ya está cerrado: no se reemplaza')
    expect(cerrar).not.toHaveBeenCalled()
    expect(controles.alTerminar).not.toHaveBeenCalled()
  })

  it('mientras envía, el foco se queda en el botón y Esc no cierra', async () => {
    const { dialogo, cerrar, motivo, enviar, user } = montar({ reemplazar: vi.fn(() => new Promise<never>(() => {})) })
    await user.click(within(dialogo).getByRole('radio', { name: /Qorilazo/ }))
    await user.type(motivo(), 'Cooperativa equivocada')
    await waitFor(() => expect(enviar()).toBeEnabled())
    await user.click(enviar())
    const enviando = await within(dialogo).findByRole('button', { name: 'Reemplazando…' })
    expect(enviando).toHaveAttribute('aria-disabled', 'true')
    expect(enviando).toHaveFocus()
    expect(within(dialogo).getByRole('radio', { name: /Prodelco/ })).toBeDisabled()
    await user.keyboard('{Escape}')
    expect(cerrar).not.toHaveBeenCalled()
  })
})

describe('Reemplazar inversión de cooperativa · lo que el servidor negaría', () => {
  it.each([
    ['la original tiene movimientos', { no_reemplazable: 'La inversión tiene una reinversión registrada: no se elimina' }, 'tiene una reinversión registrada'],
    ['la venta está anulada', { anulada: true, no_reemplazable: 'La venta de esta inversión ya fue anulada: se elimina, no se reemplaza' }, 'ya fue anulada'],
    ['el mes está cerrado', { mes_sellado: true }, 'El mes de esta venta ya está cerrado'],
    ['venció el plazo de carga', { plazo_vencido: true }, 'Venció el plazo de carga de octubre 2026'],
  ])('%s: se avisa al abrir y no deja confirmar', async (_n, over, texto) => {
    const { dialogo, motivo, enviar, user } = montar({ vistaPrevia: vi.fn(async (_i: InversionFuente, fecha: string) => previaDe(fecha, over)) })
    expect(await within(dialogo).findByRole('alert')).toHaveTextContent(texto)
    await user.click(within(dialogo).getByRole('radio', { name: /Qorilazo/ }))
    await user.type(motivo(), 'Cooperativa equivocada')
    expect(enviar()).toBeDisabled()
  })

  it('lo que es de la original (no reemplazable) sigue aunque falle un recálculo con otra fecha', async () => {
    const vistaPrevia = vi.fn(async (_i: InversionFuente, fecha: string) => {
      if (fecha === '2026-09-28') throw new CrmApiError('No llegó la respuesta del servidor.', 'RESPUESTA_NO_RECIBIDA')
      return previaDe(fecha, { no_reemplazable: 'La inversión tiene una reinversión registrada: no se elimina' })
    })
    const { dialogo, enviar } = montar({ vistaPrevia })
    expect(await within(dialogo).findByRole('alert')).toHaveTextContent('reinversión registrada')
    fireEvent.change(within(dialogo).getByLabelText('Fecha comercial'), { target: { value: '2026-09-28' } })
    expect(await within(dialogo).findByText('No llegó la respuesta del servidor.')).toBeVisible()
    expect(within(dialogo).getByText(/reinversión registrada/)).toBeVisible()
    expect(enviar()).toBeDisabled()
  })

  it('una fecha futura se dice en el acto y no deja confirmar', async () => {
    const { dialogo, motivo, enviar, user } = montar()
    const futura = `${Number(fechaLima(Date.now()).slice(0, 4)) + 1}-01-15`
    fireEvent.change(within(dialogo).getByLabelText('Fecha comercial'), { target: { value: futura } })
    expect(within(dialogo).getByRole('alert')).toHaveTextContent('La fecha comercial no puede ser futura.')
    expect(within(dialogo).getByLabelText('Fecha comercial')).toHaveAttribute('aria-invalid', 'true')
    expect(within(dialogo).getByLabelText('Fecha comercial')).toHaveAccessibleDescription(/no puede ser futura/)
    await user.type(motivo(), 'La fecha comercial era otra')
    expect(enviar()).toBeDisabled()
  })

  it('si el cálculo del mes falla, no se confirma y se puede reintentar (el foco pasa al motivo)', async () => {
    const vistaPrevia = vi.fn<ControlesReemplazoCooperativa['vistaPrevia']>()
      .mockRejectedValueOnce(new CrmApiError('No llegó la respuesta del servidor.', 'RESPUESTA_NO_RECIBIDA'))
      .mockResolvedValue(previa())
    const { dialogo, motivo, enviar, region, user } = montar({ vistaPrevia })
    await user.click(within(dialogo).getByRole('radio', { name: /Qorilazo/ }))
    expect(await within(dialogo).findByText('Sin el mes calculado no se puede confirmar: reintenta el cálculo.')).toBeVisible()
    const reintentar = within(dialogo).getByRole('button', { name: 'Reintentar el cálculo' })
    await user.click(reintentar)
    await waitFor(() => expect(region()).toHaveTextContent('Octubre 2026'))
    await waitFor(() => expect(motivo()).toHaveFocus())
    await user.type(motivo(), 'Cooperativa equivocada')
    expect(enviar()).toBeEnabled()
  })
})

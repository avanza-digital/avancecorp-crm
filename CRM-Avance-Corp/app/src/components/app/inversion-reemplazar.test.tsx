import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { useEffect, useState } from 'react'
import { InversionReemplazar, type ControlesReemplazo } from './inversion-reemplazar'
import { CrmApiError, type CrearContratoInput } from '@/data/crm-api'
import { fichaF5, inversionF5 } from '@/test/fixtures/f5'
import type { FichaInversionista, InversionFuente, VistaPreviaReemplazo } from '@/lib/inversionistas'

// El formulario de alta real tiene su propia batería (contrato-nuevo.test.tsx); aquí se prueba el reemplazo que lo envuelve:
// qué le pasa (precarga, bloqueo por motivo, textos) y qué hace con lo que devuelve.
// Simula el modo incrustado: su propio <form> (el botón de envío vive FUERA, en «Antes de confirmar»), su encabezado,
// el aviso de «listo» con su razón y el aviso de «enviando» alrededor de onRevisar, como el real. El contador de
// ediciones es estado propio: si el formulario se desmontara, volvería a 0.
const visto = vi.hoisted(() => ({ props: null as null | Record<string, unknown> }))
vi.mock('./contrato-nuevo', () => ({
  ContratoNuevo: (props: Record<string, unknown> & {
    borrador: CrearContratoInput
    incrustado: { titulo: string; idTitulo: string; idFormulario: string; onListoCambio: (listo: boolean, razon: string | null) => void }
    onRevisar: (i: CrearContratoInput, c: unknown[]) => Promise<void>
    onBorradorLocal: (d: Record<string, string>) => void
    onEnviandoCambio: (v: boolean) => void
  }) => {
    visto.props = props
    const [error, setError] = useState('')
    const [ediciones, setEdiciones] = useState(0)
    const [fecha, setFecha] = useState(props.borrador.fecha_inicio)
    const [listo, setListo] = useState(true)
    const { onListoCambio } = props.incrustado
    useEffect(() => { onListoCambio(listo, listo ? null : 'Elige la cuenta de pago del contrato.') }, [listo, onListoCambio])
    const enviar = async (fechaInicio: string) => {
      props.onEnviandoCambio(true)
      try { await props.onRevisar({ ...props.borrador, capital: 50000, fecha_inicio: fechaInicio, cuenta_pago: { tipo: 'existente', cuenta_id: 'x' } }, []) }
      catch (err) { setError((err as Error).message) }
      finally { props.onEnviandoCambio(false) }
    }
    return <form id={props.incrustado.idFormulario} onSubmit={e => { e.preventDefault(); void enviar(fecha) }}>
      <h3 id={props.incrustado.idTitulo}>{props.incrustado.titulo}</h3>
      <p>Ediciones: {ediciones}</p>
      <button type="button" onClick={() => {
        setEdiciones(n => n + 1)
        setFecha('2026-09-28')
        props.onBorradorLocal({ capital: '50000', moneda: 'PEN', tasa: '15', fechaInicio: '2026-09-28', prefijo: '2026-01-', numero: '999999' })
      }}>Editar (simulado)</button>
      <button type="button" onClick={() => setListo(false)}>Quitar la cuenta (simulado)</button>
      {/* Un envío que no pasa por el botón de confirmar (Enter, o un clic en el mismo instante en que cambia la fecha). */}
      <button type="button" onClick={() => void enviar('2026-09-15')}>Enviar otra fecha sin el botón (simulado)</button>
      {error && <p role="alert">{error}</p>}
    </form>
  },
}))

const CLIENTE = '44444444-4444-4444-8444-444444444444'
const inv = (fuente: string, numero: string, over: Partial<InversionFuente> = {}): InversionFuente => ({
  ...inversionF5, fuente_id: fuente, empresa: 'avance', perfil_id: CLIENTE, numero, capital: 5000, moneda: 'PEN', estado: 'activo',
  es_inicial: false, lead_id: null, vence_en: '2027-10-05', fecha_comercial: '2026-10-05', cotitulares: [],
  analista_venta_nombre: 'ANALISTA DE LA VENTA',
  contrato: { fecha_inicio: '2026-10-05', tasa_anual: 15, modalidad: 'mensual', tipo_interes: 'simple', categoria: 'nuevo' }, ...over,
})
const ORIGINAL = inv('33333333-3333-4333-8333-333333333333', '2026-01-999999')
const IGUAL = inv('55555555-5555-4555-8555-555555555555', '2026-01-999998')
const DISTINTA = inv('66666666-6666-4666-8666-666666666666', '2026-01-999997', { capital: 800 })
const ficha = (inversiones: InversionFuente[]): FichaInversionista => ({ ...fichaF5, persona: { ...fichaF5.persona, perfil_id: CLIENTE }, inversiones, inversiones_total: inversiones.length })
const previa = (over: Partial<VistaPreviaReemplazo> = {}): VistaPreviaReemplazo => ({ fuente_id: ORIGINAL.fuente_id, fecha_inicio: '2026-10-05',
  fecha_comercial_actual: '2026-10-05', mes_actual: '2026-10-01', fecha_comercial_resultante: '2026-10-05', mes_resultante: '2026-10-01',
  cambia_mes: false, fecha_corregida: false, cuotas_pagadas: false, ...over })

function montar(inversiones = [ORIGINAL], over: Partial<ControlesReemplazo> = {}) {
  const controles: ControlesReemplazo = {
    puede: () => true,
    vistaPrevia: vi.fn(async (_i, o) => 'fechaInicio' in o && o.fechaInicio === '2026-09-28'
      ? previa({ fecha_inicio: '2026-09-28', fecha_comercial_resultante: '2026-09-28', mes_resultante: '2026-09-01', cambia_mes: true }) : previa()),
    reemplazar: vi.fn(async () => ({ contratoId: 'n', numeroContrato: '2026-01-999999', modo: 'nueva' as const, idempotente: false, periodoVenta: null })),
    conservar: vi.fn(async () => ({ contratoId: IGUAL.fuente_id, numeroContrato: IGUAL.numero, modo: 'existente' as const, idempotente: false, periodoVenta: null })),
    alTerminar: vi.fn(),
    ...over,
  }
  const cerrar = vi.fn()
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  render(<QueryClientProvider client={qc}><InversionReemplazar inversion={ORIGINAL} ficha={ficha(inversiones)} controles={controles} onCerrar={cerrar} /></QueryClientProvider>)
  return { controles, cerrar, user: userEvent.setup(), dialogo: screen.getByRole('dialog', { name: 'Reemplazar inversión 2026-01-999999' }) }
}
afterEach(() => { cleanup(); visto.props = null })

describe('Reemplazar inversión · con los datos correctos', () => {
  it('precarga la original como «nuevo», sin cuenta elegida; cliente y analista solo se muestran', async () => {
    const { dialogo } = montar()
    expect(within(dialogo).getByText('La original')).toBeVisible()
    expect(within(dialogo).getByText('ANALISTA DE LA VENTA')).toBeVisible()
    const b = visto.props!.borrador as CrearContratoInput
    expect(b).toMatchObject({ cliente_id: CLIENTE, capital: 5000, categoria: 'nuevo', numero_contrato: '2026-01-999999', fecha_inicio: '2026-10-05', tasa_anual: 15 })
    expect(b.cuenta_pago).toEqual({ tipo: 'existente', cuenta_id: '' })
    expect(visto.props!.analistas).toBeUndefined()           // sin selector: el servidor fija el analista del original
    expect(visto.props!.categoriaFija).toBe('nuevo')
    expect(await within(dialogo).findByText('Octubre 2026')).toBeVisible()
    expect(within(dialogo).getByText('Igual que ahora')).toBeVisible()
    expect(within(dialogo).getByText('Mensual · interés simple')).toBeVisible()
    // Un solo título de diálogo; «La correcta» es una sección con su propio encabezado.
    expect(within(dialogo).getAllByRole('heading', { level: 2 })).toHaveLength(1)
    expect(within(dialogo).getByRole('region', { name: 'La correcta' })).toBeVisible()
  })

  it('las acciones van después del motivo (orden de foco y de lectura)', () => {
    const { dialogo } = montar()
    const motivo = within(dialogo).getByLabelText('Motivo del reemplazo')
    const enviar = within(dialogo).getByRole('button', { name: 'Reemplazar inversión' })
    expect(motivo.compareDocumentPosition(enviar) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy()
    expect(motivo).toHaveAttribute('aria-required', 'true')
  })

  it('ida y vuelta a «Quedarme con la otra»: el formulario, el resumen y el mes siguen coincidiendo', async () => {
    const { dialogo, user } = montar([ORIGINAL, IGUAL])
    await user.click(within(dialogo).getByRole('button', { name: 'Editar (simulado)' }))
    expect(await within(dialogo).findByText('Septiembre 2026')).toBeVisible()
    await user.click(within(dialogo).getByRole('button', { name: 'Quedarme con la otra' }))
    expect(within(dialogo).queryByRole('region', { name: 'La correcta' })).toBeNull()      // oculta, no visible
    await user.click(within(dialogo).getByRole('button', { name: 'Con los datos correctos' }))
    expect(within(dialogo).getByText('Ediciones: 1')).toBeVisible()                        // no se desmontó
    expect(within(dialogo).getByRole('list', { name: 'Cambios' })).toHaveTextContent('S/ 50,000')
    expect(await within(dialogo).findByText('Septiembre 2026')).toBeVisible()
  })

  it('si el formulario no está listo (p. ej. sin cuenta), no se envía aunque haya motivo', async () => {
    const { dialogo, user } = montar()
    await user.type(within(dialogo).getByLabelText('Motivo del reemplazo'), 'El capital se registró mal')
    const enviar = within(dialogo).getByRole('button', { name: 'Reemplazar inversión' })
    expect(enviar).toBeEnabled()
    await user.click(within(dialogo).getByRole('button', { name: 'Quitar la cuenta (simulado)' }))
    expect(enviar).toBeDisabled()
  })

  it('pasarse del tope del motivo se anuncia', async () => {
    const { dialogo, user } = montar()
    await user.click(within(dialogo).getByLabelText('Motivo del reemplazo'))
    await user.paste('x'.repeat(301))
    expect(within(dialogo).getByText(/El motivo pasa de 300 caracteres/)).toBeInTheDocument()
    expect(within(dialogo).getByRole('button', { name: 'Reemplazar inversión' })).toBeDisabled()
  })

  it('el motivo bloquea el envío; la mudanza de mes se anuncia; envía al reemplazo y termina', async () => {
    const { dialogo, user, controles, cerrar } = montar()
    const enviar = within(dialogo).getByRole('button', { name: 'Reemplazar inversión' })
    expect(enviar).toBeDisabled()
    await user.click(within(dialogo).getByRole('button', { name: 'Editar (simulado)' }))
    expect(await within(dialogo).findByText('Septiembre 2026')).toBeVisible()
    expect(within(dialogo).getByText(/Se muda desde octubre 2026/)).toBeVisible()
    expect(within(dialogo).getByRole('list', { name: 'Cambios' })).toHaveTextContent('S/ 50,000')
    await user.type(within(dialogo).getByLabelText('Motivo del reemplazo'), 'El capital se registró mal')
    expect(enviar).toBeEnabled()
    await user.click(enviar)
    await waitFor(() => expect(controles.reemplazar).toHaveBeenCalledWith(ORIGINAL, 'El capital se registró mal', expect.objectContaining({ capital: 50000 }), []))
    expect(controles.alTerminar).toHaveBeenCalledWith(ORIGINAL, expect.objectContaining({ modo: 'nueva' }))
    expect(cerrar).toHaveBeenCalled()
  })

  it('un rechazo del servidor llega al formulario tal cual y no cierra', async () => {
    const { dialogo, user, cerrar, controles } = montar([ORIGINAL], {
      reemplazar: vi.fn(async () => { throw new CrmApiError('El mes de esta venta ya está cerrado: no se reemplaza', 'CONFLICTO') }),
    })
    await user.type(within(dialogo).getByLabelText('Motivo del reemplazo'), 'Error de carga')
    await user.click(within(dialogo).getByRole('button', { name: 'Reemplazar inversión' }))
    expect(await within(dialogo).findByRole('alert')).toHaveTextContent('El mes de esta venta ya está cerrado: no se reemplaza')
    expect(cerrar).not.toHaveBeenCalled()
    expect(controles.alTerminar).not.toHaveBeenCalled()
  })

  it('si la previa falla, se dice y no se inventa un mes', async () => {
    const { dialogo } = montar([ORIGINAL], { vistaPrevia: vi.fn(async () => { throw new CrmApiError('No llegó la respuesta del servidor.', 'RESPUESTA_NO_RECIBIDA') }) })
    expect(await within(dialogo).findByText('No llegó la respuesta del servidor.')).toBeVisible()
    expect(within(dialogo).queryByText('Octubre 2026')).toBeNull()
  })

  it('cuotas pagadas: se avisa al abrir y no deja enviar aunque haya motivo', async () => {
    const { dialogo, user } = montar([ORIGINAL], { vistaPrevia: vi.fn(async () => previa({ cuotas_pagadas: true })) })
    expect(await within(dialogo).findByRole('alert')).toHaveTextContent('ya tiene cuotas pagadas')
    await user.type(within(dialogo).getByLabelText('Motivo del reemplazo'), 'Error de carga')
    expect(within(dialogo).getByRole('button', { name: 'Reemplazar inversión' })).toBeDisabled()
  })

  it('cuotas pagadas: mientras se recalcula el mes, el aviso no se desmonta ni se levanta el bloqueo', async () => {
    let soltar: (v: VistaPreviaReemplazo) => void = () => {}
    const vistaPrevia = vi.fn(async (_i: InversionFuente, o: { fechaInicio: string } | { conservarId: string }) =>
      'fechaInicio' in o && o.fechaInicio === '2026-09-28'
        ? new Promise<VistaPreviaReemplazo>(r => { soltar = r }) : previa({ cuotas_pagadas: true }))
    const { dialogo, user } = montar([ORIGINAL], { vistaPrevia })
    const aviso = await within(dialogo).findByRole('alert')
    await user.type(within(dialogo).getByLabelText('Motivo del reemplazo'), 'Error de carga')
    await user.click(within(dialogo).getByRole('button', { name: 'Editar (simulado)' }))
    await waitFor(() => expect(vistaPrevia).toHaveBeenCalledWith(ORIGINAL, { fechaInicio: '2026-09-28' }))
    expect(within(dialogo).getByText('La venta queda en').closest('[role="status"]')).toHaveAttribute('aria-busy', 'true')
    expect(aviso).toBeInTheDocument()                                                      // el MISMO nodo
    expect(within(dialogo).getByRole('button', { name: 'Reemplazar inversión' })).toBeDisabled()
    soltar(previa({ cuotas_pagadas: true, mes_resultante: '2026-09-01', cambia_mes: true }))
    expect(await within(dialogo).findByText('Septiembre 2026')).toBeVisible()
    expect(aviso).toBeInTheDocument()
  })

  it('sin el formulario listo, la pista dice QUÉ falta (no promete que basta el motivo)', async () => {
    const { dialogo, user } = montar()
    await user.type(within(dialogo).getByLabelText('Motivo del reemplazo'), 'El capital se registró mal')
    await user.click(within(dialogo).getByRole('button', { name: 'Quitar la cuenta (simulado)' }))
    expect(within(dialogo).getByText('Elige la cuenta de pago del contrato.')).toBeVisible()
    expect(within(dialogo).getByLabelText('Motivo del reemplazo')).toHaveAccessibleDescription(/Elige la cuenta de pago del contrato\./)
    expect(within(dialogo).queryByText(/Con el motivo escrito se activa/)).toBeNull()
  })

  it('con la fecha recién cambiada no se confirma hasta tener SU mes (respiro y respuesta anterior incluidos)', async () => {
    let soltar: (v: VistaPreviaReemplazo) => void = () => {}
    const vistaPrevia = vi.fn(async (_i: InversionFuente, o: { fechaInicio: string } | { conservarId: string }) =>
      'fechaInicio' in o && o.fechaInicio === '2026-09-28' ? new Promise<VistaPreviaReemplazo>(r => { soltar = r }) : previa())
    const { dialogo, user, controles } = montar([ORIGINAL], { vistaPrevia })
    await user.type(within(dialogo).getByLabelText('Motivo del reemplazo'), 'El capital se registró mal')
    const enviar = within(dialogo).getByRole('button', { name: 'Reemplazar inversión' })
    await waitFor(() => expect(enviar).toBeEnabled())
    await user.click(within(dialogo).getByRole('button', { name: 'Editar (simulado)' }))
    expect(enviar).toBeDisabled()                                                          // en el respiro
    await waitFor(() => expect(vistaPrevia).toHaveBeenCalledWith(ORIGINAL, { fechaInicio: '2026-09-28' }))
    expect(within(dialogo).getByText('Octubre 2026')).toBeVisible()                        // la respuesta anterior sigue a la vista…
    expect(enviar).toBeDisabled()                                                          // …pero no sirve para confirmar
    soltar(previa({ fecha_inicio: '2026-09-28', mes_resultante: '2026-09-01', cambia_mes: true }))
    await waitFor(() => expect(enviar).toBeEnabled())
    expect(within(dialogo).getByText('Septiembre 2026')).toBeVisible()
    await user.click(enviar)
    await waitFor(() => expect(controles.reemplazar).toHaveBeenCalledWith(ORIGINAL, 'El capital se registró mal', expect.objectContaining({ fecha_inicio: '2026-09-28' }), []))
  })

  it('un envío por fuera del botón con una fecha sin mes calculado se frena en el diálogo', async () => {
    const { dialogo, user, controles } = montar()
    await user.type(within(dialogo).getByLabelText('Motivo del reemplazo'), 'El capital se registró mal')
    await waitFor(() => expect(within(dialogo).getByRole('button', { name: 'Reemplazar inversión' })).toBeEnabled())
    await user.click(within(dialogo).getByRole('button', { name: 'Enviar otra fecha sin el botón (simulado)' }))
    expect(await within(dialogo).findByRole('alert')).toHaveTextContent('todavía se está calculando con la fecha nueva')
    expect(controles.reemplazar).not.toHaveBeenCalled()
  })

  it('si el cálculo del mes falla, no se confirma y se puede reintentar', async () => {
    const vistaPrevia = vi.fn<ControlesReemplazo['vistaPrevia']>()
      .mockRejectedValueOnce(new CrmApiError('No llegó la respuesta del servidor.', 'RESPUESTA_NO_RECIBIDA'))
      .mockResolvedValue(previa())
    const { dialogo, user } = montar([ORIGINAL], { vistaPrevia })
    await user.type(within(dialogo).getByLabelText('Motivo del reemplazo'), 'El capital se registró mal')
    expect(await within(dialogo).findByText('Sin el mes calculado no se puede confirmar: reintenta el cálculo.')).toBeVisible()
    expect(within(dialogo).getByRole('button', { name: 'Reemplazar inversión' })).toBeDisabled()
    await user.click(within(dialogo).getByRole('button', { name: 'Reintentar el cálculo' }))
    expect(await within(dialogo).findByText('Octubre 2026')).toBeVisible()
    expect(within(dialogo).getByRole('button', { name: 'Reemplazar inversión' })).toBeEnabled()
  })

  it('reintentar el cálculo: el botón no se desmonta al pulsarlo; con éxito el foco va al motivo', async () => {
    let soltar: (v: VistaPreviaReemplazo) => void = () => {}
    const vistaPrevia = vi.fn<ControlesReemplazo['vistaPrevia']>()
      .mockResolvedValueOnce(previa())
      .mockRejectedValueOnce(new CrmApiError('No llegó la respuesta del servidor.', 'RESPUESTA_NO_RECIBIDA'))
      .mockImplementationOnce(() => new Promise<VistaPreviaReemplazo>(r => { soltar = r }))
    const { dialogo, user } = montar([ORIGINAL], { vistaPrevia })
    expect(await within(dialogo).findByText('Octubre 2026')).toBeVisible()                 // fecha A, bien
    await user.click(within(dialogo).getByRole('button', { name: 'Editar (simulado)' }))   // fecha B, falla
    const reintentar = await within(dialogo).findByRole('button', { name: 'Reintentar el cálculo' })
    // Con el motivo vacío, la pista dice lo que de verdad falta (no promete que basta el motivo).
    expect(within(dialogo).getByText('Sin el mes calculado no se puede confirmar: reintenta el cálculo.')).toBeVisible()
    expect(within(dialogo).queryByText(/Con el motivo escrito se activa/)).toBeNull()
    await user.click(reintentar)
    expect(reintentar).toBeInTheDocument()                                                   // el MISMO nodo, montado
    expect(reintentar).toHaveFocus()
    expect(reintentar).toHaveAttribute('aria-disabled', 'true')
    // La región no anuncia el mes de relleno (el de la fecha A) mientras reintenta.
    expect(within(dialogo).getByText('La venta queda en').closest('[role="status"]')).toHaveTextContent('Calculando el mes…')
    expect(within(dialogo).queryByText('Octubre 2026')).toBeNull()
    soltar(previa({ fecha_inicio: '2026-09-28', mes_resultante: '2026-09-01', cambia_mes: true }))
    expect(await within(dialogo).findByText('Septiembre 2026')).toBeVisible()
    expect(within(dialogo).getByLabelText('Motivo del reemplazo')).toHaveFocus()
  })

  it('reintentar el cálculo: si mientras tanto se fue a otro campo, al resolver no le roba el foco', async () => {
    let soltar: (v: VistaPreviaReemplazo) => void = () => {}
    const vistaPrevia = vi.fn<ControlesReemplazo['vistaPrevia']>()
      .mockRejectedValueOnce(new CrmApiError('No llegó la respuesta del servidor.', 'RESPUESTA_NO_RECIBIDA'))
      .mockImplementationOnce(() => new Promise<VistaPreviaReemplazo>(r => { soltar = r }))
    const { dialogo, user } = montar([ORIGINAL], { vistaPrevia })
    await user.click(await within(dialogo).findByRole('button', { name: 'Reintentar el cálculo' }))
    await user.click(within(dialogo).getByRole('button', { name: 'Editar (simulado)' }))      // se fue a otro control
    const otro = within(dialogo).getByRole('button', { name: 'Editar (simulado)' })
    expect(otro).toHaveFocus()
    soltar(previa())
    await waitFor(() => expect(vistaPrevia).toHaveBeenCalledTimes(3))
    await new Promise(r => setTimeout(r, 0))
    expect(otro).toHaveFocus()
    expect(within(dialogo).getByLabelText('Motivo del reemplazo')).not.toHaveFocus()
  })

  it('reintentar el cálculo: si vuelve a fallar, el foco se queda en el mismo botón', async () => {
    const vistaPrevia = vi.fn<ControlesReemplazo['vistaPrevia']>()
      .mockRejectedValue(new CrmApiError('No llegó la respuesta del servidor.', 'RESPUESTA_NO_RECIBIDA'))
    const { dialogo, user } = montar([ORIGINAL], { vistaPrevia })
    const reintentar = await within(dialogo).findByRole('button', { name: 'Reintentar el cálculo' })
    await user.click(reintentar)
    await waitFor(() => expect(vistaPrevia).toHaveBeenCalledTimes(2))
    await waitFor(() => expect(reintentar).not.toHaveAttribute('aria-disabled'))
    expect(reintentar).toBeInTheDocument()
    expect(reintentar).toHaveFocus()
  })

  it('cuotas pagadas: el aviso sigue aunque falle un recálculo con otra fecha', async () => {
    const vistaPrevia = vi.fn(async (_i: InversionFuente, o: { fechaInicio: string } | { conservarId: string }) => {
      if ('fechaInicio' in o && o.fechaInicio === '2026-09-28') throw new CrmApiError('No llegó la respuesta del servidor.', 'RESPUESTA_NO_RECIBIDA')
      return previa({ cuotas_pagadas: true })
    })
    const { dialogo, user } = montar([ORIGINAL], { vistaPrevia })
    expect(await within(dialogo).findByRole('alert')).toHaveTextContent('ya tiene cuotas pagadas')
    await user.click(within(dialogo).getByRole('button', { name: 'Editar (simulado)' }))
    expect(await within(dialogo).findByText('No llegó la respuesta del servidor.')).toBeVisible()
    expect(within(dialogo).getByText(/ya tiene cuotas pagadas/)).toBeVisible()
    expect(within(dialogo).getByRole('button', { name: 'Reemplazar inversión' })).toBeDisabled()
  })

  it('mientras envía, el foco se queda en el botón y Esc no cierra', async () => {
    const { dialogo, user, cerrar } = montar([ORIGINAL], { reemplazar: vi.fn(() => new Promise<never>(() => {})) })
    await user.type(within(dialogo).getByLabelText('Motivo del reemplazo'), 'El capital se registró mal')
    const enviar = within(dialogo).getByRole('button', { name: 'Reemplazar inversión' })
    await waitFor(() => expect(enviar).toBeEnabled())
    await user.click(enviar)
    const enviando = await within(dialogo).findByRole('button', { name: 'Reemplazando…' })
    expect(enviando).toHaveAttribute('aria-disabled', 'true')
    expect(enviando).toHaveFocus()
    await user.keyboard('{Escape}')
    expect(cerrar).not.toHaveBeenCalled()
  })

  it('una fecha corregida por Gerencia se conserva y se avisa', async () => {
    const { dialogo } = montar([ORIGINAL], { vistaPrevia: vi.fn(async () => previa({ fecha_corregida: true })) })
    expect(await within(dialogo).findByText('Gerencia corrigió la fecha de esta venta: se conserva.')).toBeVisible()
  })
})

describe('Reemplazar inversión · quedarme con la otra', () => {
  it('ESTADO DE PRODUCCIÓN: un cliente con una sola inversión no tiene otra que conservar', async () => {
    const { dialogo, user } = montar([ORIGINAL])
    await user.click(within(dialogo).getByRole('button', { name: 'Quedarme con la otra' }))
    expect(within(dialogo).getByText(/no tiene otra inversión de Avance para conservar/)).toBeVisible()
    expect(within(dialogo).getByRole('button', { name: 'Quedarme con la otra' })).toHaveAttribute('aria-pressed', 'true')
    expect(within(dialogo).getByRole('button', { name: 'Sin inversión para conservar' })).toBeDisabled()
    expect(within(dialogo).getByText('La venta queda en').closest('[role="status"]')).toHaveTextContent('No hay otra inversión de este cliente para conservar.')
  })

  it('muestra cuál es igual y cuál distinta; envía la elegida con el motivo', async () => {
    const { dialogo, user, controles, cerrar } = montar([ORIGINAL, IGUAL, DISTINTA])
    await user.click(within(dialogo).getByRole('button', { name: 'Quedarme con la otra' }))
    expect(within(dialogo).getByRole('region', { name: 'La que se conserva' })).toBeVisible()
    expect(within(dialogo).getByText('Elige la inversión que se conserva.')).toBeVisible()
    expect(within(dialogo).getByText('Igual a la original')).toBeVisible()
    expect(within(dialogo).getByText('Distinta: capital')).toBeVisible()
    await user.click(within(dialogo).getByRole('radio', { name: /2026-01-999997/ }))
    expect(within(dialogo).getByText(/Solo se conserva una carga doble/)).toBeVisible()
    await user.click(within(dialogo).getByRole('radio', { name: /2026-01-999998/ }))
    await waitFor(() => expect(controles.vistaPrevia).toHaveBeenCalledWith(ORIGINAL, { conservarId: IGUAL.fuente_id }))
    const confirmar = within(dialogo).getByRole('button', { name: 'Quedarme con 2026-01-999998' })
    expect(confirmar).toBeDisabled()
    await user.type(within(dialogo).getByLabelText('Motivo del reemplazo'), 'Cargada dos veces')
    await user.click(confirmar)
    await waitFor(() => expect(controles.conservar).toHaveBeenCalledWith(ORIGINAL, IGUAL.fuente_id, 'Cargada dos veces'))
    expect(controles.alTerminar).toHaveBeenCalled()
    expect(cerrar).toHaveBeenCalled()
  })

  it('cuotas pagadas: el aviso sale antes de elegir y la confirmación queda bloqueada', async () => {
    const { dialogo, user, controles } = montar([ORIGINAL, IGUAL], { vistaPrevia: vi.fn(async () => previa({ cuotas_pagadas: true })) })
    await user.click(within(dialogo).getByRole('button', { name: 'Quedarme con la otra' }))
    expect(await within(dialogo).findByRole('alert')).toHaveTextContent('ya tiene cuotas pagadas')
    expect(controles.vistaPrevia).toHaveBeenCalledWith(ORIGINAL, { fechaInicio: '2026-10-05' })
    await user.click(within(dialogo).getByRole('radio', { name: /2026-01-999998/ }))
    await user.type(within(dialogo).getByLabelText('Motivo del reemplazo'), 'Cargada dos veces')
    expect(within(dialogo).getByRole('button', { name: 'Quedarme con 2026-01-999998' })).toBeDisabled()
  })

  it('al cambiar de candidata con su mes pendiente, la respuesta de la anterior no habilita confirmar', async () => {
    const OTRA_IGUAL = inv('77777777-7777-4777-8777-777777777777', '2026-01-999996')
    let soltar: (v: VistaPreviaReemplazo) => void = () => {}
    const vistaPrevia = vi.fn(async (_i: InversionFuente, o: { fechaInicio: string } | { conservarId: string }) =>
      'conservarId' in o && o.conservarId === OTRA_IGUAL.fuente_id ? new Promise<VistaPreviaReemplazo>(r => { soltar = r }) : previa())
    const { dialogo, user, controles } = montar([ORIGINAL, IGUAL, OTRA_IGUAL], { vistaPrevia })
    await user.click(within(dialogo).getByRole('button', { name: 'Quedarme con la otra' }))
    await user.type(within(dialogo).getByLabelText('Motivo del reemplazo'), 'Cargada dos veces')
    await user.click(within(dialogo).getByRole('radio', { name: /2026-01-999998/ }))
    await waitFor(() => expect(within(dialogo).getByRole('button', { name: 'Quedarme con 2026-01-999998' })).toBeEnabled())
    await user.click(within(dialogo).getByRole('radio', { name: /2026-01-999996/ }))
    const confirmar = within(dialogo).getByRole('button', { name: 'Quedarme con 2026-01-999996' })
    await waitFor(() => expect(vistaPrevia).toHaveBeenCalledWith(ORIGINAL, { conservarId: OTRA_IGUAL.fuente_id }))
    expect(confirmar).toBeDisabled()                                                       // la de 999998 no sirve para 999996
    soltar(previa())
    await waitFor(() => expect(confirmar).toBeEnabled())
    await user.click(confirmar)
    await waitFor(() => expect(controles.conservar).toHaveBeenCalledWith(ORIGINAL, OTRA_IGUAL.fuente_id, 'Cargada dos veces'))
  })

  it('mientras envía «quedarme con…», el foco se queda, las opciones se bloquean y Esc no cierra', async () => {
    const { dialogo, user, cerrar } = montar([ORIGINAL, IGUAL], { conservar: vi.fn(() => new Promise<never>(() => {})) })
    await user.click(within(dialogo).getByRole('button', { name: 'Quedarme con la otra' }))
    await user.click(within(dialogo).getByRole('radio', { name: /2026-01-999998/ }))
    await user.type(within(dialogo).getByLabelText('Motivo del reemplazo'), 'Cargada dos veces')
    const confirmar = within(dialogo).getByRole('button', { name: 'Quedarme con 2026-01-999998' })
    await waitFor(() => expect(confirmar).toBeEnabled())
    await user.click(confirmar)
    const enviando = await within(dialogo).findByRole('button', { name: 'Reemplazando…' })
    expect(enviando).toHaveAttribute('aria-disabled', 'true')
    expect(enviando).toHaveFocus()
    expect(within(dialogo).getByRole('radio', { name: /2026-01-999998/ })).toBeDisabled()
    await user.keyboard('{Escape}')
    expect(cerrar).not.toHaveBeenCalled()
  })

  it('el rechazo del servidor se muestra en el diálogo', async () => {
    const { dialogo, user, cerrar } = montar([ORIGINAL, IGUAL], {
      conservar: vi.fn(async () => { throw new CrmApiError('La inversión que se conserva no es igual a la original', 'CONFLICTO') }),
    })
    await user.click(within(dialogo).getByRole('button', { name: 'Quedarme con la otra' }))
    await user.click(within(dialogo).getByRole('radio', { name: /2026-01-999998/ }))
    await user.type(within(dialogo).getByLabelText('Motivo del reemplazo'), 'Cargada dos veces')
    await user.click(within(dialogo).getByRole('button', { name: 'Quedarme con 2026-01-999998' }))
    expect(await within(dialogo).findByRole('alert')).toHaveTextContent('La inversión que se conserva no es igual a la original')
    expect(cerrar).not.toHaveBeenCalled()
  })
})

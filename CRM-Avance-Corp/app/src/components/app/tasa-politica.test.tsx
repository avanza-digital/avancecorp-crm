import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { SolicitudTasa } from '@/data/crm-api'

const dobles = vi.hoisted(() => ({
  resolucion: {} as Record<string, unknown>,
  solicitudes: [] as unknown[],
  solicitar: vi.fn(),
  responder: vi.fn(),
  refetch: vi.fn(),
  refetchSolicitudes: vi.fn(),
  solicitudesPending: false,
  solicitudesError: false,
}))

vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }))
vi.mock('@/data/crm-queries', () => ({
  useResolucionTasa: () => ({ refetch: dobles.refetch, ...dobles.resolucion }),
  useSolicitudesTasa: () => ({ data: dobles.solicitudes, isPending: dobles.solicitudesPending, isError: dobles.solicitudesError, refetch: dobles.refetchSolicitudes }),
  useSolicitarTasa: () => ({ mutateAsync: dobles.solicitar, isPending: false }),
  useResponderTopeTasa: () => ({ mutateAsync: dobles.responder, isPending: false }),
}))

const { TasaPolitica } = await import('./tasa-politica')

const RES = {
  tasa_base: 15, regla: 'primera_inversion', contrato_origen: null, contratos_previos: 0, prioridad_bandeja: false,
  politica: { version: 1, modo: 'observacion', tasa_base_nueva: 15, tope_tecnico: 50, vigencia_solicitud_dias: 7 },
}
const INTENCION = { capital: 20000, moneda: 'PEN' as const, modalidad: 'mensual' as const, tipo_interes: 'simple' as const, fecha_inicio: '2026-10-01', fecha_vencimiento: '2027-10-01' }

function solicitud(sobre: Partial<SolicitudTasa> = {}): SolicitudTasa {
  return {
    id: 's-1', estado: 'pendiente', estado_efectivo: 'pendiente', vigente: true, categoria: 'nuevo', cliente_id: 'cli-1', cliente_nombre: 'CLIENTE',
    contrato_origen_id: null, contrato_origen_numero: null, producto_condicion_id: null, capital: 20000, moneda: 'PEN', modalidad: 'mensual', tipo_interes: 'simple',
    fecha_inicio: '2026-10-01', fecha_vencimiento: '2027-10-01', tasa_base: 15, regla_base: 'primera_inversion', tasa_solicitada: 17,
    tasa_maxima_autorizada: null, motivo: 'Referido', motivo_resolucion: null, motivo_analista: null, prioridad_bandeja: false, contratos_previos: 0,
    solicitada_por: 'yo', solicitante_nombre: 'YO', solicitada_en: '2026-09-06T10:00:00Z', vence_en: '2026-09-13T10:00:00Z',
    resuelta_por: null, resolutor_nombre: null, resuelta_en: null, respondida_por_analista_en: null, contrato_id: null,
    es_mia: true, puede_resolver: false, puede_responder: false,
    ...sobre,
  }
}

function Arnes({ demo = false, correccion, tasaInicial = '15' }: { demo?: boolean; correccion?: { tasaActual: number }; tasaInicial?: string }) {
  return <ArnesInterno demo={demo} tasaInicial={tasaInicial} {...(correccion ? { correccion } : {})} />
}
import { useState } from 'react'
function ArnesInterno({ demo, correccion, tasaInicial }: { demo: boolean; correccion?: { tasaActual: number }; tasaInicial: string }) {
  const [tasa, setTasa] = useState(tasaInicial)
  const [rango, setRango] = useState<string>('')
  const [bloqueo, setBloqueo] = useState<string | null>(null)
  return (
    <>
      <TasaPolitica clienteId="cli-1" categoria="nuevo" contratoOrigenId={null} intencion={INTENCION} tasa={tasa} onTasaChange={setTasa}
        onRangoChange={(r) => { setRango(`${r.modo}:${r.minimo}-${r.maximo}`); setBloqueo(r.bloqueoContrato) }} demo={demo} {...(correccion ? { correccion } : {})} />
      <span data-testid="rango">{rango}</span>
      <span data-testid="tasa">{tasa}</span>
      <button type="button" disabled={!!bloqueo}>Crear contrato</button>
    </>
  )
}

describe('TasaPolitica (Rentabilidad R3)', () => {
  beforeEach(() => {
    // El fixture vence el 13/09: el caso debe conservar su fecha de referencia.
    // Sólo se fija Date; los temporizadores de userEvent siguen siendo reales.
    vi.setSystemTime(new Date('2026-09-10T12:00:00Z'))
    dobles.resolucion = { data: RES, isPending: false, isError: false }
    dobles.solicitudes = []
    dobles.solicitudesPending = false
    dobles.solicitudesError = false
    dobles.solicitar.mockReset()
    dobles.responder.mockReset()
    dobles.refetch.mockReset()
    dobles.refetchSolicitudes.mockReset()
  })

  afterEach(() => vi.useRealTimers())

  it('bloquea la tasa en la base del núcleo y expone el rango [base, base]', async () => {
    render(<Arnes />)
    const input = screen.getByLabelText('Tasa anual (%)') as HTMLInputElement
    // readOnly (no disabled): la tasa fijada es un dato que hay que poder leer y copiar.
    expect(input).toHaveAttribute('readonly')
    expect(input).toBeEnabled()
    expect(input.value).toBe('15')
    expect(screen.getByText(/Fijada por la política/)).toBeInTheDocument()
    expect(screen.getByText(/Primera inversión: tasa base de la política: 15%/)).toBeInTheDocument()
    await waitFor(() => expect(screen.getByTestId('rango')).toHaveTextContent('base:15-15'))
  })

  it('permite tipear una tasa menor, borrar y usar coma sin restablecer 15 en cada tecla', async () => {
    dobles.resolucion = { data: { ...RES, tasa_minima_sin_autorizacion: 0.01 }, isPending: false, isError: false }
    const user = userEvent.setup()
    const vista = render(<Arnes />)
    const input = screen.getByLabelText('Tasa anual (%)')
    expect(input).not.toHaveAttribute('readonly')
    await user.clear(input)
    expect(input).toHaveValue('')
    await user.type(input, '12,5')
    expect(input).toHaveValue('12,5')
    expect(input).not.toHaveAttribute('aria-invalid', 'true')
    expect(screen.getByTestId('rango')).toHaveTextContent('base:0.01-15')
    expect(screen.getByText('Hasta 15% sin aprobación')).toBeInTheDocument()
    vista.rerender(<Arnes />)
    expect(input).toHaveValue('12,5')
    expect(dobles.solicitar).not.toHaveBeenCalled()
  })

  it.each(['0', '-1', '16', '12.345', 'NaN', '1e1'])('marca %s como inválida y conserva lo escrito para corregirlo', (valor) => {
    dobles.resolucion = { data: { ...RES, tasa_minima_sin_autorizacion: 0.01 }, isPending: false, isError: false }
    render(<Arnes />)
    const input = screen.getByLabelText('Tasa anual (%)')
    fireEvent.change(input, { target: { value: valor } })
    expect(input).toHaveValue(valor)
    expect(input).toHaveAttribute('aria-invalid', 'true')
    expect(dobles.solicitar).not.toHaveBeenCalled()
  })

  it('conserva 12.5 desde el lead al resolver el contrato y recuperar la red', () => {
    dobles.resolucion = { data: { ...RES, tasa_minima_sin_autorizacion: 0.01 }, isPending: false, isError: false }
    const cambiar = vi.fn()
    const props = { clienteId: 'cli-1', categoria: 'nuevo' as const, contratoOrigenId: null, intencion: INTENCION,
      tasa: '12.5', tasaPreseleccionada: 12.5, onTasaChange: cambiar, demo: false }
    dobles.solicitudesPending = true
    const vista = render(<TasaPolitica {...props} />)
    dobles.solicitudesPending = false
    vista.rerender(<TasaPolitica {...props} />)
    dobles.solicitudesError = true
    vista.rerender(<TasaPolitica {...props} />)
    dobles.solicitudesError = false
    vista.rerender(<TasaPolitica {...props} />)
    expect(cambiar).not.toHaveBeenCalled()
  })

  it('bajar a 12.5 no elude una solicitud pendiente', () => {
    dobles.resolucion = { data: { ...RES, tasa_minima_sin_autorizacion: 0.01 }, isPending: false, isError: false }
    dobles.solicitudes = [solicitud()]
    render(<Arnes />)
    fireEvent.change(screen.getByLabelText('Tasa anual (%)'), { target: { value: '12.5' } })
    expect(screen.getByTestId('tasa')).toHaveTextContent('12.5')
    expect(screen.getByRole('button', { name: 'Crear contrato' })).toBeDisabled()
  })

  it.each([false, true])('si el servidor deja de aceptar la tasa del lead, bloquea sin elevarla (autorizada=%s)', (autorizada) => {
    if (autorizada) dobles.solicitudes = [solicitud({ estado: 'aprobada', estado_efectivo: 'aprobada', tasa_maxima_autorizada: 18 })]
    const cambiar = vi.fn()
    const rango = vi.fn()
    render(<TasaPolitica clienteId="cli-1" categoria="nuevo" contratoOrigenId={null} intencion={INTENCION}
      tasa="12.5" tasaPreseleccionada={12.5} onTasaChange={cambiar} onRangoChange={rango} demo={false} />)
    expect(cambiar).not.toHaveBeenCalled()
    expect(screen.getByLabelText('Tasa anual (%)')).toHaveValue('12.5')
    expect(screen.getByLabelText('Tasa anual (%)')).toHaveAttribute('aria-invalid', 'true')
    expect(rango).toHaveBeenLastCalledWith(expect.objectContaining({ bloqueoContrato: expect.stringContaining('La tasa acordada ya no está dentro del rango vigente') }))
  })

  it('el mínimo nuevo no habilita rebajas al corregir un contrato emitido', () => {
    dobles.resolucion = { data: { ...RES, tasa_minima_sin_autorizacion: 0.01 }, isPending: false, isError: false }
    render(<Arnes correccion={{ tasaActual: 13 }} tasaInicial="13" />)
    expect(screen.getByLabelText('Tasa anual (%)')).toHaveAttribute('readonly')
    expect(screen.getByTestId('rango')).toHaveTextContent('base:13-13')
  })

  it('si baja la base, mantiene el bloqueo de la tasa pactada aunque otra parte escriba el campo', () => {
    dobles.resolucion = { data: { ...RES, tasa_base: 12, tasa_minima_sin_autorizacion: 0.01 }, isPending: false, isError: false }
    const cambiar = vi.fn()
    const rango = vi.fn()
    const props = { clienteId: 'cli-1', categoria: 'nuevo' as const, contratoOrigenId: null, intencion: INTENCION,
      tasaPreseleccionada: 12.5, onTasaChange: cambiar, onRangoChange: rango, demo: false }
    const vista = render(<TasaPolitica {...props} tasa="12.5" />)
    expect(cambiar).not.toHaveBeenCalled()
    expect(rango).toHaveBeenLastCalledWith(expect.objectContaining({ bloqueoContrato: expect.stringContaining('La tasa acordada') }))
    vista.rerender(<TasaPolitica {...props} tasa="12" />)
    expect(cambiar).not.toHaveBeenCalled()
    expect(rango).toHaveBeenLastCalledWith(expect.objectContaining({ bloqueoContrato: expect.stringContaining('La tasa acordada') }))
  })

  it('una autorización que ya no cubre la tasa acordada exige revisión sin sustituirla por la base', () => {
    dobles.resolucion = { data: { ...RES, tasa_minima_sin_autorizacion: 0.01 }, isPending: false, isError: false }
    const cambiar = vi.fn()
    const rango = vi.fn()
    render(<TasaPolitica clienteId="cli-1" categoria="nuevo" contratoOrigenId={null} intencion={INTENCION}
      tasa="17" tasaPreseleccionada={17} onTasaChange={cambiar} onRangoChange={rango} demo={false} />)
    expect(cambiar).not.toHaveBeenCalled()
    expect(rango).toHaveBeenLastCalledWith(expect.objectContaining({ bloqueoContrato: expect.stringContaining('La tasa acordada') }))
  })

  it('conserva la tasa elegida en el lead cuando llega la autorización y después de un fallo de relectura', () => {
    const cambiar = vi.fn()
    const props = { clienteId: 'cli-1', categoria: 'nuevo' as const, contratoOrigenId: null, intencion: INTENCION, tasa: '17', tasaPreseleccionada: 17, onTasaChange: cambiar, demo: false }
    dobles.solicitudesPending = true
    const vista = render(<TasaPolitica {...props} />)
    expect(cambiar).not.toHaveBeenCalled()
    dobles.solicitudesPending = false
    dobles.solicitudes = [solicitud({ estado: 'aprobada', estado_efectivo: 'aprobada', tasa_maxima_autorizada: 18 })]
    vista.rerender(<TasaPolitica {...props} />)
    expect(cambiar).toHaveBeenLastCalledWith('17')
    cambiar.mockClear()
    dobles.solicitudesError = true
    vista.rerender(<TasaPolitica {...props} />)
    dobles.solicitudesError = false
    vista.rerender(<TasaPolitica {...props} />)
    expect(cambiar).not.toHaveBeenCalled()
  })

  it('respeta el bloqueo del cliente ya identificado aunque la petición venga de otra ficha', () => {
    dobles.resolucion = { data: { ...RES, bloqueo_conversion: 'La solicitud de tasa está pendiente de Gerencia.' }, isPending: false, isError: false }
    const rango = vi.fn()
    render(<TasaPolitica clienteId="" leadId="lead-1" categoria="nuevo" contratoOrigenId={null} intencion={INTENCION} tasa="15" onTasaChange={vi.fn()} onRangoChange={rango} demo={false} />)
    expect(rango).toHaveBeenLastCalledWith(expect.objectContaining({ bloqueoContrato: 'La solicitud de tasa está pendiente de Gerencia.' }))
    expect(screen.queryByRole('button', { name: 'Solicitar tasa superior' })).toBeNull()
  })

  it('mientras el núcleo responde, el rango está cargando y el input bloqueado', () => {
    dobles.resolucion = { data: undefined, isPending: true, isError: false }
    render(<Arnes />)
    expect(screen.getByLabelText('Tasa anual (%)')).toBeDisabled()
    expect(screen.getByText(/Consultando la política/)).toBeInTheDocument()
    expect(screen.getByTestId('rango')).toHaveTextContent('cargando:')
  })

  it('error del núcleo: mensaje con reintento', () => {
    dobles.resolucion = { data: undefined, isPending: false, isError: true }
    render(<Arnes />)
    fireEvent.click(screen.getByRole('button', { name: /Reintentar/ }))
    expect(dobles.refetch).toHaveBeenCalled()
  })

  it('pedir una excepción envía la intención completa y la tasa pedida; rechaza pedir la base', async () => {
    const { toast } = await import('sonner')
    dobles.solicitar.mockResolvedValue(solicitud())
    render(<Arnes />)
    fireEvent.click(screen.getByRole('button', { name: 'Solicitar tasa superior' }))
    // a11y: al abrir el mini-formulario el foco va al campo de la tasa pedida
    expect(screen.getByLabelText('Tasa solicitada (%)')).toHaveFocus()
    fireEvent.change(screen.getByLabelText('Tasa solicitada (%)'), { target: { value: '15' } })
    fireEvent.change(screen.getByLabelText('Motivo comercial'), { target: { value: 'Cliente referido' } })
    fireEvent.click(screen.getByRole('button', { name: 'Enviar a Gerencia' }))
    expect(dobles.solicitar).not.toHaveBeenCalled()
    expect(vi.mocked(toast.error)).toHaveBeenCalledWith(expect.stringMatching(/superior a la tasa base de 15%/))
    fireEvent.change(screen.getByLabelText('Tasa solicitada (%)'), { target: { value: '17' } })
    fireEvent.click(screen.getByRole('button', { name: 'Enviar a Gerencia' }))
    await waitFor(() => expect(dobles.solicitar).toHaveBeenCalledTimes(1))
    expect(dobles.solicitar.mock.calls[0]?.[0]).toMatchObject({
      tasaSolicitada: 17, motivo: 'Cliente referido',
      intencion: { cliente_id: 'cli-1', categoria: 'nuevo', contrato_origen_id: null, capital: 20000, moneda: 'PEN', fecha_inicio: '2026-10-01', fecha_vencimiento: '2027-10-01' },
    })
  })

  it('con una solicitud pendiente, lo dice y no ofrece pedir otra', () => {
    dobles.solicitudes = [solicitud()]
    render(<Arnes />)
    expect(screen.getByRole('status')).toHaveTextContent(/pendiente de Gerencia/)
    expect(screen.queryByRole('button', { name: 'Solicitar tasa superior' })).toBeNull()
    expect(screen.getByLabelText('Tasa anual (%)')).toHaveAttribute('readonly')
    expect(screen.getByRole('button', { name: 'Crear contrato' })).toBeDisabled()
  })

  it('el motivo admite escritura, espacios y saltos de línea, y el envío bloquea aunque la relectura quede vacía', async () => {
    const user = userEvent.setup()
    dobles.solicitar.mockResolvedValue(solicitud({ es_mia: false })) // la mutación SQL no incluye flags de lectura
    render(<Arnes />)
    await user.click(screen.getByRole('button', { name: 'Solicitar tasa superior' }))
    expect(screen.getByRole('button', { name: 'Crear contrato' })).toBeDisabled()
    await user.type(screen.getByLabelText('Tasa solicitada (%)'), '17')
    const motivo = screen.getByLabelText('Motivo comercial')
    await user.click(motivo)
    await user.type(motivo, 'Cliente referido{Enter}Mantiene su inversión')
    expect(motivo).toHaveFocus()
    expect(motivo).toHaveValue('Cliente referido\nMantiene su inversión')
    await user.click(screen.getByRole('button', { name: 'Enviar a Gerencia' }))
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent(/pendiente de Gerencia/))
    expect(dobles.solicitar).toHaveBeenCalledWith(expect.objectContaining({ motivo: 'Cliente referido\nMantiene su inversión' }))
    expect(screen.getByRole('button', { name: 'Crear contrato' })).toBeDisabled()
  })

  it('una pendiente con otro capital sigue bloqueando esta operación; la aprobación libera el bloqueo', () => {
    dobles.solicitudes = [solicitud({ capital: 99999 })]
    const vista = render(<Arnes />)
    expect(screen.getByRole('button', { name: 'Crear contrato' })).toBeDisabled()
    dobles.solicitudes = [solicitud({ estado: 'aprobada', estado_efectivo: 'aprobada', tasa_maxima_autorizada: 17 })]
    vista.rerender(<Arnes />)
    expect(screen.getByRole('button', { name: 'Crear contrato' })).toBeEnabled()
    expect(screen.getByTestId('tasa')).toHaveTextContent('17')
  })

  it('una solicitud recibida desde otra pestaña cierra el borrador y su aprobación permite continuar', () => {
    const vista = render(<Arnes />)
    fireEvent.click(screen.getByRole('button', { name: 'Solicitar tasa superior' }))
    dobles.solicitudes = [solicitud()]
    vista.rerender(<Arnes />)
    expect(screen.queryByLabelText('Motivo comercial')).toBeNull()
    expect(screen.getByRole('button', { name: 'Crear contrato' })).toBeDisabled()
    dobles.solicitudes = [solicitud({ estado: 'aprobada', estado_efectivo: 'aprobada', tasa_maxima_autorizada: 17 })]
    vista.rerender(<Arnes />)
    expect(screen.getByRole('button', { name: 'Crear contrato' })).toBeEnabled()
  })

  it.each(['rechazada', 'vencida'] as const)('una respuesta %s libera el contrato a la base', (estado) => {
    dobles.solicitudes = [solicitud()]
    const vista = render(<Arnes />)
    expect(screen.getByRole('button', { name: 'Crear contrato' })).toBeDisabled()
    dobles.solicitudes = [solicitud({ estado, estado_efectivo: estado, vigente: false, resuelta_en: new Date().toISOString() })]
    vista.rerender(<Arnes />)
    expect(screen.getByRole('button', { name: 'Crear contrato' })).toBeEnabled()
    expect(screen.getByTestId('tasa')).toHaveTextContent('15')
  })

  it.each(['pending', 'error'] as const)('con tasa acordada superior y consulta %s muestra el estado real sin sustituir la tasa', (estado) => {
    dobles.solicitudesPending = estado === 'pending'
    dobles.solicitudesError = estado === 'error'
    const cambiar = vi.fn()
    const rango = vi.fn()
    render(<TasaPolitica clienteId="cli-1" categoria="nuevo" contratoOrigenId={null} intencion={INTENCION} tasa="17" tasaPreseleccionada={17} onTasaChange={cambiar} onRangoChange={rango} demo={false} />)
    const mensaje = estado === 'pending'
      ? 'Consultando si hay solicitudes de tasa pendientes…'
      : 'No se pudieron verificar las solicitudes de tasa. Reintenta antes de continuar.'
    expect(screen.getByRole('status')).toHaveTextContent(mensaje)
    expect(rango).toHaveBeenLastCalledWith(expect.objectContaining({ bloqueoContrato: mensaje }))
    expect(screen.queryByText(/La tasa acordada ya no está/)).toBeNull()
    expect(cambiar).not.toHaveBeenCalled()
  })

  it('sin poder consultar solicitudes no permite crear; permite reintentar', () => {
    dobles.solicitudesPending = true
    const vista = render(<Arnes />)
    expect(screen.getByRole('button', { name: 'Crear contrato' })).toBeDisabled()
    dobles.solicitudesPending = false
    dobles.solicitudesError = true
    vista.rerender(<Arnes />)
    expect(screen.getByRole('button', { name: 'Crear contrato' })).toBeDisabled()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar solicitudes' }))
    expect(dobles.refetchSolicitudes).toHaveBeenCalledTimes(1)
    expect(dobles.refetch).not.toHaveBeenCalled()
    dobles.solicitudesError = false
    vista.rerender(<Arnes />)
    expect(screen.getByRole('button', { name: 'Crear contrato' })).toBeEnabled()
  })

  it('un error al refrescar conserva el motivo y el foco del borrador', async () => {
    const user = userEvent.setup()
    const vista = render(<Arnes />)
    await user.click(screen.getByRole('button', { name: 'Solicitar tasa superior' }))
    await user.type(screen.getByLabelText('Motivo comercial'), 'Cliente referido')
    dobles.solicitudesError = true
    vista.rerender(<Arnes />)
    expect(screen.getByLabelText('Motivo comercial')).toHaveValue('Cliente referido')
    expect(screen.getByLabelText('Motivo comercial')).toHaveFocus()
    expect(screen.getByRole('button', { name: 'Enviar a Gerencia' })).toBeDisabled()
  })

  it('con un tope de Gerencia, ofrece aceptar o declinar (D6)', async () => {
    dobles.solicitudes = [solicitud({ estado: 'aprobada_con_tope', estado_efectivo: 'aprobada_con_tope', tasa_maxima_autorizada: 16, resuelta_por: 'g', resolutor_nombre: 'GERENCIA', motivo_resolucion: 'Mercado a 16' })]
    dobles.responder.mockResolvedValue(solicitud({ estado: 'aceptada_por_analista', estado_efectivo: 'aceptada_por_analista', tasa_maxima_autorizada: 16 }))
    render(<Arnes />)
    expect(screen.getByRole('status')).toHaveTextContent(/ofrece hasta 16%/)
    fireEvent.click(screen.getByRole('button', { name: /Aceptar y continuar/ }))
    await waitFor(() => expect(dobles.responder).toHaveBeenCalledWith({ solicitudId: 's-1', acepta: true, motivo: null }))
  })

  it('al reasignar el lead identifica al solicitante que debe responder y no permite suplantarlo', () => {
    dobles.solicitudes = [solicitud({ cliente_id: null, lead_id: 'lead-1', es_mia: false, solicitante_nombre: 'ANA', estado: 'aprobada_con_tope', estado_efectivo: 'aprobada_con_tope', tasa_maxima_autorizada: 16 })]
    const rango = vi.fn()
    render(<TasaPolitica clienteId="" leadId="lead-1" categoria="nuevo" contratoOrigenId={null} intencion={INTENCION} tasa="15" onTasaChange={vi.fn()} onRangoChange={rango} demo={false} />)
    expect(rango).toHaveBeenLastCalledWith(expect.objectContaining({ bloqueoContrato: 'ANA debe aceptar o declinar el tope desde su bandeja de tasas antes de convertir el lead.' }))
    expect(screen.getByRole('button', { name: /Aceptar/ })).toBeDisabled()
    expect(screen.getByRole('button', { name: /No cerrar a ese tope/ })).toBeDisabled()
    expect(dobles.responder).not.toHaveBeenCalled()
  })

  it('con autorización vigente, habilita el input entre la base y la tasa autorizada y arranca en el máximo', async () => {
    dobles.solicitudes = [solicitud({ estado: 'aprobada', estado_efectivo: 'aprobada', tasa_maxima_autorizada: 17, resuelta_por: 'g' })]
    render(<Arnes />)
    const input = screen.getByLabelText('Tasa anual (%)') as HTMLInputElement
    await waitFor(() => expect(input).toBeEnabled())
    await waitFor(() => expect(screen.getByTestId('tasa')).toHaveTextContent('17'))
    expect(screen.getByText(/Autorizada hasta 17%/)).toBeInTheDocument()
    await waitFor(() => expect(screen.getByTestId('rango')).toHaveTextContent('autorizada:15-17'))
    // Fuera de [base, tope]: el campo se marca inválido y la ayuda dice el rango (no se pisa lo que teclea).
    fireEvent.change(input, { target: { value: '18' } })
    expect(input).toHaveAttribute('aria-invalid', 'true')
    expect(screen.getByText(/La tasa debe estar entre 15% y 17%/)).toBeInTheDocument()
    fireEvent.change(input, { target: { value: '16' } })
    expect(input).not.toHaveAttribute('aria-invalid')
  })

  it('Enter en «Tasa solicitada» envía la solicitud y NO dispara el submit del formulario del contrato', async () => {
    dobles.solicitar.mockResolvedValue(solicitud())
    render(<Arnes />)
    fireEvent.click(screen.getByRole('button', { name: 'Solicitar tasa superior' }))
    const pedida = screen.getByLabelText('Tasa solicitada (%)')
    fireEvent.change(pedida, { target: { value: '17' } })
    fireEvent.change(screen.getByLabelText('Motivo comercial'), { target: { value: 'Cliente referido' } })
    // fireEvent devuelve false cuando el handler hizo preventDefault: el <form> del contrato no llegaría a enviarse.
    expect(fireEvent.keyDown(pedida, { key: 'Enter' })).toBe(false)
    await waitFor(() => expect(dobles.solicitar).toHaveBeenCalledTimes(1))
  })

  it('en corrección con autorización viva NO sube la tasa sola: conserva la persistida y habilita el rango', async () => {
    dobles.resolucion = { data: undefined, isPending: false, isError: false }
    dobles.solicitudes = [solicitud({ estado: 'aprobada', estado_efectivo: 'aprobada', tasa_maxima_autorizada: 17, resuelta_por: 'g' })]
    render(<Arnes correccion={{ tasaActual: 16 }} tasaInicial="16" />)
    const input = screen.getByLabelText('Tasa anual (%)') as HTMLInputElement
    await waitFor(() => expect(screen.getByTestId('rango')).toHaveTextContent('autorizada:16-17'))
    expect(input).toBeEnabled()
    expect(input).not.toHaveAttribute('readonly')
    expect(screen.getByTestId('tasa')).toHaveTextContent('16')
  })

  it('un rechazo reciente de Gerencia se dice y se puede volver a pedir', () => {
    dobles.solicitudes = [solicitud({ estado: 'rechazada', estado_efectivo: 'rechazada', vigente: false, resuelta_por: 'g', resuelta_en: new Date().toISOString(), motivo_resolucion: 'No a ese nivel' })]
    render(<Arnes />)
    expect(screen.getByRole('status')).toHaveTextContent(/rechazó tu solicitud de 17%: No a ese nivel/)
    expect(screen.getByRole('button', { name: 'Solicitar tasa superior' })).toBeInTheDocument()
    expect(screen.getByLabelText('Tasa anual (%)')).toHaveAttribute('readonly')
  })

  it('cancelar la solicitud devuelve el foco al botón que la abrió (a11y)', () => {
    render(<Arnes />)
    fireEvent.click(screen.getByRole('button', { name: 'Solicitar tasa superior' }))
    fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }))
    expect(screen.getByRole('button', { name: 'Solicitar tasa superior' })).toHaveFocus()
  })

  it('una autorización para OTRA intención (capital distinto) no habilita el input, avisa y deja pedir para esta', () => {
    dobles.solicitudes = [solicitud({ estado: 'aprobada', estado_efectivo: 'aprobada', tasa_maxima_autorizada: 17, capital: 99999, resuelta_por: 'g' })]
    render(<Arnes />)
    expect(screen.getByLabelText('Tasa anual (%)')).toHaveAttribute('readonly')
    expect(screen.getByRole('status')).toHaveTextContent(/otros datos/)
    expect(screen.getByRole('button', { name: 'Solicitar tasa superior' })).toBeInTheDocument()
  })

  it('una autorización con vence_en ya pasado no habilita nada (caducidad en el cliente)', () => {
    dobles.solicitudes = [solicitud({ estado: 'aprobada', estado_efectivo: 'aprobada', tasa_maxima_autorizada: 17, resuelta_por: 'g', vigente: true, vence_en: '2020-01-01T00:00:00Z' })]
    render(<Arnes />)
    expect(screen.getByLabelText('Tasa anual (%)')).toHaveAttribute('readonly')
    expect(screen.queryByText(/Autorizada hasta/)).toBeNull()
  })

  it('en demo: base fija 15, sin solicitudes ni servidor', () => {
    dobles.resolucion = { data: undefined, isPending: false, isError: false }
    render(<Arnes demo />)
    expect(screen.getByLabelText('Tasa anual (%)')).toHaveAttribute('readonly')
    expect(screen.getByText(/Demo: la política fija 15%/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Solicitar tasa superior' })).toBeNull()
  })

  it('en corrección: la base es la tasa vigente del contrato y no se consulta el núcleo', async () => {
    dobles.resolucion = { data: undefined, isPending: false, isError: false }
    render(<Arnes correccion={{ tasaActual: 18 }} />)
    await waitFor(() => expect(screen.getByTestId('tasa')).toHaveTextContent('18'))
    expect(screen.getByLabelText('Tasa anual (%)')).toHaveAttribute('readonly')
    expect(screen.getByText(/Tasa vigente del contrato: 18%/)).toBeInTheDocument()
    // Cambiar la tasa de un contrato exige autorización: también se puede pedir desde la corrección.
    expect(screen.getByRole('button', { name: 'Solicitar tasa superior' })).toBeInTheDocument()
  })
})

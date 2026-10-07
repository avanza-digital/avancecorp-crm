import { useState } from 'react'
import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest'
import type { SolicitudTasa } from '@/data/crm-api'

const dobles = vi.hoisted(() => ({
  modo: 'enforcement', minimo: 0.01, base: 18, solicitudes: [] as SolicitudTasa[],
  solicitar: vi.fn(), responder: vi.fn(),
}))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }))
vi.mock('@/data/crm-queries', () => ({
  usePoliticaRentabilidad: () => ({}),
  useResolucionTasa: () => ({ data: {
    tasa_base: dobles.base, tasa_minima_sin_autorizacion: dobles.minimo, regla: 'heredada_upgrade',
    contrato_origen: { id: 'origen-1', numero_contrato: '2026-01-000123', tasa_anual: dobles.base },
    politica: { modo: dobles.modo, tope_tecnico: 25 }, observacion_sin_aprobacion: true,
  } }),
  useSolicitudesTasa: () => ({ data: dobles.solicitudes }),
  useSolicitarTasa: () => ({ mutateAsync: dobles.solicitar, isPending: false }),
  useResponderTopeTasa: () => ({ mutateAsync: dobles.responder, isPending: false }),
}))
const { TasaPolitica } = await import('./tasa-politica')
const intencion = { capital: 10000, moneda: 'PEN' as const, modalidad: 'mensual' as const,
  tipo_interes: 'simple' as const, fecha_inicio: '2026-10-07', fecha_vencimiento: '2027-10-07' }

function solicitud(estado: SolicitudTasa['estado_efectivo'] = 'pendiente'): SolicitudTasa {
  return {
    id: 'solicitud-upgrade', estado, estado_efectivo: estado, vigente: true, categoria: 'upgrade',
    cliente_id: 'cliente-1', cliente_nombre: 'CLIENTE SINTETICO', contrato_origen_id: 'origen-1',
    contrato_origen_numero: '2026-01-000123', producto_condicion_id: null, ...intencion,
    tasa_base: 18, regla_base: 'heredada_upgrade', tasa_solicitada: 20,
    tasa_maxima_autorizada: estado === 'aprobada' ? 20 : null, motivo: 'Nuevo aporte del cliente',
    motivo_resolucion: null, motivo_analista: null, prioridad_bandeja: false, contratos_previos: 1,
    solicitada_por: 'analista', solicitante_nombre: 'ANALISTA', solicitada_en: '2026-10-07T10:00:00Z',
    vence_en: '2026-10-14T10:00:00Z', resuelta_por: null, resolutor_nombre: null, resuelta_en: null,
    respondida_por_analista_en: null, contrato_id: null, es_mia: true, puede_resolver: false, puede_responder: false,
  }
}

function Upgrade({ inicial = '', categoria = 'upgrade' }: { inicial?: string; categoria?: 'upgrade' | 'renovacion' }) {
  const [tasa, setTasa] = useState(inicial)
  const [rango, setRango] = useState('')
  const [bloqueo, setBloqueo] = useState<string | null>(null)
  return <>
    <TasaPolitica clienteId="cliente-1" categoria={categoria} contratoOrigenId="origen-1"
      intencion={intencion} tasa={tasa} onTasaChange={setTasa} demo={false}
      onRangoChange={r => { setRango(`${r.modo}:${r.minimo}-${r.maximo}`); setBloqueo(r.bloqueoContrato) }} />
    <span data-testid="rango">{rango}</span>
    <button disabled={!!bloqueo}>Continuar</button>
  </>
}

describe('Tasa del nuevo upgrade y configuración de solicitudes', () => {
  beforeEach(() => {
    vi.setSystemTime(new Date('2026-10-07T16:00:00Z'))
    dobles.modo = 'enforcement'; dobles.minimo = 0.01; dobles.base = 18; dobles.solicitudes = []
    dobles.solicitar.mockReset(); dobles.responder.mockReset()
  })
  afterEach(() => vi.useRealTimers())

  it('precarga la referencia, permite una tasa menor y mantiene visible la solicitud superior', () => {
    render(<Upgrade />)
    const tasa = screen.getByLabelText('Tasa anual (%)')
    expect(tasa).toHaveValue('18')
    expect(screen.getByText(/Tasa de referencia:/)).toHaveTextContent('18% · contrato 2026-01-000123')
    fireEvent.change(tasa, { target: { value: '16,5' } })
    expect(tasa).toHaveValue('16,5')
    expect(tasa).not.toHaveAttribute('aria-invalid', 'true')
    expect(screen.getByTestId('rango')).toHaveTextContent('base:0.01-18')
    expect(screen.getByRole('button', { name: 'Solicitar tasa superior' })).toBeVisible()
    expect(dobles.solicitar).not.toHaveBeenCalled()
  })

  it('conserva la tasa inferior de un borrador', () => {
    render(<Upgrade inicial="16" />)
    expect(screen.getByLabelText('Tasa anual (%)')).toHaveValue('16')
  })

  it('solicita desde el upgrade con su origen, capital y plazo, y continúa tras la aprobación', async () => {
    const user = userEvent.setup()
    dobles.solicitar.mockResolvedValue(solicitud())
    const vista = render(<Upgrade />)
    await user.clear(screen.getByLabelText('Tasa anual (%)'))
    await user.type(screen.getByLabelText('Tasa anual (%)'), '20')
    await user.click(screen.getByRole('button', { name: 'Solicitar tasa superior' }))
    expect(screen.getByLabelText('Tasa solicitada (%)')).toHaveValue('20')
    await user.type(screen.getByLabelText('Motivo comercial'), 'Nuevo aporte del cliente')
    await user.click(screen.getByRole('button', { name: 'Enviar a Gerencia' }))
    expect(dobles.solicitar).toHaveBeenCalledWith({
      intencion: { ...intencion, cliente_id: 'cliente-1', categoria: 'upgrade', contrato_origen_id: 'origen-1', producto_condicion_id: null },
      tasaSolicitada: 20, motivo: 'Nuevo aporte del cliente',
    })
    await waitFor(() => expect(screen.getByRole('button', { name: 'Continuar' })).toBeDisabled())
    dobles.solicitudes = [solicitud('aprobada')]
    vista.rerender(<Upgrade />)
    await waitFor(() => expect(screen.getByTestId('rango')).toHaveTextContent('autorizada:0.01-20'))
    expect(screen.getByLabelText('Tasa anual (%)')).toHaveValue('20')
    expect(screen.getByRole('button', { name: 'Continuar' })).toBeEnabled()
  })

  it.each(['pendiente', 'aprobada', 'aprobada_con_tope'] as const)('desactivar libera la tasa con solicitud %s sin enviar ni consumir otra', (estado) => {
    dobles.modo = 'observacion'; dobles.solicitudes = [solicitud(estado)]
    render(<Upgrade />)
    expect(screen.getByText('Solicitudes desactivadas · tasa libre')).toBeVisible()
    const tasa = screen.getByLabelText('Tasa anual (%)')
    for (const valor of ['16', '22']) {
      fireEvent.change(tasa, { target: { value: valor } })
      expect(tasa).not.toHaveAttribute('aria-invalid', 'true')
    }
    expect(screen.getByTestId('rango')).toHaveTextContent('observacion:0.01-25')
    expect(screen.getByRole('button', { name: 'Continuar' })).toBeEnabled()
    expect(screen.queryByRole('button', { name: 'Solicitar tasa superior' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Aceptar y continuar' })).not.toBeInTheDocument()
    expect(dobles.solicitar).not.toHaveBeenCalled(); expect(dobles.responder).not.toHaveBeenCalled()
  })

  it.each(['0', '-1', '25.01', '16.345'])('libre mantiene inválida la tasa %s', (valor) => {
    dobles.modo = 'observacion'
    render(<Upgrade />)
    fireEvent.change(screen.getByLabelText('Tasa anual (%)'), { target: { value: valor } })
    expect(screen.getByLabelText('Tasa anual (%)')).toHaveAttribute('aria-invalid', 'true')
  })

  it('reactivar mantiene lo escrito y vuelve a exigir autorización', () => {
    dobles.modo = 'observacion'
    const vista = render(<Upgrade inicial="22" />)
    dobles.modo = 'enforcement'
    vista.rerender(<Upgrade inicial="22" />)
    expect(screen.getByLabelText('Tasa anual (%)')).toHaveValue('22')
    expect(screen.getByLabelText('Tasa anual (%)')).toHaveAttribute('aria-invalid', 'true')
    expect(screen.getByRole('button', { name: 'Solicitar tasa superior' })).toBeVisible()
  })

  it('una pendiente vuelve a bloquear al reactivar, incluso con tasa menor', () => {
    dobles.solicitudes = [solicitud()]
    const vista = render(<Upgrade inicial="16" />)
    expect(screen.getByRole('button', { name: 'Continuar' })).toBeDisabled()
    dobles.modo = 'observacion'; vista.rerender(<Upgrade inicial="16" />)
    expect(screen.getByRole('button', { name: 'Continuar' })).toBeEnabled()
    dobles.modo = 'enforcement'; vista.rerender(<Upgrade inicial="16" />)
    expect(screen.getByLabelText('Tasa anual (%)')).toHaveValue('16')
    expect(screen.getByRole('button', { name: 'Continuar' })).toBeDisabled()
  })

  it('un servidor anterior mantiene su mínimo hasta instalar la ampliación', () => {
    dobles.minimo = 18
    render(<Upgrade />)
    expect(screen.getByLabelText('Tasa anual (%)')).toHaveAttribute('readonly')
    expect(screen.getByTestId('rango')).toHaveTextContent('base:18-18')
  })

  it('la ampliación no cambia la tasa mínima de renovaciones', () => {
    render(<Upgrade categoria="renovacion" />)
    expect(screen.getByTestId('rango')).toHaveTextContent('base:18-18')
  })
})

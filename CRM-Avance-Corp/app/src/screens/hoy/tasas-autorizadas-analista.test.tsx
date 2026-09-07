import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { SolicitudTasa } from '@/data/crm-api'

const dobles = vi.hoisted(() => ({
  data: [] as SolicitudTasa[],
  responder: vi.fn(),
  yo: { id: 'v-1', rol: 'vendedor', demo: false } as { id: string; rol: string; demo: boolean },
}))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('@/data/crm-queries', () => ({
  useSolicitudesTasa: () => ({ data: dobles.data, isPending: false, isError: false, refetch: vi.fn() }),
  useResponderTopeTasa: () => ({ mutateAsync: dobles.responder, isPending: false }),
}))
const { TasasAutorizadasAnalistaPanel } = await import('./tasas-autorizadas-analista')

function solicitud(sobre: Partial<SolicitudTasa> = {}): SolicitudTasa {
  return {
    id: 's-1', estado: 'pendiente', estado_efectivo: 'pendiente', vigente: true, categoria: 'nuevo', cliente_id: 'cli-1', cliente_nombre: 'ANA TORRES',
    contrato_origen_id: null, contrato_origen_numero: null, producto_condicion_id: null, capital: 20000, moneda: 'PEN', modalidad: 'mensual', tipo_interes: 'simple',
    fecha_inicio: '2026-10-01', fecha_vencimiento: '2027-10-01', tasa_base: 15, regla_base: 'primera_inversion', tasa_solicitada: 18,
    tasa_maxima_autorizada: null, motivo: 'Referido', motivo_resolucion: null, motivo_analista: null, prioridad_bandeja: false, contratos_previos: 0,
    solicitada_por: 'v-1', solicitante_nombre: 'YO', solicitada_en: '2026-09-06T10:00:00Z', vence_en: '2026-09-13T10:00:00Z',
    resuelta_por: null, resolutor_nombre: null, resuelta_en: null, respondida_por_analista_en: null, contrato_id: null,
    es_mia: true, puede_resolver: false, puede_responder: false, ...sobre,
  }
}

describe('TasasAutorizadasAnalistaPanel (aviso R3)', () => {
  beforeEach(() => { dobles.data = []; dobles.responder.mockReset(); dobles.yo = { id: 'v-1', rol: 'vendedor', demo: false } })

  it('sin solicitudes propias vivas no pinta nada', () => {
    dobles.data = [solicitud({ es_mia: false })]
    const { container } = render(<TasasAutorizadasAnalistaPanel />)
    expect(container).toBeEmptyDOMElement()
  })

  it('en demo no pinta nada', () => {
    dobles.yo = { ...dobles.yo, demo: true }
    dobles.data = [solicitud()]
    const { container } = render(<TasasAutorizadasAnalistaPanel />)
    expect(container).toBeEmptyDOMElement()
  })

  it('muestra pendiente, autorizada y con tope; el tope se acepta desde aquí', async () => {
    dobles.data = [
      solicitud(),
      solicitud({ id: 's-2', estado: 'aprobada', estado_efectivo: 'aprobada', tasa_maxima_autorizada: 18, cliente_nombre: 'LUIS' }),
      solicitud({ id: 's-3', estado: 'aprobada_con_tope', estado_efectivo: 'aprobada_con_tope', tasa_maxima_autorizada: 16, cliente_nombre: 'ROSA' }),
    ]
    dobles.responder.mockResolvedValue(solicitud({ id: 's-3', estado: 'aceptada_por_analista', estado_efectivo: 'aceptada_por_analista', tasa_maxima_autorizada: 16 }))
    render(<TasasAutorizadasAnalistaPanel />)
    const lista = screen.getByRole('list', { name: 'Solicitudes de tasa en curso' })
    expect(lista.querySelectorAll('li')).toHaveLength(3)
    expect(lista).toHaveTextContent(/Pendiente de Gerencia/)
    expect(lista).toHaveTextContent(/Autorizada hasta 18%/)
    expect(lista).toHaveTextContent(/Gerencia ofrece hasta 16%/)
    fireEvent.click(screen.getByRole('button', { name: /Aceptar y continuar/ }))
    await waitFor(() => expect(dobles.responder).toHaveBeenCalledWith({ solicitudId: 's-3', acepta: true, motivo: null }))
  })

  it('un rechazo reciente se muestra con su motivo; uno viejo o ajeno no', () => {
    const hace2dias = new Date(Date.now() - 2 * 86_400_000).toISOString()
    const hace30dias = new Date(Date.now() - 30 * 86_400_000).toISOString()
    dobles.data = [
      solicitud({ id: 'r-1', estado: 'rechazada', estado_efectivo: 'rechazada', vigente: false, resuelta_en: hace2dias, motivo_resolucion: 'No a ese nivel', cliente_nombre: 'ANA' }),
      solicitud({ id: 'r-2', estado: 'rechazada', estado_efectivo: 'rechazada', vigente: false, resuelta_en: hace30dias, cliente_nombre: 'VIEJA' }),
      solicitud({ id: 'r-3', estado: 'rechazada', estado_efectivo: 'rechazada', vigente: false, resuelta_en: hace2dias, es_mia: false, cliente_nombre: 'AJENA' }),
    ]
    render(<TasasAutorizadasAnalistaPanel />)
    const lista = screen.getByRole('list', { name: 'Solicitudes de tasa en curso' })
    expect(lista.querySelectorAll('li')).toHaveLength(1)
    expect(lista).toHaveTextContent(/Rechazada por Gerencia/)
    expect(lista).toHaveTextContent(/«No a ese nivel»/)
    expect(lista).toHaveTextContent(/queda en la base 15%/)
    expect(lista).not.toHaveTextContent(/VIEJA|AJENA/)
  })

  it('tras responder la última, el panel se queda (no deja el foco en body) y lo dice', async () => {
    dobles.data = [solicitud({ id: 's-3', estado: 'aprobada_con_tope', estado_efectivo: 'aprobada_con_tope', tasa_maxima_autorizada: 16 })]
    dobles.responder.mockResolvedValue(solicitud({ id: 's-3', estado: 'declinada_por_analista', estado_efectivo: 'declinada_por_analista', vigente: false }))
    const { rerender } = render(<TasasAutorizadasAnalistaPanel />)
    fireEvent.click(screen.getByRole('button', { name: /No cerrar a ese tope/ }))
    await waitFor(() => expect(dobles.responder).toHaveBeenCalledTimes(1))
    dobles.data = []
    rerender(<TasasAutorizadasAnalistaPanel />)
    expect(screen.getByTestId('tasas-autorizadas-analista')).toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent('Sin solicitudes de tasa en curso.')
  })
})

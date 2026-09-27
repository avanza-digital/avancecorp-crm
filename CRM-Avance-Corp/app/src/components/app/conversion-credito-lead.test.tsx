import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { ConversionEstado } from '@/lib/conversion-estado'
import { ConversionCreditoLead } from './conversion-credito-lead'

const { consulta, reintentar } = vi.hoisted(() => ({ consulta: vi.fn(), reintentar: vi.fn() }))
vi.mock('@/data/crm-queries', () => ({ useConversionEstado: consulta }))
const leadId = '11111111-1111-4111-8111-111111111111'
const acreditada: ConversionEstado = {
  version: 1, lead_id: leadId, estado: 'acreditada',
  mensaje: 'Conversión acreditada en el mes de cierre comercial.',
  fecha_comercial: '2026-09-17', periodo_comercial: '2026-09-01',
  plazo_hasta: '2026-10-11T05:00:00Z', confirmado_en: '2026-09-21T18:15:50Z',
  vinculado_en: '2026-09-26T22:00:00Z',
}
beforeEach(() => {
  vi.clearAllMocks()
  consulta.mockReturnValue({ data: acreditada, isError: false, isFetching: false, refetch: reintentar })
})
describe('crédito mensual explicado por servidor', () => {
  it('presenta la decisión y fecha del servidor sin calcular con el reloj actual', () => {
    render(<ConversionCreditoLead leadId={leadId} />)
    expect(consulta).toHaveBeenCalledWith(leadId)
    expect(screen.getByText(acreditada.mensaje)).toBeInTheDocument()
    expect(screen.getByText(/Fecha de cierre comercial:.*2026/)).toBeInTheDocument()
  })
  it('muestra pendiente sin fuente, como los legados no conciliados de producción', () => {
    consulta.mockReturnValue({ data: { ...acreditada, estado: 'pendiente_fuente', fecha_comercial: null,
      mensaje: 'Pendiente, sin crédito: falta acreditar una operación confirmada y su vínculo.' }, isError: false })
    render(<ConversionCreditoLead leadId={leadId} />)
    expect(screen.getByText(/Pendiente, sin crédito/)).toBeInTheDocument()
    expect(screen.queryByText(/Fecha de cierre comercial/)).not.toBeInTheDocument()
    expect(screen.queryByText(acreditada.mensaje)).not.toBeInTheDocument()
  })
  it('no confunde carga con falta de crédito', () => {
    consulta.mockReturnValue({ data: undefined, isError: false })
    render(<ConversionCreditoLead leadId={leadId} />)
    expect(screen.getByRole('status')).toHaveTextContent('Consultando crédito de conversión')
    expect(screen.queryByText(/sin crédito/)).not.toBeInTheDocument()
  })
  it('prioriza un error incluso con dato cacheado y permite reintentar', async () => {
    consulta.mockReturnValue({ data: acreditada, isError: true, isFetching: false, refetch: reintentar })
    render(<ConversionCreditoLead leadId={leadId} />)
    expect(screen.queryByText(acreditada.mensaje)).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Reintentar consulta de conversión' }))
    expect(reintentar).toHaveBeenCalledOnce()
  })
})

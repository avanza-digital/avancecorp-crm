// Anular un cierre de AVANCE cuando la venta cambia mientras se anula (PT409).
//
// Bloque 2.6 (20261009210000): la puerta toma el cerrojo del mes de la venta y, si mientras esperaba cambió la
// acreditación de esa venta, responde PT409 sin escribir nada. Basta con reintentar, y la pantalla tiene que decirlo
// con un texto claro, no con «No se pudo anular el cierre». Aquí corren el diálogo, el gancho de TanStack y la
// traducción de `crm-api` REALES; solo se sustituye el cliente de Supabase.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { toast } from 'sonner'
import { StoreDataContext } from '@/lib/store-context'
import type { StoreDataApi } from '@/lib/store'
import type { Lead } from '@/lib/tipos'
import { AnularCierreAvanceDialog } from './anular-cierre-avance'

const mock = vi.hoisted(() => ({ rpc: vi.fn() }))
vi.mock('@/lib/supabase', () => ({ sb: { schema: () => ({ rpc: (...args: unknown[]) => mock.rpc(...args) }) } }))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() } }))

const LEAD: Lead = {
  id: '33333333-3333-4333-8333-333333333333',
  nombre_completo: 'ANA CIERRE PRUEBA',
  telefono: '+51987654321',
  correo: 'ana@prueba.invalid',
  etapa: 'convertido',
  origen: 'landing',
  monto_estimado: 10_000,
  moneda: 'PEN',
  categoria_interes: null,
  vendedor_id: 'vendedor-1',
  vendedor_nombre: 'ANALISTA PRUEBA',
  asignado_supervisor_id: null,
  creado_en: '2026-07-17T12:00:00.000Z',
  activo: true,
  dni: null,
  distrito: null,
  nota: null,
  motivo_descarte: null,
}
const MOTIVO = 'Cierre registrado con datos que no corresponden'

function montar() {
  const recargar = vi.fn(async () => true)
  const onCerrar = vi.fn()
  const api = { anularCierreAvance: vi.fn(() => ({ ok: true })), recargar } as unknown as StoreDataApi
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  render(
    <QueryClientProvider client={qc}>
      <StoreDataContext.Provider value={api}>
        <AnularCierreAvanceDialog lead={LEAD} demo={false} onCerrar={onCerrar} />
      </StoreDataContext.Provider>
    </QueryClientProvider>,
  )
  return { recargar, onCerrar, user: userEvent.setup() }
}

describe('Anular un cierre de Avance: la venta cambió mientras se anulaba (PT409)', () => {
  beforeEach(() => {
    vi.spyOn(console, 'error').mockImplementation(() => {})
  })

  it('dice con un texto claro que se reintente, no el error genérico, y no da el cierre por anulado', async () => {
    mock.rpc.mockResolvedValue({
      data: null,
      error: { code: 'PT409', message: 'La acreditacion cambio durante la anulacion; vuelve a intentar', details: null, hint: null },
    })
    const { recargar, onCerrar, user } = montar()

    await user.type(screen.getByLabelText('Motivo de la anulación'), MOTIVO)
    await user.click(screen.getByRole('button', { name: 'Anular cierre' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('La venta cambió mientras la anulabas. Vuelve a intentarlo.')
    expect(screen.queryByText('No se pudo anular el cierre.')).not.toBeInTheDocument()
    expect(mock.rpc).toHaveBeenCalledExactlyOnceWith('anular_cierre_avance', { p_lead_id: LEAD.id, p_motivo: MOTIVO })
    expect(toast.success).not.toHaveBeenCalled()
    expect(recargar).not.toHaveBeenCalled()
    expect(onCerrar).not.toHaveBeenCalled()
    // El motivo sigue escrito y sin marca de inválido: reintentar es un clic.
    expect(screen.getByLabelText('Motivo de la anulación')).toHaveValue(MOTIVO)
    expect(screen.getByLabelText('Motivo de la anulación')).toHaveAttribute('aria-invalid', 'false')
  })
})

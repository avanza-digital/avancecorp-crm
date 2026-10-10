// Anular un cierre en COOPERATIVA cuando la venta cambia mientras se anula (PT409).
//
// Bloque 2.6 (20261009210000): si la acreditación de la venta cambia mientras la puerta espera el cerrojo de su mes, el
// servidor responde PT409 sin escribir nada. Basta con reintentar, y la revisión del mes tiene que decirlo con un texto
// claro, no con «No se pudo anular el cierre externo». Aquí corren la revisión, el gancho de TanStack y la traducción
// de `crm-api` REALES; solo se sustituyen el cliente de Supabase y la lectura de la lista.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { toast } from 'sonner'
import { StoreDataContext } from '@/lib/store-context'
import type { StoreDataApi } from '@/lib/store'

const mock = vi.hoisted(() => ({ rpc: vi.fn(), consultaCierres: vi.fn() }))
vi.mock('@/lib/supabase', () => ({ sb: { schema: () => ({ rpc: (...args: unknown[]) => mock.rpc(...args) }) } }))
vi.mock('@/data/crm-queries', async (original) => ({
  ...(await original<typeof import('@/data/crm-queries')>()),
  useCierresExternos: mock.consultaCierres,
}))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: { rol: 'gerencia' } }) }))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() } }))

const { DesglosePorEmpresa } = await import('./cierres-externos-seccion')

const CIERRE = {
  cierre_id: '44444444-4444-4444-8444-444444444444',
  lead_id: '33333333-3333-4333-8333-333333333333',
  cooperativa: 'qorilazo' as const,
  monto: 10000,
  moneda: 'PEN' as const,
  nombre_completo: 'Cliente Qorilazo Uno',
  documento_tipo: 'DNI' as const,
  documento: '41000001',
  telefono: '+51941001101',
  numero_transaccion: 'OP-77-2026',
  referencia_externa: 'QOR-2026-001',
  vence_en: '2027-09-01',
  nota: 'primera inversion',
  vendedor_id: 'v-a',
  vendedor_nombre: 'Ana Analista',
  creado_en: '2026-08-12T00:00:00.000Z',
  anulado_en: null,
  motivo_anulacion: null,
}
const PAYLOAD = {
  version: 1 as const,
  periodo: '2026-08-01',
  alcance: 'propio' as const,
  cierres: [CIERRE],
  cierres_total: 1,
  cierres_mes: [CIERRE],
  cierres_mes_total: 1,
  totales: [{ cooperativa: 'qorilazo' as const, moneda: 'PEN' as const, capital: 10000, cierres: 1 }],
  por_empresa: [
    { vendedor_id: 'v-a', vendedor_nombre: 'Ana Analista', cooperativa: 'qorilazo' as const, moneda: 'PEN' as const, capital: 10000, cierres: 1 },
  ],
}
const MOTIVO = 'El depósito se digitó dos veces'

describe('Revisión del mes en cooperativas: la venta cambió mientras se anulaba (PT409)', () => {
  beforeEach(() => {
    vi.spyOn(console, 'error').mockImplementation(() => {})
    mock.consultaCierres.mockReturnValue({ data: PAYLOAD, isPending: false, isError: false, error: null, isFetching: false, refetch: vi.fn() })
  })

  it('dice con un texto claro que se reintente, no el error genérico, y no da el cierre por anulado', async () => {
    mock.rpc.mockResolvedValue({
      data: null,
      error: { code: 'PT409', message: 'La acreditacion cambio durante la anulacion; vuelve a intentar', details: null, hint: null },
    })
    const recargar = vi.fn().mockResolvedValue(true)
    const api = { cierresExternos: [], anularCierreExterno: vi.fn(() => ({ ok: true })), recargar } as unknown as StoreDataApi
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
    render(
      <QueryClientProvider client={qc}>
        <StoreDataContext.Provider value={api}>
          <DesglosePorEmpresa demo={false} porVendedor={null} />
        </StoreDataContext.Provider>
      </QueryClientProvider>,
    )
    const user = userEvent.setup()

    await user.click(screen.getByRole('button', { name: 'Ver cierres del mes' }))
    await user.click(await screen.findByRole('button', { name: 'Anular el cierre de Cliente Qorilazo Uno' }))
    await user.type(await screen.findByLabelText('Motivo de la anulación'), MOTIVO)
    await user.click(screen.getByRole('button', { name: 'Anular cierre' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('La venta cambió mientras la anulabas. Vuelve a intentarlo.')
    expect(screen.queryByText('No se pudo anular el cierre externo.')).not.toBeInTheDocument()
    expect(mock.rpc).toHaveBeenCalledExactlyOnceWith('anular_cierre_externo', { p_cierre_id: CIERRE.cierre_id, p_motivo: MOTIVO })
    expect(toast.success).not.toHaveBeenCalled()
    expect(recargar).not.toHaveBeenCalled()
    // La confirmación sigue abierta con el motivo escrito: reintentar es un clic.
    expect(screen.getByLabelText('Motivo de la anulación')).toHaveValue(MOTIVO)
  })
})

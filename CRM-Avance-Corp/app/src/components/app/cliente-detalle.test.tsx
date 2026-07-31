// Ficha de cliente de solo lectura. Estos tests usan React Query REAL y mockean
// únicamente la frontera HTTP: fijan que una cuenta en caché nunca se presente
// como fresca, que el error cierre el acceso al dato y que la demo haga cero red.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Dialog } from '@/components/ui/dialog'
import { crmQueryKeys } from '@/data/crm-queries'
import type { ClienteDetalle as ClienteDetalleDatos } from '@/lib/clientes-tipos'
import * as crmApi from '@/data/crm-api'

vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return {
    ...actual,
    obtenerClienteDetalle: vi.fn(),
  }
})

const { ClienteDetalle } = await import('./cliente-detalle')
const obtenerDetalle = vi.mocked(crmApi.obtenerClienteDetalle)

function detalleBase(over: Partial<ClienteDetalleDatos> = {}): ClienteDetalleDatos {
  return {
    id: 'cli-1',
    nombre_completo: 'CLIENTE PORTAL UNO',
    nombres: 'CLIENTE',
    apellidos: 'PORTAL UNO',
    tipo_documento: 'DNI',
    dni: '45781234',
    correo: 'cliente1@correo.pe',
    telefono: '+51999888777',
    asesor_perfil_id: 'yo',
    creado_por: 'yo',
    creado_en: '2026-07-15T12:00:00.000Z',
    banco: 'BCP',
    tipo_cuenta: 'ahorros',
    numero_cuenta: '19112345678901',
    cci: '00219112345678901234',
    titular_distinto: false,
    beneficiario_nombre: null,
    beneficiario_dni: null,
    banco_usd: 'Interbank',
    tipo_cuenta_usd: 'corriente',
    numero_cuenta_usd: '2003001234567',
    cci_usd: '00320030012345678901',
    titular_distinto_usd: true,
    beneficiario_nombre_usd: 'JUANA PÉREZ DEMO',
    beneficiario_dni_usd: '87654321',
    ...over,
  }
}

function clienteQuery(): QueryClient {
  return new QueryClient({
    defaultOptions: {
      queries: { retry: false, networkMode: 'offlineFirst' },
    },
  })
}

function montar({
  queryClient = clienteQuery(),
  datos,
}: {
  queryClient?: QueryClient
  datos?: ClienteDetalleDatos
} = {}) {
  const onCerrar = vi.fn()
  render(
    <QueryClientProvider client={queryClient}>
      <Dialog open onClose={() => undefined} ariaLabel="Ficha del cliente">
        {datos === undefined
          ? <ClienteDetalle clienteId="cli-1" onCerrar={onCerrar} />
          : <ClienteDetalle clienteId="cli-1" datos={datos} onCerrar={onCerrar} />}
      </Dialog>
    </QueryClientProvider>,
  )
  return { onCerrar, queryClient }
}

beforeEach(() => {
  obtenerDetalle.mockReset()
})

describe('ClienteDetalle — frescura y presentación', () => {
  it('muestra identidad, contacto y las cuentas PEN/USD completas tras una lectura fresca', async () => {
    obtenerDetalle.mockResolvedValue(detalleBase())
    montar()

    expect(await screen.findByText('CLIENTE PORTAL UNO')).toBeInTheDocument()
    expect(screen.getByText('cliente1@correo.pe')).toBeInTheDocument()
    expect(screen.getByText('+51999888777')).toBeInTheDocument()

    const pen = screen.getByRole('region', { name: 'Cuenta para depósitos en soles' })
    expect(within(pen).getByText('BCP')).toBeInTheDocument()
    expect(within(pen).getByText('19112345678901')).toBeInTheDocument()
    expect(within(pen).getByText('00219112345678901234')).toBeInTheDocument()

    const usd = screen.getByRole('region', { name: 'Cuenta para depósitos en dólares' })
    expect(within(usd).getByText('Interbank')).toBeInTheDocument()
    expect(within(usd).getByText('JUANA PÉREZ DEMO')).toBeInTheDocument()
    expect(within(usd).getByText('87654321')).toBeInTheDocument()
  })

  it('no pinta una cuenta cacheada mientras la revalidación de esta apertura sigue pendiente', async () => {
    let resolver!: (detalle: ClienteDetalleDatos) => void
    obtenerDetalle.mockReturnValue(new Promise((resolve) => { resolver = resolve }))
    const queryClient = clienteQuery()
    queryClient.setQueryData(
      crmQueryKeys.clienteDetalle('cli-1'),
      detalleBase({ nombre_completo: 'COPIA CACHEADA', numero_cuenta: 'CUENTA-CACHE-VIEJA' }),
    )

    montar({ queryClient })
    expect(screen.queryByText('COPIA CACHEADA')).not.toBeInTheDocument()
    expect(screen.queryByText('CUENTA-CACHE-VIEJA')).not.toBeInTheDocument()

    resolver(detalleBase({ nombre_completo: 'COPIA FRESCA', numero_cuenta: 'CUENTA-FRESCA' }))
    expect(await screen.findByText('COPIA FRESCA')).toBeInTheDocument()
    expect(screen.getByText('CUENTA-FRESCA')).toBeInTheDocument()
    expect(screen.queryByText('CUENTA-CACHE-VIEJA')).not.toBeInTheDocument()
  })

  it('si falla la revalidación, muestra un error y nunca revela la cuenta cacheada', async () => {
    obtenerDetalle.mockRejectedValue(new crmApi.CrmApiError('No se pudo actualizar la ficha bancaria.', 'SIN_RED'))
    const queryClient = clienteQuery()
    queryClient.setQueryData(
      crmQueryKeys.clienteDetalle('cli-1'),
      detalleBase({ nombre_completo: 'COPIA CACHEADA', numero_cuenta: 'CUENTA-CACHE-VIEJA' }),
    )

    montar({ queryClient })

    expect(await screen.findByRole('alert')).toHaveTextContent('No se pudo actualizar la ficha bancaria.')
    expect(screen.queryByText('COPIA CACHEADA')).not.toBeInTheDocument()
    expect(screen.queryByText('CUENTA-CACHE-VIEJA')).not.toBeInTheDocument()
  })

  it('un fallo de refresh posterior vuelve a cerrar una ficha ya confirmada', async () => {
    obtenerDetalle
      .mockResolvedValueOnce(detalleBase({ numero_cuenta: 'CUENTA-CONFIRMADA' }))
      .mockRejectedValueOnce(new crmApi.CrmApiError('No se pudo refrescar la ficha.', 'SIN_RED'))
    const { queryClient } = montar()
    expect(await screen.findByText('CUENTA-CONFIRMADA')).toBeInTheDocument()

    await act(async () => {
      await queryClient.refetchQueries({ queryKey: crmQueryKeys.clienteDetalle('cli-1'), exact: true })
    })

    expect(await screen.findByRole('alert')).toHaveTextContent('No se pudo refrescar la ficha.')
    expect(screen.queryByText('CUENTA-CONFIRMADA')).not.toBeInTheDocument()
  })

  it('Reintentar mantiene oculto lo viejo y habilita la ficha solo al recibir una copia nueva', async () => {
    const user = userEvent.setup()
    obtenerDetalle
      .mockRejectedValueOnce(new crmApi.CrmApiError('Sin conexión.', 'SIN_RED'))
      .mockResolvedValueOnce(detalleBase({ nombre_completo: 'CLIENTE ACTUALIZADO', numero_cuenta: 'CUENTA-NUEVA' }))
    const queryClient = clienteQuery()
    queryClient.setQueryData(
      crmQueryKeys.clienteDetalle('cli-1'),
      detalleBase({ nombre_completo: 'COPIA CACHEADA', numero_cuenta: 'CUENTA-CACHE-VIEJA' }),
    )
    montar({ queryClient })

    await user.click(await screen.findByRole('button', { name: 'Reintentar' }))

    expect(await screen.findByText('CLIENTE ACTUALIZADO')).toBeInTheDocument()
    expect(screen.getByText('CUENTA-NUEVA')).toBeInTheDocument()
    expect(screen.queryByText('CUENTA-CACHE-VIEJA')).not.toBeInTheDocument()
    expect(obtenerDetalle).toHaveBeenCalledTimes(2)
  })

  it('explica por separado cuando no existe una cuenta PEN ni USD', async () => {
    obtenerDetalle.mockResolvedValue(detalleBase({
      banco: null,
      tipo_cuenta: null,
      numero_cuenta: null,
      cci: null,
      banco_usd: null,
      tipo_cuenta_usd: null,
      numero_cuenta_usd: null,
      cci_usd: null,
      titular_distinto_usd: false,
      beneficiario_nombre_usd: null,
      beneficiario_dni_usd: null,
    }))
    montar()

    await screen.findByText('CLIENTE PORTAL UNO')
    const pen = screen.getByRole('region', { name: 'Cuenta para depósitos en soles' })
    const usd = screen.getByRole('region', { name: 'Cuenta para depósitos en dólares' })
    expect(within(pen).getByText('No registró una cuenta en esta moneda.')).toBeInTheDocument()
    expect(within(usd).getByText('No registró una cuenta en esta moneda.')).toBeInTheDocument()
  })

  it('con datos demo pinta de inmediato, no llama a la API y permite cerrar', async () => {
    const user = userEvent.setup()
    const { onCerrar } = montar({ datos: detalleBase({ nombre_completo: 'CLIENTE FICTICIO DEMO' }) })

    expect(screen.getByText('CLIENTE FICTICIO DEMO')).toBeInTheDocument()
    await waitFor(() => expect(obtenerDetalle).not.toHaveBeenCalled())
    await user.click(screen.getByRole('button', { name: 'Cerrar' }))
    expect(onCerrar).toHaveBeenCalledOnce()
  })
})

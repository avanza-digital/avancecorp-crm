// Ficha de cliente de solo lectura. Estos tests usan React Query REAL y mockean
// únicamente la frontera HTTP: fijan que una cuenta en caché nunca se presente
// como fresca, que el error cierre el acceso al dato y que la demo haga cero red.
// Las cuentas salen de la RPC del ledger (listarCuentasBancariasCliente), NO de
// las columnas embebidas del perfil: ese fue el bug de 2026-08-11 (una cuenta
// registrada al crear un contrato no aparecía en la ficha).
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Dialog } from '@/components/ui/dialog'
import { crmQueryKeys } from '@/data/crm-queries'
import type { ClienteDetalle as ClienteDetalleDatos, CuentaBancariaSeleccionable } from '@/lib/clientes-tipos'
import * as crmApi from '@/data/crm-api'

vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return {
    ...actual,
    obtenerClienteDetalle: vi.fn(),
    listarCuentasBancariasCliente: vi.fn(),
  }
})

const { ClienteDetalle } = await import('./cliente-detalle')
const obtenerDetalle = vi.mocked(crmApi.obtenerClienteDetalle)
const listarCuentas = vi.mocked(crmApi.listarCuentasBancariasCliente)

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

function cuentaRpc(over: Partial<CuentaBancariaSeleccionable> = {}): CuentaBancariaSeleccionable {
  return {
    cuenta_id: 'cta-pen-1',
    moneda: 'PEN',
    banco: 'BCP',
    tipo_cuenta: 'ahorros',
    numero_cuenta: '19112345678901',
    cci: '00219112345678901234',
    titular_distinto: false,
    beneficiario_nombre: null,
    beneficiario_dni: null,
    origen: 'perfil',
    es_cuenta_perfil: false,
    creada_en: '2026-08-04T22:51:09.000Z',
    ...over,
  }
}

/** Responde la RPC por moneda (la ficha pide PEN y USD en paralelo). */
function cuentasPorMoneda(pen: CuentaBancariaSeleccionable[], usd: CuentaBancariaSeleccionable[]) {
  listarCuentas.mockImplementation(async (_clienteId, moneda) => (moneda === 'USD' ? usd : pen))
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
  listarCuentas.mockReset()
  listarCuentas.mockResolvedValue([])
})

describe('ClienteDetalle — frescura y presentación', () => {
  it('muestra identidad y las cuentas que autoriza el servidor, ignorando las columnas embebidas del perfil', async () => {
    // Las columnas embebidas traen sentinelas: si aparecieran, la ficha estaría
    // leyendo la fuente vieja (el bug), no la RPC del ledger.
    obtenerDetalle.mockResolvedValue(detalleBase({
      numero_cuenta: 'EMBEBIDA-PEN-NO-VERSE',
      numero_cuenta_usd: 'EMBEBIDA-USD-NO-VERSE',
    }))
    cuentasPorMoneda(
      [cuentaRpc()],
      [cuentaRpc({
        cuenta_id: 'cta-usd-1',
        moneda: 'USD',
        banco: 'Interbank',
        tipo_cuenta: 'corriente',
        numero_cuenta: '2003001234567',
        cci: '00320030012345678901',
        titular_distinto: true,
        beneficiario_nombre: 'JUANA PÉREZ DEMO',
        beneficiario_dni: '87654321',
        origen: 'contrato',
      })],
    )
    montar()

    expect(await screen.findByText('CLIENTE PORTAL UNO')).toBeInTheDocument()
    expect(screen.getByText('cliente1@correo.pe')).toBeInTheDocument()
    expect(screen.getByText('+51999888777')).toBeInTheDocument()

    const pen = await screen.findByRole('region', { name: 'Cuenta para depósitos en soles' })
    expect(within(pen).getByText('BCP')).toBeInTheDocument()
    expect(within(pen).getByText('19112345678901')).toBeInTheDocument()
    expect(within(pen).getByText('00219112345678901234')).toBeInTheDocument()

    const usd = screen.getByRole('region', { name: 'Cuenta para depósitos en dólares' })
    expect(within(usd).getByText('Interbank')).toBeInTheDocument()
    expect(within(usd).getByText('JUANA PÉREZ DEMO')).toBeInTheDocument()
    expect(within(usd).getByText('87654321')).toBeInTheDocument()

    expect(screen.queryByText('EMBEBIDA-PEN-NO-VERSE')).not.toBeInTheDocument()
    expect(screen.queryByText('EMBEBIDA-USD-NO-VERSE')).not.toBeInTheDocument()
  })

  it('ESTADO DE PRODUCCIÓN: cliente legacy sin nombres separados y cuenta USD registrada al crear un contrato', async () => {
    // Réplica exacta del caso ORMESINDA JULCA (2026-08-11): nombres/apellidos
    // NULL, casillas USD del perfil vacías, y la cuenta USD SOLO en el ledger
    // (origen 'contrato'). Antes: «—» en nombres y «No registró una cuenta».
    obtenerDetalle.mockResolvedValue(detalleBase({
      nombre_completo: 'ORMESINDA JULCA',
      nombres: null,
      apellidos: null,
      banco_usd: null,
      tipo_cuenta_usd: null,
      numero_cuenta_usd: null,
      cci_usd: null,
      titular_distinto_usd: false,
      beneficiario_nombre_usd: null,
      beneficiario_dni_usd: null,
    }))
    cuentasPorMoneda(
      [cuentaRpc()],
      [cuentaRpc({
        cuenta_id: 'cta-usd-bbva',
        moneda: 'USD',
        banco: 'BBVA',
        tipo_cuenta: 'corriente',
        numero_cuenta: '72728282828282',
        cci: '27273827282828282828',
        origen: 'contrato',
        creada_en: '2026-08-11T19:36:47.000Z',
      })],
    )
    montar()

    const usd = await screen.findByRole('region', { name: 'Cuenta para depósitos en dólares' })
    expect(within(usd).getByText('BBVA')).toBeInTheDocument()
    expect(within(usd).getByText('72728282828282')).toBeInTheDocument()
    expect(within(usd).getByText('Registrada el')).toBeInTheDocument()
    expect(within(usd).queryByText('No registró una cuenta en esta moneda.')).not.toBeInTheDocument()

    expect(screen.getByText('Nombres y apellidos')).toBeInTheDocument()
    // El nombre aparece en el título del diálogo Y en datos personales.
    expect(screen.getAllByText('ORMESINDA JULCA').length).toBeGreaterThanOrEqual(2)
    expect(screen.queryByText('Nombres')).not.toBeInTheDocument()
    expect(screen.queryByText('Apellidos')).not.toBeInTheDocument()
  })

  it('varias cuentas activas de la misma moneda se listan todas', async () => {
    obtenerDetalle.mockResolvedValue(detalleBase())
    cuentasPorMoneda([], [
      cuentaRpc({ cuenta_id: 'cta-usd-1', moneda: 'USD', banco: 'BBVA', numero_cuenta: '72728282828282' }),
      cuentaRpc({ cuenta_id: 'cta-usd-2', moneda: 'USD', banco: 'Scotiabank', numero_cuenta: '9887766554433' }),
    ])
    montar()

    const usd = await screen.findByRole('region', { name: 'Cuentas para depósitos en dólares' })
    expect(within(usd).getByText('BBVA')).toBeInTheDocument()
    expect(within(usd).getByText('Scotiabank')).toBeInTheDocument()
  })

  it('no pinta una cuenta cacheada mientras la revalidación de esta apertura sigue pendiente', async () => {
    let resolver!: (detalle: ClienteDetalleDatos) => void
    obtenerDetalle.mockReturnValue(new Promise((resolve) => { resolver = resolve }))
    // La RPC de cuentas también queda en vuelo: su caché envenenada tampoco
    // debe pintarse jamás.
    listarCuentas.mockImplementation(() => new Promise(() => undefined))
    const queryClient = clienteQuery()
    queryClient.setQueryData(
      crmQueryKeys.clienteDetalle('cli-1'),
      detalleBase({ nombre_completo: 'COPIA CACHEADA' }),
    )
    queryClient.setQueryData(
      crmQueryKeys.cuentasBancarias('cli-1', 'PEN'),
      [cuentaRpc({ cci: 'CCI-CACHE-VIEJO' as string })],
    )

    montar({ queryClient })
    expect(screen.queryByText('COPIA CACHEADA')).not.toBeInTheDocument()
    expect(screen.queryByText('CCI-CACHE-VIEJO')).not.toBeInTheDocument()

    resolver(detalleBase({ nombre_completo: 'COPIA FRESCA' }))
    expect(await screen.findByText('COPIA FRESCA')).toBeInTheDocument()
    // El detalle confirmó, pero las cuentas siguen en vuelo: sección en espera,
    // nunca la copia envenenada.
    expect(screen.queryByText('CCI-CACHE-VIEJO')).not.toBeInTheDocument()
  })

  it('si falla la revalidación, muestra un error y nunca revela la cuenta cacheada', async () => {
    obtenerDetalle.mockRejectedValue(new crmApi.CrmApiError('No se pudo actualizar la ficha bancaria.', 'SIN_RED'))
    const queryClient = clienteQuery()
    queryClient.setQueryData(
      crmQueryKeys.clienteDetalle('cli-1'),
      detalleBase({ nombre_completo: 'COPIA CACHEADA' }),
    )

    montar({ queryClient })

    expect(await screen.findByRole('alert')).toHaveTextContent('No se pudo actualizar la ficha bancaria.')
    expect(screen.queryByText('COPIA CACHEADA')).not.toBeInTheDocument()
  })

  it('un fallo de refresh posterior vuelve a cerrar una ficha ya confirmada', async () => {
    obtenerDetalle
      .mockResolvedValueOnce(detalleBase({ nombre_completo: 'CLIENTE CONFIRMADO' }))
      .mockRejectedValueOnce(new crmApi.CrmApiError('No se pudo refrescar la ficha.', 'SIN_RED'))
    const { queryClient } = montar()
    expect(await screen.findByText('CLIENTE CONFIRMADO')).toBeInTheDocument()

    await act(async () => {
      await queryClient.refetchQueries({ queryKey: crmQueryKeys.clienteDetalle('cli-1'), exact: true })
    })

    expect(await screen.findByRole('alert')).toHaveTextContent('No se pudo refrescar la ficha.')
    expect(screen.queryByText('CLIENTE CONFIRMADO')).not.toBeInTheDocument()
  })

  it('Reintentar mantiene oculto lo viejo y habilita la ficha solo al recibir una copia nueva', async () => {
    const user = userEvent.setup()
    obtenerDetalle
      .mockRejectedValueOnce(new crmApi.CrmApiError('Sin conexión.', 'SIN_RED'))
      .mockResolvedValueOnce(detalleBase({ nombre_completo: 'CLIENTE ACTUALIZADO' }))
    const queryClient = clienteQuery()
    queryClient.setQueryData(
      crmQueryKeys.clienteDetalle('cli-1'),
      detalleBase({ nombre_completo: 'COPIA CACHEADA' }),
    )
    montar({ queryClient })

    await user.click(await screen.findByRole('button', { name: 'Reintentar' }))

    expect(await screen.findByText('CLIENTE ACTUALIZADO')).toBeInTheDocument()
    expect(screen.queryByText('COPIA CACHEADA')).not.toBeInTheDocument()
    expect(obtenerDetalle).toHaveBeenCalledTimes(2)
  })

  it('un fallo de refetch bancario posterior oculta las cuentas ya confirmadas', async () => {
    // El requisito espejo del de la ficha, para la sección bancaria: cuentas
    // confirmadas → refetch que falla → nada de CCI viejo a la vista.
    obtenerDetalle.mockResolvedValue(detalleBase())
    cuentasPorMoneda([cuentaRpc()], [])
    const { queryClient } = montar()
    expect(await screen.findByText('00219112345678901234')).toBeInTheDocument()

    listarCuentas.mockRejectedValue(
      new crmApi.CrmApiError('No se pudieron cargar las cuentas bancarias del cliente.', 'SIN_RED'),
    )
    await act(async () => {
      await queryClient.refetchQueries({ queryKey: crmQueryKeys.cuentasBancarias('cli-1', 'PEN'), exact: true })
    })

    expect(await screen.findByRole('alert')).toHaveTextContent('No se pudieron cargar las cuentas bancarias del cliente.')
    expect(screen.queryByText('00219112345678901234')).not.toBeInTheDocument()
    // La identidad, confirmada por su propia consulta, sigue a la vista.
    expect(screen.getByText('CLIENTE PORTAL UNO')).toBeInTheDocument()
  })

  it('si fallan las cuentas, la identidad sigue visible y la sección bancaria reintenta por su cuenta', async () => {
    const user = userEvent.setup()
    obtenerDetalle.mockResolvedValue(detalleBase())
    listarCuentas
      .mockRejectedValueOnce(new crmApi.CrmApiError('No se pudieron cargar las cuentas bancarias del cliente.', 'POSTGREST_ERROR'))
      .mockRejectedValueOnce(new crmApi.CrmApiError('No se pudieron cargar las cuentas bancarias del cliente.', 'POSTGREST_ERROR'))
      .mockImplementation(async (_clienteId, moneda) =>
        moneda === 'USD' ? [cuentaRpc({ cuenta_id: 'cta-usd-1', moneda: 'USD', banco: 'BBVA' })] : [])
    montar()

    // La identidad NO se bloquea por el fallo bancario (hay lectores válidos de
    // la ficha a los que el gate de cartera de la RPC puede negar).
    expect(await screen.findByText('CLIENTE PORTAL UNO')).toBeInTheDocument()
    const alerta = await screen.findByRole('alert')
    expect(alerta).toHaveTextContent('No se pudieron cargar las cuentas bancarias del cliente.')

    await user.click(within(alerta).getByRole('button', { name: 'Reintentar' }))

    const usd = await screen.findByRole('region', { name: 'Cuenta para depósitos en dólares' })
    expect(within(usd).getByText('BBVA')).toBeInTheDocument()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })

  it('explica por separado cuando no existe una cuenta PEN ni USD', async () => {
    obtenerDetalle.mockResolvedValue(detalleBase())
    cuentasPorMoneda([], [])
    montar()

    await screen.findByText('CLIENTE PORTAL UNO')
    const pen = await screen.findByRole('region', { name: 'Cuenta para depósitos en soles' })
    const usd = screen.getByRole('region', { name: 'Cuenta para depósitos en dólares' })
    expect(within(pen).getByText('No registró una cuenta en esta moneda.')).toBeInTheDocument()
    expect(within(usd).getByText('No registró una cuenta en esta moneda.')).toBeInTheDocument()
  })

  it('con datos demo pinta de inmediato (cuentas embebidas incluidas), no llama a la API y permite cerrar', async () => {
    const user = userEvent.setup()
    const { onCerrar } = montar({ datos: detalleBase({ nombre_completo: 'CLIENTE FICTICIO DEMO' }) })

    expect(screen.getByText('CLIENTE FICTICIO DEMO')).toBeInTheDocument()
    // En demo las cuentas salen de las casillas embebidas del fixture.
    const pen = screen.getByRole('region', { name: 'Cuenta para depósitos en soles' })
    expect(within(pen).getByText('BCP')).toBeInTheDocument()
    const usd = screen.getByRole('region', { name: 'Cuenta para depósitos en dólares' })
    expect(within(usd).getByText('Interbank')).toBeInTheDocument()
    await waitFor(() => expect(obtenerDetalle).not.toHaveBeenCalled())
    expect(listarCuentas).not.toHaveBeenCalled()
    await user.click(screen.getByRole('button', { name: 'Cerrar' }))
    expect(onCerrar).toHaveBeenCalledOnce()
  })
})

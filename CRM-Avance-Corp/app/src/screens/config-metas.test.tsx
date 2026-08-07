import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { ConfiguracionMetas, DetalleMeta } from '@/lib/metas-versionadas'

const dobles = vi.hoisted(() => ({
  consulta: {} as Record<string, unknown>,
  publicar: vi.fn(),
  obtenerAnterior: vi.fn(),
  toastSuccess: vi.fn(),
  toastError: vi.fn(),
  periodoConsultado: '',
}))

vi.mock('sonner', () => ({
  toast: { success: dobles.toastSuccess, error: dobles.toastError },
}))

vi.mock('@/data/crm-config-queries', () => ({
  useConfiguracionMetas: (periodo: string) => {
    dobles.periodoConsultado = periodo
    return dobles.consulta
  },
  usePublicarMetas: () => ({ mutateAsync: dobles.publicar, isPending: false }),
}))

vi.mock('@/data/crm-config-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-config-api')>()
  return {
    ...actual,
    obtenerConfiguracionMetas: (...args: unknown[]) => dobles.obtenerAnterior(...args),
  }
})

const { ConfigMetas } = await import('./config-metas')

const ID_VENDEDOR = '10000000-0000-4000-8000-000000000001'
const ID_SUPERVISOR = '20000000-0000-4000-8000-000000000001'

function detalles(capitalBase = 1_000): DetalleMeta[] {
  return [
    { categoria: 'nuevo', moneda: 'PEN', capital_objetivo: capitalBase, contratos_objetivo: 1 },
    { categoria: 'nuevo', moneda: 'USD', capital_objetivo: 2_000, contratos_objetivo: 2 },
    { categoria: 'renovacion', moneda: 'PEN', capital_objetivo: 3_000, contratos_objetivo: 3 },
    { categoria: 'renovacion', moneda: 'USD', capital_objetivo: 4_000, contratos_objetivo: 4 },
    { categoria: 'upgrade', moneda: 'PEN', capital_objetivo: 5_000, contratos_objetivo: 5 },
    { categoria: 'upgrade', moneda: 'USD', capital_objetivo: 6_000, contratos_objetivo: 6 },
  ]
}

function configuracion(overrides: Partial<ConfiguracionMetas> = {}): ConfiguracionMetas {
  return {
    version: 1,
    periodo: '2026-08-01',
    revision: 4,
    publicada_en: '2026-08-02T15:00:00.000Z',
    publicada_por: '30000000-0000-4000-8000-000000000001',
    publicada_por_nombre: 'GERENCIA UNO',
    puede_editar: true,
    vendedores: [{
      vendedor_id: ID_VENDEDOR,
      nombre: 'ANA VENDEDORA',
      supervisor_id: ID_SUPERVISOR,
      supervisor_nombre: 'SUPERVISOR UNO',
      conversion_objetivo: 15,
      detalles: detalles(),
    }],
    ...overrides,
  }
}

function consultaCon(
  data: ConfiguracionMetas | undefined,
  overrides: Record<string, unknown> = {},
) {
  return {
    data,
    error: null,
    isPending: false,
    isError: false,
    isSuccess: Boolean(data),
    refetch: vi.fn(),
    ...overrides,
  }
}

beforeEach(() => {
  vi.spyOn(Date, 'now').mockReturnValue(Date.UTC(2026, 7, 7, 18))
  dobles.consulta = consultaCon(configuracion())
  dobles.publicar.mockReset().mockResolvedValue({})
  dobles.obtenerAnterior.mockReset().mockResolvedValue(configuracion({
    periodo: '2026-07-01',
    revision: 2,
    vendedores: [{
      vendedor_id: ID_VENDEDOR,
      nombre: 'ANA VENDEDORA',
      supervisor_id: ID_SUPERVISOR,
      supervisor_nombre: 'SUPERVISOR UNO',
      conversion_objetivo: 22,
      detalles: detalles(9_000),
    }],
  }))
})

describe('ConfigMetas', () => {
  it('representa carga, error seguro con reintento y roster vacío', async () => {
    dobles.consulta = consultaCon(undefined, { isPending: true })
    const carga = render(<ConfigMetas />)
    expect(screen.getByRole('status')).toHaveTextContent('Cargando las metas del período')
    carga.unmount()

    const refetch = vi.fn()
    dobles.consulta = consultaCon(undefined, {
      isError: true,
      error: new Error('detalle SQL privado'),
      refetch,
    })
    const error = render(<ConfigMetas />)
    expect(screen.getByText('No se pudieron cargar las metas.')).toBeInTheDocument()
    expect(screen.queryByText(/detalle SQL privado/)).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(refetch).toHaveBeenCalledOnce()
    error.unmount()

    dobles.consulta = consultaCon(configuracion({ vendedores: [], revision: 0, publicada_en: null }))
    render(<ConfigMetas />)
    expect(await screen.findByText('No hay vendedores activos en el roster de este período.')).toBeInTheDocument()
    expect(screen.getByText('Sin publicar')).toBeInTheDocument()
  })

  it('impone solo lectura desde el contrato del servidor', async () => {
    dobles.consulta = consultaCon(configuracion({ puede_editar: false }))
    render(<ConfigMetas />)

    expect(await screen.findByText(/Solo lectura: puedes auditar/)).toBeInTheDocument()
    expect(screen.getByLabelText('Conversión objetivo de ANA VENDEDORA')).toBeDisabled()
    expect(screen.getByLabelText('Capital nuevo PEN de ANA VENDEDORA')).toBeDisabled()
    expect(screen.queryByRole('button', { name: 'Publicar revisión' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Copiar mes anterior' })).not.toBeInTheDocument()
  })

  it('publica una revisión con las seis dimensiones y la revisión esperada', async () => {
    const user = userEvent.setup()
    render(<ConfigMetas />)

    const conversion = await screen.findByLabelText('Conversión objetivo de ANA VENDEDORA')
    fireEvent.change(conversion, { target: { value: '18.5' } })
    fireEvent.change(screen.getByLabelText('Capital nuevo PEN de ANA VENDEDORA'), {
      target: { value: '12500.75' },
    })
    fireEvent.change(screen.getByLabelText('Contratos upgrade USD de ANA VENDEDORA'), {
      target: { value: '9' },
    })

    expect(screen.getByRole('status')).toHaveTextContent('Hay cambios sin publicar')
    await user.click(screen.getByRole('button', { name: 'Publicar revisión' }))

    await waitFor(() => expect(dobles.publicar).toHaveBeenCalledOnce())
    expect(dobles.publicar).toHaveBeenCalledWith({
      periodo: '2026-08-01',
      expectedRevision: 4,
      metas: {
        [ID_VENDEDOR]: {
          conversion_objetivo: 18.5,
          detalles: [
            { categoria: 'nuevo', moneda: 'PEN', capital_objetivo: 12_500.75, contratos_objetivo: 1 },
            { categoria: 'nuevo', moneda: 'USD', capital_objetivo: 2_000, contratos_objetivo: 2 },
            { categoria: 'renovacion', moneda: 'PEN', capital_objetivo: 3_000, contratos_objetivo: 3 },
            { categoria: 'renovacion', moneda: 'USD', capital_objetivo: 4_000, contratos_objetivo: 4 },
            { categoria: 'upgrade', moneda: 'PEN', capital_objetivo: 5_000, contratos_objetivo: 5 },
            { categoria: 'upgrade', moneda: 'USD', capital_objetivo: 6_000, contratos_objetivo: 9 },
          ],
        },
      },
    })
    expect(dobles.toastSuccess).toHaveBeenCalledWith('Metas de agosto de 2026 publicadas.')
  })

  it('rechaza valores fuera del contrato antes de mutar', async () => {
    const user = userEvent.setup()
    render(<ConfigMetas />)

    fireEvent.change(await screen.findByLabelText('Conversión objetivo de ANA VENDEDORA'), {
      target: { value: '101' },
    })
    await user.click(screen.getByRole('button', { name: 'Publicar revisión' }))

    expect(dobles.toastError).toHaveBeenCalledWith(
      'La conversión de ANA VENDEDORA debe estar entre 0 y 100.',
    )
    expect(dobles.publicar).not.toHaveBeenCalled()
  })

  it('copia el mes anterior sin publicarlo automáticamente', async () => {
    const user = userEvent.setup()
    render(<ConfigMetas />)

    await user.click(screen.getByRole('button', { name: 'Copiar mes anterior' }))

    await waitFor(() => expect(dobles.obtenerAnterior).toHaveBeenCalledWith(
      '2026-07-01',
    ))
    expect(await screen.findByLabelText('Conversión objetivo de ANA VENDEDORA')).toHaveValue(22)
    expect(screen.getByLabelText('Capital nuevo PEN de ANA VENDEDORA')).toHaveValue(9_000)
    expect(dobles.publicar).not.toHaveBeenCalled()
    expect(dobles.toastSuccess).toHaveBeenCalledWith('Se copiaron las metas de julio de 2026.')
  })
})

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
    sin_supervisor: [],
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
    expect(screen.getByLabelText('Meta mensual total de ANA VENDEDORA')).toBeDisabled()
    expect(screen.queryByRole('button', { name: 'Publicar revisión' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Copiar mes anterior' })).not.toBeInTheDocument()
  })

  it('publica una sola meta total y normaliza las dimensiones internas', async () => {
    const user = userEvent.setup()
    render(<ConfigMetas />)

    fireEvent.change(await screen.findByLabelText('Meta mensual total de ANA VENDEDORA'), {
      target: { value: '500000' },
    })

    expect(screen.getByRole('status')).toHaveTextContent('Hay cambios sin publicar')
    await user.click(screen.getByRole('button', { name: 'Publicar revisión' }))

    await waitFor(() => expect(dobles.publicar).toHaveBeenCalledOnce())
    expect(dobles.publicar).toHaveBeenCalledWith({
      periodo: '2026-08-01',
      expectedRevision: 4,
      metas: {
        [ID_VENDEDOR]: {
          conversion_objetivo: 0,
          detalles: [
            { categoria: 'nuevo', moneda: 'PEN', capital_objetivo: 500_000, contratos_objetivo: 0 },
            { categoria: 'nuevo', moneda: 'USD', capital_objetivo: 0, contratos_objetivo: 0 },
            { categoria: 'renovacion', moneda: 'PEN', capital_objetivo: 0, contratos_objetivo: 0 },
            { categoria: 'renovacion', moneda: 'USD', capital_objetivo: 0, contratos_objetivo: 0 },
            { categoria: 'upgrade', moneda: 'PEN', capital_objetivo: 0, contratos_objetivo: 0 },
            { categoria: 'upgrade', moneda: 'USD', capital_objetivo: 0, contratos_objetivo: 0 },
          ],
        },
      },
    })
    expect(dobles.toastSuccess).toHaveBeenCalledWith('Metas de agosto de 2026 publicadas.')
  })

  it('rechaza valores fuera del contrato antes de mutar', async () => {
    const user = userEvent.setup()
    render(<ConfigMetas />)

    fireEvent.change(await screen.findByLabelText('Meta mensual total de ANA VENDEDORA'), {
      target: { value: '100000001' },
    })
    await user.click(screen.getByRole('button', { name: 'Publicar revisión' }))

    expect(dobles.toastError).toHaveBeenCalledWith(
      'La meta mensual de ANA VENDEDORA debe estar entre S/ 0 y S/ 100,000,000.',
    )
    expect(dobles.publicar).not.toHaveBeenCalled()
  })

  // ESTADO DE PRODUCCIÓN (2026-08-10): 16 analistas con supervisor y una
  // analista sin él. Ese único caso bloqueaba la publicación del mes ENTERO —
  // el editor ofrecía 16 metas y el servidor exigía 17 — y la pantalla no decía
  // nada. Aquí se fija lo contrario: se avisa de quién queda fuera Y se publica
  // igual el resto.
  it('señala a quien queda fuera de las metas sin bloquear la publicación', async () => {
    const user = userEvent.setup()
    dobles.consulta = consultaCon(configuracion({
      revision: 0,
      publicada_en: null,
      publicada_por: null,
      publicada_por_nombre: null,
      sin_supervisor: [
        {
          vendedor_id: '40000000-0000-4000-8000-000000000001',
          nombre: 'IVETT SIN JEFE',
          motivo: 'sin_supervisor',
        },
        {
          vendedor_id: '40000000-0000-4000-8000-000000000002',
          nombre: 'RUTH CON JEFE DE BAJA',
          motivo: 'supervisor_inactivo',
        },
      ],
    }))
    render(<ConfigMetas />)

    // Encabezado real, no un <p> en negrita: es el único bloque de la pantalla
    // que un lector de pantalla no encontraría navegando por encabezados.
    expect(await screen.findByRole('heading', { name: '2 analistas sin meta este mes' }))
      .toBeInTheDocument()
    // Cada motivo es un arreglo distinto y la pantalla no puede confundirlos.
    expect(screen.getByText(/IVETT SIN JEFE/)).toBeInTheDocument()
    expect(screen.getByText(/no tiene supervisor asignado/)).toBeInTheDocument()
    expect(screen.getByText(/RUTH CON JEFE DE BAJA/)).toBeInTheDocument()
    expect(screen.getByText(/su supervisor está dado de baja/)).toBeInTheDocument()
    // La consecuencia real, no solo el síntoma.
    expect(screen.getByText(/su producción no se atribuye/)).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Revisar jerarquía/ }))
      .toHaveAttribute('href', '#/config-usuarios')

    fireEvent.change(screen.getByLabelText('Meta mensual total de ANA VENDEDORA'), {
      target: { value: '80000' },
    })
    await user.click(screen.getByRole('button', { name: 'Publicar revisión' }))

    await waitFor(() => expect(dobles.publicar).toHaveBeenCalledOnce())
    const enviado = dobles.publicar.mock.calls[0]?.[0] as { metas: Record<string, unknown> }
    // Solo el roster: quien no tiene supervisor no cabe en crm.metas_vendedor.
    expect(Object.keys(enviado.metas)).toEqual([ID_VENDEDOR])
  })

  it('no menciona a nadie cuando el roster está completo', async () => {
    render(<ConfigMetas />)
    expect(await screen.findByLabelText('Meta mensual total de ANA VENDEDORA')).toBeInTheDocument()
    expect(screen.queryByText(/sin meta este mes/)).not.toBeInTheDocument()
  })

  it('copia el mes anterior sin publicarlo automáticamente', async () => {
    const user = userEvent.setup()
    render(<ConfigMetas />)

    await user.click(screen.getByRole('button', { name: 'Copiar mes anterior' }))

    await waitFor(() => expect(dobles.obtenerAnterior).toHaveBeenCalledWith(
      '2026-07-01',
    ))
    expect(await screen.findByLabelText('Meta mensual total de ANA VENDEDORA')).toHaveValue(17_000)
    expect(dobles.publicar).not.toHaveBeenCalled()
    expect(dobles.toastSuccess).toHaveBeenCalledWith('Se copiaron las metas de julio de 2026.')
  })
})

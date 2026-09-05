import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { CrmApiError } from '@/data/crm-api'
import type { ConfiguracionSla, MetricasSla } from '@/lib/sla-versionado'

const dobles = vi.hoisted(() => ({
  consulta: {} as Record<string, unknown>,
  metricas: {} as Record<string, unknown>,
  publicar: vi.fn(),
  toastSuccess: vi.fn(),
  toastError: vi.fn(),
  periodoMetricas: { desde: '', hasta: '' },
}))

vi.mock('sonner', () => ({
  toast: { success: dobles.toastSuccess, error: dobles.toastError },
}))

vi.mock('@/data/crm-config-queries', () => ({
  useConfiguracionSla: () => dobles.consulta,
  useMetricasSla: (desde: string, hasta: string) => {
    dobles.periodoMetricas = { desde, hasta }
    return dobles.metricas
  },
  usePublicarPoliticaSla: () => ({ mutateAsync: dobles.publicar, isPending: false }),
}))

const { ConfigSla } = await import('./config-sla')

const ID_POLITICA = '10000000-0000-4000-8000-000000000001'

function configuracion(overrides: Partial<ConfiguracionSla> = {}): ConfiguracionSla {
  return {
    version: 1,
    expected_version: 2,
    puede_editar: true,
    politica: {
      id: ID_POLITICA,
      version: 2,
      version_anterior_id: '10000000-0000-4000-8000-000000000000',
      vigente_desde: '2026-08-01T05:00:00.000Z',
      zona_horaria: 'America/Lima',
      tipo_reloj: 'corrido',
      primera_gestion_minutos: 60,
      primer_contacto_minutos: 120,
      publicada_por: '20000000-0000-4000-8000-000000000001',
      publicada_por_nombre: 'GERENCIA UNO',
      publicada_en: '2026-08-01T04:55:00.000Z',
      etapas: [
        { etapa: 'nuevo', maximo_minutos: 1_440 },
        { etapa: 'contactado', maximo_minutos: 4_320 },
        { etapa: 'reunion_agendada', maximo_minutos: 4_320 },
        { etapa: 'propuesta_enviada', maximo_minutos: 7_200 },
      ],
    },
    ...overrides,
  }
}

function metricasVacias(): MetricasSla {
  return {
    version: 1,
    generado_en: '2026-08-07T18:00:00.000Z',
    periodo: { desde: '2026-08-01', hasta: '2026-08-31', zona: 'America/Lima' },
    ciclos: { primera_gestion: [], primer_contacto: [] },
    asignaciones: { primera_gestion: [], primer_contacto: [] },
    etapas: [],
  }
}

function consultaCon<T>(data: T | undefined, overrides: Record<string, unknown> = {}) {
  return {
    data,
    error: null,
    isPending: false,
    isError: false,
    refetch: vi.fn(),
    ...overrides,
  }
}

beforeEach(() => {
  vi.spyOn(Date, 'now').mockReturnValue(Date.UTC(2026, 7, 7, 18))
  dobles.consulta = consultaCon(configuracion())
  dobles.metricas = consultaCon(metricasVacias())
  dobles.publicar.mockReset().mockResolvedValue({})
})

describe('ConfigSla', () => {
  it('consulta hasta hoy en Lima, sin pedir días futuros del mes al servidor', () => {
    render(<ConfigSla />)
    expect(dobles.periodoMetricas).toEqual({ desde: '2026-08-01', hasta: '2026-08-07' })
    expect(screen.getByLabelText('Hasta')).toHaveValue('2026-08-07')
    expect(screen.getByLabelText('Hasta')).toHaveAttribute('max', '2026-08-07')
    expect(screen.getByLabelText('Desde')).toHaveAttribute('max', '2026-08-07')
  })

  it('representa carga, error seguro y métricas vacías con reintento', async () => {
    dobles.consulta = consultaCon(undefined, { isPending: true })
    dobles.metricas = consultaCon(metricasVacias())
    const carga = render(<ConfigSla />)
    expect(screen.getByRole('status')).toHaveTextContent('Cargando la política vigente')
    expect(screen.getAllByText('Sin casos en el período.')).toHaveLength(8)
    carga.unmount()

    const refetch = vi.fn()
    dobles.consulta = consultaCon(undefined, {
      isError: true,
      error: new Error('detalle SQL privado'),
      refetch,
    })
    const error = render(<ConfigSla />)
    expect(screen.getByText('No se pudo cargar la política SLA.')).toBeInTheDocument()
    expect(screen.queryByText(/detalle SQL privado/)).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(refetch).toHaveBeenCalledOnce()
    error.unmount()

    const refetchMetricas = vi.fn()
    dobles.consulta = consultaCon(configuracion())
    dobles.metricas = consultaCon(undefined, {
      isError: true,
      error: new Error('consulta interna'),
      refetch: refetchMetricas,
    })
    render(<ConfigSla />)
    expect(screen.getByText('No se pudieron cargar las métricas SLA.')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(refetchMetricas).toHaveBeenCalledOnce()
  })

  it('impone solo lectura desde la capacidad devuelta por el servidor', async () => {
    dobles.consulta = consultaCon(configuracion({ puede_editar: false }))
    render(<ConfigSla />)

    expect(await screen.findByText(/Solo lectura: puedes auditar/)).toBeInTheDocument()
    expect(screen.getByLabelText('Primera gestión')).toBeDisabled()
    expect(screen.getByLabelText('Unidad de Primera gestión')).toBeDisabled()
    expect(screen.getByLabelText('Lead nuevo')).toBeDisabled()
    expect(screen.getByLabelText('Unidad de Lead nuevo')).toBeDisabled()
    expect(screen.queryByLabelText('Programar vigencia (opcional)')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Publicar nueva versión' })).not.toBeInTheDocument()
  })

  it('exige confirmación explícita y publica una nueva versión inmutable', async () => {
    const user = userEvent.setup()
    render(<ConfigSla />)

    expect(await screen.findByLabelText('Primera gestión')).toHaveValue(1)
    expect(screen.getByLabelText('Unidad de Primera gestión')).toHaveValue('horas')
    expect(screen.getByLabelText('Primer contacto efectivo')).toHaveValue(2)
    expect(screen.getByLabelText('Lead nuevo')).toHaveValue(1)
    expect(screen.getByLabelText('Unidad de Lead nuevo')).toHaveValue('dias')
    fireEvent.change(await screen.findByLabelText('Primera gestión'), {
      target: { value: '1.5' },
    })
    await user.click(screen.getByRole('button', { name: 'Publicar nueva versión' }))

    expect(dobles.publicar).not.toHaveBeenCalled()
    let dialogo = screen.getByRole('dialog', { name: 'Publicar política SLA v3' })
    expect(within(dialogo).getByRole('heading', { name: 'Publicar política SLA v3' })).toBeInTheDocument()
    expect(within(dialogo).getByText(/no se edita ni elimina/)).toBeInTheDocument()
    await user.click(within(dialogo).getByRole('button', { name: 'Cancelar' }))
    expect(screen.queryByRole('dialog', { name: 'Publicar política SLA v3' })).not.toBeInTheDocument()
    expect(dobles.publicar).not.toHaveBeenCalled()

    await user.click(screen.getByRole('button', { name: 'Publicar nueva versión' }))
    dialogo = screen.getByRole('dialog', { name: 'Publicar política SLA v3' })
    await user.click(within(dialogo).getByRole('button', { name: 'Confirmar publicación' }))

    await waitFor(() => expect(dobles.publicar).toHaveBeenCalledOnce())
    expect(dobles.publicar).toHaveBeenCalledWith({
      expectedVersion: 2,
      vigenteDesde: null,
      config: {
        zona_horaria: 'America/Lima',
        tipo_reloj: 'corrido',
        primera_gestion_minutos: 90,
        primer_contacto_minutos: 120,
        etapas: [
          { etapa: 'nuevo', maximo_minutos: 1_440 },
          { etapa: 'contactado', maximo_minutos: 4_320 },
          { etapa: 'reunion_agendada', maximo_minutos: 4_320 },
          { etapa: 'propuesta_enviada', maximo_minutos: 7_200 },
        ],
      },
    })
    expect(dobles.toastSuccess).toHaveBeenCalledWith('Política SLA v3 publicada.')
  })

  it('rechaza una política incoherente antes de abrir la confirmación', async () => {
    const user = userEvent.setup()
    render(<ConfigSla />)

    fireEvent.change(await screen.findByLabelText('Primera gestión'), {
      target: { value: '3' },
    })
    await user.click(screen.getByRole('button', { name: 'Publicar nueva versión' }))

    expect(dobles.toastError).toHaveBeenCalledWith(
      'El primer contacto debe ser igual o posterior a la primera gestión y no superar 30 días.',
    )
    expect(screen.queryByRole('dialog', { name: 'Publicar política SLA v3' })).not.toBeInTheDocument()
    expect(dobles.publicar).not.toHaveBeenCalled()
  })

  it('mantiene abierta la confirmación cuando el servidor rechaza por concurrencia', async () => {
    dobles.publicar.mockRejectedValueOnce(new CrmApiError(
      'La política cambió en otra sesión. Recarga antes de continuar.',
      'CONFLICTO_CONFIG',
    ))
    const user = userEvent.setup()
    render(<ConfigSla />)

    fireEvent.change(await screen.findByLabelText('Primer contacto efectivo'), {
      target: { value: '3' },
    })
    await user.click(screen.getByRole('button', { name: 'Publicar nueva versión' }))
    const dialogo = screen.getByRole('dialog', { name: 'Publicar política SLA v3' })
    await user.click(within(dialogo).getByRole('button', { name: 'Confirmar publicación' }))

    await waitFor(() => expect(dobles.toastError).toHaveBeenCalledWith(
      'La política cambió en otra sesión. Recarga antes de continuar.',
    ))
    expect(screen.getByRole('dialog', { name: 'Publicar política SLA v3' })).toBeInTheDocument()
  })

  it('cambia entre días y horas sin obligar a calcular minutos', async () => {
    const user = userEvent.setup()
    render(<ConfigSla />)

    const campo = await screen.findByLabelText('Lead nuevo')
    expect(campo).toHaveValue(1)
    await user.selectOptions(screen.getByLabelText('Unidad de Lead nuevo'), 'horas')
    expect(campo).toHaveValue(24)
    expect(screen.getByRole('button', { name: 'Publicar nueva versión' })).toBeDisabled()
  })
})

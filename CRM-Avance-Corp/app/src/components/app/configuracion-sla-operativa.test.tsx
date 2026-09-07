import { beforeEach, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ConfiguracionSlaOperativa } from './configuracion-sla-operativa'
import { useCambiarModoSla, useConfiguracionSlaV2, usePublicarReglasSlaAprobadas } from '@/data/sla-operacion-queries'
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: { demo: false } }) }))
vi.mock('@/data/sla-operacion-queries', () => ({ useCambiarModoSla: vi.fn(), useConfiguracionSlaV2: vi.fn(), usePublicarReglasSlaAprobadas: vi.fn() }))
const mutar = vi.fn()
const publicar = vi.fn()
const consulta = vi.mocked(useConfiguracionSlaV2)
const data = { version: 2 as const, puede_editar: true, expected_version: 3,
  vigente: { base: { version: 3 }, operacion: [{ etapa: 'contactado' as const, seguimiento_minutos: 4320, prorroga_minutos: 5760, prorroga_max: 2, tope_extra_minutos: 11520, pausa_habilitada: true, pausa_margen_minutos: 1440 }] },
  ultima_publicada: { base: { version: 3 }, operacion: null }, control: { modo: 'activo' as const, revision: 7, primera_activacion_en: null, politica_adopcion_id: null } }
beforeEach(() => {
  vi.clearAllMocks()
  consulta.mockReturnValue({ data, error: null, isFetching: false, refetch: vi.fn() } as unknown as ReturnType<typeof useConfiguracionSlaV2>)
  vi.mocked(useCambiarModoSla).mockReturnValue({ mutateAsync: mutar, isPending: false } as unknown as ReturnType<typeof useCambiarModoSla>)
  vi.mocked(usePublicarReglasSlaAprobadas).mockReturnValue({ mutateAsync: publicar, isPending: false } as unknown as ReturnType<typeof usePublicarReglasSlaAprobadas>)
})
it('muestra reglas servidas y el cambio de modo usa la revisión confirmada', async () => {
  const usuario = userEvent.setup()
  let resolver!: (value: unknown) => void
  mutar.mockReturnValue(new Promise((resolve) => { resolver = resolve }))
  render(<ConfiguracionSlaOperativa />)
  expect(screen.getByText('Contactado')).toBeInTheDocument()
  await usuario.click(screen.getByRole('button', { name: 'Desactivar seguimiento operativo' }))
  expect(mutar).toHaveBeenCalledWith({ revision: 7, modo: 'legado' })
  expect(screen.queryByRole('status')).not.toBeInTheDocument()
  resolver({ modo: 'legado' })
  expect(await screen.findByRole('status')).toHaveTextContent('Se conserva el historial')
})
it('si falla el guardado informa el error y no anuncia éxito', async () => {
  mutar.mockRejectedValue(new Error('Conexión'))
  render(<ConfiguracionSlaOperativa />)
  await userEvent.setup().click(screen.getByRole('button', { name: 'Desactivar seguimiento operativo' }))
  expect(await screen.findByRole('alert')).toBeInTheDocument()
  expect(screen.queryByRole('status')).not.toBeInTheDocument()
})
it('un lector sin permiso no recibe el botón de cambiar modo', () => {
  consulta.mockReturnValue({ data: { ...data, puede_editar: false }, error: null, isFetching: false } as unknown as ReturnType<typeof useConfiguracionSlaV2>)
  render(<ConfiguracionSlaOperativa />)
  expect(screen.queryByRole('button', { name: 'Desactivar seguimiento operativo' })).not.toBeInTheDocument()
})
it('un error en la configuración es explícito aunque haya una foto anterior', () => {
  consulta.mockReturnValue({ data, error: new Error('Conexión'), isFetching: false } as unknown as ReturnType<typeof useConfiguracionSlaV2>)
  render(<ConfiguracionSlaOperativa />)
  expect(screen.getByRole('alert')).toBeInTheDocument()
  expect(screen.queryByText('Contactado')).not.toBeInTheDocument()
})

it('publica el primer anexo con la versión confirmada y los plazos servidos antes de habilitar la activación', async () => {
  const config = { ...data, vigente: { base: { version: 3 }, operacion: null }, control: { ...data.control, modo: 'legado' },
    inicializacion_aprobada: { disponible: true, motivo: null, config: { primera_gestion_minutos: 180, primer_contacto_minutos: 2880,
      etapas: [{ ...data.vigente.operacion[0], maximo_minutos: 17280 }] } } }
  consulta.mockReturnValue({ data: config, error: null, isFetching: false } as unknown as ReturnType<typeof useConfiguracionSlaV2>)
  let confirmar!: (value: unknown) => void
  publicar.mockReturnValue(new Promise((resolve) => { confirmar = resolve }))
  render(<ConfiguracionSlaOperativa />)
  expect(screen.getByText(/Primera gestión: 3 horas/)).toBeInTheDocument()
  expect(screen.getByRole('button', { name: 'Activar seguimiento operativo' })).toBeDisabled()
  await userEvent.setup().click(screen.getByRole('button', { name: 'Publicar reglas aprobadas' }))
  expect(publicar).toHaveBeenCalledWith(3)
  expect(screen.queryByRole('status')).not.toBeInTheDocument()
  confirmar({ expected_version: 4 })
  expect(await screen.findByRole('status')).toHaveTextContent('Reglas aprobadas publicadas en la política v4')
})

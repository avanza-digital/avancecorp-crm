import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const dobles = vi.hoisted(() => ({
  consulta: {} as Record<string, unknown>,
  publicar: vi.fn(),
  yo: { id: 'g-1', rol: 'gerencia', demo: false } as { id: string; rol: string; demo: boolean },
}))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('@/data/crm-queries', () => ({
  usePoliticaRentabilidad: () => ({ refetch: vi.fn(), ...dobles.consulta }),
  usePublicarPoliticaRentabilidad: () => ({ mutateAsync: dobles.publicar, isPending: false }),
}))
const { ConfigRentabilidad } = await import('./config-rentabilidad')

const VIGENTE = { id: 'p1', version: 1, vigente_desde: '2026-09-06T21:00:00Z', tasa_base_nueva: 15, tope_tecnico: 50, vigencia_solicitud_dias: 7, modo: 'observacion', nota: null, publicada_en: '2026-09-06T21:00:00Z', publicada_por_nombre: null, es_vigente: true }
const DATA = { vigente: VIGENTE, expected_version: 1, historial: [VIGENTE], observacion_activa_desde: '2026-09-06T22:29:00Z', puede_publicar: true }

describe('ConfigRentabilidad (R3)', () => {
  beforeEach(() => { dobles.consulta = { data: DATA, isPending: false, isError: false }; dobles.publicar.mockReset(); dobles.yo = { id: 'g-1', rol: 'gerencia', demo: false } })

  it('muestra la política vigente y su historial; publicar se habilita solo con cambios', async () => {
    render(<ConfigRentabilidad />)
    expect(screen.getByText('Versión 1')).toBeInTheDocument()
    expect((screen.getByLabelText('Tasa base · primera inversión (%)') as HTMLInputElement).value).toBe('15')
    expect(screen.getByRole('list', { name: 'Versiones de la política de rentabilidad' })).toHaveTextContent(/v1 · base 15% · tope 50% · 7 días · Observación/)
    const publicar = screen.getByRole('button', { name: /Publicar nueva versión/ })
    expect(publicar).toBeDisabled()
    fireEvent.change(screen.getByLabelText('Tasa base · primera inversión (%)'), { target: { value: '16' } })
    await waitFor(() => expect(publicar).toBeEnabled())
  })

  it('valida antes de confirmar y publica con control de versión', async () => {
    const { toast } = await import('sonner')
    dobles.publicar.mockResolvedValue({ ...VIGENTE, version: 2, tasa_base_nueva: 16 })
    render(<ConfigRentabilidad />)
    fireEvent.change(screen.getByLabelText('Tasa base · primera inversión (%)'), { target: { value: '60' } })
    fireEvent.click(screen.getByRole('button', { name: /Publicar nueva versión/ }))
    expect(vi.mocked(toast.error)).toHaveBeenCalledWith(expect.stringMatching(/entre 0 y 50/))
    fireEvent.change(screen.getByLabelText('Tasa base · primera inversión (%)'), { target: { value: '16' } })
    fireEvent.click(screen.getByRole('button', { name: /Publicar nueva versión/ }))
    fireEvent.click(screen.getByRole('button', { name: 'Publicar' }))
    await waitFor(() => expect(dobles.publicar).toHaveBeenCalledWith({ expectedVersion: 1, tasaBaseNueva: 16, topeTecnico: 50, vigenciaSolicitudDias: 7, modo: 'observacion', nota: null }))
  })

  it('sin permiso de publicar, todo en solo lectura', () => {
    dobles.consulta = { data: { ...DATA, puede_publicar: false }, isPending: false, isError: false }
    render(<ConfigRentabilidad />)
    expect(screen.queryByRole('button', { name: /Publicar nueva versión/ })).toBeNull()
    expect(screen.getByLabelText('Tasa base · primera inversión (%)')).toHaveAttribute('readonly')
  })

  it('en demo no consulta y lo dice', () => {
    dobles.yo = { ...dobles.yo, demo: true }
    dobles.consulta = { data: undefined, isPending: true, isError: false }
    render(<ConfigRentabilidad />)
    expect(screen.getByRole('status')).toHaveTextContent(/En demo no hay política/)
  })

  it('R4: Gerencia enciende el candado del servidor eligiendo «Candado activo» y confirmando', async () => {
    dobles.publicar.mockResolvedValue({ ...VIGENTE, version: 2, modo: 'enforcement' })
    render(<ConfigRentabilidad />)
    // Publicar está deshabilitado hasta que algo cambia: el modo cuenta como cambio.
    expect(screen.getByRole('button', { name: /Publicar nueva versión/ })).toBeDisabled()
    // El grupo va nombrado y el nombre de cada botón es SOLO su título (la explicación es descripción).
    expect(screen.getByRole('group', { name: /Candado de la tasa en el servidor/ })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Candado activo' }))
    expect(screen.getByRole('button', { name: 'Candado activo' })).toHaveAttribute('aria-pressed', 'true')
    expect(screen.getByRole('button', { name: 'Observación' })).toHaveAttribute('aria-pressed', 'false')
    // El aviso se ve y, además, se anuncia por la ÚNICA región viva de la pantalla.
    expect(screen.getAllByText(/se rechazará al guardar/)).toHaveLength(2)
    expect(screen.getByRole('status')).toHaveTextContent(/Elegido «Candado activo»/)
    fireEvent.click(screen.getByRole('button', { name: /Publicar nueva versión/ }))
    expect(screen.getByText(/Enciendes el candado del servidor/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /^Publicar$/ }))
    await waitFor(() => expect(dobles.publicar).toHaveBeenCalledWith({ expectedVersion: 1, tasaBaseNueva: 15, topeTecnico: 50, vigenciaSolicitudDias: 7, modo: 'enforcement', nota: null }))
  })

  it('R4: con el candado ya activo, la pantalla lo dice y APAGARLO avisa en las dos vías', async () => {
    dobles.consulta = { data: { ...DATA, vigente: { ...VIGENTE, modo: 'enforcement' }, historial: [{ ...VIGENTE, modo: 'enforcement' }] }, isPending: false, isError: false }
    dobles.publicar.mockResolvedValue({ ...VIGENTE, version: 2, modo: 'observacion' })
    render(<ConfigRentabilidad />)
    expect(screen.getByText('Candado activo: el servidor rechaza')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Candado activo' })).toHaveAttribute('aria-pressed', 'true')
    expect(screen.getByRole('button', { name: 'Observación' })).toHaveAttribute('aria-pressed', 'false')
    fireEvent.click(screen.getByRole('button', { name: 'Observación' }))
    expect(screen.getByRole('status')).toHaveTextContent(/queda apagado/)
    expect(screen.getAllByText(/queda apagado/)).toHaveLength(2)
    fireEvent.click(screen.getByRole('button', { name: /Publicar nueva versión/ }))
    expect(screen.getByText(/Apagas el candado/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /^Publicar$/ }))
    await waitFor(() => expect(dobles.publicar).toHaveBeenCalledWith({ expectedVersion: 1, tasaBaseNueva: 15, topeTecnico: 50, vigenciaSolicitudDias: 7, modo: 'observacion', nota: null }))
  })

  it('R4: siempre hay exactamente un modo elegido, y sin permiso el interruptor no cambia', () => {
    dobles.consulta = { data: { ...DATA, puede_publicar: false }, isPending: false, isError: false }
    render(<ConfigRentabilidad />)
    const chips = screen.getAllByRole('button').filter((b) => b.hasAttribute('aria-pressed'))
    expect(chips).toHaveLength(2)
    expect(chips.filter((b) => b.getAttribute('aria-pressed') === 'true')).toHaveLength(1)
    const candado = screen.getByRole('button', { name: 'Candado activo' })
    expect(candado).toHaveAttribute('aria-disabled', 'true')
    // aria-disabled no lo bloquea el navegador: lo guarda el handler.
    fireEvent.click(candado)
    expect(candado).toHaveAttribute('aria-pressed', 'false')
    expect(chips.filter((b) => b.getAttribute('aria-pressed') === 'true')).toHaveLength(1)
  })
})

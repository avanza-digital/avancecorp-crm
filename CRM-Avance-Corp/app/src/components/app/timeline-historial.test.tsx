import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import { StoreDataContext } from '@/lib/store-context'
import type { StoreDataApi } from '@/lib/store'
import type { Actividad, Lead } from '@/lib/tipos'
import * as crmApi from '@/data/crm-api'
import { Timeline } from './lead-drawer'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))
vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return { ...actual, listarActividadesDeLead: vi.fn() }
})
const listar = vi.mocked(crmApi.listarActividadesDeLead)

const LEAD: Lead = {
  id: 'lead-historial-1',
  nombre_completo: 'ANA HISTORIAL PRUEBA',
  telefono: '+51987654321',
  correo: null,
  etapa: 'contactado',
  origen: 'landing',
  monto_estimado: 5_000,
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

// Sesión REAL (demo=false): el timeline se pide al servidor (mockeado).
const SESION: AuthContextValue = {
  fase: 'listo',
  yo: { id: 'vendedor-1', nombre_completo: 'ANALISTA PRUEBA', rol: 'vendedor', demo: false, puede_contratar: true },
  error: null,
  entrar: async () => ({ ok: true }),
  entrarDemo: () => undefined,
  reintentar: () => undefined,
  salir: async () => undefined,
}

const SENALES = { tieneReunionRealizada: false, tieneContacto: true, ultimaConversacionEn: null }
const act = (id: string, creado_en: string): Actividad => ({
  id, lead_id: LEAD.id, tipo: 'llamada_no_contestada', detalle: null, autor_nombre: 'ANALISTA PRUEBA', creado_en,
})

function montar({ componiendo = false, puedeRegistrarGestion = true }: { componiendo?: boolean; puedeRegistrarGestion?: boolean } = {}) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  const api = { actividadesDe: () => [], registrarActividad: vi.fn(() => ({ ok: true })) } as unknown as StoreDataApi
  render(
    <QueryClientProvider client={queryClient}>
      <AuthContext.Provider value={SESION}>
        <StoreDataContext.Provider value={api}>
          <Timeline l={LEAD} escribe activa puedeRegistrarGestion={puedeRegistrarGestion} componiendo={componiendo} setComponiendo={vi.fn()} />
        </StoreDataContext.Provider>
      </AuthContext.Provider>
    </QueryClientProvider>,
  )
}

beforeEach(() => vi.clearAllMocks())

describe('Timeline — historial por lead: estados honestos', () => {
  it('no deja rastro del acceso rápido y coloca el historial justo debajo del título', () => {
    listar.mockReturnValueOnce(new Promise(() => undefined))

    montar()

    expect(screen.queryByRole('button', { name: /Registrar actividad/i })).not.toBeInTheDocument()
    expect(screen.queryByText('Registrar actividad…')).not.toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Historial de actividades' })).toHaveClass('mt-2')
  })

  it('mantiene el composer disponible cuando una acción SLA del analista lo invoca', () => {
    listar.mockReturnValueOnce(new Promise(() => undefined))

    montar({ componiendo: true })

    expect(screen.getByLabelText('Tipo de actividad')).toBeInTheDocument()
    expect(screen.getByRole('textbox', { name: 'Detalle de la actividad' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Registrar' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Registrar actividad/i })).not.toBeInTheDocument()
  })

  it('supervisión no puede renderizar el composer aunque alguna ruta intente activarlo', () => {
    listar.mockReturnValueOnce(new Promise(() => undefined))

    montar({ componiendo: true, puedeRegistrarGestion: false })

    expect(screen.queryByLabelText('Tipo de actividad')).not.toBeInTheDocument()
    expect(screen.queryByRole('textbox', { name: 'Detalle de la actividad' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Registrar' })).not.toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Historial de actividades' })).toHaveClass('max-h-80', 'overflow-y-auto')
  })

  it('mientras carga: lista ocupada, anuncio de carga y NINGÚN «Lead creado» a secas como única señal', () => {
    listar.mockReturnValueOnce(new Promise(() => undefined))

    montar()

    const historial = screen.getByRole('region', { name: 'Historial de actividades' })
    expect(historial).toHaveClass('ac-scroll', 'max-h-80', 'overflow-y-auto', 'overscroll-contain')
    expect(screen.getByRole('list')).toHaveAttribute('aria-busy', 'true')
    expect(screen.getByRole('status')).toHaveTextContent('Cargando el historial…')
    expect(screen.queryByText('Sin gestiones todavía.')).not.toBeInTheDocument()
  })

  it('sin gestiones: lo dice, y «Lead creado» sigue como hito fijo', async () => {
    listar.mockResolvedValueOnce({ items: [], cursor: null, senales: SENALES })

    montar()

    expect(await screen.findByText('Sin gestiones todavía.')).toBeInTheDocument()
    expect(screen.getByText('Lead creado')).toBeInTheDocument()
    expect(screen.getByRole('list')).toHaveAttribute('aria-busy', 'false')
  })

  it('con fallo: alerta + Reintentar; al reintentar el foco se queda en la sección (no salta al tope del drawer)', async () => {
    const usuario = userEvent.setup()
    listar
      .mockRejectedValueOnce(new crmApi.CrmApiError('No se pudo cargar el historial del lead.', 'PGRST000'))
      .mockResolvedValueOnce({ items: [act('a-1', '2026-09-19T10:00:00.000Z')], cursor: null, senales: SENALES })

    montar()

    expect(await screen.findByRole('alert')).toHaveTextContent('No se pudo cargar el historial de este lead.')
    await usuario.click(screen.getByRole('button', { name: 'Reintentar' }))

    expect(screen.getByRole('region', { name: 'Actividad del lead' })).toHaveFocus()
    expect(await screen.findByText('Llamada no contestada')).toBeInTheDocument()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })

  it('«Cargar más gestiones» pide la siguiente página, conserva el foco y termina en «Historial completo» inerte', async () => {
    const usuario = userEvent.setup()
    listar
      .mockResolvedValueOnce({ items: [act('p1', '2026-09-19T10:00:00.000Z')], cursor: { creadoEn: '2026-09-19T10:00:00.000Z', id: 'p1' }, senales: SENALES })
      .mockResolvedValueOnce({ items: [act('p2', '2026-09-18T10:00:00.000Z')], cursor: null, senales: SENALES })

    montar()

    const boton = await screen.findByRole('button', { name: 'Cargar más gestiones' })
    expect(boton).not.toHaveAttribute('aria-disabled')
    await usuario.click(boton)

    await waitFor(() => expect(screen.getAllByText('Llamada no contestada')).toHaveLength(2))
    const completo = screen.getByRole('button', { name: 'Historial completo' })
    expect(completo).toHaveFocus()
    expect(completo).toHaveAttribute('aria-disabled', 'true')
    expect(screen.getByRole('status')).toHaveTextContent('2 gestiones cargadas')
    // Inerte de verdad: un clic más no vuelve a pedir nada.
    await usuario.click(completo)
    expect(listar).toHaveBeenCalledTimes(2)
  })

  it('si falla la SEGUNDA página no promete «Historial completo»: dice que no pudo cargar más', async () => {
    const usuario = userEvent.setup()
    listar
      .mockResolvedValueOnce({ items: [act('p1', '2026-09-19T10:00:00.000Z')], cursor: { creadoEn: '2026-09-19T10:00:00.000Z', id: 'p1' }, senales: SENALES })
      .mockRejectedValueOnce(new crmApi.CrmApiError('No se pudo cargar el historial del lead.', 'PGRST000'))

    montar()

    await usuario.click(await screen.findByRole('button', { name: 'Cargar más gestiones' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('No se pudo cargar el resto del historial.')
    expect(screen.getByRole('button', { name: 'No se pudo cargar más' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Historial completo' })).not.toBeInTheDocument()
    // La primera página sigue pintada: el fallo no borra lo que ya se sabe.
    expect(screen.getByText('Llamada no contestada')).toBeInTheDocument()
  })
})

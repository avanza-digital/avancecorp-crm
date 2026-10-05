import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { Lead } from '@/lib/tipos'
import type { PaginaCartera } from '@/data/crm-api'

const mocks = vi.hoisted(() => ({
  listar: vi.fn(), abrirLead: vi.fn(),
  yo: { id: 'v-1', demo: false },
  leads: [] as Lead[],
}))
vi.mock('@/lib/supabase', () => ({ sb: null }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: mocks.yo }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({ ambito: { leads: mocks.leads } }),
  usePanelesActions: () => ({ abrirLead: mocks.abrirLead }),
}))
vi.mock('@/data/crm-api', async (original) => ({
  ...await original<typeof import('@/data/crm-api')>(), listarCarteraPagina: mocks.listar,
}))
import { LeadsRecibidosHoy } from './leads-recibidos-hoy'

const AHORA = Date.parse('2026-10-05T15:00:00Z')
const clientes: QueryClient[] = []
function lead(id: string, extras: Partial<Lead> = {}): Lead {
  return { id, nombre_completo: `LEAD ${id}`, telefono: '+51987654321', etapa: 'nuevo', origen: 'landing',
    monto_estimado: 1000, moneda: 'PEN', vendedor_id: 'v-1', activo: true,
    creado_en: '2026-09-01T15:00:00Z', recibido_en: '2026-10-05T14:30:00Z', ...extras }
}
function pagina(items: Lead[], total = items.length, cursor: PaginaCartera['cursor'] = null): PaginaCartera {
  return { items, cursor, resumen: {
    totales: { vivos: total, abiertos: total, asignados: total, parkeados: 0, convertidos: 0, descartados: 0, asignados_pen: total, asignados_usd: 0 },
    capital: { asignado: { pen: 0, usd: 0 }, parkeado: { pen: 0, usd: 0 }, ganado: { pen: 0, usd: 0 } },
    embudo: [{ etapa: 'nuevo', n: total }],
  } }
}
function montar(ahora = AHORA) {
  const cliente = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  clientes.push(cliente)
  return render(<LeadsRecibidosHoy ahora={ahora} />, {
    wrapper: ({ children }) => <QueryClientProvider client={cliente}>{children}</QueryClientProvider>,
  })
}
beforeEach(() => {
  vi.clearAllMocks()
  vi.spyOn(Date, 'now').mockReturnValue(AHORA)
  mocks.yo = { id: 'v-1', demo: false }
  mocks.leads = []
})
afterEach(() => { clientes.splice(0).forEach(c => c.clear()); vi.restoreAllMocks() })

describe('Leads recibidos hoy', () => {
  it('consulta la recepción de Lima y el analista; muestra incluso creados antes y ya contactados', async () => {
    mocks.listar.mockResolvedValue(pagina([lead('recibido', { etapa: 'contactado', recepcion_aproximada: true })]))
    montar()
    const abrir = await screen.findByRole('button', { name: 'Abrir lead LEAD recibido' })
    expect(mocks.listar).toHaveBeenCalledWith(expect.objectContaining({
      integrada: true, vendedorId: 'v-1', etapa: 'todas', recepcion: { desde: '2026-10-05', hasta: '2026-10-05' },
    }), null, expect.any(AbortSignal))
    expect(screen.getByText('1 lead recibido hoy')).toBeInTheDocument()
    expect(abrir).toHaveAccessibleDescription('+51987654321 Recibido a las 09:30 aprox.')
    fireEvent.click(abrir)
    expect(mocks.abrirLead).toHaveBeenCalledWith('recibido')
  })

  it('el total incluye páginas pendientes y permite abrir los leads de la siguiente página', async () => {
    const cursor = { id: 'primero', actualizadoEn: '2026-10-05T14:00:00Z' }
    mocks.listar.mockResolvedValueOnce(pagina([lead('primero')], 2, cursor))
      .mockResolvedValueOnce(pagina([lead('segundo')], 2))
    montar()
    const cargarMas = await screen.findByRole('button', { name: 'Cargar más leads de hoy' })
    cargarMas.focus()
    fireEvent.click(cargarMas)
    await screen.findByRole('button', { name: 'Abrir lead LEAD segundo' })
    expect(screen.getByRole('button', { name: 'Abrir lead LEAD segundo' })).toHaveFocus()
    expect(mocks.listar).toHaveBeenLastCalledWith(expect.any(Object), cursor, expect.any(AbortSignal))
    expect(within(screen.getByRole('list')).getAllByRole('listitem')).toHaveLength(2)
    expect(screen.getByText('2 leads recibidos hoy')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Cargar más leads de hoy' })).not.toBeInTheDocument()
  })

  it('distingue carga, error y vacío real; reintentar recupera la lista', async () => {
    mocks.listar.mockRejectedValueOnce(new Error('sin conexión')).mockResolvedValue(pagina([]))
    montar()
    expect(screen.getByRole('status')).toHaveTextContent('Cargando leads')
    expect(await screen.findByRole('alert')).toHaveTextContent('No se pudieron cargar')
    expect(screen.queryByText('Todavía no has recibido leads hoy.')).not.toBeInTheDocument()
    expect(screen.queryByText('0 leads recibidos hoy')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(await screen.findByText('Todavía no has recibido leads hoy.')).toBeInTheDocument()
    expect(screen.getByText('0 leads recibidos hoy')).toBeInTheDocument()
  })

  it('renueva el día al cruzar medianoche de Lima, sin arrastrar filas de ayer', async () => {
    mocks.listar.mockResolvedValueOnce(pagina([lead('ayer')])).mockResolvedValueOnce(pagina([]))
    const antes = Date.parse('2026-10-06T04:59:00Z')
    vi.mocked(Date.now).mockReturnValue(antes)
    const vista = montar(antes)
    await screen.findByRole('button', { name: 'Abrir lead LEAD ayer' })
    const despues = Date.parse('2026-10-06T05:00:00Z')
    vi.mocked(Date.now).mockReturnValue(despues)
    vista.rerender(<LeadsRecibidosHoy ahora={despues} />)
    expect(screen.queryByRole('button', { name: 'Abrir lead LEAD ayer' })).not.toBeInTheDocument()
    await waitFor(() => expect(mocks.listar).toHaveBeenLastCalledWith(expect.objectContaining({
      recepcion: { desde: '2026-10-06', hasta: '2026-10-06' },
    }), null, expect.any(AbortSignal)))
    await screen.findByText('Todavía no has recibido leads hoy.')
  })

  it('en demo filtra recepción y titular, conserva gestionados y no consulta la red', () => {
    mocks.yo.demo = true
    mocks.leads = [
      lead('reasignado-hoy', { tenencia_desde: '2026-10-05T05:00:00Z', etapa: 'contactado' }),
      lead('ayer-lima', { creado_en: '2026-10-05T04:59:59Z' }),
      lead('otro-analista', { creado_en: '2026-10-05T12:00:00Z', vendedor_id: 'v-2' }),
      lead('baja', { creado_en: '2026-10-05T12:00:00Z', activo: false }),
    ]
    montar()
    expect(screen.getByRole('button', { name: 'Abrir lead LEAD reasignado-hoy' })).toBeInTheDocument()
    expect(within(screen.getByRole('list')).getAllByRole('listitem')).toHaveLength(1)
    expect(mocks.listar).not.toHaveBeenCalled()
    expect(screen.queryByRole('button', { name: 'Actualizar leads recibidos hoy' })).not.toBeInTheDocument()
  })

  it('conserva los recibidos hoy convertidos o descartados y muestra medianoche como 00:05', () => {
    mocks.yo.demo = true
    mocks.leads = [
      lead('convertido', { etapa: 'convertido', convertido_en: '2026-07-01T12:00:00Z', tenencia_desde: '2026-10-05T05:05:00Z' }),
      lead('descartado', { etapa: 'descartado', tenencia_desde: '2026-10-05T05:05:00Z' }),
    ]
    montar()
    expect(screen.getByText('2 leads recibidos hoy')).toBeInTheDocument()
    expect(within(screen.getByRole('list')).getAllByRole('listitem')).toHaveLength(2)
    expect(screen.getByRole('button', { name: 'Abrir lead LEAD convertido' })).toHaveAccessibleDescription('+51987654321 Recibido a las 00:05')
  })

  it('si falla la siguiente página, mantiene los leads cargados y permite reintentar', async () => {
    mocks.listar.mockResolvedValueOnce(pagina([lead('primero')], 2, { id: 'primero', actualizadoEn: '2026-10-05T14:00:00Z' }))
      .mockRejectedValueOnce(new Error('segunda página caída')).mockResolvedValue(pagina([lead('primero'), lead('segundo')]))
    montar()
    fireEvent.click(await screen.findByRole('button', { name: 'Cargar más leads de hoy' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Se conserva la última lista cargada.')
    expect(screen.getByRole('button', { name: 'Abrir lead LEAD primero' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    await screen.findByRole('button', { name: 'Abrir lead LEAD segundo' })
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })

  it('consulta nuevas asignaciones cada minuto visible y retira el intervalo al salir', async () => {
    const reloj = vi.spyOn(window, 'setInterval')
    const limpiar = vi.spyOn(window, 'clearInterval')
    const visibilidad = vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible')
    mocks.listar.mockResolvedValueOnce(pagina([lead('primero')])).mockResolvedValue(pagina([lead('primero'), lead('nuevo')]))
    const vista = montar()
    await screen.findByRole('button', { name: 'Abrir lead LEAD primero' })
    const i = reloj.mock.calls.findIndex(([, ms]) => ms === 60_000)
    const tick = reloj.mock.calls[i]?.[0]
    if (typeof tick !== 'function') throw new Error('Falta el sondeo de un minuto')
    visibilidad.mockReturnValue('hidden')
    await act(async () => { tick() })
    expect(mocks.listar).toHaveBeenCalledTimes(1)
    visibilidad.mockReturnValue('visible')
    await act(async () => { tick() })
    await screen.findByRole('button', { name: 'Abrir lead LEAD nuevo' })
    expect(mocks.listar).toHaveBeenCalledTimes(2)
    vista.unmount()
    expect(limpiar).toHaveBeenCalledWith(reloj.mock.results[i]?.value)
  })
})

import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { Actividad, Lead } from '@/lib/tipos'
import type { PaginaCartera } from '@/data/crm-api'
import { crmQueryKeys } from '@/data/crm-queries'

const mocks = vi.hoisted(() => ({
  listar: vi.fn(), pendientes: vi.fn(), abrirLead: vi.fn(),
  yo: { id: 'v-1', demo: false },
  leads: [] as Lead[], actividades: [] as Actividad[],
}))
vi.mock('@/lib/supabase', () => ({ sb: null }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: mocks.yo }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({ ambito: { leads: mocks.leads }, actividadesDelAmbito: mocks.actividades }),
  usePanelesActions: () => ({ abrirLead: mocks.abrirLead }),
}))
vi.mock('@/data/crm-api', async (original) => ({
  ...await original<typeof import('@/data/crm-api')>(),
  listarCarteraPagina: (...args: unknown[]) => (args[0] as { gestion?: string }).gestion === 'sin_gestion'
    ? mocks.pendientes(...args) : mocks.listar(...args),
}))
import { LeadsRecibidosHoy } from './leads-recibidos-hoy'
import { AgendaLeadsHoy } from './agenda-leads-hoy'

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
function montar(ahora = AHORA, conPestanas = false) {
  const cliente = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  clientes.push(cliente)
  return render(conPestanas ? <AgendaLeadsHoy ahora={ahora} agenda={<p>Agenda visible</p>} /> : <LeadsRecibidosHoy ahora={ahora} />, {
    wrapper: ({ children }) => <QueryClientProvider client={cliente}>{children}</QueryClientProvider>,
  })
}
beforeEach(() => {
  vi.clearAllMocks()
  vi.spyOn(Date, 'now').mockReturnValue(AHORA)
  mocks.yo = { id: 'v-1', demo: false }
  mocks.leads = []
  mocks.actividades = []
  mocks.pendientes.mockReset().mockResolvedValue(pagina([]))
})

describe('Agenda y contador de recibidos hoy', () => {
  it('una etapa heredada no acredita gestión del titular actual ni cambia su etiqueta', async () => {
    mocks.listar.mockResolvedValue(pagina([lead('reasignado', {
      etapa: 'contactado', tenencia_desde: '2026-10-05T14:30:00Z',
      ultimo_contacto_en: '2026-10-04T14:30:00Z', gestion_vigente: false,
    })]))
    mocks.pendientes.mockResolvedValue(pagina([], 1))
    montar(AHORA, true)
    fireEvent.click(await screen.findByRole('tab', { name: 'Leads de hoy 1 sin gestionar' }))
    expect(within(screen.getByRole('button', { name: 'Abrir lead LEAD reasignado' })).getByText('Contactado')).toBeVisible()
    expect(screen.getByRole('tab', { name: 'Leads de hoy 1 sin gestionar' })).toHaveAttribute('aria-selected', 'true')
  })

  it('un fallo del conteo conserva la lista y no inventa cero; reintentar recupera ambos', async () => {
    mocks.listar.mockResolvedValue(pagina([lead('recibido')], 12))
    mocks.pendientes.mockRejectedValueOnce(new Error('sin conexión')).mockResolvedValue(pagina([], 4))
    montar(AHORA, true)
    fireEvent.click(screen.getByRole('tab', { name: 'Leads de hoy' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('No se pudo actualizar el número')
    expect(screen.getByRole('button', { name: 'Abrir lead LEAD recibido' })).toBeVisible()
    expect(screen.getByRole('tab', { name: 'Leads de hoy' }).querySelector('.hoy-leads-contador')).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    await screen.findByRole('tab', { name: 'Leads de hoy 4 sin gestionar' })
    expect(screen.getByText('12 leads recibidos hoy')).toBeInTheDocument()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })

  it('en demo cuenta toda la jornada y gestión vigente, excluye cerrados y restaura lo deshecho', () => {
    mocks.yo.demo = true
    mocks.leads = Array.from({ length: 60 }, (_, i) => lead(String(i), {
      tenencia_desde: '2026-10-05T14:00:00Z', etapa: i === 59 ? 'convertido' : 'nuevo',
    }))
    mocks.actividades = mocks.leads.slice(0, 51).map(l => ({
      id: `gestion-${l.id}`, lead_id: l.id, tipo: 'llamada_no_contestada', detalle: null,
      creado_en: '2026-10-05T14:30:00Z', autor_nombre: 'ANALISTA',
    }))
    const vista = montar(AHORA, true)
    fireEvent.click(screen.getByRole('tab', { name: 'Leads de hoy 8 sin gestionar' }))
    expect(within(screen.getByRole('list')).getAllByRole('listitem')).toHaveLength(50)
    expect(screen.getByText('60 leads recibidos hoy')).toBeInTheDocument()
    expect(within(screen.getByRole('button', { name: 'Abrir lead LEAD 0' })).getByText('Gestionado')).toBeVisible()
    mocks.actividades = mocks.actividades.map((a, i) => i === 0 ? { ...a, metadata: { deshecho_en: null } } : a)
    vista.rerender(<AgendaLeadsHoy ahora={AHORA} agenda={<p>Agenda visible</p>} />)
    expect(screen.getByRole('tab', { name: 'Leads de hoy 9 sin gestionar' })).toBeInTheDocument()
    expect(within(screen.getByRole('button', { name: 'Abrir lead LEAD 0' })).getByText('Nuevo')).toBeVisible()
    expect(mocks.listar).not.toHaveBeenCalled()
    expect(mocks.pendientes).not.toHaveBeenCalled()
  })

  it('el sondeo no cancela una página en vuelo ni pierde el foco de sus filas nuevas', async () => {
    mocks.pendientes.mockResolvedValue(pagina([], 2))
    const reloj = vi.spyOn(window, 'setInterval')
    vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible')
    let resolver!: (valor: PaginaCartera) => void
    const siguiente = new Promise<PaginaCartera>(res => { resolver = res })
    mocks.listar.mockResolvedValueOnce(pagina([lead('primero')], 2, { id: 'primero', actualizadoEn: '2026-10-05T14:00:00Z' }))
      .mockReturnValueOnce(siguiente)
    montar(AHORA, true)
    fireEvent.click(await screen.findByRole('tab', { name: 'Leads de hoy 2 sin gestionar' }))
    const cargar = screen.getByRole('button', { name: 'Cargar más leads de hoy' })
    cargar.focus()
    fireEvent.click(cargar)
    await waitFor(() => expect(cargar).toHaveAttribute('aria-disabled', 'true'))
    const tick = reloj.mock.calls.find(([, ms]) => ms === 60_000)?.[0]
    if (typeof tick !== 'function') throw new Error('Falta el sondeo de un minuto')
    await act(async () => { tick() })
    expect(mocks.listar).toHaveBeenCalledTimes(2)
    await act(async () => { resolver(pagina([lead('segundo')], 2)) })
    expect(await screen.findByRole('button', { name: 'Abrir lead LEAD segundo' })).toHaveFocus()
  })

  it('cuenta los sin gestionar de todas las páginas y no los borra solo por abrir lista o ficha', async () => {
    const pendientes = pagina([], 60)
    pendientes.resumen!.totales.abiertos = 55 // Los otros cinco están cerrados.
    mocks.pendientes.mockResolvedValue(pendientes)
    mocks.listar.mockResolvedValue(pagina([lead('primero')], 100, { id: 'primero', actualizadoEn: '2026-10-05T14:00:00Z' }))
    montar(AHORA, true)
    const pestana = await screen.findByRole('tab', { name: 'Leads de hoy 55 sin gestionar' })
    expect(screen.getByText('Agenda visible')).toBeInTheDocument()
    expect(pestana.querySelector('[data-aviso="true"]')).not.toBeNull()
    fireEvent.click(pestana)
    expect(pestana).toHaveAttribute('aria-selected', 'true')
    fireEvent.click(screen.getByRole('button', { name: 'Abrir lead LEAD primero' }))
    expect(mocks.abrirLead).toHaveBeenCalledWith('primero')
    expect(pestana).toHaveTextContent('55')
    expect(screen.getByText('100 leads recibidos hoy')).toBeInTheDocument()
    expect(mocks.pendientes).toHaveBeenCalledWith(expect.objectContaining({
      gestion: 'sin_gestion', vendedorId: 'v-1', etapa: 'todas', recepcion: { desde: '2026-10-05', hasta: '2026-10-05' },
    }), null, expect.any(AbortSignal))
    expect(pestana.querySelector('[data-aviso="true"]')).not.toBeNull()
    fireEvent.keyDown(pestana, { key: 'ArrowLeft' })
    expect(screen.getByRole('tab', { name: 'Tu agenda de hoy' })).toHaveFocus()
    fireEvent.keyDown(screen.getByRole('tab', { name: 'Tu agenda de hoy' }), { key: 'ArrowRight' })
    expect(pestana).toHaveFocus()
    expect(mocks.listar).toHaveBeenCalledTimes(1)
  })

  it('recibe nuevas asignaciones con la agenda abierta y comparte la lista ya actualizada', async () => {
    mocks.pendientes.mockResolvedValueOnce(pagina([], 1)).mockResolvedValue(pagina([], 2))
    const reloj = vi.spyOn(window, 'setInterval')
    vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible')
    mocks.listar.mockResolvedValueOnce(pagina([lead('primero')])).mockResolvedValue(pagina([lead('primero'), lead('nuevo')]))
    montar(AHORA, true)
    await screen.findByRole('tab', { name: 'Leads de hoy 1 sin gestionar' })
    expect(screen.queryByRole('region', { name: 'Leads recibidos hoy' })).not.toBeInTheDocument()
    const intervalos = reloj.mock.calls.filter(([, ms]) => ms === 60_000)
    expect(intervalos).toHaveLength(1)
    const tick = intervalos[0]?.[0]
    if (typeof tick !== 'function') throw new Error('Falta el sondeo de un minuto')
    await act(async () => { tick() })
    const pestana = await screen.findByRole('tab', { name: 'Leads de hoy 2 sin gestionar' })
    expect(screen.getByText('Agenda visible')).toBeInTheDocument()
    fireEvent.click(pestana)
    expect(screen.getByRole('button', { name: 'Abrir lead LEAD nuevo' })).toBeInTheDocument()
    expect(mocks.listar).toHaveBeenCalledTimes(2)
  })

  it('no presenta el error como cero y el vacío confirmado no lleva aviso', async () => {
    mocks.listar.mockRejectedValueOnce(new Error('sin conexión')).mockResolvedValue(pagina([]))
    montar(AHORA, true)
    fireEvent.click(screen.getByRole('tab', { name: 'Leads de hoy' }))
    await screen.findByRole('alert')
    expect(screen.getByRole('tab', { name: 'Leads de hoy' }).querySelector('.hoy-leads-contador')).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    const pestana = await screen.findByRole('tab', { name: 'Leads de hoy 0 sin gestionar' })
    expect(pestana.querySelector('[data-aviso="true"]')).toBeNull()
    expect(screen.getByText('Todavía no has recibido leads hoy.')).toBeInTheDocument()
  })

  it('cambia contador y consulta al cruzar el día de Lima o cambiar de analista', async () => {
    mocks.pendientes.mockResolvedValueOnce(pagina([], 7)).mockResolvedValue(pagina([]))
    mocks.listar.mockResolvedValueOnce(pagina([lead('ayer')], 7)).mockResolvedValue(pagina([]))
    const antes = Date.parse('2026-10-06T04:59:00Z')
    vi.mocked(Date.now).mockReturnValue(antes)
    const vista = montar(antes, true)
    await screen.findByRole('tab', { name: 'Leads de hoy 7 sin gestionar' })
    const despues = Date.parse('2026-10-06T05:00:00Z')
    vi.mocked(Date.now).mockReturnValue(despues)
    vista.rerender(<AgendaLeadsHoy ahora={despues} agenda={<p>Agenda visible</p>} />)
    expect(screen.queryByRole('tab', { name: 'Leads de hoy 7 sin gestionar' })).not.toBeInTheDocument()
    await screen.findByRole('tab', { name: 'Leads de hoy 0 sin gestionar' })
    expect(mocks.listar).toHaveBeenLastCalledWith(expect.objectContaining({ recepcion: { desde: '2026-10-06', hasta: '2026-10-06' } }), null, expect.any(AbortSignal))
    mocks.yo = { id: 'v-2', demo: false }
    mocks.pendientes.mockResolvedValue(pagina([], 2))
    mocks.listar.mockResolvedValue(pagina([lead('otro-titular', { vendedor_id: 'v-2' })], 2))
    vista.rerender(<AgendaLeadsHoy ahora={despues} agenda={<p>Agenda visible</p>} />)
    expect(screen.queryByRole('tab', { name: 'Leads de hoy 0 sin gestionar' })).not.toBeInTheDocument()
    await screen.findByRole('tab', { name: 'Leads de hoy 2 sin gestionar' })
    expect(mocks.listar).toHaveBeenLastCalledWith(expect.objectContaining({ vendedorId: 'v-2' }), null, expect.any(AbortSignal))
  })
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
    expect(abrir).toHaveAccessibleDescription('+51987654321 Etapa actual: Contactado Recibido a las 09:30 aprox.')
    fireEvent.click(abrir)
    expect(mocks.abrirLead).toHaveBeenCalledWith('recibido')
  })

  it('al gestionar baja el aviso a cero y conserva el recibido con su etapa actual', async () => {
    mocks.pendientes.mockResolvedValue(pagina([], 1))
    const recibido = lead('en-gestion', { tenencia_desde: '2026-10-05T14:30:00Z', gestion_vigente: false })
    mocks.listar.mockResolvedValue(pagina([recibido]))
    montar(AHORA, true)
    fireEvent.click(await screen.findByRole('tab', { name: 'Leads de hoy 1 sin gestionar' }))
    const fila = screen.getByRole('button', { name: 'Abrir lead LEAD en-gestion' })
    expect(within(fila).getByText('Nuevo')).toBeVisible()
    const cliente = clientes.at(-1)!

    // La misma invalidación usada al guardar/refrescar datos actualiza la
    // etiqueta y el contador sin remontar el panel ni perder el recibido.
    for (const [etapa, gestion, etiqueta] of [
      ['nuevo', true, 'Gestionado'],
      ['contactado', true, 'Contactado'],
      ['reunion_agendada', true, 'Cita agendada'],
      ['propuesta_enviada', true, 'Entrevista realizada'],
      ['convertido', true, 'Convertido'],
      ['descartado', true, 'Descartado'],
    ] as const) {
      mocks.listar.mockResolvedValue(pagina([{ ...recibido, etapa, gestion_vigente: gestion }]))
      mocks.pendientes.mockResolvedValue(pagina([]))
      await act(async () => { await cliente.invalidateQueries({ queryKey: crmQueryKeys.carteraPaginas() }) })
      await waitFor(() => expect(within(fila).getByText(etiqueta)).toBeVisible())
      const pestana = screen.getByRole('tab', { name: 'Leads de hoy 0 sin gestionar' })
      expect(pestana).toHaveAttribute('aria-selected', 'true')
      expect(pestana.querySelector('[data-aviso="true"]')).toBeNull()
      expect(screen.getByText('1 lead recibido hoy')).toBeInTheDocument()
      expect(within(screen.getByRole('list')).getAllByRole('listitem')).toHaveLength(1)
    }
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
    expect(screen.getByRole('button', { name: 'Abrir lead LEAD convertido' })).toHaveAccessibleDescription('+51987654321 Etapa actual: Convertido Recibido a las 00:05')
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

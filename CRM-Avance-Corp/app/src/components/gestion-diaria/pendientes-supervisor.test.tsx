import { fireEvent, render, screen, within } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { filaEquipoPrueba } from '@/lib/gestion-diaria-equipo.fixture'
import { paginaPendientes, pedidoPendientes, tareaPendiente } from '@/lib/gestion-diaria-pendientes.fixture'
import type { usePendientesSupervisor } from '@/data/gestion-diaria-pendientes-queries'
import { CrmApiError } from '@/data/crm-api'
const dobles = vi.hoisted(() => ({ lista: {} as ReturnType<typeof usePendientesSupervisor>, hook: vi.fn(), abrir: vi.fn(), recargar: vi.fn(), mas: vi.fn() }))
vi.mock('@/data/gestion-diaria-pendientes-queries', () => ({ usePendientesSupervisor: (...args: unknown[]) => { dobles.hook(...args); return dobles.lista } }))
vi.mock('@/lib/store-context', () => ({ usePanelesActions: () => ({ abrirLead: dobles.abrir }) }))
const { PendientesSupervisor } = await import('./pendientes-supervisor')
const revalidar = vi.fn()
const props = { analista: pedidoPendientes.analista, nombre: 'ANA', dia: '2026-09-23', fila: filaEquipoPrueba({ tareas_pendientes: 1008, tareas_vencidas: 1007 }),
  visible: true, soloVencidasInicial: false, apertura: 0, enfocar: false, actualizacion: 0, revalidar }
beforeEach(() => {
  vi.clearAllMocks()
  dobles.lista = { items: [tareaPendiente()], pagina: paginaPendientes(), congelada: false, consultadoDesde: '2026-09-23T17:00:00Z', cargando: false,
    enVuelo: false, error: null, sinPermiso: false, hayMas: false, cargarMas: dobles.mas, recargar: dobles.recargar }
})
describe('Lista útil de pendientes', () => {
  it('respeta las tres referencias, oculta fichas sin acceso y usa título alternativo', () => {
    dobles.lista.items = [tareaPendiente(10), tareaPendiente(11, { titulo: '', lead_id: null, lead_nombre: null }),
      tareaPendiente(12, { referencia_tipo: 'perfil', lead_id: null, lead_nombre: null }), tareaPendiente(13, { referencia_tipo: 'postventa', lead_id: null, lead_nombre: null })]
    render(<PendientesSupervisor {...props} />)
    expect(screen.getByText('Sin título')).toBeVisible()
    for (const texto of ['Referencia no disponible','Tarea de perfil','Tarea de postventa']) expect(screen.getByText(texto)).toBeVisible()
    expect(within(screen.getByRole('list', { name: 'Lista de tareas pendientes' })).getAllByRole('button')).toHaveLength(1)
    fireEvent.click(screen.getByRole('button', { name: 'Lead visible' })); expect(dobles.abrir).toHaveBeenCalledWith(tareaPendiente().lead_id)
  })
  it.each(['PGRST202','XX000','42501'])('distingue %s de un vacío confirmado', codigo => {
    dobles.lista = { ...dobles.lista, items: [], pagina: null, error: new CrmApiError('error',codigo), sinPermiso: codigo==='42501' }
    render(<PendientesSupervisor {...props} />)
    expect(screen.getByRole('alert')).toBeVisible()
    expect(screen.queryByText('Sin tareas pendientes.')).not.toBeInTheDocument()
    if(codigo==='PGRST202') expect(screen.getByText('1008')).toBeVisible()
    if(codigo==='42501') { expect(screen.queryByText('1008')).not.toBeInTheDocument(); expect(revalidar).toHaveBeenCalledOnce() }
  })
  it('informa página congelada y datos anteriores; filtros y refresco externo conservan foco', () => {
    dobles.lista.congelada = true; dobles.lista.error = new Error('sin red')
    const vista=render(<PendientesSupervisor {...props} />)
    expect(screen.getByText(/Datos anteriores/)).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: /^Vencidas/ }))
    expect(dobles.hook).toHaveBeenLastCalledWith(props.dia,props.analista,true,true,0)
    const filtro=screen.getByRole('button', { name: /^Vencidas/ }); filtro.focus()
    vista.rerender(<PendientesSupervisor {...props} actualizacion={1} />)
    expect(dobles.recargar).toHaveBeenCalledOnce(); expect(filtro).toHaveFocus(); expect(filtro).toHaveAttribute('aria-pressed','true')
  })
  it('como el resumen: dos cuadros con número que filtran, la vencida se marca y el título no repite el lead (Miguel, 27/09)', () => {
    dobles.lista.items = [
      tareaPendiente(20, { tipo: 'whatsapp', titulo: 'WhatsApp — LEAD VISIBLE', vence_en: '2026-09-23T16:00:00.000001+00:00' }),
      tareaPendiente(21, { titulo: 'Responder propuesta — Lead', vence_en: '2026-09-23T18:00:00.000001+00:00' }),
    ]
    dobles.lista.pagina = paginaPendientes(dobles.lista.items, { resumen: { tareas_pendientes: 5, tareas_vencidas: 2 } })
    render(<PendientesSupervisor {...props} />)
    const filtro = screen.getByRole('group', { name: 'Filtro de tareas' })
    expect(within(filtro).getByRole('button', { name: /^Todas 5$/ })).toHaveAttribute('aria-pressed', 'true')
    fireEvent.click(within(filtro).getByRole('button', { name: /^Vencidas 2$/ }))
    expect(dobles.hook).toHaveBeenLastCalledWith(props.dia, props.analista, true, true, 0)
    const [primera, segunda] = within(screen.getByRole('list', { name: 'Lista de tareas pendientes' })).getAllByRole('listitem')
    // Vence antes del corte de la consulta (17:00 UTC): vencida. La otra, después: no.
    expect(within(primera!).getByText('Vencida')).toBeVisible()
    expect(within(segunda!).queryByText('Vencida')).not.toBeInTheDocument()
    // «WhatsApp — LEAD VISIBLE» ya lo dicen el tipo y el lead: sin título repetido.
    expect(within(primera!).queryByText(/WhatsApp —/)).not.toBeInTheDocument()
    expect(within(segunda!).getByText('Responder propuesta')).toBeVisible()
    expect(screen.getByRole('heading', { name: 'Pendientes de ANA' })).toBeInTheDocument()
  })
  it('las señales de leads solo aparecen con número confirmado mayor que cero', () => {
    const vista = render(<PendientesSupervisor {...props} fila={filaEquipoPrueba({ primer_intento_vencido: 3, datos_incompletos: null })} />)
    expect(within(screen.getByRole('list', { name: 'Leads por revisar' })).getByText('3 leads con el primer intento tarde')).toBeVisible()
    expect(screen.queryByText(/datos por revisar/)).not.toBeInTheDocument()
    vista.rerender(<PendientesSupervisor {...props} fila={filaEquipoPrueba({ primer_intento_vencido: null, datos_incompletos: 0 })} />)
    expect(screen.queryByRole('list', { name: 'Leads por revisar' })).not.toBeInTheDocument()
    expect(screen.queryByText(/no evaluado/)).not.toBeInTheDocument()
  })
})

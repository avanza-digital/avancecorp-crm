import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ColaSlaPanel, DetalleSla, SlaOperacionBoundary } from './sla-operacion'
import type { ColaSlaPagina, EstadoSlaV2 } from '@/lib/sla-operacion'
import { useColaSlaPagina, useModoSla } from '@/data/sla-operacion-queries'
const abrir = vi.fn()
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: { id: 'actor', rol: 'supervisor', demo: false } }) }))
vi.mock('@/lib/store-context', () => ({ useCRMData: () => ({ equipo: [{ perfil_id: 'analista', nombre_completo: 'Analista Uno', activo: true }] }), usePanelesActions: () => ({ abrirLead: abrir }) }))
vi.mock('@/data/sla-operacion-queries', () => ({
  slaOperacionKeys: { raiz: () => ['crm', 'metricas-ambito', 'sla-v2'] },
  useColaSlaPagina: vi.fn(), useModoSla: vi.fn(), useEstadosSlaV2: vi.fn(),
}))
const consulta = vi.mocked(useColaSlaPagina)
const modo = vi.mocked(useModoSla)
const estado: EstadoSlaV2 = {
  lead_id: 'l1', evaluacion: 'completa', motivos_datos: [],
  seguimiento: { referencia_en: null, ultima_gestion_en: null, limite_en: '2026-09-07T10:00:00Z', vencido: true, accion_pendiente: true },
  compromiso: { tarea: null, validez: 'sin_tarea', hasta_en: null, cobertura_activa: false },
  etapa: { limite_original_en: '2026-09-07T10:00:00Z', limite_prorrogado_en: '2026-09-07T10:00:00Z', limite_operativo_en: '2026-09-07T10:00:00Z', techo_en: '2026-09-09T10:00:00Z', prorrogas_usadas: 0, prorrogas_restantes: 2, revision_requerida: true, motivos_revision: ['limite_operativo_agotado'] },
}
const primera: ColaSlaPagina = {
  version: 2, modo: 'activo', control_revision: 1, calculado_en: '2026-09-07T10:00:00Z', filtros: { senal: 'todas', etapa: null, analista_id: null },
  limite: 10, total_items: 455, hay_mas: true, rango: { desde: 1, hasta: 10 }, cursor_siguiente: { token: 'pagina2' },
  totales: { primera_atencion: 527, tareas_vencidas: 538, seguimientos_pendientes: 527, revisiones: 455, datos_incompletos: 0, por_repartir: 3 },
  items: [{ lead_id: 'l1', bucket: 'primera_atencion', severidad: 'critica', prioridad: 10, referencia_en: '2026-09-07T10:00:00Z', tarea_id: null,
    lead: { id: 'l1', nombre_completo: 'Oportunidad Uno', etapa: 'contactado', analista_id: 'analista', analista_nombre: 'Analista Uno' },
    senales: { primera_atencion: true, tareas_vencidas: false, seguimientos_pendientes: true, revisiones: true, datos_incompletos: false, por_repartir: false }, estado }],
}
const segunda: ColaSlaPagina = { ...primera, rango: { desde: 11, hasta: 11 }, hay_mas: false, cursor_siguiente: null, items: [{ ...primera.items[0]!, lead_id: 'l2', lead: { ...primera.items[0]!.lead, id: 'l2', nombre_completo: 'Oportunidad Dos' } }] }
function resultado(data: ColaSlaPagina | undefined, error: Error | null = null, isFetching = false) {
  return { data, error, isFetching, refetch: vi.fn() } as unknown as ReturnType<typeof useColaSlaPagina>
}
function montar(elemento = <ColaSlaPanel />) {
  const cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return { ...render(<QueryClientProvider client={cliente}>{elemento}</QueryClientProvider>), cliente }
}
beforeEach(() => {
  consulta.mockImplementation((_filtros, cursor) => resultado(cursor ? segunda : primera))
  modo.mockReturnValue({ legado: false, activo: true, error: null, data: { control_revision: 1 } } as ReturnType<typeof useModoSla>)
})
describe('cola SLA con páginas explícitas', () => {
  it('reemplaza las filas al avanzar y recupera la anterior sin acumular scroll', async () => {
    const usuario = userEvent.setup(); montar()
    expect(screen.getByRole('button', { name: 'Anterior' })).toBeDisabled()
    expect(screen.getByText(/1–10 de 455/)).toBeInTheDocument()
    await usuario.click(screen.getByRole('button', { name: 'Siguiente' }))
    expect(screen.queryByText('Oportunidad Uno')).not.toBeInTheDocument()
    expect(screen.getByText('Oportunidad Dos')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Siguiente' })).toBeDisabled()
    await usuario.click(screen.getByRole('button', { name: 'Anterior' }))
    expect(screen.getByText('Oportunidad Uno')).toBeInTheDocument()
    expect(screen.queryByText('Oportunidad Dos')).not.toBeInTheDocument()
  })
  it('cada filtro y el tamaño de página vuelven al primer cursor', async () => {
    const usuario = userEvent.setup(); montar()
    for (const [campo, valor] of [['Mostrar', 'revisiones'], ['Etapa', 'contactado'], ['Analista', 'analista'], ['Por página', '25']] as const) {
      await usuario.click(screen.getByRole('button', { name: 'Siguiente' }))
      await usuario.selectOptions(screen.getByRole('combobox', { name: campo }), valor!)
      expect(consulta.mock.lastCall?.[1]).toBeNull()
      expect(screen.getByRole('button', { name: 'Anterior' })).toBeDisabled()
    }
    expect(consulta.mock.lastCall?.[0]).toEqual({ senal: 'revisiones', etapa: 'contactado', analista_id: 'analista' })
    expect(consulta.mock.lastCall?.[2]).toBe(25)
  })
  it('muestra la revisión aunque primera atención tenga prioridad y usa totales completos', async () => {
    const usuario = userEvent.setup(); montar()
    const lista = screen.getByRole('list', { name: 'Oportunidades de esta página' })
    expect(within(lista).getByText('Primera atención')).toBeInTheDocument()
    expect(within(lista).getByText('Revisión comercial')).toBeInTheDocument()
    expect(screen.getByRole('option', { name: 'Revisión comercial (455)' })).toBeInTheDocument()
    await usuario.click(within(lista).getByRole('button'))
    expect(abrir).toHaveBeenCalledWith('l1')
  })
  it('no conserva filas antiguas ni afirma al día cuando falla un refetch', () => {
    consulta.mockReturnValue(resultado(primera, new Error('Conexión')))
    montar()
    expect(screen.getByRole('alert')).toHaveTextContent('pendientes todavía no están confirmados')
    expect(screen.queryByText('Oportunidad Uno')).not.toBeInTheDocument()
    expect(screen.queryByText(/de 455/)).not.toBeInTheDocument()
  })
  it('deshabilita navegación mientras consulta y distingue un filtro vacío', () => {
    consulta.mockReturnValue(resultado({ ...primera, items: [], total_items: 0, rango: { desde: 0, hasta: 0 }, hay_mas: false, cursor_siguiente: null }, null, true))
    montar()
    expect(screen.getByText(/No hay oportunidades con estos filtros/)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Siguiente' })).toBeDisabled()
  })
  it('el error del modo nunca cae silenciosamente a reglas antiguas', () => {
    modo.mockReturnValue({ legado: false, activo: false, error: new Error('Modo no disponible'), refetch: vi.fn() } as unknown as ReturnType<typeof useModoSla>)
    montar(<SlaOperacionBoundary legado={<p>Cola antigua</p>}><p>Cola nueva</p></SlaOperacionBoundary>)
    expect(screen.getByRole('alert')).toBeInTheDocument()
    expect(screen.queryByText('Cola antigua')).not.toBeInTheDocument()
    expect(screen.queryByText('Cola nueva')).not.toBeInTheDocument()
  })
  it('la ficha distingue compromiso cubierto y vencimiento de agenda', () => {
    montar(<DetalleSla estado={{ ...estado, compromiso: { tarea: { id: 't1', tipo: 'llamada', vence_en: '2026-09-07T10:00:00Z', reprogramaciones: 0 }, validez: 'valido', cobertura_activa: true, hasta_en: '2026-09-08T10:00:00Z' } }} />)
    expect(screen.getByText('Cubierto por compromiso')).toBeInTheDocument()
    expect(screen.getByText(/La tarea vence a su hora en Agenda/)).toBeInTheDocument()
    expect(screen.getByText('Revisión comercial pendiente')).toBeInTheDocument()
  })
})

import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { toast } from 'sonner'
import type { Lead, Tarea } from '@/lib/tipos'
import { ProximaAccion } from './lead-drawer'
const mocks = vi.hoisted(() => ({ tareas: [] as Tarea[], obtener: vi.fn(), refetch: vi.fn(), cerrar: vi.fn(), lectura: {} as Record<string, unknown> }))
vi.mock('sonner', () => ({ toast: { error: vi.fn(), success: vi.fn(), warning: vi.fn() } }))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: { id: 'actor', rol: 'vendedor' } }) }))
vi.mock('@/data/sla-operacion-queries', () => ({ useEstadosSlaV2: () => ({ data: mocks.lectura, refetch: mocks.refetch }) }))
vi.mock('@/lib/store-context', () => ({ useCRMData: () => ({ tareasDe: () => mocks.tareas, obtenerTareaParaRevision: mocks.obtener, actividadesDe: () => [] }) }))
vi.mock('@/components/app/cerrar-tarea', () => ({ CerrarTareaDialog: ({ tarea }: { tarea: Tarea | null }) => tarea ? <p role="dialog">Cierre {tarea.tipo}: {tarea.id}</p> : null }))
const proxima = { id: 'primera-servidor', tipo: 'llamada', titulo: 'WhatsApp programado', vence_en: '2026-09-08T15:00Z' }
const lead = { id: 'lead', nombre_completo: 'SINTETICO', etapa: 'contactado' } as Lead
const tarea = { ...proxima, lead_id: 'lead', activo: true, estado: 'pendiente', reprogramaciones: 0, prioridad: 'normal', vendedor_id: 'actor', creado_en: '2026-09-01T15:00Z' } as Tarea
beforeEach(() => {
  vi.clearAllMocks(); mocks.tareas = []
  mocks.lectura = { modo: 'activo', filas: [{ lead_id: 'lead', operacion: { modelo: 3, proxima_accion: proxima } }] }
  mocks.obtener.mockResolvedValue(tarea)
})
describe('próxima acción elegida por el servidor', () => {
  it('recupera por ID una tarea fuera del lote local y abre el cierre de su tipo real', async () => {
    const usuario = userEvent.setup(); render(<ProximaAccion l={lead} escribe activa />)
    expect(screen.getByText('WhatsApp programado')).toBeInTheDocument()
    expect(screen.queryByText(/sin próxima acción/i)).not.toBeInTheDocument()
    await usuario.click(screen.getByRole('button', { name: 'Revisar actividad' }))
    expect(mocks.obtener).toHaveBeenCalledWith('lead', 'primera-servidor')
    expect(screen.getByRole('dialog')).toHaveTextContent('Cierre llamada: primera-servidor')
  })
  it('ante tarea eliminada o pérdida de acceso no abre un cierre con datos inventados', async () => {
    mocks.obtener.mockResolvedValue(null)
    const usuario = userEvent.setup(); render(<ProximaAccion l={lead} escribe activa />)
    await usuario.click(screen.getByRole('button', { name: 'Revisar actividad' }))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(mocks.refetch).toHaveBeenCalled()
    expect(toast.error).toHaveBeenCalled()
  })
  it('la fecha y primera posición siguen al servidor aunque el lote local esté atrasado', async () => {
    mocks.tareas = [{ ...tarea, id: 'otra', titulo: 'Actividad secundaria' }, { ...tarea, titulo: 'Título viejo', vence_en: '2026-09-02Z' }]
    const usuario = userEvent.setup(); render(<ProximaAccion l={lead} escribe activa />)
    expect(screen.getAllByRole('listitem')[0]).toHaveTextContent('WhatsApp programado')
    expect(screen.queryByText('Título viejo')).not.toBeInTheDocument()
    await usuario.click(screen.getByRole('button', { name: 'Cerrar tarea — WhatsApp programado' }))
    expect(mocks.obtener).toHaveBeenCalledWith('lead', 'primera-servidor')
  })
  it('mantiene lectura sin botones de escritura para directorio', () => {
    render(<ProximaAccion l={lead} escribe={false} activa />)
    expect(screen.getByText('WhatsApp programado')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Revisar actividad' })).not.toBeInTheDocument()
  })
})

// Tests del diálogo de cierre: resultado 1-tap obligatorio, la sugerencia del
// motor aparece al elegir, "saltar" a un toque, y el payload que viaja al store.
import { describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { StoreDataContext } from '@/lib/store-context'
import type { StoreDataApi } from '@/lib/store'
import type { Lead, Tarea } from '@/lib/tipos'
import { CerrarTareaDialog } from './cerrar-tarea'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

const LEAD = {
  id: 'l1',
  nombre_completo: 'ANA TORRES QUISPE',
  telefono: '+51999888777',
  etapa: 'contactado',
  origen: 'oficina',
  monto_estimado: 50_000,
  moneda: 'PEN',
  creado_en: '2026-07-10T15:00:00.000Z',
  activo: true,
} as Lead

const TAREA: Tarea = {
  id: 't1',
  lead_id: 'l1',
  tipo: 'llamada',
  titulo: 'Llamar a Ana',
  vence_en: '2026-07-18T15:00:00.000Z',
  estado: 'pendiente',
  reprogramaciones: 0,
  activo: true,
  creado_en: '2026-07-17T15:00:00.000Z',
}

function montar(tarea: Tarea | null = TAREA) {
  const completarTarea = vi.fn<StoreDataApi['completarTarea']>(() => ({ ok: true }))
  const api = {
    lead: (id: string) => (id === LEAD.id ? LEAD : undefined),
    completarTarea,
  } as unknown as StoreDataApi
  const onCerrar = vi.fn()
  render(
    <StoreDataContext.Provider value={api}>
      <CerrarTareaDialog tarea={tarea} onCerrar={onCerrar} />
    </StoreDataContext.Provider>,
  )
  return { completarTarea, onCerrar }
}

describe('CerrarTareaDialog', () => {
  it('una llamada NO se puede cerrar sin resultado (botón deshabilitado)', () => {
    montar()
    expect(screen.getByRole('button', { name: /cerrar tarea/i })).toBeDisabled()
  })

  it('elegir "No contestó" enciende la sugerencia del motor (WhatsApp, alternancia)', async () => {
    const user = userEvent.setup()
    montar()
    await user.click(screen.getByRole('button', { name: 'No contestó' }))
    expect(screen.getByText('Siguiente acción propuesta')).toBeInTheDocument()
    expect(screen.getByLabelText('Título de la siguiente')).toHaveValue('WhatsApp a Ana')
    expect(screen.getByLabelText('Tipo de la siguiente')).toHaveValue('whatsapp')
  })

  it('confirmar envía el payload completo con la siguiente al store', async () => {
    const user = userEvent.setup()
    const { completarTarea, onCerrar } = montar()
    await user.click(screen.getByRole('button', { name: 'No contestó' }))
    await user.click(screen.getByRole('button', { name: /cerrar tarea/i }))
    expect(completarTarea).toHaveBeenCalledTimes(1)
    const payload = completarTarea.mock.calls[0]?.[0]
    expect(payload).toMatchObject({
      tarea_id: 't1',
      estado: 'completada',
      resultado_tipo: 'llamada_no_contestada',
    })
    expect(payload?.siguiente).toMatchObject({ tipo: 'whatsapp', titulo: 'WhatsApp a Ana' })
    expect(onCerrar).toHaveBeenCalled()
  })

  it('"Saltar esta vez" es UN toque: cierra sin siguiente y avisa el amarillo', async () => {
    const user = userEvent.setup()
    const { completarTarea } = montar()
    await user.click(screen.getByRole('button', { name: 'Contestó' }))
    await user.click(screen.getByRole('button', { name: 'Saltar esta vez' }))
    expect(screen.getByText(/sin próxima acción/i)).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /cerrar tarea/i }))
    expect(completarTarea.mock.calls[0]?.[0]?.siguiente).toBeNull()
  })

  it('reunión ofrece "No asistió" (no_show) y el motor propone REAGENDAR', async () => {
    const user = userEvent.setup()
    const { completarTarea } = montar({ ...TAREA, tipo: 'reunion', titulo: 'Reunión con Ana' })
    await user.click(screen.getByRole('button', { name: 'No asistió' }))
    expect(screen.getByLabelText('Título de la siguiente')).toHaveValue('Reagendar con Ana')
    await user.click(screen.getByRole('button', { name: /cerrar tarea/i }))
    expect(completarTarea.mock.calls[0]?.[0]).toMatchObject({ estado: 'no_show' })
  })
})
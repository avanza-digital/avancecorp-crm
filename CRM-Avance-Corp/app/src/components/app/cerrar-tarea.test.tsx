// Tests del diálogo de cierre: resultado 1-tap obligatorio, la sugerencia del
// motor aparece al elegir, "saltar" a un toque, y el payload que viaja al store.
import { describe, expect, it, vi } from 'vitest'
import { act, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { toast } from 'sonner'
import { StoreDataContext } from '@/lib/store-context'
import type { StoreDataApi } from '@/lib/store'
import type { Actividad, Lead, Tarea } from '@/lib/tipos'
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

/** Timeline de PLANTÓN: 5 intentos sin una sola respuesta, repartidos en 8 días
 *  (`plantonDe` exige ≥5 intentos y ≥3 días de racha para ofrecer el cierre). */
function intentosSinRespuesta(): Actividad[] {
  const dia = 86_400_000
  return Array.from({ length: 5 }, (_, i) => ({
    id: `a${i}`,
    lead_id: 'l1',
    tipo: 'llamada_no_contestada' as const,
    detalle: null,
    autor_nombre: 'Vendedor',
    creado_en: new Date(Date.now() - (8 - i) * dia).toISOString(),
  }))
}

function montar(
  tarea: Tarea | null = TAREA,
  actividades: Actividad[] = [],
  resultadoCierre: ReturnType<StoreDataApi['completarTarea']> = { ok: true },
) {
  const completarTarea = vi.fn<StoreDataApi['completarTarea']>(() => resultadoCierre)
  const descartar = vi.fn<StoreDataApi['descartar']>(() => ({ ok: true }))
  const api = {
    lead: (id: string) => (id === LEAD.id ? LEAD : undefined),
    completarTarea,
    descartar,
    // El diálogo lee el timeline para detectar el PLANTÓN (5 intentos sin
    // respuesta en ≥3 días → deja de proponer toques y ofrece cerrar).
    actividadesDe: (id: string) => (id === LEAD.id ? actividades : []),
    // El aviso ámbar solo se emite si al lead NO le queda otra tarea viva.
    tareasDe: () => [],
  } as unknown as StoreDataApi
  const onCerrar = vi.fn()
  render(
    <StoreDataContext.Provider value={api}>
      <CerrarTareaDialog tarea={tarea} onCerrar={onCerrar} />
    </StoreDataContext.Provider>,
  )
  return { completarTarea, descartar, onCerrar }
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

  // El AVANCE de etapa: `completarTarea` ya lo devolvía y este diálogo —la
  // superficie donde más tareas se cierran— lo tiraba. El asesor veía el
  // stepper de la ficha moverse solo tras cerrar una llamada.
  it('canta el avance de etapa junto con la siguiente agendada', async () => {
    const user = userEvent.setup()
    montar(TAREA, [], { ok: true, avance: 'contactado' })
    await user.click(screen.getByRole('button', { name: 'Contestó' }))
    await user.click(screen.getByRole('button', { name: /cerrar tarea/i }))

    expect(toast.success).toHaveBeenCalledWith(
      expect.stringMatching(/^Tarea cerrada · pasó a Contactado · siguiente agendada: /),
    )
  })

  it('canta el avance también cuando se salta la siguiente (aviso ámbar)', async () => {
    const user = userEvent.setup()
    montar(TAREA, [], { ok: true, avance: 'contactado' })
    await user.click(screen.getByRole('button', { name: 'Contestó' }))
    await user.click(screen.getByRole('button', { name: 'Saltar esta vez' }))
    await user.click(screen.getByRole('button', { name: /cerrar tarea/i }))

    expect(toast.warning).toHaveBeenCalledWith(
      'Tarea cerrada · pasó a Contactado — Ana quedó SIN próxima acción',
    )
  })

  it('sin avance no se inventa ningún cambio de etapa en el aviso', async () => {
    const user = userEvent.setup()
    montar(TAREA, [], { ok: true })
    await user.click(screen.getByRole('button', { name: 'Contestó' }))
    await user.click(screen.getByRole('button', { name: 'Saltar esta vez' }))
    await user.click(screen.getByRole('button', { name: /cerrar tarea/i }))

    expect(toast.warning).toHaveBeenCalledWith('Tarea cerrada — Ana quedó SIN próxima acción')
  })

  it('reunión ofrece "No asistió" (no_show) y el motor propone REAGENDAR', async () => {
    const user = userEvent.setup()
    const { completarTarea } = montar({ ...TAREA, tipo: 'reunion', titulo: 'Reunión con Ana' })
    await user.click(screen.getByRole('button', { name: 'No asistió' }))
    expect(screen.getByLabelText('Título de la siguiente')).toHaveValue('Reagendar con Ana')
    await user.click(screen.getByRole('button', { name: /cerrar tarea/i }))
    expect(completarTarea.mock.calls[0]?.[0]).toMatchObject({ estado: 'no_show' })
  })

  // ── Cierre por plantón: dos escrituras, un orden NO negociable ─────────────
  // Descartar el lead cancela sus tareas pendientes por trigger; si esa
  // escritura llega antes que la RPC del cierre, la RPC no encuentra la tarea,
  // revienta, y se pierde la actividad del último intento — la EVIDENCIA misma
  // del descarte. Por eso el descarte se encadena a `persistido`, no al tick.
  async function abrirPlanton(
    user: ReturnType<typeof userEvent.setup>,
    resultadoCierre: ReturnType<StoreDataApi['completarTarea']>,
  ) {
    const m = montar(TAREA, intentosSinRespuesta(), resultadoCierre)
    await user.click(screen.getByRole('button', { name: 'No contestó' }))
    await user.click(screen.getByRole('checkbox', { name: /cerrar el lead por/i }))
    await user.click(screen.getByRole('button', { name: /cerrar tarea/i }))
    return m
  }

  it('el descarte espera a que el cierre haya PERSISTIDO en el servidor', async () => {
    const user = userEvent.setup()
    let confirmarServidor!: (ok: boolean) => void
    const persistido = new Promise<boolean>((res) => { confirmarServidor = res })
    const { completarTarea, descartar, onCerrar } = await abrirPlanton(user, { ok: true, persistido })

    expect(completarTarea).toHaveBeenCalledTimes(1)
    // El espejo local ya cerró la tarea, pero el servidor aún no: descartar
    // AQUÍ es exactamente la carrera que rompe la RPC del cierre.
    expect(descartar).not.toHaveBeenCalled()
    expect(onCerrar).not.toHaveBeenCalled()

    await act(async () => confirmarServidor(true))

    expect(descartar).toHaveBeenCalledTimes(1)
    expect(descartar).toHaveBeenCalledWith('l1', 'no_responde', undefined)
    expect(onCerrar).toHaveBeenCalled()
  })

  it('si el servidor RECHAZA el cierre, el lead NO se descarta (sin evidencia no hay descarte)', async () => {
    const user = userEvent.setup()
    const { descartar, onCerrar } = await abrirPlanton(user, {
      ok: true,
      persistido: Promise.resolve(false),
    })

    await act(async () => undefined)

    expect(descartar).not.toHaveBeenCalled()
    // El diálogo se queda abierto: la tarea volvió a estar pendiente (rollback
    // del store) y el cierre se puede reintentar.
    expect(onCerrar).not.toHaveBeenCalled()
    expect(screen.getByRole('button', { name: /cerrar tarea/i })).toBeEnabled()
  })

  it('sin persistencia (modo demo) el encadenado no espera a nadie', async () => {
    const user = userEvent.setup()
    const { descartar, onCerrar } = await abrirPlanton(user, { ok: true })

    await act(async () => undefined)

    expect(descartar).toHaveBeenCalledWith('l1', 'no_responde', undefined)
    expect(onCerrar).toHaveBeenCalled()
  })
})
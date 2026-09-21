// Panel del resultado tipificado (mockup 5): las siete opciones con atajos, el
// paso 2 que cada resultado exige, el espejo de las reglas del servidor
// (dueño vs supervisor, ventana legal, descarte con submotivo) y el toast con
// «Deshacer». El store se simula: aquí se prueba QUÉ petición se arma.
import { describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { toast } from 'sonner'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import { StoreDataContext } from '@/lib/store-context'
import type { ConfirmacionLlamada, RegistrarLlamadaInput, StoreDataApi } from '@/lib/store'
import type { Actividad, Lead, Tarea } from '@/lib/tipos'
import { RegistrarResultado } from './registrar-resultado'

vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() } }))
// Lunes 21/09/2026 10:00 Lima: dentro de la ventana legal, día hábil.
const AHORA = Date.parse('2026-09-21T15:00:00.000Z')
vi.mock('@/lib/ahora', () => ({ useAhora: () => AHORA }))

const sesion = (id: string, rol: 'vendedor' | 'supervisor' = 'vendedor'): AuthContextValue => ({
  fase: 'listo',
  yo: { id, nombre_completo: 'QUIEN LLAMA', rol, demo: true, puede_contratar: true },
  error: null, entrar: async () => ({ ok: true }), entrarDemo: () => undefined, reintentar: () => undefined, salir: async () => undefined,
})

const LEAD = {
  id: 'l1', nombre_completo: 'ANA TORRES QUISPE', telefono: '+51999888777', etapa: 'nuevo', origen: 'oficina',
  monto_estimado: 50_000, moneda: 'PEN', creado_en: '2026-09-10T15:00:00.000Z', activo: true, vendedor_id: 'v1',
} as Lead

const TAREA: Tarea = {
  id: 't1', lead_id: 'l1', tipo: 'llamada', titulo: 'Llamar a Ana', vence_en: '2026-09-21T14:00:00.000Z',
  estado: 'pendiente', reprogramaciones: 0, activo: true, creado_en: '2026-09-20T15:00:00.000Z',
}

function intentos(n: number): Actividad[] {
  return Array.from({ length: n }, (_, i) => ({
    id: `a${i}`, lead_id: 'l1', tipo: 'llamada_no_contestada' as const, detalle: null, autor_nombre: 'X',
    creado_en: new Date(AHORA - (n - i) * 86_400_000).toISOString(),
  }))
}

interface Montaje {
  lead?: Lead
  tarea?: Tarea | null
  yo?: string
  rol?: 'vendedor' | 'supervisor'
  actividades?: Actividad[]
  pendientes?: Tarea[]
  confirmacion?: ConfirmacionLlamada
  persistido?: Promise<boolean>
}

function montar({ lead = LEAD, tarea = null, yo = 'v1', rol = 'vendedor', actividades = [], pendientes = [], confirmacion = { actividad_id: 'act-1', siguiente_id: null, descartado: false }, persistido = Promise.resolve(true) }: Montaje = {}) {
  vi.useRealTimers()
  vi.spyOn(Date, 'now').mockReturnValue(AHORA)
  const registrarLlamada = vi.fn<StoreDataApi['registrarLlamada']>(() => ({ ok: true, persistido, confirmacion: Promise.resolve(confirmacion) }))
  const deshacerResultadoLlamada = vi.fn<StoreDataApi['deshacerResultadoLlamada']>(() => ({ ok: true, persistido: Promise.resolve(true) }))
  const api = {
    registrarLlamada, deshacerResultadoLlamada,
    tareasDe: () => pendientes,
    actividadesDe: () => actividades,
    lead: (id: string) => (id === lead.id ? lead : undefined),
  } as unknown as StoreDataApi
  const onClose = vi.fn()
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  render(
    <QueryClientProvider client={queryClient}>
      <AuthContext.Provider value={sesion(yo, rol)}>
        <StoreDataContext.Provider value={api}>
          <RegistrarResultado lead={lead} tarea={tarea} onClose={onClose} />
        </StoreDataContext.Provider>
      </AuthContext.Provider>
    </QueryClientProvider>,
  )
  return { registrarLlamada, deshacerResultadoLlamada, onClose }
}

const peticion = (fn: ReturnType<typeof montar>['registrarLlamada']): RegistrarLlamadaInput => {
  const args = fn.mock.calls[0]
  if (!args) throw new Error('registrarLlamada no fue llamado')
  return args[1]
}

describe('RegistrarResultado', () => {
  it('contrae los otros seis resultados, conserva el foco y permite cambiarlos sin borrar el borrador', async () => {
    const user = userEvent.setup()
    montar()
    await user.click(screen.getByRole('radio', { name: /No contestó/ }))
    expect(document.querySelectorAll('input[name="resultado-llamada"]')).toHaveLength(1)
    expect(screen.getByRole('radio', { name: /No contestó/ })).toHaveFocus()
    await user.clear(screen.getByLabelText('Título'))
    await user.type(screen.getByLabelText('Título'), 'Seguimiento personalizado')
    screen.getByRole('button', { name: 'Cambiar resultado' }).focus()
    await user.keyboard('4')
    expect(screen.getByRole('radio', { name: /No contestó/ })).toBeChecked()
    expect(screen.getByLabelText('Título')).toHaveValue('Seguimiento personalizado')
    await user.click(screen.getByRole('button', { name: 'Cambiar resultado' }))
    expect(document.querySelectorAll('input[name="resultado-llamada"]')).toHaveLength(7)
    await user.keyboard('1')
    expect(document.querySelectorAll('input[name="resultado-llamada"]')).toHaveLength(1)
    expect(screen.getByLabelText('Título')).toHaveValue('Seguimiento personalizado')
    await user.click(screen.getByRole('button', { name: 'Cambiar resultado' }))
    await user.click(screen.getByRole('radio', { name: /no le interesa/ }))
    expect(document.querySelectorAll('input[name="resultado-llamada"]')).toHaveLength(1)
    expect(screen.getByRole('checkbox', { name: /Descartar y enviar/ })).not.toBeChecked()
  })

  it.each(['llamada', 'whatsapp', 'reunion', 'tarea'])('«no le interesa» agenda %s sin descartar y conserva el título editado', async (tipo) => {
    const user = userEvent.setup()
    const { registrarLlamada } = montar()
    await user.click(screen.getByRole('radio', { name: /no le interesa/ }))
    await user.selectOptions(screen.getByLabelText(/¿Por qué no le interesa/), 'sin_fondos_ahora')
    await user.clear(screen.getByLabelText('Título'))
    await user.type(screen.getByLabelText('Título'), 'Retomar en octubre')
    await user.selectOptions(screen.getByLabelText('Tipo de próxima acción'), tipo)
    expect(screen.getByLabelText('Título')).toHaveValue('Retomar en octubre')
    if (tipo === 'reunion') await user.selectOptions(screen.getByLabelText('Modalidad de la cita'), 'virtual')
    await user.click(screen.getByRole('button', { name: 'Guardar' }))
    await waitFor(() => expect(registrarLlamada).toHaveBeenCalled())
    expect(peticion(registrarLlamada)).toMatchObject({
      resultado: 'no_interesado', submotivo: 'sin_fondos_ahora', descartar: false,
      siguiente: { tipo, titulo: 'Retomar en octubre' },
    })
  })

  it('«pide otro producto»: descartar oculta la agenda sin perder los campos si se desmarca', async () => {
    const user = userEvent.setup()
    const { registrarLlamada } = montar()
    await user.click(screen.getByRole('radio', { name: /Pide otro producto/ }))
    await user.selectOptions(screen.getByLabelText(/¿Qué producto pide/), 'credito')
    await user.selectOptions(screen.getByLabelText('Tipo de próxima acción'), 'whatsapp')
    const titulo = (screen.getByLabelText('Título') as HTMLInputElement).value
    await user.click(screen.getByRole('checkbox', { name: /Descartar y enviar/ }))
    expect(screen.queryByLabelText('Fecha')).not.toBeInTheDocument()
    await user.click(screen.getByRole('checkbox', { name: /Descartar y enviar/ }))
    expect(screen.getByLabelText('Título')).toHaveValue(titulo)
    await user.click(screen.getByRole('button', { name: 'Guardar' }))
    await waitFor(() => expect(registrarLlamada).toHaveBeenCalled())
    expect(peticion(registrarLlamada)).toMatchObject({ resultado: 'pide_otro_producto', descartar: false, siguiente: { tipo: 'whatsapp' } })
  })

  it('«No volver a contactar» no descarta, pero quita la próxima acción del envío', async () => {
    const user = userEvent.setup()
    const { registrarLlamada } = montar()
    await user.click(screen.getByRole('radio', { name: /no le interesa/ }))
    await user.selectOptions(screen.getByLabelText(/¿Por qué no le interesa/), 'desconfianza')
    await user.click(screen.getByRole('checkbox', { name: /no lo vuelvan a llamar/i }))
    expect(screen.queryByLabelText('Fecha')).not.toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent('No volver a contactar')
    await user.click(screen.getByRole('button', { name: 'Guardar' }))
    await waitFor(() => expect(registrarLlamada).toHaveBeenCalled())
    expect(peticion(registrarLlamada)).toMatchObject({ descartar: false, no_insista: true })
    expect(peticion(registrarLlamada).siguiente).toBeUndefined()
  })

  it('la confirmación incierta congela opciones y reenvía exactamente la misma entrada', async () => {
    const user = userEvent.setup()
    const { registrarLlamada, onClose } = montar({ persistido: Promise.resolve(false) })
    await user.click(screen.getByRole('radio', { name: /No contestó/ }))
    await user.click(screen.getByRole('button', { name: 'Guardar' }))
    await screen.findByRole('button', { name: 'Reintentar guardado' })
    await user.keyboard('4')
    expect(screen.getByRole('radio', { name: /No contestó/ })).toBeChecked()
    expect(screen.getByRole('button', { name: 'Cambiar resultado' })).toBeDisabled()
    expect(onClose).not.toHaveBeenCalled()
    await user.click(screen.getByRole('button', { name: 'Reintentar guardado' }))
    expect(registrarLlamada.mock.calls[1]).toEqual(registrarLlamada.mock.calls[0])
  })

  it('ofrece los siete resultados con atajos y no guarda sin elegir uno', () => {
    montar()
    const radios = screen.getAllByRole('radio')
    expect(radios).toHaveLength(7)
    expect(screen.getByRole('radio', { name: /Contestó · agendó cita/ })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Guardar' })).toBeDisabled()
  })

  it('«volver a llamar» exige fecha al DUEÑO y manda la tarea siguiente de llamada', async () => {
    const user = userEvent.setup()
    const { registrarLlamada, onClose } = montar({ tarea: TAREA })
    await user.click(screen.getByRole('radio', { name: /volver a llamar/ }))
    expect(screen.getByLabelText('Fecha')).toHaveValue('2026-09-24')
    expect(screen.getByLabelText('Título')).toHaveValue('Volver a llamar a Ana')
    await user.click(screen.getByRole('button', { name: 'Guardar' }))
    await waitFor(() => expect(onClose).toHaveBeenCalled())
    const p = peticion(registrarLlamada)
    expect(p.resultado).toBe('volver_a_llamar')
    expect(p.tarea_id).toBe('t1')
    expect(p.siguiente).toMatchObject({ tipo: 'llamada', titulo: 'Volver a llamar a Ana' })
    expect(toast.success).toHaveBeenCalledWith(expect.stringMatching(/^Llamada registrada · Volver a llamar · tarea cerrada/), expect.objectContaining({ action: expect.objectContaining({ label: 'Deshacer' }) }))
  })

  it('el supervisor registra «volver a llamar» sin agendar (la agenda es del analista)', async () => {
    const user = userEvent.setup()
    const { registrarLlamada } = montar({ yo: 's1', rol: 'supervisor' })
    await user.click(screen.getByRole('radio', { name: /volver a llamar/ }))
    expect(screen.queryByLabelText('Fecha')).not.toBeInTheDocument()
    expect(screen.getByText(/la agenda es del analista/i)).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Guardar' }))
    await waitFor(() => expect(registrarLlamada).toHaveBeenCalled())
    expect(peticion(registrarLlamada).siguiente).toBeUndefined()
  })

  it('«no le interesa» exige submotivo y solo descarta si el analista lo elige', async () => {
    const user = userEvent.setup()
    const { registrarLlamada } = montar({ pendientes: [TAREA] })
    await user.click(screen.getByRole('radio', { name: /no le interesa/ }))
    expect(screen.queryByText(/saldrá de tu cartera/i)).not.toBeInTheDocument()
    expect(screen.getByRole('checkbox', { name: /Descartar y enviar/ })).not.toBeChecked()
    await user.click(screen.getByRole('checkbox', { name: /Descartar y enviar/ }))
    expect(screen.getByText(/saldrá de tu cartera/i)).toBeInTheDocument()
    expect(screen.getByText(/Se cancelarán 1 tarea pendiente/)).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Guardar' }))
    expect(toast.error).toHaveBeenCalledWith('Indica por qué no le interesa')
    expect(registrarLlamada).not.toHaveBeenCalled()
    await user.selectOptions(screen.getByLabelText(/¿Por qué no le interesa/), 'sin_fondos_ahora')
    await user.click(screen.getByRole('checkbox', { name: /no lo vuelvan a llamar/i }))
    await user.click(screen.getByRole('button', { name: 'Guardar' }))
    await waitFor(() => expect(registrarLlamada).toHaveBeenCalled())
    expect(peticion(registrarLlamada)).toMatchObject({ resultado: 'no_interesado', submotivo: 'sin_fondos_ahora', descartar: true, no_insista: true })
    // Con «No insistir» no hay Deshacer: la restricción legal no se revierte desde aquí.
    await waitFor(() => expect(toast.success).toHaveBeenCalledWith(expect.stringMatching(/No insistir marcado/)))
  })

  it('número errado: el analista decide; con segundo número propone llamarlo hoy', async () => {
    const user = userEvent.setup()
    const { registrarLlamada } = montar({ lead: { ...LEAD, telefono_alternativo: '+51911222333' } as Lead })
    await user.click(screen.getByRole('radio', { name: /Número errado/ }))
    expect(screen.getByRole('radio', { name: /Llamar al 2.º número/ })).toBeChecked()
    expect(screen.getByLabelText('Título')).toHaveValue('Llamar al 2.º número +51911222333')
    await user.click(screen.getByRole('radio', { name: /Descartar por datos inválidos/ }))
    expect(screen.queryByLabelText('Fecha')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Guardar' }))
    await waitFor(() => expect(registrarLlamada).toHaveBeenCalled())
    expect(peticion(registrarLlamada)).toMatchObject({ resultado: 'numero_errado', descartar: true })
  })

  it('«no contestó»: sugiere WhatsApp mañana (omitible) y al 6.º intento ofrece marcar perdido', async () => {
    const user = userEvent.setup()
    const { registrarLlamada } = montar({ actividades: intentos(5) })
    await user.click(screen.getByRole('radio', { name: /No contestó/ }))
    expect(screen.getByLabelText('Título')).toHaveValue('WhatsApp a Ana')
    const perdido = screen.getByRole('checkbox', { name: /marcar perdido/i })
    await user.click(perdido)
    expect(screen.queryByLabelText('Fecha')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Guardar' }))
    await waitFor(() => expect(registrarLlamada).toHaveBeenCalled())
    expect(peticion(registrarLlamada)).toMatchObject({ resultado: 'no_contesto', descartar: true })
    expect(peticion(registrarLlamada).siguiente).toBeUndefined()
  })

  it('los atajos 1–7 eligen el resultado, pero no dentro de la nota', async () => {
    const user = userEvent.setup()
    montar()
    await user.keyboard('3')
    expect(screen.getByRole('radio', { name: /agendó cita/ })).toBeChecked()
    await user.click(screen.getByRole('textbox', { name: 'Nota de la llamada' }))
    await user.keyboard('1')
    expect(screen.getByRole('radio', { name: /agendó cita/ })).toBeChecked()
    expect(screen.getByRole('textbox', { name: 'Nota de la llamada' })).toHaveValue('1')
  })

  it('«agendó cita» pide modalidad de la cita y manda la tarea de reunión', async () => {
    const user = userEvent.setup()
    const { registrarLlamada } = montar()
    await user.click(screen.getByRole('radio', { name: /agendó cita/ }))
    await user.click(screen.getByRole('button', { name: 'Guardar' }))
    expect(registrarLlamada).not.toHaveBeenCalled()
    expect(toast.error).toHaveBeenCalled()
    await user.selectOptions(screen.getByRole('combobox', { name: 'Modalidad de la cita' }), 'virtual')
    await user.click(screen.getByRole('button', { name: 'Guardar' }))
    await waitFor(() => expect(registrarLlamada).toHaveBeenCalled())
    expect(peticion(registrarLlamada).siguiente).toMatchObject({ tipo: 'reunion', modalidad_reunion: 'virtual', ubicacion_reunion: null })
  })

  it('«Deshacer» del toast llama al deshacer con el id confirmado por el servidor', async () => {
    const user = userEvent.setup()
    const { deshacerResultadoLlamada } = montar({ confirmacion: { actividad_id: 'act-77', siguiente_id: 'sig-1', descartado: false } })
    await user.click(screen.getByRole('radio', { name: /volver a llamar/ }))
    await user.click(screen.getByRole('button', { name: 'Guardar' }))
    await waitFor(() => expect(toast.success).toHaveBeenCalled())
    const opciones = vi.mocked(toast.success).mock.calls[0]?.[1] as unknown as { action: { onClick: () => void } }
    opciones.action.onClick()
    expect(deshacerResultadoLlamada).toHaveBeenCalledWith('act-77')
  })

  it('«Cerrar sin registrar» avisa que no quedó nada en el historial', async () => {
    const user = userEvent.setup()
    const { onClose, registrarLlamada } = montar()
    await user.click(screen.getByRole('button', { name: 'Cerrar sin registrar' }))
    expect(onClose).toHaveBeenCalled()
    expect(registrarLlamada).not.toHaveBeenCalled()
    expect(toast.info).toHaveBeenCalledWith(expect.stringMatching(/sin registrar/))
  })
})

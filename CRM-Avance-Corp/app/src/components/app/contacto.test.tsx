// Tests de caracterización de AccionesContacto — F1.1.0 del plan «Llamadas desde
// el celular al CRM» (30/09/2026). Fijan lo que HOY funciona en producción antes
// de que la intención de llamada pase a un coordinador compartido con el
// receptor del enlace (F1.1.1): el marcador del celular, la pregunta al volver
// (≥ 4 s), el camino del escritorio, el rol de solo lectura y a qué tarea se le
// ofrece el cierre. Si algo de esto cambia, tiene que ser a propósito.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import type { Tarea } from '@/lib/tipos'
// El coordinador real (F1.1.1): aquí se prueba cómo lo usa AccionesContacto.
import { armarIntencion, intencionDe, limpiarIntencionesContacto } from '@/lib/intencion-contacto'

/** 10:00 de Lima: una tarea que vence a las 15:00 Lima es «de hoy». */
const AHORA = Date.parse('2026-09-30T15:00:00Z')

const dobles = vi.hoisted(() => ({
  yo: { id: 'v1', rol: 'vendedor', demo: false, nombre_completo: 'ANALISTA UNO' },
  puedeMarcar: true,
  asegurarLead: vi.fn(async (_id: string) => true),
  tareas: [] as Tarea[],
  registro: { props: null as Record<string, unknown> | null, montajes: 0 },
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn() },
}))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: dobles.yo }) }))
vi.mock('@/lib/ahora', () => ({ useAhora: () => AHORA }))
vi.mock('@/lib/media', async () => ({
  ...await vi.importActual<typeof import('@/lib/media')>('@/lib/media'),
  usePuedeMarcar: () => dobles.puedeMarcar,
}))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    asegurarLead: dobles.asegurarLead,
    tareasDe: () => dobles.tareas,
    crearTarea: vi.fn(),
    registrarActividad: vi.fn(),
    completarTarea: vi.fn(),
  }),
}))
vi.mock('sonner', () => ({ toast: dobles.toast }))
// El formulario de resultado tiene sus pruebas; aquí importa CUÁNDO se abre y con qué.
vi.mock('@/components/gestion-diaria/registrar-resultado', () => ({
  RegistrarResultado: (props: Record<string, unknown>) => {
    dobles.registro.props = props
    dobles.registro.montajes += 1
    return <div role="dialog" aria-label="Resultado de la llamada (mock)" />
  },
}))
const { AccionesContacto } = await import('./contacto')

/** Número sintético (no es de nadie). */
const LEAD = { id: 'lead-1', nombre_completo: 'MARÍA PÉREZ', telefono: '+51999888777', vendedor_id: 'v1' }

function tarea(parcial: Partial<Tarea> & { id: string }): Tarea {
  return {
    lead_id: LEAD.id, vendedor_id: 'v1', tipo: 'llamada', titulo: 'Llamar a María',
    vence_en: '2026-09-30T20:00:00Z', estado: 'pendiente', reprogramaciones: 0, activo: true,
    creado_en: '2026-09-29T12:00:00Z', ...parcial,
  }
}

/** Click sin que jsdom intente navegar (no implementa navegación fuera del hash). */
function pulsar(enlace: HTMLElement) {
  enlace.addEventListener('click', (e) => e.preventDefault(), { once: true })
  fireEvent.click(enlace)
}

/** Lo que hace el celular al volver del marcador: `focus` y `visibilitychange` llegan juntos. */
function volver(estado: DocumentVisibilityState = 'visible') {
  Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => estado })
  act(() => {
    document.dispatchEvent(new Event('visibilitychange'))
    window.dispatchEvent(new Event('focus'))
  })
}

const enlaceLlamar = () => screen.getByRole('link', { name: 'Llamar a MARÍA PÉREZ' })
const dialogoLlamada = () => screen.getByRole('dialog', { name: 'Resultado de la llamada (mock)' })

beforeEach(() => {
  vi.useFakeTimers({ now: AHORA, toFake: ['Date'] })
  limpiarIntencionesContacto()
  dobles.yo ={ id: 'v1', rol: 'vendedor', demo: false, nombre_completo: 'ANALISTA UNO' }
  dobles.puedeMarcar = true
  dobles.tareas = [tarea({ id: 't-llamada' })]
  dobles.registro.props = null
  dobles.registro.montajes = 0
  Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' })
})
afterEach(() => { vi.useRealTimers() })

describe('AccionesContacto en el celular (el aparato marca)', () => {
  it('«Llamar» es un enlace tel: con el número tal cual, avisa síncrono con onLlamar y no abre nada todavía', () => {
    const onLlamar = vi.fn()
    render(<AccionesContacto lead={LEAD} onLlamar={onLlamar} />)
    expect(enlaceLlamar()).toHaveAttribute('href', 'tel:+51999888777')
    pulsar(enlaceLlamar())
    expect(onLlamar).toHaveBeenCalledTimes(1)
    expect(dobles.asegurarLead).not.toHaveBeenCalled()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('al volver ≥ 4 s después pregunta el resultado, una sola vez, con la única tarea de llamada de hoy', async () => {
    render(<AccionesContacto lead={LEAD} />)
    pulsar(enlaceLlamar())
    vi.setSystemTime(AHORA + 4_000)
    volver()
    await waitFor(() => expect(dialogoLlamada()).toBeInTheDocument())
    // focus y visibilitychange juntos = un solo disparo.
    expect(dobles.asegurarLead).toHaveBeenCalledTimes(1)
    expect(dobles.asegurarLead).toHaveBeenCalledWith('lead-1')
    expect(dobles.registro.props).toMatchObject({ lead: LEAD, tarea: { id: 't-llamada' } })
    // Volver otra vez sin haber llamado de nuevo no vuelve a preguntar.
    volver()
    expect(dobles.asegurarLead).toHaveBeenCalledTimes(1)
    expect(dobles.registro.montajes).toBe(1)
  })

  it('volver antes de 4 s no pregunta nada: no llegó a llamar', () => {
    render(<AccionesContacto lead={LEAD} />)
    pulsar(enlaceLlamar())
    vi.setSystemTime(AHORA + 3_999)
    volver()
    expect(dobles.asegurarLead).not.toHaveBeenCalled()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('un evento con la pestaña aún oculta no consume la intención; se pregunta cuando vuelve a verse', async () => {
    render(<AccionesContacto lead={LEAD} />)
    pulsar(enlaceLlamar())
    vi.setSystemTime(AHORA + 5_000)
    volver('hidden')
    expect(dobles.asegurarLead).not.toHaveBeenCalled()
    volver('visible')
    await waitFor(() => expect(dialogoLlamada()).toBeInTheDocument())
    expect(dobles.asegurarLead).toHaveBeenCalledTimes(1)
  })

  it('con onRegistrarLlamada delega en la pantalla («Mi día») en vez de abrir su propio diálogo', async () => {
    const onRegistrarLlamada = vi.fn()
    render(<AccionesContacto lead={LEAD} onRegistrarLlamada={onRegistrarLlamada} />)
    pulsar(enlaceLlamar())
    vi.setSystemTime(AHORA + 4_000)
    volver()
    await waitFor(() => expect(onRegistrarLlamada).toHaveBeenCalledTimes(1))
    expect(dobles.asegurarLead).toHaveBeenCalledWith('lead-1')
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    // «Mi día» sigue con su propia sesión: la intención termina al delegar.
    expect(intencionDe('v1', LEAD.id)).toBeNull()
  })

  it('si el lead ya no está en el ámbito lo dice y no abre nada', async () => {
    dobles.asegurarLead.mockResolvedValueOnce(false)
    render(<AccionesContacto lead={LEAD} />)
    pulsar(enlaceLlamar())
    vi.setSystemTime(AHORA + 4_000)
    volver()
    await waitFor(() => expect(dobles.toast.error).toHaveBeenCalledWith('Este lead ya no está disponible en tu ámbito.'))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('si no se pudo comprobar el lead (sin red) lo dice y no abre nada', async () => {
    dobles.asegurarLead.mockRejectedValueOnce(new Error('sin red'))
    render(<AccionesContacto lead={LEAD} />)
    pulsar(enlaceLlamar())
    vi.setSystemTime(AHORA + 4_000)
    volver()
    await waitFor(() => expect(dobles.toast.error).toHaveBeenCalledWith('No se pudo comprobar el lead. Revisa tu conexión y vuelve a intentarlo.'))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('sin una única tarea clara de hoy se abre sin tarea: no se cierra ninguna por adivinar', async () => {
    dobles.tareas = [tarea({ id: 't-a' }), tarea({ id: 't-b' })]
    render(<AccionesContacto lead={LEAD} />)
    pulsar(enlaceLlamar())
    vi.setSystemTime(AHORA + 4_000)
    volver()
    await waitFor(() => expect(dialogoLlamada()).toBeInTheDocument())
    expect(dobles.registro.props).toMatchObject({ tarea: null })
  })

  it('WhatsApp abre wa.me en otra pestaña y al volver ≥ 4 s pregunta por la conversación (no el panel de llamada)', async () => {
    render(<AccionesContacto lead={LEAD} />)
    const wa = screen.getByRole('link', { name: 'WhatsApp a MARÍA PÉREZ' })
    expect(wa).toHaveAttribute('href', 'https://wa.me/51999888777')
    expect(wa).toHaveAttribute('target', '_blank')
    pulsar(wa)
    vi.setSystemTime(AHORA + 4_000)
    volver()
    // El nombre accesible lo pone su título (aria-labelledby), no el aria-label del contenedor.
    await waitFor(() => expect(screen.getByRole('dialog', { name: /¿Lograste comunicarte con María\?/ })).toBeInTheDocument())
    expect(screen.getByText('Registra cómo va la conversación — queda en el historial del lead.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Mensaje enviado/ })).toBeInTheDocument()
    expect(dobles.registro.montajes).toBe(0)
  })
})

describe('AccionesContacto en el escritorio (el aparato no marca)', () => {
  it('«Llamar» copia el número, avisa y abre el registro de una', async () => {
    dobles.puedeMarcar = false
    const writeText = vi.fn(async () => {})
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText } })
    const onLlamar = vi.fn()
    render(<AccionesContacto lead={LEAD} onLlamar={onLlamar} />)
    expect(screen.queryByRole('link', { name: 'Llamar a MARÍA PÉREZ' })).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Copiar el número de MARÍA PÉREZ y registrar la llamada' }))
    expect(onLlamar).toHaveBeenCalledTimes(1)
    await waitFor(() => expect(dialogoLlamada()).toBeInTheDocument())
    expect(writeText).toHaveBeenCalledWith('+51999888777')
    expect(dobles.toast.success).toHaveBeenCalledWith('Número copiado: +51999888777 — márcalo desde tu celular')
    expect(dobles.asegurarLead).toHaveBeenCalledWith('lead-1')
  })

  it('sin portapapeles pide marcarlo a mano y aun así abre el registro', async () => {
    dobles.puedeMarcar = false
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: undefined })
    render(<AccionesContacto lead={LEAD} />)
    fireEvent.click(screen.getByRole('button', { name: 'Copiar el número de MARÍA PÉREZ y registrar la llamada' }))
    await waitFor(() => expect(dialogoLlamada()).toBeInTheDocument())
    expect(dobles.toast.info).toHaveBeenCalledWith('Marca +51999888777 desde tu celular')
  })
})

describe('AccionesContacto con el coordinador de la intención (F1.1.2)', () => {
  it('la intención sobrevive al remount: la instancia nueva pregunta al volver', async () => {
    const { rerender } = render(<AccionesContacto key="a" lead={LEAD} />)
    pulsar(enlaceLlamar())
    // La cola se repintó durante la llamada: otra instancia para el mismo lead.
    rerender(<AccionesContacto key="b" lead={LEAD} />)
    vi.setSystemTime(AHORA + 4_000)
    volver()
    await waitFor(() => expect(dialogoLlamada()).toBeInTheDocument())
    expect(dobles.asegurarLead).toHaveBeenCalledTimes(1)
  })

  it('tras una recarga con la llamada en curso, la instancia nueva pregunta al montar si ya pasaron los 4 s', async () => {
    // Lo que dejó la página anterior en sessionStorage: el tap de hace 5 s.
    armarIntencion({ actor: 'v1', leadId: LEAD.id, canal: 'tel', origen: 'pantalla', instancia: 'pagina-anterior' }, AHORA - 5_000)
    render(<AccionesContacto lead={LEAD} />)
    await waitFor(() => expect(dialogoLlamada()).toBeInTheDocument())
    expect(intencionDe('v1', LEAD.id)).toMatchObject({ abierta: true })
  })

  it('un tap propio nunca se ofrece por reloj: solo al volver a la pestaña', async () => {
    const { rerender } = render(<AccionesContacto lead={LEAD} />)
    pulsar(enlaceLlamar())
    vi.setSystemTime(AHORA + 60_000)
    rerender(<AccionesContacto lead={LEAD} compacto />) // un repintado cualquiera (el reloj de la pantalla)
    await act(async () => {})
    expect(dobles.asegurarLead).not.toHaveBeenCalled()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    volver()
    await waitFor(() => expect(dialogoLlamada()).toBeInTheDocument())
  })

  it('una intención que llega del enlace se ofrece al montar sin esperar y termina al cerrar el diálogo', async () => {
    armarIntencion({ actor: 'v1', leadId: LEAD.id, canal: 'tel', origen: 'enlace', numero: '+51999888777' })
    render(<AccionesContacto lead={LEAD} />)
    await waitFor(() => expect(dialogoLlamada()).toBeInTheDocument())
    expect(dobles.asegurarLead).toHaveBeenCalledWith('lead-1')
    expect(intencionDe('v1', LEAD.id)).toMatchObject({ abierta: true, numero: '+51999888777' })
    const cerrar = dobles.registro.props?.onClose as (() => void) | undefined
    act(() => { cerrar?.() })
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(intencionDe('v1', LEAD.id)).toBeNull()
  })

  it('foco y hash en el otro orden: el tap propio queda pendiente y el enlace que llega después lo ofrece sin esperar', async () => {
    render(<AccionesContacto lead={LEAD} />)
    pulsar(enlaceLlamar())
    vi.setSystemTime(AHORA + 1_000)
    // El receptor del enlace renueva la misma intención (mismo actor, lead y canal) con el número.
    act(() => { armarIntencion({ actor: 'v1', leadId: LEAD.id, canal: 'tel', origen: 'enlace', numero: '+51999888777' }) })
    await waitFor(() => expect(dialogoLlamada()).toBeInTheDocument())
    expect(dobles.asegurarLead).toHaveBeenCalledTimes(1)
    expect(intencionDe('v1', LEAD.id)).toMatchObject({ origen: 'enlace', abierta: true })
  })

  it('una intención de otro lead no la toca', async () => {
    armarIntencion({ actor: 'v1', leadId: 'lead-2', canal: 'tel', origen: 'enlace', numero: '+51988877766' })
    render(<AccionesContacto lead={LEAD} />)
    await act(async () => {})
    expect(dobles.asegurarLead).not.toHaveBeenCalled()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(intencionDe('v1', 'lead-2')).toMatchObject({ abierta: false })
  })

  it('si la instancia se va con el diálogo abierto (la fila desaparece), la pregunta se va con ella', async () => {
    const { unmount } = render(<AccionesContacto lead={LEAD} />)
    pulsar(enlaceLlamar())
    vi.setSystemTime(AHORA + 4_000)
    volver()
    await waitFor(() => expect(dialogoLlamada()).toBeInTheDocument())
    unmount()
    expect(intencionDe('v1', LEAD.id)).toBeNull()
  })
})

describe('AccionesContacto con solo lectura (directorio)', () => {
  it('marca igual pero al volver no pregunta ni registra', () => {
    dobles.yo = { ...dobles.yo, rol: 'directorio' }
    render(<AccionesContacto lead={LEAD} />)
    expect(enlaceLlamar()).toHaveAttribute('href', 'tel:+51999888777')
    pulsar(enlaceLlamar())
    vi.setSystemTime(AHORA + 10_000)
    volver()
    expect(dobles.asegurarLead).not.toHaveBeenCalled()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })
})

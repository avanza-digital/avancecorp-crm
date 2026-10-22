// Tests del diálogo de cierre: resultado 1-tap obligatorio, la sugerencia del
// motor aparece al elegir, "saltar" a un toque, y el payload que viaja al store.
import { Profiler } from 'react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { toast } from 'sonner'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import { StoreDataContext } from '@/lib/store-context'
import type { StoreDataApi } from '@/lib/store'
import type { Actividad, EtapaActiva, Lead, Tarea } from '@/lib/tipos'
import { CerrarTareaDialog } from './cerrar-tarea'

const SESION_DEMO: AuthContextValue = {
  fase: 'listo',
  yo: { id: 'vendedor-1', nombre_completo: 'ANALISTA PRUEBA', rol: 'vendedor', demo: true, puede_contratar: true },
  error: null,
  entrar: async () => ({ ok: true }),
  entrarDemo: () => undefined,
  reintentar: () => undefined,
  salir: async () => undefined,
}

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

// Desde Gestión Diaria F2 la tarea de LLAMADA de un lead se cierra con el panel
// del resultado tipificado (ver el bloque «tarea de llamada» abajo). El flujo
// «resultado 1-tap + siguiente + plantón» de este diálogo sigue vivo para los
// demás tipos: aquí se prueba con una tarea de WhatsApp.
const TAREA: Tarea = {
  id: 't1',
  lead_id: 'l1',
  tipo: 'whatsapp',
  titulo: 'Escribir a Ana',
  vence_en: '2026-07-18T15:00:00.000Z',
  estado: 'pendiente',
  reprogramaciones: 0,
  activo: true,
  creado_en: '2026-07-17T15:00:00.000Z',
}

const TAREA_LLAMADA: Tarea = { ...TAREA, id: 't-llamada', tipo: 'llamada', titulo: 'Llamar a Ana' }

const TAREA_CLIENTE: Tarea = {
  ...TAREA,
  id: 't-cliente',
  lead_id: null,
  perfil_id: 'c-1',
  vendedor_id: 'v-1',
  tipo: 'reunion',
  titulo: 'Reunión con cliente de cartera',
  modalidad_reunion: 'presencial',
  ubicacion_reunion: 'Oficina Avance',
}

function diferida<T>() {
  let resolver!: (valor: T) => void
  const promesa = new Promise<T>((res) => {
    resolver = res
  })
  return { promesa, resolver }
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
    autor_nombre: 'Analista',
    creado_en: new Date(Date.now() - (8 - i) * dia).toISOString(),
  }))
}

function montar(
  tarea: Tarea | null = TAREA,
  actividades: Actividad[] = [],
  resultadoCierre: ReturnType<StoreDataApi['completarTarea']> = { ok: true },
  // Otras pendientes VIVAS del lead. Con al menos una, el lead NO se queda sin
  // próxima acción y el aviso ámbar sería mentira (rama negativa de
  // `quedaSinPlan`) — que es justo el escenario que motivó «anular».
  otrasTareas: Tarea[] = [],
  // Parche del lead + qué devuelve `anularTarea`: el retroceso de etapa depende
  // de la etapa VIVA del lead (solo baja desde `reunion_agendada`).
  leadParche: Partial<Lead> = {},
  retroceso?: EtapaActiva,
  resultadoAnular?: ReturnType<StoreDataApi['anularTarea']>,
  // Se llama en cada commit del diálogo: DESPUÉS de pintar y ANTES de que
  // corran sus efectos. Sirve para mover el reloj justo en ese hueco.
  alPintar?: () => void,
) {
  const l = { ...LEAD, ...leadParche } as Lead
  const completarTarea = vi.fn<StoreDataApi['completarTarea']>(() => resultadoCierre)
  const descartar = vi.fn<StoreDataApi['descartar']>(() => ({ ok: true }))
  const anularTarea = vi.fn<StoreDataApi['anularTarea']>(() =>
    resultadoAnular ?? (retroceso ? { ok: true, retroceso } : { ok: true }),
  )
  const api = {
    lead: (id: string) => (id === l.id ? l : undefined),
    completarTarea,
    anularTarea,
    descartar,
    // El diálogo lee el timeline para detectar el PLANTÓN (5 intentos sin
    // respuesta en ≥3 días → deja de proponer toques y ofrece cerrar).
    actividadesDe: (id: string) => (id === l.id ? actividades : []),
    // El aviso ámbar solo se emite si al lead NO le queda otra tarea viva.
    tareasDe: () => (tarea ? [tarea, ...otrasTareas] : otrasTareas),
    // El panel del resultado tipificado (tarea de llamada) escribe por aquí.
    registrarLlamada: vi.fn(() => ({ ok: true, persistido: Promise.resolve(true), confirmacion: Promise.resolve(null) })),
    deshacerResultadoLlamada: vi.fn(() => ({ ok: true })),
  } as unknown as StoreDataApi
  const onCerrar = vi.fn()
  // El diálogo lee el historial POR LEAD (useActividadesDeLead): en sesión
  // DEMO no sale ni un request y el timeline es el `actividadesDe` de arriba,
  // pero el hook necesita la sesión y un cliente de consultas igual.
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  render(
    <QueryClientProvider client={queryClient}>
      <AuthContext.Provider value={SESION_DEMO}>
        <StoreDataContext.Provider value={api}>
          <Profiler id="cerrar-tarea" onRender={() => alPintar?.()}>
            <CerrarTareaDialog tarea={tarea} onCerrar={onCerrar} />
          </Profiler>
        </StoreDataContext.Provider>
      </AuthContext.Provider>
    </QueryClientProvider>,
  )
  return { completarTarea, anularTarea, descartar, onCerrar }
}

describe('CerrarTareaDialog', () => {
  it('un WhatsApp NO se puede cerrar sin resultado (botón deshabilitado)', () => {
    montar()
    expect(screen.getByRole('button', { name: /cerrar tarea/i })).toBeDisabled()
  })

  it('elegir "Enviado" enciende la sugerencia del motor (llamada, alternancia)', async () => {
    const user = userEvent.setup()
    montar()
    await user.click(screen.getByRole('button', { name: 'Enviado' }))
    expect(screen.getByText('Siguiente acción propuesta')).toBeInTheDocument()
    expect(screen.getByLabelText('Título de la siguiente')).toHaveValue('Llamar a Ana')
    expect(screen.getByLabelText('Tipo de la siguiente')).toHaveValue('llamada')
  })

  it('confirmar envía el payload completo con la siguiente al store', async () => {
    const user = userEvent.setup()
    const { completarTarea, onCerrar } = montar()
    await user.click(screen.getByRole('button', { name: 'Enviado' }))
    await user.click(screen.getByRole('button', { name: /cerrar tarea/i }))
    expect(completarTarea).toHaveBeenCalledTimes(1)
    const payload = completarTarea.mock.calls[0]?.[0]
    expect(payload).toMatchObject({
      tarea_id: 't1',
      estado: 'completada',
      resultado_tipo: 'whatsapp_enviado',
    })
    expect(payload?.siguiente).toMatchObject({ tipo: 'llamada', titulo: 'Llamar a Ana' })
    expect(onCerrar).toHaveBeenCalled()
  })

  it('"Saltar esta vez" es UN toque: cierra sin siguiente y avisa el amarillo', async () => {
    const user = userEvent.setup()
    const { completarTarea } = montar()
    await user.click(screen.getByRole('button', { name: 'Respondió' }))
    await user.click(screen.getByRole('button', { name: 'Saltar esta vez' }))
    expect(screen.getByText(/sin próxima acción/i)).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /cerrar tarea/i }))
    expect(completarTarea.mock.calls[0]?.[0]?.siguiente).toBeNull()
  })

  // El AVANCE de etapa: `completarTarea` ya lo devolvía y este diálogo —la
  // superficie donde más tareas se cierran— lo tiraba. El analista veía el
  // stepper de la ficha moverse solo tras cerrar una llamada.
  it('canta el avance de etapa junto con la siguiente agendada', async () => {
    const user = userEvent.setup()
    montar(TAREA, [], { ok: true, avance: 'contactado' })
    await user.click(screen.getByRole('button', { name: 'Respondió' }))
    await user.click(screen.getByRole('button', { name: /cerrar tarea/i }))

    expect(toast.success).toHaveBeenCalledWith(
      expect.stringMatching(/^Tarea cerrada · pasó a Contactado · siguiente agendada: /),
    )
  })

  it('canta el avance también cuando se salta la siguiente (aviso ámbar)', async () => {
    const user = userEvent.setup()
    montar(TAREA, [], { ok: true, avance: 'contactado' })
    await user.click(screen.getByRole('button', { name: 'Respondió' }))
    await user.click(screen.getByRole('button', { name: 'Saltar esta vez' }))
    await user.click(screen.getByRole('button', { name: /cerrar tarea/i }))

    expect(toast.warning).toHaveBeenCalledWith(
      'Tarea cerrada · pasó a Contactado — Ana quedó SIN próxima acción',
    )
  })

  it('sin avance no se inventa ningún cambio de etapa en el aviso', async () => {
    const user = userEvent.setup()
    montar(TAREA, [], { ok: true })
    await user.click(screen.getByRole('button', { name: 'Respondió' }))
    await user.click(screen.getByRole('button', { name: 'Saltar esta vez' }))
    await user.click(screen.getByRole('button', { name: /cerrar tarea/i }))

    expect(toast.warning).toHaveBeenCalledWith('Tarea cerrada — Ana quedó SIN próxima acción')
  })

  it('reunión ofrece "No asistió" (no_show) y el motor propone REAGENDAR', async () => {
    const user = userEvent.setup()
    const { completarTarea } = montar({ ...TAREA, tipo: 'reunion', titulo: 'Reunión con Ana' })
    await user.click(screen.getByRole('button', { name: 'No asistió' }))
    expect(screen.getByLabelText('Título de la siguiente')).toHaveValue('Reagendar con Ana')
    await user.selectOptions(screen.getByLabelText('Modalidad de la cita'), 'virtual')
    expect(screen.queryByLabelText('Enlace de la cita')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /cerrar tarea/i }))
    expect(completarTarea.mock.calls[0]?.[0]).toMatchObject({ estado: 'no_show' })
  })

  it.each([TAREA_CLIENTE, { ...TAREA_CLIENTE, id: 't-lead', lead_id: 'l1', perfil_id: null }])('la reunión $id espera el COMMIT clasificado antes de avisar éxito', async (tarea) => {
    vi.mocked(toast.success).mockClear()
    const user = userEvent.setup()
    const commit = diferida<boolean>()
    const { completarTarea, onCerrar } = montar(tarea, [], {
      ok: true,
      persistido: commit.promesa,
    })

    await user.click(screen.getByRole('button', { name: 'Se realizó' }))
    await user.selectOptions(screen.getByLabelText('Resultado comercial'), 'interesado')
    const clic = user.click(screen.getByRole('button', { name: /cerrar tarea/i }))
    await waitFor(() => expect(completarTarea).toHaveBeenCalledTimes(1))

    expect(completarTarea).toHaveBeenCalledWith(
      expect.objectContaining({
        tarea_id: tarea.id,
        estado: 'completada',
        resultado_tipo: 'reunion_realizada',
        resultado_reunion: 'interesado',
      }),
    )
    expect(screen.getByRole('button', { name: 'Guardando…' })).toBeDisabled()
    expect(toast.success).not.toHaveBeenCalled()
    expect(onCerrar).not.toHaveBeenCalled()

    await act(async () => commit.resolver(true))
    await clic

    expect(toast.success).toHaveBeenCalledWith(expect.stringContaining('Tarea cerrada'))
    expect(onCerrar).toHaveBeenCalledTimes(1)
  })

  it.each([TAREA_CLIENTE, { ...TAREA_CLIENTE, id: 't-lead', lead_id: 'l1', perfil_id: null }])('si el servidor rechaza el cierre de $id, conserva el diálogo y no muestra éxito', async (tarea) => {
    vi.mocked(toast.success).mockClear()
    const user = userEvent.setup()
    const commit = diferida<boolean>()
    const { completarTarea, onCerrar } = montar(tarea, [], {
      ok: true,
      persistido: commit.promesa,
    })

    await user.click(screen.getByRole('button', { name: 'Se realizó' }))
    await user.selectOptions(screen.getByLabelText('Resultado comercial'), 'seguimiento')
    const clic = user.click(screen.getByRole('button', { name: /cerrar tarea/i }))
    await waitFor(() => expect(completarTarea).toHaveBeenCalledTimes(1))
    await act(async () => commit.resolver(false))
    await clic

    expect(screen.getByRole('button', { name: /cerrar tarea/i })).toBeEnabled()
    expect(toast.success).not.toHaveBeenCalled()
    expect(onCerrar).not.toHaveBeenCalled()
  })

  it('la cancelación de una reunión de cliente también espera que persista el motivo', async () => {
    vi.mocked(toast.success).mockClear()
    const user = userEvent.setup()
    const commit = diferida<boolean>()
    const { anularTarea, onCerrar } = montar(
      TAREA_CLIENTE,
      [],
      { ok: true },
      [],
      {},
      undefined,
      { ok: true, persistido: commit.promesa },
    )

    await user.click(screen.getByRole('button', { name: /ya no hace falta/i }))
    await user.selectOptions(
      screen.getByLabelText('Motivo de cancelación de la cita'),
      'cancelada_cliente',
    )
    const clic = user.click(screen.getByRole('button', { name: /sí, anular/i }))
    await waitFor(() => expect(anularTarea).toHaveBeenCalledTimes(1))

    expect(anularTarea).toHaveBeenCalledWith('t-cliente', {
      motivo: 'cancelada_cliente',
      detalle: null,
    })
    expect(screen.getByRole('button', { name: 'Guardando…' })).toBeDisabled()
    expect(onCerrar).not.toHaveBeenCalled()

    await act(async () => commit.resolver(true))
    await clic

    expect(toast.success).toHaveBeenCalledWith('Tarea anulada — fuera de tu agenda')
    expect(onCerrar).toHaveBeenCalledTimes(1)
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
    await user.click(screen.getByRole('button', { name: 'Enviado' }))
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

  // ANULAR — la cuarta salida (pedido de Miguel 2026-07-26). Sin ella, sacar de
  // la agenda una llamada que sobra (porque ya se agendó la reunión) exigía
  // elegir «Contestó»/«No contestó»: una afirmación FALSA sobre el cliente que
  // entra al log inmutable y puede subir la etapa del lead.
  describe('anular ("ya no hace falta")', () => {
    const abrirAnular = async (user: ReturnType<typeof userEvent.setup>) => {
      const m = montar()
      await user.click(screen.getByRole('button', { name: /ya no hace falta/i }))
      return m
    }

    it('anular NO pasa por completarTarea: no escribe resultado ninguno', async () => {
      const user = userEvent.setup()
      const { completarTarea, anularTarea, onCerrar } = await abrirAnular(user)

      await user.click(screen.getByRole('button', { name: /sí, anular/i }))

      expect(anularTarea).toHaveBeenCalledWith('t1')
      expect(completarTarea).not.toHaveBeenCalled()
      expect(onCerrar).toHaveBeenCalled()
    })

    it('esconde la nota: prometía "va al timeline" y anular no escribe nada', async () => {
      const user = userEvent.setup()
      expect(screen.queryByLabelText(/nota del resultado/i)).not.toBeInTheDocument()
      await abrirAnular(user)

      expect(screen.queryByLabelText(/nota del resultado/i)).not.toBeInTheDocument()
      expect(screen.getByText(/no se puede deshacer/i)).toBeInTheDocument()
    })

    it('avisa que el lead se queda SIN próxima acción cuando es su única tarea', async () => {
      const user = userEvent.setup()
      await abrirAnular(user)
      // El panel lo advierte ANTES de confirmar…
      expect(screen.getByText(/es su única pendiente/i)).toBeInTheDocument()

      await user.click(screen.getByRole('button', { name: /sí, anular/i }))

      // …y el toast lo repite después (mismo criterio que el cierre normal).
      expect(toast.warning).toHaveBeenCalledWith(expect.stringMatching(/SIN próxima acción/))
    })

    // EL CASO DE MIGUEL, rama negativa: ya hay una reunión agendada, así que el
    // lead NO se queda sin próxima acción y prometerlo sería mentira.
    it('con otra pendiente viva no promete el amarillo, ni antes ni después', async () => {
      const user = userEvent.setup()
      const reunion: Tarea = { ...TAREA, id: 't2', tipo: 'reunion', titulo: 'Reunión con Ana' }
      montar(TAREA, [], { ok: true }, [reunion])

      await user.click(screen.getByRole('button', { name: /ya no hace falta/i }))
      expect(screen.queryByText(/es su única pendiente/i)).not.toBeInTheDocument()

      await user.click(screen.getByRole('button', { name: /sí, anular/i }))

      expect(toast.success).toHaveBeenCalledWith('Tarea anulada — fuera de tu agenda')
      expect(toast.warning).not.toHaveBeenCalled()
    })

    it('elegir un resultado sale del modo anular (elegirlo es afirmar algo)', async () => {
      const user = userEvent.setup()
      const { anularTarea } = await abrirAnular(user)

      await user.click(screen.getByRole('button', { name: 'Respondió' }))

      expect(screen.queryByRole('button', { name: /sí, anular/i })).not.toBeInTheDocument()
      expect(screen.getByLabelText(/nota del resultado/i)).toBeInTheDocument()
      expect(anularTarea).not.toHaveBeenCalled()
    })

    it('"Volver" deja la tarea intacta', async () => {
      const user = userEvent.setup()
      const { anularTarea } = await abrirAnular(user)

      await user.click(screen.getByRole('button', { name: 'Volver' }))

      expect(anularTarea).not.toHaveBeenCalled()
      expect(screen.getByRole('button', { name: /cerrar tarea/i })).toBeInTheDocument()
    })

    // Regresión que encontró la auditoría: entrar al modo anular vaciaba
    // `eleccion`, y en una tarea GENÉRICA —una sola opción, preseleccionada al
    // montar— la guarda del footer (`opciones.length > 1 && !eleccion`) daba
    // false igual: el botón principal quedaba habilitado y no hacía NADA.
    it('asomarse a anular y volver NO deja muerto el botón de una tarea genérica', async () => {
      const user = userEvent.setup()
      const generica: Tarea = { ...TAREA, id: 't9', tipo: 'tarea', titulo: 'Preparar propuesta' }
      const { completarTarea, onCerrar } = montar(generica)

      await user.click(screen.getByRole('button', { name: /ya no hace falta/i }))
      await user.click(screen.getByRole('button', { name: 'Volver' }))
      const cerrar = screen.getByRole('button', { name: /cerrar tarea/i })
      expect(cerrar).toBeEnabled()
      await user.click(cerrar)

      expect(completarTarea).toHaveBeenCalledWith(
        expect.objectContaining({ tarea_id: 't9', estado: 'completada' }),
      )
      expect(onCerrar).toHaveBeenCalled()
    })

    it('asomarse a anular y volver NO borra la siguiente que ya se escribió', async () => {
      const user = userEvent.setup()
      const { completarTarea } = montar()
      await user.click(screen.getByRole('button', { name: 'Respondió' }))
      const titulo = screen.getByLabelText('Título de la siguiente')
      await user.clear(titulo)
      await user.type(titulo, 'Mandar cronograma firmado')

      await user.click(screen.getByRole('button', { name: /ya no hace falta/i }))
      await user.click(screen.getByRole('button', { name: 'Volver' }))

      expect(screen.getByLabelText('Título de la siguiente')).toHaveValue('Mandar cronograma firmado')
      await user.click(screen.getByRole('button', { name: /cerrar tarea/i }))
      expect(completarTarea.mock.calls[0]?.[0]?.siguiente?.titulo).toBe('Mandar cronograma firmado')
    })

    it('si el store rechaza el anulado, el diálogo NO se cierra en falso', async () => {
      const user = userEvent.setup()
      const { anularTarea, onCerrar } = await abrirAnular(user)
      anularTarea.mockReturnValueOnce({ ok: false, codigo: 'no_encontrado', error: 'Lead no encontrado' })

      await user.click(screen.getByRole('button', { name: /sí, anular/i }))

      expect(toast.error).toHaveBeenCalledWith('Lead no encontrado')
      expect(onCerrar).not.toHaveBeenCalled()
    })
  })
})
describe('CerrarTareaDialog — tarea de LLAMADA (Gestión Diaria F2)', () => {
  it('no ofrece «Contestó/No contestó»: el resultado se registra en el panel tipificado', async () => {
    const user = userEvent.setup()
    montar(TAREA_LLAMADA)
    expect(screen.queryByRole('button', { name: 'Contestó' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /^cerrar tarea$/i })).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /registrar resultado de la llamada/i }))
    expect(screen.getByText(/Cómo salió la llamada con Ana/)).toBeInTheDocument()
    expect(screen.getAllByRole('radio', { name: /./ })).toHaveLength(7)
    expect(screen.getByRole('checkbox', { name: /cerrar también «Llamar a Ana»/i })).toBeChecked()
  })

  it('conserva la cuarta salida: anular sigue disponible para una llamada', async () => {
    const user = userEvent.setup()
    const { anularTarea } = montar(TAREA_LLAMADA)
    await user.click(screen.getByRole('button', { name: /ya no hace falta/i }))
    await user.click(screen.getByRole('button', { name: /sí, anular/i }))
    expect(anularTarea).toHaveBeenCalledWith('t-llamada')
  })
})

describe('CerrarTareaDialog — anular la reunión avisa del retroceso de etapa', () => {
  // Miguel, 2026-07-26: «si se anula la reu y no se reagenda una en ese mismo
  // momento, debería bajar de etapa». El diálogo lo dice ANTES del tap; los
  // avances automáticos se cantan después porque suben, este baja.
  const REUNION: Tarea = { ...TAREA, id: 't-reu', tipo: 'reunion', titulo: 'Reunión con Ana' }
  // `vendedor_id` NO es decorado: sin dueño el lead está en la cola global y el
  // retroceso no aplica (misma guarda que la subida — una reunión de nadie).
  const EN_REUNION: Partial<Lead> = { etapa: 'reunion_agendada', vendedor_id: 'v1' }

  /** Texto completo del panel ámbar: el aviso va partido en varios elementos
   *  (nombre interpolado y <strong>), así que se asierta sobre el contenedor. */
  const panelAnular = () => screen.getByText('Anular esta tarea').parentElement
  const CONTACTO: Actividad[] = [
    {
      id: 'a1',
      lead_id: 'l1',
      tipo: 'llamada_realizada',
      detalle: null,
      autor_nombre: 'Analista',
      creado_en: '2026-07-17T15:00:00.000Z',
    },
  ]

  it('el panel de confirmación NOMBRA la etapa a la que vuelve el lead', async () => {
    const user = userEvent.setup()
    montar(REUNION, CONTACTO, { ok: true }, [], EN_REUNION)

    await user.click(screen.getByRole('button', { name: /anular esta tarea/i }))

    expect(panelAnular()?.textContent).toContain('Era su única cita')
    expect(panelAnular()?.textContent).toContain('vuelve a la etapa «Contactado»')
  })

  it('y encamina a Reprogramar, que es lo que casi siempre se quería hacer', async () => {
    const user = userEvent.setup()
    montar(REUNION, CONTACTO, { ok: true }, [], EN_REUNION)

    await user.click(screen.getByRole('button', { name: /anular esta tarea/i }))

    expect(panelAnular()?.textContent).toContain('usa Reprogramar en vez de anular')
  })

  it('si QUEDA otra reunión viva no promete ningún retroceso', async () => {
    const user = userEvent.setup()
    const otra: Tarea = { ...REUNION, id: 't-reu2', titulo: 'Otra reunión' }
    montar(REUNION, CONTACTO, { ok: true }, [otra], EN_REUNION)

    await user.click(screen.getByRole('button', { name: /anular esta tarea/i }))

    expect(panelAnular()?.textContent).not.toContain('Era su única cita')
  })

  it('anular una LLAMADA no menciona etapas aunque el lead esté en reunión', async () => {
    const user = userEvent.setup()
    montar(TAREA_LLAMADA, CONTACTO, { ok: true }, [REUNION], EN_REUNION)

    await user.click(screen.getByRole('button', { name: /anular esta tarea/i }))

    expect(panelAnular()?.textContent).not.toContain('Era su única cita')
  })

  it('el toast canta la etapa nueva y no el aviso de «sin próxima acción»', async () => {
    const user = userEvent.setup()
    montar(REUNION, CONTACTO, { ok: true }, [], EN_REUNION, 'contactado')

    await user.click(screen.getByRole('button', { name: /anular esta tarea/i }))
    await user.selectOptions(
      screen.getByLabelText('Motivo de cancelación de la cita'),
      'cancelada_cliente',
    )
    await user.click(screen.getByRole('button', { name: /sí, anular/i }))

    expect(toast.warning).toHaveBeenCalledTimes(1)
    expect(toast.warning).toHaveBeenCalledWith(expect.stringContaining('vuelve a «Contactado»'))
  })
})

describe('CerrarTareaDialog — «No asistió» espera a la hora de la cita', () => {
  // Miguel, 2026-10-05: «una reunión realizada antes de la hora pactada puede
  // marcarse realizada inmediatamente […]. Solo "No asistió" debe esperar a que
  // haya pasado la hora pactada». El servidor lo exige (22023 desde el candado
  // de crm.tareas); el diálogo no debe ofrecer lo que va a rebotar.
  const AHORA = Date.parse('2026-10-06T15:00:00.000Z') // 10:00 en Lima
  const HORA = 3_600_000
  const citaA = (ms: number): Tarea => ({
    ...TAREA,
    id: 't-cita',
    tipo: 'reunion',
    titulo: 'Reunión con Ana',
    vence_en: new Date(ms).toISOString(),
  })
  const noAsistio = () => screen.getByRole('button', { name: 'No asistió' })
  const AVISO = /se habilita a la hora de la cita/i

  // Solo el reloj: los temporizadores siguen siendo reales, así que user-event
  // funciona como en el resto del archivo.
  beforeEach(() => {
    vi.useFakeTimers({ now: AHORA, toFake: ['Date'] })
  })
  afterEach(() => {
    vi.useRealTimers()
  })

  it('antes de la hora, «No asistió» está inerte y dice desde cuándo', async () => {
    const user = userEvent.setup()
    const { completarTarea } = montar(citaA(AHORA + 7 * HORA)) // 17:00 en Lima

    // `aria-disabled` y no `disabled`: el botón sigue enfocable para que quien
    // navega con teclado o lector llegue a él y oiga por qué no se puede.
    expect(noAsistio()).toHaveAttribute('aria-disabled', 'true')
    expect(noAsistio()).toHaveAccessibleDescription(AVISO)
    // La explicación está a la vista y dice CUÁNDO.
    expect(screen.getByText(AVISO)).toHaveTextContent('Hoy · 17:00')

    // Inerte de verdad: pulsarla no la elige ni habilita el cierre.
    await user.click(noAsistio())
    expect(noAsistio()).toHaveAttribute('aria-pressed', 'false')
    expect(screen.getByRole('button', { name: /cerrar tarea/i })).toBeDisabled()
    expect(completarTarea).not.toHaveBeenCalled()
  })

  it('«Se realizó» no cambia: la reunión anticipada se registra en el acto', async () => {
    const user = userEvent.setup()
    montar(citaA(AHORA + 7 * HORA))
    const seRealizo = screen.getByRole('button', { name: 'Se realizó' })

    expect(seRealizo).not.toHaveAttribute('aria-disabled')
    await user.click(seRealizo)

    expect(seRealizo).toHaveAttribute('aria-pressed', 'true')
    expect(screen.getByLabelText('Resultado comercial')).toBeInTheDocument()
  })

  it('pasada la hora, «No asistió» está activa como siempre y sin aviso', async () => {
    const user = userEvent.setup()
    const { completarTarea } = montar(citaA(AHORA - HORA))

    expect(noAsistio()).not.toHaveAttribute('aria-disabled')
    expect(noAsistio()).not.toHaveAttribute('aria-describedby')
    expect(screen.queryByText(AVISO)).not.toBeInTheDocument()

    await user.click(noAsistio())
    await user.click(screen.getByRole('button', { name: 'Saltar esta vez' }))
    await user.click(screen.getByRole('button', { name: /cerrar tarea/i }))
    expect(completarTarea.mock.calls[0]?.[0]).toMatchObject({ tarea_id: 't-cita', estado: 'no_show' })
  })

  it('en el instante exacto de la hora ya está activa (mismo borde que el servidor)', () => {
    montar(citaA(AHORA))

    expect(noAsistio()).not.toHaveAttribute('aria-disabled')
    expect(screen.queryByText(AVISO)).not.toBeInTheDocument()
  })

  // La cita de las 10:00:30 con el diálogo abierto desde las 10:00:00: el reloj
  // compartido tickea cada minuto, pero la opción no puede quedarse inerte
  // medio minuto después de que el servidor ya la acepta.
  it('con el diálogo abierto, se activa sola al llegar la hora: ni un milisegundo antes', async () => {
    vi.useRealTimers()
    vi.useFakeTimers({ now: AHORA })
    montar(citaA(AHORA + 30_000))
    expect(noAsistio()).toHaveAttribute('aria-disabled', 'true')

    await act(async () => { await vi.advanceTimersByTimeAsync(29_999) })
    expect(noAsistio()).toHaveAttribute('aria-disabled', 'true')
    expect(screen.getByText(AVISO)).toBeInTheDocument()

    await act(async () => { await vi.advanceTimersByTimeAsync(1) })
    expect(noAsistio()).not.toHaveAttribute('aria-disabled')
    expect(screen.queryByText(AVISO)).not.toBeInTheDocument()
  })

  // La hora que llega ENTRE el render y el efecto (revisión de Codex, 06/10):
  // el render lee las 10:00:29.999 —«falta»— y el efecto corre a las
  // 10:00:30.005. Sin reconciliar, no se arma temporizador (ya no falta nada)
  // ni se actualiza nada, y la opción se queda inerte hasta el siguiente tick
  // del reloj compartido: hasta un minuto con el servidor ya aceptando.
  it('si la hora llega entre el render y el efecto, se activa igual, sin esperar al siguiente tick', () => {
    const cita = AHORA + 30_000
    vi.setSystemTime(cita - 1)
    let inerteAlPintar: string | null | undefined
    montar(citaA(cita), [], { ok: true }, [], {}, undefined, undefined, () => {
      const boton = screen.queryByRole('button', { name: 'No asistió' })
      if (!boton || inerteAlPintar !== undefined) return
      // Pintado con el reloj en «falta 1 ms»; los efectos corren 6 ms después.
      inerteAlPintar = boton.getAttribute('aria-disabled')
      vi.setSystemTime(cita + 5)
    })

    // El render SÍ vio que faltaba (si no, esta prueba no mediría el hueco)…
    expect(inerteAlPintar).toBe('true')
    // …y aun así la opción queda activa en cuanto corre el efecto.
    expect(noAsistio()).not.toHaveAttribute('aria-disabled')
    expect(screen.queryByText(AVISO)).not.toBeInTheDocument()
  })

  // El temporizador despierta, pero la hora NO ha llegado: el dispositivo
  // corrigió su reloj hacia atrás (o el temporizador se adelantó). Dar por
  // cumplida la hora objetivo sin mirar el reloj habilitaría la opción antes de
  // tiempo: tiene que volver a leerlo, seguir inerte y reprogramarse.
  it('si el reloj se atrasó, al despertar vuelve a mirar la hora: sigue inerte y se reprograma', async () => {
    vi.useRealTimers()
    vi.useFakeTimers({ now: AHORA })
    montar(citaA(AHORA + 30_000))
    // El dispositivo retrocede 10 s; el temporizador ya armado (30 s) no se entera.
    vi.setSystemTime(AHORA - 10_000)

    // Despierta cuando el reloj marca «AHORA + 20 s»: faltan 10 s para la cita.
    await act(async () => { await vi.advanceTimersByTimeAsync(30_000) })
    expect(noAsistio()).toHaveAttribute('aria-disabled', 'true')
    expect(screen.getByText(AVISO)).toBeInTheDocument()

    // Se reprogramó para lo que falta de verdad: ni un milisegundo antes.
    await act(async () => { await vi.advanceTimersByTimeAsync(9_999) })
    expect(noAsistio()).toHaveAttribute('aria-disabled', 'true')
    await act(async () => { await vi.advanceTimersByTimeAsync(1) })
    expect(noAsistio()).not.toHaveAttribute('aria-disabled')
    expect(screen.queryByText(AVISO)).not.toBeInTheDocument()
  })

  it('una tarea que no es reunión no lleva el aviso aunque su hora no haya llegado', () => {
    montar({ ...TAREA, vence_en: new Date(AHORA + 7 * HORA).toISOString() })

    expect(screen.queryByText(AVISO)).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Enviado' })).not.toHaveAttribute('aria-disabled')
  })

  // Reloj del dispositivo adelantado o pantalla vieja: el diálogo cree que la
  // hora pasó y el servidor dice que no. El aviso del rechazo lo da el store
  // (toast con el mensaje del servidor); aquí se exige que el diálogo NO cante
  // éxito y se quede abierto para reintentar cuando llegue la hora.
  it('si el servidor rechaza el «No asistió» igualmente, no canta éxito y sigue abierto', async () => {
    vi.mocked(toast.success).mockClear()
    vi.mocked(toast.warning).mockClear()
    const user = userEvent.setup()
    const { completarTarea, onCerrar } = montar(citaA(AHORA - 1_000), [], {
      ok: true,
      persistido: Promise.resolve(false),
    })

    await user.click(noAsistio())
    await user.click(screen.getByRole('button', { name: 'Saltar esta vez' }))
    await user.click(screen.getByRole('button', { name: /cerrar tarea/i }))

    await waitFor(() => expect(screen.getByRole('button', { name: /cerrar tarea/i })).toBeEnabled())
    expect(completarTarea).toHaveBeenCalledTimes(1)
    expect(toast.success).not.toHaveBeenCalled()
    expect(toast.warning).not.toHaveBeenCalled()
    expect(onCerrar).not.toHaveBeenCalled()
  })
})

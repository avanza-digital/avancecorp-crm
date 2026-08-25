// Tests del diálogo de cierre: resultado 1-tap obligatorio, la sugerencia del
// motor aparece al elegir, "saltar" a un toque, y el payload que viaja al store.
import { describe, expect, it, vi } from 'vitest'
import { act, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { toast } from 'sonner'
import { StoreDataContext } from '@/lib/store-context'
import type { StoreDataApi } from '@/lib/store'
import type { Actividad, EtapaActiva, Lead, Tarea } from '@/lib/tipos'
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
    autor_nombre: 'Vendedor',
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
  } as unknown as StoreDataApi
  const onCerrar = vi.fn()
  render(
    <StoreDataContext.Provider value={api}>
      <CerrarTareaDialog tarea={tarea} onCerrar={onCerrar} />
    </StoreDataContext.Provider>,
  )
  return { completarTarea, anularTarea, descartar, onCerrar }
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
    await user.selectOptions(screen.getByLabelText('Modalidad de la reunión'), 'virtual')
    await user.type(
      screen.getByLabelText('Enlace de la reunión'),
      'https://meet.google.com/abc-defg-hij',
    )
    await user.click(screen.getByRole('button', { name: /cerrar tarea/i }))
    expect(completarTarea.mock.calls[0]?.[0]).toMatchObject({ estado: 'no_show' })
  })

  it('una reunión de cliente espera el COMMIT clasificado antes de cerrar y avisar éxito', async () => {
    vi.mocked(toast.success).mockClear()
    const user = userEvent.setup()
    const commit = diferida<boolean>()
    const { completarTarea, onCerrar } = montar(TAREA_CLIENTE, [], {
      ok: true,
      persistido: commit.promesa,
    })

    await user.click(screen.getByRole('button', { name: 'Se realizó' }))
    await user.selectOptions(screen.getByLabelText('Resultado comercial'), 'interesado')
    const clic = user.click(screen.getByRole('button', { name: /cerrar tarea/i }))
    await waitFor(() => expect(completarTarea).toHaveBeenCalledTimes(1))

    expect(completarTarea).toHaveBeenCalledWith(
      expect.objectContaining({
        tarea_id: 't-cliente',
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

  it('si el servidor rechaza el cierre de cliente, no muestra éxito y deja el diálogo abierto', async () => {
    vi.mocked(toast.success).mockClear()
    const user = userEvent.setup()
    const commit = diferida<boolean>()
    const { completarTarea, onCerrar } = montar(TAREA_CLIENTE, [], {
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
      screen.getByLabelText('Motivo de cancelación de la reunión'),
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

      await user.click(screen.getByRole('button', { name: 'Contestó' }))

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
      await user.click(screen.getByRole('button', { name: 'Contestó' }))
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
      autor_nombre: 'Vendedor',
      creado_en: '2026-07-17T15:00:00.000Z',
    },
  ]

  it('el panel de confirmación NOMBRA la etapa a la que vuelve el lead', async () => {
    const user = userEvent.setup()
    montar(REUNION, CONTACTO, { ok: true }, [], EN_REUNION)

    await user.click(screen.getByRole('button', { name: /anular esta tarea/i }))

    expect(panelAnular()?.textContent).toContain('Era su única reunión')
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

    expect(panelAnular()?.textContent).not.toContain('Era su única reunión')
  })

  it('anular una LLAMADA no menciona etapas aunque el lead esté en reunión', async () => {
    const user = userEvent.setup()
    montar(TAREA, CONTACTO, { ok: true }, [REUNION], EN_REUNION)

    await user.click(screen.getByRole('button', { name: /anular esta tarea/i }))

    expect(panelAnular()?.textContent).not.toContain('Era su única reunión')
  })

  it('el toast canta la etapa nueva y no el aviso de «sin próxima acción»', async () => {
    const user = userEvent.setup()
    montar(REUNION, CONTACTO, { ok: true }, [], EN_REUNION, 'contactado')

    await user.click(screen.getByRole('button', { name: /anular esta tarea/i }))
    await user.selectOptions(
      screen.getByLabelText('Motivo de cancelación de la reunión'),
      'cancelada_cliente',
    )
    await user.click(screen.getByRole('button', { name: /sí, anular/i }))

    expect(toast.warning).toHaveBeenCalledTimes(1)
    expect(toast.warning).toHaveBeenCalledWith(expect.stringContaining('vuelve a «Contactado»'))
  })
})

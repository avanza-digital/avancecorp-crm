import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { toast } from 'sonner'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import {
  PanelActionsContext,
  PanelStateContext,
  StoreDataContext,
} from '@/lib/store-context'
import type { PanelesActions, ResultadoMut, StoreDataApi } from '@/lib/store'
import type { EtapaActiva, Lead, Tarea } from '@/lib/tipos'
import { LeadDrawer } from './lead-drawer'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

const LEAD: Lead = {
  id: 'lead-capital-1',
  nombre_completo: 'ANA CAPITAL PRUEBA',
  telefono: '+51987654321',
  correo: 'ana@prueba.invalid',
  etapa: 'nuevo',
  origen: 'landing',
  monto_estimado: 5_000,
  moneda: 'PEN',
  categoria_interes: null,
  vendedor_id: 'vendedor-1',
  vendedor_nombre: 'VENDEDOR PRUEBA',
  asignado_supervisor_id: null,
  creado_en: '2026-07-17T12:00:00.000Z',
  activo: true,
  dni: null,
  distrito: null,
  nota: null,
  motivo_descarte: null,
}

const SESION: AuthContextValue = {
  fase: 'listo',
  yo: {
    id: 'vendedor-1',
    nombre_completo: 'VENDEDOR PRUEBA',
    rol: 'vendedor',
    demo: true,
    puede_contratar: true,
  },
  error: null,
  entrar: async () => ({ ok: true }),
  entrarDemo: () => undefined,
  reintentar: () => undefined,
  salir: async () => undefined,
}

function montar({
  lead = {},
  resultadoEditar = { ok: true },
  avance,
  avanceTarea,
  tareas = [],
  actividades = [],
  retroceso,
}: {
  lead?: Partial<Lead>
  resultadoEditar?: ResultadoMut
  /** Etapa a la que sube el lead SOLO por registrar la actividad (avance automático). */
  avance?: EtapaActiva
  /** Etapa a la que sube el lead SOLO por AGENDAR la tarea (espejo del trigger). */
  avanceTarea?: EtapaActiva
  /** Pendientes del lead — la lista que pinta «Próxima acción». */
  tareas?: Tarea[]
  /** Timeline del lead: `retrocesoPorAnularReunion` corre DE VERDAD en el
   *  componente y necesita saber si hubo contacto real (y si la reunión llegó
   *  a ocurrir) para decidir a qué etapa devolvería el lead. */
  actividades?: { tipo: string }[]
  /** Etapa a la que BAJA el lead al anular (lo que devuelve el store real). */
  retroceso?: EtapaActiva
} = {}) {
  const l: Lead = { ...LEAD, ...lead }
  const editarLead = vi.fn<StoreDataApi['editarLead']>(() => resultadoEditar)
  const registrarActividad = vi.fn<StoreDataApi['registrarActividad']>(() =>
    avance ? { ok: true, avance } : { ok: true },
  )
  const crearTarea = vi.fn<StoreDataApi['crearTarea']>(() =>
    avanceTarea ? { ok: true, id: 't-test', avance: avanceTarea } : { ok: true, id: 't-test' },
  )
  const anularTarea = vi.fn<StoreDataApi['anularTarea']>(() =>
    retroceso ? { ok: true, retroceso } : { ok: true },
  )
  const api = {
    lead: (id: string) => (id === l.id ? l : undefined),
    ambito: { leads: [l], vendedores: [], esGlobal: false },
    actividadesDe: () => actividades,
    tareasDe: () => tareas,
    crearTarea,
    anularTarea,
    editarLead,
    reasignar: vi.fn(() => ({ ok: true })),
    cambiarEtapa: vi.fn(() => ({ ok: true })),
    reabrir: vi.fn(() => ({ ok: true })),
    registrarActividad,
    // Sin anulaciones: el banner terminal lo consulta para decidir si marca el
    // cierre y si ofrece anularlo.
    cierresEstado: [],
  } as unknown as StoreDataApi
  const actions: PanelesActions = {
    abrirLead: vi.fn(),
    abrirNuevoLead: vi.fn(),
    cerrarPaneles: vi.fn(),
  }

  // El banner de un lead terminal consulta el estado de su cierre con TanStack.
  // La sesión de este archivo es DEMO, así que la consulta nace deshabilitada y
  // no sale ni una petición — pero el hook necesita cliente igual. Se monta uno
  // desechable en vez de mockear el módulo entero: así el árbol que se prueba
  // sigue siendo el de verdad.
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  })

  render(
    <QueryClientProvider client={queryClient}>
      <AuthContext.Provider value={SESION}>
        <StoreDataContext.Provider value={api}>
          <PanelStateContext.Provider
            value={{ leadAbiertoId: l.id, nuevoLeadAbierto: false, etapaInicial: 'nuevo', telefonoInicial: null }}
          >
            <PanelActionsContext.Provider value={actions}>
              <LeadDrawer />
            </PanelActionsContext.Provider>
          </PanelStateContext.Provider>
        </StoreDataContext.Provider>
      </AuthContext.Provider>
    </QueryClientProvider>,
  )

  return { editarLead, registrarActividad, crearTarea, anularTarea }
}

beforeEach(() => vi.clearAllMocks())

describe('LeadDrawer — edición de clasificación por capital', () => {
  it('muestra el segundo celular cuando el lead lo trae de la fuente', () => {
    montar({ lead: { telefono_alternativo: '+51911222333' } })

    expect(screen.getByText('Teléfono alternativo')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: '+51911222333' })).toHaveAttribute(
      'href',
      'tel:+51911222333',
    )
  })

  it('el segundo número también se puede escribir por WhatsApp', () => {
    montar({ lead: { telefono_alternativo: '+51911222333' } })

    expect(screen.getByRole('link', { name: 'WhatsApp' })).toHaveAttribute(
      'href',
      'https://wa.me/51911222333',
    )
  })

  it('un FIJO como segundo número no ofrece WhatsApp: allí no responde nadie', () => {
    montar({ lead: { telefono_alternativo: '+5114457890' } })

    expect(screen.getByRole('link', { name: '+5114457890' })).toBeInTheDocument()
    expect(screen.queryByRole('link', { name: 'WhatsApp' })).not.toBeInTheDocument()
  })

  it('lo ilegible se muestra tal como llegó, marcado y SIN enlace', () => {
    // Nada se pierde en silencio (decisión de Miguel, 2026-08-26). Y no se
    // ofrece como marcable: un `tel:` sobre algo que no se pudo entender
    // marcaría cualquier cosa.
    montar({ lead: { telefono_alternativo: null, telefono_alternativo_crudo: '99988 7' } })

    expect(screen.getByText('«99988 7»')).toBeInTheDocument()
    expect(screen.getByText('sin validar')).toBeInTheDocument()
    expect(screen.queryByRole('link', { name: /99988/ })).not.toBeInTheDocument()
  })

  it('sin segundo número lo DICE, en vez de dejar un hueco', () => {
    // El hueco dejaba al vendedor sin saber si el CRM se comió un dato o si el
    // origen nunca lo dio. El 84,2 % de las filas del origen no trae segundo
    // número: este es el caso mayoritario, no la excepción.
    montar({ lead: { telefono_alternativo: null, telefono_alternativo_crudo: null } })

    expect(screen.getByText('Teléfono alternativo')).toBeInTheDocument()
    expect(screen.getByText('— el origen no dio un segundo número')).toBeInTheDocument()
  })

  it('guarda capital y moneda juntos', async () => {
    const user = userEvent.setup()
    const { editarLead } = montar()

    await user.click(screen.getByRole('button', { name: 'Editar' }))
    const monto = screen.getByLabelText('Capital estimado *')
    await user.clear(monto)
    await user.type(monto, '25000')
    await user.selectOptions(screen.getByLabelText('Moneda del capital estimado'), 'USD')
    await user.click(screen.getByRole('button', { name: 'Guardar' }))

    expect(editarLead).toHaveBeenCalledWith(
      LEAD.id,
      expect.objectContaining({ monto_estimado: 25_000, moneda: 'USD' }),
    )
  })

  it('no permite borrar ni guardar en cero el capital', async () => {
    const user = userEvent.setup()
    const { editarLead } = montar()

    await user.click(screen.getByRole('button', { name: 'Editar' }))
    const monto = screen.getByLabelText('Capital estimado *')
    await user.clear(monto)
    await user.click(screen.getByRole('button', { name: 'Guardar' }))

    expect(screen.getByText('El capital estimado es obligatorio y debe ser mayor que 0')).toBeInTheDocument()
    expect(editarLead).not.toHaveBeenCalled()

    await user.type(monto, '0')
    await user.click(screen.getByRole('button', { name: 'Guardar' }))
    expect(editarLead).not.toHaveBeenCalled()
  })
})

// El aviso "Faltan DNI, distrito y categoría → Completar" mandaba a un
// formulario que no tenía ninguno de los tres: el asesor no podía resolver lo
// que se le pedía y el aviso volvía a salir después de guardar. Con 64/64 leads
// de producción sin DNI, era un callejón sin salida en el 100% de las fichas.
describe('LeadDrawer — «Completar» resuelve de verdad los datos que faltan', () => {
  it('el botón del aviso abre un formulario que SÍ tiene DNI, distrito y categoría', async () => {
    const user = userEvent.setup()
    montar()

    expect(screen.getByText(/Faltan DNI, distrito, categoría y nota/)).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Completar' }))

    expect(screen.getByLabelText('DNI')).toBeInTheDocument()
    expect(screen.getByLabelText('Distrito')).toBeInTheDocument()
    expect(screen.getByRole('group', { name: 'Categoría de interés' })).toBeInTheDocument()
  })

  it('guarda los tres campos en la MISMA escritura que el resto de la ficha', async () => {
    const user = userEvent.setup()
    const { editarLead } = montar()

    await user.click(screen.getByRole('button', { name: 'Completar' }))
    await user.type(screen.getByLabelText('DNI'), '45781234')
    await user.type(screen.getByLabelText('Distrito'), 'Miraflores')
    await user.click(screen.getByRole('button', { name: 'Renovación' }))
    await user.click(screen.getByRole('button', { name: 'Guardar' }))

    expect(editarLead).toHaveBeenCalledWith(
      LEAD.id,
      expect.objectContaining({
        dni: '45781234',
        distrito: 'Miraflores',
        categoria_interes: 'renovacion',
      }),
    )
    expect(toast.success).toHaveBeenCalledWith('Cambios guardados (demo)')
  })

  it('precarga los valores que el lead ya tiene (editar no es volver a empezar)', async () => {
    const user = userEvent.setup()
    montar({ lead: { dni: '12345678', distrito: 'Surco', categoria_interes: 'upgrade' } })

    await user.click(screen.getByRole('button', { name: 'Editar' }))

    expect(screen.getByLabelText('DNI')).toHaveValue('12345678')
    expect(screen.getByLabelText('Distrito')).toHaveValue('Surco')
    expect(screen.getByRole('button', { name: 'Upgrade' })).toHaveAttribute('aria-pressed', 'true')
  })

  it('la categoría se puede DESELECCIONAR (volver a "sin dato" es legítimo)', async () => {
    const user = userEvent.setup()
    const { editarLead } = montar({ lead: { categoria_interes: 'upgrade' } })

    await user.click(screen.getByRole('button', { name: 'Editar' }))
    await user.click(screen.getByRole('button', { name: 'Upgrade' }))
    await user.click(screen.getByRole('button', { name: 'Guardar' }))

    expect(editarLead).toHaveBeenCalledWith(LEAD.id, expect.objectContaining({ categoria_interes: null }))
  })

  it('el DNI solo admite dígitos y como máximo 8 (regla del portal)', async () => {
    const user = userEvent.setup()
    const { editarLead } = montar()

    await user.click(screen.getByRole('button', { name: 'Editar' }))
    await user.type(screen.getByLabelText('DNI'), 'AB4578-1234999')
    await user.click(screen.getByRole('button', { name: 'Guardar' }))

    expect(editarLead).toHaveBeenCalledWith(LEAD.id, expect.objectContaining({ dni: '45781234' }))
  })

  it('pegar un DNI con puntos NO pierde dígitos (el tope va después de filtrar)', async () => {
    const user = userEvent.setup()
    const { editarLead } = montar()

    await user.click(screen.getByRole('button', { name: 'Editar' }))
    await user.click(screen.getByLabelText('DNI'))
    await user.paste('12.345.678')
    await user.click(screen.getByRole('button', { name: 'Guardar' }))

    // Con maxLength={8} esto se cortaba a "12.345.6" → 6 dígitos en silencio.
    expect(editarLead).toHaveBeenCalledWith(LEAD.id, expect.objectContaining({ dni: '12345678' }))
  })

  it('el error del store se ancla al campo culpable, no al primero del formulario', async () => {
    const user = userEvent.setup()
    montar({
      resultadoEditar: {
        ok: false,
        campo: 'dni',
        error: 'El DNI debe tener exactamente 8 dígitos',
      },
    })

    await user.click(screen.getByRole('button', { name: 'Editar' }))
    await user.type(screen.getByLabelText('DNI'), '4578')
    await user.click(screen.getByRole('button', { name: 'Guardar' }))

    expect(screen.getByRole('alert')).toHaveTextContent('El DNI debe tener exactamente 8 dígitos')
    expect(screen.getByLabelText('DNI')).toHaveAttribute('aria-invalid', 'true')
    expect(screen.getByLabelText('Capital estimado *')).toHaveAttribute('aria-invalid', 'false')
    // El formulario sigue abierto para corregir (no se cerró creyendo que guardó).
    expect(screen.getByRole('button', { name: 'Guardar' })).toBeInTheDocument()

    // Y al corregir, la marca se va: quedarse pegada describe un error resuelto.
    await user.type(screen.getByLabelText('DNI'), '1234')
    expect(screen.getByLabelText('DNI')).toHaveAttribute('aria-invalid', 'false')
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })
})

describe('LeadDrawer — rótulo del capital según el desenlace', () => {
  it('un lead activo tiene capital EN JUEGO', () => {
    montar()
    expect(screen.getByText('en juego')).toBeInTheDocument()
  })

  it('un lead DESCARTADO no tiene capital en juego', () => {
    montar({ lead: { etapa: 'descartado', motivo_descarte: 'sin_interes' } })
    expect(screen.queryByText('en juego')).not.toBeInTheDocument()
    expect(screen.getByText('no concretado')).toBeInTheDocument()
  })

  it('un lead CONVERTIDO lo tiene ganado', () => {
    montar({ lead: { etapa: 'convertido' } })
    expect(screen.queryByText('en juego')).not.toBeInTheDocument()
    expect(screen.getByText('ganado')).toBeInTheDocument()
  })
})

// Un cambio de etapa silencioso asusta más que ayuda: el composer tiraba el
// `avance` del store y el stepper se movía solo, sin explicación.
describe('LeadDrawer — el composer canta el avance automático de etapa', () => {
  it('lo dice cuando el contacto sube la etapa del lead', async () => {
    const user = userEvent.setup()
    montar({ avance: 'contactado' })

    await user.click(screen.getByRole('button', { name: /Registrar actividad/ }))
    await user.click(screen.getByRole('button', { name: 'Registrar' }))

    expect(toast.success).toHaveBeenCalledWith('Actividad registrada · pasó a Contactado (demo)')
  })

  it('sin avance, el aviso no inventa un cambio de etapa', async () => {
    const user = userEvent.setup()
    montar()

    await user.click(screen.getByRole('button', { name: /Registrar actividad/ }))
    await user.click(screen.getByRole('button', { name: 'Registrar' }))

    expect(toast.success).toHaveBeenCalledWith('Actividad registrada (demo)')
  })
})

// Agendar una reunión con quien ya se trabajó sube el lead por trigger. El
// store lo calculaba, movía la etapa… y no lo decía: era el único de los tres
// escritores que cambiaba el embudo a espaldas del asesor.
describe('LeadDrawer — «Próxima acción» canta el avance de agendar', () => {
  it('lo dice cuando agendar la tarea sube la etapa del lead', async () => {
    const user = userEvent.setup()
    montar({ avanceTarea: 'reunion_agendada' })

    await user.selectOptions(screen.getByLabelText('Tipo de tarea'), 'reunion')
    await user.selectOptions(screen.getByLabelText('Modalidad de la reunión'), 'virtual')
    await user.type(
      screen.getByLabelText('Enlace de la reunión'),
      'https://meet.google.com/abc-defg-hij',
    )
    await user.click(screen.getByRole('button', { name: 'Agendar' }))

    expect(toast.success).toHaveBeenCalledWith(
      'Tarea agendada · pasó a Reunión agendada · la verás en Hoy y en Agenda (demo)',
    )
  })

  it('sin avance, el aviso de siempre y ningún cambio de etapa inventado', async () => {
    const user = userEvent.setup()
    montar()

    await user.click(screen.getByRole('button', { name: 'Agendar' }))

    expect(toast.success).toHaveBeenCalledWith('Tarea agendada · la verás en Hoy y en Agenda (demo)')
  })
})

// ANULAR desde la ficha (pedido de Miguel 2026-07-26): agendas la reunión y la
// llamada de la semana pasada sobra. Sin este botón el único camino para
// sacarla de la agenda era cerrarla con un resultado FALSO.
describe('LeadDrawer — anular una pendiente que ya no hace falta', () => {
  const pendiente = (id: string, titulo: string, tipo: Tarea['tipo'] = 'llamada'): Tarea => ({
    id,
    lead_id: LEAD.id,
    tipo,
    titulo,
    vence_en: new Date(Date.now() + 86_400_000).toISOString(),
    estado: 'pendiente',
    reprogramaciones: 0,
    activo: true,
    creado_en: new Date().toISOString(),
  })

  it('pide confirmación antes de anular (un tap no basta: es irreversible)', async () => {
    const user = userEvent.setup()
    const { anularTarea } = montar({ tareas: [pendiente('t1', 'Llamar a Ana')] })

    await user.click(screen.getByRole('button', { name: 'Anular tarea — Llamar a Ana' }))

    expect(anularTarea).not.toHaveBeenCalled()
    expect(screen.getByRole('button', { name: 'Sí, anular — Llamar a Ana' })).toBeInTheDocument()
  })

  // El bug que encontró la auditoría: cuando la confirmación REEMPLAZABA la
  // fila, «Sí, anular» nacía cubriendo los 24 px del icono que acababa de
  // armarlo → un doble clic anulaba sin que nadie leyera la pregunta.
  it('la fila NO se mueve al armar: el destructivo nunca nace bajo el cursor', async () => {
    const user = userEvent.setup()
    montar({ tareas: [pendiente('t1', 'Llamar a Ana')] })
    const disparador = screen.getByRole('button', { name: 'Anular tarea — Llamar a Ana' })
    const fila = disparador.closest('li')
    const primeraLinea = disparador.parentElement

    await user.click(disparador)

    // El icono sigue existiendo, en la MISMA línea y en la misma posición.
    expect(disparador.parentElement).toBe(primeraLinea)
    expect(primeraLinea?.lastElementChild).toBe(disparador)
    // Y el destructivo está en OTRA línea, la de abajo.
    const confirmar = screen.getByRole('button', { name: 'Sí, anular — Llamar a Ana' })
    expect(confirmar.parentElement).not.toBe(primeraLinea)
    expect(fila?.contains(confirmar)).toBe(true)
  })

  it('doble clic en el icono se cancela a sí mismo (es un interruptor)', async () => {
    const user = userEvent.setup()
    const { anularTarea } = montar({ tareas: [pendiente('t1', 'Llamar a Ana')] })
    const disparador = screen.getByRole('button', { name: 'Anular tarea — Llamar a Ana' })

    await user.dblClick(disparador)

    expect(anularTarea).not.toHaveBeenCalled()
    expect(disparador).toHaveAttribute('aria-expanded', 'false')
    expect(screen.queryByRole('button', { name: 'Sí, anular — Llamar a Ana' })).not.toBeInTheDocument()
  })

  it('confirmar anula esa tarea y avisa que el lead se queda sin plan', async () => {
    const user = userEvent.setup()
    const { anularTarea } = montar({ tareas: [pendiente('t1', 'Llamar a Ana')] })

    await user.click(screen.getByRole('button', { name: 'Anular tarea — Llamar a Ana' }))
    await user.click(screen.getByRole('button', { name: 'Sí, anular — Llamar a Ana' }))

    expect(anularTarea).toHaveBeenCalledWith('t1')
    expect(toast.warning).toHaveBeenCalledWith(
      'Tarea anulada — Ana quedó SIN próxima acción (demo)',
    )
  })

  it('con OTRA pendiente viva no promete el amarillo (el caso que lo motivó)', async () => {
    // Exactamente el escenario de Miguel: queda la reunión agendada, así que el
    // lead NO se queda sin próxima acción y decirlo sería mentira.
    const user = userEvent.setup()
    const reunion = { ...pendiente('t2', 'Reunión con Ana'), tipo: 'reunion' as const }
    montar({ tareas: [pendiente('t1', 'Llamar a Ana'), reunion] })

    await user.click(screen.getByRole('button', { name: 'Anular tarea — Llamar a Ana' }))
    await user.click(screen.getByRole('button', { name: 'Sí, anular — Llamar a Ana' }))

    expect(toast.success).toHaveBeenCalledWith('Tarea anulada (demo)')
    expect(toast.warning).not.toHaveBeenCalled()
  })

  it('«No» cancela la confirmación sin tocar nada', async () => {
    const user = userEvent.setup()
    const { anularTarea } = montar({ tareas: [pendiente('t1', 'Llamar a Ana')] })

    await user.click(screen.getByRole('button', { name: 'Anular tarea — Llamar a Ana' }))
    await user.click(screen.getByRole('button', { name: 'No anular — Llamar a Ana' }))

    expect(anularTarea).not.toHaveBeenCalled()
    expect(screen.getByRole('button', { name: 'Anular tarea — Llamar a Ana' })).toBeInTheDocument()
  })

  it('un lead CERRADO no ofrece anular (sus pendientes las cancela el trigger)', () => {
    montar({ lead: { etapa: 'descartado', motivo_descarte: 'sin_interes' }, tareas: [pendiente('t1', 'Llamar a Ana')] })

    expect(screen.queryByRole('button', { name: /^Anular tarea/ })).not.toBeInTheDocument()
  })
})

// El bloque <Datos> era el ÚNICO sin `activa`: seguía ofreciendo escribir sobre
// un lead que el store ya no deja tocar (y cada escritura reescribía
// `actualizado_en`, que era el "mes de cierre" del marcador).
describe('LeadDrawer — un lead CERRADO no se edita desde la ficha', () => {
  it.each(['convertido', 'descartado'] as const)('sin «Editar» ni «Completar» en %s', (etapa) => {
    montar({ lead: { etapa, motivo_descarte: etapa === 'descartado' ? 'sin_interes' : null } })

    expect(screen.queryByRole('button', { name: 'Editar' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Completar' })).not.toBeInTheDocument()
    // La línea "Faltan …" tampoco: era un vacío accionable sin acción posible.
    expect(screen.queryByText(/^Faltan /)).not.toBeInTheDocument()
    // Los datos siguen LEYÉNDOSE: la ficha cerrada es el acta de lo que pasó.
    expect(screen.getByText('ANA CAPITAL PRUEBA')).toBeInTheDocument()
  })

  it('el badge de capital ausente deja de ser un botón en un lead cerrado', () => {
    montar({ lead: { etapa: 'convertido', monto_estimado: null as unknown as number } })

    expect(screen.getByText('Sin capital estimado')).toBeInTheDocument()
    expect(screen.queryByText('Sin capital estimado → completar')).not.toBeInTheDocument()
  })

  it('en un lead ABIERTO sigue todo donde estaba (no se rompió el camino normal)', () => {
    montar()

    expect(screen.getByRole('button', { name: 'Editar' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Completar' })).toBeInTheDocument()
  })
})

describe('LeadDrawer — anular la reunión devuelve el lead de etapa', () => {
  // Miguel, 2026-07-26: «si se anula la reu y no se reagenda una en ese mismo
  // momento, debería bajar de etapa». La consecuencia se ANUNCIA antes del tap:
  // descubrirla por el toast es descubrirla ya consumada.
  const reunion = (id: string, titulo: string): Tarea => ({
    id,
    lead_id: LEAD.id,
    tipo: 'reunion',
    titulo,
    vence_en: new Date(Date.now() + 86_400_000).toISOString(),
    estado: 'pendiente',
    reprogramaciones: 0,
    activo: true,
    creado_en: new Date().toISOString(),
  })

  const enReunion = { etapa: 'reunion_agendada' as const }

  it('la nota de confirmación AVISA del retroceso en vez de la frase genérica', async () => {
    const user = userEvent.setup()
    montar({
      lead: enReunion,
      tareas: [reunion('t1', 'Reunión con Ana')],
      actividades: [{ tipo: 'llamada_realizada' }],
    })

    await user.click(screen.getByRole('button', { name: 'Anular tarea — Reunión con Ana' }))

    const nota = document.getElementById('anular-nota-t1')
    expect(nota?.textContent).toContain('Era su única reunión')
    expect(nota?.textContent).toContain('Contactado')
  })

  it('la nota queda ANCLADA al destructivo: quien va por teclado la oye antes', async () => {
    const user = userEvent.setup()
    montar({
      lead: enReunion,
      tareas: [reunion('t1', 'Reunión con Ana')],
      actividades: [{ tipo: 'llamada_realizada' }],
    })

    await user.click(screen.getByRole('button', { name: 'Anular tarea — Reunión con Ana' }))

    const si = screen.getByRole('button', { name: 'Sí, anular — Reunión con Ana' })
    expect(si).toHaveAttribute('aria-describedby', 'anular-nota-t1')
  })

  it('si queda OTRA reunión viva vuelve a la frase genérica: ahí no baja nada', async () => {
    const user = userEvent.setup()
    montar({
      lead: enReunion,
      tareas: [reunion('t1', 'Reunión A'), reunion('t2', 'Reunión B')],
      actividades: [{ tipo: 'llamada_realizada' }],
    })

    await user.click(screen.getByRole('button', { name: 'Anular tarea — Reunión A' }))

    const nota = document.getElementById('anular-nota-t1')
    expect(nota?.textContent).toBe(
      'Queda cancelada con motivo en el reporte y no cuenta como realizada. No se puede deshacer.',
    )
  })

  it('anular una LLAMADA no promete ningún retroceso', async () => {
    const user = userEvent.setup()
    montar({
      lead: enReunion,
      tareas: [
        { ...reunion('t1', 'Llamar a Ana'), tipo: 'llamada' as const },
        reunion('t2', 'Reunión con Ana'),
      ],
      actividades: [{ tipo: 'llamada_realizada' }],
    })

    await user.click(screen.getByRole('button', { name: 'Anular tarea — Llamar a Ana' }))

    expect(document.getElementById('anular-nota-t1')?.textContent).toBe(
      'No queda como gestión ni en el historial. No se puede deshacer.',
    )
  })

  it('el toast canta la etapa nueva, no el genérico «Tarea anulada»', async () => {
    const user = userEvent.setup()
    montar({
      lead: enReunion,
      tareas: [reunion('t1', 'Reunión con Ana')],
      actividades: [{ tipo: 'llamada_realizada' }],
      retroceso: 'contactado',
    })

    await user.click(screen.getByRole('button', { name: 'Anular tarea — Reunión con Ana' }))
    await user.selectOptions(
      screen.getByLabelText('Motivo de cancelación — Reunión con Ana'),
      'cancelada_cliente',
    )
    await user.click(screen.getByRole('button', { name: 'Sí, anular — Reunión con Ana' }))

    expect(toast.warning).toHaveBeenCalledWith(expect.stringContaining('vuelve a «Contactado»'))
    expect(toast.success).not.toHaveBeenCalled()
  })

  it('el retroceso GANA al aviso de «sin próxima acción» (es el cambio mayor)', async () => {
    // Las dos cosas son ciertas a la vez —anular la última reunión suele dejar
    // al lead sin plan— pero dos toasts se pisan; canta el que más sorprende.
    const user = userEvent.setup()
    montar({
      lead: enReunion,
      tareas: [reunion('t1', 'Reunión con Ana')],
      actividades: [{ tipo: 'llamada_realizada' }],
      retroceso: 'contactado',
    })

    await user.click(screen.getByRole('button', { name: 'Anular tarea — Reunión con Ana' }))
    await user.selectOptions(
      screen.getByLabelText('Motivo de cancelación — Reunión con Ana'),
      'cancelada_cliente',
    )
    await user.click(screen.getByRole('button', { name: 'Sí, anular — Reunión con Ana' }))

    expect(toast.warning).toHaveBeenCalledTimes(1)
    expect(toast.warning).toHaveBeenCalledWith(expect.not.stringContaining('SIN próxima acción'))
  })
})

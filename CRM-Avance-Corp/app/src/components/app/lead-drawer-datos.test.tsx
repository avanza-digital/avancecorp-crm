import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { toast } from 'sonner'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import {
  PanelActionsContext,
  PanelStateContext,
  StoreDataContext,
} from '@/lib/store-context'
import type { PanelesActions, ResultadoMut, StoreDataApi } from '@/lib/store'
import type { EtapaActiva, Lead } from '@/lib/tipos'
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
}: {
  lead?: Partial<Lead>
  resultadoEditar?: ResultadoMut
  /** Etapa a la que sube el lead SOLO por registrar la actividad (avance automático). */
  avance?: EtapaActiva
  /** Etapa a la que sube el lead SOLO por AGENDAR la tarea (espejo del trigger). */
  avanceTarea?: EtapaActiva
} = {}) {
  const l: Lead = { ...LEAD, ...lead }
  const editarLead = vi.fn<StoreDataApi['editarLead']>(() => resultadoEditar)
  const registrarActividad = vi.fn<StoreDataApi['registrarActividad']>(() =>
    avance ? { ok: true, avance } : { ok: true },
  )
  const crearTarea = vi.fn<StoreDataApi['crearTarea']>(() =>
    avanceTarea ? { ok: true, id: 't-test', avance: avanceTarea } : { ok: true, id: 't-test' },
  )
  const api = {
    lead: (id: string) => (id === l.id ? l : undefined),
    ambito: { leads: [l], vendedores: [], esGlobal: false },
    actividadesDe: () => [],
    tareasDe: () => [],
    crearTarea,
    editarLead,
    reasignar: vi.fn(() => ({ ok: true })),
    cambiarEtapa: vi.fn(() => ({ ok: true })),
    reabrir: vi.fn(() => ({ ok: true })),
    registrarActividad,
  } as unknown as StoreDataApi
  const actions: PanelesActions = {
    abrirLead: vi.fn(),
    abrirNuevoLead: vi.fn(),
    cerrarPaneles: vi.fn(),
  }

  render(
    <AuthContext.Provider value={SESION}>
      <StoreDataContext.Provider value={api}>
        <PanelStateContext.Provider
          value={{ leadAbiertoId: l.id, nuevoLeadAbierto: false, etapaInicial: 'nuevo' }}
        >
          <PanelActionsContext.Provider value={actions}>
            <LeadDrawer />
          </PanelActionsContext.Provider>
        </PanelStateContext.Provider>
      </StoreDataContext.Provider>
    </AuthContext.Provider>,
  )

  return { editarLead, registrarActividad, crearTarea }
}

beforeEach(() => vi.clearAllMocks())

describe('LeadDrawer — edición de clasificación por capital', () => {
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

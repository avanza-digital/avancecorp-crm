// Tests de la pantalla AGENDA — las tres reglas que se rompieron en producción:
//  1. los saltos rápidos (+1d/+3d/+1sem) cuentan desde AHORA en una tarea
//     VENCIDA y desde su propia fecha en una FUTURA, siempre dentro de la
//     ventana legal (L–S 07:00–20:00);
//  2. Enter/Espacio sobre un botón de la tarjeta ejecuta ESE botón y NO abre la
//     ficha del lead (el guard `e.target !== e.currentTarget`);
//  3. en táctil los saltos existen (antes iban `hidden sm:flex` = invisibles
//     justo en el celular del asesor).
// Se montan los contextos REALES del store (sin red) y se mockean reloj, sesión
// y media query para que el resultado no dependa de la máquina.
import { describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { PanelActionsContext, StoreDataContext } from '@/lib/store-context'
import type { PanelesActions, StoreDataApi } from '@/lib/store'
import type { Lead, Tarea } from '@/lib/tipos'

// Miércoles 22-07-2026, 15:00 en Lima: día hábil y hora dentro de la ventana,
// para que la ventana legal no enmascare la aritmética que se está probando.
const AHORA = Date.parse('2026-07-22T15:00:00-05:00')
const iso = (s: string) => new Date(Date.parse(s)).toISOString()

let ES_MOVIL = false

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))
vi.mock('@/lib/ahora', () => ({ useAhora: () => AHORA }))
vi.mock('@/lib/auth-context', () => ({
  useAuth: () => ({
    yo: {
      id: 'v1',
      nombre_completo: 'ASESOR UNO',
      rol: 'vendedor',
      demo: false,
      puede_contratar: true,
    },
  }),
}))
// `usePuedeMarcar` lo consume AccionesContacto, que la tarjeta renderiza.
vi.mock('@/lib/media', () => ({
  useEsMovil: () => ES_MOVIL,
  usePuedeMarcar: () => ES_MOVIL,
  useMediaQuery: () => false,
  CONSULTA_MOVIL: '(max-width: 767px)',
  CONSULTA_PUEDE_MARCAR: '(hover: none)',
}))

const { toast } = await import('sonner')
const { Agenda } = await import('./agenda')

const LEAD = {
  id: 'l1',
  nombre_completo: 'ANA TORRES QUISPE',
  telefono: '+51999888777',
  etapa: 'contactado',
  origen: 'oficina',
  monto_estimado: 50_000,
  moneda: 'PEN',
  creado_en: iso('2026-07-01T10:00:00-05:00'),
  activo: true,
} as Lead

function tarea(over: Partial<Tarea> = {}): Tarea {
  return {
    id: 't1',
    lead_id: LEAD.id,
    tipo: 'llamada',
    titulo: 'Llamar a Ana',
    vence_en: iso('2026-07-17T10:00:00-05:00'), // vencida hace 5 días
    estado: 'pendiente',
    reprogramaciones: 0,
    activo: true,
    creado_en: iso('2026-07-15T10:00:00-05:00'),
    ...over,
  }
}

function montar(tareas: Tarea[]) {
  const reprogramarTarea = vi.fn<StoreDataApi['reprogramarTarea']>(() => ({
    ok: true,
  }))
  const abrirLead = vi.fn()
  const api = {
    tareas,
    equipo: [],
    ambito: { leads: [LEAD], vendedores: [], esGlobal: false },
    lead: (id: string) => (id === LEAD.id ? LEAD : undefined),
    tareasDe: () => tareas,
    actividadesDe: () => [],
    reprogramarTarea,
    confirmarTarea: vi.fn(() => ({ ok: true })),
    completarTarea: vi.fn(() => ({ ok: true })),
    crearTarea: vi.fn(() => ({ ok: true })),
    registrarActividad: vi.fn(() => ({ ok: true })),
    descartar: vi.fn(() => ({ ok: true })),
  } as unknown as StoreDataApi
  const paneles = {
    abrirLead,
    abrirNuevoLead: vi.fn(),
    cerrarPaneles: vi.fn(),
  } satisfies PanelesActions
  render(
    <StoreDataContext.Provider value={api}>
      <PanelActionsContext.Provider value={paneles}>
        <Agenda />
      </PanelActionsContext.Provider>
    </StoreDataContext.Provider>,
  )
  return { reprogramarTarea, abrirLead }
}

/** El botón de salto de la única tarjeta montada (por su etiqueta accesible). */
const salto = (aria: string) => screen.getByRole('button', { name: `Reprogramar ${aria} — Llamar a Ana` })

describe('Agenda — saltos rápidos de reprogramación', () => {
  it('una tarea VENCIDA salta desde AHORA (sale de la franja de vencidas)', async () => {
    const user = userEvent.setup()
    const { reprogramarTarea } = montar([tarea()]) // venció hace 5 días

    await user.click(salto('+1 día'))

    // Antes se sumaba sobre `vence_en`: +1d dejaba la tarea vencida hace 4 días
    // y el asesor volvía a pulsar (cada pulsación suma una "movida ×N").
    expect(reprogramarTarea).toHaveBeenCalledWith('t1', iso('2026-07-23T15:00:00-05:00'))
    expect(Date.parse(reprogramarTarea.mock.calls[0]![1])).toBeGreaterThan(AHORA)
    // Y el toast nombra el día real de destino, no el salto pedido.
    expect(toast.success).toHaveBeenCalledWith('Reprogramada — Mañana · 15:00')
  })

  it('+1sem sobre una vencida también parte de AHORA', async () => {
    const user = userEvent.setup()
    const { reprogramarTarea } = montar([tarea()])

    await user.click(salto('+1 semana'))

    expect(reprogramarTarea).toHaveBeenCalledWith('t1', iso('2026-07-29T15:00:00-05:00'))
  })

  it('una tarea FUTURA se pospone desde SU fecha (no se adelanta a mañana)', async () => {
    const user = userEvent.setup()
    // Viernes 24 a las 09:00 — dentro de la ventana legal.
    const { reprogramarTarea } = montar([tarea({ vence_en: iso('2026-07-24T09:00:00-05:00') })])
    await user.click(screen.getByRole('button', { name: /^Todo/ })) // [Hoy] no lista futuras

    await user.click(salto('+3 días'))

    expect(reprogramarTarea).toHaveBeenCalledWith('t1', iso('2026-07-27T09:00:00-05:00'))
  })

  it('respeta la ventana legal: un salto que cae domingo aterriza el lunes 10:00', async () => {
    const user = userEvent.setup()
    // Sábado 25 + 1 día = domingo → slotHabil lo corre al lunes a las 10:00.
    const { reprogramarTarea } = montar([tarea({ vence_en: iso('2026-07-25T09:00:00-05:00') })])
    await user.click(screen.getByRole('button', { name: /^Todo/ }))

    await user.click(salto('+1 día'))

    expect(reprogramarTarea).toHaveBeenCalledWith('t1', iso('2026-07-27T10:00:00-05:00'))
  })
})

describe('Agenda — teclado sobre la tarjeta', () => {
  it('Enter en un botón de la tarjeta ejecuta el botón, NO abre la ficha', async () => {
    const user = userEvent.setup()
    const { reprogramarTarea, abrirLead } = montar([tarea()])

    salto('+1 día').focus()
    await user.keyboard('{Enter}')

    expect(reprogramarTarea).toHaveBeenCalledTimes(1)
    expect(abrirLead).not.toHaveBeenCalled()
  })

  it('Espacio en el botón de cerrar tarea no se lo roba la tarjeta', async () => {
    const user = userEvent.setup()
    const { abrirLead } = montar([tarea()])

    screen.getByRole('button', { name: /^Cerrar tarea —/ }).focus()
    await user.keyboard(' ')

    expect(abrirLead).not.toHaveBeenCalled()
    // El diálogo de cierre se abrió: el botón hizo lo suyo.
    expect(await screen.findByRole('dialog')).toBeInTheDocument()
  })

  it('Enter sobre la TARJETA (no sobre un botón) sí abre la ficha', async () => {
    const user = userEvent.setup()
    const { abrirLead } = montar([tarea()])

    screen.getByRole('button', { name: /^Abrir ficha —/ }).focus()
    await user.keyboard('{Enter}')

    expect(abrirLead).toHaveBeenCalledWith(LEAD.id)
  })
})

describe('Agenda — gestiones de clientes', () => {
  it('incluye una tarea postventa sin lead y la identifica como Cliente', () => {
    montar([
      tarea({
        id: 'tc-1',
        lead_id: null,
        perfil_id: 'cliente-1',
        vendedor_id: 'v1',
        titulo: 'Reunión con Rosa',
        tipo: 'reunion',
      }),
    ])

    expect(screen.getByText('Cita con Rosa')).toBeInTheDocument()
    expect(screen.getByText('Cliente')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Abrir ficha — Cita con Rosa/ })).not.toBeInTheDocument()
  })

  it('permite cerrar la gestión del cliente desde la agenda', async () => {
    const user = userEvent.setup()
    montar([
      tarea({
        id: 'tc-2',
        lead_id: null,
        perfil_id: 'cliente-1',
        vendedor_id: 'v1',
        titulo: 'Llamar a Rosa',
      }),
    ])

    await user.click(screen.getByRole('button', { name: 'Cerrar tarea — Llamar a Rosa' }))

    expect(screen.getByRole('dialog')).toBeInTheDocument()
    expect(screen.getByText('Gestión de cliente · Mi cartera')).toBeInTheDocument()
  })
})

describe('Agenda — reprogramar en el celular', () => {
  // jsdom no aplica Tailwind: la regresión se vigila sobre las CLASES, que es
  // donde vivía el bug (`hidden sm:flex` borraba los saltos < 640 px).
  it('en viewport angosto los saltos están montados, sin `hidden` y con área de toque', () => {
    ES_MOVIL = true
    try {
      montar([tarea()])
      const boton = salto('+1 día')
      expect(boton.parentElement?.className ?? '').not.toContain('hidden')
      expect(boton.className).toContain('min-h-8')
    } finally {
      ES_MOVIL = false
    }
  })

  it('en escritorio conservan su tamaño discreto, con el ascenso táctil por puntero', () => {
    montar([tarea()])
    const boton = salto('+1 día')
    expect(boton.parentElement?.className ?? '').not.toContain('hidden')
    expect(boton.className).toContain('px-1.5')
    // El ancho NO es el único criterio: un celular en horizontal o una tablet
    // son anchos pero táctiles (sin hover) — de ahí el variant por puntero.
    expect(boton.className).toContain('pointer-coarse:min-h-8')
  })
})

describe('Agenda — bandeja compacta', () => {
  it('pagina las tareas de Hoy en lugar de alargar la pantalla completa', async () => {
    const user = userEvent.setup()
    const muchas = Array.from({ length: 13 }, (_, i) =>
      tarea({
        id: `t-${i + 1}`,
        titulo: `Seguimiento ${String(i + 1).padStart(2, '0')}`,
        // Mismo día, segundos distintos: el orden cronológico queda deliberado
        // para comprobar qué tarea cruza la frontera 12/13 de la página.
        vence_en: iso(`2026-07-22T15:00:${String(i + 1).padStart(2, '0')}-05:00`),
      }),
    )
    montar(muchas)

    expect(screen.getByText('1–12 de 13 tareas')).toBeInTheDocument()
    expect(screen.getByText('Seguimiento 01')).toBeInTheDocument()
    expect(screen.queryByText('Seguimiento 13')).not.toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Ver página siguiente de tareas' }))

    expect(screen.getByText('13–13 de 13 tareas')).toBeInTheDocument()
    expect(screen.getByText('Seguimiento 13')).toBeInTheDocument()
    expect(screen.queryByText('Seguimiento 01')).not.toBeInTheDocument()
  })
})

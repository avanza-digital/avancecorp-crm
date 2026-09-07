// Anular un cierre de AVANCE desde la ficha — quién puede, cuándo, y qué se ve
// después.
//
// Lo que este archivo vigila de verdad no es que el botón exista, sino que NO
// aparezca donde no debe: sobre un cierre en cooperativa (que la RPC rechaza),
// sobre un cierre ya anulado, y para cualquiera que no sea gerencia.
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
import type { PanelesActions, StoreDataApi } from '@/lib/store'
import type { Lead } from '@/lib/tipos'
import type { CierreEstado } from '@/lib/cierre-estado'
import { LeadDrawer } from './lead-drawer'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

// El transporte tiene su propia suite (contrato valibot + gate de RLS). Aquí se
// sustituye para que la ficha se monte sin QueryClient ni red, igual que hacen
// las otras suites del drawer.
const { mutarAnular, estadoActual } = vi.hoisted(() => ({
  mutarAnular: vi.fn(),
  estadoActual: { filas: [] as CierreEstado[] },
}))

vi.mock('@/data/crm-queries', () => ({
  useCierresEstado: () => ({ data: estadoActual.filas }),
  useAnularCierreAvance: () => ({ mutateAsync: mutarAnular }),
  useConvertirLeadExterno: () => ({ mutateAsync: vi.fn() }),
  useCuentasBancariasCliente: () => ({
    data: [], isPending: false, isError: false, isFetching: false, refetch: vi.fn(),
  }),
}))

vi.mock('@/data/sla-operacion-queries', () => ({
  useEstadosSlaV2: () => ({ data: { modo: 'legado', filas: [] }, error: null }),
}))

const LEAD: Lead = {
  id: 'lead-anular-1',
  nombre_completo: 'ANA CIERRE PRUEBA',
  telefono: '+51987654321',
  correo: 'ana@prueba.invalid',
  etapa: 'convertido',
  origen: 'landing',
  monto_estimado: 10_000,
  moneda: 'PEN',
  categoria_interes: null,
  vendedor_id: 'vendedor-1',
  vendedor_nombre: 'ANALISTA PRUEBA',
  asignado_supervisor_id: null,
  creado_en: '2026-07-17T12:00:00.000Z',
  activo: true,
  dni: null,
  distrito: null,
  nota: null,
  motivo_descarte: null,
}

function sesion(rol: string): AuthContextValue {
  return {
    fase: 'listo',
    yo: {
      id: 'usuario-1',
      nombre_completo: 'QUIEN MIRA',
      rol: rol as AuthContextValue['yo'] extends null ? never : 'gerencia',
      demo: false,
      puede_contratar: true,
    },
    error: null,
    entrar: async () => ({ ok: true }),
    entrarDemo: () => undefined,
    reintentar: () => undefined,
    salir: async () => undefined,
  } as AuthContextValue
}

function montar({
  rol = 'gerencia',
  lead = {},
  estado = [],
}: { rol?: string; lead?: Partial<Lead>; estado?: CierreEstado[] } = {}) {
  estadoActual.filas = estado
  const l: Lead = { ...LEAD, ...lead }
  const recargar = vi.fn(async () => true)
  const api = {
    lead: (id: string) => (id === l.id ? l : undefined),
    ambito: { leads: [l], vendedores: [], esGlobal: false },
    actividadesDe: () => [],
    tareasDe: () => [],
    crearTarea: vi.fn(() => ({ ok: true, id: 't-1' })),
    anularTarea: vi.fn(() => ({ ok: true })),
    editarLead: vi.fn(() => ({ ok: true })),
    reasignar: vi.fn(() => ({ ok: true })),
    cambiarEtapa: vi.fn(() => ({ ok: true })),
    reabrir: vi.fn(() => ({ ok: true })),
    registrarActividad: vi.fn(() => ({ ok: true })),
    anularCierreAvance: vi.fn(() => ({ ok: true })),
    cierresEstado: estado,
    recargar,
  } as unknown as StoreDataApi
  const actions: PanelesActions = {
    abrirLead: vi.fn(),
    abrirNuevoLead: vi.fn(),
    cerrarPaneles: vi.fn(),
  }

  render(
    <AuthContext.Provider value={sesion(rol)}>
      <StoreDataContext.Provider value={api}>
        <PanelStateContext.Provider
          value={{ leadAbiertoId: l.id, nuevoLeadAbierto: false, etapaInicial: 'nuevo', telefonoInicial: null }}
        >
          <PanelActionsContext.Provider value={actions}>
            <LeadDrawer />
          </PanelActionsContext.Provider>
        </PanelStateContext.Provider>
      </StoreDataContext.Provider>
    </AuthContext.Provider>,
  )
  return { recargar, lead: l }
}

const boton = () => screen.queryByRole('button', { name: /anular el cierre de/i })

beforeEach(() => {
  vi.clearAllMocks()
  mutarAnular.mockResolvedValue({
    leadId: LEAD.id, contratosAfectados: ['c-1'], afectaCuota: true,
  })
})

describe('quién ve el botón', () => {
  it('gerencia lo ve sobre un cierre de Avance sano', () => {
    montar()
    expect(boton()).not.toBeNull()
  })

  // Un caso por rol y no un bucle dentro de uno: con el bucle, el primer rol que
  // fallara escondería a los otros tres detrás del mismo mensaje.
  it.each(['vendedor', 'supervisor', 'coordinador', 'directorio'])(
    'un %s no lo ve, aunque vea la ficha',
    (rol) => {
      montar({ rol })
      // La ficha SÍ se pintó: el caso prueba que falta el botón, no que falte todo.
      expect(screen.getByText(/Convertido a cliente/i)).toBeTruthy()
      expect(boton()).toBeNull()
    },
  )

  it('no aparece en un lead que no está convertido', () => {
    montar({ lead: { etapa: 'propuesta_enviada' } })
    expect(boton()).toBeNull()
  })
})

// ⚠️ EL CASO DE PRODUCCIÓN. Al 2026-08-14 el ÚNICO lead convertido que existe en
// producción cerró en cooperativa. Sin esta condición, el primer y único botón
// que gerencia vería sería justo el que el servidor rechaza.
describe('un cierre en COOPERATIVA no se anula por aquí', () => {
  it('sin botón, aunque sea gerencia y esté convertido', () => {
    montar({
      estado: [{ lead_id: LEAD.id, canal: 'cooperativa', anulado_en: null, motivo: null }],
    })
    expect(boton()).toBeNull()
  })
})

describe('un cierre ya anulado', () => {
  const ANULADO: CierreEstado = {
    lead_id: LEAD.id,
    canal: 'avance',
    anulado_en: '2026-08-14T15:00:00.000Z',
    motivo: 'El cierre se registró con datos que no corresponden',
  }

  it('no se vuelve a anular (es de una sola dirección)', () => {
    montar({ estado: [ANULADO] })
    expect(boton()).toBeNull()
  })

  it('se ve marcado y CON la razón escrita', () => {
    montar({ estado: [ANULADO] })
    expect(screen.getByText('CIERRE ANULADO')).toBeTruthy()
    expect(
      screen.getByText(/El cierre se registró con datos que no corresponden/),
    ).toBeTruthy()
  })
})

describe('el diálogo de confirmación', () => {
  it('sin motivo no envía nada y lo dice', async () => {
    const usuario = userEvent.setup()
    montar()
    await usuario.click(boton()!)
    await usuario.click(screen.getByRole('button', { name: 'Anular cierre' }))
    expect(mutarAnular).not.toHaveBeenCalled()
    expect(screen.getByRole('alert').textContent).toMatch(/motivo/i)
  })

  it('con motivo anula, refresca el cumplimiento y dice qué se movió', async () => {
    const usuario = userEvent.setup()
    const { recargar } = montar()
    await usuario.click(boton()!)
    await usuario.type(
      screen.getByLabelText(/Motivo de la anulación/i),
      'Mala práctica del analista',
    )
    await usuario.click(screen.getByRole('button', { name: 'Anular cierre' }))

    expect(mutarAnular).toHaveBeenCalledWith({
      leadId: LEAD.id, motivo: 'Mala práctica del analista',
    })
    // El cumplimiento de metas NO vive en TanStack: sin este `recargar` la
    // pantalla restaría cifras frescas de un cumplimiento viejo.
    expect(recargar).toHaveBeenCalled()
    // ATR-4: anular sanciona la CONVERSION; el capital no se toca. El contrato
    // asociado se informa como trazabilidad, no como descuento.
    expect(vi.mocked(toast.success).mock.calls[0]?.[0]).toMatch(/baja la conversión de su analista \(1 contrato asociado\)/i)
    expect(vi.mocked(toast.success).mock.calls[0]?.[0]).toMatch(/El capital no se toca/i)
  })

  // Cero contratos asociados es un resultado CORRECTO (la conversión sale del
  // ledger) y el mensaje lo dice sin inventar un descuento que ya no existe.
  it('sin contratos asociados, dice que baja la conversión y nada más', async () => {
    const usuario = userEvent.setup()
    mutarAnular.mockResolvedValue({
      leadId: LEAD.id, contratosAfectados: [], afectaCuota: false,
    })
    montar()
    await usuario.click(boton()!)
    await usuario.type(screen.getByLabelText(/Motivo de la anulación/i), 'Sin contrato')
    await usuario.click(screen.getByRole('button', { name: 'Anular cierre' }))
    expect(vi.mocked(toast.success).mock.calls[0]?.[0])
      .toMatch(/baja la conversión de su analista\. El capital no se toca/i)
  })

  it('al volver, el foco regresa al botón que lo abrió', async () => {
    const usuario = userEvent.setup()
    montar()
    const disparador = boton()!
    await usuario.click(disparador)
    await usuario.click(screen.getByRole('button', { name: 'Volver' }))
    await vi.waitFor(() => expect(document.activeElement).toBe(disparador))
  })
})

// Visibilidad del botón "Convertir a cliente" en la Ficha (footer del drawer),
// no el contenido de DialogConvertir (ver lead-drawer-convertir.test.tsx).
// Cubre el criterio de ámbito por rol: analista (dueño), gerencia (verTodo) y
// supervisor (equipo, 15/09/2026 — mismo alcance que ya usa `reasignar`).
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import {
  PanelActionsContext,
  PanelStateContext,
  StoreDataContext,
} from '@/lib/store-context'
import type { PanelesActions, StoreDataApi } from '@/lib/store'
import type { Lead, Miembro } from '@/lib/tipos'
import { LeadDrawer } from './lead-drawer'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

const LEAD: Lead = {
  id: 'lead-convertir-boton-1',
  nombre_completo: 'ANA CAPITAL PRUEBA',
  telefono: '+51987654321',
  correo: 'ana@prueba.invalid',
  etapa: 'nuevo',
  origen: 'landing',
  monto_estimado: 5_000,
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

function sesion(over: Partial<AuthContextValue['yo']> = {}): AuthContextValue {
  return {
    fase: 'listo',
    yo: {
      id: 'yo-1',
      nombre_completo: 'QUIEN OPERA',
      rol: 'vendedor',
      demo: true,
      puede_contratar: true,
      ...over,
    },
    error: null,
    entrar: async () => ({ ok: true }),
    entrarDemo: () => undefined,
    reintentar: () => undefined,
    salir: async () => undefined,
  }
}

function montar({
  auth,
  vendedores = [],
  esGlobal = false,
  lead = LEAD,
}: {
  auth: AuthContextValue
  vendedores?: Miembro[]
  esGlobal?: boolean
  lead?: Lead
}) {
  const api = {
    lead: (id: string) => (id === lead.id ? lead : undefined),
    ambito: { leads: [lead], vendedores, esGlobal },
    actividadesDe: () => [],
    tareasDe: () => [],
    cierresEstado: [],
  } as unknown as StoreDataApi
  const actions: PanelesActions = {
    abrirLead: vi.fn(),
    abrirNuevoLead: vi.fn(),
    cerrarPaneles: vi.fn(),
  }
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  })

  render(
    <QueryClientProvider client={queryClient}>
      <AuthContext.Provider value={auth}>
        <StoreDataContext.Provider value={api}>
          <PanelStateContext.Provider
            value={{ leadAbiertoId: LEAD.id, nuevoLeadAbierto: false, etapaInicial: 'nuevo', telefonoInicial: null }}
          >
            <PanelActionsContext.Provider value={actions}>
              <LeadDrawer />
            </PanelActionsContext.Provider>
          </PanelStateContext.Provider>
        </StoreDataContext.Provider>
      </AuthContext.Provider>
    </QueryClientProvider>,
  )
}

beforeEach(() => vi.clearAllMocks())

describe('LeadDrawer — botón "Convertir a cliente" por ámbito de rol', () => {
  it('el supervisor convierte su lead propio aunque no tenga analistas a cargo', () => {
    montar({
      auth: sesion({ id: 'supervisor-1', rol: 'supervisor' }),
      lead: { ...LEAD, vendedor_id: 'supervisor-1', vendedor_nombre: 'SUPERVISOR PRUEBA' },
    })
    expect(screen.getByLabelText('Reasignar responsable comercial')).toHaveValue('supervisor-1')
    expect(screen.getByRole('option', { name: 'SUPERVISOR PRUEBA' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Convertir a cliente/ })).toBeInTheDocument()
  })

  it('la propiedad no sustituye una capacidad contractual revocada', () => {
    montar({
      auth: sesion({ id: 'supervisor-1', rol: 'supervisor', puede_contratar: false }),
      lead: { ...LEAD, vendedor_id: 'supervisor-1' },
    })
    expect(screen.queryByRole('button', { name: /Convertir a cliente/ })).not.toBeInTheDocument()
  })

  it('un lead en la bandeja del supervisor todavía necesita responsable para convertirse', () => {
    montar({
      auth: sesion({ id: 'supervisor-1', rol: 'supervisor' }),
      lead: { ...LEAD, vendedor_id: null, vendedor_nombre: null, asignado_supervisor_id: 'supervisor-1' },
    })
    expect(screen.queryByRole('button', { name: /Convertir a cliente/ })).not.toBeInTheDocument()
  })

  it('el analista dueño del lead ve el botón', () => {
    montar({ auth: sesion({ id: 'vendedor-1', rol: 'vendedor' }) })
    expect(screen.getByRole('button', { name: /Convertir a cliente/ })).toBeInTheDocument()
  })

  it('otro analista (no dueño) NO ve el botón', () => {
    montar({ auth: sesion({ id: 'vendedor-2', rol: 'vendedor' }) })
    expect(screen.queryByRole('button', { name: /Convertir a cliente/ })).not.toBeInTheDocument()
  })

  it('gerencia ve el botón sobre cualquier lead con analista (verTodo)', () => {
    montar({ auth: sesion({ id: 'gerencia-1', rol: 'gerencia' }), esGlobal: true })
    expect(screen.getByRole('button', { name: /Convertir a cliente/ })).toBeInTheDocument()
  })

  it('un supervisor ve el botón si el analista del lead es de su equipo (15/09/2026)', () => {
    montar({
      auth: sesion({ id: 'supervisor-1', rol: 'supervisor' }),
      vendedores: [{ perfil_id: 'vendedor-1', nombre_completo: 'ANALISTA PRUEBA', rol_crm: 'vendedor', supervisor_id: 'supervisor-1', activo: true }],
    })
    expect(screen.getByRole('button', { name: /Convertir a cliente/ })).toBeInTheDocument()
  })

  it('un supervisor NO ve el botón si el analista del lead no es de su equipo', () => {
    montar({
      auth: sesion({ id: 'supervisor-1', rol: 'supervisor' }),
      vendedores: [],
    })
    expect(screen.queryByRole('button', { name: /Convertir a cliente/ })).not.toBeInTheDocument()
  })
})

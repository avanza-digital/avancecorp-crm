// Bloque 2.16 (D-62) — lo que VE el usuario de la ficha al pulsar «Reabrir» en un lead descartado que conserva el contacto de un
// cliente: el aviso dice «Esta persona ya es cliente y está a cargo de X.», como el alta y la edición (D-36), y no el texto fijo.
// La cadena es real hasta la red: el banner (LeadDrawer) → `reabrir` → `reabrirLead` (crm-api) → Supabase SIMULADO con msw, que
// responde por `crm.reabrir_lead_fn` el P0481 con el veredicto. El store se sustituye por su contrato para «Reabrir» (`store.tsx`,
// `reabrir` → `persistirConDetalle(…, { notificarError: false })` → `aResultadoPersistenciaFallida`): `persistido` nunca rechaza y
// un CrmApiError con código propio llega con SU mensaje; el aviso lo da el banner. El componente no cambia en el 2.16. (El P0409
// «ya es cliente» por persona, con su tarjeta, lo prueba `lead-drawer-reabrir-cliente.test.tsx`.)
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'
import { toast } from 'sonner'

vi.mock('@/lib/supabase', async () => {
  const { createClient } = await import('@supabase/supabase-js')
  return { sb: createClient('http://supabase.test', 'anon-fake', { auth: { persistSession: false } }) }
})
vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

import { CrmApiError, reabrirLead } from '@/data/crm-api'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import { PanelActionsContext, PanelStateContext, StoreDataContext } from '@/lib/store-context'
import type { PanelesActions, ResultadoPersistencia, StoreDataApi } from '@/lib/store'
import type { Lead } from '@/lib/tipos'
import { LeadDrawer } from './lead-drawer'

const RPC = (fn: string) => `http://supabase.test/rest/v1/rpc/${fn}`
const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
beforeEach(() => {
  // registrarError escribe en consola: aquí no aporta nada.
  vi.spyOn(console, 'error').mockImplementation(() => {})
})

/** El P0481 «Contacto no disponible» con el veredicto en el DETAIL, como lo devuelve PostgREST. */
const p0481 = (veredicto: Record<string, unknown>) =>
  HttpResponse.json(
    { code: 'P0481', message: 'Contacto no disponible', details: JSON.stringify(veredicto), hint: null },
    { status: 400 },
  )

const LEAD: Lead = {
  id: 'lead-reabrir-veredicto-1',
  nombre_completo: 'LUIS REABRIR PRUEBA',
  telefono: '+51987654321',
  correo: null,
  etapa: 'descartado',
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
  motivo_descarte: 'no_responde',
}

// Sesión DEMO a propósito (como D-36): la ficha no consulta nada al abrirse; la escritura sí sale por la crm-api real.
const SESION: AuthContextValue = {
  fase: 'listo',
  yo: { id: 'vendedor-1', nombre_completo: 'ANALISTA PRUEBA', rol: 'vendedor', demo: true, puede_contratar: true },
  error: null,
  entrar: async () => ({ ok: true }),
  entrarDemo: () => undefined,
  reintentar: () => undefined,
  salir: async () => undefined,
}

function montar() {
  const reabrir = vi.fn<StoreDataApi['reabrir']>((id) => ({
    ok: true,
    persistido: reabrirLead(id).then(
      (): ResultadoPersistencia => ({ ok: true }),
      (causa: unknown): ResultadoPersistencia => causa instanceof CrmApiError && causa.code !== 'POSTGREST_ERROR'
        ? { ok: false, error: causa.message, codigo: causa.code }
        : { ok: false, error: 'No se pudo guardar el cambio' },
    ),
  }))
  const api = {
    lead: (id: string) => (id === LEAD.id ? LEAD : undefined),
    ambito: { leads: [LEAD], vendedores: [], esGlobal: false },
    actividadesDe: () => [],
    tareasDe: () => [],
    crearTarea: vi.fn(() => ({ ok: true })),
    anularTarea: vi.fn(() => ({ ok: true })),
    editarLead: vi.fn(() => ({ ok: true })),
    reasignar: vi.fn(() => ({ ok: true })),
    cambiarEtapa: vi.fn(() => ({ ok: true })),
    reabrir,
    registrarActividad: vi.fn(() => ({ ok: true })),
    cierresEstado: [],
  } as unknown as StoreDataApi
  const actions: PanelesActions = { abrirLead: vi.fn(), abrirNuevoLead: vi.fn(), cerrarPaneles: vi.fn() }
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  render(
    <QueryClientProvider client={queryClient}>
      <AuthContext.Provider value={SESION}>
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
  return { reabrir }
}

describe('LeadDrawer — «Reabrir» un descartado con el contacto de un cliente (P0481, bloque 2.16)', () => {
  it('el aviso dice «ya es cliente y está a cargo de X», como el alta y la edición', async () => {
    server.use(http.post(RPC('reabrir_lead_fn'), () =>
      p0481({ estado: 'ya_es_cliente', asesor: 'ANA ANALISTA', via: 'identidad' })))
    const { reabrir } = montar()

    await userEvent.setup().click(screen.getByRole('button', { name: /Reabrir/ }))

    await waitFor(() => expect(toast.error).toHaveBeenCalled())
    expect(toast.error).toHaveBeenCalledWith('Esta persona ya es cliente y está a cargo de ANA ANALISTA.')
    expect(reabrir).toHaveBeenCalledWith(LEAD.id)
    // Nada se anuncia como reabierto: el servidor no devolvió el lead.
    expect(toast.success).not.toHaveBeenCalled()
  })

  it('«No contactar» conserva el texto fijo de hoy', async () => {
    server.use(http.post(RPC('reabrir_lead_fn'), () => p0481({ estado: 'no_contactar' })))
    montar()

    await userEvent.setup().click(screen.getByRole('button', { name: /Reabrir/ }))

    await waitFor(() => expect(toast.error).toHaveBeenCalled())
    expect(toast.error).toHaveBeenCalledWith('Ese teléfono o DNI no está disponible para este lead.')
    expect(toast.success).not.toHaveBeenCalled()
  })
})

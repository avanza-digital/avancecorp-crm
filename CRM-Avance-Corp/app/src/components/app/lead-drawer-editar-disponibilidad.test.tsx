// D-36 (bloque 2.8, ronda 2) — lo que VE el usuario de la ficha: al guardar «Datos» con el teléfono de un cliente, el aviso
// del formulario dice «Esta persona ya es cliente y está a cargo de X.», como al registrar, y no el texto fijo. La cadena es
// real hasta la red: el formulario (LeadDrawer) → `editarLead` → `editarLeadFn` (crm-api) → Supabase SIMULADO con msw, que
// responde por `crm.editar_lead_documento_fn` (la ruta de la ficha: siempre manda el documento) el P0481 del disparador. El
// store se sustituye por su contrato para una edición con documento (`store.tsx`, `editarLead` → `persistirConDetalle` →
// `aResultadoPersistenciaFallida`): `persistido` nunca rechaza y un CrmApiError con código propio llega con SU mensaje.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
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

import { CrmApiError, editarLeadFn } from '@/data/crm-api'
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
  id: 'lead-editar-1',
  nombre_completo: 'ANA EDICIÓN PRUEBA',
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
  dni: '45678901',
  documento: { tipo: 'DNI', numero: '45678901' },
  distrito: null,
  nota: null,
  motivo_descarte: null,
}

// Sesión DEMO a propósito: la ficha no consulta nada al abrirse (el documento sale del lead). Con documento en el lead, el
// formulario manda `documento` igual que fuera del demo; la escritura sí sale por la crm-api real.
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
  const editarLead = vi.fn<StoreDataApi['editarLead']>((id, cambios) => ({
    ok: true,
    persistido: editarLeadFn(id, cambios).then(
      (): ResultadoPersistencia => ({ ok: true }),
      (causa: unknown): ResultadoPersistencia => causa instanceof CrmApiError
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
    editarLead,
    reasignar: vi.fn(() => ({ ok: true })),
    cambiarEtapa: vi.fn(() => ({ ok: true })),
    reabrir: vi.fn(() => ({ ok: true })),
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
  return { editarLead }
}

async function guardarTelefono(telefono: string) {
  const user = userEvent.setup()
  await user.click(screen.getByRole('button', { name: 'Editar' }))
  const campo = screen.getByLabelText('Teléfono')
  await user.clear(campo)
  await user.type(campo, telefono)
  await user.click(screen.getByRole('button', { name: 'Guardar' }))
}

describe('LeadDrawer — guardar «Datos» con el contacto de otro (P0481, D-36)', () => {
  it('teléfono de un cliente: el aviso del formulario dice «ya es cliente y está a cargo de X», como al registrar', async () => {
    server.use(http.post(RPC('editar_lead_documento_fn'), () =>
      p0481({ estado: 'ya_es_cliente', asesor: 'ANA ANALISTA', via: 'identidad' })))
    const { editarLead } = montar()

    await guardarTelefono('911222333')

    expect(await screen.findByRole('alert')).toHaveTextContent('Esta persona ya es cliente y está a cargo de ANA ANALISTA.')
    expect(editarLead).toHaveBeenCalledWith(LEAD.id, expect.objectContaining({
      telefono: '911222333',
      documento: { tipo: 'DNI', numero: '45678901' },
    }))
    // Sigue en edición para corregir el dato: nada se anuncia como guardado.
    expect(screen.getByRole('button', { name: 'Guardar' })).toBeInTheDocument()
    expect(toast.success).not.toHaveBeenCalled()
  })

  it('«No contactar» conserva el texto fijo de hoy (el del alta habla de «registrar»)', async () => {
    server.use(http.post(RPC('editar_lead_documento_fn'), () => p0481({ estado: 'no_contactar' })))
    montar()

    await guardarTelefono('911222333')

    const aviso = await screen.findByRole('alert')
    expect(aviso).toHaveTextContent('Ese teléfono o DNI no está disponible para este lead.')
    expect(aviso).not.toHaveTextContent(/registrar/)
    expect(toast.success).not.toHaveBeenCalled()
  })
})

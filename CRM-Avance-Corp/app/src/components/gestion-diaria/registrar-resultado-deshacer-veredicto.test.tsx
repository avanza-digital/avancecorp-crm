// Bloque 2.16 (D-62, D-69) — «Deshacer» un resultado de llamada que descartó el lead revierte el descarte (`crm.reabrir_lead_fn`
// dentro de `crm.deshacer_resultado_llamada`): si el lead conserva el contacto de un cliente, el servidor rechaza el deshacer
// ENTERO con el P0481 y el veredicto del alta. Lo que VE el analista en el aviso: «Esta persona ya es cliente y está a cargo de
// X.», como el alta, y no «Contacto no disponible». La cadena es real hasta la red: el toast «Deshacer» del panel → el store
// (sustituido por su contrato para el deshacer: `store.tsx`, `deshacerResultadoLlamada` → `persistir` → `persistirConDetalle`,
// que avisa con `toast.error(`${mensaje} — se actualizó la vista…`)` y resuelve `false`) → `deshacerResultadoLlamada`
// (gestion-diaria-api) → Supabase SIMULADO con msw. El componente no cambia en el 2.16.
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
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
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() } }))
// Lunes 21/09/2026 10:00 Lima: dentro de la ventana legal, día hábil (como `registrar-resultado.test.tsx`).
const AHORA = Date.parse('2026-09-21T15:00:00.000Z')
vi.mock('@/lib/ahora', () => ({ useAhora: () => AHORA }))

import { CrmApiError } from '@/data/crm-api'
import { deshacerResultadoLlamada as deshacerResultadoLlamadaFn } from '@/data/gestion-diaria-api'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import { StoreDataContext } from '@/lib/store-context'
import type { StoreDataApi } from '@/lib/store'
import type { Lead } from '@/lib/tipos'
import { RegistrarResultado } from './registrar-resultado'

const RPC_DESHACER = 'http://supabase.test/rest/v1/rpc/deshacer_resultado_llamada'
const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

const p0481 = (veredicto: Record<string, unknown>) =>
  HttpResponse.json({ code: 'P0481', message: 'Contacto no disponible', details: JSON.stringify(veredicto), hint: null }, { status: 400 })

const SESION: AuthContextValue = {
  fase: 'listo',
  yo: { id: 'v1', nombre_completo: 'QUIEN LLAMA', rol: 'vendedor', demo: true, puede_contratar: true },
  error: null, entrar: async () => ({ ok: true }), entrarDemo: () => undefined, reintentar: () => undefined, salir: async () => undefined,
}

const LEAD = {
  id: 'l1', nombre_completo: 'ANA TORRES QUISPE', telefono: '+51999888777', etapa: 'nuevo', origen: 'oficina',
  monto_estimado: 50_000, moneda: 'PEN', creado_en: '2026-09-10T15:00:00.000Z', activo: true, vendedor_id: 'v1',
} as Lead

/** El contrato del store para el deshacer en real: el rechazo se avisa con el mensaje del CrmApiError (salvo POSTGREST_ERROR). */
const MENSAJE_RESTAURADO = ' — se actualizó la vista con el estado del servidor'
function montar() {
  vi.spyOn(Date, 'now').mockReturnValue(AHORA)
  const registrarLlamada = vi.fn<StoreDataApi['registrarLlamada']>(() => ({
    ok: true, persistido: Promise.resolve(true), descartado: true,
    confirmacion: Promise.resolve({ actividad_id: 'act-77', siguiente_id: null, descartado: true }),
  }))
  const deshacerResultadoLlamada = vi.fn<StoreDataApi['deshacerResultadoLlamada']>((id) => ({
    ok: true,
    persistido: deshacerResultadoLlamadaFn(id).then(() => true, (causa: unknown) => {
      const mensaje = causa instanceof CrmApiError && causa.code !== 'POSTGREST_ERROR' ? causa.message : 'No se pudo guardar el cambio'
      toast.error(`${mensaje}${MENSAJE_RESTAURADO}`)
      return false
    }),
  }))
  const api = {
    registrarLlamada, deshacerResultadoLlamada,
    tareasDe: () => [], actividadesDe: () => [],
    lead: (id: string) => (id === LEAD.id ? LEAD : undefined),
  } as unknown as StoreDataApi
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  render(
    <QueryClientProvider client={queryClient}>
      <AuthContext.Provider value={SESION}>
        <StoreDataContext.Provider value={api}>
          <RegistrarResultado lead={LEAD} tarea={null} onClose={vi.fn()} />
        </StoreDataContext.Provider>
      </AuthContext.Provider>
    </QueryClientProvider>,
  )
  return { deshacerResultadoLlamada }
}

/** Registra «volver a llamar» y pulsa «Deshacer» en el toast de éxito. */
async function registrarYDeshacer() {
  const user = userEvent.setup()
  await user.click(screen.getByRole('radio', { name: /volver a llamar/ }))
  await user.click(screen.getByRole('button', { name: 'Guardar' }))
  await waitFor(() => expect(toast.success).toHaveBeenCalled())
  const opciones = vi.mocked(toast.success).mock.calls[0]?.[1] as unknown as { action: { onClick: () => void } }
  opciones.action.onClick()
}

describe('RegistrarResultado — «Deshacer» cuando el lead conserva el contacto de un cliente (P0481, bloque 2.16)', () => {
  it('el aviso dice «ya es cliente y está a cargo de X», como el alta', async () => {
    server.use(http.post(RPC_DESHACER, () => p0481({ estado: 'ya_es_cliente', asesor: 'Ana' })))
    const { deshacerResultadoLlamada } = montar()

    await registrarYDeshacer()

    await waitFor(() => expect(toast.error).toHaveBeenCalled())
    expect(deshacerResultadoLlamada).toHaveBeenCalledWith('act-77')
    expect(toast.error).toHaveBeenCalledWith(`Esta persona ya es cliente y está a cargo de Ana.${MENSAJE_RESTAURADO}`)
    // Nada se deshizo: no hay segundo aviso de éxito.
    expect(toast.success).toHaveBeenCalledTimes(1)
  })

  it('«No contactar» conserva el mensaje de hoy', async () => {
    server.use(http.post(RPC_DESHACER, () => p0481({ estado: 'no_contactar' })))
    montar()

    await registrarYDeshacer()

    await waitFor(() => expect(toast.error).toHaveBeenCalled())
    expect(toast.error).toHaveBeenCalledWith(`Contacto no disponible${MENSAJE_RESTAURADO}`)
  })
})

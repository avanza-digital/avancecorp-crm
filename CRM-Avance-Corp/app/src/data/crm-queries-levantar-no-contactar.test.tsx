// «Quitar No contactar» se levanta para la PERSONA y todos sus leads (D5): tras hacerlo se refresca todo lo que cuelga
// de `leads()` (la base, la cartera, el pipeline) y el historial de CUALQUIER lead en pantalla, no solo el del abierto
// (Codex F4 r1, hallazgo 6).
import { describe, expect, it, vi } from 'vitest'
import { act, renderHook } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'

vi.mock('./crm-api', async (original) => ({
  ...(await original<typeof import('./crm-api')>()),
  levantarNoContactar: vi.fn(async () => ({ leadsAfectados: 3 })),
}))

const { crmQueryKeys, useLevantarNoContactarBase } = await import('./crm-queries')

describe('useLevantarNoContactarBase', () => {
  it('invalida las listas de leads (base incluida) y el historial de todos los leads, no solo el del lead abierto', async () => {
    const cliente = new QueryClient()
    const invalidar = vi.spyOn(cliente, 'invalidateQueries')
    const envoltorio = ({ children }: { children: ReactNode }) => <QueryClientProvider client={cliente}>{children}</QueryClientProvider>
    const { result } = renderHook(() => useLevantarNoContactarBase(), { wrapper: envoltorio })
    await act(async () => { await result.current.mutateAsync({ leadId: 'lead-1', motivo: 'Volvió a pedir información' }) })
    const claves = invalidar.mock.calls.map(([filtro]) => filtro?.queryKey)
    expect(claves).toContainEqual(crmQueryKeys.leads())
    expect(claves).toContainEqual(crmQueryKeys.historialLeads())
    // El prefijo del historial abarca el de cualquier lead (el abierto y los otros de la persona).
    expect(crmQueryKeys.historialLead('otro-lead-de-la-persona').slice(0, crmQueryKeys.historialLeads().length)).toEqual([...crmQueryKeys.historialLeads()])
    expect(crmQueryKeys.baseGestionEquipo(true, '2026-10-04').slice(0, crmQueryKeys.leads().length)).toEqual([...crmQueryKeys.leads()])
  })
})

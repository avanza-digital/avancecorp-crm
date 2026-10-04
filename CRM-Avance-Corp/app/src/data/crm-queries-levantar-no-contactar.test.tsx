// «Quitar No contactar» se levanta para la PERSONA y todos sus leads (D5): tras hacerlo se refrescan las listas de
// leads (la base, la cartera y el pipeline llevan la marca de cada lead) y el historial del lead sobre el que se
// levantó, que es el ÚNICO donde el servidor escribe la actividad (migración 20261002061500, líneas 235-236; Codex F4 r2).
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
  it('invalida las listas de leads (base incluida) y el historial SOLO del lead sobre el que se levantó', async () => {
    const cliente = new QueryClient()
    const invalidar = vi.spyOn(cliente, 'invalidateQueries')
    const envoltorio = ({ children }: { children: ReactNode }) => <QueryClientProvider client={cliente}>{children}</QueryClientProvider>
    const { result } = renderHook(() => useLevantarNoContactarBase(), { wrapper: envoltorio })
    await act(async () => { await result.current.mutateAsync({ leadId: 'lead-1', motivo: 'Volvió a pedir información' }) })
    const claves = invalidar.mock.calls.map(([filtro]) => filtro?.queryKey)
    expect(claves).toHaveLength(2)
    expect(claves).toContainEqual(crmQueryKeys.leads())
    expect(claves).toContainEqual(crmQueryKeys.historialLead('lead-1'))
    expect(claves).not.toContainEqual(crmQueryKeys.historialLeads())
    // La base del equipo cuelga de `leads()`: la marca de los otros leads de la persona se refresca con ella.
    expect(crmQueryKeys.baseGestionEquipo(true, '2026-10-04').slice(0, crmQueryKeys.leads().length)).toEqual([...crmQueryKeys.leads()])
  })
})

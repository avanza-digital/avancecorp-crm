import { describe, expect, it, vi } from 'vitest'
import type { ReactNode } from 'react'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import type { ConsultaCitasRpc } from '@/data/citas-gerencia'
import { useMesesCitasGerencia } from './use-datos-citas-gerencia'

const servidor = vi.hoisted(() => ({ fallar: new Set<string>(), llamadas: [] as string[] }))
const consulta = (mes: string, cita: string): ConsultaCitasRpc => ({
  version: 1, periodo: { desde: `${mes}-01`, hasta: `${mes}-28` }, generado_en: `${mes}-28T15:00:00Z`, citas_clientes: 0,
  disponibilidad_depositos: 'sin_registro', depositos: [],
  citas: [{ id: cita, lead_id: `lead-${cita}`, nombre: 'PERSONA', telefono: '900000000', analista_id: 'ana', analista_nombre: 'ANA',
    supervisor_id: 'sup', supervisor_nombre: 'SUP', vence_en: `${mes}-10T15:00:00Z`, estado: 'pendiente', cancelada_por: null,
    modalidad: 'virtual', origen: 'referido', moneda: 'PEN', monto_estimado: 1000, resultado: 'sin_clasificar', nota: '',
    reagendada_de: null, creado_en: `${mes}-05T15:00:00Z`, asistencia_registrada_en: null, cierre_posterior: false }],
})
vi.mock('@/data/citas-gerencia', async importOriginal => ({ ...await importOriginal<typeof import('@/data/citas-gerencia')>(),
  opcionesCitasGerencia: (mes: string, actorId: string | null, habilitada: boolean) => ({
    queryKey: ['citas-prueba', actorId, mes], enabled: habilitada, retry: false,
    queryFn: async () => {
      servidor.llamadas.push(mes)
      if (servidor.fallar.has(mes)) throw new Error(`Sin ${mes}`)
      return consulta(mes, `cita-${mes}`)
    },
  }) }))

function montar(meses: string[], demo = false) {
  const cliente = new QueryClient()
  const sesion = { fase: 'listo', error: null, yo: { id: 'gerente', nombre_completo: 'GERENTE', rol: 'gerencia', demo, puede_contratar: false } } as unknown as AuthContextValue
  const envoltorio = ({ children }: { children: ReactNode }) => <QueryClientProvider client={cliente}><AuthContext.Provider value={sesion}>{children}</AuthContext.Provider></QueryClientProvider>
  return renderHook(({ m }) => useMesesCitasGerencia(m), { wrapper: envoltorio, initialProps: { m: meses } })
}

describe('useMesesCitasGerencia: meses del rango de Proyección', () => {
  it('espera a todos los meses y entrega las citas fusionadas', async () => {
    servidor.fallar.clear()
    const { result } = montar(['2026-09', '2026-10'])
    expect(result.current).toMatchObject({ meses: ['2026-09', '2026-10'], cargando: true, citas: [], error: null })
    await waitFor(() => expect(result.current.cargando).toBe(false))
    expect(result.current.citas.map(c => c.id)).toEqual(['cita-2026-09', 'cita-2026-10'])
    expect(result.current.corte).toBe('2026-10-28T15:00:00Z')
  })

  it('si un mes falla no hay cifras parciales; Reintentar vuelve a pedir solo ese mes', async () => {
    servidor.fallar = new Set(['2026-10'])
    servidor.llamadas = []
    const { result } = montar(['2026-09', '2026-10'])
    await waitFor(() => expect(result.current.error).toBe('Sin 2026-10'))
    expect(result.current).toMatchObject({ cargando: false, citas: [] })
    servidor.fallar.clear()
    result.current.onReintentar()
    await waitFor(() => expect(result.current.citas).toHaveLength(2))
    expect(servidor.llamadas.filter(m => m === '2026-10')).toHaveLength(2)
    expect(servidor.llamadas.filter(m => m === '2026-09')).toHaveLength(1)
  })

  it('en demostración no consulta al servidor', () => {
    servidor.llamadas = []
    const { result } = montar(['2026-10'], true)
    expect(result.current.cargando).toBe(true)
    expect(servidor.llamadas).toEqual([])
  })
})

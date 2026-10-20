import { describe, expect, it, vi } from 'vitest'
import type { ReactNode } from 'react'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import type { ConsultaCitasRpc } from '@/data/citas-gerencia'
import type { CitasClientesProyeccionRpc } from '@/data/citas-clientes-proyeccion'
import type { RangoProyeccion } from '@/components/citas/proyeccion-rango'
import { useDatosProyeccionCitas, useMesesCitasGerencia } from './use-datos-citas-gerencia'

const servidor = vi.hoisted(() => ({
  fallar: new Set<string>(), llamadas: [] as string[],
  // Reuniones con clientes: una llamada por rango; `pendiente` retiene la respuesta hasta resolverla.
  clientes: [] as string[], fallarClientes: false, pendiente: null as Promise<void> | null,
}))
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

const reuniones = (rango: RangoProyeccion): CitasClientesProyeccionRpc => ({
  version: 1, periodo: rango, criterio: 'creado_en', generado_en: '2026-10-19T17:00:00Z',
  citas: [{ id: 'reunion-1', creado_en: `${rango.desde}T15:00:00Z`, vence_en: '2026-10-10T15:00:00Z', estado: 'completada', cancelada_por: null,
    asistencia_registrada_en: '2026-10-10T16:00:00Z', analista_id: 'ana', analista_nombre: 'ANA', supervisor_id: 'sup', supervisor_nombre: 'SUP',
    sujeto_tipo: 'inversionista', sujeto_id: 'p1', sujeto_nombre: 'CLIENTE', inversionista_id: 'p1', perfil_id: null, identidad_visible: true,
    identidad_persona: 'persona:p1' }],
})
vi.mock('@/data/citas-clientes-proyeccion', async importOriginal => ({ ...await importOriginal<typeof import('@/data/citas-clientes-proyeccion')>(),
  opcionesCitasClientesProyeccion: (rango: RangoProyeccion | null, actorId: string | null, habilitada: boolean) => ({
    queryKey: ['clientes-prueba', actorId, rango?.desde, rango?.hasta], enabled: habilitada && rango !== null, retry: false,
    queryFn: async () => {
      servidor.clientes.push(`${rango!.desde}|${rango!.hasta}`)
      await servidor.pendiente
      if (servidor.fallarClientes) throw new Error('El rango es demasiado grande. Acorta las fechas.')
      return reuniones(rango!)
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

describe('useDatosProyeccionCitas: meses y reuniones con clientes del rango', () => {
  const OCTUBRE = { desde: '2026-10-01', hasta: '2026-10-19' }
  function montarRango(meses: string[], rango: RangoProyeccion | null, demo = false) {
    const cliente = new QueryClient()
    const sesion = { fase: 'listo', error: null, yo: { id: 'gerente', nombre_completo: 'GERENTE', rol: 'gerencia', demo, puede_contratar: false } } as unknown as AuthContextValue
    const envoltorio = ({ children }: { children: ReactNode }) => <QueryClientProvider client={cliente}><AuthContext.Provider value={sesion}>{children}</AuthContext.Provider></QueryClientProvider>
    return renderHook(({ m, r }) => useDatosProyeccionCitas(m, r), { wrapper: envoltorio, initialProps: { m: meses, r: rango } })
  }
  const reiniciar = () => { servidor.fallar.clear(); servidor.llamadas = []; servidor.clientes = []; servidor.fallarClientes = false; servidor.pendiente = null }

  it('una sola llamada por rango; mientras falten sus reuniones no hay cifras, aunque los meses ya llegaran', async () => {
    reiniciar()
    let soltar = () => {}
    servidor.pendiente = new Promise<void>(resolve => { soltar = resolve })
    const { result, rerender } = montarRango(['2026-10'], OCTUBRE)
    await waitFor(() => expect(servidor.llamadas).toEqual(['2026-10']))
    await new Promise(resolve => setTimeout(resolve, 20))
    expect(result.current).toMatchObject({ cargando: true, citas: [], reunionesClientes: [], error: null, rango: OCTUBRE })
    soltar()
    await waitFor(() => expect(result.current.cargando).toBe(false))
    expect(result.current.citas.map(c => c.id)).toEqual(['cita-2026-10'])
    expect(result.current.reunionesClientes).toEqual([expect.objectContaining({ id: 'reunion-1', leadId: null, monto: null, moneda: null,
      persona: 'persona:p1', estado: 'realizada', analista: 'ana', supervisorId: 'sup' })])
    expect(servidor.clientes).toEqual(['2026-10-01|2026-10-19'])
    // Otro rango del mismo mes: nueva llamada de reuniones, sin volver a pedir el mes; mientras tanto, sin cifras.
    rerender({ m: ['2026-10'], r: { desde: '2026-10-15', hasta: '2026-10-19' } })
    expect(result.current).toMatchObject({ cargando: true, citas: [], reunionesClientes: [] })
    await waitFor(() => expect(result.current.cargando).toBe(false))
    expect(servidor.clientes).toEqual(['2026-10-01|2026-10-19', '2026-10-15|2026-10-19'])
    expect(servidor.llamadas).toEqual(['2026-10'])
  })

  it('si fallan las reuniones no hay cifras parciales; Reintentar vuelve a pedir solo las reuniones', async () => {
    reiniciar()
    servidor.fallarClientes = true
    const { result } = montarRango(['2026-10'], OCTUBRE)
    await waitFor(() => expect(result.current.error).toBe('El rango es demasiado grande. Acorta las fechas.'))
    expect(result.current).toMatchObject({ cargando: false, citas: [], reunionesClientes: [] })
    servidor.fallarClientes = false
    result.current.onReintentar()
    await waitFor(() => expect(result.current.reunionesClientes).toHaveLength(1))
    expect(result.current).toMatchObject({ cargando: false, error: null })
    expect(servidor.clientes).toHaveLength(2)
    expect(servidor.llamadas).toEqual(['2026-10'])
  })

  it('«Actualizar» vuelve a leer los meses y las reuniones aunque ya hubieran llegado; «Reintentar» solo lo que falló', async () => {
    // Codex (19/10): Actualizar solo repetía lo fallido y no traía reuniones nuevas de otros analistas.
    reiniciar()
    const { result } = montarRango(['2026-10'], OCTUBRE)
    await waitFor(() => expect(result.current.cargando).toBe(false))
    result.current.onReintentar()
    await new Promise(resolve => setTimeout(resolve, 20))
    expect([servidor.llamadas, servidor.clientes]).toEqual([['2026-10'], ['2026-10-01|2026-10-19']])
    result.current.onActualizar!()
    await waitFor(() => expect([servidor.llamadas.length, servidor.clientes.length]).toEqual([2, 2]))
  })

  it('sin rango o en demostración no pide las reuniones', async () => {
    reiniciar()
    const sinRango = montarRango(['2026-10'], null)
    await waitFor(() => expect(servidor.llamadas).toEqual(['2026-10']))
    expect(sinRango.result.current).toMatchObject({ cargando: true, citas: [], rango: null })
    expect(servidor.clientes).toEqual([])
    reiniciar()
    const demo = montarRango(['2026-10'], OCTUBRE, true)
    expect(demo.result.current.cargando).toBe(true)
    await new Promise(resolve => setTimeout(resolve, 20))
    expect([servidor.llamadas, servidor.clientes]).toEqual([[], []])
  })
})

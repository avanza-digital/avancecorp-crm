// Tests de integración de la pantalla "Hoy · gerencia" — la tarjeta
// "Meta del mes — Empresa", cuyo objetivo sale de crm.objetivos (una fila por
// mes calendario). Regresiones que cubren:
//   1. "Ventas cerradas" contaba los `etapa === 'convertido'` de TODA la vida
//      contra la cuota MENSUAL: el avance no bajaba nunca al empezar un mes
//      nuevo y el marcador mentía hacia arriba de forma permanente;
//   2. una meta que gerencia todavía no fijó (objetivo 0) se pintaba como
//      "0 %" en rojo crítico — pctMeta(x, 0) es 0 y colorMeta(0) es crítico.
//
// El reloj se fija con timers falsos: el mes vigente se deriva del instante.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import { objetivosCero, type ObjetivosPorRol } from '@/lib/objetivos'
import { SERIES_VACIAS } from '@/lib/series-comerciales'
import type { Lead, Yo } from '@/lib/tipos'

// Miércoles 2026-07-15, 10:00 en Lima (UTC-5).
const MIERCOLES_10AM = new Date('2026-07-15T15:00:00Z')

let YO: Yo | null = null
let LEADS: Lead[] = []
let OBJETIVOS: ObjetivosPorRol = objetivosCero()

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    ambito: { leads: LEADS, vendedores: [], esGlobal: true },
    equipo: [],
    objetivos: OBJETIVOS,
    fijarObjetivos: () => ({ ok: true }),
    series: SERIES_VACIAS,
  }),
}))
// Paneles que viven de RPCs (TanStack) o de Recharts: fuera, no son lo que se
// prueba aquí y montarlos exigiría un QueryClient y el bundle de gráficas.
vi.mock('./distribucion-leads-gerencia', () => ({ DistribucionLeadsGerencia: () => null }))
vi.mock('./agenda-equipo', () => ({ AgendaEquipoPanel: () => null }))
vi.mock('./graficas-gerencia', () => ({ GraficasGerencia: () => null }))
vi.mock('./metas-editor', () => ({ MetasEditor: () => null }))
vi.mock('@/data/crm-queries', () => ({
  useMetricasDistribucionLeads: () => ({
    data: undefined,
    error: null,
    isPending: false,
    isFetching: false,
    refetch: () => {},
  }),
  useMetricasAgenda: () => ({
    data: undefined,
    error: null,
    isPending: false,
    isFetching: false,
    refetch: () => {},
  }),
  useActualizarCapacidadLeadsObjetivo: () => ({ mutateAsync: async () => {} }),
}))
// crm-api arrastra el cliente de Supabase al importarse.
vi.mock('@/data/crm-api', () => ({ mensajeDeError: (_e: unknown, f: string) => f }))

const { HoyGerencia } = await import('./gerencia')

function lead(over: Partial<Lead> = {}): Lead {
  return {
    id: 'l-1',
    nombre_completo: 'ANA TORRES',
    telefono: '+51987654321',
    etapa: 'contactado',
    origen: 'referido',
    monto_estimado: 10_000,
    moneda: 'PEN',
    vendedor_id: 'v-1',
    creado_en: '2026-07-01T15:00:00Z',
    activo: true,
    ...over,
  }
}

function montar(
  over: { leads?: Lead[]; objetivos?: Partial<ObjetivosPorRol['gerencia']> } = {},
): void {
  vi.setSystemTime(MIERCOLES_10AM)
  YO = {
    id: 'g-1',
    nombre_completo: 'GERENCIA UNO',
    rol: 'gerencia',
    demo: false,
    puede_contratar: true,
  }
  LEADS = over.leads ?? [lead()]
  OBJETIVOS = objetivosCero()
  OBJETIVOS.gerencia = {
    capitalObjetivo: 100_000,
    ventasObjetivo: 4,
    conversionObjetivo: 40,
    ...over.objetivos,
  }
  render(<HoyGerencia />)
}

/** La tarjeta del marcador mensual (hay muchos números sueltos en la pantalla). */
function tarjetaMeta(): HTMLElement {
  const titulo = screen.getByRole('heading', { name: 'Meta del mes — Empresa' })
  const tarjeta = titulo.closest('[data-slot="card"]')
  if (!(tarjeta instanceof HTMLElement)) throw new Error('no se encontró la tarjeta de meta')
  return tarjeta
}

beforeEach(() => {
  vi.useFakeTimers()
})

afterEach(() => {
  vi.useRealTimers()
})

describe('Hoy · gerencia — meta del mes', () => {
  it('"Ventas cerradas" cuenta el MES vigente, no la vida entera', () => {
    montar({
      leads: [
        lead({ id: 'l-viejo', etapa: 'convertido', actualizado_en: '2026-05-20T15:00:00Z' }),
        lead({ id: 'l-viejo2', etapa: 'convertido', actualizado_en: '2026-06-20T15:00:00Z' }),
        lead({ id: 'l-mes', etapa: 'convertido', actualizado_en: '2026-07-09T15:00:00Z' }),
      ],
      objetivos: { ventasObjetivo: 4 },
    })

    const meta = within(tarjetaMeta())
    expect(meta.getByText('Ventas cerradas este mes')).toBeInTheDocument()
    expect(meta.getByText('1')).toBeInTheDocument()
    expect(meta.getByText('de 4 cierres')).toBeInTheDocument()
    // 1 de 4 = 25 %; antes marcaba 75 % con dos cierres de meses ya cerrados.
    expect(meta.getByText('25%')).toBeInTheDocument()
    expect(meta.queryByText('75%')).not.toBeInTheDocument()
    // El acumulado se dice en voz alta para que las dos cifras no se contradigan.
    expect(meta.getByText('3 cierres acumulados en toda la operación.')).toBeInTheDocument()
  })

  it('una meta que gerencia todavía no fijó NO se pinta como incumplida', () => {
    montar({ objetivos: { capitalObjetivo: 0, ventasObjetivo: 0 } })

    const meta = within(tarjetaMeta())
    expect(meta.getAllByText('Meta del mes todavía sin fijar')).toHaveLength(2)
    // Antes: dos barras en ROJO CRÍTICO con "0%" sobre cuotas que nadie fijó.
    expect(meta.queryByText('0%')).not.toBeInTheDocument()
    expect(meta.getAllByText('meta por definir')).toHaveLength(2)
  })

  it('el KPI de capital ganado se rotula ACUMULADO (no es la cifra del mes)', () => {
    montar({
      leads: [lead({ id: 'l-viejo', etapa: 'convertido', actualizado_en: '2026-05-20T15:00:00Z' })],
    })

    expect(screen.getByText('Acumulado de ventas cerradas en soles')).toBeInTheDocument()
  })
})

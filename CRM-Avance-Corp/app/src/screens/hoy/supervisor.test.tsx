// Tests de integración de la pantalla "Hoy · supervisor" — la tarjeta "Meta del
// equipo", que se rotula "este mes" y sale de crm.objetivos (una fila por mes
// calendario). Regresiones que cubren:
//   1. "Ventas cerradas" contaba el HISTÓRICO de vida contra la cuota MENSUAL,
//      así que desde el segundo mes el marcador mentía hacia arriba para
//      siempre — y con esta cifra se juzga al equipo;
//   2. "Conversión" salía de conversionGlobal(), que tampoco mira el periodo;
//   3. un mes sin nada resuelto todavía se pintaba como "0 %" en rojo crítico
//      (eso es SIN DATO, no incumplimiento — el caso natural el día 1);
//   4. una meta que gerencia dejó en blanco (objetivo 0) también se pintaba
//      como incumplida, y el bloque "por definir" ni siquiera miraba la
//      conversión: bastaba con fijar capital y ventas para colarla al semáforo.
//
// El reloj se fija con timers falsos: el mes vigente se deriva del instante y
// sin fijarlo estos tests pasarían o fallarían según el día en que se ejecuten.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { objetivosCero, type ObjetivosPorRol } from '@/lib/objetivos'
import type { Actividad, Lead, Miembro, Yo } from '@/lib/tipos'

// Miércoles 2026-07-15, 10:00 en Lima (UTC-5).
const MIERCOLES_10AM = new Date('2026-07-15T15:00:00Z')

let YO: Yo | null = null
let LEADS: Lead[] = []
let VENDEDORES: Miembro[] = []
let OBJETIVOS: ObjetivosPorRol = objetivosCero()

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    ambito: { leads: LEADS, vendedores: VENDEDORES, esGlobal: false },
    actividades: [] as Actividad[],
    tareas: [],
    objetivos: OBJETIVOS,
    equipo: VENDEDORES,
    reasignar: () => ({ ok: true }),
  }),
  usePanelesActions: () => ({ abrirLead: () => {} }),
}))
// El panel de agenda del equipo vive de una RPC (TanStack) que no es lo que se
// prueba aquí: se apaga junto con su consulta para no montar un QueryClient.
vi.mock('./agenda-equipo', () => ({ AgendaEquipoPanel: () => null }))
vi.mock('@/data/crm-queries', () => ({
  useMetricasAgenda: () => ({
    data: undefined,
    error: null,
    isPending: false,
    isFetching: false,
    refetch: () => {},
  }),
}))
// crm-api arrastra el cliente de Supabase al importarse; solo se usa su
// formateador de errores.
vi.mock('@/data/crm-api', () => ({ mensajeDeError: (_e: unknown, f: string) => f }))

const { HoySupervisor } = await import('./supervisor')

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
  over: { leads?: Lead[]; objetivos?: Partial<ObjetivosPorRol['supervisor']> } = {},
): void {
  vi.setSystemTime(MIERCOLES_10AM)
  YO = {
    id: 's-1',
    nombre_completo: 'SUPERVISOR UNO',
    rol: 'supervisor',
    demo: false,
    puede_contratar: true,
  }
  LEADS = over.leads ?? [lead()]
  VENDEDORES = []
  OBJETIVOS = objetivosCero()
  OBJETIVOS.supervisor = {
    capitalObjetivo: 100_000,
    ventasObjetivo: 4,
    conversionObjetivo: 40,
    ...over.objetivos,
  }
  render(<HoySupervisor />)
}

beforeEach(() => {
  vi.useFakeTimers()
})

afterEach(() => {
  vi.useRealTimers()
})

describe('Hoy · supervisor — meta del equipo', () => {
  it('"Ventas cerradas" cuenta el MES vigente, no la vida entera', () => {
    montar({
      leads: [
        lead({ id: 'l-viejo', etapa: 'convertido', actualizado_en: '2026-05-20T15:00:00Z' }),
        lead({ id: 'l-viejo2', etapa: 'convertido', actualizado_en: '2026-06-20T15:00:00Z' }),
        lead({ id: 'l-mes', etapa: 'convertido', actualizado_en: '2026-07-09T15:00:00Z' }),
      ],
      objetivos: { ventasObjetivo: 4 },
    })

    // 1 de 4 este mes; antes decía "3 de 4" con dos cierres de meses cerrados.
    expect(screen.getByText('1 de 4')).toBeInTheDocument()
    expect(screen.queryByText('3 de 4')).not.toBeInTheDocument()
    // La diferencia con el acumulado se dice en voz alta.
    expect(
      screen.getByText('Cerradas este mes · 3 en total desde que el equipo lleva cartera.'),
    ).toBeInTheDocument()
  })

  it('la conversión es la del mes: convertidos sobre lo RESUELTO en el mes', () => {
    montar({
      leads: [
        lead({ id: 'l-c', etapa: 'convertido', actualizado_en: '2026-07-09T15:00:00Z' }),
        lead({ id: 'l-d', etapa: 'descartado', actualizado_en: '2026-07-10T15:00:00Z' }),
        // Resuelto el mes pasado: fuera del cálculo del periodo.
        lead({ id: 'l-viejo', etapa: 'descartado', actualizado_en: '2026-06-10T15:00:00Z' }),
        // Abierto: no vota todavía (conversionGlobal sí lo metía al divisor).
        lead({ id: 'l-abierto', etapa: 'propuesta_enviada' }),
      ],
      objetivos: { conversionObjetivo: 50 },
    })

    expect(screen.getByText('50% de 50%')).toBeInTheDocument()
  })

  it('un mes sin nada resuelto es SIN DATO, no un 0 % en rojo crítico', () => {
    montar({
      leads: [lead({ id: 'l-abierto', etapa: 'propuesta_enviada' })],
      objetivos: { conversionObjetivo: 40 },
    })

    expect(screen.getByText('Todavía no se resolvió ningún lead este mes')).toBeInTheDocument()
    expect(screen.getByText('—')).toBeInTheDocument()
    expect(screen.queryByText('0% de 40%')).not.toBeInTheDocument()
  })

  it('una meta que gerencia dejó en blanco NO se pinta como incumplida', () => {
    montar({ objetivos: { conversionObjetivo: 0 } })

    expect(screen.getByText('Sin meta fijada para este mes')).toBeInTheDocument()
    // Antes bastaba con tener capital y ventas fijadas para que la conversión
    // en blanco cayera al bloque semaforizado como "0% de 0%".
    expect(screen.queryByText('0% de 0%')).not.toBeInTheDocument()
    // Las otras dos filas conservan su objetivo y su barra.
    expect(screen.getByText('0 de 4')).toBeInTheDocument()
  })

  it('sin NINGUNA meta fijada cae al bloque "por definir" con el conteo del mes', () => {
    montar({
      leads: [
        lead({ id: 'l-mes', etapa: 'convertido', actualizado_en: '2026-07-09T15:00:00Z' }),
        lead({ id: 'l-viejo', etapa: 'convertido', actualizado_en: '2026-05-20T15:00:00Z' }),
      ],
      objetivos: { capitalObjetivo: 0, ventasObjetivo: 0, conversionObjetivo: 0 },
    })

    expect(screen.getByText(/Meta mensual del equipo por definir/)).toBeInTheDocument()
    expect(screen.getByText('Ventas cerradas este mes')).toBeInTheDocument()
    expect(screen.getByText('1')).toBeInTheDocument()
  })
})

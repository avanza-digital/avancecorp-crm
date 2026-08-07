import { describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import type { Rol } from './roles'

const derivarVendedor = vi.fn((_input: unknown) => [{
  id: 'personal-1',
  tipo: 'tarea_vencida',
  severidad: 'critica',
  alcance: 'personal',
  titulo: 'Tarea vencida',
  detalle: 'Pendiente personal',
  responsableId: 'v1',
  responsable: 'Ana',
  valor: 24,
  destino: { vista: 'agenda', leadId: 'lead-1', etiqueta: 'Abrir en Agenda' },
}])
const derivarSupervisor = vi.fn((_input: unknown) => [{
  id: 'equipo-1',
  tipo: 'por_repartir',
  severidad: 'critica',
  alcance: 'equipo',
  titulo: 'Lead por repartir',
  detalle: 'Pendiente del equipo',
  responsableId: 's1',
  responsable: null,
  valor: 1,
  destino: { vista: 'hoy', leadId: 'lead-2', etiqueta: 'Repartir lead' },
}])
const derivarGerencia = vi.fn((_input: unknown) => [{
  id: 'bajo_meta_conversion:v1',
  tipo: 'bajo_meta_conversion',
  severidad: 'atencion',
  responsableId: 'v1',
  responsable: 'Ana',
  equipo: 'Equipo Norte',
  valor: 8,
  actual: 8,
  objetivo: 15,
  brechaPp: 7,
  destino: 'ranking-vendedores',
}])

let YO: { id: string; rol: Rol; demo: boolean } | null = null
const LEADS = [{ id: 'lead-store' }]
const ACTIVIDADES = [{ id: 'actividad-store' }]
const TAREAS = [{ id: 'tarea-store' }]
const VENDEDORES = [{ perfil_id: 'v1' }]
const EQUIPO = [{ perfil_id: 'v1' }]
const ESTADOS_SLA = new Map()
const recargar = vi.fn(() => Promise.resolve(true))
const refetchActual = vi.fn()
const refetchAnterior = vi.fn()
const ACTUAL = { cohorte: { leads: 40, conversion_contratos_pct: 8 }, generado_en: '2026-08-06T17:00:00Z' }
const ANTERIOR = { cohorte: { leads: 35, conversion_contratos_pct: 15 }, generado_en: '2026-07-06T17:00:00Z' }
const consultasConversion = vi.fn((habilitada: boolean, desde: string) => ({
  data: desde === '2026-08-01' ? ACTUAL : ANTERIOR,
  error: null,
  isPending: false,
  isFetching: false,
  refetch: desde === '2026-08-01' ? refetchActual : refetchAnterior,
  enabled: habilitada,
}))

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/data/use-estado-sla-operativo', () => ({
  useEstadoSlaOperativo: () => ({
    indice: ESTADOS_SLA,
    cargando: false,
    error: null,
    recargar: vi.fn(),
  }),
}))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    ambito: { leads: LEADS, vendedores: VENDEDORES },
    actividadesDelAmbito: ACTIVIDADES,
    tareas: TAREAS,
    equipo: EQUIPO,
    objetivos: { porVendedor: { v1: { conversionObjetivo: 15 } } },
    objetivosError: false,
    recargar,
  }),
}))
vi.mock('@/lib/ahora', () => ({ useAhora: () => Date.UTC(2026, 7, 6, 17) }))
vi.mock('@/data/crm-api', () => ({ mensajeDeError: (_: unknown, fallback: string) => fallback }))
vi.mock('@/data/crm-queries', () => ({
  useMetricasConversiones: (...argumentos: Parameters<typeof consultasConversion>) =>
    consultasConversion(...argumentos),
}))
vi.mock('@/lib/conversion-equipo', () => ({
  identidadesEquipoConversion: () => [{ vendedorId: 'v1', nombre: 'Ana' }],
}))
vi.mock('@/lib/demo-inteligencia-comercial', () => ({
  conversionEquipoDemo: () => [],
  metasConversionEquipoDemo: () => ({}),
  metricasConversionesDemo: () => null,
}))
vi.mock('@/lib/alertas', () => ({
  derivarAlertasVendedor: (entrada: unknown) => derivarVendedor(entrada),
  derivarAlertasSupervisor: (entrada: unknown) => derivarSupervisor(entrada),
}))
vi.mock('@/lib/alertas-gerencia', () => ({
  derivarAlertasGerencia: (entrada: unknown) => derivarGerencia(entrada),
  periodoAnteriorComparable: () => ({ desde: '2026-07-01', hasta: '2026-07-06' }),
}))

const { AlertasCRMProvider } = await import('./alertas-provider')
const { useAlertasCRM } = await import('./alertas-context')

function Lector() {
  const estado = useAlertasCRM()
  return <output>{JSON.stringify(estado)}</output>
}

function montar(rol: Extract<Rol, 'vendedor' | 'supervisor' | 'gerencia'>) {
  YO = { id: rol === 'vendedor' ? 'v1' : rol === 'supervisor' ? 's1' : 'g1', rol, demo: false }
  derivarVendedor.mockClear()
  derivarSupervisor.mockClear()
  derivarGerencia.mockClear()
  consultasConversion.mockClear()
  return render(
    <AlertasCRMProvider>
      <Lector />
    </AlertasCRMProvider>,
  )
}

describe('AlertasCRMProvider', () => {
  it('deriva al vendedor solo desde su ámbito local y no habilita métricas globales', () => {
    montar('vendedor')

    expect(derivarVendedor).toHaveBeenCalledWith({
      vendedorId: 'v1',
      leads: LEADS,
      actividades: ACTIVIDADES,
      tareas: TAREAS,
      ahora: Date.UTC(2026, 7, 6, 17),
      estadosSla: ESTADOS_SLA,
    })
    expect(derivarSupervisor).not.toHaveBeenCalled()
    expect(derivarGerencia).not.toHaveBeenCalled()
    expect(consultasConversion.mock.calls.every(([habilitada]) => habilitada === false)).toBe(true)
    expect(screen.getByRole('status')).toHaveTextContent('personal-1')
  })

  it('deriva al supervisor con su roster visible y no consulta datos de Gerencia', () => {
    montar('supervisor')

    expect(derivarSupervisor).toHaveBeenCalledWith({
      supervisorId: 's1',
      leads: LEADS,
      actividades: ACTIVIDADES,
      tareas: TAREAS,
      vendedores: VENDEDORES,
      ahora: Date.UTC(2026, 7, 6, 17),
      estadosSla: ESTADOS_SLA,
    })
    expect(derivarVendedor).not.toHaveBeenCalled()
    expect(derivarGerencia).not.toHaveBeenCalled()
    expect(consultasConversion.mock.calls.every(([habilitada]) => habilitada === false)).toBe(true)
    expect(screen.getByRole('status')).toHaveTextContent('equipo-1')
  })

  it('habilita para Gerencia los dos cortes comparables y adapta la señal estratégica', () => {
    montar('gerencia')

    expect(consultasConversion).toHaveBeenNthCalledWith(1, true, '2026-07-01', '2026-07-06')
    expect(consultasConversion).toHaveBeenNthCalledWith(2, true, '2026-08-01', '2026-08-06')
    expect(derivarGerencia).toHaveBeenCalledWith(expect.objectContaining({
      conversiones: ACTUAL,
      conversionesAnteriores: ANTERIOR,
      diaDelMes: 6,
    }))
    expect(derivarVendedor).not.toHaveBeenCalled()
    expect(derivarSupervisor).not.toHaveBeenCalled()
    expect(screen.getByRole('status')).toHaveTextContent('bajo_meta_conversion:v1')
    expect(screen.getByRole('status')).toHaveTextContent('ranking-vendedores')
  })
})

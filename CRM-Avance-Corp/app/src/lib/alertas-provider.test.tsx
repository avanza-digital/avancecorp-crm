import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
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
  // F4: la foto de miembros que el libro de reconocimientos compara.
  miembros: ['lead-2'],
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
// F3: un recordatorio YA VENCIDO respecto del reloj congelado del arnés
// (2026-08-06T17:00Z) — la derivación real del provider debe hacerlo sonar.
const RECORDATORIOS = [{
  id: '5c073c2a-f22a-4979-8ea4-8921f746ef22',
  perfil_id: 'v1',
  telefono: '+51987654321',
  dni: null,
  recordar_en: '2026-08-05T14:00:00+00:00',
  creado_en: '2026-08-01T14:00:00+00:00',
}]
let LEADS: Array<{ id: string }> = [{ id: 'lead-store' }]
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

// Codex F3-R2: la campana vive tras el gate de funciones de leads (espejo de
// vistas.ts). El gate se controla desde aquí para probar los DOS estados, y
// se CAPTURAN los argumentos: un mock que los traga no prueba que el provider
// consulte con la identidad real (hallazgo T4 de la auditoría).
let LEADS_VISIBLES = true
const llamadasVisibilidad: Array<[boolean, string | null | undefined]> = []
vi.mock('@/lib/config', async (importActual) => {
  const actual = await importActual<typeof import('@/lib/config')>()
  return {
    ...actual,
    funcionesLeadsVisibles: (esDemo: boolean, rol?: string | null) => {
      llamadasVisibilidad.push([esDemo, rol])
      return LEADS_VISIBLES
    },
  }
})

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
const reconocerServidor = vi.fn((..._argumentos: unknown[]) => Promise.resolve())
vi.mock('@/data/crm-api', () => ({
  CrmApiError: class CrmApiError extends Error {
    code: string
    constructor(mensaje: string, code: string) {
      super(mensaje)
      this.code = code
    }
  },
  MAX_LEADS_AMBITO: 2000,
  mensajeDeError: (_: unknown, fallback: string) => fallback,
  reconocerAlertaSupervisor: (...argumentos: unknown[]) => reconocerServidor(...argumentos),
}))
let RECORDATORIOS_ERROR: Error | null = null
const refetchRecordatorios = vi.fn(() => Promise.resolve())
const consultaRecordatorios = vi.fn((habilitada: boolean) => ({
  data: habilitada && !RECORDATORIOS_ERROR ? RECORDATORIOS : [],
  error: RECORDATORIOS_ERROR,
  isPending: false,
  isFetching: false,
  refetch: refetchRecordatorios,
}))
// F4: el libro de reconocimientos del supervisor, con su propio grifo de
// error. OJO (Codex #1): con error, `data` se CONSERVA — es lo que hace
// TanStack Query cuando un refetch falla, y el provider debe ignorarla.
let RECONOCIMIENTOS_ERROR: Error | null = null
let RECONOCIMIENTOS: unknown[] = []
const refetchReconocimientos = vi.fn(() => Promise.resolve())
const consultaReconocimientos = vi.fn((habilitada: boolean) => ({
  data: habilitada ? RECONOCIMIENTOS : undefined,
  error: RECONOCIMIENTOS_ERROR,
  isPending: false,
  isFetching: false,
  refetch: refetchReconocimientos,
}))
vi.mock('@/data/crm-queries', () => ({
  crmQueryKeys: { reconocimientosAlertas: () => ['crm', 'reconocimientos-alertas'] },
  useMetricasConversiones: (...argumentos: Parameters<typeof consultasConversion>) =>
    consultasConversion(...argumentos),
  useRecordatoriosDisponibilidad: (habilitada: boolean) => consultaRecordatorios(habilitada),
  useReconocimientosAlertas: (habilitada: boolean) => consultaReconocimientos(habilitada),
}))
vi.mock('@/lib/conversion-equipo', () => ({
  identidadesEquipoConversion: () => [{ vendedorId: 'v1', nombre: 'Ana' }],
}))
vi.mock('@/lib/demo-inteligencia-comercial', () => ({
  conversionEquipoDemo: () => [],
  cumplimientoMetasConversionEquipoDemo: () => ({ porVendedor: {} }),
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
  return (
    <>
      <output>{JSON.stringify(estado)}</output>
      <button type="button" onClick={estado.reintentar}>reintentar</button>
      {/* F4: disparan reconocer/posponer con la MISMA alerta agrupada que
          derivarSupervisor mockea (equipo-1) — así el asiento resultante es
          observable en el estado que imprime el <output>. */}
      <button
        type="button"
        onClick={() => { void estado.reconocer(ALERTA_GRUPO, 'reconocer', null) }}
      >
        reconocer
      </button>
      <button
        type="button"
        onClick={() => {
          void estado.reconocer(
            ALERTA_GRUPO,
            'posponer',
            new Date(Date.now() + 86_400_000).toISOString(),
          )
        }}
      >
        posponer
      </button>
    </>
  )
}

/** La alerta que derivarSupervisor mockea, con su foto de miembros. */
const ALERTA_GRUPO = {
  id: 'equipo-1',
  tipo: 'por_repartir',
  severidad: 'critica',
  alcance: 'equipo',
  titulo: 'Lead por repartir',
  detalle: 'Pendiente del equipo',
  responsableId: 's1',
  responsable: null,
  valor: 1,
  miembros: ['lead-2'],
  destino: { vista: 'hoy', leadId: 'lead-2', etiqueta: 'Repartir lead' },
} as Parameters<ReturnType<typeof useAlertasCRM>['reconocer']>[0]

function montar(
  rol: Extract<Rol, 'vendedor' | 'supervisor' | 'gerencia'>,
  { demo = false }: { demo?: boolean } = {},
) {
  YO = { id: rol === 'vendedor' ? 'v1' : rol === 'supervisor' ? 's1' : 'g1', rol, demo }
  derivarVendedor.mockClear()
  derivarSupervisor.mockClear()
  derivarGerencia.mockClear()
  consultasConversion.mockClear()
  consultaRecordatorios.mockClear()
  consultaReconocimientos.mockClear()
  // F4: el provider usa useQueryClient (invalidación del libro) — necesita
  // el QueryClientProvider real aunque las queries estén mockeadas.
  const clienteConsultas = new QueryClient()
  render(
    <QueryClientProvider client={clienteConsultas}>
      <AlertasCRMProvider>
        <Lector />
      </AlertasCRMProvider>
    </QueryClientProvider>,
  )
  return { clienteConsultas }
}

beforeEach(() => {
  LEADS_VISIBLES = true
  LEADS = [{ id: 'lead-store' }]
  RECORDATORIOS_ERROR = null
  RECONOCIMIENTOS_ERROR = null
  RECONOCIMIENTOS = []
  refetchRecordatorios.mockClear()
  refetchReconocimientos.mockClear()
  reconocerServidor.mockClear()
  llamadasVisibilidad.length = 0
})

describe('AlertasCRMProvider', () => {
  it('deriva al analista solo desde su ámbito local y no habilita métricas globales', () => {
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
    // F3: con el gate abierto la campana SÍ consulta, y el recordatorio ya
    // vencido del arnés suena mediante la derivación real del provider.
    expect(consultaRecordatorios).toHaveBeenCalledWith(true)
    expect(screen.getByRole('status')).toHaveTextContent('revisar-contacto-5c073c2a-f22a-4979-8ea4-8921f746ef22')
    // T4: el gate se consulta con la IDENTIDAD real del actor, no al aire.
    expect(llamadasVisibilidad).toContainEqual([false, 'vendedor'])
  })

  it('F3.1: un fallo al listar recordatorios se DICE y Reintentar lo reintenta', () => {
    RECORDATORIOS_ERROR = new Error('red caída')
    montar('vendedor')

    // El fallo deja de ser mudo: viaja en los errores del contexto…
    expect(screen.getByRole('status')).toHaveTextContent(
      'No se pudieron cargar tus recordatorios de contacto.',
    )
    // …y Reintentar reintenta ESA consulta, no solo el store.
    fireEvent.click(screen.getByRole('button', { name: 'reintentar' }))
    expect(refetchRecordatorios).toHaveBeenCalledTimes(1)
    expect(recargar).toHaveBeenCalled()
  })

  it('F3.1: sin fallo de recordatorios no hay mensaje ni refetch de más', () => {
    montar('vendedor')

    expect(screen.getByRole('status')).not.toHaveTextContent('recordatorios de contacto')
    fireEvent.click(screen.getByRole('button', { name: 'reintentar' }))
    expect(refetchRecordatorios).not.toHaveBeenCalled()
  })

  it('R2 (Codex F3): con el gate de leads CERRADO la campana ni consulta ni suena', () => {
    LEADS_VISIBLES = false
    montar('vendedor')

    // El espejo de vistas.ts: si el analista no puede ABRIR la bandeja, el
    // provider no debe pedir recordatorios ni derivar alertas invisibles.
    expect(consultaRecordatorios).toHaveBeenCalledWith(false)
    expect(screen.getByRole('status')).not.toHaveTextContent('revisar-contacto')
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
    // Los recordatorios son EXCLUSIVOS del analista: supervisión ni consulta.
    expect(consultaRecordatorios).toHaveBeenCalledWith(false)
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

  it('F4: el libro se consulta SOLO para el supervisor, reconocer firma con su identidad y REFRESCA', async () => {
    const { clienteConsultas } = montar('supervisor')
    const invalidar = vi.spyOn(clienteConsultas, 'invalidateQueries')

    expect(consultaReconocimientos).toHaveBeenCalledWith(true)
    fireEvent.click(screen.getByRole('button', { name: 'reconocer' }))
    await vi.waitFor(() => {
      expect(reconocerServidor).toHaveBeenCalledWith(
        's1',
        'equipo-1',
        'reconocer',
        ['lead-2'],
        'critica',
        null,
      )
    })
    // Mutante Codex #9: borrar la invalidación tras el INSERT debe morir aquí.
    await vi.waitFor(() => {
      expect(invalidar).toHaveBeenCalledWith(
        { queryKey: ['crm', 'reconocimientos-alertas'] },
        { throwOnError: true },
      )
    })
  })

  it('F4 (Codex #1): con el libro en ERROR, los asientos CACHEADOS no se aplican — todo suena', () => {
    // El asiento pospondría equipo-1… pero el refetch falló: data conservada
    // por TanStack + error presente ⇒ el provider debe ignorar la caché.
    RECONOCIMIENTOS = [{
      id: '4c1f2a10-9f6a-49a4-8f7e-000000000002',
      alerta_id: 'equipo-1',
      accion: 'posponer',
      miembros: ['lead-2'],
      severidad: 'critica',
      hasta: '2026-08-07T17:00:00.000Z',
      creado_en: '2026-08-06T10:00:00.000Z',
      secuencia: 1,
    }]
    RECONOCIMIENTOS_ERROR = new Error('refetch caído')
    montar('supervisor')

    const estado = JSON.parse(screen.getByRole('status').textContent ?? '{}') as {
      pendientes: number
      pospuestas: number
      alertas: Array<{ id: string }>
    }
    expect(estado.pendientes).toBe(1)
    expect(estado.pospuestas).toBe(0)
    expect(estado.alertas[0]?.id).toBe('equipo-1')
  })

  it('F4 (Codex R2): con el gate de leads CERRADO el supervisor ni consulta el libro', () => {
    LEADS_VISIBLES = false
    montar('supervisor')

    expect(consultaReconocimientos).toHaveBeenCalledWith(false)
  })

  it('F4 demo: el espejo local asienta sin servidor y posponer SUPERSEDE por secuencia', async () => {
    montar('supervisor', { demo: true })

    // En demo el libro del servidor ni se consulta.
    expect(consultaReconocimientos).toHaveBeenCalledWith(false)

    fireEvent.click(screen.getByRole('button', { name: 'reconocer' }))
    await vi.waitFor(() => {
      const estado = JSON.parse(screen.getByRole('status').textContent ?? '{}') as {
        pendientes: number
        alertas: Array<{ reconocimiento?: { accion: string } }>
      }
      expect(estado.pendientes).toBe(0)
      expect(estado.alertas[0]?.reconocimiento?.accion).toBe('reconocer')
    })
    expect(reconocerServidor).not.toHaveBeenCalled()

    // El segundo asiento (posponer) manda por secuencia monotónica: oculta.
    fireEvent.click(screen.getByRole('button', { name: 'posponer' }))
    await vi.waitFor(() => {
      const estado = JSON.parse(screen.getByRole('status').textContent ?? '{}') as {
        alertas: unknown[]
        pospuestas: number
      }
      expect(estado.alertas).toHaveLength(0)
      expect(estado.pospuestas).toBe(1)
    })
  })

  it('F4 (Codex #5): con el ámbito EN el tope local, reconocer se desactiva y el libro se ignora', () => {
    LEADS = Array.from({ length: 2000 }, (_, i) => ({ id: `lead-${i}` }))
    RECONOCIMIENTOS = [{
      id: '4c1f2a10-9f6a-49a4-8f7e-000000000003',
      alerta_id: 'equipo-1',
      accion: 'reconocer',
      miembros: ['lead-2'],
      severidad: 'critica',
      hasta: null,
      creado_en: '2026-08-06T10:00:00.000Z',
      secuencia: 1,
    }]
    montar('supervisor')

    const estado = JSON.parse(screen.getByRole('status').textContent ?? '{}') as {
      pendientes: number
      errores: string[]
      alertas: Array<{ miembros?: string[]; reconocimiento?: unknown }>
    }
    // Sin foto confiable: nada se atenúa (el asiento NO se aplica)…
    expect(estado.pendientes).toBe(1)
    expect(estado.alertas[0]?.reconocimiento).toBeUndefined()
    // …los botones no existen (sin miembros no hay reconocer)…
    expect(estado.alertas[0]?.miembros).toBeUndefined()
    // …y el motivo se DICE.
    expect(estado.errores.join(' ')).toContain('tope local de leads')
  })

  it('F4: el analista ni consulta el libro ni puede asentar en él', () => {
    montar('vendedor')

    expect(consultaReconocimientos).toHaveBeenCalledWith(false)
    fireEvent.click(screen.getByRole('button', { name: 'reconocer' }))
    expect(reconocerServidor).not.toHaveBeenCalled()
  })

  it('F4: un asiento vigente ATENÚA en el contexto — pendientes descuenta y la alerta lleva su traza', () => {
    // Asiento que cubre a `equipo-1` (misma foto, misma severidad), fresco
    // respecto del reloj congelado del arnés (2026-08-06T17:00Z).
    RECONOCIMIENTOS = [{
      id: '4c1f2a10-9f6a-49a4-8f7e-000000000001',
      alerta_id: 'equipo-1',
      accion: 'reconocer',
      miembros: ['lead-2'],
      severidad: 'critica',
      hasta: null,
      creado_en: '2026-08-06T10:00:00.000Z',
      secuencia: 1,
    }]
    montar('supervisor')

    const estado = JSON.parse(screen.getByRole('status').textContent ?? '{}') as {
      pendientes: number
      alertas: Array<{ id: string; reconocimiento?: { accion: string } }>
    }
    expect(estado.pendientes).toBe(0)
    // La alerta NO se borra: sigue visible, con su traza de reconocimiento.
    expect(estado.alertas[0]?.id).toBe('equipo-1')
    expect(estado.alertas[0]?.reconocimiento?.accion).toBe('reconocer')
  })

  it('F4: un libro ilegible se DICE, las alertas suenan COMPLETAS y Reintentar lo reintenta', () => {
    RECONOCIMIENTOS_ERROR = new Error('red caída')
    montar('supervisor')

    expect(screen.getByRole('status')).toHaveTextContent(
      'No se pudieron leer tus reconocimientos; las alertas se muestran completas.',
    )
    // Degradación honesta: sin libro, nada se atenúa ni se oculta.
    const estado = JSON.parse(screen.getByRole('status').textContent ?? '{}') as { pendientes: number }
    expect(estado.pendientes).toBe(1)
    fireEvent.click(screen.getByRole('button', { name: 'reintentar' }))
    expect(refetchReconocimientos).toHaveBeenCalledTimes(1)
  })
})

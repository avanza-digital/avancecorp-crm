import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { Rol } from './roles'
import { GestionDiariaAvisosContext, type AvisosGestionDiaria } from './gestion-diaria-avisos-context'
import { avisosFixture } from './gestion-diaria-avisos.fixture'

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

let GD: AvisosGestionDiaria | null = null
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
    // Fase 4e: el store conoce lo que la pantalla muestra (aquí, sin efecto).
    conocerLeads: () => {}, asegurarLead: async () => true,
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

let RESUMEN_SLA = { version: 2, modo: 'legado', control_revision: 1, calculado_en: '2026-09-07T12:00:00Z', total_oportunidades: 0, total_avisos: 0, criticas: 0, grupos: [] as { bucket: string; total: number }[] }
let RESUMEN_ERROR: Error | null = null
const refrescarAvisos = vi.fn()
const consultarAvisos = vi.fn((habilitada: boolean) => ({ data: habilitada ? RESUMEN_SLA : undefined, error: RESUMEN_ERROR, isPending: false, isFetching: false, refetch: refrescarAvisos }))
vi.mock('@/data/sla-operacion-queries', () => ({ useResumenAvisosSla: (habilitada: boolean) => consultarAvisos(habilitada) }))

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
      <GestionDiariaAvisosContext.Provider value={GD}><AlertasCRMProvider>
        <Lector />
      </AlertasCRMProvider></GestionDiariaAvisosContext.Provider>
    </QueryClientProvider>,
  )
  return { clienteConsultas }
}

beforeEach(() => {
  GD = null
  RESUMEN_SLA = { ...RESUMEN_SLA, modo: 'legado', total_oportunidades: 0, total_avisos: 0, criticas: 0, grupos: [] }
  RESUMEN_ERROR = null
  refrescarAvisos.mockClear()
  consultarAvisos.mockClear()
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

    // Fase 3 «sin topes»: en sesión real ya no hay registro de actividades del
    // ámbito; con el modo SLA apagado el provider NO deriva alertas por
    // actividad (inventaría «sin contacto») y lo dice. Los recordatorios siguen.
    expect(derivarVendedor).not.toHaveBeenCalled()
    expect(screen.getByRole('status')).toHaveTextContent('modo SLA activo')
    expect(derivarSupervisor).not.toHaveBeenCalled()
    expect(derivarGerencia).not.toHaveBeenCalled()
    expect(consultasConversion.mock.calls.every(([habilitada]) => habilitada === false)).toBe(true)
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
    expect(screen.getByRole('status')).not.toHaveTextContent('personal-1')
  })

  it('deriva al supervisor con su roster visible y no consulta datos de Gerencia', () => {
    montar('supervisor', { demo: true })

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
    const estado = JSON.parse(screen.getByRole('status').textContent!)
    expect(estado.alertas[0].destino.periodo).toEqual({ desde: '2026-08-01', hasta: '2026-08-06' })
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

  it('F4: el analista ni consulta el libro ni puede asentar en él', () => {
    montar('vendedor')

    expect(consultaReconocimientos).toHaveBeenCalledWith(false)
    fireEvent.click(screen.getByRole('button', { name: 'reconocer' }))
    expect(reconocerServidor).not.toHaveBeenCalled()
  })

  it('Fase 3 «sin topes»: en sesión REAL con el modo SLA apagado no se derivan alertas por actividad y se dice por qué', () => {
    // Antes el provider derivaba desde el registro de actividades que bajaba
    // el arranque (recortado a 1 000 filas). Ya no existe: derivar sobre una
    // lista vacía inventaría «sin contacto» para toda la cartera. El libro F4
    // real queda sin alertas que atenuar; el espejo demo (test de arriba) vive.
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

    expect(derivarSupervisor).not.toHaveBeenCalled()
    const estado = JSON.parse(screen.getByRole('status').textContent ?? '{}') as {
      pendientes: number
      errores: string[]
      alertas: unknown[]
    }
    expect(estado.alertas).toEqual([])
    expect(estado.pendientes).toBe(0)
    expect(estado.errores.join(' ')).toContain('modo SLA activo')
  })
})

describe('campana gobernada por el núcleo SLA activo', () => {
  it.each(['vendedor', 'supervisor', 'gerencia'] as const)('usa el total del servidor para %s y conserva otros avisos', (rol) => {
    RESUMEN_SLA = { ...RESUMEN_SLA, modo: 'activo', total_oportunidades: 2501, total_avisos: 2502, criticas: 1,
      grupos: [{ bucket: 'seguimiento', total: 2501 }, { bucket: 'tarea_vencida', total: 1 }] }
    LEADS = []
    montar(rol)
    expect(derivarVendedor).not.toHaveBeenCalled()
    expect(derivarSupervisor).not.toHaveBeenCalled()
    const resultado = JSON.parse(screen.getByRole('status').textContent!)
    const aviso = resultado.alertas.find((a: { tipo: string }) => a.tipo === 'seguimiento_comercial')
    expect(aviso.valor).toBe(2501)
    expect(aviso.destino).toEqual({ vista: 'seguimiento', etiqueta: 'Ver pendientes' })
    expect(aviso.miembros).toBeUndefined()
    expect(consultaReconocimientos).toHaveBeenLastCalledWith(false)
    if (rol === 'vendedor') expect(resultado.alertas.some((a: { tipo: string }) => a.tipo === 'revisar_contacto')).toBe(true)
    if (rol === 'gerencia') expect(resultado.alertas.some((a: { tipo: string }) => a.tipo === 'bajo_meta_conversion')).toBe(true)
  })
  it('un error con datos anteriores no muestra Todo al día ni reactiva v1', () => {
    RESUMEN_SLA.modo = 'activo'
    RESUMEN_ERROR = new Error('Sin respuesta')
    montar('supervisor')
    expect(derivarSupervisor).not.toHaveBeenCalled()
    const resultado = JSON.parse(screen.getByRole('status').textContent!)
    expect(resultado.errores).toContain('No se pudieron confirmar los avisos de seguimiento. Pulsa Actualizar.')
    fireEvent.click(screen.getByText('reintentar'))
    expect(refrescarAvisos).toHaveBeenCalledOnce()
  })
})


describe('F4: una fuente para campana y lista diaria', () => {
  function contexto() {
    const datos = avisosFixture()
    datos.supervisor_id = 's1'
    datos.alertas = []
    datos.diarias = { modo_sla: 'activo', alertas: [
      { id: 'grupo:tarea_vencida:s1', tipo: 'tarea_vencida', severidad: 'atencion', miembros: ['lead-2'], total: 1 },
      { id: 'grupo:primera_atencion:s1', tipo: 'primera_atencion', severidad: 'atencion', miembros: ['lead-2'], total: 1 },
    ] }
    datos.contexto = { en_jornada: true, analistas: 0, con_llamadas: 0, equipo: [] }
    GD = { datos, cargando: false, error: null, ocupada: false, recargar: vi.fn(), actuar: vi.fn(),
      registroPedido: null, abrirRegistro: vi.fn(), consumirRegistro: vi.fn() }
  }
  it('sustituye el resumen duplicado y consulta el libro incluso con SLA activo', () => {
    contexto()
    RESUMEN_SLA = { ...RESUMEN_SLA, modo: 'activo', total_oportunidades: 1, total_avisos: 2,
      grupos: [{ bucket: 'tarea_vencida', total: 1 }, { bucket: 'primera_atencion', total: 1 }] }
    montar('supervisor')
    const estado = JSON.parse(screen.getByRole('status').textContent!)
    expect(estado.alertas.map((a: { id: string }) => a.id)).toEqual(['grupo:tarea_vencida:s1', 'grupo:primera_atencion:s1'])
    expect(estado.pendientes).toBe(2)
    expect(consultaReconocimientos).toHaveBeenCalledWith(true)
    expect(consultarAvisos).toHaveBeenCalledWith(false)
    expect(estado.alertas[0].miembros).toEqual(['lead-2'])
    expect(estado.alertas[1].miembros).toBeUndefined()
  })
  it('un fallo del libro mantiene el grupo completo y comunica el error', () => {
    contexto()
    RECONOCIMIENTOS_ERROR = new Error('desconectado')
    montar('supervisor')
    const estado = JSON.parse(screen.getByRole('status').textContent!)
    expect(estado.pendientes).toBe(2)
    expect(estado.errores.join(' ')).toContain('No se pudieron leer tus reconocimientos')
  })
})

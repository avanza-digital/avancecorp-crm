// Tests de la ruta REAL del store (sesión autenticada no-demo): gate de acciones
// abierto, persistencia optimista + resync contra el servidor, honestidad del
// rollback offline y estado de carga con reintento. La capa @/data/crm-api se
// mockea (sin red); CrmApiError se conserva real para el instanceof de persistir.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { useEffect, useRef } from 'react'
import type { Lead, Tarea } from './tipos'
import { act, render, waitFor } from '@testing-library/react'
import { QueryClient, QueryObserver } from '@tanstack/react-query'
import { toast } from 'sonner'
import { AuthContext, type AuthContextValue } from './auth-context'
import { useCRMData, usePanelesActions, usePanelesState, useStoreEstado } from './store-context'
import type { Rol } from './roles'
import type { PanelesActions, PanelesState, StoreDataApi, StoreEstado } from './store'
import type { Yo } from './tipos'
import type { ConfiguracionMetas, DetalleMeta } from './metas-versionadas'
import type { CumplimientoMetasRpc } from './objetivos'
import * as crmApi from '@/data/crm-api'
import { ejecutarComandoSla, hayIntencionPendienteSla, hayLlamadaV3Pendiente, tareaConConfirmacionPendiente } from '@/data/sla-operacion-comandos'

vi.mock('@/data/sla-operacion-comandos', () => ({
  ejecutarComandoSla: vi.fn(), tareaConConfirmacionPendiente: vi.fn(),
  hayIntencionPendienteSla: vi.fn(), hayLlamadaV3Pendiente: vi.fn(),
}))
import { deshacerResultadoLlamada as deshacerResultadoLlamadaFn } from '@/data/gestion-diaria-api'

vi.mock('@/data/gestion-diaria-api', async (importActual) => ({
  ...await importActual<typeof import('@/data/gestion-diaria-api')>(),
  deshacerResultadoLlamada: vi.fn(),
}))
import { crmQueryKeys } from '@/data/crm-queries'
import { slaOperacionKeys } from '@/data/sla-operacion-queries'
import { queryClient } from './query-client'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

vi.mock('./query-client', () => ({
  queryClient: {
    invalidateQueries: vi.fn().mockResolvedValue(undefined),
    cancelQueries: vi.fn().mockResolvedValue(undefined),
    // Historial por lead en caché (gates de descartar/retroceso): sin datos,
    // el store cae a su evidencia local — lo que estas pruebas ejercitan.
    getQueryData: vi.fn(() => undefined),
    getQueryState: vi.fn(() => undefined),
  },
}))

vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return {
    ...actual, // conserva CrmApiError real (instanceof en persistir)
    obtenerLeadDelAmbitoPorId: vi.fn(),
    obtenerTareaDelAmbitoPorId: vi.fn(),
    listarEquipo: vi.fn(),
    listarTareasDelAmbito: vi.fn(),
    obtenerMetasDelMes: vi.fn(),
    obtenerCumplimientoMetas: vi.fn(),
    insertarLead: vi.fn(),
    insertarTarea: vi.fn(),
    cerrarTarea: vi.fn(),
    cerrarReunion: vi.fn(),
    reprogramarReunion: vi.fn(),
    actualizarLead: vi.fn(),
    actualizarTarea: vi.fn(),
    insertarActividad: vi.fn(),
    reabrirLead: vi.fn(),
    editarLeadFn: vi.fn(),
  }
})

const { StoreProvider, LIMITE_CARGA_REAL_MS } = await import('./store')
const { CrmApiError } = crmApi

// Fase 4e «sin topes»: el arranque ya no baja la foto de leads. Lo que antes
// devolvía `listarLeadsDelAmbito` ahora lo REGISTRAN las pantallas con
// `conocerLeads` tras recibirlo del servidor; la sonda del arnés lo hace por
// ellas en cuanto termina cada arranque (misma semántica que el mock: una
// semilla por defecto y semillas «once» por arranque).
const SEMILLA: { siempre: Lead[]; cola: Lead[][] } = { siempre: [], cola: [] }
const listarLeads = {
  mockResolvedValue: (leads: Lead[]) => { SEMILLA.siempre = leads },
  mockResolvedValueOnce: (leads: Lead[]) => { SEMILLA.cola.push(leads) },
}
const obtenerLeadPorId = vi.mocked(crmApi.obtenerLeadDelAmbitoPorId)
const listarEquipo = vi.mocked(crmApi.listarEquipo)
const insertarLead = vi.mocked(crmApi.insertarLead)
const actualizarLead = vi.mocked(crmApi.actualizarLead)
const reabrirLead = vi.mocked(crmApi.reabrirLead)
const editarLeadFn = vi.mocked(crmApi.editarLeadFn)
const actualizarTarea = vi.mocked(crmApi.actualizarTarea)
const insertarActividad = vi.mocked(crmApi.insertarActividad)
const listarTareas = vi.mocked(crmApi.listarTareasDelAmbito)
const insertarTarea = vi.mocked(crmApi.insertarTarea)
const comandoSla = vi.mocked(ejecutarComandoSla)
const cerrarTareaMock = vi.mocked(crmApi.cerrarTarea)
const cerrarReunionMock = vi.mocked(crmApi.cerrarReunion)
const reprogramarReunionMock = vi.mocked(crmApi.reprogramarReunion)
const obtenerMetasMock = vi.mocked(crmApi.obtenerMetasDelMes)
const obtenerCumplimientoMock = vi.mocked(crmApi.obtenerCumplimientoMetas)
const invalidarQueriesMock = vi.mocked(queryClient.invalidateQueries)
const deshacerLlamadaMock = vi.mocked(deshacerResultadoLlamadaFn)

const ROSTER = [
  {
    perfil_id: 'u-ger',
    nombre_completo: 'Gerente Real',
    rol_crm: 'gerencia' as const,
    supervisor_id: null,
    activo: true,
  },
  {
    perfil_id: 'u-s1',
    nombre_completo: 'Supervisor Real',
    rol_crm: 'supervisor' as const,
    supervisor_id: null,
    activo: true,
  },
  {
    perfil_id: 'u-v1',
    nombre_completo: 'Analista Real',
    rol_crm: 'vendedor' as const,
    supervisor_id: 'u-s1',
    activo: true,
  },
]

function detallesMeta(capitalPen = 0, capitalUsd = 0): DetalleMeta[] {
  return [
    {
      categoria: 'nuevo',
      moneda: 'PEN',
      capital_objetivo: capitalPen,
      contratos_objetivo: capitalPen > 0 ? 2 : 0,
    },
    {
      categoria: 'nuevo',
      moneda: 'USD',
      capital_objetivo: capitalUsd,
      contratos_objetivo: capitalUsd > 0 ? 1 : 0,
    },
    {
      categoria: 'renovacion',
      moneda: 'PEN',
      capital_objetivo: 0,
      contratos_objetivo: 0,
    },
    {
      categoria: 'renovacion',
      moneda: 'USD',
      capital_objetivo: 0,
      contratos_objetivo: 0,
    },
    {
      categoria: 'upgrade',
      moneda: 'PEN',
      capital_objetivo: 0,
      contratos_objetivo: 0,
    },
    {
      categoria: 'upgrade',
      moneda: 'USD',
      capital_objetivo: 0,
      contratos_objetivo: 0,
    },
  ]
}

function configuracionMetas(capitalPen = 0, capitalUsd = 0, conversionObjetivo = 0): ConfiguracionMetas {
  return {
    version: 1,
    periodo: '2026-08-01',
    sin_supervisor: [],
    revision: capitalPen > 0 || capitalUsd > 0 || conversionObjetivo > 0 ? 4 : 0,
    publicada_en: null,
    publicada_por: null,
    publicada_por_nombre: null,
    puede_editar: true,
    vendedores: [
      {
        vendedor_id: 'u-v1',
        nombre: 'Analista Real',
        supervisor_id: 'u-s1',
        supervisor_nombre: 'Supervisor Real',
        conversion_objetivo: conversionObjetivo,
        detalles: detallesMeta(capitalPen, capitalUsd),
      },
    ],
  }
}

function cumplimientoMetas(
  capitalPen = 0,
  capitalUsd = 0,
  conversionReal: number | null = null,
  configuracion = configuracionMetas(),
): CumplimientoMetasRpc {
  return {
    version: 1,
    periodo: configuracion.periodo,
    revision: configuracion.revision,
    publicada_en: configuracion.publicada_en,
    fuentes_reales: {
      capital_y_contratos: 'contratos_confirmados',
      conversion: 'leads_resueltos',
    },
    vendedores: configuracion.vendedores.map((vendedor) => ({
      vendedor_id: vendedor.vendedor_id,
      nombre: vendedor.nombre,
      supervisor_id: vendedor.supervisor_id,
      supervisor_nombre: vendedor.supervisor_nombre,
      conversion_objetivo: vendedor.conversion_objetivo,
      conversion_real: conversionReal,
      convertidos: conversionReal == null ? 0 : 2,
      resueltos: conversionReal == null ? 0 : 4,
      detalles: vendedor.detalles.map((detalle) => ({
        ...detalle,
        capital_real: detalle.categoria === 'nuevo' ? (detalle.moneda === 'PEN' ? capitalPen : capitalUsd) : 0,
        capital_cumplimiento_pct: null,
        contratos_real: 0,
        contratos_cumplimiento_pct: null,
      })),
    })),
  }
}

function leadBase() {
  return {
    id: '11111111-1111-4111-8111-111111111111',
    nombre_completo: 'CLIENTE EXISTENTE',
    telefono: '+51999888777',
    correo: null,
    dni: null,
    distrito: null,
    origen: 'landing' as const,
    etapa: 'nuevo' as const,
    motivo_descarte: null,
    monto_estimado: 1000,
    moneda: 'PEN' as const,
    categoria_interes: null,
    vendedor_id: 'u-v1',
    asignado_supervisor_id: null,
    creado_en: '2026-07-01T00:00:00.000Z',
    activo: true,
    nota: null,
  }
}

function sesionReal(rol: Rol, overrides: Partial<Yo> = {}): AuthContextValue {
  const identidad =
    rol === 'gerencia'
      ? { id: 'u-ger', nombre_completo: 'Gerente Real' }
      : rol === 'supervisor'
        ? { id: 'u-s1', nombre_completo: 'Supervisor Real' }
        : rol === 'vendedor'
          ? { id: 'u-v1', nombre_completo: 'Analista Real' }
          : { id: `u-${rol}`, nombre_completo: `Usuario ${rol}` }
  return {
    fase: 'listo',
    yo: { ...identidad, rol, demo: false, puede_contratar: true, ...overrides },
    error: null,
    entrar: async () => ({ ok: true }),
    entrarDemo: () => undefined,
    reintentar: () => undefined,
    salir: async () => undefined,
  }
}

interface Montaje {
  api: () => StoreDataApi
  estado: () => StoreEstado
  panelActions: () => PanelesActions
  panelState: () => PanelesState
  rerenderAuth: (rol: Rol, overrides?: Partial<Yo>) => void
  mutar: <T>(fn: (api: StoreDataApi) => T) => T
}

function montar(rol: Rol = 'gerencia', overrides: Partial<Yo> = {}): Montaje {
  const ref: {
    api: StoreDataApi | null
    estado: StoreEstado | null
    panelActions: PanelesActions | null
    panelState: PanelesState | null
  } = {
    api: null,
    estado: null,
    panelActions: null,
    panelState: null,
  }
  function Sonda(): null {
    ref.api = useCRMData()
    ref.estado = useStoreEstado()
    ref.panelActions = usePanelesActions()
    ref.panelState = usePanelesState()
    // Al terminar cada arranque, las «pantallas» registran su semilla de leads.
    const cargando = ref.estado.cargando
    const api = ref.api
    const sembradoTrasBoot = useRef(0)
    useEffect(() => {
      // Solo tras un arranque que consultó la operación (una llamada nueva a
      // listarTareas): un rol sin operación o un arranque en vuelo no siembran.
      const boots = listarTareas.mock.calls.length
      if (!cargando && boots > sembradoTrasBoot.current) {
        sembradoTrasBoot.current = boots
        const semilla = SEMILLA.cola.shift() ?? SEMILLA.siempre
        if (semilla.length > 0) api.conocerLeads(semilla)
      }
    }, [api, cargando])
    return null
  }
  const arbol = (nuevoRol: Rol, nuevaIdentidad: Partial<Yo> = {}) => (
    <AuthContext.Provider value={sesionReal(nuevoRol, nuevaIdentidad)}>
      <StoreProvider>
        <Sonda />
      </StoreProvider>
    </AuthContext.Provider>
  )
  const vista = render(arbol(rol, overrides))
  return {
    api: () => {
      if (!ref.api) throw new Error('StoreProvider aún no montado')
      return ref.api
    },
    estado: () => {
      if (!ref.estado) throw new Error('StoreProvider aún no montado')
      return ref.estado
    },
    panelActions: () => {
      if (!ref.panelActions) throw new Error('StoreProvider aún no montado')
      return ref.panelActions
    },
    panelState: () => {
      if (!ref.panelState) throw new Error('StoreProvider aún no montado')
      return ref.panelState
    },
    rerenderAuth: (nuevoRol, nuevaIdentidad = {}) => {
      vista.rerender(arbol(nuevoRol, nuevaIdentidad))
    },
    mutar: (fn) => {
      let r!: ReturnType<typeof fn>
      act(() => {
        r = fn(ref.api as StoreDataApi)
      })
      return r
    },
  }
}

function diferida<T>() {
  let resolver!: (valor: T) => void
  const promesa = new Promise<T>((resolve) => { resolver = resolve })
  return { promesa, resolver }
}

describe('store — ruta real (sesión autenticada, no demo)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    invalidarQueriesMock.mockReset().mockResolvedValue(undefined)
    vi.mocked(queryClient.cancelQueries).mockReset().mockResolvedValue(undefined)
    comandoSla.mockResolvedValue(undefined)
    vi.mocked(hayIntencionPendienteSla).mockReset().mockReturnValue(false)
    vi.mocked(hayLlamadaV3Pendiente).mockReset().mockReturnValue(false)
    vi.mocked(tareaConConfirmacionPendiente).mockReset()
    SEMILLA.cola = []
    listarLeads.mockResolvedValue([leadBase()])
    obtenerLeadPorId.mockReset().mockResolvedValue(null)
    listarEquipo.mockResolvedValue(ROSTER)
    insertarLead.mockImplementation(async (fila) => {
      if (!fila.id) throw new Error('El test real exige el id optimista')
      return { estado: 'creado', lead_id: fila.id }
    })
    listarTareas.mockResolvedValue([])
    obtenerMetasMock.mockResolvedValue(configuracionMetas())
    obtenerCumplimientoMock.mockResolvedValue(cumplimientoMetas())
    insertarTarea.mockResolvedValue(undefined)
    cerrarTareaMock.mockResolvedValue({ siguiente_id: null })
    cerrarReunionMock.mockResolvedValue({ siguiente_id: null })
    reprogramarReunionMock.mockImplementation(async (_tareaId, _venceEn, nuevaId) => ({
      tarea_nueva_id: nuevaId,
    }))
    actualizarLead.mockResolvedValue(undefined)
    reabrirLead.mockResolvedValue(undefined)
    editarLeadFn.mockResolvedValue(undefined)
    actualizarTarea.mockResolvedValue(undefined)
    insertarActividad.mockResolvedValue(undefined)
  })
  afterEach(() => vi.clearAllMocks())

  it('el origen exacto selecciona v5 y devuelve el enlace confirmado sin escrituras sueltas', async () => {
    const { api, mutar } = montar('vendedor')
    const lead = leadBase()
    await waitFor(() => expect(api().lead(lead.id)).toBeDefined())
    comandoSla.mockResolvedValueOnce({ actividad_id: 'act', siguiente_id: null, descartado: false, enlace: { estado: 'pendiente' } })
    const r = mutar((a) => a.registrarLlamada(lead.id, { resultado: 'no_contesto', evento_origen_id: 'C1-1790980958', via_llamada: 'pestana' }))
    await act(async () => { expect(await r.persistido).toBe(true) })
    expect(comandoSla).toHaveBeenCalledWith('u-v1', 'registrar_llamada_v5', lead.id, expect.objectContaining({ p_evento_origen_id: 'C1-1790980958', p_via: 'pestana' }))
    expect(await r.confirmacion).toMatchObject({ actividad_id: 'act', enlace: { estado: 'pendiente' } })
    expect(insertarActividad).not.toHaveBeenCalled()
  })

  it('resultado sin interés y seguimiento se envían a v4 sin descarte ni escrituras sueltas', async () => {
    const { api, mutar } = montar('vendedor')
    const lead = leadBase()
    await waitFor(() => expect(api().lead(lead.id)).toBeDefined())
    const siguiente = { tipo: 'tarea', titulo: 'Preparar información', vence_en: new Date(Date.now() + 86_400_000).toISOString() }
    const r = mutar((a) => a.registrarLlamada(lead.id, { resultado: 'no_interesado', submotivo: 'otro', siguiente }))
    expect(r.ok).toBe(true)
    await act(async () => { expect(await r.persistido).toBe(true) })
    expect(comandoSla).toHaveBeenCalledWith('u-v1', 'registrar_llamada_v4', lead.id, expect.objectContaining({
      p_resultado: 'no_interesado', p_submotivo: 'otro', p_descartar: false, p_no_insista: false,
      p_siguiente: expect.objectContaining(siguiente),
    }))
    expect(insertarActividad).not.toHaveBeenCalled()
    expect(insertarTarea).not.toHaveBeenCalled()
    expect(actualizarLead).not.toHaveBeenCalled()
  })

  it('un recibo legacy bloquea una nueva interpretación antes del optimista o de la red', async () => {
    const { api, mutar } = montar('vendedor')
    const lead = leadBase()
    await waitFor(() => expect(api().lead(lead.id)).toBeDefined())
    vi.mocked(hayLlamadaV3Pendiente).mockReturnValue(true)
    const antes = api().actividadesDe(lead.id)
    const r = mutar((a) => a.registrarLlamada(lead.id, { resultado: 'no_interesado', submotivo: 'otro', descartar: false }))
    expect(r).toMatchObject({ ok: false, error: expect.stringContaining('Guardados por confirmar') })
    expect(api().actividadesDe(lead.id)).toEqual(antes)
    expect(comandoSla).not.toHaveBeenCalled()
  })

  it('un replay conserva p_tarea_id aunque la tarea cerrada ya no esté en las pendientes', async () => {
    const { api, mutar } = montar('vendedor')
    const lead = leadBase()
    await waitFor(() => expect(api().lead(lead.id)).toBeDefined())
    const tarea = { id: 'tarea-cerrada', lead_id: lead.id, tipo: 'llamada', titulo: 'Llamar',
      vence_en: new Date().toISOString(), estado: 'pendiente', activo: true, reprogramaciones: 0,
      creado_en: new Date().toISOString() } as Tarea
    vi.mocked(hayIntencionPendienteSla).mockReturnValue(true)
    vi.mocked(tareaConConfirmacionPendiente).mockReturnValue(tarea)
    expect(api().tareas).toHaveLength(0)
    const r = mutar((a) => a.registrarLlamada(lead.id, {
      resultado: 'no_interesado', submotivo: 'otro', tarea_id: tarea.id,
      siguiente: { tipo: 'tarea', titulo: 'Siguiente', vence_en: new Date(Date.now() - 86_400_000).toISOString() },
    }))
    expect(r.ok).toBe(true)
    await act(async () => { expect(await r.persistido).toBe(true) })
    expect(comandoSla).toHaveBeenCalledWith('u-v1', 'registrar_llamada_v4', lead.id,
      expect.objectContaining({ p_tarea_id: tarea.id, p_descartar: false }), tarea)
  })

  it('un replay con siguiente llega al servidor aunque el dueño haya cambiado', async () => {
    const lead = { ...leadBase(), vendedor_id: 'u-ger' }
    listarLeads.mockResolvedValue([lead])
    const { api, mutar } = montar('vendedor')
    await waitFor(() => expect(api().lead(lead.id)).toBeDefined())
    vi.mocked(hayIntencionPendienteSla).mockReturnValue(true)
    const r = mutar((a) => a.registrarLlamada(lead.id, {
      resultado: 'no_interesado', submotivo: 'otro',
      siguiente: { tipo: 'tarea', titulo: 'Siguiente original', vence_en: new Date(Date.now() - 86_400_000).toISOString() },
    }))
    expect(r.ok).toBe(true)
    await act(async () => { expect(await r.persistido).toBe(true) })
    expect(comandoSla).toHaveBeenCalledWith('u-v1', 'registrar_llamada_v4', lead.id, expect.objectContaining({ p_descartar: false }))
  })

  it('carga el ámbito operativo y resuelve vendedor_nombre desde el roster', async () => {
    const { api } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    expect(api().leads[0]?.vendedor_nombre).toBe('Analista Real')
  })

  it('resuelve cargado_por_nombre desde el mismo roster (P2 de Codex, 19/09): quien lo cargó, con nombre, y sin autor queda null', async () => {
    listarLeads.mockResolvedValueOnce([
      { ...leadBase(), procedencia: 'manual', cargado_por: 'u-v1' },
      { ...leadBase(), id: '44444444-4444-4444-8444-444444444444', nombre_completo: 'DEL PUENTE', procedencia: 'sistema', cargado_por: null },
      { ...leadBase(), id: '55555555-5555-4555-8555-555555555555', nombre_completo: 'AUTOR FUERA DEL ROSTER', procedencia: 'manual', cargado_por: 'u-desconocido' },
    ])
    const { api } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(3))
    expect(api().leads[0]).toMatchObject({ procedencia: 'manual', cargado_por: 'u-v1', cargado_por_nombre: 'Analista Real' })
    expect(api().leads[1]).toMatchObject({ procedencia: 'sistema', cargado_por: null, cargado_por_nombre: null })
    expect(api().leads[2]).toMatchObject({ procedencia: 'manual', cargado_por: 'u-desconocido', cargado_por_nombre: null })
  })

  describe('apertura de fichas autorizadas fuera de la carga inicial', () => {
    const ID_A = '22222222-2222-4222-8222-222222222222'
    const ID_B = '33333333-3333-4333-8333-333333333333'
    const filaA = () => ({ ...leadBase(), id: ID_A, nombre_completo: 'FICHA FUERA DEL BOOT', nota: 'Dato completo del servidor' })
    const filaB = () => ({ ...leadBase(), id: ID_B, nombre_completo: 'ÚLTIMA FICHA SOLICITADA' })
    type LecturaLead = Awaited<ReturnType<typeof crmApi.obtenerLeadDelAmbitoPorId>>

    async function abrir(montaje: Montaje, id: string) {
      let resultado: boolean | void
      await act(async () => { resultado = await montaje.panelActions().abrirLead(id) })
      return resultado!
    }

    it('conserva una marca de reasignado conocida si falla solo la lectura opcional del historial', async () => {
      const conocido = { ...leadBase(), reasignado: true }
      listarLeads.mockResolvedValueOnce([conocido])
      const montaje = montar('gerencia')
      await waitFor(() => expect(montaje.api().lead(conocido.id)?.reasignado).toBe(true))
      obtenerLeadPorId.mockResolvedValue({ ...conocido, reasignado: null })
      expect(await abrir(montaje, conocido.id)).toBe(true)
      expect(montaje.api().lead(conocido.id)?.reasignado).toBe(true)
    })

    it('incorpora una actividad leída por ID fuera del lote y rechaza respuestas de otra sesión', async () => {
      const montaje = montar('gerencia')
      await waitFor(() => expect(montaje.estado().cargando).toBe(false))
      obtenerLeadPorId.mockResolvedValue(filaA())
      await abrir(montaje, ID_A)
      const tarea: Awaited<ReturnType<typeof crmApi.obtenerTareaDelAmbitoPorId>> = {
        id: 'tarea-fuera-lote', lead_id: ID_A, perfil_id: null, vendedor_id: 'u-v1', asignado_supervisor_id: null,
        tipo: 'llamada', titulo: 'Contacto pendiente', nota: null, vence_en: '2026-09-07T10:00:00Z', estado: 'pendiente', activo: true,
        reprogramaciones: 0, creado_en: '2026-09-06T10:00:00Z', duracion_min: null, modalidad_reunion: null,
        ubicacion_reunion: null, enlace_reunion: null, resultado_reunion: null, motivo_no_realizada: null,
        detalle_cierre_reunion: null, confirmada_en: null, reagendada_de: null,
      }
      const obtener = vi.mocked(crmApi.obtenerTareaDelAmbitoPorId)
      obtener.mockResolvedValueOnce(tarea)
      await act(async () => { expect(await montaje.api().obtenerTareaParaRevision(ID_A, tarea.id)).toEqual(tarea) })
      expect(montaje.api().tareasDe(ID_A)).toContainEqual(tarea)
      expect(obtener).toHaveBeenCalledWith(ID_A, tarea.id, expect.any(AbortSignal))
      let resolver!: (valor: typeof tarea) => void
      obtener.mockImplementationOnce(() => new Promise((resolve) => { resolver = resolve }))
      let lectura!: Promise<typeof tarea | null>
      act(() => { lectura = montaje.api().obtenerTareaParaRevision(ID_A, 'tarea-tardia') })
      montaje.rerenderAuth('vendedor')
      await waitFor(() => expect(montaje.estado().cargando).toBe(false))
      await act(async () => { resolver({ ...tarea, id: 'tarea-tardia' }); expect(await lectura).toBeNull() })
      expect(montaje.api().tareas.some((t) => t.id === 'tarea-tardia')).toBe(false)
    })

    it('hidrata la fila completa y su analista antes de abrir la ficha', async () => {
      const montaje = montar('gerencia')
      await waitFor(() => expect(montaje.estado().cargando).toBe(false))
      expect(montaje.api().lead(ID_A)).toBeUndefined()
      obtenerLeadPorId.mockResolvedValueOnce(filaA())

      expect(await abrir(montaje, ID_A)).toBe(true)

      expect(obtenerLeadPorId).toHaveBeenCalledWith(ID_A, expect.any(AbortSignal))
      expect(montaje.api().lead(ID_A)).toMatchObject({
        ...filaA(), vendedor_nombre: 'Analista Real',
      })
      expect(montaje.api().ambito.leads.map((l) => l.id)).toEqual([leadBase().id, ID_A])
      expect(montaje.panelState().leadAbiertoId).toBe(ID_A)
    })

    it('abre una fila conocida RELEYÉNDOLA por id (Fase 4e: lo conocido puede estar revocado)', async () => {
      const montaje = montar()
      await waitFor(() => expect(montaje.estado().cargando).toBe(false))
      obtenerLeadPorId.mockResolvedValueOnce(filaA())

      expect(await abrir(montaje, ID_A)).toBe(true)

      expect(montaje.panelState().leadAbiertoId).toBe(ID_A)
      expect(obtenerLeadPorId).toHaveBeenCalledTimes(1)
      expect(montaje.api().lead(ID_A)).toMatchObject({ id: ID_A, vendedor_nombre: 'Analista Real' })
    })

    it('una fila conocida que el servidor ya no autoriza deja de ser conocida al intentar abrirla', async () => {
      const montaje = montar()
      await waitFor(() => expect(montaje.estado().cargando).toBe(false))
      expect(montaje.api().lead(leadBase().id)).toBeDefined()
      obtenerLeadPorId.mockResolvedValueOnce(null)

      expect(await abrir(montaje, leadBase().id)).toBe(false)

      expect(montaje.panelState().leadAbiertoId).toBeNull()
      expect(montaje.api().lead(leadBase().id)).toBeUndefined()
    })

    it.each(['sin acceso', 'error remoto'] as const)('no inventa ni abre una ficha ante %s', async (caso) => {
      const montaje = montar()
      await waitFor(() => expect(montaje.estado().cargando).toBe(false))
      if (caso === 'error remoto') obtenerLeadPorId.mockRejectedValueOnce(new Error('Lectura rechazada'))

      expect(await abrir(montaje, ID_A)).toBe(false)

      expect(montaje.api().lead(ID_A)).toBeUndefined()
      expect(montaje.api().leads).toHaveLength(1)
      expect(montaje.panelState().leadAbiertoId).toBeNull()
      expect(toast.error).toHaveBeenCalled()
    })

    it.each(['cerrar', 'nueva ficha'] as const)('ignora la respuesta tardía después de %s', async (accion) => {
      const lectura = diferida<LecturaLead>()
      obtenerLeadPorId.mockReturnValueOnce(lectura.promesa)
      const montaje = montar()
      await waitFor(() => expect(montaje.estado().cargando).toBe(false))
      let apertura!: ReturnType<PanelesActions['abrirLead']>
      act(() => { apertura = montaje.panelActions().abrirLead(ID_A) })
      const signal = obtenerLeadPorId.mock.calls[0]?.[1]

      act(() => {
        if (accion === 'cerrar') montaje.panelActions().cerrarPaneles()
        else montaje.panelActions().abrirNuevoLead('contactado', '+51999000111')
      })
      expect(signal?.aborted).toBe(true)
      await act(async () => {
        // El transporte simulado responde incluso tras abortar: el store debe
        // descartar también por intención, sin depender de la cancelación HTTP.
        lectura.resolver(filaA())
        expect(await apertura).toBe(false)
      })

      expect(montaje.api().lead(ID_A)).toBeUndefined()
      expect(montaje.panelState()).toMatchObject({
        leadAbiertoId: null, nuevoLeadAbierto: accion === 'nueva ficha',
      })
      if (accion === 'nueva ficha') expect(montaje.panelState()).toMatchObject({
        etapaInicial: 'contactado', telefonoInicial: '+51999000111',
      })
      expect(toast.error).not.toHaveBeenCalled()
    })

    it('la última intención gana aunque la primera lectura termine después', async () => {
      const lecturaA = diferida<LecturaLead>()
      obtenerLeadPorId.mockReturnValueOnce(lecturaA.promesa).mockResolvedValueOnce(filaB())
      const montaje = montar()
      await waitFor(() => expect(montaje.estado().cargando).toBe(false))
      let aperturaA!: ReturnType<PanelesActions['abrirLead']>
      act(() => { aperturaA = montaje.panelActions().abrirLead(ID_A) })

      expect(await abrir(montaje, ID_B)).toBe(true)
      await act(async () => {
        lecturaA.resolver(filaA())
        expect(await aperturaA).toBe(false)
      })

      expect(montaje.panelState().leadAbiertoId).toBe(ID_B)
      expect(montaje.api().lead(ID_B)).toMatchObject(filaB())
      expect(montaje.api().lead(ID_A)).toBeUndefined()
      expect(obtenerLeadPorId.mock.calls[0]?.[1]?.aborted).toBe(true)
    })

    it.each(['otro actor', 'otro rol del mismo actor'] as const)('descarta una apertura pendiente al cambiar a %s', async (cambio) => {
      const lectura = diferida<LecturaLead>()
      obtenerLeadPorId.mockReturnValueOnce(lectura.promesa)
      const montaje = montar('gerencia')
      await waitFor(() => expect(montaje.estado().cargando).toBe(false))
      let apertura!: ReturnType<PanelesActions['abrirLead']>
      act(() => { apertura = montaje.panelActions().abrirLead(ID_A) })
      const nuevoBoot = diferida<Awaited<ReturnType<typeof crmApi.listarTareasDelAmbito>>>()
      listarTareas.mockReturnValueOnce(nuevoBoot.promesa)
      listarLeads.mockResolvedValueOnce([]) // el nuevo actor arranca sin leads conocidos

      montaje.rerenderAuth('vendedor', cambio === 'otro actor' ? {} : { id: 'u-ger' })

      expect(montaje.estado().cargando).toBe(true)
      expect(montaje.api().ambito.leads).toEqual([])
      expect(montaje.panelState().leadAbiertoId).toBeNull()
      expect(obtenerLeadPorId.mock.calls[0]?.[1]?.aborted).toBe(true)
      // Tampoco se permite abrir una fila del caché de la identidad anterior
      // mientras se determina el nuevo ámbito real.
      expect(await abrir(montaje, leadBase().id)).toBe(false)
      await act(async () => {
        nuevoBoot.resolver([])
        lectura.resolver(filaA())
        expect(await apertura).toBe(false)
      })
      await waitFor(() => expect(montaje.estado().cargando).toBe(false))
      expect(montaje.api().leads).toEqual([])
      expect(montaje.panelState().leadAbiertoId).toBeNull()
    })

    it('termina la apertura y aborta la lectura si el servidor no responde', async () => {
      const lectura = diferida<LecturaLead>()
      obtenerLeadPorId.mockReturnValueOnce(lectura.promesa)
      const montaje = montar()
      await waitFor(() => expect(montaje.estado().cargando).toBe(false))
      vi.useFakeTimers()
      try {
        let apertura!: ReturnType<PanelesActions['abrirLead']>
        act(() => { apertura = montaje.panelActions().abrirLead(ID_A) })
        await act(async () => {
          await vi.advanceTimersByTimeAsync(LIMITE_CARGA_REAL_MS)
          expect(await apertura).toBe(false)
        })
        expect(obtenerLeadPorId.mock.calls[0]?.[1]?.aborted).toBe(true)
        expect(montaje.panelState().leadAbiertoId).toBeNull()
        await act(async () => { lectura.resolver(filaA()) })
        expect(montaje.api().lead(ID_A)).toBeUndefined()
      } finally {
        vi.useRealTimers()
      }
    })

    it('respeta las filas que RLS autoriza a un supervisor por descendencia recursiva', async () => {
      listarEquipo.mockResolvedValueOnce([
        ...ROSTER,
        { perfil_id: 'u-s2', nombre_completo: 'Supervisor Descendiente', rol_crm: 'supervisor', supervisor_id: 'u-s1', activo: true },
        { perfil_id: 'u-v2', nombre_completo: 'Analista Descendiente', rol_crm: 'vendedor', supervisor_id: 'u-s2', activo: true },
      ])
      listarLeads.mockResolvedValueOnce([
        { ...filaA(), vendedor_id: 'u-v2' },
        { ...filaB(), vendedor_id: null, asignado_supervisor_id: 'u-s2' },
        { ...leadBase(), activo: false },
      ])
      const montaje = montar('supervisor')
      await waitFor(() => expect(montaje.estado().cargando).toBe(false))

      expect(montaje.api().ambito.leads.map((l) => l.id)).toEqual([ID_A, ID_B])
      expect(montaje.api().ambito.vendedores.map((m) => m.perfil_id)).toContain('u-v2')
      expect(montaje.api().lead(ID_A)?.vendedor_nombre).toBe('Analista Descendiente')
      // Fase 4e: abrir siempre relee por id (una fila por apertura).
      obtenerLeadPorId.mockResolvedValueOnce({ ...filaA(), vendedor_id: 'u-v2' })
      expect(await abrir(montaje, ID_A)).toBe(true)
      obtenerLeadPorId.mockResolvedValueOnce({ ...filaB(), vendedor_id: null, asignado_supervisor_id: 'u-s2' })
      expect(await abrir(montaje, ID_B)).toBe(true)
      expect(obtenerLeadPorId).toHaveBeenCalledTimes(2)
    })

    it('asegurarLead relee por id, registra la fila y descarta una respuesta tardía de otra identidad (Fase 4e)', async () => {
      const montaje = montar()
      await waitFor(() => expect(montaje.estado().cargando).toBe(false))
      // La misma referencia entre cambios del store: los efectos de registro
      // de las pantallas no se re-disparan con cada mutación (Codex 20/09).
      const conocer = montaje.api().conocerLeads
      obtenerLeadPorId.mockResolvedValueOnce(filaA())
      let ok!: boolean
      await act(async () => { ok = await montaje.api().asegurarLead(ID_A) })
      expect(ok).toBe(true)
      expect(montaje.api().lead(ID_A)).toMatchObject({ id: ID_A, vendedor_nombre: 'Analista Real' })
      expect(montaje.api().conocerLeads).toBe(conocer)

      // Revocado: deja de ser conocido.
      obtenerLeadPorId.mockResolvedValueOnce(null)
      await act(async () => { ok = await montaje.api().asegurarLead(ID_A) })
      expect(ok).toBe(false)
      expect(montaje.api().lead(ID_A)).toBeUndefined()

      // Lectura en vuelo como gerencia; cambia la identidad; la respuesta tardía no entra.
      const lectura = diferida<LecturaLead>()
      obtenerLeadPorId.mockReturnValueOnce(lectura.promesa)
      let tardia!: Promise<boolean>
      act(() => { tardia = montaje.api().asegurarLead(ID_B) })
      listarLeads.mockResolvedValueOnce([])
      montaje.rerenderAuth('vendedor')
      await waitFor(() => expect(montaje.estado().cargando).toBe(false))
      await act(async () => { lectura.resolver(filaB()); expect(await tardia).toBe(false) })
      expect(montaje.api().lead(ID_B)).toBeUndefined()
    })

    it('resync conserva la ficha fuera del boot con una fila fresca y revalidada', async () => {
      obtenerLeadPorId.mockResolvedValueOnce(filaA())
      const montaje = montar()
      await waitFor(() => expect(montaje.estado().cargando).toBe(false))
      expect(await abrir(montaje, ID_A)).toBe(true)
      listarLeads.mockResolvedValueOnce([leadBase()])
      const fresca = { ...filaA(), nota: 'Nota modificada por otro operador', monto_estimado: 9000 }
      obtenerLeadPorId.mockResolvedValueOnce(fresca)
      listarEquipo.mockResolvedValueOnce(ROSTER.map((m) => m.perfil_id === 'u-v1' ? { ...m, nombre_completo: 'Analista actualizado' } : m))

      await act(async () => { expect(await montaje.api().recargar()).toBe(true) })

      expect(obtenerLeadPorId).toHaveBeenCalledTimes(2)
      expect(obtenerLeadPorId.mock.calls[1]?.[0]).toBe(ID_A)
      expect(montaje.api().lead(ID_A)).toMatchObject({ ...fresca, vendedor_nombre: 'Analista actualizado' })
      expect(montaje.panelState().leadAbiertoId).toBe(ID_A)
    })

    it('una ficha abierta fuera del boot también resuelve cargado_por_nombre con el roster', async () => {
      obtenerLeadPorId.mockResolvedValueOnce({ ...filaA(), procedencia: 'manual', cargado_por: 'u-v1' })
      const montaje = montar()
      await waitFor(() => expect(montaje.estado().cargando).toBe(false))
      expect(await abrir(montaje, ID_A)).toBe(true)
      expect(montaje.api().lead(ID_A)).toMatchObject({ procedencia: 'manual', cargado_por: 'u-v1', cargado_por_nombre: 'Analista Real' })
    })

    it('resync elimina una ficha abierta cuyo acceso fue revocado', async () => {
      obtenerLeadPorId.mockResolvedValueOnce(filaA())
      const montaje = montar()
      await waitFor(() => expect(montaje.estado().cargando).toBe(false))
      expect(await abrir(montaje, ID_A)).toBe(true)
      listarLeads.mockResolvedValueOnce([leadBase()])
      obtenerLeadPorId.mockResolvedValueOnce(null)

      await act(async () => { expect(await montaje.api().recargar()).toBe(true) })

      expect(obtenerLeadPorId).toHaveBeenCalledTimes(2)
      expect(montaje.api().lead(ID_A)).toBeUndefined()
      expect(montaje.api().ambito.leads.map((l) => l.id)).toEqual([leadBase().id])
      expect(await abrir(montaje, ID_A)).toBe(false)
      expect(montaje.api().lead(ID_A)).toBeUndefined()
    })

    it('una revalidación lenta de A no borra B abierta mientras viajaba el resync', async () => {
      obtenerLeadPorId.mockResolvedValueOnce(filaA())
      const montaje = montar()
      await waitFor(() => expect(montaje.estado().cargando).toBe(false))
      expect(await abrir(montaje, ID_A)).toBe(true)
      const revalidacionA = diferida<LecturaLead>()
      listarLeads.mockResolvedValueOnce([leadBase()])
      obtenerLeadPorId.mockReturnValueOnce(revalidacionA.promesa).mockResolvedValueOnce(filaB())
      let recarga!: Promise<boolean>
      act(() => { recarga = montaje.api().recargar() })
      await waitFor(() => expect(obtenerLeadPorId).toHaveBeenCalledTimes(2))

      expect(await abrir(montaje, ID_B)).toBe(true)
      await act(async () => {
        revalidacionA.resolver(filaA())
        await recarga
      })

      expect(montaje.panelState().leadAbiertoId).toBe(ID_B)
      expect(montaje.api().lead(ID_B)).toMatchObject(filaB())
      expect(montaje.api().ambito.leads.map((l) => l.id)).toContain(ID_B)
    })
  })

  it('Gerencia carga el ámbito operativo completo además del roster y las metas', async () => {
    const { api, estado } = montar('gerencia')

    await waitFor(() => expect(estado().cargando).toBe(false))
    expect(api().equipo).toEqual(ROSTER)
    expect(api().leads).toHaveLength(1)
    expect(api().ambito.leads).toHaveLength(1)
    expect(api().actividades).toEqual([])
    expect(api().tareas).toEqual([])
    expect(listarEquipo).toHaveBeenCalledTimes(1)
    expect(obtenerMetasMock).toHaveBeenCalledTimes(1)
    expect(obtenerCumplimientoMock).toHaveBeenCalledTimes(1)
    expect(listarTareas).toHaveBeenCalledTimes(1)
    expect(listarTareas).toHaveBeenCalledTimes(1)
  })

  it('Gerencia conserva metas individuales reales y sus agregados con la carga operativa', async () => {
    const configuracion = configuracionMetas(420_000, 42_000, 18)
    obtenerMetasMock.mockResolvedValueOnce(configuracion)
    obtenerCumplimientoMock.mockResolvedValueOnce(cumplimientoMetas(210_000, 10_500, 50, configuracion))
    const { api, estado } = montar('gerencia')

    await waitFor(() => expect(estado().cargando).toBe(false))
    expect(api().objetivos.porVendedor?.['u-v1']).toMatchObject({
      vendedorId: 'u-v1',
      nombre: 'Analista Real',
      supervisorId: 'u-s1',
      conversionObjetivo: 18,
    })
    expect(api().objetivos.gerencia.detalles).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          categoria: 'nuevo',
          moneda: 'PEN',
          capitalObjetivo: 420_000,
        }),
        expect.objectContaining({
          categoria: 'nuevo',
          moneda: 'USD',
          capitalObjetivo: 42_000,
        }),
      ]),
    )
    expect(api().cumplimientoMetas).toMatchObject({
      fuentesReales: {
        capitalYContratos: 'contratos_confirmados',
        conversion: 'leads_resueltos',
      },
      // F3.3: el agregado ya no transporta conversión (la sirve el servidor);
      // aquí solo viajan la meta agregada y los reales de capital/contratos.
      gerencia: { conversionObjetivo: 18 },
    })
    expect('conversionReal' in (api().cumplimientoMetas?.gerencia ?? {})).toBe(false)
    expect(api().cumplimientoMetas?.gerencia?.detalles).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          categoria: 'nuevo',
          moneda: 'PEN',
          capitalReal: 210_000,
        }),
        expect.objectContaining({
          categoria: 'nuevo',
          moneda: 'USD',
          capitalReal: 10_500,
        }),
      ]),
    )
  })

  it('recargar Gerencia resincroniza roster, metas y fuentes operativas', async () => {
    const { api, estado } = montar('gerencia')
    await waitFor(() => expect(estado().cargando).toBe(false))
    vi.clearAllMocks()
    listarLeads.mockResolvedValue([leadBase()])
    listarTareas.mockResolvedValue([])
    listarEquipo.mockResolvedValue(ROSTER)
    obtenerMetasMock.mockResolvedValue(configuracionMetas())
    obtenerCumplimientoMock.mockResolvedValue(cumplimientoMetas())

    await act(async () => {
      expect(await api().recargar()).toBe(true)
    })

    expect(listarEquipo).toHaveBeenCalledTimes(1)
    expect(obtenerMetasMock).toHaveBeenCalledTimes(1)
    expect(obtenerCumplimientoMock).toHaveBeenCalledTimes(1)
    expect(listarTareas).toHaveBeenCalledTimes(1)
    expect(listarTareas).toHaveBeenCalledTimes(1)
  })

  it('al volver al foco incorpora un alta remota de roster y metas sin duplicar la carga', async () => {
    const { api, estado } = montar('gerencia')
    await waitFor(() => expect(estado().cargando).toBe(false))
    vi.clearAllMocks()

    const analistaNuevo = {
      perfil_id: 'u-v2',
      nombre_completo: 'Analista Remoto',
      rol_crm: 'vendedor' as const,
      supervisor_id: 'u-s1',
      activo: true,
    }
    const configuracionRemota = configuracionMetas(500_000, 50_000, 20)
    configuracionRemota.revision = 5
    configuracionRemota.vendedores.push({
      ...configuracionRemota.vendedores[0]!,
      vendedor_id: analistaNuevo.perfil_id,
      nombre: analistaNuevo.nombre_completo,
    })
    let resolverRoster!: (miembros: typeof ROSTER) => void
    listarEquipo.mockImplementationOnce(() => new Promise<typeof ROSTER>((resolve) => {
      resolverRoster = resolve
    }))
    obtenerMetasMock.mockResolvedValueOnce(configuracionRemota)
    obtenerCumplimientoMock.mockResolvedValueOnce(
      cumplimientoMetas(250_000, 25_000, 50, configuracionRemota),
    )

    act(() => {
      window.dispatchEvent(new Event('focus'))
      document.dispatchEvent(new Event('visibilitychange'))
      window.dispatchEvent(new Event('online'))
    })
    await waitFor(() => expect(listarEquipo).toHaveBeenCalledTimes(1))
    expect(obtenerMetasMock).toHaveBeenCalledTimes(1)
    expect(obtenerCumplimientoMock).toHaveBeenCalledTimes(1)
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.conversionMensualPrefijo(),
    })
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.cumplimientoMetasPrefijo(),
    })
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasConversionesEquipoPrefijo(),
    })

    await act(async () => {
      resolverRoster([...ROSTER, analistaNuevo])
    })

    await waitFor(() => expect(api().ambito.vendedores.map((fila) => fila.perfil_id)).toContain('u-v2'))
    expect(api().objetivos.porVendedor?.['u-v2']).toMatchObject({
      vendedorId: 'u-v2',
      nombre: 'Analista Remoto',
      conversionObjetivo: 20,
    })
    expect(api().cumplimientoMetas?.porVendedor['u-v2']).toMatchObject({
      vendedorId: 'u-v2',
      nombre: 'Analista Remoto',
    })
  })

  it('al reconectar elimina del ranking vigente una baja remota de roster y metas', async () => {
    const { api, estado } = montar('gerencia')
    await waitFor(() => expect(estado().cargando).toBe(false))
    expect(api().ambito.vendedores.map((fila) => fila.perfil_id)).toContain('u-v1')
    vi.clearAllMocks()

    const rosterRemoto = ROSTER.filter((miembro) => miembro.perfil_id !== 'u-v1')
    const configuracionRemota = configuracionMetas()
    configuracionRemota.revision = 6
    configuracionRemota.vendedores = []
    listarEquipo.mockResolvedValueOnce(rosterRemoto)
    obtenerMetasMock.mockResolvedValueOnce(configuracionRemota)
    obtenerCumplimientoMock.mockResolvedValueOnce(cumplimientoMetas(0, 0, null, configuracionRemota))

    act(() => {
      window.dispatchEvent(new Event('online'))
    })

    await waitFor(() => expect(api().ambito.vendedores.map((fila) => fila.perfil_id)).not.toContain('u-v1'))
    expect(api().objetivos.porVendedor?.['u-v1']).toBeUndefined()
    expect(api().cumplimientoMetas?.porVendedor['u-v1']).toBeUndefined()
    expect(listarEquipo).toHaveBeenCalledTimes(1)
    expect(obtenerMetasMock).toHaveBeenCalledTimes(1)
    expect(obtenerCumplimientoMock).toHaveBeenCalledTimes(1)
  })

  it('focus y reconnect no duplican una recarga explícita que ya está en vuelo', async () => {
    const { api, estado } = montar('gerencia')
    await waitFor(() => expect(estado().cargando).toBe(false))
    vi.clearAllMocks()

    let resolverRoster!: (miembros: typeof ROSTER) => void
    listarEquipo.mockImplementationOnce(() => new Promise<typeof ROSTER>((resolve) => {
      resolverRoster = resolve
    }))

    let recarga!: Promise<boolean>
    act(() => {
      recarga = api().recargar()
    })
    await waitFor(() => expect(listarEquipo).toHaveBeenCalledTimes(1))

    act(() => {
      window.dispatchEvent(new Event('focus'))
      window.dispatchEvent(new Event('online'))
    })
    expect(listarEquipo).toHaveBeenCalledTimes(1)
    expect(obtenerMetasMock).toHaveBeenCalledTimes(1)
    expect(obtenerCumplimientoMock).toHaveBeenCalledTimes(1)

    await act(async () => {
      resolverRoster(ROSTER)
      expect(await recarga).toBe(true)
    })
  })

  it('Directorio conserva la lectura de datos operativos sin heredar escritura', async () => {
    const { api, estado } = montar('directorio')

    await waitFor(() => expect(estado().cargando).toBe(false))
    expect(api().leads).toHaveLength(1)
    expect(listarTareas).toHaveBeenCalledTimes(1)
    expect(listarTareas).toHaveBeenCalledTimes(1)
  })

  it('Superadmin sin Gerencia arranca con store vacío sin consultar operación', async () => {
    const { api, estado } = montar('directorio', {
      rol_portal: 'superadmin',
      puede_contratar: false,
      capacidades_config: {
        puede_listar_usuarios: true,
        puede_administrar_usuarios: false,
        puede_organizar_jerarquia: false,
        puede_administrar_roles: true,
      },
    })

    await waitFor(() => expect(estado().cargando).toBe(false))
    expect(estado().error).toBe(false)
    expect(api().leads).toEqual([])
    expect(api().equipo).toEqual([])
    expect(listarTareas).not.toHaveBeenCalled()
    expect(listarEquipo).not.toHaveBeenCalled()
    expect(listarTareas).not.toHaveBeenCalled()
    expect(obtenerMetasMock).not.toHaveBeenCalled()
    expect(obtenerCumplimientoMock).not.toHaveBeenCalled()
  })

  it('Gerencia edita un lead de otro analista y persiste el cambio', async () => {
    const { api, mutar } = montar('gerencia')
    await waitFor(() => expect(api().leads).toHaveLength(1))

    const res = mutar((a) => a.editarLead(leadBase().id, { telefono: '999111222' }))

    expect(res).toMatchObject({ ok: true })
    expect(api().lead(leadBase().id)?.telefono).toBe('+51999111222')
    expect(editarLeadFn).toHaveBeenCalledWith(leadBase().id, expect.objectContaining({ telefono: '+51999111222' }))
  })

  it('actividad y siguiente reunión viajan en un solo comando con los campos normalizados', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const id = api().leads[0]!.id
    const resultado = mutar((a) => a.registrarActividad(id, 'llamada_realizada', 'Conversación', {
      tipo: 'reunion', titulo: '  Reunión segura  ', vence_en: '2026-07-19T15:00:00.000Z',
      modalidad_reunion: 'virtual', ubicacion_reunion: 'No corresponde', enlace_reunion: '  https://meet.google.com/abc-defg-hij  ',
    }))
    expect(resultado.ok).toBe(true)
    await expect(resultado.persistido).resolves.toBe(true)
    expect(comandoSla).toHaveBeenCalledTimes(1)
    expect(comandoSla).toHaveBeenCalledWith('u-s1', 'registrar_actividad_v2', id, {
      p_lead_id: id, p_tipo: 'llamada_realizada', p_detalle: 'Conversación',
      p_siguiente: { id: expect.any(String), tipo: 'reunion', titulo: 'Reunión segura', vence_en: '2026-07-19T15:00:00.000Z',
        modalidad_reunion: 'virtual', ubicacion_reunion: null, enlace_reunion: 'https://meet.google.com/abc-defg-hij' },
    })
    expect(insertarActividad).not.toHaveBeenCalled()
    expect(insertarTarea).not.toHaveBeenCalled()
  })

  it.each([undefined, '', '   '])('actividad sin detalle usa el valor predeterminado de la RPC: %j', async (detalle) => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const id = api().leads[0]!.id
    const resultado = mutar((a) => a.registrarActividad(id, 'whatsapp_enviado', detalle))
    expect(resultado.ok).toBe(true)
    await expect(resultado.persistido).resolves.toBe(true)
    expect(comandoSla).toHaveBeenCalledTimes(1)
    expect(comandoSla).toHaveBeenCalledWith('u-s1', 'registrar_actividad_v2', id, {
      p_lead_id: id, p_tipo: 'whatsapp_enviado', p_siguiente: null,
    })
    expect(comandoSla.mock.calls[0]![3]).not.toHaveProperty('p_detalle')
  })

  it('cambiar etapa y registrar actividad caducan las dos fotos de conversión por rango', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const id = api().leads[0]!.id

    invalidarQueriesMock.mockClear()
    expect(mutar((a) => a.cambiarEtapa(id, 'contactado'))).toMatchObject({ ok: true })
    await waitFor(() => expect(actualizarLead).toHaveBeenCalledWith(id, { etapa: 'contactado' }))
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasConversionesPrefijo(),
    })
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasConversionesEquipoPrefijo(),
    })

    invalidarQueriesMock.mockClear()
    expect(mutar((a) => a.registrarActividad(id, 'llamada_realizada', 'Contactó'))).toMatchObject({ ok: true })
    await waitFor(() => expect(comandoSla).toHaveBeenCalledWith('u-s1', 'registrar_actividad_v2', id, expect.objectContaining({ p_lead_id: id })))
    expect(insertarActividad).not.toHaveBeenCalled()
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasConversionesPrefijo(),
    })
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasConversionesEquipoPrefijo(),
    })
  })

  // Pipeline, 01/10/2026 — columna «Gestionado». Un INTENTO (no contestó,
  // WhatsApp enviado) no mueve la etapa: el lead sigue en `nuevo`. Pero sí
  // cambia de columna, de «Nuevo» a «Gestionado», y eso lo decide el servidor:
  // las dos son listas servidas bajo `crmQueryKeys.leads()`. Si este refresco
  // se perdiera, la tarjeta se quedaría en «Nuevo» hasta recargar la página.
  it.each([
    ['llamada_no_contestada', (a: StoreDataApi, id: string) => a.registrarActividad(id, 'llamada_no_contestada')],
    ['whatsapp_enviado', (a: StoreDataApi, id: string) => a.registrarActividad(id, 'whatsapp_enviado')],
    ['resultado «no contestó»', (a: StoreDataApi, id: string) => a.registrarLlamada(id, { resultado: 'no_contesto' })],
  ] as const)('registrar un intento (%s) deja la etapa en nuevo y vuelve a pedir las listas de leads', async (_caso, registrar) => {
    const { api, mutar } = montar('vendedor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const id = api().leads[0]!.id
    const escritura = diferida<undefined>()
    comandoSla.mockReturnValueOnce(escritura.promesa)
    const cancelarQueriesMock = vi.mocked(queryClient.cancelQueries)
    invalidarQueriesMock.mockClear()
    cancelarQueriesMock.mockClear()

    const r = mutar((a) => registrar(a, id))
    expect(r).toMatchObject({ ok: true })
    // Un intento no es una conversación: no hay avance de etapa que anunciar.
    expect(r).not.toHaveProperty('avance')
    // Mientras el servidor no confirma la escritura, las listas NO se vuelven a
    // pedir: releerlas ahora traería el lead todavía en «Nuevo».
    expect(invalidarQueriesMock).not.toHaveBeenCalledWith({ queryKey: crmQueryKeys.leads() })

    await act(async () => {
      escritura.resolver(undefined)
      expect(await r.persistido).toBe(true)
    })

    expect(api().lead(id)?.etapa).toBe('nuevo')
    await waitFor(() => expect(invalidarQueriesMock).toHaveBeenCalledWith({ queryKey: crmQueryKeys.leads() }))
    // CANCELAR ANTES de invalidar, y en ese orden: una página de «Nuevo» o de
    // «Gestionado» que ya viajaba traería la foto anterior a la gestión y la
    // dejaría fresca en caché. (Que las dos listas cuelgan de `leads()` lo fija
    // crm-queries.test; aquí importa que el prefijo se cancele y se caduque.)
    const ordenDe = (mock: { mock: { calls: unknown[][]; invocationCallOrder: number[] } }) =>
      mock.mock.invocationCallOrder[mock.mock.calls.findIndex(([arg]) =>
        JSON.stringify((arg as { queryKey?: unknown }).queryKey) === JSON.stringify(crmQueryKeys.leads()))]
    expect(ordenDe(cancelarQueriesMock)).toEqual(expect.any(Number))
    expect(ordenDe(cancelarQueriesMock)!).toBeLessThan(ordenDe(invalidarQueriesMock)!)
  })

  // Regla del 01/10: un resultado de llamada DESHECHO deja de contar y el lead
  // vuelve de «Gestionado» a «Nuevo». También lo decide el servidor: «Deshacer»
  // tiene que volver a pedir las listas, o la tarjeta no regresaría sola.
  it('deshacer el resultado de una llamada vuelve a pedir las listas de leads tras confirmarse', async () => {
    const { api, mutar } = montar('vendedor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const id = api().leads[0]!.id
    const deshecho = diferida<{ lead_id: string }>()
    deshacerLlamadaMock.mockReturnValueOnce(deshecho.promesa as never)
    invalidarQueriesMock.mockClear()

    const r = mutar((a) => a.deshacerResultadoLlamada('act-1'))
    expect(r).toMatchObject({ ok: true })
    expect(deshacerLlamadaMock).toHaveBeenCalledWith('act-1')
    expect(invalidarQueriesMock).not.toHaveBeenCalledWith({ queryKey: crmQueryKeys.leads() })

    await act(async () => {
      deshecho.resolver({ lead_id: id })
      expect(await r.persistido).toBe(true)
    })

    await waitFor(() => expect(invalidarQueriesMock).toHaveBeenCalledWith({ queryKey: crmQueryKeys.leads() }))
  })

  it('expone las metas en solo lectura; la escritura vive únicamente en Configuración', async () => {
    const { api, estado } = montar('gerencia')
    await waitFor(() => expect(estado().cargando).toBe(false))

    expect('fijarObjetivos' in api()).toBe(false)
    expect(obtenerMetasMock).toHaveBeenCalledWith(expect.stringMatching(/^\d{4}-\d{2}-01$/), expect.any(AbortSignal))
  })

  it('el gate de acciones está ABIERTO: crearLead persiste y resincroniza', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))

    const res = mutar((a) =>
      a.crearLead({
        nombre_completo: 'LEAD NUEVO REAL',
        telefono: '987654321',
        origen: 'formulario',
        monto_estimado: 5000,
        moneda: 'PEN',
        vendedor_id: 'u-v1',
      }),
    )

    expect(res.ok).toBe(true)
    expect(res.codigo).toBeUndefined() // NO 'fuente_no_habilitada'
    expect(insertarLead).toHaveBeenCalledTimes(1)
    expect(insertarLead).toHaveBeenCalledWith(expect.objectContaining({ monto_estimado: 5000, moneda: 'PEN' }))
    await expect(res.persistido).resolves.toEqual({ ok: true })
    await waitFor(() => expect(listarTareas).toHaveBeenCalledTimes(2)) // resync
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.conversionMensualPrefijo(),
    })
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasConversionesPrefijo(),
    })
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasConversionesEquipoPrefijo(),
    })
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.cumplimientoMetasPrefijo(),
    })
  })

  it('cambiar el origen y reasignar caducan los tres núcleos; editar otro campo no', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const id = api().leads[0]!.id

    invalidarQueriesMock.mockClear()
    const edicionComun = mutar((a) => a.editarLead(id, { nota: 'Dato que no cambia atribución' }))
    expect(edicionComun).toMatchObject({ ok: true })
    await waitFor(() => expect(editarLeadFn).toHaveBeenCalledWith(id, expect.objectContaining({ nota: 'Dato que no cambia atribución' })))
    expect(invalidarQueriesMock).not.toHaveBeenCalledWith({
      queryKey: crmQueryKeys.conversionMensualPrefijo(),
    })
    expect(invalidarQueriesMock).not.toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasConversionesPrefijo(),
    })
    expect(invalidarQueriesMock).not.toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasConversionesEquipoPrefijo(),
    })
    expect(invalidarQueriesMock).not.toHaveBeenCalledWith({
      queryKey: crmQueryKeys.cumplimientoMetasPrefijo(),
    })

    invalidarQueriesMock.mockClear()
    const cambioOrigen = mutar((a) => a.editarLead(id, { origen: 'referido' }))
    expect(cambioOrigen).toMatchObject({ ok: true })
    await waitFor(() => expect(editarLeadFn).toHaveBeenCalledWith(id, expect.objectContaining({ origen: 'referido' })))
    for (const queryKey of [
      crmQueryKeys.conversionMensualPrefijo(),
      crmQueryKeys.metricasConversionesPrefijo(),
      crmQueryKeys.metricasConversionesEquipoPrefijo(),
      crmQueryKeys.cumplimientoMetasPrefijo(),
      crmQueryKeys.metricasReunionesPrefijo(),
    ]) {
      expect(invalidarQueriesMock).toHaveBeenCalledWith({ queryKey })
    }

    invalidarQueriesMock.mockClear()
    const reasignacion = mutar((a) => a.reasignar(id, null))
    expect(reasignacion).toMatchObject({ ok: true })
    await waitFor(() => expect(actualizarLead).toHaveBeenCalledWith(id, {
      vendedor_id: null,
      asignado_supervisor_id: 'u-s1',
    }))
    for (const queryKey of [
      crmQueryKeys.conversionMensualPrefijo(),
      crmQueryKeys.metricasConversionesPrefijo(),
      crmQueryKeys.metricasConversionesEquipoPrefijo(),
      crmQueryKeys.cumplimientoMetasPrefijo(),
      crmQueryKeys.metricasReunionesPrefijo(),
    ]) {
      expect(invalidarQueriesMock).toHaveBeenCalledWith({ queryKey })
    }
  })

  it('crearLead expone el rechazo sanitizado del INSERT para no anunciar un falso éxito', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    insertarLead.mockRejectedValueOnce(
      new CrmApiError('Este contacto acaba de ser registrado por otro usuario', 'CONTACTO_RECIEN_REGISTRADO'),
    )

    const res = mutar((a) =>
      a.crearLead({
        nombre_completo: 'CARRERA DE ALTA',
        telefono: '987654324',
        origen: 'formulario',
        monto_estimado: 5000,
        moneda: 'PEN',
        vendedor_id: 'u-v1',
      }),
    )

    expect(res.ok).toBe(true)
    await expect(res.persistido).resolves.toEqual({
      ok: false,
      error: 'Este contacto acaba de ser registrado por otro usuario',
      codigo: 'CONTACTO_RECIEN_REGISTRADO',
    })
    await waitFor(() => {
      expect(api().leads.some((lead) => lead.nombre_completo === 'CARRERA DE ALTA')).toBe(false)
    })
    expect(toast.error).not.toHaveBeenCalled()
  })

  it('la RPC puede bloquear después del precheck y revierte el lead optimista', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    insertarLead.mockResolvedValueOnce({
      estado: 'tomado',
      vendedor: 'OTRO ANALISTA',
      tenencia_desde: '2026-08-04T12:30:00.000Z',
    })

    const res = mutar((a) =>
      a.crearLead({
        nombre_completo: 'BLOQUEADO POR RPC',
        telefono: '987654325',
        origen: 'formulario',
        monto_estimado: 5000,
        moneda: 'PEN',
        vendedor_id: 'u-v1',
      }),
    )

    expect(res.ok).toBe(true)
    await expect(res.persistido).resolves.toMatchObject({
      ok: false,
      codigo: 'CONTACTO_NO_DISPONIBLE',
    })
    await waitFor(() => {
      expect(api().leads.some((lead) => lead.nombre_completo === 'BLOQUEADO POR RPC')).toBe(false)
    })
    expect(toast.success).not.toHaveBeenCalled()
  })

  it('rechaza una confirmación con otro lead_id y revierte el optimista', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    insertarLead.mockResolvedValueOnce({
      estado: 'creado',
      lead_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    })

    const res = mutar((a) =>
      a.crearLead({
        nombre_completo: 'IDENTIDAD INESPERADA',
        telefono: '987654326',
        origen: 'formulario',
        monto_estimado: 5000,
        moneda: 'PEN',
        vendedor_id: 'u-v1',
      }),
    )

    expect(res.ok).toBe(true)
    await expect(res.persistido).resolves.toMatchObject({
      ok: false,
      codigo: 'CREACION_LEAD_CONTRACT',
    })
    await waitFor(() => {
      expect(api().leads.some((lead) => lead.nombre_completo === 'IDENTIDAD INESPERADA')).toBe(false)
    })
  })

  it('género y fecha de nacimiento llegan al INSERT (si no, el avatar nunca tiene silueta)', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))

    const res = mutar((a) =>
      a.crearLead({
        nombre_completo: 'LEAD CON GÉNERO',
        telefono: '987654322',
        origen: 'formulario',
        monto_estimado: 5000,
        moneda: 'PEN',
        vendedor_id: 'u-v1',
        genero: 'F',
        fecha_nacimiento: '1990-05-20',
      }),
    )

    expect(res.ok).toBe(true)
    expect(insertarLead).toHaveBeenCalledWith(expect.objectContaining({ genero: 'F', fecha_nacimiento: '1990-05-20' }))
    // Y el optimista los muestra sin esperar al resync.
    expect(api().leads[0]).toMatchObject({
      genero: 'F',
      fecha_nacimiento: '1990-05-20',
    })
  })

  it('un lead menor de edad NO se crea ni se persiste', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    insertarLead.mockClear()

    const res = mutar((a) =>
      a.crearLead({
        nombre_completo: 'MENOR',
        telefono: '987654323',
        origen: 'formulario',
        monto_estimado: 5000,
        moneda: 'PEN',
        vendedor_id: 'u-v1',
        fecha_nacimiento: '2020-01-01',
      }),
    )

    expect(res).toMatchObject({
      ok: false,
      codigo: 'menor_de_edad',
      campo: 'fecha_nacimiento',
    })
    expect(insertarLead).not.toHaveBeenCalled()
  })

  it('crearTarea agenda de verdad: optimista + INSERT + agenda derivada', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const leadId = api().leads[0]!.id

    const res = mutar((a) =>
      a.crearTarea({
        lead_id: leadId,
        tipo: 'llamada',
        titulo: 'Llamar a CLIENTE EXISTENTE',
        vence_en: '2027-01-05T15:00:00.000Z',
      }),
    )

    expect(res.ok).toBe(true)
    expect(insertarTarea).toHaveBeenCalledTimes(1)
    expect(insertarTarea).toHaveBeenCalledWith(
      expect.objectContaining({
        lead_id: leadId,
        tipo: 'llamada',
        titulo: 'Llamar a CLIENTE EXISTENTE',
        vence_en: '2027-01-05T15:00:00.000Z',
        creado_por: 'u-s1',
      }),
    )
    // Optimista: la tarea ya vive en el store y la agenda derivada la pinta
    // con la tenencia del lead (espejo del trigger del servidor).
    expect(api().tareas[0]).toMatchObject({
      lead_id: leadId,
      estado: 'pendiente',
      vendedor_id: 'u-v1',
    })
    expect(api().agenda.some((ev) => ev.titulo === 'Llamar a CLIENTE EXISTENTE')).toBe(true)
    expect(api().tareasDe(leadId)).toHaveLength(1)
    await expect(res.persistido).resolves.toBe(true)
    await waitFor(() => expect(listarTareas).toHaveBeenCalled()) // resync
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasAgendaPrefijo(),
    })
    expect(invalidarQueriesMock).not.toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasReunionesPrefijo(),
    })
  })

  it('crearTarea permite gestionar un cliente de cartera mediante perfil_id', async () => {
    const clienteId = '99999999-9999-4999-8999-999999999999'
    const { api, mutar } = montar('vendedor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    insertarTarea.mockClear()

    const res = mutar((a) =>
      a.crearTarea({
        perfil_id: clienteId,
        tipo: 'reunion',
        titulo: 'Reunión con Rosa',
        vence_en: '2027-01-05T15:00:00.000Z',
        modalidad_reunion: 'presencial',
        ubicacion_reunion: 'Oficina Avance',
      }),
    )

    expect(res.ok).toBe(true)
    expect(insertarTarea).toHaveBeenCalledWith(
      expect.objectContaining({
        perfil_id: clienteId,
        tipo: 'reunion',
        creado_por: 'u-v1',
      }),
    )
    expect(insertarTarea.mock.calls[0]?.[0]).not.toHaveProperty('lead_id')
    expect(api().tareas.find((t) => t.id === res.id)).toMatchObject({
      lead_id: null,
      perfil_id: clienteId,
      vendedor_id: 'u-v1',
    })
    expect(api().tareasDeCliente?.(clienteId)).toHaveLength(1)
    await expect(res.persistido).resolves.toBe(true)
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasAgendaPrefijo(),
    })
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasReunionesPrefijo(),
    })
  })

  it('la ficha de cliente conserva el seguimiento neutral de todos sus perfiles enlazados', async () => {
    const perfil = '99999999-9999-4999-8999-999999999999'
    const tarea = {
      id: '22222222-2222-4222-8222-222222222222', lead_id: null, perfil_id: null,
      inversionista_id: '33333333-3333-4333-8333-333333333333', postventa_revision: 1,
      postventa_perfil_ids: [perfil], vendedor_id: 'u-v1', asignado_supervisor_id: null,
      tipo: 'llamada' as const, titulo: 'Seguimiento neutral', vence_en: '2027-01-05T15:00:00.000Z',
      estado: 'pendiente' as const, reprogramaciones: 0, activo: true, creado_en: '2026-09-10T15:00:00.000Z',
    }
    listarTareas.mockResolvedValue([tarea])
    const {api} = montar('vendedor')
    await waitFor(() => expect(api().tareasDeCliente?.(perfil)).toEqual([tarea]))
    expect(api().tareasDeCliente?.('otro-perfil')).toEqual([])
    expect(api().tareas[0]?.perfil_id).toBeNull()
  })

  it('crearTarea expone el rechazo remoto y resincroniza la fila optimista', async () => {
    const clienteId = '99999999-9999-4999-8999-999999999999'
    insertarTarea.mockRejectedValueOnce(new CrmApiError('El cliente está inactivo', 'CLIENTE_INACTIVO'))
    const { api, mutar } = montar('vendedor')
    await waitFor(() => expect(api().leads).toHaveLength(1))

    const res = mutar((a) =>
      a.crearTarea({
        perfil_id: clienteId,
        tipo: 'llamada',
        titulo: 'Llamar a Rosa',
        vence_en: '2027-01-05T15:00:00.000Z',
      }),
    )

    expect(res.ok).toBe(true)
    expect(api().tareas.some((t) => t.id === res.id)).toBe(true)
    await expect(res.persistido).resolves.toBe(false)
    await waitFor(() => expect(api().tareas.some((t) => t.id === res.id)).toBe(false))
    await waitFor(() =>
      expect(toast.error).toHaveBeenCalledWith('El cliente está inactivo — se actualizó la vista con el estado del servidor'),
    )
  })

  it('crearTarea valida y normaliza la reunión antes del optimista y del INSERT real', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const leadId = api().leads[0]!.id
    insertarTarea.mockClear()

    const invalida = mutar((a) =>
      a.crearTarea({
        lead_id: leadId,
        tipo: 'reunion',
        titulo: 'Enlace manipulado',
        vence_en: '2027-01-05T15:00:00.000Z',
        modalidad_reunion: 'virtual',
        enlace_reunion: 'http://meet.example.com/sala',
      }),
    )
    expect(invalida).toMatchObject({
      ok: false,
      codigo: 'enlace_reunion_invalido',
    })
    expect(insertarTarea).not.toHaveBeenCalled()

    const valida = mutar((a) =>
      a.crearTarea({
        lead_id: leadId,
        tipo: 'reunion',
        titulo: 'Reunión virtual segura',
        vence_en: '2027-01-05T15:00:00.000Z',
        modalidad_reunion: 'virtual',
        ubicacion_reunion: 'Campo incompatible inyectado',
        enlace_reunion: '  https://meet.google.com/abc-defg-hij  ',
      }),
    )

    expect(valida.ok).toBe(true)
    expect(api().tareas.find((t) => t.id === valida.id)).toMatchObject({
      modalidad_reunion: 'virtual',
      ubicacion_reunion: null,
      enlace_reunion: 'https://meet.google.com/abc-defg-hij',
    })
    expect(insertarTarea).toHaveBeenCalledWith(
      expect.objectContaining({
        modalidad_reunion: 'virtual',
        ubicacion_reunion: null,
        enlace_reunion: 'https://meet.google.com/abc-defg-hij',
      }),
    )
  })

  it('crearTarea rechaza tipo inválido y lead fuera del ámbito, sin tocar la red', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    insertarTarea.mockClear()

    const tipoMalo = mutar((a) =>
      a.crearTarea({
        lead_id: api().leads[0]!.id,
        tipo: 'email',
        titulo: 'X',
        vence_en: '2027-01-05T15:00:00.000Z',
      }),
    )
    expect(tipoMalo.ok).toBe(false)

    const fantasma = mutar((a) =>
      a.crearTarea({
        lead_id: 'no-existe',
        tipo: 'llamada',
        titulo: 'X',
        vence_en: '2027-01-05T15:00:00.000Z',
      }),
    )
    expect(fantasma).toMatchObject({ ok: false, codigo: 'no_encontrado' })
    expect(insertarTarea).not.toHaveBeenCalled()
  })

  it.each([
    ['tarea', false],
    ['actividad', false],
    ['tarea', true],
  ] as const)('una llamada desde %s refresca las primeras lecturas SLA sin duplicar gestión (rechazo: %s)', async (origen, rechazar) => {
    const cliente = new QueryClient({ defaultOptions: { queries: { retry: false, staleTime: 30_000 } } })
    invalidarQueriesMock.mockImplementation((filtros, opciones) => cliente.invalidateQueries(filtros, opciones))
    vi.mocked(queryClient.cancelQueries).mockImplementation((filtros, opciones) => cliente.cancelQueries(filtros, opciones))
    const lead = leadBase()
    const tarea = {
      id: '22222222-2222-4222-8222-222222222222', lead_id: lead.id, perfil_id: null,
      vendedor_id: 'u-v1', asignado_supervisor_id: null, tipo: 'llamada' as const,
      titulo: 'Llamada inicial', vence_en: '2026-07-18T15:00:00.000Z',
      estado: 'pendiente' as const, reprogramaciones: 0, activo: true,
      creado_en: '2026-07-17T15:00:00.000Z',
    }
    listarTareas.mockResolvedValue([tarea])
    const { api, mutar } = montar('vendedor')
    await waitFor(() => expect(api().tareas).toHaveLength(1))
    const escritura = diferida<void>()
    const respuestaAntigua = diferida<void>()
    let guardado = false
    comandoSla.mockImplementation(async () => {
      await escritura.promesa
      if (rechazar) throw new CrmApiError('No se pudo guardar la llamada', 'P0409')
      guardado = true
      if (origen === 'tarea') listarTareas.mockResolvedValue([{ ...tarea, estado: 'completada' }])
    })
    const claves = [
      slaOperacionKeys.estado('u-v1', [lead.id]),
      slaOperacionKeys.cola('u-v1', { senal: 'primera_atencion', etapa: null, analista_id: null }, null, 10),
      slaOperacionKeys.avisos('u-v1'),
    ]
    // QueryClient y observadores reales: las tres respuestas se capturan ANTES
    // de guardar, pero llegan DESPUÉS. Sin cancelación, invalidateQueries
    // reutiliza esas primeras peticiones y la llamada sigue como pendiente.
    const observadores = claves.map((queryKey) => new QueryObserver(cliente, {
      queryKey,
      queryFn: async ({ signal }) => {
        const foto = { primera_atencion: !guardado }
        if (!guardado) await respuestaAntigua.promesa
        void signal
        return foto
      },
    }))
    const desuscribir = observadores.map((observador) => observador.subscribe(() => undefined))
    try {
      expect(claves.every((clave) => cliente.getQueryState(clave)?.fetchStatus === 'fetching')).toBe(true)
      const res = mutar((acciones) => origen === 'tarea'
        ? acciones.completarTarea({ tarea_id: tarea.id, estado: 'completada', resultado_tipo: 'llamada_realizada' })
        : acciones.registrarActividad(lead.id, 'llamada_realizada'))
      expect(res.ok).toBe(true)
      expect(claves.every((clave) => cliente.getQueryData(clave) === undefined)).toBe(true)
      await act(async () => {
        escritura.resolver()
        expect(await res.persistido).toBe(!rechazar)
        respuestaAntigua.resolver()
      })
      await waitFor(() => {
        for (const clave of claves) expect(cliente.getQueryData(clave)).toEqual({ primera_atencion: rechazar })
      })
      expect(comandoSla).toHaveBeenCalledTimes(1)
      expect(comandoSla.mock.calls[0]?.[1]).toBe(origen === 'tarea' ? 'cerrar_tarea_v2' : 'registrar_actividad_v2')
      expect(insertarActividad).not.toHaveBeenCalled()
    } finally {
      escritura.resolver()
      respuestaAntigua.resolver()
      desuscribir.forEach((cancelar) => cancelar())
      cliente.clear()
    }
  })

  it('completarTarea: llamada exige resultado 1-tap; con él cierra por la RPC atómica y agenda la siguiente', async () => {
    const tareaBase = {
      id: '22222222-2222-4222-8222-222222222222',
      lead_id: '11111111-1111-4111-8111-111111111111',
      perfil_id: null,
      vendedor_id: 'u-v1',
      asignado_supervisor_id: null,
      tipo: 'llamada' as const,
      titulo: 'Llamar a CLIENTE',
      nota: null,
      vence_en: '2026-07-18T15:00:00.000Z',
      duracion_min: null,
      estado: 'pendiente' as const,
      confirmada_en: null,
      reagendada_de: null,
      reprogramaciones: 0,
      activo: true,
      creado_en: '2026-07-17T15:00:00.000Z',
    }
    listarTareas.mockResolvedValue([tareaBase])
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().tareas).toHaveLength(1))

    // Sin resultado → bloqueada (patrón Outreach) y la RPC no se toca.
    const sinResultado = mutar((a) => a.completarTarea({ tarea_id: tareaBase.id, estado: 'completada' }))
    expect(sinResultado).toMatchObject({
      ok: false,
      codigo: 'resultado_obligatorio',
    })
    expect(cerrarTareaMock).not.toHaveBeenCalled()

    // Con resultado + siguiente: optimista + RPC con el payload completo.
    const res = mutar((a) =>
      a.completarTarea({
        tarea_id: tareaBase.id,
        estado: 'completada',
        resultado_tipo: 'llamada_no_contestada',
        siguiente: {
          tipo: 'whatsapp',
          titulo: 'WhatsApp a CLIENTE',
          vence_en: '2026-07-19T15:00:00.000Z',
        },
      }),
    )
    expect(res.ok).toBe(true)
    expect(res.siguiente_id).toBeDefined()
    expect(comandoSla).toHaveBeenCalledWith('u-s1', 'cerrar_tarea_v2', tareaBase.id, {
      p_tarea_id: tareaBase.id,
      p_estado: 'completada',
      p_resultado_tipo: 'llamada_no_contestada',
      p_resultado_detalle: null,
      p_resultado_reunion: null,
      p_motivo_no_realizada: null,
      p_siguiente: {
        id: expect.any(String), tipo: 'whatsapp', titulo: 'WhatsApp a CLIENTE',
        vence_en: '2026-07-19T15:00:00.000Z', modalidad_reunion: null,
        ubicacion_reunion: null, enlace_reunion: null,
      },
    }, tareaBase)
    expect(cerrarTareaMock).not.toHaveBeenCalled()

    // Optimista: la original cerrada, la siguiente pendiente, y el resultado ya en el timeline.
    expect(api().tareas.find((t) => t.id === tareaBase.id)?.estado).toBe('completada')
    expect(api().tareas.some((t) => t.titulo === 'WhatsApp a CLIENTE' && t.estado === 'pendiente')).toBe(true)
    expect(api().actividades.some((a2) => a2.tipo === 'llamada_no_contestada')).toBe(true)
    await expect(res.persistido).resolves.toBe(true)
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasAgendaPrefijo(),
    })
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasConversionesPrefijo(),
    })
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasConversionesEquipoPrefijo(),
    })
  })

  it('una reunión de cliente se cierra por cerrar_tarea, conserva perfil_id y no altera el timeline de leads', async () => {
    const clienteId = '99999999-9999-4999-8999-999999999999'
    const tareaCliente = {
      id: '88888888-8888-4888-8888-888888888888',
      lead_id: null,
      perfil_id: clienteId,
      vendedor_id: 'u-v1',
      asignado_supervisor_id: null,
      tipo: 'reunion' as const,
      titulo: 'Reunión con Rosa',
      nota: null,
      vence_en: '2026-08-24T15:00:00.000Z',
      duracion_min: 45,
      modalidad_reunion: 'presencial' as const,
      ubicacion_reunion: 'Oficina Avance',
      enlace_reunion: null,
      estado: 'pendiente' as const,
      confirmada_en: null,
      resultado_reunion: null,
      motivo_no_realizada: null,
      detalle_cierre_reunion: null,
      reagendada_de: null,
      reprogramaciones: 0,
      activo: true,
      creado_en: '2026-08-20T15:00:00.000Z',
    }
    listarTareas.mockResolvedValue([tareaCliente])
    const { api, mutar } = montar('vendedor')
    await waitFor(() => expect(api().tareas).toHaveLength(1))

    const res = mutar((a) =>
      a.completarTarea({
        tarea_id: tareaCliente.id,
        estado: 'completada',
        resultado_tipo: 'reunion_realizada',
        resultado_reunion: 'interesado',
        resultado_detalle: 'Solicitó propuesta de upgrade',
        siguiente: {
          tipo: 'whatsapp',
          titulo: 'Enviar propuesta a Rosa',
          vence_en: '2026-08-25T15:00:00.000Z',
        },
      }),
    )

    expect(res.ok).toBe(true)
    await expect(res.persistido).resolves.toBe(true)
    expect(cerrarReunionMock).not.toHaveBeenCalled()
    expect(cerrarTareaMock).toHaveBeenCalledWith(
      expect.objectContaining({
        tarea_id: tareaCliente.id,
        resultado_tipo: 'reunion_realizada',
        resultado_detalle: 'Solicitó propuesta de upgrade',
        resultado_reunion: 'interesado',
        motivo_no_realizada: null,
      }),
    )
    expect(api().tareas.find((t) => t.id === tareaCliente.id)).toMatchObject({
      estado: 'completada',
      resultado_reunion: 'interesado',
      motivo_no_realizada: null,
      detalle_cierre_reunion: 'Solicitó propuesta de upgrade',
    })
    expect(api().tareas.find((t) => t.id === res.siguiente_id)).toMatchObject({
      lead_id: null,
      perfil_id: clienteId,
      tipo: 'whatsapp',
    })
    expect(api().actividades).toHaveLength(0)
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasAgendaPrefijo(),
    })
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasReunionesPrefijo(),
    })
  })

  it('una reunión cancelada de cliente conserva motivo y detalle por cerrar_tarea', async () => {
    const clienteId = '99999999-9999-4999-8999-999999999999'
    const tareaCliente = {
      id: '77777777-7777-4777-8777-777777777777',
      lead_id: null,
      perfil_id: clienteId,
      vendedor_id: 'u-v1',
      asignado_supervisor_id: null,
      tipo: 'reunion' as const,
      titulo: 'Reunión por renovar',
      nota: null,
      vence_en: '2026-08-25T15:00:00.000Z',
      duracion_min: 45,
      modalidad_reunion: 'presencial' as const,
      ubicacion_reunion: 'Oficina Avance',
      enlace_reunion: null,
      estado: 'pendiente' as const,
      confirmada_en: null,
      resultado_reunion: null,
      motivo_no_realizada: null,
      detalle_cierre_reunion: null,
      reagendada_de: null,
      reprogramaciones: 0,
      activo: true,
      creado_en: '2026-08-20T15:00:00.000Z',
    }
    listarTareas.mockResolvedValue([tareaCliente])
    const { api, mutar } = montar('vendedor')
    await waitFor(() => expect(api().tareas).toHaveLength(1))

    const res = mutar((a) =>
      a.anularTarea(tareaCliente.id, {
        motivo: 'cancelada_cliente',
        detalle: '  El cliente pidió mover la conversación al próximo mes  ',
      }),
    )

    expect(res.ok).toBe(true)
    expect(api().tareas.find((t) => t.id === tareaCliente.id)).toMatchObject({
      estado: 'cancelada',
      resultado_reunion: null,
      motivo_no_realizada: 'cancelada_cliente',
      detalle_cierre_reunion: 'El cliente pidió mover la conversación al próximo mes',
    })
    await waitFor(() =>
      expect(cerrarTareaMock).toHaveBeenCalledWith({
        tarea_id: tareaCliente.id,
        estado: 'cancelada',
        resultado_tipo: null,
        resultado_detalle: '  El cliente pidió mover la conversación al próximo mes  ',
        resultado_reunion: null,
        motivo_no_realizada: 'cancelada_cliente',
        siguiente: null,
      }),
    )
    expect(cerrarReunionMock).not.toHaveBeenCalled()
    expect(api().actividades).toHaveLength(0)
  })

  it('completarTarea aplica la misma validación y normalización a una reunión encadenada', async () => {
    const tareaBase = {
      id: '44444444-4444-4444-8444-444444444444',
      lead_id: '11111111-1111-4111-8111-111111111111',
      perfil_id: null,
      vendedor_id: 'u-v1',
      asignado_supervisor_id: null,
      tipo: 'llamada' as const,
      titulo: 'Llamar antes de agendar',
      nota: null,
      vence_en: '2026-07-18T15:00:00.000Z',
      duracion_min: null,
      estado: 'pendiente' as const,
      confirmada_en: null,
      reagendada_de: null,
      reprogramaciones: 0,
      activo: true,
      creado_en: '2026-07-17T15:00:00.000Z',
    }
    listarTareas.mockResolvedValue([tareaBase])
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().tareas).toHaveLength(1))

    const invalida = mutar((a) =>
      a.completarTarea({
        tarea_id: tareaBase.id,
        estado: 'completada',
        resultado_tipo: 'llamada_no_contestada',
        siguiente: {
          tipo: 'reunion',
          titulo: 'Reunión insegura',
          vence_en: '2026-07-19T15:00:00.000Z',
          modalidad_reunion: 'virtual',
          enlace_reunion: 'http://meet.example.com/sala',
        },
      }),
    )
    expect(invalida).toMatchObject({
      ok: false,
      codigo: 'enlace_reunion_invalido',
    })
    expect(cerrarTareaMock).not.toHaveBeenCalled()
    expect(api().tareas.find((t) => t.id === tareaBase.id)?.estado).toBe('pendiente')

    const valida = mutar((a) =>
      a.completarTarea({
        tarea_id: tareaBase.id,
        estado: 'completada',
        resultado_tipo: 'llamada_no_contestada',
        siguiente: {
          tipo: 'reunion',
          titulo: 'Reunión segura',
          vence_en: '2026-07-19T15:00:00.000Z',
          modalidad_reunion: 'virtual',
          ubicacion_reunion: 'Campo incompatible inyectado',
          enlace_reunion: '  https://meet.google.com/abc-defg-hij  ',
        },
      }),
    )

    expect(valida.ok).toBe(true)
    expect(comandoSla).toHaveBeenCalledWith('u-s1', 'cerrar_tarea_v2', tareaBase.id,
      expect.objectContaining({ p_siguiente: expect.objectContaining({
        modalidad_reunion: 'virtual', ubicacion_reunion: null,
        enlace_reunion: 'https://meet.google.com/abc-defg-hij',
      }) }), tareaBase)
    expect(cerrarTareaMock).not.toHaveBeenCalled()
    expect(api().tareas.find((t) => t.id === valida.siguiente_id)).toMatchObject({
      modalidad_reunion: 'virtual',
      ubicacion_reunion: null,
      enlace_reunion: 'https://meet.google.com/abc-defg-hij',
    })
  })

  it.each(['crear', 'cerrar', 'reprogramar', 'recargar'] as const)(
    '%s refresca el detalle de Citas y descarta una primera respuesta anterior a guardar', async (operacion) => {
      const cliente = new QueryClient({ defaultOptions: { queries: { retry: false, staleTime: 30_000 } } })
      invalidarQueriesMock.mockImplementation((filtros, opciones) => cliente.invalidateQueries(filtros, opciones))
      vi.mocked(queryClient.cancelQueries).mockImplementation((filtros, opciones) => cliente.cancelQueries(filtros, opciones))
      const cita = {
        id: '33333333-3333-4333-8333-333333333333', lead_id: leadBase().id, perfil_id: null,
        vendedor_id: 'u-v1', asignado_supervisor_id: null, tipo: 'reunion' as const,
        titulo: 'Cita de prueba', vence_en: '2026-07-18T20:00:00.000Z',
        estado: 'pendiente' as const, modalidad_reunion: 'presencial' as const,
        ubicacion_reunion: 'Oficina', reprogramaciones: 0, activo: true,
        creado_en: '2026-07-17T15:00:00.000Z',
      }
      listarTareas.mockResolvedValue([cita])
      const { api, mutar } = montar('supervisor')
      await waitFor(() => expect(api().tareas).toHaveLength(1))
      const respuestaAntigua = diferida<void>()
      let guardado = false
      comandoSla.mockImplementation(async () => { guardado = true })
      insertarTarea.mockImplementation(async () => { guardado = true })
      const clave = crmQueryKeys.citasGerencia('u-s1', '2026-07')
      const observador = new QueryObserver(cliente, {
        queryKey: clave,
        queryFn: async ({ signal }) => {
          const foto = { actualizado: guardado }
          if (!guardado) await respuestaAntigua.promesa
          void signal
          return foto
        },
      })
      const desuscribir = observador.subscribe(() => undefined)
      try {
        expect(cliente.getQueryState(clave)?.fetchStatus).toBe('fetching')
        if (operacion === 'recargar') {
          // La conversión a cliente guarda fuera del store y luego llama recargar().
          guardado = true
          await act(async () => { await api().recargar() })
        } else {
          const res = mutar((a) => operacion === 'crear'
            ? a.crearTarea({ lead_id: cita.lead_id, tipo: 'reunion', titulo: 'Otra cita',
              vence_en: '2027-01-05T15:00:00.000Z', modalidad_reunion: 'presencial', ubicacion_reunion: 'Oficina' })
            : operacion === 'cerrar'
              // Cerrar una cita de lead como realizada la convierte en entrevista:
              // el capital propuesto es obligatorio (crm.cerrar_reunion_v3).
              ? a.completarTarea({ tarea_id: cita.id, estado: 'completada', resultado_tipo: 'reunion_realizada', resultado_reunion: 'interesado', capital: { monto_estimado: 50000, moneda: 'PEN' } })
              : a.reprogramarTarea(cita.id, '2026-07-19T20:00:00.000Z'))
          expect(res.ok).toBe(true)
          await act(async () => { expect(await res.persistido).toBe(true) })
        }
        respuestaAntigua.resolver()
        await waitFor(() => expect(cliente.getQueryData(clave)).toEqual({ actualizado: true }))
      } finally {
        respuestaAntigua.resolver()
        desuscribir()
        cliente.clear()
      }
    },
  )

  it('dos recargas de Citas seguidas conservan el último dato aunque ambas respuestas anteriores lleguen tarde', async () => {
    const cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } })
    invalidarQueriesMock.mockImplementation((filtros, opciones) => cliente.invalidateQueries(filtros, opciones))
    vi.mocked(queryClient.cancelQueries).mockImplementation((filtros, opciones) => cliente.cancelQueries(filtros, opciones))
    const { api } = montar('gerencia')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const antiguas = diferida<void>()
    let version = 0
    const leidas: number[] = []
    const clave = crmQueryKeys.citasGerencia('u-ger', '2026-07')
    const observador = new QueryObserver(cliente, {
      queryKey: clave,
      queryFn: async ({ signal }) => {
        const foto = version
        leidas.push(foto)
        if (foto < 2) await antiguas.promesa
        void signal
        return foto
      },
    })
    const desuscribir = observador.subscribe(() => undefined)
    try {
      version = 1
      await act(async () => { await api().recargar() })
      await waitFor(() => expect(leidas).toContain(1))
      version = 2
      await act(async () => { await api().recargar() })
      antiguas.resolver()
      await waitFor(() => expect(cliente.getQueryData(clave)).toBe(2))
      expect(cliente.getQueryState(clave)).toMatchObject({ isInvalidated: false, fetchStatus: 'idle' })
    } finally {
      antiguas.resolver()
      desuscribir()
      cliente.clear()
    }
  })

  it('reprogramar conserva la original, enlaza una cita nueva y permite confirmarla', async () => {
    const cita = {
      id: '33333333-3333-4333-8333-333333333333',
      lead_id: '11111111-1111-4111-8111-111111111111',
      perfil_id: null,
      vendedor_id: 'u-v1',
      asignado_supervisor_id: null,
      tipo: 'reunion' as const,
      titulo: 'Reunión con CLIENTE',
      nota: null,
      vence_en: '2026-07-18T20:00:00.000Z',
      duracion_min: 60,
      estado: 'pendiente' as const,
      confirmada_en: '2026-07-18T10:00:00.000Z',
      reagendada_de: null,
      reprogramaciones: 0,
      activo: true,
      creado_en: '2026-07-17T15:00:00.000Z',
    }
    listarTareas.mockResolvedValue([cita])
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().tareas).toHaveLength(1))

    const rep = mutar((a) => a.reprogramarTarea(cita.id, '2026-07-19T20:00:00.000Z'))
    expect(rep.ok).toBe(true)
    expect(comandoSla).toHaveBeenCalledWith('u-s1', 'reprogramar_reunion_v2', cita.id, { p_tarea_id: cita.id, p_vence_en: '2026-07-19T20:00:00.000Z', p_nueva_id: expect.any(String) }, cita)
    expect(reprogramarReunionMock).not.toHaveBeenCalled()
    expect(api().tareas.find((t) => t.id === cita.id)).toMatchObject({
      estado: 'reprogramada',
      motivo_no_realizada: 'reprogramada',
    })
    const nueva = api().tareas.find((t) => t.reagendada_de === cita.id)
    expect(nueva).toMatchObject({
      vence_en: '2026-07-19T20:00:00.000Z',
      reprogramaciones: 1,
      confirmada_en: null,
    })

    const conf = mutar((a) => a.confirmarTarea(nueva?.id ?? ''))
    expect(conf.ok).toBe(true)
    expect(api().tareas[0]?.confirmada_en).toBeTruthy()
    await waitFor(() => {
      expect(invalidarQueriesMock).toHaveBeenCalledWith({
        queryKey: crmQueryKeys.metricasAgendaPrefijo(),
      })
      expect(invalidarQueriesMock).toHaveBeenCalledWith({
        queryKey: crmQueryKeys.metricasReunionesPrefijo(),
      })
    })
  })

  it('anular una reunión conserva motivo/detalle y usa solo la RPC especializada', async () => {
    const cita = {
      id: '55555555-5555-4555-8555-555555555555',
      lead_id: '11111111-1111-4111-8111-111111111111',
      perfil_id: null,
      vendedor_id: 'u-v1',
      asignado_supervisor_id: null,
      tipo: 'reunion' as const,
      titulo: 'Reunión que ya no aplica',
      nota: null,
      vence_en: '2026-07-18T20:00:00.000Z',
      duracion_min: 60,
      estado: 'pendiente' as const,
      confirmada_en: null,
      reagendada_de: null,
      reprogramaciones: 0,
      activo: true,
      creado_en: '2026-07-17T15:00:00.000Z',
    }
    listarTareas.mockResolvedValue([cita])
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().tareas).toHaveLength(1))

    const res = mutar((a) =>
      a.anularTarea(cita.id, {
        motivo: 'cancelada_cliente',
        detalle: '  El cliente pidió cancelar  ',
      }),
    )

    expect(res.ok).toBe(true)
    expect(api().tareas.find((t) => t.id === cita.id)).toMatchObject({
      estado: 'cancelada',
      motivo_no_realizada: 'cancelada_cliente',
      detalle_cierre_reunion: 'El cliente pidió cancelar',
    })
    // v3 y no v2: la misma puerta cierra la cita y registra la entrevista. Al
    // anular no hay capital que declarar, y la puerta rechazaría una cifra.
    expect(comandoSla).toHaveBeenCalledWith('u-s1', 'cerrar_reunion_v3', cita.id, {
      p_tarea_id: cita.id, p_estado: 'cancelada', p_resultado_reunion: null,
      p_motivo_no_realizada: 'cancelada_cliente', p_detalle: '  El cliente pidió cancelar  ', p_siguiente: null,
      p_capital_estimado: null, p_moneda: null,
    }, cita)
    expect(cerrarReunionMock).not.toHaveBeenCalled()
    expect(cerrarTareaMock).not.toHaveBeenCalled()
    await expect(res.persistido).resolves.toBe(true)
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasAgendaPrefijo(),
    })
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasReunionesPrefijo(),
    })
  })

  // F2.b [D-15]: la edición de la ficha va por UNA RPC transaccional con la fila
  // completa que manda la ficha (el servidor pasa el DNI por su puerta con ON).
  it('editar la ficha va por editar_lead_fn con el parche completo (DNI incluido) y NUNCA por UPDATE directo', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const id = api().leads[0]!.id

    const res = mutar((a) => a.editarLead(id, { dni: '45678901', nota: 'con documento', telefono: '+51999111222' }))

    expect(res).toMatchObject({ ok: true })
    await waitFor(() => expect(editarLeadFn).toHaveBeenCalledWith(id, { dni: '45678901', nota: 'con documento', telefono: '+51999111222' }))
    expect(actualizarLead).not.toHaveBeenCalled()
  })

  it('la puerta del DNI rechaza (P0409 «ya tiene su lead»): rollback con el texto del servidor', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const id = api().leads[0]!.id
    editarLeadFn.mockRejectedValueOnce(
      new CrmApiError('La persona de ese documento ya es cliente o ya tiene su lead: no se puede asignar a este', 'CONFLICTO'),
    )

    mutar((a) => a.editarLead(id, { dni: '45678904', nota: 'no debe guardarse' }))

    await waitFor(() =>
      expect(toast.error).toHaveBeenCalledWith(expect.stringContaining('ya es cliente o ya tiene su lead')),
    )
  })

  it('editar capital real persiste monto y moneda juntos', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const id = api().leads[0]!.id

    const res = mutar((a) => a.editarLead(id, { monto_estimado: 25_000, moneda: 'USD' }))

    expect(res).toMatchObject({ ok: true })
    await waitFor(() =>
      expect(editarLeadFn).toHaveBeenCalledWith(id, {
        monto_estimado: 25_000,
        moneda: 'USD',
      }),
    )
  })

  // En real, convertir por el store queda cerrado a propósito: la conversión de
  // verdad crea la cuenta del cliente vía edge desde la ficha. Marcar la etapa a
  // secas dejaría un "convertido" sin cliente detrás.
  it('convertir por el store sigue cerrado en real (la vía buena es la ficha/edge)', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const id = api().leads[0]!.id
    const res = mutar((a) => a.convertir(id))
    expect(res.ok).toBe(false)
    expect(res.codigo).toBe('fuente_no_habilitada')
  })

  it('rechazo del servidor: rollback con mensaje HONESTO cuando el resync sí aplica', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const id = api().leads[0]!.id
    editarLeadFn.mockRejectedValueOnce(new CrmApiError('Ese teléfono ya existe', 'DUP_TELEFONO'))

    mutar((a) => a.editarLead(id, { correo: 'nuevo@correo.com' }))

    await waitFor(() =>
      expect(toast.error).toHaveBeenCalledWith(expect.stringContaining('se actualizó la vista con el estado del servidor')),
    )
  })

  it('rechazo + servidor inalcanzable: el toast NO miente ("se restauró")', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const id = api().leads[0]!.id
    editarLeadFn.mockRejectedValueOnce(new CrmApiError('No se pudo guardar el cambio', 'POSTGREST_ERROR'))
    // El resync de rollback también falla (offline).
    listarTareas.mockRejectedValueOnce(new CrmApiError('sin red', 'POSTGREST_ERROR'))

    mutar((a) => a.editarLead(id, { correo: 'otro@correo.com' }))

    await waitFor(() =>
      expect(toast.error).toHaveBeenCalledWith(expect.stringContaining('Sin conexión con el servidor')),
    )
    expect(toast.error).not.toHaveBeenCalledWith(expect.stringContaining('se restauró'))
  })

  it('descartar real con nota: persiste el update Y la nota como actividad aparte', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const id = api().leads[0]!.id

    const res = mutar((a) => a.descartar(id, 'sin_fondos', 'Retomar en Q4'))

    expect(res.ok).toBe(true)
    await waitFor(() =>
      expect(actualizarLead).toHaveBeenCalledWith(id, {
        etapa: 'descartado',
        motivo_descarte: 'sin_fondos',
      }),
    )
    await waitFor(() =>
      expect(insertarActividad).toHaveBeenCalledWith(
        expect.objectContaining({
          lead_id: id,
          tipo: 'nota',
          detalle: expect.stringContaining('Retomar en Q4'),
        }),
      ),
    )
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasConversionesPrefijo(),
    })
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasConversionesEquipoPrefijo(),
    })
  })

  it('reabrir un descartado caduca las dos fotos de conversión por rango', async () => {
    listarLeads.mockResolvedValueOnce([
      { ...leadBase(), etapa: 'descartado', motivo_descarte: 'sin_fondos' },
    ])
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads[0]?.etapa).toBe('descartado'))

    invalidarQueriesMock.mockClear()
    expect(mutar((a) => a.reabrir(leadBase().id))).toMatchObject({ ok: true })
    // F2.b [D-15]: por su puerta SQL, nunca por UPDATE (con la identidad encendida
    // el UPDATE directo descartado→nuevo está cerrado por D-13).
    await waitFor(() => expect(reabrirLead).toHaveBeenCalledWith(leadBase().id))
    expect(actualizarLead).not.toHaveBeenCalled()
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasConversionesPrefijo(),
    })
    expect(invalidarQueriesMock).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.metricasConversionesEquipoPrefijo(),
    })
  })

  it('descartar real: si la nota falla tras el update OK, avisa el fallo parcial SIN mentir "se restauró"', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const id = api().leads[0]!.id
    // El update descarta OK; solo el insert de la nota falla.
    insertarActividad.mockRejectedValueOnce(new CrmApiError('actividad rechazada', 'POSTGREST_ERROR'))

    const res = mutar((a) => a.descartar(id, 'sin_fondos', 'Nota condenada'))

    expect(res.ok).toBe(true)
    await waitFor(() =>
      expect(toast.warning).toHaveBeenCalledWith(expect.stringContaining('no se pudo guardar la nota del descarte')),
    )
    // El descarte NO se revierte ni se miente: el toast de rollback nunca aparece.
    expect(toast.error).not.toHaveBeenCalledWith(expect.stringContaining('se actualizó la vista con el estado del servidor'))
  })

  // Un fetch COLGADO no rechaza nunca: sin el reloj de LIMITE_CARGA_REAL_MS el
  // analista se quedaba para siempre en «Preparando tu información…».
  it('carga inicial COLGADA → estado accionable de error (no un spinner eterno)', async () => {
    vi.useFakeTimers()
    try {
      // Promesa que jamás se asienta: el peor caso (ni éxito ni fallo).
      listarTareas.mockImplementationOnce(() => new Promise(() => {}))
      const { estado } = montar('supervisor')
      expect(estado().cargando).toBe(true)
      expect(estado().error).toBe(false)

      await act(async () => {
        vi.advanceTimersByTime(LIMITE_CARGA_REAL_MS + 1)
      })

      expect(estado().error).toBe(true)
      expect(estado().cargando).toBe(false)
    } finally {
      vi.useRealTimers()
    }
  })

  it('la carga normal NO se corta por el límite (no rompe el arranque lento pero vivo)', async () => {
    const { api, estado } = montar('supervisor')
    await waitFor(() => expect(estado().cargando).toBe(false))
    expect(estado().error).toBe(false)
    expect(api().leads).toHaveLength(1)
  })

  // Un fallo de LECTURA de metas se pintaba como «Meta mensual por definir»:
  // el analista creía que gerencia no le fijó meta cuando sí lo hizo.
  it('metas que NO se pudieron leer se marcan como error, no como "sin meta"', async () => {
    obtenerMetasMock.mockRejectedValueOnce(new CrmApiError('metas caídas', 'POSTGREST_ERROR'))
    const { api, estado } = montar('vendedor')

    await waitFor(() => expect(estado().cargando).toBe(false))
    // El CRM entero NO cae por las metas (siguen siendo un fetch auxiliar)…
    expect(estado().error).toBe(false)
    // …pero el consumidor sabe que los ceros no son un dato.
    expect(api().objetivosError).toBe(true)
    expect(api().cumplimientoMetas).toBeNull()
    expect(api().cumplimientoMetasError).toBe(true)
  })

  it('metas leídas OK (aunque estén vacías) NO son un error: el cero SÍ es el dato', async () => {
    obtenerMetasMock.mockResolvedValue(configuracionMetas())
    const { api, estado } = montar('vendedor')

    await waitFor(() => expect(estado().cargando).toBe(false))
    expect(api().objetivosError).toBe(false)
  })

  it('tras un fallo de metas, recargar() limpia la marca cuando el servidor vuelve', async () => {
    obtenerMetasMock.mockRejectedValueOnce(new CrmApiError('metas caídas', 'POSTGREST_ERROR'))
    const { api, estado } = montar('supervisor')
    await waitFor(() => expect(api().objetivosError).toBe(true))

    obtenerMetasMock.mockResolvedValue(configuracionMetas())
    await act(async () => {
      await api().recargar()
    })
    await waitFor(() => expect(api().objetivosError).toBe(false))
    expect(estado().error).toBe(false)
  })

  it('un fallo de cumplimiento no se reemplaza con pipeline ni derriba el CRM', async () => {
    obtenerCumplimientoMock.mockRejectedValueOnce(new CrmApiError('cumplimiento caído', 'POSTGREST_ERROR'))
    const { api, estado } = montar('gerencia')

    await waitFor(() => expect(estado().cargando).toBe(false))
    expect(estado().error).toBe(false)
    expect(api().cumplimientoMetas).toBeNull()
    expect(api().cumplimientoMetasError).toBe(true)
  })

  it('oculta el cumplimiento si llegó de una revisión distinta a la configuración', async () => {
    const configuracion = configuracionMetas(420_000, 42_000, 18)
    const cumplimientoDesfasado = cumplimientoMetas(210_000, 10_500, 50, configuracion)
    obtenerMetasMock.mockResolvedValueOnce(configuracion)
    obtenerCumplimientoMock.mockResolvedValueOnce({
      ...cumplimientoDesfasado,
      revision: configuracion.revision + 1,
    })
    const { api, estado } = montar('gerencia')

    await waitFor(() => expect(estado().cargando).toBe(false))
    expect(api().objetivosError).toBe(false)
    expect(api().cumplimientoMetas).toBeNull()
    expect(api().cumplimientoMetasError).toBe(true)
  })

  it('fallo de la carga inicial → estado.error (no pinta CRM vacío) y reintentar recupera', async () => {
    listarTareas.mockRejectedValueOnce(new CrmApiError('caída inicial', 'POSTGREST_ERROR'))
    const { api, estado } = montar('supervisor')
    await waitFor(() => expect(estado().error).toBe(true))
    expect(api().leads).toHaveLength(0)

    // El siguiente intento ya tiene el mock por defecto (1 lead).
    act(() => estado().reintentar())
    await waitFor(() => expect(estado().error).toBe(false))
    await waitFor(() => expect(api().leads).toHaveLength(1))
  })
})

describe('Fase 3 «sin topes» — el store ya no baja el registro de actividades', () => {
  it('descartar por «no_responde» SIN historial en caché pide abrir la ficha en vez de juzgar sobre una lista vacía', async () => {
    const { api, mutar } = montar('vendedor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const id = leadBase().id

    const res = mutar((a) => a.descartar(id, 'no_responde'))

    expect(res.ok).toBe(false)
    expect(res.error).toContain('Abre la ficha')
    expect(api().lead(id)?.etapa).not.toBe('descartado')
  })

  it('la resincronización conserva las gestiones optimistas recientes (el historial por lead las sustituye después)', async () => {
    const { api, mutar } = montar('vendedor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const id = leadBase().id
    expect(mutar((a) => a.registrarActividad(id, 'llamada_realizada', 'Contactó'))).toMatchObject({ ok: true })
    // La llamada más el cambio de etapa optimista (nuevo → contactado): ambas locales.
    const localesAntes = api().actividades.filter((a) => a.local === true && a.lead_id === id)
    expect(localesAntes.length).toBeGreaterThanOrEqual(1)
    expect(localesAntes.some((a) => a.tipo === 'llamada_realizada')).toBe(true)

    await act(async () => { expect(await api().recargar()).toBe(true) })

    const localesDespues = api().actividades.filter((a) => a.local === true && a.lead_id === id)
    expect(localesDespues.map((a) => a.id)).toEqual(localesAntes.map((a) => a.id))
  })
})

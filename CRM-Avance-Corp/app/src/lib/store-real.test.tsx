// Tests de la ruta REAL del store (sesión autenticada no-demo): gate de acciones
// abierto, persistencia optimista + resync contra el servidor, honestidad del
// rollback offline y estado de carga con reintento. La capa @/data/crm-api se
// mockea (sin red); CrmApiError se conserva real para el instanceof de persistir.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, render, waitFor } from '@testing-library/react'
import { toast } from 'sonner'
import { AuthContext, type AuthContextValue } from './auth-context'
import { useCRMData, useStoreEstado } from './store-context'
import type { Rol } from './roles'
import type { StoreDataApi, StoreEstado } from './store'
import * as crmApi from '@/data/crm-api'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return {
    ...actual, // conserva CrmApiError real (instanceof en persistir)
    listarLeadsDelAmbito: vi.fn(),
    listarEquipo: vi.fn(),
    listarActividadesDelAmbito: vi.fn(),
    listarTareasDelAmbito: vi.fn(),
    listarObjetivos: vi.fn(),
    fijarObjetivosRpc: vi.fn(),
    insertarLead: vi.fn(),
    insertarTarea: vi.fn(),
    cerrarTarea: vi.fn(),
    cerrarReunion: vi.fn(),
    reprogramarReunion: vi.fn(),
    actualizarLead: vi.fn(),
    actualizarTarea: vi.fn(),
    insertarActividad: vi.fn(),
  }
})

const { StoreProvider, LIMITE_CARGA_REAL_MS } = await import('./store')
const { CrmApiError } = crmApi

const listarLeads = vi.mocked(crmApi.listarLeadsDelAmbito)
const listarEquipo = vi.mocked(crmApi.listarEquipo)
const listarActs = vi.mocked(crmApi.listarActividadesDelAmbito)
const insertarLead = vi.mocked(crmApi.insertarLead)
const actualizarLead = vi.mocked(crmApi.actualizarLead)
const actualizarTarea = vi.mocked(crmApi.actualizarTarea)
const insertarActividad = vi.mocked(crmApi.insertarActividad)
const listarTareas = vi.mocked(crmApi.listarTareasDelAmbito)
const insertarTarea = vi.mocked(crmApi.insertarTarea)
const cerrarTareaMock = vi.mocked(crmApi.cerrarTarea)
const cerrarReunionMock = vi.mocked(crmApi.cerrarReunion)
const reprogramarReunionMock = vi.mocked(crmApi.reprogramarReunion)
const listarObjetivosMock = vi.mocked(crmApi.listarObjetivos)
const fijarObjetivosMock = vi.mocked(crmApi.fijarObjetivosRpc)

const ROSTER = [
  { perfil_id: 'u-ger', nombre_completo: 'Gerente Real', rol_crm: 'gerencia' as const, supervisor_id: null, activo: true },
  { perfil_id: 'u-s1', nombre_completo: 'Supervisor Real', rol_crm: 'supervisor' as const, supervisor_id: null, activo: true },
  { perfil_id: 'u-v1', nombre_completo: 'Vendedor Real', rol_crm: 'vendedor' as const, supervisor_id: 'u-s1', activo: true },
]

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

function sesionReal(rol: Rol): AuthContextValue {
  const identidad = rol === 'gerencia'
    ? { id: 'u-ger', nombre_completo: 'Gerente Real' }
    : rol === 'supervisor'
      ? { id: 'u-s1', nombre_completo: 'Supervisor Real' }
      : rol === 'vendedor'
        ? { id: 'u-v1', nombre_completo: 'Vendedor Real' }
        : { id: `u-${rol}`, nombre_completo: `Usuario ${rol}` }
  return {
    fase: 'listo',
    yo: { ...identidad, rol, demo: false, puede_contratar: true },
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
  mutar: <T>(fn: (api: StoreDataApi) => T) => T
}

function montar(rol: Rol = 'gerencia'): Montaje {
  const ref: { api: StoreDataApi | null; estado: StoreEstado | null } = { api: null, estado: null }
  function Sonda(): null {
    ref.api = useCRMData()
    ref.estado = useStoreEstado()
    return null
  }
  render(
    <AuthContext.Provider value={sesionReal(rol)}>
      <StoreProvider>
        <Sonda />
      </StoreProvider>
    </AuthContext.Provider>,
  )
  return {
    api: () => {
      if (!ref.api) throw new Error('StoreProvider aún no montado')
      return ref.api
    },
    estado: () => {
      if (!ref.estado) throw new Error('StoreProvider aún no montado')
      return ref.estado
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

describe('store — ruta real (sesión autenticada, no demo)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    listarLeads.mockResolvedValue([leadBase()])
    listarEquipo.mockResolvedValue(ROSTER)
    listarActs.mockResolvedValue([])
    insertarLead.mockImplementation(async (fila) => {
      if (!fila.id) throw new Error('El test real exige el id optimista')
      return { estado: 'creado', lead_id: fila.id }
    })
    listarTareas.mockResolvedValue([])
    listarObjetivosMock.mockResolvedValue([])
    fijarObjetivosMock.mockResolvedValue(undefined)
    insertarTarea.mockResolvedValue(undefined)
    cerrarTareaMock.mockResolvedValue({ siguiente_id: null })
    cerrarReunionMock.mockResolvedValue({ siguiente_id: null })
    reprogramarReunionMock.mockImplementation(async (_tareaId, _venceEn, nuevaId) => ({
      tarea_nueva_id: nuevaId,
    }))
    actualizarLead.mockResolvedValue(undefined)
    actualizarTarea.mockResolvedValue(undefined)
    insertarActividad.mockResolvedValue(undefined)
  })
  afterEach(() => vi.clearAllMocks())

  it('carga el ámbito operativo y resuelve vendedor_nombre desde el roster', async () => {
    const { api } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    expect(api().leads[0]?.vendedor_nombre).toBe('Vendedor Real')
  })

  it('Gerencia carga roster y metas, pero no descarga leads, actividades ni tareas', async () => {
    const { api, estado } = montar('gerencia')

    await waitFor(() => expect(estado().cargando).toBe(false))
    expect(api().equipo).toEqual(ROSTER)
    expect(api().leads).toEqual([])
    expect(api().actividades).toEqual([])
    expect(api().tareas).toEqual([])
    expect(listarEquipo).toHaveBeenCalledTimes(1)
    expect(listarObjetivosMock).toHaveBeenCalledTimes(1)
    expect(listarLeads).not.toHaveBeenCalled()
    expect(listarActs).not.toHaveBeenCalled()
    expect(listarTareas).not.toHaveBeenCalled()
  })

  it('Gerencia conserva metas individuales reales y sus agregados con la carga ligera', async () => {
    listarObjetivosMock.mockResolvedValueOnce([{
      vendedor_id: 'u-v1',
      supervisor_id: 'u-s1',
      capital_objetivo: 420_000,
      ventas_objetivo: 0,
      conversion_objetivo: 18,
    }])
    const { api, estado } = montar('gerencia')

    await waitFor(() => expect(estado().cargando).toBe(false))
    expect(api().objetivos.porVendedor?.['u-v1']).toEqual({
      vendedorId: 'u-v1',
      supervisorId: 'u-s1',
      capitalObjetivo: 420_000,
      ventasObjetivo: 0,
      conversionObjetivo: 18,
    })
    expect(api().objetivos.gerencia).toEqual({
      capitalObjetivo: 420_000,
      ventasObjetivo: 0,
      conversionObjetivo: 18,
    })
  })

  it('recargar Gerencia resincroniza roster/metas sin activar loaders operativos', async () => {
    const { api, estado } = montar('gerencia')
    await waitFor(() => expect(estado().cargando).toBe(false))
    vi.clearAllMocks()
    listarEquipo.mockResolvedValue(ROSTER)
    listarObjetivosMock.mockResolvedValue([])

    await act(async () => {
      expect(await api().recargar()).toBe(true)
    })

    expect(listarEquipo).toHaveBeenCalledTimes(1)
    expect(listarObjetivosMock).toHaveBeenCalledTimes(1)
    expect(listarLeads).not.toHaveBeenCalled()
    expect(listarActs).not.toHaveBeenCalled()
    expect(listarTareas).not.toHaveBeenCalled()
  })

  it('la omisión de datos operativos es exclusiva de Gerencia', async () => {
    const { api, estado } = montar('directorio')

    await waitFor(() => expect(estado().cargando).toBe(false))
    expect(api().leads).toHaveLength(1)
    expect(listarLeads).toHaveBeenCalledTimes(1)
    expect(listarActs).toHaveBeenCalledTimes(1)
    expect(listarTareas).toHaveBeenCalledTimes(1)
  })

  it('fijarObjetivos: optimista + RPC con el periodo Lima (solo gerencia)', async () => {
    const { api, mutar } = montar('gerencia')
    await waitFor(() => expect(api().equipo).toHaveLength(ROSTER.length))

    const metas = {
      'u-v1': {
        vendedorId: 'u-v1',
        supervisorId: 'u-s1',
        capitalObjetivo: 1_000_000,
        ventasObjetivo: 0,
        conversionObjetivo: 28,
      },
    }
    const res = mutar((a) => a.fijarObjetivos(metas))

    expect(res.ok).toBe(true)
    // Optimista: el marcador se actualiza al toque.
    expect(api().objetivos.gerencia.capitalObjetivo).toBe(1_000_000)
    await waitFor(() => expect(fijarObjetivosMock).toHaveBeenCalledTimes(1))
    const [periodo, payload] = fijarObjetivosMock.mock.calls[0] ?? []
    expect(periodo).toMatch(/^\d{4}-\d{2}-01$/) // primer día del mes (Lima)
    expect(payload?.['u-v1']).toEqual({
      capital_objetivo: 1_000_000, ventas_objetivo: 0, conversion_objetivo: 28,
    })
  })

  it('fijarObjetivos: un vendedor NO puede (espejo del gate del servidor)', async () => {
    const { api, mutar } = montar('vendedor')
    await waitFor(() => expect(api().leads).toHaveLength(1))

    const res = mutar((a) => a.fijarObjetivos(api().objetivos))

    expect(res.ok).toBe(false)
    expect(res.codigo).toBe('sin_permiso')
    expect(fijarObjetivosMock).not.toHaveBeenCalled()
  })

  it('fijarObjetivos: metas inválidas no viajan a la red', async () => {
    const { api, mutar } = montar('gerencia')
    await waitFor(() => expect(api().equipo).toHaveLength(ROSTER.length))

    const res = mutar((a) => a.fijarObjetivos({
      vendedor: { capitalObjetivo: -1, ventasObjetivo: 0, conversionObjetivo: 0 },
      supervisor: { capitalObjetivo: 0, ventasObjetivo: 0, conversionObjetivo: 0 },
      gerencia: { capitalObjetivo: 0, ventasObjetivo: 0, conversionObjetivo: 0 },
    }))

    expect(res.ok).toBe(false)
    expect(res.error).toMatch(/positivos/)
    expect(fijarObjetivosMock).not.toHaveBeenCalled()
  })

  it('el gate de acciones está ABIERTO: crearLead persiste y resincroniza', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    listarLeads.mockClear()

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
    expect(insertarLead).toHaveBeenCalledWith(
      expect.objectContaining({ monto_estimado: 5000, moneda: 'PEN' }),
    )
    await expect(res.persistido).resolves.toEqual({ ok: true })
    await waitFor(() => expect(listarLeads).toHaveBeenCalled()) // resync
  })

  it('crearLead expone el rechazo sanitizado del INSERT para no anunciar un falso éxito', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    insertarLead.mockRejectedValueOnce(new CrmApiError(
      'Este contacto acaba de ser registrado por otro usuario',
      'CONTACTO_RECIEN_REGISTRADO',
    ))

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
    expect(insertarLead).toHaveBeenCalledWith(
      expect.objectContaining({ genero: 'F', fecha_nacimiento: '1990-05-20' }),
    )
    // Y el optimista los muestra sin esperar al resync.
    expect(api().leads[0]).toMatchObject({ genero: 'F', fecha_nacimiento: '1990-05-20' })
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

    expect(res).toMatchObject({ ok: false, codigo: 'menor_de_edad', campo: 'fecha_nacimiento' })
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
    await waitFor(() => expect(listarTareas).toHaveBeenCalled()) // resync
  })

  it('crearTarea valida y normaliza la reunión antes del optimista y del INSERT real', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const leadId = api().leads[0]!.id
    insertarTarea.mockClear()

    const invalida = mutar((a) => a.crearTarea({
      lead_id: leadId,
      tipo: 'reunion',
      titulo: 'Enlace manipulado',
      vence_en: '2027-01-05T15:00:00.000Z',
      modalidad_reunion: 'virtual',
      enlace_reunion: 'http://meet.example.com/sala',
    }))
    expect(invalida).toMatchObject({ ok: false, codigo: 'enlace_reunion_invalido' })
    expect(insertarTarea).not.toHaveBeenCalled()

    const valida = mutar((a) => a.crearTarea({
      lead_id: leadId,
      tipo: 'reunion',
      titulo: 'Reunión virtual segura',
      vence_en: '2027-01-05T15:00:00.000Z',
      modalidad_reunion: 'virtual',
      ubicacion_reunion: 'Campo incompatible inyectado',
      enlace_reunion: '  https://meet.google.com/abc-defg-hij  ',
    }))

    expect(valida.ok).toBe(true)
    expect(api().tareas.find((t) => t.id === valida.id)).toMatchObject({
      modalidad_reunion: 'virtual',
      ubicacion_reunion: null,
      enlace_reunion: 'https://meet.google.com/abc-defg-hij',
    })
    expect(insertarTarea).toHaveBeenCalledWith(expect.objectContaining({
      modalidad_reunion: 'virtual',
      ubicacion_reunion: null,
      enlace_reunion: 'https://meet.google.com/abc-defg-hij',
    }))
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
    expect(sinResultado).toMatchObject({ ok: false, codigo: 'resultado_obligatorio' })
    expect(cerrarTareaMock).not.toHaveBeenCalled()

    // Con resultado + siguiente: optimista + RPC con el payload completo.
    const res = mutar((a) =>
      a.completarTarea({
        tarea_id: tareaBase.id,
        estado: 'completada',
        resultado_tipo: 'llamada_no_contestada',
        siguiente: { tipo: 'whatsapp', titulo: 'WhatsApp a CLIENTE', vence_en: '2026-07-19T15:00:00.000Z' },
      }),
    )
    expect(res.ok).toBe(true)
    expect(res.siguiente_id).toBeDefined()
    expect(cerrarTareaMock).toHaveBeenCalledWith({
      tarea_id: tareaBase.id,
      estado: 'completada',
      resultado_tipo: 'llamada_no_contestada',
      resultado_detalle: null,
      siguiente: {
        id: expect.any(String),
        tipo: 'whatsapp',
        titulo: 'WhatsApp a CLIENTE',
        vence_en: '2026-07-19T15:00:00.000Z',
        modalidad_reunion: null,
        ubicacion_reunion: null,
        enlace_reunion: null,
      },
    })
    // Optimista: la original cerrada, la siguiente pendiente, y el resultado ya en el timeline.
    expect(api().tareas.find((t) => t.id === tareaBase.id)?.estado).toBe('completada')
    expect(api().tareas.some((t) => t.titulo === 'WhatsApp a CLIENTE' && t.estado === 'pendiente')).toBe(true)
    expect(api().actividades.some((a2) => a2.tipo === 'llamada_no_contestada')).toBe(true)
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

    const invalida = mutar((a) => a.completarTarea({
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
    }))
    expect(invalida).toMatchObject({ ok: false, codigo: 'enlace_reunion_invalido' })
    expect(cerrarTareaMock).not.toHaveBeenCalled()
    expect(api().tareas.find((t) => t.id === tareaBase.id)?.estado).toBe('pendiente')

    const valida = mutar((a) => a.completarTarea({
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
    }))

    expect(valida.ok).toBe(true)
    expect(cerrarTareaMock).toHaveBeenCalledWith(expect.objectContaining({
      siguiente: expect.objectContaining({
        modalidad_reunion: 'virtual',
        ubicacion_reunion: null,
        enlace_reunion: 'https://meet.google.com/abc-defg-hij',
      }),
    }))
    expect(api().tareas.find((t) => t.id === valida.siguiente_id)).toMatchObject({
      modalidad_reunion: 'virtual',
      ubicacion_reunion: null,
      enlace_reunion: 'https://meet.google.com/abc-defg-hij',
    })
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
    expect(reprogramarReunionMock).toHaveBeenCalledWith(
      cita.id,
      '2026-07-19T20:00:00.000Z',
      expect.any(String),
    )
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

    const res = mutar((a) => a.anularTarea(cita.id, {
      motivo: 'cancelada_cliente',
      detalle: '  El cliente pidió cancelar  ',
    }))

    expect(res.ok).toBe(true)
    expect(api().tareas.find((t) => t.id === cita.id)).toMatchObject({
      estado: 'cancelada',
      motivo_no_realizada: 'cancelada_cliente',
      detalle_cierre_reunion: 'El cliente pidió cancelar',
    })
    expect(cerrarReunionMock).toHaveBeenCalledWith({
      tarea_id: cita.id,
      estado: 'cancelada',
      resultado_reunion: null,
      motivo_no_realizada: 'cancelada_cliente',
      detalle: '  El cliente pidió cancelar  ',
      siguiente: null,
    })
    expect(cerrarTareaMock).not.toHaveBeenCalled()
  })

  it('editar capital real persiste monto y moneda juntos', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const id = api().leads[0]!.id

    const res = mutar((a) => a.editarLead(id, { monto_estimado: 25_000, moneda: 'USD' }))

    expect(res).toMatchObject({ ok: true })
    await waitFor(() =>
      expect(actualizarLead).toHaveBeenCalledWith(id, { monto_estimado: 25_000, moneda: 'USD' }),
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
    actualizarLead.mockRejectedValueOnce(new CrmApiError('Ese teléfono ya existe', 'DUP_TELEFONO'))

    mutar((a) => a.editarLead(id, { correo: 'nuevo@correo.com' }))

    await waitFor(() =>
      expect(toast.error).toHaveBeenCalledWith(
        expect.stringContaining('se restauró el estado anterior'),
      ),
    )
  })

  it('rechazo + servidor inalcanzable: el toast NO miente ("se restauró")', async () => {
    const { api, mutar } = montar('supervisor')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const id = api().leads[0]!.id
    actualizarLead.mockRejectedValueOnce(new CrmApiError('No se pudo guardar el cambio', 'POSTGREST_ERROR'))
    // El resync de rollback también falla (offline).
    listarLeads.mockRejectedValueOnce(new CrmApiError('sin red', 'POSTGREST_ERROR'))

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
    await waitFor(() => expect(actualizarLead).toHaveBeenCalledWith(id, { etapa: 'descartado', motivo_descarte: 'sin_fondos' }))
    await waitFor(() =>
      expect(insertarActividad).toHaveBeenCalledWith(
        expect.objectContaining({ lead_id: id, tipo: 'nota', detalle: expect.stringContaining('Retomar en Q4') }),
      ),
    )
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
    expect(toast.error).not.toHaveBeenCalledWith(expect.stringContaining('se restauró el estado anterior'))
  })

  // Un fetch COLGADO no rechaza nunca: sin el reloj de LIMITE_CARGA_REAL_MS el
  // asesor se quedaba para siempre en «Preparando tu información…».
  it('carga inicial COLGADA → estado accionable de error (no un spinner eterno)', async () => {
    vi.useFakeTimers()
    try {
      // Promesa que jamás se asienta: el peor caso (ni éxito ni fallo).
      listarLeads.mockImplementationOnce(() => new Promise(() => {}))
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
  // el asesor creía que gerencia no le fijó meta cuando sí lo hizo.
  it('metas que NO se pudieron leer se marcan como error, no como "sin meta"', async () => {
    listarObjetivosMock.mockRejectedValueOnce(new CrmApiError('metas caídas', 'POSTGREST_ERROR'))
    const { api, estado } = montar('vendedor')

    await waitFor(() => expect(estado().cargando).toBe(false))
    // El CRM entero NO cae por las metas (siguen siendo un fetch auxiliar)…
    expect(estado().error).toBe(false)
    // …pero el consumidor sabe que los ceros no son un dato.
    expect(api().objetivosError).toBe(true)
  })

  it('metas leídas OK (aunque estén vacías) NO son un error: el cero SÍ es el dato', async () => {
    listarObjetivosMock.mockResolvedValue([])
    const { api, estado } = montar('vendedor')

    await waitFor(() => expect(estado().cargando).toBe(false))
    expect(api().objetivosError).toBe(false)
  })

  it('tras un fallo de metas, recargar() limpia la marca cuando el servidor vuelve', async () => {
    listarObjetivosMock.mockRejectedValueOnce(new CrmApiError('metas caídas', 'POSTGREST_ERROR'))
    const { api, estado } = montar('supervisor')
    await waitFor(() => expect(api().objetivosError).toBe(true))

    listarObjetivosMock.mockResolvedValue([])
    await act(async () => {
      await api().recargar()
    })
    await waitFor(() => expect(api().objetivosError).toBe(false))
    expect(estado().error).toBe(false)
  })

  it('fallo de la carga inicial → estado.error (no pinta CRM vacío) y reintentar recupera', async () => {
    listarLeads.mockRejectedValueOnce(new CrmApiError('caída inicial', 'POSTGREST_ERROR'))
    const { api, estado } = montar('supervisor')
    await waitFor(() => expect(estado().error).toBe(true))
    expect(api().leads).toHaveLength(0)

    // El siguiente intento ya tiene el mock por defecto (1 lead).
    act(() => estado().reintentar())
    await waitFor(() => expect(estado().error).toBe(false))
    await waitFor(() => expect(api().leads).toHaveLength(1))
  })
})

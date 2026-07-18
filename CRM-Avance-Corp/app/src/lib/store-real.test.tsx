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
    insertarLead: vi.fn(),
    insertarTarea: vi.fn(),
    cerrarTarea: vi.fn(),
    actualizarLead: vi.fn(),
    insertarActividad: vi.fn(),
  }
})

const { StoreProvider } = await import('./store')
const { CrmApiError } = crmApi

const listarLeads = vi.mocked(crmApi.listarLeadsDelAmbito)
const listarEquipo = vi.mocked(crmApi.listarEquipo)
const listarActs = vi.mocked(crmApi.listarActividadesDelAmbito)
const insertarLead = vi.mocked(crmApi.insertarLead)
const actualizarLead = vi.mocked(crmApi.actualizarLead)
const insertarActividad = vi.mocked(crmApi.insertarActividad)
const listarTareas = vi.mocked(crmApi.listarTareasDelAmbito)
const insertarTarea = vi.mocked(crmApi.insertarTarea)
const cerrarTareaMock = vi.mocked(crmApi.cerrarTarea)

const ROSTER = [
  { perfil_id: 'u-ger', nombre_completo: 'Gerente Real', rol_crm: 'gerencia' as const, supervisor_id: null, activo: true },
  { perfil_id: 'u-v1', nombre_completo: 'Vendedor Real', rol_crm: 'vendedor' as const, supervisor_id: 'u-ger', activo: true },
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
  return {
    fase: 'listo',
    yo: { id: 'u-ger', nombre_completo: 'Gerente Real', rol, demo: false, puede_contratar: true },
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
    insertarLead.mockResolvedValue(undefined)
    listarTareas.mockResolvedValue([])
    insertarTarea.mockResolvedValue(undefined)
    cerrarTareaMock.mockResolvedValue({ siguiente_id: null })
    actualizarLead.mockResolvedValue(undefined)
    insertarActividad.mockResolvedValue(undefined)
  })
  afterEach(() => vi.clearAllMocks())

  it('carga el ámbito real y resuelve vendedor_nombre desde el roster', async () => {
    const { api } = montar('gerencia')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    expect(api().leads[0]?.vendedor_nombre).toBe('Vendedor Real')
  })

  it('el gate de acciones está ABIERTO: crearLead persiste y resincroniza', async () => {
    const { api, mutar } = montar('gerencia')
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
    await waitFor(() => expect(listarLeads).toHaveBeenCalled()) // resync
  })

  it('género y fecha de nacimiento llegan al INSERT (si no, el avatar nunca tiene silueta)', async () => {
    const { api, mutar } = montar('gerencia')
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
    const { api, mutar } = montar('gerencia')
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
    const { api, mutar } = montar('gerencia')
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
        creado_por: 'u-ger',
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

  it('crearTarea rechaza tipo inválido y lead fuera del ámbito, sin tocar la red', async () => {
    const { api, mutar } = montar('gerencia')
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
    const { api, mutar } = montar('gerencia')
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
      siguiente: { tipo: 'whatsapp', titulo: 'WhatsApp a CLIENTE', vence_en: '2026-07-19T15:00:00.000Z' },
    })
    // Optimista: la original cerrada, la siguiente pendiente, y el resultado ya en el timeline.
    expect(api().tareas.find((t) => t.id === tareaBase.id)?.estado).toBe('completada')
    expect(api().tareas.some((t) => t.titulo === 'WhatsApp a CLIENTE' && t.estado === 'pendiente')).toBe(true)
    expect(api().actividades.some((a2) => a2.tipo === 'llamada_no_contestada')).toBe(true)
  })

  it('editar capital real persiste monto y moneda juntos', async () => {
    const { api, mutar } = montar('gerencia')
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
    const { api, mutar } = montar('gerencia')
    await waitFor(() => expect(api().leads).toHaveLength(1))
    const id = api().leads[0]!.id
    const res = mutar((a) => a.convertir(id))
    expect(res.ok).toBe(false)
    expect(res.codigo).toBe('fuente_no_habilitada')
  })

  it('rechazo del servidor: rollback con mensaje HONESTO cuando el resync sí aplica', async () => {
    const { api, mutar } = montar('gerencia')
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
    const { api, mutar } = montar('gerencia')
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
    const { api, mutar } = montar('gerencia')
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
    const { api, mutar } = montar('gerencia')
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

  it('fallo de la carga inicial → estado.error (no pinta CRM vacío) y reintentar recupera', async () => {
    listarLeads.mockRejectedValueOnce(new CrmApiError('caída inicial', 'POSTGREST_ERROR'))
    const { api, estado } = montar('gerencia')
    await waitFor(() => expect(estado().error).toBe(true))
    expect(api().leads).toHaveLength(0)

    // El siguiente intento ya tiene el mock por defecto (1 lead).
    act(() => estado().reintentar())
    await waitFor(() => expect(estado().error).toBe(false))
    await waitFor(() => expect(api().leads).toHaveLength(1))
  })
})

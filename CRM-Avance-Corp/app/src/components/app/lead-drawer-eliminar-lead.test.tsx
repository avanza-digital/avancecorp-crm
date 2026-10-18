// «Eliminar lead (error de carga)» desde la ficha — quién ve el botón y qué pasa
// al confirmar. Lo que más vigila este archivo es que el botón NO aparezca donde
// no debe (analista, supervisor, coordinador, sesión demo) y que un rechazo del
// servidor (P0409 con sus razones) se lea tal cual sin cerrar nada.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { toast } from 'sonner'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import { PanelActionsContext, PanelStateContext, StoreDataContext } from '@/lib/store-context'
import type { PanelesActions, StoreDataApi } from '@/lib/store'
import type { Lead } from '@/lib/tipos'
import { CrmApiError } from '@/data/crm-api'
import { LeadDrawer } from './lead-drawer'

const { eliminarMock } = vi.hoisted(() => ({ eliminarMock: vi.fn() }))

// El transporte tiene su propia suite (MSW): aquí solo se sustituye la llamada.
vi.mock('@/data/crm-api', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/data/crm-api')>()),
  eliminarLeadErrorCarga: eliminarMock,
}))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() } }))
vi.mock('@/data/documento-lead', () => ({ useDocumentoLead: () => ({ data: undefined, isPending: false, isError: false }) }))
vi.mock('@/data/potencial-queries', () => ({
  usePotencialLead: () => ({ habilitada: false, item: undefined }),
  useMarcarPotencial: () => ({ marcar: vi.fn(), marcando: false }),
}))
vi.mock('@/data/cliente-existente-api', () => ({ buscarClienteExistente: vi.fn(), obtenerContextoClienteExistente: vi.fn(),
  cuentasClienteExistente: vi.fn(), datosLegalesClienteExistente: vi.fn(), contratosUpgradeClienteExistente: vi.fn() }))
vi.mock('@/data/crm-queries', () => ({
  useHistorialLead: () => ({ data: undefined, dataUpdatedAt: 0, hasNextPage: false, isFetchingNextPage: false,
    isPending: false, error: null, fetchNextPage: vi.fn(), refetch: vi.fn() }),
  usePoliticaRentabilidad: () => ({ data: undefined, isPending: true, isError: false }),
  useSolicitudesTasa: () => ({ data: [], isPending: true, isError: false }),
  useCierresEstado: () => ({ data: [] }),
  useConversionEstado: () => ({ data: undefined, isError: false }),
  useAnularCierreAvance: () => ({ mutateAsync: vi.fn() }),
  useConvertirLeadExterno: () => ({ mutateAsync: vi.fn() }),
  useCuentasBancariasCliente: () => ({ data: [], isPending: false, isError: false, isFetching: false, refetch: vi.fn() }),
}))
vi.mock('@/data/sla-operacion-queries', () => ({ useEstadosSlaV2: () => ({ data: { modo: 'legado', filas: [] }, error: null }) }))

const LEAD: Lead = {
  id: 'de667c0d-1111-4111-8111-111111111111', nombre_completo: 'MARGARITA PRUEBA', telefono: '+51987654321', correo: null,
  etapa: 'contactado', origen: 'oficina', monto_estimado: null, moneda: 'PEN', categoria_interes: null,
  vendedor_id: 'vendedor-1', vendedor_nombre: 'ANA TORRES', asignado_supervisor_id: null,
  creado_en: '2026-10-13T15:00:00.000Z', activo: true, dni: null, distrito: null, nota: null,
}
const TITULO = 'Eliminar lead (error de carga)'
const MOTIVO = 'Se cargó dos veces el mismo contacto'

function sesion(rol: string, rolPortal: string | null = null, demo = false): AuthContextValue {
  return {
    fase: 'listo',
    yo: {
      id: 'usuario-1', nombre_completo: 'QUIEN MIRA', rol, demo, puede_contratar: true,
      ...(rolPortal ? { rol_portal: rolPortal } : {}),
    },
    error: null,
    entrar: async () => ({ ok: true }),
    entrarDemo: () => undefined,
    reintentar: () => undefined,
    salir: async () => undefined,
  } as unknown as AuthContextValue
}

function montar({ rol = 'gerencia', rolPortal = 'directorio', demo = false, lead = {} }:
  { rol?: string; rolPortal?: string | null; demo?: boolean; lead?: Partial<Lead> } = {}) {
  const l: Lead = { ...LEAD, ...lead }
  const olvidarLeadEliminado = vi.fn(async () => true)
  const api = {
    lead: (id: string) => (id === l.id ? l : undefined), ambito: { leads: [l], vendedores: [], esGlobal: false },
    actividadesDe: () => [], tareasDe: () => [], crearTarea: vi.fn(), anularTarea: vi.fn(), editarLead: vi.fn(),
    reasignar: vi.fn(), cambiarEtapa: vi.fn(), registrarActividad: vi.fn(), anularCierreAvance: vi.fn(), reabrir: vi.fn(),
    cierresEstado: [], recargar: vi.fn(async () => true), olvidarLeadEliminado,
  } as unknown as StoreDataApi
  const actions: PanelesActions = { abrirLead: vi.fn(), abrirNuevoLead: vi.fn(), cerrarPaneles: vi.fn() }
  render(
    <AuthContext.Provider value={sesion(rol, rolPortal, demo)}>
      <StoreDataContext.Provider value={api}>
        <PanelStateContext.Provider value={{ leadAbiertoId: l.id, nuevoLeadAbierto: false, etapaInicial: 'nuevo', telefonoInicial: null }}>
          <PanelActionsContext.Provider value={actions}><LeadDrawer /></PanelActionsContext.Provider>
        </PanelStateContext.Provider>
      </StoreDataContext.Provider>
    </AuthContext.Provider>,
  )
  return { olvidarLeadEliminado }
}

const boton = () => screen.queryByRole('button', { name: /Eliminar lead \(error de carga\)/ })

async function abrirYLlenar(motivo = MOTIVO) {
  const usuario = userEvent.setup()
  await usuario.click(boton()!)
  const dialogo = await screen.findByRole('dialog', { name: TITULO })
  await usuario.type(within(dialogo).getByLabelText('Motivo de la eliminación'), motivo)
  await usuario.type(within(dialogo).getByLabelText(/Escribe ELIMINAR para confirmar/), 'ELIMINAR')
  return { usuario, dialogo }
}

beforeEach(() => {
  vi.clearAllMocks()
  eliminarMock.mockResolvedValue({ copiaId: '77777777-7777-4777-8777-777777777777', filas: { lead: 1 } })
})

describe('quién ve el botón', () => {
  it.each([
    ['gerencia del CRM', 'gerencia', 'directorio'],
    ['admin del portal', 'directorio', 'admin'],
    ['superadmin del portal', 'vendedor', 'superadmin'],
  ])('%s lo ve', (_, rol, rolPortal) => {
    montar({ rol, rolPortal })
    expect(boton()).not.toBeNull()
  })

  // Un caso por rol: con un bucle, el primero que fallara escondería a los demás.
  it.each([
    ['vendedor', 'analista'],
    ['supervisor', 'comercial'],
    ['coordinador', 'comercial'],
    ['directorio', 'directorio'],
  ])('un %s no lo ve, aunque vea la ficha', (rol, rolPortal) => {
    montar({ rol, rolPortal })
    expect(screen.getByRole('heading', { name: LEAD.nombre_completo })).toBeInTheDocument()
    expect(boton()).toBeNull()
  })

  it('en una sesión demo no aparece, ni siquiera para gerencia', () => {
    // Sin analista: la tasa en demo monta otra consulta que este archivo no prueba.
    montar({ demo: true, lead: { vendedor_id: null, vendedor_nombre: null } })
    expect(screen.getByRole('heading', { name: LEAD.nombre_completo })).toBeInTheDocument()
    expect(boton()).toBeNull()
  })

  it('también aparece en un lead descartado: si se puede borrar lo decide el servidor', () => {
    montar({ lead: { etapa: 'descartado', motivo_descarte: 'sin_interes' } })
    expect(boton()).not.toBeNull()
  })
})

describe('el diálogo', () => {
  it('explica qué se borra y que queda una copia, sin siglas', async () => {
    montar()
    await userEvent.setup().click(boton()!)
    const dialogo = await screen.findByRole('dialog', { name: TITULO })
    expect(dialogo).toHaveTextContent(/sus tareas, sus actividades y su historial de asignación/)
    expect(dialogo).toHaveTextContent(/copia de auditoría/)
    expect(dialogo).not.toHaveTextContent(/SLA/)
    expect(within(dialogo).getByLabelText('Motivo de la eliminación')).toHaveFocus()
  })

  it('no deja confirmar con un motivo de menos de 10 caracteres', async () => {
    montar()
    const { dialogo } = await abrirYLlenar('  corto   ')
    expect(within(dialogo).getByRole('button', { name: 'Eliminar lead' })).toBeDisabled()
    expect(within(dialogo).getByText(/5 de 500 caracteres · mínimo 10/)).toBeInTheDocument()
    expect(eliminarMock).not.toHaveBeenCalled()
  })

  it('flujo feliz: manda el motivo recortado, avisa y olvida el lead (que cierra su ficha)', async () => {
    const { olvidarLeadEliminado } = montar()
    const { usuario, dialogo } = await abrirYLlenar(`   ${MOTIVO}   `)
    await usuario.click(within(dialogo).getByRole('button', { name: 'Eliminar lead' }))

    expect(eliminarMock).toHaveBeenCalledExactlyOnceWith(LEAD.id, MOTIVO)
    expect(olvidarLeadEliminado).toHaveBeenCalledExactlyOnceWith(LEAD.id)
    expect(toast.success).toHaveBeenCalledWith('Lead eliminado. Quedó una copia de auditoría.')
    expect(screen.queryByRole('dialog', { name: TITULO })).not.toBeInTheDocument()
  })

  it('un rechazo P0409 muestra el texto del servidor tal cual y no cierra ni olvida nada', async () => {
    const razones = 'No se puede eliminar este lead: tiene un contrato enlazado; se creó hace más de 30 días (01/09/2026).'
    eliminarMock.mockRejectedValueOnce(new CrmApiError(razones, 'CONFLICTO'))
    const { olvidarLeadEliminado } = montar()
    const { usuario, dialogo } = await abrirYLlenar()
    await usuario.click(within(dialogo).getByRole('button', { name: 'Eliminar lead' }))

    expect(await within(dialogo).findByRole('alert')).toHaveTextContent(razones)
    expect(screen.getByRole('dialog', { name: TITULO })).toBeInTheDocument()
    expect(olvidarLeadEliminado).not.toHaveBeenCalled()
    expect(toast.success).not.toHaveBeenCalled()
    // Se puede reintentar: el botón vuelve a estar disponible.
    expect(within(dialogo).getByRole('button', { name: 'Eliminar lead' })).toBeEnabled()
  })
})

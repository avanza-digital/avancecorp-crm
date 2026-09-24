import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { toast } from 'sonner'
import {
  CrmApiError,
  guardarRecordatorioDisponibilidad,
  tomarLeadLibre,
  verificarDisponibilidadLead,
} from '@/data/crm-api'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import {
  PanelActionsContext,
  PanelStateContext,
  StoreDataContext,
} from '@/lib/store-context'
import type { PanelesActions, StoreDataApi } from '@/lib/store'
import { validarCamposLead } from '@/lib/validacion'
import type { Miembro } from '@/lib/tipos'
import { LeadNuevo } from './lead-nuevo'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return {
    ...actual,
    verificarDisponibilidadLead: vi.fn(),
    tomarLeadLibre: vi.fn(),
    guardarRecordatorioDisponibilidad: vi.fn(),
  }
})

// Venta cruzada: el buscador de clientes de otra cartera se prueba en su propio archivo;
// aquí solo importa CON QUÉ criterio se abre y si ofrece registrar.
vi.mock('./venta-cruzada', () => ({
  VentaCruzada: (p: { inicial?: unknown; puedeRegistrar: boolean }) =>
    <p data-testid="venta-cruzada">{JSON.stringify(p.inicial)}|{String(p.puedeRegistrar)}</p>,
}))

const verificarDisponibilidad = vi.mocked(verificarDisponibilidadLead)
const tomarLead = vi.mocked(tomarLeadLibre)
const guardarRecordatorio = vi.mocked(guardarRecordatorioDisponibilidad)

const SESION: AuthContextValue = {
  fase: 'listo',
  yo: {
    id: 'vendedor-1',
    nombre_completo: 'ANALISTA PRUEBA',
    rol: 'vendedor',
    demo: true,
    puede_contratar: true,
  },
  error: null,
  entrar: async () => ({ ok: true }),
  entrarDemo: () => undefined,
  reintentar: () => undefined,
  salir: async () => undefined,
}

function montar({
  demo = true,
  rol,
  crearLeadImpl,
  telefonoInicial = null,
  vendedores = [],
}: {
  demo?: boolean
  /** Rol del actor; por defecto el analista de SESION. Para las reglas de origen. */
  rol?: 'vendedor' | 'supervisor' | 'gerencia'
  crearLeadImpl?: StoreDataApi['crearLead']
  /** El atajo del buscador (plan «lead libre», F1) llega con teléfono. */
  telefonoInicial?: string | null
  vendedores?: Miembro[]
} = {}) {
  const implementacionPorDefecto: StoreDataApi['crearLead'] = (input) => {
    const validacion = validarCamposLead({
      monto_estimado: input.monto_estimado,
      moneda: input.moneda,
    })
    return validacion.ok
      ? { ok: true, id: 'lead-nuevo-1', persistido: Promise.resolve({ ok: true }) }
      : validacion
  }
  const crearLead = vi.fn<StoreDataApi['crearLead']>(crearLeadImpl ?? implementacionPorDefecto)
  // F2 «Tomar»: el flujo ganador resincroniza el ámbito ANTES de abrir la ficha.
  const recargar = vi.fn<StoreDataApi['recargar']>().mockResolvedValue(true)
  const api = {
    ambito: { leads: [], vendedores, esGlobal: false },
    crearLead,
    recargar,
  } as unknown as StoreDataApi
  const actions: PanelesActions = {
    abrirLead: vi.fn(),
    abrirNuevoLead: vi.fn(),
    cerrarPaneles: vi.fn(),
  }
  // F3 (Codex R4c/R6): el refresco de la campana se asevera sobre el MISMO
  // cliente que ve el componente — un mutante sin invalidateQueries muere aquí.
  const clienteConsultas = new QueryClient()
  const invalidar = vi.spyOn(clienteConsultas, 'invalidateQueries')

  const resultado = render(
    <QueryClientProvider client={clienteConsultas}>
      <AuthContext.Provider value={{
        ...SESION,
        yo: SESION.yo ? { ...SESION.yo, demo, ...(rol ? { rol } : {}) } : null,
      }}>
        <StoreDataContext.Provider value={api}>
          <PanelStateContext.Provider
            value={{ leadAbiertoId: null, nuevoLeadAbierto: true, etapaInicial: 'nuevo', telefonoInicial }}
          >
            <PanelActionsContext.Provider value={actions}>
              <LeadNuevo />
            </PanelActionsContext.Provider>
          </PanelStateContext.Provider>
        </StoreDataContext.Provider>
      </AuthContext.Provider>
    </QueryClientProvider>,
  )

  return { crearLead, recargar, actions, invalidar, desmontar: resultado.unmount }
}

function completarBaseReal(origen = 'referido') {
  fireEvent.change(screen.getByLabelText('Nombre completo *'), {
    target: { value: 'ANA NUEVO LEAD' },
  })
  fireEvent.change(screen.getByLabelText('Teléfono *'), {
    target: { value: '987654321' },
  })
  // El analista de esta sesión declara SU referido — la regla especial de ese
  // origen se conserva aunque LANDING y FORMULARIO ya estén habilitados.
  fireEvent.change(screen.getByLabelText('Origen *'), { target: { value: origen } })
  fireEvent.change(screen.getByLabelText('Capital estimado *'), { target: { value: '5000' } })
}

function diferida<T>() {
  let resolver!: (valor: T) => void
  let rechazar!: (motivo: unknown) => void
  const promesa = new Promise<T>((resolve, reject) => {
    resolver = resolve
    rechazar = reject
  })
  return { promesa, resolver, rechazar }
}

beforeEach(() => {
  vi.clearAllMocks()
  verificarDisponibilidad.mockResolvedValue({ estado: 'libre' })
})

afterEach(() => {
  vi.useRealTimers()
})

async function completarBase(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByLabelText('Nombre completo *'), 'ANA NUEVO LEAD')
  await user.type(screen.getByLabelText('Teléfono *'), '987654321')
  await user.selectOptions(screen.getByLabelText('Origen *'), 'referido')
}

describe('LeadNuevo — responsable comercial del supervisor', () => {
  it.each([true, false])('crea un lead propio sin analistas a cargo (demo=%s)', async (demo) => {
    const { crearLead, actions } = montar({ rol: 'supervisor', demo })
    const responsable = screen.getByRole('combobox', { name: 'Responsable comercial' })
    expect(responsable).toHaveValue('')
    expect(screen.getByRole('option', { name: 'Yo — lead propio' })).toHaveValue(SESION.yo!.id)
    expect(screen.queryByRole('option', { name: 'Referido' })).not.toBeInTheDocument()
    completarBaseReal('oficina')
    fireEvent.change(responsable, { target: { value: SESION.yo!.id } })
    fireEvent.click(screen.getByRole('button', { name: 'Crear lead' }))
    await waitFor(() => expect(crearLead).toHaveBeenCalledWith(expect.objectContaining({
      vendedor_id: SESION.yo!.id, origen: 'oficina',
    })))
    await waitFor(() => expect(actions.abrirLead).toHaveBeenCalledWith('lead-nuevo-1'))
  })

  it.each(['analista-equipo', ''])('conserva el destino %s después de elegir un lead propio', async (destino) => {
    const miembro = { perfil_id: 'analista-equipo', nombre_completo: 'ANALISTA EQUIPO', rol_crm: 'vendedor', activo: true, supervisor_id: SESION.yo!.id } satisfies Miembro
    const { crearLead } = montar({ rol: 'supervisor', vendedores: [
      miembro,
      { ...miembro, perfil_id: 'inactivo', nombre_completo: 'INACTIVO', activo: false },
      { ...miembro, perfil_id: 'otro-supervisor', nombre_completo: 'OTRO SUPERVISOR', rol_crm: 'supervisor' },
    ] })
    const responsable = screen.getByRole('combobox', { name: 'Responsable comercial' })
    expect(screen.queryByRole('option', { name: 'INACTIVO' })).not.toBeInTheDocument()
    expect(screen.queryByRole('option', { name: 'OTRO SUPERVISOR' })).not.toBeInTheDocument()
    completarBaseReal('otro')
    fireEvent.change(responsable, { target: { value: SESION.yo!.id } })
    fireEvent.change(responsable, { target: { value: destino } })
    fireEvent.click(screen.getByRole('button', { name: 'Crear lead' }))
    await waitFor(() => expect(crearLead).toHaveBeenCalledWith(expect.objectContaining({
      vendedor_id: destino || null,
    })))
  })

  it.each(['vendedor', 'gerencia'] as const)('no ofrece la nueva opción al rol %s', (rol) => {
    montar({ rol })
    expect(screen.queryByRole('option', { name: 'Yo — lead propio' })).not.toBeInTheDocument()
  })
})

describe('LeadNuevo — segundo número', () => {
  it('el segundo número viaja en el alta y admite un FIJO', async () => {
    const user = userEvent.setup()
    const { crearLead } = montar()
    await completarBase(user)
    await user.type(screen.getByLabelText('Teléfono alternativo'), '014457890')
    await user.type(screen.getByLabelText('Capital estimado *'), '5000')

    await user.click(screen.getByRole('button', { name: 'Crear lead' }))

    expect(crearLead).toHaveBeenCalledWith(
      expect.objectContaining({ telefono_alternativo: '014457890' }),
    )
  })

  it('sin segundo número el alta sigue funcionando (el caso mayoritario)', async () => {
    // El 84,2 % de las filas del origen no trae segundo número: este es el caso
    // normal, no la excepción.
    const user = userEvent.setup()
    const { crearLead } = montar()
    await completarBase(user)
    await user.type(screen.getByLabelText('Capital estimado *'), '5000')

    await user.click(screen.getByRole('button', { name: 'Crear lead' }))

    expect(crearLead).toHaveBeenCalledWith(
      expect.objectContaining({ telefono_alternativo: null }),
    )
  })
})

describe('LeadNuevo — capital obligatorio', () => {
  it('bloquea capital vacío y cero antes de crear', async () => {
    const user = userEvent.setup()
    const { crearLead } = montar()
    await completarBase(user)

    await user.click(screen.getByRole('button', { name: 'Crear lead' }))
    expect(screen.getByRole('alert')).toHaveTextContent('Ingresa un capital estimado mayor que 0')
    expect(crearLead).not.toHaveBeenCalled()

    await user.type(screen.getByLabelText('Capital estimado *'), '0')
    await user.click(screen.getByRole('button', { name: 'Crear lead' }))
    expect(crearLead).not.toHaveBeenCalled()
  })

  it.each(['0.001', '5000.999', '10000000000'])(
    'muestra el rechazo del contrato compartido para %s',
    async (monto) => {
      const user = userEvent.setup()
      const { crearLead } = montar()
      await completarBase(user)
      await user.type(screen.getByLabelText('Capital estimado *'), monto)

      await user.click(screen.getByRole('button', { name: 'Crear lead' }))

      expect(crearLead).toHaveBeenCalledTimes(1)
      expect(screen.getByRole('alert')).toHaveTextContent(/capital estimado/i)
    },
  )

  it('crea en USD conservando monto y moneda', async () => {
    const user = userEvent.setup()
    const { crearLead, actions } = montar()
    await completarBase(user)
    await user.type(screen.getByLabelText('Capital estimado *'), '5000')
    await user.selectOptions(screen.getByLabelText('Moneda'), 'USD')

    await user.click(screen.getByRole('button', { name: 'Crear lead' }))

    expect(crearLead).toHaveBeenCalledWith(
      expect.objectContaining({ monto_estimado: 5000, moneda: 'USD' }),
    )
    expect(actions.abrirLead).toHaveBeenCalledWith('lead-nuevo-1')
  })
})

describe('LeadNuevo — género y fecha de nacimiento', () => {
  it('los envía al store; sin elegirlos el alta sigue funcionando (van null)', async () => {
    const user = userEvent.setup()
    const { crearLead } = montar()
    await completarBase(user)
    await user.type(screen.getByLabelText('Capital estimado *'), '5000')

    // Primero SIN tocarlos: son opcionales, el lead nace igual y sin silueta.
    await user.click(screen.getByRole('button', { name: 'Crear lead' }))
    expect(crearLead).toHaveBeenCalledWith(
      expect.objectContaining({ genero: null, fecha_nacimiento: null }),
    )
  })

  it('elegir género y fecha los propaga tal cual', async () => {
    const user = userEvent.setup()
    const { crearLead } = montar()
    await completarBase(user)
    await user.type(screen.getByLabelText('Capital estimado *'), '5000')
    await user.selectOptions(screen.getByLabelText('Género'), 'F')
    await user.type(screen.getByLabelText('Fecha de nacimiento'), '1990-05-20')

    await user.click(screen.getByRole('button', { name: 'Crear lead' }))

    expect(crearLead).toHaveBeenCalledWith(
      expect.objectContaining({ genero: 'F', fecha_nacimiento: '1990-05-20' }),
    )
  })

  it('un menor de edad se frena en el formulario, sin viajar al store', async () => {
    const user = userEvent.setup()
    const { crearLead } = montar()
    await completarBase(user)
    await user.type(screen.getByLabelText('Capital estimado *'), '5000')
    await user.type(screen.getByLabelText('Fecha de nacimiento'), '2020-01-01')

    await user.click(screen.getByRole('button', { name: 'Crear lead' }))

    expect(screen.getByRole('alert')).toHaveTextContent(/al menos 18 años/i)
    expect(crearLead).not.toHaveBeenCalled()
  })
})

describe('LeadNuevo — disponibilidad P-048', () => {
  it('consulta el teléfono al perder foco después de 400 ms, no antes', async () => {
    vi.useFakeTimers()
    montar({ demo: false })
    const telefono = screen.getByLabelText('Teléfono *')

    fireEvent.change(telefono, { target: { value: '+51 987 654 321' } })
    fireEvent.blur(telefono)
    await act(async () => { await vi.advanceTimersByTimeAsync(399) })
    expect(verificarDisponibilidad).not.toHaveBeenCalled()

    await act(async () => { await vi.advanceTimersByTimeAsync(1) })
    expect(verificarDisponibilidad).toHaveBeenCalledWith(
      '+51 987 654 321',
      null,
      expect.anything(),
    )
  })

  it('consulta nuevamente cuando el DNI llega a 8 dígitos', async () => {
    vi.useFakeTimers()
    montar({ demo: false })
    fireEvent.change(screen.getByLabelText('Teléfono *'), { target: { value: '987654321' } })
    const dni = screen.getByLabelText('DNI')

    fireEvent.change(dni, { target: { value: '1234567' } })
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })
    expect(verificarDisponibilidad).not.toHaveBeenCalled()

    fireEvent.change(dni, { target: { value: '12345678' } })
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })
    expect(verificarDisponibilidad).toHaveBeenCalledWith(
      '987654321',
      '12345678',
      expect.anything(),
    )
  })

  it('ignora una respuesta antigua que llega después de la consulta vigente', async () => {
    vi.useFakeTimers()
    const primera = diferida<Awaited<ReturnType<typeof verificarDisponibilidadLead>>>()
    const segunda = diferida<Awaited<ReturnType<typeof verificarDisponibilidadLead>>>()
    verificarDisponibilidad
      .mockReturnValueOnce(primera.promesa)
      .mockReturnValueOnce(segunda.promesa)
    montar({ demo: false })
    const telefono = screen.getByLabelText('Teléfono *')

    fireEvent.change(telefono, { target: { value: '987654321' } })
    fireEvent.blur(telefono)
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })

    fireEvent.change(telefono, { target: { value: '976543210' } })
    fireEvent.blur(telefono)
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })

    await act(async () => { segunda.resolver({ estado: 'libre' }) })
    await act(async () => {
      primera.resolver({ estado: 'tomado', vendedor: 'OTRO ANALISTA', tenencia_desde: null })
    })

    expect(screen.queryByText(/OTRO ANALISTA/)).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Crear lead' })).toBeEnabled()
  })

  it('un estado de negocio bloquea el alta y explica el motivo', async () => {
    vi.useFakeTimers()
    verificarDisponibilidad.mockResolvedValue({ estado: 'en_bolsa' })
    const { crearLead } = montar({ demo: false })
    const telefono = screen.getByLabelText('Teléfono *')

    fireEvent.change(telefono, { target: { value: '987654321' } })
    fireEvent.blur(telefono)
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })

    expect(screen.getByRole('alert')).toHaveTextContent(/bolsa de leads/i)
    expect(screen.getByRole('button', { name: 'Crear lead' })).toBeDisabled()
    expect(crearLead).not.toHaveBeenCalled()
  })

  it('una caída de red deja continuar y el submit revalida sin debounce', async () => {
    verificarDisponibilidad.mockRejectedValue(new CrmApiError(
      'No se pudo contactar el servicio de disponibilidad.',
      'DISPONIBILIDAD_RED',
    ))
    const { crearLead, actions } = montar({ demo: false })
    completarBaseReal()

    fireEvent.click(screen.getByRole('button', { name: 'Crear lead' }))

    expect(verificarDisponibilidad).toHaveBeenCalledTimes(1)
    expect(crearLead).not.toHaveBeenCalled()
    await waitFor(() => expect(crearLead).toHaveBeenCalledTimes(1))
    expect(screen.getByRole('status')).toHaveTextContent(/puedes continuar/i)
    expect(actions.abrirLead).toHaveBeenCalledWith('lead-nuevo-1')
  })

  it.each([
    'DISPONIBILIDAD_CONTRACT',
    'DISPONIBILIDAD_NO_DISPONIBLE',
    'POSTGREST_ERROR',
    'REGLA_SERVIDOR',
    'SIN_PERMISO',
    'SUPABASE_NOT_CONFIGURED',
  ])('un fallo estructural %s bloquea el alta', async (codigo) => {
    verificarDisponibilidad.mockRejectedValue(new CrmApiError('detalle interno', codigo))
    const { crearLead } = montar({ demo: false })
    completarBaseReal()

    fireEvent.click(screen.getByRole('button', { name: 'Crear lead' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      codigo === 'SIN_PERMISO' ? /no tienes permiso/i : /no está habilitada/i,
    )
    expect(screen.queryByText('detalle interno')).not.toBeInTheDocument()
    expect(crearLead).not.toHaveBeenCalled()
    expect(screen.getByRole('button', { name: 'Crear lead' })).toBeDisabled()
  })

  it('un TypeError inesperado fuera del transporte tipado bloquea por defecto', async () => {
    verificarDisponibilidad.mockRejectedValue(new TypeError('bug local'))
    const { crearLead } = montar({ demo: false })
    completarBaseReal()

    fireEvent.click(screen.getByRole('button', { name: 'Crear lead' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(/no está habilitada/i)
    expect(crearLead).not.toHaveBeenCalled()
  })

  it('espera la revalidación inmediata antes de invocar crearLead', async () => {
    const user = userEvent.setup()
    const veredicto = diferida<Awaited<ReturnType<typeof verificarDisponibilidadLead>>>()
    verificarDisponibilidad.mockReturnValueOnce(veredicto.promesa)
    const { crearLead } = montar({ demo: false })
    completarBaseReal()

    fireEvent.click(screen.getByRole('button', { name: 'Crear lead' }))
    expect(verificarDisponibilidad).toHaveBeenCalledTimes(1)
    expect(crearLead).not.toHaveBeenCalled()
    const nombre = screen.getByLabelText('Nombre completo *')
    expect(nombre).toBeDisabled()
    await user.type(nombre, ' CAMBIADO DURANTE EL ENVÍO')
    expect(nombre).toHaveValue('ANA NUEVO LEAD')

    await act(async () => { veredicto.resolver({ estado: 'libre' }) })
    await waitFor(() => expect(crearLead).toHaveBeenCalledTimes(1))
    expect(crearLead).toHaveBeenCalledWith(
      expect.objectContaining({ nombre_completo: 'ANA NUEVO LEAD' }),
    )
  })

  it('bloquea si el contacto deja de estar libre en la revalidación final', async () => {
    verificarDisponibilidad.mockResolvedValueOnce({ estado: 'en_bolsa' })
    const { crearLead } = montar({ demo: false })
    completarBaseReal()

    fireEvent.click(screen.getByRole('button', { name: 'Crear lead' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(/bolsa de leads/i)
    expect(crearLead).not.toHaveBeenCalled()
    expect(screen.getByRole('button', { name: 'Crear lead' })).toBeDisabled()
  })

  it('un timeout del precheck también falla abierto y permite guardar', async () => {
    vi.useFakeTimers()
    verificarDisponibilidad.mockImplementation((_telefono, _dni, signal) =>
      new Promise((_resolve, reject) => {
        signal?.addEventListener('abort', () => {
          reject(new DOMException('Timeout', 'AbortError'))
        }, { once: true })
      }),
    )
    const { crearLead } = montar({ demo: false })
    completarBaseReal()

    fireEvent.click(screen.getByRole('button', { name: 'Crear lead' }))
    expect(crearLead).not.toHaveBeenCalled()

    await act(async () => { await vi.advanceTimersByTimeAsync(5_000) })

    expect(crearLead).toHaveBeenCalledTimes(1)
    expect(screen.getByRole('status')).toHaveTextContent(/puedes continuar/i)
  })

  it('si el precheck fue libre pero la RPC bloquea, conserva el formulario y no anuncia éxito', async () => {
    const mensaje = 'Este contacto ya está asignado a otro analista.'
    const { actions } = montar({
      demo: false,
      crearLeadImpl: () => ({
        ok: true,
        id: 'lead-optimista',
        persistido: Promise.resolve({
          ok: false,
          error: mensaje,
          codigo: 'CONTACTO_NO_DISPONIBLE',
        }),
      }),
    })
    completarBaseReal()

    fireEvent.click(screen.getByRole('button', { name: 'Crear lead' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(mensaje)
    expect(actions.abrirLead).not.toHaveBeenCalled()
    expect(screen.getByLabelText('Nombre completo *')).toHaveValue('ANA NUEVO LEAD')
    expect(screen.getByLabelText('Teléfono *')).toHaveValue('987654321')
    expect(toast.success).not.toHaveBeenCalled()
  })

  it('no permite cerrar el modal mientras el INSERT está pendiente', async () => {
    const confirmacion = diferida<{ ok: boolean }>()
    const { actions } = montar({
      demo: false,
      crearLeadImpl: () => ({
        ok: true,
        id: 'lead-pendiente',
        persistido: confirmacion.promesa,
      }),
    })
    completarBaseReal()

    fireEvent.click(screen.getByRole('button', { name: 'Crear lead' }))
    await waitFor(() => expect(screen.getByRole('button', { name: 'Cancelar' })).toBeDisabled())

    fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }))
    fireEvent.keyDown(screen.getByRole('dialog'), { key: 'Escape', code: 'Escape' })
    expect(actions.cerrarPaneles).not.toHaveBeenCalled()

    await act(async () => { confirmacion.resolver({ ok: true }) })
    await waitFor(() => expect(actions.abrirLead).toHaveBeenCalledWith('lead-pendiente'))
  })

  it('en demo no consulta Supabase', async () => {
    const user = userEvent.setup()
    montar()
    await completarBase(user)
    await user.type(screen.getByLabelText('Capital estimado *'), '5000')
    await user.click(screen.getByRole('button', { name: 'Crear lead' }))

    expect(verificarDisponibilidad).not.toHaveBeenCalled()
  })
})

describe('LeadNuevo — orígenes del alta manual (2026-09-01)', () => {
  // LANDING y FORMULARIO también pueden declararse a mano. Referido conserva
  // su regla propia: solo lo declara el analista, a su nombre.
  it('el analista ve todos los orígenes activos', () => {
    montar()
    const opciones = [...screen.getByLabelText('Origen *').querySelectorAll('option')]
      .map((opcion) => opcion.value)
      .filter((valor) => valor !== '')
    expect(opciones).toEqual(['referido', 'landing', 'formulario', 'oficina', 'otro'])
  })

  it('un supervisor ve LANDING y FORMULARIO, pero no Referido', () => {
    montar({ rol: 'supervisor' })
    const opciones = [...screen.getByLabelText('Origen *').querySelectorAll('option')]
      .map((opcion) => opcion.value)
      .filter((valor) => valor !== '')
    expect(opciones).toEqual(['landing', 'formulario', 'oficina', 'otro'])
  })

  it('gerencia ve LANDING y FORMULARIO, pero tampoco Referido', () => {
    montar({ rol: 'gerencia' })
    const opciones = [...screen.getByLabelText('Origen *').querySelectorAll('option')]
      .map((opcion) => opcion.value)
      .filter((valor) => valor !== '')
    expect(opciones).toEqual(['landing', 'formulario', 'oficina', 'otro'])
  })

  it.each(['landing', 'formulario'] as const)(
    'envía el origen manual %s al crear el lead',
    async (origen) => {
      const user = userEvent.setup()
      const { crearLead } = montar()
      await user.type(screen.getByLabelText('Nombre completo *'), 'ANA NUEVO LEAD')
      await user.type(screen.getByLabelText('Teléfono *'), '987654321')
      await user.selectOptions(screen.getByLabelText('Origen *'), origen)
      await user.type(screen.getByLabelText('Capital estimado *'), '5000')

      await user.click(screen.getByRole('button', { name: 'Crear lead' }))

      expect(crearLead).toHaveBeenCalledWith(expect.objectContaining({ origen }))
    },
  )
})

// ── Fase 1 del plan «lead libre» (2026-08-16): la tarjeta §5.2 y el atajo ────
describe('LeadNuevo — tarjeta de disponibilidad', () => {
  it('un «tomado» enriquecido pinta la tarjeta: analista, última conversación y fecha', async () => {
    vi.useFakeTimers()
    verificarDisponibilidad.mockResolvedValue({
      estado: 'tomado',
      vendedor: 'ANA PÉREZ',
      tenencia_desde: '2026-08-03T16:00:00Z',
      ultima_conversacion_en: '2026-08-10T05:00:00Z',
      fecha_estimada: '2026-08-30T05:00:00Z',
    })
    montar({ demo: false })
    const telefono = screen.getByLabelText('Teléfono *')

    fireEvent.change(telefono, { target: { value: '987654321' } })
    fireEvent.blur(telefono)
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })

    expect(screen.getByText('Seguimiento activo')).toBeInTheDocument()
    expect(screen.getByText('Última conversación')).toBeInTheDocument()
    expect(screen.getByText('10 de agosto de 2026')).toBeInTheDocument()
    expect(screen.getByText('Revisable desde (estimado)')).toBeInTheDocument()
    // El alta sigue bloqueada: la tarjeta informa, no desbloquea.
    expect(screen.getByRole('button', { name: 'Crear lead' })).toBeDisabled()
  })

  it('el «tomado» de HOY (sin claves nuevas) también pinta tarjeta — sin líneas inventadas', async () => {
    vi.useFakeTimers()
    verificarDisponibilidad.mockResolvedValue({
      estado: 'tomado',
      vendedor: 'ANA PÉREZ',
      tenencia_desde: null,
    })
    montar({ demo: false })
    const telefono = screen.getByLabelText('Teléfono *')

    fireEvent.change(telefono, { target: { value: '987654321' } })
    fireEvent.blur(telefono)
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })

    expect(screen.getByText('Seguimiento activo')).toBeInTheDocument()
    expect(screen.getByText('Analista')).toBeInTheDocument()
    expect(screen.queryByText('Última conversación')).not.toBeInTheDocument()
    expect(screen.queryByText('Revisable desde (estimado)')).not.toBeInTheDocument()
  })

  it('con teléfono precargado (atajo del buscador) el precheck se dispara SOLO', async () => {
    vi.useFakeTimers()
    verificarDisponibilidad.mockResolvedValue({
      estado: 'tomado',
      vendedor: 'ANA PÉREZ',
      tenencia_desde: null,
    })
    montar({ demo: false, telefonoInicial: '987 654 321' })

    expect(screen.getByLabelText('Teléfono *')).toHaveValue('987 654 321')
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })

    // Sin blur ni tecleo: el montaje con teléfono ya verificó.
    expect(verificarDisponibilidad).toHaveBeenCalledWith('987 654 321', null, expect.anything())
    expect(screen.getByText('Seguimiento activo')).toBeInTheDocument()
  })
})

// ── Honestidad sin celular (2026-08-17, hallazgo de Miguel en la prueba visual):
// con un DNI tecleado el precheck no corría y CALLABA — el analista leía ese
// silencio como «libre». Mutante que debe morir aquí: restaurar el return mudo
// de programarDisponibilidad cuando el teléfono no normaliza. ─────────────────
describe('LeadNuevo — honestidad sin celular', () => {
  it('un DNI precargado como teléfono (atajo del buscador) avisa y NO consulta', async () => {
    vi.useFakeTimers()
    montar({ demo: false, telefonoInicial: '46736918' })

    await act(async () => { await vi.advanceTimersByTimeAsync(400) })

    expect(verificarDisponibilidad).not.toHaveBeenCalled()
    expect(screen.getByRole('status')).toHaveTextContent(/se comprueba con el CELULAR/i)
  })

  it('DNI completo con teléfono vacío: avisa en vez de callar, sin llamar a la RPC', async () => {
    vi.useFakeTimers()
    montar({ demo: false })

    fireEvent.change(screen.getByLabelText('DNI'), { target: { value: '46736918' } })
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })

    expect(verificarDisponibilidad).not.toHaveBeenCalled()
    expect(screen.getByRole('status')).toHaveTextContent(/se comprueba con el CELULAR/i)
  })

  it('sin teléfono y sin DNI el silencio es legítimo: no hay nada que verificar', async () => {
    vi.useFakeTimers()
    montar({ demo: false })

    fireEvent.blur(screen.getByLabelText('Teléfono *'))
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })

    expect(verificarDisponibilidad).not.toHaveBeenCalled()
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
  })

  it('al corregir a un celular válido, el aviso da paso a la verificación real', async () => {
    vi.useFakeTimers()
    montar({ demo: false, telefonoInicial: '46736918' })
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })
    expect(screen.getByRole('status')).toHaveTextContent(/se comprueba con el CELULAR/i)

    const telefono = screen.getByLabelText('Teléfono *')
    fireEvent.change(telefono, { target: { value: '987654321' } })
    fireEvent.blur(telefono)
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })

    expect(verificarDisponibilidad).toHaveBeenCalledWith('987654321', null, expect.anything())
  })

  it('en demo no avisa ni consulta: el mundo demo no verifica', async () => {
    vi.useFakeTimers()
    montar({ telefonoInicial: '46736918' })

    await act(async () => { await vi.advanceTimersByTimeAsync(400) })

    expect(verificarDisponibilidad).not.toHaveBeenCalled()
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
  })
})

// ── F2 «Tomar lead e iniciar seguimiento» (spec §5.6/§5.7) ───────────────────
// Mutantes que deben morir aquí: quitar can('tomarLeadDirecto') del botón
// (aparecería a supervisión), abrir la ficha SIN resincronizar antes (la ficha
// leería un store que aún no ve el lead) y presentar la carrera como error.
describe('LeadNuevo — Tomar lead (F2)', () => {
  const REUTILIZABLE = {
    estado: 'reutilizable',
    motivo_descarte: 'no_responde',
    descartado_en: '2026-08-01T15:00:00+00:00',
    quedo_libre_en: '2026-08-08T15:00:00+00:00',
    descartado_por: null,
    ultima_conversacion_en: null,
  } as const

  async function precheckCon(
    veredicto: Awaited<ReturnType<typeof verificarDisponibilidadLead>>,
    opciones: Parameters<typeof montar>[0] & { dni?: string } = {},
  ) {
    const { dni, ...montaje } = opciones
    vi.useFakeTimers()
    verificarDisponibilidad.mockResolvedValue(veredicto)
    const arnes = montar({ demo: false, ...montaje })
    // El DNI se teclea ANTES del precheck (flujo real): editarlo DESPUÉS
    // invalida el veredicto a propósito y retira el botón.
    if (dni) fireEvent.change(screen.getByLabelText('DNI'), { target: { value: dni } })
    const telefono = screen.getByLabelText('Teléfono *')
    fireEvent.change(telefono, { target: { value: '987654321' } })
    fireEvent.blur(telefono)
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })
    vi.useRealTimers()
    return arnes
  }

  it('analista + en_bolsa: el botón existe y el alta sigue bloqueada', async () => {
    await precheckCon({ estado: 'en_bolsa' })

    expect(screen.getByRole('button', { name: /Tomar lead e iniciar seguimiento/ })).toBeEnabled()
    expect(screen.getByRole('button', { name: 'Crear lead' })).toBeDisabled()
  })

  it('analista + reutilizable: el botón existe junto a la tarjeta de la historia', async () => {
    await precheckCon(REUTILIZABLE)

    expect(screen.getByRole('button', { name: /Tomar lead e iniciar seguimiento/ })).toBeEnabled()
    expect(screen.getByText('Seguimiento anterior disponible')).toBeInTheDocument()
    // El mensaje de F1 murió: ya no se promete una toma «no habilitada».
    expect(screen.getByRole('alert')).not.toHaveTextContent(/no está habilitada/i)
  })

  it('supervisor y gerencia NO ven el botón: su puerta es el reparto', async () => {
    await precheckCon({ estado: 'en_bolsa' }, { rol: 'supervisor' })
    expect(screen.queryByRole('button', { name: /Tomar lead/ })).not.toBeInTheDocument()

    cleanup()
    await precheckCon({ estado: 'en_bolsa' }, { rol: 'gerencia' })
    expect(screen.queryByRole('button', { name: /Tomar lead/ })).not.toBeInTheDocument()
  })

  it('un seguimiento activo ajeno jamás ofrece el botón', async () => {
    await precheckCon({ estado: 'tomado', vendedor: 'ANA PÉREZ', tenencia_desde: null })
    expect(screen.queryByRole('button', { name: /Tomar lead/ })).not.toBeInTheDocument()
  })

  it('GANADOR: toma por contacto, resincroniza ANTES de abrir la ficha y confirma', async () => {
    const { recargar, actions } = await precheckCon(REUTILIZABLE, { dni: '12345678' })
    // La resincronización se difiere DE VERDAD (lección RETOMAR-41: un mock
    // que resuelve síncrono no distingue «invocado antes» de «ESPERADO
    // antes»): mientras recargar no resuelva, la ficha NO puede abrirse.
    const resync = diferida<boolean>()
    recargar.mockReturnValue(resync.promesa)
    tomarLead.mockResolvedValue({
      estado: 'tomado_ok',
      lead_id: 'e5b8f1c0-4d3a-4f6b-9c2d-8a7e6f5d4c3b',
      modo: 'reutilizable',
      etapa: 'nuevo',
      ciclo_actual: 2,
      tenencia_desde: '2026-08-17T21:10:00+00:00',
    })

    fireEvent.click(screen.getByRole('button', { name: /Tomar lead e iniciar seguimiento/ }))

    await waitFor(() => expect(recargar).toHaveBeenCalledTimes(1))
    expect(tomarLead).toHaveBeenCalledWith('987654321', '12345678')
    // El ámbito aún no ve el lead: abrir la ficha aquí sería abrirla vacía.
    expect(actions.abrirLead).not.toHaveBeenCalled()

    await act(async () => { resync.resolver(true) })

    await waitFor(() => expect(actions.abrirLead).toHaveBeenCalledWith('e5b8f1c0-4d3a-4f6b-9c2d-8a7e6f5d4c3b'))
    expect(toast.success).toHaveBeenCalled()
  })

  it('PERDEDOR (§5.7): el veredicto fresco avisa del cambio y el botón se retira', async () => {
    const { actions } = await precheckCon({ estado: 'en_bolsa' })
    tomarLead.mockResolvedValue({ estado: 'tomado', vendedor: 'ANA PÉREZ', tenencia_desde: null })

    fireEvent.click(screen.getByRole('button', { name: /Tomar lead e iniciar seguimiento/ }))

    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent(
      'La disponibilidad acaba de cambiar. Este contacto ya está asignado a ANA PÉREZ.',
    ))
    expect(actions.abrirLead).not.toHaveBeenCalled()
    expect(screen.queryByRole('button', { name: /Tomar lead/ })).not.toBeInTheDocument()
    // a11y F2-M2: el foco no queda huérfano en body al retirarse el botón.
    await waitFor(() => expect(screen.getByLabelText('Teléfono *')).toHaveFocus())
  })

  it('si el blanco desapareció y volvió «libre», el alta se DESBLOQUEA y se ANUNCIA', async () => {
    await precheckCon(REUTILIZABLE)
    tomarLead.mockResolvedValue({ estado: 'libre' })

    fireEvent.click(screen.getByRole('button', { name: /Tomar lead e iniciar seguimiento/ }))

    await waitFor(() =>
      expect(screen.queryByRole('button', { name: /Tomar lead/ })).not.toBeInTheDocument(),
    )
    // Retirar «Tomar» y terminar de validar el alta son renders distintos.
    // Esperar el estado operable, no un fotograma intermedio de la transición.
    await waitFor(() => expect(screen.getByRole('button', { name: 'Crear lead' })).toBeEnabled())
    // a11y F2-M1: era el único desenlace mudo (todo se desvanecía en
    // silencio) — sonner tiene aria-live, el cambio se anuncia.
    expect(toast.info).toHaveBeenCalled()
    // a11y F2-M2: el botón retirado tenía el foco — se rescata al teléfono.
    await waitFor(() => expect(screen.getByLabelText('Teléfono *')).toHaveFocus())
  })

  it('un error real se DICE bajo el botón sin pisar el veredicto, y se puede reintentar', async () => {
    const { actions } = await precheckCon(REUTILIZABLE)
    tomarLead.mockRejectedValueOnce(new CrmApiError('Sin conexión con el servidor.', 'RED'))

    fireEvent.click(screen.getByRole('button', { name: /Tomar lead e iniciar seguimiento/ }))

    expect(await screen.findByText('Sin conexión con el servidor.')).toBeInTheDocument()
    // El veredicto (tarjeta) sigue en pantalla y el botón sigue vivo.
    expect(screen.getByText('Seguimiento anterior disponible')).toBeInTheDocument()
    const boton = screen.getByRole('button', { name: /Tomar lead e iniciar seguimiento/ })
    expect(boton).toBeEnabled()
    expect(actions.abrirLead).not.toHaveBeenCalled()

    tomarLead.mockResolvedValue({
      estado: 'tomado_ok',
      lead_id: 'e5b8f1c0-4d3a-4f6b-9c2d-8a7e6f5d4c3b',
      modo: 'reutilizable',
      etapa: 'nuevo',
      ciclo_actual: 2,
      tenencia_desde: '2026-08-17T21:10:00+00:00',
    })
    fireEvent.click(boton)
    await waitFor(() => expect(actions.abrirLead).toHaveBeenCalled())
  })

  it('en DEMO el botón no existe: la toma es del mundo real', async () => {
    // En demo el precheck ni corre — el estado tomable jamás se alcanza.
    vi.useFakeTimers()
    montar({ demo: true })
    const telefono = screen.getByLabelText('Teléfono *')
    fireEvent.change(telefono, { target: { value: '987654321' } })
    fireEvent.blur(telefono)
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })
    vi.useRealTimers()

    expect(verificarDisponibilidad).not.toHaveBeenCalled()
    expect(screen.queryByRole('button', { name: /Tomar lead/ })).not.toBeInTheDocument()
  })
})

// Las 3 refutaciones de Codex sobre el flujo (auditoría F2, 2026-08-17).
// Mutantes que deben morir: quitar `|| tomando` del fieldset o de Cancelar;
// ignorar el booleano de recargar() y abrir la ficha igual.
describe('LeadNuevo — la toma en vuelo se blinda (Codex R2/R3/R5)', () => {
  const REUTILIZABLE = {
    estado: 'reutilizable',
    motivo_descarte: 'no_responde',
    descartado_en: '2026-08-01T15:00:00+00:00',
    quedo_libre_en: '2026-08-08T15:00:00+00:00',
    descartado_por: null,
    ultima_conversacion_en: null,
  } as const

  const TOMADO_OK = {
    estado: 'tomado_ok',
    lead_id: 'e5b8f1c0-4d3a-4f6b-9c2d-8a7e6f5d4c3b',
    modo: 'reutilizable',
    etapa: 'nuevo',
    ciclo_actual: 2,
    tenencia_desde: '2026-08-17T21:10:00+00:00',
  } as const

  async function precheckReutilizable() {
    vi.useFakeTimers()
    verificarDisponibilidad.mockResolvedValue(REUTILIZABLE)
    const arnes = montar({ demo: false })
    const telefono = screen.getByLabelText('Teléfono *')
    fireEvent.change(telefono, { target: { value: '987654321' } })
    fireEvent.blur(telefono)
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })
    vi.useRealTimers()
    return arnes
  }

  it('R2+R3: con la RPC viajando, el contacto NO se puede editar ni cancelar el modal', async () => {
    await precheckReutilizable()
    const respuesta = diferida<typeof TOMADO_OK>()
    tomarLead.mockReturnValue(respuesta.promesa as never)

    fireEvent.click(screen.getByRole('button', { name: /Tomar lead e iniciar seguimiento/ }))

    // Editar teléfono/DNI aquí presentaría el veredicto de A como si fuera
    // de B; cancelar descartaría en silencio una toma que el servidor puede
    // COMPROMETER. Ambos mueren mientras la toma viaja.
    expect(screen.getByLabelText('Teléfono *')).toBeDisabled()
    expect(screen.getByLabelText('DNI')).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Cancelar' })).toBeDisabled()

    await act(async () => { respuesta.resolver(TOMADO_OK) })
    // Resuelta la toma, el formulario vuelve a la vida (aquí ganó y se abre).
    await waitFor(() => expect(screen.getByLabelText('Teléfono *')).toBeEnabled())
  })

  it('R5: si la resincronización falla, la toma real se DICE y jamás se abre una ficha vacía', async () => {
    const { recargar, actions } = await precheckReutilizable()
    recargar.mockResolvedValue(false)
    tomarLead.mockResolvedValue(TOMADO_OK)

    fireEvent.click(screen.getByRole('button', { name: /Tomar lead e iniciar seguimiento/ }))

    await waitFor(() => expect(toast.warning).toHaveBeenCalled())
    // La toma ES real: el éxito se confirma…
    expect(toast.success).toHaveBeenCalled()
    // …pero la ficha no se abre sobre un store que no ve el lead; el modal
    // se cierra para que el flujo termine limpio.
    expect(actions.abrirLead).not.toHaveBeenCalled()
    expect(actions.cerrarPaneles).toHaveBeenCalled()
  })
})

// ── F3 «Recordarme revisar» (§5.3): la única acción sobre un ocupado ─────────
// Mutantes que deben morir: ofrecer el form en un tomable (Tomar y Recordar
// son disjuntos), guardar sin las 09:00 de Lima, y mostrarlo a supervisión.
describe('LeadNuevo — Recordarme revisar (F3)', () => {
  const AHORA = Date.parse('2026-08-18T17:00:00Z')

  // El fixture de enfriamiento se libera el 10/09/2026. La fecha debe seguir
  // fija al devolver los temporizadores reales a waitFor: restaurar también
  // Date hacía caducar el fixture según el día de ejecución. El afterEach
  // general devuelve finalmente el reloj del sistema.
  function usarTemporizadoresSimulados() {
    vi.useRealTimers()
    vi.useFakeTimers()
    vi.setSystemTime(AHORA)
  }

  function usarTemporizadoresReales() {
    vi.useRealTimers()
    vi.setSystemTime(AHORA)
  }

  const TOMADO = { estado: 'tomado', vendedor: 'ANA PÉREZ', tenencia_desde: null } as const
  const ENFRIAMIENTO = {
    estado: 'enfriamiento',
    motivo_descarte: 'no_responde',
    disponible_desde: '2026-09-10T05:00:00Z',
    descartado_por: null,
  } as const

  async function precheckR(veredicto: Awaited<ReturnType<typeof verificarDisponibilidadLead>>, opciones: Parameters<typeof montar>[0] = {}) {
    usarTemporizadoresSimulados()
    verificarDisponibilidad.mockResolvedValue(veredicto)
    const arnes = montar({ demo: false, ...opciones })
    const telefono = screen.getByLabelText('Teléfono *')
    fireEvent.change(telefono, { target: { value: '987654321' } })
    fireEvent.blur(telefono)
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })
    usarTemporizadoresReales()
    return arnes
  }

  it('un seguimiento activo ajeno ofrece SOLO el recordatorio (sin botón Tomar)', async () => {
    await precheckR(TOMADO)
    expect(screen.getByRole('button', { name: /Recordarme revisar/ })).toBeEnabled()
    expect(screen.queryByRole('button', { name: /Tomar lead/ })).not.toBeInTheDocument()
  })

  it('enfriamiento sugiere el día real de liberación (la única regla con motor)', async () => {
    await precheckR(ENFRIAMIENTO)
    expect(screen.getByLabelText('Fecha del recordatorio')).toHaveValue('2026-09-10')
  })

  it('a11y M2: el mini-form es un grupo con título, ayuda y fecha nombrada', async () => {
    await precheckR(ENFRIAMIENTO)
    const grupo = screen.getByRole('group', { name: '¿Quieres que te lo recuerde?' })
    expect(grupo).toHaveAccessibleDescription(/Sin reservar nada/)
    expect(screen.getByLabelText('Fecha del recordatorio')).toBeInTheDocument()
  })

  it('R3 (Codex): la fecha se acota a mañana…hoy+364 en Lima — espejo del tope del servidor', async () => {
    usarTemporizadoresSimulados()
    verificarDisponibilidad.mockResolvedValue(TOMADO)
    montar({ demo: false })
    const telefono = screen.getByLabelText('Teléfono *')
    fireEvent.change(telefono, { target: { value: '987654321' } })
    fireEvent.blur(telefono)
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })
    usarTemporizadoresReales()

    const fecha = screen.getByLabelText('Fecha del recordatorio')
    expect(fecha).toHaveAttribute('min', '2026-08-19')
    expect(fecha).toHaveAttribute('max', '2027-08-17')
  })

  it('un tomable ofrece Tomar, JAMÁS el recordatorio (disjuntos a propósito)', async () => {
    await precheckR({ estado: 'en_bolsa' })
    expect(screen.getByRole('button', { name: /Tomar lead/ })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Recordarme revisar/ })).not.toBeInTheDocument()
  })

  it('supervisión no ve el recordatorio (es la antesala de la toma, del analista)', async () => {
    await precheckR(TOMADO, { rol: 'supervisor' })
    expect(screen.queryByRole('button', { name: /Recordarme revisar/ })).not.toBeInTheDocument()
  })

  it('GUARDA con autoría, teléfono, y las 09:00 de Lima; confirma y permite seguir', async () => {
    guardarRecordatorio.mockResolvedValue({
      id: 'r-nuevo',
      perfil_id: 'vendedor-1',
      telefono: '+51987654321',
      dni: null,
      recordar_en: '2026-09-10T14:00:00+00:00',
      creado_en: '2026-08-18T06:00:00+00:00',
    })
    await precheckR(ENFRIAMIENTO)

    const boton = screen.getByRole('button', { name: /Recordarme revisar/ })
    boton.focus()
    fireEvent.click(boton)

    await waitFor(() => expect(guardarRecordatorio).toHaveBeenCalledWith(
      'vendedor-1',
      '987654321',
      null,
      '2026-09-10T09:00:00-05:00',
    ))
    // a11y N2: la confirmación dicta la fecha LEGIBLE, no el YYYY-MM-DD crudo
    // (es-PE escribe «setiembre»).
    const confirmacion = await screen.findByText(/la campana te avisará el/)
    expect(confirmacion).toHaveTextContent('10 de setiembre')
    // a11y M1 + Codex R5: el toast nombra teléfono y fecha legibles — honesto
    // incluso si el formulario ya muestra OTRO contacto.
    expect(toast.success).toHaveBeenCalledWith(expect.stringContaining('987 654 321'))
    expect(toast.success).toHaveBeenCalledWith(expect.stringContaining('10 de setiembre'))
    // a11y A1: el botón pulsado desapareció con el intercambio — la
    // confirmación recibe el foco (la MISMA regresión pagada en F2).
    await waitFor(() => expect(confirmacion).toHaveFocus())
  })

  it('un rechazo del servidor se DICE anclado al mini-form y el foco vuelve al botón', async () => {
    guardarRecordatorio.mockRejectedValueOnce(
      new CrmApiError('La fecha de revisión debe ser futura', 'ERROR'),
    )
    await precheckR(TOMADO)

    const boton = screen.getByRole('button', { name: /Recordarme revisar/ })
    boton.focus()
    fireEvent.click(boton)
    // El navegador REAL suelta el foco de un botón deshabilitado. En jsdom
    // blur() sobre un disabled es NO-OP y body.focus() también (body no es
    // focusable sin tabindex) — el foco huérfano se simula así; si no, la
    // aserción del rescate pasaba con el rescate borrado (auditoría 18/08).
    act(() => {
      document.body.tabIndex = -1
      document.body.focus()
    })

    // a11y M3: inline junto al campo, no un toast fugaz.
    expect(await screen.findByText('La fecha de revisión debe ser futura')).toBeInTheDocument()
    expect(toast.error).not.toHaveBeenCalled()
    expect(screen.getByLabelText('Fecha del recordatorio')).toHaveAttribute('aria-invalid', 'true')
    expect(boton).toBeEnabled()
    // a11y A1 (rama de error): el foco no queda huérfano en body.
    await waitFor(() => expect(boton).toHaveFocus())
    // Editar la fecha retira el error: ya no habla de lo que hay en pantalla.
    fireEvent.change(screen.getByLabelText('Fecha del recordatorio'), {
      target: { value: '2026-12-01' },
    })
    expect(screen.queryByText('La fecha de revisión debe ser futura')).not.toBeInTheDocument()
  })

  it('F3.1: un blur del teléfono SIN editar conserva la confirmación y NO re-guarda', async () => {
    guardarRecordatorio.mockResolvedValue({
      id: 'r-nuevo',
      perfil_id: 'vendedor-1',
      telefono: '+51987654321',
      dni: null,
      recordar_en: '2026-09-10T14:00:00+00:00',
      creado_en: '2026-08-18T06:00:00+00:00',
    })
    await precheckR(ENFRIAMIENTO)

    fireEvent.click(screen.getByRole('button', { name: /Recordarme revisar/ }))
    await screen.findByText(/la campana te avisará el/)

    // El analista clica el teléfono para compararlo y sale SIN cambiar nada:
    // antes esto borraba la confirmación y el mini-form renacía «virgen»,
    // invitando a re-guardar (= reprogramar en silencio).
    usarTemporizadoresSimulados()
    const telefono = screen.getByLabelText('Teléfono *')
    fireEvent.blur(telefono)
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })
    usarTemporizadoresReales()

    expect(await screen.findByText(/la campana te avisará el/)).toHaveTextContent('10 de setiembre')
    expect(guardarRecordatorio).toHaveBeenCalledTimes(1)
  })

  it('F3.1: teclear el DNI no borra la fecha elegida (el recordatorio es del teléfono)', async () => {
    await precheckR(TOMADO)
    const fecha = screen.getByLabelText('Fecha del recordatorio')
    fireEvent.change(fecha, { target: { value: '2026-12-01' } })

    // Teclear el DNI invalida el veredicto (el mini-form se OCULTA hasta el
    // re-precheck del 8.º dígito) pero la fecha elegida debe SOBREVIVIR.
    usarTemporizadoresSimulados()
    fireEvent.change(screen.getByLabelText('DNI'), { target: { value: '1234567' } })
    fireEvent.change(screen.getByLabelText('DNI'), { target: { value: '12345678' } })
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })
    usarTemporizadoresReales()

    expect(screen.getByLabelText('Fecha del recordatorio')).toHaveValue('2026-12-01')
  })

  it('F3.1: cambiar el TELÉFONO sí resetea la fecha a la sugerida del contacto nuevo', async () => {
    usarTemporizadoresSimulados()
    verificarDisponibilidad.mockResolvedValue(TOMADO)
    montar({ demo: false })
    const telefono = screen.getByLabelText('Teléfono *')
    fireEvent.change(telefono, { target: { value: '987654321' } })
    fireEvent.blur(telefono)
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })

    fireEvent.change(screen.getByLabelText('Fecha del recordatorio'), {
      target: { value: '2026-12-01' },
    })
    fireEvent.change(telefono, { target: { value: '911111111' } })
    fireEvent.blur(telefono)
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })
    usarTemporizadoresReales()

    // Otro contacto = otro recordatorio: manda la sugerida (+7d de un tomado).
    expect(screen.getByLabelText('Fecha del recordatorio')).toHaveValue('2026-08-25')
  })

  it('F3.1: cerrar y reabrir el modal NO permite un segundo guardado del mismo contacto', async () => {
    const respuesta = diferida<Awaited<ReturnType<typeof guardarRecordatorioDisponibilidad>>>()
    guardarRecordatorio.mockReturnValue(respuesta.promesa)
    const { desmontar } = await precheckR(TOMADO)
    fireEvent.click(screen.getByRole('button', { name: /Recordarme revisar/ }))
    desmontar()

    // Segundo montaje con el guardado del primero AÚN en vuelo.
    await precheckR(TOMADO)
    fireEvent.click(screen.getByRole('button', { name: /Recordarme revisar/ }))

    expect(guardarRecordatorio).toHaveBeenCalledTimes(1)
    expect(await screen.findByText(/ya tiene un guardado en curso/)).toBeInTheDocument()

    // Aterrizado el primero, el contacto queda libre y se puede guardar.
    await act(async () => {
      respuesta.resolver({
        id: 'r-nuevo',
        perfil_id: 'vendedor-1',
        telefono: '+51987654321',
        dni: null,
        recordar_en: '2026-08-25T14:00:00+00:00',
        creado_en: '2026-08-18T06:00:00+00:00',
      })
    })
    fireEvent.click(screen.getByRole('button', { name: /Recordarme revisar/ }))
    await waitFor(() => expect(guardarRecordatorio).toHaveBeenCalledTimes(2))
  })

  it('F3.1: vaciar la fecha y pulsar NO guarda y lo DICE junto al campo', async () => {
    await precheckR(TOMADO)

    fireEvent.change(screen.getByLabelText('Fecha del recordatorio'), { target: { value: '' } })
    fireEvent.click(screen.getByRole('button', { name: /Recordarme revisar/ }))

    // El botón muerto en silencio era el hallazgo triple de la auditoría:
    // '' esquiva el ?? y el return temprano callaba.
    expect(await screen.findByText('Elige la fecha del recordatorio.')).toBeInTheDocument()
    expect(guardarRecordatorio).not.toHaveBeenCalled()

    // Teclear una fecha retira el aviso.
    fireEvent.change(screen.getByLabelText('Fecha del recordatorio'), {
      target: { value: '2026-12-01' },
    })
    expect(screen.queryByText('Elige la fecha del recordatorio.')).not.toBeInTheDocument()
  })

  it('F3.1: un ERROR con el modal ya cerrado se anuncia por toast nombrando al contacto', async () => {
    const respuesta = diferida<Awaited<ReturnType<typeof guardarRecordatorioDisponibilidad>>>()
    guardarRecordatorio.mockReturnValue(respuesta.promesa)
    const { desmontar } = await precheckR(TOMADO)

    fireEvent.click(screen.getByRole('button', { name: /Recordarme revisar/ }))
    desmontar()

    await act(async () => {
      respuesta.rechazar(new CrmApiError('La fecha de revisión debe ser futura', 'ERROR'))
    })

    // El fallo de un guardado real no puede evaporarse con el modal: el toast
    // vive fuera y NOMBRA al contacto afectado.
    expect(toast.error).toHaveBeenCalledWith(expect.stringContaining('987 654 321'))
    expect(toast.error).toHaveBeenCalledWith(expect.stringContaining('debe ser futura'))
  })

  it('F3.1: un ERROR tardío del contacto A no pinta error inline bajo el B', async () => {
    const respuesta = diferida<Awaited<ReturnType<typeof guardarRecordatorioDisponibilidad>>>()
    guardarRecordatorio.mockReturnValue(respuesta.promesa)
    await precheckR(TOMADO)

    fireEvent.click(screen.getByRole('button', { name: /Recordarme revisar/ }))
    // El analista cambia al contacto B con el guardado del A en vuelo.
    usarTemporizadoresSimulados()
    const telefono = screen.getByLabelText('Teléfono *')
    fireEvent.change(telefono, { target: { value: '911111111' } })
    fireEvent.blur(telefono)
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })
    usarTemporizadoresReales()

    await act(async () => {
      respuesta.rechazar(new CrmApiError('La fecha de revisión debe ser futura', 'ERROR'))
    })

    // Nada inline bajo B; el toast (global) nombra al A.
    expect(screen.queryByText(/debe ser futura/)).not.toBeInTheDocument()
    expect(toast.error).toHaveBeenCalledWith(expect.stringContaining('987 654 321'))
  })

  it('R4c (Codex): cerrar el modal con el guardado en vuelo NO deja la campana rancia', async () => {
    const respuesta = diferida<Awaited<ReturnType<typeof guardarRecordatorioDisponibilidad>>>()
    guardarRecordatorio.mockReturnValue(respuesta.promesa)
    const { invalidar, desmontar } = await precheckR(TOMADO)

    fireEvent.click(screen.getByRole('button', { name: /Recordarme revisar/ }))
    desmontar()

    await act(async () => {
      respuesta.resolver({
        id: 'r-nuevo',
        perfil_id: 'vendedor-1',
        telefono: '+51987654321',
        dni: null,
        recordar_en: '2026-08-25T14:00:00+00:00',
        creado_en: '2026-08-18T06:00:00+00:00',
      })
    })

    // El guardado FUE real aunque nadie lo mire: la campana se refresca y el
    // éxito se anuncia igual (sonner vive fuera del modal).
    expect(invalidar).toHaveBeenCalledWith({
      queryKey: ['crm', 'recordatorios-disponibilidad'],
    })
    expect(toast.success).toHaveBeenCalled()
  })

  it('R5 (Codex): la respuesta tardía del contacto A jamás pinta confirmación bajo el B', async () => {
    const respuesta = diferida<Awaited<ReturnType<typeof guardarRecordatorioDisponibilidad>>>()
    guardarRecordatorio.mockReturnValue(respuesta.promesa)
    const { invalidar } = await precheckR(TOMADO)

    fireEvent.click(screen.getByRole('button', { name: /Recordarme revisar/ }))

    // Con el guardado del A en vuelo, el analista cambia al contacto B y su
    // precheck llega a recordable: el mini-form vuelve FRESCO para B.
    usarTemporizadoresSimulados()
    const telefono = screen.getByLabelText('Teléfono *')
    fireEvent.change(telefono, { target: { value: '911111111' } })
    fireEvent.blur(telefono)
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })
    usarTemporizadoresReales()
    // El mini-form está FRESCO para B: deshabilitado mientras viaja el A,
    // pero SIN disfrazarse de su operación (label anclado al contacto, F3.1).
    const botonB = screen.getByRole('button', { name: /Recordarme revisar/ })
    expect(botonB).toBeDisabled()

    await act(async () => {
      respuesta.resolver({
        id: 'r-nuevo',
        perfil_id: 'vendedor-1',
        telefono: '+51987654321',
        dni: null,
        recordar_en: '2026-08-25T14:00:00+00:00',
        creado_en: '2026-08-18T06:00:00+00:00',
      })
    })

    // Nada de «guardado» bajo el contacto B…
    expect(screen.queryByText(/la campana te avisará el/)).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Recordarme revisar/ })).toBeInTheDocument()
    // …pero el guardado del A FUE real: campana refrescada y toast honesto
    // que NOMBRA al contacto A.
    expect(invalidar).toHaveBeenCalledWith({
      queryKey: ['crm', 'recordatorios-disponibilidad'],
    })
    expect(toast.success).toHaveBeenCalledWith(expect.stringContaining('987 654 321'))
  })
})

// ── Venta cruzada (2026-09-24): el contacto ya es cliente → en vez de un lead nuevo,
// se busca al cliente. Con el DNI escrito, esa búsqueda ya es la llave de su inversión. ──
describe('LeadNuevo — ya es cliente: buscarlo', () => {
  async function precheckCliente(opciones: Parameters<typeof montar>[0] = {}, dni?: string) {
    vi.useFakeTimers()
    verificarDisponibilidad.mockResolvedValue({ estado: 'ya_es_cliente', asesor: 'VC ANALISTA A' })
    montar({ demo: false, ...opciones })
    if (dni) fireEvent.change(screen.getByLabelText('DNI'), { target: { value: dni } })
    const telefono = screen.getByLabelText('Teléfono *')
    fireEvent.change(telefono, { target: { value: '987654321' } })
    fireEvent.blur(telefono)
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })
    vi.useRealTimers()
  }

  it('sin DNI busca por el teléfono y ofrece registrar a quien vende', async () => {
    await precheckCliente()
    expect(screen.getByText('Esta persona ya es cliente y está a cargo de VC ANALISTA A.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Crear lead' })).toBeDisabled()
    fireEvent.click(screen.getByRole('button', { name: 'Buscar a este cliente' }))
    expect(screen.getByTestId('venta-cruzada'))
      .toHaveTextContent(`${JSON.stringify({ tipo: 'telefono', telefono: '987654321' })}|true`)
  })

  it('con el DNI escrito busca por documento', async () => {
    await precheckCliente({}, '70000021')
    fireEvent.click(screen.getByRole('button', { name: 'Buscar a este cliente' }))
    expect(screen.getByTestId('venta-cruzada')).toHaveTextContent(
      JSON.stringify({ tipo: 'documento', tipoDocumento: 'DNI', numero: '70000021' }))
  })

  it('Gerencia lo ve, pero no registra la venta', async () => {
    await precheckCliente({ rol: 'gerencia' })
    fireEvent.click(screen.getByRole('button', { name: 'Buscar a este cliente' }))
    expect(screen.getByTestId('venta-cruzada')).toHaveTextContent(/\|false$/)
  })

  // En demo el precheck ni corre (el `!demo` del botón es cinturón, como el de «Tomar»).
  it('la sesión de demostración no busca clientes reales', async () => {
    vi.useFakeTimers()
    verificarDisponibilidad.mockResolvedValue({ estado: 'ya_es_cliente', asesor: 'VC ANALISTA A' })
    montar({ demo: true })
    const telefono = screen.getByLabelText('Teléfono *')
    fireEvent.change(telefono, { target: { value: '987654321' } })
    fireEvent.blur(telefono)
    await act(async () => { await vi.advanceTimersByTimeAsync(400) })
    vi.useRealTimers()
    expect(verificarDisponibilidad).not.toHaveBeenCalled()
    expect(screen.queryByRole('button', { name: 'Buscar a este cliente' })).not.toBeInTheDocument()
  })
})

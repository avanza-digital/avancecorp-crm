import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import userEvent from '@testing-library/user-event'
import { toast } from 'sonner'
import { CrmApiError, verificarDisponibilidadLead } from '@/data/crm-api'
import { AuthContext, type AuthContextValue } from '@/lib/auth-context'
import {
  PanelActionsContext,
  PanelStateContext,
  StoreDataContext,
} from '@/lib/store-context'
import type { PanelesActions, StoreDataApi } from '@/lib/store'
import { validarCamposLead } from '@/lib/validacion'
import { LeadNuevo } from './lead-nuevo'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return { ...actual, verificarDisponibilidadLead: vi.fn() }
})

const verificarDisponibilidad = vi.mocked(verificarDisponibilidadLead)

const SESION: AuthContextValue = {
  fase: 'listo',
  yo: {
    id: 'vendedor-1',
    nombre_completo: 'VENDEDOR PRUEBA',
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
}: {
  demo?: boolean
  /** Rol del actor; por defecto el vendedor de SESION. Para la regla D8. */
  rol?: 'vendedor' | 'supervisor' | 'gerencia'
  crearLeadImpl?: StoreDataApi['crearLead']
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
  const api = {
    ambito: { leads: [], vendedores: [], esGlobal: false },
    crearLead,
  } as unknown as StoreDataApi
  const actions: PanelesActions = {
    abrirLead: vi.fn(),
    abrirNuevoLead: vi.fn(),
    cerrarPaneles: vi.fn(),
  }

  render(
    <AuthContext.Provider value={{
      ...SESION,
      yo: SESION.yo ? { ...SESION.yo, demo, ...(rol ? { rol } : {}) } : null,
    }}>
      <StoreDataContext.Provider value={api}>
        <PanelStateContext.Provider
          value={{ leadAbiertoId: null, nuevoLeadAbierto: true, etapaInicial: 'nuevo' }}
        >
          <PanelActionsContext.Provider value={actions}>
            <LeadNuevo />
          </PanelActionsContext.Provider>
        </PanelStateContext.Provider>
      </StoreDataContext.Provider>
    </AuthContext.Provider>,
  )

  return { crearLead, actions }
}

function completarBaseReal() {
  fireEvent.change(screen.getByLabelText('Nombre completo *'), {
    target: { value: 'ANA NUEVO LEAD' },
  })
  fireEvent.change(screen.getByLabelText('Teléfono *'), {
    target: { value: '987654321' },
  })
  // D8 (2026-08-11): el alta manual ya no ofrece canales automáticos; el
  // vendedor de esta sesión declara SU referido — el flujo real de la regla.
  fireEvent.change(screen.getByLabelText('Origen *'), { target: { value: 'referido' } })
  fireEvent.change(screen.getByLabelText('Capital estimado *'), { target: { value: '5000' } })
}

function diferida<T>() {
  let resolver!: (valor: T) => void
  const promesa = new Promise<T>((resolve) => { resolver = resolve })
  return { promesa, resolver }
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
      primera.resolver({ estado: 'tomado', vendedor: 'OTRO VENDEDOR', tenencia_desde: null })
    })

    expect(screen.queryByText(/OTRO VENDEDOR/)).not.toBeInTheDocument()
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

describe('LeadNuevo — la regla D8 del origen (2026-08-11)', () => {
  // Espejo del 42501 del servidor (20260811210049): landing y formulario se
  // cargan solos por el puente; el alta manual no puede suplantarlos, y el
  // referido lo declara SOLO el vendedor. Si estas opciones reaparecieran en el
  // selector, el usuario elegiría algo que el servidor va a rechazar.
  it('el vendedor ve exactamente Referido, Wallking y Otro', () => {
    montar()
    const opciones = [...screen.getByLabelText('Origen *').querySelectorAll('option')]
      .map((opcion) => opcion.value)
      .filter((valor) => valor !== '')
    expect(opciones).toEqual(['referido', 'oficina', 'otro'])
  })

  it('un supervisor NO ve Referido (solo los vendedores, a su propio nombre)', () => {
    montar({ rol: 'supervisor' })
    const opciones = [...screen.getByLabelText('Origen *').querySelectorAll('option')]
      .map((opcion) => opcion.value)
      .filter((valor) => valor !== '')
    expect(opciones).toEqual(['oficina', 'otro'])
  })

  it('gerencia tampoco ve Referido', () => {
    montar({ rol: 'gerencia' })
    const opciones = [...screen.getByLabelText('Origen *').querySelectorAll('option')]
      .map((opcion) => opcion.value)
      .filter((valor) => valor !== '')
    expect(opciones).toEqual(['oficina', 'otro'])
  })
})

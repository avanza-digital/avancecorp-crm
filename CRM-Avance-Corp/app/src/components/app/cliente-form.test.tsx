// Tests del componente ClienteForm (alta en 2 pasos + corregir con ventana de
// 5 h). La capa @/data/crm-api se mockea (sin red); CrmApiError se conserva
// real para el instanceof del catch. Se monta dentro de <Dialog> porque el
// DialogTitle (Radix) exige el contexto del dialog — igual que en la pantalla —
// y dentro de un QueryClientProvider limpio por test porque la precarga de
// corregir va por useClienteDetalle (retry:false, espejo de lib/query-client:
// con el retry por defecto de TanStack el test de error reintentaría solo).
import { describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Dialog } from '@/components/ui/dialog'
import type { ClienteDetalle } from '@/lib/clientes-tipos'
import * as crmApi from '@/data/crm-api'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return {
    ...actual, // conserva CrmApiError real
    crearClientePortal: vi.fn(),
    actualizarClientePortal: vi.fn(),
    obtenerClienteDetalle: vi.fn(),
  }
})

const { ClienteForm } = await import('./cliente-form')
const { CrmApiError } = crmApi

const crearCliente = vi.mocked(crmApi.crearClientePortal)
const actualizarCliente = vi.mocked(crmApi.actualizarClientePortal)
const obtenerDetalle = vi.mocked(crmApi.obtenerClienteDetalle)

function detalleBase(over: Partial<ClienteDetalle> = {}): ClienteDetalle {
  return {
    id: 'cli-1',
    nombre_completo: 'PORTAL UNO CLIENTE',
    nombres: 'CLIENTE',
    apellidos: 'PORTAL UNO',
    tipo_documento: 'DNI',
    dni: '45781234',
    correo: 'cliente1@correo.pe',
    telefono: '+51999888777',
    asesor_perfil_id: 'yo',
    creado_por: 'yo',
    creado_en: new Date().toISOString(), // recién creado → ventana viva
    banco: 'BCP',
    tipo_cuenta: 'ahorros',
    numero_cuenta: '19112345678901',
    cci: '00219112345678901234',
    titular_distinto: false,
    beneficiario_nombre: null,
    beneficiario_dni: null,
    banco_usd: null,
    tipo_cuenta_usd: null,
    numero_cuenta_usd: null,
    cci_usd: null,
    titular_distinto_usd: false,
    beneficiario_nombre_usd: null,
    beneficiario_dni_usd: null,
    ...over,
  }
}

interface PropsParciales {
  modo?: 'crear' | 'corregir'
  clienteId?: string
}

function montar(props: PropsParciales = {}) {
  const onListo = vi.fn()
  const onCerrar = vi.fn()
  // QueryClient NUEVO por montaje: caché aislada entre tests (la precarga de
  // corregir usa la clave clienteDetalle(id) y no debe sobrevivir de un test a otro).
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  // exactOptionalPropertyTypes: clienteId solo se pasa cuando existe.
  render(
    <QueryClientProvider client={queryClient}>
      <Dialog open onClose={() => undefined}>
        {props.clienteId !== undefined
          ? (
              <ClienteForm
                modo={props.modo ?? 'corregir'}
                clienteId={props.clienteId}
                onListo={onListo}
                onCerrar={onCerrar}
              />
            )
          : <ClienteForm modo={props.modo ?? 'crear'} onListo={onListo} onCerrar={onCerrar} />}
      </Dialog>
    </QueryClientProvider>,
  )
  return { onListo, onCerrar }
}

/** Llena identidad + cuenta PEN completa (el mínimo del alta feliz). */
async function llenarAltaMinima(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByLabelText('Apellidos *'), 'diaz huayta')
  await user.type(screen.getByLabelText('Nombres *'), 'hugo gualberto')
  await user.type(screen.getByLabelText('Documento *'), '45781234')
  await user.type(screen.getByLabelText('Correo electrónico *'), 'hugo@correo.pe')
  const pen = screen.getByRole('group', { name: 'Cuenta bancaria en Soles (PEN)' })
  await user.selectOptions(within(pen).getByLabelText('Banco'), 'BCP')
  await user.selectOptions(within(pen).getByLabelText('Tipo de cuenta'), 'ahorros')
  await user.type(within(pen).getByLabelText('N° de cuenta'), '19112345678901')
  await user.type(within(pen).getByLabelText(/CCI/), '00219112345678901234')
}

describe('ClienteForm — modo crear (alta en 2 pasos)', () => {
  it('muestra el aviso de la clave temporal (espejo del portal)', () => {
    montar()
    expect(screen.getByText(/La clave temporal será el/)).toBeInTheDocument()
    expect(screen.getByText(/00AB1234/)).toBeInTheDocument()
  })

  it('alta feliz: UNA sola llamada con identidad + bancarios, y onListo(userId)', async () => {
    const user = userEvent.setup()
    crearCliente.mockResolvedValue({ userId: 'nuevo-1', emailEnviado: true })
    const { onListo } = montar()

    await llenarAltaMinima(user)
    await user.click(screen.getByRole('button', { name: /Crear cliente/ }))

    await waitFor(() => expect(onListo).toHaveBeenCalledWith('nuevo-1'))
    // La edge recibe la identidad normalizada (APELLIDOS primero) Y las cuentas
    // en el MISMO envío: el cliente nace con su cuenta o no nace.
    expect(crearCliente).toHaveBeenCalledWith({
      email: 'hugo@correo.pe',
      nombre_completo: 'DIAZ HUAYTA HUGO GUALBERTO',
      apellidos: 'DIAZ HUAYTA',
      nombres: 'HUGO GUALBERTO',
      dni: '45781234',
      telefono: null,
      tipo_documento: 'DNI',
      bancarios: {
        pen: expect.objectContaining({
          banco: 'BCP',
          tipo_cuenta: 'ahorros',
          numero_cuenta: '19112345678901',
          cci: '00219112345678901234',
          titular_distinto: false,
        }),
        usd: expect.objectContaining({ banco: '', cci: '', titular_distinto: false }),
      },
    })
    // Y NO queda ningún segundo paso que pueda fallar y dejar al cliente sin cuenta.
    expect(actualizarCliente).not.toHaveBeenCalled()
    expect(toast.success).toHaveBeenCalledWith('Cliente "DIAZ HUAYTA HUGO GUALBERTO" creado. Ahora crea su contrato.')
  })

  it('validación local: sin datos no toca el servidor y muestra el mensaje del portal', async () => {
    const user = userEvent.setup()
    montar()
    await user.click(screen.getByRole('button', { name: /Crear cliente/ }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Completa los apellidos y nombres del cliente.')
    expect(crearCliente).not.toHaveBeenCalled()
  })

  it('regla bancaria: identidad completa pero sin ninguna cuenta → error local', async () => {
    const user = userEvent.setup()
    montar()
    await user.type(screen.getByLabelText('Apellidos *'), 'qa')
    await user.type(screen.getByLabelText('Nombres *'), 'uno')
    await user.type(screen.getByLabelText('Documento *'), '45781234')
    await user.type(screen.getByLabelText('Correo electrónico *'), 'qa@correo.pe')
    await user.click(screen.getByRole('button', { name: /Crear cliente/ }))
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Registra al menos una cuenta bancaria (en soles o en dólares) para depositar al cliente.',
    )
    expect(crearCliente).not.toHaveBeenCalled()
  })

  it('si el servidor rechaza los bancarios NO queda cliente a medias: error y re-submit posible', async () => {
    // Sustituye a los dos casos viejos de "paso 2 fallido". Ese estado ya no
    // puede existir: la edge valida las cuentas ANTES de crear nada, así que el
    // rechazo llega como error normal y el asesor puede corregir y reintentar.
    const user = userEvent.setup()
    crearCliente.mockRejectedValue(
      new CrmApiError(
        'Registra al menos una cuenta bancaria (en soles o en dólares) para depositar al cliente.',
        'ALTA_CLIENTE_FALLIDA',
      ),
    )
    const { onListo } = montar()

    await llenarAltaMinima(user)
    await user.click(screen.getByRole('button', { name: /Crear cliente/ }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Registra al menos una cuenta bancaria (en soles o en dólares) para depositar al cliente.',
    )
    expect(onListo).not.toHaveBeenCalled() // NO se encadena al contrato
    expect(toast.success).not.toHaveBeenCalled()
    expect(actualizarCliente).not.toHaveBeenCalled()
    // Reintentable: el botón sigue ahí porque no se creó nada en el servidor.
    expect(screen.getByRole('button', { name: /Crear cliente/ })).toBeEnabled()
  })

  it('la edge rechaza (409 documento duplicado): muestra su mensaje tal cual', async () => {
    const user = userEvent.setup()
    crearCliente.mockRejectedValue(
      new CrmApiError('Este documento ya está registrado para otro cliente.', 'ALTA_CLIENTE_FALLIDA'),
    )
    const { onListo } = montar()

    await llenarAltaMinima(user)
    await user.click(screen.getByRole('button', { name: /Crear cliente/ }))

    expect(await screen.findByRole('alert'))
      .toHaveTextContent('Este documento ya está registrado para otro cliente.')
    expect(actualizarCliente).not.toHaveBeenCalled()
    expect(onListo).not.toHaveBeenCalled()
  })
})

describe('ClienteForm — modo corregir (ventana de 5 h)', () => {
  it('precarga TODO, bloquea el correo (cuenta de acceso) y guarda el patch completo', async () => {
    const user = userEvent.setup()
    obtenerDetalle.mockResolvedValue(detalleBase())
    actualizarCliente.mockResolvedValue(true)
    const { onListo } = montar({ modo: 'corregir', clienteId: 'cli-1' })

    const correo = await screen.findByLabelText('Correo electrónico *')
    expect(correo).toHaveValue('cliente1@correo.pe')
    expect(correo).toBeDisabled()
    expect(screen.getByText(/cuenta de acceso/)).toBeInTheDocument()
    expect(screen.getByLabelText('Apellidos *')).toHaveValue('PORTAL UNO')
    // Bancarios precargados (PEN del detalle).
    const pen = screen.getByRole('group', { name: 'Cuenta bancaria en Soles (PEN)' })
    expect(within(pen).getByLabelText('Banco')).toHaveValue('BCP')
    // Cuenta regresiva de la ventana (recién creado → vigente).
    expect(screen.getByText(/Ventana de corrección: Quedan/)).toBeInTheDocument()

    const tel = screen.getByLabelText('Teléfono')
    await user.clear(tel)
    await user.type(tel, '999111222')
    await user.click(screen.getByRole('button', { name: /Guardar corrección/ }))

    await waitFor(() => expect(onListo).toHaveBeenCalledWith('cli-1'))
    expect(actualizarCliente).toHaveBeenCalledTimes(1)
    const [id, patch] = actualizarCliente.mock.calls[0]!
    expect(id).toBe('cli-1')
    expect(patch).toMatchObject({
      nombre_completo: 'PORTAL UNO CLIENTE',
      tipo_documento: 'DNI',
      dni: '45781234', // sin tocar → grandfathering (pasa tal cual)
      telefono: '999111222',
      banco: 'BCP',
      cci: '00219112345678901234',
      banco_usd: null,
    })
    expect(toast.success).toHaveBeenCalledWith('Datos del cliente corregidos.')
  })

  it('ventana vencida (0 filas): mensaje honesto de NO guardado, sin onListo', async () => {
    const user = userEvent.setup()
    obtenerDetalle.mockResolvedValue(detalleBase())
    actualizarCliente.mockResolvedValue(false) // el servidor se quedó callado
    const { onListo } = montar({ modo: 'corregir', clienteId: 'cli-1' })

    await screen.findByLabelText('Apellidos *')
    await user.click(screen.getByRole('button', { name: /Guardar corrección/ }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'La ventana de corrección venció: los cambios NO se guardaron. Pide el cambio a administración.',
    )
    expect(onListo).not.toHaveBeenCalled()
    expect(toast.success).not.toHaveBeenCalled()
  })

  it('cliente LEGACY sin separar: muestra el nombre original y permite guardar sin apellidos/nombres', async () => {
    const user = userEvent.setup()
    obtenerDetalle.mockResolvedValue(
      detalleBase({ apellidos: null, nombres: null, nombre_completo: 'NOMBRE VIEJO JUNTO' }),
    )
    actualizarCliente.mockResolvedValue(true)
    montar({ modo: 'corregir', clienteId: 'cli-1' })

    expect(await screen.findByText(/Nombre registrado anteriormente:/)).toBeInTheDocument()
    expect(screen.getByText('NOMBRE VIEJO JUNTO')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /Guardar corrección/ }))

    await waitFor(() => expect(actualizarCliente).toHaveBeenCalledTimes(1))
    const [, patch] = actualizarCliente.mock.calls[0]!
    // Conserva su nombre original; apellidos/nombres viajan null (no se inventan).
    expect(patch).toMatchObject({ nombre_completo: 'NOMBRE VIEJO JUNTO', apellidos: null, nombres: null })
  })

  it('si el detalle no carga: error con Reintentar (y el reintento recarga)', async () => {
    const user = userEvent.setup()
    obtenerDetalle
      .mockRejectedValueOnce(new CrmApiError('No se pudo cargar el cliente.'))
      .mockResolvedValueOnce(detalleBase())
    montar({ modo: 'corregir', clienteId: 'cli-1' })

    expect(await screen.findByRole('alert')).toHaveTextContent('No se pudo cargar el cliente.')
    await user.click(screen.getByRole('button', { name: /Reintentar/ }))
    expect(await screen.findByLabelText('Apellidos *')).toHaveValue('PORTAL UNO')
    expect(obtenerDetalle).toHaveBeenCalledTimes(2)
  })
})
